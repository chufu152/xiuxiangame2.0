extends Node
## R5 自动验收：十兵种 + 战力/胜率/相克/地形防御/城防/围城 + 野战/夺峰/夺点 +
## 撤退/传送/驻守 + 转职/晋升 + 经验等级 + 批量移动 + ZOC + 确定性。
##
## 无头运行：`godot --headless --path server res://tests/R5Test.tscn`，
## 全绿打印 `R5_PASS checks=N` 并退出码 0，否则 `R5_FAIL ...` 退出码 1。
##
## **断言原则**：
## 1. 期望值一律**从 `data/gameConfig.json` 独立复算**，不拿被测函数的返回值当自己的判据；
## 2. 需要「必赢」的场景把攻方堆到碾压线（`powerRatioThreshold`）以上，使 `attackerWon`
##    与 `rounds` 完全确定、不消耗随机数——这样断言可复现，而不是靠运气；
## 3. 需要「必定随机」的场景（撤退、败方结局）只断言**不变式**（成功则换格、失败则移动力归零），
##    外加对概率/参数的独立复算，不断言具体结果；
## 4. 每组测试都新建一局（`_new_game`），避免上一组改过的地块/单位污染下一组。

const R5_COMMANDS: Array[String] = [
	Commands.BATCH_MOVE, Commands.ATTACK, Commands.QUERY_ATTACK_PREVIEW, Commands.QUERY_ATTACKABLE,
	Commands.RETREAT, Commands.TELEPORT, Commands.QUERY_TELEPORT_OPTIONS,
	Commands.ASSIGN_GARRISON, Commands.WITHDRAW_GARRISON, Commands.RECLASS, Commands.PROMOTE,
	Commands.QUERY_DISCIPLE_DETAIL,
]

## 只读命令：必须回 `view=null`（PROTOCOL §3）。
const READ_ONLY_R5: Array[String] = [
	Commands.QUERY_ATTACK_PREVIEW, Commands.QUERY_ATTACKABLE,
	Commands.QUERY_TELEPORT_OPTIONS, Commands.QUERY_DISCIPLE_DETAIL,
]

var _failures: Array[String] = []
var _checks: int = 0
var _config: Dictionary = {}
var _finished: bool = false
var _started: int = Time.get_ticks_msec()


func _process(_delta: float) -> void:
	if not _finished and Time.get_ticks_msec() - _started > 300000:
		printerr("R5_FAIL 测试未正常完成（可能运行时脚本错误）")
		get_tree().quit(1)


func _ready() -> void:
	var loaded: Dictionary = ConfigLoader.load_from_file(ConfigLoader.default_path())
	_check(bool(loaded["ok"]), "配置可加载")
	_config = loaded["config"]
	_check(ConfigValidator.validate(_config).is_empty(), "配置通过深层验证")
	_test_registration()
	_test_unit_classes()
	_test_combat_power()
	_test_counters()
	_test_terrain_defense()
	_test_preview_matches_resolve()
	_test_ranged_retaliation()
	_test_fortification()
	_test_siege_and_contest()
	_test_supply_line()
	_test_zoc()
	_test_retreat()
	_test_teleport()
	_test_garrison()
	_test_reclass()
	_test_promote()
	_test_experience()
	_test_batch_move()
	_test_disciple_detail()
	_test_determinism()
	_finished = true
	if _failures.is_empty():
		print("R5_PASS checks=%d" % _checks)
		get_tree().quit(0)
	else:
		for failure: String in _failures:
			printerr("R5_FAIL " + failure)
		printerr("R5_FAIL checks=%d failures=%d" % [_checks, _failures.size()])
		get_tree().quit(1)


# ---------------------------------------------------------------------------
# 1. 命令注册与只读契约
# ---------------------------------------------------------------------------

func _test_registration() -> void:
	var dispatcher: CommandDispatcher = CommandDispatcher.new(_config)
	var implemented: Array = dispatcher.implemented_commands()
	for command: String in R5_COMMANDS:
		_check(implemented.has(command), "已登记 R5 命令：" + command)
	_check(implemented.size() >= 40, "已登记命令不少于 R5 的 40 条（28 + 12）")
	for command: String in R5_COMMANDS:
		var response: Dictionary = _request(dispatcher, command, {})
		_check(response.get("errorCode") == "NO_GAME", "%s 开局前 NO_GAME" % command)
	# 开局后：只读命令 view 必须为 null。
	var game: CommandDispatcher = _new_game("5001")
	var disciple_id: String = _disciple(_player(game), 1).id
	var read_only_params: Dictionary = {
		Commands.QUERY_ATTACK_PREVIEW: {"discipleId": disciple_id, "targetTileId": _disciple(_player(game), 1).tileId},
		Commands.QUERY_ATTACKABLE: {"discipleId": disciple_id},
		Commands.QUERY_TELEPORT_OPTIONS: {"discipleId": disciple_id},
		Commands.QUERY_DISCIPLE_DETAIL: {"discipleId": disciple_id},
	}
	for command: String in READ_ONLY_R5:
		var response: Dictionary = _request(game, command, read_only_params[command])
		_check(response.get("view") == null, "只读命令 %s 的 view 必须为 null" % command)
	# 参数缺失/枚举非法 → BAD_PARAMS（协议层失败，不是业务失败）。
	_check(_request(game, Commands.RECLASS, {"discipleId": disciple_id, "unitClass": "NOT_A_CLASS"}).get("errorCode") == "BAD_PARAMS", "reclass 非法 unitClass 回 BAD_PARAMS")
	_check(_request(game, Commands.RECLASS, {"discipleId": disciple_id}).get("errorCode") == "BAD_PARAMS", "reclass 缺 unitClass 回 BAD_PARAMS")
	_check(_request(game, Commands.ATTACK, {"discipleId": disciple_id}).get("errorCode") == "BAD_PARAMS", "attack 缺 targetTileId 回 BAD_PARAMS")
	_check(_request(game, Commands.TELEPORT, {"discipleId": disciple_id, "peakId": "x"}).get("errorCode") == "BAD_PARAMS", "teleport 不接受 peakId（裁决五只认 targetPeakId）")
	_check(_request(game, Commands.BATCH_MOVE, {"sectId": _player(game).id, "discipleIds": "not-an-array", "targetTileId": _disciple(_player(game), 1).tileId}).get("errorCode") == "BAD_PARAMS", "batchMove 非数组 discipleIds 回 BAD_PARAMS")


# ---------------------------------------------------------------------------
# 2. 十兵种
# ---------------------------------------------------------------------------

func _test_unit_classes() -> void:
	var classes: Dictionary = _config["warfare"]["unitClasses"]
	_check(classes.size() == 10, "兵种表 10 种（实际 %d）" % classes.size())
	_check(Enums.UnitClass.ALL.size() == 10, "Enums.UnitClass.ALL 10 种")
	var dispatcher: CommandDispatcher = _new_game("5002")
	var disciple: Disciple = _disciple(_player(dispatcher), 1)
	for unit_class: String in Enums.UnitClass.ALL:
		var expected: Dictionary = classes[unit_class]
		# 独立复算：直接读配置，不经过 UnitRules 的取值路径。
		var attack: float = float(expected["attack"])
		var defense: float = float(expected["defense"])
		var reach: int = int(expected["range"])
		var mobility: int = int(expected["moveBonus"])
		var retaliation: float = float(expected["retaliation"])
		var vision: int = int(expected["visionBonus"])
		var siege: float = float(expected["siegeBonus"])
		# 无晋升 → 加成全 0，故 UnitRules 结果必须等于配置原值。
		disciple.unitClass = unit_class
		disciple.promotions = []
		_check(is_equal_approx(UnitRules.attack_multiplier(_config, disciple), attack), "%s attack=%s" % [unit_class, attack])
		_check(is_equal_approx(UnitRules.defense_multiplier(_config, disciple), defense), "%s defense=%s" % [unit_class, defense])
		_check(UnitRules.range_of(_config, disciple) == maxi(1, reach), "%s range=%d" % [unit_class, reach])
		_check(UnitRules.move_bonus(_config, disciple) == mobility, "%s moveBonus=%d" % [unit_class, mobility])
		_check(is_equal_approx(UnitRules.retaliation_of(_config, disciple), retaliation), "%s retaliation=%s" % [unit_class, retaliation])
		_check(UnitRules.vision_bonus(_config, disciple) == vision, "%s visionBonus=%d" % [unit_class, vision])
		_check(is_equal_approx(UnitRules.siege_bonus(_config, disciple), siege), "%s siegeBonus=%s" % [unit_class, siege])
		_check(UnitRules.kind_of(_config, disciple) == str(expected["kind"]), "%s kind=%s" % [unit_class, str(expected["kind"])])
		# 门槛与转职成本：寻常弟子为 0，其余必须为正。
		var min_realm: int = int(expected["minRealmLevel"])
		var min_root: int = int(expected["minRootGrade"])
		_check(min_realm >= 1 and min_root >= 1, "%s 门槛字段有效" % unit_class)
		if unit_class == Enums.UnitClass.PU_TONG:
			_check(int(expected["reclassSpiritPower"]) == 0 and int(expected["reclassSpiritStones"]) == 0, "寻常弟子转职成本为 0")
		else:
			_check(int(expected["reclassSpiritPower"]) > 0 and int(expected["reclassSpiritStones"]) > 0, "%s 转职成本为正" % unit_class)
	# 裁决七：moveBonus 非 0 的四个兵种逐个点名（配置口径）。
	_check(UnitRules.move_bonus(_config, _with_class(disciple, "QI_JI")) == 2, "御兽骑乘 moveBonus=+2")
	_check(UnitRules.move_bonus(_config, _with_class(disciple, "XUE_MAI_XIU_SHI")) == 1, "血脉修士 moveBonus=+1")
	_check(UnitRules.move_bonus(_config, _with_class(disciple, "JI_GUAN")) == -1, "机关傀儡 moveBonus=-1")
	_check(UnitRules.move_bonus(_config, _with_class(disciple, "JI_GUAN_JUN_TUAN")) == -1, "机关军团 moveBonus=-1")
	# 攻城单位判定：`siegeBonus >= siegeRequirement`（1.0 口径）。
	_check(not UnitRules.is_siege_unit(_config, _with_class(disciple, "PU_TONG")), "寻常弟子不是攻城单位")
	_check(UnitRules.is_siege_unit(_config, _with_class(disciple, "JI_GUAN")), "机关傀儡是攻城单位")
	_check(UnitRules.is_siege_unit(_config, _with_class(disciple, "FU_XIU")), "符修攻城能力 1.0 达阈值")
	# 非法兵种回落寻常弟子（旧档兼容），不崩。
	disciple.unitClass = "NOT_A_CLASS"
	_check(UnitRules.class_of(disciple) == Enums.UnitClass.PU_TONG, "非法兵种回落寻常弟子")


# ---------------------------------------------------------------------------
# 3. 战力公式
# ---------------------------------------------------------------------------

