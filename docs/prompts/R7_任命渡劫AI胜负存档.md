# R7 任务提示词：任命/血脉 + 渡劫飞升 + 反应式 AI + 三流派胜负/分数 + 存档读档 + 待抉择

> 状态：**草案（预生成）**。进入本里程碑前，必须按当时最新代码/config 重新核对全部文件锚点与数值后再执行。
> 建议专家：**Godot 游戏脚本工程师**（Godot 4.4 / GDScript 静态类型）
> 前置：**R0–R6 已完成且 `tools/check.ps1` 全绿**（R6 提交见 `docs/ROADMAP_2.0.md` §一）。**若前置里程碑实际交付与本文件所述锚点不一致，一律以当时代码/config 为准。**
> 本里程碑产出：**能任命峰主/长老/宗主、渡劫飞升、让三家 AI 行动、打到三流派胜负与 240 回合分数、存读档、处理胜利择一待决**的完整一局闭环。
> 本里程碑在你当前 worktree 根目录执行；开工先跑任务 0。

---

## 本里程碑范围（一句话）

实现 PROTOCOL_2.0.md 中归属 R7 的 **14 条命令**：`listSaves`、`saveGame`、`loadGame`、`queryVictoryProgress`、`checkVictory`、`checkDefeat`、`chooseVictory`、`queryGameOver`（会话组）、`tribulate`、`appointFengZhu`、`appointZhangLao`、`appointZongZhu`（单位组）、`queryVictoryChoice`、`resolveChoice`（待抉择组）；落地**任命（峰主/长老/宗主）与血脉**、**渡劫飞升**、**反应式基础 AI（三流派加权）**、**三流派胜负与分数胜利**、**存档/读档/自动存档**、**胜利择一 `awaitInput` 与 `resolveChoice`**，并把 **`AI_ACTION`、`VICTORY_CHECK`、每 10 回合自动存档、宗主外出检查**从 R2–R6 的空壳填实。

## 开工前必读（只读，禁止自创规则/数值/字段）

1. `docs/REQUIREMENTS_2.0.md`：
   - **§4.12 任命 / 血脉 / 传送 / 集结**（长老上限 2+每势力等级 1、峰主 +气运5/灵力 +30%、长老修炼 +10%/研究 +10%、宗主坐镇大殿才有全局加成且外出失效、宗门流宗主陨落且无金丹以上继承人即败；血脉：婚娶 50 石、繁衍 120 石+60 工/冷却 5、品级抖动 25%/上变 5%/多灵根 +15%/高品阈值 4、族人死亡安定 −5）；
   - **§4.15 胜利与失败**（宗门流/家族流/国家流三条件、分数公式、失败条件、同时达成发 `awaitInput` 择一、AI 取招牌路线）；
   - **§4.16 基础 AI**（反应式启发式、`attackMinWinChance` 0.55、优势阈值 1.2、三流派倾向加权、难度行动点/补贴/倍率；**删除性格/长期战略/外交议程**）；
   - **§4.4 弟子系统**（渡劫数值）、**§4.5 回合流程**（`AI_ACTION` 后刷新 AI 迷雾、`VICTORY_CHECK` 未结束回 `TURN_START`、终局冻结、**每 10 回合自动存档槽 0**、240 回合强制分数结算）、**§4.6 资源体系**（`powerLevel` 权重）、**§2.6 存档**、**§6.3 主动消息 `awaitInput`**、**§6.5 view**、**§6.7 命令清单**。
2. `docs/PROTOCOL_2.0.md`：**§2 会话与存档（13）** 的 `listSaves`（288）、`saveGame`（300）、`loadGame`（317）、`queryVictoryProgress`（334）、`checkVictory`（351）、`checkDefeat`（368）、`chooseVictory`（385）、`queryGameOver`（402）；**§3 单位（22）** 的 `tribulate`（738）、`appointFengZhu`（755）、`appointZhangLao`（773）、`appointZongZhu`（791）；**§8 待抉择（2）** 的 `queryVictoryChoice`（1406）、`resolveChoice`（1418）。**字段以该处为最终准据，一字不增不减**。
   - **§0.7 主动消息**：`awaitInput` 仅 `victoryChoice`（`{type,reqId,kind:"victoryChoice",prompt,options[{index,label,routeId,description}]}`）；**§11.1 冲突 #7** 保持；`loadGame` 后若有待决**重新推送**。
   - **§11.2 待办 #1**（`AppointmentResult` 形状）、**#3**（`queryVictoryProgress.routes[].goals` 内部形状）→ **按本文件「已裁决冲突」处理，不得臆造**。
