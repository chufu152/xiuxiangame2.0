class_name UnitView
extends Node3D
## 单位表现层（R2：新增选中标记）。
##
## 位置一律以服务端 `view` 的 `tileId` 为准，**不做任何本地位置推导**；
## 标记只是底座描边，不改变权威位置。

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


func render_view(view: Dictionary, map: HexMap, assets: AssetLibrary, fog: Fog, selected_id: String = "") -> void:
	selected_disciple_id = selected_id
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	for sect: Dictionary in view.get("sects", []):
		var offsets: Dictionary = {}
		for disciple: Dictionary in sect.get("disciples", []):
			var tile_id: String = str(disciple.get("tileId", ""))
			if not map.tiles.has(tile_id) or fog.state_for(tile_id) != Fog.State.VISIBLE:
				continue
			var unit_class: String = str(disciple.get("unitClass", Enums.UnitClass.PU_TONG))
			var model: Node3D = assets.instantiate_model("unit.%s" % unit_class, str(disciple.get("name", "弟子")))
			model.name = str(disciple.get("id", "Disciple"))
			var offset: int = int(offsets.get(tile_id, 0))
			offsets[tile_id] = offset + 1
			model.position = map.top_position(tile_id) + Vector3(-0.4 + offset * 0.34, 0, -0.35)
			if model.has_meta("placeholder"):
				var mesh: MeshInstance3D = model.get_child(0) as MeshInstance3D
				mesh.material_override = HexMap.solid(Color.from_string(str(sect.get("color", "#387f78")), Color("387f78")))
				_apply_class_silhouette(mesh, unit_class)
			if str(disciple.get("id", "")) == selected_disciple_id:
				_attach_marker(model)
			add_child(model)


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
