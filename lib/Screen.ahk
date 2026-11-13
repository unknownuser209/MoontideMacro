#Requires AutoHotkey v2.0
; ---------------------------------------------------------------------------
; Screen: the one mapper from DESIGN space (2560x1440, the size every
; coordinate in the code, data\calibration.json and tests\screens is in) to
; the Roblox client rect in physical screen px, and back. Roblox must be
; fullscreen (Roblox.ClientOk), so the client rect is its monitor: origin 0,0
; on the primary monitor, the monitor's origin on another one.
;
; Rule (a hypothesis about Sol's RNG's UI until checked live at each size):
;   s  = min(ch / 1440, cw / 2560)   scale; by HEIGHT for 16:9 and wider
;                                    (Roblox's FOV is vertical), by width for
;                                    narrower (16:10, 5:4) so nothing maps
;                                    off the client
;   a 2560*s x 1440*s design box sits in the client: centred ("C"), or pinned
;   to the left / right edge ("L" / "R", HUD that hugs a window edge on an
;   ultrawide) and top / bottom ("T" / "B", only differs on 16:10 / 5:4).
;   An anchor is a string of those letters ("C", "R", "BR"); default "C".
;
; At a 2560x1440 client at 0,0 (Screen.IsIdentity()) every function returns
; its input UNCHANGED (no rounding), so that size behaves bit for bit as
; before the mapper existed.
;
;   Screen.SetClient(x, y, w, h)  the client rect in screen px (tests, and
;                                 Roblox.ClientOk after each window check)
;   Screen.Reset()                back to 2560x1440 at 0,0 (identity)
;   Screen.X(px, anchor) / Screen.Y(py, anchor)   design -> screen px
;   Screen.Pt(x, y, anchor) -> {x, y}
;   Screen.Rect(r, anchor) / Screen.Rect(x, y, w, h, anchor) -> {x, y, w, h}
;                                 (other own props of r are copied: scale..)
;   Screen.Size(w, h) -> {w, h}   lengths only (no origin)
;   Screen.Len(px)                one length (strides, thresholds)
;   Screen.Inv(sx, sy, anchor) -> {x, y}   screen -> design (calibration)
;   Screen.InvRect(r, anchor) -> {x, y, w, h}
;   Screen.OcrScale(scale)        upscale to apply to SCREEN px so the OCR
;                                 image is as big as the design read was
;   Screen.Refresh(hwnd)          SetClient from the window's client rect
;   Screen.InitDpi()              per-monitor DPI awareness (call first)
;   Screen.Describe()             one line for the log
; ---------------------------------------------------------------------------

class Screen {
    static DesignW := 2560
    static DesignH := 1440
    static cx := 0
    static cy := 0
    static cw := 2560
    static ch := 1440
    static s := 1                ; min(sx, sy): lengths, OCR upscale
    ; Sol's RNG sizes its UI by the client's width AND height separately:
    ; live 1440x900 (2026-11-11) the Fishing Shop was W/2560 wide and H/1440
    ; tall, the left menu and Roll at H/1440 heights. So x maps by sx, y by
    ; sy (the same number at 16:9); no letterbox box. Anchors are kept in
    ; the signatures for old callers but no longer move anything.
    static sx := 1
    static sy := 1
    ; Not every panel stretches (live 1440x900, 2026-11-11): the Aura
    ; Storage and the inventory scale evenly by min(sx, sy), centred ("C");
    ; the quest panel scales evenly too, centred up / down but on the right
    ; edge ("RH"; its Claim button measured at 1137..1261 x 640..672); the
    ; Fishing Shop, Flarg's dialog and the rest stretch ("S"). The code that
    ; works such a panel sets the mode around it (WithMode); at 16:9 all
    ; three give the same pixel.
    static Mode := "S"
    ; A design point of a panel drawn under mode `from` -> the design point
    ; that lands on the same pixel under mode `to` (a stretched button used
    ; inside a WithMode block of another panel). -> {x, y}
    static Convert(pt, from, to) {
        if (Screen.IsIdentity() || from = to)
            return {x: pt.x, y: pt.y}
        old := Screen.Mode
        try {
            Screen.Mode := from
            sx := Screen.X(pt.x), sy := Screen.Y(pt.y)
            Screen.Mode := to
            return Screen.Inv(sx, sy)
        } finally
            Screen.Mode := old
    }

    static WithMode(mode, fn) {
        old := Screen.Mode
        Screen.Mode := mode
        try
            return fn()
        finally
            Screen.Mode := old
    }
    static dpi := 0              ; the Roblox window's DPI at the last Refresh (0 = unknown)
    static dpiSet := ""          ; how InitDpi made the thread aware ("" = not called)

    static SetClient(x, y, w, h) {
        Screen.cx := Integer(x), Screen.cy := Integer(y)
        Screen.cw := Max(1, Integer(w)), Screen.ch := Max(1, Integer(h))
        Screen.sx := Screen.IsIdentity() ? 1 : Screen.cw / Screen.DesignW
        Screen.sy := Screen.IsIdentity() ? 1 : Screen.ch / Screen.DesignH
        Screen.s := Min(Screen.sx, Screen.sy)
    }

    static Reset() => Screen.SetClient(0, 0, Screen.DesignW, Screen.DesignH)

    static IsIdentity() => (Screen.cx = 0 && Screen.cy = 0 && Screen.cw = Screen.DesignW && Screen.ch = Screen.DesignH)

    ; Sizes checked in game (live, windowed at that client size, 2026-11-11):
    ; fishing, sell, aura swaps, quests, the chat moved out of the way
    static Tested := ["2560x1440", "1920x1080", "1920x1200", "1680x1050", "1600x900"
        , "1536x864", "1440x900", "1366x768", "1280x800", "1280x720"]
    static Verified() {
        k := Screen.cw "x" Screen.ch
        for t in Screen.Tested
            if (t = k)
                return true
        return false
    }
    static TestedText() {
        s := ""
        for t in Screen.Tested
            s .= (s = "" ? "" : ", ") t
        return s
    }
    static NotTestedNote := "not tested at this size yet (tested: see the README); it may still work"


    ; design box origin (the client's: the UI stretches to it)
    static _Ox(anchor) => Screen.cx
    static _Oy(anchor) => Screen.cy

    static X(px, anchor := "C") {
        if Screen.IsIdentity()
            return px
        switch Screen.Mode {
            case "C": return Round(Screen.cx + (Screen.cw - Screen.DesignW * Screen.s) / 2 + px * Screen.s)
            case "RH": return Round(Screen.cx + Screen.cw - (Screen.DesignW - px) * Screen.s)
        }
        return Round(Screen.cx + px * Screen.sx)
    }
    static Y(py, anchor := "C") {
        if Screen.IsIdentity()
            return py
        if (Screen.Mode = "C" || Screen.Mode = "RH")
            return Round(Screen.cy + (Screen.ch - Screen.DesignH * Screen.s) / 2 + py * Screen.s)
        return Round(Screen.cy + py * Screen.sy)
    }

    static Pt(x, y, anchor := "C") => {x: Screen.X(x, anchor), y: Screen.Y(y, anchor)}

    ; Rect(r [, anchor]) or Rect(x, y, w, h [, anchor]). Edges are mapped, so
    ; neighbouring rects stay neighbours; w, h are at least 1.
    static Rect(a, b := "C", c := "", d := "", anchor := "C") {
        r := ""
        if IsObject(a) {
            r := a, anchor := b
            x := r.x, y := r.y, w := r.w, h := r.h
        } else
            x := a, y := b, w := c, h := d
        if Screen.IsIdentity()
            out := {x: x, y: y, w: w, h: h}
        else {
            x1 := Screen.X(x, anchor), y1 := Screen.Y(y, anchor)
            out := {x: x1, y: y1, w: Max(1, Screen.X(x + w, anchor) - x1), h: Max(1, Screen.Y(y + h, anchor) - y1)}
        }
        if IsObject(r)
            for k, v in r.OwnProps()
                if !(k = "x" || k = "y" || k = "w" || k = "h")
                    out.%k% := v
        return out
    }

    static Len(px) => Screen.IsIdentity() ? px : Round(px * Screen.s)
    static Size(w, h) => {w: Screen.IsIdentity() ? w : Max(1, Round(w * Screen.s)), h: Screen.IsIdentity() ? h : Max(1, Round(h * Screen.s))}

    static Inv(sx, sy, anchor := "C") {
        if Screen.IsIdentity()
            return {x: sx, y: sy}
        switch Screen.Mode {
            case "C":
                return {x: Round((sx - Screen.cx - (Screen.cw - Screen.DesignW * Screen.s) / 2) / Screen.s)
                    , y: Round((sy - Screen.cy - (Screen.ch - Screen.DesignH * Screen.s) / 2) / Screen.s)}
            case "RH":
                return {x: Round(Screen.DesignW - (Screen.cx + Screen.cw - sx) / Screen.s)
                    , y: Round((sy - Screen.cy - (Screen.ch - Screen.DesignH * Screen.s) / 2) / Screen.s)}
        }
        return {x: Round((sx - Screen.cx) / Screen.sx), y: Round((sy - Screen.cy) / Screen.sy)}
    }

    static InvRect(r, anchor := "C") {
        if Screen.IsIdentity()
            return {x: r.x, y: r.y, w: r.w, h: r.h}
        p := Screen.Inv(r.x, r.y, anchor), q := Screen.Inv(r.x + r.w, r.y + r.h, anchor)
        return {x: p.x, y: p.y, w: Max(1, q.x - p.x), h: Max(1, q.y - p.y)}
    }

    ; An OCR read asked for `scale` x design px, as a stretch of SCREEN px:
    ; scale / s (a float; above the asked scale on a smaller client, below it
    ; on 4K), so the recognizer gets the image size the design read had.
    ; Measured on scaled real frames (tests\test_resample.ahk) against whole
    ; factors (floor, round, at least 2): this rule missed the fewest reads
    ; (2 of 24 over 1080p / 768p / 4K; whole factors 5). OCR on one box
    ; flips between neighbouring factors, so no rule reads everything.
    static OcrScale(scale) => (Screen.IsIdentity() || Screen.s = 1) ? scale : scale / Screen.s

    ; Client rect of hwnd in screen px -> SetClient. false (nothing changed)
    ; when the window is gone or has no client area (minimized).
    static Refresh(hwnd) {
        if !hwnd
            return false
        try WinGetClientPos(&x, &y, &w, &h, "ahk_id " hwnd)
        catch
            return false
        if (w < 1 || h < 1)
            return false
        Screen.SetClient(x, y, w, h)
        try Screen.dpi := DllCall("GetDpiForWindow", "Ptr", hwnd, "UInt")
        return true
    }

    ; Per-monitor DPI awareness (v2) for this thread, before any coordinate or
    ; capture call: without it Windows at 125 / 150 % hands a non-aware
    ; script virtualised (scaled-down) coordinates and pixels. -> how it was
    ; set: "pmv2" | "pm" (older Windows) | "already" | "failed".
    static InitDpi() {
        r := "failed"
        try {
            if DllCall("SetThreadDpiAwarenessContext", "Ptr", -4, "Ptr")
                r := "pmv2"
        }
        if (r = "failed") {
            try {
                hr := DllCall("shcore\SetProcessDpiAwareness", "Int", 2, "Int")
                r := (hr = 0) ? "pm" : (hr = -2147024891) ? "already" : "failed"     ; E_ACCESSDENIED: set before (manifest)
            }
        }
        Screen.dpiSet := r
        return r
    }

    ; Windows HDR on any active display? -> 1 | 0 | "" (unknown). Diagnostic
    ; only: with HDR on, screen captures of the game can come back in other
    ; colours (a friend's PC, 2026-11-11: the reel's white border read 133).
    ; QueryDisplayConfig + DisplayConfigGetDeviceInfo: Windows 11 24H2+
    ; GET_ADVANCED_COLOR_INFO_2 (type 15, 36 bytes, activeColorMode 2 = HDR;
    ; its older "advanced colour" bit is also set by colour management
    ; without HDR), else GET_ADVANCED_COLOR_INFO (type 9, 32 bytes, bit 1).
    ; Path info 72 bytes, mode info 64.
    static HdrOn() {
        try {
            if DllCall("GetDisplayConfigBufferSizes", "UInt", 2, "UInt*", &np := 0, "UInt*", &nm := 0, "Int")
                return ""
            paths := Buffer(np * 72, 0), modes := Buffer(nm * 64, 0)
            if DllCall("QueryDisplayConfig", "UInt", 2, "UInt*", &np, "Ptr", paths, "UInt*", &nm, "Ptr", modes, "Ptr", 0, "Int")
                return ""
            seen := false
            Loop np {
                p := paths.Ptr + (A_Index - 1) * 72
                for t in [[15, 36], [9, 32]] {
                    pk := Buffer(t[2], 0)
                    NumPut("UInt", t[1], pk, 0), NumPut("UInt", t[2], pk, 4)
                    NumPut("UInt", NumGet(p, 20, "UInt"), pk, 8), NumPut("Int", NumGet(p, 24, "Int"), pk, 12)
                    NumPut("UInt", NumGet(p, 28, "UInt"), pk, 16)
                    if DllCall("DisplayConfigGetDeviceInfo", "Ptr", pk, "Int")
                        continue
                    seen := true
                    if (t[1] = 15 ? NumGet(pk, 32, "UInt") = 2 : NumGet(pk, 20, "UInt") & 2)
                        return 1
                    break
                }
            }
            return seen ? 0 : ""
        }
        return ""
    }

    static HdrText() {
        h := Screen.HdrOn()
        return h = 1 ? "HDR on" : h = 0 ? "HDR off" : "HDR unknown"
    }

    ; 0 unaware, 1 system, 2 per monitor, -1 unknown
    static Awareness() {
        try return DllCall("GetAwarenessFromDpiAwarenessContext", "Ptr", DllCall("GetThreadDpiAwarenessContext", "Ptr"), "Int")
        return -1
    }

    ; Windows display scale in percent of the monitor at x,y (100 when unknown)
    static ScaleAt(x := 0, y := 0) {
        try {
            hmon := DllCall("MonitorFromPoint", "Int64", (y << 32) | (x & 0xFFFFFFFF), "UInt", 1, "Ptr")
            if !DllCall("shcore\GetDpiForMonitor", "Ptr", hmon, "Int", 0, "UInt*", &dx := 0, "UInt*", &dy := 0)
                return Round(dx * 100 / 96)
        }
        return 100
    }

    static SizeText() => Screen.cw "x" Screen.ch (Screen.IsIdentity() ? "" : " (x" RTrim(RTrim(Format("{:.3f}", Screen.s), "0"), ".") ")")

    static Describe() {
        aw := Map(0, "unaware", 1, "system aware", 2, "per-monitor aware")
        a := Screen.Awareness()
        dpiTxt := Screen.dpi ? Screen.dpi " dpi (" Round(Screen.dpi * 100 / 96) "%)" : "dpi unknown"
        box := Screen.IsIdentity() ? "identity" : (Abs(Screen.sx - Screen.sy) < 0.002
            ? Format("x{:.4f}", Screen.s) : Format("x{:.4f} wide, x{:.4f} high", Screen.sx, Screen.sy))
        return "Roblox client " Screen.cw "x" Screen.ch " at " Screen.cx "," Screen.cy ", " dpiTxt
            . ", mapping " box ", macro " (aw.Has(a) ? aw[a] : "awareness unknown")
            . (Screen.Verified() ? "" : "; " Screen.NotTestedNote)
    }
}
