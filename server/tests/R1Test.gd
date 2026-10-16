extends Node

var _failures: Array[String] = []
var _checks: int = 0
var _config: Dictionary = {}
var _finished: bool = false
var _started: int = Time.get_ticks_msec()

func _process(_delta: float) -> void:
	if not _finished and Time.get_ticks_msec() - _started > 60000:
		printerr("R1_FAIL 测试未正常完成（可能运行时脚本错误）")
		get_tree().quit(1)

func _ready() -> void:
	var loaded: Dictionary = ConfigLoader.load_from_file(ConfigLoader.default_path())
	_check(bool(loaded["ok"]), "配置可加载")
	_config = loaded["config"]
	_check(ConfigValidator.validate(_config).is_empty(), "迁移配置通过深层验证")
	_test_params()
	_test_config()
	_test_rule_boundaries()
	var first: String = ""
	for dimensions: Vector2i in [Vector2i(20, 15), Vector2i(13, 9), Vector2i(2, 2), Vector2i(2, 9), Vector2i(9, 2), Vector2i(3, 3), Vector2i(4, 3), Vector2i(30, 18)]:
		for seed_value: String in ["123456", "1", "42", "9007199254740993", "-9223372036854775808"]:
			var dispatcher: CommandDispatcher = CommandDispatcher.new(_config)
			var params: Dictionary = {"playerFaction": "ZONG_MEN", "sectName": "测试宗", "mapWidth": dimensions.x, "mapHeight": dimensions.y, "randomSeed": seed_value}
			var response: Dictionary = _request(dispatcher, "newGame", params)
			_check(bool(response.get("ok", false)), "newGame %s seed=%s" % [dimensions, seed_value])
			if not bool(response.get("ok", false)):
				continue
			var state: GameState = dispatcher.state
			_test_state(state)
			_test_view(state, response["view"])
			var serialized: String = _authority(state)
			var repeated: Dictionary = _request(dispatcher, "newGame", params)
			_check(bool(repeated["ok"]) and serialized == _authority(dispatcher.state), "全量权威地图同种子逐字一致")
			_check(JSON.stringify(response["view"]) == JSON.stringify(repeated["view"]), "玩家 view 同种子逐字一致")
			if dimensions == Vector2i(20, 15) and seed_value == "123456":
				first = serialized
				_export("r1_authority_a.json", serialized)
				_export("r1_authority_b.json", _authority(dispatcher.state))
	_check(not first.is_empty(), "导出基准权威地图")
	_test_fog()
	_test_bonus()
	_finished = true
	if _failures.is_empty():
		print("R1_PASS checks=%d" % _checks)
		get_tree().quit(0)
	else:
		for message: String in _failures:
			printerr("R1_FAIL ", message)
		print("R1_FAIL checks=%d failures=%d" % [_checks, _failures.size()])
		get_tree().quit(1)

func _request(dispatcher: CommandDispatcher, command: String, params: Dictionary = {}) -> Dictionary:
	return dispatcher.dispatch_text(JSON.stringify({"id": "test", "type": command, "params": params}))

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)

