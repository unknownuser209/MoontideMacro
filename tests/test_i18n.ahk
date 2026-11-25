#Requires AutoHotkey v2.0
; ---------------------------------------------------------------------------
; I18n (lib\I18n.ahk, lang\<code>.json): lookups, fallbacks, the shipped
; dictionaries, a dashboard / wizard built in Spanish vs English, the
; Settings > Look language picker and, in every language, that translated
; texts fit their fixed-size controls. Every test ends with I18n.Use("en").
; Helpers UiDashTmp / UiDashClose / UiDashPos / UiDashPageIdx: test_ui_dash.ahk.
; ---------------------------------------------------------------------------

I18nRoot() => RegExReplace(A_LineFile, "\\tests\\[^\\]+$", "")

; Bug hunt 2026-11-25: the Profiles page's export / import status, Home's
; "Up to date" / "Update check failed" note and the Go back question were
; English in every language (built outside lib\ui or from variables, so the
; coverage tests never saw them).
Test_I18n_ShareAndUpdateStatusTranslated() {
    keys := ["Exported {1} settings to exports\{2}", "Not exported: {1}", "Not imported: {1}"
        , "Not imported: the file could not be read", "Nothing imported: no settings found in that file"
        , "Imported {1} setting", "Imported {1} settings", "({1} skipped)", "Turned on: {1}"
        , "Up to date (v{1})", "Update check failed, see Log"
        , "Go back to v{1}? The macro restarts. Your settings and data stay."]
    for code in I18n.Codes {
        if (code = "en")
            continue
        m := I18n.LoadFile(code)
        for k in keys
            AssertTrue(m.Has(k), code ".json has '" k "'")
    }
    src := FileRead(I18nRoot() "\lib\App.ahk", "UTF-8")
    AssertTrue(InStr(src, 'I18n.F("Up to date (v{1})"') && InStr(src, 'I18n.T("Update check failed, see Log")'), "App translates the update notes")
    dir := A_Temp "\vesper_i18n_share_" A_TickCount "_" Random(1000, 9999)
    DirCreate(dir)
    try {
        I18n.Use("es")
        cfg := Config.Load(dir)
        FileAppend("[General]`r`nsellEvery=20`r`n[Bogus]`r`nx=1`r`n", dir "\in.ini", "UTF-8")
        r := Profiles.Import(cfg, dir "\in.ini")
        AssertEq(r.msg, I18n.F("Imported {1} setting", 1) " " I18n.F("({1} skipped)", 1), "import status in Spanish")
        AssertTrue(r.msg != "Imported 1 setting (1 skipped)", "not English: " r.msg)
        AssertEq(Profiles.Import(cfg, dir "\none.ini").msg, I18n.T("Not imported: the file could not be read"), "unreadable, in Spanish")
        e := Profiles.Export(cfg, "20261125000000")
        AssertEq(e.ok, 1, "exported")
        AssertTrue(!InStr(e.msg, "Exported "), "export status in Spanish: " e.msg)
        AssertTrue(InStr(e.msg, "moontide_settings_20261125.ini"), "names the file")
    } finally {
        I18n.Use("en")
        try DirDelete(dir, true)
    }
}

Test_I18n_FallbackAndUnknownLanguage() {
    try {
        AssertEq(I18n.Use("en"), "en", "English")
        AssertEq(I18n.Count, 0, "no dictionary in English")
        AssertEq(I18n.T("Save"), "Save", "English text as is")
        AssertEq(I18n.F("Step {1} of {2}", 2, 6), "Step 2 of 6", "Format in English")
        AssertEq(I18n.Use("xx"), "en", "unknown code -> English")
        AssertEq(I18n.Use(""), "en", "empty -> English")
        AssertEq(I18n.T("Save"), "Save", "still English")
        AssertEq(I18n.Use("ES"), "es", "any case")
        AssertTrue(I18n.Count >= 150, "Spanish dictionary loaded (" I18n.Count ")")
        AssertEq(I18n.T("Save"), "Guardar", "translated")
        AssertEq(I18n.T("No such text 12345"), "No such text 12345", "no translation -> the English text")
        AssertEq(I18n.T(42), 42, "a number passes through")
        AssertEq(I18n.T("STATUS"), StrUpper(I18n.T("Status")), "ALL CAPS found through the normal-case key")
        AssertEq(I18n.F("Step {1} of {2}", 2, 6), "Paso 2 de 6", "Format with a translation")
        AssertEq(I18n.CodeOf("Deutsch"), "de", "a listed name works too")
        AssertEq(I18n.IndexOf("fil"), 4, "index in the picker")
        AssertEq(I18n.IndexOf("klingon"), 1, "unknown -> English row")
        I18n.Raw := true
        AssertEq(I18n.T("Save"), "Save", "Raw keeps English")
        I18n.Raw := false
        AssertEq(I18n.Use("en"), "en", "back to English")
        AssertEq(I18n.T("Save"), "Save", "English again")
    } finally {
        I18n.Raw := false
        I18n.Use("en")
    }
}

