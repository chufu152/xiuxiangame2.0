# 《修仙4X·宗门争霸》2.0 —— 后续目标与推进计划（ROADMAP）

> 本文是**执行层路线图**，回答三个问题：**现在到哪了 → 接下来做什么 → 每一步怎么算做完**。
> 权威需求见 [`REQUIREMENTS_2.0.md`](REQUIREMENTS_2.0.md)（§5 裁剪、§6 契约、§7 里程碑、§9 DoD）；
> 命令契约见 [`PROTOCOL_2.0.md`](PROTOCOL_2.0.md)；
> **本文不新增任何规则与数值**，只做进度定位、依赖排序、前置检查与风险登记。

---

## 一、现状盘点

### 1.1 总体位置

```
R0 ✅   ┃ R1 ✅   ┃ R1.5 ✅ ┃ R2 ✅   ┃ R3 ✅   ┃ R4 ✅   ┃ R5 ✅   ┃ R6 ✅ ← 当前位置 ┃ R7 · R8 · R9
骨架完成 ┃ 地图开局 ┃ R2 前置修复 ┃ 回合/移动/视野 ┃ 经济与城市 ┃ 道统与修炼 ┃ 兵种与战斗 ┃ 探索/政令/自动化 ┃ 全部未开始
```

**当前位置：R6「探索/政令/自动化」已完成 → 下一个里程碑 R7「胜利/存档/任命」。**

> R5 提示词名为「探索与战斗」，当时只交付了**单位战棋**那一半；**探索那一半（机缘 `sendToJiYuan` /
> 秘境 `exploreMiJing`）已在 R6 补齐**，`Sect.miJingExploredTotal` 不再是死字段（成就 `boost_first_mijing`
> 已可达），道点节奏（§11.2 #10）也已复查，见 §4.6。

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
  - R3 `b036bb4 feat(r3): economy settlement, spirit peak city, buildings districts workers improvements roads`
  - R3 收尾 `e18db84 fix(r3): wire relief and river yield bonuses into tile output`
  - R4 `15cc845 feat(r4): dao tree research, cultivation breakthrough tribulation, project queue, recruitment`（见 §4.3）
  - R4 收尾 `603987b docs(r4): record delivered r4 commit hash in roadmap`
  - R3/R4 补充（三流派特性）`1c82f68 feat(faction): implement three-faction traits (build speed, sub-peak cost, bloodline cultivation)`（见 §4.5）
  - R3/R4 补充收尾 `44ba556 docs(faction): record delivered commit hash for three-faction traits`
  - R5 `442f701 feat(r5): ten unit classes, combat preview and resolution, zoc, teleport, garrison, reclass promote`（见 §4.4）
  - R6 `a0c72c8 feat(r6): exploration ji yuan mi jing, policy government cards, automation toggles`（见 §4.6）

### 1.2 已交付并验证的资产

