extends Node
## 「最小水墨资源包」生成器（R8 前置门禁）。
##
## 作用：按 `assets/manifest.json` 的逻辑 ID → 物理路径映射，程序化生成 R8 打磨所需的
## 最小资产子集（ROADMAP §3.2 八类清单），写入 `assets/art/default/`。
##
## 为什么用生成器而不是直接塞二进制：仓库需要**可复现、可审阅、无外部依赖**的资产来源。
## 真实美术介入后，直接用同名文件覆盖即可（`manifest.json` 与代码都不用改）。
##
## 运行：
##   Godot_v4.4.1-stable_win64_console.exe --headless --path client res://tools/AssetGen.tscn
##
## 覆盖范围（严格对齐 ROADMAP §3.2，**不越界**）：
##   1. 3 基底地形顶面材质      terrain.base.{LING_FIELDS,SPIRIT_PLAIN,BARREN}
##   2. 3 海拔侧面 + 山体顶面   terrain.relief.{FLAT,HILL,MOUNTAIN}_SIDE / MOUNTAIN_TOP
##   3. 河流                    terrain.river
##   4. 险地                    terrain.danger
##   5. 三态迷雾材质            terrain.fog.{RICE_PAPER,INK_MAP}（第三态=实景，走正常材质）
##   6. 10 单位模型             unit.*
##   7. 10 建筑模型             building.*
##   8. 21 UI 图标              resource.*(13) / realm.*(5) / faction.*(3)
##
## **不生成** districts / improvements / features：它们不在最小包清单内，留给 R8 的
## 「缺失仍回退占位且 WARN 一次」验收路径（裁决二）。

# ---------------------------------------------------------------------------
# 尺寸与调色板
# ---------------------------------------------------------------------------

## 地形贴图边长。手绘水墨不需要高分辨率；256 足以覆盖半径 1.0 的六边形顶面。
const TEX_SIZE: int = 256
## UI 图标边长。
const ICON_SIZE: int = 64
## 图标超采样倍数（抗锯齿）：每个像素取 SS×SS 个采样点求平均。
const SS: int = 3

## 水墨调色板（十六进制取自 docs/ART_STYLE_REFERENCE.md：青绿山水 + 留白云雾）。
var INK: Color = Color("253b37")          # 主墨色
var INK_SOFT: Color = Color("3f5750")     # 淡墨
var JADE: Color = Color("4e7a6f")         # 青绿
var JADE_LIGHT: Color = Color("8fb3a6")   # 浅青
var PAPER: Color = Color("e8e3d2")        # 宣纸
var GOLD: Color = Color("c9a227")         # 浅金
var CINNABAR: Color = Color("a63d2f")     # 丹砂（斗拱/匾额）
var SLATE: Color = Color("5b6663")        # 青石
var BRONZE: Color = Color("8a6a3f")       # 古铜
var PURPLE: Color = Color("6a5a86")       # 紫（剑阵）
var BLOOD: Color = Color("8c2f2a")        # 血（血脉）
var AZURE: Color = Color("4a7d96")        # 水蓝（河流/剑光）
var BONE: Color = Color("d9d3c0")         # 素白（屋身/石台）

var _root: String = ""
var _written: int = 0

# ---------------------------------------------------------------------------
# 入口
# ---------------------------------------------------------------------------

func _ready() -> void:
	_root = Launcher.repo_root().path_join("assets").path_join("art").path_join("default")
	for sub: String in ["terrain", "units", "buildings", "icons"]:
		DirAccess.make_dir_recursive_absolute(_root.path_join(sub))

	_gen_terrain()
	_gen_icons()
	_gen_units()
	_gen_buildings()

	print("[AssetGen] 共写出 %d 个文件 → %s" % [_written, _root])
	print("ASSETGEN_OK")
	get_tree().quit(0)


func _out(sub: String, file_name: String) -> String:
	return _root.path_join(sub).path_join(file_name)


func _save(image: Image, sub: String, file_name: String) -> void:
	var path: String = _out(sub, file_name)
	var error: Error = image.save_png(path)
	if error != OK:
		push_error("[AssetGen] 写出失败 %s（Error %d）" % [path, error])
		return
	_written += 1


# ---------------------------------------------------------------------------
# 噪声（确定性：固定 seed，不读全局随机）
# ---------------------------------------------------------------------------

func _hash2(x: int, y: int, salt: int) -> float:
	var h: int = (x * 374761393) ^ (y * 668265263) ^ (salt * 1274126177)
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 65535) / 65535.0


## 双线性平滑插值的值噪声，返回 [0,1]。
func _noise(x: float, y: float, freq: float, salt: int) -> float:
	var fx: float = x * freq
	var fy: float = y * freq
	var x0: int = int(floor(fx))
	var y0: int = int(floor(fy))
	var tx: float = fx - float(x0)
	var ty: float = fy - float(y0)
	tx = tx * tx * (3.0 - 2.0 * tx)
	ty = ty * ty * (3.0 - 2.0 * ty)
	var v00: float = _hash2(x0, y0, salt)
	var v10: float = _hash2(x0 + 1, y0, salt)
	var v01: float = _hash2(x0, y0 + 1, salt)
	var v11: float = _hash2(x0 + 1, y0 + 1, salt)
	return lerpf(lerpf(v00, v10, tx), lerpf(v01, v11, tx), ty)


## 多倍频叠加（fbm），返回 [0,1]。
func _fbm(x: float, y: float, freq: float, octaves: int, salt: int) -> float:
	var total: float = 0.0
	var amplitude: float = 0.5
	var weight: float = 0.0
	var f: float = freq
	for index: int in range(octaves):
		total += _noise(x, y, f, salt + index * 977) * amplitude
		weight += amplitude
		amplitude *= 0.5
		f *= 2.0
	return total / maxf(weight, 0.0001)


# ---------------------------------------------------------------------------
# 绘制原语
# ---------------------------------------------------------------------------

func _blend(image: Image, x: int, y: int, color: Color, alpha: float) -> void:
	if alpha <= 0.0:
		return
	if x < 0 or y < 0 or x >= image.get_width() or y >= image.get_height():
		return
	var base: Color = image.get_pixel(x, y)
	var a: float = clampf(alpha, 0.0, 1.0)
	image.set_pixel(x, y, Color(
		lerpf(base.r, color.r, a),
		lerpf(base.g, color.g, a),
		lerpf(base.b, color.b, a),
		lerpf(base.a, color.a, a)))


## 柔和圆斑（水墨晕染的基元）。
func _blot(image: Image, cx: float, cy: float, radius: float, color: Color, alpha: float) -> void:
	var r: int = int(ceil(radius))
	var ix: int = int(cx)
	var iy: int = int(cy)
	for dy: int in range(-r, r + 1):
		for dx: int in range(-r, r + 1):
			var distance: float = sqrt(float(dx * dx + dy * dy))
			if distance > radius:
				continue
			var falloff: float = 1.0 - distance / maxf(radius, 0.0001)
			_blend(image, ix + dx, iy + dy, color, alpha * falloff * falloff)


