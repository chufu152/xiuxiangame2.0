# 《修仙4X·宗门争霸》2.0 重构需求文档（PRD + 技术规格）

| 项 | 内容 |
|---|---|
| 文档版本 | v1.1（2.0 重构基线；新增文明6式地形起伏系统，全量数值按 1.0 配置复核） |
| 日期 | 2026-10-16 |
| 性质 | **借重构重新设计**：技术架构从零重做；玩法以 1.0 成熟实现为蓝本冻结并裁剪；**地图地形升级为文明6式分层起伏（2.0 新增）** |
| 技术 | **全程 Godot 4.x / GDScript（静态类型），零 Java**；服务端权威 + 客户端表现，前后端分离，WebSocket |
| 美术风格 | **简化手绘水墨风 2.5D**（青绿山水 + 水墨山水）；3D 低模资产 + **锁定正交 45° 等距相机、不可旋转，呈现固定 2.5D，不做自由 3D 视角**；见 `docs/ART_STYLE_REFERENCE.md` |
| 仓库 | `https://github.com/chufu152/xiuxiangame2.0.git` |
| 数值权威 | `data/gameConfig.json`（1.0 迁移项以配置为准；标 **【2.0新增·设计初值】** 的地形参数为本次设计、需在 R1/R3 调参） |
| 蓝本来源 | 1.0 源码 `gameConfig.json`、`GameEngine`、`TurnProcessor`、`CombatResolver`、`UnitRules`、`EconomyCalculator`、`PROTOCOL.md`、`COMMAND_MAP.md`（只读，不进 2.0） |

> **使用方式**：本文是 2.0 唯一权威需求，每章可直接拆成 WorkBuddy 任务。标 **【默认·待确认】** 的是已给推荐默认、允许评审修改的少数决策；标 **【2.0新增·设计初值】** 的是本次新设计、数值可调的部分；其余为冻结需求。
>
> **文档权威层级（冲突裁决顺序，高者优先）**：
> ① `data/gameConfig.json`（已落地的实际数值）＞ ② **本文**（需求与口径）＞ ③ `docs/prompts/*.md`（可执行任务切片）＞ ④ `README.md` / `data/README.md` / `assets/README.md`（导读）。
> 低层级与高层级冲突时**以高层级为准并回改低层级**。任何里程碑完成后必须**回写本文与对应提示词**（状态、实际交付、偏差），禁止只改代码不改文档。

---

## 0. 阅读对象与范围

- 给：服务端、客户端、策划数值、QA。
- 规定：2.0 首版**做什么、不做什么**；架构与通信；玩法规则与数值；地形起伏；里程碑与验收；工程/Git 规范。
- 不规定：美术成品（给规范与资源位）、UI 视觉稿（给交互与信息要求）、真实多人联网（架构预留，首版不做）。

---

# 第一部分　项目与架构

## 1. 项目概述

### 1.1 定位

- 类型：单机、回合制、4X（探索/扩张/经营/征服）。
- 题材：中式修仙·宗门争霸。
- 一局：1 玩家 + 3 AI，在**带地形起伏的六边形地图**上争夺资源、扩张灵峰、修炼道统、攻城略地，按流派目标或分数取胜。
- 三流派（枚举 `FactionType`）：
  - **宗门流 ZONG_MEN**：道统推演；研究 +30%、营造 +30%、探索 +20%、气运 +25%、副峰花费 −20%；特色兵种 **剑阵使 JIAN_ZHEN_SHI**、特色建筑 **护山剑阵 HU_SHAN_JIAN_ZHEN**（落成防御 +25）。
  - **家族流 JIA_ZU**：血脉繁衍；血脉修炼 +40%、高品灵根概率 +15%、血脉道法消耗 −20%、祖祠修炼 +25%/繁衍费 −30%/每回合安定 +1；特色兵种 **血脉修士 XUE_MAI_XIU_SHI**、特色建筑 **祖祠 ZU_CI**；建峰花费 +50%、开峰 +60%。
  - **国家流 GUO_JIA**：王朝扩张；开峰 −30%、扩张 −20%、领土势力权重 ×1.5、帝都住房 +10/人口增长 +50%；特色兵种 **机关军团 JI_GUAN_JUN_TUAN**、特色建筑 **王朝帝都 WANG_CHAO_DI_DU**；稀有材料惩罚 −20%。

### 1.2 设计支柱（优先保护的核心乐趣）

1. **多流派异质胜利**：科技飞升 / 血脉繁衍 / 领土征服三条路线体验与目标显著不同。
2. **地形起伏与空间决策（2.0 强化）**：海拔、地貌、河流、险地决定建城选址、扩张方向、布阵与行军，参考文明6"在哪建、走哪、打哪"的空间取舍。
3. **弟子成长与渡劫抉择**：灵根、境界、心魔、晋升、转职构成养成取舍。
4. **战术战斗**：十兵种相克、丘陵高地/跨河/灵林/险地、城防、ZOC、远程零反击、撤退，以可预览胜率决策。
5. **城市经营拼图**：区域独立占地 + 地形邻接、人口/住房/安定/劳力、灵峰容量与铺张惩罚。
6. **确定性与可复现**：固定种子整局可复现（服务端权威 + 集中随机源）。

### 1.3 平台、输入、呈现

- 平台：PC（Windows 优先，Godot 可跨平台导出）。
- 输入：鼠标（点选、框选、悬停、滚轮）+ 键盘快捷键（结束回合等）。
- 呈现：**简化手绘水墨风 2.5D**（青绿山水 + 水墨山水，详见 `docs/ART_STYLE_REFERENCE.md`）。**2.5D 定义：正交投影相机固定 yaw=45°、pitch=45°，不可旋转、不可自由环绕，仅缩放（正交 size，以鼠标为中心）与平移；场景用 3D 低模资产，但最终观感为固定等距 2.5D，不做自由 3D 视角。**
- 地图：flat-top 六边形，轴向坐标 `(q,r)`，默认 20×15 = 300 格；六边形柱体高度随海拔起伏，山脉跨多格连成连绵山体（见 4.1）。
- **三态画卷迷雾**：未探索=宣纸空白（泼墨褪去）、已探索无视野=水墨古地图（排线速写，不显示单位/不更新敌方新建筑）、视野内=等距 2.5D 实景（见 4.2）。
- 单局：约 2–4 小时（240 回合上限）。

### 1.4 首版范围一览

- **纳入**：分层地形与起伏、河流、迷雾、三流派、弟子（境界/灵根/岗位/修炼/心魔/血脉）、回合循环与经济、灵峰/城市/区域/人口、地块改良与道路、道统科技树、十兵种战术战斗（攻城/夺点/撤退/传送）、探索（机缘/秘境）、任命/渡劫/飞升、政令（裁剪）、自动化、三流派胜利与分数胜利、基础反应式 AI、存档。
- **暂不纳入（见第 5 章）**：外交/厌战、随机事件库、叛乱/忠诚、蛮族巢穴、灾劫、AI 长期战略性格；自然奇观、雪山/沙漠/雨林/地热等更多地形、登山单位、天气季节（地形后续扩展，见 4.1.11）。

---

## 2. 技术架构（全 Godot 前后端分离，零 Java）

### 2.1 总览

```
┌───────────────────────────────┐         WebSocket (JSON 文本帧)        ┌──────────────────────────────┐
│           client/             │   ws://127.0.0.1:9527（单机回环）        │           server/            │
│  Godot 客户端（渲染/表现）      │  ═══════════════════════════════════> │  Godot --headless（权威逻辑）  │
│  - 场景/相机/输入/动画/Tween    │  请求 {id,type,params}                  │  - GameState（唯一真相）       │
│  - HUD 与面板                  │  <─────────────────────────────────── │  - rules/ 全部规则            │
│  - AssetLibrary（可替换美术）   │  响应 {id,ok,events,view,result}       │  - config/ 读 gameConfig.json │
│  - 零玩法规则                  │  主动 hello / awaitInput(victory)       │  - save/ 存档                 │
└───────────────────────────────┘                                         └──────────────────────────────┘
        ▲ 引用                          两端共享 shared/protocol、shared/geo        ▲ 读取
┌───────┴────────┐                                          ┌──────────────────────┐  ┌──────────────────┐
│ assets/ 美术包  │ （客户端独占，可整体替换）                 │ data/gameConfig.json  │  │ saves/（FileAccess）│
└────────────────┘                                          └──────────────────────┘  └──────────────────┘
```

- **权威在服务端**：地图、随机、移动范围、视野、产出、伤害、胜率、胜负全部服务端算。客户端**不实现任何玩法规则**，只做表现/输入/界面；"能不能做/花多少/会怎样"一律走 `query*`。
- **单机运行形态**：客户端启动时用 `OS.create_process` 拉起本地 headless `server`（传 `--port=9527 --data=<path>`），连接 `ws://127.0.0.1:9527`；退出时关闭子进程。服务端可单独运行。
- **未来联机预留**：协议与部署无关，远程联机只需把服务端部署到主机（首版**不做**真联机，只保证不堵死）。

### 2.2 关键技术决策

| 决策点 | 选择 | 理由 |
|---|---|---|
| 语言 | **GDScript（静态类型）** | 两端单语言、与 Godot 结合最好；禁用弱类型，全部类型注解 |
| 工程数量 | **两个 Godot 工程**（`client/`、`server/`） | 物理隔离规则与表现；服务端无头可导出，不打包美术 |
| 共享代码 | 顶层 `shared/`，以**目录联接（junction）**挂进两端 | 协议常量/枚举/DTO/几何两端一致；`tools/setup_shared.ps1` 建联接 |
| 通信 | **WebSocket + JSON 文本帧**（`WebSocketPeer`） | 回合制需可靠有序；本地/远程皆可；好调试 |
| 服务端 | Godot `--headless` 主场景 `ServerMain.tscn` | 无渲染/音频/输入，可在 CI 无头跑 |
| 数据格式 | JSON（小驼峰字段，枚举大写下划线） | 与 1.0 协议一致，便于同种子对照 |
| 配置 | `data/gameConfig.json` 启动加载 + 校验 | 数值与代码分离；服务端独占 |
| 存档 | `FileAccess` 写 JSON 到 `user://saves/`（开发期指工程 `saves/`） | 槽位、版本、自动存档 |

