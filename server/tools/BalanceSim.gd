extends Node
## R9 W4 平衡抽样器：无头批量模拟整局，输出 `docs/BALANCE_REPORT.md` + `outputs/balance_sample.json`。
##
## 无头运行：
##   `godot --headless --path server res://tools/BalanceSim.tscn -- --games=12`
##
## **零服务端改动**：本工具只调用现成的公开入口
## （`CommandDispatcher` 开局 → `TurnProcessor.begin_player_turn/finish_turn` → `AIController.run_turn`），
## 不碰任何 `*Rules` 的数值与分支，符合 R8 裁决五「不改数值」。
##
## 两种抽样模式：
## 1. `ffa`（全 AI 自由对局）：四个宗门**全部**交给 `AIController` 驱动，并清空
##    `state.playerSectId`，使某家覆灭不会提前把 `gameOver` 置真——一局能跑到
##    「有人达成胜利」或「满 240 回合分数结算」。这是纯流派强度的度量。
## 2. `player`（玩家视角）：保留 `sect_0` 的 `player` 标记（玩家宗门覆灭即终局），
##    但在每回合行动阶段临时把 `player` 翻成 false 让 `AIController` 代打，
##    用来回答「同一套决策水平下，玩家选哪个流派更好过、多少回合能过」。
##
## **可复现性**：随机只经 `GameState.rng`（硬约束 6），种子由 `_seed_of(可读文本)` 确定性散列，
## 故「同 mode + 同流派 + 同序号」必得逐字相同的对局。`--verify` 抽一局跑两遍比对终局指纹。

const MODE_FFA: String = "ffa"
const MODE_PLAYER: String = "player"
const MODE_ALL: Array[String] = [MODE_FFA, MODE_PLAYER]

## 参与抽样的玩家流派（`sect_0` 的 `factionType`）；三个 AI 席位固定为配置里的 `aiFactions`。
const FACTION_ALL: Array[String] = [
	Enums.FactionType.ZONG_MEN, Enums.FactionType.JIA_ZU, Enums.FactionType.GUO_JIA,
]

## 进度曲线采样间隔（回合）。
const CHECKPOINT_STEP: int = 30

## 默认抽样局数（每 mode × 每流派）。可通过 `--games=N` 覆盖。
const DEFAULT_GAMES: int = 12

var _config: Dictionary = {}
var _max_turns: int = 240
var _games: int = DEFAULT_GAMES
var _modes: Array[String] = MODE_ALL
var _difficulty: String = ""
var _verify: bool = false
var _started: int = Time.get_ticks_msec()


func _ready() -> void:
	var loaded: Dictionary = ConfigLoader.load_from_file(ConfigLoader.default_path())
	if not bool(loaded["ok"]):
		printerr("BALANCE_FAIL 配置加载失败：%s" % str(loaded.get("error", "")))
		get_tree().quit(1)
		return
	_config = loaded["config"]
	_parse_args()
	if _difficulty.is_empty():
		_difficulty = str(_config["difficulty"]["defaultLevel"])
	if not (_config["difficulty"]["levels"] as Dictionary).has(_difficulty):
		printerr("BALANCE_FAIL 未知难度：%s" % _difficulty)
		get_tree().quit(1)
		return
	_max_turns = VictoryRules.max_turns(_config)
	if _verify:
		_verify_determinism()
		return
	print("[balance] modes=%s games/组=%d maxTurns=%d difficulty=%s 预计 %d 局" % [
		str(_modes), _games, _max_turns, _difficulty, _games * _modes.size() * FACTION_ALL.size(),
	])
	var samples: Array = []
	for mode: String in _modes:
		for faction: String in FACTION_ALL:
			for index: int in range(_games):
				var sample: Dictionary = _simulate(mode, faction, index)
				samples.append(sample)
				print("[balance] %s/%s#%d -> %s" % [mode, faction, index, _one_line(sample)])
	_write_json(samples)
	_write_markdown(samples)
	var elapsed: float = float(Time.get_ticks_msec() - _started) / 1000.0
	var failed: int = 0
	for sample: Dictionary in samples:
		if not bool(sample.get("ok", false)):
			failed += 1
	if failed > 0:
		printerr("BALANCE_FAIL games=%d failed=%d elapsed=%.1fs" % [samples.size(), failed, elapsed])
		get_tree().quit(1)
		return
	print("BALANCE_OK games=%d modes=%s elapsed=%.1fs" % [samples.size(), str(_modes), elapsed])
	get_tree().quit(0)


# ---------------------------------------------------------------------------
# 参数
# ---------------------------------------------------------------------------

func _parse_args() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--games="):
			_games = maxi(1, int(argument.trim_prefix("--games=")))
		elif argument.begins_with("--turns="):
			_max_turns = maxi(1, int(argument.trim_prefix("--turns=")))
		elif argument.begins_with("--modes="):
			var parsed: Array[String] = []
			for piece: String in argument.trim_prefix("--modes=").split(",", false):
				var mode: String = piece.strip_edges()
				if MODE_ALL.has(mode):
					parsed.append(mode)
			if not parsed.is_empty():
				_modes = parsed
		elif argument.begins_with("--difficulty="):
			_difficulty = argument.trim_prefix("--difficulty=").strip_edges()
		elif argument == "--verify":
			_verify = true


# ---------------------------------------------------------------------------
# 单局模拟
# ---------------------------------------------------------------------------

