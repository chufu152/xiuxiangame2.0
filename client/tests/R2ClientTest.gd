extends Node
## R2 客户端验收：点选 → 高亮 → 移动 → 结束回合 的真机端到端。
##
## 无头运行：`godot --headless --path client res://tests/R2ClientTest.tscn [-- --integration]`。
## 不带 `--integration` 时只跑不依赖服务端的表现层断言。

var checks: int = 0
var failures: int = 0
var world: Node3D = null


func _ready() -> void:
	await get_tree().process_frame
	var session: Node = get_node("/root/Session")
	# hello 前：TopBar 必须已构建且「结束回合」禁用（门控）。
	world = (load("res://scenes/World.tscn") as PackedScene).instantiate() as Node3D
	add_child(world)
	await get_tree().process_frame
	check(world.get("end_turn_button") != null, "TopBar 结束回合按钮已构建")
	check((world.get("end_turn_button") as Button).disabled, "hello 前结束回合按钮禁用")
	check(int(world.call("highlight_count")) == 0, "初始无移动高亮")
	var map: Node3D = world.get_node("HexMap") as Node3D
	map.call("show_move_range", ["a", "b", "c"], {"a": 0, "b": 1, "c": 2}, "a")
	check(int(world.call("highlight_count")) == 0, "未载入地图时高亮不误增")
	map.call("clear_move_range")
	check(int(world.call("highlight_count")) == 0, "清除高亮后归零")
	world.queue_free()
	world = null
	await get_tree().process_frame
	if OS.get_cmdline_user_args().has("--integration"):
		await integration(session)
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		check(get_viewport().get_texture().get_image().save_png("res://outputs/R2_live.png") == OK, "R2 GUI 截图保存成功")
	finish()


