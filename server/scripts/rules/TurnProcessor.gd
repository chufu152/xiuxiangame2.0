class_name TurnProcessor
extends RefCounted
## 六阶段回合状态机（R2：只实做 TURN_START，其余阶段留空 + TODO 标记）。
##
## 语义对齐 1.0 `GameEngine`：`nextTurn()` = `beginPlayerTurn()` + `finishTurn()`。
## 阶段顺序：TURN_START → SPIRIT_PEAK → PLAYER_ACTION → SETTLEMENT → AI_ACTION → VICTORY_CHECK。
##
## 命令回包的 `events` 即本命令期间新增的 `state.eventLog` 字符串条目（Array[String]），
## **不发明结构化事件对象**；由本类方法直接返回，避免「清空日志后按长度差取尾巴」的歧义。

var _config: Dictionary = {}


func _init(config: Dictionary = {}) -> void:
	_config = config


## 回合开始：清空事件日志 → TURN_START → SPIRIT_PEAK → 进入 PLAYER_ACTION。
func begin_player_turn(state: GameState) -> Array[String]:
	var events: Array[String] = []
	state.eventLog.clear()
	events.append(_log(state, "第 %d 回合开始" % state.turn))
	_run_turn_start(state)
	_run_spirit_peak(state)
	state.phase = Enums.TurnPhase.PLAYER_ACTION
	return events


## 回合结束：SETTLEMENT → AI_ACTION → VICTORY_CHECK；未终局则回合 +1 并回到 PLAYER_ACTION。
func finish_turn(state: GameState) -> Array[String]:
	var events: Array[String] = []
	var ending_turn: int = state.turn
	_run_settlement(state)
	_run_ai_action(state)
	_run_victory_check(state)
	events.append(_log(state, "第 %d 回合结束" % ending_turn))
	if not state.gameOver:
		state.turn += 1
		state.phase = Enums.TurnPhase.PLAYER_ACTION
	return events


## 旧控制台入口：先 begin 再 finish（顺序与 1.0 一致；主 UI 用 finishTurn→beginPlayerTurn）。
func next_turn(state: GameState) -> Array[String]:
	var events: Array[String] = begin_player_turn(state)
	events.append_array(finish_turn(state))
	return events


# ---------------------------------------------------------------------------
# 各阶段
# ---------------------------------------------------------------------------