func _simulate(mode: String, player_faction: String, index: int) -> Dictionary:
	var seed_text: String = "balance-%s-%s-%d" % [mode, player_faction, index]
	var dispatcher: CommandDispatcher = CommandDispatcher.new(_config)
	var response: Dictionary = dispatcher.dispatch_text(JSON.stringify({
		"id": "balance", "type": Commands.NEW_GAME, "params": {
			"sectName": "抽样宗", "playerFaction": player_faction,
			"mapWidth": 20, "mapHeight": 14,
			"randomSeed": _seed_of(seed_text), "difficultyId": _difficulty,
		},
	}))
	var state: GameState = dispatcher.state
	if state == null:
		return {"ok": false, "mode": mode, "playerFaction": player_faction, "seed": seed_text,
			"error": str(response.get("message", "newGame 失败"))}
	var probe_id: String = state.playerSectId
	if mode == MODE_FFA:
		for sect: Sect in state.sects:
			sect.player = false
		state.playerSectId = ""
	var turns: TurnProcessor = TurnProcessor.new(_config)
	var checkpoints: Array = []
	var collapses: Dictionary = {}
	var end_turn: int = 0
	var settled: bool = false
	for _step: int in range(_max_turns):
		var turn_no: int = state.turn
		turns.begin_player_turn(state)
		if mode == MODE_PLAYER:
			_drive_probe(state, probe_id)
		turns.finish_turn(state)
		_capture_collapses(state, turn_no, collapses)
		if turn_no % CHECKPOINT_STEP == 0:
			checkpoints.append(_snapshot(state, turn_no))
		if state.gameOver:
			end_turn = turn_no
			settled = true
			break
		if state.turn > _max_turns:
			break
	if end_turn == 0:
		end_turn = maxi(0, state.turn - 1)
	var winner: Sect = _find_sect(state, state.winnerSectId)
	var sample: Dictionary = {
		"ok": true,
		"mode": mode,
		"playerFaction": player_faction,
		"seed": seed_text,
		"seedValue": _seed_of(seed_text),
		"difficulty": state.difficulty,
		"map": "%dx%d" % [state.width, state.height],
		"turns": end_turn,
		"gameOver": state.gameOver,
		"settled": settled,
		"winnerSectId": state.winnerSectId,
		"winnerFaction": "" if winner == null else winner.factionType,
		"winType": state.winType,
		"probeId": probe_id,
		"collapses": collapses,
		"finalSects": _sect_list(state),
		"checkpoints": checkpoints,
	}
	# 终局指纹：用于 `--verify` 的逐字比对（只含与随机/数值有关的稳定量）。
	sample["fingerprint"] = _fingerprint(state)
	return sample


## 玩家宗门代打：临时把 `player` 翻成 false 让 `AIController` 接管（`run_turn` 对 player 直接 return），
## 调用后立刻还原，保证 `finish_turn` 里的 AI_ACTION 阶段仍然跳过玩家宗门。
func _drive_probe(state: GameState, probe_id: String) -> void:
	var sect: Sect = _find_sect(state, probe_id)
	if sect == null or sect.defeated:
		return
	sect.player = false
	AIController.run_turn(state, _config, sect)
	sect.player = true


## 记录本回合**首次**出现的覆灭（回合号 + 原因）。
## `check_defeat` 在判定时会往 `eventLog` 写一行 `[胜负] ...`，而 `eventLog` 要到
## 下一回合 `begin_player_turn` 才清空，故此刻读到的就是本次覆灭的原始原因行。
func _capture_collapses(state: GameState, turn_no: int, info: Dictionary) -> void:
	for sect: Sect in state.sects:
		if not sect.defeated or info.has(sect.id):
			continue
		info[sect.id] = {"turn": turn_no, "reason": _collapse_reason(state, sect)}


func _collapse_reason(state: GameState, sect: Sect) -> String:
	for event: String in state.eventLog:
		if not event.begins_with("[胜负]") or not event.contains(sect.name):
			continue
		if event.contains("门下尽墨"):
			return "弟子全灭"
		if event.contains("灵峰尽失"):
			return "灵峰尽失"
		if event.contains("宗主陨落"):
			return "宗主陨落且无金丹继承人"
	return "未记录"


func _snapshot(state: GameState, turn_no: int) -> Dictionary:
	return {"turn": turn_no, "sects": _sect_list(state)}


func _sect_list(state: GameState) -> Array:
	var result: Array = []
	for sect: Sect in state.sects:
		result.append(_sect_metrics(state, sect))
	return result


## 单宗终局/中间指标。全部走 `VictoryRules` 的现成只读函数，不另算一套口径。
## `signatureGoals` 是招牌路线的**逐目标**完成率——报告 §4.2 靠它定位「卡在哪个目标」。
## `highRealm` / `topRealmLevel` 用来验证「突破判定是否真的在跑」：境界推不动时它们恒为 0。
func _sect_metrics(state: GameState, sect: Sect) -> Dictionary:
	var routes: Array[String] = VictoryRules.routes_for(_config, sect.factionType)
	var signature: String = "" if routes.is_empty() else routes[0]
	var ratio: float = 0.0
	var goals: Array = []
	if not signature.is_empty() and not sect.defeated:
		var progress: Dictionary = VictoryRules.progress_of(state, _config, sect, signature)
		ratio = float(progress["ratio"])
		for goal: Dictionary in (progress["goals"] as Array):
			goals.append({"name": str(goal["name"]), "ratio": float(goal["ratio"])})
	var top_level: int = 0
	for disciple: Disciple in sect.disciples:
		top_level = maxi(top_level, disciple.realmLevel)
	return {
		"id": sect.id,
		"name": sect.name,
		"faction": sect.factionType,
		"player": sect.player,
		"defeated": sect.defeated,
		"peaks": sect.spiritPeaks.size(),
		"disciples": sect.disciples.size(),
		"powerLevel": sect.powerLevel,
		"score": 0 if sect.defeated else VictoryRules.compute_score(state, _config, sect),
		"tiles": VictoryRules.owned_tiles(state, sect),
		"tileShare": VictoryRules.claimed_tile_share(state, sect),
		"daoCompletion": VictoryRules.dao_completion(_config, sect),
		"ascension": VictoryRules.ascension_count(sect),
		"highRealm": VictoryRules.high_realm_members(sect, Disciple.level_of(Enums.Realm.JIN_DAN)),
		"topRealmLevel": top_level,
		"signatureRoute": signature,
		"signatureRatio": ratio,
		"signatureGoals": goals,
	}


