extends Node

var checks: int = 0
var failures: int = 0
var world: Node3D = null

func _ready() -> void:
	await get_tree().process_frame
	var required: Array[String] = ["res://scripts/world/HexMap.gd", "res://scripts/world/Fog.gd", "res://scripts/world/CameraRig.gd", "res://scripts/world/UnitView.gd", "res://scripts/world/SectView.gd", "res://scripts/art/AssetLibrary.gd", "res://scripts/net/Session.gd", "res://scenes/MainMenu.tscn", "res://scenes/World.tscn"]
	for path: String in required:
		check(FileAccess.file_exists(path), "R1 表现组件存在：" + path)
	if failures > 0:
		finish()
		return
	var session: Node = get_node("/root/Session")
	session.call("accept_view", fixture())
	world = (load("res://scenes/World.tscn") as PackedScene).instantiate() as Node3D
	add_child(world)
	await get_tree().process_frame
	var map: Node3D = world.get_node("HexMap") as Node3D
	var tiles: Dictionary = map.get("tiles")
	check(tiles.size() == 7, "fixture 七格全部渲染")
	check(is_equal_approx(float(tiles["q0_r0"].get_meta("height")), 1.0), "平地柱高来自 renderHints")
	check(is_equal_approx(float(tiles["q1_r0"].get_meta("height")), 1.7), "丘陵柱高来自 renderHints")
	check(is_equal_approx(float(tiles["q2_r0"].get_meta("height")), 3.0), "山岳柱高来自 renderHints")
	check(tiles["q2_r0"].has_node("Mountain"), "山岳叠加峰顶")
	check(tiles["q3_r0"].has_node("Mountain"), "邻接山格都保留山体")
	check(tiles["q0_r0"].has_node("SPIRIT_FOREST"), "灵林落于顶面")
	check(tiles["q1_r0"].has_node("MIRE"), "雾泽落于顶面")
	check(tiles["q1_r0"].has_node("Danger"), "险地有顶面贴片")
	check(int(map.get("river_count")) == 1, "成对河边只渲染一次")
	check(float(tiles["q5_r0"].get_meta("height")) < 1.0, "未探索只绘低柱，不泄露海拔")
	check((tiles["q5_r0"].get_meta("display_data") as Dictionary).size() == 3, "未探索不存可查询地形")
	check(tiles["q5_r0"].get_child_count() == 2, "未探索无地貌、河流、节点装饰")
	check(int(tiles["q4_r0"].get_meta("fog_state")) == 1, "已探索隐藏格使用古图状态")
	check(int(tiles["q0_r0"].get_meta("fog_state")) == 2, "可见格使用实景状态")
	var side: MeshInstance3D = tiles["q0_r0"].get_node("Side") as MeshInstance3D
	var top: MeshInstance3D = tiles["q0_r0"].get_node("Top") as MeshInstance3D
	check(side.material_override != top.material_override, "顶面侧面独立材质")
	verify_flat_top(side)
	var units: Node3D = world.get_node("UnitView") as Node3D
	check(units.get_child_count() == 1, "仅当前可见格显示单位，古图与未探索均不显示")
	var unit: Node3D = units.get_child(0) as Node3D
	check(is_equal_approx(unit.position.y, 1.7), "单位落于丘陵顶面")
	var peaks: Node3D = world.get_node("SectView") as Node3D
	check(peaks.get_child_count() == 2, "可见峰与服务端记忆峰显示，未探索敌峰不显示")
	check(int(world.get("sect_count")) == 4, "侧栏可显示四宗公开 metadata")
	world.call("select_tile", "q5_r0")
	check(str(world.get("selection_text")).contains("未探索") and not str(world.get("selection_text")).contains("MOUNTAIN"), "未探索侧栏不泄露地形")
	world.call("select_tile", "q1_r0")
	check(str(world.get("selection_text")).contains("HILL") and str(world.get("selection_text")).contains("ling_cha"), "已知侧栏列出海拔及资源")
	var rig: Node3D = session.get("camera_rig") as Node3D
	var camera: Camera3D = rig.get("camera") as Camera3D
	check(camera.projection == Camera3D.PROJECTION_ORTHOGONAL, "相机为正交投影")
	# 取景朝向以 `CameraRig` 常量为唯一权威：R10 起改为「偏航 0 + 俯角 50°」的 Civ VI 同款
	# （网格行沿屏幕水平方向），原先的 yaw45 会把六边形网格斜成菱形。
	check(camera.rotation_degrees.is_equal_approx(
		Vector3(CameraRig.PITCH_DEGREES, CameraRig.YAW_DEGREES, 0.0)),
		"相机锁 Civ VI 朝向（yaw %.0f / pitch %.0f）" % [CameraRig.YAW_DEGREES, CameraRig.PITCH_DEGREES])
	check(is_zero_approx(CameraRig.YAW_DEGREES), "网格正对镜头（偏航 0），不斜成菱形")
	var cursor: Vector2 = Vector2(580.0, 340.0)
	var anchor: Vector3 = rig.call("ground_point", cursor)
	rig.call("zoom_at", cursor, 0.8)
	check(anchor.distance_to(rig.call("ground_point", cursor)) < 0.001, "鼠标缩放维持地面 anchor")
	var before_pan: Vector3 = rig.call("ground_point", cursor)
	rig.call("pan_between", cursor, cursor + Vector2(70.0, -25.0))
	check(before_pan.distance_to(rig.call("ground_point", cursor + Vector2(70.0, -25.0))) < 0.001, "拖拽平移地面 anchor 随鼠标")
	var transform_before: Transform3D = camera.global_transform
	var size_before: float = camera.size
	session.call("accept_view", fixture())
	check(camera.global_transform.is_equal_approx(transform_before) and is_equal_approx(camera.size, size_before), "view refresh 不重置相机")
	world.queue_free()
	await get_tree().process_frame
	var menu: Control = (load("res://scenes/MainMenu.tscn") as PackedScene).instantiate() as Control
	add_child(menu)
	await get_tree().process_frame
	var params: Dictionary = menu.call("build_params")
	check(params["playerFaction"] == "ZONG_MEN" and params["mapWidth"] == 20 and params["mapHeight"] == 15 and params["difficultyId"] == "normal", "菜单使用标准参数及20×15默认值")
	check(not params.has("randomSeed"), "空种子不伪造随机，由服务端 RNG 处理")
	check((menu.get("start_button") as Button).disabled, "hello 前开局按钮门控")
	menu.queue_free()
	await get_tree().process_frame
	session.call("accept_view", fixture())
	world = (load("res://scenes/World.tscn") as PackedScene).instantiate() as Node3D
	add_child(world)
	await get_tree().process_frame
	check(session.get("camera_rig") == rig and camera.global_transform.is_equal_approx(transform_before) and is_equal_approx(camera.size, size_before), "返回菜单再开局保留同一相机与 transform/size")
	var assets: Node = session.get("assets") as Node
	var warnings_before: int = int(assets.get("warning_count"))
	var placeholder: Node3D = assets.call("instantiate_model", "missing.test.model", "占位验证")
	check(placeholder.get_child_count() >= 2, "模型缺失回退灰阶几何与文字")
	placeholder.free()
	placeholder = assets.call("instantiate_model", "missing.test.model", "占位验证")
	placeholder.free()
	check(int(assets.get("warning_count")) == warnings_before + 1, "同一缺失 logicalID 只 WARN 一次")
	check(assets.call("resource_for", "missing.test.texture", "texture") is Texture2D, "缺失贴图回退纯色块")
	check(assets.call("resource_for", "missing.test.material", "material") is Material, "缺失材质安全回退")
	check(assets.call("resource_for", "missing.test.txt", "font") is Font, "无效文本字体安全回退")
	var generation_before: int = int(assets.get("generation"))
	assets.call("reload_manifest")
	check(int(assets.get("generation")) == generation_before + 1, "F5 热重读 manifest 并使缓存失效")
	if OS.get_cmdline_user_args().has("--integration"):
		await integration(session)
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		check(get_viewport().get_texture().get_image().save_png("res://outputs/R1_fixture.png") == OK, "GUI viewport 截图保存成功")
	finish()

