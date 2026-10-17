extends Node3D
## 建筑概念图：把 `Enums.Building.ALL` 的十个建筑排成一行实拍，用于肉眼比对参考图。
##
## 运行（**不能加 `--headless`**，否则无渲染设备）：
##   Godot_v4.4.1-stable_win64_console.exe --path client res://tools/BuildingShot.tscn
##
## 产物：`outputs/ui_preview_buildings.png`（不入库，`/outputs/` 已在 .gitignore）。
## 与 `WorldShot` 分工：那个拍的是「真实对局里的地图」，这个拍的是「建筑原型本身」，
## 因为开局只有 1~2 座建筑，光靠地图截图看不全十种形制。
##
## 名称标签用 2D 覆盖层而不是 `Label3D`：3D 标签会随正交相机一起被压扁、
## 还会被地面/檐口挡住；2D 标签用 `unproject_position` 钉在每座建筑脚下，字号恒定。

const SPACING: float = 1.34
## 十个建筑横排总宽 ≈ SPACING*9 = 12.06，最宽的帝都对焦后约 1.5；
## 正交相机横向可视 = size*aspect(16:9)=1.778*size，size=8.0 → 14.2，两侧各留 0.35 边距。
const CAMERA_SIZE: float = 8.0
## 相机注视点抬高：正交相机抬高注视点等于把整排建筑在画面里下移。
## 建筑实体只占 y∈[0,2.1]，重心约 0.75；再抬到 1.15 才让它们落在画面竖向中线。
const LOOK_AT_Y: float = 1.15
## 相机 yaw 45° 时的「屏幕右方向」（世界坐标）：沿它排开，十个建筑才会横向一字排开。
const SCREEN_RIGHT: Vector3 = Vector3(0.7071068, 0.0, -0.7071068)
const LABEL_FONT_SIZE: int = 18
const LABEL_INK: Color = Color(0.29, 0.33, 0.31)


func _ready() -> void:
	var env: WorldEnvironment = WorldEnvironment.new()
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("f3eee1")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("e8e2d2")
	# 环境光压到 0.55：参考图的体积感全靠明暗对比，环境光给满会把坡顶拍成平涂色块。
	environment.ambient_light_energy = 0.55
	env.environment = environment
	add_child(env)

	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -38, 0)
	sun.light_energy = 1.45
	sun.shadow_enabled = false
	add_child(sun)

	var camera: Camera3D = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.rotation_degrees = Vector3(-45.0, 45.0, 0.0)
	camera.size = CAMERA_SIZE
	# 沿相机自身 forward 反推位置：rotation(-45,45) 的前向 = (-0.5,-0.7071,-0.5)，
	# 故注视点 target 对应的相机位置 = target + (0.5d, 0.7071d, 0.5d)，d = 12。
	camera.position = Vector3(6.0, LOOK_AT_Y + 8.49, 6.0)
	add_child(camera)
	camera.make_current()
	print("BUILDINGSHOT_CAMERA: size=%.2f pos=%s rot=%s" % [
		camera.size, str(camera.position), str(camera.rotation_degrees)])

	var overlay: CanvasLayer = CanvasLayer.new()
	overlay.layer = 2
	add_child(overlay)
	var canvas: Control = Control.new()
	canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(canvas)

	var ids: Array = Enums.Building.ALL
	var total: float = SPACING * float(ids.size() - 1)
	var anchors: Array[Vector3] = []
	var name_labels: Array[Label] = []
	for index: int in range(ids.size()):
		var building_id: String = str(ids[index])
		var holder: Node3D = Node3D.new()
		holder.position = SCREEN_RIGHT * (-total * 0.5 + SPACING * float(index))
		add_child(holder)
		Buildings.build(holder, building_id, 2)
		# 落地投影：一枚极淡的扁圆盘。比开全局阴影便宜，也不会在纸色背景上切出硬边。
		var disc: CylinderMesh = CylinderMesh.new()
		disc.top_radius = 0.46
		disc.bottom_radius = 0.46
		disc.height = 0.006
		disc.radial_segments = 20
		var disc_node: MeshInstance3D = HexMap.add_mesh(holder, "Contact", disc,
			Vector3(0, 0.003, 0), _flat_shadow())
		disc_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

		var label: Label = Label.new()
		label.text = str(Enums.Building.NAMES.get(building_id, building_id))
		label.add_theme_font_size_override("font_size", LABEL_FONT_SIZE)
		label.add_theme_color_override("font_color", LABEL_INK)
		label.add_theme_color_override("font_shadow_color", Color(0.97, 0.95, 0.89, 0.90))
		label.add_theme_constant_override("shadow_offset_x", 0)
		label.add_theme_constant_override("shadow_offset_y", 1)
		label.add_theme_constant_override("shadow_outline_size", 4)
		canvas.add_child(label)
		name_labels.append(label)
		anchors.append(holder.position + Vector3(0, -0.34, 0.50))

	for _frame: int in range(4):
		await get_tree().process_frame
	for index: int in range(name_labels.size()):
		var label: Label = name_labels[index]
		label.size = label.get_combined_minimum_size()
		var screen_pos: Vector2 = camera.unproject_position(anchors[index])
		label.position = screen_pos - Vector2(label.size.x * 0.5, 0.0)

	for _frame: int in range(24):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw

	DirAccess.make_dir_recursive_absolute("res://outputs")
	var image: Image = get_viewport().get_texture().get_image()
	if image == null:
		push_error("BUILDINGSHOT_FAIL: 视口无纹理")
		get_tree().quit(1)
		return
	var path: String = ProjectSettings.globalize_path("res://outputs/ui_preview_buildings.png")
	var code: int = image.save_png(path)
	print("BUILDINGSHOT_SAVED: %s (%dx%d) code=%d" % [path, image.get_width(), image.get_height(), code])
	get_tree().quit(0 if code == OK else 1)


## 落地投影用的无光照半透明材质：不吃光，任何角度都是同一片淡墨。
static func _flat_shadow() -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(0.34, 0.31, 0.26, 0.085)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material
