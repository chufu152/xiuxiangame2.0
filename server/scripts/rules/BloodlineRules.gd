class_name BloodlineRules
extends RefCounted
## 血脉：联姻 / 繁衍 / 灵根继承（对齐 1.0 `action/BloodlineAction`）。
##
## **仅家族流有效**（`factionType == JIA_ZU` 的繁衍才吃 `jiaZu.highGradeRootChanceBonus`；
## 联姻与繁衍本身任何流派都能做，但只有家族流能靠它赢）。
##
## **血脉没有独立命令**（PROTOCOL 69 条里没有 `marry`/`reproduce`）——本类只由
## `AIController` 与内部结算调用，**未新增命令**（R7 提示词任务 2 注）。
##
## **所有随机只经 `GameState.rng`**（硬约束 6）。掷骰顺序严格照 1.0 `inheritChild`：
## 名字 → 品级抖动 → 家族流高品加成 → 先天突变 → 主灵根 → 额外灵根。
## 顺序固定才能让「同种子 + 同指令序列」逐字一致，也让验收可以独立复算。

const MAX_GRADE: int = 5
const MIN_GRADE: int = 1
## 子嗣名字后缀池（1.0 `DiscipleManager.childName` 的随机取名；2.0 用宗门名 + 序号 + 后缀，
## 保证同名可辨且不依赖外部词表）。
const CHILD_SUFFIXES: Array[String] = [
	"承志", "明轩", "清和", "怀瑾", "知微", "望舒", "听雪", "砚秋", "长风", "映川",
]


# ---------------------------------------------------------------------------
# 联姻
# ---------------------------------------------------------------------------

## 不可联姻的原因，可联姻返回空串（1.0 `marryBlocker`）。
static func marry_blocker(state: GameState, config: Dictionary, id_a: String, id_b: String) -> String:
	var a: Disciple = CityAction.find_disciple(state, id_a)
	var b: Disciple = CityAction.find_disciple(state, id_b)
	if a == null or b == null:
		return "弟子不存在"
	if a.id == b.id:
		return "不能与自己联姻"
	if a.sectId != b.sectId:
		return "两人不属同一宗门"
	if not a.spouseId.is_empty() or not b.spouseId.is_empty():
		return "一方已有道侣"
	if is_close_kin(a, b):
		return "血缘过近, 不可联姻"
	var sect: Sect = CityAction.find_sect(state, a.sectId)
	if sect == null:
		return "宗门不存在"
	var cost: int = int(config["faction"]["bloodline"]["marryCostStones"])
	if int(sect.resources.get("spiritStones", 0)) < cost:
		return "灵石不足(联姻需%d灵石)" % cost
	return ""


## 联姻：双方结为道侣，非血脉一方随婚入族（1.0 `marry`）。
## 返回 `{success, message, cost, spouseId}`。
static func marry(state: GameState, config: Dictionary, id_a: String, id_b: String) -> Dictionary:
	var blocker: String = marry_blocker(state, config, id_a, id_b)
	if not blocker.is_empty():
		return {"success": false, "message": blocker, "cost": 0, "spouseId": ""}
	var a: Disciple = CityAction.find_disciple(state, id_a)
	var b: Disciple = CityAction.find_disciple(state, id_b)
	var sect: Sect = CityAction.find_sect(state, a.sectId)
	var cost: int = int(config["faction"]["bloodline"]["marryCostStones"])
	sect.resources["spiritStones"] = int(sect.resources.get("spiritStones", 0)) - cost
	a.spouseId = b.id
	b.spouseId = a.id
	if a.bloodLine != b.bloodLine:
		a.bloodLine = true
		b.bloodLine = true
	state.eventLog.append("[家族] %s 与 %s 结为道侣(聘礼%d灵石), %s" % [
		a.name, b.name, cost, "二人为血脉族人" if a.bloodLine else "二人入籍族谱",
	])
	return {"success": true, "message": "%s 与 %s 结为道侣" % [a.name, b.name], "cost": cost, "spouseId": b.id}