func verify_flat_top(side: MeshInstance3D) -> void:
	var arrays: Array = side.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	# 手算 flat-top 顶点：x=±1,z=0 与 x=±0.5,z=±sqrt(3)/2。
	var wants: Array[Vector2] = [Vector2(1, 0), Vector2(0.5, 0.8660254), Vector2(-0.5, 0.8660254), Vector2(-1, 0), Vector2(-0.5, -0.8660254), Vector2(0.5, -0.8660254)]
	for want: Vector2 in wants:
		var matched: bool = false
		for vertex: Vector3 in vertices:
			var point: Vector3 = side.transform * vertex
			if Vector2(point.x, point.z).distance_to(want) < 0.001:
				matched = true
		check(matched, "六棱柱实际 mesh 顶点对齐 flat-top：" + str(want))

func integration(session: Node) -> void:
	# 菜单节点在上文已 queue_free，不能再作为带类型的 Control 参数传入。
	session.call("start_connection", 19537)
	# 冷启动实测最长 19s，deadline 取 45s（> Session 的 40s 就绪超时）留足余量。
	var deadline: int = Time.get_ticks_msec() + 45000
	while not bool(session.call("supports", "newGame")) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check(bool(session.call("supports", "newGame")), "实际 Launcher/NetClient 收到 newGame hello")
	if not bool(session.call("supports", "newGame")):
		# 提前返回前必须回收拉起的服务端，否则残留 godot 进程。
		session.call("shutdown")
		return
	var old_revision: int = int(session.get("view_revision"))
	session.call("request_new_game", {"playerFaction": "ZONG_MEN", "sectName": "青岚测试宗", "mapWidth": 20, "mapHeight": 15, "randomSeed": "123456", "difficultyId": "normal"})
	deadline = Time.get_ticks_msec() + 10000
	while int(session.get("view_revision")) == old_revision and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	var view: Dictionary = session.get("current_view")
	check(int(session.get("view_revision")) > old_revision and (view["tiles"] as Dictionary).size() == 300, "实际 newGame 返回300格 view")
	check((view["sects"] as Array).size() == 4, "实际 newGame 返回四宗公开信息")
	check((view["exploredTiles"] as Array).size() == (view["visibleTiles"] as Array).size(), "开局实际两态，不伪造探索数据")
	var camera: Camera3D = (session.get("camera_rig") as Node).get("camera") as Camera3D
	var prior: Transform3D = camera.global_transform
	var size_prior: float = camera.size
	old_revision = int(session.get("view_revision"))
	session.call("request_refresh")
	deadline = Time.get_ticks_msec() + 10000
	while int(session.get("view_revision")) == old_revision and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check(int(session.get("view_revision")) > old_revision, "实际 getState 往返成功")
	check(camera.global_transform.is_equal_approx(prior) and is_equal_approx(camera.size, size_prior), "实际服务端刷新保持相机")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		check(get_viewport().get_texture().get_image().save_png("res://outputs/R1_live.png") == OK, "实际开局 GUI 截图保存成功")
	session.call("shutdown")

