class_name ExploreRules
extends RefCounted
## 探索规则（R6）：机缘（单人）/ 秘境（多人）的成功率、冷却、奖励与伤亡。
##
## 1.0 蓝本：`action/ExploreAction.java`（`sendToJiYuan` / `exploreMiJing` / `getJiYuanInfo` /
## `getMiJingInfo` / `materialPreview` / `removeDisciple` / `addHeartDevil`）。
##
## **唯一差异（已登记 PROTOCOL §11.1 #26）**：1.0 用
## `seed ^ turn×c1 ^ MISSION_SEQ.incrementAndGet()×c2` 造一次性 `Random`，其中 `MISSION_SEQ` 是
## **JVM 静态计数器**，进程内跨对局共享 → 同种子第二局起不可复现（1.0 自己也在 `resetMissionSequence`
## 里打补丁）。2.0 一律走 `state.rng`（`RngService`），同种子 + 同指令序列逐字一致。
##
## 全部静态、无状态、只读 `config`；数值只取自 `data/gameConfig.json` 的 `explore` 节。

## `ExploreResult.rewards[].type`（1.0 `entity/Reward.RewardType` 四值，裁决二「已回填（R6）」）。
const REWARD_SPIRIT_POWER: String = "SPIRIT_POWER"
const REWARD_SPIRIT_STONES: String = "SPIRIT_STONES"
const REWARD_RARE_MATERIAL: String = "RARE_MATERIAL"
const REWARD_DAO_POINT: String = "DAO_POINT"

const KIND_JI_YUAN: String = "jiYuan"
const KIND_MI_JING: String = "miJing"


# ---------------------------------------------------------------------------
# 查找与形状
# ---------------------------------------------------------------------------

static func find_node(state: GameState, node_id: String) -> GameNode:
	return state.nodes.get(node_id, null)


## `ExploreResult` 空壳（裁决二：1.0 `entity/ExploreResult.java` 六字段原样落地）。
## `casualties` / `injured` 里放**弟子 id**（1.0 同口径），人名只出现在 `message`。
static func empty_result(message: String = "") -> Dictionary:
	return {
		"success": false,
		"message": message,
		"rewards": [],
		"casualties": [],
		"injured": [],
		"cooldown": 0,
	}


## `NodeInfo`（裁决三：1.0 `entity/NodeInfo.java` 九字段原样落地）。
## 未用到的字段留默认值（机缘 `cost` 0 / `maxParticipants` 1；秘境 `requiredRealmLevel` 0）。
static func _node_info(_state: GameState, config: Dictionary, node: GameNode, kind: String) -> Dictionary:
	var explore: Dictionary = config["explore"]
	var info: Dictionary = {
		"nodeId": node.id,
		"name": node.name,
		"type": node.type,
		"level": node.level,
		"requiredRealmLevel": 0,
		"cooldown": node.cooldown,
		"cost": 0,
		"maxParticipants": 1,
		"rewardPreview": "",
	}
	if kind == KIND_JI_YUAN:
		info["requiredRealmLevel"] = node.level * int(explore["jiYuanThresholdPerNodeLevel"])
		info["rewardPreview"] = "%s + 道统点x%d" % [
			material_preview(config, explore["jiYuanMaterials"], explore["jiYuanMaterialPerGrade"]),
			int(explore["jiYuanDaoPointReward"]),
		]
	else:
		info["cost"] = int(explore["miJingCost"])
		info["maxParticipants"] = int(explore["miJingMaxParticipants"])
		info["rewardPreview"] = "丰厚奖励: %s + 灵石x%d + 道统点x%d" % [
			material_preview(config, explore["miJingRichMaterials"], {}),
			int(explore["miJingRichSpiritStones"]),
			int(explore["miJingRichDaoPoints"]),
		]
	# `NodeInfo` 全字段来自 node + config，不需要 state；形参保留以与只读查询族签名一致。
	return info


