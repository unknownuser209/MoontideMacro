#Requires AutoHotkey v2.0
; Bug hunt 2026-11-27 fixes: craft (cauldron re-armed on Start, the retry
; gap capped), config (a folder it cannot write, a commented section
; header, "Memory Match only" and the cauldron), "Test my calibration" on a
; window open already, Memory Match's Close check. Uses the helpers of
; test_craft.ahk (Cr*), test_config.ahk (Cfg*), test_profiles.ahk (Pf*),
; test_caltest.ahk (Ct*), test_memorymatch.ahk (Mm*), test_questmatch.ahk
; (Qm*). Helpers here are prefixed Ccf (must not start with Test_).

; ---- craft-2: the cauldron's first visit since Start, every Start ------------

Test_CraftCfg_CauldronDueAgainAfterReset() {
    clk := {t: 3000000}
    m := CrMake(Map("toast", false, "cauldron", true, "now", () => clk.t))
    m.t.Run(SchedCtx())
    AssertEq(m.io.Count("down f"), 1, "the first visit since Start ran")
    AssertEq(m.t.CanRun(SchedState()), false, "nothing more due")
    AssertTrue(HasMethod(m.t, "Reset"), "CraftTask.Reset (App.Start calls it)")
    m.t.Reset()
    AssertEq(m.t.CanRun(SchedState()), true, "a new Start: the cauldron's first visit since Start is due")
    ; a retry gap left from the last session does not hold the new one back
    m.t._aborts := 3, m.t._abortAt := clk.t
    AssertEq(m.t.CanRun(SchedState()), false, "inside the old gap")
    m.t.Reset()
    AssertEq(m.t.CanRun(SchedState()), true, "a new Start: the old gap is gone")
    ; F1 before the recipe was picked: the step is skipped (and not due on
    ; every tick); picked, then F1 again: the visit comes
    m2 := CrMake(Map("toast", false, "cauldron", true, "now", () => clk.t, "gets", Map("Craft.craftTarget", "")))
    m2.t.Run(SchedCtx())
    AssertEq(m2.io.Count("down f"), 0, "no recipe: no cauldron step")
    AssertEq(m2.t.CanRun(SchedState()), false, "not due on every tick")
    m2.cfg.g["Craft.craftTarget"] := "Heavenly Potion"
    m2.t.Reset()
    AssertEq(m2.t.CanRun(SchedState()), true, "set up, then Start: the visit is due")
    m2.io.log := []
    m2.t.Run(SchedCtx())
    AssertEq(m2.io.Count("down f"), 1, "the cauldron step ran")
    ; a seen toast's one buy is kept (never bought twice, never lost)
    m3 := CrMake(Map("now", () => clk.t))
    m3.t.Reset()
    AssertEq(m3.t.BuyDue(), true, "a latched toast's buy survives Reset")
}

; ---- craft-3: the retry gap never wraps ---------------------------------------

Test_CraftCfg_RetryGapStaysCapped() {
    clk := {t: 5000000}
    m := CrMake(Map("toast", false, "cauldron", true, "now", () => clk.t))
    m.t._aborts := 1
    AssertEq(m.t._RetryGapMs(), CraftTask.RetryGapMs, "1 early end: the base gap")
    m.t._aborts := 2
    AssertEq(m.t._RetryGapMs(), 2 * CraftTask.RetryGapMs, "2: doubled")
    for a in [5, 48, 49, 50, 63, 64, 70, 200] {
        m.t._aborts := a, m.t._abortAt := clk.t
        AssertEq(m.t._RetryGapMs(), CraftTask.RetryGapMaxMs, "gap capped at " a " early ends")
        AssertEq(m.t.CanRun(SchedState()), false, "no relaunch inside the gap at " a " early ends")
    }
}

; ---- config-1: "Memory Match only" turns Stella's cauldron off too ------------

Test_CraftCfg_MemoryMatchOnlyStopsTheCauldron() {
    dir := PfDir()
    try {
        cfg := Config.Load(dir)
        cfg.Set("Craft.enabled", 1)
        cfg.Set("Craft.cauldron", 1)
        changed := Profiles.Apply(cfg, "Memory Match only")
        AssertEq(cfg.Get("Craft.cauldron", 0), 0, "crafting off includes Stella's cauldron")
        AssertEq(cfg.Get("Craft.enabled", 1), 0, "Fish shop off")
        found := false
        for k in changed
            found := found || (k = "Craft.cauldron")
        AssertTrue(found, "counted as changed")
    } finally {
        try DirDelete(dir, true)
    }
}

