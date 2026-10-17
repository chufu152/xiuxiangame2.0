class_name SaveManager
extends RefCounted
## 存档 / 读档 / 自动存档（对齐 1.0 `save/SaveManager`，用 `FileAccess` + `JSON`）。
##
## 存档文件形状与 1.0 `SaveWrapper` 一致：`{saveVersion, savedAt, gameState}`，
## 版本号取 `Msg.SAVE_VERSION`（"3.0"，裁决八）。
##
## **目录落在项目 `saves/`**（`res://saves`），已在 `.gitignore` 里（`/saves/*` + `!/saves/.gitkeep`），
## 不入库。文件名沿用 1.0 规则 `save_<slot>.json`，自动存档固定槽 0（裁决九）。
##
## 序列化口径：**不复用各模型的 `to_dict()`**——那是 `view` 形状（迷雾裁剪、部分内部字段不下发），
## 存档必须全量且与 view 无关。故本类自带 `_state_to_dict` / `_state_from_dict` 一对函数，
## 字段与 `server/scripts/model/*.gd` 逐个对应（新增模型字段时必须同步这两处，见类末清单）。

## 自动存档槽位（1.0 `AUTO_SAVE_SLOT`）。
const AUTO_SAVE_SLOT: int = 0
const SAVE_FILE_PREFIX: String = "save_"
const SAVE_FILE_SUFFIX: String = ".json"
const SAVE_DIR_NAME: String = "saves"


# ---------------------------------------------------------------------------
# 路径
# ---------------------------------------------------------------------------

## 存档目录（绝对路径）。`res://saves` 在开发期与无头模式下可写；
## 打包后 `res://` 只读时自动退回 `user://saves`，保证不因只读而丢档。
static func save_dir() -> String:
	var project_dir: String = ProjectSettings.globalize_path("res://") + SAVE_DIR_NAME
	if DirAccess.dir_exists_absolute(project_dir):
		return project_dir
	DirAccess.make_dir_recursive_absolute(project_dir)
	return project_dir


static func save_file_name(slot: int) -> String:
	return "%s%d%s" % [SAVE_FILE_PREFIX, slot, SAVE_FILE_SUFFIX]


static func save_file_path(slot: int) -> String:
	return save_dir().path_join(save_file_name(slot))


# ---------------------------------------------------------------------------
# 保存 / 读取
# ---------------------------------------------------------------------------

## 保存到指定槽位。返回 `{slot, saved}`，失败时追加 `message`
## （PROTOCOL §2 固定形状，**无 `success` 布尔**，硬约束 4）。
static func save_game(state: GameState, config: Dictionary, slot: int) -> Dictionary:
	if state == null:
		return {"slot": slot, "saved": false, "message": "尚未开局"}
	var path: String = save_file_path(slot)
	var payload: Dictionary = {
		"saveVersion": Msg.SAVE_VERSION,
		"savedAt": Time.get_datetime_string_from_system(),
		"gameState": _state_to_dict(state, config),
	}
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"slot": slot, "saved": false, "message": "无法写入存档: " + error_string(FileAccess.get_open_error())}
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()
	return {"slot": slot, "saved": true}


## 读档并重建对局。返回 `{slot, turn, state}`；槽位不存在返回 `{slot, turn:0, state:null, message}`。
static func load_game(config: Dictionary, slot: int) -> Dictionary:
	var path: String = save_file_path(slot)
	if not FileAccess.file_exists(path):
		return {"slot": slot, "turn": 0, "state": null, "message": "存档槽位不存在: %d" % slot}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"slot": slot, "turn": 0, "state": null, "message": "无法读取存档"}
	var text: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return {"slot": slot, "turn": 0, "state": null, "message": "存档内容损坏"}
	var wrapper: Dictionary = parsed as Dictionary
	var version: String = str(wrapper.get("saveVersion", ""))
	if version.is_empty():
		state_log("槽位 %d 缺少版本号, 按当前版本尝试加载" % slot)
	elif not is_version_compatible(version):
		state_log("槽位 %d 版本 %s 与当前 %s 不兼容, 仍尝试加载" % [slot, version, Msg.SAVE_VERSION])
	var raw: Variant = wrapper.get("gameState", null)
	if not (raw is Dictionary):
		return {"slot": slot, "turn": 0, "state": null, "message": "存档缺少 gameState"}
	var state: GameState = _state_from_dict(raw as Dictionary, config)
	if state == null:
		return {"slot": slot, "turn": 0, "state": null, "message": "存档重建失败"}
	migrate_legacy_rare_materials(state, config)
	# 读档后按存档种子与掷骰状态复原，保证「读同一份档续玩可复现」。
	VisionCalculator.recalculate(state, config)
	RoadNetworkService.refresh(state, config)
	return {"slot": slot, "turn": state.turn, "state": state}


