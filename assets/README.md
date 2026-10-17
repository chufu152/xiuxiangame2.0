# assets/ —— 独立、可替换的美术资源包（水墨风 2.5D）

美术资源**完全独立于代码**：客户端只通过稳定的"逻辑资源 ID"引用，由 `manifest.json` 映射物理文件。**换皮 = 换皮肤包文件夹 + 改 manifest，不改任何代码。**

> 风格权威依据：`docs/ART_STYLE_REFERENCE.md`。本作为**简化手绘水墨风 2.5D**：采用 3D 低模资产 + 手绘/水墨材质，但**锁定正交 45° 等距相机、不可旋转**，呈现固定 2.5D（非自由 3D）。

## 皮肤包（skin pack）

```
assets/
├── manifest.json          # 全局清单：当前皮肤包名 + 分组逻辑 ID → 文件路径
├── art/
│   ├── default/           # 默认皮肤包（青绿山水 + 水墨 / 手绘低模 2.5D）
│   │   ├── terrain/       # 地形材质：基底顶面/海拔侧面/河流/险地/宣纸/水墨古图（.png）
│   │   ├── units/         # 10 兵种 3D 模型（.glb）
│   │   ├── buildings/     # 10 建筑 3D 模型（.glb）
│   │   ├── districts/     # 6 区域整套建筑群模型（.glb）
│   │   ├── features/      # 地貌/节点/改良/连绵山体装饰 3D 模型（.glb）
│   │   ├── materials/     # 水墨材质、轮廓描边 shader、宣纸/古地图材质（.tres/.gdshader）
│   │   ├── particles/     # 灵气流、云气、法阵、符文、云雾、泼墨转场（.tres/.gdshader）
│   │   ├── ui/            # UI 底板、边框、按钮
│   │   ├── icons/         # 资源、境界、势力、道法、状态图标（.png）
│   │   └── atlas/         # 图集（可选）
│   └── <other_pack>/      # 其它皮肤包（切换 manifest 即可）
├── audio/{bgm,sfx}/
└── fonts/
```

## 资源形式（2.5D）

- **3D 模型 `model`（`.glb`）**：单位、建筑、区域建筑群、地貌、节点、改良。统一比例、原点锚点在底面中心、面向 45° 等距相机。
- **材质/贴图 `texture`（`.png`）**：地形基底顶面/海拔侧面/河流/险地/三态迷雾（宣纸、水墨古图）、UI 图标。
- **材质/粒子 `material/particle`（`.tres/.gdshader`）**：水墨渲染、轮廓描边、灵气流、云雾、泼墨。
- 纹理过滤统一 **Linear**（手绘，不是像素 Nearest）。

## 逻辑资源 ID（稳定，代码只认它）

完整清单见 `manifest.json`，要点：

| 分类 | 逻辑 ID（示例） | 数量 | 形式 |
|---|---|---|---|
| 基底/海拔/河/险 | `terrain.base.*`、`terrain.relief.*`、`terrain.river`、`terrain.danger` | 11 | 材质 |
| 三态迷雾 | `terrain.fog.RICE_PAPER / INK_MAP`（实景为正常材质） | 2 | 材质 |
| 地貌/节点 | `terrain.feature.SPIRIT_FOREST / MIRE`、`node.*` | 8 | 模型 |
| 兵种 | `unit.PU_TONG … JI_GUAN_JUN_TUAN` | 10 | 模型 |
| 建筑 | `building.SHAN_MEN … WANG_CHAO_DI_DU` | 10 | 模型 |
| 区域 | `district.SHOU_FU_QU … SHI_JI_QU` | 6 | 模型 |
| 改良 | `improvement.LING_TIAN_TI_TIAN … LING_QUAN_XIU_SHAN` | 8 | 模型 |
| 资源/境界/势力 | `resource.*`（13）、`realm.*`（5）、`faction.*`（3） | 21 | 图标 |

> 逻辑 ID 一旦确定**不随皮肤改变**；物理文件可随意替换、改名、改风格。

## 地形分层与三态迷雾（2.5D）

- 六边形柱体多层叠加（`world/TileMesh` 按序绘制）：①侧面（按海拔 FLAT/HILL/MOUNTAIN）②顶面（基底材质，MOUNTAIN 加峰顶）③地貌模型（灵林/雾泽）④河流（贴边水面）⑤险地/节点/改良模型。
- 柱高按 `data/gameConfig.json` 的 `map.relief`（FLAT 1.0 / HILL 1.7 / MOUNTAIN 3.0，设计初值）；相邻多格山岳连成连绵山体；顶面落点由 `shared/geo/hex.gd` 统一计算，单位沿坡面落地。
- **三态迷雾**（`world/Fog`）：未探索盖 `terrain.fog.RICE_PAPER` 宣纸（边缘泼墨褪去）；已探索无视野盖 `terrain.fog.INK_MAP` 水墨古地图（排线速写，仅地形/最后可见城市改良，无单位）；视野内为正常 2.5D 实景。