func _fingerprint(state: GameState) -> String:
	var parts: Array[String] = []
	parts.append("turn=%d" % state.turn)
	parts.append("over=%s" % str(state.gameOver))
	parts.append("winner=%s" % state.winnerSectId)
	parts.append("winType=%s" % state.winType)
	for sect: Sect in state.sects:
		parts.append("%s:%s:%d:%d:%d" % [
			sect.id, str(sect.defeated), sect.spiritPeaks.size(),
			sect.disciples.size(), sect.powerLevel,
		])
	return "|".join(parts)


func _find_sect(state: GameState, sect_id: String) -> Sect:
	if sect_id.is_empty():
		return null
	for sect: Sect in state.sects:
		if sect.id == sect_id:
			return sect
	return null


## 单行日志摘要。
func _one_line(sample: Dictionary) -> String:
	if not bool(sample.get("ok", false)):
		return "失败(%s)" % str(sample.get("error", ""))
	var winner: String = str(sample.get("winnerFaction", ""))
	var probe: String = str(sample.get("probeId", ""))
	var collapse: Dictionary = (sample.get("collapses", {}) as Dictionary).get(probe, {})
	var probe_text: String = "否"
	if not collapse.is_empty():
		probe_text = "%s@%d" % [str(collapse["reason"]), int(collapse["turn"])]
	return "回合%3d 胜者=%s(%s) 覆灭席位=%d 玩家席位覆灭=%s" % [
		int(sample.get("turns", 0)),
		"无" if winner.is_empty() else winner,
		str(sample.get("winType", "")),
		(sample.get("collapses", {}) as Dictionary).size(),
		probe_text,
	]


# ---------------------------------------------------------------------------
# 确定性自检
# ---------------------------------------------------------------------------

## 抽一局跑两遍，比对终局指纹，确认抽样本身可复现（验收 9 的延伸）。
func _verify_determinism() -> void:
	var first: Dictionary = _simulate(MODE_FFA, Enums.FactionType.ZONG_MEN, 0)
	var second: Dictionary = _simulate(MODE_FFA, Enums.FactionType.ZONG_MEN, 0)
	var left: String = str(first.get("fingerprint", ""))
	var right: String = str(second.get("fingerprint", ""))
	if left == right and not left.is_empty():
		print("BALANCE_VERIFY=OK")
		print("BALANCE_FINGERPRINT=%s" % left)
		get_tree().quit(0)
		return
	printerr("BALANCE_VERIFY=FAIL\n  A=%s\n  B=%s" % [left, right])
	get_tree().quit(1)


# ---------------------------------------------------------------------------
# 输出：原始 JSON
# ---------------------------------------------------------------------------

func _repo_root() -> String:
	return ProjectSettings.globalize_path("res://").path_join("..").simplify_path()


func _write_json(samples: Array) -> void:
	var dir: String = _repo_root().path_join("outputs")
	DirAccess.make_dir_recursive_absolute(dir)
	var path: String = dir.path_join("balance_sample.json")
	var payload: Dictionary = {
		"generatedBy": "server/tools/BalanceSim.gd",
		"maxTurns": _max_turns,
		"difficulty": _difficulty,
		"gamesPerCell": _games,
		"modes": _modes,
		"factions": FACTION_ALL,
		"checkpointStep": CHECKPOINT_STEP,
		"config": {
			"ai": _config["ai"],
			"victory": _config["victory"],
			"difficultyLevels": _config["difficulty"]["levels"].keys(),
		},
		"samples": samples,
	}
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		printerr("BALANCE_FAIL 无法写入 %s" % path)
		return
	file.store_string(JSON.stringify(payload, "  "))
	file.close()
	print("[balance] 原始数据 -> %s (%d 局)" % [path, samples.size()])


# ---------------------------------------------------------------------------
# 输出：Markdown 报告
# ---------------------------------------------------------------------------

func _write_markdown(samples: Array) -> void:
	var text: String = _render_report(samples)
	var path: String = _repo_root().path_join("docs").path_join("BALANCE_REPORT.md")
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		printerr("BALANCE_FAIL 无法写入 %s" % path)
		return
	file.store_string(text)
	file.close()
	print("[balance] 报告 -> %s (%d 字符)" % [path, text.length()])


func _render_report(samples: Array) -> String:
	var ffa: Array = _filter(samples, MODE_FFA)
	var player: Array = _filter(samples, MODE_PLAYER)
	var lines: Array[String] = []
	lines.append("# 平衡抽样报告（R9 W4）")
	lines.append("")
	lines.append("> 本文件由 `server/tools/BalanceSim.gd` **自动生成**，请勿手改。")
	lines.append("> 重新生成：`godot --headless --path server res://tools/BalanceSim.tscn -- --games=%d`" % _games)
	lines.append("")
	lines.append("## 1. 方法与可复现性")
	lines.append("")
	lines.append("| 项 | 值 |")
	lines.append("|---|---|")
	lines.append("| 抽样模式 | %s |" % str(_modes))
	lines.append("| 每格局数 | %d（每模式 × 每玩家流派） |" % _games)
	lines.append("| 总对局数 | %d |" % samples.size())
	lines.append("| 地图 | 20 × 14，`difficultyId=%s` |" % _difficulty)
	lines.append("| 回合上限 | %d（`victory.maxTurns`） |" % _max_turns)
	lines.append("| 决策水平 | 四个席位统一由 `AIController` 驱动（玩家席位代打） |")
	lines.append("| 随机源 | 仅 `GameState.rng`，种子由 `mode+流派+序号` 确定性散列 |")
	lines.append("")
	lines.append("**两种模式的区别**")
	lines.append("")
	lines.append("- `ffa`：四席全部 `player=false` 且清空 `playerSectId`，某家覆灭不提前终局，")
	lines.append("  一局必然跑到「有人达成胜利」或「满 %d 回合分数结算」——纯流派强度。" % _max_turns)
	lines.append("- `player`：`sect_0` 保留 `player=true`（该席覆灭即终局），行动阶段临时翻标志让 AI 代打。")
	lines.append("  这是玩家真实处境：**输了就是输了，不会看着别人继续打**。")
	lines.append("")
	lines.append("两种模式**都不改任何数值**（R8 裁决五），只读配置、只跑既有规则。")
	lines.append("")
	lines.append_array(_render_ffa(ffa))
	lines.append_array(_render_player(player))
	lines.append_array(_render_curves(ffa))
	lines.append_array(_render_conclusion(ffa, player))
	lines.append("## 6. 附录")
	lines.append("")
	lines.append("| 项 | 位置 |")
	lines.append("|---|---|")
	lines.append("| 逐局原始数据 | `outputs/balance_sample.json`（每局终局指标 + 每 %d 回合快照 + 覆灭记录） |" % CHECKPOINT_STEP)
	lines.append("| 生成器 | `server/tools/BalanceSim.gd` |")
	lines.append("| 复现单局 | 种子值见 JSON 的 `seedValue`，喂给 `newGame.randomSeed` 即可重放 |")
	lines.append("| 抽样器自检 | `--verify` 连跑两遍比对终局指纹，打印 `BALANCE_VERIFY=OK` |")
	lines.append("| 可选参数 | `--games=N` / `--modes=ffa,player` / `--turns=N` / `--difficulty=easy\\|normal\\|hard` |")
	lines.append("")
	lines.append("_本报告由抽样自动生成；表格中的「—」表示该格无样本。_")
	lines.append("")
	return "\n".join(lines)


