# 《修仙4X·宗门争霸》2.0 —— 后续目标与推进计划（ROADMAP）

> 本文是**执行层路线图**，回答三个问题：**现在到哪了 → 接下来做什么 → 每一步怎么算做完**。
> 权威需求见 [`REQUIREMENTS_2.0.md`](REQUIREMENTS_2.0.md)（§5 裁剪、§6 契约、§7 里程碑、§9 DoD）；
> 命令契约见 [`PROTOCOL_2.0.md`](PROTOCOL_2.0.md)；
> **本文不新增任何规则与数值**，只做进度定位、依赖排序、前置检查与风险登记。

---

## 一、现状盘点

### 1.1 总体位置

```
R0 ✅   ┃ R1 ✅   ┃ R1.5 ✅ ┃ R2 ✅   ┃ R3 ✅ ← 当前位置 ┃ R4 · R5 · R6 · R7 · R8 · R9
骨架完成 ┃ 地图开局 ┃ R2 前置修复 ┃ 回合/移动/视野 ┃ 经济与城市 ┃ 全部未开始
```

**当前位置：R3「经济与城市」已完成 → 下一个里程碑 R4「道统与修炼」。**

- 分支：`main`（WorkBuddy 在独立 worktree 工作，分支 `workbuddy/main-*`，统一推 `HEAD:main`）。
- 里程碑提交：
  - R0 `d4c5bf7 feat(r0): godot dual-project scaffold and websocket handshake`
  - R1 `9754360 feat(r1): layered terrain generation, newgame view, 2.5d locked camera and fog`
  - R1 收尾 `fac1593 fix(check): tolerate sandbox-blocked probe cleanup`
  - R1.5 提示词 `3e49c09 docs(r1.5): add pre-r2 fix prompt (worktree mount, protocol contract, art schedule)`
  - R1.5 `8c622b5 docs(r1.5): add protocol_2.0 contract, mount shared in worktree, schedule placeholder art`
  - R2 提示词 `d38e1fa docs(r2): add R2 prompt for turn state machine, BFS movement, vision on move`
  - R2 `6c5a232 feat(r2): turn state machine, terrain-aware BFS movement, vision on move`
  - R2 收尾 `edf8656 docs(r2): record delivered r2 commit hash in roadmap`
  - R3 提示词 `468fea2 docs(r3): add R3 milestone prompt`
  - R3 前置修复 `b0a9e41 fix(config): correct dangling improvement requiredDaoKey (lingtian_ti -> ling_tian_nong)`
  - R3 `feat(r3): economy settlement, spirit peak city, buildings districts workers improvements roads`（见 §4.1）

### 1.2 已交付并验证的资产

