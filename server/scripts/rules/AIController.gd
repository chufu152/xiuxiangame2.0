class_name AIController
extends RefCounted
## 反应式基础 AI（对齐 1.0 `core/AIController`，按 R7 裁决一裁剪）。
##
## **删除**（裁决一）：性格系统（好战/图治/纵横）、长期战略复盘、外交议程、`StrategyService`。
## **不检查宣战**（PRD §5.2 #1）：攻击只看战力与目标价值，不需要战争状态。
##
## 行为只由 `ai.*` 与 `difficulty.levels.*` 驱动，每回合按 `aiActionPoints`（难度覆盖）逐点决策：
## 攻击 → 扩张 → 探索 → 研究 → 驻守 → 收徒 → 血脉 → 修路；行动点用完后另有**每回合至多一次**
## 的渡劫飞升（不占行动点，见 `_try_tribulate`）。
## 顺序固定（先打后建），每类动作由对应倾向值掷骰决定「本回合要不要尝试」，
## 三流派靠 `ai.*` 倾向值与 `faction.*` 特性自然分化（宗门偏研究、家族偏血脉、国家偏扩张）。
##
## **所有随机只经 `GameState.rng`**（硬约束 6）：倾向掷骰与渡劫/血脉共用同一条序列，
## 故「同种子 + 同指令序列」下 AI 行为逐字一致（验收 9）。
##
## 遍历顺序一律按 id 升序，不依赖 Dictionary 迭代顺序（Godot 的 Dictionary 保序但显式排序更稳）。

## 单个 AI 回合内各类动作的最大尝试次数上限（防止「一直失败一直重试」把点数耗在同一类上）。
const MAX_ATTEMPTS_PER_ACTION: int = 2


# ---------------------------------------------------------------------------
# 入口
# ---------------------------------------------------------------------------

## 跑一个 AI 宗门的回合。返回本回合事件文本数组（调用方追加进 `state.eventLog`）。
static func run_turn(state: GameState, config: Dictionary, sect: Sect) -> Array[String]:
	var events: Array[String] = []
	if sect == null or sect.defeated or sect.player:
		return events
	var points: int = action_points(config, state.difficulty)
	for _index: int in range(points):
		var text: String = _next_action(state, config, sect)
		if text.is_empty():
			break
		events.append(text)
		state.eventLog.append(text)
	# R10 修复：渡劫飞升。**不放进 `_next_action` 的优先级链**，每回合至多一次（见 `_try_tribulate`）。
	var tribulation: String = _try_tribulate(state, config, sect)
	if not tribulation.is_empty():
		events.append(tribulation)
		state.eventLog.append(tribulation)
	return events


## 行动点数：`difficulty.levels.<difficulty>.aiActionPoints`，缺失时回退 `ai.actionPoints`。
static func action_points(config: Dictionary, difficulty: String) -> int:
	var levels: Dictionary = config["difficulty"]["levels"]
	if levels.has(difficulty):
		var level: Dictionary = levels[difficulty]
		if level.has("aiActionPoints"):
			return int(level["aiActionPoints"])
	return int(config["ai"]["actionPoints"])


## 按优先级依次尝试，第一个成功的动作返回事件文本。
static func _next_action(state: GameState, config: Dictionary, sect: Sect) -> String:
	var order: Array[Callable] = [
		_try_attack, _try_expand, _try_explore, _try_research,
		_try_garrison, _try_recruit, _try_bloodline, _try_improve,
	]
	for attempt: Callable in order:
		var text: String = str(attempt.call(state, config, sect))
		if not text.is_empty():
			return text
	return ""


# ---------------------------------------------------------------------------
# 战斗
# ---------------------------------------------------------------------------

