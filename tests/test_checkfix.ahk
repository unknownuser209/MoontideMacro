#Requires AutoHotkey v2.0
; ---------------------------------------------------------------------------
; Fixes from the full check of 2026-11-19 (.superpowers\sdd\2026-11-18-themes-
; layout\check-findings.md): the wizard reopened mid-pick, card frames at
; 115 / 130 %, the Discord header, "?" after translated labels, button
; padding, the tab underline of a hidden page and the language dropdown.
; Every test builds its windows hidden and ends with I18n.Use("en").
; Helpers UiDashTmp / UiDashClose / UiDashPos: test_ui_dash.ahk; I18nNeed:
; test_i18n.ahk.
; ---------------------------------------------------------------------------

; Help > Check & help opens the wizard again while a language picked in it
; is not yet told (Destroy without Skip / Finish): the app's language comes
; back, the pick is dropped (nothing told, a late pick does nothing) and
; Destroy names it so the app can still restart into it.
Test_Wizard_DestroyWhilePickPending() {
    dir := UiDashTmp()
    w := ""
    try {
        I18n.Use("en")
        got := [], done := []
        w := SetupWizard(Config.Load(dir), Map("lang", (c) => got.Push(c), "done", (f) => done.Push(f)))
        AssertEq(w.PickLanguage("de"), "de", "picked German")
        AssertEq(I18n.Lang, "de", "the wizard speaks German")
        AssertEq(w.Destroy(), "de", "Destroy names the dropped pick")
        AssertEq(I18n.Lang, "en", "the app's language is back")
        AssertEq(got.Length, 0, "nothing told")
        AssertEq(done.Length, 0, "no done either")
        AssertEq(w.PickLanguage("fr"), "en", "a late pick (its timer) does nothing")
        AssertEq(I18n.Lang, "en", "still English")
        AssertEq(w.Destroy(), "", "a second Destroy drops nothing")
        AssertEq(Config.Load(dir).Get("UI.lang", ""), "de", "UI.lang keeps the pick")
        w := ""
        ; no pick: Destroy changes nothing
        w := SetupWizard(Config.Load(dir))
        AssertEq(w.Destroy(), "", "nothing picked")
        AssertEq(I18n.Lang, "en", "English")
        w := ""
        ; closed normally first: Destroy (from _Close) drops nothing
        got2 := []
        w := SetupWizard(Config.Load(dir), Map("lang", (c) => got2.Push(c)))
        w.PickLanguage("es")
        w.Skip()
        AssertEq(got2.Length, 1, "Skip tells the pick")
        AssertEq(I18n.Lang, "en", "and puts English back")
        AssertEq(w.Destroy(), "", "nothing left to drop")
        w := ""
    } finally {
        I18n.Use("en")
        try w.Destroy()
        try DirDelete(dir, true)
    }
}

; Real (Gui px) rectangle of a control.
CfRect(c) {
    c.GetPos(&x, &y, &w, &h)
    return {x: x, y: y, w: w, h: h, r: x + w, b: y + h}
}

