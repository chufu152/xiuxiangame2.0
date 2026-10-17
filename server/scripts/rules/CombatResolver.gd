class_name CombatResolver
extends RefCounted
## 战斗的**唯一结算入口**（R5，对齐 1.0 `core/CombatResolver.java`）。
##
## **裁决三（预览 == 实战）**：`preview()` 与 `resolve_attack()` 都先走同一个 `_build_matchup()`，
## 战力/相克/地形/城防/反击/胜率全部同源，不存在「预览算一套、实战算另一套」。
##
## 目标性质决定结算分支（与 1.0 `findTarget` 同源）：
##   `PEAK` 夺峰（有敌方灵峰）→ `SIEGE_OCCUPIED` / `SIEGE_REPELLED`
##   `NODE` 夺点（有敌方节点）→ `CONTEST_WON` / `CONTEST_LOST`
##   `DUEL` 野战（只有敌方弟子）→ 败方按 `fallChanceOnLoss`/`injuryChanceOnLoss`/`captureChanceOnLoss` 掷结局
##
## **所有随机只经 `state.rng`**（胜率掷骰、每回合 ±`roundPowerNoise`、败方结局、撤退成败）；
## ZOC 无随机。同种子 + 同指令序列必然逐字一致。
##
## 未接（明确留给后续里程碑）：`policy` 战力加成（R6）、外交状态（2.0 已裁剪，裁决六）。

## 未找到可攻击目标时的空目标。
const NO_TARGET: Dictionary = {}
## 2.0 无外交系统（PRD 已裁剪），故不实现 1.0 的「未交战需先宣战」前置（裁决六）。


# ---------------------------------------------------------------------------
# 基础战力
# ---------------------------------------------------------------------------

## 战力 = 境界等级×`realmPowerWeight` + 灵根品级×`rootGradePowerWeight` + 道法 `COMBAT_BONUS`，
## 再乘重伤/心魔惩罚。取整用 `round`（1.0 同源）。
static func compute_power(state: GameState, config: Dictionary, disciple: Disciple) -> int:
	if disciple == null: return 0
	var combat: Dictionary = config["combat"]
	var power: float = float(disciple.realmLevel) * float(combat["realmPowerWeight"]) \
		+ float(disciple.rootGrade) * float(combat["rootGradePowerWeight"])
	var sect: Sect = _sect_of(state, disciple.sectId)
	if sect != null:
		power += float(DaoRules.effect_sum(state, config, sect).get("COMBAT_BONUS", 0.0))
		# 政令战力加成（R6）：`tie_lv_jun_gui` +10% / `yi_zhan_yang_zhan` +5% / `jun_quan` +10%。
		# 按 1.0 `CombatResolver` 口径是**乘法**（`power *= 1 + combatBonus`），未颁卡时 ×1.0。
		power *= 1.0 + PolicyRules.combat_bonus(state, config, sect)
	if disciple.injured:
		power *= 1.0 - float(combat["injuryPowerPenalty"])
	if disciple.heartDevil >= int(combat["heartDevilHighThreshold"]):
		power *= 1.0 - float(combat["heartDevilHighPenalty"])
	elif disciple.heartDevil >= int(combat["heartDevilLowThreshold"]):
		power *= 1.0 - float(combat["heartDevilLowPenalty"])
	return int(round(power))


## 胜率：达 `powerRatioThreshold` 即碾压（强方 1.0 / 弱方 0.0），否则均势公式，夹取 [0.02, 0.98]。
static func estimate_win_chance(config: Dictionary, attacker_power: int, defender_power: int) -> float:
	var combat: Dictionary = config["combat"]
	var maximum: int = maxi(attacker_power, defender_power)
	var minimum: int = maxi(1, mini(attacker_power, defender_power))
	if float(maximum) / float(minimum) >= float(combat["powerRatioThreshold"]):
		return 1.0 if attacker_power > defender_power else 0.0
	var chance: float = float(combat["baseWinChance"]) \
		+ 0.5 * float(attacker_power - defender_power) / float(maxi(1, attacker_power + defender_power))
	return clampf(chance, 0.02, 0.98)


# ---------------------------------------------------------------------------
# 攻击预览（只读）
# ---------------------------------------------------------------------------

