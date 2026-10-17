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
var _turns: TurnProcessor = null
const SAFE_JSON_INTEGER: int = 9007199254740991


func _init(config: Dictionary = {}) -> void:
	_config = config
	_turns = TurnProcessor.new(config)
	_handlers[Commands.PING] = Callable(self, "_handle_ping")
	_handlers[Commands.NEW_GAME] = Callable(self, "_handle_new_game")
	_handlers[Commands.GET_STATE] = Callable(self, "_handle_get_state")
	_handlers[Commands.FINISH_TURN] = Callable(self, "_handle_finish_turn")
	_handlers[Commands.BEGIN_PLAYER_TURN] = Callable(self, "_handle_begin_player_turn")
	_handlers[Commands.NEXT_TURN] = Callable(self, "_handle_next_turn")
	_handlers[Commands.MOVE_DISCIPLE] = Callable(self, "_handle_move_disciple")
	_handlers[Commands.QUERY_MOVE_RANGE] = Callable(self, "_handle_query_move_range")
	# R3：经济与城市
	_handlers[Commands.FOUND_SPIRIT_PEAK] = Callable(self, "_handle_found_spirit_peak")
	_handlers[Commands.APPOINT_BUILDER] = Callable(self, "_handle_appoint_builder")
	_handlers[Commands.CONSTRUCT_BUILDING] = Callable(self, "_handle_construct_building")
	_handlers[Commands.QUERY_BUILD_OPTIONS] = Callable(self, "_handle_query_build_options")
	_handlers[Commands.OPEN_CAVE] = Callable(self, "_handle_open_cave")
	_handlers[Commands.FORTIFY_PEAK] = Callable(self, "_handle_fortify_peak")
	_handlers[Commands.FOUND_DISTRICT] = Callable(self, "_handle_found_district")
	_handlers[Commands.QUERY_DISTRICT_SITES] = Callable(self, "_handle_query_district_sites")
	_handlers[Commands.ASSIGN_WORKER] = Callable(self, "_handle_assign_worker")
	_handlers[Commands.UNASSIGN_WORKER] = Callable(self, "_handle_unassign_worker")
	_handlers[Commands.QUERY_ASSIGNABLE_TILES] = Callable(self, "_handle_query_assignable_tiles")
	_handlers[Commands.QUERY_CITY_DETAIL] = Callable(self, "_handle_query_city_detail")
	_handlers[Commands.BUILD_IMPROVEMENT] = Callable(self, "_handle_build_improvement")
	_handlers[Commands.REPAIR_IMPROVEMENT] = Callable(self, "_handle_repair_improvement")
	_handlers[Commands.QUERY_IMPROVEMENT_OPTIONS] = Callable(self, "_handle_query_improvement_options")
	# R4：道统科技树 + 修炼/突破/渡劫 + 项目/研究队列 + 收徒
	_handlers[Commands.RESEARCH_DAO] = Callable(self, "_handle_research_dao")
	_handlers[Commands.HOLD_RECRUITMENT] = Callable(self, "_handle_hold_recruitment")
	_handlers[Commands.QUERY_PROJECT_QUEUE] = Callable(self, "_handle_query_project_queue")
	_handlers[Commands.CANCEL_PROJECT] = Callable(self, "_handle_cancel_project")
	_handlers[Commands.ACCELERATE_PROJECT] = Callable(self, "_handle_accelerate_project")
	# R5：战斗/批量移动/撤退 + 传送/驻守 + 转职晋升 + 弟子详情
	_handlers[Commands.BATCH_MOVE] = Callable(self, "_handle_batch_move")
	_handlers[Commands.ATTACK] = Callable(self, "_handle_attack")
	_handlers[Commands.QUERY_ATTACK_PREVIEW] = Callable(self, "_handle_query_attack_preview")
	_handlers[Commands.QUERY_ATTACKABLE] = Callable(self, "_handle_query_attackable")
	_handlers[Commands.RETREAT] = Callable(self, "_handle_retreat")
	_handlers[Commands.TELEPORT] = Callable(self, "_handle_teleport")
	_handlers[Commands.QUERY_TELEPORT_OPTIONS] = Callable(self, "_handle_query_teleport_options")
	_handlers[Commands.ASSIGN_GARRISON] = Callable(self, "_handle_assign_garrison")
	_handlers[Commands.WITHDRAW_GARRISON] = Callable(self, "_handle_withdraw_garrison")
	_handlers[Commands.RECLASS] = Callable(self, "_handle_reclass")
	_handlers[Commands.PROMOTE] = Callable(self, "_handle_promote")
	_handlers[Commands.QUERY_DISCIPLE_DETAIL] = Callable(self, "_handle_query_disciple_detail")
	# R6：探索（机缘/秘境）+ 政令（政体/政令卡）+ 自动化/设置 + 集结/回防
	_handlers[Commands.RALLY] = Callable(self, "_handle_rally")
	_handlers[Commands.RETURN_TO_DEFENSE] = Callable(self, "_handle_return_to_defense")
	_handlers[Commands.QUERY_JI_YUAN_INFO] = Callable(self, "_handle_query_ji_yuan_info")
	_handlers[Commands.SEND_TO_JI_YUAN] = Callable(self, "_handle_send_to_ji_yuan")
	_handlers[Commands.QUERY_MI_JING_INFO] = Callable(self, "_handle_query_mi_jing_info")
	_handlers[Commands.EXPLORE_MI_JING] = Callable(self, "_handle_explore_mi_jing")
	_handlers[Commands.SWITCH_GOVERNMENT] = Callable(self, "_handle_switch_government")
	_handlers[Commands.ENACT_POLICY] = Callable(self, "_handle_enact_policy")
	_handlers[Commands.REVOKE_POLICY] = Callable(self, "_handle_revoke_policy")
	_handlers[Commands.QUERY_POLICY_OPTIONS] = Callable(self, "_handle_query_policy_options")
	_handlers[Commands.SET_AUTOMATION_TOGGLE] = Callable(self, "_handle_set_automation_toggle")
	_handlers[Commands.SET_PEAK_AUTO_PROJECT] = Callable(self, "_handle_set_peak_auto_project")
	_handlers[Commands.SET_ALL_AUTO_PROJECT] = Callable(self, "_handle_set_all_auto_project")
	_handlers[Commands.EXPLORE_NOW] = Callable(self, "_handle_explore_now")
	_handlers[Commands.QUERY_AUTOMATION_STATE] = Callable(self, "_handle_query_automation_state")
	_handlers[Commands.SET_SETTING] = Callable(self, "_handle_set_setting")


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


# ---------------------------------------------------------------------------
# 处理器（R2：回合状态机 + 移动）
# ---------------------------------------------------------------------------

func _handle_finish_turn(request_id: String, _params: Dictionary) -> Dictionary:
	if state == null: return Dto.error_response(request_id, Msg.ERR_NO_GAME, "尚未开局")
	var events: Array[String] = _turns.finish_turn(state)
	return Dto.ok_response(request_id, events, StateView.build(state, _config), null)


func _handle_begin_player_turn(request_id: String, _params: Dictionary) -> Dictionary:
	if state == null: return Dto.error_response(request_id, Msg.ERR_NO_GAME, "尚未开局")
	var events: Array[String] = _turns.begin_player_turn(state)
	return Dto.ok_response(request_id, events, StateView.build(state, _config), null)


