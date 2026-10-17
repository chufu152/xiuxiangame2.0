extends Node
## R4 自动验收：道统科技树（21 道法）+ 修炼/突破/渡劫 + 项目/研究队列 + 收徒。
##
## 无头运行：`godot --headless --path server res://tests/R4Test.tscn`，
## 全绿打印 `R4_PASS checks=N` 并退出码 0，否则 `R4_FAIL ...` 退出码 1。
##
## 断言尽量**独立复算**（不直接用被测函数的返回值当期望值）；
## 需要「已解锁某道法」作为前置时，直接写入 `sect.unlockedDaoIds`（规则单元验证），
## 真正的研究链路另由 `_test_research_queue` 走 `researchDao` + `nextTurn` 全链路验证。

const R4_COMMANDS: Array[String] = [
	Commands.RESEARCH_DAO, Commands.HOLD_RECRUITMENT, Commands.QUERY_PROJECT_QUEUE,
	Commands.CANCEL_PROJECT, Commands.ACCELERATE_PROJECT,
]

var _failures: Array[String] = []
var _checks: int = 0
var _config: Dictionary = {}
var _finished: bool = false
var _started: int = Time.get_ticks_msec()


func _process(_delta: float) -> void:
	if not _finished and Time.get_ticks_msec() - _started > 240000:
		printerr("R4_FAIL 测试未正常完成（可能运行时脚本错误）")
		get_tree().quit(1)


func _ready() -> void:
	var loaded: Dictionary = ConfigLoader.load_from_file(ConfigLoader.default_path())
	_check(bool(loaded["ok"]), "配置可加载")
	_config = loaded["config"]
	_check(ConfigValidator.validate(_config).is_empty(), "配置通过深层验证")
	_test_registration()
	_test_dao_tree()
	_test_gating()
	_test_research_queue()
	_test_cancel_accelerate()
	_test_recruitment()
	_test_cultivation_breakthrough()
	_test_tribulation()
	_test_move_and_vision_bonus()
	_test_boosts()
	_test_determinism()
	_finished = true
	if _failures.is_empty():
		print("R4_PASS checks=%d" % _checks)
		get_tree().quit(0)
	else:
		for failure: String in _failures:
			printerr("R4_FAIL " + failure)
		printerr("R4_FAIL checks=%d failures=%d" % [_checks, _failures.size()])
		get_tree().quit(1)


# ---------------------------------------------------------------------------
# 1. 命令注册
# ---------------------------------------------------------------------------

func _test_registration() -> void:
	var dispatcher: CommandDispatcher = CommandDispatcher.new(_config)
	var implemented: Array = dispatcher.implemented_commands()
	for command: String in R4_COMMANDS:
		_check(implemented.has(command), "已登记 R4 命令：" + command)
	_check(implemented.size() >= 28, "已登记命令不少于 R4 的 28 条（ping + 7 + 15 + 5）")
	_check(not implemented.has("tribulate"), "tribulate 未登记命令（归 R7，裁决六）")
	for command: String in R4_COMMANDS:
		var response: Dictionary = _request(dispatcher, command, {})
		_check(response.get("errorCode") == "NO_GAME", "%s 开局前 NO_GAME" % command)


# ---------------------------------------------------------------------------
# 2. 道法树完整性
# ---------------------------------------------------------------------------

func _test_dao_tree() -> void:
	var daos: Array[Dao] = DaoRules.all_daos(_config)
	_check(daos.size() == 21, "道法共 21 条")
	var eras: Array = _config["daoTree"]["eras"]
	_check(eras.size() == 5, "时代共 5 个")
	var counts: Dictionary = {}
	for dao: Dao in daos:
		counts[dao.era] = int(counts.get(dao.era, 0)) + 1
	var expected: Array[int] = [3, 4, 7, 4, 3]
	for index: int in range(eras.size()):
		_check(int(counts.get(str(eras[index]), 0)) == expected[index], "时代「%s」道法数 == %d" % [str(eras[index]), expected[index]])

	# 前置链：全部指向存在的 id，且不成环
	var ids: Dictionary = {}
	for dao: Dao in daos:
		ids[dao.id] = true
	var dangling: int = 0
	for dao: Dao in daos:
		for prerequisite: String in dao.prerequisiteDaoIds:
			if not ids.has(prerequisite):
				dangling += 1
	_check(dangling == 0, "前置道法引用全部存在")
	var cyclic: int = 0
	for dao: Dao in daos:
		if _reaches_self(dao.id, ids, daos):
			cyclic += 1
	_check(cyclic == 0, "前置链无环")

	# 4 条流派专属 + 血脉标记
	var faction_only: Dictionary = {}
	var bloodline: Dictionary = {}
	for dao: Dao in daos:
		if not dao.factionOnly.is_empty():
			faction_only[dao.id] = dao.factionOnly
		if dao.requiresBloodLine:
			bloodline[dao.id] = true
	_check(faction_only.size() == 4, "流派专属道法 4 条")
	_check(str(faction_only.get("hu_shan_jian_zhen", "")) == Enums.FactionType.ZONG_MEN, "hu_shan_jian_zhen 归宗门流")
	_check(str(faction_only.get("xue_mai_jue_xing", "")) == Enums.FactionType.JIA_ZU, "xue_mai_jue_xing 归家族流")
	_check(str(faction_only.get("zu_xian_bi_you", "")) == Enums.FactionType.JIA_ZU, "zu_xian_bi_you 归家族流")
	_check(str(faction_only.get("di_wang_zhu_shu", "")) == Enums.FactionType.GUO_JIA, "di_wang_zhu_shu 归国家流")
	_check(bloodline.size() == 2 and bloodline.has("xue_mai_jue_xing") and bloodline.has("zu_xian_bi_you"), "requiresBloodLine 恰为两条血脉道法")

	# 核心道法前置链
	var hun_yuan: Dao = DaoRules.find_dao(_config, "hun_yuan")
	_check(hun_yuan != null and _same_strings(hun_yuan.prerequisiteDaoIds, ["ti_xiu", "tian_ji"]), "hun_yuan 前置 == ti_xiu + tian_ji")
	var fei_sheng: Dao = DaoRules.find_dao(_config, "fei_sheng")
	_check(fei_sheng != null and _same_strings(fei_sheng.prerequisiteDaoIds, ["hun_yuan"]), "fei_sheng 前置 == hun_yuan")


