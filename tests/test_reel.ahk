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
        this.white := 0xFFFFFF       ; the arrow and the bar's borders (dimmer on some PCs)
        this.dy := 0                 ; the reel drawn this many px lower (another top bar)
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
        y -= this.dy
        if (y = 1025) {
            if (x = 1042)
                this.Step()
            return (this.firstGrab >= 0 && Abs(x - this.m) <= 13) ? this.white : 0x00000B
        }
        if (y = 1030 || y = 1055)
            return (this.firstGrab >= 0) ? this.white : 0x101010      ; bar top / bottom border
        if (y = 1044) {
            fish := x >= this.f1 && x <= this.f1 + 76 && io.clock >= this.firstGrab + this.readyMs
            if (x <= this.m)
                return fish ? 0x8489FF : 0x3DA8FF
            return fish ? 0x8C46E6 : 0x00000B
        }
        return 0x101010
    }
}

RlRun(swing, readyMs, &sim, &logs, momentum := false, biteAfter := 2000, ioIn := "") {
    t := FsMakeCfg()
    t.cfg.Set("General.legacyReel", 0)
    FsScreen.Install()
    try {
        st := SchedState()
        io := IsObject(ioIn) ? ioIn : FsIO()
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

; A friend's PC (1920x1080, 2026-11-11): the minigame ran and nothing was
; clicked. A dimmer white (0xC8C8C8 here) never counted as the bar's border.
; The button reading the reel prompt with no bar seen: the border measured,
; logged, white lowered for the session, and the fish reeled.
class RlDimIO extends FsIO {
    __New(biteAfter) {
        super.__New()
        this.biteAfter := biteAfter
    }
    Ocr(x, y, w, h, scale := 1) {
        if (x = 1130)
            return "Fishing"
        if (x != 1050)
            return ""
        if !this.lastClick.Has("click@1161,1124")
            return "Fish"
        return (this.clock >= this.lastClick["click@1161,1124"] + this.biteAfter) ? "Click / Touch Screen to Reel" : "Exit"
    }
}

Test_Reel_DimWhiteIsLearnt() {
    t := FsMakeCfg()
    t.cfg.Set("General.legacyReel", 0)
    FsScreen.Install()
    try {
        io := RlDimIO(2000)
        logs := []
        sim := RlSim(io, 0, 0, false, 2000)
        sim.white := 0xC8C8C8
        sim.firstGrab := 0                          ; the reel drawn from the bite on
        s := sim
        FsScreen.fn := (x, y) => (io.lastClick.Has("click@1161,1124") && io.clock >= io.lastClick["click@1161,1124"] + 2000) ? s.Pixel(x, y) : 0x101010
        r := FishingTask(t.cfg, SchedState(), FsDeps(io, "", true, logs)).CatchOnce(SchedCtx())
        AssertTrue(FsHasLog(logs, "200 bright here"), "the border measured and logged")
        AssertTrue(FsHasLog(logs, "borders found in place"), "found where it should be")
        AssertEq(FishingTask.ReelDy, 0, "rows not moved")
        AssertEq(FishLogic.WhiteMin, 185, "white lowered under the border")
        AssertTrue(sim.clicks > 10, "it reels after (clicks=" sim.clicks ")")
    } finally {
        FishLogic.WhiteMin := 220
        FishingTask.ReelDy := 0
        FsScreen.Restore()
        FsClean(t.dir)
    }
}

; The friend's numbers: white 133 at the expected rows. Here the bar is also
; drawn 14 px lower (a Roblox top bar of another height): both are learnt
; from the bar's two borders and the fish reeled.
Test_Reel_ShiftedDimBarIsFound() {
    t := FsMakeCfg()
    t.cfg.Set("General.legacyReel", 0)
    FsScreen.Install()
    try {
        io := RlDimIO(2000)
        logs := []
        sim := RlSim(io, 0, 0, false, 2000)
        sim.white := 0x858585
        sim.dy := 14
        sim.firstGrab := 0
        s := sim
        FsScreen.fn := (x, y) => (io.lastClick.Has("click@1161,1124") && io.clock >= io.lastClick["click@1161,1124"] + 2000) ? s.Pixel(x, y) : 0x101010
        r := FishingTask(t.cfg, SchedState(), FsDeps(io, "", true, logs)).CatchOnce(SchedCtx())
        AssertTrue(FsHasLog(logs, "14 px lower, 133 bright"), "found lower and dimmer")
        AssertEq(FishingTask.ReelDy, 14, "rows moved")
        AssertEq(FishLogic.WhiteMin, 118, "white lowered")
        AssertTrue(sim.clicks > 10, "it reels after (clicks=" sim.clicks ")")
        AssertEq(r, "ok", "catch finished")
    } finally {
        FishLogic.WhiteMin := 220
        FishingTask.ReelDy := 0
        FsScreen.Restore()
        FsClean(t.dir)
    }
}

; Nothing like a bar near it (the game world behind): nothing changed.
Test_Reel_NoBarFoundChangesNothing() {
    t := FsMakeCfg()
    t.cfg.Set("General.legacyReel", 0)
    FsScreen.Install()
    try {
        io := RlDimIO(2000)
        logs := []
        FsScreen.fn := (x, y) => (y = 1030) ? 0x909090 : 0x202020
        r := FishingTask(t.cfg, SchedState(), FsDeps(io, "", true, logs)).CatchOnce(SchedCtx())
        AssertTrue(FsHasLog(logs, "no bar border found"), "said so")
        AssertEq(FishLogic.WhiteMin, 220, "white unchanged")
        AssertEq(FishingTask.ReelDy, 0, "rows unchanged")
    } finally {
        FishLogic.WhiteMin := 220
        FishingTask.ReelDy := 0
        FsScreen.Restore()
        FsClean(t.dir)
    }
}

; pure white: nothing measured, nothing lowered
Test_Reel_WhiteStaysWhenTheBarIsSeen() {
    sim := "", logs := ""
    o := RlRun(0, 0, &sim, &logs)
    AssertEq(FishLogic.WhiteMin, 220, "white unchanged")
    AssertTrue(!FsHasLog(logs, "bright here"), "nothing to say")
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

; live 2026-11-22: the catch card froze over the panel, raised ~346 px; its
; Fish button reads only in RaisedRect until the frozen card's X is clicked
class RlRaisedIO extends FsIO {
    raised := true
    Ocr(x, y, w, h, scale := 1) {
        if (this.raised && this.Count("click@1523,645") >= 1)
            this.raised := false
        if (x = FishingTask.RaisedRect[1] && y = FishingTask.RaisedRect[2])
            return this.raised ? "Fis" : ""
        if (x = 1050)
            return this.raised ? "" : "Fish"
        return ""
    }
}

Test_Reel_FrozenRaisedCardIsClosedNotRepathed() {
    t := FsMakeCfg()
    t.cfg.Set("General.legacyReel", 0)
    FsScreen.Install()
    try {
        st := SchedState()
        io := RlRaisedIO()
        logs := []
        FsScreen.fn := (x, y) => 0x101010
        FishingTask(t.cfg, st, FsDeps(io, "", true, logs)).CatchOnce(SchedCtx())
        AssertTrue(FsHasLog(logs, "fishing: the catch card froze over a raised fishing panel - closing it by its X"), "logged")
        AssertEq(io.Count("click@1523,645"), 1, "its X once")
        AssertEq(FsHasLog(logs, "no fishing panel"), false, "not taken for 'not at the spot'")
        AssertTrue(io.Count("click@1161,1124") >= 1, "then casts")
        AssertTrue(io.firstClick["click@1523,645"] < io.firstClick["click@1161,1124"], "close before the cast")
        ; between tasks too (the tidy): seen and closed
        io2 := RlRaisedIO()
        lo := FishingTask(t.cfg, SchedState(), FsDeps(io2, "", true, [])).Leftovers()
        AssertEq(lo[2].up.Call(), "frozen Fish Caught card", "tidy sees it")
        AssertEq(lo[2].close.Call("", SchedCtx()), 1, "tidy closes it")
        ; no panel anywhere: never clicks the frozen card's X blind
        io3 := RlPanelIO("", "")
        FishingTask(t.cfg, SchedState(), FsDeps(io3, "", true, [])).CatchOnce(SchedCtx())
        AssertEq(io3.Count("click@1523,645"), 0, "no blind click")
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

; ---- real reel frames at 2560x1440 (night recordings, 2026-11-15) ----------
; tests\screens\reel1440_<biome>_<clip>_t<sec>_x1000_y1000.png: 560x100 crops
; whose top left is screen (1000,1000), from video\raw\night\<clip>.ts at
; <sec> s (the recording is lossy, so colours are a little off a live
; BitBlt; the ones that matter are far from the thresholds). The true fish
; box (p1..p2) of each frame was read off its bar row (y 1044), where the
; box's tint starts and ends; it is noted at each check (+-12 px allowed).
RlShot(name) => MatchFileGrab(A_ScriptDir "\screens\reel1440_" name "_x1000_y1000.png")

; a grab(x1, x2, ys, stride) in screen px over a crop at (1000,1000)
RlShotGrab(g) => (x1, x2, ys, stride) => RlShotRows(g, x1, x2, ys, stride)
RlShotRows(g, x1, x2, ys, stride) {
    sy := []
    for y in ys
        sy.Push(y - 1000)
    return g.Call(x1 - 1000, x2 - 1000, sy, stride)
}

RlShotScan(name, emptyMax := 0) {
    rows := RlShotRows(RlShot(name), 1042, 1517, [1025, 1044], 2)
    return emptyMax ? FishLogic.ReelScan(rows[1], rows[2], 1042, 2, emptyMax) : FishLogic.ReelScan(rows[1], rows[2], 1042, 2)
}

RlFishAt(s, p1, p2, what) {
    AssertTrue(s.m > 0, what ": arrow found")
    AssertTrue(Abs(s.p1 - p1) <= 12 && Abs(s.p2 - p2) <= 12, what ": fish " s.p1 ".." s.p2 " (true box " p1 ".." p2 ")")
    AssertTrue(s.p2 - s.p1 <= 110, what ": fish width " (s.p2 - s.p1) " (a fish is ~76)")
}

; STARFALL, 062120.ts t427-431 (lost, progress drained to 0): the bar's empty
; part over the cyan sky reads navy (26,51,75), not "dark", so the main code
; took the empty right end (1432..1516) for the fish and chased it.
Test_Reel_FrameStarfallEmptyBarIsNotTheFish() {
    ; "Ready!": the arrow at 1279, the fish under the bar's end (its right
    ; edge 1318, empty from 1320; the text hides where it starts). The bar
    ; right of the arrow is long enough to read the empty level from.
    s := RlShotScan("starfall_ready_062120_t4273")
    AssertTrue(Abs(s.p2 - 1318) <= 12 && s.p1 >= 1230 && s.p2 - s.p1 <= 110, "Ready: fish at the bar's end " s.p1 ".." s.p2 ", not the empty end")
    AssertTrue(s.own && s.empty >= 76 && s.empty <= 120, "Ready: empty level read from the bar (" s.empty ")")
    em := s.empty
    ; the arrow at 1373 / 1443: too little bar right of it, the level from
    ; "Ready!" is used. True boxes: tint 1248..1322, 1236..1312.
    RlFishAt(RlShotScan("starfall_062120_t4293", em), 1248, 1322, "t429.3")
    RlFishAt(RlShotScan("starfall_062120_t4305", em), 1236, 1312, "t430.5")
}

; HEAVEN, 031120.ts t340 / 022120.ts t125-128 (both lost): over the bright
; warm scene the empty part reads tan (73,62,43): the fish ran on into it
; (1200..1424) or the empty end won (1434..1516).
Test_Reel_FrameHeavenEmptyBarIsNotTheFish() {
    ; pale yellow fish under the blue bar from 1200, its part past the
    ; arrow and the timer digits to 1278, empty from 1280
    RlFishAt(RlShotScan("heaven_031120_t3403"), 1200, 1278, "031120 t340.3")
    ; mint tint from 1224, green past the arrow to 1300, empty from 1302
    s := RlShotScan("heaven_022120_t1253")
    RlFishAt(s, 1224, 1300, "022120 t125.3")
    AssertTrue(s.own, "t125.3: level read from the bar")
    ; arrow at 1417: mint box 1150..1230 under the bar
    RlFishAt(RlShotScan("heaven_022120_t1278", s.empty), 1150, 1230, "022120 t127.8")
}

; SNOWY, 095120.ts t295-297 (lost, progress 0): the arrow never left the
; right part of the bar, so only a short stretch of empty bar is there to
; read; that is enough while the reel has no better level.
Test_Reel_FrameSnowyEmptyBarIsNotTheFish() {
    ; pink tint from 1316, red past the arrow to 1390, empty from 1392
    s := RlShotScan("snowy_095120_t2953")
    RlFishAt(s, 1316, 1390, "t295.3")
    AssertTrue(!s.own && s.empty > 0, "t295.3: a short read only (" s.empty ")")
    ; arrow at 1451: pink box 1222..1296 under the bar
    RlFishAt(RlShotScan("snowy_095120_t2973", s.empty), 1222, 1296, "t297.3")
}

; NORMAL, 003755.ts t274 / t276 (caught): a dark empty part, nothing changes.
Test_Reel_FrameNormalFishAsBefore() {
    ; light blue tint from 1222, dark blue past the arrow to 1298
    RlFishAt(RlShotScan("normal_003755_t2743"), 1222, 1298, "t274.3")
    ; tint from 1376, dark blue to 1450, empty from 1452
    RlFishAt(RlShotScan("normal_003755_t2763"), 1376, 1450, "t276.3")
}

; One wide reading (fish run together with the empty part) must not spoil
; the aim for the rest of the reel: the remembered width is capped.
Test_Reel_DecideWidthIsCappedToAFish() {
    st := {}
    FishLogic.ReelDecide({m: 1100, p1: 1200, p2: 1424}, st, 0, 100, 0.15)
    AssertEq(st.w, 110, "a 224 px box is remembered as a fish's width")
    st := {}
    FishLogic.ReelDecide({m: 1100, p1: 1200, p2: 1276}, st, 0, 100, 0.15)
    AssertEq(st.w, 76, "a fish-sized box as it is")
}

; The bar's frame: a bright top border, a bar row that is not white. In
; SNOWY after the reel (041120.ts t109.3, the card is up) the snow gives an
; arrow-sized white run (m 1377) and a "bar colour", so the old check kept
; the reel up to the 9 s cap; the frame is not there on any border row.
Test_Reel_FrameSnowAfterTheReelIsNotTheBar() {
    rc := FsRead("coords")["fishing"]["reel"]
    ys := [1025, 1044]
    for y in rc["borderYs"]
        ys.Push(y)
    on := RlShotRows(RlShot("snowy_092120_t3473"), 1042, 1517, ys, 2)
    s := FishLogic.ReelScan(on[1], on[2], 1042, 2)
    AssertTrue(s.m && (s.p2 || s.fill != ""), "SNOWY mid reel: arrow + bar")
    seen := false
    Loop on.Length - 2
        seen := seen || FishLogic.ReelFrame(on[A_Index + 2], on[2])
    AssertTrue(seen, "SNOWY mid reel (092120 t347.3): the bar's frame is seen")
    off := RlShotRows(RlShot("snowy_after_041120_t1093"), 1042, 1517, ys, 2)
    s := FishLogic.ReelScan(off[1], off[2], 1042, 2)
    AssertTrue(s.m && (s.p2 || s.fill != ""), "after the reel: snow still passes arrow + bar (the old check)")
    Loop off.Length - 2
        AssertTrue(!FishLogic.ReelFrame(off[A_Index + 2], off[2]), "after the reel: no frame on border row " ys[A_Index + 2])
}

; The whole reel loop on those frames: the SNOWY reel for 3 s, then the snow
; after it. It ends ~FrameGoneMs after the reel, not at the 9 s cap, and
; logs one line about the reel.
Test_Reel_SnowAfterTheReelEndsTheLoop() {
    t := FsMakeCfg()
    t.cfg.Set("General.legacyReel", 0)
    try {
        io := FsIO()
        logs := []
        d := FsDeps(io, "", true, logs)
        on := RlShotGrab(RlShot("snowy_092120_t3473"))
        off := RlShotGrab(RlShot("snowy_after_041120_t1093"))
        d.grab := (x1, x2, ys, stride) => (io.clock < 3000 ? on : off).Call(x1, x2, ys, stride)
        task := FishingTask(t.cfg, SchedState(), d)
        r := task._Reel(SchedCtx(), FishLogic.Settings(t.cfg, task._CoordsNow()))
        AssertEq(r, "ok", "reel done")
        AssertTrue(io.clock < 4600, "ended " io.clock " ms in (snow from 3000), not at the 9 s cap")
        line := ""
        for l in logs
            if InStr(l, "fishing: reel ")
                line := l
        AssertTrue(RegExMatch(line, "^fishing: reel \d+ ms \(ended\), polls \d+, avg gap \d+ ms, max gap \d+ ms, clicks \d+, empty up to \d+.*, frame seen, slowest grab \d+ / work \d+ / wait \d+ ms$"), "one reel line: " line)
    } finally
        FsClean(t.dir)
}

; Something drawn over the bar's border for a moment mid-reel does not end
; the reel; the border gone for longer than FrameGoneMs (with the arrow and
; bar still read, as snow does) does.
Test_Reel_BorderGoneEndsTheReelOnlyAfterFrameGoneMs() {
    o := RlBorderGone(500)
    AssertTrue(o.last > 8000, "border gone 500 ms: the reel went on (last click at " o.last " ms; " FsJoin(o.logs) ")")
    o := RlBorderGone(3000)
    AssertTrue(o.last < 3000 + FishingTask.FrameGoneMs + 100 && o.card < 6500,"border gone 3000 ms: the reel ended (last click at " o.last " ms, card closed at " o.card " ms)")
}

; RlSim with the bar's top border (y 1030) scenery-coloured from 3 s for
; goneMs. -> {last: last reel click, card: card close click (ms after the
; first grab), logs}
RlBorderGone(goneMs) {
    t := FsMakeCfg()
    t.cfg.Set("General.legacyReel", 0)
    FsScreen.Install()
    try {
        io := FsIO()
        sim := RlSim(io)
        FsScreen.fn := (x, y) => (y = 1030 && sim.firstGrab >= 0 && io.clock >= sim.firstGrab + 3000 && io.clock < sim.firstGrab + 3000 + goneMs) ? 0x6A7C90 : sim.Pixel(x, y)
        logs := []
        FishingTask(t.cfg, SchedState(), FsDeps(io, "", true, logs)).CatchOnce(SchedCtx())
        return {last: io.lastClick["click@1263,1177"] - sim.firstGrab, card: io.firstClick["click@1457,491"] - sim.firstGrab, logs: logs}
    } finally {
        FsScreen.Restore()
        FsClean(t.dir)
    }
}

; Every reel logs one line (polls, gaps, clicks, empty level): to measure
; slow-PC losses and controller losses from the log later.
Test_Reel_LogsOneLinePerReel() {
    RlRun(0, 0, &sim, &logs)
    n := 0, line := ""
    for l in logs
        if InStr(l, "fishing: reel ")
            n++, line := l
    AssertEq(n, 1, "one reel line")
    AssertTrue(RegExMatch(line, "polls (\d+), avg gap (\d+) ms, max gap (\d+) ms, clicks (\d+)", &m) && m[1] > 50 && m[4] > 5, "polls and clicks counted: " line)
    AssertTrue(RegExMatch(line, ", slowest grab \d+ / work \d+ / wait \d+ ms$"), "slowest pass parts logged: " line)
}

; FsIO whose Wait notes Input.InReel, and once (from stallAt) takes stallMs
; longer: the App's tick running inside the reel's sleep on a slow PC.
class RlStallIO extends FsIO {
    __New(stallAt := 0, stallMs := 0) {
        super.__New()
        this.stallAt := stallAt, this.stallMs := stallMs, this.stalled := false
        this.inReel := 0, this.outside := 0
    }
    Wait(ms, ctx := "") {
        if Input.InReel
            this.inReel++
        else
            this.outside++
        if (this.stallMs && !this.stalled && this.stallAt && this.clock >= this.stallAt) {
            this.stalled := true
            this.clock += this.stallMs
        }
        return super.Wait(ms, ctx)
    }
}

; Tester log 2026-11-23 (60 % caught): every reel paused 0.6..1.6 s; the App's
; tick did its slow work in the reel's sleeps. Input.InReel tells it a reel
; runs (set for the whole reel, clear before and after).
Test_Reel_InReelWhileTheReelRuns() {
    io := RlStallIO(), sim := "", logs := ""
    o := RlRun(0, 0, &sim, &logs, false, 2000, io)
    AssertEq(o.r, "ok", "caught")
    AssertTrue(io.inReel > 50, "Input.InReel in the reel's waits (" io.inReel ")")
    AssertTrue(io.outside > 0, "not before / after the reel (" io.outside " waits)")
    AssertEq(Input.InReel, false, "cleared after the reel")
}

; A stall still shows in the reel line, now with where it was: a long wait
; = something else ran meanwhile (the 2026-11-23 cause), not the capture.
Test_Reel_StallIsLoggedAsAWait() {
    io := RlStallIO(3000, 1000), sim := "", logs := ""
    RlRun(0, 0, &sim, &logs, false, 2000, io)
    line := ""
    for l in logs
        if InStr(l, "fishing: reel ")
            line := l
    AssertTrue(RegExMatch(line, "max gap (\d+) ms.*slowest grab (\d+) / work (\d+) / wait (\d+) ms$", &m), "reel line: " line)
    AssertTrue(m[1] >= 1000, "the 1 s stall is the max gap: " line)
    AssertTrue(m[4] >= 1000 && m[2] < 1000 && m[3] < 1000, "and it was a wait, not the capture or the scan: " line)
}

; After a pause in the polls the speed is not taken over the pause: the
; arrow 1 s ago at 1043, now at 1243, left of the fish (target 1261): it
; clicks. The stale speed (+0.2 px/ms, 100 ms lead -> 1263) said no.
Test_Reel_DecideIgnoresSpeedOverAStall() {
    st := {}
    FishLogic.ReelDecide({m: 1043, p1: 1250, p2: 1326}, st, 0, 100, 0.15)
    AssertEq(FishLogic.ReelDecide({m: 1243, p1: 1250, p2: 1326}, st, 1000, 100, 0.15), true, "left of the fish after a 1 s pause -> click")
    AssertEq(st.hist.Length, 1, "history started again from this sample")
    ; normal polls still lead with the speed
    st := {}
    FishLogic.ReelDecide({m: 1203, p1: 1250, p2: 1326}, st, 0, 100, 0.15)
    AssertEq(FishLogic.ReelDecide({m: 1243, p1: 1250, p2: 1326}, st, 40, 100, 0.15), false, "fast approach 40 ms apart -> stop early")
}

; ---- slow-PC warning (lib\tasks\ReelPause.ahk) -----------------------------

; n reels with the given max gaps (an Array, or one number for all), the
; rest of each reel healthy; -> the last Add's result. Clock 20 s per reel.
RlPauseFeed(rp, gaps, &t, parts := "", lost := false) {
    w := ""
    for g in gaps {
        p := IsObject(parts) ? parts : {grab: 20, work: 10, wait: g}
        w := rp.Add({gap: g, grab: p.grab, work: p.work, wait: p.wait, lost: lost}, t)
        t += 20000
    }
    return w
}

; Healthy PCs measure 47-94 ms max gaps: never a warning, however long it runs.
Test_ReelPause_HealthyGapsNeverWarn() {
    rp := ReelPause(), t := 0
    try {
        gaps := []
        Loop 300
            gaps.Push([47, 63, 71, 80, 94][Mod(A_Index, 5) + 1])
        for g in gaps
            AssertEq(rp.Add({gap: g, grab: 31, work: 32, wait: 16, lost: Mod(A_Index, 3) = 0}, t += 20000), "", "healthy reel " A_Index " (" g " ms)")
        ; 2 slow reels in 10 (each under 800 ms): still not enough
        AssertEq(RlPauseFeed(rp, [400, 80, 80, 450, 80, 80, 80, 80, 80, 80], &t), "", "2 slow reels in 10: no warning")
        AssertEq(ReelPause.Last, "", "nothing for Check my setup")
    } finally {
        rp.Reset()
    }
}

; 3 reels of the last 10 paused >= 300 ms: the warning, with the count, the
; longest pause and how many of those fish got away.
Test_ReelPause_ThreeSlowInTenWarns() {
    rp := ReelPause(), t := 0
    try {
        AssertEq(RlPauseFeed(rp, [80, 80, 80, 80, 80, 80, 80], &t), "", "7 healthy reels")
        AssertEq(RlPauseFeed(rp, [350], &t, "", true), "", "1 slow")
        AssertEq(RlPauseFeed(rp, [650], &t, "", true), "", "2 slow")
        w := RlPauseFeed(rp, [420], &t)
        AssertTrue(IsObject(w), "3 slow in the last 10: a warning")
        AssertEq(w.n, 3, "3 slow reels")
        AssertEq(w.of, 10, "of the last 10")
        AssertEq(w.longest, 650, "the longest pause")
        AssertEq(w.lost, 2, "2 of them got away")
        AssertTrue(InStr(w.text, "Your PC paused during 3 of the last 10 reels (longest 650 ms), which can lose fish (2 got away).") = 1, w.text)
        AssertTrue(InStr(w.text, "Try: ") && InStr(w.text, "Graphics Quality"), "what to try: " w.text)
        AssertTrue(ReelPause.Last == w, "kept for Check my setup")
        ; 2 reels over 800 ms are enough on their own
        rp2 := ReelPause(), t2 := 0
        AssertEq(RlPauseFeed(rp2, [80, 80, 80, 80, 900], &t2), "", "1 bad")
        AssertTrue(IsObject(RlPauseFeed(rp2, [1600], &t2)), "2 reels >= 800 ms: a warning")
        ; slow reels that fell out of the 10-reel window do not count
        rp3 := ReelPause(), t3 := 0
        AssertEq(RlPauseFeed(rp3, [400, 400, 80, 80, 80, 80, 80, 80, 80, 80, 80, 400], &t3), "", "the first two left the window")
    } finally {
        rp.Reset()
    }
}

; Not before 5 reels this session: 4 terrible reels say nothing, the 5th does.
Test_ReelPause_NotBeforeFiveReels() {
    rp := ReelPause(), t := 0
    try {
        AssertEq(RlPauseFeed(rp, [1500, 1500, 1500, 1500], &t), "", "4 reels: too early")
        AssertTrue(IsObject(RlPauseFeed(rp, [80], &t)), "the 5th reel: a warning")
        rp.Reset()
        AssertEq(ReelPause.Last, "", "Reset clears Check my setup's row")
        AssertEq(RlPauseFeed(rp, [1500, 1500, 1500, 1500], &t), "", "a new session counts again")
    } finally {
        rp.Reset()
    }
}

; At most once per 60 minutes, then again if it is still slow.
Test_ReelPause_OncePerHour() {
    rp := ReelPause(), t := 0
    try {
        AssertTrue(IsObject(RlPauseFeed(rp, [900, 900, 900, 900, 900], &t)), "first warning")
        first := t - 20000
        n := 0
        while (t < first + ReelPause.GapMs) {
            n += IsObject(RlPauseFeed(rp, [900], &t)) ? 1 : 0
        }
        AssertEq(n, 0, "no second warning within the hour")
        AssertTrue(IsObject(RlPauseFeed(rp, [900], &t)), "60 min later and still slow: again")
    } finally {
        rp.Reset()
    }
}

; Which part was slow picks the advice: grab = screen capture (graphics,
; recording apps), work = CPU (close apps), wait = Windows woke the macro
; late (power mode); unclear = the general advice.
Test_ReelPause_HintPicksTheAdvice() {
    AssertEq(ReelPause.Part(900, 20, 16, 950), "grab", "a slow capture")
    AssertEq(ReelPause.Part(30, 700, 16, 760), "work", "a slow scan")
    AssertEq(ReelPause.Part(30, 20, 1000, 1050), "wait", "a late wake")
    AssertEq(ReelPause.Part(200, 180, 190, 600), "", "no part took half the pause: unclear")
    cases := Map("grab", [{grab: 900, work: 20, wait: 16}, "screen capture was slow", "OBS"]
        , "work", [{grab: 30, work: 800, wait: 16}, "processor was busy", "heavy apps"]
        , "wait", [{grab: 30, work: 20, wait: 900}, "woke the macro late", "Best performance"])
    for part, c in cases {
        rp := ReelPause(), t := 0
        try {
            RlPauseFeed(rp, [80, 80, 80], &t)
            w := RlPauseFeed(rp, [950, 950], &t, c[1])
            AssertTrue(IsObject(w), part ": warned")
            AssertEq(w.part, part, part ": the part")
            AssertTrue(InStr(w.text, c[2]) && InStr(w.text, c[3]) && InStr(w.advice, c[3]), part ": " w.text)
        } finally {
            rp.Reset()
        }
    }
    rp := ReelPause(), t := 0
    try {
        w := RlPauseFeed(rp, [950, 950, 950, 950, 950], &t, {grab: 400, work: 300, wait: 350})
        AssertEq(w.part, "", "split pauses: no part named")
        AssertEq(w.advice, ReelPause.Advice(""), "the general advice")
        AssertTrue(InStr(w.advice, "Graphics Quality") && InStr(w.advice, "recording apps") && InStr(w.advice, "laptop"), w.advice)
    } finally {
        rp.Reset()
    }
}

class RlPauseWh {
    __New() => this.sent := []
    Send(event, title, desc, color, opts := "") => this.sent.Push({event: event, title: title, desc: desc})
}

; FsIO whose reel stalls stallMs once per reel (the 40th wait inside it).
class RlSlowIO extends FsIO {
    __New(stallMs) {
        super.__New()
        this.stallMs := stallMs, this.n := 0
    }
    Wait(ms, ctx := "") {
        if Input.InReel {
            if (++this.n = 40)
                this.clock += this.stallMs
        } else {
            this.n := 0
        }
        return super.Wait(ms, ctx)
    }
}

; The reel path feeds the tracker after each reel: a PC that stalls ~1 s in
; every reel gets one log line and one errors webhook on the 5th catch, and
; no second one on the 6th.
Test_Reel_SlowPcWarnsAfterTheReel() {
    t := FsMakeCfg()
    t.cfg.Set("General.legacyReel", 0)
    FsScreen.Install()
    task := ""
    try {
        io := RlSlowIO(1000), logs := [], wh := RlPauseWh()
        d := FsDeps(io, "", true, logs)
        d.webhook := wh
        task := FishingTask(t.cfg, SchedState(), d)
        Loop 6 {
            sim := RlSim(io)
            s := sim
            FsScreen.fn := (x, y) => s.Pixel(x, y)
            AssertEq(task.CatchOnce(SchedCtx()), "ok", "catch " A_Index)
            AssertEq(Input.InReel, false, "fed outside the reel")
            n := 0
            for l in logs
                n += InStr(l, "fishing: slow PC: ") ? 1 : 0
            AssertEq(n, A_Index >= 5 ? 1 : 0, "slow-PC lines after catch " A_Index)
        }
        AssertEq(wh.sent.Length, 1, "one webhook")
        AssertEq(wh.sent[1].event, "errors", "the errors webhook")
        AssertEq(wh.sent[1].title, FishingTask.PauseTitle, "its title")
        AssertTrue(InStr(wh.sent[1].desc, "Your PC paused during 5 of the last 5 reels"), wh.sent[1].desc)
        AssertTrue(InStr(wh.sent[1].desc, "woke the macro late"), "the stall was a wait: " wh.sent[1].desc)
        AssertTrue(IsObject(ReelPause.Last), "Check my setup sees it")
        task.Reset()
        AssertEq(ReelPause.Last, "", "Start: a new session")
    } finally {
        if IsObject(task)
            task.Reset()
        FsScreen.Restore()
        FsClean(t.dir)
    }
}

; Tester 2026-11-24 (1366x768, no VIP gamepass, "VIP gamepass routes" on by
; default): the shipped walk back was recorded with VIP's faster walking, so
; without VIP it stopped ~0.9 s short of the fishing spot. Every cast after
; it saw no panel and re-walked until the stuck pause. After Sell's walk back
; (state.backHops), a missing panel now gets short a+w hops first.
class RlHopIO extends RlPanelIO {
    __New(hopsNeeded) {
        super.__New("", "")
        this.need := hopsNeeded
    }
    Ocr(x, y, w, h, scale := 1) {
        if (this.Count("down a") < this.need)
            return ""
        return (x = 1050) ? "Fish" : (x = 1130) ? "Fishing" : ""
    }
}

Test_Reel_ShortWalkBackHopsForward() {
    t := FsMakeCfg()
    t.cfg.Set("General.legacyReel", 0)
    t.cfg.Set("General.vip", 1)
    FsScreen.Install()
    try {
        st := SchedState()
        st.backHops := SellTask.BackHops
        st.repathStreak := 2
        io := RlHopIO(2)                         ; the panel shows after the 2nd hop
        logs := []
        FsScreen.fn := (x, y) => 0x101010
        r := FishingTask(t.cfg, st, FsDeps(io, "", true, logs)).CatchOnce(SchedCtx())
        AssertEq(r, "hopped", "found the spot by hopping, no re-path (r=" r ")")
        AssertEq(io.Count("down a"), 2, "two hops")
        AssertEq(io.Count("down w"), 2, "a+w (the walk back's last direction)")
        AssertEq(st.needRepath, false, "no Sell made due")
        AssertEq(st.backHops, 0, "hops used up once the spot is found")
        AssertEq(FsHasLog(logs, "no fishing panel (not at the fishing spot) - re-pathing"), false, "no re-path log")
        AssertTrue(FsHasLog(logs, "untick 'VIP gamepass routes'"), "VIP hint logged")
    } finally {
        FsScreen.Restore()
        FsClean(t.dir)
    }
}

Test_Reel_HopsGiveUpThenRepath() {
    t := FsMakeCfg()
    t.cfg.Set("General.legacyReel", 0)
    FsScreen.Install()
    try {
        st := SchedState()
        st.backHops := SellTask.BackHops
        io := RlHopIO(99)                        ; never there
        logs := []
        FsScreen.fn := (x, y) => 0x101010
        r := FishingTask(t.cfg, st, FsDeps(io, "", true, logs)).CatchOnce(SchedCtx())
        AssertEq(r, "repath", "re-path after the hops")
        AssertEq(io.Count("down a"), SellTask.BackHops, "only BackHops hops")
        AssertEq(st.backHops, 0, "hops used up")
        AssertEq(st.needRepath, true, "Sell due")
        ; no hops without a walk back just before (a panel lost mid-session)
        st2 := SchedState()
        io2 := RlHopIO(99)
        r2 := FishingTask(t.cfg, st2, FsDeps(io2)).CatchOnce(SchedCtx())
        AssertEq(r2, "repath", "plain re-path")
        AssertEq(io2.Count("down a"), 0, "no hops")
    } finally {
        FsScreen.Restore()
        FsClean(t.dir)
    }
}