func _handle_next_turn(request_id: String, _params: Dictionary) -> Dictionary:
	if state == null: return Dto.error_response(request_id, Msg.ERR_NO_GAME, "尚未开局")
	var events: Array[String] = _turns.next_turn(state)
	return Dto.ok_response(request_id, events, StateView.build(state, _config), null)


## 只读：不回 view，只回 result（PROTOCOL §3）。
func _handle_query_move_range(request_id: String, params: Dictionary) -> Dictionary:
	if state == null: return Dto.error_response(request_id, Msg.ERR_NO_GAME, "尚未开局")
	var disciple_id: Variant = params.get("discipleId")
	if typeof(disciple_id) != TYPE_STRING or String(disciple_id).is_empty(): return Dto.error_response(request_id, Msg.ERR_BAD_PARAMS, "discipleId 必须是非空字符串")
	var disciple: Disciple = MoveAction.find_disciple(state, String(disciple_id))
	if disciple == null: return Dto.error_response(request_id, Msg.ERR_BAD_PARAMS, "弟子不存在：" + String(disciple_id))
	if disciple.sectId != state.playerSectId: return Dto.error_response(request_id, Msg.ERR_BAD_PARAMS, "只能查询己方弟子的移动范围")
	var result: Dictionary = MoveAction.query_move_range(state, _config, String(disciple_id))
	return Dto.ok_response(request_id, [], null, result)


## 权威移动：回 view + result。
func _handle_move_disciple(request_id: String, params: Dictionary) -> Dictionary:
	if state == null: return Dto.error_response(request_id, Msg.ERR_NO_GAME, "尚未开局")
	var disciple_id: Variant = params.get("discipleId")
	if typeof(disciple_id) != TYPE_STRING or String(disciple_id).is_empty(): return Dto.error_response(request_id, Msg.ERR_BAD_PARAMS, "discipleId 必须是非空字符串")
	var target_tile_id: Variant = params.get("targetTileId")
	if typeof(target_tile_id) != TYPE_STRING or String(target_tile_id).is_empty(): return Dto.error_response(request_id, Msg.ERR_BAD_PARAMS, "targetTileId 必须是非空字符串")
	var disciple: Disciple = MoveAction.find_disciple(state, String(disciple_id))
	if disciple == null: return Dto.error_response(request_id, Msg.ERR_BAD_PARAMS, "弟子不存在：" + String(disciple_id))
	if disciple.sectId != state.playerSectId: return Dto.error_response(request_id, Msg.ERR_BAD_PARAMS, "只能移动己方弟子")
	if not state.tiles.has(String(target_tile_id)): return Dto.error_response(request_id, Msg.ERR_BAD_PARAMS, "目标地块不存在：" + String(target_tile_id))
	if state.phase != Enums.TurnPhase.PLAYER_ACTION: return Dto.error_response(request_id, Msg.ERR_BAD_REQUEST, "当前阶段不可移动：" + state.phase)
	var before: int = state.eventLog.size()
	var result: Dictionary = MoveAction.move_disciple(state, _config, String(disciple_id), String(target_tile_id))
	var events: Array = state.eventLog.slice(before)
	return Dto.ok_response(request_id, events, StateView.build(state, _config), result)


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


# ---------------------------------------------------------------------------
# 处理器（R3：经济结算 + 灵峰/城市 + 建筑/区域/劳力/改良/道路）
# ---------------------------------------------------------------------------
# 只读命令（query*）→ Dto.ok_response(id, [], null, result)（view=null）；
# 写命令 → Dto.ok_response(id, events, StateView.build(...), result)，events = 本命令期间新增日志。
# 未开局 → NO_GAME；参数缺失/类型错/枚举非法 → BAD_PARAMS；业务不允许 → ok:true + result.success:false。

func _handle_found_spirit_peak(request_id: String, params: Dictionary) -> Dictionary:
	if state == null: return Dto.error_response(request_id, Msg.ERR_NO_GAME, "尚未开局")
	var disciple_check: Dictionary = _require_own_disciple(request_id, params)
	if not bool(disciple_check["ok"]): return disciple_check["response"]
	var tile_check: Dictionary = _require_nonempty(params, "tileId")
	if not bool(tile_check["ok"]): return Dto.error_response(request_id, Msg.ERR_BAD_PARAMS, str(tile_check["message"]))
	var before: int = state.eventLog.size()
	var result: Dictionary = CityAction.found_spirit_peak(state, _config, str(disciple_check["value"]), str(tile_check["value"]))
	return Dto.ok_response(request_id, state.eventLog.slice(before), StateView.build(state, _config), result)


func _handle_appoint_builder(request_id: String, params: Dictionary) -> Dictionary:
	if state == null: return Dto.error_response(request_id, Msg.ERR_NO_GAME, "尚未开局")
	var sect_check: Dictionary = _require_player_sect(request_id, params)
	if not bool(sect_check["ok"]): return sect_check["response"]
	var disciple_check: Dictionary = _require_own_disciple(request_id, params)
	if not bool(disciple_check["ok"]): return disciple_check["response"]
	var before: int = state.eventLog.size()
	var result: Dictionary = ImprovementAction.appoint_builder(state, _config, str(sect_check["value"]), str(disciple_check["value"]))
	return Dto.ok_response(request_id, state.eventLog.slice(before), StateView.build(state, _config), result)


func _handle_construct_building(request_id: String, params: Dictionary) -> Dictionary:
	if state == null: return Dto.error_response(request_id, Msg.ERR_NO_GAME, "尚未开局")
	var peak_check: Dictionary = _require_player_peak(request_id, params)
	if not bool(peak_check["ok"]): return peak_check["response"]
	var type_check: Dictionary = _require_enum(params, "buildingType", Enums.Building.ALL)
	if not bool(type_check["ok"]): return Dto.error_response(request_id, Msg.ERR_BAD_PARAMS, str(type_check["message"]))
	var before: int = state.eventLog.size()
	var result: Dictionary = CityAction.construct_building(state, _config, str(peak_check["value"]), str(type_check["value"]))
	return Dto.ok_response(request_id, state.eventLog.slice(before), StateView.build(state, _config), result)


func _handle_query_build_options(request_id: String, params: Dictionary) -> Dictionary:
	if state == null: return Dto.error_response(request_id, Msg.ERR_NO_GAME, "尚未开局")
	var sect_check: Dictionary = _require_player_sect(request_id, params)
	if not bool(sect_check["ok"]): return sect_check["response"]
	return Dto.ok_response(request_id, [], null, CityAction.query_build_options(state, _config, str(sect_check["value"])))


func _handle_open_cave(request_id: String, params: Dictionary) -> Dictionary:
	if state == null: return Dto.error_response(request_id, Msg.ERR_NO_GAME, "尚未开局")
	var peak_check: Dictionary = _require_player_peak(request_id, params)
	if not bool(peak_check["ok"]): return peak_check["response"]
	var disciple_check: Dictionary = _require_own_disciple(request_id, params)
	if not bool(disciple_check["ok"]): return disciple_check["response"]
	var before: int = state.eventLog.size()
	var result: Dictionary = CityAction.open_cave(state, _config, str(peak_check["value"]), str(disciple_check["value"]))
	return Dto.ok_response(request_id, state.eventLog.slice(before), StateView.build(state, _config), result)