func _test_combat_power() -> void:
	var combat: Dictionary = _config["combat"]
	var dispatcher: CommandDispatcher = _new_game("5003")
	var state: GameState = dispatcher.state
	var disciple: Disciple = _disciple(_player(dispatcher), 1)
	disciple.unitClass = Enums.UnitClass.PU_TONG
	disciple.promotions = []
	var realm_level: int = 3
	var root_grade: int = 2
	disciple.realm = Enums.Realm.JIN_DAN
	disciple.realmLevel = realm_level
	disciple.rootGrade = root_grade
	# 独立复算：境界等级×权重 + 灵根品级×权重（无道法加成时 COMBAT_BONUS=0）。
	var base: float = float(realm_level) * float(combat["realmPowerWeight"]) + float(root_grade) * float(combat["rootGradePowerWeight"])
	disciple.injured = false
	disciple.heartDevil = 0
	_check(CombatResolver.compute_power(state, _config, disciple) == int(round(base)), "基础战力 = %d" % int(round(base)))
	# 重伤 ×(1−injuryPowerPenalty)
	disciple.injured = true
	_check(CombatResolver.compute_power(state, _config, disciple) == int(round(base * (1.0 - float(combat["injuryPowerPenalty"])))), "重伤战力折减")
	disciple.injured = false
	# 心魔低段（≥50）
	disciple.heartDevil = int(combat["heartDevilLowThreshold"])
	_check(CombatResolver.compute_power(state, _config, disciple) == int(round(base * (1.0 - float(combat["heartDevilLowPenalty"])))), "心魔低段战力折减")
	# 心魔高段（≥80）：高段优先于低段，不叠加
	disciple.heartDevil = int(combat["heartDevilHighThreshold"])
	_check(CombatResolver.compute_power(state, _config, disciple) == int(round(base * (1.0 - float(combat["heartDevilHighPenalty"])))), "心魔高段战力折减（不叠加低段）")
	disciple.heartDevil = int(combat["heartDevilHighThreshold"]) - 1
	_check(CombatResolver.compute_power(state, _config, disciple) == int(round(base * (1.0 - float(combat["heartDevilLowPenalty"])))), "心魔 79 仍按低段计")
	# 胜率：碾压与均势两个分支。
	_check(is_equal_approx(CombatResolver.estimate_win_chance(_config, 150, 100), 1.0), "战力比 1.5 即碾压（强方胜率 1.0）")
	_check(is_equal_approx(CombatResolver.estimate_win_chance(_config, 100, 150), 0.0), "战力比 1.5 即碾压（弱方胜率 0.0）")
	var even: float = float(combat["baseWinChance"])
	_check(is_equal_approx(CombatResolver.estimate_win_chance(_config, 100, 100), even), "势均力敌胜率 = baseWinChance")
	var upper: float = float(combat["baseWinChance"]) + 0.5 * 20.0 / 140.0
	_check(is_equal_approx(CombatResolver.estimate_win_chance(_config, 80, 60), upper), "均势公式 = base + 0.5×(攻−防)/(攻+防)（80/60 未达碾压线）")


# ---------------------------------------------------------------------------
# 4. 相克矩阵
# ---------------------------------------------------------------------------

func _test_counters() -> void:
	var counters: Dictionary = _config["warfare"]["counters"]
	_check(counters.size() == 8, "相克矩阵 8 组（实际 %d）" % counters.size())
	var pairs: int = 0
	for attacker_class: String in counters:
		var row: Dictionary = counters[attacker_class]
		for defender_class: String in row:
			pairs += 1
			_check(is_equal_approx(UnitRules.counter_multiplier(_config, attacker_class, defender_class), float(row[defender_class])),
				"相克 %s→%s = %s" % [attacker_class, defender_class, str(row[defender_class])])
	_check(pairs == 15, "相克条目共 15 条（实际 %d）" % pairs)
	# 无条目 → 1.0（不克不被克）。
	_check(is_equal_approx(UnitRules.counter_multiplier(_config, "PU_TONG", "JIAN_XIU"), 1.0), "无相克条目返回 1.0")
	_check(is_equal_approx(UnitRules.counter_multiplier(_config, "NOT_A_CLASS", "PU_TONG"), 1.0), "未知攻方兵种返回 1.0")
	_check(is_equal_approx(UnitRules.counter_multiplier(_config, "JIAN_XIU", "NOT_A_CLASS"), 1.0), "未知守方兵种返回 1.0")


# ---------------------------------------------------------------------------
# 5. 地形防御与驻守加成
# ---------------------------------------------------------------------------

func _test_terrain_defense() -> void:
	var relief: Dictionary = _config["map"]["relief"]
	var features: Dictionary = _config["map"]["features"]
	var danger_bonus: float = float(_config["warfare"]["terrainDefenseBonus"]["险地"])
	# 丘陵：取 relief.HILL.defenseBonus
	var hill: HexTile = _tile()
	hill.relief = Enums.Relief.HILL
	_check(is_equal_approx(UnitRules.terrain_defense_bonus(_config, hill), float(relief["HILL"]["defenseBonus"])), "丘陵地形防御 +0.2")
	# 灵林：FLAT + SPIRIT_FOREST
	var forest: HexTile = _tile()
	forest.relief = Enums.Relief.FLAT
	forest.features = [Enums.Feature.SPIRIT_FOREST]
	_check(is_equal_approx(UnitRules.terrain_defense_bonus(_config, forest), float(features["SPIRIT_FOREST"]["defenseBonus"])), "灵林地形防御 +0.2")
	# 雾泽：−0.1（负加成）
	var mire: HexTile = _tile()
	mire.relief = Enums.Relief.FLAT
	mire.features = [Enums.Feature.MIRE]
	_check(is_equal_approx(UnitRules.terrain_defense_bonus(_config, mire), float(features["MIRE"]["defenseBonus"])), "雾泽地形防御 -0.1")
	# 险地：与 terrainDefenseBonus['险地'] 取大
	var danger: HexTile = _tile()
	danger.relief = Enums.Relief.FLAT
	danger.danger = true
	_check(is_equal_approx(UnitRules.terrain_defense_bonus(_config, danger), danger_bonus), "险地地形防御 0.25")
	# 险地 + 丘陵：取大而非叠加（0.25 > 0.2）
	var hill_danger: HexTile = _tile()
	hill_danger.relief = Enums.Relief.HILL
	hill_danger.danger = true
	_check(is_equal_approx(UnitRules.terrain_defense_bonus(_config, hill_danger), danger_bonus), "险地叠丘陵取大 0.25")
	# 丘陵 + 灵林：两层叠加（0.2 + 0.2）
	var hill_forest: HexTile = _tile()
	hill_forest.relief = Enums.Relief.HILL
	hill_forest.features = [Enums.Feature.SPIRIT_FOREST]
	_check(is_equal_approx(UnitRules.terrain_defense_bonus(_config, hill_forest),
		float(relief["HILL"]["defenseBonus"]) + float(features["SPIRIT_FOREST"]["defenseBonus"])), "丘陵+灵林叠加 0.4")
	# 平原无加成
	var flat: HexTile = _tile()
	flat.relief = Enums.Relief.FLAT
	_check(is_equal_approx(UnitRules.terrain_defense_bonus(_config, flat), 0.0), "平原无地形防御")
	_check(is_equal_approx(UnitRules.terrain_defense_bonus(_config, null), 0.0), "空地块防御为 0")
	# 高地：攻方海拔严格更高才有加成
	var high: HexTile = _tile()
	high.relief = Enums.Relief.HILL
	_check(is_equal_approx(UnitRules.high_ground_bonus(_config, high, flat), float(_config["warfare"]["highGroundBonus"])), "踞高下击 +0.15")
	_check(is_equal_approx(UnitRules.high_ground_bonus(_config, flat, high), 0.0), "仰攻无高地加成")
	_check(is_equal_approx(UnitRules.high_ground_bonus(_config, flat, flat), 0.0), "同海拔无高地加成")
	# 跨河：河流在边上，清空边即无惩罚
	_check(is_equal_approx(UnitRules.river_penalty(_config, flat, high), 0.0), "无河岸边时无渡河惩罚")
	# 驻守：站在己方灵峰地块上
	var dispatcher: CommandDispatcher = _new_game("5004")
	var state: GameState = dispatcher.state
	var sect: Sect = _player(dispatcher)
	var peak: SpiritPeak = _capital(sect)
	var disciple: Disciple = _disciple(sect, 1)
	disciple.tileId = peak.tileId
	_check(is_equal_approx(UnitRules.garrison_defense_bonus(state, _config, disciple), float(_config["warfare"]["garrisonDefenseBonus"])), "驻守己方灵峰 +0.15")
	disciple.tileId = _far_tile_id(state, peak.tileId)
	_check(is_equal_approx(UnitRules.garrison_defense_bonus(state, _config, disciple), 0.0), "离开灵峰无驻守加成")


# ---------------------------------------------------------------------------
# 6. 预览 == 实战（裁决三）
# ---------------------------------------------------------------------------

func _test_preview_matches_resolve() -> void:
	var dispatcher: CommandDispatcher = _new_game("5005")
	var state: GameState = dispatcher.state
	var sect: Sect = _player(dispatcher)
	var attacker: Disciple = _disciple(sect, 1)
	var defender: Disciple = _place_enemy_near(state, attacker, "r5-preview-a")
	_check(defender != null, "已放置相邻敌方弟子")
	if defender == null: return
	_make_strong(attacker)
	_make_weak(defender)
	_clear_tile(state.tiles[attacker.tileId])
	_clear_tile(state.tiles[defender.tileId])
	var preview: Dictionary = _result(dispatcher, Commands.QUERY_ATTACK_PREVIEW, {"discipleId": attacker.id, "targetTileId": defender.tileId})
	_check(bool(preview["attackable"]), "相邻敌人可攻击")
	_check(preview["blockedReason"] == "", "可攻击时 blockedReason 为空")
	_check(is_equal_approx(float(preview["winChance"]), 1.0), "碾压场景预览胜率 1.0")
	var attack: Dictionary = _result(dispatcher, Commands.ATTACK, {"discipleId": attacker.id, "targetTileId": defender.tileId})
	_check(bool(attack["success"]), "攻击成功")
	# 裁决三：预览与实战同源 → 战力与胜率必须逐字段相等。
	_check(int(attack["attackerPower"]) == int(preview["attackerPower"]), "预览与实战 attackerPower 一致")
	_check(int(attack["defenderPower"]) == int(preview["defenderPower"]), "预览与实战 defenderPower 一致")
	_check(is_equal_approx(float(attack["winChance"]), float(preview["winChance"])), "预览与实战 winChance 一致")
	_check(int(attack["retaliationPower"]) == int(preview["retaliationPower"]), "预览与实战 retaliationPower 一致")
	_check(bool(attack["ranged"]) == bool(preview["ranged"]), "预览与实战 ranged 一致")
	# 碾压：1 回合、攻方必胜
	_check(bool(attack["attackerWon"]), "碾压场景攻方必胜")
	_check(int(attack["rounds"]) == 1, "碾压场景 1 回合结束")
	# 出手消耗：出手次数 −1、移动力 −attackMoveCost
	_check(attacker.attacksRemaining == 0, "出手后 attacksRemaining 归 0")
	# 第二次出手被拦（业务失败，不是协议失败）
	var again: Dictionary = _result(dispatcher, Commands.ATTACK, {"discipleId": attacker.id, "targetTileId": defender.tileId})
	_check(not bool(again["success"]), "同回合第二次出手被拒")
	_check(str(again["message"]).contains("已出手"), "第二次出手提示已出手")


