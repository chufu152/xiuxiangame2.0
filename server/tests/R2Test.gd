extends Node
## R2 自动验收：回合状态机 + 地形叠加移动成本 + BFS 可达 + 移动后视野刷新。
##
## 无头运行：`godot --headless --path server res://tests/R2Test.tscn`，
## 全绿打印 `R2_PASS checks=N` 并退出码 0，否则 `R2_FAIL ...` 退出码 1。
##
## 断言全部**独立复算**（不直接复用被测函数作为期望值来源）；
## 涉及具体地形代价处使用字面期望值，以交叉验证 `MoveRules.step_cost`。

var _failures: Array[String] = []
var _checks: int = 0
var _config: Dictionary = {}
var _finished: bool = false
var _started: int = Time.get_ticks_msec()


func _process(_delta: float) -> void:
	if not _finished and Time.get_ticks_msec() - _started > 60000:
		printerr("R2_FAIL 测试未正常完成（可能运行时脚本错误）")
		get_tree().quit(1)


func _ready() -> void:
	var loaded: Dictionary = ConfigLoader.load_from_file(ConfigLoader.default_path())
	_check(bool(loaded["ok"]), "配置可加载")
	_config = loaded["config"]
	_check(ConfigValidator.validate(_config).is_empty(), "配置通过深层验证")
	_test_registration()
	_test_max_move_points()
	_test_terrain_costs()
	_test_query_move_range()
	_test_move_disciple()
	_test_vision_on_move()
	_test_turns()
	_test_determinism()
	_finished = true
	if _failures.is_empty():
		print("R2_PASS checks=%d" % _checks)
		get_tree().quit(0)
	else:
		for message: String in _failures:
			printerr("R2_FAIL ", message)
		print("R2_FAIL checks=%d failures=%d" % [_checks, _failures.size()])
		get_tree().quit(1)


# ---------------------------------------------------------------------------
# 0. 命令登记
# ---------------------------------------------------------------------------

func _test_registration() -> void:
	var dispatcher: CommandDispatcher = CommandDispatcher.new(_config)
	var implemented: Array = dispatcher.implemented_commands()
	for command: String in ["ping", "newGame", "getState", "finishTurn", "beginPlayerTurn", "nextTurn", "moveDisciple", "queryMoveRange"]:
		_check(implemented.has(command), "已登记命令：" + command)
	_check(implemented.size() >= 8, "已登记命令不少于 R2 的 8 条（ping + 7）")
	for command: String in ["finishTurn", "beginPlayerTurn", "nextTurn", "moveDisciple", "queryMoveRange"]:
		var response: Dictionary = _request(dispatcher, command, {})
		_check(response.get("errorCode") == "NO_GAME", "%s 开局前 NO_GAME" % command)


# ---------------------------------------------------------------------------
# 1. 移动力公式（裁决一：所有灵根都按 rootMoveBonus 计）
# ---------------------------------------------------------------------------

