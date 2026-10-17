class_name DaoTreePanel
extends CanvasLayer
## 道统树界面（对齐参考图「青云宗道法修行树」）。
##
## 结构：整幅卷轴 + 左侧竖排题签「道法」；顶部三页签（宗门/家族/国家）；
## 中间是可滚动的道法树画布（`DaoTreeCanvas`）；右侧是弟子修行 / 灵根排行 /
## 突破记录 / 研究队列四张卡；底部三态图例。
##
## **客户端零规则**：节点三态、阻塞原因、消耗、前置关系全部来自服务端
## `daoOptions[]` / `unlockedDaoIds[]`，本类只做排版与筛选（页签筛选是纯展示过滤）。

signal research_requested(dao_id: String)

const FRAME_WIDTH: float = 1440.0
const FRAME_HEIGHT: float = 786.0
const RIGHT_COLUMN: float = 296.0

var root: ScrollFrame = null
var canvas: DaoTreeCanvas = null
var detail_card: PanelContainer = null
var detail_title: Label = null
var detail_body: Label = null
var detail_action: Button = null
var right_column: VBoxContainer = null
var tab_row: HBoxContainer = null
var legend_row: HBoxContainer = null

var _entries: Array = []
var _unlocked: Array[String] = []
var _tab: String = "ZONG_MEN"
var _tabs: Dictionary = {}
var _selected: Dictionary = {}


func setup() -> void:
	name = "DaoTreePanel"
	layer = 7

	var dim: ColorRect = ColorRect.new()
	dim.color = Color(0.06, 0.09, 0.08, 0.30)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	root = ScrollFrame.new()
	root.name = "Scroll"
	root.anchor_left = 0.5
	root.anchor_right = 0.5
	root.anchor_top = 0.5
	root.anchor_bottom = 0.5
	root.offset_left = -FRAME_WIDTH * 0.5
	root.offset_right = FRAME_WIDTH * 0.5
	root.offset_top = -FRAME_HEIGHT * 0.5
	root.offset_bottom = FRAME_HEIGHT * 0.5
	root.build("道法", 56, 0.975)
	add_child(root)

	var column: VBoxContainer = root.content
	column.add_theme_constant_override("separation", 8)

	# ① 页签行 + 关闭
	var header: HBoxContainer = HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	column.add_child(header)
	tab_row = HBoxContainer.new()
	tab_row.add_theme_constant_override("separation", 6)
	tab_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(tab_row)
	_tabs = {
		"ZONG_MEN": "宗门道法",
		"JIA_ZU": "家族道法",
		"GUO_JIA": "国家道法",
	}
	for key: String in ["ZONG_MEN", "JIA_ZU", "GUO_JIA"]:
		var tab: Button = Button.new()
		tab.name = "Tab_" + key
		tab.text = str(_tabs[key])
		tab.focus_mode = Control.FOCUS_NONE
		tab.pressed.connect(func() -> void: _switch_tab(key))
		tab_row.add_child(tab)
	var close: Button = Button.new()
	close.name = "CloseDao"
	close.text = "✕"
	close.tooltip_text = "关闭道统树"
	close.custom_minimum_size = Vector2(30, 26)
	close.pressed.connect(func() -> void: hide_panel())
	UiTheme.style_plain(close)
	header.add_child(close)

	column.add_child(UiTheme.ornament_divider())

	# ② 主体：树画布 + 右侧栏
	var body: HBoxContainer = HBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(body)

	var tree_holder: Control = Control.new()
	tree_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tree_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(tree_holder)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.name = "TreeScroll"
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	tree_holder.add_child(scroll)
	canvas = DaoTreeCanvas.new()
	canvas.name = "Tree"
	canvas.node_picked.connect(_on_node_picked)
	canvas.node_hovered.connect(_on_node_hovered)
	scroll.add_child(canvas)

	# 悬浮详情卡（贴在树区顶部中央）
	detail_card = PanelContainer.new()
	detail_card.name = "DetailCard"
	detail_card.anchor_left = 0.5
	detail_card.anchor_right = 0.5
	detail_card.offset_left = -150.0
	detail_card.offset_right = 150.0
	detail_card.offset_top = 4.0
	detail_card.add_theme_stylebox_override("panel", UiTheme.ink_card(0.94, 4))
	detail_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tree_holder.add_child(detail_card)
	var detail_box: VBoxContainer = VBoxContainer.new()
	detail_box.add_theme_constant_override("separation", 2)
	detail_card.add_child(detail_box)
	detail_title = Label.new()
	detail_title.add_theme_font_size_override("font_size", 14)
	detail_title.add_theme_color_override("font_color", Color("f0e9d6"))
	detail_box.add_child(detail_title)
	detail_body = Label.new()
	detail_body.add_theme_font_size_override("font_size", 11)
	detail_body.add_theme_color_override("font_color", Color(0.84, 0.82, 0.74, 0.92))
	detail_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_box.add_child(detail_body)
	detail_action = Button.new()
	detail_action.text = "研究"
	detail_action.visible = false
	detail_action.pressed.connect(_on_detail_action)
	detail_box.add_child(detail_action)
	detail_card.visible = false

	right_column = VBoxContainer.new()
	right_column.custom_minimum_size = Vector2(RIGHT_COLUMN, 0)
	right_column.add_theme_constant_override("separation", 8)
	body.add_child(right_column)

	# ③ 图例
	legend_row = HBoxContainer.new()
	legend_row.add_theme_constant_override("separation", 16)
	column.add_child(legend_row)
	for pair: Array in [["UNLOCKED", "已学"], ["AVAILABLE", "可研究"], ["BLOCKED", "未解锁"]]:
		legend_row.add_child(_legend_dot(str(pair[0]), str(pair[1])))

	visible = false