; A missing or broken dictionary -> English (never a half-translated window).
Test_I18n_MissingOrBrokenFile() {
    old := I18n.Folder
    dir := A_Temp "\vesper_i18n_" A_TickCount "_" Random(1000, 9999)
    try {
        DirCreate(dir)
        I18n.Folder := dir
        AssertEq(I18n.Use("es"), "en", "missing file -> English")
        AssertEq(I18n.T("Save"), "Save", "nothing translated")
        FileAppend("{`"Save`": ", dir "\fr.json", "UTF-8-RAW")
        AssertEq(I18n.Use("fr"), "en", "broken JSON -> English")
        FileAppend("[1, 2]", dir "\de.json", "UTF-8-RAW")
        AssertEq(I18n.Use("de"), "en", "not an object -> English")
        FileAppend("{`"Save`": `"`", `"Stop`": `"  `", `"Start`": `"Go`"}", dir "\pt.json", "UTF-8-RAW")
        AssertEq(I18n.Use("pt"), "pt", "one usable entry")
        AssertEq(I18n.T("Save"), "Save", "empty value ignored")
        AssertEq(I18n.T("Stop"), "Stop", "blank value ignored")
        AssertEq(I18n.T("Start"), "Go", "usable value used")
    } finally {
        I18n.Folder := old
        I18n.Use("en")
        try DirDelete(dir, true)
    }
}

; Every shipped dictionary parses, has enough strings, no empty values, the
; same {n} placeholders as its key, and is UTF-8 without a BOM.
Test_I18n_EveryLanguageFileParses() {
    root := I18nRoot()
    AssertEq(I18n.Folder, root "\lang", "dictionaries live in lang\")
    AssertEq(I18n.Codes.Length, I18n.Names.Length, "a name per code")
    for code in I18n.Codes {
        if (code = "en")
            continue
        path := I18n.PathOf(code)
        AssertTrue(FileExist(path) != "", code ".json exists")
        f := FileOpen(path, "r")
        b := Buffer(3, 0)
        f.RawRead(b, 3)
        f.Close()
        AssertTrue(!(NumGet(b, 0, "UChar") = 0xEF && NumGet(b, 1, "UChar") = 0xBB), code ".json has no BOM")
        m := I18n.LoadFile(code)
        AssertTrue(m is Map, code ": a JSON object")
        AssertTrue(m.Count >= 150, code ": at least 150 strings (" m.Count ")")
        for k, v in m {
            AssertTrue(k is String && k != "", code ": key is text")
            AssertTrue(v is String && Trim(v) != "", code ": value of '" k "' is not empty")
            AssertEq(I18nHoles(v), I18nHoles(k), code ": placeholders of '" k "'")
        }
        AssertEq(I18n.Use(code), code, code " in use")
    }
    I18n.Use("en")
}

I18nHoles(s) {
    out := "", pos := 1
    while (pos := RegExMatch(s, "\{\d\}", &m, pos)) {
        out .= m[0]
        pos += m.Len
    }
    return out
}

; Built in Spanish the panel titles, hubs, buttons and status words are
; Spanish; built in English nothing changed (ids keep the English titles).
Test_I18n_DashboardSpanishAndEnglish() {
    dir := UiDashTmp()
    d := "", d2 := ""
    try {
        I18n.Use("es")
        d := Dashboard(Config.Load(dir))
        look := d.Ctrl("panelTitle:Look:Colours")
        AssertTrue(IsObject(look), "Look caption has an id")
        AssertEq(look.Text, StrUpper(I18n.T("Colours")), "panel title translated")
        AssertTrue(look.Text != "COLOURS", "not English")
        AssertEq(d.Ctrl("hub:Home").Text, "   " I18n.T("Home"), "sidebar hub translated")
        AssertEq(d.Ctrl("tab:Fishing").Text, I18n.T("Fishing"), "tab translated")
        AssertEq(d.Ctrl("desc:Settings").Text, I18n.T(Dashboard.Subtitles[UiDashPageIdx("Settings")]), "subtitle translated")
        d.SelectHub(Dashboard.HubOf("Look"))
        AssertEq(d.Ctrl("hubTitle").Text, I18n.T("Settings"), "hub title translated")
        AssertTrue(d.Ctrl("hubTitle").Text != "Settings", "hub title not English")
        AssertEq(d.Ctrl("tab:Settings").Text, I18n.T("General"), "General tab translated")
        d.SetStatus("Paused", "Fishing", "NORMAL", false, 1000, 3)
        AssertEq(d.Ctrl("pauseBtn1").Text, I18n.T("Resume"), "Resume translated")
        AssertEq(d._stState.Text, I18n.T("Paused"), "status word translated")
        AssertTrue(InStr(d._pill.Text, StrUpper(I18n.T("Paused"))), "pill translated")
        d.SetStatus("Running", "", "", false, 0, 0)
        AssertEq(d.Ctrl("pauseBtn1").Text, I18n.T("Pause"), "Pause translated")
        UiDashClose(d), d := ""

        I18n.Use("en")
        d2 := Dashboard(Config.Load(dir))
        AssertEq(d2.Ctrl("panelTitle:Look:Colours").Text, "COLOURS", "English title unchanged")
        AssertEq(d2.Ctrl("hub:Home").Text, "   Home", "English hub unchanged")
        AssertEq(d2.Ctrl("tab:Fishing").Text, "Fishing", "English tab unchanged")
        d2.SetStatus("Paused", "", "", false, 0, 0)
        AssertEq(d2.Ctrl("pauseBtn1").Text, "Resume", "English Resume")
        AssertEq(d2._stState.Text, "Paused", "English status word")
    } finally {
        I18n.Use("en")
        UiDashClose(d)
        UiDashClose(d2)
        try DirDelete(dir, true)
    }
}

; Settings > Look: the picker shows the saved language, Save (Look) writes UI.lang.
Test_I18n_LanguagePickerSaves() {
    dir := UiDashTmp()
    d := ""
    try {
        I18n.Use("en")
        cfg := Config.Load(dir)
        AssertEq(cfg.Get("UI.lang", ""), "en", "default UI.lang")
        d := Dashboard(cfg)
        dd := d.Ctrl("UI.lang")
        AssertEq(dd.Text, "English", "picker shows English")
        ; inside the Text card, below the font rows, above the card's end
        p := UiDashPos(d.Ctrl("panel:Look:Text")), q := UiDashPos(dd), t := UiDashPos(d.Ctrl("look:font:small"))
        AssertTrue(q.y > t.y && q.y + 24 <= p.y + p.h && q.x >= p.x && q.x + q.w <= p.x + p.w, "language row inside the Text card")
        AssertTrue(p.y + p.h <= 620, "Text card ends above the save bar")
        dd.Choose(2)
        AssertTrue(d.SavePage("Look"), "saved")
        AssertEq(Config.Load(dir).Get("UI.lang", ""), "es", "UI.lang written")
        AssertEq(I18n.Lang, "en", "the open window stays English until restart")
        d.RevertPage("Look")
        AssertEq(d.Ctrl("UI.lang").Text, I18n.Names[2], "reload shows the saved language")
    } finally {
        I18n.Use("en")
        UiDashClose(d)
        try DirDelete(dir, true)
    }
}

; The setup wizard in Spanish, then English unchanged.
Test_I18n_WizardTranslated() {
    dir := UiDashTmp()
    w := ""
    try {
        I18n.Use("es")
        w := SetupWizard(Config.Load(dir))
        AssertEq(w.Ctrl("title").Text, I18n.T("Choose your language"), "language title translated")
        AssertTrue(w.Ctrl("title").Text != "Choose your language", "not English")
        AssertEq(w.Ctrl("stepText").Text, "Paso 1 de 7", "step text translated")
        AssertEq(w.Ctrl("next").Text, I18n.T("Next"), "button translated")
        w.Next()
        AssertEq(w.Ctrl("title").Text, I18n.F("Welcome to {1}", Brand.Name), "title translated")
        AssertTrue(InStr(w.Ctrl("title").Text, "Bienvenido"), "Spanish welcome")
        AssertEq(w.Ctrl("next").Text, I18n.T("Start"), "Start translated")
        w.Next(), w.Next()
        AssertEq(w.Ctrl("title").Text, I18n.T("Private server"), "page title translated")
        w.Destroy(), w := ""
        I18n.Use("en")
        w := SetupWizard(Config.Load(dir))
        AssertEq(w.Ctrl("title").Text, "Choose your language", "English language title")
        AssertEq(w.Ctrl("stepText").Text, "Step 1 of 7", "English step text")
        AssertEq(w.Ctrl("next").Text, "Next", "English button")
        w.Next()
        AssertEq(w.Ctrl("title").Text, "Welcome to " Brand.Name, "English title")
        AssertEq(w.Ctrl("next").Text, "Start", "English Start")
    } finally {
        I18n.Use("en")
        try w.Destroy()
        try DirDelete(dir, true)
    }
}

; The wizard asks the language first: every language in its own name, the
; saved UI.lang lit; picking one saves UI.lang at once and the wizard's texts
; turn to it (the next page's title too); closing puts the app's language
; back and tells the app ("lang"). Picking the language in use rebuilds nothing.
Test_Wizard_LanguageFirst() {
    dir := UiDashTmp()
    dir2 := UiDashTmp()
    w := "", w2 := ""
    try {
        I18n.Use("en")
        AssertEq(SetupWizard.Pages[1], "Lang", "the language page is the first page")
        cfg := Config.Load(dir)
        got := [], done := []
        w := SetupWizard(cfg, Map("lang", (c) => got.Push(c), "done", (f) => done.Push(f)))
        AssertEq(w.Step, 1, "opens on the language page")
        AssertEq(w.Ctrl("title").Text, "Choose your language", "language title")
        AssertEq(w.Ctrl("back").Visible, false, "no Back on the first page")
        for i, code in I18n.Codes
            AssertEq(w.Ctrl("lang:" code).Value, code = "en" ? 1 : 0, "English lit by default (" code ")")
        vi := I18n.Names[I18n.IndexOf("vi")]
        AssertEq(vi, "Ti" Chr(0x1EBF) "ng Vi" Chr(0x1EC7) "t", "Vietnamese in its own name")
        AssertEq(w.PickLanguage(vi), "vi", "picked by name")
        AssertEq(Config.Load(dir).Get("UI.lang", ""), "vi", "UI.lang saved at once")
        AssertEq(I18n.Lang, "vi", "the wizard now speaks Vietnamese")
        AssertEq(w.Step, 1, "still on the language page")
        AssertEq(w.Ctrl("lang:vi").Value, 1, "Vietnamese lit")
        AssertEq(w.Ctrl("lang:en").Value, 0, "English not lit")
        d := I18n.LoadFile("vi")
        AssertEq(w.Ctrl("title").Text, d["Choose your language"], "language title in Vietnamese")
        AssertEq(w.Ctrl("next").Text, d["Next"], "Next in Vietnamese")
        AssertEq(w.Ctrl("stepText").Text, Format(d["Step {1} of {2}"], 1, 7), "step text in Vietnamese")
        AssertTrue(w.Next(), "Next")
        AssertEq(w.Step, 2, "Welcome page")
        AssertEq(w.Ctrl("title").Text, Format(d["Welcome to {1}"], Brand.Name), "next page's title in Vietnamese")
        AssertTrue(w.Ctrl("title").Text != "Welcome to " Brand.Name, "not English")
        AssertEq(w.Ctrl("next").Text, d["Start"], "Start in Vietnamese")
        w.Next()
        AssertEq(w.Ctrl("title").Text, d["Check your PC"], "Roblox check title in Vietnamese")
        w.Skip(), w := ""
        AssertEq(got.Length, 1, "the app is told once")
        AssertEq(got[1], "vi", "told the new language")
        AssertEq(done[1], 0, "skipped")
        AssertEq(I18n.Lang, "en", "the app's language put back on close")
        AssertEq(Config.Load(dir).Get("UI.lang", ""), "vi", "UI.lang kept")
        ; a saved language is lit; picking the one in use rebuilds nothing
        c2 := Config.Load(dir2)
        c2.Set("UI.lang", "fr"), c2.Save()
        got2 := []
        w2 := SetupWizard(c2, Map("lang", (c) => got2.Push(c)))
        AssertEq(w2.Ctrl("lang:fr").Value, 1, "the saved language is lit")
        AssertEq(w2.Ctrl("lang:en").Value, 0, "English not lit")
        t := w2.Ctrl("title")
        AssertEq(w2.PickLanguage("English"), "en", "English by name")
        AssertTrue(w2.Ctrl("title") == t, "same window (the language in use)")
        AssertEq(Config.Load(dir2).Get("UI.lang", ""), "en", "UI.lang saved")
        AssertEq(w2.Ctrl("lang:en").Value, 1, "English lit")
        AssertEq(w2.Ctrl("lang:fr").Value, 0, "French not lit")
        AssertEq(w2.PickLanguage("klingon"), "en", "unknown -> English")
        w2.Finish(), w2 := ""
        AssertEq(got2.Length, 0, "no language change to tell")
    } finally {
        I18n.Use("en")
        try w.Destroy()
        try w2.Destroy()
        try DirDelete(dir, true)
        try DirDelete(dir2, true)
    }
}

; Pixel size a Text control needs for `text` in its own font (single line or
; word-wrapped at width w).
I18nNeed(c, text, w, single) {
    hdc := DllCall("GetDC", "Ptr", c.Hwnd, "Ptr")
    old := DllCall("SelectObject", "Ptr", hdc, "Ptr", SendMessage(0x31, 0, 0, c.Hwnd), "Ptr")   ; WM_GETFONT
    rc := Buffer(16, 0)
    NumPut("Int", w, rc, 8)
    DllCall("DrawText", "Ptr", hdc, "Str", text, "Int", -1, "Ptr", rc, "UInt", 0x400 | 0x800 | (single ? 0x20 : 0x10))
    DllCall("SelectObject", "Ptr", hdc, "Ptr", old)
    DllCall("ReleaseDC", "Ptr", c.Hwnd, "Ptr", hdc)
    return {w: NumGet(rc, 8, "Int"), h: NumGet(rc, 12, "Int")}
}

; Text controls of a Gui in creation order: [{c, text, pos}].
I18nTexts(g) {
    out := []
    for h, c in g {
        if (c.Type = "Text")
            out.Push({c: c, text: c.Text, pos: UiDashPos(c)})
    }
    return out
}

; In every language: each TRANSLATED text fits its control (UI widths are
; fixed), every hub's tab strip ends inside the window, and the help tips
; still sit on a panel without anything over them.
Test_I18n_EveryLanguageFits() {
    dir := UiDashTmp()
    d := ""
    try {
        I18n.Use("en")
        d := Dashboard(Config.Load(dir))
        base := I18nTexts(d._gui)
        UiDashClose(d), d := ""
        inR := (a, b) => a.x >= b.x && a.y >= b.y && a.x + a.w <= b.x + b.w && a.y + a.h <= b.y + b.h
        ovR := (a, b) => !(a.x + a.w <= b.x || b.x + b.w <= a.x || a.y + a.h <= b.y || b.y + b.h <= a.y)
        for code in I18n.Codes {
            if (code = "en")
                continue
            I18n.Use(code)
            d := Dashboard(Config.Load(dir))
            now := I18nTexts(d._gui)
            AssertEq(now.Length, base.Length, code ": same controls as in English")
            changed := 0
            for i, e in now {
                if (e.text == base[i].text || StrLen(e.text) < 2)
                    continue
                changed++
                p := e.pos
                single := (ControlGetStyle(e.c.Hwnd) & 0x200) || p.h <= 22
                n := I18nNeed(e.c, e.text, p.w, single)
                AssertTrue(n.w <= p.w + 1 && n.h <= p.h + 1, code ": '" SubStr(e.text, 1, 40) "' needs " n.w "x" n.h " in " p.w "x" p.h)
            }
            AssertTrue(changed >= 100, code ": most texts translated (" changed ")")
            for hub in Dashboard.Hubs {
                last := UiDashPos(d.Ctrl("tab:" hub.pages[hub.pages.Length]))
                AssertTrue(last.x + last.w <= 1030, code ": " hub.name " tabs end at " (last.x + last.w))
            }
            for i, name in Dashboard.Pages {
                d.SelectPage(i)
                panels := []
                for c in d._pages[i].ctrls
                    if Theme.IsPanel(c)
                        panels.Push(UiDashPos(c))
                for c in d._pages[i].ctrls {
                    if (Theme.HelpText(c) = "")
                        continue
                    t := UiDashPos(c)
                    inside := false
                    for pn in panels
                        inside := inside || inR(t, pn)
                    AssertTrue(inside, code " " name ": help tip at " t.x "," t.y " sits on a panel")
                    for o in d._pages[i].ctrls {
                        if (o.Hwnd = c.Hwnd || !o.Visible || Theme.IsPanel(o))
                            continue
                        AssertTrue(!ovR(t, UiDashPos(o)), code " " name ": help tip at " t.x "," t.y " is not covered by '" SubStr(o.Text, 1, 20) "'")
                    }
                }
            }
            UiDashClose(d), d := ""
        }
    } finally {
        I18n.Use("en")
        UiDashClose(d)
        try DirDelete(dir, true)
    }
}

; Top sidebar in every language with the Menu font at 10 and at the largest
; size the Look page allows (28): no hub runs into another, the magnifier
; or the chip; every one is
; inside the window and the sidebar row, and each hub's text fits its button.
Test_I18n_TopRowFits() {
    oldSb := Theme.Sidebar, oldNav := Theme.Fonts["nav"], oldWa := Theme.WorkAreaFn, oldSc := Theme.Scale, oldLy := Theme.Layout
    dir := UiDashTmp()
    d := ""
    ovR := (a, b) => !(a.x + a.w <= b.x || b.x + b.w <= a.x || a.y + a.h <= b.y || b.y + b.h <= a.y)
    try {
        Theme.WorkAreaFn := () => {w: 3840, h: 2160}
        Theme.Scale := 100
        Theme.Layout := Map()
        Theme.Sidebar := "top"
        for fs in [10, 28] {
            Theme.Fonts["nav"] := ["s" fs " norm", "Segoe UI", "Muted"]
            for code in I18n.Codes {
                I18n.Use(code)
                d := Dashboard(Config.Load(dir))
                what := code " nav " fs
                all := []
                for i, c in d._nav {
                    if !c.Visible
                        continue
                    all.Push({c: c, n: "hub " i})
                    t := I18nNeed(c, c.Text, 9999, true), p := UiDashPos(c)
                    AssertTrue(t.w <= p.w && t.h <= p.h, what ": hub " i " text " t.w "x" t.h " fits " p.w "x" p.h)
                }
                all.Push({c: d.Ctrl("search:icon"), n: "magnifier"}, {c: d._chip, n: "chip"})
                for a in all {
                    p := UiDashPos(a.c)
                    AssertTrue(p.x >= 0 && p.x + p.w <= Dashboard.W && p.y >= 59 && p.y + p.h <= 107, what ": " a.n " inside the row: " p.x "," p.y "," p.w "," p.h)
                }
                for i, a in all {
                    for j, b in all {
                        if (i < j)
                            AssertTrue(!ovR(UiDashPos(a.c), UiDashPos(b.c)), what ": " a.n " and " b.n " overlap")
                    }
                }
                UiDashClose(d), d := ""
            }
        }
    } finally {
        Theme.Sidebar := oldSb, Theme.Fonts["nav"] := oldNav, Theme.WorkAreaFn := oldWa, Theme.Scale := oldSc, Theme.Layout := oldLy
        I18n.Use("en")
        UiDashClose(d)
        try DirDelete(dir, true)
    }
}

; Every I18n.T("...") / I18n.F("...") text written in lib\ui is in every
; language file, as a key or as the capitals of one (I18n.T upper-cases a
; translation for an all-caps text: "DRY RUN" comes from "Dry run").
; I18nKeepEnglish (below) lists texts left English on purpose.
Test_I18n_EveryUiStringTranslated() {
    keep := I18nKeepEnglish()
    texts := Map()
    Loop Files, I18nRoot() "\lib\ui\*.ahk" {
        src := FileRead(A_LoopFilePath, "UTF-8")
        pos := 1
        while (pos := RegExMatch(src, "I18n\.[TF]\(\s*`"((?:[^`"``\r\n]|``.)*)`"", &m, pos)) {
            s := StrReplace(m[1], "````", Chr(1))
            s := StrReplace(StrReplace(StrReplace(s, "``n", "`n"), "``t", "`t"), "```"", "`"")
            s := StrReplace(s, Chr(1), "``")
            if !keep.Has(s)
                texts[s] := A_LoopFileName
            pos += m.Len
        }
    }
    AssertTrue(texts.Count >= 100, "texts found in lib\ui (" texts.Count ")")
    for code in I18n.Codes {
        if (code = "en")
            continue
        m := I18n.LoadFile(code)
        caps := Map()
        for k in m
            caps[StrUpper(k)] := true
        bad := ""
        for s, file in texts {
            if !(m.Has(s) || (s == StrUpper(s) && caps.Has(s)))
                bad .= "`n  " file ": " s
        }
        AssertEq(bad, "", code ".json misses")
    }
}

