#Requires AutoHotkey v2.0
; Tests for lib\ui\Layout.ahk and Dashboard.ApplyLayout (themes move, resize
; and hide cards). The dashboard is built hidden; scratch folders under A_Temp.
; Uses UiDashTmp / UiDashClose / UiCardDesc from test_ui_dash.ahk (same script).
#Include ..\lib\ui\Layout.ahk

; Position of every control of the page, hwnd -> "x,y,w,h" (100 % units).
LyPositions(page) {
    m := Map()
    for c in page.ctrls {
        p := Theme.Pos(c)
        m[c.Hwnd] := p.x "," p.y "," p.w "," p.h
    }
    return m
}

LyCard(d, id) {
    page := RegExReplace(id, ":.*$")
    for card in d.Cards(page) {
        if (card.id = id)
            return card
    }
    return ""
}

Test_Layout_SnapClampMin() {
    AssertEq(Layout.Snap(13), 16, "13 snaps up")
    AssertEq(Layout.Snap(11), 8, "11 snaps down")
    AssertEq(Layout.Snap(-3), 0, "-3 snaps to 0")
    area := {x: 204, y: 152, w: 808, h: 468}
    r := Layout.Clamp({x: -40, y: 300, w: 200, h: 100}, area)
    AssertEq(r.x, 204, "dragged to x = -40 clamps to area.x")
    AssertEq(r.w "x" r.h, "200x100", "size kept when it fits")
    r := Layout.Clamp({x: 900, y: 600, w: 200, h: 100}, area)
    AssertEq(r.x + r.w, 1012, "right edge stops at the area")
    AssertEq(r.y + r.h, 620, "bottom edge stops at the area")
    r := Layout.Clamp({x: 300, y: 200, w: 2000, h: 2000}, area)
    AssertEq(r.x "," r.y "," r.w "," r.h, "204,152,808,468", "too big shrinks to the area")
    r := Layout.Clamp({x: 300, y: 200, w: 10, h: 10}, area, {w: 120, h: 60})
    AssertEq(r.w "x" r.h, "120x60", "resized to 10x10 becomes the minimum")
    dir := UiDashTmp()
    d := ""
    try {
        d := Dashboard(Config.Load(dir))
        card := LyCard(d, "Settings:Recovery")
        AssertTrue(IsObject(card), "Settings:Recovery exists")
        mn := Layout.MinSize(card)
        AssertTrue(mn.w > 12 && mn.h > 12 && mn.w <= card.w + 12 && mn.h <= card.h + 12, "MinSize is about the controls' box: " mn.w "x" mn.h " of " card.w "x" card.h)
        e := Layout.Place(card, [300, 200, 10, 10, 0], area)
        AssertEq(e.w "x" e.h, mn.w "x" mn.h, "a 10x10 entry becomes MinSize")
    } finally {
        UiDashClose(d)
        try DirDelete(dir, true)
    }
}

Test_Layout_Overlaps() {
    r := Map("a", {x: 0, y: 0, w: 100, h: 100}, "b", {x: 99, y: 0, w: 50, h: 50}, "c", {x: 149, y: 0, w: 50, h: 50}
        , "d", {x: 0, y: 100, w: 100, h: 20})
    o := Layout.Overlaps(r)
    AssertEq(o.Length, 1, "only a/b share pixels")
    AssertEq(o[1][1] "," o[1][2], "a,b", "the pair")
    AssertEq(Layout.Overlaps(Map()).Length, 0, "empty -> none")
}

Test_Layout_ApplyMovesOnlyThatCard() {
    dir := UiDashTmp()
    d := ""
    try {
        d := Dashboard(Config.Load(dir))
        page := d._PageByName("Settings")
        card := LyCard(d, "Settings:Recovery")
        before := LyPositions(page)
        mine := Map()
        for c in card.ctrls
            mine[c.Hwnd] := true
        x0 := card.x, y0 := card.y, w0 := card.w, h0 := card.h
        d.ApplyLayout("Settings", Map("Settings:Recovery", [x0 + 412, y0 - 200, w0, h0, 0]))
        after := LyPositions(page)
        bad := ""
        for hw, pos in before {
            if mine.Has(hw)
                continue
            if (after[hw] != pos)
                bad .= "`n" hw ": " pos " -> " after[hw]
        }
        AssertEq(bad, "", "no control of another card moved")
        for c in card.ctrls {
            b := StrSplit(before[c.Hwnd], ",")
            a := StrSplit(after[c.Hwnd], ",")
            AssertEq((a[1] - b[1]) "," (a[2] - b[2]), "412,-200", "moved by exactly that: " UiCardDesc(c))
        }
        p := Theme.Pos(card.frame)
        AssertEq(p.x "," p.y, (x0 + 412) "," (y0 - 200), "frame moved")
        AssertEq(card.x "," card.y, (x0 + 412) "," (y0 - 200), "the card record follows")
    } finally {
        UiDashClose(d)
        try DirDelete(dir, true)
    }
}