func _test_max_move_points() -> void:
	var setup: Dictionary = _config["map"]["setup"]
	var base: int = int(_config["disciple"]["baseMovePoints"])
	# 逐灵根：1.0 只加 FENG/ZA 的 bug 会在这里对 JIN/MU/SHUI/HUO/TU/LEI 全部失败。
	for root: String in setup["rootTypes"]:
		var probe: Disciple = Disciple.new()
		probe.realm = "LIAN_QI"
		probe.unitClass = "PU_TONG"
		probe.spiritRoots = [root]
		var expected: int = base + int(setup["realmMoveBonus"]["LIAN_QI"]) + int(setup["rootMoveBonus"][root]) + int(_config["warfare"]["unitClasses"]["PU_TONG"]["moveBonus"])
		_check(MoveRules.calculate_max_move_points(probe, _config) == expected, "灵根 %s 加成按配置" % root)
	for realm: String in ["LIAN_QI", "ZHU_JI", "JIN_DAN", "YUAN_YING", "HUA_SHEN"]:
		var probe: Disciple = Disciple.new()
		probe.realm = realm
		probe.unitClass = "PU_TONG"
		probe.spiritRoots = []
		_check(MoveRules.calculate_max_move_points(probe, _config) == base + int(setup["realmMoveBonus"][realm]), "境界 %s 移动力加成" % realm)
	# 多灵根累加
	var multi: Disciple = Disciple.new()
	multi.realm = "JIN_DAN"
	multi.unitClass = "PU_TONG"
	multi.spiritRoots = ["JIN", "HUO"]
	_check(MoveRules.calculate_max_move_points(multi, _config) == base + 1 + 1 + 1, "多灵根与境界累加")
	# 开局：每名弟子 maxMovePoints == movePoints == 独立复算值
	var dispatcher: CommandDispatcher = CommandDispatcher.new(_config)
	_request(dispatcher, "newGame", {"sectName": "移动力宗", "playerFaction": "ZONG_MEN", "randomSeed": "123456"})
	var state: GameState = dispatcher.state
	var total: int = 0
	for sect: Sect in state.sects:
		for disciple: Disciple in sect.disciples:
			total += 1
			var want: int = base + int(setup["realmMoveBonus"][disciple.realm])
			for root: String in disciple.spiritRoots: want += int(setup["rootMoveBonus"][root])
			want += int(_config["warfare"]["unitClasses"][disciple.unitClass]["moveBonus"])
			_check(disciple.maxMovePoints == want, "%s maxMovePoints 复算" % disciple.id)
			_check(disciple.movePoints == want, "%s 开局 movePoints==maxMovePoints" % disciple.id)
			_check(disciple.attacksRemaining == int(_config["warfare"]["attacksPerTurn"]), "%s 开局出手数" % disciple.id)
			_check(disciple.turnsInSect == 0, "%s 开局 turnsInSect=0" % disciple.id)
			_check(disciple.to_dict().has("maxMovePoints") and disciple.to_dict().has("turnsInSect"), "%s to_dict 含新字段" % disciple.id)
	_check(total == 12, "四宗十二弟子全部复算")


# ---------------------------------------------------------------------------
# 2. 地形叠加代价 + BFS 可达（最小构造地图，字面期望值）
# ---------------------------------------------------------------------------

