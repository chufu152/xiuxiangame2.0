# assets/ —— 独立、可替换的美术资源包

美术资源**完全独立于代码**：客户端只通过稳定的"逻辑资源 ID"引用美术，由 `manifest.json` 把 ID 映射到物理文件。**换皮 = 换一个皮肤包文件夹 + 改 manifest，不改任何代码。**

## 皮肤包（skin pack）

```
assets/
├── manifest.json          # 全局清单：当前皮肤包名 + 逻辑 ID → 文件路径
├── art/
│   ├── default/           # 默认皮肤包（青绿山水鎏金 / 精致像素 / 2.5D）
│   │   ├── terrain/       # 地形（hex 柱体贴图）
│   │   ├── units/         # 兵种 / 弟子立绘或像素单位
│   │   ├── buildings/     # 建筑
│   │   ├── ui/            # UI 底板、边框、按钮
│   │   ├── icons/         # 资源、境界、道法、状态图标
│   │   └── atlas/         # 图集（可选）
│   └── <other_pack>/      # 其它皮肤包（可随时加入，切换 manifest 即可）
├── audio/
│   ├── bgm/
│   └── sfx/
└── fonts/
```

## 逻辑资源 ID（稳定，代码只认它）

ID 用「分类.键」命名，与游戏枚举一一对应，例如：

| 逻辑 ID | 对应游戏概念 |
|---|---|
| `terrain.PLAIN` / `terrain.DANGER` / `terrain.FOREST` / `terrain.MOUNTAIN` / `terrain.SPIRIT_VEIN` / `terrain.SPIRIT_SPRING` / `terrain.RIVER` | 地形 |
| `unit.PU_TONG`、`unit.JIAN_XIU`、`unit.FA_XIU` … `unit.JIAN_ZHEN` / `unit.XUE_MAI` / `unit.JIGUAN_BINGTUAN` | 10 兵种 |
| `building.MOUNTAIN_GATE` / `building.HALL` / `building.CLASSICS` … | 建筑 |
| `improvement.LING_TIAN` / `improvement.ROAD` … | 改良 |
| `resource.spiritPower` / `resource.spiritStones` / `resource.workPower` … | 资源图标 |
| `realm.LIAN_QI` … `realm.HUA_SHEN` | 境界图标 |
| `faction.ZONG_MEN` / `FAMILY` / `DYNASTY` | 势力徽记 |

> 逻辑 ID 一旦确定**不随皮肤改变**；物理文件可以随意替换、改名、改风格。

## manifest.json 约定

每个资源条目至少含：`id`、`path`、`type`，可含像素尺寸 `size`、锚点 `offset`、是否竖直板 `billboard`、九宫格切片 `nine_patch`。客户端 `AssetLibrary`（`client/scripts/art/`）负责：

1. 启动时读取 `manifest.json`，建立 ID → 路径表。
2. 按 ID 用 `ResourceLoader.load()` 懒加载并缓存 `Texture2D`。
3. **缺失资源不崩溃**：回退到程序化占位（按分类给色块 + 文字标签），并打印一条 `WARN`。
4. 支持开发期热重载（F5 重新读 manifest，不重启游戏）。

## 美术规范（默认皮肤包）

- 风格：精致像素、青绿山水 + 鎏金点缀、中式修仙、斜俯视 2.5D。
- 纹理过滤：**Nearest**（像素风不糊），关闭 mipmap 或按需要开；导入保持像素比例。
- 地形柱：与 `data/gameConfig.json` 的 `map.hexSize` / 地形高度对齐（平原 4、险地 8、灵峰 20 等），保证相邻地块无缝拼接。
- 单位/建筑：统一基准像素高度、朝向（面向斜俯视相机）、底部落点锚点（`offset.y` 落在柱顶）。
- 命名：物理文件小写蛇形（`jian_xiu.png`），与枚举键对应；同 ID 多分辨率用后缀（`@2x`）。
- 音频：BGM 用 `.ogg` 循环；SFX 用 `.wav/.ogg`，短音效；音量规范在 manifest 注明。
- 字体：中文像素/书法字体放入 `fonts/`，manifest 声明正文/标题字体。
