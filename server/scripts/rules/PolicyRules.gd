class_name PolicyRules
extends RefCounted
## 政令规则（R6）：3 政体 × 槽位 + 8 政令卡（时代/道法门控）+ 切换冷却 + 每回合效果结算。
##
## 1.0 蓝本：`core/PolicyService.java` + `action/PolicyAction.java`。
##
## 2.0 裁剪（裁决一，PRD §5.2 #3/#4）：
## - 一切 `loyaltyPerTurn` 语义一律落 `stabilityPerTurn`（安定），**不实现 `weariness`**；
## - 2 张外交卡已删，`category=diplomacy` 不再出现（`category_label` 保留映射仅为兼容旧档文案）。
##
## 安定落地口径（R6 裁决）：2.0 的 `SpiritPeak.stability` 是 `EconomyRules.stability_of()` **每回合重算的派生值**，
## 因此政令安定不并入派生公式（会改动 R3 已验证的安定/产出系数），而是**在结算之后叠加**：
## `peak.stability = clamp(base + 已落地安定叠加值)`，叠加值本身按小数累积逐回合增长。
## 百分比类效果（`outputBonus`/`spiritPowerBonus`/`cultivationBonus`/`combatBonus`）经 `effect_sum` **唯一出口**
## 对外暴露，消费方接入登记在 PROTOCOL §11.2（R6 不改动 R3/R5 已验证的产出与战力公式）。

## 小数累积容差：逐回合浮点累加常得到 0.9999999999999998，无容差会吞掉整点（1.0 同值）。
const CARRY_EPSILON: float = 1e-9

## `effect_sum` 的**全部**键（2.0 `policy` 配置里出现过的效果键，缺省补 0）。
## 顺序固定 → `queryPolicyOptions.effects{}` 与 `effects_text` 逐字稳定。
const EFFECT_KEYS: Array[String] = [
	"outputBonus",
	"spiritPowerBonus",
	"cultivationBonus",
	"combatBonus",
	"stabilityPerTurn",
	"prestigePerTurn",
]

## 百分比类效果（`formatEffects` 按 `+15%` 展示）；其余按 `+0.5/回合` 展示。
const PERCENT_KEYS: Array[String] = ["outputBonus", "spiritPowerBonus", "cultivationBonus", "combatBonus"]


# ---------------------------------------------------------------------------
# 配置读取
# ---------------------------------------------------------------------------

static func enabled(config: Dictionary) -> bool:
	return bool(config["policy"].get("enabled", false))


static func government(config: Dictionary, government_id: String) -> Dictionary:
	if government_id.is_empty():
		return {}
	for entry: Variant in config["policy"]["governments"]:
		var item: Dictionary = entry
		if str(item.get("id", "")) == government_id:
			return item
	return {}


static func card(config: Dictionary, card_id: String) -> Dictionary:
	if card_id.is_empty():
		return {}
	for entry: Variant in config["policy"]["cards"]:
		var item: Dictionary = entry
		if str(item.get("id", "")) == card_id:
			return item
	return {}


## 当前政体：未立政体（空 id / 旧档 / 配置里已不存在）回退配置**首个**政体（宗门共治）。
static func government_of(_state: GameState, config: Dictionary, sect: Sect) -> Dictionary:
	if sect != null:
		var by_id: Dictionary = government(config, sect.governmentId)
		if not by_id.is_empty():
			return by_id
	var list: Array = config["policy"]["governments"]
	if list.is_empty():
		return {}
	return list[0]


## 本宗时代序号（**复用 R4 `DaoRules.sect_era_index`**，裁决五；不另立口径）。
static func sect_era_index(state: GameState, config: Dictionary, sect: Sect) -> int:
	return DaoRules.sect_era_index(state, config, sect)


## 时代门槛：空/未知时代名 = 无门槛；返回空串 = 通过，否则中文原因。
static func era_block_reason(state: GameState, config: Dictionary, sect: Sect, unlock_era: String) -> String:
	if unlock_era.is_empty():
		return ""
	var need: int = DaoRules.era_index(config, unlock_era)
	if need < 0:
		return ""
	if sect_era_index(state, config, sect) >= need:
		return ""
	return "未至「%s」" % unlock_era


## 该类目已占用的槽位数（按 `policy.cards[].category` 统计）。
static func used_slots(config: Dictionary, sect: Sect, category: String) -> int:
	if sect == null:
		return 0
	var count: int = 0
	for card_id: String in sect.enactedPolicies:
		var entry: Dictionary = card(config, card_id)
		if not entry.is_empty() and str(entry.get("category", "")) == category:
			count += 1
	return count