func _test_terrain_costs() -> void:
	# 起点 (0,0) FLAT，六邻分别覆盖 平地/丘陵/灵林/雾泽/险地/跨河，另加一山岳验证排除。
	var specs: Array[Dictionary] = [
		{"q": 0, "r": 0},
		{"q": 1, "r": 0, "relief": "FLAT"},
		{"q": 1, "r": -1, "relief": "HILL"},
		{"q": 0, "r": -1, "relief": "FLAT", "features": ["SPIRIT_FOREST"]},
		{"q": -1, "r": 0, "relief": "FLAT", "features": ["MIRE"]},
		{"q": -1, "r": 1, "relief": "FLAT", "danger": true},
		{"q": 0, "r": 1, "relief": "FLAT", "riverEdges": [2]},
		{"q": 2, "r": 0, "relief": "MOUNTAIN"},
	]
	var state: GameState = _make_state(specs)
	# 起点自己不带河边；跨河由对邻 (0,1) 的第 opposite(5)=2 条边标记。
	var disciple: Disciple = _make_disciple(state, "q0_r0", 10)

	_check(MoveRules.is_passable(state.tiles["q1_r0"], _config), "平地可通行")
	_check(MoveRules.is_passable(state.tiles["q1_r-1"], _config), "丘陵可通行")
	_check(not MoveRules.is_passable(state.tiles["q2_r0"], _config), "山岳不可通行")
	_check(MoveRules.step_cost(_config, state.tiles["q0_r0"], state.tiles["q2_r0"]) == MoveRules.IMPASSABLE, "山岳 step_cost 返回不可通行标记")
	_check(MoveRules.step_cost(_config, state.tiles["q0_r0"], state.tiles["q1_r0"]) == 1, "平地进入代价 1")
	_check(MoveRules.step_cost(_config, state.tiles["q0_r0"], state.tiles["q1_r-1"]) == 2, "丘陵进入代价 2")
	_check(MoveRules.step_cost(_config, state.tiles["q0_r0"], state.tiles["q0_r-1"]) == 2, "灵林 +1")
	_check(MoveRules.step_cost(_config, state.tiles["q0_r0"], state.tiles["q-1_r0"]) == 2, "雾泽 +1")
	_check(MoveRules.step_cost(_config, state.tiles["q0_r0"], state.tiles["q-1_r1"]) == 2, "险地附加 1（dangerTileMoveCost=1）")
	_check(_config["map"]["dangerTileMoveCost"] == 1, "配置 dangerTileMoveCost 已改为 1（裁决二）")
	_check(MoveRules.crosses_river(state.tiles["q0_r0"], state.tiles["q0_r1"]), "跨河判定（对邻边标记）")
	_check(MoveRules.step_cost(_config, state.tiles["q0_r0"], state.tiles["q0_r1"]) == 2, "跨河 +1")
	_check(not MoveRules.crosses_river(state.tiles["q0_r0"], state.tiles["q1_r0"]), "无河不跨河")

	var reach: Dictionary = MoveRangeCalculator.reachable(state, _config, disciple)
	var costs: Dictionary = reach["costs"]
	var order: Array = reach["order"]
	_check(str(reach["origin"]) == "q0_r0", "origin 为起点")
	_check(str(order[0]) == "q0_r0", "order[0] 为起点")
	_check(int(costs["q0_r0"]) == 0, "起点代价 0")
	_check(int(costs["q1_r0"]) == 1, "BFS：平地 1")
	_check(int(costs["q1_r-1"]) == 2, "BFS：丘陵 2")
	_check(int(costs["q0_r-1"]) == 2, "BFS：灵林 2")
	_check(int(costs["q-1_r0"]) == 2, "BFS：雾泽 2")
	_check(int(costs["q-1_r1"]) == 2, "BFS：险地 2")
	_check(int(costs["q0_r1"]) == 2, "BFS：跨河 2")
	_check(not costs.has("q2_r0"), "BFS：山岳不进高亮")
	_check(not order.has("q2_r0"), "BFS：山岳不在 order")
	_check(order.size() == costs.size(), "order 与 costs 同规模（首次发现顺序）")
	# 与独立复算（Bellman-Ford 式反复松弛）逐项一致
	var reference: Dictionary = _reference_costs(state, _config, "q0_r0", 10)
	_check(_same_costs(costs, reference), "BFS 代价与独立复算逐项一致")
	# 预算受限：只剩 1 点移动力时只能走到平地邻格
	var poor: Disciple = _make_disciple(state, "q0_r0", 1)
	var tight: Dictionary = MoveRangeCalculator.reachable(state, _config, poor)["costs"]
	_check(int(tight.get("q1_r0", -1)) == 1 and not tight.has("q1_r-1"), "预算 1 时丘陵不可达")


# ---------------------------------------------------------------------------
# 3. queryMoveRange / moveDisciple
# ---------------------------------------------------------------------------

