class_name DaoTreeCanvas
extends Control
## 道法修行树的「画布」：按前置关系分层排布节点，并画出层间连线。
##
## 布局是**纯几何**：`depth(id) = 0（无前置）或 1 + max(depth(前置))`，
## 同层内按 `eraIndex` + 原顺序排开。不读任何随机源，同输入必然同布局（确定性）。
##
## 节点三态配色由 `state` 决定（UNLOCKED / RESEARCHING / AVAILABLE / BLOCKED），
## 客户端不判定状态——`state` 与 `blocker` 全部来自服务端 `daoOptions`。

signal node_picked(entry: Dictionary)
signal node_hovered(entry: Dictionary)

## 单节点占位（含下方文字）。
const CELL_WIDTH: float = 104.0
const CELL_HEIGHT: float = 100.0
## 圆徽直径。
const NODE_SIZE: float = 44.0
## 层间距（相邻两层的 y 差）。
const ROW_GAP: float = 14.0

var entries: Array = []
var unlocked: Array[String] = []

var _nodes: Dictionary = {}
var _depth_of: Dictionary = {}
var _positions: Dictionary = {}


func configure(dao_entries: Array, unlocked_ids: Array[String]) -> void:
	entries = dao_entries
	unlocked = unlocked_ids
	_layout()
	queue_redraw()


## 计算深度、坐标并重建节点控件。
func _layout() -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	_nodes.clear()
	_depth_of.clear()
	_positions.clear()
	if entries.is_empty():
		custom_minimum_size = Vector2(400, 200)
		return

	var by_id: Dictionary = {}
	for entry: Dictionary in entries:
		by_id[str(entry.get("id", ""))] = entry
	for entry: Dictionary in entries:
		_depth_of[str(entry.get("id", ""))] = _resolve_depth(str(entry.get("id", "")), by_id, 0)

	# 按深度分桶
	var layers: Dictionary = {}
	var max_depth: int = 0
	for entry: Dictionary in entries:
		var depth: int = int(_depth_of.get(str(entry.get("id", "")), 0))
		max_depth = maxi(max_depth, depth)
		if not layers.has(depth):
			layers[depth] = []
		(layers[depth] as Array).append(entry)

	var widest: int = 1
	for depth: int in layers.keys():
		widest = maxi(widest, (layers[depth] as Array).size())
	var canvas_width: float = maxf(widest * CELL_WIDTH + 40.0, 520.0)
	var canvas_height: float = float(max_depth + 1) * (CELL_HEIGHT + ROW_GAP) + 20.0
	custom_minimum_size = Vector2(canvas_width, canvas_height)

	for depth: int in layers.keys():
		var bucket: Array = layers[depth]
		bucket.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var ea: int = int(a.get("eraIndex", 0))
			var eb: int = int(b.get("eraIndex", 0))
			if ea != eb:
				return ea < eb
			return str(a.get("id", "")) < str(b.get("id", "")))
		var count: int = bucket.size()
		for index: int in range(count):
			var entry: Dictionary = bucket[index]
			var x: float = canvas_width * float(index + 1) / float(count + 1)
			var y: float = 16.0 + float(depth) * (CELL_HEIGHT + ROW_GAP)
			var node_id: String = str(entry.get("id", ""))
			_positions[node_id] = Vector2(x, y)
			var node: Control = _make_node(entry)
			node.position = Vector2(x - CELL_WIDTH * 0.5, y)
			add_child(node)
			_nodes[node_id] = node


## 递归求深度（前置缺失时按 0 处理，不崩）。
func _resolve_depth(dao_id: String, by_id: Dictionary, guard: int) -> int:
	if guard > 8 or not by_id.has(dao_id):
		return 0
	var entry: Dictionary = by_id[dao_id]
	var prerequisites: Array = entry.get("prerequisiteDaoIds", [])
	if prerequisites.is_empty():
		return 0
	var best: int = 0
	for prerequisite: Variant in prerequisites:
		best = maxi(best, _resolve_depth(str(prerequisite), by_id, guard + 1) + 1)
	return best


## 建一个节点：圆徽（含首字）+ 名称 + 进度，最上面盖一枚透明按钮吃点击。
func _make_node(entry: Dictionary) -> Control:
	var holder: Control = Control.new()
	holder.custom_minimum_size = Vector2(CELL_WIDTH, CELL_HEIGHT)
	holder.size = Vector2(CELL_WIDTH, CELL_HEIGHT)
	holder.name = "Node_" + str(entry.get("id", ""))

	var state: String = str(entry.get("state", "BLOCKED"))
	var name_text: String = str(entry.get("name", ""))
	var glyph_text: String = name_text.substr(0, 1) if not name_text.is_empty() else "?"

	var circle: PanelContainer = PanelContainer.new()
	circle.custom_minimum_size = Vector2(NODE_SIZE, NODE_SIZE)
	circle.size = Vector2(NODE_SIZE, NODE_SIZE)
	circle.position = Vector2((CELL_WIDTH - NODE_SIZE) * 0.5, 0.0)
	circle.add_theme_stylebox_override("panel", _node_style(state))
	holder.add_child(circle)
	var glyph: Label = Label.new()
	glyph.text = glyph_text
	glyph.add_theme_font_size_override("font_size", 20)
	glyph.add_theme_color_override("font_color", _glyph_color(state))
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	circle.add_child(glyph)

	var name_label: Label = Label.new()
	name_label.text = name_text
	name_label.add_theme_font_size_override("font_size", 11)
	name_label.add_theme_color_override("font_color", UiTheme.INK if state != "BLOCKED" else UiTheme.INK_FAINT)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.position = Vector2(0.0, NODE_SIZE + 3.0)
	name_label.size = Vector2(CELL_WIDTH, 16)
	holder.add_child(name_label)

	var progress: Label = Label.new()
	progress.text = _progress_text(entry)
	progress.add_theme_font_size_override("font_size", 9)
	progress.add_theme_color_override("font_color", UiTheme.INK_FAINT)
	progress.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	progress.position = Vector2(0.0, NODE_SIZE + 19.0)
	progress.size = Vector2(CELL_WIDTH, 14)
	holder.add_child(progress)

	# 透明按钮盖住整个单元格：负责点击与 tooltip（圆徽本身不做交互）。
	var hit: Button = Button.new()
	hit.name = "Hit"
	hit.flat = true
	hit.focus_mode = Control.FOCUS_NONE
	hit.position = Vector2.ZERO
	hit.size = Vector2(CELL_WIDTH, CELL_HEIGHT)
	hit.tooltip_text = _tooltip_text(entry)
	for slot: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		var empty: StyleBoxEmpty = StyleBoxEmpty.new()
		hit.add_theme_stylebox_override(slot, empty)
	hit.pressed.connect(func() -> void: node_picked.emit(entry))
	hit.mouse_entered.connect(func() -> void: node_hovered.emit(entry))
	holder.add_child(hit)
	return holder