# ---------------------------------------------------------------------------
# 繁衍
# ---------------------------------------------------------------------------

## 不可繁衍的原因，可繁衍返回空串（1.0 `reproduceBlocker`）。
static func reproduce_blocker(state: GameState, config: Dictionary, peak_id: String,
		father_id: String, mother_id: String) -> String:
	var father: Disciple = CityAction.find_disciple(state, father_id)
	var mother: Disciple = CityAction.find_disciple(state, mother_id)
	if father == null or mother == null:
		return "父母不存在"
	if father.id == mother.id:
		return "需两名族人共同繁衍"
	if father.sectId != mother.sectId:
		return "两人不属同一宗门"
	if father.spouseId != mother.id or mother.spouseId != father.id:
		return "二人需先结为道侣"
	var sect: Sect = CityAction.find_sect(state, father.sectId)
	var peak: SpiritPeak = _peak_in_sect(sect, peak_id)
	if peak == null:
		return "灵峰不属本宗"
	var cooldown: int = int(config["faction"]["bloodline"]["reproduceCooldownTurns"])
	if _within_cooldown(state, father, cooldown) or _within_cooldown(state, mother, cooldown):
		return "繁衍需休养(还需%d回合)" % _cooldown_left(state, father, mother, cooldown)
	if int(sect.resources.get("spiritStones", 0)) < reproduce_stone_cost(config, sect, peak):
		return "灵石不足(繁衍需%d灵石)" % reproduce_stone_cost(config, sect, peak)
	if int(sect.resources.get("workPower", 0)) < reproduce_work_cost(config, sect, peak):
		return "工力不足(繁衍需%d工力)" % reproduce_work_cost(config, sect, peak)
	return ""


## 繁衍：扣灵石与工力 → 子嗣降生（灵根品级继承父母并小概率变异）。
## 返回 `{success, message, childId, stoneCost, workCost}`。
static func reproduce(state: GameState, config: Dictionary, peak_id: String,
		father_id: String, mother_id: String) -> Dictionary:
	var blocker: String = reproduce_blocker(state, config, peak_id, father_id, mother_id)
	if not blocker.is_empty():
		return {"success": false, "message": blocker, "childId": "", "stoneCost": 0, "workCost": 0}
	var father: Disciple = CityAction.find_disciple(state, father_id)
	var mother: Disciple = CityAction.find_disciple(state, mother_id)
	var sect: Sect = CityAction.find_sect(state, father.sectId)
	var peak: SpiritPeak = _peak_in_sect(sect, peak_id)
	var stone_cost: int = reproduce_stone_cost(config, sect, peak)
	var work_cost: int = reproduce_work_cost(config, sect, peak)
	sect.resources["spiritStones"] = int(sect.resources.get("spiritStones", 0)) - stone_cost
	sect.resources["workPower"] = int(sect.resources.get("workPower", 0)) - work_cost
	var child: Disciple = inherit_child(state, config, sect, peak, father, mother)
	sect.disciples.append(child)
	father.lastReproduceTurn = state.turn
	mother.lastReproduceTurn = state.turn
	# 子嗣也是人口：同步人口/住房/空闲劳力，避免「有人无口」。
	peak.population += 1
	peak.housing = CityRules.housing_of(state, config, peak)
	CityRules.sync_free_workers(peak)
	state.eventLog.append("[家族] %s 与 %s 的子嗣 %s 降生于%s(第%d代·灵根品级%d, 耗灵石%d/工力%d)" % [
		father.name, mother.name, child.name, peak.name, child.generation,
		child.rootGrade, stone_cost, work_cost,
	])
	return {
		"success": true,
		"message": "%s 降生(灵根品级%d)" % [child.name, child.rootGrade],
		"childId": child.id,
		"stoneCost": stone_cost,
		"workCost": work_cost,
	}


