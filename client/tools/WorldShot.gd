extends Node
## GUI 联络表：真实拉起服务端 → newGame → 装配 `World` → 截图到 `outputs/`。
##
## 用途：R8 之后每次改 HUD/地图/建筑，都能用一张真实渲染图肉眼核对，
## 而不是靠 headless 断言猜观感。
##
## 运行（**不能加 `--headless`**，否则无渲染设备）：
##   Godot_v4.4.1-stable_win64_console.exe --path client res://tools/WorldShot.tscn
##
## 产物：`outputs/ui_preview_map.png`（全景）、`outputs/ui_preview_hud.png`（同帧，HUD 已就位）。
## 以及每个卷轴界面一张：`ui_preview_turn_summary.png` / `ui_preview_dao_tree.png` /
## `ui_preview_saves.png` / `ui_preview_combat.png` / `ui_preview_victory.png`。
## 不入库（`/outputs/` 已在 .gitignore）。

const TEST_PORT: int = 19599
const WARMUP_FRAMES: int = 90
const MAP_WIDTH: int = 26
const MAP_HEIGHT: int = 18

## 皮肤包（`--pack=<name>`）。非 default 时只截一张全景（面板与皮肤无关，不重复截）。
var _shot_pack: String = "default"


func _ready() -> void:
	_shot_pack = _read_arg("--pack=", "default")
	var session: Node = get_node("/root/Session")
	session.call("start_connection", TEST_PORT)
	var deadline: int = Time.get_ticks_msec() + 60000
	while not bool(session.call("supports", "newGame")) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if not bool(session.call("supports", "newGame")):
		push_error("WORLDSHOT_FAIL: 未能连上服务端")
		get_tree().quit(1)
		return

	session.call("request_new_game", {
		"playerFaction": "ZONG_MEN",
		"sectName": "青岚决天宗",
		"mapWidth": MAP_WIDTH,
		"mapHeight": MAP_HEIGHT,
		"randomSeed": "864213",
		"difficultyId": "normal",
	})
	var view_deadline: int = Time.get_ticks_msec() + 60000
	while (session.get("current_view") as Dictionary).is_empty() and Time.get_ticks_msec() < view_deadline:
		await get_tree().process_frame
	if (session.get("current_view") as Dictionary).is_empty():
		push_error("WORLDSHOT_FAIL: 未拿到首个 view")
		get_tree().quit(1)
		return

	var world: Node3D = (load("res://scenes/World.tscn") as PackedScene).instantiate() as Node3D
	add_child(world)
	# 换皮必须发生在取景之后：`apply_skin` 只重建表现层，不动相机（相机铁律）。
	if _shot_pack != "default":
		world.call("apply_skin", _shot_pack)
	# 让远景/装饰/泼墨转场与 HUD 布局稳定下来再截。
	for _frame: int in range(WARMUP_FRAMES):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw

	DirAccess.make_dir_recursive_absolute("res://outputs")
	var image: Image = get_viewport().get_texture().get_image()
	if image == null:
		push_error("WORLDSHOT_FAIL: 视口无纹理")
		get_tree().quit(1)
		return
	var map_name: String = "ui_preview_map.png" if _shot_pack == "default" else "ui_preview_map_%s.png" % _shot_pack
	var path: String = ProjectSettings.globalize_path("res://outputs/" + map_name)
	var code: int = image.save_png(path)
	print("WORLDSHOT_SAVED: %s (%dx%d) code=%d" % [path, image.get_width(), image.get_height(), code])

	if _shot_pack != "default":
		print("WORLDSHOT_DONE pack=%s" % _shot_pack)
		get_tree().quit(0)
		return

	# 打一个完整回合：让回合结算卷轴有真实资源增减与事件文案可展示（而不是空栏）。
	await _play_one_turn(world, session)
	# 选中己方首个弟子：让战斗界面/单位卡有真实数据（战力/射程/移动力）。
	await _select_first_disciple(world, session)

	# 卷轴界面逐个实拍（每个界面先开、等布局稳定、再关）。
	await _capture_screen(world, session, "ui_preview_turn_summary.png", "open_turn_summary", "close_turn_summary", true)
	await _capture_screen(world, session, "ui_preview_dao_tree.png", "open_dao_panel", "close_dao_panel", false)
	await _capture_screen(world, session, "ui_preview_saves.png", "open_saves_panel", "close_saves_panel", true)
	await _capture_screen(world, session, "ui_preview_combat.png", "open_combat_screen", "close_combat_screen", false)
	await _capture_screen(world, session, "ui_preview_victory.png", "open_victory_screen", "close_victory_screen", false)

	session.call("shutdown")
	get_tree().quit(0 if code == OK else 1)


## 打一个完整回合：让回合结算卷轴有真实资源增减与事件文案可展示（而不是空栏）。
func _play_one_turn(world: Node3D, session: Node) -> void:
	var turn_before: int = _turn_of(session)
	session.call("request_end_turn_sequence")
	var deadline: int = Time.get_ticks_msec() + 30000
	while _turn_of(session) == turn_before and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	# 等 view 刷新把结算卷轴自动弹出并稳定布局。
	for _frame: int in range(30):
		await get_tree().process_frame
	print("WORLDSHOT_TURN: %d → %d，结算卷轴可见=%s" % [
		turn_before, _turn_of(session), str(world.call("turn_summary_visible"))])


func _turn_of(session: Node) -> int:
	var view: Dictionary = session.get("current_view")
	var meta: Dictionary = view.get("metadata", {})
	return int(meta.get("turn", view.get("turn", 0)))


## 选中玩家第一个弟子（触发 queryMoveRange → queryAttackable 串行链，战斗界面才有射程/胜率）。
func _select_first_disciple(world: Node3D, session: Node) -> void:
	var view: Dictionary = session.get("current_view")
	for entry: Variant in view.get("sects", []):
		var sect: Dictionary = entry
		if not bool(sect.get("player", false)):
			continue
		var disciples: Array = sect.get("disciples", [])
		if disciples.is_empty():
			return
		var disciple_id: String = str((disciples[0] as Dictionary).get("id", ""))
		world.call("select_disciple", disciple_id)
		for _frame: int in range(30):
			await get_tree().process_frame
		print("WORLDSHOT_SELECT: %s（选中弟子 %s）" % [
			str((disciples[0] as Dictionary).get("name", "")), disciple_id])
		return


## 打开某个界面 → 截图 → 关闭。`settle` 为 true 时多等一会儿（有异步请求的界面）。
func _capture_screen(world: Node3D, session: Node, file_name: String, open_call: String,
		close_call: String, settle: bool) -> void:
	if not world.has_method(open_call):
		print("WORLDSHOT_SKIP: %s（World 尚无 %s）" % [file_name, open_call])
		return
	world.call(open_call)
	var frames: int = 40 if settle else 12
	for _frame: int in range(frames):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	if image == null:
		print("WORLDSHOT_FAIL: %s 视口无纹理" % file_name)
		return
	var path: String = ProjectSettings.globalize_path("res://outputs/" + file_name)
	var code: int = image.save_png(path)
	print("WORLDSHOT_SAVED: %s code=%d" % [path, code])
	if world.has_method(close_call):
		world.call(close_call)
	for _frame: int in range(4):
		await get_tree().process_frame


static func _read_arg(prefix: String, fallback: String) -> String:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with(prefix):
			return arg.substr(prefix.length())
	for arg: String in OS.get_cmdline_args():
		if arg.begins_with(prefix):
			return arg.substr(prefix.length())
	return fallback
