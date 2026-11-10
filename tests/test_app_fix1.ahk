#Requires AutoHotkey v2.0
; Task 14b review fix round 1: window/focus loss mid-task, rebuild race,
; per-run caps across rebuilds, pause releases keys, logging, harness
; scrub, fresh LogWatch on restart. Fakes live in test_app.ahk.
#Include ..\lib\App.ahk

Test_App_MidTaskWindowGonePreemptsForRecovery() {
    rec := AppFakeTask("recovery", 2, false)
    fish := AppFakeTask("fishing", 99, true, (self, ctx) => (t.rb.win := 0, t.app.Tick()
        , self.pre := ctx.IsPreempted(), self.paused := ctx.IsPaused(), self.halted := CleanupCtx.Halted(ctx)))
    t := AppTestMake(Map("tasks", Map("recovery", rec, "fishing", fish)))
    t.app.Start()
    t.app.Tick()
    AppTestRunLaunched(t)
    AssertEq(fish.pre, true, "window gone mid-task -> preempt for recovery")
    AssertEq(fish.paused, false, "not paused while recovery is on")
    AssertEq(fish.halted, true, "a halt too: its closing steps send nothing with no window")
}

Test_App_WindowGoneAfterAPreemptStillHalts() {
    rec := AppFakeTask("recovery", 2, false)
    fish := AppFakeTask("fishing", 99, true, (self, ctx) => (ctx.RequestPreempt(), t.rb.win := 0, t.app.Tick()
        , self.halted := CleanupCtx.Halted(ctx)))
    t := AppTestMake(Map("tasks", Map("recovery", rec, "fishing", fish)))
    t.app.Start()
    t.app.Tick()
    AppTestRunLaunched(t)
    AssertEq(fish.halted, true, "window gone on top of a plain preempt -> halted")
}

Test_App_MidTaskWindowGoneRecoveryOffPauses() {
    fish := AppFakeTask("fishing", 99, true, (self, ctx) => (t.rb.win := 0, t.app.Tick(), self.stop := ctx.ShouldStop()))
    t := AppTestMake(Map("tasks", Map("fishing", fish)))
    t.app.Start()
    t.app.Tick()
    AppTestRunLaunched(t)
    AssertEq(fish.stop, true, "task told to stop")
    AssertEq(t.app.ctx.IsPaused(), true, "paused without recovery")
    AssertTrue(InStr(t.ui.status.task, "Roblox not found"), "status")
}

Test_App_MidTaskLostFocusPauses() {
    fish := AppFakeTask("fishing", 99, true, (self, ctx) => (t.rb.activeOk := false, t.app.Tick(), self.stop := ctx.ShouldStop()))
    t := AppTestMake(Map("tasks", Map("fishing", fish)))
    t.app.Start()
    t.app.Tick()
    AppTestRunLaunched(t)
    AssertEq(fish.stop, true, "task told to stop on alt-tab")
    AssertEq(t.ui.status.state, "Paused", "paused")
    AssertEq(t.ui.status.task, "Roblox lost focus", "clear status")
    AssertTrue(t.input.releases >= 1, "held keys released")
    t.app.Tick()
    AssertEq(t.launched.Length, 0, "nothing new starts while paused")
    t.app.Resume()                       ; F2: next start focuses Roblox again
    t.app.Tick()
    AssertEq(t.launched.Length, 1, "runs again after resume")
}

Test_App_RecoveryRunningExemptFromWindowChecks() {
    rec := AppFakeTask("recovery", 2, true, (self, ctx) => (t.rb.win := 0, t.app.Tick(), t.rb.win := 1, t.rb.activeOk := false
        , t.app.Tick(), self.stop := ctx.ShouldStop()))
    t := AppTestMake(Map("tasks", Map("recovery", rec, "fishing", AppFakeTask("fishing", 99))))
    t.app.Start()
    t.app.Tick()
    AppTestRunLaunched(t)
    AssertEq(rec.runs, 1, "recovery ran")
    AssertEq(rec.stop, false, "rejoin not interrupted by missing window / focus")
}

