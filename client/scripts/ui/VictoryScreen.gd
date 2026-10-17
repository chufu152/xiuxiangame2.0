class_name VictoryScreen
extends CanvasLayer
## 胜利结算界面（对齐参考图「仙途终焉：九天胜境」）。
##
## 全屏云海仙山（程序化 `_draw`，不加载任何图片）→ 中央金色「胜利」+ 朱印 →
## 三路线徽记 → 卷轴「最终结算」双列 12 项 → 底部三枚药丸。
##
## 数据来源（全部真实）：
##   章节/回合      ← `view.metadata.turn` 与 `victory.maxTurns`
##   三路线进度     ← `queryVictoryProgress` 的 `routes[]`（`ratio` / `achieved` / `summary`）
##   最终结算 12 项 ← 玩家宗门 `powerLevel` / 灵峰数 / 弟子数 / `unlockedDaoIds` /
##                     `cultivationProgress` 之和 / 13 项资源 / 回合数
##   胜负状态       ← `queryGameOver` 的 `gameOver` / `winType` / `winnerSectId`

signal restart_requested()
signal map_requested()
signal saves_requested()
signal close_requested()

const CARD_WIDTH: float = 900.0
const CARD_HEIGHT: float = 244.0
const EMBLEM_SIZE: float = 78.0

## 三路线：(route id, 显示名, 副标题, 徽记字)。
const ROUTES: Array = [
	["ZONG_MEN", "宗门路线", "一统九天，道法无边", "宗"],
	["JIA_ZU", "家族路线", "传承千载，血脉永续", "族"],
	["GUO_JIA", "国家路线", "万国来朝，山河共主", "国"],
]

var backdrop: Control = null
var chapter_label: Label = null
var subtitle_label: Label = null
var big_title: Label = null
var route_row: HBoxContainer = null
var card: PanelContainer = null
var left_column: VBoxContainer = null
var right_column: VBoxContainer = null
var footer_note: Label = null
var button_row: HBoxContainer = null


func setup() -> void:
	layer = 8
	visible = false

	backdrop = VictoryBackdrop.new()
	backdrop.name = "Backdrop"
	backdrop.anchor_right = 1.0
	backdrop.anchor_bottom = 1.0
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)

	_build_header()
	_build_emblems()
	_build_card()
	_build_buttons()


# ---------------------------------------------------------------------------
# 顶部：章节 + 大字 + 副题
# ---------------------------------------------------------------------------

