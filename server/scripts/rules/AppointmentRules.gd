class_name AppointmentRules
extends RefCounted
## 任命规则：峰主 / 长老 / 宗主（对齐 1.0 `action/AppointmentAction`）。
##
## **本类是任命加成的唯一来源**：`appointment.*` 八键的消费点全在这里暴露成查询函数，
## 由 `EconomyRules` / `DiscipleRules` 调用，避免「任命了但加成没接线」。
##
## 三条加成的落地口径（严格照 1.0 `EconomyCalculator`）：
## 1. 峰主：**必须驻留在所辖灵峰**才生效（`fengZhuQiYunBonus` 气运 +5 / `fengZhuSpiritPowerBonus` ×1.3）；
##    外出即失效，故判定函数是 `feng_zhu_present`。
## 2. 长老：全局生效（`zhangLaoCultivationBonus` 修炼 / `zhangLaoResearchSpeedBonus` 研究），
##    后者 R4 已在 `DaoRules.research_turns` 消费，本类只补修炼那一半。
## 3. 宗主：**坐镇首都 + 宗主大殿建成**才生效（`zongZhuDaDianQiYunBonus` 气运 +10 /
##    `zongZhuDaDianSpiritPowerBonus` 灵力 ×1.2），外出失效——即 R2 留的「宗主外出」TODO。
##
## 返回形状（裁决二，已回 1.0 `entity/AppointmentResult.java` 与 `bridge/CommandDispatcher.java`
## 的 `toResult(AppointmentResult)` 逐字段核对）：**只有 `{success, message}` 两个字段**，
## 1.0 原文没有 `discipleId`/`position`/`peakId`，故**不得**添加。

const POSITION_ORDER: Array[String] = [
	Enums.Position.ZA_YI, Enums.Position.WAI_MEN, Enums.Position.NEI_MEN, Enums.Position.QIN_CHUAN,
]


# ---------------------------------------------------------------------------
# 结果构造
# ---------------------------------------------------------------------------

## 1.0 `AppointmentResult.ok(message)`：`{success: true, message}`。
static func ok(message: String) -> Dictionary:
	return {"success": true, "message": message}


## 1.0 `AppointmentResult.fail(message)`：`{success: false, message}`。
static func fail(message: String) -> Dictionary:
	return {"success": false, "message": message}


# ---------------------------------------------------------------------------
# 门控
# ---------------------------------------------------------------------------

## 可任命原因判定（1.0 `canAppoint`）：返回 blocker 文本，可任命返回空串。
## 只查「境界」与「晋升等待回合」两条通用门槛，具体岗位的额外条件在各 `appoint_*` 里查。
static func can_appoint(config: Dictionary, disciple: Disciple, position: String) -> String:
	if disciple == null:
		return "弟子不存在"
	if not Enums.Position.ALL.has(position):
		return "目标岗位无效"
	var min_realm: String = str(Enums.Position.MIN_REALM.get(position, Enums.Realm.LIAN_QI))
	if disciple.realmLevel < Disciple.level_of(min_realm):
		return "修为不足: %s需%s境界(当前%s)" % [
			_position_name(position), _realm_name(min_realm), _realm_name(disciple.realm),
		]
	# 内门/亲传还要求入宗满 `promotionWaitTurns`（1.0 `canAppoint` 同条件）。
	if position == Enums.Position.NEI_MEN or position == Enums.Position.QIN_CHUAN:
		var wait_turns: int = int(config["disciple"]["promotionWaitTurns"])
		if disciple.turnsInSect < wait_turns:
			return "入宗未满%d回合, 不能晋升%s" % [wait_turns, _position_name(position)]
	return ""


## 长老名额上限 = `zhangLaoBaseLimit` + `powerLevel` × `zhangLaoPerPowerLevel`。
## `powerLevel` 是派生缓存，调用前须由 `VictoryRules.refresh_power_level` 刷新（1.0 同序）。
static func zhang_lao_limit(config: Dictionary, sect: Sect) -> int:
	var appt: Dictionary = config["appointment"]
	return int(appt["zhangLaoBaseLimit"]) + sect.powerLevel * int(appt["zhangLaoPerPowerLevel"])


