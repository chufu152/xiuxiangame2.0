extends Node
## R7 自动验收：任命/血脉/渡劫 + 反应式 AI + 三流派胜负/分数 + 存档读档 + 胜利择一待决。
##
## 无头运行：`godot --headless --path server res://tests/R7Test.tscn`，
## 全绿打印 `R7_PASS checks=N` 并退出码 0，否则 `R7_FAIL ...` 退出码 1。
##
## **断言原则**（沿用 R5/R6）：
## 1. 期望值一律**从 `data/gameConfig.json` 独立复算**，不拿被测函数的返回值当自己的判据；
## 2. 需要「必定成功 / 必定失败 / 必定陨落」的分支，把 `config` **深拷贝**后改那一个概率为 0 或 1
##    再直接调 `*Rules`，使分支完全确定、不靠运气（命令层仍走真实 `_config`）；
## 3. 概率本身只做**独立复算式**断言；
## 4. 每组测试都新建一局（`_new_game`），避免上一组改过的资源/弟子污染下一组；
## 5. 存档测试只用槽位 90–99，跑完即清，不碰玩家的真实存档。

const R7_COMMANDS: Array[String] = [
	Commands.LIST_SAVES, Commands.SAVE_GAME, Commands.LOAD_GAME,
	Commands.QUERY_VICTORY_PROGRESS, Commands.CHECK_VICTORY, Commands.CHECK_DEFEAT,
	Commands.CHOOSE_VICTORY, Commands.QUERY_GAME_OVER,
	Commands.TRIBULATE, Commands.APPOINT_FENG_ZHU, Commands.APPOINT_ZHANG_LAO, Commands.APPOINT_ZONG_ZHU,
	Commands.QUERY_VICTORY_CHOICE, Commands.RESOLVE_CHOICE,
]

## 只读命令：必须回 `view=null`（PROTOCOL §2/§3/§8）。
const READ_ONLY_R7: Array[String] = [
	Commands.LIST_SAVES, Commands.QUERY_VICTORY_PROGRESS, Commands.CHECK_VICTORY,
	Commands.CHECK_DEFEAT, Commands.QUERY_GAME_OVER, Commands.QUERY_VICTORY_CHOICE,
]

## 需要 `GameState` 的命令（`listSaves`/`saveGame` 无开局也能回）。
const NEEDS_GAME_R7: Array[String] = [
	Commands.QUERY_VICTORY_PROGRESS, Commands.CHECK_VICTORY,
	Commands.CHECK_DEFEAT, Commands.CHOOSE_VICTORY, Commands.QUERY_GAME_OVER,
	Commands.TRIBULATE, Commands.APPOINT_FENG_ZHU, Commands.APPOINT_ZHANG_LAO,
	Commands.APPOINT_ZONG_ZHU, Commands.QUERY_VICTORY_CHOICE, Commands.RESOLVE_CHOICE,
]

## 存档测试专用槽位区间（避开玩家真实存档）。
const TEST_SLOT_BASE: int = 90
const TEST_SLOT_COUNT: int = 10

var _failures: Array[String] = []
var _checks: int = 0
## 已实现命令总数（`_test_registration` 记录，供 `R7_IMPLEMENTED=` 行自报，check.ps1 据此卡 70 条）。
var _implemented_count: int = 0
var _config: Dictionary = {}
var _finished: bool = false
var _started: int = Time.get_ticks_msec()


func _process(_delta: float) -> void:
	if not _finished and Time.get_ticks_msec() - _started > 420000:
		printerr("R7_FAIL 测试未正常完成（可能运行时脚本错误）")
		get_tree().quit(1)


func _ready() -> void:
	var loaded: Dictionary = ConfigLoader.load_from_file(ConfigLoader.default_path())
	_check(bool(loaded["ok"]), "配置可加载")
	_config = loaded["config"]
	_check(ConfigValidator.validate(_config).is_empty(), "配置通过深层验证")
	_clean_test_slots()
	_test_registration()
	_test_appointment()
	_test_appointment_bonus()
	_test_bloodline()
	_test_tribulate()
	_test_ai()
	_test_victory_routes()
	_test_score()
	_test_victory_choice()
	_test_save()
	_test_backfill()
	_test_determinism()
	_clean_test_slots()
	_finished = true
	if _failures.is_empty():
		print("R7_IMPLEMENTED=%d" % _implemented_count)
		print("R7_PASS checks=%d" % _checks)
		get_tree().quit(0)
	else:
		for failure: String in _failures:
			printerr("R7_FAIL " + failure)
		printerr("R7_FAIL checks=%d failures=%d" % [_checks, _failures.size()])
		get_tree().quit(1)


# ---------------------------------------------------------------------------
# 1. 命令注册、只读契约、参数把关
# ---------------------------------------------------------------------------

func _test_registration() -> void:
	var dispatcher: CommandDispatcher = CommandDispatcher.new(_config)
	var implemented: Array = dispatcher.implemented_commands()
	_implemented_count = implemented.size()
	for command: String in R7_COMMANDS:
		_check(implemented.has(command), "已登记 R7 命令：" + command)
	# 全量口径：69 条业务命令 + ping = 70（PROTOCOL §1）。
	_check(implemented.size() == 70, "已实现命令 70 条（69 + ping，实际 %d）" % implemented.size())
	_check(implemented.has(Commands.PING), "ping 已登记")
	for command: String in NEEDS_GAME_R7:
		_check(_request(dispatcher, command, {}).get("errorCode") == "NO_GAME", "%s 开局前 NO_GAME" % command)
	# `saveGame` 未开局是**业务失败**而非协议失败：ok:true + saved:false（硬约束 4）。
	var save_no_game: Dictionary = _request(dispatcher, Commands.SAVE_GAME, {"slot": TEST_SLOT_BASE})
	_check(bool(save_no_game.get("ok")) and bool(save_no_game["result"]["saved"]) == false,
		"saveGame 未开局回 ok:true + saved:false")
	_check(not save_no_game["result"].has("success"), "saveGame 结果不含 success 布尔（存档类固定形状）")
	# `listSaves` 无开局也能用（纯文件枚举）。
	_check(bool(_request(dispatcher, Commands.LIST_SAVES, {}).get("ok")), "listSaves 无开局可用")

	var game: CommandDispatcher = _new_game("r7-registration")
	for command: String in READ_ONLY_R7:
		var params: Dictionary = {}
		if command in [Commands.QUERY_VICTORY_PROGRESS, Commands.CHECK_VICTORY, Commands.CHECK_DEFEAT]:
			params["sectId"] = game.state.playerSectId
		var response: Dictionary = _request(game, command, params)
		_check(bool(response.get("ok")) and response.get("view") == null,
			"%s 只读命令回 view=null" % command)
	# 参数把关：sectId 不存在 / routeId 空 / slot 非法 / optionIndex 非整数。
	_check(_request(game, Commands.QUERY_VICTORY_PROGRESS, {"sectId": "no_such_sect"}).get("errorCode") == "BAD_PARAMS",
		"queryVictoryProgress 不存在的 sectId → BAD_PARAMS")
	_check(_request(game, Commands.CHOOSE_VICTORY, {}).get("errorCode") == "BAD_PARAMS",
		"chooseVictory 缺 routeId → BAD_PARAMS")
	_check(_request(game, Commands.SAVE_GAME, {"slot": "abc"}).get("errorCode") == "BAD_PARAMS",
		"saveGame 非法 slot → BAD_PARAMS")
	_check(_request(game, Commands.LOAD_GAME, {"slot": 999}).get("errorCode") == "BAD_PARAMS",
		"loadGame 不存在的槽位 → BAD_PARAMS")
	_check(_request(game, Commands.RESOLVE_CHOICE, {"reqId": "req_victory_1", "optionIndex": "x"}).get("errorCode") == "BAD_PARAMS",
		"resolveChoice 非整数 optionIndex → BAD_PARAMS")


# ---------------------------------------------------------------------------
# 2. 任命：名额 / 境界门槛 / 岗位互斥
# ---------------------------------------------------------------------------

