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

## TURN_START（R2 实做 + R3 回填道路刷新）：重算视野 → 刷新道路网 → 每名弟子重置出手、
## 按公式恢复移动力（含本宗道路起点加成）、宗门停留回合 +1。
## **不做**：传送清零（R5）、宗主外出（R7）、伤愈（R5）、修炼（R4）、自动化（R6）。
func _run_turn_start(state: GameState) -> void:
	VisionCalculator.recalculate(state, _config)
	# R3 回填：道路网等级刷新（R2 留的 TODO）。
	RoadNetworkService.refresh(state, _config)
	# R2 无淘汰机制（R7），全部宗门都刷新。
	for sect: Sect in state.sects:
		for disciple: Disciple in sect.disciples:
			disciple.attacksRemaining = int(_config["warfare"]["attacksPerTurn"])
			var points: int = MoveRules.calculate_max_move_points(disciple, _config, state, sect)
			disciple.maxMovePoints = points
			disciple.movePoints = points
			disciple.turnsInSect += 1


## SPIRIT_PEAK（R3 实做）：项目队列推进（`turnsRemaining -= 1`，归零则落成）。
## **留空**：围城断供（R5）、研究队列推进（R4）。
func _run_spirit_peak(state: GameState) -> void:
	for sect: Sect in state.sects:
		for peak: SpiritPeak in sect.spiritPeaks:
			CityAction.advance_projects(state, _config, sect, peak)
	# TODO(R5): 围城断供削减；TODO(R4): 研究队列推进（工力不足则暂停）。


## SETTLEMENT（R3 实做）：节点冷却 → 人口结算 → 经济结算（唯一入口 `EconomyRules.apply_settlement`）。
## **留空**：道统成就 boost（R4）、心魔（R4）、政令（R6）。
func _run_settlement(state: GameState) -> void:
	EconomyRules.apply_settlement(state, _config)
	# TODO(R4): 道统成就 boost；TODO(R4): 心魔结算；TODO(R6): 政令结算。


func _run_ai_action(_state: GameState) -> void:
	# TODO(R7): 三家 AI 行动。R2 三家 AI 不行动。
	pass


func _run_victory_check(_state: GameState) -> void:
	# TODO(R7): 胜负判定 / 240 回合强制分数。R2 不判定、不终局。
	pass


func _log(state: GameState, text: String) -> String:
	state.eventLog.append(text)
	return text