; At 115 and 130 %: every card frame of every page (every sidebar side) lies
; inside the client area, its fill leaves at least 1 px of frame on every
; side (the fill was rounded on its own and covered the right / bottom
; line: x 204 w 808 -> frame 265..1315, fill 267..1315), and no other
; control of the page sits on the frame line.
Test_Scale_CardFramesWhole() {
    oldSc := Theme.Scale, oldWa := Theme.WorkAreaFn, oldSb := Theme.Sidebar, oldLy := Theme.Layout
    dir := UiDashTmp()
    d := ""
    try {
        Theme.WorkAreaFn := () => {w: 3840, h: 2160}
        Theme.Layout := Map()
        for side in ["left", "right", "top"] {
            for sc in [115, 130] {
                Theme.Sidebar := side, Theme.Scale := sc
                d := Dashboard(Config.Load(dir))
                AssertEq(Theme.Scale, sc, "built at " sc)
                sz := d.ShownSize()
                bad := ""
                for i, name in Dashboard.Pages {
                    d.SelectPage(i)
                    for card in d.Cards(name) {
                        if !card.frame.Visible
                            continue
                        f := CfRect(card.frame), n := CfRect(card.fill)
                        what := side " " sc " " card.id
                        if (f.x < 0 || f.y < 0 || f.r > sz.w || f.b > sz.h)
                            bad .= " | " what ": frame " f.x "," f.y ".." f.r "," f.b " outside " sz.w "x" sz.h
                        if (n.x < f.x + 1 || n.y < f.y + 1 || n.r > f.r - 1 || n.b > f.b - 1)
                            bad .= " | " what ": fill " n.x "," n.y ".." n.r "," n.b " covers frame " f.x "," f.y ".." f.r "," f.b
                        for o in d._pages[i].ctrls {
                            if (o = card.frame || o = card.fill || !o.Visible)
                                continue
                            q := CfRect(o)
                            if (q.w = 0 || q.h = 0 || q.r <= f.x || q.x >= f.r || q.b <= f.y || q.y >= f.b)
                                continue
                            if (q.x < n.x || q.y < n.y || q.r > n.r || q.b > n.b)
                                bad .= " | " what ": " o.Type " '" SubStr(o.Text, 1, 16) "' " q.x "," q.y ".." q.r "," q.b " on the frame line"
                        }
                        if (StrLen(bad) > 900)
                            break 2
                    }
                }
                AssertEq(bad, "", side " " sc " %")
                UiDashClose(d), d := ""
            }
        }
    } finally {
        Theme.Scale := oldSc, Theme.WorkAreaFn := oldWa, Theme.Sidebar := oldSb, Theme.Layout := oldLy
        UiDashClose(d)
        try DirDelete(dir, true)
    }
}

; Help > Dev tools opened outside the dev copy (its tab is not shown): no
; underline (it sat under Credits); Credits: under Credits.
Test_Tabs_UnderlineOnlyUnderAShownTab() {
    dir := UiDashTmp()
    d := ""
    try {
        I18n.Use("en")
        d := Dashboard(Config.Load(dir))
        AssertTrue(!d.PageShown("Dev tools"), "a test folder is not the dev copy")
        u := d.Ctrl("tabUnderline")
        d.SelectPage(Dashboard.PageIndex("Credits"))
        Anim.Stop("underline")
        AssertTrue(u.Visible, "under Credits")
        AssertEq(UiDashPos(u).x, UiDashPos(d.Ctrl("tab:Credits")).x, "at the Credits tab")
        d.SelectPage(Dashboard.PageIndex("Dev tools"))
        AssertEq(d.ActivePage, "Dev tools", "opened")
        AssertTrue(!d.Ctrl("tab:Dev tools").Visible, "its tab is not shown")
        AssertTrue(!u.Visible, "no underline under another tab")
        d.SelectPage(Dashboard.PageIndex("Calibrate"))
        Anim.Stop("underline")
        AssertTrue(u.Visible, "back under a shown tab")
        AssertEq(UiDashPos(u).x, UiDashPos(d.Ctrl("tab:Calibrate")).x, "at the Calibrate tab")
        d._dev := true
        d.SelectHub(1)
        d.SelectPage(Dashboard.PageIndex("Dev tools"))
        Anim.Stop("underline")
        AssertTrue(d.Ctrl("tab:Dev tools").Visible, "dev copy: the tab shows")
        AssertTrue(u.Visible, "and has the underline")
        AssertEq(UiDashPos(u).x, UiDashPos(d.Ctrl("tab:Dev tools")).x, "at the Dev tools tab")
    } finally {
        UiDashClose(d)
        try DirDelete(dir, true)
    }
}

; Settings > Look: every language name fits the language dropdown (text,
; the arrow and a margin), at 100 and 130 %.
Test_Look_LanguageDropdownFits() {
    oldSc := Theme.Scale, oldWa := Theme.WorkAreaFn
    dir := UiDashTmp()
    d := ""
    try {
        Theme.WorkAreaFn := () => {w: 3840, h: 2160}
        for sc in [100, 130] {
            Theme.Scale := sc
            d := Dashboard(Config.Load(dir))
            dd := d.Ctrl("UI.lang")
            p := UiDashPos(dd)
            arrow := DllCall("GetSystemMetrics", "Int", 2)          ; SM_CXVSCROLL
            for name in I18n.Names {
                n := I18nNeed(dd, name, 9999, true)
                AssertTrue(n.w + arrow + 8 <= p.w, sc " %: '" name "' needs " (n.w + arrow + 8) " in " p.w)
            }
            UiDashClose(d), d := ""
        }
    } finally {
        Theme.Scale := oldSc, Theme.WorkAreaFn := oldWa
        UiDashClose(d)
        try DirDelete(dir, true)
    }
}