func _test_params() -> void:
	var dispatcher: CommandDispatcher = CommandDispatcher.new(_config)
	# R2 起已登记命令随里程碑增长（R2 为 8 条），故只断言 R1 三命令仍在册，不再锁死总数。
	var implemented: Array = dispatcher.implemented_commands()
	for required: String in ["ping", "newGame", "getState"]:
		_check(implemented.has(required), "R1 命令仍在册：" + required)
	_check(implemented.size() >= 3, "已登记命令不少于 R1 的 3 条")
	_check(_request(dispatcher, "getState").get("errorCode") == "NO_GAME", "getState 开局前 NO_GAME")
	var base: Dictionary = {"sectName": "参数宗", "playerFaction": "JIA_ZU", "randomSeed": "9007199254740993"}
	var good: Dictionary = _request(dispatcher, "newGame", base)
	_check(bool(good.get("ok", false)), "64bit 字符串 seed 可开局")
	if bool(good.get("ok", false)):
		_check(dispatcher.state.seed == 9007199254740993, "64bit seed 内部精确")
		_check(good["view"]["randomSeed"] == "9007199254740993", "64bit seed 视图无损十进制字符串")
		_check(dispatcher.state.width == 20 and dispatcher.state.height == 15 and dispatcher.state.difficulty == "normal", "宽高和难度读取配置默认")
	for bad: Dictionary in [{"mapWidth": 2.5}, {"mapHeight": true}, {"mapWidth": 1}, {"mapHeight": 0}, {"mapWidth": 9999999999999}, {"sectName": " \t "}, {"playerFaction": "INVALID"}, {"difficultyId": "INVALID"}, {"factionType": "GUO_JIA"}, {"difficultyId": "easy", "difficulty": "hard"}, {"randomSeed": 9007199254740993}, {"randomSeed": 1.5}, {"randomSeed": "9223372036854775808"}, {"randomSeed": "-9223372036854775809"}, {"randomSeed": "abc"}]:
		var params: Dictionary = base.duplicate(true)
		params.merge(bad, true)
		var previous: GameState = dispatcher.state
		_check(_request(dispatcher, "newGame", params).get("errorCode") == "BAD_PARAMS", "拒绝非法参数 %s" % bad)
		_check(dispatcher.state == previous, "非法参数不替换既有局")
	_check(bool(_request(dispatcher, "newGame", {"sectName": "兼容宗", "factionType": "GUO_JIA", "difficulty": "easy", "randomSeed": ""}).get("ok", false)), "aliases 与随机空 seed")
	_check(bool(_request(dispatcher, "getState").get("ok", false)), "getState 成功")

func _test_config() -> void:
	for block: String in ["map", "resources", "disciple", "spiritPeak", "vision", "warfare", "daoTree", "policy", "difficulty"]:
		var missing: Dictionary = _config.duplicate(true)
		missing.erase(block)
		_check(not ConfigValidator.validate(missing).is_empty(), "拒绝缺块 %s" % block)
	for path: Array in [["map", "relief", "HILL", "height"], ["resources", "initial", "materials", "tian_jing"], ["vision", "discipleVisionByRealm", "JIN_DAN"], ["warfare", "unitClasses", "PU_TONG", "range"], ["map", "setup", "rootGrade"]]:
		var missing: Dictionary = _config.duplicate(true)
		var parent: Dictionary = missing
		for index: int in range(path.size() - 1):
			parent = parent[path[index]]
		parent.erase(path[-1])
		_check(not ConfigValidator.validate(missing).is_empty(), "拒绝嵌套缺项 %s" % str(path))
	for value: Variant in ["高", -1, INF, NAN, true]:
		var bad: Dictionary = _config.duplicate(true)
		bad["map"]["relief"]["HILL"]["height"] = value
		_check(not ConfigValidator.validate(bad).is_empty(), "拒绝非法高度 %s" % str(value))
	var ratio: Dictionary = _config.duplicate(true)
	ratio["map"]["relief"]["MOUNTAIN"]["ratio"] = 0.9
	_check(not ConfigValidator.validate(ratio).is_empty(), "拒绝比例和错误")
	var bad_enum: Dictionary = _config.duplicate(true)
	bad_enum["map"]["nodeSpawnByTerrain"]["LING_MAI"]["reliefs"] = ["INVALID"]
	_check(not ConfigValidator.validate(bad_enum).is_empty(), "拒绝地形枚举")
	var nested: Dictionary = _config.duplicate(true)
	nested["ai"]["diplomacyPeaceWeariness"] = 4
	_check(not ConfigValidator.validate(nested).is_empty(), "拒绝嵌套裁剪字段")

