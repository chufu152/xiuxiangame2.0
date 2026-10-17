extends Control

const FACTIONS: Array[String] = ["ZONG_MEN", "JIA_ZU", "GUO_JIA"]
const DIFFICULTIES: Array[String] = ["easy", "normal", "hard"]
## 客户端能流畅渲染的地块数上限（软限制，**不改服务端规则**）。
##
## 服务端 `map.setup` 允许到 128×128 / 16384 格，那是给批量工具留的上限；
## 客户端要为每格生成地形、网格线、边框、迷雾与小地图缩略点，几千格会让「开宗·展卷」
## 长时间停在「请求中」（实测 99×50 = 4950 格：服务端 CPU 破百秒、客户端内存 400MB+）。
## 超限时直接禁用开局并说明原因，好过让玩家干等。
const MAP_TILE_SOFT_LIMIT: int = 2000

var faction: OptionButton = null
var difficulty: OptionButton = null
var sect_name: LineEdit = null
var width_input: SpinBox = null
var height_input: SpinBox = null
var seed_input: LineEdit = null
var start_button: Button = null
var load_button: Button = null
var load_list: VBoxContainer = null
var load_status_label: Label = null
var status_label: Label = null
## `listSaves` 最近一次回包（`{saves:[…]}`）。
var saves_data: Dictionary = {}

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Session.camera_rig.set_active(false)
	_build_ui()
	Session.status_changed.connect(_update_status)
	Session.game_started.connect(_enter_world)
	Session.saves_received.connect(_on_saves_received)
	_update_status()
	# **R10 修复：生产入口从不拨号。** `run/main_scene` 是 `MainMenu.tscn`，而
	# `Session.start_connection()` 全仓只有 `client/tests/R*ClientTest.gd` 在调——
	# 于是正式启动的客户端状态栏永远停在初始值「尚未连接」，`supports(newGame)` 恒为 false，
	# 「开宗·展卷」永远是灰的（玩家看到的就是「无法开局」）。
	# `Session` 里「连不上就自己拉起本地服务端」的完整链路（`_on_connect_failed` →
	# `Launcher.launch` → `_await_server_ready`）早就写好了，只差这一次拨号。
	Session.start_connection()

func build_params() -> Dictionary:
	var params: Dictionary = {"playerFaction": FACTIONS[faction.selected], "sectName": sect_name.text.strip_edges(), "mapWidth": int(width_input.value), "mapHeight": int(height_input.value), "difficultyId": DIFFICULTIES[difficulty.selected]}
	var seed: String = seed_input.text.strip_edges()
	if not seed.is_empty():
		# 使用十进制字符串避免 JSON 浮点数吞掉 64 位种子精度。
		params["randomSeed"] = seed
	return params

func _update_status() -> void:
	if start_button == null:
		return
	var valid: bool = not sect_name.text.strip_edges().is_empty() and (seed_input.text.strip_edges().is_empty() or seed_input.text.strip_edges().is_valid_int())
	var tiles: int = int(width_input.value) * int(height_input.value)
	var too_large: bool = tiles > MAP_TILE_SOFT_LIMIT
	start_button.disabled = Session.busy or not Session.supports(Commands.NEW_GAME) or not valid or too_large
	if too_large:
		start_button.tooltip_text = "地图过大（%d×%d = %d 格 > %d），客户端会长时间卡在生成；建议 20×15" % [
			int(width_input.value), int(height_input.value), tiles, MAP_TILE_SOFT_LIMIT]
	elif start_button.disabled:
		start_button.tooltip_text = "需要服务端 hello 支持 newGame、非空名称与整数种子"
	else:
		start_button.tooltip_text = "向本地服务端请求开局（%d×%d = %d 格）" % [
			int(width_input.value), int(height_input.value), tiles]
	if load_button != null:
		load_button.disabled = Session.busy or not Session.supports(Commands.LOAD_GAME)
	status_label.text = Session.status


## R7 读档：先 `listSaves` 拉列表，再按槽位 `loadGame`。
## 读档成功后服务端回 view，`Session.game_started` 触发 `_enter_world`（与 newGame 同路径）。
func _toggle_load_list() -> void:
	if load_list.get_child_count() > 0:
		_clear_load_list()
		load_status_label.text = ""
		return
	load_status_label.text = "正在读取存档列表…"
	Session.request_list_saves()