; In every language: every "?" of every page shows (16 x 16, not hidden) and
; sits after the real width of any label on its row to its left: a "?" made
; from the English width sat on the translated text, and one whose label
; was too long went hidden ("Aura rarer than 1 in" in fil / pt, "Always clip
; classes" in de). Left-aligned single-line texts only (a centred or right
; text, an edit, a list are measured by other tests).
Test_Help_AfterTranslatedLabels() {
    dir := UiDashTmp()
    d := ""
    try {
        for code in I18n.Codes {
            I18n.Use(code)
            d := Dashboard(Config.Load(dir))
            bad := ""
            for i, name in Dashboard.Pages {
                ctrls := d._pages[i].ctrls
                for h in ctrls {
                    if (Theme.HelpText(h) = "")
                        continue
                    t := UiDashPos(h)
                    if (d._hidden.Has(h.Hwnd) || t.w < 16 || t.h < 16) {
                        bad .= " | " name ": '?' at " t.x "," t.y " hidden or " t.w "x" t.h
                        continue
                    }
                    for o in ctrls {
                        if (o.Type != "Text" || o = h || d._hidden.Has(o.Hwnd) || Theme.IsPanel(o) || Theme.HelpText(o) != "" || StrLen(o.Text) < 2)
                            continue
                        q := UiDashPos(o)
                        if (q.h > 22 || q.x >= t.x || q.y + q.h <= t.y || t.y + t.h <= q.y || (ControlGetStyle(o.Hwnd) & 0x3))
                            continue
                        n := I18nNeed(o, o.Text, 9999, true)
                        if (q.x + n.w > t.x - 2)
                            bad .= " | " name ": '" SubStr(o.Text, 1, 30) "' ends at " (q.x + n.w) ", its '?' at " t.x
                    }
                }
            }
            AssertEq(bad, "", code)
            UiDashClose(d), d := ""
        }
    } finally {
        I18n.Use("en")
        UiDashClose(d)
        try DirDelete(dir, true)
    }
}

; In every language: every Theme.Button of the dashboard (every page, the
; header, the sidebar) and of the setup wizard (every page) keeps
; Theme.BtnPad px clear on each side of its text (a long translation gets a
; smaller font; one still too wide needs a shorter translation).
Test_Buttons_TextPadded() {
    dir := UiDashTmp()
    d := "", w := ""
    try {
        for code in I18n.Codes {
            I18n.Use(code)
            d := Dashboard(Config.Load(dir))
            bad := CfButtonsBad(d._gui, code " dashboard")
            ; the sidebar's simple-mode button (both states) and the dry-run chip
            for simple in [true, false] {
                d.SetSimple(simple)
                for c in [d.Ctrl("simpleMode"), d._chip] {
                    p := UiDashPos(c), n := I18nNeed(c, c.Text, 9999, true)
                    if (n.w + 2 * Theme.BtnPad > p.w || n.h > p.h)
                        bad .= " | " code ": '" c.Text "' needs " (n.w + 2 * Theme.BtnPad) "x" n.h " in " p.w "x" p.h
                }
            }
            UiDashClose(d), d := ""
            w := SetupWizard(Config.Load(dir))
            Loop SetupWizard.Steps {
                bad .= CfButtonsBad(w._gui, code " wizard " A_Index)
                if (A_Index < SetupWizard.Steps)
                    w._Show(A_Index + 1)
            }
            w.Destroy(), w := ""
            AssertEq(bad, "", code)
        }
    } finally {
        I18n.Use("en")
        UiDashClose(d)
        try w.Destroy()
        try DirDelete(dir, true)
    }
}

