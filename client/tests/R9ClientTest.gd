extends Node
## R9 客户端验收：导出态路径解析（W3）+ 换皮机制（W2）。
##
## 无头运行：`godot --headless --path client res://tests/R9ClientTest.tscn [-- --integration]`。
## 不带 `--integration` 时只跑不依赖服务端的断言（两套根目录口径、皮肤包切换的路径层）。
## 带 `--integration` 时额外跑「真 view 下换皮」：切包后 view 逐字不变、相机不变、
## 但地形贴图实例确实换了（证明换皮真的生效，而不是什么都没发生）。
##
## 为什么导出态要单独测：`OS.has_feature("template")` 在编辑器里恒为 false，
## 而它恰恰是最容易写错的一段——导出后 `res://` 已指向可执行文件所在目录，
## 再套一次 `get_base_dir()` 就会跑到上一级，`assets/`、`data/` 全部定位失败。
## 故用 `Launcher._exported_override` 强制切态做真实断言。

const TEST_PORT: int = 19582

var checks: int = 0
var failures: int = 0
var world: Node3D = null


func _ready() -> void:
	await get_tree().process_frame
	var session: Node = get_node("/root/Session")

	await _assert_export_paths()
	await _assert_skin_paths(session)

	if OS.get_cmdline_user_args().has("--integration"):
		await _integration(session)

	# 复位，避免污染后续测试
	Launcher._exported_override = -1
	if session.get("assets") != null:
		(session.get("assets") as AssetLibrary).reset_pack()

	print("R9_CLIENT_RESULT=%s checks=%d failures=%d" % ["OK" if failures == 0 else "FAIL", checks, failures])
	get_tree().quit(0 if failures == 0 else 1)


# ---------------------------------------------------------------------------
# W3：开发态 / 导出态两套根目录口径
# ---------------------------------------------------------------------------

func _assert_export_paths() -> void:
	await get_tree().process_frame

	var engine_exe_dir: String = OS.get_executable_path().get_base_dir()
	var res_dir: String = ProjectSettings.globalize_path("res://").trim_suffix("/")
	var editor_repo_root: String = res_dir.get_base_dir()

	# ① 编辑器里必须判为开发态
	Launcher._exported_override = -1
	check(not Launcher.is_exported(), "编辑器内 is_exported() = false")
	check(Launcher.repo_root() == editor_repo_root,
		"开发态 repo_root() = client/ 的上一级（实际 %s）" % Launcher.repo_root())
	check(Launcher.server_project_dir() == editor_repo_root.path_join("server"),
		"开发态 server_project_dir() 指向仓库 server/（实际 %s）" % Launcher.server_project_dir())
	check(Launcher.default_data_path() == editor_repo_root.path_join("data/gameConfig.json"),
		"开发态 default_data_path() 指向仓库 data/gameConfig.json")
	check(FileAccess.file_exists(Launcher.default_data_path()),
		"开发态 default_data_path() 真实存在（%s）" % Launcher.default_data_path())

	# ② 强制导出态：根目录 = 可执行文件所在目录
	Launcher._exported_override = 1
	var exported_root: String = Launcher.repo_root()
	check(Launcher.is_exported(), "强制导出态 is_exported() = true")
	check(exported_root == engine_exe_dir,
		"导出态 repo_root() = 可执行文件所在目录（期望 %s，实际 %s）" % [engine_exe_dir, exported_root])
	# 这条是**回归钉子**：老写法 `globalize_path("res://").get_base_dir()` 在导出态会跑到上一级。
	check(exported_root != res_dir.get_base_dir(),
		"导出态 repo_root() 不是 res:// 的上一级（老写法会错到 %s）" % res_dir.get_base_dir())
	check(Launcher.server_executable() == exported_root.path_join(Launcher.SERVER_EXE_NAME),
		"导出态 server_executable() = <产物目录>/%s" % Launcher.SERVER_EXE_NAME)
	check(Launcher.server_executable().get_file() == "XiuxianServer.exe",
		"导出态服务端可执行文件名与导出预设一致（XiuxianServer.exe）")
	check(Launcher.server_project_dir() == Launcher.server_executable(),
		"导出态 server_project_dir() 退化为服务端可执行文件路径（无工程目录概念）")
	check(Launcher.default_data_path() == exported_root.path_join("data/gameConfig.json"),
		"导出态 default_data_path() = <产物目录>/data/gameConfig.json")
	check(Launcher.default_data_path().begins_with(exported_root),
		"导出态 assets/ 与 data/ 同根（asset_root 走同一个 repo_root()）")

	# ③ 导出态缺服务端可执行文件时必须给出可诊断错误，而不是静默失败
	var real_data: String = editor_repo_root.path_join("data/gameConfig.json")
	var outcome: Dictionary = Launcher.launch(19999, real_data)
	check(not bool(outcome["ok"]), "导出态缺服务端 exe 时 launch() 返回 ok=false")
	check(str(outcome["error"]).contains("XiuxianServer.exe"),
		"错误信息点名缺失的可执行文件（实际：%s）" % str(outcome["error"]))
	check(int(outcome["pid"]) <= 0, "失败时 pid ≤ 0（不会被误当成已拉起）")

	# ④ 复位
	Launcher._exported_override = -1
	check(not Launcher.is_exported(), "复位后回到开发态")


