#Requires AutoHotkey v2.0
; Offline tests for lib\CalTest.ahk ("Test my calibration") and
; lib\CalHealth.ahk (how each recorded spot did when a task used it). Every
; system call is a fake probe; the real-frame tests read tests\screens with
; the real Windows OCR. Helpers are prefixed Ct (must not start with Test_).
#Include ..\lib\CalTest.ahk
#Include ..\lib\tasks\Obby.ahk

CtFrame(name) => A_ScriptDir "\screens\" name ".jpg"

; the 2560x1440 preset's spots (data\presets\calibration_2560x1440_100.json)
CtPreset() => Map("inv_open", {x: 45, y: 674, color: 0xFFFFFF}, "inv_items_tab", {x: 1684, y: 445, color: 0xFFFFFF}
    , "inv_search", {x: 1434, y: 487}, "inv_tile1_rect", {x: 1076, y: 578, w: 110, h: 112}
    , "inv_use", {x: 913, y: 770}, "inv_desc_rect", {x: 648, y: 812, w: 367, h: 243}
    , "aura_open", {x: 35, y: 534}, "aura_search", {x: 1146, y: 490}, "aura_equip", {x: 840, y: 843}
    , "aura_close", {x: 1886, y: 393}, "chat_rect", {x: 13, y: 102, w: 463, h: 283}
    , "fisher_open_shop", {x: 865, y: 1257}, "quest_board_rect", {x: 2024, y: 489, w: 458, h: 326})

; steps for the probe: ids (in this order) from CtPreset, with overrides
CtSteps(ids, over := "", at := "") {
    pre := CtPreset()
    out := []
    for id in ids {
        v := (IsObject(over) && over.Has(id)) ? over[id] : pre[id]
        out.Push({id: id, kind: v.HasProp("w") ? "rect" : "point", v: v, at: (IsObject(at) && at.Has(id)) ? at[id] : ""})
    }
    return out
}

CtFind(rows, id) {
    for r in rows
        if (r.id = id)
            return r
    return ""
}

CtIn(p, r) => p.x >= r.x && p.x <= r.x + r.w && p.y >= r.y && p.y <= r.y + r.h

; the Aura Storage fake: its sidebar button toggles it, its X closes it
CtAuraClick(st, pt) {
    st.clicks.Push(pt.x "," pt.y)
    if (pt.x = 35)
        st.open := !st.open
    else if (pt.x = 1886)
        st.open := false
    return 1
}

