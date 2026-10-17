# 《修仙4X·宗门争霸》2.0 —— 后续目标与推进计划（ROADMAP）

> 本文是**执行层路线图**，回答三个问题：**现在到哪了 → 接下来做什么 → 每一步怎么算做完**。
> 权威需求见 [`REQUIREMENTS_2.0.md`](REQUIREMENTS_2.0.md)（§5 裁剪、§6 契约、§7 里程碑、§9 DoD）；
> 命令契约见 [`PROTOCOL_2.0.md`](PROTOCOL_2.0.md)；
> **本文不新增任何规则与数值**，只做进度定位、依赖排序、前置检查与风险登记。

---

## 一、现状盘点

### 1.1 总体位置

```
R0 ✅   ┃ R1 ✅   ┃ R1.5 ✅ ┃ R2 ✅   ┃ R3 ✅   ┃ R4 ✅   ┃ R5 ✅   ┃ R6 ✅   ┃ R7 ✅   ┃ R8 ✅   ┃ R9 🔶 ← 当前位置
骨架完成 ┃ 地图开局 ┃ R2 前置修复 ┃ 回合/移动/视野 ┃ 经济与城市 ┃ 道统与修炼 ┃ 兵种与战斗 ┃ 探索/政令/自动化 ┃ 任命/渡劫/AI/胜负/存档 ┃ 表现与UI打磨 ┃ 未开始
```

**当前位置：R8「表现与 UI 打磨」已交付**——§3.2 硬门禁「最小水墨资源包」（52 个文件，`ASSETVERIFY_OK covered=52 warned=0`，提交 `8f96a6e`）+ 70 条命令全入口 + 六项表现层（昼夜/网格/宗门色边框/粒子/泼墨转场/小地图）+ 设置/引导/Toast。`R8_CLIENT_RESULT=OK checks=44`（单元）/ `checks=59`（端到端），服务端**零改动**。交付纪要见 §4.8。

> R7 之后 **69 条命令 + `ping` 全部落地**（`implemented_commands()` 共 70 项，PROTOCOL §1 已无「待实现」），
> 故 R8 的任务是「给每一条已实现命令补 UI 入口 + 打磨表现」，不再新增命令。

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
  - R7 `756e545 feat(r7): appointment bloodline, tribulation ascension, reactive ai, victory score, save load, victory choice`（见 §4.7）

### 1.2 已交付并验证的资产

