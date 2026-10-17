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
> **R8 表现与 UI 打磨 ✅ 已完成**（客户端 `R8_CLIENT_RESULT=OK checks=44`（单元）/ `checks=59`（端到端）、`tools/check.ps1` 24 阶段 **175/175** 全绿（R8 追加两轮界面打磨后为 179/179）、`check_protocol.ps1` 38/38）：**70 条命令全入口**（底栏按钮 5 + 面板按钮 43 + 地图手势 5 + 自动查询 17，机检用 `commands.gd` 常量全集反向核对，19 条裁剪命令**不造任何入口**）+ 水墨表现（昼夜 180 秒循环、六边形网格开关 1131 条线、宗门色边框、灵气粒子、飞鸟、三态迷雾泼墨转场）+ 小地图（三态配色 + 视口框 + 点击跳转**只平移**）+ 设置面板（6 项本地偏好，`setSetting` 不下发 view）+ 6 步新手引导 + Toast 轻提示 + 顶栏 13 项资源图标化。**服务端零改动**（`commands.gd`/`CommandDispatcher`/`StateView`/`TurnProcessor`/`gameConfig.json` 一行未改，PROTOCOL §11.3 已锁定）。前置硬门禁「最小水墨资源包」52 个文件已先交付（`ASSETVERIFY_OK covered=52 warned=0`，`8f96a6e`）。
> 里程碑进度、提示词与已知坑见 [`docs/prompts/README.md`](docs/prompts/README.md) §3。
>
> **R8 视觉对齐参考图（收尾打磨）✅ 已完成**：按水墨长卷参考图重做表现层——**宣纸米白底 + 未探索区纯留白**（夜色不再压成深蓝灰，未探索格照建但隐藏）、**地图取景收紧到画面八成**并沿屏幕右方平移半个侧栏宽做构图补偿、**顶栏/底栏改横贯全屏的纸带**（左「第 N 回合 · 春 · 修行期」+ 13 项圆形资源徽章 + 右上青玉「结束回合」印章）、**右侧地块卡 / 左上目标卡 / 左下深墨小地图**、**中式重檐楼阁**（石台基 + 朱红柱 + 米色墙 + 青瓦下檐 + 金瓦上檐 + 宝顶 + 竖幅宗门旗）、**单位改小人形象**、外围**层叠远山 + 流动云带**。新增 `world/Scenery.gd`、`ui/UiTheme.gd`、`tools/WorldShot.gd`（真实渲染截图，非 headless）。客户端单元 `R1 52 / R2 5 / R3 5 / R4 8 / R5 8 / R6 9 / R7 14 / R8 44` 全绿，服务端**零改动**。纪要见 ROADMAP §4.9。
>
> **R8 追加：六套全屏界面 + 青云宗建筑群 ✅ 已完成**（按 7 张参考图逐张制作，服务端**零改动**）：
> **回合结算**（`ui/TurnSummary.gd`，三栏卷轴：资源收支 / 重要事件卡 / 事件时间线）、**道统树**（`ui/DaoTreePanel.gd` + `ui/DaoTreeCanvas.gd`，三页签 + 贝塞尔连线 + 三态节点 + 悬浮详情 + 右栏弟子修行/研究队列）、**存档**（`ui/SavesScreen.gd`，左导航 + 6 槽卷宗 + 程序化缩略图 + 右详情卡）、**战斗**（`ui/CombatScreen.gd`，胜负条件卡 + 部队卡 + 胜率预估 + 地形加成 + 单位卡 + 五枚圆形动作钮）、**胜利结算**（`ui/VictoryScreen.gd`，程序化天光/山脊/云带/仙山/飞鹤背景 + 三路线徽记 + 最终结算卷轴）、**青云宗建筑群**（`world/Buildings.gd`，十种原型：大殿/帝都/藏经阁/炼丹楼/合院/阵法台/灵植园/讲道台/祖祠/山门，青琉璃瓦 + 金脊 + 朱柱 + 玉台栏杆 + 宝顶）。共用件 `ui/ScrollFrame.gd`（卷轴外框）与 `ui/RatioBar.gd`（细进度条）。**旧面板结构一字不动只置 `visible=false` 作「隐藏断言镜像」**，故 R4 69/69、R7 77/77 原样通过；`tools/check.ps1` 24 阶段全绿，交付物清单 R8 由 20 项扩为 **31 项**。纪要见 ROADMAP §4.10。
>
> **R9 W0 收尾清账 ✅ 已完成**（服务端只改 1 处字段裁剪，玩法数值零改动）：`StateView` 对**非玩家宗门**的弟子剥离 `assignedPeakId`（与敌方灵峰早已剥离 `fengZhuId` 同口径，防止「他归属哪座峰」随可见格泄露）；`PROTOCOL_2.0.md` §11.2 更名「结案记录」，四处实质 TODO 全部回查 1.0 源码后给出结论（`querySpiritPeakBlocker` 不是命令 / 敌方 `assignedPeakId` 已剥离 / 灵泉 `minFactor = 3 ÷ 6 = 0.5` / 三流派 46 键审计完毕，4 个死键在 1.0 亦无消费点），`TODO(需核对)` 7 处 → **3 处**（均为对标记本身的说明）。纪要见 ROADMAP §4.11。
>
> **R9 W1 补全默认皮肤 ✅ 已完成**（`AssetGen` 989 → 1342 行，覆盖 52 → **75** 个 ID）：新增 `districts` 6（首府/修炼/丹器/藏经/法坛/市集）、`improvements` 8（灵田/灵矿/采石/药园/聚灵阵/青石路/洞府/灵泉修缮）、`features` 8（灵林/雾泽/灵田/灵脉/机缘/秘境/灵泉/灵峰）、`audio` 1（16000 Hz × 8 秒五声音阶 BGM，频率与 LFO 周期整除 8 秒故首尾无缝），全部程序化生成、确定性可复现。顺带修掉**两处一直掩盖在 WARN 下的真 bug**：`asset_root` 是绝对文件系统路径，`ResourceLoader.load()` 只认 `res://`，故音频/字体必须走 `AudioStreamWAV.load_from_file()` / `FontFile.load_dynamic_font()`；`loop` 字段改由资源库兑现。验收 `ASSETVERIFY_OK covered=75 warned=0`，剩余 2 条 WARN 恰为 `font.body` / `font.title`（按裁决保留回退占位，manifest 标 `"pending": "art"`）。`tools/check.ps1` **179/179** 全绿，`check_protocol.ps1` 38/38。纪要见 ROADMAP §4.12。
>
> **R9 W3 Windows 导出 ✅ 已完成**（`tools/export.ps1` 一键产出 `dist/xiuxian/`）：`Xiuxian.exe` + `XiuxianServer.exe`（各 97.5 MB，含 `.pck`）+ `data/gameConfig.json` + `assets/**`。**关键点是两种运行态的根目录口径**——导出后 `res://` 已指向可执行文件所在目录，再取一次上一级就会把所有资源/配置定位到错误位置，故 `Launcher.repo_root()` 按 `OS.has_feature("template")` 分流，导出态直接返回可执行文件目录，并改为拉起**同目录**的 `XiuxianServer.exe`（不带 `--path`）。新增 `client/tests/R9ClientTest.gd`（17 条断言，用 `_exported_override` 强制切态验证两套口径）；`check.ps1` 扩为 **25 阶段**，新增 `[22/25]` 导出冒烟：真跑一次导出 → 断言四个产物 + `art/default` 74 个模型贴图 → **真启动导出态服务端并断言监听 19641**（无模板或 `-SkipExport` 时打 `[SKIP]`）。`check.ps1` **200/200** 全绿。纪要见 ROADMAP §4.13。

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
