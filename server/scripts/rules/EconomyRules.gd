class_name EconomyRules
extends RefCounted
## 经济结算规则（R3）：地块产出 / 灵峰产出 / 维护 / 安定 / 产出系数 / `SETTLEMENT` 唯一入口。
##
## 数值唯一权威 `data/gameConfig.json`；全部静态、无状态、只读 config。
## 1.0 蓝本：`EconomyCalculator` + `PopulationCalculator` + `DistrictCalculator`。
##
## 产出字典统一形状：`{food, spiritPower, spiritStones, daoPoints, qiYun}`；地貌/改良可能附带材料键
## （如 `ling_mu`），由结算按 `resources.strategic` 路由到 `sect.resources.materials`。
##
## **R3 不做**：道统成就 boost（R4）、心魔结算（R4）、政令结算（R6）、围城断供（R5）、
## 宗主/峰主任命加成（R7）。
##
## **R3 回填**：气运攒满 → 吞并相邻无主地块 / 灵峰晋升（1.0 `EconomyCalculator.annexAdjacentTile`
## + `developPeak`）。这是 1.0 唯一的地块归属增长途径，也是 `foundDistrict`/`assignWorker`/
## `buildImprovement` 在开局能落到地块上的前提（见 `docs/PROTOCOL_2.0.md` §11.1）。

## 产出字典的 5 个标准键（顺序固定，便于逐字比对）。
const YIELD_KEYS: Array[String] = ["food", "spiritPower", "spiritStones", "daoPoints", "qiYun"]
## 境界等级（与 `map.setup.realmMoveBonus` 的键序一致）。
const REALM_LEVEL: Dictionary = {"LIAN_QI": 1, "ZHU_JI": 2, "JIN_DAN": 3, "YUAN_YING": 4, "HUA_SHEN": 5}


static func zero_yield() -> Dictionary:
	return {"food": 0, "spiritPower": 0, "spiritStones": 0, "daoPoints": 0, "qiYun": 0}


## 把 `source` 中的数值键累加进 `target`（非数值键跳过）。
static func add_yield(target: Dictionary, source: Dictionary) -> void:
	for key: Variant in source.keys():
		var value: Variant = source[key]
		if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
			continue
		target[key] = int(target.get(key, 0)) + int(round(float(value)))


static func realm_level(realm: String) -> int:
	return int(REALM_LEVEL.get(realm, 1))


# ---------------------------------------------------------------------------
# 地块产出
# ---------------------------------------------------------------------------

## 单个工作地块的产出；**仅被 `peak` 指派（`workedByPeakId` 匹配）才产出**（PRD §4.1.9）。
static func tile_yield(state: GameState, config: Dictionary, tile: HexTile, peak: SpiritPeak) -> Dictionary:
	if tile == null or peak == null or tile.workedByPeakId != peak.id:
		return zero_yield()
	return tile_yield_preview(state, config, tile)


## 无视指派、纯按地块计算产出（指派预览 / 选址提示用）。
## 组成（顺序同 PRD §4.1.9 L315）：基底地形 + 海拔（`map.relief[].yield`，丘陵石 +1）
## + 地貌（`map.features[].yield`）+ 河流（`map.river.foodBonus`，沿河粮 +1）+ 节点
## （`city.workYieldByNode`）+ 改良（完好时）。
static func tile_yield_preview(state: GameState, config: Dictionary, tile: HexTile) -> Dictionary:
	var result: Dictionary = zero_yield()
	var city: Dictionary = config["city"]
	var terrain_table: Dictionary = city["workYieldByTerrain"]
	if terrain_table.has(tile.baseTerrain):
		add_yield(result, terrain_table[tile.baseTerrain])
	# 海拔加成（PRD §4.1.3「丘陵 石 +1」；平地/山岳为空表）
	var relief_table: Dictionary = config["map"]["relief"]
	if relief_table.has(tile.relief) and relief_table[tile.relief].has("yield"):
		add_yield(result, relief_table[tile.relief]["yield"])
	var feature_table: Dictionary = config["map"]["features"]
	for feature: String in tile.features:
		if feature_table.has(feature) and feature_table[feature].has("yield"):
			add_yield(result, feature_table[feature]["yield"])
	# 沿河灌溉（PRD §4.1.5 L280「沿河地块：粮 +1」）
	if not tile.riverEdges.is_empty():
		result["food"] = int(result["food"]) + int(config["map"]["river"]["foodBonus"])
	if not tile.nodeId.is_empty() and state.nodes.has(tile.nodeId):
		var node: GameNode = state.nodes[tile.nodeId]
		var node_table: Dictionary = city["workYieldByNode"]
		if node_table.has(node.type):
			add_yield(result, node_table[node.type])
	add_yield(result, ImprovementRules.yield_bonus(state, config, tile))
	return result


