extends Node
## R6 客户端验收：探索 / 政令 / 自动化三面板的真机端到端。
##
## 无头运行：`godot --headless --path client res://tests/R6ClientTest.tscn [-- --integration]`。
## 不带 `--integration` 时只跑不依赖服务端的表现层断言（三面板已构建、默认隐藏、互斥）。
##
## 覆盖 `docs/prompts/R6_探索政令自动化.md`「自动验收 · 客户端」：
## newGame → 点节点格打开探索面板（显示冷却/奖励预览）→ 派弟子探索 → 打开政令面板 →
## 切换政体/颁一张卡 → 打开自动化面板 → 开「自动修缮」→ 本地设置 → 全程相机 transform/size 不变。
##
## 为什么不断言「探索成功」：机缘成败与弟子是否在节点格由地图随机布局决定，
## 客户端只负责「发命令 + 展示回包」，故这里断言**回包到达且面板有反馈**，
## 成功率/奖励/伤亡的正确性由服务端 `R6Test` 覆盖。

const TEST_PORT: int = 19560

var checks: int = 0
var failures: int = 0
var world: Node3D = null


func _ready() -> void:
	await get_tree().process_frame
	var session: Node = get_node("/root/Session")
	# ① 开局前：三个 R6 面板已构建但隐藏，且无按钮。
	world = (load("res://scenes/World.tscn") as PackedScene).instantiate() as Node3D
	add_child(world)
	await get_tree().process_frame
	check(world.get("explore_panel") != null, "探索面板已构建（CanvasLayer）")
	check(world.get("policy_panel") != null, "政令面板已构建（CanvasLayer）")
	check(world.get("automation_panel") != null, "自动化面板已构建（CanvasLayer）")
	check(not bool(world.call("explore_panel_visible")), "未选节点时探索面板不显示")
	check(not bool(world.call("policy_panel_visible")), "未打开时政令面板不显示")
	check(not bool(world.call("automation_panel_visible")), "未打开时自动化面板不显示")
	check(int(world.call("explore_button_count")) == 0, "探索面板初始无按钮")
	check(int(world.call("policy_button_count")) == 0, "政令面板初始无按钮")
	check(int(world.call("automation_button_count")) == 0, "自动化面板初始无按钮")
	world.queue_free()
	world = null
	await get_tree().process_frame
	if OS.get_cmdline_user_args().has("--integration"):
		await integration(session)
	if DisplayServer.get_name() != "headless":
		DirAccess.make_dir_recursive_absolute("res://outputs")
		await RenderingServer.frame_post_draw
		check(get_viewport().get_texture().get_image().save_png("res://outputs/R6_live.png") == OK, "R6 GUI 截图保存成功")
	finish()