## 攻击：`winChance ≥ attackMinWinChance`（0.55）**且**战力优势 ≥ `combatAdvantageThreshold`（1.2）
## 才发起（裁决一）。优势比按 `attackerPower / defenderPower` 算，与 `preview()` 同源。
static func _try_attack(state: GameState, config: Dictionary, sect: Sect) -> String:
	var ai: Dictionary = config["ai"]
	var aggression: float = float(ai["aggression"]) * _difficulty_multiplier(config, state.difficulty, "aiAggressionMultiplier")
	if not state.rng.chance(clampf(aggression, 0.0, 1.0)):
		return ""
	var threshold: float = float(ai["combatAdvantageThreshold"])
	var min_chance: float = float(ai["attackMinWinChance"])
	# **性能：敌方格集合每次进攻只算一次**（见 `_enemy_tiles` 的注释）。
	var enemy_tiles: Array[String] = _enemy_tiles(state, sect)
	if enemy_tiles.is_empty():
		return ""
	for disciple: Disciple in _sorted_disciples(sect):
		if not UnitRules.can_fight(disciple) or disciple.attacksRemaining <= 0:
			continue
		# **R10 修复：不得以「本宗当场覆灭」为代价发起进攻。**
		# 宗门流「宗主陨落且无金丹以上继承人」即覆灭（`VictoryRules.check_defeat` 第三分支），
		# 而 AI 原先把宗主当普通战力派出去——只看 `can_fight` 与战力比，不看职位。
		# 平衡抽样里宗门流因此 48/48 席全部在第 74 回合前后自灭，胜率 0%。
		# 判据直接取自失败规则本身（反事实推演「此人没了会不会覆灭」），不引入新的调参项。
		if VictoryRules.would_collapse_if_lost(sect, disciple.id):
			continue
		var origin: HexTile = state.tiles.get(disciple.tileId, null)
		if origin == null:
			continue
		var reach: int = UnitRules.range_of(config, disciple)
		var best_tile: String = ""
		var best_chance: float = -1.0
		for tile_id: String in enemy_tiles:
			var tile: HexTile = state.tiles.get(tile_id, null)
			if tile == null:
				continue
			var distance: int = Hex.distance(Vector2i(origin.q, origin.r), Vector2i(tile.q, tile.r))
			if distance < 1 or distance > reach:
				continue
			var preview: Dictionary = CombatResolver.preview(state, config, disciple.id, tile_id)
			if not bool(preview["attackable"]):
				continue
			var chance: float = float(preview["winChance"])
			if chance < min_chance:
				continue
			var defender_power: int = maxi(1, int(preview["defenderPower"]))
			if float(int(preview["attackerPower"])) / float(defender_power) < threshold:
				continue
			if chance > best_chance:
				best_chance = chance
				best_tile = tile_id
		if best_tile.is_empty():
			continue
		var result: Dictionary = CombatResolver.resolve_attack(state, config, disciple.id, best_tile)
		if bool(result.get("success", false)):
			return "[AI] %s 进攻 %s (胜率%.2f)" % [sect.name, best_tile, best_chance]
	return ""


## 该宗视角下「有敌方内容」的全部格子（敌方地块 / 敌方节点 / 敌方灵峰），按 id 升序。
##
## **必须每回合只算一次，不能放进弟子循环。** 原实现是「每名弟子 × 每个行动点」各扫一遍全图，
## 而 `_has_enemy_content` 内部还要遍历**全部宗门的全部灵峰**，于是复杂度是
## `O(弟子 × 地块 × 宗门 × 峰)`。突破判定修好之后 AI 真的会开峰（1 座 → 最多 11 座），
## 这个四层嵌套立刻爆炸：平衡抽样单局从 5 秒涨到 109 秒，瓶颈全在这里。
## 抽成一次预计算后是 `O(地块 × 宗门 × 峰) + O(弟子 × 敌方格)`。
## **语义与排序完全不变**（仍是「先廉价过滤归属、再算距离、再 preview」，且返回有序数组，
## 故 `chance > best_chance` 的平手取先规则也不变）。
static func _enemy_tiles(state: GameState, sect: Sect) -> Array[String]:
	var tiles: Array[String] = []
	for tile: HexTile in state.tiles.values():
		if _has_enemy_content(state, sect.id, tile):
			tiles.append(tile.id)
	tiles.sort()
	return tiles