## 自动存档槽 0（裁决九）。
static func auto_save(state: GameState, config: Dictionary) -> bool:
	return bool(save_game(state, config, AUTO_SAVE_SLOT)["saved"])


## 列出全部存档槽（按槽位升序）。字段与 PROTOCOL §2 `listSaves.saves[]` 逐字一致。
static func list_saves() -> Array[SaveInfo]:
	var result: Array[SaveInfo] = []
	var dir: DirAccess = DirAccess.open(save_dir())
	if dir == null:
		return result
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while not entry.is_empty():
		if not dir.current_is_dir() and entry.begins_with(SAVE_FILE_PREFIX) and entry.ends_with(SAVE_FILE_SUFFIX):
			var info: SaveInfo = _read_save_info(entry)
			if info != null:
				result.append(info)
		entry = dir.get_next()
	dir.list_dir_end()
	result.sort_custom(func(a: SaveInfo, b: SaveInfo) -> bool: return a.slotId < b.slotId)
	return result


## 版本兼容：主版本号相同即兼容（1.0 `isVersionCompatible` 同语义）。
static func is_version_compatible(version: String) -> bool:
	var theirs: PackedStringArray = version.split(".")
	var ours: PackedStringArray = Msg.SAVE_VERSION.split(".")
	if theirs.is_empty() or ours.is_empty():
		return false
	return theirs[0] == ours[0]


## 旧档稀有材料整数字段按配置折算成分材料；折算后清零，重复读档不会翻倍
## （1.0 `migrateLegacyRareMaterials`，裁决八保留）。
## 2.0 的 `Sect.resources` 用 `materials{}` 字典，不存在旧式整数字段时本函数是空操作。
static func migrate_legacy_rare_materials(state: GameState, config: Dictionary) -> void:
	var conversion: Dictionary = config["resources"].get("legacyRareMaterialConversion", {})
	if conversion.is_empty():
		return
	for sect: Sect in state.sects:
		var legacy: int = int(sect.resources.get("rareMaterials", 0))
		if legacy <= 0:
			continue
		var materials: Dictionary = sect.resources.get("materials", {})
		for material: Variant in conversion.keys():
			materials[str(material)] = int(materials.get(str(material), 0)) \
				+ legacy * int(conversion[material])
		sect.resources["materials"] = materials
		sect.resources["rareMaterials"] = 0


# ---------------------------------------------------------------------------
# 槽位元信息
# ---------------------------------------------------------------------------

static func _read_save_info(file_name: String) -> SaveInfo:
	var path: String = save_dir().path_join(file_name)
	var slot_text: String = file_name.substr(SAVE_FILE_PREFIX.length(),
		file_name.length() - SAVE_FILE_PREFIX.length() - SAVE_FILE_SUFFIX.length())
	if not slot_text.is_valid_int():
		return null
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var text: String = file.get_as_text()
	var size: int = file.get_length()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return null
	var wrapper: Dictionary = parsed as Dictionary
	var info: SaveInfo = SaveInfo.new()
	info.slotId = int(slot_text)
	info.savedAt = str(wrapper.get("savedAt", ""))
	info.filePath = path
	info.fileSize = size
	var game_state: Variant = wrapper.get("gameState", null)
	if game_state is Dictionary:
		var raw: Dictionary = game_state as Dictionary
		info.turn = int(raw.get("turn", 0))
		var player: Dictionary = _find_player_sect_dict(raw)
		info.playerSectName = str(player.get("name", ""))
		info.factionType = str(player.get("factionType", ""))
	return info


