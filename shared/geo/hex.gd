class_name Hex
extends RefCounted
## flat-top 六边形轴向坐标（axial q,r）几何。
##
## 唯一权威：docs/REQUIREMENTS_2.0.md §1.3 / §4.1.10 / §8.4。
##
## 纯函数、无状态、不依赖节点。服务端移动/视野计算与客户端渲染**必须共用本文件的换算**，
## 避免两端口径漂移。
##   - 地块 id 换算："q{q}_r{r}" <-> Vector2i(q, r)
##   - 六邻接、轴向距离、方向索引
##   - 世界坐标：x = size * 1.5 * q，z = size * sqrt(3) * (r + q / 2)
##   - 地块边的两个端点（河流贴边渲染、河流图去重用）
##
## 方向与边的对应：`DIRECTIONS[i]` 是第 i 条边的外法线方向；
## `edge_vertices(q, r, i)` 返回的边，正是与 `(q, r) + DIRECTIONS[i]` 共享的那条边。
## 因此 `edge_vertices(q, r, i)` 与 `edge_vertices(neighbor, opposite(i))` 得到同一对端点。

## sqrt(3)，六边形换算基础常量。
const SQRT3: float = 1.7320508075688772

## 六个邻接方向（轴向偏移，逆时针 E / NE / NW / W / SW / SE）。
## 索引 i 与 i+3 互为反向，与河流「边」索引一一对应。
const DIR_E: Vector2i = Vector2i(1, 0)
const DIR_NE: Vector2i = Vector2i(1, -1)
const DIR_NW: Vector2i = Vector2i(0, -1)
const DIR_W: Vector2i = Vector2i(-1, 0)
const DIR_SW: Vector2i = Vector2i(-1, 1)
const DIR_SE: Vector2i = Vector2i(0, 1)

const DIRECTIONS: Array[Vector2i] = [DIR_E, DIR_NE, DIR_NW, DIR_W, DIR_SW, DIR_SE]

const DIRECTION_NAMES: Array[String] = ["E", "NE", "NW", "W", "SW", "SE"]

## flat-top 六边形的 6 个角点偏移（size = 1；分量 x 为世界 x，分量 y 为世界 z）。
## 角 i 与角 (i + 1) % 6 之间的边，其外法线正对 DIRECTIONS[i]（见 edge_vertices）。
const VERTEX_OFFSETS: Array[Vector2] = [
	Vector2(1.0, 0.0),
	Vector2(0.5, SQRT3 * 0.5),
	Vector2(-0.5, SQRT3 * 0.5),
	Vector2(-1.0, 0.0),
	Vector2(-0.5, -SQRT3 * 0.5),
	Vector2(0.5, -SQRT3 * 0.5),
]

## 地块 id：`"q{q}_r{r}"`（负坐标亦合法，如 `q-1_r3`）。
static func id(q: int, r: int) -> String:
	return "q%d_r%d" % [q, r]

## 由地块 id 还原轴向坐标；非法输入回退 Vector2i.ZERO（不抛错，保持纯函数）。
static func coords(tile_id: String) -> Vector2i:
	var parts: PackedStringArray = tile_id.split("_r", false)
	if parts.size() != 2:
		return Vector2i.ZERO
	var q_text: String = parts[0]
	if not q_text.begins_with("q"):
		return Vector2i.ZERO
	return Vector2i(int(q_text.substr(1)), int(parts[1]))

## 六个轴向邻接（顺序与 DIRECTIONS 一致）。
static func neighbors(cell: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for direction: Vector2i in DIRECTIONS:
		result.append(cell + direction)
	return result

## 轴向距离（六边形格数，非世界距离）。
static func distance(a: Vector2i, b: Vector2i) -> int:
	var dq: int = a.x - b.x
	var dr: int = a.y - b.y
	return (absi(dq) + absi(dr) + absi(dq + dr)) / 2

## 地块中心的世界坐标（flat-top：x = size * 1.5 * q，z = size * sqrt(3) * (r + q / 2)）。
static func to_world(q: int, r: int, size: float = 1.0, height: float = 0.0) -> Vector3:
	return Vector3(size * 1.5 * q, height, size * SQRT3 * (r + q * 0.5))

## 第 edge 条边的反向边索引（i 与 i+3 互为反向）。
static func opposite(edge: int) -> int:
	return (edge + 3) % 6

## 第 edge 条边的两个世界端点（河流贴边渲染用）。
## 返回顺序固定为 [角 (6 - edge) % 6, 角 (7 - edge) % 6]，与相邻格同一边互为逆序。
static func edge_vertices(q: int, r: int, edge: int, size: float = 1.0, height: float = 0.0) -> Array[Vector3]:
	var center: Vector3 = to_world(q, r, size, height)
	var result: Array[Vector3] = []
	for index: int in [(6 - edge) % 6, (7 - edge) % 6]:
		var offset: Vector2 = VERTEX_OFFSETS[index]
		result.append(center + Vector3(size * offset.x, 0.0, size * offset.y))
	return result
