class_name NetClient
extends Node
## WebSocket 客户端：连接 / 收发包 / 握手 / 首连退避重试（§2.1 / §6.1–§6.3）。
##
## 只做传输与信封解析，**不含任何玩法规则**。
## 首连失败按指数退避重试若干次；重试耗尽后发 connect_failed，由上层决定是否拉起服务端。

signal connected()
signal handshake_received(payload: Dictionary)
signal response_received(response: Dictionary)
signal server_message(payload: Dictionary)
signal disconnected(code: int, reason: String)
signal connect_failed(message: String)
signal retry_scheduled(attempt: int, delay_sec: float)

enum State { IDLE, CONNECTING, HANDSHAKING, READY, CLOSED, FAILED }

## 单次连接尝试的超时（TCP + WebSocket 握手）。
const ATTEMPT_TIMEOUT_SEC: float = 1.5
## 已连上但迟迟收不到 hello 的超时。
const HANDSHAKE_TIMEOUT_SEC: float = 5.0
## 最大尝试次数（含首次）。
const MAX_ATTEMPTS: int = 5
const BASE_RETRY_DELAY_SEC: float = 0.3
const MAX_RETRY_DELAY_SEC: float = 3.0

var _host: String = Msg.DEFAULT_HOST
var _port: int = Msg.DEFAULT_PORT
var _peer: WebSocketPeer = null
var _state: State = State.IDLE
var _request_counter: int = 0
var _attempt: int = 0
var _attempt_elapsed: float = 0.0
var _retry_wait: float = 0.0
var _last_error: String = ""


func get_state() -> State:
	return _state


func get_last_error() -> String:
	return _last_error


func is_ready() -> bool:
	return _state == State.READY


## 开始连接流程（会重置重试计数）。
func connect_to_server(host: String = Msg.DEFAULT_HOST, port: int = Msg.DEFAULT_PORT) -> void:
	_host = host
	_port = port
	_attempt = 0
	_retry_wait = 0.0
	_close_peer()
	_start_attempt()


## 重试计数已耗尽后，由上层（拉起服务端成功）调用以重新开始尝试。
func restart_attempts() -> void:
	_attempt = 0
	_retry_wait = 0.0


func disconnect_from_server() -> void:
	_close_peer()
	_set_state(State.IDLE)


## 发送一条命令；返回本地生成的请求 id（用于与响应配对）。
func send_command(command_name: String, params: Dictionary = {}) -> String:
	_request_counter += 1
	var request_id: String = "c%d" % _request_counter
	if _peer == null or _peer.get_ready_state() != WebSocketPeer.STATE_OPEN:
		_last_error = "连接未就绪，命令 %s 未发送" % command_name
		push_warning("[Client] %s" % _last_error)
		return request_id
	var envelope: Dictionary = {
		Msg.KEY_ID: request_id,
		Msg.KEY_TYPE: command_name,
	}
	if not params.is_empty():
		envelope[Msg.KEY_PARAMS] = params
	_peer.send_text(JSON.stringify(envelope))
	return request_id


func _process(delta: float) -> void:
	if _peer == null:
		if _retry_wait > 0.0:
			_retry_wait -= delta
			if _retry_wait <= 0.0:
				_start_attempt()
		return

	_peer.poll()
	match _peer.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if _state == State.CONNECTING:
				_attempt_elapsed = 0.0
				_set_state(State.HANDSHAKING)
				connected.emit()
			while _peer.get_available_packet_count() > 0:
				var packet: PackedByteArray = _peer.get_packet()
				if _peer.was_string_packet():
					_handle_text(packet.get_string_from_utf8())
		WebSocketPeer.STATE_CLOSED:
			var code: int = _peer.get_close_code()
			var reason: String = _peer.get_close_reason()
			_close_peer()
			if _state == State.HANDSHAKING or _state == State.CONNECTING:
				_retry_or_fail("连接在握手前被关闭（code=%d）" % code)
			else:
				_set_state(State.CLOSED)
				disconnected.emit(code, reason)
		_:
			_attempt_elapsed += delta
			if _state == State.CONNECTING and _attempt_elapsed > ATTEMPT_TIMEOUT_SEC:
				_close_peer()
				_retry_or_fail("连接超时（%.1f 秒）" % ATTEMPT_TIMEOUT_SEC)
			elif _state == State.HANDSHAKING and _attempt_elapsed > HANDSHAKE_TIMEOUT_SEC:
				_close_peer()
				_retry_or_fail("等待 hello 超时（%.1f 秒）" % HANDSHAKE_TIMEOUT_SEC)


# ---------------------------------------------------------------------------
# 连接与重试
# ---------------------------------------------------------------------------

func _start_attempt() -> void:
	_peer = WebSocketPeer.new()
	# 缓冲上限必须在 connect_to_url 之前设置，否则收不下 view 快照帧。
	_peer.inbound_buffer_size = Msg.FRAME_BUFFER_BYTES
	_peer.outbound_buffer_size = Msg.FRAME_BUFFER_BYTES
	var url: String = "ws://%s:%d" % [_host, _port]
	var error: Error = _peer.connect_to_url(url)
	if error != OK:
		_peer = null
		_retry_or_fail("无法发起连接 %s：%s" % [url, error_string(error)])
		return
	_attempt_elapsed = 0.0
	_set_state(State.CONNECTING)


func _retry_or_fail(message: String) -> void:
	_last_error = message
	_attempt += 1
	if _attempt >= MAX_ATTEMPTS:
		_set_state(State.FAILED)
		connect_failed.emit("已尝试 %d 次仍无法连接 %s:%d（%s）" % [MAX_ATTEMPTS, _host, _port, message])
		return
	_retry_wait = minf(BASE_RETRY_DELAY_SEC * pow(2.0, float(_attempt - 1)), MAX_RETRY_DELAY_SEC)
	retry_scheduled.emit(_attempt + 1, _retry_wait)


func _close_peer() -> void:
	if _peer != null:
		if _peer.get_ready_state() == WebSocketPeer.STATE_OPEN:
			_peer.close(1000, "client closing")
		_peer = null


# ---------------------------------------------------------------------------
# 收包
# ---------------------------------------------------------------------------

func _handle_text(text: String) -> void:
	var parser: JSON = JSON.new()
	if parser.parse(text) != OK:
		_last_error = "收到非法 JSON（第 %d 行）：%s" % [parser.get_error_line(), parser.get_error_message()]
		push_warning("[Client] %s" % _last_error)
		return
	var payload: Variant = parser.data
	if typeof(payload) != TYPE_DICTIONARY:
		_last_error = "收到非 JSON 对象消息"
		push_warning("[Client] %s" % _last_error)
		return

	var message: Dictionary = payload
	if message.has(Msg.KEY_TYPE):
		match str(message[Msg.KEY_TYPE]):
			Msg.TYPE_HELLO:
				_set_state(State.READY)
				handshake_received.emit(message)
			_:
				server_message.emit(message)
		return
	response_received.emit(message)


func _set_state(next: State) -> void:
	if _state == next:
		return
	_state = next
