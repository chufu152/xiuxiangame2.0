# WorkBuddy 开工提示词（R0–R9）

本目录是**给 WorkBuddy 逐里程碑执行的任务提示词**。每份提示词都是一条独立、可直接复制粘贴的指令，内含：必读文件锚点、硬约束、文件清单、可执行自动验收、完成后提交。

> **本文件是提示词目录的索引与规则总纲**；具体任务在 `R*_*.md`。

---

## 0. 文档权威层级（冲突裁决顺序，高者优先）

| 层级 | 文件 | 定位 |
|---|---|---|
| ① | `data/gameConfig.json` | 已落地的实际数值（唯一数值真相） |
| ② | `docs/REQUIREMENTS_2.0.md` | 需求与口径（唯一权威需求） |
| ③ | `docs/prompts/*.md`（本目录） | 需求的可执行任务切片 |
| ④ | `README.md` / `data/README.md` / `assets/README.md` | 导读与迁移说明 |

**低层级与高层级冲突时，以高层级为准并回改低层级。** 任何里程碑完成后，必须回写 ② 与 ③（状态、实际交付、偏差），禁止只改代码不改文档。

---

## 1. 用法

1. **一次只派发一个提示词**（R0 通过后再派 R1，不得跳步）。
2. WorkBuddy 专家统一选 **Godot 游戏脚本工程师（Godot 4.4 / GDScript）**。
3. 把对应 `R*_*.md` 的**全文**复制给 WorkBuddy；要求它**先只读引用文档、不自创规则/数值**，完成后跑自检并自行提交。
4. 每个里程碑结束，检查：自检全绿、无残留进程、已 push，再进入下一个。
5. 若执行中发现提示词与 `data/gameConfig.json` 或 PRD 冲突，**停下报告，不要自行发明数值**。

---

## 2. 环境（已确认，照用）

- 引擎：**Godot 4.4.1 stable（标准 GDScript 版，非 .NET）**
- GUI 版：`C:\Users\Administrator\godot\Godot_v4.4.1-stable_win64.exe`
- 控制台 / headless 版：`C:\Users\Administrator\godot\Godot_v4.4.1-stable_win64_console.exe`
- 服务端：`--headless --path server`，监听 `127.0.0.1:9527`
- 客户端：`--path client`
- 若 Godot 路径变动：写 `tools/godot_path.txt`（不入库）或设环境变量 `GODOT_CONSOLE_EXE`。

---

## 3. 里程碑状态与提示词