func _handle_fortify_peak(request_id: String, params: Dictionary) -> Dictionary:
	if state == null: return Dto.error_response(request_id, Msg.ERR_NO_GAME, "尚未开局")
	var peak_check: Dictionary = _require_player_peak(request_id, params)
	if not bool(peak_check["ok"]): return peak_check["response"]
	var before: int = state.eventLog.size()
	var result: Dictionary = CityAction.fortify_peak(state, _config, str(peak_check["value"]))
	return Dto.ok_response(request_id, state.eventLog.slice(before), StateView.build(state, _config), result)


func _handle_found_district(request_id: String, params: Dictionary) -> Dictionary:
	if state == null: return Dto.error_response(request_id, Msg.ERR_NO_GAME, "尚未开局")
	var sect_check: Dictionary = _require_player_sect(request_id, params)
	if not bool(sect_check["ok"]): return sect_check["response"]
	var peak_check: Dictionary = _require_player_peak(request_id, params)
	if not bool(peak_check["ok"]): return peak_check["response"]
	var type_check: Dictionary = _require_enum(params, "districtTypeId", Enums.DistrictType.ALL)
	if not bool(type_check["ok"]): return Dto.error_response(request_id, Msg.ERR_BAD_PARAMS, str(type_check["message"]))
	var tile_check: Dictionary = _require_nonempty(params, "tileId")
	if not bool(tile_check["ok"]): return Dto.error_response(request_id, Msg.ERR_BAD_PARAMS, str(tile_check["message"]))
	var before: int = state.eventLog.size()
	var result: Dictionary = CityAction.found_district(state, _config, str(sect_check["value"]), str(peak_check["value"]), str(type_check["value"]), str(tile_check["value"]))
	return Dto.ok_response(request_id, state.eventLog.slice(before), StateView.build(state, _config), result)


func _handle_query_district_sites(request_id: String, params: Dictionary) -> Dictionary:
	if state == null: return Dto.error_response(request_id, Msg.ERR_NO_GAME, "尚未开局")
	var sect_check: Dictionary = _require_player_sect(request_id, params)
	if not bool(sect_check["ok"]): return sect_check["response"]
	var peak_check: Dictionary = _require_player_peak(request_id, params)
	if not bool(peak_check["ok"]): return peak_check["response"]
	var type_check: Dictionary = _require_enum(params, "districtTypeId", Enums.DistrictType.ALL)
	if not bool(type_check["ok"]): return Dto.error_response(request_id, Msg.ERR_BAD_PARAMS, str(type_check["message"]))
	return Dto.ok_response(request_id, [], null, CityAction.query_district_sites(state, _config, str(sect_check["value"]), str(peak_check["value"]), str(type_check["value"])))


func _handle_assign_worker(request_id: String, params: Dictionary) -> Dictionary:
	if state == null: return Dto.error_response(request_id, Msg.ERR_NO_GAME, "尚未开局")
	var peak_check: Dictionary = _require_player_peak(request_id, params)
	if not bool(peak_check["ok"]): return peak_check["response"]
	var tile_check: Dictionary = _require_nonempty(params, "tileId")
	if not bool(tile_check["ok"]): return Dto.error_response(request_id, Msg.ERR_BAD_PARAMS, str(tile_check["message"]))
	var before: int = state.eventLog.size()
	var result: Dictionary = CityAction.assign_worker(state, _config, str(peak_check["value"]), str(tile_check["value"]))
	return Dto.ok_response(request_id, state.eventLog.slice(before), StateView.build(state, _config), result)


func _handle_unassign_worker(request_id: String, params: Dictionary) -> Dictionary:
	if state == null: return Dto.error_response(request_id, Msg.ERR_NO_GAME, "尚未开局")
	var peak_check: Dictionary = _require_player_peak(request_id, params)
	if not bool(peak_check["ok"]): return peak_check["response"]
	var tile_check: Dictionary = _require_nonempty(params, "tileId")
	if not bool(tile_check["ok"]): return Dto.error_response(request_id, Msg.ERR_BAD_PARAMS, str(tile_check["message"]))
	var before: int = state.eventLog.size()
	var result: Dictionary = CityAction.unassign_worker(state, _config, str(peak_check["value"]), str(tile_check["value"]))
	return Dto.ok_response(request_id, state.eventLog.slice(before), StateView.build(state, _config), result)


func _handle_query_assignable_tiles(request_id: String, params: Dictionary) -> Dictionary:
	if state == null: return Dto.error_response(request_id, Msg.ERR_NO_GAME, "尚未开局")
	var peak_check: Dictionary = _require_player_peak(request_id, params)
	if not bool(peak_check["ok"]): return peak_check["response"]
	return Dto.ok_response(request_id, [], null, CityAction.query_assignable_tiles(state, _config, str(peak_check["value"])))


func _handle_query_city_detail(request_id: String, params: Dictionary) -> Dictionary:
	if state == null: return Dto.error_response(request_id, Msg.ERR_NO_GAME, "尚未开局")
	var peak_check: Dictionary = _require_player_peak(request_id, params)
	if not bool(peak_check["ok"]): return peak_check["response"]
	return Dto.ok_response(request_id, [], null, CityAction.query_city_detail(state, _config, str(peak_check["value"])))


func _handle_build_improvement(request_id: String, params: Dictionary) -> Dictionary:
	if state == null: return Dto.error_response(request_id, Msg.ERR_NO_GAME, "尚未开局")
	var sect_check: Dictionary = _require_player_sect(request_id, params)
	if not bool(sect_check["ok"]): return sect_check["response"]
	var disciple_check: Dictionary = _require_own_disciple(request_id, params)
	if not bool(disciple_check["ok"]): return disciple_check["response"]
	var tile_check: Dictionary = _require_nonempty(params, "tileId")
	if not bool(tile_check["ok"]): return Dto.error_response(request_id, Msg.ERR_BAD_PARAMS, str(tile_check["message"]))
	var type_check: Dictionary = _require_enum(params, "improvementType", Enums.ImprovementType.ALL)
	if not bool(type_check["ok"]): return Dto.error_response(request_id, Msg.ERR_BAD_PARAMS, str(type_check["message"]))
	var before: int = state.eventLog.size()
	var result: Dictionary = ImprovementAction.build_improvement(state, _config, str(sect_check["value"]), str(disciple_check["value"]), str(tile_check["value"]), str(type_check["value"]))
	return Dto.ok_response(request_id, state.eventLog.slice(before), StateView.build(state, _config), result)


func _handle_repair_improvement(request_id: String, params: Dictionary) -> Dictionary:
	if state == null: return Dto.error_response(request_id, Msg.ERR_NO_GAME, "尚未开局")
	var sect_check: Dictionary = _require_player_sect(request_id, params)
	if not bool(sect_check["ok"]): return sect_check["response"]
	var disciple_check: Dictionary = _require_own_disciple(request_id, params)
	if not bool(disciple_check["ok"]): return disciple_check["response"]
	var tile_check: Dictionary = _require_nonempty(params, "tileId")
	if not bool(tile_check["ok"]): return Dto.error_response(request_id, Msg.ERR_BAD_PARAMS, str(tile_check["message"]))
	var before: int = state.eventLog.size()
	var result: Dictionary = ImprovementAction.repair_improvement(state, _config, str(sect_check["value"]), str(disciple_check["value"]), str(tile_check["value"]))
	return Dto.ok_response(request_id, state.eventLog.slice(before), StateView.build(state, _config), result)


