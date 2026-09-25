# ============================================================
#  run-frontend.ps1 - start the Vue3 dev server
# ============================================================
#  Usage (from anywhere):
#     powershell -ExecutionPolicy Bypass -File C:\Users\Sword\Desktop\test\_tools\run-frontend.ps1
#
#  Before the first run you must install dependencies once:
#     cd C:\Users\Sword\Desktop\test\power-load-platform\frontend
#     npm install
#
#  Press Ctrl+C in this window to stop the dev server.
#
#  NOTE: this file is intentionally ASCII-only.
#  Windows PowerShell 5.1 decodes BOM-less files as GBK, which corrupts
#  non-ASCII text and can even break string parsing. ASCII avoids that.
# ============================================================

$ErrorActionPreference = 'Stop'

# Locate the workspace from this script's own position (this file is in
# <workspace>\_tools), so renaming the workspace folder never breaks it.
$Workspace = Split-Path $PSScriptRoot -Parent
$Frontend  = Join-Path $Workspace 'power-load-platform\frontend'

Write-Host ''
Write-Host '=== power-load frontend (Vue3 + Vite) ===' -ForegroundColor Cyan
Write-Host ('  workspace : ' + $Workspace)
Write-Host ('  frontend  : ' + $Frontend)
Write-Host ''

if (-not (Test-Path $Frontend)) {
    Write-Host ('MISSING frontend folder: ' + $Frontend) -ForegroundColor Red
    exit 1
}

# Dependencies live in node_modules; without them Vite cannot run at all.
if (-not (Test-Path (Join-Path $Frontend 'node_modules'))) {
    Write-Host 'node_modules not found - dependencies are not installed yet.' -ForegroundColor Yellow
    Write-Host 'Run this once first:'
    Write-Host ''
    Write-Host ('  cd ' + $Frontend)
    Write-Host '  npm install'
    Write-Host ''
    exit 1
}

try {
    $nodeVersion = (& node -v)
} catch {
    Write-Host 'node not found on PATH. Install Node.js first.' -ForegroundColor Red
    exit 1
}

Write-Host ('  node      : ' + $nodeVersion)
Write-Host ''
Write-Host 'Starting Vite dev server...' -ForegroundColor Yellow
Write-Host '  frontend : http://127.0.0.1:5173'
Write-Host '  backend  : http://127.0.0.1:8080  (must be running separately!)'
Write-Host ''
Write-Host '  API calls are proxied: /api/* -> http://127.0.0.1:8080/api/*'
Write-Host ''

Set-Location $Frontend

# --host 127.0.0.1 keeps it on localhost only (no firewall prompt)
& npm run dev -- --host 127.0.0.1
