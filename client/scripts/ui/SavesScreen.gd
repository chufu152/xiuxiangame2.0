class_name SavesScreen
extends CanvasLayer
## 存档界面（对齐参考图「水墨仙侠存档界面」）。
##
## 结构：全屏压暗 → 居中卷轴（题签「存档」）→ 三栏
##   左：竖排导航（存档 / 读取 / 设置 / 返回）+ 底部题诗
##   中：6 个存档槽卡片（序号徽章 + 缩略图 + 宗门 + 流派 + 回合 + 时间 + 体积 + 三枚动作钮）
##   右：选中槽的详情卡（大缩略图 + 元信息 + 存档内容 + 装饰落款）
##
## 数据全部来自 `listSaves` 回包的 7 个字段
## （`slotId / turn / playerSectName / factionType / savedAt / filePath / fileSize`）。
## 回包里**没有**缩略图与难度，故缩略图由槽号哈希程序化绘制（确定性、不联网、不读盘），
## 难度一行不显示——不臆造服务端没下发的字段。
##
## 协议 2.0 只有 `listSaves` / `saveGame` / `loadGame`，**没有 deleteSave**，
## 故「删除」按钮固定置灰并在 tooltip 里说明原因。

signal load_requested(slot: int)
signal save_requested(slot: int)
signal refresh_requested()

const FRAME_WIDTH: float = 1500.0
const FRAME_HEIGHT: float = 812.0
const NAV_WIDTH: float = 152.0
const DETAIL_WIDTH: float = 300.0
const SLOT_HEIGHT: float = 92.0
const SLOT_COUNT: int = 6
## 槽 0 是服务端每 10 回合写的自动存档（`SaveManager` 约定）。
const AUTO_SLOT: int = 0

const FACTION_NAMES: Dictionary = {"ZONG_MEN": "宗门", "JIA_ZU": "家族", "GUO_JIA": "国家"}

var root: ScrollFrame = null
var slot_column: VBoxContainer = null
var detail_column: VBoxContainer = null
var nav_column: VBoxContainer = null
var status_label: Label = null

var _saves: Dictionary = {}
var _selected: int = 0
var _nav: String = "存档"


func setup() -> void:
	layer = 7
	visible = false

	var dim: ColorRect = ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0.06, 0.09, 0.08, 0.30)
	dim.anchor_right = 1.0
	dim.anchor_bottom = 1.0
	add_child(dim)

	root = ScrollFrame.new()
	root.name = "Frame"
	root.anchor_left = 0.5
	root.anchor_right = 0.5
	root.anchor_top = 0.5
	root.anchor_bottom = 0.5
	root.offset_left = -FRAME_WIDTH * 0.5
	root.offset_right = FRAME_WIDTH * 0.5
	root.offset_top = -FRAME_HEIGHT * 0.5
	root.offset_bottom = FRAME_HEIGHT * 0.5
	add_child(root)
	root.build("存档", 62, 0.972)

	var header: HBoxContainer = HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	root.content.add_child(header)
	var title: Label = UiTheme.title_label("万界存档 · 卷宗", 17, UiTheme.INK)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	# 注意：`UiTheme.body_label` 默认开启自动换行，放进横向 HBox 会被挤成「一字一行」的竖排，
	# 进而把整行撑高数百像素（踩过一次）。此处必须显式关掉换行。
	var auto_note: Label = UiTheme.body_label("自动存档：槽 0（每 10 回合）", 11, UiTheme.INK_FAINT)
	auto_note.autowrap_mode = TextServer.AUTOWRAP_OFF
	auto_note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(auto_note)

	var close: Button = Button.new()
	close.name = "CloseSaves"
	close.text = "关闭"
	UiTheme.style_plain(close)
	close.custom_minimum_size = Vector2(64, 26)
	close.pressed.connect(func() -> void: hide_screen())
	header.add_child(close)

	var body: HBoxContainer = HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	root.content.add_child(body)

	nav_column = VBoxContainer.new()
	nav_column.name = "Nav"
	nav_column.custom_minimum_size = Vector2(NAV_WIDTH, 0)
	nav_column.add_theme_constant_override("separation", 6)
	body.add_child(nav_column)

	var slot_scroll: ScrollContainer = ScrollContainer.new()
	slot_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slot_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	slot_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(slot_scroll)
	slot_column = VBoxContainer.new()
	slot_column.name = "Slots"
	slot_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slot_column.add_theme_constant_override("separation", 7)
	slot_scroll.add_child(slot_column)

	detail_column = VBoxContainer.new()
	detail_column.name = "Detail"
	detail_column.custom_minimum_size = Vector2(DETAIL_WIDTH, 0)
	detail_column.add_theme_constant_override("separation", 6)
	body.add_child(detail_column)

	_build_nav()
	_build_footer()


