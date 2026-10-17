class_name Toast
extends PanelContainer
## 轻提示条（§8.4「Toast：事件与业务失败文案」）。
##
## 只做「显示一段文字 + 自动淡出」，不参与任何规则判定；
## 文案由调用方传入（业务失败取 `result.message`，事件取 `events[]`）。

const DEFAULT_SECONDS: float = 3.2

var label: Label = null
var _remaining: float = 0.0
var _shown: String = ""


func setup() -> void:
	name = "Toast"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = -230.0
	offset_right = 230.0
	offset_top = -104.0
	offset_bottom = -62.0
	modulate = Color(1, 1, 1, 0)
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.15, 0.14, 0.92)
	style.border_color = Color("c9a227")
	style.border_width_left = 2
	style.border_width_right = 2
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	add_theme_stylebox_override("panel", style)
	label = Label.new()
	label.name = "ToastText"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color("f0e9d6"))
	add_child(label)


func show_message(text: String, seconds: float = DEFAULT_SECONDS) -> void:
	if text.strip_edges().is_empty():
		return
	_shown = text
	if label != null:
		label.text = text
	_remaining = maxf(seconds, 0.6)
	modulate = Color(1, 1, 1, 1)


func _process(delta: float) -> void:
	if _remaining <= 0.0:
		return
	_remaining -= delta
	if _remaining <= 0.0:
		modulate = Color(1, 1, 1, 0)
		return
	# 最后 0.6 秒淡出。
	modulate = Color(1, 1, 1, clampf(_remaining / 0.6, 0.0, 1.0))


## 供自动验收断言。
func text() -> String:
	return "" if label == null else label.text


func is_visible_now() -> bool:
	return modulate.a > 0.01