| 层 | 文件 | 状态 |
|---|---|---|
| 共享协议 | `shared/protocol/{commands,msg,dto,enums}.gd` | ✅ `msg`（版本 2.0/存档 3.0/端口 9527/8 个错误码/16 MiB 帧缓冲）、`commands`（**R6 起 56 条**：R2 的 8 条 + R3 城市/改良 15 条 + R4 道统/队列 5 条 + R5 战斗/单位 12 条 + R6 探索/政令/自动化 16 条）、`enums`（地形/节点/流派/境界/兵种/建筑/区域/改良/资源/阶段全量；**R3 新增 `Building`（10 种 + `ALL`/`NAMES`/`CORE`）、`DistrictType`（首府区 + 5 可建 + `ALL`/`NAMES`/`BUILDABLE`）、`ImprovementType`（8 种 `ALL`）**；**R4 新增 `Realm.NAMES`（炼气/筑基/金丹/元婴/化神）、`Position` 具名常量 + `NAMES`**；**R5 新增 `CombatOutcome`（8 值 + `ALL`/`NAMES`）、`UnitClass` 补齐 9 个具名常量 + `ALL`/`KINDS`、`SpiritRootType.NAMES`**；**R6 新增 `NodeType.NAMES`（灵田/灵脉/机缘/秘境/灵泉/灵峰，`GameNode.name` 的取名来源）**）、`dto`（信封解析与构造） |
| 共享几何 | `shared/geo/hex.gd` | ✅ 7 个静态函数（`id/coords/neighbors/distance/to_world/opposite/edge_vertices`）已按 R1 契约补齐，两端共用 |
| 服务端·网络 | `net/{NetServer,CommandDispatcher,StateView}.gd` | ✅ 监听 9527、hello 握手、**R6 起 56 条命令**、错误码口径、`view` 全量快照 + 迷雾快照；**R3 新增**：`view.improvements{}` 按 `Sect.improvementSnapshots` 做迷雾「最后可见」缓存下发；**R4 新增**：`view.sects[player].unlockedDaoIds[]` 与 `daoOptions[]`（21 条道法，含 `eraIndex`/折扣后 `daoPointCost`/工力总额 `spiritPowerCost`/加速后 `turns`/三态 `state`/`blocker`，**仅己方下发**）；**R5 新增**：`view.nodes[nodeId].garrisonDiscipleIds[]`（己方节点下发、敌方/中立节点整字段 `erase`）、`view.sects[].disciples[]` 追加 `battleXp`/`battleLevel`/`promotionPoints`/`promotions[]`/`reclassCooldown`/`garrisonNodeId`；**R6 无新增 view 字段**——政令/自动化状态一律走 `queryPolicyOptions` / `queryAutomationState` 按需下发（`governmentId`/`enactedPolicies`/`automationToggles`/`autoProjectByPeak` 属内部记账，见 PROTOCOL §12.5） |
| 服务端·规则 | `rules/{MapGenerator,SetupInitializer,VisionCalculator,MoveRules,MoveRangeCalculator,MoveAction,TurnProcessor}.gd`、`rng/RngService.gd` | ✅ 分层地形生成（基底/海拔/地貌/河流/险地/节点/奢侈，种子确定）、四宗初始化、视野计算、移动力公式/可通行/跨河/进入代价叠加、BFS 可达（与 `queryMoveRange` 同算法）、移动命令、六阶段回合状态机；**R3 新增**：`EconomyRules`（地块/灵峰产出、维护、安定、产出系数、粮食、`apply_settlement` 唯一入口、气运满溢吞并与灵峰晋升）、`CityRules`（工作半径/指派/住房/容量/区域产出与邻接/建城与建筑可建判定）、`ImprovementRules`（地形与道法/区域/节点门控、产出、洞府住房、道路机动、掠夺、修缮）、`RoadNetworkService`（路网连通度/减耗/起始格加成）、`CityAction`（开峰/建筑/洞府/加固/区域/劳力/项目队列推进/只读查询）、`ImprovementAction`（任命建造者/修筑/修缮/查询）；**R3 回填 R2 空钩子**：`MoveRules.step_cost` 与 `calculate_max_move_points` 改调 `RoadNetworkService`，`TurnProcessor` 的 `TURN_START` 调 `RoadNetworkService.refresh()`、`SPIRIT_PEAK` 推项目队列、`SETTLEMENT` 调 `EconomyRules.apply_settlement()`；**R4 新增**：`DaoRules`（21 道法查找/时代门控/前置链/费用与工期/`effect_sum` 唯一汇总出口/成就 boost）、`DiscipleRules`（修炼速度/进度上限/突破/渡劫/心魔/伤愈/洞府判定）、`ProjectRules`（逐回合工力摊销、研究推进与落成）、`DaoAction`（5 条命令的规则实现）；**R4 回填**：`ImprovementRules._has_unlocked_dao`（查 `unlockedDaoIds`）、`MoveRules` 接 `MOVE_BONUS`、`VisionCalculator` 接 `VISION_BONUS`、`CityAction._complete_project` 增 `TYPE_RECRUITMENT` + `complete_project_now()`、`TurnProcessor` 三阶段接修炼/项目推进/成就与心魔；**R5 新增**：`UnitRules`（十兵种战术数值**唯一出口**：相克/射程/攻城/机动/视野/反击/地形防御/高台/河流/驻守/补给/断粮/撤退概率/战阶与晋升/转职校验/解锁判定，共 27 个静态函数）、`CombatResolver`（**战斗唯一结算入口**：`preview` 与 `attack` 共用 `_build_matchup`，故「预览=实战」结构性成立；含野战/攻城/夺节点三种结算 + 俘虏/伤亡/心魔反噬/战功）、`CombatAction`（`attack`/`queryAttackPreview`/`queryAttackable`/`retreat`/`batchMove`）、`UnitAction`（`teleport`/`queryTeleportOptions`/`assignGarrison`/`withdrawGarrison`/`reclass`/`promote`/`queryDiscipleDetail`）、`TeleportRules`（传送网络开启/容量/余量/花费/拦截）；**R6 新增**：`ExploreRules`（机缘/秘境：`NodeInfo` 九字段、成功率三段加成、失败三分支、秘境成本与人数、`Reward` 四类型）、`PolicyRules`（3 政体 × 8 卡、时代/道法门控、槽位裁剪、切换冷却、`effect_sum` 唯一出口、`process_settlement` 安定叠加与威望累积）、`AutomationRules`（自动修缮/改良/修路三趟 + 逐峰项目 + 立即探索 + 集结/回防，预算 = `maxActionsPerTurn`）、`ExploreAction`/`PolicyAction`/`AutomationAction`（三条命令族薄门面）；**R6 回填**：`TurnProcessor._run_turn_start` 末尾接 `AutomationRules.run_turn`（R2 留的 TODO）、`TurnProcessor._run_settlement` 在 `EconomyRules.apply_settlement` **之后**接 `PolicyRules.process_settlement`；**R5 回填**：`MoveRules.step_cost` 接 ZOC 附加代价与敌方占格阻挡、`calculate_max_move_points` 接晋升 `MOVE_BONUS`，`TurnProcessor` 的 `TURN_START` 清零传送次数并递减转职冷却、`SPIRIT_PEAK` 接断粮削减、`SETTLEMENT` 补一次 `VisionCalculator.recalculate` |
| 服务端·模型 | `model/{HexTile,GameNode,Sect,Disciple,SpiritPeak,GameState}.gd` | ✅ 纯数据 + `to_dict()`；**R2 起 `Disciple` 含 `maxMovePoints`/`turnsInSect`**；**R3 新增 `Project`/`District`/`Improvement`**，`SpiritPeak` 增 `food`/`foodProgress`/`freeWorkers`/`workedTileIds`/`projectQueue`、`Sect` 增 `improvements`/`improvementSnapshots`、`Disciple` 增 `builderCharges`、`GameState` 增 `projectSeq`/`improvementSeq`；**R4 新增 `Dao`/`ResearchProject`**，`Disciple` 增 `realmLevel`/`breakthroughPending`/`tribulating`/`lastReproduceTurn`、`Sect` 增 `unlockedDaoIds`/`researchQueue`/`boostFlags`/`recruitedTotal`/`enemiesDefeated`/`miJingExploredTotal`/`lastRecruitmentTurn`、`Project` 增 `TYPE_RECRUITMENT`、`GameState` 增 `discipleSeq`；**R5 新增**：`Disciple` 增 `battleXp`/`battleLevel`/`promotionPoints`/`promotions`/`reclassCooldown`/`garrisonNodeId`/`capturedFromSectId`、`SpiritPeak` 增 `siegeTurns`、`Sect` 增 `teleportsUsedThisTurn`、`GameNode` 增 `garrisonDiscipleIds`；**R6 新增**：`GameNode` 增 `name`（节点显示名，只进 `NodeInfo.name`，不进 view）、`Sect` 增 `governmentId`/`enactedPolicies`/`policyCarry`/`lastPolicySwitchTurn`/`automationToggles`/`autoProjectByPeak`、`Disciple` 增 `missionNodeId`（与 `garrisonNodeId` 互斥） |
| 服务端·配置 | `config/{ConfigLoader,ConfigValidator}.gd` | ✅ 加载 + 校验，缺字段/引用已删模块即非零退出；**R2 起 `map.dangerTileMoveCost = 1`**（险地附加，裁决二）；**R3 未新增顶层块**（`spiritPeak`/`economy`/`building`/`city`/`improvement`/`road`/`resources` 均复用） |
| 客户端·表现 | `world/{HexMap,Fog,CameraRig,UnitView,SectView}.gd`、`scenes/{Main,MainMenu,World}`、`art/AssetLibrary.gd` | ✅ 起伏六棱柱 + 连绵山体 + 河流贴边、三态迷雾静态材质、正交 45° 锁定相机、占位回退；**R2 新增**：移动高亮层、选中标记、顶部 TopBar、点选→高亮→移动交互；**R3 新增**：`CityPanel`（CanvasLayer，人口/粮食/安定/住房/工作格/区域/产出明细 + 建造/区域选址/劳力指派/改良按钮）、`SectView` 灵峰/建筑/区域占位几何、TopBar 资源栏追加 粮/气运/道点/材料；**R4 新增**：`DaoPanel`（左侧竖排，按 `eraIndex` 分 5 列 + 三态标记 + `blocker` tooltip + 点击研究）、`QueuePanel`（左下，`projects[]`/`researchQueue[]` 两列并排不混池 + 回合数输入/加速/取消）、侧栏弟子详情追加修炼进度/心魔/伤势/入门回合/灵根品阶，三个面板互斥且均不触碰相机；**R5 新增**：`CombatPanel`（右下，悬停攻击预览：攻守战力/胜率/相克/反击/距离/notes + 不可攻击时显 `blockedReason` + `CombatResult` 结算反馈）、`UnitPanel`（左下，与城市面板互斥：战功/战阶/晋升点/出手 + 撤退/传送/驻守/撤离按钮 + 十兵种转职候选置灰与 blocker tooltip + 晋升候选）、**攻击高亮层**（`HexMap.show_attack_range`，与移动高亮层**完全独立并存**，清一层不影响另一层）、`UnitView` 十兵种占位剪影（prism/box/sphere/cylinder/cone 各按兵种取值，正式模型缺失时仍可区分）、Shift+点选多选 → `batchMove`；**R6 新增**：`ExplorePanel`（节点冷却/奖励预览/派弟子/秘境多选）、`PolicyPanel`（当前政体 + 效果合计 + 3 政体按钮 + 8 卡按钮三态 + 槽位占用）、`AutomationPanel`（4 开关 + 逐峰自动项目 + 立即探索/集结/回防 + 本地设置），三面板左侧竖排**互斥**且均不触碰相机；TopBar 追加 政令 / 自动 入口；**节点点击优先级提到弟子点击之前**（秘境要求全员已站在节点格，否则面板永远打不开） |
| 客户端·网络 | `net/{NetClient,Launcher,Session}.gd` | ✅ 自动连接、hello 展示、子进程拉起与回收；**R2 起**：拉起后 0.5s 轮询等待就绪（40s 超时）、`moveRange`/`moveResult` 信号、`requestEndTurnSequence`；**R3 新增**：15 条 `request_*` 包装 + 6 个信号（`buildOptions`/`districtSites`/`assignableTiles`/`cityDetail`/`improvementOptions`/`r3Result`）；**R4 新增**：5 条 `request_*` 包装 + 2 个信号（`projectQueue`/`r4Result`）+ `_is_r4_command`；**R5 新增**：12 条 `request_*` 包装 + 5 个信号（`attackPreview`/`attackable`/`teleportOptions`/`discipleDetail`/`r5Result`）+ `_is_r5_command`；**R6 新增**：16 条 `request_*` 包装 + 5 个信号（`ji_yuan_info_received`/`mi_jing_info_received`/`policy_options_received`/`automation_state_received`/`r6_result_received`）+ `_is_r6_command`；**点选弟子改为三段串行链**（`queryMoveRange` → `queryAttackable` → `queryDiscipleDetail`），因 `_request` 是单请求语义、并发会被静默丢弃 |
| 配置 | `data/gameConfig.json` | ✅ 2144 行，26 个顶层块；2.0 地形块（`baseTerrains`/`relief`/`features`/`river`/`nodeSpawnByTerrain`）已落地；6 个裁剪块确认不存在；**R3 只读复用** `spiritPeak`/`economy`/`building`/`city`/`improvement`/`road`/`resources`/`qiYun` |
| 协议契约 | `docs/PROTOCOL_2.0.md` + `tools/check_protocol.ps1` | ✅ 69 条 + `ping` 全覆盖，分组 13/22/18/4/4/6/2；**R6 起 55 条 + `ping` 标「已实现」**（`implemented_commands()` 共 56 项；R6 的 16 条 `待实现（R6）` 全部转正，残留 14 条全属 R7）；`TODO(需核对)` 降至 **9 处**（R6 回填 §11.2 #1/#2/#4 三个实体形状，新增 §11.1 #26/#27 两项已核实差异）；校验脚本 35/35 全绿、69 分组点数不变 |
| 工具 | `tools/{setup_shared,run_dev,check}.ps1`、`tools/check_protocol.ps1` | ✅ `check.ps1` 已扩为 **21 阶段**（`[0/21]`–`[20/21]`），含 R0–R6 全量断言 + 协议契约校验（**130/130** 全绿） |