func _test_rule_boundaries() -> void:
	# 偏好块缺关键字段不能悄悄放宽生成限制。
	for path: Array in [["LING_TIAN", "reliefs"], ["LING_MAI", "reliefs"], ["LING_QUAN", "riverRequired"], ["JI_YUAN", "danger"], ["MI_JING", "danger"]]:
		var malformed: Dictionary = _config.duplicate(true)
		malformed["map"]["nodeSpawnByTerrain"][path[0]].erase(path[1])
		_check(not ConfigValidator.validate(malformed).is_empty(), "节点偏好缺关键限制应拒绝 %s" % str(path))
	for value: Variant in [0, 1.5, "1", true]:
		var malformed: Dictionary = _config.duplicate(true)
		malformed["map"]["setup"]["safeRadius"] = value
		_check(not ConfigValidator.validate(malformed).is_empty(), "出生安全半径不能无效 %s" % str(value))
	for field: String in ["rootTypes", "aiNames"]:
		var malformed: Dictionary = _config.duplicate(true)
		malformed["map"]["setup"][field] = [null, null, null]
		_check(not ConfigValidator.validate(malformed).is_empty(), "开局数组元素必须合法 %s" % field)
	var malformed: Dictionary = _config.duplicate(true)
	malformed["map"]["baseTerrainAlgorithm"] = "INVALID"
	_check(not ConfigValidator.validate(malformed).is_empty(), "基底算法枚举须合法")
	# 自有实体在旧视野外也须实时；旧缓存不能保留已拆除的自有峰。
	var dispatcher: CommandDispatcher = CommandDispatcher.new(_config)
	_request(dispatcher, "newGame", {"sectName": "边界宗", "playerFaction": "ZONG_MEN", "randomSeed": "123456"})
	var state: GameState = dispatcher.state
	var player: Sect = state.sects[0]
	var owned_tile: String = player.spiritPeaks[0].tileId
	var tile: HexTile = state.tiles[owned_tile]
	var owned_node: GameNode = GameNode.new()
	owned_node.id = "owned_node"
	owned_node.tileId = owned_tile
	owned_node.ownerSectId = player.id
	owned_node.type = "LING_TIAN"
	owned_node.output = 5.0
	state.nodes[owned_node.id] = owned_node
	tile.nodeId = owned_node.id
	StateView.build(state, _config)
	player.visibleTiles.clear()
	tile.improvementId = "owned_improvement"
	owned_node.output = 42.0
	var view: Dictionary = StateView.build(state, _config)
	_check(view["tiles"][owned_tile]["improvementId"] == "owned_improvement", "己方地块改良实时")
	_check(view["nodes"][owned_node.id]["output"] == 42.0, "己方节点实时")
	player.spiritPeaks.clear()
	_check(StateView.build(state, _config)["sects"][0]["spiritPeaks"].is_empty(), "己方拆峰不残留缓存")
	# 旧 GameState 的 RNG 不能被下一次 newGame 复位共享。
	var old_sequence: int = state.rng.sequence
	_request(dispatcher, "newGame", {"sectName": "下一局", "playerFaction": "ZONG_MEN", "randomSeed": "42"})
	_check(state.rng.seed_value == 123456 and state.rng.sequence == old_sequence, "不同局不共享可变 RNG")