func _test_query_move_range() -> void:
	var dispatcher: CommandDispatcher = CommandDispatcher.new(_config)
	_request(dispatcher, "newGame", {"sectName": "移动宗", "playerFaction": "ZONG_MEN", "randomSeed": "123456"})
	var state: GameState = dispatcher.state
	var disciple: Disciple = state.sects[0].disciples[0]
	var response: Dictionary = _request(dispatcher, "queryMoveRange", {"discipleId": disciple.id})
	_check(bool(response.get("ok", false)), "queryMoveRange ok")
	_check(not response.has("view"), "queryMoveRange 不回 view（只读）")
	var result: Dictionary = response["result"]
	_check(str(result["discipleId"]) == disciple.id, "result.discipleId 正确")
	_check(str(result["originTileId"]) == disciple.tileId, "originTileId == 起点")
	_check((result["tileIds"] as Array)[0] == disciple.tileId, "tileIds[0] == 起点")
	_check(int(result["costs"][disciple.tileId]) == 0, "costs[起点] == 0")
	_check(int(result["movePoints"]) == disciple.movePoints and int(result["maxMovePoints"]) == disciple.maxMovePoints, "movePoints/maxMovePoints 回包")
	_check(int(result["tileCount"]) == (result["tileIds"] as Array).size(), "tileCount 与 tileIds 一致")
	# 全量逐格独立复算
	var reference: Dictionary = _reference_costs(state, _config, disciple.tileId, disciple.movePoints)
	_check(_same_costs(result["costs"], reference), "真实地图 costs 与独立复算逐项一致")
	_check((result["tileIds"] as Array).size() == reference.size(), "真实地图可达格数一致")
	var mountains: int = 0
	for value: Variant in result["tileIds"]:
		var tile: HexTile = state.tiles[str(value)]
		if tile.relief == "MOUNTAIN": mountains += 1
	_check(mountains == 0, "真实地图山岳不进 tileIds")
	# 非玩家 / 不存在弟子 -> BAD_PARAMS
	var enemy: Disciple = state.sects[1].disciples[0]
	_check(_request(dispatcher, "queryMoveRange", {"discipleId": enemy.id}).get("errorCode") == "BAD_PARAMS", "非玩家弟子 BAD_PARAMS")
	_check(_request(dispatcher, "queryMoveRange", {"discipleId": "nope"}).get("errorCode") == "BAD_PARAMS", "不存在弟子 BAD_PARAMS")
	_check(_request(dispatcher, "queryMoveRange", {}).get("errorCode") == "BAD_PARAMS", "缺 discipleId BAD_PARAMS")


