class_name CityRules
extends RefCounted
## 城市规则（R3）：工作半径 / 人口指派 / 住房 / 区域产出与邻接 / 建城与建筑可建判定。
##
## 数值唯一权威 `data/gameConfig.json` 的 `city` / `spiritPeak` / `building` / `faction` 节；
## 全部静态、无状态、只读 config。1.0 蓝本：`CityRules` + `DistrictCalculator` + `PopulationCalculator`。
##
## 邻接（裁决三）：只按 `city.district.adjacency` 配置表匹配；`neighbor` 取值不在配置内的组合一律不生效。
## 首府区（`SHOU_FU_QU`）不参与邻接（它压在灵峰脚下）。


# ---------------------------------------------------------------------------
# 灵峰结构：洞府 / 建筑 / 区域
# ---------------------------------------------------------------------------

## 洞府座数（`openCave` 产物，以 `buildings` 中 `type == "CAVE"` 记录）。
static func cave_count(peak: SpiritPeak) -> int:
	return building_count(peak, "CAVE")


## 灵峰上某类建筑的座数。
static func building_count(peak: SpiritPeak, building_type: String) -> int:
	var count: int = 0
	for building_id: Variant in peak.buildings.keys():
		var entry: Dictionary = peak.buildings[building_id]
		if str(entry.get("type", "")) == building_type:
			count += 1
	return count


## 灵峰上全部建筑的等级总和（含洞府）。
static func building_levels(peak: SpiritPeak) -> int:
	var total: int = 0
	for building_id: Variant in peak.buildings.keys():
		total += int((peak.buildings[building_id] as Dictionary).get("level", 1))
	return total


## 已建成的玩家区域（不含灵峰自带的首府区）；住房与区域上限都按这个数。
static func built_districts(peak: SpiritPeak) -> Array[District]:
	var result: Array[District] = []
	for district: District in peak.districts:
		if district.type != Enums.DistrictType.SHOU_FU_QU:
			result.append(district)
	return result


static func find_district(peak: SpiritPeak, district_id: String) -> District:
	for district: District in peak.districts:
		if district.id == district_id:
			return district
	return null


# ---------------------------------------------------------------------------
# 住房 / 容量 / 工作半径
# ---------------------------------------------------------------------------

## 住房（PRD §4.7）：`6 + 峰级×2 + 洞府×1 + 区域×2 + 建筑×1`（王朝帝都额外 +10）
## 再加灵峰辐射内完好 `DONG_FU` 改良的住房（`improvement.dongFuHousing`）。
static func housing_of(state: GameState, config: Dictionary, peak: SpiritPeak) -> int:
	var city: Dictionary = config["city"]
	var housing: int = int(city["housingBase"]) + int(city["housingPerPeakLevel"]) * maxi(0, peak.level)
	var caves: int = cave_count(peak)
	housing += int(city["housingPerCave"]) * caves
	housing += int(city["housingPerDistrict"]) * built_districts(peak).size()
	housing += int(city["housingPerBuilding"]) * (peak.buildings.size() - caves)
	if building_count(peak, Enums.Building.WANG_CHAO_DI_DU) > 0:
		housing += int(config["faction"]["guoJia"]["diDuHousingBonus"])
	housing += ImprovementRules.housing_bonus(state, config, peak)
	return housing


## 弟子容量：`baseDiscipleCapacity + capacityPerLevel×(等级−1)`。
static func capacity_of(config: Dictionary, peak: SpiritPeak) -> int:
	var spirit_peak: Dictionary = config["spiritPeak"]
	return int(spirit_peak["baseDiscipleCapacity"]) + int(spirit_peak["capacityPerLevel"]) * maxi(0, peak.level - 1)


## 工作半径（`city.workRadius`，至少 1 格）。
static func work_radius(config: Dictionary) -> int:
	return maxi(1, int(config["city"]["workRadius"]))


# ---------------------------------------------------------------------------
# 工作格 / 人口指派
# ---------------------------------------------------------------------------

