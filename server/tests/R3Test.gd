extends Node
## R3 自动验收：经济结算 + 灵峰/城市 + 建筑/区域/劳力/改良/道路。
##
## 无头运行：`godot --headless --path server res://tests/R3Test.tscn`，
## 全绿打印 `R3_PASS checks=N` 并退出码 0，否则 `R3_FAIL ...` 退出码 1。
##
## 断言全部**独立复算**（不直接复用被测函数的返回值作为期望值来源）。
## 开局每宗只拥有主峰所在地块（`SetupInitializer`），故区域/劳力/改良相关用例
## 以「测试夹具」显式把主峰邻格划归本宗（`_claim_neighbors`），这是对规则的单元验证，
## 不代表真实开局领土（真实扩张走气运满溢吞并，见 `_test_annex`）。

var _failures: Array[String] = []
var _checks: int = 0
var _config: Dictionary = {}
var _finished: bool = false
var _started: int = Time.get_ticks_msec()


func _process(_delta: float) -> void:
	if not _finished and Time.get_ticks_msec() - _started > 240000:
		printerr("R3_FAIL 测试未正常完成（可能运行时脚本错误）")
		get_tree().quit(1)


func _ready() -> void:
	var loaded: Dictionary = ConfigLoader.load_from_file(ConfigLoader.default_path())
	_check(bool(loaded["ok"]), "配置可加载")
	_config = loaded["config"]
	_check(ConfigValidator.validate(_config).is_empty(), "配置通过深层验证")
	_test_registration()
	_test_found_peak()
	_test_buildings()
	_test_districts()
	_test_workers()
	_test_improvements()
	_test_tile_yield()
	_test_settlement()
	_test_roads()
	_test_annex()
	_test_determinism()
	_finished = true
	if _failures.is_empty():
		print("R3_PASS checks=%d" % _checks)
		get_tree().quit(0)
	else:
		for message: String in _failures:
			printerr("R3_FAIL ", message)
		print("R3_FAIL checks=%d failures=%d" % [_checks, _failures.size()])
		get_tree().quit(1)


# ---------------------------------------------------------------------------
# 0. 命令登记
# ---------------------------------------------------------------------------

const R3_COMMANDS: Array[String] = [
	"foundSpiritPeak", "appointBuilder", "constructBuilding", "queryBuildOptions", "openCave",
	"fortifyPeak", "foundDistrict", "queryDistrictSites", "assignWorker", "unassignWorker",
	"queryAssignableTiles", "queryCityDetail", "buildImprovement", "repairImprovement",
	"queryImprovementOptions",
]


func _test_registration() -> void:
	var dispatcher: CommandDispatcher = CommandDispatcher.new(_config)
	var implemented: Array = dispatcher.implemented_commands()
	for command: String in R3_COMMANDS:
		_check(implemented.has(command), "已登记 R3 命令：" + command)
	_check(implemented.size() >= 23, "已登记命令不少于 R3 的 23 条（ping + 7 + 15）")
	# 未开局：全部 R3 命令 NO_GAME
	for command: String in R3_COMMANDS:
		var response: Dictionary = _request(dispatcher, command, {})
		_check(response.get("errorCode") == "NO_GAME", "%s 开局前 NO_GAME" % command)


# ---------------------------------------------------------------------------
# 1. 开峰（foundSpiritPeak）
# ---------------------------------------------------------------------------

func _test_found_peak() -> void:
	var dispatcher: CommandDispatcher = _new_game("123456")
	var state: GameState = dispatcher.state
	var sect: Sect = state.sects[0]
	var leader: Disciple = sect.disciples[0]
	_boost(sect, 5000)
	var found_turns: int = int(_config["spiritPeak"]["foundTurns"])
	var cost: int = int(_config["spiritPeak"]["foundCost"]["zongMen"])

	# ① 山岳格：success=false（裁决四）
	var mountain: String = _find_tile(state, true, false)
	_check(not mountain.is_empty(), "地图存在山岳格")
	if not mountain.is_empty():
		leader.tileId = mountain
		var blocked: Dictionary = _result(dispatcher, "foundSpiritPeak", {"discipleId": leader.id, "tileId": mountain})
		_check(not bool(blocked.get("success", true)), "山岳开峰 success=false")
		_check(str(blocked.get("message", "")).contains("山岳"), "山岳开峰 message 含「山岳」")
		_check(str(blocked.get("projectId", "x")).is_empty(), "山岳开峰 projectId 为空")

	# ② 合法格：入队 Project（turnsRequired == foundTurns）
	var legal: String = _find_tile(state, false, true)
	_check(not legal.is_empty(), "地图存在无主非山岳格")
	if legal.is_empty():
		return
	leader.tileId = legal
	var power_before: int = int(sect.resources["spiritPower"])
	var accepted: Dictionary = _result(dispatcher, "foundSpiritPeak", {"discipleId": leader.id, "tileId": legal})
	_check(bool(accepted.get("success", false)), "合法格开峰 success=true")
	_check(not str(accepted.get("projectId", "")).is_empty(), "开峰返回 projectId")
	_check(int(accepted.get("turnsRequired", -1)) == found_turns, "开峰 turnsRequired == spiritPeak.foundTurns")
	_check(int(accepted.get("spiritPowerCost", -1)) == cost, "开峰 spiritPowerCost == spiritPeak.foundCost.zongMen")
	_check(int(sect.resources["spiritPower"]) == power_before - cost, "开峰扣灵力 == foundCost")
	var capital: SpiritPeak = _capital(sect)
	_check(capital.projectQueue.size() == 1, "开峰项目入主峰队列")
	_check(capital.projectQueue[0].turnsRemaining == found_turns, "项目 turnsRemaining == foundTurns")

	# ③ 推进 foundTurns 回合（nextTurn = begin + finish，项目在 SPIRIT_PEAK 阶段推进）
	var peaks_before: int = sect.spiritPeaks.size()
	for _i: int in range(found_turns):
		_request(dispatcher, "nextTurn")
	_check(sect.spiritPeaks.size() == peaks_before + 1, "foundTurns 回合后灵峰落成")
	var founded: SpiritPeak = sect.spiritPeaks[sect.spiritPeaks.size() - 1]
	_check(founded.tileId == legal, "新灵峰坐落于目标格")
	_check(not founded.capital, "新灵峰为副峰")
	_check(founded.level == 1, "新灵峰等级 1")
	_check(founded.population == int(_config["city"]["startPopulation"]), "新灵峰人口 == city.startPopulation")
	_check(founded.qiYunMax == int(_config["spiritPeak"]["baseQiYunMax"]), "新灵峰气运上限 == baseQiYunMax")
	_check(state.tiles[legal].ownerSectId == sect.id, "新灵峰地块归本宗")
	_check(founded.districts.size() == 1 and founded.districts[0].type == "SHOU_FU_QU", "新灵峰自带首府区")
	# ④ view：spiritPeaks 增一
	var view: Dictionary = _view(dispatcher)
	_check((view["sects"][0]["spiritPeaks"] as Array).size() == peaks_before + 1, "view.sects[player].spiritPeaks 增一")


# ---------------------------------------------------------------------------
# 2. 建筑（constructBuilding / queryBuildOptions）
# ---------------------------------------------------------------------------