func _node_style(state: String) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.set_corner_radius_all(64)
	style.set_border_width_all(2)
	match state:
		"UNLOCKED":
			style.bg_color = UiTheme.JADE_DEEP
			style.border_color = UiTheme.GOLD_LIGHT
		"RESEARCHING":
			style.bg_color = Color("8a6a2a")
			style.border_color = UiTheme.GOLD_LIGHT
		"AVAILABLE":
			style.bg_color = Color(0.98, 0.965, 0.925, 0.98)
			style.border_color = UiTheme.GOLD
		_:
			style.bg_color = Color(0.88, 0.875, 0.85, 0.85)
			style.border_color = Color(0.62, 0.63, 0.60, 0.80)
	return style


func _glyph_color(state: String) -> Color:
	match state:
		"UNLOCKED", "RESEARCHING":
			return Color("f4efe3")
		"AVAILABLE":
			return UiTheme.JADE_DEEP
	return Color("8b8f8c")


## 进度文案：已解锁显示「已学」，推演中显示「推演中」，其余显示消耗。
func _progress_text(entry: Dictionary) -> String:
	match str(entry.get("state", "")):
		"UNLOCKED":
			return "已学"
		"RESEARCHING":
			return "推演中"
		"AVAILABLE":
			return "道点 %d" % int(entry.get("daoPointCost", 0))
	return "未解锁"


func _tooltip_text(entry: Dictionary) -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append(str(entry.get("name", "")))
	var desc: String = str(entry.get("desc", ""))
	if not desc.is_empty():
		lines.append(desc)
	lines.append("道点 %d · 工力 %d · %d 回合" % [
		int(entry.get("daoPointCost", 0)), int(entry.get("spiritPowerCost", 0)), int(entry.get("turns", 0))])
	var blocker: String = str(entry.get("blocker", ""))
	if not blocker.is_empty():
		lines.append("阻塞：%s" % blocker)
	return "\n".join(lines)


func _draw() -> void:
	if _positions.is_empty():
		return
	# 先画线，再让节点控件盖在上面。
	for entry: Dictionary in entries:
		var child_id: String = str(entry.get("id", ""))
		if not _positions.has(child_id):
			continue
		var child_pos: Vector2 = _positions[child_id]
		var from: Vector2 = child_pos + Vector2(0.0, NODE_SIZE * 0.5)
		for prerequisite: Variant in entry.get("prerequisiteDaoIds", []):
			var parent_id: String = str(prerequisite)
			if not _positions.has(parent_id):
				continue
			var parent_pos: Vector2 = _positions[parent_id]
			var to: Vector2 = parent_pos + Vector2(0.0, NODE_SIZE * 0.5)
			var unlocked_edge: bool = unlocked.has(parent_id) and unlocked.has(child_id)
			var color: Color = Color(UiTheme.GOLD.r, UiTheme.GOLD.g, UiTheme.GOLD.b, 0.55) \
				if unlocked_edge else Color(0.55, 0.56, 0.53, 0.42)
			draw_polyline(_curve(to, from), color, 1.6, true)


## 两节点之间的竖向缓弯（贝塞尔采样 12 段）。
static func _curve(from: Vector2, to: Vector2) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	var mid_y: float = (from.y + to.y) * 0.5
	for step: int in range(13):
		var t: float = float(step) / 12.0
		var p0: Vector2 = from
		var p1: Vector2 = Vector2(from.x, mid_y)
		var p2: Vector2 = Vector2(to.x, mid_y)
		var p3: Vector2 = to
		var mt: float = 1.0 - t
		var point: Vector2 = p0 * (mt * mt * mt) + p1 * (3.0 * mt * mt * t) \
			+ p2 * (3.0 * mt * t * t) + p3 * (t * t * t)
		points.append(point)
	return points


# --- 供自动验收断言 ---

func node_count() -> int:
	return _nodes.size()


func depth_count() -> int:
	if _depth_of.is_empty():
		return 0
	var deepest: int = 0
	for value: Variant in _depth_of.values():
		deepest = maxi(deepest, int(value))
	return deepest + 1