3. `data/gameConfig.json`（2.0 数值唯一权威，本里程碑涉及的键必须逐个定位到行）：
   - `appointment`（`zhangLaoBaseLimit` 2 / `zhangLaoPerPowerLevel` 1 / `fengZhuQiYunBonus` 5 / `fengZhuSpiritPowerBonus` 0.3 / `zhangLaoCultivationBonus` 0.1 / `zhangLaoResearchSpeedBonus` 0.1 / `zongZhuDaDianQiYunBonus` 10 / `zongZhuDaDianSpiritPowerBonus` 0.2）；
   - `faction.bloodline`（`marryCostStones` 50 / `reproduceCostStones` 120 / `reproduceCostWorkPower` 60 / `reproduceCooldownTurns` 5 / `gradeJitterChance` 0.25 / `gradeMutationUpChance` 0.05 / `extraRootChance` 0.15 / `highGradeRootThreshold` 4 / `bloodlineDeathStabilityPenalty` 5）、`faction.zongMen`/`jiaZu`/`guoJia`（流派特性）、`faction.flavors`；
   - `victory`（`maxTurns` 240 / `scoreVictoryEnabled` true / `zongMen{daoCompletionRatio:1.0,coreDaoIds:[fei_sheng,hun_yuan],powerLevel:140,minPeaks:10,...}` / `jiaZu{ascensionCount:4,minClanMembers:12,minHighRealmMembers:3,highRealmLevel:4,...}` / `guoJia{claimedTileRatio:0.2,minControlledTiles:24,requireAllOwnedPeaks:false,minPeaks:2,...}` / `score{powerLevelWeight:1.0,ascensionWeight:12.0,claimedTileShareWeight:40.0,daoCompletionWeight:30.0,peakWeight:3.0}`）；
   - `ai`（`actionPoints` 5 / `aggression` 0.4 / `expansionTendency` 0.5 / `exploreTendency` 0.3 / `maxGarrisonPerNode` 2 / `minDisciplesForGarrison` 3 / `recruitPerPeak` 2 / `clanMemberTarget` 20 / `uniqueUnitTarget` 3 / `bloodlineTendency` 0.5 / `researchTendency` 0.4 / `combatAdvantageThreshold` 1.2 / `attackMinWinChance` 0.55 / `trainUnitChance` 0.35 / `powerPoorThreshold` 150 / `expansion*Bonus/Penalty`）；
   - `difficulty.levels.{easy,normal,hard}`（`aiActionPoints` 4/5/6、`aiStartStonesBonus` 0/0/600、`aiStartWorkPowerBonus` 0/0/300、`aiAggressionMultiplier` 0.7/1.0/1.3、`aiExpansionMultiplier` 0.7/1.0/1.2、`playerStartStonesBonus` 500/0/0）；
   - `powerLevel`（`tilesPerLevel` 5 / `highRealmDiscipleWeight` 2 / `unlockedDaoWeight` 1 / `buildingLevelWeight` 1）、`speed`（`animationScale`/`autoPlayIntervalMs`/`fastSettlementDefault`/`batchMoveMaxTargets`）、`saveVersion` "3.0"、`disciple.cultivation.tribulation*`。
