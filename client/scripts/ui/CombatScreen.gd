class_name CombatScreen
extends CanvasLayer
## 战斗系统界面（对齐参考图「水墨奇幻战场：天玄城争夺战」）。
##
## 这是**叠加在战场之上**的一层 HUD，不是全屏卷轴：地图仍可见，只压一层极淡的墨色，
## 四角挂卡片——左上胜负条件、右侧部队/胜率/地形、底部单位卡、右下五枚圆形动作钮。
##
## 数据来源（全部真实，客户端零规则）：
##   回合/阶段     ← `view.metadata`
##   胜负条件      ← `data/gameConfig.json` 的 `victory.<faction>` 与 `VictoryRules.check_defeat` 的判定项
##   部队/战力/射程 ← `queryAttackable` + `queryAttackPreview` 回包
##   胜率预估      ← `preview.winChance`（服务端算好，客户端只乘 100 显示）
##   地形加成      ← `gameConfig.warfare` 里的四个系数（纯展示，不参与计算）
##
## 没有独立「技能」系统：五枚圆钮里的第三枚做成「道法」，直接开道统树——
## 本作的战斗加成来自宗门道法，而不是每个单位一套技能，故不伪造技能列表。

signal action_pressed(key: String)
signal close_requested()

const BAR_HEIGHT: float = ActionBar.BAR_HEIGHT
const RIGHT_WIDTH: float = 232.0
const UNIT_CARD_WIDTH: float = 566.0
const UNIT_CARD_HEIGHT: float = 154.0
const ROUND_BUTTON: float = 54.0

## 五枚圆钮：(key, 文案, 字形, 提示)。
const ACTIONS: Array = [
	["move", "移动", "行", "高亮服务端下发的可达格"],
	["attack", "攻击", "剑", "高亮服务端下发的可攻击格"],
	["dao", "道法", "诀", "打开道统树（战斗加成来自宗门道法）"],
	["wait", "待机", "止", "协议 2.0 无 wait/skip 命令，故置灰"],
	["retreat", "撤退", "退", "选择相邻格撤退（成功率由服务端判定）"],
]

## 单位卡数值项的字形 → 中文名（字形只作图标，避免再塞一套贴图）。
const STAT_NAMES: Dictionary = {
	"兵": "战力", "行": "移动", "弓": "射程", "刃": "攻击", "星": "战阶",
}

var objectives_card: PanelContainer = null
var turn_label: Label = null
var victory_list: VBoxContainer = null
var defeat_list: VBoxContainer = null
var troop_card: PanelContainer = null
var troop_name: Label = null
var troop_bar: RatioBar = null
var troop_bar_text: Label = null
var troop_stats: VBoxContainer = null
var odds_card: PanelContainer = null
var odds_value: Label = null
var odds_note: Label = null
var terrain_card: PanelContainer = null
var terrain_list: VBoxContainer = null
var unit_card: PanelContainer = null
var unit_portrait: Label = null
var unit_name: Label = null
var unit_bar: RatioBar = null
var unit_bar_text: Label = null
var unit_stats: HBoxContainer = null
var action_row: HBoxContainer = null
var action_buttons: Dictionary = {}


func setup() -> void:
	layer = 6
	visible = false

	var dim: ColorRect = ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0.06, 0.09, 0.08, 0.16)
	dim.anchor_right = 1.0
	dim.anchor_bottom = 1.0
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	_build_objectives()
	_build_right_column()
	_build_unit_card()
	_build_action_buttons()


# ---------------------------------------------------------------------------
# 左上：回合 + 胜负条件
# ---------------------------------------------------------------------------

