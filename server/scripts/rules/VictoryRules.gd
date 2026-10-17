class_name VictoryRules
extends RefCounted
## 胜负 / 分数 / 势力等级（对齐 1.0 `core/VictoryCalculator` + `GameEngine` 的胜负段）。
##
## **数值全部读 `data/gameConfig.json` 的 `victory` / `powerLevel` / `faction` 节**（裁决四/五/六）。
## 本类是胜负判定的唯一入口：`TurnProcessor._run_victory_check` 只调 `process_victory_check`。
##
## 四条路线 id **与 1.0 `VictoryRoute.name()` 逐字一致**（`chooseVictory(routeId)` 认的就是它）：
## `ZONG_MEN_DAOTONG` / `JIA_ZU_ASCENSION` / `GUO_JIA_UNIFICATION` / `SCORE_SUPREMACY`。
##
## `queryVictoryProgress.routes[].goals[]` 内部形状（裁决三，已回 1.0 `entity/VictoryGoal.java`
## 与 `entity/VictoryProgress.java` 逐字段核对）：
## 1.0 `VictoryGoal` 有 5 个字段 `{name, current, target, unit, description}`，
## 另有 4 个派生方法 `getRatio()` / `isMet()` / `missingText()` / `valueText()`。
## 客户端零规则（硬约束 2），故把派生值一并下发，共 9 键——全部可追溯到 1.0，不臆造。

const ROUTE_ZONG_MEN: String = "ZONG_MEN_DAOTONG"
const ROUTE_JIA_ZU: String = "JIA_ZU_ASCENSION"
const ROUTE_GUO_JIA: String = "GUO_JIA_UNIFICATION"
const ROUTE_SCORE: String = "SCORE_SUPREMACY"
const ROUTE_ALL: Array[String] = [ROUTE_ZONG_MEN, ROUTE_JIA_ZU, ROUTE_GUO_JIA, ROUTE_SCORE]

## 路线 → 归属流派（空串 = 任何流派可走，即分数兜底路线）。
## 出处：1.0 `entity/VictoryRoute.java` 构造参数 `factionType`。
const ROUTE_FACTION: Dictionary = {
	ROUTE_ZONG_MEN: Enums.FactionType.ZONG_MEN,
	ROUTE_JIA_ZU: Enums.FactionType.JIA_ZU,
	ROUTE_GUO_JIA: Enums.FactionType.GUO_JIA,
	ROUTE_SCORE: "",
}

## 路线显示名（= 结局名 `winType`）与描述。出处：1.0 `entity/VictoryRoute.java`。
const ROUTE_NAMES: Dictionary = {
	ROUTE_ZONG_MEN: "万法归宗",
	ROUTE_JIA_ZU: "举族登仙",
	ROUTE_GUO_JIA: "一统天下",
	ROUTE_SCORE: "修仙共主",
}
const ROUTE_DESCRIPTIONS: Dictionary = {
	ROUTE_ZONG_MEN: "主干道统尽数推演, 宗门鼎盛",
	ROUTE_JIA_ZU: "血脉族人飞升, 满门高修",
	ROUTE_GUO_JIA: "普天之下皆为王土",
	ROUTE_SCORE: "回合终局综合评分问鼎",
}


# ---------------------------------------------------------------------------
# 势力等级（裁决六：**不是声望折算**）
# ---------------------------------------------------------------------------

