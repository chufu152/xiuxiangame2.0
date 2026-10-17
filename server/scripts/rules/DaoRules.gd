class_name DaoRules
extends RefCounted
## 道统规则（R4）：21 条道法树、研究门控、效果汇总、道点产出、成就 boost。
##
## 数值唯一权威 `data/gameConfig.json` 的 `daoTree` / `faction` / `appointment` / `economy`；
## 全部静态、无状态、只读 config。1.0 蓝本：`DaoEffects` + `BuildAction.researchDao`。
##
## **效果汇总唯一出口是 `effect_sum()`**（R4 提示词裁决三）：经济/移动/视野/战力/研究/修炼
## 一律经此取加成，禁止各模块自行遍历 `unlockedDaoIds`。
##
## **本类不做**：政令（R6）、战斗结算（R5）、任命加成落地（R7，`appointment.zhangLaoResearchSpeedBonus`
## 已在 `research_turns` 内按长老人数计入）。

## 宗门时代对道法时代的允许超前量：已解锁最高时代 +1 内可研究。
##
## PRD §4.9 只给出 5 时代与前置链，**未定义时代门控公式**；若按「同代才可研究」则
## 炼气篇 3 条解锁后宗门时代仍为炼气，筑基篇永久不可研究（死锁）。故取「可超前一代」，
## 既保留时代推进感又不死锁（登记于 PROTOCOL §11.1）。
const ERA_LOOKAHEAD: int = 1
## 研究回合数的下限倍率（1.0 `BuildAction.researchDao` 同值）。
const MIN_TURNS_MULTIPLIER: float = 0.3
## `effect_sum()` 的固定键（顺序固定，便于逐字比对）。
const EFFECT_KEYS: Array[String] = [
	"CULTIVATION_BONUS", "ECONOMY_BONUS", "COMBAT_BONUS", "MOVE_BONUS", "VISION_BONUS", "RESEARCH_BONUS",
]
const UNLOCK_KEYS: Array[String] = [
	"UNLOCK_IMPROVEMENT", "UNLOCK_BUILDING", "UNLOCK_UNIT", "UNLOCK_DISTRICT", "UNLOCK_TELEPORT", "UNLOCK_POLICY",
]


# ---------------------------------------------------------------------------
# 道法树读取
# ---------------------------------------------------------------------------

static func all_daos(config: Dictionary) -> Array[Dao]:
	var out: Array[Dao] = []
	for entry: Variant in config["daoTree"]["daos"]:
		out.append(Dao.from_config(entry))
	return out


static func find_dao(config: Dictionary, dao_id: String) -> Dao:
	for entry: Variant in config["daoTree"]["daos"]:
		var item: Dictionary = entry
		if str(item.get("id", "")) == dao_id:
			return Dao.from_config(item)
	return null


static func era_index(config: Dictionary, era_name: String) -> int:
	return (config["daoTree"]["eras"] as Array).find(era_name)


## 宗门时代 = 已解锁道法所属**最高**时代的索引；未解锁任何道法时为 0（炼气篇）。
static func sect_era_index(_state: GameState, config: Dictionary, sect: Sect) -> int:
	var highest: int = 0
	for dao_id: String in sect.unlockedDaoIds:
		var dao: Dao = find_dao(config, dao_id)
		if dao == null:
			continue
		highest = maxi(highest, era_index(config, dao.era))
	return highest


static func is_unlocked(sect: Sect, dao_id: String) -> bool:
	return sect.unlockedDaoIds.has(dao_id)


static func is_queued(sect: Sect, dao_id: String) -> bool:
	for project: ResearchProject in sect.researchQueue:
		if project.daoId == dao_id:
			return true
	return false


## 未满足的前置道法 id 列表（1.0 `DaoEffects.unmetPrereqs`）。
static func unmet_prerequisites(sect: Sect, dao: Dao) -> Array[String]:
	var out: Array[String] = []
	for prerequisite: String in dao.prerequisiteDaoIds:
		if not sect.unlockedDaoIds.has(prerequisite):
			out.append(prerequisite)
	return out


# ---------------------------------------------------------------------------
# 费用与工期
# ---------------------------------------------------------------------------

