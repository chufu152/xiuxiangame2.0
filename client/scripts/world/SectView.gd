class_name SectView
extends Node3D
## 势力表现层：灵峰 / 建筑 / 区域 / 宗门旗。
##
## 只读 view，不推导任何规则；缺失资源由 AssetLibrary 回退，绝不崩溃。
## 每次 `render_view` 全量重建，故 `tile.ownerSectId`/`districtId`/`improvementId` 变化后自然重渲。
##
## R8 打磨（对齐参考图）：建筑改为**中式楼阁**——石台基 + 朱红柱 + 米色墙 + 重檐四坡顶
## （青瓦或金瓦）+ 金色宝顶；灵峰旁立**竖幅宗门旗**。全部程序化拼装，不依赖外部模型。
##
## 硬约束：**每座峰只产生一个顶层子节点**（`R1ClientTest` 断言 `SectView.get_child_count()`），
## 旗/区域/建筑一律挂在峰节点之下。

## 区域类型 → 占位色（区分功能分区；键取自 `Enums.DistrictType.ALL`）。
const DISTRICT_COLORS: Dictionary = {
	"SHOU_FU_QU": "#c9a24a",
	"XIU_LIAN_QU": "#7f9f7a",
	"DAN_QI_QU": "#b0705a",
	"CANG_JING_QU": "#6f86a6",
	"FA_TAN_QU": "#8f7bb0",
	"SHI_JI_QU": "#a98b53",
}

## 楼阁配色（对齐参考图：青琉璃瓦 + 金脊 + 朱柱 + 玉台，宣纸工笔调）。
const STONE: Color = Color("c9c4b0")
const WALL: Color = Color("e6dcc4")
const PILLAR: Color = Color("a34a3a")
const TILE_DARK: Color = Color("3f7d8c")
const TILE_GOLD: Color = Color("d8b45a")
const BEAM: Color = Color("6d4a33")
const BANNER_POLE: Color = Color("5a4632")
const JADE_RAIL: Color = Color("dfe3d8")
const WATER: Color = Color("8fb8c4")


func render_view(view: Dictionary, map: HexMap, assets: AssetLibrary, fog: Fog) -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	for sect: Dictionary in view.get("sects", []):
		for peak: Dictionary in sect.get("spiritPeaks", []):
			var tile_id: String = str(peak.get("tileId", ""))
			if not map.tiles.has(tile_id) or fog.state_for(tile_id) == Fog.State.UNEXPLORED:
				continue
			var root: Node3D = Node3D.new()
			root.name = str(peak.get("id", "Peak"))
			root.position = map.top_position(tile_id)
			var sect_color: Color = Color.from_string(str(sect.get("color", "#387f78")), Color("387f78"))
			# 正式模型存在则直接用；缺失（当前状态）则程序化拼一座楼阁。
			var supplied: Node3D = assets.instantiate_model("node.LING_FENG", str(peak.get("name", "灵峰")))
			if supplied.has_meta("placeholder"):
				supplied.free()
				# 主峰楼阁放大到接近「一格宽」，与参考图里建筑占满地块的比例一致。
				_build_pavilion(root, Vector3.ZERO, 1.40, true)
				_build_banner(root, str(sect.get("name", "")), sect_color)
				# 参考图里主峰还有山门、石桥、瀑布三件「门户」构件，只在主峰铺。
				if bool(peak.get("capital", false)):
					_build_gate(root)
					_build_bridge(root)
					_build_waterfall(root)
			else:
				root.add_child(supplied)
			_render_districts(root, peak, map, fog, tile_id)
			_render_buildings(root, peak, map, fog, tile_id)
			if fog.state_for(tile_id) == Fog.State.MEMORY:
				fog.apply_memory(root)
			add_child(root)


# ---------------------------------------------------------------------------
# 中式楼阁（程序化）
# ---------------------------------------------------------------------------