# ---------------------------------------------------------------------------
# 校验（返回空串 = 通过）
# ---------------------------------------------------------------------------

## 可颁行检查：系统关闭 / 卡不存在 / 已颁行 / 政体无此类槽位 / 槽满 / 时代 / 道法。
static func card_block_reason(state: GameState, config: Dictionary, sect: Sect, card_id: String) -> String:
	if not enabled(config):
		return "政令系统未启用"
	var entry: Dictionary = card(config, card_id)
	if entry.is_empty():
		return "政令卡不存在"
	if sect == null:
		return "宗门不存在"
	if sect.enactedPolicies.has(card_id):
		return "「%s」已颁行" % str(entry.get("name", card_id))
	var gov: Dictionary = government_of(state, config, sect)
	if gov.is_empty():
		return "未立政体, 无从颁行"
	var category: String = str(entry.get("category", ""))
	var slots: Dictionary = gov.get("slots", {})
	if int(slots.get(category, 0)) <= 0:
		return "当前政体无此类槽位"
	if used_slots(config, sect, category) >= int(slots.get(category, 0)):
		return "%s槽位已满" % category_label(category)
	var era_reason: String = era_block_reason(state, config, sect, str(entry.get("unlockEra", "")))
	if not era_reason.is_empty():
		return era_reason
	var dao_key: String = str(entry.get("unlockDaoKey", ""))
	if not dao_key.is_empty() and not DaoRules.is_unlocked(sect, dao_key):
		var dao: Dao = DaoRules.find_dao(config, dao_key)
		return "需先修成道法「%s」" % (dao_key if dao == null else dao.name)
	return ""


## 可切换检查：系统关闭 / 政体不存在 / 已是该政体 / 时代 / 冷却。
static func switch_block_reason(state: GameState, config: Dictionary, sect: Sect, government_id: String) -> String:
	if not enabled(config):
		return "政令系统未启用"
	var target: Dictionary = government(config, government_id)
	if target.is_empty():
		return "政体不存在"
	if sect == null:
		return "宗门不存在"
	var current: Dictionary = government_of(state, config, sect)
	if not current.is_empty() and str(current.get("id", "")) == str(target.get("id", "")):
		return "已是该政体"
	var era_reason: String = era_block_reason(state, config, sect, str(target.get("unlockEra", "")))
	if not era_reason.is_empty():
		return era_reason
	var cooldown_left: int = switch_cooldown_left(state, config, sect)
	if cooldown_left > 0:
		return "政体切换冷却中(还需%d回合)" % cooldown_left
	return ""


## 政体切换冷却剩余回合（切换当回合记满冷却；`lastPolicySwitchTurn<=0` 视作从未切换 = 无冷却）。
static func switch_cooldown_left(state: GameState, config: Dictionary, sect: Sect) -> int:
	if sect == null or sect.lastPolicySwitchTurn <= 0:
		return 0
	var cooldown: int = int(config["policy"]["switchCooldownTurns"])
	return maxi(0, sect.lastPolicySwitchTurn + cooldown - state.turn)


# ---------------------------------------------------------------------------
# 效果汇总与结算
# ---------------------------------------------------------------------------

## 效果合计 = 政体 + 全部已颁政令卡；系统关闭返回全零。**所有消费方的唯一出口。**
static func effect_sum(state: GameState, config: Dictionary, sect: Sect) -> Dictionary:
	var sum: Dictionary = {}
	for key: String in EFFECT_KEYS:
		sum[key] = 0.0
	if not enabled(config) or sect == null:
		return sum
	_merge(sum, government_of(state, config, sect).get("effects", {}))
	for card_id: String in sect.enactedPolicies:
		_merge(sum, card(config, card_id).get("effects", {}))
	return sum


## 灵力产出乘区：`1 + outputBonus + spiritPowerBonus`（1.0 `EconomyCalculator` 同一公式，
## 只作用于**灵力总产出**，不作用于灵石/道点）。未颁任何加成卡时恒为 `1.0`。
## 这是 `outputBonus` / `spiritPowerBonus` 的唯一消费口——`effect_sum` 汇总出来的四个百分比乘区
## 必须各自落到自己的消费点，否则「灵田制 产出+15%」颁了也等于没颁。
static func output_multiplier(state: GameState, config: Dictionary, sect: Sect) -> float:
	var effects: Dictionary = effect_sum(state, config, sect)
	return 1.0 + float(effects["outputBonus"]) + float(effects["spiritPowerBonus"])