func _test_buildings() -> void:
	var building: Dictionary = _config["building"]
	var faction_rejected: Array[String] = ["ZU_CI", "WANG_CHAO_DI_DU"]  # 玩家为 ZONG_MEN
	for building_type: String in Enums.Building.ALL:
		var dispatcher: CommandDispatcher = _new_game("123456")
		var state: GameState = dispatcher.state
		var sect: Sect = state.sects[0]
		var peak: SpiritPeak = _capital(sect)
		var cost: int = int(building["costs"][building_type])
		var turns: int = int(building["turns"][building_type])
		var material_cost: Dictionary = building["materialCosts"].get(building_type, {})
		# 精确配平：灵力恰好够、材料恰好够
		sect.resources["spiritPower"] = cost
		sect.resources["materials"] = material_cost.duplicate(true)
		var result: Dictionary = _result(dispatcher, "constructBuilding", {"peakId": peak.id, "buildingType": building_type})
		var should_ok: bool = not faction_rejected.has(building_type)
		_check(bool(result.get("success", false)) == should_ok, "constructBuilding %s 可建性 == 独立判定" % building_type)
		if not should_ok:
			_check(str(result.get("message", "")).contains("专属"), "%s 流派专属拒绝文案" % building_type)
			continue
		_check(int(result.get("turnsRequired", -1)) == turns, "%s turnsRequired == building.turns" % building_type)
		_check(int(result.get("spiritPowerCost", -1)) == cost, "%s spiritPowerCost == building.costs" % building_type)
		_check(not str(result.get("projectId", "")).is_empty(), "%s 入队 projectId" % building_type)
		_check(int(sect.resources["spiritPower"]) == 0, "%s 精确扣灵力" % building_type)
		for material: Variant in material_cost.keys():
			_check(int((sect.resources["materials"] as Dictionary).get(material, -1)) == 0, "%s 精确扣材料 %s" % [building_type, material])
		_check(peak.projectQueue.size() == 1, "%s 项目入队" % building_type)
		_check(peak.projectQueue[0].buildingType == building_type, "%s 项目 buildingType 正确" % building_type)

	# 材料不足 → success=false
	var dispatcher2: CommandDispatcher = _new_game("123456")
	var sect2: Sect = dispatcher2.state.sects[0]
	var peak2: SpiritPeak = _capital(sect2)
	sect2.resources["spiritPower"] = 5000
	sect2.resources["materials"] = {}
	var poor: Dictionary = _result(dispatcher2, "constructBuilding", {"peakId": peak2.id, "buildingType": "CANG_JING_GE"})
	_check(not bool(poor.get("success", true)), "材料不足 constructBuilding success=false")
	_check(str(poor.get("message", "")).contains("战略资源不足"), "材料不足文案")
	# 灵力不足 → success=false
	sect2.resources["spiritPower"] = int(building["costs"]["SHAN_MEN"]) - 1
	var no_power: Dictionary = _result(dispatcher2, "constructBuilding", {"peakId": peak2.id, "buildingType": "SHAN_MEN"})
	_check(not bool(no_power.get("success", true)), "灵力不足 constructBuilding success=false")
	# 枚举非法 → BAD_PARAMS
	_check(_request(dispatcher2, "constructBuilding", {"peakId": peak2.id, "buildingType": "NOPE"}).get("errorCode") == "BAD_PARAMS", "非法建筑枚举 BAD_PARAMS")
	_check(_request(dispatcher2, "constructBuilding", {"peakId": peak2.id}).get("errorCode") == "BAD_PARAMS", "缺 buildingType BAD_PARAMS")

	# 建筑落成 → buildings 记入 + 住房刷新（用 SHAN_MEN，3 回合）
	var dispatcher3: CommandDispatcher = _new_game("123456")
	var sect3: Sect = dispatcher3.state.sects[0]
	var peak3: SpiritPeak = _capital(sect3)
	_boost(sect3, 5000)
	var housing_before: int = CityRules.housing_of(dispatcher3.state, _config, peak3)
	_request(dispatcher3, "constructBuilding", {"peakId": peak3.id, "buildingType": "SHAN_MEN"})
	for _i: int in range(int(building["turns"]["SHAN_MEN"])):
		_request(dispatcher3, "nextTurn")
	_check(CityRules.building_count(peak3, "SHAN_MEN") == 1, "SHAN_MEN 落成 1 座")
	_check(CityRules.housing_of(dispatcher3.state, _config, peak3) == housing_before + int(_config["city"]["housingPerBuilding"]), "建筑落成住房 +housingPerBuilding")
	# 核心槽位唯一：再建山门被拒
	var again: Dictionary = _result(dispatcher3, "constructBuilding", {"peakId": peak3.id, "buildingType": "SHAN_MEN"})
	_check(not bool(again.get("success", true)), "核心建筑重复建造 success=false")
	# queryBuildOptions 只读、不返 view，且 options 覆盖 10 种
	var options_response: Dictionary = _request(dispatcher3, "queryBuildOptions", {"sectId": sect3.id})
	_check(bool(options_response.get("ok", false)), "queryBuildOptions ok")
	_check(not options_response.has("view"), "queryBuildOptions 不回 view（只读）")
	_check((options_response["result"]["options"] as Array).size() == 10, "queryBuildOptions 覆盖 10 种建筑")


# ---------------------------------------------------------------------------
# 3. 区域（foundDistrict / queryDistrictSites）
# ---------------------------------------------------------------------------

