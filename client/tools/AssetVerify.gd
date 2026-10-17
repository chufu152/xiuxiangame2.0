extends Node
## 「最小水墨资源包」验收器（ROADMAP §3.2 验收方式）。
##
## 直接用客户端的 `AssetLibrary` 按 `manifest.json` 的逻辑 ID 逐个取资源，
## 断言最小包资产**全部命中实体文件、零 WARN**；同时打印**仍然回退占位**的分组
## （R9 之后只剩 `fonts`）——那是裁决二要求的「未覆盖 ID 仍回退且不崩」。
##
## 运行：
##   Godot_v4.4.1-stable_win64_console.exe --headless --path client res://tools/AssetVerify.tscn
##
## 输出契约：
##   `ASSETVERIFY_OK covered=75 warned=0`  全绿
##   `ASSETVERIFY_FAIL ...`                有 ID 未命中
##
## 注意：集合按 **manifest 分组名**选取，不按 ID 前缀——`terrain.feature.*` 虽然以
## `terrain.` 开头，但归属 `features` 分组（地貌模型），R9 W1 起已纳入最小包。

## 最小水墨资源包覆盖的 manifest 分组（= ROADMAP §3.2 八类清单）。
const MINIMAL_GROUPS: Array[String] = [
	"terrain",       # 基底顶面 / 海拔侧面 / 山体顶面 / 河流 / 险地 / 三态迷雾（11）
	"units",         # 10 兵种
	"buildings",     # 10 建筑
	"resources",     # 13 资源图标
	"realms",        # 5 境界图标
	"factions",      # 3 势力图标
	"districts",     # 6 区域（R9 W1）
	"improvements",  # 8 改良（R9 W1）
	"features",      # 8 地貌/节点（R9 W1）
	"audio",         # 1 背景音（R9 W1）
]
## 最小包应有 ID 数（manifest 共 77，减去 `fonts` 的 2 个待美术项）。
const EXPECTED_MINIMAL: int = 75

var _library: AssetLibrary = null
var _failures: Array[String] = []
## 目标皮肤包（`--pack=<name>`）。空 = 用 manifest 的 `activePack`。
var _pack: String = ""


func _ready() -> void:
	_library = AssetLibrary.new()
	_library.name = "AssetLibrary"
	add_child(_library)

	_pack = _read_arg("--pack=", "")
	if not _pack.is_empty() and not _library.set_pack(_pack):
		printerr("[AssetVerify] 皮肤包不存在：%s" % _pack)
		print("ASSETVERIFY_FAIL pack=%s" % _pack)
		get_tree().quit(1)
		return
	print("[AssetVerify] 皮肤包：%s（%s）" % [_library.active_pack, _library.asset_root])

	var groups: Dictionary = _manifest_groups()
	if groups.is_empty():
		printerr("[AssetVerify] 无法读取 assets/manifest.json")
		print("ASSETVERIFY_FAIL manifest")
		get_tree().quit(1)
		return

	var minimal: Array[String] = []
	var fallback_ids: Array[String] = []
	for group_name: String in groups.keys():
		var ids: Array[String] = _ids_of(groups, group_name)
		if MINIMAL_GROUPS.has(group_name):
			minimal.append_array(ids)
		else:
			fallback_ids.append_array(ids)
	minimal.sort()
	fallback_ids.sort()

	var covered: int = 0
	for logical_id: String in minimal:
		var entry: Dictionary = _library.entries.get(logical_id, {})
		if entry.is_empty():
			_failures.append("%s：AssetLibrary 未登记该 ID" % logical_id)
			continue
		var expected_type: String = str(entry.get("type", "texture"))
		var before: int = _library.warning_count
		var resource: Resource = _library.resource_for(logical_id, expected_type)
		if resource == null:
			_failures.append("%s：返回 null（type=%s）" % [logical_id, expected_type])
			continue
		if _library.warning_count > before:
			_failures.append("%s：触发了 WARN（%s）" % [logical_id, str(entry.get("path", ""))])
			continue
		covered += 1

	# 未覆盖分组：必须「回退占位 + 不崩」，此处只统计不判失败（裁决二）。
	var placeholder_count: int = 0
	for logical_id: String in fallback_ids:
		var entry: Dictionary = _library.entries.get(logical_id, {})
		if entry.is_empty():
			continue
		_library.resource_for(logical_id, str(entry.get("type", "texture")))
		placeholder_count += 1

	var fallback_groups: Array[String] = []
	for group_name: String in groups.keys():
		if not MINIMAL_GROUPS.has(group_name):
			fallback_groups.append(group_name)
	fallback_groups.sort()

	print("[AssetVerify] 最小包 ID 命中 %d / %d，WARN 总数 %d"
		% [covered, minimal.size(), _library.warning_count])
	print("[AssetVerify] 未覆盖分组仍回退占位 %d 个（%s）"
		% [placeholder_count, ", ".join(fallback_groups)])

	_check_model_bounds(minimal)

	if _failures.is_empty() and covered == minimal.size() and minimal.size() == EXPECTED_MINIMAL:
		print("ASSETVERIFY_OK covered=%d warned=0 pack=%s" % [covered, _library.active_pack])
		get_tree().quit(0)
		return
	for message: String in _failures:
		printerr("[AssetVerify] %s" % message)
	print("ASSETVERIFY_FAIL covered=%d expected=%d pack=%s"
		% [covered, minimal.size(), _library.active_pack])
	get_tree().quit(1)


