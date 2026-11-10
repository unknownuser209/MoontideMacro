#Requires AutoHotkey v2.0
; Tests for lib\tasks\FishLogic.ahk, Fishing.ahk, Sell.ahk and the shipped
; data\coords.json / data\routes.json. No game, no real input: a recording io,
; a fake clock (io.Wait advances it) and a fake screen (Pixel._getter).
; Config tests only use temp dirs, never the repo's settings.ini.
#Include ..\lib\Json.ahk
#Include ..\lib\Config.ahk
#Include ..\lib\Scheduler.ahk
#Include ..\lib\Input.ahk
#Include ..\lib\Pixel.ahk
#Include ..\lib\tasks\FishLogic.ahk
#Include ..\lib\tasks\Fishing.ahk
#Include ..\lib\tasks\Sell.ahk

; ---- helpers (names must not start with Test_) -----------------------------

; Recording io + fake clock. Wait advances the clock, never sleeps.
; stopAtWait = n: the n-th Wait() stops ctx (like F3 mid-sleep).
class FsIO {
    __New(stopAtWait := 0) {
        this.log := []
        this.clock := 0
        this._waits := 0
        this._stopAt := stopAtWait
        this.x := 0
        this.y := 0
        this.wheels := []
        this.firstClick := Map()      ; "click@x,y" -> clock at first click
        this.lastClick := Map()       ; "click@x,y" -> clock at latest click
    }
    Down(k) => this.log.Push("down " k)
    Up(k) => this.log.Push("up " k)
    MoveTo(x, y) {
        this.x := x
        this.y := y
        this.log.Push("move " x "," y)
    }
    ClickHere() {
        key := "click@" this.x "," this.y
        if !this.firstClick.Has(key)
            this.firstClick[key] := this.clock
        this.lastClick[key] := this.clock
        this.log.Push(key)
    }
    Wheel(dir, n := 1, gapMs := 25) {
        this.wheels.Push(dir " " n " " gapMs)
        this.log.Push("wheel " dir " " n)
    }
    WheelTotal(dir) {
        t := 0
        for w in this.wheels {
            p := StrSplit(w, " ")
            if (p[1] = dir)
                t += Integer(p[2])
        }
        return t
    }
    Wait(ms, ctx := "") {
        this._waits++
        if (this._stopAt && this._waits = this._stopAt) {
            ctx.Stop()
            this.log.Push("wait-stopped")
            return false
        }
        this.clock += ms
        return true
    }
    Count(text) {
        n := 0
        for line in this.log
            if (line == text)
                n++
        return n
    }
    Has(text) => this.Count(text) > 0
    IndexOf(text, from := 1) {
        i := from
        while (i <= this.log.Length) {
            if (this.log[i] == text)
                return i
            i++
        }
        return 0
    }
}

class FsRoblox {
    __New(ok := true) {
        this.ok := ok
        this.focusCalls := 0
    }
    Focus() {
        this.focusCalls++
        return this.ok
    }
}

class FsDeps {
    __New(io, unused := "", focusOk := true, logs := "") {
        this.io := io
        this.roblox := FsRoblox(focusOk)
        this.now := () => io.clock
        this.log := (msg) => (IsObject(logs) ? logs.Push(msg) : 0)
        this.grab := (x1, x2, ys, stride) => FsGrab(x1, x2, ys, stride)
    }
}

; Fake StripGrab.Rows reading the fake screen.
FsGrab(x1, x2, ys, stride) {
    FsScreen.grabbed := true
    FsScreen.inGrab := true
    try {
        out := []
        for y in ys {
            row := []
            x := x1
            while (x <= x2) {
                row.Push(FsScreen.fn.Call(x, y))
                x += stride
            }
            out.Push(row)
        }
    } finally {
        FsScreen.inGrab := false
    }
    return out
}

; Fake screen: FsScreen.fn := (x, y) => 0xRRGGBB.
class FsScreen {
    static fn := (x, y) => 0
    static grabbed := false     ; set by the first strip grab (see FsBiteScreen)
    static inGrab := false      ; true only while FsGrab reads (see FsCastScreen)
    static Install() {
        Pixel._getter := (x, y) => FsScreen.fn.Call(x, y)
        FsScreen.grabbed := false
        FsScreen.inGrab := false
    }
    static Restore() {
        Pixel._getter := (x, y) => Pixel._ScreenColor(x, y)
    }
}