; Texts left English on purpose, in every language (both coverage tests):
; game and brand names as the game shows them, units, the bot's command
; names and OK. A text without two letters in a row ("0", "%", "?") is
; never checked either.
I18nKeepEnglish() {
    m := Map()
    for s in ["Sol's RNG", "Moontide Macro", "Mari", "Jester", "Obby", "Memory Match", "Limbo (Eden)"   ; names
        , "pt", "px", "s", "min"                                                                      ; units
        , "OK"
        , "!status   !stats   !screenshot   !log`n!start   !stop   !pause   !resume   !help"]            ; bot commands
        m[s] := true
    return m
}

; Every text the helpers translate when they build a window (Theme.Label /
; Button / Check / Help / Panel / Window / Segmented / ListHeader / Confirm /
; EmptyHint, the dashboard's _Panel / _BoolField / _IntField / _StrField /
; _WarnOn / _Tr), written as a literal (or literals joined with ., Brand.Name
; or Chr(0xB7)) in lib\ui, plus the tables they read (page subtitles, hub
; and tab names, the Look labels, the wizard's titles and switches, every
; HelpTexts "?" text) is in every language file. A text built from variables
; at run time cannot be checked here.
Test_I18n_EveryHelperTextTranslated() {
    keep := I18nKeepEnglish()
    texts := Map()
    add := (s, where) => (!keep.Has(s) && RegExMatch(s, "[A-Za-z]{2}") && !texts.Has(s)) ? texts[s] := where : 0
    helpers := Map("I18n.T", [1], "I18n.F", [1], "Theme.Window", [1], "Theme.Label", [3], "Theme.Panel", [6]
        , "Theme.Help", [4], "Theme.Button", [3], "Theme.Check", [4], "Theme.Segmented", [4], "Theme.ListHeader", [5]
        , "Theme.Confirm", [2, 3, 4, 5], "Theme.EmptyHint", [3], "this._Panel", [5, 6], "this._IntField", [3, 6]
        , "this._StrField", [3], "this._BoolField", [3, 7], "this._WarnOn", [2, 3], "Dashboard._Tr", [1])
    Loop Files, I18nRoot() "\lib\ui\*.ahk" {
        src := I18nStripComments(FileRead(A_LoopFilePath, "UTF-8"))
        for name, idxs in helpers {
            pos := 1
            while (pos := InStr(src, name "(", true, pos)) {
                prev := pos > 1 ? SubStr(src, pos - 1, 1) : " "
                at := pos + StrLen(name)
                pos := at
                if RegExMatch(prev, "[\w.]")
                    continue
                args := I18nArgs(src, at)
                for k in idxs {
                    if (k <= args.Length)
                        for s in I18nTextsOf(args[k])
                            add(s, A_LoopFileName " " name)
                }
            }
        }
    }
    AssertTrue(texts.Count >= 300, "texts found in lib\ui (" texts.Count ")")
    ; the tables the helpers are given
    for s in Dashboard.Subtitles
        add(s, "Dashboard.Subtitles")
    for h in Dashboard.Hubs
        add(h.name, "Dashboard.Hubs")
    for p in Dashboard.Pages
        add(Dashboard.TabLabel(p), "Dashboard.TabLabel")
    for tbl in [Dashboard.LookBaseLabels, Dashboard.LookDerivedLabels, Dashboard.LookRoleLabels]
        for k, s in tbl
            add(s, "Dashboard.Look labels")
    for tbl in [Dashboard.LookFits, Dashboard.LookSides]
        for s in tbl
            add(s, "Dashboard.Look choices")
    for i, s in SetupWizard.Titles
        if (i != 2)                     ; page 2 shows I18n.F("Welcome to {1}", Brand.Name)
            add(s, "SetupWizard.Titles")
    for r in SetupWizard.RunKeys
        add(r[2], "SetupWizard.RunKeys")
    for k, s in HelpTexts.Map
        add(s, "HelpTexts " k)
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
                bad .= " | " where ": " SubStr(StrReplace(s, "`n", " / "), 1, 80)
        }
        AssertEq(bad, "", code ".json misses")
    }
}

