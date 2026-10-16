# 《修仙4X·宗门争霸》2.0 重构需求文档（PRD + 技术规格）

| 项 | 内容 |
|---|---|
| 文档版本 | v1.0（2.0 重构基线） |
| 日期 | 2026-10-16 |
| 性质 | **借重构重新设计**：技术架构从零重做，玩法规则以 1.0 成熟实现为蓝本冻结并裁剪 |
| 仓库 | `https://github.com/chufu152/xiuxiangame2.0.git` |
| 技术 | Godot 4.x / GDScript（静态类型）；服务端权威 + 客户端表现，前后端分离，WebSocket 通信 |
| 数值权威 | `data/gameConfig.json`（本文件所有数值必须与之一致，冲突以配置为准） |
| 蓝本来源 | 1.0 源码 `gameConfig.json` / `GameEngine` / `TurnProcessor` / `CombatResolver` / `PROTOCOL.md` / `COMMAND_MAP.md` |

> **使用方式**：本文是 2.0 的唯一权威需求。每一章都可直接拆成 WorkBuddy 任务。标注 **【默认·待确认】** 的是已给出推荐默认、但允许在评审时改的少数决策点；其余为冻结需求。

---

## 0. 阅读对象与范围

- 给：服务端程序、客户端程序、策划（数值）、QA。
- 规定：2.0 首版**做什么、不做什么**；架构分层与通信契约；玩法规则与数值；里程碑与验收；工程与 Git 规范。
- 不规定：具体美术成品（给规范与资源位）、UI 视觉稿（给交互与信息要求）、真实多人联网（架构预留，首版不做）。

---

# 第一部分　项目与架构

## 1. 项目概述

### 1.1 游戏定位

- 类型：单机、回合制、4X（eXplore 探索 / eXpand 扩张 / eXploit 经营 / eXterminate 征服）。
- 题材：中式修仙·宗门争霸。
- 一局：1 名玩家 + 3 家 AI，在一张六边形地图上争夺资源、扩张灵峰、修炼道统、攻城略地，最终以各自流派的胜利条件或分数取胜。
- 三流派（玩家与 AI 各择其一）：
  - **宗门流（ZONG_MEN）·天剑门**：道统推演，研究 +30%、分峰省费；特色兵种**剑阵使**、特色建筑**护山剑阵**。
  - **家族流（FAMILY）·烈氏家族**：血脉繁衍，修炼 +40%、高品灵根概率 60%；特色兵种**血脉修士**、特色建筑**祖祠**。
  - **国家流（DYNASTY）·大乾王朝**：王朝扩张，开峰/扩张省费、领土人口权重 ×2；特色兵种**机关军团**、特色建筑**王朝帝都**。

### 1.2 设计支柱（重写时优先保护的核心乐趣）

1. **多流派异质胜利**：三条发育路线（科技飞升 / 血脉繁衍 / 领土征服）体验与目标显著不同。
2. **弟子成长与渡劫抉择**：灵根、境界、心魔、晋升、转职构成可持续的养成与取舍。
3. **战术战斗**：十兵种相克、地形/高地/跨河、城防、ZOC、远程零反击、撤退——以可预览的胜率做决策。
4. **城市经营拼图**：区域独立占地 + 邻接、人口/住房/安定/劳动力、灵峰容量与铺张惩罚。
5. **确定性与可复现**：固定种子整局可复现（服务端权威 + 集中随机源），便于测试与平衡。

### 1.3 平台、输入、呈现

- 平台：PC（Windows 优先，Godot 可跨平台导出）。
- 输入：鼠标为主（点选、框选、悬停、滚轮）、键盘快捷键（结束回合等）。
- 呈现：3D 正交相机 **2.5D 斜俯视**，相机锁定 **yaw=45°、pitch=45°**，禁止自由旋转，保留缩放（正交 size）与平移。
- 地图：flat-top 六边形，轴向坐标 `(q,r)`，默认 20×15 = 300 格。
- 单局时长：约 2–4 小时（240 回合上限）。

### 1.4 2.0 首版范围一览

- **纳入**：地图与迷雾、三流派、弟子（境界/灵根/岗位/修炼/心魔）、回合循环与经济、灵峰/城市/区域/人口、地块改良与道路、道统科技树、十兵种战术战斗（含攻城/夺点/撤退/传送）、探索（机缘/秘境）、任命/渡劫/飞升、政令（裁剪）、自动化、三流派胜利与分数胜利、基础反应式 AI、存档。
- **暂不纳入（首版明确裁剪，详见第 5 章）**：外交/厌战、随机事件、叛乱/忠诚、蛮族巢穴、灾劫、AI 长期战略性格。

---

## 2. 技术架构（全 Godot 前后端分离）

### 2.1 架构总览

```
┌───────────────────────────────┐         WebSocket (JSON 文本帧)        ┌──────────────────────────────┐
│           client/             │   ws://127.0.0.1:9527（单机回环）        │           server/            │
│  Godot 客户端（渲染/表现）      │  ═══════════════════════════════════> │  Godot --headless（权威逻辑）  │
│  - 场景/相机/输入/动画/Tween    │  请求 {id,type,params}                  │  - GameState（唯一真相）       │
│  - HUD 与面板                  │  <─────────────────────────────────── │  - rules/ 全部规则            │
│  - AssetLibrary（可替换美术）   │  响应 {id,ok,events,view,result}       │  - config/ 读 gameConfig.json │
│  - 零玩法规则                  │  主动 hello / awaitInput(victory)       │  - save/ 存档                 │
└──────────────────────────────┘                                         └──────────────────────────────┘
        ▲ 引用                          两端共享 shared/protocol/                      ▲ 读取
        │                                                                  ┌──────────┴─────────┐
┌───────┴────────┐                                          ┌──────────────┴──────┐   ┌──────────────────┐
│ assets/ 美术包  │ （客户端独占，可整体替换）                 │ data/gameConfig.json │   │ saves/（FileAccess）│
└────────────────┘                                          └─────────────────────┘   └──────────────────┘
```

- **权威在服务端**：地图、随机数、移动范围、视野、产出、伤害、胜率、胜负全部由服务端计算。客户端**不实现任何玩法规则**，只做表现、输入与界面；所有"能不能做/要花多少/会发生什么"必须通过 `query*` 命令向服务端取。
- **单机运行形态**：客户端启动时通过 `OS.create_process` 拉起本地 `server` 可执行（headless，传 `--port=9527 --data=<path>`），连接 `ws://127.0.0.1:9527`；客户端退出时关闭子进程。服务端也可由开发者单独运行。
- **未来联机预留**：传输层与协议与部署无关；远程联机时只需把服务端部署到主机、客户端连接其地址（首版**不做**真正的多人联网，只保证架构不堵死这条路）。

### 2.2 关键技术决策