## 重算并写回 `sect.powerLevel`（1.0 `refreshPowerLevel` → `EconomyCalculator.calculatePowerLevel`）。
##
## 口径：领地数÷`tilesPerLevel`（国家流 ×`territoryPowerWeight`）+ 金丹以上弟子×
## `highRealmDiscipleWeight` + 已解锁道法×`unlockedDaoWeight` + 建筑等级×`buildingLevelWeight`，
## 结果 `max(1, int(power))`（1.0 同）。覆灭宗门直接 0。
static func refresh_power_level(state: GameState, config: Dictionary, sect: Sect) -> void:
	if sect == null:
		return
	if sect.defeated:
		sect.powerLevel = 0
		return
	var power_config: Dictionary = config["powerLevel"]
	var power: float = 0.0
	# 领地规模：国家流有 `territoryPowerWeight`（1.5）加成。
	var territory_weight: float = 1.0
	if sect.factionType == Enums.FactionType.GUO_JIA:
		territory_weight = float(config["faction"]["guoJia"]["territoryPowerWeight"])
	power += float(owned_tiles(state, sect)) * territory_weight \
		/ float(maxi(1, int(power_config["tilesPerLevel"])))
	# 高阶弟子（金丹及以上）。
	power += float(high_realm_members(sect, Disciple.level_of(Enums.Realm.JIN_DAN))) \
		* float(power_config["highRealmDiscipleWeight"])
	# 道统进度。
	power += float(sect.unlockedDaoIds.size()) * float(power_config["unlockedDaoWeight"])
	# 建筑等级：主峰自身等级 + 已建成建筑等级（2.0 的洞府/分峰都是 `peak.buildings` 条目，
	# 故 1.0 的 `allDistrictBuildings()` + `getSubPeaks()` 两轮在 2.0 合并为这一轮）。
	var building_weight: float = float(power_config["buildingLevelWeight"])
	for peak: SpiritPeak in sect.spiritPeaks:
		power += float(peak.level) * building_weight
		for building: Variant in peak.buildings.values():
			power += float(int((building as Dictionary).get("level", 0))) * building_weight
	sect.powerLevel = maxi(1, int(power))


# ---------------------------------------------------------------------------
# 单项指标
# ---------------------------------------------------------------------------

## 主干道统完成度 = 已推演道法 / 本流派可推演道法。
## 别的流派专属道法分母分子都不计（否则家族道法会把宗门的 100% 锁死）；
## 存档里的陌生道法 id 不计入分子（防改树后凭空达标）。
static func dao_completion(config: Dictionary, sect: Sect) -> float:
	var total: int = 0
	var done: int = 0
	for dao: Dao in DaoRules.all_daos(config):
		if not dao.factionOnly.is_empty() and dao.factionOnly != sect.factionType:
			continue
		total += 1
		if sect.unlockedDaoIds.has(dao.id):
			done += 1
	return 0.0 if total <= 0 else float(done) / float(total)


## 已解锁的道法数（只数配置里真实存在的 id）。
static func known_unlocked_dao_count(config: Dictionary, sect: Sect) -> int:
	var count: int = 0
	for dao_id: String in sect.unlockedDaoIds:
		if DaoRules.find_dao(config, dao_id) != null:
			count += 1
	return count


## 核心道法已解锁数（`victory.zongMen.coreDaoIds`）。
static func core_daos_unlocked(sect: Sect, core_ids: Array) -> int:
	var count: int = 0
	for dao_id: Variant in core_ids:
		if sect.unlockedDaoIds.has(str(dao_id)):
			count += 1
	return count


## 境界等级 ≥ `min_level` 的弟子数。
static func high_realm_members(sect: Sect, min_level: int) -> int:
	var count: int = 0
	for disciple: Disciple in sect.disciples:
		if disciple.realmLevel >= min_level:
			count += 1
	return count


## 已飞升人数（家族流 `ascensionCount` 与分数公式的「飞升数」同源）。
static func ascension_count(sect: Sect) -> int:
	var count: int = 0
	for disciple: Disciple in sect.disciples:
		if disciple.ascended:
			count += 1
	return count


## 王土份额 = 己方地块 / 全图已认领地块（无人认领时 0）。
static func claimed_tile_share(state: GameState, sect: Sect) -> float:
	var claimed: int = 0
	var mine: int = 0
	for tile: HexTile in state.tiles.values():
		if tile.ownerSectId.is_empty():
			continue
		claimed += 1
		if tile.ownerSectId == sect.id:
			mine += 1
	return 0.0 if claimed <= 0 else float(mine) / float(claimed)


## 直接按地块归属统计（不依赖任何缓存字段，避免脏数据虚报疆域）。
static func owned_tiles(state: GameState, sect: Sect) -> int:
	var mine: int = 0
	for tile: HexTile in state.tiles.values():
		if tile.ownerSectId == sect.id:
			mine += 1
	return mine


