class_name DiscipleRules
extends RefCounted
## 弟子修炼 / 突破 / 渡劫 / 心魔 / 伤愈规则（R4）。
##
## 数值唯一权威 `data/gameConfig.json` 的 `disciple.cultivation` / `disciple.heartDevil` /
## `disciple.{promotionWaitTurns,injuryRecoveryChance}` / `economy.prestige*`；全部静态、只读 config。
## 1.0 蓝本：`UnitRules.beginTurn()` 的修炼/心魔钩子 + `DiscipleManager.cultivate`。
##
## **所有随机只经 `RngService`**（突破成败、渡劫成败、心魔受伤/叛逃、伤愈），保证同种子逐字一致。
##
## **本类不做**：转职/晋升（R5）、`tribulate` 命令注册（R7，裁决六只落地规则函数）、
## 讲道减心魔（`jiangDaoReduce`，R7 任命/讲道）。

## 可正常突破的境界（元婴→化神由 `tribulate()` 接管，裁决六）。
const BREAKTHROUGH_REALMS: Array[String] = [
	Enums.Realm.LIAN_QI, Enums.Realm.ZHU_JI, Enums.Realm.JIN_DAN,
]


# ---------------------------------------------------------------------------
# 修炼
# ---------------------------------------------------------------------------

## 该弟子是否有洞府（R3 把洞府建成 `peak.buildings["cave_<peakId>_<discipleId>"]`）。
static func has_cave(peak: SpiritPeak, disciple_id: String) -> bool:
	if peak == null:
		return false
	return peak.buildings.has("cave_%s_%s" % [peak.id, disciple_id])


## 修炼速度 = `baseSpeed` × (1 + 灵根品级×`rootGradeBonusPerGrade` + 洞府×`caveBonus`
## + 宗门×`zongMenBonus` + 威望加成 + 道法 `CULTIVATION_BONUS`)，心魔 ≥ 阈值时 ×(1−`heartDevilPenalty`)。
static func cultivation_speed(state: GameState, config: Dictionary, disciple: Disciple) -> float:
	var cultivation: Dictionary = config["disciple"]["cultivation"]
	var sect: Sect = CityAction.find_sect(state, disciple.sectId)
	var bonus: float = 0.0
	bonus += float(cultivation["rootGradeBonusPerGrade"]) * float(disciple.rootGrade)
	var peak: SpiritPeak = _peak_of(state, sect, disciple)
	if has_cave(peak, disciple.id):
		bonus += float(cultivation["caveBonus"])
	if sect != null and sect.factionType == Enums.FactionType.ZONG_MEN:
		bonus += float(cultivation["zongMenBonus"])
	if sect != null:
		bonus += prestige_cultivation_bonus(config, sect)
		bonus += DaoRules.cultivation_bonus(state, config, sect)
	var speed: float = float(cultivation["baseSpeed"]) * (1.0 + bonus)
	if disciple.heartDevil >= int(cultivation["heartDevilPenaltyThreshold"]):
		speed *= 1.0 - float(cultivation["heartDevilPenalty"])
	return maxf(0.0, speed)


## 威望带来的修炼加成：`prestige × prestigeCultivationBonusPerPoint`，封顶 `prestigeCultivationBonusCap`。
static func prestige_cultivation_bonus(config: Dictionary, sect: Sect) -> float:
	var prestige: int = int(sect.resources.get("prestige", 0))
	return minf(float(config["economy"]["prestigeCultivationBonusCap"]),
		float(prestige) * float(config["economy"]["prestigeCultivationBonusPerPoint"]))


static func progress_cap(config: Dictionary, disciple: Disciple) -> float:
	return float(config["disciple"]["cultivation"]["progressCapPerRealm"].get(disciple.realm, 0))


## 每回合修炼的灵力消耗 = `spiritPowerCostPerTurn` + `spiritPowerCostPerRealmLevel` × (境界等级 − 1)。
static func cultivation_power_cost(config: Dictionary, disciple: Disciple) -> int:
	var cultivation: Dictionary = config["disciple"]["cultivation"]
	return int(cultivation["spiritPowerCostPerTurn"]) + int(cultivation["spiritPowerCostPerRealmLevel"]) * maxi(0, disciple.realmLevel - 1)


## 推进一回合修炼：扣灵力 → 加进度 → 满则置 `breakthroughPending`。
## 返回 `{advanced, reason, gained, progress, cap, pending, spiritPowerCost}`。
static func advance_cultivation(state: GameState, config: Dictionary, disciple: Disciple) -> Dictionary:
	var sect: Sect = CityAction.find_sect(state, disciple.sectId)
	var cost: int = cultivation_power_cost(config, disciple)
	if sect != null and int(sect.resources.get("spiritPower", 0)) < cost:
		return {"advanced": false, "reason": "灵力不足", "gained": 0.0, "progress": disciple.cultivationProgress, "cap": progress_cap(config, disciple), "pending": disciple.breakthroughPending, "spiritPowerCost": cost}
	if sect != null:
		sect.resources["spiritPower"] = int(sect.resources.get("spiritPower", 0)) - cost
	var gained: float = cultivation_speed(state, config, disciple)
	disciple.cultivationProgress = disciple.cultivationProgress + gained
	var cap: float = progress_cap(config, disciple)
	var pending: bool = false
	if cap > 0.0 and disciple.cultivationProgress >= cap:
		disciple.cultivationProgress = cap
		if disciple.realm != Enums.Realm.HUA_SHEN:
			disciple.breakthroughPending = true
			pending = true
	return {"advanced": true, "reason": "", "gained": gained, "progress": disciple.cultivationProgress, "cap": cap, "pending": pending, "spiritPowerCost": cost}


