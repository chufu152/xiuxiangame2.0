class_name UiTheme
extends RefCounted
## 统一水墨 UI 主题（对齐参考图）：宣纸卡片、淡金细线、青玉印章按钮、竖排标题。
##
## 只提供「样式工厂」，不持有任何状态、不读 `view`、不碰相机。
## 所有控件仍由各面板自行创建，本类只负责把配色/描边/内边距统一到一处，
## 避免 R8 之后每加一个面板就复制一遍 `StyleBoxFlat` 字面量。

## 宣纸底色（实心）。
const PAPER: Color = Color("f4efe3")
## 宣纸卡片（半透明，压在地图上仍能透出山水）。
const PAPER_CARD: Color = Color(0.957, 0.937, 0.890, 0.94)
## 顶栏用更透的一档，让远山从栏下透出来。
const PAPER_BAR: Color = Color(0.949, 0.929, 0.878, 0.88)
## 墨色（正文）。
const INK: Color = Color("2f3b38")
## 淡墨（次要信息）。
const INK_SOFT: Color = Color("5d6b64")
## 更淡的墨（提示/占位）。
const INK_FAINT: Color = Color("8a958d")
## 金线（卡片描边、分隔）。
const GOLD: Color = Color("b8912f")
## 亮金（强调）。
const GOLD_LIGHT: Color = Color("d8b45a")
## 朱砂（警示、敌方、失败）。
const CINNABAR: Color = Color("a8382c")
## 青玉（主操作、己方）。
const JADE: Color = Color("4e7a6f")
## 深青（印章底）。
const JADE_DEEP: Color = Color("2f5a52")
## 深墨板（小地图底）。
const BOARD: Color = Color("2b3a37")


## 宣纸卡片：圆角 + 细金边 + 内边距。
static func paper(alpha: float = 0.94, radius: int = 6, border: float = 1.0) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(PAPER_CARD.r, PAPER_CARD.g, PAPER_CARD.b, alpha)
	style.border_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.55)
	style.border_width_left = int(border)
	style.border_width_right = int(border)
	style.border_width_top = int(border)
	style.border_width_bottom = int(border)
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 9.0
	style.content_margin_bottom = 9.0
	return style


## 顶栏：只有下缘一条金线，不画四边框（参考图的顶栏是「纸带」而非卡片）。
static func bar() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = PAPER_BAR
	style.border_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.42)
	style.border_width_bottom = 1
	style.content_margin_left = 16.0
	style.content_margin_right = 16.0
	style.content_margin_top = 4.0
	style.content_margin_bottom = 4.0
	return style


## 深墨板（小地图底板）。
static func board(alpha: float = 0.96) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(BOARD.r, BOARD.g, BOARD.b, alpha)
	style.border_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.75)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 4.0
	style.content_margin_right = 4.0
	style.content_margin_top = 4.0
	style.content_margin_bottom = 4.0
	return style


## 印章（圆形按钮底）：`corner_radius` 给到极大值即成正圆。
static func seal(color: Color = JADE_DEEP, border: Color = GOLD_LIGHT) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 64
	style.corner_radius_top_right = 64
	style.corner_radius_bottom_left = 64
	style.corner_radius_bottom_right = 64
	style.content_margin_left = 4.0
	style.content_margin_right = 4.0
	style.content_margin_top = 2.0
	style.content_margin_bottom = 2.0
	return style


## 主操作按钮（青玉底 + 金边 + 纸色字）。
static func primary_button() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = JADE_DEEP
	style.border_color = Color(GOLD_LIGHT.r, GOLD_LIGHT.g, GOLD_LIGHT.b, 0.85)
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 5.0
	style.content_margin_bottom = 5.0
	return style


## 次操作按钮（纸底 + 墨字 + 淡金边）。
static func plain_button() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.973, 0.957, 0.914, 0.96)
	style.border_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.45)
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	style.content_margin_top = 4.0
	style.content_margin_bottom = 4.0
	return style


## 卡片标题：小字号、深墨、字距拉开（仿宋体书页标题）。
static func title_label(text: String, size: int = 15, color: Color = INK) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


## 正文/次要文本。
static func body_label(text: String, size: int = 12, color: Color = INK_SOFT) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


## 一条极细分隔线（金线 30% 不透明度）。
static func hairline() -> HSeparator:
	var line: HSeparator = HSeparator.new()
	var style: StyleBoxLine = StyleBoxLine.new()
	style.color = Color(GOLD.r, GOLD.g, GOLD.b, 0.30)
	style.thickness = 1
	line.add_theme_stylebox_override("separator", style)
	return line


