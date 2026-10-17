class_name CameraRig
extends Node3D

var camera: Camera3D = null
var framed: bool = false
var active: bool = false
var dragging: bool = false
var drag_button: MouseButton = MOUSE_BUTTON_NONE

func _ready() -> void:
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.rotation_degrees = Vector3(-45.0, 45.0, 0.0)
	camera.size = 24.0
	camera.near = 0.1
	camera.far = 400.0
	add_child(camera)

func frame_once(center: Vector3, span: float) -> void:
	if framed:
		return
	camera.global_position = center + camera.global_basis.z * 70.0
	camera.size = maxf(span, 12.0)
	framed = true

func set_active(enabled: bool) -> void:
	active = enabled
	dragging = false
	camera.current = enabled

func ground_point(screen_position: Vector2) -> Vector3:
	var origin: Vector3 = camera.project_ray_origin(screen_position)
	var direction: Vector3 = camera.project_ray_normal(screen_position)
	return origin + direction * (-origin.y / direction.y)

func zoom_at(screen_position: Vector2, factor: float) -> void:
	var anchor: Vector3 = ground_point(screen_position)
	camera.size = clampf(camera.size * factor, 4.0, 120.0)
	camera.global_position += anchor - ground_point(screen_position)

func pan_between(previous: Vector2, current: Vector2) -> void:
	camera.global_position += ground_point(previous) - ground_point(current)

## 平移到指定地面点（小地图跳转用）：**只平移**，不改 `rotation`、不改 `size`。
## 这是 R8 相机铁律的显式实现——任何「跳转」都不得顺手重置取景。
func pan_to(target: Vector3) -> void:
	var current_center: Vector3 = camera.global_position - camera.global_basis.z * 70.0
	camera.global_position += Vector3(target.x - current_center.x, 0.0, target.z - current_center.z)

## 当前取景中心（地面点），供小地图画视口框。
func view_center() -> Vector3:
	return camera.global_position - camera.global_basis.z * 70.0

func view_size() -> float:
	return camera.size

func _input(event: InputEvent) -> void:
	# 按键释放即便落在侧栏也结束拖拽，避免镜头继续跟随。
	if event is InputEventMouseButton and not event.pressed and event.button_index == drag_button:
		dragging = false
		drag_button = MOUSE_BUTTON_NONE

func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventMouseButton:
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			zoom_at(event.position, 0.88 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 0.88)
			get_viewport().set_input_as_handled()
		elif event.button_index in [MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT]:
			dragging = event.pressed
			drag_button = event.button_index if event.pressed else MOUSE_BUTTON_NONE
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and dragging:
		pan_between(event.position - event.relative, event.position)
		get_viewport().set_input_as_handled()