func _test_districts() -> void:
	var dispatcher: CommandDispatcher = _new_game("123456")
	var state: GameState = dispatcher.state
	var sect: Sect = state.sects[0]
	var peak: SpiritPeak = _capital(sect)
	_boost(sect, 9000)
	var claimed: Array[HexTile] = _claim_neighbors(state, sect, peak, 6)
	_check(claimed.size() >= 4, "夹具：主峰邻格已划归本宗")
	if claimed.size() < 4:
		return
	var district_type: String = "XIU_LIAN_QU"
	# ① queryDistrictSites：只读 + 逐 site 独立复算 adjacencyReasons / yield
	var sites_response: Dictionary = _request(dispatcher, "queryDistrictSites", {"sectId": sect.id, "peakId": peak.id, "districtTypeId": district_type})
	_check(bool(sites_response.get("ok", false)), "queryDistrictSites ok")
	_check(not sites_response.has("view"), "queryDistrictSites 不回 view（只读）")
	var result: Dictionary = sites_response["result"]
	_check(str(result["districtTypeId"]) == district_type, "sites.districtTypeId 回包")
	_check(int(result["siteCount"]) == (result["sites"] as Array).size(), "siteCount == sites.size()")
	_check((result["sites"] as Array).size() >= 1, "queryDistrictSites 返回候选格")
	var center: HexTile = state.tiles[peak.tileId]
	for site: Dictionary in result["sites"]:
		var tile: HexTile = state.tiles[str(site["tileId"])]
		_check(Hex.distance(Vector2i(tile.q, tile.r), Vector2i(center.q, center.r)) <= CityRules.work_radius(_config), "site 在工作半径内")
		var reference: Dictionary = _reference_adjacency(state, _config, district_type, tile.id)
		_check(_same_yield(site["yield"], reference["yield"]), "site %s yield 与独立复算一致" % tile.id)
		_check(_same_strings(site["adjacencyReasons"], reference["reasons"]), "site %s adjacencyReasons 与独立复算一致" % tile.id)

	# ② foundDistrict 成功（入队，turnsRequired == district.turns）
	var target: String = str((result["sites"] as Array)[0]["tileId"])
	var expected_turns: int = int(_config["city"]["district"]["turns"][district_type])
	var expected_cost: int = int(_config["city"]["district"]["costs"][district_type])
	var power_before: int = int(sect.resources["spiritPower"])
	var found: Dictionary = _result(dispatcher, "foundDistrict", {"sectId": sect.id, "peakId": peak.id, "districtTypeId": district_type, "tileId": target})
	_check(bool(found.get("success", false)), "foundDistrict success=true")
	_check(int(found.get("turnsRequired", -1)) == expected_turns, "foundDistrict turnsRequired == city.district.turns")
	_check(int(found.get("spiritPowerCost", -1)) == expected_cost, "foundDistrict spiritPowerCost == city.district.costs")
	_check(int(sect.resources["spiritPower"]) == power_before - expected_cost, "foundDistrict 扣灵力")
	# 落成
	for _i: int in range(expected_turns):
		_request(dispatcher, "nextTurn")
	_check(CityRules.built_districts(peak).size() == 1, "区域落成（built_districts == 1）")
	_check(state.tiles[target].districtId != "", "区域地块 districtId 已写")
	# ③ 超 maxDistrictsPerPeak → success=false（先补齐到上限，避免受地图邻格数量限制）
	var cap: int = int(_config["city"]["district"]["maxDistrictsPerPeak"])
	var free_tiles: Array[HexTile] = []
	for tile: HexTile in claimed:
		if tile.districtId.is_empty():
			free_tiles.append(tile)
	while CityRules.built_districts(peak).size() < cap and not free_tiles.is_empty():
		var tile: HexTile = free_tiles.pop_front()
		var probe: Dictionary = _result(dispatcher, "foundDistrict", {"sectId": sect.id, "peakId": peak.id, "districtTypeId": district_type, "tileId": tile.id})
		if not bool(probe.get("success", false)):
			continue
		for _i: int in range(expected_turns):
			_request(dispatcher, "nextTurn")
	# 若邻格不足，用夹具补齐至上限
	while CityRules.built_districts(peak).size() < cap:
		var filler: District = CityRules.new_district(peak, district_type, peak.tileId, "补位区")
		peak.districts.append(filler)
	_check(CityRules.built_districts(peak).size() == cap, "区域数达到 maxDistrictsPerPeak")
	var over_tile: HexTile = free_tiles[0] if not free_tiles.is_empty() else claimed[0]
	var over: Dictionary = _result(dispatcher, "foundDistrict", {"sectId": sect.id, "peakId": peak.id, "districtTypeId": district_type, "tileId": over_tile.id})
	_check(not bool(over.get("success", true)), "超 maxDistrictsPerPeak success=false")
	_check(str(over.get("message", "")).contains("已满"), "区域超上限文案")
	# ④ queryCityDetail：districtTypes 为 5 种可建；districts 含首府区
	var detail_response: Dictionary = _request(dispatcher, "queryCityDetail", {"peakId": peak.id})
	_check(not detail_response.has("view"), "queryCityDetail 不回 view（只读）")
	var detail: Dictionary = detail_response["result"]
	_check(bool(detail["found"]), "queryCityDetail.found=true")
	_check((detail["districtTypes"] as Array).size() == Enums.DistrictType.BUILDABLE.size(), "districtTypes == 5 种可建区域")
	_check((detail["districts"] as Array).size() == CityRules.built_districts(peak).size() + 1, "districts 含首府区")
	_check(detail["cityYield"] is Dictionary and detail["districts"] is Array, "queryCityDetail 结构齐备")
	# 灵峰不存在 → BAD_PARAMS
	var missing: Dictionary = _request(dispatcher, "queryCityDetail", {"peakId": "nope"})
	_check(missing.get("errorCode") == "BAD_PARAMS", "不存在 peakId queryCityDetail BAD_PARAMS")


# ---------------------------------------------------------------------------
# 4. 劳力（assignWorker / unassignWorker / queryAssignableTiles）
# ---------------------------------------------------------------------------

func _test_workers() -> void:
	var dispatcher: CommandDispatcher = _new_game("123456")
	var state: GameState = dispatcher.state
	var sect: Sect = state.sects[0]
	var peak: SpiritPeak = _capital(sect)
	_boost(sect, 5000)
	var claimed: Array[HexTile] = _claim_neighbors(state, sect, peak, 4)
	_check(claimed.size() >= 2, "夹具：主峰邻格已划归本宗")
	if claimed.size() < 2:
		return
	# ① queryAssignableTiles：只返回工作半径内、本宗归属格
	var tiles_response: Dictionary = _request(dispatcher, "queryAssignableTiles", {"peakId": peak.id})
	_check(not tiles_response.has("view"), "queryAssignableTiles 不回 view（只读）")
	var listed: Dictionary = tiles_response["result"]
	_check(int(listed["tileCount"]) == (listed["tiles"] as Array).size(), "tileCount == tiles.size()")
	var center: HexTile = state.tiles[peak.tileId]
	for entry: Dictionary in listed["tiles"]:
		var tile: HexTile = state.tiles[str(entry["tileId"])]
		_check(Hex.distance(Vector2i(tile.q, tile.r), Vector2i(center.q, center.r)) <= CityRules.work_radius(_config), "可指派格在工作半径内")
		_check(tile.ownerSectId == sect.id, "可指派格归本宗")

	# ② assignWorker：地块立刻产出、freeWorkers 递减
	var tile_a: HexTile = claimed[0]
	var free_before: int = peak.freeWorkers
	var assigned: Dictionary = _result(dispatcher, "assignWorker", {"peakId": peak.id, "tileId": tile_a.id})
	_check(bool(assigned.get("success", false)), "assignWorker success=true")
	_check(tile_a.workedByPeakId == peak.id, "assignWorker 后 tile.workedByPeakId == peakId")
	_check(peak.workedTileIds.has(tile_a.id), "peak.workedTileIds 记入")
	_check(peak.freeWorkers == free_before - 1, "assignWorker 后 freeWorkers 递减")
	var detail: Dictionary = _request(dispatcher, "queryCityDetail", {"peakId": peak.id})["result"]
	_check(int(detail["freeWorkers"]) == peak.freeWorkers, "queryCityDetail.freeWorkers 同步")
	_check(int(detail["population"]) == peak.population, "queryCityDetail.population 同步")
	# ③ unassignWorker：复原
	var released: Dictionary = _result(dispatcher, "unassignWorker", {"peakId": peak.id, "tileId": tile_a.id})
	_check(bool(released.get("success", false)), "unassignWorker success=true")
	_check(tile_a.workedByPeakId == "", "unassignWorker 后 workedByPeakId 清空")
	_check(peak.freeWorkers == free_before, "unassignWorker 后 freeWorkers 复原")
	# ④ 失败路径
	_check(not bool(_result(dispatcher, "unassignWorker", {"peakId": peak.id, "tileId": tile_a.id}).get("success", true)), "重复 unassign success=false")
	# 超半径格（主峰半径外 3 格的任意格）
	var far: String = _find_tile(state, false, false, Vector2i(center.q, center.r), CityRules.work_radius(_config) + 1)
	if not far.is_empty():
		state.tiles[far].ownerSectId = sect.id
		var far_result: Dictionary = _result(dispatcher, "assignWorker", {"peakId": peak.id, "tileId": far})
		_check(not bool(far_result.get("success", true)), "超辐射范围 assignWorker success=false")
		_check(str(far_result.get("message", "")).contains("辐射范围"), "超范围文案")
	# 非本宗地块
	var enemy_peak: SpiritPeak = state.sects[1].spiritPeaks[0]
	var enemy_tile: Dictionary = _result(dispatcher, "assignWorker", {"peakId": peak.id, "tileId": enemy_peak.tileId})
	_check(not bool(enemy_tile.get("success", true)), "他宗地块 assignWorker success=false")
	# 参数错误
	_check(_request(dispatcher, "assignWorker", {"peakId": peak.id}).get("errorCode") == "BAD_PARAMS", "缺 tileId BAD_PARAMS")
	_check(_request(dispatcher, "assignWorker", {"peakId": enemy_peak.id, "tileId": claimed[0].id}).get("errorCode") == "BAD_PARAMS", "他宗 peakId BAD_PARAMS")


# ---------------------------------------------------------------------------
# 5. 改良（appointBuilder / buildImprovement / repairImprovement / queryImprovementOptions）
# ---------------------------------------------------------------------------