func _legend_dot(state: String, text: String) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	var dot: PanelContainer = PanelContainer.new()
	dot.custom_minimum_size = Vector2(11, 11)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.set_corner_radius_all(64)
	style.set_border_width_all(1)
	match state:
		"UNLOCKED":
			style.bg_color = UiTheme.JADE_DEEP
			style.border_color = UiTheme.GOLD_LIGHT
		"AVAILABLE":
			style.bg_color = Color(0.98, 0.965, 0.925)
			style.border_color = UiTheme.GOLD
		_:
			style.bg_color = Color(0.88, 0.875, 0.85)
			style.border_color = Color(0.62, 0.63, 0.60)
	dot.add_theme_stylebox_override("panel", style)
	row.add_child(dot)
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", UiTheme.INK_SOFT)
	row.add_child(label)
	return row


## 填充并显示。`data` 字段见文件头；缺失字段一律降级为空，不崩。
func show_tree(data: Dictionary) -> void:
	_entries = data.get("entries", [])
	_unlocked.clear()
	for entry: Variant in data.get("unlocked", []):
		_unlocked.append(str(entry))
	_refresh_tabs()
	_refresh_tree()
	_refresh_right_column(data)
	visible = true


func hide_panel() -> void:
	visible = false


func _switch_tab(key: String) -> void:
	_tab = key
	_refresh_tabs()
	_refresh_tree()


## 页签上的计数 = 该页签筛选后可见的道法条数（纯过滤统计）。
func _refresh_tabs() -> void:
	if tab_row == null:
		return
	for child: Node in tab_row.get_children():
		var button: Button = child as Button
		if button == null:
			continue
		var key: String = button.name.trim_prefix("Tab_")
		var count: int = _filtered(key).size()
		button.text = "%s %d" % [str(_tabs.get(key, key)), count]
		var active: bool = key == _tab
		var style: StyleBoxFlat = UiTheme.pill(UiTheme.JADE_DEEP if active else Color(0.86, 0.85, 0.80, 0.92))
		style.content_margin_left = 14.0
		style.content_margin_right = 14.0
		style.content_margin_top = 4.0
		style.content_margin_bottom = 4.0
		style.set_corner_radius_all(13)
		button.add_theme_stylebox_override("normal", style)
		button.add_theme_stylebox_override("hover", style)
		button.add_theme_stylebox_override("pressed", style)
		button.add_theme_color_override("font_color", UiTheme.PAPER if active else UiTheme.INK)
		button.add_theme_font_size_override("font_size", 13)


## 页签筛选：宗门=全部；家族=需血脉或家族专属；国家=国家专属。
func _filtered(key: String) -> Array:
	if key == "ZONG_MEN":
		return _entries
	var out: Array = []
	for entry: Dictionary in _entries:
		var faction: String = str(entry.get("factionOnly", ""))
		var blood: bool = bool(entry.get("requiresBloodLine", false))
		if key == "JIA_ZU" and (blood or faction == "JIA_ZU"):
			out.append(entry)
		elif key == "GUO_JIA" and faction == "GUO_JIA":
			out.append(entry)
	return out


func _refresh_tree() -> void:
	if canvas == null:
		return
	canvas.configure(_filtered(_tab), _unlocked)
	detail_card.visible = false


func _on_node_picked(entry: Dictionary) -> void:
	_selected = entry
	_show_detail(entry, true)


func _on_node_hovered(entry: Dictionary) -> void:
	_show_detail(entry, false)


