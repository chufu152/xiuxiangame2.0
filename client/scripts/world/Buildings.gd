class_name Buildings
extends RefCounted
## 青云宗建筑群（对齐参考图「青云宗建筑概念设定集」）。
##
## 参考图的六种原型：大殿（重檐 + 金脊 + 青琉璃瓦 + 宝顶 + 玉台栏杆）、
## 藏经阁（三层塔楼）、炼丹楼（高塔 + 药炉）、弟子居所（合院）、
## 阵法台（圆坛 + 光柱）、灵植园（药田 + 水塘）。本文件按 `Enums.Building.ALL`
## 的十个建筑 ID 逐一对应，缺号回退到「大殿」而不是不画。
##
## 全部程序化拼装（`BoxMesh` / `CylinderMesh` / `SphereMesh` / `TorusMesh`），
## 不加载任何外部模型；配色取自参考图的「青琉璃 + 金脊 + 朱柱 + 玉台」四色系。
##
## 朝向：相机在 +X+Z 象限、yaw 45°，故根节点取 `rotation.y = +45°`。
## 这样一来**局部 +X = 屏幕横向**（左右分置的柱子/厢房才会真的左右分开），
## **局部 +Z = 正对相机**（门窗、台阶、香案开在 +Z 才看得见）。
## 早先误写成 `-45°`：局部 ±X 会正好落在视线方向上，山门的两根柱子叠成一根、
## 合院的两侧厢房互相遮挡，正面门窗也全部转到掠射侧棱上。
##
## 高度约定：`_roof()` 返回**实际举高**，调用方一律用返回值累加 Y，
## 不要再用传入的 `height`——否则按檐口半径兜底加高后，上层楼身会插进瓦面里。

# --- 配色（参考图取色）---
const TILE_BLUE: Color = Color("3f7d8c")
const TILE_BLUE_DARK: Color = Color("2c5c69")
const GOLD_RIDGE: Color = Color("d8b45a")
const GOLD_BRIGHT: Color = Color("efd27a")
const PILLAR_RED: Color = Color("a34a3a")
const WALL: Color = Color("e6dcc4")
const JADE_WHITE: Color = Color("dfe3d8")
const STONE: Color = Color("c9c4b0")
const STONE_DARK: Color = Color("a8a390")
const BEAM_DARK: Color = Color("6d4a33")
const WINDOW_TEAL: Color = Color("6b8a86")
const WATER: Color = Color("8fb8c4")
const FIELD_GREEN: Color = Color("8ba86a")
const TREE_GREEN: Color = Color("5f7f63")

## 建筑 ID → 原型（缺号回退「大殿」）。
const ARCHETYPES: Dictionary = {
	"ZONG_ZHU_DA_DIAN": "hall",
	"WANG_CHAO_DI_DU": "palace",
	"CANG_JING_GE": "pagoda",
	"DAN_TANG_FEN_FENG": "alchemy",
	"XIU_LIAN_FEN_FENG": "courtyard",
	"HU_SHAN_JIAN_ZHEN": "altar",
	"QI_TANG_FEN_FENG": "garden",
	"JIANG_DAO_FEN_FENG": "pulpit",
	"ZU_CI": "shrine",
	"SHAN_MEN": "gate",
}


## 造一座建筑，返回根节点（已按相机朝向旋转）。`level` 只影响檐层数与瓦色，不改结构。
static func build(parent: Node3D, building_id: String, level: int = 1) -> Node3D:
	var root: Node3D = Node3D.new()
	root.name = "Building_%s" % building_id
	root.rotation.y = PI * 0.25
	parent.add_child(root)
	var archetype: String = str(ARCHETYPES.get(building_id, "hall"))
	match archetype:
		"palace": _palace(root, level)
		"pagoda": _pagoda(root, level)
		"alchemy": _alchemy(root, level)
		"courtyard": _courtyard(root, level)
		"altar": _altar(root, level)
		"garden": _garden(root, level)
		"pulpit": _pulpit(root, level)
		"shrine": _shrine(root, level)
		"gate": _gate(root, level)
		_: _hall(root, level)
	return root