## PROTOCOL §3 `queryAttackPreview` 的 `BattlePreview` 全字段 + `targetTileId`。
static func preview(state: GameState, config: Dictionary, attacker_id: String, target_tile_id: String) -> Dictionary:
	var attacker: Disciple = _find_disciple(state, attacker_id)
	var out: Dictionary = {
		"targetTileId": target_tile_id,
		"attackable": false,
		"blockedReason": "",
		"attackerId": attacker_id,
		"defenderId": "",
		"attackerClass": UnitRules.class_of(attacker),
		"defenderClass": Enums.UnitClass.PU_TONG,
		"attackerPower": 0,
		"defenderPower": 0,
		"counterMultiplier": 1.0,
		"winChance": 0.0,
		"ranged": false,
		"beyondMeleeContact": false,
		"retaliationPower": 0,
		"distance": 0,
		"xpPreview": 0,
		"notes": [] as Array,
	}
	var blocker: String = attack_blocker(state, config, attacker, target_tile_id)
	if not blocker.is_empty():
		out["blockedReason"] = blocker
		if attacker != null and state.tiles.has(target_tile_id):
			out["distance"] = _distance(state.tiles[attacker.tileId], state.tiles[target_tile_id])
		return out
	var target: Dictionary = _target_of(state, config, attacker, target_tile_id)
	var matchup: Dictionary = _build_matchup(state, config, [attacker], _defenders_of(state, target), target.get("peak", null))
	out["attackable"] = true
	var anchor: Disciple = _strongest_of(state, config, _defenders_of(state, target))
	out["defenderId"] = "" if anchor == null else anchor.id
	out["defenderClass"] = Enums.UnitClass.PU_TONG if anchor == null else UnitRules.class_of(anchor)
	out["attackerPower"] = int(matchup["attackerPower"])
	out["defenderPower"] = int(matchup["defenderPower"])
	out["counterMultiplier"] = float(matchup["counterMultiplier"])
	out["winChance"] = float(matchup["winChance"])
	out["ranged"] = bool(matchup["ranged"])
	out["beyondMeleeContact"] = bool(matchup["ranged"])
	out["retaliationPower"] = int(matchup["retaliationPower"])
	out["distance"] = int(matchup["distance"])
	out["xpPreview"] = int(matchup["xpIfVictory"])
	out["notes"] = (matchup["notes"] as Array).duplicate()
	return out


## PROTOCOL §3 `queryAttackable`：`{discipleId, range, tileIds[], tileCount}`。
## 「可攻击」判定直接复用 `preview().attackable`，故高亮范围与实际能打的格子必然一致。
static func attackable(state: GameState, config: Dictionary, disciple_id: String) -> Dictionary:
	var disciple: Disciple = _find_disciple(state, disciple_id)
	var tile_ids: Array[String] = []
	if disciple == null or disciple.tileId.is_empty():
		return {"discipleId": disciple_id, "range": 1, "tileIds": tile_ids, "tileCount": 0}
	var origin: HexTile = state.tiles.get(disciple.tileId, null)
	var reach: int = UnitRules.range_of(config, disciple)
	if origin == null:
		return {"discipleId": disciple_id, "range": reach, "tileIds": tile_ids, "tileCount": 0}
	for tile: HexTile in state.tiles.values():
		var distance: int = Hex.distance(Vector2i(origin.q, origin.r), Vector2i(tile.q, tile.r))
		if distance < 1 or distance > reach: continue
		if bool(preview(state, config, disciple_id, tile.id)["attackable"]): tile_ids.append(tile.id)
	return {"discipleId": disciple_id, "range": reach, "tileIds": tile_ids, "tileCount": tile_ids.size()}


# ---------------------------------------------------------------------------
# 攻击执行（权威）
# ---------------------------------------------------------------------------

## PROTOCOL §3 `attack` 的 `CombatResult` 全字段。
static func resolve_attack(state: GameState, config: Dictionary, attacker_id: String, target_tile_id: String) -> Dictionary:
	var attacker: Disciple = _find_disciple(state, attacker_id)
	var blocker: String = attack_blocker(state, config, attacker, target_tile_id)
	if not blocker.is_empty(): return _fail(blocker)
	var target: Dictionary = _target_of(state, config, attacker, target_tile_id)
	var kind: String = str(target["kind"])
	var result: Dictionary = {}
	match kind:
		"PEAK":
			result = _resolve_peak_siege(state, config, attacker, target["peak"])
		"NODE":
			result = _resolve_node_contest(state, config, attacker, target["node"])
		_:
			result = _resolve_duel(state, config, attacker, target["defender"])
	if bool(result["success"]):
		attacker.attacksRemaining -= 1
		attacker.movePoints = maxi(0, attacker.movePoints - maxi(0, int(config["warfare"]["attackMoveCost"])))
		if bool(result["attackerWon"]):
			# 胜战掠夺：地块改良被战火打残，产出停摆待修缮（R3 已实现的钩子，此处接线）。
			var tile: HexTile = state.tiles.get(target_tile_id, null)
			if tile != null:
				ImprovementRules.apply_pillage(state, config, tile, 1.0, "battle")
	return result


