#Requires AutoHotkey v2.0
; ---------------------------------------------------------------------------
; Proc: run a helper program (hidden) and wait for it WITH A TIME CAP.
;
;   r := Proc.RunCapped(cmd, dir := "", capMs := 120000)
;       -> {code, timedOut, ms}
;       code      the program's exit code ("" when it was stopped)
;       timedOut  true when it ran past capMs: it is killed (TerminateProcess)
;       ms        how long it ran
;       Throws when the program cannot be started (not found, ...).
;
; Why: RunWait has no time cap. A PowerShell that never returned on one
; player's PC left "Making the zip..." up for 20+ minutes (2026-11-26); an
; update that waits on such a PowerShell would hang the same way. While it
; waits the GUI, timers and hotkeys keep running (Sleep between checks).
; ---------------------------------------------------------------------------

class Proc {
    static PollMs := 50

    static RunCapped(cmd, dir := "", capMs := 120000) {
        x64 := A_PtrSize = 8
        si := Buffer(x64 ? 104 : 68, 0)                 ; STARTUPINFOW
        NumPut("UInt", si.Size, si, 0)
        NumPut("UInt", 0x1, si, x64 ? 60 : 44)         ; dwFlags = STARTF_USESHOWWINDOW
        NumPut("UShort", 0, si, x64 ? 64 : 48)         ; wShowWindow = SW_HIDE
        pi := Buffer(x64 ? 24 : 16, 0)                  ; PROCESS_INFORMATION
        line := Buffer(StrPut(cmd, "UTF-16") * 2, 0)   ; CreateProcessW may write to it
        StrPut(cmd, line, "UTF-16")
        ok := DllCall("CreateProcessW", "Ptr", 0, "Ptr", line, "Ptr", 0, "Ptr", 0, "Int", 0
            , "UInt", 0x08000000                         ; CREATE_NO_WINDOW
            , "Ptr", 0, "Ptr", dir = "" ? 0 : StrPtr(dir), "Ptr", si, "Ptr", pi, "Int")
        if !ok
            throw Error("cannot start " RegExReplace(RegExReplace(Trim(cmd), '^"?([^" ]*).*$', "$1"), "^.*\\")
                . " (" Trim(OSError(A_LastError).Message, " `r`n") ")", -1)
        hProc := NumGet(pi, 0, "Ptr")
        DllCall("CloseHandle", "Ptr", NumGet(pi, A_PtrSize, "Ptr"))     ; the thread handle
        t0 := A_TickCount
        try {
            ; WAIT_OBJECT_0 = 0: ended
            while (DllCall("WaitForSingleObject", "Ptr", hProc, "UInt", 0, "UInt") != 0) {
                if (A_TickCount - t0 >= capMs) {
                    DllCall("TerminateProcess", "Ptr", hProc, "UInt", 1)
                    DllCall("WaitForSingleObject", "Ptr", hProc, "UInt", 2000, "UInt")
                    return {code: "", timedOut: true, ms: A_TickCount - t0}
                }
                Sleep(Proc.PollMs)
            }
            code := 0
            DllCall("GetExitCodeProcess", "Ptr", hProc, "UInt*", &code)
            return {code: code, timedOut: false, ms: A_TickCount - t0}
        } finally {
            DllCall("CloseHandle", "Ptr", hProc)
        }
    }
}
