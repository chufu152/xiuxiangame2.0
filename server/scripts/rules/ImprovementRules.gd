class_name ImprovementRules
extends RefCounted
## 地块改良规则（R3）：建造合法性（地形/道法/区域/节点）、产出、住房/道路被动、掠夺与修缮。
##
## 数值唯一权威 `data/gameConfig.json` 的 `improvement` / `city` / `road` 节；全部静态、只读 config。
## 1.0 蓝本：`ImprovementCalculator` + `ImprovementAction`。
##
## 地形限制按 PRD §4.1.9（裁决一）：灵田梯田→平地沃野且需道法 `ling_tian_nong`；灵矿/采石场→丘陵；
## 药园→平地/丘陵且需丹器区；聚灵阵→平地/丘陵且需道法 `ju_ling_zhen`；青石道路/洞府→平地/丘陵；
## 灵泉修缮→仅灵泉节点（不可自由建造）。**以 `improvement.byType[]` 的 `reliefs/baseTerrains/
## requiredDaoKey/requiredDistrictType/nodeTypes` 为准，不自行发挥。**

## 改良产出字典的标准键（与 `EconomyRules.YIELD_KEYS` 一致；本地复制以避免反向依赖）。
const YIELD_KEYS: Array[String] = ["food", "spiritPower", "spiritStones", "daoPoints", "qiYun"]


static func zero_yield() -> Dictionary:
	return {"food": 0, "spiritPower": 0, "spiritStones": 0, "daoPoints": 0, "qiYun": 0}


static func _add(target: Dictionary, source: Dictionary) -> void:
	for key: Variant in source.keys():
		var value: Variant = source[key]
		if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
			continue
		target[key] = int(target.get(key, 0)) + int(round(float(value)))


static func type_config(config: Dictionary, improvement_type: String) -> Dictionary:
	var table: Dictionary = config["improvement"]["byType"]
	if table.has(improvement_type):
		return table[improvement_type]
	return {}


static func display_name(config: Dictionary, improvement_type: String) -> String:
	var entry: Dictionary = type_config(config, improvement_type)
	return str(entry.get("name", improvement_type))


# ---------------------------------------------------------------------------
# 查找
# ---------------------------------------------------------------------------

## 地块上的改良（无则 null）。
static func improvement_on(state: GameState, tile: HexTile) -> Improvement:
	if tile == null or tile.improvementId.is_empty():
		return null
	return find_by_id(state, tile.improvementId)


static func find_by_id(state: GameState, improvement_id: String) -> Improvement:
	for sect: Sect in state.sects:
		for improvement: Improvement in sect.improvements:
			if improvement.id == improvement_id:
				return improvement
	return null


static func find_on_tile(state: GameState, tile_id: String) -> Improvement:
	if not state.tiles.has(tile_id):
		return null
	return improvement_on(state, state.tiles[tile_id])


# ---------------------------------------------------------------------------
# 产出与被动
# ---------------------------------------------------------------------------

## 改良产出：破损归零；计入耕作地块产出（`EconomyRules.tile_yield_preview`）。
static func yield_bonus(state: GameState, config: Dictionary, tile: HexTile) -> Dictionary:
	var result: Dictionary = zero_yield()
	var improvement: Improvement = improvement_on(state, tile)
	if improvement == null or improvement.broken:
		return result
	var entry: Dictionary = type_config(config, improvement.type)
	if entry.is_empty():
		return result
	_add(result, entry.get("yields", {}))
	return result


## 洞府住房：灵峰辐射内完好 `DONG_FU` 各 +`dongFuHousing`（破损不计）。
static func housing_bonus(state: GameState, config: Dictionary, peak: SpiritPeak) -> int:
	if not state.tiles.has(peak.tileId):
		return 0
	var center: HexTile = state.tiles[peak.tileId]
	var radius: int = CityRules.work_radius(config)
	var per: int = int(config["improvement"]["dongFuHousing"])
	var bonus: int = 0
	for tile: HexTile in state.tiles.values():
		if Hex.distance(Vector2i(tile.q, tile.r), Vector2i(center.q, center.r)) > radius:
			continue
		var improvement: Improvement = improvement_on(state, tile)
		if improvement != null and not improvement.broken and improvement.type == "DONG_FU":
			bonus += per
	return bonus