## 找玩家宗门：先按 `playerSectId`，再按 `player` 标志，最后退回首个（1.0 `findPlayerSect` 同序）。
static func _find_player_sect_dict(game_state: Dictionary) -> Dictionary:
	var sects: Variant = game_state.get("sects", null)
	if not (sects is Array):
		return {}
	var player_id: String = str(game_state.get("playerSectId", ""))
	for entry: Variant in sects as Array:
		if entry is Dictionary and str((entry as Dictionary).get("id", "")) == player_id:
			return entry as Dictionary
	for entry: Variant in sects as Array:
		if entry is Dictionary and bool((entry as Dictionary).get("player", false)):
			return entry as Dictionary
	var first: Variant = (sects as Array)[0] if not (sects as Array).is_empty() else null
	return first as Dictionary if first is Dictionary else {}


static func state_log(text: String) -> void:
	print("[存档] " + text)


# ---------------------------------------------------------------------------
# 序列化：GameState → Dictionary
# ---------------------------------------------------------------------------

static func _state_to_dict(state: GameState, config: Dictionary) -> Dictionary:
	var tiles: Dictionary = {}
	for tile: HexTile in state.tiles.values():
		tiles[tile.id] = _tile_to_dict(tile)
	var nodes: Dictionary = {}
	for node: GameNode in state.nodes.values():
		nodes[node.id] = _node_to_dict(node)
	var sects: Array = []
	for sect: Sect in state.sects:
		sects.append(_sect_to_dict(sect))
	return {
		"width": state.width,
		"height": state.height,
		"seed": state.seed,
		"difficulty": state.difficulty,
		"turn": state.turn,
		"phase": state.phase,
		"playerSectId": state.playerSectId,
		"tiles": tiles,
		"nodes": nodes,
		"spawnTiles": state.spawnTiles.duplicate(),
		"sects": sects,
		"rng": state.rng.snapshot() if state.rng != null else {"seed": state.seed, "sequence": 0},
		"riverPaths": _deep_duplicate(state.riverPaths),
		"gameOver": state.gameOver,
		"eventLog": state.eventLog.duplicate(),
		"projectSeq": state.projectSeq,
		"improvementSeq": state.improvementSeq,
		"discipleSeq": state.discipleSeq,
		"winType": state.winType,
		"winnerSectId": state.winnerSectId,
		"pendingVictoryChoices": state.pendingVictoryChoices.duplicate(),
	}


static func _tile_to_dict(tile: HexTile) -> Dictionary:
	return {
		"id": tile.id, "q": tile.q, "r": tile.r,
		"baseTerrain": tile.baseTerrain, "relief": tile.relief,
		"features": tile.features.duplicate(), "riverEdges": tile.riverEdges.duplicate(),
		"danger": tile.danger, "ownerSectId": tile.ownerSectId,
		"nodeId": tile.nodeId, "districtId": tile.districtId,
		"workedByPeakId": tile.workedByPeakId, "improvementId": tile.improvementId,
		"luxuryType": tile.luxuryType,
	}


static func _node_to_dict(node: GameNode) -> Dictionary:
	return {
		"id": node.id, "name": node.name, "type": node.type, "tileId": node.tileId,
		"ownerSectId": node.ownerSectId, "level": node.level, "reserve": node.reserve,
		"output": node.output, "cooldown": node.cooldown,
		"garrisonDiscipleIds": node.garrisonDiscipleIds.duplicate(),
	}


