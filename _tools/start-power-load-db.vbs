' ============================================================
'  start-power-load-db.vbs   (installed in the Startup folder)
' ============================================================
'  Runs at every Windows logon and makes sure MySQL is up.
'
'  Why VBScript instead of a .cmd?
'     WScript.Shell.Run with window style 0 launches a process
'     COMPLETELY hidden - no black console window flashes on screen.
'     A .cmd in the Startup folder always flashes a console briefly.
'
'  Why is the workspace path written out in full below?
'     The first version tried to walk up from the Startup folder with
'     "..\_tools". That failed: VBScript's GetAbsolutePathName treats
'     "..\_tools" as "go up one level and REPLACE the last segment",
'     giving ...\Programs\_tools instead of <workspace>\_tools.
'     Relative-path rules differ between languages, so this launcher
'     simply states the absolute path. The real logic still lives in
'     _tools\startup-db.ps1, which locates the workspace by itself.
'
'  NOTE: THIS FILE MUST STAY PURE ASCII.
'     VBScript decodes a BOM-less file with the system ANSI codepage
'     (GBK on a Chinese Windows). Non-ASCII bytes then become invalid
'     characters and the script fails to compile with
'     "Invalid character" before a single line runs.
'     Keep all comments in English here.
'
'  IF YOU MOVE THE WORKSPACE to a different folder, edit WORKSPACE below,
'  or just re-run _tools\install-autostart.ps1 which rewrites it for you.
' ============================================================

Option Explicit

Dim fso, shell, workspace, ps1, cmd, logFile, lf, marker

Set fso = CreateObject("Scripting.FileSystemObject")
Set shell = CreateObject("WScript.Shell")

' >>> EDIT THIS ONE LINE if the workspace folder is ever moved <<<
workspace = "C:\Users\Sword\Desktop\test"

ps1 = workspace & "\_tools\startup-db.ps1"
logFile = workspace & "\mysql-logs\vbs-launcher.log"
marker = workspace & "\mysql-logs\vbs-launcher-FAILED.txt"

' If the workspace is gone there is nowhere to log and nothing to do.
If Not fso.FolderExists(workspace) Then
    WScript.Quit 2
End If

' Make sure the log folder exists
If Not fso.FolderExists(workspace & "\mysql-logs") Then
    On Error Resume Next
    fso.CreateFolder(workspace & "\mysql-logs")
    On Error GoTo 0
End If

' Timestamp WITHOUT the Now() function on purpose:
'   Now() renders using the system locale, which on a Chinese Windows
'   contains non-ASCII characters - and this file must stay ASCII-only.
'   DateDiff against a fixed epoch gives a locale-independent number.
Dim epochSeconds
epochSeconds = DateDiff("s", "1970-01-01 00:00:00", Now())

Set lf = fso.OpenTextFile(logFile, 8, True)
lf.WriteLine "epoch=" & epochSeconds & " vbs launcher triggered"

If Not fso.FileExists(ps1) Then
    lf.WriteLine "epoch=" & epochSeconds & " FAILED: script not found at " & ps1
    lf.Close
    Set lf = fso.OpenTextFile(marker, 8, True)
    lf.WriteLine "startup-db.ps1 not found at: " & ps1
    lf.Close
    WScript.Quit 1
End If

lf.WriteLine "epoch=" & epochSeconds & " handing over to " & ps1
lf.Close

cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & ps1 & """"

' 0 = hidden window, False = do not wait for PowerShell to finish
shell.Run cmd, 0, False

WScript.Quit 0
