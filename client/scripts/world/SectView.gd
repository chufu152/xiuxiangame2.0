class_name SectView
extends Node3D

func render_view(view: Dictionary, map: HexMap, assets: AssetLibrary, fog: Fog) -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	for sect: Dictionary in view.get("sects", []):
		for peak: Dictionary in sect.get("spiritPeaks", []):
			var tile_id: String = str(peak.get("tileId", ""))
			if not map.tiles.has(tile_id) or fog.state_for(tile_id) == Fog.State.UNEXPLORED:
				continue
			# 隐藏峰仅消费服务端已经冻结的 snapshot，不查其他宗的当前实体。
			var model: Node3D = assets.instantiate_model("node.LING_FENG", str(peak.get("name", "灵峰")))
			model.name = str(peak.get("id", "Peak"))
			model.position = map.top_position(tile_id)
			if model.has_meta("placeholder"):
				var shape: BoxMesh = BoxMesh.new()
				shape.size = Vector3(0.72, 0.65, 0.55)
				var mesh: MeshInstance3D = model.get_child(0) as MeshInstance3D
				mesh.mesh = shape
				mesh.position.y = 0.325
				mesh.material_override = HexMap.solid(Color.from_string(str(sect.get("color", "#387f78")), Color("387f78")))
				var roof: PrismMesh = PrismMesh.new()
				roof.size = Vector3(0.9, 0.3, 0.72)
				HexMap.add_mesh(model, "Roof", roof, Vector3(0, 0.8, 0), HexMap.solid(Color("426d62")))
				(model.get_child(1) as Label3D).position.y = 1.15
			if fog.state_for(tile_id) == Fog.State.MEMORY:
				fog.apply_memory(model)
			add_child(model)
