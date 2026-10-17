class_name TurnSummary
extends CanvasLayer
## 回合结算界面（对齐参考图「仙门回合结算：青云宗崛起」）。
##
## 布局：整幅卷轴 + 左侧竖排题签「回合结算」，内部三栏——
##   ① 资源收支（图标 + 名称 + 增减值，末行本回合净收入）
##   ② 重要事件（缩略图卡片 + 「新」角标）
##   ③ 事件时间线（圆形节点 + 回合 + 时间 + 文案）
## 底部居中青玉药丸「下一回合」。
##
## 数据来源（**全部是服务端下发过的值，客户端不推导任何规则**）：
##   - 资源增减：`view.sects[player].resources` 在「上一帧 view」与「当前 view」之间的差值。
##     服务端 2.0 不下发回合结算报告，故这是客户端对两帧 view 的算术，不是规则推导。
##   - 事件：回包信封里的 `events[]`（纯字符串），由 `Session.events_received` 累积。
##
## 不触碰相机（相机铁律），不改任何玩法状态。
##
## **关闭路径**：卷轴是带全屏遮罩（`MOUSE_FILTER_STOP`）的模态层，弹出期间世界不可点。
## 因此它必须自带出口，否则玩家除了「下一回合」什么都点不到——这正是 R10 玩家反馈的
## 「点完下个回合之后界面只能点下个回合」。三个出口：点遮罩、点「返回 · 继续经营」、Esc
## （Esc 走 `World._close_all_panels()`，那里也登记了本卷轴）。

## 玩家主动关闭卷轴（点遮罩 / 点返回按钮）。`World` 连接后收起。
signal close_requested

## 结算卷轴尺寸。高度取 470 而不是更高：结算内容通常只有 4~6 行资源 + 2~3 张事件卡，
## 卷轴再高下半幅就会空着，看着像渲染没画完。
const FRAME_WIDTH: float = 1200.0
const FRAME_HEIGHT: float = 470.0
## 单栏宽度。
const COL_RESOURCE: float = 336.0
const COL_EVENT: float = 400.0
const COL_TIMELINE: float = 330.0

var root: ScrollFrame = null
var resource_column: VBoxContainer = null
var event_column: VBoxContainer = null
var timeline_column: VBoxContainer = null
var net_label: Label = null
var next_button: Button = null
## 次要出口：只收起卷轴，不推进回合。
var close_button: Button = null
var title_label: Label = null

var _assets: AssetLibrary = null
var _dim: ColorRect = null


func setup(assets: AssetLibrary) -> void:
	name = "TurnSummary"
	layer = 6
	_assets = assets

	_dim = ColorRect.new()
	_dim.name = "Dim"
	_dim.color = Color(0.06, 0.09, 0.08, 0.22)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	# 点卷轴以外的暗底即关闭（模态层的通用习惯，也给不想找按钮的玩家留一条路）。
	_dim.gui_input.connect(_on_dim_input)
	add_child(_dim)

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
	root.build("回合结算", 56, 0.975)
	add_child(root)

	var column: VBoxContainer = root.content
	column.add_theme_constant_override("separation", 10)

	# 顶部一行：回合标题（左）+ 小字落款（右）
	var header: HBoxContainer = HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	column.add_child(header)
	title_label = Label.new()
	title_label.name = "TurnTitle"
	title_label.text = "第 1 回合 · 春 · 修行期"
	title_label.add_theme_font_size_override("font_size", 17)
	title_label.add_theme_color_override("font_color", UiTheme.INK)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_label)
	var motto: Label = Label.new()
	motto.text = "天地逆旅 · 万物生息"
	motto.add_theme_font_size_override("font_size", 11)
	motto.add_theme_color_override("font_color", UiTheme.INK_FAINT)
	motto.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(motto)

	column.add_child(UiTheme.ornament_divider())

	var row: HBoxContainer = HBoxContainer.new()
	row.name = "Columns"
	row.add_theme_constant_override("separation", 12)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(row)

	resource_column = _make_column(row, "资源收支", COL_RESOURCE)
	event_column = _make_column(row, "重要事件", COL_EVENT)
	timeline_column = _make_column(row, "事件时间线", COL_TIMELINE)

	# 底部：居中「下一回合」药丸
	var footer: HBoxContainer = HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(footer)
	next_button = Button.new()
	next_button.name = "NextTurnButton"
	next_button.text = "下一回合"
	next_button.tooltip_text = "finishTurn → beginPlayerTurn；期间相机角度与缩放保持不变"
	next_button.add_theme_stylebox_override("normal", UiTheme.pill(UiTheme.JADE_DEEP))
	var hover: StyleBoxFlat = UiTheme.pill(UiTheme.JADE)
	next_button.add_theme_stylebox_override("hover", hover)
	var pressed: StyleBoxFlat = UiTheme.pill(UiTheme.JADE_DEEP.darkened(0.18))
	next_button.add_theme_stylebox_override("pressed", pressed)
	next_button.add_theme_color_override("font_color", UiTheme.PAPER)
	next_button.add_theme_color_override("font_hover_color", Color.WHITE)
	next_button.add_theme_font_size_override("font_size", 16)
	next_button.custom_minimum_size = Vector2(190, 40)
	next_button.pressed.connect(_on_next_pressed)
	footer.add_child(next_button)

	# 次要出口：**不推进回合**，只收起卷轴回到山河图。
	# 主操作仍是「下一回合」（对齐参考图的青玉药丸），但玩家必须有办法留在当前回合继续经营。
	var spacer: Control = Control.new()
	spacer.custom_minimum_size = Vector2(14, 0)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	footer.add_child(spacer)
	close_button = Button.new()
	close_button.name = "CloseButton"
	close_button.text = "返回 · 继续经营"
	close_button.tooltip_text = "收起结算卷轴，留在本回合继续操作（Esc 同效）"
	close_button.custom_minimum_size = Vector2(164, 40)
	UiTheme.style_plain(close_button)
	close_button.pressed.connect(_on_dismiss)
	footer.add_child(close_button)

	visible = false