# ---------------------------------------------------------------------------
# 灵峰产出 / 维护
# ---------------------------------------------------------------------------

## 单座灵峰的**毛产出**（不含维护，维护见 `sect_upkeep`）。
## 组成：工作格产出 + 区域产出 + 主峰基础灵力（`baseSpiritPowerOutput`×等级）
##      + 建筑加成（藏经阁道点）+ 气运（`qiYun` 节）+ 安定/住房折减 − 铺张惩罚。
## 主峰（`capital`）额外计入**宗级计一次**的部分：弟子灵力反哺、宗门级节点道点、奢侈品气运，
## 以保证 `Σ peak_output == 宗门毛收入`。
static func peak_output(state: GameState, config: Dictionary, peak: SpiritPeak) -> Dictionary:
	var result: Dictionary = zero_yield()
	if peak == null:
		return result
	var sect: Sect = _sect_of(state, peak.sectId)
	# 工作格
	for tile_id: String in peak.workedTileIds:
		if state.tiles.has(tile_id):
			add_yield(result, tile_yield(state, config, state.tiles[tile_id], peak))
	# 区域
	for district: District in peak.districts:
		add_yield(result, CityRules.district_yield(state, config, peak, district.type, district.tileId))
	# 主峰基础灵力（按等级）；**峰主驻留该峰时** ×(1 + `fengZhuSpiritPowerBonus`)，外出失效（R7）。
	var base_power: int = int(config["spiritPeak"]["baseSpiritPowerOutput"]) * peak.level
	if AppointmentRules.feng_zhu_present(state, sect, peak):
		base_power = int(round(float(base_power) \
			* (1.0 + float(config["appointment"]["fengZhuSpiritPowerBonus"]))))
	result["spiritPower"] = int(result["spiritPower"]) + base_power
	# 藏经阁：每座道点 +cangJingGePointsPerTurn
	var cang_jing: int = CityRules.building_count(peak, Enums.Building.CANG_JING_GE)
	if cang_jing > 0:
		result["daoPoints"] = int(result["daoPoints"]) + int(config["daoTree"]["cangJingGePointsPerTurn"]) * cang_jing
	# 气运：基础 + 驻留高阶弟子 + 邻接灵脉/灵泉
	var qi_yun: int = int(config["qiYun"]["basePerTurn"])
	qi_yun += _dwelling_high_realm_qi_yun(state, config, peak, sect)
	qi_yun += _adjacent_resource_nodes(state, peak) * int(config["qiYun"]["adjacentNodeBonus"])
	if peak.capital:
		qi_yun += _luxury_qi_yun(config, sect)
	# R7 任命气运：峰主驻留该峰 +`fengZhuQiYunBonus`；宗主坐镇首都大殿 +`zongZhuDaDianQiYunBonus`。
	# 两者都是「在场才生效」，与灵力加成的失效口径一致（1.0 `calculateQiYun` 同序）。
	if AppointmentRules.feng_zhu_present(state, sect, peak):
		qi_yun += int(config["appointment"]["fengZhuQiYunBonus"])
	if peak.capital and sect != null:
		qi_yun += AppointmentRules.zong_zhu_qi_yun_bonus(state, config, sect)
	result["qiYun"] = int(result["qiYun"]) + qi_yun
	if peak.capital and sect != null:
		# 弟子灵力反哺（宗级计一次；R3 无重伤/渡劫状态，全员计入）
		result["spiritPower"] = int(result["spiritPower"]) + int(config["economy"]["discipleSpiritPowerOutput"]) * sect.disciples.size()
		# 宗门已占节点道点（`daoTree.nodeOutput`）
		result["daoPoints"] = int(result["daoPoints"]) + _node_dao_points(state, config, sect)
	# 安定/住房折减 × 铺张惩罚
	var peaks: int = 1 if sect == null else maxi(1, sect.spiritPeaks.size())
	var factor: float = output_multiplier(state, config, peak) * maxf(0.0, 1.0 - float(config["spiritPeak"]["spreadPenaltyPerPeak"]) * float(peaks - 1))
	for key: String in YIELD_KEYS:
		result[key] = int(round(float(result[key]) * factor))
	return result