static func _has_enemy_content(state: GameState, my_sect_id: String, tile: HexTile) -> bool:
	if not tile.ownerSectId.is_empty() and tile.ownerSectId != my_sect_id:
		return true
	if state.nodes.has(tile.nodeId):
		var node: GameNode = state.nodes[tile.nodeId]
		if not node.ownerSectId.is_empty() and node.ownerSectId != my_sect_id:
			return true
	for sect: Sect in state.sects:
		if sect.defeated or sect.id == my_sect_id:
			continue
		for peak: SpiritPeak in sect.spiritPeaks:
			if peak.tileId == tile.id:
				return true
	return false


# ---------------------------------------------------------------------------
# 扩张
# ---------------------------------------------------------------------------

## 扩张：派闲置的金丹以上弟子去无主地块开辟新峰。地块评分读 `expansion*` 五项权重
## （节点 +`expansionNodeBonus` / 邻接资源 +`expansionAdjacentResourceBonus` /
## 接壤己方 +`expansionOwnBorderBonus` / 接壤敌方 −`expansionEnemyBorderPenalty` /
## 危险 −`expansionDangerPenalty`）。
static func _try_expand(state: GameState, config: Dictionary, sect: Sect) -> String:
	var ai: Dictionary = config["ai"]
	var tendency: float = float(ai["expansionTendency"]) * _difficulty_multiplier(config, state.difficulty, "aiExpansionMultiplier")
	if not state.rng.chance(clampf(tendency, 0.0, 1.0)):
		return ""
	for disciple: Disciple in _sorted_disciples(sect):
		if disciple.realmLevel < Disciple.level_of(Enums.Realm.JIN_DAN):
			continue
		if not UnitRules.can_fight(disciple) or not disciple.garrisonNodeId.is_empty():
			continue
		if not disciple.missionNodeId.is_empty() or disciple.injured:
			continue
		var target: String = choose_expansion_tile(state, config, sect, disciple)
		if target.is_empty():
			continue
		var result: Dictionary = CityAction.found_spirit_peak(state, config, disciple.id, target)
		if bool(result.get("success", false)):
			return "[AI] %s 于 %s 开辟灵峰" % [sect.name, target]
	return ""


## 选扩张地块（`ai.expansion*` 五项权重打分，取最高分；同分按 id 升序取先）。
## 只在**当前可移动到达**的无主非山岳地块里选，避免「选了走不到」。
static func choose_expansion_tile(state: GameState, config: Dictionary, sect: Sect, disciple: Disciple) -> String:
	var ai: Dictionary = config["ai"]
	var reach: Dictionary = MoveRangeCalculator.reachable(state, config, disciple)
	var best_tile: String = ""
	var best_score: int = -999999
	var capital: SpiritPeak = AppointmentRules.capital_peak_of(sect)
	var capital_tile: HexTile = null if capital == null else state.tiles.get(capital.tileId, null)
	var candidates: Array[String] = []
	for tile_id: Variant in (reach["costs"] as Dictionary).keys():
		candidates.append(str(tile_id))
	candidates.sort()
	for tile_id: String in candidates:
		if tile_id == disciple.tileId:
			continue
		var tile: HexTile = state.tiles.get(tile_id, null)
		if tile == null:
			continue
		# 地形/归属层面的可开峰过滤（「弟子须身处目标格」由下方先移动再开峰满足）。
		if not _is_foundable_terrain(state, config, sect, tile):
			continue
		var score: int = _expansion_score(state, config, sect, tile, capital_tile, ai)
		if score > best_score:
			best_score = score
			best_tile = tile_id
	if best_tile.is_empty():
		return ""
	# 先走过去再开峰（`can_found_peak` 要求弟子身处目标格）。
	if best_tile != disciple.tileId:
		var move: Dictionary = MoveAction.move_disciple(state, config, disciple.id, best_tile)
		if not bool(move.get("success", false)):
			return ""
	return best_tile


