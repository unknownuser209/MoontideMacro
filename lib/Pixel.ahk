#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\Screen.ahk
; ---------------------------------------------------------------------------
; Pixel: single-point color checks with per-channel tolerance.
; DESIGN coordinates (2560x1440): Get / Is / WaitFor / Signature / Grab map
; them to the Roblox client through Screen (unchanged at 2560x1440). Colors are 0xRRGGBB (Integer) or "0xRRGGBB" /
; "#RRGGBB" / "RRGGBB" strings. Tolerance: every channel |a-b| <= tol.
; No PixelSearch / ImageSearch (spec: single-point checks only; the rect
; signature below compares one fixed calibrated rect, it never searches).
;
; Pixel._getter is the color source, (x, y) -> color. Tests swap it for a
; fake; production uses Pixel._ScreenColor (PixelGetColor, CoordMode Screen).
;
; RECT SIGNATURE (amount box "1" check, Task 12b). Not a search: one fixed,
; calibrated rect is compared with what it looked like at calibration.
;   Pixel.Signature(x, y, w, h, cols := 16, rows := 6, thr := 170) -> String
;     "s1:<cols>x<rows>:<thr>:<cells>"; cells = one digit 0..9 per grid cell
;     (row-major) = round(9 * bright / pixels in the cell), bright = pixel
;     luminance (0.299R + 0.587G + 0.114B) >= thr. Bright text on the dark,
;     translucent box survives a changing world behind it; the world's
;     colors do not count unless they are brighter than thr.
;   Pixel.SigLike(stored, x, y, w, h)  live signature with the stored one's
;     grid + threshold ("" if stored is malformed)
;   Pixel.SigParse(s) -> {cols, rows, thr, cells: Array} | ""
;   Pixel.SigInk(s)   -> sum of cells (-1 if malformed)
;   Pixel.SigValid(s, minInk := 3) well-formed and has bright content
;   Pixel.SigMatch(live, stored, tol := 2) both well-formed, same grid and
;     threshold, every cell within tol. Anything else -> false.
;   Pixel.SigMaxDiff(a, b) / Pixel.SigL1(a, b)  largest / summed cell
;     difference (-1 if malformed or different grid)
;   Pixel.SigCloser(live, target, other, tol, sumTol, margin)  SigMatch to
;     target AND L1(live, target) <= sumTol AND L1(live, other) -
;     L1(live, target) >= margin ("1" vs "empty" box, 12b fix 1)
; Pixel._grabber is the rect source, (x, y, w, h) -> Array of w*h colors
; 0xRRGGBB row-major (one BitBlt); off 2560x1440 Pixel.Grab calls it as
; (sx, sy, sw, sh, dw, dh) -> dw*dh colors (screen rect stretched to the
; design size). Tests swap it.
; ---------------------------------------------------------------------------

class Pixel {
    static _getter := (x, y) => Pixel._ScreenColor(x, y)
    ; dw, dh: off 2560x1440 Grab passes the design size to stretch to. The
    ; 4-parameter form threw there (swallowed by callers): every rect read
    ; came back empty below 1440p, so no aura result tile ever "showed" at
    ; 1920x1080 (live 2026-11-10)
    static _grabber := (x, y, w, h, dw := "", dh := "") => Pixel._ScreenGrab(x, y, w, h, dw, dh)

    ; ---- rect signature ------------------------------------------------------

    static Signature(x, y, w, h, cols := 16, rows := 6, thr := 170) {
        x := Integer(x), y := Integer(y), w := Integer(w), h := Integer(h)
        if (w < 1 || h < 1)
            return ""
        cols := Max(1, Min(Integer(cols), w, 40)), rows := Max(1, Min(Integer(rows), h, 40))
        px := ""
        try px := Pixel.Grab(x, y, w, h)
        if !(px is Array && px.Length = w * h)
            return ""
        return Pixel.SigFromPixels(px, w, h, cols, rows, thr)
    }

    static SigLike(stored, x, y, w, h) {
        p := Pixel.SigParse(stored)
        return IsObject(p) ? Pixel.Signature(x, y, w, h, p.cols, p.rows, p.thr) : ""
    }

