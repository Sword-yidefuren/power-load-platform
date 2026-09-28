# ============================================================
#  check-health.ps1 - one-shot health check for all services
# ============================================================
#  Run this before a demo: it tells you in one second whether
#  the project is ready to show.
#
#  Usage:
#     powershell -ExecutionPolicy Bypass -File check-health.ps1
#
#  MySQL is configured to auto-start at logon, so normally you do
#  not have to start it by hand. This script only REPORTS status;
#  it never starts anything for you.
#
#  NOTE: this file is intentionally ASCII-only.
#  Windows PowerShell 5.1 decodes a BOM-less file with the system
#  ANSI codepage (GBK on a Chinese Windows). Non-ASCII bytes then
#  break string/brace parsing with confusing "Unexpected token"
#  errors - which is exactly what happened the first time this
#  script was written with Chinese comments in it.
# ============================================================

$ErrorActionPreference = 'Continue'

$Workspace = Split-Path $PSScriptRoot -Parent
$Ok = 0
$Total = 3

Write-Host ''
Write-Host '=== power-load health check ===' -ForegroundColor Cyan
Write-Host ''

# ---------- 1. MySQL ----------
$mysqlOk = (Test-NetConnection -ComputerName 127.0.0.1 -Port 3306 -WarningAction SilentlyContinue).TcpTestSucceeded
if ($mysqlOk) {
    Write-Host '  [1/3] MySQL    (3306) : UP' -ForegroundColor Green
    $Ok++
} else {
    Write-Host '  [1/3] MySQL    (3306) : DOWN' -ForegroundColor Red
    Write-Host ('        fix: powershell -ExecutionPolicy Bypass -File "' + $Workspace + '\db\mysql.ps1" start')
}

# ---------- 2. backend ----------
$backendOk = $false
$r = $null
try {
    $r = Invoke-WebRequest -Uri 'http://127.0.0.1:8080/api/health' -UseBasicParsing -TimeoutSec 6
    if ($r.StatusCode -eq 200) { $backendOk = $true }
} catch { }

if ($backendOk) {
    Write-Host '  [2/3] Backend  (8080) : UP' -ForegroundColor Green
    $Ok++
    # Also report whether the backend can reach MySQL (it reports UP/DOWN itself)
    $dbStatus = 'unknown'
    if ($r.Content -match '"status":"([A-Za-z]+)"') { $dbStatus = $Matches[1] }
    if ($dbStatus -eq 'UP') {
        Write-Host '        database link  : OK' -ForegroundColor Green
    } else {
        Write-Host '        database link  : DOWN  <-- backend is up but cannot reach MySQL' -ForegroundColor Yellow
    }
} else {
    Write-Host '  [2/3] Backend  (8080) : DOWN' -ForegroundColor Red
    Write-Host ('        fix: powershell -ExecutionPolicy Bypass -File "' + $Workspace + '\_tools\run-backend.ps1"')
}

# ---------- 3. frontend ----------
$frontendOk = $false
try {
    $r2 = Invoke-WebRequest -Uri 'http://127.0.0.1:5173/' -UseBasicParsing -TimeoutSec 6
    if ($r2.StatusCode -eq 200) { $frontendOk = $true }
} catch { }

if ($frontendOk) {
    Write-Host '  [3/3] Frontend (5173) : UP' -ForegroundColor Green
    $Ok++
} else {
    Write-Host '  [3/3] Frontend (5173) : DOWN' -ForegroundColor Red
    Write-Host ('        fix: powershell -ExecutionPolicy Bypass -File "' + $Workspace + '\_tools\run-frontend.ps1"')
}

# ---------- forecast data (extra) ----------
Write-Host ''
$forecastOk = $false
try {
    $r3 = Invoke-WebRequest -Uri 'http://127.0.0.1:8080/api/forecast/overview' -UseBasicParsing -TimeoutSec 6
    if ($r3.Content -match '"totalPoints":(\d+)') {
        $pts = [int]$Matches[1]
        if ($pts -gt 0) {
            Write-Host ('  [extra] Forecast data : ' + $pts + ' points') -ForegroundColor Green
            $forecastOk = $true
        }
    }
} catch { }

if (-not $forecastOk) {
    Write-Host '  [extra] Forecast data : EMPTY (run the Python script first)' -ForegroundColor Yellow
    Write-Host ('        fix: python "' + $Workspace + '\power-load-platform\analytics\load_forecast.py"')
}

# ---------- summary ----------
Write-Host ''
Write-Host ('  ' + $Ok + '/' + $Total + ' services up') -ForegroundColor $(if ($Ok -eq $Total) { 'Green' } else { 'Yellow' })

if ($Ok -eq $Total) {
    Write-Host ''
    Write-Host '  READY. Open: http://127.0.0.1:5173' -ForegroundColor Green
} else {
    Write-Host ''
    Write-Host '  NOT READY - run the fix commands listed above.' -ForegroundColor Yellow
}
Write-Host ''