## 攻击前置校验：不合格返回原因（供 `preview.blockedReason`），合格返回空串。
static func attack_blocker(state: GameState, config: Dictionary, attacker: Disciple, target_tile_id: String) -> String:
	if attacker == null: return "攻方弟子不存在"
	if not state.tiles.has(target_tile_id): return "目标地块不存在：" + target_tile_id
	if attacker.injured: return attacker.name + " 身受重伤, 无力出手"
	if attacker.tribulating: return attacker.name + " 正在渡劫, 无法战斗"
	if attacker.position == Enums.Position.ZONG_ZHU: return "宗主坐镇宗门, 不亲自动手"
	if attacker.tileId.is_empty(): return attacker.name + " 尚未落位, 无法战斗"
	if attacker.attacksRemaining <= 0: return attacker.name + " 本回合已出手"
	var target: Dictionary = _target_of(state, config, attacker, target_tile_id)
	if target.is_empty(): return "该地块没有可攻击的敌方目标"
	var distance: int = _distance(state.tiles[attacker.tileId], state.tiles[target_tile_id])
	var reach: int = UnitRules.range_of(config, attacker)
	if distance > reach: return "超出射程(射程%d格, 相距%d格)" % [reach, distance]
	if attacker.movePoints < maxi(0, int(config["warfare"]["attackMoveCost"])): return attacker.name + " 移动力不足以发起攻击"
	return ""


# ---------------------------------------------------------------------------
# 撤退（权威）
# ---------------------------------------------------------------------------

## 主动撤退：概率脱离接触，失败则被咬住并耗尽移动力。
## result 形状同 `CombatResult`（PROTOCOL §3 `retreat`）。
static func retreat(state: GameState, config: Dictionary, disciple_id: String, to_tile_id: String) -> Dictionary:
	var disciple: Disciple = _find_disciple(state, disciple_id)
	if disciple == null: return _fail("弟子不存在: " + disciple_id)
	if not state.tiles.has(disciple.tileId) or not state.tiles.has(to_tile_id):
		return _fail("撤退起讫地块无效")
	var from_tile: HexTile = state.tiles[disciple.tileId]
	var to_tile: HexTile = state.tiles[to_tile_id]
	if Hex.distance(Vector2i(from_tile.q, from_tile.r), Vector2i(to_tile.q, to_tile.r)) != 1:
		return _fail("只能撤往相邻地块")
	if not MoveRules.is_passable(to_tile, config): return _fail("撤退目标不可通行")
	var own: Sect = _sect_of(state, disciple.sectId)
	if own == null: return _fail("弟子宗门不存在")
	var cost: int = maxi(0, int(config["warfare"]["retreatMoveCost"]))
	if disciple.movePoints < cost: return _fail("移动力不足以撤退(需%d)" % cost)
	if not to_tile.ownerSectId.is_empty() and to_tile.ownerSectId != own.id:
		return _fail("不可撤入敌占地块: " + to_tile_id)
	var chance: float = UnitRules.retreat_chance(config, disciple)
	var result: Dictionary = _empty_result()
	result["notes"].append("撤退概率%d%%" % int(round(chance * 100.0)))
	disciple.attacksRemaining = 0
	if state.rng.chance(chance):
		disciple.movePoints -= cost
		disciple.tileId = to_tile_id
		VisionCalculator.recalculate(state, config)
		result["success"] = true
		result["outcome"] = Enums.CombatOutcome.REPEL
		result["message"] = "%s 撤退成功, 脱离接触至 %s" % [disciple.name, to_tile_id]
		state.eventLog.append("[撤退] %s → %s: 成功" % [disciple.name, to_tile_id])
	else:
		disciple.movePoints = 0
		result["success"] = false
		result["message"] = "%s 撤退失败, 被咬住在 %s" % [disciple.name, from_tile.id]
		state.eventLog.append("[撤退] %s → %s: 失败" % [disciple.name, to_tile_id])
	return result


# ---------------------------------------------------------------------------
# 对阵口径（预览与实战的唯一共同来源）
# ---------------------------------------------------------------------------

