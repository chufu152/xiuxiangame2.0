class_name MoveRangeCalculator
extends RefCounted
## 移动可达范围的唯一计算入口（只读，R2）。
##
## 口径与 1.0 `MoveRangeCalculator.reachableCosts` 一致：起点代价 0，BFS 按 `Hex.DIRECTIONS`
## 固定顺序展开，遇到更小代价时松弛重排（Dijkstra 松弛），只依赖固定邻接顺序，故输出确定。
##
## `queryMoveRange`（高亮）与 `moveDisciple`（权威移动）**共用本文件**，
## 从结构上杜绝「高亮的格子实际走不进去」这类不一致。
##
## **R2 不做**：外交过境关（外交已裁剪）、敌方 ZOC（R5）、单位占格阻挡、战斗触发。
## **R3 已回填**：本宗青石道路逐格减耗（经 `MoveRules.step_cost` → `RoadNetworkService`）。
## 可达性只由地形与道路决定；己方多个弟子开局同格，移动后仍可与队友同格。


## 返回 `{origin: String, costs: Dictionary, order: Array}`：
##   - `costs` 为 tileId → 从起点进入该格的**最小**移动力代价（含起点 0），插入顺序即首次发现顺序；
##   - `order` 为 BFS 首次发现顺序的 tileId 列表（起点在 [0]），与 `costs` 键序一致。
## 预算取**当前剩余移动力** `disciple.movePoints`（不是 maxMovePoints）。
static func reachable(state: GameState, config: Dictionary, disciple: Disciple) -> Dictionary:
	var costs: Dictionary = {}
	var order: Array[String] = []
	var origin: String = disciple.tileId
	if not state.tiles.has(origin):
		return {"origin": origin, "costs": costs, "order": order}
	var mover: Sect = _sect_of(state, disciple.sectId)
	costs[origin] = 0
	order.append(origin)
	var queue: Array[String] = [origin]
	var head: int = 0
	while head < queue.size():
		var current: String = queue[head]
		head += 1
		var current_cost: int = int(costs[current])
		var tile: HexTile = state.tiles[current]
		for neighbor_coords: Vector2i in Hex.neighbors(Vector2i(tile.q, tile.r)):
			var neighbor_id: String = Hex.id(neighbor_coords.x, neighbor_coords.y)
			if not state.tiles.has(neighbor_id):
				continue
			var neighbor: HexTile = state.tiles[neighbor_id]
			# 山岳等不可通行先排除，不进入代价累加（step_cost 的 IMPASSABLE 契约）。
			if not MoveRules.is_passable(neighbor, config):
				continue
			var step: int = MoveRules.step_cost(config, tile, neighbor, mover, state)
			if step < 0:
				continue
			var total: int = current_cost + step
			if total > disciple.movePoints:
				continue
			var known: bool = costs.has(neighbor_id)
			if not known or total < int(costs[neighbor_id]):
				if not known:
					order.append(neighbor_id)
				costs[neighbor_id] = total
				queue.append(neighbor_id)
	return {"origin": origin, "costs": costs, "order": order}


static func _sect_of(state: GameState, sect_id: String) -> Sect:
	for sect: Sect in state.sects:
		if sect.id == sect_id:
			return sect
	return null