| 决策点 | 选择 | 理由 |
|---|---|---|
| 语言 | **GDScript（静态类型）** | 两端单语言、与 Godot 结合最好、AI 生成语料稳定；禁用弱类型，全部用 `:=`/类型注解 |
| 工程数量 | **两个 Godot 工程**（`client/`、`server/`） | 物理隔离规则与表现，服务端可独立导出/部署，不打包美术与 UI |
| 共享代码 | 顶层 `shared/`，通过**目录联接（junction）**挂进两端 | 协议常量、枚举、DTO、几何两端一致；`tools/setup_shared.ps1` 建 junction |
| 通信 | **WebSocket + JSON 文本帧**（`WebSocketPeer`） | 回合制需可靠有序；本地回环与未来远程皆可；好调试；Godot 原生支持 |
| 服务端运行 | Godot `--headless` 主场景 `ServerMain.tscn` | 无渲染、无音频、无输入；可在 CI 无头跑 |
| 数据格式 | JSON（小驼峰字段、枚举大写下划线） | 与 1.0 协议一致，便于同种子对照 |
| 配置 | `data/gameConfig.json` 启动加载 + 校验 | 数值与代码分离；服务端独占 |
| 存档 | `FileAccess` 写 JSON 到 `user://saves/`（开发期指向工程 `saves/`） | 槽位制、版本号、自动存档 |

> **【默认·待确认】** 语言 GDScript；若团队更偏好强类型工程可改 C#（两端都用 .NET 版），但不允许混用。通信 WebSocket（不选 stdio：后者只能本机子进程、不利联机；不选 ENet/UDP：4X 回合制无需实时性）。

### 2.3 目录结构（落地约定）

```
xiuxiangame2.0/
├── client/
│   ├── project.godot
│   ├── scenes/        # MainMenu / Game（地图） / HUD / 对话框与面板
│   ├── scripts/
│   │   ├── net/       # NetClient（WebSocket 连接、收发包、重连、拉起子进程）
│   │   ├── world/     # HexMap、CameraRig（锁45°）、TileMesh、UnitView、PeakView、Fog
│   │   ├── ui/        # TopBar/BottomBar/LeftPanel/RightPanel、各 Dialog、Toast、VictoryOverlay
│   │   ├── art/       # AssetLibrary（按逻辑 ID 加载 manifest）、占位回退
│   │   └── view/      # view 快照的客户端只读模型（DTO→显示数据，不含规则）
│   └── addons/
├── server/
│   ├── project.godot
│   ├── scenes/ServerMain.tscn
│   └── scripts/
│       ├── net/       # NetServer（监听/会话）、CommandDispatcher、StateView（快照）、协议编解码
│       ├── model/     # GameState、Sect、Disciple、SpiritPeak、HexTile、GameNode、Project、枚举
│       ├── rules/     # MapGenerator、MoveRange、Vision、Combat、Economy、Population、
│       │              #  City、Improvement、Road、Dao、Explore、Appointment、Policy、
│       │              #  Automation、Victory、AI、TurnProcessor
│       ├── config/    # ConfigLoader、ConfigValidator（启动校验，缺字段即报错）
│       ├── rng/       # 集中随机源（按种子+回合+序列号派生，保证可复现）
│       └── save/      # SaveManager（槽位、版本、自动存）
├── shared/protocol/
│   ├── commands.gd    # 命令名常量（lowerCamelCase，与 1.0 同名）
│   ├── msg.gd         # 信封/主动消息类型常量
│   ├── enums.gd       # 枚举字符串（与配置一致，大写下划线）
│   └── dto.gd         # 消息与快照的静态类型类（两端共用）
├── shared/geo/
│   └── hex.gd         # 六边形轴向坐标、邻接、距离、世界坐标换算（纯函数，两端共用）
├── assets/            # 见第 3 章
├── data/gameConfig.json
├── docs/              # 需求、协议、提示词、报告
├── tools/
│   ├── setup_shared.ps1   # 建 shared→client/server 目录联接
│   ├── run_dev.ps1        # 起 server + client
│   ├── export_server.ps1 / export_client.ps1
│   └── check.ps1          # 无头自检（固定种子 N 回合、确定性、规则断言）
├── saves/、exports/   # gitignore，保留 .gitkeep
```

### 2.4 服务端分层职责（rules/）

- `model/`：纯数据实体（`RefCounted`/`Resource`），不写规则、不依赖节点。
- `rules/`：全部为无状态或仅依赖 GameState 的纯函数模块，输入 GameState + 命令，产出结果与事件；**禁止**在规则里读节点、播放音效、访问美术。
- `rng/`：全服唯一随机入口。任何随机（战斗、地图、探索、AI、繁衍）都从 `rng` 取，按 `seed ^ turn ^ 序列号` 派生；禁止散落 `RandomNumberGenerator.new()`。
- `net/CommandDispatcher`：命令名 → rules 方法；参数校验；业务失败与协议失败分离；按 §6 拼信封。
- `config/ConfigValidator`：启动时校验 `data/gameConfig.json` 的字段完整性与取值合法（缺字段、非法枚举、负值等直接报错退出）。

### 2.5 确定性与可复现（硬约束）

- 固定种子下，同一份命令序列必须产生**逐字一致**的事件流与终局（与 1.0 D1 修复口径一致）。
- 所有可变序列（地图、战斗、弟子、探索、AI 等）使用集中登记的序列号；开新局与读档都要复位。
- 自检 `tools/check.ps1`：同种子跑两遍 N 回合，事件流逐字一致；并与 1.0 同种子对照（首版至少对核心命令输出）。

### 2.6 存档

- JSON 文件，槽位制（`saves/slot_<n>.json`）；`saveVersion = "3.0"`。
- 每 10 回合自动存档到槽 0；`listSaves` 返回槽号/回合/玩家宗门/流派/时间/大小。
- 存档保存完整 GameState（含种子、序列号、回合、阶段、所有实体、队列、冷却）；读档后必须能继续、待决点能重建（2.0 仅剩胜利待择）。
- 客户端显示设置（动画速度、自动播放等）不进存档，留在客户端本地。

---

## 3. 美术资源规范（独立、可替换）

美术资源**完全独立于代码**，客户端只通过稳定的"逻辑资源 ID"引用，由 `assets/manifest.json` 映射到物理文件。**换皮 = 换皮肤包文件夹 + 改 manifest，零代码改动。**

### 3.1 皮肤包与目录

- `assets/art/<pack>/`：一个皮肤包（默认 `default`），下分 `terrain/ units/ buildings/ ui/ icons/ atlas/`。
- `assets/audio/{bgm,sfx}/`、`assets/fonts/`。
- `assets/manifest.json`：声明 `activePack`、纹理过滤、资源条目（`id/path/type/size/offset/billboard/nine_patch`）。

### 3.2 逻辑 ID（稳定，代码只认它）

