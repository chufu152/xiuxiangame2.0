extends Node
## R6 自动验收：探索（机缘/秘境）+ 政令（3 政体 / 8 卡 / 槽位 / 时代道法门控 / 冷却）+
## 自动化（开关/预算/建造次数/立即探索）+ 集结/回防 + `setSetting` + R2/R3 空钩子回填 + 确定性。
##
## 无头运行：`godot --headless --path server res://tests/R6Test.tscn`，
## 全绿打印 `R6_PASS checks=N` 并退出码 0，否则 `R6_FAIL ...` 退出码 1。
##
## **断言原则**（沿用 R5）：
## 1. 期望值一律**从 `data/gameConfig.json` 独立复算**，不拿被测函数的返回值当自己的判据；
## 2. 需要「必定成功 / 必定陨落 / 必定受伤」的分支，把 `config` **深拷贝**后改那一个概率为 0 或 1
##    再直接调 `*Rules`，使分支完全确定、不靠运气（命令层仍走真实 `_config`）；
## 3. 概率本身只做**独立复算式**断言（基础值 + 品级 × 每级 + 宗门流加成，封顶 1.0）；
## 4. 每组测试都新建一局（`_new_game`），避免上一组改过的节点/资源污染下一组。

const R6_COMMANDS: Array[String] = [
	Commands.RALLY, Commands.RETURN_TO_DEFENSE,
	Commands.QUERY_JI_YUAN_INFO, Commands.SEND_TO_JI_YUAN,
	Commands.QUERY_MI_JING_INFO, Commands.EXPLORE_MI_JING,
	Commands.SWITCH_GOVERNMENT, Commands.ENACT_POLICY, Commands.REVOKE_POLICY, Commands.QUERY_POLICY_OPTIONS,
	Commands.SET_AUTOMATION_TOGGLE, Commands.SET_PEAK_AUTO_PROJECT, Commands.SET_ALL_AUTO_PROJECT,
	Commands.EXPLORE_NOW, Commands.QUERY_AUTOMATION_STATE, Commands.SET_SETTING,
]

## 只读命令：必须回 `view=null`（PROTOCOL §5/§6/§7）。
const READ_ONLY_R6: Array[String] = [
	Commands.QUERY_JI_YUAN_INFO, Commands.QUERY_MI_JING_INFO,
	Commands.QUERY_POLICY_OPTIONS, Commands.QUERY_AUTOMATION_STATE,
]

## 需要 `GameState` 的命令（`setSetting` 是纯确认命令，无状态也能回）。
const NEEDS_GAME_R6: Array[String] = [
	Commands.RALLY, Commands.RETURN_TO_DEFENSE,
	Commands.QUERY_JI_YUAN_INFO, Commands.SEND_TO_JI_YUAN,
	Commands.QUERY_MI_JING_INFO, Commands.EXPLORE_MI_JING,
	Commands.SWITCH_GOVERNMENT, Commands.ENACT_POLICY, Commands.REVOKE_POLICY, Commands.QUERY_POLICY_OPTIONS,
	Commands.SET_AUTOMATION_TOGGLE, Commands.SET_PEAK_AUTO_PROJECT, Commands.SET_ALL_AUTO_PROJECT,
	Commands.EXPLORE_NOW, Commands.QUERY_AUTOMATION_STATE,
]

var _failures: Array[String] = []
var _checks: int = 0
## 已实现命令总数（`_test_registration` 记录，供 `R6_IMPLEMENTED=` 行自报，check.ps1 据此卡 56 条）。
var _implemented_count: int = 0
var _config: Dictionary = {}
var _finished: bool = false
var _started: int = Time.get_ticks_msec()


func _process(_delta: float) -> void:
	if not _finished and Time.get_ticks_msec() - _started > 300000:
		printerr("R6_FAIL 测试未正常完成（可能运行时脚本错误）")
		get_tree().quit(1)


func _ready() -> void:
	var loaded: Dictionary = ConfigLoader.load_from_file(ConfigLoader.default_path())
	_check(bool(loaded["ok"]), "配置可加载")
	_config = loaded["config"]
	_check(ConfigValidator.validate(_config).is_empty(), "配置通过深层验证")
	_test_registration()
	_test_ji_yuan()
	_test_mi_jing()
	_test_government()
	_test_policies()
	_test_policy_options()
	_test_automation()
	_test_rally()
	_test_set_setting()
	_test_backfill()
	_test_determinism()
	_finished = true
	if _failures.is_empty():
		print("R6_IMPLEMENTED=%d" % _implemented_count)
		print("R6_PASS checks=%d" % _checks)
		get_tree().quit(0)
	else:
		for failure: String in _failures:
			printerr("R6_FAIL " + failure)
		printerr("R6_FAIL checks=%d failures=%d" % [_checks, _failures.size()])
		get_tree().quit(1)


# ---------------------------------------------------------------------------
# 1. 命令注册、只读契约、参数把关
# ---------------------------------------------------------------------------

func _test_registration() -> void:
	var dispatcher: CommandDispatcher = CommandDispatcher.new(_config)
	var implemented: Array = dispatcher.implemented_commands()
	_implemented_count = implemented.size()
	for command: String in R6_COMMANDS:
		_check(implemented.has(command), "已登记 R6 命令：" + command)
	_check(implemented.size() == 56, "已登记命令 56 条（40 + 16，实际 %d）" % implemented.size())
	for command: String in NEEDS_GAME_R6:
		_check(_request(dispatcher, command, {}).get("errorCode") == "NO_GAME", "%s 开局前 NO_GAME" % command)
	# `setSetting` 无状态也可用（服务端只确认，不碰 GameState）。
	var setting: Dictionary = _request(dispatcher, Commands.SET_SETTING, {"key": "animation", "value": true})
	_check(bool(setting.get("ok")) and setting.get("view") == null, "setSetting 无开局也能回包且 view=null")

	var game: CommandDispatcher = _new_game("6001")
	var sect: Sect = _player(game)
	var disciple: Disciple = _disciple(sect, 0)
	var capital: SpiritPeak = _capital(sect)
	var ji_node: GameNode = _inject_node(game.state, capital.tileId, Enums.NodeType.JI_YUAN)
	# 只读命令 view 必须为 null。
	var read_only_params: Dictionary = {
		Commands.QUERY_JI_YUAN_INFO: {"nodeId": ji_node.id},
		Commands.QUERY_MI_JING_INFO: {"nodeId": ji_node.id},
		Commands.QUERY_POLICY_OPTIONS: {"sectId": sect.id},
		Commands.QUERY_AUTOMATION_STATE: {"sectId": sect.id},
	}
	for command: String in READ_ONLY_R6:
		var response: Dictionary = _request(game, command, read_only_params[command])
		_check(response.get("view") == null, "只读命令 %s 的 view 必须为 null" % command)
	# 参数缺失/类型错/枚举非法 → BAD_PARAMS（协议层失败）。
	_check(_request(game, Commands.QUERY_JI_YUAN_INFO, {}).get("errorCode") == "BAD_PARAMS", "queryJiYuanInfo 缺 nodeId 回 BAD_PARAMS")
	_check(_request(game, Commands.QUERY_JI_YUAN_INFO, {"nodeId": "no_such_node"}).get("errorCode") == "BAD_PARAMS", "queryJiYuanInfo 节点不存在回 BAD_PARAMS")
	_check(_request(game, Commands.SEND_TO_JI_YUAN, {"discipleId": disciple.id}).get("errorCode") == "BAD_PARAMS", "sendToJiYuan 缺 nodeId 回 BAD_PARAMS")
	_check(_request(game, Commands.EXPLORE_MI_JING, {"discipleIds": "nope", "nodeId": ji_node.id}).get("errorCode") == "BAD_PARAMS", "exploreMiJing 非数组 discipleIds 回 BAD_PARAMS")
	_check(_request(game, Commands.SWITCH_GOVERNMENT, {"sectId": sect.id, "governmentId": "no_such_gov"}).get("errorCode") == "BAD_PARAMS", "switchGovernment 非法政体回 BAD_PARAMS")
	_check(_request(game, Commands.ENACT_POLICY, {"sectId": sect.id, "cardId": "no_such_card"}).get("errorCode") == "BAD_PARAMS", "enactPolicy 非法 cardId 回 BAD_PARAMS")
	_check(_request(game, Commands.ENACT_POLICY, {"sectId": sect.id, "policyId": "ling_tian_zhi"}).get("errorCode") == "BAD_PARAMS", "enactPolicy 只认 cardId（§11.1 #5）")
	_check(_request(game, Commands.SET_AUTOMATION_TOGGLE, {"sectId": sect.id, "key": "nope", "on": true}).get("errorCode") == "BAD_PARAMS", "setAutomationToggle 非法 key 回 BAD_PARAMS")
	_check(_request(game, Commands.SET_AUTOMATION_TOGGLE, {"sectId": sect.id, "key": "road", "on": "yes"}).get("errorCode") == "BAD_PARAMS", "setAutomationToggle 非布尔 on 回 BAD_PARAMS")
	_check(_request(game, Commands.SET_SETTING, {"value": 1}).get("errorCode") == "BAD_PARAMS", "setSetting 缺 key 回 BAD_PARAMS")
	_check(_request(game, Commands.SET_SETTING, {"key": "animation"}).get("errorCode") == "BAD_PARAMS", "setSetting 缺 value 回 BAD_PARAMS")


