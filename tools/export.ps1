#Requires -Version 5.1
<#
.SYNOPSIS
    一键导出 Windows 独立产物（R9 W3）：客户端 + 服务端 + 配置 + 资源。

.DESCRIPTION
    产出目录结构（默认 dist\xiuxian\）：

        Xiuxian.exe           客户端（Godot 导出，非控制台窗口）
        Xiuxian.pck           客户端资源包
        XiuxianServer.exe     服务端（headless 运行）
        XiuxianServer.pck     服务端资源包
        data\gameConfig.json  权威配置（服务端启动时按 --data 读取）
        assets\               美术/音频/清单（AssetLibrary 按绝对路径直接读文件）

    客户端在**导出态**（OS.has_feature("template")）会拉起同目录的 XiuxianServer.exe，
    并把 assets/ 与 data/ 定位到可执行文件所在目录——见 client/scripts/net/Launcher.gd。

    步骤：
      1. 校验 Godot 4.4.1 导出模板已安装（%APPDATA%\Godot\export_templates\4.4.1.stable）
      2. 两个工程各跑一次 --import（导出需要 .godot\imported 缓存）
      3. --export-release "Windows Desktop" 导出两个 exe
      4. 拷 data\gameConfig.json 与 assets\ 到产物目录
      5. 断言产物齐全并打印清单

.PARAMETER OutputDir
    产物目录，默认 <repo>\dist\xiuxian。

.PARAMETER SkipImport
    跳过 --import（缓存已存在时可加速）。

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools\export.ps1
#>
[CmdletBinding()]
param(
    [string]$OutputDir = '',
    [switch]$SkipImport
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path $repoRoot 'dist\xiuxian'
}
$OutputDir = [System.IO.Path]::GetFullPath($OutputDir)

$clientDir = Join-Path $repoRoot 'client'
$serverDir = Join-Path $repoRoot 'server'
$presetName = 'Windows Desktop'
$templateVersion = '4.4.1.stable'

# ---------------------------------------------------------------------------
# 公共函数（与 check.ps1 保持一致）
# ---------------------------------------------------------------------------

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

# 同步运行并捕获输出（不用 Start-Process：本机环境块有重复代理键会抛异常）。
function Invoke-Godot {
    param(
        [Parameter(Mandatory)][string]$Executable,
        [Parameter(Mandatory)][string[]]$Arguments,
        [Parameter(Mandatory)][string]$Label
    )
    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = $Executable
    $quoted = foreach ($item in $Arguments) {
        if ($item -match '[\s"]') { '"' + ($item -replace '"', '\"') + '"' } else { $item }
    }
    $info.Arguments = ($quoted -join ' ')
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $utf8 = New-Object System.Text.UTF8Encoding $false
    $info.StandardOutputEncoding = $utf8
    $info.StandardErrorEncoding = $utf8

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $info
    [void]$process.Start()
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $process.WaitForExit(600000) | Out-Null
    if (-not $process.HasExited) {
        try { $process.Kill() } catch { }
        throw "$Label 超时（600 秒）"
    }
    $stdout = $stdoutTask.GetAwaiter().GetResult()
    $stderr = $stderrTask.GetAwaiter().GetResult()
    $code = $process.ExitCode
    $process.Dispose()
    return @{ StdOut = $stdout; StdErr = $stderr; ExitCode = $code }
}

# ---------------------------------------------------------------------------
# 1. 环境检查
# ---------------------------------------------------------------------------

Write-Host "=== 修仙4X·宗门争霸 2.0 —— Windows 导出 ===" -ForegroundColor Cyan
Write-Host "仓库根：$repoRoot"
Write-Host "产物目录：$OutputDir"

$godot = Resolve-GodotConsole
Write-Host "Godot：$godot"

$templateDir = Join-Path $env:APPDATA "Godot\export_templates\$templateVersion"
$windowsTemplate = Join-Path $templateDir 'windows_release_x86_64.exe'
if (-not (Test-Path -PathType Leaf $windowsTemplate)) {
    throw @"
缺少导出模板：$windowsTemplate
请安装 Godot 4.4.1 导出模板（编辑器菜单 编辑器 → 管理导出模板 → 下载并安装），
或把 Godot_v4.4.1-stable_export_templates.tpz 解压到：$env:APPDATA\Godot\export_templates\
"@
}

# ---------------------------------------------------------------------------
# 2. 导入
# ---------------------------------------------------------------------------

if (-not $SkipImport) {
    foreach ($pair in @(@{ Name = 'client'; Path = $clientDir }, @{ Name = 'server'; Path = $serverDir })) {
        Write-Host "`n[import] $($pair.Name)" -ForegroundColor Cyan
        $result = Invoke-Godot -Executable $godot -Label "import $($pair.Name)" -Arguments @(
            '--headless', '--path', $pair.Path, '--import'
        )
        if ($result.ExitCode -ne 0) {
            Write-Host $result.StdOut
            Write-Host $result.StdErr
            throw "工程导入失败（$($pair.Name)，退出码 $($result.ExitCode)）"
        }
    }
}

