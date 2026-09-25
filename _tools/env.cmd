@echo off
REM ============================================================
REM  env.cmd - 一键激活开发环境（只对当前这个 cmd 窗口生效）
REM
REM  用法：
REM    1) 双击本文件，或在 cmd 里执行 env.cmd
REM    2) 然后就能直接用 java / mvn / mysql
REM
REM  为什么需要它？
REM    环境变量装到了系统里，但要重开终端才生效。
REM    临时用这个脚本可以立刻生效，不用改系统设置。
REM ============================================================

set "JAVA_HOME=C:\devtools\jdk17\jdk-17.0.20.1+1"
set "MAVEN_HOME=C:\devtools\maven\apache-maven-3.9.11"
set "MYSQL_HOME=C:\devtools\mysql"
set "PATH=%JAVA_HOME%\bin;%MAVEN_HOME%\bin;%MYSQL_HOME%\bin;%PATH%"

echo.
echo   [env.cmd] 开发环境已激活:
echo     JAVA_HOME   = %JAVA_HOME%
echo     MAVEN_HOME  = %MAVEN_HOME%
echo     MYSQL_HOME  = %MYSQL_HOME%
echo.
echo   现在可以直接用: java -version / mvn -v / mysql -u root -p
echo.

cmd /k
