#Requires AutoHotkey v2.0
; ---------------------------------------------------------------------------
; Fast transitions between tasks (live log 2026-11-23..24: fishing came back
; for the chat 3346 times, 0.48 s between its end and its next start; the
; tidy after a Biome Selector use took 3-6 s). Fakes from test_app /
; test_tidy / test_fishing / test_reel / test_questmatch / test_biomeitems.
; ---------------------------------------------------------------------------

; A Daily Quests task fake: counts its window reads (tidy) and _Close calls.
class TrDq extends AppFakeTask {
    __New() {
        super.__New("dailyquests", 5, false)
        this.ups := 0
        this.closes := 0
    }
    _Close(ctx) {
        this.closes++
        return 0
    }
    Leftovers() => [{up: () => (this.ups++, ""), close: (l, c) => 0}]
}

; A fishing fake that says whether it came back clean.
class TrFish extends TdTask {
    clean := false
    YieldedClean() => this.clean
}

; The shared screens' fake for the title gate: counts title reads.
class TrScreen extends TdScreen {
    titleUps := 0
    TitleItem() => {up: () => (this.titleUps++, ""), close: (l, c) => 0}
}

; ---- App ---------------------------------------------------------------------

Test_Transition_TaskEndKicksTheNextTickAtOnce() {
    fish := TdTask("fishing", 99)
    t := AppTestMake(Map("tasks", Map("fishing", fish)))
    t.app.Start()
    t.app._RunTask(fish)
    AssertEq(t.timers[t.timers.Length], -1, "a one-shot tick right after the task")
    AssertTrue(t.app._kickFn !== t.app._tickFn, "its own timer: the 250 ms period stays")
    ; that tick launches the next task
    t.app._kickFn.Call()
    AssertEq(t.launched.Length, 1, "next task launched by the kick")
}

Test_Transition_TicksNeverOverlap() {
    t := AppTestMake()
    t.app.Start()
    t.app._inTick := true                   ; another tick is running (a thread under this one)
    t.app.Tick()
    AssertEq(t.launched.Length, 0, "returned at once: no second launch")
    t.app._inTick := false
    t.app.Tick()
    AssertEq(t.launched.Length, 1, "the next one runs")
    AssertEq(t.app._inTick, false, "cleared after the tick")
    ; an error inside still clears it
    t2 := AppTestMake()
    t2.app.Start()
    t2.app.DefineProp("_TickBody", {Call: (self) => AppTestThrow("boom")})
    t2.app.Tick()
    AssertEq(t2.app._inTick, false, "cleared after an error")
}

Test_Transition_FishingAgainAfterACleanReturnSkipsTheShiftProbe() {
    fish := TrFish("fishing", 99)
    fish.clean := true
    inp := AppFakeShift()
    t := AppTestMake(Map("tasks", Map("fishing", fish), "input", inp))
    t.app.Start()
    t.app._RunTask(fish)
    AssertEq(inp.shifts.Length, 1, "first run of the session: probed")
    t.app._RunTask(fish)
    AssertEq(inp.shifts.Length, 1, "fishing again right after its clean return: no probe")
    ; not clean (a cast was cut): probed
    fish.clean := false
    t.app._RunTask(fish)
    t.app._RunTask(fish)
    AssertEq(inp.shifts.Length, 3, "not clean: both probed")
    ; another task in between: probed
    fish.clean := true
    q := TdTask("quests", 5)
    t.app._RunTask(fish)
    n := inp.shifts.Length
    t.app._RunTask(q)
    t.app._RunTask(fish)
    AssertEq(inp.shifts.Length, n + 2, "after another task: both probed")
    ; a pause in between: probed
    t.app._RunTask(fish)
    n := inp.shifts.Length
    t.app.Pause(), t.app.Resume()
    t.app._RunTask(fish)
    AssertEq(inp.shifts.Length, n + 1, "after a pause: probed")
    ; a preempted fishing run: probed
    pre := TrFish("fishing", 99, true, (self, ctx) => ctx.RequestPreempt())
    pre.clean := true
    t2 := AppTestMake(Map("tasks", Map("fishing", pre), "input", inp2 := AppFakeShift()))
    t2.app.Start()
    t2.app._RunTask(pre)
    t2.app._RunTask(pre)
    AssertEq(inp2.shifts.Length, 2, "preempted: probed again")
}

