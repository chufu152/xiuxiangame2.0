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
		var color: Color = Color("efe9d8")
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
	for tile_id: String in tiles:
		var item: Dictionary = tiles[tile_id]
		var flat: Vector2 = Vector2(float(item["q"]) * 1.5, (float(item["r"]) + float(item["q"]) * 0.5) * Hex.SQRT3)
		_points[tile_id] = _to_control(flat)
	queue_redraw()


func set_view(center: Vector3, ortho_size: float) -> void:
	view_center = center
	view_size = ortho_size
	queue_redraw()


func _to_control(flat: Vector2) -> Vector2:
	var span: Vector2 = _bounds.size
	var usable: Vector2 = Vector2(MAP_SIZE - PADDING * 2.0, MAP_SIZE - PADDING * 2.0)
	var scale_value: float = minf(usable.x / maxf(span.x, 0.001), usable.y / maxf(span.y, 0.001))
	var center_flat: Vector2 = _bounds.position + span * 0.5
	return Vector2(MAP_SIZE * 0.5, MAP_SIZE * 0.5) + (flat - center_flat) * scale_value


func _draw() -> void:
	var background: Color = Color(0.93, 0.90, 0.82, 0.92)
	draw_rect(Rect2(Vector2.ZERO, Vector2(MAP_SIZE, MAP_SIZE)), background, true)
	draw_rect(Rect2(Vector2.ZERO, Vector2(MAP_SIZE, MAP_SIZE)), Color("b6ad8b"), false, 1.5)
	for tile_id: String in _points:
		var point: Vector2 = _points[tile_id] as Vector2
		var color: Color = (tiles[tile_id] as Dictionary)["color"] as Color
		draw_circle(point, 2.4, color)
	# 视口框：世界坐标 → 小地图坐标（与地块同一线性映射）。
	var corners: PackedVector2Array = PackedVector2Array()
	var half: float = view_size * 0.5
	for offset: Vector2 in [Vector2(-half, -half), Vector2(half, -half), Vector2(half, half), Vector2(-half, half)]:
		var world: Vector3 = view_center + Vector3(offset.x, 0.0, offset.y)
		var flat: Vector2 = Vector2(world.x / (Hex.SQRT3 * 1.0) * 1.0, world.z / (Hex.SQRT3 * 1.0) * 1.0)
		corners.append(_to_control(flat))
	draw_polyline(corners + PackedVector2Array([corners[0]]), Color(0.85, 0.64, 0.24, 0.95), 1.5)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var picked: String = tile_at(event.position)
		if not picked.is_empty():
			_picked = picked
			tile_picked.emit(picked)
		accept_event()


## 命中最近的缩略点（半径 6px 内）。
func tile_at(position: Vector2) -> String:
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
		"LING_FIELDS": return Color("9bb98b")
		"SPIRIT_PLAIN": return Color("bed0ac")
		"BARREN": return Color("d0b894")
	return Color("e7e2d3")
