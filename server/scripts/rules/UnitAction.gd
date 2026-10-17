class_name UnitAction
extends RefCounted
## 单位行动入口（R5）：`teleport` / `queryTeleportOptions` / `assignGarrison` / `withdrawGarrison` /
## `reclass` / `promote` / `queryDiscipleDetail`。
##
## 规则计算全在 `TeleportRules`（传送）与 `UnitRules`（兵种/经验/晋升/转职校验），本文件只做
## 校验编排 + 资源扣减 + 状态落地 + 结果组装，不自己发明数值。
##
## **裁决四（`TrainingResult` 形状）**：已回 1.0 `entity/TrainingResult.java` 逐字段核对成功，
## 字段为 `{success, message, unitClass}` 三个（1.0 亦只有这三个），故 `reclass`/`promote`
## 按该形状落地，`PROTOCOL_2.0.md` §11.2 #1 已标注「已回填（R5）」。


# ---------------------------------------------------------------------------
# 传送
# ---------------------------------------------------------------------------

## `teleport`：把弟子传送到己方灵峰（首版跨越山岳的唯一手段）。result 为 `MoveResult`。
static func teleport(state: GameState, config: Dictionary, disciple_id: String, target_peak_id: String) -> Dictionary:
	var disciple: Disciple = MoveAction.find_disciple(state, disciple_id)
	if disciple == null: return _move_fail("", 0, "弟子不存在：" + disciple_id)
	var sect: Sect = _sect_of(state, disciple.sectId)
	if sect == null: return _move_fail(disciple.tileId, disciple.movePoints, "弟子所属宗门不存在")
	var target: SpiritPeak = _find_peak(sect, target_peak_id)
	if target == null: return _move_fail(disciple.tileId, disciple.movePoints, "目标灵峰不存在或非己方：" + target_peak_id)
	var from_peak: SpiritPeak = TeleportRules.peak_of_disciple(sect, disciple)
	if from_peak == null: return _move_fail(disciple.tileId, disciple.movePoints, "弟子不在己方灵峰上, 无法定位传送起点")
	if from_peak.id == target.id: return _move_fail(disciple.tileId, disciple.movePoints, "已在该灵峰")
	var blocker: String = TeleportRules.blocker(state, config, sect, from_peak, target)
	if not blocker.is_empty(): return _move_fail(disciple.tileId, disciple.movePoints, blocker)
	var price: int = TeleportRules.cost(state, config, from_peak, target)
	sect.resources["spiritStones"] = int(sect.resources.get("spiritStones", 0)) - price
	TeleportRules.record_use(sect)
	disciple.tileId = target.tileId
	disciple.garrisonNodeId = ""
	_clear_garrison(state, disciple.id)
	VisionCalculator.recalculate(state, config)
	state.eventLog.append("[传送] %s 由 %s 传至 %s（耗 %d 灵石）" % [disciple.name, from_peak.name, target.name, price])
	return {
		"success": true,
		"message": "已传送至 %s（耗 %d 灵石）" % [target.name, price],
		"reachedTileId": target.tileId,
		"turnsRemaining": disciple.movePoints,
		"triggeredEvent": "",
	}


## `queryTeleportOptions`：只读，列出可传送的己方灵峰与花费、拦截原因。
static func query_teleport_options(state: GameState, config: Dictionary, disciple_id: String) -> Dictionary:
	var disciple: Disciple = MoveAction.find_disciple(state, disciple_id)
	var out: Dictionary = {
		"discipleId": disciple_id,
		"found": disciple != null,
		"enabled": false,
		"capacity": 0,
		"remaining": 0,
		"fromPeakId": "",
		"options": [] as Array,
	}
	if disciple == null: return out
	var sect: Sect = _sect_of(state, disciple.sectId)
	if sect == null: return out
	out["enabled"] = TeleportRules.enabled(state, config, sect)
	out["capacity"] = TeleportRules.capacity(state, config, sect)
	out["remaining"] = TeleportRules.remaining(state, config, sect)
	var from_peak: SpiritPeak = TeleportRules.peak_of_disciple(sect, disciple)
	if from_peak != null: out["fromPeakId"] = from_peak.id
	var options: Array = []
	for peak: SpiritPeak in sect.spiritPeaks:
		var blocker: String = ""
		if from_peak == null:
			blocker = "弟子不在己方灵峰上, 无法定位传送起点"
		elif peak.id == from_peak.id:
			blocker = "已在该灵峰"
		else:
			blocker = TeleportRules.blocker(state, config, sect, from_peak, peak)
		options.append({
			"peakId": peak.id,
			"name": peak.name,
			"capital": peak.capital,
			"level": peak.level,
			"allowed": blocker.is_empty(),
			"blocker": blocker,
			"cost": 0 if from_peak == null else TeleportRules.cost(state, config, from_peak, peak),
		})
	out["options"] = options
	return out