func _test_move_disciple() -> void:
	var dispatcher: CommandDispatcher = CommandDispatcher.new(_config)
	_request(dispatcher, "newGame", {"sectName": "行宗", "playerFaction": "ZONG_MEN", "randomSeed": "123456"})
	var state: GameState = dispatcher.state
	var player: Sect = state.sects[0]
	var enemy: Sect = state.sects[1]
	var disciple: Disciple = player.disciples[0]
	var range_result: Dictionary = _request(dispatcher, "queryMoveRange", {"discipleId": disciple.id})["result"]
	var costs: Dictionary = range_result["costs"]
	var origin: String = disciple.tileId
	var target: String = ""
	for value: Variant in range_result["tileIds"]:
		var candidate: String = str(value)
		if candidate != origin and int(costs[candidate]) >= 1 and int(costs[candidate]) <= disciple.movePoints:
			target = candidate
			break
	_check(not target.is_empty(), "存在可达目标格")
	var expected_cost: int = int(costs[target])
	var expected_remaining: int = disciple.movePoints - expected_cost
	var response: Dictionary = _request(dispatcher, "moveDisciple", {"discipleId": disciple.id, "targetTileId": target})
	_check(bool(response.get("ok", false)), "moveDisciple ok")
	_check(response.has("view"), "moveDisciple 回 view")
	var result: Dictionary = response["result"]
	_check(bool(result["success"]), "MoveResult.success=true")
	_check(str(result["reachedTileId"]) == target, "reachedTileId == 目标")
	_check(int(result["turnsRemaining"]) == expected_remaining, "turnsRemaining == movePoints-cost")
	_check(str(result["triggeredEvent"]) == "", "R2 triggeredEvent 为空串")
	_check(disciple.tileId == target, "权威位置已更新")
	_check(disciple.movePoints == expected_remaining, "移动力已扣减")
	_check(state.eventLog.size() >= 1 and str(state.eventLog[-1]).contains(target), "eventLog 追加移动事件")
	_check(not (response["view"]["sects"][0]["disciples"][0] as Dictionary).is_empty(), "view 中弟子可见")
	# 连续第二次移动按剩余移动力扣减
	var second_range: Dictionary = _request(dispatcher, "queryMoveRange", {"discipleId": disciple.id})["result"]
	_check(str(second_range["originTileId"]) == target, "第二次 query 起点为新位置")
	_check(int(second_range["movePoints"]) == expected_remaining, "第二次 query 用剩余移动力")
	var second_target: String = ""
	for value: Variant in second_range["tileIds"]:
		var candidate: String = str(value)
		if candidate != target and int(second_range["costs"][candidate]) <= expected_remaining and int(second_range["costs"][candidate]) >= 1:
			second_target = candidate
			break
	if not second_target.is_empty():
		var second: Dictionary = _request(dispatcher, "moveDisciple", {"discipleId": disciple.id, "targetTileId": second_target})["result"]
		_check(bool(second["success"]), "连续第二次移动成功")
		_check(disciple.movePoints == expected_remaining - int(second_range["costs"][second_target]), "连续两次移动扣减正确")

	# 失败路径：山岳 / 超预算 / 不存在 id / 非玩家弟子 —— 状态必须不变
	var before_tile: String = disciple.tileId
	var before_points: int = disciple.movePoints
	var mountain: String = ""
	for tile: HexTile in state.tiles.values():
		if tile.relief == "MOUNTAIN":
			mountain = tile.id
			break
	if not mountain.is_empty():
		var blocked: Dictionary = _request(dispatcher, "moveDisciple", {"discipleId": disciple.id, "targetTileId": mountain})["result"]
		_check(not bool(blocked["success"]), "山岳不可达：success=false")
		_check(str(blocked["reachedTileId"]) == before_tile, "山岳失败：reachedTileId 保持原位")
		_check(disciple.tileId == before_tile and disciple.movePoints == before_points, "山岳失败：状态不变")
	var saved_points: int = disciple.movePoints
	var standing: String = disciple.tileId
	disciple.movePoints = 0
	var over: Dictionary = _request(dispatcher, "moveDisciple", {"discipleId": disciple.id, "targetTileId": standing})["result"]
	_check(bool(over["success"]), "零移动力时仍可「移动到原地」")
	disciple.movePoints = saved_points
	var any_neighbor: String = ""
	for direction: Vector2i in Hex.DIRECTIONS:
		var neighbor_id: String = Hex.id(Hex.coords(disciple.tileId).x + direction.x, Hex.coords(disciple.tileId).y + direction.y)
		if state.tiles.has(neighbor_id): any_neighbor = neighbor_id
	if not any_neighbor.is_empty():
		disciple.movePoints = 0
		var out_of_budget: Dictionary = _request(dispatcher, "moveDisciple", {"discipleId": disciple.id, "targetTileId": any_neighbor})["result"]
		_check(not bool(out_of_budget["success"]) or any_neighbor == disciple.tileId, "零移动力时邻格不可达")
		_check(disciple.movePoints == 0 and disciple.tileId == before_tile, "超预算失败：状态不变")
		disciple.movePoints = saved_points
	_check(_request(dispatcher, "moveDisciple", {"discipleId": "nope", "targetTileId": origin}).get("errorCode") == "BAD_PARAMS", "不存在弟子 BAD_PARAMS")
	_check(_request(dispatcher, "moveDisciple", {"discipleId": enemy.disciples[0].id, "targetTileId": origin}).get("errorCode") == "BAD_PARAMS", "非玩家弟子 BAD_PARAMS")
	_check(_request(dispatcher, "moveDisciple", {"discipleId": disciple.id, "targetTileId": "q999_r999"}).get("errorCode") == "BAD_PARAMS", "目标格不存在 BAD_PARAMS")
	_check(_request(dispatcher, "moveDisciple", {"discipleId": disciple.id}).get("errorCode") == "BAD_PARAMS", "缺 targetTileId BAD_PARAMS")