## 城市级产出（指派地块 + 区域，含安定/住房折减），供 `queryCityDetail.cityYield`。
## 与 `peak_output` 的区别：不含主峰基础灵力、弟子反哺、气运与铺张惩罚。
static func city_yield(state: GameState, config: Dictionary, peak: SpiritPeak) -> Dictionary:
	var result: Dictionary = zero_yield()
	for tile_id: String in peak.workedTileIds:
		if state.tiles.has(tile_id):
			add_yield(result, tile_yield(state, config, state.tiles[tile_id], peak))
	for district: District in peak.districts:
		add_yield(result, CityRules.district_yield(state, config, peak, district.type, district.tileId))
	var factor: float = output_multiplier(state, config, peak)
	for key: Variant in result.keys():
		result[key] = int(round(float(result[key]) * factor))
	return result


## 灵峰维护（灵力）：主峰 `baseMaintenance` + 每座洞府 `subPeakMaintenance`。
static func peak_maintenance(config: Dictionary, peak: SpiritPeak) -> int:
	return int(config["spiritPeak"]["baseMaintenance"]) + int(config["spiritPeak"]["subPeakMaintenance"]) * CityRules.cave_count(peak)


## 宗门每回合维护：`{food: 弟子口粮, spiritPower: 建筑/单位/灵峰维护, …}`。
## 口径（PRD §4.6/§4.7）：每名弟子粮 1；建筑每级 1、单位每级 2、主峰 6 / 副峰（洞府）2（灵力）。
## 人口口粮在 `food_balance` 中按城计，不在此重复。
static func sect_upkeep(state: GameState, config: Dictionary, sect: Sect) -> Dictionary:
	var result: Dictionary = zero_yield()
	var economy: Dictionary = config["economy"]
	result["food"] = int(economy["discipleUpkeepBase"]) * sect.disciples.size()
	var building_levels: int = 0
	for peak: SpiritPeak in sect.spiritPeaks:
		result["spiritPower"] = int(result["spiritPower"]) + peak_maintenance(config, peak)
		building_levels += peak.level
		building_levels += CityRules.cave_count(peak)
		building_levels += CityRules.building_levels(peak)
	result["spiritPower"] = int(result["spiritPower"]) + int(economy["buildingUpkeepPerLevel"]) * building_levels
	var unit_levels: int = 0
	for disciple: Disciple in sect.disciples:
		if disciple.unitClass != Enums.UnitClass.PU_TONG:
			unit_levels += 1
	result["spiritPower"] = int(result["spiritPower"]) + int(economy["unitUpkeepPerLevel"]) * unit_levels
	return result


## 工力（建设吞吐）每回合收入：每峰基础 + 每洞府 + 每个工作格。
static func work_power_income(state: GameState, config: Dictionary, sect: Sect) -> int:
	var economy: Dictionary = config["economy"]
	var total: int = 0
	var worked: int = 0
	for peak: SpiritPeak in sect.spiritPeaks:
		total += int(economy["workPowerBasePerPeak"])
		total += int(economy["workPowerPerSubPeak"]) * CityRules.cave_count(peak)
		worked += peak.workedTileIds.size()
	total += int(economy["workPowerPerWorkedTile"]) * worked
	return total


## 威望每回合收入：金丹以上弟子各计一份。
static func prestige_income(state: GameState, config: Dictionary, sect: Sect) -> int:
	var threshold: int = realm_level(Enums.Realm.JIN_DAN)
	var count: int = 0
	for disciple: Disciple in sect.disciples:
		if realm_level(disciple.realm) >= threshold:
			count += 1
	return count * int(config["economy"]["prestigePerHighRealmDisciple"])


# ---------------------------------------------------------------------------
# 安定 / 产出系数 / 粮食
# ---------------------------------------------------------------------------

