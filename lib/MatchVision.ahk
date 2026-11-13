#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\tasks\FishLogic.ahk
; ---------------------------------------------------------------------------
; MatchVision: the eyes of the Memory Match task (the board as measured on
; the user's clip 2026-10-27, 2560x1440). Tiles show an icon and an amount
; ("x100", "x1,000", "x1") but no name, and Windows OCR misreads the small
; amounts ("xT00", nothing for x1), so tiles are told apart by their PIXELS:
; the same reward and amount always draw the same picture.
;
;   v := MatchVision(grab)   grab(x1, x2, ys, stride) -> rows of 0xRRGGBB
;                            (StripGrab.Rows shape; default StripGrab.Rows)
;   MatchVision.Tile(i)      i = 1..20, row by row -> {x, y, w, h}
;   MatchVision.Center(i)    -> {x, y}: where a flip is clicked
;   v.State(i)               the tile's corner against its bottom right ->
;                            "hidden" (face down) | "open" (face up, or the
;                            cursor on it) | "matched" (green, 0x56BB5E) |
;                            "" (animating)
;   v.Sig(i)                 -> {icon, prof, width}: sampled pixels of the
;                            icon; the amount line as a column profile (white
;                            pixels per screen column, trimmed to the text),
;                            and the text's width in px
;   MatchVision.Same(a, b)   two Sigs show the same reward and amount
;   MatchVision.Stable(a, b) two Sigs of ONE tile taken a moment apart are
;                            equal (its flip animation is over)
;
; VALUE without reading: the amount's text width orders the rewards. "x1"
; (the rare ones: Godlike, Heavenly, Godly, Bound, Void Coin, Rune) is the
; narrowest, then x5 (Fortune/Haste III), x10 / x20, x25..x200 (Lucky /
; Speed), and the coins (x1,000 and up) are the widest.
; ---------------------------------------------------------------------------

class MatchVision {
    static Grid := {x0: 1037, y0: 440, dx: 150.3, dy: 162, w: 122, h: 132, cols: 5, rows: 4}
    static Colors := Map("hidden", 0x212121, "open", 0x434343, "matched", 0x56BB5E)
    static CornerTol := 18
    static PixTol := 48          ; per channel, two samples are "the same"
    static IconMin := 0.70       ; icon samples that must agree (clip: pairs 0.81-1.00, others <= 0.40, mid-flip 0.04)
    static Ink := 0x68           ; a sample is icon (not tile background) when a channel reaches this
    static ProfMaxDiff := 0.035  ; amount profiles: real pairs 0.00-0.01, x3,000 vs x5,000 0.08 (clip)
    static ProfShift := 2        ; px of slack when lining the profiles up
    static Bright := 0xB0        ; amount text: every channel at least this

    __New(grab := "") {
        this._grab := IsObject(grab) ? grab : (x1, x2, ys, stride) => StripGrab.Rows(x1, x2, ys, stride)
    }

    static Tile(i) {
        g := MatchVision.Grid
        r := (i - 1) // g.cols, c := Mod(i - 1, g.cols)
        return {x: g.x0 + Round(g.dx * c), y: g.y0 + g.dy * r, w: g.w, h: g.h}
    }

    static Center(i) {
        t := MatchVision.Tile(i)
        return {x: t.x + t.w // 2, y: t.y + t.h // 2}
    }

    ; The corner (+10,+10) against the bottom right (+105,+118) of the same
    ; tile, so a brighter or darker look does not matter. Face down: a grey
    ; corner and a bottom right a little darker (0x222222 / 0x131313 on the
    ; 2026-10-27 clip, 0x3E3E3E / 0x252525 live 1920x1080 2026-11-11 after
    ; a game update: the fixed 0x212121 read every tile as "open" and the
    ; board never counted as dealt). Face up (or the cursor on a face-down
    ; tile): a lighter corner and a near-black bottom right (0x444444 /
    ; 0x010101 on the clip). Green corner: matched.
    static DownStep := [6, 42]     ; corner minus bottom right, face down (clip 15, live 25)
    static DownMax := 0x58         ; a face-down corner is no lighter than this
    State(i) {
        t := MatchVision.Tile(i)
        rows := (this._grab)(t.x + 10, t.x + 105, [t.y + 10, t.y + 118], 95)
        c := rows[1][1], lr := rows[2][rows[2].Length]
        if MatchVision._Near(c, MatchVision.Colors["matched"], MatchVision.CornerTol)
            return "matched"
        if !(MatchVision._Grey(c) && MatchVision._Grey(lr))
            return ""
        d := (c & 0xFF) - (lr & 0xFF)
        if (d >= MatchVision.DownStep[1] && d <= MatchVision.DownStep[2] && (c & 0xFF) <= MatchVision.DownMax)
            return "hidden"
        if (d > MatchVision.DownStep[2])
            return "open"
        return ""
    }

    ; r, g, b within 10 of each other
    static _Grey(c) {
        r := (c >> 16) & 0xFF, g := (c >> 8) & 0xFF, b := c & 0xFF
        return Max(r, g, b) - Min(r, g, b) <= 10
    }

    Sig(i) {
        t := MatchVision.Tile(i)
        iys := [], tys := []
        y := t.y + 18
        while (y <= t.y + 96)
            iys.Push(y), y += 6
        ; the amount line one sample per SCREEN px: below 1440p a design-px
        ; step read some screen columns twice, and which ones changed with
        ; the tile's x, so two tiles of a pair drew different profiles
        ; (Test_Resample_PixelReads "mm pairs"). Nudged 0.1 screen px off
        ; the half-pixel ties of x0.75.
        st := Screen.IsIdentity() ? 1 : 1 / Screen.s
        nud := Screen.IsIdentity() ? 0 : 0.1 * st
        y := t.y + 100 + nud
        while (y <= t.y + 126)
            tys.Push(y), y += st
        icon := MatchVision._Flat((this._grab)(t.x + 10, t.x + 112, iys, 3))
        rows := (this._grab)(t.x + 6 + nud, t.x + 116, tys, st)
        cols := []
        Loop rows[1].Length
            cols.Push(0)
        for row in rows
            for k, c in row
                cols[k] += MatchVision._IsBright(c) ? 1 : 0
        lo := 0, hi := 0
        for k, n in cols {
            if (n > 0) {
                lo := (lo = 0) ? k : lo
                hi := k
            }
        }
        prof := []
        if hi
            Loop hi - lo + 1
                prof.Push(cols[lo + A_Index - 1])
        return {icon: icon, prof: prof, width: prof.Length}
    }

    static Same(a, b) {
        if (!IsObject(a) || !IsObject(b) || a.icon.Length != b.icon.Length)
            return false
        ; only samples where either tile draws something: the dark tile
        ; background is the same on every tile and would hide a difference
        ink := 0, ok := 0
        for k, c in a.icon {
            d := b.icon[k]
            if !(MatchVision._IsInk(c) || MatchVision._IsInk(d))
                continue
            ink++
            ok += MatchVision._Near(c, d, MatchVision.PixTol) ? 1 : 0
        }
        if (ink = 0 || ok < MatchVision.IconMin * ink)
            return false
        return MatchVision.ProfDiff(a.prof, b.prof) <= MatchVision.ProfMaxDiff
    }

    ; Amount profiles -> the smallest differing share over shifts of up to
    ; ProfShift px (1 = nothing alike). Different lengths count as different.
    static ProfDiff(p, q) {
        if (p.Length = 0 || q.Length = 0 || Abs(p.Length - q.Length) > MatchVision.ProfShift)
            return 1
        sum := 0
        for n in p
            sum += n
        for n in q
            sum += n
        best := 1
        s := -MatchVision.ProfShift
        while (s <= MatchVision.ProfShift) {
            d := 0
            Loop Max(p.Length, q.Length + s) - Min(1, 1 + s) + 1 {
                k := Min(1, 1 + s) + A_Index - 1
                a := (k >= 1 && k <= p.Length) ? p[k] : 0
                j := k - s
                b := (j >= 1 && j <= q.Length) ? q[j] : 0
                d += Abs(a - b)
            }
            best := Min(best, d / sum)
            s++
        }
        return best
    }

    static Stable(a, b) => MatchVision.Same(a, b)

    static _Flat(rows) {
        out := []
        for row in rows
            for c in row
                out.Push(c)
        return out
    }

    static _IsInk(c) => ((c >> 16) & 0xFF) >= MatchVision.Ink || ((c >> 8) & 0xFF) >= MatchVision.Ink || (c & 0xFF) >= MatchVision.Ink

    static _IsBright(c) => ((c >> 16) & 0xFF) >= MatchVision.Bright && ((c >> 8) & 0xFF) >= MatchVision.Bright && (c & 0xFF) >= MatchVision.Bright

    static _Near(a, b, tol) {
        return Abs(((a >> 16) & 0xFF) - ((b >> 16) & 0xFF)) <= tol
            && Abs(((a >> 8) & 0xFF) - ((b >> 8) & 0xFF)) <= tol
            && Abs((a & 0xFF) - (b & 0xFF)) <= tol
    }
}

; A grab(x1, x2, ys, stride) over a saved frame (tests\screens), like
; StripGrab.Rows over the screen. Loads the image once per instance.
class MatchFileGrab {
    __New(path) {
        DllCall("LoadLibrary", "Str", "gdiplus", "Ptr")
        si := Buffer(24, 0), NumPut("UInt", 1, si, 0)
        DllCall("gdiplus\GdiplusStartup", "Ptr*", &tok := 0, "Ptr", si, "Ptr", 0)
        this._tok := tok
        if DllCall("gdiplus\GdipCreateBitmapFromFile", "WStr", path, "Ptr*", &bmp := 0) || !bmp
            throw Error("MatchFileGrab: cannot load " path)
        this._bmp := bmp
    }
    __Delete() {
        try DllCall("gdiplus\GdipDisposeImage", "Ptr", this._bmp)
        try DllCall("gdiplus\GdiplusShutdown", "Ptr", this._tok)
    }
    Call(x1, x2, ys, stride := 1) {
        out := []
        for y in ys {
            row := []
            x := x1
            while (x <= x2) {
                DllCall("gdiplus\GdipBitmapGetPixel", "Ptr", this._bmp, "Int", x, "Int", y, "UInt*", &c := 0)
                row.Push(c & 0xFFFFFF)
                x += stride
            }
            out.Push(row)
        }
        return out
    }
}