> **【默认·待确认】** 语言 GDScript（不选 C#，避免双工具链；不混用）；通信 WebSocket（不选 stdio/ENet，理由见评审记录）。

### 2.3 目录结构（落地约定）

```
xiuxiangame2.0/
├── client/
│   ├── project.godot
│   ├── scenes/        # MainMenu / Game（地图）/ HUD / 对话框与面板
│   ├── scripts/
│   │   ├── net/       # NetClient（连接/收发包/重连/拉起子进程）
│   │   ├── world/     # HexMap、CameraRig（锁45°）、TileMesh（按海拔起伏）、RiverMesh、
│   │   │              #   UnitView、PeakView、Fog
│   │   ├── ui/        # TopBar/BottomBar/LeftPanel/RightPanel、各 Dialog、Toast、VictoryOverlay
│   │   ├── art/       # AssetLibrary（按逻辑 ID 加载 manifest）、占位回退
│   │   └── view/      # view 快照的客户端只读模型（DTO→显示数据，不含规则）
│   └── addons/
├── server/
│   ├── project.godot
│   ├── scenes/ServerMain.tscn
│   └── scripts/
│       ├── net/       # NetServer、CommandDispatcher、StateView、协议编解码
│       ├── model/     # GameState、Sect、Disciple、SpiritPeak、HexTile、GameNode、Project、枚举
│       ├── rules/     # MapGenerator（地形/海拔/河流/节点）、MoveRange、Vision、Combat、
│       │              #   Economy、Population、City、Improvement、Road、Dao、Explore、
│       │              #   Appointment、Policy、Automation、Victory、AI、TurnProcessor
│       ├── config/    # ConfigLoader、ConfigValidator（缺字段即报错）
│       ├── rng/       # 集中随机源（按种子+回合+序列号派生，保证可复现）
│       └── save/      # SaveManager
├── shared/protocol/
│   ├── commands.gd    # 命令名常量（lowerCamelCase，与 1.0 同名）
│   ├── msg.gd         # 信封/主动消息类型
│   ├── enums.gd       # 枚举字符串（与配置一致，大写下划线）
│   └── dto.gd         # 消息/快照静态类型类（两端共用）
├── shared/geo/
│   ├── hex.gd         # 六边形轴向坐标、邻接、距离、世界坐标（含海拔高度换算，纯函数）
├── assets/            # 见第 3 章
├── data/gameConfig.json
├── docs/、tools/、saves/、exports/
```

### 2.4 服务端分层职责

- `model/`：纯数据实体（`RefCounted`/`Resource`），不写规则、不依赖节点。
- `rules/`：无状态或仅依赖 GameState 的纯函数模块，输入状态 + 命令 → 结果 + 事件；禁止读节点/播音频/访问美术。
- `rng/`：全服唯一随机入口（战斗、地图、探索、AI、繁衍），按 `seed ^ turn ^ 序列号` 派生；禁止散落 `RandomNumberGenerator.new()`。
- `net/CommandDispatcher`：命令名 → rules 方法；参数校验；业务失败与协议失败分离。
- `config/ConfigValidator`：启动校验字段完整性与取值合法（缺字段、非法枚举、负值直接报错退出）。

### 2.5 确定性与可复现（硬约束）

- 固定种子下，同一份命令序列必须产生**逐字一致**的事件流与终局（与 1.0 D1 修复口径一致）。
- 地形生成（含海拔/河流/资源/节点）必须种子确定，不依赖渲染帧率或遍历顺序。
- 所有可变序列使用集中登记序列号；开新局与读档都复位。
- 自检 `tools/check.ps1`：同种子跑两遍 N 回合，事件流逐字一致；并与 1.0 同种子对照核心命令。

### 2.6 存档

- JSON 槽位制（`saves/slot_<n>.json`）；`saveVersion = "3.0"`。
- 每 10 回合自动存档到槽 0；`listSaves` 返回槽号/回合/宗门/流派/时间/大小。
- 保存完整 GameState（种子、序列号、回合、阶段、实体、队列、冷却、地形）；读档后待决点能重建（2.0 仅剩胜利待择）。
- 客户端显示设置不进存档，留本地。

---

## 3. 美术资源规范（独立、可替换、水墨风 2.5D）

> 权威依据 `docs/ART_STYLE_REFERENCE.md`。美术资源**完全独立于代码**，客户端只通过稳定"逻辑资源 ID"引用，由 `assets/manifest.json` 映射物理文件。**换皮 = 换皮肤包文件夹 + 改 manifest，零代码改动。**

### 3.1 风格定位

- **简化手绘水墨风 2.5D**：采用手绘低模 3D 资产 + 水墨/青绿材质，但**锁定正交 45° 等距相机、禁止旋转**，呈现固定 2.5D（非自由 3D）；轮廓清晰，俯瞰全局一眼可读，拉近可见模型细节与动态（飞鸟、风吹草木）。
- 青绿山水 + 水墨山水为骨架，大量留白与云雾营造仙境；主色青、白、浅金，材质白玉/玉石/云；建筑斗拱飞檐、依山半嵌；意象/符号见参考文件。
- **功能色读图**：建筑/设施/地形用固定功能色（丹房红、药田绿、基底地形专属底色）。

### 3.2 资源形式与目录（3D 低模资产，服务于 2.5D 等距）

- `assets/art/<pack>/`（默认 `default`）：
  - `terrain/`：基底顶面 / 海拔侧面 / 河流 / 险地 / 宣纸 / 古地图排线等**材质贴图**。
  - `units/`：10 兵种 3D 模型 `.glb`；`buildings/`：10 建筑模型；`districts/`：6 区域整套建筑群模型。
  - `features/`：地貌（灵林/雾泽）、连绵山体装饰、节点、改良小模型 `.glb`。
  - `materials/`：水墨材质、轮廓描边 shader、宣纸/古地图材质；`particles/`：灵气流、云气、法阵、符文、云雾、泼墨转场。
  - `ui/ icons/ atlas/`：2D 底板/边框/按钮/资源/境界/势力图标。
- `assets/audio/{bgm,sfx}/`、`assets/fonts/`。
- 纹理过滤统一 **Linear**（手绘非像素）；模型统一比例、原点锚点在底面中心、面向 45° 相机。

### 3.3 逻辑 ID（稳定，代码只认它；与 1.0 枚举一致）

- **基底地形**：`terrain.base.LING_FIELDS / SPIRIT_PLAIN / BARREN`
- **海拔**：`terrain.relief.FLAT_SIDE / HILL_SIDE / MOUNTAIN_SIDE / MOUNTAIN_TOP`（侧面材质与峰顶）
- **地貌**：`terrain.feature.SPIRIT_FOREST / MIRE`；`terrain.river`（贴边水面）；`terrain.danger`（险地印记）
- **节点**：`node.LING_TIAN / LING_MAI / JI_YUAN / MI_JING / LING_QUAN / LING_FENG`
- **兵种**：`unit.PU_TONG / JIAN_XIU / FA_XIU / TI_XIU / QI_JI / FU_XIU / JI_GUAN / JIAN_ZHEN_SHI / XUE_MAI_XIU_SHI / JI_GUAN_JUN_TUAN`
- **建筑**：`building.SHAN_MEN / ZONG_ZHU_DA_DIAN / CANG_JING_GE / XIU_LIAN_FEN_FENG / DAN_TANG_FEN_FENG / QI_TANG_FEN_FENG / JIANG_DAO_FEN_FENG / HU_SHAN_JIAN_ZHEN / ZU_CI / WANG_CHAO_DI_DU`
- **区域**：`district.SHOU_FU_QU / XIU_LIAN_QU / DAN_QI_QU / CANG_JING_QU / FA_TAN_QU / SHI_JI_QU`
- **改良**：`improvement.LING_TIAN_TI_TIAN / LING_KUANG / CAI_SHI_CHANG / YAO_YUAN / JU_LING_ZHEN / QING_SHI_DAO_LU / DONG_FU / LING_QUAN_XIU_SHAN`
- **资源**：`resource.spiritPower / spiritStones / workPower / prestige / qiYun / food / daoPoints / tian_jing / xuan_tie / ling_mu / ling_cha / yun_jin / ling_yu`
- **境界/势力**：`realm.LIAN_QI / ZHU_JI / JIN_DAN / YUAN_YING / HUA_SHEN`；`faction.ZONG_MEN / JIA_ZU / GUO_JIA`。

### 3.4 AssetLibrary 行为

1. 启动读 manifest 建 ID→路径表；按 type 加载（`model`→`.glb`、`texture`→`.png`、`material/particle`→`.tres/.gdshader`），懒加载缓存。
2. **缺失资源不崩溃**：回退程序化占位——模型用水墨灰阶几何体 + 文字标签、贴图用色块，打 `WARN`。
3. 支持 F5 热重载 manifest；换皮只改 `activePack` 与物理文件，逻辑 ID 不变。

### 3.5 美术规范

- **模型**：手绘低模 + 轮廓描边强化，全局视角仍可分辨设施（可读性优先）；区域占独立地块、为整套建筑群（宫殿/庙宇/广场 + 配套道路装饰），不堆单格；改良为叠加小模型（梯田/矿井脚手架/药园等），**被掠夺后破损**。
- **地形**：六边形柱体高度随海拔（FLAT 1.0 / HILL 1.7 / MOUNTAIN 3.0，设计初值）；山脉跨多格连成连绵山体；河流贴边水面；灵林/雾泽可叠加。
- **动效**：简易昼夜循环、草木摆动、飞鸟、建筑粒子、灵气漂浮；高阶法器微光符文流转。
- **单位**：仙袍广袖飘带随风；低阶粗布、高阶玉质流光（首版可用贴图分层 + 简化 shader）。
- **道路与归属**：青石砖自动生成；地块归属用宗门颜色边框；六边形网格线可在设置开关。
- **命名**：物理文件小写蛇形（`jian_xiu.glb`、`top_spirit_plain.png`）；BGM `.ogg` 循环、SFX `.wav/.ogg`；字体放 `fonts/`。

