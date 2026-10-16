class_name MoveRules
extends RefCounted
## 移动规则：移动力公式、可通行判定、跨河判定、进入代价叠加（R2）。
##
## 数值唯一权威是 `data/gameConfig.json`；全部静态、无状态、只读 config。
## 进入成本口径（PRD §4.1.8，裁决二）：
##   relief.moveCost + Σ 地貌 moveExtra + 险地附加(dangerTileMoveCost) + 跨河 moveExtra
## **R2 不做**：敌方 ZOC（R5）、青石道路减耗（R3）、道法 MOVE_BONUS（R4）。

## 不可通行（MOUNTAIN）的排除标记：调用方（BFS）先过 is_passable 跳过，不进入代价累加。
const IMPASSABLE: int = -1


## 移动力上限（开局与每回合开始共用同一函数，避免两处公式漂移）。
## 裁决一：灵根加成对**所有**灵根按 rootMoveBonus 计（金木水火土风雷各 +1、杂灵根 -1），
## 不照搬 1.0 `MoveAction.calculateMaxMovePoints()` 里 `if (root == FENG || root == ZA)` 的 bug。
static func calculate_max_move_points(disciple: Disciple, config: Dictionary) -> int:
	var setup: Dictionary = config["map"]["setup"]
	var total: int = int(config["disciple"]["baseMovePoints"])
	total += int(setup["realmMoveBonus"][disciple.realm])
	for root: String in disciple.spiritRoots:
		total += int(setup["rootMoveBonus"][root])
	total += int(config["warfare"]["unitClasses"][disciple.unitClass]["moveBonus"])
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
static func step_cost(config: Dictionary, from_tile: HexTile, to_tile: HexTile) -> int:
	if not is_passable(to_tile, config):
		return IMPASSABLE
	var map_config: Dictionary = config["map"]
	var cost: int = int(map_config["relief"][to_tile.relief]["moveCost"])
	for feature: String in to_tile.features:
		cost += int(map_config["features"][feature]["moveExtra"])
	if to_tile.danger:
		cost += int(map_config["dangerTileMoveCost"])
	if crosses_river(from_tile, to_tile):
		cost += int(map_config["river"]["moveExtra"])
	return maxi(1, cost)
