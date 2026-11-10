#Requires AutoHotkey v2.0
; Fishing false-bite fix (live test 2026-10-25): white scenery at the bite
; pixel was read as a bite, the minigame clicked into the world and counted a
; catch, and the 61 s pathing timer restarted every cast so the macro never
; re-pathed. Also: Start now re-paths first (Sell runs before fishing).
; Helpers (FsIO, FsDeps, FsScreen, FsCastScreen, FsMakeCfg, ...) live in test_fishing.ahk;
; App fakes in test_app.ahk.
#Include ..\lib\tasks\Fishing.ahk
#Include ..\lib\tasks\Sell.ahk
#Include ..\lib\App.ahk

; ---- helpers (names must not start with Test_) -----------------------------

; Bite pixel read counter: white only on the reads listed in `whiteReads`.
FsFlicker(cnt, whiteReads) {
    cnt.n += 1
    return whiteReads.Has(cnt.n) ? 0xFFFFFF : 0x101010
}

FsClicks(io) {
    n := 0
    for line in io.log
        if (SubStr(line, 1, 6) = "click@")
            n++
    return n
}

FsHasLog(logs, text) {
    for l in logs
        if InStr(l, text)
            return true
    return false
}

FsCountLog(logs, text) {
    n := 0
    for l in logs
        if InStr(l, text)
            n++
    return n
}

; ---- B: baseline guard -------------------------------------------------------

Test_FishRepath_MomentaryWhiteAfterCastIsNotScenery() {
    t := FsMakeCfg()
    FsScreen.Install()
    try {
        st := SchedState()
        io := FsIO()
        logs := []
        ; white for 200 ms right after the rod settle (panel icon sliding past), then a real bite at 3 s
        FsScreen.fn := (x, y) => (x = 1536 && y = 1119)
            ? ((io.lastClick.Has("click@1161,1124") && (io.clock - io.lastClick["click@1161,1124"] < 500 || io.clock - io.lastClick["click@1161,1124"] >= 3000)) ? 0xFFFFFF : 0x101010)
            : ((x = 1261 && y = 1033 && !FsScreen.inGrab) ? 0x3366CC : 0x101010)
        r := FishingTask(t.cfg, st, FsDeps(io, "", true, logs)).CatchOnce(SchedCtx())
        AssertTrue(r != "repath", "momentary white is not scenery (r=" r ")")
        AssertEq(FsHasLog(logs, "stays white"), false, "no scenery log")
        AssertEq(st.needRepath, false, "no re-path")
    } finally {
        FsScreen.Restore()
        FsClean(t.dir)
    }
}

Test_FishRepath_WhiteBeforeBiteRepaths() {
    t := FsMakeCfg()
    FsScreen.Install()
    try {
        st := SchedState()
        io := FsIO()
        logs := []
        FsScreen.fn := (x, y) => (x = 1536 && y = 1119) ? 0xFFFFFF : 0x202020   ; white scenery
        task := FishingTask(t.cfg, st, FsDeps(io, "", true, logs))
        r := task.CatchOnce(SchedCtx())
        AssertEq(r, "repath", "white before any bite -> repath")
        AssertEq(st.fishLoops, 0, "not counted as a catch, fishLoops not inflated")
        AssertEq(st.needRepath, true, "Sell made due (needRepath)")
        AssertEq(FsClicks(io), 1, "only the rod click, no minigame/close clicks")
        AssertEq(io.Has("move 1263,1177"), false, "no minigame (mouse never parked)")
        AssertTrue(io.clock <= 400 + FishLogic.BaselineMs, "decided right after the baseline window, clock=" io.clock)
        AssertTrue(FsHasLog(logs, "fishing: bite pixel stays white (not at fishing spot / white scenery) - re-pathing"), "logged")
        AssertEq(FsCountLog(logs, "bite pixel stays white"), 1, "logged once")
        ; scheduler: Sell runs next, fishing.Run sends no input while due
        sell := SellTask(t.cfg, st, FsDeps(FsIO()))
        AssertEq(sell.CanRun(st), true, "Sell.CanRun honours needRepath")
        AssertEq(Scheduler.Next([sell, task], st, 0).name, "sell", "scheduler picks sell")
        io2 := FsIO()
        FishingTask(t.cfg, st, FsDeps(io2)).Run(SchedCtx())
        AssertEq(io2.log.Length, 0, "fishing yields while a repath is due")
    } finally {
        FsScreen.Restore()
        FsClean(t.dir)
    }
}

; ---- C: two consecutive polls ------------------------------------------------