### 1.3 遗留缺口（进入 R5 前需知悉，不阻塞 R5）

1. **美术资源实体文件为 0**（`assets/` 下除 `manifest.json` 外无实体文件）。**这是计划内状态**，不是缺陷：
   - `AssetLibrary` 对 manifest 里 60+ 逻辑 ID 缺失时**全部回退占位**（模型=水墨灰阶几何体 + 文字标签、贴图=纯色块、材质=`StandardMaterial3D`、字体=回退字体），**不崩**。
   - 该行为已有测试覆盖：`client/tests/R1ClientTest.gd` L84–96 断言「模型缺失回退灰阶几何与文字」「同一缺失 logicalID 只 WARN 一次」「缺失贴图回退纯色块」「缺失材质安全回退」「无效文本字体安全回退」「F5 热重读 manifest 并使缓存失效」，并由 `check.ps1` `[9/14]` 断言 `同一缺失 logicalID 只 WARN 一次`。
   - R3 的灵峰/建筑/区域同样只走 `SectView` 占位几何（`DISTRICT_COLORS` 色块 + `Label3D` 文字 + 堆叠方块），未引入真资产。
   - 真资源排期见 §三「最小水墨资源包」前置约束。
2. **协议契约仍有 9 处 `TODO(需核对)`**（`PROTOCOL_2.0.md` §11.2；R6 已回填 #1 的 `ExploreResult`/`PolicyResult`、#2 `NodeInfo`、#4 `effects{}`/`slots{}`；R2 时 8 处 → R3 增 3 处 → R3 收尾消 1 增 1 仍 11 处 → R4 未增 → **R3/R4 收尾补做 +1 为 12 处 → R6 回填 3 处降为 9 处**）：`TrainingResult`/`AppointmentResult`/`ExploreResult`/`PolicyResult`/`NodeInfo` 等实体形状 1.0 未展开；`querySpiritPeakBlocker` 未在 69 条清单内；R3 遗留：`ImprovementRules.apply_pillage()` 的接线点（R2 移动 / R5 攻击）、敌方可见弟子的 `assignedPeakId` 未剥离、灵泉衰减/修缮恢复的生效口径（归 R6 灾劫）；**R4 后新增**：三流派特性中未能落地的键（§11.2 #11，`guoJia.expansionCostReduction`/`diDuGrowthBonus` 缺可计算口径）。**已消项**：① 原「`city` 配置缺丘陵石+1 / 河流 foodBonus」已在 R3 收尾回填（`map.relief[].yield` + `map.river.foodBonus`，见 §4.1.1）；② R3 的「道法门控改良不可建」已在 R4 回填（`ImprovementRules._has_unlocked_dao` 改查 `unlockedDaoIds`）。**R4 另登记两项已核实结论**（非 `TODO`）：§11.1 #23 成就「初探秘境」语义修正、§11.2 #10 前期道点断层；**R3/R4 收尾另登记** §11.1 #24 三流派特性落地口径（6 项已实现）。**不阻塞 R5**，随对应里程碑逐条补齐。
3. **R5–R9 提示词已预生成**（草案）；`R5_*.md` 起进入前须按当时最新代码/config 重新核对文件锚点与数值。

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

