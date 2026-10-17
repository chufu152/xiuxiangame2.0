class_name Decorations
extends Node3D
## R8 表现层装饰：昼夜循环、六边形网格开关、宗门色边框、灵气粒子、飞鸟、草木摆动、
## 泼墨迷雾转场。
##
## 硬约束（R8 提示词）：
##   - **纯显示层**：网格与宗门边框不写入 `GameState`、不下发协议字段（裁决四）；
##   - **不触碰相机**：本类只操作自己名下的节点与光照，永不读写 `CameraRig`（裁决一）；
##   - **不引入服务端随机**：所有动画按 `delta` 推进，不调用任何随机源（确定性铁律）；
##   - 资源缺失不崩：粒子/网格全部程序化生成，不依赖 `manifest.json`。

## 昼夜一轮的秒数（纯表现，不影响回合）。
const DAY_CYCLE_SECONDS: float = 180.0
## 泼墨转场时长（秒）。
const INK_FADE_SECONDS: float = 0.55
## 网格线颜色（淡墨）。
const GRID_COLOR: Color = Color(0.20, 0.26, 0.24, 0.35)
## 宗门边框厚度（世界单位）。
const BORDER_HEIGHT: float = 0.05

var sun: DirectionalLight3D = null
var environment: Environment = null

## 昼夜：0=子夜、0.25=日出、0.5=正午、0.75=日落。开局停在上午。
var day_phase: float = 0.38
var day_night_enabled: bool = true
var day_seconds: float = DAY_CYCLE_SECONDS

var grid_root: Node3D = null
var border_root: Node3D = null
var ambient_root: Node3D = null
var bird_root: Node3D = null
var ink_root: Node3D = null

var grid_visible: bool = false
var borders_visible: bool = true

## 供自动验收断言：累计播放的泼墨转场次数。
var ink_transition_count: int = 0

var _birds: Array[Node3D] = []
var _bird_angles: Array[float] = []
var _sway_nodes: Array[Node3D] = []
var _sway_base: Array[float] = []
var _sway_clock: float = 0.0
var _ink_clock: float = 0.0


func setup(sun_node: DirectionalLight3D, world_environment: Environment) -> void:
	sun = sun_node
	environment = world_environment
	grid_root = _make_layer("GridLayer")
	border_root = _make_layer("BorderLayer")
	ambient_root = _make_layer("AmbientLayer")
	bird_root = _make_layer("BirdLayer")
	ink_root = _make_layer("InkLayer")
	_build_birds()
	_apply_day_phase()


func _make_layer(layer_name: String) -> Node3D:
	var layer: Node3D = Node3D.new()
	layer.name = layer_name
	add_child(layer)
	return layer


# ---------------------------------------------------------------------------
# 昼夜循环
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	if day_night_enabled:
		day_phase = fposmod(day_phase + delta / maxf(day_seconds, 1.0), 1.0)
		_apply_day_phase()
	_sway_clock += delta
	_animate_sway()
	_animate_birds(delta)


## 把 `day_phase` 映射到太阳高度角、光照能量、环境色与背景色。
## 相机的 `rotation`/`size` 一律不参与（相机铁律）。
func _apply_day_phase() -> void:
	if sun == null:
		return
	# 相位 → 太阳方位角：日出在东方（-90°），正午在正上方（0°），日落在西方（+90°）。
	var elevation: float = sin((day_phase - 0.25) * TAU) * 68.0
	var azimuth: float = -110.0 + 220.0 * clampf((day_phase - 0.25) / 0.5, 0.0, 1.0)
	sun.rotation_degrees = Vector3(-maxf(elevation, -18.0), azimuth, 0.0)
	var daylight: float = clampf(sin((day_phase - 0.25) * TAU), 0.0, 1.0)
	sun.light_energy = 0.18 + 1.05 * daylight
	sun.light_color = Color(1.0, 0.93, 0.82).lerp(Color(1.0, 0.86, 0.66), 1.0 - daylight)
	if environment == null:
		return
	var night_ambient: Color = Color("4a5a6b")
	var day_ambient: Color = Color("fff6e2")
	environment.ambient_light_color = night_ambient.lerp(day_ambient, daylight)
	environment.ambient_light_energy = 0.42 + 0.55 * daylight
	environment.background_color = Color("2b3542").lerp(Color("e7e2d3"), daylight)


## 切换到指定相位（自动验收用，立即生效）。
func set_day_phase(phase: float) -> void:
	day_phase = fposmod(phase, 1.0)
	_apply_day_phase()


func toggle_day_night(enabled: bool) -> void:
	day_night_enabled = enabled


# ---------------------------------------------------------------------------
# 六边形网格（裁决四：纯显示层）
# ---------------------------------------------------------------------------

