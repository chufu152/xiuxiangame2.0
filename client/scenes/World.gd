extends Node3D
## 世界场景（表现层）。R1 起：分层渲染 + 三态迷雾 + 侧栏；R2 加：点选弟子 → 移动高亮 → 移动 → 顶部 TopBar。
##
## 职责：把服务端下发的 view 交给 HexMap / UnitView / SectView 分层渲染，配置三态迷雾，
## 维护极简侧栏（选中格地形 / 选中弟子）与顶部 TopBar（回合、阶段、资源、结束回合）。
##
## 硬约束（§8.4）：
##   - 只读 view，不推导任何玩法规则；迷雾可见集合与移动可达性**完全来自服务端**。
##   - 相机由常驻的 Session.camera_rig 提供；本场景**只做一次**首帧取景（frame_once），
##     view 刷新、点选、移动、结束回合、再开一局都不得重置相机角度与缩放。
##   - 占位资源缺失只由 AssetLibrary 告警回退，本场景不崩溃。

const SIDEBAR_WIDTH: float = 320.0
const TOPBAR_HEIGHT: float = 46.0

var map: HexMap = null
var fog: Fog = null
var units: UnitView = null
var sects: SectView = null
var sidebar: RichTextLabel = null
var status_label: Label = null

## 顶部 TopBar（第 N 回合 / 阶段 / 玩家资源 / 结束回合）。
var topbar: CanvasLayer = null
var topbar_turn_label: Label = null
var topbar_phase_label: Label = null
var topbar_resource_label: Label = null
var end_turn_button: Button = null

## 当前选中格的文字描述（供 UI 与自动验收断言）。
var selection_text: String = ""
## 最近一次 view 里的势力数量。
var sect_count: int = 0

## 当前选中的己方弟子 id（空串 = 未选中）。
var selected_disciple_id: String = ""
## 是否处于移动模式（已选中弟子且有非空可达集）。
var move_mode: bool = false
## 最近一次 queryMoveRange 的可达格（服务端权威，客户端不本地推导）。
var reachable_ids: Array[String] = []
## 最近一次 queryMoveRange 的逐格累计代价（侧栏 / 验收用）。
var reachable_costs: Dictionary = {}
## 移动模式下光标所在高亮格及其累计代价（-1 = 不在高亮内）。
var hover_tile_id: String = ""
var hover_cost: int = -1

var _selected: String = ""


func _ready() -> void:
	map = get_node("HexMap") as HexMap
	fog = get_node("Fog") as Fog
	units = get_node("UnitView") as UnitView
	sects = get_node("SectView") as SectView
	_build_lighting()
	_build_sidebar()
	_build_topbar()
	Session.camera_rig.set_active(true)
	Session.view_changed.connect(_on_view_changed)
	Session.move_range_received.connect(_on_move_range_received)
	Session.move_result_received.connect(_on_move_result_received)
	if not Session.current_view.is_empty():
		_render(Session.current_view)
	else:
		_set_selection("")
		_refresh_status()
		_refresh_topbar()


func _process(_delta: float) -> void:
	# busy 期间禁用「结束回合」，避免 finishTurn/beginPlayerTurn 序列被重入。
	if end_turn_button != null:
		end_turn_button.disabled = Session.busy or not Session.supports(Commands.FINISH_TURN)


func _on_view_changed(view: Dictionary) -> void:
	_render(view)


# ---------------------------------------------------------------------------
# 渲染
# ---------------------------------------------------------------------------

func _render(view: Dictionary) -> void:
	var assets: AssetLibrary = Session.assets
	fog.configure(view)
	map.render_view(view, assets, fog)
	units.render_view(view, map, assets, fog, selected_disciple_id)
	sects.render_view(view, map, assets, fog)
	sect_count = (view.get("sects", []) as Array).size()
	var bounds: Dictionary = _view_bounds(view)
	Session.camera_rig.frame_once(bounds["center"], bounds["span"])
	if not _selected.is_empty():
		_set_selection(_selected)
	elif not selected_disciple_id.is_empty():
		_set_selection(_describe_disciple(selected_disciple_id, {}))
	_refresh_status()
	_refresh_topbar()