## 四、R3/R4 交付纪要 与 下一步（R5）

> R3、R4 均已在本里程碑完成并提交推送（见 §一 提交列表）。以下为**实际交付**与**下一里程碑启动清单**。

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

### 4.1.1 R3 收尾完善（交付后补做）

- **补齐地块产出的海拔/河流加成**（原 §11.2 #7 缺口）：`EconomyRules.tile_yield_preview` 现按 PRD §4.1.9 L315 的顺序计算 **基底 → 海拔 → 地貌 → 河流 → 节点 → 改良**。
  - 海拔：新增配置键 `map.relief[].yield`（形状对齐既有 `map.features[].yield`），`HILL = {spiritStones: 1}`（PRD §4.1.3 表「丘陵…石 +1」），`FLAT`/`MOUNTAIN` 空表；`ConfigValidator` 增对应类型校验。
  - 河流：接通 `map.river.foodBonus`（值 1，PRD §4.1.5 L280「沿河地块：粮 +1」）。**该键与校验此前早已存在但无任何代码读取（死键）**，本次一并修掉。
  - 影响：丘陵不再是「只涨移动成本、无经济收益」的废格；`BARREN` 的 `spiritStones` 基底与丘陵加成叠加后可达 3。
- **新增 `_test_tile_yield`**（11 项断言）：平地基线、丘陵石 +1、平地/山岳无海拔加成、沿河粮 +1、丘陵+沿河+灵林+灵田四重叠加逐项累加、未指派不产出。
- **登记新缺口 §11.2 #9**：灵泉衰减/修缮恢复（`economy.lingQuanDecayRate` / `lingQuanMinOutput` / `improvement.lingQuanRestorePerTurn` 三个死键）。1.0 以 `lingQuanBaseOutput`(15) 为分母求衰减下限，2.0 改由 `city.workYieldByNode.LING_QUAN` 给出产出后分母无权威取值；灵泉枯竭属 PRD §5.1「灾劫」，归 R6，故 R3 **不臆造系数**、留待 R6 一并回填。
- **死键审计**（`city`/`economy`/`road`/`improvement`/`spiritPeak`/`building`/`qiYun` 全部标量键对照代码引用）：除上述已修与已登记项外，其余未读键均属后续里程碑计划内（`recruitment*`/`refundRate`/`accelerateStonePerTurn`/`prestigeCultivation*`/`qiYunPerUnlockedDao` → R4；`prestigePerBattleWin` → R5；`cityAutoBuild*`/`guoJiaGovernancePerTile` → R6），无遗漏。
- **验收变化**：`R3_PASS checks=268 → 279`；`check.ps1` 仍 15 阶段全绿；`check_protocol.ps1` 仍 35/35（`TODO(需核对)` 计数 11 → 11：消 1 增 1，见上）。

### 4.2 下一步 · R4「道统与修炼」启动清单（已执行完毕，见 §4.3）

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

### 4.3 R4 实际交付（与本清单原始计划的偏差）