## 灵峰安定（PRD §4.7）：基础 70 + 气运 + 区域 + 奢侈品 + 祖祠 − 拥挤 12 − 缺粮 15 − 赤字 3。
static func stability_of(state: GameState, config: Dictionary, peak: SpiritPeak, deficit: bool = false) -> float:
	var city: Dictionary = config["city"]
	var sect: Sect = _sect_of(state, peak.sectId)
	var stability: float = float(city["stabilityBase"])
	if peak.qiYunMax > 0:
		stability += round(float(mini(peak.qiYun, peak.qiYunMax)) / float(peak.qiYunMax) * float(city["qiYunStabilityBonus"]))
	stability += float(CityRules.district_stability(config, peak))
	if sect != null:
		stability += float(_luxury_stability(config, sect))
		if CityRules.building_count(peak, Enums.Building.ZU_CI) > 0:
			stability += float(config["faction"]["jiaZu"]["zuCiStabilityPerTurn"])
	if deficit:
		stability -= float(config["economy"]["stabilityDropOnDeficit"])
	var housing: int = CityRules.housing_of(state, config, peak)
	var overflow: int = maxi(0, peak.population - housing)
	stability -= float(overflow) * float(city["overcrowdingPenalty"])
	if peak.food <= 0.0 and food_balance(state, config, peak) < 0:
		stability -= float(city["foodShortagePenalty"])
	return clampf(stability, 0.0, float(city["stabilityMax"]))


## 城市产出系数：安定偏离基准的增减（`stabilityOutputFactor`）× 住房超员惩罚（下限 0.2）。
static func output_multiplier(state: GameState, config: Dictionary, peak: SpiritPeak, deficit: bool = false) -> float:
	var city: Dictionary = config["city"]
	var factor: float = 1.0 + (stability_of(state, config, peak, deficit) - float(city["stabilityBase"])) * float(city["stabilityOutputFactor"])
	var housing: int = CityRules.housing_of(state, config, peak)
	var overflow: int = maxi(0, peak.population - housing)
	factor -= float(overflow) * float(city["housingOverflowOutputPenalty"])
	return maxf(0.2, factor)


## 本回合粮食净增：指派地块 + 区域产粮 − 人口口粮（PRD §4.7：粮耗 1/人）。
static func food_balance(state: GameState, config: Dictionary, peak: SpiritPeak) -> int:
	var income: int = 0
	for tile_id: String in peak.workedTileIds:
		if state.tiles.has(tile_id):
			income += int(tile_yield(state, config, state.tiles[tile_id], peak)["food"])
	for district: District in peak.districts:
		income += int(CityRules.district_yield(state, config, peak, district.type, district.tileId)["food"])
	return income - int(config["city"]["foodPerPopulation"]) * peak.population


# ---------------------------------------------------------------------------
# SETTLEMENT：唯一入口
# ---------------------------------------------------------------------------

## `SETTLEMENT` 阶段唯一入口（PRD §4.5）：
##   节点冷却 −1 → 城市人口结算（补劳力/粮食/增长）→ 经济结算 → 道统 boost(R4) → 心魔(R4) → 政令(R6)。
## 返回本次新增的 `state.eventLog` 条目。
static func apply_settlement(state: GameState, config: Dictionary) -> Array[String]:
	var before: int = state.eventLog.size()
	# 1) 节点冷却 −1
	for node: GameNode in state.nodes.values():
		if node.cooldown > 0:
			node.cooldown -= 1
	# 2) 人口结算 → 3) 经济结算（逐宗）
	for sect: Sect in state.sects:
		var totals: Dictionary = zero_yield()
		var per_peak: Array[Dictionary] = []
		for peak: SpiritPeak in sect.spiritPeaks:
			var out: Dictionary = peak_output(state, config, peak)
			per_peak.append(out)
			add_yield(totals, out)
		var upkeep: Dictionary = sect_upkeep(state, config, sect)
		# 政令产出乘区（R6）：`1 + outputBonus + spiritPowerBonus`，只作用灵力总产出。
		# 未颁加成卡时恒 ×1.0，故不改变 R3 已验收的任何数值。
		var policy_multiplier: float = PolicyRules.output_multiplier(state, config, sect)
		if not is_equal_approx(policy_multiplier, 1.0):
			totals["spiritPower"] = int(round(float(totals["spiritPower"]) * policy_multiplier))
		# 宗主大殿灵力乘区（R7）：宗主坐镇首都且大殿建成时宗级 ×1.2，外出即 ×1.0。
		# 与 1.0 `calculateSpiritPowerIncome` 的 `total *= 1 + zongZhuDaDianSpiritPowerBonus` 同位置。
		var zong_zhu_multiplier: float = AppointmentRules.zong_zhu_spirit_multiplier(state, config, sect)
		if not is_equal_approx(zong_zhu_multiplier, 1.0):
			totals["spiritPower"] = int(round(float(totals["spiritPower"]) * zong_zhu_multiplier))
		var deficit: bool = int(sect.resources.get("spiritPower", 0)) + int(totals["spiritPower"]) < int(upkeep["spiritPower"])
		settle_city(state, config, sect, deficit)
		_apply_economy(state, config, sect, totals, per_peak, upkeep, deficit)
	# 道统成就 boost / 心魔结算（R4）与政令结算（R6）在 `TurnProcessor._run_settlement` 里按序调用，
	# 因为政令的安定叠加必须落在本函数重算安定之后。
	return state.eventLog.slice(before)


