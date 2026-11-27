#Requires AutoHotkey v2.0
; Silent stops (2026-11-26): a tester came back after an hour or two to a
; macro that had done nothing, and only the log knew why. Every way the
; macro pauses or waits by itself now tells the player (log, `errors`
; webhook, status), and "Roblox lost focus" while nobody uses the PC is
; undone by itself (General.awayRefocus). Uses the App rig from
; test_app.ahk (AppTestMake & co) and UiDashTmp from test_ui_dash.ahk.

SsCount(t, ev, title := "") {
    n := 0
    for i, e in t.wh.sent
        if (e = ev && (title = "" || t.wh.titles[i] = title))
            n++
    return n
}

SsLogHas(t, text) {
    for l in t.ui.logs
        if InStr(l, text)
            return true
    return false
}

; a rig whose fishing task makes Roblox lose focus in the middle of it;
; idle / busy: what the away check reads (ms since the last input, a
; fullscreen app in front)
SsFocusRig(cfgVals := "", idle := 0, busy := false) {
    v := Map("General.sound", 0, "Medal.onRareBiome", 0)
    if (cfgVals is Map)
        for k, x in cfgVals
            v[k] := x
    fish := AppFakeTask("fishing", 99, true, (self, ctx) => (t.rb.activeOk := false, t.app.Tick()))
    t := AppTestMake(Map("tasks", Map("fishing", fish), "cfgVals", v))
    t.fish := fish
    t.idle := {ms: idle, busy: busy}
    t.app._frontFn := () => "notepad.exe"
    t.app._idleMsFn := () => t.idle.ms
    t.app._userBusyFn := () => t.idle.busy
    return t
}

; one fishing run that loses focus -> paused "Roblox lost focus"
SsLoseFocus(t) {
    t.app.Tick()
    AppTestRunLaunched(t)
}

Test_SilentStop_FocusPauseToldAfterAMinute() {
    t := SsFocusRig(Map("General.awayRefocus", 0))
    t.app.Start()
    SsLoseFocus(t)
    AssertEq(t.ui.status.task, "Roblox lost focus", "status says why")
    AssertEq(SsCount(t, "errors"), 0, "nothing sent at once (a quick alt-tab is no news)")
    t.clk.t += 30000
    t.app.Tick()
    AssertEq(SsCount(t, "errors"), 0, "30 s: not yet")
    t.clk.t += 31000
    t.app.Tick()
    AssertEq(SsCount(t, "errors", "Macro paused"), 1, "61 s: one errors message")
    AssertTrue(SsLogHas(t, "Still paused after 1 min (Roblox lost focus): told Discord"), "logged")
    t.clk.t += 3600000
    t.app.Tick()
    AssertEq(SsCount(t, "errors"), 1, "once per pause, not every tick")
    ; F2 and a new pause: told again
    t.app.Resume()
    SsLoseFocus(t)
    t.clk.t += 61000
    t.app.Tick()
    AssertEq(SsCount(t, "errors", "Macro paused"), 2, "a new pause is a new message")
    t.app.Stop("test")
}

Test_SilentStop_QuickAltTabSendsNothing() {
    t := SsFocusRig(Map("General.awayRefocus", 0))
    t.app.Start()
    SsLoseFocus(t)
    t.clk.t += 20000
    t.app.Tick()
    t.app.Resume()                          ; back within 20 s
    t.clk.t += 120000
    t.app.Tick()
    AssertEq(SsCount(t, "errors"), 0, "nothing sent")
    t.app.Stop("test")
}

Test_SilentStop_WindowPausesToldToo() {
    ; Roblox closed with auto-rejoin off: paused "Roblox not found"
    t := SsFocusRig()
    t.app.Start()
    t.rb.win := 0
    t.app.Tick()
    AssertTrue(InStr(t.ui.status.task, "Roblox not found"), "status: " t.ui.status.task)
    t.clk.t += 61000
    t.app.Tick()
    AssertEq(SsCount(t, "errors", "Macro paused"), 1, "missing window told")
    t.app.Stop("test")
    ; minimized
    t2 := SsFocusRig()
    t2.rb.fs := false
    t2.app.Start()
    t2.clk.t += 61000
    t2.app.Tick()
    AssertEq(SsCount(t2, "errors", "Macro paused"), 1, "unusable window told")
    t2.app.Stop("test")
}