# ---------------------------------------------------------------------------
# 突破
# ---------------------------------------------------------------------------

## 突破判定：按 `breakthroughChancePerRealm[realm]` 掷骰。
## 成功 → 境界 +1、进度归零；失败 → 心魔 +`breakthroughFailHeartDevil`、进度 ×`breakthroughFailProgressRatio`。
## 元婴→化神不在本函数（须 `tribulate()`，裁决六）。
static func try_breakthrough(state: GameState, config: Dictionary, disciple: Disciple) -> Dictionary:
	var cultivation: Dictionary = config["disciple"]["cultivation"]
	if disciple.realm == Enums.Realm.HUA_SHEN:
		return {"success": false, "reason": "已至化神", "chance": 0.0, "realm": disciple.realm, "heartDevil": disciple.heartDevil, "progress": disciple.cultivationProgress}
	if disciple.realm == Enums.Realm.YUAN_YING:
		return {"success": false, "reason": "元婴突破化神须渡劫(tribulate)", "chance": 0.0, "realm": disciple.realm, "heartDevil": disciple.heartDevil, "progress": disciple.cultivationProgress}
	if not disciple.breakthroughPending:
		return {"success": false, "reason": "修为未满", "chance": 0.0, "realm": disciple.realm, "heartDevil": disciple.heartDevil, "progress": disciple.cultivationProgress}
	var chance: float = float(cultivation["breakthroughChancePerRealm"].get(disciple.realm, 0.0))
	var roll: bool = state.rng.chance(chance)
	disciple.breakthroughPending = false
	if roll:
		var index: int = Enums.Realm.ALL.find(disciple.realm)
		disciple.realm = Enums.Realm.ALL[mini(index + 1, Enums.Realm.ALL.size() - 1)]
		disciple.realmLevel = Disciple.level_of(disciple.realm)
		disciple.cultivationProgress = 0.0
		state.eventLog.append("[修炼] %s 突破至%s" % [disciple.name, _realm_name(config, disciple.realm)])
		return {"success": true, "reason": "", "chance": chance, "realm": disciple.realm, "heartDevil": disciple.heartDevil, "progress": disciple.cultivationProgress}
	disciple.heartDevil = mini(int(config["disciple"]["heartDevil"]["max"]), disciple.heartDevil + int(cultivation["breakthroughFailHeartDevil"]))
	disciple.cultivationProgress = disciple.cultivationProgress * float(cultivation["breakthroughFailProgressRatio"])
	state.eventLog.append("[修炼] %s 突破失败, 心魔 %d" % [disciple.name, disciple.heartDevil])
	return {"success": false, "reason": "突破失败", "chance": chance, "realm": disciple.realm, "heartDevil": disciple.heartDevil, "progress": disciple.cultivationProgress}