## 修炼加成：并入 `DiscipleRules.cultivation_speed` 的加性池（1.0 `DiscipleManager` 乘 `1 + cultivationBonus`）。
static func cultivation_bonus(state: GameState, config: Dictionary, sect: Sect) -> float:
	return float(effect_sum(state, config, sect)["cultivationBonus"])


## 战力加成：`CombatResolver.compute_power` 末尾乘 `1 + combatBonus`（1.0 `CombatResolver` 同口径）。
static func combat_bonus(state: GameState, config: Dictionary, sect: Sect) -> float:
	return float(effect_sum(state, config, sect)["combatBonus"])


## 每回合结算：安定（小数累积 → 叠加到各峰 `stability`）与声望（小数累积 → `resources.prestige`）。
## 返回本次新增的 `state.eventLog` 条目。
static func process_settlement(state: GameState, config: Dictionary) -> Array[String]:
	var before: int = state.eventLog.size()
	if not enabled(config):
		return []
	var stability_max: float = float(config["city"]["stabilityMax"])
	for sect: Sect in state.sects:
		var effects: Dictionary = effect_sum(state, config, sect)
		var stability_delta: int = _accrue(sect, "stability", float(effects["stabilityPerTurn"]))
		if stability_delta != 0:
			sect.policyCarry["stabilityBonus"] = int(sect.policyCarry.get("stabilityBonus", 0)) + stability_delta
			state.eventLog.append("[政令] %s 安定 %+d" % [sect.name, stability_delta])
		var bonus: int = int(sect.policyCarry.get("stabilityBonus", 0))
		if bonus != 0:
			# 在 `EconomyRules.apply_settlement` 重算安定之后叠加，不改动 R3 已验证的安定公式。
			for peak: SpiritPeak in sect.spiritPeaks:
				peak.stability = clampf(peak.stability + float(bonus), 0.0, stability_max)
		var prestige_delta: int = _accrue(sect, "prestige", float(effects["prestigePerTurn"]))
		if prestige_delta != 0:
			sect.resources["prestige"] = maxi(0, int(sect.resources.get("prestige", 0)) + prestige_delta)
			state.eventLog.append("[政令] %s 声望 %+d" % [sect.name, prestige_delta])
	return state.eventLog.slice(before)


## 小数累积：本次应落地的整数 = (存量余数 + perTurn) 向零截断，余数存回本宗账户。
## 每回合 +0.2 即每 5 回合落地 +1；负向效果（集权 −0.5/回合）对称生效。
static func _accrue(sect: Sect, key: String, per_turn: float) -> int:
	var remain: float = float(sect.policyCarry.get(key, 0.0))
	if is_zero_approx(per_turn) and absf(remain) < CARRY_EPSILON:
		return 0
	var total: float = remain + per_turn
	var whole: int = 0
	if total >= 0.0:
		whole = int(floor(total + CARRY_EPSILON))
	else:
		whole = int(ceil(total - CARRY_EPSILON))
	sect.policyCarry[key] = total - float(whole)
	return whole


static func _merge(target: Dictionary, source: Dictionary) -> void:
	for key: String in EFFECT_KEYS:
		target[key] = float(target[key]) + float(source.get(key, 0.0))


# ---------------------------------------------------------------------------
# 写操作（业务失败 → `{success:false, message}`，不抛协议错误）
# ---------------------------------------------------------------------------

static func ok_result(message: String) -> Dictionary:
	return {"success": true, "message": message}


static func fail_result(message: String) -> Dictionary:
	return {"success": false, "message": message}


## 颁行政令卡：校验通过后按颁行顺序入列。
static func enact_policy(state: GameState, config: Dictionary, sect_id: String, card_id: String) -> Dictionary:
	var sect: Sect = CityAction.find_sect(state, sect_id)
	if sect == null:
		return fail_result("宗门不存在: " + sect_id)
	var blocker: String = card_block_reason(state, config, sect, card_id)
	if not blocker.is_empty():
		return fail_result(blocker)
	var entry: Dictionary = card(config, card_id)
	sect.enactedPolicies.append(card_id)
	state.eventLog.append("[政令] %s 颁行「%s」" % [sect.name, str(entry.get("name", card_id))])
	return ok_result("已颁行「%s」" % str(entry.get("name", card_id)))


