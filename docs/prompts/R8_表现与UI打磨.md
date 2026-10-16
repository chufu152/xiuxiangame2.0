# R8 任务提示词：表现与 UI 打磨（69 命令全入口 / 正式 HUD / 泼墨转场 / 昼夜粒子 / 小地图 / 设置 / 引导）

> 状态：**草案（预生成）**。进入本里程碑前，必须按当时最新代码/config 重新核对全部文件锚点与数值后再执行。
> 建议专家：**Godot 游戏脚本工程师**（Godot 4.4 / GDScript 静态类型）
> 前置：**R0–R7 已完成且 `tools/check.ps1` 全绿**（R7 提交见 `docs/ROADMAP_2.0.md` §一，69 条 + `ping` 全部已实现）。**若前置里程碑实际交付与本文件所述锚点不一致，一律以当时代码/config 为准。**
> 本里程碑产出：**69 命令全有 UI 入口、正式 HUD 与全面板、泼墨迷雾转场、昼夜/草木飞鸟/灵气粒子、小地图、设置、引导、轮廓描边、网格开关、宗门色边框**的完整表现层。
> 本里程碑在你当前 worktree 根目录执行；开工先跑任务 0。

---

## 本里程碑范围（一句话）

**本里程碑不新增任何协议命令**（PROTOCOL 69 条 + `ping` 已于 R7 全部实现）；仅做**表现层与 UI 打磨**：把 69 命令全部接上可见 UI 入口、落地正式 HUD/面板/框选/动画/音效/小地图/设置/引导，以及**泼墨迷雾转场、昼夜循环、草木飞鸟、灵气粒子、模型轮廓描边、网格开关、宗门色边框**；服务端**仅在确有需要时补 `view` 字段**（不新增命令、不改玩法规则）。

## 开工前必读（只读，禁止自创规则/数值/字段）

1. `docs/REQUIREMENTS_2.0.md`：
   - **§1.3 平台、输入、呈现**、**§3 美术资源规范**（§3.1 风格定位 / §3.2 资源形式与目录 / §3.3 逻辑 ID / §3.4 AssetLibrary 行为 / §3.5 美术规范）；
   - **§4.1.10 Godot 2.5D 等距起伏表现**、**§4.2 三层画卷迷雾**（未探索宣纸空白→**泼墨褪去动画**、已探索水墨古图、当前视野实景）；
   - **§8.4 客户端相机与 UI 硬性要求**（相机锁 45°、入口齐全且不可用置灰悬浮说明、左键/框选/滚轮/中右键/快捷键、空格/End 结束回合、水墨视觉清单、布局：顶部资源栏/底部操作栏/左侧城市弟子/右侧势力胜利、Toast、选中地块侧栏全要素）。
2. `docs/ART_STYLE_REFERENCE.md`（§二 三态迷雾、§三 建模与地形）与 `assets/README.md`。
3. `docs/ROADMAP_2.0.md`：
   - **§3.2 ★ 前置约束：R8 开工前必须先交付「最小水墨资源包」**（**本提示词的硬门禁，见任务 0**）；
   - §七 R8 验收速查。
4. `assets/manifest.json`（**schemaVersion 3**，逻辑 ID 唯一权威；**代码只认逻辑 ID，禁止硬编码路径**）：
   - `activePack`（默认 `default`）、`filter`、`renderStyle`；
   - `terrain`（11）、`features`（8）、`units`（10）、`buildings`（10）、`districts`（6）、`improvements`（8）、`resources`（13）、`realms`（5）、`factions`（3）、`audio`（1）、`fonts`（2）。