## 存续宗门的灵峰总数（国家流 `requireAllOwnedPeaks` 用）。
static func total_peak_count(state: GameState) -> int:
	var total: int = 0
	for sect: Sect in state.sects:
		if sect.defeated:
			continue
		total += sect.spiritPeaks.size()
	return total


# ---------------------------------------------------------------------------
# 分数（裁决五）
# ---------------------------------------------------------------------------

## `score = powerLevel×w1 + 飞升×w2 + 地块份额×w3 + 道法完成×w4 + 灵峰×w5`，权重全读 config。
static func compute_score(state: GameState, config: Dictionary, sect: Sect) -> int:
	if sect == null or sect.defeated:
		return 0
	var weights: Dictionary = config["victory"]["score"]
	var raw: float = float(sect.powerLevel) * float(weights["powerLevelWeight"]) \
		+ float(ascension_count(sect)) * float(weights["ascensionWeight"]) \
		+ claimed_tile_share(state, sect) * float(weights["claimedTileShareWeight"]) \
		+ dao_completion(config, sect) * float(weights["daoCompletionWeight"]) \
		+ float(sect.spiritPeaks.size()) * float(weights["peakWeight"])
	return int(round(raw))


## 场上最高分（不含自己）；无对手时 0。
static func best_score(state: GameState, config: Dictionary, except_sect_id: String) -> int:
	var best: int = 0
	for sect: Sect in state.sects:
		if sect.defeated or sect.id == except_sect_id:
			continue
		best = maxi(best, compute_score(state, config, sect))
	return best


## 是否并列或领先全场。并列时按「势力等级 → 灵峰数」定唯一胜者（1.0 `isTopScorer` 同序），
## 免得兜底胜利谁都判不赢。
static func is_top_scorer(state: GameState, config: Dictionary, sect: Sect) -> bool:
	var mine: int = compute_score(state, config, sect)
	for other: Sect in state.sects:
		if other.defeated or other.id == sect.id:
			continue
		var theirs: int = compute_score(state, config, other)
		if theirs > mine:
			return false
		if theirs == mine and (other.powerLevel > sect.powerLevel \
				or (other.powerLevel == sect.powerLevel \
				and other.spiritPeaks.size() > sect.spiritPeaks.size())):
			return false
	return true


## 回合上限时的分数胜者（无存续宗门时返回 null）。
static func score_winner(state: GameState, config: Dictionary) -> Sect:
	var best: Sect = null
	for sect: Sect in state.sects:
		if sect.defeated:
			continue
		if best == null or _is_better(state, config, sect, best):
			best = sect
	return best


static func _is_better(state: GameState, config: Dictionary, a: Sect, b: Sect) -> bool:
	var sa: int = compute_score(state, config, a)
	var sb: int = compute_score(state, config, b)
	if sa != sb:
		return sa > sb
	if a.powerLevel != b.powerLevel:
		return a.powerLevel > b.powerLevel
	return a.spiritPeaks.size() > b.spiritPeaks.size()


static func max_turns(config: Dictionary) -> int:
	return int(config["victory"]["maxTurns"])


static func score_victory_enabled(config: Dictionary) -> bool:
	return bool(config["victory"]["scoreVictoryEnabled"])


# ---------------------------------------------------------------------------
# 路线
# ---------------------------------------------------------------------------

## 该流派可走的路线（招牌路线在前、分数兜底路线在后；关掉兜底时不展示）。
static func routes_for(config: Dictionary, faction: String) -> Array[String]:
	var routes: Array[String] = []
	for route: String in ROUTE_ALL:
		var owner: String = str(ROUTE_FACTION[route])
		if not owner.is_empty() and owner != faction:
			continue
		if route == ROUTE_SCORE and not score_victory_enabled(config):
			continue
		routes.append(route)
	return routes