## 地形/归属层面的可开峰判定（不含「弟子须身处」这一条，那条由移动满足）。
static func _is_foundable_terrain(state: GameState, config: Dictionary, sect: Sect, tile: HexTile) -> bool:
	if not tile.ownerSectId.is_empty():
		return false
	if tile.relief == Enums.Relief.MOUNTAIN:
		return false
	if not MoveRules.is_passable(tile, config):
		return false
	for peak: SpiritPeak in sect.spiritPeaks:
		for project: Project in peak.projectQueue:
			if project.type == Project.TYPE_FOUND_PEAK and project.targetId == tile.id:
				return false
	return true


static func _expansion_score(state: GameState, config: Dictionary, sect: Sect, tile: HexTile,
		capital_tile: HexTile, ai: Dictionary) -> int:
	var score: int = 0
	if not tile.nodeId.is_empty():
		score += int(ai["expansionNodeBonus"])
	for neighbor_coords: Vector2i in Hex.neighbors(Vector2i(tile.q, tile.r)):
		var neighbor: HexTile = state.tiles.get(Hex.id(neighbor_coords.x, neighbor_coords.y), null)
		if neighbor == null:
			continue
		if _is_resource_node(state, neighbor) and (neighbor.ownerSectId.is_empty() or neighbor.ownerSectId == sect.id):
			score += int(ai["expansionAdjacentResourceBonus"])
		if neighbor.ownerSectId == sect.id:
			score += int(ai["expansionOwnBorderBonus"])
		elif not neighbor.ownerSectId.is_empty() and _is_active_sect(state, neighbor.ownerSectId):
			score -= int(ai["expansionEnemyBorderPenalty"])
	if tile.danger:
		score -= int(ai["expansionDangerPenalty"])
	# 离首都越远越难治理。
	if capital_tile != null:
		score -= Hex.distance(Vector2i(tile.q, tile.r), Vector2i(capital_tile.q, capital_tile.r))
	return score


static func _is_resource_node(state: GameState, tile: HexTile) -> bool:
	if tile.nodeId.is_empty() or not state.nodes.has(tile.nodeId):
		return false
	var type: String = (state.nodes[tile.nodeId] as GameNode).type
	return type == Enums.NodeType.LING_MAI or type == Enums.NodeType.LING_QUAN \
		or type == Enums.NodeType.LING_TIAN


static func _is_active_sect(state: GameState, sect_id: String) -> bool:
	for sect: Sect in state.sects:
		if sect.id == sect_id:
			return not sect.defeated
	return false


# ---------------------------------------------------------------------------
# 探索
# ---------------------------------------------------------------------------

