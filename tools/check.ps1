#Requires -Version 5.1
<#
.SYNOPSIS
    里程碑自检：R0 工程骨架 + R1 地图开局 + R1.5 协议契约 + R2 回合/移动/视野
    + R3 经济结算/灵峰城市/建筑区域劳力改良道路 + R4 道统/修炼/项目队列/收徒
    + R5 十兵种/战斗预览与结算/转职晋升/传送驻守/批量移动
    + R6 探索（机缘/秘境）/政令（政体/卡牌）/自动化（开关/立即探索/集结回防）
    + R7 任命/血脉/渡劫飞升/反应式 AI/胜负与评分/存档读档/胜利择一
    + R8 表现与 UI 打磨（69 命令全入口 / 水墨转场 / 昼夜粒子 / 小地图 / 设置 / 引导）
    + R9 皮肤化与导出（默认皮肤 75 个资源 / 导出态路径解析 / Windows 独立产物）
    （对应 docs/prompts/*.md「自动验收」）。

.DESCRIPTION
    依次执行：
      [0/26] 环境与交付物清单（R0 + R1 + R3 + R4 + R5 + R6 + R7 + R8）
      [1/26] shared/ 目录联接：幂等 + 内容贯通（临时文件在另一处可见）
      [2/26] 两个工程 --import 无解析错误并生成 class_name 缓存
      [3/26] 配置缺失时服务端非零退出（负向用例）
      [4/26] console 版 --headless 启动服务端并监听 127.0.0.1:9527
      [5/26] 运行 res://tests/SmokeTest.tscn，断言 SMOKE_PASS 且退出码 0（R0 协议回归）
      [6/26] 清理本脚本拉起的 Godot 进程，断言 tasklist 无残留
      [7/26] 服务端 R1 验收：res://tests/R1Test.tscn 打印 R1_PASS、退出码 0，
            且同种子双跑导出的权威地图 outputs/r1_authority_a|b.json 逐字一致（SHA256 相同）
      [8/26] 服务端 R2 验收：res://tests/R2Test.tscn 打印 R2_PASS、退出码 0
            （回合状态机 + 地形叠加移动成本 + BFS 可达 + 移动后视野刷新 + 确定性）
      [9/26] 客户端 R1 验收：res://tests/R1ClientTest.tscn 无头全绿；
            再加 --integration 端到端（真实拉起 headless 服务端 + newGame 300 格 view + getState 往返）
      [10/26] 客户端 R2 验收：res://tests/R2ClientTest.tscn 无头全绿；
            再加 --integration 端到端（点选弟子 → 移动高亮 → moveDisciple → 结束回合 → 相机不重置）
      [11/26] 服务端 R3 验收：res://tests/R3Test.tscn 打印 R3_PASS、退出码 0
            （开峰 + 建筑 10 种 + 区域/邻接 + 劳力 + 改良地形限制 + 经济结算/赤字 + 道路减耗 + 气运扩张 + 确定性）
      [12/26] 客户端 R3 验收：res://tests/R3ClientTest.tscn 无头全绿；
            再加 --integration 端到端（选中灵峰 → 城市面板 → 建造山门 → 指派劳力 → 相机不重置）
      [13/26] 服务端 R4 验收：res://tests/R4Test.tscn 打印 R4_PASS、退出码 0
            （21 道法树前置/时代/流派/血脉门控 + 研究队列 + 修炼/突破/渡劫 + 收徒 + 项目队列取消/加速 + 成就 boost + 确定性）
      [14/26] 客户端 R4 验收：res://tests/R4ClientTest.tscn 无头全绿；
            再加 --integration 端到端（道统树三态 → 研究道法 → 队列两列不混 → 加速 → 收徒 → 取消 → 相机不重置）
      [15/26] 服务端 R5 验收：res://tests/R5Test.tscn 打印 R5_PASS、退出码 0
            （十兵种/相克/地形防御/高台/河流/城防 + 攻击预览与结算一致 + ZOC/占格阻挡 + 传送 + 驻守 + 转职晋升 + 批量移动 + 确定性）
      [16/26] 客户端 R5 验收：res://tests/R5ClientTest.tscn 无头全绿；
            再加 --integration 端到端（点选三段串行链 → 十兵种转职三态 → 攻击预览 blockedReason →
            attack/reclass/promote/retreat 业务失败提示 → 传送未开启 → Shift 多选 batchMove → 两层高亮独立 → 相机不重置）
      [17/26] 服务端 R6 验收：res://tests/R6Test.tscn 打印 R6_PASS、退出码 0
            （机缘成功率/失败三分支 + 秘境成本/人数/富矿与灾祸 + 政体切换冷却 + 卡牌槽位/时代/道法门控 + 政令安定叠加
             + 自动化预算与建造者扣次 + 集结超限拒绝 + setSetting 不下发 view + 回合回填 + 确定性）
      [18/26] 客户端 R6 验收：res://tests/R6ClientTest.tscn 无头全绿；
            再加 --integration 端到端（点节点格开探索面板 → 派弟子 → 政令面板颁卡 → 自动化开关/立即探索/集结 → 本地设置 → 相机不重置）
      [19/26] 服务端 R7 验收：res://tests/R7Test.tscn 打印 R7_PASS、退出码 0
            （任命名额/境界门控/峰主长老宗主加成 + 联姻繁衍冷却与品级抖动 + 渡劫成功率/心魔/陨落
             + AI 反应式行动与视野刷新 + 三流派胜负/失败清算 + 评分公式/240 回合强制结算
             + 待抉择 awaitInput/resolveChoice + 存档 {slot,saved} 与读档 view 逐字一致 + 确定性双跑 SHA256）
      [20/26] 客户端 R7 验收：res://tests/R7ClientTest.tscn 无头全绿；
            再加 --integration 端到端（胜利进度面板 → 存读档往返 → awaitInput 弹窗 → resolveChoice →
            结局屏 → 事件栏 → 相机不重置）
      [21/26] 客户端 R8 验收：res://tests/R8ClientTest.tscn 无头全绿；
            再加 --integration 端到端（hello 70 条 → 装饰层按真 view 生成 → 小地图只平移 →
            泼墨/存读档/结束回合/getState 全序列相机不重置 → setSetting 不进 view → 资源栏 13 项）
      [22/26] R9 皮肤化 + Windows 导出冒烟：
            客户端 R9 无头验收（开发态/导出态两套根目录口径 + 缺 exe 时报错可诊断 +
            皮肤包切换路径层）→ 端到端换皮（view 逐字不变 / 相机不变 / 贴图实例真换）
            → 第二套皮肤包 zhu_xia 资源验收 75/75 → 预设文件断言 →
            tools/export.ps1 产出 dist\xiuxian\{Xiuxian.exe,XiuxianServer.exe} →
            导出态服务端 --headless 监听
            （未安装 4.4.1 导出模板或指定 -SkipExport 时打印 SKIP，跳过实际导出）
      [23/26] 扫描仓库确认无 .java 文件（零 Java 约束）+ 最终残留进程断言
      [24/26] 协议契约校验：docs/PROTOCOL_2.0.md 覆盖 69 条 + ping（tools/check_protocol.ps1）
      [25/26] 平衡抽样器自检：res://tools/BalanceSim.tscn --verify 双跑同一局，
            断言终局指纹一致（抽样本身可复现）；并校验 docs/BALANCE_REPORT.md
            章节骨架齐全、含「不改数值」声明
            （不在此重跑 72 局全量抽样——那是 --games=12 的手工动作，见 docs/BALANCE_REPORT.md）

    退出码：0 = 全绿；1 = 存在失败项。

    说明：本脚本用 .NET Process 而非 Start-Process 启动子进程——本机环境块同时存在
    HTTP_PROXY 与 http_proxy，Start-Process 重建环境字典时会抛「已添加项。字典中的
    关键字…」，导致子进程根本无法启动。.NET Process 继承父进程环境块，规避该问题。
    服务端就绪改用 TCP 端口轮询判定（Godot 对 stdout 重定向的行为不稳定，不依赖日志匹配）。
    读取子进程输出使用「有界等待」：客户端 --integration 会拉起服务端子进程并继承 stdout
    管道，若子进程未及时回收，无限等待会挂死自检，故超时后放弃读取并让断言显式失败。

.PARAMETER Port
    自检使用的端口，默认 9527（客户端端到端验收自带 19537，不冲突）。

.PARAMETER SkipImport
    跳过工程导入（缓存已存在时可加速）。

.PARAMETER SkipExport
    跳过 [22/26] 的实际导出（预设文件与产物路径断言仍会执行）。

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools\check.ps1
    （本机执行策略为 Restricted，必须用 -ExecutionPolicy Bypass；仓库不提供 .cmd 包装）
#>
[CmdletBinding()]
param(
    [int]$Port = 9527,
    [switch]$SkipImport,
    [switch]$SkipExport
)

$ErrorActionPreference = 'Stop'

# 说明：不修改 [Console]::OutputEncoding——在 CP936 控制台强行切到 UTF-8 反而会乱码。
# 脚本自身的中文用 Write-Host（走控制台 API）输出；Godot 子进程输出一律用 .NET Process
# 显式按 UTF-8 解码（见 New-GodotStartInfo），不依赖控制台编码。

# ---------------------------------------------------------------------------
# 公共函数（与 run_dev.ps1 保持一致；不引入额外公共脚本，避免超出文件清单）
# ---------------------------------------------------------------------------

# 按 docs/prompts/README.md 的顺序定位 Godot 控制台版可执行文件。
function Resolve-GodotConsole {
    $fromEnv = $env:GODOT_CONSOLE_EXE
    if ($fromEnv -and (Test-Path -PathType Leaf $fromEnv)) { return (Resolve-Path $fromEnv).Path }

    $pointer = Join-Path $PSScriptRoot 'godot_path.txt'
    if (Test-Path -PathType Leaf $pointer) {
        $text = (Get-Content -Path $pointer -Raw -ErrorAction SilentlyContinue)
        if ($text) { $text = $text.Trim() }
        if ($text -and (Test-Path -PathType Leaf $text)) { return $text }
    }

    $fallback = 'C:\Users\Administrator\godot\Godot_v4.4.1-stable_win64_console.exe'
    if (Test-Path -PathType Leaf $fallback) { return $fallback }

    throw "找不到 Godot 4.4.1 控制台版可执行文件。请设置环境变量 GODOT_CONSOLE_EXE，或把路径写入 $pointer"
}

# 组装 ProcessStartInfo：默认继承环境块（不使用 Start-Process，规避环境字典重复键问题）。
function New-GodotStartInfo {
    param(
        [Parameter(Mandatory)][string]$Executable,
        [Parameter(Mandatory)][string[]]$Arguments,
        [switch]$CaptureOutput
    )
    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = $Executable
    $quoted = foreach ($item in $Arguments) {
        if ($item -match '[\s"]') { '"' + ($item -replace '"', '\"') + '"' } else { $item }
    }
    $info.Arguments = ($quoted -join ' ')
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    if ($CaptureOutput) {
        $info.RedirectStandardOutput = $true
        $info.RedirectStandardError = $true
        $utf8 = New-Object System.Text.UTF8Encoding $false
        $info.StandardOutputEncoding = $utf8
        $info.StandardErrorEncoding = $utf8
    }
    return $info
}

# 同步运行并捕获输出，返回 @{ StdOut; StdErr; ExitCode }。
# 读流用有界等待：--integration 拉起的服务端子进程会继承 stdout 管道，
# 无界 GetResult() 在子进程未回收时会永久阻塞，宁可放弃读取让断言失败。
function Invoke-GodotCapture {
    param(
        [Parameter(Mandatory)][string]$Executable,
        [Parameter(Mandatory)][string[]]$Arguments,
        [int]$TimeoutMs = 180000,
        [int]$DrainMs = 20000
    )
    $info = New-GodotStartInfo -Executable $Executable -Arguments $Arguments -CaptureOutput
    $process = [System.Diagnostics.Process]::Start($info)
    $outTask = $process.StandardOutput.ReadToEndAsync()
    $errTask = $process.StandardError.ReadToEndAsync()
    if (-not $process.WaitForExit($TimeoutMs)) {
        try { $process.Kill() } catch { }
        [void]$process.WaitForExit(5000)
    }
    $stdout = ''
    $stderr = ''
    if ($outTask.Wait($DrainMs)) { try { $stdout = $outTask.Result } catch { } }
    if ($errTask.Wait($DrainMs)) { try { $stderr = $errTask.Result } catch { } }
    return @{ StdOut = $stdout; StdErr = $stderr; ExitCode = $process.ExitCode }
}

# 轮询 TCP 端口，判断服务端是否已开始监听。
function Test-TcpPort {
    param([int]$Port, [string]$TargetHost = '127.0.0.1', [int]$TimeoutMs = 400)
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $async = $client.BeginConnect($TargetHost, $Port, $null, $null)
        if ($async.AsyncWaitHandle.WaitOne($TimeoutMs, $false)) {
            $client.EndConnect($async)
            return $true
        }
        return $false
    }
    catch { return $false }
    finally { try { $client.Close() } catch { } }
}

# 找出仍在运行、且命令行指向指定工程目录的 Godot 进程。
function Get-ProjectGodotProcesses {
    param([Parameter(Mandatory)][string]$ProjectPath)
    $needle = ($ProjectPath -replace '/', '\').TrimEnd('\')
    $result = @()
    $processes = Get-CimInstance Win32_Process -Filter "Name LIKE 'Godot%'" -ErrorAction SilentlyContinue
    foreach ($process in $processes) {
        if ($process.CommandLine -and $process.CommandLine.Contains($needle)) { $result += $process }
    }
    return $result
}

# 强制回收指定工程目录下的全部 Godot 进程（返回被回收的进程对象）。
function Stop-ProjectGodotProcesses {
    param([Parameter(Mandatory)][string[]]$ProjectPaths)
    $killed = @()
    foreach ($path in $ProjectPaths) {
        foreach ($item in (Get-ProjectGodotProcesses -ProjectPath $path)) {
            try {
                Stop-Process -Id $item.ProcessId -Force -ErrorAction SilentlyContinue
                $killed += $item
            }
            catch { }
        }
    }
    return $killed
}

# ---------------------------------------------------------------------------
# 断言
# ---------------------------------------------------------------------------

$script:checkCount = 0
$script:failCount = 0

function Assert-Check {
    param(
        [bool]$Condition,
        [string]$Description,
        [string]$Detail = ''
    )
    $script:checkCount++
    if ($Condition) {
        Write-Host "  [PASS] $Description" -ForegroundColor Green
    }
    else {
        $script:failCount++
        Write-Host "  [FAIL] $Description" -ForegroundColor Red
        if ($Detail) {
            foreach ($line in ($Detail -split "`n")) {
                if ($line.Trim()) { Write-Host "         $line" -ForegroundColor DarkGray }
            }
        }
    }
}

# 从 Godot 输出里摘出失败/错误行，便于失败时定位。
function Select-GodotProblems {
    param([string]$Text)
    $result = @()
    foreach ($line in ($Text -split "`r?`n")) {
        if ($line -match 'R1_FAIL|R1_CLIENT_FAIL|R2_FAIL|R2_CLIENT_FAIL|R3_FAIL|R3_CLIENT_FAIL|R4_FAIL|R4_CLIENT_FAIL|R5_FAIL|R5_CLIENT_FAIL|R6_FAIL|R6_CLIENT_FAIL|SMOKE_FAIL|Parse Error|SCRIPT ERROR') { $result += $line.Trim() }
    }
    return $result
}

# ---------------------------------------------------------------------------
# 主流程
# ---------------------------------------------------------------------------

$root = Split-Path -Parent $PSScriptRoot
$serverPath = Join-Path $root 'server'
$clientPath = Join-Path $root 'client'
$sharedPath = Join-Path $root 'shared'
$dataPath = Join-Path $root 'data\gameConfig.json'

$workDir = Join-Path ([IO.Path]::GetTempPath()) ('xiuxian-check-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $workDir -Force | Out-Null

$serverProcess = $null
$serverOutTask = $null
$serverErrTask = $null

try {
    Write-Host "=== 修仙4X·宗门争霸 2.0 —— 里程碑自检（R0 + R1 + R2 + R3 + R4 + R5 + R6 + R7）===" -ForegroundColor Cyan
    Write-Host "仓库根：$root"
    Write-Host "临时目录：$workDir"

    # ---------------------------------------------------------------- 0. 环境
    Write-Host "`n[0/26] 环境与交付物清单（R0 + R1 + R3 + R4 + R5 + R6 + R7 + R8）" -ForegroundColor Cyan
    $godotExe = $null
    try { $godotExe = Resolve-GodotConsole }
    catch { Assert-Check $false '定位 Godot 控制台版可执行文件' $_.Exception.Message }
    Assert-Check ([bool]$godotExe) '定位 Godot 控制台版可执行文件' "路径：$godotExe"
    if ($godotExe) { Write-Host "  Godot: $godotExe" }

    $r0Files = @(
        'shared\protocol\commands.gd', 'shared\protocol\msg.gd', 'shared\protocol\enums.gd',
        'shared\protocol\dto.gd', 'shared\geo\hex.gd',
        'server\project.godot', 'server\scenes\ServerMain.tscn', 'server\scenes\ServerMain.gd',
        'server\scripts\net\NetServer.gd', 'server\scripts\net\CommandDispatcher.gd',
        'server\scripts\config\ConfigLoader.gd', 'server\scripts\config\ConfigValidator.gd',
        'data\gameConfig.json',
        'server\tests\SmokeTest.tscn', 'server\tests\SmokeTest.gd',
        'client\project.godot', 'client\scenes\Main.tscn', 'client\scenes\Main.gd',
        'client\scripts\net\NetClient.gd', 'client\scripts\net\Launcher.gd',
        'tools\setup_shared.ps1', 'tools\run_dev.ps1', 'tools\check.ps1'
    )
    $r1Files = @(
        'server\scripts\rng\RngService.gd',
        'server\scripts\model\HexTile.gd', 'server\scripts\model\GameNode.gd',
        'server\scripts\model\Sect.gd', 'server\scripts\model\Disciple.gd',
        'server\scripts\model\SpiritPeak.gd', 'server\scripts\model\GameState.gd',
        'server\scripts\rules\MapGenerator.gd', 'server\scripts\rules\SetupInitializer.gd',
        'server\scripts\rules\VisionCalculator.gd', 'server\scripts\net\StateView.gd',
        'server\tests\R1Test.gd', 'server\tests\R1Test.tscn',
        'client\scripts\art\AssetLibrary.gd', 'client\scripts\net\Session.gd',
        'client\scripts\world\HexMap.gd', 'client\scripts\world\Fog.gd',
        'client\scripts\world\CameraRig.gd', 'client\scripts\world\UnitView.gd',
        'client\scripts\world\SectView.gd', 'client\scripts\ui\MainMenu.gd',
        'client\scenes\World.gd', 'client\scenes\World.tscn', 'client\scenes\MainMenu.tscn',
        'client\tests\R1ClientTest.gd', 'client\tests\R1ClientTest.tscn'
    )
    $expectedFiles = $r0Files + $r1Files
    $r3Files = @(
        'server\scripts\model\Project.gd', 'server\scripts\model\District.gd',
        'server\scripts\model\Improvement.gd',
        'server\scripts\rules\EconomyRules.gd', 'server\scripts\rules\CityRules.gd',
        'server\scripts\rules\ImprovementRules.gd', 'server\scripts\rules\RoadNetworkService.gd',
        'server\scripts\rules\CityAction.gd', 'server\scripts\rules\ImprovementAction.gd',
        'server\tests\R3Test.gd', 'server\tests\R3Test.tscn',
        'client\tests\R3ClientTest.gd', 'client\tests\R3ClientTest.tscn'
    )
    $expectedFiles += $r3Files
    $r4Files = @(
        'server\scripts\model\Dao.gd', 'server\scripts\model\ResearchProject.gd',
        'server\scripts\rules\DaoRules.gd', 'server\scripts\rules\DaoAction.gd',
        'server\scripts\rules\DiscipleRules.gd', 'server\scripts\rules\ProjectRules.gd',
        'server\tests\R4Test.gd', 'server\tests\R4Test.tscn',
        'client\tests\R4ClientTest.gd', 'client\tests\R4ClientTest.tscn'
    )
    $expectedFiles += $r4Files
    $r5Files = @(
        'server\scripts\rules\UnitRules.gd', 'server\scripts\rules\CombatResolver.gd',
        'server\scripts\rules\CombatAction.gd', 'server\scripts\rules\UnitAction.gd',
        'server\scripts\rules\TeleportRules.gd',
        'server\tests\R5Test.gd', 'server\tests\R5Test.tscn',
        'client\tests\R5ClientTest.gd', 'client\tests\R5ClientTest.tscn'
    )
    $expectedFiles += $r5Files
    $r6Files = @(
        'server\scripts\rules\ExploreRules.gd', 'server\scripts\rules\PolicyRules.gd',
        'server\scripts\rules\AutomationRules.gd',
        'server\scripts\rules\ExploreAction.gd', 'server\scripts\rules\PolicyAction.gd',
        'server\scripts\rules\AutomationAction.gd',
        'server\tests\R6Test.gd', 'server\tests\R6Test.tscn',
        'client\tests\R6ClientTest.gd', 'client\tests\R6ClientTest.tscn'
    )
    $expectedFiles += $r6Files
    $r7Files = @(
        'server\scripts\model\SaveInfo.gd',
        'server\scripts\rules\AppointmentRules.gd', 'server\scripts\rules\VictoryRules.gd',
        'server\scripts\rules\BloodlineRules.gd', 'server\scripts\rules\AIController.gd',
        'server\scripts\save\SaveManager.gd',
        'server\scripts\rules\AppointmentAction.gd', 'server\scripts\rules\VictoryAction.gd',
        'server\scripts\rules\SaveAction.gd',
        'server\tests\R7Test.gd', 'server\tests\R7Test.tscn',
        'client\tests\R7ClientTest.gd', 'client\tests\R7ClientTest.tscn'
    )
    $expectedFiles += $r7Files
    $r8Files = @(
        'client\scripts\world\Decorations.gd', 'client\scripts\world\Scenery.gd',
        'client\scripts\world\Buildings.gd',
        'client\scripts\ui\ActionBar.gd', 'client\scripts\ui\Toast.gd',
        'client\scripts\ui\Minimap.gd', 'client\scripts\ui\SettingsPanel.gd',
        'client\scripts\ui\GuideOverlay.gd', 'client\scripts\ui\UiTheme.gd',
        'client\scripts\ui\RatioBar.gd', 'client\scripts\ui\ScrollFrame.gd',
        'client\scripts\ui\TurnSummary.gd', 'client\scripts\ui\DaoTreeCanvas.gd',
        'client\scripts\ui\DaoTreePanel.gd', 'client\scripts\ui\SavesScreen.gd',
        'client\scripts\ui\CombatScreen.gd', 'client\scripts\ui\VictoryScreen.gd',
        'client\tests\R8ClientTest.gd', 'client\tests\R8ClientTest.tscn',
        'client\tools\AssetGen.gd', 'client\tools\AssetGen.tscn',
        'client\tools\AssetVerify.gd', 'client\tools\AssetVerify.tscn',
        'client\tools\AssetPreview.gd', 'client\tools\AssetPreview.tscn',
        'client\tools\WorldShot.gd', 'client\tools\WorldShot.tscn',
        'client\tools\BuildingShot.gd', 'client\tools\BuildingShot.tscn',
        'assets\manifest.json', 'assets\README.md'
    )
    $expectedFiles += $r8Files
    $r9Files = @(
        'client\export_presets.cfg', 'server\export_presets.cfg',
        'tools\export.ps1',
        'client\tests\R9ClientTest.gd', 'client\tests\R9ClientTest.tscn',
        'server\tools\BalanceSim.gd', 'server\tools\BalanceSim.tscn',
        'docs\BALANCE_REPORT.md'
    )
    $expectedFiles += $r9Files
    $missing = @()
    foreach ($rel in $expectedFiles) {
        if (-not (Test-Path (Join-Path $root $rel))) { $missing += $rel }
    }
    Assert-Check ($missing.Count -eq 0) `
        "R0+R1+R3+R4+R5+R6+R7+R8+R9 交付物清单齐全（R0 $($r0Files.Count) + R1 $($r1Files.Count) + R3 $($r3Files.Count) + R4 $($r4Files.Count) + R5 $($r5Files.Count) + R6 $($r6Files.Count) + R7 $($r7Files.Count) + R8 $($r8Files.Count) + R9 $($r9Files.Count) 个文件）" `
        ("缺失：`n" + ($missing -join "`n"))

    if (-not $godotExe) { throw '未定位到 Godot 可执行文件，后续步骤无法进行。' }

    # ------------------------------------------- 1. shared 目录联接（幂等 + 贯通）
    Write-Host "`n[1/26] shared/ 目录联接（幂等 + 内容贯通）" -ForegroundColor Cyan
    $setupScript = Join-Path $PSScriptRoot 'setup_shared.ps1'

    $firstOk = $true; $firstErr = ''
    try { & $setupScript | Out-Null } catch { $firstOk = $false; $firstErr = $_.Exception.Message }
    $secondOk = $true; $secondErr = ''
    try { & $setupScript | Out-Null } catch { $secondOk = $false; $secondErr = $_.Exception.Message }

    Assert-Check $firstOk 'setup_shared.ps1 首次执行成功' $firstErr
    Assert-Check $secondOk 'setup_shared.ps1 可重复执行（幂等）' $secondErr

    $clientShared = Join-Path $clientPath 'shared'
    $serverShared = Join-Path $serverPath 'shared'
    foreach ($pair in @(@('client', $clientShared), @('server', $serverShared))) {
        $item = Get-Item $pair[1] -Force -ErrorAction SilentlyContinue
        $isJunction = $item -and (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)
        Assert-Check ([bool]$isJunction) "$($pair[0])/shared 是指向顶层 shared/ 的目录联接"
    }

    # 内容贯通：在 client/shared 建临时文件，断言 server/shared 与顶层 shared 均可见，随后删除。
    $probeName = '__junction_probe__.tmp'
    $probeClient = Join-Path $clientShared $probeName
    $probeServer = Join-Path $serverShared $probeName
    $probeTop = Join-Path $sharedPath $probeName
    $roundTripOk = $false
    try {
        Set-Content -Path $probeClient -Value 'junction-probe' -Encoding ASCII -ErrorAction Stop
        $roundTripOk = (Test-Path $probeServer) -and (Test-Path $probeTop)
    }
    catch { $roundTripOk = $false }
    finally {
        # 清理探测文件。部分托管/安全环境会拦截 Remove-Item 并抛出终止性异常（此时文件通常已被移走）。
        # 清理失败绝不能中断自检主流程——否则后续导入/启动/自测等核心验收步骤会被整体跳过。
        # 故逐个吞掉异常，并回退到 cmd del 兜底。
        foreach ($p in @($probeClient, $probeServer, $probeTop)) {
            if (Test-Path $p) {
                try { Remove-Item $p -Force -ErrorAction Stop }
                catch {
                    # 拦截后文件通常已被移走，del 会报「找不到」；在 Stop 模式下该错误会再次
                    # 变成终止异常，故必须连输出一起吞掉。
                    try { cmd /c del /f /q "$p" 2>&1 | Out-Null } catch { }
                }
            }
        }
    }
    Assert-Check $roundTripOk 'client/shared 写入内容在 server/shared 与顶层 shared 均可见'
    Assert-Check (-not (Test-Path $probeTop)) '临时探测文件已清理'

    # --------------------------------------------------------- 2. 工程导入
    Write-Host "`n[2/26] 工程导入与 GDScript 解析" -ForegroundColor Cyan
    if ($SkipImport) {
        Write-Host '  （-SkipImport：跳过导入步骤）' -ForegroundColor DarkGray
    }
    else {
        foreach ($project in @('server', 'client')) {
            $projectPath = Join-Path $root $project
            $result = Invoke-GodotCapture -Executable $godotExe `
                -Arguments @('--headless', '--path', $projectPath, '--import')
            $combined = ($result.StdOut + "`n" + $result.StdErr)
            $parseIssues = @()
            foreach ($line in ($combined -split "`r?`n")) {
                if ($line -match 'Parse Error|SCRIPT ERROR|Failed to load script') { $parseIssues += $line.Trim() }
            }
            Assert-Check ($parseIssues.Count -eq 0) "$project 工程导入无解析错误" ($parseIssues -join "`n")
            Assert-Check (Test-Path (Join-Path $projectPath '.godot\global_script_class_cache.cfg')) `
                "$project 生成 class_name 缓存（global_script_class_cache.cfg）"
        }
    }

    # --------------------------------------------- 3. 配置失败路径（负向用例）
    Write-Host "`n[3/26] 配置缺失时非零退出（负向用例）" -ForegroundColor Cyan
    $missingConfig = Join-Path $workDir 'not-exists.json'
    $badResult = Invoke-GodotCapture -Executable $godotExe `
        -Arguments @('--headless', '--path', $serverPath, '--', "--port=$Port", "--data=$missingConfig") `
        -TimeoutMs 60000
    $badCombined = ($badResult.StdOut + "`n" + $badResult.StdErr)
    Assert-Check ($badResult.ExitCode -ne 0) '配置缺失时服务端以非零退出码结束' "退出码：$($badResult.ExitCode)"
    Assert-Check ($badCombined -match 'config_load_failed|配置加载失败') '配置缺失时输出可诊断的失败原因' $badCombined.Trim()

    # ------------------------------------------------- 4. 启动 headless 服务端
    Write-Host "`n[4/26] headless 服务端启动并监听" -ForegroundColor Cyan
    $serverInfo = New-GodotStartInfo -Executable $godotExe `
        -Arguments @('--headless', '--path', $serverPath, '--', "--port=$Port", "--data=$dataPath") -CaptureOutput
    $serverProcess = [System.Diagnostics.Process]::Start($serverInfo)
    $serverOutTask = $serverProcess.StandardOutput.ReadToEndAsync()
    $serverErrTask = $serverProcess.StandardError.ReadToEndAsync()

    $deadline = (Get-Date).AddSeconds(30)
    $ready = $false
    while ((Get-Date) -lt $deadline) {
        if (Test-TcpPort -Port $Port) { $ready = $true; break }
        if ($serverProcess.HasExited) { break }
        Start-Sleep -Milliseconds 250
    }
    Assert-Check $ready "服务端在 30 秒内开始监听 127.0.0.1:$Port"
    Assert-Check (-not $serverProcess.HasExited) '服务端进程持续运行（未提前退出）'

    # ------------------------------------------------ 5. 无头自测（SmokeTest）
    Write-Host "`n[5/26] 无头自测（res://tests/SmokeTest.tscn，R0 协议回归）" -ForegroundColor Cyan
    if ($ready) {
        $smokeResult = Invoke-GodotCapture -Executable $godotExe `
            -Arguments @('--headless', '--path', $serverPath, 'res://tests/SmokeTest.tscn', '--', "--port=$Port") `
            -TimeoutMs 60000
        $smokeCombined = ($smokeResult.StdOut + "`n" + $smokeResult.StdErr)
        Assert-Check ($smokeCombined -match 'SMOKE_PASS') '自测打印 SMOKE_PASS' $smokeCombined.Trim()
        Assert-Check ($smokeResult.ExitCode -eq 0) '自测退出码为 0' "退出码：$($smokeResult.ExitCode)"
        Assert-Check ($smokeCombined -notmatch 'SMOKE_FAIL') '自测未出现 SMOKE_FAIL'
        Assert-Check ($smokeCombined -match 'hello\.protocolVersion == "2\.0"') '自测断言 hello.protocolVersion == "2.0"' $smokeCombined.Trim()
        Assert-Check ($smokeCombined -match 'hello\.saveVersion == "3\.0"') '自测断言 hello.saveVersion == "3.0"' $smokeCombined.Trim()
        Assert-Check ($smokeCombined -match 'implementedCommands 含 ping') '自测断言 implementedCommands 含 ping' $smokeCombined.Trim()
        Assert-Check ($smokeCombined -match 'ping 回包 result\.pong==true') '自测断言 ping 回包 result.pong==true' $smokeCombined.Trim()
        Assert-Check ($smokeCombined -match '未登记命令 errorCode == "UNKNOWN_COMMAND"') '自测断言未登记命令 -> UNKNOWN_COMMAND' $smokeCombined.Trim()
        Assert-Check ($smokeCombined -match '缺 id 帧 errorCode == "NO_ID"') '自测断言缺 id 帧 -> NO_ID' $smokeCombined.Trim()
    }
    else {
        Assert-Check $false '运行无头自测（服务端未就绪，已跳过）'
    }
}
catch {
    Assert-Check $false '自检流程未抛出异常' $_.Exception.Message
}
finally {
    # ------------------------------------------------------- 6. 清理与残留
    Write-Host "`n[6/26] 进程清理（R0 服务端）" -ForegroundColor Cyan

    if ($serverProcess) {
        try { $serverProcess.Refresh() } catch { }
        if (-not $serverProcess.HasExited) {
            try { $serverProcess.Kill() } catch { }
            try { [void]$serverProcess.WaitForExit(5000) } catch { }
        }
        # 进程结束后管道关闭，可读取累积的服务端启动日志并校验。
        $serverStdout = ''
        try { if ($serverOutTask.Wait(10000)) { $serverStdout = $serverOutTask.Result } } catch { }
        if ($serverStdout) {
            Assert-Check ($serverStdout -match 'server listening on 127\.0\.0\.1') `
                '服务端启动打印「server listening on 127.0.0.1」' $serverStdout.Trim()
            Assert-Check ($serverStdout -match 'config ok') '服务端启动完成配置加载与校验' $serverStdout.Trim()
        }
    }

    Start-Sleep -Milliseconds 800
    [void](Stop-ProjectGodotProcesses -ProjectPaths @($serverPath, $clientPath))
    Start-Sleep -Milliseconds 500

    $residualServer = Get-ProjectGodotProcesses -ProjectPath $serverPath
    $residualClient = Get-ProjectGodotProcesses -ProjectPath $clientPath
    Assert-Check ($residualServer.Count -eq 0) '结束后无残留 godot 服务端进程' `
        (($residualServer | ForEach-Object { "pid=$($_.ProcessId) $($_.CommandLine)" }) -join "`n")
    Assert-Check ($residualClient.Count -eq 0) '结束后无残留 godot 客户端进程' `
        (($residualClient | ForEach-Object { "pid=$($_.ProcessId) $($_.CommandLine)" }) -join "`n")
}

# ------------------------------------------- 7. 服务端 R1 验收（R1Test）
Write-Host "`n[7/26] 服务端 R1 验收（res://tests/R1Test.tscn）" -ForegroundColor Cyan
if ($godotExe) {
    $r1Result = Invoke-GodotCapture -Executable $godotExe `
        -Arguments @('--headless', '--path', $serverPath, 'res://tests/R1Test.tscn') `
        -TimeoutMs 300000
    $r1Combined = ($r1Result.StdOut + "`n" + $r1Result.StdErr)
    Assert-Check ($r1Combined -match 'R1_PASS checks=\d+') '服务端 R1 验收打印 R1_PASS checks=N' $r1Combined.Trim()
    Assert-Check ($r1Result.ExitCode -eq 0) '服务端 R1 验收退出码为 0' "退出码：$($r1Result.ExitCode)"
    Assert-Check ($r1Combined -notmatch 'R1_FAIL') '服务端 R1 验收未出现 R1_FAIL' `
        ((Select-GodotProblems -Text $r1Combined) -join "`n")

    # 同种子双跑导出的权威地图必须逐字一致（R1 验收第 1 条）。
    $authorityA = Join-Path $root 'outputs\r1_authority_a.json'
    $authorityB = Join-Path $root 'outputs\r1_authority_b.json'
    $hasAuthority = (Test-Path -PathType Leaf $authorityA) -and (Test-Path -PathType Leaf $authorityB)
    Assert-Check $hasAuthority '导出两份权威地图（outputs/r1_authority_a|b.json）' `
        "缺失：$authorityA / $authorityB"
    if ($hasAuthority) {
        $hashA = (Get-FileHash -Algorithm SHA256 -Path $authorityA).Hash
        $hashB = (Get-FileHash -Algorithm SHA256 -Path $authorityB).Hash
        $bytesA = (Get-Item $authorityA).Length
        Assert-Check ($hashA -eq $hashB) '同种子双跑权威地图逐字一致（SHA256 相同）' `
            "a=$hashA ($bytesA 字节)`nb=$hashB"
        Assert-Check ($bytesA -gt 1000) '权威地图导出非空' "$bytesA 字节"
    }
}
else {
    Assert-Check $false '运行服务端 R1 验收（未定位到 Godot，已跳过）'
}

# ------------------------------------------- 8. 服务端 R2 验收（回合 + 移动 + 视野）
Write-Host "`n[8/26] 服务端 R2 验收（res://tests/R2Test.tscn）" -ForegroundColor Cyan
if ($godotExe) {
    $r2Result = Invoke-GodotCapture -Executable $godotExe `
        -Arguments @('--headless', '--path', $serverPath, 'res://tests/R2Test.tscn') `
        -TimeoutMs 300000
    $r2Combined = ($r2Result.StdOut + "`n" + $r2Result.StdErr)
    Assert-Check ($r2Combined -match 'R2_PASS checks=\d+') '服务端 R2 验收打印 R2_PASS checks=N' $r2Combined.Trim()
    Assert-Check ($r2Result.ExitCode -eq 0) '服务端 R2 验收退出码为 0' "退出码：$($r2Result.ExitCode)"
    Assert-Check ($r2Combined -notmatch 'R2_FAIL') '服务端 R2 验收未出现 R2_FAIL' `
        ((Select-GodotProblems -Text $r2Combined) -join "`n")
}
else {
    Assert-Check $false '运行服务端 R2 验收（未定位到 Godot，已跳过）'
}

# ------------------------------------------- 9. 客户端 R1 验收（无头 + 端到端）
Write-Host "`n[9/26] 客户端 R1 验收（res://tests/R1ClientTest.tscn）" -ForegroundColor Cyan
if ($godotExe) {
    $clientResult = Invoke-GodotCapture -Executable $godotExe `
        -Arguments @('--headless', '--path', $clientPath, 'res://tests/R1ClientTest.tscn') `
        -TimeoutMs 120000
    $clientCombined = ($clientResult.StdOut + "`n" + $clientResult.StdErr)
    Assert-Check ($clientCombined -match 'R1_CLIENT_RESULT=OK') '客户端无头验收全绿（R1_CLIENT_RESULT=OK）' `
        ((Select-GodotProblems -Text $clientCombined) -join "`n")
    Assert-Check ($clientResult.ExitCode -eq 0) '客户端无头验收退出码为 0' "退出码：$($clientResult.ExitCode)"
    Assert-Check ($clientCombined -notmatch 'R1_CLIENT_FAIL') '客户端无头验收未出现 R1_CLIENT_FAIL'
    Assert-Check ($clientCombined -match '未探索侧栏不泄露地形') '侧栏对未探索格不泄露地形'
    Assert-Check ($clientCombined -match 'Godot 相机锁 yaw45 pitch-45 俯看') '相机锁 45° 且无旋转输入'
    Assert-Check ($clientCombined -match '同一缺失 logicalID 只 WARN 一次') '占位资源缺失只 WARN 一次不崩溃'

    $integrationResult = Invoke-GodotCapture -Executable $godotExe `
        -Arguments @('--headless', '--path', $clientPath, 'res://tests/R1ClientTest.tscn', '--', '--integration') `
        -TimeoutMs 240000
    $integrationCombined = ($integrationResult.StdOut + "`n" + $integrationResult.StdErr)
    # 必须匹配 R1_CLIENT_PASS: 前缀：仅凭中文 label 会把 push_error 的 R1_CLIENT_FAIL 也误判为 PASS。
    Assert-Check ($integrationCombined -match 'R1_CLIENT_PASS: 实际 Launcher/NetClient 收到 newGame hello') `
        '端到端：客户端拉起 headless 服务端并收到 newGame hello' `
        ((Select-GodotProblems -Text $integrationCombined) -join "`n")
    Assert-Check ($integrationCombined -match 'R1_CLIENT_PASS: 实际 newGame 返回300格 view') '端到端：newGame 返回 300 格 view'
    Assert-Check ($integrationCombined -match 'R1_CLIENT_PASS: 实际 newGame 返回四宗公开信息') '端到端：newGame 返回四宗公开信息'
    Assert-Check ($integrationCombined -match 'R1_CLIENT_PASS: 实际 getState 往返成功') '端到端：getState 往返成功'
    Assert-Check ($integrationCombined -match 'R1_CLIENT_PASS: 实际服务端刷新保持相机') '端到端：view 刷新保持相机 transform/size'
    Assert-Check ($integrationCombined -match 'R1_CLIENT_RESULT=OK') '端到端集成验收全绿（R1_CLIENT_RESULT=OK）' `
        ((Select-GodotProblems -Text $integrationCombined) -join "`n")

    # 端到端验收会拉起自己的服务端子进程，必须确认已回收。
    Start-Sleep -Milliseconds 800
    [void](Stop-ProjectGodotProcesses -ProjectPaths @($serverPath, $clientPath))
    Start-Sleep -Milliseconds 500
}
else {
    Assert-Check $false '运行客户端 R1 验收（未定位到 Godot，已跳过）'
}

# ------------------------------ 10. 客户端 R2 验收（点选 → 高亮 → 移动 → 结束回合）
Write-Host "`n[10/26] 客户端 R2 验收（res://tests/R2ClientTest.tscn）" -ForegroundColor Cyan
if ($godotExe) {
    $r2ClientResult = Invoke-GodotCapture -Executable $godotExe `
        -Arguments @('--headless', '--path', $clientPath, 'res://tests/R2ClientTest.tscn') `
        -TimeoutMs 120000
    $r2ClientCombined = ($r2ClientResult.StdOut + "`n" + $r2ClientResult.StdErr)
    Assert-Check ($r2ClientCombined -match 'R2_CLIENT_RESULT=OK') '客户端 R2 无头验收全绿（R2_CLIENT_RESULT=OK）' `
        ((Select-GodotProblems -Text $r2ClientCombined) -join "`n")
    Assert-Check ($r2ClientResult.ExitCode -eq 0) '客户端 R2 无头验收退出码为 0' "退出码：$($r2ClientResult.ExitCode)"
    Assert-Check ($r2ClientCombined -notmatch 'R2_CLIENT_FAIL') '客户端 R2 无头验收未出现 R2_CLIENT_FAIL'
    Assert-Check ($r2ClientCombined -match 'hello 前结束回合按钮禁用') 'R2 TopBar 结束回合按钮在 hello 前门控'

    $r2Integration = Invoke-GodotCapture -Executable $godotExe `
        -Arguments @('--headless', '--path', $clientPath, 'res://tests/R2ClientTest.tscn', '--', '--integration') `
        -TimeoutMs 300000
    $r2IntegrationCombined = ($r2Integration.StdOut + "`n" + $r2Integration.StdErr)
    # 与 R1 同理：必须匹配 R2_CLIENT_PASS: 前缀，否则 FAIL 也会被判 PASS。
    Assert-Check ($r2IntegrationCombined -match 'R2_CLIENT_PASS: 端到端：点选弟子后出现移动高亮') `
        '端到端 R2：点选己方弟子出现移动高亮' `
        ((Select-GodotProblems -Text $r2IntegrationCombined) -join "`n")
    Assert-Check ($r2IntegrationCombined -match 'R2_CLIENT_PASS: 端到端：高亮格数与 queryMoveRange 结果一致') '端到端 R2：高亮格数与 queryMoveRange 一致'
    Assert-Check ($r2IntegrationCombined -match 'R2_CLIENT_PASS: 端到端：moveDisciple 成功，权威位置更新') '端到端 R2：moveDisciple 成功且位置更新'
    Assert-Check ($r2IntegrationCombined -match 'R2_CLIENT_PASS: 端到端：移动后迷雾变化') '端到端 R2：移动后迷雾刷新'
    Assert-Check ($r2IntegrationCombined -match 'R2_CLIENT_PASS: 端到端：结束回合后回合数 \+1') '端到端 R2：结束回合后回合数 +1'
    Assert-Check ($r2IntegrationCombined -match 'R2_CLIENT_PASS: 端到端：beginPlayerTurn 恢复弟子移动力') '端到端 R2：beginPlayerTurn 恢复移动力'
    Assert-Check ($r2IntegrationCombined -match 'R2_CLIENT_PASS: 端到端：点选/移动/结束回合全程相机 transform/size 不变') '端到端 R2：全程相机不重置'
    Assert-Check ($r2IntegrationCombined -match 'R2_CLIENT_RESULT=OK') '端到端 R2 集成验收全绿（R2_CLIENT_RESULT=OK）' `
        ((Select-GodotProblems -Text $r2IntegrationCombined) -join "`n")

    Start-Sleep -Milliseconds 800
    [void](Stop-ProjectGodotProcesses -ProjectPaths @($serverPath, $clientPath))
    Start-Sleep -Milliseconds 500
}
else {
    Assert-Check $false '运行客户端 R2 验收（未定位到 Godot，已跳过）'
}

# ------------------------------ 11. 服务端 R3 验收（经济 + 城市 + 建筑/区域/劳力/改良/道路）
Write-Host "`n[11/26] 服务端 R3 验收（res://tests/R3Test.tscn）" -ForegroundColor Cyan
if ($godotExe) {
    $r3Result = Invoke-GodotCapture -Executable $godotExe `
        -Arguments @('--headless', '--path', $serverPath, 'res://tests/R3Test.tscn') `
        -TimeoutMs 300000
    $r3Combined = ($r3Result.StdOut + "`n" + $r3Result.StdErr)
    Assert-Check ($r3Combined -match 'R3_PASS checks=\d+') '服务端 R3 验收打印 R3_PASS checks=N' $r3Combined.Trim()
    Assert-Check ($r3Result.ExitCode -eq 0) '服务端 R3 验收退出码为 0' "退出码：$($r3Result.ExitCode)"
    Assert-Check ($r3Combined -notmatch 'R3_FAIL') '服务端 R3 验收未出现 R3_FAIL' `
        ((Select-GodotProblems -Text $r3Combined) -join "`n")
}
else {
    Assert-Check $false '运行服务端 R3 验收（未定位到 Godot，已跳过）'
}

# ------------------------------ 12. 客户端 R3 验收（选中灵峰 → 城市面板 → 建造 → 指派劳力）
Write-Host "`n[12/26] 客户端 R3 验收（res://tests/R3ClientTest.tscn）" -ForegroundColor Cyan
if ($godotExe) {
    $r3ClientResult = Invoke-GodotCapture -Executable $godotExe `
        -Arguments @('--headless', '--path', $clientPath, 'res://tests/R3ClientTest.tscn') `
        -TimeoutMs 120000
    $r3ClientCombined = ($r3ClientResult.StdOut + "`n" + $r3ClientResult.StdErr)
    Assert-Check ($r3ClientCombined -match 'R3_CLIENT_RESULT=OK') '客户端 R3 无头验收全绿（R3_CLIENT_RESULT=OK）' `
        ((Select-GodotProblems -Text $r3ClientCombined) -join "`n")
    Assert-Check ($r3ClientResult.ExitCode -eq 0) '客户端 R3 无头验收退出码为 0' "退出码：$($r3ClientResult.ExitCode)"
    Assert-Check ($r3ClientCombined -notmatch 'R3_CLIENT_FAIL') '客户端 R3 无头验收未出现 R3_CLIENT_FAIL'
    Assert-Check ($r3ClientCombined -match '未选中灵峰时城市面板不显示') 'R3 城市面板未选中灵峰时门控'

    $r3Integration = Invoke-GodotCapture -Executable $godotExe `
        -Arguments @('--headless', '--path', $clientPath, 'res://tests/R3ClientTest.tscn', '--', '--integration') `
        -TimeoutMs 300000
    $r3IntegrationCombined = ($r3Integration.StdOut + "`n" + $r3Integration.StdErr)
    # 与 R1/R2 同理：必须匹配 R3_CLIENT_PASS: 前缀，否则 FAIL 也会被判 PASS。
    Assert-Check ($r3IntegrationCombined -match 'R3_CLIENT_PASS: 端到端：queryCityDetail 面板显示人口') `
        '端到端 R3：城市面板显示人口/住房/安定' `
        ((Select-GodotProblems -Text $r3IntegrationCombined) -join "`n")
    Assert-Check ($r3IntegrationCombined -match 'R3_CLIENT_PASS: 端到端：queryBuildOptions 列出可建建筑（含山门）') '端到端 R3：queryBuildOptions 列出可建建筑'
    Assert-Check ($r3IntegrationCombined -match 'R3_CLIENT_PASS: 端到端：constructBuilding 成功并刷新 view') '端到端 R3：constructBuilding 成功且 view 更新'
    Assert-Check ($r3IntegrationCombined -match 'R3_CLIENT_PASS: 端到端：constructBuilding 扣 building\.costs\.SHAN_MEN=200 灵力') '端到端 R3：constructBuilding 扣 200 灵力'
    Assert-Check ($r3IntegrationCombined -match 'R3_CLIENT_PASS: 端到端：assignWorker 成功，workedTileIds 含候选格') '端到端 R3：assignWorker 成功且权威状态更新'
    Assert-Check ($r3IntegrationCombined -match 'R3_CLIENT_PASS: 端到端：选中灵峰/建造/指派劳力全程相机 transform/size 不变') '端到端 R3：全程相机不重置'
    Assert-Check ($r3IntegrationCombined -match 'R3_CLIENT_RESULT=OK') '端到端 R3 集成验收全绿（R3_CLIENT_RESULT=OK）' `
        ((Select-GodotProblems -Text $r3IntegrationCombined) -join "`n")

    Start-Sleep -Milliseconds 800
    [void](Stop-ProjectGodotProcesses -ProjectPaths @($serverPath, $clientPath))
    Start-Sleep -Milliseconds 500
}
else {
    Assert-Check $false '运行客户端 R3 验收（未定位到 Godot，已跳过）'
}

# ------------------------------ 13. 服务端 R4 验收（道统树 + 修炼/突破/渡劫 + 项目队列 + 收徒）
Write-Host "`n[13/26] 服务端 R4 验收（res://tests/R4Test.tscn）" -ForegroundColor Cyan
if ($godotExe) {
    $r4Result = Invoke-GodotCapture -Executable $godotExe `
        -Arguments @('--headless', '--path', $serverPath, 'res://tests/R4Test.tscn') `
        -TimeoutMs 180000
    $r4Combined = ($r4Result.StdOut + "`n" + $r4Result.StdErr)
    Assert-Check ($r4Combined -match 'R4_PASS checks=\d+') '服务端 R4 验收打印 R4_PASS checks=N' $r4Combined.Trim()
    Assert-Check ($r4Result.ExitCode -eq 0) '服务端 R4 验收退出码为 0' "退出码：$($r4Result.ExitCode)"
    Assert-Check ($r4Combined -notmatch 'R4_FAIL') '服务端 R4 验收未出现 R4_FAIL' `
        ((Select-GodotProblems -Text $r4Combined) -join "`n")
}
else {
    Assert-Check $false '运行服务端 R4 验收（未定位到 Godot，已跳过）'
}

# ------------------------------ 14. 客户端 R4 验收（道统树 → 研究 → 队列 → 加速 → 收徒 → 取消）
Write-Host "`n[14/26] 客户端 R4 验收（res://tests/R4ClientTest.tscn）" -ForegroundColor Cyan
if ($godotExe) {
    $r4ClientResult = Invoke-GodotCapture -Executable $godotExe `
        -Arguments @('--headless', '--path', $clientPath, 'res://tests/R4ClientTest.tscn') `
        -TimeoutMs 120000
    $r4ClientCombined = ($r4ClientResult.StdOut + "`n" + $r4ClientResult.StdErr)
    Assert-Check ($r4ClientCombined -match 'R4_CLIENT_RESULT=OK') '客户端 R4 无头验收全绿（R4_CLIENT_RESULT=OK）' `
        ((Select-GodotProblems -Text $r4ClientCombined) -join "`n")
    Assert-Check ($r4ClientResult.ExitCode -eq 0) '客户端 R4 无头验收退出码为 0' "退出码：$($r4ClientResult.ExitCode)"
    Assert-Check ($r4ClientCombined -notmatch 'R4_CLIENT_FAIL') '客户端 R4 无头验收未出现 R4_CLIENT_FAIL'
    Assert-Check ($r4ClientCombined -match '未打开时道统树面板不显示') 'R4 道统树面板未打开时门控'

    $r4Integration = Invoke-GodotCapture -Executable $godotExe `
        -Arguments @('--headless', '--path', $clientPath, 'res://tests/R4ClientTest.tscn', '--', '--integration') `
        -TimeoutMs 420000
    $r4IntegrationCombined = ($r4Integration.StdOut + "`n" + $r4Integration.StdErr)
    # 与 R1/R2/R3 同理：必须匹配 R4_CLIENT_PASS: 前缀，否则 FAIL 也会被判 PASS。
    Assert-Check ($r4IntegrationCombined -match 'R4_CLIENT_PASS: 端到端：daoOptions 下发 21 条道法') `
        '端到端 R4：道统树下发 21 条道法' `
        ((Select-GodotProblems -Text $r4IntegrationCombined) -join "`n")
    Assert-Check ($r4IntegrationCombined -match 'R4_CLIENT_PASS: 端到端：每条道法 state') '端到端 R4：每条道法下发三态与 blocker'
    Assert-Check ($r4IntegrationCombined -match 'R4_CLIENT_PASS: 端到端：researchDao 入队即扣 daoPointCost=20 道点') '端到端 R4：researchDao 入队即扣道点'
    Assert-Check ($r4IntegrationCombined -match 'R4_CLIENT_PASS: 端到端：researchQueue\[\] 出现 1 条研究项目') '端到端 R4：queryProjectQueue 显示研究项目'
    Assert-Check ($r4IntegrationCombined -match 'R4_CLIENT_PASS: 端到端：研究项目\*\*不\*\*混入 projects\[\]（两池分离）') '端到端 R4：projects[] 与 researchQueue[] 两池不混'
    Assert-Check ($r4IntegrationCombined -match 'R4_CLIENT_PASS: 端到端：accelerateProject 扣 accelerateStonePerTurn') '端到端 R4：accelerateProject 扣灵石并推进工期'
    Assert-Check ($r4IntegrationCombined -match 'R4_CLIENT_PASS: 端到端：cancelProject 后 projects\[\] 清空') '端到端 R4：cancelProject 清空项目'
    Assert-Check ($r4IntegrationCombined -match 'R4_CLIENT_PASS: 端到端：开面板/研究/加速/收徒/取消全程相机 transform/size 不变') '端到端 R4：全程相机不重置'
    Assert-Check ($r4IntegrationCombined -match 'R4_CLIENT_RESULT=OK') '端到端 R4 集成验收全绿（R4_CLIENT_RESULT=OK）' `
        ((Select-GodotProblems -Text $r4IntegrationCombined) -join "`n")

    Start-Sleep -Milliseconds 800
    [void](Stop-ProjectGodotProcesses -ProjectPaths @($serverPath, $clientPath))
    Start-Sleep -Milliseconds 500
}
else {
    Assert-Check $false '运行客户端 R4 验收（未定位到 Godot，已跳过）'
}

# ------------------------------ 15. 服务端 R5 验收（十兵种 + 战斗结算 + ZOC + 传送 + 转职晋升）
Write-Host "`n[15/26] 服务端 R5 验收（res://tests/R5Test.tscn）" -ForegroundColor Cyan
if ($godotExe) {
    $r5Result = Invoke-GodotCapture -Executable $godotExe `
        -Arguments @('--headless', '--path', $serverPath, 'res://tests/R5Test.tscn') `
        -TimeoutMs 300000
    $r5Combined = ($r5Result.StdOut + "`n" + $r5Result.StdErr)
    Assert-Check ($r5Combined -match 'R5_PASS checks=\d+') '服务端 R5 验收打印 R5_PASS checks=N' $r5Combined.Trim()
    Assert-Check ($r5Result.ExitCode -eq 0) '服务端 R5 验收退出码为 0' "退出码：$($r5Result.ExitCode)"
    Assert-Check ($r5Combined -notmatch 'R5_FAIL') '服务端 R5 验收未出现 R5_FAIL' `
        ((Select-GodotProblems -Text $r5Combined) -join "`n")
}
else {
    Assert-Check $false '运行服务端 R5 验收（未定位到 Godot，已跳过）'
}

# ------------------------------ 16. 客户端 R5 验收（攻击预览 → 转职晋升 → 批量移动）
Write-Host "`n[16/26] 客户端 R5 验收（res://tests/R5ClientTest.tscn）" -ForegroundColor Cyan
if ($godotExe) {
    $r5ClientResult = Invoke-GodotCapture -Executable $godotExe `
        -Arguments @('--headless', '--path', $clientPath, 'res://tests/R5ClientTest.tscn') `
        -TimeoutMs 120000
    $r5ClientCombined = ($r5ClientResult.StdOut + "`n" + $r5ClientResult.StdErr)
    Assert-Check ($r5ClientCombined -match 'R5_CLIENT_RESULT=OK') '客户端 R5 无头验收全绿（R5_CLIENT_RESULT=OK）' `
        ((Select-GodotProblems -Text $r5ClientCombined) -join "`n")
    Assert-Check ($r5ClientResult.ExitCode -eq 0) '客户端 R5 无头验收退出码为 0' "退出码：$($r5ClientResult.ExitCode)"
    Assert-Check ($r5ClientCombined -notmatch 'R5_CLIENT_FAIL') '客户端 R5 无头验收未出现 R5_CLIENT_FAIL'
    Assert-Check ($r5ClientCombined -match '十兵种占位剪影两两不同') 'R5 十兵种占位剪影互不相同（正式模型缺失时可区分）'

    $r5Integration = Invoke-GodotCapture -Executable $godotExe `
        -Arguments @('--headless', '--path', $clientPath, 'res://tests/R5ClientTest.tscn', '--', '--integration') `
        -TimeoutMs 300000
    $r5IntegrationCombined = ($r5Integration.StdOut + "`n" + $r5Integration.StdErr)
    # 与 R1–R4 同理：必须匹配 R5_CLIENT_PASS: 前缀，否则 FAIL 也会被判 PASS。
    Assert-Check ($r5IntegrationCombined -match 'R5_CLIENT_PASS: 端到端：点选后主选中为该弟子') `
        '端到端 R5：点选弟子走完 可达集→可攻击集→弟子详情 三段串行链' `
        ((Select-GodotProblems -Text $r5IntegrationCombined) -join "`n")
    Assert-Check ($r5IntegrationCombined -match 'R5_CLIENT_PASS: 端到端：转职候选覆盖 10 个兵种') '端到端 R5：queryDiscipleDetail 下发十兵种转职候选'
    Assert-Check ($r5IntegrationCombined -match 'R5_CLIENT_PASS: 端到端：不可用的转职按钮置灰') '端到端 R5：不满足条件的兵种按钮置灰'
    Assert-Check ($r5IntegrationCombined -match 'R5_CLIENT_PASS: 端到端：blockedReason 指明无敌方目标') '端到端 R5：攻击预览下发 blockedReason'
    Assert-Check ($r5IntegrationCombined -match 'R5_CLIENT_PASS: 端到端：attack 业务失败不刷新 view') '端到端 R5：attack 业务失败只提示不刷新 view'
    Assert-Check ($r5IntegrationCombined -match 'R5_CLIENT_PASS: 端到端：非法兵种枚举回 BAD_PARAMS') '端到端 R5：reclass 非法枚举走协议失败'
    Assert-Check ($r5IntegrationCombined -match 'R5_CLIENT_PASS: 端到端：未开启时 capacity=0') '端到端 R5：传送未开启时 capacity/remaining 自洽为 0'
    Assert-Check ($r5IntegrationCombined -match 'R5_CLIENT_PASS: 端到端：批量移动后第 2 人同格抵达') '端到端 R5：Shift 多选后 batchMove 两人同格'
    Assert-Check ($r5IntegrationCombined -match 'R5_CLIENT_PASS: 端到端：清移动层不影响攻击层') '端到端 R5：移动/攻击两层高亮互相独立'
    Assert-Check ($r5IntegrationCombined -match 'R5_CLIENT_PASS: 端到端：点选/预览/攻击/转职/晋升/传送/驻守/撤退/批量移动全程相机') '端到端 R5：全程相机不重置'
    Assert-Check ($r5IntegrationCombined -match 'R5_CLIENT_RESULT=OK') '端到端 R5 集成验收全绿（R5_CLIENT_RESULT=OK）' `
        ((Select-GodotProblems -Text $r5IntegrationCombined) -join "`n")

    Start-Sleep -Milliseconds 800
    [void](Stop-ProjectGodotProcesses -ProjectPaths @($serverPath, $clientPath))
    Start-Sleep -Milliseconds 500
}
else {
    Assert-Check $false '运行客户端 R5 验收（未定位到 Godot，已跳过）'
}

# ------------------------------ 17. 服务端 R6 验收（探索 / 政令 / 自动化）
Write-Host "`n[17/26] 服务端 R6 验收（res://tests/R6Test.tscn）" -ForegroundColor Cyan
if ($godotExe) {
    $r6Result = Invoke-GodotCapture -Executable $godotExe `
        -Arguments @('--headless', '--path', $serverPath, 'res://tests/R6Test.tscn') `
        -TimeoutMs 300000
    $r6Combined = ($r6Result.StdOut + "`n" + $r6Result.StdErr)
    Assert-Check ($r6Combined -match 'R6_PASS checks=\d+') '服务端 R6 验收打印 R6_PASS checks=N' `
        ((Select-GodotProblems -Text $r6Combined) -join "`n")
    Assert-Check ($r6Result.ExitCode -eq 0) '服务端 R6 验收退出码为 0' "退出码：$($r6Result.ExitCode)"
    Assert-Check ($r6Combined -notmatch 'R6_FAIL') '服务端 R6 验收未出现 R6_FAIL' `
        ((Select-GodotProblems -Text $r6Combined) -join "`n")
    # R6 的硬口径是「R6 那 16 条都已登记、总数不少于 56」；后续里程碑继续加命令不应打破它，
    # 故这里卡下限而非等值（R7 后总数 70）。
    Assert-Check ($r6Combined -match 'R6_IMPLEMENTED=(\d+)' -and [int]$Matches[1] -ge 56) `
        '服务端已实现命令不少于 56 条（R6 交付 40 + 16）' `
        ((Select-GodotProblems -Text $r6Combined) -join "`n")
}
else {
    Assert-Check $false '运行服务端 R6 验收（未定位到 Godot，已跳过）'
}

# ------------------------------ 18. 客户端 R6 验收（探索面板 → 政令面板 → 自动化面板）
Write-Host "`n[18/26] 客户端 R6 验收（res://tests/R6ClientTest.tscn）" -ForegroundColor Cyan
if ($godotExe) {
    $r6ClientResult = Invoke-GodotCapture -Executable $godotExe `
        -Arguments @('--headless', '--path', $clientPath, 'res://tests/R6ClientTest.tscn') `
        -TimeoutMs 120000
    $r6ClientCombined = ($r6ClientResult.StdOut + "`n" + $r6ClientResult.StdErr)
    Assert-Check ($r6ClientCombined -match 'R6_CLIENT_RESULT=OK') '客户端 R6 无头验收全绿（R6_CLIENT_RESULT=OK）' `
        ((Select-GodotProblems -Text $r6ClientCombined) -join "`n")
    Assert-Check ($r6ClientResult.ExitCode -eq 0) '客户端 R6 无头验收退出码为 0' "退出码：$($r6ClientResult.ExitCode)"
    Assert-Check ($r6ClientCombined -notmatch 'R6_CLIENT_FAIL') '客户端 R6 无头验收未出现 R6_CLIENT_FAIL'

    $r6Integration = Invoke-GodotCapture -Executable $godotExe `
        -Arguments @('--headless', '--path', $clientPath, 'res://tests/R6ClientTest.tscn', '--', '--integration') `
        -TimeoutMs 300000
    $r6IntegrationCombined = ($r6Integration.StdOut + "`n" + $r6Integration.StdErr)
    # 与 R1–R5 同理：必须匹配 R6_CLIENT_PASS: 前缀，否则 FAIL 也会被判 PASS。
    Assert-Check ($r6IntegrationCombined -match 'R6_CLIENT_PASS: 端到端：点节点格打开探索面板') `
        '端到端 R6：点节点格打开探索面板（节点点击优先于弟子点击）' `
        ((Select-GodotProblems -Text $r6IntegrationCombined) -join "`n")
    Assert-Check ($r6IntegrationCombined -match 'R6_CLIENT_PASS: 端到端：三面板互斥（政令未显示）') `
        '端到端 R6：探索/政令/自动化三面板互斥显示'
    Assert-Check ($r6IntegrationCombined -match 'R6_CLIENT_PASS: 端到端：探索面板显示奖励预览') `
        '端到端 R6：探索面板展示服务端下发的冷却与奖励预览'
    Assert-Check ($r6IntegrationCombined -match 'R6_CLIENT_PASS: 端到端：已颁卡按钮变为可废除态') `
        '端到端 R6：颁行后卡牌按钮翻转为可废除态'
    Assert-Check ($r6IntegrationCombined -match 'R6_CLIENT_PASS: 端到端：关闭自动修缮后按钮变') `
        '端到端 R6：自动化开关写回后按钮态同步'
    Assert-Check ($r6IntegrationCombined -match 'R6_CLIENT_PASS: 端到端：本地设置在前端生效') `
        '端到端 R6：setSetting 仅确认、值留在前端'
    Assert-Check ($r6IntegrationCombined -match 'R6_CLIENT_PASS: 端到端：全程相机 transform 不变') `
        '端到端 R6：全程相机 transform/size 不重置'
    Assert-Check ($r6IntegrationCombined -match 'R6_CLIENT_RESULT=OK') '端到端 R6 集成验收全绿（R6_CLIENT_RESULT=OK）' `
        ((Select-GodotProblems -Text $r6IntegrationCombined) -join "`n")

    Start-Sleep -Milliseconds 800
    [void](Stop-ProjectGodotProcesses -ProjectPaths @($serverPath, $clientPath))
    Start-Sleep -Milliseconds 500
}
else {
    Assert-Check $false '运行客户端 R6 验收（未定位到 Godot，已跳过）'
}

# ------------------------------ 19. 服务端 R7 验收（任命 / 渡劫 / AI / 胜负 / 存档）
Write-Host "`n[19/26] 服务端 R7 验收（res://tests/R7Test.tscn）" -ForegroundColor Cyan
if ($godotExe) {
    $r7Result = Invoke-GodotCapture -Executable $godotExe `
        -Arguments @('--headless', '--path', $serverPath, 'res://tests/R7Test.tscn') `
        -TimeoutMs 600000
    $r7Combined = ($r7Result.StdOut + "`n" + $r7Result.StdErr)
    Assert-Check ($r7Combined -match 'R7_PASS checks=\d+') '服务端 R7 验收打印 R7_PASS checks=N' `
        ((Select-GodotProblems -Text $r7Combined) -join "`n")
    Assert-Check ($r7Result.ExitCode -eq 0) '服务端 R7 验收退出码为 0' "退出码：$($r7Result.ExitCode)"
    Assert-Check ($r7Combined -notmatch 'R7_FAIL') '服务端 R7 验收未出现 R7_FAIL' `
        ((Select-GodotProblems -Text $r7Combined) -join "`n")
    # R7 的硬口径是「hello 下发 70 条 = 69 + ping 全覆盖」（任务 4 第 2 条）。
    Assert-Check ($r7Combined -match 'R7_IMPLEMENTED=(\d+)' -and [int]$Matches[1] -eq 70) `
        '服务端已实现命令 70 条（69 + ping 全覆盖）' `
        ((Select-GodotProblems -Text $r7Combined) -join "`n")
}
else {
    Assert-Check $false '运行服务端 R7 验收（未定位到 Godot，已跳过）'
}

# ------------------------------ 20. 客户端 R7 验收（胜负面板 / 存读档 / awaitInput / 结局屏）
Write-Host "`n[20/26] 客户端 R7 验收（res://tests/R7ClientTest.tscn）" -ForegroundColor Cyan
if ($godotExe) {
    $r7ClientResult = Invoke-GodotCapture -Executable $godotExe `
        -Arguments @('--headless', '--path', $clientPath, 'res://tests/R7ClientTest.tscn') `
        -TimeoutMs 120000
    $r7ClientCombined = ($r7ClientResult.StdOut + "`n" + $r7ClientResult.StdErr)
    Assert-Check ($r7ClientCombined -match 'R7_CLIENT_RESULT=OK') '客户端 R7 无头验收全绿（R7_CLIENT_RESULT=OK）' `
        ((Select-GodotProblems -Text $r7ClientCombined) -join "`n")
    Assert-Check ($r7ClientResult.ExitCode -eq 0) '客户端 R7 无头验收退出码为 0' "退出码：$($r7ClientResult.ExitCode)"
    Assert-Check ($r7ClientCombined -notmatch 'R7_CLIENT_FAIL') '客户端 R7 无头验收未出现 R7_CLIENT_FAIL'

    $r7Integration = Invoke-GodotCapture -Executable $godotExe `
        -Arguments @('--headless', '--path', $clientPath, 'res://tests/R7ClientTest.tscn', '--', '--integration') `
        -TimeoutMs 600000
    $r7IntegrationCombined = ($r7Integration.StdOut + "`n" + $r7Integration.StdErr)
    # 与 R1–R6 同理：必须匹配 R7_CLIENT_PASS: 前缀，否则 FAIL 也会被判 PASS。
    Assert-Check ($r7IntegrationCombined -match 'R7_CLIENT_PASS: 端到端：打开胜利进度面板') `
        '端到端 R7：打开胜利进度面板并渲染三路线 goals' `
        ((Select-GodotProblems -Text $r7IntegrationCombined) -join "`n")
    Assert-Check ($r7IntegrationCombined -match 'R7_CLIENT_PASS: 端到端：未达成路线的择定按钮置灰') `
        '端到端 R7：未达成路线的择定按钮置灰'
    Assert-Check ($r7IntegrationCombined -match 'R7_CLIENT_PASS: 端到端：saveGame 回') `
        '端到端 R7：saveGame 回 {slot,saved} 被判为成功（无 success 布尔）'
    Assert-Check ($r7IntegrationCombined -match 'R7_CLIENT_PASS: 端到端：读档后回合与存档时一致') `
        '端到端 R7：存读档往返后回合与 view 一致'
    Assert-Check ($r7IntegrationCombined -match 'R7_CLIENT_PASS: 端到端：awaitInput 触发待抉择弹窗') `
        '端到端 R7：awaitInput 主动消息触发待抉择弹窗'
    Assert-Check ($r7IntegrationCombined -match 'R7_CLIENT_PASS: 端到端：待决未清空时弹窗保留') `
        '端到端 R7：resolveChoice 越界时待决保留且弹窗不消失'
    Assert-Check ($r7IntegrationCombined -match 'R7_CLIENT_PASS: 端到端：结局屏显示 winType') `
        '端到端 R7：结局屏展示 winType / winnerSectId'
    Assert-Check ($r7IntegrationCombined -match 'R7_CLIENT_PASS: 端到端：事件栏展示回包 events') `
        '端到端 R7：事件栏展示回包 events（AI 行动占位）'
    Assert-Check ($r7IntegrationCombined -match 'R7_CLIENT_PASS: 端到端：全程相机 transform 不变') `
        '端到端 R7：全程相机 transform/size 不重置'
    Assert-Check ($r7IntegrationCombined -match 'R7_CLIENT_RESULT=OK') '端到端 R7 集成验收全绿（R7_CLIENT_RESULT=OK）' `
        ((Select-GodotProblems -Text $r7IntegrationCombined) -join "`n")

    Start-Sleep -Milliseconds 800
    [void](Stop-ProjectGodotProcesses -ProjectPaths @($serverPath, $clientPath))
    Start-Sleep -Milliseconds 500
}
else {
    Assert-Check $false '运行客户端 R7 验收（未定位到 Godot，已跳过）'
}

# ------------------------------------------------------ 21. 客户端 R8 表现与 UI 打磨
Write-Host "`n[21/26] 客户端 R8 验收（res://tests/R8ClientTest.tscn）" -ForegroundColor Cyan
if ($godotExe) {
    $r8ClientResult = Invoke-GodotCapture -Executable $godotExe `
        -Arguments @('--headless', '--path', $clientPath, 'res://tests/R8ClientTest.tscn') `
        -TimeoutMs 180000
    $r8ClientCombined = ($r8ClientResult.StdOut + "`n" + $r8ClientResult.StdErr)
    # 69 命令 + ping 全入口（R8 核心硬口径）
    Assert-Check ($r8ClientCombined -match 'R8_CLIENT_PASS: commands\.gd 常量共 70 条') `
        '客户端 R8：commands.gd 常量共 70 条（69 命令 + ping）' `
        ((Select-GodotProblems -Text $r8ClientCombined) -join "`n")
    Assert-Check ($r8ClientCombined -match 'R8_CLIENT_PASS: 69 命令 \+ ping 全部有 UI 入口') `
        '客户端 R8：69 命令 + ping 全部有 UI 入口（缺失列表为空）'
    Assert-Check ($r8ClientCombined -match 'R8_CLIENT_PASS: 四类入口之和 = 70') `
        '客户端 R8：button/panel/gesture/auto 四类入口之和 = 70'
    # 不可用置灰 + blocker 文案
    Assert-Check ($r8ClientCombined -match 'R8_CLIENT_PASS: 未选中弟子时「开洞府」置灰') `
        '客户端 R8：未选中弟子时「开洞府」置灰'
    Assert-Check ($r8ClientCombined -match 'R8_CLIENT_PASS: 「开洞府」带 blocker 悬浮说明') `
        '客户端 R8：置灰按钮带 blocker 悬浮说明'
    # 纯显示层开关（裁决四：不改玩法与数值）
    Assert-Check ($r8ClientCombined -match 'R8_CLIENT_PASS: 开关网格后状态变为开') `
        '客户端 R8：网格开关可开'
    Assert-Check ($r8ClientCombined -match 'R8_CLIENT_PASS: 网格开关同步到本地偏好') `
        '客户端 R8：网格开关写入本地偏好（不经服务端 view）'
    Assert-Check ($r8ClientCombined -match 'R8_CLIENT_PASS: 宗门色边框默认开启') `
        '客户端 R8：宗门色边框默认开启'
    # 引导 / Toast / 设置
    Assert-Check ($r8ClientCombined -match 'R8_CLIENT_PASS: 新手引导共 6 步') `
        '客户端 R8：新手引导 6 步且可翻页'
    Assert-Check ($r8ClientCombined -match 'R8_CLIENT_PASS: Toast 显示业务/事件文案') `
        '客户端 R8：Toast 显示业务/事件文案'
    Assert-Check ($r8ClientCombined -match 'R8_CLIENT_PASS: 设置面板有状态文案') `
        '客户端 R8：设置项本地生效（服务端仅确认）'
    # 相机铁律（R8 自动验收第 3 条）
    Assert-Check ($r8ClientCombined -match 'R8_CLIENT_PASS: 相机铁律：全序列后 size 不变') `
        '客户端 R8：全序列后相机 size 不变'
    Assert-Check ($r8ClientCombined -match 'R8_CLIENT_PASS: 相机铁律：全序列后 rotation 不变') `
        '客户端 R8：全序列后相机 rotation 不变（锁定 45°，无旋转）'
    Assert-Check ($r8ClientCombined -match 'R8_CLIENT_PASS: 相机铁律：全序列后 transform 的基不变') `
        '客户端 R8：全序列后相机基不变'
    # 资源缺失只 WARN 不崩（裁决二）
    Assert-Check ($r8ClientCombined -match 'R8_CLIENT_PASS: 最小包 75 个 ID 均未触发 WARN') `
        '客户端 R8：最小水墨资源包 75 个 ID 全部命中、零 WARN（仅 fonts 2 项待美术）'
    Assert-Check ($r8ClientCombined -match 'R8_CLIENT_PASS: 未覆盖 ID 仍回退占位并 WARN 一次') `
        '客户端 R8：未覆盖资源 ID 仍回退占位并 WARN 一次（不崩）'
    Assert-Check ($r8ClientCombined -match 'R8_CLIENT_RESULT=OK') '客户端 R8 无头验收全绿（R8_CLIENT_RESULT=OK）' `
        ((Select-GodotProblems -Text $r8ClientCombined) -join "`n")
    Assert-Check ($r8ClientResult.ExitCode -eq 0) '客户端 R8 无头验收退出码为 0' "退出码：$($r8ClientResult.ExitCode)"
    Assert-Check ($r8ClientCombined -notmatch 'R8_CLIENT_FAIL') '客户端 R8 无头验收未出现 R8_CLIENT_FAIL'

    $r8Integration = Invoke-GodotCapture -Executable $godotExe `
        -Arguments @('--headless', '--path', $clientPath, 'res://tests/R8ClientTest.tscn', '--', '--integration') `
        -TimeoutMs 600000
    $r8IntegrationCombined = ($r8Integration.StdOut + "`n" + $r8Integration.StdErr)
    # 与 R1–R7 同理：必须匹配 R8_CLIENT_PASS: 前缀，否则 FAIL 也会被判 PASS。
    Assert-Check ($r8IntegrationCombined -match 'R8_CLIENT_PASS: 端到端：hello 声明支持全部 70 条') `
        '端到端 R8：hello 声明支持全部 70 条（R8 不新增命令）' `
        ((Select-GodotProblems -Text $r8IntegrationCombined) -join "`n")
    Assert-Check ($r8IntegrationCombined -match 'R8_CLIENT_PASS: 端到端：网格线已生成') `
        '端到端 R8：装饰层按真 view 生成网格线'
    Assert-Check ($r8IntegrationCombined -match 'R8_CLIENT_PASS: 端到端：宗门色边框已生成') `
        '端到端 R8：按 tile.ownerSectId + sect.color 生成宗门色边框'
    Assert-Check ($r8IntegrationCombined -match 'R8_CLIENT_PASS: 端到端：小地图缩略点 = 地块数') `
        '端到端 R8：小地图缩略点数量 = 地块数'
    Assert-Check ($r8IntegrationCombined -match 'R8_CLIENT_PASS: 端到端：小地图跳转后缩放不变') `
        '端到端 R8：小地图跳转不改缩放'
    Assert-Check ($r8IntegrationCombined -match 'R8_CLIENT_PASS: 端到端：小地图跳转后角度不变') `
        '端到端 R8：小地图跳转不改角度（只平移）'
    Assert-Check ($r8IntegrationCombined -match 'R8_CLIENT_PASS: 端到端：小地图跳转确实平移了相机') `
        '端到端 R8：小地图跳转确实平移了相机'
    Assert-Check ($r8IntegrationCombined -match 'R8_CLIENT_PASS: 端到端：全序列后相机 size 不变') `
        '端到端 R8：泼墨转场/面板/存读档/结束回合/getState 全序列后 size 不变'
    Assert-Check ($r8IntegrationCombined -match 'R8_CLIENT_PASS: 端到端：全序列后相机 rotation 不变') `
        '端到端 R8：全序列后 rotation 不变'
    Assert-Check ($r8IntegrationCombined -match 'R8_CLIENT_PASS: 端到端：全序列后相机基不变') `
        '端到端 R8：全序列后相机基不变（无旋转）'
    Assert-Check ($r8IntegrationCombined -match 'R8_CLIENT_PASS: 端到端：setSetting 不进入 view') `
        '端到端 R8：setSetting 不进入 view（客户端本地偏好）'
    Assert-Check ($r8IntegrationCombined -match 'R8_CLIENT_PASS: 端到端：13 项资源均显示数值') `
        '端到端 R8：顶部资源栏 13 项均显示数值'
    Assert-Check ($r8IntegrationCombined -match 'R8_CLIENT_RESULT=OK') '端到端 R8 集成验收全绿（R8_CLIENT_RESULT=OK）' `
        ((Select-GodotProblems -Text $r8IntegrationCombined) -join "`n")

    Start-Sleep -Milliseconds 800
    [void](Stop-ProjectGodotProcesses -ProjectPaths @($serverPath, $clientPath))
    Start-Sleep -Milliseconds 500
}
else {
    Assert-Check $false '运行客户端 R8 验收（未定位到 Godot，已跳过）'
}

# ------------------------------------------------------ 22. Windows 导出冒烟（R9 W3）
Write-Host "`n[22/26] Windows 导出冒烟（预设 + 产物 + 导出态服务端）" -ForegroundColor Cyan

# 22.0 导出态路径解析（纯客户端单元，不依赖导出产物）
$r9ClientResult = Invoke-GodotCapture -Executable $godotExe `
    -Arguments @('--headless', '--path', $clientPath, 'res://tests/R9ClientTest.tscn') `
    -TimeoutMs 300000
$r9ClientCombined = ($r9ClientResult.StdOut + "`n" + $r9ClientResult.StdErr)
Assert-Check ($r9ClientCombined -match 'R9_CLIENT_RESULT=OK') '客户端 R9 无头验收全绿（R9_CLIENT_RESULT=OK）' `
    ((Select-GodotProblems -Text $r9ClientCombined) -join "`n")
Assert-Check ($r9ClientResult.ExitCode -eq 0) '客户端 R9 无头验收退出码为 0' "退出码：$($r9ClientResult.ExitCode)"
Assert-Check ($r9ClientCombined -notmatch 'R9_CLIENT_FAIL') '客户端 R9 无头验收未出现 R9_CLIENT_FAIL'
Assert-Check ($r9ClientCombined -match 'R9_CLIENT_PASS: 导出态 repo_root\(\) 不是 res:// 的上一级') `
    '客户端 R9：导出态 repo_root() 不落在 res:// 的上一级（钉住老写法的坑）'
Assert-Check ($r9ClientCombined -match 'R9_CLIENT_PASS: 导出态服务端可执行文件名与导出预设一致') `
    '客户端 R9：Launcher.SERVER_EXE_NAME 与 server/export_presets.cfg 产物名一致'

# 22.05 换皮端到端：真 view 下切包，view 逐字不变、相机不变、贴图实例确实更换
$r9Integration = Invoke-GodotCapture -Executable $godotExe `
    -Arguments @('--headless', '--path', $clientPath, 'res://tests/R9ClientTest.tscn', '--', '--integration') `
    -TimeoutMs 600000
$r9IntegrationCombined = ($r9Integration.StdOut + "`n" + $r9Integration.StdErr)
Assert-Check ($r9IntegrationCombined -match 'R9_CLIENT_PASS: 端到端：换皮后 view 逐字不变') `
    '端到端 R9：换皮后 view 逐字不变（纯表现，不动数据）' `
    ((Select-GodotProblems -Text $r9IntegrationCombined) -join "`n")
Assert-Check ($r9IntegrationCombined -match 'R9_CLIENT_PASS: 端到端：换皮不触发 view 刷新') `
    '端到端 R9：换皮不触发 view 刷新（revision 不变）'
Assert-Check ($r9IntegrationCombined -match 'R9_CLIENT_PASS: 端到端：换皮后相机 transform 不变') `
    '端到端 R9：换皮后相机 transform 不变'
Assert-Check ($r9IntegrationCombined -match 'R9_CLIENT_PASS: 端到端：换皮后相机 size 不变') `
    '端到端 R9：换皮后相机 size 不变'
Assert-Check ($r9IntegrationCombined -match 'R9_CLIENT_PASS: 端到端：换皮后地形贴图实例已更换') `
    '端到端 R9：换皮后地形贴图实例已更换（证明真的重载）'
Assert-Check ($r9IntegrationCombined -match 'R9_CLIENT_PASS: 端到端：切回默认后相机 transform 仍不变') `
    '端到端 R9：切回默认包后相机 transform 仍不变'
Assert-Check ($r9IntegrationCombined -match 'R9_CLIENT_RESULT=OK') '端到端 R9 集成验收全绿（R9_CLIENT_RESULT=OK）' `
    ((Select-GodotProblems -Text $r9IntegrationCombined) -join "`n")

# 22.06 第二套皮肤包资源验收：与默认包同口径 75/75
$inkVerify = Invoke-GodotCapture -Executable $godotExe `
    -Arguments @('--headless', '--path', $clientPath, 'res://tools/AssetVerify.tscn', '--', '--pack=zhu_xia') `
    -TimeoutMs 300000
$inkVerifyCombined = ($inkVerify.StdOut + "`n" + $inkVerify.StdErr)
Assert-Check ($inkVerifyCombined -match 'ASSETVERIFY_OK covered=75 warned=0 pack=zhu_xia') `
    '第二套皮肤包 zhu_xia 资源验收全绿（covered=75 warned=0）' `
    (($inkVerifyCombined -split "`r?`n" | Where-Object { $_ -match 'AssetVerify|ASSETVERIFY' }) -join "`n")
Assert-Check ($inkVerify.ExitCode -eq 0) 'zhu_xia 资源验收退出码为 0' "退出码：$($inkVerify.ExitCode)"

# 22.1 预设文件
$clientPreset = Join-Path $clientPath 'export_presets.cfg'
$serverPreset = Join-Path $serverPath 'export_presets.cfg'
Assert-Check (Test-Path -PathType Leaf $clientPreset) '客户端导出预设存在（client/export_presets.cfg）' "缺失：$clientPreset"
Assert-Check (Test-Path -PathType Leaf $serverPreset) '服务端导出预设存在（server/export_presets.cfg）' "缺失：$serverPreset"

$clientPresetText = ''
$serverPresetText = ''
if (Test-Path -PathType Leaf $clientPreset) { $clientPresetText = Get-Content -Path $clientPreset -Raw }
if (Test-Path -PathType Leaf $serverPreset) { $serverPresetText = Get-Content -Path $serverPreset -Raw }

Assert-Check ($clientPresetText -match 'name="Windows Desktop"') '客户端预设声明 Windows Desktop'
Assert-Check ($serverPresetText -match 'name="Windows Desktop"') '服务端预设声明 Windows Desktop'
Assert-Check ($clientPresetText -match 'Xiuxian\.exe') '客户端产物名为 Xiuxian.exe'
# 与 client/scripts/net/Launcher.gd 的 SERVER_EXE_NAME 必须一致，否则导出态拉不起服务端。
Assert-Check ($serverPresetText -match 'XiuxianServer\.exe') '服务端产物名为 XiuxianServer.exe（与 Launcher.SERVER_EXE_NAME 一致）'

$exportScript = Join-Path $PSScriptRoot 'export.ps1'
$exportedRoot = Join-Path $root 'dist\xiuxian'
$exportedServerExe = Join-Path $exportedRoot 'XiuxianServer.exe'
$exportedClientExe = Join-Path $exportedRoot 'Xiuxian.exe'
$exportedData = Join-Path $exportedRoot 'data\gameConfig.json'

$templateDir = Join-Path $env:APPDATA 'Godot\export_templates\4.4.1.stable'
$hasExportTemplate = Test-Path -PathType Leaf (Join-Path $templateDir 'windows_release_x86_64.exe')

if (-not $hasExportTemplate) {
    Write-Host '  [SKIP] 未安装 Godot 4.4.1 导出模板，跳过实际导出（预设与产物名断言已通过）' -ForegroundColor Yellow
}
elseif ($SkipExport) {
    Write-Host '  [SKIP] 已指定 -SkipExport，跳过实际导出' -ForegroundColor Yellow
}
else {
    Assert-Check (Test-Path -PathType Leaf $exportScript) '导出脚本存在（tools/export.ps1）' "缺失：$exportScript"

    # export.ps1 末尾有 exit，必须放子进程执行，否则会把自检一起带走。
    $exportInfo = New-Object System.Diagnostics.ProcessStartInfo
    $exportInfo.FileName = 'powershell.exe'
    $exportInfo.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$exportScript`""
    $exportInfo.UseShellExecute = $false
    $exportInfo.CreateNoWindow = $true
    $exportInfo.RedirectStandardOutput = $true
    $exportInfo.RedirectStandardError = $true
    # 不设 StandardOutputEncoding：子进程是 powershell.exe，按控制台编码（CP936）写管道。
    $exportProcess = [System.Diagnostics.Process]::Start($exportInfo)
    $exportOutTask = $exportProcess.StandardOutput.ReadToEndAsync()
    $exportErrTask = $exportProcess.StandardError.ReadToEndAsync()
    if (-not $exportProcess.WaitForExit(900000)) {
        try { $exportProcess.Kill() } catch { }
        [void]$exportProcess.WaitForExit(5000)
    }
    $exportOut = ''
    $exportErr = ''
    if ($exportOutTask.Wait(15000)) { try { $exportOut = $exportOutTask.Result } catch { } }
    if ($exportErrTask.Wait(15000)) { try { $exportErr = $exportErrTask.Result } catch { } }
    $exportCombined = ($exportOut + "`n" + $exportErr)

    Assert-Check ($exportProcess.ExitCode -eq 0) 'tools/export.ps1 退出码为 0' `
        (($exportCombined -split "`r?`n" | Where-Object { $_ -match 'FAIL|错误|失败|error|Error' } | Select-Object -First 20) -join "`n")
    Assert-Check ($exportCombined -match 'EXPORT_RESULT=OK') '导出脚本打印 EXPORT_RESULT=OK' `
        (($exportCombined -split "`r?`n" | Select-Object -Last 15) -join "`n")

    Assert-Check (Test-Path -PathType Leaf $exportedClientExe) '产物含客户端可执行文件 Xiuxian.exe'
    Assert-Check (Test-Path -PathType Leaf $exportedServerExe) '产物含服务端可执行文件 XiuxianServer.exe'
    Assert-Check (Test-Path -PathType Leaf $exportedData) '产物含 data\gameConfig.json'
    Assert-Check (Test-Path -PathType Leaf (Join-Path $exportedRoot 'assets\manifest.json')) '产物含 assets\manifest.json'
    $exportedArtCount = 0
    $exportedArtDir = Join-Path $exportedRoot 'assets\art\default'
    if (Test-Path $exportedArtDir) {
        # 只数真实资源（.glb/.png）；分组目录里的 .gitkeep 不计入。
        $exportedArtCount = (Get-ChildItem -Path $exportedArtDir -Recurse -File |
            Where-Object { $_.Extension -in @('.glb', '.png') }).Count
    }
    Assert-Check ($exportedArtCount -ge 74) "产物含 assets\art\default 全部模型/贴图（≥74，实际 $exportedArtCount）"
    $exportedSkinDir = Join-Path $exportedRoot 'assets\art\zhu_xia'
    $exportedSkinCount = 0
    if (Test-Path $exportedSkinDir) {
        $exportedSkinCount = (Get-ChildItem -Path $exportedSkinDir -Recurse -File |
            Where-Object { $_.Extension -in @('.glb', '.png') }).Count
    }
    Assert-Check ($exportedSkinCount -ge 74) "产物含第二套皮肤包 assets\art\zhu_xia（≥74，实际 $exportedSkinCount）"

    # 导出态服务端：不带 --path、直接跑 exe，验证「导出后可独立运行」。
    $exportPort = 19641
    $exportedProcess = $null
    if (Test-Path -PathType Leaf $exportedServerExe) {
        $exportStartInfo = New-GodotStartInfo -Executable $exportedServerExe `
            -Arguments @('--headless', "--port=$exportPort", "--data=$exportedData") -CaptureOutput
        try {
            $exportedProcess = [System.Diagnostics.Process]::Start($exportStartInfo)
        }
        catch {
            $exportedProcess = $null
        }
    }
    Assert-Check ($null -ne $exportedProcess) '导出态服务端可被拉起（XiuxianServer.exe 启动成功）'

    $exportListening = $false
    if ($null -ne $exportedProcess) {
        for ($attempt = 0; $attempt -lt 120; $attempt++) {
            Start-Sleep -Milliseconds 500
            if ($exportedProcess.HasExited) { break }
            if (Test-TcpPort -Port $exportPort -TimeoutMs 300) { $exportListening = $true; break }
        }
    }
    Assert-Check $exportListening "导出态服务端监听 127.0.0.1:$exportPort（独立运行，无需 --path）"

    if ($null -ne $exportedProcess) {
        try {
            if (-not $exportedProcess.HasExited) { $exportedProcess.Kill() }
            [void]$exportedProcess.WaitForExit(5000)
        }
        catch { }
        try { $exportedProcess.Dispose() } catch { }
    }
}

# ------------------------------------------------------ 23. 仓库扫描与最终残留
Write-Host "`n[23/26] 仓库扫描：零 Java + 最终残留" -ForegroundColor Cyan
$javaFiles = @()
try {
    $javaFiles = Get-ChildItem -Path $root -Recurse -File -Filter '*.java' -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '[\\/]\.(git|godot)[\\/]' }
}
catch { }
Assert-Check ($javaFiles.Count -eq 0) '全仓库无 .java 文件（零 Java 约束）' `
    (($javaFiles | ForEach-Object { $_.FullName }) -join "`n")

$finalServer = Get-ProjectGodotProcesses -ProjectPath $serverPath
$finalClient = Get-ProjectGodotProcesses -ProjectPath $clientPath
Assert-Check ($finalServer.Count -eq 0) 'R1 验收结束后无残留 godot 服务端进程' `
    (($finalServer | ForEach-Object { "pid=$($_.ProcessId) $($_.CommandLine)" }) -join "`n")
Assert-Check ($finalClient.Count -eq 0) 'R1 验收结束后无残留 godot 客户端进程' `
    (($finalClient | ForEach-Object { "pid=$($_.ProcessId) $($_.CommandLine)" }) -join "`n")

# ---------------------------------------------- 24. 协议契约（PROTOCOL_2.0）
Write-Host "`n[24/26] 协议契约校验（docs/PROTOCOL_2.0.md）" -ForegroundColor Cyan
$protocolScript = Join-Path $PSScriptRoot 'check_protocol.ps1'
if (Test-Path -PathType Leaf $protocolScript) {
    # 必须放到子进程执行：脚本内的 exit 会终止当前会话，直接 & 调用会把自检一起带走。
    $protocolInfo = New-Object System.Diagnostics.ProcessStartInfo
    $protocolInfo.FileName = 'powershell.exe'
    $protocolInfo.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$protocolScript`""
    $protocolInfo.UseShellExecute = $false
    $protocolInfo.CreateNoWindow = $true
    $protocolInfo.RedirectStandardOutput = $true
    $protocolInfo.RedirectStandardError = $true
    # 注意：这里**不设** StandardOutputEncoding。子进程是 powershell.exe，它按控制台输出编码
    # （本机 CP936）写管道；若强行按 UTF-8 解码会把中文变成「?」。不设则 .NET 用与控制台一致的
    # 默认编码解码，中文可读。（Godot 子进程相反——它输出 UTF-8，故 New-GodotStartInfo 显式设 UTF-8。）
    $protocolProcess = [System.Diagnostics.Process]::Start($protocolInfo)
    $protocolOutTask = $protocolProcess.StandardOutput.ReadToEndAsync()
    $protocolErrTask = $protocolProcess.StandardError.ReadToEndAsync()
    if (-not $protocolProcess.WaitForExit(120000)) {
        try { $protocolProcess.Kill() } catch { }
        [void]$protocolProcess.WaitForExit(5000)
    }
    $protocolOut = ''
    $protocolErr = ''
    if ($protocolOutTask.Wait(15000)) { try { $protocolOut = $protocolOutTask.Result } catch { } }
    if ($protocolErrTask.Wait(15000)) { try { $protocolErr = $protocolErrTask.Result } catch { } }
    foreach ($line in (($protocolOut + "`n" + $protocolErr) -split "`r?`n")) {
        if ($line.Trim()) { Write-Host "  $($line.TrimEnd())" -ForegroundColor DarkGray }
    }
    Assert-Check ($protocolProcess.ExitCode -eq 0) `
        '协议契约校验全绿（tools/check_protocol.ps1）' "退出码：$($protocolProcess.ExitCode)"
    Assert-Check (($protocolOut + $protocolErr) -match 'CHECK_PROTOCOL_RESULT=OK') `
        '协议校验打印 CHECK_PROTOCOL_RESULT=OK' (($protocolOut + "`n" + $protocolErr).Trim())
}
else {
    Assert-Check $false '找到 tools/check_protocol.ps1' "缺失：$protocolScript"
}

# ------------------------------------------------------ 25. 平衡抽样器自检（R9 W4）
Write-Host "`n[25/26] 平衡抽样器自检（server/tools/BalanceSim.tscn --verify）" -ForegroundColor Cyan
$balanceResult = Invoke-GodotCapture -Executable $godotExe `
    -Arguments @('--headless', '--path', $serverPath, 'res://tools/BalanceSim.tscn', '--', '--verify') `
    -TimeoutMs 600000
$balanceCombined = ($balanceResult.StdOut + "`n" + $balanceResult.StdErr)
Assert-Check ($balanceCombined -match 'BALANCE_VERIFY=OK') `
    '平衡抽样器双跑同一局终局指纹一致（BALANCE_VERIFY=OK：抽样本身可复现）' `
    ((Select-GodotProblems -Text $balanceCombined) -join "`n")
Assert-Check ($balanceResult.ExitCode -eq 0) '平衡抽样器自检退出码为 0' "退出码：$($balanceResult.ExitCode)"
Assert-Check ($balanceCombined -match 'BALANCE_FINGERPRINT=turn=\d+') `
    '平衡抽样器打印终局指纹（BALANCE_FINGERPRINT=turn=…）'

# 报告交付物：只校验已提交报告的骨架，不在此重跑 72 局全量抽样（那是 --games=12 的手工动作）。
$balanceReport = Join-Path $root 'docs\BALANCE_REPORT.md'
Assert-Check (Test-Path -PathType Leaf $balanceReport) 'docs/BALANCE_REPORT.md 已生成' "缺失：$balanceReport"
if (Test-Path -PathType Leaf $balanceReport) {
    $reportText = Get-Content -Raw -Encoding UTF8 $balanceReport
    foreach ($section in @(
            '## 1. 方法与可复现性', '## 2. 全 AI 自由对局', '## 3. 玩家视角',
            '## 4. 进度曲线', '## 5. 观察与建议', '## 6. 附录')) {
        Assert-Check ($reportText.Contains($section)) "平衡报告含章节「$section」"
    }
    Assert-Check ($reportText -match '不改任何数值') '平衡报告声明不改数值（R8 裁决五）'
    Assert-Check ($reportText -match 'ZONG_MEN') '平衡报告含三流派实际抽样结果'
}

Write-Host ''
Write-Host "=== 自检结果：$($script:checkCount - $script:failCount) / $($script:checkCount) 项通过 ===" -ForegroundColor Cyan
if ($script:failCount -eq 0) {
    Write-Host 'CHECK_RESULT=OK' -ForegroundColor Green
    exit 0
}
else {
    Write-Host "CHECK_RESULT=FAIL（$($script:failCount) 项失败）" -ForegroundColor Red
    Write-Host "临时目录保留供排查：$workDir" -ForegroundColor Yellow
    exit 1
}