func _build_header() -> void:
	var block: VBoxContainer = VBoxContainer.new()
	block.name = "Header"
	block.position = Vector2(26, 20)
	block.add_theme_constant_override("separation", 2)
	add_child(block)
	chapter_label = Label.new()
	chapter_label.text = "第 1 章 · 终焉之战"
	chapter_label.add_theme_font_size_override("font_size", 14)
	chapter_label.add_theme_color_override("font_color", Color(0.16, 0.22, 0.21, 0.92))
	block.add_child(chapter_label)
	subtitle_label = Label.new()
	subtitle_label.text = "终局 · 仙途长明"
	subtitle_label.add_theme_font_size_override("font_size", 11)
	subtitle_label.add_theme_color_override("font_color", Color(0.28, 0.34, 0.33, 0.72))
	block.add_child(subtitle_label)

	# 中央金色「胜利」：用 4 层错位描边模拟烫金浮雕。
	var title_holder: Control = Control.new()
	title_holder.name = "BigTitleHolder"
	title_holder.anchor_left = 0.5
	title_holder.anchor_right = 0.5
	title_holder.offset_left = -220.0
	title_holder.offset_right = 220.0
	title_holder.offset_top = 84.0
	title_holder.offset_bottom = 246.0
	add_child(title_holder)
	big_title = Label.new()
	big_title.text = "胜 利"
	big_title.add_theme_font_size_override("font_size", 116)
	big_title.add_theme_color_override("font_color", Color("e8c96a"))
	big_title.add_theme_color_override("font_shadow_color", Color(0.36, 0.27, 0.10, 0.85))
	big_title.add_theme_constant_override("shadow_offset_x", 3)
	big_title.add_theme_constant_override("shadow_offset_y", 4)
	big_title.add_theme_constant_override("shadow_outline_size", 10)
	big_title.add_theme_color_override("font_outline_color", Color(0.29, 0.22, 0.09, 0.90))
	big_title.add_theme_constant_override("outline_size", 3)
	big_title.anchor_right = 1.0
	big_title.anchor_bottom = 1.0
	big_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	big_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_holder.add_child(big_title)

	var seal: PanelContainer = PanelContainer.new()
	seal.name = "Seal"
	seal.anchor_left = 1.0
	seal.anchor_right = 1.0
	seal.offset_left = -34.0
	seal.offset_right = -2.0
	seal.offset_top = 26.0
	seal.offset_bottom = 58.0
	seal.add_theme_stylebox_override("panel", UiTheme.seal(UiTheme.CINNABAR, Color(0, 0, 0, 0)))
	title_holder.add_child(seal)
	var seal_text: Label = Label.new()
	seal_text.text = "胜"
	seal_text.add_theme_font_size_override("font_size", 15)
	seal_text.add_theme_color_override("font_color", UiTheme.PAPER)
	seal_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	seal_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	seal.add_child(seal_text)

	var motto: Label = Label.new()
	motto.name = "Motto"
	motto.text = "—— 道统归一 · 万灵共荣 ——"
	motto.anchor_left = 0.5
	motto.anchor_right = 0.5
	motto.offset_left = -220.0
	motto.offset_right = 220.0
	motto.offset_top = 250.0
	motto.offset_bottom = 276.0
	motto.add_theme_font_size_override("font_size", 15)
	motto.add_theme_color_override("font_color", Color(0.20, 0.26, 0.25, 0.92))
	motto.add_theme_color_override("font_shadow_color", Color(1.0, 1.0, 1.0, 0.75))
	motto.add_theme_constant_override("shadow_offset_x", 0)
	motto.add_theme_constant_override("shadow_offset_y", 0)
	motto.add_theme_constant_override("shadow_outline_size", 8)
	motto.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(motto)

	# 右侧竖排落款
	var side: Label = UiTheme.vertical_title("青云之上 万象归心", 16)
	side.name = "SideNote"
	side.anchor_left = 1.0
	side.anchor_right = 1.0
	side.anchor_top = 0.0
	side.offset_left = -62.0
	side.offset_right = -20.0
	side.offset_top = 380.0
	side.offset_bottom = 660.0
	side.add_theme_color_override("font_color", Color(0.22, 0.28, 0.27, 0.78))
	side.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(side)


# ---------------------------------------------------------------------------
# 三路线徽记
# ---------------------------------------------------------------------------

func _build_emblems() -> void:
	route_row = HBoxContainer.new()
	route_row.name = "Routes"
	route_row.anchor_left = 0.5
	route_row.anchor_right = 0.5
	route_row.offset_left = -330.0
	route_row.offset_right = 330.0
	route_row.offset_top = 286.0
	route_row.offset_bottom = 410.0
	route_row.alignment = BoxContainer.ALIGNMENT_CENTER
	route_row.add_theme_constant_override("separation", 56)
	add_child(route_row)


func _refresh_emblems(routes: Dictionary, active_route: String) -> void:
	for child: Node in route_row.get_children():
		route_row.remove_child(child)
		child.queue_free()
	for entry: Array in ROUTES:
		var route_id: String = str(entry[0])
		var progress: Dictionary = routes.get(route_id, {})
		var achieved: bool = bool(progress.get("achieved", false))
		var active: bool = route_id == active_route
		var column: VBoxContainer = VBoxContainer.new()
		column.add_theme_constant_override("separation", 3)
		route_row.add_child(column)

		var emblem: PanelContainer = PanelContainer.new()
		emblem.custom_minimum_size = Vector2(EMBLEM_SIZE, EMBLEM_SIZE)
		emblem.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		var style: StyleBoxFlat = StyleBoxFlat.new()
		if active:
			style.bg_color = Color(0.918, 0.847, 0.659, 0.98)
			style.border_color = Color(UiTheme.GOLD.r, UiTheme.GOLD.g, UiTheme.GOLD.b, 0.95)
		else:
			# 未解锁徽记原本是半透明灰，正好压在中央仙山的暗面上，糊成一团。
			# 改成不透明的浅灰玉色 + 明确描边，保证在任何背景上都读得出轮廓。
			style.bg_color = Color(0.86, 0.88, 0.85, 0.96)
			style.border_color = Color(0.42, 0.48, 0.47, 0.90)
		style.set_border_width_all(2)
		style.set_corner_radius_all(int(EMBLEM_SIZE * 0.5))
		emblem.add_theme_stylebox_override("panel", style)
		column.add_child(emblem)
		var glyph: Label = Label.new()
		glyph.text = str(entry[3])
		glyph.add_theme_font_size_override("font_size", 30)
		glyph.add_theme_color_override("font_color", UiTheme.JADE_DEEP if active else Color(0.32, 0.36, 0.35, 0.85))
		glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		emblem.add_child(glyph)

		var name_label: Label = Label.new()
		name_label.text = str(entry[1])
		name_label.add_theme_font_size_override("font_size", 13)
		name_label.add_theme_color_override("font_color",
			Color(0.20, 0.26, 0.25, 0.95) if active else Color(0.34, 0.38, 0.37, 0.72))
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.add_theme_color_override("font_shadow_color", Color(1.0, 1.0, 1.0, 0.85))
		name_label.add_theme_constant_override("shadow_offset_x", 0)
		name_label.add_theme_constant_override("shadow_offset_y", 0)
		name_label.add_theme_constant_override("shadow_outline_size", 4)
		column.add_child(name_label)

		var sub: Label = Label.new()
		if active:
			sub.text = str(entry[2])
		elif achieved:
			sub.text = "已达成"
		else:
			sub.text = "未解锁"
		sub.add_theme_font_size_override("font_size", 10)
		sub.add_theme_color_override("font_color", Color(0.36, 0.40, 0.39, 0.70))
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sub.add_theme_color_override("font_shadow_color", Color(1.0, 1.0, 1.0, 0.85))
		sub.add_theme_constant_override("shadow_offset_x", 0)
		sub.add_theme_constant_override("shadow_offset_y", 0)
		sub.add_theme_constant_override("shadow_outline_size", 4)
		column.add_child(sub)