## 探索：把闲着的弟子送去机缘（`exploreTendency` 掷骰）。
##
## **R10 修复：候选集原先是「自家节点」，于是机缘探索恒为 0 次。**
## `ExploreRules.send_to_ji_yuan` 的规则本身**不校验节点归属**（机缘是公共野点，谁都能去），
## 而节点归属只能靠「在该地块开灵峰」或气运吞并取得——20×14 地图上机缘节点只有个位数，
## AI 一座都占不到，`_sorted_node_ids` 就恒为空 → 从不探索 → 天晶恒为初始 2 →
## 渡劫要 3 天晶 → **化神/飞升永远 0**（家族流「举族登仙」因此 0/4）。
## 现改为遍历全图机缘节点（归属无关），与规则口径一致。
##
## **只挑「最近的一对」再调规则**：`send_to_ji_yuan` 内部会走一次全图 BFS（`MoveAction.move_disciple`），
## 若对「节点 × 弟子」逐对调用，单回合就是几十次 BFS——实测把整局从 67 秒拖到 300 秒。
## 距离是纯算术，先用它选出一对最优组合，**每次尝试只跑一次 BFS**。
static func _try_explore(state: GameState, config: Dictionary, sect: Sect) -> String:
	if not state.rng.chance(clampf(float(config["ai"]["exploreTendency"]), 0.0, 1.0)):
		return ""
	var best_node: String = ""
	var best_disciple: Disciple = null
	var best_distance: int = 1 << 30
	var candidates: Array[Disciple] = _sorted_disciples(sect)
	for node_id: String in _explorable_node_ids(state):
		var node: GameNode = state.nodes[node_id]
		if node.cooldown > 0:
			continue
		var target: HexTile = state.tiles.get(node.tileId, null)
		if target == null:
			continue
		var cell: Vector2i = Vector2i(target.q, target.r)
		for disciple: Disciple in candidates:
			if disciple.injured or not disciple.garrisonNodeId.is_empty() or not disciple.missionNodeId.is_empty():
				continue
			var origin: HexTile = state.tiles.get(disciple.tileId, null)
			if origin == null:
				continue
			var distance: int = Hex.distance(Vector2i(origin.q, origin.r), cell)
			# **廉价上界剪枝**：BFS 步数 ≥ 六边形直线距离，故「直线距离 > 移动力」的组合一定到不了。
			if distance > disciple.movePoints:
				continue
			# 平手取先（节点按 id 升序、弟子按 id 升序），保证同种子逐字一致。
			if distance < best_distance:
				best_distance = distance
				best_node = node_id
				best_disciple = disciple
	if best_disciple == null:
		return ""
	var picked: GameNode = state.nodes[best_node]
	var result: Dictionary = ExploreRules.send_to_ji_yuan(state, config, best_disciple.id, best_node)
	if bool(result.get("success", false)):
		return "[AI] %s 派 %s 探索机缘 %s" % [sect.name, best_disciple.name, picked.name]
	return ""


## 全图机缘节点（按 id 升序）：**不看归属**，与 `ExploreRules.send_to_ji_yuan` 同口径。
static func _explorable_node_ids(state: GameState) -> Array[String]:
	var ids: Array[String] = []
	for node: GameNode in state.nodes.values():
		if node.type == Enums.NodeType.JI_YUAN:
			ids.append(node.id)
	ids.sort()
	return ids


## 本宗**自有**节点（按 id 升序）：驻守等「只能在自己地盘做」的动作才用它。
static func _sorted_node_ids(state: GameState, sect: Sect) -> Array[String]:
	var ids: Array[String] = []
	for node: GameNode in state.nodes.values():
		if node.ownerSectId == sect.id:
			ids.append(node.id)
	ids.sort()
	return ids


# ---------------------------------------------------------------------------
# 研究
# ---------------------------------------------------------------------------

## 研究：按 `daoTree.daos` 顺序找第一个可研究的道法入队（`researchTendency` 掷骰）。
static func _try_research(state: GameState, config: Dictionary, sect: Sect) -> String:
	if not state.rng.chance(clampf(float(config["ai"]["researchTendency"]), 0.0, 1.0)):
		return ""
	for dao: Dao in DaoRules.all_daos(config):
		if not DaoRules.can_research(state, config, sect, dao.id)["allowed"]:
			continue
		var result: Dictionary = DaoAction.research_dao(state, config, sect.id, dao.id)
		if bool(result.get("success", false)):
			return "[AI] %s 开始推演 %s" % [sect.name, dao.name]
	return ""


# ---------------------------------------------------------------------------
# 驻守
# ---------------------------------------------------------------------------

