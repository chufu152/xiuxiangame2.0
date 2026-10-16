class_name Dto
extends RefCounted
## 消息信封的解析与构造辅助（两端共用）。
##
## 唯一权威：docs/REQUIREMENTS_2.0.md §6.1–§6.4。
## 只处理「信封层」：JSON 文本 -> {id,type,params}，以及按协议口径拼响应。
## **不解析未知字段、不做任何玩法判断。**


## 构造 hello 主动消息（§6.1）。连接建立后服务端发送的第一帧。
static func hello(implemented_commands: Array) -> Dictionary:
	return {
		Msg.KEY_TYPE: Msg.TYPE_HELLO,
		Msg.KEY_PROTOCOL_VERSION: Msg.PROTOCOL_VERSION,
		Msg.KEY_BACKEND: Msg.BACKEND,
		Msg.KEY_SAVE_VERSION: Msg.SAVE_VERSION,
		Msg.KEY_IMPLEMENTED_COMMANDS: implemented_commands.duplicate(),
	}


## 构造成功响应（§6.2）。
## view 传 null 表示不下发全量快照（只读 query* 命令）；result 传 null 表示省略该字段。
static func ok_response(request_id: String, events: Array, view: Variant, result: Variant) -> Dictionary:
	var response: Dictionary = {
		Msg.KEY_ID: request_id,
		Msg.KEY_OK: true,
		Msg.KEY_EVENTS: events,
	}
	if view != null:
		response[Msg.KEY_VIEW] = view
	if result != null:
		response[Msg.KEY_RESULT] = result
	return response


## 构造协议失败响应（§6.2 / §6.4）。
## message 仅供调试，客户端不依赖其文案。
static func error_response(request_id: String, error_code: String, message: String) -> Dictionary:
	return {
		Msg.KEY_ID: request_id,
		Msg.KEY_OK: false,
		Msg.KEY_ERROR_CODE: error_code,
		Msg.KEY_MESSAGE: message,
	}


## 解析一条文本帧。
## 返回 { "ok": bool, "errorCode": String, "message": String,
##        "id": String, "type": String, "params": Dictionary }
## 失败时 id 可能为空串（缺 id / JSON 非法时无从回显）。
static func parse_text(text: String) -> Dictionary:
	var parser: JSON = JSON.new()
	var error: Error = parser.parse(text)
	if error != OK:
		return _failure("", Msg.ERR_BAD_JSON,
			"JSON 解析失败（第 %d 行）：%s" % [parser.get_error_line(), parser.get_error_message()])
	return parse_envelope(parser.data)


## 解析已反序列化的信封对象（便于单测直接传 Dictionary）。
static func parse_envelope(raw: Variant) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		return _failure("", Msg.ERR_BAD_REQUEST, "请求必须是 JSON 对象")

	var envelope: Dictionary = raw

	var type_value: Variant = envelope.get(Msg.KEY_TYPE)
	if typeof(type_value) != TYPE_STRING or String(type_value).is_empty():
		return _failure("", Msg.ERR_BAD_REQUEST, "缺少 type 或 type 不是字符串")

	var id_value: Variant = envelope.get(Msg.KEY_ID)
	if typeof(id_value) != TYPE_STRING or String(id_value).is_empty():
		return _failure("", Msg.ERR_NO_ID, "缺少 id 或 id 不是非空字符串")

	var params: Dictionary = {}
	var params_value: Variant = envelope.get(Msg.KEY_PARAMS)
	if params_value != null:
		if typeof(params_value) != TYPE_DICTIONARY:
			return _failure(String(id_value), Msg.ERR_BAD_PARAMS, "params 必须是 JSON 对象")
		params = params_value

	return {
		"ok": true,
		"errorCode": "",
		"message": "",
		"id": String(id_value),
		"type": String(type_value),
		"params": params,
	}


static func _failure(request_id: String, error_code: String, message: String) -> Dictionary:
	return {
		"ok": false,
		"errorCode": error_code,
		"message": message,
		"id": request_id,
		"type": "",
		"params": {},
	}