## 子嗣构造（1.0 `inheritChild`）。掷骰顺序**不可调换**，见类头注释。
static func inherit_child(state: GameState, config: Dictionary, sect: Sect, peak: SpiritPeak,
		father: Disciple, mother: Disciple) -> Disciple:
	var bloodline: Dictionary = config["faction"]["bloodline"]
	var setup: Dictionary = config["map"]["setup"]
	state.discipleSeq += 1
	var child: Disciple = Disciple.new()
	child.id = "disciple_%s_%d" % [sect.id, state.discipleSeq]
	# 1) 名字：后缀由 RNG 选，序号保证唯一。
	child.name = "%s·%s%d" % [
		sect.name,
		CHILD_SUFFIXES[state.rng.next_int(0, CHILD_SUFFIXES.size() - 1)],
		child_seq_of(sect),
	]
	child.sectId = sect.id
	child.tileId = peak.tileId
	child.realm = Enums.Realm.LIAN_QI
	child.realmLevel = Disciple.level_of(child.realm)
	child.position = Enums.Position.ZA_YI
	child.assignedPeakId = peak.id
	child.turnsInSect = 0
	child.bloodLine = father.bloodLine or mother.bloodLine
	child.generation = maxi(father.generation, mother.generation) + 1
	child.directLine = father.directLine or mother.directLine
	child.fatherId = father.id
	child.motherId = mother.id
	# 2) 品级 = 父母均值，四舍五入。
	var grade: int = int(round((float(father.rootGrade) + float(mother.rootGrade)) / 2.0))
	# 3) 品级抖动：`gradeJitterChance` 命中则 ±1（1.0 `random.nextBoolean()`）。
	if state.rng.chance(float(bloodline["gradeJitterChance"])):
		grade += 1 if state.rng.next_int(0, 1) == 1 else -1
	# 4) 家族流高品灵根加成（`jiaZu.highGradeRootChanceBonus`）：仅家族流掷这一次。
	if sect.factionType == Enums.FactionType.JIA_ZU \
			and state.rng.chance(float(config["faction"]["jiaZu"]["highGradeRootChanceBonus"])):
		grade += 1
	# 5) 先天突变 `gradeMutationUpChance`。
	if state.rng.chance(float(bloodline["gradeMutationUpChance"])):
		grade += 1
	child.rootGrade = clampi(grade, MIN_GRADE, MAX_GRADE)
	# 6) 灵根类型继承（`extraRootChance` 出第二灵根）。
	child.spiritRoots = inherit_roots(state, father, mother, float(bloodline["extraRootChance"]))
	child.unitClass = str(setup.get("unitClass", Enums.UnitClass.PU_TONG))
	var points: int = MoveRules.calculate_max_move_points(child, config, state, sect)
	child.maxMovePoints = points
	child.movePoints = points
	child.attacksRemaining = int(config["warfare"]["attacksPerTurn"])
	return child


## 灵根继承：从父母灵根并集取一，`extra_root_chance` 命中再取一（1.0 `inheritRoots`）。
static func inherit_roots(state: GameState, father: Disciple, mother: Disciple,
		extra_root_chance: float) -> Array[String]:
	var pool: Array[String] = []
	for root: String in father.spiritRoots:
		if not pool.has(root):
			pool.append(root)
	for root: String in mother.spiritRoots:
		if not pool.has(root):
			pool.append(root)
	if pool.is_empty():
		pool.append(Enums.SpiritRootType.ALL[state.rng.next_int(0, Enums.SpiritRootType.ALL.size() - 1)])
	var roots: Array[String] = []
	roots.append(pool[state.rng.next_int(0, pool.size() - 1)])
	if state.rng.chance(extra_root_chance):
		var extra: String = ""
		if pool.size() > 1:
			var rest: Array[String] = []
			for root: String in pool:
				if root != roots[0]:
					rest.append(root)
			extra = rest[state.rng.next_int(0, rest.size() - 1)]
		else:
			extra = Enums.SpiritRootType.ALL[state.rng.next_int(0, Enums.SpiritRootType.ALL.size() - 1)]
		if not roots.has(extra):
			roots.append(extra)
	return roots


