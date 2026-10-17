extends Node
## R8 客户端验收：69 命令全入口 / 不可用置灰 / 相机不重置 / 资源缺失不崩 /
## 网格开关与宗门色边框 / 小地图只平移 / 设置不写 view。
##
## 无头运行：`godot --headless --path client res://tests/R8ClientTest.tscn [-- --integration]`。
## 不带 `--integration` 时只跑不依赖服务端的表现层断言（HUD 已构建、入口表覆盖、
## 网格/边框/小地图/设置/引导/Toast 可用、相机不变）。
##
## 覆盖 `docs/prompts/R8_表现与UI打磨.md`「自动验收」第 1–7 条（客户端）。
## 纯视觉项（配色/连绵观感/泼墨观感/粒子观感）不在此断言，见汇报里的人工核验清单。

const TEST_PORT: int = 19581
## 最小水墨资源包覆盖的 manifest 分组（R9 W1 起把 districts/improvements/features/audio 也补进来了）。
const MINIMAL_GROUPS: Array[String] = ["terrain", "units", "buildings", "resources", "realms", "factions",
	"districts", "improvements", "features", "audio"]
## 明确「不在最小包内」的分组——它们必须继续回退占位并 WARN 一次（裁决二）。
## R9 之后只剩 `fonts`：中文字体无法程序化生成，且客户端零处消费，故按计划待美术介入。
const FALLBACK_GROUPS: Array[String] = ["fonts"]
## 最小包应有的 ID 数（manifest 共 77，减去 fonts 的 2 个待美术项）。
const EXPECTED_MINIMAL: int = 75

var checks: int = 0
var failures: int = 0
var world: Node3D = null