# ---------------------------------------------------------------------------
# 最终结算卷轴
# ---------------------------------------------------------------------------

func _build_card() -> void:
	card = PanelContainer.new()
	card.name = "FinalCard"
	card.anchor_left = 0.5
	card.anchor_right = 0.5
	card.anchor_top = 0.5
	card.anchor_bottom = 0.5
	card.offset_left = -CARD_WIDTH * 0.5
	card.offset_right = CARD_WIDTH * 0.5
	# 卡片顶边 452：题诗到 276、三枚路线徽记到 410，留 42px 喘口气再压卷轴，
	# 否则「未解锁」那行小字会被卷轴上沿切掉一半。
	card.offset_top = 2.0
	card.offset_bottom = 2.0 + CARD_HEIGHT
	card.add_theme_stylebox_override("panel", UiTheme.scroll_paper(0.955, 6))
	add_child(card)

	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	card.add_child(column)

	var band: PanelContainer = PanelContainer.new()
	band.custom_minimum_size = Vector2(200, 26)
	band.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var band_style: StyleBoxFlat = UiTheme.title_band(UiTheme.JADE_DEEP)
	band_style.set_corner_radius_all(3)
	band.add_theme_stylebox_override("panel", band_style)
	column.add_child(band)
	var band_label: Label = Label.new()
	band_label.text = "◈ 最终结算"
	band_label.add_theme_font_size_override("font_size", 13)
	band_label.add_theme_color_override("font_color", UiTheme.PAPER)
	band_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	band.add_child(band_label)

	var columns: HBoxContainer = HBoxContainer.new()
	columns.add_theme_constant_override("separation", 24)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(columns)
	left_column = VBoxContainer.new()
	left_column.name = "Left"
	left_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_column.add_theme_constant_override("separation", 3)
	columns.add_child(left_column)
	right_column = VBoxContainer.new()
	right_column.name = "Right"
	right_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_column.add_theme_constant_override("separation", 3)
	columns.add_child(right_column)

	column.add_child(UiTheme.ornament_divider())
	footer_note = Label.new()
	footer_note.text = "仙路漫漫，终得大道"
	footer_note.add_theme_font_size_override("font_size", 11)
	footer_note.add_theme_color_override("font_color", UiTheme.INK_FAINT)
	footer_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(footer_note)


# ---------------------------------------------------------------------------
# 底部三枚药丸
# ---------------------------------------------------------------------------