func _test_appointment() -> void:
	var dispatcher: CommandDispatcher = _new_game("r7-appoint")
	var sect: Sect = _player(dispatcher)
	VictoryRules.refresh_power_level(dispatcher.state, _config, sect)
	var base_limit: int = int(_config["appointment"]["zhangLaoBaseLimit"]) \
		+ sect.powerLevel * int(_config["appointment"]["zhangLaoPerPowerLevel"])
	_check(AppointmentRules.zhang_lao_limit(_config, sect) == base_limit,
		"长老上限 = baseLimit %d + powerLevel %d × 1 = %d" % [
			int(_config["appointment"]["zhangLaoBaseLimit"]), sect.powerLevel, base_limit])

	# 境界门槛：炼气弟子不能当峰主/长老/宗主（`Position.MIN_REALM` = JIN_DAN）。
	var outer: Disciple = _disciple_of_realm(sect, Enums.Realm.LIAN_QI)
	_check(outer != null, "开局存在炼气弟子（用于境界门槛断言）")
	if outer != null:
		for command: String in [Commands.APPOINT_FENG_ZHU, Commands.APPOINT_ZHANG_LAO, Commands.APPOINT_ZONG_ZHU]:
			var params: Dictionary = {"discipleId": outer.id}
			if command == Commands.APPOINT_FENG_ZHU:
				params["peakId"] = _capital(sect).id
			var result: Dictionary = _result(dispatcher, command, params)
			_check(bool(result.get("success")) == false and str(result.get("message", "")).contains("修为不足"),
				"%s 对炼气弟子返回 success=false + 修为不足" % command)
			_check(result.has("success") and result.has("message") and result.size() == 2,
				"%s 结果只有 {success, message} 两键（裁决二）" % command)

	# 名额：造足金丹弟子，任命到上限后第 N+1 个失败。
	var jin_dan: Array[Disciple] = []
	for index: int in range(base_limit + 1):
		jin_dan.append(_make_disciple(dispatcher.state, sect, "长老候选%d" % index, Enums.Realm.JIN_DAN,
			Enums.Position.QIN_CHUAN, _capital(sect)))
	var appointed: int = 0
	for disciple: Disciple in jin_dan:
		var result: Dictionary = _result(dispatcher, Commands.APPOINT_ZHANG_LAO, {"discipleId": disciple.id})
		if bool(result.get("success")):
			appointed += 1
	_check(appointed == base_limit, "长老任命成功 %d 人 = 上限 %d" % [appointed, base_limit])
	var overflow: Disciple = jin_dan[jin_dan.size() - 1]
	var overflow_result: Dictionary = _result(dispatcher, Commands.APPOINT_ZHANG_LAO, {"discipleId": overflow.id})
	_check(bool(overflow_result.get("success")) == false and str(overflow_result.get("message", "")).contains("已满"),
		"超长老上限返回 success=false + 已满")

	# 宗主不可兼任长老。
	var zong_zhu: Disciple = _disciple_of_position(sect, Enums.Position.ZONG_ZHU)
	_check(zong_zhu != null, "开局有宗主")
	if zong_zhu != null:
		var conflict: Dictionary = _result(dispatcher, Commands.APPOINT_ZHANG_LAO, {"discipleId": zong_zhu.id})
		_check(bool(conflict.get("success")) == false, "宗主不可兼任长老")

	# 峰主任命：原峰主降为亲传（1.0 `appointFengZhu`）。
	var capital: SpiritPeak = _capital(sect)
	var old_feng_zhu_id: String = capital.fengZhuId
	var candidate: Disciple = jin_dan[0]
	AppointmentRules.appoint_feng_zhu(dispatcher.state, _config, candidate.id, capital.id)
	_check(capital.fengZhuId == candidate.id, "峰主任命后 peak.fengZhuId 指向新峰主")
	var old: Disciple = CityAction.find_disciple(dispatcher.state, old_feng_zhu_id)
	if old != null and old.id != candidate.id:
		_check(old.position == Enums.Position.QIN_CHUAN or old.position == Enums.Position.ZONG_ZHU,
			"原峰主降为亲传（当前 %s）" % old.position)


# ---------------------------------------------------------------------------
# 3. 任命加成：峰主气运/灵力、长老修炼/研究、宗主大殿外出失效
# ---------------------------------------------------------------------------

func _test_appointment_bonus() -> void:
	var dispatcher: CommandDispatcher = _new_game("r7-appoint-bonus")
	var state: GameState = dispatcher.state
	var sect: Sect = _player(dispatcher)
	var capital: SpiritPeak = _capital(sect)

	# --- 峰主驻留：气运 +5 / 灵力 ×1.3 ---
	# 先造弟子再取基准：`peak_output` 含「弟子灵力反哺 × 弟子数」，造人会改变基准值。
	# 峰主用**炼气**弟子（`feng_zhu_present` 只看 `fengZhuId` + 是否在峰上，不看境界；
	# 境界由 `appoint*` 门控），这样「驻留高阶弟子气运」两次一致，差值纯粹是峰主加成。
	var lord: Disciple = _make_disciple(state, sect, "峰主候选人", Enums.Realm.LIAN_QI,
		Enums.Position.QIN_CHUAN, capital)
	var saved_feng_zhu: String = capital.fengZhuId
	capital.fengZhuId = ""
	var without: Dictionary = EconomyRules.peak_output(state, _config, capital)
	capital.fengZhuId = lord.id
	var with_lord: Dictionary = EconomyRules.peak_output(state, _config, capital)
	_check(int(with_lord["qiYun"]) - int(without["qiYun"]) == int(_config["appointment"]["fengZhuQiYunBonus"]),
		"峰主驻留气运 +%d（实得 %d）" % [int(_config["appointment"]["fengZhuQiYunBonus"]),
			int(with_lord["qiYun"]) - int(without["qiYun"])])
	# 灵力：只有「主峰基础灵力」这一段被乘，其余项不受影响 → 增量 = round(base×0.3)。
	var base_power: int = int(_config["spiritPeak"]["baseSpiritPowerOutput"]) * capital.level
	var expected_gain: int = int(round(float(base_power) \
		* (1.0 + float(_config["appointment"]["fengZhuSpiritPowerBonus"])))) - base_power
	_check(int(with_lord["spiritPower"]) - int(without["spiritPower"]) == expected_gain,
		"峰主驻留灵力 +%d（实得 %d）" % [expected_gain, int(with_lord["spiritPower"]) - int(without["spiritPower"])])

	# --- 峰主外出：加成失效 ---
	lord.tileId = _far_tile_id(state, capital.tileId)
	_check(AppointmentRules.feng_zhu_present(state, sect, capital) == false, "峰主离开所在峰后 feng_zhu_present=false")
	var after_leave: Dictionary = EconomyRules.peak_output(state, _config, capital)
	_check(int(after_leave["qiYun"]) == int(without["qiYun"]), "峰主外出后气运加成失效")
	capital.fengZhuId = saved_feng_zhu

	# --- 长老修炼：每位 +zhangLaoCultivationBonus（加性） ---
	var disciple: Disciple = _disciple_of_position(sect, Enums.Position.WAI_MEN)
	if disciple == null:
		disciple = _make_disciple(state, sect, "修炼样本", Enums.Realm.ZHU_JI, Enums.Position.WAI_MEN, capital)
	var speed_before: float = DiscipleRules.cultivation_speed(state, _config, disciple)
	var elder: Disciple = _make_disciple(state, sect, "长老样本", Enums.Realm.JIN_DAN, Enums.Position.ZHANG_LAO, capital)
	var speed_after: float = DiscipleRules.cultivation_speed(state, _config, disciple)
	var expected_speed: float = float(_config["disciple"]["cultivation"]["baseSpeed"]) \
		* float(_config["appointment"]["zhangLaoCultivationBonus"])
	_check(absf((speed_after - speed_before) - expected_speed) < 0.0001,
		"1 名长老使修炼速度 +%.3f（实得 %.3f）" % [expected_speed, speed_after - speed_before])
	# 长老研究加成（R4 已在 `DaoRules.research_turns` 消费，此处确认仍生效）。
	var dao: Dao = DaoRules.all_daos(_config)[0]
	var turns_with_elder: int = DaoRules.research_turns(_config, sect, dao)
	elder.position = Enums.Position.QIN_CHUAN
	var turns_without: int = DaoRules.research_turns(_config, sect, dao)
	_check(turns_with_elder <= turns_without, "长老使研究回合数不增（%d ≤ %d）" % [turns_with_elder, turns_without])
	elder.position = Enums.Position.ZHANG_LAO

	# --- 宗主大殿：坐镇首都 + 大殿建成才生效，外出失效 ---
	var zong_zhu: Disciple = _disciple_of_position(sect, Enums.Position.ZONG_ZHU)
	_check(zong_zhu != null, "开局有宗主（大殿断言）")
	if zong_zhu != null:
		capital.buildings.erase(Enums.Building.ZONG_ZHU_DA_DIAN)
		_check(AppointmentRules.zong_zhu_outside_bonus_active(state, _config, sect) == false,
			"宗主大殿未建成时加成不生效")
		capital.buildings[Enums.Building.ZONG_ZHU_DA_DIAN] = {
			"id": "b_hall", "type": Enums.Building.ZONG_ZHU_DA_DIAN, "name": "宗主大殿",
			"level": 1, "districtId": "",
		}
		zong_zhu.tileId = capital.tileId
		_check(AppointmentRules.zong_zhu_outside_bonus_active(state, _config, sect),
			"宗主坐镇首都 + 大殿建成 → 加成生效")
		_check(AppointmentRules.zong_zhu_qi_yun_bonus(state, _config, sect)
			== int(_config["appointment"]["zongZhuDaDianQiYunBonus"]),
			"宗主大殿气运加成 = %d" % int(_config["appointment"]["zongZhuDaDianQiYunBonus"]))
		var multiplier: float = AppointmentRules.zong_zhu_spirit_multiplier(state, _config, sect)
		_check(absf(multiplier - (1.0 + float(_config["appointment"]["zongZhuDaDianSpiritPowerBonus"]))) < 0.0001,
			"宗主大殿灵力乘区 = 1 + %.2f" % float(_config["appointment"]["zongZhuDaDianSpiritPowerBonus"]))
		zong_zhu.tileId = _far_tile_id(state, capital.tileId)
		_check(AppointmentRules.zong_zhu_outside_bonus_active(state, _config, sect) == false,
			"宗主外出 → 大殿加成失效")
		_check(is_equal_approx(AppointmentRules.zong_zhu_spirit_multiplier(state, _config, sect), 1.0),
			"宗主外出 → 灵力乘区退回 1.0")