# ---------------------------------------------------------------------------
# 原型：大殿 / 帝都
# ---------------------------------------------------------------------------

## 大殿：须弥座 + 玉栏杆 + 朱柱米墙 + 重檐青瓦 + 金脊 + 宝顶 + 蓝晶尖塔。
static func _hall(root: Node3D, level: int) -> void:
	_platform(root, 0.92, 0.17, true)
	var base_y: float = 0.17
	_body(root, "Lower", 0.62, 0.30, base_y, 4)
	var eave_y: float = base_y + 0.30 + 0.03
	var r1: float = _roof(root, "RoofLower", 0.50, 0.11, 0.0, eave_y, TILE_BLUE)
	var upper_y: float = eave_y + r1
	_box(root, "Balcony", Vector3(0.42, 0.018, 0.36), Vector3(0, upper_y - 0.009, 0), JADE_WHITE)
	_body(root, "Upper", 0.36, 0.20, upper_y, 4)
	var top_eave: float = upper_y + 0.20 + 0.02
	var r2: float = _roof(root, "RoofUpper", 0.32, 0.08, 0.0, top_eave,
		GOLD_RIDGE if level > 1 else TILE_BLUE)
	_finial(root, top_eave + r2 + 0.030, GOLD_BRIGHT)
	_spire(root, top_eave + r2 + 0.080, 0.40)


## 帝都：三重檐 + 金瓦 + 双层台基 + 双阙。
static func _palace(root: Node3D, _level: int) -> void:
	_platform(root, 1.06, 0.18, true)
	_box(root, "Base2", Vector3(0.80, 0.10, 0.80), Vector3(0, 0.28, 0), STONE.lightened(0.06))
	var base_y: float = 0.33
	_body(root, "Lower", 0.68, 0.28, base_y, 6)
	var eave1: float = base_y + 0.28 + 0.03
	var r1: float = _roof(root, "Roof1", 0.54, 0.15, 0.0, eave1, TILE_BLUE)
	var mid_y: float = eave1 + r1
	_body(root, "Mid", 0.44, 0.22, mid_y, 4)
	var eave2: float = mid_y + 0.22 + 0.02
	var r2: float = _roof(root, "Roof2", 0.38, 0.10, 0.0, eave2, GOLD_RIDGE)
	var top_y: float = eave2 + r2
	_body(root, "Top", 0.26, 0.16, top_y, 4)
	var eave3: float = top_y + 0.16 + 0.02
	var r3: float = _roof(root, "Roof3", 0.24, 0.06, 0.0, eave3, GOLD_RIDGE)
	_finial(root, eave3 + r3 + 0.030, GOLD_BRIGHT)
	_spire(root, eave3 + r3 + 0.080, 0.28)
	# 双阙：台基左右各一座小方楼
	for side: float in [-1.0, 1.0]:
		var tower: Node3D = Node3D.new()
		tower.position = Vector3(side * 0.48, 0, 0.30)
		root.add_child(tower)
		_box(tower, "QueBase", Vector3(0.15, 0.22, 0.15), Vector3(0, 0.11, 0), STONE)
		_box(tower, "QueBody", Vector3(0.11, 0.14, 0.11), Vector3(0, 0.29, 0), WALL)
		_roof(tower, "QueRoof", 0.14, 0.03, 0.0, 0.36, GOLD_RIDGE, 0.50)


# ---------------------------------------------------------------------------
# 藏经阁：三层塔楼
# ---------------------------------------------------------------------------