## `dao_id` 沿前置链能否回到自身。
func _reaches_self(dao_id: String, ids: Dictionary, daos: Array[Dao]) -> bool:
	var stack: Array[String] = [dao_id]
	var seen: Dictionary = {}
	while not stack.is_empty():
		var current: String = stack.pop_back()
		if seen.has(current):
			continue
		seen[current] = true
		var dao: Dao = _dao_by_id(daos, current)
		if dao == null:
			continue
		for prerequisite: String in dao.prerequisiteDaoIds:
			if prerequisite == dao_id:
				return true
			if ids.has(prerequisite):
				stack.append(prerequisite)
	return false


func _dao_by_id(daos: Array[Dao], dao_id: String) -> Dao:
	for dao: Dao in daos:
		if dao.id == dao_id:
			return dao
	return null


# ---------------------------------------------------------------------------
# 3. 门控
# ---------------------------------------------------------------------------

func _test_gating() -> void:
	var dispatcher: CommandDispatcher = _new_game("400001")
	var state: GameState = dispatcher.state
	var sect: Sect = state.sects[0]
	sect.resources["daoPoints"] = 0
	sect.resources["workPower"] = 1000

	# 道点不足
	var low: Dictionary = _result(dispatcher, "researchDao", {"sectId": sect.id, "daoId": "tu_na"})
	_check(not bool(low.get("success", true)), "道点不足 → success=false")
	_check(str(low.get("message", "")).contains("道点不足"), "道点不足 blocker 文案正确")

	sect.resources["daoPoints"] = 1000
	_check(str(DaoRules.dao_state(state, _config, sect, "tu_na")["state"]) == "AVAILABLE", "资源充足时 tu_na 状态 == AVAILABLE")
	_check(str(DaoRules.dao_state(state, _config, sect, "cang_shu")["state"]) == "BLOCKED", "前置/时代不足时 cang_shu 状态 == BLOCKED")

	# 前置未解锁
	var prereq: Dictionary = _result(dispatcher, "researchDao", {"sectId": sect.id, "daoId": "jian_xiu"})
	_check(not bool(prereq.get("success", true)), "前置未解锁 → success=false")
	_check(str(prereq.get("message", "")).contains("前置道法未推演"), "前置 blocker 文案正确")

	# 时代未到（金丹篇需先推演一条筑基篇道法：宗门时代 = 已解锁最高时代，可超前 1 代）
	sect.unlockedDaoIds.append("tu_na")
	sect.unlockedDaoIds.append("dan_yao_chu")
	var era: Dictionary = _result(dispatcher, "researchDao", {"sectId": sect.id, "daoId": "cang_shu"})
	_check(not bool(era.get("success", true)), "时代未到 → success=false")
	_check(str(era.get("message", "")).contains("时代未到"), "时代 blocker 文案正确")
	_check(DaoRules.sect_era_index(state, _config, sect) == 0, "未解锁道法时宗门时代 == 炼气篇")

	# 流派不符（宗门时代推进到筑基篇后，金丹篇家族道法被流派拦下）
	sect.unlockedDaoIds.append("jian_xiu")
	_check(DaoRules.sect_era_index(state, _config, sect) == 1, "解锁筑基篇道法后宗门时代 == 筑基篇")
	var faction: Dictionary = _result(dispatcher, "researchDao", {"sectId": sect.id, "daoId": "xue_mai_jue_xing"})
	_check(not bool(faction.get("success", true)), "流派不符 → success=false")
	_check(str(faction.get("message", "")).contains("专属道法"), "流派 blocker 文案正确")

	# 血脉要求：家族流但族内无血脉修士
	var family: CommandDispatcher = _new_game_faction("400002", Enums.FactionType.JIA_ZU)
	var family_sect: Sect = family.state.sects[0]
	family_sect.resources["daoPoints"] = 1000
	family_sect.resources["workPower"] = 1000
	family_sect.unlockedDaoIds.append("tu_na")
	family_sect.unlockedDaoIds.append("jian_xiu")
	for disciple: Disciple in family_sect.disciples:
		disciple.bloodLine = false
	var blood: Dictionary = _result(family, "researchDao", {"sectId": family_sect.id, "daoId": "xue_mai_jue_xing"})
	_check(not bool(blood.get("success", true)), "requiresBloodLine 不符 → success=false")
	_check(str(blood.get("message", "")).contains("血脉"), "血脉 blocker 文案正确")
	for disciple: Disciple in family_sect.disciples:
		disciple.bloodLine = true
	var blood_ok: Dictionary = _result(family, "researchDao", {"sectId": family_sect.id, "daoId": "xue_mai_jue_xing"})
	_check(bool(blood_ok.get("success", false)), "血脉修士在族 → 可推演血脉道法")

	# 血脉道法费用折扣（jiaZu.bloodDaoCostReduction）
	var xue_mai: Dao = DaoRules.find_dao(_config, "xue_mai_jue_xing")
	var expected_cost: int = int(round(float(xue_mai.daoPointCost) * (1.0 - float(_config["faction"]["jiaZu"]["bloodDaoCostReduction"]))))
	_check(int(blood_ok.get("turnsRequired", -1)) == DaoRules.research_turns(_config, family_sect, xue_mai), "血脉道法工期按研究加速公式")
	_check(DaoRules.dao_point_cost(_config, xue_mai) == expected_cost, "血脉道法道点折扣 == %d" % expected_cost)

	# 工力为 0 → 无法开工
	sect.resources["workPower"] = 0
	var no_work: Dictionary = _result(dispatcher, "researchDao", {"sectId": sect.id, "daoId": "ling_tian_nong"})
	_check(not bool(no_work.get("success", true)), "工力为 0 → success=false")
	_check(str(no_work.get("message", "")).contains("工力不足"), "工力 blocker 文案正确")
	sect.resources["workPower"] = 1000

	# 非己方宗门 → BAD_PARAMS
	var foreign: Dictionary = _request(dispatcher, "researchDao", {"sectId": state.sects[1].id, "daoId": "tu_na"})
	_check(str(foreign.get("errorCode", "")) == "BAD_PARAMS", "非己方宗门 researchDao → BAD_PARAMS")
	# 缺 daoId → BAD_PARAMS
	var missing: Dictionary = _request(dispatcher, "researchDao", {"sectId": sect.id})
	_check(str(missing.get("errorCode", "")) == "BAD_PARAMS", "缺 daoId → BAD_PARAMS")
	# 不存在的道法 → 业务失败
	var unknown: Dictionary = _result(dispatcher, "researchDao", {"sectId": sect.id, "daoId": "no_such_dao"})
	_check(not bool(unknown.get("success", true)), "不存在的道法 → success=false")