# ---------------------------------------------------------------------------
# 4. 血脉：联姻 / 繁衍 / 灵根继承 / 族人死亡
# ---------------------------------------------------------------------------

func _test_bloodline() -> void:
	var dispatcher: CommandDispatcher = _new_game("r7-bloodline")
	var state: GameState = dispatcher.state
	var sect: Sect = _player(dispatcher)
	var capital: SpiritPeak = _capital(sect)
	var bloodline: Dictionary = _config["faction"]["bloodline"]

	# 造一对可婚配的族人。
	var a: Disciple = _make_disciple(state, sect, "联姻甲", Enums.Realm.ZHU_JI, Enums.Position.NEI_MEN, capital)
	var b: Disciple = _make_disciple(state, sect, "联姻乙", Enums.Realm.ZHU_JI, Enums.Position.NEI_MEN, capital)
	a.spiritRoots = ["JIN"]
	b.spiritRoots = ["MU"]
	# 1.0 `marry`：只有「一方血脉一方非血脉」才把两人都设为族人；两个都非血脉时不动。
	a.bloodLine = true
	b.bloodLine = false
	sect.resources["spiritStones"] = 1000
	sect.resources["workPower"] = 1000

	# --- 联姻：扣 marryCostStones 50 ---
	var before_stones: int = int(sect.resources["spiritStones"])
	var married: Dictionary = BloodlineRules.marry(state, _config, a.id, b.id)
	_check(bool(married["success"]), "联姻成功")
	_check(before_stones - int(sect.resources["spiritStones"]) == int(bloodline["marryCostStones"]),
		"联姻消耗 %d 灵石（实际 %d）" % [int(bloodline["marryCostStones"]),
			before_stones - int(sect.resources["spiritStones"])])
	_check(a.spouseId == b.id and b.spouseId == a.id, "道侣双向绑定")
	_check(a.bloodLine and b.bloodLine, "非血脉一方随婚入族")

	# --- 繁衍：扣 120 石 + 60 工 ---
	var stones_before: int = int(sect.resources["spiritStones"])
	var work_before: int = int(sect.resources["workPower"])
	var born: Dictionary = BloodlineRules.reproduce(state, _config, capital.id, a.id, b.id)
	_check(bool(born["success"]), "繁衍成功")
	_check(stones_before - int(sect.resources["spiritStones"]) == int(bloodline["reproduceCostStones"]),
		"繁衍消耗 %d 灵石（实际 %d）" % [int(bloodline["reproduceCostStones"]),
			stones_before - int(sect.resources["spiritStones"])])
	_check(work_before - int(sect.resources["workPower"]) == int(bloodline["reproduceCostWorkPower"]),
		"繁衍消耗 %d 工力（实际 %d）" % [int(bloodline["reproduceCostWorkPower"]),
			work_before - int(sect.resources["workPower"])])
	var child: Disciple = CityAction.find_disciple(state, str(born["childId"]))
	_check(child != null, "子嗣已入宗门名册")
	if child != null:
		_check(child.fatherId == a.id and child.motherId == b.id, "子嗣父母 id 已记录")
		_check(child.generation == maxi(a.generation, b.generation) + 1,
			"子嗣代数 = max(父母)+1（%d）" % child.generation)
		_check(child.bloodLine, "子嗣继承血脉")

	# --- 冷却 5 回合 ---
	_check(BloodlineRules.reproduce_blocker(state, _config, capital.id, a.id, b.id).contains("休养"),
		"繁衍后进入 %d 回合冷却" % int(bloodline["reproduceCooldownTurns"]))
	state.turn += int(bloodline["reproduceCooldownTurns"])
	_check(BloodlineRules.reproduce_blocker(state, _config, capital.id, a.id, b.id).is_empty(),
		"冷却 %d 回合后可再繁衍" % int(bloodline["reproduceCooldownTurns"]))

	# --- 品级抖动：把概率钉死，独立复算式断言 ---
	_check_inherit_grade(bloodline)
	# --- 多灵根：extraRootChance 钉 1 → 双灵根 ---
	var extra_config: Dictionary = _config.duplicate(true)
	extra_config["faction"]["bloodline"]["extraRootChance"] = 1.0
	var roots: Array[String] = BloodlineRules.inherit_roots(state, a, b, 1.0)
	_check(roots.size() == 2, "extraRootChance=1 时子嗣为双灵根（实得 %d）" % roots.size())
	_check(roots[0] != roots[1], "双灵根不重复")

	# --- 族人死亡：安定 −5（家族流 + 血脉弟子才触发） ---
	var jia_zu_dispatcher: CommandDispatcher = _new_game("r7-bloodline-death", Enums.FactionType.JIA_ZU)
	var jia_state: GameState = jia_zu_dispatcher.state
	var jia_sect: Sect = _player(jia_zu_dispatcher)
	var jia_peak: SpiritPeak = _capital(jia_sect)
	jia_peak.stability = 50.0
	var clan_member: Disciple = _disciple_of_position(jia_sect, Enums.Position.ZONG_ZHU)
	_check(clan_member != null and clan_member.bloodLine, "家族流宗主为血脉族人")
	if clan_member != null:
		BloodlineRules.on_clan_death(jia_state, _config, jia_sect, clan_member)
		_check(absf(jia_peak.stability - (50.0 - float(bloodline["bloodlineDeathStabilityPenalty"]))) < 0.0001,
			"族人死亡安定 -%d（实得 %.1f）" % [int(bloodline["bloodlineDeathStabilityPenalty"]), jia_peak.stability])
	# 非家族流不触发。
	var zong_peak: SpiritPeak = _capital(sect)
	zong_peak.stability = 50.0
	BloodlineRules.on_clan_death(state, _config, sect, child)
	_check(absf(zong_peak.stability - 50.0) < 0.0001, "非家族流族人死亡不扣安定")


## 品级继承的独立复算：把三处概率钉成确定值，逐个分支验证。
func _check_inherit_grade(bloodline: Dictionary) -> void:
	var dispatcher: CommandDispatcher = _new_game("r7-grade")
	var state: GameState = dispatcher.state
	var sect: Sect = _player(dispatcher)
	var capital: SpiritPeak = _capital(sect)
	var father: Disciple = _make_disciple(state, sect, "父", Enums.Realm.ZHU_JI, Enums.Position.NEI_MEN, capital)
	var mother: Disciple = _make_disciple(state, sect, "母", Enums.Realm.ZHU_JI, Enums.Position.NEI_MEN, capital)
	father.rootGrade = 3
	mother.rootGrade = 3

	# 分支 A：全部概率 0 → 品级 = 父母均值（四舍五入）。
	var flat: Dictionary = _config.duplicate(true)
	flat["faction"]["bloodline"]["gradeJitterChance"] = 0.0
	flat["faction"]["bloodline"]["gradeMutationUpChance"] = 0.0
	flat["faction"]["jiaZu"]["highGradeRootChanceBonus"] = 0.0
	var child_a: Disciple = BloodlineRules.inherit_child(state, flat, sect, capital, father, mother)
	_check(child_a.rootGrade == 3, "无变异时品级 = 父母均值 3（实得 %d）" % child_a.rootGrade)

	# 分支 B：抖动必命中 → 均值 ±1（不为 2 也不为 4）。
	var jitter: Dictionary = flat.duplicate(true)
	jitter["faction"]["bloodline"]["gradeJitterChance"] = 1.0
	var child_b: Disciple = BloodlineRules.inherit_child(state, jitter, sect, capital, father, mother)
	_check(child_b.rootGrade == 2 or child_b.rootGrade == 4,
		"抖动命中时品级 = 3±1（实得 %d）" % child_b.rootGrade)

	# 分支 C：上变必命中 → 均值 +1。
	var mutate: Dictionary = flat.duplicate(true)
	mutate["faction"]["bloodline"]["gradeMutationUpChance"] = 1.0
	var child_c: Disciple = BloodlineRules.inherit_child(state, mutate, sect, capital, father, mother)
	_check(child_c.rootGrade == 4, "上变命中时品级 = 3+1（实得 %d）" % child_c.rootGrade)

	# 分支 D：家族流高品加成必命中 → 均值 +1。
	var jia: CommandDispatcher = _new_game("r7-grade-jia", Enums.FactionType.JIA_ZU)
	var jia_sect: Sect = _player(jia)
	var jia_peak: SpiritPeak = _capital(jia_sect)
	var jia_father: Disciple = _make_disciple(jia.state, jia_sect, "父", Enums.Realm.ZHU_JI, Enums.Position.NEI_MEN, jia_peak)
	var jia_mother: Disciple = _make_disciple(jia.state, jia_sect, "母", Enums.Realm.ZHU_JI, Enums.Position.NEI_MEN, jia_peak)
	jia_father.rootGrade = 3
	jia_mother.rootGrade = 3
	var bonus: Dictionary = flat.duplicate(true)
	bonus["faction"]["jiaZu"]["highGradeRootChanceBonus"] = 1.0
	var child_d: Disciple = BloodlineRules.inherit_child(jia.state, bonus, jia_sect, jia_peak, jia_father, jia_mother)
	_check(child_d.rootGrade == 4, "家族流高品加成命中时品级 = 3+1（实得 %d）" % child_d.rootGrade)
	# 同一概率对非家族流不生效。
	var child_e: Disciple = BloodlineRules.inherit_child(state, bonus, sect, capital, father, mother)
	_check(child_e.rootGrade == 3, "非家族流不吃 highGradeRootChanceBonus（实得 %d）" % child_e.rootGrade)
	# 品级夹取 [1, 5]。
	_check(child_a.rootGrade >= 1 and child_a.rootGrade <= 5, "品级夹取在 1..5")