static func _pagoda(root: Node3D, level: int) -> void:
	_platform(root, 0.66, 0.14, true)
	var y: float = 0.14
	var widths: Array[float] = [0.48, 0.40, 0.32]
	var heights: Array[float] = [0.24, 0.20, 0.16]
	for index: int in range(3):
		var width: float = widths[index]
		_body(root, "Tier%d" % index, width, heights[index], y, 4)
		y += heights[index] + 0.02
		var roof_color: Color = GOLD_RIDGE if (index == 2 or level > 1) else TILE_BLUE
		var rise: float = _roof(root, "TierRoof%d" % index, width * 0.74, width * 0.16, 0.0, y, roof_color, 0.44)
		y += rise
		if index < 2:
			_box(root, "Balcony%d" % index, Vector3(width * 0.84, 0.016, width * 0.84),
				Vector3(0, y - 0.008, 0), JADE_WHITE)
	_finial(root, y + 0.02, GOLD_BRIGHT)


# ---------------------------------------------------------------------------
# 炼丹楼：细高塔 + 塔顶 + 门口药炉
# ---------------------------------------------------------------------------

static func _alchemy(root: Node3D, _level: int) -> void:
	_platform(root, 0.62, 0.12, false)
	var y: float = 0.12
	var shaft: CylinderMesh = CylinderMesh.new()
	shaft.top_radius = 0.14
	shaft.bottom_radius = 0.20
	shaft.height = 0.50
	shaft.radial_segments = 6
	HexMap.add_mesh(root, "Shaft", shaft, Vector3(0, y + 0.25, 0), HexMap.solid(WALL))
	for offset: float in [0.10, 0.30]:
		var band: CylinderMesh = CylinderMesh.new()
		band.top_radius = 0.205
		band.bottom_radius = 0.205
		band.height = 0.020
		band.radial_segments = 6
		HexMap.add_mesh(root, "Band", band, Vector3(0, y + offset, 0), HexMap.solid(GOLD_RIDGE))
	var eave_y: float = y + 0.50
	var rise: float = _roof(root, "TowerRoof", 0.27, 0.05, 0.0, eave_y, TILE_BLUE)
	_finial(root, eave_y + rise + 0.02, GOLD_BRIGHT)
	# 药炉：三足圆鼎 + 炉盖 + 一缕青烟
	var tripod: Node3D = Node3D.new()
	tripod.position = Vector3(0.26, 0.0, 0.16)
	root.add_child(tripod)
	_box(tripod, "FurnaceBase", Vector3(0.17, 0.03, 0.17), Vector3(0, 0.015, 0), STONE_DARK)
	var pot: CylinderMesh = CylinderMesh.new()
	pot.top_radius = 0.062
	pot.bottom_radius = 0.078
	pot.height = 0.10
	pot.radial_segments = 10
	HexMap.add_mesh(tripod, "Furnace", pot, Vector3(0, 0.08, 0), HexMap.solid(BEAM_DARK))
	var lid: CylinderMesh = CylinderMesh.new()
	lid.top_radius = 0.02
	lid.bottom_radius = 0.066
	lid.height = 0.05
	lid.radial_segments = 10
	HexMap.add_mesh(tripod, "Lid", lid, Vector3(0, 0.155, 0), HexMap.solid(GOLD_RIDGE))
	for index: int in range(3):
		var smoke: SphereMesh = SphereMesh.new()
		smoke.radius = 0.026 + float(index) * 0.010
		smoke.height = smoke.radius * 2.0
		smoke.radial_segments = 8
		smoke.rings = 4
		var puff: MeshInstance3D = HexMap.add_mesh(tripod, "Smoke", smoke,
			Vector3(0.01 * float(index), 0.20 + float(index) * 0.055, 0),
			_glow(Color(0.86, 0.90, 0.88), 0.34))
		puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# ---------------------------------------------------------------------------
# 弟子居所：合院（正屋 + 两侧厢房 + 前院矮墙）
# ---------------------------------------------------------------------------