- **服务端新增文件**：`model/{Dao,ResearchProject}.gd`、`rules/{DaoRules,DiscipleRules,ProjectRules,DaoAction}.gd`、`tests/{R4Test.gd,R4Test.tscn}`。
- **服务端修改文件**：`model/{Disciple,Sect,Project,GameState}.gd`（`realmLevel`/`breakthroughPending`/`tribulating`/`lastReproduceTurn`、`unlockedDaoIds`/`researchQueue`/`boostFlags`/`recruitedTotal`/`enemiesDefeated`/`miJingExploredTotal`/`lastRecruitmentTurn`、`Project.TYPE_RECRUITMENT`、`discipleSeq`）、`net/{CommandDispatcher,StateView}.gd`（5 handler + `daoOptions[]`/`unlockedDaoIds[]`）、`rules/{ImprovementRules,MoveRules,VisionCalculator,CityAction,TurnProcessor,SetupInitializer}.gd`、`config/ConfigValidator.gd`、`shared/protocol/{commands,enums}.gd`。
- **5 条命令**：`researchDao` / `holdRecruitment` / `queryProjectQueue` / `cancelProject` / `accelerateProject`。`hello.implementedCommands` 累计 **28 条**（23 → 28）。
- **回合阶段（替换 R3 的 `# TODO(R4)`）**：`TURN_START` 增 伤愈（`DiscipleRules.heal_tick`）+ 修炼推进（`advance_cultivation`）；`SPIRIT_PEAK` 增 `ProjectRules.advance_projects`（先灵峰建造队列、后宗门研究队列，工力不足则暂停不扣）；`SETTLEMENT` 增 `DaoRules.check_boosts` + `_run_heart_devil`（心魔过高叛逃，原地 `while` 移除避免迭代失效）。仍留空：`# TODO(R5)` 围城断供、`# TODO(R6)` 政令、`# TODO(R7)` AI 行动/胜负判定。
- **★ R4 回填（R3 遗留）**：① `ImprovementRules._has_unlocked_dao()` 由恒 `false` 改为查 `Sect.unlockedDaoIds`，`LING_TIAN_TI_TIAN`（需 `ling_tian_nong`）与 `JU_LING_ZHEN`（需 `ju_ling_zhen`）随道法推演真正可建；② `MoveRules.calculate_max_move_points` 接入 `DaoRules.move_bonus`（`MOVE_BONUS`）；③ `VisionCalculator` 接入 `DaoRules.vision_bonus`（`VISION_BONUS`，按宗算一次后贯穿 `_reveal`）；④ `CityAction._complete_project` 增 `TYPE_RECRUITMENT` 分支 + 新增 `complete_project_now()` 包装，使 `accelerateProject` 走同一落成分发器而不绕过。
- **道法树 21 条 / 5 时代**：`炼气篇 3 / 筑基篇 4 / 金丹篇 7 / 元婴篇 4 / 化神篇 3`；4 条 `factionOnly`（各流派 1 条）、2 条 `requiresBloodLine`；前置链无环无悬空，`hun_yuan ← ti_xiu + tian_ji`、`fei_sheng ← hun_yuan`。
- **★ 时代门控（PRD 未给公式，登记 §11.1 #20）**：取 `sect_era_index`（已解锁道法所属最高时代）+ `ERA_LOOKAHEAD = 1`。理由：「同代才可研究」会死锁（炼气篇 3 条全解锁后宗门时代仍是炼气篇，筑基篇永久不可研究）。`ERA_LOOKAHEAD` 为唯一常量，不散落。
- **★ 成就语义修正（登记 §11.1 #23）**：`初探秘境` 原按 1.0 口径「已探索地块中存在秘境节点」计数，2.0 实测发现该条件**开局即成立**（出生点视野内常含秘境节点），导致第 1 回合白送 30 道点且成就永久失效——由客户端端到端断言 `开局无任何 AVAILABLE 道法` 首次暴露。已改为「成功探索秘境次数」`Sect.miJingExploredTotal`（内部记账，R5 `exploreMiJing` 落地时递增），R4 期间恒 0、成就不可触发；并补两条回归断言（开局不触发任何成就、开局道点仍为 0）。
- **客户端**：`World` 增 `DaoPanel`（左侧竖排，按 `eraIndex` 分 5 列，三态 ✓/⏳/◻/✗ + `blocker` tooltip + 点击发 `researchDao`）与 `QueuePanel`（左下，`projects[]` 与 `researchQueue[]` **两列并排不混池**，每条含「回合数 SpinBox + 加速 + 取消」），两面板与城市面板三者互斥（同屏区域）；侧栏弟子详情追加 `cultivationProgress`/`heartDevil`/`injured`/`turnsInSect`/`rootGrade`/`builderCharges`；TopBar 增「道统」「队列」入口（道点 R3 已加）。`Session` 增 5 条 `request_*` + `project_queue_received`/`r4_result_received` 两信号 + `_is_r4_command`。
- **★ 客户端单请求语义再确认**：`Session._request` 单飞（`busy` 期间静默丢弃），故队列面板的「写命令成功后重查」放在 `_on_r4_result_received` 内（此时该请求的 `pending` 已 erase、`busy` 已释放），不在 `request_*` 前连发。
- **协议契约**：`PROTOCOL_2.0.md` 10 条 `待实现（R4）`→`已实现（R4）`（残留 0）；§11.1 增 4 行（#20 时代门控、#21 研究费用/工期语义、#22 收徒人数公式、#23 成就语义修正），并回填 #18（道法门控改良在 R4 已可建）；§11.2 增 #10（前期道点断层）；§12.4 增 `unlockedDaoIds[]`/`daoOptions[]`（**仅己方**）；§12.5 增 5 组内部字段。`TODO(需核对)` 仍 11 处（R4 未新增臆造项，新增缺口均为已核实结论）。
- **验收**：服务端 `R4_PASS checks=169`（11 组：注册/道法树/门控/研究队列/取消加速/收徒/修炼突破/渡劫/移动与视野加成/成就 boost/确定性）；R1/R2/R3 无回归（`R1_PASS 79458`、`R2_PASS 220`、`R3_PASS 279`）；客户端无头 `R4_CLIENT_RESULT=OK checks=8`、端到端 `R4_CLIENT_RESULT=OK checks=69`；`check.ps1` **17 阶段 97/97 全绿**；`check_protocol.ps1` 35/35（69 条分组点数 13/22/18/4/4/6/2 不变、**28 条**已实现）；无残留 godot 进程、无 `.java`。
- **★ 端到端实测暴露的节奏问题（登记 §11.2 #10，不属缺陷）**：PRD 初始资源无道点、道点来源仅藏经阁（+2/回合）/节点/成就，而机缘（+20）与秘境（+40）属 R5 → 开局 21 条道法**全部 BLOCKED**，必须先建藏经阁（250 灵力/4 回合）再等 10 回合，**最早第 15 回合**才有首条可研究道法（`R4ClientTest` 实测 14 回合后道点 20）。与 1.0 一致（1.0 初值同为 0），R5 落地机缘/秘境后应复查节奏。

### 4.4 R5 实际交付（与本清单原始计划的偏差）

**Step 0 · 提示词锚点核对（12 处 PROTOCOL 行锚点全部命中）**
逐条核对 `docs/prompts/R5_兵种与战斗.md` 引用的配置块与协议行号：`combat`（15 键）、`warfare`（27 键，含 `zocEnabled`/`zocExtraCost=2`/`unitClasses` 10 种/`counters` 8 行 15 对/`promotions` 9 项/`levelThresholds[0,30,80,160,280]`）、`teleport`（7 键）、`powerLevel`（4 键）、`speed.batchMoveMaxTargets=8`、`map.relief`/`map.features` 的 `height`/`defenseBonus`，PROTOCOL 453/472/490/508/525/543/561/578/596/613/631/649 行全部对上。核对中发现 **4 处锚点偏差**（均已登记，无一阻塞）：

1. `map.relief` / `map.features` 在 2.0 是**字典**（按 id 索引）而非数组——1.0 是 `List`；
2. 2.0 地形 id 是英文枚举，故 1.0 那张**中文键**的 `terrainDefenseBonus{平原,险地}` 无法复用（见 §11.1 #25）；
3. `warfare.unitClasses[].factionOnly` 存在（提示词未提），由 `reclass_blocker` 强制（家族/国家专属兵种宗门不可改习）；
4. `Enums.UnitClass` 此前只有 `PU_TONG` + `ALL`，缺 9 个具名常量（已补，见 §1.2）。

**Step 1 · 服务端规则（新增 5 个文件）**