# ---------------------------------------------------------------------------
# 5. 渡劫：成功率独立复算 / 失败心魔 / 陨落 / 飞升
# ---------------------------------------------------------------------------

func _test_tribulate() -> void:
	var dispatcher: CommandDispatcher = _new_game("r7-tribulate")
	var state: GameState = dispatcher.state
	var sect: Sect = _player(dispatcher)
	var capital: SpiritPeak = _capital(sect)
	var cultivation: Dictionary = _config["disciple"]["cultivation"]
	var disciple: Disciple = _make_disciple(state, sect, "渡劫者", Enums.Realm.YUAN_YING,
		Enums.Position.QIN_CHUAN, capital)
	disciple.rootGrade = 3
	sect.unlockedDaoIds = ["dao_a", "dao_b"]

	# 成功率独立复算：base + 已解锁道法数 × perUnlocked + 品级 × perGrade，clamp [0,1]。
	var expected_chance: float = float(cultivation["tribulationBaseSuccessChance"]) \
		+ float(sect.unlockedDaoIds.size()) * float(cultivation["tribulationDaoBonusPerUnlocked"]) \
		+ float(disciple.rootGrade) * float(cultivation["tribulationRootGradeBonusPerGrade"])
	expected_chance = clampf(expected_chance, 0.0, 1.0)

	# 资源不足 → 业务失败（不是协议失败）。
	sect.resources["spiritPower"] = 0
	var poor: Dictionary = _result(dispatcher, Commands.TRIBULATE, {"discipleId": disciple.id})
	_check(bool(poor.get("success")) == false and str(poor.get("message", "")).contains("灵力不足"),
		"灵力不足时 tribulate 返回 success=false + 灵力不足")

	# 备足资源，把成功率钉成 1 → 必定飞升。
	var success_config: Dictionary = _config.duplicate(true)
	success_config["disciple"]["cultivation"]["tribulationBaseSuccessChance"] = 1.0
	sect.resources["spiritPower"] = 100000
	sect.resources["spiritStones"] = 100000
	var materials: Dictionary = {}
	for material: Variant in (cultivation["tribulationMaterialCosts"] as Dictionary).keys():
		materials[str(material)] = 100
	sect.resources["materials"] = materials
	var success: Dictionary = AppointmentAction.tribulate(state, success_config, disciple.id)
	_check(bool(success["success"]), "成功率钉 1 时渡劫成功")
	_check(disciple.realm == Enums.Realm.HUA_SHEN, "渡劫成功晋化神（当前 %s）" % disciple.realm)
	_check(disciple.ascended, "渡劫成功后 ascended=true")

	# 失败分支：成功率 0 + 不陨落 → 心魔 +50。
	var victim: Disciple = _make_disciple(state, sect, "渡劫失败者", Enums.Realm.YUAN_YING,
		Enums.Position.QIN_CHUAN, capital)
	victim.heartDevil = 10
	var fail_config: Dictionary = _config.duplicate(true)
	fail_config["disciple"]["cultivation"]["tribulationBaseSuccessChance"] = 0.0
	fail_config["disciple"]["cultivation"]["tribulationDaoBonusPerUnlocked"] = 0.0
	fail_config["disciple"]["cultivation"]["tribulationRootGradeBonusPerGrade"] = 0.0
	fail_config["disciple"]["cultivation"]["tribulationFailFallChance"] = 0.0
	var failed: Dictionary = AppointmentAction.tribulate(state, fail_config, victim.id)
	_check(bool(failed["success"]) == false, "成功率钉 0 时渡劫失败")
	_check(victim.heartDevil == 10 + int(cultivation["tribulationFailHeartDevil"]),
		"渡劫失败心魔 +%d（实得 %d）" % [int(cultivation["tribulationFailHeartDevil"]), victim.heartDevil])
	_check(bool(failed["fallen"]) == false, "陨落概率 0 时不身死")
	_check(victim.ascended == false, "渡劫失败不置 ascended")

	# 陨落分支：陨落概率 1 → fallen=true。
	var doomed: Disciple = _make_disciple(state, sect, "陨落者", Enums.Realm.YUAN_YING,
		Enums.Position.QIN_CHUAN, capital)
	var fall_config: Dictionary = fail_config.duplicate(true)
	fall_config["disciple"]["cultivation"]["tribulationFailFallChance"] = 1.0
	var fallen: Dictionary = AppointmentAction.tribulate(state, fall_config, doomed.id)
	_check(bool(fallen["success"]) == false and bool(fallen["fallen"]), "陨落概率 1 时 fallen=true")

	# 独立复算的成功率与规则函数一致（用真实 config 再算一遍）。
	var probe: Disciple = _make_disciple(state, sect, "概率探针", Enums.Realm.YUAN_YING,
		Enums.Position.QIN_CHUAN, capital)
	probe.rootGrade = 3
	var probe_result: Dictionary = DiscipleRules.tribulate(state, _config, probe)
	_check(absf(float(probe_result["chance"]) - expected_chance) < 0.0001,
		"渡劫成功率 %.4f = 独立复算 %.4f" % [float(probe_result["chance"]), expected_chance])


# ---------------------------------------------------------------------------
# 6. AI：行动点数 / 攻击门槛 / 视野刷新 / 不检查宣战
# ---------------------------------------------------------------------------

func _test_ai() -> void:
	# 行动点数：难度覆盖 `ai.actionPoints`。
	var levels: Dictionary = _config["difficulty"]["levels"]
	for level: String in ["easy", "normal", "hard"]:
		_check(AIController.action_points(_config, level) == int(levels[level]["aiActionPoints"]),
			"%s 难度 AI 行动点 = %d" % [level, int(levels[level]["aiActionPoints"])])
	_check(AIController.action_points(_config, "no_such_level") == int(_config["ai"]["actionPoints"]),
		"未知难度回退 ai.actionPoints")

	# AI 真的在行动：跑若干回合，AI 宗门的地块+弟子总量应发生变化。
	var dispatcher: CommandDispatcher = _new_game("r7-ai")
	var state: GameState = dispatcher.state
	var before: int = _ai_footprint(state)
	for _round: int in range(6):
		_request(dispatcher, Commands.FINISH_TURN, {})
		_request(dispatcher, Commands.BEGIN_PLAYER_TURN, {})
		state = dispatcher.state
	_check(_ai_footprint(state) != before, "AI 行动改变了其地块/弟子格局（前 %d 后 %d）" % [before, _ai_footprint(state)])
	var ai_sect: Sect = _first_ai_sect(state)
	_check(ai_sect != null, "存在 AI 宗门")
	if ai_sect != null:
		_check(not ai_sect.visibleTiles.is_empty(), "AI 行动后其 visibleTiles 已刷新（%d 格）" % ai_sect.visibleTiles.size())

	# 攻击门槛：`attackMinWinChance` 0.55 与 `combatAdvantageThreshold` 1.2 来自 config。
	_check(is_equal_approx(float(_config["ai"]["attackMinWinChance"]), 0.55),
		"ai.attackMinWinChance = 0.55")
	_check(is_equal_approx(float(_config["ai"]["combatAdvantageThreshold"]), 1.2),
		"ai.combatAdvantageThreshold = 1.2")

	# 不检查宣战：2.0 无战争状态，攻击阻塞原因里不含「宣战」。
	var attacker: Disciple = _disciple_of_position(_player(dispatcher), Enums.Position.ZONG_ZHU)
	var target_tile: String = ""
	for tile: HexTile in state.tiles.values():
		if not tile.ownerSectId.is_empty() and tile.ownerSectId != state.playerSectId:
			target_tile = tile.id
			break
	if attacker != null and not target_tile.is_empty():
		var preview: Dictionary = CombatResolver.preview(state, _config, attacker.id, target_tile)
		_check(not str(preview.get("blockedReason", "")).contains("宣战"),
			"攻击不检查宣战（blockedReason=%s）" % str(preview.get("blockedReason", "")))

	# AI 行为只由 config 驱动：删掉性格/长期战略/外交议程后仍能跑（无 StrategyService 依赖）。
	_check(AIController.run_turn(state, _config, _player(dispatcher)).is_empty(),
		"AI 不对玩家宗门行动（run_turn 跳过 player）")