func _test_state(state: GameState) -> void:
	_check(state.tiles.size() == state.width * state.height, "权威地图完整")
	_check(state.sects.size() == 4 and state.spawnTiles.size() == 4, "四宗四个出生点")
	var unique: Dictionary = {}
	var total_disciples: int = 0
	for sect: Sect in state.sects:
		total_disciples += sect.disciples.size()
		_check(sect.disciples.size() == 3 and sect.spiritPeaks.size() == 1, "每宗三弟子一主峰")
		_check(sect.resources["spiritPower"] == 400 and sect.resources["spiritStones"] == 300 and sect.resources["workPower"] == 120 and sect.resources["prestige"] == 0, "普通难度初始资源")
		_check(sect.resources["materials"] == {"tian_jing": 2.0, "xuan_tie": 2.0, "ling_mu": 4.0}, "初始材料")
		var peak: SpiritPeak = sect.spiritPeaks[0]
		_check(peak.population == 3 and peak.capacity == 10 and peak.defense == 10 and peak.level == 1 and peak.qiYun == 0 and peak.qiYunMax == 100, "主峰初始数据")
		_check(sect.disciples[0].realm == "JIN_DAN" and sect.disciples[1].realm == "LIAN_QI" and sect.disciples[2].realm == "LIAN_QI", "宗主金丹两外门炼气")
		_check(sect.disciples[1].rootGrade == 1 and sect.disciples[1].spiritRoots.size() == 1, "外门灵根一品一个")
		_check(sect.exploredTiles == sect.visibleTiles, "fresh explored 等于 visible 不加演示环")
	for spawn: String in state.spawnTiles:
		_check(not unique.has(spawn), "出生点不重复")
		unique[spawn] = true
		var nearby_resource: bool = false
		for tile: HexTile in state.tiles.values():
			if Hex.distance(Hex.coords(spawn), Vector2i(tile.q, tile.r)) <= 1:
				_check(not tile.danger and tile.relief != "MOUNTAIN", "出生邻域安全")
				nearby_resource = nearby_resource or (tile.baseTerrain == "LING_FIELDS" and not tile.nodeId.is_empty()) or not tile.riverEdges.is_empty()
		_check(nearby_resource, "出生邻域近水或灵田节点")
	_check(total_disciples == 12, "内部十二弟子")
	_check(state.spawnTiles[0] == Hex.id(state.width / 2, state.height / 2), "玩家中心出生")
	var reached: Dictionary = {}
	var queue: Array[String] = [state.spawnTiles[0]]
	reached[queue[0]] = true
	var cursor: int = 0
	while cursor < queue.size():
		var current: String = queue[cursor]
		cursor += 1
		for cell: Vector2i in Hex.neighbors(Hex.coords(current)):
			var neighbor: String = Hex.id(cell.x, cell.y)
			if state.tiles.has(neighbor) and not reached.has(neighbor) and state.tiles[neighbor].relief != "MOUNTAIN":
				reached[neighbor] = true
				queue.append(neighbor)
	for spawn: String in state.spawnTiles:
		_check(reached.has(spawn), "各出生点可通路连接")
	var counts: Dictionary = {"MOUNTAIN": 0, "HILL": 0, "FLAT": 0}
	for tile: HexTile in state.tiles.values():
		counts[tile.relief] += 1
		_check(tile.features.size() <= 1 and (tile.relief != "MOUNTAIN" or tile.features.is_empty()), "山顶不叠地貌")
		_check(not tile.features.has("MIRE") or tile.relief == "FLAT", "雾泽仅平地")
		for edge: int in tile.riverEdges:
			var cell: Vector2i = Vector2i(tile.q, tile.r) + Hex.DIRECTIONS[edge]
			var neighbor: String = Hex.id(cell.x, cell.y)
			if state.tiles.has(neighbor):
				_check(state.tiles[neighbor].riverEdges.has(Hex.opposite(edge)), "河流成对边标记")
	if state.tiles.size() >= 100:
		_check(absf(float(counts["MOUNTAIN"]) / state.tiles.size() - 0.08) <= 0.03, "山岳 8%±3%")
		_check(absf(float(counts["HILL"]) / state.tiles.size() - 0.22) <= 0.03, "丘陵 22%±3%")
		_check(_max_mountain_component(state) >= 3, "至少三格连绵山岳")
	_test_rivers(state)
	for node: GameNode in state.nodes.values():
		var tile: HexTile = state.tiles[node.tileId]
		_check(tile.nodeId == node.id, "节点格引用正确")
		match node.type:
			"LING_TIAN": _check(tile.baseTerrain == "LING_FIELDS" and tile.relief == "FLAT" and not tile.danger, "灵田地形偏好")
			"LING_MAI": _check(tile.relief in ["HILL", "MOUNTAIN"] and not tile.danger, "灵脉地形偏好")
			"LING_QUAN": _check(not tile.riverEdges.is_empty() and not tile.danger, "灵泉沿河")
			"JI_YUAN", "MI_JING": _check(tile.danger, "探索节点险地偏好")

