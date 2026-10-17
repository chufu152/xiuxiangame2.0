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
## 不入库（`/outputs/` 已在 .gitignore）。

const TEST_PORT: int = 19599
const WARMUP_FRAMES: int = 90
const MAP_WIDTH: int = 26
const MAP_HEIGHT: int = 18


func _ready() -> void:
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
	var path: String = ProjectSettings.globalize_path("res://outputs/ui_preview_map.png")
	var code: int = image.save_png(path)
	print("WORLDSHOT_SAVED: %s (%dx%d) code=%d" % [path, image.get_width(), image.get_height(), code])
	session.call("shutdown")
	get_tree().quit(0 if code == OK else 1)