Test_Layout_ResizesFrameAndFill() {
    dir := UiDashTmp()
    d := ""
    try {
        d := Dashboard(Config.Load(dir))
        card := LyCard(d, "Settings:Recovery")
        d.ApplyLayout("Settings", Map("Settings:Recovery", [card.x, card.y, 500, 200, 0]))
        f := Theme.Pos(card.frame), fl := Theme.Pos(card.fill)
        AssertEq(f.w "x" f.h, "500x200", "frame sized")
        AssertEq(fl.w "x" fl.h, "498x198", "fill is 2 px smaller")
    } finally {
        UiDashClose(d)
        try DirDelete(dir, true)
    }
}

Test_Layout_HiddenCard() {
    dir := UiDashTmp()
    d := ""
    try {
        d := Dashboard(Config.Load(dir))
        card := LyCard(d, "Settings:Recovery")
        idx := Dashboard.PageIndex("Settings")
        d.ApplyLayout("Settings", Map("Settings:Recovery", [card.x, card.y, card.w, card.h, 1]))
        d.SelectPage(idx)
        vis := 0
        for c in card.ctrls
            vis += c.Visible ? 1 : 0
        AssertEq(vis, 0, "every control of the hidden card is hidden on a shown page")
        AssertTrue(d.Cards("Settings")[1].frame.Visible, "another card is still shown")
        d.ApplyLayout("Settings", Map())
        d.SelectPage(1)
        d.SelectPage(idx)
        shown := 0
        for c in card.ctrls
            shown += (c.Visible = !d._hidden.Has(c.Hwnd)) ? 1 : 0
        AssertEq(shown, card.ctrls.Length, "every control follows its own rule again")
        AssertTrue(card.frame.Visible, "the frame is shown again")
    } finally {
        UiDashClose(d)
        try DirDelete(dir, true)
    }
}

Test_Layout_BarCardStaysHidden() {
    dir := UiDashTmp()
    d := ""
    try {
        d := Dashboard(Config.Load(dir))
        card := LyCard(d, "Run:#1")
        AssertTrue(IsObject(card), "Run:#1 exists")
        d.ApplyLayout("Run", Map("Run:#1", [card.x, card.y + 8, card.w, card.h, 0]))
        d.SelectPage(Dashboard.PageIndex("Run"))
        AssertTrue(!card.frame.Visible && !card.fill.Visible, "a bar card keeps its frame and fill hidden")
        d.ApplyLayout("Run", Map("Run:#1", [card.x, card.y, card.w, card.h, 1]))
        d.ApplyLayout("Run", Map())
        d.SelectPage(1)
        d.SelectPage(Dashboard.PageIndex("Run"))
        AssertTrue(!card.frame.Visible && !card.fill.Visible, "still hidden after hide and show")
    } finally {
        UiDashClose(d)
        try DirDelete(dir, true)
    }
}

Test_Layout_ImportedLayoutClamped() {
    dir := UiDashTmp()
    d := ""
    try {
        d := Dashboard(Config.Load(dir))
        card := LyCard(d, "Settings:Recovery")
        mn := Layout.MinSize(card)
        d.ApplyLayout("Settings", Map("Settings:Recovery", [99999, 99999, 5, 5, 0]))
        f := Theme.Pos(card.frame)
        a := d.PageArea()
        AssertEq(f.w "x" f.h, mn.w "x" mn.h, "at its MinSize")
        AssertTrue(f.x >= a.x && f.y >= a.y && f.x + f.w <= a.x + a.w && f.y + f.h <= a.y + a.h, "inside the page area: " f.x "," f.y " " f.w "x" f.h)
    } finally {
        UiDashClose(d)
        try DirDelete(dir, true)
    }
}

Test_Layout_UnknownCardIgnored() {
    dir := UiDashTmp()
    d := ""
    try {
        d := Dashboard(Config.Load(dir))
        page := d._PageByName("Settings")
        before := LyPositions(page)
        d.ApplyLayout("Settings", Map("Settings:Nope", [10, 10, 100, 100, 1], "Settings:Recovery", "junk", "Settings:#9", [1, 2]))
        d.ApplyLayout("NoSuchPage", Map("Settings:Recovery", [0, 0, 50, 50, 0]))
        d.ApplyLayout("Settings", "not a map")
        after := LyPositions(page)
        same := true
        for hw, pos in before
            same := same && after[hw] = pos
        AssertTrue(same, "nothing moved")
    } finally {
        UiDashClose(d)
        try DirDelete(dir, true)
    }
}

