#Requires AutoHotkey v2.0
; Tests for lib\App.ahk (Task 14b wiring). Everything is faked: no timers,
; no hotkeys, no windows, no Roblox, no HTTP. Launch is captured so a test
; decides when a task "thread" runs; Tick() is called by hand.
#Include ..\lib\App.ahk

; ---- fakes (names must not start with Test_) -------------------------------

class AppFakeCfg {
    __New(vals := "") {
        this.vals := Map()
        this.vals.CaseSense := "Off"
        if (vals is Map)
            for k, v in vals
                this.vals[k] := v
        this.biomes := Map("biomes", [Map("name", "GLITCHED", "rare", 1, "potions", []), Map("name", "NORMAL", "rare", 0)])
        this.potionsData := Map("potions", [Map("name", "Lucky Potion", "desc", "1 minute of [Lucky]", "locked", false, "perBiome", 5, "perDay", 50, "perRun", 1)])
    }
    ; Simulates a Biomes & Potions save that changed something.
    Bump() {
        p := this.potionsData["potions"][1]
        p["perDay"] := p["perDay"] + 1
    }
    Get(path, default := "") => this.vals.Has(path) ? this.vals[path] : default
    Set(path, v) => this.vals[path] := v
    Data(name) => (name = "biomes") ? this.biomes : (name = "potions") ? this.potionsData : (name = "routes" && this.HasOwnProp("routes")) ? this.routes : Map()
    Webhooks() => []
}

class AppFakeTask {
    __New(name, priority, can := true, runFn := "") {
        this.name := name
        this.priority := priority
        this.can := can
        this.runFn := runFn
        this.runs := 0
        this.busySeen := []
    }
    CanRun(state) => this.can
    Run(ctx) {
        this.runs++
        this.busySeen.Push(AppTestState.busy)
        if IsObject(this.runFn)
            this.runFn.Call(this, ctx)
    }
}

; The state object the current test uses (read inside fake Run).
class AppTestState {
    static busy := ""
}

class AppFakeMerchant extends AppFakeTask {
    __New() {
        super.__New("merchant", 3, false)
        this.events := []
        this.notified := []
    }
    OnLogEvent(ev) => this.events.Push(ev)
    Notify(name) => this.notified.Push(name)
}

class AppFakePotions {
    __New(safety) {
        this.name := "potions"
        this.priority := 1
        this.safety := safety
        this.pending := ""
        this.runs := 0
        this.runFn := ""
    }
    Queue(biome, ts) => this.pending := {biome: biome, ts: ts}
    CanRun(state) => IsObject(this.pending)
    Run(ctx) {
        this.runs++
        this.pending := ""
        if IsObject(this.runFn)
            this.runFn.Call(this, ctx)
    }
}

class AppFakeUi {
    __New() {
        this.logs := []
        this.status := ""
    }
    Log(t) => this.logs.Push(t)
    SetStatus(st, task, biome, rare, up, loops) {
        this.status := {state: st, task: task, biome: biome, rare: rare, up: up, loops: loops}
    }
}

class AppFakeWh {
    __New() {
        this.sent := []
        this.titles := []
        this.flushes := 0
        this.drains := 0
    }
    Send(ev, title, desc, color, opts := "") => (this.sent.Push(ev), this.titles.Push(title))
    Broadcast(title, desc, color, opts := "") => (this.sent.Push("broadcast"), this.titles.Push(title))
    Flush() => this.flushes++
    Drain(ms := 0) => this.drains++
    Pending() => 0
}

class AppFakeLw {
    __New() {
        this.queue := []
        this.polls := 0
    }
    Push(ev) => this.queue.Push(ev)
    Poll() {
        this.polls++
        out := this.queue
        this.queue := []
        return out
    }
}

class AppFakeBe {
    __New() {
        this.handled := []
    }
    Handle(ev) => this.handled.Push(ev)
}

class AppFakeChat {
    __New(app := "") {
        this.app := app
        this.checks := 0
        this.duringTask := 0
    }
    Check() {
        this.checks++
        if (IsObject(this.app) && this.app.TaskRunning())
            this.duringTask++
        return []
    }
}

