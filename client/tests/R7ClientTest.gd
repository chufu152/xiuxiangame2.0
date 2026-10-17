extends Node
## R7 客户端验收：胜负进度 / 存档往返 / 待抉择弹窗 / 结局屏 / 事件栏的真机端到端。
##
## 无头运行：`godot --headless --path client res://tests/R7ClientTest.tscn [-- --integration]`。
## 不带 `--integration` 时只跑不依赖服务端的表现层断言（四面板已构建、默认隐藏、互斥）。
##
## 覆盖 `docs/prompts/R7_任命渡劫AI胜负存档.md`「自动验收 · 客户端」第 11 条：
## newGame → 打开胜利进度面板 → 存读档往返 → 触发多路线待决 → `awaitInput` 弹窗 →
## `resolveChoice` → 结局屏显示 → 全程相机 transform/size 不变。
##
## **为什么「多路线待决」用注入而非真打出来**：`pendingVictoryChoices` 只能由服务端
## `VICTORY_CHECK` 在「同一回合达成 ≥2 条路线」时写入，而任何协议命令都无法直接置位；
## 客户端验收要在有限时间内跑到那个状态，只能靠 240 回合强制结算或三路线齐备的构造局。
## 故这里把一条**形状完全合规**的 `awaitInput`（PROTOCOL §0.7）注入到 `NetClient.server_message`
## 的下游处理函数（`Session._on_server_message`），走的是与服务端推送**完全相同**的那条链路：
## 主动消息 → `await_input` 信号 → 世界层弹窗 → 按 `options[].index` 发 `resolveChoice`。
## 服务端此刻确实没有待决，故 `resolveChoice` 回 `BAD_PARAMS`——本用例**正是**要断言
## 「越界/无待决时弹窗不消失且给出 ✗ 提示」（裁决七），随后由 `queryGameOver` 收尾。

const TEST_PORT: int = 19580
## 存档往返用槽 4（避开槽 0 自动存档与人工槽 1–3），测完删除。
## 必须落在 `World.SAVE_SLOTS` 内，否则面板不会渲染该槽的按钮（本用例正是按按钮名断言）。
const TEST_SLOT: int = 4

var checks: int = 0
var failures: int = 0
var world: Node3D = null


