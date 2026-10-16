extends Node

signal status_changed()
signal view_changed(view: Dictionary)
signal game_started()
## queryMoveRange 不回 view，结果经本信号交给世界层（高亮层据此绘制）。
signal move_range_received(result: Dictionary)
## moveDisciple 的 MoveResult（成功或业务失败），供状态栏提示。
signal move_result_received(result: Dictionary)
## 「结束回合」两步序列（finishTurn → beginPlayerTurn）走完（或中断）时发出。
signal end_turn_finished()

## 拉起服务端后的就绪总超时。实测冷启动 2.18s / 6.49s / 19s 波动极大，故取 40s 留足余量。
const SERVER_READY_TIMEOUT_SEC: float = 40.0
## 就绪轮询间隔：每 0.5s 尝试连接一次。
const READY_POLL_INTERVAL_SEC: float = 0.5

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
var ready_loop_running: bool = false
## 「结束回合」序列是否进行中（finishTurn 已发、beginPlayerTurn 尚未收尾）。
var end_turn_pending: bool = false

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

func request_query_move_range(disciple_id: String) -> String:
	return _request(Commands.QUERY_MOVE_RANGE, {"discipleId": disciple_id})

func request_move_disciple(disciple_id: String, tile_id: String) -> String:
	return _request(Commands.MOVE_DISCIPLE, {"discipleId": disciple_id, "targetTileId": tile_id})

func request_finish_turn() -> String:
	return _request(Commands.FINISH_TURN, {})

func request_begin_player_turn() -> String:
	return _request(Commands.BEGIN_PLAYER_TURN, {})

## 「结束回合」顺序封装：**先 finishTurn，收到响应后再 beginPlayerTurn**
## （与 1.0 GUI 手动结束回合一致）。期间 busy；最终以 beginPlayerTurn 的 view 渲染。
func request_end_turn_sequence() -> String:
	if end_turn_pending:
		return ""
	end_turn_pending = true
	var sent: String = request_finish_turn()
	if sent.is_empty():
		_abort_end_turn_sequence()
	return sent

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
		if command == Commands.FINISH_TURN or command == Commands.BEGIN_PLAYER_TURN:
			_abort_end_turn_sequence()
		return
	var result: Dictionary = response.get("result", {})
	if result.has("success") and not bool(result["success"]):
		_set_status(str(result.get("message", "请求失败")))
		if command == Commands.MOVE_DISCIPLE:
			move_result_received.emit(result)
		if command == Commands.FINISH_TURN or command == Commands.BEGIN_PLAYER_TURN:
			_abort_end_turn_sequence()
		return
	if response.get("view") is Dictionary:
		accept_view(response["view"])
		if command == Commands.NEW_GAME:
			game_started.emit()
	if command == Commands.QUERY_MOVE_RANGE:
		move_range_received.emit(result)
	elif command == Commands.MOVE_DISCIPLE:
		move_result_received.emit(result)
	_set_status("已同步服务端 view")
	_advance_end_turn_sequence(command)


## 结束回合序列推进：finishTurn 响应到达后再发 beginPlayerTurn。
func _advance_end_turn_sequence(command: String) -> void:
	if not end_turn_pending:
		return
	if command == Commands.FINISH_TURN:
		var sent: String = request_begin_player_turn()
		if sent.is_empty():
			_abort_end_turn_sequence()
	elif command == Commands.BEGIN_PLAYER_TURN:
		end_turn_pending = false
		end_turn_finished.emit()


func _abort_end_turn_sequence() -> void:
	if not end_turn_pending:
		return
	end_turn_pending = false
	end_turn_finished.emit()

func _on_connect_failed(message: String) -> void:
	if shutting_down:
		return
	if ready_loop_running:
		return
	if server_pid <= 0:
		var result: Dictionary = Launcher.launch(port)
		if not bool(result["ok"]):
			_set_status(str(result["error"]))
			return
		server_pid = int(result["pid"])
		_set_status("本地服务端已启动，等待就绪…")
	else:
		# 已拉起期间连接失败既不终止等待，也不重复 launch。
		_set_status(message + "，继续等待本地服务端…")
	_await_server_ready()


## 拉起后轮询等待服务端就绪：每 READY_POLL_INTERVAL_SEC 尝试连接一次，
## 直到 hello 声明支持 newGame 或总耗时超过 SERVER_READY_TIMEOUT_SEC。
## 只负责「何时重连」，传输与退避仍由 NetClient 负责（保持其纯传输职责）。
func _await_server_ready() -> void:
	ready_loop_running = true
	var deadline: int = Time.get_ticks_msec() + int(SERVER_READY_TIMEOUT_SEC * 1000.0)
	while not shutting_down and not supports("newGame"):
		if Time.get_ticks_msec() >= deadline:
			_set_status("等待本地服务端就绪超时（%.0f 秒）" % SERVER_READY_TIMEOUT_SEC)
			break
		var state: int = net.get_state()
		# 仅在无在途尝试时重新发起，避免打断正在握手/刚连上的连接。
		if state == NetClient.State.IDLE or state == NetClient.State.FAILED or state == NetClient.State.CLOSED:
			net.connect_to_server(Msg.DEFAULT_HOST, port)
		await get_tree().create_timer(READY_POLL_INTERVAL_SEC).timeout
	ready_loop_running = false

func _on_disconnected(_code: int, reason: String) -> void:
	hello.clear()
	pending.clear()
	busy = false
	_abort_end_turn_sequence()
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