# ---------------------------------------------------------------------------
# 左栏导航
# ---------------------------------------------------------------------------

func _build_nav() -> void:
	for child: Node in nav_column.get_children():
		nav_column.remove_child(child)
		child.queue_free()
	var band: PanelContainer = PanelContainer.new()
	band.add_theme_stylebox_override("panel", UiTheme.title_band())
	nav_column.add_child(band)
	var label: Label = Label.new()
	label.text = "卷 宗"
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", UiTheme.PAPER)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	band.add_child(label)

	for key: String in ["存档", "读取", "设置", "返回"]:
		var button: Button = Button.new()
		button.name = "Nav_" + key
		button.text = key
		button.custom_minimum_size = Vector2(0, 30)
		var active: bool = key == _nav
		var style: StyleBoxFlat = UiTheme.pill(UiTheme.JADE_DEEP if active else Color(0.90, 0.89, 0.84, 0.92))
		style.set_corner_radius_all(14)
		style.content_margin_left = 10.0
		style.content_margin_right = 10.0
		button.add_theme_stylebox_override("normal", style)
		button.add_theme_stylebox_override("hover", style)
		button.add_theme_stylebox_override("pressed", style)
		button.add_theme_color_override("font_color", UiTheme.PAPER if active else UiTheme.INK_SOFT)
		button.add_theme_font_size_override("font_size", 13)
		button.pressed.connect(_on_nav.bind(key))
		nav_column.add_child(button)

	var spacer: Control = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	nav_column.add_child(spacer)
	nav_column.add_child(UiTheme.ornament_divider())
	for line: String in ["执一卷天书", "观万界沉浮"]:
		var poem: Label = Label.new()
		poem.text = line
		poem.add_theme_font_size_override("font_size", 11)
		poem.add_theme_color_override("font_color", UiTheme.INK_FAINT)
		poem.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nav_column.add_child(poem)
	var seal: PanelContainer = PanelContainer.new()
	seal.custom_minimum_size = Vector2(26, 26)
	seal.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	seal.add_theme_stylebox_override("panel", UiTheme.seal(UiTheme.CINNABAR, Color(0, 0, 0, 0)))
	nav_column.add_child(seal)
	var seal_text: Label = Label.new()
	seal_text.text = "录"
	seal_text.add_theme_font_size_override("font_size", 12)
	seal_text.add_theme_color_override("font_color", UiTheme.PAPER)
	seal_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	seal_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	seal.add_child(seal_text)


func _on_nav(key: String) -> void:
	_nav = key
	_build_nav()
	if key == "返回":
		hide_screen()


# ---------------------------------------------------------------------------
# 底部动作条
# ---------------------------------------------------------------------------

func _build_footer() -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	root.content.add_child(row)
	var status: Label = UiTheme.body_label("", 11, UiTheme.INK_FAINT)
	status.name = "Status"
	status.autowrap_mode = TextServer.AUTOWRAP_OFF
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(status)
	status_label = status
	var refresh: Button = Button.new()
	refresh.name = "RefreshSaves"
	refresh.text = "刷新列表"
	UiTheme.style_plain(refresh)
	refresh.custom_minimum_size = Vector2(96, 30)
	refresh.pressed.connect(func() -> void: refresh_requested.emit())
	row.add_child(refresh)
	var create: Button = Button.new()
	create.name = "NewSave"
	create.text = "新建存档"
	create.custom_minimum_size = Vector2(150, 34)
	UiTheme.style_primary(create)
	create.pressed.connect(_on_new_save)
	row.add_child(create)


