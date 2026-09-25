# ============================================================
#  install-autostart.ps1 - install / uninstall MySQL logon autostart
# ============================================================
#  Usage (from your own PowerShell window):
#     powershell -ExecutionPolicy Bypass -File install-autostart.ps1
#     powershell -ExecutionPolicy Bypass -File install-autostart.ps1 -Uninstall
#
#  What it does:
#     installs  -> copies start-power-load-db.vbs into your Startup folder
#                  (and rewrites its hardcoded workspace path if needed)
#     uninstall -> removes it, so MySQL stops starting automatically
#
#  No administrator rights needed: the Startup folder belongs to the user.
#
#  NOTE: this file is intentionally ASCII-only.
# ============================================================

param(
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'

$Workspace = Split-Path $PSScriptRoot -Parent
$Startup   = [Environment]::GetFolderPath('Startup')
$TargetVbs = Join-Path $Startup 'start-power-load-db.vbs'
$SourceVbs = Join-Path $PSScriptRoot 'start-power-load-db.vbs'

Write-Host ''
Write-Host '=== power-load MySQL autostart ===' -ForegroundColor Cyan
Write-Host ('  workspace : ' + $Workspace)
Write-Host ('  startup   : ' + $Startup)
Write-Host ''

if ($Uninstall) {
    if (Test-Path $TargetVbs) {
        Remove-Item $TargetVbs -Force
        Write-Host 'UNINSTALLED: MySQL will no longer start automatically at logon.' -ForegroundColor Yellow
        Write-Host 'Start it manually with: db\mysql.ps1 start'
    } else {
        Write-Host 'Nothing to uninstall (no launcher in the Startup folder).'
    }
    exit 0
}

if (-not (Test-Path $SourceVbs)) {
    Write-Host ('MISSING source file: ' + $SourceVbs) -ForegroundColor Red
    exit 1
}

# Read the launcher, point it at the CURRENT workspace path, then install.
$text = Get-Content $SourceVbs -Raw

# Matches:  workspace = "C:\any\path\here"
$pattern = 'workspace = ".*"'
if ($text -match $pattern) {
    $replacement = 'workspace = "' + $Workspace + '"'
    $text = $text -replace $pattern, $replacement
} else {
    Write-Host 'Could not find the "workspace =" line in the launcher template.' -ForegroundColor Red
    exit 1
}

# Write as UTF-8 WITHOUT BOM (cscript is fine with either, but no-BOM keeps
# the file identical to a hand-edited one).
[System.IO.File]::WriteAllText($TargetVbs, $text, (New-Object System.Text.UTF8Encoding $false))

Write-Host 'INSTALLED.' -ForegroundColor Green
Write-Host ('  ' + $TargetVbs)
Write-Host ''
Write-Host 'Verify it works right now (MySQL is probably already running, so'
Write-Host 'expect a "nothing to do" line in the log):'
Write-Host ''
Write-Host ('  & cscript.exe //nologo "' + $TargetVbs + '"')
Write-Host ('  Get-Content ' + (Join-Path $Workspace 'mysql-logs\autostart.log'))
Write-Host ''
Write-Host 'The real test is a reboot: after logging in, MySQL should be up'
Write-Host 'within a few seconds, with no window popping up.'