## 奖励预览文案（1.0 `materialPreview`）：`天晶x(2+灵根品级x1)` 形式，按 config 顺序拼接。
static func material_preview(config: Dictionary, base: Dictionary, per_grade: Dictionary) -> String:
	var parts: Array[String] = []
	for material: String in base.keys():
		var amount: int = int(base[material])
		var per: int = int(per_grade.get(material, 0))
		if per > 0:
			parts.append("%sx(%d+灵根品级x%d)" % [material_label(config, material), amount, per])
		else:
			parts.append("%sx%d" % [material_label(config, material), amount])
	return "、".join(parts)


static func material_label(config: Dictionary, material: String) -> String:
	var table: Dictionary = config["resources"]["strategic"]
	var entry: Dictionary = table.get(material, {})
	return str(entry.get("displayName", material))


# ---------------------------------------------------------------------------
# 成功率（只读，供 queryJiYuanInfo / queryMiJingInfo 与实测共用）
# ---------------------------------------------------------------------------

## 机缘成功率 = `jiYuanBaseSuccessChance` + 灵根品级 × `jiYuanRootGradeBonus`
## + 宗门流 `faction.zongMen.exploreSuccessBonus`，封顶 1.0（1.0 同式）。
static func ji_yuan_success_chance(_state: GameState, config: Dictionary, disciple: Disciple, sect: Sect) -> float:
	var explore: Dictionary = config["explore"]
	var chance: float = float(explore["jiYuanBaseSuccessChance"]) \
		+ float(disciple.rootGrade) * float(explore["jiYuanRootGradeBonus"])
	if sect != null and sect.factionType == Enums.FactionType.ZONG_MEN:
		chance += float(config["faction"]["zongMen"]["exploreSuccessBonus"])
	return minf(1.0, chance)


## 秘境富裕率 = `miJingBaseRichChance` + 平均灵根品级 × `miJingRootGradeBonus`
## + (平均境界等级 − 1) × `miJingRealmBonus` + 宗门流加成，封顶 1.0（1.0 同式）。
static func mi_jing_rich_chance(_state: GameState, config: Dictionary, participants: Array, sect: Sect) -> float:
	var explore: Dictionary = config["explore"]
	if participants.is_empty():
		return 0.0
	var grade_sum: int = 0
	var realm_sum: int = 0
	for entry: Variant in participants:
		var disciple: Disciple = entry as Disciple
		grade_sum += disciple.rootGrade
		realm_sum += disciple.realmLevel
	var avg_grade: float = float(grade_sum) / float(participants.size())
	var avg_realm: float = float(realm_sum) / float(participants.size())
	var chance: float = float(explore["miJingBaseRichChance"]) \
		+ avg_grade * float(explore["miJingRootGradeBonus"]) \
		+ (avg_realm - 1.0) * float(explore["miJingRealmBonus"])
	if sect != null and sect.factionType == Enums.FactionType.ZONG_MEN:
		chance += float(config["faction"]["zongMen"]["exploreSuccessBonus"])
	return minf(1.0, chance)


# ---------------------------------------------------------------------------
# 机缘
# ---------------------------------------------------------------------------

