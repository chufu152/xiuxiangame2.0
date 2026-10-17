class_name MoveRules
extends RefCounted
## 移动规则：移动力公式、可通行判定、跨河判定、进入代价叠加（R2）。
##
## 数值唯一权威是 `data/gameConfig.json`；全部静态、无状态、只读 config。
## 进入成本口径（PRD §4.1.8，裁决二）：
##   relief.moveCost + Σ 地貌 moveExtra + 险地附加(dangerTileMoveCost) + 跨河 moveExtra + ZOC − 本宗道路减耗(≥1)
## **R2 不做**：敌方 ZOC、道法 MOVE_BONUS、单位占格阻挡（均已在 R4/R5 回填）。
## **R3 已回填**：青石道路逐格减耗与起点机动加成，均委托 `RoadNetworkService`。
## **R4 已回填**：道法 `MOVE_BONUS`（经 `DaoRules.effect_sum` 唯一出口）。
## **R5 已回填**：① 敌方 ZOC 附加（裁决一，`warfare.zocEnabled`/`zocExtraCost`）；
##   ② **敌方单位占格阻挡**（裁决二）；③ 兵种 `moveBonus` 与晋升 `move` 加成经 `UnitRules` 统一取值。

## 不可通行（MOUNTAIN）的排除标记：调用方（BFS）先过 is_passable 跳过，不进入代价累加。
const IMPASSABLE: int = -1


## 移动力上限（开局与每回合开始共用同一函数，避免两处公式漂移）。
## 裁决一：灵根加成对**所有**灵根按 rootMoveBonus 计（金木水火土风雷各 +1、杂灵根 -1），
## 不照搬 1.0 `MoveAction.calculateMaxMovePoints()` 里 `if (root == FENG || root == ZA)` 的 bug。
## R3 回填：传入 `state`/`sect` 时追加「回合开始身处本宗青石道路」的机动加成（数值取自 `RoadNetworkService`）；
## R4 回填：追加已解锁道法的 `MOVE_BONUS`（`dun_shu`/`qi_ji` 各 +1），经 `DaoRules.effect_sum` 唯一出口。
## R5 回填：兵种 `moveBonus` 与晋升 `move` 加成统一走 `UnitRules.move_bonus`（裁决七），
## 故 `reclass` 后本函数结果**当场**跟着变，不需要另存字段。
## 不传 `state`/`sect` 则等价 R2 口径（R2 测试与开局播种沿用）。
static func calculate_max_move_points(disciple: Disciple, config: Dictionary, state: GameState = null, sect: Sect = null) -> int:
	var setup: Dictionary = config["map"]["setup"]
	var total: int = int(config["disciple"]["baseMovePoints"])
	total += int(setup["realmMoveBonus"][disciple.realm])
	for root: String in disciple.spiritRoots:
		total += int(setup["rootMoveBonus"][root])
	total += UnitRules.move_bonus(config, disciple)
	if state != null and sect != null:
		if state.tiles.has(disciple.tileId):
			total += RoadNetworkService.start_tile_bonus(state, config, sect, state.tiles[disciple.tileId])
		total += DaoRules.move_bonus(state, config, sect)
	return total


## 该格是否可进入（MOUNTAIN 的 passable=false）。
static func is_passable(tile: HexTile, config: Dictionary) -> bool:
	return bool(config["map"]["relief"][tile.relief]["passable"])


## from → to 是否跨河。
## 河流边在 MapGenerator 成对写回：from 的第 d 条边等价于 to 的第 opposite(d) 条边。
static func crosses_river(from_tile: HexTile, to_tile: HexTile) -> bool:
	var delta: Vector2i = Vector2i(to_tile.q - from_tile.q, to_tile.r - from_tile.r)
	var direction: int = -1
	for index: int in range(Hex.DIRECTIONS.size()):
		if Hex.DIRECTIONS[index] == delta:
			direction = index
			break
	if direction < 0:
		return false
	return from_tile.riverEdges.has(direction) or to_tile.riverEdges.has(Hex.opposite(direction))