func _on_new_save() -> void:
	# 优先写入第一个空槽；全满则覆盖当前选中槽。
	for slot: int in range(SLOT_COUNT):
		if not _saves.has(slot):
			save_requested.emit(slot)
			return
	save_requested.emit(_selected)


# ---------------------------------------------------------------------------
# 对外接口
# ---------------------------------------------------------------------------

## `saves` 为 `listSaves` 回包的 `saves[]` 原样数组；缺字段一律降级为空，不崩。
func show_saves(saves: Array) -> void:
	_saves.clear()
	for entry: Variant in saves:
		var info: Dictionary = entry
		_saves[int(info.get("slotId", -1))] = info
	if not _saves.has(_selected):
		_selected = int(_saves.keys()[0]) if not _saves.is_empty() else 0
	_rebuild_slots()
	_rebuild_detail()
	visible = true


func hide_screen() -> void:
	visible = false


func set_status(text: String) -> void:
	if status_label != null:
		status_label.text = text


# ---------------------------------------------------------------------------
# 中栏：存档槽
# ---------------------------------------------------------------------------

func _rebuild_slots() -> void:
	for child: Node in slot_column.get_children():
		slot_column.remove_child(child)
		child.queue_free()
	for slot: int in range(SLOT_COUNT):
		slot_column.add_child(_slot_card(slot, _saves.get(slot, {})))


func _slot_card(slot: int, info: Dictionary) -> PanelContainer:
	var filled: bool = not info.is_empty()
	var card: PanelContainer = PanelContainer.new()
	card.name = "Slot_%d" % slot
	card.custom_minimum_size = Vector2(0, SLOT_HEIGHT)
	card.add_theme_stylebox_override("panel", UiTheme.slot_card(slot == _selected and filled))
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.gui_input.connect(_on_slot_input.bind(slot, filled))

	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	card.add_child(row)

	row.add_child(_slot_badge(slot, filled))
	row.add_child(_thumb(slot, filled, 116, 72))

	var info_column: VBoxContainer = VBoxContainer.new()
	info_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_column.add_theme_constant_override("separation", 2)
	row.add_child(info_column)

	var name_row: HBoxContainer = HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 6)
	info_column.add_child(name_row)
	var mark: Label = Label.new()
	mark.text = "◈"
	mark.add_theme_font_size_override("font_size", 12)
	mark.add_theme_color_override("font_color", UiTheme.JADE_DEEP if filled else UiTheme.INK_FAINT)
	name_row.add_child(mark)
	var name_label: Label = Label.new()
	name_label.text = str(info.get("playerSectName", "")) if filled else "空存档位"
	name_label.add_theme_font_size_override("font_size", 15)
	name_label.add_theme_color_override("font_color", UiTheme.INK if filled else UiTheme.INK_FAINT)
	name_row.add_child(name_label)
	if filled:
		name_row.add_child(_faction_tag(str(info.get("factionType", ""))))

	var sub: Label = Label.new()
	if filled:
		sub.text = "%s · %s" % [
			str(info.get("playerSectName", "")),
			str(FACTION_NAMES.get(str(info.get("factionType", "")), "—")),
		]
	else:
		sub.text = "暂无存档数据"
	sub.add_theme_font_size_override("font_size", 11)
	sub.add_theme_color_override("font_color", UiTheme.INK_FAINT)
	info_column.add_child(sub)

	var path_label: Label = Label.new()
	path_label.text = _file_name(str(info.get("filePath", ""))) if filled else "—"
	path_label.add_theme_font_size_override("font_size", 10)
	path_label.add_theme_color_override("font_color", UiTheme.INK_FAINT)
	info_column.add_child(path_label)

	var meta: VBoxContainer = VBoxContainer.new()
	meta.custom_minimum_size = Vector2(150, 0)
	meta.add_theme_constant_override("separation", 2)
	row.add_child(meta)
	for text: String in [
		"第 %d 回合" % int(info.get("turn", 0)) if filled else "—",
		_time_text(str(info.get("savedAt", ""))) if filled else "—",
		_size_text(int(info.get("fileSize", 0))) if filled else "—",
	]:
		var line: Label = Label.new()
		line.text = text
		line.add_theme_font_size_override("font_size", 10)
		line.add_theme_color_override("font_color", UiTheme.INK_SOFT if filled else UiTheme.INK_FAINT)
		line.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		meta.add_child(line)

	row.add_child(_slot_actions(slot, filled))
	return card