# ---------------------------------------------------------------------------
# 4. 移动后视野刷新
# ---------------------------------------------------------------------------

func _test_vision_on_move() -> void:
	var dispatcher: CommandDispatcher = CommandDispatcher.new(_config)
	_request(dispatcher, "newGame", {"sectName": "视野宗", "playerFaction": "ZONG_MEN", "randomSeed": "123456"})
	var state: GameState = dispatcher.state
	var player: Sect = state.sects[0]
	var disciple: Disciple = player.disciples[0]
	var before_visible: Array[String] = player.visibleTiles.duplicate()
	var before_explored: Array[String] = player.exploredTiles.duplicate()
	var range_result: Dictionary = _request(dispatcher, "queryMoveRange", {"discipleId": disciple.id})["result"]
	var target: String = ""
	for value: Variant in range_result["tileIds"]:
		if str(value) != disciple.tileId:
			target = str(value)
			break
	_check(not target.is_empty(), "存在可移动目标格")
	_request(dispatcher, "moveDisciple", {"discipleId": disciple.id, "targetTileId": target})
	_check(disciple.tileId == target, "视野测试：位置已更新")
	# 独立复算 recalculate 的期望可见集合
	var expected: Dictionary = _expected_visible(state, _config, player)
	_check(player.visibleTiles.size() == expected.size(), "移动后 visibleTiles 与独立复算同规模")
	var mismatch: bool = false
	for tile_id: String in expected:
		if not player.visibleTiles.has(tile_id): mismatch = true
	_check(not mismatch, "移动后 visibleTiles 与独立复算逐项一致")
	_check(player.visibleTiles.has(target), "新位置已揭示")
	# 旧位置若已离开视野则降级为「已探索」，不丢失
	var demoted: bool = true
	for tile_id: String in before_visible:
		if not player.exploredTiles.has(tile_id): demoted = false
	_check(demoted, "旧可见格降级为已探索（不丢失）")
	_check(player.exploredTiles.size() >= before_explored.size(), "已探索集合只增不减")
	_check(player.visibleTiles != before_visible or before_visible.has(target), "视野随移动发生变化")


# ---------------------------------------------------------------------------
# 5. 回合状态机
# ---------------------------------------------------------------------------

func _test_turns() -> void:
	var dispatcher: CommandDispatcher = CommandDispatcher.new(_config)
	_request(dispatcher, "newGame", {"sectName": "回合宗", "playerFaction": "ZONG_MEN", "randomSeed": "123456"})
	var state: GameState = dispatcher.state
	_check(state.turn == 1, "开局第 1 回合")
	_check(state.phase == "PLAYER_ACTION", "开局 PLAYER_ACTION")
	var before: int = state.turn
	var finished: Dictionary = _request(dispatcher, "finishTurn")
	_check(bool(finished.get("ok", false)), "finishTurn ok")
	_check(finished.has("view"), "finishTurn 回 view")
	_check(state.turn == before + 1, "finishTurn 回合 +1")
	_check(state.phase == "PLAYER_ACTION", "finishTurn 后回到 PLAYER_ACTION")
	_check((finished.get("events", []) as Array).size() >= 1, "finishTurn events 为事件字符串数组")
	_check(not state.gameOver, "R2 不终局（VICTORY_CHECK 留空）")
	# beginPlayerTurn 恢复移动力 / 重置出手 / turnsInSect+1
	for sect: Sect in state.sects:
		for disciple: Disciple in sect.disciples:
			disciple.movePoints = 0
			disciple.attacksRemaining = 0
	var turns_before: Dictionary = {}
	for sect: Sect in state.sects:
		for disciple: Disciple in sect.disciples:
			turns_before[disciple.id] = disciple.turnsInSect
	var began: Dictionary = _request(dispatcher, "beginPlayerTurn")
	_check(bool(began.get("ok", false)), "beginPlayerTurn ok")
	_check((began.get("events", []) as Array).size() >= 1, "beginPlayerTurn events 非空")
	for sect: Sect in state.sects:
		for disciple: Disciple in sect.disciples:
			_check(disciple.movePoints == disciple.maxMovePoints, "%s 恢复移动力" % disciple.id)
			_check(disciple.attacksRemaining == int(_config["warfare"]["attacksPerTurn"]), "%s 重置出手" % disciple.id)
			_check(disciple.turnsInSect == int(turns_before[disciple.id]) + 1, "%s turnsInSect+1" % disciple.id)
	_check(state.eventLog.size() >= 1, "beginPlayerTurn 写入事件日志")
	# nextTurn = begin + finish
	var turn_before: int = state.turn
	var next: Dictionary = _request(dispatcher, "nextTurn")
	_check(bool(next.get("ok", false)), "nextTurn ok")
	_check(state.turn == turn_before + 1, "nextTurn 推进一回合")
	_check((next.get("events", []) as Array).size() >= 2, "nextTurn 含开始与结算两条事件")
	for command: String in ["finishTurn", "beginPlayerTurn", "nextTurn"]:
		var fresh: CommandDispatcher = CommandDispatcher.new(_config)
		_check(_request(fresh, command).get("errorCode") == "NO_GAME", "%s 未开局 NO_GAME" % command)