| 里程碑 | 状态 | 服务端 | 客户端 | 提示词 |
|---|---|---|---|---|
| **R0** 工程骨架 | ✅ **已完成**（`d4c5bf7`，已推送） | 双 Godot 工程、shared 联接、WebSocket 互通、config 加载/校验、hello | 连接/握手/启动器拉起子进程 | `R0_工程骨架.md` |
| **R1** 地图与开局 | ✅ **已完成**（已通过 `tools/check.ps1` 50/50，已推送） | 分层地形生成（基底/海拔/地貌/河流/险地/资源/节点，种子确定）、实体初始化、三流派、出生点、view 快照、迷雾（可见/已探索） | 主菜单/开局、起伏六边形+连绵山体+河流渲染、相机锁 45° 正交、三层迷雾静态材质 | `R1_地图开局.md` |
| **R1.5** R2 前置修复 | ✅ **已完成**（`8c622b5`，已推送） | 仅落地 `docs/PROTOCOL_2.0.md` 契约 + `tools/check_protocol.ps1` 校验，**无玩法逻辑** | 挂载新 worktree 联接、占位回退核对、ROADMAP 登记最小水墨资源包排期 | [`R1.5_R2前置修复.md`](R1.5_R2前置修复.md) |
| **R2** 回合/移动/视野 | ✅ **已完成**（已通过 `tools/check.ps1` 全绿，已推送） | 6 阶段状态机（已填 TURN_START/SPIRIT_PEAK/PLAYER_ACTION，其余留 TODO）、地形移动力叠加/BFS、视野随移动刷新 | 点选/移动/高亮/范围预览/TopBar、全程相机不重置 | [`R2_回合移动视野.md`](R2_回合移动视野.md) |
| **R3** 经济与城市 | ✅ **已完成**（已通过 `tools/check.ps1` 15 阶段 81/81 全绿，已推送） | 经济结算（`SETTLEMENT` 填实）、地形产出、人口/住房/安定、灵峰/项目队列、建筑 10 种、区域 5+首府区（含地形邻接）、劳力指派、改良 8 种、青石道路网、**气运满溢吞并/灵峰晋升（1.0 回填）** | 城市面板、建造/区域选址、劳力指派、改良、资源栏（追加 粮/气运/道点/材料） | [`R3_经济与城市.md`](R3_经济与城市.md) |
| **R4** 道统与修炼 | ✅ **已完成**（已通过 `tools/check.ps1` 17 阶段 97/97 全绿，已推送） | 21 道法树/道点/前置·时代·流派·血脉门控、研究队列（逐回合工力摊销）、修炼/突破/渡劫、心魔、收徒、项目队列取消/加速、成就 boost（**含 `初探秘境` 语义修正**）、**回填 R3 道法门控改良 + MOVE/VISION 加成** | 道统树面板（5 时代分列 + 三态 + blocker）、项目/研究队列双列（不混池 + 加速/取消）、弟子详情（修为/心魔/伤势/入门回合）、TopBar 道统/队列入口 | [`R4_道统与修炼.md`](R4_道统与修炼.md) |
| **R5** 兵种与战斗 | ✅ **单位战棋部分已完成**（`R5_PASS checks=453`、`R5_CLIENT_RESULT=OK checks=95`，`tools/check.ps1` 19 阶段全绿，已推送）。**探索部分（机缘/秘境）未做，转 R6** | 十兵种（`UnitRules` 27 个纯函数：相克/射程/攻城/机动/视野/反击/地形防御/高台/河流/驻守/补给/断粮/撤退概率/战阶晋升/转职校验/解锁）、战斗唯一结算入口 `CombatResolver`（`preview` 与 `attack` 共用 `_build_matchup`，**预览=实战**）、野战/攻城/夺节点三分支、ZOC 与敌方占格阻挡（回填 `MoveRules.step_cost`）、传送网络、节点驻守、转职/晋升（当场重算机动）、批量移动（上限 8）、**回填 R4 遗留** `enemiesDefeated`（`boost_first_win` 可达）与围城断供削减 | 战斗预览面板（攻守战力/胜率/相克/反击/blockedReason/notes + 结算反馈）、**攻击高亮层与移动高亮层完全独立**、弟子详情面板（战功/战阶/晋升点/出手 + 撤退/传送/驻守/撤离 + 十兵种转职置灰与 blocker + 晋升候选）、十兵种占位剪影、Shift 多选 → batchMove | [`R5_兵种与战斗.md`](R5_兵种与战斗.md) |
| R6 探索/政令/自动化 | 🔶 **提示词已就绪（草案）、待执行**（**R5 提示词里的「探索」那一半并入本里程碑**：机缘 `sendToJiYuan`/秘境 `exploreMiJing` 未实现，故 `miJingExploredTotal` 仍恒 0、`boost_first_mijing` 不可达、道点节奏待复查） | 机缘/秘境、政令（8 卡/3 政体）、自动化、集结/回防 | 探索/政令/自动化面板 | [`R6_探索政令自动化.md`](R6_探索政令自动化.md) |
| R7 任命/渡劫/AI/胜负/存档 | 🔶 **提示词已就绪（草案）、待执行** | 任命、血脉、渡劫飞升、基础 AI、胜负、分数、存档 | 胜利进度/结局/存档/AI 回放 | [`R7_任命渡劫AI胜负存档.md`](R7_任命渡劫AI胜负存档.md) |
| R8 表现与 UI 打磨 | 🔶 **提示词已就绪（草案）、待执行**（硬门禁：先交付「最小水墨资源包」，见 ROADMAP §3.2） | —（仅协议补字段） | 正式 HUD、全面板、框选、动画、音效、小地图、设置、引导、泼墨迷雾转场、昼夜/草木飞鸟/灵气粒子、轮廓描边、网格开关与宗门色边框 | [`R8_表现与UI打磨.md`](R8_表现与UI打磨.md) |
| R9 皮肤化/平衡/导出 | 🔶 **提示词已就绪（草案）、待执行** | 数值平衡微调（不改架构） | 皮肤包切换、默认水墨风 2.5D 皮肤、Win 导出 | [`R9_皮肤化平衡导出.md`](R9_皮肤化平衡导出.md) |