## 进入 `to_tile` 的移动代价；不可通行返回 IMPASSABLE(-1)。
## R3 回填：传入 `mover_sect`/`state` 时，本宗完好青石道路减 `road.stepCostReduction`（最低 `road.minStepCost`）；
## 数值只取自 `RoadNetworkService`，本函数不硬编码道路数值。不传则等价 R2 口径。
## R5 回填：① 敌方控制区 ZOC 附加（裁决一）；② **敌方单位占格阻挡**（裁决二）。
static func step_cost(config: Dictionary, from_tile: HexTile, to_tile: HexTile, mover_sect: Sect = null, state: GameState = null) -> int:
	if not is_passable(to_tile, config):
		return IMPASSABLE
	# 裁决二：敌方**可战**单位占据的格子不可进入（必须先打掉它）。
	# 友军仍可同格——R2 已定口径「己方多个弟子开局同格，移动后仍可与队友同格」，R5 不推翻。
	if mover_sect != null and state != null and blocked_by_enemy(state, config, mover_sect, to_tile):
		return IMPASSABLE
	var map_config: Dictionary = config["map"]
	var cost: int = int(map_config["relief"][to_tile.relief]["moveCost"])
	for feature: String in to_tile.features:
		cost += int(map_config["features"][feature]["moveExtra"])
	if to_tile.danger:
		cost += int(map_config["dangerTileMoveCost"])
	if crosses_river(from_tile, to_tile):
		cost += int(map_config["river"]["moveExtra"])
	if mover_sect != null and state != null:
		cost += zoc_extra_cost(state, config, mover_sect, to_tile)
		var reduction: int = RoadNetworkService.step_cost_reduction(state, config, mover_sect, to_tile)
		if reduction > 0:
			cost -= reduction
			cost = maxi(cost, RoadNetworkService.min_step_cost(config))
	return maxi(1, cost)


# ---------------------------------------------------------------------------
# 敌方控制区（ZOC）与占格阻挡（R5 回填，裁决一/二）
# ---------------------------------------------------------------------------

## 该地块被多少个**敌方可战单位**的控制区覆盖（相邻即施加）。
## 语义对齐 1.0 `UnitRules.zocPressure()`，数值只取 `warfare.zocEnabled`/`zocExtraCost`。
## 放在本文件而非 `UnitRules` 的原因：它是**移动代价**的一部分，必须与 `step_cost` 同源，
## 才能保证「高亮可达」与「实际可走」永远一致。
static func zoc_pressure(state: GameState, config: Dictionary, mover_sect: Sect, tile: HexTile) -> int:
	if state == null or mover_sect == null or tile == null:
		return 0
	if not bool(config["warfare"]["zocEnabled"]):
		return 0
	var pressure: int = 0
	for sect: Sect in state.sects:
		if sect.id == mover_sect.id:
			continue
		for disciple: Disciple in sect.disciples:
			if not _is_combat_unit(disciple):
				continue
			if _hex_distance(tile, disciple.tileId) == 1:
				pressure += 1
	return pressure


## 进入该地块需要额外付出的移动力 = 压力 × `warfare.zocExtraCost`。
static func zoc_extra_cost(state: GameState, config: Dictionary, mover_sect: Sect, tile: HexTile) -> int:
	var pressure: int = zoc_pressure(state, config, mover_sect, tile)
	if pressure <= 0:
		return 0
	return pressure * maxi(0, int(config["warfare"]["zocExtraCost"]))


## 该格是否被敌方单位占据（敌方单位阻挡进入）。
static func blocked_by_enemy(state: GameState, config: Dictionary, mover_sect: Sect, tile: HexTile) -> bool:
	if state == null or mover_sect == null or tile == null:
		return false
	for sect: Sect in state.sects:
		if sect.id == mover_sect.id:
			continue
		for disciple: Disciple in sect.disciples:
			if not _is_combat_unit(disciple):
				continue
			if disciple.tileId == tile.id:
				return true
	return false


## 是否为可战单位（受伤/渡劫/宗主/峰主不算占格阻挡，与 `UnitRules.can_fight` 同口径）。
static func _is_combat_unit(disciple: Disciple) -> bool:
	if disciple == null or disciple.injured or disciple.tribulating:
		return false
	if disciple.position == Enums.Position.ZONG_ZHU or disciple.position == Enums.Position.FENG_ZHU:
		return false
	return not disciple.tileId.is_empty()


static func _hex_distance(tile: HexTile, other_tile_id: String) -> int:
	if other_tile_id.is_empty():
		return -1
	return Hex.distance(Vector2i(tile.q, tile.r), Hex.coords(other_tile_id))