## 驻守：弟子已在己方节点格且该节点驻守数 < `maxGarrisonPerNode`、
## 且本宗弟子数 ≥ `minDisciplesForGarrison` 才派人（避免把家底全钉在点上）。
static func _try_garrison(state: GameState, config: Dictionary, sect: Sect) -> String:
	var ai: Dictionary = config["ai"]
	if sect.disciples.size() < int(ai["minDisciplesForGarrison"]):
		return ""
	var cap: int = int(ai["maxGarrisonPerNode"])
	for disciple: Disciple in _sorted_disciples(sect):
		if not disciple.garrisonNodeId.is_empty() or disciple.injured:
			continue
		if not disciple.missionNodeId.is_empty():
			continue
		for node_id: String in _sorted_node_ids(state, sect):
			var node: GameNode = state.nodes[node_id]
			if node.tileId != disciple.tileId:
				continue
			if node.garrisonDiscipleIds.size() >= cap:
				continue
			var result: Dictionary = UnitAction.assign_garrison(state, config, disciple.id, node_id)
			if bool(result.get("success", false)):
				return "[AI] %s 派 %s 驻守 %s" % [sect.name, disciple.name, node.name]
	return ""


# ---------------------------------------------------------------------------
# 收徒
# ---------------------------------------------------------------------------

## 收徒：首都峰办收徒大典（`trainUnitChance` 掷骰；受 `recruitPerPeak` 与经济门控约束）。
static func _try_recruit(state: GameState, config: Dictionary, sect: Sect) -> String:
	if not state.rng.chance(clampf(float(config["ai"]["trainUnitChance"]), 0.0, 1.0)):
		return ""
	var capital: SpiritPeak = AppointmentRules.capital_peak_of(sect)
	if capital == null:
		return ""
	var result: Dictionary = DaoAction.hold_recruitment(state, config, capital.id)
	if bool(result.get("success", false)):
		return "[AI] %s 于%s举办收徒大典" % [sect.name, capital.name]
	return ""


# ---------------------------------------------------------------------------
# 血脉（仅家族流）
# ---------------------------------------------------------------------------

## 血脉：家族流优先繁衍（`bloodlineTendency` 掷骰）；族人不足 `clanMemberTarget` 时先联姻。
static func _try_bloodline(state: GameState, config: Dictionary, sect: Sect) -> String:
	if sect.factionType != Enums.FactionType.JIA_ZU:
		return ""
	if not state.rng.chance(clampf(float(config["ai"]["bloodlineTendency"]), 0.0, 1.0)):
		return ""
	var target: int = int(config["ai"]["clanMemberTarget"])
	var capital: SpiritPeak = AppointmentRules.capital_peak_of(sect)
	if capital == null:
		return ""
	# 已有道侣 → 繁衍。
	var disciples: Array[Disciple] = _sorted_disciples(sect)
	for father: Disciple in disciples:
		if father.spouseId.is_empty():
			continue
		var mother: Disciple = CityAction.find_disciple(state, father.spouseId)
		if mother == null or mother.sectId != sect.id:
			continue
		var result: Dictionary = BloodlineRules.reproduce(state, config, capital.id, father.id, mother.id)
		if bool(result.get("success", false)):
			return "[AI] %s %s 降生" % [sect.name, str(result.get("message", ""))]
	# 族人不足目标 → 联姻（找一对无配偶的非近亲）。
	if sect.disciples.size() < target:
		for index: int in range(disciples.size()):
			for other_index: int in range(index + 1, disciples.size()):
				var a: Disciple = disciples[index]
				var b: Disciple = disciples[other_index]
				if not a.spouseId.is_empty() or not b.spouseId.is_empty():
					continue
				var result: Dictionary = BloodlineRules.marry(state, config, a.id, b.id)
				if bool(result.get("success", false)):
					return "[AI] %s %s" % [sect.name, str(result.get("message", ""))]
	return ""


# ---------------------------------------------------------------------------
# 修路
# ---------------------------------------------------------------------------

