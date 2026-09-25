# ============================================================
#  post-rename.ps1
#  Run this ONCE after renaming the workspace folder.
#
#  What it does:
#     1. detects the new workspace path automatically (from its own
#        location), so no hardcoded paths to fix by hand
#     2. rewrites _tools\settings.xml  -> new Maven repo location
#     3. rewrites db\mysql.ps1         -> no change needed (uses C:\devtools)
#     4. MOVES the MySQL data dir from C:\devtools\data into the
#        workspace  (<workspace>\mysql-data) so the whole project
#        becomes self-contained, then rewrites C:\devtools\my.ini
#     5. restarts MySQL and verifies the data is intact
#
#  Usage (normal PowerShell, NOT as administrator):
#     cd <new workspace>\_tools
#     powershell -ExecutionPolicy Bypass -File post-rename.ps1
#
#  NOTE: ASCII-only on purpose (PowerShell 5.1 decodes BOM-less files
#  with the system ANSI codepage, which corrupts non-ASCII text).
# ============================================================

$ErrorActionPreference = 'Stop'

# --- locate ourselves: this file sits in <workspace>\_tools ---
$Tools     = $PSScriptRoot
$Workspace = Split-Path $Tools -Parent

$JdkHome   = 'C:\devtools\jdk17\jdk-17.0.20.1+1'
$MvnHome   = 'C:\devtools\maven\apache-maven-3.9.11'
$MySQLHome = 'C:\devtools\mysql'
$MyIni     = 'C:\devtools\my.ini'
$OldData   = 'C:\devtools\data'
$NewData   = Join-Path $Workspace 'mysql-data'
$Mysqld    = Join-Path $MySQLHome 'bin\mysqld.exe'
$Mysql     = Join-Path $MySQLHome 'bin\mysql.exe'
$Pass      = 'root123456'

Write-Host ''
Write-Host '=== Detected workspace ===' -ForegroundColor Cyan
Write-Host ('  ' + $Workspace)

# Refuse to run while the path still contains non-ASCII characters:
# mysqld cannot handle them at all.
$nonAscii = ($Workspace.ToCharArray() | Where-Object { [int]$_ -gt 127 } | Measure-Object).Count
if ($nonAscii -gt 0) {
    Write-Host ''
    Write-Host '  WARNING: the workspace path still contains non-ASCII characters.' -ForegroundColor Yellow
    Write-Host '  Rename the folder to a plain-English name first (e.g. "test"),' -ForegroundColor Yellow
    Write-Host '  otherwise mysqld will fail to start.' -ForegroundColor Yellow
    Write-Host ''
    $go = Read-Host '  Continue anyway? (y/N)'
    if ($go -ne 'y') { exit 1 }
}

# ------------------------------------------------------------
Write-Host ''
Write-Host '=== 1/5  stop MySQL ===' -ForegroundColor Cyan
if (Get-Process mysqld -ErrorAction SilentlyContinue) {
    & $Mysql -u root -h 127.0.0.1 ('-p' + $Pass) -e 'SHUTDOWN;' 2>&1 | Out-Null
    for ($i = 0; $i -lt 20; $i++) {
        Start-Sleep -Seconds 1
        if (-not (Get-Process mysqld -ErrorAction SilentlyContinue)) { break }
    }
    Get-Process mysqld -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Seconds 2
    Write-Host '  stopped'
} else {
    Write-Host '  was not running'
}

# ------------------------------------------------------------
Write-Host ''
Write-Host '=== 2/5  move the data directory into the workspace ===' -ForegroundColor Cyan
if (Test-Path $NewData) {
    Write-Host ('  target already exists, leaving it alone: ' + $NewData)
} elseif (Test-Path $OldData) {
    Write-Host ('  moving ' + $OldData + '  ->  ' + $NewData)
    Move-Item $OldData $NewData
    Write-Host '  moved'
} else {
    Write-Host '  no data dir found in either place (will be re-initialised if needed)'
}
New-Item -ItemType Directory -Path (Join-Path $NewData 'tmp') -Force | Out-Null

# ------------------------------------------------------------
Write-Host ''
Write-Host '=== 3/5  rewrite C:\devtools\my.ini ===' -ForegroundColor Cyan
# Build the file line by line: avoids every backslash/quoting pitfall.
$lines = @(
    '[mysqld]'
    'basedir=' + ($MySQLHome -replace '\\', '/')
    'datadir=' + ($NewData   -replace '\\', '/')
    'port=3306'
    'bind-address=127.0.0.1'
    'character-set-server=utf8mb4'
    'collation-server=utf8mb4_unicode_ci'
    'default-storage-engine=INNODB'
    'max_connections=200'
    'log-error=' + ((Join-Path $Workspace 'mysql-logs\error.log') -replace '\\', '/')
    'tmpdir=' + ((Join-Path $NewData 'tmp') -replace '\\', '/')
    ''
    '[client]'
    'port=3306'
    'default-character-set=utf8mb4'
    ''
    '[mysql]'
    'default-character-set=utf8mb4'
)
[System.IO.File]::WriteAllText($MyIni, ($lines -join "`r`n"), (New-Object System.Text.UTF8Encoding $false))
New-Item -ItemType Directory -Path (Join-Path $Workspace 'mysql-logs') -Force | Out-Null
Write-Host ('  written: ' + $MyIni)

# ------------------------------------------------------------
Write-Host ''
Write-Host '=== 4/5  update _tools\settings.xml ===' -ForegroundColor Cyan
$settings = Join-Path $Tools 'settings.xml'
$repo     = Join-Path $Workspace 'maven-repo'
if (Test-Path $settings) {
    $txt = Get-Content $settings -Raw
    $txt = $txt -replace '<localRepository>.*?</localRepository>', ('<localRepository>' + $repo + '</localRepository>')
    [System.IO.File]::WriteAllText($settings, $txt, (New-Object System.Text.UTF8Encoding $false))
    Write-Host ('  localRepository -> ' + $repo)
    Write-Host ('  maven-repo exists: ' + (Test-Path $repo))
} else {
    Write-Host '  settings.xml not found, skipped'
}

# ------------------------------------------------------------
Write-Host ''
Write-Host '=== 5/5  restart MySQL and verify ===' -ForegroundColor Cyan
Start-Process -FilePath $Mysqld -ArgumentList @('--defaults-file=' + $MyIni) -WindowStyle Hidden
$up = $false
for ($i = 0; $i -lt 30; $i++) {
    Start-Sleep -Seconds 1
    & $Mysql -u root -h 127.0.0.1 ('-p' + $Pass) -e 'SELECT 1;' 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) { $up = $true; break }
}
if ($up) {
    Write-Host '  MySQL is UP' -ForegroundColor Green
    & $Mysql -u root -h 127.0.0.1 ('-p' + $Pass) --default-character-set=utf8mb4 `
        -e 'SELECT COUNT(*) AS load_rows FROM power_load.load_record;' 2>&1
} else {
    Write-Host '  MySQL FAILED to start. Check the log:' -ForegroundColor Red
    Get-Content (Join-Path $Workspace 'mysql-logs\error.log') -Tail 20 -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host '=== done ===' -ForegroundColor Green
Write-Host 'Next: tell the assistant "run the continue notes" and it will pick up from here.'
