extends Node
## R3 客户端验收：选中己方灵峰 → 城市面板 → 建造 → 指派劳力 的真机端到端。
##
## 无头运行：`godot --headless --path client res://tests/R3ClientTest.tscn [-- --integration]`。
## 不带 `--integration` 时只跑不依赖服务端的表现层断言。
##
## 覆盖 `docs/prompts/R3_经济与城市.md`「自动验收 · 客户端」第 9 条：
## newGame → 选中己方主峰 → `queryCityDetail` 面板显示人口/住房/安定 → `queryBuildOptions`
## 列可建建筑 → 点建山门（`constructBuilding`）成功且 view 更新 → 指派劳力 →
## 全程相机 transform/size 不变（`R3_CLIENT_PASS:` 前缀）。

var checks: int = 0
var failures: int = 0
var world: Node3D = null


func _ready() -> void:
	await get_tree().process_frame
	var session: Node = get_node("/root/Session")
	# hello 前：城市面板已构建但未选中灵峰 → 不显示详情，也不出现任何按钮。
	world = (load("res://scenes/World.tscn") as PackedScene).instantiate() as Node3D
	add_child(world)
	await get_tree().process_frame
	check(world.get("city_panel") != null, "城市面板已构建（CanvasLayer）")
	check(not bool(world.call("city_panel_visible")), "未选中灵峰时城市面板不显示")
	check(str(world.call("city_info_text")).contains("点击己方灵峰"), "未选中时面板提示点击己方灵峰")
	check(int(world.call("city_button_count")) == 0, "未选中时无建造/区域/劳力按钮")
	check(int(world.call("city_candidate_count")) == 0, "未选中时无候选格")
	world.queue_free()
	world = null
	await get_tree().process_frame
	if OS.get_cmdline_user_args().has("--integration"):
		await integration(session)
	if DisplayServer.get_name() != "headless":
		DirAccess.make_dir_recursive_absolute("res://outputs")
		await RenderingServer.frame_post_draw
		check(get_viewport().get_texture().get_image().save_png("res://outputs/R3_live.png") == OK, "R3 GUI 截图保存成功")
	finish()