; overnight review: idle (nothing eligible) the macro focused Roblox every
; tick, taking it back from the browser within 250 ms
Test_App_IdleDoesNotGrabFocus() {
    task := AppFakeTask("fishing", 99, false)
    t := AppTestMake(Map("tasks", Map("fishing", task)))
    chat := AppFakeChat(t.app)
    t.app.chat := chat
    t.app.Start()
    t.rb.focusCalls := 0
    t.rb.activeOk := false                  ; the user is in the browser
    Loop 5
        t.app.Tick()
    AssertEq(t.rb.focusCalls, 0, "idle: Roblox not focused")
    AssertEq(chat.checks, 0, "no chat read while Roblox is not in front")
    AssertEq(t.ui.status.task, "Idle", "status")
    ; Roblox already in front: chat is read, still no focus call
    t.rb.activeOk := true
    t.app.Tick()
    AssertEq(t.rb.focusCalls, 0, "in front already: no focus call")
    AssertTrue(chat.checks >= 1, "chat read while Roblox is in front")
    ; something to run: focused, then launched
    t.rb.activeOk := false
    task.can := true
    t.app.Tick()
    AssertEq(t.rb.focusCalls, 1, "focused for the launch")
    AssertEq(t.launched.Length, 1, "launched")
}

Test_App_ChatNeedsFocusAndActiveRoblox() {
    t := AppTestMake()
    chat := AppFakeChat(t.app)
    t.app.chat := chat
    t.rb.focusOk := false
    t.app.Start()
    t.app.Tick()
    AssertEq(chat.checks, 0, "no chat read when focus fails")
    AssertEq(t.launched.Length, 0, "no launch")
    t.rb.focusOk := true
    t.rb.focusActivates := false
    t.rb.activeOk := false
    t.app.Tick()
    AssertEq(chat.checks, 0, "no chat read while Roblox is not active")
    AppTestRunLaunched(t)
    t.rb.focusActivates := true
    t.app.Tick()
    AssertEq(chat.checks, 1, "chat read once Roblox is active")
    AssertTrue(t.rb.focusCalls >= 3, "focus before chat")
}

Test_App_RebuildDuringFocusLaunchesCurrentPotions() {
    t := AppTestMake(Map("be", "fake"))
    t.app._proxy.Queue("GLITCHED", "ts1")
    old := t.app.potions
    t.rb.duringFocus := () => (t.cfg.Bump(), t.app.OnPotionsChanged())
    t.app.Start()
    t.app.Tick()
    t.rb.duringFocus := ""
    AppTestRunLaunched(t)
    AssertTrue(t.app.potions !== old, "rebuilt during focus")
    AssertEq(old.runs, 0, "stale PotionsTask never runs")
    AssertEq(t.app.potions.runs, 1, "current PotionsTask ran")
}

Test_App_LaunchSwapsReplacedPotions() {
    t := AppTestMake(Map("be", "fake"))
    t.app._proxy.Queue("GLITCHED", "ts1")
    old := t.app.potions
    t.cfg.Bump()
    t.app.OnPotionsChanged()
    t.app.Start()
    t.app._Launch(old)                    ; picked just before the rebuild
    AppTestRunLaunched(t)
    AssertEq(old.runs, 0, "old object not run")
    AssertEq(t.app.potions.runs, 1, "current object run")
    t.app._Launch(old)                    ; nothing pending any more
    AssertEq(t.launched.Length, 0, "no launch when current has nothing pending")
    AssertEq(t.app.TaskRunning(), false, "running flag cleared")
}

Test_App_StopOrPauseDuringFocusNoLaunch() {
    q := AppFakeTask("quests", 5)
    t := AppTestMake(Map("tasks", Map("quests", q, "fishing", AppFakeTask("fishing", 99))))
    t.app.Start()
    t.rb.duringFocus := () => t.app.Pause()
    t.app.Tick()
    AssertEq(t.launched.Length, 0, "pause during focus: no launch")
    t.rb.duringFocus := ""
    t.app.Resume()
    t.rb.duringFocus := () => t.app.Stop()
    t.app.Tick()
    AssertEq(t.launched.Length, 0, "stop during focus: no launch")
    AssertEq(t.app.state.lastRun.Count, 0, "no MarkRun")
    AssertEq(t.app.state.busy, "", "busy untouched")
}

Test_App_SaveWithoutChangeSkipsRebuild() {
    t := AppTestMake()
    p := t.app.potions
    t.app.OnPotionsChanged()
    t.app.OnPotionsChanged()
    AssertEq(t.builds, 1, "identical data: no rebuild")
    AssertTrue(t.app.potions == p, "same task kept")
    t.cfg.biomes["biomes"][1]["potions"] := [Map("name", "Lucky Potion", "qty", 1)]
    t.app.OnPotionsChanged()
    AssertEq(t.builds, 2, "biomes.json change rebuilds too")
}

AppTestUsagePath() {
    path := A_Temp "\vesper_app_test_usage.json"
    for f in [path, path ".tmp", path ".probe"]
        try FileDelete(f)
    return path
}