class AppFakeRoblox {
    __New() {
        this.win := 1
        this.fs := true
        this.focusOk := true
        this.activeOk := true
        this.focusActivates := true
        this.focusCalls := 0
        this.duringFocus := ""       ; callable run inside Focus (hotkey/GUI event during WinWaitActive)
        this.afterSleep := ""        ; callable run on App's settle sleep (the dashboard's minimize ending)
    }
    Hwnd() => this.win
    ClientOk() => !this.win ? "missing" : this.fs ? "ok" : "notfs"
    IsActive() => this.win && this.activeOk
    Focus(t := 2) {
        this.focusCalls++
        if IsObject(this.duringFocus)
            this.duringFocus.Call()
        if (this.focusOk && this.focusActivates)
            this.activeOk := true
        return this.focusOk
    }
}

class AppFakeCounter {
    __New() {
        this.cancels := 0
        this.releases := 0
        this.triggers := []
    }
    CancelAll() => this.cancels++
    ReleaseAll(io := "") => this.releases++
    Trigger(reason) => this.triggers.Push(reason)
}

; input fake that records Input.ShiftLock calls (App turns shift lock off
; before a task and on stop); fails: ShiftLock throws; stuck: never
; confirmed (returns false)
class AppFakeShift extends AppFakeCounter {
    shifts := []
    fails := false
    stuck := false
    ShiftLock(on, io := "", ctx := "") {
        this.shifts.Push(on ? 1 : 0)
        if this.fails
            throw Error("no io")
        return !this.stuck
    }
}

AppTestThrow(msg) {
    throw Error(msg)
}

AppTestEv(type, name, ts, live) {
    ev := Map("type", type, "name", name, "ts", ts, "live", live ? true : false)
    return ev
}

; -> {app, clk, ui, wh, lw, rb, clip, input, launched, timers, tasks Map,
;     builds (safety factory calls)}. opts Map: tasks (Map name -> task),
;     be ("real" = real BiomeEvents with fakes), cfg values.
AppTestMake(opts := "") {
    o := (opts is Map) ? opts : Map()
    t := {clk: {t: 100000}, ui: AppFakeUi(), wh: AppFakeWh(), lw: AppFakeLw(), rb: AppFakeRoblox()
        , clip: AppFakeCounter(), input: AppFakeCounter(), launched: [], timers: [], builds: 0, be: ""}
    t.cfg := o.Has("cfgObj") ? o["cfgObj"] : AppFakeCfg(o.Has("cfgVals") ? o["cfgVals"] : Map("General.sound", 0, "Medal.onRareBiome", 0))
    if o.Has("whObj")
        t.wh := o["whObj"]
    if o.Has("input")
        t.input := o["input"]
    tasks := o.Has("tasks") ? o["tasks"] : Map("fishing", AppFakeTask("fishing", 99))
    t.tasks := tasks
    d := Map("hiRes", false, "cfg", t.cfg, "root", A_Temp, "now", () => t.clk.t, "ui", [t.ui], "wh", t.wh
        , "logWatch", t.lw, "roblox", t.rb, "clip", t.clip, "input", t.input
        , "launch", (fn) => t.launched.Push(fn)
        , "timer", (fn, ms) => t.timers.Push(ms)
        , "tasks", tasks
        , "chatWatch", ""
        , "calibrate", AppFakeCounter()
        , "safetyFactory", () => (t.builds++, {id: t.builds})
        , "potionsFactory", (s) => AppFakePotions(s)
        , "shotFn", () => ""
        , "soundFn", (s) => 0
        , "hadLogDir", ""
        , "recordRespawn", (ctx) => (t.respawns := (t.HasOwnProp("respawns") ? t.respawns : 0) + 1, true)
        , "sleep", (ms) => (IsObject(t.rb.afterSleep) ? t.rb.afterSleep.Call() : 0))
    if (o.Has("be") && o["be"] = "fake") {
        t.be := AppFakeBe()
        d["biomeEvents"] := t.be
    }
    for k in ["safetyFactory", "logWatchFactory", "calibrate", "recordRoute", "walkRoute", "recordRespawn", "creditsVerify", "splash", "tidyScreen"]
        if o.Has(k)
            d[k] := o[k]
    if o.Has("defaultTasks")
        d.Delete("tasks")                       ; App builds its own task set
    if o.Has("sync")
        d["launch"] := (fn) => (t.launched.Push(fn), fn.Call())
    t.app := App(d)
    AppTestState.busy := ""
    return t
}

; Runs every captured launch (oldest first) and clears the list.
AppTestRunLaunched(t) {
    while (t.launched.Length) {
        fn := t.launched.RemoveAt(1)
        fn.Call()
    }
}

; ---- tests -----------------------------------------------------------------

Test_App_SchedStateDeclaresBiomeAndRareTs() {
    s := SchedState()
    AssertEq(s.biome, "", "biome declared")
    AssertEq(s.rareTs, "", "rareTs declared")
}

