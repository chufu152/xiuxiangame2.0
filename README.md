# 修仙4X·宗门争霸 2.0（xiuxiangame 2.0）

单机回合制 4X 修仙宗门争霸游戏。**2.0 版以 Godot 全栈重写：服务端权威逻辑 + 客户端表现，前后端分离，为未来联机预留。**

- 玩家：1 人 + 3 家 AI（宗门流 / 家族流 / 国家流）
- 地图：flat-top 六边形轴向坐标，默认 20×15 = 300 格；**文明6式分层地形起伏（基底/海拔丘陵山岳/地貌/河流/险地），山脉连绵**
- 形态：单机可独立运行；服务端为 Godot `--headless` 进程，客户端通过 WebSocket 连接
- 引擎：Godot 4.x，语言 GDScript（静态类型）
- 美术：**简化手绘水墨风 2.5D**（3D 低模 + 锁定正交 45° 等距相机、不可旋转）；独立可替换资源包（`assets/`，逻辑 ID 映射，换皮不改代码）

> 本文是仓库入口。**完整需求、玩法规则、数值口径、接口契约、里程碑与工程规范见
> [`docs/REQUIREMENTS_2.0.md`](docs/REQUIREMENTS_2.0.md)。**

---

## 目录结构

```
xiuxiangame2.0/
├── client/          # Godot 客户端工程（表现层：渲染/输入/UI/相机/资源映射）
│   ├── scenes/      # 场景（MainMenu 主菜单、World 地图/侧栏；HUD、各类面板在 R8）
│   └── scripts/
│       ├── net/     # WebSocket 客户端（NetClient）、会话状态与信号（Session autoload）
│       ├── world/   # 六边形地图、相机、地块/单位/建筑渲染
│       ├── ui/      # HUD 与各功能面板
│       └── art/     # AssetLibrary：按逻辑资源 ID 加载美术
├── server/          # Godot headless 服务端工程（权威规则层，不渲染）
│   ├── scenes/      # ServerMain 主场景（--headless）
│   ├── tests/       # 无头自测（SmokeTest / R1Test：打印 PASS/FAIL 标记 + 退出码）
│   └── scripts/
│       ├── net/     # WebSocket 服务端、命令分发、StateView（view 快照构造）
│       ├── model/   # 实体与 GameState（纯数据）
│       ├── rules/   # 全部规则：地形生成/移动/战斗/经济/城市/道统/探索/胜利/AI
│       ├── rng/     # 集中随机源（按 种子+序号 派生，保证可复现）
│       ├── config/  # gameConfig.json 加载与校验
│       └── save/    # 存档读写
├── shared/          # 两端共享（协议常量/枚举/DTO/六边形几何），通过目录联接挂载
│   ├── protocol/    # commands / msg / enums / dto
│   └── geo/         # hex.gd：轴向坐标、邻接、世界坐标（服务端与客户端共用同一换算）
├── assets/          # ★ 独立、可整体替换的美术资源包（水墨风 2.5D，皮肤包机制）
│   ├── art/default/ # 默认皮肤（terrain 材质；units/buildings/districts/features 模型；materials/particles；ui/icons）
│   ├── audio/       # bgm / sfx
│   ├── fonts/
│   └── manifest.json# 逻辑资源 ID → 物理文件路径（模型 .glb / 材质 .png / 粒子）
├── data/            # 权威数值配置（仅服务端读取，客户端不下发规则）
│   └── gameConfig.json
├── docs/            # 需求、协议、架构、任务提示词
├── tools/           # 启动/共享目录挂载/导出/自检脚本
├── saves/           # 本地存档（gitignore，保留 .gitkeep）
└── exports/         # 导出产物（gitignore，保留 .gitkeep）
```

---

## 快速开始

