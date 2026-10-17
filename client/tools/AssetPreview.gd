extends Node
## 模型联络表（contact sheet）：把最小资源包里的 20 个 `.glb` 软件渲染成一张 PNG，
## 供人工核验「轮廓是否可辨、比例是否合理、底面是否落地」。
##
## 为什么不用引擎渲染：`--headless` 无渲染设备，开窗口又会污染验收流程。
## 这里用等距正交投影 + z-buffer 做纯 CPU 光栅化，**零渲染依赖、结果确定**。
##
## 运行：
##   Godot_v4.4.1-stable_win64_console.exe --headless --path client res://tools/AssetPreview.tscn
##
## 输出：`outputs/r8_asset_models.png`（5 列 × 4 行，每格左上角为序号）
## 序号 → 模型对照见运行日志，同时写入 `outputs/r8_asset_models_index.txt`。

const CELL: int = 148
const COLS: int = 5
const MARGIN: int = 8
const PAPER_BG: Color = Color("efe9d8")
const CELL_BG: Color = Color("e3dcc8")
const BORDER: Color = Color("b8b09a")
const LABEL: Color = Color("253b37")

## 3×5 点阵数字（0–9），用于在格角标注序号。
const DIGITS: Array = [
	["111", "101", "101", "101", "111"],
	["010", "110", "010", "010", "111"],
	["111", "001", "111", "100", "111"],
	["111", "001", "111", "001", "111"],
	["101", "101", "111", "001", "001"],
	["111", "100", "111", "001", "111"],
	["111", "100", "111", "101", "111"],
	["111", "001", "010", "010", "010"],
	["111", "101", "111", "101", "111"],
	["111", "101", "111", "001", "111"],
]

var _models: Array[String] = []
var _paths: Array[String] = []
var _out_dir: String = ""
## 目标皮肤包名。
var _pack: String = "default"


func _ready() -> void:
	_out_dir = Launcher.repo_root().path_join("outputs")
	DirAccess.make_dir_recursive_absolute(_out_dir)
	# `--pack=<name>` 可对第二套皮肤包出联络表（默认 default）。
	_pack = _read_arg("--pack=", "default")
	var art_root: String = Launcher.repo_root().path_join("assets").path_join("art").path_join(_pack)

	for unit_name: String in ["pu_tong", "jian_xiu", "fa_xiu", "ti_xiu", "qi_ji",
			"fu_xiu", "ji_guan", "jian_zhen_shi", "xue_mai_xiu_shi", "ji_guan_jun_tuan"]:
		_models.append("unit." + unit_name.to_upper())
		_paths.append(art_root.path_join("units").path_join(unit_name + ".glb"))
	for building_name: String in ["shan_men", "zong_zhu_da_dian", "cang_jing_ge", "xiu_lian_fen_feng",
			"dan_tang_fen_feng", "qi_tang_fen_feng", "jiang_dao_fen_feng", "hu_shan_jian_zhen",
			"zu_ci", "wang_chao_di_du"]:
		_models.append("building." + building_name.to_upper())
		_paths.append(art_root.path_join("buildings").path_join(building_name + ".glb"))

	var rows: int = int(ceil(float(_models.size()) / float(COLS)))
	var width: int = MARGIN + COLS * (CELL + MARGIN)
	var height: int = MARGIN + rows * (CELL + MARGIN)
	var sheet: Image = Image.create(width, height, false, Image.FORMAT_RGBA8)
	sheet.fill(PAPER_BG)

	var index_lines: Array[String] = []
	var rendered: int = 0
	for index: int in range(_models.size()):
		var triangles: Array = _load_triangles(_paths[index])
		var cell_x: int = MARGIN + (index % COLS) * (CELL + MARGIN)
		var cell_y: int = MARGIN + int(index / COLS) * (CELL + MARGIN)
		var cell_image: Image = Image.create(CELL, CELL, false, Image.FORMAT_RGBA8)
		cell_image.fill(CELL_BG)
		if triangles.is_empty():
			printerr("[AssetPreview] 空模型：%s（%s）" % [_models[index], _paths[index]])
		else:
			_rasterize(cell_image, triangles)
			rendered += 1
		_frame(cell_image)
		_stamp_number(cell_image, index + 1)
		sheet.blit_rect(cell_image, Rect2i(0, 0, CELL, CELL), Vector2i(cell_x, cell_y))
		index_lines.append("%2d  %s" % [index + 1, _models[index]])

	var sheet_path: String = _out_dir.path_join("r8_asset_models_%s.png" % _pack)
	var error: Error = sheet.save_png(sheet_path)
	if error != OK:
		printerr("[AssetPreview] 写出失败 %s（Error %d）" % [sheet_path, error])
		print("ASSETPREVIEW_FAIL")
		get_tree().quit(1)
		return

	var index_path: String = _out_dir.path_join("r8_asset_models_index_%s.txt" % _pack)
	var index_file: FileAccess = FileAccess.open(index_path, FileAccess.WRITE)
	if index_file != null:
		index_file.store_string("\n".join(index_lines) + "\n")
		index_file.close()

	print("[AssetPreview] 渲染 %d / %d 个模型 → %s" % [rendered, _models.size(), sheet_path])
	for line: String in index_lines:
		print("  " + line)

	_compose_icon_sheet(art_root)
	_compose_terrain_sheet(art_root)

	print("ASSETPREVIEW_OK rendered=%d" % rendered)
	get_tree().quit(0)


