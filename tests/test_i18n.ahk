#Requires AutoHotkey v2.0
; ---------------------------------------------------------------------------
; I18n (lib\I18n.ahk, lang\<code>.json): lookups, fallbacks, the shipped
; dictionaries, a dashboard / wizard built in Spanish vs English, the
; Settings > Look language picker and, in every language, that translated
; texts fit their fixed-size controls. Every test ends with I18n.Use("en").
; Helpers UiDashTmp / UiDashClose / UiDashPos / UiDashPageIdx: test_ui_dash.ahk.
; ---------------------------------------------------------------------------

I18nRoot() => RegExReplace(A_LineFile, "\\tests\\[^\\]+$", "")

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
        look := d.Ctrl("panelTitle:Settings:Look")
        AssertTrue(IsObject(look), "Look caption has an id")
        AssertEq(look.Text, StrUpper(I18n.T("Look")), "panel title translated")
        AssertTrue(look.Text != "LOOK", "not English")
        AssertEq(d.Ctrl("hub:Home").Text, "   " I18n.T("Home"), "sidebar hub translated")
        AssertEq(d.Ctrl("tab:Fishing").Text, I18n.T("Fishing"), "tab translated")
        AssertEq(d.Ctrl("desc:Settings").Text, I18n.T(Dashboard.Subtitles[UiDashPageIdx("Settings")]), "subtitle translated")
        d.SelectHub(5)
        AssertEq(d.Ctrl("hubTitle").Text, I18n.T("Setup"), "hub title translated")
        d.SetStatus("Paused", "Fishing", "NORMAL", false, 1000, 3)
        AssertEq(d.Ctrl("pauseBtn1").Text, I18n.T("Resume"), "Resume translated")
        AssertEq(d._stState.Text, I18n.T("Paused"), "status word translated")
        AssertTrue(InStr(d._pill.Text, StrUpper(I18n.T("Paused"))), "pill translated")
        d.SetStatus("Running", "", "", false, 0, 0)
        AssertEq(d.Ctrl("pauseBtn1").Text, I18n.T("Pause"), "Pause translated")
        UiDashClose(d), d := ""

        I18n.Use("en")
        d2 := Dashboard(Config.Load(dir))
        AssertEq(d2.Ctrl("panelTitle:Settings:Look").Text, "LOOK", "English title unchanged")
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

; Settings > Look: the picker shows the saved language, Save writes UI.lang.
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
        ; inside the Look panel, below the theme row, above the panel's end
        p := UiDashPos(d.Ctrl("panel:Settings:Look")), q := UiDashPos(dd), t := UiDashPos(d.Ctrl("UI.theme"))
        AssertTrue(q.y > t.y && q.y + 24 <= p.y + p.h && q.x >= p.x && q.x + q.w <= p.x + p.w, "language row inside the Look panel")
        AssertTrue(p.y + p.h <= 616, "Look panel ends above the save bar")
        dd.Choose(2)
        AssertTrue(d.SavePage("Settings"), "saved")
        AssertEq(Config.Load(dir).Get("UI.lang", ""), "es", "UI.lang written")
        AssertEq(I18n.Lang, "en", "the open window stays English until restart")
        d.RevertPage("Settings")
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
        AssertEq(w.Ctrl("title").Text, I18n.F("Welcome to {1}", Brand.Name), "title translated")
        AssertTrue(InStr(w.Ctrl("title").Text, "Bienvenido"), "Spanish welcome")
        AssertEq(w.Ctrl("stepText").Text, "Paso 1 de 6", "step text translated")
        AssertEq(w.Ctrl("next").Text, I18n.T("Start"), "button translated")
        w.Next(), w.Next()
        AssertEq(w.Ctrl("title").Text, I18n.T("Private server"), "page title translated")
        w.Destroy(), w := ""
        I18n.Use("en")
        w := SetupWizard(Config.Load(dir))
        AssertEq(w.Ctrl("title").Text, "Welcome to " Brand.Name, "English title")
        AssertEq(w.Ctrl("stepText").Text, "Step 1 of 6", "English step text")
        AssertEq(w.Ctrl("next").Text, "Start", "English button")
    } finally {
        I18n.Use("en")
        try w.Destroy()
        try DirDelete(dir, true)
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