## 把任意按钮改成「次操作」样式（纸底墨字）。
static func style_plain(button: Button) -> void:
	button.add_theme_stylebox_override("normal", plain_button())
	var hover: StyleBoxFlat = plain_button()
	hover.bg_color = Color(0.996, 0.984, 0.949, 1.0)
	hover.border_color = GOLD
	button.add_theme_stylebox_override("hover", hover)
	var pressed: StyleBoxFlat = plain_button()
	pressed.bg_color = Color(0.906, 0.882, 0.824, 1.0)
	button.add_theme_stylebox_override("pressed", pressed)
	var disabled: StyleBoxFlat = plain_button()
	disabled.bg_color = Color(0.929, 0.918, 0.886, 0.72)
	disabled.border_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.20)
	button.add_theme_stylebox_override("disabled", disabled)
	button.add_theme_color_override("font_color", INK)
	button.add_theme_color_override("font_hover_color", INK)
	button.add_theme_color_override("font_pressed_color", INK)
	button.add_theme_color_override("font_disabled_color", INK_FAINT)
	button.add_theme_font_size_override("font_size", 13)


## 把任意按钮改成「主操作」样式（青玉底纸色字）。
static func style_primary(button: Button) -> void:
	button.add_theme_stylebox_override("normal", primary_button())
	var hover: StyleBoxFlat = primary_button()
	hover.bg_color = JADE
	button.add_theme_stylebox_override("hover", hover)
	var pressed: StyleBoxFlat = primary_button()
	pressed.bg_color = JADE_DEEP.darkened(0.18)
	button.add_theme_stylebox_override("pressed", pressed)
	var disabled: StyleBoxFlat = primary_button()
	disabled.bg_color = Color(0.62, 0.65, 0.62, 0.55)
	disabled.border_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.25)
	button.add_theme_stylebox_override("disabled", disabled)
	button.add_theme_color_override("font_color", PAPER)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", PAPER)
	button.add_theme_color_override("font_disabled_color", Color(0.86, 0.85, 0.81, 0.65))
	button.add_theme_font_size_override("font_size", 13)


## 资源徽章色：13 项资源各给一个「工笔颜料」色，顶栏图标底衬用它。
static func resource_color(key: String) -> Color:
	match key:
		"spiritPower": return Color("6fa38f")
		"spiritStones": return Color("5b93a6")
		"workPower": return Color("b08a52")
		"prestige": return Color("8f7bb0")
		"food": return Color("9bb35f")
		"qiYun": return Color("c9a227")
		"daoPoints": return Color("4a7d96")
		"materials.tian_jing": return Color("7fa8b8")
		"materials.xuan_tie": return Color("6d757c")
		"materials.ling_mu": return Color("8a6b45")
		"luxuries.ling_cha": return Color("7f9f5a")
		"luxuries.yun_jin": return Color("b0705a")
		"luxuries.ling_yu": return Color("a8b8a0")
	return Color("8a958d")


# ===========================================================================
# 卷轴 / 面板组件库（回合结算、道统树、存档、战斗、胜利五个界面共用）
# ===========================================================================

## 卷轴纸面：双层描边（外金内墨）+ 圆角，压在地图上仍透出山水。
static func scroll_paper(alpha: float = 0.965, radius: int = 4) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.969, 0.957, 0.918, alpha)
	style.border_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.72)
	style.set_border_width_all(1)
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	return style


## 卷轴轴身（木质圆杆）：只在上下两端露头，中间是纸。
static func roller_wood() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color("8d6b3f")
	style.border_color = Color("5d4526")
	style.set_border_width_all(1)
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3
	return style


## 深墨卡片（战斗数值卡、存档缩略图底）。
static func ink_card(alpha: float = 0.90, radius: int = 3) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.169, 0.227, 0.216, alpha)
	style.border_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.62)
	style.set_border_width_all(1)
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	return style


## 墨绿标题条（参考图里「资源收支」「重要事件」那种小标题带）。
static func title_band(color: Color = JADE_DEEP) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(color.r, color.g, color.b, 0.94)
	style.border_color = Color(GOLD_LIGHT.r, GOLD_LIGHT.g, GOLD_LIGHT.b, 0.70)
	style.border_width_left = 3
	style.border_width_right = 3
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 2
	style.corner_radius_top_right = 2
	style.corner_radius_bottom_left = 2
	style.corner_radius_bottom_right = 2
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 3.0
	style.content_margin_bottom = 3.0
	return style


## 青玉药丸（参考图底部「下一回合」那种胶囊按钮）。
static func pill(color: Color = JADE_DEEP) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = Color(GOLD_LIGHT.r, GOLD_LIGHT.g, GOLD_LIGHT.b, 0.92)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 18
	style.corner_radius_top_right = 18
	style.corner_radius_bottom_left = 18
	style.corner_radius_bottom_right = 18
	style.content_margin_left = 26.0
	style.content_margin_right = 26.0
	style.content_margin_top = 7.0
	style.content_margin_bottom = 7.0
	return style


