extends Node
## R5 客户端验收：战斗预览 → 战斗结算反馈 → 转职/晋升 → 传送/驻守/撤退 → 多选批量移动 的真机端到端。
##
## 无头运行：`godot --headless --path client res://tests/R5ClientTest.tscn [-- --integration]`。
## 不带 `--integration` 时只跑不依赖服务端的表现层断言（面板构建 + 十兵种占位剪影）。
##
## 覆盖 `docs/prompts/R5_兵种与战斗.md`「自动验收 · 客户端」：
## newGame → 点选外门弟子（可达集 → 可攻击集 → 弟子详情 三段串行链）→ 十兵种转职候选三态 →
## 攻击预览（不可攻击时给出 blockedReason）→ attack 业务失败提示 → reclass/promote 业务失败提示 →
## retreat 相邻校验 → 传送未开启提示 → 驻守非法节点提示 → Shift 多选 → batchMove 两人同格 →
## 两层高亮互相独立 → 全程相机 transform/size 不变。
##
## 为什么首回合打不起来：`attack_blocker` 要求目标在射程内，开局无敌人在 1 格内，
## 故本测试**不硬凑战斗**，而是把「不可攻击的 blockedReason / 业务失败提示 / 结算面板渲染」
## 这些客户端真正负责的部分逐条验到位；战斗数值与结算正确性由服务端 `R5Test` 覆盖。

const TEST_PORT: int = 19540

var checks: int = 0
var failures: int = 0
var world: Node3D = null


func _ready() -> void:
	await get_tree().process_frame
	var session: Node = get_node("/root/Session")
	# ① 开局前：两个 R5 面板已构建但隐藏，且无高亮/无按钮。
	world = (load("res://scenes/World.tscn") as PackedScene).instantiate() as Node3D
	add_child(world)
	await get_tree().process_frame
	check(world.get("combat_panel") != null, "战斗面板已构建（CanvasLayer）")
	check(not bool(world.call("combat_panel_visible")), "未选中弟子时战斗面板不显示")
	check(int(world.call("combat_button_count")) == 0, "未选中弟子时战斗面板无按钮")
	check(world.get("unit_panel") != null, "弟子详情面板已构建（CanvasLayer）")
	check(not bool(world.call("unit_panel_visible")), "未选中弟子时弟子详情面板不显示")
	check(int(world.call("attack_highlight_count")) == 0, "未选中弟子时攻击高亮层为空")
	check(_placeholder_shapes_distinct(), "十兵种占位剪影两两不同（正式模型缺失时可区分）")
	world.queue_free()
	world = null
	await get_tree().process_frame
	if OS.get_cmdline_user_args().has("--integration"):
		await integration(session)
	if DisplayServer.get_name() != "headless":
		DirAccess.make_dir_recursive_absolute("res://outputs")
		await RenderingServer.frame_post_draw
		check(get_viewport().get_texture().get_image().save_png("res://outputs/R5_live.png") == OK, "R5 GUI 截图保存成功")
	finish()


