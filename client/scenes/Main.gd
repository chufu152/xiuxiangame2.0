extends Control
## 客户端主界面（R0 工程骨架）。
##
## 显示：连接状态、hello 各字段、一个 Ping 按钮、回包日志；启动自动连接。
## 连不上时自动拉起本地 headless 服务端（Launcher），退出时回收该子进程。
##
## R1 起本场景将被 MainMenu + World 取代，NetClient / Launcher 保持不变。

const HOST: String = Msg.DEFAULT_HOST
const PORT: int = Msg.DEFAULT_PORT

var _net: NetClient = null
var _server_pid: int = -1
var _launched_server: bool = false

var _status_label: Label = null
var _hello_label: Label = null
var _log_view: RichTextLabel = null
var _ping_button: Button = null


func _ready() -> void:
	_build_ui()

	_net = NetClient.new()
	_net.name = "NetClient"
	add_child(_net)
	_net.connected.connect(_on_connected)
	_net.handshake_received.connect(_on_handshake_received)
	_net.response_received.connect(_on_response_received)
	_net.server_message.connect(_on_server_message)
	_net.disconnected.connect(_on_disconnected)
	_net.connect_failed.connect(_on_connect_failed)
	_net.retry_scheduled.connect(_on_retry_scheduled)

	_log("客户端启动：Godot %s" % Engine.get_version_info()["string"])
	_log("目标服务端：ws://%s:%d" % [HOST, PORT])
	_log("服务端工程：%s" % Launcher.server_project_dir())
	_set_status("连接中…")
	_net.connect_to_server(HOST, PORT)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_shutdown()


# ---------------------------------------------------------------------------
# 连接流程
# ---------------------------------------------------------------------------

func _on_connected() -> void:
	_set_status("已连接，等待 hello…")
	_log("WebSocket 通道已建立")


func _on_retry_scheduled(attempt: int, delay_sec: float) -> void:
	_log("连接失败，%.2f 秒后进行第 %d 次尝试" % [delay_sec, attempt])


func _on_handshake_received(hello: Dictionary) -> void:
	var implemented: Array = hello.get(Msg.KEY_IMPLEMENTED_COMMANDS, [])
	_set_status("已连接")
	_hello_label.text = "\n".join(PackedStringArray([
		"protocolVersion：%s" % str(hello.get(Msg.KEY_PROTOCOL_VERSION, "?")),
		"backend：%s" % str(hello.get(Msg.KEY_BACKEND, "?")),
		"saveVersion：%s" % str(hello.get(Msg.KEY_SAVE_VERSION, "?")),
		"implementedCommands：%s" % JSON.stringify(implemented),
	]))
	_ping_button.disabled = false
	_log("[握手] 收到 hello：%s" % JSON.stringify(hello))


func _on_connect_failed(message: String) -> void:
	_log("[失败] %s" % message)
	if _launched_server:
		_set_status("连接失败（服务端已拉起但仍无法连接）")
		return
	_launch_server_and_retry()


func _launch_server_and_retry() -> void:
	_set_status("未发现服务端，正在拉起 headless 子进程…")
	_log("尝试拉起本地服务端 …")
	var outcome: Dictionary = Launcher.launch(PORT)
	if not bool(outcome["ok"]):
		_set_status("启动服务端失败")
		_log("[错误] %s" % str(outcome["error"]))
		return

	_server_pid = int(outcome["pid"])
	_launched_server = true
	_log("已拉起服务端子进程 pid=%d" % _server_pid)
	_log("  %s" % str(outcome["command"]))

	# 进程启动到开始监听需要一点时间，稍后重连。
	await get_tree().create_timer(1.0).timeout
	if not is_inside_tree():
		return
	_net.restart_attempts()
	_net.connect_to_server(HOST, PORT)


func _shutdown() -> void:
	if _net != null:
		_net.disconnect_from_server()
	if _launched_server and _server_pid > 0:
		Launcher.stop(_server_pid)
		_log("已回收服务端子进程 pid=%d" % _server_pid)
		_server_pid = -1
	get_tree().quit()


# ---------------------------------------------------------------------------
# 命令往返
# ---------------------------------------------------------------------------

func _on_response_received(response: Dictionary) -> void:
	if bool(response.get(Msg.KEY_OK, false)):
		_log("[回包] id=%s ok=true result=%s"
			% [str(response.get(Msg.KEY_ID, "")), JSON.stringify(response.get(Msg.KEY_RESULT, {}))])
	else:
		_log("[回包] id=%s ok=false errorCode=%s message=%s"
			% [str(response.get(Msg.KEY_ID, "")),
			   str(response.get(Msg.KEY_ERROR_CODE, "")),
			   str(response.get(Msg.KEY_MESSAGE, ""))])


func _on_server_message(payload: Dictionary) -> void:
	_log("[主动消息] %s" % JSON.stringify(payload))


func _on_disconnected(code: int, reason: String) -> void:
	_set_status("连接已断开")
	_log("连接已断开（code=%d %s）" % [code, reason])


func _on_ping_pressed() -> void:
	var request_id: String = _net.send_command(Commands.PING)
	_log("已发送 ping（id=%s）" % request_id)


# ---------------------------------------------------------------------------
# UI
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var background: ColorRect = ColorRect.new()
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.color = Color("1b1b1f")
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_bottom", 24)
	add_child(margin)

	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)

	var title: Label = Label.new()
	title.text = "修仙4X·宗门争霸 2.0 —— R0 工程骨架"
	title.add_theme_font_size_override("font_size", 22)
	column.add_child(title)

	var subtitle: Label = Label.new()
	subtitle.text = "客户端（表现层）通过 WebSocket 连接 headless 服务端（权威规则层）；客户端不含任何玩法规则。"
	subtitle.add_theme_font_size_override("font_size", 13)
	subtitle.modulate = Color("9a9aa5")
	column.add_child(subtitle)

	column.add_child(HSeparator.new())

	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", 18)
	column.add_child(_status_label)

	_hello_label = Label.new()
	_hello_label.add_theme_font_size_override("font_size", 13)
	_hello_label.modulate = Color("9a9aa5")
	column.add_child(_hello_label)

	var buttons: HBoxContainer = HBoxContainer.new()
	column.add_child(buttons)

	_ping_button = Button.new()
	_ping_button.text = "Ping"
	_ping_button.disabled = true
	_ping_button.pressed.connect(_on_ping_pressed)
	buttons.add_child(_ping_button)

	column.add_child(HSeparator.new())

	_log_view = RichTextLabel.new()
	_log_view.bbcode_enabled = true
	_log_view.scroll_following = true
	_log_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log_view.add_theme_font_size_override("normal_font_size", 13)
	column.add_child(_log_view)


func _set_status(text: String) -> void:
	if _status_label != null:
		_status_label.text = text


func _log(message: String) -> void:
	print("[Client] %s" % message)
	if _log_view != null:
		_log_view.append_text(message + "\n")