| 层 | 文件 | 状态 |
|---|---|---|
| 共享协议 | `shared/protocol/{commands,msg,dto,enums}.gd` | ✅ `msg`（版本 2.0/存档 3.0/端口 9527/8 个错误码/16 MiB 帧缓冲）、`commands`（**R7 起 70 条**：R2 的 8 条 + R3 城市/改良 15 条 + R4 道统/队列 5 条 + R5 战斗/单位 12 条 + R6 探索/政令/自动化 16 条 + R7 存档/胜负/任命/待抉择 14 条；**69 + `ping` 全覆盖**）、`enums`（地形/节点/流派/境界/兵种/建筑/区域/改良/资源/阶段全量；**R3 新增 `Building`（10 种 + `ALL`/`NAMES`/`CORE`）、`DistrictType`（首府区 + 5 可建 + `ALL`/`NAMES`/`BUILDABLE`）、`ImprovementType`（8 种 `ALL`）**；**R4 新增 `Realm.NAMES`（炼气/筑基/金丹/元婴/化神）、`Position` 具名常量 + `NAMES`**；**R5 新增 `CombatOutcome`（8 值 + `ALL`/`NAMES`）、`UnitClass` 补齐 9 个具名常量 + `ALL`/`KINDS`、`SpiritRootType.NAMES`**；**R6 新增 `NodeType.NAMES`（灵田/灵脉/机缘/秘境/灵泉/灵峰，`GameNode.name` 的取名来源）**）、`dto`（信封解析与构造） |
| 共享几何 | `shared/geo/hex.gd` | ✅ 7 个静态函数（`id/coords/neighbors/distance/to_world/opposite/edge_vertices`）已按 R1 契约补齐，两端共用 |
| 服务端·网络 | `net/{NetServer,CommandDispatcher,StateView}.gd` | ✅ 监听 9527、hello 握手、**R7 起 70 条命令**、错误码口径、`view` 全量快照 + 迷雾快照；**R3 新增**：`view.improvements{}` 按 `Sect.improvementSnapshots` 做迷雾「最后可见」缓存下发；**R4 新增**：`view.sects[player].unlockedDaoIds[]` 与 `daoOptions[]`（21 条道法，含 `eraIndex`/折扣后 `daoPointCost`/工力总额 `spiritPowerCost`/加速后 `turns`/三态 `state`/`blocker`，**仅己方下发**）；**R5 新增**：`view.nodes[nodeId].garrisonDiscipleIds[]`（己方节点下发、敌方/中立节点整字段 `erase`）、`view.sects[].disciples[]` 追加 `battleXp`/`battleLevel`/`promotionPoints`/`promotions[]`/`reclassCooldown`/`garrisonNodeId`；**R6 无新增 view 字段**——政令/自动化状态一律走 `queryPolicyOptions` / `queryAutomationState` 按需下发（`governmentId`/`enactedPolicies`/`automationToggles`/`autoProjectByPeak` 属内部记账，见 PROTOCOL §12.5）；**R7 无新增字段，但把三个**「占位恒空」**字段接上真值**：`view.winType` / `view.winnerSectId` / `view.pendingVictoryChoices[]`（R1 起一直是空字面量）；主动消息侧新增 `awaitInput`（`CommandDispatcher.poll_await_input` + `ServerMain._on_text_received` 在响应后推送，同 `reqId` 只推一次） |
| 服务端·规则 | `rules/{MapGenerator,SetupInitializer,VisionCalculator,MoveRules,MoveRangeCalculator,MoveAction,TurnProcessor}.gd`、`rng/RngService.gd` | ✅ 分层地形生成（基底/海拔/地貌/河流/险地/节点/奢侈，种子确定）、四宗初始化、视野计算、移动力公式/可通行/跨河/进入代价叠加、BFS 可达（与 `queryMoveRange` 同算法）、移动命令、六阶段回合状态机；**R3 新增**：`EconomyRules`（地块/灵峰产出、维护、安定、产出系数、粮食、`apply_settlement` 唯一入口、气运满溢吞并与灵峰晋升）、`CityRules`（工作半径/指派/住房/容量/区域产出与邻接/建城与建筑可建判定）、`ImprovementRules`（地形与道法/区域/节点门控、产出、洞府住房、道路机动、掠夺、修缮）、`RoadNetworkService`（路网连通度/减耗/起始格加成）、`CityAction`（开峰/建筑/洞府/加固/区域/劳力/项目队列推进/只读查询）、`ImprovementAction`（任命建造者/修筑/修缮/查询）；**R3 回填 R2 空钩子**：`MoveRules.step_cost` 与 `calculate_max_move_points` 改调 `RoadNetworkService`，`TurnProcessor` 的 `TURN_START` 调 `RoadNetworkService.refresh()`、`SPIRIT_PEAK` 推项目队列、`SETTLEMENT` 调 `EconomyRules.apply_settlement()`；**R4 新增**：`DaoRules`（21 道法查找/时代门控/前置链/费用与工期/`effect_sum` 唯一汇总出口/成就 boost）、`DiscipleRules`（修炼速度/进度上限/突破/渡劫/心魔/伤愈/洞府判定）、`ProjectRules`（逐回合工力摊销、研究推进与落成）、`DaoAction`（5 条命令的规则实现）；**R4 回填**：`ImprovementRules._has_unlocked_dao`（查 `unlockedDaoIds`）、`MoveRules` 接 `MOVE_BONUS`、`VisionCalculator` 接 `VISION_BONUS`、`CityAction._complete_project` 增 `TYPE_RECRUITMENT` + `complete_project_now()`、`TurnProcessor` 三阶段接修炼/项目推进/成就与心魔；**R5 新增**：`UnitRules`（十兵种战术数值**唯一出口**：相克/射程/攻城/机动/视野/反击/地形防御/高台/河流/驻守/补给/断粮/撤退概率/战阶与晋升/转职校验/解锁判定，共 27 个静态函数）、`CombatResolver`（**战斗唯一结算入口**：`preview` 与 `attack` 共用 `_build_matchup`，故「预览=实战」结构性成立；含野战/攻城/夺节点三种结算 + 俘虏/伤亡/心魔反噬/战功）、`CombatAction`（`attack`/`queryAttackPreview`/`queryAttackable`/`retreat`/`batchMove`）、`UnitAction`（`teleport`/`queryTeleportOptions`/`assignGarrison`/`withdrawGarrison`/`reclass`/`promote`/`queryDiscipleDetail`）、`TeleportRules`（传送网络开启/容量/余量/花费/拦截）；**R6 新增**：`ExploreRules`（机缘/秘境：`NodeInfo` 九字段、成功率三段加成、失败三分支、秘境成本与人数、`Reward` 四类型）、`PolicyRules`（3 政体 × 8 卡、时代/道法门控、槽位裁剪、切换冷却、`effect_sum` 唯一出口、`process_settlement` 安定叠加与威望累积）、`AutomationRules`（自动修缮/改良/修路三趟 + 逐峰项目 + 立即探索 + 集结/回防，预算 = `maxActionsPerTurn`）、`ExploreAction`/`PolicyAction`/`AutomationAction`（三条命令族薄门面）；**R6 回填**：`TurnProcessor._run_turn_start` 末尾接 `AutomationRules.run_turn`（R2 留的 TODO）、`TurnProcessor._run_settlement` 在 `EconomyRules.apply_settlement` **之后**接 `PolicyRules.process_settlement`；**R5 回填**：`MoveRules.step_cost` 接 ZOC 附加代价与敌方占格阻挡、`calculate_max_move_points` 接晋升 `MOVE_BONUS`，`TurnProcessor` 的 `TURN_START` 清零传送次数并递减转职冷却、`SPIRIT_PEAK` 接断粮削减、`SETTLEMENT` 补一次 `VisionCalculator.recalculate`；**R7 新增**：`AppointmentRules`（7 岗位最低境界/长老名额/峰主驻留与宗主坐镇加成/原峰主降亲传）、`VictoryRules`（`refresh_power_level` 五来源、四路线 `progress_of`、`achieved_routes`、`check_defeat`、`collapse_sect` 清算、`process_victory_check` **`VICTORY_CHECK` 唯一入口**）、`BloodlineRules`（联姻/繁衍/品级抖动/灵根继承/族人死亡安定 −5）、`AIController`（反应式八段决策，攻击双门 `winChance` + 战力比）、`save/SaveManager`（全量序列化 + 版本兼容 + 自动存档槽 0）、`AppointmentAction`/`VictoryAction`/`SaveAction`（三条命令族薄门面）；**R7 回填**：`TurnProcessor` 的 `AI_ACTION` 接 `AIController.run_turn`（其后重算 AI 视野）、`VICTORY_CHECK` 接 `VictoryRules.process_victory_check`、`TURN_START` 末尾接宗主外出状态检查（两处 `# TODO(R7)` 销账）；`EconomyRules.apply_settlement` 接宗主坐镇 ×1.2、`peak_output` 接峰主驻留灵力/气运加成、`DiscipleRules.cultivation_speed` 接长老修炼加成 |
| 服务端·模型 | `model/{HexTile,GameNode,Sect,Disciple,SpiritPeak,GameState}.gd` | ✅ 纯数据 + `to_dict()`；**R2 起 `Disciple` 含 `maxMovePoints`/`turnsInSect`**；**R3 新增 `Project`/`District`/`Improvement`**，`SpiritPeak` 增 `food`/`foodProgress`/`freeWorkers`/`workedTileIds`/`projectQueue`、`Sect` 增 `improvements`/`improvementSnapshots`、`Disciple` 增 `builderCharges`、`GameState` 增 `projectSeq`/`improvementSeq`；**R4 新增 `Dao`/`ResearchProject`**，`Disciple` 增 `realmLevel`/`breakthroughPending`/`tribulating`/`lastReproduceTurn`、`Sect` 增 `unlockedDaoIds`/`researchQueue`/`boostFlags`/`recruitedTotal`/`enemiesDefeated`/`miJingExploredTotal`/`lastRecruitmentTurn`、`Project` 增 `TYPE_RECRUITMENT`、`GameState` 增 `discipleSeq`；**R5 新增**：`Disciple` 增 `battleXp`/`battleLevel`/`promotionPoints`/`promotions`/`reclassCooldown`/`garrisonNodeId`/`capturedFromSectId`、`SpiritPeak` 增 `siegeTurns`、`Sect` 增 `teleportsUsedThisTurn`、`GameNode` 增 `garrisonDiscipleIds`；**R6 新增**：`GameNode` 增 `name`（节点显示名，只进 `NodeInfo.name`，不进 view）、`Sect` 增 `governmentId`/`enactedPolicies`/`policyCarry`/`lastPolicySwitchTurn`/`automationToggles`/`autoProjectByPeak`、`Disciple` 增 `missionNodeId`（与 `garrisonNodeId` 互斥）；**R7 新增 `SaveInfo`**（7 字段与 1.0 逐字一致），`GameState` 增 `winType`/`winnerSectId`/`pendingVictoryChoices`，`Sect` 增 `powerLevel`/`defeated`/`lastAutoSaveTurn`/`zongZhuOutside`，`Disciple` 增 `ascended`/`spouseId`/`fatherId`/`motherId` |
| 服务端·配置 | `config/{ConfigLoader,ConfigValidator}.gd` | ✅ 加载 + 校验，缺字段/引用已删模块即非零退出；**R2 起 `map.dangerTileMoveCost = 1`**（险地附加，裁决二）；**R3 未新增顶层块**（`spiritPeak`/`economy`/`building`/`city`/`improvement`/`road`/`resources` 均复用） |
| 客户端·表现 | `world/{HexMap,Fog,CameraRig,UnitView,SectView}.gd`、`scenes/{Main,MainMenu,World}`、`art/AssetLibrary.gd` | ✅ 起伏六棱柱 + 连绵山体 + 河流贴边、三态迷雾静态材质、正交 45° 锁定相机、占位回退；**R2 新增**：移动高亮层、选中标记、顶部 TopBar、点选→高亮→移动交互；**R3 新增**：`CityPanel`（CanvasLayer，人口/粮食/安定/住房/工作格/区域/产出明细 + 建造/区域选址/劳力指派/改良按钮）、`SectView` 灵峰/建筑/区域占位几何、TopBar 资源栏追加 粮/气运/道点/材料；**R4 新增**：`DaoPanel`（左侧竖排，按 `eraIndex` 分 5 列 + 三态标记 + `blocker` tooltip + 点击研究）、`QueuePanel`（左下，`projects[]`/`researchQueue[]` 两列并排不混池 + 回合数输入/加速/取消）、侧栏弟子详情追加修炼进度/心魔/伤势/入门回合/灵根品阶，三个面板互斥且均不触碰相机；**R5 新增**：`CombatPanel`（右下，悬停攻击预览：攻守战力/胜率/相克/反击/距离/notes + 不可攻击时显 `blockedReason` + `CombatResult` 结算反馈）、`UnitPanel`（左下，与城市面板互斥：战功/战阶/晋升点/出手 + 撤退/传送/驻守/撤离按钮 + 十兵种转职候选置灰与 blocker tooltip + 晋升候选）、**攻击高亮层**（`HexMap.show_attack_range`，与移动高亮层**完全独立并存**，清一层不影响另一层）、`UnitView` 十兵种占位剪影（prism/box/sphere/cylinder/cone 各按兵种取值，正式模型缺失时仍可区分）、Shift+点选多选 → `batchMove`；**R6 新增**：`ExplorePanel`（节点冷却/奖励预览/派弟子/秘境多选）、`PolicyPanel`（当前政体 + 效果合计 + 3 政体按钮 + 8 卡按钮三态 + 槽位占用）、`AutomationPanel`（4 开关 + 逐峰自动项目 + 立即探索/集结/回防 + 本地设置），三面板左侧竖排**互斥**且均不触碰相机；TopBar 追加 政令 / 自动 入口；**节点点击优先级提到弟子点击之前**（秘境要求全员已站在节点格，否则面板永远打不开）；**R7 新增**：`VictoryPanel`（三路线 `stage`/`ratio`/`summary`/`score` + 逐 goal 9 键行 + 择定按钮）、`SavesPanel`（槽 0–4 存入/读取 + `listSaves` 刷新）、`GameOverPanel`（`winType`/`winnerSectId`/本宗达成路线/覆灭判定）、`ChoicePanel`（居中 `layer=5` 待抉择弹窗，按 `options[].index` 发 `resolveChoice`）、侧栏**事件栏**（回包 `events[]` 保留 12 条，AI 行动占位展示）、弟子详情追加「任命峰主/长老/宗主」「渡劫飞升」四入口；TopBar 追加 胜负 / 存档 / 结局 入口；`MainMenu` 追加「读取存档」（`listSaves` → `loadGame`，与 `newGame` 共用 `game_started` 路径）；四面板与 R3–R6 面板**全局互斥**且均不触碰相机；**R8 新增**：`world/Decorations.gd`（昼夜 180 秒循环 / 六边形网格开关 / 宗门色边框 / 灵气粒子 / 飞鸟 / 三态迷雾泼墨转场，五层子节点互不干扰）、`ui/ActionBar.gd`（底栏 + **70 条命令入口登记表**，四类 button/panel/gesture/auto）、`ui/Minimap.gd`（三态配色 + 视口框 + 点击跳转**只发信号不碰相机**）、`ui/SettingsPanel.gd`（6 项本地偏好，`setSetting` 仅作确认）、`ui/GuideOverlay.gd`（6 步引导，不阻塞输入）、`ui/Toast.gd`（轻提示，只显 `✗` 状态与 `events[]`）；TopBar 资源文本改 **13 项图标化 `ResourceChips`**（`topbar_resource_label` 保留为 `visible=false` 文本镜像，不破坏 R2 既有断言），7 个面板按钮下沉到底栏；补 8 条此前无 UI 入口的命令（`foundSpiritPeak`/`appointBuilder`/`openCave`/`fortifyPeak`/`repairImprovement`/`queryVictoryChoice`/`nextTurn`/`finishTurn`）；快捷键 `空格`/`End`/`G`/`B`/`M`/`F1`/`Esc`；`world/CameraRig.gd` 新增 `pan_to()`（**只平移**，显式不改 `rotation`/`size`）、`view_center()`、`view_size()` |
| 客户端·网络 | `net/{NetClient,Launcher,Session}.gd` | ✅ 自动连接、hello 展示、子进程拉起与回收；**R2 起**：拉起后 0.5s 轮询等待就绪（40s 超时）、`moveRange`/`moveResult` 信号、`requestEndTurnSequence`；**R3 新增**：15 条 `request_*` 包装 + 6 个信号（`buildOptions`/`districtSites`/`assignableTiles`/`cityDetail`/`improvementOptions`/`r3Result`）；**R4 新增**：5 条 `request_*` 包装 + 2 个信号（`projectQueue`/`r4Result`）+ `_is_r4_command`；**R5 新增**：12 条 `request_*` 包装 + 5 个信号（`attackPreview`/`attackable`/`teleportOptions`/`discipleDetail`/`r5Result`）+ `_is_r5_command`；**R6 新增**：16 条 `request_*` 包装 + 5 个信号（`ji_yuan_info_received`/`mi_jing_info_received`/`policy_options_received`/`automation_state_received`/`r6_result_received`）+ `_is_r6_command`；**点选弟子改为三段串行链**（`queryMoveRange` → `queryAttackable` → `queryDiscipleDetail`），因 `_request` 是单请求语义、并发会被静默丢弃；**R7 新增**：14 条 `request_*` 包装 + 6 个信号（`victory_progress_received`/`victory_choice_received`/`saves_received`/`await_input`/`events_received`/`r7_result_received`）+ `_is_r7_command`；`NetClient.server_message` 分流 `awaitInput`（它不带 `id`/`ok`/`view`，走不到 `_handle_response`）；`loadGame` 与 `newGame` 同样触发 `game_started`；**R8 新增**：`request_next_turn()`（`nextTurn` 此前服务端已实现、客户端无入口，R8「70 条全入口」才暴露） |
| 配置 | `data/gameConfig.json` | ✅ 2144 行，26 个顶层块；2.0 地形块（`baseTerrains`/`relief`/`features`/`river`/`nodeSpawnByTerrain`）已落地；6 个裁剪块确认不存在；**R3 只读复用** `spiritPeak`/`economy`/`building`/`city`/`improvement`/`road`/`resources`/`qiYun` |
| 协议契约 | `docs/PROTOCOL_2.0.md` + `tools/check_protocol.ps1` | ✅ 69 条 + `ping` 全覆盖，分组 13/22/18/4/4/6/2；**R7 起 69 条 + `ping` 全部标「已实现」**（`implemented_commands()` 共 70 项；**无「待实现」**）；`TODO(需核对)` 降至 **7 处**（R7 回填 §11.2 #1 `AppointmentResult` 与 #3 `goals` 9 键，§3 `tribulate`/`appoint*` 的 result 展开）；校验脚本 **38/38** 全绿（新增「已实现 = 70」全量断言与 `awaitInput` 转正断言）、69 分组点数不变 |
| 工具 | `tools/{setup_shared,run_dev,check}.ps1`、`tools/check_protocol.ps1` | ✅ `check.ps1` 已扩为 **24 阶段**（`[0/24]`–`[23/24]`），含 R0–R8 全量断言 + 协议契约校验（**175/175** 全绿） |