---

# 第二部分　玩法规则

> 1.0 迁移项数值以 `data/gameConfig.json` 为准；地形起伏相关为 **【2.0新增·设计初值】**。

## 4. 玩法规则

### 4.1 地图与地形起伏（文明6式分层，2.0 重做）

#### 4.1.1 设计目标与模型

1.0 所有地块基底都是"平原"、仅靠 `danger` 标记区分，空间层次单薄。2.0 每个六边形由**多层可叠加要素**组成（参考文明6：基底地形 + 海拔丘陵/山脉 + 地貌森林/沼泽 + 河流边 + 资源/节点），让建城、扩张、行军、布阵成为空间决策。

```
HexTile {
  id: String,                 # "q{q}_r{r}"
  q, r: int
  baseTerrain: String,        # 基底：LING_FIELDS / SPIRIT_PLAIN / BARREN
  relief: String,             # 海拔：FLAT / HILL / MOUNTAIN
  features: Array[String],    # 地貌：[SPIRIT_FOREST] / [MIRE]（首版至多 1 个）
  riverEdges: Array[int],     # 0..5 中为河流的边（河是"边"不是"格"）
  danger: bool,               # 险地标记（可与海拔/地貌叠加）
  nodeId, ownerSectId, districtId, workedByPeakId, improvementId, luxuryType: String
}
```

#### 4.1.2 基底地形 baseTerrain（决定基础产出）【2.0新增·设计初值】

| 基底 | 定位 | 基础产出（粮/灵/石） | 倾向 |
|---|---|---|---|
| LING_FIELDS 灵田沃野 | 草原（粮多） | 粮3 灵1 | 灵田节点、灵茶、药园 |
| SPIRIT_PLAIN 灵壤 | 平原（均衡，1.0 默认基底） | 粮2 灵2 | 建城、灵林、云锦 |
| BARREN 荒土 | 贫瘠（粮少矿多） | 粮1 石2 | 采石、天晶、偏远 |

> 1.0 只有"平原"，工作产出为 粮3 灵2；2.0 将其拆为 3 种基底并给设计初值，最终以 `map.baseTerrains` 配置为准。

#### 4.1.3 海拔 relief（起伏核心：高度/移动/防御/视野/通行）

| 海拔 | 柱高系数 | 可通行 | 进入移动 | 守方防御 | 视野 | 其它 |
|---|---|---|---|---|---|---|
| FLAT 平地 | 1.0 | 是 | 1 | 0 | 0 | 基准 |
| HILL 丘陵 | 1.7 | 是 | 2 | +20% | 站立者 +1 | 石 +1；玄铁/采石多发；**高处打低处 +15%** |
| MOUNTAIN 山岳 | 3.0 | **否（普通单位）** | — | 不可攻 | — | 天晶/玄铁/灵脉多发；可被**传送**跨越；区域邻接加成源 |

- 比例（设计初值）：平地 70% / 丘陵 22% / 山岳 8%，生成连续山脊而非散点。
- **高地加成**：攻方位于 HILL、守方位于 FLAT（攻方海拔更高）时攻方战力 `×(1+0.15)`（落地 1.0 预留 `highGroundBonus`）。
- **山岳不可通行、不可建城**；首版仅传送可越过（不做登山/飞行单位）。

#### 4.1.4 地貌特征 feature（叠加、可清除）【2.0新增·设计初值】

| 地貌 | 移动叠加 | 防御 | 产出 | 清除 |
|---|---|---|---|---|
| SPIRIT_FOREST 灵林 | +1 | +20% | 灵木+1、粮+1 | 可"清林"，一次性产灵木 2 |
| MIRE 雾泽 | +1 | −10% | 粮+1 | 可"排淤"清除 |

- 灵林可覆盖平地/丘陵；雾泽仅平地。**生成率设计初值：灵林 22% / 雾泽 12%**（最终以 `data/gameConfig.json` 的 `map.features.*.chance` 为准；R1 已按 22% / 12% 落地）。

#### 4.1.5 河流 river（地块边，非地块）

- 生成时以 1–2 处山岳/灵泉为源，沿海拔降低方向蜿蜒至地图边界，在沿岸地块的 `riverEdges` 标记相邻边。
- 沿河地块：粮 +1（灌溉）；是灵泉/灵田/沃野的高发地；建城优先淡水（`querySpiritPeakBlocker` 给缺水提示）。
- **跨河攻击**：攻击路径越过河流边时，攻方 `×(1−0.25)`（落地 1.0 预留 `riverCrossPenalty`）；进入跨河格额外 +1 移动（设计初值，纳入 `map.river`）。

#### 4.1.6 险地 danger（沿用 1.0 标记）

- 生成率 `dangerTileChance=0.1`，与海拔/地貌可叠加（险地丘陵更险）。
- 进入移动 +1（`dangerTileMoveCost=2`）、守方防御 +25%（`terrainDefenseBonus.险地=0.25`）；不刷普通节点（见 4.1.7）；机缘/秘境风险与奖励更高。

#### 4.1.7 节点与资源分布（地形关联）

- 单格节点（1.0 为单格，非多格），按概率生成且**与地形绑定（2.0 新增）**：

| 节点 NodeType | 1.0 生成率 | 2.0 偏好地形 |
|---|---|---|
| LING_TIAN 灵田 | 0.15 | 沃野/灵壤平地 |
| LING_MAI 灵脉 | 0.08 | 丘陵/山岳（优先，权重上调） |
| JI_YUAN 机缘 | 0.06 | 险地、偏远 |
| MI_JING 秘境 | 0.04 | 险地、雾泽 |
| LING_QUAN 灵泉 | 0.05 | 沿河、山岳脚下 |

- 奢侈品生成率 `luxurySpawnChance=0.12`；2.0 按地形分布：灵茶 ling_cha（沃野/灵林）、云锦 yun_jin（灵壤）、灵玉 ling_yu（丘陵/灵泉）。
- 战略材料：玄铁 xuan_tie（丘陵/山岳）、天晶 tian_jing（山岳/险地）、灵木 ling_mu（灵林）。
- 每块非险地格按 灵田→灵脉→机缘→秘境→灵泉 顺序掷骰，至多 1 个节点；出生点邻域清险地、清山岳封死。

#### 4.1.8 移动消耗（叠加，取整 ≥1）

```
进入成本 = 海拔(平地1/丘陵2/山岳不可通行)
        + 地貌(灵林1/雾泽1) + 险地(1) + 跨河(1, 设计初值)
        + 敌方控制区 ZOC(+2) − 本宗道路(1, 最低1)
```
- 移动力为整数（基础 2，见 4.4）；BFS 计算可达，`queryMoveRange` 与实际移动共用同一算法。

#### 4.1.9 地形产出与城市/区域/改良联动

- 地块产出 = 基底 + 海拔（丘陵石+1）+ 地貌（灵林/雾泽/河）+ 资源 + 改良 + 节点产出（节点覆盖格）+ 区域邻接；被劳力指派（`workedByPeakId`）才产出。
- **建城选址**：不可建于 MOUNTAIN；不建议雾泽（可给惩罚）；优先淡水（河/灵泉）或灵脉。
- **改良地形限制（替换 1.0 全限平原）**：灵田梯田→平地沃野；灵矿/采石场→丘陵；药园→平地/雾泽（需丹器区）；聚灵阵→灵泉旁（需道法）；道路→平地/丘陵（不跨山岳）；洞府→平地/丘陵；灵泉修缮→灵泉节点（不可自由建）。
- **区域邻接（在 1.0 八条基础上新增地形邻接）**：藏经区邻山岳 +2 道点；法坛区邻山岳 +2 气运（原有邻险地 +3）；修炼区邻灵泉 +4 灵力（原有）；其余沿用 1.0 邻接表（见 4.7）。

#### 4.1.10 Godot 2.5D 等距起伏表现（客户端）

- 每个六边形为带厚度柱体，顶面世界高度 = `reliefHeight[relief]`（FLAT 1.0 / HILL 1.7 / MOUNTAIN 3.0，设计初值）；山岳为柱体 + 峰顶尖锥，相邻多格山岳连成连绵山体；`shared/geo/hex.gd` 统一计算顶面落点（含海拔），单位在相邻不同高度格间沿坡面移动。
- 河流为贴边水面 ribbon；地貌为顶面叠加装饰层（灵林树木模型、雾泽半透明色块）；险地为顶面印记。
- **相机为正交投影、锁定 45° 等距（见 §8.4），3D 资产呈现 2.5D 观感，禁止旋转**；**任何操作/收到 view 后相机 transform 不得被重置**。

#### 4.1.11 首版范围（地形）

- 做：3 基底 + 3 海拔 + 2 地貌 + 河流边 + 险地 + 地形关联的节点/资源 + 高地/跨河/丘陵/灵林防御 + 3D 起伏柱体 + 建城/改良/邻接限制。
- 不做（后续）：自然奇观、雨林/绿洲/地热/冻土/雪原/沙漠/泛滥平原、可登山单位、天气季节、自定义地图脚本。

### 4.2 视野与三层画卷迷雾

