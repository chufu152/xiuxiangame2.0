class_name CityAction
extends RefCounted
## 城市命令（R3）：开峰 / 建筑 / 洞府 / 加固 / 区域 / 劳力 / 城市面板查询。
##
## 全部静态、无状态；数值只取自 `data/gameConfig.json`，规则委托 `CityRules` / `EconomyRules`。
## 1.0 蓝本：`BuildAction` + `DistrictAction`。
##
## 返回口径（PROTOCOL §3/§4）：
##   - 写命令 → `BuildResult{success, message, projectId, turnsRequired, spiritPowerCost}`；
##   - 只读 `query*` → 各自 result 形状（调用方以 `view=null` 下发）。
## **业务失败**（灵力/材料不足、山岳不可建城、区域超上限等）一律 `success:false + message`，
## 不用协议错误码；参数缺失/枚举非法由 `CommandDispatcher` 回 `BAD_PARAMS`。


# ---------------------------------------------------------------------------
# BuildResult 构造
# ---------------------------------------------------------------------------

static func ok_result(message: String, project_id: String = "", turns: int = 0, cost: int = 0) -> Dictionary:
	return {"success": true, "message": message, "projectId": project_id, "turnsRequired": turns, "spiritPowerCost": cost}


static func fail_result(message: String) -> Dictionary:
	return {"success": false, "message": message, "projectId": "", "turnsRequired": 0, "spiritPowerCost": 0}


# ---------------------------------------------------------------------------
# 查找
# ---------------------------------------------------------------------------

static func find_sect(state: GameState, sect_id: String) -> Sect:
	for sect: Sect in state.sects:
		if sect.id == sect_id:
			return sect
	return null


static func find_peak(state: GameState, peak_id: String) -> SpiritPeak:
	for sect: Sect in state.sects:
		for peak: SpiritPeak in sect.spiritPeaks:
			if peak.id == peak_id:
				return peak
	return null


static func find_disciple(state: GameState, disciple_id: String) -> Disciple:
	for sect: Sect in state.sects:
		for disciple: Disciple in sect.disciples:
			if disciple.id == disciple_id:
				return disciple
	return null


static func _capital_peak(sect: Sect) -> SpiritPeak:
	for peak: SpiritPeak in sect.spiritPeaks:
		if peak.capital:
			return peak
	if sect.spiritPeaks.is_empty():
		return null
	return sect.spiritPeaks[0]


static func _new_project(state: GameState, project_type: String, name: String, turns: int, cost: int) -> Project:
	state.projectSeq += 1
	var project: Project = Project.new()
	project.id = "project_%d" % state.projectSeq
	project.type = project_type
	project.name = name
	project.turnsRequired = maxi(1, turns)
	project.turnsRemaining = maxi(1, turns)
	project.spiritPowerCost = cost
	return project


static func _power(sect: Sect) -> int:
	return int(sect.resources.get("spiritPower", 0))


static func _set_power(sect: Sect, value: int) -> void:
	sect.resources["spiritPower"] = maxi(0, value)


# ---------------------------------------------------------------------------
# 写命令
# ---------------------------------------------------------------------------

## 开辟灵峰（建城）：入队 `foundTurns` 回合，落成时新增灵峰并铺首府区（裁决四）。
static func found_spirit_peak(state: GameState, config: Dictionary, disciple_id: String, tile_id: String) -> Dictionary:
	var disciple: Disciple = find_disciple(state, disciple_id)
	if disciple == null:
		return fail_result("弟子不存在: " + disciple_id)
	var sect: Sect = find_sect(state, disciple.sectId)
	if sect == null:
		return fail_result("弟子宗门不存在")
	var tile: HexTile = state.tiles.get(tile_id)
	var blocker: String = CityRules.can_found_peak(state, config, disciple, tile)
	if not blocker.is_empty():
		return fail_result(blocker)
	var cost: int = CityRules.found_peak_cost(config, sect)
	if _power(sect) < cost:
		return fail_result("灵力不足(%d/%d)" % [_power(sect), cost])
	var capital: SpiritPeak = _capital_peak(sect)
	if capital == null:
		return fail_result("宗门无灵峰落脚, 无法开辟新峰")
	var turns: int = int(config["spiritPeak"]["foundTurns"])
	_set_power(sect, _power(sect) - cost)
	var project: Project = _new_project(state, Project.TYPE_FOUND_PEAK, "开辟灵峰(%s)" % tile_id, turns, cost)
	project.targetId = tile_id
	project.discipleId = disciple_id
	capital.projectQueue.append(project)
	state.eventLog.append("[灵峰] %s 于 %s 开辟灵峰, 需 %d 回合" % [sect.name, tile_id, turns])
	return ok_result("已加入项目队列: 开辟灵峰, 需 %d 回合, 消耗 %d 灵力" % [turns, cost], project.id, turns, cost)


