class_name CameraRig
extends Node3D

## 取景朝向（文明六同款）：**偏航 0**，让 flat-top 六边形网格的行沿屏幕水平方向排列。
##
## 历史坑：R1 起用的是 `(-45, 45, 0)`——俯角 45° 再偏航 45°，网格在屏幕上斜成一条对角线，
## 玩家看到的是「菱形地图」，且一格只有二十来像素（单位 11px 高），既看不清也点不准。
## Civ VI 的观感是「网格正对镜头、行从左到右」，故偏航归零、俯角略压到 50°。
const PITCH_DEGREES: float = -50.0
const YAW_DEGREES: float = 0.0
## 正交相机的高度（世界单位）。六边形半径 = 1，故 15 ≈ 屏幕纵向 15 格，
## 1080p 下一格约 120px——与 Civ VI 默认缩放同级。
const DEFAULT_VIEW_SIZE: float = 15.0
## 相机沿自身后退轴停放的距离（正交投影下只影响裁剪，不影响缩放）。
const EYE_DISTANCE: float = 70.0

var camera: Camera3D = null
var framed: bool = false
var active: bool = false
var dragging: bool = false
var drag_button: MouseButton = MOUSE_BUTTON_NONE

func _ready() -> void:
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.rotation_degrees = Vector3(PITCH_DEGREES, YAW_DEGREES, 0.0)
	camera.size = DEFAULT_VIEW_SIZE
	camera.near = 0.1
	camera.far = 400.0
	add_child(camera)

func frame_once(center: Vector3, span: float) -> void:
	if framed:
		return
	camera.global_position = center + camera.global_basis.z * EYE_DISTANCE
	camera.size = maxf(span, 8.0)
	framed = true

## 屏幕右方在水平面上的单位向量。偏航 0 时就是 +X；留成函数是为了偏航再次可调时不失配。
static func screen_right() -> Vector3:
	var yaw: float = deg_to_rad(YAW_DEGREES)
	return Vector3(cos(yaw), 0.0, -sin(yaw))

func set_active(enabled: bool) -> void:
	active = enabled
	dragging = false
	camera.current = enabled

func ground_point(screen_position: Vector2) -> Vector3:
	var origin: Vector3 = camera.project_ray_origin(screen_position)
	var direction: Vector3 = camera.project_ray_normal(screen_position)
	if is_zero_approx(direction.y):
		return Vector3(origin.x, 0.0, origin.z)
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
	var current_center: Vector3 = camera.global_position - camera.global_basis.z * EYE_DISTANCE
	camera.global_position += Vector3(target.x - current_center.x, 0.0, target.z - current_center.z)

## 当前取景中心（地面点），供小地图画视口框。
func view_center() -> Vector3:
	return camera.global_position - camera.global_basis.z * EYE_DISTANCE

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