func _build_buttons() -> void:
	button_row = HBoxContainer.new()
	button_row.name = "Buttons"
	button_row.anchor_left = 0.5
	button_row.anchor_right = 0.5
	button_row.anchor_top = 1.0
	button_row.anchor_bottom = 1.0
	button_row.offset_left = -270.0
	button_row.offset_right = 270.0
	button_row.offset_top = -66.0
	button_row.offset_bottom = -26.0
	button_row.alignment = BoxContainer.ALIGNMENT_CENTER
	button_row.add_theme_constant_override("separation", 22)
	add_child(button_row)

	var entries: Array = [
		["RestartVictory", "重新开始", restart_requested],
		["MapVictory", "查看地图", map_requested],
		["SavesVictory", "读取存档", saves_requested],
	]
	for entry: Array in entries:
		var button: Button = Button.new()
		button.name = str(entry[0])
		button.text = str(entry[1])
		button.custom_minimum_size = Vector2(160, 40)
		button.add_theme_font_size_override("font_size", 14)
		var style: StyleBoxFlat = UiTheme.pill(UiTheme.JADE_DEEP)
		style.set_corner_radius_all(20)
		style.content_margin_left = 22.0
		style.content_margin_right = 22.0
		button.add_theme_stylebox_override("normal", style)
		button.add_theme_stylebox_override("hover", style)
		button.add_theme_stylebox_override("pressed", style)
		button.add_theme_color_override("font_color", UiTheme.PAPER)
		var sig: Signal = entry[2] as Signal
		button.pressed.connect(func() -> void: sig.emit())
		button_row.add_child(button)


# ---------------------------------------------------------------------------
# 对外接口
# ---------------------------------------------------------------------------

## `data`：
##   {chapter, chapterNote, routes:{routeId:progress}, activeRoute, rows:[[name,value,glyph]],
##    footer, gameOver, winType}
func show_victory(data: Dictionary) -> void:
	chapter_label.text = str(data.get("chapter", "第 1 章 · 终焉之战"))
	subtitle_label.text = str(data.get("chapterNote", "终局 · 仙途长明"))
	var routes: Dictionary = data.get("routes", {})
	_refresh_emblems(routes, str(data.get("activeRoute", "")))
	_fill_rows(data.get("rows", []))
	footer_note.text = str(data.get("footer", "仙路漫漫，终得大道"))
	visible = true


func hide_screen() -> void:
	visible = false


## 12 项按左右两列各 6 项切分；不足时补「—」，多余时截断。
func _fill_rows(rows: Array) -> void:
	for column: VBoxContainer in [left_column, right_column]:
		for child: Node in column.get_children():
			column.remove_child(child)
			child.queue_free()
	for index: int in range(12):
		var target: VBoxContainer = left_column if index < 6 else right_column
		var entry: Array = rows[index] if index < rows.size() else ["—", "—", "◆"]
		target.add_child(_row(str(entry[0]), str(entry[1]), str(entry[2]) if entry.size() > 2 else "◆"))


func _row(name_text: String, value_text: String, glyph: String) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var icon: Label = Label.new()
	icon.text = glyph
	icon.add_theme_font_size_override("font_size", 10)
	icon.add_theme_color_override("font_color", UiTheme.GOLD)
	icon.custom_minimum_size = Vector2(16, 0)
	row.add_child(icon)
	var name_label: Label = Label.new()
	name_label.text = name_text
	name_label.add_theme_font_size_override("font_size", 12)
	name_label.add_theme_color_override("font_color", UiTheme.INK_SOFT)
	name_label.custom_minimum_size = Vector2(104, 0)
	row.add_child(name_label)
	var dots: Label = Label.new()
	dots.text = "·" 
	dots.add_theme_font_size_override("font_size", 10)
	dots.add_theme_color_override("font_color", Color(0.62, 0.60, 0.54, 0.55))
	dots.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(dots)
	var value: Label = Label.new()
	value.text = value_text
	value.add_theme_font_size_override("font_size", 12)
	value.add_theme_color_override("font_color", UiTheme.INK)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value)
	return row


# --- 供自动验收断言 ---

func row_count() -> int:
	return 0 if left_column == null else left_column.get_child_count() + right_column.get_child_count()


func route_emblem_count() -> int:
	return 0 if route_row == null else route_row.get_child_count()


func button_count() -> int:
	return 0 if button_row == null else button_row.get_child_count()


func title_text() -> String:
	return "" if big_title == null else big_title.text


# ---------------------------------------------------------------------------
# 云海仙山背景（程序化绘制，无外部资源）
# ---------------------------------------------------------------------------