# ---------------------------------------------------------------------------
# 2. 机缘
# ---------------------------------------------------------------------------

func _test_ji_yuan() -> void:
	var explore: Dictionary = _config["explore"]
	var dispatcher: CommandDispatcher = _new_game("6002")
	var state: GameState = dispatcher.state
	var sect: Sect = _player(dispatcher)
	var disciple: Disciple = _disciple(sect, 0)
	var node: GameNode = _inject_node(state, _capital(sect).tileId, Enums.NodeType.JI_YUAN)
	# 2.1 成功率独立复算：基础 + 品级 × 每级 + 宗门流加成（封顶 1.0）。
	disciple.rootGrade = 4
	var expected: float = minf(1.0, float(explore["jiYuanBaseSuccessChance"])
		+ 4.0 * float(explore["jiYuanRootGradeBonus"])
		+ float(_config["faction"]["zongMen"]["exploreSuccessBonus"]))
	_check(is_equal_approx(ExploreRules.ji_yuan_success_chance(state, _config, disciple, sect), expected),
		"机缘成功率 = 0.5 + 品级×0.05 + 宗门流加成")
	var info: Dictionary = _result(dispatcher, Commands.QUERY_JI_YUAN_INFO, {"nodeId": node.id})
	_check(bool(info["found"]) and str(info["kind"]) == "jiYuan", "queryJiYuanInfo found/kind")
	var node_info: Dictionary = info["info"]
	_check(str(node_info["nodeId"]) == node.id and str(node_info["type"]) == Enums.NodeType.JI_YUAN, "NodeInfo nodeId/type")
	_check(int(node_info["requiredRealmLevel"]) == node.level * int(explore["jiYuanThresholdPerNodeLevel"]), "NodeInfo requiredRealmLevel = 等级 × 每级门槛")
	_check(int(node_info["cooldown"]) == 0, "NodeInfo 初始冷却 0")
	_check(str(node_info["rewardPreview"]).contains(str(ExploreRules.material_label(_config, "tian_jing"))), "NodeInfo rewardPreview 含材料名")
	_check(str(node_info["rewardPreview"]).contains("道统点x%d" % int(explore["jiYuanDaoPointReward"])), "NodeInfo rewardPreview 含道点")
	_check(str(node_info["name"]) == node.name and not node.name.is_empty(), "NodeInfo name 来自 GameNode.name")

	# 2.2 必定成功：品级拉高把成功率顶到 1.0，奖励按 基础 + 品级 × 每级 逐项复算。
	disciple.rootGrade = 40
	var points_before: int = int(sect.resources.get("daoPoints", 0))
	var materials_before: Dictionary = (sect.resources.get("materials", {}) as Dictionary).duplicate()
	var result: Dictionary = _result(dispatcher, Commands.SEND_TO_JI_YUAN, {"discipleId": disciple.id, "nodeId": node.id})
	_check(bool(result["success"]), "机缘必定成功（成功率已顶到 1.0）")
	_check(int(result["cooldown"]) == int(explore["jiYuanCooldownTurns"]), "ExploreResult.cooldown = jiYuanCooldownTurns")
	_check(node.cooldown == int(explore["jiYuanCooldownTurns"]), "节点冷却已置为 jiYuanCooldownTurns")
	var rewards: Array = result["rewards"]
	var by_material: Dictionary = {}
	var dao_reward: int = 0
	for entry: Variant in rewards:
		var reward: Dictionary = entry
		if str(reward["type"]) == ExploreRules.REWARD_RARE_MATERIAL:
			by_material[str(reward["materialId"])] = int(reward["amount"])
		elif str(reward["type"]) == ExploreRules.REWARD_DAO_POINT:
			dao_reward = int(reward["amount"])
	for material: String in (explore["jiYuanMaterials"] as Dictionary).keys():
		var expect_amount: int = int(explore["jiYuanMaterials"][material]) \
			+ disciple.rootGrade * int(explore["jiYuanMaterialPerGrade"].get(material, 0))
		_check(int(by_material.get(material, -1)) == expect_amount, "机缘材料 %s 数量 = 基础 + 品级×每级" % material)
		_check(int((sect.resources.get("materials", {}) as Dictionary).get(material, 0)) == int(materials_before.get(material, 0)) + expect_amount, "材料入账 %s" % material)
	_check(dao_reward == int(explore["jiYuanDaoPointReward"]), "机缘道点奖励 = jiYuanDaoPointReward")
	_check(int(sect.resources.get("daoPoints", 0)) == points_before + int(explore["jiYuanDaoPointReward"]), "道点入账")

	# 2.3 冷却中再派 → 业务失败（ok:true + success:false）。
	var again: Dictionary = _result(dispatcher, Commands.SEND_TO_JI_YUAN, {"discipleId": disciple.id, "nodeId": node.id})
	_check(not bool(again["success"]) and str(again["message"]).contains("冷却"), "机缘冷却中再次派遣回 success=false")

	# 2.4 修为不足：节点等级抬到 2 → 需 2 级修为。
	var dispatcher_realm: CommandDispatcher = _new_game("6003")
	var state_realm: GameState = dispatcher_realm.state
	var sect_realm: Sect = _player(dispatcher_realm)
	var node_realm: GameNode = _inject_node(state_realm, _capital(sect_realm).tileId, Enums.NodeType.JI_YUAN, 2)
	var weak: Disciple = _disciple(sect_realm, 1)
	_check(weak.realmLevel < 2, "夹具：外门弟子境界 < 2")
	var blocked: Dictionary = _result(dispatcher_realm, Commands.SEND_TO_JI_YUAN, {"discipleId": weak.id, "nodeId": node_realm.id})
	_check(not bool(blocked["success"]) and str(blocked["message"]).contains("修为不足"), "修为不足回 success=false")
	_check(node_realm.cooldown == 0, "修为不足不消耗节点冷却")

	# 2.5 三种失败分支：深拷贝 config 把概率钉死，逐一验证落地效果。
	_ji_yuan_failure("6004", 1.0, 0.0, "fall")
	_ji_yuan_failure("6005", 0.0, 1.0, "injury")
	_ji_yuan_failure("6006", 0.0, 0.0, "none")