## 修路：有建造者差事的弟子在其所在格铺青石道路（1.0 AI 的「经济」项）。
static func _try_improve(state: GameState, config: Dictionary, sect: Sect) -> String:
	for disciple: Disciple in _sorted_disciples(sect):
		if disciple.builderCharges <= 0:
			continue
		if disciple.injured or not disciple.garrisonNodeId.is_empty():
			continue
		var result: Dictionary = ImprovementAction.build_improvement(
			state, config, sect.id, disciple.id, disciple.tileId, AutomationRules.ROAD_TYPE)
		if bool(result.get("success", false)):
			return "[AI] %s 于 %s 修筑道路" % [sect.name, disciple.tileId]
	return ""


# ---------------------------------------------------------------------------
# 渡劫
# ---------------------------------------------------------------------------

## 渡劫飞升：元婴且修为已满的弟子尝试晋化神（走命令层 `AppointmentAction.tribulate`，
## 以便与玩家点命令完全同一条路径：成功补 `ascended=true`、失败身死道消时走血脉死亡处理）。
##
## **R10 修复：AI 原先完全不会渡劫。** `DiscipleRules.tribulate` 与命令层
## `AppointmentAction.tribulate` 在 R4/R7 都已实现，但只有玩家点命令能触发，AI 没有任何入口。
## 平衡抽样里所有宗门的最强弟子**永远停在元婴**（`topRealmLevel` 恒为 4），于是：
## 家族流「举族登仙」的 `ascensionCount` 永远 0/4，路线一次都走不通；
## 分数公式里的 `ascensionWeight = 12` 也永远拿不到分。
##
## **每回合至多一次、且不占行动点**：渡劫要花 500 灵力 + 300 灵石 + 材料，
## 若塞进 `_next_action` 的优先级链，一个回合的 5 点行动力会把它连点 5 次、直接抽干家底。
## 失败也返回事件文本（消耗本回合这唯一一次机会），避免「失败即原地重试」烧光资源。
##
## **不在本函数另设资源门槛**：付不付得起由规则函数判定（`DiscipleRules.tribulate` 在掷骰之前
## 就按灵力/灵石/材料逐项拒绝，既不掉资源也不消耗随机数）。这里只区分两种拒绝——
## 「付不起/不合法」不算尝试（换下一个弟子继续找，不写日志），
## 只有真的掷过骰的 `渡劫失败` 才返回事件文本。
static func _try_tribulate(state: GameState, config: Dictionary, sect: Sect) -> String:
	for disciple: Disciple in _sorted_disciples(sect):
		if disciple.realm != Enums.Realm.YUAN_YING or not disciple.breakthroughPending:
			continue
		if disciple.injured:
			continue
		var result: Dictionary = AppointmentAction.tribulate(state, config, disciple.id)
		if bool(result.get("success", false)):
			return "[AI] %s %s 渡劫飞升" % [sect.name, disciple.name]
		# 规则只在**真的掷过骰**之后才给 `reason = "渡劫失败"`；其余 reason（灵力/灵石/材料不足、
		# 仅元婴可渡劫…）都是「没尝试」的拒绝，此时资源未扣、随机数未动，不该记成一次失败。
		if str(result.get("reason", "")) != "渡劫失败":
			continue
		return "[AI] %s %s 渡劫失败" % [sect.name, disciple.name]
	return ""


# ---------------------------------------------------------------------------
# 辅助
# ---------------------------------------------------------------------------

## 按 id 升序的弟子列表（不依赖 `Array` 原序，保证同种子逐字一致）。
static func _sorted_disciples(sect: Sect) -> Array[Disciple]:
	var sorted: Array[Disciple] = sect.disciples.duplicate()
	sorted.sort_custom(func(a: Disciple, b: Disciple) -> bool: return a.id < b.id)
	return sorted


static func _difficulty_multiplier(config: Dictionary, difficulty: String, key: String) -> float:
	var levels: Dictionary = config["difficulty"]["levels"]
	if not levels.has(difficulty):
		return 1.0
	return float((levels[difficulty] as Dictionary).get(key, 1.0))
