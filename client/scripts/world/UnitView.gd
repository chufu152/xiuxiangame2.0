class_name UnitView
extends Node3D
## 单位表现层（R2：新增选中标记）。
##
## 位置一律以服务端 `view` 的 `tileId` 为准，**不做任何本地位置推导**；
## 标记只是底座描边，不改变权威位置。

## 当前选中的弟子 id（空串 = 未选中）。
var selected_disciple_id: String = ""


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
			var model: Node3D = assets.instantiate_model("unit.%s" % str(disciple.get("unitClass", "PU_TONG")), str(disciple.get("name", "弟子")))
			model.name = str(disciple.get("id", "Disciple"))
			var offset: int = int(offsets.get(tile_id, 0))
			offsets[tile_id] = offset + 1
			model.position = map.top_position(tile_id) + Vector3(-0.4 + offset * 0.34, 0, -0.35)
			if model.has_meta("placeholder"):
				var mesh: MeshInstance3D = model.get_child(0) as MeshInstance3D
				mesh.material_override = HexMap.solid(Color.from_string(str(sect.get("color", "#387f78")), Color("387f78")))
			if str(disciple.get("id", "")) == selected_disciple_id:
				_attach_marker(model)
			add_child(model)


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