func _ji_yuan_failure(seed: String, fall_chance: float, injury_chance: float, expected: String) -> void:
	var dispatcher: CommandDispatcher = _new_game(seed)
	var state: GameState = dispatcher.state
	var sect: Sect = _player(dispatcher)
	var disciple: Disciple = _disciple(sect, 0)
	var node: GameNode = _inject_node(state, _capital(sect).tileId, Enums.NodeType.JI_YUAN)
	var config: Dictionary = _config.duplicate(true)
	config["explore"]["jiYuanBaseSuccessChance"] = 0.0
	config["faction"]["zongMen"]["exploreSuccessBonus"] = 0.0
	config["explore"]["jiYuanFailFallChance"] = fall_chance
	config["explore"]["jiYuanFailInjuryChance"] = injury_chance
	disciple.rootGrade = 0
	var devil_before: int = disciple.heartDevil
	var result: Dictionary = ExploreRules.send_to_ji_yuan(state, config, disciple.id, node.id)
	_check(not bool(result["success"]), "机缘失败分支(%s)：success=false" % expected)
	_check(int(result["cooldown"]) == int(_config["explore"]["jiYuanCooldownTurns"]), "机缘失败分支(%s)：冷却同样置满" % expected)
	_check(node.cooldown == int(_config["explore"]["jiYuanCooldownTurns"]), "机缘失败分支(%s)：节点冷却已置满" % expected)
	match expected:
		"fall":
			_check((result["casualties"] as Array).has(disciple.id), "机缘失败：陨落写入 casualties")
			_check(not sect.disciples.has(disciple), "机缘失败：陨落者已出宗")
			_check(disciple.missionNodeId.is_empty(), "机缘失败：任务节点已清空")
		"injury":
			_check((result["injured"] as Array).has(disciple.id), "机缘失败：受伤写入 injured")
			_check(disciple.injured and disciple.movePoints == 0, "机缘失败：受伤且移动力归零")
			_check(disciple.heartDevil == devil_before + int(_config["disciple"]["heartDevil"]["exploreFailBonus"]), "机缘失败：受伤仍加心魔")
		"none":
			_check((result["casualties"] as Array).is_empty() and (result["injured"] as Array).is_empty(), "机缘失败：一无所获无伤亡")
			_check(disciple.heartDevil == devil_before + int(_config["disciple"]["heartDevil"]["exploreFailBonus"]), "机缘失败：一无所获加心魔")
			_check(not disciple.injured, "机缘失败：一无所获不受伤")


# ---------------------------------------------------------------------------
# 3. 秘境
# ---------------------------------------------------------------------------

func _test_mi_jing() -> void:
	var explore: Dictionary = _config["explore"]
	var dispatcher: CommandDispatcher = _new_game("6010")
	var state: GameState = dispatcher.state
	var sect: Sect = _player(dispatcher)
	var node: GameNode = _inject_node(state, _capital(sect).tileId, Enums.NodeType.MI_JING)
	var info: Dictionary = _result(dispatcher, Commands.QUERY_MI_JING_INFO, {"nodeId": node.id})
	_check(bool(info["found"]) and str(info["kind"]) == "miJing", "queryMiJingInfo found/kind")
	var node_info: Dictionary = info["info"]
	_check(int(node_info["cost"]) == int(explore["miJingCost"]), "NodeInfo cost = miJingCost")
	_check(int(node_info["maxParticipants"]) == int(explore["miJingMaxParticipants"]), "NodeInfo maxParticipants = miJingMaxParticipants")
	_check(str(node_info["rewardPreview"]).contains("灵石x%d" % int(explore["miJingRichSpiritStones"])), "NodeInfo rewardPreview 含富裕灵石")
	# 3.1 人数超限。
	var too_many: Array = []
	for index: int in range(int(explore["miJingMaxParticipants"]) + 1):
		too_many.append(_disciple(sect, index % sect.disciples.size()).id)
	var over: Dictionary = _result(dispatcher, Commands.EXPLORE_MI_JING, {"discipleIds": too_many, "nodeId": node.id})
	_check(not bool(over["success"]) and str(over["message"]).contains("参与人数超限"), "秘境人数超限回 success=false")
	_check(node.cooldown == 0, "人数超限不消耗秘境冷却")
	# 3.2 灵石不足。
	var stones_before: int = int(sect.resources["spiritStones"])
	sect.resources["spiritStones"] = int(explore["miJingCost"]) - 1
	var poor: Dictionary = _result(dispatcher, Commands.EXPLORE_MI_JING, {"discipleIds": [_disciple_id(sect, 0)], "nodeId": node.id})
	_check(not bool(poor["success"]) and str(poor["message"]).contains("灵石不足"), "秘境灵石不足回 success=false")
	sect.resources["spiritStones"] = stones_before
	# 3.3 不在节点格。
	var wanderer: Disciple = _disciple(sect, 1)
	var home: String = wanderer.tileId
	wanderer.tileId = _neighbor_tile(state, home)
	var away: Dictionary = _result(dispatcher, Commands.EXPLORE_MI_JING, {"discipleIds": [wanderer.id], "nodeId": node.id})
	_check(not bool(away["success"]) and str(away["message"]).contains("不在秘境所在地块"), "秘境要求全员已在节点格")
	wanderer.tileId = home
	# 3.4 富裕率独立复算。
	var participants: Array = [_disciple_id(sect, 0), _disciple_id(sect, 1), _disciple_id(sect, 2)]
	var grade_sum: int = 0
	var realm_sum: int = 0
	for id: String in participants:
		var one: Disciple = MoveAction.find_disciple(state, id)
		grade_sum += one.rootGrade
		realm_sum += one.realmLevel
	var expected_rich: float = minf(1.0, float(explore["miJingBaseRichChance"])
		+ (float(grade_sum) / float(participants.size())) * float(explore["miJingRootGradeBonus"])
		+ ((float(realm_sum) / float(participants.size())) - 1.0) * float(explore["miJingRealmBonus"])
		+ float(_config["faction"]["zongMen"]["exploreSuccessBonus"]))
	var group: Array = []
	for id: String in participants:
		group.append(MoveAction.find_disciple(state, id))
	_check(is_equal_approx(ExploreRules.mi_jing_rich_chance(state, _config, group, sect), expected_rich),
		"秘境富裕率 = 0.3 + 平均品级×0.04 + (平均境界−1)×0.04 + 宗门流加成")
	# 3.5 必定富裕（富裕率钉 1.0）：奖励与入账逐项复算。
	var rich_config: Dictionary = _config.duplicate(true)
	rich_config["explore"]["miJingBaseRichChance"] = 1.0
	rich_config["explore"]["miJingDisasterChance"] = 0.0
	var stones_pre: int = int(sect.resources["spiritStones"])
	var points_pre: int = int(sect.resources.get("daoPoints", 0))
	var explored_pre: int = sect.miJingExploredTotal
	var rich: Dictionary = ExploreRules.explore_mi_jing(state, rich_config, participants, node.id)
	_check(bool(rich["success"]), "秘境必定富裕（富裕率钉 1.0）")
	_check(node.cooldown == int(explore["miJingCooldownTurns"]), "秘境冷却 = miJingCooldownTurns")
	_check(int(rich["cooldown"]) == int(explore["miJingCooldownTurns"]), "ExploreResult.cooldown = miJingCooldownTurns")
	_check(int(sect.resources["spiritStones"]) == stones_pre - int(explore["miJingCost"]) + int(explore["miJingRichSpiritStones"]), "秘境富裕灵石 = −成本 + 富裕奖励")
	_check(int(sect.resources.get("daoPoints", 0)) == points_pre + int(explore["miJingRichDaoPoints"]), "秘境富裕道点入账")
	var rich_types: Dictionary = {}
	for entry: Variant in (rich["rewards"] as Array):
		rich_types[str((entry as Dictionary)["type"])] = int((entry as Dictionary)["amount"])
	_check(int(rich_types.get(ExploreRules.REWARD_SPIRIT_STONES, -1)) == int(explore["miJingRichSpiritStones"]), "富裕奖励含 SPIRIT_STONES")
	_check(int(rich_types.get(ExploreRules.REWARD_DAO_POINT, -1)) == int(explore["miJingRichDaoPoints"]), "富裕奖励含 DAO_POINT")
	_check(sect.miJingExploredTotal == explored_pre + 1, "miJingExploredTotal 递增（boost_first_mijing 可达）")
	# 3.6 遇险：富裕率 0 + 险情率 1 + 陨落率 1 → 全员陨落。
	var disaster_config: Dictionary = _config.duplicate(true)
	disaster_config["explore"]["miJingBaseRichChance"] = 0.0
	disaster_config["explore"]["miJingRootGradeBonus"] = 0.0
	disaster_config["explore"]["miJingRealmBonus"] = 0.0
	disaster_config["explore"]["miJingDisasterChance"] = 1.0
	disaster_config["explore"]["miJingFallChance"] = 1.0
	disaster_config["explore"]["miJingInjuryChance"] = 0.0
	disaster_config["faction"]["zongMen"]["exploreSuccessBonus"] = 0.0
	node.cooldown = 0
	var alive_before: int = sect.disciples.size()
	var disaster: Dictionary = ExploreRules.explore_mi_jing(state, disaster_config, participants, node.id)
	_check(not bool(disaster["success"]), "秘境遇险回 success=false")
	_check((disaster["casualties"] as Array).size() == participants.size(), "秘境遇险：全员陨落写入 casualties")
	_check(sect.disciples.size() == alive_before - participants.size(), "秘境遇险：陨落者已出宗")
	# 3.7 一无所获：富裕率 0 + 险情率 0。
	var empty_config: Dictionary = _config.duplicate(true)
	empty_config["explore"]["miJingBaseRichChance"] = 0.0
	empty_config["explore"]["miJingRootGradeBonus"] = 0.0
	empty_config["explore"]["miJingRealmBonus"] = 0.0
	empty_config["explore"]["miJingDisasterChance"] = 0.0
	empty_config["faction"]["zongMen"]["exploreSuccessBonus"] = 0.0
	node.cooldown = 0
	# 上一步全员陨落，此处补一名临时弟子（秘境要求参与者站在节点格上）。
	var survivor: Disciple = Disciple.new()
	survivor.id = "survivor_1"
	survivor.name = "幸存弟子"
	survivor.sectId = sect.id
	survivor.tileId = node.tileId
	survivor.realm = Enums.Realm.LIAN_QI
	survivor.realmLevel = 1
	sect.disciples.append(survivor)
	var nothing: Dictionary = ExploreRules.explore_mi_jing(state, empty_config, [survivor.id], node.id)
	_check(not bool(nothing["success"]) and str(nothing["message"]).contains("一无所获"), "秘境一无所获回 success=false")