Test_App_BusySetAndClearedAroundRun() {
    fish := AppFakeTask("fishing", 99, true, (self, ctx) => AppTestState.busy := t.app.state.busy)
    t := AppTestMake(Map("tasks", Map("fishing", fish)))
    t.app.Start()
    t.app.Tick()
    AssertEq(t.launched.Length, 1, "one launch")
    AssertEq(t.app.TaskRunning(), true, "running flag set at launch")
    AppTestRunLaunched(t)
    AssertEq(fish.runs, 1, "fishing ran")
    AssertEq(AppTestState.busy, "fishing", "busy = task name inside Run")
    AssertEq(t.app.state.busy, "", "busy cleared after Run")
    AssertEq(t.app.TaskRunning(), false, "running flag cleared")
}

Test_App_BusyClearedAndMarkRunOnThrow() {
    bad := AppFakeTask("quests", 5, true, (self, ctx) => (AppTestState.busy := t.app.state.busy, AppTestThrow("boom")))
    t := AppTestMake(Map("tasks", Map("quests", bad, "fishing", AppFakeTask("fishing", 99))))
    t.app.Start()
    t.app.Tick()
    AppTestRunLaunched(t)
    AssertEq(bad.runs, 1, "quests ran")
    AssertEq(AppTestState.busy, "quests", "busy set inside Run")
    AssertEq(t.app.state.busy, "", "busy cleared after throw")
    AssertEq(t.app.TaskRunning(), false, "not running after throw")
    AssertEq(t.app.state.lastRun.Has("quests") && t.app.state.lastRun["quests"] = t.clk.t, true, "MarkRun even on throw")
    found := false
    for ev in t.wh.sent
        found := found || ev = "errors"
    AssertTrue(found, "errors webhook on throw")
    ; error hold: the next tick does not relaunch at once
    t.app.Tick()
    AssertEq(t.launched.Length, 0, "held after a throw")
    t.clk.t += App.ErrorHoldMs
    t.app.Tick()
    AssertEq(t.launched.Length, 1, "relaunch after the hold")
}

Test_App_MarkRunCalledAfterRun() {
    q := AppFakeTask("quests", 5)
    t := AppTestMake(Map("tasks", Map("quests", q, "fishing", AppFakeTask("fishing", 99))))
    t.app.Start()
    t.app.Tick()
    AppTestRunLaunched(t)
    AssertEq(q.runs, 1, "quests ran first")
    AssertEq(t.app.state.lastRun["quests"], t.clk.t, "MarkRun stamped quests")
    ; quests now gated by the interval -> fishing next
    t.app.Tick()
    AssertEq(t.launched.Length, 1, "next launch")
    AppTestRunLaunched(t)
    AssertEq(q.runs, 1, "quests not rerun inside interval")
    AssertEq(t.tasks["fishing"].runs, 1, "fishing ran")
}

Test_App_PreemptWhenPotionsDuringFishing() {
    seen := {pre: false}
    fish := AppFakeTask("fishing", 99, true, AppTestFishRun.Bind(seen))
    t := AppTestMake(Map("tasks", Map("fishing", fish)))
    seen.t := t
    t.app.Start()
    t.app.Tick()                       ; first poll (empty) + launch fishing
    AppTestRunLaunched(t)
    AssertEq(seen.pre, true, "preempt requested while fishing ran")
    AssertEq(t.app.state.rareActive, true, "BiomeEvents marked rare")
    AssertEq(t.app.potions.CanRun(t.app.state), true, "potions queued via BiomeEvents proxy")
    t.app.potions.runFn := (self, ctx) => self.preInside := ctx.IsPreempted()
    t.app.Tick()
    AssertEq(t.launched.Length, 1, "potions launched")
    AppTestRunLaunched(t)
    AssertEq(t.app.potions.runs, 1, "potions ran")
    AssertEq(t.app.potions.preInside, false, "preempt cleared before the next task ran")
}

; Fishing Run: a live rare biome arrives; the next scheduler tick (it
; interrupts the running task in the real app) must request a preempt.
AppTestFishRun(seen, self, ctx) {
    t := seen.t
    AssertEq(ctx.ShouldStop(), false, "fishing starts unpreempted")
    t.lw.Push(AppTestEv("biome", "GLITCHED", "2026-10-25T10:00:00", true))
    t.clk.t += App.LogPollMs
    t.app.Tick()
    seen.pre := ctx.IsPreempted()
}

