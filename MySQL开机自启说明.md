# MySQL 开机自启说明

> 目的：**面试当天重启电脑后，MySQL 自动起来，不会因为忘记手动启动而演示翻车。**
> 安装时间：2026-09-25　状态：已安装并验证（"已在运行"分支）

---

## 一、回答你最关心的问题：自启会占 CPU 吗？

**不会。实测数据（你这台机器）：**

```
pid=10356  CPU累计=6.62秒   常驻内存=402.9MB
pid=12172  CPU累计=0.06秒   常驻内存=27.7MB
```

这颗 mysqld 跑了 **40 多分钟，总共只用了 6.62 秒 CPU 时间**，平均占用约 **0.2%**。

**为什么这么省？** 数据库是**事件驱动**的：没人查询时它阻塞在网络等待上"睡觉"，不消耗 CPU。
只有接口真的来查数据时它才醒过来干活。你可以在任务管理器里自己看 —— `mysqld.exe`
那一行的 CPU 基本**一直是 00**。

**真正的代价是内存：约 400MB（常驻）。**

| 组成 | 大小 | 说明 |
| --- | --- | --- |
| InnoDB 缓冲池 | 128MB | 数据缓存，固定大小，不会越用越多 |
| 进程/连接池/后台线程 | 约 270MB | MySQL 自身的固定开销 |

**建议：接受这 400MB，不要去调小参数。** 随便一个浏览器或 VS Code 都占 500MB 以上，
而这 400MB 换来的是"面试当天不用手动启动"的稳定性 —— 这笔账很划算。

---

## 二、它是怎么实现的

```
登录 Windows
   │
   ▼
启动文件夹里的 start-power-load-db.vbs        ← 唯一需要放进系统目录的文件
   │  用 WScript.Shell.Run + 窗口样式 0 静默启动（完全不闪黑窗口）
   ▼
工作区 _tools\startup-db.ps1                  ← 真正的逻辑在这里
   │  1. mysqld 在跑？ → 记一行日志，退出
   │  2. 没在跑？      → 静默启动 + 最多等 40 秒直到能连上
   ▼
mysql-logs\autostart.log                      ← 每次结果都记在这里
```

**为什么用 VBS 而不是 .cmd？**
`.cmd` 放进启动文件夹**一定会闪一下黑色控制台窗口**；VBS 的 `Run(cmd, 0, False)`
可以做到**完全无窗口**。

**为什么启动脚本放 `_tools` 而不是直接塞进启动文件夹？**
`startup-db.ps1` 用 `$PSScriptRoot` 自己定位工作区，所以**工作区改名后它依然能用**。
启动文件夹里只留一个"发射器"，它只需要知道工作区在哪。

---

## 三、涉及的文件

