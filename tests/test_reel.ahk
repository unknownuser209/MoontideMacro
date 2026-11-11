#Requires AutoHotkey v2.0
; Arrow reel controller (2026 reel UI): keep the white arrow (end of the
; player's click bar) on the fish box. Colours change per fish and with the
; light, so the reader uses none: arrow = white base line at y 1025, click
; bar colour = the bar's left end, fish = biggest block of other colour.
; Colours below come from lossless captures (2026-10-25).
; Helpers live in test_fishing.ahk and test_fishing_repath.ahk.

RlRow(x1, x2, stride, fn) {
    row := []
    x := x1
    while (x <= x2) {
        row.Push(fn.Call(x))
        x += stride
    }
    return row
}

RlArrowRow(m) => RlRow(1042, 1517, 2, (x) => (Abs(x - m) <= 13) ? 0xFFFFFF : 0x00000B)

Test_Reel_ScanBlueBarPurpleFishUnderIt() {
    ; capture 652: blue bar to 1347, purple fish (lighter, under the bar) 1247..1322, white timer digits inside the fish
    bar := RlRow(1042, 1517, 2, (x) => (x >= 1284 && x <= 1287) ? 0xFFFFFF
        : (x >= 1247 && x <= 1322) ? 0x8489FF
        : (x <= 1347) ? 0x3DA8FF : 0x00000B)
    s := FishLogic.ReelScan(RlArrowRow(1347), bar, 1042, 2)
    AssertTrue(Abs(s.m - 1347) <= 2, "arrow at the bar's end (m=" s.m ")")
    AssertTrue(Abs(s.p1 - 1247) <= 2 && Abs(s.p2 - 1322) <= 2, "fish " s.p1 ".." s.p2)
    AssertEq(s.fill, 0x3DA8FF, "click bar colour from the left end")
}

Test_Reel_ScanYellowFishAheadOfTheBar() {
    ; capture 955: bar to 1192, yellow fish 1224..1300 with dark digits
    bar := RlRow(1042, 1517, 2, (x) => (x >= 1262 && x <= 1268) ? 0x04000B
        : (x >= 1224 && x <= 1300) ? 0xE5CB3E
        : (x <= 1192) ? 0x38BEFF : 0x04000B)
    s := FishLogic.ReelScan(RlArrowRow(1192), bar, 1042, 2)
    AssertTrue(Abs(s.m - 1192) <= 2, "arrow (m=" s.m ")")
    AssertTrue(Abs(s.p1 - 1224) <= 2 && Abs(s.p2 - 1300) <= 2, "yellow fish " s.p1 ".." s.p2)
}

Test_Reel_ScanIgnoresTimerTextAndEmptyBar() {
    ; red timer digits (small) must not beat the fish block
    bar := RlRow(1042, 1517, 2, (x) => (x >= 1268 && x <= 1293 && Mod(x, 6) < 3) ? 0xFF5D74
        : (x >= 1100 && x <= 1175) ? 0x8182FF
        : (x <= 1207) ? 0x3BA8FF : 0x00000B)
    s := FishLogic.ReelScan(RlArrowRow(1207), bar, 1042, 2)
    AssertTrue(Abs(s.p1 - 1100) <= 2 && Abs(s.p2 - 1175) <= 2, "fish, not the digits: " s.p1 ".." s.p2)
    ; empty click bar: fish is any colour block
    bar2 := RlRow(1042, 1517, 2, (x) => (x >= 1400 && x <= 1476) ? 0x8C46E6 : 0x00000B)
    s2 := FishLogic.ReelScan(RlArrowRow(1050), bar2, 1042, 2)
    AssertEq(s2.fill, "", "no click bar colour")
    AssertTrue(Abs(s2.p1 - 1400) <= 2, "fish found")
    ; no arrow: m = 0 when there is no white run
    s3 := FishLogic.ReelScan(RlRow(1042, 1517, 2, (x) => 0x204020), RlRow(1042, 1517, 2, (x) => 0x00000B), 1042, 2)
    AssertEq(s3.m, 0, "no arrow")
    AssertEq(s3.p2, 0, "no fish")
}

Test_Reel_ScanLowContrastFishUnderTheBar() {
    ; first catch of the 2026-10-25 run (day): bar (47,255,255) with noise, fish under it (0,255,255) 1320..1394
    bar := RlRow(1042, 1517, 2, (x) => (x >= 1320 && x <= 1394) ? 0x00FFFF
        : (x <= 1400) ? (Mod(x, 10) < 5 ? 0x2FFFFF : 0x32FAFF) : 0x241B19)
    s := FishLogic.ReelScan(RlArrowRow(1400), bar, 1042, 2)
    AssertTrue(Abs(s.p1 - 1320) <= 2 && Abs(s.p2 - 1394) <= 2, "day: fish under the bar " s.p1 ".." s.p2)
    ; catch 4 (night): bar (71,173,255) ~ (69,169,255), fish under it (75,156,255) 1180..1256
    bar2 := RlRow(1042, 1517, 2, (x) => (x >= 1180 && x <= 1256) ? 0x4B9CFF
        : (x <= 1300) ? (Mod(x, 8) < 4 ? 0x47ADFF : 0x45A9FF) : 0x221919)
    s2 := FishLogic.ReelScan(RlArrowRow(1300), bar2, 1042, 2)
    AssertTrue(Abs(s2.p1 - 1180) <= 2 && Abs(s2.p2 - 1256) <= 2, "night: fish under the bar " s2.p1 ".." s2.p2)
    ; anti-aliased first pixels must not become the bar colour
    bar3 := RlRow(1042, 1517, 2, (x) => (x <= 1043) ? 0x9AA0B0 : (x <= 1300) ? 0x44B4FF : 0x221919)
    s3 := FishLogic.ReelScan(RlArrowRow(1300), bar3, 1042, 2)
    AssertEq(s3.p2, 0, "no fish in a plain bar (edge pixels ignored)")
}

Test_Reel_ArrowRestingAtTheLeftEdge() {
    ; capture 2026-10-26 #20: empty bar, the arrow's base line at 1028..1055,
    ; so only 1042..1055 (14 px) is inside the strip; green fish 1254..1328
    arrow := RlRow(1042, 1517, 2, (x) => (x <= 1055) ? 0xFFFFFF : 0x1A3A70)
    bar := RlRow(1042, 1517, 2, (x) => (x >= 1254 && x <= 1328) ? 0x77E04A : 0x131A2A)
    s := FishLogic.ReelScan(arrow, bar, 1042, 2)
    AssertEq(s.m, 1042, "the arrow resting at the left end is seen (m=" s.m ")")
    AssertTrue(Abs(s.p1 - 1254) <= 2 && Abs(s.p2 - 1328) <= 2, "fish " s.p1 ".." s.p2)
    AssertEq(FishLogic.ReelDecide(s, {}, 0, 100, 0.15), true, "so it clicks to bring the bar to the fish")
}

Test_Reel_SnowIsNotTheArrow() {
    ; SNOWY: white snow above the bar makes a long white run on the arrow row;
    ; the arrow-sized run (1300 +-13) is the arrow, the 200 px of snow is not
    arrow := RlRow(1042, 1517, 2, (x) => (x >= 1060 && x <= 1260) || Abs(x - 1300) <= 13 ? 0xF4F8FF : 0x6A7C90)
    bar := RlRow(1042, 1517, 2, (x) => (x >= 1400 && x <= 1476) ? 0x8C46E6 : (x <= 1300) ? 0x3DA8FF : 0x131A2A)
    s := FishLogic.ReelScan(arrow, bar, 1042, 2)
    AssertTrue(Abs(s.m - 1300) <= 2, "the arrow, not the snow (m=" s.m ")")
    ; only snow, no arrow-sized run: no arrow (no blind clicking)
    arrow2 := RlRow(1042, 1517, 2, (x) => (x >= 1060 && x <= 1400) ? 0xF4F8FF : 0x6A7C90)
    AssertEq(FishLogic.ReelScan(arrow2, bar, 1042, 2).m, 0, "a wide white run is scenery")
    ; snow touching the strip's end is not an arrow at rest either
    arrow3 := RlRow(1042, 1517, 2, (x) => (x <= 1200) ? 0xF4F8FF : 0x6A7C90)
    AssertEq(FishLogic.ReelScan(arrow3, bar, 1042, 2).m, 0, "wide snow at the edge is scenery")
}

Test_Reel_DecideClicksTowardTheFish() {
    st := {}
    AssertEq(FishLogic.ReelDecide({m: 1100, p1: 1300, p2: 1376}, st, 0, 40, 0.4), true, "left of the fish -> click")
    st := {}
    AssertEq(FishLogic.ReelDecide({m: 1450, p1: 1300, p2: 1376}, st, 0, 40, 0.4), false, "right of the fish -> let it drift")
    st := {}
    AssertEq(FishLogic.ReelDecide({m: 1100, p1: 0, p2: 0}, st, 0, 40, 0.4), false, "no fish -> no click")
    st := {}
    AssertEq(FishLogic.ReelDecide({m: 0, p1: 1300, p2: 1376}, st, 0, 40, 0.4), false, "no arrow -> no click")
    st := {}
    FishLogic.ReelDecide({m: 1300, p1: 1310, p2: 1386}, st, 0, 80, 0.4)
    AssertEq(FishLogic.ReelDecide({m: 1330, p1: 1320, p2: 1396}, st, 30, 80, 0.4), false, "fast approach -> stop early")
}

; Simulated reel: the arrow drifts left 0.12 px/ms and each click pushes it
; 22 px right. Fish box 76 px wide at f1 (moves +-swing). The bar is drawn
; in blue, the fish purple (lighter where the bar covers it).
class RlSim {
    __New(io, swing := 0, readyMs := 0, momentum := false, biteAfter := 2000) {
        this.io := io
        this.biteAfter := biteAfter
        this.momentum := momentum   ; true: gravity + click kicks (as in the captures)
        this.v := 0.3
        this.swing := swing
        this.readyMs := readyMs     ; "Ready!" phase: fish hidden
        this.firstGrab := -1
        this.f1 := 1300
        this.m := 1262.0
        this.t := 0
        this.clicks := 0
        this.grabs := 0
        this.onFish := 0
        this.lastClock := -1
        this.trace := ""
    }
    Step() {
        io := this.io
        if (io.clock = this.lastClock)
            return
        if (this.firstGrab < 0) {
            this.firstGrab := io.clock
            this.t := io.clock
        }
        dt := io.clock - this.t
        this.t := io.clock
        this.lastClock := io.clock
        n := io.Count("click@1263,1177")
        if this.momentum {
            g := 0.0008
            this.m += this.v * dt - 0.5 * g * dt * dt
            this.v := Max(-0.4, this.v - g * dt)
            if (n > this.clicks)
                this.v := 0.25
        } else {
            this.m += 22 * (n - this.clicks) - 0.12 * dt
        }
        this.clicks := n
        this.m := Max(1042, Min(1517, this.m))
        this.f1 := 1300 + Round(this.swing * Sin(io.clock / 800))
        this.grabs++
        if (this.m >= this.f1 && this.m <= this.f1 + 76)
            this.onFish++
        if (Mod(this.grabs, 25) = 0)
            this.trace .= Round(this.m) "/" this.f1 ","
    }
    Pixel(x, y) {
        io := this.io
        if (x = 1536 && y = 1119)
            return (io.lastClick.Has("click@1161,1124") && io.clock >= io.lastClick["click@1161,1124"] + this.biteAfter) ? 0xFFFFFF : 0x101010
        if (y = 1025) {
            if (x = 1042)
                this.Step()
            return (this.firstGrab >= 0 && Abs(x - this.m) <= 13) ? 0xFFFFFF : 0x00000B
        }
        if (y = 1030)
            return (this.firstGrab >= 0) ? 0xFFFFFF : 0x101010      ; bar top border
        if (y = 1044) {
            fish := x >= this.f1 && x <= this.f1 + 76 && io.clock >= this.firstGrab + this.readyMs
            if (x <= this.m)
                return fish ? 0x8489FF : 0x3DA8FF
            return fish ? 0x8C46E6 : 0x00000B
        }
        return 0x101010
    }
}

RlRun(swing, readyMs, &sim, &logs, momentum := false, biteAfter := 2000) {
    t := FsMakeCfg()
    t.cfg.Set("General.legacyReel", 0)
    FsScreen.Install()
    try {
        st := SchedState()
        io := FsIO()
        logs := []
        sim := RlSim(io, swing, readyMs, momentum, biteAfter)
        s := sim
        FsScreen.fn := (x, y) => s.Pixel(x, y)
        r := FishingTask(t.cfg, st, FsDeps(io, "", true, logs)).CatchOnce(SchedCtx())
        return {r: r, st: st}
    } finally {
        FsScreen.Restore()
        FsClean(t.dir)
    }
}

Test_Reel_KeepsArrowOnTheFish() {
    sim := "", logs := ""
    o := RlRun(0, 0, &sim, &logs)
    AssertEq(o.r, "ok", "catch finished")
    AssertTrue(sim.clicks > 10, "it reels (clicks=" sim.clicks ")")
    AssertTrue(sim.onFish / sim.grabs > 0.85, "arrow on the fish " Round(100 * sim.onFish / sim.grabs) "% of the time; trace " sim.trace)
    AssertEq(o.st.fishLoops, 1, "counted")
}

Test_Reel_FollowsAMovingFish() {
    sim := "", logs := ""
    o := RlRun(90, 0, &sim, &logs)      ; fish speed up to ~0.11 px/ms, the arrow falls at 0.12
    AssertEq(o.r, "ok", "catch finished")
    AssertTrue(sim.onFish / sim.grabs > 0.75, "arrow on a moving fish " Round(100 * sim.onFish / sim.grabs) "% of the time; trace " sim.trace)
}

Test_Reel_HandlesMomentum() {
    sim := "", logs := ""
    o := RlRun(60, 0, &sim, &logs, true)
    AssertEq(o.r, "ok", "catch finished")
    AssertTrue(sim.onFish / sim.grabs > 0.7, "arrow with momentum on the fish " Round(100 * sim.onFish / sim.grabs) "% of the time; trace " sim.trace)
}

Test_Reel_QuickBiteIsNotScenery() {
    sim := "", logs := ""
    o := RlRun(0, 0, &sim, &logs, false, 0)       ; the fish bites at once: bite pixel white from the cast on
    AssertEq(o.r, "ok", "reeled, not re-pathed")
    AssertEq(FsHasLog(logs, "stays white"), false, "not taken for white scenery")
    AssertEq(o.st.needRepath, false, "no re-path")
    AssertTrue(sim.clicks > 10, "reels (clicks=" sim.clicks ")")
}

Test_Reel_WhiteBitePixelIsNotABite() {
    ; the waiting panel's white border on the bite pixel (long tip text), or snow:
    ; no reel bar ever shows, so no bite, no re-path right away; the pathing
    ; failsafe re-paths after pathingFailsafeSec
    t := FsMakeCfg()
    t.cfg.Set("General.legacyReel", 0)
    FsScreen.Install()
    try {
        st := SchedState()
        io := FsIO()
        logs := []
        FsScreen.fn := (x, y) => 0xFFFFFF
        r := FishingTask(t.cfg, st, FsDeps(io, "", true, logs)).CatchOnce(SchedCtx())
        AssertEq(r, "repath", "no reel -> pathing failsafe")
        AssertEq(FsHasLog(logs, "stays white"), false, "white bite pixel ignored")
        AssertTrue(FsHasLog(logs, "fishing: pathing failsafe"), "pathing failsafe logged")
        AssertTrue(io.clock >= 61000, "only after pathingFailsafeSec (clock " io.clock ")")
        AssertEq(io.Has("move 1263,1177"), false, "never started a minigame")
        AssertEq(st.needRepath, true, "Sell due")
    } finally {
        FsScreen.Restore()
        FsClean(t.dir)
    }
}

Test_Reel_WaitingPanelIsNotAReel() {
    ; 22:26:58 screenshot: the waiting panel's title underline (~70 % wide, y 1025) and
    ; tip text; arrow row sees a white run, but there is no full-width bar border
    t := FsMakeCfg()
    t.cfg.Set("General.legacyReel", 0)
    FsScreen.Install()
    try {
        FsScreen.fn := (x, y) => (y = 1025 && x >= 1110 && x <= 1442) ? 0xFFFFFF
            : (y = 1044 && x >= 1050 && x <= 1300 && Mod(x, 7) < 2) ? 0x9A8C82
            : 0x2A211E
        task := FishingTask(t.cfg, SchedState(), FsDeps(FsIO()))
        AssertEq(task._ReelUp(), false, "waiting panel is not a reel")
        FsScreen.fn := (x, y) => (y = 1025 && Abs(x - 1300) <= 13) ? 0xFFFFFF
            : (y = 1030) ? 0xFFFFFF
            : (y = 1044) ? (x <= 1300 ? 0x3DA8FF : 0x00000B) : 0x00000B
        AssertEq(task._ReelUp(), true, "reel with its border is up")
        FsScreen.fn := (x, y) => (y = 1025 && Abs(x - 1300) <= 13) ? 0xFFFFFF
            : (y = 1044) ? (x <= 1300 ? 0x3DA8FF : 0x00000B) : 0x00000B
        AssertEq(task._ReelUp(), false, "no border -> not up")
    } finally {
        FsScreen.Restore()
        FsClean(t.dir)
    }
}

Test_Reel_ReadyPhaseIsARealBite() {
    sim := "", logs := ""
    o := RlRun(0, 1500, &sim, &logs)
    AssertEq(o.r, "ok", "reels after the Ready phase")
    AssertEq(FsHasLog(logs, "not a real bite"), false, "not dropped as a false bite")
    AssertTrue(sim.clicks > 10, "reels (clicks=" sim.clicks ")")
}

Test_Reel_NoReelBarNoClicks() {
    t := FsMakeCfg()
    t.cfg.Set("General.legacyReel", 0)
    FsScreen.Install()
    try {
        st := SchedState()
        io := FsIO()
        FsCastScreen(io, 2000, 0x3366CC, (x, y) => 0xFFFFFF)      ; bite pixel white, but no reel bar ever
        r := FishingTask(t.cfg, st, FsDeps(io)).CatchOnce(SchedCtx())
        AssertEq(r, "repath", "no reel bar -> no bite (pathing failsafe in the end)")
        AssertEq(io.Count("click@1263,1177"), 0, "no reel clicks")
        AssertEq(st.fishLoops, 0, "not counted")
    } finally {
        FsScreen.Restore()
        FsClean(t.dir)
    }
}

; FsIO plus a scripted Fish/Exit button read through Ocr().
class RlBtnIO extends FsIO {
    __New(showAt) {
        super.__New()
        this.showAt := showAt
    }
    Ocr(x, y, w, h, scale := 1) => (x = 1050 && this.clock >= this.showAt) ? "Fish" : ""
}

Test_Reel_WaitsForTheFishButtonBeforeCasting() {
    t := FsMakeCfg()
    FsScreen.Install()
    try {
        st := SchedState()
        io := RlBtnIO(1500)                     ; button comes back 1.5 s late
        FsScreen.fn := (x, y) => 0x101010
        ctx := SchedCtx()
        task := FishingTask(t.cfg, st, FsDeps(io))
        AssertEq(task._WaitFishButton(ctx), 1, "button seen")
        AssertTrue(io.clock >= 1500, "waited for it (clock " io.clock ")")
        io2 := RlBtnIO(999999)                  ; never shows
        task2 := FishingTask(t.cfg, st, FsDeps(io2))
        AssertEq(task2._WaitFishButton(ctx), 0, "gives up and casts anyway")
        AssertTrue(io2.clock <= 4500, "bounded wait")
    } finally {
        FsScreen.Restore()
        FsClean(t.dir)
    }
}

; FsIO with a scripted fishing panel: button text and title read via Ocr().
; The Fish button covered by Eden's combo bar (reads nothing), the panel's
; status line idle: cast without waiting the whole fishButton.waitMs
class RlCoveredIO extends FsIO {
    __New(status) {
        super.__New()
        this.status := status
    }
    Ocr(x, y, w, h, scale := 1) => (x = FishingTask.StatusRect[1] && y = FishingTask.StatusRect[2]) ? this.status : ""
}

Test_Reel_CoveredButtonUsesTheStatusLine() {
    t := FsMakeCfg()
    FsScreen.Install()
    try {
        st := SchedState()
        ctx := SchedCtx()
        io := RlCoveredIO("Location • Gol's World Moin Island")
        AssertEq(FishingTask(t.cfg, st, FsDeps(io))._WaitFishButton(ctx), 1, "idle status: ready")
        AssertTrue(io.clock < 1000, "no long wait (clock " io.clock ")")
        io2 := RlCoveredIO("Is something tugging... or just the wind?")
        AssertEq(FishingTask(t.cfg, st, FsDeps(io2))._WaitFishButton(ctx), 0, "line out: not ready")
    } finally {
        FsScreen.Restore()
        FsClean(t.dir)
    }
}

class RlPanelIO extends FsIO {
    __New(button, title) {
        super.__New()
        this.button := button
        this.title := title
    }
    Ocr(x, y, w, h, scale := 1) => (x = 1050) ? this.button : (x = 1130) ? this.title : ""
}

Test_Reel_NoPanelMeansNotAtTheSpot() {
    t := FsMakeCfg()
    t.cfg.Set("General.legacyReel", 0)
    FsScreen.Install()
    try {
        st := SchedState()
        io := RlPanelIO("", "")                  ; no Fish button, no Fishing panel
        logs := []
        FsScreen.fn := (x, y) => 0xFFFFFF       ; snowy world
        r := FishingTask(t.cfg, st, FsDeps(io, "", true, logs)).CatchOnce(SchedCtx())
        AssertEq(r, "repath", "re-path")
        AssertTrue(FsHasLog(logs, "fishing: no fishing panel (not at the fishing spot) - re-pathing"), "logged")
        AssertTrue(io.clock <= 7000, "within seconds, not the 61 s failsafe (clock " io.clock ")")
        AssertEq(io.Count("click@1161,1124"), 0, "no cast click")
        AssertEq(st.needRepath, true, "Sell due")
    } finally {
        FsScreen.Restore()
        FsClean(t.dir)
    }
}

Test_Reel_ExitButtonMeansLineIsOut() {
    t := FsMakeCfg()
    t.cfg.Set("General.legacyReel", 0)
    FsScreen.Install()
    try {
        st := SchedState()
        io := RlPanelIO("Exit", "Fishing")       ; the line is already out
        logs := []
        FsScreen.fn := (x, y) => 0x101010       ; no reel ever
        r := FishingTask(t.cfg, st, FsDeps(io, "", true, logs)).CatchOnce(SchedCtx())
        AssertEq(io.Count("click@1161,1124"), 0, "Exit is never clicked")
        AssertEq(FsHasLog(logs, "no fishing panel"), false, "panel is there")
        AssertEq(r, "repath", "no bite in the end -> pathing failsafe")
    } finally {
        FsScreen.Restore()
        FsClean(t.dir)
    }
}

Test_Reel_PanelWithoutButtonTextStillCasts() {
    t := FsMakeCfg()
    t.cfg.Set("General.legacyReel", 0)
    FsScreen.Install()
    try {
        st := SchedState()
        io := RlPanelIO("", "Fishing")           ; button unreadable, title there
        FsScreen.fn := (x, y) => 0x101010
        FishingTask(t.cfg, st, FsDeps(io)).CatchOnce(SchedCtx())
        AssertEq(io.Count("click@1161,1124"), 1, "casts")
    } finally {
        FsScreen.Restore()
        FsClean(t.dir)
    }
}

Test_Reel_DefaultIsArrowController() {
    d := A_Temp "\vesper_rltest_" A_TickCount
    DirCreate(d)
    try {
        cfg := Config.Load(d)
        AssertEq(cfg.Get("General.legacyReel", ""), "0", "arrow reel by default")
    } finally {
        try DirDelete(d, true)
    }
}

; FsIO + a scripted result card read through Ocr(): up after the cast, a
; click on its X closes it.
class RlResultIO extends FsIO {
    __New(card) {
        super.__New()
        this.card := card
        this.cast := false
    }
    Ocr(x, y, w, h, scale := 1) => (x = 1000 && y = 440 && this.cast) ? this.card : (x = 1050) ? "Fish" : ""
    ClickHere() {
        super.ClickHere()
        if (this.x = 1161 && this.y = 1124)
            this.cast := true
        if (this.x = 1457 && this.y = 491)
            this.card := ""
    }
}

Test_Reel_CardReadInTheGameFont() {
    t := FsMakeCfg()
    try {
        task := FishingTask(t.cfg, SchedState(), FsDeps(FsIO()))
        ; what Windows OCR reads off the real card (screenshot 2026-10-26)
        AssertEq(task._CardKind("Fish Cought!`nYou've qöt Stonefish!"), "caught", "scale-1 read")
        AssertEq(task._CardKind("Fi?h Cought!"), "caught", "title only")
        AssertEq(task._CardKind("Fish Caught!`nYou've got Stonefish!"), "caught", "scale-2 read")
        AssertEq(task._CardKind("Fishing Failed`nThe fish is gone..."), "failed", "a miss")
        AssertEq(task._CardKind("Fishing`nFish"), "", "the fishing panel is not a card")
        AssertEq(task._CardKind(""), "", "nothing")
        AssertEq(FishingTask.CardScale, 2, "read at scale 2")
    } finally {
        FsClean(t.dir)
    }
}

; FsIO + a catch card that shows `showMs` after its rect is first read after
; the cast (or from the start: showMs -1) and needs `clicksToClose` clicks on its X. While
; it is up it covers the fishing panel (no Fish button, no title).
class RlCardIO extends FsIO {
    __New(showMs, clicksToClose) {
        super.__New()
        this.showMs := showMs
        this.need := clicksToClose
        this.closeClicks := 0
        this.firstRead := -1
        this.shownAt := -1
        this.cast := false
    }
    Up() {
        if (this.closeClicks >= this.need)
            return false
        if (this.showMs < 0)
            return true
        return this.firstRead >= 0 && this.clock >= this.firstRead + this.showMs
    }
    Ocr(x, y, w, h, scale := 1) {
        if (x = 1000 && y = 440) {
            if (this.firstRead < 0 && this.cast)
                this.firstRead := this.clock
            if (this.Up() && this.shownAt < 0)
                this.shownAt := this.clock
            return this.Up() ? "Fish Caught! You've got Stonefish!" : ""
        }
        if (x = 1050)
            return this.Up() ? "" : "Fish"
        if (x = 1130)
            return this.Up() ? "" : "Fishing"
        return ""
    }
    ClickHere() {
        if (this.x = 1457 && this.y = 491 && this.Up())
            this.closeClicks += 1
        if (this.x = 1161 && this.y = 1124)
            this.cast := true
        super.ClickHere()
    }
}

RlRunIO(io, &logs) {
    t := FsMakeCfg()
    t.cfg.Set("General.legacyReel", 0)
    FsScreen.Install()
    try {
        st := SchedState()
        logs := []
        sim := RlSim(io)
        FsScreen.fn := (x, y) => sim.Pixel(x, y)
        r := FishingTask(t.cfg, st, FsDeps(io, "", true, logs)).CatchOnce(SchedCtx())
        return {r: r, st: st}
    } finally {
        FsScreen.Restore()
        FsClean(t.dir)
    }
}

Test_Reel_ClicksTheCardAgainUntilItCloses() {
    logs := ""
    io := RlCardIO(0, 2)                        ; the first click does not take
    o := RlRunIO(io, &logs)
    AssertEq(o.r, "ok", "catch done")
    AssertEq(io.Count("click@1457,491"), 2, "clicked the X again")
    AssertEq(io.Up(), false, "card closed")
    AssertEq(o.st.fishLoops, 1, "counted once")
    AssertEq(FsHasLog(logs, "still open"), false, "no warning")
    io2 := RlCardIO(0, 99)                      ; never closes
    o2 := RlRunIO(io2, &logs)
    AssertEq(io2.Count("click@1457,491"), FishingTask.CloseTries, "bounded clicks")
    AssertTrue(FsHasLog(logs, "fishing: the catch card is still open"), "logged")
    AssertEq(o2.r, "ok", "goes on")
}

Test_Reel_WaitsForALateCardBeforeClosing() {
    logs := ""
    io := RlCardIO(2000, 1)                     ; card pops in 2 s after the reel
    o := RlRunIO(io, &logs)
    AssertTrue(io.shownAt >= 0, "card seen")
    AssertTrue(io.firstClick.Has("click@1457,491") && io.firstClick["click@1457,491"] >= io.shownAt, "the X is clicked after the card shows")
    AssertEq(io.Count("click@1457,491"), 1, "one click was enough")
    AssertEq(io.Up(), false, "card closed")
}

Test_Reel_LeftoverCardIsClosedNotRepathed() {
    t := FsMakeCfg()
    t.cfg.Set("General.legacyReel", 0)
    FsScreen.Install()
    try {
        st := SchedState()
        io := RlCardIO(-1, 1)                   ; card already up before the cast
        logs := []
        FsScreen.fn := (x, y) => 0x101010
        r := FishingTask(t.cfg, st, FsDeps(io, "", true, logs)).CatchOnce(SchedCtx())
        AssertTrue(FsHasLog(logs, "fishing: a catch card was still open - closing it"), "logged")
        AssertEq(FsHasLog(logs, "no fishing panel"), false, "not taken for 'not at the spot'")
        AssertTrue(io.firstClick["click@1457,491"] < 1500, "closed right away, before waiting for the Fish button")
        AssertTrue(io.firstClick.Has("click@1457,491") && io.firstClick.Has("click@1161,1124"), "closed, then cast")
        AssertTrue(io.firstClick["click@1457,491"] < io.firstClick["click@1161,1124"], "close before the cast")
    } finally {
        FsScreen.Restore()
        FsClean(t.dir)
    }
}

RlRunCard(card, &logs) {
    t := FsMakeCfg()
    t.cfg.Set("General.legacyReel", 0)
    FsScreen.Install()
    try {
        st := SchedState()
        io := RlResultIO(card)
        logs := []
        sim := RlSim(io)
        FsScreen.fn := (x, y) => sim.Pixel(x, y)
        r := FishingTask(t.cfg, st, FsDeps(io, "", true, logs)).CatchOnce(SchedCtx())
        return {r: r, st: st}
    } finally {
        FsScreen.Restore()
        FsClean(t.dir)
    }
}

Test_Reel_CountsCaughtAndGotAway() {
    logs := ""
    o := RlRunCard("Fishing Failed / The fish is gone...", &logs)
    AssertEq(o.r, "ok", "reel finished")
    AssertEq(o.st.stats.Has("fishFailed") ? o.st.stats["fishFailed"] : 0, 1, "got away counted")
    AssertEq(o.st.fishLoops, 0, "a lost fish is not a loop")
    AssertTrue(FsHasLog(logs, "fishing: the fish got away"), "logged")
    o := RlRunCard("Fishing Success / Emberfin", &logs)
    AssertEq(o.st.stats.Has("fishCaught") ? o.st.stats["fishCaught"] : 0, 1, "caught counted")
    AssertEq(o.st.fishLoops, 1, "a caught fish is a loop")
}

Test_Reel_EndsWhenTheReelCloses() {
    ; reel visible for ~3 s then gone: the catch ends shortly after, not at the 9 s cap
    t := FsMakeCfg()
    t.cfg.Set("General.legacyReel", 0)
    FsScreen.Install()
    try {
        io := FsIO()
        sim := RlSim(io)
        FsScreen.fn := (x, y) => (sim.firstGrab >= 0 && io.clock > sim.firstGrab + 3000 && (y = 1025 || y = 1030 || y = 1044)) ? 0x101010 : sim.Pixel(x, y)
        FishingTask(t.cfg, SchedState(), FsDeps(io)).CatchOnce(SchedCtx())
        AssertTrue(io.firstClick.Has("click@1457,491"), "closed the card")
        AssertTrue(io.firstClick["click@1457,491"] - sim.firstGrab < 6000, "ended early (" io.firstClick["click@1457,491"] - sim.firstGrab " ms)")
    } finally {
        FsScreen.Restore()
        FsClean(t.dir)
    }
}

; live 1080p SNOWY 2026-11-10 (frame f0870, mapped to design px): bar
; 0x42DAFF to 1429, fish 0x01FFFF under it 1171..1250, and the bar's empty
; see-through part a dim grey 0x3E4750 over the bright scene. That grey
; (brightest channel 80) counted as fish: the arrow chased it to the end.
Test_Reel_ScanDimGreyEmptyPartIsNotTheFish() {
    bar := RlRow(1042, 1517, 2, (x) => (x >= 1171 && x <= 1250) ? 0x01FFFF
        : (x <= 1429) ? (Mod(x, 10) < 5 ? 0x42DAFF : 0x3DD4FF) : (Mod(x, 6) < 3 ? 0x3E4750 : 0x3C464F))
    s := FishLogic.ReelScan(RlArrowRow(1429), bar, 1042, 2)
    AssertTrue(Abs(s.p1 - 1171) <= 2 && Abs(s.p2 - 1250) <= 2, "fish under the bar, not the grey " s.p1 ".." s.p2)
    AssertTrue(FishLogic.ReelDark(0x3E4750) && FishLogic.ReelDark(0x221919), "dim grey / black are empty")
    AssertTrue(!FishLogic.ReelDark(0x8489FF) && !FishLogic.ReelDark(0x4B9CFF) && !FishLogic.ReelDark(0x01FFFF), "fish colours are not")
}