## 辐射半径内、本宗归属、非险地的可工作地块；按产出降序、id 升序（确定性）。
static func workable_tiles(state: GameState, config: Dictionary, sect: Sect, peak: SpiritPeak) -> Array[HexTile]:
	var result: Array[HexTile] = []
	if not state.tiles.has(peak.tileId):
		return result
	var center: HexTile = state.tiles[peak.tileId]
	var radius: int = work_radius(config)
	for tile: HexTile in state.tiles.values():
		if tile.danger or tile.ownerSectId != sect.id:
			continue
		if Hex.distance(Vector2i(tile.q, tile.r), Vector2i(center.q, center.r)) > radius:
			continue
		result.append(tile)
	result.sort_custom(func(a: HexTile, b: HexTile) -> bool:
		var yield_a: int = _yield_score(state, config, a)
		var yield_b: int = _yield_score(state, config, b)
		if yield_a != yield_b:
			return yield_a > yield_b
		return a.id < b.id)
	return result


## 可指派候选：辐射内、未被区域占用、且未被别峰耕种的格子。
static func assignable_tiles(state: GameState, config: Dictionary, sect: Sect, peak: SpiritPeak) -> Array[HexTile]:
	var result: Array[HexTile] = []
	for tile: HexTile in workable_tiles(state, config, sect, peak):
		if not tile.districtId.is_empty() and tile.id != peak.tileId:
			continue
		if not tile.workedByPeakId.is_empty() and tile.workedByPeakId != peak.id:
			continue
		result.append(tile)
	return result


## 指派一格：一格一份人力；被别峰占用则失败。
static func assign(state: GameState, config: Dictionary, peak: SpiritPeak, tile: HexTile) -> bool:
	if not tile.workedByPeakId.is_empty() and tile.workedByPeakId != peak.id:
		return false
	if tile.workedByPeakId.is_empty():
		tile.workedByPeakId = peak.id
	if not peak.workedTileIds.has(tile.id):
		peak.workedTileIds.append(tile.id)
	sync_free_workers(peak)
	return true


## 撤下指派：地块立刻停产，可由其他灵峰重新指派。
static func unassign(peak: SpiritPeak, tile: HexTile) -> void:
	peak.workedTileIds.erase(tile.id)
	if tile.workedByPeakId == peak.id:
		tile.workedByPeakId = ""
	sync_free_workers(peak)


## 空闲人口 = 人口 − 已耕作格数（下限 0）。
static func sync_free_workers(peak: SpiritPeak) -> void:
	peak.freeWorkers = maxi(0, peak.population - peak.workedTileIds.size())


## 人口自动上岗：清掉失效指派后，按产出从高到低补满空闲人口。
static func auto_assign(state: GameState, config: Dictionary, sect: Sect, peak: SpiritPeak) -> void:
	drop_invalid_assignments(state, config, sect, peak)
	var slots: int = peak.population - peak.workedTileIds.size()
	if slots <= 0:
		sync_free_workers(peak)
		return
	for tile: HexTile in workable_tiles(state, config, sect, peak):
		if slots <= 0:
			break
		if peak.workedTileIds.has(tile.id):
			continue
		if assign(state, config, peak, tile):
			slots -= 1
	sync_free_workers(peak)


## 地块易主 / 险地 / 被区域占用后，指派要跟着清掉。
static func drop_invalid_assignments(state: GameState, config: Dictionary, sect: Sect, peak: SpiritPeak) -> void:
	var invalid: Array[String] = []
	for tile_id: String in peak.workedTileIds:
		var tile: HexTile = state.tiles.get(tile_id)
		var bad: bool = tile == null or tile.ownerSectId != sect.id or tile.danger
		if not bad and not tile.districtId.is_empty() and tile.id != peak.tileId:
			bad = true
		if bad:
			invalid.append(tile_id)
			if tile != null and tile.workedByPeakId == peak.id:
				tile.workedByPeakId = ""
	for tile_id: String in invalid:
		peak.workedTileIds.erase(tile_id)


# ---------------------------------------------------------------------------
# 区域
# ---------------------------------------------------------------------------

## 新区域对象（id 由灵峰内同类型序号生成，确定性）。
static func new_district(peak: SpiritPeak, district_type: String, tile_id: String, name: String) -> District:
	var district: District = District.new()
	district.id = next_district_id(peak, district_type)
	district.name = name
	district.type = district_type
	district.typeName = str(Enums.DistrictType.NAMES.get(district_type, district_type))
	district.level = 1
	district.tileId = tile_id
	return district


static func next_district_id(peak: SpiritPeak, district_type: String) -> String:
	var count: int = 0
	for district: District in peak.districts:
		if district.type == district_type:
			count += 1
	return "district_%s_%s_%d" % [peak.id, district_type.to_lower(), count + 1]