; F2 by hand is the player's own pause: never sent, never undone
Test_SilentStop_HandPauseLeftAlone() {
    t := SsFocusRig(, 3600000)
    t.app.Start()
    t.app.Pause()
    t.rb.activeOk := false
    Loop 3 {
        t.clk.t += 600000
        t.app.Tick()
    }
    AssertEq(SsCount(t, "errors"), 0, "nothing sent")
    AssertTrue(t.app.ctx.IsPaused(), "still paused")
    t.app.Stop("test")
}

; nobody used the PC for 2 min: Roblox back in front, resumed, logged and sent
Test_SilentStop_AwayRefocusResumes() {
    t := SsFocusRig(, 180000)
    t.app.Start()
    SsLoseFocus(t)
    AssertTrue(t.app.ctx.IsPaused(), "paused in the task")
    f0 := t.rb.focusCalls
    t.app.Tick()                            ; the task ended: the away check runs
    AssertTrue(!t.app.ctx.IsPaused(), "resumed")
    AssertTrue(t.rb.focusCalls > f0, "Roblox focused")
    AssertEq(t.app._pauseReason, "", "no pause reason left")
    AssertEq(SsCount(t, "errors", "Macro resumed"), 1, "sent")
    AssertTrue(SsLogHas(t, "Resumed: Roblox lost focus and nobody used the PC for 3 min") && SsLogHas(t, "In front: notepad.exe."), "logged with the window that took it")
    AssertEq(t.launched.Length, 1, "the next task launched")
    t.app.Stop("test")
}

; at most AwayMax an hour, AwayRetryMs apart; then the pause stays and is told
Test_SilentStop_AwayRefocusLimited() {
    t := SsFocusRig(, 180000)
    t.app.Start()
    Loop App.AwayMax {
        SsLoseFocus(t)
        t.app.Tick()
        AssertTrue(!t.app.ctx.IsPaused(), "refocus " A_Index)
        t.clk.t += App.AwayRetryMs + 1000
    }
    SsLoseFocus(t)
    t.app.Tick()
    AssertTrue(t.app.ctx.IsPaused(), "the " (App.AwayMax + 1) "th in an hour stays paused")
    t.clk.t += App.PauseTellMs + 1000
    t.app.Tick()
    AssertEq(SsCount(t, "errors", "Macro paused"), 1, "and is told")
    t.clk.t += App.AwayWindowMs
    t.app.Tick()
    AssertTrue(!t.app.ctx.IsPaused(), "an hour later it may refocus again")
    t.app.Stop("test")
    ; two pauses within AwayRetryMs: the second waits
    t2 := SsFocusRig(, 180000)
    t2.app.Start()
    SsLoseFocus(t2)
    t2.app.Tick()
    t2.clk.t += 10000
    SsLoseFocus(t2)
    t2.app.Tick()
    AssertTrue(t2.app.ctx.IsPaused(), "10 s after the last refocus: waits")
    t2.clk.t += App.AwayRetryMs
    t2.app.Tick()
    AssertTrue(!t2.app.ctx.IsPaused(), "after the gap: refocused")
    t2.app.Stop("test")
}