Test_Layout_CardWithoutEntryStays() {
    dir := UiDashTmp()
    d := ""
    try {
        d := Dashboard(Config.Load(dir))
        card := LyCard(d, "Stats:Last 7 days")
        before := Theme.Pos(card.frame)
        d.ApplyLayout("Stats", Map("Stats:Nothing", [0, 0, 50, 50, 0]))
        after := Theme.Pos(card.frame)
        AssertEq(after.x "," after.y "," after.w "," after.h, before.x "," before.y "," before.w "," before.h, "a card without an entry is not clamped or moved")
    } finally {
        UiDashClose(d)
        try DirDelete(dir, true)
    }
}

Test_Layout_ThemeLayoutAppliedAtBuild() {
    old := Theme.Layout
    dir := UiDashTmp()
    d := "", d2 := ""
    try {
        d := Dashboard(Config.Load(dir))
        card := LyCard(d, "Settings:Recovery")
        x0 := card.x, y0 := card.y, w0 := card.w, h0 := card.h
        UiDashClose(d)
        d := ""
        Theme.Layout := Map("Settings:Recovery", [x0 + 8, y0 - 40, w0, h0, 0])
        d2 := Dashboard(Config.Load(dir))
        c2 := LyCard(d2, "Settings:Recovery")
        p := Theme.Pos(c2.frame)
        AssertEq(p.x "," p.y, (x0 + 8) "," (y0 - 40), "the theme's layout is applied when the dashboard is built")
    } finally {
        Theme.Layout := old
        UiDashClose(d)
        UiDashClose(d2)
        try DirDelete(dir, true)
    }
}

; Layout entries are page places (the place with the sidebar at the left):
; a card moved with the sidebar at the left keeps its offset from an unmoved
; neighbour when the window is built with the sidebar at the right or the
; top, and an entry written with the sidebar at the top lands at the same
; page place with the sidebar at the left.
Test_Layout_EntriesFollowTheSidebar() {
    oldSb := Theme.Sidebar, oldLy := Theme.Layout, oldWa := Theme.WorkAreaFn, oldSc := Theme.Scale
    dir := UiDashTmp()
    d := ""
    offOf := (d) => (LyCard(d, "Settings:Recovery").x - LyCard(d, "Settings:Intervals").x) "," (LyCard(d, "Settings:Recovery").y - LyCard(d, "Settings:Intervals").y)
    try {
        Theme.WorkAreaFn := () => {w: 3840, h: 2160}
        Theme.Scale := 100
        Theme.Layout := Map()
        Theme.Sidebar := "left"
        d := UiLookDash(Config.Load(dir))
        built := offOf(d)
        d.EditLayout(true)
        AssertTrue(d.DragCard("Settings:Recovery", 16, -8), "moved with the sidebar at the left")
        lay := Dashboard._LayClone(d.LayoutEntries())
        off := offOf(d)
        AssertTrue(off != built, "the drag changed the offset: " built " -> " off)
        d.LayoutCancel()
        UiDashClose(d), d := ""
        for side in ["right", "top"] {
            Theme.Sidebar := side
            Theme.Layout := Dashboard._LayClone(lay)
            d := Dashboard(Config.Load(dir))
            AssertEq(offOf(d), off, side ": the moved card keeps its offset from an unmoved neighbour")
            rec := LyCard(d, "Settings:Recovery"), a := d.PageArea()
            AssertTrue(rec.x >= a.x && rec.y >= a.y && rec.x + rec.w <= a.x + a.w && rec.y + rec.h <= a.y + a.h, side ": inside the page area")
            UiDashClose(d), d := ""
        }
        ; written with the sidebar at the top, shown with it at the left
        Theme.Sidebar := "top"
        Theme.Layout := Map()
        d := UiLookDash(Config.Load(dir))
        d.EditLayout(true)
        AssertTrue(d.DragCard("Settings:Recovery", 16, -8), "moved with the sidebar at the top")
        e := d.LayoutEntries()["Settings:Recovery"].Clone()
        rec := LyCard(d, "Settings:Recovery"), sh := Dashboard.PageShift("top")
        AssertEq(e[1] "," e[2], (rec.x - sh.dx) "," (rec.y - sh.dy), "top: the entry is the page place")
        AssertEq(offOf(d), off, "top: the same drag, the same offset")
        d.LayoutCancel()
        UiDashClose(d), d := ""
        Theme.Sidebar := "left"
        Theme.Layout := Map("Settings:Recovery", e)
        d := Dashboard(Config.Load(dir))
        rec := LyCard(d, "Settings:Recovery")
        AssertEq(rec.x "," rec.y, e[1] "," e[2], "left: lands at the entry's page place")
        AssertEq(offOf(d), off, "left: the offset from the neighbour")
    } finally {
        Theme.Sidebar := oldSb, Theme.Layout := oldLy, Theme.WorkAreaFn := oldWa, Theme.Scale := oldSc
        Anim.Reset()
        UiDashClose(d)
        try DirDelete(dir, true)
    }
}