- 权威：每宗 `visibleTiles`（当前可见）、`exploredTiles`（曾探索），客户端不得自行推导；视野范围由服务端按 `vision` 计算。
- 视野半径：灵峰 3、节点 2；弟子按境界 **炼气 2 / 筑基 2 / 金丹 3 / 元婴 3 / 化神 4**；站丘陵额外 +1。
- 回合开始、移动、驻守、夺峰/夺点后重算；灵峰/节点易主当场为双方重算。
- **三态视觉（画卷机制，见 ART_STYLE_REFERENCE §二）**：
  1. **未探索（宣纸空白）**：整块为米白色宣纸纹理，无任何地形/资源信息；单位探索到边缘时，宣纸以**泼墨"褪去"动画**露出下方实景。
  2. **已探索无视野（水墨古地图）**：以排线/速写线条绘制的手绘古地图，只显示**固定地形**（基底/海拔/地貌/河流/节点）与**最后可见时**的城市、改良快照；**不显示任何单位**；**不记录、不更新失去视野后敌方新建/拆除的建筑、改良与领地变化**（冻结为最后可见）。
  3. **当前视野（等距 2.5D 实景）**：完整手绘模型（地块、植被、资源、单位、城市、全部改良）与动态光影。
- **view 下发规则**：地形/地貌/河流/节点一旦 explored 永久保留；己方实体实时下发；敌方单位仅在可见格下发；敌方城市/建筑/改良/领地在可见格实时、在 mid-fog 格冻结为最后可见快照（服务端按宗门缓存"最后可见"状态）。
- 客户端 `world/Fog` 按图块渲染三种材质；R1 做三态静态材质，R8 做泼墨转场与粒子。

### 4.3 势力与三流派

- 初始资源（`resources.initial`）：灵力 400、灵石 300、工力 120、声望 0；材料 天晶2/玄铁2/灵木4；主峰气运初始 0（上限 100）。
- 开局每宗：1 主峰（等级1、人口3、容量10、防御10、气运0/100）+ 宗主（金丹、任峰主）+ 2 外门弟子（炼气，灵根品级1、随机1灵根）；家族流始祖即血脉（世代1、嫡支）。
- 出生点：玩家在地图中心 `(w/2,h/2)`；3 AI 在 `(1,1)`、`(w-2,1)`、`(1,h-2)` 附近取最近无主格；小地图重叠时就近取格。
- 流派特性数值（`faction`）见 1.1；开峰造价 `foundCost`：宗门 500 / 家族 800 / 国家 350（国家另有 −30%），工期 5。

### 4.4 弟子系统

- **境界 Realm**（等级/移动加成）：炼气 LIAN_QI(1,+0) / 筑基 ZHU_JI(2,+0) / 金丹 JIN_DAN(3,+1) / 元婴 YUAN_YING(4,+2) / 化神 HUA_SHEN(5,+3)。
- **岗位 Position**：杂役 ZA_YI / 外门 WAI_MEN（炼气）/ 内门 NEI_MEN / 亲传 QIN_CHUAN（筑基）/ 峰主 FENG_ZHU / 长老 ZHANG_LAO / 宗主 ZONG_ZHU（金丹）。
- **灵根 SpiritRootType**：金 JIN / 木 MU / 水 SHUI / 火 HUO / 土 TU / 风 FENG / 雷 LEI（均移动 +1）/ 杂灵根 ZA（移动 −1）；品级 1–5，每品级修炼 +10%（`rootGradeBonusPerGrade=0.1`）。
- **移动力**：基础 2 + 境界移动（金丹+1/元婴+2/化神+3）+ 风/雷/金/木/水/火/土 +1、杂灵根 −1 + 道法移动（遁术、御兽骑乘）+ 道路。
- **修炼**：速度 10 进度/回合 ×（1 + 灵根品级×0.1 + 洞府0.5 + 宗门/建筑/道法/政策加成），心魔 ≥50 时 −20%；进度上限 100/200/400/800/1600；突破率 0.8/0.6/0.4/0.2；突破失败心魔 +10、进度退到 ×0.5。
- **渡劫（元婴→化神）**：耗灵力 500 + 天晶3 + 玄铁2 + 灵石300；基础成功率 30%，每解锁道法 +5%、每灵根品级 +5%；失败心魔 +50 且 30% 陨落；成功即飞升候选。
- **心魔（0–100）**：≥50 战力 ×0.9、≥80 战力 ×0.75 且按 30% 概率受伤；≥100 按 50% 叛逃（投中立/AI）；超容量每回合 +5；探索失败 +10；近战反击胜方反噬心魔 `max(1, 反击战力/10)`；洞府/讲道各 −5。
- **重伤**：战力 ×0.5；回合开始 50% 概率伤愈（`injuryRecoveryChance`）。
- **收徒**（`holdRecruitment`）：耗灵力 200、工期 3 回合；基础收 2 人、每峰等级 +1（`recruitmentBaseCount=2/perLevel=1`）；两次收徒基础间隔 10 回合（`recruitmentBaseInterval`）。
- **出手**：每回合 1 次攻击（`attacksPerTurn=1`），攻击额外耗 1 移动力。

### 4.5 回合流程

六阶段（`TurnPhase`），单线程顺序推进：

1. **TURN_START**：刷新迷雾 → 道路网 → 传送次数清零 → 宗主外出检查（大殿全局加成失效判定）→ 每名弟子（重置移动力/出手、入宗年限 +1、伤愈、修炼）→ 自动化行动。
2. **SPIRIT_PEAK**：围城断供削减 → 项目队列推进 → 研究队列推进（工力不足则暂停）。
3. **PLAYER_ACTION**：玩家操作。
4. **SETTLEMENT**（2.0 裁剪后）：节点冷却 −1 → 城市人口结算（补劳力/粮食/增长）→ 经济结算（按当时劳力汇总产出与维护）→ 道统成就（boost）结算 → 心魔结算 → 政令结算（产出/声望/安定，不含厌战/忠诚）。
5. **AI_ACTION**：3 家 AI（未覆灭者）各跑一次基础行动点决策，随后刷新其迷雾。
6. **VICTORY_CHECK**：胜负判定；未结束回 TURN_START；终局冻结；每 10 回合自动存档槽 0；240 回合强制分数结算。

> 删除 1.0 SETTLEMENT 中的：外交/厌战、世界威胁（巢穴）、随机事件、灾劫、忠诚叛乱（见第 5 章）。

### 4.6 资源体系

- **主资源**：灵力 spiritPower（修炼/建造/扩张）、灵石 spiritStones（高级建造/传送/加速）、工力 workPower（推进项目与改良）、声望 prestige（综合影响、修炼加成）、气运 qiYun（开峰/扩张容量，每峰上限 100）、灵粮 food（人口与弟子维护）、道点 daoPoints（研究道法）。
- **势力等级 powerLevel**（胜利指标）：由 领地数（每 5 格 1 级）+ 高境界弟子×2 + 已解锁道法×1 + 建筑等级×1 加权（`powerLevel` 配置），**不是声望折算**。
- **战略材料**：天晶 tian_jing、玄铁 xuan_tie、灵木 ling_mu。
- **奢侈品**（`luxuryTypes`）：灵茶 ling_cha（安定+3、修炼+5%）、云锦 yun_jin（安定+3、气运+1）、灵玉 ling_yu（安定+4、气运+2、修炼+5%）。
- **维护**：每名弟子每回合粮 1；建筑每级 1 维护、单位每级 2 维护；主峰维护 6、副峰 2。
- **关键产出**：主峰基础灵力 12；每名弟子灵力产出 4；每峰基础工力 25（+10/工作格、+3/副峰）；胜战声望 +3、飞升 +50、高境界弟子 +1。
- 地块产出 = 地形/海拔/地貌/资源 + 改良 + 节点 + 区域 + 建筑 + 道法 + 政令；安定影响产出（见 4.7）。

### 4.7 灵峰与城市

- 灵峰：容量 10、每级 +5；最高 5 级；开峰 5 回合、造价见 4.3；每多一峰铺张惩罚 5%（产出/效率，`spreadPenaltyPerPeak`）；基础防御 10；**加固** `fortifyPeak` 耗 80 灵力、2 回合、防御 +10；拆建返还 50%。
- **建筑（10 种，`building.costs/turns/materials`，core 建筑归首府区）**：

| 建筑 | 造价(灵) | 回合 | 材料 | 归属/说明 |
|---|---|---|---|---|
| SHAN_MEN 山门 | 200 | 3 | — | 核心，首府区 |
| ZONG_ZHU_DA_DIAN 宗主大殿 | 300 | 5 | 天晶3 | 核心；宗主坐镇：气运+10、灵力+20% |
| CANG_JING_GE 藏经阁 | 250 | 4 | 灵木4 | 核心/藏经区；道点 +2/回合 |
| XIU_LIAN_FEN_FENG 修炼分峰 | 150 | 3 | — | 归修炼区 |
| DAN_TANG_FEN_FENG 丹堂分峰 | 150 | 3 | — | 归丹器区 |
| QI_TANG_FEN_FENG 器堂分峰 | 150 | 3 | — | 归丹器区 |
| JIANG_DAO_FEN_FENG 讲道台分峰 | 150 | 3 | — | 归修炼区 |
| HU_SHAN_JIAN_ZHEN 护山剑阵 | 280 | 4 | 玄铁4 | 宗门专属，防御 +25 |
| ZU_CI 祖祠 | 260 | 4 | 灵木4 | 家族专属，修炼 +25%、繁衍 −30%、安定 +1/回合 |
| WANG_CHAO_DI_DU 王朝帝都 | 320 | 5 | 天晶4/玄铁3 | 国家专属，住房 +10、增长 +50% |

- **洞府**：`openCave` 耗 100 灵力、2 回合；住房 +1、修炼 +50%（`caveBonus=0.5`）。
- **区域（5 可建 + 1 自带首府区，独立占地，每峰最多 4）**：

| 区域 | 造价(灵) | 回合 | 产出 | 额外 |
|---|---|---|---|---|
| XIU_LIAN_QU 修炼区 | 220 | 4 | 灵8/气运1 | 防御+4；归修炼/讲道分峰 |
| DAN_QI_QU 丹器区 | 200 | 4 | 灵3/石5 | 归丹堂/器堂分峰 |
| CANG_JING_QU 藏经区 | 260 | 5 | 灵2/道3 | 可归藏经阁 |
| FA_TAN_QU 法坛区 | 180 | 3 | 灵2/气运4 | 安定+4、防御+8 |
| SHI_JI_QU 坊市区 | 240 | 4 | 粮4/石6 | 安定+6 |
| SHOU_FU_QU 首府区 | 自带 | — | — | 灵峰自带，收纳核心建筑 |