| 层 | 文件 | 状态 |
|---|---|---|
| 共享协议 | `shared/protocol/{commands,msg,dto,enums}.gd` | ✅ `msg`（版本 2.0/存档 3.0/端口 9527/8 个错误码/16 MiB 帧缓冲）、`commands`（**R3 起 23 条**：R2 的 8 条 + R3 城市/改良 15 条）、`enums`（地形/节点/流派/境界/兵种/建筑/区域/改良/资源/阶段全量；**R3 新增 `Building`（10 种 + `ALL`/`NAMES`/`CORE`）、`DistrictType`（首府区 + 5 可建 + `ALL`/`NAMES`/`BUILDABLE`）、`ImprovementType`（8 种 `ALL`）**）、`dto`（信封解析与构造） |
| 共享几何 | `shared/geo/hex.gd` | ✅ 7 个静态函数（`id/coords/neighbors/distance/to_world/opposite/edge_vertices`）已按 R1 契约补齐，两端共用 |
| 服务端·网络 | `net/{NetServer,CommandDispatcher,StateView}.gd` | ✅ 监听 9527、hello 握手、**R3 起 23 条命令**、错误码口径、`view` 全量快照 + 迷雾快照；**R3 新增**：`view.improvements{}` 按 `Sect.improvementSnapshots` 做迷雾「最后可见」缓存下发 |
| 服务端·规则 | `rules/{MapGenerator,SetupInitializer,VisionCalculator,MoveRules,MoveRangeCalculator,MoveAction,TurnProcessor}.gd`、`rng/RngService.gd` | ✅ 分层地形生成（基底/海拔/地貌/河流/险地/节点/奢侈，种子确定）、四宗初始化、视野计算、移动力公式/可通行/跨河/进入代价叠加、BFS 可达（与 `queryMoveRange` 同算法）、移动命令、六阶段回合状态机；**R3 新增**：`EconomyRules`（地块/灵峰产出、维护、安定、产出系数、粮食、`apply_settlement` 唯一入口、气运满溢吞并与灵峰晋升）、`CityRules`（工作半径/指派/住房/容量/区域产出与邻接/建城与建筑可建判定）、`ImprovementRules`（地形与道法/区域/节点门控、产出、洞府住房、道路机动、掠夺、修缮）、`RoadNetworkService`（路网连通度/减耗/起始格加成）、`CityAction`（开峰/建筑/洞府/加固/区域/劳力/项目队列推进/只读查询）、`ImprovementAction`（任命建造者/修筑/修缮/查询）；**R3 回填 R2 空钩子**：`MoveRules.step_cost` 与 `calculate_max_move_points` 改调 `RoadNetworkService`，`TurnProcessor` 的 `TURN_START` 调 `RoadNetworkService.refresh()`、`SPIRIT_PEAK` 推项目队列、`SETTLEMENT` 调 `EconomyRules.apply_settlement()` |
| 服务端·模型 | `model/{HexTile,GameNode,Sect,Disciple,SpiritPeak,GameState}.gd` | ✅ 纯数据 + `to_dict()`；**R2 起 `Disciple` 含 `maxMovePoints`/`turnsInSect`**；**R3 新增 `Project`/`District`/`Improvement`**，`SpiritPeak` 增 `food`/`foodProgress`/`freeWorkers`/`workedTileIds`/`projectQueue`、`Sect` 增 `improvements`/`improvementSnapshots`、`Disciple` 增 `builderCharges`、`GameState` 增 `projectSeq`/`improvementSeq` |
| 服务端·配置 | `config/{ConfigLoader,ConfigValidator}.gd` | ✅ 加载 + 校验，缺字段/引用已删模块即非零退出；**R2 起 `map.dangerTileMoveCost = 1`**（险地附加，裁决二）；**R3 未新增顶层块**（`spiritPeak`/`economy`/`building`/`city`/`improvement`/`road`/`resources` 均复用） |
| 客户端·表现 | `world/{HexMap,Fog,CameraRig,UnitView,SectView}.gd`、`scenes/{Main,MainMenu,World}`、`art/AssetLibrary.gd` | ✅ 起伏六棱柱 + 连绵山体 + 河流贴边、三态迷雾静态材质、正交 45° 锁定相机、占位回退；**R2 新增**：移动高亮层、选中标记、顶部 TopBar、点选→高亮→移动交互；**R3 新增**：`CityPanel`（CanvasLayer，人口/粮食/安定/住房/工作格/区域/产出明细 + 建造/区域选址/劳力指派/改良按钮）、`SectView` 灵峰/建筑/区域占位几何、TopBar 资源栏追加 粮/气运/道点/材料 |
| 客户端·网络 | `net/{NetClient,Launcher,Session}.gd` | ✅ 自动连接、hello 展示、子进程拉起与回收；**R2 起**：拉起后 0.5s 轮询等待就绪（40s 超时）、`moveRange`/`moveResult` 信号、`requestEndTurnSequence`；**R3 新增**：15 条 `request_*` 包装 + 6 个信号（`buildOptions`/`districtSites`/`assignableTiles`/`cityDetail`/`improvementOptions`/`r3Result`） |
| 配置 | `data/gameConfig.json` | ✅ 2144 行，26 个顶层块；2.0 地形块（`baseTerrains`/`relief`/`features`/`river`/`nodeSpawnByTerrain`）已落地；6 个裁剪块确认不存在；**R3 只读复用** `spiritPeak`/`economy`/`building`/`city`/`improvement`/`road`/`resources`/`qiYun` |
| 协议契约 | `docs/PROTOCOL_2.0.md` + `tools/check_protocol.ps1` | ✅ 69 条 + `ping` 全覆盖，分组 13/22/18/4/4/6/2；**R3 起 23 条标「已实现」**；`TODO(需核对)` 由 8 处增至 **11 处**（R3 新增 3 处缺口登记，见 §4.1）；校验脚本 35/35 全绿 |
| 工具 | `tools/{setup_shared,run_dev,check}.ps1`、`tools/check_protocol.ps1` | ✅ `check.ps1` 已扩为 **15 阶段**（`[0/14]`–`[14/14]`），含 R0/R1/R2/R3 全量断言 + 协议契约校验（81/81 全绿） |