# ---------------------------------------------------------------------------
# 4. 政体
# ---------------------------------------------------------------------------

func _test_government() -> void:
	var policy: Dictionary = _config["policy"]
	var dispatcher: CommandDispatcher = _new_game("6020")
	var state: GameState = dispatcher.state
	var sect: Sect = _player(dispatcher)
	# 4.1 三政体与 config 一致（slots / effects）。
	var options: Dictionary = _result(dispatcher, Commands.QUERY_POLICY_OPTIONS, {"sectId": sect.id})
	_check((options["governments"] as Array).size() == (policy["governments"] as Array).size(), "政体数量与 config 一致")
	_check((policy["governments"] as Array).size() == 3, "config 定义 3 个政体")
	for entry: Variant in (options["governments"] as Array):
		var shown: Dictionary = entry
		var source: Dictionary = PolicyRules.government(_config, str(shown["id"]))
		_check(not source.is_empty(), "政体 %s 在 config 中存在" % str(shown["id"]))
		_check((shown["slots"] as Dictionary) == (source["slots"] as Dictionary), "政体 %s 槽位与 config 一致" % str(shown["id"]))
		_check(str(shown["effectsText"]) == PolicyRules.effects_text(source.get("effects", {})), "政体 %s 效果文案与 config 一致" % str(shown["id"]))
	# 4.2 未立政体时回退配置首政体（宗门共治）。
	_check(str(options["governmentId"]) == str((policy["governments"] as Array)[0]["id"]), "未立政体回退首政体")
	_check(bool((options["governments"] as Array)[0]["current"]), "首政体标记 current")
	# 4.3 已是该政体 → 业务失败。
	var same: Dictionary = _result(dispatcher, Commands.SWITCH_GOVERNMENT, {"sectId": sect.id, "governmentId": "zong_fa"})
	_check(not bool(same["success"]) and str(same["message"]).contains("已是该政体"), "切换为当前政体回 success=false")
	# 4.4 时代门控：jun_quan 需元婴篇，开局只有炼气篇。
	_check(PolicyRules.sect_era_index(state, _config, sect) == 0, "开局时代序号 = 0（炼气篇）")
	var era_blocked: Dictionary = _result(dispatcher, Commands.SWITCH_GOVERNMENT, {"sectId": sect.id, "governmentId": "jun_quan"})
	_check(not bool(era_blocked["success"]) and str(era_blocked["message"]).contains("元婴篇"), "时代未到回 success=false（jun_quan 需元婴篇）")
	var menfa_blocked: Dictionary = _result(dispatcher, Commands.SWITCH_GOVERNMENT, {"sectId": sect.id, "governmentId": "men_fa"})
	_check(not bool(menfa_blocked["success"]) and str(menfa_blocked["message"]).contains("金丹篇"), "时代未到回 success=false（men_fa 需金丹篇）")
	# 4.5 解锁元婴篇道法后可切换，且切换当回合记满冷却。
	sect.unlockedDaoIds.append(_dao_of_era("元婴篇"))
	_check(PolicyRules.sect_era_index(state, _config, sect) == 3, "解锁元婴篇后时代序号 = 3")
	var switched: Dictionary = _result(dispatcher, Commands.SWITCH_GOVERNMENT, {"sectId": sect.id, "governmentId": "jun_quan"})
	_check(bool(switched["success"]), "时代达标后可切换政体")
	_check(sect.governmentId == "jun_quan", "政府 id 已落库")
	_check(sect.lastPolicySwitchTurn == state.turn, "切换回合已记账")
	_check(PolicyRules.switch_cooldown_left(state, _config, sect) == int(policy["switchCooldownTurns"]), "切换当回合冷却 = switchCooldownTurns")
	# 4.6 冷却内再切 → 业务失败。
	var cooling: Dictionary = _result(dispatcher, Commands.SWITCH_GOVERNMENT, {"sectId": sect.id, "governmentId": "zong_fa"})
	_check(not bool(cooling["success"]) and str(cooling["message"]).contains("冷却"), "切换冷却内回 success=false")
	_check(sect.governmentId == "jun_quan", "冷却内切换不改政体")
	# 4.7 冷却按回合递减，到期后可切。
	state.turn += int(policy["switchCooldownTurns"])
	_check(PolicyRules.switch_cooldown_left(state, _config, sect) == 0, "冷却到期后剩余 0")
	var later: Dictionary = _result(dispatcher, Commands.SWITCH_GOVERNMENT, {"sectId": sect.id, "governmentId": "zong_fa"})
	_check(bool(later["success"]), "冷却到期后可再次切换")


# ---------------------------------------------------------------------------
# 5. 政令卡
# ---------------------------------------------------------------------------

