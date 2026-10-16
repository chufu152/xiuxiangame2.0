#Requires -Version 5.1
<#
.SYNOPSIS
    协议契约校验：docs/PROTOCOL_2.0.md 是否完整覆盖 69 条命令 + ping。

.DESCRIPTION
    幂等只读脚本，不修改任何文件。断言：
      1. 从 docs/REQUIREMENTS_2.0.md §6.7 的「**分组（N）**：...」行提取命令名，与
         shared/protocol/commands.gd 的常量合并，得到权威命令集合；
      2. PROTOCOL_2.0.md 正文覆盖 69 条 + ping，分组点数严格为
         会话13 / 单位22 / 城市18 / 探索4 / 政令4 / 自动化6 / 待抉择2 = 69，不缺不溢；
      3. 每条命令条目都含 params / result / view / errorCode / 里程碑 / 状态 / 出处 七个小节；
      4. commands.gd 中已登记的命令（ping/newGame/getState）在文档里均标「已实现」；
      5. 裁剪的 19 条命令只出现在 §10，不出现在 §2–§9 正文；
      6. 全文 TODO(需核对) 数量单独打印（列出清单，但不因 TODO 判失败）。

    退出码：0 = 全绿；1 = 存在失败项。

.PARAMETER ProtocolPath
    PROTOCOL_2.0.md 路径，默认 <repo>/docs/PROTOCOL_2.0.md。

.PARAMETER PrdPath
    REQUIREMENTS_2.0.md 路径，默认 <repo>/docs/REQUIREMENTS_2.0.md。

.PARAMETER CommandsPath
    shared/protocol/commands.gd 路径。

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools\check_protocol.ps1
#>
[CmdletBinding()]
param(
    [string]$ProtocolPath,
    [string]$PrdPath,
    [string]$CommandsPath
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
if (-not $ProtocolPath) { $ProtocolPath = Join-Path $root 'docs\PROTOCOL_2.0.md' }
if (-not $PrdPath) { $PrdPath = Join-Path $root 'docs\REQUIREMENTS_2.0.md' }
if (-not $CommandsPath) { $CommandsPath = Join-Path $root 'shared\protocol\commands.gd' }

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

# 文档内的分组编号 -> 期望点数（会话/单位/城市/探索/政令/自动化/待抉择）
# 注意：必须用普通 Hashtable——[ordered]@{} 生成的是 OrderedDictionary，用整数下标访问会走
# 「按位置索引」的重载而不是「按键查找」，会静默取到错位的值。
$expectedGroupCounts = @{ 2 = 13; 3 = 22; 4 = 18; 5 = 4; 6 = 4; 7 = 6; 8 = 2 }
$groupOrder = @(2, 3, 4, 5, 6, 7, 8)
$requiredLabels = @('params', 'result', 'view', 'errorCode', '里程碑', '状态', '出处')

Write-Host "=== PROTOCOL_2.0 契约校验 ===" -ForegroundColor Cyan
Write-Host "文档：$ProtocolPath"

if (-not (Test-Path -PathType Leaf $ProtocolPath)) {
    Write-Host "  [FAIL] 找到 docs/PROTOCOL_2.0.md" -ForegroundColor Red
    Write-Host 'CHECK_PROTOCOL_RESULT=FAIL'
    exit 1
}

$doc = Get-Content -Path $ProtocolPath -Raw -Encoding UTF8
$prd = Get-Content -Path $PrdPath -Raw -Encoding UTF8
$commandsGd = Get-Content -Path $CommandsPath -Raw -Encoding UTF8

# ---------------------------------------------------------------------------
# 1. 权威命令集合：PRD §6.7 分组行 + commands.gd 常量
# ---------------------------------------------------------------------------

$prdGroups = @{}
$groupPattern = '(?m)^\*\*(会话|单位|城市/区域/改良|探索|政令|自动化/设置|待抉择)（(\d+)）\*\*：(.*)$'
foreach ($match in [regex]::Matches($prd, $groupPattern)) {
    $label = $match.Groups[1].Value
    $declared = [int]$match.Groups[2].Value
    $names = @([regex]::Matches($match.Groups[3].Value, '`([a-z][a-zA-Z0-9]*)`') |
        ForEach-Object { $_.Groups[1].Value })
    $prdGroups[$label] = @{ Declared = $declared; Names = $names }
}

Assert-Check ($prdGroups.Count -eq 7) '从 PRD §6.7 提取到 7 个命令分组' `
    "实际：$($prdGroups.Count) 个 -> $($prdGroups.Keys -join ' / ')"

$prdNames = New-Object System.Collections.Generic.List[string]
foreach ($key in $prdGroups.Keys) {
    foreach ($n in $prdGroups[$key].Names) { $prdNames.Add($n) }
}
$prdSet = @($prdNames | Select-Object -Unique)
Assert-Check ($prdSet.Count -eq 69) 'PRD §6.7 命令集合共 69 条' "实际：$($prdSet.Count) 条"

foreach ($key in $prdGroups.Keys) {
    $actual = @($prdGroups[$key].Names | Select-Object -Unique).Count
    Assert-Check ($actual -eq $prdGroups[$key].Declared) `
        "PRD §6.7「$key」点数 = 声明值 $($prdGroups[$key].Declared)" "实际：$actual"
}