### 1.3 遗留缺口（进入 R5 前需知悉，不阻塞 R5）

1. **美术资源：R8 前置已交付 52 个实体文件，其余仍为 0**（`assets/art/default/**` 下现有 32 个 `.png` + 20 个 `.glb`，覆盖 `terrain`/`units`/`buildings`/`resources`/`realms`/`factions` 六组；`districts`/`improvements`/`features`/`audio`/`fonts` 五组共 25 个 ID 仍缺，见 §3.2.1）。缺的部分**是计划内状态**，不是缺陷：
   - `AssetLibrary` 对 manifest 里缺失的逻辑 ID **全部回退占位**（模型=水墨灰阶几何体 + 文字标签、贴图=纯色块、材质=`StandardMaterial3D`、字体=回退字体），**不崩**；R8 的 `R8ClientTest` 已双向断言「最小包 52 个 ID 零 WARN」+「未覆盖 ID 仍 WARN 一次」。
   - 回退行为有测试覆盖：`client/tests/R1ClientTest.gd` L84–96 断言「模型缺失回退灰阶几何与文字」「同一缺失 logicalID 只 WARN 一次」「缺失贴图回退纯色块」「缺失材质安全回退」「无效文本字体安全回退」「F5 热重读 manifest 并使缓存失效」；R8 起由 `R8ClientTest._assert_asset_fallback` 接续双向覆盖。
   - R3 的灵峰/建筑/区域同样只走 `SectView` 占位几何（`DISTRICT_COLORS` 色块 + `Label3D` 文字 + 堆叠方块），未引入真资产。
   - 真资源排期见 §三「最小水墨资源包」前置约束。
2. **协议契约仍有 7 处 `TODO(需核对)`**（`PROTOCOL_2.0.md` §11.2，`check_protocol.ps1` 实测统计；R2 时 8 处 → R3 增 3 处 → R3 收尾消 1 增 1 仍 11 处 → R4 未增 → R3/R4 收尾补做 +1 为 12 处 → R6 回填 3 处降为 9 处 → **R7 回填 2 处降为 7 处**）：`querySpiritPeakBlocker` 未在 69 条清单内；R3 遗留：`ImprovementRules.apply_pillage()` 的移动路径接线点、敌方可见弟子的 `assignedPeakId` 未剥离、灵泉衰减/修缮恢复的生效口径；**R4 后新增**：三流派特性中未能落地的键（§11.2 #11，`guoJia.expansionCostReduction`/`diDuGrowthBonus` 缺可计算口径）。**已消项**：① 原「`city` 配置缺丘陵石+1 / 河流 foodBonus」已在 R3 收尾回填（`map.relief[].yield` + `map.river.foodBonus`，见 §4.1.1）；② R3 的「道法门控改良不可建」已在 R4 回填（`ImprovementRules._has_unlocked_dao` 改查 `unlockedDaoIds`）；③ `TrainingResult`/`ExploreResult`/`PolicyResult`/`AppointmentResult`/`NodeInfo`/`goals` 九键 均已在 R5–R7 回填。**R4 另登记两项已核实结论**（非 `TODO`）：§11.1 #23 成就「初探秘境」语义修正、§11.2 #10 前期道点断层；**R3/R4 收尾另登记** §11.1 #24 三流派特性落地口径（6 项已实现）。**不阻塞 R9**，随对应里程碑逐条补齐。
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

#### 3.2.1 交付记录（✅ 已完成，`8f96a6e`）

- **交付内容**：`assets/art/default/` 下 **52 个实体文件**，覆盖上述八类清单全部 ID：
  - 地形材质 11 张（3 基底顶面 + 3 海拔侧面 + `mountain_peak` + `river` + `danger` + 2 张迷雾）；
  - 兵种模型 10 个、建筑模型 10 个（`.glb`，原点锚在底面中心，单位 ≤1.4 高 / 建筑 ≤1.75 宽，均落在半径 1.0 的六边形格内）；
  - UI 图标 21 张（`resource.*` 13 + `realm.*` 5 + `faction.*` 3，64×64 透明底、3×3 超采样）。
- **生成方式**：`client/tools/AssetGen.gd`（`res://tools/AssetGen.tscn`）**程序化生成**——固定 seed 的哈希值噪声 + 低模图元拼装，**零外部依赖、确定性可复现**。真实美术介入时同名文件覆盖即可，`manifest.json` 与代码均无需改动。
- **验收工具**：`client/tools/AssetVerify.gd` 用客户端 `AssetLibrary` 逐 ID 取资源，输出 **`ASSETVERIFY_OK covered=52 warned=0`**；`client/tools/AssetPreview.gd` 用 CPU 等距光栅化把模型/图标/材质拼成联络表（`outputs/r8_asset_*.png`，不入库）供人工核验。
- **仍未覆盖**（计划内，`AssetLibrary` 继续回退占位并 WARN 一次，裁决二）：`districts` 6、`improvements` 8、`features`/`node` 8、`audio` 1、`fonts` 2 —— 共 25 个 ID。
- **回归**：`tools/check.ps1` 现 **175/175 `CHECK_RESULT=OK`**（24 阶段，R0–R8 断言无回归）；无残留 godot 进程、无 `.java`。

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

