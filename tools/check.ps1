#Requires -Version 5.1
<#
.SYNOPSIS
    R0 自检（对应 docs/prompts/R0_工程骨架.md「自动验收」）。

.DESCRIPTION
    依次执行：
      [0/7] 环境与 R0 交付物清单
      [1/7] shared/ 目录联接：幂等 + 内容贯通（临时文件在另一处可见）
      [2/7] 两个工程 --import 无解析错误并生成 class_name 缓存
      [3/7] 配置缺失时服务端非零退出（负向用例）
      [4/7] console 版 --headless 启动服务端并监听 127.0.0.1:9527
      [5/7] 运行 res://tests/SmokeTest.tscn，断言 SMOKE_PASS 且退出码 0
      [6/7] 清理本脚本拉起的 Godot 进程，断言 tasklist 无残留
      [7/7] 扫描仓库确认无 .java 文件（零 Java 约束）

    退出码：0 = 全绿；1 = 存在失败项。

    说明：本脚本用 .NET Process 而非 Start-Process 启动子进程——本机环境块同时存在
    HTTP_PROXY 与 http_proxy，Start-Process 重建环境字典时会抛「已添加项。字典中的
    关键字…」，导致子进程根本无法启动。.NET Process 继承父进程环境块，规避该问题。
    服务端就绪改用 TCP 端口轮询判定（Godot 对 stdout 重定向的行为不稳定，不依赖日志匹配）。

.PARAMETER Port
    自检使用的端口，默认 9527。

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
# 公共函数（与 run_dev.ps1 保持一致；R0 不引入额外公共脚本，避免超出文件清单）
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

