class_name RoadNetworkService
extends RefCounted
## 青石道路网（R3）：同宗完好道路相连成链后按「是否接入本宗灵峰/灵脉」分级。
##
## 数值唯一权威 `data/gameConfig.json` 的 `road` 节；1.0 蓝本：`RoadNetworkService`。
## 等级写回 `Improvement.networkLevel`（入 view），每回合开始由 `TurnProcessor._run_turn_start` 刷新。
##
## 逐格减耗（`step_cost_reduction`）：只要**目标格**是本宗完好青石道路即生效，与是否成网无关。
## 起点机动加成（`start_tile_bonus`）：基础加成 + 网络等级加成（支线/干线）。

const TIER_NONE: int = 0
const TIER_LINK: int = 1
const TIER_HUB: int = 2


static func enabled(config: Dictionary) -> bool:
	return bool(config["road"]["enabled"])


## 刷新全部宗门的道路链等级（关闭道路系统时等级清零）。
static func refresh(state: GameState, config: Dictionary) -> void:
	for sect: Sect in state.sects:
		for improvement: Improvement in sect.improvements:
			if improvement.type == "QING_SHI_DAO_LU":
				improvement.networkLevel = TIER_NONE
	if not enabled(config):
		return
	for sect: Sect in state.sects:
		_refresh_for_sect(state, config, sect)


## 踏入本宗完好道路的移动代价减免（险地受益最明显）。
static func step_cost_reduction(state: GameState, config: Dictionary, sect: Sect, tile: HexTile) -> int:
	if sect == null or tile == null or not enabled(config):
		return 0
	var improvement: Improvement = ImprovementRules.find_on_tile(state, tile.id)
	if improvement == null or improvement.broken or improvement.type != "QING_SHI_DAO_LU":
		return 0
	if tile.ownerSectId != sect.id:
		return 0
	return int(config["road"]["stepCostReduction"])


## 减免后的每格代价下限。
static func min_step_cost(config: Dictionary) -> int:
	if not enabled(config):
		return 1
	return maxi(1, int(config["road"]["minStepCost"]))


## 回合开始身处道路的机动加成：基础加成（任意本宗完好道路）+ 本宗网络等级加成。
static func start_tile_bonus(state: GameState, config: Dictionary, sect: Sect, tile: HexTile) -> int:
	var base: int = ImprovementRules.road_move_bonus(state, config, tile)
	if base == 0 or sect == null or tile == null or not enabled(config) or tile.ownerSectId != sect.id:
		return base
	var improvement: Improvement = ImprovementRules.find_on_tile(state, tile.id)
	if improvement == null:
		return base
	if improvement.networkLevel >= TIER_HUB:
		return base + int(config["road"]["tierHubBonus"])
	if improvement.networkLevel >= TIER_LINK:
		return base + int(config["road"]["tierPeakBonus"])
	return base


# ---------------------------------------------------------------------------
# 内部工具
# ---------------------------------------------------------------------------

static func _refresh_for_sect(state: GameState, config: Dictionary, sect: Sect) -> void:
	var roads: Dictionary = {}
	for improvement: Improvement in sect.improvements:
		if improvement.type != "QING_SHI_DAO_LU" or improvement.broken:
			continue
		if not state.tiles.has(improvement.tileId):
			continue
		var tile: HexTile = state.tiles[improvement.tileId]
		if tile.ownerSectId == sect.id:
			roads[improvement.tileId] = improvement
	if roads.is_empty():
		return
	var peak_tiles: Dictionary = _peak_tiles(sect)
	var ling_mai_tiles: Dictionary = _ling_mai_tiles(state, sect)
	var min_chain: int = int(config["road"]["networkMinChainTiles"])
	var hub_peaks: int = maxi(1, int(config["road"]["hubPeakCount"]))
	var visited: Dictionary = {}
	for start: Variant in roads.keys():
		var start_id: String = str(start)
		if visited.has(start_id):
			continue
		var chain: Array[String] = _collect_chain(state, roads, start_id, visited)
		var linked_peaks: int = _count_touching(state, chain, peak_tiles)
		var linked_ling_mai: int = _count_touching(state, chain, ling_mai_tiles)
		var tier: int = TIER_NONE
		if chain.size() >= min_chain:
			if linked_peaks >= hub_peaks or linked_ling_mai > 0:
				tier = TIER_HUB
			elif linked_peaks >= 1:
				tier = TIER_LINK
		for tile_id: String in chain:
			(roads[tile_id] as Improvement).networkLevel = tier


## 从一格出发把整条相连道路收出来（六邻域 BFS）。
static func _collect_chain(state: GameState, roads: Dictionary, start: String, visited: Dictionary) -> Array[String]:
	var chain: Array[String] = []
	var queue: Array[String] = [start]
	visited[start] = true
	var head: int = 0
	while head < queue.size():
		var tile_id: String = queue[head]
		head += 1
		chain.append(tile_id)
		if not state.tiles.has(tile_id):
			continue
		var tile: HexTile = state.tiles[tile_id]
		for coords: Vector2i in Hex.neighbors(Vector2i(tile.q, tile.r)):
			var neighbor_id: String = Hex.id(coords.x, coords.y)
			if roads.has(neighbor_id) and not visited.has(neighbor_id):
				visited[neighbor_id] = true
				queue.append(neighbor_id)
	return chain


## 道路链「接上」了几个目标：链上道路自身即目标格，或其邻域含目标格。
static func _count_touching(state: GameState, chain: Array[String], targets: Dictionary) -> int:
	if targets.is_empty():
		return 0
	var touched: Dictionary = {}
	for tile_id: String in chain:
		if targets.has(tile_id):
			touched[tile_id] = true
		if not state.tiles.has(tile_id):
			continue
		var tile: HexTile = state.tiles[tile_id]
		for coords: Vector2i in Hex.neighbors(Vector2i(tile.q, tile.r)):
			var neighbor_id: String = Hex.id(coords.x, coords.y)
			if targets.has(neighbor_id):
				touched[neighbor_id] = true
	return touched.size()


static func _peak_tiles(sect: Sect) -> Dictionary:
	var tiles: Dictionary = {}
	for peak: SpiritPeak in sect.spiritPeaks:
		if not peak.tileId.is_empty():
			tiles[peak.tileId] = true
	return tiles


static func _ling_mai_tiles(state: GameState, sect: Sect) -> Dictionary:
	var tiles: Dictionary = {}
	for node: GameNode in state.nodes.values():
		if node.type != Enums.NodeType.LING_MAI or node.ownerSectId != sect.id:
			continue
		tiles[node.tileId] = true
	return tiles