# ---------------------------------------------------------------------------
# 4. 研究队列推进
# ---------------------------------------------------------------------------

func _test_research_queue() -> void:
	var dispatcher: CommandDispatcher = _new_game("400003")
	var state: GameState = dispatcher.state
	var sect: Sect = state.sects[0]
	var peak: SpiritPeak = _capital(sect)
	_grant(sect)

	var dao: Dao = DaoRules.find_dao(_config, "tu_na")
	var expected_turns: int = DaoRules.research_turns(_config, sect, dao)
	var expected_points: int = DaoRules.dao_point_cost(_config, dao)
	var expected_work: int = DaoRules.work_cost(_config, dao)
	var points_before: int = int(sect.resources.get("daoPoints", 0))
	var result: Dictionary = _result(dispatcher, "researchDao", {"sectId": sect.id, "daoId": "tu_na"})
	_check(bool(result.get("success", false)), "researchDao 入队成功")
	_check(int(result.get("turnsRequired", -1)) == expected_turns, "researchDao turnsRequired == %d" % expected_turns)
	_check(int(result.get("spiritPowerCost", -1)) == expected_work, "researchDao spiritPowerCost（工力总额）== %d" % expected_work)
	_check(int(sect.resources.get("daoPoints", 0)) == points_before - expected_points, "入队即扣道点 %d" % expected_points)
	_check(sect.researchQueue.size() == 1, "研究队列 1 项")

	# queryProjectQueue：两池分列、不混池、只读不返 view
	var queue_response: Dictionary = _request(dispatcher, "queryProjectQueue", {"peakId": peak.id})
	_check(queue_response.get("view") == null, "queryProjectQueue 不返 view（只读）")
	var queue: Dictionary = queue_response.get("result", {})
	_check(bool(queue.get("found", false)), "queryProjectQueue found=true")
	_check(str(queue.get("peakName", "")) == peak.name, "queryProjectQueue peakName 正确")
	_check((queue.get("projects", []) as Array).is_empty(), "projects[] 为空（建造池独立）")
	_check((queue.get("researchQueue", []) as Array).size() == 1, "researchQueue[] 有 1 项")
	var entry: Dictionary = (queue["researchQueue"] as Array)[0]
	for field: String in ["id", "daoId", "name", "turnsRequired", "turnsRemaining", "daoPointCost", "spiritPowerCost"]:
		_check(entry.has(field), "researchQueue[] 含字段 " + field)

	# view 三态
	_check(_dao_state_of(_view(dispatcher), "tu_na") == "RESEARCHING", "view 中 tu_na 状态 == RESEARCHING")
	_check(_dao_state_of(_view(dispatcher), "dan_yao_chu") == "BLOCKED", "view 中 dan_yao_chu 状态 == BLOCKED（前置研究中）")
	_check(_dao_state_of(_view(dispatcher), "cang_shu") == "BLOCKED", "view 中 cang_shu 状态 == BLOCKED")

	# 逐回合推进 → 解锁
	var remaining: int = expected_turns
	for _i: int in range(expected_turns):
		_request(dispatcher, "nextTurn")
		remaining -= 1
		if remaining > 0:
			_check(sect.researchQueue.size() == 1 and sect.researchQueue[0].turnsRemaining == remaining, "研究剩余回合递减至 %d" % remaining)
	_check(sect.researchQueue.is_empty(), "研究完成后出队")
	_check(sect.unlockedDaoIds.has("tu_na"), "研究完成后 unlockedDaoIds 含 tu_na")
	_check(_dao_state_of(_view(dispatcher), "tu_na") == "UNLOCKED", "view 中 tu_na 状态 == UNLOCKED")
	_check(DaoRules.sect_era_index(state, _config, sect) == 0, "解锁炼气篇后宗门时代仍为炼气篇")

	# 重复研究 → 拒绝
	var again: Dictionary = _result(dispatcher, "researchDao", {"sectId": sect.id, "daoId": "tu_na"})
	_check(not bool(again.get("success", true)), "重复研究已解锁道法 → success=false")
	_check(str(again.get("message", "")).contains("已推演完成"), "已解锁 blocker 文案正确")


# ---------------------------------------------------------------------------
# 5. 取消 / 加速
# ---------------------------------------------------------------------------

