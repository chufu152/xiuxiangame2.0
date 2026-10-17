class_name Minimap
extends Control
## 小地图（§8.4 / R8 任务 4）：缩略图 + 视口框 + 点击跳转。
##
## 硬约束：**点击只平移相机**——不改角度、不改缩放（R8 验收第 6 条）。
## 缩略图内容全部来自服务端 `view`（基底/归属/迷雾三态），客户端零推导。

signal tile_picked(tile_id: String)

const MAP_SIZE: float = 168.0
const PADDING: float = 6.0

## tile_id → {q, r, baseTerrain, ownerColor, fog}
var tiles: Dictionary = {}
## 视口框（世界坐标中心 + 正交 size）。
var view_center: Vector3 = Vector3.ZERO
var view_size: float = 24.0
var _bounds: Rect2 = Rect2()
var _points: Dictionary = {}
var _picked: String = ""


func setup() -> void:
	name = "Minimap"
	custom_minimum_size = Vector2(MAP_SIZE, MAP_SIZE)
	size = Vector2(MAP_SIZE, MAP_SIZE)
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = "小地图：点击跳转（只平移，不改角度与缩放）"


func configure(view: Dictionary, fog: Fog) -> void:
	tiles.clear()
	_points.clear()
	var data: Dictionary = view.get("tiles", {})
	var colors: Dictionary = {}
	for sect: Dictionary in view.get("sects", []):
		colors[str(sect.get("id", ""))] = Color.from_string(str(sect.get("color", "#387f78")), Color("387f78"))
	var minimum: Vector2 = Vector2(INF, INF)
	var maximum: Vector2 = Vector2(-INF, -INF)
	for tile_id: String in data:
		var tile: Dictionary = data[tile_id]
		var q: int = int(tile.get("q", 0))
		var r: int = int(tile.get("r", 0))
		var state: int = int(fog.state_for(tile_id)) if fog != null else 2
		var color: Color = Color(0.34, 0.39, 0.37, 0.70)
		if state != 0:
			color = _terrain_color(str(tile.get("baseTerrain", "")))
			var owner_id: String = str(tile.get("ownerSectId", ""))
			if colors.has(owner_id):
				color = (colors[owner_id] as Color).lightened(0.35)
			if state == 1:
				color = color.darkened(0.18)
		tiles[tile_id] = {"q": q, "r": r, "color": color}
		var flat: Vector2 = Vector2(float(q) * 1.5, (float(r) + float(q) * 0.5) * Hex.SQRT3)
		minimum = Vector2(minf(minimum.x, flat.x), minf(minimum.y, flat.y))
		maximum = Vector2(maxf(maximum.x, flat.x), maxf(maximum.y, flat.y))
	if minimum.x == INF:
		_bounds = Rect2()
		queue_redraw()
		return
	_bounds = Rect2(minimum, maximum - minimum)
	_rebuild_points()
	queue_redraw()


## 按当前控件尺寸重算各格屏幕坐标。
## 必须每次绘制/命中前重算：`PanelContainer` 会异步改变子控件尺寸，
## 若只在 `configure` 里算一次，缩略图会挤在左上角一小块。
func _rebuild_points() -> void:
	_points.clear()
	for tile_id: String in tiles:
		var item: Dictionary = tiles[tile_id]
		var flat: Vector2 = Vector2(float(item["q"]) * 1.5, (float(item["r"]) + float(item["q"]) * 0.5) * Hex.SQRT3)
		_points[tile_id] = _to_control(flat)


func set_view(center: Vector3, ortho_size: float) -> void:
	view_center = center
	view_size = ortho_size
	queue_redraw()


func _to_control(flat: Vector2) -> Vector2:
	var canvas: Vector2 = _canvas()
	var span: Vector2 = _bounds.size
	var usable: Vector2 = Vector2(canvas.x - PADDING * 2.0, canvas.y - PADDING * 2.0)
	var scale_value: float = minf(usable.x / maxf(span.x, 0.001), usable.y / maxf(span.y, 0.001))
	var center_flat: Vector2 = _bounds.position + span * 0.5
	return canvas * 0.5 + (flat - center_flat) * scale_value


## 实际绘制区尺寸（`PanelContainer` 会把控件拉到内容区，不能用常量硬算）。
func _canvas() -> Vector2:
	var value: Vector2 = size
	if value.x < 8.0 or value.y < 8.0:
		return Vector2(MAP_SIZE, MAP_SIZE)
	return value


func _draw() -> void:
	_rebuild_points()
	var canvas: Vector2 = _canvas()
	# 深墨底 + 金边：与参考图的「世界地图」小窗一致，压在山水的暗部不抢视线。
	draw_rect(Rect2(Vector2.ZERO, canvas), Color(0.169, 0.227, 0.216, 0.96), true)
	draw_rect(Rect2(Vector2.ZERO, canvas), Color(0.72, 0.57, 0.18, 0.85), false, 1.5)
	for tile_id: String in _points:
		var point: Vector2 = _points[tile_id] as Vector2
		var color: Color = (tiles[tile_id] as Dictionary)["color"] as Color
		draw_circle(point, 2.6, color)
	# 视口框：世界坐标 → 小地图坐标（与地块同一线性映射）。
	# 注意：`_points` 用的是 `Hex.to_world` 的 (x, z) 原值，故这里也必须直接用 (x, z)，
	# 若再除一次 √3 会把框推到左上角（曾出现过的偏移 bug）。
	var corners: PackedVector2Array = PackedVector2Array()
	var half: float = view_size * 0.5
	for offset: Vector2 in [Vector2(-half, -half), Vector2(half, -half), Vector2(half, half), Vector2(-half, half)]:
		var world: Vector3 = view_center + Vector3(offset.x, 0.0, offset.y)
		corners.append(_to_control(Vector2(world.x, world.z)))
	if corners.size() == 4:
		draw_polyline(corners + PackedVector2Array([corners[0]]), Color(0.95, 0.82, 0.42, 0.95), 1.6)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var picked: String = tile_at(event.position)
		if not picked.is_empty():
			_picked = picked
			tile_picked.emit(picked)
		accept_event()


## 命中最近的缩略点（半径 6px 内）。
func tile_at(position: Vector2) -> String:
	_rebuild_points()
	var best: String = ""
	var best_distance: float = 6.0
	for tile_id: String in _points:
		var point: Vector2 = _points[tile_id] as Vector2
		var distance: float = point.distance_to(position)
		if distance <= best_distance:
			best_distance = distance
			best = tile_id
	return best


# --- 供自动验收断言 ---

func tile_point_count() -> int:
	return _points.size()


func last_picked() -> String:
	return _picked


func _terrain_color(base_terrain: String) -> Color:
	match base_terrain:
		"LING_FIELDS": return Color("a8c48d")
		"SPIRIT_PLAIN": return Color("b9cfa2")
		"BARREN": return Color("cfbb95")
	return Color("d8d2bf")