## 按地块重建网格线。只画「唯一一条」相邻边，避免重复叠线。
func build_grid(map: HexMap) -> void:
	if grid_root == null:
		return
	for child: Node in grid_root.get_children():
		grid_root.remove_child(child)
		child.queue_free()
	if map == null:
		return
	var drawn: Dictionary = {}
	for tile_id: String in map.tiles:
		var tile: Node3D = map.tiles[tile_id] as Node3D
		var data: Dictionary = tile.get_meta("display_data", {})
		var q: int = int(data.get("q", 0))
		var r: int = int(data.get("r", 0))
		var top: Vector3 = map.top_position(tile_id) + Vector3(0, 0.035, 0)
		for edge: int in range(6):
			var adjacent: Vector2i = Vector2i(q, r) + Hex.DIRECTIONS[edge]
			var key: String = "%s|%d|%d" % [tile_id, edge, 0]
			var reverse: String = "%s|%d|%d" % [Hex.id(adjacent.x, adjacent.y), (edge + 3) % 6, 0]
			if drawn.has(key) or drawn.has(reverse):
				continue
			drawn[key] = true
			var endpoints: Array[Vector3] = Hex.edge_vertices(q, r, edge)
			var a: Vector3 = endpoints[0]
			var b: Vector3 = endpoints[1]
			a.y = top.y
			b.y = top.y
			var shape: BoxMesh = BoxMesh.new()
			shape.size = Vector3(0.022, 0.008, a.distance_to(b))
			var material: StandardMaterial3D = HexMap.solid(GRID_COLOR)
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			var line: MeshInstance3D = HexMap.add_mesh(grid_root, "GridLine", shape, (a + b) / 2.0, material)
			line.rotation.y = atan2(b.x - a.x, b.z - a.z)
	grid_root.visible = grid_visible


func set_grid_visible(value: bool) -> void:
	grid_visible = value
	if grid_root != null:
		grid_root.visible = value


# ---------------------------------------------------------------------------
# 宗门色边框（裁决四：纯显示层）
# ---------------------------------------------------------------------------

## 按 `view.tiles[].ownerSectId` 给归属地块加一圈宗门色边框。
## 归属与配色**全部来自 view**，客户端不推导领土归属。
func build_borders(view: Dictionary, map: HexMap) -> void:
	if border_root == null:
		return
	for child: Node in border_root.get_children():
		border_root.remove_child(child)
		child.queue_free()
	if map == null:
		return
	var colors: Dictionary = {}
	for sect: Dictionary in view.get("sects", []):
		colors[str(sect.get("id", ""))] = Color.from_string(str(sect.get("color", "#387f78")), Color("387f78"))
	var tiles: Dictionary = view.get("tiles", {})
	for tile_id: String in tiles:
		var tile: Dictionary = tiles[tile_id]
		var owner_id: String = str(tile.get("ownerSectId", ""))
		if owner_id.is_empty() or not colors.has(owner_id):
			continue
		if not map.tiles.has(tile_id):
			continue
		var rim: CylinderMesh = CylinderMesh.new()
		rim.top_radius = 1.0
		rim.bottom_radius = 1.0
		rim.height = BORDER_HEIGHT
		rim.radial_segments = 6
		rim.cap_top = false
		rim.cap_bottom = false
		var color: Color = colors[owner_id]
		color.a = 0.62
		var material: StandardMaterial3D = HexMap.solid(color)
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		var instance: MeshInstance3D = HexMap.add_mesh(border_root, "Border",
			rim, map.top_position(tile_id) + Vector3(0, BORDER_HEIGHT * 0.5, 0), material)
		instance.rotation.y = PI / 6.0
	border_root.visible = borders_visible


func set_borders_visible(value: bool) -> void:
	borders_visible = value
	if border_root != null:
		border_root.visible = value


# ---------------------------------------------------------------------------
# 灵气粒子 + 飞鸟 + 草木摆动
# ---------------------------------------------------------------------------

## 灵气上升粒子：跟随地图中心，数量固定、方向确定（不读随机源）。
func build_ambient_particles(center: Vector3, span: float) -> void:
	if ambient_root == null:
		return
	for child: Node in ambient_root.get_children():
		ambient_root.remove_child(child)
		child.queue_free()
	var particles: CPUParticles3D = CPUParticles3D.new()
	particles.name = "SpiritMotes"
	particles.amount = 90
	particles.lifetime = 4.2
	particles.preprocess = 2.0
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	particles.emission_box_extents = Vector3(span * 0.5, 0.4, span * 0.5)
	particles.direction = Vector3(0.0, 1.0, 0.0)
	particles.spread = 12.0
	particles.gravity = Vector3(0.0, 0.22, 0.0)
	particles.initial_velocity_min = 0.16
	particles.initial_velocity_max = 0.46
	particles.scale_amount_min = 0.035
	particles.scale_amount_max = 0.075
	particles.color = Color(0.72, 0.92, 0.86, 0.55)
	particles.position = center + Vector3(0, 1.1, 0)
	ambient_root.add_child(particles)


