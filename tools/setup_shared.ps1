# Mount the top-level shared/ folder into client/ and server/ as directory junctions.
# Junctions do NOT require administrator privileges. Run once after clone so Godot
# can reference shared code via res://shared/...
# The client/shared and server/shared junctions are git-ignored; the real source
# is the top-level shared/ folder.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$shared = Join-Path $root 'shared'
if (-not (Test-Path $shared)) { throw "shared folder not found: $shared" }

foreach ($proj in @('client', 'server')) {
    $link = Join-Path (Join-Path $root $proj) 'shared'
    if (Test-Path $link) {
        $item = Get-Item $link -Force
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            cmd /c rmdir "$link" | Out-Null
            Write-Output "Removed existing junction: $proj/shared"
        }
        else {
            throw "$link exists and is not a junction. Please handle it manually."
        }
    }
    cmd /c mklink /J "$link" "$shared" | Out-Null
    if (-not (Test-Path $link)) { throw "failed to create junction: $link" }
    Write-Output "Linked $proj/shared -> ../shared"
}

Write-Output "Done. Both client/ and server/ can now use res://shared/..."