### 1.3 遗留缺口（进入 R4 前需知悉，不阻塞 R4）

1. **美术资源实体文件为 0**（`assets/` 下除 `manifest.json` 外无实体文件）。**这是计划内状态**，不是缺陷：
   - `AssetLibrary` 对 manifest 里 60+ 逻辑 ID 缺失时**全部回退占位**（模型=水墨灰阶几何体 + 文字标签、贴图=纯色块、材质=`StandardMaterial3D`、字体=回退字体），**不崩**。
   - 该行为已有测试覆盖：`client/tests/R1ClientTest.gd` L84–96 断言「模型缺失回退灰阶几何与文字」「同一缺失 logicalID 只 WARN 一次」「缺失贴图回退纯色块」「缺失材质安全回退」「无效文本字体安全回退」「F5 热重读 manifest 并使缓存失效」，并由 `check.ps1` `[9/14]` 断言 `同一缺失 logicalID 只 WARN 一次`。
   - R3 的灵峰/建筑/区域同样只走 `SectView` 占位几何（`DISTRICT_COLORS` 色块 + `Label3D` 文字 + 堆叠方块），未引入真资产。
   - 真资源排期见 §三「最小水墨资源包」前置约束。
2. **协议契约仍有 11 处 `TODO(需核对)`**（`PROTOCOL_2.0.md` §11.2；R2 时 8 处 → R3 增 3 处）：`TrainingResult`/`AppointmentResult`/`ExploreResult`/`PolicyResult`/`NodeInfo` 等实体形状 1.0 未展开；`querySpiritPeakBlocker` 未在 69 条清单内；R3 新增：`city` 配置缺「丘陵石+1 / 河流 foodBonus」权威键、`ImprovementRules.apply_pillage()` 的接线点（R2 移动 / R5 攻击）、敌方可见弟子的 `assignedPeakId` 未剥离。**不阻塞 R4**，随对应里程碑逐条补齐。
3. **R4–R9 提示词已全部预生成**（草案）；`R4_道统与修炼.md` 起进入前须按当时最新代码/config 重新核对文件锚点与数值。

### 1.4 前置条件核验（全部就绪 ✅）

| 依赖 | 检查结果 |
|---|---|
| Godot 4.4.1 stable | ✅ `C:\Users\Administrator\godot\Godot_v4.4.1-stable_win64{,_console}.exe` 均在 |
| 1.0 迁移源（配置/协议） | ✅ `IdeaProjects\xiuxianGame\src\main\{resources\gameConfig.json, java\com\xiuxiangame\bridge\{PROTOCOL,COMMAND_MAP}.md}` |
| 远程仓库 | ✅ `origin` = `https://github.com/chufu152/xiuxiangame2.0.git`（HTTPS + 本机代理 127.0.0.1:7890 + Windows 凭据管理器） |
| 共享目录联接 | ✅ `tools/setup_shared.ps1` 幂等；**每个新 worktree 都需挂一次**（本任务已在当前 worktree 挂载并验证双向可见） |

---

## 二、目标拆解：R2–R9 里程碑

> 每一阶段都是**纵向切片**：服务端规则 + 协议命令 + 客户端界面，端到端可跑、可验收、可推送。
> 命令归属的完整清单见 [`PROTOCOL_2.0.md`](PROTOCOL_2.0.md) §1。