# ---------------------------------------------------------------------------
# §2 全 AI 自由对局
# ---------------------------------------------------------------------------

func _render_ffa(ffa: Array) -> Array[String]:
	var lines: Array[String] = []
	lines.append("## 2. 全 AI 自由对局（`ffa`）")
	lines.append("")
	if ffa.is_empty():
		lines.append("_本模式未参与抽样。_")
		lines.append("")
		return lines
	var seats: Array = _seat_rows(ffa)
	lines.append("### 2.1 按流派聚合的胜率与生死")
	lines.append("")
	lines.append("「出场」= 该流派在样本中出现的席位数（每局 4 席，故出场数 = 局数 × 该流派每局席位数）。")
	lines.append("")
	lines.append("| 流派 | 出场 | 夺冠 | 胜率 | 覆灭 | 覆灭率 | 夺冠平均回合 | 覆灭平均回合 |")
	lines.append("|---|---|---|---|---|---|---|---|")
	for faction: String in FACTION_ALL:
		var appear: int = 0
		var wins: int = 0
		var dead: int = 0
		var win_turns: Array = []
		var dead_turns: Array = []
		for row: Dictionary in seats:
			if str(row["faction"]) != faction:
				continue
			appear += 1
			if bool(row["defeated"]):
				dead += 1
				dead_turns.append(float(row["collapseTurn"]))
			if bool(row["winner"]):
				wins += 1
				win_turns.append(float(row["endTurn"]))
		lines.append("| %s | %d | %d | %s | %d | %s | %s | %s |" % [
			faction, appear, wins, _pct(wins, appear), dead, _pct(dead, appear),
			"—" if win_turns.is_empty() else "%.1f" % _mean(win_turns),
			"—" if dead_turns.is_empty() else "%.1f" % _mean(dead_turns),
		])
	lines.append("")
	lines.append("### 2.2 结束回合与收尾方式")
	lines.append("")
	var turns: Array = _turns_of(ffa)
	lines.append("| 统计量 | 值 |")
	lines.append("|---|---|")
	lines.append("| 局数 | %d |" % turns.size())
	lines.append("| 结束回合 平均 / 中位 | %.1f / %.0f |" % [_mean(turns), _median(turns)])
	lines.append("| 结束回合 最小 / 最大 | %d / %d |" % [int(_min_of(turns)), int(_max_of(turns))])
	lines.append("| 招牌路线达成而终局 | %d 局 |" % (ffa.size() - _score_settled(ffa)))
	lines.append("| 分数兜底（`%s`）终局 | %d 局 |" % [
		str(VictoryRules.ROUTE_NAMES[VictoryRules.ROUTE_SCORE]), _score_settled(ffa),
	])
	lines.append("| 打满上限仍未终局 | %d 局 |" % _unsettled(ffa))
	lines.append("")
	lines.append("### 2.3 胜利路线分布")
	lines.append("")
	lines.append("| 结局名 | 次数 | 占比 |")
	lines.append("|---|---|---|")
	var win_types: Dictionary = {}
	for sample: Dictionary in ffa:
		var key: String = str(sample.get("winType", ""))
		if key.is_empty():
			key = "（未终局）"
		win_types[key] = int(win_types.get(key, 0)) + 1
	var win_keys: Array = win_types.keys()
	win_keys.sort()
	for key: String in win_keys:
		lines.append("| %s | %d | %s |" % [key, int(win_types[key]), _pct(int(win_types[key]), ffa.size())])
	lines.append("")
	lines.append("### 2.4 覆灭原因分布")
	lines.append("")
	var reasons: Dictionary = {}
	var total_dead: int = 0
	for row: Dictionary in seats:
		if not bool(row["defeated"]):
			continue
		total_dead += 1
		var reason: String = str(row["reason"])
		var key: String = "%s / %s" % [str(row["faction"]), reason]
		reasons[key] = int(reasons.get(key, 0)) + 1
	if total_dead == 0:
		lines.append("_本批样本无覆灭。_")
	else:
		lines.append("| 流派 / 原因 | 次数 |")
		lines.append("|---|---|")
		var reason_keys: Array = reasons.keys()
		reason_keys.sort()
		for key: String in reason_keys:
			lines.append("| %s | %d |" % [key, int(reasons[key])])
	lines.append("")
	lines.append("### 2.5 各流派终局指标（覆灭者按 0 计）")
	lines.append("")
	lines.append("| 流派 | 平均评分 | 平均势力等级 | 平均灵峰 | 平均弟子 | 平均金丹以上 | 平均王土份额 | 平均道统完成度 | 招牌路线平均进度 |")
	lines.append("|---|---|---|---|---|---|---|---|---|")
	for faction: String in FACTION_ALL:
		var scores: Array = []
		var powers: Array = []
		var peaks: Array = []
		var members: Array = []
		var highs: Array = []
		var shares: Array = []
		var daos: Array = []
		var ratios: Array = []
		for row: Dictionary in seats:
			if str(row["faction"]) != faction:
				continue
			var entry: Dictionary = row["entry"]
			scores.append(float(entry["score"]))
			powers.append(float(entry["powerLevel"]))
			peaks.append(float(entry["peaks"]))
			members.append(float(entry["disciples"]))
			highs.append(float(entry.get("highRealm", 0)))
			shares.append(float(entry["tileShare"]))
			daos.append(float(entry["daoCompletion"]))
			ratios.append(float(entry["signatureRatio"]))
		lines.append("| %s | %.1f | %.1f | %.1f | %.1f | %.1f | %s | %s | %s |" % [
			faction, _mean(scores), _mean(powers), _mean(peaks), _mean(members), _mean(highs),
			_pct(_percent(_mean(shares)), 100), _pct(_percent(_mean(daos)), 100),
			_pct(_percent(_mean(ratios)), 100),
		])
	lines.append("")
	lines.append("### 2.6 逐局明细")
	lines.append("")
	lines.append("| 玩家流派 | # | 种子值 | 结束回合 | 胜者流派 | 结局 | 覆灭席位 |")
	lines.append("|---|---|---|---|---|---|---|")
	for sample: Dictionary in ffa:
		lines.append("| %s | %d | %d | %d | %s | %s | %d |" % [
			str(sample["playerFaction"]), _index_of(sample), int(sample["seedValue"]),
			int(sample["turns"]),
			"—" if str(sample["winnerFaction"]).is_empty() else str(sample["winnerFaction"]),
			"—" if str(sample["winType"]).is_empty() else str(sample["winType"]),
			(sample.get("collapses", {}) as Dictionary).size(),
		])
	lines.append("")
	return lines


