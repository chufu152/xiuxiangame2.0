class_name CommandDispatcher
extends RefCounted
## 命令名 -> 处理器 的分发与信封口径把关（§2.4 / §6.2 / §6.4）。
##
## R0 只注册 ping。每完成一个里程碑在此登记新命令，并同步 shared/protocol/commands.gd。
##
## 错误码口径（§6.4）：
##   JSON 非法 -> BAD_JSON；缺 id -> NO_ID；缺/非字符串 type -> BAD_REQUEST；
##   未登记命令 -> UNKNOWN_COMMAND（id 能回显就回显）。
##
## 处理器签名：`func(request_id: String, params: Dictionary) -> Dictionary`，
## 返回**完整响应信封**（用 Dto.ok_response 构造），保证口径统一。
##
## 单会话顺序处理：调用方按收到顺序逐条调用本方法，事件顺序即结算顺序（§6.1）。

var _config: Dictionary = {}
var _handlers: Dictionary = {}


func _init(config: Dictionary = {}) -> void:
	_config = config
	_handlers[Commands.PING] = Callable(self, "_handle_ping")


## 处理一条原始文本帧，返回响应信封。
func dispatch_text(text: String) -> Dictionary:
	var parsed: Dictionary = Dto.parse_text(text)
	if not bool(parsed["ok"]):
		return Dto.error_response(str(parsed["id"]), str(parsed["errorCode"]), str(parsed["message"]))

	var request_id: String = str(parsed["id"])
	var command_name: String = str(parsed["type"])

	if not _handlers.has(command_name):
		return Dto.error_response(request_id, Msg.ERR_UNKNOWN_COMMAND,
			"未登记的命令：%s" % command_name)

	var handler: Callable = _handlers[command_name]
	if not handler.is_valid():
		return Dto.error_response(request_id, Msg.ERR_INTERNAL,
			"命令 %s 已登记但处理器无效（服务端配置错误）" % command_name)

	var params: Dictionary = parsed["params"]
	return handler.call(request_id, params)


## 已登记的命令名（供 hello.implementedCommands 使用）。
func implemented_commands() -> Array:
	return _handlers.keys()


# ---------------------------------------------------------------------------
# 处理器（R0）
# ---------------------------------------------------------------------------

## ping：连通性与握手自检用，不带 view，不改任何游戏状态。
func _handle_ping(request_id: String, _params: Dictionary) -> Dictionary:
	return Dto.ok_response(request_id, [], null, {"pong": true})