func integration(session: Node) -> void:
	session.call("start_connection", 19539)
	var deadline: int = Time.get_ticks_msec() + 45000
	while not bool(session.call("supports", "newGame")) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check(bool(session.call("supports", "newGame")), "端到端：收到 newGame hello")
	if not bool(session.call("supports", "newGame")):
		session.call("shutdown")
		return
	for command: String in [
		"foundSpiritPeak", "appointBuilder", "constructBuilding", "queryBuildOptions",
		"openCave", "fortifyPeak", "foundDistrict", "queryDistrictSites",
		"assignWorker", "unassignWorker", "queryAssignableTiles", "queryCityDetail",
		"buildImprovement", "repairImprovement", "queryImprovementOptions",
	]:
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
	var peaks: Array = player_sect.get("spiritPeaks", [])
	check(peaks.size() >= 1, "端到端：玩家开局有灵峰")
	if peaks.is_empty():
		session.call("shutdown")
		return
	var peak: Dictionary = peaks[0]
	var peak_id: String = str(peak["id"])
	check(bool(peak.get("capital", false)), "端到端：首个灵峰为主峰")
	var power_before: int = int((player_sect.get("resources", {}) as Dictionary).get("spiritPower", -1))

	# ① 选中己方主峰 → queryCityDetail 面板显示人口/住房/安定
	world.call("select_peak", peak_id)
	deadline = Time.get_ticks_msec() + 15000
	while not str(world.call("city_info_text")).contains("人口") and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check(bool(world.call("city_panel_visible")), "端到端：选中灵峰后城市面板显示")
	var info: String = str(world.call("city_info_text"))
	check(info.contains("人口"), "端到端：queryCityDetail 面板显示人口")
	check(info.contains("住房"), "端到端：queryCityDetail 面板显示住房")
	check(info.contains("安定"), "端到端：queryCityDetail 面板显示安定")
	check(info.contains("气运"), "端到端：queryCityDetail 面板显示气运/产出倍率")

	# ② queryBuildOptions 列可建建筑（出现「山门」按钮）
	var shan_men: Button = null
	deadline = Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		shan_men = _find_button(world, "山门")
		if shan_men != null:
			break
	check(shan_men != null, "端到端：queryBuildOptions 列出可建建筑（含山门）")
	check(int(world.call("city_button_count")) > 0, "端到端：城市面板按钮数 > 0")
	check(str((world.get("topbar_resource_label") as Label).text).contains("粮"), "端到端：资源栏追加「粮」")
	check(str((world.get("topbar_resource_label") as Label).text).contains("灵木"), "端到端：资源栏追加材料「灵木」")
	if shan_men == null:
		session.call("shutdown")
		return

	# ③ 点建「山门」→ constructBuilding 成功、扣 200 灵力、view 更新
	check(not shan_men.disabled, "端到端：山门可建（按钮可用）")
	var revision_before: int = int(session.get("view_revision"))
	shan_men.emit_signal("pressed")
	deadline = Time.get_ticks_msec() + 15000
	while (int(session.get("view_revision")) == revision_before or bool(session.get("busy"))) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check(int(session.get("view_revision")) > revision_before, "端到端：constructBuilding 成功并刷新 view")
	var power_after: int = int((_player_sect(session).get("resources", {}) as Dictionary).get("spiritPower", -2))
	check(power_after == power_before - 200, "端到端：constructBuilding 扣 building.costs.SHAN_MEN=200 灵力")
	check(str((world.get("city_status_label") as Label).text).begins_with("✓"), "端到端：城市面板状态显示建造成功")

	# ④ 指派劳力：queryAssignableTiles → 点候选格 → assignWorker 成功
	await _wait_idle(session, 20000)
	session.call("request_query_assignable_tiles", peak_id)
	deadline = Time.get_ticks_msec() + 15000
	while int(world.call("city_candidate_count")) == 0 and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check(int(world.call("city_candidate_count")) > 0, "端到端：queryAssignableTiles 返回候选格")
	var candidates: Array = world.get("city_candidate_ids")
	if candidates.is_empty():
		session.call("shutdown")
		return
	var candidate: String = str(candidates[0])
	var free_before: int = int(_peak_in_view(session, peak_id).get("freeWorkers", -1))
	world.call("on_tile_clicked", candidate)
	var assigned: bool = false
	deadline = Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		if (_peak_in_view(session, peak_id).get("workedTileIds", []) as Array).has(candidate):
			assigned = true
			break
	check(assigned, "端到端：assignWorker 成功，workedTileIds 含候选格")
	var free_after: int = int(_peak_in_view(session, peak_id).get("freeWorkers", -2))
	check(free_after == free_before - 1, "端到端：assignWorker 后 freeWorkers 递减")

	# ⑤ 撤下劳力复原
	await _wait_idle(session, 20000)
	session.call("request_unassign_worker", peak_id, candidate)
	var restored: bool = false
	deadline = Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		if not (_peak_in_view(session, peak_id).get("workedTileIds", []) as Array).has(candidate):
			restored = true
			break
	check(restored, "端到端：unassignWorker 复原，workedTileIds 不含该格")

	# ⑥ 相机铁律：全程不重置
	check(camera.global_transform.is_equal_approx(transform_before) and is_equal_approx(camera.size, size_before), "端到端：选中灵峰/建造/指派劳力全程相机 transform/size 不变")

	world.queue_free()
	world = null
	await get_tree().process_frame
	session.call("shutdown")


## 等会话彻底空闲（连续 5 帧 busy=false），避开写命令成功后自动重查的中间态。
func _wait_idle(session: Node, timeout_ms: int) -> bool:
	var deadline: int = Time.get_ticks_msec() + timeout_ms
	var stable: int = 0
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		if bool(session.get("busy")):
			stable = 0
			continue
		stable += 1
		if stable >= 5:
			return true
	return false


func _player_sect(session: Node) -> Dictionary:
	for sect: Dictionary in (session.get("current_view") as Dictionary).get("sects", []):
		if bool(sect.get("player", false)):
			return sect
	return {}


func _peak_in_view(session: Node, peak_id: String) -> Dictionary:
	for sect: Dictionary in (session.get("current_view") as Dictionary).get("sects", []):
		for peak: Dictionary in sect.get("spiritPeaks", []):
			if str(peak.get("id", "")) == peak_id:
				return peak
	return {}


## 在城市面板按钮列表里按文本前缀找按钮（建造按钮文本形如「山门（灵200 · 3回合）」）。
func _find_button(world_node: Node3D, prefix: String) -> Button:
	var list: Node = world_node.get("city_list") as Node
	if list == null:
		return null
	for child: Node in list.get_children():
		var button: Button = child as Button
		if button != null and button.text.begins_with(prefix):
			return button
	return null


func check(ok: bool, label: String) -> void:
	checks += 1
	if ok:
		print("R3_CLIENT_PASS: " + label)
	else:
		failures += 1
		push_error("R3_CLIENT_FAIL: " + label)


func finish() -> void:
	print("R3_CLIENT_RESULT=%s checks=%d failures=%d" % ["OK" if failures == 0 else "FAIL", checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