4. **1.0 只读蓝本（禁止改动旧仓库 `C:\Users\Administrator\IdeaProjects\xiuxianGame`，只用于核对算法与字段）**：
   - `core\GameEngine.java`：`loadState()`（189）、`executePhase()`（206）、`checkVictory()`（236）、`achievedRoutes()`（242）、`victoryProgress()`（252）、`chooseVictory()`（265）、`refreshPowerLevel()`（282）、`checkDefeat()`（286）、`eliminateReason()`（311）、`processVictoryCheck()`（316）、`settleVictory()`（340）、`collapseSect()`（359）；
   - `action\AppointmentAction.java`：`appointFengZhu()`（20）、`appointZhangLao()`（66）、`appointZongZhu()`（103）、`promoteDisciple()`（143）、`canAppoint()`（174）、`dismissPosition()`（195）、`countPosition()`（222）；
   - `action\BloodlineAction.java`：`marry()`（69）、`reproduce()`（131）、`inheritChild()`（163）、`inheritRoots()`（203）、`withinCooldown()`（262）、`isCloseKin()`（277）；
   - `save\SaveManager.java`：`saveGame()`（47）、`loadGame()`（68）、`migrateLegacyRareMaterials()`（98）、`listSaves()`（112）、`autoSave()`（144）、`saveFileName()`（160）、`isVersionCompatible()`（164）、`readSaveInfo()`（173）、`findPlayerSect()`（199）；`save\SaveInfo.java`；
   - `core\AIController.java` / `core\AIDecision.java`（反应式启发式；**删除性格/长期战略/外交议程**，见「已裁决冲突」）；
   - `entity\AppointmentResult.java`（形状核对，见裁决二）。
5. 2.0 现有代码（在其上扩展）：`shared/protocol/{commands,enums,msg,dto}.gd`、`server/scripts/{net/{CommandDispatcher,NetServer,StateView}.gd,rules/{TurnProcessor,DiscipleRules,DaoRules,UnitRules,CombatResolver,PolicyRules,AutomationRules,EconomyRules}.gd,model/*}`、`client/scenes/{Main,MainMenu,World}.gd`、`client/scripts/net/Session.gd`。

## 硬约束（违反即返工）

1. **完全 Godot 4.4 + GDScript 静态类型，零 Java**；全仓库无 Java。
2. **服务端权威、客户端零规则**：客户端**不实现任何胜负判定/分数/任命门控/AI 决策**；「能不能任命、进度几何、谁赢了」一律来自 `queryVictoryProgress`/`checkVictory`/`checkDefeat`/`queryGameOver`/`queryVictoryChoice` 与 `view`。
3. **规则、数值唯一权威是 `data/gameConfig.json` 与服务端 `rules/`**；**不新增命令、不新增错误码、不发明 result/events 字段**。错误码只用 `msg.gd` 既有 8 码。
4. **业务失败 ≠ 协议失败**：任命名额已满、境界不足、渡劫条件不满足、存档槽不存在、路线未达成等一律 `ok:true + result.success:false + result.message`；只有参数缺失/枚举非法才 `BAD_PARAMS`。**存档类命令 `saveGame` 用固定形状 `{slot, saved}`（+失败时 `message`），不使用写命令通用的 `success` 布尔**（PROTOCOL §2 明列，1.0 D5 已拍板）。
5. **相机铁律**：锁 45° 正交、禁旋转；任命、渡劫、存读档、结局屏、AI 行动、任何 view 刷新后，`CameraRig` 的 transform 与 `size` 都**不得重置**。
6. **确定性**：同种子 + 同指令序列，任意次数跑结果逐字一致；**所有随机只经 `RngService`**（AI 决策掷骰、渡劫成败、血脉品级抖动、AI 攻击选择）。**AI 行动必须走同一 `RngService`**，不得引入非确定性来源。
7. 新增 `class_name` 后必须对两工程分别 `--import`；任何 Agent 跑通后无残留 godot 进程。
8. 表现层只读 `view`；R7 只用占位资源，结局屏/存档菜单为**占位 UI**，正式 HUD 在 R8。

## 已裁决冲突（按本提示词执行，禁止自由裁量）