# ---------------------------------------------------------------------------
# §3 玩家视角
# ---------------------------------------------------------------------------

func _render_player(player: Array) -> Array[String]:
	var lines: Array[String] = []
	lines.append("## 3. 玩家视角（`player`）")
	lines.append("")
	if player.is_empty():
		lines.append("_本模式未参与抽样。_")
		lines.append("")
		return lines
	lines.append("玩家宗门（`sect_0`）覆灭即终局，故「结束回合」既是通关回合也可能是覆灭回合，两者分开统计。")
	lines.append("")
	lines.append("| 玩家流派 | 局数 | 通关 | 通关率 | 覆灭 | 覆灭率 | 平均通关回合 | 平均覆灭回合 |")
	lines.append("|---|---|---|---|---|---|---|---|")
	for faction: String in FACTION_ALL:
		var total: int = 0
		var wins: int = 0
		var losses: int = 0
		var win_turns: Array = []
		var loss_turns: Array = []
		for sample: Dictionary in player:
			if str(sample["playerFaction"]) != faction:
				continue
			total += 1
			var probe_id: String = str(sample["probeId"])
			if not probe_id.is_empty() and str(sample["winnerSectId"]) == probe_id:
				wins += 1
				win_turns.append(float(sample["turns"]))
			elif (sample.get("collapses", {}) as Dictionary).has(probe_id):
				losses += 1
				loss_turns.append(float(((sample["collapses"] as Dictionary)[probe_id] as Dictionary)["turn"]))
		lines.append("| %s | %d | %d | %s | %d | %s | %s | %s |" % [
			faction, total, wins, _pct(wins, total), losses, _pct(losses, total),
			"—" if win_turns.is_empty() else "%.1f" % _mean(win_turns),
			"—" if loss_turns.is_empty() else "%.1f" % _mean(loss_turns),
		])
	lines.append("")
	lines.append("### 3.1 与配置预期区间的对照")
	lines.append("")
	lines.append("配置里每条招牌路线都带 `expectedMinTurns` / `expectedMaxTurns`。")
	lines.append("**只有「以该招牌路线夺冠」的局才算校准样本**——靠分数兜底在 240 回合夺冠")
	lines.append("说明的是「没被淘汰」，不是「路线按预期达成」，混在一起会把结论带偏。")
	lines.append("")
	lines.append("| 流派 | 招牌路线 | 配置预期区间 | 招牌路线夺冠 | 平均达成回合 | 判定 |")
	lines.append("|---|---|---|---|---|---|")
	for faction: String in FACTION_ALL:
		var route: String = _signature_route(faction)
		var window: Dictionary = _expected_window(faction)
		var route_name: String = str(VictoryRules.ROUTE_NAMES.get(route, route))
		var route_turns: Array = []
		for sample: Dictionary in player:
			if str(sample["playerFaction"]) != faction:
				continue
			if str(sample["winnerSectId"]) != str(sample["probeId"]) or str(sample["probeId"]).is_empty():
				continue
			if str(sample.get("winType", "")) != route_name:
				continue
			route_turns.append(float(sample["turns"]))
		var verdict: String = "无样本（该路线一次都没走通）"
		var shown: String = "—"
		if not route_turns.is_empty():
			var avg: float = _mean(route_turns)
			shown = "%.1f" % avg
			if avg < float(window["min"]):
				verdict = "偏快（低于下限）"
			elif avg > float(window["max"]):
				verdict = "偏慢（高于上限）"
			else:
				verdict = "在区间内"
		lines.append("| %s | %s（`%s`） | %d – %d | %d 次 | %s | %s |" % [
			faction, route_name, route, int(window["min"]), int(window["max"]),
			route_turns.size(), shown, verdict,
		])
	lines.append("")
	lines.append("### 3.2 逐局明细")
	lines.append("")
	lines.append("| 玩家流派 | # | 结束回合 | 结果 | 结局 |")
	lines.append("|---|---|---|---|---|")
	for sample: Dictionary in player:
		var probe_id: String = str(sample["probeId"])
		var collapses: Dictionary = sample.get("collapses", {})
		var result: String = "未终局"
		if not probe_id.is_empty() and str(sample["winnerSectId"]) == probe_id:
			result = "通关"
		elif collapses.has(probe_id):
			var info: Dictionary = collapses[probe_id]
			result = "覆灭@%d（%s）" % [int(info["turn"]), str(info["reason"])]
		elif bool(sample["gameOver"]):
			result = "他人夺冠"
		lines.append("| %s | %d | %d | %s | %s |" % [
			str(sample["playerFaction"]), _index_of(sample), int(sample["turns"]), result,
			"—" if str(sample["winType"]).is_empty() else str(sample["winType"]),
		])
	lines.append("")
	return lines


