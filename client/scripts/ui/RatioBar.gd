class_name RatioBar
extends HBoxContainer
## 细进度条：底槽 + 填充两段按比例分配宽度。
##
## 为什么不用 `ProgressBar`：参考图里的进度条是「纸槽 + 青玉条」两段独立描边，
## `ProgressBar` 的 fill 只能整块换色、做不出双层圆角。这里用两个 `PanelContainer`
## 靠 `size_flags_stretch_ratio` 分配宽度，外观完全可控，且不需要每帧重算像素宽度。

## 填充段（外部可改样式，例如战斗里按血量换色）。
var fill: PanelContainer = null
## 底槽段。
var groove: PanelContainer = null
## 当前比例（0–1）。
var ratio: float = 0.0


func setup(color: Color = UiTheme.JADE, bar_height: int = 6) -> void:
	add_theme_constant_override("separation", 0)
	custom_minimum_size = Vector2(0, bar_height)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 顺序要紧：填充段必须**先**加，才能排在左边；底槽随后铺满右侧剩余宽度。
	fill = PanelContainer.new()
	fill.name = "Fill"
	fill.add_theme_stylebox_override("panel", UiTheme.bar_fill(color))
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	fill.custom_minimum_size = Vector2(0, bar_height)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fill)
	groove = PanelContainer.new()
	groove.name = "Groove"
	groove.add_theme_stylebox_override("panel", UiTheme.bar_groove())
	groove.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	groove.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	groove.custom_minimum_size = Vector2(0, bar_height)
	groove.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(groove)
	set_ratio(0.0)


func set_ratio(value: float) -> void:
	ratio = clampf(value, 0.0, 1.0)
	if fill == null or groove == null:
		return
	# 两段都 EXPAND_FILL，宽度按 size_flags_stretch_ratio 分摊：填充占 ratio，底槽占 1-ratio。
	# （Godot 4 里 Control.stretch_ratio 已更名为 size_flags_stretch_ratio。）
	fill.size_flags_stretch_ratio = maxf(ratio, 0.0001)
	groove.size_flags_stretch_ratio = maxf(1.0 - ratio, 0.0001)


## 换填充色（血量/进度语义变化时用）。
func set_color(color: Color) -> void:
	if fill != null:
		fill.add_theme_stylebox_override("panel", UiTheme.bar_fill(color))