func _ready() -> void:
	await get_tree().process_frame
	var session: Node = get_node("/root/Session")
	# ① 开局前：R7 四面板已构建但隐藏，且无按钮。
	world = (load("res://scenes/World.tscn") as PackedScene).instantiate() as Node3D
	add_child(world)
	await get_tree().process_frame
	check(world.get("victory_panel") != null, "胜利进度面板已构建（CanvasLayer）")
	check(world.get("saves_panel") != null, "存档面板已构建（CanvasLayer）")
	check(world.get("gameover_panel") != null, "结局屏已构建（CanvasLayer）")
	check(world.get("choice_panel") != null, "待抉择弹窗已构建（CanvasLayer）")
	check(world.get("event_label") != null, "侧栏事件栏已构建")
	check(not bool(world.call("victory_panel_visible")), "未打开时胜利进度面板不显示")
	check(not bool(world.call("saves_panel_visible")), "未打开时存档面板不显示")
	check(not bool(world.call("gameover_panel_visible")), "未打开时结局屏不显示")
	check(not bool(world.call("choice_panel_visible")), "无 awaitInput 时待抉择弹窗不显示")
	check(int(world.call("victory_button_count")) == 0, "胜利进度面板初始无按钮")
	check(int(world.call("saves_button_count")) == 0, "存档面板初始无按钮")
	check(int(world.call("gameover_button_count")) == 0, "结局屏初始无按钮")
	check(int(world.call("choice_button_count")) == 0, "待抉择弹窗初始无按钮")
	check(str(world.call("event_text")) == "（暂无事件）", "事件栏初始为空态文案")
	world.queue_free()
	world = null
	await get_tree().process_frame
	if OS.get_cmdline_user_args().has("--integration"):
		await integration(session)
	if DisplayServer.get_name() != "headless":
		DirAccess.make_dir_recursive_absolute("res://outputs")
		await RenderingServer.frame_post_draw
		check(get_viewport().get_texture().get_image().save_png("res://outputs/R7_live.png") == OK, "R7 GUI 截图保存成功")
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
		"listSaves", "saveGame", "loadGame", "queryVictoryProgress", "checkVictory",
		"checkDefeat", "chooseVictory", "queryGameOver", "tribulate", "appointFengZhu",
		"appointZhangLao", "appointZongZhu", "queryVictoryChoice", "resolveChoice",
	]:
		check(bool(session.call("supports", command)), "端到端：hello 声明支持 " + command)

	var old_revision: int = int(session.get("view_revision"))
	session.call("request_new_game", {"playerFaction": "ZONG_MEN", "sectName": "青岚决天宗", "mapWidth": 24, "mapHeight": 18, "randomSeed": "246813", "difficultyId": "normal"})
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
	var turn_before: int = _turn_of(session)

	# ② 胜利进度面板：三路线 goals 全部来自服务端
	world.call("open_victory_panel")
	await _wait_idle(session, 20000)
	check(bool(world.call("victory_panel_visible")), "端到端：打开胜利进度面板")
	check(int(world.call("victory_route_count")) >= 1, "端到端：queryVictoryProgress 返回路线")
	var victory_info: String = str(world.call("victory_info_text"))
	check(victory_info.contains("进度"), "端到端：胜利面板显示各路线进度百分比")
	check(victory_info.contains("还差") or victory_info.contains("已达成"), "端到端：胜利面板显示 summary 差距文案")
	check(int(world.call("victory_button_count")) >= 3, "端到端：胜利面板渲染 goals 行 + 择定 + 刷新/关闭")
	var choose_state: Dictionary = world.call("r7_button_state", "Choose_ZONG_MEN_DAOTONG")
	check(not choose_state.is_empty(), "端到端：招牌路线「择定」按钮已渲染")
	check(bool(choose_state.get("disabled", false)), "端到端：未达成路线的择定按钮置灰")
	check(not bool(world.call("saves_panel_visible")), "端到端：R7 面板互斥（存档未显示）")
	check(not bool(world.call("gameover_panel_visible")), "端到端：R7 面板互斥（结局未显示）")
	world.call("close_victory_panel")
	check(not bool(world.call("victory_panel_visible")), "端到端：关闭胜利进度面板")

	# ③ 存档往返：saveGame → listSaves → loadGame（回 view 且回合一致）
	world.call("open_saves_panel")
	await _wait_idle(session, 20000)
	check(bool(world.call("saves_panel_visible")), "端到端：打开存档面板")
	check(str(world.call("saves_info_text")).contains("槽 0"), "端到端：存档面板说明槽 0 为自动存档")
	check(not (world.call("r7_button_state", "Save_%d" % TEST_SLOT) as Dictionary).is_empty(), "端到端：槽 %d 存入按钮已渲染" % TEST_SLOT)
	var load_empty: Dictionary = world.call("r7_button_state", "Load_%d" % TEST_SLOT)
	check(not load_empty.is_empty() and bool(load_empty.get("disabled", false)), "端到端：空槽读取按钮置灰")

	session.call("request_save_game", TEST_SLOT)
	await _wait_idle(session, 20000)
	var save_feedback: String = str(world.call("saves_feedback_text"))
	check(save_feedback.begins_with("✓"), "端到端：saveGame 回 {slot,saved} 被判为成功（非 success 布尔）")
	check(save_feedback.contains(str(TEST_SLOT)), "端到端：存档反馈指明槽位")
	var load_state: Dictionary = world.call("r7_button_state", "Load_%d" % TEST_SLOT)
	check(not load_state.is_empty() and not bool(load_state.get("disabled", true)), "端到端：存入后该槽读取按钮可用")
	check(str(load_state.get("text", "")).contains("第 %d 回合" % turn_before), "端到端：读取按钮显示存档回合")
	check(int(world.call("saves_slot_count")) >= 1, "端到端：listSaves 返回至少一个槽")

	var revision_before_load: int = int(session.get("view_revision"))
	session.call("request_load_game", TEST_SLOT)
	await _wait_idle(session, 20000)
	check(int(session.get("view_revision")) > revision_before_load, "端到端：loadGame 返回 view 并重建世界")
	check(str(world.call("saves_feedback_text")).contains("已读取槽 %d" % TEST_SLOT), "端到端：读档反馈指明槽位")
	check(_turn_of(session) == turn_before, "端到端：读档后回合与存档时一致")
	world.call("close_saves_panel")
	check(not bool(world.call("saves_panel_visible")), "端到端：关闭存档面板")

	# ④ 待抉择：注入形状合规的 awaitInput（见文件头「为什么用注入」）
	var payload: Dictionary = {
		"type": "awaitInput",
		"reqId": "req_victory_%d" % turn_before,
		"kind": "victoryChoice",
		"prompt": "同时达成 2 条胜利路线, 请择一而终",
		"options": [
			{"index": 0, "label": "万法归宗", "routeId": "ZONG_MEN_DAOTONG", "description": "以道统压服天下宗门"},
			{"index": 1, "label": "举族登仙", "routeId": "JIA_ZU_ASCENSION", "description": "举族渡劫飞升"},
		],
	}
	session.call("_on_server_message", payload)
	await get_tree().process_frame
	check(bool(world.call("choice_panel_visible")), "端到端：awaitInput 触发待抉择弹窗")
	check(int(world.call("choice_option_count")) == 2, "端到端：弹窗解析 2 个选项")
	check(int(world.call("choice_button_count")) == 3, "端到端：弹窗渲染 2 选项 + 稍后再说")
	check(str(world.call("choice_info_text")).contains("req_victory_"), "端到端：弹窗显示 reqId（resolveChoice 的唯一凭据）")
	var option_state: Dictionary = world.call("r7_button_state", "Choice_0")
	check(not option_state.is_empty() and str(option_state.get("text", "")).contains("万法归宗"), "端到端：选项按钮显示路线显示名")

	_press(world.get("choice_list"), "Choice_0")
	await _wait_idle(session, 20000)
	check(str(world.call("choice_feedback_text")).begins_with("✗"), "端到端：无待决时 resolveChoice 回 BAD_PARAMS 并提示 ✗")
	check(bool(world.call("choice_panel_visible")), "端到端：待决未清空时弹窗保留（裁决七）")
	world.call("close_choice_panel")
	check(not bool(world.call("choice_panel_visible")), "端到端：可手动关闭待抉择弹窗")

	# ⑤ 结束一回合：AI 行动事件进侧栏事件栏
	var revision_before_turn: int = int(session.get("view_revision"))
	session.call("request_end_turn_sequence")
	await _wait_idle(session, 60000)
	check(int(session.get("view_revision")) > revision_before_turn, "端到端：结束回合后 view 刷新")
	check(str(world.call("event_text")).contains("回合"), "端到端：事件栏展示回包 events（AI 行动占位）")

	# ⑥ 结局屏：winType / winnerSectId / 本宗路线 / 覆灭判定
	world.call("open_gameover_panel")
	await _wait_idle(session, 30000)
	check(bool(world.call("gameover_panel_visible")), "端到端：打开结局屏")
	var gameover_info: String = str(world.call("gameover_info_text"))
	check(gameover_info.contains("结局："), "端到端：结局屏显示 winType")
	check(gameover_info.contains("胜者："), "端到端：结局屏显示 winnerSectId")
	check(gameover_info.contains("回合"), "端到端：结局屏显示当前回合")
	check(int(world.call("gameover_button_count")) >= 2, "端到端：结局屏渲染刷新 + 关闭")
	world.call("close_gameover_panel")
	check(not bool(world.call("gameover_panel_visible")), "端到端：关闭结局屏")

	# ⑦ 弟子详情面板的任命/渡劫入口
	var disciple_id: String = ""
	var disciples: Array = player_sect.get("disciples", [])
	if not disciples.is_empty():
		disciple_id = str((disciples[0] as Dictionary).get("id", ""))
	check(not disciple_id.is_empty(), "端到端：玩家有弟子可任命/渡劫")
	if not disciple_id.is_empty():
		world.call("select_disciple", disciple_id)
		await _wait_idle(session, 20000)
		for entry: Array in [
			["AppointFengZhu", "任命峰主"], ["AppointZhangLao", "任命长老"],
			["AppointZongZhu", "任命宗主"], ["Tribulate", "渡劫"],
		]:
			var found: bool = _has_button(world.get("unit_list"), str(entry[0]))
			check(found, "端到端：弟子详情面板含「%s」入口" % str(entry[1]))

	_check_camera(camera, transform_before, size_before)
	_clean_test_slot()
	session.call("shutdown")