Test_App_ReentrancyGuard() {
    fish := AppFakeTask("fishing", 99, true, (self, ctx) => (t.app.Tick(), t.app.Tick()))
    sell := AppFakeTask("sell", 6, false)
    t := AppTestMake(Map("tasks", Map("fishing", fish, "sell", sell)))
    t.app.Start()
    t.app.Tick()
    AssertEq(t.launched.Length, 1, "one launch")
    t.app.Tick()
    AssertEq(t.launched.Length, 1, "no second launch while one is pending")
    fn := t.launched.RemoveAt(1)
    fn.Call()                           ; Run ticks twice inside
    AssertEq(t.launched.Length, 0, "no launch from ticks inside Run")
    AssertEq(fish.runs, 1, "fishing ran once")
}

Test_App_StopPathStopsCancelsReleases() {
    t := AppTestMake()
    t.app.Start()
    AssertEq(t.timers.Length, 1, "tick timer started")
    AssertEq(t.timers[1], App.TickMs, "250 ms tick")
    t.app.Stop()
    AssertEq(t.app.ctx.IsStopped(), true, "ctx stopped")
    AssertEq(t.clip.cancels, 1, "Clip.CancelAll")
    AssertEq(t.input.releases, 1, "Input.ReleaseAll")
    starts := 0, bcast := 0
    for ev in t.wh.sent {
        starts += (ev = "startstop")
        bcast += (ev = "broadcast")
    }
    AssertEq(starts, 1, "startstop only on stop (start is a broadcast)")
    AssertEq(bcast, 1, "start announcement broadcast once")
    AssertEq(t.ui.status.state, "Stopped", "status stopped")
    t.app.Tick()
    AssertEq(t.wh.drains, 1, "Drain after stop")
    AssertEq(t.timers[t.timers.Length], 0, "timer off after stop")
    AssertEq(t.launched.Length, 0, "nothing launched after stop")
}

Test_App_StopTurnsShiftLockOffWhenRobloxIsActive() {
    inp := AppFakeShift()
    t := AppTestMake(Map("input", inp))
    t.app.Start()
    t.app.Stop()
    AssertEq(inp.shifts.Length, 1, "shift lock off on stop")
    AssertEq(inp.shifts[1], 0, "off, not on")
    ; Roblox in the background: no probe, no key (the user is in another window)
    inp2 := AppFakeShift()
    t2 := AppTestMake(Map("input", inp2))
    t2.app.Start()
    t2.rb.activeOk := false
    t2.app.Stop()
    AssertEq(inp2.shifts.Length, 0, "Roblox not in front: shift lock left alone")
    ; a throw in it does not break Stop
    inp3 := AppFakeShift()
    inp3.fails := true
    t3 := AppTestMake(Map("input", inp3))
    t3.app.Start()
    t3.app.Stop()
    AssertEq(t3.app._started, false, "stopped despite the throw")
    AssertEq(t3.input.releases, 1, "keys still released")
}

Test_App_TaskStartsWithShiftLockOff() {
    inp := AppFakeShift()
    fish := AppFakeTask("fishing", 99, true, (self, ctx) => (self.shiftsSeen := inp.shifts.Length))
    t := AppTestMake(Map("input", inp, "tasks", Map("fishing", fish)))
    t.app.Start()
    t.app._RunTask(fish)
    AssertEq(fish.shiftsSeen, 1, "shift lock turned off before the task's first click")
    AssertEq(inp.shifts[1], 0, "off")
    ; Roblox not in front: nothing sent
    inp2 := AppFakeShift()
    q := AppFakeTask("quests", 5)
    t2 := AppTestMake(Map("input", inp2, "tasks", Map("quests", q)))
    t2.app.Start()
    t2.rb.activeOk := false
    t2.app._RunTask(q)
    AssertEq(inp2.shifts.Length, 0, "Roblox not in front: shift lock left alone")
    AssertEq(q.runs, 1, "the task still ran")
}

; shift lock never confirmed off: one more try, then the task is skipped
; (with it on every click lands at the screen centre: live 2026-11-02 the
; Donation purchase prompt)
Test_App_TaskSkippedWhileShiftLockStaysOn() {
    inp := AppFakeShift()
    inp.stuck := true
    fish := AppFakeTask("fishing", 99)
    t := AppTestMake(Map("input", inp, "tasks", Map("fishing", fish)))
    t.app.Start()
    t.app._RunTask(fish)
    AssertEq(fish.runs, 0, "never run: no click")
    AssertEq(inp.shifts.Length, 2, "off tried once more first")
    found := false
    for l in t.ui.logs
        found := found || InStr(l, "Fishing: shift lock may still be on - skipped (no click)")
    AssertTrue(found, "logged")
    AssertEq(t.app.state.busy, "", "not left busy")
    inp.stuck := false
    t.app._RunTask(fish)
    AssertEq(fish.runs, 1, "confirmed off: runs")
}