func _test_policies() -> void:
	var policy: Dictionary = _config["policy"]
	var cards: Array = policy["cards"]
	# 5.1 8 张卡、无外交类目（PRD §5.2 #4）。
	_check(cards.size() == 8, "政令卡 8 张（实际 %d）" % cards.size())
	var diplomacy: int = 0
	var loyalty_keys: int = 0
	var weariness_keys: int = 0
	for entry: Variant in cards:
		var card: Dictionary = entry
		if str(card.get("category", "")) == "diplomacy":
			diplomacy += 1
		var effects: Dictionary = card.get("effects", {})
		if effects.has("loyaltyPerTurn"):
			loyalty_keys += 1
		if effects.has("weariness") or effects.has("wearinessDecay"):
			weariness_keys += 1
	_check(diplomacy == 0, "无 category=diplomacy（2 张外交卡已删）")
	_check(loyalty_keys == 0, "无 loyaltyPerTurn（裁决一：一律改落 stabilityPerTurn）")
	_check(weariness_keys == 0, "无 weariness 效果（裁决一：已删）")
	# 5.2 安定效果确实落在 stabilityPerTurn 上。
	var stability_cards: int = 0
	for entry: Variant in cards:
		if (entry as Dictionary).get("effects", {}).has("stabilityPerTurn"):
			stability_cards += 1
	_check(stability_cards >= 2, "至少 2 张卡带 stabilityPerTurn（严明赏罚/仙途诏令）")
	_check(PolicyRules.EFFECT_KEYS.has("stabilityPerTurn") and not PolicyRules.EFFECT_KEYS.has("loyaltyPerTurn"), "effect_sum 键集合只含 stabilityPerTurn")

	var dispatcher: CommandDispatcher = _new_game("6030")
	var state: GameState = dispatcher.state
	var sect: Sect = _player(dispatcher)
	# 5.3 颁行经济卡（宗门共治经济槽 1）。
	var first: Dictionary = _result(dispatcher, Commands.ENACT_POLICY, {"sectId": sect.id, "cardId": "ling_tian_zhi"})
	_check(bool(first["success"]), "颁行灵田制成功")
	_check(sect.enactedPolicies.has("ling_tian_zhi"), "已颁政令落库")
	_check(PolicyRules.used_slots(_config, sect, "economy") == 1, "经济槽占用 1")
	_check(is_equal_approx(float(PolicyRules.effect_sum(state, _config, sect)["outputBonus"]), 0.15), "effect_sum 含灵田制 outputBonus 0.15")
	var dup: Dictionary = _result(dispatcher, Commands.ENACT_POLICY, {"sectId": sect.id, "cardId": "ling_tian_zhi"})
	_check(not bool(dup["success"]) and str(dup["message"]).contains("已颁行"), "重复颁行回 success=false")
	# 5.4 槽位已满。
	var full: Dictionary = _result(dispatcher, Commands.ENACT_POLICY, {"sectId": sect.id, "cardId": "shang_dao"})
	_check(not bool(full["success"]), "经济槽满时颁行经济卡回 success=false")
	_check(str(full["message"]).contains("经济") or str(full["message"]).contains("筑基篇"), "槽满/时代门控给出中文原因")
	# 5.5 时代门控：先解锁筑基篇，再换 men_fa（经济 2 槽）后颁行商道通衢。
	sect.unlockedDaoIds.append(_dao_of_era("筑基篇"))
	sect.unlockedDaoIds.append(_dao_of_era("金丹篇"))
	sect.lastPolicySwitchTurn = 0
	var to_menfa: Dictionary = _result(dispatcher, Commands.SWITCH_GOVERNMENT, {"sectId": sect.id, "governmentId": "men_fa"})
	_check(bool(to_menfa["success"]), "解锁金丹篇后可切 men_fa")
	_check(sect.enactedPolicies.has("ling_tian_zhi"), "zong_fa→men_fa 经济槽 1→2，灵田制保留")
	_check(not str(to_menfa["message"]).contains("废止"), "无超槽位政令时不写「废止」")
	var second: Dictionary = _result(dispatcher, Commands.ENACT_POLICY, {"sectId": sect.id, "cardId": "shang_dao"})
	_check(bool(second["success"]), "men_fa 经济槽 2 可颁行商道通衢")
	_check(PolicyRules.used_slots(_config, sect, "economy") == 2, "经济槽占用 2")
	# 5.6 men_fa 无军事槽 → 军事卡不可颁。
	var military: Dictionary = _result(dispatcher, Commands.ENACT_POLICY, {"sectId": sect.id, "cardId": "tie_lv_jun_gui"})
	_check(not bool(military["success"]) and str(military["message"]).contains("槽位"), "men_fa 无军事槽，军事卡回 success=false")
	# 5.7 道法门控：仙途诏令需 fei_sheng。
	var dao_gate: Dictionary = _result(dispatcher, Commands.ENACT_POLICY, {"sectId": sect.id, "cardId": "xian_tu_zhao_ling"})
	_check(not bool(dao_gate["success"]) and str(dao_gate["message"]).contains("道法"), "unlockDaoKey 门控生效")
	sect.unlockedDaoIds.append("fei_sheng")
	var dao_open: Dictionary = _result(dispatcher, Commands.ENACT_POLICY, {"sectId": sect.id, "cardId": "xian_tu_zhao_ling"})
	_check(bool(dao_open["success"]), "修成 fei_sheng 后可颁仙途诏令")
	_check(is_equal_approx(float(PolicyRules.effect_sum(state, _config, sect)["stabilityPerTurn"]), 1.0), "men_fa 0.5 + 仙途诏令 0.5 = 安定 1.0/回合")
	# 5.8 废除。
	var revoked: Dictionary = _result(dispatcher, Commands.REVOKE_POLICY, {"sectId": sect.id, "cardId": "xian_tu_zhao_ling"})
	_check(bool(revoked["success"]) and not sect.enactedPolicies.has("xian_tu_zhao_ling"), "废除政令成功")
	var revoke_again: Dictionary = _result(dispatcher, Commands.REVOKE_POLICY, {"sectId": sect.id, "cardId": "xian_tu_zhao_ling"})
	_check(not bool(revoke_again["success"]) and str(revoke_again["message"]).contains("尚未颁行"), "重复废除回 success=false")
	# 5.9 换政体触发槽位裁剪：men_fa 经济 2 → zong_fa 经济 1，多出的经济卡被废止。
	_check(PolicyRules.used_slots(_config, sect, "economy") == 2, "夹具：men_fa 经济槽已占 2")
	sect.lastPolicySwitchTurn = 0
	var trim: Dictionary = _result(dispatcher, Commands.SWITCH_GOVERNMENT, {"sectId": sect.id, "governmentId": "zong_fa"})
	_check(bool(trim["success"]), "回到 zong_fa 成功")
	_check(PolicyRules.used_slots(_config, sect, "economy") == 1, "经济槽被裁剪到 1")
	_check(sect.enactedPolicies.size() == 1, "只保留 1 张政令（超槽位的那张已废止）")
	_check(str(trim["message"]).contains("废止"), "裁剪结果写进 message")


# ---------------------------------------------------------------------------
# 6. queryPolicyOptions 形状
# ---------------------------------------------------------------------------