func _max_mountain_component(state: GameState) -> int:
	var visited: Dictionary = {}
	var largest: int = 0
	for tile: HexTile in state.tiles.values():
		if tile.relief != "MOUNTAIN" or visited.has(tile.id):
			continue
		var queue: Array[String] = [tile.id]
		visited[tile.id] = true
		var cursor: int = 0
		while cursor < queue.size():
			var cell: Vector2i = Hex.coords(queue[cursor])
			cursor += 1
			for neighbor: Vector2i in Hex.neighbors(cell):
				var key: String = Hex.id(neighbor.x, neighbor.y)
				if state.tiles.has(key) and state.tiles[key].relief == "MOUNTAIN" and not visited.has(key):
					visited[key] = true
					queue.append(key)
		largest = maxi(largest, queue.size())
	return largest

func _test_rivers(state: GameState) -> void:
	var all_edges: Dictionary = {}
	var marked: Dictionary = {}
	for tile: HexTile in state.tiles.values():
		for edge: int in range(6):
			var cell: Vector2i = Vector2i(tile.q, tile.r) + Hex.DIRECTIONS[edge]
			var pair: Array[String] = [tile.id, Hex.id(cell.x, cell.y)]
			pair.sort()
			var key: String = "|".join(pair)
			all_edges[key] = true
			if tile.riverEdges.has(edge): marked[key] = true
	_check(float(marked.size()) / all_edges.size() >= 0.1 and float(marked.size()) / all_edges.size() <= 0.2, "河流占唯一边 10%-20% %dx%d" % [state.width, state.height])
	_check(state.riverPaths.size() >= 1 and state.riverPaths.size() <= 2, "一至二个河源")
	var path_edges: Dictionary = {}
	for path: Array in state.riverPaths:
		var previous_end: Vector3 = Vector3.ZERO
		var first: bool = true
		var previous_height: float = INF
		for segment: Dictionary in path:
			var tile: HexTile = state.tiles[segment["tileId"]]
			var endpoints: Array[Vector3] = Hex.edge_vertices(tile.q, tile.r, segment["edge"])
			var start: Vector3 = endpoints[segment["startIndex"]]
			var end: Vector3 = endpoints[1 - int(segment["startIndex"]) ]
			if first:
				_check(tile.relief in ["HILL", "MOUNTAIN"] or _edge_touches_high(state, tile, segment["edge"]), "河源山丘")
			else:
				_check(previous_end.distance_to(start) < 0.0001, "河段真实世界边端点连续")
			_check(is_equal_approx(float(segment["fromHeight"]), _river_vertex_height(state, start)) and is_equal_approx(float(segment["toHeight"]), _river_vertex_height(state, end)), "河路径高度来自相接地块真实海拔")
			_check(float(segment["fromHeight"]) <= previous_height and float(segment["toHeight"]) <= float(segment["fromHeight"]), "河沿顶点海拔不升高")
			_check(tile.riverEdges.has(segment["edge"]), "内部河路径全部已标记")
			_check(segment["startIndex"] == 0 or segment["startIndex"] == 1, "河路径端点索引合法")
			previous_height = float(segment["toHeight"])
			previous_end = end
			first = false
			path_edges["%s:%d" % [tile.id, segment["edge"]]] = true
		if not path.is_empty():
			_check(bool(path[-1]["endsAtBoundary"]) and _river_endpoint_is_boundary(state, previous_end), "河流真实终点边界")
	_check(path_edges.size() == marked.size(), "无游离河边")

func _river_vertex_height(state: GameState, endpoint: Vector3) -> float:
	var highest: float = 0.0
	for tile: HexTile in state.tiles.values():
		for edge: int in range(6):
			var points: Array[Vector3] = Hex.edge_vertices(tile.q, tile.r, edge)
			if endpoint.distance_to(points[0]) < 0.0001 or endpoint.distance_to(points[1]) < 0.0001:
				highest = maxf(highest, {"FLAT": 1.0, "HILL": 1.7, "MOUNTAIN": 3.0}[tile.relief])
	return highest