## `sendToJiYuan`：单人探索机缘。
## 校验冷却/归属/驻守/修为 → 不在节点格则先移动（耗移动力）→ 掷骰 → 成败都进冷却。
## 返回 `ExploreResult`（裁决二）。
static func send_to_ji_yuan(state: GameState, config: Dictionary, disciple_id: String, node_id: String) -> Dictionary:
	var disciple: Disciple = MoveAction.find_disciple(state, disciple_id)
	if disciple == null:
		return empty_result("弟子不存在: " + disciple_id)
	var node: GameNode = find_node(state, node_id)
	if node == null:
		return empty_result("节点不存在: " + node_id)
	if node.type != Enums.NodeType.JI_YUAN:
		return empty_result("该节点不是机缘节点")
	if node.cooldown > 0:
		return empty_result("机缘节点冷却中, 剩余 %d 回合" % node.cooldown)
	if is_garrisoned(disciple):
		return empty_result("弟子正在驻守灵脉, 需先撤回驻守")
	var explore: Dictionary = config["explore"]
	var required_realm: int = node.level * int(explore["jiYuanThresholdPerNodeLevel"])
	if disciple.realmLevel < required_realm:
		return empty_result("修为不足: 该机缘需 %d 级修为(当前%d)" % [required_realm, disciple.realmLevel])
	if disciple.tileId != node.tileId:
		var moved: Dictionary = MoveAction.move_disciple(state, config, disciple_id, node.tileId)
		if not bool(moved["success"]) or str(moved["reachedTileId"]) != node.tileId:
			return empty_result("未能抵达机缘节点: " + str(moved["message"]))
	var sect: Sect = CityAction.find_sect(state, disciple.sectId)
	var chance: float = ji_yuan_success_chance(state, config, disciple, sect)
	var result: Dictionary = empty_result()
	# 成败都进冷却：否则同一弟子可在本回合无限重掷同一机缘节点（1.0 注释同）。
	var cooldown: int = int(explore["jiYuanCooldownTurns"])
	node.cooldown = cooldown
	result["cooldown"] = cooldown
	disciple.missionNodeId = node.id
	var success: bool = state.rng.next_float() < chance
	if success:
		var rewards: Array = result["rewards"]
		var notes: Array[String] = []
		var materials: Dictionary = sect.resources.get("materials", {}) if sect != null else {}
		for material: String in explore["jiYuanMaterials"].keys():
			var amount: int = int(explore["jiYuanMaterials"][material]) \
				+ disciple.rootGrade * int(explore["jiYuanMaterialPerGrade"].get(material, 0))
			if sect != null:
				materials[material] = int(materials.get(material, 0)) + amount
			rewards.append(_reward(REWARD_RARE_MATERIAL, amount, material))
			notes.append("%sx%d" % [material_label(config, material), amount])
		if sect != null:
			sect.resources["materials"] = materials
		var dao_points: int = int(explore["jiYuanDaoPointReward"])
		if sect != null:
			sect.resources["daoPoints"] = int(sect.resources.get("daoPoints", 0)) + dao_points
		rewards.append(_reward(REWARD_DAO_POINT, dao_points, ""))
		result["success"] = true
		result["message"] = "%s 机缘探索成功, 获得%s、道统点+%d, 节点进入冷却 %d 回合" % [
			disciple.name, "、".join(notes), dao_points, cooldown,
		]
		state.eventLog.append("[探索] %s" % str(result["message"]))
	else:
		var fall_chance: float = float(explore["jiYuanFailFallChance"])
		var injury_chance: float = float(explore["jiYuanFailInjuryChance"])
		var roll: float = state.rng.next_float()
		var devil: int = int(config["disciple"]["heartDevil"]["exploreFailBonus"])
		if roll < fall_chance:
			(result["casualties"] as Array).append(disciple.id)
			result["message"] = "%s 机缘探索失败, 弟子陨落" % disciple.name
			state.eventLog.append("[探索] %s" % str(result["message"]))
			remove_disciple(state, disciple)
		elif roll < fall_chance + injury_chance:
			disciple.injured = true
			disciple.movePoints = 0
			(result["injured"] as Array).append(disciple.id)
			add_heart_devil(config, disciple, devil)
			result["message"] = "%s 机缘探索失败, 弟子重伤, 心魔+%d" % [disciple.name, devil]
			state.eventLog.append("[探索] %s" % str(result["message"]))
		else:
			add_heart_devil(config, disciple, devil)
			result["message"] = "%s 机缘探索失败, 一无所获, 心魔+%d" % [disciple.name, devil]
			state.eventLog.append("[探索] %s" % str(result["message"]))
	disciple.missionNodeId = ""
	return result


# ---------------------------------------------------------------------------
# 秘境
# ---------------------------------------------------------------------------