func _view_bounds(view: Dictionary) -> Dictionary:
	var tiles: Dictionary = view.get("tiles", {})
	var min_x: float = INF
	var max_x: float = -INF
	var min_z: float = INF
	var max_z: float = -INF
	for tile_id: String in tiles:
		var tile: Dictionary = tiles[tile_id]
		var point: Vector3 = Hex.to_world(int(tile.get("q", 0)), int(tile.get("r", 0)))
		min_x = minf(min_x, point.x)
		max_x = maxf(max_x, point.x)
		min_z = minf(min_z, point.z)
		max_z = maxf(max_z, point.z)
	if min_x > max_x:
		return {"center": Vector3.ZERO, "span": 24.0}
	return {
		"center": Vector3((min_x + max_x) / 2.0, 0.0, (min_z + max_z) / 2.0),
		"span": maxf(max_x - min_x, max_z - min_z) + 4.0,
	}


# ---------------------------------------------------------------------------
# 选中格
# ---------------------------------------------------------------------------

func select_tile(tile_id: String) -> void:
	_selected = tile_id
	_set_selection(tile_id)


func _set_selection(tile_id: String) -> void:
	selection_text = _describe(tile_id)
	if sidebar != null:
		sidebar.text = selection_text


func _describe(tile_id: String) -> String:
	if tile_id.is_empty():
		return "点击地块查看详情"
	if map == null or not map.tiles.has(tile_id):
		return "地块 %s\n（尚未载入）" % tile_id
	if fog.state_for(tile_id) == Fog.State.UNEXPLORED:
		# 未探索格绝不泄露任何地形/归属字段。
		return "地块 %s\n未探索" % tile_id
	var data: Dictionary = (map.tiles[tile_id] as Node3D).get_meta("display_data")
	return "\n".join(PackedStringArray([
		"地块 %s" % tile_id,
		"基底 %s" % _text_of(data, "baseTerrain"),
		"海拔 %s" % _text_of(data, "relief"),
		"地貌 %s" % _list_of(data, "features"),
		"河流 %s" % ("是" if not (data.get("riverEdges", []) as Array).is_empty() else "无"),
		"险地 %s" % ("是" if bool(data.get("danger", false)) else "否"),
		"节点 %s" % _text_of(data, "nodeId"),
		"资源 %s" % _text_of(data, "luxuryType"),
		"归属 %s" % _text_of(data, "ownerSectId"),
	]))


static func _text_of(data: Dictionary, key: String) -> String:
	var value: Variant = data.get(key)
	if value == null or str(value).is_empty():
		return "无"
	return str(value)


static func _list_of(data: Dictionary, key: String) -> String:
	var values: Array = data.get(key, [])
	var parts: PackedStringArray = PackedStringArray()
	for value: Variant in values:
		parts.append(str(value))
	if parts.is_empty():
		return "无"
	return "、".join(parts)


# ---------------------------------------------------------------------------
# R2：点选 → 高亮 → 移动
# ---------------------------------------------------------------------------

## 左键点击优先级：① 移动模式下点可达格 → moveDisciple；② 点己方弟子所在格 → 选中并 queryMoveRange；
## ③ 否则回到 R1 的地块选择并清除高亮。
func on_tile_clicked(tile_id: String) -> void:
	if move_mode and reachable_ids.has(tile_id):
		Session.request_move_disciple(selected_disciple_id, tile_id)
		return
	var disciple: Dictionary = _player_disciple_at(tile_id)
	if not disciple.is_empty():
		select_disciple(str(disciple.get("id", "")))
		return
	_clear_move_state()
	select_tile(tile_id)


func select_disciple(disciple_id: String) -> void:
	selected_disciple_id = disciple_id
	move_mode = false
	reachable_ids.clear()
	reachable_costs.clear()
	hover_tile_id = ""
	hover_cost = -1
	_selected = ""
	if map != null:
		map.clear_move_range()
	if units != null:
		units.set_selected(disciple_id)
	_set_selection(_describe_disciple(disciple_id, {}))
	Session.request_query_move_range(disciple_id)


func _clear_move_state() -> void:
	move_mode = false
	selected_disciple_id = ""
	reachable_ids.clear()
	reachable_costs.clear()
	hover_tile_id = ""
	hover_cost = -1
	if map != null:
		map.clear_move_range()
	if units != null:
		units.set_selected("")


func _on_move_range_received(result: Dictionary) -> void:
	if str(result.get("discipleId", "")) != selected_disciple_id:
		return
	var ids: Array = result.get("tileIds", [])
	reachable_ids.clear()
	for value: Variant in ids:
		reachable_ids.append(str(value))
	reachable_costs = (result.get("costs", {}) as Dictionary).duplicate()
	move_mode = not reachable_ids.is_empty()
	map.show_move_range(ids, result.get("costs", {}), str(result.get("originTileId", "")))
	_set_selection(_describe_disciple(selected_disciple_id, result))


