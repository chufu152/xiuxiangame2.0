class_name MoveAction
extends RefCounted
## 移动命令（R2）：`queryMoveRange`（只读，不回 view）与 `moveDisciple`（权威移动 + 视野刷新）。
##
## 两者**共用同一份 `MoveRangeCalculator`**，保证「高亮的格子必然走得进去」。
## **R2 不做**：外交过境关（已裁剪）、敌方 ZOC（R5）、青石道路（R3）、单位占格阻挡、战斗触发、批量移动（R3）。


## 在权威 state 中查找弟子；找不到返回 null。
static func find_disciple(state: GameState, disciple_id: String) -> Disciple:
	for sect: Sect in state.sects:
		for disciple: Disciple in sect.disciples:
			if disciple.id == disciple_id:
				return disciple
	return null


## 只读：返回 PROTOCOL §3 的 `queryMoveRange` 结果
## `{discipleId, originTileId, movePoints, maxMovePoints, tileIds, costs, tileCount}`。
## 弟子不存在时返回空字典（调用方应先用 `find_disciple` 校验并回 BAD_PARAMS）。
static func query_move_range(state: GameState, config: Dictionary, disciple_id: String) -> Dictionary:
	var disciple: Disciple = find_disciple(state, disciple_id)
	if disciple == null:
		return {}
	var reach: Dictionary = MoveRangeCalculator.reachable(state, config, disciple)
	var order: Array[String] = reach["order"]
	return {
		"discipleId": disciple.id,
		"originTileId": str(reach["origin"]),
		"movePoints": disciple.movePoints,
		"maxMovePoints": disciple.maxMovePoints,
		"tileIds": order.duplicate(),
		"costs": (reach["costs"] as Dictionary).duplicate(),
		"tileCount": order.size(),
	}


## 权威移动：成功则更新位置、扣减移动力、刷新视野并写事件；失败则状态不变。
## 返回 PROTOCOL §3 的 `MoveResult{success, message, reachedTileId, turnsRemaining, triggeredEvent}`。
static func move_disciple(state: GameState, config: Dictionary, disciple_id: String, target_tile_id: String) -> Dictionary:
	var disciple: Disciple = find_disciple(state, disciple_id)
	if disciple == null:
		return _failure(null, "弟子不存在：" + disciple_id)
	if not state.tiles.has(target_tile_id):
		return _failure(disciple, "目标地块不存在：" + target_tile_id)
	var reach: Dictionary = MoveRangeCalculator.reachable(state, config, disciple)
	var costs: Dictionary = reach["costs"]
	if not costs.has(target_tile_id):
		return _failure(disciple, "目标不可达（山岳 / 超剩余移动力 / 越界）")
	var cost: int = int(costs[target_tile_id])
	disciple.tileId = target_tile_id
	disciple.movePoints -= cost
	# 离开机缘/秘境所在地块即视为任务结束（1.0 `MoveAction.clearMissionIfLeft`）。
	clear_mission_if_left(state, disciple)
	# 迷雾随移动刷新：新位置揭示、旧位置降级为已探索。
	VisionCalculator.recalculate(state, config)
	state.eventLog.append("弟子 %s 移动至 %s（耗 %d 移动力）" % [disciple.name, target_tile_id, cost])
	return {
		"success": true,
		"message": "",
		"reachedTileId": target_tile_id,
		"turnsRemaining": disciple.movePoints,
		"triggeredEvent": "",
	}


## 弟子离开机缘/秘境所在地块后清空 `missionNodeId`（1.0 `MoveAction.clearMissionIfLeft`）。
## 节点已被移除（不应发生）也一并清空，避免 `queryDiscipleDetail` 挂着一个不存在的节点名。
static func clear_mission_if_left(state: GameState, disciple: Disciple) -> void:
	if disciple == null or disciple.missionNodeId.is_empty():
		return
	if not state.nodes.has(disciple.missionNodeId):
		disciple.missionNodeId = ""
		return
	var node: GameNode = state.nodes[disciple.missionNodeId]
	if node.tileId != disciple.tileId:
		disciple.missionNodeId = ""


static func _failure(disciple: Disciple, message: String) -> Dictionary:
	return {
		"success": false,
		"message": message,
		"reachedTileId": "" if disciple == null else disciple.tileId,
		"turnsRemaining": 0 if disciple == null else disciple.movePoints,
		"triggeredEvent": "",
	}