- **裁决一（AI 用 2.0 反应式启发式，删 1.0 性格/长期战略/外交议程）**：2.0 按 §4.16 与 §5.2 #6 **删除性格系统（好战/图治/纵横）、长期战略复盘、外交议程**；攻击**不检查宣战**（§5.2 #1）。AI 行为只由 `ai.*` 与 `difficulty.levels.*` 驱动：扩张（开峰/修路/抢点）、战斗（`attackMinWinChance` 0.55 且优势 ≥ `combatAdvantageThreshold` 1.2 才打）、研究、驻守、经济，按 `faction` 倾向加权。**不得迁移 1.0 `StrategyService`。**
- **裁决二（`AppointmentResult` 形状：`TODO(需核对)` 的落地口径）**：PROTOCOL §11.2 #1 记 `AppointmentResult` 形状 1.0 未展开。**不得臆造**：实现前必须回 1.0 `entity\AppointmentResult.java` 与 `bridge\CommandDispatcher.java` 逐字段核对；**若核对成功，按 1.0 字段落地并在 `docs/PROTOCOL_2.0.md` §11.2 #1 标注「已回填（R7）」并补 §3 的 `appoint*` result 展开**；**若仍无法确证，则暂以最小同构形状落地（`{success, message, discipleId, position, peakId}`，字段均须能在 1.0 或 config 找到依据），并在 §11.2 #1 追加「R7 暂以最小同构形状落地，待核对」——两者二选一，必须在汇报中说明。**
- **裁决三（`queryVictoryProgress.routes[].goals` 内部形状：`TODO(需核对)`）**：PROTOCOL §11.2 #3 同样未展开。**同一口径**：先回 1.0 `core\GameEngine.victoryProgress()` / `VictoryProgress` 核对；核对成功则回填并标注「已回填（R7）」；否则以能追溯到 1.0 或 config 的最小同构形状落地（`{label, current, required, achieved}`）并在 §11.2 #3 追加说明。
- **裁决四（胜负条件取 config，非硬编码）**：宗门流 = `zongMen.daoCompletionRatio` 1.0（含 `coreDaoIds`）+ `powerLevel` ≥140 + `minPeaks` ≥10；家族流 = `jiaZu.ascensionCount` 4 + `minClanMembers` ≥12 + `minHighRealmMembers` ≥3（`highRealmLevel` 4）；国家流 = `guoJia.claimedTileRatio` ≥0.2 + `minControlledTiles` ≥24 + `minPeaks` ≥2。**全部读 config。**
- **裁决五（分数公式与 240 回合强制结算）**：`score = powerLevel×1 + 飞升×12 + 地块份额×40 + 道法完成×30 + 灵峰×3`（`victory.score`）；达 `victory.maxTurns` 240 时强制分数结算（`scoreVictoryEnabled` 为真）。
- **裁决六（`powerLevel` 不是声望折算）**：`powerLevel` = 领地数÷`tilesPerLevel` + 高境界弟子×`highRealmDiscipleWeight` + 已解锁道法×`unlockedDaoWeight` + 建筑等级×`buildingLevelWeight`（PRD §4.6/附录 B 明示）。**不得用声望折算。**
- **裁决七（`awaitInput` 仅 `victoryChoice`；`resolveChoice` 只分派 `req_victory_*`）**：同时达成多条路线时发 `awaitInput(kind="victoryChoice")`；`resolveChoice` 越界回 `BAD_PARAMS` **且待决状态原样保留**；`loadGame` 回到待决点**重新推送** `awaitInput`（PROTOCOL §2/§6.3）。**不实现 `randomEvent` 待决。**
- **裁决八（存档版本 `3.0`，`migrateLegacyRareMaterials` 保留）**：`Msg.SAVE_VERSION` = "3.0"；`isVersionCompatible` 语义沿用 1.0；`legacyRareMaterialConversion{tian_jing:1}` 迁移保留。**存档目录/文件名规则沿用 1.0，但**路径须落在项目 `saves/`（见 `docs/ROADMAP_2.0.md` 目录约定），**不入库**。
- **裁决九（每 10 回合自动存档槽 0）**：`VICTORY_CHECK` 中 `turn % 10 == 0` 时自动存槽 0（PRD §4.5）；回填 R2 留的自动存档 TODO。

---

## 任务 0：前置门禁（必须先全绿）