## 点暗底：左键按下即关闭。
func _on_dim_input(event: InputEvent) -> void:
	var mouse: InputEventMouseButton = event as InputEventMouseButton
	if mouse == null or not mouse.pressed or mouse.button_index != MOUSE_BUTTON_LEFT:
		return
	_on_dismiss()


## 收起卷轴并通知 `World`。重复调用安全（已隐藏时直接返回）。
func _on_dismiss() -> void:
	if not visible:
		return
	visible = false
	close_requested.emit()


## 建一栏：标题带 + 可滚动内容区，返回内容容器。
func _make_column(parent: HBoxContainer, title: String, width: float) -> VBoxContainer:
	var holder: VBoxContainer = VBoxContainer.new()
	holder.custom_minimum_size = Vector2(width, 0)
	holder.add_theme_constant_override("separation", 6)
	parent.add_child(holder)

	var band: PanelContainer = PanelContainer.new()
	band.add_theme_stylebox_override("panel", UiTheme.title_band())
	holder.add_child(band)
	var band_label: Label = Label.new()
	band_label.text = "◈ " + title
	band_label.add_theme_font_size_override("font_size", 13)
	band_label.add_theme_color_override("font_color", UiTheme.PAPER)
	band.add_child(band_label)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	holder.add_child(scroll)
	var content: VBoxContainer = VBoxContainer.new()
	content.name = "List"
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 5)
	scroll.add_child(content)
	return content


## 填充数据并显示。`data` 见文件头注释。
func show_summary(data: Dictionary) -> void:
	if title_label != null:
		title_label.text = str(data.get("heading", "第 1 回合 · 春 · 修行期"))
	_fill_resources(data.get("resources", []), int(data.get("net", 0)), bool(data.get("hasBaseline", false)))
	_fill_events(data.get("events", []))
	_fill_timeline(data.get("timeline", []))
	visible = true


func hide_summary() -> void:
	visible = false


func _on_next_pressed() -> void:
	visible = false
	Session.request_end_turn_sequence()


# ---------------------------------------------------------------------------
# ① 资源收支
# ---------------------------------------------------------------------------

func _fill_resources(rows: Array, net: int, has_baseline: bool) -> void:
	if resource_column == null:
		return
	for child: Node in resource_column.get_children():
		resource_column.remove_child(child)
		child.queue_free()
	if rows.is_empty():
		var empty: Label = UiTheme.body_label("（未开局，无收支）", 12, UiTheme.INK_FAINT)
		resource_column.add_child(empty)
		return
	for entry: Variant in rows:
		var row_data: Dictionary = entry
		var key: String = str(row_data.get("key", ""))
		var icon: Texture2D = null
		if _assets != null:
			var resource: Resource = _assets.resource_for("resource." + key, "texture")
			if resource is Texture2D:
				icon = resource as Texture2D
		var row: HBoxContainer = UiTheme.resource_row(
			icon, str(row_data.get("label", key)), int(row_data.get("delta", 0)))
		row.name = "Res_" + key.replace(".", "_")
		resource_column.add_child(row)

	resource_column.add_child(UiTheme.ornament_divider())

	var net_row: HBoxContainer = HBoxContainer.new()
	net_row.add_theme_constant_override("separation", 8)
	resource_column.add_child(net_row)
	var net_title: Label = Label.new()
	net_title.text = "本回合净收入"
	net_title.add_theme_font_size_override("font_size", 13)
	net_title.add_theme_color_override("font_color", UiTheme.INK)
	net_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	net_row.add_child(net_title)
	net_label = Label.new()
	net_label.name = "NetTotal"
	net_label.text = ("+%d" % net) if net >= 0 else str(net)
	net_label.add_theme_font_size_override("font_size", 15)
	net_label.add_theme_color_override("font_color", Color("a8382c") if net >= 0 else Color("2f6b4f"))
	net_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	net_label.custom_minimum_size = Vector2(72, 0)
	net_row.add_child(net_label)

	if not has_baseline:
		var note: Label = UiTheme.body_label("首回合无对比基线，数值为 0", 10, UiTheme.INK_FAINT)
		resource_column.add_child(note)