### 4.7 R7 实际交付（与本清单原始计划的偏差）

**Step 0 · 提示词锚点核对（配置 0 缺失）**
用一次性脚本逐键核对 `docs/prompts/R7_任命渡劫AI胜负存档.md` 引用的每一个配置键，**全部命中，无一条需要新增/改写配置**：
`appointment`（8 键）、`faction.bloodline`（9 键）、`victory`（三流派 + `score` 5 权重 + `maxTurns`）、`ai`（19 键）、`difficulty.levels.*`（5×3）、`powerLevel`（4 键）、`msg.SAVE_VERSION = "3.0"`、`disciple.cultivation.tribulation*`（8 键）。核对脚本用完即删（不入库）。
1.0 侧补齐了三个形状未知之处，故裁决二/三**可原样落地而非降级**：`entity/AppointmentResult.java`（仅 `success` + `message`）、`entity/VictoryGoal.java`（5 字段 + 4 派生）、`EconomyCalculator.calculatePowerLevel`（181–217 行的完整口径）。

**Step 1 · 模型扩充（3 处改 + 1 处新建）**

| 文件 | 增量 |
|---|---|
| `GameState.gd` | `winType` / `winnerSectId` / `pendingVictoryChoices[]` |
| `Sect.gd` | `powerLevel`（派生缓存）、`defeated`、`lastAutoSaveTurn`、`zongZhuOutside`（**内部记账，只在状态翻转时记一条事件**，避免每回合刷屏） |
| `Disciple.gd` | `ascended`、`spouseId`、`fatherId`、`motherId` |
| `SaveInfo.gd`（新建） | 7 字段与 1.0 `save/SaveInfo.java` **逐字一致**（`slotId`/`turn`/`playerSectName`/`factionType`/`savedAt`/`filePath`/`fileSize`） |

`StateView.gd` 的 `winType` / `winnerSectId` / `pendingVictoryChoices` 由**恒空字面量**改为读 `GameState` 真值——R1 起它们一直占位，R7 才真正有内容。`enums.gd` 的 `Position` 增 `MIN_REALM`（7 岗位 → 最低境界，取自 1.0 `Position` 结构定义，**非可调数值**）。

**Step 2 · 服务端规则（新增 5 个文件 + 3 处接线）**

| 文件 | 职责 | 关键设计 |
|---|---|---|
| `AppointmentRules.gd` | 任命 / 名额 / 加成 | `can_appoint` 返回 blocker 串；名额 = `zhangLaoBaseLimit` + `powerLevel × zhangLaoPerPowerLevel`；`appoint_feng_zhu` 把原峰主**降为亲传**并解绑兼任；`appoint_zong_zhu` 家族流须血脉 + 须身处首都，原宗主退长老；`zong_zhu_outside_bonus_active` 三重门（有宗主 + 在首都 + 首都已有 `ZONG_ZHU_DA_DIAN`） |
| `VictoryRules.gd`（~520 行） | 胜负 / 评分 / 待决 / 失败清算 | `refresh_power_level` 口径 = 地块÷`tilesPerLevel`（国家流 ×`territoryPowerWeight`）+ 金丹以上×2 + 道法×1 + 建筑等级×1，`max(1, int)`；`process_victory_check` 是 `VICTORY_CHECK` **唯一入口**（逐宗判胜 → 判败清算 → 每 10 回合自动存档）；**240 回合不另设分支**——分数路线在 `achieved_routes` 里「`turn >= maxTurns` 且领先」自动达成，故第 1 步即完成强制结算 |
| `BloodlineRules.gd` | 联姻 / 繁衍 / 血脉继承 | 联姻 50 石；繁衍 120 石 + 60 工、冷却 5、祖祠折扣 `zuCiReproduceCostReduction`（仅家族流）；`inherit_child` 掷骰顺序固定（名字 → 品级抖动 → 家族流高品加成 → 先天突变 → 主灵根 → 额外灵根）；`on_clan_death` 家族流血脉弟子死亡 → 各峰安定 −5。**无独立命令**（69 条里没有 `marry`/`reproduce`），只由 AI 与内部结算调用 |
| `AIController.gd` | 反应式 AI | 按 `difficulty.levels.<d>.aiActionPoints` 逐点决策，优先级 `攻 → 扩张 → 探索 → 研究 → 驻守 → 收徒 → 血脉 → 改良`；攻击需 `winChance ≥ attackMinWinChance` **且** `attackerPower/defenderPower ≥ combatAdvantageThreshold` 双门；**不查宣战**（2.0 默认可直接攻击，§11.1 #6）；`_sorted_disciples` 按 id 升序，保证确定性 |
| `SaveManager.gd` | 存档 / 读档 / 自动存档 | `{slot, saved}` 固定形状（**无 `success` 布尔**）；`list_saves()` 读文件头部拼 `SaveInfo`；`is_version_compatible` 只比主版本号；读档后 `VisionCalculator.recalculate` + `RoadNetworkService.refresh`。**自带 `_state_to_dict`/`_state_from_dict` 全套，不复用 `to_dict()`**——后者是 view 形状（迷雾裁剪、内部字段不下发），存档必须全量 |

三处接线（R7 的「消费点」，否则加成/行动都是死代码）：
- `TurnProcessor._run_ai_action`：逐宗调 `AIController.run_turn`，**之后**再 `VisionCalculator.recalculate`（提示词明写「AI 行动后刷新 AI 迷雾」）；
- `TurnProcessor._run_turn_start` 末尾：宗主外出状态翻转检查（只记一次事件）；
- `TurnProcessor._run_victory_check`：转 `VictoryRules.process_victory_check`，两处 `# TODO(R7)` 注释销账；
- `EconomyRules.apply_settlement`：政令乘区之后追加 `AppointmentRules.zong_zhu_spirit_multiplier`（宗级 ×1.2）；
- `EconomyRules.peak_output`：峰主驻留时主峰基础灵力 ×(1+`fengZhuSpiritPowerBonus`)，`qi_yun` 追加峰主 +5 与宗主大殿 +10；
- `DiscipleRules.cultivation_speed`：追加 `AppointmentRules.zhang_lao_cultivation_bonus`。

**Step 3 · 协议命令**：`commands.gd` 56 → **70 条**（14 条 R7），`CommandDispatcher` 全部注册 → hello 自动下发 70 条 = **69 + ping 全覆盖**。三条口径细节：
- `_require_slot` 接受 int / 纯数字串 / 整数值 float，范围 0..99；
- `_require_any_sect` **不限己方**（胜负进度与失败判定对 AI 宗门也开放，1.0 同语义）；
- `saveGame` **未开局也回 `ok:true + saved:false`**（业务失败 ≠ 协议失败）；`loadGame` 槽位不存在才回 `BAD_PARAMS`；`loadGame` 清空 `_await_input_sent` 以便回到待决点时**重新推送**。

**Step 4 · 主动消息 `awaitInput`**（PROTOCOL §0.7 落地）
`VictoryAction.await_input_payload` 组装 `{type,reqId,kind:"victoryChoice",prompt,options[{index,label,routeId,description}]}`；`CommandDispatcher.poll_await_input()` **同 `reqId` 只推一次**（`_await_input_sent`），`ServerMain._on_text_received` 在**响应发出之后**再推，保证客户端先拿回包再收弹窗。`reqId` 取 `req_victory_<turn>`：同回合内稳定，读档后按存档回合重建，客户端不必记 id 也能对上。

**Step 5 · 客户端表现**
`Session` 14 条 `request_*` 包装 + 5 个信号（`victory_progress_received` / `victory_choice_received` / `saves_received` / `await_input` / `r7_result_received`）+ `events_received`（回包 `events[]` 进侧栏事件栏）+ `_is_r7_command`；`NetClient` 的 `server_message` 分流 `awaitInput`（它不带 `id`/`ok`/`view`，走不到 `_handle_response`）。`World` 新增四块 UI：**胜利进度面板**（三路线 `stage`/`ratio`/`summary`/`score` + 逐 goal 9 键行 + 择定按钮）、**存档面板**（槽 0–4，存入/读取/listSaves 刷新）、**结局屏**（`winType`/`winnerSectId`/本宗达成路线/覆灭判定 + 待择按钮）、**待抉择弹窗**（居中 `layer=5`，按 `options[].index` 发 `resolveChoice`）、**事件栏**（侧栏，保留 12 条）；弟子详情面板追加「任命峰主/长老/宗主」「渡劫飞升」四个入口。`MainMenu` 追加「读取存档」（`listSaves` → `loadGame`，与 `newGame` 共用 `game_started` 路径）。