func _on_saves_received(result: Dictionary) -> void:
	saves_data = result
	_clear_load_list()
	var saves: Array = result.get("saves", [])
	if saves.is_empty():
		load_status_label.text = "（暂无存档；对局中每 10 回合会自动存入槽 0）"
		return
	load_status_label.text = "共 %d 个存档，点选读取：" % saves.size()
	for entry: Variant in saves:
		var info: Dictionary = entry
		var slot: int = int(info.get("slotId", -1))
		var button: Button = Button.new()
		button.name = "LoadSlot_%d" % slot
		button.text = "槽 %d · 第 %d 回合 · %s（%s）" % [
			slot, int(info.get("turn", 0)), str(info.get("playerSectName", "")), str(info.get("savedAt", "")),
		]
		button.tooltip_text = "%s · %d 字节 · %s" % [
			str(info.get("factionType", "")), int(info.get("fileSize", 0)), str(info.get("filePath", "")),
		]
		button.pressed.connect(func() -> void: Session.request_load_game(slot))
		load_list.add_child(button)


func _clear_load_list() -> void:
	for child: Node in load_list.get_children():
		load_list.remove_child(child)
		child.queue_free()

func _enter_world() -> void:
	get_tree().change_scene_to_file("res://scenes/World.tscn")

func _build_ui() -> void:
	var background: ColorRect = ColorRect.new()
	background.color = Color("eeeadc")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var panel: PanelContainer = PanelContainer.new()
	panel.position = Vector2(470, 100)
	panel.custom_minimum_size = Vector2(660, 690)
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color("f8f5eb")
	style.border_color = Color("b6ad8b")
	style.set_border_width_all(2)
	style.content_margin_left = 40
	style.content_margin_right = 40
	style.content_margin_top = 28
	style.content_margin_bottom = 28
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 15)
	panel.add_child(column)
	_label(column, "修仙 4X · 宗门争霸", 32)
	_label(column, "R1 / 展开山河画卷", 19)
	column.add_child(HSeparator.new())
	_label(column, "流派", 16)
	faction = OptionButton.new()
	for title: String in ["宗门流 · 道统", "家族流 · 血脉", "国家流 · 扩张"]:
		faction.add_item(title)
	column.add_child(faction)
	_label(column, "难度", 16)
	difficulty = OptionButton.new()
	for title: String in ["初入仙途", "正道争锋", "群雄噬血"]:
		difficulty.add_item(title)
	difficulty.select(1)
	column.add_child(difficulty)
	_label(column, "宗门名称", 16)
	sect_name = LineEdit.new()
	sect_name.text = "青岚宗"
	sect_name.max_length = 40
	sect_name.text_changed.connect(func(_text: String) -> void: _update_status())
	column.add_child(sect_name)
	_label(column, "地图宽 × 高", 16)
	var dimensions: HBoxContainer = HBoxContainer.new()
	column.add_child(dimensions)
	width_input = SpinBox.new()
	height_input = SpinBox.new()
	for input: SpinBox in [width_input, height_input]:
		input.min_value = 1
		input.max_value = 100
		input.step = 1
		input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		dimensions.add_child(input)
	width_input.value = 20
	height_input.value = 15
	# 宽高变化立刻重算「能否开局」（过大时禁用）。必须在默认值设好之后再连：
	# 否则 `value_changed` 会在 `start_button` 尚未创建时触发 `_update_status`。
	width_input.value_changed.connect(func(_value: float) -> void: _update_status())
	height_input.value_changed.connect(func(_value: float) -> void: _update_status())
	_label(column, "随机种子（留空由服务端随机）", 16)
	seed_input = LineEdit.new()
	seed_input.placeholder_text = "可选 · 64 位整数"
	seed_input.text_changed.connect(func(_text: String) -> void: _update_status())
	column.add_child(seed_input)
	start_button = Button.new()
	start_button.text = "开宗 · 展卷"
	start_button.custom_minimum_size.y = 50
	start_button.pressed.connect(func() -> void: Session.request_new_game(build_params()))
	column.add_child(start_button)
	# R7：读档开局（listSaves → loadGame，成功后与 newGame 走同一条 `game_started` 路径）。
	load_button = Button.new()
	load_button.name = "LoadGameButton"
	load_button.text = "读取存档"
	load_button.tooltip_text = "列出本地存档槽（槽 0 = 每 10 回合自动存档）并读取"
	load_button.pressed.connect(func() -> void: _toggle_load_list())
	column.add_child(load_button)
	load_list = VBoxContainer.new()
	load_list.add_theme_constant_override("separation", 4)
	column.add_child(load_list)
	load_status_label = _label(column, "", 14)
	load_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label = _label(column, "", 15)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label(column, "正交 45° · 滚轮缩放 · 中 / 右键平移 · F5 资源热重读", 14)

func _label(parent: Node, text: String, font_size: int) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_color_override("font_color", Color("294e48"))
	label.add_theme_font_size_override("font_size", font_size)
	parent.add_child(label)
	return label