    ; Pure: px = Array of w*h colors, row-major.
    static SigFromPixels(px, w, h, cols, rows, thr) {
        bright := [], total := []
        Loop cols * rows
            bright.Push(0), total.Push(0)
        Loop h {
            iy := A_Index - 1
            cy := (iy * rows) // h
            base := iy * w
            Loop w {
                ix := A_Index - 1
                c := px[base + A_Index] & 0xFFFFFF
                lum := (((c >> 16) & 0xFF) * 299 + ((c >> 8) & 0xFF) * 587 + (c & 0xFF) * 114) // 1000
                k := cy * cols + (ix * cols) // w + 1
                total[k] += 1
                if (lum >= thr)
                    bright[k] += 1
            }
        }
        cells := ""
        Loop cols * rows
            cells .= total[A_Index] ? Round(9 * bright[A_Index] / total[A_Index]) : 0
        return "s1:" cols "x" rows ":" thr ":" cells
    }

    static SigParse(s) {
        if !(s is String) || !RegExMatch(s, "^s1:(\d{1,2})x(\d{1,2}):(\d{1,3}):(\d+)$", &m)
            return ""
        cols := Integer(m[1]), rows := Integer(m[2]), thr := Integer(m[3])
        if (cols < 1 || rows < 1 || thr > 255 || StrLen(m[4]) != cols * rows)
            return ""
        cells := []
        Loop Parse m[4]
            cells.Push(Integer(A_LoopField))
        return {cols: cols, rows: rows, thr: thr, cells: cells}
    }

    static SigInk(s) {
        p := Pixel.SigParse(s)
        if !IsObject(p)
            return -1
        n := 0
        for v in p.cells
            n += v
        return n
    }

    static SigValid(s, minInk := 3) => Pixel.SigInk(s) >= minInk

    static SigMatch(live, stored, tol := 2) {
        m := Pixel.SigMaxDiff(live, stored)
        return (m >= 0 && m <= tol)
    }

    ; Largest per-cell difference, or -1 if malformed / different grid.
    static SigMaxDiff(a, b) {
        d := Pixel._SigDiffs(a, b)
        if !IsObject(d)
            return -1
        m := 0
        for v in d
            m := Max(m, v)
        return m
    }

    ; Sum of per-cell differences (L1), or -1 if malformed / different grid.
    static SigL1(a, b) {
        d := Pixel._SigDiffs(a, b)
        if !IsObject(d)
            return -1
        n := 0
        for v in d
            n += v
        return n
    }

    ; live is `target` and clearly not `other`: every cell within tol, L1 to
    ; target <= sumTol, and L1 to other at least `margin` larger than L1 to
    ; target. Malformed / mismatched grids -> false.
    static SigCloser(live, target, other, tol := 2, sumTol := 3, margin := 4) {
        if !Pixel.SigMatch(live, target, tol)
            return false
        dt := Pixel.SigL1(live, target), dOther := Pixel.SigL1(live, other)
        return (dt >= 0 && dOther >= 0 && dt <= sumTol && dOther - dt >= margin)
    }

    static _SigDiffs(a, b) {
        pa := Pixel.SigParse(a), pb := Pixel.SigParse(b)
        if !(IsObject(pa) && IsObject(pb) && pa.cols = pb.cols && pa.rows = pb.rows && pa.thr = pb.thr)
            return ""
        out := []
        for v in pa.cells
            out.Push(Abs(v - pb.cells[A_Index]))
        return out
    }

    ; A DESIGN-space rect (2560x1440 px) -> Array of w*h 0xRRGGBB, row-major,
    ; whatever the client size: at 2560x1440 the old _grabber(x, y, w, h)
    ; call; at another size _grabber(sx, sy, sw, sh, w, h) grabs the mapped
    ; screen rect and stretches it (nearest pixel) back to w x h, so every
    ; rect detector keeps its design-px geometry and strides.
    static Grab(x, y, w, h) {
        if Screen.IsIdentity()
            return (Pixel._grabber)(x, y, w, h)
        r := Screen.Rect(x, y, w, h)
        return (Pixel._grabber)(r.x, r.y, r.w, r.h, w, h)
    }

