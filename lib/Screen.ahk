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
    static s := 1
    static dpi := 0              ; the Roblox window's DPI at the last Refresh (0 = unknown)
    static dpiSet := ""          ; how InitDpi made the thread aware ("" = not called)

    static SetClient(x, y, w, h) {
        Screen.cx := Integer(x), Screen.cy := Integer(y)
        Screen.cw := Max(1, Integer(w)), Screen.ch := Max(1, Integer(h))
        Screen.s := Screen.IsIdentity() ? 1 : Min(Screen.ch / Screen.DesignH, Screen.cw / Screen.DesignW)
    }

    static Reset() => Screen.SetClient(0, 0, Screen.DesignW, Screen.DesignH)

    static IsIdentity() => (Screen.cx = 0 && Screen.cy = 0 && Screen.cw = Screen.DesignW && Screen.ch = Screen.DesignH)

    ; true at the one size checked in game so far
    static Verified() => (Screen.cw = Screen.DesignW && Screen.ch = Screen.DesignH)

    ; design box origin for an anchor
    static _Ox(anchor) {
        bw := Screen.DesignW * Screen.s
        return InStr(anchor, "L") ? Screen.cx : InStr(anchor, "R") ? Screen.cx + Screen.cw - bw : Screen.cx + (Screen.cw - bw) / 2
    }
    static _Oy(anchor) {
        bh := Screen.DesignH * Screen.s
        return InStr(anchor, "T") ? Screen.cy : InStr(anchor, "B") ? Screen.cy + Screen.ch - bh : Screen.cy + (Screen.ch - bh) / 2
    }

    static X(px, anchor := "C") => Screen.IsIdentity() ? px : Round(Screen._Ox(anchor) + px * Screen.s)
    static Y(py, anchor := "C") => Screen.IsIdentity() ? py : Round(Screen._Oy(anchor) + py * Screen.s)

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
        return {x: Round((sx - Screen._Ox(anchor)) / Screen.s), y: Round((sy - Screen._Oy(anchor)) / Screen.s)}
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
        box := Screen.IsIdentity() ? "identity" : Format("x{:.4f}, design box {}x{} at {},{}", Screen.s
            , Round(Screen.DesignW * Screen.s), Round(Screen.DesignH * Screen.s), Round(Screen._Ox("C")), Round(Screen._Oy("C")))
        return "Roblox client " Screen.cw "x" Screen.ch " at " Screen.cx "," Screen.cy ", " dpiTxt
            . ", mapping " box ", macro " (aw.Has(a) ? aw[a] : "awareness unknown")
            . (Screen.Verified() ? "" : "; only 2560x1440 is verified so far")
    }
}