**Step 6 · 验收**：`R7_PASS checks=211`（12 个测试组，含 `outputs/r7_authority_a|b.json` 双跑 SHA256 相同）、`R7_IMPLEMENTED=70`、`R7_CLIENT_RESULT=OK checks=77`；回归 `R1 79458` / `R2 220` / `R3 297` / `R4 174` / `R5 453` / `R6 317`、客户端 `R1 58` / `R2 36` / `R3 43` / `R4 69` / `R5 95` / `R6 59` 全绿；`tools/check.ps1` 扩为 **23 阶段**（新增 `[19/23]` 服务端 R7、`[20/23]` 客户端 R7，原仓库扫描/协议契约顺延为 `[21/23]`/`[22/23]`），`check_protocol.ps1` **38/38**（新增「已实现 = 70」全量断言）、69 分组点数不变。已提交 `756e545` 并推送。

**九条裁决的落地对照**

| 裁决 | 落地位置 |
|---|---|
| ① AI 反应式启发式（删性格/长期战略/外交议程/`StrategyService`） | `AIController` 只有 `_try_*` 八段反应式决策，无任何性格/战略状态字段 |
| ② `AppointmentResult` = `{success, message}` 两键 | `AppointmentRules.ok()/fail()`；1.0 已回核（§11.2 #1） |
| ③ `routes[].goals` = 1.0 `VictoryGoal` 5 字段 + 4 派生 = 9 键 | `VictoryRules._goal()`（§11.2 #3） |
| ④ 胜负条件全读 config | `progress_of` 的每个 `target` 都取自 `config["victory"]`，无字面量阈值 |
| ⑤ 分数 = `powerLevel×1 + 飞升×12 + 份额×40 + 道法完成×30 + 灵峰×3`，240 回合强制结算 | `VictoryRules.compute_score`（权重读 `victory.score`）+ `achieved_routes` 的分数分支 |
| ⑥ `powerLevel` 不是声望折算 | `refresh_power_level` 五来源，`prestige` 不参与 |
| ⑦ `awaitInput` 仅 `victoryChoice`，`resolveChoice` 只认 `req_victory_*` | `VictoryAction.KIND`/`REQ_PREFIX`；越界回 `BAD_PARAMS` **且待决原样保留** |
| ⑧ 存档版本 `"3.0"`、`saves/` 不入库 | `Msg.SAVE_VERSION`；`.gitignore` 已有 `/saves/*` + `!/saves/.gitkeep` |
| ⑨ 每 10 回合自动存档槽 0 | `VictoryRules.process_victory_check` 末尾 + `SaveManager.AUTO_SAVE_SLOT` |

**偏差与未做项（诚实登记）**
- **`process_victory_check` 不单设 240 回合分支**：分数路线在 `achieved_routes` 里带 `turn >= maxTurns` 条件，故「强制结算」由同一条判定路径自然完成，少一条易漂移的分支。
- **`SaveManager` 不复用 `to_dict()`**：view 形状与存档形状是两件事（前者迷雾裁剪、后者必须全量），复用会导致读档后迷雾/内部字段丢失。
- **客户端「多路线待决」用注入而非真打**：`pendingVictoryChoices` 只能由服务端 `VICTORY_CHECK` 在「同回合达成 ≥2 条路线」时写入，**任何协议命令都无法置位**；要在客户端验收里跑到那个状态，只能 240 回合或构造齐备局。故 `R7ClientTest` 把一条**形状完全合规**的 `awaitInput` 注入到 `Session._on_server_message`（与服务端推送**同一条下游链路**：主动消息 → `await_input` → 弹窗 → `resolveChoice`），并顺势断言「服务端此刻无待决 → `BAD_PARAMS` → 弹窗保留」（正是裁决七要的行为）。服务端侧的真待决路径由 `R7Test._test_victory_choice` 用构造局覆盖。
- **三处既有测试被后续里程碑打破的过期断言，已按「新语义」修正而非放宽**：`R6Test` 的「已登记命令 56 条」→ `>= 56`（R7 后 70）；`R4Test` 的「`tribulate` 未登记」→ `Commands.TRIBULATE == "tribulate"`；`R3Test` 的赤字夹具改为逐座加建筑（R7 峰主灵力加成让写死的 20 座建筑构造不出赤字）。
- **客户端路线显示名用本地对照表**：`routes[]` 只下发路线 id（PROTOCOL §2），故 `World.ROUTE_LABELS` 保留四路线 id → `winType` 中文名。**纯文案映射，不含任何规则**（比例/达成/评分全部来自服务端）。

### 4.8 R8 实际交付（表现与 UI 打磨）

**Step 0 · 前置门禁（§3.2）已先行交付**：`8f96a6e` / `59a7bee` 提交了 52 个程序化水墨资源（`assets/art/default/**`）+ 三个可复现工具（`AssetGen` 生成 / `AssetVerify` 逐 ID 验收 / `AssetPreview` CPU 等距联络表）。验收口径 `ASSETVERIFY_OK covered=52 warned=0`，即 §3.2 八类（3 基底顶面 + 3 海拔含 `MOUNTAIN_TOP` + 河流 + 险地 + 三态迷雾 + 10 单位 `.glb` + 10 建筑 `.glb` + 21 UI 图标）全部命中，`AssetLibrary.resource_for()` 对这 52 个 ID **零 WARN**。`districts`/`improvements`/`features`/`audio`/`fonts` 五组共 25 个 ID **刻意不覆盖**——保留裁决二「资源缺失只 WARN 不崩」的活体验收路径。

**Step 1 · 新建 6 个表现层模块（服务端零改动）**

| 文件 | 职责 | 关键设计 |
|---|---|---|
| `world/Decorations.gd`（~330 行） | 昼夜 / 网格 / 宗门色边框 / 环境粒子 / 飞鸟 / 泼墨转场 | 五层子节点（`GridLayer`/`BorderLayer`/`AmbientLayer`/`BirdLayer`/`InkLayer`）互不干扰；`DAY_CYCLE_SECONDS=180` 纯本地计时，相位→太阳高度角/能量/环境色/背景色；`build_grid` 每格只画唯一一条相邻边（`drawn`/`reverse` 去重，352 格 → 1131 条线）；`build_borders` 按 `tile.ownerSectId` + `sect.color` 生成 `CylinderMesh` 无盖环；`play_ink_transitions` 从 `scale(0.35,1,0.35)`+alpha 0.86 tween 到 1.0+alpha 0 |
| `ui/ActionBar.gd`（~180 行） | 底部操作栏 + **70 条命令入口登记表** | `entries: Dictionary` 四类 `button`/`gesture`/`auto`；`add_plain()` 专供显示开关（**不进命令表**，故「网格/边框/小地图/引导」不会被误算成命令入口）；`state_of(command)` 返回 `{registered,kind,label,exists,enabled,text,tooltip}` 供机检 |
| `ui/Toast.gd`（~70 行） | 业务/事件轻提示 | `DEFAULT_SECONDS=3.2`，最后 0.6 秒淡出；只显示 `Session.status` 以 `✗` 开头者与回包 `events[]`，不弹模态框 |
| `ui/Minimap.gd`（~180 行） | 小地图 + 视口框 + 点击跳转 | 三态迷雾配色 + 宗门色 `lightened(0.35)`；`_gui_input` 命中 6px 内最近点 → `tile_picked` 信号；**只发信号，不碰相机** |
| `ui/SettingsPanel.gd`（~200 行） | 6 项显示/音频偏好 | 5 个 `CheckButton`（`gridVisible`/`factionBorders`/`dayNight`/`ambientParticles`/`animation`）+ `VolumeSlider`；`_apply` 本地立即生效，`Session.request_set_setting()` **仅作确认**；`on_setting_confirmed` 处理 `{success,key,value,applied:false,note}`（`applied` 恒 false 是正确行为） |
| `ui/GuideOverlay.gd`（~170 行） | 6 步新手引导 | 看地图 → 选弟子 → 打与守 → 建与治 → 势力与胜负 → 常用键；不阻塞输入、不改相机 |

**Step 2 · 修改 3 个既有文件**

| 文件 | 增量 |
|---|---|
| `world/CameraRig.gd` | 新增 `pan_to()`（**只平移**，显式不改 `rotation`/`size`）、`view_center()`、`view_size()`。`pan_to` 是相机铁律在 R8 的显式实现 |
| `net/Session.gd` | 新增 `request_next_turn()`——`nextTurn` 此前**服务端已实现、客户端无入口**（R8「70 条全入口」才暴露出来） |
| `scenes/World.gd`（3542 → 4204 行） | `_build_r8()` 装配全部 R8 模块；`_refresh_r8(view)` 挂在 `_render()` 与空 view 分支末尾；顶栏资源文本改 13 项图标化 `ResourceChips`（`topbar_resource_label` 保留为 `visible=false` 文本镜像，**不破坏 R2 既有断言**），7 个面板按钮下沉到 `ActionBar`；补 8 条此前无 UI 入口的命令（`foundSpiritPeak`/`appointBuilder`/`openCave`/`fortifyPeak`/`repairImprovement`/`queryVictoryChoice`/`nextTurn`/`finishTurn`）；`_unhandled_input` 前置 `_handle_r8_shortcut`（`空格`/`End`/`G`/`B`/`M`/`F1`/`Esc`） |