    ; One BitBlt of the rect into a 32bpp top-down DIB -> Array of 0xRRGGBB.
    ; dw, dh (default w, h): the array's size; a different size stretches
    ; (COLORONCOLOR: nearest pixel, colours kept exact).
    static _ScreenGrab(x, y, w, h, dw := "", dh := "") {
        hdcScreen := 0, hdcMem := 0, hbm := 0, old := 0
        sx := x, sy := y, sw := w, sh := h
        if (dw != "")
            w := dw, h := dh
        try {
            hdcScreen := DllCall("GetDC", "Ptr", 0, "Ptr")
            hdcMem := DllCall("CreateCompatibleDC", "Ptr", hdcScreen, "Ptr")
            bi := Buffer(40, 0)
            NumPut("UInt", 40, bi, 0), NumPut("Int", w, bi, 4), NumPut("Int", -h, bi, 8)
            NumPut("UShort", 1, bi, 12), NumPut("UShort", 32, bi, 14)
            hbm := DllCall("CreateDIBSection", "Ptr", hdcMem, "Ptr", bi, "UInt", 0, "Ptr*", &bits := 0, "Ptr", 0, "UInt", 0, "Ptr")
            if (!hbm || !bits)
                return ""
            old := DllCall("SelectObject", "Ptr", hdcMem, "Ptr", hbm, "Ptr")
            if (sw = w && sh = h) {
                if !DllCall("BitBlt", "Ptr", hdcMem, "Int", 0, "Int", 0, "Int", w, "Int", h
                    , "Ptr", hdcScreen, "Int", sx, "Int", sy, "UInt", 0x00CC0020)
                    return ""
            } else {
                DllCall("SetStretchBltMode", "Ptr", hdcMem, "Int", 3)          ; COLORONCOLOR
                if !DllCall("StretchBlt", "Ptr", hdcMem, "Int", 0, "Int", 0, "Int", w, "Int", h
                    , "Ptr", hdcScreen, "Int", sx, "Int", sy, "Int", sw, "Int", sh, "UInt", 0x00CC0020)
                    return ""
            }
            DllCall("GdiFlush")
            out := []
            out.Capacity := w * h
            Loop w * h
                out.Push(NumGet(bits, (A_Index - 1) * 4, "UInt") & 0xFFFFFF)
            return out
        } finally {
            if old
                DllCall("SelectObject", "Ptr", hdcMem, "Ptr", old)
            if hbm
                DllCall("DeleteObject", "Ptr", hbm)
            if hdcMem
                DllCall("DeleteDC", "Ptr", hdcMem)
            if hdcScreen
                DllCall("ReleaseDC", "Ptr", 0, "Ptr", hdcScreen)
        }
    }

    static _ScreenColor(x, y) {
        CoordMode("Pixel", "Screen")
        return PixelGetColor(x, y, "RGB")
    }

    ; Current color at DESIGN x,y (Screen maps it to the client) as Integer
    ; 0xRRGGBB. At 2560x1440 the getter gets x, y untouched.
    static Get(x, y) {
        if Screen.IsIdentity()
            return Pixel.ToRgb((Pixel._getter)(x, y))
        p := Screen.Pt(x, y)
        return Pixel.ToRgb((Pixel._getter)(p.x, p.y))
    }

    static Is(x, y, color, tol := 10) {
        return Pixel.Match(Pixel.Get(x, y), color, tol)
    }

    ; Polls every pollMs until x,y matches. -> false on timeout or when
    ; ctx.ShouldStop() turns true. ctx may be "" (no stop checks).
    static WaitFor(x, y, color, timeoutMs, ctx := "", tol := 10, pollMs := 50) {
        want := Pixel.ToRgb(color)
        deadline := A_TickCount + timeoutMs
        Loop {
            if (IsObject(ctx) && ctx.ShouldStop())
                return false
            if Pixel.Match(Pixel.Get(x, y), want, tol)
                return true
            left := deadline - A_TickCount
            if (left <= 0)
                return false
            Sleep(Min(pollMs, left))
        }
    }

    static Match(a, b, tol := 10) {
        a := Pixel.ToRgb(a), b := Pixel.ToRgb(b)
        return Abs(((a >> 16) & 0xFF) - ((b >> 16) & 0xFF)) <= tol
            && Abs(((a >> 8) & 0xFF) - ((b >> 8) & 0xFF)) <= tol
            && Abs((a & 0xFF) - (b & 0xFF)) <= tol
    }

    static ToRgb(c) {
        if (Type(c) = "Integer")
            return c & 0xFFFFFF
        s := Trim(String(c))
        if RegExMatch(s, "i)^(?:0x|#)?([0-9a-f]{6})$", &m)
            return Integer("0x" m[1])
        throw ValueError("Pixel: bad color value")
    }
}