func _test_improvements() -> void:
	var dispatcher: CommandDispatcher = _new_game("123456")
	var state: GameState = dispatcher.state
	var sect: Sect = state.sects[0]
	var peak: SpiritPeak = _capital(sect)
	_boost(sect, 5000)
	sect.resources["workPower"] = 5000
	var claimed: Array[HexTile] = _claim_neighbors(state, sect, peak, 6)
	_check(claimed.size() >= 5, "夹具：主峰邻格已划归本宗")
	if claimed.size() < 5:
		return
	# 清掉节点干扰，统一为丘陵
	for tile: HexTile in claimed:
		tile.nodeId = ""
		tile.relief = "HILL"
		tile.baseTerrain = "SPIRIT_PLAIN"
	var builder: Disciple = sect.disciples[1]  # 外门（LIAN_QI，realm level 1 <= builderMaxRealmLevel 2）
	# ① appointBuilder：金丹以上被拒；低阶成功且获 builderCharges
	var too_high: Dictionary = _result(dispatcher, "appointBuilder", {"sectId": sect.id, "discipleId": sect.disciples[0].id})
	_check(not bool(too_high.get("success", true)), "金丹宗主 appointBuilder success=false")
	var appointed: Dictionary = _result(dispatcher, "appointBuilder", {"sectId": sect.id, "discipleId": builder.id})
	_check(bool(appointed.get("success", false)), "低阶弟子 appointBuilder success=true")
	_check(builder.builderCharges == int(_config["improvement"]["builderCharges"]), "builderCharges == improvement.builderCharges")

	# ② queryImprovementOptions：逐项独立判定地形/道法门控
	var hill_tile: HexTile = claimed[0]
	var options_response: Dictionary = _request(dispatcher, "queryImprovementOptions", {"sectId": sect.id, "tileId": hill_tile.id})
	_check(not options_response.has("view"), "queryImprovementOptions 不回 view（只读）")
	var options: Dictionary = options_response["result"]
	var by_type: Dictionary = {}
	for option: Dictionary in options["options"]:
		by_type[str(option["type"])] = option
	_check(bool(by_type["LING_KUANG"]["buildable"]), "丘陵：灵矿 buildable=true")
	_check(bool(by_type["CAI_SHI_CHANG"]["buildable"]), "丘陵：采石场 buildable=true")
	_check(bool(by_type["QING_SHI_DAO_LU"]["buildable"]), "丘陵：青石道路 buildable=true")
	_check(bool(by_type["DONG_FU"]["buildable"]), "丘陵：洞府 buildable=true")
	_check(not bool(by_type["LING_TIAN_TI_TIAN"]["buildable"]), "丘陵：灵田梯田 buildable=false（需平地沃野+道法）")
	_check(not bool(by_type["JU_LING_ZHEN"]["buildable"]), "丘陵：聚灵阵 buildable=false（需道法 ju_ling_zhen）")
	_check(not bool(by_type["YAO_YUAN"]["buildable"]), "丘陵：药园 buildable=false（需丹器区）")
	_check(str(by_type["JU_LING_ZHEN"]["rejection"]).contains("道法"), "聚灵阵 rejection 提示需道法")
	_check(not by_type.has("LING_QUAN_XIU_SHAN"), "非灵泉地块不列灵泉修缮")

	# ③ buildImprovement：消耗 builderCharges 3→2→1→0，之后 success=false
	var charges: int = builder.builderCharges
	for index: int in range(claimed.size()):
		var tile: HexTile = claimed[index]
		builder.tileId = tile.id
		var work_before: int = int(sect.resources["workPower"])
		var cost: int = int(_config["improvement"]["byType"]["LING_KUANG"]["cost"])
		var built: Dictionary = _result(dispatcher, "buildImprovement", {"sectId": sect.id, "discipleId": builder.id, "tileId": tile.id, "improvementType": "LING_KUANG"})
		if charges > 0:
			_check(bool(built.get("success", false)), "buildImprovement 第%d次 success=true" % (index + 1))
			_check(builder.builderCharges == charges - 1, "buildImprovement 后 builderCharges 递减")
			_check(int(sect.resources["workPower"]) == work_before - cost, "buildImprovement 扣工力 == cost")
			_check(tile.improvementId != "", "改良写入 tile.improvementId")
			charges -= 1
		else:
			_check(not bool(built.get("success", true)), "builderCharges 用尽后 buildImprovement success=false")
			_check(str(built.get("message", "")).contains("建造次数"), "用尽文案")
	# ④ 同一格重复建 → success=false
	builder.builderCharges = 3
	builder.tileId = claimed[0].id
	var dup: Dictionary = _result(dispatcher, "buildImprovement", {"sectId": sect.id, "discipleId": builder.id, "tileId": claimed[0].id, "improvementType": "LING_KUANG"})
	_check(not bool(dup.get("success", true)), "已有改良地块重复建造 success=false")
	# ⑤ 建造者须身处施工地块
	builder.tileId = peak.tileId
	var away: Dictionary = _result(dispatcher, "buildImprovement", {"sectId": sect.id, "discipleId": builder.id, "tileId": claimed[1].id, "improvementType": "LING_KUANG"})
	_check(not bool(away.get("success", true)), "建造者不在场 success=false")
	# ⑥ repairImprovement：破损 → 修缮耗 repairCost 工力
	var improvement: Improvement = ImprovementRules.find_on_tile(state, claimed[0].id)
	_check(improvement != null, "地块上存在改良")
	if improvement != null:
		improvement.broken = true
		builder.tileId = claimed[0].id
		var work_before2: int = int(sect.resources["workPower"])
		var repair_cost: int = int(_config["improvement"]["repairCost"])
		var repaired: Dictionary = _result(dispatcher, "repairImprovement", {"sectId": sect.id, "discipleId": builder.id, "tileId": claimed[0].id})
		_check(bool(repaired.get("success", false)), "repairImprovement success=true")
		_check(not improvement.broken, "修缮后 broken=false")
		_check(int(sect.resources["workPower"]) == work_before2 - repair_cost, "repairImprovement 耗 repairCost 工力")
		# 完好再修 → false
		var again: Dictionary = _result(dispatcher, "repairImprovement", {"sectId": sect.id, "discipleId": builder.id, "tileId": claimed[0].id})
		_check(not bool(again.get("success", true)), "完好改良再修 success=false")
	# ⑦ 灵泉修缮：仅灵泉节点
	# 用未被 `builderCharges` 用尽的干净邻格（前面 3 次建造只落在 claimed[0..2]）
	var spring_tile: HexTile = claimed[4]
	spring_tile.nodeId = "test_ling_quan"
	spring_tile.relief = "FLAT"
	spring_tile.improvementId = ""
	var node: GameNode = GameNode.new()
	node.id = "test_ling_quan"
	node.type = "LING_QUAN"
	node.tileId = spring_tile.id
	node.ownerSectId = sect.id
	state.nodes["test_ling_quan"] = node
	var spring_options: Dictionary = _request(dispatcher, "queryImprovementOptions", {"sectId": sect.id, "tileId": spring_tile.id})["result"]
	var spring_by_type: Dictionary = {}
	for option: Dictionary in spring_options["options"]:
		spring_by_type[str(option["type"])] = option
	_check(spring_by_type.has("LING_QUAN_XIU_SHAN") and bool(spring_by_type["LING_QUAN_XIU_SHAN"]["buildable"]), "灵泉地块可建灵泉修缮")
	_check(not bool(spring_by_type["LING_KUANG"]["buildable"]), "灵泉地块不可建灵矿")
	# ⑧ 非本宗地块 → false
	var enemy_tile: String = state.sects[1].spiritPeaks[0].tileId
	builder.builderCharges = 3
	builder.tileId = enemy_tile
	var foreign: Dictionary = _result(dispatcher, "buildImprovement", {"sectId": sect.id, "discipleId": builder.id, "tileId": enemy_tile, "improvementType": "LING_KUANG"})
	_check(not bool(foreign.get("success", true)), "他宗地块 buildImprovement success=false")
	# ⑨ 枚举非法 → BAD_PARAMS
	_check(_request(dispatcher, "buildImprovement", {"sectId": sect.id, "discipleId": builder.id, "tileId": claimed[1].id, "improvementType": "NOPE"}).get("errorCode") == "BAD_PARAMS", "非法改良枚举 BAD_PARAMS")


