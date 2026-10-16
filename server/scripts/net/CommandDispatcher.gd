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
var state: GameState = null
const SAFE_JSON_INTEGER: int = 9007199254740991


func _init(config: Dictionary = {}) -> void:
	_config = config
	_handlers[Commands.PING] = Callable(self, "_handle_ping")
	_handlers[Commands.NEW_GAME] = Callable(self, "_handle_new_game")
	_handlers[Commands.GET_STATE] = Callable(self, "_handle_get_state")


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


func _handle_get_state(request_id: String, _params: Dictionary) -> Dictionary:
	if state == null: return Dto.error_response(request_id, Msg.ERR_NO_GAME, "尚未开局")
	return Dto.ok_response(request_id, [], StateView.build(state, _config), null)


func _handle_new_game(request_id: String, params: Dictionary) -> Dictionary:
	var normalized: Dictionary = _normalize_params(params)
	if not bool(normalized["ok"]): return Dto.error_response(request_id, Msg.ERR_BAD_PARAMS, str(normalized["error"]))
	var values: Dictionary = normalized["params"]
	# 每局独立随机源：旧局的 state.rng 不得被下一局 reset 复用（否则旧局存档会随新局漂移）。
	var rng: RngService = RngService.new()
	var seed_number: int = values["randomSeed"]
	if bool(normalized["random"]): seed_number = rng.random_seed()
	rng.reset(seed_number)
	var next: GameState = MapGenerator.generate(values["mapWidth"], values["mapHeight"], rng, _config)
	next.width = int(values["mapWidth"])
	next.height = int(values["mapHeight"])
	next.seed = seed_number
	next.difficulty = str(values["difficultyId"])
	SetupInitializer.initialize(next, values, _config, rng)
	VisionCalculator.recalculate(next, _config)
	state = next
	return Dto.ok_response(request_id, [], StateView.build(state, _config), {"success": true})


func _normalize_params(params: Dictionary) -> Dictionary:
	if not _config.has("map"): return {"ok": false, "error": "缺少权威配置"}
	var name_value: Variant = params.get("sectName")
	if typeof(name_value) != TYPE_STRING or String(name_value).strip_edges().is_empty(): return {"ok": false, "error": "sectName 必须是非空白字符串"}
	var faction: Variant = params.get("playerFaction", params.get("factionType"))
	if typeof(faction) != TYPE_STRING or not Enums.FactionType.ALL.has(faction): return {"ok": false, "error": "非法 playerFaction"}
	if params.has("playerFaction") and params.has("factionType") and params["playerFaction"] != params["factionType"]: return {"ok": false, "error": "流派 aliases 冲突"}
	var difficulty: Variant = params.get("difficultyId", params.get("difficulty", _config["difficulty"]["defaultLevel"]))
	if typeof(difficulty) != TYPE_STRING or not _config["difficulty"]["levels"].has(difficulty): return {"ok": false, "error": "非法 difficultyId"}
	if params.has("difficultyId") and params.has("difficulty") and params["difficultyId"] != params["difficulty"]: return {"ok": false, "error": "难度 aliases 冲突"}
	var width: Variant = params.get("mapWidth", _config["map"]["defaultWidth"])
	var height: Variant = params.get("mapHeight", _config["map"]["defaultHeight"])
	var setup: Dictionary = _config["map"]["setup"]
	if not _safe_integer(width) or not _safe_integer(height): return {"ok": false, "error": "地图宽高必须是安全整数"}
	if int(width) < 2 or int(height) < 2 or int(width) > int(setup["maxWidth"]) or int(height) > int(setup["maxHeight"]) or int(width) * int(height) > int(setup["maxTiles"]): return {"ok": false, "error": "地图范围必须至少 2x2 且不超过配置安全上限"}
	var seed_value: Variant = params.get("randomSeed", "")
	var seed_number: int = 0
	var random: bool = false
	if typeof(seed_value) == TYPE_STRING:
		var raw: String = String(seed_value).strip_edges()
		if raw.is_empty(): random = true
		else:
			if not raw.is_valid_int(): return {"ok": false, "error": "seed 必须是十进制 64bit 整数"}
			var negative: bool = raw.begins_with("-")
			var digits: String = raw.trim_prefix("-").trim_prefix("+")
			while digits.length() > 1 and digits.begins_with("0"): digits = digits.substr(1)
			var limit: String = "9223372036854775808" if negative else "9223372036854775807"
			if digits.length() > limit.length() or (digits.length() == limit.length() and digits > limit): return {"ok": false, "error": "seed 超出有符号 64bit 范围"}
			seed_number = raw.to_int()
	elif _safe_integer(seed_value): seed_number = int(seed_value)
	else: return {"ok": false, "error": "JSON 数值 seed 超过 2^53-1 请传十进制字符串，避免浮点损精"}
	return {"ok": true, "random": random, "params": {"sectName": String(name_value).strip_edges(), "playerFaction": faction, "difficultyId": difficulty, "mapWidth": int(width), "mapHeight": int(height), "randomSeed": seed_number}}


static func _safe_integer(value: Variant) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT: return false
	var number: float = float(value)
	return is_finite(number) and number == floor(number) and absf(number) <= SAFE_JSON_INTEGER