## 某岗位当前人数。
static func count_position(sect: Sect, position: String) -> int:
	var count: int = 0
	for disciple: Disciple in sect.disciples:
		if disciple.position == position:
			count += 1
	return count


# ---------------------------------------------------------------------------
# 峰主
# ---------------------------------------------------------------------------

## 任命峰主（1.0 `appointFengZhu`）。`peak.fengZhuId` 是该峰峰主的唯一真源，
## 弟子的 `position` 同步为 `FENG_ZHU`；原峰主降为亲传（非峰主岗位的兼任者只解绑不降级）。
static func appoint_feng_zhu(state: GameState, config: Dictionary, disciple_id: String, peak_id: String) -> Dictionary:
	var disciple: Disciple = CityAction.find_disciple(state, disciple_id)
	if disciple == null:
		return fail("弟子不存在: " + disciple_id)
	var peak: SpiritPeak = CityAction.find_peak(state, peak_id)
	if peak == null:
		return fail("灵峰不存在: " + peak_id)
	if peak.sectId != disciple.sectId:
		return fail("弟子不属于该灵峰所在宗门")
	var reason: String = can_appoint(config, disciple, Enums.Position.FENG_ZHU)
	if not reason.is_empty():
		return fail(reason)
	if disciple.position == Enums.Position.FENG_ZHU and disciple_id == peak.fengZhuId:
		return fail("%s 已是%s峰主" % [disciple.name, peak.name])
	var sect: Sect = CityAction.find_sect(state, disciple.sectId)
	if sect == null:
		return fail("宗门不存在")

	var extra: String = ""
	# 原峰主处理：峰主降为亲传；其他岗位兼任者只解除兼任（1.0 同分支）。
	var old_id: String = peak.fengZhuId
	if not old_id.is_empty() and old_id != disciple_id:
		var old_feng_zhu: Disciple = CityAction.find_disciple(state, old_id)
		if old_feng_zhu != null:
			if old_feng_zhu.position == Enums.Position.FENG_ZHU:
				old_feng_zhu.position = Enums.Position.QIN_CHUAN
				extra += "原峰主%s降为亲传; " % old_feng_zhu.name
			else:
				extra += "解除%s(%s)兼任峰主; " % [old_feng_zhu.name, _position_name(old_feng_zhu.position)]
	# 弟子若原为其他灵峰峰主，解除旧绑定。
	if disciple.position == Enums.Position.FENG_ZHU:
		for other: SpiritPeak in sect.spiritPeaks:
			if other.id != peak.id and other.fengZhuId == disciple_id:
				other.fengZhuId = ""
	disciple.position = Enums.Position.FENG_ZHU
	peak.fengZhuId = disciple_id
	state.eventLog.append("[任命] %s 任 %s 峰主" % [disciple.name, peak.name])
	return ok("任命 %s 为%s峰主; %s驻留灵峰时气运与灵力产能加成生效" % [disciple.name, peak.name, extra])


## 峰主是否驻留在所辖灵峰（1.0 `isFengZhuPresent`）。**外出即失效**。
static func feng_zhu_present(state: GameState, sect: Sect, peak: SpiritPeak) -> bool:
	if sect == null or peak == null or peak.fengZhuId.is_empty():
		return false
	var feng_zhu: Disciple = CityAction.find_disciple(state, peak.fengZhuId)
	if feng_zhu == null:
		return false
	return feng_zhu.tileId == peak.tileId


# ---------------------------------------------------------------------------
# 长老
# ---------------------------------------------------------------------------