# ---------------------------------------------------------------------------
# 6. 经济结算（apply_settlement）
# ---------------------------------------------------------------------------

## 地块产出构成（PRD §4.1.9 L315）：基底 + 海拔（丘陵石+1）+ 地貌 + 沿河粮+1 + 节点 + 改良。
## 逐项独立复算，不经由被测函数推导期望值。
func _test_tile_yield() -> void:
	var dispatcher: CommandDispatcher = _new_game("123456")
	var state: GameState = dispatcher.state
	var tile: HexTile = state.tiles[state.sects[0].spiritPeaks[0].tileId]
	# 用一座无节点、无地貌、无河流、无改良的平地作为基线
	var original: Dictionary = {
		"baseTerrain": tile.baseTerrain, "relief": tile.relief, "features": tile.features.duplicate(),
		"riverEdges": tile.riverEdges.duplicate(), "nodeId": tile.nodeId, "improvementId": tile.improvementId,
	}
	tile.baseTerrain = Enums.BaseTerrain.SPIRIT_PLAIN
	tile.relief = Enums.Relief.FLAT
	var no_features: Array[String] = []
	tile.features = no_features
	var no_edges: Array[int] = []
	tile.riverEdges = no_edges
	tile.nodeId = ""
	tile.improvementId = ""
	var plain: Dictionary = EconomyRules.tile_yield_preview(state, _config, tile)
	var base: Dictionary = _config["city"]["workYieldByTerrain"][Enums.BaseTerrain.SPIRIT_PLAIN]
	_check(_same_yield(plain, base), "平地基线产出 == workYieldByTerrain（粮%d 灵力%d）" % [int(base["food"]), int(base["spiritPower"])])

	# ① 丘陵：石 +map.relief.HILL.yield.spiritStones（PRD §4.1.3）
	tile.relief = Enums.Relief.HILL
	var hill: Dictionary = EconomyRules.tile_yield_preview(state, _config, tile)
	var hill_bonus: Dictionary = _config["map"]["relief"]["HILL"]["yield"]
	_check(int(hill["spiritStones"]) == int(base.get("spiritStones", 0)) + int(hill_bonus["spiritStones"]), "丘陵地块灵石 +%d" % int(hill_bonus["spiritStones"]))
	_check(int(hill["food"]) == int(base["food"]), "丘陵不改粮产")
	_check(int(_config["map"]["relief"]["FLAT"]["yield"].size()) == 0, "平地无海拔产出加成")
	_check(int(_config["map"]["relief"]["MOUNTAIN"]["yield"].size()) == 0, "山岳无海拔产出加成")

	# ② 沿河：粮 +map.river.foodBonus（PRD §4.1.5 L280）
	tile.relief = Enums.Relief.FLAT
	var river_edge: Array[int] = [0]
	tile.riverEdges = river_edge
	var riverside: Dictionary = EconomyRules.tile_yield_preview(state, _config, tile)
	_check(int(riverside["food"]) == int(base["food"]) + int(_config["map"]["river"]["foodBonus"]), "沿河地块粮 +%d" % int(_config["map"]["river"]["foodBonus"]))
	_check(int(riverside["spiritPower"]) == int(base["spiritPower"]), "沿河不改灵力产出")

	# ③ 叠加：丘陵 + 沿河 + 灵林地貌 + 灵田节点，逐项累加
	tile.relief = Enums.Relief.HILL
	var forest: Array[String] = [Enums.Feature.SPIRIT_FOREST]
	tile.features = forest
	var node: GameNode = GameNode.new()
	node.id = "test_ling_tian"
	node.type = Enums.NodeType.LING_TIAN
	node.tileId = tile.id
	state.nodes[node.id] = node
	tile.nodeId = node.id
	var stacked: Dictionary = EconomyRules.tile_yield_preview(state, _config, tile)
	var expected_food: int = int(base["food"]) + int(_config["map"]["features"][Enums.Feature.SPIRIT_FOREST]["yield"].get("food", 0)) + int(_config["map"]["river"]["foodBonus"]) + int(_config["city"]["workYieldByNode"][Enums.NodeType.LING_TIAN].get("food", 0))
	var expected_stones: int = int(base.get("spiritStones", 0)) + int(hill_bonus["spiritStones"])
	var expected_power: int = int(base["spiritPower"]) + int(_config["map"]["features"][Enums.Feature.SPIRIT_FOREST]["yield"].get("spiritPower", 0)) + int(_config["city"]["workYieldByNode"][Enums.NodeType.LING_TIAN].get("spiritPower", 0))
	_check(int(stacked["food"]) == expected_food, "叠加产出粮 == 独立累加(%d)" % expected_food)
	_check(int(stacked["spiritStones"]) == expected_stones, "叠加产出灵石 == 独立累加(%d)" % expected_stones)
	_check(int(stacked["spiritPower"]) == expected_power, "叠加产出灵力 == 独立累加(%d)" % expected_power)

	# ④ 未指派 → 不产出（`tile_yield` 要求 workedByPeakId 匹配）
	var peak: SpiritPeak = state.sects[0].spiritPeaks[0]
	peak.workedTileIds.clear()
	tile.workedByPeakId = ""
	_check(_same_yield(EconomyRules.tile_yield(state, _config, tile, peak), EconomyRules.zero_yield()), "未指派地块不产出")

	# 还原
	tile.baseTerrain = str(original["baseTerrain"])
	tile.relief = str(original["relief"])
	tile.features = original["features"]
	tile.riverEdges = original["riverEdges"]
	tile.nodeId = str(original["nodeId"])
	tile.improvementId = str(original["improvementId"])
	state.nodes.erase("test_ling_tian")