Test_App_StopWhileTaskRunningWaitsForIt() {
    fish := AppFakeTask("fishing", 99, true, (self, ctx) => (t.app.Stop(), t.app.Tick(), self.stopSeen := ctx.ShouldStop()))
    t := AppTestMake(Map("tasks", Map("fishing", fish)))
    t.app.Start()
    t.app.Tick()
    AppTestRunLaunched(t)
    AssertEq(fish.stopSeen, true, "task sees stop")
    AssertEq(t.wh.drains, 0, "no drain while the task still runs")
    t.app.Tick()
    AssertEq(t.wh.drains, 1, "drain once it ended")
}

Test_App_PotionsChangedRebuildDeferredWhileRunning() {
    t := AppTestMake()
    AssertEq(t.builds, 1, "one PotionSafety at start")
    t.cfg.Bump()
    t.app.OnPotionsChanged()
    AssertEq(t.builds, 2, "idle: rebuilt at once")
    p := t.app.potions
    AssertEq(p.safety.id, 2, "new task holds the new safety")
    p.runFn := (self, ctx) => (t.cfg.Bump(), t.app.OnPotionsChanged(), self.buildsInside := t.builds)
    p.Queue("GLITCHED", "ts1")
    t.app.state.rareActive := true
    t.app.Start()
    t.app.Tick()
    AppTestRunLaunched(t)
    AssertEq(p.runs, 1, "potions ran")
    AssertEq(p.buildsInside, 2, "no rebuild while potions running")
    AssertEq(t.builds, 3, "rebuilt when the potion task ended")
    AssertTrue(t.app.potions !== p, "task replaced")
}

Test_App_PotionsChangedKeepsPendingEvent() {
    t := AppTestMake(Map("be", "fake"))
    t.app._proxy.Queue("GLITCHED", "ts9")      ; as BiomeEvents does
    old := t.app.potions
    AssertEq(old.CanRun(t.app.state), true, "pending")
    t.cfg.Bump()
    t.app.OnPotionsChanged()
    AssertTrue(t.app.potions !== old, "rebuilt while only pending")
    AssertEq(t.app.potions.CanRun(t.app.state), true, "pending event re-queued on the new task")
    AssertEq(t.app.potions.pending.ts, "ts9", "same event key")
}

Test_App_PotionSafetyFailureDisablesPotions() {
    t := AppTestMake()
    t.app.safetyFactory := () => (t.builds++, AppTestThrow("disk"))
    t.cfg.Bump()
    t.app.OnPotionsChanged()
    AssertEq(t.app.potions, "", "no potion task when safety cannot load")
    threw := false
    try t.app._proxy.Queue("GLITCHED", "ts1")
    catch
        threw := true
    AssertEq(threw, true, "queue refused (BiomeEvents logs it)")
}

Test_App_LogEventRouting() {
    m := AppFakeMerchant()
    t := AppTestMake(Map("be", "fake", "tasks", Map("merchant", m, "fishing", AppFakeTask("fishing", 99))))
    t.lw.Push(AppTestEv("biome", "NORMAL", "t0", false))
    t.lw.Push(AppTestEv("biome", "GLITCHED", "t1", true))
    t.lw.Push(AppTestEv("aura", "Glock", "t2", true))
    t.lw.Push(AppTestEv("merchant", "Mari", "t3", false))
    t.lw.Push(AppTestEv("merchant", "Jester", "t4", true))
    n := t.app.PollLogs()
    AssertEq(n, 5, "all events routed")
    AssertEq(t.be.handled.Length, 3, "biome + aura events to BiomeEvents (it filters live)")
    AssertEq(t.be.handled[1]["live"], false, "non-live biome passed for state")
    AssertEq(m.events.Length, 1, "only the live merchant event")
    AssertEq(m.events[1]["name"], "Jester", "live merchant")
}

Test_App_RealBiomeEventsNonLiveDoesNotQueue() {
    t := AppTestMake()
    t.lw.Push(AppTestEv("biome", "GLITCHED", "t1", false))
    t.app.PollLogs()
    AssertEq(t.app.state.biome, "GLITCHED", "state.biome set by backfill")
    AssertEq(t.app.state.rareActive, false, "backfill not rare-active")
    AssertEq(t.app.potions.CanRun(t.app.state), false, "backfill never queues potions")
    t.lw.Push(AppTestEv("biome", "GLITCHED", "t2", true))
    t.app.PollLogs()
    AssertEq(t.app.state.rareTs, "t2", "live rare sets rareTs")
    AssertEq(t.app.potions.CanRun(t.app.state), true, "live rare queues potions")
}