1. `powershell -NoProfile -ExecutionPolicy Bypass -File tools\setup_shared.ps1` 幂等挂载目录联接。
2. 两工程各跑一次 `--headless --path <proj> --import`，无解析错误。
3. `powershell -NoProfile -ExecutionPolicy Bypass -File tools\check.ps1` **全绿 `CHECK_RESULT=OK`**（R0–R6 断言不得回归）。
4. 确认**无残留 godot 进程**、无 `.java`、`saves/` 目录存在且**不入库**（`.gitignore`）。
5. 若第 3 步不绿，**停下报告**。

---

## 任务 1：配置与模型（服务端）

1. `data/gameConfig.json`：**R7 不新增顶层块**（`appointment`/`ai`/`faction`/`victory`/`powerLevel`/`difficulty`/`speed` 均已存在）。核对 §4.12/§4.15/§4.16 所列键，缺则**停下报告**，不得自造。
2. `server/scripts/model/` 扩充（纯数据 + `to_dict()`）：
   - `GameState.gd`：**按需新增** `winType: String`、`winnerSectId: String`、`pendingVictoryChoices: Array`（`view` 已声明这三字段，R1 恒空）。
   - `Sect.gd`：**按需新增** `powerLevel: int`（派生缓存）、`defeated: bool`、`lastAutoSaveTurn: int`（内部）。
   - `Disciple.gd`：`position`/`bloodLine`/`generation`/`directLine`/`capturedFromSectId` 等已就绪；**按需新增** `ascended: bool`（飞升候选/已飞升）。
   - 新增 `server/scripts/model/SaveInfo.gd`（`class_name SaveInfo`）：`slotId/turn/playerSectName/factionType/savedAt/filePath/fileSize`（对齐 PROTOCOL §2 `listSaves`）。

---

## 任务 2：任命/血脉/AI/胜负/存档规则（服务端 `server/scripts/rules/` + `save/`，新建）

全部静态、无状态、只读 `config`，数值只取自 `data/gameConfig.json`。

1. **新建 `AppointmentRules.gd`**（对齐 1.0 `AppointmentAction`）：
   - `can_appoint(state, config, disciple, position) -> String`（境界/名额/血缘门槛；长老上限 = `zhangLaoBaseLimit` + `powerLevel`×`zhangLaoPerPowerLevel`）；
   - `appoint_feng_zhu`/`appoint_zhang_lao`/`appoint_zong_zhu`（变更 `position`/`fengZhuId`，应用 `appointment.*` 加成）；
   - `dismiss_position`、`count_position`；
   - `zong_zhu_outside_bonus_active(state, config, sect) -> bool`（宗主是否坐镇大殿；**回填 R2 留的「宗主外出」TODO**）。
2. **新建 `BloodlineRules.gd`**（对齐 1.0 `BloodlineAction`，仅家族流有效）：
   - `marry`/`reproduce`（耗 `marryCostStones` 50 / `reproduceCostStones` 120 + `reproduceCostWorkPower` 60、冷却 `reproduceCooldownTurns` 5、祖祠折扣 `zuCiReproduceCostReduction`）；
   - `inherit_roots`（`gradeJitterChance` 0.25 / `gradeMutationUpChance` 0.05 / `extraRootChance` 0.15 / `highGradeRootThreshold` 4）；
   - `on_clan_death(state, config, sect)`（安定 −`bloodlineDeathStabilityPenalty` 5）。
   - **注**：血脉**没有独立命令**（PROTOCOL 69 条中无 marry/reproduce），故本规则**只由 AI 与内部结算调用**；若需玩家入口，**不得新增命令**，须在汇报中说明未提供玩家入口。
3. **新建 `AIController.gd`**（对齐 1.0 `AIController`，但按裁决一裁剪）：
   - `run_turn(state, config, sect) -> Array[String]`（按 `ai.actionPoints`（受 `difficulty.levels.*.aiActionPoints` 覆盖）逐点决策：扩张/战斗/研究/驻守/经济/收徒/血脉；受 `ai.*` 与 `faction` 倾向加权）；
   - `choose_attack_target`（`attackMinWinChance` 0.55 + `combatAdvantageThreshold` 1.2）、`choose_expansion_tile`（`expansion*Bonus/Penalty`）、`choose_research`（`researchTendency`）、`choose_garrison`（`maxGarrisonPerNode`/`minDisciplesForGarrison`）。