func _test_settlement() -> void:
	var dispatcher: CommandDispatcher = _new_game("123456")
	var state: GameState = dispatcher.state
	var sect: Sect = state.sects[0]
	var peak: SpiritPeak = _capital(sect)
	_boost(sect, 5000)
	var claimed: Array[HexTile] = _claim_neighbors(state, sect, peak, 4)
	# 预指派满人口，令 settle_city 的 auto_assign 成为 no-op（保证独立复算口径一致）
	for index: int in range(mini(peak.population, claimed.size())):
		CityRules.assign(state, _config, peak, claimed[index])
	peak.food = 200.0
	peak.freeWorkers = maxi(0, peak.population - peak.workedTileIds.size())

	# 独立复算：毛产出 / 维护 / 工力 / 威望 / 住房
	var totals: Dictionary = EconomyRules.zero_yield()
	for each: SpiritPeak in sect.spiritPeaks:
		EconomyRules.add_yield(totals, EconomyRules.peak_output(state, _config, each))
	var upkeep: Dictionary = EconomyRules.sect_upkeep(state, _config, sect)
	var work_income: int = EconomyRules.work_power_income(state, _config, sect)
	var prestige_income: int = EconomyRules.prestige_income(state, _config, sect)
	var before: Dictionary = {
		"spiritPower": int(sect.resources["spiritPower"]),
		"spiritStones": int(sect.resources["spiritStones"]),
		"daoPoints": int(sect.resources.get("daoPoints", 0)),
		"workPower": int(sect.resources["workPower"]),
		"prestige": int(sect.resources["prestige"]),
	}
	var population_before: int = peak.population
	var housing: int = CityRules.housing_of(state, _config, peak)
	var balance: int = EconomyRules.food_balance(state, _config, peak)
	var stability: float = EconomyRules.stability_of(state, _config, peak)
	var threshold: float = float(_config["city"]["growthFoodThreshold"])
	var growth_cost: float = float(_config["city"]["growthFoodCost"])
	var stability_min: float = float(_config["city"]["growthStabilityMin"])
	var expected_growth: int = 0
	var food_probe: float = maxf(0.0, peak.food + float(balance))
	while population_before + expected_growth < housing and food_probe >= threshold and stability >= stability_min:
		food_probe -= growth_cost
		expected_growth += 1

	_request(dispatcher, "finishTurn")
	_check(int(sect.resources["spiritPower"]) == before["spiritPower"] + int(totals["spiritPower"]) - int(upkeep["spiritPower"]), "SETTLEMENT 后灵力 == 毛产出 − 维护")
	_check(int(sect.resources["spiritStones"]) == before["spiritStones"] + int(totals["spiritStones"]), "SETTLEMENT 后灵石 == +毛产出")
	_check(int(sect.resources["daoPoints"]) == before["daoPoints"] + int(totals["daoPoints"]), "SETTLEMENT 后道点 == +毛产出")
	_check(int(sect.resources["workPower"]) == before["workPower"] + work_income, "SETTLEMENT 后工力 == +work_power_income")
	_check(int(sect.resources["prestige"]) == before["prestige"] + prestige_income, "SETTLEMENT 后威望 == +prestige_income")
	_check(peak.population == population_before + expected_growth, "人口按 growthFoodThreshold 增长（独立复算）")
	_check(peak.population <= housing, "人口不超住房")

	# 住房公式独立复算
	var caves: int = CityRules.cave_count(peak)
	var built: int = CityRules.built_districts(peak).size()
	var housing_ref: int = int(_config["city"]["housingBase"]) + int(_config["city"]["housingPerPeakLevel"]) * peak.level
	housing_ref += int(_config["city"]["housingPerCave"]) * caves
	housing_ref += int(_config["city"]["housingPerDistrict"]) * built
	housing_ref += int(_config["city"]["housingPerBuilding"]) * (peak.buildings.size() - caves)
	_check(CityRules.housing_of(state, _config, peak) == housing_ref, "住房 == housingBase + 峰级 + 洞府 + 区域 + 建筑")

	# 产出系数独立复算
	var overflow: int = maxi(0, peak.population - CityRules.housing_of(state, _config, peak))
	var factor_ref: float = 1.0 + (EconomyRules.stability_of(state, _config, peak) - float(_config["city"]["stabilityBase"])) * float(_config["city"]["stabilityOutputFactor"])
	factor_ref -= float(overflow) * float(_config["city"]["housingOverflowOutputPenalty"])
	_check(is_equal_approx(EconomyRules.output_multiplier(state, _config, peak), maxf(0.2, factor_ref)), "产出系数按 stabilityOutputFactor + 住房超员")

	# 赤字：灵力清零 + 安定 −stabilityDropOnDeficit
	# 夹具：开局主峰毛产出（12 基础 + 4×3 弟子 = 24）远高于维护（6 峰 + 1 建筑级 + 2 单位），
	# 故直接给主峰挂 20 座不产灵力的建筑（每座 +1 建筑级维护）把维护推高到 29 > 24，构造真实赤字；
	# 粮仓置 7（结算后 7 − 弟子口粮 3 > 0），既不触发缺粮惩罚也不会人口暴涨。
	var dispatcher2: CommandDispatcher = _new_game("123456")
	var state2: GameState = dispatcher2.state
	var sect2: Sect = state2.sects[0]
	var peak2: SpiritPeak = _capital(sect2)
	for index: int in range(20):
		var building_id: String = "test_building_%d" % index
		peak2.buildings[building_id] = {"id": building_id, "type": "SHAN_MEN", "name": "山门", "level": 1, "districtId": ""}
	peak2.food = 7.0
	sect2.resources["spiritPower"] = 0
	var totals2: Dictionary = EconomyRules.zero_yield()
	for each: SpiritPeak in sect2.spiritPeaks:
		EconomyRules.add_yield(totals2, EconomyRules.peak_output(state2, _config, each))
	var upkeep2: Dictionary = EconomyRules.sect_upkeep(state2, _config, sect2)
	_check(int(sect2.resources["spiritPower"]) + int(totals2["spiritPower"]) < int(upkeep2["spiritPower"]), "夹具：已构造灵力赤字")
	var no_deficit: float = EconomyRules.stability_of(state2, _config, peak2, false)
	_request(dispatcher2, "finishTurn")
	_check(int(sect2.resources["spiritPower"]) == 0, "赤字时灵力清零")
	_check(is_equal_approx(peak2.stability, no_deficit - float(_config["economy"]["stabilityDropOnDeficit"])), "赤字时安定按 stabilityDropOnDeficit 结算")
	_check(is_equal_approx(peak2.stability, EconomyRules.stability_of(state2, _config, peak2, true)), "赤字安定 == stability_of(deficit=true)")
	_check(peak2.stability <= no_deficit, "赤字时安定不上升")


# ---------------------------------------------------------------------------
# 7. 道路（RoadNetworkService）
# ---------------------------------------------------------------------------

func _test_roads() -> void:
	var dispatcher: CommandDispatcher = _new_game("123456")
	var state: GameState = dispatcher.state
	var sect: Sect = state.sects[0]
	var peak: SpiritPeak = _capital(sect)
	_boost(sect, 5000)
	sect.resources["workPower"] = 5000
	var claimed: Array[HexTile] = _claim_neighbors(state, sect, peak, 4)
	_check(claimed.size() >= 2, "夹具：主峰邻格已划归本宗")
	if claimed.size() < 2:
		return
	for tile: HexTile in claimed:
		tile.nodeId = ""
		tile.relief = "FLAT"
		tile.baseTerrain = "SPIRIT_PLAIN"
	# 相邻两格（claimed[0] 与 claimed[1] 是否相邻需确认；用主峰为桥：两格都与主峰相邻，但彼此不一定）
	var road_a: HexTile = claimed[0]
	var road_b: HexTile = claimed[1]
	var builder: Disciple = sect.disciples[1]
	_result(dispatcher, "appointBuilder", {"sectId": sect.id, "discipleId": builder.id})
	# 直接造路（绕过 builderCharges 限制：每格一次，charges=3 足够两格）
	for tile: HexTile in [road_a, road_b]:
		builder.tileId = tile.id
		var built: Dictionary = _result(dispatcher, "buildImprovement", {"sectId": sect.id, "discipleId": builder.id, "tileId": tile.id, "improvementType": "QING_SHI_DAO_LU"})
		_check(bool(built.get("success", false)), "青石道路 %s 修筑成功" % tile.id)
	RoadNetworkService.refresh(state, _config)
	# 独立复算：链长 2 格，且两格均在主峰邻域 → 至少接上 1 座灵峰
	var imp_a: Improvement = ImprovementRules.find_on_tile(state, road_a.id)
	var imp_b: Improvement = ImprovementRules.find_on_tile(state, road_b.id)
	_check(imp_a != null and imp_b != null, "两格均写入改良")
	var chain_len: int = 2 if _are_neighbors(road_a, road_b) else 1
	if chain_len >= int(_config["road"]["networkMinChainTiles"]):
		_check(imp_a.networkLevel >= RoadNetworkService.TIER_LINK, "道路链接入灵峰 → 等级 >= TIER_LINK")
	else:
		_check(imp_a.networkLevel == RoadNetworkService.TIER_NONE, "未成链 → 等级 TIER_NONE")

	# step_cost：踏入本宗完好道路减 stepCostReduction（下限 minStepCost）
	var from: HexTile = state.tiles[peak.tileId]
	var base_cost: int = MoveRules.step_cost(_config, from, road_a)
	var expected: int = maxi(RoadNetworkService.min_step_cost(_config), base_cost - int(_config["road"]["stepCostReduction"]))
	_check(MoveRules.step_cost(_config, from, road_a, sect, state) == expected, "踏入本宗道路 step_cost 减 stepCostReduction")
	_check(MoveRules.step_cost(_config, from, road_a) == base_cost, "不带 sect/state 的 3 参调用保持 R2 原值")

	# start_tile_bonus：身处道路的机动加成（基础 + 网络等级）
	var disciple: Disciple = sect.disciples[0]
	disciple.tileId = road_a.id
	var base_points: int = MoveRules.calculate_max_move_points(disciple, _config)
	var bonus: int = RoadNetworkService.start_tile_bonus(state, _config, sect, road_a)
	_check(bonus == int(_config["improvement"]["roadMoveBonus"]) + (int(_config["road"]["tierPeakBonus"]) if imp_a.networkLevel == RoadNetworkService.TIER_LINK else int(_config["road"]["tierHubBonus"]) if imp_a.networkLevel >= RoadNetworkService.TIER_HUB else 0), "start_tile_bonus == 基础 + 网络等级加成")
	_check(MoveRules.calculate_max_move_points(disciple, _config, state, sect) == base_points + bonus, "calculate_max_move_points 含 start_tile_bonus")


