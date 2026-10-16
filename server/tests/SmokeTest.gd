extends Node
## R0 无头自测客户端（§7 R0 验收 / §8.3 自检）。
##
## 运行（由 tools/check.ps1 调用）：
##   Godot_v4.4.1-stable_win64_console.exe --headless --path <abs>\server res://tests/SmokeTest.tscn -- --port=9527
##
## 断言：
##   1. 连上后收到 hello，protocolVersion=="2.0"、saveVersion=="3.0"、implementedCommands 含 ping；
##   2. 发 ping，回包 ok==true、id 回显、result.pong==true；
##   3. 发未登记命令，回包 ok==false 且 errorCode=="UNKNOWN_COMMAND"；
##   4. 发缺 id 的帧，回包 errorCode=="NO_ID"。
## 全部通过打印 SMOKE_PASS 并以退出码 0 结束，否则打印 SMOKE_FAIL 并以退出码 1 结束。
##
## 说明：本节点是**独立客户端进程**，通过 WebSocket 连接服务端，不复用客户端工程的
## NetClient，以免「被测对象与被测代码同源」而漏掉传输层问题。

const HOST: String = "127.0.0.1"
const ARG_PORT: String = "--port="
const TIMEOUT_SEC: float = 20.0
## 故意不存在的命令名，用于触发 UNKNOWN_COMMAND。
const UNKNOWN_COMMAND: String = "__no_such_command__"

enum Step { CONNECTING, WAIT_HELLO, WAIT_PING, WAIT_UNKNOWN, WAIT_NO_ID, DONE }

var _port: int = Msg.DEFAULT_PORT
var _peer: WebSocketPeer = null
var _step: Step = Step.CONNECTING
var _elapsed: float = 0.0
var _passes: Array[String] = []
var _failures: Array[String] = []
var _finished: bool = false


func _ready() -> void:
	_port = _read_port()
	print("[Smoke] target ws://%s:%d" % [HOST, _port])
	_peer = WebSocketPeer.new()
	var error: Error = _peer.connect_to_url("ws://%s:%d" % [HOST, _port])
	if error != OK:
		_fail("无法发起连接：%s" % error_string(error))
		_finish()


func _process(delta: float) -> void:
	if _finished:
		return
	_elapsed += delta
	if _elapsed > TIMEOUT_SEC:
		_fail("超时（%.0f 秒）未完成全部断言，停在 %s 阶段" % [TIMEOUT_SEC, _step_name()])
		_finish()
		return

	_peer.poll()
	match _peer.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if _step == Step.CONNECTING:
				_step = Step.WAIT_HELLO
			while _peer.get_available_packet_count() > 0:
				var packet: PackedByteArray = _peer.get_packet()
				if not _peer.was_string_packet():
					continue
				_consume(packet.get_string_from_utf8())
				if _finished:
					return
		WebSocketPeer.STATE_CLOSED:
			_fail("连接在断言完成前被关闭（code=%d）" % _peer.get_close_code())
			_finish()


# ---------------------------------------------------------------------------
# 收包与断言
# ---------------------------------------------------------------------------

func _consume(text: String) -> void:
	var parser: JSON = JSON.new()
	if parser.parse(text) != OK:
		_fail("收到非法 JSON：%s" % text)
		return
	var payload: Variant = parser.data
	if typeof(payload) != TYPE_DICTIONARY:
		_fail("收到非 JSON 对象消息：%s" % text)
		return

	var message: Dictionary = payload
	if str(message.get(Msg.KEY_TYPE, "")) == Msg.TYPE_HELLO:
		_on_hello(message)
	else:
		_on_response(message)