# ---------------------------------------------------------------------------
# 驻守
# ---------------------------------------------------------------------------

## `assignGarrison`：指派弟子驻守己方节点。弟子必须**站在节点地块上**。
static func assign_garrison(state: GameState, config: Dictionary, disciple_id: String, node_id: String) -> Dictionary:
	var disciple: Disciple = MoveAction.find_disciple(state, disciple_id)
	if disciple == null: return _move_fail("", 0, "弟子不存在：" + disciple_id)
	if not state.nodes.has(node_id): return _move_fail(disciple.tileId, disciple.movePoints, "节点不存在：" + node_id)
	var node: GameNode = state.nodes[node_id]
	if node.ownerSectId != disciple.sectId:
		return _move_fail(disciple.tileId, disciple.movePoints, "只能驻守己方节点")
	if disciple.tileId != node.tileId:
		return _move_fail(disciple.tileId, disciple.movePoints, "弟子须先移动到节点所在地块")
	if not disciple.garrisonNodeId.is_empty() and disciple.garrisonNodeId != node_id:
		_clear_garrison(state, disciple.id)
	if not node.garrisonDiscipleIds.has(disciple.id): node.garrisonDiscipleIds.append(disciple.id)
	disciple.garrisonNodeId = node.id
	state.eventLog.append("[驻守] %s 进驻节点 %s" % [disciple.name, node.id])
	return {
		"success": true,
		"message": "%s 已驻守节点 %s" % [disciple.name, node.id],
		"reachedTileId": disciple.tileId,
		"turnsRemaining": disciple.movePoints,
		"triggeredEvent": "",
	}


## `withdrawGarrison`：撤回驻守的弟子。
static func withdraw_garrison(state: GameState, config: Dictionary, disciple_id: String) -> Dictionary:
	var disciple: Disciple = MoveAction.find_disciple(state, disciple_id)
	if disciple == null: return _move_fail("", 0, "弟子不存在：" + disciple_id)
	# 任务节点优先于驻守（1.0 `MoveAction.withdrawGarrison` 同序）：站在机缘/秘境上的弟子
	# 也要有办法「撤回任务」，否则 `missionNodeId` 只能靠走开或陨落清除。
	if not disciple.missionNodeId.is_empty():
		var mission_name: String = disciple.missionNodeId
		if state.nodes.has(disciple.missionNodeId):
			mission_name = (state.nodes[disciple.missionNodeId] as GameNode).name
		disciple.missionNodeId = ""
		state.eventLog.append("[任务] %s 撤回 %s 任务" % [disciple.name, mission_name])
		return {
			"success": true,
			"message": "%s 已撤回机缘/秘境任务" % disciple.name,
			"reachedTileId": disciple.tileId,
			"turnsRemaining": disciple.movePoints,
			"triggeredEvent": "",
		}
	if disciple.garrisonNodeId.is_empty():
		return _move_fail(disciple.tileId, disciple.movePoints, "该弟子未驻守任何节点")
	var node_id: String = disciple.garrisonNodeId
	_clear_garrison(state, disciple.id)
	disciple.garrisonNodeId = ""
	state.eventLog.append("[驻守] %s 撤离节点 %s" % [disciple.name, node_id])
	return {
		"success": true,
		"message": "%s 已撤离节点 %s" % [disciple.name, node_id],
		"reachedTileId": disciple.tileId,
		"turnsRemaining": disciple.movePoints,
		"triggeredEvent": "",
	}


# ---------------------------------------------------------------------------
# 转职 / 晋升
# ---------------------------------------------------------------------------