## 单条路线的进度（1.0 `VictoryCalculator.progressOf`）。
static func progress_of(state: GameState, config: Dictionary, sect: Sect, route: String) -> Dictionary:
	var victory: Dictionary = config["victory"]
	var cap: int = max_turns(config)
	var goals: Array = []
	var score_value: Variant = null
	var worst_goal_decides: bool = false
	match route:
		ROUTE_ZONG_MEN:
			var zong_men: Dictionary = victory["zongMen"]
			var core_ids: Array = zong_men.get("coreDaoIds", [])
			goals.append(_goal("主干道统完成度", dao_completion(config, sect),
				float(zong_men["daoCompletionRatio"]), "%", "推演的道法占全树比例"))
			# 核心道法为空视为无门槛（1.0 `coreDaoTarget` 同口径）。
			goals.append(_goal("核心道法", float(core_daos_unlocked(sect, core_ids)),
				float(core_ids.size()), "种", "镇派之法必须齐备"))
			goals.append(_goal("势力等级", float(sect.powerLevel),
				float(zong_men["powerLevel"]), "级", "宗门综合威望"))
			goals.append(_goal("道场灵峰", float(sect.spiritPeaks.size()),
				float(zong_men["minPeaks"]), "座", "开枝散叶的香火道场"))
		ROUTE_JIA_ZU:
			var jia_zu: Dictionary = victory["jiaZu"]
			var high_level: int = int(jia_zu["highRealmLevel"])
			goals.append(_goal("化神飞升", float(ascension_count(sect)),
				float(jia_zu["ascensionCount"]), "人", "渡劫成功举族登仙"))
			goals.append(_goal("血脉族人", float(sect.disciples.size()),
				float(jia_zu["minClanMembers"]), "人", "族人丁旺才撑得起门楣"))
			goals.append(_goal("元婴以上族人", float(high_realm_members(sect, high_level)),
				float(jia_zu["minHighRealmMembers"]), "人",
				"%s以上的顶梁柱" % _realm_name(high_level)))
		ROUTE_GUO_JIA:
			var guo_jia: Dictionary = victory["guoJia"]
			goals.append(_goal("王土份额", claimed_tile_share(state, sect),
				float(guo_jia["claimedTileRatio"]), "%", "已认领地块中属于自己的比例"))
			goals.append(_goal("实际控制地块", float(owned_tiles(state, sect)),
				float(guo_jia["minControlledTiles"]), "格", "疆域绝对规模"))
			if bool(guo_jia.get("requireAllOwnedPeaks", false)):
				goals.append(_goal("天下灵峰尽归", float(sect.spiritPeaks.size()),
					float(maxi(total_peak_count(state), int(guo_jia["minPeaks"]))), "座",
					"存续宗的灵峰全在本宗名下"))
		ROUTE_SCORE:
			var mine: int = compute_score(state, config, sect)
			var best: int = best_score(state, config, sect.id)
			score_value = mine
			worst_goal_decides = true
			goals.append(_goal("评分领先", float(mine), float(best + 1), "分",
				"势力等级/飞升/王土/道统加权, 须高于天下最高对手"))
			goals.append(_goal("回合上限", float(mini(state.turn, cap)), float(cap), "回合",
				"满 %d 回合仍居天下之首者问鼎" % cap))
	var ratio: float = _ratio_of(goals, worst_goal_decides)
	return {
		"route": route,
		"achieved": _achieved_of(goals),
		"ratio": ratio,
		"summary": _summary_of(goals),
		"stage": _stage_of(ratio, _achieved_of(goals)),
		"score": score_value,
		"goals": goals,
	}


## 全部路线进度（`queryVictoryProgress` 的 `routes[]`）。
static func victory_progress(state: GameState, config: Dictionary, sect: Sect) -> Dictionary:
	var routes: Array = []
	if sect != null:
		refresh_power_level(state, config, sect)
		for route: String in routes_for(config, sect.factionType):
			routes.append(progress_of(state, config, sect, route))
	return {"sectId": "" if sect == null else sect.id, "routes": routes}


