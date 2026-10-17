class_name UnitView
extends Node3D
## 单位表现层（R2：新增选中标记；R8：改为「小人」形象）。
##
## 位置一律以服务端 `view` 的 `tileId` 为准，**不做任何本地位置推导**；
## 标记只是底座描边，不改变权威位置。
##
## 硬约束：
##   - **每个弟子只产生一个顶层子节点**，根节点 `position.y` 恒等于格顶面高度
##     （`R1ClientTest` 断言 `position.y == 1.7`）；
##   - 影子/袍/躯干/头一律挂在根节点之下，不额外占顶层计数；
##   - `_apply_class_silhouette` 仍是「十兵种互不相同」的唯一出口
##     （`R5ClientTest` 直接调它并比对 `(mesh class, aabb.size)`）。

## 当前选中的弟子 id（空串 = 未选中）。
var selected_disciple_id: String = ""

## 十兵种占位剪影（R5）：正式模型缺失时按兵种给出可区分的轮廓，避免十种兵种长得一样。
## 纯表现层数据，**不参与任何玩法判定**（兵种数值一律来自服务端 view / 规则层）。
## 值 = [形状, 尺寸]：prism=三棱柱（凡人）/ box=方柱 / sphere=球 / cylinder=圆柱 / cone=锥。
const PLACEHOLDER_SHAPES: Dictionary = {
	Enums.UnitClass.PU_TONG: ["prism", Vector3(0.45, 0.60, 0.45)],
	Enums.UnitClass.JIAN_XIU: ["box", Vector3(0.12, 0.96, 0.12)],
	Enums.UnitClass.FA_XIU: ["sphere", Vector3(0.30, 0.60, 0.30)],
	Enums.UnitClass.TI_XIU: ["box", Vector3(0.58, 0.50, 0.58)],
	Enums.UnitClass.QI_JI: ["cylinder", Vector3(0.36, 0.46, 0.36)],
	Enums.UnitClass.FU_XIU: ["box", Vector3(0.36, 0.54, 0.07)],
	Enums.UnitClass.JI_GUAN: ["box", Vector3(0.44, 0.74, 0.44)],
	Enums.UnitClass.JIAN_ZHEN_SHI: ["cone", Vector3(0.42, 0.74, 0.42)],
	Enums.UnitClass.XUE_MAI_XIU_SHI: ["sphere", Vector3(0.34, 0.72, 0.34)],
	Enums.UnitClass.JI_GUAN_JUN_TUAN: ["box", Vector3(0.64, 0.56, 0.64)],
}

## 肤色（宣纸工笔的暖白）。
const SKIN: Color = Color("e8d5b8")
## 影子色。
const SHADOW: Color = Color(0.18, 0.22, 0.20, 0.26)


func render_view(view: Dictionary, map: HexMap, assets: AssetLibrary, fog: Fog, selected_id: String = "") -> void:
	selected_disciple_id = selected_id
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	for sect: Dictionary in view.get("sects", []):
		var offsets: Dictionary = {}
		var sect_color: Color = Color.from_string(str(sect.get("color", "#387f78")), Color("387f78"))
		for disciple: Dictionary in sect.get("disciples", []):
			var tile_id: String = str(disciple.get("tileId", ""))
			if not map.tiles.has(tile_id) or fog.state_for(tile_id) != Fog.State.VISIBLE:
				continue
			var unit_class: String = str(disciple.get("unitClass", Enums.UnitClass.PU_TONG))
			var disciple_id: String = str(disciple.get("id", "Disciple"))
			var model: Node3D = assets.instantiate_model("unit.%s" % unit_class, str(disciple.get("name", "弟子")))
			if model.has_meta("placeholder"):
				model.free()
				model = Node3D.new()
				model.name = disciple_id
				_build_figure(model, unit_class, sect_color)
			else:
				model.name = disciple_id
			var offset: int = int(offsets.get(tile_id, 0))
			offsets[tile_id] = offset + 1
			model.position = map.top_position(tile_id) + Vector3(-0.34 + offset * 0.30, 0, -0.30)
			if disciple_id == selected_disciple_id:
				_attach_marker(model)
			add_child(model)


# ---------------------------------------------------------------------------
# 小人形象（程序化）
# ---------------------------------------------------------------------------