- 地形：`terrain.PLAIN / DANGER / FOREST / MOUNTAIN / SPIRIT_VEIN / SPIRIT_SPRING / RIVER`
- 兵种：`unit.PU_TONG / JIAN_XIU / FA_XIU / TI_XIU / SHOU_LING / FU_XIU / JI_GUAN / JIAN_ZHEN / XUE_MAI / JIGUAN_BINGTUAN`
- 建筑：`building.MOUNTAIN_GATE / HALL / CLASSICS / PEAK_STUDY / PEAK_ELIXIR / PEAK_ARTIFACT / PEAK_TEACH / SWORD_FORMATION / ANCESTRAL_HALL / DYNASTY_CAPITAL`
- 改良：`improvement.LING_TIAN / TERRACE / MINE / QUARRY / HERB / SPIRIT_ARRAY / ROAD / CAVE`
- 资源：`resource.spiritPower / spiritStones / workPower / prestige / qiYun / food / daoPoints / tian_jing / xuan_tie / ling_mu / <luxury>`
- 境界/势力：`realm.LIAN_QI … HUA_SHEN`、`faction.ZONG_MEN / FAMILY / DYNASTY`。

### 3.3 客户端 `AssetLibrary` 行为

1. 启动读 manifest，建 ID→路径表；`ResourceLoader` 懒加载并缓存。
2. **缺失资源不崩溃**：回退程序化占位（按分类给色块 + 文字标签）并打 `WARN`。
3. 支持 F5 热重载 manifest。
4. 像素风纹理统一 **Nearest** 过滤；单位/建筑为竖直板（`billboard`），锚点落在柱顶/地面。

### 3.4 美术规范

- 风格：精致像素、青绿山水 + 鎏金点缀、中式修仙、斜俯视 2.5D。
- 地形柱贴图与 `map.hexSize`、地形高度（平原 4 / 险地 8 / 山岳 10 / 灵脉 20 / 灵泉 6）对齐，相邻无缝。
- 单位/建筑统一基准像素高度、统一朝向、底部落点锚点；文件小写蛇形。
- 音频：BGM 用 `.ogg` 循环，SFX 用 `.wav/.ogg`；字体放 `fonts/`。

---

# 第二部分　玩法规则（以 1.0 为蓝本，数值权威见 `data/gameConfig.json`）

## 4. 玩法规则

### 4.1 地图与六边形

- 网格：flat-top 六边形，**轴向坐标 `(q,r)`**，地图对象 `tiles` 以 `q{r}_r{r}` 为键；默认 20×15。
- 世界坐标（`hexSize=0.7`）：`x = hexSize*1.5*q`；`z = hexSize*√3*(r + q/2)`；柱体沿 −Y。
- 地形类型与基础数值：

| 地形 | 移动消耗 | 产出 | 防御 | 备注 |
|---|---|---|---|---|
| PLAIN 平原 | 1 | 灵4 / 石2 / 工2 / 粮4 / 木1 | — | 柱高 4 |
| DANGER 险地 | 2 | 灵2 / 天晶1 | 防御 +25% | 高地 +15%；柱高 8 |
| FOREST 森林 | 1 | 灵2 / 工1 / 粮2 / 木1 | — | 柱高 4 |
| MOUNTAIN 山岳 | 2 | 灵1 / 玄铁1 / 木1 | — | 柱高 10 |
| SPIRIT_VEIN 灵脉 | — | 灵14 / 石6 / 工2 | — | 柱高 20，节点源 |
| SPIRIT_SPRING 灵泉 | — | 灵9 / 粮2 | — | 柱高 6 |
| RIVER 河流 | 1 | 石1 / 粮1 | 攻方跨河 −25% | |

- 资源点 **GameNode（节点）**：由 3 格组成（`clusterTiles`），中心为占位，占领后整团归主；类型含灵脉/灵泉/灵田/矿脉/药园/灵茶/云锦/灵玉/机缘/秘境。视野节点范围 = 2。
- 出生：玩家主峰在地图中心；3 AI 依次在 `(1,1)`、`(w-2,1)`、`(1,h-2)` 附近取最近无主格；出生点附近保证 1 灵泉、1 灵脉。

### 4.2 视野与战争迷雾

- 三态：**未探索 / 已探明（记忆）/ 可见**。权威为每宗 `visibleTiles`、`exploredTiles`，客户端不得自行推导。
- 视野半径：灵峰 3、节点 2；弟子按境界：炼气 2、筑基 3、金丹 3、元婴 4、化神 4。
- 视野在回合开始、移动、驻守、夺峰/夺点后重算；灵峰/节点易主当场为双方重算。

### 4.3 势力与三流派

- 初始资源：灵力 400、灵石 300、工力 120、声望 0、气运 50；材料 天晶 2 / 玄铁 2 / 灵木 4。
- 开局每宗：1 主峰（人口 3）+ 宗主（金丹）+ 2 外门弟子（炼气）。家族流始祖为血脉世代 1 的嫡支。
- 流派特性（`faction.flavors`）：

| 流派 | 修炼 | 研究 | 开峰费 | 其它 | 特色兵种 | 特色建筑 |
|---|---|---|---|---|---|---|
| 宗门 ZONG_MEN | ×1.0 | ×1.3 | 500 | 分峰（区域）花费 ×0.8 | 剑阵使 JIAN_ZHEN | 护山剑阵 SWORD_FORMATION |
| 家族 FAMILY | ×1.4 | ×1.0 | 800 | 高品灵根概率 60% | 血脉修士 XUE_MAI | 祖祠 ANCESTRAL_HALL |
| 国家 DYNASTY | ×1.0 | ×1.0 | 350 | 灵峰建筑 ×0.9、扩张 ×0.8、领土人口权重 ×2 | 机关军团 JIGUAN_BINGTUAN | 王朝帝都 DYNASTY_CAPITAL |

### 4.4 弟子系统

- **境界**：炼气 LIAN_QI(1) / 筑基 ZHU_JI(2) / 金丹 JIN_DAN(3) / 元婴 YUAN_YING(4) / 化神 HUA_SHEN(5)。
- **岗位**：杂役 ZA_YI / 外门 WAI_MEN（炼气起）/ 内门 NEI_MEN / 亲传 QIN_CHUAN（筑基起）/ 峰主 FENG_ZHU / 长老 ZHANG_LAO / 宗主 ZONG_ZHU（金丹起）。
- **灵根**：金/木/水/火/土/风（移动 +1）/雷/杂灵根（品级 1，移动 −1）；品级 1–5。
- **移动力**：基础 2 + 境界加成（金丹 +1 / 元婴 +2 / 化神 +3）+ 风灵根 1 − 杂灵根 1 + 道法移动加成 + 道路网加成。
- **移动代价**：地形 `moveCost`（平原/森林/河流 1，山岳/险地 2）+ 敌方控制区 ZOC（+2）− 本宗青石道路减耗；移动范围用 BFS 计算，`queryMoveRange` 与实际移动共用同一算法，"高亮即可达"。
- **修炼**：速度 10 进度/回合（受流派/建筑/区域/道法/政策影响）；进度上限：炼气 100 / 筑基 200 / 金丹 400 / 元婴 800 / 化神 1600；突破概率：0.8 / 0.6 / 0.4 / 0.2。
- **渡劫**（元婴→化神）：耗灵力 500 + 天晶 3 + 玄铁 2 + 灵石 300；基础成功率 30%，每解锁道法 +5%、每灵根品级 +5%；失败心魔 +50 且 30% 陨落；成功即飞升候选。
- **心魔（0–100）**：≥50 战力 −10%，≥80 战力 −25% 且可能受伤，≥100 叛逃；人数超容量时每回合 +5；近战反击胜方反噬心魔 = max(1, 反击战力/10)。
- 重伤：移动力减半、战力 ×0.5；回合开始有概率伤愈。
- 出手次数：每回合默认 1 次攻击；攻击额外消耗 1 移动力。
- 收徒：每峰最多 2 人，冷却 3 回合，耗灵力 200；成长上限筑基 2，招募境界上限炼气；家族流走血脉繁衍（冷却 8 等）。