; " | what: 'text' needs N in W" for each button of g whose text is not padded.
CfButtonsBad(g, what) {
    bad := ""
    for h, c in g {
        if !Theme.IsButton(c) || c.Text = ""
            continue
        p := UiDashPos(c)
        pad := Theme.IsScaled(g) ? Theme.S(Theme.BtnPad) : Theme.BtnPad
        n := I18nNeed(c, c.Text, 9999, true)
        if (n.w + 2 * pad > p.w || n.h > p.h)
            bad .= " | " what ": '" c.Text "' needs " (n.w + 2 * pad) "x" n.h " in " p.w "x" p.h
    }
    return bad
}

; Discord & Clips > Discord, in every language at 100 and 130 %: no two
; column captions overlap, each one's text fits its caption (width and
; height, in the font it ended with), none overlaps the title or a row
; control, neighbours in a row keep a gap, and the event captions are
; translated (not the old 28 px codes).
Test_Webhooks_HeaderCaptionsFit() {
    oldSc := Theme.Scale, oldWa := Theme.WorkAreaFn
    dir := UiDashTmp()
    d := ""
    ovR := (a, b) => !(a.x + a.w <= b.x || b.x + b.w <= a.x || a.y + a.h <= b.y || b.y + b.h <= a.y)
    try {
        Theme.WorkAreaFn := () => {w: 3840, h: 2160}
        for sc in [100, 130] {
            Theme.Scale := sc
            for code in I18n.Codes {
                I18n.Use(code)
                d := Dashboard(Config.Load(dir))
                d.SelectPage(Dashboard.PageIndex("Webhooks"))
                caps := d._hookCaps
                what := code " " sc " %"
                AssertEq(caps.Length, 4 + Dashboard.EventCaps.Length, what ": a caption per column")
                for j, s in Dashboard.EventCaps
                    AssertEq(caps[4 + j].Text, Dashboard.EventCap(s), what ": event caption " j " translated")
                bad := ""
                for i, a in caps {
                    p := UiDashPos(a)
                    n := I18nNeed(a, a.Text, 9999, true)
                    if (n.w > p.w || n.h > p.h)
                        bad .= " | '" a.Text "' needs " n.w "x" n.h " in " p.w "x" p.h
                    for j, b in caps
                        if (i < j && ovR(p, UiDashPos(b)))
                            bad .= " | '" a.Text "' overlaps '" b.Text "'"
                    for o in [d.Ctrl("panelTitle:Webhooks:Webhooks"), d.Ctrl("hook1.name"), d.Ctrl("hook1.men"), d.Ctrl("hook1.test"), d.Ctrl("hook1.ev1")._box, d.Ctrl("hook1.ev12")._box]
                        if ovR(p, UiDashPos(o))
                            bad .= " | '" a.Text "' overlaps a control at " UiDashPos(o).x "," UiDashPos(o).y
                }
                ; neighbours in a caption row (two columns apart) keep a
                ; visible gap between their texts (fil "Mga quest" and "Mga
                ; error" nearly touched)
                gap := Round(6 * sc / 100)
                Loop Dashboard.EventCaps.Length - 2 {
                    a := caps[4 + A_Index], b := caps[6 + A_Index]
                    pa := UiDashPos(a), pb := UiDashPos(b)
                    wa := I18nNeed(a, a.Text, 9999, true).w, wb := I18nNeed(b, b.Text, 9999, true).w
                    if ((pb.x + (pb.w - wb) / 2) - (pa.x + (pa.w + wa) / 2) < gap)
                        bad .= " | '" a.Text "' and '" b.Text "' less than " gap " px apart"
                }
                AssertEq(bad, "", what)
                UiDashClose(d), d := ""
            }
        }
    } finally {
        Theme.Scale := oldSc, Theme.WorkAreaFn := oldWa
        I18n.Use("en")
        UiDashClose(d)
        try DirDelete(dir, true)
    }
}

; Texts made at run time (status lines, dropdown rows, list cells, the
; tables the pages read) go through I18n.T / I18n.F; every one is in every
; language file: each literal inside the first argument of an I18n.T / F
; call anywhere in lib\ (both branches of a ? :, across lines), plus the
; tables (Discord captions, Stats rows, the Check summary patterns, the clip
; app tips, every calibration "what to hover" and the profiles' names and
; descriptions). Then a German dashboard shows a few of them translated.
Test_I18n_RuntimeTextsTranslated() {
    texts := CfRuntimeTexts()
    for code in I18n.Codes {
        if (code = "en")
            continue
        m := I18n.LoadFile(code)
        caps := Map()
        for k in m
            caps[StrUpper(k)] := true
        bad := ""
        for s, where in texts {
            if !(m.Has(s) || (s == StrUpper(s) && caps.Has(s)))
                bad .= " | " where ": " SubStr(StrReplace(s, "`n", " / "), 1, 90)
        }
        AssertEq(bad, "", code ".json misses")
    }
    ; shown translated
    dir := UiDashTmp()
    d := ""
    try {
        I18n.Use("de")
        de := I18n.LoadFile("de")
        d := Dashboard(Config.Load(dir))
        AssertTrue(InStr(d.Ctrl("simpleMode").Text, StrUpper(de["Simple mode"])), "simple mode: " d.Ctrl("simpleMode").Text)
        st := d.Ctrl("calStatus").Text
        AssertTrue(RegExMatch(st, "^(\d+)", &n) && st == Format(de["{1} of {2} steps ready"], n[1], Calibrate.Steps().Length), "calibrate status: " st)
        lv := d.Ctrl("calibrate")
        AssertEq(lv.GetText(2, 3), de[Calibrate.Steps()[2]["prompt"]], "a what-to-hover cell")
        AssertEq(d.Ctrl("calWindowed").Text, de[d.cfg.Get("General.windowed", 0) = 1 ? "Yes" : "No"], "windowed dropdown")
        AssertEq(d.Ctrl("profile:AFK fishing").Text, de["AFK fishing"], "profile button")
        AssertEq(d.Ctrl("privateServerMask").Text, de["(not set)"], "private server mask")
    } finally {
        I18n.Use("en")
        UiDashClose(d)
        try DirDelete(dir, true)
    }
}

; Map text -> where, of the texts Test_I18n_RuntimeTextsTranslated checks.
CfRuntimeTexts() {
    keep := I18nKeepEnglish()
    texts := Map()
    add := (s, where) => (!keep.Has(s) && RegExMatch(s, "[A-Za-z]{2}") && !texts.Has(s)) ? texts[s] := where : 0
    Loop Files, I18nRoot() "\lib\*.ahk", "R" {
        src := I18nStripComments(FileRead(A_LoopFilePath, "UTF-8"))
        for name in ["I18n.T", "I18n.F"] {
            pos := 1
            while (pos := InStr(src, name "(", true, pos)) {
                prev := pos > 1 ? SubStr(src, pos - 1, 1) : " "
                at := pos + StrLen(name)
                pos := at
                if RegExMatch(prev, "[\w.]")
                    continue
                args := I18nArgs(src, at)
                if !args.Length
                    continue
                ; a literal used as a key (x["prompt"]) or compared (c.Text = "FFFFFF") is not a text
                p := 1
                while (p := RegExMatch(args[1], "`"((?:[^`"``]|``.)*)`"", &m, p)) {
                    before := RTrim(SubStr(args[1], 1, p - 1), " `t`r`n")
                    if !RegExMatch(before, "[\[=<>]$")
                        add(I18nUnescape(m[1]), A_LoopFileName)
                    p += m.Len
                }
            }
        }
    }
    AssertTrue(texts.Count >= 150, "texts found in lib (" texts.Count ")")
    for s in Dashboard.EventCaps
        add(s, "Dashboard.EventCaps")
    for r in Dashboard.StatRows
        add(r[2], "Dashboard.StatRows")
    for s in Dashboard.CheckCounts
        add(s, "Dashboard.CheckCounts")
    for k, s in Dashboard.ClipAppTips
        add(s, "Dashboard.ClipAppTips")
    for s in Calibrate.Steps()
        add(s["fmt"] != "" ? s["fmt"] : s["prompt"], "Calibrate.Steps " s["id"])
    for n in Profiles.Names {
        add(n, "Profiles.Names")
        add(Profiles.Description(n), "Profiles.Description")
    }
    return texts
}