static func _sect_to_dict(sect: Sect) -> Dictionary:
	var disciples: Array = []
	for disciple: Disciple in sect.disciples:
		disciples.append(_disciple_to_dict(disciple))
	var peaks: Array = []
	for peak: SpiritPeak in sect.spiritPeaks:
		peaks.append(_peak_to_dict(peak))
	var improvements: Array = []
	for improvement: Improvement in sect.improvements:
		improvements.append(improvement.to_dict())
	var research: Array = []
	for project: ResearchProject in sect.researchQueue:
		research.append(project.to_dict())
	return {
		"id": sect.id, "name": sect.name, "factionType": sect.factionType, "player": sect.player,
		"resources": _deep_duplicate(sect.resources),
		"disciples": disciples,
		"spiritPeaks": peaks,
		"visibleTiles": sect.visibleTiles.duplicate(),
		"exploredTiles": sect.exploredTiles.duplicate(),
		"tileSnapshots": _deep_duplicate(sect.tileSnapshots),
		"nodeSnapshots": _deep_duplicate(sect.nodeSnapshots),
		"peakSnapshots": _deep_duplicate(sect.peakSnapshots),
		"improvementSnapshots": _deep_duplicate(sect.improvementSnapshots),
		"improvements": improvements,
		"unlockedDaoIds": sect.unlockedDaoIds.duplicate(),
		"researchQueue": research,
		"boostFlags": _deep_duplicate(sect.boostFlags),
		"recruitedTotal": sect.recruitedTotal,
		"enemiesDefeated": sect.enemiesDefeated,
		"miJingExploredTotal": sect.miJingExploredTotal,
		"lastRecruitmentTurn": sect.lastRecruitmentTurn,
		"teleportsUsedThisTurn": sect.teleportsUsedThisTurn,
		"governmentId": sect.governmentId,
		"enactedPolicies": sect.enactedPolicies.duplicate(),
		"policyCarry": _deep_duplicate(sect.policyCarry),
		"lastPolicySwitchTurn": sect.lastPolicySwitchTurn,
		"automationToggles": _deep_duplicate(sect.automationToggles),
		"autoProjectByPeak": _deep_duplicate(sect.autoProjectByPeak),
		"powerLevel": sect.powerLevel,
		"defeated": sect.defeated,
		"lastAutoSaveTurn": sect.lastAutoSaveTurn,
		"zongZhuOutside": sect.zongZhuOutside,
	}


static func _disciple_to_dict(disciple: Disciple) -> Dictionary:
	return {
		"id": disciple.id, "name": disciple.name, "sectId": disciple.sectId,
		"tileId": disciple.tileId, "realm": disciple.realm, "position": disciple.position,
		"rootGrade": disciple.rootGrade, "spiritRoots": disciple.spiritRoots.duplicate(),
		"unitClass": disciple.unitClass, "movePoints": disciple.movePoints,
		"maxMovePoints": disciple.maxMovePoints, "attacksRemaining": disciple.attacksRemaining,
		"turnsInSect": disciple.turnsInSect, "assignedPeakId": disciple.assignedPeakId,
		"bloodLine": disciple.bloodLine, "generation": disciple.generation,
		"directLine": disciple.directLine, "heartDevil": disciple.heartDevil,
		"injured": disciple.injured, "cultivationProgress": disciple.cultivationProgress,
		"builderCharges": disciple.builderCharges, "realmLevel": disciple.realmLevel,
		"breakthroughPending": disciple.breakthroughPending, "tribulating": disciple.tribulating,
		"lastReproduceTurn": disciple.lastReproduceTurn, "battleXp": disciple.battleXp,
		"battleLevel": disciple.battleLevel, "promotionPoints": disciple.promotionPoints,
		"promotions": disciple.promotions.duplicate(), "reclassCooldown": disciple.reclassCooldown,
		"garrisonNodeId": disciple.garrisonNodeId,
		"capturedFromSectId": disciple.capturedFromSectId,
		"missionNodeId": disciple.missionNodeId, "ascended": disciple.ascended,
		"spouseId": disciple.spouseId, "fatherId": disciple.fatherId, "motherId": disciple.motherId,
	}