## `exploreMiJing`：多人探索秘境（≤ `miJingMaxParticipants`）。
## 校验冷却/人数/同宗/全员已在节点格（**不自动移动**，1.0 同口径）/灵石 →
## **先扣灵石与冷却**再掷骰 → 富裕 / 遇险（逐人伤亡）/ 一无所获。
static func explore_mi_jing(state: GameState, config: Dictionary, disciple_ids: Array, node_id: String) -> Dictionary:
	var node: GameNode = find_node(state, node_id)
	if node == null:
		return empty_result("节点不存在: " + node_id)
	if node.type != Enums.NodeType.MI_JING:
		return empty_result("该节点不是秘境节点")
	if node.cooldown > 0:
		return empty_result("秘境冷却中, 剩余 %d 回合" % node.cooldown)
	if disciple_ids.is_empty():
		return empty_result("未指定探索弟子")
	var explore: Dictionary = config["explore"]
	var max_participants: int = int(explore["miJingMaxParticipants"])
	if disciple_ids.size() > max_participants:
		return empty_result("参与人数超限: 最多 %d 人" % max_participants)
	var participants: Array = []
	for entry: Variant in disciple_ids:
		var disciple: Disciple = MoveAction.find_disciple(state, str(entry))
		if disciple == null:
			return empty_result("弟子不存在: " + str(entry))
		if is_garrisoned(disciple):
			return empty_result("%s 正在驻守灵脉, 需先撤回驻守" % disciple.name)
		participants.append(disciple)
	var sect_id: String = (participants[0] as Disciple).sectId
	for entry: Variant in participants:
		var disciple: Disciple = entry as Disciple
		if disciple.sectId != sect_id:
			return empty_result("探索弟子必须同属一个宗门")
	for entry: Variant in participants:
		var disciple: Disciple = entry as Disciple
		if disciple.tileId != node.tileId:
			return empty_result("%s 不在秘境所在地块, 需先移动至 %s" % [disciple.name, node.tileId])
	var sect: Sect = CityAction.find_sect(state, sect_id)
	if sect == null:
		return empty_result("弟子宗门不存在")
	var cost: int = int(explore["miJingCost"])
	var stones: int = int(sect.resources.get("spiritStones", 0))
	if stones < cost:
		return empty_result("灵石不足: 探索秘境需 %d 灵石" % cost)
	sect.resources["spiritStones"] = stones - cost
	# 成功探索秘境计数（`boost_first_mijing` 条件，R4 起一直为 0 的缺口在此补上）。
	sect.miJingExploredTotal += 1
	var rich_chance: float = mi_jing_rich_chance(state, config, participants, sect)
	var cooldown: int = int(explore["miJingCooldownTurns"])
	node.cooldown = cooldown
	var result: Dictionary = empty_result()
	result["cooldown"] = cooldown
	for entry: Variant in participants:
		(entry as Disciple).missionNodeId = node.id
	var roll: float = state.rng.next_float()
	if roll < rich_chance:
		var rewards: Array = result["rewards"]
		var notes: Array[String] = []
		var materials: Dictionary = sect.resources.get("materials", {})
		for material: String in explore["miJingRichMaterials"].keys():
			var amount: int = int(explore["miJingRichMaterials"][material])
			materials[material] = int(materials.get(material, 0)) + amount
			rewards.append(_reward(REWARD_RARE_MATERIAL, amount, material))
			notes.append("%sx%d" % [material_label(config, material), amount])
		sect.resources["materials"] = materials
		var rich_stones: int = int(explore["miJingRichSpiritStones"])
		var rich_points: int = int(explore["miJingRichDaoPoints"])
		sect.resources["spiritStones"] = int(sect.resources.get("spiritStones", 0)) + rich_stones
		sect.resources["daoPoints"] = int(sect.resources.get("daoPoints", 0)) + rich_points
		rewards.append(_reward(REWARD_SPIRIT_STONES, rich_stones, ""))
		rewards.append(_reward(REWARD_DAO_POINT, rich_points, ""))
		result["success"] = true
		result["message"] = "秘境探索大获成功: 获得 %s, 灵石+%d, 道统点+%d, 秘境进入冷却 %d 回合" % [
			"、".join(notes), rich_stones, rich_points, cooldown,
		]
		state.eventLog.append("[探索] %s" % str(result["message"]))
	elif roll < rich_chance + float(explore["miJingDisasterChance"]):
		var fall_chance: float = float(explore["miJingFallChance"])
		var injury_chance: float = float(explore["miJingInjuryChance"])
		var devil: int = int(config["disciple"]["heartDevil"]["exploreFailBonus"])
		var dead: Array[Disciple] = []
		for entry: Variant in participants:
			var disciple: Disciple = entry as Disciple
			var bad: float = state.rng.next_float()
			if bad < fall_chance:
				(result["casualties"] as Array).append(disciple.id)
				dead.append(disciple)
			elif bad < fall_chance + injury_chance:
				disciple.injured = true
				disciple.movePoints = 0
				(result["injured"] as Array).append(disciple.id)
				add_heart_devil(config, disciple, devil)
			else:
				add_heart_devil(config, disciple, devil)
		# 先算完所有人的骰，再统一移除陨落者（保持骰序与 1.0 一致，且避免边遍历边改容器）。
		for disciple: Disciple in dead:
			remove_disciple(state, disciple)
		result["message"] = "秘境探索遇险, 弟子伤亡, 幸存者心魔+%d" % devil
		state.eventLog.append("[探索] %s" % str(result["message"]))
	else:
		result["message"] = "秘境探索一无所获"
		state.eventLog.append("[探索] %s" % str(result["message"]))
	for entry: Variant in participants:
		(entry as Disciple).missionNodeId = ""
	return result