### 4.5 回合流程

六阶段（`TurnPhase`），单线程顺序推进：

1. **TURN_START**：刷新迷雾 → 刷新道路网络 → 传送次数清零 → 宗主外出检查（大殿全局加成失效判定）→ 每名弟子（重置移动力/出手、入宗年限 +1、伤愈、修炼）→ 自动化行动。
2. **SPIRIT_PEAK**：围城断供削减 → 各灵峰项目队列推进 → 各宗研究队列推进（工力不足则暂停）。
3. **PLAYER_ACTION**：玩家操作阶段。
4. **SETTLEMENT**（2.0 裁剪后顺序）：节点冷却 −1 → 各宗逐峰**城市人口结算**（补劳力/粮食/增长）→ **经济结算**（按当时劳动力汇总产出与维护）→ 道统顿悟领取 → 心魔结算 → 政令结算（威望/产出，不含厌战）。
5. **AI_ACTION**：3 家 AI 各跑一次基础行动点决策（非玩家、未覆灭者），随后刷新其迷雾。
6. **VICTORY_CHECK**：胜负判定；未结束回到 TURN_START；终局冻结操作；每 10 回合自动存档槽 0；240 回合强制结算分数胜利。

> 2.0 删除了 1.0 SETTLEMENT 中的：外交厌战、世界威胁（巢穴）、随机事件、灾劫、忠诚叛乱（见第 5 章）。

### 4.6 资源体系

- 灵力 spiritPower（修炼/建造/扩张）、灵石 spiritStones（高级建造/传送/赋税）、工力 workPower（推进项目与改良）、声望 prestige（势力等级，每 100 声望 = 1 势力等级）、气运 qiYun（开峰/扩张的容量，每峰上限 100）、灵粮 food（人口与弟子维护）、道点 daoPoints（研究道法）。
- 战略材料：天晶 tian_jing、玄铁 xuan_tie、灵木 ling_mu（建筑/渡劫/高阶单位）。
- 奢侈品：灵茶 SPIRIT_TEA（安定 +5/石 10）、云锦 CLOUD_BROCADE（灵 +5/声望 +10）、灵玉 SPIRIT_JADE（修炼 +10%/声望 +15）。
- 维护：每名弟子每回合 灵粮 1、工力 0.5；建筑另有工力维护。
- 产出 = 基础 + 工作半径内分配人口的地块 + 改良 + 节点 + 区域 + 建筑 + 道法 + 政令；安定影响产出（见 4.7）。

### 4.7 灵峰与城市

- 灵峰容量：基础 10 人，每级 +5；气运上限 100；最高 5 级；超出容量每峰 5% 铺张惩罚（产出/效率）。
- 开辟灵峰：耗灵力（宗门 500 / 家族 800 / 国家 350），5 回合；国家流扩张 ×0.8。
- 防御加固：耗 200 灵力，城防 +10；城防基础 20、上限 100。
- **建筑（10 种）**：

| 建筑 | 造价(灵) | 回合 | 材料 | 效果 | 归属 |
|---|---|---|---|---|---|
| MOUNTAIN_GATE 山门 | 200 | 3 | 木2 | 城防 +15 | 通用 |
| HALL 宗主大殿 | 400 | 5 | 铁1木2 | 全局 产出/修炼/研究 +15%，城防 +10 | 通用 |
| CLASSICS 藏经阁 | 350 | 4 | 铁1 | 道点 +2/回合，城防 +5 | 通用 |
| PEAK_STUDY 修炼分峰 | 250 | 3 | 木2 | 修炼速度 +10/峰 | 通用 |
| PEAK_ELIXIR 丹堂 | 220 | 3 | — | 灵粮 +1/回合 | 通用 |
| PEAK_ARTIFACT 器堂 | 300 | 4 | 铁1 | 工力 +10/回合 | 通用 |
| PEAK_TEACH 讲道分峰 | 250 | 3 | — | 突破率 +5% | 通用 |
| SWORD_FORMATION 护山剑阵 | 450 | 5 | 晶1铁2 | 城防 +30 | 宗门 |
| ANCESTRAL_HALL 祖祠 | 450 | 5 | — | 修炼 +15%/稳定，血脉 | 家族 |
| DYNASTY_CAPITAL 王朝帝都 | 500 | 6 | 晶2铁2 | 城市扩张 +1 | 国家 |

- **区域（5 类，独立占地、可邻接）**：道 DAO（每指派 1 人 +1 道点/2 回合）、修炼 STUDY（每人 +10 修炼进度）、丹器 ELIXIR（灵粮/工力/材料）、法坛 LEGAL（安定）、坊市 MARKET（+3 灵石、+1 奢侈品）；每峰最多 4 区域；每个区域提供 3 个人口岗位（`popPerDistrict`）。
- 工作半径：峰周围 2 格；可指派格由 `queryAssignableTiles` 返回，指派/撤下劳力由 `assignWorker/unassignWorker` 完成。
- **人口**：起始 3；粮食每累计 8 增长 1 人；住房 = 基础 6 + 峰等级×2 + 洞府×1 + 区域×2 + 建筑×1。
- **安定**：基础 70、上限 100；低阈值 40、危急 20；每回合增长 1（条件好）、恶化 −5；低安定时人口增长 ×0.5、产出 ×0.8；危急时产出 ×0.5。
- **洞府**：耗灵 200、2 回合、由筑基以上弟子开辟；每峰最多 5；+1 住房、+10% 修炼。
- 气运：开峰/扩张消耗；建筑/等级提供上限。

### 4.8 地块改良与建造者

- 建造者：每单位 3 次建造次数；最高境界筑基；`appointBuilder` 任命。
- 修缮：1 回合、15 工力；战斗会把地块改良打残（产出 −50%），需修缮恢复。
- 改良类型：

| 改良 | 花费(工) | 回合 | 效果 | 限制 |
|---|---|---|---|---|
| LING_TIAN 灵田 | 20 | 1 | 粮 +5 | 平地 |
| TERRACE 梯田 | 40 | 2 | 粮 +8 | 险地/山岳 |
| MINE 灵矿 | 40 | 2 | 工1/晶1/铁1 | 险地/山岳 |
| QUARRY 采石场 | 30 | 2 | 铁2/工1 | — |
| HERB 药园 | 35 | 2 | 粮2/晶1 | — |
| SPIRIT_ARRAY 聚灵阵 | 60 | 3 | 灵力 +5 | — |
| ROAD 青石道路 | 30 | 2 | 同宗道路网减移动消耗、连通加成 | 路网 |
| CAVE 洞府 | 灵30/工20 | 2 | +1 住房 | 需筑基 |