## 柔边线段（笔触）。
func _stroke(image: Image, from: Vector2, to: Vector2, width: float, color: Color, alpha: float) -> void:
	var distance: float = from.distance_to(to)
	var steps: int = int(maxf(distance, 1.0))
	for index: int in range(steps + 1):
		var point: Vector2 = from.lerp(to, float(index) / float(maxf(steps, 1)))
		_blot(image, point.x, point.y, width, color, alpha)


## 纸纤维（细碎明暗点）。
func _fibers(image: Image, count: int, salt: int) -> void:
	var width: int = image.get_width()
	var height: int = image.get_height()
	for index: int in range(count):
		var x: int = int(_hash2(index, 7, salt) * float(width))
		var y: int = int(_hash2(index, 13, salt) * float(height))
		var light: bool = _hash2(index, 29, salt) > 0.5
		var color: Color = Color(1.0, 1.0, 1.0) if light else INK
		_blend(image, x, y, color, 0.05 + 0.05 * _hash2(index, 41, salt))


## 四周压暗（让相邻格有分界感）。
func _vignette(image: Image, strength: float) -> void:
	var width: int = image.get_width()
	var height: int = image.get_height()
	var half: float = float(width) * 0.5
	for y: int in range(height):
		for x: int in range(width):
			var dx: float = (float(x) - half + 0.5) / half
			var dy: float = (float(y) - half + 0.5) / half
			var d: float = clampf(sqrt(dx * dx + dy * dy) / 1.41421, 0.0, 1.0)
			_blend(image, x, y, INK, strength * d * d * d)


# ---------------------------------------------------------------------------
# 1–5：地形贴图
# ---------------------------------------------------------------------------

func _gen_terrain() -> void:
	# 3 基底顶面：宣纸底 + 各自色相的水墨晕染 + 细纤维。
	_terrain_top("top_ling_fields.png", Color("8d8f4e"), Color("5f6b33"), 1101, 0)
	_terrain_top("top_spirit_plain.png", Color("7fa892"), Color("3f6b5c"), 2203, 0)
	_terrain_top("top_barren.png", Color("a2917a"), Color("6b5b47"), 3307, 0)
	# 3 海拔侧面：竖直渐变 + 横向岩层 + 底部积墨。
	_relief_side("side_flat.png", Color("b6ae96"), Color("7d7864"), 4409, 3)
	_relief_side("side_hill.png", Color("a49a80"), Color("655f4e"), 5501, 5)
	_relief_side("side_mountain.png", Color("8f958c"), Color("4b524e"), 6607, 8)
	# 山体顶面（连绵山脊）：淡墨山峦皴线。
	_mountain_top("mountain_peak.png", 7703)
	# 河流：横向波纹 + 留白高光。
	_river("river.png", 8809)
	# 险地：焦墨 + 丹砂裂纹。
	_danger("danger.png", 9901)
	# 三态迷雾：宣纸空白 / 水墨古图排线。
	_fog_rice_paper("fog_rice_paper.png", 10103)
	_fog_ink_map("fog_ink_map.png", 11213)


func _terrain_top(file_name: String, light: Color, dark: Color, salt: int, furrows: int) -> void:
	var image: Image = Image.create(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_RGBA8)
	image.fill(PAPER)
	var size: float = float(TEX_SIZE)
	for y: int in range(TEX_SIZE):
		for x: int in range(TEX_SIZE):
			var u: float = float(x) / size
			var v: float = float(y) / size
			var wash: float = _fbm(u, v, 3.0, 4, salt)
			var t: float = smoothstep(0.38, 0.78, wash)
			var color: Color = PAPER.lerp(light, 0.55 + 0.45 * t).lerp(dark, t * t * 0.55)
			# 二次叠色：让色块边缘像笔触收尾。
			var edge: float = _fbm(u, v, 7.0, 2, salt + 17)
			color = color.lerp(dark, smoothstep(0.62, 0.92, edge) * 0.25)
			image.set_pixel(x, y, color)
	if furrows > 0:
		for index: int in range(furrows * 6):
			var y0: float = (float(index) + 0.5) * size / float(furrows * 6)
			_stroke(image, Vector2(0.0, y0), Vector2(size, y0 + (float(index % 3) - 1.0) * 3.0),
				1.2, dark.darkened(0.25), 0.22)
	_fibers(image, 520, salt + 3)
	_vignette(image, 0.16)
	_save(image, "terrain", file_name)


func _relief_side(file_name: String, light: Color, dark: Color, salt: int, strata: int) -> void:
	var image: Image = Image.create(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_RGBA8)
	var size: float = float(TEX_SIZE)
	for y: int in range(TEX_SIZE):
		var v: float = float(y) / size
		# 顶部贴近顶面色、底部积墨（v=1 在底部）。
		var base: Color = light.lerp(dark, smoothstep(0.0, 1.0, v))
		for x: int in range(TEX_SIZE):
			var u: float = float(x) / size
			var n: float = _fbm(u, v, 4.0, 3, salt)
			var color: Color = base.lerp(dark, n * 0.35)
			image.set_pixel(x, y, color)
	# 横向岩层：不均匀的深色横纹。
	for index: int in range(strata):
		var y0: float = (float(index) + 0.35 + 0.3 * _hash2(index, 3, salt)) * size / float(strata)
		var width: float = 1.0 + 2.0 * _hash2(index, 5, salt)
		_stroke(image, Vector2(0.0, y0), Vector2(size, y0 + (float(index % 2) * 2.0 - 1.0) * 4.0),
			width, INK, 0.16)
	# 底部积墨加重。
	for y: int in range(int(size * 0.72), TEX_SIZE):
		var weight: float = (float(y) - size * 0.72) / (size * 0.28)
		for x: int in range(TEX_SIZE):
			_blend(image, x, y, INK, weight * weight * 0.30)
	_fibers(image, 260, salt + 11)
	_save(image, "terrain", file_name)


func _mountain_top(file_name: String, salt: int) -> void:
	var image: Image = Image.create(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_RGBA8)
	var size: float = float(TEX_SIZE)
	for y: int in range(TEX_SIZE):
		for x: int in range(TEX_SIZE):
			var u: float = float(x) / size
			var v: float = float(y) / size
			var n: float = _fbm(u, v, 3.5, 4, salt)
			var color: Color = Color("cfd2c6").lerp(Color("6d746c"), smoothstep(0.35, 0.85, n))
			image.set_pixel(x, y, color)
	# 皴线：沿等高方向的短促笔触，模拟连绵山脊。
	for index: int in range(26):
		var start: Vector2 = Vector2(_hash2(index, 2, salt) * size, _hash2(index, 4, salt) * size)
		var length: float = 22.0 + 60.0 * _hash2(index, 6, salt)
		var angle: float = (-0.9 + 1.8 * _hash2(index, 8, salt))
		var end: Vector2 = start + Vector2(cos(angle), sin(angle)) * length
		_stroke(image, start, end, 1.4, INK, 0.20)
		_stroke(image, start + Vector2(2.0, 3.0), end + Vector2(2.0, 3.0), 0.9, INK, 0.12)
	_fibers(image, 320, salt + 5)
	_vignette(image, 0.20)
	_save(image, "terrain", file_name)