## 序号徽章：金色竖牌，上半序号、下半「自动/手动」。
func _slot_badge(slot: int, filled: bool) -> PanelContainer:
	var badge: PanelContainer = PanelContainer.new()
	badge.custom_minimum_size = Vector2(40, 66)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var style: StyleBoxFlat = StyleBoxFlat.new()
	if filled:
		style.bg_color = Color(0.914, 0.847, 0.671, 0.96)
		style.border_color = Color(UiTheme.GOLD.r, UiTheme.GOLD.g, UiTheme.GOLD.b, 0.85)
	else:
		style.bg_color = Color(0.87, 0.86, 0.82, 0.72)
		style.border_color = Color(0.72, 0.71, 0.67, 0.80)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	badge.add_theme_stylebox_override("panel", style)

	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	badge.add_child(column)
	var number: Label = Label.new()
	number.text = str(slot)
	number.add_theme_font_size_override("font_size", 20)
	number.add_theme_color_override("font_color", UiTheme.INK if filled else UiTheme.INK_FAINT)
	number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(number)
	var kind: Label = Label.new()
	kind.text = "\n".join(PackedStringArray(["自", "动"]) if slot == AUTO_SLOT else PackedStringArray(["手", "动"]))
	kind.add_theme_font_size_override("font_size", 9)
	kind.add_theme_color_override("font_color", UiTheme.INK_SOFT if filled else UiTheme.INK_FAINT)
	kind.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(kind)
	return badge


func _slot_actions(slot: int, filled: bool) -> VBoxContainer:
	var column: VBoxContainer = VBoxContainer.new()
	column.custom_minimum_size = Vector2(84, 0)
	column.add_theme_constant_override("separation", 3)
	var load_button: Button = Button.new()
	load_button.name = "Load_%d" % slot
	load_button.text = "读取"
	load_button.custom_minimum_size = Vector2(84, 22)
	load_button.add_theme_font_size_override("font_size", 11)
	UiTheme.style_primary(load_button)
	load_button.disabled = not filled
	load_button.pressed.connect(func() -> void: load_requested.emit(slot))
	column.add_child(load_button)

	var save_button: Button = Button.new()
	save_button.name = "Save_%d" % slot
	save_button.text = "覆盖" if filled else "存入"
	save_button.custom_minimum_size = Vector2(84, 22)
	save_button.add_theme_font_size_override("font_size", 11)
	UiTheme.style_plain(save_button)
	save_button.pressed.connect(func() -> void: save_requested.emit(slot))
	column.add_child(save_button)

	var delete_button: Button = Button.new()
	delete_button.name = "Delete_%d" % slot
	delete_button.text = "删除"
	delete_button.custom_minimum_size = Vector2(84, 22)
	delete_button.add_theme_font_size_override("font_size", 11)
	delete_button.add_theme_color_override("font_color", UiTheme.CINNABAR)
	UiTheme.style_plain(delete_button)
	# 协议 2.0 无 deleteSave：不假装能删，置灰并写明原因。
	delete_button.disabled = true
	delete_button.tooltip_text = "协议 2.0 只有 listSaves / saveGame / loadGame，无 deleteSave 命令"
	column.add_child(delete_button)
	return column


func _on_slot_input(event: InputEvent, slot: int, filled: bool) -> void:
	if not (event is InputEventMouseButton):
		return
	var mouse: InputEventMouseButton = event
	if not mouse.pressed or mouse.button_index != MOUSE_BUTTON_LEFT:
		return
	_selected = slot
	_rebuild_slots()
	_rebuild_detail()


# ---------------------------------------------------------------------------
# 右栏：详情卡
# ---------------------------------------------------------------------------