func _handle_query_improvement_options(request_id: String, params: Dictionary) -> Dictionary:
	if state == null: return Dto.error_response(request_id, Msg.ERR_NO_GAME, "尚未开局")
	var sect_check: Dictionary = _require_player_sect(request_id, params)
	if not bool(sect_check["ok"]): return sect_check["response"]
	var tile_check: Dictionary = _require_nonempty(params, "tileId")
	if not bool(tile_check["ok"]): return Dto.error_response(request_id, Msg.ERR_BAD_PARAMS, str(tile_check["message"]))
	return Dto.ok_response(request_id, [], null, ImprovementAction.query_improvement_options(state, _config, str(sect_check["value"]), str(tile_check["value"])))


# ---------------------------------------------------------------------------
# 处理器（R4：道统科技树 + 修炼/突破/渡劫 + 项目/研究队列 + 收徒）
# ---------------------------------------------------------------------------
# 只读 `queryProjectQueue` → view=null；写命令 → events = 本命令期间新增日志 + 实时 view。

func _handle_research_dao(request_id: String, params: Dictionary) -> Dictionary:
	if state == null: return Dto.error_response(request_id, Msg.ERR_NO_GAME, "尚未开局")
	var sect_check: Dictionary = _require_player_sect(request_id, params)
	if not bool(sect_check["ok"]): return sect_check["response"]
	var dao_check: Dictionary = _require_nonempty(params, "daoId")
	if not bool(dao_check["ok"]): return Dto.error_response(request_id, Msg.ERR_BAD_PARAMS, str(dao_check["message"]))
	var before: int = state.eventLog.size()
	var result: Dictionary = DaoAction.research_dao(state, _config, str(sect_check["value"]), str(dao_check["value"]))
	return Dto.ok_response(request_id, state.eventLog.slice(before), StateView.build(state, _config), result)


func _handle_hold_recruitment(request_id: String, params: Dictionary) -> Dictionary:
	if state == null: return Dto.error_response(request_id, Msg.ERR_NO_GAME, "尚未开局")
	var peak_check: Dictionary = _require_player_peak(request_id, params)
	if not bool(peak_check["ok"]): return peak_check["response"]
	var before: int = state.eventLog.size()
	var result: Dictionary = DaoAction.hold_recruitment(state, _config, str(peak_check["value"]))
	return Dto.ok_response(request_id, state.eventLog.slice(before), StateView.build(state, _config), result)


func _handle_query_project_queue(request_id: String, params: Dictionary) -> Dictionary:
	if state == null: return Dto.error_response(request_id, Msg.ERR_NO_GAME, "尚未开局")
	var peak_check: Dictionary = _require_player_peak(request_id, params)
	if not bool(peak_check["ok"]): return peak_check["response"]
	return Dto.ok_response(request_id, [], null, DaoAction.query_project_queue(state, _config, str(peak_check["value"])))


func _handle_cancel_project(request_id: String, params: Dictionary) -> Dictionary:
	if state == null: return Dto.error_response(request_id, Msg.ERR_NO_GAME, "尚未开局")
	var peak_check: Dictionary = _require_player_peak(request_id, params)
	if not bool(peak_check["ok"]): return peak_check["response"]
	var project_check: Dictionary = _require_nonempty(params, "projectId")
	if not bool(project_check["ok"]): return Dto.error_response(request_id, Msg.ERR_BAD_PARAMS, str(project_check["message"]))
	var before: int = state.eventLog.size()
	var result: Dictionary = DaoAction.cancel_project(state, _config, str(peak_check["value"]), str(project_check["value"]))
	return Dto.ok_response(request_id, state.eventLog.slice(before), StateView.build(state, _config), result)


## `accelerateProject`：`[peakId,] projectId, turns, [research=false]`（PROTOCOL §11.1 #4 参数顺序）。
## `research=true` 时 `peakId` 可省——研究队列属宗门级，用己方主峰定位宗门即可。
func _handle_accelerate_project(request_id: String, params: Dictionary) -> Dictionary:
	if state == null: return Dto.error_response(request_id, Msg.ERR_NO_GAME, "尚未开局")
	var research: bool = bool(params.get("research", false))
	var peak_id: String = ""
	if params.has("peakId"):
		var peak_check: Dictionary = _require_player_peak(request_id, params)
		if not bool(peak_check["ok"]): return peak_check["response"]
		peak_id = str(peak_check["value"])
	else:
		if not research:
			return Dto.error_response(request_id, Msg.ERR_BAD_PARAMS, "peakId 必填（仅 research=true 时可省略）")
		peak_id = _player_capital_peak_id()
		if peak_id.is_empty():
			return Dto.error_response(request_id, Msg.ERR_BAD_PARAMS, "己方无灵峰，无法定位宗门研究队列")
	var project_check: Dictionary = _require_nonempty(params, "projectId")
	if not bool(project_check["ok"]): return Dto.error_response(request_id, Msg.ERR_BAD_PARAMS, str(project_check["message"]))
	var turns_check: Dictionary = _require_int(params, "turns")
	if not bool(turns_check["ok"]): return Dto.error_response(request_id, Msg.ERR_BAD_PARAMS, str(turns_check["message"]))
	if int(turns_check["value"]) <= 0: return Dto.error_response(request_id, Msg.ERR_BAD_PARAMS, "turns 必须大于 0")
	var before: int = state.eventLog.size()
	var result: Dictionary = DaoAction.accelerate_project(state, _config, peak_id, str(project_check["value"]), int(turns_check["value"]), research)
	return Dto.ok_response(request_id, state.eventLog.slice(before), StateView.build(state, _config), result)


func _player_capital_peak_id() -> String:
	for sect: Sect in state.sects:
		if sect.id != state.playerSectId:
			continue
		for peak: SpiritPeak in sect.spiritPeaks:
			if peak.capital:
				return peak.id
		if not sect.spiritPeaks.is_empty():
			return sect.spiritPeaks[0].id
	return ""


# ---------------------------------------------------------------------------
# 参数校验辅助
# ---------------------------------------------------------------------------

## 校验整数参数（JSON 数字，允许 `TYPE_INT`/`TYPE_FLOAT` 但必须是整值且在安全范围内）。
func _require_int(params: Dictionary, key: String) -> Dictionary:
	var value: Variant = params.get(key)
	if not _safe_integer(value):
		return {"ok": false, "message": "%s 必须是整数" % key}
	return {"ok": true, "value": int(value)}

func _require_nonempty(params: Dictionary, key: String) -> Dictionary:
	var value: Variant = params.get(key)
	if typeof(value) != TYPE_STRING or String(value).is_empty():
		return {"ok": false, "message": "%s 必须是非空字符串" % key}
	return {"ok": true, "value": String(value)}


func _require_enum(params: Dictionary, key: String, allowed: Array) -> Dictionary:
	var check: Dictionary = _require_nonempty(params, key)
	if not bool(check["ok"]): return check
	if not allowed.has(check["value"]):
		return {"ok": false, "message": "%s 非法枚举值：%s" % [key, str(check["value"])]}
	return check