func _build_objectives() -> void:
	var column: VBoxContainer = VBoxContainer.new()
	column.name = "Objectives"
	column.position = Vector2(14, 52)
	column.custom_minimum_size = Vector2(304, 0)
	add_child(column)

	var pill: PanelContainer = PanelContainer.new()
	pill.custom_minimum_size = Vector2(190, 28)
	pill.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var pill_style: StyleBoxFlat = UiTheme.pill(UiTheme.JADE_DEEP)
	pill_style.set_corner_radius_all(14)
	pill.add_theme_stylebox_override("panel", pill_style)
	column.add_child(pill)
	turn_label = Label.new()
	turn_label.text = "第 1 回合 · 我方行动"
	turn_label.add_theme_font_size_override("font_size", 13)
	turn_label.add_theme_color_override("font_color", UiTheme.PAPER)
	turn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	turn_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pill.add_child(turn_label)

	objectives_card = PanelContainer.new()
	objectives_card.add_theme_stylebox_override("panel", UiTheme.paper(0.94, 4, 1.0))
	column.add_child(objectives_card)
	var inner: VBoxContainer = VBoxContainer.new()
	inner.add_theme_constant_override("separation", 4)
	objectives_card.add_child(inner)

	inner.add_child(_section_band("胜利条件", UiTheme.JADE_DEEP))
	victory_list = VBoxContainer.new()
	victory_list.name = "VictoryList"
	victory_list.add_theme_constant_override("separation", 3)
	inner.add_child(victory_list)

	inner.add_child(_section_band("失败条件", UiTheme.CINNABAR))
	defeat_list = VBoxContainer.new()
	defeat_list.name = "DefeatList"
	defeat_list.add_theme_constant_override("separation", 3)
	inner.add_child(defeat_list)

	var close: Button = Button.new()
	close.name = "CloseCombat"
	close.text = "关闭战斗界面"
	close.custom_minimum_size = Vector2(0, 26)
	close.add_theme_font_size_override("font_size", 11)
	UiTheme.style_plain(close)
	close.pressed.connect(func() -> void: close_requested.emit())
	inner.add_child(close)


# ---------------------------------------------------------------------------
# 右侧：部队 / 胜率 / 地形
# ---------------------------------------------------------------------------

func _build_right_column() -> void:
	var column: VBoxContainer = VBoxContainer.new()
	column.name = "RightColumn"
	column.anchor_left = 1.0
	column.anchor_right = 1.0
	column.offset_left = -(RIGHT_WIDTH + 14.0)
	column.offset_right = -14.0
	column.offset_top = 52.0
	column.add_theme_constant_override("separation", 8)
	add_child(column)

	# ① 部队卡
	troop_card = PanelContainer.new()
	troop_card.add_theme_stylebox_override("panel", UiTheme.paper(0.94, 4, 1.0))
	column.add_child(troop_card)
	var troop_inner: VBoxContainer = VBoxContainer.new()
	troop_inner.add_theme_constant_override("separation", 5)
	troop_card.add_child(troop_inner)
	troop_inner.add_child(_section_band("青云宗 · 剑修部队", UiTheme.JADE_DEEP))

	troop_name = UiTheme.title_label("（未选中弟子）", 13, UiTheme.INK)
	troop_inner.add_child(troop_name)

	troop_bar = RatioBar.new()
	troop_bar.setup(UiTheme.JADE, 6)
	troop_inner.add_child(troop_bar)
	troop_bar_text = UiTheme.body_label("—", 10, UiTheme.INK_FAINT)
	troop_bar_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	troop_inner.add_child(troop_bar_text)

	troop_stats = VBoxContainer.new()
	troop_stats.name = "TroopStats"
	troop_stats.add_theme_constant_override("separation", 2)
	troop_inner.add_child(troop_stats)

	# ② 胜率预估
	odds_card = PanelContainer.new()
	odds_card.add_theme_stylebox_override("panel", UiTheme.paper(0.94, 4, 1.0))
	column.add_child(odds_card)
	var odds_inner: VBoxContainer = VBoxContainer.new()
	odds_inner.add_theme_constant_override("separation", 2)
	odds_card.add_child(odds_inner)
	odds_inner.add_child(_section_band("胜率预估", UiTheme.JADE_DEEP))
	odds_value = Label.new()
	odds_value.text = "—"
	odds_value.add_theme_font_size_override("font_size", 30)
	odds_value.add_theme_color_override("font_color", UiTheme.JADE_DEEP)
	odds_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	odds_inner.add_child(odds_value)
	odds_note = UiTheme.body_label("选中弟子并指向可攻击格后显示", 10, UiTheme.INK_FAINT)
	odds_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	odds_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	odds_inner.add_child(odds_note)

	# ③ 地形加成
	terrain_card = PanelContainer.new()
	terrain_card.add_theme_stylebox_override("panel", UiTheme.paper(0.94, 4, 1.0))
	column.add_child(terrain_card)
	var terrain_inner: VBoxContainer = VBoxContainer.new()
	terrain_inner.add_theme_constant_override("separation", 3)
	terrain_card.add_child(terrain_inner)
	terrain_inner.add_child(_section_band("地形加成", UiTheme.JADE_DEEP))
	terrain_list = VBoxContainer.new()
	terrain_list.name = "TerrainList"
	terrain_list.add_theme_constant_override("separation", 3)
	terrain_inner.add_child(terrain_list)