; A fake Roblox with an inventory that a click on inv_open toggles. The
; inventory window is drawn at the 2560x1440 places (title middle 1282,402).
class CtGame {
    __New() {
        this.open := false
        this.clicks := []
        this.frontLeft := 9999        ; front() answers true this many times
        this.opens := true            ; a click on inv_open toggles the inventory
        this.openAt := {x: 45, y: 674}
    }
    Probes(steps, over := "") {
        p := Map(
            "steps", () => steps,
            "client", () => {w: 2560, h: 1440},
            "presets", () => [],
            "health", (id) => "",
            "running", () => false,
            "hwnd", () => 1,
            "focus", () => true,
            "front", () => this.Front(),
            "click", (pt, mode) => this.Click(pt, mode),
            "wait", (ms) => 0,
            "ocr", (x, y, w, h, scale := 1) => this.Ocr(x, y, w, h),
            "lines", (x, y, w, h, scale := 1) => this.Lines(),
            "pixel", (x, y, c, tol) => false,
            "purchaseUp", () => false,
            "now", () => "20261123130500")
        if IsObject(over)
            for k, v in over
                p[k] := v
        return p
    }
    Front() {
        this.frontLeft -= 1
        return this.frontLeft >= 0
    }
    Click(pt, mode) {
        this.clicks.Push(pt.x "," pt.y " " mode)
        if (this.opens && Abs(pt.x - this.openAt.x) <= 10 && Abs(pt.y - this.openAt.y) <= 10)
            this.open := !this.open
        return 1
    }
    Ocr(x, y, w, h) {
        if !this.open
            return ""
        r := {x: x, y: y, w: w, h: h}
        if CtIn({x: 1696, y: 449}, r)            ; the tabs (Items at 1696,449)
            return "Gears   Items"
        if CtIn({x: 1131, y: 634}, r)            ; the first tile's name
            return "Lucky Potion"
        return ""
    }
    Lines() {
        if !this.open
            return []
        L := (t, l, tp, rr, b) => {text: t, x: (l + rr) // 2, y: (tp + b) // 2, l: l, t: tp, r: rr, b: b}
        return [L("Inventory", 1182, 386, 1382, 418), L("Gears", 1218, 442, 1281, 456), L("Items", 1670, 442, 1722, 456)
            , L("Search...", 1076, 480, 1180, 500), L("Lucky", 1100, 626, 1160, 642), L("Use", 900, 760, 926, 780)]
    }
}

; ---- (a) static ------------------------------------------------------------------

Test_CalTest_InsideTheClient() {
    Screen.Reset()
    c := {w: 2560, h: 1440}
    AssertEq(CalTest.Static({id: "fisher_open_shop", v: {x: 865, y: 1257}}, c, []).v, "", "a spot on the screen is fine")
    r := CalTest.Static({id: "fisher_open_shop", v: {x: 2700, y: 100}}, c, [])
    AssertEq(r.v, "redo", "off the game screen")
    AssertTrue(InStr(r.why, "off the game screen"), "says why: " r.why)
    r := CalTest.Static({id: "chat_rect", v: {x: 2400, y: 100, w: 300, h: 200}}, c, [])
    AssertEq(r.v, "redo", "a box that runs off the screen")
    r := CalTest.Static({id: "notify_rect", v: {x: 100, y: 100, w: 4, h: 40}}, c, [])
    AssertEq(r.v, "redo", "a box too small to read")
    AssertTrue(InStr(r.why, "too small"), "says why: " r.why)
    ; the inventory scales evenly ("C"): on a 2560x1080 window its top is
    ; cut off, a stretched step ("S") at the same spot is not
    wide := {w: 2560, h: 1080}
    r := CalTest.Static({id: "inv_search", v: {x: 1434, y: 100}}, wide, [])
    AssertEq(r.v, "redo", "C-mode spot outside a wide window")
    AssertTrue(InStr(r.why, "outside your Roblox window (2560x1080)"), "names the window: " r.why)
    AssertEq(CalTest.Static({id: "fisher_open_shop", v: {x: 1434, y: 100}}, wide, []).v, "", "a stretched spot stays inside")
    AssertEq(CalTest.ModeOf("inv_open") "," CalTest.ModeOf("quest_accept") "," CalTest.ModeOf("quest_close") "," CalTest.ModeOf("fisher_qty"), "C,RH,S,C", "modes")
    ; Roblox closed: only the size-free checks
    AssertEq(CalTest.Static({id: "inv_search", v: {x: 1434, y: 100}}, "", []).v, "", "no window: no window check")
    AssertTrue(Screen.IsIdentity(), "the mapping is left as it was")
}

Test_CalTest_RecordedForAnotherSize() {
    ; every spot is design space, mapped the way its window scales: another
    ; size is fine, another shape is named (live reads / history decide)
    s := {id: "inv_search", v: {x: 1434, y: 487}, at: "1920x1080"}
    r := CalTest.Static(s, {w: 1920, h: 1200}, [])
    AssertEq(r.v, "", "a 16:9 recording on 16:10 is not redone for the shape alone")
    AssertTrue(InStr(r.origin, "recorded at 1920x1080") && InStr(r.origin, "another shape"), "but the shape is named: " r.origin)
    r := CalTest.Static(s, {w: 2560, h: 1440}, [])
    AssertEq(r.v "|" r.origin, "|recorded at 1920x1080", "the same shape at another size: just where it comes from")
    ; the chat keeps its size in pixels
    r := CalTest.Static({id: "chat_rect", v: {x: 13, y: 102, w: 463, h: 283}, at: "2560x1440"}, {w: 1920, h: 1080}, [])
    AssertEq(r.v, "redo", "the chat recorded at 1440p used at 1080p")
    AssertTrue(InStr(r.why, "chat keeps its size"), "says why: " r.why)
    AssertEq(CalTest.Static({id: "chat_rect", v: {x: 13, y: 102, w: 463, h: 283}, at: "2560x1440"}, {w: 2560, h: 1369}, []).v, "", "a maximized window: close enough")
    ; no size kept: the preset whose spot it is
    pre := [{w: 1920, h: 1080, label: "1920x1080", steps: Map("inv_search", Map("x", 1434, "y", 487, "color", "0x000B10"))}
        , {w: 2560, h: 1440, label: "2560x1440", steps: Map("chat_rect", Map("x", 13, "y", 102, "w", 463, "h", 283))}]
    r := CalTest.Static({id: "inv_search", v: {x: 1434, y: 487}, at: ""}, {w: 1920, h: 1080}, pre)
    AssertEq(r.v "|" r.origin, "|the 1920x1080 preset's spot", "the preset for this size")
    r := CalTest.Static({id: "inv_search", v: {x: 1434, y: 487}, at: ""}, {w: 1920, h: 1200}, pre)
    AssertTrue(r.v = "" && InStr(r.origin, "the 1920x1080 preset's spot, another shape"), "a 16:9 preset on 16:10: named: " r.origin)
    AssertEq(CalTest.Static({id: "inv_search", v: {x: 1400, y: 487}, at: ""}, {w: 1920, h: 1200}, pre).origin, "", "recorded by hand: size unknown")
    ; the row shows where it comes from, and says to apply the preset
    rows := CalTest.Run("", CtGame().Probes(CtSteps(["chat_rect", "inv_search"]), Map("client", () => {w: 1920, h: 1080}, "presets", () => pre, "hwnd", () => 0)))
    r := CtFind(rows, "chat_rect")
    AssertEq(r.verdict, "REDO", "the 1440p preset's chat box at 1080p")
    AssertTrue(InStr(r.detail, "the 2560x1440 preset's spot"), "names the preset: " r.detail)
    AssertTrue(InStr(r.fix, "Calibrate page") && InStr(r.fix, "preset"), "what to do: " r.fix)
    src := CtFind(rows, "_source").detail
    AssertTrue(InStr(src, "1920x1080") && InStr(src, "2 steps recorded"), "the source note: " src)
}

; A capture is mapped back in the mode its window is used in: off 16:9 an
; inventory spot lands where the task clicks it; at 16:9 nothing changes
Test_CalTest_CaptureInItsWindowsMode() {
    try {
        Screen.SetClient(0, 0, 1920, 1200)
        p := Screen.WithMode("C", () => Screen.Pt(1434, 487))         ; where the task clicks inv_search
        d := Calibrate.CaptureDesign("inv_search", p.x, p.y)
        AssertTrue(Abs(d.x - 1434) <= 2 && Abs(d.y - 487) <= 2, "16:10 inventory spot back to its design point: " d.x "," d.y)
        q := Screen.Pt(865, 1257)                                       ; a stretched button
        d := Calibrate.CaptureDesign("fisher_open_shop", q.x, q.y)
        AssertTrue(Abs(d.x - 865) <= 2 && Abs(d.y - 1257) <= 2, "a stretched spot as before: " d.x "," d.y)
        Screen.SetClient(0, 0, 1920, 1080)
        a := Calibrate.CaptureDesign("inv_search", 1075, 365), b := Calibrate.ToDesign(1075, 365)
        AssertEq(a.x "," a.y, b.x "," b.y, "16:9: the same as before")
        AssertEq(Screen.Mode, "S", "the mode is left as it was")
    } finally
        Screen.Reset()
}

; Calibrate keeps the client size a step was recorded at
Test_CalTest_CalibrateKeepsTheSize() {
    d := A_Temp "\ct_cal_" A_TickCount
    DirCreate(d)
    oldAt := Calibrate.AtFn
    try {
        Calibrate.AtFn := () => "1920x1080"
        Calibrate.Use(d "\cal.json")
        Calibrate.SetPoint("inv_open", 45, 674, 0xFFFFFF)
        Calibrate.SetRect("chat_rect", 13, 102, 476, 385)
        AssertEq(Calibrate.RecordedAt("inv_open"), "1920x1080", "kept in memory")
        AssertEq(Calibrate.StoredKey("chat_rect"), "13,102,463,283", "the recording's key")
        Calibrate.Use(d "\cal.json")
        AssertEq(Calibrate.RecordedAt("chat_rect"), "1920x1080", "kept on disk")
        AssertEq(Calibrate.Point("inv_open").x, 45, "the point still loads")
        AssertEq(Calibrate.RecordedAt("nope") Calibrate.StoredKey("nope"), "", "not recorded")
        Calibrate.AtFn := () => "junk"
        Calibrate.SetPoint("inv_use", 1, 2, 0)
        AssertEq(Calibrate.RecordedAt("inv_use"), "", "a bad size is not kept")
    } finally {
        Calibrate.AtFn := oldAt
        Calibrate.Use(A_Temp "\vesper_cal_unused.json")
        try DirDelete(d, true)
    }
}

; ---- (b) live --------------------------------------------------------------------

Test_CalTest_InventoryLiveOk() {
    Screen.Reset()
    g := CtGame()
    rows := CalTest.Run("", g.Probes(CtSteps(["inv_open", "inv_items_tab", "inv_search", "inv_tile1_rect", "inv_use"])))
    AssertEq(CtFind(rows, "inv_open").verdict, "OK", "inv_open opened it: " CtFind(rows, "inv_open").detail)
    AssertEq(CtFind(rows, "inv_items_tab").verdict, "OK", "the tabs read at inv_items_tab")
    AssertEq(CtFind(rows, "inv_search").verdict, "OK", "on the search box: " CtFind(rows, "inv_search").detail)
    AssertEq(CtFind(rows, "inv_tile1_rect").verdict, "OK", "a name reads in the tile box")
    AssertTrue(InStr(CtFind(rows, "inv_tile1_rect").detail, "Lucky Potion"), "shows what it read")
    AssertEq(CtFind(rows, "inv_use").verdict, "OK", "Use reads at inv_use")
    AssertEq(g.clicks.Length, 3, "inv_open, the Items tab, inv_open again")
    AssertEq(g.clicks[1] "|" g.clicks[3], "45,674 C|45,674 C", "opened and closed by its button")
    AssertEq(g.clicks[2], "1684,445 C", "the Items tab where it reads")
    AssertTrue(!g.open, "closed again")
    AssertTrue(InStr(CtFind(rows, "_live").detail, "3 clicks"), "the note counts the clicks: " CtFind(rows, "_live").detail)
}

Test_CalTest_InventoryLiveRedo() {
    Screen.Reset()
    ; inv_items_tab recorded 300 px off: its tabs do not read there, the
    ; window found on screen says where it is
    g := CtGame()
    rows := CalTest.Run("", g.Probes(CtSteps(["inv_open", "inv_items_tab", "inv_search"], Map("inv_items_tab", {x: 1384, y: 445}))))
    r := CtFind(rows, "inv_items_tab")
    AssertEq(r.verdict, "REDO", "the tab does not read where recorded")
    AssertTrue(InStr(r.detail, "1696,449"), "says where it is: " r.detail)
    AssertEq(CtFind(rows, "inv_open").verdict, "OK", "the inventory did open")
    AssertEq(rows[3].verdict, "REDO", "REDO listed first (after the two notes)")
    AssertTrue(!g.open, "closed again (by the tab found)")
    ; inv_open on the wrong spot: one click, nothing opens, nothing more
    g := CtGame()
    g.opens := false
    rows := CalTest.Run("", g.Probes(CtSteps(["inv_open", "inv_items_tab", "inv_search"])))
    r := CtFind(rows, "inv_open")
    AssertEq(r.verdict, "REDO", "a click that opens nothing")
    AssertTrue(InStr(r.detail, "did not open the inventory"), "says why: " r.detail)
    AssertEq(g.clicks.Length, 1, "no second click")
    AssertEq(CtFind(rows, "inv_items_tab").verdict, "NOT TESTED", "the tab could not be tested")
    ; already open: no click on its button, left open
    g := CtGame()
    g.open := true
    rows := CalTest.Run("", g.Probes(CtSteps(["inv_open", "inv_items_tab"])))
    AssertEq(g.clicks.Length, 1, "only the Items tab")
    AssertTrue(g.open, "left open as it was")
    AssertEq(CtFind(rows, "inv_items_tab").verdict, "OK", "its tabs read")
}

Test_CalTest_FocusLostStopsInput() {
    Screen.Reset()
    g := CtGame()
    g.frontLeft := 1                   ; in front for the first click only
    rows := CalTest.Run("", g.Probes(CtSteps(["inv_open", "inv_items_tab", "inv_search", "aura_open", "aura_search"])))
    AssertEq(g.clicks.Length, 1, "nothing sent after focus was lost")
    live := CtFind(rows, "_live").detail
    AssertTrue(InStr(live, "lost focus"), "the note says so: " live)
    AssertTrue(InStr(live, "left open: the inventory"), "and what is left open: " live)
    for id in ["inv_open", "inv_items_tab", "aura_open"]
        AssertEq(CtFind(rows, id).verdict, "NOT TESTED", id " not tested")
    ; never in front: no click at all
    g := CtGame()
    rows := CalTest.Run("", g.Probes(CtSteps(["inv_open", "inv_items_tab"]), Map("focus", () => false)))
    AssertEq(g.clicks.Length, 0, "no click without Roblox in front")
    AssertTrue(InStr(CtFind(rows, "_live").detail, "front"), "says why")
    AssertTrue(InStr(CtFind(rows, "inv_open").detail, "front"), "the step says why it is not tested")
}

Test_CalTest_SkipsWhileRunningOrPrompt() {
    g := CtGame()
    called := []
    rows := CalTest.Run("", g.Probes(CtSteps(["inv_open", "inv_items_tab"]), Map("running", () => true, "focus", () => (called.Push(1), true))))
    AssertEq(g.clicks.Length + called.Length, 0, "a running macro: Roblox not even brought forward")
    AssertTrue(InStr(CtFind(rows, "_live").detail, "macro is running"), "says why")
    g := CtGame()
    rows := CalTest.Run("", g.Probes(CtSteps(["inv_open", "inv_items_tab"]), Map("purchaseUp", () => true)))
    AssertEq(g.clicks.Length, 0, "a purchase prompt: nothing clicked")
    AssertTrue(InStr(CtFind(rows, "_live").detail, "purchase prompt"), "says why")
    ; a step the static checks failed is never clicked
    g := CtGame()
    rows := CalTest.Run("", g.Probes(CtSteps(["inv_open", "inv_items_tab"], Map("inv_open", {x: -5, y: 674}))))
    AssertEq(g.clicks.Length, 0, "an off-screen inv_open is not clicked")
    AssertEq(CtFind(rows, "inv_open").verdict, "REDO", "and is to redo")
}

Test_CalTest_AuraLive() {
    Screen.Reset()
    st := {open: false, clicks: []}
    ocr := (x, y, w, h, scale := 1) => (st.open && CtIn({x: 1146 - 200 + 100, y: 490 - 135 + 40}, {x: x, y: y, w: w, h: h})) ? "Aura Storage"
        : (st.open && CtIn({x: 840 - 210 + 100, y: 843 - 262 + 30}, {x: x, y: y, w: w, h: h})) ? "[ Information ]"
        : (CtIn({x: 1886, y: 393}, {x: x, y: y, w: w, h: h})) ? "X" : ""
    click := (pt, mode) => CtAuraClick(st, pt)
    g := CtGame()
    rows := CalTest.Run("", g.Probes(CtSteps(["aura_open", "aura_search", "aura_equip", "aura_close"]), Map("ocr", ocr, "click", click, "lines", (*) => [])))
    for id in ["aura_open", "aura_search", "aura_equip", "aura_close"]
        AssertEq(CtFind(rows, id).verdict, "OK", id ": " CtFind(rows, id).detail)
    AssertEq(st.clicks.Length, 2, "its button, then its X")
    AssertEq(st.clicks[2], "1886,393", "closed by its X")
    AssertTrue(!st.open, "closed")
    ; an X on a Delete button is never clicked: the sidebar button closes it
    st := {open: false, clicks: []}
    ocr2 := (x, y, w, h, scale := 1) => CtIn({x: 1886, y: 393}, {x: x, y: y, w: w, h: h}) ? "Delete" : ocr(x, y, w, h, scale)
    rows := CalTest.Run("", g.Probes(CtSteps(["aura_open", "aura_search", "aura_equip", "aura_close"]), Map("ocr", ocr2, "click", click, "lines", (*) => [])))
    AssertEq(CtFind(rows, "aura_close").verdict, "REDO", "on a Delete button")
    AssertEq(st.clicks.Length "|" st.clicks[2], "2|35,534", "never clicked: its sidebar button instead")
    AssertTrue(!st.open, "closed")
}

; ---- (c) history -------------------------------------------------------------------

Test_CalHealth_CountsAndVerdicts() {
    oldKey := CalHealth.KeyFn, oldNow := CalHealth.NowFn
    keys := Map("fisher_open_shop", "865,1257", "quest_board_rect", "2024,489,458,326")
    stamp := {v: "20261123130400"}
    try {
        CalHealth.Reset()
        CalHealth.On := true
        CalHealth.KeyFn := (id) => keys.Has(id) ? keys[id] : ""
        CalHealth.NowFn := () => stamp.v
        AssertEq(CalHealth.Get("fisher_open_shop"), "", "no use yet")
        Loop 3
            CalHealth.Ok("fisher_open_shop", {x: 865, y: 1257})
        CalHealth.Ok("fisher_open_shop", {x: 900, y: 1257})     ; a place found on screen: not noted
        CalHealth.Ok("fisher_leave")                             ; not recorded: not noted
        h := CalHealth.Get("fisher_open_shop")
        AssertEq(h.ok "|" h.fail "|" h.run, "3|0|0", "three uses")
        AssertEq(CalHealth.Get("fisher_leave"), "", "nothing for a step that is not recorded")
        r := CalTest.FromHistory(h, "20261123140000")
        AssertEq(r.v, "ok", "worked")
        AssertTrue(InStr(r.why, "worked 3 times, last today 13:04"), r.why)
        stamp.v := "20261123130500"
        CalHealth.Fail("fisher_open_shop", "Open Shop did not read")
        r := CalTest.FromHistory(CalHealth.Get("fisher_open_shop"), "20261123140000")
        AssertEq(r.v, "untested", "one miss: not sure yet")
        Loop 2
            CalHealth.Fail("fisher_open_shop", "Open Shop did not read")
        h := CalHealth.Get("fisher_open_shop")
        AssertEq(h.ok "|" h.fail "|" h.run, "3|3|3", "three misses in a row")
        r := CalTest.FromHistory(h, "20261124090000")
        AssertEq(r.v, "redo", "misses in a row: redo")
        AssertTrue(InStr(r.why, "last 3 times") && InStr(r.why, "yesterday 13:05") && InStr(r.why, "Open Shop did not read"), r.why)
        CalHealth.Ok("fisher_open_shop")
        AssertEq(CalHealth.Get("fisher_open_shop").run, 0, "a success ends the run")
        ; recorded again: the history starts over
        keys["fisher_open_shop"] := "870,1257"
        AssertEq(CalHealth.Get("fisher_open_shop"), "", "a new recording has no history")
        ; the rows: a REDO from history comes first, a step with no use says why
        CalHealth.Fail("quest_board_rect", "no quest text read in it")
        CalHealth.Fail("quest_board_rect", "no quest text read in it")
        keys["fisher_open_shop"] := "865,1257"
        rows := CalTest.Run("", CtGame().Probes(CtSteps(["fisher_open_shop", "quest_board_rect", "chat_rect"])
            , Map("health", (id) => CalHealth.Get(id), "hwnd", () => 0)))
        AssertEq(rows[1].id "|" rows[2].id, "_source|_live", "the notes first")
        AssertEq(rows[3].id "|" rows[3].verdict, "quest_board_rect|REDO", "REDO next")
        AssertEq(rows[4].id "|" rows[4].verdict, "fisher_open_shop|OK", "then OK")
        AssertEq(rows[5].id "|" rows[5].verdict, "chat_rect|NOT TESTED", "then NOT TESTED")
        AssertTrue(InStr(rows[5].detail, "Roblox is not open"), "a live step says why: " rows[5].detail)
        AssertEq(CalTest.Summary(rows), "1 to redo, 1 ok, 1 not tested", "summary")
        AssertTrue(InStr(CalTest.Report(rows), "[REDO] quest_board_rect"), "the report")
        rows := CalTest.Run("", CtGame().Probes(CtSteps(["fisher_open_shop"]), Map("health", (id) => "", "hwnd", () => 0)))
        AssertTrue(InStr(CtFind(rows, "fisher_open_shop").detail, "Captain Flarg"), "where it needs you")
    } finally {
        CalHealth.KeyFn := oldKey, CalHealth.NowFn := oldNow
        CalHealth.Reset()
    }
}

Test_CalHealth_SavedAndLoaded() {
    oldKey := CalHealth.KeyFn
    d := A_Temp "\ct_health_" A_TickCount
    DirCreate(d)
    try {
        CalHealth.KeyFn := (id) => id = "cauldron_gui" ? "1861,222,586,35" : ""
        CalHealth.Use(d "\cal_health.json")
        AssertTrue(CalHealth.On, "on with a file")
        CalHealth.Fail("cauldron_gui", "the title did not read")          ; a failure is saved at once
        AssertTrue(FileExist(d "\cal_health.json"), "written")
        CalHealth.Ok("cauldron_gui")
        CalHealth.Flush()
        CalHealth.Use(d "\cal_health.json")
        h := CalHealth.Get("cauldron_gui")
        AssertEq(h.ok "|" h.fail "|" h.run "|" h.why, "1|1|0|the title did not read", "loaded back")
        FileDelete(d "\cal_health.json")
        FileAppend("{broken", d "\cal_health.json", "UTF-8")
        CalHealth.Use(d "\cal_health.json")
        AssertEq(CalHealth.Get("cauldron_gui"), "", "a broken file is an empty history")
        CalHealth.Reset()
        AssertTrue(!CalHealth.On, "off again (tests note nothing)")
    } finally {
        CalHealth.KeyFn := oldKey
        CalHealth.Reset()
        try DirDelete(d, true)
    }
}

Test_CalTest_SameReadsAsTheTasks() {
    box := (b) => b.dx "," b.dy "," b.w "," b.h
    AssertEq(box(CalTest.StorageBox), box(ObbyTask.StorageBox), "StorageBox")
    AssertEq(box(CalTest.PanelBox), box(ObbyTask.PanelBox), "PanelBox")
    AssertEq(CalTest.StorageRe "|" CalTest.PanelRe "|" CalTest.NeverRe "|" CalTest.StorageScale
        , ObbyTask.StorageRe "|" ObbyTask.PanelRe "|" ObbyTask.NeverRe "|" ObbyTask.StorageScale, "the regexes and scale")
}

; ---- real frames -------------------------------------------------------------------

; The inventory on real 2560x1440 frames, read at the preset's spots (as
; recorded on that screen), with the real OCR: the open window is left
; open (no click on its button), only the Items tab is clicked.
Test_CalTest_RealFrameInventory() {
    Screen.Reset()
    for f in ["inventory_open_day", "inventory_open_rainy"] {
        path := CtFrame(f)
        AssertTrue(FileExist(path), f " exists")
        g := CtGame()
        pr := g.Probes(CtSteps(["inv_open", "inv_items_tab", "inv_search", "inv_tile1_rect", "inv_use", "inv_desc_rect"])
            , Map("ocr", (x, y, w, h, scale := 1) => Ocr.ReadFile(path, x, y, w, h, scale)
                , "lines", (x, y, w, h, scale := 1) => Ocr.LinesFile(path, x, y, w, h, scale)))
        rows := CalTest.Run("", pr)
        for id in ["inv_items_tab", "inv_search", "inv_tile1_rect", "inv_use", "inv_desc_rect"]
            AssertEq(CtFind(rows, id).verdict, "OK", f " " id ": " CtFind(rows, id).detail)
        AssertEq(g.clicks.Length, 1, f ": only the Items tab clicked (it was open)")
        AssertEq(CtFind(rows, "inv_open").verdict, "NOT TESTED", f ": inv_open not clicked, not tested")
        ; recorded for another screen: 120 px lower, the tabs do not read there
        g := CtGame()
        pr["click"] := (pt, mode) => g.Click(pt, mode)
        pr["steps"] := () => CtSteps(["inv_open", "inv_items_tab", "inv_search"], Map("inv_items_tab", {x: 1684, y: 565}, "inv_search", {x: 1434, y: 700}))
        rows := CalTest.Run("", pr)
        r := CtFind(rows, "inv_items_tab")
        AssertEq(r.verdict, "REDO", f ": a tab recorded off the tabs")
        AssertTrue(RegExMatch(r.detail, "Items tab is at 1[67]\d\d,4[34]\d"), f ": says where it is: " r.detail)
        AssertEq(CtFind(rows, "inv_search").verdict, "REDO", f ": a search box recorded off the box")
    }
}