func _test_policy_options() -> void:
	var dispatcher: CommandDispatcher = _new_game("6040")
	var state: GameState = dispatcher.state
	var sect: Sect = _player(dispatcher)
	var options: Dictionary = _result(dispatcher, Commands.QUERY_POLICY_OPTIONS, {"sectId": sect.id})
	for key: String in ["sectId", "enabled", "found", "governmentId", "governmentName", "switchCooldownLeft", "eraIndex", "effects", "lines", "governments", "cards"]:
		_check(options.has(key), "queryPolicyOptions 含 %s" % key)
	_check(bool(options["enabled"]), "enabled 与 config 一致")
	_check(bool(options["found"]), "found=true")
	_check(str(options["sectId"]) == sect.id, "sectId 回显")
	var effects: Dictionary = options["effects"]
	_check(effects.size() == PolicyRules.EFFECT_KEYS.size(), "effects{} 键数 = 6（裁决三）")
	for key: String in PolicyRules.EFFECT_KEYS:
		_check(effects.has(key) and typeof(effects[key]) == TYPE_FLOAT, "effects.%s 存在且为浮点" % key)
	var gov: Dictionary = (options["governments"] as Array)[0]
	for key: String in ["id", "name", "description", "current", "allowed", "blocker", "slots", "effectsText"]:
		_check(gov.has(key), "governments[] 含 %s" % key)
	_check((gov["slots"] as Dictionary).size() == 3, "zong_fa slots 三键（经济/军事/治理）")
	var card: Dictionary = (options["cards"] as Array)[0]
	for key: String in ["id", "name", "category", "categoryLabel", "description", "unlockEra", "enacted", "allowed", "blocker", "usedSlots", "effectsText"]:
		_check(card.has(key), "cards[] 含 %s" % key)
	_check(not card.has("unlockDaoKey"), "cards[] 不下发 unlockDaoKey（PROTOCOL 字段不增不减）")
	_check((options["lines"] as Array).size() >= 2, "lines[] 含政体与槽位文案")
	_check(int(options["eraIndex"]) == 0, "eraIndex 复用 DaoRules.sect_era_index")
	# 已颁卡的 enacted/usedSlots 联动。
	sect.enactedPolicies.append("ling_tian_zhi")
	var again: Dictionary = _result(dispatcher, Commands.QUERY_POLICY_OPTIONS, {"sectId": sect.id})
	for entry: Variant in (again["cards"] as Array):
		var item: Dictionary = entry
		if str(item["id"]) == "ling_tian_zhi":
			_check(bool(item["enacted"]), "已颁卡 enacted=true")
			_check(int(item["usedSlots"]) == 1, "已颁卡 usedSlots 按类目统计")
	# 非己方宗门 → BAD_PARAMS。
	_check(_request(dispatcher, Commands.QUERY_POLICY_OPTIONS, {"sectId": "sect_x"}).get("errorCode") == "BAD_PARAMS", "queryPolicyOptions 非己方宗门回 BAD_PARAMS")
	_check(state.turn == 1, "只读查询不改回合")


# ---------------------------------------------------------------------------
# 7. 自动化
# ---------------------------------------------------------------------------

func _test_automation() -> void:
	var automation: Dictionary = _config["automation"]
	var dispatcher: CommandDispatcher = _new_game("6050")
	var state: GameState = dispatcher.state
	var sect: Sect = _player(dispatcher)
	# 7.1 默认开关 = config（改良开/修缮开/道路关/探索关/项目关）。
	var described: Dictionary = _result(dispatcher, Commands.QUERY_AUTOMATION_STATE, {"sectId": sect.id})
	for key: String in ["sectId", "enabled", "found", "autoImprove", "autoRepair", "autoRoad", "autoExplore", "summary", "peaks"]:
		_check(described.has(key), "queryAutomationState 含 %s" % key)
	_check(bool(described["autoImprove"]) == bool(automation["defaultAutoImprove"]), "autoImprove 默认 = config")
	_check(bool(described["autoRepair"]) == bool(automation["defaultAutoRepair"]), "autoRepair 默认 = config")
	_check(bool(described["autoRoad"]) == bool(automation["defaultAutoRoad"]), "autoRoad 默认 = config")
	_check(bool(described["autoExplore"]) == bool(automation["defaultAutoExplore"]), "autoExplore 默认 = config")
	var peak_entry: Dictionary = (described["peaks"] as Array)[0]
	_check(peak_entry.has("peakId") and peak_entry.has("name") and peak_entry.has("autoProject"), "peaks[] 三字段")
	_check(bool(peak_entry["autoProject"]) == bool(automation["defaultAutoProject"]), "autoProject 默认 = config")
	_check(str(described["summary"]).contains("自动改良"), "summary 含开关摘要")
	# 7.2 开关写入与读回。
	var toggled: Dictionary = _result(dispatcher, Commands.SET_AUTOMATION_TOGGLE, {"sectId": sect.id, "key": "road", "on": true})
	_check(bool(toggled["success"]), "开启自动修路成功")
	_check(AutomationRules.toggle_of(state, _config, sect, "road"), "自动修路已开启")
	_check(bool(_result(dispatcher, Commands.QUERY_AUTOMATION_STATE, {"sectId": sect.id})["autoRoad"]), "queryAutomationState 读回 autoRoad=true")
	# 7.3 逐峰 / 全峰自动项目。
	var capital: SpiritPeak = _capital(sect)
	_check(bool(_result(dispatcher, Commands.SET_PEAK_AUTO_PROJECT, {"peakId": capital.id, "on": true})["success"]), "setPeakAutoProject 成功")
	_check(AutomationRules.auto_project_of(_config, sect, capital), "单峰自动项目已开启")
	_check(bool(_result(dispatcher, Commands.SET_ALL_AUTO_PROJECT, {"sectId": sect.id, "on": false})["success"]), "setAllAutoProject 成功")
	_check(not AutomationRules.auto_project_of(_config, sect, capital), "全峰关闭后单峰也关闭")
	# 7.4 预算：把 maxActionsPerTurn 钉到 1，构造 2 座破损改良 → 一回合只修 1 座。
	#     建造差事只给低阶弟子（`improvement.builderMaxRealmLevel` = 2，宗主是金丹不给）。
	var builder: Disciple = _disciple(sect, 1)
	_check(bool(ImprovementAction.appoint_builder(state, _config, sect.id, builder.id)["success"]), "夹具：外门弟子领受建造差事")
	_check(builder.builderCharges == int(_config["improvement"]["builderCharges"]), "建造者获得 builderCharges")
	var charges_before: int = builder.builderCharges
	_break_improvement(state, sect, "improvement_test_1", capital.tileId)
	_break_improvement(state, sect, "improvement_test_2", _neighbor_tile(state, capital.tileId))
	var tight: Dictionary = _config.duplicate(true)
	tight["automation"]["maxActionsPerTurn"] = 1
	tight["automation"]["defaultAutoRoad"] = false
	var events_before: int = state.eventLog.size()
	var log1: Array[String] = AutomationRules.run_turn(state, tight)
	var repairs1: int = _count_prefix(log1, "[自动]")
	_check(repairs1 == 1, "maxActionsPerTurn=1 时一回合只做 1 个自动动作（实际 %d）" % repairs1)
	_check(builder.builderCharges == charges_before - int(automation["builderChargeCost"]), "自动建造耗 builderChargeCost 次建造次数")
	# 7.5 建造次数耗尽后不再自动施工。
	builder.builderCharges = 0
	var log2: Array[String] = AutomationRules.run_turn(state, tight)
	_check(_count_prefix(log2, "[自动]") == 0, "建造次数耗尽后不再自动施工")
	_check(state.eventLog.size() >= events_before, "自动化只追加日志，不清空历史")
	# 7.6 立即探索：最多 autoExploreMaxDisciples 人。
	builder.builderCharges = int(_config["improvement"]["builderCharges"])
	var now: Dictionary = _result(dispatcher, Commands.EXPLORE_NOW, {"sectId": sect.id})
	_check(bool(now["success"]), "exploreNow 成功")
	_check(str(now["message"]).contains("名弟子已外出探索"), "exploreNow 文案含人数")
	var sent_text: String = str(now["message"])
	var sent_count: int = int(sent_text.split(" ")[0])
	_check(sent_count <= int(automation["autoExploreMaxDisciples"]), "exploreNow 派出人数 ≤ autoExploreMaxDisciples")
	# 7.7 全部弟子已无移动力 → 业务失败。
	for disciple: Disciple in sect.disciples:
		disciple.movePoints = 0
	var exhausted: Dictionary = _result(dispatcher, Commands.EXPLORE_NOW, {"sectId": sect.id})
	_check(not bool(exhausted["success"]), "无闲置弟子时 exploreNow 回 success=false")


# ---------------------------------------------------------------------------
# 8. 集结 / 回防
# ---------------------------------------------------------------------------