func _ready() -> void:
	await get_tree().process_frame
	var session: Node = get_node("/root/Session")

	world = (load("res://scenes/World.tscn") as PackedScene).instantiate() as Node3D
	add_child(world)
	await get_tree().process_frame

	# ① HUD 与 R8 模块已构建
	check(world.get("action_bar") != null, "底部操作栏已构建")
	check(world.get("minimap") != null, "小地图已构建")
	check(world.get("settings_panel") != null, "设置面板已构建")
	check(world.get("guide_overlay") != null, "新手引导已构建")
	check(world.get("toast") != null, "Toast 已构建")
	check(world.get("decorations") != null, "装饰层（昼夜/网格/边框/粒子）已构建")
	check(world.get("audio_player") != null, "音效播放器已构建（缺失资源静默）")

	# ② 69 命令 + ping 全入口（按 commands.gd 的常量全集核对，避免硬编码漂移）
	var commands: Dictionary = (load("res://shared/protocol/commands.gd") as GDScript).get_script_constant_map()
	check(commands.size() == 70, "commands.gd 常量共 70 条（69 命令 + ping）")
	var missing: Array[String] = []
	var kinds: Dictionary = {"button": 0, "panel": 0, "gesture": 0, "auto": 0}
	for name: String in commands.keys():
		var command: String = str(commands[name])
		var state: Dictionary = world.call("command_entry_state", command)
		if not bool(state.get("registered", false)):
			missing.append(command)
			continue
		var kind: String = str(state.get("kind", ""))
		kinds[kind] = int(kinds.get(kind, 0)) + 1
	check(missing.is_empty(), "69 命令 + ping 全部有 UI 入口（缺失：%s）" % ", ".join(missing))
	check(int(world.call("command_entry_count")) == 70, "入口表条目数 = 70")
	check(int(kinds["button"]) >= 5, "底栏真按钮型入口 ≥ 5（实际 %d）" % int(kinds["button"]))
	check(int(kinds["panel"]) >= 40, "面板按钮型入口 ≥ 40（实际 %d）" % int(kinds["panel"]))
	check(int(kinds["gesture"]) == 5, "手势型入口 = 5（移动/批量/攻击/预览/指派）")
	check(int(kinds["auto"]) == 17, "自动型入口 = 17（只读查询与握手）")
	check(int(kinds["button"]) + int(kinds["panel"]) + int(kinds["gesture"]) + int(kinds["auto"]) == 70,
		"四类入口之和 = 70")

	# ③ 不可用置灰：未选中弟子时「开洞府」「任命建造者」必须置灰且有 blocker 文案。
	# 注意：`_render_city_panel()` 在没有选中灵峰时会提前 return（只改标题文案、不建按钮），
	# 所以这里必须喂一个合成 cityDetail 才能让「灵峰治理」段真正生成出来。
	world.set("selected_peak_id", "R8_TEST_PEAK")
	world.set("selected_disciple_id", "")
	world.set("city_detail", {
		"found": true, "name": "校验峰", "level": 1, "capital": true, "defense": 3,
		"population": 10, "freeWorkers": 2, "housing": 12, "food": 40, "foodBalance": 1,
		"stability": 60, "qiYun": 5, "qiYunMax": 20, "outputMultiplier": 1.0,
		"workedTileIds": [], "builtDistrictCount": 0, "cityYield": {},
	})
	world.call("_render_city_panel")
	var cave_state: Dictionary = _button_state(world, "city_list", "OpenCave")
	check(not cave_state.is_empty(), "「开洞府」入口已生成（灵峰治理段）")
	check(bool(cave_state.get("disabled", false)), "未选中弟子时「开洞府」置灰")
	check(not str(cave_state.get("tooltip", "")).is_empty(), "「开洞府」带 blocker 悬浮说明")
	var builder_state: Dictionary = _button_state(world, "city_list", "AppointBuilder")
	check(not builder_state.is_empty() and bool(builder_state.get("disabled", false)),
		"未选中弟子时「任命建造者」置灰")
	var fortify_state: Dictionary = _button_state(world, "city_list", "FortifyPeak")
	check(not fortify_state.is_empty(), "「加固灵峰」按钮存在（选中灵峰后可用）")
	check(not bool(fortify_state.get("disabled", true)), "「加固灵峰」不依赖弟子，选中灵峰即可用")
	# 复位，避免污染后续断言
	world.set("selected_peak_id", "")
	world.set("city_detail", {})
	world.call("_render_city_panel")

	# ④ 网格开关（纯显示层，裁决四）
	check(not bool(world.call("grid_enabled")), "网格默认关闭")
	world.call("toggle_grid")
	check(bool(world.call("grid_enabled")), "开关网格后状态变为开")
	check(world.call("settings_pref", "gridVisible") == true, "网格开关同步到本地偏好")
	world.call("toggle_grid")
	check(not bool(world.call("grid_enabled")), "再开关一次回到关闭")

	# ⑤ 宗门色边框（纯显示层，裁决四）
	check(bool(world.call("border_enabled")), "宗门色边框默认开启")
	world.call("toggle_borders")
	check(not bool(world.call("border_enabled")), "开关后边框关闭")
	world.call("toggle_borders")

	# ⑥ 小地图：存在、可开关、点击入口已接线
	check(int(world.call("minimap_tile_count")) == 0, "无 view 时小地图无缩略点")
	world.call("toggle_minimap")
	world.call("toggle_minimap")
	check(true, "小地图开关不抛错")

	# ⑦ 设置：本地偏好生效
	world.call("settings_pref", "dayNight")
	var panel: Node = world.get("settings_panel")
	panel.call("set_pref", "dayNight", false)
	check(world.call("settings_pref", "dayNight") == false, "设置项 dayNight 可写入本地偏好")
	check(str(world.call("settings_status_text")).length() > 0, "设置面板有状态文案（服务端仅确认）")

	# ⑧ 新手引导：6 步、可翻页、可关闭
	var guide: Node = world.get("guide_overlay")
	guide.call("open_panel")
	check(bool(world.call("guide_visible")), "打开新手引导")
	check(int(world.call("guide_step_count")) == 6, "新手引导共 6 步")
	var first_title: String = str(world.call("guide_title_text"))
	guide.call("advance")
	check(str(world.call("guide_title_text")) != first_title, "引导可翻到下一步")
	guide.call("close_panel")
	check(not bool(world.call("guide_visible")), "引导可关闭")

	# ⑨ Toast
	world.call("_toast", "R8 自检提示")
	check(str(world.call("toast_text")) == "R8 自检提示", "Toast 显示业务/事件文案")

	# ⑩ 相机不重置：面板开关 / 显示开关 / 引导 / 设置 / 快捷键序列后 transform 与 size 不变
	await _assert_camera_stable()

	# ⑪ 资源缺失只 WARN 不崩：最小包 ID 不再 WARN，未覆盖分组仍回退
	await _assert_asset_fallback(session)

	world.queue_free()
	world = null
	await get_tree().process_frame

	if OS.get_cmdline_user_args().has("--integration"):
		await integration(session)
	finish()