## 建造建筑：按 `building.costs/turns/materialCosts` 扣灵力与材料后入队。
static func construct_building(state: GameState, config: Dictionary, peak_id: String, building_type: String) -> Dictionary:
	var peak: SpiritPeak = find_peak(state, peak_id)
	if peak == null:
		return fail_result("灵峰不存在: " + peak_id)
	var sect: Sect = find_sect(state, peak.sectId)
	if sect == null:
		return fail_result("灵峰所属宗门不存在")
	var check: Dictionary = CityRules.can_build(state, config, peak, building_type)
	if not bool(check["allowed"]):
		return fail_result(str(check["blocker"]))
	var building: Dictionary = config["building"]
	var cost: int = int(building["costs"][building_type])
	var turns: int = int(building["turns"][building_type])
	var material_cost: Dictionary = building["materialCosts"].get(building_type, {})
	var materials: Dictionary = sect.resources.get("materials", {})
	_set_power(sect, _power(sect) - cost)
	for material: Variant in material_cost.keys():
		materials[material] = int(materials.get(material, 0)) - int(material_cost[material])
	sect.resources["materials"] = materials
	var display_name: String = str(Enums.Building.NAMES.get(building_type, building_type))
	var project_type: String = Project.TYPE_BUILD if Enums.Building.CORE.has(building_type) else Project.TYPE_SUB_PEAK
	var project: Project = _new_project(state, project_type, "建造" + display_name, turns, cost)
	project.buildingType = building_type
	project.materialCost = material_cost.duplicate(true)
	peak.projectQueue.append(project)
	state.eventLog.append("[灵峰] %s 建造%s, 需 %d 回合, 消耗 %d 灵力" % [peak.name, display_name, turns, cost])
	return ok_result("已加入项目队列: 建造%s, 需 %d 回合, 消耗 %d 灵力" % [display_name, turns, cost], project.id, turns, cost)


## 开辟洞府：需已有修炼分峰，且弟子身处该灵峰。
static func open_cave(state: GameState, config: Dictionary, peak_id: String, disciple_id: String) -> Dictionary:
	var peak: SpiritPeak = find_peak(state, peak_id)
	if peak == null:
		return fail_result("灵峰不存在: " + peak_id)
	var sect: Sect = find_sect(state, peak.sectId)
	if sect == null:
		return fail_result("灵峰所属宗门不存在")
	if CityRules.building_count(peak, Enums.Building.XIU_LIAN_FEN_FENG) == 0:
		return fail_result("需先建造修炼分峰方可开辟洞府")
	var disciple: Disciple = find_disciple(state, disciple_id)
	if disciple == null:
		return fail_result("弟子不存在: " + disciple_id)
	if disciple.sectId != sect.id:
		return fail_result("弟子不属于该宗门")
	if disciple.tileId != peak.tileId:
		return fail_result("弟子需身处该灵峰方可分配洞府")
	var building: Dictionary = config["building"]
	var cost: int = int(building["caveCost"])
	var turns: int = int(building["caveTurns"])
	if _power(sect) < cost:
		return fail_result("灵力不足(%d/%d)" % [_power(sect), cost])
	_set_power(sect, _power(sect) - cost)
	var project: Project = _new_project(state, Project.TYPE_CAVE, "开辟洞府(%s)" % disciple.name, turns, cost)
	project.discipleId = disciple_id
	peak.projectQueue.append(project)
	state.eventLog.append("[灵峰] %s 为 %s 开辟洞府, 需 %d 回合" % [peak.name, disciple.name, turns])
	return ok_result("已加入项目队列: 为 %s 开辟洞府, 需 %d 回合, 消耗 %d 灵力" % [disciple.name, turns, cost], project.id, turns, cost)