## 血脉道法费用折算率（`faction.jiaZu.bloodDaoCostReduction`，下限 0.1；1.0 同口径）。
static func _blood_cost_rate(config: Dictionary, dao: Dao) -> float:
	if not dao.requiresBloodLine:
		return 1.0
	return maxf(0.1, 1.0 - float(config["faction"]["jiaZu"]["bloodDaoCostReduction"]))


static func dao_point_cost(config: Dictionary, dao: Dao) -> int:
	return int(round(float(dao.daoPointCost) * _blood_cost_rate(config, dao)))


## 研究项目的**工力总额**（1.0 把 `dao.spiritPowerCost` 当作工力，非灵力）。
static func work_cost(config: Dictionary, dao: Dao) -> int:
	return int(round(float(dao.spiritPowerCost) * _blood_cost_rate(config, dao)))


## 研究回合数 = `dao.turns` ×（1 − 宗门研究加速）×（1 − 长老数×加成）×（1 − RESEARCH_BONUS），下限 0.3。
static func research_turns(config: Dictionary, sect: Sect, dao: Dao) -> int:
	var multiplier: float = 1.0
	if sect.factionType == Enums.FactionType.ZONG_MEN:
		multiplier *= 1.0 - float(config["faction"]["zongMen"]["researchSpeedBonus"])
	var elders: int = 0
	for disciple: Disciple in sect.disciples:
		if disciple.position == "ZHANG_LAO":
			elders += 1
	multiplier *= 1.0 - float(elders) * float(config["appointment"]["zhangLaoResearchSpeedBonus"])
	multiplier *= 1.0 - minf(0.5, float(effect_sum(null, config, sect).get("RESEARCH_BONUS", 0.0)))
	multiplier = maxf(MIN_TURNS_MULTIPLIER, multiplier)
	return maxi(1, int(round(float(dao.turns) * multiplier)))


# ---------------------------------------------------------------------------
# 研究门控
# ---------------------------------------------------------------------------

## 研究合法性：返回 `{allowed, blocker}`；`blocker` 空串 = 可研究。
## 检查顺序对齐 1.0 `BuildAction.researchDao`：存在 → 已解锁 → 研究中 → 前置 → 时代 → 流派 → 血脉 → 道点。
static func can_research(state: GameState, config: Dictionary, sect: Sect, dao_id: String) -> Dictionary:
	var dao: Dao = find_dao(config, dao_id)
	if dao == null:
		return {"allowed": false, "blocker": "道统树中不存在道法: " + dao_id}
	if sect.unlockedDaoIds.has(dao_id):
		return {"allowed": false, "blocker": "该道法已推演完成: " + dao.name}
	if is_queued(sect, dao_id):
		return {"allowed": false, "blocker": "该道法已在研究中: " + dao.name}
	var unmet: Array[String] = unmet_prerequisites(sect, dao)
	if not unmet.is_empty():
		var names: Array[String] = []
		for missing: String in unmet:
			var prerequisite: Dao = find_dao(config, missing)
			names.append(prerequisite.name if prerequisite != null else missing)
		return {"allowed": false, "blocker": "前置道法未推演: " + "、".join(names)}
	var current_era: int = sect_era_index(state, config, sect)
	var dao_era: int = era_index(config, dao.era)
	if dao_era > current_era + ERA_LOOKAHEAD:
		return {"allowed": false, "blocker": "时代未到: 需先推演%s之后时代的道法" % str(config["daoTree"]["eras"][current_era])}
	if not dao.factionOnly.is_empty() and dao.factionOnly != sect.factionType:
		return {"allowed": false, "blocker": "「%s」是%s专属道法" % [dao.name, _faction_name(config, dao.factionOnly)]}
	if dao.requiresBloodLine and not _has_bloodline(sect):
		return {"allowed": false, "blocker": "「%s」需族中血脉修士方可推演" % dao.name}
	var point_cost: int = dao_point_cost(config, dao)
	var points: int = int(sect.resources.get("daoPoints", 0))
	if points < point_cost:
		return {"allowed": false, "blocker": "道点不足: 需要 %d, 当前 %d" % [point_cost, points]}
	# 研究按工力逐回合推进（1.0 `BuildAction.advanceProject`）；工力为 0 时无法开工。
	if int(sect.resources.get("workPower", 0)) <= 0:
		return {"allowed": false, "blocker": "工力不足: 无法推进研究"}
	return {"allowed": true, "blocker": ""}