# ---------------------------------------------------------------------------
# 7. 远程零反击 + 近身反击反噬
# ---------------------------------------------------------------------------

func _test_ranged_retaliation() -> void:
	var dispatcher: CommandDispatcher = _new_game("5006")
	var state: GameState = dispatcher.state
	var sect: Sect = _player(dispatcher)
	var attacker: Disciple = _disciple(sect, 1)
	var defender: Disciple = _place_enemy_near(state, attacker, "r5-ranged-a")
	if defender == null:
		_check(false, "已放置相邻敌方弟子（远程）")
		return
	_make_strong(attacker)
	_make_weak(defender)
	_clear_tile(state.tiles[attacker.tileId])
	_clear_tile(state.tiles[defender.tileId])
	# 贴身：法修射程 3 但距离 1 → 不算远程，守方能反击
	attacker.unitClass = Enums.UnitClass.FA_XIU
	var adjacent: Dictionary = _result(dispatcher, Commands.QUERY_ATTACK_PREVIEW, {"discipleId": attacker.id, "targetTileId": defender.tileId})
	_check(not bool(adjacent["ranged"]), "距离 1 不算远程打击")
	_check(int(adjacent["distance"]) == 1, "贴身距离为 1")
	var expected_retaliation: int = int(round(float(CombatResolver.compute_power(state, _config, defender)) * float(UnitRules.retaliation_of(_config, defender))))
	_check(int(adjacent["retaliationPower"]) == expected_retaliation, "贴身反击 = 守方战力×retaliation(%d)" % expected_retaliation)
	_check(expected_retaliation > 0, "贴身反击大于 0")
	# 拉开到 2 格：射程内但非贴身 → 远程、零反击
	var far_tile: String = _empty_tile_at_distance(state, attacker.tileId, 2)
	_check(not far_tile.is_empty(), "找到距离 2 的地块")
	if far_tile.is_empty(): return
	_clear_tile(state.tiles[far_tile])
	defender.tileId = far_tile
	var ranged: Dictionary = _result(dispatcher, Commands.QUERY_ATTACK_PREVIEW, {"discipleId": attacker.id, "targetTileId": far_tile})
	_check(bool(ranged["ranged"]), "距离 2 判定为远程")
	_check(bool(ranged["beyondMeleeContact"]), "远程时 beyondMeleeContact 为真")
	_check(int(ranged["distance"]) == 2, "远程距离为 2")
	_check(int(ranged["retaliationPower"]) == 0, "远程打击守方零反击")
	# 实打一次：远程零反击 → 胜方心魔不因反击增长
	var heart_before: int = attacker.heartDevil
	var result: Dictionary = _result(dispatcher, Commands.ATTACK, {"discipleId": attacker.id, "targetTileId": far_tile})
	_check(bool(result["attackerWon"]), "远程碾压攻方必胜")
	_check(int(result["retaliationPower"]) == 0, "远程实战零反击")
	_check(attacker.heartDevil == heart_before, "远程胜利无反击心魔反噬")
	# 近身胜战的反噬：max(1, 反击/10)
	var melee: CommandDispatcher = _new_game("5007")
	var melee_state: GameState = melee.state
	var melee_sect: Sect = _player(melee)
	var melee_attacker: Disciple = _disciple(melee_sect, 1)
	var melee_defender: Disciple = _place_enemy_near(melee_state, melee_attacker, "r5-melee-a")
	if melee_defender == null:
		_check(false, "已放置相邻敌方弟子（近身）")
		return
	_make_strong(melee_attacker)
	_make_weak(melee_defender)
	_clear_tile(melee_state.tiles[melee_attacker.tileId])
	_clear_tile(melee_state.tiles[melee_defender.tileId])
	melee_attacker.heartDevil = 0
	var melee_result: Dictionary = _result(melee, Commands.ATTACK, {"discipleId": melee_attacker.id, "targetTileId": melee_defender.tileId})
	_check(bool(melee_result["attackerWon"]), "近身碾压攻方必胜")
	var expected_backlash: int = maxi(1, int(melee_result["retaliationPower"]) / 10)
	_check(melee_attacker.heartDevil == expected_backlash, "近身胜战心魔反噬 +%d" % expected_backlash)
	var notes: Array = melee_result["notes"]
	var found_note: bool = false
	for note: Variant in notes:
		if str(note).contains("心魔反噬"): found_note = true
	_check(found_note, "战报 notes 含心魔反噬说明")


# ---------------------------------------------------------------------------
# 8. 城防：非攻城单位输出打折，攻城单位不打折
# ---------------------------------------------------------------------------

func _test_fortification() -> void:
	var dispatcher: CommandDispatcher = _new_game("5008")
	var state: GameState = dispatcher.state
	var sect: Sect = _player(dispatcher)
	var attacker: Disciple = _disciple(sect, 1)
	var enemy_sect: Sect = _enemy_sect(state)
	_check(enemy_sect != null, "存在敌方宗门")
	if enemy_sect == null: return
	var enemy_peak: SpiritPeak = _capital(enemy_sect)
	var target_tile: String = _neighbor_tile(state, attacker.tileId)
	_check(not target_tile.is_empty(), "找到夺峰目标地块")
	if target_tile.is_empty(): return
	# 把敌方灵峰挪到攻击者相邻格，并把该峰城防设为固定值（隔离其他变量）。
	enemy_peak.tileId = target_tile
	enemy_peak.sectId = enemy_sect.id
	enemy_peak.defense = 20
	enemy_peak.siegeTurns = 0
	state.tiles[target_tile].ownerSectId = enemy_sect.id
	_clear_tile(state.tiles[attacker.tileId])
	_clear_tile(state.tiles[target_tile])
	_make_strong(attacker)
	# 清空该峰守军，避免守方战力干扰（只验证城防对攻方输出的打折）。
	for other: Disciple in enemy_sect.disciples:
		if other.tileId == target_tile or other.assignedPeakId == enemy_peak.id:
			other.tileId = _far_tile_id(state, target_tile)
			other.assignedPeakId = ""
	var fort_ratio: float = float(_config["warfare"]["fortificationRatio"])
	var base_power: float = float(CombatResolver.compute_power(state, _config, attacker))
	# 非攻城单位：输出 ×fortificationRatio
	attacker.unitClass = Enums.UnitClass.PU_TONG
	var plain: Dictionary = _result(dispatcher, Commands.QUERY_ATTACK_PREVIEW, {"discipleId": attacker.id, "targetTileId": target_tile})
	var plain_expected: int = int(round(base_power * float(UnitRules.class_config(_config, "PU_TONG")["attack"]) * fort_ratio))
	_check(int(plain["attackerPower"]) == plain_expected, "非攻城单位输出打折：%d == %d" % [int(plain["attackerPower"]), plain_expected])
	# 攻城单位：输出不打折
	attacker.unitClass = Enums.UnitClass.JI_GUAN
	var siege: Dictionary = _result(dispatcher, Commands.QUERY_ATTACK_PREVIEW, {"discipleId": attacker.id, "targetTileId": target_tile})
	var siege_expected: int = int(round(base_power * float(UnitRules.class_config(_config, "JI_GUAN")["attack"])))
	_check(int(siege["attackerPower"]) == siege_expected, "攻城单位输出不打折：%d == %d" % [int(siege["attackerPower"]), siege_expected])
	# 城防计入守方战力：defenderPower 至少含 peak.defense×(1−折减)
	_check(int(siege["defenderPower"]) >= int(round(float(enemy_peak.defense))), "城防计入守方战力")
	var has_fort_note: bool = false
	for note: Variant in plain["notes"]:
		if str(note).contains("城防"): has_fort_note = true
	_check(has_fort_note, "非攻城单位预览含城防说明")


# ---------------------------------------------------------------------------
# 9. 夺峰 / 夺点
# ---------------------------------------------------------------------------

func _test_siege_and_contest() -> void:
	# --- 夺峰 ---
	var dispatcher: CommandDispatcher = _new_game("5009")
	var state: GameState = dispatcher.state
	var sect: Sect = _player(dispatcher)
	var attacker: Disciple = _disciple(sect, 1)
	var enemy_sect: Sect = _enemy_sect(state)
	if enemy_sect == null:
		_check(false, "存在敌方宗门（夺峰）")
		return
	var peak: SpiritPeak = _capital(enemy_sect)
	var target: String = _neighbor_tile(state, attacker.tileId)
	if target.is_empty():
		_check(false, "找到夺峰目标地块")
		return
	peak.tileId = target
	peak.sectId = enemy_sect.id
	peak.defense = 1
	peak.siegeTurns = 0
	state.tiles[target].ownerSectId = enemy_sect.id
	for other: Disciple in enemy_sect.disciples:
		if other.tileId == target or other.assignedPeakId == peak.id:
			other.tileId = _far_tile_id(state, target)
			other.assignedPeakId = ""
	_clear_tile(state.tiles[attacker.tileId])
	_clear_tile(state.tiles[target])
	_make_strong(attacker)
	var peaks_before: int = sect.spiritPeaks.size()
	var enemy_peaks_before: int = enemy_sect.spiritPeaks.size()
	var result: Dictionary = _result(dispatcher, Commands.ATTACK, {"discipleId": attacker.id, "targetTileId": target})
	_check(bool(result["success"]), "夺峰攻击成功")
	_check(bool(result["attackerWon"]), "夺峰攻方必胜（碾压）")
	_check(str(result["outcome"]) == Enums.CombatOutcome.SIEGE_OCCUPIED, "夺峰结局 = SIEGE_OCCUPIED")
	_check(sect.spiritPeaks.size() == peaks_before + 1, "夺峰后攻方灵峰 +1")
	_check(enemy_sect.spiritPeaks.size() == enemy_peaks_before - 1, "夺峰后守方灵峰 -1")
	_check(peak.sectId == sect.id, "灵峰归属改为攻方")
	_check(state.tiles[target].ownerSectId == sect.id, "灵峰地块所有权改为攻方")
	_check(peak.fengZhuId == "", "易主后峰主清空")

	# --- 夺点 ---
	var contest: CommandDispatcher = _new_game("5010")
	var cstate: GameState = contest.state
	var csect: Sect = _player(contest)
	var cunit: Disciple = _disciple(csect, 1)
	var cenemy: Sect = _enemy_sect(cstate)
	if cenemy == null:
		_check(false, "存在敌方宗门（夺点）")
		return
	var node_tile: String = _neighbor_tile(cstate, cunit.tileId)
	if node_tile.is_empty():
		_check(false, "找到夺点目标地块")
		return
	var node: GameNode = GameNode.new()
	node.id = "r5_node"
	node.type = Enums.NodeType.LING_TIAN
	node.tileId = node_tile
	node.ownerSectId = cenemy.id
	node.level = 1
	cstate.nodes[node.id] = node
	cstate.tiles[node_tile].nodeId = node.id
	cstate.tiles[node_tile].ownerSectId = cenemy.id
	_clear_tile(cstate.tiles[cunit.tileId])
	_clear_tile(cstate.tiles[node_tile])
	_make_strong(cunit)
	var contest_result: Dictionary = _result(contest, Commands.ATTACK, {"discipleId": cunit.id, "targetTileId": node_tile})
	_check(bool(contest_result["success"]), "夺点攻击成功")
	_check(bool(contest_result["attackerWon"]), "夺点攻方必胜（守军为空 → 0 回合）")
	_check(int(contest_result["rounds"]) == 0, "空节点争夺 0 回合")
	_check(str(contest_result["outcome"]) == Enums.CombatOutcome.CONTEST_WON, "夺点结局 = CONTEST_WON")
	_check(node.ownerSectId == csect.id, "节点归属改为攻方")
	_check(cstate.tiles[node_tile].ownerSectId == csect.id, "节点地块所有权改为攻方")