func _river(file_name: String, salt: int) -> void:
	var image: Image = Image.create(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_RGBA8)
	var size: float = float(TEX_SIZE)
	for y: int in range(TEX_SIZE):
		for x: int in range(TEX_SIZE):
			var u: float = float(x) / size
			var v: float = float(y) / size
			# 顺流方向的波浪（横向条纹），频率随噪声扰动。
			var phase: float = v * 11.0 + _fbm(u, v, 2.5, 3, salt) * 2.4
			var wave: float = 0.5 + 0.5 * sin(phase * PI)
			var color: Color = Color("6f97a3").lerp(Color("31596a"), wave)
			# 留白高光（水流反光）。
			if wave > 0.86:
				color = color.lerp(PAPER, (wave - 0.86) * 2.6)
			image.set_pixel(x, y, color)
	_fibers(image, 180, salt + 7)
	_vignette(image, 0.14)
	_save(image, "terrain", file_name)


func _danger(file_name: String, salt: int) -> void:
	var image: Image = Image.create(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_RGBA8)
	var size: float = float(TEX_SIZE)
	for y: int in range(TEX_SIZE):
		for x: int in range(TEX_SIZE):
			var u: float = float(x) / size
			var v: float = float(y) / size
			var n: float = _fbm(u, v, 4.5, 4, salt)
			var color: Color = Color("6b625c").lerp(Color("2f2a28"), smoothstep(0.3, 0.8, n))
			image.set_pixel(x, y, color)
	# 裂纹：从中心向外发散的折线，丹砂描边。
	for index: int in range(7):
		var angle: float = TAU * float(index) / 7.0 + 0.4 * _hash2(index, 3, salt)
		var point: Vector2 = Vector2(size * 0.5, size * 0.5)
		var direction: Vector2 = Vector2(cos(angle), sin(angle))
		for step: int in range(9):
			var wobble: float = (0.6 - 1.2 * _hash2(index * 31 + step, 7, salt)) * 0.9
			var next: Vector2 = point + (direction.rotated(wobble) * (size * 0.058))
			_stroke(image, point, next, 1.8, CINNABAR, 0.42)
			_stroke(image, point, next, 0.8, INK, 0.55)
			point = next
	_blot(image, size * 0.5, size * 0.5, size * 0.16, INK, 0.22)
	_fibers(image, 240, salt + 13)
	_vignette(image, 0.26)
	_save(image, "terrain", file_name)


func _fog_rice_paper(file_name: String, salt: int) -> void:
	var image: Image = Image.create(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_RGBA8)
	var size: float = float(TEX_SIZE)
	for y: int in range(TEX_SIZE):
		for x: int in range(TEX_SIZE):
			var u: float = float(x) / size
			var v: float = float(y) / size
			var n: float = _fbm(u, v, 2.0, 3, salt)
			var color: Color = Color("f2ecdb").lerp(Color("e2dac4"), n * 0.7)
			image.set_pixel(x, y, color)
	# 宣纸的云絮感：几团极淡的湿墨。
	for index: int in range(6):
		_blot(image,
			_hash2(index, 2, salt) * size,
			_hash2(index, 4, salt) * size,
			size * (0.10 + 0.10 * _hash2(index, 6, salt)),
			Color("cfc7b0"), 0.16)
	_fibers(image, 700, salt + 3)
	_vignette(image, 0.10)
	_save(image, "terrain", file_name)


func _fog_ink_map(file_name: String, salt: int) -> void:
	var image: Image = Image.create(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_RGBA8)
	var size: float = float(TEX_SIZE)
	for y: int in range(TEX_SIZE):
		for x: int in range(TEX_SIZE):
			var u: float = float(x) / size
			var v: float = float(y) / size
			var n: float = _fbm(u, v, 2.5, 3, salt)
			var color: Color = Color("ded6bf").lerp(Color("c9c0a6"), n * 0.8)
			image.set_pixel(x, y, color)
	# 古地图排线：疏密不均的斜向细线（速写感）。
	for index: int in range(64):
		var y0: float = (float(index) + 0.5) * size / 64.0
		var jitter: float = (0.5 - _hash2(index, 3, salt)) * 6.0
		var width: float = 0.5 + 0.7 * _hash2(index, 5, salt)
		_stroke(image, Vector2(0.0, y0), Vector2(size, y0 + jitter), width, INK_SOFT, 0.20)
	# 若干淡墨区块（山体/水系的暗示）。
	for index: int in range(5):
		_blot(image,
			_hash2(index, 11, salt) * size,
			_hash2(index, 17, salt) * size,
			size * (0.14 + 0.12 * _hash2(index, 19, salt)),
			INK_SOFT, 0.10)
	_fibers(image, 420, salt + 9)
	_vignette(image, 0.22)
	_save(image, "terrain", file_name)


# ---------------------------------------------------------------------------
# 8：21 个 UI 图标（64×64，透明底，3×3 超采样抗锯齿）
# ---------------------------------------------------------------------------

func _gen_icons() -> void:
	# resource.*（13）
	_icon("resource_spirit_power.png", "spirit_power", JADE)
	_icon("resource_spirit_stones.png", "spirit_stones", JADE_LIGHT)
	_icon("resource_work_power.png", "work_power", BRONZE)
	_icon("resource_prestige.png", "prestige", GOLD)
	_icon("resource_qi_yun.png", "qi_yun", AZURE)
	_icon("resource_food.png", "food", Color("7d8f4e"))
	_icon("resource_dao_points.png", "dao_points", INK_SOFT)
	_icon("resource_tian_jing.png", "tian_jing", AZURE)
	_icon("resource_xuan_tie.png", "xuan_tie", SLATE)
	_icon("resource_ling_mu.png", "ling_mu", Color("4d7a4a"))
	_icon("resource_ling_cha.png", "ling_cha", Color("6f8f5a"))
	_icon("resource_yun_jin.png", "yun_jin", CINNABAR)
	_icon("resource_ling_yu.png", "ling_yu", Color("9fc3a8"))
	# realm.*（5）
	_icon("realm_lian_qi.png", "realm_lian_qi", JADE_LIGHT)
	_icon("realm_zhu_ji.png", "realm_zhu_ji", JADE)
	_icon("realm_jin_dan.png", "realm_jin_dan", GOLD)
	_icon("realm_yuan_ying.png", "realm_yuan_ying", AZURE)
	_icon("realm_hua_shen.png", "realm_hua_shen", PURPLE)
	# faction.*（3）
	_icon("faction_zong_men.png", "faction_zong_men", JADE)
	_icon("faction_jia_zu.png", "faction_jia_zu", CINNABAR)
	_icon("faction_guo_jia.png", "faction_guo_jia", GOLD)


