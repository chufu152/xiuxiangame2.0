class_name Scenery
extends Node3D
## 水墨远景：地图外围的层叠远山 + 流动云带。
##
## 纯表现层（R8 裁决四/五）：
##   - 不读 `view` 的玩法字段，只按地图包围盒铺景；
##   - 不写任何游戏状态，不产生协议交互；
##   - 不触碰相机（相机铁律）；
##   - 不引入随机源：所有形状/位置由索引哈希派生，同输入必然同输出（确定性铁律）。
##
## 参考图特征：远山越远越淡（向背景色 lerp）、山形层叠、云带横向缓慢漂移、
## 大面积留白。故远景只用「三层山 + 一层云」，越靠外越接近纸色。

## 远山环数（由内到外）。
const MOUNTAIN_RINGS: int = 3
## 每环山数（宜少：多了会连成一堵灰墙，把留白吃掉）。
const MOUNTAINS_PER_RING: int = 10
## 云片数量（宜少不宜多：多了会把画面糊成一片灰）。
const CLOUD_COUNT: int = 8
## 云片横向漂移速度（世界单位/秒）。
const CLOUD_SPEED: float = 0.30

## 远山主色（青灰）。
const MOUNTAIN_INK: Color = Color("7d948c")
## 云片色（宣纸白）。
const CLOUD_INK: Color = Color("fbf7ec")

var _mountains: Array[MeshInstance3D] = []
var _clouds: Array[MeshInstance3D] = []
var _cloud_dirs: Array[float] = []
var _cloud_speeds: Array[float] = []
var _center: Vector3 = Vector3.ZERO
var _span: float = 30.0
var _background: Color = Color("e7e2d3")
var _clock: float = 0.0


## 按取景包围盒铺景。`background` 用于把远山向纸色 lerp（越远越淡）。
func build(bounds: Dictionary, background: Color) -> void:
	_clear()
	_center = bounds.get("center", Vector3.ZERO)
	_span = maxf(float(bounds.get("span", 24.0)), 12.0)
	_background = background
	_build_mountains()
	_build_clouds()


func mountain_count() -> int:
	return _mountains.size()


func cloud_count() -> int:
	return _clouds.size()


func _clear() -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	_mountains.clear()
	_clouds.clear()
	_cloud_dirs.clear()
	_cloud_speeds.clear()


# ---------------------------------------------------------------------------
# 远山
# ---------------------------------------------------------------------------

## 三层环状远山：内环深、外环淡，每座山由 2–3 个六棱锥叠成山形。
##
## 半径以**取景范围**（而非全图）为基准：远山要落在「已探索地块之外、取景之内」，
## 才既能被看见，又不会压在地块上。另只铺**画面远侧半圈**——近侧的山会挡住地块。
func _build_mountains() -> void:
	for ring: int in range(MOUNTAIN_RINGS):
		var radius: float = _span * (0.60 + 0.13 * float(ring))
		var base_height: float = 2.0 - 0.40 * float(ring)
		# 外环向纸色靠拢，制造「远山如黛、渐远渐无」的空气透视。
		# 基准已很淡（0.62 起）：远山只是纸上的一层墨气，不能抢地块。
		var tint: float = 0.62 + 0.12 * float(ring)
		var color: Color = MOUNTAIN_INK.lerp(_background, tint)
		for index: int in range(MOUNTAINS_PER_RING):
			var angle: float = TAU * (float(index) + 0.35 * float(ring)) / float(MOUNTAINS_PER_RING)
			var jitter: float = _hash(index, ring) - 0.5
			var distance: float = radius + jitter * _span * 0.09
			var spot: Vector3 = _center + Vector3(cos(angle) * distance, 0.0, sin(angle) * distance)
			# 相机 yaw 45°：屏幕「上方」对应世界 (-x, -z)。近侧（dx+dz>0）不铺山。
			if (spot.x - _center.x) + (spot.z - _center.z) > _span * 0.16:
				continue
			var height: float = base_height * (0.72 + 0.55 * _hash(index + 91, ring))
			var width: float = height * (0.62 + 0.30 * _hash(index + 17, ring + 5))
			var root: Node3D = Node3D.new()
			root.name = "Mountain_%d_%d" % [ring, index]
			root.position = spot
			add_child(root)
			# 主峰 + 两侧次峰，形成连绵而非孤立尖锥。
			_stack_peak(root, Vector3.ZERO, width, height, color)
			_stack_peak(root, Vector3(width * 0.72, 0.0, width * 0.28),
				width * 0.62, height * 0.58, color.lerp(_background, 0.10))
			_stack_peak(root, Vector3(-width * 0.58, 0.0, width * 0.42),
				width * 0.52, height * 0.46, color.lerp(_background, 0.16))
			for child: Node3D in root.get_children():
				var mesh: MeshInstance3D = child as MeshInstance3D
				if mesh != null:
					_mountains.append(mesh)