## `reclass`：转职到指定兵种。result 为 `TrainingResult{success, message, unitClass}`（裁决四）。
## `unitClass` 的**枚举合法性由 `CommandDispatcher` 用 `Enums.UnitClass.ALL` 严格比对**并回 `BAD_PARAMS`，
## 本函数不再「借道枚举 from 静默回退」——非法值走到这里一律 `success:false`。
static func reclass(state: GameState, config: Dictionary, disciple_id: String, unit_class: String) -> Dictionary:
	var disciple: Disciple = MoveAction.find_disciple(state, disciple_id)
	if disciple == null: return _training_fail("弟子不存在：" + disciple_id, disciple)
	var sect: Sect = _sect_of(state, disciple.sectId)
	if sect == null: return _training_fail("弟子所属宗门不存在", disciple)
	if not Enums.UnitClass.ALL.has(unit_class):
		return _training_fail("非法兵种：" + unit_class, disciple)
	var blocker: String = UnitRules.reclass_blocker(state, config, sect, disciple, unit_class)
	if not blocker.is_empty(): return _training_fail(blocker, disciple)
	var unit: Dictionary = UnitRules.class_config(config, unit_class)
	var power_cost: int = maxi(0, int(unit.get("reclassSpiritPower", 0)))
	var stone_cost: int = maxi(0, int(unit.get("reclassSpiritStones", 0)))
	sect.resources["spiritPower"] = int(sect.resources.get("spiritPower", 0)) - power_cost
	sect.resources["spiritStones"] = int(sect.resources.get("spiritStones", 0)) - stone_cost
	var materials: Dictionary = sect.resources.get("materials", {})
	var needed: Dictionary = unit.get("reclassMaterials", {})
	for material: String in needed:
		materials[material] = int(materials.get(material, 0)) - int(needed[material])
	sect.resources["materials"] = materials
	var from_class: String = UnitRules.class_of(disciple)
	disciple.unitClass = unit_class
	disciple.reclassCooldown = maxi(0, int(unit.get("reclassCooldownTurns", 0)))
	# 裁决七：兵种 moveBonus 随转职**实时**改变，故机动上限当场重算（不是等下回合）。
	_refresh_move_points(disciple, config, state, sect)
	state.eventLog.append("[训练] %s 改习%s(自%s), 耗灵力%d、灵石%d, %d回合内不能再改" % [
		disciple.name, UnitRules.class_name_of(config, unit_class), UnitRules.class_name_of(config, from_class),
		power_cost, stone_cost, disciple.reclassCooldown])
	return {"success": true, "message": "已转职为" + UnitRules.class_name_of(config, unit_class), "unitClass": unit_class}


## `promote`：花 1 点晋升点择一晋升。result 形状同 `TrainingResult`（`unitClass` 为当前兵种）。
static func promote(state: GameState, config: Dictionary, disciple_id: String, promotion_id: String) -> Dictionary:
	var disciple: Disciple = MoveAction.find_disciple(state, disciple_id)
	if disciple == null: return _training_fail("弟子不存在：" + disciple_id, disciple)
	if disciple.promotionPoints <= 0:
		return _training_fail("晋升点不足(现有%d)" % disciple.promotionPoints, disciple)
	var chosen: Dictionary = {}
	for option: Dictionary in UnitRules.available_promotions(config, disciple):
		if str(option["id"]) == promotion_id:
			chosen = option
			break
	if chosen.is_empty(): return _training_fail("该晋升不可选：" + promotion_id, disciple)
	disciple.promotions.append(promotion_id)
	disciple.promotionPoints -= 1
	var sect: Sect = _sect_of(state, disciple.sectId)
	# 晋升里的 `move` 加成同样当场生效（`pro_flying_sword`/`pro_swift_hoof` 各 +1）。
	_refresh_move_points(disciple, config, state, sect)
	state.eventLog.append("[晋升] %s 习得「%s」(%s), 剩余晋升点%d" % [
		disciple.name, str(chosen.get("name", promotion_id)), str(chosen.get("description", "")), disciple.promotionPoints])
	return {"success": true, "message": "已晋升: " + str(chosen.get("name", promotion_id)), "unitClass": UnitRules.class_of(disciple)}


# ---------------------------------------------------------------------------
# 弟子详情
# ---------------------------------------------------------------------------