## 全程相机 transform/size 不变（R7 相机铁律）。
func _check_camera(camera: Camera3D, transform_before: Transform3D, size_before: float) -> void:
	check(camera.global_transform.is_equal_approx(transform_before), "端到端：全程相机 transform 不变")
	check(is_equal_approx(camera.size, size_before), "端到端：全程相机 size 不变")


## 在指定 VBoxContainer 里按名按下按钮（模拟玩家点击）。
func _press(list: Variant, button_name: String) -> void:
	if list == null:
		return
	var button: Button = (list as Node).get_node_or_null(NodePath(button_name)) as Button
	if button == null:
		return
	button.emit_signal("pressed")


func _has_button(list: Variant, button_name: String) -> bool:
	if list == null:
		return false
	return (list as Node).get_node_or_null(NodePath(button_name)) != null


func _turn_of(session: Node) -> int:
	var view: Dictionary = session.get("current_view") as Dictionary
	var meta: Dictionary = view.get("metadata", {})
	return int(meta.get("turn", view.get("turn", 0)))


func _player_sect(session: Node) -> Dictionary:
	for sect: Dictionary in (session.get("current_view") as Dictionary).get("sects", []):
		if bool(sect.get("player", false)):
			return sect
	return {}


## 删除本用例写的存档槽文件（`server/saves/save_<slot>.json`），避免污染后续运行。
func _clean_test_slot() -> void:
	var client_root: String = ProjectSettings.globalize_path("res://")
	var path: String = client_root.path_join("../server/saves/save_%d.json" % TEST_SLOT).simplify_path()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


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
		print("R7_CLIENT_PASS: " + label)
	else:
		failures += 1
		push_error("R7_CLIENT_FAIL: " + label)


func finish() -> void:
	print("R7_CLIENT_RESULT=%s checks=%d failures=%d" % ["OK" if failures == 0 else "FAIL", checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