static func _read_arg(prefix: String, fallback: String) -> String:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with(prefix):
			return arg.substr(prefix.length())
	for arg: String in OS.get_cmdline_args():
		if arg.begins_with(prefix):
			return arg.substr(prefix.length())
	return fallback


## 读取 manifest 原始分组（分组名 → 条目数组）。`AssetLibrary` 只保留扁平表，
## 这里需要分组信息来精确划定「最小包」范围，故直接读原始 JSON。
func _manifest_groups() -> Dictionary:
	var manifest_path: String = Launcher.repo_root().path_join("assets").path_join("manifest.json")
	var file: FileAccess = FileAccess.open(manifest_path, FileAccess.READ)
	if file == null:
		return {}
	var parser: JSON = JSON.new()
	if parser.parse(file.get_as_text()) != OK or not parser.data is Dictionary:
		return {}
	var data: Dictionary = parser.data
	var groups: Dictionary = {}
	for key: Variant in data.keys():
		if not data[key] is Array:
			continue
		groups[str(key)] = data[key]
	return groups


func _ids_of(groups: Dictionary, group_name: String) -> Array[String]:
	var ids: Array[String] = []
	var entries: Variant = groups.get(group_name, [])
	if not entries is Array:
		return ids
	for entry: Variant in entries:
		if entry is Dictionary and entry.has("id"):
			ids.append(str(entry["id"]))
	return ids


## 模型几何合理性：非退化、底面锚点在 y≈0、六边形格（半径 1.0）内不溢出。
## 纯尺寸校验，不做视觉判断（观感留人工核验清单）。
func _check_model_bounds(ids: Array[String]) -> void:
	var checked: int = 0
	for logical_id: String in ids:
		if not logical_id.begins_with("unit.") and not logical_id.begins_with("building.") \
				and not logical_id.begins_with("district.") and not logical_id.begins_with("improvement.") \
				and not logical_id.begins_with("node.") and not logical_id.begins_with("terrain.feature."):
			continue
		var resource: Resource = _library.resource_for(logical_id, "model")
		if not resource is PackedScene:
			continue
		var instance: Node = (resource as PackedScene).instantiate()
		if not instance is Node3D:
			instance.free()
			continue
		var root: Node3D = instance as Node3D
		var bounds: AABB = _aabb_of(root)
		var size: Vector3 = bounds.size
		checked += 1
		if size.x <= 0.01 or size.y <= 0.01 or size.z <= 0.01:
			_failures.append("%s：模型退化（尺寸 %s）" % [logical_id, str(size)])
		elif bounds.position.y < -0.05:
			_failures.append("%s：底面低于地面（minY=%.3f）" % [logical_id, bounds.position.y])
		elif size.x > 1.75 or size.z > 1.75:
			_failures.append("%s：横向溢出六边形格（%s）" % [logical_id, str(size)])
		elif logical_id.begins_with("unit.") and size.y > 1.4:
			_failures.append("%s：单位过高（y=%.2f）" % [logical_id, size.y])
		root.free()
	print("[AssetVerify] 模型几何校验 %d 个（单位 ≤1.4 高、建筑 ≤1.75 宽、底面锚 y≈0）" % checked)


## 精确包围盒：逐三角形顶点做变换后求极值。
## 不能用 `transform * mesh.get_aabb()`——那会把旋转后的轴对齐盒再取包围盒，
## 45° 旋转的攒尖顶会被放大约 1.41 倍，导致误判「横向溢出」。
func _aabb_of(root: Node3D) -> AABB:
	var minimum: Vector3 = Vector3(INF, INF, INF)
	var maximum: Vector3 = Vector3(-INF, -INF, -INF)
	var found: bool = false
	for child: Node in root.get_children():
		if not child is MeshInstance3D:
			continue
		var mesh_instance: MeshInstance3D = child as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		var transform: Transform3D = mesh_instance.transform
		for point: Vector3 in mesh_instance.mesh.get_faces():
			var world: Vector3 = transform * point
			minimum = Vector3(minf(minimum.x, world.x), minf(minimum.y, world.y), minf(minimum.z, world.z))
			maximum = Vector3(maxf(maximum.x, world.x), maxf(maximum.y, world.y), maxf(maximum.z, world.z))
			found = true
	if not found:
		return AABB()
	return AABB(minimum, maximum - minimum)