## 面板三态：`UNLOCKED` / `RESEARCHING` / `AVAILABLE` / `BLOCKED`。
static func dao_state(state: GameState, config: Dictionary, sect: Sect, dao_id: String) -> Dictionary:
	if sect.unlockedDaoIds.has(dao_id):
		return {"state": "UNLOCKED", "blocker": ""}
	if is_queued(sect, dao_id):
		return {"state": "RESEARCHING", "blocker": ""}
	var check: Dictionary = can_research(state, config, sect, dao_id)
	if bool(check["allowed"]):
		return {"state": "AVAILABLE", "blocker": ""}
	return {"state": "BLOCKED", "blocker": str(check["blocker"])}


static func _has_bloodline(sect: Sect) -> bool:
	for disciple: Disciple in sect.disciples:
		if disciple.bloodLine:
			return true
	return false


static func _faction_name(config: Dictionary, faction: String) -> String:
	var flavors: Dictionary = config["faction"]["flavors"]
	if flavors.has(faction):
		return str(flavors[faction].get("displayName", faction))
	return faction


# ---------------------------------------------------------------------------
# 效果汇总（唯一出口，裁决三）
# ---------------------------------------------------------------------------

## 把已解锁道法的 `effects` 按 type 汇总。
## 加成类（`EFFECT_KEYS`）累加为 float；解锁类（`UNLOCK_KEYS`）收集为去重的 key 数组。
static func effect_sum(_state: GameState, config: Dictionary, sect: Sect) -> Dictionary:
	var out: Dictionary = {}
	for key: String in EFFECT_KEYS:
		out[key] = 0.0
	for key: String in UNLOCK_KEYS:
		out[key] = []
	if sect == null:
		return out
	for dao_id: String in sect.unlockedDaoIds:
		var dao: Dao = find_dao(config, dao_id)
		if dao == null:
			continue
		for effect: Variant in dao.effects:
			var entry: Dictionary = effect
			var type: String = str(entry.get("type", ""))
			if EFFECT_KEYS.has(type):
				out[type] = float(out[type]) + float(entry.get("amount", 0.0))
			elif UNLOCK_KEYS.has(type):
				var key: String = str(entry.get("key", ""))
				var bucket: Array = out[type]
				if not key.is_empty() and not bucket.has(key):
					bucket.append(key)
	return out


static func move_bonus(state: GameState, config: Dictionary, sect: Sect) -> int:
	if sect == null:
		return 0
	return int(round(float(effect_sum(state, config, sect).get("MOVE_BONUS", 0.0))))


static func vision_bonus(state: GameState, config: Dictionary, sect: Sect) -> int:
	if sect == null:
		return 0
	return int(round(float(effect_sum(state, config, sect).get("VISION_BONUS", 0.0))))


static func cultivation_bonus(state: GameState, config: Dictionary, sect: Sect) -> float:
	if sect == null:
		return 0.0
	return float(effect_sum(state, config, sect).get("CULTIVATION_BONUS", 0.0))


static func economy_bonus(state: GameState, config: Dictionary, sect: Sect) -> float:
	if sect == null:
		return 0.0
	return float(effect_sum(state, config, sect).get("ECONOMY_BONUS", 0.0))


static func research_bonus(state: GameState, config: Dictionary, sect: Sect) -> float:
	if sect == null:
		return 0.0
	return float(effect_sum(state, config, sect).get("RESEARCH_BONUS", 0.0))


## 已解锁道法解锁的改良 key 集合（`UNLOCK_IMPROVEMENT`，形如 `lingtian_ti`）。
static func unlocked_improvement_keys(state: GameState, config: Dictionary, sect: Sect) -> Array:
	return effect_sum(state, config, sect).get("UNLOCK_IMPROVEMENT", [])


# ---------------------------------------------------------------------------
# 道点产出
# ---------------------------------------------------------------------------

