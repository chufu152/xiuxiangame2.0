class_name HexMap
extends Node3D

var tiles: Dictionary = {}
var heights: Dictionary = {}
var river_count: int = 0
var fog: Fog = null
var assets: AssetLibrary = null
var river_keys: Dictionary = {}

func render_view(view: Dictionary, library: AssetLibrary, fog_layer: Fog) -> void:
	assets = library
	fog = fog_layer
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	tiles.clear()
	river_keys.clear()
	river_count = 0
	heights = (view.get("renderHints", {}) as Dictionary).get("reliefHeight", {})
	var data: Dictionary = view.get("tiles", {})
	for tile_id: String in data:
		var tile: Dictionary = data[tile_id]
		var state: Fog.State = fog.state_for(tile_id)
		var height: float = 0.18 if state == Fog.State.UNEXPLORED else float(heights.get(str(tile.get("relief", "")), 1.0))
		var root: Node3D = Node3D.new()
		root.name = tile_id
		root.position = Hex.to_world(int(tile["q"]), int(tile["r"]))
		root.set_meta("height", height)
		root.set_meta("fog_state", state)
		root.set_meta("display_data", {"id": tile_id, "q": tile["q"], "r": tile["r"]} if state == Fog.State.UNEXPLORED else tile.duplicate(true))
		add_child(root)
		tiles[tile_id] = root
		var relief: String = str(tile.get("relief", ""))
		var side_color: Color = Color("677969") if relief == "MOUNTAIN" else Color("a3a38c") if relief == "HILL" else Color("c4bea4")
		var side_material: Material = assets.material_for("terrain.fog.RICE_PAPER", Color("ede8d6")) if state == Fog.State.UNEXPLORED else assets.material_for("terrain.relief.%s_SIDE" % relief, side_color)
		var top_material: Material = assets.material_for("terrain.fog.RICE_PAPER", Color("f1ecdb")) if state == Fog.State.UNEXPLORED else assets.material_for("terrain.base.%s" % str(tile.get("baseTerrain", "")), base_color(str(tile.get("baseTerrain", ""))))
		var side: CylinderMesh = CylinderMesh.new()
		side.top_radius = 1.0
		side.bottom_radius = 1.0
		side.height = height
		side.radial_segments = 6
		side.cap_top = false
		side.cap_bottom = false
		add_mesh(root, "Side", side, Vector3(0, height / 2.0, 0), side_material).rotation.y = PI / 6.0
		var top: CylinderMesh = CylinderMesh.new()
		top.top_radius = 1.0
		top.bottom_radius = 1.0
		top.height = 0.012
		top.radial_segments = 6
		add_mesh(root, "Top", top, Vector3(0, height, 0), top_material).rotation.y = PI / 6.0
		if state == Fog.State.UNEXPLORED:
			continue
		if relief == "MOUNTAIN":
			var cone: CylinderMesh = CylinderMesh.new()
			cone.top_radius = 0.0
			cone.bottom_radius = 1.0
			cone.height = 1.6
			cone.radial_segments = 6
			add_mesh(root, "Mountain", cone, Vector3(0, height + 0.8, 0), assets.material_for("terrain.relief.MOUNTAIN_TOP", Color("6c8c7a"))).rotation.y = PI / 6.0
		for feature: String in tile.get("features", []):
			if feature == "SPIRIT_FOREST":
				var forest: Node3D = Node3D.new()
				forest.name = feature
				forest.position.y = height
				root.add_child(forest)
				var supplied: Node3D = assets.instantiate_model("terrain.feature.SPIRIT_FOREST", "灵林")
				if not supplied.has_meta("placeholder"):
					forest.add_child(supplied)
				else:
					supplied.free()
					for offset: Vector3 in [Vector3(-0.35, 0, -0.2), Vector3(0.25, 0, -0.15), Vector3(0, 0, 0.35)]:
						var tree: CylinderMesh = CylinderMesh.new()
						tree.top_radius = 0.0
						tree.bottom_radius = 0.22
						tree.height = 0.7
						tree.radial_segments = 5
						add_mesh(forest, "Tree", tree, offset + Vector3(0, 0.35, 0), solid(Color("397565")))
			elif feature == "MIRE":
				var mire: Node3D = assets.instantiate_model("terrain.feature.MIRE", "雾泽")
				if mire.has_meta("placeholder"):
					mire.free()
					var patch: CylinderMesh = CylinderMesh.new()
					patch.top_radius = 0.78
					patch.bottom_radius = 0.78
					patch.height = 0.02
					patch.radial_segments = 6
					var wet: StandardMaterial3D = solid(Color(0.46, 0.65, 0.62, 0.64))
					wet.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					add_mesh(root, "MIRE", patch, Vector3(0, height + 0.03, 0), wet).rotation.y = PI / 6.0
				else:
					mire.name = "MIRE"
					mire.position.y = height
					root.add_child(mire)
		if bool(tile.get("danger", false)):
			var danger: PlaneMesh = PlaneMesh.new()
			danger.size = Vector2(0.48, 0.48)
			add_mesh(root, "Danger", danger, Vector3(-0.3, height + 0.055, 0.22), assets.material_for("terrain.danger", Color("a86455")))
		var node_id: String = str(tile.get("nodeId", ""))
		var nodes: Dictionary = view.get("nodes", {})
		if nodes.has(node_id):
			var info: Dictionary = nodes[node_id]
			var model: Node3D = assets.instantiate_model("node.%s" % str(info.get("type", "LING_TIAN")), node_label(str(info.get("type", ""))))
			model.name = "ResourceNode"
			model.position = Vector3(0.28, height, 0.22)
			root.add_child(model)
		var improvement: String = str(tile.get("improvementId", ""))
		var improvements: Dictionary = view.get("improvements", {})
		if improvements.has(improvement):
			var item: Dictionary = improvements[improvement]
			var model: Node3D = assets.instantiate_model("improvement.%s" % str(item.get("type", "")), str(item.get("type", "改良")))
			model.name = "Improvement"
			model.position = Vector3(-0.3, height, 0.2)
			root.add_child(model)
		if state == Fog.State.MEMORY:
			fog.apply_memory(root)
	# 先渲染可见河边，灰图不会覆盖同一边的实景；未探索绝不参与边高推导。
	for state: Fog.State in [Fog.State.VISIBLE, Fog.State.MEMORY]:
		for tile_id: String in data:
			if fog.state_for(tile_id) == state:
				_render_rivers(data[tile_id], state, data)