; MinionsTask's biome dep: the log polled first (no Tick runs mid-task)
Test_App_BiomeNowPollsTheLog() {
    t := AppTestMake()
    t.lw.Push(AppTestEv("biome", "SNOWY", "t1", true))
    AssertEq(t.app._BiomeNow(), "SNOWY", "read from the log")
    t.lw.Push(AppTestEv("biome", "PUMPKIN MOON", "t2", true))
    AssertEq(t.app._BiomeNow(), "PUMPKIN MOON", "the change seen mid-task")
}

Test_App_PollGuardNoReentry() {
    t := AppTestMake()
    t.app._polling := true
    t.lw.Push(AppTestEv("biome", "NORMAL", "t0", true))
    AssertEq(t.app.PollLogs(), 0, "re-entrant poll skipped")
    AssertEq(t.lw.polls, 0, "LogWatch not touched")
}

Test_App_ChatWatchOnlyBetweenTasks() {
    fish := AppFakeTask("fishing", 99, true, (self, ctx) => (t.clk.t += 10000, t.app.Tick(), t.app.Tick()))
    t := AppTestMake(Map("tasks", Map("fishing", fish)))
    chat := AppFakeChat(t.app)
    t.app.chat := chat
    t.app.Start()
    t.app.Tick()
    AssertEq(chat.checks, 1, "checked before launching")
    AppTestRunLaunched(t)
    AssertEq(chat.duringTask, 0, "never while a task runs")
    AssertEq(chat.checks, 1, "ticks inside Run did not check")
    t.app.Pause()
    t.app.Tick()
    AssertEq(chat.checks, 1, "not while paused")
    t.cfg.Set("merchant.enabled", 0)
    t.app.Resume()
    t.app.Tick()
    AssertEq(chat.checks, 1, "not when merchants are off")
}

Test_App_ChatFoundNotifiesMerchant() {
    m := AppFakeMerchant()
    t := AppTestMake(Map("tasks", Map("merchant", m)))
    t.app._OnChatMerchant("Mari")
    AssertEq(m.notified.Length, 1, "Notify called")
    AssertEq(m.notified[1], "Mari", "name passed")
}

Test_App_FlushEveryTick() {
    t := AppTestMake()
    t.app.Start()
    t.app.Tick()
    t.app.Pause()
    t.app.Tick()
    t.app.Tick()
    AssertEq(t.wh.flushes, 3, "Flush on every tick, paused too")
    AssertEq(t.lw.polls, 1, "LogWatch polled at most once per second")
    t.clk.t += App.LogPollMs
    t.app.Tick()
    AssertEq(t.lw.polls, 2, "polled again after 1 s")
}

; live 2026-11-10: log reads / webhook posts on the tick held the walk's key
; down and the sell route overshot the Fisher
Test_App_NoLogReadOrWebhookWhileARouteWalks() {
    t := AppTestMake()
    t.app.Start()
    t.app.Tick()
    f := t.wh.flushes, p := t.lw.polls
    t.clk.t += App.LogPollMs
    Input.InRoute := true
    try {
        t.app.Tick()
        AssertEq(t.wh.flushes, f, "no webhook post mid-walk")
        AssertEq(t.lw.polls, p, "no log read mid-walk")
    } finally {
        Input.InRoute := false
    }
    t.app.Tick()
    AssertEq(t.wh.flushes, f + 1, "posted after the walk")
    AssertEq(t.lw.polls, p + 1, "read after the walk")
}

Test_App_NotFullscreenPausesWithStatus() {
    t := AppTestMake()
    t.rb.fs := false
    t.app.Start()
    AssertEq(t.ui.status.state, "Paused", "paused at start")
    AssertTrue(InStr(t.ui.status.task, "fullscreen"), "status names the problem")
    t.app.Tick()
    AssertEq(t.launched.Length, 0, "nothing launched")
    t.app.Resume()
    AssertEq(t.app.ctx.IsPaused(), true, "resume refused while still not fullscreen")
    t.rb.fs := true
    t.app.Resume()
    AssertEq(t.app.ctx.IsPaused(), false, "resumed once fullscreen")
    t.app.Tick()
    AssertEq(t.launched.Length, 1, "runs after resume")
}