# ---------------------------------------------------------------------------
# 6. 确定性
# ---------------------------------------------------------------------------

func _test_determinism() -> void:
	var first: String = _run_sequence()
	var second: String = _run_sequence()
	_check(not first.is_empty(), "指令序列可执行")
	_check(first == second, "同种子同指令序列双跑关键 view 逐字一致")


func _run_sequence() -> String:
	var dispatcher: CommandDispatcher = CommandDispatcher.new(_config)
	_request(dispatcher, "newGame", {"sectName": "确定性宗", "playerFaction": "ZONG_MEN", "randomSeed": "20261016"})
	var state: GameState = dispatcher.state
	var disciple: Disciple = state.sects[0].disciples[0]
	var range_result: Dictionary = _request(dispatcher, "queryMoveRange", {"discipleId": disciple.id})["result"]
	var target: String = ""
	for value: Variant in range_result["tileIds"]:
		if str(value) != disciple.tileId:
			target = str(value)
			break
	_request(dispatcher, "moveDisciple", {"discipleId": disciple.id, "targetTileId": target})
	_request(dispatcher, "finishTurn")
	_request(dispatcher, "beginPlayerTurn")
	var second_range: Dictionary = _request(dispatcher, "queryMoveRange", {"discipleId": disciple.id})["result"]
	var second_target: String = ""
	for value: Variant in second_range["tileIds"]:
		if str(value) != disciple.tileId:
			second_target = str(value)
			break
	if not second_target.is_empty():
		_request(dispatcher, "moveDisciple", {"discipleId": disciple.id, "targetTileId": second_target})
	var snapshot: Dictionary = _request(dispatcher, "getState")["view"]
	var owners: Dictionary = {}
	for tile_id: String in snapshot["tiles"]:
		owners[tile_id] = snapshot["tiles"][tile_id]["ownerSectId"]
	var positions: Dictionary = {}
	var points: Dictionary = {}
	for sect: Dictionary in snapshot["sects"]:
		for item: Dictionary in sect["disciples"]:
			positions[item["id"]] = item["tileId"]
			points[item["id"]] = item["movePoints"]
	return JSON.stringify({
		"turn": snapshot["metadata"]["turn"],
		"phase": snapshot["metadata"]["phase"],
		"positions": positions,
		"movePoints": points,
		"visibleTiles": snapshot["visibleTiles"],
		"exploredTiles": snapshot["exploredTiles"],
		"owners": owners,
	}, "\t", true)


# ---------------------------------------------------------------------------
# 辅助
# ---------------------------------------------------------------------------

func _request(dispatcher: CommandDispatcher, command: String, params: Dictionary = {}) -> Dictionary:
	return dispatcher.dispatch_text(JSON.stringify({"id": "test", "type": command, "params": params}))


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