## 十兵种占位剪影互不相同：按 (网格类型, 包围盒尺寸) 去重后应恰好 10 种。
func _placeholder_shapes_distinct() -> bool:
	check(UnitView.PLACEHOLDER_SHAPES.size() == Enums.UnitClass.ALL.size(), "占位剪影表覆盖全部 10 个兵种")
	var probe: MeshInstance3D = MeshInstance3D.new()
	add_child(probe)
	var seen: Dictionary = {}
	for unit_class: String in Enums.UnitClass.ALL:
		UnitView._apply_class_silhouette(probe, unit_class)
		var key: String = "%s|%s" % [probe.mesh.get_class(), str(probe.mesh.get_aabb().size)]
		seen[key] = unit_class
	probe.queue_free()
	return seen.size() == Enums.UnitClass.ALL.size()


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
		"batchMove", "attack", "queryAttackPreview", "queryAttackable", "retreat", "teleport",
		"queryTeleportOptions", "assignGarrison", "withdrawGarrison", "reclass", "promote",
		"queryDiscipleDetail",
	]:
		check(bool(session.call("supports", command)), "端到端：hello 声明支持 " + command)

	var old_revision: int = int(session.get("view_revision"))
	session.call("request_new_game", {"playerFaction": "ZONG_MEN", "sectName": "青岚战测宗", "mapWidth": 20, "mapHeight": 15, "randomSeed": "246810", "difficultyId": "normal"})
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
	# 宗主不可亲自出手/改习兵种，故战斗与转职相关断言一律取外门弟子。
	var outer: Array = []
	for disciple: Dictionary in player_sect.get("disciples", []):
		if str(disciple.get("position", "")) != "ZONG_ZHU":
			outer.append(disciple)
	check(outer.size() >= 2, "端到端：玩家有 ≥2 名外门弟子（outerCount=2）")
	if outer.size() < 2:
		session.call("shutdown")
		return
	var first: Dictionary = outer[0]
	var second: Dictionary = outer[1]
	var disciple_id: String = str(first.get("id", ""))
	var second_id: String = str(second.get("id", ""))
	check(str(first.get("unitClass", "")) == "PU_TONG", "端到端：开局兵种为寻常弟子 PU_TONG")

	# ② 点选外门弟子：可达集 → 可攻击集 → 弟子详情 三段串行链
	world.call("select_disciple", disciple_id)
	await _wait_idle(session, 20000)
	check(str(world.get("selected_disciple_id")) == disciple_id, "端到端：点选后主选中为该弟子")
	check((world.get("selected_ids") as Array).size() == 1, "端到端：单选时多选集合只有 1 人")
	check(bool(world.get("move_mode")), "端到端：首回合有移动力，进入移动模式")
	check(int(world.call("highlight_count")) > 0, "端到端：移动高亮层有格子")
	check(int(world.call("attack_highlight_count")) == 0, "端到端：开局无敌人在射程内，攻击高亮层为空")
	check(not bool(world.get("attack_mode")), "端到端：无可攻击格时不进入攻击模式")
	check(bool(world.call("unit_panel_visible")), "端到端：弟子详情面板自动打开")
	var detail: Dictionary = world.get("disciple_detail") as Dictionary
	check(bool(detail.get("found", false)), "端到端：queryDiscipleDetail 回包 found=true")
	check(int(detail.get("range", 0)) >= 1, "端到端：详情下发射程 range")
	check((detail.get("availableUnitClasses", []) as Array).size() == Enums.UnitClass.ALL.size(), "端到端：转职候选覆盖 10 个兵种")
	var unit_info: String = str(world.call("unit_info_text"))
	check(unit_info.contains("战功"), "端到端：弟子详情显示 battleXp")
	check(unit_info.contains("战阶"), "端到端：弟子详情显示 battleLevel")
	check(unit_info.contains("晋升点"), "端到端：弟子详情显示 promotionPoints")
	check(unit_info.contains("转职冷却"), "端到端：弟子详情显示 reclassCooldown")
	check(unit_info.contains("出手"), "端到端：弟子详情显示 strikesLeft（本回合剩余出手）")

	# ③ 十兵种转职候选三态：开局全置灰，blocker 逐类不同（道法未推演 / 流派专属 / 已是本兵种）
	var blocked_kinds: Dictionary = {}
	for entry: Dictionary in detail.get("availableUnitClasses", []):
		check(not bool(entry.get("allowed", true)), "端到端：开局 %s 转职不可用" % str(entry.get("id", "?")))
		blocked_kinds[str(entry.get("blocker", ""))] = true
	check(_blocker_of(detail, "PU_TONG").contains("已是"), "端到端：PU_TONG 的 blocker 为「已是寻常弟子」")
	check(_blocker_of(detail, "JIAN_XIU").contains("道法"), "端到端：JIAN_XIU 的 blocker 指向未推演道法")
	check(_blocker_of(detail, "XUE_MAI_XIU_SHI").contains("专属"), "端到端：血脉修士对宗门是流派专属兵种")
	check(_blocker_of(detail, "JI_GUAN_JUN_TUAN").contains("专属"), "端到端：机关军团对国家是流派专属兵种")
	check(blocked_kinds.size() >= 3, "端到端：转职 blocker 至少 3 类（专属/道法/已习）")
	var reclass_ui: Dictionary = world.call("reclass_button_state", "PU_TONG")
	check(not reclass_ui.is_empty(), "端到端：转职面板含 PU_TONG 按钮")
	if not reclass_ui.is_empty():
		check(bool(reclass_ui.get("disabled", false)), "端到端：不可用的转职按钮置灰")
		check(str(reclass_ui.get("tooltip", "")).contains("已是"), "端到端：转职按钮 tooltip 显示 blocker")
	check(int(world.call("unit_button_count")) > 10, "端到端：详情面板含机动/转职/晋升多段按钮")

	# ④ 晋升候选：开局无战功无晋升点 → 空清单 + 占位提示
	check((detail.get("availablePromotions", []) as Array).is_empty(), "端到端：开局 availablePromotions 为空")
	check(int(detail.get("promotionPoints", 0)) == 0, "端到端：开局晋升点为 0")

	# ⑤ 攻击预览：对本格（无敌方目标）→ 明确 blockedReason，且不给「发起攻击」按钮
	await _wait_idle(session, 15000)
	var own_tile: String = str(first.get("tileId", ""))
	world.call("query_attack_preview", own_tile)
	await _wait_idle(session, 15000)
	var preview: Dictionary = world.get("attack_preview") as Dictionary
	check(str(preview.get("targetTileId", "")) == own_tile, "端到端：queryAttackPreview 回包带 targetTileId")
	check(not bool(preview.get("attackable", true)), "端到端：本格无敌方目标时 attackable=false")
	check(str(preview.get("blockedReason", "")).contains("没有可攻击的敌方目标"), "端到端：blockedReason 指明无敌方目标")
	var combat_info: String = str(world.call("combat_info_text"))
	check(combat_info.contains("不可攻击"), "端到端：战斗面板显示「不可攻击」")
	check(combat_info.contains("没有可攻击的敌方目标"), "端到端：战斗面板显示 blockedReason 原文")
	check(int(world.call("combat_button_count")) == 0, "端到端：不可攻击时不给「发起攻击」按钮")
	check(bool(world.call("combat_panel_visible")), "端到端：有预览时战斗面板显示")

	# ⑥ attack 业务失败：ok=true + success=false，只提示不刷新 view
	await _wait_idle(session, 15000)
	var revision_before: int = int(session.get("view_revision"))
	session.call("request_attack", disciple_id, own_tile)
	await _wait_idle(session, 15000)
	var feedback: String = str(world.call("combat_feedback_text"))
	check(feedback.begins_with("✗"), "端到端：attack 业务失败时战斗面板提示 ✗")
	check(feedback.contains("没有可攻击的敌方目标"), "端到端：失败提示含 blockedReason 原文")
	check(int(session.get("view_revision")) == revision_before, "端到端：attack 业务失败不刷新 view")

	# ⑦ reclass 业务失败（已是本兵种）+ 非法枚举走协议失败 BAD_PARAMS
	await _wait_idle(session, 15000)
	session.call("request_reclass", disciple_id, "PU_TONG")
	await _wait_idle(session, 15000)
	check(str(world.call("combat_feedback_text")).contains("已是"), "端到端：reclass 到本兵种返回「已是寻常弟子」")
	await _wait_idle(session, 15000)
	revision_before = int(session.get("view_revision"))
	session.call("request_reclass", disciple_id, "NOT_A_UNIT_CLASS")
	await _wait_idle(session, 15000)
	check(str(world.call("combat_feedback_text")).begins_with("✗"), "端到端：非法兵种枚举回 BAD_PARAMS 并提示 ✗")
	check(int(session.get("view_revision")) == revision_before, "端到端：非法枚举不产生新 view")

	# ⑧ promote 业务失败：无晋升点
	await _wait_idle(session, 15000)
	session.call("request_promote", disciple_id, "pro_sword_essence")
	await _wait_idle(session, 15000)
	check(str(world.call("combat_feedback_text")).contains("晋升点不足"), "端到端：promote 无晋升点时业务失败")

	# ⑨ retreat 业务失败：目标非相邻
	await _wait_idle(session, 15000)
	var far_tile: String = _far_tile(session, own_tile)
	session.call("request_retreat", disciple_id, far_tile)
	await _wait_idle(session, 15000)
	check(str(world.call("combat_feedback_text")).contains("相邻"), "端到端：retreat 到非相邻格返回「只能撤往相邻地块」")

	# ⑩ 传送：未推演 chuan_song → enabled=false / capacity=0，面板给出明确提示
	await _wait_idle(session, 15000)
	session.call("request_query_teleport_options", disciple_id)
	await _wait_idle(session, 15000)
	var teleport: Dictionary = world.get("teleport_options") as Dictionary
	check(bool(teleport.get("found", false)), "端到端：queryTeleportOptions 回包 found=true")
	check(not bool(teleport.get("enabled", true)), "端到端：未推演 chuan_song 时传送未开启")
	check(int(teleport.get("capacity", -1)) == 0, "端到端：未开启时 capacity=0（API 自洽）")
	check(int(teleport.get("remaining", -1)) == 0, "端到端：未开启时 remaining=0")
	check(str(world.call("combat_feedback_text")).contains("传送网络未开启"), "端到端：面板提示传送网络未开启")

	# ⑪ 驻守：非法节点 id → 业务/协议失败提示（弟子也不在节点地块上）
	await _wait_idle(session, 15000)
	session.call("request_assign_garrison", disciple_id, "node_does_not_exist")
	await _wait_idle(session, 15000)
	check(str(world.call("combat_feedback_text")).begins_with("✗"), "端到端：驻守非法节点返回失败提示")

	# ⑫ Shift 多选 → 点可达格走 batchMove（两人同格）
	await _wait_idle(session, 15000)
	world.call("select_disciple", second_id, true)
	await get_tree().process_frame
	check((world.get("selected_ids") as Array).size() == 2, "端到端：Shift+点选把第 2 人加入多选集合")
	check(str(world.get("selected_disciple_id")) == disciple_id, "端到端：多选不改变主选中弟子")
	var target: String = _reachable_target(world, own_tile)
	check(not target.is_empty(), "端到端：可达集里有可作批量移动目标的格子")
	if not target.is_empty():
		world.call("on_tile_clicked", target)
		await _wait_idle(session, 20000)
		check(str(world.call("combat_feedback_text")).begins_with("✓"), "端到端：batchMove 成功并提示 ✓")
		var moved: Dictionary = _disciple_of(session, disciple_id)
		var moved_second: Dictionary = _disciple_of(session, second_id)
		check(str(moved.get("tileId", "")) == target, "端到端：批量移动后主弟子抵达目标格")
		check(str(moved_second.get("tileId", "")) == target, "端到端：批量移动后第 2 人同格抵达")
		check(str(world.call("combat_feedback_text")).contains("2/2"), "端到端：batchMove 报告 2/2 人抵达")

	# ⑬ 两层高亮互相独立：清移动层不影响攻击层
	var map: HexMap = world.get("map") as HexMap
	var tile_ids: Array = []
	for tile_id: String in (session.get("current_view") as Dictionary).get("tiles", {}):
		tile_ids.append(tile_id)
		if tile_ids.size() >= 2:
			break
	check(tile_ids.size() >= 2, "端到端：view 至少含 2 个地块（高亮层测试前提）")
	if tile_ids.size() >= 2:
		map.clear_move_range()
		map.clear_attack_range()
		map.show_move_range([tile_ids[0]], {}, tile_ids[0])
		map.show_attack_range([tile_ids[1]], tile_ids[0])
		check(map.highlight_ids.size() == 1, "端到端：移动高亮层画出 1 格")
		check(map.attack_ids.size() == 1, "端到端：攻击高亮层画出 1 格")
		map.clear_move_range()
		check(map.highlight_ids.is_empty() and map.attack_ids.size() == 1, "端到端：清移动层不影响攻击层")
		map.clear_attack_range()
		check(map.attack_ids.is_empty(), "端到端：清攻击层后为空")

	# ⑭ 相机铁律：全程不重置
	check(camera.global_transform.is_equal_approx(transform_before) and is_equal_approx(camera.size, size_before), "端到端：点选/预览/攻击/转职/晋升/传送/驻守/撤退/批量移动全程相机 transform/size 不变")

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


