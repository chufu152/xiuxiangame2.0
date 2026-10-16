#Requires -Version 5.1
<#
.SYNOPSIS
    一键开发启动：headless 服务端 + 客户端（GUI）。

.DESCRIPTION
    1. 定位 Godot 4.4.1 控制台版 / GUI 版可执行文件；
    2. 建立 shared/ 目录联接并导入两个工程（生成 class_name 缓存，可用 -SkipImport 跳过）；
    3. 后台启动 headless 服务端，等待端口就绪；
    4. 前台启动客户端；客户端退出后回收服务端子进程。

    说明：本脚本用 .NET Process 而非 Start-Process 启动子进程——本机环境块同时存在
    HTTP_PROXY 与 http_proxy，Start-Process 在重建环境字典时会抛
    “已添加项。字典中的关键字…”。.NET Process 默认继承父进程环境块，不重建，规避该问题。

.PARAMETER Port
    服务端监听端口，默认 9527。

.PARAMETER SkipImport
    跳过工程导入（缓存已存在时可加速）。

.PARAMETER ServerOnly
    只启动服务端，不启动客户端。

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools\run_dev.ps1
    （本机执行策略为 Restricted，必须用 -ExecutionPolicy Bypass；仓库不提供 .cmd 包装）
#>
[CmdletBinding()]
param(
    [int]$Port = 9527,
    [switch]$SkipImport,
    [switch]$ServerOnly
)

$ErrorActionPreference = 'Stop'

# 说明：不修改 [Console]::OutputEncoding——在 CP936 控制台强行切到 UTF-8 反而会乱码。
# Godot 子进程输出一律用 .NET Process 显式按 UTF-8 解码（见 New-GodotStartInfo）。

# ---------------------------------------------------------------------------
# 公共函数
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

function Resolve-GodotGui {
    param([Parameter(Mandatory)][string]$ConsoleExe)
    $gui = $ConsoleExe -replace '_console\.exe$', '.exe'
    if (Test-Path -PathType Leaf $gui) { return $gui }
    throw "找不到 Godot GUI 版可执行文件：$gui"
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
# 主流程
# ---------------------------------------------------------------------------

$root = Split-Path -Parent $PSScriptRoot
$serverPath = Join-Path $root 'server'
$clientPath = Join-Path $root 'client'
$dataPath = Join-Path $root 'data\gameConfig.json'

$consoleExe = Resolve-GodotConsole
$guiExe = Resolve-GodotGui -ConsoleExe $consoleExe
Write-Host "Godot 控制台版: $consoleExe"
Write-Host "Godot GUI 版 : $guiExe"

# 清理上次残留
foreach ($item in (Get-ProjectGodotProcesses -ProjectPath $serverPath)) {
    try {
        Stop-Process -Id $item.ProcessId -Force -ErrorAction Stop
        Write-Host "已回收残留服务端进程 pid=$($item.ProcessId)"
    }
    catch { }
}

if (-not $SkipImport) {
    Write-Host "建立 shared/ 目录联接 ..."
    & (Join-Path $PSScriptRoot 'setup_shared.ps1') | Out-Null
    foreach ($project in @('server', 'client')) {
        Write-Host "导入工程 $project ..."
        $result = Invoke-GodotCapture -Executable $consoleExe `
            -Arguments @('--headless', '--path', (Join-Path $root $project), '--import')
        if ($result.StdErr -match 'Parse Error|SCRIPT ERROR') {
            Write-Host "  [警告] $project 导入期间出现解析错误：" -ForegroundColor Yellow
            Write-Host $result.StdErr -ForegroundColor Yellow
        }
    }
}

Write-Host "启动 headless 服务端（端口 $Port）..." -ForegroundColor Cyan
$serverInfo = New-GodotStartInfo -Executable $consoleExe `
    -Arguments @('--headless', '--path', $serverPath, '--', "--port=$Port", "--data=$dataPath")
$serverProcess = [System.Diagnostics.Process]::Start($serverInfo)

$deadline = (Get-Date).AddSeconds(30)
$ready = $false
while ((Get-Date) -lt $deadline) {
    if (Test-TcpPort -Port $Port) { $ready = $true; break }
    if ($serverProcess.HasExited) { break }
    Start-Sleep -Milliseconds 250
}

if (-not $ready) {
    Write-Host "服务端未在 30 秒内就绪。" -ForegroundColor Red
    if (-not $serverProcess.HasExited) { try { $serverProcess.Kill() } catch { } }
    exit 1
}
Write-Host "服务端就绪：ws://127.0.0.1:$Port" -ForegroundColor Green

$clientExit = 0
if (-not $ServerOnly) {
    Write-Host "启动客户端 ..." -ForegroundColor Cyan
    $clientInfo = New-GodotStartInfo -Executable $guiExe -Arguments @('--path', $clientPath)
    $clientProcess = [System.Diagnostics.Process]::Start($clientInfo)
    $clientProcess.WaitForExit()
    $clientExit = $clientProcess.ExitCode
}

Write-Host "回收服务端子进程 ..." -ForegroundColor Cyan
if (-not $serverProcess.HasExited) { try { $serverProcess.Kill() } catch { } }
foreach ($item in (Get-ProjectGodotProcesses -ProjectPath $serverPath)) {
    try { Stop-Process -Id $item.ProcessId -Force -ErrorAction SilentlyContinue } catch { }
}

$residual = Get-ProjectGodotProcesses -ProjectPath $serverPath
if ($residual.Count -gt 0) {
    Write-Host "警告：仍有 $($residual.Count) 个服务端进程未退出。" -ForegroundColor Yellow
}
else {
    Write-Host "已退出，无残留进程。" -ForegroundColor Green
}

exit $clientExit