## 一座重檐楼阁：石台基 → 一层柱墙 → 下檐 → 二层柱墙 → 上檐 → 宝顶。
## `tier_scale` 控制整体大小（主峰 1.0，附属建筑 0.62）。
func _build_pavilion(parent: Node3D, offset: Vector3, tier_scale: float, golden_roof: bool) -> void:
	var node: Node3D = Node3D.new()
	node.name = "Pavilion"
	node.position = offset
	node.scale = Vector3.ONE * tier_scale
	# 相机 yaw 45°：把楼阁反向转 45°，正立面才朝向观察者（否则看到的是菱形斜角）。
	node.rotation.y = -PI * 0.25
	parent.add_child(node)

	var base_w: float = 0.80
	var lower_w: float = 0.52
	var lower_h: float = 0.36
	var upper_w: float = 0.34
	var upper_h: float = 0.22
	var base_h: float = 0.12

	# ① 石台基（两级，仿须弥座）+ 玉栏杆。
	_box(node, "Base", Vector3(base_w, base_h, base_w), Vector3(0, base_h / 2.0, 0), STONE)
	_box(node, "BaseTop", Vector3(base_w * 0.86, 0.025, base_w * 0.86), Vector3(0, base_h + 0.012, 0), STONE.lightened(0.10))
	_box(node, "BaseJade", Vector3(base_w * 0.90, 0.016, base_w * 0.90),
		Vector3(0, base_h + 0.032, 0), JADE_RAIL)
	# 四边玉栏杆（细横杆 + 四角望柱），对齐参考图「玉台栏杆」细节。
	for axis: int in range(2):
		for side: float in [-1.0, 1.0]:
			var rail_size: Vector3 = Vector3(base_w * 0.86, 0.022, 0.016) if axis == 0 \
				else Vector3(0.016, 0.022, base_w * 0.86)
			var rail_pos: Vector3 = Vector3(0, base_h + 0.052, side * base_w * 0.42) if axis == 0 \
				else Vector3(side * base_w * 0.42, base_h + 0.052, 0)
			_box(node, "Rail", rail_size, rail_pos, JADE_RAIL)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_box(node, "Post", Vector3(0.024, 0.055, 0.024),
				Vector3(sx * base_w * 0.42, base_h + 0.055, sz * base_w * 0.42), JADE_RAIL.lightened(0.06))

	# ② 一层：米色墙 + 四根朱红柱。
	var wall_y: float = base_h + 0.025
	_box(node, "WallLower", Vector3(lower_w * 0.92, lower_h, lower_w * 0.78), Vector3(0, wall_y + lower_h / 2.0, 0), WALL)
	var pillar_h: float = lower_h + 0.05
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_box(node, "Pillar", Vector3(0.05, pillar_h, 0.05),
				Vector3(sx * lower_w * 0.46, wall_y + pillar_h / 2.0, sz * lower_w * 0.39), PILLAR)
	# 额枋：柱头一圈深色横梁，让檐下有「斗拱」的暗线。
	_box(node, "Beam", Vector3(lower_w * 1.02, 0.035, lower_w * 0.88),
		Vector3(0, wall_y + lower_h + 0.018, 0), BEAM)

	# ③ 下檐（四坡顶，檐口略宽于墙体，形成出檐）。
	var lower_eave_y: float = wall_y + lower_h + 0.035
	var lower_roof_h: float = 0.30
	_roof(node, "RoofLower", lower_w * 1.34, lower_w * 0.12, lower_roof_h, lower_eave_y, TILE_DARK)

	# ④ 二层：起点落在下檐**顶端**（不可塞进锥体内部，否则墙体从瓦面里穿出来），
	# 并在衔接处加一圈薄「平座」，模拟楼阁的腰檐回廊。
	var upper_y: float = lower_eave_y + lower_roof_h
	_box(node, "Balcony", Vector3(upper_w * 1.34, 0.022, upper_w * 1.10),
		Vector3(0, upper_y - 0.010, 0), STONE)
	_box(node, "WallUpper", Vector3(upper_w, upper_h, upper_w * 0.80), Vector3(0, upper_y + upper_h / 2.0, 0), WALL)
	for sx2: float in [-1.0, 1.0]:
		for sz2: float in [-1.0, 1.0]:
			_box(node, "PillarUpper", Vector3(0.038, upper_h, 0.038),
				Vector3(sx2 * upper_w * 0.44, upper_y + upper_h / 2.0, sz2 * upper_w * 0.36), PILLAR)
	var upper_eave_y: float = upper_y + upper_h + 0.02
	var upper_roof_h: float = 0.34
	_roof(node, "RoofUpper", upper_w * 1.16, upper_w * 0.10, upper_roof_h,
		upper_eave_y, TILE_GOLD if golden_roof else TILE_DARK)

	# ⑤ 宝顶（金色球）+ 蓝晶尖塔（参考图里正殿屋脊上最醒目的那道天光）。
	var finial: SphereMesh = SphereMesh.new()
	finial.radius = 0.048
	finial.height = 0.10
	finial.radial_segments = 10
	finial.rings = 5
	var finial_node: MeshInstance3D = HexMap.add_mesh(node, "Finial", finial,
		Vector3(0, upper_eave_y + upper_roof_h + 0.035, 0), HexMap.solid(TILE_GOLD.lightened(0.15)))
	finial_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if golden_roof:
		_build_spire(node, upper_eave_y + upper_roof_h + 0.085, 0.52)