func _river_endpoint_is_boundary(state: GameState, endpoint: Vector3) -> bool:
	for tile: HexTile in state.tiles.values():
		for edge: int in range(6):
			var neighbor: Vector2i = Vector2i(tile.q, tile.r) + Hex.DIRECTIONS[edge]
			if state.tiles.has(Hex.id(neighbor.x, neighbor.y)): continue
			var points: Array[Vector3] = Hex.edge_vertices(tile.q, tile.r, edge)
			if endpoint.distance_to(points[0]) < 0.0001 or endpoint.distance_to(points[1]) < 0.0001: return true
	return false

func _edge_touches_high(state: GameState, tile: HexTile, edge: int) -> bool:
	var neighbor: Vector2i = Vector2i(tile.q, tile.r) + Hex.DIRECTIONS[edge]
	var key: String = Hex.id(neighbor.x, neighbor.y)
	return state.tiles.has(key) and state.tiles[key].relief in ["HILL", "MOUNTAIN"]

func _test_view(state: GameState, view: Dictionary) -> void:
	_check(view["tiles"].size() == state.tiles.size(), "全地图坐标 shell")
	_check(view["renderHints"]["reliefHeight"] == {"FLAT": 1.0, "HILL": 1.7, "MOUNTAIN": 3.0}, "渲染高度从配置下发")
	_check(not view.has("riverPaths") and not view.has("tileSnapshots") and not view.has("relations") and not view.has("lairs") and not view.has("disasters"), "内部信息与裁剪模块不下发")
	for key: String in view["tiles"]:
		var tile: Dictionary = view["tiles"][key]
		_check(tile.has("id") and tile.has("q") and tile.has("r") and tile.has("features") and tile.has("improvementId"), "tile 字段完整")
		if not state.sects[0].exploredTiles.has(key):
			for field: String in ["baseTerrain", "relief", "features", "riverEdges", "danger", "ownerSectId", "nodeId", "districtId", "workedByPeakId", "improvementId", "luxuryType"]:
				_check(tile[field] == null, "未探索 tile 不泄露 %s" % field)
	for sect: Dictionary in view["sects"]:
		_check(sect.has("disciples") and sect.has("spiritPeaks"), "嵌套弟子与峰")
		if sect["id"] != state.playerSectId:
			_check(not sect.has("resources"), "敌宗资源不泄露")
			for disciple: Dictionary in sect["disciples"]:
				_check(view["visibleTiles"].has(disciple["tileId"]), "敌单位仅视野内")
	for node: Dictionary in view["nodes"].values():
		_check(view["exploredTiles"].has(node["tileId"]), "未探索节点不泄露")