## manifest.json 约定

条目至少含 `id`、`path`、`type`；模型可含 `anchor`（默认 `ground`）、统一比例；贴图可含九宫格切片。`AssetLibrary`（`client/scripts/art/`）负责：

1. 启动读 manifest，建立 ID → 路径表（遍历 terrain/features/units/buildings/districts/improvements/resources/realms/factions 等分组）。
2. 按 type 加载：`model`→`.glb`、`texture`→`.png`、`material/particle`→`.tres/.gdshader`，懒加载缓存。
3. **缺失资源不崩溃**：模型回退水墨灰阶几何体 + 文字标签，贴图回退色块，打印 `WARN`。
4. 支持开发期 F5 热重载 manifest。

## 最小水墨资源包（R8 前置交付）

`assets/art/default/` 下的实体文件由**程序化生成器**产出，覆盖 ROADMAP §3.2 的八类清单（共 52 个文件）：

| 类别 | 逻辑 ID | 数量 | 文件 |
|---|---|---|---|
| 基底顶面 | `terrain.base.{LING_FIELDS,SPIRIT_PLAIN,BARREN}` | 3 | `terrain/top_*.png` |
| 海拔侧面 + 山体顶面 | `terrain.relief.{FLAT,HILL,MOUNTAIN}_SIDE`、`MOUNTAIN_TOP` | 4 | `terrain/side_*.png`、`terrain/mountain_peak.png` |
| 河流 / 险地 | `terrain.river`、`terrain.danger` | 2 | `terrain/river.png`、`terrain/danger.png` |
| 三态迷雾 | `terrain.fog.{RICE_PAPER,INK_MAP}` | 2 | `terrain/fog_*.png`（第三态=实景，走正常材质） |
| 兵种 | `unit.*` | 10 | `units/*.glb` |
| 建筑 | `building.*` | 10 | `buildings/*.glb` |
| 图标 | `resource.*`、`realm.*`、`faction.*` | 21 | `icons/*.png` |

**未覆盖**（`AssetLibrary` 仍回退占位并 WARN 一次，属计划内）：`districts`（6）、`improvements`（8）、`features`/`node`（8）、`audio`（1）、`fonts`（2）。

### 再生成与核验

```powershell
$godot = "C:\Users\Administrator\godot\Godot_v4.4.1-stable_win64_console.exe"
& $godot --headless --path client res://tools/AssetGen.tscn      # 重新生成 52 个文件（ASSETGEN_OK）
& $godot --headless --path client res://tools/AssetVerify.tscn   # 断言最小包零 WARN（ASSETVERIFY_OK）
& $godot --headless --path client res://tools/AssetPreview.tscn  # 输出 outputs/r8_asset_*.png 供人工核验
```

- `AssetGen`：**确定性**（固定 seed 的哈希值噪声，不读全局随机），零外部依赖，只写 `assets/art/default/`。
- `AssetVerify`：用客户端 `AssetLibrary` 逐 ID 取资源，最小包必须 `covered=52 warned=0`；同时校验 20 个模型的几何（非退化、底面锚 `y≈0`、单位 ≤1.4 高、建筑 ≤1.75 宽）。
- `AssetPreview`：CPU 等距光栅化，把 20 个模型 / 21 个图标 / 11 张材质拼成联络表，写到 `outputs/`（不入库）。

> 真实美术介入时，**直接用同名文件覆盖即可**——`manifest.json` 与代码都不用改。生成器是「可复现的最小基线」，不是最终美术方案。

## 美术规范（默认皮肤包）

- 风格：简化手绘水墨、青绿山水 + 留白云雾；主色青、白、浅金；建筑斗拱飞檐、依山半嵌；功能色读图（丹房红、药田绿、地形底色）。
- 所有模型做**轮廓描边强化**，全局缩到最远仍可分辨设施；区域为整套建筑群（宫殿/庙宇/广场），不堆单格；改良为叠加小模型，被掠夺后破损。
- 动效：简易昼夜、草木摆动、飞鸟、灵气粒子；道路青石砖、地块归属宗门色边框、网格线可开关。
- 命名：物理文件小写蛇形（`jian_xiu.glb`、`top_spirit_plain.png`），与枚举键对应；多分辨率用 `@2x`。
- 音频：BGM `.ogg` 循环；SFX `.wav/.ogg`；字体放 `fonts/`。