func _show_detail(entry: Dictionary, actionable: bool) -> void:
	if detail_card == null or entry.is_empty():
		return
	detail_title.text = str(entry.get("name", ""))
	var lines: PackedStringArray = PackedStringArray()
	var desc: String = str(entry.get("desc", ""))
	if not desc.is_empty():
		lines.append(desc)
	lines.append("消耗：道点 %d · 工力 %d · %d 回合" % [
		int(entry.get("daoPointCost", 0)), int(entry.get("spiritPowerCost", 0)), int(entry.get("turns", 0))])
	var prerequisites: Array = entry.get("prerequisiteDaoIds", [])
	if not prerequisites.is_empty():
		var names: PackedStringArray = PackedStringArray()
		for prerequisite: Variant in prerequisites:
			names.append(_name_of(str(prerequisite)))
		lines.append("前置：%s" % "、".join(names))
	var blocker: String = str(entry.get("blocker", ""))
	if not blocker.is_empty():
		lines.append("阻塞：%s" % blocker)
	detail_body.text = "\n".join(lines)
	var state: String = str(entry.get("state", ""))
	detail_action.visible = actionable and state == "AVAILABLE"
	detail_action.text = "研究「%s」" % str(entry.get("name", ""))
	detail_card.visible = true


func _on_detail_action() -> void:
	var dao_id: String = str(_selected.get("id", ""))
	if not dao_id.is_empty():
		research_requested.emit(dao_id)


func _name_of(dao_id: String) -> String:
	for entry: Dictionary in _entries:
		if str(entry.get("id", "")) == dao_id:
			return str(entry.get("name", dao_id))
	return dao_id


# ---------------------------------------------------------------------------
# 右侧四张卡
# ---------------------------------------------------------------------------

func _refresh_right_column(data: Dictionary) -> void:
	if right_column == null:
		return
	for child: Node in right_column.get_children():
		right_column.remove_child(child)
		child.queue_free()

	# ① 弟子修行
	var disciple: Dictionary = data.get("disciple", {})
	right_column.add_child(_card("弟子修行", _disciple_body(disciple)))

	# ② 灵根排行（按 rootGrade 统计，全部来自 view 的 disciples[]）
	var roots: Array = data.get("roots", [])
	right_column.add_child(_card("灵根排行", _roots_body(roots)))

	# ③ 突破记录（从真实事件文案里筛「突破」，不造历史）
	var breaks: Array = data.get("breaks", [])
	right_column.add_child(_card("突破记录", _breaks_body(breaks)))

	# ④ 研究队列
	var queue: Array = data.get("queue", [])
	right_column.add_child(_card("研究队列", _queue_body(queue)))


func _card(title: String, body: Control) -> PanelContainer:
	var card: PanelContainer = PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiTheme.paper(0.94, 4, 1.0))
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	card.add_child(column)
	var band: PanelContainer = PanelContainer.new()
	band.add_theme_stylebox_override("panel", UiTheme.title_band())
	column.add_child(band)
	var label: Label = Label.new()
	label.text = "◈ " + title
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", UiTheme.PAPER)
	band.add_child(label)
	column.add_child(body)
	return card


func _disciple_body(disciple: Dictionary) -> VBoxContainer:
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	if disciple.is_empty():
		column.add_child(UiTheme.body_label("（本宗暂无弟子）", 11, UiTheme.INK_FAINT))
		return column
	var head: HBoxContainer = HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	column.add_child(head)
	# 立绘框：程序化墨像（无插画资源，用纸框 + 宗门色墨块 + 姓氏字占位）
	var portrait: PanelContainer = PanelContainer.new()
	portrait.custom_minimum_size = Vector2(46, 58)
	portrait.add_theme_stylebox_override("panel", UiTheme.paper(0.98, 3, 1.0))
	head.add_child(portrait)
	var glyph: Label = Label.new()
	var name_text: String = str(disciple.get("name", ""))
	glyph.text = name_text.substr(0, 1) if not name_text.is_empty() else "修"
	glyph.add_theme_font_size_override("font_size", 24)
	glyph.add_theme_color_override("font_color", UiTheme.JADE_DEEP)
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	portrait.add_child(glyph)

	var info: VBoxContainer = VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 2)
	head.add_child(info)
	var title: Label = Label.new()
	title.text = name_text
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", UiTheme.INK)
	info.add_child(title)
	var realm: Label = Label.new()
	realm.text = str(disciple.get("realmLabel", ""))
	realm.add_theme_font_size_override("font_size", 11)
	realm.add_theme_color_override("font_color", UiTheme.INK_SOFT)
	info.add_child(realm)

	var progress_bar: RatioBar = RatioBar.new()
	progress_bar.setup(UiTheme.JADE, 5)
	progress_bar.set_ratio(float(disciple.get("progressRatio", 0.0)))
	column.add_child(progress_bar)
	var progress_text: Label = Label.new()
	progress_text.text = str(disciple.get("progressText", ""))
	progress_text.add_theme_font_size_override("font_size", 10)
	progress_text.add_theme_color_override("font_color", UiTheme.INK_FAINT)
	progress_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	column.add_child(progress_text)

	for pair: Array in disciple.get("rows", []):
		column.add_child(_kv_row(str(pair[0]), str(pair[1])))
	return column