## 同时达成的路线（招牌在前、分数在后）。分数路线**只在回合上限那一刻**判定
## （1.0 `achievedRoutes` 同口径：平时进度条只显示差距，不算达成）。
static func achieved_routes(state: GameState, config: Dictionary, sect: Sect) -> Array[String]:
	var achieved: Array[String] = []
	if sect == null or sect.defeated:
		return achieved
	for route: String in routes_for(config, sect.factionType):
		if route == ROUTE_SCORE:
			if score_victory_enabled(config) and state.turn >= max_turns(config) \
					and is_top_scorer(state, config, sect):
				achieved.append(route)
			continue
		if _achieved_of(progress_of(state, config, sect, route)["goals"]):
			achieved.append(route)
	return achieved


## 是否达成胜利：返回首个路线 id，未达成返回空串（1.0 `checkVictory` 语义）。
static func check_victory(state: GameState, config: Dictionary, sect: Sect) -> String:
	var achieved: Array[String] = achieved_routes(state, config, sect)
	return "" if achieved.is_empty() else achieved[0]


# ---------------------------------------------------------------------------
# 失败
# ---------------------------------------------------------------------------

## 是否已失败（1.0 `checkDefeat`）：
## 弟子全灭 / 灵峰全失 / 宗门流宗主陨落且无金丹以上继承人。
## **本函数只判定，不做覆灭清算**（清理由 `collapse_sect` 负责，`process_victory_check` 调用）。
static func check_defeat(state: GameState, config: Dictionary, sect: Sect) -> bool:
	if sect == null or sect.defeated:
		return false
	if sect.disciples.is_empty():
		state.eventLog.append("[胜负] %s 门下尽墨, 传承断绝, 该宗覆灭" % sect.name)
		return true
	if sect.spiritPeaks.is_empty():
		state.eventLog.append("[胜负] %s 灵峰尽失, 无立足之地, 该宗覆灭" % sect.name)
		return true
	if sect.factionType == Enums.FactionType.ZONG_MEN:
		if not _has_succession(sect):
			state.eventLog.append("[胜负] %s 宗主陨落且无金丹以上继承人, 该宗覆灭" % sect.name)
			return true
	return false


## 宗门流的「继承链」是否成立：有宗主 **或** 有金丹以上继承人。
## 纯查询、不写日志；`check_defeat` 与 `would_collapse_if_lost` 共用同一口径，避免两处漂移。
## `except_id` 非空时跳过该弟子（用于「假设此人阵亡」的反事实推演）。
static func _has_succession(sect: Sect, except_id: String = "") -> bool:
	var heir_level: int = Disciple.level_of(Enums.Realm.JIN_DAN)
	for disciple: Disciple in sect.disciples:
		if not except_id.is_empty() and disciple.id == except_id:
			continue
		if disciple.position == Enums.Position.ZONG_ZHU:
			return true
		if disciple.realmLevel >= heir_level:
			return true
	return false


## **纯查询**：假设 `disciple_id` 阵亡，该宗是否会立刻覆灭。不写事件日志、不掷骰。
##
## 用途：`AIController` 用它避免「以本宗当场覆灭为代价发起进攻」。AI 原先只看 `can_fight`
## 与战力比，把宗主当普通战力派出去，于是宗门流在平衡抽样里 48/48 席全部在第 74 回合前后
## 因「宗主陨落且无金丹继承人」自灭——这不是运气差，是决策层缺了一条保命约束。
##
## 口径与 `check_defeat` 一致，只少一条与「失去该弟子」无关的分支：**灵峰尽失**不是弟子造成的，
## 不计入；而「弟子全灭」按剩余 0 人计入。
static func would_collapse_if_lost(sect: Sect, disciple_id: String) -> bool:
	if sect == null or sect.defeated:
		return false
	var remaining: int = 0
	for disciple: Disciple in sect.disciples:
		if disciple.id == disciple_id:
			continue
		remaining += 1
	if remaining <= 0:
		return true
	if sect.factionType != Enums.FactionType.ZONG_MEN:
		return false
	return not _has_succession(sect, disciple_id)