Test_SilentStop_AwayRefocusNeedsAwayIdleAndTheSwitch() {
    ; the player is using the PC
    t := SsFocusRig(, 30000)
    t.app.Start()
    SsLoseFocus(t)
    Loop 3
        t.app.Tick()
    AssertTrue(t.app.ctx.IsPaused(), "30 s since the last input: left paused")
    t.idle.ms := 180000, t.idle.busy := true
    t.app.Tick()
    AssertTrue(t.app.ctx.IsPaused(), "a fullscreen app in front: left paused")
    t.idle.busy := false
    t.app.Tick()
    AssertTrue(!t.app.ctx.IsPaused(), "away and nothing fullscreen: resumed")
    t.app.Stop("test")
    ; switched off
    t2 := SsFocusRig(Map("General.awayRefocus", 0), 3600000)
    t2.app.Start()
    SsLoseFocus(t2)
    t2.clk.t += 61000
    t2.app.Tick()
    AssertTrue(t2.app.ctx.IsPaused(), "switch off: left paused")
    AssertEq(t2.rb.focusCalls > 1 ? "focused" : "", "", "Roblox not pulled to the front")
    AssertTrue(SsCount(t2, "errors", "Macro paused"), "told instead")
    t2.app.Stop("test")
    ; Roblox would not come to the front: still paused, said once
    t3 := SsFocusRig(, 180000)
    t3.app.Start()
    SsLoseFocus(t3)
    t3.rb.focusOk := false
    t3.app.Tick()
    AssertTrue(t3.app.ctx.IsPaused(), "focus refused: still paused")
    AssertTrue(SsLogHas(t3, "Roblox could not be put back in front"), "said so")
    t3.app.Stop("test")
    ; an unusable window is never 'refocused'
    t4 := SsFocusRig(, 3600000)
    t4.rb.fs := false
    t4.app.Start()
    t4.app.Tick()
    AssertTrue(t4.app.ctx.IsPaused() && InStr(t4.app._pauseReason, "not usable"), "notfs pause stays")
    t4.app.Stop("test")
}

; between tasks Roblox would not take the focus: "Waiting for Roblox focus"
; for a minute is told once
Test_SilentStop_WaitingForFocusTold() {
    t := SsFocusRig(Map("General.awayRefocus", 0))
    t.rb.focusOk := false, t.rb.activeOk := false
    t.app.Start()
    t.app.Tick()
    AssertEq(t.ui.status.task, "Waiting for Roblox focus", "status")
    AssertEq(t.launched.Length, 0, "nothing launched")
    t.app.Tick()                            ; the next tick (250 ms later) starts its clock
    t.clk.t += 61000
    t.app.Tick()
    AssertEq(SsCount(t, "errors", "Macro waiting"), 1, "told after a minute")
    t.clk.t += 600000
    t.app.Tick()
    AssertEq(SsCount(t, "errors"), 1, "once")
    t.rb.focusOk := true
    t.app.Tick()
    AssertEq(t.launched.Length, 1, "goes on when Roblox comes to the front")
    t.app.Stop("test")
}