4. **新建 `VictoryRules.gd`**（对齐 1.0 `GameEngine` 的胜负部分）：
   - `refresh_power_level(state, config, sect)`（裁决六）；
   - `achieved_routes(state, config, sect) -> Array`、`victory_progress(state, config, sect) -> Dictionary`（对齐 PROTOCOL §2 `queryVictoryProgress`）；
   - `check_victory(state, config, sect) -> String`（返回 `route` 或空）、`check_defeat(state, config, sect) -> bool`（弟子全灭/灵峰全失/宗门流宗主陨落且无金丹以上继承人）；
   - `process_victory_check(state, config)`（**`VICTORY_CHECK` 唯一入口**：判定 → 多条路线发 `awaitInput` → 终局冻结 → **每 10 回合自动存档**（裁决九）→ 240 回合强制分数结算）；
   - `compute_score(state, config, sect) -> int`（裁决五）。
5. **新建 `server/scripts/save/SaveManager.gd`**（对齐 1.0 `SaveManager`，用 `FileAccess` + `JSON`）：
   - `save_game(state, config, slot) -> Dictionary`（`{slot, saved}` + 失败 `message`）、`load_game(slot) -> Dictionary`（`{slot, turn}`）、`list_saves() -> Array`、`auto_save(state) -> bool`、`is_version_compatible(version)`、`migrate_legacy_rare_materials(state)`；
   - 存档目录：项目 `saves/`（**不入库**）；文件名规则沿用 1.0；`saveVersion` "3.0"。
6. **回填 R2–R6 空钩子**（`TurnProcessor.gd`）：
   - `_run_ai_action()`：`AIController.run_turn()` × 未覆灭 AI 宗门 + 刷新其迷雾（**回填 R2 留的 AI TODO**）；
   - `_run_victory_check()`：`VictoryRules.process_victory_check()`（**回填 R2 留的胜负 TODO**）；
   - `_run_turn_start()`：`AppointmentRules.zong_zhu_outside_bonus_active()`（**回填 R2 留的宗主外出 TODO**）。

## 任务 3：命令处理器（服务端 `server/scripts/rules/` + `net/`）

- `AppointmentAction.gd`：`tribulate`（**R4 已实现规则函数，此处只注册命令**，裁决见 R4 裁决六）、`appoint_feng_zhu`、`appoint_zhang_lao`、`appoint_zong_zhu`。
- `VictoryAction.gd`：`query_victory_progress`、`check_victory`、`check_defeat`、`choose_victory`、`query_game_over`、`query_victory_choice`、`resolve_choice`。
- `SaveAction.gd`：`list_saves`、`save_game`、`load_game`。
- 在 `CommandDispatcher` 注册 14 个 handler；只读命令 view=null；`loadGame` 回 view + **待决时追加 `awaitInput`**；未开局 `NO_GAME`；枚举非法 `BAD_PARAMS`；业务不允许 `ok:true + success:false`（存档类用 `{slot, saved}`）。
- **主动消息**：`CommandDispatcher`/`NetServer` 需支持在响应后**推送 `awaitInput`**（新出现时推一次；`loadGame` 回到待决点重新推）。

---

## 任务 4：协议登记（`shared/` + `docs/`）

1. `shared/protocol/commands.gd` 新增 14 个常量（值 = 对应 lowerCamelCase 命令名）：`LIST_SAVES`、`SAVE_GAME`、`LOAD_GAME`、`QUERY_VICTORY_PROGRESS`、`CHECK_VICTORY`、`CHECK_DEFEAT`、`CHOOSE_VICTORY`、`QUERY_GAME_OVER`、`TRIBULATE`、`APPOINT_FENG_ZHU`、`APPOINT_ZHANG_LAO`、`APPOINT_ZONG_ZHU`、`QUERY_VICTORY_CHOICE`、`RESOLVE_CHOICE`。
2. `CommandDispatcher._init` 注册 14 个 handler（hello 自动下发 → 累计 **70 条**，即 **69 + ping 全覆盖**）。
3. `docs/PROTOCOL_2.0.md`：把这 14 条「状态」由 `待实现（R7）` 改为 `已实现（R7）`，§1 命令总表同步（**全部 69 条 + ping 均标「已实现」**）；**按裁决二/三回填 §11.2 待办 #1/#3**；§11.1 #7 保持。
4. `tools/check_protocol.ps1`：**69 分组点数不变**；动态断言自动覆盖新 14 条，并断言**「已实现 = 69 + ping」全量**。