## 废除已颁政令卡（退槽，无返还）。
static func revoke_policy(state: GameState, config: Dictionary, sect_id: String, card_id: String) -> Dictionary:
	var sect: Sect = CityAction.find_sect(state, sect_id)
	if sect == null:
		return fail_result("宗门不存在: " + sect_id)
	var entry: Dictionary = card(config, card_id)
	if entry.is_empty():
		return fail_result("政令卡不存在")
	if not sect.enactedPolicies.has(card_id):
		return fail_result("「%s」尚未颁行" % str(entry.get("name", card_id)))
	sect.enactedPolicies.erase(card_id)
	state.eventLog.append("[政令] %s 废止「%s」" % [sect.name, str(entry.get("name", card_id))])
	return ok_result("已废止「%s」" % str(entry.get("name", card_id)))


## 切换政体：校验通过后更迭，并按新槽位裁剪超限的在行政令。
static func switch_government(state: GameState, config: Dictionary, sect_id: String, government_id: String) -> Dictionary:
	var sect: Sect = CityAction.find_sect(state, sect_id)
	if sect == null:
		return fail_result("宗门不存在: " + sect_id)
	var blocker: String = switch_block_reason(state, config, sect, government_id)
	if not blocker.is_empty():
		return fail_result(blocker)
	var target: Dictionary = government(config, government_id)
	var current: Dictionary = government_of(state, config, sect)
	sect.governmentId = government_id
	sect.lastPolicySwitchTurn = state.turn
	state.eventLog.append("[政令] %s 政体更迭: %s → %s" % [
		sect.name,
		"未立" if current.is_empty() else str(current.get("name", "")),
		str(target.get("name", government_id)),
	])
	var revoked: Array[String] = trim_policies_to_slots(state, config, sect)
	for card_id: String in revoked:
		var entry: Dictionary = card(config, card_id)
		state.eventLog.append("[政令] %s 政令「%s」因政体更迭而废止" % [
			sect.name, str(entry.get("name", card_id)),
		])
	var message: String = "政体已更迭为「%s」" % str(target.get("name", government_id))
	if not revoked.is_empty():
		message += ", %d项政令因槽位不足废止" % revoked.size()
	return ok_result(message)


## 政体更迭后按新槽位裁剪在行政令：保持颁行顺序，超限/失效的废止并返回其 id。
static func trim_policies_to_slots(state: GameState, config: Dictionary, sect: Sect) -> Array[String]:
	var slots: Dictionary = government_of(state, config, sect).get("slots", {})
	var kept: Array[String] = []
	var revoked: Array[String] = []
	var used: Dictionary = {}
	for card_id: String in sect.enactedPolicies:
		var entry: Dictionary = card(config, card_id)
		var category: String = str(entry.get("category", ""))
		var limit: int = int(slots.get(category, 0))
		if limit > 0 and int(used.get(category, 0)) < limit:
			used[category] = int(used.get(category, 0)) + 1
			kept.append(card_id)
		else:
			revoked.append(card_id)
	sect.enactedPolicies = kept
	return revoked


# ---------------------------------------------------------------------------
# 只读查询：`queryPolicyOptions`
# ---------------------------------------------------------------------------

