#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\GameText.ahk
#Include %A_LineFile%\..\Screen.ahk
; ---------------------------------------------------------------------------
; AutoCal: setup that calibrates itself. Windows of the game whose parts can
; be found ON SCREEN BY THEIR TEXT are placed from one read of the screen
; (Ocr.Lines: every line with its box), so their calibration steps need no
; hovering. Pure logic: lines in, places out (DESIGN px, 2560x1440). The
; tasks call these while their window is open, check the place by a read of
; its own (the title read again at the place found, the picked item's name,
; the result card's title) and only then click.
;
;   lines = Array of {text, x, y (centre), l, t, r, b}   (Ocr.Lines)
;
;   AutoCal.IsAuto(id)           the calibration step needs no hovering (the
;                                Calibrate page shows it as found on screen)
;   AutoCal.Find(lines, re)      the first line matching re, or ""
;
;   Fisher shop, its BUY tab (title "Fishing Shop", box 592,342..893,378;
;   live frame 2026-11-21 03:17, tests\screens\fishshop_buy_tab.jpg: 4
;   columns of tall tiles 243 apart, rows 304 apart, tile 1's centre
;   1125,596, 2 rows in sight, the rest under the wheel. The Sell tab's grid
;   is another one: 5 columns, 190 apart.)
;   AutoCal.ShopTitle(lines)     the title's line, or ""
;   AutoCal.ShopTile(title, k)   {x, y} of tile k (1-based, row by row) with
;                                the grid at its top; "" for a tile below
;                                the rows in sight; title "" = the shop's
;                                usual place
;   AutoCal.ShopLabel(lines, title, isName)   {x, y} of the tile whose name
;                                under its picture isName(text) accepts, or ""
;
;   Stella's Workshop (title "Stella's Workshop", read 'Stello's Worl<shop';
;   live frames 2026-11-20 / 11-21: title box 2005,229..2348,259, its X at
;   2467,242, the search box under the tabs, result cards 181 apart, "Open
;   Recipe" in the left panel)
;   AutoCal.Workshop(lines)      "" or {gui (the title's rect, read like
;                                cauldron_gui), close, search, open ("" when
;                                "Open Recipe" did not read), list (the rect
;                                the result cards are in)}
;   AutoCal.Card(lines, isTitle, hint)   the result card {x, y, w, h} whose
;                                title isTitle(text) accepts (hint != "": and
;                                whose lines under it hold the folded hint),
;                                or ""
;
;   Biome Selector (its 9 Drives in a fixed order, names centred in their
;   rows, rows 50 apart; live frames 2026-11-21: list rect 822,515,672,416)
;   AutoCal.Selector(lines, drives)   the list's rect (as selector_list_rect)
;                                or "": 3 Drives' rows must agree
;   AutoCal.SelectorConfirmX(r)  the prompt's Confirm button x
;
;   Inventory (title "Inventory" 1182,386..1382,418, tabs Gears / Items under
;   it, the search box, Use and the description in the left panel; frames
;   tests\screens\inventory_open_*, inv_randomizer_selected_sand). It scales
;   evenly, centred: read in Screen mode "C", as the tasks use it.
;   AutoCal.Inventory(lines)     "" or {title, tab (inv_items_tab: where
;                                "Items" reads, else beside "Gears", else
;                                from the title), search (inv_search), use
;                                (inv_use), tile1 (inv_tile1_rect), desc
;                                (inv_desc_rect), box (the window, for a
;                                closer read)}; search / use / tile1 / desc
;                                are "" when nothing reads where they would
;                                be. The title alone is taken: THE CALLER
;                                checks the tabs at `tab` (TaskEnv.InvOpen;
;                                the small tab words do not always read in
;                                a whole-screen read below 1440p).
;                                Inventory(lines, title) reads a part of
;                                the window with the title known already.
;   AutoCal.InvMerge(a, b)       a with its "" parts filled from b
;
;   Quest board (the panel on the right: title, "Objects", the buttons
;   Accept / Claim Rewards and Dismiss; Exit under the board, the < >
;   arrows beside it; live frames 2026-11-21, tests\screens\quest_page_full_*).
;   The panel maps in Screen mode "RH", Exit and the arrows stretch ("S"):
;   each is read in its own mode.
;   AutoCal.QuestPanel(lines)    "" or {rect (quest_board_rect), accept
;                                (quest_accept), dismiss (quest_dismiss)}:
;                                "Objects" and a button under it must sit
;                                as on the settled panel (it slides while
;                                the quest changes)
;   AutoCal.QuestExit(lines)     "" or {close (quest_close), next
;                                (quest_next, no text of its own: the task
;                                checks its pixels, AutoCal.IsArrow)}
;   AutoCal.IsArrow(px)          pixels (0xRRGGBB) of the box around an
;                                arrow: a dark button with a white glyph
;
; A window that scales evenly off 16:9 (not stretched like the Fishing Shop)
; is measured by its own text: the Workshop by its title's width, the
; Selector by its row spacing (yx = Screen.sx / Screen.sy puts the other
; axis right). At 16:9 both are 1. Not checked live off 16:9.
; ---------------------------------------------------------------------------

class AutoCal {
    ; steps found on screen: no hovering needed (fisher_item_<potion> too)
    static Ids := ["cauldron_gui", "cauldron_search", "cauldron_result", "cauldron_result_2"
        , "cauldron_open_recipe", "cauldron_close", "selector_list_rect", "selector_confirm"
        , "inv_items_tab", "inv_search", "inv_use", "inv_tile1_rect", "inv_desc_rect"
        , "quest_board_rect", "quest_accept", "quest_dismiss", "quest_close", "quest_next"]
    static TilePrefix := "fisher_item_"
    ; the inventory steps found by one look at the open inventory
    ; (lib\tasks\InvFind.ahk); the quest board's by the quest task
    static InvIds := ["inv_items_tab", "inv_search", "inv_use", "inv_tile1_rect", "inv_desc_rect"]
    static QuestIds := ["quest_board_rect", "quest_accept", "quest_dismiss", "quest_close", "quest_next"]

    static IsAuto(id) {
        id := String(id)
        if (SubStr(id, 1, StrLen(AutoCal.TilePrefix)) = AutoCal.TilePrefix)
            return true
        for a in AutoCal.Ids
            if (a = id)
                return true
        return false
    }

    static Find(lines, re) {
        if !(lines is Array)
            return ""
        for L in lines
            if RegExMatch(L.text, re)
                return L
        return ""
    }

    ; ---- Fisher shop --------------------------------------------------------

    static Shop := {re: "i)fishing\s*sh[ao0]p", dx: 533, dy: 254, pitch: 243, pitchY: 304, cols: 4, rows: 2
        , tile1: {x: 1125, y: 596}
        ; the names under the pictures, from the title's left / top; a name
        ; sits labelUp px under its tile's centre
        , labels: {l: 380, t: 90, r: 1420, b: 790}, labelUp: 49}

    static ShopTitle(lines) => AutoCal.Find(lines, AutoCal.Shop.re)

    static ShopTile(title, k) {
        s := AutoCal.Shop
        if (!IsInteger(k) || k < 1 || k > s.cols * s.rows)
            return ""
        x0 := IsObject(title) ? title.l + s.dx : s.tile1.x
        y0 := IsObject(title) ? title.t + s.dy : s.tile1.y
        return {x: x0 + Mod(k - 1, s.cols) * s.pitch, y: y0 + ((k - 1) // s.cols) * s.pitchY}
    }

    ; A long name breaks into two lines under its picture ("Fortune Potion" /
    ; "III"): a line is tried with the one right under it first, then alone.
    static ShopLabel(lines, title, isName) {
        if !(lines is Array && IsObject(title))
            return ""
        s := AutoCal.Shop, a := s.labels
        inGrid := []
        for L in lines
            if (L.x >= title.l + a.l && L.x <= title.l + a.r && L.y >= title.t + a.t && L.y <= title.t + a.b)
                inGrid.Push(L)
        for L in inGrid {
            for M in inGrid
                if (M.t > L.t && M.t - L.b < 30 && Abs(M.x - L.x) < 60 && isName(L.text " " M.text))
                    return {x: L.x, y: L.y - s.labelUp}
        }
        for L in inGrid
            if isName(L.text)
                return {x: L.x, y: L.y - s.labelUp}
        return ""
    }

    ; ---- Stella's Workshop ----------------------------------------------------

    static Ws := {titleW: 343, closeDx: 119, closeDy: -2, searchDx: -37, searchDy: 113
        , guiPadX: 30, guiPadY: 2, listDy: 140, listHalfW: 300
        , cardDx: -286, cardDy: -7, cardW: 572, cardH: 138, cardLines: 150
        , openRe: "i)[o0]pen\s*rec", scaleTol: 0.04}

    ; The title must hold both words ("Workshop" alone could be cut, and its
    ; middle is what everything else is placed from).
    static WsTitle(lines) {
        if !(lines is Array)
            return ""
        for L in lines
            if (GameText.Has(L.text, "workshop") && GameText.StartsWord(L.text, "stel"))
                return L
        return ""
    }

    static Workshop(lines, yx := "") {
        T := AutoCal.WsTitle(lines)
        if !IsObject(T)
            return ""
        w := AutoCal.Ws
        kx := (T.r - T.l) / w.titleW
        if (Abs(kx - 1) <= w.scaleTol)
            kx := 1
        ky := (kx = 1) ? 1 : kx * (IsNumber(yx) ? yx : Screen.sx / Screen.sy)
        X := (d) => Round(T.x + d * kx), Y := (d) => Round(T.y + d * ky)
        o := AutoCal.Find(lines, w.openRe)
        top := Y(w.listDy)
        return {title: T, kx: kx, ky: ky
            , gui: {x: T.l - w.guiPadX, y: T.t - w.guiPadY, w: (T.r - T.l) + 2 * w.guiPadX, h: (T.b - T.t) + 2 * w.guiPadY}
            , close: {x: Round(T.r + w.closeDx * kx), y: Y(w.closeDy)}
            , search: {x: X(w.searchDx), y: Y(w.searchDy)}
            , open: IsObject(o) ? {x: o.x, y: o.y} : ""
            , list: {x: X(-w.listHalfW), y: top, w: Round(2 * w.listHalfW * kx), h: Max(1, Screen.DesignH - top - 10)}}
    }

    static Card(lines, isTitle, hint := "", ws := "") {
        if !(lines is Array)
            return ""
        w := AutoCal.Ws
        kx := IsObject(ws) ? ws.kx : 1, ky := IsObject(ws) ? ws.ky : 1
        want := GameText.Fold(hint)
        for T in lines {
            if !isTitle(T.text)
                continue
            if (want != "") {
                under := ""
                for L in lines
                    if (L.y > T.y && L.t < T.t + w.cardLines * ky)
                        under .= " " L.text
                if !InStr(GameText.Fold(under), want)
                    continue
            }
            return {x: Round(T.x + w.cardDx * kx), y: Round(T.t + w.cardDy * ky), w: Round(w.cardW * kx), h: Round(w.cardH * ky)}
        }
        return ""
    }

    ; ---- Biome Selector ---------------------------------------------------------

    ; charW: the names are drawn in a fixed-width font, 19.8 px a letter
    ; ("Radiant Star Drive", 18 letters, reads 978..1334); a row's whole
    ; name is that wide (widthTol), so a read with junk glued on, or cut,
    ; gives no middle.
    static Sel := {w: 672, h: 416, pitch: 50, pitchMin: 35, pitchMax: 75, row1: 0.072
        , confirmDx: 0.315, minRows: 3, scaleTol: 0.06, rowTol: 0.25, sideTol: 320
        , charW: 19.8, widthTol: 0.08}

    ; Drive i (1-based) named by the line: its first or second word reads
    ; (the same rule as BiomeItemsTask.RowIs), or a long first word with its
    ; first or last letter lost ('nfernal', 'Chillin': thin coloured letters
    ; over the world, live frames). Only ever used with rows that agree.
    static _DriveOf(text, drives) {
        f := GameText.Fold(text)
        for d in drives {
            w := StrSplit(d, " ")
            if (GameText.Has(text, w[1]) || (w.Length > 1 && GameText.Has(text, w[2])))
                return A_Index
            a := GameText.Fold(w[1])
            if (StrLen(a) >= 6 && (InStr(f, SubStr(a, 2)) || InStr(f, SubStr(a, 1, -1))))
                return A_Index
        }
        return 0
    }

    static Selector(lines, drives, yx := "") {
        if !(lines is Array && drives is Array)
            return ""
        s := AutoCal.Sel
        hits := []
        for L in lines {
            i := AutoCal._DriveOf(L.text, drives)
            if i
                hits.Push({i: i, y: L.y, L: L})
        }
        ; the rows that agree: every pair of hits gives a spacing and a first
        ; row; the pair most other hits fit wins ('Auro Storage' reads as
        ; "Star" but fits no other row)
        best := "", bestN := 0
        for a in hits {
            for b in hits {
                if (b.i <= a.i)
                    continue
                p := (b.y - a.y) / (b.i - a.i)
                if (p < s.pitchMin || p > s.pitchMax)
                    continue
                y1 := a.y - (a.i - 1) * p
                seen := Map(), fit := []
                for h in hits
                    if (Abs(h.y - (y1 + (h.i - 1) * p)) <= s.rowTol * p && Abs(h.L.x - a.L.x) <= s.sideTol) {
                        seen[h.i] := 1
                        fit.Push(h)
                    }
                if (seen.Count > bestN)
                    bestN := seen.Count, best := {p: p, y1: y1, fit: fit}
            }
        }
        if (!IsObject(best) || bestN < s.minRows)
            return ""
        ; spacing and first row from every row that fits
        lo := best.fit[1], hi := best.fit[1]
        for h in best.fit {
            if (h.i < lo.i)
                lo := h
            if (h.i > hi.i)
                hi := h
        }
        p := (hi.y - lo.y) / (hi.i - lo.i)
        sum := 0
        for h in best.fit
            sum += h.y - (h.i - 1) * p
        y1 := sum / best.fit.Length
        ; the names are centred in their rows: the middle of a row whose
        ; whole name read (its first letters at the left, "Drive" at the right)
        mids := []
        for h in best.fit {
            ; (AHK names ignore case: no variable "l" next to a line "L")
            left := "", right := "", txt := ""
            parts := []
            for ln in lines
                if (Abs(ln.y - h.y) <= s.rowTol * p && Abs(ln.x - h.L.x) <= s.sideTol)
                    parts.Push(ln)
            Loop parts.Length {                 ; left to right
                pick := 0
                for k, ln in parts
                    if (!pick || ln.l < parts[pick].l)
                        pick := k
                ln := parts.RemoveAt(pick)
                left := (left = "") ? ln.l : Min(left, ln.l), right := (right = "") ? ln.r : Max(right, ln.r)
                txt .= " " ln.text
            }
            head := SubStr(GameText.Fold(drives[h.i]), 1, 2)
            wide := StrLen(drives[h.i]) * s.charW * (p / s.pitch)
            if (SubStr(GameText.Fold(txt), 1, 2) = head && RegExMatch(txt, "i)r[il1|]ve\W*$")
                && Abs((right - left) - wide) <= s.widthTol * wide)
                mids.Push((left + right) / 2)
        }
        if !mids.Length
            return ""
        cx := AutoCal._Median(mids)
        ky := p / s.pitch
        if (Abs(ky - 1) <= s.scaleTol)
            ky := 1
        kx := (ky = 1) ? 1 : ky / (IsNumber(yx) ? yx : Screen.sx / Screen.sy)
        w := Round(s.w * kx), h := Round(s.h * ky)
        return {x: Round(cx - w / 2), y: Round(y1 - s.row1 * h), w: w, h: h}
    }

    static SelectorConfirmX(r) => Round(r.x + AutoCal.Sel.confirmDx * r.w)

    ; ---- Inventory -----------------------------------------------------------------

    ; offsets from the title's middle (1282,402 on every frame)
    static Inv := {re: "i)^\W*[il1|]nvent[o0]r[yv]\W*$"
        , tab: {dx: 414, dy: 47}, tabRe: "i)^\W*[il1|]?te\S{0,3}s\W*$", gearsRe: "i)^\W*ge[ao]rs\W*$", gearsDx: -32
        , search: {dx: 152, dy: 88}, searchLeft: -206, searchTol: 16
        , use: {dx: -372, dy: 370}, useRe: "i)^\W*use\W*$", useTol: 36
        , tile1: {dx: -206, dy: 176, w: 110, h: 112}
        , desc: {dx: -262, dy: 40, w: 367, h: 243}}

    ; title: the title's line from an earlier read (for a closer read of a
    ; part of the window that does not hold the title)
    static Inventory(lines, title := "") {
        v := AutoCal.Inv
        T := IsObject(title) ? title : AutoCal.Find(lines, v.re)
        if !(IsObject(T) && lines is Array)
            return ""
        ; the Items tab: its own word, else beside Gears, else from the title
        ; (the caller reads the tabs there before it believes any of it)
        tabY := T.y + v.tab.dy, tab := "", read := false
        for ln in lines {
            if (Abs(ln.y - tabY) > 12)
                continue
            if (RegExMatch(ln.text, v.tabRe) && Abs(ln.x - (T.x + v.tab.dx)) <= 30)
                tab := {x: ln.x, y: ln.y}, read := true
            else if (RegExMatch(ln.text, v.gearsRe) && Abs(ln.x - (T.x + v.gearsDx)) <= 30 && !read)
                tab := {x: T.x + v.tab.dx, y: ln.y}
        }
        if !IsObject(tab)
            tab := {x: T.x + v.tab.dx, y: tabY}
        out := {title: T, tab: tab, search: "", use: "", tile1: "", desc: ""
            , box: {x: T.x - 700, y: T.y - 60, w: 1400, h: 820}
            ; "use" is small: it reads in this box at 2x at every size
            ; tried (1280x720 .. 1920x1080 frames), not always in a bigger one
            , useBox: {x: T.x - 582, y: T.y + 278, w: 420, h: 180}}
        ; the search box: its text (the "Search..." hint or what was typed)
        ; starts at its left end
        sy := T.y + v.search.dy
        for ln in lines
            if (Abs(ln.y - sy) <= 10 && Abs(ln.l - (T.x + v.searchLeft)) <= v.searchTol)
                out.search := {x: T.x + v.search.dx, y: ln.y}
        ; Use, and the description right under it
        for ln in lines
            if (RegExMatch(ln.text, v.useRe) && Abs(ln.x - (T.x + v.use.dx)) <= v.useTol && Abs(ln.y - (T.y + v.use.dy)) <= v.useTol) {
                out.use := {x: ln.x, y: ln.y}
                out.desc := {x: ln.x + v.desc.dx, y: ln.y + v.desc.dy, w: v.desc.w, h: v.desc.h}
            }
        ; the first tile's name: a line must read inside its box
        r := {x: T.x + v.tile1.dx, y: T.y + v.tile1.dy, w: v.tile1.w, h: v.tile1.h}
        for ln in lines
            if (ln.x >= r.x && ln.x <= r.x + r.w && ln.y >= r.y && ln.y <= r.y + r.h)
                out.tile1 := r
        return out
    }

    static InvMerge(a, b) {
        if !IsObject(a)
            return b
        if !IsObject(b)
            return a
        for k in ["search", "use", "tile1", "desc"]
            if (!IsObject(a.%k%) && IsObject(b.%k%))
                a.%k% := b.%k%
        return a
    }

    ; ---- Quest board -----------------------------------------------------------------

    ; "Objects" 2147,512..2360,557 (middle 2254,535); the buttons' row 552
    ; under it, Dismiss 120 right of it, Accept / Claim Rewards 121 left;
    ; Exit 1282,1254, the > arrow 1815,720
    static Quest := {objRe: "i)^\W*[o0]b[ji]ects?\W*$", rect: {dx: -230, dy: -23, w: 458, h: 326}
        , rowDy: 552, rowTol: 14, dismissDx: 120, acceptDx: -121, btnTol: 16, acceptTol: 44
        , dismissRe: "i)d[il1|]sm[il1|]ss"
        , exitRe: "i)^\W*ex[il1|]t\W*$", nextDx: 533, nextDy: -534
        , arrowBox: 60, arrowBright: 200, arrowDark: 120}

    static QuestPanel(lines) {
        q := AutoCal.Quest
        if !(lines is Array)
            return ""
        for O in lines {
            if !RegExMatch(O.text, q.objRe)
                continue
            rowY := ""
            for ln in lines {
                if (Abs(ln.y - (O.y + q.rowDy)) > q.rowTol)
                    continue
                if (RegExMatch(ln.text, q.dismissRe) && Abs(ln.x - (O.x + q.dismissDx)) <= q.btnTol)
                    rowY := ln.y
                else if (rowY = "" && ln.x < O.x && Abs(ln.x - (O.x + q.acceptDx)) <= q.acceptTol && StrLen(RegExReplace(ln.text, "[^A-Za-z]")) >= 4)
                    rowY := ln.y
            }
            if (rowY = "")
                continue                        ; the panel is sliding, or it is not the board
            return {rect: {x: O.x + q.rect.dx, y: O.t + q.rect.dy, w: q.rect.w, h: q.rect.h}
                , accept: {x: O.x + q.acceptDx, y: rowY}, dismiss: {x: O.x + q.dismissDx, y: rowY}}
        }
        return ""
    }

    static QuestExit(lines) {
        q := AutoCal.Quest
        E := AutoCal.Find(lines, q.exitRe)
        if !IsObject(E)
            return ""
        return {close: {x: E.x, y: E.y}, next: {x: E.x + q.nextDx, y: E.y + q.nextDy}}
    }

    ; The box around an arrow (arrowBox px square): the dark button fills it
    ; (live frames: 91 %), its white glyph is 8 % of it.
    static IsArrow(px) {
        q := AutoCal.Quest
        if !(px is Array && px.Length >= 100)
            return false
        br := 0, dk := 0
        for c in px {
            r := (c >> 16) & 255, g := (c >> 8) & 255, b := c & 255
            if (Min(r, g, b) >= q.arrowBright)
                br++
            else if (Max(r, g, b) < q.arrowDark)
                dk++
        }
        return br >= px.Length * 0.03 && br <= px.Length * 0.2 && dk >= px.Length * 0.7
    }

    static _Median(a) {
        v := []
        for x in a {
            i := 1
            while (i <= v.Length && v[i] <= x)
                i++
            v.InsertAt(i, x)
        }
        n := v.Length
        return Mod(n, 2) ? v[(n + 1) // 2] : (v[n // 2] + v[n // 2 + 1]) / 2
    }
}
