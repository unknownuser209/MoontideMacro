#Requires AutoHotkey v2.0
; ---------------------------------------------------------------------------
; Polish pass of 2026-11-19 (.superpowers\sdd\2026-11-18-themes-layout\
; polish-findings.md): a long translation never shrinks a label below 9 pt
; or a button below 8 pt (a caption or small text not at all) and a shrunk
; label keeps the middle of its row; list columns show their whole status
; words; the leftover English is translated.
; Every test builds its windows hidden and ends with I18n.Use("en").
; Helpers UiDashTmp / UiDashClose / UiDashPos: test_ui_dash.ahk; I18nNeed:
; test_i18n.ahk.
; ---------------------------------------------------------------------------

; |lfHeight| (real px) of a control's font; 0 when it has none.
PlFontPx(c) {
    try {
        hf := SendMessage(0x31, 0, 0, c.Hwnd)              ; WM_GETFONT
        lf := Buffer(92, 0)
        if (hf && DllCall("gdi32\GetObjectW", "Ptr", hf, "Int", 92, "Ptr", lf))
            return Abs(NumGet(lf, 0, "Int"))
    }
    return 0
}

; |lfHeight| of Theme.MinPt(role) in c's window (times the UI size when the
; window scales), as Gui.SetFont makes it.
PlFloorPx(c, role) {
    pt := Theme.MinPt(role)
    if Theme.IsScaled(c.Gui)
        pt := Max(6, Theme.S(pt))
    return DllCall("MulDiv", "Int", pt, "Int", A_ScreenDPI, "Int", 72, "Int")
}

; " | what: ..." for each text of g in a font under its floor (a button:
; 8 pt; a label: 9 pt; caps / small: their own size), and each label that
; was shrunk and still does not show its whole text.
PlTextsBad(g, what) {
    bad := ""
    for h, c in g {
        if (c.Type != "Text" || c.Text = "")
            continue
        btn := Theme.IsButton(c)
        role := btn ? "button" : Theme.RoleOf(c)
        if (role = "") {
            if !Theme.FitPt(c)
                continue
            role := "body"
        }
        px := PlFontPx(c), floor := PlFloorPx(c, role)
        if (px && px < floor)
            bad .= " | " what ": '" SubStr(c.Text, 1, 30) "' (" role ") font " px " px, at least " floor
        if (Theme.FitPt(c) && !btn) {
            p := UiDashPos(c), n := I18nNeed(c, c.Text, 9999, true)
            if (n.w > p.w || n.h > p.h)
                bad .= " | " what ": '" SubStr(c.Text, 1, 30) "' shrunk to " Theme.FitPt(c) " pt still needs " n.w "x" n.h " in " p.w "x" p.h
        }
    }
    return bad
}

