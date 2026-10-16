#Requires -Version 5.1
<#
.SYNOPSIS
    里程碑自检：R0 工程骨架 + R1 地图开局 + R1.5 协议契约 + R2 回合/移动/视野
    + R3 经济结算/灵峰城市/建筑区域劳力改良道路（对应 docs/prompts/*.md「自动验收」）。

.DESCRIPTION
    依次执行：
      [0/14] 环境与交付物清单（R0 + R1 + R3）
      [1/14] shared/ 目录联接：幂等 + 内容贯通（临时文件在另一处可见）
      [2/14] 两个工程 --import 无解析错误并生成 class_name 缓存
      [3/14] 配置缺失时服务端非零退出（负向用例）
      [4/14] console 版 --headless 启动服务端并监听 127.0.0.1:9527
      [5/14] 运行 res://tests/SmokeTest.tscn，断言 SMOKE_PASS 且退出码 0（R0 协议回归）
      [6/14] 清理本脚本拉起的 Godot 进程，断言 tasklist 无残留
      [7/14] 服务端 R1 验收：res://tests/R1Test.tscn 打印 R1_PASS、退出码 0，
            且同种子双跑导出的权威地图 outputs/r1_authority_a|b.json 逐字一致（SHA256 相同）
      [8/14] 服务端 R2 验收：res://tests/R2Test.tscn 打印 R2_PASS、退出码 0
            （回合状态机 + 地形叠加移动成本 + BFS 可达 + 移动后视野刷新 + 确定性）
      [9/14] 客户端 R1 验收：res://tests/R1ClientTest.tscn 无头全绿；
            再加 --integration 端到端（真实拉起 headless 服务端 + newGame 300 格 view + getState 往返）
      [10/14] 客户端 R2 验收：res://tests/R2ClientTest.tscn 无头全绿；
            再加 --integration 端到端（点选弟子 → 移动高亮 → moveDisciple → 结束回合 → 相机不重置）
      [11/14] 服务端 R3 验收：res://tests/R3Test.tscn 打印 R3_PASS、退出码 0
            （开峰 + 建筑 10 种 + 区域/邻接 + 劳力 + 改良地形限制 + 经济结算/赤字 + 道路减耗 + 气运扩张 + 确定性）
      [12/14] 客户端 R3 验收：res://tests/R3ClientTest.tscn 无头全绿；
            再加 --integration 端到端（选中灵峰 → 城市面板 → 建造山门 → 指派劳力 → 相机不重置）
      [13/14] 扫描仓库确认无 .java 文件（零 Java 约束）+ 最终残留进程断言
      [14/14] 协议契约校验：docs/PROTOCOL_2.0.md 覆盖 69 条 + ping（tools/check_protocol.ps1）

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

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools\check.ps1
    （本机执行策略为 Restricted，必须用 -ExecutionPolicy Bypass；仓库不提供 .cmd 包装）
#>
[CmdletBinding()]
param(
    [int]$Port = 9527,
    [switch]$SkipImport
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
        if ($line -match 'R1_FAIL|R1_CLIENT_FAIL|R2_FAIL|R2_CLIENT_FAIL|R3_FAIL|R3_CLIENT_FAIL|SMOKE_FAIL|Parse Error|SCRIPT ERROR') { $result += $line.Trim() }
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
    Write-Host "=== 修仙4X·宗门争霸 2.0 —— 里程碑自检（R0 + R1 + R2 + R3）===" -ForegroundColor Cyan
    Write-Host "仓库根：$root"
    Write-Host "临时目录：$workDir"

    # ---------------------------------------------------------------- 0. 环境
    Write-Host "`n[0/14] 环境与交付物清单（R0 + R1 + R3）" -ForegroundColor Cyan
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
    $missing = @()
    foreach ($rel in $expectedFiles) {
        if (-not (Test-Path (Join-Path $root $rel))) { $missing += $rel }
    }
    Assert-Check ($missing.Count -eq 0) `
        "R0+R1+R3 交付物清单齐全（R0 $($r0Files.Count) + R1 $($r1Files.Count) + R3 $($r3Files.Count) 个文件）" `
        ("缺失：`n" + ($missing -join "`n"))

    if (-not $godotExe) { throw '未定位到 Godot 可执行文件，后续步骤无法进行。' }

    # ------------------------------------------- 1. shared 目录联接（幂等 + 贯通）
    Write-Host "`n[1/14] shared/ 目录联接（幂等 + 内容贯通）" -ForegroundColor Cyan
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
    Write-Host "`n[2/14] 工程导入与 GDScript 解析" -ForegroundColor Cyan
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
    Write-Host "`n[3/14] 配置缺失时非零退出（负向用例）" -ForegroundColor Cyan
    $missingConfig = Join-Path $workDir 'not-exists.json'
    $badResult = Invoke-GodotCapture -Executable $godotExe `
        -Arguments @('--headless', '--path', $serverPath, '--', "--port=$Port", "--data=$missingConfig") `
        -TimeoutMs 60000
    $badCombined = ($badResult.StdOut + "`n" + $badResult.StdErr)
    Assert-Check ($badResult.ExitCode -ne 0) '配置缺失时服务端以非零退出码结束' "退出码：$($badResult.ExitCode)"
    Assert-Check ($badCombined -match 'config_load_failed|配置加载失败') '配置缺失时输出可诊断的失败原因' $badCombined.Trim()

    # ------------------------------------------------- 4. 启动 headless 服务端
    Write-Host "`n[4/14] headless 服务端启动并监听" -ForegroundColor Cyan
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
    Write-Host "`n[5/14] 无头自测（res://tests/SmokeTest.tscn，R0 协议回归）" -ForegroundColor Cyan
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
    Write-Host "`n[6/14] 进程清理（R0 服务端）" -ForegroundColor Cyan

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
Write-Host "`n[7/14] 服务端 R1 验收（res://tests/R1Test.tscn）" -ForegroundColor Cyan
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
Write-Host "`n[8/14] 服务端 R2 验收（res://tests/R2Test.tscn）" -ForegroundColor Cyan
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
Write-Host "`n[9/14] 客户端 R1 验收（res://tests/R1ClientTest.tscn）" -ForegroundColor Cyan
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
Write-Host "`n[10/14] 客户端 R2 验收（res://tests/R2ClientTest.tscn）" -ForegroundColor Cyan
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
Write-Host "`n[11/14] 服务端 R3 验收（res://tests/R3Test.tscn）" -ForegroundColor Cyan
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
Write-Host "`n[12/14] 客户端 R3 验收（res://tests/R3ClientTest.tscn）" -ForegroundColor Cyan
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

# ------------------------------------------------------ 13. 仓库扫描与最终残留
Write-Host "`n[13/14] 仓库扫描：零 Java + 最终残留" -ForegroundColor Cyan
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

# ---------------------------------------------- 14. 协议契约（PROTOCOL_2.0）
Write-Host "`n[14/14] 协议契约校验（docs/PROTOCOL_2.0.md）" -ForegroundColor Cyan
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