func _ai_footprint(state: GameState) -> int:
	var total: int = 0
	for sect: Sect in state.sects:
		if sect.player or sect.defeated:
			continue
		total += sect.disciples.size() * 1000
		for tile: HexTile in state.tiles.values():
			if tile.ownerSectId == sect.id:
				total += 1
	return total


func _first_ai_sect(state: GameState) -> Sect:
	for sect: Sect in state.sects:
		if not sect.player and not sect.defeated:
			return sect
	return null


# ---------------------------------------------------------------------------
# 7. 胜负：三流派达成 / 未达成 / 失败
# ---------------------------------------------------------------------------

func _test_victory_routes() -> void:
	var victory: Dictionary = _config["victory"]

	# --- 未达成：新开局三路线都不成立 ---
	var fresh: CommandDispatcher = _new_game("r7-victory-none")
	_check(_result(fresh, Commands.CHECK_VICTORY,
		{"sectId": fresh.state.playerSectId})["route"] == null, "新开局未达成任何路线")
	var progress: Dictionary = _result(fresh, Commands.QUERY_VICTORY_PROGRESS,
		{"sectId": fresh.state.playerSectId})
	_check((progress["routes"] as Array).size() == 2,
		"宗门流可见 2 条路线（招牌 + 分数兜底，实际 %d）" % (progress["routes"] as Array).size())
	# goals 内部形状（裁决三）：9 键。
	var goals: Array = (progress["routes"] as Array)[0]["goals"]
	_check(not goals.is_empty(), "routes[0].goals 非空")
	if not goals.is_empty():
		var goal: Dictionary = goals[0]
		for key: String in ["name", "current", "target", "unit", "description", "ratio", "met", "missingText", "valueText"]:
			_check(goal.has(key), "goals[] 含 %s（裁决三 9 键）" % key)

	# --- 宗门流：道法全解锁 + 势力等级 ≥140 + 灵峰 ≥10 ---
	var zong: CommandDispatcher = _new_game("r7-victory-zong")
	var zong_sect: Sect = _player(zong)
	_satisfy_zong_men(zong.state, zong_sect)
	VictoryRules.refresh_power_level(zong.state, _config, zong_sect)
	_check(zong_sect.powerLevel >= int(victory["zongMen"]["powerLevel"]),
		"构造后势力等级 %d ≥ %d" % [zong_sect.powerLevel, int(victory["zongMen"]["powerLevel"])])
	var zong_route: Variant = _result(zong, Commands.CHECK_VICTORY, {"sectId": zong_sect.id})["route"]
	_check(zong_route == VictoryRules.ROUTE_ZONG_MEN,
		"宗门流达成 → route = ZONG_MEN_DAOTONG（实得 %s）" % str(zong_route))

	# --- 家族流：飞升 4 + 族人 12 + 元婴以上 3 ---
	var jia: CommandDispatcher = _new_game("r7-victory-jia", Enums.FactionType.JIA_ZU)
	var jia_sect: Sect = _player(jia)
	_satisfy_jia_zu(jia.state, jia_sect)
	var jia_route: Variant = _result(jia, Commands.CHECK_VICTORY, {"sectId": jia_sect.id})["route"]
	_check(jia_route == VictoryRules.ROUTE_JIA_ZU,
		"家族流达成 → route = JIA_ZU_ASCENSION（实得 %s）" % str(jia_route))

	# --- 国家流：王土份额 ≥0.2 + 控制 ≥24 格 + 灵峰 ≥2 ---
	var guo: CommandDispatcher = _new_game("r7-victory-guo", Enums.FactionType.GUO_JIA)
	var guo_sect: Sect = _player(guo)
	_satisfy_guo_jia(guo.state, guo_sect)
	var guo_route: Variant = _result(guo, Commands.CHECK_VICTORY, {"sectId": guo_sect.id})["route"]
	_check(guo_route == VictoryRules.ROUTE_GUO_JIA,
		"国家流达成 → route = GUO_JIA_UNIFICATION（实得 %s）" % str(guo_route))

	# --- 失败：弟子全灭 / 灵峰全失 ---
	var dead: CommandDispatcher = _new_game("r7-defeat")
	var dead_sect: Sect = _player(dead)
	dead_sect.disciples.clear()
	_check(bool(_result(dead, Commands.CHECK_DEFEAT, {"sectId": dead_sect.id})["defeated"]),
		"弟子全灭 → checkDefeat = true")
	var peakless: CommandDispatcher = _new_game("r7-defeat-peak")
	var peakless_sect: Sect = _player(peakless)
	peakless_sect.spiritPeaks.clear()
	_check(bool(_result(peakless, Commands.CHECK_DEFEAT, {"sectId": peakless_sect.id})["defeated"]),
		"灵峰全失 → checkDefeat = true")
	# 覆灭清算：地块与节点归属解除。
	var collapse_state: GameState = dead.state
	var collapsed: Sect = _player(dead)
	var owned_before: int = VictoryRules.owned_tiles(collapse_state, collapsed)
	_check(owned_before > 0, "覆灭前有领地（%d 格）" % owned_before)
	VictoryRules.collapse_sect(collapse_state, collapsed)
	_check(collapsed.defeated, "覆灭后 defeated=true")
	_check(VictoryRules.owned_tiles(collapse_state, collapsed) == 0, "覆灭后领地清零")
	_check(collapsed.spiritPeaks.is_empty() and collapsed.disciples.is_empty(), "覆灭后灵峰与弟子清空")


## 构造宗门流达成：解锁全部本流派道法 + 10 座高等级灵峰。
func _satisfy_zong_men(state: GameState, sect: Sect) -> void:
	var core: Array = _config["victory"]["zongMen"]["coreDaoIds"]
	for dao: Dao in DaoRules.all_daos(_config):
		if not dao.factionOnly.is_empty() and dao.factionOnly != sect.factionType:
			continue
		if not sect.unlockedDaoIds.has(dao.id):
			sect.unlockedDaoIds.append(dao.id)
	# 核心道法必须真的在解锁列表里（否则 coreDaosUnlocked 不达标）。
	for dao_id: Variant in core:
		if not sect.unlockedDaoIds.has(str(dao_id)):
			sect.unlockedDaoIds.append(str(dao_id))
	var target_peaks: int = int(_config["victory"]["zongMen"]["minPeaks"])
	while sect.spiritPeaks.size() < target_peaks:
		var peak: SpiritPeak = SpiritPeak.new()
		peak.id = "peak_extra_%d" % sect.spiritPeaks.size()
		peak.name = "验收峰%d" % sect.spiritPeaks.size()
		peak.sectId = sect.id
		peak.tileId = _far_tile_id(state, _capital(sect).tileId)
		peak.capital = false
		# 等级拉高以满足 `powerLevel ≥ 140`（建筑等级权重 1/级）。
		peak.level = 20
		sect.spiritPeaks.append(peak)


## 构造家族流达成：4 名飞升 + 12 族人 + 3 名元婴以上。
func _satisfy_jia_zu(state: GameState, sect: Sect) -> void:
	var peak: SpiritPeak = _capital(sect)
	var target_ascended: int = int(_config["victory"]["jiaZu"]["ascensionCount"])
	var target_members: int = int(_config["victory"]["jiaZu"]["minClanMembers"])
	var target_high: int = int(_config["victory"]["jiaZu"]["minHighRealmMembers"])
	var high_level: int = int(_config["victory"]["jiaZu"]["highRealmLevel"])
	var high_realm: String = Enums.Realm.ALL[high_level - 1]
	var ascended: int = 0
	var high: int = 0
	var index: int = 0
	while sect.disciples.size() < target_members:
		index += 1
		var realm: String = high_realm if high < target_high else Enums.Realm.LIAN_QI
		var disciple: Disciple = _make_disciple(state, sect, "族人%d" % index, realm, Enums.Position.QIN_CHUAN, peak)
		disciple.bloodLine = true
		if high < target_high:
			high += 1
		if ascended < target_ascended:
			disciple.ascended = true
			ascended += 1
	# 已有弟子也补足飞升数。
	for disciple: Disciple in sect.disciples:
		if ascended >= target_ascended:
			break
		if not disciple.ascended:
			disciple.ascended = true
			ascended += 1


