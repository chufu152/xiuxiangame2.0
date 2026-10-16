# WorkBuddy 开工提示词（R0–R9）

本目录是**给 WorkBuddy 逐里程碑执行的任务提示词**。每个提示词都是一份独立、可直接复制粘贴的指令，内含：必读文件锚点、硬约束、文件清单、可执行自动验收、完成后提交。

## 用法

1. 按里程碑顺序，一次只派发一个提示词（R0 通过后再派 R1，不得跳步）。
2. WorkBuddy 专家统一选 **Godot 游戏脚本工程师（Godot 4.4 / GDScript）**。
3. 把对应 `R*_*.md` 的**全文**复制给 WorkBuddy；要求它**先只读引用的文档、不自创规则/数值**，完成后跑自检并自行提交。
4. 每个里程碑结束，检查自检是否全绿、有无残留进程、是否已 push，再进入下一个。

## 环境（已确认）

- 引擎：**Godot 4.4.1 stable（标准 GDScript 版，非 .NET）**
- GUI 版：`C:\Users\Administrator\godot\Godot_v4.4.1-stable_win64.exe`
- 控制台/headless 版：`C:\Users\Administrator\godot\Godot_v4.4.1-stable_win64_console.exe`
- 服务端：`--headless --path server`，监听 `127.0.0.1:9527`
- 客户端：`--path client`
- 若 Godot 路径变动，放 `tools/godot_path.txt`（不入库）或设环境变量 `GODOT_CONSOLE_EXE`。

## Windows 环境已知坑（R0 实证，务必遵守）

1. **先 `--import` 再运行**：新克隆或新增 `class_name` 全局类后，第一次跑工程要先生成全局类缓存，否则所有全局类报 "not declared"：
   - `Godot_v4.4.1-stable_win64_console.exe --headless --path server --import`
   - `Godot_v4.4.1-stable_win64.exe --headless --path client --import`
   - `tools/check.ps1` 已内置；新增脚本/场景后若报类未声明，重跑 import。
2. **拉子进程不要用 `Start-Process`**：本机同时存在大小写两份 `HTTP_PROXY`/`http_proxy`，`Start-Process` 重建环境块会抛"已添加项"。工具脚本统一用 .NET `System.Diagnostics.Process`；**等待服务端就绪用 TCP 端口轮询**，不要依赖匹配控制台日志。
3. **脚本不要设 `[Console]::OutputEncoding`**：CP936 控制台强行切 UTF-8 会导致中文乱码；日志输出用英文，或交给 Godot 自身处理。

## 通用硬约束（每个里程碑都适用）

- 完全 Godot 4.4 + GDScript 静态类型，**零 Java、零 JVM**，全仓库无 `.java`。
- 服务端权威、客户端零规则；规则/数值唯一权威是 `data/gameConfig.json` 与服务端 `rules/`。
- 2.5D：**正交相机锁定 yaw/pitch=45°，禁止旋转**；缩放/平移/任何操作与 view 刷新后相机不重置。
- 美术资源独立可替换（逻辑 ID → manifest 映射），缺失只 WARN 不崩。
- 每任务结束**无残留 godot 进程**，自检 `tools/check.ps1` 全绿。
- 提交用约定式英文信息。**远程固定用 HTTPS（不要改成 SSH）**：仓库本地已配代理 7890、凭据走 Windows 凭据管理器（chufu152 已登录）。WorkBuddy 在自己的 worktree 提交后，直接执行 `git push origin HEAD:main` 即可（保持 Clash 代理开启）；主工作区在 main 分支则 `git push origin main`。
- 新 clone 的仓库没有仓库本地代理时，先执行（仅本仓库，**不是 `--global`**）：`git config http.proxy http://127.0.0.1:7890 && git config https.proxy http://127.0.0.1:7890`；或临时 `git -c http.proxy=http://127.0.0.1:7890 -c https.proxy=http://127.0.0.1:7890 push origin HEAD:main`。
- 若报 401/403，加 `-c credential.helper=manager` 强制走凭据管理器；**不要自行生成 SSH key、不要改 remote**（现有公钥未在 GitHub 注册，SSH 会 Permission denied）。
- 代理只在本机 Clash 开启时有效；推送报连接失败先确认 7890 端口在监听。

## 里程碑与提示词

| 里程碑 | 内容 | 服务端 | 客户端 | 提示词 |
|---|---|---|---|---|
| **R0** | 双 Godot 工程 + shared 联接 + WebSocket 握手 + config 加载 + 启动器 | ping/hello、错误码框架 | 连接、hello、Ping、拉起子进程 | ✅ `R0_工程骨架.md` |
| **R1** | 分层地形生成、newGame/getState、view 快照、视野 | 地图/初始化/视野（无回合） | 起伏 2.5D、连绵山体、河流、锁定相机、三态迷雾、主菜单 | ✅ `R1_地图开局.md` |
| R2 | 回合推进、单位移动/驻防、ZOC、道路、路径 | endTurn、move、garrison、go 等 | 移动动画、路径预览、选中 | 待生成 |
| R3 | 灵峰城市、区域、改良、道路、弟子槽 | found/build/repair/... | 建造面板、区域/改良渲染 | 待生成 |
| R4 | 经济产出、道统科技树、政令、任命位 | 结算/产出/boost/政令 | 经济栏、科技树、政令卡、任命 UI | 待生成 |
| R5 | 修炼突破、战斗、十种单位、战术 | 战斗/伤亡/经验/捕获 | 战斗面板、战报、战斗动画 | 待生成 |
| R6 | 探索/机缘/秘境/灵泉、飞升 | explore、秘境、tribulation | 探索事件 UI、抉择弹窗 | 待生成 |
| R7 | 三流派胜利、反应式 AI、存档/读档 | 胜利判定、AI、save | 胜利/失败屏、存档菜单 | 待生成 |
| R8 | 表现与 UI 打磨、小地图、设置、引导 | 仅协议补字段 | 正式 HUD/面板/框选/泼墨转场/昼夜粒子 | 待生成 |
| R9 | 皮肤化、平衡、默认水墨皮肤、Win 导出 | 平衡微调 | 皮肤切换、导出 | 待生成 |

> 命令清单（69 条）、view 字段、数值口径、裁剪范围见 `docs/REQUIREMENTS_2.0.md`。
> 后续里程碑提示词在进入该里程碑时再生成，保持与当时代码/文档一致。