func _on_move_result_received(result: Dictionary) -> void:
	if not bool(result.get("success", false)):
		# 业务失败（不可达 / 移动力不足）：只提示，不移动。
		_set_selection(str(result.get("message", "移动失败")))
		return
	if int(result.get("turnsRemaining", 0)) > 0:
		# 仍有移动力：重新查询，高亮随之更新。
		Session.request_query_move_range(selected_disciple_id)
	else:
		move_mode = false
		reachable_ids.clear()
		reachable_costs.clear()
		map.clear_move_range()
		_set_selection(_describe_disciple(selected_disciple_id, {}))


func _player_disciple_at(tile_id: String) -> Dictionary:
	for sect: Dictionary in Session.current_view.get("sects", []):
		if not bool(sect.get("player", false)):
			continue
		for disciple: Dictionary in sect.get("disciples", []):
			if str(disciple.get("tileId", "")) == tile_id:
				return disciple
	return {}


func _find_disciple(disciple_id: String) -> Dictionary:
	for sect: Dictionary in Session.current_view.get("sects", []):
		for disciple: Dictionary in sect.get("disciples", []):
			if str(disciple.get("id", "")) == disciple_id:
				return disciple
	return {}


func _describe_disciple(disciple_id: String, range_result: Dictionary) -> String:
	var disciple: Dictionary = _find_disciple(disciple_id)
	if disciple.is_empty():
		return "弟子 %s\n（已不在视野）" % disciple_id
	var move_points: int = int(disciple.get("movePoints", 0))
	var lines: PackedStringArray = PackedStringArray([
		"弟子 %s" % str(disciple.get("name", disciple_id)),
		"境界 %s" % str(disciple.get("realm", "?")),
		"灵根 %s" % _list_of(disciple, "spiritRoots"),
		"兵种 %s" % str(disciple.get("unitClass", "?")),
		"移动力 %d/%d" % [move_points, int(disciple.get("maxMovePoints", 0))],
	])
	if not range_result.is_empty():
		lines.append("可达格 %d" % int(range_result.get("tileCount", 0)))
	if hover_cost >= 0:
		lines.append("光标格 %s 代价 %d" % [hover_tile_id, hover_cost])
	if move_points <= 0:
		lines.append("（本回合已无移动力，可选中但无可达格）")
	return "\n".join(lines)


## 当前移动高亮格数（供自动验收断言）。
func highlight_count() -> int:
	if map == null:
		return 0
	return map.highlight_ids.size()


# ---------------------------------------------------------------------------
# 顶部 TopBar
# ---------------------------------------------------------------------------

func _build_topbar() -> void:
	topbar = CanvasLayer.new()
	topbar.name = "TopBar"
	topbar.layer = 2
	add_child(topbar)
	var panel: PanelContainer = PanelContainer.new()
	panel.anchor_left = 0.0
	panel.anchor_right = 1.0
	panel.offset_left = 0.0
	panel.offset_right = -SIDEBAR_WIDTH
	panel.offset_top = 0.0
	panel.offset_bottom = TOPBAR_HEIGHT
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.11, 0.16, 0.15, 0.90)
	style.border_color = Color("4d5f57")
	style.border_width_bottom = 1
	style.content_margin_left = 16.0
	style.content_margin_right = 16.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	panel.add_theme_stylebox_override("panel", style)
	topbar.add_child(panel)

	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	panel.add_child(row)

	topbar_turn_label = _topbar_label(row, "第 ? 回合")
	topbar_phase_label = _topbar_label(row, "阶段 ?")
	topbar_resource_label = _topbar_label(row, "")
	topbar_resource_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	end_turn_button = Button.new()
	end_turn_button.text = "结束回合"
	end_turn_button.tooltip_text = "先 finishTurn 再 beginPlayerTurn；期间相机角度与缩放保持不变"
	end_turn_button.pressed.connect(func() -> void: Session.request_end_turn_sequence())
	row.add_child(end_turn_button)


func _topbar_label(parent: Node, text: String) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", Color("e9e2ce"))
	parent.add_child(label)
	return label


func _refresh_topbar() -> void:
	var view: Dictionary = Session.current_view
	var meta: Dictionary = view.get("metadata", {})
	var turn: int = int(meta.get("turn", view.get("turn", 0)))
	var phase: String = str(meta.get("phase", view.get("phase", "?")))
	if topbar_turn_label != null:
		topbar_turn_label.text = "第 %d 回合" % turn
	if topbar_phase_label != null:
		topbar_phase_label.text = "阶段 %s" % phase
	if topbar_resource_label != null:
		topbar_resource_label.text = _resource_text(view)