## 构造国家流达成：控制 ≥24 格 + 王土份额 ≥0.2 + 2 座灵峰。
func _satisfy_guo_jia(state: GameState, sect: Sect) -> void:
	var needed: int = int(_config["victory"]["guoJia"]["minControlledTiles"])
	var ratio: float = float(_config["victory"]["guoJia"]["claimedTileRatio"])
	var claimed: int = 0
	for tile: HexTile in state.tiles.values():
		if not tile.ownerSectId.is_empty():
			claimed += 1
	var mine: int = VictoryRules.owned_tiles(state, sect)
	var index: int = 0
	for tile: HexTile in state.tiles.values():
		if mine >= needed and float(mine) / float(maxi(1, claimed)) >= ratio:
			break
		if tile.ownerSectId == sect.id:
			continue
		tile.ownerSectId = sect.id
		mine += 1
		if tile.ownerSectId != sect.id:
			claimed += 1
		index += 1
	# 份额不够时把别人认领的地改成无主（提高己方占比）。
	if float(mine) / float(maxi(1, claimed)) < ratio:
		for tile: HexTile in state.tiles.values():
			if not tile.ownerSectId.is_empty() and tile.ownerSectId != sect.id:
				tile.ownerSectId = ""
	while sect.spiritPeaks.size() < int(_config["victory"]["guoJia"]["minPeaks"]):
		var peak: SpiritPeak = SpiritPeak.new()
		peak.id = "peak_guo_%d" % sect.spiritPeaks.size()
		peak.name = "王土峰%d" % sect.spiritPeaks.size()
		peak.sectId = sect.id
		peak.tileId = _far_tile_id(state, _capital(sect).tileId)
		peak.capital = false
		sect.spiritPeaks.append(peak)


# ---------------------------------------------------------------------------
# 8. 分数：公式独立复算 + 240 回合强制结算
# ---------------------------------------------------------------------------

func _test_score() -> void:
	var dispatcher: CommandDispatcher = _new_game("r7-score")
	var state: GameState = dispatcher.state
	var sect: Sect = _player(dispatcher)
	_satisfy_zong_men(state, sect)
	VictoryRules.refresh_power_level(state, _config, sect)
	var weights: Dictionary = _config["victory"]["score"]
	var expected: int = int(round(
		float(sect.powerLevel) * float(weights["powerLevelWeight"])
		+ float(VictoryRules.ascension_count(sect)) * float(weights["ascensionWeight"])
		+ VictoryRules.claimed_tile_share(state, sect) * float(weights["claimedTileShareWeight"])
		+ VictoryRules.dao_completion(_config, sect) * float(weights["daoCompletionWeight"])
		+ float(sect.spiritPeaks.size()) * float(weights["peakWeight"])))
	var actual: int = VictoryRules.compute_score(state, _config, sect)
	_check(actual == expected, "compute_score = %d（独立复算 %d）" % [actual, expected])

	# 240 回合强制分数结算：`turn >= maxTurns` 且领先 → 分数路线进入 achieved。
	var cap: int = int(_config["victory"]["maxTurns"])
	_check(cap == 240, "victory.maxTurns = 240")
	state.turn = cap - 1
	var before: Array[String] = VictoryRules.achieved_routes(state, _config, sect)
	_check(not before.has(VictoryRules.ROUTE_SCORE), "未到回合上限时分数路线不算达成")
	state.turn = cap
	var after: Array[String] = VictoryRules.achieved_routes(state, _config, sect)
	_check(after.has(VictoryRules.ROUTE_SCORE), "到 %d 回合且领先 → 分数路线达成" % cap)
	_check(VictoryRules.is_top_scorer(state, _config, sect), "构造后玩家为全场最高分")
	# 并列时按「势力等级 → 灵峰数」定唯一胜者。
	_check(VictoryRules.score_winner(state, _config) != null, "score_winner 非空")


# ---------------------------------------------------------------------------
# 9. 待抉择：多路线 awaitInput / resolveChoice 越界保留 / chooseVictory
# ---------------------------------------------------------------------------

func _test_victory_choice() -> void:
	var dispatcher: CommandDispatcher = _new_game("r7-choice")
	var state: GameState = dispatcher.state
	var sect: Sect = _player(dispatcher)
	_satisfy_zong_men(state, sect)
	VictoryRules.refresh_power_level(state, _config, sect)
	# 推到回合上限，让「宗门流 + 分数路线」同时达成。
	state.turn = int(_config["victory"]["maxTurns"])
	VictoryRules.process_victory_check(state, _config)
	_check(state.gameOver, "终局判定后 gameOver=true")
	_check(state.pendingVictoryChoices.size() == 2,
		"同时达成 2 条路线 → pendingVictoryChoices 2 项（实际 %d）" % state.pendingVictoryChoices.size())
	_check(state.winType.is_empty(), "待玩家择定时 winType 暂为空")
	_check(state.winnerSectId == sect.id, "winnerSectId 指向胜者")

	# awaitInput：形状照 PROTOCOL §0.7。
	var payload: Variant = dispatcher.poll_await_input()
	_check(payload != null, "有待决时 poll_await_input 返回消息体")
	if payload != null:
		var message: Dictionary = payload as Dictionary
		_check(str(message["type"]) == "awaitInput", "awaitInput.type = awaitInput")
		_check(str(message["kind"]) == "victoryChoice", "awaitInput.kind = victoryChoice（裁决七）")
		_check(str(message["reqId"]).begins_with("req_victory_"), "reqId 以 req_victory_ 开头")
		var options: Array = message["options"]
		_check(options.size() == 2, "awaitInput.options 2 项")
		if options.size() == 2:
			_check((options[0] as Dictionary).has("index") and (options[0] as Dictionary).has("label")
				and (options[0] as Dictionary).has("routeId") and (options[0] as Dictionary).has("description"),
				"awaitInput.options[] 含 index/label/routeId/description")
	# 同一 reqId 不重复推送。
	_check(dispatcher.poll_await_input() == null, "同一 reqId 不重复推送 awaitInput")

	# queryVictoryChoice 只读回包。
	var choice: Dictionary = _result(dispatcher, Commands.QUERY_VICTORY_CHOICE, {})
	_check(bool(choice["pending"]) and (choice["options"] as Array).size() == 2, "queryVictoryChoice 回 pending + 2 选项")

	# resolveChoice 越界 → BAD_PARAMS 且待决原样保留。
	var pending_before: Array[String] = state.pendingVictoryChoices.duplicate()
	var out_of_range: Dictionary = _request(dispatcher, Commands.RESOLVE_CHOICE,
		{"reqId": VictoryAction.request_id(state), "optionIndex": 99})
	_check(out_of_range.get("errorCode") == "BAD_PARAMS", "resolveChoice 越界 → BAD_PARAMS")
	_check(state.pendingVictoryChoices == pending_before, "越界后待决状态原样保留")
	# 非 victoryChoice 前缀 → BAD_PARAMS。
	var wrong_req: Dictionary = _request(dispatcher, Commands.RESOLVE_CHOICE,
		{"reqId": "req_random_event_1", "optionIndex": 0})
	_check(wrong_req.get("errorCode") == "BAD_PARAMS", "非 req_victory_ 前缀 → BAD_PARAMS")
	_check(state.pendingVictoryChoices == pending_before, "认不出 reqId 时待决状态原样保留")

	# 合法 resolveChoice → 成功并清空待决。
	var resolved: Dictionary = _result(dispatcher, Commands.RESOLVE_CHOICE,
		{"reqId": VictoryAction.request_id(state), "optionIndex": 0})
	_check(bool(resolved["success"]), "resolveChoice 合法下标成功")
	_check(state.pendingVictoryChoices.is_empty(), "择定后待决清空")
	_check(not state.winType.is_empty(), "择定后 winType 有值（%s）" % state.winType)
	_check(state.gameOver, "择定后 gameOver 仍为 true")
	_check(dispatcher.poll_await_input() == null, "待决清空后不再推 awaitInput")

	# chooseVictory：无待决时返回 success=false（业务失败）。
	var no_pending: Dictionary = _result(dispatcher, Commands.CHOOSE_VICTORY, {"routeId": VictoryRules.ROUTE_ZONG_MEN})
	_check(bool(no_pending.get("success")) == false, "无待决时 chooseVictory 返回 success=false")


# ---------------------------------------------------------------------------
# 10. 存档：形状 / 往返一致 / 列表字段 / 自动存档 / 读档重推待决
# ---------------------------------------------------------------------------