## 21 个 UI 图标拼成一张 7×3 联络表（图标本身已带透明底，铺在宣纸色上）。
func _compose_icon_sheet(art_root: String) -> void:
	var names: Array[String] = [
		"resource_spirit_power", "resource_spirit_stones", "resource_work_power", "resource_prestige",
		"resource_qi_yun", "resource_food", "resource_dao_points", "resource_tian_jing",
		"resource_xuan_tie", "resource_ling_mu", "resource_ling_cha", "resource_yun_jin",
		"resource_ling_yu", "realm_lian_qi", "realm_zhu_ji", "realm_jin_dan",
		"realm_yuan_ying", "realm_hua_shen", "faction_zong_men", "faction_jia_zu", "faction_guo_jia",
	]
	var cell: int = 72
	var columns: int = 7
	var rows: int = int(ceil(float(names.size()) / float(columns)))
	var sheet: Image = Image.create(MARGIN + columns * (cell + MARGIN), MARGIN + rows * (cell + MARGIN),
		false, Image.FORMAT_RGBA8)
	sheet.fill(PAPER_BG)
	for index: int in range(names.size()):
		var path: String = art_root.path_join("icons").path_join(names[index] + ".png")
		var icon: Image = Image.new()
		if icon.load(path) != OK:
			printerr("[AssetPreview] 图标读取失败：%s" % path)
			continue
		var cell_x: int = MARGIN + (index % columns) * (cell + MARGIN)
		var cell_y: int = MARGIN + int(index / columns) * (cell + MARGIN)
		sheet.blit_rect(icon, Rect2i(0, 0, icon.get_width(), icon.get_height()),
			Vector2i(cell_x + (cell - icon.get_width()) / 2, cell_y + (cell - icon.get_height()) / 2))
		_stamp_number(sheet, index + 1, Vector2i(cell_x, cell_y))
	var sheet_path: String = _out_dir.path_join("r8_asset_icons_%s.png" % _pack)
	sheet.save_png(sheet_path)
	print("[AssetPreview] 图标联络表 → %s（%d 个）" % [sheet_path, names.size()])


## 11 张地形材质拼成一张 4×3 联络表。
func _compose_terrain_sheet(art_root: String) -> void:
	var names: Array[String] = [
		"top_ling_fields", "top_spirit_plain", "top_barren", "mountain_peak",
		"side_flat", "side_hill", "side_mountain", "river",
		"danger", "fog_rice_paper", "fog_ink_map",
	]
	var cell: int = 128
	var columns: int = 4
	var rows: int = int(ceil(float(names.size()) / float(columns)))
	var sheet: Image = Image.create(MARGIN + columns * (cell + MARGIN), MARGIN + rows * (cell + MARGIN),
		false, Image.FORMAT_RGBA8)
	sheet.fill(PAPER_BG)
	for index: int in range(names.size()):
		var path: String = art_root.path_join("terrain").path_join(names[index] + ".png")
		var texture: Image = Image.new()
		if texture.load(path) != OK:
			printerr("[AssetPreview] 地形材质读取失败：%s" % path)
			continue
		texture.resize(cell, cell, Image.INTERPOLATE_BILINEAR)
		var cell_x: int = MARGIN + (index % columns) * (cell + MARGIN)
		var cell_y: int = MARGIN + int(index / columns) * (cell + MARGIN)
		sheet.blit_rect(texture, Rect2i(0, 0, cell, cell), Vector2i(cell_x, cell_y))
		_stamp_number(sheet, index + 1, Vector2i(cell_x + 2, cell_y + 2))
	var sheet_path: String = _out_dir.path_join("r8_asset_terrain_%s.png" % _pack)
	sheet.save_png(sheet_path)
	print("[AssetPreview] 地形材质联络表 → %s（%d 张）" % [sheet_path, names.size()])