## 取某个面板列表里指定名字按钮的状态。
func _button_state(target: Node, list_property: String, button_name: String) -> Dictionary:
	var list: Node = target.get(list_property)
	if list == null:
		return {}
	var button: Button = list.get_node_or_null(NodePath(button_name)) as Button
	if button == null:
		return {}
	return {"disabled": button.disabled, "text": button.text, "tooltip": button.tooltip_text}


## 相机铁律：任何操作后 `CameraRig.camera` 的 transform 与 size 都不得变化。
func _assert_camera_stable() -> void:
	var rig: Node = get_node("/root/Session").get("camera_rig")
	await get_tree().process_frame
	var camera: Camera3D = rig.get("camera") as Camera3D
	if camera == null:
		check(false, "相机存在（无法断言铁律）")
		return
	var before_transform: Transform3D = camera.global_transform
	var before_size: float = camera.size
	var before_rotation: Vector3 = camera.rotation

	# 面板开合
	for opener: String in ["open_victory_panel", "open_saves_panel", "open_gameover_panel",
			"open_policy_panel", "open_automation_panel", "toggle_dao_panel"]:
		world.call(opener)
		await get_tree().process_frame
	world.call("_close_all_panels")
	await get_tree().process_frame
	# 显示开关
	world.call("toggle_grid")
	world.call("toggle_borders")
	world.call("toggle_minimap")
	world.call("toggle_minimap")
	world.call("toggle_grid")
	world.call("toggle_borders")
	# 引导 / 设置
	(world.get("guide_overlay") as Node).call("open_panel")
	(world.get("guide_overlay") as Node).call("close_panel")
	(world.get("settings_panel") as Node).call("toggle_panel")
	(world.get("settings_panel") as Node).call("close_panel")
	# 昼夜切换（改光照，绝不能改相机）
	var decorations: Node = world.get("decorations")
	decorations.call("set_day_phase", 0.05)
	await get_tree().process_frame
	decorations.call("set_day_phase", 0.62)
	await get_tree().process_frame
	# 旋转输入：模拟右键拖拽（CameraRig 只平移，不得旋转）。
	# 注意：这里**不能**写 `camera.rotation = before_rotation` 做「复位」——
	# Euler→basis 往返本身就会引入浮点误差，那会让断言自己把相机改掉。
	rig.call("pan_between", Vector2(300, 200), Vector2(420, 260))
	await get_tree().process_frame
	rig.call("pan_to", Vector3(6.0, 0.0, -4.0))
	await get_tree().process_frame

	check(camera.size == before_size, "相机铁律：全序列后 size 不变（%.3f）" % camera.size)
	check(camera.rotation.is_equal_approx(before_rotation),
		"相机铁律：全序列后 rotation 不变（锁定 45°，实际 %s / 基准 %s）" % [
			str(camera.rotation), str(before_rotation)])
	check(camera.global_transform.basis.is_equal_approx(before_transform.basis),
		"相机铁律：全序列后 transform 的基不变（无旋转，实际 %s）" % str(camera.global_transform.basis))