- 道路：同宗青石道路相连成网，降低单位移动消耗；城市可自动修路（自动化开关）。

### 4.9 道统科技树

- 道点：藏经阁 +2/回合；道区域按人口产出。
- 5 个时代：炼气篇 / 筑基篇 / 金丹篇 / 元婴篇 / 化神篇；共 **23 条道法**（19 条常规可研究 + 4 条顿悟），每时代需完成前置条数：4 / 4 / 5 / 5 / 5。
- 道法有 `cost`（道点）、`turns`（研究队列回合，耗工力）、`requiredEra`、`requiredDao`（前置）。
- 10 类效果：研究/修炼/战力/移动/灵力/工力/灵石/粮食/视野加成、解锁传送。
- 核心道法：**hun_yuan 混元大道**、**fei_sheng 飞升妙法**（宗门流胜利必需）。
- 4 条顿悟（每境界突破时 30% 概率，boost）：五行通脉（修炼 +20%）、金丹固道（突破 +20%/战力 +10/灵 +100）、元婴出窍（移动 +1/战力 +15）、化神返虚（全资源 +20%/战力 +20）。
- 研究队列支持取消、加速（`researchDao/cancelProject/accelerateProject/queryProjectQueue`）。

### 4.10 兵种与战斗

**十兵种（基础系数）**：

| 兵种 | 攻 | 防 | 射程 | 移动 | 定位 | 限制 |
|---|---|---|---|---|---|---|
| PU_TONG 寻常弟子 | 1.0 | 1.0 | 1 | 0 | 通用 | — |
| JIAN_XIU 剑修 | 1.3 | 1.0 | 1 | 0 | 近战主力 | 炼气 |
| FA_XIU 法修 | 1.1 | 0.8 | 3 | 0 | 远程（零反击） | 炼气 |
| TI_XIU 体修 | 0.9 | 1.4 | 1 | 0 | 反骑/肉盾 | 炼气 |
| SHOU_LING 御兽骑乘 | 1.1 | 1.1 | 1 | +2 | 骑兵机动 | 炼气 |
| FU_XIU 符修 | 0.9 | 1.0 | 1 | 0 | 辅助攻城 | 炼气 |
| JI_GUAN 机关傀儡 | 1.2 | 1.2 | 1 | 0 | 攻城单位 | 炼气 |
| JIAN_ZHEN 剑阵使 | 1.5 | 1.3 | 1 | 0 | 宗门精英 | 筑基+剑修 |
| XUE_MAI 血脉修士 | 1.4 | 1.1 | 1 | 0 | 家族精英 | 炼气+血脉 |
| JIGUAN_BINGTUAN 机关军团 | 1.6 | 1.4 | 1 | 0 | 国家终极 | 金丹+傀儡 |

**相克**：剑修→法修 ×1.3；体修→骑乘 ×1.3；傀儡→剑阵 ×1.3；剑阵→普通 ×1.2；符修→傀儡 ×1.2；骑乘→体修 ×1.2；机关军团→剑修 ×1.3。

**战力公式（基础）**：

```
power = 境界等级×10 + 灵根品级×5 + 道统COMBAT_BONUS
power = power × (1 + 政令战力%)
若重伤: power × 0.5
若心魔≥80: power × 0.75；若心魔≥50: power × 0.9
```

**对阵计算**：
- 攻方：`power × 兵种攻击系数 × 相克系数(对守方最强者) × (1 + 高地0.15 − 跨河0.25)`；攻灵峰时非攻城单位再 ×0.5（城防，需傀儡/符修/军团破防）。
- 守方：`power × 兵种防御系数 × (1 + 地形防御[险地0.25] + 驻守0.15)`；攻峰再加 `(峰防 + 区域防御) × (1 − 围城削减)`。
- 围城：相邻通道被敌方占据满 2 回合起，城防每回合 −10%，最多 −60%。
- 远程：距离 > 1 视为远程打击，守方**零反击**。
- 胜率：战力比（max/min）≥ 1.5 时强方**速胜/速败**；否则
  `winChance = clamp(0.5 + 0.5×(攻−防)/(攻+防), 0.02, 0.98)`。
- 实战：未碾压时打 1–3 回合，每回合双方战力各加 ±20% 噪声，按多数回合胜负；平局按 winChance 掷。
- 败方结局：按权重掷——**陨落 0.2 / 重伤 0.4 / 俘虏 0.2 / 击退（余下）**。陨落者移除并清空岗位；俘虏转投胜方；重伤移动力归零。
- 反击：贴身时守方最强者以 `power × 兵种反击系数` 反噬，胜方心魔 += max(1, 反击/10)。
- 经验：胜 +20、败 +8、击杀 +15、夺峰/夺点 +10；战技等级阈值 `[0,30,80,160,280]`；升级可择一晋升。
- 撤退：撤往相邻格，成功率 0.6，耗 1 移动力，失败移动力归零、被咬住。
- 三种攻击目标：**夺峰 PEAK**（占领灵峰、易主、城防）、**夺点 NODE**（占领 3 格节点）、**野战 DUEL**（击杀/击退弟子）。
- 胜利方每胜 +5 威望；胜战掠夺会打残目标格改良。

**9 条晋升**：避锋（防御+20%）、行剑（移动+1）、灵悟（修炼+15%）、化犀（攻城+30%）、破军（攻+25%）、内甲（受伤减免30%）、保甲（护卫+15%）、两界（射程+1）、神焰（攻+30%）；各有兵种与等级要求；晋升花费按等级 100/200/300。
**转职**：耗 200 灵力、冷却 5 回合；普通兵种需炼气，剑阵/军团有更高境界与前置要求。

### 4.11 探索（机缘 / 秘境）

- **机缘 jiYuan**：成功率 0.5，冷却 5 回合；成功得 工力 30 / 道点 1 / 天晶 1 / 玄铁 1 / 灵木 2；失败伤亡：受伤 15%、陨落 5%。
- **秘境 miJing**：最多 4 人组队，冷却 8，成功率 0.6，富裕概率 0.3（富裕奖励翻倍：工力 60 / 道点 2 / 晶2 铁2 木4）；失败伤亡：受伤 20%、陨落 10%。
- 由节点派遣：`sendToJiYuan`（单人）、`exploreMiJing`（多人）。

### 4.12 任命 / 渡劫 / 传送 / 集结

- 任命：峰主（驻峰，筑基）、长老、宗主（金丹）；宗主坐镇大殿才有全局加成，外出则失效；宗门流宗主陨落且无金丹以上继承人即败。
- 传送：需道法 `chuan_song`（咫尺天涯）；基础 30 灵石 + 每格 5；按灵脉容量限制；每回合次数有上限（回合开始清零）。
- 集结 rally / 回防 returnToDefense：自动化战术调动（单位向目标/主峰集结）。
- 驻守/撤回节点：`assignGarrison / withdrawGarrison`，驻守 +15% 防御。
- 批量移动：`batchMove`（多单位同目标）。

### 4.13 政令（保留并裁剪）