# ---------------------------------------------------------------------------
# 底部：单位卡
# ---------------------------------------------------------------------------

func _build_unit_card() -> void:
	unit_card = PanelContainer.new()
	unit_card.name = "UnitCard"
	unit_card.anchor_top = 1.0
	unit_card.anchor_bottom = 1.0
	unit_card.offset_left = 330.0
	unit_card.offset_right = 330.0 + UNIT_CARD_WIDTH
	unit_card.offset_top = -(BAR_HEIGHT + UNIT_CARD_HEIGHT + 14.0)
	unit_card.offset_bottom = -(BAR_HEIGHT + 14.0)
	unit_card.add_theme_stylebox_override("panel", UiTheme.paper(0.95, 5, 1.0))
	add_child(unit_card)

	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	unit_card.add_child(row)

	# 立绘：程序化墨像（无插画资源，用纸框 + 姓氏首字）
	var portrait_frame: PanelContainer = PanelContainer.new()
	portrait_frame.custom_minimum_size = Vector2(84, 118)
	portrait_frame.add_theme_stylebox_override("panel", UiTheme.paper(0.98, 3, 1.0))
	row.add_child(portrait_frame)
	unit_portrait = Label.new()
	unit_portrait.text = "修"
	unit_portrait.add_theme_font_size_override("font_size", 40)
	unit_portrait.add_theme_color_override("font_color", UiTheme.JADE_DEEP)
	unit_portrait.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	unit_portrait.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	portrait_frame.add_child(unit_portrait)

	var info: VBoxContainer = VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 4)
	row.add_child(info)

	unit_name = UiTheme.title_label("（未选中弟子）", 15, UiTheme.INK)
	info.add_child(unit_name)

	unit_bar = RatioBar.new()
	unit_bar.setup(UiTheme.JADE, 7)
	info.add_child(unit_bar)
	unit_bar_text = UiTheme.body_label("—", 10, UiTheme.INK_FAINT)
	unit_bar_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	info.add_child(unit_bar_text)

	unit_stats = HBoxContainer.new()
	unit_stats.name = "UnitStats"
	unit_stats.add_theme_constant_override("separation", 14)
	info.add_child(unit_stats)

	info.add_child(UiTheme.ornament_divider())


# ---------------------------------------------------------------------------
# 右下：五枚圆形动作钮
# ---------------------------------------------------------------------------

func _build_action_buttons() -> void:
	action_row = HBoxContainer.new()
	action_row.name = "Actions"
	action_row.anchor_left = 1.0
	action_row.anchor_right = 1.0
	action_row.anchor_top = 1.0
	action_row.anchor_bottom = 1.0
	action_row.offset_left = -(ROUND_BUTTON * 5.0 + 14.0 * 4.0 + 16.0)
	action_row.offset_right = -16.0
	action_row.offset_top = -(BAR_HEIGHT + ROUND_BUTTON + 44.0)
	action_row.offset_bottom = -(BAR_HEIGHT + 44.0)
	action_row.add_theme_constant_override("separation", 14)
	add_child(action_row)

	for entry: Array in ACTIONS:
		var key: String = str(entry[0])
		var label: String = str(entry[1])
		var glyph: String = str(entry[2])
		var tip: String = str(entry[3])
		var column: VBoxContainer = VBoxContainer.new()
		column.add_theme_constant_override("separation", 2)
		action_row.add_child(column)
		var button: Button = Button.new()
		button.name = "Combat_" + key
		button.text = glyph
		button.custom_minimum_size = Vector2(ROUND_BUTTON, ROUND_BUTTON)
		button.tooltip_text = tip
		button.add_theme_font_size_override("font_size", 20)
		var style: StyleBoxFlat = UiTheme.round_action()
		style.set_corner_radius_all(int(ROUND_BUTTON * 0.5))
		button.add_theme_stylebox_override("normal", style)
		button.add_theme_stylebox_override("hover", style)
		button.add_theme_stylebox_override("pressed", style)
		button.add_theme_stylebox_override("disabled", style)
		button.add_theme_color_override("font_color", UiTheme.GOLD_LIGHT)
		button.add_theme_color_override("font_disabled_color", Color(0.62, 0.62, 0.58, 0.75))
		button.pressed.connect(func() -> void: action_pressed.emit(key))
		column.add_child(button)
		var caption: Label = Label.new()
		caption.text = label
		caption.add_theme_font_size_override("font_size", 10)
		caption.add_theme_color_override("font_color", UiTheme.PAPER)
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(caption)
		action_buttons[key] = button

	_set_action_enabled("wait", false)