## 灵峰防御加固。
static func fortify_peak(state: GameState, config: Dictionary, peak_id: String) -> Dictionary:
	var peak: SpiritPeak = find_peak(state, peak_id)
	if peak == null:
		return fail_result("灵峰不存在: " + peak_id)
	var sect: Sect = find_sect(state, peak.sectId)
	if sect == null:
		return fail_result("灵峰所属宗门不存在")
	var building: Dictionary = config["building"]
	var cost: int = int(building["fortifyCost"])
	var turns: int = int(building["fortifyTurns"])
	if _power(sect) < cost:
		return fail_result("灵力不足(%d/%d)" % [_power(sect), cost])
	_set_power(sect, _power(sect) - cost)
	var project: Project = _new_project(state, Project.TYPE_FORTIFY, "灵峰防御加固", turns, cost)
	peak.projectQueue.append(project)
	state.eventLog.append("[灵峰] %s 防御加固, 需 %d 回合" % [peak.name, turns])
	return ok_result("已加入项目队列: 防御加固 %s, 需 %d 回合, 消耗 %d 灵力" % [peak.name, turns, cost], project.id, turns, cost)


## 区域选址建造：入队 `city.district.turns` 回合。
static func found_district(state: GameState, config: Dictionary, sect_id: String, peak_id: String, district_type_id: String, tile_id: String) -> Dictionary:
	var sect: Sect = find_sect(state, sect_id)
	if sect == null:
		return fail_result("宗门不存在: " + sect_id)
	var peak: SpiritPeak = find_peak(state, peak_id)
	if peak == null:
		return fail_result("灵峰不存在: " + peak_id)
	if peak.sectId != sect.id:
		return fail_result("灵峰不属于该宗门")
	var tile: HexTile = state.tiles.get(tile_id)
	var blocker: String = CityRules.can_found_district(state, config, peak, district_type_id, tile)
	if not blocker.is_empty():
		return fail_result(blocker)
	for project: Project in peak.projectQueue:
		if project.type == Project.TYPE_DISTRICT and project.targetId == tile_id:
			return fail_result("该地块的区域正在兴建中")
	var district_config: Dictionary = config["city"]["district"]
	var cost: int = int(district_config["costs"][district_type_id])
	var turns: int = int(district_config["turns"][district_type_id])
	if _power(sect) < cost:
		return fail_result("灵力不足(%d/%d)" % [_power(sect), cost])
	_set_power(sect, _power(sect) - cost)
	var display_name: String = str(Enums.DistrictType.NAMES.get(district_type_id, district_type_id))
	var project: Project = _new_project(state, Project.TYPE_DISTRICT, "兴建" + display_name, turns, cost)
	project.targetId = tile_id
	project.districtType = district_type_id
	peak.projectQueue.append(project)
	var reasons: Array[String] = CityRules.district_adjacency(state, config, peak, district_type_id, tile_id)
	var hint: String = "" if reasons.is_empty() else "(邻接: %s)" % "、".join(reasons)
	state.eventLog.append("[区域] %s 在 %s 兴建%s, 需 %d 回合" % [sect.name, tile_id, display_name, turns])
	return ok_result("已加入项目队列: 兴建%s(%s), 需 %d 回合, 消耗 %d 灵力%s" % [display_name, tile_id, turns, cost, hint], project.id, turns, cost)


## 指派劳力：一格一份人力，无空闲人口或被别峰占用则失败。
static func assign_worker(state: GameState, config: Dictionary, peak_id: String, tile_id: String) -> Dictionary:
	var peak: SpiritPeak = find_peak(state, peak_id)
	if peak == null:
		return fail_result("灵峰不存在: " + peak_id)
	var sect: Sect = find_sect(state, peak.sectId)
	if sect == null:
		return fail_result("灵峰所属宗门不存在")
	var tile: HexTile = state.tiles.get(tile_id)
	if tile == null:
		return fail_result("地块不存在: " + tile_id)
	if peak.workedTileIds.has(tile_id):
		return fail_result("该地块已有人口耕作")
	if peak.freeWorkers <= 0:
		return fail_result("无空闲人口可指派(人口%d, 已耕作%d格)" % [peak.population, peak.workedTileIds.size()])
	if tile.ownerSectId != sect.id:
		return fail_result("只能耕作本宗地块")
	if tile.danger:
		return fail_result("险地无法耕作")
	if not tile.districtId.is_empty() and tile.id != peak.tileId:
		return fail_result("该地块已被区域占用")
	if not tile.workedByPeakId.is_empty() and tile.workedByPeakId != peak.id:
		return fail_result("该地块已被 %s 的人口耕种" % tile.workedByPeakId)
	if not state.tiles.has(peak.tileId):
		return fail_result("灵峰地块缺失")
	var center: HexTile = state.tiles[peak.tileId]
	var radius: int = CityRules.work_radius(config)
	var distance: int = Hex.distance(Vector2i(tile.q, tile.r), Vector2i(center.q, center.r))
	if distance > radius:
		return fail_result("超出灵峰辐射范围(半径%d格, 此处%d格)" % [radius, distance])
	CityRules.assign(state, config, peak, tile)
	var preview: Dictionary = EconomyRules.tile_yield_preview(state, config, tile)
	state.eventLog.append("[城市] %s 指派人口耕作 %s" % [peak.name, tile_id])
	return ok_result("%s 指派人口耕作 %s, 产出 %s" % [peak.name, tile_id, _yield_text(preview)])