- 3 政体：**宗门共治**（默认，无政策卡）、**君主集权**（金丹后，槽位 经济2/军事2/治理2）、**世家门阀**（金丹后，槽位 经济1/军事2/治理2，原外交槽在 2.0 改治理）。
- 切换冷却 20 回合。
- 政策卡（2.0 保留 9 张，删除外交类"远交近攻"）：
  - 经济：尊贤纳士（修炼+10%）、精擅百工（工力+15%）、灵田连产（粮+20%）、赋税改革（石+15%）、钱庄汇通（石+10/回合）
  - 军事：厉兵秣马（战力+10%）、军屯戍边（粮+10%/驻守+10%）、军威森严（战力+15%）
  - 治理：世家共治（安定+10）
- 效果按回合以小数累积落地（避免整数丢失）。

### 4.14 自动化

- 全局开关：自动改良、自动修缮、自动道路、自动探索（阈值：改良/修缮 20、道路 100、探索 0）。
- 单峰 / 全峰自动项目；"立即探索"；集结 / 回防。
- 命令：`setAutomationToggle / setPeakAutoProject / setAllAutoProject / exploreNow / queryAutomationState`。

### 4.15 胜利与失败

- 回合上限 240；达到上限按分数结算。
- **宗门流**：道法全成（完成率 1.0，且含 fei_sheng、hun_yuan）+ 势力等级 ≥140 + 灵峰 ≥10。
- **家族流**：4 人飞升 + 族人 ≥12 + 元婴及以上高境界族人 ≥3。
- **国家流**：占据地块 ≥20% + 领土 ≥24 格 + 灵峰 ≥2。
- **分数胜利**：权重 = 势力等级 ×1 + 飞升 ×12 + 地块份额 ×40 + 道法完成 ×30 + 灵峰 ×3。
- 失败：弟子全灭；灵峰全失；宗门流宗主陨落且无金丹以上继承人。
- 同时达成多条胜利路线时，服务端发 `awaitInput(kind=victoryChoice)` 暂停，由玩家择一。

### 4.16 基础 AI（2.0 首版）

- **保留**：基于行动点（约 5 点）的反应式启发式：扩张（开峰/修路/抢点）、战斗（可胜则打）、研究（队列不空）、驻守（补防）、经济（项目/改良）。
- 三流派按其特性给倾向权重（宗门偏研究、家族偏修炼繁衍、国家偏扩张）。
- 难度倍率：初入仙途（AI 修炼/研究/战斗/扩张 ×0.85）、正道争锋（×1.0/1.0/1.1/1.1）、群雄噬血（×1.15/1.2/1.3/1.3）；初始资源倍率 1.0/1.0/1.1。
- **删除**：性格系统（好战/图治/纵横）、跨回合长期战略复盘、外交议程（rivalAgendas）。

---

# 第三部分　范围裁剪、接口契约、里程碑与工程规范

## 5. 2.0 范围裁剪与耦合点裁决

### 5.1 暂不纳入模块（命令级，共裁剪 19 条命令）

| 模块 | 裁剪命令 | 对应 1.0 服务 |
|---|---|---|
| 外交 / 厌战（10） | `queryCasusBelli` `declareWar` `makePeace` `trade` `signNonAggressionPact` `formAlliance` `offerVassalage` `breakTreaty` `releaseCaptives` `queryDiplomacyOverview` | DiplomacyAction、Relation、warWeariness、条约/交易/附庸 |
| 蛮族巢穴（3） | `clearLair` `queryClearBlocker` `queryLairInfo` | ThreatAction / WorldThreatService 巢穴 |
| 灾劫（1） | `resolveDisaster` | DisasterService（灵泉枯竭/灵脉震动/天罚雷劫/瘴气） |
| 威胁总览（1） | `queryThreatOverview` | 巢穴/灾异/民心/外交议程聚合（随上述模块一并去除） |
| 忠诚 / 叛乱（2） | `giftLoyalty` `queryLoyaltyGiftBlocker` | LoyaltyService 的赏赐与叛乱 |
| 随机事件（2） | `queryPendingEvent` `resolvePendingEvent`（含 `awaitInput kind=randomEvent`） | EventService 事件库与路途事件 |

> 裁剪后 2.0 保留 **69 条命令 + ping**（1.0 为 88 条）。机缘/秘境（`explore`）属于玩家主动探索，**保留**，不在"随机事件"范围内。

### 5.2 耦合点裁决（保证砍系统后规则不断裂）

1. **开战前置（最重要）**：1.0 攻击他宗要求双方为"战争状态"（需先宣战）。2.0 移除外交后采用 **【默认·待确认】**：各势力在"逐鹿天下"设定下**默认可直接攻击**任何非己方单位/节点/灵峰（攻击即交战，无宣战/议和/条约）。移动高亮与过境规则随之简化：删除基于"和平/互不侵犯/同盟/附庸"的通行分支，只区分**己方 / 敌方 / 无主**；敌占格按战斗与占领规则处理。
2. **厌战**：删除 `warWeariness` 字段与所有 `addWeariness` 调用（伤亡、失地、失峰、交战回合均不再累积）。
3. **城市安定**：保留 `stability` 作为基础内政属性（影响人口/产出，见 4.7）；删除"安定过低→叛乱/独立"的结算，删除"赏赐民心"。2.0 安定只由人口、住房、驻防、建筑（法坛/讲道）、政策（世家共治）等驱动，低值只给产出与增长惩罚。
4. **政令**：删除外交类政策卡（远交近攻）与所有厌战/外交效果；世家门阀的外交槽改为治理槽；切换政体的时代要求保留。
5. **蛮族 / 灾劫 / 随机事件**：世界中对手仅 3 家 AI + 玩家主动探索的节点；移除巢穴滋生/骚扰、瘴气占地、灵泉枯竭/灵脉震动/雷劫等随机打击与待决事件。
6. **AI**：移除性格、长期战略、外交议程；攻击决策不再检查"是否已宣战"，直接按战力对比与目标价值行动。
7. **awaitInput**：仅保留 `victoryChoice`（多胜利路线择一）；`resolveChoice` 统一入口只分派 `req_victory_*`。
8. **配置**：`gameConfig.json` 删/禁用对应块（见 `data/README.md`），ConfigValidator 启动时若仍引用已删字段即报错。

---

## 6. 接口契约（WebSocket + JSON）

> 沿用 1.0 成熟信封，仅把传输从 stdio 换成 WebSocket，并按第 5 章裁剪命令。

### 6.1 连接、握手与帧

- 传输：WebSocket 文本帧，UTF-8 JSON，**一条消息一个 JSON 对象**（紧凑、无裸换行）。
- 服务端启动后监听 `127.0.0.1:9527`（端口可用 `--port` 覆盖）；客户端连接后服务端第一帧推送：
  ```json
  {"type":"hello","protocolVersion":"2.0","backend":"xiuxian-godot-headless",
   "saveVersion":"3.0","implementedCommands":["newGame","..."]}
  ```