## 任命长老（1.0 `appointZhangLao`）。宗主不可兼任长老；原峰主先解绑峰主位。
static func appoint_zhang_lao(state: GameState, config: Dictionary, disciple_id: String) -> Dictionary:
	var disciple: Disciple = CityAction.find_disciple(state, disciple_id)
	if disciple == null:
		return fail("弟子不存在: " + disciple_id)
	var sect: Sect = CityAction.find_sect(state, disciple.sectId)
	if sect == null:
		return fail("弟子宗门不存在")
	var reason: String = can_appoint(config, disciple, Enums.Position.ZHANG_LAO)
	if not reason.is_empty():
		return fail(reason)
	if disciple.position == Enums.Position.ZONG_ZHU:
		return fail("宗主不可兼任长老, 请先禅让或罢免")
	if disciple.position == Enums.Position.ZHANG_LAO:
		return fail("%s 已是长老" % disciple.name)
	var limit: int = zhang_lao_limit(config, sect)
	var elders: int = count_position(sect, Enums.Position.ZHANG_LAO)
	if elders >= limit:
		return fail("长老人数已满: 上限 %d(当前%d)" % [limit, elders])
	if disciple.position == Enums.Position.FENG_ZHU:
		for peak: SpiritPeak in sect.spiritPeaks:
			if peak.fengZhuId == disciple_id:
				peak.fengZhuId = ""
	disciple.position = Enums.Position.ZHANG_LAO
	state.eventLog.append("[任命] %s 任长老(%d/%d)" % [disciple.name, elders + 1, limit])
	return ok("任命 %s 为长老(%d/%d), 全局修炼/研究加成生效" % [disciple.name, elders + 1, limit])


## 长老数带来的修炼加成（加性，1.0 `DiscipleManager` 的 `1 + elderCount × bonus`）。
static func zhang_lao_cultivation_bonus(config: Dictionary, sect: Sect) -> float:
	if sect == null:
		return 0.0
	return float(count_position(sect, Enums.Position.ZHANG_LAO)) \
		* float(config["appointment"]["zhangLaoCultivationBonus"])


# ---------------------------------------------------------------------------
# 宗主
# ---------------------------------------------------------------------------

## 任命宗主（1.0 `appointZongZhu`）。家族流须血脉族人；即位须身处首都灵峰；
## 原宗主退位为长老。
static func appoint_zong_zhu(state: GameState, config: Dictionary, disciple_id: String) -> Dictionary:
	var disciple: Disciple = CityAction.find_disciple(state, disciple_id)
	if disciple == null:
		return fail("弟子不存在: " + disciple_id)
	var sect: Sect = CityAction.find_sect(state, disciple.sectId)
	if sect == null:
		return fail("弟子宗门不存在")
	var reason: String = can_appoint(config, disciple, Enums.Position.ZONG_ZHU)
	if not reason.is_empty():
		return fail(reason)
	if disciple.position == Enums.Position.ZONG_ZHU:
		return fail("%s 已是宗主" % disciple.name)
	if sect.factionType == Enums.FactionType.JIA_ZU and not disciple.bloodLine:
		return fail("家族流宗主须为血脉族人")
	var capital: SpiritPeak = capital_peak_of(sect)
	if capital == null:
		return fail("宗门没有首都灵峰")
	if disciple.tileId != capital.tileId:
		return fail("宗主即位需身处首都灵峰" + capital.name)

	var extra: String = ""
	var old: Disciple = null
	for other: Disciple in sect.disciples:
		if other.position == Enums.Position.ZONG_ZHU:
			old = other
			break
	if old != null and old.id != disciple_id:
		old.position = Enums.Position.ZHANG_LAO
		extra = "原宗主%s退位为长老; " % old.name
	disciple.position = Enums.Position.ZONG_ZHU
	state.eventLog.append("[任命] %s 继任宗主" % disciple.name)
	return ok(extra + "任命 %s 为宗主, 驻留首都时宗主大殿全局加成生效" % disciple.name)


## 宗主是否坐镇首都且宗主大殿已建成（1.0 `isZongZhuAtCapitalWithHall`）。
## **外出即失效**——这就是 R2 留的「宗主外出」TODO 的判定入口。
static func zong_zhu_outside_bonus_active(state: GameState, _config: Dictionary, sect: Sect) -> bool:
	if sect == null:
		return false
	var zong_zhu: Disciple = null
	for disciple: Disciple in sect.disciples:
		if disciple.position == Enums.Position.ZONG_ZHU:
			zong_zhu = disciple
			break
	if zong_zhu == null:
		return false
	var capital: SpiritPeak = capital_peak_of(sect)
	if capital == null or capital.tileId != zong_zhu.tileId:
		return false
	return capital.buildings.has(Enums.Building.ZONG_ZHU_DA_DIAN)