| 文件 | 位置 | 作用 |
| --- | --- | --- |
| `start-power-load-db.vbs` | 启动文件夹 | 发射器，静默调起下面的脚本 |
| `startup-db.ps1` | 工作区 `_tools\` | 真正的启动 + 等待 + 记日志逻辑 |
| `install-autostart.ps1` | 工作区 `_tools\` | 安装 / 卸载自启 |
| `autostart.log` | 工作区 `mysql-logs\` | 每次自启的结果 |
| `vbs-launcher.log` | 工作区 `mysql-logs\` | 发射器是否被触发过 |

启动文件夹的完整路径：
```
C:\Users\Sword\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup
```

---

## 四、常用操作

**查看自启日志（排查"为什么开机后 MySQL 没起来"）：**
```powershell
Get-Content C:\Users\Sword\Desktop\test\mysql-logs\autostart.log
Get-Content C:\Users\Sword\Desktop\test\mysql-logs\vbs-launcher.log
```

**立刻手动触发一次自启（不用重启电脑就能测）：**
```powershell
$s = [Environment]::GetFolderPath('Startup')
& cscript.exe //nologo "$s\start-power-load-db.vbs"
Start-Sleep 6
Get-Content C:\Users\Sword\Desktop\test\mysql-logs\autostart.log
```

**临时取消自启：**
```powershell
powershell -ExecutionPolicy Bypass -File C:\Users\Sword\Desktop\test\_tools\install-autostart.ps1 -Uninstall
```

**重新安装（比如工作区被改名或移动了）：**
```powershell
powershell -ExecutionPolicy Bypass -File C:\Users\Sword\Desktop\test\_tools\install-autostart.ps1
```
安装脚本会**自动把工作区路径改写进发射器**，所以改名后重跑一次就能修好。

**想改成开机后手动启动（回到原来的方式）：**
```powershell
cd C:\Users\Sword\Desktop\test\db
.\mysql.ps1 start
```

---

## 五、踩过的两个坑（值得记住）

### 坑 1：VBScript 的 `..` 和 PowerShell 不一样

第一版发射器想用相对路径从启动文件夹"往回找"工作区：

```vbscript
toolsDir = fso.GetAbsolutePathName(here & "\..\_tools")
```

结果算出来是 `...\Start Menu\Programs\_tools`，**而不是 `<工作区>\_tools`** ——
VBScript 的 `GetAbsolutePathName` 把 `..\_tools` 理解成"退一层并**替换掉最后一段**"。

**教训：`..` 的解析规则不跨语言通用，跨目录的脚本一律写绝对路径。**

### 坑 2：无 BOM 的 UTF-8 脚本，中文注释会让 VBS 编译失败

第一版 `.vbs` 里写了中文注释，运行直接报：

```
Microsoft VBScript 编译器错误: 无效字符
```

**原因**：VBScript 和 PowerShell 5.1 一样，**读无 BOM 的文件时按系统 ANSI 代码页解码**
（中文 Windows 就是 GBK）。中文注释的字节被当 GBK 解释后就变成非法字符，
**整个脚本连第一行都跑不到**。

**已被迫形成的规则（对所有 Windows 脚本引擎适用）：**

| 文件类型 | 规则 |
| --- | --- |
| `.ps1` / `.vbs` / `.cmd` | **一律纯 ASCII 英文**，中文说明放到 `.md` 里 |
| `.java` | 无 BOM 的 UTF-8 可以（javac 默认按 UTF-8 读），但**不能用 `Set-Content -Encoding UTF8`**（PS 5.1 会加 BOM，javac 报"非法字符 '\ufeff'"） |
| `.md` | 随便写中文 |

**验证某个脚本文件是否真的纯 ASCII（可以随时自查）：**

```powershell
$p = 'C:\Users\Sword\Desktop\test\_tools\startup-db.ps1'
$b = [System.IO.File]::ReadAllBytes($p)
$bad = 0; foreach ($x in $b) { if ($x -gt 127) { $bad++ } }
Write-Host "non-ASCII bytes: $bad  (0 = 安全)"
```

---

## 六、还没验证的部分（重要）

**已验证：** "MySQL 已经在跑 → 什么都不做" 这条分支（手动触发过，日志正确）。

**未验证：** "电脑刚开机 → MySQL 没在跑 → 自动启动" 这条分支。

**因为验证它必须重启电脑。** 请你找个方便的时候重启一次，然后在**登录进桌面后 30 秒内**跑：

```powershell
powershell -ExecutionPolicy Bypass -File C:\Users\Sword\Desktop\test\db\mysql.ps1 status
```

**期望看到：**
```
MySQL RUNNING  pid=xxxxx  port=3306  connection OK
```

如果显示 `MySQL is NOT running`，把这两份日志贴给我：
```
mysql-logs\autostart.log
mysql-logs\vbs-launcher.log
```

> 提示：重启后**后端不会自动启动**（只有 MySQL 自启）。后端是你演示时手动开的 ——
> 这是故意的，因为你可能需要看启动日志。