# ---------------------------------------------------------------------------
# 10. 围城与补给线
# ---------------------------------------------------------------------------

func _test_supply_line() -> void:
	var dispatcher: CommandDispatcher = _new_game("5011")
	var state: GameState = dispatcher.state
	var sect: Sect = _player(dispatcher)
	var peak: SpiritPeak = _capital(sect)
	var enemy_sect: Sect = _enemy_sect(state)
	if enemy_sect == null:
		_check(false, "存在敌方宗门（围城）")
		return
	var center: HexTile = state.tiles[peak.tileId]
	# 初态：相邻有无主地块 → 有补给
	_check(UnitRules.has_supply_line(state, _config, peak), "开局灵峰有补给线")
	_check(UnitRules.update_attrition(state, _config, peak) == false, "有补给时不累计围城")
	_check(peak.siegeTurns == 0, "有补给时 siegeTurns 为 0")
	# 把所有相邻地块划给敌方 → 断供
	var neighbors: Array[String] = []
	for coords: Vector2i in Hex.neighbors(Vector2i(center.q, center.r)):
		var tile_id: String = Hex.id(coords.x, coords.y)
		if not state.tiles.has(tile_id): continue
		state.tiles[tile_id].ownerSectId = enemy_sect.id
		neighbors.append(tile_id)
	_check(neighbors.size() > 0, "灵峰有相邻地块")
	_check(not UnitRules.has_supply_line(state, _config, peak), "相邻全为敌占 → 无补给线")
	# 逐回合累计，折减按 defenseCutPerTurn 递增并封顶 maxDefenseCut
	var per_turn: float = float(_config["warfare"]["defenseCutPerTurn"])
	var maximum: float = float(_config["warfare"]["maxDefenseCut"])
	var max_turns: int = int(ceil(maximum / per_turn))
	for index: int in range(max_turns):
		UnitRules.update_attrition(state, _config, peak)
		_check(peak.siegeTurns == index + 1, "围城回合累计至 %d" % (index + 1))
		var expected_cut: float = minf(maximum, per_turn * float(index + 1))
		_check(is_equal_approx(UnitRules.siege_defense_cut(_config, peak), expected_cut), "围城第 %d 回合城防折减 %.2f" % [index + 1, expected_cut])
	# 超过上限后不再增加折减
	UnitRules.update_attrition(state, _config, peak)
	_check(is_equal_approx(UnitRules.siege_defense_cut(_config, peak), maximum), "折减封顶 maxDefenseCut=%.2f" % maximum)
	_check(UnitRules.turns_to_breach(_config, peak) == 0, "已达折减上限时剩余回合为 0")
	# 恢复一个无主相邻地块 → 补给恢复、siegeTurns 清零
	state.tiles[neighbors[0]].ownerSectId = ""
	_check(UnitRules.has_supply_line(state, _config, peak), "恢复一处相邻无主地 → 补给恢复")
	_check(UnitRules.update_attrition(state, _config, peak) == false, "补给恢复后不再被围")
	_check(peak.siegeTurns == 0, "补给恢复后 siegeTurns 清零")
	_check(is_equal_approx(UnitRules.siege_defense_cut(_config, peak), 0.0), "补给恢复后城防折减归零")
	# 回合阶段：断供时 `_run_spirit_peak` 会推进 siegeTurns（端到端）
	for tile_id: String in neighbors:
		state.tiles[tile_id].ownerSectId = enemy_sect.id
	_request(dispatcher, Commands.BEGIN_PLAYER_TURN, {})
	_check(peak.siegeTurns >= 1, "回合开始阶段推进围城计数（实测 %d）" % peak.siegeTurns)


# ---------------------------------------------------------------------------
# 11. ZOC 控制区（裁决一）
# ---------------------------------------------------------------------------

func _test_zoc() -> void:
	var dispatcher: CommandDispatcher = _new_game("5012")
	var state: GameState = dispatcher.state
	var sect: Sect = _player(dispatcher)
	var mover: Disciple = _disciple(sect, 1)
	var enemy: Disciple = _place_enemy_near(state, mover, "r5-zoc-a")
	if enemy == null:
		_check(false, "已放置相邻敌方弟子（ZOC）")
		return
	# 目标格：与 mover 相邻、且与敌人相邻 —— 让敌人正好压在目标格旁边
	var target_id: String = enemy.tileId
	_clear_tile(state.tiles[mover.tileId])
	_clear_tile(state.tiles[target_id])
	# 敌人占据目标格 → 先验证占格阻挡，再把敌人挪开一格验证 ZOC
	var blocked: int = MoveRules.step_cost(_config, state.tiles[mover.tileId], state.tiles[target_id], sect, state)
	_check(blocked == MoveRules.IMPASSABLE, "敌方占据的格子不可进入（裁决二）")
	# 敌人挪到目标格的另一侧（不与 mover 相邻，但与 target 相邻）
	var flank: String = _tile_at_distance_from(state, target_id, mover.tileId, 2)
	_check(not flank.is_empty(), "找到目标格另一侧的相邻格")
	if flank.is_empty(): return
	_clear_tile(state.tiles[flank])
	enemy.tileId = flank
	# 无 ZOC 的基线代价：平原 1
	var plain_cost: int = MoveRules.step_cost(_config, state.tiles[mover.tileId], state.tiles[target_id], sect, state)
	_check(plain_cost == 1 + int(_config["warfare"]["zocExtraCost"]), "相邻敌方 1 个单位 → ZOC 附加 %d（实际总代价 %d）" % [int(_config["warfare"]["zocExtraCost"]), plain_cost])
	_check(MoveRules.zoc_pressure(state, _config, sect, state.tiles[target_id]) == 1, "ZOC 压力 = 1")
	# 第二个敌人也贴上来 → 压力 2、附加翻倍
	var second: Disciple = _enemy_disciple(state, enemy.sectId, enemy.id)
	if second != null:
		var flank2: String = _tile_at_distance_from(state, target_id, mover.tileId, 1)
		if flank2.is_empty(): flank2 = flank
		if flank2 != flank:
			_clear_tile(state.tiles[flank2])
			second.tileId = flank2
			second.position = Enums.Position.NEI_MEN
			second.injured = false
			second.tribulating = false
			var double_cost: int = MoveRules.step_cost(_config, state.tiles[mover.tileId], state.tiles[target_id], sect, state)
			_check(double_cost == 1 + 2 * int(_config["warfare"]["zocExtraCost"]), "两个相邻敌人 → ZOC 附加翻倍（实际 %d）" % double_cost)
			second.tileId = _far_tile_id(state, target_id)
	# 高亮与实走一致：`queryMoveRange` 的 costs 必须等于 `step_cost` 的累加
	mover.movePoints = 10
	var range_result: Dictionary = _result(dispatcher, Commands.QUERY_MOVE_RANGE, {"discipleId": mover.id})
	var costs: Dictionary = range_result["costs"]
	_check(costs.has(target_id), "ZOC 后目标格仍在可达范围（移动力足够）")
	_check(int(costs[target_id]) == MoveRules.step_cost(_config, state.tiles[mover.tileId], state.tiles[target_id], sect, state), "高亮代价 == 实际单步代价")
	var before_points: int = mover.movePoints
	var move_result: Dictionary = _result(dispatcher, Commands.MOVE_DISCIPLE, {"discipleId": mover.id, "targetTileId": target_id})
	_check(bool(move_result["success"]), "ZOC 下仍可移动（移动力足够）")
	_check(before_points - mover.movePoints == int(costs[target_id]), "实走扣减 == 高亮代价")
	# 关闭 ZOC 开关后不再附加
	_config["warfare"]["zocEnabled"] = false
	_check(MoveRules.zoc_pressure(state, _config, sect, state.tiles[target_id]) == 0, "zocEnabled=false 时压力为 0")
	_check(MoveRules.zoc_extra_cost(state, _config, sect, state.tiles[target_id]) == 0, "zocEnabled=false 时无附加")
	_config["warfare"]["zocEnabled"] = true


# ---------------------------------------------------------------------------
# 12. 撤退
# ---------------------------------------------------------------------------

func _test_retreat() -> void:
	var dispatcher: CommandDispatcher = _new_game("5013")
	var state: GameState = dispatcher.state
	var sect: Sect = _player(dispatcher)
	var disciple: Disciple = _disciple(sect, 1)
	disciple.unitClass = Enums.UnitClass.PU_TONG
	disciple.promotions = []
	disciple.injured = false
	disciple.movePoints = 5
	disciple.attacksRemaining = 1
	# 概率独立复算：base + 晋升 retreat + 骑兵加成 − 重伤惩罚，夹取 [0.05,0.95]
	var base: float = float(_config["warfare"]["retreatBaseChance"])
	_check(is_equal_approx(UnitRules.retreat_chance(_config, disciple), clampf(base, 0.05, 0.95)), "寻常弟子撤退概率 = base")
	disciple.injured = true
	_check(is_equal_approx(UnitRules.retreat_chance(_config, disciple), clampf(base - 0.2, 0.05, 0.95)), "重伤撤退概率 -0.2")
	disciple.injured = false
	disciple.unitClass = Enums.UnitClass.QI_JI
	_check(is_equal_approx(UnitRules.retreat_chance(_config, disciple), clampf(base + float(_config["warfare"]["retreatMobileBonus"]), 0.05, 0.95)), "骑兵撤退概率 +retreatMobileBonus")
	disciple.unitClass = Enums.UnitClass.PU_TONG
	# 撤退到相邻地块：成功则换格、失败则移动力归零（不断言具体成败）
	var target: String = _neighbor_tile(state, disciple.tileId)
	_check(not target.is_empty(), "找到撤退目标地块")
	if target.is_empty(): return
	state.tiles[target].ownerSectId = ""
	var origin: String = disciple.tileId
	var cost: int = int(_config["warfare"]["retreatMoveCost"])
	var before: int = disciple.movePoints
	var result: Dictionary = _result(dispatcher, Commands.RETREAT, {"discipleId": disciple.id, "toTileId": target})
	_check(disciple.attacksRemaining == 0, "撤退后出手次数归零")
	if bool(result["success"]):
		_check(disciple.tileId == target, "撤退成功则换格")
		_check(disciple.movePoints == before - cost, "撤退成功扣 %d 移动力" % cost)
	else:
		_check(disciple.movePoints == 0, "撤退失败移动力归零")
		_check(disciple.tileId == origin, "撤退失败仍在原地")
	var has_chance_note: bool = false
	for note: Variant in result["notes"]:
		if str(note).contains("撤退概率"): has_chance_note = true
	_check(has_chance_note, "撤退战报含概率说明")
	# 非相邻目标 → 业务失败
	var far: String = _empty_tile_at_distance(state, disciple.tileId, 3)
	if not far.is_empty():
		var bad: Dictionary = _result(dispatcher, Commands.RETREAT, {"discipleId": disciple.id, "toTileId": far})
		_check(not bool(bad["success"]), "非相邻撤退被拒")
		_check(str(bad["message"]).contains("相邻"), "非相邻撤退提示相邻")
	# 移动力不足 → 业务失败
	disciple.movePoints = 0
	var poor: Dictionary = _result(dispatcher, Commands.RETREAT, {"discipleId": disciple.id, "toTileId": target})
	_check(not bool(poor["success"]), "移动力不足无法撤退")


