class_name Hex
extends RefCounted
## flat-top 六边形轴向坐标（axial q,r）几何。
##
## 唯一权威：docs/REQUIREMENTS_2.0.md §1.3 / §4.1.10 / §8.4。
##
## R0 只放常量占位与注释，**不实现任何地图逻辑**。
## R1 在此实现（纯函数、无状态、不依赖节点）：
##   - 地块 id 换算："q{q}_r{r}" <-> Vector2i(q, r)
##   - 六邻接、轴向距离、方向索引
##   - 世界坐标：x = size * 1.5 * q，z = size * sqrt(3) * (r + q / 2)
##   - 由 map.relief 柱高系数（FLAT 1.0 / HILL 1.7 / MOUNTAIN 3.0）换算柱体高度与顶面落点
##   - 地块边的端点（河流贴边渲染用）
##
## 注意：服务端移动/视野计算与客户端渲染**必须共用本文件的换算**，避免两端口径漂移。

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
