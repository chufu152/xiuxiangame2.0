extends Control

const FACTIONS: Array[String] = ["ZONG_MEN", "JIA_ZU", "GUO_JIA"]
const DIFFICULTIES: Array[String] = ["easy", "normal", "hard"]

var faction: OptionButton = null
var difficulty: OptionButton = null
var sect_name: LineEdit = null
var width_input: SpinBox = null
var height_input: SpinBox = null
var seed_input: LineEdit = null
var start_button: Button = null
var status_label: Label = null

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Session.camera_rig.set_active(false)
	_build_ui()
	Session.status_changed.connect(_update_status)
	Session.game_started.connect(_enter_world)
	_update_status()

func build_params() -> Dictionary:
	var params: Dictionary = {"playerFaction": FACTIONS[faction.selected], "sectName": sect_name.text.strip_edges(), "mapWidth": int(width_input.value), "mapHeight": int(height_input.value), "difficultyId": DIFFICULTIES[difficulty.selected]}
	var seed: String = seed_input.text.strip_edges()
	if not seed.is_empty():
		# 使用十进制字符串避免 JSON 浮点数吞掉 64 位种子精度。
		params["randomSeed"] = seed
	return params

func _update_status() -> void:
	var valid: bool = not sect_name.text.strip_edges().is_empty() and (seed_input.text.strip_edges().is_empty() or seed_input.text.strip_edges().is_valid_int())
	start_button.disabled = Session.busy or not Session.supports(Commands.NEW_GAME) or not valid
	start_button.tooltip_text = "需要服务端 hello 支持 newGame、非空名称与整数种子" if start_button.disabled else "向本地服务端请求开局"
	status_label.text = Session.status

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
