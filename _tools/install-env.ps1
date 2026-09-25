# ============================================================
#  install-env.ps1
#  Configure JAVA_HOME / MAVEN_HOME / PATH for the dev toolchain.
#  User-level only. Does NOT need administrator rights.
#
#  Usage:
#     powershell -ExecutionPolicy Bypass -File install-env.ps1
#
#  Then CLOSE this window and open a NEW one, and check:
#     java -version
#     mvn -v
#
#  What it changes:
#     JAVA_HOME  -> C:\devtools\jdk17\jdk-17.0.20.1+1
#     MAVEN_HOME -> C:\devtools\maven\apache-maven-3.9.11
#     PATH       -> adds the \bin of both (prepended, so JDK 17 wins
#                   over the older JDK 8 that is still installed)
#
#  To undo: remove those two PATH entries and delete JAVA_HOME/MAVEN_HOME.
#           Your original JDK 8 is not touched.
#
#  NOTE: This file is intentionally ASCII-only.
#  Windows PowerShell 5.1 reads BOM-less files using the system ANSI
#  codepage (GBK on Chinese Windows). Non-ASCII text would be decoded
#  wrongly, which can even break string parsing. ASCII avoids that.
# ============================================================

$ErrorActionPreference = 'Stop'

$JdkHome = 'C:\devtools\jdk17\jdk-17.0.20.1+1'
$MvnHome = 'C:\devtools\maven\apache-maven-3.9.11'

Write-Host ''
Write-Host '=== Step 1/4 : check the tools exist ===' -ForegroundColor Cyan
if (-not (Test-Path (Join-Path $JdkHome 'bin\java.exe'))) { throw "NOT FOUND: $JdkHome\bin\java.exe" }
if (-not (Test-Path (Join-Path $MvnHome 'bin\mvn.cmd')))  { throw "NOT FOUND: $MvnHome\bin\mvn.cmd" }
Write-Host '  JDK and Maven found.'

Write-Host ''
Write-Host '=== Step 2/4 : back up current values ===' -ForegroundColor Cyan
$oldJava = [Environment]::GetEnvironmentVariable('JAVA_HOME', 'User')
$oldPath = [Environment]::GetEnvironmentVariable('Path', 'User')
Write-Host ('  old JAVA_HOME : ' + $oldJava)
Write-Host ('  old PATH len  : ' + $oldPath.Length)
if ($null -eq $oldPath) { $oldPath = '' }

$backup = Join-Path $PSScriptRoot 'env-backup.txt'
@(
    'JAVA_HOME(User)=' + $oldJava
    'PATH(User)=' + $oldPath
) | Set-Content -Path $backup -Encoding UTF8
Write-Host ('  backup written: ' + $backup)

Write-Host ''
Write-Host '=== Step 3/4 : write new values ===' -ForegroundColor Cyan
[Environment]::SetEnvironmentVariable('JAVA_HOME',  $JdkHome, 'User')
[Environment]::SetEnvironmentVariable('MAVEN_HOME', $MvnHome, 'User')
Write-Host ('  JAVA_HOME  = ' + $JdkHome)
Write-Host ('  MAVEN_HOME = ' + $MvnHome)

# Put the new bin folders at the FRONT of PATH so JDK 17 is found
# before the older JDK 8 that is still on the machine.
$parts = $oldPath -split ';' | Where-Object { $_ -ne '' }
$wanted = @( (Join-Path $JdkHome 'bin'), (Join-Path $MvnHome 'bin') )

# drop any previous copies of these entries first
$parts = $parts | Where-Object { $wanted -notcontains $_ }

$newPath = (($wanted + $parts) -join ';')
[Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
Write-Host '  PATH updated (new entries placed first).'

Write-Host ''
Write-Host '=== Step 4/4 : done ===' -ForegroundColor Green
Write-Host ''
Write-Host 'NOW DO THIS:' -ForegroundColor Yellow
Write-Host '  1) CLOSE this PowerShell window completely'
Write-Host '  2) Open a NEW PowerShell window'
Write-Host '  3) Run these two commands and check the output:'
Write-Host ''
Write-Host '       java -version     <- expect 17.0.20.1'
Write-Host '       mvn -v            <- expect Java version: 17'
Write-Host ''
Write-Host 'Your old JDK 8 is still installed and untouched.' -ForegroundColor DarkGray