## 一次对阵的完整战术口径。`peak` 非 null 表示攻城（城防生效）。
static func _build_matchup(state: GameState, config: Dictionary, attackers: Array, defenders: Array, peak: Variant) -> Dictionary:
	var warfare: Dictionary = config["warfare"]
	var lead: Disciple = attackers[0] if not attackers.is_empty() else null
	var anchor: Disciple = _strongest_of(state, config, defenders)
	var attack_tile: HexTile = state.tiles.get(lead.tileId, null) if lead != null else null
	var defend_tile: HexTile = null
	if anchor != null:
		defend_tile = state.tiles.get(anchor.tileId, null)
	elif peak != null:
		defend_tile = state.tiles.get((peak as SpiritPeak).tileId, null)
	var distance: int = _distance(attack_tile, defend_tile)
	var ranged: bool = distance > 1
	var high_ground: float = UnitRules.high_ground_bonus(config, attack_tile, defend_tile)
	var river: float = UnitRules.river_penalty(config, attack_tile, defend_tile)
	var notes: Array = []

	var attack_sum: float = 0.0
	for attacker: Disciple in attackers:
		var single: float = float(compute_power(state, config, attacker)) * UnitRules.attack_multiplier(config, attacker)
		if anchor != null:
			single *= UnitRules.counter_multiplier(config, UnitRules.class_of(attacker), UnitRules.class_of(anchor))
		single *= 1.0 + high_ground - river
		if peak != null and not UnitRules.is_siege_unit(config, attacker):
			single *= float(warfare["fortificationRatio"])
		attack_sum += single
	var fortified: bool = peak != null and not attackers.is_empty() \
		and not UnitRules.is_siege_unit(config, attackers[0])

	var defense_sum: float = 0.0
	for defender: Disciple in defenders:
		var single: float = float(compute_power(state, config, defender)) * UnitRules.defense_multiplier(config, defender)
		single *= 1.0 + UnitRules.terrain_defense_bonus(config, state.tiles.get(defender.tileId, null)) \
			+ UnitRules.garrison_defense_bonus(state, config, defender)
		defense_sum += single
	if peak != null:
		var city: SpiritPeak = peak
		defense_sum += float(city.defense) * (1.0 - UnitRules.siege_defense_cut(config, city))

	var counter: float = 1.0
	if anchor != null and lead != null:
		counter = UnitRules.counter_multiplier(config, UnitRules.class_of(lead), UnitRules.class_of(anchor))
	# 贴身才挨反击；射程外打击零反击。
	var retaliation: int = 0
	if not ranged and anchor != null:
		retaliation = int(round(float(compute_power(state, config, anchor)) * UnitRules.retaliation_of(config, anchor)))

	# notes 与 1.0 `describe()` 同源，供 UI 直接展示。
	if anchor != null and lead != null:
		notes.append("%s 对 %s 相克x%.2f" % [
			UnitRules.class_name_of(config, UnitRules.class_of(lead)),
			UnitRules.class_name_of(config, UnitRules.class_of(anchor)), counter])
	if high_ground > 0.0: notes.append("踞高下击 +%d%%" % int(round(high_ground * 100.0)))
	if river > 0.0: notes.append("涉水攻坚 -%d%%" % int(round(river * 100.0)))
	if fortified: notes.append("灵峰城防: 普通兵种输出x%.2f, 需攻城单位破防" % float(warfare["fortificationRatio"]))
	if defenders.is_empty(): notes.append("守方无人驻守")
	if ranged: notes.append("射程%d格打击, 守方无法反击" % distance)
	elif retaliation > 0: notes.append("守方可反击%d战力" % retaliation)

	var attacker_power: int = int(round(attack_sum))
	var defender_power: int = int(round(defense_sum))
	return {
		"attackerPower": attacker_power,
		"defenderPower": defender_power,
		"retaliationPower": retaliation,
		"distance": distance,
		"xpIfVictory": int(config["warfare"]["xpPerVictory"]) + int(config["warfare"]["xpPerKill"]),
		"counterMultiplier": counter,
		"winChance": estimate_win_chance(config, attacker_power, defender_power),
		"ranged": ranged,
		"fortified": fortified,
		"notes": notes,
	}


# ---------------------------------------------------------------------------
# 三种结算分支
# ---------------------------------------------------------------------------

## 野战：单挑，败方按概率掷「陨落/重伤/俘虏/击退」。
static func _resolve_duel(state: GameState, config: Dictionary, attacker: Disciple, defender: Disciple) -> Dictionary:
	var matchup: Dictionary = _build_matchup(state, config, [attacker], [defender], null)
	var result: Dictionary = _empty_result()
	_apply_matchup(result, matchup)
	var attacker_won: bool = _decide_winner(state, config, int(matchup["attackerPower"]), int(matchup["defenderPower"]), result)
	result["attackerWon"] = attacker_won
	var winner: Disciple = attacker if attacker_won else defender
	var loser: Disciple = defender if attacker_won else attacker
	var winner_sect: Sect = _sect_of(state, winner.sectId)
	var loser_sect: Sect = _sect_of(state, loser.sectId)
	# 「初战告捷」成就口径：击败**他宗弟子**（1.0 `resolveCombat` 同源）。
	if winner_sect != null and loser_sect != null and winner_sect.id != loser_sect.id:
		winner_sect.enemiesDefeated += 1
		_award_battle_prestige(config, winner_sect)
	var outcome: String = _roll_loser_outcome(state, config)
	result["outcome"] = outcome
	_apply_outcome(state, loser, outcome, winner_sect, result)
	_award_experience(result, state, config, [winner], [loser], outcome)
	_apply_retaliation(result, state, config, winner, matchup)
	result["success"] = true
	result["message"] = "%s(战力%d) 对阵 %s(战力%d): %s胜, %s%s" % [
		attacker.name, int(matchup["attackerPower"]), defender.name, int(matchup["defenderPower"]),
		winner.name, loser.name, str(Enums.CombatOutcome.NAMES.get(outcome, outcome))]
	state.eventLog.append("[战斗] " + str(result["message"]))
	return result