static func _courtyard(root: Node3D, _level: int) -> void:
	_platform(root, 0.80, 0.10, false)
	var main: Node3D = Node3D.new()
	main.position = Vector3(0, 0.10, -0.20)
	root.add_child(main)
	_box(main, "MainBody", Vector3(0.42, 0.16, 0.20), Vector3(0, 0.08, 0), WALL)
	for side: float in [-1.0, 1.0]:
		_box(main, "MainPillar", Vector3(0.026, 0.17, 0.026),
			Vector3(side * 0.18, 0.085, 0.09), PILLAR_RED)
	_roof(main, "MainRoof", 0.30, 0.06, 0.0, 0.17, TILE_BLUE, 0.46)
	for side: float in [-1.0, 1.0]:
		var wing: Node3D = Node3D.new()
		wing.position = Vector3(side * 0.31, 0.10, 0.06)
		root.add_child(wing)
		_box(wing, "WingBody", Vector3(0.15, 0.13, 0.26), Vector3(0, 0.065, 0), WALL)
		_roof(wing, "WingRoof", 0.14, 0.03, 0.0, 0.14, TILE_BLUE, 0.42)
	for side: float in [-1.0, 1.0]:
		_box(root, "YardWall", Vector3(0.26, 0.07, 0.022),
			Vector3(side * 0.25, 0.135, 0.30), STONE.lightened(0.08))
	_box(root, "YardGate", Vector3(0.16, 0.10, 0.026), Vector3(0, 0.15, 0.30), PILLAR_RED)
	var table: CylinderMesh = CylinderMesh.new()
	table.top_radius = 0.045
	table.bottom_radius = 0.045
	table.height = 0.016
	table.radial_segments = 10
	HexMap.add_mesh(root, "Table", table, Vector3(0, 0.155, 0.10), HexMap.solid(STONE))


# ---------------------------------------------------------------------------
# 阵法台：圆坛 + 双层圆环 + 光柱
# ---------------------------------------------------------------------------

static func _altar(root: Node3D, _level: int) -> void:
	for index: int in range(3):
		var radius: float = 0.42 - float(index) * 0.09
		var disc: CylinderMesh = CylinderMesh.new()
		disc.top_radius = radius
		disc.bottom_radius = radius * 1.04
		disc.height = 0.06
		disc.radial_segments = 16
		HexMap.add_mesh(root, "Tier%d" % index, disc,
			Vector3(0, 0.03 + 0.06 * float(index), 0),
			HexMap.solid(JADE_WHITE.darkened(0.06 + float(index) * 0.08)))
	# 坛面青玉盘（把白盘压出「法阵」的青色圆心）
	var face: CylinderMesh = CylinderMesh.new()
	face.top_radius = 0.24
	face.bottom_radius = 0.24
	face.height = 0.012
	face.radial_segments = 16
	HexMap.add_mesh(root, "Face", face, Vector3(0, 0.192, 0), HexMap.solid(Color("7fb3ad")))
	for index: int in range(2):
		var ring: TorusMesh = TorusMesh.new()
		ring.inner_radius = 0.15 + float(index) * 0.09
		ring.outer_radius = 0.168 + float(index) * 0.09
		ring.rings = 20
		ring.ring_segments = 8
		var node: MeshInstance3D = HexMap.add_mesh(root, "Ring%d" % index, ring,
			Vector3(0, 0.200 + float(index) * 0.003, 0), _glow(Color(0.56, 0.86, 0.92), 0.80))
		node.rotation_degrees = Vector3(90, 0, 0)
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for pair: Array in [[0.078, 0.24], [0.040, 0.38]]:
		var beam: CylinderMesh = CylinderMesh.new()
		beam.top_radius = float(pair[0])
		beam.bottom_radius = float(pair[0]) * 1.10
		beam.height = float(pair[1])
		beam.radial_segments = 12
		var pillar: MeshInstance3D = HexMap.add_mesh(root, "Beam", beam,
			Vector3(0, 0.20 + float(pair[1]) * 0.5, 0), _glow(Color(0.72, 0.94, 0.98), 0.24))
		pillar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# ---------------------------------------------------------------------------