# ---------------------------------------------------------------------------
# 3. 导出
# ---------------------------------------------------------------------------

if (Test-Path $OutputDir) { Remove-Item -Recurse -Force $OutputDir }
New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null

$targets = @(
    @{ Name = 'client'; Path = $clientDir; Exe = (Join-Path $OutputDir 'Xiuxian.exe') },
    @{ Name = 'server'; Path = $serverDir; Exe = (Join-Path $OutputDir 'XiuxianServer.exe') }
)

foreach ($target in $targets) {
    Write-Host "`n[export] $($target.Name) -> $($target.Exe)" -ForegroundColor Cyan
    $result = Invoke-Godot -Executable $godot -Label "export $($target.Name)" -Arguments @(
        '--headless', '--path', $target.Path, '--export-release', $presetName, $target.Exe
    )
    if ($result.ExitCode -ne 0) {
        Write-Host $result.StdOut
        Write-Host $result.StdErr
        throw "导出失败（$($target.Name)，退出码 $($result.ExitCode)）"
    }
    if (-not (Test-Path -PathType Leaf $target.Exe)) {
        Write-Host $result.StdOut
        Write-Host $result.StdErr
        throw "导出未生成可执行文件：$($target.Exe)"
    }
}

# ---------------------------------------------------------------------------
# 4. 配置与资源
# ---------------------------------------------------------------------------

Write-Host "`n[copy] data + assets" -ForegroundColor Cyan

$dataTarget = Join-Path $OutputDir 'data'
New-Item -ItemType Directory -Path $dataTarget -Force | Out-Null
Copy-Item -Path (Join-Path $repoRoot 'data\gameConfig.json') -Destination $dataTarget -Force

$assetSource = Join-Path $repoRoot 'assets'
$assetTarget = Join-Path $OutputDir 'assets'
New-Item -ItemType Directory -Path $assetTarget -Force | Out-Null
foreach ($entry in @('manifest.json', 'art', 'audio')) {
    $source = Join-Path $assetSource $entry
    if (Test-Path $source) {
        Copy-Item -Path $source -Destination $assetTarget -Recurse -Force
    }
}

# ---------------------------------------------------------------------------
# 5. 断言与清单
# ---------------------------------------------------------------------------

$required = @(
    'Xiuxian.exe',
    'XiuxianServer.exe',
    'data\gameConfig.json',
    'assets\manifest.json'
)

$failures = 0
Write-Host "`n[verify]" -ForegroundColor Cyan
foreach ($relative in $required) {
    $full = Join-Path $OutputDir $relative
    if (Test-Path -PathType Leaf $full) {
        $size = (Get-Item $full).Length
        Write-Host ("  [PASS] {0}  ({1:N0} 字节)" -f $relative, $size)
    } else {
        Write-Host ("  [FAIL] {0}  缺失" -f $relative) -ForegroundColor Red
        $failures++
    }
}

$artCount = 0
$artDir = Join-Path $OutputDir 'assets\art\default'
if (Test-Path $artDir) {
    # 只数真实资源（.glb/.png）；目录里还有各分组的 .gitkeep 占位，不能计入。
    $artCount = (Get-ChildItem -Path $artDir -Recurse -File |
        Where-Object { $_.Extension -in @('.glb', '.png') }).Count
}
if ($artCount -ge 74) {
    Write-Host ("  [PASS] assets\art\default 共 {0} 个模型/贴图（≥ 74）" -f $artCount)
} else {
    Write-Host ("  [FAIL] assets\art\default 只有 {0} 个模型/贴图（期望 ≥ 74）" -f $artCount) -ForegroundColor Red
    $failures++
}

# 第二套皮肤包（R9 W2）必须一并进产物，否则导出后设置面板里选不到它。
$skinDir = Join-Path $OutputDir 'assets\art\zhu_xia'
$skinCount = 0
if (Test-Path $skinDir) {
    $skinCount = (Get-ChildItem -Path $skinDir -Recurse -File |
        Where-Object { $_.Extension -in @('.glb', '.png') }).Count
}
if ($skinCount -ge 74) {
    Write-Host ("  [PASS] assets\art\zhu_xia 共 {0} 个模型/贴图（≥ 74）" -f $skinCount)
} else {
    Write-Host ("  [FAIL] assets\art\zhu_xia 只有 {0} 个模型/贴图（期望 ≥ 74）" -f $skinCount) -ForegroundColor Red
    $failures++
}

$bgm = Join-Path $OutputDir 'assets\audio\bgm\main.wav'
if (Test-Path -PathType Leaf $bgm) {
    Write-Host "  [PASS] assets\audio\bgm\main.wav"
} else {
    Write-Host "  [FAIL] assets\audio\bgm\main.wav 缺失" -ForegroundColor Red
    $failures++
}

Write-Host ""
if ($failures -gt 0) {
    Write-Host "EXPORT_RESULT=FAIL failures=$failures" -ForegroundColor Red
    exit 1
}

Write-Host "产物目录：$OutputDir"
Write-Host "EXPORT_RESULT=OK" -ForegroundColor Green
exit 0