## 夺峰：攻方胜则灵峰易主、守方全部败退；攻方败则被击退。
static func _resolve_peak_siege(state: GameState, config: Dictionary, attacker: Disciple, peak: SpiritPeak) -> Dictionary:
	var defender_sect: Sect = _sect_of(state, peak.sectId)
	if defender_sect == null: return _fail("灵峰无归属宗门: " + peak.name)
	var attacker_sect: Sect = _sect_of(state, attacker.sectId)
	if attacker_sect == null or attacker_sect.id == defender_sect.id: return _fail("攻方宗门无效")
	var defenders: Array = _defenders_of_peak(state, defender_sect, peak)
	var matchup: Dictionary = _build_matchup(state, config, [attacker], defenders, peak)
	var result: Dictionary = _empty_result()
	_apply_matchup(result, matchup)
	var attacker_won: bool = _decide_winner(state, config, int(matchup["attackerPower"]), int(matchup["defenderPower"]), result)
	result["attackerWon"] = attacker_won
	if attacker_won:
		result["outcome"] = Enums.CombatOutcome.SIEGE_OCCUPIED
		_transfer_peak(state, config, peak, defender_sect, attacker_sect)
		for defender: Disciple in defenders:
			_apply_outcome(state, defender, _roll_loser_outcome(state, config), attacker_sect, result)
		result["message"] = "攻方%s 攻入 %s: 占领成功, 守方%d人+防御%d败退" % [
			attacker_sect.name, peak.name, defenders.size(), peak.defense]
	else:
		result["outcome"] = Enums.CombatOutcome.SIEGE_REPELLED
		_apply_outcome(state, attacker, _roll_loser_outcome(state, config), defender_sect, result)
		result["message"] = "攻方%s 攻入 %s: 被守方击退" % [attacker_sect.name, peak.name]
	result["success"] = true
	_award_battle_prestige(config, attacker_sect if attacker_won else defender_sect)
	var winners: Array = [attacker] if attacker_won else defenders
	var losers: Array = defenders if attacker_won else [attacker]
	_award_experience(result, state, config, winners, losers, str(result["outcome"]))
	state.eventLog.append("[战斗] " + str(result["message"]))
	return result


## 夺点：攻方胜则节点易主、地块归属转移；守方无人则直接占领（0 回合）。
static func _resolve_node_contest(state: GameState, config: Dictionary, attacker: Disciple, node: GameNode) -> Dictionary:
	var attacker_sect: Sect = _sect_of(state, attacker.sectId)
	if attacker_sect == null: return _fail("攻方宗门不存在")
	var defenders: Array = _defenders_of_node(state, node)
	var matchup: Dictionary = _build_matchup(state, config, [attacker], defenders, null)
	var result: Dictionary = _empty_result()
	_apply_matchup(result, matchup)
	var attacker_won: bool = true
	if not defenders.is_empty():
		attacker_won = _decide_winner(state, config, int(matchup["attackerPower"]), int(matchup["defenderPower"]), result)
	else:
		result["rounds"] = 0
	result["attackerWon"] = attacker_won
	if attacker_won:
		result["outcome"] = Enums.CombatOutcome.CONTEST_WON
		var old_owner: String = node.ownerSectId
		node.ownerSectId = attacker_sect.id
		var tile: HexTile = state.tiles.get(node.tileId, null)
		if tile != null and (tile.ownerSectId.is_empty() or tile.ownerSectId == old_owner):
			tile.ownerSectId = attacker_sect.id
		for defender: Disciple in defenders:
			node.garrisonDiscipleIds.erase(defender.id)
			if defender.garrisonNodeId == node.id: defender.garrisonNodeId = ""
			_apply_outcome(state, defender, _roll_loser_outcome(state, config), attacker_sect, result)
		result["message"] = "攻方%s 争夺 %s: 胜利, 节点易主" % [attacker_sect.name, node.id]
		# 节点是视野源：易主当场重算双方视野（R5 任务 7 的 SETTLEMENT 重算在此即时生效）。
		VisionCalculator.recalculate(state, config)
	else:
		result["outcome"] = Enums.CombatOutcome.CONTEST_LOST
		var defender_sect: Sect = _sect_of(state, node.ownerSectId)
		_apply_outcome(state, attacker, _roll_loser_outcome(state, config), defender_sect, result)
		result["message"] = "攻方%s 争夺 %s: 失败, 被守方击退" % [attacker_sect.name, node.id]
	result["success"] = true
	var winners: Array = [attacker] if attacker_won else defenders
	var losers: Array = defenders if attacker_won else [attacker]
	_award_battle_prestige(config, attacker_sect if attacker_won else _sect_of(state, node.ownerSectId))
	_award_experience(result, state, config, winners, losers, str(result["outcome"]))
	state.eventLog.append("[战斗] " + str(result["message"]))
	return result