> **进度**：R0 工程骨架 ✅ 已完成（`d4c5bf7`）；R1 地图与开局 ✅ 已完成并通过验收（服务端 `R1_PASS checks=79458`）；R2 回合/移动/视野 ✅ 已完成（`6c5a232`）；R3 经济与城市 ✅ 已完成（`b036bb4` + 收尾 `e18db84`）；R4 道统与修炼 ✅ 已完成（服务端 `R4_PASS checks=174`、客户端 `R4_CLIENT_RESULT=OK checks=69`）；R3/R4 收尾已补实现**三流派特性**（`FactionRules`：宗门建造提速/副峰降价、家族血脉修炼加成/祖祠叠加、家族峰建造加价）；**R5 兵种与战斗 ✅ 已完成**（服务端 `R5_PASS checks=453`、客户端 `R5_CLIENT_RESULT=OK checks=95`、`tools/check.ps1` 19 阶段全绿）：十兵种 + 相克/地形防御/高台/河流 + 战斗预览与结算（`CombatResolver` 单一入口，预览=实战）+ ZOC/占格阻挡 + 传送 + 驻守 + 转职晋升 + 批量移动。**R5 未含探索那一半**（机缘/秘境属 R6）。
> **R6 探索/政令/自动化 ✅ 已完成**（服务端 `R6_PASS checks=317`、客户端 `R6_CLIENT_RESULT=OK checks=59`、`tools/check.ps1` 21 阶段 **130/130** 全绿）：机缘（成功率 = 基础 + 灵根品级×系数 + 宗门加成，失败三分支 死亡/受伤/心魔）+ 秘境（扣灵石、人数上限、全员须站在节点格、富矿/灾祸/空手三态）+ 政令（3 政体 × 8 卡、时代与道法门控、槽位裁剪、切换冷却）+ 自动化（自动修缮/改良/修路 + 逐峰自动项目 + 立即探索 + 集结/回防）+ 回合回填（`TurnProcessor` 接自动化与政令结算）。**R5 遗留已全部回填**：`miJingExploredTotal` 可达 → 成就 `boost_first_mijing` 解锁；道点节奏复查完成。
> **R7 任命/渡劫/AI/胜负/存档 ✅ 已完成**（服务端 `R7_PASS checks=211`、客户端 `R7_CLIENT_RESULT=OK checks=77`、`tools/check.ps1` 23 阶段 **147/147** 全绿）：任命（7 岗位最低境界、长老名额 = 基础 + 势力等级×1、峰主驻留/宗主坐镇加成、原峰主降亲传）+ 血脉（联姻 50 石、繁衍 120 石 + 60 工、冷却 5、品级抖动与灵根继承、族人死亡安定 −5）+ 渡劫飞升（成功率 = 基础 + 道法 + 灵根，失败心魔 +50 并按概率陨落）+ 反应式 AI（按 `ai.actionPoints` 逐点决策，攻击双门 `winChance` + 战力比，行动后重算视野）+ 胜负（三流派 + 评分路线，`powerLevel` 五来源、240 回合强制结算、失败三条件与覆灭清算）+ 存档（`{slot, saved}` 形状、槽 0 每 10 回合自动存档、读档后 view 逐字一致）+ 胜利择一（`awaitInput` 仅 `victoryChoice`、`resolveChoice` 只认 `req_victory_*`、越界待决保留）。**至此 69 条命令 + `ping` 全部落地**（`implemented_commands()` 共 70 项）。
> **R8 表现与 UI 打磨 ✅ 已完成**（客户端 `R8_CLIENT_RESULT=OK checks=44`（单元）/ `checks=59`（端到端）、`tools/check.ps1` 24 阶段 **175/175** 全绿、`check_protocol.ps1` 38/38）：**70 条命令全入口**（底栏按钮 5 + 面板按钮 43 + 地图手势 5 + 自动查询 17，机检用 `commands.gd` 常量全集反向核对，19 条裁剪命令**不造任何入口**）+ 水墨表现（昼夜 180 秒循环、六边形网格开关 1131 条线、宗门色边框、灵气粒子、飞鸟、三态迷雾泼墨转场）+ 小地图（三态配色 + 视口框 + 点击跳转**只平移**）+ 设置面板（6 项本地偏好，`setSetting` 不下发 view）+ 6 步新手引导 + Toast 轻提示 + 顶栏 13 项资源图标化。**服务端零改动**（`commands.gd`/`CommandDispatcher`/`StateView`/`TurnProcessor`/`gameConfig.json` 一行未改，PROTOCOL §11.3 已锁定）。前置硬门禁「最小水墨资源包」52 个文件已先交付（`ASSETVERIFY_OK covered=52 warned=0`，`8f96a6e`）。
> 里程碑进度、提示词与已知坑见 [`docs/prompts/README.md`](docs/prompts/README.md) §3。

1. 安装 Godot 4.4.x（标准 GDScript 版即可，无需 .NET 版）；路径 `C:\Users\Administrator\godot\`。
2. 首次拉取后运行 `tools/setup_shared.ps1`，把顶层 `shared/` 以目录联接（junction）挂到 `client/` 与 `server/`。
3. **导入（新增脚本/场景后必须先做）**：
   ```
   powershell -NoProfile -ExecutionPolicy Bypass -File tools\check.ps1
   ```
   `check.ps1` 已内置 `--import`；也可手动：
   `Godot_v4.4.1-stable_win64_console.exe --headless --path server --import`
4. 开发：`powershell -NoProfile -ExecutionPolicy Bypass -File tools\run_dev.ps1`（一键拉起 headless 服务端 + 客户端）。
5. 自检：`powershell -NoProfile -ExecutionPolicy Bypass -File tools\check.ps1`（服务端无头跑断言，校验确定性、地形比例与关键规则）。

> 本机 PowerShell 执行策略为 Restricted，因此统一用 `-ExecutionPolicy Bypass` 调用 `.ps1`；仓库**不提供** `.cmd` 包装脚本。

---

## 仓库规则（务必遵守）

- 每个里程碑 / 任务完成并通过自检后，**立即提交并推送到 `main`**：
  `git add -A && git commit -m "feat(模块): 简述" && git push`。
- 提交信息使用约定式提交：`feat / fix / docs / refactor / test / chore / perf`。
- **远程固定 HTTPS，禁止改成 SSH、禁止自行生成 SSH key**。仓库本地（仅本仓库，不写 `--global`）已配 `http.proxy`/`https.proxy = http://127.0.0.1:7890`，凭据走 Windows 凭据管理器；直接 `git push origin HEAD:main`。报 401/403 时用 `git -c credential.helper=manager push origin HEAD:main`。
- 规则、数值的唯一权威是 `data/gameConfig.json` 与服务端 `rules/`；客户端不实现任何玩法规则。

## 2.0 首版范围（速览）

- **纳入**：**分层地形起伏与河流（基底/海拔/地貌/河流/险地）、三层画卷迷雾**、三流派、弟子修炼与境界、回合经济、灵峰城市与区域、地块改良与道路、道统科技树、十兵种战术战斗（含丘陵高地/跨河）、探索机缘秘境、任命渡劫飞升、政令（裁剪）、自动化、三流派胜利、基础反应式 AI、存档。
- **暂不纳入**（首版明确裁剪，详见需求文档第 5 章）：外交/厌战、随机事件、叛乱/忠诚、蛮族巢穴、灾劫、AI 长期战略性格；更多地形（雨林/沙漠/雪原/自然奇观/登山单位）。