| 文件 | 职责 | 关键设计 |
|---|---|---|
| `UnitRules.gd` | 十兵种战术数值**唯一出口**（27 个静态函数） | 相克/射程/攻城/机动/视野/反击/地形防御/高台/河流/驻守/补给/断粮/撤退概率/战阶与晋升/转职校验/解锁判定全部集中于此；**唯一写状态的函数是 `update_attrition`**（写 `peak.siegeTurns`），其余纯函数 |
| `CombatResolver.gd` | **战斗唯一结算入口** | `preview()` 与 `resolve_attack()` 共用 `_build_matchup` → 「预览=实战」结构性成立（裁决三）；三种结算分支：野战 `_resolve_duel` / 攻城 `_resolve_peak_siege` / 夺节点 `_resolve_node_contest` |
| `CombatAction.gd` | `attack`/`queryAttackPreview`/`queryAttackable`/`retreat`/`batchMove` | `queryAttackable` 直接复用 `preview().attackable`，故「高亮即可打」；`batchMove` 单人失败不中断其余，逐人报告拼进 `message` |
| `UnitAction.gd` | `teleport`/`queryTeleportOptions`/`assignGarrison`/`withdrawGarrison`/`reclass`/`promote`/`queryDiscipleDetail` | 转职/晋升后**当场重算机动上限**（裁决七），避免「转职后移动力仍是旧值」 |
| `TeleportRules.gd` | 传送网络开启/容量/余量/花费/拦截 | `enabled=false` 时 `capacity` 与 `remaining` **强制为 0**（API 自洽：关掉网络就不该还有容量） |

**Step 2 · 协议命令**：`commands.gd` 28 → **40 条**（12 条 R5），`CommandDispatcher` 全部注册，`reclass.unitClass` 用 `_require_enum(..., Enums.UnitClass.ALL)` 严格比对、非法值回 `BAD_PARAMS`（**不静默回退**）；`teleport` 目标峰字段取 `targetPeakId`（§11.1 #1）。

**Step 3 · 客户端表现**：见 §1.2「客户端·表现 / 客户端·网络」两行的 R5 条目。核心约束全部守住：**客户端零规则**（可攻击集/转职三态/传送选项一律来自服务端）、**面板互斥**（战斗面板右下、弟子详情左下与城市面板互斥）、**相机不重置**（`R5ClientTest` 逐项断言 transform/size 不变）。

**Step 4 · 验收**：`R5_PASS checks=453`（20 个测试组）、`R5_CLIENT_RESULT=OK checks=95`；`R1 79458`/`R2 220`/`R3 297`/`R4 174`/`R1_CLIENT 52`/`R2_CLIENT 5`/`R3_CLIENT 5`/`R4_CLIENT 8` 无回归；`tools/check.ps1` 扩为 **19 阶段**（新增 `[15/18]` 服务端 R5、`[16/18]` 客户端 R5，原仓库扫描/协议契约顺延为 `[17/18]`/`[18/18]`），`check_protocol.ps1` 35/35。

**R4 遗留回填情况**（R5 提示词 Step 1 要求的三项）：
- ✅ `Sect.enemiesDefeated` 由战斗胜利递增（`CombatResolver` 胜负判定后），故成就 `boost_first_win` **已可达**；
- ✅ 围城断供削减已落地（`UnitRules.update_attrition` 在 `TurnProcessor` 的 `SPIRIT_PEAK` 段逐峰调用，断粮/恢复写事件日志）；
- ❌ `Sect.miJingExploredTotal` **未回填**——依赖 `exploreMiJing`，而该命令属 R6。

**偏差与未做项（诚实登记）**
- **R5 提示词含「探索」，本轮只交付「单位战棋」那一半**：机缘 `sendToJiYuan` / 秘境 `exploreMiJing` 未实现，故 `Sect.miJingExploredTotal` 仍恒 0、成就 `boost_first_mijing` 不可达（§11.1 #23），道点节奏问题（§11.2 #10）**未复查**，留待 R6。
- **移动路径掠夺未接线**：`pillageChanceOnMove` 0.35 仍未被读取；攻击路径已接（`attackerWon` 时调 `ImprovementRules.apply_pillage`），见 §11.2 #7。
- **R5 未新增配置块**：`combat`/`warfare`/`teleport`/`powerLevel`/`speed` 均复用既有配置，仅补 `ConfigValidator` 约 30 个数值键 + 6 个类型键的校验。

### 4.5 R3/R4 补充完善：三流派特性（交付后补做）

**怎么发现的**：R4 交付后对 `daoTree`/`disciple`/`building`/`economy`/`appointment`/`warfare`/`faction`/`city` 八个配置块重跑死键审计，发现 **`faction` 块此前从未被审计过**（R3 收尾只覆盖了 `city`/`economy`/`road`/`improvement`/`spiritPeak`/`building`/`qiYun`）。审计结果：`faction` 46 个叶子键中只有 3 个被读过（`researchSpeedBonus`/`qiYunBonus`/`bloodDaoCostReduction`），而 PRD §1.1 明确写着的「营造 +30%、副峰花费 −20%、血脉修炼 +40%、祖祠修炼 +25%、建峰花费 +50%」全部未实现。

**关键判断**：回查 1.0 源码，这些键在 `GameConfig.java` 里**只有 getter/setter，业务代码零引用** —— 即 1.0 也从未实现流派特性。因此这不是「1.0 回填」，而是**按 PRD §1.1 首次实现**。落地前先排除了两类陷阱：

- **不叠乘开峰造价**：`spiritPeak.foundCost` 表已内建流派差异（宗门 500 / 家族 800 / 国家 350，其中 800=500×1.6、350=500×0.7），故 `jiaZu.foundCostPenalty`(0.6)、`guoJia.foundCostReduction`(0.3) 是**冗余键**，再乘一次会双重计费。
- **不臆造口径**：`guoJia.expansionCostReduction`（「扩张 −20%」未定义扩张指建区还是气运吞并）、`guoJia.diDuGrowthBonus`（「帝都人口增长 +50%」但 `building` 侧无住房/增长配置键）暂不实现，登记 §11.2 #11。

**交付**：新增 `server/scripts/rules/FactionRules.gd` 作为流派特性**唯一出口**（`build_turns` / `building_cost` / `cultivation_multiplier` / `sect_building_count`），接入 5 处：
1. `CityAction.construct_building`（造价 + 工期）
2. `CityAction.open_cave` / `fortify_peak` / `found_district`（工期）
3. `CityRules.can_build`（灵力够不够按**折后**造价判定，否则 blocker 与实际扣款不一致）
4. `CityAction.query_build_options`（`cost` 折后价、`baseCost` 配置原值、`turns` 折后工期）
5. `DiscipleRules.cultivation_speed`（家族血脉 ×1.4，有祖祠再 ×1.25）

`ConfigValidator` 增 9 个 `faction.*` 键的类型校验。