## 任务 5：客户端交互（`client/`，只表现，不推规则）

- `scripts/net/Session.gd`：新增 14 条 `request_*` 包装 + `victory_progress_received`/`victory_choice_received`/`saves_received` 信号；**新增 `await_input` 信号**处理服务端主动推送的 `awaitInput`。
- `scenes/World.gd` / `MainMenu.gd`：
  - **胜利进度面板**：`queryVictoryProgress` 展示三路线 `routes[]`（`achieved`/`ratio`/`summary`/`stage`/`score`/`goals`）；
  - **结局屏**：`queryGameOver`/`checkVictory`/`checkDefeat` 结果展示 `winType`/`winnerSectId`；多条路线时弹 `awaitInput` 选项 → 发 `resolveChoice`；
  - **存档菜单**：`listSaves` 列表 → `saveGame`/`loadGame`；读档后按 `view` 重建；
  - **任命入口**：弟子详情面板增加「任命峰主/长老/宗主」（发 `appoint*`）与「渡劫」（发 `tribulate`）；
  - **AI 回放**：`events` 中 AI 行动文案在侧栏/事件栏展示（占位，真回放在 R8）。
- 所有新操作与 view 刷新后**保持相机 transform/size**。

---

## 自动验收（扩展 `tools/check.ps1`，全部通过）

**服务端（新建 `server/tests/R7Test.gd` + `.tscn`，无头打印 `R7_PASS checks=N`，退出码 0；勿改动 R1–R6 测试）**：

1. **任命**：`appointFengZhu`/`appointZhangLao`/`appointZongZhu` 名额 = `zhangLaoBaseLimit` 2 + `powerLevel`×1；境界不足/名额满返回 `success=false`；峰主 +气运5/灵力 +30%、长老修炼 +10%/研究 +10% 生效；宗主坐镇大殿才有全局加成，**外出失效**。
2. **血脉**：`marry`/`reproduce` 耗 50 石 / 120 石 + 60 工；冷却 5 回合；品级抖动 0.25/上变 0.05/多灵根 0.15 按独立复算 RNG 校验；族人死亡安定 −5。
3. **渡劫**：`tribulate` 成功率 = 独立复算值；失败心魔 +50 且按 `tribulationFailFallChance` 陨落；成功即飞升候选。
4. **AI**：固定种子下 `AI_ACTION` 阶段三家 AI 各按 `ai.actionPoints`（难度覆盖）行动；攻击仅在 `winChance ≥ 0.55` 且优势 ≥1.2 时发起；AI 行动后其 `visibleTiles` 刷新；**AI 不检查宣战**。
5. **胜负**：三流派各构造达成场景 → `checkVictory` 返回对应 `route`；未达成返回 `null`；`checkDefeat` 对弟子全灭/灵峰全失返回真。
6. **分数**：`compute_score` = 独立复算的 `powerLevel×1 + 飞升×12 + 份额×40 + 道法完成×30 + 灵峰×3`；达 240 回合强制分数结算。
7. **待抉择**：同时达成多条路线时服务端发 `awaitInput(kind="victoryChoice")`；`resolveChoice` 越界回 `BAD_PARAMS` **且待决保留**；`chooseVictory` 成功后 `gameOver=true`。
8. **存档**：`saveGame` 回 `{slot, saved}`（失败带 `message`，**无 `success` 布尔**）；`loadGame` 回 `{slot, turn}` 且 `view` 与存档时逐字一致；`listSaves` 字段齐全；`turn % 10 == 0` 自动存档槽 0；`loadGame` 回到待决点**重新推送 `awaitInput`**。
9. **确定性（核心）**：固定种子 + 相同完整指令序列（含 AI 行动）双跑，**整局 view 与事件流逐字一致**；导出 `outputs/r7_authority_a|b.json` 并断言 SHA256 相同。
10. **全量命令**：`implemented_commands()` == 69 + ping；协议契约校验 69 分组点数不变。