## 青石道路机动加成：身处本宗完好道路地块则 +`roadMoveBonus`。
static func road_move_bonus(state: GameState, config: Dictionary, tile: HexTile) -> int:
	var improvement: Improvement = improvement_on(state, tile)
	if improvement == null or improvement.broken or improvement.type != "QING_SHI_DAO_LU":
		return 0
	if tile.ownerSectId != improvement.sectId:
		return 0
	return int(config["improvement"]["roadMoveBonus"])


## 该宗是否已推演某道法。R3 尚无道统系统（R4），一律视为未推演。
static func _has_unlocked_dao(_sect: Sect, _dao_key: String) -> bool:
	# TODO(R4): 接入道统树已解锁集合后改为真实判定（当前恒 false，故需道法的改良在 R3 不可建）。
	return false


# ---------------------------------------------------------------------------
# 建造合法性
# ---------------------------------------------------------------------------

## 建造合法性：返回 blocker 文案，空串 = 可建。
## `disciple` 传 null 时跳过「建造者」相关校验（供 `queryImprovementOptions` 复用）。
static func can_build_improvement(state: GameState, config: Dictionary, sect: Sect, disciple: Disciple, tile: HexTile, improvement_type: String) -> String:
	if not Enums.ImprovementType.ALL.has(improvement_type):
		return "未知改良类型: " + improvement_type
	if tile == null:
		return "地块不存在"
	if sect == null:
		return "宗门不存在"
	if tile.ownerSectId != sect.id:
		return "只能在本宗归属的地块施工"
	if tile.danger:
		return "险地无法施工"
	if not tile.districtId.is_empty():
		return "区域占地不可再建改良"
	if not tile.improvementId.is_empty():
		return "该地块已有改良"
	var node: GameNode = null
	if not tile.nodeId.is_empty() and state.nodes.has(tile.nodeId):
		node = state.nodes[tile.nodeId]
	var entry: Dictionary = type_config(config, improvement_type)
	if entry.is_empty():
		return "缺少改良配置: " + improvement_type
	# 灵泉修缮只能落在灵泉节点；其余改良不得占用灵泉地块。
	var node_types: Array = entry.get("nodeTypes", [])
	if node_types.has("LING_QUAN"):
		if node == null or node.type != Enums.NodeType.LING_QUAN:
			return "灵泉修缮只能建于灵泉地块"
	elif node != null and node.type == Enums.NodeType.LING_QUAN:
		return "灵泉地块只能修筑灵泉修缮"
	# 地形限制
	var reliefs: Array = entry.get("reliefs", [])
	if not reliefs.is_empty() and not reliefs.has(tile.relief):
		return "地形不符(需%s)" % _join_reliefs(reliefs)
	var base_terrains: Array = entry.get("baseTerrains", [])
	if not base_terrains.is_empty() and not base_terrains.has(tile.baseTerrain):
		return "地形不符(需%s)" % _join_terrains(base_terrains)
	# 道法门控
	var required_dao: String = str(entry.get("requiredDaoKey", ""))
	if not required_dao.is_empty() and not _has_unlocked_dao(sect, required_dao):
		return "未推演前置道法(%s)" % required_dao
	# 区域门控
	var required_district: String = str(entry.get("requiredDistrictType", ""))
	if not required_district.is_empty() and not _peak_with_district_within(state, config, sect, tile, required_district):
		return "需身处已建%s的灵峰辐射内" % str(Enums.DistrictType.NAMES.get(required_district, required_district))
	# 建造者
	if disciple != null:
		if disciple.sectId != sect.id:
			return "弟子不存在或不属本宗"
		if disciple.builderCharges <= 0:
			return "该弟子未担任建造者或建造次数已用尽"
		if disciple.tileId != tile.id:
			return "建造者须身处施工地块"
	return ""


## 修缮造价（工力）。
static func repair_cost(config: Dictionary) -> int:
	return int(config["improvement"]["repairCost"])