## 圆形动作钮（战斗界面「移动/攻击/技能/待机/撤退」）。
static func round_action(fill: Color = Color(0.169, 0.227, 0.216, 0.94)) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = Color(GOLD_LIGHT.r, GOLD_LIGHT.g, GOLD_LIGHT.b, 0.85)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 64
	style.corner_radius_top_right = 64
	style.corner_radius_bottom_left = 64
	style.corner_radius_bottom_right = 64
	style.content_margin_left = 4.0
	style.content_margin_right = 4.0
	style.content_margin_top = 4.0
	style.content_margin_bottom = 4.0
	return style


## 存档槽卡片（左侧序号徽章 + 内容 + 右侧三枚按钮）。
static func slot_card(selected: bool = false) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.984, 0.973, 0.941, 0.96) if not selected else Color(1.0, 0.988, 0.945, 0.99)
	style.border_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.55) if not selected else Color(GOLD.r, GOLD.g, GOLD.b, 0.95)
	style.set_border_width_all(2 if selected else 1)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	return style


## 进度条底槽。
static func bar_groove() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.78, 0.76, 0.70, 0.55)
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3
	return style


## 进度条填充。
static func bar_fill(color: Color = JADE) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3
	return style


## 竖排题签（参考图左侧「回合结算」「存档」「道法」那种竖写的标题带）。
static func vertical_title(text: String, size: int = 26) -> Label:
	var chars: PackedStringArray = PackedStringArray()
	for index: int in range(text.length()):
		chars.append(text.substr(index, 1))
	var label: Label = Label.new()
	label.text = "\n".join(chars)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", PAPER)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label


## 一行「图标 + 名称 + 数值」的资源行（回合结算左侧栏用）。
## `delta` 正数朱红、负数青绿——与中式「进项为红、支出为绿」的账册习惯一致。
static func resource_row(icon: Texture2D, name_text: String, delta: int, show_sign: bool = true) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var icon_rect: TextureRect = TextureRect.new()
	icon_rect.custom_minimum_size = Vector2(18, 18)
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if icon != null:
		icon_rect.texture = icon
	row.add_child(icon_rect)
	var name_label: Label = Label.new()
	name_label.text = name_text
	name_label.add_theme_font_size_override("font_size", 13)
	name_label.add_theme_color_override("font_color", INK)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	var value_label: Label = Label.new()
	value_label.name = "Delta"
	if delta > 0:
		value_label.text = ("+%d" % delta) if show_sign else str(delta)
		value_label.add_theme_color_override("font_color", Color("a8382c"))
	elif delta < 0:
		value_label.text = ("-%d" % absi(delta)) if show_sign else str(delta)
		value_label.add_theme_color_override("font_color", Color("2f6b4f"))
	else:
		value_label.text = "0"
		value_label.add_theme_color_override("font_color", INK_FAINT)
	value_label.add_theme_font_size_override("font_size", 13)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.custom_minimum_size = Vector2(64, 0)
	row.add_child(value_label)
	return row


## 「新」角标（参考图事件卡右上角的朱红小签）。
static func new_badge() -> PanelContainer:
	var badge: PanelContainer = PanelContainer.new()
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = CINNABAR
	style.border_color = Color(GOLD_LIGHT.r, GOLD_LIGHT.g, GOLD_LIGHT.b, 0.85)
	style.set_border_width_all(1)
	style.corner_radius_top_left = 2
	style.corner_radius_top_right = 2
	style.corner_radius_bottom_left = 2
	style.corner_radius_bottom_right = 2
	style.content_margin_left = 4.0
	style.content_margin_right = 4.0
	style.content_margin_top = 0.0
	style.content_margin_bottom = 0.0
	badge.add_theme_stylebox_override("panel", style)
	var label: Label = Label.new()
	label.text = "新"
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", Color("fdf6e6"))
	badge.add_child(label)
	return badge


## 花饰分隔线（中间一枚菱形，两侧细金线）。
static func ornament_divider(width: int = 0) -> Control:
	var holder: HBoxContainer = HBoxContainer.new()
	holder.add_theme_constant_override("separation", 6)
	holder.custom_minimum_size = Vector2(width, 10)
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var left: HSeparator = hairline()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.add_child(left)
	var diamond: Label = Label.new()
	diamond.text = "◆"
	diamond.add_theme_font_size_override("font_size", 8)
	diamond.add_theme_color_override("font_color", Color(GOLD.r, GOLD.g, GOLD.b, 0.75))
	diamond.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	holder.add_child(diamond)
	var right: HSeparator = hairline()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.add_child(right)
	return holder


## 细进度条（底槽 + 填充）见 `RatioBar.gd`；本类只提供底槽与填充的样式。