func fixture() -> Dictionary:
	var data: Dictionary = {}
	var reliefs: Array[String] = ["FLAT", "HILL", "MOUNTAIN", "MOUNTAIN", "HILL", "MOUNTAIN", "FLAT"]
	for q: int in range(7):
		var tile_id: String = "q%d_r0" % q
		data[tile_id] = {"id": tile_id, "q": q, "r": 0, "baseTerrain": "LING_FIELDS", "relief": reliefs[q], "features": [], "riverEdges": [], "danger": false, "ownerSectId": "", "nodeId": "", "districtId": "", "workedByPeakId": "", "improvementId": "", "luxuryType": ""}
	data["q0_r0"]["features"] = ["SPIRIT_FOREST"]
	data["q0_r0"]["riverEdges"] = [0]
	data["q1_r0"]["riverEdges"] = [3]
	data["q1_r0"]["features"] = ["MIRE"]
	data["q1_r0"]["danger"] = true
	data["q1_r0"]["luxuryType"] = "ling_cha"
	data["q1_r0"]["nodeId"] = "node1"
	data["q4_r0"]["ownerSectId"] = "enemy"
	# 刻意给未探索格注入字段，验证客户端也不会漏绘/漏查；真实服务端是 null。
	var sects: Array[Dictionary] = [{"id": "player", "name": "青岚宗", "player": true, "color": "#267b75", "disciples": [{"id": "u1", "tileId": "q1_r0", "unitClass": "PU_TONG", "name": "宗主"}], "spiritPeaks": [{"id": "p1", "tileId": "q0_r0", "name": "青岚主峰"}]}, {"id": "enemy", "name": "记忆宗", "player": false, "color": "#bc685c", "disciples": [{"id": "u2", "tileId": "q4_r0", "name": "隐蔽弟子"}, {"id": "u3", "tileId": "q5_r0", "name": "未探索弟子"}], "spiritPeaks": [{"id": "p2", "tileId": "q4_r0", "name": "旧峰快照"}, {"id": "p3", "tileId": "q5_r0", "name": "隐蔽峰"}]}, {"id": "e2", "name": "家族", "disciples": [], "spiritPeaks": []}, {"id": "e3", "name": "国家", "disciples": [], "spiritPeaks": []}]
	return {"metadata": {"turn": 1, "phase": "PLAYER_ACTION", "mapWidth": 7, "mapHeight": 1, "randomSeed": "123456", "difficultyId": "normal", "playerSectId": "player"}, "tiles": data, "nodes": {"node1": {"id": "node1", "type": "LING_QUAN", "tileId": "q1_r0"}}, "sects": sects, "visibleTiles": ["q0_r0", "q1_r0", "q2_r0", "q3_r0"], "exploredTiles": ["q0_r0", "q1_r0", "q2_r0", "q3_r0", "q4_r0"], "renderHints": {"reliefHeight": {"FLAT": 1.0, "HILL": 1.7, "MOUNTAIN": 3.0}}}

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok:
		print("R1_CLIENT_PASS: " + label)
	else:
		failures += 1
		push_error("R1_CLIENT_FAIL: " + label)

func finish() -> void:
	print("R1_CLIENT_RESULT=%s checks=%d failures=%d" % ["OK" if failures == 0 else "FAIL", checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