## 单图标：逐像素 3×3 超采样，`kind` 决定字形。
func _icon(file_name: String, kind: String, accent: Color) -> void:
	var image: Image = Image.create(ICON_SIZE, ICON_SIZE, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var size: float = float(ICON_SIZE)
	for y: int in range(ICON_SIZE):
		for x: int in range(ICON_SIZE):
			var accum: Color = Color(0, 0, 0, 0)
			var hits: int = 0
			for sy: int in range(SS):
				for sx: int in range(SS):
					var u: float = (float(x) + (float(sx) + 0.5) / float(SS)) / size
					var v: float = (float(y) + (float(sy) + 0.5) / float(SS)) / size
					var sample: Color = _glyph(kind, u, v, accent)
					if sample.a > 0.0:
						accum = Color(
							accum.r + sample.r * sample.a,
							accum.g + sample.g * sample.a,
							accum.b + sample.b * sample.a,
							accum.a + sample.a)
						hits += 1
			if hits == 0:
				continue
			var total: int = SS * SS
			image.set_pixel(x, y, Color(
				accum.r / maxf(accum.a, 0.0001),
				accum.g / maxf(accum.a, 0.0001),
				accum.b / maxf(accum.a, 0.0001),
				accum.a / float(total)))
	_save(image, "icons", file_name)


## 字形求值：返回带 alpha 的颜色（alpha=0 表示该采样点不在字形内）。
## 坐标 u/v ∈ [0,1]，原点左上。
func _glyph(kind: String, u: float, v: float, accent: Color) -> Color:
	var ink: Color = INK
	match kind:
		"spirit_power":
			# 灵气：环形 + 中心点 + 三道上升气流。
			if _ring(u, v, 0.5, 0.56, 0.30, 0.075):
				return ink
			if _disc(u, v, 0.5, 0.56, 0.09):
				return accent
			if _line(u, v, 0.5, 0.30, 0.36, 0.14, 0.028) or _line(u, v, 0.5, 0.30, 0.64, 0.14, 0.028):
				return accent
		"spirit_stones":
			# 灵石：菱形晶体 + 中缝高光。
			if _rhombus(u, v, 0.5, 0.52, 0.30, 0.38):
				if _line(u, v, 0.5, 0.14, 0.5, 0.90, 0.022):
					return PAPER
				return accent
		"work_power":
			# 工力：交叉工具（两把斜杆 + 端头）。
			if _line(u, v, 0.24, 0.80, 0.74, 0.20, 0.075):
				return accent
			if _line(u, v, 0.26, 0.20, 0.76, 0.80, 0.055):
				return ink
			if _disc(u, v, 0.24, 0.80, 0.10) or _disc(u, v, 0.74, 0.20, 0.10):
				return ink
		"prestige":
			# 声望：旗杆 + 飘旗。
			if _line(u, v, 0.30, 0.12, 0.30, 0.88, 0.055):
				return ink
			if u > 0.32 and u < 0.80 and v > 0.16 and v < 0.52:
				var wave: float = 0.06 * sin((u - 0.32) * 12.0)
				if v < 0.34 + wave:
					return accent
		"qi_yun":
			# 气运：三团相连云气。
			if _disc(u, v, 0.36, 0.58, 0.20) or _disc(u, v, 0.56, 0.44, 0.24) or _disc(u, v, 0.70, 0.62, 0.18):
				if _disc(u, v, 0.52, 0.62, 0.10):
					return PAPER
				return accent
			if _line(u, v, 0.22, 0.74, 0.80, 0.74, 0.035):
				return ink
		"food":
			# 灵粮：谷穗（中轴 + 两侧谷粒）。
			if _line(u, v, 0.50, 0.16, 0.50, 0.86, 0.045):
				return ink
			for index: int in range(4):
				var y0: float = 0.28 + float(index) * 0.14
				if _disc(u, v, 0.36, y0, 0.075) or _disc(u, v, 0.64, y0, 0.075):
					return accent
		"dao_points":
			# 道点：三横（坤卦）+ 一点朱砂。
			if _line(u, v, 0.18, 0.30, 0.82, 0.30, 0.055) \
					or _line(u, v, 0.18, 0.50, 0.82, 0.50, 0.055) \
					or _line(u, v, 0.18, 0.70, 0.82, 0.70, 0.055):
				return ink
			if _disc(u, v, 0.50, 0.50, 0.055):
				return CINNABAR
		"tian_jing":
			# 天晶：六边形晶体 + 内部棱线。
			if _hexagon(u, v, 0.5, 0.5, 0.34):
				if _line(u, v, 0.5, 0.16, 0.5, 0.84, 0.02) or _line(u, v, 0.30, 0.42, 0.70, 0.58, 0.02):
					return PAPER
				return accent
		"xuan_tie":
			# 玄铁：梯形锭 + 上下压线。
			if u > 0.20 and u < 0.80 and v > 0.36 and v < 0.72:
				var inset: float = (v - 0.36) / 0.36
				if u > 0.20 + inset * 0.10 and u < 0.80 - inset * 0.10:
					if _line(u, v, 0.20, 0.54, 0.80, 0.54, 0.03):
						return PAPER
					return accent
		"ling_mu":
			# 灵木：树干 + 层叠树冠。
			if _line(u, v, 0.50, 0.48, 0.50, 0.88, 0.06):
				return BRONZE
			if _triangle(u, v, 0.50, 0.12, 0.50, 0.30) or _triangle(u, v, 0.50, 0.32, 0.68, 0.38):
				return accent
		"ling_cha":
			# 灵茶：茶盏 + 把手 + 热气。
			if _trapezoid(u, v, 0.24, 0.78, 0.42, 0.68):
				return accent
			if _ring(u, v, 0.78, 0.55, 0.10, 0.035):
				return ink
			if _line(u, v, 0.38, 0.22, 0.44, 0.36, 0.025) or _line(u, v, 0.58, 0.18, 0.52, 0.34, 0.025):
				return INK_SOFT
		"yun_jin":
			# 云锦：菱形格纹（织锦）。
			var cell: float = 0.26
			var cu: float = fposmod(u - 0.10, cell) - cell * 0.5
			var cv: float = fposmod(v - 0.10, cell) - cell * 0.5
			if absf(cu) + absf(cv) < 0.042:
				return accent
			if absf(cu) + absf(cv) < 0.068:
				return INK_SOFT
		"ling_yu":
			# 灵玉：玉璧（粗环 + 内孔留白 + 高光）。
			if _ring(u, v, 0.5, 0.5, 0.32, 0.14):
				if _line(u, v, 0.30, 0.34, 0.46, 0.24, 0.035):
					return PAPER
				return accent
		"realm_lian_qi":
			# 炼气：单环。
			if _ring(u, v, 0.5, 0.5, 0.30, 0.075):
				return accent
		"realm_zhu_ji":
			# 筑基：双环 + 基座横线。
			if _ring(u, v, 0.5, 0.42, 0.26, 0.065):
				return accent
			if _line(u, v, 0.20, 0.76, 0.80, 0.76, 0.06):
				return ink
		"realm_jin_dan":
			# 金丹：实心圆 + 高光缺口。
			if _disc(u, v, 0.5, 0.5, 0.31):
				if _disc(u, v, 0.40, 0.38, 0.09):
					return PAPER
				return accent
		"realm_yuan_ying":
			# 元婴：外环 + 内丹 + 三点灵光。
			if _ring(u, v, 0.5, 0.5, 0.33, 0.055):
				return accent
			if _disc(u, v, 0.5, 0.5, 0.11):
				return ink
			if _disc(u, v, 0.50, 0.20, 0.045) or _disc(u, v, 0.24, 0.66, 0.045) or _disc(u, v, 0.76, 0.66, 0.045):
				return accent
		"realm_hua_shen":
			# 化神：环 + 八向光芒。
			if _ring(u, v, 0.5, 0.5, 0.22, 0.06):
				return accent
			var dx: float = u - 0.5
			var dy: float = v - 0.5
			var radius: float = sqrt(dx * dx + dy * dy)
			var angle: float = atan2(dy, dx)
			var ray: float = absf(fposmod(angle, TAU / 8.0) - TAU / 16.0)
			if radius > 0.26 and radius < 0.44 and ray < 0.055:
				return accent
		"faction_zong_men":
			# 宗门：山门（两柱 + 横梁 + 檐）。
			if _line(u, v, 0.28, 0.28, 0.28, 0.86, 0.055) or _line(u, v, 0.72, 0.28, 0.72, 0.86, 0.055):
				return ink
			if _line(u, v, 0.16, 0.30, 0.84, 0.30, 0.06):
				return ink
			if _line(u, v, 0.12, 0.20, 0.88, 0.20, 0.055):
				return accent
		"faction_jia_zu":
			# 家族：家屋（人字顶 + 屋身 + 门）。
			if _triangle(u, v, 0.50, 0.14, 0.46, 0.42):
				return accent
			if u > 0.22 and u < 0.78 and v > 0.44 and v < 0.84:
				if u > 0.42 and u < 0.58 and v > 0.58:
					return ink
				return BONE
		"faction_guo_jia":
			# 国家：城墙（垛口 + 墙体 + 城门）。
			if v > 0.26 and v < 0.36:
				var notch: float = fposmod(u - 0.16, 0.17)
				if notch > 0.085:
					return accent
			if u > 0.16 and u < 0.84 and v > 0.36 and v < 0.82:
				if u > 0.42 and u < 0.58 and v > 0.56:
					return ink
				return accent
	return Color(0, 0, 0, 0)


func _disc(u: float, v: float, cx: float, cy: float, radius: float) -> bool:
	var dx: float = u - cx
	var dy: float = v - cy
	return dx * dx + dy * dy <= radius * radius


func _ring(u: float, v: float, cx: float, cy: float, radius: float, thickness: float) -> bool:
	var dx: float = u - cx
	var dy: float = v - cy
	var distance: float = sqrt(dx * dx + dy * dy)
	return distance <= radius and distance >= radius - thickness


func _rhombus(u: float, v: float, cx: float, cy: float, half_w: float, half_h: float) -> bool:
	return absf(u - cx) / half_w + absf(v - cy) / half_h <= 1.0


func _hexagon(u: float, v: float, cx: float, cy: float, radius: float) -> bool:
	var dx: float = absf(u - cx)
	var dy: float = absf(v - cy)
	if dx > radius or dy > radius * 0.866:
		return false
	return dy <= radius * 0.866 - dx * 0.5


## 等腰三角形：`cx` 为对称轴，`apex_y` 为顶点，`base_y` 为底边，`half_width` 为底边半宽。
## 注意：apex_y 必须小于 base_y（屏幕坐标向下为正）。
func _triangle(u: float, v: float, cx: float, apex_y: float, base_y: float, half_width: float) -> bool:
	if v < apex_y or v > base_y:
		return false
	var span: float = base_y - apex_y
	if span <= 0.0:
		return false
	var t: float = (v - apex_y) / span
	return absf(u - cx) <= half_width * t


func _trapezoid(u: float, v: float, top_w: float, bottom_w: float, top_y: float, bottom_y: float) -> bool:
	if v < top_y or v > bottom_y:
		return false
	var t: float = (v - top_y) / maxf(bottom_y - top_y, 0.0001)
	var half: float = lerpf(top_w, bottom_w, t) * 0.5
	return absf(u - 0.5) <= half


func _line(u: float, v: float, x0: float, y0: float, x1: float, y1: float, width: float) -> bool:
	var dx: float = x1 - x0
	var dy: float = y1 - y0
	var length_squared: float = dx * dx + dy * dy
	if length_squared <= 0.000001:
		return false
	var t: float = clampf(((u - x0) * dx + (v - y0) * dy) / length_squared, 0.0, 1.0)
	var px: float = x0 + dx * t
	var py: float = y0 + dy * t
	var ex: float = u - px
	var ey: float = v - py
	return ex * ex + ey * ey <= width * width


# ---------------------------------------------------------------------------
# 6–7：单位与建筑 3D 模型（.glb）
# ---------------------------------------------------------------------------

## 统一材质：水墨风格——高粗糙度、零金属度，靠固有色区分。
func _material(color: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	material.metallic = 0.0
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	return material


func _add_box(parent: Node3D, size: Vector3, position: Vector3, color: Color,
		rot_y: float = 0.0, rot_z: float = 0.0) -> MeshInstance3D:
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	mesh.material = _material(color)
	return _attach(parent, mesh, position, rot_y, rot_z)


## 四棱锥/攒尖屋顶：`radial_segments=4` 的圆柱，绕 Y 轴 45° 让斜面正对轴向。
func _add_roof(parent: Node3D, base_radius: float, height: float, position: Vector3,
		color: Color, rot_y: float = 0.0) -> MeshInstance3D:
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.top_radius = base_radius * 0.08
	mesh.bottom_radius = base_radius
	mesh.height = height
	mesh.radial_segments = 4
	mesh.rings = 1
	mesh.material = _material(color)
	return _attach(parent, mesh, position, rot_y + PI * 0.25, 0.0)


func _add_cylinder(parent: Node3D, radius: float, height: float, position: Vector3,
		color: Color, segments: int = 8, rot_y: float = 0.0) -> MeshInstance3D:
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = segments
	mesh.rings = 1
	mesh.material = _material(color)
	return _attach(parent, mesh, position, rot_y, 0.0)


func _add_cone(parent: Node3D, radius: float, height: float, position: Vector3,
		color: Color, segments: int = 10) -> MeshInstance3D:
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.top_radius = 0.0
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = segments
	mesh.rings = 1
	mesh.material = _material(color)
	return _attach(parent, mesh, position, 0.0, 0.0)


func _add_sphere(parent: Node3D, radius: float, position: Vector3, color: Color) -> MeshInstance3D:
	var mesh: SphereMesh = SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 10
	mesh.rings = 6
	mesh.material = _material(color)
	return _attach(parent, mesh, position, 0.0, 0.0)


func _attach(parent: Node3D, mesh: Mesh, position: Vector3, rot_y: float, rot_z: float) -> MeshInstance3D:
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = position
	instance.rotation = Vector3(0.0, rot_y, rot_z)
	parent.add_child(instance)
	return instance


func _new_root(model_name: String) -> Node3D:
	var root: Node3D = Node3D.new()
	root.name = model_name
	return root


## 导出为 .glb。原点锚在底面中心（与 `manifest.anchor = "ground"` 一致）。
func _export_glb(root: Node3D, sub: String, file_name: String) -> void:
	var path: String = _out(sub, file_name)
	var document: GLTFDocument = GLTFDocument.new()
	var state: GLTFState = GLTFState.new()
	var error: Error = document.append_from_scene(root, state)
	if error != OK:
		push_error("[AssetGen] GLTF 组装失败 %s（Error %d）" % [file_name, error])
		root.free()
		return
	error = document.write_to_filesystem(state, path)
	if error != OK:
		push_error("[AssetGen] GLTF 写出失败 %s（Error %d）" % [path, error])
		root.free()
		return
	_written += 1
	root.free()


func _gen_units() -> void:
	# 1 普通弟子：素袍 + 束发，最朴素的基准体型。
	var pu_tong: Node3D = _new_root("PU_TONG")
	_add_box(pu_tong, Vector3(0.26, 0.50, 0.20), Vector3(0.0, 0.25, 0.0), SLATE)
	_add_sphere(pu_tong, 0.11, Vector3(0.0, 0.58, 0.0), BONE)
	_add_roof(pu_tong, 0.13, 0.10, Vector3(0.0, 0.66, 0.0), INK)
	_export_glb(pu_tong, "units", "pu_tong.glb")

	# 2 剑修：窄身 + 背剑（斜插）+ 剑光青。
	var jian_xiu: Node3D = _new_root("JIAN_XIU")
	_add_box(jian_xiu, Vector3(0.20, 0.55, 0.16), Vector3(0.0, 0.275, 0.0), JADE_LIGHT)
	_add_sphere(jian_xiu, 0.10, Vector3(0.0, 0.62, 0.0), BONE)
	_add_box(jian_xiu, Vector3(0.035, 0.92, 0.035), Vector3(0.17, 0.52, 0.0), AZURE, 0.0, 0.18)
	_add_box(jian_xiu, Vector3(0.10, 0.03, 0.03), Vector3(0.10, 0.30, 0.0), GOLD)
	_export_glb(jian_xiu, "units", "jian_xiu.glb")

	# 3 法修：道袍 + 掌上灵珠。
	var fa_xiu: Node3D = _new_root("FA_XIU")
	_add_cone(fa_xiu, 0.24, 0.60, Vector3(0.0, 0.30, 0.0), JADE, 8)
	_add_sphere(fa_xiu, 0.10, Vector3(0.0, 0.68, 0.0), BONE)
	_add_sphere(fa_xiu, 0.085, Vector3(0.24, 0.60, 0.06), GOLD)
	_add_sphere(fa_xiu, 0.05, Vector3(0.24, 0.78, 0.06), GOLD)
	_export_glb(fa_xiu, "units", "fa_xiu.glb")

	# 4 体修：宽肩厚背，最矮最壮。
	var ti_xiu: Node3D = _new_root("TI_XIU")
	_add_box(ti_xiu, Vector3(0.32, 0.30, 0.26), Vector3(0.0, 0.15, 0.0), BRONZE)
	_add_box(ti_xiu, Vector3(0.36, 0.34, 0.28), Vector3(0.0, 0.46, 0.0), Color("9a7444"))
	_add_box(ti_xiu, Vector3(0.50, 0.12, 0.30), Vector3(0.0, 0.66, 0.0), BRONZE)
	_add_sphere(ti_xiu, 0.10, Vector3(0.0, 0.78, 0.0), BONE)
	_export_glb(ti_xiu, "units", "ti_xiu.glb")

	# 5 器骑：坐骑 + 骑手 + 旗。
	var qi_ji: Node3D = _new_root("QI_JI")
	_add_box(qi_ji, Vector3(0.52, 0.26, 0.26), Vector3(0.0, 0.17, 0.0), SLATE)
	_add_box(qi_ji, Vector3(0.12, 0.20, 0.12), Vector3(0.22, 0.06, 0.0), INK_SOFT)
	_add_box(qi_ji, Vector3(0.12, 0.20, 0.12), Vector3(-0.22, 0.06, 0.0), INK_SOFT)
	_add_box(qi_ji, Vector3(0.18, 0.34, 0.16), Vector3(0.0, 0.47, 0.0), CINNABAR)
	_add_sphere(qi_ji, 0.09, Vector3(0.0, 0.70, 0.0), BONE)
	_add_cylinder(qi_ji, 0.018, 0.60, Vector3(-0.20, 0.60, -0.10), INK, 6)
	_add_box(qi_ji, Vector3(0.16, 0.10, 0.012), Vector3(-0.30, 0.82, -0.10), CINNABAR)
	_export_glb(qi_ji, "units", "qi_ji.glb")

	# 6 符修：素袍 + 悬符 + 朱砂印。
	var fu_xiu: Node3D = _new_root("FU_XIU")
	_add_box(fu_xiu, Vector3(0.22, 0.52, 0.18), Vector3(0.0, 0.26, 0.0), Color("cfc7b0"))
	_add_sphere(fu_xiu, 0.10, Vector3(0.0, 0.60, 0.0), BONE)
	_add_box(fu_xiu, Vector3(0.16, 0.30, 0.014), Vector3(0.22, 0.48, 0.0), PAPER, 0.35)
	_add_box(fu_xiu, Vector3(0.05, 0.05, 0.018), Vector3(0.26, 0.40, 0.0), CINNABAR, 0.35)
	_export_glb(fu_xiu, "units", "fu_xiu.glb")

	# 7 机关：方形机身 + 两侧齿轮 + 独眼。
	var ji_guan: Node3D = _new_root("JI_GUAN")
	_add_box(ji_guan, Vector3(0.30, 0.50, 0.30), Vector3(0.0, 0.25, 0.0), SLATE)
	_add_cylinder(ji_guan, 0.11, 0.05, Vector3(0.19, 0.34, 0.0), GOLD, 8, PI * 0.5)
	_add_cylinder(ji_guan, 0.11, 0.05, Vector3(-0.19, 0.34, 0.0), GOLD, 8, PI * 0.5)
	_add_box(ji_guan, Vector3(0.14, 0.12, 0.14), Vector3(0.0, 0.56, 0.0), INK_SOFT)
	_add_sphere(ji_guan, 0.035, Vector3(0.0, 0.56, 0.08), CINNABAR)
	_export_glb(ji_guan, "units", "ji_guan.glb")

	# 8 剑阵师：锥形道袍 + 环身三剑。
	var jian_zhen_shi: Node3D = _new_root("JIAN_ZHEN_SHI")
	_add_cone(jian_zhen_shi, 0.26, 0.58, Vector3(0.0, 0.29, 0.0), PURPLE, 8)
	_add_sphere(jian_zhen_shi, 0.10, Vector3(0.0, 0.66, 0.0), BONE)
	for index: int in range(3):
		var angle: float = TAU * float(index) / 3.0
		var offset: Vector3 = Vector3(cos(angle) * 0.32, 0.50, sin(angle) * 0.32)
		# 悬空短剑：刃 + 护手，向外微倾，避免看起来像长杆。
		_add_box(jian_zhen_shi, Vector3(0.035, 0.40, 0.035), offset, AZURE, -angle, 0.30)
		_add_box(jian_zhen_shi, Vector3(0.11, 0.025, 0.025), offset + Vector3(0.0, -0.17, 0.0), GOLD, -angle, 0.30)
	_export_glb(jian_zhen_shi, "units", "jian_zhen_shi.glb")

	# 9 血脉修士：暗红袍 + 脚下血环。
	var xue_mai: Node3D = _new_root("XUE_MAI_XIU_SHI")
	_add_cylinder(xue_mai, 0.30, 0.035, Vector3(0.0, 0.02, 0.0), BLOOD, 12)
	_add_box(xue_mai, Vector3(0.24, 0.50, 0.20), Vector3(0.0, 0.27, 0.0), BLOOD)
	_add_sphere(xue_mai, 0.11, Vector3(0.0, 0.60, 0.0), Color("d8c2a8"))
	_add_box(xue_mai, Vector3(0.30, 0.06, 0.24), Vector3(0.0, 0.52, 0.0), Color("6d211d"))
	_export_glb(xue_mai, "units", "xue_mai_xiu_shi.glb")

	# 10 机关军团：四台小机关成方阵 + 军旗。
	var jun_tuan: Node3D = _new_root("JI_GUAN_JUN_TUAN")
	for sx: int in range(2):
		for sz: int in range(2):
			var offset: Vector3 = Vector3(-0.16 + float(sx) * 0.32, 0.17, -0.16 + float(sz) * 0.32)
			_add_box(jun_tuan, Vector3(0.20, 0.34, 0.20), offset, SLATE)
			_add_box(jun_tuan, Vector3(0.10, 0.08, 0.10), offset + Vector3(0.0, 0.21, 0.0), GOLD)
	_add_cylinder(jun_tuan, 0.02, 0.70, Vector3(0.30, 0.35, -0.30), INK, 6)
	_add_box(jun_tuan, Vector3(0.22, 0.14, 0.012), Vector3(0.42, 0.62, -0.30), CINNABAR)
	_export_glb(jun_tuan, "units", "ji_guan_jun_tuan.glb")


func _gen_buildings() -> void:
	# 1 山门：两柱 + 横梁 + 丹砂檐 + 匾额。
	var shan_men: Node3D = _new_root("SHAN_MEN")
	_add_box(shan_men, Vector3(1.10, 0.10, 0.44), Vector3(0.0, 0.05, 0.0), SLATE)
	_add_cylinder(shan_men, 0.065, 0.62, Vector3(-0.42, 0.41, 0.0), BONE, 6)
	_add_cylinder(shan_men, 0.065, 0.62, Vector3(0.42, 0.41, 0.0), BONE, 6)
	_add_box(shan_men, Vector3(1.02, 0.10, 0.16), Vector3(0.0, 0.74, 0.0), CINNABAR)
	_add_roof(shan_men, 0.66, 0.24, Vector3(0.0, 0.90, 0.0), INK_SOFT)
	_add_box(shan_men, Vector3(0.30, 0.14, 0.05), Vector3(0.0, 0.62, 0.09), GOLD)
	_export_glb(shan_men, "buildings", "shan_men.glb")

	# 2 宗主大殿：重台 + 主殿 + 双重檐。
	var da_dian: Node3D = _new_root("ZONG_ZHU_DA_DIAN")
	_add_box(da_dian, Vector3(1.24, 0.14, 1.04), Vector3(0.0, 0.07, 0.0), BONE)
	_add_box(da_dian, Vector3(1.02, 0.10, 0.84), Vector3(0.0, 0.19, 0.0), SLATE)
	_add_box(da_dian, Vector3(0.86, 0.46, 0.68), Vector3(0.0, 0.47, 0.0), Color("c9c0a6"))
	for index: int in range(4):
		var x: float = -0.33 + float(index) * 0.22
		_add_cylinder(da_dian, 0.035, 0.44, Vector3(x, 0.47, 0.35), CINNABAR, 6)
	_add_roof(da_dian, 0.80, 0.30, Vector3(0.0, 0.85, 0.0), INK_SOFT)
	_add_box(da_dian, Vector3(0.48, 0.20, 0.38), Vector3(0.0, 1.04, 0.0), Color("c9c0a6"))
	_add_roof(da_dian, 0.56, 0.26, Vector3(0.0, 1.26, 0.0), GOLD)
	_export_glb(da_dian, "buildings", "zong_zhu_da_dian.glb")

	# 3 藏经阁：三层楼阁，逐层收进。
	var cang_jing: Node3D = _new_root("CANG_JING_GE")
	_add_box(cang_jing, Vector3(0.76, 0.16, 0.76), Vector3(0.0, 0.08, 0.0), BONE)
	_add_box(cang_jing, Vector3(0.62, 0.30, 0.62), Vector3(0.0, 0.31, 0.0), Color("cfc7b0"))
	_add_roof(cang_jing, 0.56, 0.20, Vector3(0.0, 0.56, 0.0), INK_SOFT)
	_add_box(cang_jing, Vector3(0.46, 0.26, 0.46), Vector3(0.0, 0.79, 0.0), Color("cfc7b0"))
	_add_roof(cang_jing, 0.44, 0.18, Vector3(0.0, 1.01, 0.0), INK_SOFT)
	_add_box(cang_jing, Vector3(0.32, 0.22, 0.32), Vector3(0.0, 1.21, 0.0), Color("cfc7b0"))
	_add_roof(cang_jing, 0.34, 0.20, Vector3(0.0, 1.42, 0.0), GOLD)
	_export_glb(cang_jing, "buildings", "cang_jing_ge.glb")

	# 4 修炼分峰：演武台 + 讲堂 + 侧塔。
	var xiu_lian: Node3D = _new_root("XIU_LIAN_FEN_FENG")
	_add_box(xiu_lian, Vector3(1.14, 0.10, 1.14), Vector3(0.0, 0.05, 0.0), SLATE)
	_add_cylinder(xiu_lian, 0.34, 0.06, Vector3(-0.18, 0.13, 0.20), BONE, 12)
	_add_box(xiu_lian, Vector3(0.54, 0.34, 0.46), Vector3(-0.12, 0.33, -0.22), Color("c9c0a6"))
	_add_roof(xiu_lian, 0.50, 0.24, Vector3(-0.12, 0.62, -0.22), JADE)
	_add_box(xiu_lian, Vector3(0.20, 0.52, 0.20), Vector3(0.40, 0.36, -0.34), Color("cfc7b0"))
	_add_roof(xiu_lian, 0.20, 0.16, Vector3(0.40, 0.70, -0.34), INK_SOFT)
	_export_glb(xiu_lian, "buildings", "xiu_lian_fen_feng.glb")

	# 5 丹堂分峰：丹房 + 丹炉 + 炉烟。
	var dan_tang: Node3D = _new_root("DAN_TANG_FEN_FENG")
	_add_box(dan_tang, Vector3(1.10, 0.10, 0.92), Vector3(0.0, 0.05, 0.0), SLATE)
	_add_box(dan_tang, Vector3(0.56, 0.34, 0.50), Vector3(-0.22, 0.33, -0.10), Color("c9c0a6"))
	_add_roof(dan_tang, 0.52, 0.24, Vector3(-0.22, 0.62, -0.10), CINNABAR)
	_add_cylinder(dan_tang, 0.19, 0.24, Vector3(0.32, 0.28, 0.16), Color("6d5a44"), 10)
	_add_cone(dan_tang, 0.20, 0.14, Vector3(0.32, 0.47, 0.16), GOLD, 10)
	_add_sphere(dan_tang, 0.055, Vector3(0.32, 0.62, 0.16), Color("cfc7b0"))
	_add_sphere(dan_tang, 0.04, Vector3(0.36, 0.72, 0.20), Color("cfc7b0"))
	_export_glb(dan_tang, "buildings", "dan_tang_fen_feng.glb")

	# 6 器堂分峰：锻坊 + 烟囱 + 铁砧。
	var qi_tang: Node3D = _new_root("QI_TANG_FEN_FENG")
	_add_box(qi_tang, Vector3(1.10, 0.10, 0.92), Vector3(0.0, 0.05, 0.0), SLATE)
	_add_box(qi_tang, Vector3(0.60, 0.34, 0.50), Vector3(-0.18, 0.33, -0.10), Color("b8b0a0"))
	_add_roof(qi_tang, 0.54, 0.22, Vector3(-0.18, 0.61, -0.10), INK_SOFT)
	_add_box(qi_tang, Vector3(0.12, 0.46, 0.12), Vector3(0.16, 0.39, -0.22), Color("6d5a44"))
	_add_box(qi_tang, Vector3(0.26, 0.10, 0.16), Vector3(0.34, 0.15, 0.20), SLATE)
	_add_box(qi_tang, Vector3(0.06, 0.18, 0.06), Vector3(0.34, 0.28, 0.20), BRONZE)
	_export_glb(qi_tang, "buildings", "qi_tang_fen_feng.glb")

	# 7 讲道台分峰：四面开敞的亭子 + 讲席。
	var jiang_dao: Node3D = _new_root("JIANG_DAO_FEN_FENG")
	_add_box(jiang_dao, Vector3(1.10, 0.10, 1.10), Vector3(0.0, 0.05, 0.0), BONE)
	_add_box(jiang_dao, Vector3(0.80, 0.06, 0.80), Vector3(0.0, 0.13, 0.0), Color("c9c0a6"))
	for sx: int in range(2):
		for sz: int in range(2):
			_add_cylinder(jiang_dao, 0.04, 0.52,
				Vector3(-0.34 + float(sx) * 0.68, 0.42, -0.34 + float(sz) * 0.68), CINNABAR, 6)
	_add_roof(jiang_dao, 0.68, 0.28, Vector3(0.0, 0.80, 0.0), JADE)
	_add_box(jiang_dao, Vector3(0.22, 0.20, 0.16), Vector3(0.0, 0.26, -0.06), Color("8a6a3f"))
	_export_glb(jiang_dao, "buildings", "jiang_dao_fen_feng.glb")

	# 8 护山剑阵：石台 + 四剑柱 + 中心晶。
	var jian_zhen: Node3D = _new_root("HU_SHAN_JIAN_ZHEN")
	_add_cylinder(jian_zhen, 0.62, 0.10, Vector3(0.0, 0.05, 0.0), SLATE, 12)
	for index: int in range(4):
		var angle: float = TAU * float(index) / 4.0 + PI * 0.25
		var offset: Vector3 = Vector3(cos(angle) * 0.46, 0.0, sin(angle) * 0.46)
		_add_box(jian_zhen, Vector3(0.07, 0.66, 0.07), offset + Vector3(0.0, 0.43, 0.0), BONE)
		_add_box(jian_zhen, Vector3(0.04, 0.26, 0.04), offset + Vector3(0.0, 0.86, 0.0), AZURE, -angle, 0.12)
	_add_roof(jian_zhen, 0.16, 0.34, Vector3(0.0, 0.28, 0.0), AZURE)
	_add_roof(jian_zhen, 0.16, -0.24, Vector3(0.0, 0.10, 0.0), AZURE)
	_export_glb(jian_zhen, "buildings", "hu_shan_jian_zhen.glb")

	# 9 祖祠：享堂 + 三座神主 + 香炉。
	var zu_ci: Node3D = _new_root("ZU_CI")
	_add_box(zu_ci, Vector3(1.08, 0.10, 0.86), Vector3(0.0, 0.05, 0.0), BONE)
	_add_box(zu_ci, Vector3(0.78, 0.36, 0.52), Vector3(0.0, 0.28, -0.10), Color("c9c0a6"))
	_add_roof(zu_ci, 0.72, 0.28, Vector3(0.0, 0.60, -0.10), INK_SOFT)
	for index: int in range(3):
		var x: float = -0.20 + float(index) * 0.20
		_add_box(zu_ci, Vector3(0.08, 0.16, 0.04), Vector3(x, 0.20, 0.30), GOLD)
	_add_cylinder(zu_ci, 0.09, 0.14, Vector3(0.0, 0.19, 0.34), Color("6d5a44"), 8)
	_add_sphere(zu_ci, 0.03, Vector3(0.0, 0.30, 0.34), CINNABAR)
	_export_glb(zu_ci, "buildings", "zu_ci.glb")

	# 10 王朝帝都：大殿 + 双翼 + 城台 + 阙楼。
	var di_du: Node3D = _new_root("WANG_CHAO_DI_DU")
	_add_box(di_du, Vector3(1.40, 0.16, 1.06), Vector3(0.0, 0.08, 0.0), BONE)
	_add_box(di_du, Vector3(1.16, 0.12, 0.86), Vector3(0.0, 0.22, 0.0), SLATE)
	_add_box(di_du, Vector3(0.72, 0.50, 0.58), Vector3(0.0, 0.53, 0.0), Color("c9c0a6"))
	_add_roof(di_du, 0.78, 0.34, Vector3(0.0, 0.95, 0.0), GOLD)
	for sx: int in range(2):
		var sign: float = -1.0 if sx == 0 else 1.0
		_add_box(di_du, Vector3(0.26, 0.30, 0.44), Vector3(sign * 0.56, 0.43, -0.06), Color("b8b0a0"))
		_add_roof(di_du, 0.30, 0.18, Vector3(sign * 0.56, 0.66, -0.06), INK_SOFT)
		_add_box(di_du, Vector3(0.14, 0.46, 0.14), Vector3(sign * 0.60, 0.51, 0.42), CINNABAR)
		_add_roof(di_du, 0.18, 0.16, Vector3(sign * 0.60, 0.82, 0.42), GOLD)
	_add_box(di_du, Vector3(0.26, 0.30, 0.06), Vector3(0.0, 0.35, 0.29), CINNABAR)
	_export_glb(di_du, "buildings", "wang_chao_di_du.glb")