# ---------------------------------------------------------------------------
# 13. 传送
# ---------------------------------------------------------------------------

func _test_teleport() -> void:
	var dispatcher: CommandDispatcher = _new_game("5014")
	var state: GameState = dispatcher.state
	var sect: Sect = _player(dispatcher)
	var disciple: Disciple = _disciple(sect, 1)
	var capital: SpiritPeak = _capital(sect)
	disciple.tileId = capital.tileId
	# 造第二座己方灵峰（放在远处地块上）
	var second_tile: String = _far_tile_id(state, capital.tileId)
	var second: SpiritPeak = SpiritPeak.new()
	second.id = "r5_peak_b"
	second.name = "乙峰"
	second.sectId = sect.id
	second.tileId = second_tile
	second.capital = false
	second.level = 1
	sect.spiritPeaks.append(second)
	state.tiles[second_tile].ownerSectId = sect.id
	# 未解锁 chuan_song：不可传送
	var options_locked: Dictionary = _result(dispatcher, Commands.QUERY_TELEPORT_OPTIONS, {"discipleId": disciple.id})
	_check(bool(options_locked["found"]), "传送选项 found=true")
	_check(not bool(options_locked["enabled"]), "未解锁 chuan_song 时 enabled=false")
	_check(int(options_locked["capacity"]) == 0, "未解锁时容量为 0（enabled=false 与 capacity=0 自洽）")
	_check(int(options_locked["remaining"]) == 0, "未解锁时剩余次数为 0")
	var locked: Dictionary = _result(dispatcher, Commands.TELEPORT, {"discipleId": disciple.id, "targetPeakId": second.id})
	_check(not bool(locked["success"]), "未解锁 chuan_song 传送失败")
	_check(str(locked["message"]).contains("道法"), "未解锁提示需推演道法")
	# 解锁 chuan_song 后：容量 = capacityBase + 在守灵脉节点数 × perNode（封顶 capacityMax）
	sect.unlockedDaoIds.append("chuan_song")
	var options: Dictionary = _result(dispatcher, Commands.QUERY_TELEPORT_OPTIONS, {"discipleId": disciple.id})
	_check(bool(options["enabled"]), "解锁 chuan_song 后 enabled=true")
	_check(int(options["capacity"]) == int(_config["teleport"]["capacityBase"]), "无在守灵脉节点时容量 = capacityBase")
	_check(int(options["remaining"]) == int(options["capacity"]), "初始剩余 == 容量")
	_check(str(options["fromPeakId"]) == capital.id, "起点灵峰为所在峰")
	var entries: Array = options["options"]
	_check(entries.size() == 2, "传送选项列出 2 座己方灵峰（实际 %d）" % entries.size())
	for entry: Variant in entries:
		var option: Dictionary = entry
		if str(option["peakId"]) == capital.id:
			_check(not bool(option["allowed"]), "所在峰不可作为传送目标")
		else:
			_check(bool(option["allowed"]), "另一峰可作为传送目标")
			# 花费独立复算：baseStones + 六边距离 × stonesPerHex
			var from_tile: HexTile = state.tiles[capital.tileId]
			var to_tile: HexTile = state.tiles[second_tile]
			var distance: int = Hex.distance(Vector2i(from_tile.q, from_tile.r), Vector2i(to_tile.q, to_tile.r))
			var expected_cost: int = int(_config["teleport"]["baseStones"]) + distance * int(_config["teleport"]["stonesPerHex"])
			_check(int(option["cost"]) == expected_cost, "传送花费 = baseStones + 距离×stonesPerHex(%d)" % expected_cost)
			# 实际传送：扣灵石、计数 +1
			var stones_before: int = int(sect.resources.get("spiritStones", 0))
			var result: Dictionary = _result(dispatcher, Commands.TELEPORT, {"discipleId": disciple.id, "targetPeakId": second.id})
			_check(bool(result["success"]), "传送成功")
			_check(disciple.tileId == second_tile, "传送后弟子在目标峰地块")
			_check(str(result["reachedTileId"]) == second_tile, "MoveResult.reachedTileId 为目标地块")
			_check(stones_before - int(sect.resources.get("spiritStones", 0)) == expected_cost, "扣灵石 = 传送花费")
			_check(sect.teleportsUsedThisTurn == 1, "传送计数 +1")
	# 次数用尽 → 失败
	var exhausted: Dictionary = _result(dispatcher, Commands.TELEPORT, {"discipleId": disciple.id, "targetPeakId": capital.id})
	_check(not bool(exhausted["success"]), "次数用尽后传送失败")
	_check(str(exhausted["message"]).contains("次数"), "次数用尽提示次数")
	# TURN_START 清零
	_request(dispatcher, Commands.BEGIN_PLAYER_TURN, {})
	_check(sect.teleportsUsedThisTurn == 0, "回合开始传送次数清零（回填 R2 的 TODO）")
	var after_reset: Dictionary = _result(dispatcher, Commands.QUERY_TELEPORT_OPTIONS, {"discipleId": disciple.id})
	_check(int(after_reset["remaining"]) == int(after_reset["capacity"]), "清零后剩余恢复为容量")
	# 在守灵脉节点补充次数
	var node: GameNode = GameNode.new()
	node.id = "r5_lingmai"
	node.type = Enums.NodeType.LING_MAI
	node.tileId = _far_tile_id(state, second_tile)
	node.ownerSectId = sect.id
	state.nodes[node.id] = node
	var guard: Disciple = _disciple(sect, 2)
	guard.tileId = node.tileId
	node.garrisonDiscipleIds.append(guard.id)
	guard.garrisonNodeId = node.id
	var boosted: Dictionary = _result(dispatcher, Commands.QUERY_TELEPORT_OPTIONS, {"discipleId": disciple.id})
	var expected_capacity: int = mini(int(_config["teleport"]["capacityBase"]) + int(_config["teleport"]["capacityPerOwnLingMaiNode"]),
		maxi(int(_config["teleport"]["capacityBase"]), int(_config["teleport"]["capacityMax"])))
	_check(int(boosted["capacity"]) == expected_capacity, "在守灵脉节点使容量增至 %d" % expected_capacity)


# ---------------------------------------------------------------------------
# 14. 驻守
# ---------------------------------------------------------------------------

func _test_garrison() -> void:
	var dispatcher: CommandDispatcher = _new_game("5015")
	var state: GameState = dispatcher.state
	var sect: Sect = _player(dispatcher)
	var disciple: Disciple = _disciple(sect, 1)
	# 必须先把弟子挪到**非灵峰地块**：否则撤回驻守后仍会因「站在己方灵峰上」吃加成，断言就失真了。
	var node_tile: String = _far_tile_id(state, _capital(sect).tileId)
	disciple.tileId = node_tile
	var node: GameNode = GameNode.new()
	node.id = "r5_own_node"
	node.type = Enums.NodeType.LING_TIAN
	node.tileId = node_tile
	node.ownerSectId = sect.id
	state.nodes[node.id] = node
	state.tiles[node_tile].nodeId = node.id
	# 未驻守时撤回 → 业务失败
	var empty: Dictionary = _result(dispatcher, Commands.WITHDRAW_GARRISON, {"discipleId": disciple.id})
	_check(not bool(empty["success"]), "未驻守时撤回失败")
	# 驻守成功
	var assigned: Dictionary = _result(dispatcher, Commands.ASSIGN_GARRISON, {"discipleId": disciple.id, "nodeId": node.id})
	_check(bool(assigned["success"]), "驻守成功")
	_check(disciple.garrisonNodeId == node.id, "garrisonNodeId 已写入")
	_check(node.garrisonDiscipleIds.has(disciple.id), "节点驻守名单已包含该弟子")
	_check(str(assigned["reachedTileId"]) == disciple.tileId, "MoveResult.reachedTileId 为节点地块")
	# 驻守后防御加成生效
	_check(is_equal_approx(UnitRules.garrison_defense_bonus(state, _config, disciple), float(_config["warfare"]["garrisonDefenseBonus"])), "驻守己方节点获防御加成")
	# 重复驻守同一节点：幂等，不重复入列
	_result(dispatcher, Commands.ASSIGN_GARRISON, {"discipleId": disciple.id, "nodeId": node.id})
	var count: int = 0
	for entry: String in node.garrisonDiscipleIds:
		if entry == disciple.id: count += 1
	_check(count == 1, "重复驻守不重复入列")
	# 撤回
	var withdrawn: Dictionary = _result(dispatcher, Commands.WITHDRAW_GARRISON, {"discipleId": disciple.id})
	_check(bool(withdrawn["success"]), "撤回驻守成功")
	_check(disciple.garrisonNodeId == "", "撤回后 garrisonNodeId 清空")
	_check(not node.garrisonDiscipleIds.has(disciple.id), "撤回后节点名单移除该弟子")
	_check(is_equal_approx(UnitRules.garrison_defense_bonus(state, _config, disciple), 0.0), "撤回驻守后不再享有节点驻守加成（1.0 语义：需已指派）")
	# 不在节点地块上 → 业务失败
	var other: Disciple = _disciple(sect, 2)
	other.tileId = _far_tile_id(state, node.tileId)
	var wrong: Dictionary = _result(dispatcher, Commands.ASSIGN_GARRISON, {"discipleId": other.id, "nodeId": node.id})
	_check(not bool(wrong["success"]), "不在节点地块上无法驻守")
	_check(str(wrong["message"]).contains("移动"), "提示需先移动到节点地块")
	# 敌方节点 → 业务失败
	var enemy_sect: Sect = _enemy_sect(state)
	if enemy_sect != null:
		node.ownerSectId = enemy_sect.id
		var foreign: Dictionary = _result(dispatcher, Commands.ASSIGN_GARRISON, {"discipleId": disciple.id, "nodeId": node.id})
		_check(not bool(foreign["success"]), "不可驻守敌方节点")
		node.ownerSectId = sect.id


# ---------------------------------------------------------------------------
# 15. 转职
# ---------------------------------------------------------------------------

