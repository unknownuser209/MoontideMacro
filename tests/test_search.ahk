#Requires AutoHotkey v2.0
; Tests for lib\ui\Search.ahk and the dashboard search box (jump + flash).
; Dashboards are built hidden; scratch folders under A_Temp. Uses UiDashTmp /
; UiDashClose from test_ui_dash.ahk (same script).
#Include ..\lib\ui\Search.ahk

; The query's first result as "text|page|card".
SrFirst(d, q) {
    r := d.SearchFor(q)
    return r.Length ? r[1].text "|" r[1].page "|" r[1].card : ""
}

SrIndex(res, text) {
    for i, r in res {
        if (r.text = text)
            return i
    }
    return 0
}

SrHas(res, page, card) {
    for r in res {
        if (r.page = page && r.card = card)
            return true
    }
    return false
}

Test_Search_Pure() {
    idx := []
    Search.Add(idx, "Auto-rejoin and anti-AFK", "label", "Settings", "Settings:Recovery")
    Search.Add(idx, "Rejoins you after a crash.", "help", "Settings", "Settings:Recovery")
    Search.Add(idx, "Recovery", "title", "Settings", "Settings:Recovery")
    Search.Add(idx, "Café menu", "label", "Run", "Run:#1")
    r := Search.Find(idx, "rejoin")
    AssertEq(r.Length, 2, "two entries start a word with rejoin")
    AssertEq(r[1].text, "Auto-rejoin and anti-AFK", "label before help")
    AssertTrue(r[1].score > r[2].score, "label scores above help")
    AssertEq(Search.Find(idx, "RECOV")[1].text, "Recovery", "case-insensitive prefix, title")
    AssertEq(Search.Find(idx, "cafe").Length, 1, "accent folded in the entry")
    AssertEq(Search.Find(idx, "café").Length, 1, "accent folded in the query")
    AssertEq(Search.Find(idx, "ejoin").Length, 0, "a word must START with the query word")
    ; bad input never throws
    for q in ["", "   ", "!!!", "(((", "\", "*", "a|b", "[", Chr(0x1F50D), StrReplace(Format("{:3000}", ""), " ", "x"), "zz zz zz zz zz zz zz zz zz zz"]
        AssertTrue(Search.Find(idx, q) is Array, "no throw for a bad query")
    AssertEq(Search.Find(idx, 42).Length, 0, "a number query finds nothing, no throw")
    AssertEq(Search.Find("", "x").Length, 0, "a bad index finds nothing")
    ; max
    big := []
    Loop 20
        Search.Add(big, "Thing " A_Index, "label", "P", "P:" A_Index)
    AssertEq(Search.Find(big, "thing").Length, 8, "default max 8")
    AssertEq(Search.Find(big, "thing", 3).Length, 3, "max 3")
    ; a shorter entry wins ties
    t := []
    Search.Add(t, "Sound on rare biome", "label", "P", "P:1")
    Search.Add(t, "Sound", "label", "P", "P:2")
    AssertEq(Search.Find(t, "sound")[1].text, "Sound", "shorter entry first")
    ; the same shown text on the same card is listed once
    u := []
    Search.Add(u, "Rejoin", "label", "P", "P:1", "Reingreso")
    Search.Add(u, "Reingreso", "label", "P", "P:1", "Reingreso")
    AssertEq(Search.Find(u, "re").Length, 1, "one row per shown text and card")
    AssertEq(Search.Find(u, "rejoin")[1].text, "Reingreso", "the shown text is listed")
}

Test_Search_Rank() {
    dir := UiDashTmp()
    d := ""
    try {
        d := Dashboard(Config.Load(dir))
        r := d.SearchFor("rejoin")
        AssertTrue(r.Length >= 2, "rejoin: label and help found")
        k := SrIndex(r, "Auto-rejoin and anti-AFK")
        AssertEq(k, 1, "a setting's label comes before a read-only label (Stats' Rejoins)")
        AssertEq(r[k].page "|" r[k].card, "Settings|Settings:Recovery", "on the General page, Recovery card")
        AssertTrue(r[k].score >= 20000 && r[k].score < 30000, "it is a label")
        for i, e in r {
            if (e.score < 20000)
                AssertTrue(i > k, "a lower-ranked entry is listed after the label")
        }
        AssertTrue(r.Length <= 8, "at most 8 rows")
        AssertTrue(d.Ctrl("search:list").Visible, "the list shows")
        AssertTrue(!d.Ctrl("search:none").Visible, "no none note")
        ; masked fields are never indexed
        for e in d.SearchFor("discord.com")
            AssertTrue(!InStr(e.text, "api/webhooks"), "no webhook URL in a result")
        AssertEq(d.SearchFor("").Length, 0, "empty query: no results")
        AssertTrue(!d.Ctrl("search:list").Visible, "empty query hides the list")
    } finally {
        UiDashClose(d)
        try DirDelete(dir, true)
    }
}

Test_Search_TwoWords() {
    dir := UiDashTmp()
    d := ""
    try {
        d := Dashboard(Config.Load(dir))
        AssertTrue(SrHas(d.SearchFor("vip routes"), "Settings", "Settings:Routes"), "vip routes finds the VIP gamepass routes switch")
        AssertTrue(SrHas(d.SearchFor("routes vip"), "Settings", "Settings:Routes"), "routes vip does too")
        AssertEq(SrFirst(d, "vip routes"), "VIP gamepass routes|Settings|Settings:Routes", "and it is first")
    } finally {
        UiDashClose(d)
        try DirDelete(dir, true)
    }
}

Test_Search_Translated() {
    dir := UiDashTmp()
    d := ""
    try {
        I18n.Use("es")
        AssertEq(I18n.T("Auto-rejoin and anti-AFK"), "Auto-reingreso y anti-AFK", "the Spanish label is in the dictionary")
        d := Dashboard(Config.Load(dir))
        AssertTrue(SrHas(d.SearchFor("reingreso"), "Settings", "Settings:Recovery"), "the translated word finds the card")
        r := d.SearchFor("rejoin")
        AssertTrue(SrHas(r, "Settings", "Settings:Recovery"), "the English word finds the same card")
        AssertTrue(SrIndex(r, "Auto-reingreso y anti-AFK") > 0, "the row shows the translated text")
    } finally {
        I18n.Use("en")
        UiDashClose(d)
        try DirDelete(dir, true)
    }
}

Test_Search_Go() {
    dir := UiDashTmp()
    d := ""
    try {
        d := Dashboard(Config.Load(dir))
        r := d.SearchFor("webhook")
        AssertTrue(r.Length >= 1, "webhook has a result")
        k := 0
        for i, e in r {
            if (e.page = "Webhooks") {
                k := i
                break
            }
        }
        AssertTrue(k > 0, "a result on the Webhooks page")
        d.SelectHub(1)
        AssertEq(d.ActivePage, "Run", "start on Home")
        d.SearchGo(k)
        AssertEq(d.ActivePage, "Webhooks", "the Discord page is open")
        AssertEq(Dashboard.Hubs[d.ActiveHub].name, "Discord & Clips", "in the Discord & Clips hub")
        AssertTrue(d.Flashing, "the flash timer is running")
        AssertTrue(!d.Ctrl("search:list").Visible, "the list closes")
        ; the frame is four 2 px strips round the card, in no card
        AssertEq(d._flash.ctrls.Length, 4, "four edge strips")
        for c in d._flash.ctrls {
            AssertEq(d.CardOf(c), "", "a strip is in no card")
            p := Theme.Pos(c)
            AssertTrue(p.w = 2 || p.h = 2, "2 px thick")
        }
        ; a bad index does nothing; a second jump replaces the flash
        d.SearchGo(99)
        d.SearchGo(0)
        d.SearchGo("x")
        d.SearchFor("webhook")
        d.SearchGo(k)
        AssertEq(d._flash.ctrls.Length, 4, "one flash at a time")
        ; the window goes away mid-flash: the timer is harmless
        UiDashClose(d)
        d := ""
        Sleep(300)
    } finally {
        UiDashClose(d)
        try DirDelete(dir, true)
    }
}

Test_Search_None() {
    dir := UiDashTmp()
    d := ""
    try {
        d := Dashboard(Config.Load(dir))
        r := d.SearchFor("zzzz")
        AssertEq(r.Length, 0, "no results")
        AssertTrue(d.Ctrl("search:none").Visible, "No setting matches shows")
        AssertTrue(!d.Ctrl("search:list").Visible, "the list is hidden")
        d.SearchFor("rejoin")
        AssertTrue(!d.Ctrl("search:none").Visible, "the note goes when something matches")
        d.SearchClear()
        AssertTrue(!d.Ctrl("search:none").Visible && !d.Ctrl("search:list").Visible, "Escape clears both")
    } finally {
        UiDashClose(d)
        try DirDelete(dir, true)
    }
}

; Right and top sidebar: the search controls are inside the window and clear of
; the hubs; top mode shows the box only after the magnifier (or Ctrl+F) opens it.
Test_Search_Sides() {
    SbEach((side, d) => SrCheckSide(side, d), ["right", "top"])
}

SrCheckSide(side, d) {
    ovR := (a, b) => !(a.x + a.w <= b.x || b.x + b.w <= a.x || a.y + a.h <= b.y || b.y + b.h <= a.y)
    gw := Dashboard.W, gh := Dashboard.H + Dashboard.PageShift(side).extraH
    box := d.Ctrl("search:box")
    AssertTrue(IsObject(box), side ": the box exists")
    d.SearchFor("rejoin")
    for id in ["search:box", "search:list", "search:none"] {
        p := UiDashPos(d.Ctrl(id))
        AssertTrue(p.x >= 0 && p.y >= 0 && p.x + p.w <= gw && p.y + p.h <= gh, side ": " id " inside the window")
    }
    for r in d._sRows {
        p := UiDashPos(r)
        AssertTrue(p.x >= 0 && p.y >= 0 && p.x + p.w <= gw && p.y + p.h <= gh, side ": a result row inside the window")
    }
    bp := UiDashPos(box)
    for c in SbNavCtrls(d)
        AssertTrue(!ovR(bp, UiDashPos(c)), side ": the box is clear of the sidebar controls")
    if (side = "top") {
        ic := d.Ctrl("search:icon")
        AssertTrue(IsObject(ic), "top: a magnifier")
        for c in SbNavCtrls(d)
            AssertTrue(!ovR(UiDashPos(ic), UiDashPos(c)), "top: the magnifier is clear of the hubs")
        d.SearchClear()
        AssertTrue(!d._sBoxCtrls[1].Visible, "top: the box is hidden until opened")
        d.SearchFocus()
        AssertTrue(d._sBoxCtrls[1].Visible, "top: the magnifier opens the box")
    } else
        AssertTrue(box.Visible, side ": the box shows at once")
    ; none of the search controls belongs to a page
    for c in [box, d.Ctrl("search:list"), d.Ctrl("search:none")]
        AssertEq(d.PageOf(c), "", side ": not a page control")
}

; A row's click and hover act on its own row, not the last one.
Test_Search_RowHandlers() {
    dir := UiDashTmp()
    d := ""
    try {
        d := Dashboard(Config.Load(dir))
        r := d.SearchFor("webhook")
        k := 0
        for i, e in r {
            if (e.page = "Webhooks") {
                k := i
                break
            }
        }
        AssertTrue(k > 0 && r.Length >= 2, "webhook has several rows")
        d.SelectHub(1)
        hot := Theme._hot[d._sRows[k].Hwnd]
        hot.hover.Call(true)
        AssertEq(d._sSel, k, "hover selects its own row")
        hot.click.Call(d._sRows[k])
        AssertEq(d.ActivePage, "Webhooks", "the row's click opens its page")
    } finally {
        UiDashClose(d)
        try DirDelete(dir, true)
    }
}

; Theme.Forget removes every entry of the window, even after a control with none.
Test_Search_ForgetClears() {
    g := Gui()
    try {
        g.Add("Text", "x0 y0 w10 h10", "plain")
        a := Theme.Label(g, "x0 y20 w80 h20", "Alpha text")
        b := Theme.Button(g, "x0 y50 w80 h24", "Beta", (*) => 0)
        h := Theme.Help(g, 0, 80, "Gamma help")
        AssertEq(Theme.SourceOf(b), "Beta", "source recorded")
        Theme.Forget(g)
        AssertEq(Theme.SourceOf(a) Theme.SourceOf(b) Theme.SourceOf(h), "", "every source removed")
        AssertEq(Theme.HelpText(h), "", "help removed")
        AssertTrue(!Theme.IsActionText(b), "action mark removed")
    } finally {
        try g.Destroy()
    }
}