## 单宗城市结算：自动补劳力 → 进粮 → 按粮/住房/安定判定人口增长 → 刷新安定/住房/空闲劳力。
static func settle_city(state: GameState, config: Dictionary, sect: Sect, deficit: bool = false) -> void:
	var city: Dictionary = config["city"]
	var threshold: float = float(city["growthFoodThreshold"])
	var growth_cost: float = float(city["growthFoodCost"])
	var stability_min: float = float(city["growthStabilityMin"])
	for peak: SpiritPeak in sect.spiritPeaks:
		CityRules.auto_assign(state, config, sect, peak)
		var balance: int = food_balance(state, config, peak)
		peak.food = maxf(0.0, peak.food + float(balance))
		peak.stability = stability_of(state, config, peak, deficit)
		var housing: int = CityRules.housing_of(state, config, peak)
		var grew: int = 0
		while peak.population + grew < housing and peak.food >= threshold and peak.stability >= stability_min:
			peak.food -= growth_cost
			grew += 1
		peak.population += grew
		peak.housing = housing
		peak.foodProgress = peak.food
		CityRules.sync_free_workers(peak)
		if grew > 0:
			state.eventLog.append("[城市] %s 人口 +%d → %d（住房 %d）" % [peak.name, grew, peak.population, housing])


static func _apply_economy(state: GameState, config: Dictionary, sect: Sect, totals: Dictionary, per_peak: Array[Dictionary], upkeep: Dictionary, deficit: bool) -> void:
	var resources: Dictionary = sect.resources
	var power_before: int = int(resources.get("spiritPower", 0))
	# 灵力
	if deficit:
		resources["spiritPower"] = 0
	else:
		resources["spiritPower"] = power_before + int(totals["spiritPower"]) - int(upkeep["spiritPower"])
	# 灵石 / 道点
	resources["spiritStones"] = int(resources.get("spiritStones", 0)) + int(totals["spiritStones"])
	resources["daoPoints"] = int(resources.get("daoPoints", 0)) + int(totals["daoPoints"])
	# 工力 / 威望
	resources["workPower"] = int(resources.get("workPower", 0)) + work_power_income(state, config, sect)
	resources["prestige"] = int(resources.get("prestige", 0)) + prestige_income(state, config, sect)
	# 气运（逐峰，上限 qiYunMax）；攒满则按 1.0 `EconomyCalculator` 吞并相邻无主地块 / 灵峰晋升。
	var peak_index: int = 0
	for peak: SpiritPeak in sect.spiritPeaks:
		if peak_index < per_peak.size():
			peak.qiYun = peak.qiYun + int(per_peak[peak_index]["qiYun"])
			if peak.qiYun >= peak.qiYunMax:
				if annex_adjacent_tile(state, config, sect, peak) or develop_peak(config, peak):
					peak.qiYun = 0
				else:
					peak.qiYun = peak.qiYunMax
		peak_index += 1
	# 材料（地貌/改良产出）
	var materials: Dictionary = resources.get("materials", {})
	for key: Variant in totals.keys():
		var name: String = str(key)
		if YIELD_KEYS.has(name) or not config["resources"]["strategic"].has(name):
			continue
		materials[name] = int(materials.get(name, 0)) + int(totals[name])
	resources["materials"] = materials
	# 弟子口粮：从各峰粮仓按峰序扣减
	var drained: int = _drain_food(sect, int(upkeep["food"]))
	# 奢侈品入账
	_accrue_luxury(state, config, sect)
	# 显示聚合：粮仓总和 / 气运总和
	resources["food"] = _total_food(sect)
	resources["qiYun"] = _total_qi_yun(sect)
	state.eventLog.append("[结算] %s 灵力%+d→%d 灵石+%d 道点+%d 工力+%d 威望+%d 粮-%d" % [
		sect.name,
		int(resources["spiritPower"]) - power_before, int(resources["spiritPower"]),
		int(totals["spiritStones"]), int(totals["daoPoints"]),
		work_power_income(state, config, sect), prestige_income(state, config, sect), drained])


