#Requires AutoHotkey v2.0
; ---------------------------------------------------------------------------
; Roblox: find, focus and check the Roblox player window.
; Standard launcher only (RobloxPlayerBeta.exe). Coordinates are screen px.
; ---------------------------------------------------------------------------

class Roblox {
    static Exe := "RobloxPlayerBeta.exe"
    static TargetW := 2560
    static TargetH := 1440

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

    ; True when the client area is exactly 2560x1440 at screen 0,0
    ; (exclusive or borderless fullscreen on the primary 1440p monitor).
    static IsFullscreen1440() {
        hwnd := Roblox.Hwnd()
        if !hwnd
            return false
        try {
            WinGetClientPos(&x, &y, &w, &h, "ahk_id " hwnd)
        } catch {
            return false
        }
        return Roblox.RectIs1440(x, y, w, h)
    }

    ; Pure check, split out for tests.
    static RectIs1440(x, y, w, h) {
        return (x = 0 && y = 0 && w = Roblox.TargetW && h = Roblox.TargetH)
    }
}
