class_name ConfigValidator
extends RefCounted

const FORBIDDEN_BLOCKS: Array[String] = ["diplomacy", "threat", "event", "disaster", "loyalty", "strategy"]
const REQUIRED_BLOCKS: Array[String] = ["map", "disciple", "spiritPeak", "economy", "resources", "combat", "building", "explore", "appointment", "ai", "faction", "victory", "qiYun", "powerLevel", "daoTree", "vision", "warfare", "city", "improvement", "policy", "road", "teleport", "automation", "speed", "difficulty"]
const NUMERIC_PATHS: Array[String] = [
	"map.defaultWidth", "map.defaultHeight", "map.dangerTileChance", "map.dangerTileMoveCost",
	"disciple.baseMovePoints", "disciple.recruitmentBaseInterval", "disciple.promotionWaitTurns", "disciple.injuryRecoveryChance",
	"spiritPeak.baseDiscipleCapacity", "spiritPeak.capacityPerLevel", "spiritPeak.baseQiYunMax", "spiritPeak.baseDefense", "spiritPeak.maxLevel", "spiritPeak.foundTurns", "spiritPeak.spreadPenaltyPerPeak",
	"resources.initial.spiritPower", "resources.initial.spiritStones", "resources.initial.workPower", "resources.initial.prestige", "resources.luxurySpawnChance",
	"economy.lingTianBaseOutput", "economy.lingMaiBaseOutput", "economy.lingQuanBaseOutput", "economy.lingMaiTotalReserveBase",
	"vision.peakVision", "vision.nodeVision", "warfare.attacksPerTurn", "warfare.highGroundBonus", "warfare.riverCrossPenalty",
	"city.startPopulation", "city.housingBase", "city.housingPerPeakLevel", "city.stabilityBase", "city.stabilityMax", "city.workRadius",
	"policy.switchCooldownTurns", "daoTree.cangJingGePointsPerTurn", "improvement.builderCharges",
	"combat.baseWinChance", "combat.powerRatioThreshold", "combat.realmPowerWeight", "combat.rootGradePowerWeight",
	"victory.maxTurns", "teleport.baseStones", "road.stepCostReduction", "automation.maxActionsPerTurn", "speed.animationScale"
]
const SETUP_NUMBERS: Array[String] = ["sectCount", "safeRadius", "maxWidth", "maxHeight", "maxTiles", "peakLevel", "peakQiYun", "nodeLevel", "rootGrade", "rootCount", "outerCount", "generation"]
const DAO_EFFECTS: Array[String] = ["CULTIVATION_BONUS", "ECONOMY_BONUS", "COMBAT_BONUS", "MOVE_BONUS", "VISION_BONUS", "RESEARCH_BONUS", "UNLOCK_IMPROVEMENT", "UNLOCK_BUILDING", "UNLOCK_UNIT", "UNLOCK_DISTRICT", "UNLOCK_TELEPORT", "UNLOCK_POLICY"]
## 开局数值的合法下界：0 不是有效安全半径/宽高，必须拒绝，而不是静默放行。
const SETUP_MINIMUMS: Dictionary = {"sectCount": 1, "safeRadius": 1, "maxWidth": 2, "maxHeight": 2, "maxTiles": 1, "peakLevel": 1, "peakQiYun": 0, "nodeLevel": 1, "rootGrade": 1, "rootCount": 1, "outerCount": 1, "generation": 1}
## 每个可生成节点的地形偏好块必须显式声明这些限制键；缺项等于悄悄放宽生成限制。
const NODE_SPAWN_REQUIRED_KEYS: Dictionary = {"LING_TIAN": ["baseTerrains", "reliefs", "danger"], "LING_MAI": ["reliefs", "danger"], "JI_YUAN": ["danger"], "MI_JING": ["danger"], "LING_QUAN": ["riverRequired", "danger"]}