class VictoryBackdrop extends Control:
	func _draw() -> void:
		var w: float = size.x
		var h: float = size.y
		# ① 天光：自上而下「暖白 → 淡青 → 青灰」两段插值（分 64 条横带模拟渐变）。
		var bands: int = 64
		for index: int in range(bands):
			var t: float = float(index) / float(bands - 1)
			var color: Color
			if t < 0.5:
				color = Color(0.984, 0.973, 0.933).lerp(Color(0.878, 0.925, 0.929), t / 0.5)
			else:
				color = Color(0.878, 0.925, 0.929).lerp(Color(0.706, 0.800, 0.812), (t - 0.5) / 0.5)
			draw_rect(Rect2(0, h * t, w, h / float(bands) + 1.0), color)

		# ② 中央天光：一串同心圆叠出「金光自峰顶升起」的柔光（「胜利」二字压在其上）。
		var glow_center: Vector2 = Vector2(w * 0.5, h * 0.30)
		for index: int in range(16):
			var radius: float = 40.0 + float(index) * 26.0
			var alpha: float = 0.055 * (1.0 - float(index) / 16.0)
			draw_circle(glow_center, radius, Color(1.0, 0.960, 0.820, alpha))

		# ③ 远山四层：越远越淡、越矮；用 |sin| 造尖峰而不是圆丘。
		_draw_ridge(w, h, 0.44, Color(0.706, 0.784, 0.788, 0.55), 6, 0.075, 1.0, 1.4)
		_draw_ridge(w, h, 0.54, Color(0.604, 0.702, 0.706, 0.62), 8, 0.090, 2.0, 1.7)
		_draw_ridge(w, h, 0.66, Color(0.494, 0.596, 0.600, 0.70), 10, 0.105, 3.0, 2.0)
		_draw_ridge(w, h, 0.80, Color(0.396, 0.498, 0.502, 0.78), 13, 0.120, 4.0, 2.4)

		# ④ 云海：三条带，每条 46 枚小圆叠出蓬松边缘（大圆会变成气泡，故用小圆密集叠）。
		_draw_cloud_band(w, h, 0.30, 46, 11.0, 0.55)
		_draw_cloud_band(w, h, 0.56, 54, 13.0, 0.62)
		_draw_cloud_band(w, h, 0.82, 48, 12.0, 0.52)

		# ⑤ 中央仙山 + 山顶楼阁 + 瀑布。
		_draw_summit(w, h)

		# ⑥ 飞鹤：四只，只用两笔折线。
		_draw_crane(Vector2(w * 0.085, h * 0.20), 15.0)
		_draw_crane(Vector2(w * 0.155, h * 0.13), 10.0)
		_draw_crane(Vector2(w * 0.875, h * 0.33), 12.0)
		_draw_crane(Vector2(w * 0.815, h * 0.71), 9.0)

		# ⑦ 底部压一层浅墨，让结算卷轴与按钮浮起来。
		for index: int in range(16):
			var t: float = float(index) / 15.0
			draw_rect(Rect2(0, h * (0.74 + t * 0.26), w, h * 0.26 / 16.0 + 1.0),
				Color(0.10, 0.14, 0.13, 0.022))

	## 一道山脊：`abs(sin)` 产生尖峰，`seed_offset` 只影响相位（确定性，不依赖随机数）。
	func _draw_ridge(w: float, h: float, base: float, color: Color,
			peaks: int, amplitude: float, seed_offset: float, sharpness: float) -> void:
		var points: PackedVector2Array = PackedVector2Array()
		points.append(Vector2(0, h))
		var steps: int = 90
		for index: int in range(steps + 1):
			var t: float = float(index) / float(steps)
			var x: float = w * t
			var phase: float = t * TAU * float(peaks) + seed_offset
			var y: float = h * base
			y -= pow(abs(sin(phase)), sharpness) * h * amplitude
			y -= pow(abs(sin(phase * 2.7 + seed_offset)), sharpness) * h * amplitude * 0.30
			points.append(Vector2(x, y))
		points.append(Vector2(w, h))
		draw_colored_polygon(points, color)

	## 一条云带：若干簇，每簇由 4 枚递减小圆叠成（低透明度，叠出软边）。
	func _draw_cloud_band(w: float, h: float, base: float, count: int,
			radius: float, alpha: float) -> void:
		var state: int = int(base * 1000.0) + 101
		for index: int in range(count):
			state = (state * 1103515245 + 12345) & 0x7FFFFFFF
			var x: float = float(state % 1000) / 1000.0 * w
			state = (state * 1103515245 + 12345) & 0x7FFFFFFF
			var y: float = h * base + (float(state % 1000) / 1000.0 - 0.5) * h * 0.085
			state = (state * 1103515245 + 12345) & 0x7FFFFFFF
			var scale: float = 0.55 + float(state % 100) / 100.0 * 0.75
			for sub: int in range(4):
				var shrink: float = 1.0 - float(sub) * 0.22
				draw_circle(Vector2(x + float(sub) * radius * 0.45, y - float(sub) * 1.5),
					radius * scale * shrink, Color(1.0, 1.0, 1.0, alpha * (0.34 - float(sub) * 0.05)))

	## 中央仙山：主峰 + 左右副峰 + 山顶楼阁 + 两道瀑布。
	func _draw_summit(w: float, h: float) -> void:
		var cx: float = w * 0.5
		# 山脚收到 0.75h：结算卷轴占 0.467h~0.764h，若山脚仍画到 0.82h，
		# 卷轴下方会露出一截无来由的灰色楔形（首版截图就是这个毛病）。
		var base_y: float = h * 0.75
		var peak_y: float = h * 0.36
		# 左右副峰
		draw_colored_polygon(PackedVector2Array([
			Vector2(cx - w * 0.34, base_y), Vector2(cx - w * 0.18, h * 0.50),
			Vector2(cx - w * 0.02, base_y),
		]), Color(0.42, 0.53, 0.54, 0.80))
		draw_colored_polygon(PackedVector2Array([
			Vector2(cx + w * 0.04, base_y), Vector2(cx + w * 0.20, h * 0.48),
			Vector2(cx + w * 0.36, base_y),
		]), Color(0.42, 0.53, 0.54, 0.80))
		# 主峰
		draw_colored_polygon(PackedVector2Array([
			Vector2(cx - w * 0.19, base_y), Vector2(cx - w * 0.05, h * 0.52),
			Vector2(cx, peak_y), Vector2(cx + w * 0.06, h * 0.52), Vector2(cx + w * 0.19, base_y),
		]), Color(0.35, 0.46, 0.47, 0.88))
		# 主峰受光面
		draw_colored_polygon(PackedVector2Array([
			Vector2(cx, peak_y), Vector2(cx + w * 0.06, h * 0.52),
			Vector2(cx + w * 0.19, base_y), Vector2(cx + w * 0.02, base_y),
		]), Color(0.47, 0.58, 0.58, 0.55))

		# 山顶楼阁：台基 + 两层檐 + 金脊（轮廓即可；被三枚路线徽记压住时仍露檐角）。
		var tower_y: float = peak_y + h * 0.004
		var tower_w: float = w * 0.026
		draw_rect(Rect2(cx - tower_w * 0.5, tower_y, tower_w, h * 0.026),
			Color(0.30, 0.40, 0.42, 0.92))
		for tier: int in range(2):
			var y: float = tower_y - h * 0.010 * float(tier) - h * 0.004
			var half: float = tower_w * (0.95 - float(tier) * 0.28)
			draw_colored_polygon(PackedVector2Array([
				Vector2(cx - half, y), Vector2(cx, y - h * 0.017), Vector2(cx + half, y),
			]), Color(0.24, 0.36, 0.40, 0.92))
			draw_line(Vector2(cx - half, y), Vector2(cx + half, y), Color(0.86, 0.72, 0.38, 0.90), 1.6)

		# 瀑布：落在画面两侧的远峰上（中央区域留给结算卷轴，故不放中间）。
		for pair: Array in [[0.062, 0.44], [0.938, 0.40]]:
			var x: float = w * float(pair[0])
			var top: float = h * float(pair[1])
			draw_rect(Rect2(x, top, 6.0, h * 0.28), Color(0.94, 0.975, 0.98, 0.70))
			draw_rect(Rect2(x + 7.0, top + h * 0.03, 3.0, h * 0.24), Color(0.90, 0.95, 0.97, 0.46))
			draw_circle(Vector2(x + 3.0, top + h * 0.28), 30.0, Color(1.0, 1.0, 1.0, 0.24))
			draw_circle(Vector2(x + 3.0, top + h * 0.30), 46.0, Color(1.0, 1.0, 1.0, 0.14))

	## 飞鹤：两条斜线组成「人」字翅。
	func _draw_crane(position_value: Vector2, span: float) -> void:
		var color: Color = Color(0.20, 0.24, 0.24, 0.66)
		draw_line(position_value, position_value + Vector2(-span, -span * 0.45), color, 1.6)
		draw_line(position_value, position_value + Vector2(span, -span * 0.45), color, 1.6)
		draw_line(position_value + Vector2(-span * 0.2, 0), position_value + Vector2(span * 0.2, 0), color, 1.2)