func _disciple_of(session: Node, disciple_id: String) -> Dictionary:
	for sect: Dictionary in (session.get("current_view") as Dictionary).get("sects", []):
		for disciple: Dictionary in sect.get("disciples", []):
			if str(disciple.get("id", "")) == disciple_id:
				return disciple
	return {}


func _blocker_of(detail: Dictionary, unit_class: String) -> String:
	for entry: Dictionary in detail.get("availableUnitClasses", []):
		if str(entry.get("id", "")) == unit_class:
			return str(entry.get("blocker", ""))
	return ""


## 可达集里第一个非起点格（batchMove 的目标）。
func _reachable_target(world_node: Node3D, origin: String) -> String:
	var ids: Array = world_node.get("reachable_ids")
	for value: Variant in ids:
		if str(value) != origin:
			return str(value)
	return ""


## 找一个与 `origin` 距离 ≥3 的地块（retreat 的非法目标）。
func _far_tile(session: Node, origin: String) -> String:
	var tiles: Dictionary = (session.get("current_view") as Dictionary).get("tiles", {})
	if not tiles.has(origin):
		for tile_id: String in tiles:
			return tile_id
		return ""
	var from: Dictionary = tiles[origin]
	for tile_id: String in tiles:
		if tile_id == origin:
			continue
		var data: Dictionary = tiles[tile_id]
		var distance: int = Hex.distance(
			Vector2i(int(from.get("q", 0)), int(from.get("r", 0))),
			Vector2i(int(data.get("q", 0)), int(data.get("r", 0))))
		if distance >= 3:
			return tile_id
	return ""


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
		print("R5_CLIENT_PASS: " + label)
	else:
		failures += 1
		push_error("R5_CLIENT_FAIL: " + label)


func finish() -> void:
	print("R5_CLIENT_RESULT=%s checks=%d failures=%d" % ["OK" if failures == 0 else "FAIL", checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