**验收**：`R3_PASS 279 → 297`（新增 `_test_faction_traits` 18 项：三流派造价/工期纯函数断言、家族与宗门端到端扣款、`queryBuildOptions` 双价字段）；`R4_PASS 169 → 174`（家族血脉/祖祠/非血脉/宗门流血脉弟子共 5 项）；`R1 79458`/`R2 220`/`R3_CLIENT 43`/`R4_CLIENT 69` 无回归；`check.ps1` 17 阶段 **97/97**、`check_protocol.ps1` **35/35** 全绿。已提交 `1c82f68` 并推送。

**顺带修正的既有测试口径**：`R3Test._test_buildings` 与 `_test_districts` 原先直接拿 `building.costs`/`building.turns` 当期望值，流派特性落地后必然失败。已改为**在测试内用 config + PRD 口径独立复算**（不调用 `FactionRules`），避免「用被测函数当自己的 oracle」。

### 4.6 R6 实际交付（与本清单原始计划的偏差）

**Step 0 · 提示词锚点核对**
逐条核对 `docs/prompts/R6_探索政令自动化.md` 引用的配置块与协议行：`explore`（12 键）、`policy`（3 政体 × `slots` + 8 卡 + `switchCooldownTurns`）、`automation`（9 键）、`qiYun`，PROTOCOL 703/721（`rally`/`returnToDefense`）、§5 探索 1145–1215、§6 政令 1219–1291、§7 自动化 1295–1402 全部对上。**无锚点偏差、无缺失配置键**（`ConfigValidator` 未新增键）。1.0 侧补齐了三个形状未知的实体：`ExploreResult`、`NodeInfo`、`Reward`，故 §11.2 #1/#2 可**原样回填**而非降级实现。

**Step 1 · 服务端规则（新增 6 个文件）**

| 文件 | 职责 | 关键设计 |
|---|---|---|
| `ExploreRules.gd` | 机缘 / 秘境 | `NodeInfo` 九字段 + `ExploreResult` 六字段原样落地；机缘成功率 = 基础 + `rootGrade × perGrade` + `zongMen.exploreSuccessBonus`；失败按 `roll` 三分支（死亡 / 受伤 + 心魔 / 仅心魔）；秘境**先扣灵石再掷骰**、全员须已站在节点格、`miJingExploredTotal += 1` |
| `PolicyRules.gd` | 3 政体 × 8 卡 | `effect_sum` 是效果合计**唯一出口**（`policy.enabled=false` 时全零）；槽位读 `policy.governments[].slots` 而非硬编码；时代门控复用 `DaoRules.sect_era_index`；`trim_policies_to_slots` 在政体槽位变少时自动废止溢出卡并逐条写进 `message` |
| `AutomationRules.gd` | 自动修缮/改良/修路 + 逐峰项目 + 立即探索 + 集结/回防 | 预算 = `automation.maxActionsPerTurn`，一趟修完再改良再修路；建造者按 `movePoints` 降序挑、按 `builderChargeCost` 扣次；`rally`/`returnToDefense` 超 `rallyMaxDisciples` **直接失败**（§11.1 #27） |
| `ExploreAction.gd` / `PolicyAction.gd` / `AutomationAction.gd` | 三条命令族薄门面 | 与 R3–R5 的 `*Action` 同构，规则实现全在 `*Rules` 里，门面只做转发与 `{success, message}` 包装 |

**Step 2 · 协议命令**：`commands.gd` 40 → **56 条**（16 条 R6），`CommandDispatcher` 全部注册；`governmentId` / `cardId` / `setAutomationToggle.key` 三处用 `_require_enum` 严格比对配置里的 id 列表，非法值回 `BAD_PARAMS`；`rally.tileId` 可选，缺省取本宗都城地块；`setSetting` **无开局也可用**（服务端只确认，`view=null`，值留在前端）。

**Step 3 · 回合回填**（R2/R3 留的 TODO 全部销账）
- `TurnProcessor._run_turn_start` 末尾接 `AutomationRules.run_turn`——必须放在移动力恢复之后，否则自动工序无法移动建造者/弟子。
- `TurnProcessor._run_settlement` 在 `EconomyRules.apply_settlement` **之后**接 `PolicyRules.process_settlement`。
- 节点冷却 −1 与 `qiYun` 每回合产出**已在 R3 实现**，本轮只补断言（`R6Test._test_backfill` 用独立对局验证），未重复实现，并把 `EconomyRules` 里那条过期的 `# TODO(R4)…TODO(R6)` 注释改成准确说明。

**Step 4 · 客户端表现**：`Session` 16 条 `request_*` 包装 + 5 个信号 + `_is_r6_command`；`World` 三个左侧竖排面板（探索 / 政令 / 自动化）互斥显示，TopBar 追加「政令」「自动」入口。**客户端零规则**：成功率、槽位、`blocker`、自动化摘要全部由服务端算好。**相机不重置**：`R6ClientTest` 逐项断言 transform/size 不变。

**Step 5 · 验收**：`R6_PASS checks=317`（13 个测试组，含 8 步命令脚本的确定性双跑逐字节比对）、`R6_CLIENT_RESULT=OK checks=59`；`R1 79458`/`R2 220`/`R3 297`/`R4 174`/`R5 453`/`R1_CLIENT 58`/`R2_CLIENT 36`/`R3_CLIENT 43`/`R4_CLIENT 69`/`R5_CLIENT 95` 无回归；`tools/check.ps1` 扩为 **21 阶段 130/130**（新增 `[17/21]` 服务端 R6、`[18/21]` 客户端 R6，原仓库扫描/协议契约顺延为 `[19/21]`/`[20/21]`），`check_protocol.ps1` **35/35**、69 分组点数不变。已提交 `a0c72c8` 并推送。

**R5 遗留回填情况**（R6 提示词要求的两项 + 一项自查）
- ✅ `Sect.miJingExploredTotal` 由 `exploreMiJing` 递增 → 成就 `boost_first_mijing` **已可达**（§11.1 #23 语义按 1.0 口径落地）；
- ✅ 道点节奏（§11.2 #10）复查完成：机缘产出 `explore.jiYuanDaoPointReward`、秘境 `explore.miJingRichDaoPoints`，与 `daoTree` 各道法 `daoPointCost` 对照后**不需要调数值**，前期断层由「探索 + 成就 boost」共同填补；
- ✅ `rally` / `returnToDefense` 两条 R5 顺延命令一并落地。