; ---- config-2: a folder it cannot write does not crash the first start --------

Test_CraftCfg_UnwritableFolderLoadsDefaults() {
    dir := CfgTmpDir()
    ; a folder where _WriteText's temp file goes: FileOpen(tmp, "w") throws
    ; OSError, as in Program Files or under Controlled folder access
    DirCreate(dir "\settings.ini.tmp")
    try {
        cfg := ""
        threw := ""
        try cfg := Config.Load(dir)
        catch Any as e
            threw := Type(e)
        AssertEq(threw, "", "Config.Load does not throw")
        AssertTrue(IsObject(cfg), "a config")
        AssertEq(cfg.Get("General.sellEvery", 0), 15, "defaults in memory")
        AssertEq(cfg.saveFail, true, "the failed save is flagged, not thrown")
        AssertTrue(!FileExist(dir "\settings.ini"), "no settings.ini written")
        ; a folder it can write: no flag
        dir2 := CfgTmpDir()
        try {
            AssertEq(Config.Load(dir2).saveFail, false, "a normal folder: no flag")
        } finally {
            CfgTmpClean(dir2)
        }
    } finally {
        CfgTmpClean(dir)
    }
}

; ---- config-3: "[General] ; note" keeps that section --------------------------

Test_CraftCfg_HeaderWithCommentKeepsSection() {
    dir := CfgTmpDir()
    try {
        FileAppend("[General] `; mine`r`nsellEvery=7`r`n[Webhook.1] # main`r`nname=Main`r`nurl=x`r`n[Hotkeys]`r`nstart=F1`r`n", dir "\settings.ini", "UTF-8")
        cfg := Config.Load(dir)
        AssertEq(cfg.Get("General.sellEvery", 15), 7, "commented [General] header still read")
        AssertEq(cfg.Webhooks().Length, 1, "commented [Webhook.1] header still read")
        AssertEq(cfg.Webhooks()[1]["name"], "Main", "its keys")
        AssertEq(cfg.Get("Hotkeys.start", ""), "F1", "a plain header as before")
        cfg.Save()
        cfg2 := Config.Load(dir)
        AssertEq(cfg2.Get("General.sellEvery", 15), 7, "a save keeps it")
        AssertEq(cfg2.Webhooks().Length, 1, "a save keeps the webhook")
        ; a line that is no header still ends the section
        FileDelete(dir "\settings.ini")
        FileAppend("[General]`r`nsellEvery=8`r`n[Broken`r`nsellEvery=9`r`n", dir "\settings.ini", "UTF-8")
        AssertEq(Config.Load(dir).Get("General.sellEvery", 15), 8, "keys under a broken header are skipped")
    } finally {
        CfgTmpClean(dir)
    }
}

; ---- calib-1: a window open already is never closed by the test ---------------

Test_CraftCfg_CalTestInventoryOpenWithTheTabOff() {
    Screen.Reset()
    ; the inventory open, inv_items_tab recorded 300 px off
    g := CtGame()
    g.open := true
    rows := CalTest.Run("", g.Probes(CtSteps(["inv_open", "inv_items_tab", "inv_search"], Map("inv_items_tab", {x: 1384, y: 445}))))
    AssertTrue(g.open, "left open as it was")
    for c in g.clicks
        AssertTrue(!InStr(c, "45,674"), "its button never clicked: " c)
    r := CtFind(rows, "inv_items_tab")
    AssertEq(r.verdict, "REDO", "the step that is off: " r.detail)
    AssertTrue(InStr(r.detail, "1696,449"), "says where the tab is: " r.detail)
    AssertEq(CtFind(rows, "inv_open").verdict, "NOT TESTED", "its button is not blamed")
    ; closed at the start: as before (opened, the tab to redo, closed)
    g := CtGame()
    rows := CalTest.Run("", g.Probes(CtSteps(["inv_open", "inv_items_tab", "inv_search"], Map("inv_items_tab", {x: 1384, y: 445}))))
    AssertEq(CtFind(rows, "inv_open").verdict, "OK", "closed at the start: opened by its button")
    AssertEq(CtFind(rows, "inv_items_tab").verdict, "REDO", "closed at the start: the tab to redo")
    AssertTrue(!g.open, "closed again")
}