### 各里程碑命令与验收（与 PRD §7 一致，供生成提示词时直接引用）

| 里程碑 | 协议命令 | 关键验收 |
|---|---|---|
| R0 | `ping` | 客户端连上 headless 并显示 hello；`setup_shared` 可重复执行；无残留进程 |
| R1 | `newGame` `getState` | 固定种子地图逐字一致；海拔/河流比例正确；300 格/4 宗/初始资源与弟子正确；三态迷雾与 §4.2 下发规则一致；不可旋转、缩放平移不重置 |
| R2 | `finishTurn` `nextTurn` `beginPlayerTurn` `moveDisciple` `queryMoveRange` | 高亮即可达；山岳不可达；丘陵/灵林/雾泽/跨河扣力与预览一致；迷雾随移动更新 |
| R3 | 城市 18 条 | 产出与 config 一致；山岳不可建城、丘陵/灵林限制生效；区域邻接与上限生效；安定惩罚生效 |
| R4 | `researchDao` `holdRecruitment` `queryProjectQueue` `cancelProject` `accelerateProject` | 21 道法前置/时代/流派专属门控正确；进度/突破/渡劫正确；成就 boost 触发正确 |
| R5 | 单位 22 条（战斗相关） | 预览胜率 == 实战口径；高地/跨河/丘陵/灵林加成正确；夺峰/夺点易主与视野重算；远程零反击；ZOC/围城生效 |
| R6 | 探索 4 + 政令 4 + 自动化 6 | 成功率/冷却/伤亡与 config 一致；政策槽位/冷却 8 正确；loyalty 效果落安定；自动化按阈值触发 |
| R7 | 会话剩余命令、`tribulate`/任命、`saveGame`/`loadGame`/`listSaves`、胜利待择 | 三流派胜利可达成；240 回合分数正确；同种子双跑逐字一致；读档继续与待决重建 |
| R8 | —（仅协议补字段） | 全部 69 命令有 UI 入口；信息直观；视角/缩放操作后不重置；全局缩到最远设施仍可辨 |
| R9 | — | 换皮肤零代码；默认皮肤完整；导出可独立运行；自检全绿 |

> 命令清单（69 条 + `ping`）、view 字段、数值口径、裁剪范围以 `docs/REQUIREMENTS_2.0.md` §5–§6 为准。

---

## 4. 通用硬约束（每个里程碑都适用）

- 完全 Godot 4.4 + GDScript **静态类型**，**零 Java、零 JVM**，全仓库无 `.java`。
- **服务端权威、客户端零规则**；规则/数值唯一权威是 `data/gameConfig.json` 与服务端 `rules/`。
- 2.5D：**正交相机锁定 yaw/pitch=45°，禁止旋转**；缩放/平移/任何操作与 view 刷新后相机不重置。
- 美术资源独立可替换（逻辑 ID → `assets/manifest.json` 映射），缺失只 WARN 不崩。
- 确定性：同种子、同宽高、同命令序列 → 逐字一致；随机只经服务端集中随机源。
- 每任务结束**无残留 godot 进程**，自检 `tools/check.ps1` 全绿。

---

## 5. Windows 环境已知坑（R0/R1 实证，务必遵守）

1. **先 `--import` 再运行**：新克隆、或新增 `class_name` 全局类后，必须先跑一次导入生成全局类缓存，否则所有全局类报 `not declared`：
   - `Godot_v4.4.1-stable_win64_console.exe --headless --path server --import`
   - `Godot_v4.4.1-stable_win64_console.exe --headless --path client --import`
   - `tools/check.ps1` 已内置该步骤；新增脚本/场景后若报类未声明，重跑 import。