## 撤回劳力：地块立刻停产。
static func unassign_worker(state: GameState, config: Dictionary, peak_id: String, tile_id: String) -> Dictionary:
	var peak: SpiritPeak = find_peak(state, peak_id)
	if peak == null:
		return fail_result("灵峰不存在: " + peak_id)
	var tile: HexTile = state.tiles.get(tile_id)
	if tile == null or not peak.workedTileIds.has(tile_id):
		return fail_result("该地块不由 %s 耕作" % peak.name)
	CityRules.unassign(peak, tile)
	state.eventLog.append("[城市] %s 撤回 %s 上的人口" % [peak.name, tile_id])
	return ok_result("%s 撤回 %s 上的人口, 该地块停产" % [peak.name, tile_id])


# ---------------------------------------------------------------------------
# 项目队列推进（SPIRIT_PEAK 阶段）
# ---------------------------------------------------------------------------

## 推进一座灵峰的项目队列：逐项 `turnsRemaining -= 1`，归零则出队并结算落成。
static func advance_projects(state: GameState, config: Dictionary, sect: Sect, peak: SpiritPeak) -> void:
	var index: int = 0
	while index < peak.projectQueue.size():
		var project: Project = peak.projectQueue[index]
		project.turnsRemaining -= 1
		if project.turnsRemaining > 0:
			index += 1
			continue
		peak.projectQueue.remove_at(index)
		_complete_project(state, config, sect, peak, project)


static func _complete_project(state: GameState, config: Dictionary, sect: Sect, peak: SpiritPeak, project: Project) -> void:
	match project.type:
		Project.TYPE_FOUND_PEAK:
			_complete_found_peak(state, config, sect, project)
		Project.TYPE_BUILD, Project.TYPE_SUB_PEAK:
			_complete_building(state, config, sect, peak, project)
		Project.TYPE_CAVE:
			_complete_cave(state, config, sect, peak, project)
		Project.TYPE_FORTIFY:
			peak.defense += int(config["building"]["fortifyDefenseBonus"])
			state.eventLog.append("[灵峰] %s 防御加固完成, 防御 %d" % [peak.name, peak.defense])
		Project.TYPE_DISTRICT:
			_complete_district(state, config, sect, peak, project)
		Project.TYPE_RECRUITMENT:
			DaoAction.complete_recruitment(state, config, sect, peak, project)
		_:
			state.eventLog.append("[灵峰] 未知项目类型: " + project.type)


## 公开入口：供 `accelerateProject` 在加速到 0 时即时落成（避免绕过 `_complete_project` 分派）。
static func complete_project_now(state: GameState, config: Dictionary, sect: Sect, peak: SpiritPeak, project: Project) -> void:
	_complete_project(state, config, sect, peak, project)


