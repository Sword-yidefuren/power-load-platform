# ============================================================
#  mysql.ps1 - Start/stop your MySQL 8.0 (green install, no Windows service)
# ============================================================
#  Usage (open PowerShell in this folder):
#     .\mysql.ps1            # show status
#     .\mysql.ps1 start      # start
#     .\mysql.ps1 stop       # stop
#     .\mysql.ps1 restart    # restart
#     .\mysql.ps1 cli        # open mysql client
#     .\mysql.ps1 log        # tail error log
#
#  Connection:
#     host=127.0.0.1  port=3306  user=root  password=root123456
#     database: power_load
#
#  NOTE: this file is intentionally ASCII-only.
#  Windows PowerShell 5.1 decodes BOM-less files as GBK, which corrupts
#  non-ASCII text and can even break string parsing. ASCII avoids that.
# ============================================================
param(
    [Parameter(Position = 0)]
    [ValidateSet('status', 'start', 'stop', 'restart', 'cli', 'log')]
    [string]$Action = 'status'
)

$ErrorActionPreference = 'Continue'

# Locate the workspace from this script's own position (this file is in
# <workspace>\db), so renaming the workspace folder never breaks it.
$Workspace = Split-Path $PSScriptRoot -Parent
$DataDir   = Join-Path $Workspace 'mysql-data'

$MySQLHome = 'C:\devtools\mysql'
$MyIni     = 'C:\devtools\my.ini'
$ErrLog    = Join-Path $Workspace 'mysql-logs\error.log'
$Mysqld    = Join-Path $MySQLHome 'bin\mysqld.exe'
$Mysql     = Join-Path $MySQLHome 'bin\mysql.exe'

$Port = 3306
$User = 'root'
$Pass = 'root123456'
$Db   = 'power_load'

function Test-Running {
    [bool](Get-Process mysqld -ErrorAction SilentlyContinue)
}

function Test-CanConnect {
    # Connect for real instead of checking the port:
    # Get-NetTCPConnection can come up empty in some environments
    # even when the server is perfectly healthy.
    if (-not (Test-Path $Mysql)) { return $false }
    & $Mysql -u $User -h 127.0.0.1 ('-p' + $Pass) -e 'SELECT 1;' 2>&1 | Out-Null
    return ($LASTEXITCODE -eq 0)
}

function Wait-Ready {
    param([int]$TimeoutSec = 30)
    for ($i = 0; $i -lt $TimeoutSec; $i++) {
        Start-Sleep -Seconds 1
        if ((Test-Running) -and (Test-CanConnect)) { return $true }
    }
    return $false
}

function Show-Status {
    if (-not (Test-Running)) {
        Write-Host 'MySQL is NOT running' -ForegroundColor Yellow
        return
    }
    $p = Get-Process mysqld -ErrorAction SilentlyContinue
    if (Test-CanConnect) {
        Write-Host ('MySQL RUNNING  pid=' + ($p.Id -join ',') + '  port=' + $Port + '  connection OK') -ForegroundColor Green
    } else {
        Write-Host ('mysqld process alive (pid=' + ($p.Id -join ',') + ') but cannot connect on port ' + $Port) -ForegroundColor Yellow
    }
}

switch ($Action) {

    'status' { Show-Status }

    'start' {
        if (Test-Running) { Write-Host 'Already running'; Show-Status; break }
        if (-not (Test-Path $Mysqld)) { Write-Host ('mysqld not found: ' + $Mysqld) -ForegroundColor Red; break }
        Write-Host 'Starting MySQL...'
        # Pass arguments as an ARRAY. A single string containing quotes would
        # hand mysqld a literal '"--defaults-file=..."' and it exits silently.
        Start-Process -FilePath $Mysqld -ArgumentList @('--defaults-file=' + $MyIni) -WindowStyle Hidden
        if (Wait-Ready) {
            Show-Status
            Write-Host ('Connect with: mysql -u ' + $User + ' -h 127.0.0.1 -p' + $Pass)
        } else {
            Write-Host 'Start FAILED. Last lines of error log:' -ForegroundColor Red
            if (Test-Path $ErrLog) { Get-Content $ErrLog -Tail 20 }
        }
    }

    'stop' {
        if (-not (Test-Running)) { Write-Host 'Not running'; break }
        Write-Host 'Stopping MySQL...'
        & $Mysql -u $User -h 127.0.0.1 ('-p' + $Pass) -e 'SHUTDOWN;' 2>&1 | Out-Null
        Start-Sleep -Seconds 3
        if (Test-Running) { Get-Process mysqld -ErrorAction SilentlyContinue | Stop-Process -Force }
        Start-Sleep -Seconds 1
        Show-Status
    }

    'restart' {
        & $PSCommandPath stop
        Start-Sleep -Seconds 2
        & $PSCommandPath start
    }

    'cli' {
        if (-not (Test-Running)) { Write-Host 'MySQL is not running. Run: .\mysql.ps1 start' -ForegroundColor Red; break }
        Write-Host ('Entering database ' + $Db + ' - type exit to quit') -ForegroundColor Cyan
        & $Mysql -u $User -h 127.0.0.1 ('-p' + $Pass) $Db
    }

    'log' {
        if (Test-Path $ErrLog) { Get-Content $ErrLog -Tail 40 } else { Write-Host 'No error log yet' }
    }
}
