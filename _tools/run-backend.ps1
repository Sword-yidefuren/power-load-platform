# ============================================================
#  run-backend.ps1 - start the Spring Boot backend
# ============================================================
#  Usage (from anywhere):
#     powershell -ExecutionPolicy Bypass -File C:\Users\Sword\Desktop\test\_tools\run-backend.ps1
#
#  What it does:
#     1. pins JAVA_HOME to JDK 17 (your machine also has an old JDK 8)
#     2. points Maven at the offline repo inside the workspace
#     3. runs spring-boot:run
#
#  Press Ctrl+C in this window to stop the server.
#
#  NOTE: this file is intentionally ASCII-only.
#  Windows PowerShell 5.1 decodes BOM-less files as GBK, which corrupts
#  non-ASCII text and can even break string parsing. ASCII avoids that.
# ============================================================

$ErrorActionPreference = 'Stop'

# Locate the workspace from this script's own position (this file is in
# <workspace>\_tools), so renaming the workspace folder never breaks it.
$Workspace = Split-Path $PSScriptRoot -Parent
$Backend   = Join-Path $Workspace 'power-load-platform\backend'
$Settings  = Join-Path $Workspace '_tools\settings.xml'

$env:JAVA_HOME   = 'C:\devtools\jdk17\jdk-17.0.20.1+1'
$env:MAVEN_HOME  = 'C:\devtools\maven\apache-maven-3.9.11'
$Mvn = Join-Path $env:MAVEN_HOME 'bin\mvn.cmd'

Write-Host ''
Write-Host '=== power-load backend ===' -ForegroundColor Cyan
Write-Host ('  workspace : ' + $Workspace)
Write-Host ('  JAVA_HOME : ' + $env:JAVA_HOME)
Write-Host ''

foreach ($p in @($Mvn, (Join-Path $Backend 'pom.xml'), $Settings)) {
    if (-not (Test-Path $p)) {
        Write-Host ('MISSING: ' + $p) -ForegroundColor Red
        exit 1
    }
}

Write-Host 'Starting... (first run may take ~20s, Ctrl+C to stop)' -ForegroundColor Yellow
Write-Host ('  health check: http://127.0.0.1:8080/api/health')
Write-Host ''

Set-Location $Backend

# -o = offline (use only the local repo; works without internet)
# -s = use our settings.xml (aliyun mirror + workspace repo path)
& $Mvn -o -s $Settings spring-boot:run