static func _peak_to_dict(peak: SpiritPeak) -> Dictionary:
	var districts: Array = []
	for district: District in peak.districts:
		districts.append(district.to_dict())
	var projects: Array = []
	for project: Project in peak.projectQueue:
		projects.append(project.to_dict())
	return {
		"id": peak.id, "name": peak.name, "sectId": peak.sectId, "tileId": peak.tileId,
		"capital": peak.capital, "level": peak.level, "population": peak.population,
		"capacity": peak.capacity, "defense": peak.defense, "qiYun": peak.qiYun,
		"qiYunMax": peak.qiYunMax, "stability": peak.stability, "housing": peak.housing,
		"fengZhuId": peak.fengZhuId, "buildings": _deep_duplicate(peak.buildings),
		"districts": districts, "food": peak.food, "foodProgress": peak.foodProgress,
		"freeWorkers": peak.freeWorkers, "workedTileIds": peak.workedTileIds.duplicate(),
		"projectQueue": projects, "siegeTurns": peak.siegeTurns,
	}


# ---------------------------------------------------------------------------
# 反序列化：Dictionary → GameState
# ---------------------------------------------------------------------------

static func _state_from_dict(raw: Dictionary, config: Dictionary) -> GameState:
	var state: GameState = GameState.new()
	state.width = int(raw.get("width", 0))
	state.height = int(raw.get("height", 0))
	state.seed = int(raw.get("seed", 0))
	state.difficulty = str(raw.get("difficulty", "normal"))
	state.turn = int(raw.get("turn", 1))
	state.phase = str(raw.get("phase", Enums.TurnPhase.PLAYER_ACTION))
	state.playerSectId = str(raw.get("playerSectId", ""))
	state.gameOver = bool(raw.get("gameOver", false))
	state.eventLog = _strings(raw.get("eventLog", []))
	state.projectSeq = int(raw.get("projectSeq", 0))
	state.improvementSeq = int(raw.get("improvementSeq", 0))
	state.discipleSeq = int(raw.get("discipleSeq", 0))
	state.winType = str(raw.get("winType", ""))
	state.winnerSectId = str(raw.get("winnerSectId", ""))
	state.pendingVictoryChoices = _strings(raw.get("pendingVictoryChoices", []))
	state.spawnTiles = _strings(raw.get("spawnTiles", []))
	state.riverPaths = _river_paths(raw.get("riverPaths", []))
	state.rng = RngService.new(state.seed)
	state.rng.restore(raw.get("rng", {}))
	state.tiles = {}
	var tiles: Variant = raw.get("tiles", {})
	if tiles is Dictionary:
		for key: Variant in (tiles as Dictionary).keys():
			state.tiles[str(key)] = _tile_from_dict((tiles as Dictionary)[key])
	state.nodes = {}
	var nodes: Variant = raw.get("nodes", {})
	if nodes is Dictionary:
		for key: Variant in (nodes as Dictionary).keys():
			state.nodes[str(key)] = _node_from_dict((nodes as Dictionary)[key])
	state.sects = []
	var sects: Variant = raw.get("sects", [])
	if sects is Array:
		for entry: Variant in sects as Array:
			if entry is Dictionary:
				state.sects.append(_sect_from_dict(entry as Dictionary))
	return state


static func _tile_from_dict(data: Variant) -> HexTile:
	var tile: HexTile = HexTile.new()
	if not (data is Dictionary):
		return tile
	var raw: Dictionary = data as Dictionary
	tile.id = str(raw.get("id", ""))
	tile.q = int(raw.get("q", 0))
	tile.r = int(raw.get("r", 0))
	tile.baseTerrain = str(raw.get("baseTerrain", Enums.BaseTerrain.SPIRIT_PLAIN))
	tile.relief = str(raw.get("relief", Enums.Relief.FLAT))
	tile.features = _strings(raw.get("features", []))
	tile.riverEdges.clear()
	for edge: Variant in _array(raw.get("riverEdges", [])):
		tile.riverEdges.append(int(edge))
	tile.danger = bool(raw.get("danger", false))
	tile.ownerSectId = str(raw.get("ownerSectId", ""))
	tile.nodeId = str(raw.get("nodeId", ""))
	tile.districtId = str(raw.get("districtId", ""))
	tile.workedByPeakId = str(raw.get("workedByPeakId", ""))
	tile.improvementId = str(raw.get("improvementId", ""))
	tile.luxuryType = str(raw.get("luxuryType", ""))
	return tile