func _on_hello(hello: Dictionary) -> void:
	if _step != Step.WAIT_HELLO:
		_fail("在 %s 阶段收到 hello" % _step_name())
		return

	_expect_equals("hello.protocolVersion", str(hello.get(Msg.KEY_PROTOCOL_VERSION, "")), Msg.PROTOCOL_VERSION)
	_expect_equals("hello.saveVersion", str(hello.get(Msg.KEY_SAVE_VERSION, "")), Msg.SAVE_VERSION)
	_expect_equals("hello.backend", str(hello.get(Msg.KEY_BACKEND, "")), Msg.BACKEND)

	var implemented_value: Variant = hello.get(Msg.KEY_IMPLEMENTED_COMMANDS)
	if typeof(implemented_value) != TYPE_ARRAY:
		_fail("hello.implementedCommands 必须是数组")
	else:
		var implemented: Array = implemented_value
		_check(implemented.has(Commands.PING), "hello.implementedCommands 含 ping")

	_send('{"id":"c1","type":"%s"}' % Commands.PING)
	_step = Step.WAIT_PING


func _on_response(response: Dictionary) -> void:
	match _step:
		Step.WAIT_PING:
			_check(bool(response.get(Msg.KEY_OK, false)), "ping 回包 ok==true")
			_expect_equals("ping 回包 id 回显", str(response.get(Msg.KEY_ID, "")), "c1")
			var result_value: Variant = response.get(Msg.KEY_RESULT)
			if typeof(result_value) != TYPE_DICTIONARY:
				_fail("ping 回包缺少 result 对象")
			else:
				var result: Dictionary = result_value
				_check(bool(result.get("pong", false)), "ping 回包 result.pong==true")
			_send('{"id":"c2","type":"%s"}' % UNKNOWN_COMMAND)
			_step = Step.WAIT_UNKNOWN

		Step.WAIT_UNKNOWN:
			_check(not bool(response.get(Msg.KEY_OK, true)), "未登记命令回包 ok==false")
			_expect_equals("未登记命令 id 回显", str(response.get(Msg.KEY_ID, "")), "c2")
			_expect_equals("未登记命令 errorCode", str(response.get(Msg.KEY_ERROR_CODE, "")), Msg.ERR_UNKNOWN_COMMAND)
			_send('{"type":"%s"}' % Commands.PING)
			_step = Step.WAIT_NO_ID

		Step.WAIT_NO_ID:
			_check(not bool(response.get(Msg.KEY_OK, true)), "缺 id 帧回包 ok==false")
			_expect_equals("缺 id 帧 id 为空", str(response.get(Msg.KEY_ID, "x")), "")
			_expect_equals("缺 id 帧 errorCode", str(response.get(Msg.KEY_ERROR_CODE, "")), Msg.ERR_NO_ID)
			_finish()

		_:
			_fail("在 %s 阶段收到意外响应：%s" % [_step_name(), JSON.stringify(response)])


func _send(text: String) -> void:
	if _peer.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_peer.send_text(text)


func _check(condition: bool, description: String) -> void:
	if condition:
		_passes.append(description)
	else:
		_failures.append(description)


func _expect_equals(label: String, actual: String, expected: String) -> void:
	_check(actual == expected, "%s == \"%s\"（实际 \"%s\"）" % [label, expected, actual])


func _fail(description: String) -> void:
	_failures.append(description)


func _step_name() -> String:
	return str(Step.keys()[_step])


# ---------------------------------------------------------------------------
# 收尾
# ---------------------------------------------------------------------------

func _finish() -> void:
	if _finished:
		return
	_finished = true

	if _peer != null and _peer.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_peer.close(1000, "smoke done")

	print("[Smoke] 通过 %d 项：" % _passes.size())
	for item: String in _passes:
		print("  [PASS] %s" % item)

	if _failures.is_empty():
		print("SMOKE_PASS")
		get_tree().quit(0)
		return

	printerr("[Smoke] 失败 %d 项：" % _failures.size())
	for item: String in _failures:
		printerr("  [FAIL] %s" % item)
	print("SMOKE_FAIL")
	get_tree().quit(1)


func _read_port() -> int:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with(ARG_PORT):
			var raw: String = arg.substr(ARG_PORT.length())
			if raw.is_valid_int():
				return raw.to_int()
	return Msg.DEFAULT_PORT