# 同步运行并捕获输出，返回 @{ StdOut; StdErr; ExitCode }
function Invoke-GodotCapture {
    param(
        [Parameter(Mandatory)][string]$Executable,
        [Parameter(Mandatory)][string[]]$Arguments,
        [int]$TimeoutMs = 180000
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
    try { $stdout = $outTask.GetAwaiter().GetResult() } catch { }
    try { $stderr = $errTask.GetAwaiter().GetResult() } catch { }
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

# ---------------------------------------------------------------------------
# 主流程
# ---------------------------------------------------------------------------

$root = Split-Path -Parent $PSScriptRoot
$serverPath = Join-Path $root 'server'
$clientPath = Join-Path $root 'client'
$sharedPath = Join-Path $root 'shared'
$dataPath = Join-Path $root 'data\gameConfig.json'

$workDir = Join-Path ([IO.Path]::GetTempPath()) ('xiuxian-r0-check-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $workDir -Force | Out-Null

$serverProcess = $null
$serverOutTask = $null
$serverErrTask = $null

try {
    Write-Host "=== 修仙4X·宗门争霸 2.0 —— R0 自检 ===" -ForegroundColor Cyan
    Write-Host "仓库根：$root"
    Write-Host "临时目录：$workDir"

    # ---------------------------------------------------------------- 0. 环境
    Write-Host "`n[0/7] 环境与交付物清单" -ForegroundColor Cyan
    $godotExe = $null
    try { $godotExe = Resolve-GodotConsole }
    catch { Assert-Check $false '定位 Godot 控制台版可执行文件' $_.Exception.Message }
    Assert-Check ([bool]$godotExe) '定位 Godot 控制台版可执行文件' "路径：$godotExe"
    if ($godotExe) { Write-Host "  Godot: $godotExe" }

    $expectedFiles = @(
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
    $missing = @()
    foreach ($rel in $expectedFiles) {
        if (-not (Test-Path (Join-Path $root $rel))) { $missing += $rel }
    }
    Assert-Check ($missing.Count -eq 0) "R0 交付物清单齐全（$($expectedFiles.Count) 个文件）" `
        ("缺失：`n" + ($missing -join "`n"))

    if (-not $godotExe) { throw '未定位到 Godot 可执行文件，后续步骤无法进行。' }

    # ------------------------------------------- 1. shared 目录联接（幂等 + 贯通）
    Write-Host "`n[1/7] shared/ 目录联接（幂等 + 内容贯通）" -ForegroundColor Cyan
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
        Set-Content -Path $probeClient -Value 'r0-junction-probe' -Encoding ASCII -ErrorAction Stop
        $roundTripOk = (Test-Path $probeServer) -and (Test-Path $probeTop)
    }
    catch { $roundTripOk = $false }
    finally {
        foreach ($p in @($probeClient, $probeServer, $probeTop)) {
            if (Test-Path $p) { Remove-Item $p -Force -ErrorAction SilentlyContinue }
        }
    }
    Assert-Check $roundTripOk 'client/shared 写入内容在 server/shared 与顶层 shared 均可见'
    Assert-Check (-not (Test-Path $probeTop)) '临时探测文件已清理'

    # --------------------------------------------------------- 2. 工程导入
    Write-Host "`n[2/7] 工程导入与 GDScript 解析" -ForegroundColor Cyan
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
    Write-Host "`n[3/7] 配置缺失时非零退出（负向用例）" -ForegroundColor Cyan
    $missingConfig = Join-Path $workDir 'not-exists.json'
    $badResult = Invoke-GodotCapture -Executable $godotExe `
        -Arguments @('--headless', '--path', $serverPath, '--', "--port=$Port", "--data=$missingConfig") `
        -TimeoutMs 60000
    $badCombined = ($badResult.StdOut + "`n" + $badResult.StdErr)
    Assert-Check ($badResult.ExitCode -ne 0) '配置缺失时服务端以非零退出码结束' "退出码：$($badResult.ExitCode)"
    Assert-Check ($badCombined -match 'config_load_failed|配置加载失败') '配置缺失时输出可诊断的失败原因' $badCombined.Trim()

    # ------------------------------------------------- 4. 启动 headless 服务端
    Write-Host "`n[4/7] headless 服务端启动并监听" -ForegroundColor Cyan
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
    Write-Host "`n[5/7] 无头自测（res://tests/SmokeTest.tscn）" -ForegroundColor Cyan
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
    Write-Host "`n[6/7] 进程清理" -ForegroundColor Cyan

    if ($serverProcess) {
        try { $serverProcess.Refresh() } catch { }
        if (-not $serverProcess.HasExited) {
            try { $serverProcess.Kill() } catch { }
            try { [void]$serverProcess.WaitForExit(5000) } catch { }
        }
        # 进程结束后管道关闭，可读取累积的服务端启动日志并校验。
        $serverStdout = ''
        try { $serverStdout = $serverOutTask.GetAwaiter().GetResult() } catch { }
        if ($serverStdout) {
            Assert-Check ($serverStdout -match 'server listening on 127\.0\.0\.1') `
                '服务端启动打印「server listening on 127.0.0.1」' $serverStdout.Trim()
            Assert-Check ($serverStdout -match 'config ok') '服务端启动完成配置加载与校验' $serverStdout.Trim()
        }
    }

    Start-Sleep -Milliseconds 800
    foreach ($path in @($serverPath, $clientPath)) {
        foreach ($item in (Get-ProjectGodotProcesses -ProjectPath $path)) {
            try { Stop-Process -Id $item.ProcessId -Force -ErrorAction SilentlyContinue } catch { }
        }
    }
    Start-Sleep -Milliseconds 500

    $residualServer = Get-ProjectGodotProcesses -ProjectPath $serverPath
    $residualClient = Get-ProjectGodotProcesses -ProjectPath $clientPath
    Assert-Check ($residualServer.Count -eq 0) '结束后无残留 godot 服务端进程' `
        (($residualServer | ForEach-Object { "pid=$($_.ProcessId) $($_.CommandLine)" }) -join "`n")
    Assert-Check ($residualClient.Count -eq 0) '结束后无残留 godot 客户端进程' `
        (($residualClient | ForEach-Object { "pid=$($_.ProcessId) $($_.CommandLine)" }) -join "`n")
}

# ------------------------------------------------------ 7. 仓库扫描：零 Java
Write-Host "`n[7/7] 仓库扫描：零 Java" -ForegroundColor Cyan
$javaFiles = @()
try {
    $javaFiles = Get-ChildItem -Path $root -Recurse -File -Filter '*.java' -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '[\\/]\.(git|godot)[\\/]' }
}
catch { }
Assert-Check ($javaFiles.Count -eq 0) '全仓库无 .java 文件（零 Java 约束）' `
    (($javaFiles | ForEach-Object { $_.FullName }) -join "`n")

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