## 渡劫（元婴→化神）。**规则函数**；对外命令 `tribulate` 归 R7（裁决六）。
## 耗灵力 500 + 天晶3 + 玄铁2 + 灵石300；成功率 = 基础 + 已解锁道法数×5% + 灵根品级×5%；
## 失败心魔 +50 且按 `tribulationFailFallChance` 陨落（`fallen=true`，由调用方移除弟子）。
static func tribulate(state: GameState, config: Dictionary, disciple: Disciple) -> Dictionary:
	var cultivation: Dictionary = config["disciple"]["cultivation"]
	var sect: Sect = CityAction.find_sect(state, disciple.sectId)
	var fail: Dictionary = {"success": false, "reason": "", "chance": 0.0, "realm": disciple.realm, "heartDevil": disciple.heartDevil, "fallen": false}
	if sect == null:
		fail["reason"] = "宗门不存在"
		return fail
	if disciple.realm != Enums.Realm.YUAN_YING:
		fail["reason"] = "仅元婴可渡劫"
		return fail
	var power_cost: int = int(cultivation["tribulationSpiritPowerCost"])
	var stone_cost: int = int(cultivation["tribulationSpiritStoneCost"])
	var materials: Dictionary = sect.resources.get("materials", {})
	var material_cost: Dictionary = cultivation["tribulationMaterialCosts"]
	if int(sect.resources.get("spiritPower", 0)) < power_cost:
		fail["reason"] = "灵力不足: 需要 %d" % power_cost
		return fail
	if int(sect.resources.get("spiritStones", 0)) < stone_cost:
		fail["reason"] = "灵石不足: 需要 %d" % stone_cost
		return fail
	for material: Variant in material_cost.keys():
		if int(materials.get(material, 0)) < int(material_cost[material]):
			fail["reason"] = "材料不足: 需要 %s x%d" % [str(material), int(material_cost[material])]
			return fail
	sect.resources["spiritPower"] = int(sect.resources.get("spiritPower", 0)) - power_cost
	sect.resources["spiritStones"] = int(sect.resources.get("spiritStones", 0)) - stone_cost
	for material: Variant in material_cost.keys():
		materials[material] = int(materials.get(material, 0)) - int(material_cost[material])
	sect.resources["materials"] = materials
	var chance: float = float(cultivation["tribulationBaseSuccessChance"])
	chance += float(sect.unlockedDaoIds.size()) * float(cultivation["tribulationDaoBonusPerUnlocked"])
	chance += float(disciple.rootGrade) * float(cultivation["tribulationRootGradeBonusPerGrade"])
	chance = clampf(chance, 0.0, 1.0)
	disciple.tribulating = true
	var roll: bool = state.rng.chance(chance)
	disciple.tribulating = false
	if roll:
		disciple.realm = Enums.Realm.HUA_SHEN
		disciple.realmLevel = Disciple.level_of(disciple.realm)
		disciple.cultivationProgress = 0.0
		disciple.breakthroughPending = false
		state.eventLog.append("[渡劫] %s 渡劫成功, 晋化神" % disciple.name)
		return {"success": true, "reason": "", "chance": chance, "realm": disciple.realm, "heartDevil": disciple.heartDevil, "fallen": false}
	disciple.heartDevil = mini(int(config["disciple"]["heartDevil"]["max"]), disciple.heartDevil + int(cultivation["tribulationFailHeartDevil"]))
	var fallen: bool = state.rng.chance(float(cultivation["tribulationFailFallChance"]))
	state.eventLog.append("[渡劫] %s 渡劫失败, 心魔 %d%s" % [disciple.name, disciple.heartDevil, ", 身死道消" if fallen else ""])
	return {"success": false, "reason": "渡劫失败", "chance": chance, "realm": disciple.realm, "heartDevil": disciple.heartDevil, "fallen": fallen}


# ---------------------------------------------------------------------------
# 心魔 / 伤愈
# ---------------------------------------------------------------------------

## 每回合心魔结算：超容量 +`overCapacityPerTurn`；≥`injuryThreshold` 按 `injuryChance` 受伤；
## ≥`betrayThreshold` 按 `betrayNeutralChance` 叛逃（`betray=true`，由调用方转中立）。
## 有洞府时按 `caveReduce` 递减（PRD §4.4「洞府/讲道各 −5」；讲道归 R7）。
static func heart_devil_tick(state: GameState, config: Dictionary, disciple: Disciple) -> Dictionary:
	var heart: Dictionary = config["disciple"]["heartDevil"]
	var max_devil: int = int(heart["max"])
	var sect: Sect = CityAction.find_sect(state, disciple.sectId)
	var peak: SpiritPeak = _peak_of(state, sect, disciple)
	if peak != null and _assigned_count(sect, peak.id) > peak.capacity:
		disciple.heartDevil += int(heart["overCapacityPerTurn"])
	if has_cave(peak, disciple.id):
		disciple.heartDevil = maxi(0, disciple.heartDevil - int(heart["caveReduce"]))
	disciple.heartDevil = clampi(disciple.heartDevil, 0, max_devil)
	var injured: bool = false
	if disciple.heartDevil >= int(heart["injuryThreshold"]) and not disciple.injured:
		if state.rng.chance(float(heart["injuryChance"])):
			disciple.injured = true
			injured = true
			state.eventLog.append("[心魔] %s 心魔反噬, 受伤" % disciple.name)
	var betray: bool = false
	if disciple.heartDevil >= int(heart["betrayThreshold"]):
		if state.rng.chance(float(heart["betrayNeutralChance"])):
			betray = true
			state.eventLog.append("[心魔] %s 心魔失控, 叛出宗门" % disciple.name)
	return {"heartDevil": disciple.heartDevil, "injured": injured, "betray": betray}


## 回合开始伤愈：按 `injuryRecoveryChance` 恢复。
static func heal_tick(state: GameState, config: Dictionary, disciple: Disciple) -> bool:
	if not disciple.injured:
		return false
	if state.rng.chance(float(config["disciple"]["injuryRecoveryChance"])):
		disciple.injured = false
		return true
	return false


# ---------------------------------------------------------------------------
# 内部工具
# ---------------------------------------------------------------------------

static func _peak_of(state: GameState, sect: Sect, disciple: Disciple) -> SpiritPeak:
	if sect == null:
		return null
	for peak: SpiritPeak in sect.spiritPeaks:
		if peak.id == disciple.assignedPeakId:
			return peak
	return null


static func _assigned_count(sect: Sect, peak_id: String) -> int:
	var count: int = 0
	for disciple: Disciple in sect.disciples:
		if disciple.assignedPeakId == peak_id:
			count += 1
	return count


static func _realm_name(_config: Dictionary, realm: String) -> String:
	return str(Enums.Realm.NAMES.get(realm, realm))