func _test_fog() -> void:
	var dispatcher: CommandDispatcher = CommandDispatcher.new(_config)
	_request(dispatcher, "newGame", {"sectName": "迷雾宗", "playerFaction": "ZONG_MEN", "randomSeed": "123456"})
	var state: GameState = dispatcher.state
	var player: Sect = state.sects[0]
	var enemy: Sect = state.sects[1]
	var key: String = enemy.spiritPeaks[0].tileId
	player.visibleTiles.append(key)
	player.exploredTiles.append(key)
	var initial: Dictionary = StateView.build(state, _config)
	var frozen: String = JSON.stringify(initial["tiles"][key])
	var old_peak: String = JSON.stringify(initial["sects"][1]["spiritPeaks"])
	var frozen_node_id: String = state.tiles[key].nodeId
	if not frozen_node_id.is_empty():
		state.nodes[frozen_node_id].ownerSectId = "hidden_owner"
	player.visibleTiles.erase(key)
	state.tiles[key].ownerSectId = "changed"
	state.tiles[key].improvementId = "new_secret"
	state.tiles[key].nodeId = "new_secret_node"
	enemy.spiritPeaks[0].defense = 999
	var hidden: Dictionary = StateView.build(state, _config)
	_check(JSON.stringify(hidden["tiles"][key]) == frozen, "失去视野 ownership/node/改良保持最后可见")
	_check(JSON.stringify(hidden["sects"][1]["spiritPeaks"]) == old_peak, "敌峰最后可见冻结")
	_check(hidden["sects"][1]["disciples"].is_empty(), "不可见敌单位不保留快照")
	if not frozen_node_id.is_empty(): _check(hidden["nodes"][frozen_node_id]["ownerSectId"] != "hidden_owner", "节点归属隐藏变化冻结")
	var remembered_peak: SpiritPeak = enemy.spiritPeaks[0]
	enemy.spiritPeaks.clear()
	_check(JSON.stringify(StateView.build(state, _config)["sects"][1]["spiritPeaks"]) == old_peak, "隐藏拆峰保留最后可见")
	player.visibleTiles.append(key)
	_check(StateView.build(state, _config)["sects"][1]["spiritPeaks"].is_empty(), "可见拆峰刷新删除快照")
	enemy.spiritPeaks.append(remembered_peak)
	player.visibleTiles.append(key)
	var visible: Dictionary = StateView.build(state, _config)
	_check(visible["tiles"][key]["improvementId"] == "new_secret", "恢复可见更新快照")
	var expected: Dictionary = {}
	for tile: HexTile in state.tiles.values():
		if Hex.distance(Hex.coords(player.spiritPeaks[0].tileId), Vector2i(tile.q, tile.r)) <= 3 + (1 if state.tiles[player.spiritPeaks[0].tileId].relief == "HILL" else 0): expected[tile.id] = true
	VisionCalculator.recalculate(state, _config)
	_check(player.visibleTiles.size() == expected.size(), "初始峰宗主半径与丘陵加一一致")
	for tile_id: String in expected: _check(player.visibleTiles.has(tile_id), "手算视野集合")

func _test_bonus() -> void:
	for difficulty: String in ["easy", "hard"]:
		var dispatcher: CommandDispatcher = CommandDispatcher.new(_config)
		_request(dispatcher, "newGame", {"sectName": "难度宗", "playerFaction": "JIA_ZU", "difficultyId": difficulty, "randomSeed": "1"})
		_check(dispatcher.state.sects[0].resources["spiritStones"] == (800 if difficulty == "easy" else 300), "easy 玩家补贴")
		_check(dispatcher.state.sects[1].resources["spiritStones"] == (900 if difficulty == "hard" else 300), "hard AI 石补贴")
		_check(dispatcher.state.sects[1].resources["workPower"] == (420 if difficulty == "hard" else 120), "hard AI 工补贴")
		_check(dispatcher.state.sects[0].disciples[0].bloodLine and dispatcher.state.sects[0].disciples[0].generation == 1, "家族始祖血脉")

func _authority(state: GameState) -> String:
	var tiles: Dictionary = {}
	for tile: HexTile in state.tiles.values(): tiles[tile.id] = tile.to_dict()
	var nodes: Dictionary = {}
	for node: GameNode in state.nodes.values(): nodes[node.id] = node.to_dict()
	return JSON.stringify({"seed": str(state.seed), "width": state.width, "height": state.height, "tiles": tiles, "nodes": nodes, "spawnTiles": state.spawnTiles, "riverPaths": state.riverPaths, "rngSequence": state.rng.sequence}, "\t", true)

func _export(filename: String, text: String) -> void:
	# globalize_path("res://") 带尾斜杠，必须先 trim 再取上级，否则会落到 server/ 而不是仓库根。
	var directory: String = ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir().path_join("outputs")
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output-dir="): directory = arg.substr(13)
	if not DirAccess.dir_exists_absolute(directory): DirAccess.make_dir_recursive_absolute(directory)
	_check(DirAccess.dir_exists_absolute(directory), "导出目录存在")
	var file: FileAccess = FileAccess.open(directory.path_join(filename), FileAccess.WRITE)
	_check(file != null, "导出权威地图 %s" % filename)
	if file != null:
		file.store_string(text)
		file.close()