func _test_reclass() -> void:
	var dispatcher: CommandDispatcher = _new_game("5016")
	var state: GameState = dispatcher.state
	var sect: Sect = _player(dispatcher)
	sect.unlockedDaoIds.append("jian_xiu")
	sect.unlockedDaoIds.append("qi_ji")
	sect.unlockedDaoIds.append("fa_xiu")
	sect.resources["spiritPower"] = 5000
	sect.resources["spiritStones"] = 5000
	sect.resources["materials"] = {"xuan_tie": 20, "tian_jing": 20, "ling_mu": 20}
	var first: Disciple = _disciple(sect, 1)
	var second: Disciple = _disciple(sect, 2)
	# 门槛不足 → 业务失败（炼气一重、灵根 1 品，剑修需二重）
	first.realm = Enums.Realm.LIAN_QI
	first.realmLevel = 1
	first.rootGrade = 1
	first.unitClass = Enums.UnitClass.PU_TONG
	first.reclassCooldown = 0
	var too_low: Dictionary = _result(dispatcher, Commands.RECLASS, {"discipleId": first.id, "unitClass": Enums.UnitClass.JIAN_XIU})
	_check(not bool(too_low["success"]), "境界不足无法转职")
	_check(str(too_low["message"]).contains("修为"), "境界不足提示修为")
	_check(str(too_low["unitClass"]) == Enums.UnitClass.PU_TONG, "失败时 unitClass 仍为原兵种（TrainingResult 三字段）")
	# 达标后转职成功
	first.realm = Enums.Realm.ZHU_JI
	first.realmLevel = 2
	var power_before: int = int(sect.resources["spiritPower"])
	var stones_before: int = int(sect.resources["spiritStones"])
	var ok: Dictionary = _result(dispatcher, Commands.RECLASS, {"discipleId": first.id, "unitClass": Enums.UnitClass.JIAN_XIU})
	_check(bool(ok["success"]), "达标后转职成功")
	_check(str(ok["unitClass"]) == Enums.UnitClass.JIAN_XIU, "TrainingResult.unitClass 为新兵种")
	_check(first.unitClass == Enums.UnitClass.JIAN_XIU, "弟子兵种已更新")
	var jian: Dictionary = _config["warfare"]["unitClasses"]["JIAN_XIU"]
	_check(power_before - int(sect.resources["spiritPower"]) == int(jian["reclassSpiritPower"]), "扣灵力 = reclassSpiritPower")
	_check(stones_before - int(sect.resources["spiritStones"]) == int(jian["reclassSpiritStones"]), "扣灵石 = reclassSpiritStones")
	_check(first.reclassCooldown == int(jian["reclassCooldownTurns"]), "转职后进入冷却 %d 回合" % int(jian["reclassCooldownTurns"]))
	# 冷却中再次转职 → 业务失败
	var cooling: Dictionary = _result(dispatcher, Commands.RECLASS, {"discipleId": first.id, "unitClass": Enums.UnitClass.FA_XIU})
	_check(not bool(cooling["success"]), "冷却中无法再次转职")
	_check(str(cooling["message"]).contains("冷却"), "冷却提示冷却")
	# 冷却逐回合递减，归零后可再转
	_request(dispatcher, Commands.BEGIN_PLAYER_TURN, {})
	_check(first.reclassCooldown == int(jian["reclassCooldownTurns"]) - 1, "回合开始冷却递减")
	# 裁决七：moveBonus 随转职实时改变
	second.realm = Enums.Realm.JIN_DAN
	second.realmLevel = 3
	second.rootGrade = 2
	second.unitClass = Enums.UnitClass.PU_TONG
	second.promotions = []
	second.reclassCooldown = 0
	var move_before: int = MoveRules.calculate_max_move_points(second, _config, state, sect)
	var to_cavalry: Dictionary = _result(dispatcher, Commands.RECLASS, {"discipleId": second.id, "unitClass": Enums.UnitClass.QI_JI})
	_check(bool(to_cavalry["success"]), "转职御兽骑乘成功")
	var move_after: int = MoveRules.calculate_max_move_points(second, _config, state, sect)
	var expected_delta: int = int(_config["warfare"]["unitClasses"]["QI_JI"]["moveBonus"]) - int(_config["warfare"]["unitClasses"]["PU_TONG"]["moveBonus"])
	_check(move_after - move_before == expected_delta, "转职后机动 %+d（实测 %+d）" % [expected_delta, move_after - move_before])
	_check(second.maxMovePoints == move_after, "转职当场刷新 maxMovePoints")
	# 已是该兵种 → 业务失败
	var same: Dictionary = _result(dispatcher, Commands.RECLASS, {"discipleId": second.id, "unitClass": Enums.UnitClass.QI_JI})
	_check(not bool(same["success"]), "转职为当前兵种被拒")
	# 宗主不可转职
	var leader: Disciple = _leader(sect)
	if leader != null:
		leader.realm = Enums.Realm.HUA_SHEN
		leader.realmLevel = 5
		leader.rootGrade = 9
		leader.reclassCooldown = 0
		var lord: Dictionary = _result(dispatcher, Commands.RECLASS, {"discipleId": leader.id, "unitClass": Enums.UnitClass.JIAN_XIU})
		_check(not bool(lord["success"]), "宗主不可转职")
		_check(str(lord["message"]).contains("宗主"), "宗主提示不可转职")
	# 未解锁兵种 → 业务失败
	sect.unlockedDaoIds.clear()
	var locked: Dictionary = _result(dispatcher, Commands.RECLASS, {"discipleId": second.id, "unitClass": Enums.UnitClass.FA_XIU})
	_check(not bool(locked["success"]), "未解锁兵种无法转职")
	_check(str(locked["message"]).contains("道法"), "未解锁提示需道法")


# ---------------------------------------------------------------------------
# 16. 晋升
# ---------------------------------------------------------------------------

func _test_promote() -> void:
	var dispatcher: CommandDispatcher = _new_game("5017")
	var state: GameState = dispatcher.state
	var sect: Sect = _player(dispatcher)
	var disciple: Disciple = _disciple(sect, 1)
	disciple.unitClass = Enums.UnitClass.JIAN_XIU
	disciple.promotions = []
	disciple.promotionPoints = 0
	disciple.battleLevel = 0
	# 无晋升点 → 业务失败
	var no_points: Dictionary = _result(dispatcher, Commands.PROMOTE, {"discipleId": disciple.id, "promotionId": "pro_sword_essence"})
	_check(not bool(no_points["success"]), "无晋升点无法晋升")
	_check(str(no_points["message"]).contains("晋升点"), "提示晋升点不足")
	# 给点后可选列表包含剑修项与通用项，不含其他兵种专属项
	disciple.promotionPoints = 1
	disciple.battleLevel = 1
	var detail: Dictionary = _result(dispatcher, Commands.QUERY_DISCIPLE_DETAIL, {"discipleId": disciple.id})
	var available: Array = detail["availablePromotions"]
	var has_sword: bool = false
	var has_generic: bool = false
	var has_cavalry: bool = false
	for entry: Variant in available:
		var option: Dictionary = entry
		var promotion_id: String = str(option["id"])
		if promotion_id == "pro_sword_essence": has_sword = true
		if promotion_id == "pro_killer_instinct": has_generic = true
		if promotion_id == "pro_swift_hoof": has_cavalry = true
	_check(has_sword, "剑修可选「剑意通明」")
	_check(has_generic, "通用晋升可选「杀伐果断」")
	_check(not has_cavalry, "骑兵专属晋升对剑修不可选")
	# 等级不足的项不可选（pro_flying_sword 需 minLevel 2）
	var flying_visible: bool = false
	for entry: Variant in available:
		if str((entry as Dictionary)["id"]) == "pro_flying_sword": flying_visible = true
	_check(not flying_visible, "等级不足的晋升不出现在可选列表")
	# 晋升成功
	var ok: Dictionary = _result(dispatcher, Commands.PROMOTE, {"discipleId": disciple.id, "promotionId": "pro_sword_essence"})
	_check(bool(ok["success"]), "晋升成功")
	_check(disciple.promotions.has("pro_sword_essence"), "已习得晋升项")
	_check(disciple.promotionPoints == 0, "晋升点 -1")
	_check(str(ok["unitClass"]) == Enums.UnitClass.JIAN_XIU, "TrainingResult.unitClass 为当前兵种")
	# 攻击加成生效：attack = 兵种 attack + 晋升 attack
	var expected_attack: float = float(_config["warfare"]["unitClasses"]["JIAN_XIU"]["attack"]) + 0.15
	_check(is_equal_approx(UnitRules.attack_multiplier(_config, disciple), expected_attack), "晋升攻击加成生效 %.2f" % expected_attack)
	# 已习得的项不再出现在可选列表
	disciple.promotionPoints = 1
	var after: Dictionary = _result(dispatcher, Commands.QUERY_DISCIPLE_DETAIL, {"discipleId": disciple.id})
	var repeat_visible: bool = false
	for entry: Variant in after["availablePromotions"]:
		if str((entry as Dictionary)["id"]) == "pro_sword_essence": repeat_visible = true
	_check(not repeat_visible, "已习得晋升不再出现")
	# 不可选 id → 业务失败
	var invalid: Dictionary = _result(dispatcher, Commands.PROMOTE, {"discipleId": disciple.id, "promotionId": "not_a_promotion"})
	_check(not bool(invalid["success"]), "不存在的晋升被拒")
	# 机动类晋升实时生效：骑兵 + 疾风兽步 move+1
	var cavalry: Disciple = _disciple(sect, 2)
	cavalry.unitClass = Enums.UnitClass.QI_JI
	cavalry.promotions = []
	cavalry.promotionPoints = 1
	cavalry.battleLevel = 1
	var move_before: int = MoveRules.calculate_max_move_points(cavalry, _config, state, sect)
	var hoof: Dictionary = _result(dispatcher, Commands.PROMOTE, {"discipleId": cavalry.id, "promotionId": "pro_swift_hoof"})
	_check(bool(hoof["success"]), "骑兵晋升疾风兽步成功")
	_check(MoveRules.calculate_max_move_points(cavalry, _config, state, sect) - move_before == 1, "机动类晋升 +1 移动力")
	_check(cavalry.maxMovePoints == MoveRules.calculate_max_move_points(cavalry, _config, state, sect), "晋升当场刷新 maxMovePoints")
	# 撤退类晋升加成：retreat +0.15
	_check(is_equal_approx(UnitRules.promotion_bonus(_config, cavalry, "retreat"), 0.15), "疾风兽步 retreat 加成 0.15")


# ---------------------------------------------------------------------------
# 17. 经验与等级
# ---------------------------------------------------------------------------