## 一个小人：椭圆影 + 宗门色袍摆 + 兵种躯干 + 头 + 发冠。
## 躯干形状走 `_apply_class_silhouette`，故十兵种在画面里仍可区分。
func _build_figure(parent: Node3D, unit_class: String, sect_color: Color) -> void:
	var spec: Array = PLACEHOLDER_SHAPES.get(unit_class, PLACEHOLDER_SHAPES[Enums.UnitClass.PU_TONG])
	var size: Vector3 = spec[1]
	# 身高/体宽按兵种微调：重甲更矮壮、剑修更瘦高。
	var height: float = 0.56 + size.y * 0.20
	var width: float = 0.10 + size.x * 0.13

	# ① 影子：贴地扁圆，让单位「站」在格面上而不是飘着。
	var shadow_mesh: CylinderMesh = CylinderMesh.new()
	shadow_mesh.top_radius = width * 1.35
	shadow_mesh.bottom_radius = width * 1.55
	shadow_mesh.height = 0.006
	shadow_mesh.radial_segments = 10
	var shadow_material: StandardMaterial3D = HexMap.solid(SHADOW)
	shadow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shadow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var shadow: MeshInstance3D = HexMap.add_mesh(parent, "Shadow", shadow_mesh,
		Vector3(0, 0.012, 0), shadow_material)
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# ② 袍摆：下宽上窄的圆台，用宗门色，一眼分辨敌我。
	var robe: CylinderMesh = CylinderMesh.new()
	robe.top_radius = width * 0.62
	robe.bottom_radius = width * 1.18
	robe.height = height * 0.46
	robe.radial_segments = 8
	var robe_color: Color = sect_color.lerp(Color("f2ece0"), 0.18)
	HexMap.add_mesh(parent, "Robe", robe, Vector3(0, height * 0.23, 0), HexMap.solid(robe_color))

	# ③ 躯干：形状来自十兵种剪影表（缩放后作为上半身）。
	var torso: MeshInstance3D = MeshInstance3D.new()
	torso.name = "Torso"
	parent.add_child(torso)
	_apply_class_silhouette(torso, unit_class)
	torso.scale = Vector3.ONE * 0.46
	torso.position = Vector3(0, height * 0.62, 0)
	torso.material_override = HexMap.solid(robe_color.darkened(0.12))
	torso.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# ④ 头 + 发冠（小方块），工笔人物的「一点」。
	var head_mesh: SphereMesh = SphereMesh.new()
	head_mesh.radius = height * 0.105
	head_mesh.height = height * 0.21
	head_mesh.radial_segments = 10
	head_mesh.rings = 6
	HexMap.add_mesh(parent, "Head", head_mesh, Vector3(0, height * 0.90, 0), HexMap.solid(SKIN))
	var crown: BoxMesh = BoxMesh.new()
	crown.size = Vector3(height * 0.16, height * 0.055, height * 0.16)
	HexMap.add_mesh(parent, "Crown", crown, Vector3(0, height * 1.00, 0), HexMap.solid(robe_color.darkened(0.32)))


## 把占位网格换成该兵种的剪影（仅占位资源生效；正式模型原样保留）。
static func _apply_class_silhouette(mesh: MeshInstance3D, unit_class: String) -> void:
	var spec: Array = PLACEHOLDER_SHAPES.get(unit_class, PLACEHOLDER_SHAPES[Enums.UnitClass.PU_TONG])
	var size: Vector3 = spec[1]
	var height: float = size.y
	match str(spec[0]):
		"box":
			var box: BoxMesh = BoxMesh.new()
			box.size = size
			mesh.mesh = box
		"sphere":
			var sphere: SphereMesh = SphereMesh.new()
			sphere.radius = size.x / 2.0
			sphere.height = height
			mesh.mesh = sphere
		"cylinder":
			var cylinder: CylinderMesh = CylinderMesh.new()
			cylinder.top_radius = size.x / 2.0
			cylinder.bottom_radius = size.x / 2.0
			cylinder.height = height
			cylinder.radial_segments = 6
			mesh.mesh = cylinder
		"cone":
			var cone: CylinderMesh = CylinderMesh.new()
			cone.top_radius = 0.0
			cone.bottom_radius = size.x / 2.0
			cone.height = height
			cone.radial_segments = 6
			mesh.mesh = cone
		_:
			var prism: PrismMesh = PrismMesh.new()
			prism.size = size
			mesh.mesh = prism
	# 占位网格以原点为中心，抬高半个身高使其立在格面上（与 AssetLibrary 的默认 0.3 对齐）。
	mesh.position.y = height / 2.0


## 当前渲染出的单位数（供自动验收断言）。
func unit_count() -> int:
	return get_child_count()


## 某个兵种当前渲染出的单位数（供自动验收断言：十兵种剪影互不相同）。
func count_of_class(view: Dictionary, unit_class: String) -> int:
	var total: int = 0
	for sect: Dictionary in view.get("sects", []):
		for disciple: Dictionary in sect.get("disciples", []):
			if str(disciple.get("unitClass", Enums.UnitClass.PU_TONG)) == unit_class:
				total += 1
	return total


## 只切换选中标记，不重建单位（供点选时立即反馈）。
func set_selected(disciple_id: String) -> void:
	if selected_disciple_id == disciple_id:
		return
	selected_disciple_id = disciple_id
	for child: Node in get_children():
		var model: Node3D = child as Node3D
		if model == null:
			continue
		var has_marker: bool = model.has_node("SelectionMarker")
		var should_have: bool = not selected_disciple_id.is_empty() and str(model.name) == selected_disciple_id
		if should_have and not has_marker:
			_attach_marker(model)
		elif has_marker and not should_have:
			model.get_node("SelectionMarker").queue_free()


## 当前带选中标记的单位数（供自动验收断言）。
func marker_count() -> int:
	var total: int = 0
	for child: Node in get_children():
		if (child as Node3D) != null and child.has_node("SelectionMarker"):
			total += 1
	return total


func _attach_marker(model: Node3D) -> void:
	var ring: CylinderMesh = CylinderMesh.new()
	ring.top_radius = 0.42
	ring.bottom_radius = 0.42
	ring.height = 0.05
	ring.radial_segments = 6
	var marker: MeshInstance3D = HexMap.add_mesh(model, "SelectionMarker", ring, Vector3(0, 0.02, 0), HexMap.solid(Color("d8a33c")))
	marker.rotation.y = PI / 6.0