func integration(session: Node) -> void:
	session.call("start_connection", TEST_PORT)
	var deadline: int = Time.get_ticks_msec() + 45000
	while not bool(session.call("supports", "newGame")) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check(bool(session.call("supports", "newGame")), "端到端：收到 newGame hello")
	if not bool(session.call("supports", "newGame")):
		session.call("shutdown")
		return
	for command: String in [
		"rally", "returnToDefense", "queryJiYuanInfo", "sendToJiYuan", "queryMiJingInfo",
		"exploreMiJing", "switchGovernment", "enactPolicy", "revokePolicy", "queryPolicyOptions",
		"setAutomationToggle", "setPeakAutoProject", "setAllAutoProject", "exploreNow",
		"queryAutomationState", "setSetting",
	]:
		check(bool(session.call("supports", command)), "端到端：hello 声明支持 " + command)

	var old_revision: int = int(session.get("view_revision"))
	session.call("request_new_game", {"playerFaction": "ZONG_MEN", "sectName": "青岚探政宗", "mapWidth": 24, "mapHeight": 18, "randomSeed": "246811", "difficultyId": "normal"})
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
	var sect_id: String = str(player_sect.get("id", ""))

	# ② 点节点格 → 探索面板
	var node: Dictionary = _first_explore_node(session)
	check(not node.is_empty(), "端到端：地图上存在机缘或秘境节点（随机布局）")
	if node.is_empty():
		_check_camera(camera, transform_before, size_before)
		session.call("shutdown")
		return
	var node_id: String = str(node.get("id", ""))
	var node_tile: String = str(node.get("tileId", ""))
	world.call("on_tile_clicked", node_tile)
	await _wait_idle(session, 20000)
	check(bool(world.call("explore_panel_visible")), "端到端：点节点格打开探索面板")
	check(not bool(world.call("policy_panel_visible")), "端到端：三面板互斥（政令未显示）")
	check(not bool(world.call("automation_panel_visible")), "端到端：三面板互斥（自动化未显示）")
	var explore_info: String = str(world.call("explore_info_text"))
	check(explore_info.contains("冷却"), "端到端：探索面板显示节点冷却")
	check(explore_info.contains("奖励预览"), "端到端：探索面板显示奖励预览")
	check(int(world.call("explore_button_count")) >= 2, "端到端：探索面板列出弟子按钮 + 关闭")
	# 派弟子探索（单人机缘 / 多人秘境各走一条命令）
	var disciples: Array = player_sect.get("disciples", [])
	check(disciples.size() >= 1, "端到端：玩家有弟子可派")
	var node_type: String = str(node.get("type", ""))
	if node_type == "MI_JING":
		var ids: Array[String] = []
		for entry: Dictionary in disciples:
			ids.append(str(entry.get("id", "")))
			if ids.size() >= 2:
				break
		session.call("request_explore_mi_jing", ids, node_id)
	else:
		session.call("request_send_to_ji_yuan", str((disciples[0] as Dictionary).get("id", "")), node_id)
	await _wait_idle(session, 20000)
	check(not str(world.call("explore_feedback_text")).is_empty(), "端到端：探索回包落到面板反馈")
	world.call("close_explore_panel")
	check(not bool(world.call("explore_panel_visible")), "端到端：关闭探索面板")

	# ③ 政令面板：政体列表 + 8 张卡 + 颁一张卡
	world.call("open_policy_panel")
	await _wait_idle(session, 20000)
	check(bool(world.call("policy_panel_visible")), "端到端：打开政令面板")
	var policy_info: String = str(world.call("policy_info_text"))
	check(policy_info.contains("政体"), "端到端：政令面板显示当前政体")
	check(policy_info.contains("效果合计"), "端到端：政令面板显示效果合计")
	check(int(world.call("policy_button_count")) >= 3 + 8 + 1, "端到端：政令面板渲染 3 政体 + 8 卡 + 关闭")
	var gov_state: Dictionary = world.call("r6_button_state", "Gov_zong_fa")
	check(not gov_state.is_empty(), "端到端：当前政体按钮已渲染")
	check(bool(gov_state.get("disabled", false)), "端到端：当前政体按钮禁用")
	session.call("request_enact_policy", sect_id, "ling_tian_zhi")
	await _wait_idle(session, 20000)
	check(not str(world.call("policy_feedback_text")).is_empty(), "端到端：颁行回包落到面板反馈")
	var card_state: Dictionary = world.call("r6_button_state", "Card_ling_tian_zhi")
	check(not card_state.is_empty(), "端到端：灵田制按钮已渲染")
	check(str(card_state.get("text", "")).begins_with("✕"), "端到端：已颁卡按钮变为可废除态（✕）")
	session.call("request_switch_government", sect_id, "zong_fa")
	await _wait_idle(session, 20000)
	check(str(world.call("policy_feedback_text")).contains("政体") or str(world.call("policy_feedback_text")).contains("✗"), "端到端：切换政体回包有反馈")
	world.call("close_policy_panel")

	# ④ 自动化面板：开关 + 立即探索 + 集结/回防 + 本地设置
	world.call("open_automation_panel")
	await _wait_idle(session, 20000)
	check(bool(world.call("automation_panel_visible")), "端到端：打开自动化面板")
	check(str(world.call("automation_info_text")).contains("自动改良"), "端到端：自动化面板显示开关摘要")
	check(int(world.call("automation_button_count")) >= 4 + 1, "端到端：自动化面板渲染 4 个开关 + 其他按钮")
	var repair_state: Dictionary = world.call("r6_button_state", "Toggle_repair")
	check(not repair_state.is_empty(), "端到端：自动修缮开关按钮已渲染")
	session.call("request_set_automation_toggle", sect_id, "repair", false)
	await _wait_idle(session, 20000)
	check(not str(world.call("automation_feedback_text")).is_empty(), "端到端：自动化开关回包落到面板反馈")
	check(str((world.call("r6_button_state", "Toggle_repair") as Dictionary).get("text", "")).begins_with("☐"), "端到端：关闭自动修缮后按钮变 ☐")
	session.call("request_explore_now", sect_id)
	await _wait_idle(session, 20000)
	check(not str(world.call("automation_feedback_text")).is_empty(), "端到端：立即探索回包落到面板反馈")
	session.call("request_rally", sect_id)
	await _wait_idle(session, 20000)
	check(not str(world.call("automation_feedback_text")).is_empty(), "端到端：集结回包落到面板反馈")
	world.call("_toggle_local_setting", "fastSettlement")
	await _wait_idle(session, 20000)
	check(bool(world.call("settings_value", "fastSettlement")), "端到端：本地设置在前端生效")
	world.call("close_automation_panel")

	_check_camera(camera, transform_before, size_before)
	session.call("shutdown")


## 全程相机 transform/size 不变（R6 相机铁律）。
func _check_camera(camera: Camera3D, transform_before: Transform3D, size_before: float) -> void:
	check(camera.global_transform.is_equal_approx(transform_before), "端到端：全程相机 transform 不变")
	check(is_equal_approx(camera.size, size_before), "端到端：全程相机 size 不变")


## 在 view 里找第一个机缘（优先）或秘境节点。
func _first_explore_node(session: Node) -> Dictionary:
	var nodes: Dictionary = (session.get("current_view") as Dictionary).get("nodes", {})
	var fallback: Dictionary = {}
	for node_id: String in nodes:
		var node: Dictionary = nodes[node_id]
		var node_type: String = str(node.get("type", ""))
		if node_type == "JI_YUAN":
			return node
		if node_type == "MI_JING" and fallback.is_empty():
			fallback = node
	return fallback


func _player_sect(session: Node) -> Dictionary:
	for sect: Dictionary in (session.get("current_view") as Dictionary).get("sects", []):
		if bool(sect.get("player", false)):
			return sect
	return {}


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


func check(ok: bool, label: String) -> void:
	checks += 1
	if ok:
		print("R6_CLIENT_PASS: " + label)
	else:
		failures += 1
		push_error("R6_CLIENT_FAIL: " + label)


func finish() -> void:
	print("R6_CLIENT_RESULT=%s checks=%d failures=%d" % ["OK" if failures == 0 else "FAIL", checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