## 区域产出 = 该类型基础产出（`city.district.yields`）+ 邻接加成；地块易主后停产。
static func district_yield(state: GameState, config: Dictionary, peak: SpiritPeak, district_type: String, tile_id: String) -> Dictionary:
	var result: Dictionary = EconomyRules.zero_yield()
	var tile: HexTile = state.tiles.get(tile_id)
	if tile == null or tile.ownerSectId != peak.sectId:
		return result
	var table: Dictionary = config["city"]["district"]["yields"]
	if table.has(district_type):
		EconomyRules.add_yield(result, table[district_type])
	EconomyRules.add_yield(result, _adjacency_detail(state, config, district_type, tile_id)["yield"])
	return result


## 邻接说明文案（裁决三：只按配置 `adjacency` 匹配，`description` 缺失时按配置值合成）。
static func district_adjacency(state: GameState, config: Dictionary, peak: SpiritPeak, district_type: String, tile_id: String) -> Array[String]:
	var reasons: Array[String] = []
	for reason: String in _adjacency_detail(state, config, district_type, tile_id)["reasons"]:
		reasons.append(reason)
	return reasons


static func district_stability(config: Dictionary, peak: SpiritPeak) -> int:
	var table: Dictionary = config["city"]["district"]["stabilityByType"]
	var total: int = 0
	for district: District in peak.districts:
		total += int(table.get(district.type, 0))
	return total


static func district_defense(config: Dictionary, peak: SpiritPeak) -> int:
	var table: Dictionary = config["city"]["district"]["defenseByType"]
	var total: int = 0
	for district: District in peak.districts:
		total += int(table.get(district.type, 0))
	return total


## 可建区域类型清单（供 `queryCityDetail.districtTypes`）。
static func district_type_ids() -> Array[String]:
	return Enums.DistrictType.BUILDABLE.duplicate()


# ---------------------------------------------------------------------------
# 建城 / 建区 / 建筑可建判定
# ---------------------------------------------------------------------------

## 开峰合法性：返回 blocker 文案，空串 = 可建（裁决四：山岳/非无主/弟子境界与位置等由本函数承载）。
static func can_found_peak(state: GameState, config: Dictionary, disciple: Disciple, tile: HexTile) -> String:
	if disciple == null:
		return "弟子不存在"
	var sect: Sect = _sect_of(state, disciple.sectId)
	if sect == null:
		return "宗门不存在"
	if EconomyRules.realm_level(disciple.realm) < EconomyRules.realm_level(Enums.Realm.JIN_DAN):
		return "开辟灵峰需金丹以上修为弟子"
	if tile == null:
		return "目标地块不存在"
	if disciple.tileId != tile.id:
		return "弟子需身处目标地块方可开辟灵峰"
	if not tile.ownerSectId.is_empty():
		return "目标地块已有归属, 无法开辟灵峰"
	if tile.relief == Enums.Relief.MOUNTAIN:
		return "山岳不可开辟灵峰"
	for peak: SpiritPeak in sect.spiritPeaks:
		for project: Project in peak.projectQueue:
			if project.type == Project.TYPE_FOUND_PEAK and project.targetId == tile.id:
				return "该地块已有开辟灵峰项目进行中"
	return ""


## 开峰造价：`spiritPeak.foundCost[流派]`。
## 说明：配置的 `foundCost`（宗门 500 / 家族 800 / 国家 350）已内含流派修正
## （500×1.6=800 对应 `jiaZu.foundCostPenalty`，500×0.7=350 对应 `guoJia.foundCostReduction`），
## 故**不再二次施加** `foundCostReduction`；`spreadPenaltyPerPeak` 按 PRD §4.7 只作用于产出，不入造价。
static func found_peak_cost(config: Dictionary, sect: Sect) -> int:
	var table: Dictionary = config["spiritPeak"]["foundCost"]
	return int(table.get(_faction_key(sect.factionType), table["zongMen"]))