# ---------------------------------------------------------------------------
# §4 进度曲线
# ---------------------------------------------------------------------------

func _render_curves(ffa: Array) -> Array[String]:
	var lines: Array[String] = []
	lines.append("## 4. 进度曲线（`ffa`）")
	lines.append("")
	lines.append("### 4.1 招牌路线总进度（每 %d 回合采样）" % CHECKPOINT_STEP)
	lines.append("")
	if ffa.is_empty():
		lines.append("_本模式未参与抽样。_")
		lines.append("")
		return lines
	lines.append("单元格为该流派**招牌胜利路线**的平均进度（`progress_of().ratio`，覆灭者计 0）。")
	lines.append("能直接看出「哪家前期滚得快、哪家到 240 回合还起不来」。")
	lines.append("")
	var turn_marks: Array = _checkpoint_turns(ffa)
	var header: Array[String] = ["回合"]
	for faction: String in FACTION_ALL:
		header.append(faction)
	lines.append("| %s |" % " | ".join(header))
	lines.append("|%s|" % "|".join(_repeat("---", header.size())))
	for turn_mark: int in turn_marks:
		var row: Array[String] = [str(turn_mark)]
		for faction: String in FACTION_ALL:
			var values: Array = []
			for sample: Dictionary in ffa:
				var snapshot: Dictionary = _snapshot_at(sample, turn_mark)
				if snapshot.is_empty():
					continue
				for entry: Dictionary in (snapshot["sects"] as Array):
					if str(entry["faction"]) == faction:
						values.append(float(entry["signatureRatio"]))
			row.append("—" if values.is_empty() else _pct(_percent(_mean(values)), 100))
		lines.append("| %s |" % " | ".join(row))
	lines.append("")
	lines.append("各流派在**全部采样点**上取到的最高进度（比「终局进度」更能看出差多远）：")
	lines.append("")
	var peak_parts: Array[String] = []
	for faction: String in FACTION_ALL:
		var peak: float = 0.0
		for sample: Dictionary in ffa:
			for snapshot: Dictionary in (sample.get("checkpoints", []) as Array):
				for entry: Dictionary in (snapshot["sects"] as Array):
					if str(entry["faction"]) == faction:
						peak = maxf(peak, float(entry["signatureRatio"]))
		peak_parts.append("%s %s" % [faction, _pct(_percent(peak), 100)])
	lines.append("- " + "；".join(peak_parts) + "。")
	lines.append("")
	lines.append_array(_render_goal_breakdown(ffa))
	return lines


## §4.2 招牌路线的**目标级**拆解：每个目标单独算平均完成率，最低的那格加粗为「卡点」。
## 这是把「路线进度 33%」翻译成「卡在飞升 0/4」的唯一办法——只看总进度无法定位。
##
## **覆灭席位用「最后一次存活快照」兜底**：覆灭时 `collapse_sect` 会清空弟子与灵峰，
## 终局指标全是 0，若直接取终局就等于把这家的诊断信息丢掉——而「它为什么先死」恰恰最值得看。
func _render_goal_breakdown(ffa: Array) -> Array[String]:
	var lines: Array[String] = []
	lines.append("### 4.2 招牌路线卡在哪个目标")
	lines.append("")
	lines.append("每格是该目标在全部席位上的平均完成率，**加粗**的是该流派完成率最低的目标（卡点）。")
	lines.append("这一节回答的是「为什么总进度上不去」：总进度只是几个目标的平均，不拆开就无从下手。")
	lines.append("覆灭席位取其**最后一次存活快照**（覆灭会清空弟子与灵峰，直接取终局只会得到一片 0）。")
	lines.append("")
	lines.append("| 流派 | 目标 1 | 目标 2 | 目标 3 | 目标 4 |")
	lines.append("|---|---|---|---|---|")
	for faction: String in FACTION_ALL:
		var names: Array[String] = []
		var buckets: Dictionary = {}
		for sample: Dictionary in ffa:
			var alive_last: Dictionary = {}
			for snapshot: Dictionary in (sample.get("checkpoints", []) as Array):
				for entry: Dictionary in (snapshot["sects"] as Array):
					if not bool(entry["defeated"]):
						alive_last[str(entry["id"])] = entry
			for entry: Dictionary in (sample.get("finalSects", []) as Array):
				if str(entry["faction"]) != faction:
					continue
				var source: Dictionary = entry
				if (entry.get("signatureGoals", []) as Array).is_empty():
					source = alive_last.get(str(entry["id"]), {})
				for goal: Dictionary in (source.get("signatureGoals", []) as Array):
					var goal_name: String = str(goal["name"])
					if not buckets.has(goal_name):
						buckets[goal_name] = []
						names.append(goal_name)
					(buckets[goal_name] as Array).append(float(goal["ratio"]))
		var cells: Array[String] = []
		var lowest: String = ""
		var lowest_value: float = 2.0
		for goal_name: String in names:
			var value: float = _mean(buckets[goal_name])
			cells.append("%s %s" % [goal_name, _pct(_percent(value), 100)])
			if value < lowest_value:
				lowest_value = value
				lowest = goal_name
		for index: int in range(cells.size()):
			if names[index] == lowest:
				cells[index] = "**%s**" % cells[index]
		while cells.size() < 4:
			cells.append("—")
		lines.append("| %s | %s |" % [faction, " | ".join(cells)])
	lines.append("")
	return lines


# ---------------------------------------------------------------------------
# §5 观察与建议
# ---------------------------------------------------------------------------

