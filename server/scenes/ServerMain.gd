extends Node
## 服务端主场景（R0 工程骨架）。
##
## 职责：解析启动参数 -> 加载并校验 data/gameConfig.json -> 监听 WebSocket -> 每帧驱动网络循环。
## 失败一律以非零退出码结束（CI / tools/check.ps1 依赖此语义）。
##
## 启动（自定义参数放在 `--` 之后，对应 OS.get_cmdline_user_args）：
##   godot --headless --path server -- --port=9527 --data=<abs>/data/gameConfig.json
##
## 本节点不含任何玩法规则；规则在 R1 起的 server/scripts/rules/ 中实现。

const ARG_PORT: String = "--port="
const ARG_DATA: String = "--data="

var _port: int = Msg.DEFAULT_PORT
var _data_path: String = ""
var _config: Dictionary = {}
var _server: NetServer = null
var _dispatcher: CommandDispatcher = null
var _running: bool = false


func _ready() -> void:
	_port = _read_int_arg(ARG_PORT, Msg.DEFAULT_PORT)
	_data_path = _read_arg(ARG_DATA, ConfigLoader.default_path())

	if not _load_config():
		get_tree().quit(1)
		return
	if not _start_network():
		get_tree().quit(1)
		return

	_running = true
	# 该行是自检脚本的就绪信号（ASCII，避免编码差异影响断言）。
	print("server listening on %s:%d" % [Msg.DEFAULT_HOST, _port])


func _process(_delta: float) -> void:
	if _server != null:
		_server.poll()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		_shutdown()


# ---------------------------------------------------------------------------
# 配置
# ---------------------------------------------------------------------------

func _load_config() -> bool:
	var loaded: Dictionary = ConfigLoader.load_from_file(_data_path)
	if not bool(loaded["ok"]):
		printerr("[Server] FATAL config_load_failed: %s" % str(loaded["error"]))
		printerr("[Server] 配置加载失败：%s" % str(loaded["error"]))
		return false

	var config: Dictionary = loaded["config"]
	var errors: Array[String] = ConfigValidator.validate(config)
	if not errors.is_empty():
		printerr("[Server] FATAL config_invalid: %d problem(s)" % errors.size())
		for item: String in errors:
			printerr("[Server]   - %s" % item)
		return false

	_config = config
	print("[Server] config ok: %s" % _data_path)
	return true


# ---------------------------------------------------------------------------
# 网络
# ---------------------------------------------------------------------------

func _start_network() -> bool:
	_dispatcher = CommandDispatcher.new(_config)

	_server = NetServer.new()
	_server.client_connected.connect(_on_client_connected)
	_server.client_disconnected.connect(_on_client_disconnected)
	_server.text_received.connect(_on_text_received)

	var error: Error = _server.listen(_port, Msg.DEFAULT_HOST)
	if error != OK:
		printerr("[Server] FATAL listen_failed: %s:%d -> %s"
			% [Msg.DEFAULT_HOST, _port, error_string(error)])
		return false
	return true


func _shutdown() -> void:
	if not _running:
		return
	_running = false
	if _server != null:
		_server.stop()
		print("[Server] stopped listening")


## 新连接进入 OPEN 后的第一帧：hello 握手（§6.1）。
func _on_client_connected(peer: WebSocketPeer) -> void:
	_server.send_json(peer, Dto.hello([Commands.PING]))


func _on_client_disconnected(_peer: WebSocketPeer, _code: int, _reason: String) -> void:
	pass


## 单会话顺序处理：收到即分发，事件顺序 == 结算顺序（§6.1）。
func _on_text_received(peer: WebSocketPeer, text: String) -> void:
	var response: Dictionary = _dispatcher.dispatch_text(text)
	_server.send_json(peer, response)


# ---------------------------------------------------------------------------
# 命令行参数
# ---------------------------------------------------------------------------

static func _read_arg(prefix: String, fallback: String) -> String:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with(prefix):
			return arg.substr(prefix.length())
	for arg: String in OS.get_cmdline_args():
		if arg.begins_with(prefix):
			return arg.substr(prefix.length())
	return fallback


static func _read_int_arg(prefix: String, fallback: int) -> int:
	var raw: String = _read_arg(prefix, "")
	if raw.is_empty() or not raw.is_valid_int():
		return fallback
	return raw.to_int()
