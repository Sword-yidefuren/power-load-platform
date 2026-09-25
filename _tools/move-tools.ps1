# ============================================================
#  move-tools.ps1  —  把工具链安装/迁移到纯英文路径 C:\devtools
# ============================================================
#  为什么需要这个脚本？
#    MySQL 的 mysqld.exe 在 Windows 上无法解析含中文的路径
#    （本机路径 C:\Users\Sword\Desktop\测试 中的"测试"会被吞掉，
#     导致 mysqld 找不到 errmsg.sys / datadir 而崩溃）。
#    所以 JDK / Maven / MySQL 必须放在纯英文路径下。
#
#  怎么用？
#    1) 右键"以管理员身份运行 PowerShell"其实**不需要**，普通权限即可
#       （只有注册系统服务才需要管理员，本脚本不注册服务）
#    2) 直接运行：
#         powershell -ExecutionPolicy Bypass -File move-tools.ps1
#    3) 运行完关闭终端重开，配置才会生效
#
#  前提：工作区 _cache 下已有 jdk17.zip / maven.zip / mysql.zip
# ============================================================

$ErrorActionPreference = 'Stop'

# 中文路径用 char code 拼出来，避免本脚本自身遇到编码问题
$Repo  = 'C:\Users\Sword\Desktop\' + [char]0x6D4B + [char]0x8BD5
$Cache = Join-Path $Repo '_cache'
$Dev   = 'C:\devtools'

Write-Host '=== 1/4 检查下载缓存 ===' -ForegroundColor Cyan
foreach ($z in @('jdk17.zip', 'maven.zip', 'mysql.zip')) {
    $f = Join-Path $Cache $z
    if (-not (Test-Path $f)) {
        throw "缺少 $f —— 请先下载好这三个 zip 再运行本脚本"
    }
    $mb = [math]::Round((Get-Item $f).Length / 1MB, 1)
    Write-Host ("  找到 {0}  ({1} MB)" -f $z, $mb)
}

New-Item -ItemType Directory -Path $Dev -Force | Out-Null
Add-Type -AssemblyName System.IO.Compression.FileSystem

function Expand-IfMissing {
    param([string]$Zip, [string]$Dest, [string]$Label)
    if (Test-Path $Dest) {
        Write-Host "  $Label 已存在，跳过"
        return
    }
    Write-Host "  解压 $Label ..."
    $tmp = "$Dest.tmp"
    if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
    [System.IO.Compression.ZipFile]::ExtractToDirectory($Zip, $tmp)
    Move-Item $tmp $Dest
}

function Expand-Flat {
    # MySQL 的 zip 有一个顶层同名目录，解压后把它"提"到 $Dest
    param([string]$Zip, [string]$Dest)
    if (Test-Path $Dest) { Write-Host '  MySQL 已存在，跳过'; return }
    Write-Host '  解压 MySQL ...'
    $tmp = "$Dest.tmp"
    if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
    [System.IO.Compression.ZipFile]::ExtractToDirectory($Zip, $tmp)
    $inner = Get-ChildItem $tmp -Directory | Select-Object -First 1
    Move-Item $inner.FullName $Dest
    Remove-Item $tmp -Recurse -Force
}

Write-Host '=== 2/4 解压到 C:\devtools ===' -ForegroundColor Cyan
Expand-IfMissing -Zip (Join-Path $Cache 'jdk17.zip') -Dest (Join-Path $Dev 'jdk17') -Label 'JDK 17'
Expand-IfMissing -Zip (Join-Path $Cache 'maven.zip') -Dest (Join-Path $Dev 'maven') -Label 'Maven'
Expand-Flat      -Zip (Join-Path $Cache 'mysql.zip') -Dest (Join-Path $Dev 'mysql')

Write-Host '=== 3/4 定位真实路径（zip 内有版本号目录）===' -ForegroundColor Cyan
$JdkHome = (Get-ChildItem (Join-Path $Dev 'jdk17') -Directory | Select-Object -First 1).FullName
$MvnHome = (Get-ChildItem (Join-Path $Dev 'maven') -Directory | Select-Object -First 1).FullName
Write-Host "  JAVA_HOME = $JdkHome"
Write-Host "  MAVEN_HOME = $MvnHome"

Write-Host '=== 4/4 写入环境变量（用户级，无需管理员）===' -ForegroundColor Cyan
[Environment]::SetEnvironmentVariable('JAVA_HOME',  $JdkHome, 'User')
[Environment]::SetEnvironmentVariable('MAVEN_HOME', $MvnHome, 'User')

# 把 JAVA_HOME\bin 和 maven\bin 追加进用户级 PATH（已存在则不重复加）
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$add = @("$JdkHome\bin", "$MvnHome\bin")
$parts = $userPath -split ';' | Where-Object { $_ -ne '' }
foreach ($a in $add) {
    if ($parts -notcontains $a) { $parts += $a; Write-Host "  PATH += $a" }
    else { Write-Host "  PATH 已含 $a" }
}
[Environment]::SetEnvironmentVariable('Path', ($parts -join ';'), 'User')

# Maven 镜像配置：加速国内依赖下载
$M2 = Join-Path $env:USERPROFILE '.m2'
New-Item -ItemType Directory -Path $M2 -Force | Out-Null
$settings = Join-Path $M2 'settings.xml'
if (Test-Path $settings) {
    Copy-Item $settings "$settings.bak" -Force
    Write-Host "  已备份原 settings.xml -> settings.xml.bak"
}
$xml = @'
<?xml version="1.0" encoding="UTF-8"?>
<settings xmlns="http://maven.apache.org/SETTINGS/1.0.0">
  <localRepository>C:\devtools\maven-repo</localRepository>
  <mirrors>
    <mirror>
      <id>aliyun-public</id>
      <name>Aliyun Public</name>
      <url>https://maven.aliyun.com/repository/public</url>
      <mirrorOf>central</mirrorOf>
    </mirror>
  </mirrors>
</settings>
'@
[System.IO.File]::WriteAllText($settings, $xml, (New-Object System.Text.UTF8Encoding $false))
Write-Host "  已写入 $settings"

Write-Host ''
Write-Host '=== 完成 ===' -ForegroundColor Green
Write-Host '请关闭并重新打开终端 / IDEA，然后验证：'
Write-Host '    java -version     # 应显示 17.0.20.1'
Write-Host '    mvn -v            # 应显示 Apache Maven 3.9.11 + Java 17'
Write-Host '    javac -version    # 应显示 17.0.20.1'