- 客户端应据 `implementedCommands` 把不支持的按钮置灰。
- 单会话顺序处理：一条命令处理完再处理下一条；事件顺序 == 服务端结算顺序。

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
- **业务失败不是协议失败**：玩法不允许（工力不足、不在射程、无法通行）一律 `ok:true + result.success:false + message`；只有参数缺字段/类型错/值非法才 `BAD_PARAMS`。
- **只读 `query*` 命令不回 `view`**（高频、不改状态）。

### 6.3 主动消息

- `hello`：握手（见 6.1）。
- `awaitInput`（2.0 仅胜利择一）：
  ```json
  {"type":"awaitInput","reqId":"req_victory_12","kind":"victoryChoice",
   "prompt":"择定结局","options":[{"index":0,"label":"…","routeId":"…","description":"…"}]}
  ```
  客户端回 `{"id":"c13","type":"resolveChoice","params":{"reqId":"req_victory_12","optionIndex":0}}`。
  只在新出现时推送一次；读档回到待决点时重新推送；越界回 `BAD_PARAMS` 且待决保留。
- `snapshot` / `event`：形状预留；首版沿用"每条写命令回包带全量 `view` + `events` 增量"。

### 6.4 错误码

| 码 | 含义 | 客户端应对 |
|---|---|---|
| BAD_JSON | JSON 非法 | 打日志（客户端 bug） |
| NO_ID / BAD_REQUEST | 缺 id / 缺 type | 打日志 |
| UNKNOWN_COMMAND | 命令名未登记 | 打日志（字段拼错） |
| NOT_IMPLEMENTED | 已登记但本版未实现 | 按钮置灰 |
| BAD_PARAMS | 参数缺失/类型错/值非法 | 弹提示 |
| NO_GAME | 未开局/未读档 | 先开局 |
| INTERNAL | 服务端异常 | 上报并附日志 |

### 6.5 view 全量快照（字段）

```
turn, phase, mapWidth, mapHeight, playerSectId, randomSeed, difficultyId,
gameOver, winType, winnerSectId, pendingVictoryChoices,
tiles{ tileId: HexTile }, nodes{ nodeId: GameNode }, improvements{ id: Improvement },
sects[ { …, disciples[ … ], spiritPeaks[ … ] } ],
eventLog[ ]
```
- 2.0 删除 1.0 快照中的 `relations`、`lairs`、`disasters`（外交/蛮族/灾劫）。
- 容器形状与实体一致：Map→JSON 对象，List→数组。
- 不下发内部记账字段：`tileSnapshots`、`policyCarry`、`lastPolicySwitchTurn`、`lastReproduceTurn` 等。

### 6.6 字段命名

- 字段小驼峰，与实体一致；枚举序列化为大写下划线字符串（`LIAN_QI`、`ZONG_MEN`、`PLAYER_ACTION`），GDScript 用同名比较。
- 布尔 getter 的 `is` 前缀剥离：`player / danger / capital / bloodLine`。
- `randomSeed` 按 64 位整数处理（GDScript 用 int，Godot 4 int 为 64 位）。

### 6.7 2.0 命令清单（69 条 + ping）

**会话（13）**：`newGame`、`getState`、`finishTurn`、`beginPlayerTurn`、`nextTurn`、`listSaves`、`saveGame`、`loadGame`、`queryVictoryProgress`、`checkVictory`、`checkDefeat`、`chooseVictory`、`queryGameOver`
- `newGame params`：`{playerFaction, sectName, mapWidth, mapHeight, randomSeed, difficultyId}`

**单位（22）**：`moveDisciple`、`queryMoveRange`、`batchMove`、`attack`、`queryAttackPreview`、`queryAttackable`、`retreat`、`teleport`、`queryTeleportOptions`、`assignGarrison`、`withdrawGarrison`、`reclass`、`promote`、`tribulate`、`rally`、`returnToDefense`、`foundSpiritPeak`、`appointBuilder`、`appointFengZhu`、`appointZhangLao`、`appointZongZhu`、`queryDiscipleDetail`

**城市/区域/改良（18）**：`constructBuilding`、`queryBuildOptions`、`holdRecruitment`、`researchDao`、`openCave`、`fortifyPeak`、`cancelProject`、`accelerateProject`、`queryProjectQueue`、`foundDistrict`、`queryDistrictSites`、`assignWorker`、`unassignWorker`、`queryAssignableTiles`、`queryCityDetail`、`buildImprovement`、`repairImprovement`、`queryImprovementOptions`

**探索（4）**：`queryJiYuanInfo`、`sendToJiYuan`、`queryMiJingInfo`、`exploreMiJing`

**政令（4）**：`switchGovernment`、`enactPolicy`、`revokePolicy`、`queryPolicyOptions`

**自动化/设置（6）**：`setAutomationToggle`、`setPeakAutoProject`、`setAllAutoProject`、`exploreNow`、`queryAutomationState`、`setSetting`（仅客户端本地，不回 view）

**待抉择（2）**：`queryVictoryChoice`、`resolveChoice`

> 各命令 `params` / `result` 形状沿用 1.0 `PROTOCOL.md §11`（迁移到 `docs/PROTOCOL_2.0.md` 时逐条落地），并删除其中与裁剪模块相关的字段（如 `queryThreatOverview`、`queryDiplomacyOverview` 等整条移除）。

---

## 7. 里程碑与任务拆分（纵向切片，每阶段端到端可玩、可验收）

> 原则：每个里程碑都是"服务端规则 + 协议命令 + 客户端对应界面"的可运行切片；每阶段都要跑无头自检并**提交推送**。