# ---------------------------------------------------------------------------
# 胜负与结局
# ---------------------------------------------------------------------------

## 碾压（达 `powerRatioThreshold`）→ 1 回合速胜/速败；否则打 `roundsMin..roundsMax` 回合，
## 每回合 ±`roundPowerNoise` 噪声，多数回合定胜负，平票回落到胜率掷骰。
static func _decide_winner(state: GameState, config: Dictionary, attacker_power: int, defender_power: int, result: Dictionary) -> bool:
	var combat: Dictionary = config["combat"]
	var maximum: int = maxi(attacker_power, defender_power)
	var minimum: int = maxi(1, mini(attacker_power, defender_power))
	if float(maximum) / float(minimum) >= float(combat["powerRatioThreshold"]):
		result["rounds"] = 1
		return attacker_power > defender_power
	var rounds_min: int = maxi(1, int(combat["roundsMin"]))
	var rounds_max: int = maxi(rounds_min, int(combat["roundsMax"]))
	var rounds: int = rounds_min + state.rng.next_int(0, rounds_max - rounds_min)
	var noise: float = float(combat["roundPowerNoise"])
	var attacker_round_wins: int = 0
	for _index: int in range(rounds):
		var a: float = float(attacker_power) * (1.0 - noise + state.rng.next_float() * 2.0 * noise)
		var d: float = float(defender_power) * (1.0 - noise + state.rng.next_float() * 2.0 * noise)
		if a > d: attacker_round_wins += 1
	result["rounds"] = rounds
	if attacker_round_wins * 2 != rounds:
		return attacker_round_wins * 2 > rounds
	return state.rng.chance(estimate_win_chance(config, attacker_power, defender_power))


## 败方结局掷骰：`fallChanceOnLoss` → 陨落，再 `injuryChanceOnLoss` → 重伤，
## 再 `captureChanceOnLoss` → 俘虏，其余击退。
static func _roll_loser_outcome(state: GameState, config: Dictionary) -> String:
	var combat: Dictionary = config["combat"]
	var roll: float = state.rng.next_float()
	var fall: float = float(combat["fallChanceOnLoss"])
	var injury: float = float(combat["injuryChanceOnLoss"])
	var capture: float = float(combat["captureChanceOnLoss"])
	if roll < fall: return Enums.CombatOutcome.FALL
	if roll < fall + injury: return Enums.CombatOutcome.SERIOUS_INJURY
	if roll < fall + injury + capture: return Enums.CombatOutcome.CAPTURED
	return Enums.CombatOutcome.REPEL


## 落败结局的落地效果（1.0 `applyOutcome` 同源）。
static func _apply_outcome(state: GameState, loser: Disciple, outcome: String, winner_sect: Sect, result: Dictionary) -> void:
	match outcome:
		Enums.CombatOutcome.FALL:
			var sect: Sect = _sect_of(state, loser.sectId)
			if sect != null: sect.disciples.erase(loser)
			_clear_garrison(state, loser.id)
			for owner: Sect in state.sects:
				for peak: SpiritPeak in owner.spiritPeaks:
					if peak.fengZhuId == loser.id: peak.fengZhuId = ""
			result["casualties"].append(loser.id)
		Enums.CombatOutcome.SERIOUS_INJURY:
			loser.injured = true
			loser.movePoints = 0
		Enums.CombatOutcome.CAPTURED:
			var old_sect: Sect = _sect_of(state, loser.sectId)
			if old_sect != null:
				old_sect.disciples.erase(loser)
				loser.capturedFromSectId = old_sect.id
			if winner_sect != null and winner_sect.id != loser.sectId:
				loser.sectId = winner_sect.id
				loser.assignedPeakId = ""
				winner_sect.disciples.append(loser)
			_clear_garrison(state, loser.id)
			result["capturedIds"].append(loser.id)
		_:
			loser.movePoints = 0


