# MySQL 8.0 green install: init data dir, start, set root password.
# ASCII-only on purpose so any PowerShell codepage can parse it.
# Idempotent: safe to re-run; rewrites my.ini and validates it every time.
# Usage:
#   .\mysql-init.ps1            # init (if needed) + start + set password
#   .\mysql-init.ps1 -Start     # start only
#   .\mysql-init.ps1 -Stop      # stop
#   .\mysql-init.ps1 -Status    # status
#   .\mysql-init.ps1 -Reset     # wipe data dir and re-init from scratch
param(
    [switch]$Start,
    [switch]$Stop,
    [switch]$Status,
    [switch]$Reset
)

$ErrorActionPreference = 'Stop'
$Root      = 'C:\Users\Sword\Desktop\' + [char]0x6D4B + [char]0x8BD5
$MySQLHome = Join-Path $Root '_tools\mysql-8.0.44-winx64'
$DataDir   = Join-Path $Root 'mysql-data'
$MyIni     = Join-Path $Root 'my.ini'
$LogDir    = Join-Path $Root 'mysql-logs'
$MavenRepo = Join-Path $Root 'maven-repo'
$Port      = 3306
$RootPwd   = 'root123456'

$Mysqld = Join-Path $MySQLHome 'bin\mysqld.exe'
$Mysql  = Join-Path $MySQLHome 'bin\mysql.exe'

function Get-MySqlProc { Get-Process mysqld -ErrorAction SilentlyContinue }

function Show-Status {
    $p = Get-MySqlProc
    if ($p) { Write-Output ('MySQL RUNNING pid=' + ($p.Id -join ',') + ' port=' + $Port) }
    else    { Write-Output 'MySQL STOPPED' }
}

function Stop-Db {
    $p = Get-MySqlProc
    if (-not $p) { return }
    Write-Output ('Stopping MySQL pid=' + ($p.Id -join ','))
    if (Test-Path $Mysql) { & $Mysql -u root ('-p' + $RootPwd) -e 'SHUTDOWN;' 2>&1 | Out-Null }
    Start-Sleep -Seconds 4
    $p = Get-MySqlProc
    if ($p) { $p | Stop-Process -Force }
    Start-Sleep -Seconds 2
}

function Start-Db {
    if (Get-MySqlProc) { return }
    Start-Process -FilePath $Mysqld -ArgumentList ('--defaults-file="' + $MyIni + '"') -WindowStyle Hidden
    for ($i = 0; $i -lt 20; $i++) {
        Start-Sleep -Seconds 1
        if (Get-MySqlProc) { Start-Sleep -Seconds 2; return }
    }
}

# Build my.ini as an array of lines: avoids every backslash/escaping pitfall.
function Write-MyIni {
    $b = $MySQLHome -replace '\\', '/'
    $d = $DataDir   -replace '\\', '/'
    $e = (Join-Path $LogDir 'error.log') -replace '\\', '/'
    $t = (Join-Path $DataDir 'tmp')      -replace '\\', '/'
    $lines = @(
        '[mysqld]'
        'basedir=' + $b
        'datadir=' + $d
        'port=' + $Port
        'character-set-server=utf8mb4'
        'collation-server=utf8mb4_unicode_ci'
        'default-storage-engine=INNODB'
        'max_connections=200'
        'log-error=' + $e
        'tmpdir=' + $t
        'skip-name-resolve'
        ''
        '[client]'
        'port=' + $Port
        'default-character-set=utf8mb4'
        ''
        '[mysql]'
        'default-character-set=utf8mb4'
    )
    # UTF-8 without BOM: mysqld chokes on a BOM on line 1
    [System.IO.File]::WriteAllText($MyIni, ($lines -join "`r`n"), (New-Object System.Text.UTF8Encoding $false))
}

# ---------------- Stop ----------------
if ($Stop) { Stop-Db; Write-Output 'Stopped'; exit 0 }

# ---------------- Status ----------------
if ($Status) { Show-Status; exit 0 }

# ---------------- Reset ----------------
if ($Reset) {
    Stop-Db
    Remove-Item $DataDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-Output 'data dir wiped'
}

# ---------------- Start only ----------------
if ($Start) {
    if (Get-MySqlProc) { Write-Output 'Already running'; Show-Status; exit 0 }
    Write-Output 'Starting MySQL...'
    Start-Db
    Show-Status
    if (-not (Get-MySqlProc)) { Write-Output ('!! failed, check ' + (Join-Path $LogDir 'error.log')) }
    exit 0
}

# ---------------- Init / ensure running ----------------
Write-Output '=== 1/5 check files ==='
if (-not (Test-Path $Mysqld)) { throw ('mysqld.exe not found: ' + $Mysqld) }
New-Item -ItemType Directory -Path $LogDir    -Force | Out-Null
New-Item -ItemType Directory -Path $MavenRepo -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $DataDir 'tmp') -Force | Out-Null
Write-Output ('mysqld: ' + $Mysqld)

Write-Output '=== 2/5 write my.ini ==='
Write-MyIni
Write-Output ('written: ' + $MyIni)

Write-Output '=== 3/5 validate my.ini ==='
& $Mysqld ('--defaults-file=' + $MyIni) --validate-config 2>&1 | Write-Output
if ($LASTEXITCODE -ne 0) { throw 'my.ini validation failed (see output above)' }
Write-Output 'config OK'

if (Test-Path (Join-Path $DataDir 'mysql')) {
    Write-Output '=== 4/5 data dir already initialized, skip ==='
} else {
    Write-Output '=== 4/5 initialize data dir (10-40s) ==='
    & $Mysqld ('--defaults-file=' + $MyIni) --initialize-insecure --console 2>&1 | Write-Output
    if (-not (Test-Path (Join-Path $DataDir 'mysql'))) {
        throw ('init failed, check ' + (Join-Path $LogDir 'error.log'))
    }
    Write-Output 'data dir initialized'
}

Write-Output '=== 5/5 start and set password ==='
Start-Db
if (-not (Get-MySqlProc)) { throw ('start failed, check ' + (Join-Path $LogDir 'error.log')) }
Show-Status

# root has no password right after --initialize-insecure; set it now.
& $Mysql -u root --skip-password -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '$RootPwd'; FLUSH PRIVILEGES;" 2>&1 | Write-Output

Write-Output ''
Write-Output '=== verify connection ==='
& $Mysql -u root ('-p' + $RootPwd) -e 'SELECT VERSION() AS mysql_version;' 2>&1 | Write-Output

Write-Output ''
Write-Output ('DSN: host=127.0.0.1 port=' + $Port + ' user=root password=' + $RootPwd)