## 宗主大殿气运加成（1.0 `calculateQiYun`：首都 +10）。
static func zong_zhu_qi_yun_bonus(state: GameState, config: Dictionary, sect: Sect) -> int:
	if not zong_zhu_outside_bonus_active(state, config, sect):
		return 0
	return int(config["appointment"]["zongZhuDaDianQiYunBonus"])


## 宗主大殿灵力乘区（1.0 `calculateSpiritPowerIncome`：宗级 `total *= 1.2`）。
static func zong_zhu_spirit_multiplier(state: GameState, config: Dictionary, sect: Sect) -> float:
	if not zong_zhu_outside_bonus_active(state, config, sect):
		return 1.0
	return 1.0 + float(config["appointment"]["zongZhuDaDianSpiritPowerBonus"])


# ---------------------------------------------------------------------------
# 罢免 / 晋升
# ---------------------------------------------------------------------------

## 罢免岗位（1.0 `dismissPosition`）：降为亲传；峰主同时解绑 `fengZhuId`。
## 本里程碑无 `dismiss` 命令（69 条里没有），仅供 AI 与内部结算调用。
static func dismiss_position(state: GameState, disciple_id: String) -> Dictionary:
	var disciple: Disciple = CityAction.find_disciple(state, disciple_id)
	if disciple == null:
		return fail("弟子不存在: " + disciple_id)
	var position: String = disciple.position
	if position != Enums.Position.FENG_ZHU and position != Enums.Position.ZHANG_LAO \
			and position != Enums.Position.ZONG_ZHU:
		return fail("%s 无可罢免职位(当前%s)" % [disciple.name, _position_name(position)])
	if position == Enums.Position.FENG_ZHU:
		var sect: Sect = CityAction.find_sect(state, disciple.sectId)
		if sect != null:
			for peak: SpiritPeak in sect.spiritPeaks:
				if peak.fengZhuId == disciple_id:
					peak.fengZhuId = ""
	disciple.position = Enums.Position.QIN_CHUAN
	var extra: String = ", 宗门暂无宗主" if position == Enums.Position.ZONG_ZHU else ""
	return ok("%s 被罢免%s, 降为亲传%s" % [disciple.name, _position_name(position), extra])


## 逐级晋升（1.0 `promoteDisciple`）：仅 杂役→外门→内门→亲传。
static func promote_disciple(state: GameState, config: Dictionary, disciple_id: String, target: String) -> Dictionary:
	var disciple: Disciple = CityAction.find_disciple(state, disciple_id)
	if disciple == null:
		return fail("弟子不存在: " + disciple_id)
	if not POSITION_ORDER.has(target):
		return fail("晋升目标仅支持 杂役/外门/内门/亲传")
	var reason: String = can_appoint(config, disciple, target)
	if not reason.is_empty():
		return fail(reason)
	var current_index: int = POSITION_ORDER.find(disciple.position)
	if current_index < 0:
		return fail("当前岗位%s不可晋升, 需先罢免职位" % _position_name(disciple.position))
	if current_index == POSITION_ORDER.size() - 1:
		return fail("%s 已是最高晋升岗位" % disciple.name)
	if POSITION_ORDER.find(target) != current_index + 1:
		return fail("需逐级晋升: 当前%s只能晋升为%s" % [
			_position_name(disciple.position), _position_name(POSITION_ORDER[current_index + 1]),
		])
	var old: String = disciple.position
	disciple.position = target
	return ok("%s 由%s晋升为%s" % [disciple.name, _position_name(old), _position_name(target)])


# ---------------------------------------------------------------------------
# 辅助
# ---------------------------------------------------------------------------

## 首都灵峰：优先 `capital=true`，其次首座（1.0 `strictCapitalPeak` 的宽松版，
## 2.0 的 `SpiritPeak.capital` 是显式标志，无需回退猜等级）。
static func capital_peak_of(sect: Sect) -> SpiritPeak:
	if sect == null:
		return null
	for peak: SpiritPeak in sect.spiritPeaks:
		if peak.capital:
			return peak
	return null


static func _position_name(position: String) -> String:
	return str(Enums.Position.NAMES.get(position, position))


static func _realm_name(realm: String) -> String:
	return str(Enums.Realm.NAMES.get(realm, realm))