func _render_conclusion(ffa: Array, player: Array) -> Array[String]:
	var lines: Array[String] = []
	lines.append("## 5. 观察与建议")
	lines.append("")
	lines.append("**本节只陈述抽样里看到的事实并给建议，不自动改任何数值**——")
	lines.append("改平衡属于产品决策，须由人裁决后单独提交（沿用 R8 裁决五）。")
	lines.append("")
	lines.append("### 5.1 客观事实")
	lines.append("")
	if not ffa.is_empty():
		var seats: Array = _seat_rows(ffa)
		var dead: int = 0
		for row: Dictionary in seats:
			if bool(row["defeated"]):
				dead += 1
		lines.append("- `ffa` 共 %d 局、%d 个席位；终局时覆灭 %d 席（%s）。" % [
			ffa.size(), seats.size(), dead, _pct(dead, seats.size()),
		])
		lines.append("- 其中 **%d 局靠分数兜底**（`%s`）、%d 局靠招牌路线、%d 局打满未终局。" % [
			_score_settled(ffa), str(VictoryRules.ROUTE_NAMES[VictoryRules.ROUTE_SCORE]),
			ffa.size() - _score_settled(ffa) - _unsettled(ffa), _unsettled(ffa),
		])
		lines.append("- 平均结束回合 %.1f（中位 %.0f，范围 %d–%d）。" % [
			_mean(_turns_of(ffa)), _median(_turns_of(ffa)),
			int(_min_of(_turns_of(ffa))), int(_max_of(_turns_of(ffa))),
		])
		var top: String = _top_faction(ffa)
		if not top.is_empty():
			lines.append("- 夺冠最多的流派是 **%s**（%d 局）。" % [top, _wins_of(ffa, top)])
		for faction: String in FACTION_ALL:
			var appear: int = 0
			var wins: int = 0
			var faction_dead: int = 0
			for row: Dictionary in seats:
				if str(row["faction"]) != faction:
					continue
				appear += 1
				if bool(row["winner"]):
					wins += 1
				if bool(row["defeated"]):
					faction_dead += 1
			lines.append("- **%s**：出场 %d 席，夺冠 %d（%s），覆灭 %d（%s）。" % [
				faction, appear, wins, _pct(wins, appear), faction_dead, _pct(faction_dead, appear),
			])
		var worst_faction: String = ""
		var worst_dead: int = -1
		for faction: String in FACTION_ALL:
			var faction_dead: int = 0
			for row: Dictionary in seats:
				if str(row["faction"]) == faction and bool(row["defeated"]):
					faction_dead += 1
			if faction_dead > worst_dead:
				worst_dead = faction_dead
				worst_faction = faction
		if worst_dead > 0:
			var reason_counts: Dictionary = {}
			for row: Dictionary in seats:
				if str(row["faction"]) != worst_faction or not bool(row["defeated"]):
					continue
				var reason: String = str(row["reason"])
				reason_counts[reason] = int(reason_counts.get(reason, 0)) + 1
			var top_reason: String = ""
			var top_count: int = -1
			for reason: String in reason_counts.keys():
				if int(reason_counts[reason]) > top_count:
					top_count = int(reason_counts[reason])
					top_reason = reason
			lines.append("- 覆灭最集中的是 **%s**（%d 席），主因「%s」（%d 次）。" % [
				worst_faction, worst_dead, top_reason, top_count,
			])
		var min_peaks: int = 99
		var max_peaks: int = 0
		var max_tiles: int = 0
		for row: Dictionary in seats:
			var entry: Dictionary = row["entry"]
			if bool(entry["defeated"]):
				continue
			min_peaks = mini(min_peaks, int(entry["peaks"]))
			max_peaks = maxi(max_peaks, int(entry["peaks"]))
			max_tiles = maxi(max_tiles, int(entry["tiles"]))
		if max_peaks > 0:
			lines.append("- 存续席位终局灵峰 %d–%d 座、控制地块最多 %d 格%s。" % [
				min_peaks, max_peaks, max_tiles,
				"；**全场没有一家开出第二座峰**，扩张事实上停滞" if max_peaks <= 1 else "",
			])
	if not player.is_empty():
		for faction: String in FACTION_ALL:
			var wins: int = 0
			var total: int = 0
			for sample: Dictionary in player:
				if str(sample["playerFaction"]) != faction:
					continue
				total += 1
				var probe_id: String = str(sample["probeId"])
				if not probe_id.is_empty() and str(sample["winnerSectId"]) == probe_id:
					wins += 1
			lines.append("- `player` 模式下选 **%s** 通关 %d/%d（%s）。" % [
				faction, wins, total, _pct(wins, total),
			])
	lines.append("")
	lines.append("### 5.2 判读注意")
	lines.append("")
	lines.append("- 本抽样里**四个席位用同一套 `AIController` 决策**，差异全部来自流派规则本身。")
	lines.append("  它能回答「流派强度」与「AI 是否能自己走到胜利」，**不能**回答「人类玩家操作水平」——")
	lines.append("  真人会主动补经济、抢资源点、按路线挑道法，通常显著快于这里的数字。")
	lines.append("- `ffa` 允许某家覆灭后其他人继续打到上限，`player` 一覆灭即终局，")
	lines.append("  故同一流派的「平均结束回合」在两表里不可直接相减。")
	lines.append("- AI 不走 `chooseVictory`（多路线同回合达成时取第一条），")
	lines.append("  因此「同时达成多条路线」在样本里会被压成单一结局，路线分布偏保守。")
	lines.append("- `AIController` 的行动优先级是「攻击 → 扩张 → 探索 → 研究 → 驻守 → 收徒 → 血脉 → 修路」，")
	lines.append("  每类先掷一次倾向骰再尝试，故 `researchTendency=0.4` 这类低倾向会明显拖慢道统路线——")
	lines.append("  这是「AI 走不到」而非「路线不可达」的主因之一。")
	lines.append("")
	lines.append("### 5.3 若要调平衡，建议先动的旋钮")
	lines.append("")
	lines.append("按「改一处、影响面最小」排序（都只动 `data/gameConfig.json`，不碰代码）：")
	lines.append("")
	lines.append("| 优先级 | 旋钮 | 作用 |")
	lines.append("|---|---|---|")
	lines.append("| 1 | `ai.<某流派倾向>` / `ai.actionPoints` | 直接改 AI 每回合的行动预算与各类尝试概率，最灵敏 |")
	lines.append("| 2 | `victory.<流派>.expectedMin/MaxTurns` | 只改「预期」不改变际，用于先把文档口径与实测对齐 |")
	lines.append("| 3 | `victory.<流派>` 的达成阈值 | 改难度本身，影响面最大，最后动 |")
	lines.append("")
	return lines