static func _node_from_dict(data: Variant) -> GameNode:
	var node: GameNode = GameNode.new()
	if not (data is Dictionary):
		return node
	var raw: Dictionary = data as Dictionary
	node.id = str(raw.get("id", ""))
	node.name = str(raw.get("name", ""))
	node.type = str(raw.get("type", Enums.NodeType.LING_TIAN))
	node.tileId = str(raw.get("tileId", ""))
	node.ownerSectId = str(raw.get("ownerSectId", ""))
	node.level = int(raw.get("level", 1))
	node.reserve = float(raw.get("reserve", 0.0))
	node.output = float(raw.get("output", 0.0))
	node.cooldown = int(raw.get("cooldown", 0))
	node.garrisonDiscipleIds = _strings(raw.get("garrisonDiscipleIds", []))
	return node


static func _sect_from_dict(data: Dictionary) -> Sect:
	var sect: Sect = Sect.new()
	sect.id = str(data.get("id", ""))
	sect.name = str(data.get("name", ""))
	sect.factionType = str(data.get("factionType", Enums.FactionType.ZONG_MEN))
	sect.player = bool(data.get("player", false))
	sect.resources = _dict(data.get("resources", {}))
	sect.visibleTiles = _strings(data.get("visibleTiles", []))
	sect.exploredTiles = _strings(data.get("exploredTiles", []))
	sect.tileSnapshots = _dict(data.get("tileSnapshots", {}))
	sect.nodeSnapshots = _dict(data.get("nodeSnapshots", {}))
	sect.peakSnapshots = _dict(data.get("peakSnapshots", {}))
	sect.improvementSnapshots = _dict(data.get("improvementSnapshots", {}))
	sect.unlockedDaoIds = _strings(data.get("unlockedDaoIds", []))
	sect.boostFlags = _dict(data.get("boostFlags", {}))
	sect.recruitedTotal = int(data.get("recruitedTotal", 0))
	sect.enemiesDefeated = int(data.get("enemiesDefeated", 0))
	sect.miJingExploredTotal = int(data.get("miJingExploredTotal", 0))
	sect.lastRecruitmentTurn = int(data.get("lastRecruitmentTurn", 0))
	sect.teleportsUsedThisTurn = int(data.get("teleportsUsedThisTurn", 0))
	sect.governmentId = str(data.get("governmentId", ""))
	sect.enactedPolicies = _strings(data.get("enactedPolicies", []))
	sect.policyCarry = _dict(data.get("policyCarry", {}))
	sect.lastPolicySwitchTurn = int(data.get("lastPolicySwitchTurn", 0))
	sect.automationToggles = _dict(data.get("automationToggles", {}))
	sect.autoProjectByPeak = _dict(data.get("autoProjectByPeak", {}))
	sect.powerLevel = int(data.get("powerLevel", 0))
	sect.defeated = bool(data.get("defeated", false))
	sect.lastAutoSaveTurn = int(data.get("lastAutoSaveTurn", 0))
	sect.zongZhuOutside = bool(data.get("zongZhuOutside", false))
	sect.disciples = []
	for entry: Variant in _array(data.get("disciples", [])):
		if entry is Dictionary:
			sect.disciples.append(_disciple_from_dict(entry as Dictionary))
	sect.spiritPeaks = []
	for entry: Variant in _array(data.get("spiritPeaks", [])):
		if entry is Dictionary:
			sect.spiritPeaks.append(_peak_from_dict(entry as Dictionary))
	sect.improvements = []
	for entry: Variant in _array(data.get("improvements", [])):
		if entry is Dictionary:
			sect.improvements.append(_improvement_from_dict(entry as Dictionary))
	sect.researchQueue = []
	for entry: Variant in _array(data.get("researchQueue", [])):
		if entry is Dictionary:
			sect.researchQueue.append(_research_from_dict(entry as Dictionary))
	return sect