## 校验 `sectId` 存在且为己方宗门；返回 {ok, value, response}。
func _require_player_sect(request_id: String, params: Dictionary) -> Dictionary:
	var check: Dictionary = _require_nonempty(params, "sectId")
	if not bool(check["ok"]): return {"ok": false, "response": Dto.error_response(request_id, Msg.ERR_BAD_PARAMS, str(check["message"]))}
	if str(check["value"]) != state.playerSectId:
		return {"ok": false, "response": Dto.error_response(request_id, Msg.ERR_BAD_PARAMS, "只能操作己方宗门")}
	return {"ok": true, "value": str(check["value"])}


## 校验 `peakId` 存在且属己方宗门；返回 {ok, value, response}。
func _require_player_peak(request_id: String, params: Dictionary) -> Dictionary:
	var check: Dictionary = _require_nonempty(params, "peakId")
	if not bool(check["ok"]): return {"ok": false, "response": Dto.error_response(request_id, Msg.ERR_BAD_PARAMS, str(check["message"]))}
	var peak: SpiritPeak = CityAction.find_peak(state, str(check["value"]))
	if peak == null:
		return {"ok": false, "response": Dto.error_response(request_id, Msg.ERR_BAD_PARAMS, "灵峰不存在：" + str(check["value"]))}
	if peak.sectId != state.playerSectId:
		return {"ok": false, "response": Dto.error_response(request_id, Msg.ERR_BAD_PARAMS, "只能操作己方灵峰")}
	return {"ok": true, "value": peak.id}


## 校验 `discipleId` 存在且属己方宗门；返回 {ok, value, response}。
func _require_own_disciple(request_id: String, params: Dictionary) -> Dictionary:
	var check: Dictionary = _require_nonempty(params, "discipleId")
	if not bool(check["ok"]): return {"ok": false, "response": Dto.error_response(request_id, Msg.ERR_BAD_PARAMS, str(check["message"]))}
	var disciple: Disciple = MoveAction.find_disciple(state, str(check["value"]))
	if disciple == null:
		return {"ok": false, "response": Dto.error_response(request_id, Msg.ERR_BAD_PARAMS, "弟子不存在：" + str(check["value"]))}
	if disciple.sectId != state.playerSectId:
		return {"ok": false, "response": Dto.error_response(request_id, Msg.ERR_BAD_PARAMS, "只能操作己方弟子")}
	return {"ok": true, "value": disciple.id}


# ---------------------------------------------------------------------------
# 处理器（R5：战斗/批量移动/撤退 + 传送/驻守 + 转职晋升 + 弟子详情）
# ---------------------------------------------------------------------------
# 只读命令（`queryAttackPreview`/`queryAttackable`/`queryTeleportOptions`/`queryDiscipleDetail`）
# → `Dto.ok_response(id, [], null, result)`（view=null）；
# 写命令 → `Dto.ok_response(id, events, StateView.build(...), result)`，events = 本命令期间新增日志。
# 业务失败（不在射程/已出手/灵石不足/晋升点不足…）一律 `ok:true + result.success:false + message`；
# 只有参数缺失/类型错/枚举非法才 `BAD_PARAMS`。

func _handle_batch_move(request_id: String, params: Dictionary) -> Dictionary:
	if state == null: return Dto.error_response(request_id, Msg.ERR_NO_GAME, "尚未开局")
	var sect_check: Dictionary = _require_player_sect(request_id, params)
	if not bool(sect_check["ok"]): return sect_check["response"]
	var list_check: Dictionary = _require_string_array(params, "discipleIds")
	if not bool(list_check["ok"]): return Dto.error_response(request_id, Msg.ERR_BAD_PARAMS, str(list_check["message"]))
	var tile_check: Dictionary = _require_nonempty(params, "targetTileId")
	if not bool(tile_check["ok"]): return Dto.error_response(request_id, Msg.ERR_BAD_PARAMS, str(tile_check["message"]))
	if not state.tiles.has(str(tile_check["value"])): return Dto.error_response(request_id, Msg.ERR_BAD_PARAMS, "目标地块不存在：" + str(tile_check["value"]))
	if state.phase != Enums.TurnPhase.PLAYER_ACTION: return Dto.error_response(request_id, Msg.ERR_BAD_REQUEST, "当前阶段不可移动：" + state.phase)
	var before: int = state.eventLog.size()
	var result: Dictionary = CombatAction.batch_move(state, _config, str(sect_check["value"]), list_check["value"], str(tile_check["value"]))
	return Dto.ok_response(request_id, state.eventLog.slice(before), StateView.build(state, _config), result)


func _handle_attack(request_id: String, params: Dictionary) -> Dictionary:
	if state == null: return Dto.error_response(request_id, Msg.ERR_NO_GAME, "尚未开局")
	var disciple_check: Dictionary = _require_own_disciple(request_id, params)
	if not bool(disciple_check["ok"]): return disciple_check["response"]
	var tile_check: Dictionary = _require_nonempty(params, "targetTileId")
	if not bool(tile_check["ok"]): return Dto.error_response(request_id, Msg.ERR_BAD_PARAMS, str(tile_check["message"]))
	if not state.tiles.has(str(tile_check["value"])): return Dto.error_response(request_id, Msg.ERR_BAD_PARAMS, "目标地块不存在：" + str(tile_check["value"]))
	var before: int = state.eventLog.size()
	var result: Dictionary = CombatAction.attack(state, _config, str(disciple_check["value"]), str(tile_check["value"]))
	return Dto.ok_response(request_id, state.eventLog.slice(before), StateView.build(state, _config), result)


func _handle_query_attack_preview(request_id: String, params: Dictionary) -> Dictionary:
	if state == null: return Dto.error_response(request_id, Msg.ERR_NO_GAME, "尚未开局")
	var disciple_check: Dictionary = _require_own_disciple(request_id, params)
	if not bool(disciple_check["ok"]): return disciple_check["response"]
	var tile_check: Dictionary = _require_nonempty(params, "targetTileId")
	if not bool(tile_check["ok"]): return Dto.error_response(request_id, Msg.ERR_BAD_PARAMS, str(tile_check["message"]))
	if not state.tiles.has(str(tile_check["value"])): return Dto.error_response(request_id, Msg.ERR_BAD_PARAMS, "目标地块不存在：" + str(tile_check["value"]))
	return Dto.ok_response(request_id, [], null, CombatAction.query_attack_preview(state, _config, str(disciple_check["value"]), str(tile_check["value"])))


func _handle_query_attackable(request_id: String, params: Dictionary) -> Dictionary:
	if state == null: return Dto.error_response(request_id, Msg.ERR_NO_GAME, "尚未开局")
	var disciple_check: Dictionary = _require_own_disciple(request_id, params)
	if not bool(disciple_check["ok"]): return disciple_check["response"]
	return Dto.ok_response(request_id, [], null, CombatAction.query_attackable(state, _config, str(disciple_check["value"])))