**偏差与未做项（诚实登记）**
- **两处 2.0 与 1.0 的主动差异**（已登记 PROTOCOL §11.1 #26/#27）：① 探索随机源从 1.0 的静态 `AtomicLong` + XOR 播种改为 `GameState.rng`（确定性铁律）；② `rally`/`returnToDefense` 超限改为**显式失败**而非静默截断。
- **政令安定不能照抄 1.0**：2.0 的 `SpiritPeak.stability` 是 `EconomyRules.stability_of()` 每回合**派生**的值，1.0 那套「每回合 mutate loyalty」无法移植。改为把政令安定累加进 `Sect.policyCarry["stabilityBonus"]`（整数），在 `apply_settlement` **之后**叠加到各峰 `stability` 上——这样既不改 R3 已验证的安定/产出公式，又能让「+1 安定/回合」真实生效。`R6Test` 用「开政令 vs `policy.enabled=false`」两局对照验证，避免用被测函数当自己的 oracle。
- **客户端节点点击优先级调整**：原本「先判弟子、后判节点」，导致秘境格（要求全员已站在节点格）永远打不开探索面板。已把节点分支提到弟子分支之前，Shift 仍可绕过；`R6ClientTest` 对此有专门断言。
- **R6 未新增配置块**：`explore`/`policy`/`automation`/`qiYun` 全部只读复用，`ConfigValidator` 未新增键。

#### 4.6.1 交付后审计（自查发现并修掉的 4 个洞）

交付后逐条对照提示词的 9 条硬约束、7 条裁决、12 条验收项重查了一遍，发现 4 个真问题——都不是「测试没覆盖」，而是「测试覆盖了却断言不出东西」：

| # | 问题 | 后果 | 修法 |
|---|---|---|---|
| 1 | `ExploreRules` 里 `missionNodeId` **设完立刻清空**（两个探索函数末尾各一行 `= ""`） | `queryDiscipleDetail.missionNodeId/missionNodeName` 恒为空——字段存在但永远没值，`R6Test` 原先那条「失败后已清空」是**空断言**（本来就恒空） | 删掉两处清空；按 1.0 `MoveAction.clearMissionIfLeft` 在移动到达后清、`withdrawGarrison` 优先判任务节点。新增 `_test_mission_marker` 7 项钉住完整生命周期 |
| 2 | `effect_sum` 汇总出的 4 个百分比乘区（`outputBonus`/`spiritPowerBonus`/`cultivationBonus`/`combatBonus`）**没有任何消费点** | 8 张政令卡里 6 张的主效果（产出+15%、灵力+10%、修炼+10%/+15%、战力+10%/+5%）颁了等于没颁，只有 `stabilityPerTurn`/`prestigePerTurn` 生效 | 按 1.0 三处接线：`EconomyRules.apply_settlement`（灵力总产出 ×`1+output+spiritPower`，且在 deficit 判定前）、`DiscipleRules.cultivation_speed`（并入加性池）、`CombatResolver.compute_power`（末尾乘法）。未颁卡时恒为恒等元，R3/R4/R5 数值零变化（回归实测 297/174/453 全绿） |
| 3 | PROTOCOL §11.2 #4 把槽位键写成 `{economy, military, culture}` | 实际配置键是 **`governance`**（PRD §4.13「原外交槽 2.0 改治理」）。文档错会诱导后来者按 `culture` 取槽位，导致 `used_slots` 恒 0、治理卡永远「槽位已满」 | 文档改 `governance`；`R6Test` 增两条断言（`slots` 含 `governance` 且 `zong_fa` 治理槽 = 1） |
| 4 | `queryDiscipleDetail.garrisonNodeName` 返回的是 **id 不是 name**（R5 遗留，当时 `GameNode` 还没有 `name` 字段） | 弟子详情里「驻守」显示的是 `node_37` 这类内部 id | 改为 `garrison_node.name`；客户端改用新增的 `_node_label_of()`（优先显示名、缺失退回 id），并同时展示「任务」节点 |

**另外两处「提示词自身互斥」的处理（不改实现，登记入 PROTOCOL §11.1）**：

- **验收 11 要求「`queryJiYuanInfo` 显示成功率」做不到**：1.0 `NodeInfo` 九字段不含成功率，硬约束 2 禁止客户端算，裁决三禁止凭空加字段——三者互斥。取约束优先：面板只显示 `cooldown`/`rewardPreview`/`requiredRealmLevel`/`cost`/`maxParticipants`，成功率由服务端在 `sendToJiYuan` 内判定（§11.1 #30）。
- **`missionNodeId` 在 1.0 是死字段**（`clearMissionIfLeft`/`withdrawGarrison` 两条清理规则都写好了，但全仓没有 setter 调用）。2.0 让它真正有值，并沿用 1.0 的两条清理规则（§11.1 #29）。

**顺带发现但**未**修（属 R4/R5 既有行为，改动会推翻已验收数值，留待对应里程碑复查）**：

- `DaoRules.economy_bonus()` **从未被调用**——5 条道法（`ling_tian_nong` +5%、`ju_ling_zhen` +10%、`cang_shu` +5%、`shi_jie` +10%、`di_wang_zhu_shu` +5%）的 `ECONOMY_BONUS` 目前对产出无影响。1.0 在 `EconomyCalculator` 里是 `total *= 1 + ECONOMY_BONUS`。R6 只接了政令乘区（未颁卡时恒等元），没顺手接这条，因为一接就会改动 R3 已验收的灵力产出数值、必须同步改 `R3Test` 期望值（与「勿改动 R1–R5 测试」冲突）。**建议 R7 前单独开一次「道法经济加成接线」收尾**。
- `CombatResolver.compute_power` 里道法 `COMBAT_BONUS` 用的是**加法**（`power += 0.05`），1.0 是**乘法**（`power *= 1 + 0.05`）。战力基数只有个位到几十，加 0.05 实际等于没有。同理未改（`R5Test` 在无道法加成下断言战力，改动不影响测试，但会改变 R5 已验收的战斗平衡口径）。


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
| R6 | 成功率/冷却/伤亡与 config 一致；政令槽位与切换冷却正确；`loyalty` 效果落 `stability`（叠加在派生安定之后）；自动化按 `maxActionsPerTurn` 预算触发；`miJingExploredTotal` 递增 → `boost_first_mijing` 可达 |
| R7 | 三流派胜利可达成；240 回合分数正确；同种子双跑逐字一致；读档继续与待决重建 |
| R8 | 69 命令全有 UI 入口；视角/缩放操作后不重置；全局缩到最远设施仍可辨（**前置：最小水墨资源包已交付**） |
| R9 | 换皮肤零代码；默认水墨皮肤完整；导出可独立运行；自检全绿 |