Test_App_MissingAtStartPauses() {
    t := AppTestMake()
    t.rb.win := 0
    t.app.Start()
    AssertEq(t.ui.status.state, "Paused", "paused")
    AssertTrue(InStr(t.ui.status.task, "Roblox not found"), "clear status")
}

Test_App_NotFullscreenMidTaskPauses() {
    fish := AppFakeTask("fishing", 99, true, (self, ctx) => (t.rb.fs := false, t.app.Tick(), self.stop := ctx.ShouldStop()))
    t := AppTestMake(Map("tasks", Map("fishing", fish)))
    t.app.Start()
    t.app.Tick()
    AppTestRunLaunched(t)
    AssertEq(fish.stop, true, "task told to stop")
    AssertEq(t.ui.status.state, "Paused", "paused")
}

Test_App_MissingWindowRunsOnlyRecovery() {
    rec := AppFakeTask("recovery", 2, true)
    t := AppTestMake(Map("tasks", Map("recovery", rec, "fishing", AppFakeTask("fishing", 99))))
    t.app.Start()
    t.rb.win := 0
    t.app.potions.Queue("GLITCHED", "ts")
    t.app.Tick()
    AppTestRunLaunched(t)
    AssertEq(rec.runs, 1, "recovery ran although potions were pending")
    AssertEq(t.app.potions.runs, 0, "potions not run without a window")
    rec.can := false
    t.app.Tick()
    AssertEq(t.launched.Length, 0, "nothing else runs without a window")
    AssertEq(t.ui.status.task, "Waiting for Roblox", "status while waiting")
}

Test_App_MissingWindowRecoveryOffPauses() {
    t := AppTestMake(Map("cfgVals", Map("recovery.enabled", 0)))
    t.app.Start()
    t.rb.win := 0
    t.app.Tick()
    AssertEq(t.app.ctx.IsPaused(), true, "paused")
    AssertTrue(InStr(t.ui.status.task, "Roblox not found"), "status")
}

Test_App_FocusFailureDoesNotLaunch() {
    t := AppTestMake()
    t.rb.focusOk := false
    t.app.Start()
    t.app.Tick()
    AssertEq(t.launched.Length, 0, "no launch without focus")
    AssertEq(t.ui.status.task, "Waiting for Roblox focus", "status")
}

Test_App_PauseResumeAndStatus() {
    t := AppTestMake()
    t.app.Start()
    t.app.Tick()
    AssertEq(t.ui.status.state, "Running", "running")
    AssertEq(t.ui.status.task, "Fishing", "task shown")
    AppTestRunLaunched(t)
    t.app.TogglePause()
    AssertEq(t.app.ctx.IsPaused(), true, "F2 pauses")
    t.app.Tick()
    AssertEq(t.launched.Length, 0, "no launch while paused")
    AssertEq(t.ui.status.state, "Paused", "paused shown")
    t.app.TogglePause()
    AssertEq(t.app.ctx.IsPaused(), false, "F2 resumes")
}

Test_App_UptimeAndLoops() {
    t := AppTestMake()
    t.app.Start()
    t.clk.t += 5000
    t.app.state.fishLoops := 1
    t.app.Tick()
    t.app.state.fishLoops := 2
    t.app.Tick()
    t.app.state.fishLoops := 0            ; sell reset
    t.app.Tick()
    t.app.state.fishLoops := 15           ; repath jump: not catches
    t.app.Tick()
    AssertEq(t.ui.status.loops, 2, "loops counts catches across sells")
    AssertEq(t.ui.status.up, 5000, "uptime since start")
}

Test_App_HotkeyNameValidation() {
    AssertEq(App.HotkeyName("F1", "F1"), "F1", "F1 ok")
    AssertEq(App.HotkeyName(" f12 ", "F1"), "F12", "case/space")
    AssertEq(App.HotkeyName("a", "F2"), "F2", "letter refused")
    AssertEq(App.HotkeyName("^F1", "F3"), "F3", "combo refused")
    AssertEq(App.HotkeyName("F25", "F3"), "F3", "F25 refused")
    keys := App.HotkeyKeys(AppFakeCfg(Map("Hotkeys.start", "F2")))
    AssertEq(keys["start"] "," keys["pause"] "," keys["stop"], "F1,F2,F3", "duplicates fall back to defaults")
}

Test_App_CalibrateRefusedWhileRunning() {
    t := AppTestMake()
    t.app.Start()
    AssertEq(t.app.OnCalibrate("all"), 0, "refused while running")
    AssertTrue(InStr(t.ui.logs[t.ui.logs.Length], "Stop the macro"), "explains")
}

