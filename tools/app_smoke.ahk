#Requires AutoHotkey v2.0
#SingleInstance Off
; ---------------------------------------------------------------------------
; App smoke + memory harness (dev only).
;
;   AutoHotkey64.exe tools\app_smoke.ahk [hidden|offscreen] [holdMs]
;
; Copies Vesper.ahk, lib\, data\*.json (never settings.ini or
; potion_usage.json) and assets\ to A_Temp\vesper_app_smoke, then runs the
; COPY:  Vesper.ahk /harness <mode> <holdMs>
; The app boots fully (UI, Calibrate.Use, Clip.Setup, PotionSafety, OnExit)
; with a fresh default settings.ini (no webhooks, dryRun=1), prints its
; memory and exits by itself. It never starts the scheduler, installs no
; hotkeys and never touches the Roblox window. "offscreen" shows the
; dashboard + overlay right of the virtual desktop with NoActivate, then
; minimizes the dashboard with SW_SHOWMINNOACTIVE (focus never moves).
; Prints the child's stdout/stderr; exit 0 only on "VESPER EXIT OK".
; ---------------------------------------------------------------------------

Out(s) => FileAppend(s "`n", "*")

mode := A_Args.Length ? A_Args[1] : "hidden"
holdMs := A_Args.Length > 1 ? Integer(A_Args[2]) : 1000
root := RegExReplace(A_LineFile, "\\tools\\[^\\]+$", "")
dst := A_Temp "\vesper_app_smoke"
try DirDelete(dst, true)
DirCreate(dst "\data")
FileCopy(root "\Vesper.ahk", dst "\Vesper.ahk")
DirCopy(root "\lib", dst "\lib")
DirCopy(root "\assets", dst "\assets")
Loop Files, root "\data\*.json" {
    if (A_LoopFileName != "potion_usage.json")
        FileCopy(A_LoopFilePath, dst "\data\" A_LoopFileName)
}

cmd := '"' A_AhkPath '" /ErrorStdOut "' dst '\Vesper.ahk" /harness ' mode ' ' holdMs
shell := ComObject("WScript.Shell")
ex := shell.Exec(cmd)
deadline := A_TickCount + holdMs + 30000
while (ex.Status = 0 && A_TickCount < deadline)
    Sleep(100)
timedOut := (ex.Status = 0)
if timedOut
    ex.Terminate()
so := ex.StdOut.ReadAll()
se := ex.StdErr.ReadAll()
Out(RTrim(so, "`r`n"))
if (se != "")
    Out("STDERR " RTrim(se, "`r`n"))
ok := !timedOut && InStr(so, "VESPER EXIT OK") && !InStr(so, "ERROR ")
Out(timedOut ? "SMOKE FAIL (timeout)" : ok ? "SMOKE PASS exit=" ex.ExitCode : "SMOKE FAIL exit=" ex.ExitCode)
try DirDelete(dst, true)
ExitApp(ok ? 0 : 1)