func _test_rally() -> void:
	var automation: Dictionary = _config["automation"]
	var dispatcher: CommandDispatcher = _new_game("6060")
	var state: GameState = dispatcher.state
	var sect: Sect = _player(dispatcher)
	var capital: SpiritPeak = _capital(sect)
	var target: String = _neighbor_tile(state, capital.tileId)
	# 8.1 集结（3 人 ≤ 上限 8）。
	var result: Dictionary = _result(dispatcher, Commands.RALLY, {"sectId": sect.id, "tileId": target})
	_check(bool(result["success"]), "rally 成功")
	_check(result.has("message") and not result.has("movedIds"), "rally 是文案型结果（裁决七：不发明 movedIds）")
	_check(str(result["message"]).contains("集结"), "rally message 含「集结」")
	var at_target: int = 0
	for disciple: Disciple in sect.disciples:
		if disciple.tileId == target: at_target += 1
	_check(at_target >= 1, "至少 1 名弟子抵达集结地（实际 %d）" % at_target)
	# 8.2 超过 rallyMaxDisciples → 业务失败。
	var limit: int = int(automation["rallyMaxDisciples"])
	for disciple: Disciple in sect.disciples:
		disciple.movePoints = disciple.maxMovePoints
	var index: int = 0
	while sect.disciples.size() <= limit:
		var extra: Disciple = Disciple.new()
		extra.id = "dummy_%d" % index
		extra.name = "试炼弟子%d" % index
		extra.sectId = sect.id
		extra.tileId = capital.tileId
		extra.realm = Enums.Realm.LIAN_QI
		extra.realmLevel = 1
		extra.maxMovePoints = 3
		extra.movePoints = 3
		sect.disciples.append(extra)
		index += 1
	var over: Dictionary = _result(dispatcher, Commands.RALLY, {"sectId": sect.id, "tileId": target})
	_check(not bool(over["success"]) and str(over["message"]).contains("超限"), "rally 超 rallyMaxDisciples 回 success=false")
	_check(str(over["message"]).contains(str(limit)), "超限文案给出上限值")
	# 8.3 回防。
	var back: Dictionary = _result(dispatcher, Commands.RETURN_TO_DEFENSE, {"sectId": sect.id})
	_check(not bool(back["success"]) and str(back["message"]).contains("超限"), "returnToDefense 同样受上限约束")
	# 砍到上限内再回防。
	while sect.disciples.size() > limit:
		sect.disciples.pop_back()
	var defend: Dictionary = _result(dispatcher, Commands.RETURN_TO_DEFENSE, {"sectId": sect.id})
	_check(bool(defend["success"]), "returnToDefense 成功")
	_check(defend.has("message") and not defend.has("movedIds"), "returnToDefense 是文案型结果（裁决七）")
	var peak_tiles: Array[String] = []
	for peak: SpiritPeak in sect.spiritPeaks:
		peak_tiles.append(peak.tileId)
	var home: int = 0
	for disciple: Disciple in sect.disciples:
		if peak_tiles.has(disciple.tileId): home += 1
	_check(home >= 1, "至少 1 名弟子回到己方灵峰（实际 %d）" % home)
	# 8.4 省略 tileId → 集结到主峰地块。
	var implicit: Dictionary = _result(dispatcher, Commands.RALLY, {"sectId": sect.id})
	_check(bool(implicit["success"]), "rally 省略 tileId 时集结到主峰地块")


# ---------------------------------------------------------------------------
# 9. setSetting
# ---------------------------------------------------------------------------

func _test_set_setting() -> void:
	var dispatcher: CommandDispatcher = _new_game("6070")
	var state: GameState = dispatcher.state
	var sect: Sect = _player(dispatcher)
	var turn_before: int = state.turn
	var log_before: int = state.eventLog.size()
	var stones_before: int = int(sect.resources["spiritStones"])
	var response: Dictionary = _request(dispatcher, Commands.SET_SETTING, {"key": "autoPlayIntervalMs", "value": 300})
	_check(bool(response.get("ok")), "setSetting 回 ok:true")
	_check(response.get("view") == null, "setSetting 不回 view")
	_check((response.get("events") as Array).is_empty(), "setSetting 不产生事件")
	var result: Dictionary = response["result"]
	_check(bool(result["success"]), "setSetting result.success=true")
	_check(str(result["key"]) == "autoPlayIntervalMs" and int(result["value"]) == 300, "setSetting 回显 key/value")
	_check(not bool(result["applied"]), "setSetting applied=false（值留在客户端）")
	_check(str(result["note"]).contains("客户端"), "setSetting note 说明只在客户端生效")
	_check(state.turn == turn_before and state.eventLog.size() == log_before, "setSetting 不改 GameState")
	_check(int(sect.resources["spiritStones"]) == stones_before, "setSetting 不改资源")


# ---------------------------------------------------------------------------
# 10. R2/R3 空钩子回填
# ---------------------------------------------------------------------------

func _test_backfill() -> void:
	var dispatcher: CommandDispatcher = _new_game("6080")
	var state: GameState = dispatcher.state
	var sect: Sect = _player(dispatcher)
	var capital: SpiritPeak = _capital(sect)
	# 10.1 TURN_START 调用 AutomationRules.run_turn：任命建造者 + 破一座改良 → beginPlayerTurn 自动修缮。
	var builder: Disciple = _disciple(sect, 1)
	_check(bool(ImprovementAction.appoint_builder(state, _config, sect.id, builder.id)["success"]), "夹具：外门弟子领受建造差事")
	_break_improvement(state, sect, "improvement_backfill", capital.tileId)
	var charges_before: int = builder.builderCharges
	_request(dispatcher, Commands.BEGIN_PLAYER_TURN)
	_check(builder.builderCharges == charges_before - int(_config["automation"]["builderChargeCost"]), "TURN_START 自动化已回填（自动修缮消耗建造次数）")
	_check(_count_prefix(state.eventLog, "[自动]") >= 1, "TURN_START 写入 [自动] 日志")
	# 10.2/10.3 另起一局（节点注入会改动邻格节点类型，避免污染 10.4 的安定对照）。
	var game2: CommandDispatcher = _new_game("6081")
	var state2: GameState = game2.state
	var sect2: Sect = _player(game2)
	var capital2: SpiritPeak = _capital(sect2)
	# 10.2 SETTLEMENT 节点冷却 −1（R3 已落 `EconomyRules.apply_settlement`，R6 复核仍生效）。
	var node: GameNode = _inject_node(state2, _neighbor_tile(state2, capital2.tileId), Enums.NodeType.JI_YUAN)
	node.cooldown = int(_config["explore"]["jiYuanCooldownTurns"])
	var cooldown_before: int = node.cooldown
	# 10.3 qiYun 每回合产出（R3 已落 `EconomyRules.peak_output` / `_apply_economy`）。
	var output: Dictionary = EconomyRules.peak_output(state2, _config, capital2)
	_check(int(output["qiYun"]) >= int(_config["qiYun"]["basePerTurn"]), "peak_output 气运 ≥ qiYun.basePerTurn")
	var qi_before: int = capital2.qiYun
	_request(game2, Commands.FINISH_TURN)
	_check(node.cooldown == cooldown_before - 1, "SETTLEMENT 节点冷却 −1")
	_check(capital2.qiYun > qi_before, "SETTLEMENT 气运逐回合累积")
	# 10.4 SETTLEMENT 政令结算：默认政体宗门共治 stabilityPerTurn=0.5 → 两回合落地 +1。
	#      用「同种子 + 关闭政令系统」的对照局做差，避免拿派生值自证（两局都不做任何注入/夹具）。
	var game3: CommandDispatcher = _new_game("6082")
	var control_config: Dictionary = _config.duplicate(true)
	control_config["policy"]["enabled"] = false
	var control: CommandDispatcher = CommandDispatcher.new(control_config)
	_request(control, "newGame", {"sectName": "验收宗", "playerFaction": Enums.FactionType.ZONG_MEN,
		"mapWidth": 24, "mapHeight": 18, "randomSeed": "6082", "difficultyId": "normal"})
	var sect3: Sect = _player(game3)
	var control_sect: Sect = _player(control)
	_check(control_sect != null, "对照组开局成功")
	_check(is_equal_approx(float(PolicyRules.effect_sum(game3.state, _config, sect3)["stabilityPerTurn"]), 0.5), "默认政体安定 +0.5/回合")
	# 两边都跑 2 个完整回合（SETTLEMENT + 下一回合 TURN_START）。
	for index: int in range(2):
		_request(game3, Commands.FINISH_TURN)
		_request(game3, Commands.BEGIN_PLAYER_TURN)
		_request(control, Commands.FINISH_TURN)
		_request(control, Commands.BEGIN_PLAYER_TURN)
	var bonus: int = int(sect3.policyCarry.get("stabilityBonus", 0))
	_check(bonus == 1, "两回合 0.5×2 小数累积落地 +1（实际 %d）" % bonus)
	_check(int(control_sect.policyCarry.get("stabilityBonus", 0)) == 0, "政令关闭时无安定叠加")
	var with_policy: float = _capital(sect3).stability
	var without_policy: float = _capital(control_sect).stability
	_check(is_equal_approx(with_policy, without_policy + float(bonus)), "政令安定叠加在派生安定之上（差 = %d）" % bonus)
	_check(int(sect3.resources.get("prestige", 0)) >= int(control_sect.resources.get("prestige", 0)), "声望结算不倒退")
	_check(PolicyRules.process_settlement(control.state, control_config).is_empty(), "政令系统关闭时结算不产生事件")