## 宗门道点**毛收入汇总**（藏经阁 + 已占节点 + 藏经区）。
##
## **不参与结算**：R3 的 `EconomyRules.peak_output` 已把藏经阁与节点道点逐峰计入，
## 此处再入结算会双计。本函数供验收断言（`Σ peak_output.daoPoints == dao_point_output.total`）
## 与后续 UI 复用。
static func dao_point_output(state: GameState, config: Dictionary, sect: Sect) -> Dictionary:
	var cang_jing: int = 0
	var district_points: int = 0
	for peak: SpiritPeak in sect.spiritPeaks:
		cang_jing += CityRules.building_count(peak, Enums.Building.CANG_JING_GE) * int(config["daoTree"]["cangJingGePointsPerTurn"])
		for district: District in peak.districts:
			if district.type == Enums.DistrictType.CANG_JING_QU:
				district_points += int(config["city"]["district"]["yields"][Enums.DistrictType.CANG_JING_QU].get("daoPoints", 0))
	var node_points: int = 0
	var output: Dictionary = config["daoTree"]["nodeOutput"]
	for node: GameNode in state.nodes.values():
		if node.ownerSectId != sect.id:
			continue
		match node.type:
			Enums.NodeType.LING_MAI:
				node_points += int(output["lingMaiBase"]) + int(output["lingMaiPerLevel"]) * node.level
			Enums.NodeType.JI_YUAN:
				node_points += int(output["jiYuanBase"]) + int(output["jiYuanPerLevel"]) * node.level
			Enums.NodeType.MI_JING:
				node_points += int(output["miJingBase"]) + int(output["miJingPerLevel"]) * node.level
	return {
		"cangJingGe": cang_jing,
		"nodes": node_points,
		"districts": district_points,
		"total": cang_jing + node_points + district_points,
	}


# ---------------------------------------------------------------------------
# 道统成就 boost（一次性道点奖励，替代 1.0「顿悟」）
# ---------------------------------------------------------------------------

## 按 `daoTree.boosts` 判定条件；已触发过的跳过（`sect.boostFlags`）。
## 触发即加道点、置标志并返回事件文案。`boostFlags` 不下发 view（PROTOCOL §12.5）。
static func check_boosts(state: GameState, config: Dictionary, sect: Sect) -> Array[String]:
	var events: Array[String] = []
	for entry: Variant in config["daoTree"]["boosts"]:
		var boost: Dictionary = entry
		var boost_id: String = str(boost.get("id", ""))
		if boost_id.is_empty() or sect.boostFlags.has(boost_id):
			continue
		var condition: String = str(boost.get("condition", ""))
		var threshold: int = int(boost.get("threshold", 1))
		if _boost_progress(state, config, sect, condition) < threshold:
			continue
		var points: int = int(boost.get("points", 0))
		sect.boostFlags[boost_id] = true
		sect.resources["daoPoints"] = int(sect.resources.get("daoPoints", 0)) + points
		events.append("[道统] %s 达成成就「%s」, 道点 +%d" % [sect.name, _boost_name(condition), points])
	return events


static func _boost_progress(state: GameState, config: Dictionary, sect: Sect, condition: String) -> int:
	match condition:
		"miJingExplored":
			# 语义为「成功探索秘境次数」，**不是**「视野内存在秘境节点」：
			# 后者在开局视野内即成立，会让该成就第 1 回合白送 30 道点并永久失效。
			# R5 落地 `exploreMiJing` 后由该动作递增 `Sect.miJingExploredTotal`。
			return sect.miJingExploredTotal
		"ownLingMai":
			var owned: int = 0
			for node: GameNode in state.nodes.values():
				if node.type == Enums.NodeType.LING_MAI and node.ownerSectId == sect.id:
					owned += 1
			return owned
		"recruited":
			return sect.recruitedTotal
		"enemyDefeated":
			return sect.enemiesDefeated
	return 0


static func _boost_name(condition: String) -> String:
	match condition:
		"miJingExplored":
			return "初探秘境"
		"ownLingMai":
			return "三脉在手"
		"recruited":
			return "广纳门徒"
		"enemyDefeated":
			return "首战告捷"
	return condition