; Source without ; comments (a ; at a line start or after a space or tab,
; outside quotes), lines kept.
I18nStripComments(src) {
    out := ""
    for line in StrSplit(StrReplace(src, "`r", ""), "`n") {
        q := "", res := "", i := 1, n := StrLen(line)
        while (i <= n) {
            ch := SubStr(line, i, 1)
            if (q != "") {
                res .= ch
                if (ch = "``" && i < n) {
                    res .= SubStr(line, i + 1, 1), i += 2
                    continue
                }
                if (ch = q)
                    q := ""
            } else {
                if (ch = "`"" || ch = "'")
                    q := ch
                else if (ch = ";" && (i = 1 || InStr(" `t", SubStr(line, i - 1, 1))))
                    break
                res .= ch
            }
            i++
        }
        out .= res "`n"
    }
    return out
}

; The top-level arguments of the call whose "(" is at `at` (text, untouched).
I18nArgs(src, at) {
    args := [], cur := "", depth := 0, q := "", i := at, n := StrLen(src)
    while (i <= n) {
        ch := SubStr(src, i, 1)
        if (q != "") {
            cur .= ch
            if (ch = "``") {
                cur .= SubStr(src, i + 1, 1), i += 2
                continue
            }
            if (ch = q)
                q := ""
        } else if (ch = "`"" || ch = "'") {
            q := ch, cur .= ch
        } else if InStr("([{", ch) {
            depth++
            if (depth > 1)
                cur .= ch
        } else if InStr(")]}", ch) {
            depth--
            if (depth = 0) {
                args.Push(cur)
                return args
            }
            cur .= ch
        } else if (ch = "," && depth = 1) {
            args.Push(cur), cur := ""
        } else
            cur .= ch
        i++
    }
    return args
}

; Texts of an argument: a literal (or literals joined), each literal item of
; an [array], or the two literal branches of cond ? "a" : "b". Else none.
I18nTextsOf(expr) {
    e := Trim(expr, " `t`r`n")
    if (SubStr(e, 1, 1) = "[" && SubStr(e, -1) = "]") {
        out := []
        for a in I18nArgs("(" SubStr(e, 2, -1) ")", 1) {
            t := I18nLiteral(a)
            if (t != "")
                out.Push(t)
        }
        return out
    }
    t := I18nLiteral(e)
    if (t != "")
        return [t]
    if RegExMatch(e, "s)^(.*?)\?(.*):(.*)$", &m) {
        out := []
        for part in [m[2], m[3]] {
            t := I18nLiteral(part)
            if (t != "")
                out.Push(t)
        }
        return out
    }
    return []
}

; "a" . 'b' . Brand.Name . Chr(0xB7) joined -> the text; "" when anything
; else is in it (a variable, a call) or it holds no literal.
I18nLiteral(expr) {
    e := Trim(expr, " `t`r`n")
    out := "", any := false, pos := 1, n := StrLen(e)
    while (pos <= n) {
        if !RegExMatch(e, "s)\G\s*(?:`"((?:[^`"``]|``.)*)`"|'((?:[^'``]|``.)*)'|(\.)|(Brand\.Name)|(Chr\(0xB7\)))", &m, pos)
            return ""
        if (m.Len = 0)
            return ""
        if (m.Pos[1])
            out .= I18nUnescape(m[1]), any := true
        else if (m.Pos[2])
            out .= I18nUnescape(m[2]), any := true
        else if (m.Pos[4])
            out .= Brand.Name
        else if (m.Pos[5])
            out .= Chr(0xB7)
        pos += m.Len
        if (Trim(SubStr(e, pos), " `t`r`n") = "")
            break
    }
    return any ? out : ""
}

I18nUnescape(s) {
    out := "", i := 1, n := StrLen(s)
    while (i <= n) {
        ch := SubStr(s, i, 1)
        if (ch = "``" && i < n) {
            nx := SubStr(s, i + 1, 1)
            out .= (nx = "n") ? "`n" : (nx = "t") ? "`t" : (nx = "r") ? "`r" : nx
            i += 2
        } else
            out .= ch, i++
    }
    return out
}