| 里程碑 | 服务端规则 | 协议命令 | 客户端 | 验收（关键） |
|---|---|---|---|---|
| **R0 工程骨架** | 两个 Godot 工程、shared 联接、WebSocket 互通、config 加载/校验、hello 握手、日志 | `ping` | 连接/握手/启动器拉起子进程 | 客户端连上 headless 服务端并显示 hello；`setup_shared` 可重复执行；无残留进程 |
| **R1 地图与开局** | 地图生成（种子确定）、实体初始化、三流派、出生点、view 快照、迷雾基础 | `newGame` `getState` | 主菜单/开局、六边形地图渲染、相机锁定 45°、三态迷雾 | 固定种子地图逐字一致；300 格/4 宗/初始资源与弟子数正确；不可旋转、缩放平移不重置 |
| **R2 回合/移动/视野** | 回合状态机（6 阶段骨架）、移动力/BFS、视野刷新 | `finishTurn` `nextTurn` `beginPlayerTurn` `moveDisciple` `queryMoveRange` | 点选/移动/高亮/范围预览/TopBar 回合 | 高亮即可达；移动扣力与预览一致；迷雾随移动更新；回合推进正确 |
| **R3 经济与城市** | 经济结算、人口/住房/安定、灵峰、建筑、区域、劳力、改良、道路 | 城市 18 条命令 | 城市面板/建造/区域选址/劳力指派/改良、资源栏 | 产出与维护数值与 config 一致；区域邻接与上限生效；安定低值惩罚生效 |
| **R4 道统与修炼** | 修炼/突破、道统树/道点/顿悟、项目队列、收徒 | `researchDao` `holdRecruitment` `queryProjectQueue` `cancelProject` `accelerateProject` | 道统树面板、研究队列、弟子详情 | 23 道法前置/时代门控正确；进度上限/突破概率正确；顿悟概率可复现 |
| **R5 兵种与战斗** | 十兵种、转职/晋升、战力/胜率/相克/地形/城防、野战/夺峰/夺点、撤退、传送、驻守 | 单位 22 条（战斗相关） | 攻击预览/攻击范围/战斗动画/伤亡反馈/转职晋升面板 | 预览胜率==实战口径；夺峰/夺点易主与视野重算；远程零反击；ZOC/围城生效 |
| **R6 探索/政令/自动化** | 机缘/秘境、政令（裁剪）、自动化、集结/回防 | 探索 4 + 政令 4 + 自动化 6 | 探索面板、政令面板、自动化开关 | 成功率/冷却/伤亡与 config 一致；政策槽位与冷却正确；自动化按阈值触发 |
| **R7 任命/渡劫/AI/胜负/存档** | 任命、渡劫飞升、基础 AI、胜负判定、分数、存档（含自动存） | 会话剩余命令、`tribulate`/任命、`saveGame/loadGame/listSaves`、胜利待择 | 胜利进度/结局覆盖层/存档界面/AI 行动回放 | 三流派胜利可达成；240 回合分数正确；同种子双跑逐字一致；读档继续与待决重建 |
| **R8 表现与 UI 打磨** | —（仅协议补字段） | — | 正式 HUD、全面板、框选、动画、音效、小地图、设置、引导 | 全部 69 命令有对应 UI 入口；信息直观（解决 1.0 视角/缩放重置、UI 不直观问题） |
| **R9 美术皮肤化/平衡/导出** | 数值平衡微调（不改架构） | — | 皮肤包切换、默认皮肤成品、Win 导出与打包 | 换皮肤零代码；默认皮肤完整；导出可独立运行；自检全绿 |

---

## 8. 工程与 Git 规范

### 8.1 仓库与提交

- 远程：`https://github.com/chufu152/xiuxiangame2.0.git`，主分支 `main`。
- **每个任务/里程碑完成并通过自检后立即提交并推送**：
  ```
  git add -A
  git commit -m "feat(r5-combat): 实现十兵种战力与胜率结算"
  git push
  ```
- 约定式提交：`feat / fix / docs / refactor / test / perf / chore`，建议带模块范围（如 `feat(r3-city)`、`fix(net)`）。
- 个人项目可直接小步提交 `main`；里程碑较大时可用 `feature/rX-xxx` 分支再合并。
- 代理仅对单条命令临时生效：`git -c http.proxy=http://127.0.0.1:7890 -c https.proxy=http://127.0.0.1:7890 push`，不写全局。

### 8.2 GDScript 规范

- 全部静态类型：`var x: int = 0`、`func f(a: String) -> Dictionary:`；常量 `const`；避免无类型 `Variant` 滥用。
- 规则层（`server/scripts/rules`）与节点解耦：不继承 Node2D/Node3D，不调用渲染/音频；便于无头测试。
- 枚举统一引用 `shared/protocol/enums.gd`；命令名引用 `commands.gd`，禁止散落字符串字面量。
- 不硬编码数值：一律从 `data/gameConfig.json` 读。

### 8.3 自检（`tools/check.ps1`）

- 启动服务端 headless，固定种子跑 N 回合（如 30/60），导出事件流。
- 断言：地图/资源/阶段/胜负、移动范围、战斗预览==实战、关键经济产出。
- 确定性：同种子跑两遍逐字一致。
- 配置校验：缺字段/非法枚举/引用已删模块即失败。
- 结束后**无残留 godot 进程**（对应 1.0 "无残留 java 进程"的验收口径）。

### 8.4 客户端 UI 硬性要求（针对 1.0 反馈）

- 相机锁定 45° 正交 2.5D；**执行任何操作后相机角度与缩放不得被重置**（1.0 痛点）。
- 所有命令都有可见入口，不可用按钮置灰并提示原因；悬停/预览信息直观（移动范围、攻击胜率、造价、收益）。
- 镜头控制：左键选择/框选、滚轮缩放（以鼠标为中心）、中键/右键拖拽平移、键盘快捷键；空格/End 结束回合。
- 面板：顶部资源栏、底部操作栏、左侧城市/弟子、右侧势力/胜利；Toast 显示事件与业务失败文案。

---

## 9. 完成定义（Definition of Done）

一个里程碑只有满足以下全部条件才算完成：

1. 服务端规则与 `data/gameConfig.json` 数值一致，关键公式有断言。
2. 对应命令在 `implementedCommands` 内，`ping`/握手/错误码/业务失败口径正确。
3. 客户端有对应 UI 入口，操作后相机角度/缩放保持，信息直观。
4. 固定种子整段可复现（双跑逐字一致）；新增随机序列号已登记复位。
5. 缺失美术资源有占位且不崩溃；美术仅经逻辑 ID 引用。
6. `tools/check.ps1` 全绿；无残留 godot 进程；无客户端规则实现。
7. 已 `git commit` 并 `git push` 到 `main`，提交信息符合约定。

---

## 10. 开放决策点（评审时确认）

| # | 决策点 | 推荐默认 | 不选默认的影响 |
|---|---|---|---|
| 1 | 语言 | GDScript 静态类型 | 改 C# 需两端换 .NET 版、工具链与 CI 调整 |
| 2 | 通信 | WebSocket | 选 stdio 不利未来联机；选 ENet 需自行处理可靠/重连 |
| 3 | 首版是否真联机 | 否，仅本地回环 + 架构预留 | 若做需增加房间/多人权威/断线重连，工作量显著增加 |
| 4 | 被砍外交后的开战规则 | 默认可自由攻击（逐鹿设定） | 若保留"需先开战"，需引入一个最小"宣战"动作（无条约/交易） |
| 5 | 灾劫是否与随机事件一并排除 | 一并排除（默认） | 若保留需恢复 DisasterService 与相关待决/配置 |
| 6 | 安定去叛乱后的结算 | 仅产出/人口惩罚，不独立 | 若要叛乱需保留 LoyaltyService 与"赏赐民心" |

---

## 附录 A：数值与配置索引

完整数值以 `data/gameConfig.json` 为准（R1 从 1.0 迁移并按第 5 章裁剪）。配置块索引：`map / terrain / disciple / faction / city（含 buildings/peak/district/population/stability/cave）/ improvement / economy / dao / explore / warfare（含 combat/unitClasses/counters/promotions/reclass）/ policy / automation / vision / victory / difficulty`。

## 附录 B：术语表

- 灵峰 SpiritPeak：宗门的城市/据点；主峰为首都。
- 弟子 Disciple：单位/人口，兼具修炼者与兵种身份。
- 节点 GameNode：3 格资源点/探索点。
- 区域 District：城市内独立占地的功能分区。
- 道统 Dao：科技树道法；顿悟 Insight 为突破时的随机强化。
- 气运 QiYun：扩张/开峰容量资源；心魔 HeartDevil：弟子风险值。
- 势力等级 powerLevel：由声望折算（每 100 声望 1 级）的综合实力分。