# ---------------------------------------------------------------------------
# 气运满溢：扩张（1.0 `EconomyCalculator.annexAdjacentTile` / `developPeak`）
# ---------------------------------------------------------------------------

## 气运攒满后吞并灵峰相邻的**无主**地块：优先带资源节点者（LING_TIAN/LING_MAI/LING_QUAN），
## 其次按 `Hex.neighbors` 顺序取首个无主地块；同时接管其节点归属。返回是否吞并成功。
## 说明：这是 1.0 唯一的地块归属增长途径（另两处为战斗夺地 R5、外交割让 R7），
## 也是 `foundDistrict`/`assignWorker`/`buildImprovement` 在开局能落到地块上的前提。
static func annex_adjacent_tile(state: GameState, config: Dictionary, sect: Sect, peak: SpiritPeak) -> bool:
	if not state.tiles.has(peak.tileId):
		return false
	var center: HexTile = state.tiles[peak.tileId]
	var target: HexTile = null
	var neighbors: Array[HexTile] = []
	for coords: Vector2i in Hex.neighbors(Vector2i(center.q, center.r)):
		var tile_id: String = Hex.id(coords.x, coords.y)
		if state.tiles.has(tile_id):
			neighbors.append(state.tiles[tile_id])
	# 优先吞并带资源节点的无主地块，让气运扩张转化为实际产出。
	for neighbor: HexTile in neighbors:
		if neighbor.ownerSectId.is_empty() and _has_resource_node(state, neighbor):
			target = neighbor
			break
	if target == null:
		for neighbor: HexTile in neighbors:
			if neighbor.ownerSectId.is_empty():
				target = neighbor
				break
	if target == null:
		return false
	target.ownerSectId = sect.id
	if not target.nodeId.is_empty() and state.nodes.has(target.nodeId):
		state.nodes[target.nodeId].ownerSectId = sect.id
	state.eventLog.append("[气运] %s 的%s 气运攒满, 吞并相邻无主地块 %s" % [sect.name, peak.name, target.id])
	return true


## 无处可吞并时：气运浇灌灵峰本身，灵峰晋升（容量 +`capacityPerLevel`、防御 +`baseDefense`/2）。
static func develop_peak(config: Dictionary, peak: SpiritPeak) -> bool:
	var max_level: int = int(config["spiritPeak"]["maxLevel"])
	if peak.level >= max_level:
		return false
	var spirit_peak: Dictionary = config["spiritPeak"]
	peak.level += 1
	peak.capacity += int(spirit_peak["capacityPerLevel"])
	peak.defense += int(int(spirit_peak["baseDefense"]) / 2)
	peak.qiYunMax = int(spirit_peak["baseQiYunMax"])
	return true


static func _has_resource_node(state: GameState, tile: HexTile) -> bool:
	if tile.nodeId.is_empty() or not state.nodes.has(tile.nodeId):
		return false
	var node_type: String = state.nodes[tile.nodeId].type
	return node_type == Enums.NodeType.LING_TIAN or node_type == Enums.NodeType.LING_MAI or node_type == Enums.NodeType.LING_QUAN


# ---------------------------------------------------------------------------
# 内部工具
# ---------------------------------------------------------------------------

static func _sect_of(state: GameState, sect_id: String) -> Sect:
	for sect: Sect in state.sects:
		if sect.id == sect_id:
			return sect
	return null


## 驻留本峰的高阶弟子气运（`qiYun.highRealmLevel` 起，每高一阶 +qiYunPerRealmLevel）。
static func _dwelling_high_realm_qi_yun(state: GameState, config: Dictionary, peak: SpiritPeak, sect: Sect) -> int:
	if sect == null:
		return 0
	var high: int = int(config["qiYun"]["highRealmLevel"])
	var per_level: int = int(config["qiYun"]["qiYunPerRealmLevel"])
	var total: int = 0
	for disciple: Disciple in sect.disciples:
		if disciple.tileId != peak.tileId:
			continue
		var level: int = realm_level(disciple.realm)
		if level >= high:
			total += (level - high + 1) * per_level
	return total