- **区域邻接（1.0 八条，2.0 加地形项，见 4.1.9）**：修炼区邻灵泉灵力+4、邻灵脉+25%；丹器区邻灵田石+3、邻灵脉石+4；藏经区邻区域道点+2；法坛区邻险地气运+3；坊市区邻灵田粮+4、邻区域石+20%。
- **工作半径**：峰周围 2 格；`queryAssignableTiles` 返回可指派格，`assignWorker/unassignWorker` 指派/撤下劳力。
- **人口**：起始 3；粮每累计 8 增长 1；粮耗 1/人；住房 = 6 + 峰级×2 + 洞府×1 + 区域×2 + 建筑×1（帝都 +10）。
- **安定**：基础 70、上限 100；低于 45 停止人口增长（`growthStabilityMin`）；过度拥挤 −12、缺粮 −15；超员住房产出 −5%；气运 +10、每种奢侈品 +5；安定按 `stabilityOutputFactor=0.006` 影响产出；赤字时安定 −3。2.0 **无叛乱/独立**（仅产出/人口惩罚）。

### 4.8 地块改良与建造者

- 建造者：每人 3 次建造次数（`builderCharges`）；最高境界筑基；`appointBuilder` 任命；自动化建造耗 1 次。
- 修缮 `repairImprovement`：40 工力；被掠夺后产出减半需修缮；被掠夺概率 移动 0.35 / 攻击 1.0。
- **改良（8 种，`improvement.byType`）**：

| 改良 | 花费(工) | 产出 | 限制/前置 |
|---|---|---|---|
| LING_TIAN_TI_TIAN 灵田梯田 | 60 | 粮4/灵2 | 平地沃野；需道法 ling_tian_nong |
| LING_KUANG 灵矿 | 90 | 灵1/石5 | 丘陵（2.0 改） |
| CAI_SHI_CHANG 采石场 | 70 | 石4 | 丘陵（2.0 改） |
| YAO_YUAN 灵植药园 | 80 | 粮2/石3 | 平地/雾泽；需丹器区 |
| JU_LING_ZHEN 聚灵阵 | 120 | 灵3/气运1；修炼+15%、视野+1 | 需道法 ju_ling_zhen |
| QING_SHI_DAO_LU 青石道路 | 30 | — | 平地/丘陵；同宗路网移动 −1 |
| DONG_FU 洞府 | 100 | 住房+1 | 平地/丘陵 |
| LING_QUAN_XIU_SHAN 灵泉修缮 | 150 | 灵泉每回合恢复 5% | 灵泉节点；不可自由建造 |

- 道路：同宗青石道路相连成网，减移动消耗（最低 1）；城市可每峰自动修 1 条，耗 15 灵石（`road.cityAutoBuild`）。

### 4.9 道统科技树（`daoTree`，21 条道法）

- **5 个时代**：炼气篇 / 筑基篇 / 金丹篇 / 元婴篇 / 化神篇。
- **共 21 条道法**（含 4 条流派专属），按时代分布：

| 时代 | 条数 | 道法 id（通用 + 专属） |
|---|---|---|
| 炼气篇 | 3 | tu_na、ling_tian_nong、dan_yao_chu |
| 筑基篇 | 4 | jian_xiu、fa_xiu、dun_shu、ju_ling_zhen |
| 金丹篇 | 7 | cang_shu、ti_xiu、chuan_song、qi_ji、+hu_shan_jian_zhen(宗门)、+xue_mai_jue_xing(家族)、+zu_xian_bi_you(家族) |
| 元婴篇 | 4 | fu_zhen、shi_jie、tian_ji、+di_wang_zhu_shu(国家) |
| 化神篇 | 3 | ji_guan、hun_yuan、fei_sheng |

- 每条道法含 `daoPointCost`（道点）、`spiritPowerCost`（灵力）、`turns`（研究队列回合）、`prerequisiteDaoIds`（前置链）、`effects`、可选 `factionOnly`/`requiresBloodLine`。
- 效果类型：修炼/经济/战力/移动/视野/研究加成，解锁兵种、建筑、改良、区域、传送、政策。
- **道点来源**：藏经阁 +2/回合；灵脉/机缘/秘境节点与藏经区产出；**道统成就 boost**（一次性道点奖励，替代旧"顿悟"表述）：
  - 首次秘境 +30；拥有 3 灵脉 +40；累计招募 5 人 +30；首次胜敌 +30（`daoTree.boosts`）。
- 核心道法：**hun_yuan 混元大道**（化神，战力+25/修炼+15%，前置 ti_xiu+tian_ji）、**fei_sheng 飞升妙法**（化神，前置 hun_yuan，解锁"仙途诏令"、修炼+10%，宗门流胜利必需）。
- 研究队列支持取消/加速（`researchDao/cancelProject/accelerateProject/queryProjectQueue`，加速 120 灵石/回合）。

### 4.10 兵种与战斗（`warfare`，十兵种）

**十兵种（`unitClasses`，攻/防系数、射程、转职成本）**：

| 兵种 | 类型 | 攻 | 防 | 射程 | 移动 | 反击 | 境界/灵根门槛 | 转职(灵/石/冷却/材料) |
|---|---|---|---|---|---|---|---|---|
| PU_TONG 寻常弟子 | 近战 | 1.0 | 1.0 | 1 | 0 | 0.30 | 1/1 | 默认 |
| JIAN_XIU 剑修 | 近战 | 1.25 | 1.0 | 1 | 0 | 0.35 | 筑基/1 | 200/100/3/铁2 |
| FA_XIU 法修 | 远程 | 1.1 | 0.8 | 3 | 视野+1 | 0.15 | 筑基/1 | 250/120/3/晶2 |
| TI_XIU 体修 | 反骑 | 0.9 | 1.5 | 1 | 0 | 0.40 | 金丹/1 | 300/150/4/木3 |
| QI_JI 御兽骑乘 | 骑兵 | 1.15 | 0.9 | 1 | +2/视野+1 | 0.25 | 金丹/2 | 300/180/4/木4 |
| FU_XIU 符修 | 辅助 | 0.8 | 0.9 | 2 | 视野+1 | 0.10 | 金丹/2，攻城1.0 | 350/200/4/晶2木2 |
| JI_GUAN 机关傀儡 | 攻城 | 1.3 | 1.2 | 2 | −1 | 0.20 | 元婴/2，攻城2.0 | 500/300/5/铁5晶3 |
| JIAN_ZHEN_SHI 剑阵使 | 反骑 | 1.2 | 1.35 | 1 | 0 | 0.50 | 金丹/2，宗门 | 320/180/4/铁3 |
| XUE_MAI_XIU_SHI 血脉修士 | 近战 | 1.25 | 1.1 | 1 | +1/视野+1 | 0.35 | 金丹/3，家族 | 350/200/4/木3 |
| JI_GUAN_JUN_TUAN 机关军团 | 攻城 | 1.35 | 1.3 | 2 | −1 | 0.25 | 元婴/2，国家，攻城2.2 | 550/350/5/铁6晶4 |

**相克（`counters`）**：剑修→法修 1.35（被体修 0.9）；骑乘→法修 1.4/符修 1.3/傀儡 1.3；体修→骑乘 1.5/傀儡 1.2；法修→体修 0.85；符修→傀儡 1.15；剑阵使→骑乘 1.3/血脉 1.15；血脉→剑修 1.15/寻常 1.2；机关军团→符修 1.25/剑阵使 1.15。

**战力（基础）**：
```
power = 境界等级×10 + 灵根品级×5 + 道统 COMBAT_BONUS
power = power × (1 + 政令战力%)
重伤 ×0.5；心魔 ≥50 ×0.9、≥80 ×0.75
```

**对阵**：
- 攻方：`power × 兵种攻击系数 × 相克系数（对守方最强者）× (1 + 高地0.15 − 跨河0.25)`；攻灵峰时非攻城单位再 ×0.5（需傀儡/符修/军团破城）。
- 守方：`power × 兵种防御系数 × (1 + 海拔/地貌/险地防御 + 驻防0.15)`；丘陵+20%、灵林+20%、雾泽−10%、险地+25%；攻峰再加 `(峰防+区防) × (1−围城削减)`。
- 围城：相邻补给通道被敌方占据（满 1 倍要求）起，城防每回合 −12%（`defenseCutPerTurn=0.12`），上限 −60%。
- 远程：距离 >1 为远程打击，守方**零反击**。
- 胜率：战力比 max/min ≥ 1.5 时强方速胜/速败；否则 `winChance = clamp(0.5 + 0.5×(攻−防)/(攻+防), 0.02, 0.98)`。
- 实战：未碾压时打 1–3 回合，每回合 ±20% 噪声，按多数回合胜负。
- 败方结局：陨落 0.2 / 重伤 0.4 / 俘虏 0.2 / 余为击退；陨落移除并清空岗位，俘虏转投胜方。
- 反击：贴身守方最强者以 `power × 反击系数` 反噬，胜方心魔 += max(1, 反击/10)。
- 经验：胜 +20 / 败 +8 / 击杀 +15 / 夺目标 +10；等级阈值 `[0,30,80,160,280]`；升级可择一晋升。
- 撤退：撤往相邻格，成功率 50%（骑兵 +20%）、耗 1 移动，失败移动力归零。
- 目标：夺峰 PEAK（占领灵峰/易主/城防）、夺点 NODE（占领节点）、野战 DUEL（击杀/击退）；胜战掠夺目标格改良；胜战声望 +3。