## 覆灭清算（1.0 `collapseSect`）：解除地块/节点归属、清空弟子与灵峰与研究队列。
## **保留 `sect` 实体本身**（`defeated=true`），因为 `view.sects[]` 与历史事件还要读它。
static func collapse_sect(state: GameState, sect: Sect) -> void:
	sect.defeated = true
	sect.powerLevel = 0
	for tile: HexTile in state.tiles.values():
		if tile.ownerSectId == sect.id:
			tile.ownerSectId = ""
	var doomed: Array[String] = []
	for disciple: Disciple in sect.disciples:
		doomed.append(disciple.id)
	for node: GameNode in state.nodes.values():
		if node.ownerSectId == sect.id:
			node.ownerSectId = ""
		var kept: Array[String] = []
		for garrison_id: String in node.garrisonDiscipleIds:
			if not doomed.has(garrison_id):
				kept.append(garrison_id)
		node.garrisonDiscipleIds = kept
	sect.spiritPeaks.clear()
	sect.disciples.clear()
	sect.researchQueue.clear()
	sect.defeated = true
	state.eventLog.append("[胜负] %s 势力消散, 疆土尽归无主" % sect.name)


# ---------------------------------------------------------------------------
# 终局流程（`VICTORY_CHECK` 唯一入口）
# ---------------------------------------------------------------------------

## 判定顺序（1.0 `processVictoryCheck` + R7 裁决九）：
## 1. 逐宗（宗门序）判胜负：有达成路线 → `settle_victory` 并返回；
## 2. 未达成则判失败：覆灭清算，玩家宗门覆灭即 `gameOver` 并返回；
## 3. 全部走完后：`turn % 10 == 0` 自动存档槽 0（裁决九，R2 留的 TODO）。
##
## 240 回合强制分数结算不另设分支——`achieved_routes` 里分数路线在 `turn >= maxTurns`
## 且领先时自动达成，故第 1 步即完成强制结算（裁决五）。
static func process_victory_check(state: GameState, config: Dictionary) -> void:
	if state.gameOver:
		return
	for sect: Sect in state.sects:
		if sect.defeated:
			continue
		refresh_power_level(state, config, sect)
		var achieved: Array[String] = achieved_routes(state, config, sect)
		if not achieved.is_empty():
			settle_victory(state, config, sect, achieved)
			return
		if check_defeat(state, config, sect):
			collapse_sect(state, sect)
			if sect.id == state.playerSectId:
				state.gameOver = true
				return
	# 裁决九：每 10 回合自动存档槽 0（`lastAutoSaveTurn` 防同回合重复落盘）。
	if state.turn % 10 == 0 and state.turn != 0:
		if SaveManager.auto_save(state, config):
			for sect: Sect in state.sects:
				if sect.player:
					sect.lastAutoSaveTurn = state.turn


## 终局结算（1.0 `settleVictory`）：AI 直接取招牌路线；玩家同时达成多条则只定胜者，
## 结局名留空等 `chooseVictory`（读档后仍会重新问一次）。
static func settle_victory(state: GameState, config: Dictionary, sect: Sect, routes: Array[String]) -> void:
	state.gameOver = true
	state.winnerSectId = sect.id
	state.pendingVictoryChoices.clear()
	if routes.size() == 1 or not sect.player:
		state.winType = str(ROUTE_NAMES.get(routes[0], routes[0]))
		state.eventLog.append("[胜负] %s 达成胜利: %s (%s)" % [
			sect.name, state.winType, str(ROUTE_DESCRIPTIONS.get(routes[0], "")),
		])
		return
	state.winType = ""
	for route: String in routes:
		state.pendingVictoryChoices.append(route)
	state.eventLog.append("[胜负] %s 同时达成 %d 条胜利路线, 请择一而终" % [sect.name, routes.size()])


## 玩家择定结局（1.0 `GameEngine.chooseVictory`）：只认 `pendingVictoryChoices` 里的路线。
## 成功返回 `winType`，失败返回空串（调用方据此判 `success=false`）。
static func choose_victory(state: GameState, route_id: String) -> String:
	if route_id.is_empty() or state.pendingVictoryChoices.is_empty():
		return ""
	if not state.pendingVictoryChoices.has(route_id):
		return ""
	state.pendingVictoryChoices.clear()
	state.winType = str(ROUTE_NAMES.get(route_id, route_id))
	var winner: Sect = null
	for sect: Sect in state.sects:
		if sect.id == state.winnerSectId:
			winner = sect
			break
	state.eventLog.append("[胜负] %s 择定结局: %s (%s)" % [
		"胜者" if winner == null else winner.name,
		state.winType, str(ROUTE_DESCRIPTIONS.get(route_id, "")),
	])
	return state.winType


