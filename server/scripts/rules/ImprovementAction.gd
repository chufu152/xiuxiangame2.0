class_name ImprovementAction
extends RefCounted
## 改良命令（R3）：任命建造者 / 修筑改良 / 修缮 / 查询可建改良。
##
## 全部静态、无状态；数值只取自 `data/gameConfig.json`，规则委托 `ImprovementRules` / `RoadNetworkService`。
## 1.0 蓝本：`ImprovementAction`。
##
## 即时性说明：`buildImprovement` / `repairImprovement` 为**即时落成**（消耗 1 次建造次数与造价，
## 无项目队列），与 1.0 一致；故 `BuildResult.projectId=""`、`turnsRequired=0`。
## 差异登记于 `docs/PROTOCOL_2.0.md` §11.1。


static func find_sect(state: GameState, sect_id: String) -> Sect:
	return CityAction.find_sect(state, sect_id)


static func find_disciple(state: GameState, disciple_id: String) -> Disciple:
	return CityAction.find_disciple(state, disciple_id)


## 任命建造者：低阶弟子领受建造差事，获得 `builderCharges` 次修筑额度。
static func appoint_builder(state: GameState, config: Dictionary, sect_id: String, disciple_id: String) -> Dictionary:
	var sect: Sect = find_sect(state, sect_id)
	if sect == null:
		return CityAction.fail_result("宗门不存在: " + sect_id)
	var disciple: Disciple = find_disciple(state, disciple_id)
	if disciple == null or disciple.sectId != sect.id:
		return CityAction.fail_result("弟子不存在或不属本宗: " + disciple_id)
	var max_realm: int = int(config["improvement"]["builderMaxRealmLevel"])
	if EconomyRules.realm_level(disciple.realm) > max_realm:
		return CityAction.fail_result("境界过高, 建造差事只交给低阶弟子")
	var charges: int = int(config["improvement"]["builderCharges"])
	disciple.builderCharges = charges
	state.eventLog.append("[改良] %s 领受建造差事, 可修筑%d次" % [disciple.name, charges])
	return CityAction.ok_result("%s 领受建造差事, 可修筑%d次" % [disciple.name, charges])


## 修筑改良：建造者须身处目标地块，扣 1 次建造次数 + 造价（工力），即时落成。
static func build_improvement(state: GameState, config: Dictionary, sect_id: String, disciple_id: String, tile_id: String, improvement_type: String) -> Dictionary:
	var sect: Sect = find_sect(state, sect_id)
	if sect == null:
		return CityAction.fail_result("宗门不存在: " + sect_id)
	var disciple: Disciple = find_disciple(state, disciple_id)
	if disciple == null or disciple.sectId != sect.id:
		return CityAction.fail_result("弟子不存在或不属本宗: " + disciple_id)
	var tile: HexTile = state.tiles.get(tile_id)
	var blocker: String = ImprovementRules.can_build_improvement(state, config, sect, disciple, tile, improvement_type)
	if not blocker.is_empty():
		return CityAction.fail_result(blocker)
	var entry: Dictionary = ImprovementRules.type_config(config, improvement_type)
	var cost: int = int(entry.get("cost", 0))
	var work_power: int = int(sect.resources.get("workPower", 0))
	if work_power < cost:
		return CityAction.fail_result("工力不足(%d/%d)" % [work_power, cost])
	sect.resources["workPower"] = work_power - cost
	state.improvementSeq += 1
	var improvement: Improvement = Improvement.new()
	improvement.id = "improvement_%d" % state.improvementSeq
	improvement.type = improvement_type
	improvement.tileId = tile_id
	improvement.sectId = sect.id
	improvement.broken = false
	sect.improvements.append(improvement)
	tile.improvementId = improvement.id
	disciple.builderCharges -= 1
	if improvement_type == "QING_SHI_DAO_LU":
		RoadNetworkService.refresh(state, config)
	var display_name: String = ImprovementRules.display_name(config, improvement_type)
	var tail: String = "" if disciple.builderCharges > 0 else ", 建造次数用尽, 差事结束"
	state.eventLog.append("[改良] %s 于 %s 修筑%s(耗工力%d, 剩余%d次)" % [disciple.name, tile_id, display_name, cost, disciple.builderCharges])
	return CityAction.ok_result("%s 于 %s 修筑%s, 耗工力%d(剩余%d次)%s" % [disciple.name, tile_id, display_name, cost, disciple.builderCharges, tail], "", 0, cost)


## 修缮破损改良：耗 `repairCost` 工力 + 1 次建造次数，即时恢复。
static func repair_improvement(state: GameState, config: Dictionary, sect_id: String, disciple_id: String, tile_id: String) -> Dictionary:
	var sect: Sect = find_sect(state, sect_id)
	if sect == null:
		return CityAction.fail_result("宗门不存在: " + sect_id)
	var disciple: Disciple = find_disciple(state, disciple_id)
	if disciple == null or disciple.sectId != sect.id:
		return CityAction.fail_result("弟子不存在或不属本宗: " + disciple_id)
	if disciple.builderCharges <= 0:
		return CityAction.fail_result("该弟子未担任建造者或建造次数已用尽")
	if disciple.tileId != tile_id:
		return CityAction.fail_result("建造者须身处施工地块")
	var tile: HexTile = state.tiles.get(tile_id)
	if tile == null:
		return CityAction.fail_result("地块不存在: " + tile_id)
	if tile.ownerSectId != sect.id:
		return CityAction.fail_result("只能修缮本宗归属地块的改良")
	var improvement: Improvement = ImprovementRules.improvement_on(state, tile)
	if improvement == null:
		return CityAction.fail_result("该地块没有改良设施")
	if not improvement.broken:
		return CityAction.fail_result("该改良完好无损, 无需修缮")
	var cost: int = ImprovementRules.repair_cost(config)
	var work_power: int = int(sect.resources.get("workPower", 0))
	if work_power < cost:
		return CityAction.fail_result("工力不足(%d/%d)" % [work_power, cost])
	sect.resources["workPower"] = work_power - cost
	improvement.broken = false
	disciple.builderCharges -= 1
	if improvement.type == "QING_SHI_DAO_LU":
		RoadNetworkService.refresh(state, config)
	var display_name: String = ImprovementRules.display_name(config, improvement.type)
	state.eventLog.append("[改良] %s 修复 %s(耗工力%d)" % [disciple.name, display_name, cost])
	return CityAction.ok_result("%s 修复%s, 耗工力%d(剩余%d次)" % [disciple.name, display_name, cost, disciple.builderCharges], "", 0, cost)


## `queryImprovementOptions`：`{sectId, tileId, broken, options[]}`（只读，不返 view）。
static func query_improvement_options(state: GameState, config: Dictionary, sect_id: String, tile_id: String) -> Dictionary:
	var sect: Sect = find_sect(state, sect_id)
	var tile: HexTile = state.tiles.get(tile_id)
	var detail: Dictionary = ImprovementRules.improvement_options(state, config, sect, tile)
	return {"sectId": sect_id, "tileId": tile_id, "broken": detail["broken"], "options": detail["options"]}