**Step 3 · 70 条命令入口覆盖表（四类之和 = 70）**

| 类型 | 条数 | 内容 |
|---|---|---|
| `button`（底栏真按钮） | **5** | `getState` 刷新 / `beginPlayerTurn` 开始回合 / `nextTurn` 下一回合 / `setSetting` 设置 / `finishTurn` 结束回合 |
| `panel`（面板内按钮） | **43** | 城市面板 9（建造/建区/撤劳力/指派/改良查询/建改良/修缮/开洞府/加固灵峰/任命建造者）· 弟子详情 12（开峰/撤退/传送/传送候选/驻守/撤驻守/转职/晋升/渡劫/任命峰主/长老/宗主）· 道统 2 · 队列 2 · 自动化 6 · 探索 2 · 政令 3 · 存档 2 · 胜负 2 · 待抉择 1 · 新局 1 |
| `gesture`（地图手势） | **5** | `moveDisciple` 点高亮格 / `batchMove` Shift 多选 / `attack` 点赭红格 / `queryAttackPreview` 悬停预览 / `assignWorker` 劳力模式点候选格 |
| `auto`（随 view 或面板打开触发） | **17** | `ping` + 16 条只读 `query*`/`listSaves`/`checkVictory`/`checkDefeat`（面板打开或选中对象后链式查询） |

> 机检锚点：`R8ClientTest` 用 `commands.gd` 的 `get_script_constant_map()` 反向遍历（**不硬编码命令名**，天然防漂移），断言每条都有入口且总数 = 70。19 条裁剪命令**不造任何入口**（PROTOCOL §10 已登记该口径）。

**Step 4 · 六条裁决的落地对照**

| 裁决 | 落地位置 |
|---|---|
| ① 相机禁旋转（锁 45° 正交，禁一切旋转输入） | `CameraRig` 无任何旋转代码路径；`pan_to` 只改 `global_position`；`World._on_minimap_picked()` 在平移后**主动恢复** `camera.size` 与 `camera.rotation`（防御性冗余） |
| ② 资源缺失只 WARN 不崩 | `AssetLibrary.resource_for()` 命中失败 → `_warn_once()` + 占位（texture 2×2 白块 / model `PrismMesh`+`Label3D` 带 `placeholder` meta / font ThemeDB 回退 / material `StandardMaterial3D`）；`World._build_r8()` 读 `bgm.main` 失败静默 |
| ③ 19 条裁剪命令不造入口、`awaitInput` 仅 `victoryChoice` | 入口表恒 70 条；`R8ClientTest` 反向核对；`resolveChoice` 仍只认 `req_victory_*` |
| ④ 网格 / 边框纯显示层 | `Decorations` 只读 `view.tiles[]`/`view.sects[]`，不产生协议交互；`setSetting` 不下发 view |
| ⑤ 不改玩法与数值 | `data/gameConfig.json`、`commands.gd`、`CommandDispatcher`、`TurnProcessor`、`StateView` **一行未改**（PROTOCOL §11.3 已锁定） |
| ⑥ 不做多皮肤切换 | 只有 `default` 一套；`assets/manifest.json` 的 `skin` 字段未被新增分支消费 |

**Step 5 · 验收数字**
- `R8_CLIENT_RESULT=OK checks=44 failures=0`（单元：HUD 七模块 / 70 入口 / 置灰+blocker / 网格 / 边框 / 小地图 / 设置 / 引导 6 步 / Toast / 相机铁律 / 资源回退）
- `R8_CLIENT_RESULT=OK checks=59 failures=0`（端到端：hello 70 条 → 装饰层按真 view 生成 1131 条网格线 + 1 圈边框 + 352 个缩略点 → 小地图只平移 → 泼墨/存读档/结束回合/getState 全序列相机不变 → `setSetting` 不进 view → 资源栏 13 项有值）
- `ASSETVERIFY_OK covered=52 warned=0`（前置资源包）
- 回归全绿：服务端 `R1 79458` / `R2 220` / `R3 297` / `R4 174` / `R5 453` / `R6 317` / `R7 211`（`R7_IMPLEMENTED=70`）；客户端 `R1 58` / `R2 36` / `R3 43` / `R4 69` / `R5 95` / `R6 59` / `R7 77`
- `tools/check.ps1` 扩为 **24 阶段 175/175**（新增 `[21/24]` 客户端 R8 单元 + 端到端，原仓库扫描/协议契约顺延为 `[22/24]`/`[23/24]`），`check_protocol.ps1` 仍 **38/38**、`TODO(需核对)` 仍 **7 处**（L5/L1517/L1554/L1562/L1565/L1566/L1568）、69 分组点数不变

**偏差与未做项（诚实登记）**
- **昼夜是客户端本地计时，不与服务端回合同步**：R8 裁决五禁止改数值，回合数也不下发时间戳，故 `DAY_CYCLE_SECONDS=180` 是一个纯观感常量。副作用：读档/刷新 view **不会**重置昼夜相位（这是有意的——否则每次操作画面都会跳一下）。若后续要「昼夜跟着回合走」，需要服务端在 view 里补一个时间字段，属**协议变更**，不在 R8 范围。
- **泼墨转场首帧不播**：`_refresh_r8` 用 `_fog_states` 与上一帧比对，首次渲染时把当前三态全部记为基线而不播转场。否则一开局 352 格会同时泼墨，观感是「屏幕被糊住」而不是「迷雾揭开」。
- **网格重建有节流**：只在 `tiles.size() != _grid_tile_count` 时重建。否则每次 view 刷新都要销毁重建上千个节点（352 格 × 3 条边），R7 的 `endTurn` 序列会明显卡顿。
- **飞鸟/粒子是三角函数，不是物理**：`_animate_birds` 用纯 `sin`/`cos` 绕圈，不接 `RngService`。它们**不影响任何游戏状态**，也**不参与确定性断言**（`check.ps1` 的双跑 SHA256 只比服务端导出的权威地图）。
- **小地图点击跳转只平移、不居中到格心**：`pan_to` 把目标地面点平移到当前视口中心，但因为正交 45° 视角的「视口中心地面点」与「格心」在 y 方向有偏移，实际落点会略偏。**有意不修**——任何「顺手修正」都容易变成改 `rotation`/`size` 的借口，而相机铁律优先级更高。
- **设置项 `applied` 恒为 `false` 是正确的**：`setSetting` 的回包语义是「服务端收到了、但不改服务端状态」，客户端不应等 `applied=true` 才生效，否则设置面板会永远显示「未生效」。`SettingsPanel.on_setting_confirmed` 据此只更新状态文案。
- **资源包是程序化生成的「占位级美术」**：可复现、可审阅、零外部依赖，但**不是**成品美术。真实美术同名覆盖 `assets/art/default/**` 即可生效，无需改任何代码（`assets/README.md` 已写明覆盖方式与再生成命令）。

### 4.9 R8 视觉对齐参考图（收尾打磨，服务端零改动）

R8 交付后追加了一轮「按水墨长卷参考图贴近」的表现层改造。**只改表现层**：`data/gameConfig.json`、`commands.gd`、`CommandDispatcher`、`TurnProcessor`、`StateView` 与全部服务端文件**一行未改**；协议 70 条命令入口不变。

**新增 3 个文件**

| 文件 | 职责 | 关键设计 |
|---|---|---|
| `world/Scenery.gd` | 地图外围的层叠远山 + 流动云带 | 三层环状远山（每层 10 座，每座 3 个七棱锥叠成连绵山形）+ 8 片极淡云；半径以**取景包围盒**为基准（`0.60/0.73/0.86 × span`），且**只铺画面远侧半圈**（`(dx+dz) > 0.16·span` 跳过），否则近侧的山会挡住地块；颜色向背景纸色 lerp `0.62→0.86` 做空气透视；云 alpha 仅 `0.03~0.08` |
| `ui/UiTheme.gd` | 水墨 UI 主题工厂 | `paper()` 宣纸卡片（细金边 + 内边距）/ `bar()` 顶底栏纸带（只有下缘金线）/ `board()` 小地图深墨板 / `seal()` 正圆印章（`corner_radius=64`）/ `primary_button()`/`plain_button()` / `title_label()`/`body_label()`/`hairline()` / `resource_color()` 13 项资源各一工笔颜料色 |
| `tools/WorldShot.gd` + `.tscn` | **真实渲染截图**工具 | 拉起服务端 → `newGame(seed=864213, 26×18)` → 装配 `World` → 90 帧预热 → `RenderingServer.frame_post_draw` → `save_png("res://outputs/ui_preview_map.png")`。**必须非 headless**（否则无渲染设备），命令见文件头注释 |