**晋升（9 条，`promotions`，达到等级解锁）**：剑意通明（剑修 Lv1，攻+15%）、御剑千里（剑修 Lv2，射程+1/机动+1）、铁身不坏（体修 Lv1，防+25%）、疾风兽步（骑乘 Lv1，机动+1/撤退+15%）、破阵真符（符修 Lv1，攻城+0.5）、重械核心（傀儡 Lv2，攻城+0.5/攻+20%）、杀伐果断（任意 Lv1，攻+8%）、定心如磐（任意 Lv1，防+8%）、神游太虚（任意 Lv2，视野+1）。

### 4.11 探索（机缘 / 秘境，`explore`）

- **机缘**（单人，`sendToJiYuan`）：基础成功率 50%（+每灵根品级 5%）；冷却 5 回合；成功得 道点 20 + 材料（天晶2/玄铁1/灵木2，每品级追加 晶1/木1）；失败 30% 受伤、10% 陨落。
- **秘境**（最多 4 人，`exploreMiJing`）：耗 200 灵石；冷却 8 回合；富裕概率 30%（+每品级 4%/每境界 4%）；富裕奖励 天晶6/玄铁4/灵木5 + 300 石 + 40 道点；失败 40% 受伤、15% 陨落、25% 遭遇险情（`miJingDisasterChance`，作为秘境内部风险，非独立灾劫）。

### 4.12 任命 / 血脉 / 传送 / 集结

- 任命：长老上限 2 + 每势力等级 +1；峰主 +气运5、灵力产出 +30%；长老修炼 +10%、研究 +10%；宗主坐镇大殿才有全局加成（气运+10、灵力+20%），外出失效；宗门流宗主陨落且无金丹以上继承人即败。
- 血脉（家族）：婚娶 50 石；繁衍 120 石 + 60 工、冷却 5 回合；品级抖动 25%、上变 5%、多灵根 +15%、高品阈值 4；族人死亡安定 −5。
- 传送：需道法 `chuan_song`；基础 30 石 + 每格 5 石；容量 1 + 自有灵脉节点数（上限 4）；每回合次数回合开始清零。
- 集结/回防：`rally`（最多 8 人）/`returnToDefense`；驻守 `assignGarrison`（+15% 防御，自动探索最多 3 人）；批量移动 `batchMove`（单次最多 8 目标）。

### 4.13 政令（保留并裁剪，`policy`）

- 切换政体冷却 8 回合（`switchCooldownTurns`）。
- **3 政体**：
  - **宗门共治 zong_fa**（默认）：槽位 经济1/军事1/治理1（原外交槽 2.0 改治理）。
  - **君主集权 jun_quan**（元婴篇解锁）：经济1/军事2/治理1；战力 +10%。
  - **世家门阀 men_fa**（金丹篇解锁）：经济2/治理2；声望 +0.5/回合。
- **政策卡：1.0 共 10 张，2.0 删 2 张外交卡（远交近攻、怀柔四方），保留 8 张**；凡原 `loyaltyPerTurn` 效果统一改落为安定（`stability`），删除一切 `weariness` 效果：
  - 经济：灵田制（产出+15%）、商道通衢（筑基，灵力+10%/声望+0.3）
  - 军事：铁律军规（战力+10%）、以战养战（金丹，战力+5%/声望+0.2）
  - 治理：静心道场（修炼+10%）、严明赏罚（改：安定+0.5/回合）、广纳门徒（筑基，产出+5%/声望+0.2）、仙途诏令（需道法 fei_sheng，修炼+15%/安定+0.5）
- 效果按回合以小数累积落地，避免整数丢失。

### 4.14 自动化（`automation`）

- 开关（默认）：自动改良 开、自动修缮 开、自动道路 关、自动项目 关、自动探索 关。
- 单峰/全峰自动项目；"立即探索"；每回合自动动作上限 6、集结最多 8、自动探索最多 3、建造耗 1 次建造次数。
- 命令：`setAutomationToggle / setPeakAutoProject / setAllAutoProject / exploreNow / queryAutomationState`。

### 4.15 胜利与失败（`victory`，上限 240 回合）

- **宗门流**：道法完成率 1.0（含 fei_sheng、hun_yuan）+ 势力等级 ≥140 + 灵峰 ≥10。
- **家族流**：4 人飞升 + 族人 ≥12 + 元婴（level≥4）及以上族人 ≥3。
- **国家流**：占地块 ≥20% + 控制 ≥24 格 + 灵峰 ≥2。
- **分数胜利**：势力等级×1 + 飞升×12 + 地块份额×40 + 道法完成×30 + 灵峰×3。
- 失败：弟子全灭、灵峰全失、宗门流宗主陨落且无金丹以上继承人。
- 同时达成多条路线时服务端发 `awaitInput(kind=victoryChoice)`，玩家择一（AI 取招牌路线）。

### 4.16 基础 AI（首版）

- 保留基于行动点的反应式启发式：扩张（开峰/修路/抢点）、战斗（胜率达标才打，`attackMinWinChance=0.55`、优势阈值 1.2）、研究、驻守、经济；三流派按倾向加权。
- 难度（`difficulty`，行动点/AI 起手补贴/倍率）：
  - **初入仙途 easy**：AI 行动点 4、攻×0.7、扩×0.7；玩家 +500 石。
  - **正道争锋 normal**：AI 行动点 5、×1.0。
  - **群雄噬血 hard**：AI 行动点 6、起手 +600 石 +300 工、攻×1.3、扩×1.2。
- **删除**：性格系统（好战/图治/纵横）、长期战略复盘、外交议程；攻击不再检查"是否已宣战"，直接按战力与目标价值决策。

---

# 第三部分　范围裁剪、接口契约、里程碑与工程规范

## 5. 2.0 范围裁剪与耦合点裁决

### 5.1 暂不纳入模块（命令级，共裁剪 19 条命令）

| 模块 | 裁剪命令 | 对应 1.0 服务 |
|---|---|---|
| 外交/厌战（10） | `queryCasusBelli` `declareWar` `makePeace` `trade` `signNonAggressionPact` `formAlliance` `offerVassalage` `breakTreaty` `releaseCaptives` `queryDiplomacyOverview` | DiplomacyAction、Relation、warWeariness、条约/交易/附庸 |
| 蛮族巢穴（3） | `clearLair` `queryClearBlocker` `queryLairInfo` | ThreatAction / WorldThreatService |
| 灾劫（1） | `resolveDisaster` | DisasterService（灵泉枯竭/灵脉震动/天罚雷劫/瘴气） |
| 威胁总览（1） | `queryThreatOverview` | 巢穴/灾异/民心/外交聚合 |
| 忠诚/叛乱（2） | `giftLoyalty` `queryLoyaltyGiftBlocker` | LoyaltyService 赏赐与叛乱 |
| 随机事件（2） | `queryPendingEvent` `resolvePendingEvent`（含 `awaitInput kind=randomEvent`） | EventService 事件库与路途事件 |

> 裁剪后 2.0 保留 **69 条命令 + ping**（1.0 为 88 条）。机缘/秘境（`explore`）是玩家主动探索，保留。

### 5.2 耦合点裁决

1. **开战前置（最重要）**：1.0 攻击他宗要求"战争状态"（先宣战）。2.0 **【默认·待确认】**：逐鹿设定下**默认可直接攻击**任何非己方单位/节点/灵峰（攻击即交战）；通行只区分 己方/敌方/无主。
2. **厌战**：删除 `warWeariness` 与所有 `addWeariness`。
3. **安定**：保留 `stability`（影响人口/产出，见 4.7）；删除"安定过低→叛乱/独立"与"赏赐民心"。
4. **政令**：删 2 张外交卡；政体/卡片的 `loyalty` 效果改落 `stability`，删 `weariness`；宗门共治的外交槽改治理槽。
5. **蛮族/灾劫/事件**：世界对手仅 3 家 AI + 玩家主动探索节点；秘境内部 `miJingDisasterChance` 作为探索风险保留，独立灾劫系统移除。
6. **AI**：移除性格/长期战略/外交议程；攻击不检查宣战。
7. **awaitInput**：仅保留 `victoryChoice`；`resolveChoice` 只分派 `req_victory_*`。
8. **配置**：`gameConfig.json` 删/禁用对应块（见 `data/README.md`）；新增 `map` 地形起伏配置；ConfigValidator 对引用已删字段即报错。

---

## 6. 接口契约（WebSocket + JSON）

### 6.1 连接、握手与帧

- WebSocket 文本帧，UTF-8 JSON，一条消息一个 JSON 对象。
- 服务端监听 `127.0.0.1:9527`（`--port` 可覆盖）；客户端连上后第一帧：
  ```json
  {"type":"hello","protocolVersion":"2.0","backend":"xiuxian-godot-headless",
   "saveVersion":"3.0","implementedCommands":["newGame","..."]}
  ```
- 客户端据 `implementedCommands` 置灰不支持按钮；单会话顺序处理，事件顺序 == 结算顺序。
- **帧缓冲**：`WebSocketPeer` 默认单帧收发缓冲仅 **64 KiB**，而 `view` 快照随地图规模线性增长（默认 20×15=300 格约 70 KB，128×128≈4 MB）。两端必须在**建连前**（服务端 `accept_stream` / 客户端 `connect_to_url` 之前）统一设 `inbound/outbound_buffer_size` 为共享常量 `Msg.FRAME_BUFFER_BYTES`（当前 16 MiB），否则大帧静默发送失败（`_send ERR_OUT_OF_MEMORY`）。

### 6.2 请求与响应

请求：
```json
{"id":"c12","type":"moveDisciple","params":{"discipleId":"disciple_3","targetTileId":"q4_r5"}}
```
成功：
```json
{"id":"c12","ok":true,"events":["[结算] …"],"view":{ /* 全量快照，只读命令不带 */ },
 "result":{ /* 命令特定返回，可省略 */ }}
```
失败：
```json
{"id":"c12","ok":false,"errorCode":"BAD_PARAMS","message":"人读诊断（仅调试用）"}
```
- **业务失败不是协议失败**：玩法不允许（工力不足/不在射程/无法通行/山岳不可建城）一律 `ok:true + result.success:false + message`；参数缺字段/类型错才 `BAD_PARAMS`。
- 只读 `query*` 不回 `view`。