# ---------------------------------------------------------------------------
# ② 重要事件（缩略图卡片）
# ---------------------------------------------------------------------------

func _fill_events(events: Array) -> void:
	if event_column == null:
		return
	for child: Node in event_column.get_children():
		event_column.remove_child(child)
		child.queue_free()
	if events.is_empty():
		event_column.add_child(UiTheme.body_label("（本回合无重要事件）", 12, UiTheme.INK_FAINT))
		return
	for entry: Variant in events:
		var item: Dictionary = entry
		event_column.add_child(_event_card(item))


func _event_card(item: Dictionary) -> PanelContainer:
	var card: PanelContainer = PanelContainer.new()
	card.name = "Event_" + str(item.get("id", "x"))
	card.add_theme_stylebox_override("panel", UiTheme.paper(0.92, 4, 1.0))
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	card.add_child(row)

	# 缩略图：无对应插画资源，用「深青墨块 + 类目字形」占位（与水墨风一致）。
	var thumb: PanelContainer = PanelContainer.new()
	thumb.custom_minimum_size = Vector2(58, 44)
	thumb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	thumb.add_theme_stylebox_override("panel", UiTheme.ink_card(0.92, 2))
	row.add_child(thumb)
	var glyph: Label = Label.new()
	glyph.text = str(item.get("glyph", "✦"))
	glyph.add_theme_font_size_override("font_size", 22)
	glyph.add_theme_color_override("font_color", Color(0.86, 0.83, 0.72, 0.92))
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	thumb.add_child(glyph)

	var text_column: VBoxContainer = VBoxContainer.new()
	text_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_column.add_theme_constant_override("separation", 1)
	row.add_child(text_column)
	var head: HBoxContainer = HBoxContainer.new()
	text_column.add_child(head)
	var title: Label = Label.new()
	title.text = str(item.get("title", ""))
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", UiTheme.INK)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	if bool(item.get("fresh", false)):
		head.add_child(UiTheme.new_badge())
	var detail: Label = Label.new()
	detail.text = str(item.get("detail", ""))
	detail.add_theme_font_size_override("font_size", 11)
	detail.add_theme_color_override("font_color", UiTheme.INK_SOFT)
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_column.add_child(detail)
	return card


# ---------------------------------------------------------------------------
# ③ 事件时间线
# ---------------------------------------------------------------------------

func _fill_timeline(items: Array) -> void:
	if timeline_column == null:
		return
	for child: Node in timeline_column.get_children():
		timeline_column.remove_child(child)
		child.queue_free()
	if items.is_empty():
		timeline_column.add_child(UiTheme.body_label("（暂无时间线）", 12, UiTheme.INK_FAINT))
		return
	for entry: Variant in items:
		var item: Dictionary = entry
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		# 圆形节点：深青底 + 金字形。
		var node_holder: VBoxContainer = VBoxContainer.new()
		node_holder.add_theme_constant_override("separation", 0)
		row.add_child(node_holder)
		var dot: PanelContainer = PanelContainer.new()
		dot.custom_minimum_size = Vector2(22, 22)
		dot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		dot.add_theme_stylebox_override("panel", UiTheme.seal(UiTheme.JADE_DEEP, UiTheme.GOLD_LIGHT))
		node_holder.add_child(dot)
		var dot_glyph: Label = Label.new()
		dot_glyph.text = str(item.get("glyph", "◆"))
		dot_glyph.add_theme_font_size_override("font_size", 10)
		dot_glyph.add_theme_color_override("font_color", Color("f4efe3"))
		dot_glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		dot_glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		dot.add_child(dot_glyph)

		var text_column: VBoxContainer = VBoxContainer.new()
		text_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text_column.add_theme_constant_override("separation", 0)
		row.add_child(text_column)
		var stamp: Label = Label.new()
		stamp.text = str(item.get("stamp", ""))
		stamp.add_theme_font_size_override("font_size", 10)
		stamp.add_theme_color_override("font_color", UiTheme.INK_FAINT)
		text_column.add_child(stamp)
		var body: Label = Label.new()
		body.text = str(item.get("text", ""))
		body.add_theme_font_size_override("font_size", 12)
		body.add_theme_color_override("font_color", UiTheme.INK_SOFT)
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text_column.add_child(body)
		timeline_column.add_child(row)