| 里程碑 | 目标（一句话） | 服务端核心 | 客户端核心 | 主要命令 |
|---|---|---|---|---|
| **R2 回合/移动/视野** | 能结束回合、点选移动弟子 | 6 阶段状态机、地形移动力叠加/BFS、视野（丘陵 +1） | 点选/移动/高亮/范围预览/TopBar | `finishTurn` `nextTurn` `beginPlayerTurn` `moveDisciple` `queryMoveRange` |
| **R3 经济与城市** | 能建城、造建筑、派劳力 | 经济结算、地形产出、人口/住房/安定、灵峰、建筑、区域邻接、劳力、改良、道路 | 城市面板、建造/区域选址、劳力指派、改良、资源栏 | 城市 13 条 + `foundSpiritPeak` `appointBuilder` |
| **R4 道统与修炼** | 能点道统树、弟子突破 | 修炼/突破/渡劫、21 道法树/道点/成就 boost、项目队列、收徒 | 道统树、研究队列、弟子详情 | `researchDao` `holdRecruitment` `queryProjectQueue` `cancelProject` `accelerateProject` |
| **R5 兵种与战斗** | 能打一场可预览胜率的仗 | 十兵种、转职/晋升、战力/胜率/相克、丘陵高地/跨河/地貌防御/城防、野战/夺峰/夺点、撤退、传送、驻守 | 攻击预览/范围、战斗动画、伤亡反馈、转职晋升 | 单位 12 条（战斗相关） |
| **R6 探索/政令/自动化** | 能探机缘秘境、发政令、开自动化 | 机缘/秘境、8 政令卡 3 政体、自动化阈值、集结/回防 | 探索/政令/自动化面板 | 探索 4 + 政令 4 + 自动化 6 + `rally` `returnToDefense` |
| **R7 任命/渡劫/AI/胜负/存档** | 能打到结局、能存读档 | 任命、血脉、渡劫飞升、反应式 AI、三流派胜负、分数、存档 | 胜利进度/结局屏、存档菜单、AI 回放 | 会话剩余 8 + `tribulate` + 任命 4 + 待抉择 2 |
| **R8 表现与 UI 打磨** | 69 命令全有 UI 入口、体验成型 | 仅协议补字段 | 正式 HUD/面板、框选、泼墨转场、昼夜粒子、小地图、设置、引导 | — |
| **R9 皮肤化/平衡/导出** | 换皮零代码、导出可独立运行 | 数值平衡微调（不改架构） | 皮肤切换、默认水墨皮肤、Win 导出 | — |

**完成定义（每个里程碑都要满足，PRD §9）**：数值与配置一致 → 命令进 `implementedCommands` → 客户端有 UI 入口且相机不重置 → 固定种子双跑逐字一致 → 缺失资源有占位不崩 → `check.ps1` 全绿且无残留进程 → 已 commit + push。

---

## 三、依赖、关键路径与前置约束

### 3.1 主干串行

- **主干串行**：R2 → R3 → R4 → R5 → R6 → R7 → R8 → R9。
  串行原因：每个里程碑都在扩展同一套 `GameState` / `view` 快照 / 协议命令，前置未定型时后置会大面积返工。
- **R8/R9 是收口**：不做新规则，只做表现与打包，可在 R7 验收通过后连续推进。
- **可穿插的低风险补强**（不改变主线顺序）：
  - 补齐 `PROTOCOL_2.0.md` 的 11 处 `TODO(需核对)`：随对应里程碑（R4/R5/R6）落地时一并回填，不必单独立项。
  - 生成 R4–R9 提示词：严格「进入该里程碑时再生成」，保持与当时代码一致（R4–R9 草案已预生成，进入前须重新核对锚点）。

### 3.2 ★ 前置约束：R8 开工前必须先交付「最小水墨资源包」

> **本条目是硬约束，登记于此以防被跳过。本任务不制作任何真实美术资源。**

- **背景**：R1–R7 一律使用 `AssetLibrary` 的占位回退（缺失即 WARN + 程序化几何体，不崩）——这是**计划内**的，占位不阻塞任何玩法里程碑。
  但 R8「表现与 UI 打磨」的目标（轮廓描边、昼夜/草木飞鸟/灵气粒子、泼墨迷雾转场、小地图、设施可辨性）**依赖真实资产**；没有真资产，R8 无物可打磨。