## 蓝晶尖塔：半透明自发光圆锥，叠在宝顶之上（只有主峰正殿才有）。
func _build_spire(parent: Node3D, y: float, height: float) -> void:
	var cone: CylinderMesh = CylinderMesh.new()
	cone.top_radius = 0.007
	cone.bottom_radius = 0.034
	cone.height = height
	cone.radial_segments = 8
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(0.62, 0.90, 0.96, 0.74)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.emission_enabled = true
	material.emission = Color(0.62, 0.90, 0.96)
	material.emission_energy_multiplier = 1.7
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var spire: MeshInstance3D = HexMap.add_mesh(parent, "Spire", cone,
		Vector3(0, y + height * 0.5, 0), material)
	spire.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## 四坡顶：`radial_segments=4` 的圆台旋转 45° 得到「四角攒尖」，再压一层檐口薄板与一道屋脊。
func _roof(parent: Node3D, node_name: String, eave_radius: float, top_radius: float,
		height: float, eave_y: float, color: Color) -> void:
	var cone: CylinderMesh = CylinderMesh.new()
	cone.top_radius = top_radius
	cone.bottom_radius = eave_radius
	cone.height = height
	cone.radial_segments = 4
	cone.rings = 1
	var roof: MeshInstance3D = HexMap.add_mesh(parent, node_name, cone,
		Vector3(0, eave_y + height / 2.0, 0), HexMap.solid(color))
	roof.rotation.y = PI * 0.25
	roof.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# 檐口薄板：把檐线压深一档，45° 俯视时能看到清晰的一圈瓦口。
	var eave: CylinderMesh = CylinderMesh.new()
	eave.top_radius = eave_radius
	eave.bottom_radius = eave_radius * 1.02
	eave.height = 0.028
	eave.radial_segments = 4
	var eave_node: MeshInstance3D = HexMap.add_mesh(parent, node_name + "Eave", eave,
		Vector3(0, eave_y + 0.012, 0), HexMap.solid(color.darkened(0.22)))
	eave_node.rotation.y = PI * 0.25
	eave_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# 屋脊金线：攒尖**顶端**的一道细金棱（压在锥顶而非锥体内，否则看不见）。
	var ridge: BoxMesh = BoxMesh.new()
	ridge.size = Vector3(top_radius * 3.2 + 0.05, 0.030, 0.030)
	var ridge_node: MeshInstance3D = HexMap.add_mesh(parent, node_name + "Ridge", ridge,
		Vector3(0, eave_y + height - 0.012, 0), HexMap.solid(Color("d8b45a")))
	ridge_node.rotation.y = PI * 0.25
	ridge_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## 竖幅宗门旗：细杆 + 顶部横担 + 竖长旗面 + 竖排宗门名。