# ---------------------------------------------------------------------------
# 费用
# ---------------------------------------------------------------------------

## 繁衍灵石花费：祖祠落成则按 `zuCiReproduceCostReduction` 减免（1.0 `reproduceStoneCost`）。
static func reproduce_stone_cost(config: Dictionary, sect: Sect, peak: SpiritPeak) -> int:
	return _zu_ci_discount(config, sect, peak, int(config["faction"]["bloodline"]["reproduceCostStones"]))


## 繁衍工力花费：同上。
static func reproduce_work_cost(config: Dictionary, sect: Sect, peak: SpiritPeak) -> int:
	return _zu_ci_discount(config, sect, peak, int(config["faction"]["bloodline"]["reproduceCostWorkPower"]))


static func _zu_ci_discount(config: Dictionary, sect: Sect, peak: SpiritPeak, base: int) -> int:
	if sect == null or sect.factionType != Enums.FactionType.JIA_ZU:
		return base
	if peak == null or not peak.buildings.has(Enums.Building.ZU_CI):
		return base
	var reduction: float = float(config["faction"]["jiaZu"]["zuCiReproduceCostReduction"])
	return base - int(round(float(base) * reduction))


# ---------------------------------------------------------------------------
# 族人死亡
# ---------------------------------------------------------------------------

## 族人死亡安定惩罚（`bloodlineDeathStabilityPenalty`）：该宗每座灵峰安定 −5（下限 0）。
## 只在**家族流**触发（血脉是家族流的胜利根基，丁口损失直接动摇人心）。
static func on_clan_death(state: GameState, config: Dictionary, sect: Sect, disciple: Disciple) -> void:
	if sect == null or disciple == null:
		return
	if sect.factionType != Enums.FactionType.JIA_ZU or not disciple.bloodLine:
		return
	var penalty: int = int(config["faction"]["bloodline"]["bloodlineDeathStabilityPenalty"])
	for peak: SpiritPeak in sect.spiritPeaks:
		peak.stability = clampf(peak.stability - float(penalty), 0.0, float(config["city"]["stabilityMax"]))
	state.eventLog.append("[家族] %s 陨落, 全宗安定 -%d" % [disciple.name, penalty])


# ---------------------------------------------------------------------------
# 辅助
# ---------------------------------------------------------------------------

## 近亲判定（1.0 `isCloseKin`）：同父/同母，或互为父母。
static func is_close_kin(a: Disciple, b: Disciple) -> bool:
	if a.fatherId != "" and a.fatherId == b.fatherId:
		return true
	if a.motherId != "" and a.motherId == b.motherId:
		return true
	return a.id == b.fatherId or a.id == b.motherId or b.id == a.fatherId or b.id == a.motherId


static func _within_cooldown(state: GameState, parent: Disciple, cooldown: int) -> bool:
	return parent.lastReproduceTurn > 0 and state.turn - parent.lastReproduceTurn < cooldown


static func _cooldown_left(state: GameState, father: Disciple, mother: Disciple, cooldown: int) -> int:
	var left: int = 0
	for parent: Disciple in [father, mother]:
		if parent.lastReproduceTurn > 0:
			left = maxi(left, cooldown - (state.turn - parent.lastReproduceTurn))
	return left


static func _peak_in_sect(sect: Sect, peak_id: String) -> SpiritPeak:
	if sect == null or peak_id.is_empty():
		return null
	for peak: SpiritPeak in sect.spiritPeaks:
		if peak.id == peak_id:
			return peak
	return null


## 子嗣序号：只数名字里带「·」的（本类生成的血脉子嗣），保证同宗多胎不重名。
static func child_seq_of(sect: Sect) -> int:
	var count: int = 0
	for disciple: Disciple in sect.disciples:
		if disciple.name.contains("·"):
			count += 1
	return count + 1