# ---------------------------------------------------------------------------
# 只读查询
# ---------------------------------------------------------------------------

## `queryJiYuanInfo`：`{nodeId, kind:"jiYuan", found, info:NodeInfo}`。
static func query_ji_yuan_info(state: GameState, config: Dictionary, node_id: String) -> Dictionary:
	var node: GameNode = find_node(state, node_id)
	if node == null or node.type != Enums.NodeType.JI_YUAN:
		return {"nodeId": node_id, "kind": KIND_JI_YUAN, "found": false, "info": null}
	return {"nodeId": node.id, "kind": KIND_JI_YUAN, "found": true, "info": _node_info(state, config, node, KIND_JI_YUAN)}


## `queryMiJingInfo`：`{nodeId, kind:"miJing", found, info:NodeInfo}`。
static func query_mi_jing_info(state: GameState, config: Dictionary, node_id: String) -> Dictionary:
	var node: GameNode = find_node(state, node_id)
	if node == null or node.type != Enums.NodeType.MI_JING:
		return {"nodeId": node_id, "kind": KIND_MI_JING, "found": false, "info": null}
	return {"nodeId": node.id, "kind": KIND_MI_JING, "found": true, "info": _node_info(state, config, node, KIND_MI_JING)}


# ---------------------------------------------------------------------------
# 内部工具
# ---------------------------------------------------------------------------

static func _reward(reward_type: String, amount: int, material_id: String) -> Dictionary:
	return {"type": reward_type, "amount": amount, "materialId": material_id}


## 驻守中的弟子不能出任务（1.0 `isGarrisoned`）。R5 起驻守落在 `Disciple.garrisonNodeId`。
static func is_garrisoned(disciple: Disciple) -> bool:
	return not disciple.garrisonNodeId.is_empty()


## 心魔叠加（封顶 `disciple.heartDevil.max`，下限 0）。
static func add_heart_devil(config: Dictionary, disciple: Disciple, amount: int) -> void:
	var cap: int = int(config["disciple"]["heartDevil"]["max"])
	disciple.heartDevil = mini(cap, maxi(0, disciple.heartDevil + amount))


## 弟子陨落：出宗 + 清驻守/任务 + 清峰主（1.0 `removeDisciple`；2.0 血脉结算归 R7）。
static func remove_disciple(state: GameState, disciple: Disciple) -> void:
	var sect: Sect = CityAction.find_sect(state, disciple.sectId)
	if sect != null:
		sect.disciples.erase(disciple)
	for node: GameNode in state.nodes.values():
		node.garrisonDiscipleIds.erase(disciple.id)
	for owner: Sect in state.sects:
		for peak: SpiritPeak in owner.spiritPeaks:
			if peak.fengZhuId == disciple.id:
				peak.fengZhuId = ""
	disciple.garrisonNodeId = ""
	disciple.missionNodeId = ""