func _build_birds() -> void:
	if bird_root == null:
		return
	_birds.clear()
	_bird_angles.clear()
	for index: int in range(5):
		var bird: Node3D = Node3D.new()
		bird.name = "Bird%d" % index
		var left: BoxMesh = BoxMesh.new()
		left.size = Vector3(0.16, 0.012, 0.035)
		var right: BoxMesh = BoxMesh.new()
		right.size = Vector3(0.16, 0.012, 0.035)
		var material: StandardMaterial3D = HexMap.solid(Color(0.16, 0.20, 0.19, 0.85))
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		var left_instance: MeshInstance3D = HexMap.add_mesh(bird, "Left", left, Vector3(-0.08, 0, 0), material)
		left_instance.rotation.z = 0.35
		var right_instance: MeshInstance3D = HexMap.add_mesh(bird, "Right", right, Vector3(0.08, 0, 0), material)
		right_instance.rotation.z = -0.35
		bird_root.add_child(bird)
		_birds.append(bird)
		_bird_angles.append(TAU * float(index) / 5.0)


## 飞鸟：在固定半径上绕圈，高度按相位轻微起伏（纯三角函数，无随机）。
func _animate_birds(delta: float) -> void:
	for index: int in range(_birds.size()):
		var bird: Node3D = _birds[index]
		if not is_instance_valid(bird):
			continue
		_bird_angles[index] = fposmod(_bird_angles[index] + delta * (0.24 + 0.05 * float(index)), TAU)
		var angle: float = _bird_angles[index]
		var radius: float = 7.5 + 1.6 * float(index)
		bird.position = Vector3(cos(angle) * radius, 6.4 + sin(angle * 2.0) * 0.5, sin(angle) * radius)
		bird.rotation.y = -angle + PI * 0.5


## 登记需要摆动的草木节点（HexMap 的占位树）。每帧按正弦微幅旋转。
func register_sway(nodes: Array[Node3D]) -> void:
	_sway_nodes.clear()
	_sway_base.clear()
	for node: Node3D in nodes:
		if not is_instance_valid(node):
			continue
		_sway_nodes.append(node)
		_sway_base.append(node.rotation.z)


func _animate_sway() -> void:
	for index: int in range(_sway_nodes.size()):
		var node: Node3D = _sway_nodes[index]
		if not is_instance_valid(node):
			continue
		node.rotation.z = _sway_base[index] + sin(_sway_clock * 1.35 + float(index) * 0.7) * 0.045


# ---------------------------------------------------------------------------
# 泼墨迷雾转场
# ---------------------------------------------------------------------------

## 对「本次新变为可见」的地块播一次泼墨褪去：墨团由浓转淡、由小铺满。
## `tile_ids` 由调用方（World）对比前后两帧迷雾状态得出，本类不做任何状态推导。
func play_ink_transitions(map: HexMap, tile_ids: Array[String]) -> void:
	if map == null or ink_root == null:
		return
	for tile_id: String in tile_ids:
		if not map.tiles.has(tile_id):
			continue
		var disc: CylinderMesh = CylinderMesh.new()
		disc.top_radius = 1.02
		disc.bottom_radius = 1.02
		disc.height = 0.012
		disc.radial_segments = 6
		var material: StandardMaterial3D = HexMap.solid(Color(0.09, 0.12, 0.11, 0.86))
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		var overlay: MeshInstance3D = HexMap.add_mesh(ink_root, "InkFade",
			disc, map.top_position(tile_id) + Vector3(0, 0.09, 0), material)
		overlay.rotation.y = PI / 6.0
		overlay.scale = Vector3(0.35, 1.0, 0.35)
		var tween: Tween = create_tween()
		tween.set_parallel(true)
		tween.tween_property(overlay, "scale", Vector3(1.0, 1.0, 1.0), INK_FADE_SECONDS)
		tween.tween_property(material, "albedo_color", Color(0.09, 0.12, 0.11, 0.0), INK_FADE_SECONDS)
		tween.chain().tween_callback(overlay.queue_free)
		ink_transition_count += 1


# ---------------------------------------------------------------------------
# 供自动验收断言（R8）
# ---------------------------------------------------------------------------

func grid_layer_visible() -> bool:
	return grid_root != null and grid_root.visible


func border_layer_visible() -> bool:
	return border_root != null and border_root.visible


func border_count() -> int:
	return 0 if border_root == null else border_root.get_child_count()


func grid_line_count() -> int:
	return 0 if grid_root == null else grid_root.get_child_count()


func bird_count() -> int:
	return _birds.size()


func sun_energy() -> float:
	return 0.0 if sun == null else sun.light_energy