static func _disciple_from_dict(data: Dictionary) -> Disciple:
	var disciple: Disciple = Disciple.new()
	disciple.id = str(data.get("id", ""))
	disciple.name = str(data.get("name", ""))
	disciple.sectId = str(data.get("sectId", ""))
	disciple.tileId = str(data.get("tileId", ""))
	disciple.realm = str(data.get("realm", Enums.Realm.LIAN_QI))
	disciple.position = str(data.get("position", ""))
	disciple.rootGrade = int(data.get("rootGrade", 0))
	disciple.spiritRoots = _strings(data.get("spiritRoots", []))
	disciple.unitClass = str(data.get("unitClass", Enums.UnitClass.PU_TONG))
	disciple.movePoints = int(data.get("movePoints", 0))
	disciple.maxMovePoints = int(data.get("maxMovePoints", 0))
	disciple.attacksRemaining = int(data.get("attacksRemaining", 0))
	disciple.turnsInSect = int(data.get("turnsInSect", 0))
	disciple.assignedPeakId = str(data.get("assignedPeakId", ""))
	disciple.bloodLine = bool(data.get("bloodLine", false))
	disciple.generation = int(data.get("generation", 0))
	disciple.directLine = bool(data.get("directLine", false))
	disciple.heartDevil = int(data.get("heartDevil", 0))
	disciple.injured = bool(data.get("injured", false))
	disciple.cultivationProgress = float(data.get("cultivationProgress", 0.0))
	disciple.builderCharges = int(data.get("builderCharges", 0))
	disciple.realmLevel = int(data.get("realmLevel", Disciple.level_of(disciple.realm)))
	disciple.breakthroughPending = bool(data.get("breakthroughPending", false))
	disciple.tribulating = bool(data.get("tribulating", false))
	disciple.lastReproduceTurn = int(data.get("lastReproduceTurn", 0))
	disciple.battleXp = int(data.get("battleXp", 0))
	disciple.battleLevel = int(data.get("battleLevel", 0))
	disciple.promotionPoints = int(data.get("promotionPoints", 0))
	disciple.promotions = _strings(data.get("promotions", []))
	disciple.reclassCooldown = int(data.get("reclassCooldown", 0))
	disciple.garrisonNodeId = str(data.get("garrisonNodeId", ""))
	disciple.capturedFromSectId = str(data.get("capturedFromSectId", ""))
	disciple.missionNodeId = str(data.get("missionNodeId", ""))
	disciple.ascended = bool(data.get("ascended", false))
	disciple.spouseId = str(data.get("spouseId", ""))
	disciple.fatherId = str(data.get("fatherId", ""))
	disciple.motherId = str(data.get("motherId", ""))
	return disciple


static func _peak_from_dict(data: Dictionary) -> SpiritPeak:
	var peak: SpiritPeak = SpiritPeak.new()
	peak.id = str(data.get("id", ""))
	peak.name = str(data.get("name", ""))
	peak.sectId = str(data.get("sectId", ""))
	peak.tileId = str(data.get("tileId", ""))
	peak.capital = bool(data.get("capital", true))
	peak.level = int(data.get("level", 0))
	peak.population = int(data.get("population", 0))
	peak.capacity = int(data.get("capacity", 0))
	peak.defense = int(data.get("defense", 0))
	peak.qiYun = int(data.get("qiYun", 0))
	peak.qiYunMax = int(data.get("qiYunMax", 0))
	peak.stability = float(data.get("stability", 0.0))
	peak.housing = int(data.get("housing", 0))
	peak.fengZhuId = str(data.get("fengZhuId", ""))
	peak.buildings = _dict(data.get("buildings", {}))
	peak.food = float(data.get("food", 0.0))
	peak.foodProgress = float(data.get("foodProgress", 0.0))
	peak.freeWorkers = int(data.get("freeWorkers", 0))
	peak.workedTileIds = _strings(data.get("workedTileIds", []))
	peak.siegeTurns = int(data.get("siegeTurns", 0))
	peak.districts = []
	for entry: Variant in _array(data.get("districts", [])):
		if entry is Dictionary:
			peak.districts.append(_district_from_dict(entry as Dictionary))
	peak.projectQueue = []
	for entry: Variant in _array(data.get("projectQueue", [])):
		if entry is Dictionary:
			peak.projectQueue.append(_project_from_dict(entry as Dictionary))
	return peak