func _kv_row(key: String, value: String) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var key_label: Label = Label.new()
	key_label.text = key
	key_label.add_theme_font_size_override("font_size", 11)
	key_label.add_theme_color_override("font_color", UiTheme.INK_FAINT)
	key_label.custom_minimum_size = Vector2(46, 0)
	row.add_child(key_label)
	var value_label: Label = Label.new()
	value_label.text = value
	value_label.add_theme_font_size_override("font_size", 11)
	value_label.add_theme_color_override("font_color", UiTheme.INK_SOFT)
	value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value_label)
	return row


func _roots_body(roots: Array) -> VBoxContainer:
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	if roots.is_empty():
		column.add_child(UiTheme.body_label("（暂无弟子）", 11, UiTheme.INK_FAINT))
		return column
	var max_count: int = 1
	for entry: Variant in roots:
		max_count = maxi(max_count, int((entry as Dictionary).get("count", 0)))
	for entry: Variant in roots:
		var item: Dictionary = entry
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var dot: PanelContainer = PanelContainer.new()
		dot.custom_minimum_size = Vector2(8, 8)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		dot.add_theme_stylebox_override("panel", UiTheme.seal(UiTheme.resource_color(str(item.get("key", ""))), Color(0, 0, 0, 0)))
		row.add_child(dot)
		var name_label: Label = Label.new()
		name_label.text = str(item.get("label", ""))
		name_label.add_theme_font_size_override("font_size", 11)
		name_label.add_theme_color_override("font_color", UiTheme.INK_SOFT)
		name_label.custom_minimum_size = Vector2(40, 0)
		row.add_child(name_label)
		var bar: RatioBar = RatioBar.new()
		bar.setup(UiTheme.JADE, 5)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.set_ratio(float(int(item.get("count", 0))) / float(max_count))
		row.add_child(bar)
		var count_label: Label = Label.new()
		count_label.text = "%d 人" % int(item.get("count", 0))
		count_label.add_theme_font_size_override("font_size", 10)
		count_label.add_theme_color_override("font_color", UiTheme.INK_FAINT)
		count_label.custom_minimum_size = Vector2(38, 0)
		count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(count_label)
		column.add_child(row)
	return column


func _breaks_body(breaks: Array) -> VBoxContainer:
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	if breaks.is_empty():
		column.add_child(UiTheme.body_label("（本局尚无突破记录）", 11, UiTheme.INK_FAINT))
		return column
	for entry: Variant in breaks:
		var item: Dictionary = entry
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var mark: Label = Label.new()
		mark.text = "✦"
		mark.add_theme_font_size_override("font_size", 10)
		mark.add_theme_color_override("font_color", Color("a8382c"))
		row.add_child(mark)
		var text: Label = Label.new()
		text.text = str(item.get("text", ""))
		text.add_theme_font_size_override("font_size", 10)
		text.add_theme_color_override("font_color", UiTheme.INK_SOFT)
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text)
		column.add_child(row)
	return column


func _queue_body(queue: Array) -> VBoxContainer:
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	if queue.is_empty():
		column.add_child(UiTheme.body_label("（研究队列为空）", 11, UiTheme.INK_FAINT))
		return column
	for entry: Variant in queue:
		var item: Dictionary = entry
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var name_label: Label = Label.new()
		name_label.text = str(item.get("name", item.get("id", "?")))
		name_label.add_theme_font_size_override("font_size", 11)
		name_label.add_theme_color_override("font_color", UiTheme.INK)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		var remain: Label = Label.new()
		remain.text = "剩 %d/%d 回合" % [int(item.get("turnsRemaining", 0)), int(item.get("turnsRequired", 0))]
		remain.add_theme_font_size_override("font_size", 10)
		remain.add_theme_color_override("font_color", UiTheme.INK_FAINT)
		row.add_child(remain)
		column.add_child(row)
	return column


# --- 供自动验收断言 ---

func tree_node_count() -> int:
	return 0 if canvas == null else canvas.node_count()


func tree_depth_count() -> int:
	return 0 if canvas == null else canvas.depth_count()


func current_tab() -> String:
	return _tab


func detail_visible() -> bool:
	return detail_card != null and detail_card.visible