FsRead(name) {
    return Json.Parse(FileRead(A_ScriptDir "\..\data\" name ".json", "UTF-8"))
}

; -> {cfg, dir}. Config lives in a temp dir; coords/routes injected from the
; shipped data files.
FsMakeCfg() {
    d := A_Temp "\vesper_fstest_" A_TickCount "_" Random(100000, 999999)
    DirCreate(d)
    cfg := Config.Load(d)
    cfg.Set("General.legacyReel", 1)      ; these tests drive the FishSol minigame; arrow reel: test_reel.ahk
    cfg.SetData("coords", FsRead("coords"))
    cfg.SetData("routes", FsRead("routes"))
    return {cfg: cfg, dir: d}
}

FsClean(d) {
    try DirDelete(d, true)
}

FsJoin(arr, sep := "|") {
    s := ""
    for v in arr
        s .= (A_Index > 1 ? sep : "") v
    return s
}

FsThrows(fn) {
    try fn()
    catch
        return true
    return false
}

; Screen where the bite pixel turns white at tick `biteAt`, the bar sample
; returns `bar`, and the strip returns `stripFn(x, y)`.
FsBiteScreen(io, biteAt, bar, stripFn) {
    FsScreen.fn := (x, y) => (x = 1536 && y = 1119)
        ? (io.clock >= biteAt ? 0xFFFFFF : 0x101010)
        : (x = 1261 && y = 1033 && !FsScreen.grabbed ? bar : stripFn.Call(x, y))
}

; Bite pixel turns white `afterMs` after the LATEST rod click (each cast gets
; its own bite). The bar sample point returns `bar` outside strip grabs; the
; strip returns stripFn(x, y).
FsCastScreen(io, afterMs, bar, stripFn) {
    FsScreen.fn := (x, y) => (x = 1536 && y = 1119)
        ? ((io.lastClick.Has("click@1161,1124") && io.clock >= io.lastClick["click@1161,1124"] + afterMs) ? 0xFFFFFF : 0x101010)
        : ((x = 1261 && y = 1033 && !FsScreen.inGrab) ? bar : stripFn.Call(x, y))
}

; ---- data files ------------------------------------------------------------

Test_FishData_FilesParseAndComplete() {
    coords := FsRead("coords")
    routes := FsRead("routes")
    AssertEq(FsJoin(FishLogic.Missing(coords, routes)), "", "no missing keys in shipped data")
    AssertTrue(coords.Has("_source") && coords["fishing"].Has("_source") && coords["sell"].Has("_source"), "coords has _source audit notes")
    AssertTrue(routes.Has("_source"), "routes has _source")
    ; FishSol 1440p values that must not drift
    AssertEq(FsJoin(coords["fishing"]["rod"], ","), "1161,1124", "rod click")
    AssertEq(FsJoin(coords["fishing"]["bite"]["pixel"], ","), "1536,1119", "bite pixel")
    AssertEq(coords["fishing"]["bite"]["color"], "0xFFFFFF", "bite color")
    AssertEq(FsJoin(coords["fishing"]["barSample"], ","), "1261,1033", "bar sample point")
    AssertEq(coords["fishing"]["strip"]["x1"], 1043, "strip x1")
    AssertEq(coords["fishing"]["strip"]["x2"], 1519, "strip x2")
    AssertEq(coords["fishing"]["strip"]["rows"][1], 1033, "strip top row")
    AssertEq(coords["fishing"]["strip"]["rows"][coords["fishing"]["strip"]["rows"].Length], 1058, "strip bottom row")
    AssertEq(coords["fishing"]["failsafe"]["fishingSec"], 31, "fishing failsafe")
    AssertEq(coords["fishing"]["failsafe"]["pathingSec"], 61, "pathing failsafe")
    AssertEq(coords["fishing"]["minigameCapMs"], 9000, "minigame cap")
    AssertEq(coords["sell"]["loop"]["loaded"]["color"], "0x999999", "shop loaded color")
    AssertEq(FsJoin(coords["sell"]["loop"]["loaded"]["pixel"], ","), "593,795", "shop loaded pixel")
    AssertEq(FsJoin(coords["sell"]["loop"]["sellAll"], ","), "904,1080", "sell all click")
    AssertEq(FsJoin(coords["sell"]["loop"]["sellSelected"], ","), "700,1078", "sell selected click")
    ; every route parses and has the recorded walk timings (nonvip = vip x1.25)
    for variant in ["vip", "nonvip"]
        for leg in ["toShop", "back"]
            AssertTrue(Input.ParseRoute(routes[variant][leg]).Length > 0, variant "." leg " parses")
    AssertEq(Input.RouteMs(routes["vip"]["toShop"]), 11477, "vip toShop ms")
    AssertEq(Input.RouteMs(routes["vip"]["back"]), 3767, "vip back ms")
    AssertEq(Input.RouteMs(routes["nonvip"]["toShop"]), 14347, "nonvip toShop ms")
    AssertEq(Input.RouteMs(routes["nonvip"]["back"]), 4709, "nonvip back ms")
}

Test_FishData_MissingKeyDetected() {
    coords := FsRead("coords")
    routes := FsRead("routes")
    coords["fishing"].Delete("rod")
    routes["vip"].Delete("back")
    missing := FishLogic.Missing(coords, routes)
    AssertEq(missing.Length, 2, "two keys missing")
    AssertEq(missing[1], "coords.fishing.rod", "coords path named")
    AssertEq(missing[2], "routes.vip.back", "routes path named")
    ; a point that is not [x, y] is reported too
    coords2 := FsRead("coords")
    coords2["fishing"]["rod"] := [1161]
    AssertEq(FishLogic.Missing(coords2, FsRead("routes")).Length, 1, "bad point shape reported")
    ; empty maps (Config fallback for missing files) report everything
    AssertTrue(FishLogic.Missing(Map(), Map()).Length > 20, "empty data reports all keys")
}

Test_FishData_TaskCtorRejectsBadData() {
    t := FsMakeCfg()
    try {
        t.cfg.SetData("coords", Map())
        AssertTrue(FsThrows(() => FishingTask(t.cfg, SchedState())), "FishingTask ctor throws on empty coords")
        AssertTrue(FsThrows(() => SellTask(t.cfg, SchedState())), "SellTask ctor throws on empty coords")
    } finally {
        FsClean(t.dir)
    }
}

; ---- pure minigame decision ------------------------------------------------

Test_FishLogic_Xs() {
    AssertEq(FsJoin(FishLogic.Xs(10, 20, 4)), "10|14|18", "xs by stride")
    AssertEq(FsJoin(FishLogic.Xs(10, 10, 4)), "10", "single x")
}

Test_FishLogic_NormalDecision() {
    bar := 0x3366CC
    other := 0x202020
    ; bar color present anywhere in the strip -> do not click
    rows := [[other, other, other], [other, bar, other], [other, other, other]]
    AssertEq(FishLogic.ShouldClick(rows, 6, bar, 5, false, 25), false, "bar present -> no click")
    ; absent -> click
    rows2 := [[other, other], [other, other]]
    AssertEq(FishLogic.ShouldClick(rows2, 6, bar, 5, false, 25), true, "bar absent -> click")
    ; within tolerance counts as present, outside does not
    near := 0x3668CA     ; +3,+2,-2
    far := 0x3F6FD3      ; +9,+9,+7
    AssertEq(FishLogic.ShouldClick([[near]], 6, bar, 5, false, 25), false, "within tol -> present")
    AssertEq(FishLogic.ShouldClick([[far]], 6, bar, 5, false, 25), true, "outside tol -> absent")
    AssertEq(FishLogic.ShouldClick([], 6, bar, 5, false, 25), true, "no samples -> click")
}

Test_FishLogic_AdvancedDecision() {
    bar := 0x3366CC
    o := 0x202020
    stride := 3
    ; run of 10 matching samples -> width 9*3 = 27 >= 25 -> no click
    row := [o, o]
    Loop 10
        row.Push(bar)
    row.Push(o)
    AssertEq(FishLogic.BarWidth(row, stride, bar, 5, 10), 27, "width of 10-sample run")
    AssertEq(FishLogic.ShouldClick([row], stride, bar, 5, true, 25), false, "wide bar -> no click")
    ; run of 8 samples -> 21 < 25 -> click
    row2 := [o]
    Loop 8
        row2.Push(bar)
    row2.Push(o)
    AssertEq(FishLogic.BarWidth(row2, stride, bar, 5, 10), 21, "width of 8-sample run")
    AssertEq(FishLogic.ShouldClick([row2], stride, bar, 5, true, 25), true, "narrow bar -> click")
    ; no bar at all -> click
    AssertEq(FishLogic.BarWidth([o, o, o], stride, bar, 5, 10), -1, "no bar -> -1")
    AssertEq(FishLogic.ShouldClick([[o, o, o]], stride, bar, 5, true, 25), true, "no bar -> click")
    ; only the first run counts (FishSol extends right from the first hit)
    row3 := [bar, bar, o, bar, bar, bar, bar, bar, bar, bar, bar, bar]
    AssertEq(FishLogic.BarWidth(row3, stride, bar, 5, 10), 3, "first run only")
    ; extend tolerance (10) is wider than the search tolerance (5)
    wide := 0x3D70D6     ; +10,+10,+10 vs bar
    row4 := [bar, wide, wide, o]
    AssertEq(FishLogic.BarWidth(row4, stride, bar, 5, 10), 6, "extend tol 10 keeps run going")
    AssertEq(FishLogic.BarWidth([wide, wide], stride, bar, 5, 10), -1, "search tol 5 rejects first hit")
}

; ---- fishing task ----------------------------------------------------------

Test_Fishing_Contract() {
    t := FsMakeCfg()
    try {
        task := FishingTask(t.cfg, SchedState())
        AssertEq(task.name, "fishing", "name")
        AssertEq(task.priority, 99, "priority")
        AssertEq(task.CanRun(SchedState()), true, "fishing on by default")
        t.cfg.Set("General.fishing", 0)
        AssertEq(task.CanRun(SchedState()), false, "General.fishing = 0: never fishes")
        t.cfg.Set("General.fishing", 1)
    } finally {
        FsClean(t.dir)
    }
}

Test_Fishing_BarPresentNeverClicksMinigame() {
    t := FsMakeCfg()
    FsScreen.Install()
    try {
        st := SchedState()
        io := FsIO()
        bar := 0x3366CC
        FsBiteScreen(io, 2000, bar, (x, y) => bar)      ; bar visible everywhere
        task := FishingTask(t.cfg, st, FsDeps(io))
        r := task.CatchOnce(SchedCtx())
        AssertEq(r, "ok", "catch ok")
        AssertEq(st.fishLoops, 1, "fishLoops incremented")
        AssertEq(io.Count("click@1161,1124"), 1, "rod clicked once")
        AssertEq(io.Count("click@1457,491"), 1, "close/claim clicked once")
        n := 0
        for line in io.log
            if (SubStr(line, 1, 6) = "click@")
                n++
        AssertEq(n, 2, "no minigame clicks while bar is in the zone")
        ; ran the full 9 s cap
        AssertTrue(io.clock >= 2000 + 9000, "minigame ran its 9 s cap")
    } finally {
        FsScreen.Restore()
        FsClean(t.dir)
    }
}

Test_Fishing_BarAbsentClicks() {
    t := FsMakeCfg()
    FsScreen.Install()
    try {
        st := SchedState()
        io := FsIO()
        ; bar seen at the start (real bite), then leaves the strip for good
        FsBiteScreen(io, 1500, 0x3366CC, (x, y) => io.clock < 2000 ? 0x3366CC : 0x202020)
        task := FishingTask(t.cfg, st, FsDeps(io))
        AssertEq(task.CatchOnce(SchedCtx()), "ok", "catch ok")
        AssertTrue(io.Count("click@1263,1177") > 20, "many minigame clicks at the parked mouse")
        ; the mouse was parked after the bite
        AssertTrue(io.IndexOf("move 1263,1177") > io.IndexOf("click@1161,1124"), "mouse parked after rod click")
        ; close click is last
        AssertEq(io.log[io.log.Length], "click@1457,491", "close click is the last input")
    } finally {
        FsScreen.Restore()
        FsClean(t.dir)
    }
}

; 2026-11-09 22:11:17: the Biome Randomizer took over mid reel: the reel bar
; ran on under the inventory and the "Fishing Failed" card covered the next
; hunt. A preempt after the bite lands the fish and closes its card first.
Test_Fishing_PreemptMidReelLandsTheFishFirst() {
    t := FsMakeCfg()
    FsScreen.Install()
    try {
        st := SchedState()
        io := FsIO()
        ctx := SchedCtx()
        FsBiteScreen(io, 1500, 0x3366CC, (x, y) => ((io.clock >= 1600 ? ctx.RequestPreempt() : 0), io.clock < 2000 ? 0x3366CC : 0x202020))
        task := FishingTask(t.cfg, st, FsDeps(io))
        AssertEq(task.CatchOnce(ctx), "ok", "the catch finished")
        AssertTrue(ctx.ShouldStop(), "the preempt is still asked for (the next task runs after)")
        AssertEq(io.log[io.log.Length], "click@1457,491", "its card closed last")
    } finally {
        FsScreen.Restore()
        FsClean(t.dir)
    }
}

Test_Fishing_AdvancedModeUsesWidth() {
    t := FsMakeCfg()
    FsScreen.Install()
    try {
        t.cfg.Set("General.advancedFishing", 1)
        t.cfg.Set("General.advancedThreshold", 25)
        st := SchedState()
        io := FsIO()
        bar := 0x3366CC
        ; 8 px wide bar at x 1100..1107 on row 1033: narrower than 25 -> click
        FsBiteScreen(io, 1500, bar, (x, y) => (y = 1033 && x >= 1100 && x <= 1107) ? bar : 0x202020)
        task := FishingTask(t.cfg, st, FsDeps(io))
        task.CatchOnce(SchedCtx())
        AssertTrue(io.Count("click@1263,1177") > 20, "narrow bar -> clicks")
        ; 60 px wide bar -> no minigame clicks
        io2 := FsIO()
        FsBiteScreen(io2, 1500, bar, (x, y) => (y = 1033 && x >= 1100 && x <= 1160) ? bar : 0x202020)
        task2 := FishingTask(t.cfg, SchedState(), FsDeps(io2))
        task2.CatchOnce(SchedCtx())
        AssertEq(io2.Count("click@1263,1177"), 0, "wide bar -> no minigame clicks")
    } finally {
        FsScreen.Restore()
        FsClean(t.dir)
    }
}

Test_Fishing_FailsafesFireAt31And61() {
    t := FsMakeCfg()
    FsScreen.Install()
    try {
        st := SchedState()
        io := FsIO()
        FsScreen.fn := (x, y) => 0x101010          ; never bites
        task := FishingTask(t.cfg, st, FsDeps(io))
        r := task.CatchOnce(SchedCtx())
        AssertEq(r, "repath", "pathing failsafe -> repath")
        AssertTrue(io.Has("click@1690,1224"), "fishing failsafe click 1")
        AssertTrue(io.Has("click@1523,649"), "fishing failsafe click 2")
        AssertTrue(io.Has("click@1163,1126"), "fishing failsafe re-cast click")
        AssertEq(io.Count("click@1690,1224"), 1, "fishing failsafe runs once")
        AssertTrue(io.firstClick["click@1690,1224"] >= 31000, "first failsafe click at/after 31 s, at " io.firstClick["click@1690,1224"])
        AssertTrue(io.firstClick["click@1690,1224"] < 33000, "first failsafe click not much later than 31 s")
        AssertTrue(io.clock >= 61000 && io.clock < 70000, "gave up at ~61 s, clock=" io.clock)
        ; failsafe click sequence started after 31 s
        AssertEq(st.needRepath, true, "repath forces the sell task due (needRepath)")
        AssertEq(st.fishLoops, 0, "repath does not inflate fishLoops")
        ; setting overrides
        t.cfg.Set("General.fishingFailsafeSec", 5)
        t.cfg.Set("General.pathingFailsafeSec", 8)
        io2 := FsIO()
        st2 := SchedState()
        task2 := FishingTask(t.cfg, st2, FsDeps(io2))
        AssertEq(task2.CatchOnce(SchedCtx()), "repath", "custom failsafes")
        AssertTrue(io2.clock >= 8000 && io2.clock < 12000, "custom pathing failsafe at ~8 s, clock=" io2.clock)
        AssertTrue(io2.firstClick["click@1690,1224"] >= 5000, "custom failsafe click at/after 5 s, at " io2.firstClick["click@1690,1224"])
        AssertTrue(io2.firstClick["click@1690,1224"] < 7000, "custom failsafe click not much later than 5 s")
    } finally {
        FsScreen.Restore()
        FsClean(t.dir)
    }
}

; FsIO with the fishing panel read through Ocr(), as the game shows it: the
; button (1050..1250 x 1095..1140) reads Fish until a click on it casts,
; then Exit until a click on it reels the line back in. The rod click
; (1161,1124) and the failsafe's 1163,1126 are both on it. castLost: casts
; that do not take (the line stays in). Nothing ever bites.
class FsPanelIO extends FsIO {
    __New(castLost := 0) {
        super.__New()
        this.lineOut := false
        this.castLost := castLost
        this.casts := 0
        this.reeledIn := 0
    }
    Ocr(x, y, w, h, scale := 1) {
        if (x = 1050)
            return this.lineOut ? "Exit" : "Fish"
        if (x = 1130)
            return "Fishing"
        return ""
    }
    ClickHere() {
        super.ClickHere()
        if !(this.x >= 1050 && this.x < 1250 && this.y >= 1095 && this.y < 1140)
            return
        if this.lineOut {
            this.lineOut := false
            this.reeledIn++
        } else if (++this.casts > this.castLost) {
            this.lineOut := true
        }
    }
}

Test_Fishing_FailsafeNeverReelsTheLineIn() {
    ; 2026-10-27 review: the failsafe's last click (1163,1126) is the panel's
    ; button; with the line out it reads Exit, the click reeled the line in
    ; and nothing cast again until the pathing failsafe re-pathed
    t := FsMakeCfg()
    t.cfg.Set("General.legacyReel", 0)
    FsScreen.Install()
    try {
        FsScreen.fn := (x, y) => 0x101010          ; no reel bar: never bites
        io := FsPanelIO()
        logs := []
        r := FishingTask(t.cfg, SchedState(), FsDeps(io, "", true, logs)).CatchOnce(SchedCtx())
        AssertEq(r, "repath", "no bite: the pathing failsafe in the end")
        AssertTrue(io.Has("click@1690,1224") && io.Has("click@1523,649") && io.Has("click@1457,491"), "the other failsafe clicks")
        AssertEq(io.Count("click@1163,1126"), 0, "the button is not clicked while it reads Exit")
        AssertEq(io.reeledIn, 0, "the line was never reeled in")
        AssertTrue(FsHasLog(logs, "failsafe click on the button skipped"), "logged")
        ; the cast was lost (the button still reads Fish): the failsafe click casts
        io2 := FsPanelIO(1)
        FishingTask(t.cfg, SchedState(), FsDeps(io2)).CatchOnce(SchedCtx())
        AssertEq(io2.Count("click@1163,1126"), 1, "lost cast: the failsafe click on the button")
        AssertEq(io2.lineOut, true, "lost cast: the line is out after the failsafe")
        ; that click is lost too: the button still reads Fish, so cast again
        io3 := FsPanelIO(2)
        logs3 := []
        FishingTask(t.cfg, SchedState(), FsDeps(io3, "", true, logs3)).CatchOnce(SchedCtx())
        AssertEq(io3.Count("click@1161,1124"), 2, "cast again after the failsafe")
        AssertEq(io3.lineOut, true, "the line is out")
        AssertTrue(FsHasLog(logs3, "casting again"), "logged")
    } finally {
        FsScreen.Restore()
        FsClean(t.dir)
    }
}

Test_Fishing_FailCardInTheGameFont() {
    ; "Fishing Failed" reads "Fishing Foiled" (the font of "Fish Cought!"):
    ; a title-only read counted a lost fish as caught (2026-10-27 review).
    ; Matched in code, so the shipped failWords stay as they are.
    t := FsMakeCfg()
    try {
        task := FishingTask(t.cfg, SchedState(), FsDeps(FsIO()))
        for txt in ["Fishing Foiled", "Fishing FoiIed", "Fishing Failed", "The fish is gone...", "Fishing Foiled`nThe fish is g0ne"]
            AssertEq(task._CardKind(txt), "failed", "'" txt "' is a miss")
        for txt in ["Fish Cought!", "Fish Caught!`nYou've got Stonefish!"]
            AssertEq(task._CardKind(txt), "caught", "'" txt "' is a catch")
        AssertEq(task._CardKind("Fishing`nFish"), "", "the fishing panel is no card")
        AssertEq(FsJoin(FsRead("coords")["fishing"]["result"]["failWords"]), "failed|gone", "data\coords.json failWords unchanged")
    } finally {
        FsClean(t.dir)
    }
}

Test_Fishing_StopDuringBiteWait() {
    t := FsMakeCfg()
    FsScreen.Install()
    try {
        st := SchedState()
        io := FsIO(4)       ; stop on the 4th wait
        FsScreen.fn := (x, y) => 0x101010
        task := FishingTask(t.cfg, st, FsDeps(io))
        ctx := SchedCtx()
        AssertEq(task.CatchOnce(ctx), "stopped", "stop -> stopped")
        AssertEq(st.fishLoops, 0, "no loop counted")
    } finally {
        FsScreen.Restore()
        FsClean(t.dir)
    }
}

Test_FishLogic_SellEveryClampedToOne() {
    t := FsMakeCfg()
    try {
        for v in [0, -5] {
            t.cfg.Set("General.sellEvery", v)
            AssertEq(FishLogic.SellEvery(t.cfg), 1, "sellEvery " v " -> 1")
        }
        t.cfg.Set("General.sellEvery", "abc")
        AssertEq(FishLogic.SellEvery(t.cfg), 15, "not a number -> 15")
        t.cfg.Set("General.sellEvery", 7)
        AssertEq(FishLogic.SellEvery(t.cfg), 7, "valid value kept")
    } finally {
        FsClean(t.dir)
    }
}

Test_Fishing_YieldsBetweenCatchesWhenChatDue() {
    t := FsMakeCfg()
    FsScreen.Install()
    try {
        st := SchedState()
        st.chatDue := true                  ; app wants a chat read
        io := FsIO()
        bar := 0x3366CC
        FsCastScreen(io, 500, bar, (x, y) => bar)      ; each cast bites 500 ms in
        FishingTask(t.cfg, st, FsDeps(io)).Run(SchedCtx())
        AssertEq(st.fishLoops, 1, "finishes one catch, then returns for the chat check")
        AssertEq(io.Count("click@1161,1124"), 1, "one cast")
        AssertEq(st.chatDue, true, "the app clears chatDue, not fishing")
    } finally {
        FsScreen.Restore()
        FsClean(t.dir)
    }
}

Test_Fishing_RunStopsWhenSellDue() {
    t := FsMakeCfg()
    FsScreen.Install()
    try {
        t.cfg.Set("General.sellEvery", 2)
        st := SchedState()
        io := FsIO()
        bar := 0x3366CC
        FsCastScreen(io, 500, bar, (x, y) => bar)      ; each cast bites 500 ms in
        task := FishingTask(t.cfg, st, FsDeps(io))
        task.Run(SchedCtx())
        AssertEq(st.fishLoops, 2, "Run catches until sell is due, then returns")
        n := io.Count("click@1161,1124")
        AssertEq(n, 2, "two casts")
        ; already due: returns without touching the game
        io2 := FsIO()
        st2 := SchedState()
        st2.fishLoops := 5
        FishingTask(t.cfg, st2, FsDeps(io2)).Run(SchedCtx())
        AssertEq(io2.log.Length, 0, "no input when sell already due")
        ; stopped ctx: no input
        io3 := FsIO()
        ctx := SchedCtx()
        ctx.Stop()
        FishingTask(t.cfg, SchedState(), FsDeps(io3)).Run(ctx)
        AssertEq(io3.log.Length, 0, "no input when already stopped")
    } finally {
        FsScreen.Restore()
        FsClean(t.dir)
    }
}

; ---- sell task -------------------------------------------------------------

Test_Sell_CanRunByLoops() {
    t := FsMakeCfg()
    try {
        task := SellTask(t.cfg, SchedState())
        AssertEq(task.name, "sell", "name")
        AssertEq(task.priority, 6, "priority")
        st := SchedState()
        st.fishLoops := 14
        AssertEq(task.CanRun(st), false, "14 loops: not yet")
        st.fishLoops := 15
        AssertEq(task.CanRun(st), true, "15 loops: due")
        t.cfg.Set("General.sellEvery", 3)
        st.fishLoops := 3
        AssertEq(task.CanRun(st), true, "setting honoured")
        st.fishLoops := 2
        AssertEq(task.CanRun(st), false, "below setting")
    } finally {
        FsClean(t.dir)
    }
}

; Screen for a sell run: shop loads (0x999999), daily reward absent, nothing
; left to sell after `rounds` rounds.
; a state with fish caught since the last sell (an empty trip skips the shop)
FsCaught() {
    st := SchedState()
    st.fishLoops := 5
    return st
}

FsSellScreen(io, rounds := 1) {
    st := {confirms: 0}
    FsScreen.fn := (x, y) => (x = 593 && y = 795) ? 0x999999
        : ((y >= 595 && y <= 604 && x >= 1027 && x <= 1183) ? (io.Count("click@1002,831") < rounds ? 0xFFFFFF : 0x101010)
        : 0x101010)
}

Test_Sell_VipFlow() {
    t := FsMakeCfg()
    FsScreen.Install()
    try {
        st := SchedState()
        st.fishLoops := 15
        io := FsIO()
        FsSellScreen(io, 1)
        task := SellTask(t.cfg, st, FsDeps(io))
        task.Run(SchedCtx())
        AssertEq(st.fishLoops, 0, "fishLoops reset after sell")
        ; reset first (Esc is the first key)
        AssertEq(io.IndexOf("down Esc"), 1, "ResetToSpawn runs first")
        AssertEq(io.WheelTotal("up"), 80, "camera zoom: 80 notches up via io.Wheel")
        AssertEq(io.WheelTotal("down"), 35, "camera zoom: 35 notches down via io.Wheel")
        AssertTrue(io.IndexOf("wheel up 10") > io.IndexOf("down Esc") && io.IndexOf("wheel down 10") > io.IndexOf("wheel up 10"), "wheel after reset, up before down")
        ; VIP route keys: a held 4150 then ... e tap
        AssertTrue(io.IndexOf("down a") > io.IndexOf("down Esc"), "route after reset")
        ; walk time: the VIP legs ran, not the non-VIP ones
        keys := FsJoin(io.log)
        AssertTrue(InStr(keys, "down Space"), "route jumps")
        AssertTrue(io.Has("down e") && io.Has("up e"), "interacts with e")
        ; dialog + sell clicks in order
        iDlg := io.IndexOf("click@1308,1073")
        AssertTrue(iDlg > 0, "dialog A clicked")
        AssertEq(io.Count("click@1308,1073"), 2, "dialog A clicked twice")
        iB := io.IndexOf("click@1289,1264")
        iItem := io.IndexOf("click@1117,550")
        iOpt := io.IndexOf("click@904,1080")
        iConf := io.IndexOf("click@1002,831")
        iClose := io.IndexOf("click@1958,361")
        AssertTrue(iDlg < iB && iB < iItem && iItem < iOpt && iOpt < iConf && iConf < iClose, "click order dialog->item->option->confirm->close")
        AssertEq(io.Count("click@700,1078"), 0, "sell-all by default: no sell-selected click")
        AssertEq(io.Count("click@1945,355"), 0, "shop loaded: no rescue close click")
        ; return leg after the shop close: last key activity is w
        lastDown := 0
        Loop io.log.Length
            if (SubStr(io.log[A_Index], 1, 5) = "down ")
                lastDown := A_Index
        AssertEq(io.log[lastDown], "down w", "returns with w")
    } finally {
        FsScreen.Restore()
        FsClean(t.dir)
    }
}

; live 2026-11-10: 77 of 132 trips (walks back after a hunt / the obby)
; sold 0 fish but still went through the whole shop
Test_Sell_NothingCaughtSkipsTheShop() {
    t := FsMakeCfg()
    FsScreen.Install()
    try {
        st := SchedState()
        st.fishLoops := 0, st.needRepath := true
        io := FsIO()
        FsSellScreen(io, 1)
        d := FsDeps(io)
        logs := []
        d.log := (s) => logs.Push(s)
        d.afterSell := (ctx) => (io.log.Push("BUY HERE"), 1)
        SellTask(t.cfg, st, d).Run(SchedCtx())
        AssertEq(io.Count("click@1289,1264"), 0, "no Open Shop click")
        AssertEq(io.Count("click@1958,361"), 0, "no shop X")
        AssertEq(io.Count("click@1308,1073"), 2, "his text clicked through (Leave only shows after it)")
        AssertTrue(io.IndexOf("BUY HERE") > 0, "a due buy still happens")
        AssertEq(st.needRepath, false, "back at the fishing spot")
        found := false
        for l in logs
            found := found || InStr(l, "skipping the shop")
        AssertTrue(found, "logged")
        lastDown := 0
        Loop io.log.Length
            if (SubStr(io.log[A_Index], 1, 5) = "down ")
                lastDown := A_Index
        AssertEq(io.log[lastDown], "down w", "walked back")
        ; the first sell of a run always sells (fish from before the start)
        st2 := SchedState()
        st2.fishLoops := 0, st2.needRepath := true, st2.startSell := true
        io2 := FsIO()
        FsSellScreen(io2, 1)
        SellTask(t.cfg, st2, FsDeps(io2)).Run(SchedCtx())
        AssertTrue(io2.Count("click@1289,1264") > 0, "start sell opens the shop")
    } finally {
        FsScreen.Restore()
        FsClean(t.dir)
    }
}

; The user's own recorded sell walks (Setup > Routes) replace the shipped
; ones; E is pressed after sell_to_fisher; a broken recording falls back.
Test_Sell_UsesTheRecordedWalks() {
    t := FsMakeCfg()
    FsScreen.Install()
    try {
        io := FsIO()
        FsSellScreen(io, 1)
        task := SellTask(t.cfg, FsCaught(), FsDeps(io))
        task._routes["sell_to_fisher"] := Map("steps", [["d", "down", 777], ["d", "up", 0]])
        task._routes["fisher_to_fishing"] := Map("steps", [["s", "down", 555], ["s", "up", 0]])
        task.Run(SchedCtx())
        iD := io.IndexOf("down d"), iE := io.IndexOf("down e"), iBack := io.IndexOf("down s")
        AssertTrue(iD > 0 && iE > iD, "recorded walk, then E")
        AssertEq(io.IndexOf("down Space"), 0, "the shipped walk (with its jump) not used")
        AssertTrue(iBack > iE, "recorded walk back")
        io2 := FsIO()
        FsSellScreen(io2, 1)
        task2 := SellTask(t.cfg, FsCaught(), FsDeps(io2))
        task2._routes["sell_to_fisher"] := Map("steps", "broken")
        task2.Run(SchedCtx())
        AssertTrue(io2.IndexOf("down Space") > 0, "broken recording: the shipped walk")
    } finally {
        FsScreen.Restore()
        FsClean(t.dir)
    }
}

Test_Sell_BuysInTheSameVisitBeforeWalkingBack() {
    t := FsMakeCfg()
    FsScreen.Install()
    try {
        st := SchedState()
        st.fishLoops := 15
        io := FsIO()
        FsSellScreen(io, 1)
        d := FsDeps(io)
        d.afterSell := (ctx) => (io.log.Push("BUY HERE"), 1)
        SellTask(t.cfg, st, d).Run(SchedCtx())
        iBuy := io.IndexOf("BUY HERE")
        iClose := io.IndexOf("click@1958,361")
        AssertTrue(iClose > 0 && iBuy > iClose, "the buy comes after the sell shop is closed")
        lastDown := 0
        Loop io.log.Length
            if (SubStr(io.log[A_Index], 1, 5) = "down ")
                lastDown := A_Index
        AssertTrue(lastDown > iBuy && io.log[lastDown] = "down w", "then the walk back to fishing")
        AssertEq(io.Count("down Esc"), 1, "one respawn for the whole visit (sell + buy)")
        AssertEq(st.fishLoops, 0, "sell done")
        ; stopped while buying: no walk back
        st2 := SchedState()
        st2.fishLoops := 15
        io2 := FsIO()
        FsSellScreen(io2, 1)
        d2 := FsDeps(io2)
        d2.afterSell := (ctx) => -1
        SellTask(t.cfg, st2, d2).Run(SchedCtx())
        AssertEq(st2.fishLoops, 15, "stopped during the buy: sell not marked done")
    } finally {
        FsScreen.Restore()
        FsClean(t.dir)
    }
}

Test_Sell_VipVsNonVipDuration() {
    t := FsMakeCfg()
    FsScreen.Install()
    try {
        io := FsIO()
        FsSellScreen(io, 1)
        SellTask(t.cfg, FsCaught(), FsDeps(io, [])).Run(SchedCtx())
        vipMs := io.clock
        t.cfg.Set("General.vip", 0)
        io2 := FsIO()
        FsSellScreen(io2, 1)
        SellTask(t.cfg, FsCaught(), FsDeps(io2, [])).Run(SchedCtx())
        ; non-VIP legs are longer by (14347-11477) + (4709-3767)
        AssertEq(io2.clock - vipMs, (14347 - 11477) + (4709 - 3767), "non-VIP route timings used")
        ; default (no key) is VIP
        t2 := FsMakeCfg()
        try {
            io3 := FsIO()
            FsSellScreen(io3, 1)
            SellTask(t2.cfg, FsCaught(), FsDeps(io3, [])).Run(SchedCtx())
            AssertEq(io3.clock, vipMs, "default is VIP")
        } finally {
            FsClean(t2.dir)
        }
    } finally {
        FsScreen.Restore()
        FsClean(t.dir)
    }
}

Test_Sell_SellAllSetting() {
    t := FsMakeCfg()
    FsScreen.Install()
    try {
        t.cfg.Set("General.sellAll", 1)
        io := FsIO()
        FsSellScreen(io, 1)
        SellTask(t.cfg, FsCaught(), FsDeps(io, [])).Run(SchedCtx())
        AssertEq(io.Count("click@904,1080"), 1, "sell-all click")
        AssertEq(io.Count("click@700,1078"), 0, "no selected click")
        t.cfg.Set("General.sellAll", 0)
        io2 := FsIO()
        FsSellScreen(io2, 1)
        SellTask(t.cfg, FsCaught(), FsDeps(io2, [])).Run(SchedCtx())
        AssertEq(io2.Count("click@700,1078"), 1, "sellAll 0: selected click")
        AssertEq(io2.Count("click@904,1080"), 0, "sellAll 0: no sell-all click")
    } finally {
        FsScreen.Restore()
        FsClean(t.dir)
    }
}

Test_Sell_RepeatsWhileMoreToSell() {
    t := FsMakeCfg()
    FsScreen.Install()
    try {
        io := FsIO()
        FsSellScreen(io, 3)
        SellTask(t.cfg, FsCaught(), FsDeps(io, [])).Run(SchedCtx())
        AssertEq(io.Count("click@1002,831"), 3, "three sell rounds while white pixels remain")
    } finally {
        FsScreen.Restore()
        FsClean(t.dir)
    }
}

Test_Sell_ShopNotLoadedClosesAndGoesOn() {
    t := FsMakeCfg()
    FsScreen.Install()
    try {
        io := FsIO()
        FsScreen.fn := (x, y) => 0x101010       ; shop pixel never 0x999999, nothing to sell
        st := SchedState()
        st.fishLoops := 15
        SellTask(t.cfg, st, FsDeps(io, [])).Run(SchedCtx())
        AssertEq(io.Count("click@1945,355"), 1, "5 s timeout -> rescue close click")
        AssertEq(st.fishLoops, 0, "still finishes and resets")
    } finally {
        FsScreen.Restore()
        FsClean(t.dir)
    }
}

Test_Sell_DailyRewardClaimed() {
    t := FsMakeCfg()
    FsScreen.Install()
    try {
        io := FsIO()
        base := (x, y) => (x = 593 && y = 795) ? 0x999999 : 0x101010
        FsScreen.fn := (x, y) => (x = 1228 && y = 884 && io.Count("click@1280,895") = 0) ? 0x7ffd90 : base.Call(x, y)
        SellTask(t.cfg, FsCaught(), FsDeps(io, [])).Run(SchedCtx())
        AssertEq(io.Count("click@1280,895"), 1, "daily reward claim clicked")
        AssertEq(io.Count("click@1890,527"), 1, "daily reward closed")
        ; claim happens before the route
        AssertTrue(io.IndexOf("click@1280,895") < io.IndexOf("down a"), "claim before walking")
    } finally {
        FsScreen.Restore()
        FsClean(t.dir)
    }
}

Test_Sell_StopMidRouteKeepsLoopsAndReleasesKeys() {
    t := FsMakeCfg()
    FsScreen.Install()
    try {
        st := SchedState()
        st.fishLoops := 15
        FsScreen.fn := (x, y) => 0x101010
        ; reset uses 3 key waits + 3 waits, camera 2, then the route starts.
        ; Find a stop point inside the route by scanning wait indexes.
        found := false
        Loop 25 {
            n := 10 + A_Index
            io := FsIO(n)
            st2 := SchedState()
            st2.fishLoops := 15
            ctx := SchedCtx()
            SellTask(t.cfg, st2, FsDeps(io, [])).Run(ctx)
            AssertTrue(ctx.IsStopped(), "ctx stopped (n=" n ")")
            AssertEq(st2.fishLoops, 15, "stopped sell keeps fishLoops (n=" n ")")
            ; every key pressed was released
            downs := Map()
            for line in io.log {
                if (SubStr(line, 1, 5) = "down ")
                    downs[SubStr(line, 6)] := (downs.Has(SubStr(line, 6)) ? downs[SubStr(line, 6)] : 0) + 1
                else if (SubStr(line, 1, 3) = "up ")
                    downs[SubStr(line, 4)] := (downs.Has(SubStr(line, 4)) ? downs[SubStr(line, 4)] : 0) - 1
            }
            for k, v in downs
                AssertEq(v, 0, "key " k " balanced (n=" n ")")
            if (io.Has("down a"))
                found := true
        }
        AssertTrue(found, "scanned stop points inside the route")
    } finally {
        FsScreen.Restore()
        FsClean(t.dir)
    }
}

; ---- real strip grab (live screen smoke test) -------------------------------

Test_StripGrab_MatchesPixelGetColor() {
    rows := StripGrab.Rows(100, 163, [200, 205, 210], 1)
    AssertEq(rows.Length, 3, "one row per requested y")
    AssertEq(rows[1].Length, 64, "64 px per row at stride 1")
    AssertEq(StripGrab.Rows(100, 163, [200], 4)[1].Length, 16, "stride 4 -> 16 samples")
    ; Compare against PixelGetColor at scattered points (screen may animate,
    ; so allow a few mismatches).
    same := 0
    total := 0
    for yi, y in [200, 205, 210] {
        for x in [100, 117, 133, 150, 163] {
            total++
            if Pixel.Match(rows[yi][x - 100 + 1], Pixel.Get(x, y), 24)
                same++
        }
    }
    AssertTrue(same >= total - 3, "grab agrees with PixelGetColor (" same "/" total ")")
    ; a color is a plain 0xRRGGBB integer
    AssertTrue(rows[1][1] >= 0 && rows[1][1] <= 0xFFFFFF, "color in range")
}

; ---- settings, focus, capture safety ---------------------------------------

Test_Fishing_ConfigDefaultsRegistered() {
    t := FsMakeCfg()
    try {
        g := Config.IniDefaults()["General"]
        AssertEq(g["vip"], "1", "Config default vip = 1 (VIP)")
        AssertEq(g["sellAll"], "1", "sellAll default")
        AssertEq(g["advancedFishing"], "0", "advancedFishing default")
        AssertEq(g["advancedThreshold"], "20", "advancedThreshold default")
        AssertEq(g["fishingFailsafeSec"], "31", "fishingFailsafeSec default")
        AssertEq(g["pathingFailsafeSec"], "61", "pathingFailsafeSec default")
        o := FishLogic.Settings(t.cfg, FsRead("coords"))
        AssertEq(o.vip, true, "settings: vip")
        AssertEq(o.sellAll, true, "settings: sellAll")
        AssertEq(o.advanced, false, "settings: advanced")
        AssertEq(o.threshold, 20, "settings: threshold from ini default")
        AssertEq(o.fishingSec, 31, "settings: fishing failsafe")
        AssertEq(o.pathingSec, 61, "settings: pathing failsafe")
        AssertEq(o.sellEvery, 15, "settings: sellEvery")
        AssertEq(FishLogic.SellEvery(t.cfg), 15, "SellEvery helper")
    } finally {
        FsClean(t.dir)
    }
}

Test_Fishing_FailsafeSecondsAreClamped() {
    vals := Map("General.fishingFailsafeSec", "0", "General.pathingFailsafeSec", "abc")
    cfg := {}
    cfg.DefineProp("Get", {Call: (self, k, d := "") => vals.Has(k) ? vals[k] : d})
    o := FishLogic.Settings(cfg, FsRead("coords"))
    AssertEq(o.fishingSec, FishLogic.MinFishingSec, "0 in settings.ini -> the Dashboard's minimum")
    AssertEq(o.pathingSec, 61, "text -> the coords.json default")
    vals["General.pathingFailsafeSec"] := "3"
    AssertEq(FishLogic.Settings(cfg, FsRead("coords")).pathingSec, FishLogic.MinPathingSec, "below the minimum -> the minimum")
}

Test_Fishing_OffMeansNoSell() {
    vals := Map("General.fishing", "0", "Craft.enabled", "0")
    cfg := {}
    cfg.DefineProp("Get", {Call: (self, k, d := "") => vals.Has(k) ? vals[k] : d})
    st := SchedState()
    st.needRepath := true, st.fishLoops := 99
    AssertEq(FishLogic.SellDue(st, cfg), false, "fishing off: no sell trip (hunting only, 2026-10-31)")
    vals["General.fishing"] := "1"
    AssertEq(FishLogic.SellDue(st, cfg), true, "fishing on: due")
}

Test_Input_WheelThroughIo() {
    io := FsIO()
    Input.Wheel("up", 3, io)
    Input.Wheel("down", 1, io)
    AssertEq(FsJoin(io.log), "wheel up 3|wheel down 1", "wheel goes through the io backend")
    AssertTrue(FsThrows(() => Input.Wheel("left", 1, io)), "bad dir throws")
}

Test_Fishing_FocusFailureWaitsAndLogsOnce() {
    t := FsMakeCfg()
    try {
        io := FsIO()
        logs := []
        st := SchedState()
        FishingTask(t.cfg, st, FsDeps(io, "", false, logs)).Run(SchedCtx())
        AssertEq(logs.Length, 1, "logged once")
        AssertTrue(io.clock >= 2000, "waited ~2 s before returning, clock=" io.clock)
        AssertEq(io.log.Length, 0, "no input sent")
        ; stop during the wait aborts it
        io2 := FsIO(1)
        ctx := SchedCtx()
        FishingTask(t.cfg, SchedState(), FsDeps(io2, "", false)).Run(ctx)
        AssertEq(io2.clock, 0, "stop aborts the focus wait")
        ; Sell: same behaviour
        io3 := FsIO()
        logs3 := []
        st3 := SchedState()
        st3.fishLoops := 15
        SellTask(t.cfg, st3, FsDeps(io3, "", false, logs3)).Run(SchedCtx())
        AssertEq(logs3.Length, 1, "sell logged once")
        AssertTrue(io3.clock >= 2000, "sell waited ~2 s")
        AssertEq(st3.fishLoops, 15, "sell did not run")
        AssertEq(io3.log.Length, 0, "sell sent no input")
    } finally {
        FsClean(t.dir)
    }
}

FsGrabThrows() {
    throw OSError("StripGrab: BitBlt failed")
}

Test_Fishing_CaptureThrowsAbandonsCatch() {
    t := FsMakeCfg()
    FsScreen.Install()
    try {
        io := FsIO()
        logs := []
        st := SchedState()
        FsCastScreen(io, 500, 0x3366CC, (x, y) => 0x202020)
        d := FsDeps(io, "", true, logs)
        d.grab := (x1, x2, ys, stride) => FsGrabThrows()
        task := FishingTask(t.cfg, st, d)
        AssertEq(task.CatchOnce(SchedCtx()), "error", "capture failure -> error")
        AssertEq(io.Count("click@1263,1177"), 0, "no minigame clicks")
        AssertEq(st.fishLoops, 0, "catch not counted")
        AssertEq(io.Count("click@1457,491"), 0, "no close click either")
        AssertEq(logs.Length, 1, "logged")
        task.CatchOnce(SchedCtx())
        AssertEq(logs.Length, 1, "logged once per task")
        ; Run waits before returning so the scheduler cannot spin hot
        io2 := FsIO()
        FsBiteScreen(io2, 500, 0x3366CC, (x, y) => 0x202020)
        d2 := FsDeps(io2)
        d2.grab := (x1, x2, ys, stride) => FsGrabThrows()
        FishingTask(t.cfg, SchedState(), d2).Run(SchedCtx())
        AssertTrue(io2.clock >= 2000 + 500, "Run waited after the error, clock=" io2.clock)
    } finally {
        FsScreen.Restore()
        FsClean(t.dir)
    }
}

Test_Fishing_AllBlackCaptureNeverClicks() {
    AssertEq(FishLogic.AllBlack([[0, 0], [0, 0]]), true, "all zero is black")
    AssertEq(FishLogic.AllBlack([[0, 0], [0, 1]]), false, "one non-zero is not black")
    t := FsMakeCfg()
    FsScreen.Install()
    try {
        io := FsIO()
        logs := []
        st := SchedState()
        ; strip reads pure black everywhere (bar sample is a real color)
        FsCastScreen(io, 500, 0x3366CC, (x, y) => 0x000000)
        task := FishingTask(t.cfg, st, FsDeps(io, "", true, logs))
        AssertEq(task.CatchOnce(SchedCtx()), "error", "black capture -> error")
        AssertEq(io.Count("click@1263,1177"), 0, "no clicks on a black strip")
        AssertEq(st.fishLoops, 0, "catch not counted")
        AssertEq(logs.Length, 1, "logged once")
        task.CatchOnce(SchedCtx())
        AssertEq(logs.Length, 1, "still logged once")
        ; advanced mode too
        t.cfg.Set("General.advancedFishing", 1)
        io2 := FsIO()
        FsBiteScreen(io2, 500, 0x3366CC, (x, y) => 0x000000)
        task2 := FishingTask(t.cfg, SchedState(), FsDeps(io2))
        AssertEq(task2.CatchOnce(SchedCtx()), "error", "advanced: black capture -> error")
        AssertEq(io2.Count("click@1263,1177"), 0, "advanced: no clicks")
    } finally {
        FsScreen.Restore()
        FsClean(t.dir)
    }
}
