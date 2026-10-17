extends Node
## R4 客户端验收：道统树面板 → 研究道法 → 项目/研究队列 → 加速/取消 → 收徒大典 的真机端到端。
##
## 无头运行：`godot --headless --path client res://tests/R4ClientTest.tscn [-- --integration]`。
## 不带 `--integration` 时只跑不依赖服务端的表现层断言。
##
## 覆盖 `docs/prompts/R4_道统与修炼.md`「自动验收 · 客户端」：
## newGame → 打开道统树（21 条道法、5 个时代、三态 + blocker）→ 研究一条可用道法 →
## `queryProjectQueue` 显示它 → 加速 1 回合成功 → 收徒大典入队 → 取消 → 全程相机 transform/size 不变。
##
## 道点现实（PRD L345 初始资源无道点、L455 道点来源为藏经阁/节点/成就）：
## 开局 0 道点 → 全部道法 BLOCKED。本测试按真实玩法先建藏经阁（+2 道点/回合），
## 跑到道点 ≥ 20 再研究 `tu_na`，不做任何资源作弊。

var checks: int = 0
var failures: int = 0
var world: Node3D = null


func _ready() -> void:
	await get_tree().process_frame
	var session: Node = get_node("/root/Session")
	# ① 开局前：两个 R4 面板已构建但隐藏，且无任何条目/按钮。
	world = (load("res://scenes/World.tscn") as PackedScene).instantiate() as Node3D
	add_child(world)
	await get_tree().process_frame
	check(world.get("dao_panel") != null, "道统树面板已构建（CanvasLayer）")
	check(not bool(world.call("dao_panel_visible")), "未打开时道统树面板不显示")
	check(int(world.call("dao_button_count")) == 0, "未开局时道统树无道法按钮")
	check(int(world.call("dao_option_count")) == 0, "未开局时无 daoOptions 缓存")
	check(world.get("queue_panel") != null, "项目/研究队列面板已构建（CanvasLayer）")
	check(not bool(world.call("queue_panel_visible")), "未打开时队列面板不显示")
	check(int(world.call("queue_build_count")) == 0, "未开局时建造队列为空")
	check(int(world.call("queue_research_count")) == 0, "未开局时研究队列为空")
	world.queue_free()
	world = null
	await get_tree().process_frame
	if OS.get_cmdline_user_args().has("--integration"):
		await integration(session)
	if DisplayServer.get_name() != "headless":
		DirAccess.make_dir_recursive_absolute("res://outputs")
		await RenderingServer.frame_post_draw
		check(get_viewport().get_texture().get_image().save_png("res://outputs/R4_live.png") == OK, "R4 GUI 截图保存成功")
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
		"researchDao", "holdRecruitment", "queryProjectQueue", "cancelProject", "accelerateProject",
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
	var sect_id: String = str(player_sect.get("id", ""))
	var peaks: Array = player_sect.get("spiritPeaks", [])
	check(peaks.size() >= 1, "端到端：玩家开局有灵峰")
	if peaks.is_empty():
		session.call("shutdown")
		return
	var peak: Dictionary = peaks[0]
	var peak_id: String = str(peak["id"])
	check(bool(peak.get("capital", false)), "端到端：首个灵峰为主峰")

	# ② 道统树数据：21 条道法 / 5 个时代 / 每条都有三态与 blocker
	check(int(world.call("dao_option_count")) == 21, "端到端：daoOptions 下发 21 条道法")
	check(_era_count(world) == 5, "端到端：daoOptions 覆盖 5 个时代")
	check(_all_states_valid(world), "端到端：每条道法 state ∈ {UNLOCKED, RESEARCHING, AVAILABLE, BLOCKED}")
	check(_all_have_blocker_key(world), "端到端：每条道法都下发 blocker 字段")
	check(str(world.call("dao_state_of", "tu_na")) == "BLOCKED", "端到端：开局 0 道点，tu_na 为 BLOCKED")
	check(str(world.call("dao_blocker_of", "tu_na")).contains("道点"), "端到端：tu_na blocker 文案指明道点不足")
	check(_available_count(world) == 0, "端到端：开局无任何 AVAILABLE 道法（初始道点 0，PRD L345）")

	# ③ 打开道统树：5 个时代分列 + 21 个道法按钮，阻塞者置灰
	world.call("open_dao_panel")
	await get_tree().process_frame
	check(bool(world.call("dao_panel_visible")), "端到端：道统树面板打开")
	check(int(world.call("dao_button_count")) == 26, "端到端：道统树含 21 道法 + 5 时代标题共 26 个节点")
	var tu_na: Button = world.call("dao_button", "tu_na") as Button
	check(tu_na != null, "端到端：道统树含 tu_na 按钮")
	if tu_na != null:
		check(tu_na.disabled, "端到端：BLOCKED 的 tu_na 按钮置灰不可点")
		check(tu_na.text.contains("道点"), "端到端：tu_na 按钮显示道点/工力/回合代价")
		check(tu_na.tooltip_text.contains("阻塞"), "端到端：tu_na tooltip 显示 blocker 文案")
	check(str((world.get("dao_title_label") as Label).text).contains("已解锁 0 / 21"), "端到端：道统树标题显示已解锁 0/21")

	# ④ researchDao 业务失败路径：道点不足 → 面板 ✗ 提示（协议 ok=true + success=false）
	await _wait_idle(session, 15000)
	var revision_before: int = int(session.get("view_revision"))
	session.call("request_research_dao", sect_id, "tu_na")
	await _wait_idle(session, 15000)
	var dao_status: String = str((world.get("dao_status_label") as Label).text)
	check(dao_status.begins_with("✗"), "端到端：道点不足时 researchDao 返回业务失败并提示 ✗")
	check(dao_status.contains("道点"), "端到端：失败提示含「道点」")
	check(int(session.get("view_revision")) == revision_before, "端到端：researchDao 业务失败不刷新 view")

	# ⑤ queryProjectQueue：两列不混池，初始两列皆空
	world.call("open_queue_panel")
	deadline = Time.get_ticks_msec() + 15000
	while (world.get("project_queue") as Dictionary).is_empty() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check(bool(world.call("queue_panel_visible")), "端到端：队列面板打开")
	check(not (world.get("project_queue") as Dictionary).is_empty(), "端到端：queryProjectQueue 回包到达")
	check(bool((world.get("project_queue") as Dictionary).get("found", false)), "端到端：queryProjectQueue.found=true")
	check(int(world.call("queue_build_count")) == 0, "端到端：初始建造队列 projects[] 为空")
	check(int(world.call("queue_research_count")) == 0, "端到端：初始研究队列 researchQueue[] 为空")
	check(str((world.get("queue_title_label") as Label).text).contains(str(peak.get("name", ""))), "端到端：队列标题显示灵峰名")

	# ⑥ 工力 120 < recruitmentCost 200 → 收徒大典业务失败
	await _wait_idle(session, 15000)
	session.call("request_hold_recruitment", peak_id)
	await _wait_idle(session, 15000)
	var queue_status: String = str(world.call("queue_status_text"))
	check(queue_status.begins_with("✗") and queue_status.contains("工力"), "端到端：工力不足时 holdRecruitment 业务失败")

	# ⑦ 建藏经阁（道点唯一前期来源，PRD L455）→ 跑到道点 ≥ 20
	await _wait_idle(session, 15000)
	var power_before: int = _resource(session, "spiritPower")
	session.call("request_construct_building", peak_id, "CANG_JING_GE")
	await _wait_idle(session, 15000)
	check(_resource(session, "spiritPower") == power_before - 250, "端到端：constructBuilding 扣 building.costs.CANG_JING_GE=250 灵力")
	# 建造项目应只出现在 projects[] 列，researchQueue[] 列仍空（两池不混，反向验证）
	world.call("open_queue_panel")
	deadline = Time.get_ticks_msec() + 15000
	while int(world.call("queue_build_count")) == 0 and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check(int(world.call("queue_build_count")) == 1, "端到端：建造项目入 projects[] 列")
	check(int(world.call("queue_research_count")) == 0, "端到端：建造项目**不**混入 researchQueue[] 列")
	var dao_points: int = 0
	var turns_played: int = 0
	deadline = Time.get_ticks_msec() + 120000
	while dao_points < 20 and turns_played < 20 and Time.get_ticks_msec() < deadline:
		await _wait_idle(session, 15000)
		session.call("request_end_turn_sequence")
		await _wait_idle(session, 15000)
		turns_played += 1
		dao_points = _resource(session, "daoPoints")
	check(dao_points >= 20, "端到端：藏经阁 +2 道点/回合，%d 回合后道点达 %d（≥20）" % [turns_played, dao_points])
	check(str(world.call("dao_state_of", "tu_na")) == "AVAILABLE", "端到端：道点充足后 tu_na 变为 AVAILABLE")

	# ⑧ 点道统树的 tu_na → researchDao 成功 → 研究队列出现该道法
	world.call("open_dao_panel")
	await get_tree().process_frame
	tu_na = world.call("dao_button", "tu_na") as Button
	check(tu_na != null and not tu_na.disabled, "端到端：AVAILABLE 的 tu_na 按钮可点")
	if tu_na == null:
		session.call("shutdown")
		return
	var points_before: int = _resource(session, "daoPoints")
	tu_na.emit_signal("pressed")
	await _wait_idle(session, 15000)
	check(_resource(session, "daoPoints") == points_before - 20, "端到端：researchDao 入队即扣 daoPointCost=20 道点")
	check(str(world.call("dao_state_of", "tu_na")) == "RESEARCHING", "端到端：研究入队后 tu_na 变为 RESEARCHING")

	world.call("open_queue_panel")
	deadline = Time.get_ticks_msec() + 15000
	while int(world.call("queue_research_count")) == 0 and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check(int(world.call("queue_research_count")) == 1, "端到端：researchQueue[] 出现 1 条研究项目")
	check(int(world.call("queue_build_count")) == 0, "端到端：研究项目**不**混入 projects[]（两池分离）")
	var research_rows: Array = (world.get("project_queue") as Dictionary).get("researchQueue", [])
	check(research_rows.size() == 1, "端到端：project_queue.researchQueue 含 1 条")
	if research_rows.size() != 1:
		session.call("shutdown")
		return
	var project: Dictionary = research_rows[0]
	var project_id: String = str(project.get("id", ""))
	var turns_required: int = int(project.get("turnsRequired", 0))
	var turns_left: int = int(project.get("turnsRemaining", 0))
	check(turns_required >= 1 and turns_left == turns_required, "端到端：研究项目初始 turnsRemaining == turnsRequired")

	# ⑨ 加速 1 回合：扣 accelerateStonePerTurn=120 灵石，剩余回合 −1（或即刻完成）
	var stones_before: int = _resource(session, "spiritStones")
	session.call("request_accelerate_project", peak_id, project_id, 1, true)
	await _wait_idle(session, 15000)
	check(_resource(session, "spiritStones") == stones_before - 120, "端到端：accelerateProject 扣 accelerateStonePerTurn×1=120 灵石")
	var accelerated_ok: bool = str(world.call("dao_state_of", "tu_na")) == "UNLOCKED"
	if not accelerated_ok:
		await _wait_idle(session, 15000)
		world.call("open_queue_panel")
		deadline = Time.get_ticks_msec() + 15000
		while (world.get("project_queue") as Dictionary).is_empty() and Time.get_ticks_msec() < deadline:
			await get_tree().process_frame
		var after_rows: Array = (world.get("project_queue") as Dictionary).get("researchQueue", [])
		accelerated_ok = after_rows.is_empty()
		if not accelerated_ok:
			accelerated_ok = int((after_rows[0] as Dictionary).get("turnsRemaining", 99)) == turns_left - 1
	check(accelerated_ok, "端到端：加速 1 回合后 turnsRemaining 递减（或研究即刻完成解锁）")

	# ⑩ 收徒大典：工力已够 → 入 projects[]（不混入 researchQueue[]）
	await _wait_idle(session, 15000)
	world.call("open_queue_panel")
	await _wait_idle(session, 15000)
	var work_power: int = _resource(session, "workPower")
	check(work_power >= 200, "端到端：%d 回合后工力 %d ≥ recruitmentCost 200" % [turns_played, work_power])
	session.call("request_hold_recruitment", peak_id)
	await _wait_idle(session, 15000)
	world.call("open_queue_panel")
	deadline = Time.get_ticks_msec() + 15000
	while int(world.call("queue_build_count")) == 0 and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check(int(world.call("queue_build_count")) == 1, "端到端：holdRecruitment 后 projects[] 出现 1 条收徒项目")
	check(str(world.call("queue_status_text")).begins_with("✓"), "端到端：队列面板状态显示 ✓ 成功")
	var build_rows: Array = (world.get("project_queue") as Dictionary).get("projects", [])
	check(build_rows.size() == 1, "端到端：project_queue.projects 含 1 条")
	if build_rows.size() != 1:
		session.call("shutdown")
		return
	var build_id: String = str((build_rows[0] as Dictionary).get("id", ""))

	# ⑪ 取消项目：projects[] 清空
	session.call("request_cancel_project", peak_id, build_id)
	await _wait_idle(session, 15000)
	world.call("open_queue_panel")
	deadline = Time.get_ticks_msec() + 15000
	while int(world.call("queue_build_count")) != 0 and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check(int(world.call("queue_build_count")) == 0, "端到端：cancelProject 后 projects[] 清空")

	# ⑫ 弟子详情面板（侧栏）含 R4 字段
	var disciples: Array = _player_sect(session).get("disciples", [])
	check(disciples.size() >= 1, "端到端：玩家有弟子")
	if disciples.size() >= 1:
		var detail: String = str(world.call("disciple_detail_text", str((disciples[0] as Dictionary).get("id", ""))))
		check(detail.contains("修为进度"), "端到端：弟子详情显示 cultivationProgress")
		check(detail.contains("心魔"), "端到端：弟子详情显示 heartDevil")
		check(detail.contains("伤势"), "端到端：弟子详情显示 injured")
		check(detail.contains("入门"), "端到端：弟子详情显示 turnsInSect")
		check(detail.contains("灵根品阶"), "端到端：弟子详情显示 rootGrade")

	# ⑬ 资源栏含道点（R3 已加，R4 复核）
	check(str((world.get("topbar_resource_label") as Label).text).contains("道点"), "端到端：资源栏含道点 daoPoints")

	# ⑭ 相机铁律：全程不重置
	check(camera.global_transform.is_equal_approx(transform_before) and is_equal_approx(camera.size, size_before), "端到端：开面板/研究/加速/收徒/取消全程相机 transform/size 不变")

	world.queue_free()
	world = null
	await get_tree().process_frame
	session.call("shutdown")