# ---------------------------------------------------------------------------
# 载入与三角化
# ---------------------------------------------------------------------------

## 读 .glb 并展平成世界空间三角形列表：[Vector3 a, Vector3 b, Vector3 c, Color]。
func _load_triangles(path: String) -> Array:
	var document: GLTFDocument = GLTFDocument.new()
	var state: GLTFState = GLTFState.new()
	if document.append_from_file(path, state) != OK:
		return []
	var scene: Node = document.generate_scene(state)
	if scene == null:
		return []
	var triangles: Array = []
	_collect(scene, Transform3D.IDENTITY, triangles)
	scene.free()
	return triangles


func _collect(node: Node, parent_xform: Transform3D, triangles: Array) -> void:
	var world: Transform3D = parent_xform
	if node is Node3D:
		world = parent_xform * (node as Node3D).transform
	if node is MeshInstance3D:
		var mesh_instance: MeshInstance3D = node as MeshInstance3D
		if mesh_instance.mesh != null:
			var color: Color = Color("8a938c")
			var material: Material = mesh_instance.mesh.surface_get_material(0)
			if material is StandardMaterial3D:
				color = (material as StandardMaterial3D).albedo_color
			var faces: PackedVector3Array = mesh_instance.mesh.get_faces()
			var cursor: int = 0
			while cursor + 2 < faces.size():
				triangles.append([
					world * faces[cursor],
					world * faces[cursor + 1],
					world * faces[cursor + 2],
					color,
				])
				cursor += 3
	for child: Node in node.get_children():
		_collect(child, world, triangles)


# ---------------------------------------------------------------------------
# 等距正交投影 + z-buffer 光栅化
# ---------------------------------------------------------------------------

## 等距正交投影（相机在 (+1,+1,+1) 方向看向原点）：
##   右向量 r = normalize(f × world_up) = (1, 0, -1)/√2
##   上向量 u = r × f                = (-1, 2, -1)/√6
## 故：
##   u = (x - z) / √2                屏幕横轴（向右为正）
##   v = (2y - x - z) / √6           屏幕纵轴（向上为正）
##   d = (x + y + z) / √3            视深（越大越靠近相机）
func _project(point: Vector3) -> Vector3:
	var u: float = (point.x - point.z) * 0.70710678
	var v: float = (2.0 * point.y - point.x - point.z) * 0.40824829
	var d: float = (point.x + point.y + point.z) * 0.57735027
	return Vector3(u, v, d)