##
## 朝向：整个 banner 反向转 45°，使旗面的宽面法线正对相机（否则 45° 斜看会把字压扁）。
## 旋转后局部 +z 指向屏幕左方，故横担与旗面沿**局部 z** 铺开，才在屏幕上呈水平。
func _build_banner(parent: Node3D, sect_name: String, sect_color: Color) -> void:
	var banner: Node3D = Node3D.new()
	banner.name = "Banner"
	banner.position = Vector3(0.80, 0.0, -0.74)
	banner.rotation.y = -PI * 0.25
	parent.add_child(banner)
	var pole: CylinderMesh = CylinderMesh.new()
	pole.top_radius = 0.018
	pole.bottom_radius = 0.022
	pole.height = 1.45
	pole.radial_segments = 6
	HexMap.add_mesh(banner, "Pole", pole, Vector3(0, 0.725, 0), HexMap.solid(BANNER_POLE))
	var arm: BoxMesh = BoxMesh.new()
	arm.size = Vector3(0.024, 0.024, 0.38)
	HexMap.add_mesh(banner, "Arm", arm, Vector3(0, 1.41, -0.17), HexMap.solid(BANNER_POLE))
	# 旗面：竖长条，挂在横担下方（宽面法线为局部 ±x，正对相机）。
	var cloth: BoxMesh = BoxMesh.new()
	cloth.size = Vector3(0.024, 0.74, 0.30)
	HexMap.add_mesh(banner, "Cloth", cloth, Vector3(0, 1.02, -0.34), HexMap.solid(sect_color))
	var trim: BoxMesh = BoxMesh.new()
	trim.size = Vector3(0.030, 0.05, 0.31)
	HexMap.add_mesh(banner, "Trim", trim, Vector3(0, 0.64, -0.34), HexMap.solid(Color("d8b45a")))
	if sect_name.is_empty():
		return
	# Label3D 不支持竖排，逐字换行即为竖排效果。
	var chars: PackedStringArray = PackedStringArray()
	for index: int in range(sect_name.length()):
		chars.append(sect_name.substr(index, 1))
	var vertical: String = "\n".join(chars)
	var tag: Label3D = Label3D.new()
	tag.text = vertical
	tag.font_size = 40
	tag.pixel_size = 0.0032
	tag.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	# 父节点已转 -45°；再转 (x=-45°, y=+90°) 后文字平面正好垂直于 45° 俯视的视线，
	# 否则竖排字会被斜视压扁成一排横杠（这是改版时踩过的坑）。
	tag.rotation_degrees = Vector3(-45, 90, 0)
	tag.modulate = Color("f6f1e6")
	tag.outline_size = 0
	# Label3D 以自身位置为**垂直居中**，故与旗面中心对齐，整段字才不会溢出到旗外。
	tag.position = Vector3(0.016, 1.02, -0.34)
	tag.no_depth_test = true
	banner.add_child(tag)


# ---------------------------------------------------------------------------
# 门户构件：山门 / 石桥 / 瀑布（只铺在主峰）
# ---------------------------------------------------------------------------

## 山门：两级石阶 + 双朱柱 + 横匾 + 双坡顶，立在楼阁正前方。
func _build_gate(parent: Node3D) -> void:
	var gate: Node3D = Node3D.new()
	gate.name = "Gate"
	gate.position = Vector3(0, 0.0, 0.94)
	gate.rotation.y = -PI * 0.25
	parent.add_child(gate)
	_box(gate, "Step", Vector3(0.56, 0.045, 0.20), Vector3(0, 0.022, 0), STONE)
	for side: float in [-1.0, 1.0]:
		_box(gate, "Pillar", Vector3(0.062, 0.34, 0.062), Vector3(side * 0.21, 0.21, 0), PILLAR)
		_box(gate, "PillarBase", Vector3(0.092, 0.045, 0.092), Vector3(side * 0.21, 0.068, 0), STONE.darkened(0.10))
	_box(gate, "Plaque", Vector3(0.50, 0.085, 0.05), Vector3(0, 0.365, 0), BEAM)
	_box(gate, "PlaqueFace", Vector3(0.38, 0.052, 0.010), Vector3(0, 0.365, 0.028), TILE_GOLD)
	for side: float in [-1.0, 1.0]:
		var slope: BoxMesh = BoxMesh.new()
		slope.size = Vector3(0.30, 0.018, 0.26)
		var roof: MeshInstance3D = HexMap.add_mesh(gate, "Roof", slope,
			Vector3(side * 0.13, 0.452, 0), HexMap.solid(TILE_DARK))
		roof.rotation_degrees = Vector3(0, 0, side * 17.0)
		roof.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_box(gate, "Ridge", Vector3(0.045, 0.042, 0.26), Vector3(0, 0.486, 0), TILE_GOLD)