Test_CraftCfg_CalTestAuraOpenWithTheSearchOff() {
    Screen.Reset()
    ; the Aura Storage open (title middle 1046,395 as at the preset's
    ; aura_search 1146,490), aura_search recorded 200 px lower
    st := {open: true, clicks: []}
    ocr := (x, y, w, h, scale := 1) => (st.open && CtIn({x: 1046, y: 395}, {x: x, y: y, w: w, h: h})) ? "Aura Storage"
        : (st.open && CtIn({x: 730, y: 611}, {x: x, y: y, w: w, h: h})) ? "[ Information ]" : ""
    lines := (x, y, w, h, scale := 1) => st.open ? [{text: "Aura Storage", x: 1046, y: 395, l: 960, t: 380, r: 1132, b: 410}] : []
    click := (pt, mode) => CtAuraClick(st, pt)
    g := CtGame()
    rows := CalTest.Run("", g.Probes(CtSteps(["aura_open", "aura_search", "aura_equip"], Map("aura_search", {x: 1146, y: 690}))
        , Map("ocr", ocr, "click", click, "lines", lines)))
    AssertTrue(st.open, "left open as it was")
    AssertEq(st.clicks.Length, 0, "nothing clicked")
    r := CtFind(rows, "aura_search")
    AssertEq(r.verdict, "REDO", "the step that is off: " r.detail)
    AssertEq(CtFind(rows, "aura_open").verdict, "NOT TESTED", "its button is not blamed")
    AssertEq(CtFind(rows, "aura_equip").verdict, "OK", "the header reads over aura_equip")
    ; the title found on screen alone (no aura_equip) is enough
    st := {open: true, clicks: []}
    rows := CalTest.Run("", g.Probes(CtSteps(["aura_open", "aura_search"], Map("aura_search", {x: 1146, y: 690}))
        , Map("ocr", ocr, "click", click, "lines", lines)))
    AssertTrue(st.open && st.clicks.Length = 0, "open, nothing clicked (title found on screen)")
    r := CtFind(rows, "aura_search")
    AssertEq(r.verdict, "REDO", "title found: aura_search to redo")
    AssertTrue(InStr(r.detail, "1046,395"), "says where the title is: " r.detail)
    AssertEq(CtFind(rows, "aura_open").verdict, "NOT TESTED", "its button is not blamed (title found)")
}

; The same on the real 2560x1440 frames (real OCR): the inventory and the
; Aura Storage are open, the companion step recorded for another screen:
; their sidebar buttons are not clicked (that would shut them).
Test_CraftCfg_CalTestOpenAlreadyRealFrames() {
    Screen.Reset()
    for f in ["inventory_open_day", "inventory_open_rainy"] {
        path := CtFrame(f)
        AssertTrue(FileExist(path), f " exists")
        g := CtGame()
        rows := CalTest.Run("", g.Probes(CtSteps(["inv_open", "inv_items_tab", "inv_search"], Map("inv_items_tab", {x: 1684, y: 565}, "inv_search", {x: 1434, y: 700}))
            , Map("ocr", (x, y, w, h, scale := 1) => Ocr.ReadFile(path, x, y, w, h, scale)
                , "lines", (x, y, w, h, scale := 1) => Ocr.LinesFile(path, x, y, w, h, scale))))
        for c in g.clicks
            AssertTrue(!InStr(c, "45,674"), f ": inv_open never clicked on an open inventory: " c)
        AssertEq(CtFind(rows, "inv_open").verdict, "NOT TESTED", f ": inv_open not blamed")
        r := CtFind(rows, "inv_items_tab")
        AssertEq(r.verdict, "REDO", f ": the tab to redo")
        AssertTrue(RegExMatch(r.detail, "Items tab is at 1[67]\d\d,4[34]\d"), f ": says where it is: " r.detail)
    }
    path := CtFrame("aura_selected_sailor")
    g := CtGame()
    rows := CalTest.Run("", g.Probes(CtSteps(["aura_open", "aura_search"], Map("aura_search", {x: 1146, y: 640}))
        , Map("ocr", (x, y, w, h, scale := 1) => Ocr.ReadFile(path, x, y, w, h, scale)
            , "lines", (x, y, w, h, scale := 1) => Ocr.LinesFile(path, x, y, w, h, scale)
            , "click", (pt, mode) => (g.clicks.Push(pt.x "," pt.y), 1))))
    AssertEq(g.clicks.Length, 0, "the open Aura Storage: nothing clicked")
    AssertEq(CtFind(rows, "aura_open").verdict, "NOT TESTED", "aura_open not blamed")
    r := CtFind(rows, "aura_search")
    AssertEq(r.verdict, "REDO", "aura_search to redo: " r.detail)
    AssertTrue(InStr(r.detail, "the title is at"), "the title found on screen: " r.detail)
}