; a task that pauses the macro itself (Sell's stuck pause, Limbo off): the
; status says which, not a bare "Paused"; an F2 in a task stays plain
Test_SilentStop_TaskPauseStatusSaysWhy() {
    sell := AppFakeTask("sell", 6, true, (self, ctx) => ctx.Pause())
    t := AppTestMake(Map("tasks", Map("sell", sell)))
    t.app.Start()
    t.app.Tick()
    AppTestRunLaunched(t)
    t.app.Tick()
    AssertEq(t.ui.status.state, "Paused", "paused")
    AssertEq(t.ui.status.task, "Sell paused the macro: see the log", "says which task")
    t.app.Resume()
    AssertEq(t.app._pauseReason, "", "F2 clears it")
    t.app.Stop("test")
    fish := AppFakeTask("fishing", 99, true, (self, ctx) => t2.app.Pause())
    t2 := AppTestMake(Map("tasks", Map("fishing", fish)))
    t2.app.Start()
    t2.app.Tick()
    AppTestRunLaunched(t2)
    AssertEq(t2.app._pauseReason, "", "an F2 pause is the player's own")
    t2.app.Stop("test")
}

; every task skipped (shift lock / locked mouse) with auto-rejoin off:
; nothing clears it, so it is said once (log + errors), again after a run
Test_SilentStop_SkipsWithNoRejoinTold() {
    inp := AppFakeShift()
    inp.stuck := true
    fish := AppFakeTask("fishing", 99)
    t := AppTestMake(Map("input", inp, "tasks", Map("fishing", fish)))
    t.app.Start()
    Loop App.SkipRejoinAt - 1
        t.app._RunTask(fish)
    AssertEq(SsCount(t, "errors"), 0, "not yet")
    t.app._RunTask(fish)
    AssertEq(SsCount(t, "errors"), 1, "told after " App.SkipRejoinAt " skips")
    AssertTrue(SsLogHas(t, "Every task is skipped"), "logged")
    t.app._RunTask(fish), t.app._RunTask(fish)
    AssertEq(SsCount(t, "errors"), 1, "once per streak")
    inp.stuck := false
    t.app._RunTask(fish)
    AssertEq(fish.runs, 1, "ran once the lock is gone")
    inp.stuck := true
    Loop App.SkipRejoinAt
        t.app._RunTask(fish)
    AssertEq(SsCount(t, "errors"), 2, "a new streak is told again")
    t.app.Stop("test")
    ; with a recovery task that rejoins: the rejoin, no such message
    inp2 := AppFakeShift()
    inp2.stuck := true
    rec := AppFakeUnlockRecovery()
    t2 := AppTestMake(Map("input", inp2, "tasks", Map("fishing", AppFakeTask("fishing", 99), "recovery", rec)))
    t2.app.Start()
    Loop App.SkipRejoinAt + 1
        t2.app._RunTask(t2.tasks["fishing"])
    AssertEq(rec.asks, 1, "rejoin asked")
    AssertTrue(!SsLogHas(t2, "Every task is skipped"), "no skip message")
    t2.app.Stop("test")
}

; stuck game windows with auto-rejoin off: the Discord message too
Test_SilentStop_StuckUiNoRejoinSent() {
    UiStuck.Reset()
    obby := AppFakeTask("obby", 7, true, (self, ctx) => UiStuck.Fail("aura storage", UiStuck.TripAt))
    t := AppTestMake(Map("tasks", Map("obby", obby)))
    try {
        t.app.Start()
        t.app._RunTask(obby)
        AssertEq(SsCount(t, "errors"), 1, "errors webhook")
        AssertTrue(SsLogHas(t, "auto-rejoin is off, so nothing clears them"), "logged")
        t.app._RunTask(obby)
        AssertEq(SsCount(t, "errors"), 1, "once per run")
        t.app.Stop("test")
    } finally
        UiStuck.Reset()
}

; the schedule's stop names its rule ("stop time" was logged after a
; "Stop after N hours" ended a manual run)
Test_SilentStop_ScheduleStopSaysWhy() {
    AssertEq(App.SchedStopWhy(AppFakeCfg(Map("Schedule.maxHours", 2)), 2 * 3600000), "ran 2 h, its Stop after limit", "max hours")
    AssertEq(App.SchedStopWhy(AppFakeCfg(Map("Schedule.maxHours", 1.5)), 6000000), "ran 1.5 h, its Stop after limit", "1.5 h")
    AssertEq(App.SchedStopWhy(AppFakeCfg(Map("Schedule.maxHours", 2)), 3600000), "its Stop at time", "under the limit: the window")
    AssertEq(App.SchedStopWhy(AppFakeCfg(), 99 * 3600000), "its Stop at time", "no limit")
    t := AppTestMake()
    s := AfFakeSched()
    t.app.sched := s
    t.app.Start()
    s.acts.Push("stop")
    t.app._ScheduleTick()
    AssertTrue(!t.app._started, "stopped")
    AssertTrue(SsLogHas(t, "Schedule: its Stop at time; stopping") && SsLogHas(t, "Stopped (schedule: its Stop at time)"), "logged why")
}

Test_SilentStop_AwaySwitchDefaultsAndHelp() {
    AssertEq(Config.IniDefaults()["General"]["awayRefocus"], "1", "on by default")
    AssertTrue(InStr(HelpTexts.For("General.awayRefocus"), "nobody has used the PC for 2 minutes"), "help text")
    AssertEq(App.AwayMs, 120000, "help text's 2 minutes")
    AssertEq(App.AwayMax, 3, "help text's 3 times an hour")
    AssertTrue(App.UserBusy() = true || App.UserBusy() = false, "the real check never throws")
}