func _test_cancel_accelerate() -> void:
	var dispatcher: CommandDispatcher = _new_game("400004")
	var state: GameState = dispatcher.state
	var sect: Sect = state.sects[0]
	var peak: SpiritPeak = _capital(sect)
	_grant(sect)

	# 研究项目取消：推进 1 回合后退还已付工力的 refundRate
	var dao: Dao = DaoRules.find_dao(_config, "tu_na")
	var turns: int = DaoRules.research_turns(_config, sect, dao)
	_check(turns >= 2, "tu_na 工期 >= 2 回合（可测中途取消）")
	_result(dispatcher, "researchDao", {"sectId": sect.id, "daoId": "tu_na"})
	_request(dispatcher, "nextTurn")
	var research: ResearchProject = sect.researchQueue[0]
	var paid: int = ProjectRules.paid_work_cost(research)
	_check(paid > 0, "已支付工力 > 0")
	var work_before: int = int(sect.resources.get("workPower", 0))
	var cancel: Dictionary = _result(dispatcher, "cancelProject", {"peakId": peak.id, "projectId": research.id})
	var expected_refund: int = int(round(float(paid) * float(_config["building"]["refundRate"])))
	_check(bool(cancel.get("success", false)), "取消研究项目成功")
	_check(sect.researchQueue.is_empty(), "取消后研究队列清空")
	_check(int(sect.resources.get("workPower", 0)) == work_before + expected_refund, "取消研究退还工力 %d" % expected_refund)

	# 建造项目取消：退灵力 + 全额退材料
	var build: Dictionary = _result(dispatcher, "constructBuilding", {"peakId": peak.id, "buildingType": "CANG_JING_GE"})
	_check(bool(build.get("success", false)), "建造藏经阁入队成功")
	var build_cost: int = int(_config["building"]["costs"]["CANG_JING_GE"])
	var material_cost: Dictionary = _config["building"]["materialCosts"]["CANG_JING_GE"]
	var power_before: int = int(sect.resources.get("spiritPower", 0))
	var ling_mu_before: int = int((sect.resources.get("materials", {}) as Dictionary).get("ling_mu", 0))
	var build_cancel: Dictionary = _result(dispatcher, "cancelProject", {"peakId": peak.id, "projectId": str(build.get("projectId", ""))})
	_check(bool(build_cancel.get("success", false)), "取消建造项目成功")
	_check(int(sect.resources.get("spiritPower", 0)) == power_before + int(round(float(build_cost) * float(_config["building"]["refundRate"]))), "取消建造退还灵力按 refundRate")
	_check(int((sect.resources.get("materials", {}) as Dictionary).get("ling_mu", 0)) == ling_mu_before + int(material_cost["ling_mu"]), "取消建造全额退还材料")

	# 加速研究：灵石 -accelerateStonePerTurn×turns，剩余回合递减
	_result(dispatcher, "researchDao", {"sectId": sect.id, "daoId": "tu_na"})
	var research2: ResearchProject = sect.researchQueue[0]
	var stone_per_turn: int = int(_config["economy"]["accelerateStonePerTurn"])
	var stones_before: int = int(sect.resources.get("spiritStones", 0))
	var accel: Dictionary = _result(dispatcher, "accelerateProject", {"peakId": peak.id, "projectId": research2.id, "turns": 1, "research": true})
	_check(bool(accel.get("success", false)), "加速研究 1 回合成功")
	_check(int(sect.resources.get("spiritStones", 0)) == stones_before - stone_per_turn, "加速扣灵石 %d" % stone_per_turn)
	_check(research2.turnsRemaining == turns - 1, "加速后剩余回合 -1")

	# 加速到 0 → 即时完成并解锁
	var accel2: Dictionary = _result(dispatcher, "accelerateProject", {"peakId": peak.id, "projectId": research2.id, "turns": 5, "research": true})
	_check(bool(accel2.get("success", false)), "加速到 0 即时完成")
	_check(sect.researchQueue.is_empty(), "即时完成后出队")
	_check(sect.unlockedDaoIds.has("tu_na"), "即时完成即解锁道法")

	# peakId 可省（research=true）
	sect.resources["daoPoints"] = 1000
	_result(dispatcher, "researchDao", {"sectId": sect.id, "daoId": "ling_tian_nong"})
	var research3: ResearchProject = sect.researchQueue[0]
	var no_peak: Dictionary = _result(dispatcher, "accelerateProject", {"projectId": research3.id, "turns": 1, "research": true})
	_check(bool(no_peak.get("success", false)), "research=true 时 peakId 可省")
	# 非研究项目缺 peakId → BAD_PARAMS
	var missing_peak: Dictionary = _request(dispatcher, "accelerateProject", {"projectId": research3.id, "turns": 1})
	_check(str(missing_peak.get("errorCode", "")) == "BAD_PARAMS", "非研究项目缺 peakId → BAD_PARAMS")
	# turns 非法 → BAD_PARAMS
	var bad_turns: Dictionary = _request(dispatcher, "accelerateProject", {"peakId": peak.id, "projectId": research3.id, "turns": 0})
	_check(str(bad_turns.get("errorCode", "")) == "BAD_PARAMS", "turns<=0 → BAD_PARAMS")
	# 灵石不足 → 业务失败
	sect.resources["spiritStones"] = 0
	var poor: Dictionary = _result(dispatcher, "accelerateProject", {"peakId": peak.id, "projectId": research3.id, "turns": 1, "research": true})
	_check(not bool(poor.get("success", true)), "灵石不足 → success=false")
	_check(str(poor.get("message", "")).contains("灵石不足"), "灵石不足 blocker 文案正确")
	# 不存在的项目
	sect.resources["spiritStones"] = 1000
	var ghost: Dictionary = _result(dispatcher, "cancelProject", {"peakId": peak.id, "projectId": "no_such_project"})
	_check(not bool(ghost.get("success", true)), "取消不存在的项目 → success=false")


# ---------------------------------------------------------------------------
# 6. 收徒
# ---------------------------------------------------------------------------

func _test_recruitment() -> void:
	var dispatcher: CommandDispatcher = _new_game("400005")
	var state: GameState = dispatcher.state
	var sect: Sect = state.sects[0]
	var peak: SpiritPeak = _capital(sect)
	_grant(sect)

	var cost: int = int(_config["building"]["recruitmentCost"])
	var turns: int = int(_config["building"]["recruitmentTurns"])
	var work_before: int = int(sect.resources.get("workPower", 0))
	var count_before: int = sect.disciples.size()
	var result: Dictionary = _result(dispatcher, "holdRecruitment", {"peakId": peak.id})
	_check(bool(result.get("success", false)), "holdRecruitment 入队成功")
	_check(int(result.get("turnsRequired", -1)) == turns, "holdRecruitment turnsRequired == %d" % turns)
	_check(int(sect.resources.get("workPower", 0)) == work_before - cost, "收徒扣工力 %d" % cost)
	_check(peak.projectQueue.size() == 1 and peak.projectQueue[0].type == Project.TYPE_RECRUITMENT, "收徒项目进入灵峰项目队列")

	# 间隔不足 → 拒绝
	var too_soon: Dictionary = _result(dispatcher, "holdRecruitment", {"peakId": peak.id})
	_check(not bool(too_soon.get("success", true)), "收徒间隔不足 → success=false")
	_check(str(too_soon.get("message", "")).contains("不足"), "间隔 blocker 文案正确")

	# 推进到落成
	for _i: int in range(turns):
		_request(dispatcher, "nextTurn")
	var expected_count: int = int(_config["building"]["recruitmentBaseCount"]) + int(_config["building"]["recruitmentPerLevel"]) * maxi(0, peak.level - 1)
	_check(sect.disciples.size() == count_before + expected_count, "收徒落成新增 %d 名弟子" % expected_count)
	_check(sect.recruitedTotal == expected_count, "recruitedTotal == %d" % expected_count)
	var all_assigned: bool = true
	for index: int in range(sect.disciples.size()):
		if index < count_before:
			continue
		if sect.disciples[index].assignedPeakId != peak.id:
			all_assigned = false
		if sect.disciples[index].realm != str(_config["map"]["setup"]["outerRealm"]):
			all_assigned = false
	_check(all_assigned, "新弟子归属该峰且境界为外门境界")

	# 冷却过后可再次举办
	sect.lastRecruitmentTurn = state.turn - int(_config["disciple"]["recruitmentBaseInterval"])
	var again: Dictionary = _result(dispatcher, "holdRecruitment", {"peakId": peak.id})
	_check(bool(again.get("success", false)), "冷却结束可再次举办收徒大典")

	# 工力不足 → 拒绝
	sect.resources["workPower"] = 0
	var poor: Dictionary = _result(dispatcher, "holdRecruitment", {"peakId": peak.id})
	_check(not bool(poor.get("success", true)), "工力不足 → 收徒失败")