## `queryDiscipleDetail`：只读，PROTOCOL §3 全字段 + 2.0 追加的
## `availablePromotions[]` / `availableUnitClasses[]`。
static func query_disciple_detail(state: GameState, config: Dictionary, disciple_id: String) -> Dictionary:
	var disciple: Disciple = MoveAction.find_disciple(state, disciple_id)
	if disciple == null: return {"found": false, "discipleId": disciple_id}
	var sect: Sect = _sect_of(state, disciple.sectId)
	var unit_class: String = UnitRules.class_of(disciple)
	var current_peak: SpiritPeak = null
	var garrison_node: GameNode = null
	if sect != null:
		for peak: SpiritPeak in sect.spiritPeaks:
			if peak.tileId == disciple.tileId: current_peak = peak
	if not disciple.garrisonNodeId.is_empty() and state.nodes.has(disciple.garrisonNodeId):
		garrison_node = state.nodes[disciple.garrisonNodeId]
	# R6：探索任务节点（机缘/秘境），与驻守互斥。
	var mission_node: GameNode = null
	if not disciple.missionNodeId.is_empty() and state.nodes.has(disciple.missionNodeId):
		mission_node = state.nodes[disciple.missionNodeId]
	var promotions: Array[String] = disciple.promotions.duplicate()
	var promotion_names: Array[String] = []
	for promotion_id: String in promotions:
		promotion_names.append(_promotion_name(config, promotion_id))
	var root_names: Array[String] = []
	for root: String in disciple.spiritRoots:
		root_names.append(str(Enums.SpiritRootType.NAMES.get(root, root)))
	var available: Array = []
	for option: Dictionary in UnitRules.available_promotions(config, disciple):
		available.append({
			"id": str(option["id"]),
			"name": str(option.get("name", "")),
			"description": str(option.get("description", "")),
			"minLevel": int(option.get("minLevel", 0)),
		})
	return {
		"found": true,
		"id": disciple.id,
		"name": disciple.name,
		"realm": disciple.realm,
		"realmName": str(Enums.Realm.NAMES.get(disciple.realm, disciple.realm)),
		"position": disciple.position,
		"positionName": str(Enums.Position.NAMES.get(disciple.position, disciple.position)),
		"sectId": disciple.sectId,
		"sectName": "" if sect == null else sect.name,
		"spiritRoots": disciple.spiritRoots.duplicate(),
		"spiritRootNames": root_names,
		"spiritRootGrade": disciple.rootGrade,
		"bloodLine": disciple.bloodLine,
		"cultivationProgress": disciple.cultivationProgress,
		"heartDevil": disciple.heartDevil,
		"movePoints": disciple.movePoints,
		"maxMovePoints": disciple.maxMovePoints,
		"strikesLeft": disciple.attacksRemaining,
		"turnsInSect": disciple.turnsInSect,
		"unitClass": unit_class,
		"unitClassName": UnitRules.class_name_of(config, unit_class),
		"range": UnitRules.range_of(config, disciple),
		"reclassCooldown": disciple.reclassCooldown,
		"battleXp": disciple.battleXp,
		"battleLevel": disciple.battleLevel,
		"promotionPoints": disciple.promotionPoints,
		"promotions": promotions,
		"promotionNames": promotion_names,
		"builderCharges": disciple.builderCharges,
		"currentTileId": disciple.tileId,
		"currentPeakId": "" if current_peak == null else current_peak.id,
		"currentPeakName": "" if current_peak == null else current_peak.name,
		"garrisonNodeId": disciple.garrisonNodeId,
		"garrisonNodeName": "" if garrison_node == null else garrison_node.name,
		"missionNodeId": disciple.missionNodeId,
		"missionNodeName": "" if mission_node == null else mission_node.name,
		"injured": disciple.injured,
		"tribulating": disciple.tribulating,
		"capturedFromSectId": disciple.capturedFromSectId,
		"availablePromotions": available,
		"availableUnitClasses": UnitRules.available_unit_classes(state, config, sect, disciple),
	}


# ---------------------------------------------------------------------------
# 内部工具
# ---------------------------------------------------------------------------

## 重算机动上限（兵种/晋升变化后立即生效），并把当前移动力夹到新上限内。
static func _refresh_move_points(disciple: Disciple, config: Dictionary, state: GameState, sect: Sect) -> void:
	disciple.maxMovePoints = MoveRules.calculate_max_move_points(disciple, config, state, sect)
	disciple.movePoints = mini(disciple.movePoints, disciple.maxMovePoints)


static func _clear_garrison(state: GameState, disciple_id: String) -> void:
	for node: GameNode in state.nodes.values():
		node.garrisonDiscipleIds.erase(disciple_id)


static func _find_peak(sect: Sect, peak_id: String) -> SpiritPeak:
	if sect == null: return null
	for peak: SpiritPeak in sect.spiritPeaks:
		if peak.id == peak_id: return peak
	return null


static func _sect_of(state: GameState, sect_id: String) -> Sect:
	for sect: Sect in state.sects:
		if sect.id == sect_id: return sect
	return null


static func _promotion_name(config: Dictionary, promotion_id: String) -> String:
	for promotion: Dictionary in config["warfare"]["promotions"]:
		if str(promotion["id"]) == promotion_id: return str(promotion.get("name", promotion_id))
	return promotion_id


## `MoveResult` 的失败形状（PROTOCOL §3）。
static func _move_fail(tile_id: String, move_points: int, message: String) -> Dictionary:
	return {
		"success": false,
		"message": message,
		"reachedTileId": tile_id,
		"turnsRemaining": move_points,
		"triggeredEvent": "",
	}


## `TrainingResult` 的失败形状（裁决四：`{success, message, unitClass}`）。
static func _training_fail(message: String, disciple: Disciple) -> Dictionary:
	return {
		"success": false,
		"message": message,
		"unitClass": "" if disciple == null else UnitRules.class_of(disciple),
	}
