extends Node3D
## R1 世界场景（表现层）。
##
## 职责：把服务端下发的 view 交给 HexMap / UnitView / SectView 分层渲染，配置三态迷雾，
## 维护极简侧栏（选中格的 基底/海拔/地貌/河流/险地/节点/资源/归属）。
##
## 硬约束（§8.4）：
##   - 只读 view，不推导任何玩法规则；迷雾可见集合完全来自服务端。
##   - 相机由常驻的 Session.camera_rig 提供；本场景**只做一次**首帧取景（frame_once），
##     view 刷新、再开一局都不得重置相机角度与缩放。
##   - 占位资源缺失只由 AssetLibrary 告警回退，本场景不崩溃。

const SIDEBAR_WIDTH: float = 320.0

var map: HexMap = null
var fog: Fog = null
var units: UnitView = null
var sects: SectView = null
var sidebar: RichTextLabel = null
var status_label: Label = null

## 当前选中格的文字描述（供 UI 与自动验收断言）。
var selection_text: String = ""
## 最近一次 view 里的势力数量。
var sect_count: int = 0

var _selected: String = ""


func _ready() -> void:
	map = get_node("HexMap") as HexMap
	fog = get_node("Fog") as Fog
	units = get_node("UnitView") as UnitView
	sects = get_node("SectView") as SectView
	_build_lighting()
	_build_sidebar()
	Session.camera_rig.set_active(true)
	Session.view_changed.connect(_on_view_changed)
	if not Session.current_view.is_empty():
		_render(Session.current_view)
	else:
		_set_selection("")
		_refresh_status()


func _on_view_changed(view: Dictionary) -> void:
	_render(view)


# ---------------------------------------------------------------------------
# 渲染
# ---------------------------------------------------------------------------

func _render(view: Dictionary) -> void:
	var assets: AssetLibrary = Session.assets
	fog.configure(view)
	map.render_view(view, assets, fog)
	units.render_view(view, map, assets, fog)
	sects.render_view(view, map, assets, fog)
	sect_count = (view.get("sects", []) as Array).size()
	var bounds: Dictionary = _view_bounds(view)
	Session.camera_rig.frame_once(bounds["center"], bounds["span"])
	if not _selected.is_empty():
		_set_selection(_selected)
	_refresh_status()


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


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var button: InputEventMouseButton = event
	if not button.pressed or button.button_index != MOUSE_BUTTON_LEFT:
		return
	if map == null or fog == null:
		return
	var picked: String = map.pick_tile(Session.camera_rig.camera, button.position)
	if not picked.is_empty():
		select_tile(picked)
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
	title.text = "山河画卷 · R1"
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
	hint.text = "正交 45° · 滚轮缩放 · 中/右键平移 · 左键选中 · F5 资源热重读"
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color("6d7470"))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(hint)

	Session.status_changed.connect(_refresh_status)


func _refresh_status() -> void:
	if status_label != null:
		status_label.text = Session.status