; Windows says "a fullscreen app runs" for Roblox itself and for the screen
; dim (the macro's own window): only someone else's fullscreen window in
; front keeps Roblox from being brought back (2026-11-27: paused 44 min
; behind an iCUE crash dialog, every refocus refused)
Test_SilentStop_AwayNotBlockedByRobloxOrTheDim() {
    f := (mine, roblox, full) => {mine: mine, roblox: roblox, full: full}
    AssertEq(App.BusyFrom(1, ""), true, "locked / screen saver")
    AssertEq(App.BusyFrom(4, ""), true, "presentation mode")
    AssertEq(App.BusyFrom(5, ""), false, "normal")
    AssertEq(App.BusyFrom(2, f(false, false, false)), false, "a small dialog in front (the iCUE crash window)")
    AssertEq(App.BusyFrom(2, f(false, true, true)), false, "Roblox fullscreen")
    AssertEq(App.BusyFrom(3, f(true, false, true)), false, "the macro's own fullscreen window (the screen dim)")
    AssertEq(App.BusyFrom(2, f(false, false, true)), true, "someone else's fullscreen app (a film, another game)")
    AssertEq(App.BusyFrom(3, ""), true, "fullscreen, front unknown: leave it")
    fi := App.FrontInfo()
    AssertTrue(fi.HasOwnProp("mine") && fi.HasOwnProp("roblox") && fi.HasOwnProp("full"), "the real front never throws")
}

; Settings > Recovery: the switch is bound, inside its card, overlaps
; nothing, saves, and the search finds it
Test_SilentStop_AwaySwitchOnTheDashboard() {
    dir := UiDashTmp()
    d := ""
    try {
        cfg := Config.Load(dir)
        AssertEq(String(cfg.Get("General.awayRefocus", "")), "1", "a new settings.ini has it on")
        d := Dashboard(cfg)
        pi := Dashboard.PageIndex("Settings")
        d.SelectPage(pi)
        sw := d.Ctrl("General.awayRefocus")
        AssertTrue(IsObject(sw), "switch bound")
        AssertEq(sw.Value, 1, "loaded on")
        own := Map(sw._box.Hwnd, 1, sw._lbl.Hwnd, 1)
        mine := [UiDashPos(sw._box), UiDashPos(sw._lbl)]
        for c in d._pages[pi].ctrls
            if (Theme.HelpText(c) = HelpTexts.For("General.awayRefocus"))
                own[c.Hwnd] := 1, mine.Push(UiDashPos(c))
        AssertEq(mine.Length, 3, "box, label and its ?")
        pn := UiDashPos(d.Ctrl("panel:Settings:Recovery"))
        ovR := (a, b) => !(a.x + a.w <= b.x || b.x + b.w <= a.x || a.y + a.h <= b.y || b.y + b.h <= a.y)
        for r in mine {
            AssertTrue(r.x >= pn.x && r.y >= pn.y && r.x + r.w <= pn.x + pn.w && r.y + r.h <= pn.y + pn.h
                , "inside the Recovery card: " r.x "," r.y " " r.w "x" r.h)
            for c in d._pages[pi].ctrls {
                if (own.Has(c.Hwnd) || Theme.IsPanel(c))
                    continue
                AssertTrue(!ovR(r, UiDashPos(c)), "not over '" SubStr(c.Text, 1, 30) "'")
            }
        }
        sw.Value := 0
        d.SavePage("Settings")
        AssertEq(String(Config.Load(dir).Get("General.awayRefocus", "")), "0", "off saved")
        res := d.SearchFor("bring roblox")
        AssertTrue(res.Length >= 1 && res[1].page = "Settings", "search finds it")
    } finally {
        UiDashClose(d)
        try DirDelete(dir, true)
    }
}
