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
│   ├── scenes/      # 场景（主菜单、地图、HUD、各类面板）
│   └── scripts/
│       ├── net/     # WebSocket 客户端、消息收发、服务端子进程拉起
│       ├── world/   # 六边形地图、相机、地块/单位/建筑渲染
│       ├── ui/      # HUD 与各功能面板
│       └── art/     # AssetLibrary：按逻辑资源 ID 加载美术
├── server/          # Godot headless 服务端工程（权威规则层，不渲染）
│   ├── scenes/      # ServerMain 主场景（--headless）
│   └── scripts/
│       ├── net/     # WebSocket 服务端、会话、命令分发
│       ├── model/   # 实体与 GameState（纯数据）
│       ├── rules/   # 全部规则：移动/战斗/经济/城市/道统/探索/胜利/AI
│       ├── config/  # gameConfig.json 加载与校验
│       └── save/    # 存档读写
├── shared/          # 两端共享（协议常量/枚举/DTO/六边形几何），通过目录联接挂载
│   └── protocol/
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

> R0 里程碑完成后此处给出可直接运行的命令。当前仓库为骨架 + 需求文档阶段。

1. 安装 Godot 4.x（使用标准 GDScript 版即可，无需 .NET 版）。
2. 首次拉取后运行 `tools/setup_shared.ps1`，把顶层 `shared/` 以目录联接（junction）挂到 `client/` 与 `server/`。
3. 开发：`tools/run_dev.ps1` 一键拉起 headless 服务端 + 客户端。
4. 自检：`tools/check.ps1`（服务端无头固定种子跑 N 回合，校验确定性与关键规则）。

---

## 仓库规则（务必遵守）

- 每个里程碑 / 任务完成并通过自检后，**立即提交并推送到 `main`**：
  `git add -A && git commit -m "feat(模块): 简述" && git push`。
- 提交信息使用约定式提交：`feat / fix / docs / refactor / test / chore / perf`。
- 网络走本机代理时，仅对单条命令临时加 `-c http.proxy=http://127.0.0.1:7890`，**不要**写进全局配置。
- 规则、数值的唯一权威是 `data/gameConfig.json` 与服务端 `rules/`；客户端不实现任何玩法规则。

## 2.0 首版范围（速览）

- **纳入**：**分层地形起伏与河流（基底/海拔/地貌/河流/险地）、三层画卷迷雾**、三流派、弟子修炼与境界、回合经济、灵峰城市与区域、地块改良与道路、道统科技树、十兵种战术战斗（含丘陵高地/跨河）、探索机缘秘境、任命渡劫飞升、政令（裁剪）、自动化、三流派胜利、基础反应式 AI、存档。
- **暂不纳入**（首版明确裁剪，详见需求文档第 5 章）：外交/厌战、随机事件、叛乱/忠诚、蛮族巢穴、灾劫、AI 长期战略性格；更多地形（雨林/沙漠/雪原/自然奇观/登山单位）。