2. **拉子进程不要用 `Start-Process`**：本机同时存在大小写两份 `HTTP_PROXY`/`http_proxy`，`Start-Process` 重建环境块会抛「已添加项」。工具脚本统一用 .NET `System.Diagnostics.Process`；**等待服务端就绪用 TCP 端口轮询**，不要依赖匹配控制台日志。
3. **脚本不要设 `[Console]::OutputEncoding`**：CP936 控制台强行切 UTF-8 会导致中文乱码；Godot 输出统一用 .NET Process 显式按 UTF-8 解码。
4. **含中文的 `.ps1` 必须带 UTF-8 BOM**，否则 Windows PowerShell 5.1 按 ANSI 读取会报「字符串缺少终止符」。
5. **执行策略为 Restricted**：跑脚本用 `powershell -NoProfile -ExecutionPolicy Bypass -File <脚本>`；不要假设双击可用（本仓库**不提供** `.cmd` 包装，直接调用 `.ps1`）。
6. **`shared/` 用目录联接（junction）挂载**：`tools/setup_shared.ps1` 幂等创建；联接本体在 `.gitignore` 中，顶层 `shared/` 真实目录入库。
7. **`*.uid` 不入库**：Godot 4.4 为每个脚本生成的 `.uid` 属引擎元数据，已在 `.gitignore` 忽略。

---

## 6. Git 与推送规范

- 远程 `https://github.com/chufu152/xiuxiangame2.0.git`，主分支 `main`。
- 每个里程碑完成并通过自检后**立即提交并推送**：
  ```
  git add -A
  git commit -m "feat(rX): <英文简述>"
  git push origin HEAD:main
  ```
- **远程固定 HTTPS，禁止改成 SSH、禁止自行生成 SSH key。** 仓库本地（**仅本仓库，不写 `--global`**）已配 `http.proxy`/`https.proxy = http://127.0.0.1:7890`，凭据走 Windows 凭据管理器；保持 Clash 代理开启即可免参推送。
- 新 clone 的仓库没有仓库本地代理时：
  `git config http.proxy http://127.0.0.1:7890 && git config https.proxy http://127.0.0.1:7890`；
  或仅对单条命令临时加 `-c http.proxy=... -c https.proxy=...`。
- **报 401/403 或 `could not read Username ... terminal prompts disabled`** 时，改用：
  `git -c credential.helper=manager push origin HEAD:main`。
  若仍失败（本机默认继承的 `credential.helper=helper-selector` 在受限环境会卡死），在**仓库本地**重置助手链：
  ```
  git config --local credential.helper ""
  git config --local --add credential.helper manager
  ```
- 代理只在本机 Clash 开启时有效；推送报连接失败先确认 `7890` 端口在监听。
- **worktree 说明**：WorkBuddy 在 `WorkBuddy/Worktrees/...` 的独立 worktree 工作（分支 `workbuddy/main-*`），`main` 可能同时被主检出 `IdeaProjects/xiuxiangame2.0` 占用；因此统一推 `HEAD:main` 而不是 `push origin main`。

---

## 7. 已知阻塞项 / 待办

> R0、R1、R1.5、R2、R3 已全部完成并推送，**当前无阻塞项**。以下为历史记录（均已解除），供追溯：

| # | 项 | 影响 | 处理结果 |
|---|---|---|---|
| 1 | `shared/geo/hex.gd` 仅有 R0 常量占位，**未实现** `id/coords/neighbors/distance/to_world/opposite/edge_vertices` | R1 服务端与客户端全部脚本解析失败（`Static function "id()" not found in base "Hex"`），R1 无法运行 | ✅ 已按 R1 提示词的**显式契约**补齐 7 个静态函数，双端 `--import` 无解析错误 |
| 2 | R1 交付物（配置/服务端/客户端/测试）已落盘但**未提交** | 工作区不干净 | ✅ 已通过验收后提交推送 |

### R1 附带修复（影响后续所有里程碑，需知悉）