## 灵峰易主：归属、峰主、地块所有权、双方视野全部重算。
static func _transfer_peak(state: GameState, config: Dictionary, peak: SpiritPeak, from_sect: Sect, to_sect: Sect) -> void:
	from_sect.spiritPeaks.erase(peak)
	to_sect.spiritPeaks.append(peak)
	peak.sectId = to_sect.id
	peak.fengZhuId = ""
	var tile: HexTile = state.tiles.get(peak.tileId, null)
	if tile != null:
		tile.ownerSectId = to_sect.id
		if not tile.nodeId.is_empty() and state.nodes.has(tile.nodeId):
			state.nodes[tile.nodeId].ownerSectId = to_sect.id
	# 灵峰是视野源：易主当场双方重算（不能等 SETTLEMENT）。
	VisionCalculator.recalculate(state, config)


## 胜战声望（`economy.prestigePerBattleWin`，配置为 3）。
static func _award_battle_prestige(config: Dictionary, winner_sect: Sect) -> void:
	if winner_sect == null: return
	var amount: int = int(config["economy"].get("prestigePerBattleWin", 0))
	if amount <= 0: return
	winner_sect.resources["prestige"] = int(winner_sect.resources.get("prestige", 0)) + amount


## 经验：胜方 `xpPerVictory` +（陨落另计 `xpPerKill`）+（夺峰/夺点 `xpPerObjective`）；
## 败方也给 `xpPerDefeat`（苦修经验）。
static func _award_experience(result: Dictionary, state: GameState, config: Dictionary, winners: Array, losers: Array, loser_outcome: String) -> void:
	var warfare: Dictionary = config["warfare"]
	var took_objective: bool = loser_outcome == Enums.CombatOutcome.SIEGE_OCCUPIED or loser_outcome == Enums.CombatOutcome.CONTEST_WON
	var winner_xp: int = int(warfare["xpPerVictory"])
	if loser_outcome == Enums.CombatOutcome.FALL: winner_xp += int(warfare["xpPerKill"])
	if took_objective: winner_xp += int(warfare["xpPerObjective"])
	var total: int = _grant_experience(state, config, winners, winner_xp) + _grant_experience(state, config, losers, int(warfare["xpPerDefeat"]))
	result["xpAwarded"] = total


static func _grant_experience(state: GameState, config: Dictionary, disciples: Array, xp: int) -> int:
	if disciples.is_empty() or xp <= 0: return 0
	var total: int = 0
	for disciple: Disciple in disciples:
		if _find_disciple(state, disciple.id) == null: continue
		total += xp
		if UnitRules.award_experience(config, disciple, xp) > 0:
			state.eventLog.append("[战技] %s 累计战功升至%d级, 可择一晋升" % [disciple.name, disciple.battleLevel])
	return total


## 近身交锋的反击落在**胜方**身上，以心魔反噬形式体现（远程零反击因此有实感）。
static func _apply_retaliation(result: Dictionary, state: GameState, _config: Dictionary, winner: Disciple, matchup: Dictionary) -> void:
	var retaliation: int = int(matchup["retaliationPower"])
	if retaliation <= 0 or _find_disciple(state, winner.id) == null: return
	var backlash: int = maxi(1, retaliation / 10)
	winner.heartDevil = mini(100, winner.heartDevil + backlash)
	result["notes"].append("%s 受反击心魔反噬+%d" % [winner.name, backlash])


# ---------------------------------------------------------------------------
# 目标判定
# ---------------------------------------------------------------------------

## 目标：`{}` 表示没有可攻击目标；否则 `{kind, peak, node, defender}`。
static func _target_of(state: GameState, config: Dictionary, attacker: Disciple, target_tile_id: String) -> Dictionary:
	if attacker == null: return NO_TARGET
	var peak: SpiritPeak = _enemy_peak_on(state, attacker, target_tile_id)
	if peak != null:
		var owner: Sect = _sect_of(state, peak.sectId)
		return {"kind": "PEAK", "peak": peak, "node": null,
			"defender": _strongest_of(state, {}, [] if owner == null else _defenders_of_peak(state, owner, peak))}
	var node: GameNode = _enemy_node_on(state, attacker, target_tile_id)
	if node != null:
		var garrison: Array = _defenders_of_node(state, node)
		return {"kind": "NODE", "peak": null, "node": node,
			"defender": _strongest_of(state, config, garrison)}
	var tile: HexTile = state.tiles.get(target_tile_id, null)
	if tile == null: return NO_TARGET
	var candidates: Array = []
	for sect: Sect in state.sects:
		if sect.id == attacker.sectId: continue
		for disciple: Disciple in sect.disciples:
			if disciple.tileId == target_tile_id: candidates.append(disciple)
	if candidates.is_empty(): return NO_TARGET
	return {"kind": "DUEL", "peak": null, "node": null, "defender": _strongest_of(state, config, candidates)}


