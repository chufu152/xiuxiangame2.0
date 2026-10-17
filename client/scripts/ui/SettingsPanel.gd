class_name SettingsPanel
extends CanvasLayer
## 设置面板（R8 任务 4）：画面 / 音量 / 快捷键。
##
## 分工（与 `setSetting` 的服务端语义一致）：
##   - **本地偏好**（网格、宗门边框、昼夜、粒子、动画、音量）由本面板立即生效并写本地变量；
##   - 同时向服务端发一次 `setSetting` **仅作确认**（服务端回 `{success, key, value, applied:false}`，
##     不写入 `GameState`、不下发 `view` 字段）。
## 相机角度与缩放全程不参与（相机铁律）。

signal pref_changed(key: String, value: Variant)
signal setting_confirmed(key: String, result: Dictionary)

const PANEL_WIDTH: float = 420.0
const PANEL_HEIGHT: float = 430.0

var panel: PanelContainer = null
var title_label: Label = null
var status_label: Label = null
var open: bool = false
var prefs: Dictionary = {}
var _checks: Dictionary = {}
var _volume: HSlider = null


func setup(defaults: Dictionary) -> void:
	name = "SettingsPanel"
	layer = 4
	prefs = defaults.duplicate(true)
	visible = false

	panel = PanelContainer.new()
	panel.name = "SettingsPanelBox"
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -PANEL_WIDTH * 0.5
	panel.offset_right = PANEL_WIDTH * 0.5
	panel.offset_top = -PANEL_HEIGHT * 0.5
	panel.offset_bottom = PANEL_HEIGHT * 0.5
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.965, 0.957, 0.925, 0.97)
	style.border_color = Color("b6ad8b")
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.content_margin_left = 16.0
	style.content_margin_right = 16.0
	style.content_margin_top = 12.0
	style.content_margin_bottom = 12.0
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)

	title_label = Label.new()
	title_label.text = "设置"
	title_label.add_theme_font_size_override("font_size", 18)
	title_label.add_theme_color_override("font_color", Color("294e48"))
	column.add_child(title_label)

	column.add_child(_section("画面"))
	_check(column, "gridVisible", "显示六边形网格（G）")
	_check(column, "factionBorders", "显示宗门色边框（B）")
	_check(column, "dayNight", "昼夜循环")
	_check(column, "ambientParticles", "灵气粒子与飞鸟")
	_check(column, "animation", "界面动画")

	column.add_child(_section("音量"))
	_volume = HSlider.new()
	_volume.name = "VolumeSlider"
	_volume.min_value = 0.0
	_volume.max_value = 1.0
	_volume.step = 0.05
	_volume.value = float(prefs.get("volume", 0.6))
	_volume.custom_minimum_size = Vector2(0, 22)
	_volume.value_changed.connect(func(value: float) -> void: _apply("volume", value))
	column.add_child(_volume)

	column.add_child(_section("快捷键"))
	var keys: Label = Label.new()
	keys.text = "空格 / End：结束回合　G：网格　B：宗门边框　M：小地图　Esc：关闭面板　F1：新手引导"
	keys.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	keys.add_theme_font_size_override("font_size", 12)
	keys.add_theme_color_override("font_color", Color("5d6b64"))
	column.add_child(keys)

	status_label = Label.new()
	status_label.name = "SettingsStatus"
	status_label.text = "本地偏好立即生效；服务端仅确认，不写入对局状态。"
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_font_size_override("font_size", 12)
	status_label.add_theme_color_override("font_color", Color("6d7470"))
	column.add_child(status_label)

	var close_button: Button = Button.new()
	close_button.name = "SettingsClose"
	close_button.text = "关闭"
	close_button.pressed.connect(func() -> void: close_panel())
	column.add_child(close_button)


func _section(text: String) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color("294e48"))
	return label


func _check(parent: Node, key: String, text: String) -> void:
	var toggle: CheckButton = CheckButton.new()
	toggle.name = "Toggle_" + key
	toggle.text = text
	toggle.button_pressed = bool(prefs.get(key, true))
	toggle.add_theme_font_size_override("font_size", 13)
	toggle.toggled.connect(func(value: bool) -> void: _apply(key, value))
	parent.add_child(toggle)
	_checks[key] = toggle


func _apply(key: String, value: Variant) -> void:
	prefs[key] = value
	pref_changed.emit(key, value)
	# 服务端仅确认；失败不影响本地生效（本地偏好是客户端职责）。
	Session.request_set_setting(key, value)


## 服务端 `setSetting` 回包（`{success, key, value, applied, note}`）。
func on_setting_confirmed(result: Dictionary) -> void:
	if status_label != null:
		status_label.text = "已同步「%s」→ %s（服务端仅确认）" % [
			str(result.get("key", "")), str(result.get("value", ""))]
	setting_confirmed.emit(str(result.get("key", "")), result)


func open_panel() -> void:
	visible = true
	open = true


func close_panel() -> void:
	visible = false
	open = false


func toggle_panel() -> void:
	if open:
		close_panel()
	else:
		open_panel()


func set_pref(key: String, value: Variant) -> void:
	prefs[key] = value
	if _checks.has(key):
		(_checks[key] as CheckButton).set_pressed_no_signal(bool(value))


func pref(key: String) -> Variant:
	return prefs.get(key, null)


func status_text() -> String:
	return "" if status_label == null else status_label.text


func check_state(key: String) -> Dictionary:
	if not _checks.has(key):
		return {}
	var toggle: CheckButton = _checks[key] as CheckButton
	return {"pressed": toggle.button_pressed, "text": toggle.text}