$gdNames = @([regex]::Matches($commandsGd, 'const\s+[A-Z_]+\s*:\s*String\s*=\s*"([a-zA-Z]+)"') |
    ForEach-Object { $_.Groups[1].Value })
Assert-Check ($gdNames.Count -ge 1) 'commands.gd 至少登记 1 条命令' "实际：$($gdNames -join ', ')"

# ---------------------------------------------------------------------------
# 2. 解析 PROTOCOL_2.0.md 的章节与命令条目
# ---------------------------------------------------------------------------

$sections = @{}
foreach ($part in [regex]::Split($doc, '(?m)^##\s+')) {
    $m = [regex]::Match($part, '^(\d+)\.')
    if ($m.Success) { $sections[[int]$m.Groups[1].Value] = $part }
}

Assert-Check ($sections.Count -ge 12) '文档含 §0–§12 全部章节' `
    "实际解析到章节：$(($sections.Keys | Sort-Object) -join ', ')"

$blockMap = @{}
$docNames = New-Object System.Collections.Generic.List[string]

foreach ($num in $groupOrder) {
    $body = $sections[$num]
    if (-not $body) {
        Assert-Check $false "文档存在 §$num" "未解析到该章节"
        continue
    }
    $declared = -1
    if ($body -match '（(\d+)\s*条）') { $declared = [int]$Matches[1] }
    Assert-Check ($declared -eq $expectedGroupCounts[$num]) `
        "§$num 标题声明点数 = $($expectedGroupCounts[$num]) 条" "实际声明：$declared"

    $chunks = [regex]::Split($body, '(?m)^###\s+')
    $sectionNames = New-Object System.Collections.Generic.List[string]
    for ($i = 1; $i -lt $chunks.Count; $i++) {
        $name = ([regex]::Match($chunks[$i], '^`([a-zA-Z]+)`')).Groups[1].Value
        if ($name) {
            $sectionNames.Add($name)
            $blockMap[$name] = $chunks[$i]
        }
    }
    Assert-Check ($sectionNames.Count -eq $expectedGroupCounts[$num]) `
        "§$num 命令条目数 = $($expectedGroupCounts[$num])" "实际：$($sectionNames.Count)"
    foreach ($n in $sectionNames) { $docNames.Add($n) }
}

# ping 单列在 §9
$pingNames = New-Object System.Collections.Generic.List[string]
if ($sections[9]) {
    foreach ($chunk in [regex]::Split($sections[9], '(?m)^###\s+')) {
        $name = ([regex]::Match($chunk, '^`([a-zA-Z]+)`')).Groups[1].Value
        if ($name) { $pingNames.Add($name); $blockMap[$name] = $chunk }
    }
}
Assert-Check (@($pingNames) -contains 'ping') '§9 单列了 ping' "实际：$($pingNames -join ', ')"
Assert-Check ($pingNames.Count -eq 1) '§9 只列 ping 一条' "实际：$($pingNames.Count) 条"

# ---------------------------------------------------------------------------
# 3. 覆盖度：正文 == 69 条 + ping
# ---------------------------------------------------------------------------

$missing = @($prdSet | Where-Object { $docNames -notcontains $_ })
$extra = @($docNames | Where-Object { $prdSet -notcontains $_ })
Assert-Check ($missing.Count -eq 0) 'PRD §6.7 的 69 条命令全部出现在 §2–§9' "缺失：`n$($missing -join "`n")"
Assert-Check ($extra.Count -eq 0) '§2–§9 未出现 PRD §6.7 之外的命令' "多余：`n$($extra -join "`n")"

$total = $docNames.Count + $pingNames.Count
Assert-Check ($total -eq 70) '正文合计 69 条 + ping = 70 条' "实际：$total"

# ---------------------------------------------------------------------------
# 4. 每条命令的七个小节
# ---------------------------------------------------------------------------

$missingLabels = New-Object System.Collections.Generic.List[string]
foreach ($name in $blockMap.Keys) {
    foreach ($label in $requiredLabels) {
        if ($blockMap[$name].IndexOf("**$label**", [StringComparison]::Ordinal) -lt 0) {
            $missingLabels.Add("$name 缺 **$label**")
        }
    }
}
Assert-Check ($missingLabels.Count -eq 0) `
    '每条命令条目均含 params/result/view/errorCode/里程碑/状态/出处 七个小节' `
    ($missingLabels -join "`n")