# ---------------------------------------------------------------------------
# 7. 修炼 / 突破
# ---------------------------------------------------------------------------

func _test_cultivation_breakthrough() -> void:
	var dispatcher: CommandDispatcher = _new_game("400006")
	var state: GameState = dispatcher.state
	var sect: Sect = state.sects[0]
	var disciple: Disciple = sect.disciples[1]
	_grant(sect)
	sect.resources["prestige"] = 0

	var cultivation: Dictionary = _config["disciple"]["cultivation"]
	var expected_speed: float = float(cultivation["baseSpeed"]) * (1.0 + float(cultivation["rootGradeBonusPerGrade"]) * float(disciple.rootGrade) + float(cultivation["zongMenBonus"]))
	var progress_before: float = disciple.cultivationProgress
	_request(dispatcher, "nextTurn")
	_check(is_equal_approx(disciple.cultivationProgress, progress_before + expected_speed), "修炼进度 +独立复算速度(%.2f)" % expected_speed)

	# 心魔 ≥ 阈值 → 速度 ×(1−penalty)
	sect.resources["prestige"] = 0
	disciple.heartDevil = int(cultivation["heartDevilPenaltyThreshold"])
	var penalized: float = DiscipleRules.cultivation_speed(state, _config, disciple)
	_check(is_equal_approx(penalized, expected_speed * (1.0 - float(cultivation["heartDevilPenalty"]))), "心魔≥阈值时修炼速度 −%d%%" % int(round(float(cultivation["heartDevilPenalty"]) * 100.0)))
	disciple.heartDevil = 0

	# 洞府加成（须先归属某峰：`_peak_of` 按 `assignedPeakId` 定位）
	sect.resources["prestige"] = 0
	var peak: SpiritPeak = _capital(sect)
	disciple.assignedPeakId = peak.id
	peak.buildings["cave_%s_%s" % [peak.id, disciple.id]] = {"id": "cave_test", "type": "CAVE", "name": "洞府", "level": 1, "districtId": ""}
	var with_cave: float = DiscipleRules.cultivation_speed(state, _config, disciple)
	_check(is_equal_approx(with_cave, expected_speed + float(cultivation["baseSpeed"]) * float(cultivation["caveBonus"])), "洞府修炼加成 +caveBonus")
	peak.buildings.erase("cave_%s_%s" % [peak.id, disciple.id])

	# 灵力不足 → 不推进
	sect.resources["spiritPower"] = 0
	var blocked: Dictionary = DiscipleRules.advance_cultivation(state, _config, disciple)
	_check(not bool(blocked["advanced"]), "灵力不足时修炼不推进")
	_grant(sect)

	# 修为满 → breakthroughPending
	var cap: float = float(cultivation["progressCapPerRealm"][disciple.realm])
	disciple.cultivationProgress = cap - 1.0
	disciple.breakthroughPending = false
	DiscipleRules.advance_cultivation(state, _config, disciple)
	_check(disciple.cultivationProgress <= cap, "进度不超过 progressCapPerRealm")
	_check(disciple.breakthroughPending, "进度满后置 breakthroughPending")

	# 突破判定（按境界成功率；成败都要符合公式）
	var chance: float = float(cultivation["breakthroughChancePerRealm"][disciple.realm])
	var realm_before: String = disciple.realm
	var devil_before: int = disciple.heartDevil
	var outcome: Dictionary = DiscipleRules.try_breakthrough(state, _config, disciple)
	_check(is_equal_approx(float(outcome["chance"]), chance), "突破成功率 == breakthroughChancePerRealm（%.2f）" % chance)
	if bool(outcome["success"]):
		_check(disciple.realm == Enums.Realm.ALL[Enums.Realm.ALL.find(realm_before) + 1], "突破成功 → 境界 +1")
		_check(is_equal_approx(disciple.cultivationProgress, 0.0), "突破成功 → 进度归零")
		_check(disciple.realmLevel == Disciple.level_of(disciple.realm), "突破成功 → realmLevel 同步")
	else:
		_check(disciple.realm == realm_before, "突破失败 → 境界不变")
		_check(disciple.heartDevil == devil_before + int(cultivation["breakthroughFailHeartDevil"]), "突破失败 → 心魔 +%d" % int(cultivation["breakthroughFailHeartDevil"]))
		_check(is_equal_approx(disciple.cultivationProgress, cap * float(cultivation["breakthroughFailProgressRatio"])), "突破失败 → 进度 ×%.1f" % float(cultivation["breakthroughFailProgressRatio"]))

	# 元婴不走路突破（须渡劫）、化神不可再突破
	var elder: Disciple = sect.disciples[0]
	elder.realm = Enums.Realm.YUAN_YING
	elder.realmLevel = 4
	elder.breakthroughPending = true
	var yuan_ying: Dictionary = DiscipleRules.try_breakthrough(state, _config, elder)
	_check(not bool(yuan_ying["success"]) and str(yuan_ying["reason"]).contains("渡劫"), "元婴突破被拒（须渡劫）")
	elder.realm = Enums.Realm.HUA_SHEN
	elder.realmLevel = 5
	var hua_shen: Dictionary = DiscipleRules.try_breakthrough(state, _config, elder)
	_check(not bool(hua_shen["success"]) and str(hua_shen["reason"]).contains("化神"), "化神不可再突破")

	# 修为未满 → 拒绝
	disciple.breakthroughPending = false
	var early: Dictionary = DiscipleRules.try_breakthrough(state, _config, disciple)
	_check(not bool(early["success"]) and str(early["reason"]).contains("未满"), "修为未满 → 拒绝突破")


