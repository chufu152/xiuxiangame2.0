class_name Fog
extends Node

enum State { UNEXPLORED, MEMORY, VISIBLE }

var visible_cells: Dictionary = {}
var explored_cells: Dictionary = {}
var ink_material: ShaderMaterial = null

func configure(view: Dictionary) -> void:
	visible_cells.clear()
	explored_cells.clear()
	for tile_id: String in view.get("visibleTiles", []):
		visible_cells[tile_id] = true
	for tile_id: String in view.get("exploredTiles", []):
		explored_cells[tile_id] = true

func state_for(tile_id: String) -> State:
	if visible_cells.has(tile_id):
		return State.VISIBLE
	if explored_cells.has(tile_id):
		return State.MEMORY
	return State.UNEXPLORED

func memory_material() -> ShaderMaterial:
	if ink_material == null:
		var shader: Shader = Shader.new()
		shader.code = "shader_type spatial; render_mode diffuse_burley; varying vec3 world_pos; void vertex(){world_pos=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;} void fragment(){float line=step(0.87,fract((world_pos.x+world_pos.z+world_pos.y*0.3)*7.0)); ALBEDO=mix(vec3(0.63,0.64,0.60),vec3(0.35,0.38,0.36),line); ROUGHNESS=1.0;}"
		ink_material = ShaderMaterial.new()
		ink_material.shader = shader
	return ink_material

func apply_memory(node: Node) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = memory_material()
	elif node is Label3D:
		(node as Label3D).modulate = Color("61635c")
	for child: Node in node.get_children():
		apply_memory(child)