func _set_action_enabled(key: String, enabled: bool) -> void:
	var button: Button = action_buttons.get(key, null) as Button
	if button != null:
		button.disabled = not enabled


# ---------------------------------------------------------------------------
# 对外接口
# ---------------------------------------------------------------------------

## `data` 字段见文件头；缺项一律降级为占位，不崩。
func show_combat(data: Dictionary) -> void:
	turn_label.text = str(data.get("heading", "第 1 回合 · 我方行动"))
	_fill_conditions(victory_list, data.get("victory", []), UiTheme.JADE_DEEP)
	_fill_conditions(defeat_list, data.get("defeat", []), UiTheme.CINNABAR)
	_fill_troop(data.get("troop", {}))
	_fill_odds(data.get("odds", {}))
	_fill_terrain(data.get("terrain", []))
	_fill_unit(data.get("unit", {}))
	var has_unit: bool = not (data.get("unit", {}) as Dictionary).is_empty()
	for key: String in ["move", "attack", "retreat", "dao"]:
		_set_action_enabled(key, has_unit)
	visible = true


func hide_screen() -> void:
	visible = false


func _fill_conditions(list: VBoxContainer, rows: Array, color: Color) -> void:
	for child: Node in list.get_children():
		list.remove_child(child)
		child.queue_free()
	if rows.is_empty():
		list.add_child(UiTheme.body_label("（未下发）", 10, UiTheme.INK_FAINT))
		return
	for entry: Variant in rows:
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 5)
		var mark: Label = Label.new()
		mark.text = "◆"
		mark.add_theme_font_size_override("font_size", 8)
		mark.add_theme_color_override("font_color", color)
		mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(mark)
		var text: Label = Label.new()
		text.text = str(entry)
		text.add_theme_font_size_override("font_size", 11)
		text.add_theme_color_override("font_color", UiTheme.INK_SOFT)
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text)
		list.add_child(row)


func _fill_troop(troop: Dictionary) -> void:
	if troop.is_empty():
		troop_name.text = "（未选中弟子）"
		troop_bar.set_ratio(0.0)
		troop_bar_text.text = "—"
		_clear_children(troop_stats)
		return
	troop_name.text = "%s · %s" % [str(troop.get("sectName", "")), str(troop.get("title", ""))]
	troop_bar.set_ratio(float(troop.get("powerRatio", 0.0)))
	troop_bar_text.text = str(troop.get("powerText", "—"))
	_clear_children(troop_stats)
	for pair: Array in troop.get("stats", []):
		troop_stats.add_child(_stat_row(str(pair[0]), str(pair[1]), str(pair[2])))


func _fill_odds(odds: Dictionary) -> void:
	var has_odds: bool = bool(odds.get("known", false))
	odds_value.text = "%.0f%%" % (float(odds.get("chance", 0.0)) * 100.0) if has_odds else "—"
	odds_value.add_theme_color_override("font_color",
		UiTheme.JADE_DEEP if has_odds else UiTheme.INK_FAINT)
	odds_note.text = str(odds.get("note", ""))


func _fill_terrain(rows: Array) -> void:
	_clear_children(terrain_list)
	if rows.is_empty():
		terrain_list.add_child(UiTheme.body_label("（配置未下发）", 10, UiTheme.INK_FAINT))
		return
	for entry: Variant in rows:
		var item: Dictionary = entry
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var name_label: Label = Label.new()
		name_label.text = str(item.get("label", ""))
		name_label.add_theme_font_size_override("font_size", 11)
		name_label.add_theme_color_override("font_color", UiTheme.INK_SOFT)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		var value_label: Label = Label.new()
		var ratio: float = float(item.get("ratio", 0.0))
		value_label.text = "%s%.0f%% %s" % [
			"+" if ratio >= 0.0 else "",
			ratio * 100.0,
			str(item.get("note", "")),
		]
		value_label.add_theme_font_size_override("font_size", 11)
		value_label.add_theme_color_override("font_color",
			UiTheme.CINNABAR if ratio >= 0.0 else UiTheme.JADE)
		row.add_child(value_label)
		terrain_list.add_child(row)