# ---------------------------------------------------------------------------
# 5. commands.gd 已登记命令必须标「已实现」
# ---------------------------------------------------------------------------

$stateIssues = New-Object System.Collections.Generic.List[string]
foreach ($name in $gdNames) {
    if (-not $blockMap.ContainsKey($name)) {
        $stateIssues.Add("$name 未出现在 §2–§9")
        continue
    }
    if ($blockMap[$name] -notmatch '\*\*状态\*\*：\s*已实现') {
        $stateIssues.Add("$name 已在 commands.gd 登记，但文档未标「已实现」")
    }
}
Assert-Check ($stateIssues.Count -eq 0) `
    "commands.gd 已登记命令（$($gdNames -join '/')）在文档中均为「已实现」" `
    ($stateIssues -join "`n")

# ---------------------------------------------------------------------------
# 6. 裁剪的 19 条只出现在 §10
# ---------------------------------------------------------------------------

$cutRegion = ([regex]::Match($prd, '(?s)###\s*5\.1(.*?)###\s*5\.2')).Groups[1].Value
$cutNames = New-Object System.Collections.Generic.List[string]
foreach ($line in ($cutRegion -split "`r?`n")) {
    if ($line -match '^\|' -and $line -notmatch '^\|\s*-') {
        $cols = $line.Split('|')
        if ($cols.Count -ge 4) {
            foreach ($m in [regex]::Matches($cols[2], '`([a-z][a-zA-Z0-9]*)`')) {
                $cutNames.Add($m.Groups[1].Value)
            }
        }
    }
}
$cutSet = @($cutNames | Select-Object -Unique)
Assert-Check ($cutSet.Count -eq 19) 'PRD §5.1 裁剪命令共 19 条' "实际：$($cutSet.Count) 条 -> $($cutSet -join ', ')"

$section10 = if ($sections[10]) { $sections[10] } else { '' }
$notInSection10 = @($cutSet | Where-Object { $section10.IndexOf('`' + $_ + '`', [StringComparison]::Ordinal) -lt 0 })
Assert-Check ($notInSection10.Count -eq 0) '裁剪的 19 条全部列于 §10' "缺失：$($notInSection10 -join ', ')"

$leaked = @($cutSet | Where-Object { $docNames -contains $_ -or $pingNames -contains $_ })
Assert-Check ($leaked.Count -eq 0) '裁剪命令未出现在 §2–§9 正文' "越界：$($leaked -join ', ')"

# ---------------------------------------------------------------------------
# 7. TODO(需核对) 统计（打印清单，不判失败）
# ---------------------------------------------------------------------------

$todoLines = New-Object System.Collections.Generic.List[string]
$lineNo = 0
foreach ($line in ($doc -split "`r?`n")) {
    $lineNo++
    if ($line.IndexOf('TODO(需核对)', [StringComparison]::Ordinal) -ge 0) {
        $todoLines.Add("L$lineNo")
    }
}
Write-Host "`n  TODO(需核对) 标记数：$($todoLines.Count)" -ForegroundColor Yellow
if ($todoLines.Count -gt 0) {
    Write-Host "  位置：$($todoLines -join ', ')" -ForegroundColor DarkGray
}

# ---------------------------------------------------------------------------
# 汇总
# ---------------------------------------------------------------------------

Write-Host ''
Write-Host '  分组点数核对表：' -ForegroundColor Cyan
foreach ($num in $groupOrder) {
    $body = $sections[$num]
    $declared = -1
    if ($body -and $body -match '（(\d+)\s*条）') { $declared = [int]$Matches[1] }
    Write-Host ("    §{0}  期望 {1,2} 条  实际 {2,2} 条" -f $num, $expectedGroupCounts[$num], $declared)
}
Write-Host ("    合计  期望 69 条  实际 {0,2} 条（另 ping 1 条）" -f $docNames.Count)

Write-Host ''
Write-Host "=== 校验结果：$($script:checkCount - $script:failCount) / $($script:checkCount) 项通过 ===" -ForegroundColor Cyan
if ($script:failCount -eq 0) {
    Write-Host 'CHECK_PROTOCOL_RESULT=OK' -ForegroundColor Green
    exit 0
}
else {
    Write-Host "CHECK_PROTOCOL_RESULT=FAIL（$($script:failCount) 项失败）" -ForegroundColor Red
    exit 1
}
