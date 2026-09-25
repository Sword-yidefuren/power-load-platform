# ============================================================
#  startup-db.ps1 - run automatically at Windows logon
# ============================================================
#  Purpose:
#     MySQL is NOT registered as a Windows service (registering needs
#     admin rights). That means it does not come back after a reboot,
#     and a forgotten "start MySQL" would break the whole demo.
#     This script is what makes it start by itself at logon.
#
#  Installed by: _tools\install-autostart.ps1
#  Called by:    start-power-load-db.vbs in the Windows Startup folder
#
#  Behaviour:
#     - if mysqld is already running: do nothing, log one line
#     - otherwise: start it silently in the background and wait until
#       it really accepts connections (up to ~40s)
#     - EVERY outcome is appended to mysql-logs\autostart.log, so you
#       can always find out what happened after a reboot
#
#  NOTE: this file is intentionally ASCII-only.
#  Windows PowerShell 5.1 decodes BOM-less files as GBK, which corrupts
#  non-ASCII text and can even break string parsing. ASCII avoids that.
# ============================================================

$ErrorActionPreference = 'Continue'

# Locate the workspace from this script's own position (this file lives in
# <workspace>\_tools), so renaming the workspace folder never breaks it.
$Workspace = Split-Path $PSScriptRoot -Parent
$Mysql     = 'C:\devtools\mysql\bin\mysql.exe'
$Mysqld    = 'C:\devtools\mysql\bin\mysqld.exe'
$MyIni     = 'C:\devtools\my.ini'
$LogDir    = Join-Path $Workspace 'mysql-logs'
$LogFile   = Join-Path $LogDir 'autostart.log'

$User = 'root'
$Pass = 'root123456'

if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

function Write-Log {
    param([string]$Message)
    $stamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    try {
        Add-Content -Path $LogFile -Value ('[' + $stamp + '] ' + $Message) -Encoding UTF8
    } catch {
        # Never let logging failure kill the actual job
    }
}

function Test-CanConnect {
    if (-not (Test-Path $Mysql)) { return $false }
    # Use MYSQL_PWD so the password never shows up in the process list
    $env:MYSQL_PWD = $Pass
    & $Mysql -u $User -h 127.0.0.1 -e 'SELECT 1;' 2>&1 | Out-Null
    return ($LASTEXITCODE -eq 0)
}

Write-Log '=== autostart triggered ==='

# ------------------------------------------------------------
#  Case 1: already running -> nothing to do (but still log it,
#  otherwise you can never tell "ran and skipped" from "never ran")
# ------------------------------------------------------------
if (Get-Process mysqld -ErrorAction SilentlyContinue) {
    if (Test-CanConnect) {
        Write-Log 'mysqld already running and accepting connections - nothing to do'
    } else {
        Write-Log 'mysqld process exists but is not accepting connections yet - leaving it alone'
    }
    exit 0
}

# ------------------------------------------------------------
#  Case 2: not running -> start it and wait for readiness
# ------------------------------------------------------------
if (-not (Test-Path $Mysqld)) {
    Write-Log ('FAILED: mysqld not found at ' + $Mysqld)
    exit 1
}

Write-Log 'mysqld not running - starting it'

# Start-Process detaches the server from this script, so the logon
# console can close without killing MySQL.
# ArgumentList is an ARRAY on purpose: a single string containing quotes
# would hand mysqld a literal '"--defaults-file=..."' and it exits silently.
Start-Process -FilePath $Mysqld -ArgumentList @('--defaults-file=' + $MyIni) -WindowStyle Hidden

$ready = $false
for ($i = 0; $i -lt 40; $i++) {
    Start-Sleep -Seconds 1
    if (Test-CanConnect) { $ready = $true; break }
}

if ($ready) {
    Write-Log ('OK: MySQL is up after ' + ($i + 1) + 's')
    exit 0
} else {
    Write-Log 'FAILED: MySQL did not accept connections within 40s'
    $errLog = Join-Path $LogDir 'error.log'
    if (Test-Path $errLog) {
        Write-Log '--- last 10 lines of error.log ---'
        Get-Content $errLog -Tail 10 | ForEach-Object { Write-Log ('  ' + $_) }
    }
    exit 1
}