func _rebuild_detail() -> void:
	for child: Node in detail_column.get_children():
		detail_column.remove_child(child)
		child.queue_free()
	var info: Dictionary = _saves.get(_selected, {})
	var filled: bool = not info.is_empty()

	var card: PanelContainer = PanelContainer.new()
	card.name = "DetailCard"
	card.add_theme_stylebox_override("panel", UiTheme.paper(0.95, 4, 1.0))
	detail_column.add_child(card)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	card.add_child(column)

	var head: HBoxContainer = HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	column.add_child(head)
	head.add_child(_thumb(_selected, filled, 116, 72))
	var head_text: VBoxContainer = VBoxContainer.new()
	head_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head_text.add_theme_constant_override("separation", 2)
	head.add_child(head_text)
	var name_label: Label = Label.new()
	name_label.text = str(info.get("playerSectName", "")) if filled else "空存档位"
	name_label.add_theme_font_size_override("font_size", 15)
	name_label.add_theme_color_override("font_color", UiTheme.INK)
	head_text.add_child(name_label)
	var tag_row: HBoxContainer = HBoxContainer.new()
	head_text.add_child(tag_row)
	tag_row.add_child(_faction_tag(str(info.get("factionType", ""))) if filled else
		UiTheme.body_label("—", 10, UiTheme.INK_FAINT))

	column.add_child(UiTheme.ornament_divider())
	for pair: Array in _detail_rows(info, filled):
		column.add_child(_kv_row(str(pair[0]), str(pair[1])))

	column.add_child(UiTheme.hairline())
	var band: PanelContainer = PanelContainer.new()
	band.add_theme_stylebox_override("panel", UiTheme.title_band())
	column.add_child(band)
	var band_label: Label = Label.new()
	band_label.text = "◈ 存档内容"
	band_label.add_theme_font_size_override("font_size", 12)
	band_label.add_theme_color_override("font_color", UiTheme.PAPER)
	band.add_child(band_label)

	for pair: Array in _content_rows(info, filled):
		column.add_child(_kv_row(str(pair[0]), str(pair[1])))

	column.add_child(UiTheme.ornament_divider())
	var poem: Label = Label.new()
	poem.text = "山河万里，宗门长存"
	poem.add_theme_font_size_override("font_size", 11)
	poem.add_theme_color_override("font_color", UiTheme.INK_FAINT)
	poem.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(poem)

	var spacer: Control = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_column.add_child(spacer)


func _detail_rows(info: Dictionary, filled: bool) -> Array:
	if not filled:
		return [["槽位", str(_selected)], ["状态", "空"]]
	return [
		["槽位", str(_selected) + ("（自动）" if _selected == AUTO_SLOT else "（手动）")],
		["第 N 回合", str(int(info.get("turn", 0)))],
		["保存时间", _time_text(str(info.get("savedAt", "")))],
		["文件体积", _size_text(int(info.get("fileSize", 0)))],
	]


## 「存档内容」只列回包里真实存在的字段，不编造弟子数/资源总量。
func _content_rows(info: Dictionary, filled: bool) -> Array:
	if not filled:
		return [["宗门信息", "—"], ["势力范围", "—"], ["存档文件", "—"]]
	return [
		["宗门信息", str(info.get("playerSectName", ""))],
		["势力范围", str(FACTION_NAMES.get(str(info.get("factionType", "")), "—"))],
		["存档文件", _file_name(str(info.get("filePath", "")))],
	]


func _kv_row(key: String, value: String) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var key_label: Label = Label.new()
	key_label.text = key
	key_label.add_theme_font_size_override("font_size", 11)
	key_label.add_theme_color_override("font_color", UiTheme.INK_FAINT)
	key_label.custom_minimum_size = Vector2(66, 0)
	row.add_child(key_label)
	var value_label: Label = Label.new()
	value_label.text = value
	value_label.add_theme_font_size_override("font_size", 11)
	value_label.add_theme_color_override("font_color", UiTheme.INK_SOFT)
	value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	# 同上：HBox 内的 Label 一旦开自动换行就会被压成一字一行，必须关掉。
	value_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	value_label.clip_text = true
	row.add_child(value_label)
	return row