### 6.3 主动消息

- `hello`：握手。
- `awaitInput`（2.0 仅胜利择一）：
  ```json
  {"type":"awaitInput","reqId":"req_victory_12","kind":"victoryChoice",
   "prompt":"择定结局","options":[{"index":0,"label":"…","routeId":"…","description":"…"}]}
  ```
  客户端回 `{"id":"c13","type":"resolveChoice","params":{"reqId":"req_victory_12","optionIndex":0}}`；新出现时推送一次，读档回到待决点重新推送；越界回 `BAD_PARAMS` 且待决保留。

### 6.4 错误码

| 码 | 含义 | 客户端应对 |
|---|---|---|
| BAD_JSON | JSON 非法 | 打日志 |
| NO_ID / BAD_REQUEST | 缺 id / 缺 type | 打日志 |
| UNKNOWN_COMMAND | 命令名未登记 | 打日志 |
| NOT_IMPLEMENTED | 已登记但本版未实现 | 按钮置灰 |
| BAD_PARAMS | 参数缺失/类型错/值非法 | 弹提示 |
| NO_GAME | 未开局/未读档 | 先开局 |
| INTERNAL | 服务端异常 | 上报并附日志 |

### 6.5 view 全量快照（字段）

```
turn, phase, mapWidth, mapHeight, playerSectId, randomSeed, difficultyId,
gameOver, winType, winnerSectId, pendingVictoryChoices,
tiles{ tileId: {
  id, q, r, baseTerrain, relief, features[], riverEdges[], danger,
  ownerSectId, nodeId, districtId, workedByPeakId, improvementId, luxuryType
}},
nodes{ nodeId: GameNode }, improvements{ id: Improvement },
sects[ { …, disciples[ … ], spiritPeaks[ … ] } ],
eventLog[ ]
```
- 2.0 新增地形字段（`baseTerrain/relief/features/riverEdges`）；删除 1.0 快照的 `relations`、`lairs`、`disasters`。
- Map→JSON 对象，List→数组；不下发内部记账字段（`tileSnapshots/policyCarry` 等）。

### 6.6 字段命名

- 小驼峰字段；枚举序列化为大写下划线字符串（`LIAN_QI`、`ZONG_MEN`、`HILL`）；布尔 getter 的 `is` 前缀剥离（`player/danger/capital/bloodLine`）；`randomSeed` 用 64 位 int。

### 6.7 2.0 命令清单（69 条 + ping）

**会话（13）**：`newGame`、`getState`、`finishTurn`、`beginPlayerTurn`、`nextTurn`、`listSaves`、`saveGame`、`loadGame`、`queryVictoryProgress`、`checkVictory`、`checkDefeat`、`chooseVictory`、`queryGameOver`
- `newGame params`：`{playerFaction, sectName, mapWidth, mapHeight, randomSeed, difficultyId}`
  - **字段名以本行为准**。为兼容早期提示词，服务端额外接受别名：`factionType`→`playerFaction`、`difficulty`→`difficultyId`；同一语义同时出现且取值不一致时回 `BAD_PARAMS`。
  - `mapWidth`/`mapHeight` 缺省取 `map.defaultWidth`/`map.defaultHeight`（20×15）；`randomSeed` 可为空（空则由服务端集中随机源生成，须为 64 位整数语义）；`difficultyId` 缺省 `normal`（`easy`/`normal`/`hard`）。
  - `getState` 在未开局时回 `NO_GAME`。

**单位（22）**：`moveDisciple`、`queryMoveRange`、`batchMove`、`attack`、`queryAttackPreview`、`queryAttackable`、`retreat`、`teleport`、`queryTeleportOptions`、`assignGarrison`、`withdrawGarrison`、`reclass`、`promote`、`tribulate`、`rally`、`returnToDefense`、`foundSpiritPeak`、`appointBuilder`、`appointFengZhu`、`appointZhangLao`、`appointZongZhu`、`queryDiscipleDetail`

**城市/区域/改良（18）**：`constructBuilding`、`queryBuildOptions`、`holdRecruitment`、`researchDao`、`openCave`、`fortifyPeak`、`cancelProject`、`accelerateProject`、`queryProjectQueue`、`foundDistrict`、`queryDistrictSites`、`assignWorker`、`unassignWorker`、`queryAssignableTiles`、`queryCityDetail`、`buildImprovement`、`repairImprovement`、`queryImprovementOptions`

**探索（4）**：`queryJiYuanInfo`、`sendToJiYuan`、`queryMiJingInfo`、`exploreMiJing`

**政令（4）**：`switchGovernment`、`enactPolicy`、`revokePolicy`、`queryPolicyOptions`

**自动化/设置（6）**：`setAutomationToggle`、`setPeakAutoProject`、`setAllAutoProject`、`exploreNow`、`queryAutomationState`、`setSetting`（客户端本地，不回 view）

**待抉择（2）**：`queryVictoryChoice`、`resolveChoice`

> 各命令 `params/result` 沿用 1.0 `PROTOCOL.md §11`（迁移到 `docs/PROTOCOL_2.0.md` 时逐条落地），删除裁剪模块相关字段；地形 blocker（山岳不可建城/不可通行、雾泽、缺水）由 `querySpiritPeakBlocker/queryBuildOptions/queryMoveRange` 等返回。

---

## 7. 里程碑与任务拆分（纵向切片，每阶段端到端可玩、可验收）

> 每阶段都是"服务端规则 + 协议命令 + 客户端界面"的可运行切片；跑无头自检并**提交推送**。

| 里程碑 | 服务端规则 | 协议命令 | 客户端 | 验收（关键） |
|---|---|---|---|---|
| **R0 工程骨架** | 两个 Godot 工程、shared 联接、WebSocket 互通、config 加载/校验、hello | `ping` | 连接/握手/启动器拉起子进程 | 客户端连上 headless 并显示 hello；`setup_shared` 可重复执行；无残留进程 |
| **R1 地图与开局** | **分层地形生成（基底/海拔/河流/地貌/险地/资源/节点，种子确定）**、实体初始化、三流派、出生点、view 快照、迷雾（可见/已探索） | `newGame` `getState` | 主菜单/开局、**起伏六边形+连绵山体+河流渲染**、相机锁定 45° 正交、**三层迷雾静态材质（宣纸/水墨古图/实景）** | 固定种子地图逐字一致；海拔/河流比例正确；300 格/4 宗/初始资源弟子正确；三态与 4.2 下发规则一致；不可旋转、缩放平移不重置 |
| **R2 回合/移动/视野** | 6 阶段状态机、地形移动力叠加/BFS、视野（含丘陵+1） | `finishTurn` `nextTurn` `beginPlayerTurn` `moveDisciple` `queryMoveRange` | 点选/移动/高亮/范围预览/TopBar | 高亮即可达；山岳不可达；丘陵/灵林/雾泽/跨河扣力与预览一致；迷雾随移动更新 |
| **R3 经济与城市** | 经济结算、地形产出、人口/住房/安定、灵峰、建筑、区域（含地形邻接）、劳力、改良、道路 | 城市 18 条 | 城市面板/建造/区域选址/劳力指派/改良、资源栏 | 产出与 config 一致；山岳不可建城、丘陵/灵林限制生效；区域邻接与上限生效；安定惩罚生效 |
| **R4 道统与修炼** | 修炼/突破/渡劫、21 道法树/道点/成就 boost、项目队列、收徒 | `researchDao` `holdRecruitment` `queryProjectQueue` `cancelProject` `accelerateProject` | 道统树、研究队列、弟子详情 | 21 道法前置/时代/流派专属门控正确；进度/突破/渡劫正确；成就 boost 触发正确 |
| **R5 兵种与战斗** | 十兵种、转职/晋升、战力/胜率/相克/**丘陵高地/跨河/地貌防御**/城防、野战/夺峰/夺点、撤退、传送、驻守 | 单位 22 条（战斗相关） | 攻击预览/攻击范围/战斗动画/伤亡反馈/转职晋升面板 | 预览胜率==实战口径；高地/跨河/丘陵/灵林加成正确；夺峰/夺点易主与视野重算；远程零反击；ZOC/围城生效 |
| **R6 探索/政令/自动化** | 机缘/秘境、政令（8 卡/3 政体）、自动化、集结/回防 | 探索 4 + 政令 4 + 自动化 6 | 探索/政令/自动化面板 | 成功率/冷却/伤亡与 config 一致；政策槽位/冷却 8 正确；loyalty 效果落安定；自动化按阈值触发 |
| **R7 任命/渡劫/AI/胜负/存档** | 任命、血脉、渡劫飞升、基础 AI、胜负、分数、存档 | 会话剩余命令、`tribulate`/任命、`saveGame/loadGame/listSaves`、胜利待择 | 胜利进度/结局/存档/AI 回放 | 三流派胜利可达成；240 回合分数正确；同种子双跑逐字一致；读档继续与待决重建 |
| **R8 表现与 UI 打磨** | —（仅协议补字段） | — | 正式 HUD、全面板、框选、动画、音效、小地图、设置、引导、**泼墨迷雾转场、昼夜/草木飞鸟/灵气粒子、轮廓描边、网格开关与宗门色边框** | 全部 69 命令有 UI 入口；信息直观；**视角/缩放操作后不重置**；全局缩到最远设施仍可辨 |
| **R9 皮肤化/平衡/导出** | 数值平衡微调（不改架构） | — | 皮肤包切换、**默认水墨风 2.5D 皮肤（模型/材质/粒子/图标）**、Win 导出 | 换皮肤零代码；默认皮肤完整；导出可独立运行；自检全绿 |

---

## 8. 工程与 Git 规范

### 8.1 仓库与提交

- 远程 `https://github.com/chufu152/xiuxiangame2.0.git`，主分支 `main`。
- **每个任务/里程碑完成并通过自检后立即提交并推送**：
  ```
  git add -A
  git commit -m "feat(r5-combat): 实现十兵种战力与胜率结算"
  git push origin HEAD:main
  ```