# ---------------------------------------------------------------------------
# W2：皮肤包切换（路径层，不需要服务端）
# ---------------------------------------------------------------------------

func _assert_skin_paths(session: Node) -> void:
	var assets: AssetLibrary = session.get("assets") as AssetLibrary
	if assets == null:
		check(false, "Session.assets 存在")
		return

	var packs: Array[String] = assets.available_packs()
	check(packs.has("default"), "磁盘上存在默认皮肤包 default（实际：%s）" % ", ".join(packs))
	check(packs.has("zhu_xia"), "磁盘上存在第二套皮肤包 zhu_xia（实际：%s）" % ", ".join(packs))
	check(assets.active_pack == "default",
		"初始皮肤包来自 manifest.activePack（实际 %s）" % assets.active_pack)

	var default_entry: Dictionary = assets.entries.get("unit.PU_TONG", {})
	check(str(default_entry.get("path", "")).contains("art/default/"),
		"默认包条目路径落在 art/default/（实际 %s）" % str(default_entry.get("path", "")))
	var default_model: Resource = assets.resource_for("unit.PU_TONG", "model")
	check(default_model is PackedScene, "默认包能取到 unit.PU_TONG 模型")

	# ① 切到 zhu_xia
	check(assets.set_pack("zhu_xia"), "set_pack(\"zhu_xia\") 返回 true")
	check(assets.active_pack == "zhu_xia", "切换后 active_pack = zhu_xia")
	var zx_entry: Dictionary = assets.entries.get("unit.PU_TONG", {})
	check(str(zx_entry.get("path", "")).contains("art/zhu_xia/"),
		"换包后条目路径改写到 art/zhu_xia/（实际 %s）" % str(zx_entry.get("path", "")))
	var zx_model: Resource = assets.resource_for("unit.PU_TONG", "model")
	check(zx_model is PackedScene, "zhu_xia 包能取到 unit.PU_TONG 模型")
	check(zx_model != default_model, "换包后拿到的是另一个资源实例（缓存已失效）")
	check(assets.resource_for("terrain.base.SPIRIT_PLAIN", "texture") is Texture2D,
		"zhu_xia 包能取到地形贴图")

	# ② 不存在的包必须拒绝，且不改变当前状态
	check(not assets.set_pack("no_such_pack"), "set_pack 对不存在的包返回 false")
	check(assets.active_pack == "zhu_xia", "被拒绝后 active_pack 保持不变（不静默降级）")

	# ③ 复位回 manifest 声明的默认包
	assets.reset_pack()
	check(assets.active_pack == "default", "reset_pack() 回到 default")
	check(str((assets.entries.get("unit.PU_TONG", {}) as Dictionary).get("path", "")).contains("art/default/"),
		"复位后条目路径回到 art/default/")

	# ④ 设置面板的皮肤下拉必须列出这两个包
	if world == null:
		world = (load("res://scenes/World.tscn") as PackedScene).instantiate() as Node3D
		add_child(world)
		await get_tree().process_frame
	var panel: Node = world.get("settings_panel")
	check(panel != null, "设置面板已构建（皮肤下拉的宿主）")
	if panel != null:
		var option: OptionButton = panel.get("_skin") as OptionButton
		check(option != null, "设置面板含皮肤下拉（SkinOption）")
		if option != null:
			var names: Array[String] = []
			for index: int in option.item_count:
				names.append(option.get_item_text(index))
			check(names.has("default") and names.has("zhu_xia"),
				"皮肤下拉列出 default 与 zhu_xia（实际：%s）" % ", ".join(names))
		check(str(panel.call("selected_skin")) == "default",
			"皮肤下拉初始选中 manifest 声明的 default（实际 %s）" % str(panel.call("selected_skin")))


