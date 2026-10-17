class_name AssetLibrary
extends Node

signal manifest_reloaded()

var entries: Dictionary = {}
var cache: Dictionary = {}
var warned: Dictionary = {}
var warning_count: int = 0
var generation: int = 0
var asset_root: String = ""
var manifest_path: String = ""

func _ready() -> void:
	asset_root = Launcher.repo_root().path_join("assets")
	manifest_path = asset_root.path_join("manifest.json")
	reload_manifest()

func reload_manifest() -> void:
	var file: FileAccess = FileAccess.open(manifest_path, FileAccess.READ)
	if file == null:
		_warn_once("manifest", "无法读取资源清单")
		return
	var parser: JSON = JSON.new()
	if parser.parse(file.get_as_text()) != OK or not parser.data is Dictionary:
		_warn_once("manifest", "资源清单不是有效 JSON 对象")
		return
	var data: Dictionary = parser.data
	if int(data.get("schemaVersion", 0)) != 3:
		_warn_once("manifest", "资源清单需要 schemaVersion 3")
		return
	entries.clear()
	for value: Variant in data.values():
		if value is Array:
			for entry: Variant in value:
				if entry is Dictionary and entry.has("id") and entry.has("path"):
					var item: Dictionary = entry.duplicate(true)
					var pack: String = str(data.get("activePack", "default"))
					item["path"] = str(item["path"]).replace("art/default/", "art/%s/" % pack)
					entries[str(item["id"])] = item
	cache.clear()
	generation += 1
	manifest_reloaded.emit()

func resource_for(logical_id: String, expected_type: String = "texture") -> Resource:
	var key: String = logical_id + ":" + expected_type
	if cache.has(key):
		return cache[key] as Resource
	var entry: Dictionary = entries.get(logical_id, {})
	var resource: Resource = null
	var relative: String = str(entry.get("path", ""))
	var path: String = asset_root.path_join(relative).simplify_path()
	if not relative.is_empty() and path.begins_with(asset_root.simplify_path() + "/") and FileAccess.file_exists(path):
		resource = _load_external(path, str(entry.get("type", expected_type)))
	if resource is AudioStream and bool(entry.get("loop", false)):
		# manifest 的 `loop` 字段由库兑现：`AudioStreamWAV` 用 `loop_mode` 枚举，
		# `AudioStreamOggVorbis`/`MP3` 用布尔 `loop`，两者键名不同，故按存在性分派。
		if "loop_mode" in resource:
			resource.set("loop_mode", AudioStreamWAV.LOOP_FORWARD)
		elif "loop" in resource:
			resource.set("loop", true)
	if not _matches(resource, expected_type):
		_warn_once(logical_id, "缺失或不可用资源，使用占位：" + relative)
		resource = _fallback(expected_type)
	cache[key] = resource
	return resource

func _load_external(path: String, kind: String) -> Resource:
	match kind:
		"texture":
			var image: Image = Image.new()
			if image.load(path) == OK:
				return ImageTexture.create_from_image(image)
		"model":
			if path.get_extension().to_lower() in ["glb", "gltf"]:
				var document: GLTFDocument = GLTFDocument.new()
				var state: GLTFState = GLTFState.new()
				if document.append_from_file(path, state) == OK:
					var scene: Node = document.generate_scene(state)
					if scene != null:
						var packed: PackedScene = PackedScene.new()
						_own_children(scene, scene)
						var error: Error = packed.pack(scene)
						scene.free()
						if error == OK:
							return packed
		"audio":
			# 必须走 `load_from_file`：`asset_root` 是**绝对文件系统路径**（`Launcher.repo_root()/assets`），
			# 而 `ResourceLoader` 只认 `res://`，所以以前用 `ResourceLoader.load(path)` 永远返回 null，
			# 音频/字体这两类资源「文件明明在，却一直 WARN」。`load_from_*` 接受绝对路径。
			var extension: String = path.get_extension().to_lower()
			if extension == "wav":
				return AudioStreamWAV.load_from_file(path)
			if extension == "ogg":
				return AudioStreamOggVorbis.load_from_file(path)
			if extension == "mp3":
				return AudioStreamMP3.load_from_file(path)
		"font":
			# 同上：字体也走 `FontFile.load_dynamic_font()`，不能用 ResourceLoader。
			if path.get_extension().to_lower() in ["ttf", "otf"]:
				var font: FontFile = FontFile.new()
				if font.load_dynamic_font(path) == OK:
					return font
		"material", "particle":
			# 材质/粒子仍只支持 `res://` 内的 .tres/.res（当前 manifest 未使用）。
			if path.get_extension().to_lower() in ["tres", "res", "gdshader"]:
				if ResourceLoader.exists(path):
					return ResourceLoader.load(path)
	return null

func _own_children(node: Node, root: Node) -> void:
	for child: Node in node.get_children():
		child.owner = root
		_own_children(child, root)

func _matches(resource: Resource, kind: String) -> bool:
	match kind:
		"model": return resource is PackedScene
		"texture": return resource is Texture2D
		"material": return resource is Material or resource is Shader
		"font": return resource is Font
		"audio": return resource is AudioStream
		"particle": return resource != null
	return resource != null

func _fallback(kind: String) -> Resource:
	match kind:
		"texture":
			var image: Image = Image.create(2, 2, false, Image.FORMAT_RGBA8)
			image.fill(Color.WHITE)
			return ImageTexture.create_from_image(image)
		"font": return ThemeDB.fallback_font
		"material", "particle": return StandardMaterial3D.new()
	return null

func material_for(logical_id: String, color: Color) -> Material:
	var entry: Dictionary = entries.get(logical_id, {})
	if str(entry.get("type", "texture")) == "material":
		var supplied: Resource = resource_for(logical_id, "material")
		if supplied is Material:
			return supplied as Material
		if supplied is Shader:
			var shader_material: ShaderMaterial = ShaderMaterial.new()
			shader_material.shader = supplied as Shader
			return shader_material
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.albedo_texture = resource_for(logical_id, "texture") as Texture2D
	material.roughness = 1.0
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	return material

func instantiate_model(logical_id: String, label_text: String = "") -> Node3D:
	var resource: Resource = resource_for(logical_id, "model")
	if resource is PackedScene:
		var instance: Node = (resource as PackedScene).instantiate()
		if instance is Node3D:
			return instance as Node3D
		instance.free()
	var root: Node3D = Node3D.new()
	root.set_meta("placeholder", true)
	var mesh: MeshInstance3D = MeshInstance3D.new()
	var shape: PrismMesh = PrismMesh.new()
	shape.size = Vector3(0.45, 0.6, 0.45)
	mesh.mesh = shape
	mesh.position.y = 0.3
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color("6d7470")
	mesh.material_override = material
	root.add_child(mesh)
	var label: Label3D = Label3D.new()
	label.text = label_text if not label_text.is_empty() else logical_id.get_slice(".", 1)
	label.font_size = 32
	label.pixel_size = 0.008
	label.position.y = 0.9
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color("253b37")
	root.add_child(label)
	return root

func _warn_once(logical_id: String, message: String) -> void:
	if warned.has(logical_id):
		return
	warned[logical_id] = true
	warning_count += 1
	push_warning("[AssetLibrary] WARN %s：%s" % [logical_id, message])

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F5:
		reload_manifest()
		get_viewport().set_input_as_handled()