func _fill_unit(unit: Dictionary) -> void:
	if unit.is_empty():
		unit_portrait.text = "修"
		unit_name.text = "（未选中弟子）"
		unit_bar.set_ratio(0.0)
		unit_bar_text.text = "—"
		_clear_children(unit_stats)
		return
	var name_text: String = str(unit.get("name", ""))
	unit_portrait.text = name_text.substr(0, 1) if not name_text.is_empty() else "修"
	unit_name.text = "%s · %s · %s" % [
		str(unit.get("sectName", "")), str(unit.get("className", "")), str(unit.get("realmLabel", "")),
	]
	unit_bar.set_ratio(float(unit.get("powerRatio", 0.0)))
	unit_bar_text.text = str(unit.get("powerText", "—"))
	_clear_children(unit_stats)
	for pair: Array in unit.get("stats", []):
		unit_stats.add_child(_stat_chip(str(pair[0]), str(pair[1])))


# ---------------------------------------------------------------------------
# 小部件
# ---------------------------------------------------------------------------

func _section_band(title: String, color: Color) -> PanelContainer:
	var band: PanelContainer = PanelContainer.new()
	band.add_theme_stylebox_override("panel", UiTheme.title_band(color))
	var label: Label = Label.new()
	label.text = "◈ " + title
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", UiTheme.PAPER)
	band.add_child(label)
	return band


## 右侧部队卡的一行：图标字 + 名称 + 数值（左名右值）。
func _stat_row(glyph: String, key: String, value: String) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var icon: Label = Label.new()
	icon.text = glyph
	icon.add_theme_font_size_override("font_size", 10)
	icon.add_theme_color_override("font_color", UiTheme.GOLD)
	icon.custom_minimum_size = Vector2(14, 0)
	row.add_child(icon)
	var key_label: Label = Label.new()
	key_label.text = key
	key_label.add_theme_font_size_override("font_size", 11)
	key_label.add_theme_color_override("font_color", UiTheme.INK_FAINT)
	key_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(key_label)
	var value_label: Label = Label.new()
	value_label.text = value
	value_label.add_theme_font_size_override("font_size", 12)
	value_label.add_theme_color_override("font_color", UiTheme.INK)
	row.add_child(value_label)
	return row


## 底部单位卡的一项：「图标 + 名称」在上、数值在下；固定宽度让五项对齐成网格。
func _stat_chip(glyph: String, value: String) -> VBoxContainer:
	var column: VBoxContainer = VBoxContainer.new()
	column.custom_minimum_size = Vector2(62, 0)
	column.add_theme_constant_override("separation", 0)
	var head: HBoxContainer = HBoxContainer.new()
	head.add_theme_constant_override("separation", 3)
	column.add_child(head)
	var icon: Label = Label.new()
	icon.text = glyph
	icon.add_theme_font_size_override("font_size", 9)
	icon.add_theme_color_override("font_color", UiTheme.GOLD)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(icon)
	var name_label: Label = Label.new()
	name_label.text = str(STAT_NAMES.get(glyph, ""))
	name_label.add_theme_font_size_override("font_size", 9)
	name_label.add_theme_color_override("font_color", UiTheme.INK_FAINT)
	name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	head.add_child(name_label)
	var value_label: Label = Label.new()
	value_label.text = value
	value_label.add_theme_font_size_override("font_size", 15)
	value_label.add_theme_color_override("font_color", UiTheme.INK)
	column.add_child(value_label)
	return column


static func _clear_children(node: Node) -> void:
	for child: Node in node.get_children():
		node.remove_child(child)
		child.queue_free()


# --- 供自动验收断言 ---

func action_button_count() -> int:
	return action_buttons.size()


func action_enabled(key: String) -> bool:
	var button: Button = action_buttons.get(key, null) as Button
	return button != null and not button.disabled


func victory_condition_count() -> int:
	return 0 if victory_list == null else victory_list.get_child_count()


func defeat_condition_count() -> int:
	return 0 if defeat_list == null else defeat_list.get_child_count()


func terrain_row_count() -> int:
	return 0 if terrain_list == null else terrain_list.get_child_count()


func odds_text() -> String:
	return "" if odds_value == null else odds_value.text