# ---------------------------------------------------------------------------
# 断言辅助
# ---------------------------------------------------------------------------

func _player_sect(session: Node) -> Dictionary:
	for sect: Dictionary in (session.get("current_view") as Dictionary).get("sects", []):
		if bool(sect.get("player", false)):
			return sect
	return {}


func _resource(session: Node, key: String) -> int:
	var sect: Dictionary = _player_sect(session)
	return int((sect.get("resources", {}) as Dictionary).get(key, 0))


func _era_count(world_node: Node3D) -> int:
	var eras: Array[int] = []
	for entry: Dictionary in world_node.get("dao_options") as Array:
		var era_index: int = int(entry.get("eraIndex", -1))
		if not eras.has(era_index):
			eras.append(era_index)
	return eras.size()


func _all_states_valid(world_node: Node3D) -> bool:
	for entry: Dictionary in world_node.get("dao_options") as Array:
		if not (str(entry.get("state", "")) in ["UNLOCKED", "RESEARCHING", "AVAILABLE", "BLOCKED"]):
			return false
	return true


func _all_have_blocker_key(world_node: Node3D) -> bool:
	for entry: Dictionary in world_node.get("dao_options") as Array:
		if not entry.has("blocker"):
			return false
	return true


func _available_count(world_node: Node3D) -> int:
	var count: int = 0
	for entry: Dictionary in world_node.get("dao_options") as Array:
		if str(entry.get("state", "")) == "AVAILABLE":
			count += 1
	return count


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


func check(ok: bool, label: String) -> void:
	checks += 1
	if ok:
		print("R4_CLIENT_PASS: " + label)
	else:
		failures += 1
		push_error("R4_CLIENT_FAIL: " + label)


func finish() -> void:
	print("R4_CLIENT_RESULT=%s checks=%d failures=%d" % ["OK" if failures == 0 else "FAIL", checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