func _rasterize(image: Image, triangles: Array) -> void:
	# 先把全部顶点投影，求屏幕包围盒用于自适应缩放。
	var projected: Array = []
	var minimum: Vector2 = Vector2(INF, INF)
	var maximum: Vector2 = Vector2(-INF, -INF)
	for triangle: Array in triangles:
		var a: Vector3 = _project(triangle[0] as Vector3)
		var b: Vector3 = _project(triangle[1] as Vector3)
		var c: Vector3 = _project(triangle[2] as Vector3)
		projected.append([a, b, c, triangle[3] as Color])
		for point: Vector3 in [a, b, c]:
			minimum = Vector2(minf(minimum.x, point.x), minf(minimum.y, point.y))
			maximum = Vector2(maxf(maximum.x, point.x), maxf(maximum.y, point.y))

	var span: Vector2 = maximum - minimum
	var usable: float = float(CELL) * 0.78
	var scale: float = usable / maxf(maxf(span.x, span.y), 0.0001)
	var center: Vector2 = (minimum + maximum) * 0.5
	var anchor: Vector2 = Vector2(float(CELL) * 0.5, float(CELL) * 0.5)

	var depth_buffer: PackedFloat32Array = PackedFloat32Array()
	depth_buffer.resize(CELL * CELL)
	depth_buffer.fill(-INF)

	var light: Vector3 = Vector3(0.42, 0.86, 0.30).normalized()
	for entry: Array in projected:
		var pa: Vector3 = entry[0] as Vector3
		var pb: Vector3 = entry[1] as Vector3
		var pc: Vector3 = entry[2] as Vector3
		var color: Color = entry[3] as Color
		# 屏幕坐标（y 轴翻转）。
		var ax: float = (pa.x - center.x) * scale + anchor.x
		var ay: float = anchor.y - (pa.y - center.y) * scale
		var bx: float = (pb.x - center.x) * scale + anchor.x
		var by: float = anchor.y - (pb.y - center.y) * scale
		var cx: float = (pc.x - center.x) * scale + anchor.x
		var cy: float = anchor.y - (pc.y - center.y) * scale

		var area: float = (bx - ax) * (cy - ay) - (cx - ax) * (by - ay)
		if absf(area) < 0.0001:
			continue

		# 平面法线决定明暗（世界空间，双面取绝对值）。
		var normal: Vector3 = ((entry[1] as Vector3) - (entry[0] as Vector3)).cross(
			(entry[2] as Vector3) - (entry[0] as Vector3))
		if normal.length_squared() < 0.0000001:
			continue
		normal = normal.normalized()
		var shade: float = 0.46 + 0.54 * absf(normal.dot(light))
		var shaded: Color = Color(color.r * shade, color.g * shade, color.b * shade, 1.0)

		var min_x: int = int(floor(minf(ax, minf(bx, cx))))
		var max_x: int = int(ceil(maxf(ax, maxf(bx, cx))))
		var min_y: int = int(floor(minf(ay, minf(by, cy))))
		var max_y: int = int(ceil(maxf(ay, maxf(by, cy))))
		min_x = maxi(min_x, 0)
		min_y = maxi(min_y, 0)
		max_x = mini(max_x, CELL - 1)
		max_y = mini(max_y, CELL - 1)

		for py: int in range(min_y, max_y + 1):
			for px: int in range(min_x, max_x + 1):
				var sample_x: float = float(px) + 0.5
				var sample_y: float = float(py) + 0.5
				var w0: float = ((bx - ax) * (sample_y - ay) - (sample_x - ax) * (by - ay)) / area
				var w1: float = ((sample_x - ax) * (cy - ay) - (cx - ax) * (sample_y - ay)) / area
				var w2: float = 1.0 - w0 - w1
				if w0 < -0.002 or w1 < -0.002 or w2 < -0.002:
					continue
				var depth: float = pa.z * w2 + pb.z * w1 + pc.z * w0
				var slot: int = py * CELL + px
				if depth <= depth_buffer[slot]:
					continue
				depth_buffer[slot] = depth
				image.set_pixel(px, py, shaded)


func _frame(image: Image) -> void:
	for index: int in range(CELL):
		_blend(image, index, 0, BORDER, 0.55)
		_blend(image, index, CELL - 1, BORDER, 0.55)
		_blend(image, 0, index, BORDER, 0.55)
		_blend(image, CELL - 1, index, BORDER, 0.55)


func _stamp_number(image: Image, number: int, origin: Vector2i = Vector2i(4, 4)) -> void:
	var text: String = str(number)
	var origin_x: int = origin.x
	var origin_y: int = origin.y
	for char_index: int in range(text.length()):
		var digit: int = int(text[char_index])
		if digit < 0 or digit > 9:
			continue
		var glyph: Array = DIGITS[digit]
		for row: int in range(5):
			var bits: String = str(glyph[row])
			for column: int in range(3):
				if bits[column] == "1":
					for dy: int in range(2):
						for dx: int in range(2):
							_blend(image, origin_x + char_index * 8 + column * 2 + dx,
								origin_y + row * 2 + dy, LABEL, 0.85)


func _blend(image: Image, x: int, y: int, color: Color, alpha: float) -> void:
	if x < 0 or y < 0 or x >= image.get_width() or y >= image.get_height():
		return
	var base: Color = image.get_pixel(x, y)
	var a: float = clampf(alpha, 0.0, 1.0)
	image.set_pixel(x, y, Color(
		lerpf(base.r, color.r, a),
		lerpf(base.g, color.g, a),
		lerpf(base.b, color.b, a),
		1.0))


static func _read_arg(prefix: String, fallback: String) -> String:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with(prefix):
			return arg.substr(prefix.length())
	for arg: String in OS.get_cmdline_args():
		if arg.begins_with(prefix):
			return arg.substr(prefix.length())
	return fallback