Test_App_SaveTwiceMidRunKeepsRunCap() {
    path := AppTestUsagePath()
    cfgRef := {c: AppFakeCfg()}
    t := AppTestMake(Map("safetyFactory", () => PotionSafety(cfgRef.c.Data("potions"), path)))
    ; the constructor's first build used a placeholder cfg: rebuild on the test cfg
    cfgRef.c := t.cfg
    t.app.potions := ""
    t.app.OnPotionsChanged()
    s1 := t.app.potions.safety
    k1 := "GLITCHED|2026-10-25T10:00:00"
    AssertEq(s1.BeginEvent(k1), true, "event 1 claimed")
    s1.Record("Lucky Potion", k1)         ; perRun = 1 -> run cap used up
    AssertEq(s1.Plan("Lucky Potion", 1, k1, 10).reason, "cap_run", "cap used before saves")
    t.cfg.Bump()
    t.app.OnPotionsChanged()              ; save 1 (changed)
    s2 := t.app.potions.safety
    AssertTrue(s2 !== s1, "rebuilt")
    k2 := "GLITCHED|2026-10-25T11:00:00"
    AssertEq(s2.BeginEvent(k2), true, "event 2 claimed")
    AssertEq(s2.Plan("Lucky Potion", 1, k2, 10).reason, "cap_run", "run cap kept after save 1")
    t.cfg.Bump()
    t.app.OnPotionsChanged()              ; save 2 (changed)
    s3 := t.app.potions.safety
    AssertTrue(s3 !== s2, "rebuilt again")
    AssertEq(s3.Plan("Lucky Potion", 1, k2, 10).reason, "cap_run", "run cap kept after save 2 (open event carried)")
    for f in [path, path ".tmp", path ".probe"]
        try FileDelete(f)
}

Test_App_TransferRunCountsCarriesHalt() {
    path := AppTestUsagePath()
    pc := Map("potions", [Map("name", "Lucky Potion", "locked", false, "perBiome", 5, "perDay", 5, "perRun", 5)])
    s1 := PotionSafety(pc, path)
    try s1.Record("Nope", "GLITCHED|t")   ; bad args -> halts s1
    s2 := PotionSafety(pc, path)
    AssertEq(s2.TransferRunCountsFrom(s1), true, "transfer ok")
    k := "GLITCHED|t9"
    s2.BeginEvent(k)
    AssertEq(s2.Plan("Lucky Potion", 1, k, 10).reason, "record_failed", "halt survives a rebuild")
    AssertEq(s2.TransferRunCountsFrom(s2), false, "self refused")
    AssertEq(s2.TransferRunCountsFrom({}), false, "non-PotionSafety refused")
    for f in [path, path ".tmp", path ".probe"]
        try FileDelete(f)
}

Test_App_PauseReleasesKeysAndCancelsClips() {
    t := AppTestMake()
    t.app.Start()
    t.app.Pause()
    AssertEq(t.input.releases, 1, "F2 releases held keys")
    AssertEq(t.clip.cancels, 1, "F2 cancels scheduled clips")
}

class AppFakeCalThrows {
    Use(path, cfg) {
        throw Error("calibration exploded")
    }
}

Test_App_CalibrationUseErrorLogged() {
    t := AppTestMake(Map("calibrate", AppFakeCalThrows()))
    t.app.OnSaved("Craft")
    AssertTrue(InStr(t.ui.logs[t.ui.logs.Length], "calibration exploded"), "Use error logged")
}

Test_App_HarnessErrorScrubbed() {
    cfg := AppFakeCfg(Map("General.privateServer", "my-private-link-code-123456"))
    e := Error("boom https://discord.com/api/webhooks/123/SECRETTOKEN and my-private-link-code-123456")
    txt := App.HarnessErrorText(e, cfg)
    AssertTrue(InStr(txt, "ERROR boom"), "message kept")
    AssertEq(InStr(txt, "SECRETTOKEN"), 0, "webhook URL scrubbed")
    AssertEq(InStr(txt, "my-private-link-code-123456"), 0, "configured secret scrubbed")
}

Test_App_RestartRecreatesLogWatch() {
    made := []
    t := AppTestMake(Map("logWatchFactory", () => (made.Push(AppFakeLw()), made[made.Length])))
    AssertEq(made.Length, 1, "one LogWatch at construction")
    t.app.Start()
    AssertEq(made.Length, 1, "first start reuses it")
    t.app.Stop()
    t.app.Tick()
    t.app.Start()
    AssertEq(made.Length, 2, "restart makes a fresh LogWatch (silent backfill)")
    AssertTrue(t.app.lw == made[2], "new instance in use")
}