func _faction_tag(faction: String) -> PanelContainer:
	var tag: PanelContainer = PanelContainer.new()
	tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var style: StyleBoxFlat = UiTheme.pill(Color(0.72, 0.74, 0.66, 0.90))
	style.set_corner_radius_all(9)
	style.content_margin_left = 7.0
	style.content_margin_right = 7.0
	style.content_margin_top = 1.0
	style.content_margin_bottom = 1.0
	tag.add_theme_stylebox_override("panel", style)
	var label: Label = Label.new()
	label.text = str(FACTION_NAMES.get(faction, faction if not faction.is_empty() else "—"))
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", UiTheme.PAPER)
	tag.add_child(label)
	return tag


# ---------------------------------------------------------------------------
# 缩略图（程序化：槽号哈希派生的确定性墨块地图）
# ---------------------------------------------------------------------------

func _thumb(slot: int, filled: bool, width: int, height: int) -> Control:
	var frame: PanelContainer = PanelContainer.new()
	frame.custom_minimum_size = Vector2(width, height)
	frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	frame.add_theme_stylebox_override("panel", UiTheme.paper(0.98, 3, 1.0))
	var thumb: SaveThumb = SaveThumb.new()
	thumb.slot_id = slot
	thumb.filled = filled
	thumb.custom_minimum_size = Vector2(width - 6, height - 6)
	frame.add_child(thumb)
	return frame


# ---------------------------------------------------------------------------
# 文案格式化
# ---------------------------------------------------------------------------

## ISO 8601 → 「2025-08-28 14:32」，去掉秒与时区尾巴。
static func _time_text(raw: String) -> String:
	var text: String = raw.replace("T", " ")
	if text.length() > 16:
		return text.substr(0, 16)
	return text if not text.is_empty() else "—"


static func _size_text(bytes: int) -> String:
	if bytes <= 0:
		return "—"
	if bytes >= 1048576:
		return "%.2f MB" % (float(bytes) / 1048576.0)
	if bytes >= 1024:
		return "%.1f KB" % (float(bytes) / 1024.0)
	return "%d B" % bytes


static func _file_name(path: String) -> String:
	if path.is_empty():
		return "—"
	return path.replace("\\", "/").get_file()


# --- 供自动验收断言 ---

func slot_card_count() -> int:
	return 0 if slot_column == null else slot_column.get_child_count()


func filled_slot_count() -> int:
	return _saves.size()


func selected_slot() -> int:
	return _selected


# ---------------------------------------------------------------------------
# 缩略图控件：只用 `_draw`，不加载任何外部图片
# ---------------------------------------------------------------------------

class SaveThumb extends Control:
	var slot_id: int = 0
	var filled: bool = true

	func _draw() -> void:
		var rect: Rect2 = Rect2(Vector2.ZERO, size)
		if not filled:
			draw_rect(rect, Color(0.90, 0.89, 0.855, 0.85))
			draw_line(Vector2(4, size.y - 6), Vector2(size.x - 4, 6),
				Color(0.74, 0.73, 0.69, 0.75), 1.0)
			return
		draw_rect(rect, Color(0.855, 0.878, 0.855, 0.96))
		# 确定性伪随机：同一个槽号永远画出同一张图（表现层索引哈希，不碰 GameState.rng）。
		var state: int = slot_id * 7919 + 104729
		for index: int in range(9):
			state = (state * 1103515245 + 12345) & 0x7FFFFFFF
			var cx: float = float(state % 1000) / 1000.0 * size.x
			state = (state * 1103515245 + 12345) & 0x7FFFFFFF
			var cy: float = float(state % 1000) / 1000.0 * size.y
			state = (state * 1103515245 + 12345) & 0x7FFFFFFF
			var radius: float = 5.0 + float(state % 9)
			var tint: Color = Color(0.36, 0.47, 0.42, 0.55) if index % 3 == 0 else Color(0.55, 0.60, 0.55, 0.45)
			draw_circle(Vector2(cx, cy), radius, tint)
		# 一格红点标出「主城」，青色细线标出「势力范围」。
		draw_line(Vector2(4, size.y * 0.62), Vector2(size.x - 4, size.y * 0.48),
			Color(0.30, 0.45, 0.62, 0.55), 1.2)
		draw_circle(Vector2(size.x * 0.62, size.y * 0.46), 3.0, Color(0.66, 0.22, 0.18, 0.90))
		draw_rect(rect, Color(0.42, 0.40, 0.33, 0.45), false, 1.0)
