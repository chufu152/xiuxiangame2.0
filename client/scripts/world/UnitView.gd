class_name UnitView
extends Node3D

func render_view(view: Dictionary, map: HexMap, assets: AssetLibrary, fog: Fog) -> void:
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
			add_child(model)
