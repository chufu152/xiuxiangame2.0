class_name GuideOverlay
extends CanvasLayer
## 新手引导（R8 任务 4）：首次进入时按步展示操作要点。
##
## 纯文案 + 分步翻页，**不阻塞任何协议交互**（不拦截输入、不改相机）；
## 文案只描述已有入口，不引入任何新玩法概念。

signal finished()

## 每步：{ "title": 标题, "body": 正文 }
const STEPS: Array = [
	{"title": "第一步 · 看地图", "body": "左键点地块看详情；滚轮缩放、中键/右键平移。相机锁定正交 45°，不可旋转。"},
	{"title": "第二步 · 选弟子", "body": "左键点己方弟子 → 青绿高亮为可移动格，点高亮格即移动；Shift+点选可多选后批量移动。"},
	{"title": "第三步 · 打与守", "body": "选中弟子后悬停赭红格看胜率预览，点击即攻击；弟子详情里可转职、晋升、传送、驻守、撤退。"},
	{"title": "第四步 · 建与治", "body": "点己方灵峰开城市面板：开峰、建殿、开洞府、加固、区域选址、指派劳力、改良修缮。"},
	{"title": "第五步 · 势力与胜负", "body": "顶栏「胜负」看三路线进度与择定；「存档」存读档；「结局」随时查胜负与覆灭。"},
	{"title": "第六步 · 常用键", "body": "空格/End 结束回合；G 开关网格；B 开关宗门色边框；M 小地图；Esc 关面板；F1 重看引导。"},
]

const PANEL_WIDTH: float = 520.0
const PANEL_HEIGHT: float = 260.0

var panel: PanelContainer = null
var title_label: Label = null
var body_label: Label = null
var step_label: Label = null
var next_button: Button = null
var open: bool = false
var index: int = 0
var completed: bool = false


func setup() -> void:
	name = "GuideOverlay"
	layer = 6
	visible = false

	panel = PanelContainer.new()
	panel.name = "GuideBox"
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -PANEL_WIDTH * 0.5
	panel.offset_right = PANEL_WIDTH * 0.5
	panel.offset_top = -PANEL_HEIGHT * 0.5
	panel.offset_bottom = PANEL_HEIGHT * 0.5
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.96, 0.94, 0.88, 0.98)
	style.border_color = Color("c9a227")
	style.border_width_left = 3
	style.border_width_right = 3
	style.border_width_top = 3
	style.border_width_bottom = 3
	style.content_margin_left = 20.0
	style.content_margin_right = 20.0
	style.content_margin_top = 16.0
	style.content_margin_bottom = 16.0
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)

	step_label = Label.new()
	step_label.name = "GuideStep"
	step_label.add_theme_font_size_override("font_size", 12)
	step_label.add_theme_color_override("font_color", Color("8a6a3f"))
	column.add_child(step_label)

	title_label = Label.new()
	title_label.name = "GuideTitle"
	title_label.add_theme_font_size_override("font_size", 20)
	title_label.add_theme_color_override("font_color", Color("294e48"))
	column.add_child(title_label)

	body_label = Label.new()
	body_label.name = "GuideBody"
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body_label.add_theme_font_size_override("font_size", 14)
	body_label.add_theme_color_override("font_color", Color("3f4a45"))
	body_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(body_label)

	var buttons: HBoxContainer = HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	column.add_child(buttons)

	next_button = Button.new()
	next_button.name = "GuideNext"
	next_button.text = "下一步"
	next_button.pressed.connect(func() -> void: advance())
	buttons.add_child(next_button)

	var skip: Button = Button.new()
	skip.name = "GuideSkip"
	skip.text = "跳过引导"
	skip.pressed.connect(func() -> void: close_panel())
	buttons.add_child(skip)

	_render_step()


func _render_step() -> void:
	if index < 0 or index >= STEPS.size():
		return
	var step: Dictionary = STEPS[index]
	step_label.text = "引导 %d / %d" % [index + 1, STEPS.size()]
	title_label.text = str(step.get("title", ""))
	body_label.text = str(step.get("body", ""))
	next_button.text = "完成" if index == STEPS.size() - 1 else "下一步"


func open_panel() -> void:
	visible = true
	open = true
	index = 0
	_render_step()


func close_panel() -> void:
	visible = false
	open = false
	completed = true
	finished.emit()


func advance() -> void:
	if index >= STEPS.size() - 1:
		close_panel()
		return
	index += 1
	_render_step()


func step_count() -> int:
	return STEPS.size()


func current_index() -> int:
	return index


func title_text() -> String:
	return "" if title_label == null else title_label.text


func body_text() -> String:
	return "" if body_label == null else body_label.text