## TURN_START（R2 实做 + R3 回填道路刷新 + R4 回填修炼 + R5 回填传送次数清零 + R6 回填自动化
## + R7 回填宗主外出检查 + R10 修复突破判定）：
## 重算视野 → 刷新道路网 → 传送次数清零 → 每名弟子重置出手/转职冷却、按公式恢复移动力
## （含本宗道路起点加成与兵种/晋升机动）、宗门停留回合 +1 → 伤愈 → 修炼 → **突破判定**
## → **玩家宗门自动化** → **宗主外出检查**。
func _run_turn_start(state: GameState) -> void:
	VisionCalculator.recalculate(state, _config)
	# R3 回填：道路网等级刷新（R2 留的 TODO）。
	RoadNetworkService.refresh(state, _config)
	# R2 无淘汰机制（R7），全部宗门都刷新。
	for sect: Sect in state.sects:
		# R5 回填：传送次数每回合清零（R2 留的 TODO）。
		sect.teleportsUsedThisTurn = 0
		for disciple: Disciple in sect.disciples:
			disciple.attacksRemaining = int(_config["warfare"]["attacksPerTurn"])
			var points: int = MoveRules.calculate_max_move_points(disciple, _config, state, sect)
			disciple.maxMovePoints = points
			disciple.movePoints = points
			disciple.turnsInSect += 1
			# R5：转职冷却递减（1.0 `UnitRules.beginTurn` 语义）。
			if disciple.reclassCooldown > 0: disciple.reclassCooldown -= 1
	# R4 回填：伤愈 + 修炼（R2 留的修炼 TODO）。顺序固定（宗门序 → 弟子序），保证同种子逐字一致。
	# **R10 修复：突破判定此前从未被调用。** `advance_cultivation` 只负责「把进度条填满并置
	# `breakthroughPending`」，而全仓没有任何地方消费这个标志，于是修为满了就永久卡住——
	# 弟子境界停在开局值（外门永远炼气）→ 没有金丹 → `AIController._try_expand` 永远没有
	# 合格人选 → 灵峰恒为 1 座；元婴/化神永远 0 人 → 家族流「举族登仙」飞升 0/4。
	# 这里是 `try_breakthrough` 的**唯一**调用点，判定权仍完全归它（含「元婴→化神须渡劫」的
	# 拒绝分支），本处不重复任何条件。
	for sect: Sect in state.sects:
		for disciple: Disciple in sect.disciples:
			if DiscipleRules.heal_tick(state, _config, disciple):
				state.eventLog.append("[修炼] %s 伤愈" % disciple.name)
			DiscipleRules.advance_cultivation(state, _config, disciple)
			# 灵力不足时 `advance_cultivation` 会提前返回，但上一回合攒下的 `breakthroughPending`
			# 依然有效，故此处只认 pending 标志、不看返回值。
			# 元婴弟子会一直保持 pending=true（等玩家 `tribulate`），此时本调用是纯 no-op：
			# `try_breakthrough` 在掷骰之前就返回，不消耗随机数、不写事件日志。
			if disciple.breakthroughPending:
				DiscipleRules.try_breakthrough(state, _config, disciple)
	# R6 回填：玩家宗门自动化（R2 留的 TODO）。必须放在移动力恢复之后——自动工序要移动建造者/弟子。
	AutomationRules.run_turn(state, _config)
	# R7 回填：宗主外出检查（R2 留的 TODO）。只在**状态翻转时**记事件，避免每回合刷屏；
	# 加成本身由 `EconomyRules` 每回合现算（`AppointmentRules.zong_zhu_outside_bonus_active`）。
	for sect: Sect in state.sects:
		var has_zong_zhu: bool = false
		for disciple: Disciple in sect.disciples:
			if disciple.position == Enums.Position.ZONG_ZHU:
				has_zong_zhu = true
				break
		var outside: bool = has_zong_zhu and not AppointmentRules.zong_zhu_outside_bonus_active(state, _config, sect)
		if outside and not sect.zongZhuOutside:
			state.eventLog.append("[任命] %s 宗主外出, 宗主大殿全局加成失效" % sect.name)
		elif not outside and sect.zongZhuOutside:
			state.eventLog.append("[任命] %s 宗主归位, 宗主大殿全局加成恢复" % sect.name)
		sect.zongZhuOutside = outside


## SPIRIT_PEAK（R3 实做 + R4 回填研究队列 + R5 回填围城断供）：
## 灵峰建造项目推进 + 宗门研究队列推进（工力不足则暂停）→ 围城补给结算。
##
## **围城断供（R5 回填 R3 留的 TODO）**：补给线被切断的灵峰逐回合累计 `siegeTurns`，
## 城防按 `min(maxDefenseCut, defenseCutPerTurn × siegeTurns)` 折减（`CombatResolver` 攻城时生效）；
## 补给恢复则 `siegeTurns` 归零。被围期间该峰的建造项目**暂停不扣工力**，避免「围城中还在盖楼」。
func _run_spirit_peak(state: GameState) -> void:
	# R4 回填：`ProjectRules.advance_projects` 内部分派灵峰项目（R3 逻辑不变）与宗门研究队列。
	ProjectRules.advance_projects(state, _config)
	# R5 回填：围城断供削减（R3 留的 TODO）。
	for sect: Sect in state.sects:
		for peak: SpiritPeak in sect.spiritPeaks:
			var was_besieged: bool = peak.siegeTurns > 0
			var besieged: bool = UnitRules.update_attrition(state, _config, peak)
			if besieged and not was_besieged:
				state.eventLog.append("[围城] %s 补给线被切断, 城防开始折减" % peak.name)
			elif was_besieged and not besieged:
				state.eventLog.append("[围城] %s 补给恢复, 城防折减清零" % peak.name)