# 灵植园：药田格 + 水塘 + 树
# ---------------------------------------------------------------------------

static func _garden(root: Node3D, _level: int) -> void:
	_box(root, "Soil", Vector3(0.78, 0.03, 0.78), Vector3(0, 0.015, 0), Color("9a8a63"))
	for row: int in range(3):
		for col: int in range(3):
			if row == 0 and col == 2:
				continue
			var x: float = -0.23 + float(col) * 0.23
			var z: float = -0.23 + float(row) * 0.23
			var shade: Color = FIELD_GREEN.lightened(0.10) if (row + col) % 2 == 0 else FIELD_GREEN
			_box(root, "Plot", Vector3(0.18, 0.035, 0.18), Vector3(x, 0.045, z), shade)
	var pond: CylinderMesh = CylinderMesh.new()
	pond.top_radius = 0.135
	pond.bottom_radius = 0.135
	pond.height = 0.02
	pond.radial_segments = 14
	HexMap.add_mesh(root, "Pond", pond, Vector3(0.25, 0.030, -0.25), _glow(WATER, 0.90))
	for pair: Array in [[-0.27, 0.27, 0.080], [0.02, -0.31, 0.058], [0.31, 0.06, 0.050]]:
		var x: float = float(pair[0])
		var z: float = float(pair[1])
		var radius: float = float(pair[2])
		var trunk: CylinderMesh = CylinderMesh.new()
		trunk.top_radius = 0.010
		trunk.bottom_radius = 0.014
		trunk.height = 0.10
		trunk.radial_segments = 6
		HexMap.add_mesh(root, "Trunk", trunk, Vector3(x, 0.08, z), HexMap.solid(BEAM_DARK))
		var crown: SphereMesh = SphereMesh.new()
		crown.radius = radius
		crown.height = radius * 1.7
		crown.radial_segments = 10
		crown.rings = 5
		HexMap.add_mesh(root, "Crown", crown, Vector3(x, 0.15 + radius * 0.5, z), HexMap.solid(TREE_GREEN))


# ---------------------------------------------------------------------------
# 讲道台：方台 + 伞盖
# ---------------------------------------------------------------------------

static func _pulpit(root: Node3D, _level: int) -> void:
	_box(root, "Stage", Vector3(0.58, 0.10, 0.58), Vector3(0, 0.05, 0), STONE)
	_box(root, "StageTop", Vector3(0.50, 0.020, 0.50), Vector3(0, 0.110, 0), JADE_WHITE)
	var pole: CylinderMesh = CylinderMesh.new()
	pole.top_radius = 0.014
	pole.bottom_radius = 0.018
	pole.height = 0.40
	pole.radial_segments = 8
	HexMap.add_mesh(root, "Pole", pole, Vector3(-0.19, 0.31, -0.19), HexMap.solid(BEAM_DARK))
	var rise: float = _roof(root, "Canopy", 0.36, 0.06, 0.0, 0.50, TILE_BLUE, 0.34)
	_finial(root, 0.50 + rise + 0.02, GOLD_BRIGHT)
	_box(root, "Seat", Vector3(0.14, 0.08, 0.12), Vector3(0, 0.16, 0), PILLAR_RED)
	_box(root, "Desk", Vector3(0.20, 0.05, 0.09), Vector3(0, 0.135, 0.18), BEAM_DARK)


# ---------------------------------------------------------------------------
# 祖祠：单檐 + 供桌 + 香炉
# ---------------------------------------------------------------------------