- **约束**：**R8「表现与 UI 打磨」开工前，必须先交付一个「最小水墨资源包」**，作为 R9 默认皮肤的前置子集，至少覆盖：
  1. **3 基底**地形顶面材质（`terrain.base.LING_FIELDS` / `SPIRIT_PLAIN` / `BARREN`）
  2. **3 海拔**（`terrain.relief.{FLAT,HILL,MOUNTAIN}_SIDE` + `MOUNTAIN_TOP`，含**连绵山体**）
  3. **河流**（`terrain.river`）
  4. **险地**（`terrain.danger`）
  5. **三态迷雾材质**（`terrain.fog.RICE_PAPER` / `INK_MAP`，加实景态）
  6. **10 单位**模型（`unit.PU_TONG` … `unit.JI_GUAN_JUN_TUAN`）
  7. **10 建筑**模型（`building.SHAN_MEN` … `building.WANG_CHAO_DI_DU`）
  8. **主要 UI 图标**（`resource.*` 13 项 + `realm.*` 5 项 + `faction.*` 3 项）
- **排期**：该资源包的具体制作在 **R7 完成后、R8 启动前单独立项**（含美术风格与工作量评估），**不属于任何现有里程碑**，也不在 R1.5 范围内。
- **验收方式**：替换 `assets/art/default/` 下实体文件后，`activePack=default` 下 `AssetLibrary` 不再对上述 ID 触发 WARN；R8 打磨项基于真资产进行。

---

## 四、R3 交付纪要 与 下一步（R4）

> R3 已于本里程碑完成并提交推送（见 §一 提交列表）。以下为**实际交付**与**R4 启动清单**。

### 4.1 R3 实际交付（与本清单原始计划的偏差）

- **服务端新增文件**：`rules/{EconomyRules,CityRules,ImprovementRules,RoadNetworkService,CityAction,ImprovementAction}.gd`、`model/{Project,District,Improvement}.gd`、`tests/{R3Test.gd,R3Test.tscn}`。
- **服务端修改文件**：`model/{SpiritPeak,Sect,Disciple,GameState}.gd`（新增字段 + `to_dict`）、`net/{CommandDispatcher,StateView}.gd`（15 handler + `view.improvements{}` 迷雾缓存）、`rules/{MoveRules,MoveRangeCalculator,TurnProcessor,SetupInitializer}.gd`（道路回填 + 三阶段 R3 实做）、`config/ConfigValidator.gd`、`shared/protocol/{commands,enums}.gd`。
- **15 条命令**（**偏差：不是清单里写的 18 条**——`PROTOCOL_2.0.md` §4 分组的 18 条含 `researchDao`/`holdRecruitment`/`queryProjectQueue` 等 R4 命令，R3 实际归属为 15 条，见 `R3_经济与城市.md` 范围段）：`foundSpiritPeak`/`appointBuilder`（单位组）+ `constructBuilding`/`queryBuildOptions`/`openCave`/`fortifyPeak`/`foundDistrict`/`queryDistrictSites`/`assignWorker`/`unassignWorker`/`queryAssignableTiles`/`queryCityDetail`/`buildImprovement`/`repairImprovement`/`queryImprovementOptions`（城市组）。`hello.implementedCommands` 累计 **23 条**。
- **回合阶段**：`TURN_START` 增 `RoadNetworkService.refresh()`；`SPIRIT_PEAK` 实做项目队列推进（`Project.turnsRemaining -= 1` → 归零结算落成：开峰/建筑/洞府/加固/区域）；`SETTLEMENT` 调 `EconomyRules.apply_settlement()`（节点冷却 → 人口/住房/安定 → 经济结算 → 气运满溢扩张）。仍留空：`# TODO(R4)` 研究队列/道统 boost/心魔、`# TODO(R5)` 围城断供、`# TODO(R6)` 政令、`# TODO(R7)` AI 行动/胜负判定。
- **★ R3 回填（计划外但必需）**：开局每宗只占主峰一格（`SetupInitializer` 仅设 `spawnTiles[index].ownerSectId`），而 `foundDistrict`/`assignWorker`/`buildImprovement` 都要求 `tile.ownerSectId == sect.id` —— 没有领土增长机制时 R3 核心循环**不可玩**。已按 1.0 蓝本 `EconomyCalculator.annexAdjacentTile` / `developPeak` 忠实回填：气运攒满 `qiYunMax` 时优先吞并带资源节点的相邻无主地块，无处可吞则灵峰晋升（`capacity += capacityPerLevel`、`defense += baseDefense/2`）。这是 1.0 唯一非战斗领土增长途径（战斗 R5、外交 R7）。登记于 `docs/PROTOCOL_2.0.md` §11.1。
- **客户端**：`World` 增 `CityPanel`（CanvasLayer，layer 3）+ 城市模式（区域选址 / 劳力指派高亮候选格）+ R3 信号处理；`Session` 增 15 条 `request_*` + 6 个信号；`SectView` 增区域/建筑占位几何；TopBar 资源栏追加 粮/气运/道点/天晶/玄铁/灵木。**客户端零规则**：产出/造价/人口/安定/可建性全部来自 `query*` 回包。
- **偏差/修复（客户端两处）**：① `_on_r3_result_received` 原先把只读 `query*` 回包（不带 `success`）误判为「操作失败」，已改为只接管写命令；② `select_peak` 原先连发 `queryCityDetail` + `queryBuildOptions`，而 `Session._request` 是单请求串行语义（`busy` 期间静默丢弃），已改为「详情回包后链式拉取可构建清单」。
- **协议契约**：`PROTOCOL_2.0.md` 15 条 `待实现（R3）`→`已实现（R3）`；§11.1 增 5 行冲突裁决（`Enums.Improvement`/`Enums.District` 重命名、`Improvement.networkLevel`、`queryCityDetail.districts[].buildings` 为字符串数组、道法门控在 R3 不可建）；§11.2 增 3 处缺口；§12.1/§12.4/§12.5 同步 `view` 字段。`TODO(需核对)` 8 → 11 处（脚本只统计不断言）。
- **验收**：服务端 `R3_PASS checks=268`；客户端无头 `R3_CLIENT_RESULT=OK checks=5`、端到端 `R3_CLIENT_RESULT=OK checks=43`；`check.ps1` **15 阶段 81/81 全绿**；`check_protocol.ps1` 35/35（69 条分组点数 13/22/18/4/4/6/2 不变、23 条已实现）；无残留 godot 进程、无 `.java`。