## 灵峰邻接的本宗/中立灵脉、灵泉节点数（气运 `adjacentNodeBonus`）。
static func _adjacent_resource_nodes(state: GameState, peak: SpiritPeak) -> int:
	if not state.tiles.has(peak.tileId):
		return 0
	var center: HexTile = state.tiles[peak.tileId]
	var count: int = 0
	for coords: Vector2i in Hex.neighbors(Vector2i(center.q, center.r)):
		var tile_id: String = Hex.id(coords.x, coords.y)
		if not state.tiles.has(tile_id):
			continue
		var tile: HexTile = state.tiles[tile_id]
		if tile.nodeId.is_empty() or not state.nodes.has(tile.nodeId):
			continue
		var node: GameNode = state.nodes[tile.nodeId]
		if node.type != Enums.NodeType.LING_MAI and node.type != Enums.NodeType.LING_QUAN:
			continue
		if node.ownerSectId.is_empty() or node.ownerSectId == peak.sectId:
			count += 1
	return count


## 宗门已占灵脉/机缘/秘境节点的道点产出（`daoTree.nodeOutput`）。
static func _node_dao_points(state: GameState, config: Dictionary, sect: Sect) -> int:
	var table: Dictionary = config["daoTree"]["nodeOutput"]
	var total: int = 0
	for node: GameNode in state.nodes.values():
		if node.ownerSectId != sect.id:
			continue
		match node.type:
			"LING_MAI":
				total += int(table["lingMaiBase"]) + int(table["lingMaiPerLevel"]) * node.level
			"JI_YUAN":
				total += int(table["jiYuanBase"]) + int(table["jiYuanPerLevel"]) * node.level
			"MI_JING":
				total += int(table["miJingBase"]) + int(table["miJingPerLevel"]) * node.level
	return total


static func _luxury_held(sect: Sect) -> Array:
	if sect == null:
		return []
	var luxuries: Dictionary = sect.resources.get("luxuries", {})
	var held: Array = []
	for key: Variant in luxuries.keys():
		if int(luxuries[key]) > 0:
			held.append(str(key))
	held.sort()
	return held


static func _luxury_stability(config: Dictionary, sect: Sect) -> int:
	var table: Dictionary = config["resources"]["luxuryTypes"]
	var total: int = 0
	for luxury_type: String in _luxury_held(sect):
		if table.has(luxury_type):
			total += int(table[luxury_type]["stabilityBonus"])
		else:
			total += int(config["city"]["luxuryStabilityBonus"])
	return total


static func _luxury_qi_yun(config: Dictionary, sect: Sect) -> int:
	var table: Dictionary = config["resources"]["luxuryTypes"]
	var total: int = 0
	for luxury_type: String in _luxury_held(sect):
		if table.has(luxury_type):
			total += int(table[luxury_type]["qiYunBonus"])
	return total


## 奢侈资源入账：被指派工作的产地地块每回合按 `luxuryYieldPerTurn` 产出。
static func _accrue_luxury(state: GameState, config: Dictionary, sect: Sect) -> void:
	var per_turn: int = int(config["resources"]["luxuryYieldPerTurn"])
	var luxuries: Dictionary = sect.resources.get("luxuries", {})
	for peak: SpiritPeak in sect.spiritPeaks:
		for tile_id: String in peak.workedTileIds:
			if not state.tiles.has(tile_id):
				continue
			var tile: HexTile = state.tiles[tile_id]
			if tile.luxuryType.is_empty():
				continue
			luxuries[tile.luxuryType] = int(luxuries.get(tile.luxuryType, 0)) + per_turn
	sect.resources["luxuries"] = luxuries


## 从各峰粮仓按峰序扣减 `amount` 口粮，返回实际扣减量。
static func _drain_food(sect: Sect, amount: int) -> int:
	var remaining: int = amount
	for peak: SpiritPeak in sect.spiritPeaks:
		if remaining <= 0:
			break
		var take: int = mini(int(peak.food), remaining)
		peak.food -= float(take)
		peak.foodProgress = peak.food
		remaining -= take
	return amount - remaining


static func _total_food(sect: Sect) -> int:
	var total: int = 0
	for peak: SpiritPeak in sect.spiritPeaks:
		total += int(peak.food)
	return total


static func _total_qi_yun(sect: Sect) -> int:
	var total: int = 0
	for peak: SpiritPeak in sect.spiritPeaks:
		total += peak.qiYun
	return total