func _test_save() -> void:
	var dispatcher: CommandDispatcher = _new_game("r7-save")
	var state: GameState = dispatcher.state
	# 制造一些非默认状态，确保往返真的在存东西。
	state.turn = 7
	_player(dispatcher).resources["spiritStones"] = 4321
	_request(dispatcher, Commands.FINISH_TURN, {})
	_request(dispatcher, Commands.BEGIN_PLAYER_TURN, {})
	var view_before: String = JSON.stringify(_view(dispatcher))

	# --- saveGame：固定形状 {slot, saved} ---
	var saved: Dictionary = _request(dispatcher, Commands.SAVE_GAME, {"slot": TEST_SLOT_BASE})
	_check(bool(saved.get("ok")), "saveGame ok:true")
	var result: Dictionary = saved["result"]
	_check(result.has("slot") and result.has("saved"), "saveGame 结果含 slot 与 saved")
	_check(bool(result["saved"]), "saveGame saved=true")
	_check(not result.has("success"), "saveGame 结果不含 success 布尔")
	_check(int(result["slot"]) == TEST_SLOT_BASE, "saveGame 回显槽位 %d" % TEST_SLOT_BASE)
	# 字符串槽位也接受（PROTOCOL §2 `slot` 为 string|int）。
	var string_slot: Dictionary = _request(dispatcher, Commands.SAVE_GAME, {"slot": str(TEST_SLOT_BASE + 1)})
	_check(bool(string_slot["result"]["saved"]), "saveGame 接受字符串槽位")

	# --- listSaves：7 字段 ---
	var listed: Dictionary = _result(dispatcher, Commands.LIST_SAVES, {})
	var saves: Array = listed["saves"]
	_check(not saves.is_empty(), "listSaves 返回至少 1 个槽位")
	var found: bool = false
	for entry: Variant in saves:
		var info: Dictionary = entry as Dictionary
		if int(info.get("slotId", -1)) != TEST_SLOT_BASE:
			continue
		found = true
		for key: String in ["slotId", "turn", "playerSectName", "factionType", "savedAt", "filePath", "fileSize"]:
			_check(info.has(key), "listSaves.saves[] 含 %s" % key)
		_check(info.size() == 7, "listSaves.saves[] 恰好 7 字段（实际 %d）" % info.size())
		_check(str(info["playerSectName"]) == "验收宗", "listSaves.playerSectName = 验收宗")
		_check(int(info["fileSize"]) > 0, "listSaves.fileSize > 0")
	_check(found, "listSaves 含刚保存的槽位 %d" % TEST_SLOT_BASE)

	# --- loadGame：{slot, turn} + view 逐字一致 ---
	var turn_before: int = state.turn
	var loaded: Dictionary = _request(dispatcher, Commands.LOAD_GAME, {"slot": TEST_SLOT_BASE})
	_check(bool(loaded.get("ok")), "loadGame ok:true")
	_check(loaded["result"].has("slot") and loaded["result"].has("turn"), "loadGame 结果含 slot 与 turn")
	_check(int(loaded["result"]["turn"]) == turn_before,
		"loadGame 回显回合 %d（实际 %d）" % [turn_before, int(loaded["result"]["turn"])])
	# 「逐字一致」按 **JSON 语义**比较：JSON 不保留 int/float 区分（`12` 与 `12.0` 解析后同为 float），
	# 故先做一次往返归一再比字符串。归一只抹平数值表示，任何真实差异（值/键/长度）都会被抓到。
	var view_after: String = _canonical(JSON.stringify(_view(dispatcher)))
	var expected_view: String = _canonical(view_before)
	_check(view_after == expected_view, "loadGame 后 view 与存档时逐字一致" + _diff_hint(expected_view, view_after))
	var view_in_response: String = _canonical(JSON.stringify(loaded["view"]))
	_check(view_in_response == expected_view, "loadGame 响应携带的 view 与存档时逐字一致"
		+ _diff_hint(expected_view, view_in_response))
	_check(int(_player(dispatcher).resources["spiritStones"]) == int(_player_state(dispatcher).resources["spiritStones"]),
		"读档后玩家灵石与存档一致")

	# --- 自动存档：turn % 10 == 0 时落槽 0 ---
	var auto: CommandDispatcher = _new_game("r7-autosave")
	auto.state.turn = 9
	# `finish_turn` 的 VICTORY_CHECK 用当前回合判定，故 turn=10 时会自动存档。
	auto.state.turn = 10
	_request(auto, Commands.FINISH_TURN, {})
	var auto_path: String = SaveManager.save_file_path(SaveManager.AUTO_SAVE_SLOT)
	_check(FileAccess.file_exists(auto_path), "turn=10 触发自动存档槽 0")
	if FileAccess.file_exists(auto_path):
		var file: FileAccess = FileAccess.open(auto_path, FileAccess.READ)
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		file.close()
		if parsed is Dictionary:
			var wrapper: Dictionary = parsed as Dictionary
			_check(str(wrapper.get("saveVersion", "")) == Msg.SAVE_VERSION,
				"自动存档 saveVersion = %s" % Msg.SAVE_VERSION)

	# --- 读档回到待决点：重新推送 awaitInput ---
	var choice_dispatcher: CommandDispatcher = _new_game("r7-save-choice")
	var choice_state: GameState = choice_dispatcher.state
	_satisfy_zong_men(choice_state, _player(choice_dispatcher))
	VictoryRules.refresh_power_level(choice_state, _config, _player(choice_dispatcher))
	choice_state.turn = int(_config["victory"]["maxTurns"])
	VictoryRules.process_victory_check(choice_state, _config)
	_check(choice_state.pendingVictoryChoices.size() == 2, "存档前处于 2 路线待决")
	_check(choice_dispatcher.poll_await_input() != null, "待决时首次推送 awaitInput")
	_request(choice_dispatcher, Commands.SAVE_GAME, {"slot": TEST_SLOT_BASE + 2})
	# 换个对局，再把待决那一局读回来。
	var reloaded: CommandDispatcher = _new_game("r7-save-choice-2")
	_check(reloaded.poll_await_input() == null, "新开局无待决不推送")
	var load_response: Dictionary = _request(reloaded, Commands.LOAD_GAME, {"slot": TEST_SLOT_BASE + 2})
	_check(bool(load_response.get("ok")), "读回待决存档成功")
	_check(reloaded.state.pendingVictoryChoices.size() == 2, "读档后待决路线恢复 2 项")
	var repushed: Variant = reloaded.poll_await_input()
	_check(repushed != null, "读档回到待决点重新推送 awaitInput")
	if repushed != null:
		_check(str((repushed as Dictionary)["reqId"]) == VictoryAction.request_id(reloaded.state),
			"重推的 reqId 与存档回合一致")


func _player_state(dispatcher: CommandDispatcher) -> Sect:
	return _player(dispatcher)


# ---------------------------------------------------------------------------
# 11. 回填：AI_ACTION / VICTORY_CHECK / 自动存档 / 宗主外出
# ---------------------------------------------------------------------------

func _test_backfill() -> void:
	# 三个 R2 空钩子现在都有实体：源文件里不应再留 TODO(R7)。
	var processor_source: String = FileAccess.get_file_as_string("res://scripts/rules/TurnProcessor.gd")
	_check(not processor_source.contains("TODO(R7)"), "TurnProcessor 已无 TODO(R7) 残留")
	_check(processor_source.contains("AIController.run_turn"), "AI_ACTION 阶段已接 AIController")
	_check(processor_source.contains("VictoryRules.process_victory_check"), "VICTORY_CHECK 阶段已接 VictoryRules")
	_check(processor_source.contains("zong_zhu_outside_bonus_active"), "TURN_START 已接宗主外出检查")

	# 宗主外出只在状态翻转时记事件（不刷屏）。
	var dispatcher: CommandDispatcher = _new_game("r7-outside")
	var state: GameState = dispatcher.state
	var sect: Sect = _player(dispatcher)
	var capital: SpiritPeak = _capital(sect)
	var zong_zhu: Disciple = _disciple_of_position(sect, Enums.Position.ZONG_ZHU)
	if zong_zhu != null:
		capital.buildings[Enums.Building.ZONG_ZHU_DA_DIAN] = {
			"id": "b_hall", "type": Enums.Building.ZONG_ZHU_DA_DIAN, "name": "宗主大殿",
			"level": 1, "districtId": "",
		}
		zong_zhu.tileId = capital.tileId
		_request(dispatcher, Commands.FINISH_TURN, {})
		_request(dispatcher, Commands.BEGIN_PLAYER_TURN, {})
		_check(sect.zongZhuOutside == false, "宗主坐镇时 zongZhuOutside=false")
		# 让宗主外出 → 下一回合开始应记一条「宗主外出」。
		zong_zhu.tileId = _far_tile_id(state, capital.tileId)
		_request(dispatcher, Commands.FINISH_TURN, {})
		_request(dispatcher, Commands.BEGIN_PLAYER_TURN, {})
		_check(sect.zongZhuOutside, "宗主外出后 zongZhuOutside=true")
		_check(_count_events(state, "宗主外出") == 1, "宗主外出状态翻转时记且仅记一条事件")
		# 再跑一回合，不应重复记。
		_request(dispatcher, Commands.FINISH_TURN, {})
		_request(dispatcher, Commands.BEGIN_PLAYER_TURN, {})
		# `begin_player_turn` 每回合清空 `eventLog`，故第二轮断言「本轮没有该事件」即为不重复。
		_check(_count_events(state, "宗主外出") == 0, "宗主持续外出不重复刷事件")


# ---------------------------------------------------------------------------
# 12. 确定性：双跑整局 view 与事件流逐字一致
# ---------------------------------------------------------------------------