; The Aura Storage on a real frame (Sailor selected): its title over
; aura_search and the [Information] header over aura_equip read with the
; real OCR at the preset's spots; open already, so nothing is clicked.
Test_CalTest_RealFrameAuraStorage() {
    Screen.Reset()
    path := CtFrame("aura_selected_sailor")
    g := CtGame()
    rows := CalTest.Run("", g.Probes(CtSteps(["aura_open", "aura_search", "aura_equip", "aura_close"])
        , Map("ocr", (x, y, w, h, scale := 1) => Ocr.ReadFile(path, x, y, w, h, scale)
            , "lines", (x, y, w, h, scale := 1) => Ocr.LinesFile(path, x, y, w, h, scale))))
    AssertEq(CtFind(rows, "aura_search").verdict, "OK", "the title reads over aura_search: " CtFind(rows, "aura_search").detail)
    AssertEq(CtFind(rows, "aura_equip").verdict, "OK", "the header reads over aura_equip: " CtFind(rows, "aura_equip").detail)
    AssertEq(g.clicks.Length, 0, "open already: nothing clicked")
    ; recorded for another screen: aura_search 150 px off
    g := CtGame()
    rows := CalTest.Run("", g.Probes(CtSteps(["aura_open", "aura_search"], Map("aura_search", {x: 1146, y: 640}))
        , Map("ocr", (x, y, w, h, scale := 1) => Ocr.ReadFile(path, x, y, w, h, scale)
            , "lines", (x, y, w, h, scale := 1) => Ocr.LinesFile(path, x, y, w, h, scale)
            , "click", (pt, mode) => (g.clicks.Push(pt.x "," pt.y), 1))))
    r := CtFind(rows, "aura_search")
    AssertEq(r.verdict, "REDO", "the title does not read over a moved aura_search: " r.detail)
    AssertTrue(InStr(r.detail, "the title is at"), "the title found on screen: " r.detail)
}

