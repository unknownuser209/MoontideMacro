#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\Screen.ahk
; ---------------------------------------------------------------------------
; Roblox: find, focus and check the Roblox player window.
; Standard launcher only (RobloxPlayerBeta.exe). Coordinates are screen px.
;
; Roblox can be FULLSCREEN (exclusive or borderless: the client rect covers
; its whole monitor) or in a WINDOW (2026-11-14), at any resolution and
; Windows scale. Every coordinate is in 2560x1440 design space and Screen
; maps it to the client; ClientOk refreshes that mapping on each check.
; A window must be restored (not minimized), wholly on its monitor and at
; least MinW x MinH; FitWindow sizes it to the largest tested size that fits
; the monitor's work area (General.fitWindow, on by default, at every Start).
; ---------------------------------------------------------------------------

class Roblox {
    static Exe := "RobloxPlayerBeta.exe"
    static AllowWindowed := true     ; windows are supported (2026-11-14); kept for old callers
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
        why := Roblox.WindowProblem(x, y, w, h, m.x, m.y, m.w, m.h)
        if (why != "") {
            Roblox.Problem := why
            return "notfs"
        }
        Roblox.Problem := ""
        Roblox.Windowed := !Roblox.CoversMonitor(x, y, w, h, m.x, m.y, m.w, m.h)
        Screen.Refresh(hwnd)
        return "ok"
    }

    ; Pure: "" when a client rect can be used (fullscreen, or a window wholly
    ; on its monitor and at least MinW x MinH), else why not.
    static WindowProblem(x, y, w, h, mx, my, mw, mh) {
        if (w <= 0 || h <= 0)
            return "Roblox is minimized"
        if Roblox.CoversMonitor(x, y, w, h, mx, my, mw, mh)
            return ""
        if (w < Roblox.MinW || h < Roblox.MinH)
            return "the Roblox window is too small (" w "x" h "; at least " Roblox.MinW "x" Roblox.MinH ")"
        if (x < mx || y < my || x + w > mx + mw || y + h > my + mh)
            return "the Roblox window is partly off the screen"
        return ""
    }

    ; Pure: the largest tested client size (Screen.Tested) that fits in
    ; availW x availH -> {w, h}, or "" when none fits. Same area: the wider.
    static BestSize(availW, availH) {
        best := ""
        for t in Screen.Tested {
            p := StrSplit(t, "x"), w := Integer(p[1]), h := Integer(p[2])
            if (w > availW || h > availH)
                continue
            if (!IsObject(best) || w * h > best.w * best.h || (w * h = best.w * best.h && w > best.w))
                best := {w: w, h: h}
        }
        return best
    }

    ; A windowed (or maximized) Roblox whose client is not a tested size is
    ; restored and resized to BestSize of its monitor's work area (taskbar
    ; excluded, title bar and borders allowed for), centred there. Fullscreen
    ; and already-tested windows are left alone.
    ; -> "" (nothing to do) | "WxH" (resized to) | "nofit" (no tested size
    ; fits this monitor as a window: use fullscreen)
    static FitWindow() {
        hwnd := Roblox.Hwnd()
        if !hwnd
            return ""
        try {
            if DllCall("IsIconic", "Ptr", hwnd, "Int")
                WinRestore("ahk_id " hwnd)
            WinGetClientPos(&cx, &cy, &cw, &ch, "ahk_id " hwnd)
            m := Roblox._Monitor(hwnd)
            if (!IsObject(m) || Roblox.CoversMonitor(cx, cy, cw, ch, m.x, m.y, m.w, m.h))
                return ""
            maxed := WinGetMinMax("ahk_id " hwnd) = 1
            if (!maxed && Roblox._TestedSize(cw, ch) && !Roblox.WindowProblem(cx, cy, cw, ch, m.x, m.y, m.w, m.h))
                return ""
            if maxed {
                WinRestore("ahk_id " hwnd)
                Sleep(300)
            }
            wa := Roblox._WorkArea(hwnd)
            WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " hwnd)
            WinGetClientPos(&cx, &cy, &cw, &ch, "ahk_id " hwnd)
            fw := ww - cw, fh := wh - ch                 ; frame: borders + title bar
            best := Roblox.BestSize(wa.w - fw, wa.h - fh)
            if !IsObject(best)
                return "nofit"
            nx := wa.x + (wa.w - best.w - fw) // 2, ny := wa.y + (wa.h - best.h - fh) // 2
            WinMove(nx, ny, best.w + fw, best.h + fh, "ahk_id " hwnd)
            Sleep(400)
            WinGetClientPos(, , &cw, &ch, "ahk_id " hwnd)
            if (cw != best.w || ch != best.h) {          ; a DPI change on the move: once more
                WinGetPos(, , &ww, &wh, "ahk_id " hwnd)
                WinMove(, , ww + best.w - cw, wh + best.h - ch, "ahk_id " hwnd)
                Sleep(300)
            }
            return best.w "x" best.h
        }
        return ""
    }

    static _TestedSize(w, h) {
        for t in Screen.Tested
            if (t = w "x" h)
                return true
        return false
    }

    ; The window's monitor work area (no taskbar) {x, y, w, h} in screen px.
    static _WorkArea(hwnd) {
        hmon := DllCall("MonitorFromWindow", "Ptr", hwnd, "UInt", 2, "Ptr")
        mi := Buffer(40, 0), NumPut("UInt", 40, mi, 0)
        if !(hmon && DllCall("GetMonitorInfoW", "Ptr", hmon, "Ptr", mi, "Int"))
            return {x: 0, y: 0, w: A_ScreenWidth, h: A_ScreenHeight}
        l := NumGet(mi, 20, "Int"), t := NumGet(mi, 24, "Int")
        return {x: l, y: t, w: NumGet(mi, 28, "Int") - l, h: NumGet(mi, 32, "Int") - t}
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