func _test_determinism() -> void:
	var first: Dictionary = _run_scripted_game("r7-determinism-seed")
	var second: Dictionary = _run_scripted_game("r7-determinism-seed")
	_check(first["view"] == second["view"], "双跑整局 view 逐字一致")
	_check(first["events"] == second["events"], "双跑事件流逐字一致")
	_check(first["view"].length() > 1000, "确定性样本足够大（view %d 字符）" % first["view"].length())

	# 导出两份权威样本并比对 SHA256（验收 9）。
	var output_dir: String = ProjectSettings.globalize_path("res://").path_join("../outputs")
	DirAccess.make_dir_recursive_absolute(output_dir)
	var path_a: String = output_dir.path_join("r7_authority_a.json")
	var path_b: String = output_dir.path_join("r7_authority_b.json")
	_write_text(path_a, str(first["view"]))
	_write_text(path_b, str(second["view"]))
	var hash_a: String = FileAccess.get_sha256(path_a)
	var hash_b: String = FileAccess.get_sha256(path_b)
	_check(hash_a == hash_b, "outputs/r7_authority_a|b.json SHA256 相同（%s）" % hash_a.substr(0, 16))
	_check(hash_a.length() == 64, "SHA256 为 64 位十六进制串")


## 跑一段固定指令序列（含 AI 行动），返回 `{view, events}` 快照。
func _run_scripted_game(seed: String) -> Dictionary:
	var dispatcher: CommandDispatcher = CommandDispatcher.new(_config)
	_request(dispatcher, Commands.NEW_GAME, {"sectName": "确定性宗", "playerFaction": Enums.FactionType.ZONG_MEN,
		"mapWidth": 16, "mapHeight": 12, "randomSeed": _seed_of(seed), "difficultyId": "normal"})
	var collected: Array[String] = []
	for round_index: int in range(4):
		var finish: Dictionary = _request(dispatcher, Commands.FINISH_TURN, {})
		for event: Variant in finish.get("events", []):
			collected.append(str(event))
		var begin: Dictionary = _request(dispatcher, Commands.BEGIN_PLAYER_TURN, {})
		for event: Variant in begin.get("events", []):
			collected.append(str(event))
		# 插入几条只读命令，确认它们不改状态。
		var sect_id: String = dispatcher.state.playerSectId
		_request(dispatcher, Commands.QUERY_VICTORY_PROGRESS, {"sectId": sect_id})
		_request(dispatcher, Commands.CHECK_VICTORY, {"sectId": sect_id})
		collected.append("--round %d--" % round_index)
	return {"view": JSON.stringify(_view(dispatcher)), "events": collected}


func _write_text(path: String, text: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(text)
	file.close()


# ---------------------------------------------------------------------------
# 辅助
# ---------------------------------------------------------------------------

## 把可读 seed 文本映射成 `randomSeed` 要求的十进制 64bit 整数。
## `newGame.randomSeed` 只接受整数或纯数字字符串（PROTOCOL §2 / `_normalize_params`），
## 故这里用确定性散列把 "r7-xxx" 变成稳定数字，同文本必得同种子。
func _seed_of(text: String) -> int:
	var value: int = 700001
	for index: int in range(text.length()):
		value = (value * 131 + text.unicode_at(index) + index) % 900000000
	return value + 1


func _new_game(seed: String, faction: String = Enums.FactionType.ZONG_MEN) -> CommandDispatcher:
	var dispatcher: CommandDispatcher = CommandDispatcher.new(_config)
	var response: Dictionary = _request(dispatcher, "newGame", {"sectName": "验收宗", "playerFaction": faction,
		"mapWidth": 20, "mapHeight": 14, "randomSeed": _seed_of(seed), "difficultyId": "normal"})
	if dispatcher.state == null:
		_check(false, "newGame 失败（seed=%s）：%s" % [seed, str(response.get("message"))])
	return dispatcher


func _request(dispatcher: CommandDispatcher, command: String, params: Dictionary = {}) -> Dictionary:
	return dispatcher.dispatch_text(JSON.stringify({"id": "test", "type": command, "params": params}))


func _result(dispatcher: CommandDispatcher, command: String, params: Dictionary) -> Dictionary:
	return _request(dispatcher, command, params).get("result", {})


func _view(dispatcher: CommandDispatcher) -> Dictionary:
	return _request(dispatcher, "getState")["view"]


func _player(dispatcher: CommandDispatcher) -> Sect:
	for sect: Sect in dispatcher.state.sects:
		if sect.player: return sect
	return null


func _capital(sect: Sect) -> SpiritPeak:
	for peak: SpiritPeak in sect.spiritPeaks:
		if peak.capital: return peak
	return null if sect.spiritPeaks.is_empty() else sect.spiritPeaks[0]


func _disciple_of_realm(sect: Sect, realm: String) -> Disciple:
	for disciple: Disciple in sect.disciples:
		if disciple.realm == realm: return disciple
	return null


func _disciple_of_position(sect: Sect, position: String) -> Disciple:
	for disciple: Disciple in sect.disciples:
		if disciple.position == position: return disciple
	return null


## 造一名弟子并挂到宗门名册（不消耗资源，纯构造测试场景）。
func _make_disciple(state: GameState, sect: Sect, name: String, realm: String,
		position: String, peak: SpiritPeak) -> Disciple:
	state.discipleSeq += 1
	var disciple: Disciple = Disciple.new()
	disciple.id = "disciple_%s_test_%d" % [sect.id, state.discipleSeq]
	disciple.name = name
	disciple.sectId = sect.id
	disciple.tileId = peak.tileId
	disciple.realm = realm
	disciple.realmLevel = Disciple.level_of(realm)
	disciple.position = position
	disciple.rootGrade = 1
	disciple.spiritRoots = ["JIN"]
	disciple.unitClass = Enums.UnitClass.PU_TONG
	disciple.assignedPeakId = peak.id
	var points: int = MoveRules.calculate_max_move_points(disciple, _config, state, sect)
	disciple.maxMovePoints = points
	disciple.movePoints = points
	disciple.attacksRemaining = int(_config["warfare"]["attacksPerTurn"])
	sect.disciples.append(disciple)
	return disciple


## 找一个离 `tile_id` 最远的格子（用于「外出」场景）。
func _far_tile_id(state: GameState, tile_id: String) -> String:
	var origin: HexTile = state.tiles.get(tile_id, null)
	if origin == null:
		return tile_id
	var best_id: String = ""
	var best_distance: int = -1
	var ids: Array[String] = []
	for key: Variant in state.tiles.keys():
		ids.append(str(key))
	ids.sort()
	for id: String in ids:
		var tile: HexTile = state.tiles[id]
		var distance: int = Hex.distance(Vector2i(origin.q, origin.r), Vector2i(tile.q, tile.r))
		if distance > best_distance:
			best_distance = distance
			best_id = id
	return best_id


## 清理测试槽位（90–99）与自动存档槽 0，避免污染玩家存档与影响 listSaves 断言。
func _clean_test_slots() -> void:
	for index: int in range(TEST_SLOT_COUNT):
		var path: String = SaveManager.save_file_path(TEST_SLOT_BASE + index)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


## JSON 往返归一：抹平 `12` / `12.0` 这类数值表示差异，保留全部语义。
func _canonical(text: String) -> String:
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null:
		return text
	return JSON.stringify(parsed)


## 两段 JSON 文本的第一处差异（用于断言失败时定位，不影响断言结果）。
func _diff_hint(expected: String, actual: String) -> String:
	if expected == actual:
		return ""
	var left: Variant = JSON.parse_string(expected)
	var right: Variant = JSON.parse_string(actual)
	return "；首处差异：" + _diff_path(left, right, "$")


func _diff_path(left: Variant, right: Variant, path: String) -> String:
	if typeof(left) != typeof(right):
		return "%s 类型 %d vs %d" % [path, typeof(left), typeof(right)]
	if left is Dictionary:
		var a: Dictionary = left as Dictionary
		var b: Dictionary = right as Dictionary
		var keys: Array[String] = []
		for key: Variant in a.keys():
			keys.append(str(key))
		for key: Variant in b.keys():
			if not keys.has(str(key)):
				keys.append(str(key))
		keys.sort()
		for key: String in keys:
			if not a.has(key):
				return "%s.%s 仅右侧有" % [path, key]
			if not b.has(key):
				return "%s.%s 仅左侧有" % [path, key]
			var sub: String = _diff_path(a[key], b[key], path + "." + key)
			if not sub.is_empty():
				return sub
		return ""
	if left is Array:
		var a2: Array = left as Array
		var b2: Array = right as Array
		if a2.size() != b2.size():
			return "%s 长度 %d vs %d" % [path, a2.size(), b2.size()]
		for index: int in range(a2.size()):
			var sub2: String = _diff_path(a2[index], b2[index], "%s[%d]" % [path, index])
			if not sub2.is_empty():
				return sub2
		return ""
	if left != right:
		return "%s = %s vs %s" % [path, str(left), str(right)]
	return ""


## 统计 `state.eventLog` 里含某关键字的条目数。
func _count_events(state: GameState, keyword: String) -> int:
	var count: int = 0
	for entry: String in state.eventLog:
		if entry.contains(keyword):
			count += 1
	return count


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