### 4.2 下一步 · R4「道统与修炼」启动清单

**Step 0 · 核对 R4 提示词**
- 按当时最新代码/config 重新核对 `docs/prompts/R4_道统与修炼.md` 的文件锚点与数值（`data/gameConfig.json` 的 `daoTree` / `cultivation` / `breakthrough` / `recruit` 等块）。

**Step 1 · 服务端规则**
- 修炼/突破/渡劫、21 道法树/道点/成就 boost、`SPIRIT_PEAK` 的研究队列推进（替换 R3 的 `# TODO(R4)`）、`SETTLEMENT` 的道统 boost 与心魔结算（替换 R3 的 `# TODO(R4)`）、收徒。
- **回填 R3 遗留**：`ImprovementRules._has_unlocked_dao()` 当前恒 `false`（R3 无道统系统），R4 接入已解锁道法集合后应改为真实判定，使 `LING_TIAN_TI_TIAN`（需 `ling_tian_nong`）与 `JU_LING_ZHEN`（需 `ju_ling_zhen`）真正可建。

**Step 2 · 协议命令**
- `researchDao` / `holdRecruitment` / `queryProjectQueue` / `cancelProject` / `accelerateProject`；在 `commands.gd` 登记并在 `CommandDispatcher` 注册。

**Step 3 · 客户端表现**
- 道统树面板、研究队列、弟子详情（境界/灵根/进度）。

**Step 4 · 验收与提交**
- 扩展 `tools/check.ps1`：21 道法前置/时代/流派门控、进度/突破/渡劫、成就 boost 触发。
- 全绿后：`git add -A && git commit -m "feat(r4): ..." && git push origin HEAD:main`。

---

## 五、风险登记表