static func _shrine(root: Node3D, _level: int) -> void:
	_platform(root, 0.62, 0.12, false)
	_body(root, "Hall", 0.46, 0.22, 0.12, 4)
	var rise: float = _roof(root, "HallRoof", 0.36, 0.07, 0.0, 0.36, TILE_BLUE, 0.56)
	_finial(root, 0.36 + rise + 0.02, GOLD_RIDGE)
	_box(root, "Altar", Vector3(0.24, 0.06, 0.10), Vector3(0, 0.16, 0.22), BEAM_DARK)
	var censer: CylinderMesh = CylinderMesh.new()
	censer.top_radius = 0.036
	censer.bottom_radius = 0.044
	censer.height = 0.055
	censer.radial_segments = 10
	HexMap.add_mesh(root, "Censer", censer, Vector3(0, 0.218, 0.22), HexMap.solid(GOLD_RIDGE))
	for side: float in [-1.0, 1.0]:
		var lamp: SphereMesh = SphereMesh.new()
		lamp.radius = 0.020
		lamp.height = 0.036
		lamp.radial_segments = 8
		lamp.rings = 4
		var node: MeshInstance3D = HexMap.add_mesh(root, "Lamp", lamp,
			Vector3(side * 0.16, 0.19, 0.24), _glow(Color(0.98, 0.82, 0.52), 0.85))
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# ---------------------------------------------------------------------------
# 山门：双柱 + 横匾 + 双坡顶
# ---------------------------------------------------------------------------

static func _gate(root: Node3D, _level: int) -> void:
	_box(root, "Step", Vector3(0.66, 0.05, 0.26), Vector3(0, 0.025, 0), STONE)
	for side: float in [-1.0, 1.0]:
		_box(root, "GatePillar", Vector3(0.070, 0.38, 0.070),
			Vector3(side * 0.25, 0.24, 0), PILLAR_RED)
		_box(root, "GateBase", Vector3(0.10, 0.05, 0.10), Vector3(side * 0.25, 0.075, 0), STONE_DARK)
	_box(root, "Plaque", Vector3(0.58, 0.095, 0.055), Vector3(0, 0.405, 0), BEAM_DARK)
	_box(root, "PlaqueFace", Vector3(0.44, 0.058, 0.010), Vector3(0, 0.405, 0.032), GOLD_RIDGE)
	# 双坡顶：两块斜置薄板拼「人」字，比四坡锥更贴合「山门」形制。
	for side: float in [-1.0, 1.0]:
		var slope: BoxMesh = BoxMesh.new()
		slope.size = Vector3(0.36, 0.018, 0.28)
		var node: MeshInstance3D = HexMap.add_mesh(root, "GateRoof", slope,
			Vector3(side * 0.155, 0.510, 0), HexMap.solid(TILE_BLUE))
		node.rotation_degrees = Vector3(0, 0, -side * 18.0)
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_box(root, "Ridge", Vector3(0.05, 0.05, 0.28), Vector3(0, 0.560, 0), GOLD_RIDGE)


# ---------------------------------------------------------------------------
# 通用零件
# ---------------------------------------------------------------------------

## 台基：一层须弥座；`balustrade` 为真时沿四边加玉栏杆与四角望柱。
static func _platform(root: Node3D, width: float, height: float, balustrade: bool) -> void:
	_box(root, "Base", Vector3(width, height, width), Vector3(0, height * 0.5, 0), STONE)
	_box(root, "BaseLip", Vector3(width * 1.05, 0.020, width * 1.05),
		Vector3(0, height - 0.010, 0), STONE_DARK)
	_box(root, "BaseTop", Vector3(width * 0.94, 0.016, width * 0.94),
		Vector3(0, height + 0.008, 0), JADE_WHITE)
	_box(root, "Steps", Vector3(width * 0.28, height * 0.55, 0.10),
		Vector3(0, height * 0.275, width * 0.5 + 0.03), STONE.lightened(0.06))
	if not balustrade:
		return
	var half: float = width * 0.5
	for axis: int in range(2):
		for side: float in [-1.0, 1.0]:
			var size: Vector3 = Vector3(width * 0.96, 0.028, 0.020) if axis == 0 \
				else Vector3(0.020, 0.028, width * 0.96)
			var offset: Vector3 = Vector3(0, height + 0.030, side * half * 0.94) if axis == 0 \
				else Vector3(side * half * 0.94, height + 0.030, 0)
			_box(root, "Rail", size, offset, JADE_WHITE)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_box(root, "Post", Vector3(0.028, 0.056, 0.028),
				Vector3(sx * half * 0.94, height + 0.044, sz * half * 0.94), JADE_WHITE.lightened(0.05))