func _render_rivers(tile: Dictionary, state: Fog.State, data: Dictionary) -> void:
	var q: int = int(tile["q"])
	var r: int = int(tile["r"])
	var height: float = float((tiles[str(tile["id"])] as Node3D).get_meta("height"))
	for edge_value: Variant in tile.get("riverEdges", []):
		var edge: int = int(edge_value)
		var endpoints: Array[Vector3] = Hex.edge_vertices(q, r, edge)
		var a: Vector3 = endpoints[0]
		var b: Vector3 = endpoints[1]
		var left: String = "%.3f,%.3f" % [a.x, a.z]
		var right: String = "%.3f,%.3f" % [b.x, b.z]
		var key: String = left + ":" + right if left < right else right + ":" + left
		if river_keys.has(key):
			continue
		river_keys[key] = true
		var adjacent: Vector2i = Vector2i(q, r) + Hex.DIRECTIONS[edge]
		var adjacent_id: String = Hex.id(adjacent.x, adjacent.y)
		var river_height: float = height
		if data.has(adjacent_id) and fog.state_for(adjacent_id) != Fog.State.UNEXPLORED:
			river_height = maxf(height, float((tiles[adjacent_id] as Node3D).get_meta("height")))
		a.y = river_height + 0.04
		b.y = a.y
		var shape: BoxMesh = BoxMesh.new()
		shape.size = Vector3(0.085, 0.035, a.distance_to(b))
		var river: MeshInstance3D = add_mesh(self, "River", shape, (a + b) / 2.0, assets.material_for("terrain.river", Color("549dad")))
		river.rotation.y = atan2(b.x - a.x, b.z - a.z)
		if state == Fog.State.MEMORY:
			fog.apply_memory(river)
		river_count += 1

func top_position(tile_id: String) -> Vector3:
	var tile: Node3D = tiles[tile_id] as Node3D
	return tile.position + Vector3(0, float(tile.get_meta("height")), 0)

func pick_tile(camera: Camera3D, screen_position: Vector2) -> String:
	var origin: Vector3 = camera.project_ray_origin(screen_position)
	var direction: Vector3 = camera.project_ray_normal(screen_position)
	var best_distance: float = INF
	var picked: String = ""
	for tile_id: String in tiles:
		var top: Vector3 = top_position(tile_id)
		var distance: float = (top.y - origin.y) / direction.y
		if distance < 0.0 or distance >= best_distance:
			continue
		var delta: Vector3 = origin + direction * distance - top
		if absf(delta.z) <= Hex.SQRT3 / 2.0 and Hex.SQRT3 * absf(delta.x) + absf(delta.z) <= Hex.SQRT3:
			best_distance = distance
			picked = tile_id
	return picked

static func base_color(terrain: String) -> Color:
	match terrain:
		"LING_FIELDS": return Color("9bb98b")
		"SPIRIT_PLAIN": return Color("bed0ac")
		"BARREN": return Color("d0b894")
	return Color("ede8d6")

static func node_label(kind: String) -> String:
	return str({"LING_TIAN": "灵田", "LING_MAI": "灵脉", "JI_YUAN": "机缘", "MI_JING": "秘境", "LING_QUAN": "灵泉", "LING_FENG": "灵峰"}.get(kind, kind))

static func solid(color: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	return material

static func add_mesh(parent: Node3D, node_name: String, mesh: Mesh, position_value: Vector3, material: Material) -> MeshInstance3D:
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.position = position_value
	instance.material_override = material
	parent.add_child(instance)
	return instance