Test_App_ExitHookDrainsAndReturnsZero() {
    t := AppTestMake()
    t.app.Start()
    r := t.app.OnExitApp("Exit", 0)
    AssertEq(r, 0, "exit not blocked (Input's own OnExit still runs)")
    AssertEq(t.wh.drains, 1, "Drain on exit")
    AssertEq(t.clip.cancels, 1, "clips cancelled on exit")
    AssertEq(t.wh.sent[t.wh.sent.Length], "startstop", "stop webhook on exit")
}

Test_App_UsagePathAbsolute() {
    p := PotionsTask.DefaultUsagePath()
    AssertTrue(RegExMatch(p, "i)^[A-Z]:\\.+\\data\\potion_usage\.json$"), "absolute usage path")
    AssertEq(App.DefaultRoot() "\data\potion_usage.json", p, "same repo root as the app")
}

Test_App_DryRunDefaultOn() {
    AssertEq(Config.IniDefaults()["General"]["dryRun"], "1", "General.dryRun default stays 1")
}

; A Dashboard-like ui that also takes the Home stats.
class AppStatsUi extends AppFakeUi {
    __New() {
        super.__New()
        this.stats := []
    }
    SetStats(m) => this.stats.Push(m)
}

Test_App_StatusFeedsDashStats() {
    t := AppTestMake()
    ui := AppStatsUi()
    t.app.ui.Push(ui)
    t.app.state.Bump("fishCaught", 5)
    t.app.state.Bump("biomes")
    t.app._Status()
    AssertEq(ui.stats.Length, 1, "SetStats called once per status")
    AssertTrue(ui.stats[1] is Map, "a Map")
    AssertEq(ui.stats[1]["fishCaught"], 5, "fishCaught passed")
    AssertEq(ui.stats[1]["biomes"], 1, "biomes passed")
    AssertTrue(IsObject(ui.status), "SetStatus still called")
    AssertEq(t.ui.status.state, "Stopped", "a ui without SetStats still gets SetStatus")
}

; 1920x1080 (and smaller): the open chat covers the left menu, so Mari /
; Jester can't be done - warned once in the log while Merchants is on
; the old "Mari and Jester can't be done" warning is gone: ChatGuard moves
; the chat out of the way below 1440p (2026-11-11)
Test_App_NoChatWarningBelow1440() {
    for on in [1, 0] {
        t := AppTestMake(Map("cfgVals", Map("General.sound", 0, "Medal.onRareBiome", 0, "merchant.enabled", on)))
        t.app.roblox := {Describe: (this) => "Roblox client 1920x1080", Verified: (this) => false, SizeText: (this) => "1920x1080 (x0.75)"}
        try {
            Screen.SetClient(0, 0, 1920, 1080)
            t.app._DisplayCheck()
            t.app._DisplayCheck()
        } finally
            Screen.Reset()
        n := 0
        for l in t.ui.logs
            n += InStr(l, "Mari and Jester can't be done") ? 1 : 0
        AssertEq(n, 0, "merchant.enabled=" on ": no warning")
        AssertTrue(!InStr(t.app._display, "Mari / Jester"), "no status note")
    }
    t := AppTestMake(Map("cfgVals", Map("General.sound", 0, "Medal.onRareBiome", 0, "merchant.enabled", 1)))
    t.app.roblox := {Describe: (this) => "Roblox client 2560x1440", Verified: (this) => true, SizeText: (this) => "2560x1440"}
    t.app._DisplayCheck()
    for l in t.ui.logs
        AssertTrue(!InStr(l, "Mari and Jester"), "no warning at 2560x1440")
}

; 2026-11-11: Roblox had closed; F1 paused ("Roblox not found") and F2 was
; refused. With auto-rejoin on and a private server link, Start goes on and
; the recovery task opens it.
Test_App_MissingAtStartRejoinsWithALink() {
    rec := AppFakeTask("recovery", 2, true)
    t := AppTestMake(Map("tasks", Map("recovery", rec, "fishing", AppFakeTask("fishing", 99))
        , "cfgVals", Map("General.privateServer", RecoveryTask.LinkPrefix "123")))
    t.rb.win := 0
    t.app.Start()
    AssertEq(t.app.ctx.IsPaused(), false, "not paused")
    t.app.Tick()
    AppTestRunLaunched(t)
    AssertEq(rec.runs, 1, "recovery ran (it rejoins)")
}