# ---------------------------------------------------------------------------
# 端到端：真 view 下换皮
# ---------------------------------------------------------------------------

func _integration(session: Node) -> void:
	session.call("start_connection", TEST_PORT)
	var deadline: int = Time.get_ticks_msec() + 45000
	while not bool(session.call("supports", "newGame")) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check(bool(session.call("supports", "newGame")), "端到端：收到 newGame hello")
	if not bool(session.call("supports", "newGame")):
		session.call("shutdown")
		return

	session.call("request_new_game", {
		"playerFaction": "ZONG_MEN", "sectName": "青岚决天宗",
		"mapWidth": 22, "mapHeight": 16, "randomSeed": "864213", "difficultyId": "normal",
	})
	await _wait_view(session, 1)
	var view: Dictionary = session.get("current_view")
	check(not view.is_empty(), "端到端：拿到首个 view")
	if view.is_empty():
		session.call("shutdown")
		return

	if world == null:
		world = (load("res://scenes/World.tscn") as PackedScene).instantiate() as Node3D
		add_child(world)
	await get_tree().process_frame
	await get_tree().process_frame

	var rig: Node = session.get("camera_rig")
	var camera: Camera3D = rig.get("camera") as Camera3D
	var before_transform: Transform3D = camera.global_transform
	var before_size: float = camera.size
	var before_rotation: Vector3 = camera.rotation
	var before_view: String = var_to_str(view)
	var before_revision: int = int(session.get("view_revision"))
	var assets: AssetLibrary = session.get("assets") as AssetLibrary
	var before_texture: Texture2D = assets.resource_for("terrain.base.SPIRIT_PLAIN", "texture") as Texture2D
	var before_terrain_id: int = 0 if before_texture == null else before_texture.get_instance_id()

	# ① 换皮
	check(bool(world.call("apply_skin", "zhu_xia")), "端到端：apply_skin(\"zhu_xia\") 成功")
	await get_tree().process_frame
	await get_tree().process_frame

	check(str(world.call("current_skin")) == "zhu_xia",
		"端到端：World 报告当前皮肤为 zhu_xia（实际 %s）" % str(world.call("current_skin")))

	# ② view 逐字不变（换皮纯表现，绝不动数据）
	check(var_to_str(session.get("current_view")) == before_view,
		"端到端：换皮后 view 逐字不变")
	check(int(session.get("view_revision")) == before_revision,
		"端到端：换皮不触发 view 刷新（revision 不变，%d）" % before_revision)

	# ③ 相机铁律：transform / size / rotation 全不变
	check(camera.global_transform == before_transform, "端到端：换皮后相机 transform 不变")
	check(is_equal_approx(camera.size, before_size), "端到端：换皮后相机 size 不变（%.3f）" % camera.size)
	check(camera.rotation.is_equal_approx(before_rotation), "端到端：换皮后相机 rotation 不变")

	# ④ 换皮确实生效：地形贴图换成了另一个实例
	var after_texture: Texture2D = assets.resource_for("terrain.base.SPIRIT_PLAIN", "texture") as Texture2D
	var after_terrain_id: int = 0 if after_texture == null else after_texture.get_instance_id()
	check(after_terrain_id != before_terrain_id,
		"端到端：换皮后地形贴图实例已更换（证明真的重载，不是空转）")

	# ⑤ 切回默认包，相机依旧不动
	check(bool(world.call("apply_skin", "default")), "端到端：切回 default 成功")
	await get_tree().process_frame
	check(camera.global_transform == before_transform, "端到端：切回默认后相机 transform 仍不变")
	check(is_equal_approx(camera.size, before_size), "端到端：切回默认后相机 size 仍不变")
	check(str(world.call("current_skin")) == "default", "端到端：当前皮肤回到 default")

	session.call("shutdown")


func _wait_view(session: Node, revision: int) -> void:
	var deadline: int = Time.get_ticks_msec() + 20000
	while int(session.get("view_revision")) < revision and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	await get_tree().process_frame


func check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("R9_CLIENT_PASS: %s" % description)
	else:
		failures += 1
		printerr("R9_CLIENT_FAIL: %s" % description)