static func _district_from_dict(data: Dictionary) -> District:
	var district: District = District.new()
	district.id = str(data.get("id", ""))
	district.name = str(data.get("name", ""))
	district.type = str(data.get("type", ""))
	district.typeName = str(data.get("typeName", ""))
	district.level = int(data.get("level", 1))
	district.populationAssigned = int(data.get("populationAssigned", 0))
	district.buildings = _strings(data.get("buildings", []))
	district.tileId = str(data.get("tileId", ""))
	return district


static func _project_from_dict(data: Dictionary) -> Project:
	var project: Project = Project.new()
	project.id = str(data.get("id", ""))
	project.type = str(data.get("type", ""))
	project.name = str(data.get("name", ""))
	project.turnsRequired = int(data.get("turnsRequired", 0))
	project.turnsRemaining = int(data.get("turnsRemaining", 0))
	project.spiritPowerCost = int(data.get("spiritPowerCost", 0))
	project.targetId = str(data.get("targetId", ""))
	project.discipleId = str(data.get("discipleId", ""))
	project.buildingType = str(data.get("buildingType", ""))
	project.districtType = str(data.get("districtType", ""))
	project.materialCost = _dict(data.get("materialCost", {}))
	return project


static func _improvement_from_dict(data: Dictionary) -> Improvement:
	var improvement: Improvement = Improvement.new()
	improvement.id = str(data.get("id", ""))
	improvement.type = str(data.get("type", ""))
	improvement.tileId = str(data.get("tileId", ""))
	improvement.sectId = str(data.get("sectId", ""))
	improvement.broken = bool(data.get("broken", false))
	improvement.charges = int(data.get("charges", 0))
	improvement.networkLevel = int(data.get("networkLevel", 0))
	return improvement


static func _research_from_dict(data: Dictionary) -> ResearchProject:
	var project: ResearchProject = ResearchProject.new()
	project.id = str(data.get("id", ""))
	project.daoId = str(data.get("daoId", ""))
	project.name = str(data.get("name", ""))
	project.turnsRequired = int(data.get("turnsRequired", 0))
	project.turnsRemaining = int(data.get("turnsRemaining", 0))
	project.daoPointCost = int(data.get("daoPointCost", 0))
	project.spiritPowerCost = int(data.get("spiritPowerCost", 0))
	return project


# ---------------------------------------------------------------------------
# 类型辅助
# ---------------------------------------------------------------------------

## JSON 读回来一律是无类型 `Array`，赋值给 `Array[String]` 字段必须显式重建。
static func _strings(value: Variant) -> Array[String]:
	var out: Array[String] = []
	if value is Array:
		for entry: Variant in value as Array:
			out.append(str(entry))
	return out


static func _array(value: Variant) -> Array:
	return value as Array if value is Array else []


static func _dict(value: Variant) -> Dictionary:
	return value as Dictionary if value is Dictionary else {}


## `riverPaths` 是 `Array[Array]`（每段路径是坐标对数组），JSON 往返后需要按层重建。
static func _river_paths(value: Variant) -> Array[Array]:
	var out: Array[Array] = []
	for path: Variant in _array(value):
		var points: Array = []
		for point: Variant in _array(path):
			if point is Array:
				var pair: Array = []
				for component: Variant in point as Array:
					pair.append(int(component))
				points.append(pair)
		out.append(points)
	return out


## JSON 里 Dictionary/Array 是引用共享的；存档要的是快照，故按层深拷。
static func _deep_duplicate(value: Variant) -> Variant:
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	if value is Array:
		return (value as Array).duplicate(true)
	return value