## 独立复算：反复松弛直至稳定（不依赖被测的队列式 BFS）。
func _reference_costs(state: GameState, config: Dictionary, origin: String, move_points: int) -> Dictionary:
	var costs: Dictionary = {origin: 0}
	var changed: bool = true
	while changed:
		changed = false
		for tile: HexTile in state.tiles.values():
			if not costs.has(tile.id): continue
			for direction: Vector2i in Hex.DIRECTIONS:
				var neighbor_id: String = Hex.id(tile.q + direction.x, tile.r + direction.y)
				if not state.tiles.has(neighbor_id): continue
				var neighbor: HexTile = state.tiles[neighbor_id]
				if not MoveRules.is_passable(neighbor, config): continue
				var total: int = int(costs[tile.id]) + MoveRules.step_cost(config, tile, neighbor)
				if total > move_points: continue
				if not costs.has(neighbor_id) or total < int(costs[neighbor_id]):
					costs[neighbor_id] = total
					changed = true
	return costs


func _same_costs(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size(): return false
	for key: String in b:
		if not a.has(key) or int(a[key]) != int(b[key]): return false
	return true


## 独立复算 VisionCalculator 的期望可见集合（验证移动确实触发了完整重算）。
func _expected_visible(state: GameState, config: Dictionary, sect: Sect) -> Dictionary:
	var visible: Dictionary = {}
	for peak: SpiritPeak in sect.spiritPeaks:
		_reveal(state, config, peak.tileId, int(config["vision"]["peakVision"]), visible)
	for node: GameNode in state.nodes.values():
		if node.ownerSectId == sect.id: _reveal(state, config, node.tileId, int(config["vision"]["nodeVision"]), visible)
	for disciple: Disciple in sect.disciples:
		var radius: int = int(config["vision"]["discipleVisionByRealm"][disciple.realm]) + int(config["warfare"]["unitClasses"][disciple.unitClass]["visionBonus"])
		_reveal(state, config, disciple.tileId, radius, visible)
	return visible


func _reveal(state: GameState, config: Dictionary, center: String, radius: int, visible: Dictionary) -> void:
	var tile: HexTile = state.tiles[center]
	var effective: int = radius + int(config["map"]["relief"][tile.relief]["visionBonus"])
	for candidate: HexTile in state.tiles.values():
		if Hex.distance(Vector2i(tile.q, tile.r), Vector2i(candidate.q, candidate.r)) <= effective:
			visible[candidate.id] = true


func _make_state(specs: Array[Dictionary]) -> GameState:
	var state: GameState = GameState.new()
	state.width = 6
	state.height = 6
	state.difficulty = "normal"
	state.playerSectId = "sect_0"
	for spec: Dictionary in specs:
		var tile: HexTile = HexTile.new()
		tile.q = int(spec["q"])
		tile.r = int(spec["r"])
		tile.id = Hex.id(tile.q, tile.r)
		tile.baseTerrain = "SPIRIT_PLAIN"
		tile.relief = str(spec.get("relief", "FLAT"))
		for feature: Variant in spec.get("features", []): tile.features.append(str(feature))
		for edge: Variant in spec.get("riverEdges", []): tile.riverEdges.append(int(edge))
		tile.danger = bool(spec.get("danger", false))
		state.tiles[tile.id] = tile
	return state


func _make_disciple(state: GameState, tile_id: String, move_points: int) -> Disciple:
	var disciple: Disciple = Disciple.new()
	disciple.id = "d_fixture"
	disciple.name = "构造弟子"
	disciple.sectId = state.playerSectId
	disciple.tileId = tile_id
	disciple.movePoints = move_points
	disciple.maxMovePoints = move_points
	var sect: Sect = Sect.new()
	sect.id = state.playerSectId
	sect.name = "构造宗"
	sect.player = true
	sect.disciples.append(disciple)
	state.sects.append(sect)
	return disciple
