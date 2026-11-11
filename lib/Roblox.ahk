#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\Screen.ahk
; ---------------------------------------------------------------------------
; Roblox: find, focus and check the Roblox player window.
; Standard launcher only (RobloxPlayerBeta.exe). Coordinates are screen px.
;
; The macro needs Roblox FULLSCREEN (exclusive or borderless: the client
; rect covers its whole monitor) at any resolution and Windows scale. Every
; coordinate is in 2560x1440 design space and Screen maps it to the client;
; ClientOk refreshes that mapping on each check. Only 2560x1440 is verified
; in game so far.
; ---------------------------------------------------------------------------

class Roblox {
    static Exe := "RobloxPlayerBeta.exe"
    static AllowWindowed := false    ; General.allowWindowed=1 (testing only): a window counts as fullscreen

    ; -> hwnd (Integer) or 0 when Roblox is not running.
    static Hwnd() {
        return WinExist("ahk_exe " Roblox.Exe)
    }

    ; Activates the Roblox window. -> true if it is active afterwards.
    static Focus(timeoutSec := 2) {
        hwnd := Roblox.Hwnd()
        if !hwnd
            return false
        if WinActive("ahk_id " hwnd)
            return true
        try {
            WinActivate("ahk_id " hwnd)
            return WinWaitActive("ahk_id " hwnd, , timeoutSec) ? true : false
        } catch {
            return false
        }
    }

    ; "ok" (fullscreen; Screen now maps to its client) | "missing" |
    ; "notfs" (windowed or minimized: the macro does not support those).
    static ClientOk() {
        hwnd := Roblox.Hwnd()
        if !hwnd
            return "missing"
        try {
            if DllCall("IsIconic", "Ptr", hwnd, "Int")
                return "notfs"
            WinGetClientPos(&x, &y, &w, &h, "ahk_id " hwnd)
            m := Roblox._Monitor(hwnd)
        } catch
            return "missing"
        if !(IsObject(m) && Roblox.CoversMonitor(x, y, w, h, m.x, m.y, m.w, m.h)) && !(Roblox.AllowWindowed && w > 0 && h > 0)
            return "notfs"
        Screen.Refresh(hwnd)
        return "ok"
    }

    ; Pure: client rect == monitor rect (and not empty). Split out for tests.
    static CoversMonitor(x, y, w, h, mx, my, mw, mh) {
        return (w > 0 && h > 0 && x = mx && y = my && w = mw && h = mh)
    }

    ; The window's monitor rect {x, y, w, h} (screen px) or "".
    static _Monitor(hwnd) {
        hmon := DllCall("MonitorFromWindow", "Ptr", hwnd, "UInt", 2, "Ptr")     ; NEAREST
        mi := Buffer(40, 0), NumPut("UInt", 40, mi, 0)
        if !(hmon && DllCall("GetMonitorInfoW", "Ptr", hmon, "Ptr", mi, "Int"))
            return ""
        l := NumGet(mi, 4, "Int"), t := NumGet(mi, 8, "Int")
        return {x: l, y: t, w: NumGet(mi, 12, "Int") - l, h: NumGet(mi, 16, "Int") - t}
    }

    ; "1920x1080 (x0.75)" of the last OK check (Screen's client)
    static SizeText() => Screen.SizeText()
    static Verified() => Screen.Verified()
    static Describe() => Screen.Describe()
}