Test_Transition_LaunchSkipsReadsTheTidyJustMade() {
    dq := TrDq()
    scr := TrScreen()
    q := TdTask("quests", 5)
    fish := TrFish("fishing", 99)
    t := AppTestMake(Map("tasks", Map("fishing", fish, "quests", q, "dailyquests", dq), "tidyScreen", scr))
    t.app.Start()
    t.app._RunTask(q)
    AssertEq(dq.closes, 1, "first task of the session: Daily Quests checked at its start")
    AssertEq(dq.ups, 1, "and by the tidy after it")
    t.app._TitleGate()
    AssertEq(scr.titleUps, 0, "the tidy just read the title screen: the gate does not")
    t.app._RunTask(fish)
    AssertEq(dq.closes, 1, "the tidy just read the Daily Quests window: not read again")
    ; later than TidyFreshMs: read again
    t.clk.t += App.TidyFreshMs + 1
    t.app._TitleGate()
    AssertEq(scr.titleUps, 1, "stale: the gate reads")
    t.app._RunTask(q)
    AssertEq(dq.closes, 2, "stale: Daily Quests read at the start")
    ; only for the next launch
    t.app._RunTask(q)                       ; tidy fresh again; consumed by this launch
    t.app._freshAt["dq"] := t.clk.t
    t.app.Pause(), t.app.Resume()
    t.app._RunTask(q)
    AssertEq(dq.closes, 3, "a pause drops it")
    ; a skipped tidy (Roblox not in front) leaves nothing fresh
    t.app._freshAt := Map()
    t.rb.activeOk := false
    t.app._RunTask(q)
    t.rb.activeOk := true
    t.app._TitleGate()
    AssertEq(scr.titleUps, 2, "no tidy: the gate reads")
}

Test_Transition_CleanFishingTidyReadsNoDailyQuests() {
    dq := TrDq()
    fish := TrFish("fishing", 99)
    fish.clean := true
    t := AppTestMake(Map("tasks", Map("fishing", fish, "dailyquests", dq), "tidyScreen", TdScreen()))
    t.app.Start()
    t.app._RunTask(fish)
    n := dq.ups
    t.app._RunTask(fish)
    AssertEq(dq.ups, n, "clean return: the window is not read")
    AssertEq(dq.closes, 1, "nor at the next start (only the session's first)")
    fish.clean := false
    t.app._RunTask(fish)
    AssertEq(dq.ups, n + 1, "not clean: read")
}

; a fishing fake with the real Leftovers(settle) contract
class TrFishLeft extends AppFakeTask {
    __New() {
        super.__New("fishing", 99)
        this.settles := []
    }
    Leftovers(settle := false) {
        this.settles.Push(settle)
        return []
    }
}

Test_Transition_FishingCardSettledAfterAWalk() {
    fish := TrFishLeft()
    obby := TdTask("obby", 5), pot := TdTask("potions", 1)
    t := AppTestMake(Map("tasks", Map("fishing", fish, "obby", obby, "potions", pot)))
    t.app.Start()
    t.app._RunTask(pot)
    AssertEq(fish.settles[fish.settles.Length], false, "a task that did not walk: no settle")
    t.app._RunTask(obby)
    AssertEq(fish.settles[fish.settles.Length], true, "after a walk: settle")
    ; a fishing fake without the parameter still gets its plain call
    plain := TdTask("fishing", 99)
    plain.left := TdLeft("Fishing Failed card")
    t2 := AppTestMake(Map("tasks", Map("fishing", plain, "obby", obby2 := TdTask("obby", 5))))
    t2.app.Start()
    t2.app._RunTask(obby2)
    AssertEq(plain.left.closed, 1, "old contract: still read and closed")
}

