# Extract JDK 17 and Maven into _tools directory
# NOTE: keep this file ASCII-only so any PowerShell encoding can parse it.
$ErrorActionPreference = 'Stop'
$Root  = 'C:\Users\Sword\Desktop\' + [char]0x6D4B + [char]0x8BD5
$Cache = Join-Path $Root '_cache'
$Tools = Join-Path $Root '_tools'

function Expand-ZipFast {
    param([string]$Zip, [string]$Dest)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $tmp = "$Dest.tmp"
    if (Test-Path $tmp)  { Remove-Item $tmp  -Recurse -Force }
    if (Test-Path $Dest) { Remove-Item $Dest -Recurse -Force }
    [System.IO.Compression.ZipFile]::ExtractToDirectory($Zip, $tmp)
    Move-Item $tmp $Dest
}

Write-Output '=== Extract JDK 17 ==='
$jdkDest = Join-Path $Tools 'jdk17'
if (Test-Path $jdkDest) {
    Write-Output 'already exists, skip'
} else {
    Expand-ZipFast -Zip (Join-Path $Cache 'jdk17.zip') -Dest $jdkDest
    Write-Output 'JDK extracted'
}

Write-Output '=== Extract Maven ==='
$mvnDest = Join-Path $Tools 'maven'
if (Test-Path $mvnDest) {
    Write-Output 'already exists, skip'
} else {
    Expand-ZipFast -Zip (Join-Path $Cache 'maven.zip') -Dest $mvnDest
    Write-Output 'Maven extracted'
}

Write-Output '=== Verify ==='
$javaExe = Get-ChildItem $jdkDest -Recurse -Filter 'java.exe' -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -match '\\bin\\java\.exe$' } | Select-Object -First 1
if ($javaExe) { Write-Output ('java.exe -> ' + $javaExe.FullName) } else { Write-Output '!! java.exe not found' }

$mvnCmd = Get-ChildItem $mvnDest -Recurse -Filter 'mvn.cmd' -ErrorAction SilentlyContinue | Select-Object -First 1
if ($mvnCmd) { Write-Output ('mvn.cmd  -> ' + $mvnCmd.FullName) } else { Write-Output '!! mvn.cmd not found' }
