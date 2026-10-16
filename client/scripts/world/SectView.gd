class_name SectView
extends Node3D
## 势力表现层：R1 渲染灵峰；R3 追加区域与建筑的**占位几何**（无真美术，R8 打磨）。
##
## 只读 view，不推导任何规则；缺失资源由 AssetLibrary 回退，绝不崩溃。
## 每次 `render_view` 全量重建，故 `tile.ownerSectId`/`districtId`/`improvementId` 变化后自然重渲。

## 区域类型 → 占位色（区分功能分区；键取自 `Enums.DistrictType.ALL`）。
const DISTRICT_COLORS: Dictionary = {
	"SHOU_FU_QU": "#c9a24a",
	"XIU_LIAN_QU": "#7f9f7a",
	"DAN_QI_QU": "#b0705a",
	"CANG_JING_QU": "#6f86a6",
	"FA_TAN_QU": "#8f7bb0",
	"SHI_JI_QU": "#a98b53",
}

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
			_render_districts(peak, map, fog, tile_id)
			_render_buildings(peak, map, fog, tile_id)


## 区域占位：优先落在区域自身地块，缺失时环绕主峰铺开（回退不崩）。
func _render_districts(peak: Dictionary, map: HexMap, fog: Fog, peak_tile: String) -> void:
	var districts: Array = peak.get("districts", [])
	var index: int = 0
	for district: Dictionary in districts:
		var district_type: String = str(district.get("type", ""))
		var host_tile: String = str(district.get("tileId", peak_tile))
		if not map.tiles.has(host_tile) or fog.state_for(host_tile) == Fog.State.UNEXPLORED:
			host_tile = peak_tile
		var color: Color = Color.from_string(str(DISTRICT_COLORS.get(district_type, "#9aa08a")), Color("9aa08a"))
		var slab: BoxMesh = BoxMesh.new()
		slab.size = Vector3(0.5, 0.12, 0.5)
		var offset: Vector3 = _ring_offset(index) if host_tile == peak_tile else Vector3.ZERO
		var node: Node3D = Node3D.new()
		node.name = "District_%s" % str(district.get("id", str(index)))
		node.position = map.top_position(host_tile) + offset + Vector3(0, 0.03, 0)
		HexMap.add_mesh(node, "Slab", slab, Vector3.ZERO, HexMap.solid(color))
		var tag: Label3D = Label3D.new()
		tag.text = str(district.get("typeName", district_type))
		tag.font_size = 24
		tag.pixel_size = 0.0032
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.position = Vector3(0, 0.22, 0)
		tag.modulate = color
		node.add_child(tag)
		if fog.state_for(host_tile) == Fog.State.MEMORY:
			fog.apply_memory(node)
		add_child(node)
		index += 1


## 建筑占位：在灵峰旁堆叠小方块（数量即建筑数），缺失回退不崩。
func _render_buildings(peak: Dictionary, map: HexMap, fog: Fog, peak_tile: String) -> void:
	var buildings: Dictionary = peak.get("buildings", {})
	var index: int = 0
	for key: Variant in buildings.keys():
		var info: Dictionary = buildings[key] if typeof(buildings[key]) == TYPE_DICTIONARY else {}
		var box: BoxMesh = BoxMesh.new()
		box.size = Vector3(0.26, 0.34, 0.26)
		var node: Node3D = Node3D.new()
		node.name = "Building_%s" % str(key)
		node.position = map.top_position(peak_tile) + _building_offset(index) + Vector3(0, 0.17, 0)
		HexMap.add_mesh(node, "Box", box, Vector3.ZERO, HexMap.solid(Color("b9a06a")))
		if not info.is_empty() and int(info.get("level", 0)) > 1:
			var crown: PrismMesh = PrismMesh.new()
			crown.size = Vector3(0.3, 0.16, 0.3)
			HexMap.add_mesh(node, "Crown", crown, Vector3(0, 0.25, 0), HexMap.solid(Color("8d7a4e")))
		if fog.state_for(peak_tile) == Fog.State.MEMORY:
			fog.apply_memory(node)
		add_child(node)
		index += 1


static func _ring_offset(index: int) -> Vector3:
	var angle: float = TAU * float(index) / 6.0
	return Vector3(cos(angle) * 0.72, 0.0, sin(angle) * 0.72)


static func _building_offset(index: int) -> Vector3:
	var row: int = index / 3
	var col: int = index % 3
	return Vector3(-0.42 + float(col) * 0.34, 0.0, -0.62 - float(row) * 0.32)