func _test_experience() -> void:
	var thresholds: Array = _config["warfare"]["levelThresholds"]
	_check(thresholds.size() == 5, "等级阈值 5 档")
	_check(UnitRules.level_for_xp(_config, 0) == 0, "0 经验为 0 级")
	_check(UnitRules.level_for_xp(_config, int(thresholds[1]) - 1) == 0, "%d 经验仍为 0 级" % (int(thresholds[1]) - 1))
	_check(UnitRules.level_for_xp(_config, int(thresholds[1])) == 1, "%d 经验升 1 级" % int(thresholds[1]))
	_check(UnitRules.level_for_xp(_config, int(thresholds[2])) == 2, "%d 经验升 2 级" % int(thresholds[2]))
	_check(UnitRules.level_for_xp(_config, 99999) == thresholds.size() - 1, "越界取最高档")
	var dispatcher: CommandDispatcher = _new_game("5018")
	var disciple: Disciple = _disciple(_player(dispatcher), 1)
	disciple.battleXp = 0
	disciple.battleLevel = 0
	disciple.promotionPoints = 0
	var per_level: int = int(_config["warfare"]["promotionPointsPerLevel"])
	# 一次给足跨 2 级
	var gained: int = UnitRules.award_experience(_config, disciple, int(thresholds[2]))
	_check(gained == 2, "一次跨 2 级")
	_check(disciple.battleLevel == 2, "battleLevel 更新为 2")
	_check(disciple.promotionPoints == 2 * per_level, "每升 1 级给 %d 晋升点" % per_level)
	_check(disciple.battleXp == int(thresholds[2]), "battleXp 累加")
	# 不足升级 → 不给点
	var no_gain: int = UnitRules.award_experience(_config, disciple, 1)
	_check(no_gain == 0, "经验不足不升级")
	_check(disciple.promotionPoints == 2 * per_level, "未升级不给晋升点")
	# 0/负经验不处理
	_check(UnitRules.award_experience(_config, disciple, 0) == 0, "0 经验不处理")
	# 战功经验在实战中发放：胜方拿 xpPerVictory（+击杀/夺目标另计），败方拿 xpPerDefeat
	var state: GameState = dispatcher.state
	var sect: Sect = _player(dispatcher)
	var attacker: Disciple = _disciple(sect, 2)
	var defender: Disciple = _place_enemy_near(state, attacker, "r5-xp-a")
	if defender == null:
		_check(false, "已放置相邻敌方弟子（经验）")
		return
	_make_strong(attacker)
	_make_weak(defender)
	attacker.battleXp = 0
	attacker.battleLevel = 0
	_clear_tile(state.tiles[attacker.tileId])
	_clear_tile(state.tiles[defender.tileId])
	var result: Dictionary = _result(dispatcher, Commands.ATTACK, {"discipleId": attacker.id, "targetTileId": defender.tileId})
	_check(bool(result["attackerWon"]), "经验测试攻方必胜")
	var expected_xp: int = int(_config["warfare"]["xpPerVictory"])
	if str(result["outcome"]) == Enums.CombatOutcome.FALL:
		expected_xp += int(_config["warfare"]["xpPerKill"])
	_check(int(result["xpAwarded"]) >= expected_xp, "xpAwarded 至少含胜方经验 %d（实际 %d）" % [expected_xp, int(result["xpAwarded"])])


# ---------------------------------------------------------------------------
# 18. 批量移动
# ---------------------------------------------------------------------------

func _test_batch_move() -> void:
	var dispatcher: CommandDispatcher = _new_game("5019")
	var state: GameState = dispatcher.state
	var sect: Sect = _player(dispatcher)
	var first: Disciple = _disciple(sect, 1)
	var second: Disciple = _disciple(sect, 2)
	var target: String = _neighbor_tile(state, first.tileId)
	_check(not target.is_empty(), "找到批量移动目标地块")
	if target.is_empty(): return
	state.tiles[target].ownerSectId = sect.id
	var limit: int = int(_config["speed"]["batchMoveMaxTargets"])
	_check(limit == 8, "批量移动上限 8")
	# 超上限 → 业务失败
	var too_many: Array[String] = []
	for index: int in range(limit + 1): too_many.append(first.id)
	var rejected: Dictionary = _result(dispatcher, Commands.BATCH_MOVE, {"sectId": sect.id, "discipleIds": too_many, "targetTileId": target})
	_check(not bool(rejected["success"]), "超上限批量移动被拒")
	_check(str(rejected["message"]).contains(str(limit)), "超上限提示上限值")
	# 正常批量移动：两人都到位
	first.movePoints = 20
	second.movePoints = 20
	second.tileId = first.tileId
	var ok: Dictionary = _result(dispatcher, Commands.BATCH_MOVE, {"sectId": sect.id, "discipleIds": [first.id, second.id], "targetTileId": target})
	_check(bool(ok["success"]), "批量移动成功")
	_check(int(ok["discipleCount"]) == 2, "成功移动 2 人")
	_check(str(ok["targetTileId"]) == target, "result.targetTileId 回显")
	_check(str(ok["sectId"]) == sect.id, "result.sectId 回显")
	_check(first.tileId == target and second.tileId == target, "两名弟子均抵达目标地块")
	_check(str(ok["message"]).contains("移动成功"), "逐人战报在 message")
	# 空列表 → 业务失败
	var empty: Dictionary = _result(dispatcher, Commands.BATCH_MOVE, {"sectId": sect.id, "discipleIds": [], "targetTileId": target})
	_check(not bool(empty["success"]), "空弟子列表被拒")


# ---------------------------------------------------------------------------
# 19. 弟子详情
# ---------------------------------------------------------------------------

func _test_disciple_detail() -> void:
	var dispatcher: CommandDispatcher = _new_game("5020")
	var sect: Sect = _player(dispatcher)
	var disciple: Disciple = _disciple(sect, 1)
	disciple.unitClass = Enums.UnitClass.FA_XIU
	disciple.battleXp = 45
	disciple.battleLevel = 1
	disciple.promotionPoints = 1
	disciple.promotions = ["pro_calm_mind"]
	disciple.reclassCooldown = 2
	disciple.garrisonNodeId = ""
	var detail: Dictionary = _result(dispatcher, Commands.QUERY_DISCIPLE_DETAIL, {"discipleId": disciple.id})
	_check(bool(detail["found"]), "弟子详情 found=true")
	# PROTOCOL §3 全字段逐个点名（缺一即失败）。
	var required: Array[String] = [
		"id", "name", "realm", "realmName", "position", "positionName", "sectId", "sectName",
		"spiritRoots", "spiritRootNames", "spiritRootGrade", "bloodLine", "cultivationProgress",
		"heartDevil", "movePoints", "maxMovePoints", "strikesLeft", "turnsInSect",
		"unitClass", "unitClassName", "range", "reclassCooldown", "battleXp", "battleLevel",
		"promotionPoints", "promotions", "promotionNames", "builderCharges",
		"currentTileId", "currentPeakId", "currentPeakName", "garrisonNodeId", "garrisonNodeName",
		"missionNodeId", "missionNodeName", "injured", "tribulating", "capturedFromSectId",
		"availablePromotions", "availableUnitClasses",
	]
	for field: String in required:
		_check(detail.has(field), "弟子详情含字段 " + field)
	_check(str(detail["unitClass"]) == Enums.UnitClass.FA_XIU, "unitClass 回显")
	_check(str(detail["unitClassName"]) == str(_config["warfare"]["unitClasses"]["FA_XIU"]["displayName"]), "unitClassName 为展示名")
	_check(int(detail["range"]) == int(_config["warfare"]["unitClasses"]["FA_XIU"]["range"]), "range 回显兵种射程")
	_check(int(detail["battleXp"]) == 45 and int(detail["battleLevel"]) == 1, "战功字段回显")
	_check(str(detail["realmName"]) == str(Enums.Realm.NAMES.get(disciple.realm, "")), "realmName 为展示名")
	_check(str(detail["positionName"]) == str(Enums.Position.NAMES.get(disciple.position, "")), "positionName 为展示名")
	var promotions: Array = detail["promotions"]
	var promotion_names: Array = detail["promotionNames"]
	_check(promotions.size() == 1 and str(promotions[0]) == "pro_calm_mind", "promotions 回显")
	_check(promotion_names.size() == 1 and str(promotion_names[0]) == "定心如磐", "promotionNames 为展示名")
	# availableUnitClasses：10 种全列出，各带 allowed/blocker
	var classes: Array = detail["availableUnitClasses"]
	_check(classes.size() == 10, "availableUnitClasses 列 10 种（实际 %d）" % classes.size())
	var plain_blocker: String = ""
	for entry: Variant in classes:
		var option: Dictionary = entry
		_check(option.has("id") and option.has("name") and option.has("allowed") and option.has("blocker"), "兵种选项含 id/name/allowed/blocker")
		if str(option["id"]) == Enums.UnitClass.PU_TONG: plain_blocker = str(option["blocker"])
	# 该弟子 `reclassCooldown=2`，故即便寻常弟子也会被冷却拦住——这正是 blocker 该给出的信息。
	_check(plain_blocker.contains("冷却"), "寻常弟子选项因冷却被拦，blocker 说明冷却（实际：%s）" % plain_blocker)
	# 门槛类 blocker：解除冷却并解锁该兵种道法后，blocker 必须落到「修为/灵根不足」而不是含糊「不可用」。
	# （blocker 的判定顺序是 专属→解锁→冷却→境界→灵根，故必须逐层放开才能测到门槛这一层。）
	sect.unlockedDaoIds.append("ji_guan")
	disciple.reclassCooldown = 0
	var detail2: Dictionary = _result(dispatcher, Commands.QUERY_DISCIPLE_DETAIL, {"discipleId": disciple.id})
	var gate_blocker: String = ""
	for entry: Variant in detail2["availableUnitClasses"]:
		if str((entry as Dictionary)["id"]) == Enums.UnitClass.JI_GUAN: gate_blocker = str((entry as Dictionary)["blocker"])
	_check(gate_blocker.contains("修为") or gate_blocker.contains("灵根"), "高门槛兵种 blocker 说明门槛（实际：%s）" % gate_blocker)
	# 专属兵种：家族流血脉修士对国家流玩家必须是「专属」而非「道法未解锁」。
	var exclusive_blocker: String = ""
	for entry: Variant in detail2["availableUnitClasses"]:
		if str((entry as Dictionary)["id"]) == Enums.UnitClass.XUE_MAI_XIU_SHI: exclusive_blocker = str((entry as Dictionary)["blocker"])
	_check(exclusive_blocker.contains("专属"), "他流派专属兵种 blocker 说明专属（实际：%s）" % exclusive_blocker)
	# 不存在的弟子 → found=false（业务层，不是协议错误）
	var missing: Dictionary = _result(dispatcher, Commands.QUERY_DISCIPLE_DETAIL, {"discipleId": "no_such_disciple"})
	_check(not bool(missing["found"]), "不存在弟子 found=false")
	_check(str(missing["discipleId"]) == "no_such_disciple", "不存在弟子回显 discipleId")


# ---------------------------------------------------------------------------
# 20. 确定性
# ---------------------------------------------------------------------------