func _stack_peak(parent: Node3D, offset: Vector3, width: float, height: float, color: Color) -> void:
	var cone: CylinderMesh = CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = width
	cone.height = height
	cone.radial_segments = 7
	cone.rings = 1
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.roughness = 1.0
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = "Peak"
	instance.mesh = cone
	instance.position = offset + Vector3(0, height / 2.0, 0)
	instance.material_override = material
	# 远山不投影、不接收阴影，避免把地图边缘压暗。
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)


# ---------------------------------------------------------------------------
# 云带
# ---------------------------------------------------------------------------

## 水平云片：从 45° 俯视看是流动的雾带，绕地图外圈缓慢漂移。
func _build_clouds() -> void:
	for index: int in range(CLOUD_COUNT):
		var angle: float = TAU * _hash(index + 3, 11)
		var distance: float = _span * (0.34 + 0.30 * _hash(index + 29, 7))
		var radius: float = _span * (0.04 + 0.06 * _hash(index + 53, 13))
		var disc: CylinderMesh = CylinderMesh.new()
		disc.top_radius = radius
		disc.bottom_radius = radius * 1.08
		disc.height = 0.02
		disc.radial_segments = 12
		# 极淡：只在山水边缘添一层「气」，不能盖住地形。
		var alpha: float = 0.03 + 0.05 * _hash(index + 71, 3)
		var material: StandardMaterial3D = StandardMaterial3D.new()
		material.albedo_color = Color(CLOUD_INK.r, CLOUD_INK.g, CLOUD_INK.b, alpha)
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		var cloud: MeshInstance3D = MeshInstance3D.new()
		cloud.name = "Cloud_%d" % index
		cloud.mesh = disc
		cloud.material_override = material
		cloud.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		cloud.position = _center + Vector3(
			cos(angle) * distance,
			0.45 + 0.75 * _hash(index + 97, 5),
			sin(angle) * distance)
		add_child(cloud)
		_clouds.append(cloud)
		_cloud_dirs.append(1.0 if _hash(index + 101, 2) > 0.35 else -1.0)
		_cloud_speeds.append(CLOUD_SPEED * (0.55 + 0.9 * _hash(index + 131, 17)))


func _process(delta: float) -> void:
	if _clouds.is_empty():
		return
	_clock += delta
	var limit: float = _span * 0.98
	for index: int in range(_clouds.size()):
		var cloud: MeshInstance3D = _clouds[index]
		if not is_instance_valid(cloud):
			continue
		cloud.position.x += _cloud_dirs[index] * _cloud_speeds[index] * delta
		# 越界后从另一侧回卷，保持云带始终覆盖地图外围。
		var offset: float = cloud.position.x - _center.x
		if offset > limit:
			cloud.position.x = _center.x - limit
		elif offset < -limit:
			cloud.position.x = _center.x + limit


## 索引哈希：与 `AssetGen._hash2` 同构，保证远景形状可复现（不读任何随机源）。
static func _hash(x: int, y: int) -> float:
	var h: int = (x * 374761393) ^ (y * 668265263) ^ 0x9e3779b9
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 65535) / 65535.0