## 开峰落成：新增灵峰、接管地块与节点、铺首府区与首批人口、重算视野。
static func _complete_found_peak(state: GameState, config: Dictionary, sect: Sect, project: Project) -> void:
	if not state.tiles.has(project.targetId):
		state.eventLog.append("[灵峰] %s 的开峰目标地块缺失, 项目作废" % sect.name)
		return
	var tile: HexTile = state.tiles[project.targetId]
	if not tile.ownerSectId.is_empty() and tile.ownerSectId != sect.id:
		state.eventLog.append("[灵峰] %s 的开峰目标地块 %s 已被他人抢占, 项目作废" % [sect.name, project.targetId])
		return
	var peak: SpiritPeak = SpiritPeak.new()
	peak.id = "peak_%s_%d" % [sect.id, sect.spiritPeaks.size() + 1]
	peak.name = "%s·灵峰%d" % [sect.name, sect.spiritPeaks.size() + 1]
	peak.sectId = sect.id
	peak.tileId = tile.id
	peak.capital = false
	peak.level = 1
	peak.population = int(config["city"]["startPopulation"])
	peak.capacity = int(config["spiritPeak"]["baseDiscipleCapacity"])
	peak.defense = int(config["spiritPeak"]["baseDefense"])
	peak.qiYun = 0
	peak.qiYunMax = int(config["spiritPeak"]["baseQiYunMax"])
	peak.stability = float(config["city"]["stabilityBase"])
	peak.food = 0.0
	peak.foodProgress = 0.0
	peak.fengZhuId = project.discipleId
	sect.spiritPeaks.append(peak)
	tile.ownerSectId = sect.id
	var district: District = CityRules.new_district(peak, Enums.DistrictType.SHOU_FU_QU, tile.id, Enums.DistrictType.NAMES[Enums.DistrictType.SHOU_FU_QU])
	district.id = "capital_%s" % peak.id
	peak.districts.append(district)
	tile.districtId = district.id
	if not tile.nodeId.is_empty() and state.nodes.has(tile.nodeId):
		state.nodes[tile.nodeId].ownerSectId = sect.id
	var founder: Disciple = find_disciple(state, project.discipleId)
	if founder != null and founder.tileId == tile.id:
		founder.assignedPeakId = peak.id
	peak.housing = CityRules.housing_of(state, config, peak)
	CityRules.sync_free_workers(peak)
	VisionCalculator.recalculate(state, config)
	EconomyRules.settle_city(state, config, sect)
	state.eventLog.append("[灵峰] %s 建成, 人口%d, 住房%d" % [peak.name, peak.population, peak.housing])


## 建筑落成：核心/分峰归入可收纳它的区域，无则归首府区。
static func _complete_building(state: GameState, config: Dictionary, sect: Sect, peak: SpiritPeak, project: Project) -> void:
	var building_type: String = project.buildingType
	var display_name: String = str(Enums.Building.NAMES.get(building_type, building_type))
	var host: District = _host_district(peak, building_type)
	var building_id: String = "building_%s_%s" % [peak.id, building_type]
	if CityRules.building_count(peak, building_type) > 0:
		building_id = "building_%s_%s_%d" % [peak.id, building_type, peak.buildings.size() + 1]
	peak.buildings[building_id] = {"id": building_id, "type": building_type, "name": display_name, "level": 1, "districtId": host.id}
	if not host.buildings.has(building_type):
		host.buildings.append(building_type)
	if building_type == Enums.Building.HU_SHAN_JIAN_ZHEN:
		peak.defense += int(config["faction"]["zongMen"]["uniqueBuildingDefenseBonus"])
	peak.housing = CityRules.housing_of(state, config, peak)
	state.eventLog.append("[灵峰] %s 的%s 落成(归%s)" % [peak.name, display_name, host.typeName])


## 洞府落成：住房 +1（`housingPerCave`）、维护按副峰计。
static func _complete_cave(state: GameState, config: Dictionary, sect: Sect, peak: SpiritPeak, project: Project) -> void:
	var disciple: Disciple = find_disciple(state, project.discipleId)
	var cave_id: String = "cave_%s_%s" % [peak.id, project.discipleId]
	var cave_name: String = "洞府·%s" % (disciple.name if disciple != null else project.discipleId)
	peak.buildings[cave_id] = {"id": cave_id, "type": "CAVE", "name": cave_name, "level": 1, "districtId": ""}
	peak.housing = CityRules.housing_of(state, config, peak)
	state.eventLog.append("[灵峰] %s 的%s 落成" % [peak.name, cave_name])


## 区域落成：在目标地块落区域并同步占地标记；原先在此耕作的人口撤离。
static func _complete_district(state: GameState, config: Dictionary, sect: Sect, peak: SpiritPeak, project: Project) -> void:
	var tile: HexTile = state.tiles.get(project.targetId)
	var blocker: String = CityRules.can_found_district(state, config, peak, project.districtType, tile)
	if not blocker.is_empty():
		state.eventLog.append("[区域] %s 的%s 工地 %s 已不合格(%s), 项目作废" % [sect.name, peak.name, project.targetId, blocker])
		return
	var display_name: String = str(Enums.DistrictType.NAMES.get(project.districtType, project.districtType))
	var district: District = CityRules.new_district(peak, project.districtType, project.targetId, "%s·%s" % [peak.name, display_name])
	peak.districts.append(district)
	tile.districtId = district.id
	if not tile.workedByPeakId.is_empty():
		var worker_peak: SpiritPeak = find_peak(state, tile.workedByPeakId)
		if worker_peak != null:
			CityRules.unassign(worker_peak, tile)
	peak.housing = CityRules.housing_of(state, config, peak)
	state.eventLog.append("[区域] %s 在 %s 建成%s" % [sect.name, district.tileId, display_name])


