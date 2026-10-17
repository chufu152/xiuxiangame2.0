class_name ScrollFrame
extends Control
## 水墨卷轴外框：左右木轴 + 纸面 + 竖排题签 + 内容区。
##
## 五个界面（回合结算 / 道统树 / 存档 / 战斗 / 胜利结算）共用同一套外框，
## 避免每处各写一遍 `StyleBoxFlat` 字面量导致风格漂移。
##
## 结构（全部用锚点自适应，调用方只需设置本控件的 rect）：
##   Shadow     阴影纸（下移 3px 的半透明深色，制造「卷轴压在画上」的厚度）
##   Paper      纸面
##   InnerLine  纸面内一圈细金线
##   RollerL/R  左右木轴（上下各一枚金色轴头）
##   TitleBand  左侧竖排题签（可选）
##   Body       内容区（`content` 是它内部的 VBoxContainer）

## 内容容器：调用方往这里塞控件。
var content: VBoxContainer = null

var _paper: PanelContainer = null
var _title_band: PanelContainer = null
var _title_label: Label = null
var _body: MarginContainer = null


## `title` 为空则不画题签；`title_width` 为题签宽度（含轴），`paper_alpha` 控制透光度。
func build(title: String = "", title_width: int = 54, paper_alpha: float = 0.965) -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	clip_contents = false

	var shadow: PanelContainer = PanelContainer.new()
	shadow.name = "Shadow"
	shadow.anchor_right = 1.0
	shadow.anchor_bottom = 1.0
	shadow.offset_left = 4.0
	shadow.offset_top = 6.0
	shadow.offset_right = 4.0
	shadow.offset_bottom = 6.0
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shadow_style: StyleBoxFlat = StyleBoxFlat.new()
	shadow_style.bg_color = Color(0.10, 0.13, 0.12, 0.20)
	shadow_style.corner_radius_top_left = 6
	shadow_style.corner_radius_top_right = 6
	shadow_style.corner_radius_bottom_left = 6
	shadow_style.corner_radius_bottom_right = 6
	shadow.add_theme_stylebox_override("panel", shadow_style)
	add_child(shadow)

	_paper = PanelContainer.new()
	_paper.name = "Paper"
	_paper.anchor_right = 1.0
	_paper.anchor_bottom = 1.0
	_paper.add_theme_stylebox_override("panel", UiTheme.scroll_paper(paper_alpha, 6))
	add_child(_paper)

	# 内圈细金线：用空 PanelContainer 叠一层描边，纸面本身的描边留给外缘。
	var inner: PanelContainer = PanelContainer.new()
	inner.name = "InnerLine"
	inner.anchor_right = 1.0
	inner.anchor_bottom = 1.0
	inner.offset_left = 7.0
	inner.offset_top = 7.0
	inner.offset_right = -7.0
	inner.offset_bottom = -7.0
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var inner_style: StyleBoxFlat = StyleBoxFlat.new()
	inner_style.bg_color = Color(0, 0, 0, 0)
	inner_style.border_color = Color(UiTheme.GOLD.r, UiTheme.GOLD.g, UiTheme.GOLD.b, 0.34)
	inner_style.set_border_width_all(1)
	inner.add_theme_stylebox_override("panel", inner_style)
	add_child(inner)

	_add_roller("RollerL", true)
	_add_roller("RollerR", false)

	var left_pad: float = 18.0
	if not title.is_empty():
		_build_title_band(title, title_width)
		left_pad = title_width + 12.0

	_body = MarginContainer.new()
	_body.name = "Body"
	_body.anchor_right = 1.0
	_body.anchor_bottom = 1.0
	_body.offset_left = left_pad
	_body.offset_top = 16.0
	_body.offset_right = -26.0
	_body.offset_bottom = -16.0
	add_child(_body)

	content = VBoxContainer.new()
	content.name = "Content"
	content.add_theme_constant_override("separation", 8)
	_body.add_child(content)


## 左右木轴：一根圆杆 + 上下两枚金色轴头。
func _add_roller(node_name: String, is_left: bool) -> void:
	var roller: PanelContainer = PanelContainer.new()
	roller.name = node_name
	roller.anchor_top = 0.0
	roller.anchor_bottom = 1.0
	roller.offset_top = 12.0
	roller.offset_bottom = -12.0
	roller.custom_minimum_size = Vector2(16, 0)
	roller.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if is_left:
		roller.anchor_left = 0.0
		roller.anchor_right = 0.0
		roller.offset_left = 4.0
		roller.offset_right = 20.0
	else:
		roller.anchor_left = 1.0
		roller.anchor_right = 1.0
		roller.offset_left = -20.0
		roller.offset_right = -4.0
	roller.add_theme_stylebox_override("panel", UiTheme.roller_wood())
	add_child(roller)
	for is_top: bool in [true, false]:
		var cap: PanelContainer = PanelContainer.new()
		cap.name = "CapTop" if is_top else "CapBottom"
		cap.anchor_left = 0.0
		cap.anchor_right = 1.0
		cap.custom_minimum_size = Vector2(0, 12)
		if is_top:
			cap.anchor_top = 0.0
			cap.anchor_bottom = 0.0
			cap.offset_top = -12.0
			cap.offset_bottom = 0.0
		else:
			cap.anchor_top = 1.0
			cap.anchor_bottom = 1.0
			cap.offset_top = 0.0
			cap.offset_bottom = 12.0
		cap.offset_left = -3.0
		cap.offset_right = 3.0
		cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var cap_style: StyleBoxFlat = StyleBoxFlat.new()
		cap_style.bg_color = Color("c9a227")
		cap_style.border_color = Color("8a6a1e")
		cap_style.set_border_width_all(1)
		cap_style.corner_radius_top_left = 5
		cap_style.corner_radius_top_right = 5
		cap_style.corner_radius_bottom_left = 5
		cap_style.corner_radius_bottom_right = 5
		cap.add_theme_stylebox_override("panel", cap_style)
		roller.add_child(cap)


## 左侧竖排题签：深青底 + 金色上下缘 + 竖写字。
func _build_title_band(title: String, title_width: int) -> void:
	_title_band = PanelContainer.new()
	_title_band.name = "TitleBand"
	_title_band.anchor_top = 0.0
	_title_band.anchor_bottom = 1.0
	_title_band.offset_left = 24.0
	_title_band.offset_right = float(title_width)
	_title_band.offset_top = 14.0
	_title_band.offset_bottom = -14.0
	_title_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var band_style: StyleBoxFlat = StyleBoxFlat.new()
	band_style.bg_color = Color(0.184, 0.353, 0.322, 0.96)
	band_style.border_color = Color(UiTheme.GOLD_LIGHT.r, UiTheme.GOLD_LIGHT.g, UiTheme.GOLD_LIGHT.b, 0.80)
	band_style.border_width_top = 2
	band_style.border_width_bottom = 2
	band_style.corner_radius_top_left = 2
	band_style.corner_radius_top_right = 2
	band_style.corner_radius_bottom_left = 2
	band_style.corner_radius_bottom_right = 2
	band_style.content_margin_top = 14.0
	band_style.content_margin_bottom = 14.0
	_title_band.add_theme_stylebox_override("panel", band_style)
	add_child(_title_band)

	_title_label = UiTheme.vertical_title(title, 24)
	_title_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_title_band.add_child(_title_label)


## 更换题签文字（同一外框复用给不同界面时用）。
func set_title(title: String) -> void:
	if _title_label == null:
		return
	var chars: PackedStringArray = PackedStringArray()
	for index: int in range(title.length()):
		chars.append(title.substr(index, 1))
	_title_label.text = "\n".join(chars)