# ---------------------------------------------------------------------------
# 8. 气运满溢扩张（1.0 EconomyCalculator.annexAdjacentTile）
# ---------------------------------------------------------------------------

func _test_annex() -> void:
	var dispatcher: CommandDispatcher = _new_game("123456")
	var state: GameState = dispatcher.state
	var sect: Sect = state.sects[0]
	var peak: SpiritPeak = _capital(sect)
	var center: HexTile = state.tiles[peak.tileId]
	var owned_before: int = _owned_count(state, sect)
	# 把气运顶到上限，下一次结算即触发吞并
	peak.qiYun = peak.qiYunMax
	_request(dispatcher, "finishTurn")
	_check(_owned_count(state, sect) == owned_before + 1, "气运攒满吞并一块相邻无主地块")
	_check(peak.qiYun == 0, "吞并后气运归零")
	var annexed: bool = false
	for coords: Vector2i in Hex.neighbors(Vector2i(center.q, center.r)):
		var nid: String = Hex.id(coords.x, coords.y)
		if state.tiles.has(nid) and state.tiles[nid].ownerSectId == sect.id:
			annexed = true
	_check(annexed, "吞并的地块与主峰相邻")
	# 无处可吞并 → 灵峰晋升（把六邻全部占满）
	for coords: Vector2i in Hex.neighbors(Vector2i(center.q, center.r)):
		var nid: String = Hex.id(coords.x, coords.y)
		if state.tiles.has(nid) and state.tiles[nid].ownerSectId.is_empty():
			state.tiles[nid].ownerSectId = state.sects[1].id
	var level_before: int = peak.level
	var capacity_before: int = peak.capacity
	peak.qiYun = peak.qiYunMax
	_request(dispatcher, "finishTurn")
	_check(peak.level == level_before + 1, "无处可吞并 → 灵峰晋升 1 级")
	_check(peak.capacity == capacity_before + int(_config["spiritPeak"]["capacityPerLevel"]), "灵峰晋升容量 +capacityPerLevel")


# ---------------------------------------------------------------------------
# 9. 确定性
# ---------------------------------------------------------------------------

func _test_determinism() -> void:
	var first: String = _run_sequence()
	var second: String = _run_sequence()
	_check(not first.is_empty(), "指令序列可执行")
	_check(first == second, "同种子同指令序列双跑关键 view 逐字一致")


func _run_sequence() -> String:
	var dispatcher: CommandDispatcher = _new_game("20261016")
	var state: GameState = dispatcher.state
	var sect: Sect = state.sects[0]
	var peak: SpiritPeak = _capital(sect)
	_boost(sect, 5000)
	sect.resources["workPower"] = 5000
	var claimed: Array[HexTile] = _claim_neighbors(state, sect, peak, 3)
	for tile: HexTile in claimed:
		tile.nodeId = ""
		tile.relief = "HILL"
		tile.baseTerrain = "SPIRIT_PLAIN"
	if claimed.size() >= 2:
		var builder: Disciple = sect.disciples[1]
		_result(dispatcher, "appointBuilder", {"sectId": sect.id, "discipleId": builder.id})
		builder.tileId = claimed[0].id
		_result(dispatcher, "buildImprovement", {"sectId": sect.id, "discipleId": builder.id, "tileId": claimed[0].id, "improvementType": "LING_KUANG"})
		_result(dispatcher, "assignWorker", {"peakId": peak.id, "tileId": claimed[1].id})
	var leader: Disciple = sect.disciples[0]
	var target: String = _find_tile(state, false, true)
	if not target.is_empty():
		leader.tileId = target
		_result(dispatcher, "foundSpiritPeak", {"discipleId": leader.id, "tileId": target})
	for _i: int in range(6):
		_request(dispatcher, "nextTurn")
	return JSON.stringify(_snapshot(_view(dispatcher)), "\t", true)


func _snapshot(view: Dictionary) -> Dictionary:
	var owners: Dictionary = {}
	var worked: Dictionary = {}
	var district_ids: Dictionary = {}
	var improvement_ids: Dictionary = {}
	for tile_id: String in view["tiles"]:
		var tile: Dictionary = view["tiles"][tile_id]
		owners[tile_id] = tile["ownerSectId"]
		worked[tile_id] = tile["workedByPeakId"]
		district_ids[tile_id] = tile["districtId"]
		improvement_ids[tile_id] = tile["improvementId"]
	var improvements: Array = []
	for key: String in (view["improvements"] as Dictionary).keys():
		var item: Dictionary = view["improvements"][key]
		improvements.append([item["id"], item["type"], item["tileId"], item["sectId"], item["broken"], item["networkLevel"]])
	improvements.sort_custom(func(a: Array, b: Array) -> bool: return str(a[0]) < str(b[0]))
	var sects: Array = []
	for sect_data: Dictionary in view["sects"]:
		var peaks: Array = []
		for peak: Dictionary in sect_data["spiritPeaks"]:
			var districts: Array = []
			for district: Dictionary in peak["districts"]:
				districts.append([district["id"], district["type"], district["tileId"]])
			peaks.append([peak["id"], peak["tileId"], peak["level"], peak["population"], peak["qiYun"], peak["qiYunMax"], peak["food"], peak["stability"], peak["workedTileIds"], districts])
		sects.append({"id": sect_data["id"], "resources": sect_data.get("resources", {}), "peaks": peaks})
	return {
		"turn": view["turn"], "phase": view["phase"], "sects": sects,
		"owners": owners, "worked": worked, "districtIds": district_ids,
		"improvementIds": improvement_ids, "improvements": improvements,
	}


# ---------------------------------------------------------------------------
# 辅助
# ---------------------------------------------------------------------------

func _new_game(seed: String) -> CommandDispatcher:
	var dispatcher: CommandDispatcher = CommandDispatcher.new(_config)
	_request(dispatcher, "newGame", {"sectName": "验收宗", "playerFaction": "ZONG_MEN", "mapWidth": 24, "mapHeight": 18, "randomSeed": seed, "difficultyId": "normal"})
	return dispatcher


func _request(dispatcher: CommandDispatcher, command: String, params: Dictionary = {}) -> Dictionary:
	return dispatcher.dispatch_text(JSON.stringify({"id": "test", "type": command, "params": params}))