## 建筑归属：优先落进能收纳它的已建区域，否则落首府区。
static func _host_district(peak: SpiritPeak, building_type: String) -> District:
	for district: District in peak.districts:
		if district.type == Enums.DistrictType.SHOU_FU_QU:
			continue
		if _district_accepts(district.type, building_type):
			return district
	for district: District in peak.districts:
		if district.type == Enums.DistrictType.SHOU_FU_QU:
			return district
	# 兜底：新建首府区（旧存档缺首府区时不崩）
	var home: District = CityRules.new_district(peak, Enums.DistrictType.SHOU_FU_QU, peak.tileId, Enums.DistrictType.NAMES[Enums.DistrictType.SHOU_FU_QU])
	home.id = "capital_%s" % peak.id
	peak.districts.append(home)
	return home


## 区域可收纳的建筑（对齐 1.0 `DistrictType.accepts`）。
static func _district_accepts(district_type: String, building_type: String) -> bool:
	match district_type:
		"XIU_LIAN_QU":
			return building_type == Enums.Building.XIU_LIAN_FEN_FENG or building_type == Enums.Building.JIANG_DAO_FEN_FENG
		"DAN_QI_QU":
			return building_type == Enums.Building.DAN_TANG_FEN_FENG or building_type == Enums.Building.QI_TANG_FEN_FENG
		"CANG_JING_QU":
			return building_type == Enums.Building.CANG_JING_GE
	return false


# ---------------------------------------------------------------------------
# 只读查询
# ---------------------------------------------------------------------------

## `queryBuildOptions`：`{sectId, sectName, options[]}`。
static func query_build_options(state: GameState, config: Dictionary, sect_id: String) -> Dictionary:
	var sect: Sect = find_sect(state, sect_id)
	if sect == null:
		return {"sectId": sect_id, "sectName": "", "options": []}
	var building: Dictionary = config["building"]
	var materials: Dictionary = sect.resources.get("materials", {})
	var power: int = _power(sect)
	var options: Array[Dictionary] = []
	for building_type: String in Enums.Building.ALL:
		var check: Dictionary = CityRules.can_build(state, config, _peak_of_sect(sect, building_type), building_type)
		var cost: int = int(building["costs"].get(building_type, 0))
		var material_cost: Dictionary = building["materialCosts"].get(building_type, {})
		var affordable: bool = power >= cost
		for material: Variant in material_cost.keys():
			if int(materials.get(material, 0)) < int(material_cost[material]):
				affordable = false
		options.append({
			"type": building_type,
			"displayName": str(Enums.Building.NAMES.get(building_type, building_type)),
			"core": Enums.Building.CORE.has(building_type),
			"factionOnly": str(building["factionOnly"].get(building_type, "")),
			"allowed": bool(check["allowed"]),
			"cost": cost,
			"baseCost": cost,
			"turns": int(building["turns"].get(building_type, 0)),
			"materialCost": material_cost.duplicate(true),
			"affordable": affordable,
		})
	return {"sectId": sect.id, "sectName": sect.name, "options": options}


## `queryDistrictSites`：`{sectId, peakId, districtTypeId, sites[], siteCount}`。
static func query_district_sites(state: GameState, config: Dictionary, sect_id: String, peak_id: String, district_type_id: String) -> Dictionary:
	var sect: Sect = find_sect(state, sect_id)
	var peak: SpiritPeak = find_peak(state, peak_id)
	var sites: Array[Dictionary] = []
	if sect != null and peak != null and peak.sectId == sect.id:
		for tile: HexTile in CityRules.workable_tiles(state, config, sect, peak):
			if not CityRules.can_found_district(state, config, peak, district_type_id, tile).is_empty():
				continue
			sites.append({
				"tileId": tile.id,
				"type": district_type_id,
				"yield": CityRules.district_yield(state, config, peak, district_type_id, tile.id),
				"adjacencyReasons": CityRules.district_adjacency(state, config, peak, district_type_id, tile.id),
			})
	sites.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var total_a: int = _yield_total(a["yield"])
		var total_b: int = _yield_total(b["yield"])
		if total_a != total_b:
			return total_a > total_b
		return str(a["tileId"]) < str(b["tileId"]))
	return {"sectId": sect_id, "peakId": peak_id, "districtTypeId": district_type_id, "sites": sites, "siteCount": sites.size()}