## 石桥：桥面 + 两侧栏板 + 三孔拱券，向山门右前方伸出。
func _build_bridge(parent: Node3D) -> void:
	var bridge: Node3D = Node3D.new()
	bridge.name = "Bridge"
	bridge.position = Vector3(0.86, 0.0, 0.62)
	bridge.rotation.y = -PI * 0.25
	parent.add_child(bridge)
	_box(bridge, "Deck", Vector3(0.30, 0.030, 0.62), Vector3(0, 0.115, 0), STONE.lightened(0.06))
	for side: float in [-1.0, 1.0]:
		_box(bridge, "Rail", Vector3(0.020, 0.050, 0.62), Vector3(side * 0.14, 0.150, 0), JADE_RAIL)
	# 三孔拱券：用半圆环近似（薄 Torus 绕 x 轴立起来）。
	for index: int in range(3):
		var arch: TorusMesh = TorusMesh.new()
		arch.inner_radius = 0.040
		arch.outer_radius = 0.056
		arch.rings = 12
		arch.ring_segments = 6
		var node: MeshInstance3D = HexMap.add_mesh(bridge, "Arch", arch,
			Vector3(0, 0.100, -0.20 + float(index) * 0.20), HexMap.solid(STONE.darkened(0.16)))
		node.rotation_degrees = Vector3(90, 0, 0)
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## 瀑布：一道半透明水幕 + 落点水雾，从山体侧面垂落。
func _build_waterfall(parent: Node3D) -> void:
	var fall: Node3D = Node3D.new()
	fall.name = "Waterfall"
	fall.position = Vector3(-0.94, 0.0, 0.50)
	parent.add_child(fall)
	var sheet: BoxMesh = BoxMesh.new()
	sheet.size = Vector3(0.16, 0.62, 0.03)
	var water: StandardMaterial3D = StandardMaterial3D.new()
	water.albedo_color = Color(WATER.r, WATER.g, WATER.b, 0.62)
	water.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water.emission_enabled = true
	water.emission = WATER
	water.emission_energy_multiplier = 0.8
	water.cull_mode = BaseMaterial3D.CULL_DISABLED
	var node: MeshInstance3D = HexMap.add_mesh(fall, "Sheet", sheet, Vector3(0, -0.05, 0), water)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for index: int in range(3):
		var mist: SphereMesh = SphereMesh.new()
		mist.radius = 0.10 + float(index) * 0.05
		mist.height = mist.radius * 1.4
		mist.radial_segments = 10
		mist.rings = 5
		var puff: StandardMaterial3D = StandardMaterial3D.new()
		puff.albedo_color = Color(1.0, 1.0, 1.0, 0.24 - float(index) * 0.05)
		puff.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		var mist_node: MeshInstance3D = HexMap.add_mesh(fall, "Mist", mist,
			Vector3(0, -0.36 - float(index) * 0.03, 0), puff)
		mist_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# ---------------------------------------------------------------------------
# 区域 / 建筑
# ---------------------------------------------------------------------------