func _resource_text(view: Dictionary) -> String:
	for sect: Dictionary in view.get("sects", []):
		if not bool(sect.get("player", false)):
			continue
		var resources: Dictionary = sect.get("resources", {})
		return "灵力 %d · 灵石 %d · 工力 %d · 声望 %d" % [
			int(resources.get("spiritPower", 0)),
			int(resources.get("spiritStones", 0)),
			int(resources.get("workPower", 0)),
			int(resources.get("prestige", 0)),
		]
	return ""


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		# 仅在移动模式下做悬停代价提示，避免常态下每帧射线拾取。
		if move_mode and map != null:
			var motion: InputEventMouseMotion = event
			var hovered: String = map.pick_tile(Session.camera_rig.camera, motion.position)
			if hovered != hover_tile_id:
				hover_tile_id = hovered
				hover_cost = map.highlight_cost(hovered) if not hovered.is_empty() else -1
				if not selected_disciple_id.is_empty():
					_set_selection(_describe_disciple(selected_disciple_id, {}))
		return
	if not (event is InputEventMouseButton):
		return
	var button: InputEventMouseButton = event
	if not button.pressed or button.button_index != MOUSE_BUTTON_LEFT:
		return
	if map == null or fog == null:
		return
	var picked: String = map.pick_tile(Session.camera_rig.camera, button.position)
	if not picked.is_empty():
		on_tile_clicked(picked)
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------------------
# 场景自建节点（避免 .tscn 里塞非必要子资源）
# ---------------------------------------------------------------------------

func _build_lighting() -> void:
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-52.0, -38.0, 0.0)
	sun.light_energy = 1.15
	sun.shadow_enabled = false
	add_child(sun)
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("e7e2d3")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("fff6e2")
	environment.ambient_light_energy = 0.95
	var world_environment: WorldEnvironment = WorldEnvironment.new()
	world_environment.name = "WorldEnvironment"
	world_environment.environment = environment
	add_child(world_environment)


func _build_sidebar() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	layer.name = "Hud"
	add_child(layer)

	var panel: PanelContainer = PanelContainer.new()
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_top = 0.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -SIDEBAR_WIDTH
	panel.offset_right = 0.0
	panel.offset_top = 0.0
	panel.offset_bottom = 0.0
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.965, 0.957, 0.925, 0.94)
	style.border_color = Color("b6ad8b")
	style.border_width_left = 2
	style.content_margin_left = 18.0
	style.content_margin_right = 18.0
	style.content_margin_top = 16.0
	style.content_margin_bottom = 16.0
	panel.add_theme_stylebox_override("panel", style)
	layer.add_child(panel)

	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)

	var title: Label = Label.new()
	title.text = "山河画卷 · R2"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color("294e48"))
	column.add_child(title)

	status_label = Label.new()
	status_label.add_theme_font_size_override("font_size", 13)
	status_label.add_theme_color_override("font_color", Color("5d6b64"))
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(status_label)

	column.add_child(HSeparator.new())

	sidebar = RichTextLabel.new()
	sidebar.fit_content = false
	sidebar.scroll_active = true
	sidebar.selection_enabled = false
	sidebar.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sidebar.add_theme_font_size_override("normal_font_size", 15)
	sidebar.text = "点击地块查看详情"
	column.add_child(sidebar)

	column.add_child(HSeparator.new())

	var buttons: HBoxContainer = HBoxContainer.new()
	column.add_child(buttons)
	var refresh: Button = Button.new()
	refresh.text = "刷新 view"
	refresh.tooltip_text = "向服务端请求 getState，相机角度与缩放保持不变"
	refresh.pressed.connect(func() -> void: Session.request_refresh())
	buttons.add_child(refresh)
	var back: Button = Button.new()
	back.text = "返回菜单"
	back.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://scenes/MainMenu.tscn"))
	buttons.add_child(back)

	var hint: Label = Label.new()
	hint.text = "正交 45° · 滚轮缩放 · 中/右键平移 · 左键选中弟子/地块 · 点高亮格移动 · 结束回合"
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color("6d7470"))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(hint)

	Session.status_changed.connect(_refresh_status)


func _refresh_status() -> void:
	if status_label != null:
		status_label.text = Session.status
