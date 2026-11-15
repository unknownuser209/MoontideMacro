#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\Screen.ahk
; ---------------------------------------------------------------------------
; Roblox: find, focus and check the Roblox player window.
; Standard launcher only (RobloxPlayerBeta.exe). Coordinates are screen px.
;
; Roblox is FULLSCREEN (exclusive or borderless: the client rect covers its
; whole monitor) or, with Windowed set to Yes (General.windowed=1, Setup >
; Calibrate, 2026-11-14), in a WINDOW, at any resolution and Windows scale.
; Every coordinate is in 2560x1440 design space and Screen maps it to the
; client; ClientOk refreshes that mapping on each check. A window must be
; restored (not minimized), wholly on its monitor and at least MinW x MinH.
; The macro never moves or resizes the window: the player sizes it.
; ---------------------------------------------------------------------------

class Roblox {
    static Exe := "RobloxPlayerBeta.exe"
    static AllowWindowed := false    ; General.windowed=1 (Windowed: Yes): a window is used as it is
    static Windowed := false         ; the last OK check found a window (not fullscreen)
    static Problem := ""             ; why the last check was "notfs" (one short sentence)
    static MinW := 800
    static MinH := 450

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

    ; "ok" (fullscreen or a usable window; Screen now maps to its client) |
    ; "missing" | "notfs" (minimized, too small or partly off its monitor:
    ; Roblox.Problem says which).
    static ClientOk() {
        hwnd := Roblox.Hwnd()
        if !hwnd
            return "missing"
        try {
            if DllCall("IsIconic", "Ptr", hwnd, "Int") {
                Roblox.Problem := "Roblox is minimized"
                return "notfs"
            }
            WinGetClientPos(&x, &y, &w, &h, "ahk_id " hwnd)
            m := Roblox._Monitor(hwnd)
        } catch
            return "missing"
        if !IsObject(m)
            m := {x: x, y: y, w: w, h: h}
        why := Roblox.WindowProblem(x, y, w, h, m.x, m.y, m.w, m.h, Roblox.AllowWindowed)
        if (why != "") {
            Roblox.Problem := why
            return "notfs"
        }
        Roblox.Problem := ""
        Roblox.Windowed := !Roblox.CoversMonitor(x, y, w, h, m.x, m.y, m.w, m.h)
        Screen.Refresh(hwnd)
        return "ok"
    }

    ; Pure: "" when a client rect can be used (fullscreen, or with windowed
    ; on a window wholly on its monitor and at least MinW x MinH), else why not.
    static WindowProblem(x, y, w, h, mx, my, mw, mh, windowed := true) {
        if (w <= 0 || h <= 0)
            return "Roblox is minimized"
        if Roblox.CoversMonitor(x, y, w, h, mx, my, mw, mh)
            return ""
        if !windowed
            return "Roblox is in a window and Windowed is set to No (press F11 in Roblox, or set Windowed to Yes in Setup > Calibrate)"
        if (w < Roblox.MinW || h < Roblox.MinH)
            return "the Roblox window is too small (" w "x" h "; at least " Roblox.MinW "x" Roblox.MinH ")"
        if (x < mx || y < my || x + w > mx + mw || y + h > my + mh)
            return "the Roblox window is partly off the screen"
        return ""
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