## 建筑可建判定：返回 `{allowed: bool, blocker: String}`。
static func can_build(state: GameState, config: Dictionary, peak: SpiritPeak, building_type: String) -> Dictionary:
	if peak == null:
		return {"allowed": false, "blocker": "灵峰不存在"}
	var sect: Sect = _sect_of(state, peak.sectId)
	if sect == null:
		return {"allowed": false, "blocker": "灵峰所属宗门不存在"}
	if not Enums.Building.ALL.has(building_type):
		return {"allowed": false, "blocker": "未知建筑类型: " + building_type}
	var building: Dictionary = config["building"]
	if not building["costs"].has(building_type) or not building["turns"].has(building_type):
		return {"allowed": false, "blocker": "缺少建筑配置: " + building_type}
	var display_name: String = str(Enums.Building.NAMES.get(building_type, building_type))
	var faction_only: String = str(building["factionOnly"].get(building_type, ""))
	if not faction_only.is_empty() and faction_only != sect.factionType:
		return {"allowed": false, "blocker": "%s是%s专属建筑" % [display_name, _faction_display(config, faction_only)]}
	if building_type == Enums.Building.ZONG_ZHU_DA_DIAN and not peak.capital:
		return {"allowed": false, "blocker": "宗主大殿仅限首都灵峰建造"}
	if Enums.Building.CORE.has(building_type) and building_count(peak, building_type) > 0:
		return {"allowed": false, "blocker": "该核心槽位已有建筑: " + display_name}
	var materials: Dictionary = sect.resources.get("materials", {})
	var material_cost: Dictionary = building["materialCosts"].get(building_type, {})
	for material: Variant in material_cost.keys():
		var need: int = int(material_cost[material])
		var have: int = int(materials.get(material, 0))
		if have < need:
			return {"allowed": false, "blocker": "战略资源不足: 建造%s需 %sx%d, 当前 %d" % [display_name, _material_label(config, str(material)), need, have]}
	var cost: int = int(building["costs"][building_type])
	var power: int = int(sect.resources.get("spiritPower", 0))
	if power < cost:
		return {"allowed": false, "blocker": "灵力不足(%d/%d)" % [power, cost]}
	return {"allowed": true, "blocker": ""}


## 建区合法性：返回 blocker 文案，空串 = 可建。
static func can_found_district(state: GameState, config: Dictionary, peak: SpiritPeak, district_type: String, tile: HexTile) -> String:
	if peak == null:
		return "灵峰不存在"
	var sect: Sect = _sect_of(state, peak.sectId)
	if sect == null:
		return "灵峰所属宗门不存在"
	if not Enums.DistrictType.BUILDABLE.has(district_type):
		return "该区域类型不可建造: " + district_type
	if tile == null:
		return "地块不存在"
	if tile.ownerSectId != sect.id:
		return "只能在本宗归属的地块设置区域"
	if tile.danger:
		return "险地无法施工"
	if not tile.districtId.is_empty():
		return "该地块已有区域"
	if not state.tiles.has(peak.tileId):
		return "灵峰地块缺失"
	var center: HexTile = state.tiles[peak.tileId]
	var radius: int = work_radius(config)
	var distance: int = Hex.distance(Vector2i(tile.q, tile.r), Vector2i(center.q, center.r))
	if distance > radius:
		return "超出灵峰辐射范围(半径%d格, 此处%d格)" % [radius, distance]
	var slots: int = int(config["city"]["district"]["maxDistrictsPerPeak"])
	if built_districts(peak).size() >= slots:
		return "该灵峰区域已满(%d处), 需升级灵峰" % slots
	if not config["city"]["district"]["costs"].has(district_type):
		return "缺少区域造价配置: " + district_type
	return ""


# ---------------------------------------------------------------------------
# 内部工具
# ---------------------------------------------------------------------------

static func _sect_of(state: GameState, sect_id: String) -> Sect:
	for sect: Sect in state.sects:
		if sect.id == sect_id:
			return sect
	return null


static func _faction_key(faction_type: String) -> String:
	match faction_type:
		"ZONG_MEN":
			return "zongMen"
		"JIA_ZU":
			return "jiaZu"
		"GUO_JIA":
			return "guoJia"
	return "zongMen"


static func _faction_display(config: Dictionary, faction_type: String) -> String:
	var flavors: Dictionary = config["faction"]["flavors"]
	if flavors.has(faction_type):
		return str(flavors[faction_type]["displayName"])
	return faction_type


static func _material_label(config: Dictionary, material_id: String) -> String:
	var strategic: Dictionary = config["resources"]["strategic"]
	if strategic.has(material_id):
		return str(strategic[material_id]["displayName"])
	return material_id