; ---- ChatWatch: hover ahead ------------------------------------------------------

class TrHoverIO extends QmWaitIO {
    pos := {x: 0, y: 0}
    MoveTo(x, y) {
        this.pos := {x: x, y: y}
        super.MoveTo(x, y)
    }
    MousePos() => this.pos
}

Test_Transition_ChatHoverAheadWaitsOnlyTheRest() {
    clk := {t: 0}
    io := TrHoverIO()
    cw := ChatWatch({io: io, cal: QmCal(, Map("chat_rect", {x: 10, y: 20, w: 400, h: 200}))
        , ocr: (*) => (io.log.Push("ocr"), "x"), now: () => clk.t})
    AssertEq(cw.HoverAhead(), true, "hovered")
    AssertEq(io.log[1], "move 210,120", "over the chat")
    clk.t += 100
    cw.Check()
    AssertEq(io.log.Length, 3, "no second move")
    AssertEq(io.log[2], "wait 50", "only what is left of the 150 ms")
    AssertEq(io.log[3], "ocr", "then the read")
    ; hovered long ago: no wait at all
    clk.t += 10000
    io.log := []
    cw.HoverAhead()
    clk.t += 400
    cw.Check()
    AssertEq(io.log.Length, 2, "move, ocr (no wait)")
    ; the mouse left the chat meanwhile: the full hover
    clk.t += 10000
    io.log := []
    cw.HoverAhead()
    io.MoveTo(5, 5)
    clk.t += 100
    cw.Check()
    AssertEq(io.log[3], "move 210,120", "hovered again")
    AssertEq(io.log[4], "wait 150", "the whole wait")
    ; not due (chatPollSec): no hover at all
    io.log := []
    clk.t += 1000
    AssertEq(cw.HoverAhead(), false, "not due: nothing")
    AssertEq(io.log.Length, 0, "the mouse not moved")
    ; an io without MousePos: the full hover
    io2 := QmWaitIO()
    cw2 := ChatWatch({io: io2, cal: QmCal(, Map("chat_rect", {x: 10, y: 20, w: 400, h: 200}))
        , ocr: (*) => (io2.log.Push("ocr"), "x"), now: () => clk.t})
    cw2.HoverAhead()
    cw2.Check()
    AssertEq(io2.log[3], "wait 150", "no MousePos: the whole wait")
    ; idle mode: never moves the mouse
    ChatWatch.NoHover := true
    try {
        io3 := TrHoverIO()
        cw3 := ChatWatch({io: io3, cal: QmCal(, Map("chat_rect", {x: 10, y: 20, w: 400, h: 200})), ocr: (*) => "", now: () => clk.t})
        AssertEq(cw3.HoverAhead(), false, "idle mode: no hover")
        AssertEq(io3.log.Length, 0, "nothing moved")
    } finally {
        ChatWatch.NoHover := false
    }
}

class TrChat {
    hovers := 0
    checks := 0
    HoverAhead() => (this.hovers++, true)
    Check() => (this.checks++, [])
    Rebase() => 0
}

Test_Transition_AppHoversTheChatAheadAfterACleanFishingReturn() {
    fish := TrFish("fishing", 99)
    fish.clean := true
    chat := TrChat()
    cal := AppFakeCounter()
    cal.DefineProp("Rect", {Call: (self, id) => {x: 0, y: 0, w: 10, h: 10}})
    t := AppTestMake(Map("tasks", Map("fishing", fish), "calibrate", cal))
    t.app.chat := chat
    t.app.Start()
    t.app.state.chatDue := true
    t.app._RunTask(fish)
    AssertEq(chat.hovers, 1, "hovered before the tidy")
    fish.clean := false
    t.app._RunTask(fish)
    AssertEq(chat.hovers, 1, "not clean: no hover ahead")
    fish.clean := true
    t.app.state.chatDue := false
    t.app._RunTask(fish)
    AssertEq(chat.hovers, 1, "no chat read due: no hover ahead")
}

; ---- FishingTask: clean returns ---------------------------------------------------