; ---- the Check page ------------------------------------------------------------------

Test_Dashboard_CalTestShown() {
    dir := UiDashTmp()
    d := ""
    try {
        rows := [{id: "_live", name: "Live test", level: "info", verdict: "", detail: "tested 2 steps on screen (3 clicks)", fix: ""}
            , {id: "inv_items_tab", name: "inv_items_tab", level: "fail", verdict: "REDO", detail: "the tabs do not read there", fix: "Record inv_items_tab again on the Calibrate page"}
            , {id: "inv_open", name: "inv_open", level: "ok", verdict: "OK", detail: "a click on it opened the inventory", fix: ""}
            , {id: "fisher_leave", name: "fisher_leave", level: "info", verdict: "NOT TESTED", detail: "not tested: needs you at Captain Flarg", fix: ""}]
        calls := {n: 0}
        d := Dashboard(Config.Load(dir), Map("testCalibration", () => (calls.n++, rows)))
        d._TestCal()
        out := d.Ctrl("checkOut").Value
        AssertEq(calls.n, 1, "the button's callback ran once")
        AssertTrue(InStr(out, "[REDO]  inv_items_tab: the tabs do not read there") && InStr(out, "Record inv_items_tab again"), "REDO with what to do")
        AssertTrue(InStr(out, "[OK]  inv_open") && InStr(out, "[--]  fisher_leave") && InStr(out, "[i]  Live test"), "every row tagged")
        AssertTrue(InStr(out, "[REDO]") < InStr(out, "[OK]"), "in the order given (REDO first)")
        AssertEq(d.Ctrl("checkSummary").Text, "1 to redo, 1 ok, 1 not tested", "summary line")
    } finally {
        UiDashClose(d)
        try DirDelete(dir, true)
    }
}