# ---------------------------------------------------------------------------
# 11. 确定性
# ---------------------------------------------------------------------------

func _test_determinism() -> void:
	var left: CommandDispatcher = _new_game("6090")
	var right: CommandDispatcher = _new_game("6090")
	var script: Array = [
		[Commands.SET_AUTOMATION_TOGGLE, {"key": "explore", "on": true}],
		[Commands.SET_ALL_AUTO_PROJECT, {"on": true}],
		[Commands.ENACT_POLICY, {"cardId": "ling_tian_zhi"}],
		[Commands.EXPLORE_NOW, {}],
		[Commands.RALLY, {}],
		[Commands.FINISH_TURN, {}],
		[Commands.BEGIN_PLAYER_TURN, {}],
		[Commands.GET_STATE, {}],
	]
	for step: Array in script:
		var command: String = str(step[0])
		var extra: Dictionary = step[1]
		var params: Dictionary = extra.duplicate()
		if [Commands.SET_AUTOMATION_TOGGLE, Commands.SET_ALL_AUTO_PROJECT, Commands.ENACT_POLICY, Commands.EXPLORE_NOW, Commands.RALLY].has(command):
			params["sectId"] = _player(left).id
		_request(left, command, params)
		var mirror: Dictionary = extra.duplicate()
		if params.has("sectId"):
			mirror["sectId"] = _player(right).id
		_request(right, command, mirror)
	var left_view: Dictionary = _view(left)
	var right_view: Dictionary = _view(right)
	_check(JSON.stringify(left_view) == JSON.stringify(right_view), "同种子 + 同指令序列 → 两份 view 逐字一致")
	_check(JSON.stringify(_player(left).resources) == JSON.stringify(_player(right).resources), "资源逐字一致")
	_check(JSON.stringify(left.state.eventLog) == JSON.stringify(right.state.eventLog), "事件日志逐字一致")
	var left_nodes: Dictionary = {}
	for node: GameNode in left.state.nodes.values():
		left_nodes[node.id] = node.cooldown
	var right_nodes: Dictionary = {}
	for node: GameNode in right.state.nodes.values():
		right_nodes[node.id] = node.cooldown
	_check(JSON.stringify(left_nodes) == JSON.stringify(right_nodes), "节点冷却逐字一致")
	_check(JSON.stringify(_player(left).automationToggles) == JSON.stringify(_player(right).automationToggles), "自动化开关逐字一致")
	_check(JSON.stringify(_player(left).enactedPolicies) == JSON.stringify(_player(right).enactedPolicies), "政令状态逐字一致")
	var left_disciple: Array = []
	var right_disciple: Array = []
	for disciple: Disciple in _player(left).disciples:
		left_disciple.append([disciple.id, disciple.tileId, disciple.heartDevil, disciple.movePoints])
	for disciple: Disciple in _player(right).disciples:
		right_disciple.append([disciple.id, disciple.tileId, disciple.heartDevil, disciple.movePoints])
	_check(JSON.stringify(left_disciple) == JSON.stringify(right_disciple), "弟子位置/心魔/移动力逐字一致")


# ---------------------------------------------------------------------------
# 测试辅助
# ---------------------------------------------------------------------------

## 在指定地块上放一个测试节点（覆盖该地块原有 `nodeId`，仅测试夹具使用）。
func _inject_node(state: GameState, tile_id: String, type: String, level: int = 1) -> GameNode:
	var tile: HexTile = state.tiles[tile_id]
	var node: GameNode = GameNode.new()
	node.id = "test_node_" + tile_id
	node.name = "%s测" % str(Enums.NodeType.NAMES.get(type, type))
	node.tileId = tile_id
	node.type = type
	node.level = level
	state.nodes[node.id] = node
	tile.nodeId = node.id
	return node


## 在指定地块上放一座破损改良（`repairImprovement` 只需「有改良 + broken」，不校验区域）。
func _break_improvement(state: GameState, sect: Sect, improvement_id: String, tile_id: String) -> void:
	var tile: HexTile = state.tiles[tile_id]
	var improvement: Improvement = Improvement.new()
	improvement.id = improvement_id
	improvement.type = "DONG_FU"
	improvement.tileId = tile_id
	improvement.sectId = sect.id
	improvement.broken = true
	sect.improvements.append(improvement)
	if tile.improvementId.is_empty():
		tile.improvementId = improvement.id


## 相邻地块 id（优先陆地可通行）；找不到时回落到原地块。
func _neighbor_tile(state: GameState, tile_id: String) -> String:
	var tile: HexTile = state.tiles.get(tile_id, null)
	if tile == null:
		return tile_id
	var coords: Vector2i = Hex.coords(tile_id)
	for direction: Vector2i in Hex.DIRECTIONS:
		var next: Vector2i = coords + direction
		var candidate: String = Hex.id(next.x, next.y)
		if state.tiles.has(candidate):
			return candidate
	return tile_id


func _count_prefix(lines: Array, prefix: String) -> int:
	var count: int = 0
	for line: Variant in lines:
		if str(line).begins_with(prefix):
			count += 1
	return count


func _dao_of_era(era: String) -> String:
	for entry: Variant in _config["daoTree"]["daos"]:
		var dao: Dictionary = entry
		if str(dao.get("era", "")) == era:
			return str(dao.get("id", ""))
	return ""


func _new_game(seed: String) -> CommandDispatcher:
	var dispatcher: CommandDispatcher = CommandDispatcher.new(_config)
	var response: Dictionary = _request(dispatcher, "newGame", {"sectName": "验收宗", "playerFaction": Enums.FactionType.ZONG_MEN,
		"mapWidth": 24, "mapHeight": 18, "randomSeed": seed, "difficultyId": "normal"})
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


## 第 index 名弟子（0 起）；不足时回落到最后一名。
func _disciple(sect: Sect, index: int) -> Disciple:
	if sect == null or sect.disciples.is_empty(): return null
	return sect.disciples[mini(index, sect.disciples.size() - 1)]


func _disciple_id(sect: Sect, index: int) -> String:
	var disciple: Disciple = _disciple(sect, index)
	return "" if disciple == null else disciple.id


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