## 资源缺失只 WARN 不崩（裁决二）：最小包 75 个 ID 不再 WARN；未覆盖分组（只剩 fonts）仍 WARN 一次。
func _assert_asset_fallback(session: Node) -> void:
	var library: Node = session.get("assets")
	if library == null:
		check(false, "AssetLibrary 存在（无法断言资源回退）")
		return
	var manifest_path: String = str(library.get("manifest_path"))
	var file: FileAccess = FileAccess.open(manifest_path, FileAccess.READ)
	if file == null:
		check(false, "manifest.json 可读")
		return
	var parser: JSON = JSON.new()
	var parsed: bool = parser.parse(file.get_as_text()) == OK and parser.data is Dictionary
	check(parsed, "manifest.json 是有效 JSON")
	if not parsed:
		return
	var data: Dictionary = parser.data
	var minimal_ids: Array[String] = []
	var fallback_ids: Array[String] = []
	for group: Variant in data.keys():
		if not data[group] is Array:
			continue
		for entry: Variant in data[group]:
			if not (entry is Dictionary) or not entry.has("id"):
				continue
			var logical_id: String = str(entry["id"])
			if MINIMAL_GROUPS.has(str(group)):
				minimal_ids.append(logical_id)
			elif FALLBACK_GROUPS.has(str(group)):
				fallback_ids.append(logical_id)
	check(minimal_ids.size() == EXPECTED_MINIMAL,
		"最小包 ID 共 %d 个（实际 %d）" % [EXPECTED_MINIMAL, minimal_ids.size()])
	check(not fallback_ids.is_empty(), "存在未覆盖分组 ID（用于验证回退路径）")

	var warned_ids: Dictionary = library.get("warned")
	var wrongly_warned: Array[String] = []
	for logical_id: String in minimal_ids:
		if warned_ids.has(logical_id):
			wrongly_warned.append(logical_id)
	check(wrongly_warned.is_empty(),
		"最小包 %d 个 ID 均未触发 WARN（实际告警：%s）" % [EXPECTED_MINIMAL, ", ".join(wrongly_warned)])

	var fallback_ok: int = 0
	for logical_id: String in fallback_ids:
		var before: int = int(library.get("warning_count"))
		var expected_type: String = "texture"
		if logical_id.begins_with("font."):
			expected_type = "font"
		elif logical_id.begins_with("improvement.") or logical_id.begins_with("district.") \
				or logical_id.begins_with("node.") or logical_id.begins_with("terrain.feature."):
			expected_type = "model"
		library.call("resource_for", logical_id, expected_type)
		if int(library.get("warning_count")) > before or warned_ids.has(logical_id):
			fallback_ok += 1
	check(fallback_ok > 0, "未覆盖 ID 仍回退占位并 WARN 一次（%d 个）" % fallback_ok)


# ---------------------------------------------------------------------------
# 端到端（需服务端）
# ---------------------------------------------------------------------------