# ---------------------------------------------------------------------------
# 8. 渡劫（规则函数，命令归 R7）
# ---------------------------------------------------------------------------

func _test_tribulation() -> void:
	var dispatcher: CommandDispatcher = _new_game("400007")
	var state: GameState = dispatcher.state
	var sect: Sect = state.sects[0]
	var disciple: Disciple = sect.disciples[0]
	_grant(sect)
	sect.resources["spiritStones"] = 10000
	sect.resources["materials"] = {"tian_jing": 9, "xuan_tie": 9, "ling_mu": 9}
	disciple.realm = Enums.Realm.YUAN_YING
	disciple.realmLevel = 4
	disciple.rootGrade = 3
	sect.unlockedDaoIds = [] as Array[String]

	var cultivation: Dictionary = _config["disciple"]["cultivation"]
	var expected_chance: float = float(cultivation["tribulationBaseSuccessChance"]) + float(disciple.rootGrade) * float(cultivation["tribulationRootGradeBonusPerGrade"])
	var power_before: int = int(sect.resources["spiritPower"])
	var stones_before: int = int(sect.resources["spiritStones"])
	var outcome: Dictionary = DiscipleRules.tribulate(state, _config, disciple)
	_check(is_equal_approx(float(outcome["chance"]), expected_chance), "渡劫成功率 == 独立复算（%.2f）" % expected_chance)
	_check(int(sect.resources["spiritPower"]) == power_before - int(cultivation["tribulationSpiritPowerCost"]), "渡劫扣灵力 %d" % int(cultivation["tribulationSpiritPowerCost"]))
	_check(int(sect.resources["spiritStones"]) == stones_before - int(cultivation["tribulationSpiritStoneCost"]), "渡劫扣灵石 %d" % int(cultivation["tribulationSpiritStoneCost"]))
	var materials: Dictionary = sect.resources["materials"]
	_check(int(materials["tian_jing"]) == 9 - int(cultivation["tribulationMaterialCosts"]["tian_jing"]), "渡劫扣天晶")
	_check(int(materials["xuan_tie"]) == 9 - int(cultivation["tribulationMaterialCosts"]["xuan_tie"]), "渡劫扣玄铁")
	if bool(outcome["success"]):
		_check(disciple.realm == Enums.Realm.HUA_SHEN, "渡劫成功 → 化神")
		_check(disciple.realmLevel == 5, "渡劫成功 → realmLevel 5")
	else:
		_check(disciple.realm == Enums.Realm.YUAN_YING, "渡劫失败 → 仍元婴")
		_check(disciple.heartDevil == int(cultivation["tribulationFailHeartDevil"]), "渡劫失败 → 心魔 +%d" % int(cultivation["tribulationFailHeartDevil"]))
	_check(not disciple.tribulating, "渡劫结束后 tribulating 复位")

	# 已解锁道法提升成功率
	var boosted: Disciple = sect.disciples[1]
	boosted.realm = Enums.Realm.YUAN_YING
	boosted.realmLevel = 4
	boosted.rootGrade = 0
	sect.unlockedDaoIds.append("tu_na")
	var chance_two: Dictionary = DiscipleRules.tribulate(state, _config, boosted)
	var expected_two: float = float(cultivation["tribulationBaseSuccessChance"]) + float(cultivation["tribulationDaoBonusPerUnlocked"])
	_check(is_equal_approx(float(chance_two["chance"]), expected_two), "每解锁 1 道法 → 渡劫成功率 +5%")

	# 非元婴 → 拒绝
	var young: Disciple = sect.disciples[2]
	young.realm = Enums.Realm.LIAN_QI
	young.realmLevel = 1
	var refused: Dictionary = DiscipleRules.tribulate(state, _config, young)
	_check(not bool(refused["success"]) and str(refused["reason"]).contains("元婴"), "非元婴渡劫 → 拒绝")

	# 资源不足 → 拒绝且不扣
	sect.resources["materials"] = {"tian_jing": 0, "xuan_tie": 0}
	var broke: Disciple = sect.disciples[1]
	broke.realm = Enums.Realm.YUAN_YING
	broke.realmLevel = 4
	var stones_now: int = int(sect.resources["spiritStones"])
	var no_material: Dictionary = DiscipleRules.tribulate(state, _config, broke)
	_check(not bool(no_material["success"]) and str(no_material["reason"]).contains("材料不足"), "材料不足 → 渡劫失败且不扣")
	_check(int(sect.resources["spiritStones"]) == stones_now, "渡劫前置检查失败不扣灵石")


# ---------------------------------------------------------------------------
# 9. 道法 MOVE_BONUS / VISION_BONUS 回填
# ---------------------------------------------------------------------------