5. `docs/PROTOCOL_2.0.md`：**§12 view 快照结构**（客户端渲染的唯一数据源）；**§0.7 主动消息**（`hello`/`awaitInput`）；**§10 已裁剪命令**（**不得为它们造 UI 入口**）。**本里程碑不新增/修改任何命令与错误码。**
6. **1.0 只读蓝本（禁止改动旧仓库 `C:\Users\Administrator\IdeaProjects\xiuxianGame`，只用于核对 UI 交互与信息组织）**：`gui\` 包（主窗口、面板、对话框、主题、`gui\assets\`）；**1.0 的相机可自由旋转、UI 布局零散是旧问题**，2.0 按 §8.4 重做（见「已裁决冲突」）。
7. 2.0 现有代码（在其上扩展）：`client/scenes/{Main,MainMenu,World}.gd`、`client/scripts/world/{HexMap,Fog,CameraRig,UnitView,SectView}.gd`、`client/scripts/art/AssetLibrary.gd`、`client/scripts/ui/MainMenu.gd`、`client/scripts/net/Session.gd`；`server/scripts/net/StateView.gd`。

## 硬约束（违反即返工）

1. **完全 Godot 4.4 + GDScript 静态类型，零 Java**；全仓库无 Java。
2. **服务端权威、客户端零规则**：**R8 不得实现任何玩法规则**；客户端只读 `view`；若确需补字段，**只在 `StateView.build` 追加展示用字段**（如 `renderHints` 扩展），**不新增命令、不改玩法数值**。
3. **相机铁律（R8 最高优先）**：锁 45° 正交、禁旋转；**任何操作（含框选、快捷键、打开/关闭面板、动画播放、泼墨转场、昼夜切换）与任何 view 刷新后，`CameraRig` 的 transform 与 `size` 都不得重置**；滚轮缩放以鼠标为中心、中键/右键拖拽平移。
4. **69 命令全入口**：每条已实现命令都必须有**可见 UI 入口**；不可用按钮**置灰并悬浮说明原因**（`blocker`/`message`）；`hello.implementedCommands` 决定按钮可用性。
5. **美术资源只经逻辑 ID**：`assets/manifest.json` 是唯一映射；**缺失只 WARN 不崩**（回退占位）；**换皮肤零代码**（见 R9）。
6. **确定性不受影响**：表现层动画/粒子/转场**不得引入服务端随机**；客户端表现随机不得写入 `GameState`。
7. 新增 `class_name` 后必须对两工程分别 `--import`；任何 Agent 跑通后无残留 godot 进程。
8. 所有 2.5D 元素**轮廓描边**；**全局缩到最远时设施仍可分辨**。

## 已裁决冲突（按本提示词执行，禁止自由裁量）

- **裁决一（相机不可旋转是硬约束，1.0 的自由旋转不迁移）**：1.0 允许自由环绕；2.0 按 §8.4 锁定 yaw=45°/pitch=45°、**禁用旋转输入**。**不得恢复任何旋转控制**。
- **裁决二（资源缺失只 WARN 不崩，是计划内状态）**：R1–R7 一直使用 `AssetLibrary` 占位回退，属计划内；R8 开工后若「最小水墨资源包」已交付，则对应逻辑 ID **不再触发 WARN**；**未交付的 ID 仍回退占位且不崩**。**不得为通过验收而删除回退逻辑。**
- **裁决三（已裁剪命令不造 UI 入口）**：PROTOCOL §10 的 19 条裁剪命令（外交/巢穴/灾劫/威胁/忠诚/随机事件）**不得出现在任何面板**。`awaitInput` **只处理 `victoryChoice`**。
- **裁决四（网格开关与宗门色边框是显示选项，不改变规则）**：网格线可开关、地块归属用宗门色边框标识——**纯显示层**，不写入 `GameState`、不下发协议字段。
- **裁决五（R8 不改数值、不改玩法）**：`data/gameConfig.json` **R8 不做数值调整**（数值平衡归 R9）；若因表现需要读取新键，只读不改。

---

## 任务 0：前置门禁（硬门禁，必须先交付「最小水墨资源包」）

> **本任务是 ROADMAP §3.2 的硬约束，未完成不得开工 R8。**

1. `powershell -NoProfile -ExecutionPolicy Bypass -File tools\setup_shared.ps1` 幂等挂载目录联接。
2. 两工程各跑一次 `--headless --path <proj> --import`，无解析错误。
3. `powershell -NoProfile -ExecutionPolicy Bypass -File tools\check.ps1` **全绿 `CHECK_RESULT=OK`**（R0–R7 断言不得回归）。
4. 确认**无残留 godot 进程**、无 `.java`。
5. **「最小水墨资源包」已交付**（至少覆盖 ROADMAP §3.2 清单）：
   1. 3 基底地形顶面材质（`terrain.base.LING_FIELDS`/`SPIRIT_PLAIN`/`BARREN`）；
   2. 3 海拔（`terrain.relief.{FLAT,HILL,MOUNTAIN}_SIDE` + `MOUNTAIN_TOP`，含连绵山体）；
   3. 河流（`terrain.river`）；
   4. 险地（`terrain.danger`）；
   5. 三态迷雾材质（`terrain.fog.RICE_PAPER`/`INK_MAP`，加实景态）；
   6. 10 单位模型（`unit.PU_TONG` … `unit.JI_GUAN_JUN_TUAN`）；
   7. 10 建筑模型（`building.SHAN_MEN` … `building.WANG_CHAO_DI_DU`）；
   8. 主要 UI 图标（`resource.*` 13 项 + `realm.*` 5 项 + `faction.*` 3 项）。
   - **验收方式**：替换 `assets/art/default/` 下实体文件后，`activePack=default` 下 `AssetLibrary` **不再对上述 ID 触发 WARN**。
   - **若资源包未交付，停下报告，不得开工 R8 打磨项。**
6. 若第 3 步或第 5 步不满足，**停下报告**。

---

## 任务 1：AssetLibrary 与资源接入（客户端）

1. `client/scripts/art/AssetLibrary.gd`：确认按 `manifest.json` 逻辑 ID 懒加载 `.glb`/`.png`/`.tres`；**缺失回退占位（模型=水墨灰阶几何体+文字标签、贴图=纯色块、材质=`StandardMaterial3D`、字体=回退字体）并 WARN 一次**（沿用 R1 行为）。
2. 为「最小水墨资源包」覆盖的 ID 接入真资源；**未覆盖的 ID 继续回退占位**（裁决二）。
3. 支持 F5 热重读 `manifest.json` 并使缓存失效（R1 已有，保持）。

## 任务 2：HUD 与全面板（客户端，69 命令全入口）

- **顶部资源栏**：灵力/灵石/工力/声望/气运/灵粮/道点 + 材料（天晶/玄铁/灵木）+ 奢侈品（灵茶/云锦/灵玉）（取 `view.sects[player].resources`），**回合数 + 阶段**。
- **底部操作栏**：结束回合（空格/End）、单位动作、建造、区域、劳力、改良、探索、政令、自动化、任命、存档等入口。
- **左侧面板**：城市/弟子；**右侧面板**：势力/胜利进度。
- **全面板清单（每条对应命令，全部要有入口）**：
  | 面板 | 覆盖命令（69 条中的对应项） |
  |---|---|
  | 开局/主菜单 | `newGame`、`getState` |
  | 回合 | `finishTurn`、`beginPlayerTurn`、`nextTurn` |
  | 单位/移动 | `moveDisciple`、`queryMoveRange`、`batchMove` |
  | 战斗 | `attack`、`queryAttackPreview`、`queryAttackable`、`retreat` |
  | 传送/驻守 | `teleport`、`queryTeleportOptions`、`assignGarrison`、`withdrawGarrison` |
  | 兵种 | `reclass`、`promote`、`queryDiscipleDetail` |
  | 建城/城市 | `foundSpiritPeak`、`constructBuilding`、`queryBuildOptions`、`openCave`、`fortifyPeak`、`queryCityDetail` |
  | 区域/劳力 | `foundDistrict`、`queryDistrictSites`、`assignWorker`、`unassignWorker`、`queryAssignableTiles` |
  | 改良/建造者 | `appointBuilder`、`buildImprovement`、`repairImprovement`、`queryImprovementOptions` |
  | 道统 | `researchDao`、`holdRecruitment`、`queryProjectQueue`、`cancelProject`、`accelerateProject` |
  | 探索 | `queryJiYuanInfo`、`sendToJiYuan`、`queryMiJingInfo`、`exploreMiJing` |
  | 政令 | `switchGovernment`、`enactPolicy`、`revokePolicy`、`queryPolicyOptions` |
  | 自动化/设置 | `setAutomationToggle`、`setPeakAutoProject`、`setAllAutoProject`、`exploreNow`、`queryAutomationState`、`setSetting` |
  | 任命/渡劫 | `tribulate`、`appointFengZhu`、`appointZhangLao`、`appointZongZhu` |
  | 集结/回防 | `rally`、`returnToDefense` |
  | 胜负/待决 | `queryVictoryProgress`、`checkVictory`、`checkDefeat`、`chooseVictory`、`queryGameOver`、`queryVictoryChoice`、`resolveChoice` |
  | 存档 | `listSaves`、`saveGame`、`loadGame` |
- **框选**：左键框选多单位（供 `batchMove` 等）；**快捷键**：空格/End 结束回合等。
- **Toast**：事件与业务失败文案（`result.message`）。
- **选中地块侧栏**：列出 基底/海拔/地貌/河流/险地/节点/资源/改良/归属 + 产出明细。

## 任务 3：2.5D 表现打磨（客户端）

1. **泼墨迷雾转场**（§4.2）：未探索（宣纸空白）→ 探索到时以**泼墨「褪去」动画**露出实景；三态材质切换；R1 的三态静态材质升级为动画（`Fog.gd`）。
2. **昼夜循环**：简易昼夜光照（`World.gd` 已有 `_build_lighting()`，扩展为循环）。
3. **草木摆动、飞鸟、灵气粒子**：占位粒子/程序化动画（真资产来自资源包）。
4. **轮廓描边**：所有模型轮廓描边强化；**全局缩到最远设施仍可分辨**。
5. **网格开关**：六边形网格线可开关（裁决四）。
6. **宗门色边框**：地块归属用宗门色边框标识（裁决四）。
7. **河流贴边 ribbon、地貌顶面装饰、险地印记、节点标签**（R1 占位升级为真资产）。

## 任务 4：小地图 / 设置 / 引导（客户端）

1. **小地图**：缩略图 + 视口框 + 点击跳转（不改相机角度/缩放，只平移）。
2. **设置面板**：`setSetting`（动画/自动播放/快速结算等**客户端本地偏好**，服务端只确认）；**画面/音量/快捷键**设置。
3. **音效**：`manifest.audio` 逻辑 ID 接入（缺失回退静默，不崩）。
4. **新手引导**：首次进入的分步引导（占位文案即可）。

## 任务 5：服务端（仅在确需时补 `view` 字段）

- 若表现层确需新字段，**只在 `server/scripts/net/StateView.gd` 的 `build()` 追加展示用字段**（如扩展 `renderHints`），**不改玩法规则、不新增命令、不改错误码**。
- 若无需补字段，**服务端不改动**；在汇报中明确说明「R8 服务端零改动」。

---

## 自动验收（扩展 `tools/check.ps1`，全部通过）

**客户端（新建 `client/tests/R8ClientTest.gd` + `.tscn`，无头 + `--integration`；勿改动 R1–R7 测试）**：

1. **69 命令全入口（可机检部分）**：遍历 `hello.implementedCommands`，断言客户端存在对应入口（面板/按钮注册表），**数量 == 69 + ping**；未实现命令**不出现入口**。
2. **不可用置灰**：对若干命令制造不可用条件（如未选中单位时 `moveDisciple`），断言按钮 `disabled==true` 且有 `blocker` 文案。
3. **相机不重置（核心）**：执行「框选 → 打开/关闭各面板 → 触发泼墨转场 → 昼夜切换 → 存读档 → 结束回合 → `getState`」全序列，断言 `CameraRig` 的 transform 与 `size` **全程不变**；断言**无任何旋转输入生效**（`R8_CLIENT_PASS:` 前缀）。
4. **资源缺失只 WARN 不崩**：对「最小水墨资源包」覆盖的 ID 断言**不再 WARN**；对未覆盖 ID 断言**仍回退占位且 WARN 一次、不崩**（裁决二）。
5. **网格开关/宗门色边框**：开关网格线后渲染层状态变化；归属地块显示宗门色边框；**均不写入 `GameState`**（裁决四）。
6. **小地图**：点击小地图跳转后**相机角度/缩放不变**（只平移）。
7. **设置**：`setSetting` 后本地偏好生效、服务端 `view` 不含该值。

**通用（`tools/check.ps1`）**：

8. 增加 R8 客户端段；两工程 `--import` 无解析错误；协议校验仍绿（**69 分组点数不变、70 条已实现不变**）；无残留 godot、无 `.java`，最终 `CHECK_RESULT=OK`。
9. **纯视觉项（配色/连绵观感/泼墨观感/粒子观感）** 留**人工核验清单**（在汇报中列出），但**相机不重置、资源缺失不崩、69 命令全入口**必须机检通过。

---

## 提交与推送（在你的 worktree 根目录）

```powershell
& "C:\Users\Administrator\godot\Godot_v4.4.1-stable_win64_console.exe" --headless --path server --import
& "C:\Users\Administrator\godot\Godot_v4.4.1-stable_win64_console.exe" --headless --path client --import
powershell -NoProfile -ExecutionPolicy Bypass -File tools\check.ps1
git add -A
git commit -m "feat(r8): full ui entry points, ink-wash transitions, day-night particles, minimap settings onboarding"
git push origin HEAD:main
```

> 推送已固化为 HTTPS + 仓库本地代理（127.0.0.1:7890）；**保持 Clash 代理开启**；直接 `git push origin HEAD:main`，不改 remote、不用 SSH。若报 401/403 加 `-c credential.helper=manager`。

## 完成后汇报（固定格式）

- 任务 0：`setup_shared`/`--import`/`check.ps1` 结果、是否残留进程、**「最小水墨资源包」交付清单与 `AssetLibrary` 不再 WARN 的 ID 列表**；
- 客户端：新增/修改文件清单；HUD/面板/框选/动画/音效/小地图/设置/引导/泼墨转场/昼夜粒子/描边/网格开关/宗门色边框的实现；
- **69 命令入口覆盖表**（逐条列出对应 UI 入口）；
- **服务端改动**：是否为表现补了 `view` 字段（若无，明确「零改动」）；
- **相机不重置断言**：全序列测试结果；
- 验收：R8ClientTest 结果、check.ps1 各段结果、协议 69 分组点数与已实现命令数（70）不变；
- **人工核验清单**（纯视觉项）；
- **全部 `TODO(需核对)` 字段及出处缺口清单**（R8 应无新增）；
- commit hash、推送结果、残留进程情况。

## 非目标（本里程碑明确不做）

- **不做任何新玩法规则、不新增命令、不新增错误码**（R8 仅表现层；协议 69 条 + `ping` 已于 R7 全实现）；
- **不做数值平衡调整**（R9）；
- **不做皮肤包切换机制与默认水墨 2.5D 皮肤包**（R9）——R8 只消费「最小水墨资源包」，**不做多皮肤切换**；
- **不做 Win 导出 exe**（R9）；
- **不恢复相机旋转**（裁决一）；**不为已裁剪的 19 条命令造 UI 入口**（裁决三）；
- **不改 `data/gameConfig.json` 数值**（裁决五）；**不删除资源缺失回退逻辑**（裁决二）。