func _handle_retreat(request_id: String, params: Dictionary) -> Dictionary:
	if state == null: return Dto.error_response(request_id, Msg.ERR_NO_GAME, "尚未开局")
	var disciple_check: Dictionary = _require_own_disciple(request_id, params)
	if not bool(disciple_check["ok"]): return disciple_check["response"]
	var tile_check: Dictionary = _require_nonempty(params, "toTileId")
	if not bool(tile_check["ok"]): return Dto.error_response(request_id, Msg.ERR_BAD_PARAMS, str(tile_check["message"]))
	if not state.tiles.has(str(tile_check["value"])): return Dto.error_response(request_id, Msg.ERR_BAD_PARAMS, "目标地块不存在：" + str(tile_check["value"]))
	var before: int = state.eventLog.size()
	var result: Dictionary = CombatAction.retreat(state, _config, str(disciple_check["value"]), str(tile_check["value"]))
	return Dto.ok_response(request_id, state.eventLog.slice(before), StateView.build(state, _config), result)


func _handle_teleport(request_id: String, params: Dictionary) -> Dictionary:
	if state == null: return Dto.error_response(request_id, Msg.ERR_NO_GAME, "尚未开局")
	var disciple_check: Dictionary = _require_own_disciple(request_id, params)
	if not bool(disciple_check["ok"]): return disciple_check["response"]
	# 裁决五：`teleport` 用 `targetPeakId`，不得使用 `peakId`。
	var peak_check: Dictionary = _require_nonempty(params, "targetPeakId")
	if not bool(peak_check["ok"]): return Dto.error_response(request_id, Msg.ERR_BAD_PARAMS, str(peak_check["message"]))
	var before: int = state.eventLog.size()
	var result: Dictionary = UnitAction.teleport(state, _config, str(disciple_check["value"]), str(peak_check["value"]))
	return Dto.ok_response(request_id, state.eventLog.slice(before), StateView.build(state, _config), result)


func _handle_query_teleport_options(request_id: String, params: Dictionary) -> Dictionary:
	if state == null: return Dto.error_response(request_id, Msg.ERR_NO_GAME, "尚未开局")
	var disciple_check: Dictionary = _require_own_disciple(request_id, params)
	if not bool(disciple_check["ok"]): return disciple_check["response"]
	return Dto.ok_response(request_id, [], null, UnitAction.query_teleport_options(state, _config, str(disciple_check["value"])))


func _handle_assign_garrison(request_id: String, params: Dictionary) -> Dictionary:
	if state == null: return Dto.error_response(request_id, Msg.ERR_NO_GAME, "尚未开局")
	var disciple_check: Dictionary = _require_own_disciple(request_id, params)
	if not bool(disciple_check["ok"]): return disciple_check["response"]
	var node_check: Dictionary = _require_nonempty(params, "nodeId")
	if not bool(node_check["ok"]): return Dto.error_response(request_id, Msg.ERR_BAD_PARAMS, str(node_check["message"]))
	if not state.nodes.has(str(node_check["value"])): return Dto.error_response(request_id, Msg.ERR_BAD_PARAMS, "节点不存在：" + str(node_check["value"]))
	var before: int = state.eventLog.size()
	var result: Dictionary = UnitAction.assign_garrison(state, _config, str(disciple_check["value"]), str(node_check["value"]))
	return Dto.ok_response(request_id, state.eventLog.slice(before), StateView.build(state, _config), result)


func _handle_withdraw_garrison(request_id: String, params: Dictionary) -> Dictionary:
	if state == null: return Dto.error_response(request_id, Msg.ERR_NO_GAME, "尚未开局")
	var disciple_check: Dictionary = _require_own_disciple(request_id, params)
	if not bool(disciple_check["ok"]): return disciple_check["response"]
	var before: int = state.eventLog.size()
	var result: Dictionary = UnitAction.withdraw_garrison(state, _config, str(disciple_check["value"]))
	return Dto.ok_response(request_id, state.eventLog.slice(before), StateView.build(state, _config), result)


## 转职：`unitClass` **严格比对 `Enums.UnitClass.ALL`**，非法值回 `BAD_PARAMS`，
## 不得借道枚举 `from` 静默回退（PROTOCOL §3 `reclass` 明列）。
func _handle_reclass(request_id: String, params: Dictionary) -> Dictionary:
	if state == null: return Dto.error_response(request_id, Msg.ERR_NO_GAME, "尚未开局")
	var disciple_check: Dictionary = _require_own_disciple(request_id, params)
	if not bool(disciple_check["ok"]): return disciple_check["response"]
	var class_check: Dictionary = _require_enum(params, "unitClass", Enums.UnitClass.ALL)
	if not bool(class_check["ok"]): return Dto.error_response(request_id, Msg.ERR_BAD_PARAMS, str(class_check["message"]))
	var before: int = state.eventLog.size()
	var result: Dictionary = UnitAction.reclass(state, _config, str(disciple_check["value"]), str(class_check["value"]))
	return Dto.ok_response(request_id, state.eventLog.slice(before), StateView.build(state, _config), result)


func _handle_promote(request_id: String, params: Dictionary) -> Dictionary:
	if state == null: return Dto.error_response(request_id, Msg.ERR_NO_GAME, "尚未开局")
	var disciple_check: Dictionary = _require_own_disciple(request_id, params)
	if not bool(disciple_check["ok"]): return disciple_check["response"]
	var promotion_check: Dictionary = _require_nonempty(params, "promotionId")
	if not bool(promotion_check["ok"]): return Dto.error_response(request_id, Msg.ERR_BAD_PARAMS, str(promotion_check["message"]))
	var before: int = state.eventLog.size()
	var result: Dictionary = UnitAction.promote(state, _config, str(disciple_check["value"]), str(promotion_check["value"]))
	return Dto.ok_response(request_id, state.eventLog.slice(before), StateView.build(state, _config), result)


## 弟子详情：只读。允许查看任意可见弟子的详情（`view` 本就把可见格上的敌方弟子下发）。
func _handle_query_disciple_detail(request_id: String, params: Dictionary) -> Dictionary:
	if state == null: return Dto.error_response(request_id, Msg.ERR_NO_GAME, "尚未开局")
	var check: Dictionary = _require_nonempty(params, "discipleId")
	if not bool(check["ok"]): return Dto.error_response(request_id, Msg.ERR_BAD_PARAMS, str(check["message"]))
	return Dto.ok_response(request_id, [], null, UnitAction.query_disciple_detail(state, _config, str(check["value"])))


## 校验字符串数组参数；返回 {ok, value, message}。
func _require_string_array(params: Dictionary, key: String) -> Dictionary:
	var raw: Variant = params.get(key)
	if typeof(raw) != TYPE_ARRAY: return {"ok": false, "message": "%s 必须是字符串数组" % key}
	var values: Array = []
	for entry: Variant in raw:
		if typeof(entry) != TYPE_STRING or String(entry).is_empty():
			return {"ok": false, "message": "%s 的每一项都必须是非空字符串" % key}
		values.append(String(entry))
	return {"ok": true, "value": values}


## 校验布尔参数；返回 {ok, value, message}。
func _require_bool(params: Dictionary, key: String) -> Dictionary:
	var raw: Variant = params.get(key)
	if typeof(raw) != TYPE_BOOL:
		return {"ok": false, "message": "%s 必须是布尔值" % key}
	return {"ok": true, "value": bool(raw)}