func _test_move_and_vision_bonus() -> void:
	var dispatcher: CommandDispatcher = _new_game("400008")
	var state: GameState = dispatcher.state
	var sect: Sect = state.sects[0]
	var disciple: Disciple = sect.disciples[1]
	var base: int = MoveRules.calculate_max_move_points(disciple, _config, state, sect)
	var base_plain: int = MoveRules.calculate_max_move_points(disciple, _config)
	sect.unlockedDaoIds.append("dun_shu")
	_check(MoveRules.calculate_max_move_points(disciple, _config, state, sect) == base + 1, "解锁 dun_shu → 移动力 +1")
	sect.unlockedDaoIds.append("qi_ji")
	_check(MoveRules.calculate_max_move_points(disciple, _config, state, sect) == base + 2, "再解锁 qi_ji → 移动力 +2")
	_check(DaoRules.move_bonus(state, _config, sect) == 2, "effect_sum MOVE_BONUS 合计 == 2")
	# 不传 state/sect 时等价 R2 口径（不含道路起点加成与道法加成）
	_check(MoveRules.calculate_max_move_points(disciple, _config) == base_plain, "2 参调用不受道法加成影响（R2 口径不变）")

	# 视野加成
	var before: int = sect.visibleTiles.size()
	sect.unlockedDaoIds.append("fa_xiu")
	VisionCalculator.recalculate(state, _config)
	_check(sect.visibleTiles.size() >= before, "解锁 fa_xiu 后视野格数不减")
	_check(DaoRules.vision_bonus(state, _config, sect) == 1, "effect_sum VISION_BONUS == 1")

	# 解锁类效果收集
	var unlocks: Array = DaoRules.effect_sum(state, _config, sect).get("UNLOCK_UNIT", [])
	_check(unlocks.has("jian_xiu") or unlocks.has("fa_xiu"), "UNLOCK_UNIT 收集已解锁兵种 key")

	# 改良道法门控回填：解锁 ling_tian_nong 后 LING_TIAN_TI_TIAN 不再被道法拦
	# 取主峰邻格作为施工地块（主峰自身被首府区占用，不能建改良）
	var peak_tile: HexTile = state.tiles[_capital(sect).tileId]
	var flat_tile: HexTile = null
	for coords: Vector2i in Hex.neighbors(Vector2i(peak_tile.q, peak_tile.r)):
		var neighbor_id: String = Hex.id(coords.x, coords.y)
		if state.tiles.has(neighbor_id):
			flat_tile = state.tiles[neighbor_id]
			break
	_check(flat_tile != null, "夹具：主峰存在邻格")
	if flat_tile != null:
		flat_tile.ownerSectId = sect.id
		flat_tile.districtId = ""
		flat_tile.improvementId = ""
		flat_tile.nodeId = ""
		flat_tile.danger = false
		flat_tile.relief = Enums.Relief.FLAT
		flat_tile.baseTerrain = Enums.BaseTerrain.LING_FIELDS
		var no_features: Array[String] = []
		flat_tile.features = no_features
		var blocked_before: String = ImprovementRules.can_build_improvement(state, _config, sect, null, flat_tile, "LING_TIAN_TI_TIAN")
		_check(blocked_before.contains("道法"), "未解锁 ling_tian_nong 时灵田梯田被道法门控拦下")
		sect.unlockedDaoIds.append("ling_tian_nong")
		var blocked_after: String = ImprovementRules.can_build_improvement(state, _config, sect, null, flat_tile, "LING_TIAN_TI_TIAN")
		_check(not blocked_after.contains("道法"), "解锁 ling_tian_nong 后不再被道法门控拦下")


# ---------------------------------------------------------------------------
# 10. 道统成就 boost
# ---------------------------------------------------------------------------

func _test_boosts() -> void:
	var dispatcher: CommandDispatcher = _new_game("400009")
	var state: GameState = dispatcher.state
	var sect: Sect = state.sects[0]
	# 回归：开局视野内可能含秘境节点，但「看见」≠「探索过」，不得白送成就道点。
	var fresh_events: Array[String] = DaoRules.check_boosts(state, _config, sect)
	_check(fresh_events.is_empty(), "开局不触发任何道统成就")
	_check(int(sect.resources.get("daoPoints", 0)) == 0, "开局道点仍为 0（视野内秘境节点不算已探索）")
	sect.resources["daoPoints"] = 0
	sect.boostFlags.clear()

	# 拥有 3 灵脉 +40
	var any_tile: HexTile = state.tiles[sect.spiritPeaks[0].tileId]
	for index: int in range(3):
		var node: GameNode = GameNode.new()
		node.id = "boost_ling_mai_%d" % index
		node.type = Enums.NodeType.LING_MAI
		node.tileId = any_tile.id
		node.ownerSectId = sect.id
		state.nodes[node.id] = node
	var first: Array[String] = DaoRules.check_boosts(state, _config, sect)
	_check(not first.is_empty(), "拥有 3 灵脉触发成就")
	_check(int(sect.resources["daoPoints"]) == 40, "灵脉成就道点 +40")
	var second: Array[String] = DaoRules.check_boosts(state, _config, sect)
	_check(second.is_empty(), "同一成就只触发一次")
	_check(int(sect.resources["daoPoints"]) == 40, "重复判定不加道点")

	# 累计招募 5 人 +30
	sect.recruitedTotal = 5
	DaoRules.check_boosts(state, _config, sect)
	_check(int(sect.resources["daoPoints"]) == 70, "招募成就道点 +30")

	# 首次秘境 +30：条件是**成功探索秘境次数**，不是「视野内存在秘境节点」
	# （后者开局即成立，会白送 30 道点并让成就永久失效，见 PROTOCOL §11.1 #23）。
	var mijing: GameNode = GameNode.new()
	mijing.id = "boost_mijing"
	mijing.type = Enums.NodeType.MI_JING
	mijing.tileId = any_tile.id
	state.nodes[mijing.id] = mijing
	if not sect.exploredTiles.has(any_tile.id):
		sect.exploredTiles.append(any_tile.id)
	DaoRules.check_boosts(state, _config, sect)
	_check(int(sect.resources["daoPoints"]) == 70, "仅「视野内可见秘境节点」不触发秘境成就")
	sect.miJingExploredTotal = 1
	DaoRules.check_boosts(state, _config, sect)
	_check(int(sect.resources["daoPoints"]) == 100, "秘境成就道点 +30（成功探索秘境后）")

	# 首次胜敌 +30
	sect.enemiesDefeated = 1
	DaoRules.check_boosts(state, _config, sect)
	_check(int(sect.resources["daoPoints"]) == 130, "首胜成就道点 +30")
	_check(sect.boostFlags.size() == 4, "四个成就标志均已置位")

	# boostFlags 不下发 view
	var view: Dictionary = _view(dispatcher)
	var player: Dictionary = _player_sect(view)
	_check(not player.has("boostFlags"), "view 不含 boostFlags（内部记账）")
	_check(not player.has("recruitedTotal"), "view 不含 recruitedTotal")
	_check(not player.has("enemiesDefeated"), "view 不含 enemiesDefeated")
	# 内部字段也不进 disciples[]
	var disciple_view: Dictionary = (player["disciples"] as Array)[0]
	for field: String in ["lastReproduceTurn", "breakthroughPending", "tribulating", "realmLevel"]:
		_check(not disciple_view.has(field), "view.disciples[] 不含 " + field)

	# 道点产出汇总：分项之和 == total，且藏经阁按 cangJingGePointsPerTurn 计入
	var sect_now: Sect = state.sects[0]
	var peak_now: SpiritPeak = _capital(sect_now)
	var cang_jing_id: String = "building_%s_%s" % [peak_now.id, Enums.Building.CANG_JING_GE]
	peak_now.buildings[cang_jing_id] = {"id": cang_jing_id, "type": Enums.Building.CANG_JING_GE, "name": "藏经阁", "level": 1, "districtId": ""}
	var breakdown: Dictionary = DaoRules.dao_point_output(state, _config, sect_now)
	var per_turn: int = int(_config["daoTree"]["cangJingGePointsPerTurn"])
	_check(int(breakdown["cangJingGe"]) == per_turn, "藏经阁道点 == cangJingGePointsPerTurn（%d）" % per_turn)
	_check(int(breakdown["total"]) == int(breakdown["cangJingGe"]) + int(breakdown["nodes"]) + int(breakdown["districts"]), "dao_point_output.total == 分项之和")