**客户端（扩展或新建 `R7ClientTest`，`--integration` 真机）**：

11. newGame → 打开胜利进度面板 → 存读档往返 → 触发多路线待决 → `awaitInput` 弹窗 → `resolveChoice` → 结局屏显示 → 全程相机 transform/size 不变（`R7_CLIENT_PASS:` 前缀）。

**自检脚本**：

12. `tools/check.ps1` 增加 R7 服务端段、R7 客户端段；两工程 `--import` 无解析错误；协议校验仍绿（69 分组点数不变、**70 条（69 + ping）已实现**）；无残留 godot、无 `.java`，最终 `CHECK_RESULT=OK`。

---

## 提交与推送（在你的 worktree 根目录）

```powershell
& "C:\Users\Administrator\godot\Godot_v4.4.1-stable_win64_console.exe" --headless --path server --import
& "C:\Users\Administrator\godot\Godot_v4.4.1-stable_win64_console.exe" --headless --path client --import
powershell -NoProfile -ExecutionPolicy Bypass -File tools\check.ps1
git add -A
git commit -m "feat(r7): appointment bloodline, tribulation ascension, reactive ai, victory score, save load, victory choice"
git push origin HEAD:main
```

> 推送已固化为 HTTPS + 仓库本地代理（127.0.0.1:7890）；**保持 Clash 代理开启**；直接 `git push origin HEAD:main`，不改 remote、不用 SSH。若报 401/403 加 `-c credential.helper=manager`。

## 完成后汇报（固定格式）

- 任务 0：`setup_shared`/`--import`/`check.ps1` 结果、是否残留进程、`saves/` 是否不入库；
- 服务端：新增/修改文件清单；任命/血脉/渡劫、AI 决策、胜负/分数、存档的实现与 `data/gameConfig.json` 实际读取的键；
- 14 条命令：注册情况、各 `result`/`events` 字段与 PROTOCOL 一致性（`saveGame` 固定形状、只读命令 view=null、`loadGame` 待决重推）；
- **裁决二/三落实**：`AppointmentResult`/`routes[].goals` 选了哪条口径，§11.2 #1/#3 是否已更新；
- **血脉玩家入口说明**：69 条命令中无 marry/reproduce，是否只由 AI/内部结算调用（**未新增命令**）；
- **回填记录**：`AI_ACTION`、`VICTORY_CHECK`、每 10 回合自动存档、宗主外出是否已进 `TurnProcessor`；
- 客户端：胜利进度/结局屏/存档菜单/任命入口/待决弹窗/AI 回放交互、相机不重置断言；
- 验收：R7Test checks 数、R7ClientTest 结果、check.ps1 各段结果、**全量命令 70（69 + ping）已实现**；
- **全部 `TODO(需核对)` 字段及出处缺口清单**（R7 完成后 §11.2 应全部回填或标注）；
- commit hash、推送结果、残留进程情况。

## 非目标（本里程碑明确不做）

- **不做泼墨迷雾转场、正式 HUD/全面板、框选、正式战斗/单位动画、音效、小地图、设置项 UI、引导、昼夜/草木飞鸟/灵气粒子、轮廓描边、网格开关与宗门色边框**（R8）；R7 的结局屏/存档菜单/AI 回放为**占位 UI**；
- **不做皮肤包切换、默认水墨 2.5D 皮肤、数值平衡、Win 导出 exe**（R9）；
- **不实现外交/厌战、蛮族巢穴、独立灾劫、威胁总览、忠诚/叛乱、随机事件**（PRD §5.1 已裁剪 19 条命令，**不得实现**）；`awaitInput` **只保留 `victoryChoice`**；
- **不迁移 1.0 `StrategyService`（性格/长期战略/外交议程）**（裁决一）；
- **不新增命令、不新增错误码、不发明协议字段**；不改 R0–R6 已验证的地形生成、开局数值、移动/经济/道统/战斗/探索/政令/自动化规则（AI/胜负/存档/宗主外出属 R7 计划内回填，不视为改动）。