## 一层楼身：米墙 + 朱柱 + 柱头额枋 + 正面板门与槛窗。
static func _body(root: Node3D, tag: String, width: float, height: float, base_y: float,
		pillars: int) -> void:
	_box(root, tag + "Wall", Vector3(width * 0.92, height, width * 0.80),
		Vector3(0, base_y + height * 0.5, 0), WALL)
	# 正面门窗开在**局部 +Z 面**（正对相机的那面）。缺了这层细节，45° 下整面墙
	# 就是一块米色平板，十座建筑远看会糊成同一种色块。
	var face_z: float = width * 0.40 + 0.006
	_box(root, tag + "Door", Vector3(width * 0.19, height * 0.60, 0.012),
		Vector3(0, base_y + height * 0.30, face_z), BEAM_DARK)
	for side: float in [-1.0, 1.0]:
		_box(root, tag + "Window", Vector3(width * 0.16, height * 0.32, 0.012),
			Vector3(side * width * 0.27, base_y + height * 0.56, face_z), WINDOW_TEAL)
	var pillar_h: float = height + 0.04
	var half_x: float = width * 0.46
	var half_z: float = width * 0.40
	if pillars <= 4:
		for sx: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				_box(root, tag + "Pillar", Vector3(0.040, pillar_h, 0.040),
					Vector3(sx * half_x, base_y + pillar_h * 0.5, sz * half_z), PILLAR_RED)
	else:
		for sx: float in [-1.0, 0.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				_box(root, tag + "Pillar", Vector3(0.038, pillar_h, 0.038),
					Vector3(sx * half_x * 0.86, base_y + pillar_h * 0.5, sz * half_z), PILLAR_RED)
	_box(root, tag + "Beam", Vector3(width * 0.98, 0.028, width * 0.86),
		Vector3(0, base_y + height + 0.014, 0), BEAM_DARK)


## 四坡攒尖顶：`radial_segments=4` 的圆台转 45° + 檐口压深 + 四角翘檐 + 金脊。返回**实际举高**。
##
## `pitch` 是「举高 / 檐口半径」的兜底比，默认 0.66（≈33° 中式坡顶）。
## 小体量构件（合院厢房、塔层、讲道台伞盖）必须传更小的值：檐口 0.30 配 0.66
## 会举高 0.198，比它下面 0.16 高的墙还高，看着像顶帐篷而不是屋顶。
static func _roof(root: Node3D, tag: String, eave_radius: float, top_radius: float,
		height: float, eave_y: float, color: Color, pitch: float = 0.66) -> float:
	var rise: float = maxf(height, eave_radius * pitch)
	var cone: CylinderMesh = CylinderMesh.new()
	cone.top_radius = top_radius
	cone.bottom_radius = eave_radius
	cone.height = rise
	cone.radial_segments = 4
	cone.rings = 1
	var roof: MeshInstance3D = HexMap.add_mesh(root, tag, cone,
		Vector3(0, eave_y + rise * 0.5, 0), HexMap.solid(color))
	roof.rotation.y = PI * 0.25
	roof.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# 檐口压深：一圈略外扩的薄盘，把瓦面与墙身之间「切」出一道暗边，
	# 没有这道边，坡顶会和下面的米墙糊成一片，45° 下就只剩一块蓝板。
	var eave: CylinderMesh = CylinderMesh.new()
	eave.top_radius = eave_radius
	eave.bottom_radius = eave_radius * 1.04
	eave.height = 0.020
	eave.radial_segments = 4
	var eave_node: MeshInstance3D = HexMap.add_mesh(root, tag + "Eave", eave,
		Vector3(0, eave_y + 0.009, 0),
		HexMap.solid(TILE_BLUE_DARK if color != GOLD_RIDGE else GOLD_RIDGE.darkened(0.30)))
	eave_node.rotation.y = PI * 0.25
	eave_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# 四角翘檐：中式坡顶最强的辨识点。四片小板从**四个转角**（±X±Z 对角）向外伸出、
	# 外端上翘 30°，让屋檐在 45° 俯视下不再是一条死板直线。
	# 注意必须挂在转角上：屋面转 45° 后顶点在对角方向，若把翘角摆在 ±X/±Z 就落在
	# 檐面正中间，四片小板会从瓦面中部横着扎出来，轮廓变成一个「蝴蝶结」。
	var tip_length: float = maxf(eave_radius * 0.34, 0.07)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var pivot: Node3D = Node3D.new()
			pivot.position = Vector3(sx * eave_radius * 0.7071, eave_y + 0.024,
				sz * eave_radius * 0.7071)
			# 让 pivot 的 +X 指向「朝外」的对角方向（rotation.y 把 +X 映射到 (cosθ,0,-sinθ)）。
			pivot.rotation.y = atan2(-sz, sx)
			root.add_child(pivot)
			var tip: BoxMesh = BoxMesh.new()
			tip.size = Vector3(tip_length, 0.016, 0.062)
			var node: MeshInstance3D = HexMap.add_mesh(pivot, tag + "Tip", tip,
				Vector3(tip_length * 0.42, 0.0, 0.0), HexMap.solid(color))
			node.rotation_degrees = Vector3(0, 0, 30.0)
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var ridge: BoxMesh = BoxMesh.new()
	ridge.size = Vector3(top_radius * 3.0 + 0.04, 0.022, 0.022)
	var ridge_node: MeshInstance3D = HexMap.add_mesh(root, tag + "Ridge", ridge,
		Vector3(0, eave_y + rise - 0.008, 0), HexMap.solid(GOLD_RIDGE))
	ridge_node.rotation.y = PI * 0.25
	ridge_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return rise


## 宝顶：金色球。
static func _finial(root: Node3D, y: float, color: Color) -> void:
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = 0.038
	sphere.height = 0.080
	sphere.radial_segments = 10
	sphere.rings = 5
	var node: MeshInstance3D = HexMap.add_mesh(root, "Finial", sphere, Vector3(0, y, 0), HexMap.solid(color))
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## 蓝晶尖塔：屋脊上那根「天光」尖锥（参考图里最醒目的辨识点）。
static func _spire(root: Node3D, y: float, height: float) -> void:
	var cone: CylinderMesh = CylinderMesh.new()
	cone.top_radius = 0.006
	cone.bottom_radius = 0.028
	cone.height = height
	cone.radial_segments = 8
	var node: MeshInstance3D = HexMap.add_mesh(root, "Spire", cone,
		Vector3(0, y + height * 0.5, 0), _glow(Color(0.62, 0.90, 0.96), 0.78))
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## 半透明自发光材质（光柱 / 法阵环 / 尖塔 / 香火用）。
static func _glow(color: Color, alpha: float) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(color.r, color.g, color.b, alpha)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 1.6
	material.roughness = 0.6
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


static func _box(parent: Node3D, tag: String, size: Vector3, position_value: Vector3,
		color: Color) -> MeshInstance3D:
	var box: BoxMesh = BoxMesh.new()
	box.size = size
	var node: MeshInstance3D = HexMap.add_mesh(parent, tag, box, position_value, HexMap.solid(color))
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node