# ---------------------------------------------------------------------------
# 11. 确定性
# ---------------------------------------------------------------------------

func _test_determinism() -> void:
	var first: String = _run_sequence()
	var second: String = _run_sequence()
	_check(not first.is_empty(), "R4 指令序列可执行")
	_check(first == second, "同种子同指令序列双跑关键 view 逐字一致")


func _run_sequence() -> String:
	var dispatcher: CommandDispatcher = _new_game("20261017")
	var state: GameState = dispatcher.state
	var sect: Sect = state.sects[0]
	var peak: SpiritPeak = _capital(sect)
	_grant(sect)
	_result(dispatcher, "researchDao", {"sectId": sect.id, "daoId": "tu_na"})
	_result(dispatcher, "holdRecruitment", {"peakId": peak.id})
	for _i: int in range(6):
		_request(dispatcher, "nextTurn")
	return JSON.stringify(_snapshot(_view(dispatcher), state), "\t", true)


func _snapshot(view: Dictionary, state: GameState) -> Dictionary:
	var player: Dictionary = _player_sect(view)
	var disciples: Array = []
	for disciple: Disciple in state.sects[0].disciples:
		disciples.append({"id": disciple.id, "realm": disciple.realm, "progress": snappedf(disciple.cultivationProgress, 0.0001), "heartDevil": disciple.heartDevil, "tileId": disciple.tileId, "assignedPeakId": disciple.assignedPeakId})
	var peaks: Array = []
	for peak: SpiritPeak in state.sects[0].spiritPeaks:
		peaks.append({"id": peak.id, "level": peak.level, "population": peak.population, "food": snappedf(peak.food, 0.0001), "stability": snappedf(peak.stability, 0.0001), "qiYun": peak.qiYun, "projects": peak.projectQueue.size(), "buildings": peak.buildings.size()})
	return {
		"turn": view["turn"],
		"phase": view["phase"],
		"resources": player.get("resources", {}),
		"unlockedDaoIds": player.get("unlockedDaoIds", []),
		"researchQueue": player.get("researchQueue", []),
		"daoStates": _dao_state_map(view),
		"disciples": disciples,
		"peaks": peaks,
		"eventLog": view["eventLog"],
	}


func _dao_state_map(view: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var player: Dictionary = _player_sect(view)
	for option: Variant in player.get("daoOptions", []):
		var entry: Dictionary = option
		out[str(entry["id"])] = "%s|%s|%d" % [str(entry["state"]), str(entry["blocker"]), int(entry["turns"])]
	return out


# ---------------------------------------------------------------------------
# 辅助
# ---------------------------------------------------------------------------

func _new_game(seed: String) -> CommandDispatcher:
	return _new_game_faction(seed, Enums.FactionType.ZONG_MEN)


func _new_game_faction(seed: String, faction: String) -> CommandDispatcher:
	var dispatcher: CommandDispatcher = CommandDispatcher.new(_config)
	_request(dispatcher, "newGame", {"sectName": "验收宗", "playerFaction": faction, "mapWidth": 24, "mapHeight": 18, "randomSeed": seed, "difficultyId": "normal"})
	return dispatcher


func _request(dispatcher: CommandDispatcher, command: String, params: Dictionary = {}) -> Dictionary:
	return dispatcher.dispatch_text(JSON.stringify({"id": "test", "type": command, "params": params}))


func _result(dispatcher: CommandDispatcher, command: String, params: Dictionary) -> Dictionary:
	var response: Dictionary = _request(dispatcher, command, params)
	return response.get("result", {})


func _view(dispatcher: CommandDispatcher) -> Dictionary:
	return _request(dispatcher, "getState")["view"]


func _capital(sect: Sect) -> SpiritPeak:
	for peak: SpiritPeak in sect.spiritPeaks:
		if peak.capital:
			return peak
	return sect.spiritPeaks[0]


## 给足研究/收徒所需资源（道点、工力、灵力、灵石、材料）。
func _grant(sect: Sect) -> void:
	sect.resources["spiritPower"] = 20000
	sect.resources["spiritStones"] = 20000
	sect.resources["workPower"] = 20000
	sect.resources["daoPoints"] = 20000
	sect.resources["materials"] = {"tian_jing": 99, "xuan_tie": 99, "ling_mu": 99}


func _player_sect(view: Dictionary) -> Dictionary:
	for entry: Variant in view["sects"]:
		var sect: Dictionary = entry
		if bool(sect.get("player", false)):
			return sect
	return {}


func _dao_state_of(view: Dictionary, dao_id: String) -> String:
	var player: Dictionary = _player_sect(view)
	for option: Variant in player.get("daoOptions", []):
		var entry: Dictionary = option
		if str(entry.get("id", "")) == dao_id:
			return str(entry.get("state", ""))
	return ""


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _same_strings(a: Variant, b: Variant) -> bool:
	var left: Array = a if a is Array else []
	var right: Array = b if b is Array else []
	if left.size() != right.size():
		return false
	for index: int in range(left.size()):
		if str(left[index]) != str(right[index]):
			return false
	return true