; ---- quests-2: a dropped Close with the title unread (1080p) -----------------

Test_CraftCfg_MMDroppedCloseWithUnreadableTitleIsClickedAgain() {
    b := MmStd()
    b.titleGoneAfter := 6                       ; 1080p: the title stops reading mid-round
    b.DefineProp("Click", {call: CcfDropFirstClose})
    UiStuck.Reset()
    m := MmMake(b)
    try {
        AssertEq(m.t.Run(SchedCtx()), 1, "played")
        AssertTrue(b.Count("close") >= 2, "Close clicked again (" b.Count("close") ")")
        AssertTrue(b.closed, "the board closed")
        AssertEq(UiStuck.Due(), false, "no rejoin needed")
    } finally {
        MmClean(m)
        UiStuck.Reset()
    }
    ; the tidy sees a board whose title does not read by its Close
    b2 := MmStd()
    b2.titleGoneAfter := 6
    b2.DefineProp("Click", {call: MmNoCloseClick})
    m2 := MmMake(b2)
    try {
        m2.t.Run(SchedCtx())
        AssertTrue(!b2.closed, "still open")
        AssertEq(m2.t.Leftovers()[1].up.Call(), "Memory Match board", "the tidy sees the board by its Close")
    } finally {
        MmClean(m2)
        UiStuck.Reset()
    }
}

; the tidy's check on real frames, the title read missing (1080p): Close
; under the board (plain on the clip, red ink over the bright sky) says
; the board is up; frames without the board say nothing
Test_CraftCfg_MMTidyCloseOnRealFrames() {
    for f in ["mm_end.jpg", "mm_end_live_snowy_1440.png"] {
        t := CcfMmFrameTask(A_ScriptDir "\screens\" f)
        AssertEq(t.Leftovers()[1].up.Call(), "Memory Match board", f ": the board is up (its Close shows)")
    }
    for f in ["mm_board_start.jpg", "aura_search_sailor.jpg", "mari_night_buttons.jpg", "fish_raised_card_day.jpg", "inventory_open_day.jpg"] {
        t := CcfMmFrameTask(A_ScriptDir "\screens\" f)
        AssertEq(t.Leftovers()[1].up.Call(), "", f ": no Close, no board")
    }
}

; a task reading the frame at path, the title box reading nothing
CcfMmFrameTask(path) {
    L := MemoryMatchTask.Layout
    rd := (x, y, w, h, s := 1) => (x = L.title.x && y = L.title.y) ? "" : Ocr.ReadFile(path, x, y, w, h, s)
    return MemoryMatchTask({cfg: QmCfg(Map("MemoryMatch.enabled", "1"), MmRoutes()), io: MmStd().io, cal: QmCal()
        , ocr: rd, ink: (x, y, w, h, s := 1, k := 0) => Ocr.ReadFile(path, x, y, w, h, s, k)
        , vision: MmStd().vision, log: (s) => 0, clock: () => "20261027120000"
        , statePath: A_Temp "\vesper_ccf_mm_unused.json"})
}

; Roblox drops the first click on Close (lag)
CcfDropFirstClose(b, x, y) {
    L := MemoryMatchTask.Layout
    if (x = L.close.x && y = L.close.y && !b.HasOwnProp("dropped")) {
        b.dropped := true
        b.log.Push("close")
        return
    }
    MmBoard.Prototype.Click.Call(b, x, y)
}