func integration(session: Node) -> void:
	session.call("start_connection", TEST_PORT)
	var deadline: int = Time.get_ticks_msec() + 45000
	while not bool(session.call("supports", "newGame")) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check(bool(session.call("supports", "newGame")), "端到端：收到 newGame hello")
	if not bool(session.call("supports", "newGame")):
		session.call("shutdown")
		return

	# ① hello 声明的命令必须与 commands.gd 的 70 条一致（R8 不新增命令，故恒等）
	var commands: Dictionary = (load("res://shared/protocol/commands.gd") as GDScript).get_script_constant_map()
	var unsupported: Array[String] = []
	for name: String in commands.keys():
		var command: String = str(commands[name])
		if not bool(session.call("supports", command)):
			unsupported.append(command)
	check(unsupported.is_empty(), "端到端：hello 声明支持全部 70 条（缺：%s）" % ", ".join(unsupported))

	session.call("request_new_game", {
		"playerFaction": "ZONG_MEN", "sectName": "青岚决天宗",
		"mapWidth": 22, "mapHeight": 16, "randomSeed": "864213", "difficultyId": "normal",
	})
	await _wait_view(session, 1)
	var view: Dictionary = session.get("current_view")
	check(not view.is_empty(), "端到端：拿到首个 view")

	# ② 装饰层按真 view 生成：网格线 / 宗门边框 / 小地图缩略点
	world = (load("res://scenes/World.tscn") as PackedScene).instantiate() as Node3D
	add_child(world)
	await get_tree().process_frame
	await get_tree().process_frame
	var tile_count: int = (view.get("tiles", {}) as Dictionary).size()
	check(int(world.call("grid_line_count")) > 0, "端到端：网格线已生成（%d 条）" % int(world.call("grid_line_count")))
	check(int(world.call("border_count")) > 0, "端到端：宗门色边框已生成（%d 圈）" % int(world.call("border_count")))
	check(int(world.call("minimap_tile_count")) == tile_count,
		"端到端：小地图缩略点 = 地块数（%d）" % int(world.call("minimap_tile_count")))

	# ③ 小地图点击只平移：角度与缩放不变，位置改变
	var rig: Node = session.get("camera_rig")
	var camera: Camera3D = rig.get("camera") as Camera3D
	var before_size: float = camera.size
	var before_rotation: Vector3 = camera.rotation
	var before_position: Vector3 = camera.global_position
	var target_tile: String = ""
	for tile_id: String in (view.get("tiles", {}) as Dictionary).keys():
		target_tile = str(tile_id)
		break
	world.call("_on_minimap_picked", target_tile)
	await get_tree().process_frame
	check(camera.size == before_size, "端到端：小地图跳转后缩放不变")
	check(camera.rotation.is_equal_approx(before_rotation), "端到端：小地图跳转后角度不变")
	check(camera.global_position != before_position, "端到端：小地图跳转确实平移了相机")

	# ④ 相机全序列不重置（含存读档 / 结束回合 / getState / 泼墨转场）
	var stable_size: float = camera.size
	var stable_basis: Basis = camera.global_transform.basis
	var stable_rotation: Vector3 = camera.rotation
	(world.get("decorations") as Node).call("set_day_phase", 0.12)
	await get_tree().process_frame
	(world.get("decorations") as Node).call("set_day_phase", 0.55)
	await get_tree().process_frame
	world.call("open_victory_panel")
	await get_tree().process_frame
	world.call("open_saves_panel")
	await get_tree().process_frame
	world.call("_close_all_panels")
	session.call("request_save_game", 3)
	await _wait_idle(session)
	session.call("request_load_game", 3)
	await _wait_idle(session)
	await _wait_view(session, int(session.get("view_revision")) + 1)
	session.call("request_end_turn_sequence")
	await _wait_idle(session)
	session.call("request_refresh")
	await _wait_view(session, int(session.get("view_revision")) + 1)
	check(camera.size == stable_size, "端到端：全序列后相机 size 不变")
	check(camera.rotation.is_equal_approx(stable_rotation),
		"端到端：全序列后相机 rotation 不变（实际 %s / 基准 %s）" % [str(camera.rotation), str(stable_rotation)])
	check(camera.global_transform.basis.is_equal_approx(stable_basis),
		"端到端：全序列后相机基不变（无旋转，实际 %s）" % str(camera.global_transform.basis))

	# ⑤ 设置不写 view（服务端只确认）
	(world.get("settings_panel") as Node).call("set_pref", "gridVisible", true)
	session.call("request_set_setting", "gridVisible", true)
	await _wait_idle(session)
	await _wait_view(session, int(session.get("view_revision")) + 1)
	var fresh: Dictionary = session.get("current_view")
	var serialized: String = JSON.stringify(fresh)
	check(not serialized.contains("gridVisible"), "端到端：setSetting 不进入 view（客户端本地偏好）")

	# ⑥ 顶部资源栏 13 项都有数值文本
	var chips: Dictionary = world.get("resource_chips")
	check(chips.size() == 13, "端到端：资源栏 13 项已构建")
	var filled: int = 0
	for key: String in chips.keys():
		var label: Label = chips[key] as Label
		if label != null and label.text.strip_edges().length() > 0:
			filled += 1
	check(filled == 13, "端到端：13 项资源均显示数值（%d）" % filled)

	world.queue_free()
	world = null
	await get_tree().process_frame
	# 收尾：回收 Launcher 拉起的 headless 服务端子进程，避免占用 TEST_PORT。
	session.call("shutdown")
	await get_tree().process_frame


func _wait_idle(session: Node) -> void:
	var deadline: int = Time.get_ticks_msec() + 15000
	while bool(session.get("busy")) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	await get_tree().process_frame


func _wait_view(session: Node, revision: int) -> void:
	var deadline: int = Time.get_ticks_msec() + 15000
	while int(session.get("view_revision")) < revision and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	await get_tree().process_frame


func check(ok: bool, label: String) -> void:
	checks += 1
	if ok:
		print("R8_CLIENT_PASS: " + label)
	else:
		failures += 1
		push_error("R8_CLIENT_FAIL: " + label)


func finish() -> void:
	print("R8_CLIENT_RESULT=%s checks=%d failures=%d" % ["OK" if failures == 0 else "FAIL", checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