static func _yield_score(state: GameState, config: Dictionary, tile: HexTile) -> int:
	var total: int = 0
	for key: String in EconomyRules.YIELD_KEYS:
		total += int(EconomyRules.tile_yield_preview(state, config, tile)[key])
	return total


## 邻接地块的匹配键：险地 / 节点 / 区域 / 海拔（`MOUNTAIN` 等）/ 基底地形。
static func _neighbor_keys(state: GameState, neighbor: HexTile) -> Array[String]:
	var keys: Array[String] = []
	if neighbor.danger:
		keys.append("DANGER")
	if not neighbor.nodeId.is_empty() and state.nodes.has(neighbor.nodeId):
		keys.append("NODE_" + (state.nodes[neighbor.nodeId] as GameNode).type)
	if not neighbor.districtId.is_empty():
		keys.append("DISTRICT")
	keys.append(neighbor.relief)
	keys.append("TERRAIN_" + neighbor.baseTerrain)
	return keys


## 邻接结算明细：`{yield: Dictionary, reasons: Array[String]}`。
static func _adjacency_detail(state: GameState, config: Dictionary, district_type: String, tile_id: String) -> Dictionary:
	var out: Dictionary = {"yield": EconomyRules.zero_yield(), "reasons": []}
	if district_type == Enums.DistrictType.SHOU_FU_QU:
		return out
	if not state.tiles.has(tile_id):
		return out
	var district_config: Dictionary = config["city"]["district"]
	var rules: Array = district_config["adjacency"]
	if rules.is_empty():
		return out
	var base: Dictionary = district_config["yields"].get(district_type, {})
	var anchor: HexTile = state.tiles[tile_id]
	for coords: Vector2i in Hex.neighbors(Vector2i(anchor.q, anchor.r)):
		var neighbor_id: String = Hex.id(coords.x, coords.y)
		if not state.tiles.has(neighbor_id):
			continue
		var neighbor: HexTile = state.tiles[neighbor_id]
		var keys: Array[String] = _neighbor_keys(state, neighbor)
		for rule: Variant in rules:
			var entry: Dictionary = rule
			if str(entry["districtType"]) != district_type or not keys.has(str(entry["neighbor"])):
				continue
			var resource: String = str(entry["resource"])
			var flat: int = int(entry.get("flat", 0))
			var ratio: float = float(entry.get("ratio", 0.0))
			var amount: int = flat
			if ratio > 0.0:
				amount += int(round(float(base.get(resource, 0)) * ratio))
			if amount == 0:
				continue
			var yields: Dictionary = out["yield"]
			yields[resource] = int(yields.get(resource, 0)) + amount
			out["reasons"].append(_describe_rule(entry, neighbor, state))
	return out


static func _describe_rule(rule: Dictionary, neighbor: HexTile, state: GameState) -> String:
	var neighbor_key: String = str(rule["neighbor"])
	var from: String = neighbor.id
	if neighbor_key.begins_with("NODE_") and not neighbor.nodeId.is_empty() and state.nodes.has(neighbor.nodeId):
		from = _node_label((state.nodes[neighbor.nodeId] as GameNode).type)
	elif neighbor_key == "MOUNTAIN":
		from = "山岳"
	elif neighbor_key == "DANGER":
		from = "险地"
	elif neighbor_key == "DISTRICT":
		from = "相邻区域"
	var detail: String = str(rule.get("description", ""))
	if detail.is_empty():
		var parts: Array[String] = []
		var flat: int = int(rule.get("flat", 0))
		var ratio: float = float(rule.get("ratio", 0.0))
		if flat != 0:
			parts.append("%s%+d" % [_resource_label(str(rule["resource"])), flat])
		if ratio > 0.0:
			parts.append("%s+%d%%" % [_resource_label(str(rule["resource"])), int(round(ratio * 100.0))])
		detail = "、".join(parts)
	return "%s: %s" % [from, detail]


static func _resource_label(resource: String) -> String:
	match resource:
		"food":
			return "灵粮"
		"spiritPower":
			return "灵力"
		"spiritStones":
			return "灵石"
		"daoPoints":
			return "道统点"
		"qiYun":
			return "气运"
	return resource


static func _node_label(node_type: String) -> String:
	match node_type:
		"LING_TIAN":
			return "灵田"
		"LING_MAI":
			return "灵脉"
		"LING_QUAN":
			return "灵泉"
		"JI_YUAN":
			return "机缘"
		"MI_JING":
			return "秘境"
	return node_type