## `queryAssignableTiles`：`{peakId, tiles[], tileCount}`。
static func query_assignable_tiles(state: GameState, config: Dictionary, peak_id: String) -> Dictionary:
	var peak: SpiritPeak = find_peak(state, peak_id)
	var tiles: Array[Dictionary] = []
	if peak != null:
		var sect: Sect = find_sect(state, peak.sectId)
		if sect != null:
			for tile: HexTile in CityRules.assignable_tiles(state, config, sect, peak):
				tiles.append({
					"tileId": tile.id,
					"q": tile.q,
					"r": tile.r,
					"terrain": tile.baseTerrain,
					"danger": tile.danger,
					"ownerSectId": tile.ownerSectId,
					"nodeId": tile.nodeId,
					"luxuryType": tile.luxuryType,
				})
	return {"peakId": peak_id, "tiles": tiles, "tileCount": tiles.size()}


## `queryCityDetail`：城市面板数据（不含 `loyalty`，裁决二；追加 `districtTypes`）。
static func query_city_detail(state: GameState, config: Dictionary, peak_id: String) -> Dictionary:
	var peak: SpiritPeak = find_peak(state, peak_id)
	if peak == null:
		return {"found": false, "peakId": peak_id}
	var sect: Sect = find_sect(state, peak.sectId)
	var districts: Array[Dictionary] = []
	for district: District in peak.districts:
		districts.append({
			"id": district.id,
			"name": district.name,
			"type": district.type,
			"typeName": district.typeName,
			"level": district.level,
			"populationAssigned": 1 if peak.workedTileIds.has(district.tileId) else 0,
			"buildings": district.buildings.duplicate(),
		})
	var district_types: Array[Dictionary] = []
	for district_type: String in CityRules.district_type_ids():
		district_types.append({"id": district_type, "name": str(Enums.DistrictType.NAMES.get(district_type, district_type))})
	return {
		"found": true,
		"peakId": peak.id,
		"name": peak.name,
		"level": peak.level,
		"capital": peak.capital,
		"defense": peak.defense,
		"qiYun": peak.qiYun,
		"qiYunMax": peak.qiYunMax,
		"population": peak.population,
		"food": peak.food,
		"stability": peak.stability,
		"tileId": peak.tileId,
		"workedTileIds": peak.workedTileIds.duplicate(),
		"freeWorkers": peak.freeWorkers,
		"sectId": peak.sectId,
		"sectName": sect.name if sect != null else "",
		"housing": CityRules.housing_of(state, config, peak),
		"foodBalance": EconomyRules.food_balance(state, config, peak),
		"outputMultiplier": EconomyRules.output_multiplier(state, config, peak),
		"cityYield": EconomyRules.city_yield(state, config, peak),
		"districts": districts,
		"builtDistrictCount": CityRules.built_districts(peak).size(),
		"districtTypes": district_types,
	}


# ---------------------------------------------------------------------------
# 内部工具
# ---------------------------------------------------------------------------

static func _peak_of_sect(sect: Sect, _building_type: String) -> SpiritPeak:
	return _capital_peak(sect)


static func _yield_total(yields: Dictionary) -> int:
	var total: int = 0
	for key: Variant in yields.keys():
		var value: Variant = yields[key]
		if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
			total += int(round(float(value)))
	return total


static func _yield_text(yields: Dictionary) -> String:
	var parts: Array[String] = []
	for key: String in EconomyRules.YIELD_KEYS:
		var amount: int = int(yields.get(key, 0))
		if amount != 0:
			parts.append("%s%d" % [_resource_label(key), amount])
	return "/".join(parts)


static func _resource_label(resource: String) -> String:
	match resource:
		"food":
			return "粮"
		"spiritPower":
			return "灵"
		"spiritStones":
			return "石"
		"daoPoints":
			return "道"
		"qiYun":
			return "气运"
	return resource