## 区域占位：优先落在区域自身地块，缺失时环绕主峰铺开（回退不崩）。
func _render_districts(root: Node3D, peak: Dictionary, map: HexMap, fog: Fog, peak_tile: String) -> void:
	var districts: Array = peak.get("districts", [])
	var index: int = 0
	for district: Dictionary in districts:
		var district_type: String = str(district.get("type", ""))
		var host_tile: String = str(district.get("tileId", peak_tile))
		if not map.tiles.has(host_tile) or fog.state_for(host_tile) == Fog.State.UNEXPLORED:
			host_tile = peak_tile
		var color: Color = Color.from_string(str(DISTRICT_COLORS.get(district_type, "#9aa08a")), Color("9aa08a"))
		var node: Node3D = Node3D.new()
		node.name = "District_%s" % str(district.get("id", str(index)))
		# 区域自身格时用绝对位置（相对峰节点换算），否则环绕主峰。
		var offset: Vector3 = Vector3.ZERO
		if host_tile != peak_tile:
			offset = map.top_position(host_tile) - root.position
		else:
			offset = _ring_offset(index)
		node.position = offset + Vector3(0, 0.03, 0)
		# 区域改用「矮墙围合」而非实心色块，避免把地形整片盖住。
		var slab: BoxMesh = BoxMesh.new()
		slab.size = Vector3(0.46, 0.05, 0.46)
		HexMap.add_mesh(node, "Slab", slab, Vector3(0, 0.02, 0), HexMap.solid(color.lightened(0.42)))
		for sx: float in [-1.0, 1.0]:
			var wall_x: BoxMesh = BoxMesh.new()
			wall_x.size = Vector3(0.46, 0.07, 0.022)
			HexMap.add_mesh(node, "WallX", wall_x, Vector3(0, 0.06, sx * 0.22), HexMap.solid(color))
		for sz: float in [-1.0, 1.0]:
			var wall_z: BoxMesh = BoxMesh.new()
			wall_z.size = Vector3(0.022, 0.07, 0.46)
			HexMap.add_mesh(node, "WallZ", wall_z, Vector3(sz * 0.22, 0.06, 0), HexMap.solid(color))
		var tag: Label3D = Label3D.new()
		tag.text = str(district.get("typeName", district_type))
		tag.font_size = 26
		tag.pixel_size = 0.0028
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.position = Vector3(0, 0.26, 0)
		tag.modulate = color.darkened(0.15)
		node.add_child(tag)
		root.add_child(node)
		index += 1


## 建筑：按 `Enums.Building.ALL` 的类型逐一调用 `Buildings` 工厂（各型各貌，不再一律小楼阁）。
##
## `BUILDING_SCALE` 必须是「缩小件」：`Buildings` 造出来的原型按一格宽（≈1.0）设计，
## 直接放到峰节点下会盖住整个六边形地块、并把主峰楼阁埋进去。0.30 让它们退成主峰
## 身后的附属建筑群，符合参考图「一峰一阁 + 环列小院」的层级。
const BUILDING_SCALE: float = 0.30


func _render_buildings(root: Node3D, peak: Dictionary, map: HexMap, fog: Fog, peak_tile: String) -> void:
	var buildings: Dictionary = peak.get("buildings", {})
	var index: int = 0
	for key: Variant in buildings.keys():
		var info: Dictionary = buildings[key] if typeof(buildings[key]) == TYPE_DICTIONARY else {}
		var level: int = int(info.get("level", 1))
		var node: Node3D = Node3D.new()
		node.name = "Building_%s" % str(key)
		node.position = _building_offset(index)
		node.scale = Vector3.ONE * BUILDING_SCALE
		root.add_child(node)
		Buildings.build(node, str(key), level)
		index += 1


func _box(parent: Node3D, node_name: String, size: Vector3, position_value: Vector3, color: Color) -> MeshInstance3D:
	var box: BoxMesh = BoxMesh.new()
	box.size = size
	var instance: MeshInstance3D = HexMap.add_mesh(parent, node_name, box, position_value, HexMap.solid(color))
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance


static func _ring_offset(index: int) -> Vector3:
	var angle: float = TAU * float(index) / 6.0
	return Vector3(cos(angle) * 0.72, 0.0, sin(angle) * 0.72)


## 建筑成排铺在主峰后方（-z 方向），3 个一行。
static func _building_offset(index: int) -> Vector3:
	var row: int = index / 3
	var col: int = index % 3
	# 与 BUILDING_SCALE=0.30 配套：缩小后的建筑占地约 0.30，故步距 0.30、行距 0.24，
	# 整体向后（-Z）铺成三列，给正面主峰楼阁让出视野。
	return Vector3(-0.30 + float(col) * 0.30, 0.0, -0.42 - float(row) * 0.24)