func _result(dispatcher: CommandDispatcher, command: String, params: Dictionary) -> Dictionary:
	var response: Dictionary = _request(dispatcher, command, params)
	return response.get("result", {})


func _view(dispatcher: CommandDispatcher) -> Dictionary:
	return _request(dispatcher, "getState")["view"]


func _capital(sect: Sect) -> SpiritPeak:
	for peak: SpiritPeak in sect.spiritPeaks:
		if peak.capital:
			return peak
	return sect.spiritPeaks[0]


func _boost(sect: Sect, power: int) -> void:
	sect.resources["spiritPower"] = power
	sect.resources["materials"] = {"tian_jing": 99, "xuan_tie": 99, "ling_mu": 99}
	sect.resources["workPower"] = 5000


## 测试夹具：把主峰六邻中最多 `count` 块无主非山岳格划归本宗。
func _claim_neighbors(state: GameState, sect: Sect, peak: SpiritPeak, count: int) -> Array[HexTile]:
	var claimed: Array[HexTile] = []
	if not state.tiles.has(peak.tileId):
		return claimed
	var center: HexTile = state.tiles[peak.tileId]
	var candidates: Array[HexTile] = []
	for coords: Vector2i in Hex.neighbors(Vector2i(center.q, center.r)):
		var tile_id: String = Hex.id(coords.x, coords.y)
		if state.tiles.has(tile_id):
			candidates.append(state.tiles[tile_id])
	candidates.sort_custom(func(a: HexTile, b: HexTile) -> bool: return a.id < b.id)
	for tile: HexTile in candidates:
		if claimed.size() >= count:
			break
		if not tile.ownerSectId.is_empty() or tile.relief == "MOUNTAIN":
			continue
		tile.danger = false
		tile.ownerSectId = sect.id
		claimed.append(tile)
	return claimed


## 找一个地块：`mountain=true` 取山岳；`unowned=true` 要求无主。`min_distance` 可限定与 `center` 的最小距离。
func _find_tile(state: GameState, mountain: bool, unowned: bool, center: Vector2i = Vector2i(-9999, -9999), min_distance: int = 0) -> String:
	var ids: Array[String] = []
	for tile_id: String in state.tiles.keys():
		ids.append(tile_id)
	ids.sort()
	for tile_id: String in ids:
		var tile: HexTile = state.tiles[tile_id]
		if mountain and tile.relief != "MOUNTAIN":
			continue
		if not mountain and tile.relief == "MOUNTAIN":
			continue
		if unowned and not tile.ownerSectId.is_empty():
			continue
		if center.x != -9999 and Hex.distance(Vector2i(tile.q, tile.r), center) < min_distance:
			continue
		return tile_id
	return ""


func _owned_count(state: GameState, sect: Sect) -> int:
	var total: int = 0
	for tile: HexTile in state.tiles.values():
		if tile.ownerSectId == sect.id:
			total += 1
	return total


func _are_neighbors(a: HexTile, b: HexTile) -> bool:
	return Hex.distance(Vector2i(a.q, a.r), Vector2i(b.q, b.r)) == 1


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _same_yield(a: Dictionary, b: Dictionary) -> bool:
	for key: String in EconomyRules.YIELD_KEYS:
		if int(a.get(key, 0)) != int(b.get(key, 0)):
			return false
	return true


func _same_strings(a: Variant, b: Variant) -> bool:
	var left: Array = a if a is Array else []
	var right: Array = b if b is Array else []
	if left.size() != right.size():
		return false
	for index: int in range(left.size()):
		if str(left[index]) != str(right[index]):
			return false
	return true


# --- 独立复算：区域邻接（镜像 city.district.adjacency 配置语义） ---

func _reference_adjacency(state: GameState, config: Dictionary, district_type: String, tile_id: String) -> Dictionary:
	var out: Dictionary = {"yield": EconomyRules.zero_yield(), "reasons": []}
	if district_type == "SHOU_FU_QU" or not state.tiles.has(tile_id):
		return out
	var rules: Array = config["city"]["district"]["adjacency"]
	var base: Dictionary = config["city"]["district"]["yields"].get(district_type, {})
	# 基础产出（与 `CityRules.district_yield` 同口径）
	for key: Variant in base.keys():
		out["yield"][str(key)] = int(out["yield"].get(str(key), 0)) + int(base[key])
	var anchor: HexTile = state.tiles[tile_id]
	for coords: Vector2i in Hex.neighbors(Vector2i(anchor.q, anchor.r)):
		var neighbor_id: String = Hex.id(coords.x, coords.y)
		if not state.tiles.has(neighbor_id):
			continue
		var neighbor: HexTile = state.tiles[neighbor_id]
		var keys: Array[String] = _neighbor_keys(state, neighbor)
		for rule: Variant in rules:
			var entry: Dictionary = rule
			if str(entry["districtType"]) != district_type or not keys.has(str(entry["neighbor"])):
				continue
			var resource: String = str(entry["resource"])
			var amount: int = int(entry.get("flat", 0))
			var ratio: float = float(entry.get("ratio", 0.0))
			if ratio > 0.0:
				amount += int(round(float(base.get(resource, 0)) * ratio))
			if amount == 0:
				continue
			var yields: Dictionary = out["yield"]
			yields[resource] = int(yields.get(resource, 0)) + amount
			out["reasons"].append(_reference_reason(entry, neighbor, state))
	return out


func _neighbor_keys(state: GameState, neighbor: HexTile) -> Array[String]:
	var keys: Array[String] = []
	if neighbor.danger:
		keys.append("DANGER")
	if not neighbor.nodeId.is_empty() and state.nodes.has(neighbor.nodeId):
		keys.append("NODE_" + (state.nodes[neighbor.nodeId] as GameNode).type)
	if not neighbor.districtId.is_empty():
		keys.append("DISTRICT")
	keys.append(neighbor.relief)
	keys.append("TERRAIN_" + neighbor.baseTerrain)
	return keys


func _reference_reason(rule: Dictionary, neighbor: HexTile, state: GameState) -> String:
	var neighbor_key: String = str(rule["neighbor"])
	var from: String = neighbor.id
	if neighbor_key.begins_with("NODE_") and not neighbor.nodeId.is_empty() and state.nodes.has(neighbor.nodeId):
		from = _node_label((state.nodes[neighbor.nodeId] as GameNode).type)
	elif neighbor_key == "MOUNTAIN":
		from = "山岳"
	elif neighbor_key == "DANGER":
		from = "险地"
	elif neighbor_key == "DISTRICT":
		from = "相邻区域"
	var detail: String = str(rule.get("description", ""))
	if detail.is_empty():
		var parts: Array[String] = []
		var flat: int = int(rule.get("flat", 0))
		var ratio: float = float(rule.get("ratio", 0.0))
		if flat != 0:
			parts.append("%s%+d" % [_resource_label(str(rule["resource"])), flat])
		if ratio > 0.0:
			parts.append("%s+%d%%" % [_resource_label(str(rule["resource"])), int(round(ratio * 100.0))])
		detail = "、".join(parts)
	return "%s: %s" % [from, detail]


func _node_label(node_type: String) -> String:
	match node_type:
		"LING_TIAN":
			return "灵田"
		"LING_MAI":
			return "灵脉"
		"LING_QUAN":
			return "灵泉"
		"JI_YUAN":
			return "机缘"
		"MI_JING":
			return "秘境"
	return node_type


func _resource_label(resource: String) -> String:
	match resource:
		"food":
			return "灵粮"
		"spiritPower":
			return "灵力"
		"spiritStones":
			return "灵石"
		"daoPoints":
			return "道统点"
		"qiYun":
			return "气运"
	return resource
