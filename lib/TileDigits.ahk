#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\Ocr.ahk
; ---------------------------------------------------------------------------
; TileDigits: reads the white count on an inventory tile ("x113107") by
; matching each glyph against the game font's digits, no OCR engine.
;
; 2026-11-18 live: Windows OCR read the tile counts x112842 / x113107 as
; 'xu25ß7_' / 'x 1 mamo 7' (the font's 1 is a bare bar), so a "Use N Lucky
; Potion" quest always skipped. The templates below are 10 x 14 cells made
; from real 2560x1440 frames (every digit, 53 glyphs: tile counts x5 x14
; x21 x80 x55 x1 x8 x90 x87 x77 x2037 x821 x550 x1057 x2036 x541 x112842
; x255); the glyph box is scaled to the cell grid, so other sizes work too.
;
;   TileDigits.Read(x, y, w, h)  -> "113107" | ""  (the screen; Ocr._srcFile /
;                                   Ocr.Win are honoured, as Ocr.Read)
;   TileDigits.FromMask(m, w, h) -> the same from a 0/1 Buffer (tests)
; "" whenever any glyph is not a clear match: the caller treats the count
; as unreadable (a potion is never used on a guess).
; ---------------------------------------------------------------------------

class TileDigits {
    static TW := 10, TH := 14
    static WhiteMin := 200       ; ink: every channel at least this
    static MinScore := 0.86      ; share of matching cells for a glyph
    static MinMargin := 0.04     ; ahead of the second-best digit by this
    static Templates := Map(
        "0", "01111111111110000111111000011111100001111110000111111000011111100001111110000111111000011111100001111110000111111000011111100001110111111111",
        "1", "11111111110000111111000011111100001111110000111111000011111100001111110000111111000011111100001111110000111111000011111100001111110000111111",
        "2", "11111111101110000111111000011111100001110000000111000000111000000111100000011110000011110000011110000011110000001110000001110000001111111111",
        "3", "01111111101110000111111000011111100001110000000111000000011100001111100000111110000000011100000001111110000111111000011111100001110111111110",
        "4", "00001110000000110000000111000000111000000011100000011110000001110011100111001110011100111011100011101100001110111111111100000011100000001110",
        "5", "01111111110110000000011000000001100000000110000000011111111000000001110000000111000000011100000001111110000111111000011111100001110111111110",
        "6", "01111111100110000111111000011111100001111110000000111000000011111111101111111110111000011111100001111110000111111000011101100001110111111110",
        "7", "11111111110000000111000000111100000011100000011110000001110000001111000000111100000011100000011110000001110000001111000000111000000111100000",
        "8", "01111111101110000111111000011111100001111110000111111000011101111111100111111110111000011111100001111110000111111000011111100001110111111110",
        "9", "01111111101110000111111000011111100001111110000111111000011111100001111110000111011111111100000001110110000111011000011101100001110111111110")

    static Read(x, y, w, h) {
        ; a DESIGN box, mapped like every Ocr read (bug hunt 2026-11-27: it
        ; was blitted as screen px, so at 1080p or on a second monitor the
        ; count was read from other pixels and fell back to the garbling OCR)
        ; the glyphs are 1440p-sized: at any other scale they read as ""
        ; or worse (resampled x1.5: "87" as "07"), and a wrong count feeds
        ; the potion plan, so only s = 1 (1440p anywhere on the desktop)
        if (Screen.s != 1)
            return ""
        if !Screen.IsIdentity() {
            r := Screen.Rect(x, y, w, h)
            x := r.x, y := r.y, w := r.w, h := r.h
        }
        if (w < 8 || h < 8)
            return ""
        g := ""
        try {
            g := Ocr._Capture(x, y, w, h, w, h)
            m := Buffer(w * h, 0), q := g.bits, wm := TileDigits.WhiteMin
            Loop w * h {
                if (Min(NumGet(q, 0, "UChar"), NumGet(q, 1, "UChar"), NumGet(q, 2, "UChar")) >= wm)
                    NumPut("UChar", 1, m, A_Index - 1)
                q += 4
            }
        } catch Any {
            return ""
        } finally {
            if IsObject(g)
                Ocr._FreeCapture(g)
        }
        return TileDigits.FromMask(m, w, h)
    }

    ; m: Buffer of w*h bytes, 1 = ink. Shapes touching the edge (the tile's
    ; corner brackets) are dropped, the short "x" and specks too.
    static FromMask(m, w, h) {
        comps := TileDigits._Comps(m, w, h)
        if !comps.Length
            return ""
        hmax := 0
        for c in comps
            hmax := Max(hmax, c.y1 - c.y0)
        if (hmax < 7)
            return ""
        glyphs := []
        for c in comps
            if (c.y1 - c.y0 >= 0.8 * hmax)
                glyphs.Push(c)
        ; left to right; touching digits split by width
        glyphs := TileDigits._SortX(glyphs)
        usual := hmax * 0.9, parts := []
        for c in glyphs {
            wd := c.x1 - c.x0
            k := (wd > usual * 1.6) ? Max(1, Round(wd / usual)) : 1
            Loop k
                parts.Push({x0: c.x0 + Round((A_Index - 1) * wd / k), x1: c.x0 + Round(A_Index * wd / k), y0: c.y0, y1: c.y1})
        }
        if (parts.Length < 1 || parts.Length > 9)
            return ""
        out := ""
        for p in parts {
            d := TileDigits._Match(m, w, p)
            if (d = "")
                return ""
            out .= d
        }
        return out
    }

    ; -> the digit whose template fits glyph box p, or ""
    static _Match(m, w, p) {
        v := TileDigits._Cells(m, w, p)
        best := "", bs := -1, second := -1
        for d, t in TileDigits.Templates {
            same := 0
            Loop StrLen(t)
                same += (SubStr(t, A_Index, 1) = SubStr(v, A_Index, 1))
            s := same / StrLen(t)
            if (s > bs)
                second := bs, bs := s, best := d
            else if (s > second)
                second := s
        }
        return (bs >= TileDigits.MinScore && bs - second >= TileDigits.MinMargin) ? best : ""
    }

    ; glyph box -> "0101..." (TW x TH cells, 3 x 3 samples a cell, ink when
    ; at least 4 of the 9 samples are)
    static _Cells(m, w, p) {
        gw := p.x1 - p.x0, gh := p.y1 - p.y0, out := ""
        Loop TileDigits.TH {
            cy := A_Index - 1
            Loop TileDigits.TW {
                cx := A_Index - 1, n := 0
                Loop 3 {
                    sy := p.y0 + Min(gh - 1, Floor((cy + (A_Index - 0.5) / 3) * gh / TileDigits.TH))
                    iy := A_Index
                    Loop 3 {
                        sx := p.x0 + Min(gw - 1, Floor((cx + (A_Index - 0.5) / 3) * gw / TileDigits.TW))
                        n += NumGet(m, sy * w + sx, "UChar")
                    }
                }
                out .= (n >= 4) ? "1" : "0"
            }
        }
        return out
    }

    ; 4-connected shapes not touching the edge, over 8 px: [{x0, y0, x1, y1}]
    static _Comps(m, w, h) {
        seen := Buffer(w * h, 0), out := []
        Loop w * h {
            i := A_Index - 1
            if (!NumGet(m, i, "UChar") || NumGet(seen, i, "UChar"))
                continue
            st := [i], NumPut("UChar", 1, seen, i)
            x0 := w, y0 := h, x1 := 0, y1 := 0, n := 0, edge := false
            while st.Length {
                j := st.Pop(), x := Mod(j, w), y := j // w, n++
                x0 := Min(x0, x), y0 := Min(y0, y), x1 := Max(x1, x + 1), y1 := Max(y1, y + 1)
                if (x = 0 || y = 0 || x = w - 1 || y = h - 1)
                    edge := true
                for nb in [x > 0 ? j - 1 : -1, x < w - 1 ? j + 1 : -1, y > 0 ? j - w : -1, y < h - 1 ? j + w : -1]
                    if (nb >= 0 && NumGet(m, nb, "UChar") && !NumGet(seen, nb, "UChar"))
                        NumPut("UChar", 1, seen, nb), st.Push(nb)
            }
            if (!edge && n > 8)
                out.Push({x0: x0, y0: y0, x1: x1, y1: y1})
        }
        return out
    }

    static _SortX(arr) {
        out := []
        for c in arr {
            i := out.Length + 1
            while (i > 1 && out[i - 1].x0 > c.x0)
                i--
            out.InsertAt(i, c)
        }
        return out
    }
}