## 从 `policy` 配置取某类 id 清单（`governments` / `cards`），供 `_require_enum` 做 BAD_PARAMS 把关。
func _policy_ids(section: String) -> Array:
	var list: Array = _config["policy"].get(section, [])
	var ids: Array = []
	for entry: Variant in list:
		ids.append(str((entry as Dictionary).get("id", "")))
	return ids


# ---------------------------------------------------------------------------
# 处理器（R6：探索 + 政令 + 自动化/设置 + 集结/回防）
# ---------------------------------------------------------------------------
# 只读（`queryJiYuanInfo`/`queryMiJingInfo`/`queryPolicyOptions`/`queryAutomationState`）→ view=null；
# 写命令 → 实时 view + 本命令期间新增日志；`setSetting` → view=null 且不改 `GameState`。
# 业务失败（冷却中/灵石不足/人数超限/槽位满/时代未到/道法未解锁…）一律
# `ok:true + result.success:false + message`；只有参数缺失/类型错/枚举非法才 `BAD_PARAMS`。

## `rally`：`tileId` 可省（省则集结到己方主峰地块）。
func _handle_rally(request_id: String, params: Dictionary) -> Dictionary:
	if state == null: return Dto.error_response(request_id, Msg.ERR_NO_GAME, "尚未开局")
	var sect_check: Dictionary = _require_player_sect(request_id, params)
	if not bool(sect_check["ok"]): return sect_check["response"]
	var tile_id: String = ""
	if params.has("tileId"):
		var tile_check: Dictionary = _require_nonempty(params, "tileId")
		if not bool(tile_check["ok"]): return Dto.error_response(request_id, Msg.ERR_BAD_PARAMS, str(tile_check["message"]))
		tile_id = str(tile_check["value"])
	else:
		tile_id = _player_capital_tile_id()
		if tile_id.is_empty(): return Dto.error_response(request_id, Msg.ERR_BAD_PARAMS, "未指定 tileId 且本宗没有可用的集结地")
	if not state.tiles.has(tile_id): return Dto.error_response(request_id, Msg.ERR_BAD_PARAMS, "目标地块不存在：" + tile_id)
	var before: int = state.eventLog.size()
	var result: Dictionary = AutomationAction.rally(state, _config, str(sect_check["value"]), tile_id)
	return Dto.ok_response(request_id, state.eventLog.slice(before), StateView.build(state, _config), result)


func _handle_return_to_defense(request_id: String, params: Dictionary) -> Dictionary:
	if state == null: return Dto.error_response(request_id, Msg.ERR_NO_GAME, "尚未开局")
	var sect_check: Dictionary = _require_player_sect(request_id, params)
	if not bool(sect_check["ok"]): return sect_check["response"]
	var before: int = state.eventLog.size()
	var result: Dictionary = AutomationAction.return_to_defense(state, _config, str(sect_check["value"]))
	return Dto.ok_response(request_id, state.eventLog.slice(before), StateView.build(state, _config), result)


func _handle_query_ji_yuan_info(request_id: String, params: Dictionary) -> Dictionary:
	if state == null: return Dto.error_response(request_id, Msg.ERR_NO_GAME, "尚未开局")
	var node_check: Dictionary = _require_nonempty(params, "nodeId")
	if not bool(node_check["ok"]): return Dto.error_response(request_id, Msg.ERR_BAD_PARAMS, str(node_check["message"]))
	if not state.nodes.has(str(node_check["value"])): return Dto.error_response(request_id, Msg.ERR_BAD_PARAMS, "节点不存在：" + str(node_check["value"]))
	return Dto.ok_response(request_id, [], null, ExploreAction.query_ji_yuan_info(state, _config, str(node_check["value"])))


func _handle_send_to_ji_yuan(request_id: String, params: Dictionary) -> Dictionary:
	if state == null: return Dto.error_response(request_id, Msg.ERR_NO_GAME, "尚未开局")
	var disciple_check: Dictionary = _require_own_disciple(request_id, params)
	if not bool(disciple_check["ok"]): return disciple_check["response"]
	var node_check: Dictionary = _require_nonempty(params, "nodeId")
	if not bool(node_check["ok"]): return Dto.error_response(request_id, Msg.ERR_BAD_PARAMS, str(node_check["message"]))
	if not state.nodes.has(str(node_check["value"])): return Dto.error_response(request_id, Msg.ERR_BAD_PARAMS, "节点不存在：" + str(node_check["value"]))
	var before: int = state.eventLog.size()
	var result: Dictionary = ExploreAction.send_to_ji_yuan(state, _config, str(disciple_check["value"]), str(node_check["value"]))
	return Dto.ok_response(request_id, state.eventLog.slice(before), StateView.build(state, _config), result)


func _handle_query_mi_jing_info(request_id: String, params: Dictionary) -> Dictionary:
	if state == null: return Dto.error_response(request_id, Msg.ERR_NO_GAME, "尚未开局")
	var node_check: Dictionary = _require_nonempty(params, "nodeId")
	if not bool(node_check["ok"]): return Dto.error_response(request_id, Msg.ERR_BAD_PARAMS, str(node_check["message"]))
	if not state.nodes.has(str(node_check["value"])): return Dto.error_response(request_id, Msg.ERR_BAD_PARAMS, "节点不存在：" + str(node_check["value"]))
	return Dto.ok_response(request_id, [], null, ExploreAction.query_mi_jing_info(state, _config, str(node_check["value"])))


## 秘境多人探索：`discipleIds` 只校验形状（同宗/在格/灵石由规则回 `success:false`，与 `batchMove` 同口径）。
func _handle_explore_mi_jing(request_id: String, params: Dictionary) -> Dictionary:
	if state == null: return Dto.error_response(request_id, Msg.ERR_NO_GAME, "尚未开局")
	var list_check: Dictionary = _require_string_array(params, "discipleIds")
	if not bool(list_check["ok"]): return Dto.error_response(request_id, Msg.ERR_BAD_PARAMS, str(list_check["message"]))
	var node_check: Dictionary = _require_nonempty(params, "nodeId")
	if not bool(node_check["ok"]): return Dto.error_response(request_id, Msg.ERR_BAD_PARAMS, str(node_check["message"]))
	if not state.nodes.has(str(node_check["value"])): return Dto.error_response(request_id, Msg.ERR_BAD_PARAMS, "节点不存在：" + str(node_check["value"]))
	var before: int = state.eventLog.size()
	var result: Dictionary = ExploreAction.explore_mi_jing(state, _config, list_check["value"], str(node_check["value"]))
	return Dto.ok_response(request_id, state.eventLog.slice(before), StateView.build(state, _config), result)


## 切换政体：`governmentId` 必须在 `policy.governments[].id` 内（非法 → BAD_PARAMS）。
func _handle_switch_government(request_id: String, params: Dictionary) -> Dictionary:
	if state == null: return Dto.error_response(request_id, Msg.ERR_NO_GAME, "尚未开局")
	var sect_check: Dictionary = _require_player_sect(request_id, params)
	if not bool(sect_check["ok"]): return sect_check["response"]
	var gov_check: Dictionary = _require_enum(params, "governmentId", _policy_ids("governments"))
	if not bool(gov_check["ok"]): return Dto.error_response(request_id, Msg.ERR_BAD_PARAMS, str(gov_check["message"]))
	var before: int = state.eventLog.size()
	var result: Dictionary = PolicyAction.switch_government(state, _config, str(sect_check["value"]), str(gov_check["value"]))
	return Dto.ok_response(request_id, state.eventLog.slice(before), StateView.build(state, _config), result)


