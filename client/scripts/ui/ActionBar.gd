class_name ActionBar
extends PanelContainer
## 底部操作栏（§8.4 布局要求：顶部资源栏 / 底部操作栏 / 左侧城市弟子 / 右侧势力胜利）。
##
## 本类同时充当 **69 命令 UI 入口登记表**：每条已实现命令都必须在这里登记一条入口，
## 入口分三类，`state_of()` 对三类都给出可机检的结果——
##   - `button`：真实 `Button` 节点（面板入口 / 面板内按钮），可断言存在与禁用态；
##   - `gesture`：地图手势入口（点地块 / 悬停 / Shift 多选），断言「手势可达」；
##   - `auto`：随 view / 回合流程自动触发，断言「流程已接」。
##
## 硬约束：本类只做「发信号」，**不拼参数、不推导规则**——参数一律由 World 依据服务端
## 回包填充后调用 `Session.request_*`。相机角度与缩放全程不参与（相机铁律）。

## 用户点击某个入口时抛出命令名（World 据此执行）。
signal command_pressed(command: String)

const BAR_HEIGHT: float = 52.0
const SIDEBAR_WIDTH: float = 320.0

## command → { kind: "button"|"gesture"|"auto", label: String, button: Button|null }
var entries: Dictionary = {}
var row: HBoxContainer = null
var status_label: Label = null

var _groups: Dictionary = {}


func setup() -> void:
	name = "ActionBar"
	anchor_left = 0.0
	anchor_right = 1.0
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = 0.0
	offset_right = 0.0
	offset_top = -BAR_HEIGHT
	offset_bottom = 0.0
	# 与顶栏同一条「纸带」：宣纸半透明 + 上缘金线，避免底部一条深色横杠压住画面。
	var style: StyleBoxFlat = UiTheme.bar()
	style.border_width_bottom = 0
	style.border_width_top = 1
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 5.0
	style.content_margin_bottom = 5.0
	add_theme_stylebox_override("panel", style)

	row = HBoxContainer.new()
	row.name = "Row"
	row.add_theme_constant_override("separation", 6)
	add_child(row)

	status_label = Label.new()
	status_label.name = "BarHint"
	status_label.text = "左键选中 / 悬停预览 · 空格或 End 结束回合 · G 网格 · B 边框"
	status_label.add_theme_font_size_override("font_size", 11)
	status_label.add_theme_color_override("font_color", UiTheme.INK_FAINT)
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(status_label)


## 建一个分组容器（纯排版：让「城市 / 军事 / 势力 / 系统」四簇按钮分开）。
func add_group(group_name: String, separator: bool = true) -> void:
	if _groups.has(group_name):
		return
	if separator and row.get_child_count() > 0:
		var line: VSeparator = VSeparator.new()
		row.add_child(line)
	var box: HBoxContainer = HBoxContainer.new()
	box.name = group_name
	box.add_theme_constant_override("separation", 4)
	# 提示文字始终贴右，故新分组插在它之前。
	row.add_child(box)
	row.move_child(box, status_label.get_index())
	_groups[group_name] = box


## 登记一个按钮型入口，并把按钮挂进指定分组。
func add(command: String, text: String, tooltip: String, callback: Callable,
		group_name: String = "") -> Button:
	var button: Button = Button.new()
	button.name = _node_name_for(command)
	button.text = text
	button.tooltip_text = tooltip
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(func() -> void:
		command_pressed.emit(command)
		callback.call())
	var parent: Node = _groups.get(group_name, row)
	parent.add_child(button)
	entries[command] = {"kind": "button", "label": text, "button": button}
	return button


## 登记「面板内按钮」型入口（按钮不在底栏，而在某个面板里）。
func register_panel_button(command: String, text: String, button: Button) -> void:
	entries[command] = {"kind": "button", "label": text, "button": button}


## 纯显示开关（网格 / 边框 / 小地图 / 引导）：**不是协议命令**，故不登记到命令表。
func add_plain(text: String, tooltip: String, callback: Callable, group_name: String = "") -> Button:
	var button: Button = Button.new()
	button.text = text
	button.tooltip_text = tooltip
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(callback)
	var parent: Node = _groups.get(group_name, row)
	parent.add_child(button)
	return button


## 登记手势型入口（点地块 / 悬停 / Shift 多选）。
func register_gesture(command: String, label: String) -> void:
	entries[command] = {"kind": "gesture", "label": label, "button": null}


## 登记自动触发型入口（随 view 刷新 / 回合流程）。
func register_auto(command: String, label: String) -> void:
	entries[command] = {"kind": "auto", "label": label, "button": null}


func has_entry(command: String) -> bool:
	return entries.has(command)


func kind_of(command: String) -> String:
	return str((entries.get(command, {}) as Dictionary).get("kind", ""))


func button_for(command: String) -> Button:
	var button: Variant = (entries.get(command, {}) as Dictionary).get("button", null)
	if button is Button and is_instance_valid(button):
		return button as Button
	return null


## 入口状态快照（供 R8 自动验收断言）。
## `exists`：按钮型=节点有效；手势/自动型=已登记（其可达性由 World 的状态断言覆盖）。
func state_of(command: String) -> Dictionary:
	var entry: Dictionary = entries.get(command, {})
	if entry.is_empty():
		return {"registered": false, "kind": "", "label": "", "exists": false,
			"enabled": false, "text": "", "tooltip": ""}
	var kind: String = str(entry.get("kind", ""))
	if kind != "button":
		return {"registered": true, "kind": kind, "label": str(entry.get("label", "")),
			"exists": true, "enabled": true, "text": str(entry.get("label", "")), "tooltip": ""}
	var button: Button = button_for(command)
	if button == null:
		return {"registered": true, "kind": kind, "label": str(entry.get("label", "")),
			"exists": false, "enabled": false, "text": "", "tooltip": ""}
	return {"registered": true, "kind": kind, "label": str(entry.get("label", "")),
		"exists": true, "enabled": not button.disabled, "text": button.text,
		"tooltip": button.tooltip_text}


func registered_commands() -> Array[String]:
	var commands: Array[String] = []
	for command: String in entries.keys():
		commands.append(command)
	commands.sort()
	return commands


func registered_count() -> int:
	return entries.size()


func button_count() -> int:
	var total: int = 0
	for command: String in entries.keys():
		if kind_of(command) == "button" and button_for(command) != null:
			total += 1
	return total


## 给按钮设禁用态并同步 blocker 文案（不可用按钮必须置灰 + 悬浮说明原因）。
func set_blocked(command: String, blocked: bool, blocker: String = "") -> void:
	var button: Button = button_for(command)
	if button == null:
		return
	button.disabled = blocked
	if blocked and not blocker.is_empty():
		button.tooltip_text = blocker


func set_hint(text: String) -> void:
	if status_label != null:
		status_label.text = text


## 命令名 → 稳定的节点名（`queryMoveRange` → `Entry_queryMoveRange`）。
func _node_name_for(command: String) -> String:
	return "Entry_" + command