static func query_policy_options(state: GameState, config: Dictionary, sect_id: String) -> Dictionary:
	var sect: Sect = CityAction.find_sect(state, sect_id)
	if sect == null:
		return {
			"sectId": sect_id,
			"enabled": enabled(config),
			"found": false,
			"governmentId": "",
			"governmentName": "",
			"switchCooldownLeft": 0,
			"eraIndex": 0,
			"effects": _zero_effects(),
			"lines": [],
			"governments": [],
			"cards": [],
		}
	var gov: Dictionary = government_of(state, config, sect)
	var governments: Array = []
	for entry: Variant in config["policy"]["governments"]:
		var item: Dictionary = entry
		var current: bool = str(item.get("id", "")) == str(gov.get("id", ""))
		var blocker: String = "" if current else switch_block_reason(state, config, sect, str(item.get("id", "")))
		governments.append({
			"id": str(item.get("id", "")),
			"name": str(item.get("name", "")),
			"description": str(item.get("description", "")),
			"current": current,
			"allowed": current or blocker.is_empty(),
			"blocker": blocker,
			"slots": (item.get("slots", {}) as Dictionary).duplicate(),
			"effectsText": effects_text(item.get("effects", {})),
		})
	var cards: Array = []
	for entry: Variant in config["policy"]["cards"]:
		var item: Dictionary = entry
		var card_id: String = str(item.get("id", ""))
		var enacted: bool = sect.enactedPolicies.has(card_id)
		var blocker: String = "" if enacted else card_block_reason(state, config, sect, card_id)
		var category: String = str(item.get("category", ""))
		cards.append({
			"id": card_id,
			"name": str(item.get("name", "")),
			"category": category,
			"categoryLabel": category_label(category),
			"description": str(item.get("description", "")),
			"unlockEra": str(item.get("unlockEra", "")),
			"enacted": enacted,
			"allowed": enacted or blocker.is_empty(),
			"blocker": blocker,
			"usedSlots": used_slots(config, sect, category),
			"effectsText": effects_text(item.get("effects", {})),
		})
	return {
		"sectId": sect.id,
		"enabled": enabled(config),
		"found": true,
		"governmentId": str(gov.get("id", "")),
		"governmentName": str(gov.get("name", "")),
		"switchCooldownLeft": switch_cooldown_left(state, config, sect),
		"eraIndex": sect_era_index(state, config, sect),
		"effects": effect_sum(state, config, sect),
		"lines": describe(state, config, sect),
		"governments": governments,
		"cards": cards,
	}


## 政令面板文本（1.0 `PolicyAction.describe`）：政体/冷却 → 槽位占用 → 每张卡的状态与原因。
static func describe(state: GameState, config: Dictionary, sect: Sect) -> Array[String]:
	var lines: Array[String] = []
	var gov: Dictionary = government_of(state, config, sect)
	if gov.is_empty():
		lines.append("政体: 未立(政令未配置)")
		return lines
	var cooldown_left: int = switch_cooldown_left(state, config, sect)
	lines.append("政体: 「%s」 %s | %s" % [
		str(gov.get("name", "")),
		effects_text(gov.get("effects", {})),
		("切换冷却中(还需%d回合)" % cooldown_left) if cooldown_left > 0 else "可切换",
	])
	var slots: Dictionary = gov.get("slots", {})
	if not slots.is_empty():
		var parts: Array[String] = []
		for category: String in slots.keys():
			parts.append("%s %d/%d" % [
				category_label(category), used_slots(config, sect, category), int(slots[category]),
			])
		lines.append("槽位: " + " | ".join(parts))
	for entry: Variant in config["policy"]["cards"]:
		var item: Dictionary = entry
		var card_id: String = str(item.get("id", ""))
		var status: String = "可颁"
		var blocker: String = card_block_reason(state, config, sect, card_id)
		if sect.enactedPolicies.has(card_id):
			status = "已颁"
			blocker = ""
		elif not blocker.is_empty():
			status = "锁定"
		lines.append("  [%s] 「%s」(%s) %s%s" % [
			status,
			str(item.get("name", "")),
			category_label(str(item.get("category", ""))),
			effects_text(item.get("effects", {})),
			"" if blocker.is_empty() else " — " + blocker,
		])
	return lines


## 效果一句话：百分比类 `产出+15%`，每回合类 `安定+0.5/回合`；全零显示「无」。
static func effects_text(effects: Dictionary) -> String:
	var parts: Array[String] = []
	for key: String in EFFECT_KEYS:
		var value: float = float(effects.get(key, 0.0))
		if is_zero_approx(value):
			continue
		var label: String = effect_label(key)
		if PERCENT_KEYS.has(key):
			parts.append("%s%+.0f%%" % [label, value * 100.0])
		else:
			parts.append("%s%+.1f/回合" % [label, value])
	return "无" if parts.is_empty() else " ".join(parts)


## 效果键中文名（裁决一：`loyalty` 语义已并入 `stabilityPerTurn`，此处只留安定）。
static func effect_label(key: String) -> String:
	match key:
		"outputBonus": return "产出"
		"spiritPowerBonus": return "灵力"
		"cultivationBonus": return "修炼"
		"combatBonus": return "战力"
		"stabilityPerTurn": return "安定"
		"prestigePerTurn": return "声望"
	return key


static func category_label(category: String) -> String:
	match category:
		"economy": return "经济"
		"military": return "军事"
		"governance": return "治理"
		"diplomacy": return "外交"
	return category


static func _zero_effects() -> Dictionary:
	var zero: Dictionary = {}
	for key: String in EFFECT_KEYS:
		zero[key] = 0.0
	return zero