## SETTLEMENT（R3 实做 + R4 回填道统/心魔 + R5 回填视野重算 + R6 回填政令结算）：节点冷却 →
## 人口结算 → 经济结算（唯一入口 `EconomyRules.apply_settlement`，内含节点冷却 −1 与气运产出）→
## **政令结算** → 道统成就 boost → 心魔结算 → 视野重算。
##
## 节点冷却 −1（R3 已落 `EconomyRules.apply_settlement` 首步）与 `qiYun` 每回合产出（R3 已落
## `EconomyRules.peak_output`/`_apply_economy`）在 R6 复核后确认**已存在**，故不重复回填，
## 只在 R6 验收里显式断言二者仍生效（避免「以为没做」而二次叠加）。
func _run_settlement(state: GameState) -> void:
	EconomyRules.apply_settlement(state, _config)
	# R6 回填：政令结算（R3 留的政令 TODO）。必须紧跟经济结算——安定是派生值，
	# 政令的安定叠加要在 `settle_city` 重算之后落地（见 `PolicyRules.process_settlement`）。
	PolicyRules.process_settlement(state, _config)
	# R4 回填：道统成就 boost（一次性道点奖励，替代 1.0「顿悟」）。
	for sect: Sect in state.sects:
		DaoRules.check_boosts(state, _config, sect)
	# R4 回填：心魔结算（超容量/受伤/叛逃）。
	_run_heart_devil(state)
	# R5 回填：夺峰/夺点易主后的视野重算。`CombatResolver` 在易主当下已即时重算过一次，
	# 此处再兜一次是因为结算期还会改视野源（弟子陨落/叛逃移除、被俘改换门庭），
	# 保证「回合结束时各宗视野与实体分布自洽」。`recalculate` 幂等，重复调用无副作用。
	VisionCalculator.recalculate(state, _config)


## 心魔结算：逐弟子推进；叛逃者从宗门移除（投中立，R7 前不建立中立势力实体）。
func _run_heart_devil(state: GameState) -> void:
	for sect: Sect in state.sects:
		var index: int = 0
		while index < sect.disciples.size():
			var disciple: Disciple = sect.disciples[index]
			var outcome: Dictionary = DiscipleRules.heart_devil_tick(state, _config, disciple)
			if bool(outcome["betray"]):
				sect.disciples.remove_at(index)
				continue
			index += 1


## AI_ACTION（R7 回填 R2 留的 TODO）：未覆灭的 AI 宗门逐家行动，行动后重算其视野。
## 顺序固定（宗门序），每家的 `AIController.run_turn` 内部也按 id 升序遍历，
## 故「同种子 + 同指令序列」下 AI 行为逐字一致（验收 9）。
## **AI 不检查宣战**（PRD §5.2 #1）。
func _run_ai_action(state: GameState) -> void:
	for sect: Sect in state.sects:
		if sect.player or sect.defeated:
			continue
		AIController.run_turn(state, _config, sect)
	# AI 行动会改地块归属/灵峰易主，行动后统一重算视野，让「AI 打到哪」即时反映在迷雾上。
	VisionCalculator.recalculate(state, _config)


## VICTORY_CHECK（R7 回填 R2 留的 TODO）：胜负判定 / 终局冻结 / 240 回合分数结算 /
## 每 10 回合自动存档，全部收敛在 `VictoryRules.process_victory_check` 一个入口。
func _run_victory_check(state: GameState) -> void:
	VictoryRules.process_victory_check(state, _config)


func _log(state: GameState, text: String) -> String:
	state.eventLog.append(text)
	return text