# ---------------------------------------------------------------------------
# goal 构造与派生（1.0 `VictoryGoal`）
# ---------------------------------------------------------------------------

## `{name, current, target, unit, description}` + 派生 `{ratio, met, missingText, valueText}`。
static func _goal(name: String, current: float, target: float, unit: String, description: String) -> Dictionary:
	var ratio: float = 1.0 if target <= 0.0 else clampf(current / target, 0.0, 1.0)
	var met: bool = target <= 0.0 or current >= target
	return {
		"name": name,
		"current": current,
		"target": target,
		"unit": unit,
		"description": description,
		"ratio": ratio,
		"met": met,
		"missingText": "" if met else _missing_text(name, current, target, unit),
		"valueText": _value_text(current, target, unit),
	}


## 1.0 `missingText`：比例目标报百分比差，计数目标报整数差。
static func _missing_text(name: String, current: float, target: float, unit: String) -> String:
	var gap: float = target - current
	var gap_text: String = "%.0f" % (gap * 100.0) if unit == "%" else str(int(ceil(gap)))
	return "还差 %s%s (%s)" % [gap_text, unit, name]


## 1.0 `valueText`：比例目标 `x%→y%`，计数目标 `x/y单位`。
static func _value_text(current: float, target: float, unit: String) -> String:
	if unit == "%":
		return "%.0f%%→%.0f%%" % [current * 100.0, target * 100.0]
	return "%s/%s%s" % [_trim(current), _trim(target), unit]


static func _trim(value: float) -> String:
	if absf(value - round(value)) < 1e-9:
		return str(int(round(value)))
	return "%.1f" % value


static func _ratio_of(goals: Array, worst_decides: bool) -> float:
	if goals.is_empty():
		return 0.0
	if worst_decides:
		var lowest: float = 1.0
		for goal: Variant in goals:
			lowest = minf(lowest, float((goal as Dictionary)["ratio"]))
		return lowest
	var total: float = 0.0
	for goal: Variant in goals:
		total += float((goal as Dictionary)["ratio"])
	return total / float(goals.size())


static func _achieved_of(goals: Array) -> bool:
	if goals.is_empty():
		return false
	for goal: Variant in goals:
		if not bool((goal as Dictionary)["met"]):
			return false
	return true


## 1.0 `getSummary`：已达成给「已达成」，否则报最拖后腿那一项的 `missingText`。
static func _summary_of(goals: Array) -> String:
	if _achieved_of(goals):
		return "已达成"
	var worst: Dictionary = {}
	for goal: Variant in goals:
		var entry: Dictionary = goal as Dictionary
		if bool(entry["met"]):
			continue
		if worst.is_empty() or float(entry["ratio"]) < float(worst["ratio"]):
			worst = entry
	if worst.is_empty():
		return "目标未齐"
	var text: String = str(worst["missingText"])
	return "目标未齐" if text.is_empty() else text


## 1.0 `getStage`：功成 / 临门一脚 / 大势已成 / 渐入佳境 / 初具规模 / 白手起家。
static func _stage_of(ratio: float, achieved: bool) -> String:
	if achieved:
		return "功成"
	if ratio >= 0.85:
		return "临门一脚"
	if ratio >= 0.6:
		return "大势已成"
	if ratio >= 0.3:
		return "渐入佳境"
	if ratio > 0.0:
		return "初具规模"
	return "白手起家"


static func _realm_name(level: int) -> String:
	var index: int = clampi(level - 1, 0, Enums.Realm.ALL.size() - 1)
	return str(Enums.Realm.NAMES.get(Enums.Realm.ALL[index], Enums.Realm.ALL[index]))