func integration(session: Node) -> void:
	session.call("start_connection", 19538)
	var deadline: int = Time.get_ticks_msec() + 45000
	while not bool(session.call("supports", "newGame")) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check(bool(session.call("supports", "newGame")), "端到端：收到 newGame hello")
	if not bool(session.call("supports", "newGame")):
		session.call("shutdown")
		return
	for command: String in ["finishTurn", "beginPlayerTurn", "moveDisciple", "queryMoveRange"]:
		check(bool(session.call("supports", command)), "端到端：hello 声明支持 " + command)

	var old_revision: int = int(session.get("view_revision"))
	session.call("request_new_game", {"playerFaction": "ZONG_MEN", "sectName": "青岚测试宗", "mapWidth": 20, "mapHeight": 15, "randomSeed": "123456", "difficultyId": "normal"})
	deadline = Time.get_ticks_msec() + 20000
	while int(session.get("view_revision")) == old_revision and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check(int(session.get("view_revision")) > old_revision, "端到端：newGame 返回 view")

	world = (load("res://scenes/World.tscn") as PackedScene).instantiate() as Node3D
	add_child(world)
	await get_tree().process_frame
	var camera: Camera3D = (session.get("camera_rig") as Node).get("camera") as Camera3D
	var transform_before: Transform3D = camera.global_transform
	var size_before: float = camera.size

	var player_sect: Dictionary = _player_sect(session)
	check(not player_sect.is_empty(), "端到端：view 含玩家宗门")
	if player_sect.is_empty():
		session.call("shutdown")
		return
	var disciples: Array = player_sect["disciples"]
	check(disciples.size() >= 1, "端到端：玩家有弟子")
	var disciple: Dictionary = disciples[0]
	var disciple_id: String = str(disciple["id"])
	var start_tile: String = str(disciple["tileId"])
	var start_points: int = int(disciple.get("movePoints", -1))
	var start_max: int = int(disciple.get("maxMovePoints", -1))
	check(start_points >= 1, "端到端：开局弟子有移动力")
	check(start_points == start_max, "端到端：开局 movePoints == maxMovePoints")

	# ① 点选己方弟子 → 高亮
	world.call("select_disciple", disciple_id)
	deadline = Time.get_ticks_msec() + 15000
	while int(world.call("highlight_count")) == 0 and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	var highlight: int = int(world.call("highlight_count"))
	var reachable: Array = world.get("reachable_ids")
	check(highlight >= 1, "端到端：点选弟子后出现移动高亮")
	check(highlight == reachable.size(), "端到端：高亮格数与 queryMoveRange 结果一致")
	check(bool(world.get("move_mode")), "端到端：进入移动模式")
	check((world.get_node("UnitView") as Node3D).call("marker_count") == 1, "端到端：选中弟子有标记")
	var reachable_map: Dictionary = {}
	for value: Variant in reachable:
		reachable_map[str(value)] = true
	check(reachable_map.has(start_tile), "端到端：可达集含起点")

	# ② 点可达格 → moveDisciple 成功、单位位置更新、迷雾变化
	# 取累计代价最大的可达格，使视野环真正外移（短距离移动可能不改变可见集合）。
	var target: String = ""
	var best_cost: int = -1
	var costs: Dictionary = world.get("reachable_costs")
	for value: Variant in reachable:
		var candidate: String = str(value)
		if candidate == start_tile:
			continue
		var cost: int = int(costs.get(candidate, -1))
		if cost > best_cost:
			best_cost = cost
			target = candidate
	check(not target.is_empty(), "端到端：存在可移动目标格")
	check(int(costs.get(target, 0)) >= 1 and int(costs.get(target, 0)) <= start_points, "端到端：目标格在剩余移动力内")
	var positions_before: Dictionary = _unit_positions(world)
	var visible_before: Array = (session.get("current_view") as Dictionary)["visibleTiles"].duplicate()
	world.call("on_tile_clicked", target)
	deadline = Time.get_ticks_msec() + 15000
	while str(_find_disciple(session, disciple_id).get("tileId", "")) != target and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	var moved: Dictionary = _find_disciple(session, disciple_id)
	check(str(moved.get("tileId", "")) == target, "端到端：moveDisciple 成功，权威位置更新")
	check(int(moved.get("movePoints", -1)) < start_points, "端到端：移动力已扣减")
	var positions_after: Dictionary = _unit_positions(world)
	check(positions_after.has(disciple_id), "端到端：移动后单位仍在场景")
	if positions_before.has(disciple_id) and positions_after.has(disciple_id):
		check((positions_before[disciple_id] as Vector3).distance_to(positions_after[disciple_id]) > 0.001, "端到端：单位世界坐标随移动更新")
	var visible_after: Array = (session.get("current_view") as Dictionary)["visibleTiles"]
	check(visible_after.has(target), "端到端：新位置已揭示")
	check(visible_after != visible_before, "端到端：移动后迷雾变化（visibleTiles 更新）")
	# 移动成功会触发一次 queryMoveRange 重查；UI 上「结束回合」在此期间禁用。
	deadline = Time.get_ticks_msec() + 15000
	while bool(session.get("busy")) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check(not bool(session.get("busy")), "端到端：移动收尾后不再 busy")

	# ③ 结束回合（finishTurn → beginPlayerTurn），经由 TopBar 按钮
	check(not (world.get("end_turn_button") as Button).disabled, "端到端：空闲时结束回合按钮可用")
	var turn_before: int = int((session.get("current_view") as Dictionary)["metadata"]["turn"])
	(world.get("end_turn_button") as Button).emit_signal("pressed")
	deadline = Time.get_ticks_msec() + 25000
	while (int((session.get("current_view") as Dictionary)["metadata"]["turn"]) == turn_before or bool(session.get("end_turn_pending"))) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	var turn_after: int = int((session.get("current_view") as Dictionary)["metadata"]["turn"])
	check(turn_after == turn_before + 1, "端到端：结束回合后回合数 +1")
	check(not bool(session.get("end_turn_pending")), "端到端：finishTurn→beginPlayerTurn 序列完成")
	var restored: Dictionary = _find_disciple(session, disciple_id)
	check(int(restored.get("movePoints", -1)) == int(restored.get("maxMovePoints", -2)), "端到端：beginPlayerTurn 恢复弟子移动力")
	check(int(restored.get("attacksRemaining", -1)) == 1, "端到端：beginPlayerTurn 重置出手")
	var turn_label: Label = world.get("topbar_turn_label") as Label
	check(turn_label != null and turn_label.text == "第 %d 回合" % turn_after, "端到端：TopBar 回合文本同步")

	# ④ 相机铁律：全程不重置
	check(camera.global_transform.is_equal_approx(transform_before) and is_equal_approx(camera.size, size_before), "端到端：点选/移动/结束回合全程相机 transform/size 不变")

	world.queue_free()
	world = null
	await get_tree().process_frame
	session.call("shutdown")


func _player_sect(session: Node) -> Dictionary:
	for sect: Dictionary in (session.get("current_view") as Dictionary).get("sects", []):
		if bool(sect.get("player", false)):
			return sect
	return {}


func _find_disciple(session: Node, disciple_id: String) -> Dictionary:
	for sect: Dictionary in (session.get("current_view") as Dictionary).get("sects", []):
		for disciple: Dictionary in sect.get("disciples", []):
			if str(disciple.get("id", "")) == disciple_id:
				return disciple
	return {}


func _unit_positions(world_node: Node3D) -> Dictionary:
	var result: Dictionary = {}
	var units: Node3D = world_node.get_node("UnitView") as Node3D
	for child: Node in units.get_children():
		var model: Node3D = child as Node3D
		if model != null:
			result[str(model.name)] = model.position
	return result


func check(ok: bool, label: String) -> void:
	checks += 1
	if ok:
		print("R2_CLIENT_PASS: " + label)
	else:
		failures += 1
		push_error("R2_CLIENT_FAIL: " + label)


func finish() -> void:
	print("R2_CLIENT_RESULT=%s checks=%d failures=%d" % ["OK" if failures == 0 else "FAIL", checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