Test_FishRepath_SinglePollFlickerNotABite() {
    t := FsMakeCfg()
    FsScreen.Install()
    try {
        t.cfg.Set("General.fishingFailsafeSec", 2)
        t.cfg.Set("General.pathingFailsafeSec", 3)
        st := SchedState()
        io := FsIO()
        logs := []
        cnt := {n: 0}
        ; read 1 = baseline; read 10 alone is white (one-poll flicker)
        FsScreen.fn := (x, y) => (x = 1536 && y = 1119) ? FsFlicker(cnt, Map(10, 1)) : 0x3366CC
        r := FishingTask(t.cfg, st, FsDeps(io, "", true, logs)).CatchOnce(SchedCtx())
        AssertEq(r, "repath", "flicker ignored, pathing failsafe fires")
        AssertTrue(FsHasLog(logs, "pathing failsafe"), "via the pathing failsafe")
        AssertEq(io.Has("move 1263,1177"), false, "no minigame on a one-poll flicker")
        AssertEq(st.fishLoops, 0, "no catch")
        ; two consecutive white polls = a bite
        io2 := FsIO()
        cnt2 := {n: 0}
        FsScreen.fn := (x, y) => (x = 1536 && y = 1119) ? FsFlicker(cnt2, Map(10, 1, 11, 1)) : 0x3366CC
        st2 := SchedState()
        r2 := FishingTask(t.cfg, st2, FsDeps(io2)).CatchOnce(SchedCtx())
        AssertEq(r2, "ok", "two consecutive white polls -> bite, catch ok")
        AssertEq(st2.fishLoops, 1, "real catch counted")
        AssertTrue(io2.Has("move 1263,1177"), "minigame ran")
    } finally {
        FsScreen.Restore()
        FsClean(t.dir)
    }
}

; ---- D: reel bar sanity ------------------------------------------------------

Test_FishRepath_NoReelBarNoClicksThenRepath() {
    t := FsMakeCfg()
    FsScreen.Install()
    try {
        st := SchedState()
        io := FsIO()
        logs := []
        FsCastScreen(io, 1000, 0x3366CC, (x, y) => 0x202020)     ; bar colour never in the strip
        task := FishingTask(t.cfg, st, FsDeps(io, "", true, logs))
        r := task.CatchOnce(SchedCtx())
        AssertEq(r, "nobite", "no reel bar -> nobite")
        AssertEq(FsClicks(io), 1, "rod only: no minigame clicks, no close click")
        AssertEq(st.fishLoops, 0, "fishLoops not incremented")
        AssertEq(st.needRepath, false, "first non-bite does not repath yet")
        AssertTrue(io.clock <= 1030 + 100 + 1200, "gave up within ~1 s of the minigame start, clock=" io.clock)
        AssertTrue(FsHasLog(logs, "fishing: no reel bar - not a real bite"), "logged")
        r2 := task.CatchOnce(SchedCtx())
        AssertEq(r2, "repath", "second consecutive non-bite -> repath")
        AssertEq(st.needRepath, true, "Sell made due")
        AssertEq(st.fishLoops, 0, "still no fake catches")
        AssertEq(FsClicks(io), 2, "two rod clicks, nothing else")
    } finally {
        FsScreen.Restore()
        FsClean(t.dir)
    }
}

Test_FishRepath_RealCatchResetsNonBiteCount() {
    t := FsMakeCfg()
    FsScreen.Install()
    try {
        st := SchedState()
        io := FsIO()
        bar := 0x3366CC
        mode := {bar: false}
        FsCastScreen(io, 1000, bar, (x, y) => mode.bar ? bar : 0x202020)
        task := FishingTask(t.cfg, st, FsDeps(io))
        AssertEq(task.CatchOnce(SchedCtx()), "nobite", "1st: no bar")
        mode.bar := true
        AssertEq(task.CatchOnce(SchedCtx()), "ok", "2nd: real catch")
        AssertEq(st.fishLoops, 1, "real catch counted")
        mode.bar := false
        AssertEq(task.CatchOnce(SchedCtx()), "nobite", "3rd: no bar again is only the 1st in a row")
        AssertEq(st.needRepath, false, "no repath")
    } finally {
        FsScreen.Restore()
        FsClean(t.dir)
    }
}

Test_FishRepath_BarAppearsLateStillCatches() {
    t := FsMakeCfg()
    FsScreen.Install()
    try {
        st := SchedState()
        io := FsIO()
        bar := 0x3366CC
        ; bite at ~1030-1050; bar shows in the strip only from clock 1600 on
        FsCastScreen(io, 1000, bar, (x, y) => io.clock >= 1600 ? bar : 0x202020)
        r := FishingTask(t.cfg, st, FsDeps(io)).CatchOnce(SchedCtx())
        AssertEq(r, "ok", "bar within ~1 s -> real catch")
        AssertEq(io.Count("click@1263,1177"), 0, "no clicks before the bar was seen, none while present")
        AssertEq(st.fishLoops, 1, "counted")
    } finally {
        FsScreen.Restore()
        FsClean(t.dir)
    }
}