# ---------------------------------------------------------------------------
# 统计辅助
# ---------------------------------------------------------------------------

## 把样本摊平成「席位行」：一局四席 → 四行，带流派、是否夺冠、覆灭回合与原因。
## §2 的所有聚合都基于它，避免每处重复遍历 finalSects。
func _seat_rows(samples: Array) -> Array:
	var rows: Array = []
	for sample: Dictionary in samples:
		var collapses: Dictionary = sample.get("collapses", {})
		for entry: Dictionary in (sample.get("finalSects", []) as Array):
			var sect_id: String = str(entry["id"])
			var collapse: Dictionary = collapses.get(sect_id, {})
			rows.append({
				"faction": str(entry["faction"]),
				"defeated": bool(entry["defeated"]),
				"winner": sect_id == str(sample.get("winnerSectId", "")),
				"endTurn": int(sample.get("turns", 0)),
				"collapseTurn": int(collapse.get("turn", sample.get("turns", 0))),
				"reason": str(collapse.get("reason", "未记录")),
				"entry": entry,
			})
	return rows


func _filter(samples: Array, mode: String) -> Array:
	var result: Array = []
	for sample: Dictionary in samples:
		if bool(sample.get("ok", false)) and str(sample.get("mode", "")) == mode:
			result.append(sample)
	return result


func _turns_of(samples: Array) -> Array:
	var result: Array = []
	for sample: Dictionary in samples:
		result.append(float(sample.get("turns", 0)))
	return result


## 以分数兜底路线收尾的局数（`winType` 等于分数路线的显示名）。
func _score_settled(samples: Array) -> int:
	var name: String = str(VictoryRules.ROUTE_NAMES[VictoryRules.ROUTE_SCORE])
	var count: int = 0
	for sample: Dictionary in samples:
		if str(sample.get("winType", "")) == name:
			count += 1
	return count


func _unsettled(samples: Array) -> int:
	var count: int = 0
	for sample: Dictionary in samples:
		if str(sample.get("winType", "")).is_empty():
			count += 1
	return count


func _wins_of(samples: Array, faction: String) -> int:
	var count: int = 0
	for sample: Dictionary in samples:
		if str(sample.get("winnerFaction", "")) == faction:
			count += 1
	return count


func _top_faction(samples: Array) -> String:
	var best: String = ""
	var best_count: int = -1
	for faction: String in FACTION_ALL:
		var count: int = _wins_of(samples, faction)
		if count > best_count:
			best_count = count
			best = faction
	return "" if best_count <= 0 else best


func _index_of(sample: Dictionary) -> int:
	var seed_text: String = str(sample.get("seed", ""))
	var pieces: PackedStringArray = seed_text.split("-")
	return int(pieces[pieces.size() - 1]) if pieces.size() > 0 else 0


func _checkpoint_turns(samples: Array) -> Array:
	var seen: Array = []
	for sample: Dictionary in samples:
		for snapshot: Dictionary in (sample.get("checkpoints", []) as Array):
			var turn_no: int = int(snapshot["turn"])
			if not seen.has(turn_no):
				seen.append(turn_no)
	seen.sort()
	return seen


func _snapshot_at(sample: Dictionary, turn_no: int) -> Dictionary:
	for snapshot: Dictionary in (sample.get("checkpoints", []) as Array):
		if int(snapshot["turn"]) == turn_no:
			return snapshot
	return {}


func _signature_route(faction: String) -> String:
	var routes: Array[String] = VictoryRules.routes_for(_config, faction)
	return "" if routes.is_empty() else routes[0]


## 招牌路线的配置预期回合区间（`victory.<key>.expectedMinTurns/expectedMaxTurns`）。
func _expected_window(faction: String) -> Dictionary:
	var route: String = _signature_route(faction)
	var key: String = ""
	match route:
		VictoryRules.ROUTE_ZONG_MEN: key = "zongMen"
		VictoryRules.ROUTE_JIA_ZU: key = "jiaZu"
		VictoryRules.ROUTE_GUO_JIA: key = "guoJia"
		_: key = ""
	if key.is_empty():
		return {"min": 0, "max": _max_turns}
	var block: Dictionary = _config["victory"][key]
	return {"min": int(block.get("expectedMinTurns", 0)), "max": int(block.get("expectedMaxTurns", _max_turns))}


func _mean(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var sum: float = 0.0
	for value: Variant in values:
		sum += float(value)
	return sum / float(values.size())


func _median(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var sorted: Array = values.duplicate()
	sorted.sort()
	var middle: int = sorted.size() / 2
	if sorted.size() % 2 == 1:
		return float(sorted[middle])
	return (float(sorted[middle - 1]) + float(sorted[middle])) / 2.0


func _min_of(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var best: float = float(values[0])
	for value: Variant in values:
		best = minf(best, float(value))
	return best


func _max_of(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var best: float = float(values[0])
	for value: Variant in values:
		best = maxf(best, float(value))
	return best


## 0..1 比例 → 百分数整数（四舍五入）。
func _percent(ratio: float) -> int:
	return int(round(clampf(ratio, 0.0, 1.0) * 100.0))


func _pct(part: int, total: int) -> String:
	if total <= 0:
		return "—"
	return "%.0f%%" % (100.0 * float(part) / float(total))


func _repeat(text: String, count: int) -> Array[String]:
	var result: Array[String] = []
	for _index: int in range(count):
		result.append(text)
	return result


## 把可读 seed 文本映射成 `randomSeed` 要求的十进制整数（与 `R7Test._seed_of` 同算法，
## 保证跨工具的种子口径一致）。
func _seed_of(text: String) -> int:
	var value: int = 700001
	for index: int in range(text.length()):
		value = (value * 131 + text.unicode_at(index) + index) % 900000000
	return value + 1