; A catch card after every reel until its X is clicked; card reads logged.
class TrCardIO extends FsIO {
    card := false
    from := 0                       ; Index looks only after this log entry (TdPreemptAt on a later run)
    Index(entry) => this.IndexOf(entry, this.from + 1)
    Ocr(x, y, w, h, scale := 1) {
        if (x = 1000 && y = 440) {
            this.log.Push("ocr card")
            return this.card ? "Fish Caught! You've got Stonefish!" : ""
        }
        if (x = 1050)
            return this.card ? "" : "Fish"
        if (x = 1130)
            return this.card ? "" : "Fishing"
        return ""
    }
    ClickHere() {
        if (this.x = 1457 && this.y = 491)
            this.card := false
        super.ClickHere()
    }
}

Test_Transition_FishingCleanReturnSkipsCardReads() {
    t := FsMakeCfg()
    t.cfg.Set("General.legacyReel", 0)
    FsScreen.Install()
    try {
        st := SchedState()
        st.chatDue := true
        io := TrCardIO()
        sim := RlSim(io)
        FsScreen.fn := (x, y) => sim.Pixel(x, y)
        ; the card comes up once the reel ends: after the first reel click
        io.DefineProp("Wait", {Call: (self, ms, ctx := "") => (self.Count("click@1263,1177") && !self.Count("click@1457,491") && (self.card := true), FsIO.Prototype.Wait.Call(self, ms, ctx))})
        task := FishingTask(t.cfg, st, FsDeps(io))
        task.Run(SchedCtx())
        AssertEq(st.fishLoops, 1, "one catch, then back for the chat")
        AssertEq(task.YieldedClean(), true, "clean: the card was seen closing")
        n := io.Count("ocr card")
        AssertEq(task.Leftovers()[1].up.Call(), "", "the tidy: no card")
        AssertEq(io.Count("ocr card"), n, "not read")
        ; the next run casts without a leftover read first
        start := io.log.Length
        io.from := start
        task.Run(TdPreemptAt(io, "click@1161,1124"))
        cast := io.IndexOf("click@1161,1124", start + 1)
        AssertTrue(cast > 0, "cast")
        reads := 0
        for i, e in io.log
            reads += (i > start && i < cast && e = "ocr card") ? 1 : 0
        AssertEq(reads, 0, "no card read before the cast")
        AssertEq(task.YieldedClean(), false, "cut mid-cast: not clean")
        n := io.Count("ocr card")
        task.Leftovers()[1].up.Call()
        AssertEq(io.Count("ocr card"), n + 1, "not clean: the tidy reads the card")
        ; App.Start: a new session reads everything again
        task._yieldClean := true
        task.Reset()
        AssertEq(task.YieldedClean(), false, "Reset clears it")
    } finally {
        FsScreen.Restore()
        FsClean(t.dir)
    }
}

Test_Transition_FishingCardSettlesAfterAWalk() {
    t := FsMakeCfg()
    try {
        io := TrCardIO()
        task := FishingTask(t.cfg, SchedState(), FsDeps(io))
        lo := task.Leftovers()
        lo[1].up.Call(), lo[1].up.Call()
        AssertEq(io.Count("ocr card"), 2, "no settle: read every time")
        io.card := true
        AssertEq(task.Leftovers(true)[1].up.Call(), "Fish Caught card", "a card up: seen, not settled")
        io.card := false
        task.Leftovers(true)[1].up.Call()
        n := io.Count("ocr card")
        AssertEq(task.Leftovers()[1].up.Call(), "", "settled: none")
        AssertEq(io.Count("ocr card"), n, "settled: not read again")
        AssertEq(task.Leftovers()[2].up.Call(), "", "the frozen card is still read")
    } finally {
        FsClean(t.dir)
    }
}

; ---- Biome Selector: closes by itself after Confirm -------------------------------