; ---- E: Run + scheduler ------------------------------------------------------

Test_FishRepath_RunRetriesNoBiteThenYieldsToSell() {
    t := FsMakeCfg()
    FsScreen.Install()
    try {
        st := SchedState()
        io := FsIO()
        FsCastScreen(io, 1000, 0x3366CC, (x, y) => 0x202020)
        task := FishingTask(t.cfg, st, FsDeps(io))
        task.Run(SchedCtx())
        AssertEq(io.Count("click@1161,1124"), 2, "Run recast once after a non-bite, then returned on repath")
        AssertEq(FsClicks(io), 2, "no other clicks")
        AssertEq(st.fishLoops, 0, "no fake catches")
        AssertEq(st.needRepath, true, "repath due")
        sell := SellTask(t.cfg, st, FsDeps(FsIO()))
        AssertEq(Scheduler.Next([sell, task], st, 0).name, "sell", "sell next")
    } finally {
        FsScreen.Restore()
        FsClean(t.dir)
    }
}

Test_FishRepath_PathingFailsafeNoInflation() {
    t := FsMakeCfg()
    FsScreen.Install()
    try {
        t.cfg.Set("General.fishingFailsafeSec", 2)
        t.cfg.Set("General.pathingFailsafeSec", 3)
        st := SchedState()
        st.fishLoops := 4
        FsScreen.fn := (x, y) => 0x101010
        AssertEq(FishingTask(t.cfg, st, FsDeps(FsIO())).CatchOnce(SchedCtx()), "repath", "pathing failsafe")
        AssertEq(st.fishLoops, 4, "fishLoops untouched (no jump to sellEvery)")
        AssertEq(st.needRepath, true, "needRepath set")
    } finally {
        FsScreen.Restore()
        FsClean(t.dir)
    }
}

Test_FishRepath_SellClearsNeedRepath() {
    t := FsMakeCfg()
    FsScreen.Install()
    try {
        st := SchedState()
        AssertEq(st.needRepath, false, "SchedState declares needRepath = false")
        st.needRepath := true
        io := FsIO()
        FsSellScreen(io, 1)
        sell := SellTask(t.cfg, st, FsDeps(io, []))
        AssertEq(sell.CanRun(st), true, "due with fishLoops 0")
        sell.Run(SchedCtx())
        AssertEq(st.needRepath, false, "cleared after a finished sell run")
        AssertEq(st.fishLoops, 0, "fishLoops 0")
        AssertEq(sell.CanRun(st), false, "no longer due")
        ; stopped part way: still due
        st2 := SchedState()
        st2.needRepath := true
        io2 := FsIO(12)
        FsScreen.fn := (x, y) => 0x101010
        SellTask(t.cfg, st2, FsDeps(io2, [])).Run(SchedCtx())
        AssertEq(st2.needRepath, true, "stopped sell keeps needRepath")
    } finally {
        FsScreen.Restore()
        FsClean(t.dir)
    }
}

; ---- A: re-path on Start -----------------------------------------------------

Test_FishRepath_ConfigDefault() {
    AssertEq(Config.IniDefaults()["General"]["repathOnStart"], "1", "repathOnStart default 1")
}

Test_App_StartRepathsFirst() {
    sell := AppFakeTask("sell", 6, false)
    t := AppTestMake(Map("tasks", Map("fishing", AppFakeTask("fishing", 99), "sell", sell)))
    AssertEq(t.app.state.needRepath, false, "not due before Start")
    t.app.Start()
    AssertEq(t.app.state.needRepath, true, "Start makes the re-path (Sell) due")
    ; a finished sell clears it; the next F1 start sets it again
    t.app.state.needRepath := false
    t.app.Stop()
    t.app.Start()
    AssertEq(t.app.state.needRepath, true, "each Start re-paths")
    ; disabled by setting
    t2 := AppTestMake(Map("tasks", Map("fishing", AppFakeTask("fishing", 99), "sell", AppFakeTask("sell", 6, false))
        , "cfgVals", Map("General.sound", 0, "Medal.onRareBiome", 0, "General.repathOnStart", 0)))
    t2.app.Start()
    AssertEq(t2.app.state.needRepath, false, "repathOnStart=0 disables it")
    ; no sell task (disabled by bad data): never block fishing
    t3 := AppTestMake(Map("tasks", Map("fishing", AppFakeTask("fishing", 99))))
    t3.app.Start()
    AssertEq(t3.app.state.needRepath, false, "no sell task -> no repath flag")
}