**改造要点（按参考图逐项对齐）**

| 参考图特征 | 落地方式 |
|---|---|
| 宣纸米白底、大面积留白 | `Decorations._apply_day_phase` 的夜色由 `2b3542`（深蓝灰）改为 `cfcabc`（冷纸色），昼色 `efe9d9`；**未探索地块的柱/顶面照建但 `visible=false`**（节点与 meta 保留，`R1ClientTest` 的 `get_child_count()==2` 锚点不破），未知区即纯纸底 |
| 地图约占画面八成 | `_framing_bounds()` 取景系数 `1.15 → 0.84`、下限 `14 → 11`；并沿**屏幕右方**（世界 `(0.707,0,-0.707)`）平移半个侧栏宽，补偿右侧 320px 侧栏的遮挡 |
| 顶栏是横贯全屏的「纸带」 | `_build_topbar()` 全量重写：`UiTheme.bar()` + 左「第 N 回合」/「春 · 修行期」+ 13 项圆形资源徽章 + 右上圆形青玉「结束回合」印章。`topbar_resource_label` 保留为 `visible=false` 文本镜像，R2/R3/R4 断言不受影响 |
| 13 项圆形彩色徽章 | `_build_r8_resource_chips()`：`PanelContainer`（20×20，`seal(资源色.lerp(纸色,0.62))`）+ 13×13 图标 + 11 号字。**关键坑**：`TextureRect` 默认 `expand_mode=KEEP_SIZE` 会被 32×32 图标撑到 32px，13 项直接顶出屏幕——必须显式 `EXPAND_IGNORE_SIZE` |
| 左上小目标卡 | 新增 `_build_objectives_panel()` / `_render_objectives()`：取 `victory_progress.routes[0].goals` 前 3 条，`◇ 名称（进度/目标）`，达成转青玉色 |
| 右侧宣纸卡片（地块信息） | `_build_sidebar()` 重写为 `SideCard`：标题 / 类型·归属·海拔键值对 / 可获取资源 / 风物小注 / 事件 / 刷新·返回。新增 `_refresh_tile_card()`，未探索时显示「云雾未开，山形不可辨」 |
| 左下深墨小地图 + 金色视口框 | `UiTheme.board()` 底板 + `Minimap._rebuild_points()`（`PanelContainer` 异步改尺寸，必须在 `_draw()`/`tile_at()` 前重算）。**修掉一处真 bug**：视口框原先把世界坐标再除一次 `√3`，导致金框偏到左上角 |
| 底栏通栏纸带 | `ActionBar` 由 `offset_right = -SIDEBAR_WIDTH` 改为 `0.0`，样式换 `UiTheme.bar()` + 上缘金线 |
| 中式楼阁建筑 | `SectView._build_pavilion()` 重写：石台基（两级须弥座）→ 米色墙 + 4 朱红柱 + 额枋 → 宽出檐下檐（青瓦）→ 薄「平座」→ 二层墙 → 上檐（金瓦）→ 金色宝顶 + 屋脊金棱。**楼阁整体转 -45°**（正立面朝相机），屋顶再转 +45° 抵消（四坡顶仍与屏幕轴平行）；主峰 `tier_scale=1.40`、附属建筑 `0.78` |
| 竖幅宗门旗 | `_build_banner()`：细杆 + 横担（沿局部 z 铺，屏幕上才水平）+ 竖长旗面 + 逐字换行 `Label3D`。**关键坑**：`Label3D` 若只转 yaw，45° 俯视会把竖排字压成横杠——须 `rotation_degrees = (-45, 90, 0)` 让文字平面垂直于视线 |
| 单位小人 | `UnitView._build_figure()`：影子（贴地扁圆）→ 宗门色袍（圆台）→ 躯干（走 `_apply_class_silhouette`，`scale 0.46`）→ 头（球）+ 发冠（小方块）。`PLACEHOLDER_SHAPES` 10 项与 `_apply_class_silhouette` **一字未改**（R5 断言依赖） |
| 青绿山水配色 | `HexMap.base_color()`：灵田 `a8c48d` / 灵原 `b9cfa2` / 荒地 `cfbb95` / 默认 `e6e0cd`；侧面山岳 `5e7d70` / 丘陵 `98a583` / 平地 `bdbd9c`；网格线由深墨改**近白半透明** `Color(1,0.99,0.94,0.34)` |

**验收**
- 客户端单元 `R1 52 / R2 5 / R3 5 / R4 8 / R5 8 / R6 9 / R7 14 / R8 44` 全绿（`*_CLIENT_RESULT=OK failures=0`）
- `tools/check.ps1` **24 阶段全绿**；交付物清单 R8 由 16 项扩为 **20 项**（新增 `Scenery.gd`/`UiTheme.gd`/`WorldShot.gd`/`.tscn`）
- 截图工具可复现：`Godot --path client res://tools/WorldShot.tscn` → `outputs/ui_preview_map.png`（1600×900）

**偏差登记**
- **截图是「观感核对」而非「像素基线」**：`outputs/` 在 `.gitignore` 内，不参与 CI 断言。原因：不同 GPU/驱动的抗锯齿与阴影差异会让像素比对必然假红；真正的回归保护仍是 R1–R8 的结构断言。
- **远山只铺半圈**是有意为之：完整环在 45° 俯视下，近侧的山会压在地块前，观感像「山从地图里长出来」。若后续相机可自由旋转，需要按相机方向动态重铺（当前相机铁律锁定 45°，故静态铺一次即可）。
- **未探索格保留空节点**：为不破坏 `R1ClientTest` 的 `get_child_count()==2` 锚点，柱与顶面照建但隐藏。代价是每格多 2 个不可见 `MeshInstance3D`（`visible=false` 不参与绘制），352 格共 704 个空节点，实测无性能影响。

### 4.10 R8 追加：六套全屏界面 + 青云宗建筑群（按参考图制作，服务端零改动）

用户给了 7 张水墨仙侠参考图，要求「根据这张图制作」六个界面与一套建筑群。**仍然只改表现层**：`data/gameConfig.json`、`shared/commands.gd`、`CommandDispatcher`、`TurnProcessor`、`StateView` 与全部 `server/` 文件**一行未改**，协议 70 条命令入口不变。

**新增 11 个文件**

| 文件 | 对应参考图 | 职责 |
|---|---|---|
| `ui/RatioBar.gd` | — | 细进度条（`HBoxContainer` + 两段 `size_flags_stretch_ratio` 分配宽度）。**踩坑**：Godot 4 把 `stretch_ratio` 改名为 `size_flags_stretch_ratio`；且 `fill` 必须先于 `groove` 入树，否则填充跑到右侧 |
| `ui/ScrollFrame.gd` | 全部 | 共用卷轴外框：投影 + 宣纸 + 内金线 + 左右木轴（含金色轴头）+ 竖排题签 + 内容区 |
| `ui/TurnSummary.gd` | 仙门回合结算 | 回合结算卷轴：资源收支 / 重要事件卡 / 事件时间线三栏 + 「下一回合」药丸 |
| `ui/DaoTreeCanvas.gd` | 青云宗道法修行树 | 道法树画布：三次贝塞尔 12 段折线连边 + 节点圆 + 三态着色（已学 / 可研究 / 未解锁） |
| `ui/DaoTreePanel.gd` | 青云宗道法修行树 | 道统树全屏：三页签（宗门 / 家族 / 国家，标注实际条数）+ 树 + 悬浮详情卡 + 右栏（弟子修行 / 资源禀赋 / 突破记录 / 研究队列） |
| `ui/SavesScreen.gd` | 水墨仙侠存档界面 | 存档全屏：左导航 + 6 槽卷宗列表（程序化缩略图）+ 右详情卡 + 底部状态行 |
| `ui/CombatScreen.gd` | 水墨奇幻战场 | 战斗全屏：左上胜负条件卡 + 右列部队卡/胜率预估/地形加成 + 底部单位卡 + 右下五枚圆形动作钮 |
| `ui/VictoryScreen.gd` | 仙途终焉：九天胜境 | 胜利结算全屏：程序化天光背景（横带渐变 + 同心圆天光 + 尖峰山脊 + 云带 + 中央仙山 + 飞鹤）+ 大字「胜 利」+ 三路线徽记 + 最终结算卷轴 |
| `world/Buildings.gd` | 青云宗建筑概念设定集 | 十种建筑原型工厂（大殿 / 帝都 / 藏经阁 / 炼丹楼 / 合院 / 阵法台 / 灵植园 / 讲道台 / 祖祠 / 山门），全部 `BoxMesh`/`CylinderMesh`/`SphereMesh`/`TorusMesh` 程序化拼装 |
| `tools/BuildingShot.gd` + `.tscn` | 青云宗建筑概念设定集 | 建筑原型实拍：十个原型沿「屏幕右方向」一字排开，2D 覆盖层标签钉在脚下 |

**关键设计决策**