## 该地块可修筑的改良清单（含不可建原因），供建造菜单展示。
## `broken`：地块上已破损的改良（`{id,type,displayName}`），无则 null。
## `options[]`：`{type, displayName, cost, yieldText, buildable, rejection}`。
static func improvement_options(state: GameState, config: Dictionary, sect: Sect, tile: HexTile) -> Dictionary:
	var options: Array[Dictionary] = []
	var broken: Variant = null
	var existing: Improvement = improvement_on(state, tile)
	if existing != null and existing.broken:
		broken = {"id": existing.id, "type": existing.type, "displayName": display_name(config, existing.type)}
	for improvement_type: String in Enums.ImprovementType.ALL:
		var entry: Dictionary = type_config(config, improvement_type)
		var rejection: String = can_build_improvement(state, config, sect, null, tile, improvement_type)
		# `buildable=false` 的特殊改良（灵泉修缮）只在合法地块上单列，不进普通清单（对齐 1.0）。
		var listed: bool = bool(entry.get("buildable", false))
		if not listed and not rejection.is_empty():
			continue
		options.append({
			"type": improvement_type,
			"displayName": display_name(config, improvement_type),
			"cost": int(entry.get("cost", 0)),
			"yieldText": _yield_text(entry.get("yields", {})),
			"buildable": rejection.is_empty(),
			"rejection": rejection,
		})
	return {"broken": broken, "options": options}


# ---------------------------------------------------------------------------
# 掠夺
# ---------------------------------------------------------------------------

## 掠夺判定：按概率把地块上完好改良打成破损（产出归零、被动失效）。
## 随机只经 `state.rng`（确定性）。
static func apply_pillage(state: GameState, config: Dictionary, tile: HexTile, chance: float, source: String) -> bool:
	var improvement: Improvement = improvement_on(state, tile)
	if improvement == null or improvement.broken:
		return false
	if chance <= 0.0 or not state.rng.chance(chance):
		return false
	improvement.broken = true
	if improvement.type == "QING_SHI_DAO_LU":
		RoadNetworkService.refresh(state, config)
	state.eventLog.append("[改良] %s 的%s 被%s破坏, 产出停摆" % [_owner_name(state, tile), display_name(config, improvement.type), source])
	return true


# ---------------------------------------------------------------------------
# 内部工具
# ---------------------------------------------------------------------------

static func _peak_with_district_within(state: GameState, config: Dictionary, sect: Sect, tile: HexTile, district_type: String) -> bool:
	var radius: int = CityRules.work_radius(config)
	for peak: SpiritPeak in sect.spiritPeaks:
		var has_type: bool = false
		for district: District in peak.districts:
			if district.type == district_type:
				has_type = true
				break
		if not has_type or not state.tiles.has(peak.tileId):
			continue
		var center: HexTile = state.tiles[peak.tileId]
		if Hex.distance(Vector2i(tile.q, tile.r), Vector2i(center.q, center.r)) <= radius:
			return true
	return false


static func _owner_name(state: GameState, tile: HexTile) -> String:
	if tile == null or tile.ownerSectId.is_empty():
		return "荒野"
	for sect: Sect in state.sects:
		if sect.id == tile.ownerSectId:
			return sect.name
	return "荒野"


static func _yield_text(yields: Dictionary) -> String:
	var parts: Array[String] = []
	for key: String in YIELD_KEYS:
		var amount: int = int(yields.get(key, 0))
		if amount != 0:
			parts.append("%s%d" % [_resource_label(key), amount])
	return "/".join(parts)


static func _resource_label(resource: String) -> String:
	match resource:
		"food":
			return "粮"
		"spiritPower":
			return "灵"
		"spiritStones":
			return "石"
		"daoPoints":
			return "道"
		"qiYun":
			return "气运"
	return resource


static func _join_reliefs(reliefs: Array) -> String:
	var labels: Array[String] = []
	for relief: Variant in reliefs:
		match str(relief):
			"FLAT":
				labels.append("平地")
			"HILL":
				labels.append("丘陵")
			"MOUNTAIN":
				labels.append("山岳")
			_:
				labels.append(str(relief))
	return "/".join(labels)


static func _join_terrains(terrains: Array) -> String:
	var labels: Array[String] = []
	for terrain: Variant in terrains:
		match str(terrain):
			"LING_FIELDS":
				labels.append("沃野")
			"SPIRIT_PLAIN":
				labels.append("灵原")
			"BARREN":
				labels.append("荒原")
			_:
				labels.append(str(terrain))
	return "/".join(labels)