- **WebSocketPeer 默认收发缓冲仅 64 KiB**：`newGame`/`getState` 的 view 快照随地图线性增长（默认 300 格约 70 KB），默认地图即触发 `_send ERR_OUT_OF_MEMORY` 静默失败。已在 `shared/protocol/msg.gd` 定义 `FRAME_BUFFER_BYTES = 16 MiB`，服务端/客户端**建连前**统一设置。**新增任何大帧命令时沿用该常量，勿再退回默认值。**
- **`tools/check.ps1` 已扩展为 19 阶段（`[0/18]`–`[18/18]`）R0+R1+R2+R3+R4+R5 里程碑自检**，并加固子进程输出排空（有界 `Task.Wait`），后续里程碑在其上继续追加验收阶段。
  - R2 起端到端断言必须匹配 `R1_CLIENT_PASS:` / `R2_CLIENT_PASS:` / `R3_CLIENT_PASS:` / `R4_CLIENT_PASS:` / `R5_CLIENT_PASS:` **前缀**：仅凭中文 label 会把 `push_error` 的 `*_FAIL` 也误判为 PASS。
  - **`Session._request` 是「单请求串行 + 排队补发」语义**：同一时刻只允许 1 条请求在途；在途期间的新请求进入 `deferred` 队列（上限 8），当前回包处理完后按 FIFO 补发。**R5 起不再是「静默丢弃」**——R5 的「点选弟子」是三段串行链（`queryMoveRange` → `queryAttackable` → `queryDiscipleDetail`），若仍丢弃，玩家在高亮刚出现时点可达格会被吞掉（`R2ClientTest` 端到端实测暴露）。客户端同一操作需要多个 `query*` 时仍应**串行链式**（前一个回包到达后再发下一个），不要依赖队列去保证顺序。
  - **`query*` 只读回包不带 `success` 字段**（形状见 `PROTOCOL_2.0.md` §4）；写命令回包才带 `BuildResult.success`。消费端不得用 `success` 判定只读查询的成败。
- **`OS.execute(cmd,args,out,true)` 在本机不可靠**（按管道缓冲边界分块、丢换行、破坏 UTF-8）；`OS.execute_with_pipe` 会挂起；`git show --output=<file>` 对 blob 写 0 字节。需要字节精确取文件时用 `git archive --format=zip -o <file>`。

---

## 8. 提示词写作模板（生成 R2–R9 时套用）

每份 `R*_*.md` 至少包含以下小节，缺一不可：

```markdown
# RX 任务提示词：<一句话主题>

> 建议专家：Godot 游戏脚本工程师（Godot 4.4 / GDScript / 3D）
> 前置：<上一里程碑> 必须已完成且 tools/check.ps1 全绿。
> 本里程碑产出：<端到端可玩切片的一句话>；**不做**：<明确非目标>。

## 开工前必读（只读，禁止自创规则/数值）
<按 § 列出 PRD / 美术 / manifest / data/README 的精确章节>

## 硬约束（违反即返工）
<引用 §4 通用约束 + 本里程碑特有约束，数值全部写死>

## 配置迁移/新增（如涉及）
<字段名 + 数值，标注来源章节>

## 服务端任务（server/scripts/…）
<文件 → 职责 → 接口签名>

## 客户端任务（client/…）
<文件 → 职责 → 交互与表现>

## 自动验收（扩展 tools/check.ps1，全部通过）
<编号断言清单，每条可机检>

## 完成后
git add -A
git commit -m "feat(rX): <英文简述>"
git push origin HEAD:main

## 非目标（RX 不做）
<逐条列出越界项>
```

**写作要求**：
- 数值一律**照抄** PRD/config，不写「合理值」「自行调参」。
- 跨里程碑接口（如 `Hex.*`、`Dto.*`、命令名）**必须写成显式签名**，避免下游猜。
- 验收项必须**可机检**（打印固定标记 + 退出码，或导出可比对文件）。
- 非目标必须显式，防止越界实现后续里程碑。

---

## 9. 文档维护规则

1. 里程碑完成后，回写本文件 §3 状态列 + 对应 `R*_*.md` 的「实际交付 / 偏差」小节。
2. 新增/修改配置字段，同步更新 `data/README.md` 与 PRD 附录 A。
3. 发现冲突时按 §0 层级裁决，**同一次提交内**把高低层一起改齐。
4. 后续里程碑提示词在进入该里程碑时生成，生成时须先核对当时代码与 config 实际状态。