- 约定式提交 `feat/fix/docs/refactor/test/perf/chore`，建议带模块范围。提交信息用**英文**。
- **worktree 说明**：WorkBuddy 在独立 worktree（分支 `workbuddy/main-*`）工作，`main` 可能同时被主检出占用，故统一推 `HEAD:main` 而非 `push origin main`。
- **远程固定 HTTPS，禁止改成 SSH、禁止自行生成 SSH key**。仓库本地（**仅本仓库，不写 `--global`**）已配 `http.proxy`/`https.proxy = http://127.0.0.1:7890`，凭据走 Windows 凭据管理器；worktree 内提交后直接 `git push origin HEAD:main`。
- 新 clone 的仓库没有仓库本地代理时：`git config http.proxy http://127.0.0.1:7890 && git config https.proxy http://127.0.0.1:7890`；或仅对单条命令临时加 `-c http.proxy=... -c https.proxy=...`，不写全局。
- 报 401/403 时改用 `git -c credential.helper=manager push origin HEAD:main`。本机默认继承的 `credential.helper=helper-selector` 在受限/无交互环境会卡死并报 `could not read Username ... terminal prompts disabled`，此时需显式重置助手链（见 `docs/prompts/README.md`）。

### 8.2 GDScript 规范

- 全部静态类型：`var x: int = 0`、`func f(a: String) -> Dictionary:`；常量 `const`；避免无类型 `Variant` 滥用。
- 规则层（`server/scripts/rules`）与节点解耦：不继承 Node2D/Node3D，不调渲染/音频；便于无头测试。
- 枚举统一引用 `shared/protocol/enums.gd`；命令名引用 `commands.gd`；禁止散落字符串字面量。
- 不硬编码数值：一律从 `data/gameConfig.json` 读（含 2.0 新增地形参数）。

### 8.3 自检（`tools/check.ps1`）

自检**随里程碑扩展**：每个里程碑只**增加**该阶段可机检的断言，既有断言不得为通过而删减。退出码全绿 0，否则非 0（打印 `CHECK_RESULT=OK` / `FAIL`）。

- **前置**：两个工程各跑一次 `--headless --path <proj> --import`（生成 `.godot/global_script_class_cache.cfg`），否则 `class_name` 全局类报 `not declared`。
- **R0**：`shared/` 目录联接幂等与内容贯通（临时文件双向可见）、配置缺失负向用例（非零退出）、headless 监听就绪（TCP 轮询）、`SmokeTest`（hello/ping/`UNKNOWN_COMMAND`/`NO_ID`）、无残留进程、零 `.java`。
- **R1**：固定种子双跑导出 tiles 全字段**逐字一致**（`outputs/r1_authority_a|b.json` SHA256 相同）；MOUNTAIN≈8% / HILL≈22%（±3%）；河流边成对且连续、由高至边界；≥1 条连绵 ≥3 格山脉；出生点中心与三方向安全且可走通；节点只落偏好地形；4 宗 × (1 主峰 + 1 金丹宗主 + 2 炼气外门)、初始资源 400/300/120/0 与 晶2/铁2/木4；玩家 `visibleTiles`/`exploredTiles` 与视野半径一致且不下发未见敌方单位。**客户端**：无头验收（侧栏对未探索格不泄露地形、相机锁 45° 无旋转输入、占位缺失只 WARN 一次）与**端到端**（客户端拉起 headless 服务端 → `newGame` 收到 300 格 view + 四宗公开信息 → `getState` 往返 → view 刷新保持相机 transform/size）。当前 `check.ps1` 为 **10 阶段**（`[0/9]`–`[9/9]`），共 **50** 项断言。
- **R2 起**：启动 headless 服务端，固定种子跑 N 回合（30/60），导出事件流；断言地图/资源/阶段/胜负、地形移动成本、战斗预览==实战（含高地/跨河）、关键经济产出。
- **通用**：配置校验（缺字段/非法枚举/引用已删模块即失败）；同种子双跑逐字一致（含地形生成）；结束后**无残留 godot 进程**。

### 8.4 客户端相机与 UI 硬性要求（针对 1.0 反馈）

- **相机**：锁定 45° 正交 2.5D（yaw=45°/pitch=45°），禁止自由旋转；滚轮缩放以鼠标为中心、中键/右键拖拽平移；相机状态（位置、正交 size、朝向）由客户端 CameraRig 自持，**任何操作、动画、收到 view 快照后都不得重置相机角度与缩放**；单位移动动画只移动镜头内要素，不改变相机 transform（除非玩家主动平移跟随，且可关）。
- **入口**：所有命令都有可见入口，不可用按钮置灰并悬浮说明原因；悬停/预览直观（移动范围、攻击胜率、造价、收益、地形加成、建城选址是否缺水）。
- **操作**：左键选择/框选、滚轮缩放、中键/右键拖拽平移、键盘快捷键；空格/End 结束回合。
- **视觉（水墨 2.5D）**：六边形网格线可开关；地块归属用宗门颜色边框标识；功能色读图（丹房红/药田绿/地形底色）；所有模型轮廓描边强化，全局缩到最远仍可分辨设施；简易昼夜循环、草木摆动、飞鸟、灵气粒子；地图按 海拔/地貌/河流/节点/单位/迷雾 分层。
- **布局**：顶部资源栏、底部操作栏、左侧城市/弟子、右侧势力/胜利；Toast 显示事件与业务失败文案；选中地块在侧栏列出全部地形要素（基底/海拔/地貌/河流/险地/节点/资源/改良/归属）与产出明细。

---

## 9. 完成定义（Definition of Done）

一个里程碑只有满足以下全部条件才算完成：

1. 服务端规则与 `data/gameConfig.json` 数值一致，关键公式有断言；2.0 新增地形参数在配置中可调。
2. 对应命令在 `implementedCommands` 内，`ping`/握手/错误码/业务失败口径正确。
3. 客户端有对应 UI 入口，操作后相机角度/缩放保持，信息直观。
4. 固定种子整段可复现（双跑逐字一致），地形生成确定；新增随机序列号已登记复位。
5. 缺失美术资源有占位且不崩溃；美术仅经逻辑 ID 引用。
6. `tools/check.ps1` 全绿；无残留 godot 进程；无客户端规则实现。
7. 已 `git commit` 并 `git push` 到 `main`，提交信息符合约定。

---

## 10. 开放决策点（评审时确认）

| # | 决策点 | 推荐默认 | 不选默认的影响 |
|---|---|---|---|
| 1 | 语言 | GDScript 静态类型 | 改 C# 需两端换 .NET 版、工具链与 CI 调整 |
| 2 | 通信 | WebSocket | 选 stdio 不利未来联机；选 ENet 需自行处理可靠/重连 |
| 3 | 首版是否真联机 | 否，仅本地回环 + 架构预留 | 做真联机需房间/多人权威/断线重连，工作量显著增加 |
| 4 | 砍外交后开战规则 | 默认可自由攻击（逐鹿设定） | 若保留需引入最小"宣战"动作 |
| 5 | 灾劫是否与随机事件一并排除 | 一并排除（秘境内部风险保留） | 保留需恢复 DisasterService 与待决/配置 |
| 6 | 安定去叛乱后结算 | 仅产出/人口惩罚 | 要叛乱需保留 LoyaltyService 与赏赐 |
| 7 | 地形起伏强度 | 3 海拔（平/丘/山 70/22/8）、2 地貌、1–2 条河 | 更平缓（少山岳）利通行但空间决策弱；更崎岖则建城/行军受限、需更多调参 |
| 8 | 河流是否给额外移动消耗 | 跨河 +1（设计初值） | 不给则河流仅影响战斗与产出，行军取舍更弱 |
| 9 | 山岳是否可被特殊单位翻越 | 首版仅传送，不做登山单位 | 做登山/飞行单位需新增道法/兵种与通路规则 |

---

## 附录 A：数值与配置索引

完整数值以 `data/gameConfig.json` 为准（R1 从 1.0 迁移并按第 5 章裁剪，按 4.1 扩展地形块）。
- **1.0 迁移块**：`map`、`disciple`、`spiritPeak`、`economy`、`resources`、`combat`、`building`、`explore`、`appointment`、`ai`、`faction`（含 bloodline/zongMen/jiaZu/guoJia）、`victory`、`qiYun`、`powerLevel`、`daoTree`（daos 21 + boosts 4）、`vision`、`warfare`（unitClasses 10/counters/promotions 9）、`city`（district 5+首府区/邻接）、`improvement`（byType 8）、`policy`（governments 3/cards 10）、`road`、`teleport`、`automation`、`speed`、`difficulty`。
- **裁剪块（不迁/禁用）**：`diplomacy`、`threat`、`event`、`disaster`、`loyalty`、`strategy`（AI 性格）。
- **2.0 新增块（设计初值）**：`map.baseTerrains`（3 基底）、`map.relief`（FLAT/HILL/MOUNTAIN 高度/移动/防御/视野/比例）、`map.features`（灵林/雾泽）、`map.river`（跨河/灌溉/数量）、`map.nodeSpawnByTerrain`（节点地形分布）。

## 附录 B：术语表

- 灵峰 SpiritPeak：宗门城市/据点；主峰为首都。
- 弟子 Disciple：单位/人口，兼具修炼者与兵种身份。
- 基底 baseTerrain / 海拔 relief / 地貌 feature：地块的三层地形要素（2.0）；河流 river 是地块边。
- 节点 GameNode：单格资源/探索点（灵田/灵脉/机缘/秘境/灵泉）。
- 区域 District：城市内独立占地的功能分区（另含灵峰自带首府区）。
- 道统 Dao：科技树道法（21 条）；道统成就 boost 为达成条件给的一次性道点奖励。
- 气运 QiYun：扩张/开峰容量；心魔 HeartDevil：弟子风险值。
- 势力等级 powerLevel：由领地/高境界弟子/道法/建筑加权的综合实力分（非声望折算）。