Test_Transition_SelectorLeftToCloseByItselfAfterConfirm() {
    m := BiMake(Map("BiomeItems.biomeSelector", 1, "BiomeItems.selectorDrive", "Abyss Curse Drive"), ["Biome Selector"]
        , ["Select a biome using a Drive"])
    AssertEq(m.t.Run(SchedCtx()), 1, "used")
    AssertEq(m.ocr.confirmed, "Abyss Curse Drive", "confirmed")
    ; the game: the window stays up after Confirm until the new biome starts
    m.ocr.selector := true, m.ocr.barBlank := true, m.ocr.rowsBlank := true, m.ocr.btnBlank := true
    m.ocr.DefineProp("Read", {Call: TrSelectorRead})
    t0 := m.ocr.t
    m.ocr.goneAt := t0 + 3000
    strips := m.ocr.strips
    nlog := m.io.log.Length
    logs := []
    Tidy.Run("biomeitems", m.t.Leftovers(), SchedCtx(), (s) => logs.Push(s))
    AssertEq(m.ocr.selector, false, "gone")
    AssertEq(logs.Length, 1, "one line")
    AssertEq(logs[1], "tidy after biomeitems: closed the Biome Selector list", "wording")
    AssertEq(m.io.log.Length, nlog, "nothing clicked or pressed")
    AssertTrue(m.ocr.t - t0 <= 3000 + BiomeItemsTask.SelfPollMs, "done within a poll of it going (" (m.ocr.t - t0) " ms)")
    AssertTrue(m.ocr.strips - strips <= 30, "no scan of the window (" (m.ocr.strips - strips) " strip reads)")
    AssertEq(BiSaid(m, "could not be placed"), false, "no 'could not be placed'")
}

; BiOcr.Read with the window going by itself at goneAt (ms of its clock)
TrSelectorRead(self, x, y, w, h) {
    if (self.HasOwnProp("goneAt") && self.goneAt && self.t >= self.goneAt)
        self.selector := false, self.goneAt := 0
    if (x = 500 && w = 600 && self.selector && h >= 400)
        return "Abyss Curse Drive"              ; the window still reads while it waits for the biome
    return BiOcr.Prototype.Read.Call(self, x, y, w, h)
}

Test_Transition_SelectorStillUpLongAfterConfirmUsesItsX() {
    m := BiMake(Map("BiomeItems.biomeSelector", 1, "BiomeItems.selectorDrive", "Abyss Curse Drive"), ["Biome Selector"]
        , ["Select a biome using a Drive"])
    AssertEq(m.t.Run(SchedCtx()), 1, "used")
    m.ocr.selector := true                  ; never goes by itself
    m.clk.t += BiomeItemsTask.SelfCloseMs + 1
    AssertEq(m.t.Leftovers()[1].close.Call("", SchedCtx()), 1, "closed")
    AssertTrue(m.io.Index("move 1318,323") > 0, "by its X")
    ; up right after Confirm and staying up: polled SelfCloseMs, then its X
    m2 := BiMake(Map("BiomeItems.biomeSelector", 1, "BiomeItems.selectorDrive", "Abyss Curse Drive"), ["Biome Selector"]
        , ["Select a biome using a Drive"])
    m2.t.Run(SchedCtx())
    m2.ocr.selector := true
    t0 := m2.ocr.t
    AssertEq(m2.t.Leftovers()[1].close.Call("", SchedCtx()), 1, "closed")
    AssertTrue(m2.ocr.t - t0 >= BiomeItemsTask.SelfCloseMs, "waited for it first")
    AssertTrue(m2.io.Index("move 1318,323") > 0, "then its X")
    ; halted while waiting: -1, nothing sent
    m3 := BiMake(Map("BiomeItems.biomeSelector", 1, "BiomeItems.selectorDrive", "Abyss Curse Drive"), ["Biome Selector"]
        , ["Select a biome using a Drive"])
    m3.t.Run(SchedCtx())
    m3.ocr.selector := true
    c := SchedCtx()
    c.Stop()
    n := m3.io.log.Length
    AssertEq(m3.t._TidySelector(c), -1, "halted")
    AssertEq(m3.io.log.Length, n, "nothing sent")
}