static func _defenders_of(state: GameState, target: Dictionary) -> Array:
	if target.is_empty(): return []
	match str(target["kind"]):
		"PEAK":
			var peak: SpiritPeak = target["peak"]
			var owner: Sect = _sect_of(state, peak.sectId)
			return [] if owner == null else _defenders_of_peak(state, owner, peak)
		"NODE":
			return _defenders_of_node(state, target["node"])
		_:
			var defender: Disciple = target["defender"]
			return [] if defender == null else [defender]


static func _defenders_of_peak(state: GameState, owner: Sect, peak: SpiritPeak) -> Array:
	var out: Array = []
	for disciple: Disciple in owner.disciples:
		if disciple.tileId == peak.tileId or disciple.assignedPeakId == peak.id: out.append(disciple)
	return out


static func _defenders_of_node(state: GameState, node: GameNode) -> Array:
	var out: Array = []
	for disciple_id: String in node.garrisonDiscipleIds:
		var disciple: Disciple = _find_disciple(state, disciple_id)
		if disciple != null: out.append(disciple)
	return out


static func _enemy_peak_on(state: GameState, attacker: Disciple, tile_id: String) -> SpiritPeak:
	for sect: Sect in state.sects:
		if sect.id == attacker.sectId: continue
		for peak: SpiritPeak in sect.spiritPeaks:
			if peak.tileId == tile_id: return peak
	return null


static func _enemy_node_on(state: GameState, attacker: Disciple, tile_id: String) -> GameNode:
	var tile: HexTile = state.tiles.get(tile_id, null)
	if tile == null or tile.nodeId.is_empty(): return null
	if not state.nodes.has(tile.nodeId): return null
	var node: GameNode = state.nodes[tile.nodeId]
	if node.ownerSectId.is_empty() or node.ownerSectId == attacker.sectId: return null
	return node


# ---------------------------------------------------------------------------
# 内部工具
# ---------------------------------------------------------------------------

## 守方最强者（按战力）；多人会战的地形/相克/反击口径都取它。
static func _strongest_of(state: GameState, config: Dictionary, disciples: Array) -> Disciple:
	var best: Disciple = null
	var best_power: int = -1
	for disciple: Disciple in disciples:
		var power: int = compute_power(state, config, disciple)
		if power > best_power:
			best_power = power
			best = disciple
	return best


static func _clear_garrison(state: GameState, disciple_id: String) -> void:
	for node: GameNode in state.nodes.values():
		node.garrisonDiscipleIds.erase(disciple_id)


static func _distance(from_tile: HexTile, to_tile: HexTile) -> int:
	if from_tile == null or to_tile == null: return 0
	return Hex.distance(Vector2i(from_tile.q, from_tile.r), Vector2i(to_tile.q, to_tile.r))


static func _find_disciple(state: GameState, disciple_id: String) -> Disciple:
	for sect: Sect in state.sects:
		for disciple: Disciple in sect.disciples:
			if disciple.id == disciple_id: return disciple
	return null


static func _sect_of(state: GameState, sect_id: String) -> Sect:
	for sect: Sect in state.sects:
		if sect.id == sect_id: return sect
	return null


## `CombatResult` 的空骨架（字段与 PROTOCOL §3 `attack` 一字不差）。
static func _empty_result() -> Dictionary:
	return {
		"success": false,
		"outcome": "",
		"message": "",
		"attackerPower": 0,
		"defenderPower": 0,
		"rounds": 0,
		"attackerWon": false,
		"casualties": [] as Array,
		"capturedIds": [] as Array,
		"winChance": 0.0,
		"ranged": false,
		"retaliationPower": 0,
		"xpAwarded": 0,
		"notes": [] as Array,
	}


static func _apply_matchup(result: Dictionary, matchup: Dictionary) -> void:
	result["attackerPower"] = int(matchup["attackerPower"])
	result["defenderPower"] = int(matchup["defenderPower"])
	result["ranged"] = bool(matchup["ranged"])
	result["retaliationPower"] = int(matchup["retaliationPower"])
	result["winChance"] = float(matchup["winChance"])
	for note: String in matchup["notes"]: result["notes"].append(note)


static func _fail(message: String) -> Dictionary:
	var result: Dictionary = _empty_result()
	result["message"] = message
	return result