func _test_determinism() -> void:
	var left: CommandDispatcher = _new_game("5021")
	var right: CommandDispatcher = _new_game("5021")
	# 均势对战：不达碾压线，会消耗回合数/噪声/结局三处随机。
	for dispatcher: CommandDispatcher in [left, right]:
		var state: GameState = dispatcher.state
		var sect: Sect = _player(dispatcher)
		var attacker: Disciple = _disciple(sect, 1)
		var defender: Disciple = _place_enemy_near(state, attacker, "r5-determinism-a")
		if defender == null: continue
		attacker.realm = Enums.Realm.ZHU_JI
		attacker.realmLevel = 2
		attacker.rootGrade = 2
		attacker.unitClass = Enums.UnitClass.PU_TONG
		attacker.promotions = []
		attacker.injured = false
		attacker.heartDevil = 0
		attacker.attacksRemaining = 1
		attacker.movePoints = 9
		defender.realm = Enums.Realm.ZHU_JI
		defender.realmLevel = 2
		defender.rootGrade = 2
		defender.unitClass = Enums.UnitClass.PU_TONG
		defender.promotions = []
		defender.injured = false
		defender.heartDevil = 0
		_clear_tile(state.tiles[attacker.tileId])
		_clear_tile(state.tiles[defender.tileId])
		# 记录本次对战的完整战报，供两次运行逐字比对。
		dispatcher.set_meta("battle", _result(dispatcher, Commands.ATTACK, {"discipleId": attacker.id, "targetTileId": defender.tileId}))
	var left_report: Dictionary = left.get_meta("battle", {})
	var right_report: Dictionary = right.get_meta("battle", {})
	_check(not left_report.is_empty() and not right_report.is_empty(), "两次运行均产生战报")
	_check(JSON.stringify(left_report) == JSON.stringify(right_report), "同种子同指令 → 战报逐字一致")
	# 关键 view 逐字一致（弟子位置/状态/资源/灵峰归属/视野）
	_check(JSON.stringify(_view(left)) == JSON.stringify(_view(right)), "同种子同指令 → view 逐字一致")
	# 再次同种子跑一遍，确认不是「碰巧相等」
	var third: CommandDispatcher = _new_game("5021")
	var third_state: GameState = third.state
	var third_sect: Sect = _player(third)
	var third_attacker: Disciple = _disciple(third_sect, 1)
	var third_defender: Disciple = _place_enemy_near(third_state, third_attacker, "r5-determinism-a")
	if third_defender != null:
		third_attacker.realm = Enums.Realm.ZHU_JI
		third_attacker.realmLevel = 2
		third_attacker.rootGrade = 2
		third_attacker.unitClass = Enums.UnitClass.PU_TONG
		third_attacker.promotions = []
		third_attacker.injured = false
		third_attacker.heartDevil = 0
		third_attacker.attacksRemaining = 1
		third_attacker.movePoints = 9
		third_defender.realm = Enums.Realm.ZHU_JI
		third_defender.realmLevel = 2
		third_defender.rootGrade = 2
		third_defender.unitClass = Enums.UnitClass.PU_TONG
		third_defender.promotions = []
		third_defender.injured = false
		third_defender.heartDevil = 0
		_clear_tile(third_state.tiles[third_attacker.tileId])
		_clear_tile(third_state.tiles[third_defender.tileId])
		var third_report: Dictionary = _result(third, Commands.ATTACK, {"discipleId": third_attacker.id, "targetTileId": third_defender.tileId})
		_check(JSON.stringify(third_report) == JSON.stringify(left_report), "第三次同种子运行战报仍逐字一致")


# ---------------------------------------------------------------------------
# 测试辅助
# ---------------------------------------------------------------------------

func _new_game(seed: String) -> CommandDispatcher:
	var dispatcher: CommandDispatcher = CommandDispatcher.new(_config)
	var response: Dictionary = _request(dispatcher, "newGame", {"sectName": "验收宗", "playerFaction": Enums.FactionType.ZONG_MEN,
		"mapWidth": 24, "mapHeight": 18, "randomSeed": seed, "difficultyId": "normal"})
	# 开局失败必须显式断言，而不是让后续断言在 null state 上连锁报错（那样失败原因会被淹没）。
	if dispatcher.state == null:
		_check(false, "newGame 失败（seed=%s）：%s" % [seed, str(response.get("message"))])
	return dispatcher


func _request(dispatcher: CommandDispatcher, command: String, params: Dictionary = {}) -> Dictionary:
	return dispatcher.dispatch_text(JSON.stringify({"id": "test", "type": command, "params": params}))


func _result(dispatcher: CommandDispatcher, command: String, params: Dictionary) -> Dictionary:
	var response: Dictionary = _request(dispatcher, command, params)
	return response.get("result", {})


func _view(dispatcher: CommandDispatcher) -> Dictionary:
	return _request(dispatcher, "getState")["view"]


func _player(dispatcher: CommandDispatcher) -> Sect:
	for sect: Sect in dispatcher.state.sects:
		if sect.player: return sect
	return null


func _enemy_sect(state: GameState) -> Sect:
	for sect: Sect in state.sects:
		if not sect.player: return sect
	return null


func _capital(sect: Sect) -> SpiritPeak:
	for peak: SpiritPeak in sect.spiritPeaks:
		if peak.capital: return peak
	return null if sect.spiritPeaks.is_empty() else sect.spiritPeaks[0]


## 第 index 名弟子（0 起）；不足时回落到最后一名。
func _disciple(sect: Sect, index: int) -> Disciple:
	if sect == null or sect.disciples.is_empty(): return null
	return sect.disciples[mini(index, sect.disciples.size() - 1)]


## 宗门领袖（`ZONG_ZHU`），没有则 null。
func _leader(sect: Sect) -> Disciple:
	for disciple: Disciple in sect.disciples:
		if disciple.position == Enums.Position.ZONG_ZHU: return disciple
	return null


## 把某弟子设为「碾压级」攻方：境界/灵根拉满，清空减益。
func _make_strong(disciple: Disciple) -> void:
	disciple.realm = Enums.Realm.HUA_SHEN
	disciple.realmLevel = 5
	disciple.rootGrade = 9
	disciple.unitClass = Enums.UnitClass.PU_TONG
	disciple.promotions = []
	disciple.injured = false
	disciple.tribulating = false
	disciple.heartDevil = 0
	disciple.attacksRemaining = 1
	disciple.movePoints = 99


## 把某弟子设为「碾压级」守方：境界/灵根压到最低。
func _make_weak(disciple: Disciple) -> void:
	disciple.realm = Enums.Realm.LIAN_QI
	disciple.realmLevel = 1
	disciple.rootGrade = 1
	disciple.unitClass = Enums.UnitClass.PU_TONG
	disciple.promotions = []
	disciple.injured = false
	disciple.tribulating = false
	disciple.heartDevil = 0
	disciple.position = Enums.Position.WAI_MEN
	disciple.attacksRemaining = 1
	disciple.movePoints = 99


## 造一个「干净地块」：平原、无地貌、无河、非险地。
## 这样地形/高地/渡河三项修正全为 0，期望值可以精确整数复算。
func _clear_tile(tile: HexTile) -> void:
	if tile == null: return
	tile.relief = Enums.Relief.FLAT
	tile.features.clear()
	tile.riverEdges.clear()
	tile.danger = false


func _tile() -> HexTile:
	return HexTile.new()


func _with_class(disciple: Disciple, unit_class: String) -> Disciple:
	disciple.unitClass = unit_class
	return disciple


## 把某敌方宗门的可战弟子放到 `player_disciple` 相邻格；返回该弟子。
func _place_enemy_near(state: GameState, player_disciple: Disciple, tag: String) -> Disciple:
	var origin: HexTile = state.tiles.get(player_disciple.tileId, null)
	if origin == null: return null
	var enemy: Disciple = _enemy_disciple(state, "", "")
	if enemy == null: return null
	for coords: Vector2i in Hex.neighbors(Vector2i(origin.q, origin.r)):
		var tile_id: String = Hex.id(coords.x, coords.y)
		if not state.tiles.has(tile_id): continue
		if not MoveRules.is_passable(state.tiles[tile_id], _config): continue
		enemy.tileId = tile_id
		enemy.position = Enums.Position.WAI_MEN
		enemy.assignedPeakId = ""
		enemy.injured = false
		enemy.tribulating = false
		enemy.attacksRemaining = 1
		enemy.movePoints = 99
		state.tiles[tile_id].ownerSectId = ""
		return enemy
	_check(false, "找不到可放置敌方单位的地块（%s）" % tag)
	return null


## 取一名非宗主、非峰主的敌方弟子（可战）。`exclude_id` 用于排除已用的那个。
func _enemy_disciple(state: GameState, sect_id: String, exclude_id: String) -> Disciple:
	for sect: Sect in state.sects:
		if sect.player: continue
		if not sect_id.is_empty() and sect.id != sect_id: continue
		for disciple: Disciple in sect.disciples:
			if disciple.id == exclude_id: continue
			if disciple.position == Enums.Position.ZONG_ZHU: continue
			if disciple.position == Enums.Position.FENG_ZHU: continue
			return disciple
	return null


func _neighbor_tile(state: GameState, tile_id: String) -> String:
	var tile: HexTile = state.tiles.get(tile_id, null)
	if tile == null: return ""
	for coords: Vector2i in Hex.neighbors(Vector2i(tile.q, tile.r)):
		var candidate: String = Hex.id(coords.x, coords.y)
		if not state.tiles.has(candidate): continue
		if not MoveRules.is_passable(state.tiles[candidate], _config): continue
		return candidate
	return ""


## 距离 `tile_id` 恰好 `distance` 格的一个可通行地块（广度优先，顺序确定）。
func _tile_at_distance(state: GameState, tile_id: String, distance: int) -> String:
	var origin: HexTile = state.tiles.get(tile_id, null)
	if origin == null: return ""
	var best: String = ""
	var best_delta: int = 9999
	for candidate: HexTile in state.tiles.values():
		if not MoveRules.is_passable(candidate, _config): continue
		var current: int = Hex.distance(Vector2i(origin.q, origin.r), Vector2i(candidate.q, candidate.r))
		if current != distance: continue
		# 取字典序最小者，保证确定
		if best.is_empty() or candidate.id < best:
			best = candidate.id
			best_delta = current
	if best_delta == 9999: return ""
	return best


## 距离 `tile_id` 恰好 `distance` 格、且**没有任何弟子占据**的可通行地块（字典序最小，保证确定）。
func _empty_tile_at_distance(state: GameState, tile_id: String, distance: int) -> String:
	var origin: HexTile = state.tiles.get(tile_id, null)
	if origin == null: return ""
	var occupied: Dictionary = {}
	for sect: Sect in state.sects:
		for disciple: Disciple in sect.disciples:
			occupied[disciple.tileId] = true
	var best: String = ""
	for candidate: HexTile in state.tiles.values():
		if not MoveRules.is_passable(candidate, _config): continue
		if occupied.has(candidate.id): continue
		var current: int = Hex.distance(Vector2i(origin.q, origin.r), Vector2i(candidate.q, candidate.r))
		if current != distance: continue
		if best.is_empty() or candidate.id < best: best = candidate.id
	return best


## 与 `anchor_id` 相邻、但与 `avoid_id` 不相邻的一个可通行地块（用于把敌人挪到侧面）。
func _tile_at_distance_from(state: GameState, tile_id: String, avoid_id: String, distance: int) -> String:
	var tile: HexTile = state.tiles.get(tile_id, null)
	var avoid: HexTile = state.tiles.get(avoid_id, null)
	if tile == null or avoid == null: return ""
	for coords: Vector2i in Hex.neighbors(Vector2i(tile.q, tile.r)):
		var candidate: String = Hex.id(coords.x, coords.y)
		if not state.tiles.has(candidate): continue
		if not MoveRules.is_passable(state.tiles[candidate], _config): continue
		var away: int = Hex.distance(Vector2i(avoid.q, avoid.r), Hex.coords(candidate))
		if away == distance: return candidate
	return ""


## 离 `tile_id` 尽量远的一个可通行地块（用于把守军/单位挪出战场）。
func _far_tile_id(state: GameState, tile_id: String) -> String:
	var origin: HexTile = state.tiles.get(tile_id, null)
	if origin == null: return tile_id
	var best: String = tile_id
	var best_distance: int = -1
	for candidate: HexTile in state.tiles.values():
		if not MoveRules.is_passable(candidate, _config): continue
		var current: int = Hex.distance(Vector2i(origin.q, origin.r), Vector2i(candidate.q, candidate.r))
		if current > best_distance:
			best_distance = current
			best = candidate.id
	return best


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