static func validate(config: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	for block: String in REQUIRED_BLOCKS: _require(config, block, TYPE_DICTIONARY, errors)
	for key: String in ["schemaVersion", "saveVersion"]:
		_require(config, key, TYPE_STRING, errors)
		if config.get(key) != Msg.SAVE_VERSION: errors.append("%s 必须为 3.0" % key)
	_scan(config, "", errors)
	for path: String in NUMERIC_PATHS: _number(config, path, errors)
	for key: String in ["map.baseTerrains", "map.relief", "map.features", "map.river", "map.nodeSpawnByTerrain", "map.luxuryByTerrain", "map.strategicByTerrain", "map.setup", "resources.initial.materials", "resources.initial.luxuries", "vision.discipleVisionByRealm", "warfare.unitClasses", "difficulty.levels", "improvement.byType", "faction.flavors"]: _require(config, key, TYPE_DICTIONARY, errors)
	_require(config, "vision.enabled", TYPE_BOOL, errors)
	_require(config, "difficulty.defaultLevel", TYPE_STRING, errors)
	_require(config, "map.baseTerrainAlgorithm", TYPE_STRING, errors)
	_enum_value(config, "map.baseTerrainAlgorithm", Enums.BaseTerrainAlgorithm.ALL, errors)
	for key: String in SETUP_NUMBERS: _number(config, "map.setup." + key, errors, true)
	for key: String in SETUP_MINIMUMS:
		var setup_value: Variant = _lookup(config, "map.setup." + key)
		if _is_number(setup_value) and float(setup_value) < float(SETUP_MINIMUMS[key]): errors.append("开局数值越界 `map.setup.%s`（下界 %s）" % [key, str(SETUP_MINIMUMS[key])])
	for key: String in ["source", "leaderRealm", "outerRealm", "leaderPosition", "outerPosition", "unitClass"]: _require(config, "map.setup." + key, TYPE_STRING, errors)
	for key: String in ["rootTypes", "aiFactions", "aiNames"]: _require(config, "map.setup." + key, TYPE_ARRAY, errors)
	_require(config, "map.setup.rootMoveBonus", TYPE_DICTIONARY, errors)
	_enum_value(config, "map.setup.leaderRealm", Enums.Realm.ALL, errors)
	_enum_value(config, "map.setup.outerRealm", Enums.Realm.ALL, errors)
	_enum_value(config, "map.setup.leaderPosition", Enums.Position.ALL, errors)
	_enum_value(config, "map.setup.outerPosition", Enums.Position.ALL, errors)
	_enum_value(config, "map.setup.unitClass", Enums.UnitClass.ALL, errors)
	_enum_value(config, "difficulty.defaultLevel", Enums.Difficulty.ALL, errors)
	for root: String in Enums.SpiritRootType.ALL: _number(config, "map.setup.rootMoveBonus." + root, errors, true, true)
	for material: String in Enums.ResourceKind.MATERIALS:
		_number(config, "resources.initial.materials." + material, errors, true)
		_require(config, "resources.strategic." + material, TYPE_DICTIONARY, errors)
	for luxury: String in Enums.ResourceKind.LUXURIES:
		_require(config, "resources.luxuryTypes." + luxury, TYPE_DICTIONARY, errors)
		_require(config, "map.luxuryByTerrain." + luxury, TYPE_DICTIONARY, errors)
	for base: String in Enums.BaseTerrain.ALL:
		for resource: String in ["food", "spiritPower", "spiritStones"]: _number(config, "map.baseTerrains." + base + "." + resource, errors)
	var ratio_sum: float = 0.0
	for relief: String in Enums.Relief.ALL:
		for field: String in ["height", "ratio", "moveCost", "defenseBonus", "visionBonus"]: _number(config, "map.relief." + relief + "." + field, errors)
		_require(config, "map.relief." + relief + ".passable", TYPE_BOOL, errors)
		# 海拔产出加成（PRD §4.1.9 L315「丘陵石+1」）；平地/山岳为空表
		_require(config, "map.relief." + relief + ".yield", TYPE_DICTIONARY, errors)
		for resource: String in ["food", "spiritPower", "spiritStones", "daoPoints", "qiYun"]:
			if _lookup(config, "map.relief." + relief + ".yield") != null and (_lookup(config, "map.relief." + relief + ".yield") as Dictionary).has(resource):
				_number(config, "map.relief." + relief + ".yield." + resource, errors)
		var ratio: Variant = _lookup(config, "map.relief." + relief + ".ratio")
		if _is_number(ratio):
			ratio_sum += float(ratio)
			if float(ratio) > 1.0: errors.append("海拔比例超过1")
		var height: Variant = _lookup(config, "map.relief." + relief + ".height")
		if _is_number(height) and float(height) <= 0.0: errors.append("海拔柱高必须为正数")
	if not is_equal_approx(ratio_sum, 1.0): errors.append("海拔比例之和必须为1")
	for feature: String in Enums.Feature.ALL:
		for field: String in ["chance", "moveExtra", "defenseBonus"]: _number(config, "map.features." + feature + "." + field, errors, false, field == "defenseBonus")
		_require(config, "map.features." + feature + ".reliefs", TYPE_ARRAY, errors)
		_require(config, "map.features." + feature + ".yield", TYPE_DICTIONARY, errors)
		_require(config, "map.features." + feature + ".clearYield", TYPE_DICTIONARY, errors)
	for node: String in Enums.NodeType.SPAWN:
		var node_prefix: String = "map.nodeSpawnByTerrain." + node
		_require(config, node_prefix, TYPE_DICTIONARY, errors)
		for field: String in NODE_SPAWN_REQUIRED_KEYS[node]:
			if _lookup(config, node_prefix + "." + field) == null: errors.append("节点地形偏好缺关键限制 `%s.%s`" % [node_prefix, field])
	for key: String in Enums.NodeType.CHANCE_KEYS: _number(config, "map.nodeSpawnChance." + key, errors)
	for field: String in ["sourcesMin", "sourcesMax", "sourceEdgesMin", "sourceEdgesMax", "moveExtra", "foodBonus", "crossPenalty", "edgeRatioMin", "edgeRatioMax"]: _number(config, "map.river." + field, errors)
	_check_range(config, "map.river.sourcesMin", "map.river.sourcesMax", 1, 2, errors)
	_check_range(config, "map.river.sourceEdgesMin", "map.river.sourceEdgesMax", 1, 2, errors)
	_check_range(config, "map.river.edgeRatioMin", "map.river.edgeRatioMax", 0.0, 1.0, errors)
	_check_range(config, "map.defaultWidth", "map.setup.maxWidth", 2, 128, errors)
	_check_range(config, "map.defaultHeight", "map.setup.maxHeight", 2, 128, errors)
	for realm: String in Enums.Realm.ALL:
		_number(config, "vision.discipleVisionByRealm." + realm, errors, true)
		_number(config, "map.setup.realmMoveBonus." + realm, errors, true)
	for faction: String in Enums.FactionType.ALL: _require(config, "faction.flavors." + faction, TYPE_DICTIONARY, errors)
	# 三流派特性数值（`FactionRules` 读取；PRD §1.1）。已落地 6 项做类型校验，
	# 其余键属 R5/R6/R7 或 PRD 未给口径（见 PROTOCOL §11.2 #11），此处不臆造校验。
	for key: String in ["faction.zongMen.buildSpeedBonus", "faction.zongMen.subPeakCostReduction", "faction.zongMen.researchSpeedBonus", "faction.zongMen.qiYunBonus", "faction.jiaZu.peakBuildCostPenalty", "faction.jiaZu.bloodLineSpeedBonus", "faction.jiaZu.zuCiCultivationBonus", "faction.jiaZu.bloodDaoCostReduction"]:
		_number(config, key, errors)
	_number(config, "faction.zongMen.uniqueBuildingDefenseBonus", errors, true)
	for difficulty: String in Enums.Difficulty.ALL:
		_require(config, "difficulty.levels." + difficulty + ".name", TYPE_STRING, errors)
		for field: String in ["aiActionPoints", "aiStartStonesBonus", "aiStartWorkPowerBonus", "aiAggressionMultiplier", "aiExpansionMultiplier", "playerStartStonesBonus"]: _number(config, "difficulty.levels." + difficulty + "." + field, errors)
	for unit: String in Enums.UnitClass.ALL:
		var prefix: String = "warfare.unitClasses." + unit + "."
		_require(config, prefix + "displayName", TYPE_STRING, errors)
		_enum_value(config, prefix + "kind", Enums.UnitClass.KINDS, errors)
		for field: String in ["attack", "defense", "moveBonus", "range", "siegeBonus", "retaliation", "visionBonus", "minRealmLevel", "minRootGrade", "reclassSpiritPower", "reclassSpiritStones", "reclassCooldownTurns"]: _number(config, prefix + field, errors, false, field == "moveBonus")
		_require(config, prefix + "reclassMaterials", TYPE_DICTIONARY, errors)
	var classes: Variant = _lookup(config, "warfare.unitClasses")
	if typeof(classes) == TYPE_DICTIONARY and classes.size() != 10: errors.append("必须恰好10兵种")
	_validate_rows(config, errors)
	# R4：道统树结构（5 时代 / 藏经阁道点 / 节点道点表）。分布 3-4-7-4-3 由 `R4Test` 断言。
	var eras: Variant = _lookup(config, "daoTree.eras")
	if typeof(eras) != TYPE_ARRAY or (eras as Array).size() != 5: errors.append("道统必须有5个时代")
	_number(config, "daoTree.cangJingGePointsPerTurn", errors, true)
	for key: String in ["lingMaiBase", "lingMaiPerLevel", "jiYuanBase", "jiYuanPerLevel", "miJingBase", "miJingPerLevel"]:
		_number(config, "daoTree.nodeOutput." + key, errors, true)
	var boosts: Variant = _lookup(config, "daoTree.boosts")
	if typeof(boosts) == TYPE_ARRAY:
		for boost: Variant in boosts:
			if typeof(boost) != TYPE_DICTIONARY:
				errors.append("道统成就必须对象")
				continue
			_require(boost, "id", TYPE_STRING, errors)
			_require(boost, "condition", TYPE_STRING, errors)
			for field: String in ["threshold", "points"]: _number(boost, field, errors, true)
	# R4：修炼/心魔/收徒键（数值表缺项会让结算静默失真）
	for key: String in ["baseSpeed", "rootGradeBonusPerGrade", "caveBonus", "zongMenBonus", "heartDevilPenaltyThreshold", "heartDevilPenalty", "spiritPowerCostPerTurn", "spiritPowerCostPerRealmLevel", "breakthroughFailHeartDevil", "breakthroughFailProgressRatio", "tribulationSpiritPowerCost", "tribulationSpiritStoneCost", "tribulationBaseSuccessChance", "tribulationDaoBonusPerUnlocked", "tribulationRootGradeBonusPerGrade", "tribulationFailHeartDevil", "tribulationFailFallChance"]:
		_number(config, "disciple.cultivation." + key, errors)
	for key: String in ["max", "injuryThreshold", "betrayThreshold", "overCapacityPerTurn", "injuryChance", "caveReduce", "betrayNeutralChance"]:
		_number(config, "disciple.heartDevil." + key, errors)
	for key: String in ["recruitmentBaseInterval", "promotionWaitTurns"]:
		_number(config, "disciple." + key, errors, true)
	_number(config, "disciple.injuryRecoveryChance", errors)
	for key: String in ["recruitmentCost", "recruitmentTurns", "recruitmentBaseCount", "recruitmentPerLevel", "refundRate"]:
		_number(config, "building." + key, errors)
	_number(config, "economy.accelerateStonePerTurn", errors, true)
	for realm: String in Enums.Realm.ALL:
		_number(config, "disciple.cultivation.progressCapPerRealm." + realm, errors, true)
		if realm != Enums.Realm.HUA_SHEN: _number(config, "disciple.cultivation.breakthroughChancePerRealm." + realm, errors)
	_exact_keys(config, "map.baseTerrains", Enums.BaseTerrain.ALL, errors)
	_exact_keys(config, "map.relief", Enums.Relief.ALL, errors)
	_exact_keys(config, "map.features", Enums.Feature.ALL, errors)
	_exact_keys(config, "map.nodeSpawnByTerrain", Enums.NodeType.SPAWN, errors)
	_exact_keys(config, "warfare.unitClasses", Enums.UnitClass.ALL, errors)
	_exact_keys(config, "improvement.byType", Enums.ImprovementType.ALL, errors)
	for building: String in Enums.Building.ALL:
		_number(config, "building.costs." + building, errors, true)
		_number(config, "building.turns." + building, errors, true)
	for improvement: String in Enums.ImprovementType.ALL:
		_require(config, "improvement.byType." + improvement + ".buildable", TYPE_BOOL, errors)
		_number(config, "improvement.byType." + improvement + ".cost", errors)
		_require(config, "improvement.byType." + improvement + ".yields", TYPE_DICTIONARY, errors)
		_require(config, "improvement.byType." + improvement + ".reliefs", TYPE_ARRAY, errors)
	var heights: Array[float] = []
	for relief: String in Enums.Relief.ALL:
		var value: Variant = _lookup(config, "map.relief." + relief + ".height")
		if _is_number(value): heights.append(float(value))
	if heights.size() == 3 and not (heights[0] < heights[1] and heights[1] < heights[2]): errors.append("海拔高度必须 FLAT < HILL < MOUNTAIN")
	for relief: String in Enums.Relief.ALL:
		if _lookup(config, "map.relief." + relief + ".passable") != (relief != Enums.Relief.MOUNTAIN): errors.append("山岳不可通行，平地丘陵可通行")
	for feature: String in Enums.Feature.ALL:
		var allowed: Variant = _lookup(config, "map.features." + feature + ".reliefs")
		if typeof(allowed) == TYPE_ARRAY and (allowed.has(Enums.Relief.MOUNTAIN) or (feature == Enums.Feature.MIRE and allowed != [Enums.Relief.FLAT])): errors.append("地貌海拔限制非法")
	var default_width: Variant = _lookup(config, "map.defaultWidth")
	var default_height: Variant = _lookup(config, "map.defaultHeight")
	var max_tiles: Variant = _lookup(config, "map.setup.maxTiles")
	if _is_number(default_width) and _is_number(default_height) and _is_number(max_tiles):
		if float(default_width) * float(default_height) > float(max_tiles) or float(max_tiles) > 16384: errors.append("地图格数超过安全上限")
	var setup: Variant = _lookup(config, "map.setup")
	if typeof(setup) == TYPE_DICTIONARY:
		if setup.get("sectCount") != 4: errors.append("R1 必须四宗")
		if typeof(setup.get("aiNames")) == TYPE_ARRAY:
			if setup["aiNames"].size() != 3: errors.append("AI名称必须3项")
			for index: int in range(setup["aiNames"].size()):
				var ai_name: Variant = setup["aiNames"][index]
				if typeof(ai_name) != TYPE_STRING or String(ai_name).strip_edges().is_empty(): errors.append("AI名称必须是非空白字符串")
		if typeof(setup.get("aiFactions")) == TYPE_ARRAY and setup["aiFactions"].size() != 3: errors.append("AI流派必须3项")
		if _is_number(setup.get("rootGrade")) and (float(setup["rootGrade"]) < 1 or float(setup["rootGrade"]) > 5): errors.append("灵根品级越界")
		if _is_number(setup.get("rootCount")) and float(setup["rootCount"]) < 1: errors.append("灵根数量必须正数")
	return errors

static func _validate_rows(config: Dictionary, errors: Array[String]) -> void:
	for path: String in ["daoTree.daos", "daoTree.boosts", "policy.cards", "policy.governments", "warfare.promotions", "city.district.adjacency"]: _require(config, path, TYPE_ARRAY, errors)
	var daos: Variant = _lookup(config, "daoTree.daos")
	var ids: Dictionary = {}
	if typeof(daos) == TYPE_ARRAY:
		if daos.size() != 21: errors.append("必须21条道法")
		for row: Variant in daos:
			if typeof(row) != TYPE_DICTIONARY:
				errors.append("道法必须对象")
				continue
			for field: String in ["id", "name", "era"]: _require(row, field, TYPE_STRING, errors)
			for field: String in ["daoPointCost", "spiritPowerCost", "turns"]: _number(row, field, errors)
			for field: String in ["prerequisiteDaoIds", "effects"]: _require(row, field, TYPE_ARRAY, errors)
			if ids.has(row.get("id")): errors.append("重复道法ID")
			ids[row.get("id")] = true
			if row.has("factionOnly"): _enum_value(row, "factionOnly", Enums.FactionType.ALL, errors)
			if typeof(row.get("effects")) == TYPE_ARRAY:
				for effect: Variant in row["effects"]:
					if typeof(effect) == TYPE_DICTIONARY: _enum_value(effect, "type", DAO_EFFECTS, errors)
					else: errors.append("道法效果必须对象")
		for row: Variant in daos:
			if typeof(row) == TYPE_DICTIONARY and typeof(row.get("prerequisiteDaoIds")) == TYPE_ARRAY:
				for key: Variant in row["prerequisiteDaoIds"]:
					if not ids.has(key): errors.append("前置道法引用不存在")
	for path: String in ["policy.cards", "policy.governments"]:
		var rows: Variant = _lookup(config, path)
		if typeof(rows) != TYPE_ARRAY: continue
		if rows.size() != (8 if path == "policy.cards" else 3): errors.append("政策卡必须8张，政体必须3个")
		var seen: Dictionary = {}
		for row: Variant in rows:
			if typeof(row) != TYPE_DICTIONARY:
				errors.append("政令项必须对象")
				continue
			_require(row, "id", TYPE_STRING, errors)
			_require(row, "effects", TYPE_DICTIONARY, errors)
			if seen.has(row.get("id")): errors.append("重复政策ID")
			seen[row.get("id")] = true
			if path == "policy.cards": _enum_value(row, "category", ["economy", "military", "governance"], errors)
			else: _require(row, "slots", TYPE_DICTIONARY, errors)

static func _exact_keys(config: Dictionary, path: String, allowed: Array, errors: Array[String]) -> void:
	var value: Variant = _lookup(config, path)
	if typeof(value) != TYPE_DICTIONARY: return
	for key: Variant in value:
		if not allowed.has(key): errors.append("非法枚举键 `%s.%s`" % [path, str(key)])
	for key: String in allowed:
		if not value.has(key): errors.append("缺枚举项 `%s.%s`" % [path, key])

static func _lookup(config: Dictionary, path: String) -> Variant:
	var current: Variant = config
	for key: String in path.split("."):
		if typeof(current) != TYPE_DICTIONARY or not current.has(key): return null
		current = current[key]
	return current

static func _require(config: Dictionary, path: String, expected: int, errors: Array[String]) -> void:
	var value: Variant = _lookup(config, path)
	if typeof(value) != expected: errors.append("缺项或类型错误 `%s`（需要%s）" % [path, type_string(expected)])
	elif expected == TYPE_STRING and String(value).strip_edges().is_empty(): errors.append("空白字符串 `%s`" % path)

static func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT

static func _number(config: Dictionary, path: String, errors: Array[String], integer: bool = false, signed: bool = false) -> void:
	var value: Variant = _lookup(config, path)
	if not _is_number(value):
		errors.append("缺数值或类型错误 `%s`" % path)
		return
	var number: float = float(value)
	if not is_finite(number) or (not signed and number < 0) or (integer and number != floor(number)): errors.append("数值非法 `%s`" % path)

static func _enum_value(config: Dictionary, path: String, allowed: Array, errors: Array[String]) -> void:
	var value: Variant = _lookup(config, path)
	if typeof(value) != TYPE_STRING or not allowed.has(value): errors.append("枚举非法 `%s`" % path)

static func _check_range(config: Dictionary, low_path: String, high_path: String, minimum: float, maximum: float, errors: Array[String]) -> void:
	var low: Variant = _lookup(config, low_path)
	var high: Variant = _lookup(config, high_path)
	if _is_number(low) and _is_number(high):
		if float(low) < minimum or float(high) > maximum or float(low) > float(high): errors.append("配置范围非法 %s / %s" % [low_path, high_path])

static func _scan(value: Variant, path: String, errors: Array[String]) -> void:
	if typeof(value) == TYPE_DICTIONARY:
		for key: Variant in value:
			if typeof(key) != TYPE_STRING:
				errors.append("配置键必须字符串")
				continue
			var field: String = key
			var lower: String = field.to_lower()
			var child: String = field if path.is_empty() else path + "." + field
			if FORBIDDEN_BLOCKS.has(field) or "diplomacy" in lower or "weariness" in lower or "loyalty" in lower or "rebel" in lower: errors.append("裁剪字段不得存在 `%s`" % child)
			var allowed: Array = []
			if field in ["danger", "riverRequired", "enabled", "passable", "buildable", "requiresBloodLine"] and typeof(value[key]) != TYPE_BOOL: errors.append("布尔类型非法 `%s`" % child)
			if field in ["baseTerrains", "reliefs", "rootTypes", "aiFactions", "nodeTypes", "aiNames", "prerequisiteDaoIds"] and typeof(value[key]) != TYPE_ARRAY and child != "map.baseTerrains": errors.append("数组类型非法 `%s`" % child)
			match field:
				"baseTerrains": allowed = Enums.BaseTerrain.ALL
				"reliefs": allowed = Enums.Relief.ALL
				"rootTypes": allowed = Enums.SpiritRootType.ALL
				"aiFactions": allowed = Enums.FactionType.ALL
				"nodeTypes": allowed = Enums.NodeType.ALL
			if not allowed.is_empty() and typeof(value[key]) == TYPE_ARRAY:
				if value[key].is_empty(): errors.append("枚举数组不能为空 `%s`" % child)
				for entry: Variant in value[key]:
					if typeof(entry) != TYPE_STRING or not allowed.has(entry): errors.append("非法枚举 `%s`" % child)
			if field == "factionOnly" and child != "building.factionOnly" and (typeof(value[key]) != TYPE_STRING or not Enums.FactionType.ALL.has(String(value[key]))): errors.append("流派枚举非法 `%s`" % child)
			if field == "features" and typeof(value[key]) == TYPE_ARRAY:
				for entry: Variant in value[key]:
					if typeof(entry) != TYPE_STRING or not Enums.Feature.ALL.has(entry): errors.append("地貌枚举非法 `%s`" % child)
			if field in ["range", "minRealmLevel", "minRootGrade", "moveCost", "visionBonus", "sourcesMin", "sourcesMax", "sourceEdgesMin", "sourceEdgesMax", "defaultWidth", "defaultHeight"] and _is_number(value[key]) and float(value[key]) != floor(float(value[key])): errors.append("必须整数 `%s`" % child)
			_scan(value[key], child, errors)
	elif typeof(value) == TYPE_ARRAY:
		for index: int in range(value.size()): _scan(value[index], "%s[%d]" % [path, index], errors)
	elif _is_number(value):
		var number: float = float(value)
		var signed: bool = path.ends_with("moveBonus") or "rootMoveBonus." in path or path.ends_with("defenseBonus") or path.ends_with("stabilityPerTurn")
		if not is_finite(number) or (number < 0 and not signed): errors.append("负数/非有限数 `%s`" % path)
		var lower: String = path.to_lower()
		if ("chance" in lower or path.ends_with(".ratio") or "edgeRatio" in path) and (number < 0 or number > 1): errors.append("概率/比例越界 `%s`" % path)