| 决策 | 理由 |
|---|---|
| **隐藏断言镜像**：旧面板结构一字不动，只把外层容器 `visible = false` | `R4ClientTest` 依赖 `dao_list` 的 26 个节点、`Dao_<id>` 按钮、`dao_title_label.text`；`R7ClientTest` 依赖 `saves_info_label` 含「槽 0」与 `Save_%d`/`Load_%d`。新界面若直接替换旧面板，两条断言链全断。镜像后 R4 69/69、R7 77/77 原样通过 |
| **数据全部取真实回包，不造假** | 回合结算的资源增减 = 「本回合首帧 view」与「当前 view」的 13 项资源**算术相减**（协议 2.0 不下发结算报告）；事件取 `Session.events_received` 累积的 `event_lines`；道统树读 `daoOptions[]`/`unlockedDaoIds[]`/`projectQueue.researchQueue`；存档只用 `listSaves` 的 7 个字段；战斗读 `preview.winChance/attackerPower/defenderPower/...`；胜利读 `queryVictoryProgress.routes[]` |
| **协议没有的能力就置灰并写明原因** | 「待机」按钮 `disabled`，tooltip 写「协议 2.0 无 wait/skip 命令」；存档「删除」按钮同理（无 `deleteSave`）。不伪造一个点不动的按钮，也不假装它可用 |
| **存档回包无缩略图、无难度** | 缩略图由 `SaveThumb._draw()` 用「槽位号派生」的确定性伪随机墨块地图程序化生成；难度整行不做（宁可少一行，也不编一个值） |
| **战斗界面打开时快照并隐藏常驻 HUD** | 否则地块卡/事件/目标/单位卡会叠在战斗卡上。`open_combat_screen()` 记录 `hud_layer / city_panel / unit_panel` 的 `visible`，关闭时原样还原并重绘单位卡 |
| **相机铁律不破** | 六套界面都是 `CanvasLayer`，从不触碰 `CameraRig` 的 transform/size；截图工具也只在 `_ready()` 里设置一次相机 |

**按参考图逐项对齐**

| 参考图特征 | 落地方式 |
|---|---|
| 回合结算：整幅卷轴 + 左竖排题签 | `ScrollFrame.build(title, 56, 0.975)`：题签竖排（逐字换行 `Label`）+ 左右木轴 + 金色轴头。卷轴高取 **470** 而非更高——结算内容通常只有 4~6 行资源 + 2~3 张事件卡，再高下半幅就空着 |
| 道法树：树状连线 + 三态节点 | `DaoTreeCanvas._draw()` 用三次贝塞尔 12 段折线，纵向按 `_resolve_depth()`（`guard > 8` 防环）分层；节点三态：已学（青玉实心）/ 可研究（金边空心）/ 未解锁（灰边） |
| 存档：左侧卷宗导航 + 中间槽位列表 + 右侧详情 | 左导航 5 项 + 题诗「执一卷天书 观万界沉浮」+ 朱印「录」；中 6 槽 `ScrollContainer`（槽卡 = 序号徽章 + 缩略图 + 宗门名 + 流派药丸 + 回合/时间/体积 + 读/存/删）；右详情卡（缩略图 + 槽位 + 回合 + 时间 + 体积 + 宗门信息/势力范围/存档文件） |
| 战场：左上条件卡 + 右侧部队卡 + 底部单位卡 + 圆形动作钮 | 单位卡五项属性用「字形 + 中文名」两行（只写字形看不出是什么，加中文名后 45px 高的胶囊才读得懂）；五枚动作钮 `Combat_move/attack/dao/wait/retreat` |
| 胜利：大字标题 + 天光 + 仙山 | `VictoryBackdrop._draw()`：64 条横带「暖白→淡青→青灰」渐变 + 16 层同心圆天光 + 4 层 `abs(sin)` 尖峰山脊 + 3 条云带（每簇 4 枚递减小圆）+ 中央仙山（主峰/双侧峰/山顶楼阁/两侧瀑布）+ 4 只飞鹤 |
| 建筑群：青琉璃瓦 + 金脊 + 朱柱 + 玉台栏杆 + 宝顶 | `Buildings` 十原型共用 `_platform`（须弥座 + 玉栏杆 + 望柱）/ `_body`（米墙 + 朱柱 + 额枋 + 正面门窗）/ `_roof`（四坡攒尖 + 檐口压深 + 四角翘檐 + 金脊）/ `_finial` / `_spire`（蓝晶尖塔） |

**踩过的坑（都已修）**

| 现象 | 根因 | 修法 |
|---|---|---|
| 新界面报 `Could not find type "SavesScreen"` | 新 `class_name` 未注册 | 先跑 `--headless --path client --import`，`global_script_class_cache.cfg` 出现 6 处引用后即恢复 |
| 存档界面顶行被压成「一字一行竖排」、整屏被撑高 | `UiTheme.body_label()` 默认 `AUTOWRAP_WORD_SMART`，放进横向 `HBoxContainer` 会被压成窄条 | 横排里的 `Label` 必须显式 `autowrap_mode = TextServer.AUTOWRAP_OFF` |
| 建筑坡顶塌成一块蓝板 | 檐口 0.50 配举高 0.20 只有 22° | `_roof()` 统一按 `eave_radius × 0.66` 兜底，并**返回实际举高**，调用方用返回值累加 Y |
| 山门两根柱子叠成一根、合院厢房互相遮挡、门窗转到看不见的侧棱 | 根节点 `rotation.y` 取成 `-45°`，局部 ±X 正好落在视线方向上 | 改 `+45°`：局部 +X = 屏幕横向，局部 +Z = 正对相机（门窗/台阶/香案才可见） |
| 屋檐四角翘檐从瓦面中部横着扎出来，轮廓像蝴蝶结 | 屋面转 45° 后顶点在**对角**方向，翘檐却摆在 ±X/±Z 的檐面中点 | 翘檐挂到四角 `(±0.707r, ±0.707r)`，用 `Node3D` 支点把 +X 指向朝外对角再上翘 30° |
| 合院厢房屋顶比它下面的墙还高，像帐篷 | 小体量构件套用 0.66 的举高比 | `_roof()` 增加 `pitch` 参数，厢房 0.42 / 塔层 0.44 / 伞盖 0.34 |
| 建筑群截图里十个建筑挤在画面中央一小点、后排被前排遮住 | 相机沿世界 X 轴排开，而 45° 正交下世界 X 与屏幕横轴不等价 | 沿**屏幕右方向** `(0.7071, 0, -0.7071)` 排开，并把相机沿自身 forward 反推到 `(6, 8.49+LOOK_AT_Y, 6)` |
| 建筑群截图标签被地面挡住、被正交相机压扁 | `Label3D` 在正交 + 45° 下既会被压扁又会被地面遮挡 | 改用 2D 覆盖层 + `camera.unproject_position()` 钉在每座建筑脚下，字号恒定 |
| 胜利界面「胜 利」与副题重叠 | 标题占位 84~246、副题 250~276，间距不够 | 标题收到 84~246，副题加白色 shadow outline 8，三路线徽记下移到 286~410 |
| 胜利界面卷轴下方露出一截灰色楔形 | 中央仙山山脚画到 `0.82h`，而卷轴只到 `0.764h` | 山脚收到 `0.75h`（藏在卷轴后面） |
| 胜利界面「未解锁」小字被卷轴上沿切掉一半 | 卡片顶边 420 与徽记行 410 只差 10px | 卡片顶边移到 452、高度 268→244 |

**验收**
- 客户端单元 `R1 52 / R2 5 / R3 5 / R4 69 / R5 8 / R6 9 / R7 77 / R8 44` 全绿（R4/R7 带 `--integration`）
- `tools/check.ps1` **24 阶段全绿**；交付物清单 R8 由 20 项扩为 **31 项**
- 截图可复现：
  - `Godot --path client res://tools/WorldShot.tscn` → `ui_preview_map / turn_summary / dao_tree / saves / combat / victory .png`
  - `Godot --path client res://tools/BuildingShot.tscn` → `ui_preview_buildings.png`
  - 两者都**不能加 `--headless`**（否则无渲染设备）

**偏差登记**
- **道法树页签是纯展示过滤**：配置里只有 4 条道法带 `factionOnly` / `requiresBloodLine`，所以「宗门 21 / 家族 2 / 国家 1」是客户端按字段过滤出的条数，不是新的规则判定。
- **道统树画布不撑满容器**：画布最小宽度由「最宽一层的列数」算出（约 640px），比容器窄时会靠左，右侧留白。这是 `ScrollContainer` 的默认行为，不影响可读性，故未强改。
- **战斗「战力」显示「—」**：`preview.attackerPower` 需要先选目标，未选时服务端不给值，界面如实显示破折号而不是 0。
- **建筑群截图是「原型图册」不是「对局截图」**：开局只有 1~2 座建筑，光靠地图截图看不全十种形制，故单独做 `BuildingShot`。它不入 CI，只用于肉眼比对参考图。

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
