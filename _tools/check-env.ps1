# ============================================================
#  check-env.ps1
#  Verify that java / mvn / mysql are all ready to use.
#  Safe to run any time. Changes nothing.
#
#  Usage:
#     powershell -ExecutionPolicy Bypass -File check-env.ps1
#
#  NOTE: ASCII-only on purpose (see install-env.ps1 header).
# ============================================================

$JdkHome   = 'C:\devtools\jdk17\jdk-17.0.20.1+1'
$MvnHome   = 'C:\devtools\maven\apache-maven-3.9.11'
$MySqlHome = 'C:\devtools\mysql'

# Work out the workspace folder from this script's own location
# (this file lives in <workspace>\_tools), so the folder can be
# renamed freely without editing this script.
$Workspace = Split-Path $PSScriptRoot -Parent
$MysqlPs1  = Join-Path $Workspace 'db\mysql.ps1'

function Show-Item {
    param([string]$Name, [bool]$Ok, [string]$Detail)
    if ($Ok) {
        Write-Host ('  [OK]   ' + $Name.PadRight(10) + $Detail) -ForegroundColor Green
    } else {
        Write-Host ('  [FAIL] ' + $Name.PadRight(10) + $Detail) -ForegroundColor Red
    }
}

Write-Host ''
Write-Host '=========== 1. Files on disk ===========' -ForegroundColor Cyan
Show-Item 'JDK'   (Test-Path (Join-Path $JdkHome 'bin\java.exe'))   $JdkHome
Show-Item 'Maven' (Test-Path (Join-Path $MvnHome 'bin\mvn.cmd'))    $MvnHome
Show-Item 'MySQL' (Test-Path (Join-Path $MySqlHome 'bin\mysqld.exe')) $MySqlHome

Write-Host ''
Write-Host '=========== 2. Environment variables ===========' -ForegroundColor Cyan
$jh = [Environment]::GetEnvironmentVariable('JAVA_HOME', 'User')
$jhOk = ($jh -eq $JdkHome)
Show-Item 'JAVA_HOME' $jhOk ('= ' + $jh)

$pathHasJdk = ([Environment]::GetEnvironmentVariable('Path','User')) -like '*devtools*'
Show-Item 'PATH' $pathHasJdk 'contains devtools entries (User level)'

Write-Host ''
Write-Host '=========== 3. Commands in THIS window ===========' -ForegroundColor Cyan
Write-Host '  (If these fail right after install-env.ps1, just close and'
Write-Host '   reopen the window. A new window is required.)'
Write-Host ''

$javaCmd = Get-Command java -ErrorAction SilentlyContinue
if ($javaCmd) {
    $v = (& java -version 2>&1 | Select-Object -First 1)
    $is17 = ($v -match '17\.')
    Show-Item 'java' $is17 $v
} else {
    Show-Item 'java' $false 'command not found in this window'
}

$mvnCmd = Get-Command mvn -ErrorAction SilentlyContinue
if ($mvnCmd) {
    $Line = (& mvn -v 2>&1 | Select-String -Pattern 'Java version' | Select-Object -First 1)
    Show-Item 'mvn' $true ($Line -replace '\s+', ' ')
} else {
    Show-Item 'mvn' $false 'command not found in this window'
}

Write-Host ''
Write-Host '=========== 4. MySQL server ===========' -ForegroundColor Cyan
$proc = Get-Process mysqld -ErrorAction SilentlyContinue
if ($proc) {
    Show-Item 'mysqld' $true ('running, pid=' + ($proc.Id -join ','))
    $client = Join-Path $MySqlHome 'bin\mysql.exe'
    & $client -u root -h 127.0.0.1 -proot123456 -e 'SELECT VERSION();' 2>&1 | Out-Null
    Show-Item 'connect' ($LASTEXITCODE -eq 0) 'root@127.0.0.1 can log in'
} else {
    Show-Item 'mysqld' $false ('NOT running. Start it: ' + $MysqlPs1 + ' start')
}

Write-Host ''
Write-Host '======================================' -ForegroundColor Cyan
Write-Host 'All [OK] = environment is ready.'
Write-Host 'Any [FAIL] = send me that line and I will help.' -ForegroundColor Yellow
Write-Host ''
