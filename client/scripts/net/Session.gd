extends Node

signal status_changed()
signal view_changed(view: Dictionary)
signal game_started()

var net: NetClient = null
var camera_rig: CameraRig = null
var assets: AssetLibrary = null
var current_view: Dictionary = {}
var hello: Dictionary = {}
var status: String = "尚未连接"
var view_revision: int = 0
var pending: Dictionary = {}
var busy: bool = false
var server_pid: int = -1
var port: int = Msg.DEFAULT_PORT
var connection_started: bool = false
var shutting_down: bool = false

func _ready() -> void:
	assets = AssetLibrary.new()
	assets.name = "AssetLibrary"
	add_child(assets)
	camera_rig = CameraRig.new()
	camera_rig.name = "CameraRig"
	add_child(camera_rig)
	net = NetClient.new()
	net.name = "NetClient"
	add_child(net)
	net.handshake_received.connect(_on_hello)
	net.response_received.connect(_on_response)
	net.connect_failed.connect(_on_connect_failed)
	net.disconnected.connect(_on_disconnected)
	net.connected.connect(func() -> void: _set_status("已连接，等待 hello"))

func start_connection(target_port: int = Msg.DEFAULT_PORT) -> void:
	if connection_started:
		return
	port = target_port
	connection_started = true
	_set_status("正在连接本地服务端…")
	net.connect_to_server(Msg.DEFAULT_HOST, port)

func supports(command: String) -> bool:
	return net.is_ready() and (hello.get("implementedCommands", []) as Array).has(command)

func request_new_game(params: Dictionary) -> String:
	return _request(Commands.NEW_GAME, params)

func request_refresh() -> String:
	return _request(Commands.GET_STATE, {})

func _request(command: String, params: Dictionary) -> String:
	if busy or not supports(command):
		_set_status("服务端未就绪或不支持 " + command)
		return ""
	busy = true
	var request_id: String = net.send_command(command, params)
	pending[request_id] = command
	_set_status("请求 " + command + "…")
	return request_id

func accept_view(view: Dictionary) -> void:
	current_view = view.duplicate(true)
	view_revision += 1
	view_changed.emit(current_view)

func _on_hello(payload: Dictionary) -> void:
	hello = payload.duplicate(true)
	_set_status("本地服务端已就绪 · 协议 %s" % str(hello.get("protocolVersion", "?")))

func _on_response(response: Dictionary) -> void:
	var request_id: String = str(response.get("id", ""))
	var command: String = str(pending.get(request_id, ""))
	pending.erase(request_id)
	busy = not pending.is_empty()
	if not bool(response.get("ok", false)):
		_set_status("%s：%s" % [str(response.get("errorCode", "请求失败")), str(response.get("message", ""))])
		return
	var result: Dictionary = response.get("result", {})
	if result.has("success") and not bool(result["success"]):
		_set_status(str(result.get("message", "开局失败")))
		return
	if response.get("view") is Dictionary:
		accept_view(response["view"])
		if command == Commands.NEW_GAME:
			game_started.emit()
	_set_status("已同步服务端 view")

func _on_connect_failed(message: String) -> void:
	if server_pid > 0:
		_set_status(message)
		return
	var result: Dictionary = Launcher.launch(port)
	if not bool(result["ok"]):
		_set_status(str(result["error"]))
		return
	server_pid = int(result["pid"])
	_set_status("本地服务端已启动，等待连接…")
	await get_tree().create_timer(0.5).timeout
	if not shutting_down:
		net.connect_to_server(Msg.DEFAULT_HOST, port)

func _on_disconnected(_code: int, reason: String) -> void:
	hello.clear()
	pending.clear()
	busy = false
	_set_status("连接已断开：" + reason)

func _set_status(value: String) -> void:
	status = value
	status_changed.emit()

func shutdown() -> void:
	if shutting_down:
		return
	shutting_down = true
	if net != null:
		net.disconnect_from_server()
	if server_pid > 0:
		Launcher.stop(server_pid)
		server_pid = -1

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		shutdown()
		get_tree().quit()

func _exit_tree() -> void:
	shutdown()