## 颁行政令：参数名 `cardId`（PROTOCOL §11.1 #5），必须在 `policy.cards[].id` 内。
func _handle_enact_policy(request_id: String, params: Dictionary) -> Dictionary:
	if state == null: return Dto.error_response(request_id, Msg.ERR_NO_GAME, "尚未开局")
	var sect_check: Dictionary = _require_player_sect(request_id, params)
	if not bool(sect_check["ok"]): return sect_check["response"]
	var card_check: Dictionary = _require_enum(params, "cardId", _policy_ids("cards"))
	if not bool(card_check["ok"]): return Dto.error_response(request_id, Msg.ERR_BAD_PARAMS, str(card_check["message"]))
	var before: int = state.eventLog.size()
	var result: Dictionary = PolicyAction.enact_policy(state, _config, str(sect_check["value"]), str(card_check["value"]))
	return Dto.ok_response(request_id, state.eventLog.slice(before), StateView.build(state, _config), result)


func _handle_revoke_policy(request_id: String, params: Dictionary) -> Dictionary:
	if state == null: return Dto.error_response(request_id, Msg.ERR_NO_GAME, "尚未开局")
	var sect_check: Dictionary = _require_player_sect(request_id, params)
	if not bool(sect_check["ok"]): return sect_check["response"]
	var card_check: Dictionary = _require_enum(params, "cardId", _policy_ids("cards"))
	if not bool(card_check["ok"]): return Dto.error_response(request_id, Msg.ERR_BAD_PARAMS, str(card_check["message"]))
	var before: int = state.eventLog.size()
	var result: Dictionary = PolicyAction.revoke_policy(state, _config, str(sect_check["value"]), str(card_check["value"]))
	return Dto.ok_response(request_id, state.eventLog.slice(before), StateView.build(state, _config), result)


func _handle_query_policy_options(request_id: String, params: Dictionary) -> Dictionary:
	if state == null: return Dto.error_response(request_id, Msg.ERR_NO_GAME, "尚未开局")
	var sect_check: Dictionary = _require_player_sect(request_id, params)
	if not bool(sect_check["ok"]): return sect_check["response"]
	return Dto.ok_response(request_id, [], null, PolicyAction.query_policy_options(state, _config, str(sect_check["value"])))


## 自动化开关：`key` 必须是 `improve`/`repair`/`road`/`explore`（非法 → BAD_PARAMS，PROTOCOL §7 明列）。
func _handle_set_automation_toggle(request_id: String, params: Dictionary) -> Dictionary:
	if state == null: return Dto.error_response(request_id, Msg.ERR_NO_GAME, "尚未开局")
	var sect_check: Dictionary = _require_player_sect(request_id, params)
	if not bool(sect_check["ok"]): return sect_check["response"]
	var key_check: Dictionary = _require_enum(params, "key", AutomationRules.TOGGLE_KEYS)
	if not bool(key_check["ok"]): return Dto.error_response(request_id, Msg.ERR_BAD_PARAMS, str(key_check["message"]))
	var on_check: Dictionary = _require_bool(params, "on")
	if not bool(on_check["ok"]): return Dto.error_response(request_id, Msg.ERR_BAD_PARAMS, str(on_check["message"]))
	var before: int = state.eventLog.size()
	var result: Dictionary = AutomationAction.set_automation_toggle(state, _config, str(sect_check["value"]), str(key_check["value"]), bool(on_check["value"]))
	return Dto.ok_response(request_id, state.eventLog.slice(before), StateView.build(state, _config), result)


func _handle_set_peak_auto_project(request_id: String, params: Dictionary) -> Dictionary:
	if state == null: return Dto.error_response(request_id, Msg.ERR_NO_GAME, "尚未开局")
	var peak_check: Dictionary = _require_player_peak(request_id, params)
	if not bool(peak_check["ok"]): return peak_check["response"]
	var on_check: Dictionary = _require_bool(params, "on")
	if not bool(on_check["ok"]): return Dto.error_response(request_id, Msg.ERR_BAD_PARAMS, str(on_check["message"]))
	var before: int = state.eventLog.size()
	var result: Dictionary = AutomationAction.set_peak_auto_project(state, _config, str(peak_check["value"]), bool(on_check["value"]))
	return Dto.ok_response(request_id, state.eventLog.slice(before), StateView.build(state, _config), result)


func _handle_set_all_auto_project(request_id: String, params: Dictionary) -> Dictionary:
	if state == null: return Dto.error_response(request_id, Msg.ERR_NO_GAME, "尚未开局")
	var sect_check: Dictionary = _require_player_sect(request_id, params)
	if not bool(sect_check["ok"]): return sect_check["response"]
	var on_check: Dictionary = _require_bool(params, "on")
	if not bool(on_check["ok"]): return Dto.error_response(request_id, Msg.ERR_BAD_PARAMS, str(on_check["message"]))
	var before: int = state.eventLog.size()
	var result: Dictionary = AutomationAction.set_all_auto_project(state, _config, str(sect_check["value"]), bool(on_check["value"]))
	return Dto.ok_response(request_id, state.eventLog.slice(before), StateView.build(state, _config), result)


func _handle_explore_now(request_id: String, params: Dictionary) -> Dictionary:
	if state == null: return Dto.error_response(request_id, Msg.ERR_NO_GAME, "尚未开局")
	var sect_check: Dictionary = _require_player_sect(request_id, params)
	if not bool(sect_check["ok"]): return sect_check["response"]
	var before: int = state.eventLog.size()
	var result: Dictionary = AutomationAction.explore_now(state, _config, str(sect_check["value"]))
	return Dto.ok_response(request_id, state.eventLog.slice(before), StateView.build(state, _config), result)


func _handle_query_automation_state(request_id: String, params: Dictionary) -> Dictionary:
	if state == null: return Dto.error_response(request_id, Msg.ERR_NO_GAME, "尚未开局")
	var sect_check: Dictionary = _require_player_sect(request_id, params)
	if not bool(sect_check["ok"]): return sect_check["response"]
	return Dto.ok_response(request_id, [], null, AutomationAction.query_automation_state(state, _config, str(sect_check["value"])))


## `setSetting`：**不改 `GameState`、不回 view**（PROTOCOL §7）；`value` 允许任意类型但必须存在。
func _handle_set_setting(request_id: String, params: Dictionary) -> Dictionary:
	var key_check: Dictionary = _require_nonempty(params, "key")
	if not bool(key_check["ok"]): return Dto.error_response(request_id, Msg.ERR_BAD_PARAMS, str(key_check["message"]))
	if not params.has("value"): return Dto.error_response(request_id, Msg.ERR_BAD_PARAMS, "value 必须存在")
	var result: Dictionary = AutomationAction.set_setting(str(key_check["value"]), params["value"])
	return Dto.ok_response(request_id, [], null, result)


## 己方主峰地块 id（`rally` 省略 `tileId` 时的集结地）。
func _player_capital_tile_id() -> String:
	var peak_id: String = _player_capital_peak_id()
	if peak_id.is_empty(): return ""
	var peak: SpiritPeak = CityAction.find_peak(state, peak_id)
	return "" if peak == null else peak.tileId