; Theme.FitFont: a label stops at 9 pt, a button at 8 pt, a caption (8 pt
; already) does not shrink; a top-aligned label moves down by half the
; height it lost (its text keeps the row's middle), a centred one stays.
Test_Polish_FitFontFloor() {
    g := Gui()
    try {
        AssertEq(Theme.MinPt("body"), 9, "labels: 9 pt")
        AssertEq(Theme.MinPt("button"), 8, "buttons: 8 pt")
        AssertEq(Theme.MinPt("caps"), 8, "caps: their own 8 pt")
        AssertEq(Theme.MinPt("small"), 8, "small: their own 8 pt")
        long := "A very long translated label text that never fits"
        l := Theme.Label(g, "x0 y40 w60 h20", long)
        h0 := Theme.TextH(l)
        AssertEq(Theme.FitFont(l, "body", 60), 9, "a label stops at 9 pt")
        AssertEq(Theme.FitPt(l), 9, "recorded")
        AssertEq(PlFontPx(l), PlFloorPx(l, "body"), "its font is 9 pt")
        l.GetPos(, &y)
        AssertEq(y, 40 + (h0 - Theme.TextH(l)) // 2, "moved down by half the height it lost")
        AssertTrue(y > 40, "the 1 pt smaller text sits lower (" y ")")
        cl := Theme.Label(g, "x0 y80 w60 h20 +0x200", long)
        Theme.FitFont(cl, "body", 60)
        cl.GetPos(, &y)
        AssertEq(y, 80, "a vertically centred label stays")
        ok := Theme.Label(g, "x0 y120 w300 h20", "Short")
        AssertEq(Theme.FitFont(ok, "body", 300), 10, "a text that fits keeps 10 pt")
        AssertEq(Theme.FitPt(ok), 0, "nothing recorded")
        b := Theme.Button(g, "x0 y160 w40 h28", long, (*) => 0)
        AssertEq(Theme.FitPt(b), 8, "a button stops at 8 pt")
        AssertEq(PlFontPx(b), PlFloorPx(b, "button"), "its font is 8 pt")
        Theme.SetText(b, "OK")
        AssertEq(Theme.FitPt(b), 0, "a short text: back to the full size")
        ; quiet (flat) buttons keep the same padding rule (de "Leeren")
        q := Theme.Button(g, "x0 y240 w40 h28", long, (*) => 0, "quiet")
        AssertTrue(Theme.IsButton(q), "a quiet button is a button for the fit tests")
        AssertEq(Theme.FitPt(q), 8, "and shrinks like one")
        c := Theme.Label(g, "x0 y200 w20 h14", "CAPTION TEXT", "caps")
        AssertEq(Theme.FitFont(c, "caps", 20), 8, "a caption does not shrink")
        AssertEq(Theme.FitPt(c), 0, "nothing recorded for it")
    } finally {
        try Theme.Forget(g)
        try g.Destroy()
    }
}

; In every language at 100 and 130 %: no text of the dashboard (every page,
; the header, the sidebar) or of the setup wizard (every page, 100 %) is in
; a font under its floor (labels 9 pt, buttons 8 pt, captions and small
; texts their own size), and every shrunk label shows its whole text. A
; translation that would need more is too long (fil "Laging i-clip ang
; klase" was 6-7 pt). The Look preview's texts fit their boxes.
Test_Polish_TextsNotTooSmall() {
    oldSc := Theme.Scale, oldWa := Theme.WorkAreaFn
    dir := UiDashTmp()
    d := "", w := ""
    try {
        Theme.WorkAreaFn := () => {w: 3840, h: 2160}
        bad := ""
        for code in I18n.Codes {
            I18n.Use(code)
            for sc in [100, 130] {
                Theme.Scale := sc
                d := Dashboard(Config.Load(dir))
                for i, name in Dashboard.Pages
                    d.SelectPage(i)
                bad .= PlTextsBad(d._gui, code " " sc " % dashboard")
                ; the Look preview's texts fit their boxes (vi "Trang chu" was cut)
                for part in ["nav", "title", "small", "head", "body", "button"] {
                    c := d._lkPv[part], p := UiDashPos(c), n := I18nNeed(c, c.Text, 9999, true)
                    if (n.w > p.w || n.h > p.h)
                        bad .= " | " code " " sc " % preview " part ": '" c.Text "' needs " n.w "x" n.h " in " p.w "x" p.h
                }
                UiDashClose(d), d := ""
            }
            Theme.Scale := 100
            w := SetupWizard(Config.Load(dir))
            Loop SetupWizard.Steps {
                bad .= PlTextsBad(w._gui, code " wizard " A_Index)
                if (A_Index < SetupWizard.Steps)
                    w._Show(A_Index + 1)
            }
            w.Destroy(), w := ""
        }
        AssertEq(bad, "", "every language")
    } finally {
        Theme.Scale := oldSc, Theme.WorkAreaFn := oldWa
        I18n.Use("en")
        UiDashClose(d)
        try w.Destroy()
        try DirDelete(dir, true)
    }
}

; Pixel width a ListView needs for `text` in one of its cells (the list's
; font plus the cell's side margins).
PlCellNeed(lv, text) => SendMessage(0x1057, 0, StrPtr(String(text)), lv) + 12   ; LVM_GETSTRINGWIDTHW

; In every language: every list column between the first (names: a
; duplicate potion name carries its long id) and the last (which takes the
; rest of the row) shows each of its cells whole, and the status columns fit
; every status word they can show (Calibrate: "✓ recorded" was cut to
; "aufgenomm…" in de; Potions: "Desbloq…" in es / pt, "Déverro…" in fr).
Test_Polish_ListColumnsFit() {
    dir := UiDashTmp()
    d := ""
    try {
        bad := ""
        for code in I18n.Codes {
            I18n.Use(code)
            d := Dashboard(Config.Load(dir))
            for i, name in Dashboard.Pages
                d.SelectPage(i)
            ; the status words each column can show, whatever is recorded / locked now
            words := [[d.Ctrl("calibrate"), 2, [Chr(0x2713) " " I18n.T("recorded"), Chr(0x2713) " " I18n.T("automatic"), I18n.T("missing"), I18n.T("default (optional)")]]
                , [d.Ctrl("potions"), 2, [I18n.T("Locked"), I18n.T("Unlocked")]]]
            for e in words {
                cw := SendMessage(0x101D, e[2] - 1, 0, e[1])          ; LVM_GETCOLUMNWIDTH
                for t in e[3]
                    if (PlCellNeed(e[1], t) > cw)
                        bad .= " | " code ": '" t "' needs " PlCellNeed(e[1], t) " in " cw
            }
            for h, c in d._gui {
                if (c.Type != "ListView")
                    continue
                n := c.GetCount("Col")
                Loop c.GetCount() {
                    r := A_Index
                    Loop n - 2 {
                        col := A_Index + 1
                        t := c.GetText(r, col)
                        cw := SendMessage(0x101D, col - 1, 0, c)
                        if (t != "" && PlCellNeed(c, t) > cw) {
                            bad .= " | " code " list " c.Hwnd " col " col ": '" SubStr(t, 1, 30) "' needs " PlCellNeed(c, t) " in " cw
                            break 2
                        }
                    }
                }
            }
            UiDashClose(d), d := ""
        }
        AssertEq(bad, "", "every language")
    } finally {
        I18n.Use("en")
        UiDashClose(d)
        try DirDelete(dir, true)
    }
}