| # | 风险 | 影响 | 缓解措施 |
|---|---|---|---|
| 1 | 1.0 配置迁移遗漏/误改 | 数值全线漂移 | `ConfigValidator` 强制校验；`saveVersion=3.0` 锁定；已确认 6 个裁剪块不存在 |
| 2 | 随机源分散导致不确定性 | 违反「同种子双跑逐字一致」硬约束 | 只经 `RngService`，禁止各处 `RandomNumberGenerator.new()`；`check.ps1` 双跑 SHA256 断言 |
| 3 | 服务端/客户端几何口径漂移 | 单位位置错位、移动范围与渲染不符 | 换算只在 `shared/geo/hex.gd`，两端共用 |
| 4 | 相机在操作/刷新后被重置（1.0 老问题） | 直接违反 PRD §8.4 | `CameraRig` 自持 transform/size；已有 `check.ps1` 断言「view 刷新保持相机」 |
| 5 | **R8 无真实资产可打磨** | R8 打磨项落空、被迫返工 | **§3.2 前置约束**：R7 完成后、R8 启动前先交付「最小水墨资源包」 |
| 6 | **协议契约存在未核对字段** | 相关里程碑（R4/R5/R6）落地时字段口径分歧 | `PROTOCOL_2.0.md` §11 已逐条登记 11 处 `TODO(需核对)` 与 18 处冲突裁决；随里程碑回填，`check_protocol.ps1` 持续统计 |
| 7 | **新 worktree 未挂载 `shared/` 联接** | 全线 `class_name not declared` | 每个新 worktree 首次开工先跑 `tools/setup_shared.ps1`；`check.ps1` `[1/14]` 已断言 |
| 8 | Windows 环境坑（import / Start-Process / 控制台编码 / BOM） | 脚本挂死或中文乱码 | 已实证并写入 `docs/prompts/README.md` §5；含中文 `.ps1` 必须带 UTF-8 BOM |
| 9 | 里程碑提示词滞后于代码 | 派发指令与实现不符 | 严格「进入该里程碑时再生成」；每步结束更新 `prompts/README.md` 进度 |
| 10 | 客户端越界实现规则 | 破坏「服务端权威」架构 | 客户端只读 `view`；「能不能做/花多少」一律走 `query*` |

---

## 六、流程保障（每个里程碑固定动作）

1. **派发**：把对应 `docs/prompts/R*_*.md` 全文交给 Godot 游戏脚本工程师，要求先只读引用文档。
2. **执行**：服务端权威优先，客户端只表现；全程静态类型 GDScript，零 Java。
3. **自检**：`tools/check.ps1` 全绿（含协议契约阶段）+ 无残留 godot 进程 + GUI 人工核验项通过。
4. **提交**：约定式英文提交信息，`git push origin HEAD:main`（HTTPS + 本机代理）。
5. **收尾**：更新 `docs/prompts/README.md` 进度标记与本文 §1；把本里程碑产出追加到 `.workbuddy-ai/memory/YYYY-MM-DD.md`。
6. **放行**：上一里程碑未全绿，**不派发下一个**。

---

## 七、附：里程碑验收速查

| 里程碑 | 一句话验收 |
|---|---|
| R0 | 客户端连上 headless 并显示 hello；`setup_shared` 可重复执行；无残留进程 |
| R1 | 固定种子地图逐字一致；山岳连绵、河流成对；4 宗资源正确；相机锁 45° 不可旋转、缩放平移不重置；三态迷雾与服务端集合一致 |
| R1.5 | `shared` 联接挂载且双向可见；`PROTOCOL_2.0.md` 覆盖 69 条 + `ping`（分组 13/22/18/4/4/6/2）；裁剪 19 条只在 §10；`check.ps1` 全绿 |
| R2 | 高亮即可达；山岳不可达；丘陵/灵林/雾泽/跨河扣力与预览一致；迷雾随移动更新 |
| R3 | 产出与 config 一致；山岳不可建城、丘陵/灵林限制生效；区域邻接与上限生效；安定惩罚生效 |
| R4 | 21 道法前置/时代/流派门控正确；进度/突破/渡劫正确；成就 boost 触发正确 |
| R5 | 预览胜率 == 实战口径；高地/跨河/丘陵/灵林加成正确；夺峰夺点易主与视野重算；远程零反击 |
| R6 | 成功率/冷却/伤亡与 config 一致；政令槽位/冷却 8 正确；loyalty 效果落安定；自动化按阈值触发 |
| R7 | 三流派胜利可达成；240 回合分数正确；同种子双跑逐字一致；读档继续与待决重建 |
| R8 | 69 命令全有 UI 入口；视角/缩放操作后不重置；全局缩到最远设施仍可辨（**前置：最小水墨资源包已交付**） |
| R9 | 换皮肤零代码；默认水墨皮肤完整；导出可独立运行；自检全绿 |
