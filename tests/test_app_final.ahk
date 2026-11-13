#Requires AutoHotkey v2.0
; Final fix wave: tick guard, chat yield during fishing, test events, route
; recorder callback. Fakes live in test_app.ahk.
#Include ..\lib\App.ahk

AppFinalCount(t, ev) {
    n := 0
    for e in t.wh.sent
        n += (e = ev) ? 1 : 0
    return n
}

; ---- tick guard ------------------------------------------------------------

Test_App_TickErrorPausesReleasesAndReports() {
    bad := AppFakeTask("quests", 5)
    bad.DefineProp("CanRun", {Call: (self, st) => AppTestThrow("boom https://discord.com/api/webhooks/123456/secretTOKEN")})
    t := AppTestMake(Map("tasks", Map("fishing", AppFakeTask("fishing", 99), "quests", bad)))
    t.app.Start()
    r0 := t.input.releases
    threw := false
    try t.app.Tick()
    catch
        threw := true
    AssertTrue(!threw, "nothing escapes Tick")
    AssertTrue(t.app.ctx.IsPaused(), "macro paused")
    AssertEq(t.launched.Length, 0, "no task launched")
    AssertTrue(t.input.releases > r0, "held keys released")
    AssertEq(AppFinalCount(t, "errors"), 1, "one errors webhook")
    found := false
    for l in t.ui.logs {
        AssertTrue(!InStr(l, "secretTOKEN"), "log line scrubbed")
        if InStr(l, "Scheduler error")
            found := true
    }
    AssertTrue(found, "error logged")
    t.app.Tick()
    AssertEq(AppFinalCount(t, "errors"), 1, "no repeat webhook while paused")
    ; while a task runs: the monitor's CanRun throws -> paused, task told to stop
    bad2 := AppFakeTask("quests", 5, false)
    fish := AppFakeTask("fishing", 99, true, (self, ctx) => (bad2.DefineProp("CanRun", {Call: (s, st) => AppTestThrow("late boom")})
        , t2.app.Tick(), self.stop := ctx.ShouldStop()))
    t2 := AppTestMake(Map("tasks", Map("fishing", fish, "quests", bad2)))
    t2.app.Start()
    t2.app.Tick()
    AppTestRunLaunched(t2)
    AssertEq(fish.stop, true, "running task sees the pause")
    AssertTrue(t2.app.ctx.IsPaused(), "paused mid-task")
}

; ---- chat yield -------------------------------------------------------------

Test_App_ChatDueYieldsFishing() {
    seen := {d1: "", d2: ""}
    fish := AppFakeTask("fishing", 99, true, (self, ctx) => (seen.d1 := t.app.state.chatDue
        , t.clk.t += 6000, t.app.Tick(), seen.d2 := t.app.state.chatDue))
    t := AppTestMake(Map("tasks", Map("fishing", fish)))
    chat := AppFakeChat(t.app)
    t.app.chat := chat
    t.app.Start()
    t.app.Tick()
    AssertEq(chat.checks, 1, "chat read before fishing")
    AppTestRunLaunched(t)
    AssertEq(seen.d1, false, "chatDue clear when fishing starts")
    AssertEq(seen.d2, true, "chatDue set after merchant.chatPollSec while fishing")
    AssertEq(chat.duringTask, 0, "chat never read while a task runs")
    t.app.Tick()                                    ; fishing returned: between tasks
    AssertEq(chat.checks, 2, "chat read between tasks")
    AssertEq(t.app.state.chatDue, false, "chatDue cleared by the check")
    AssertEq(t.launched.Length, 1, "fishing launched again")
}

Test_App_ChatDueOnlyWhenWatchingAndNotRare() {
    seen := {d: ""}
    fish := AppFakeTask("fishing", 99, true, (self, ctx) => (t.clk.t += 60000, t.app.Tick(), seen.d := t.app.state.chatDue))
    ; merchants off
    t := AppTestMake(Map("tasks", Map("fishing", fish), "cfgVals", Map("General.sound", 0, "merchant.enabled", 0)))
    t.app.chat := AppFakeChat(t.app)
    t.app.Start(), t.app.Tick(), AppTestRunLaunched(t)
    AssertEq(seen.d, false, "merchant.enabled = 0: no yield")
    ; chat_rect not calibrated
    t := AppTestMake(Map("tasks", Map("fishing", fish), "calibrate", {Rect: (self, id) => "", Run: (self, ids) => 0, Use: (self, p, c) => 0}))
    t.app.chat := AppFakeChat(t.app)
    t.app.Start(), t.app.Tick(), AppTestRunLaunched(t)
    AssertEq(seen.d, false, "chat_rect missing: no yield")
    ; no ChatWatch
    t := AppTestMake(Map("tasks", Map("fishing", fish)))
    t.app.Start(), t.app.Tick(), AppTestRunLaunched(t)
    AssertEq(seen.d, false, "no chat watcher: no yield")
    ; rare biome active: no yield and no chat read at all
    t := AppTestMake(Map("tasks", Map("fishing", fish)))
    chat := AppFakeChat(t.app)
    t.app.chat := chat
    t.app.Start()
    t.app.state.rareActive := true       ; from the log, after Start cleared the old one
    t.app.Tick()
    AssertEq(chat.checks, 0, "no chat read during a rare biome")
    AppTestRunLaunched(t)
    AssertEq(seen.d, false, "rare biome: no yield")
}

; ---- test events ------------------------------------------------------------

Test_App_TestEventsRefusedWhenDryRunOff() {
    m := AppFakeMerchant()
    t := AppTestMake(Map("tasks", Map("fishing", AppFakeTask("fishing", 99), "merchant", m)
        , "cfgVals", Map("General.sound", 0, "Medal.onRareBiome", 0, "General.dryRun", 0)))
    t.app.Start()
    msg := t.app.FakeEvent("biome")
    AssertTrue(InStr(msg, "refused") && InStr(msg, "dry run"), "refused, says why: " msg)
    AssertEq(t.app.state.rareActive, false, "no fake rare biome")
    AssertEq(t.app.potions.CanRun(t.app.state), false, "no potion pass queued")
    AssertEq(AppFinalCount(t, "rare"), 0, "no rare webhook")
    msg := t.app.FakeEvent("merchant")
    AssertTrue(InStr(msg, "refused"), "merchant refused too")
    AssertEq(m.events.Length, 0, "merchant not notified")
    ; dry run on but the macro stopped -> refused
    t2 := AppTestMake(Map("cfgVals", Map("General.sound", 0, "Medal.onRareBiome", 0, "General.dryRun", 1)))
    AssertTrue(InStr(t2.app.FakeEvent("biome"), "not running"), "refused while stopped")
    AssertEq(t2.app.state.rareActive, false, "nothing routed while stopped")
}

Test_App_TestEventsRouteWithDryRun() {
    m := AppFakeMerchant()
    t := AppTestMake(Map("tasks", Map("fishing", AppFakeTask("fishing", 99), "merchant", m)
        , "cfgVals", Map("General.sound", 0, "Medal.onRareBiome", 0, "General.dryRun", 1)))
    t.app.Start()
    n0 := t.wh.titles.Length
    msg := t.app.FakeEvent("biome")
    AssertTrue(InStr(msg, "Sent"), "sent: " msg)
    AssertEq(t.app.state.rareActive, true, "BiomeEvents saw a live rare biome")
    AssertEq(t.app.state.biome, "GLITCHED", "fake GLITCHED")
    AssertTrue(SubStr(t.app.state.rareTs, 1, 5) = "TEST-", "event ts marked TEST-")
    AssertEq(t.app.potions.CanRun(t.app.state), true, "potion pass queued (dry run)")
    AssertTrue(AppFinalCount(t, "rare") = 1, "rare webhook sent")
    AssertTrue(t.wh.titles.Length > n0, "webhooks sent for the fake event")
    for i, title in t.wh.titles
        if (i > n0)
            AssertTrue(SubStr(title, 1, 7) = "[TEST] ", "webhook title marked: " title)
    ; potion pass, then the previous biome comes back silently
    t.app.Tick()
    AppTestRunLaunched(t)
    AssertEq(t.app.potions.runs, 1, "potions ran for the fake event")
    t.app.Tick()
    AssertEq(t.app.state.rareActive, false, "fake rare biome ended after the pass")
    AssertEq(t.app.state.biome, "NORMAL", "previous (unknown) biome -> NORMAL")
    ; merchant
    msg := t.app.FakeEvent("merchant")
    AssertTrue(InStr(msg, "Sent"), "merchant sent")
    AssertEq(m.events.Length, 1, "routed to MerchantTask.OnLogEvent")
    AssertEq(m.events[1]["name"], "Mari", "Mari")
    AssertEq(m.events[1]["live"], 1, "live event")
    ; tag only while routing
    t.app.wh.Send("errors", "plain", "x", 0)
    AssertEq(t.wh.titles[t.wh.titles.Length], "plain", "no [TEST] outside a test event")
    AssertTrue(InStr(t.app.FakeEvent("nope"), "unknown"), "unknown kind refused")
}

; ---- route recorder callback -------------------------------------------------

Test_App_RecordRouteStopsTheMacroFirst() {
    calls := []
    t := AppTestMake(Map("recordRoute", (name, path) => (calls.Push(name), {ok: false, msg: "cancelled", steps: [], routes: ""})))
    t.app.Start()
    r := t.app.OnRecordRoute("cauldron")
    AssertEq(t.app._started, false, "the running macro was stopped")
    AssertEq(t.respawns, 1, "respawned first, like playback does")
    AssertEq(calls.Length, 1, "then the recorder ran")
    AssertEq(calls[1], "cauldron", "for that route")
    AssertEq(r.msg, "cancelled", "recorder result returned")
}

Test_App_StartSellsThenBuysEvenWithoutFishing() {
    sell := AppFakeTask("sell", 6)
    t := AppTestMake(Map("tasks", Map("sell", sell, "fishing", AppFakeTask("fishing", 99)), "cfgVals", Map("General.fishing", 0, "Craft.enabled", 1)))
    t.app.Start()
    AssertEq(t.app.state.needRepath, true, "a sell run is due at start, fishing off too (to buy)")
    AssertEq(t.app.state.startSell, true, "buying waits for it")
    t.app._RunTask(sell)
    AssertEq(t.app.state.startSell, false, "after the sell run, buying may follow")
    ; no sell task: nothing is held back
    t2 := AppTestMake()
    t2.app.Start()
    AssertEq(t2.app.state.startSell, false, "no sell task: no start sell")
    ; fishing and crafting off (hunting only): no trip at all
    t3 := AppTestMake(Map("tasks", Map("sell", AppFakeTask("sell", 6)), "cfgVals", Map("General.fishing", 0, "Craft.enabled", 0)))
    t3.app.Start()
    AssertEq(t3.app.state.startSell, false, "nothing to sell or buy: no start trip")
}

Test_App_QuestRunGoesStraightBackThroughTheFisher() {
    sell := AppFakeTask("sell", 6)
    quests := AppFakeTask("quests", 5)
    t := AppTestMake(Map("tasks", Map("sell", sell, "quests", quests, "fishing", AppFakeTask("fishing", 99))))
    t.app.Start()
    t.app._RunTask(sell)
    t.app.state.needRepath := false
    t.app._RunTask(quests)
    AssertEq(t.app.state.needRepath, true, "after the board: the sell trip (to the fishing spot) is next")
    ; fishing off: no trip back
    t2 := AppTestMake(Map("tasks", Map("sell", AppFakeTask("sell", 6), "quests", quests), "cfgVals", Map("General.fishing", 0)))
    t2.app.Start()
    t2.app.state.needRepath := false
    t2.app._RunTask(quests)
    AssertEq(t2.app.state.needRepath, false, "fishing off: stays put")
}

Test_App_TasksThatWalkAwayGoBackThroughTheFisher() {
    for name in ["obby", "minions", "merchant", "memorymatch"] {
        task := AppFakeTask(name, 5)
        t := AppTestMake(Map("tasks", Map("sell", AppFakeTask("sell", 6), name, task, "fishing", AppFakeTask("fishing", 99))))
        t.app.Start()
        t.app.state.needRepath := false
        t.app._RunTask(task)
        AssertEq(t.app.state.needRepath, true, name ": the sell trip is next")
    }
    ; a task that stays put (biome items use the inventory where you stand)
    bi := AppFakeTask("biomeitems", 2)
    t := AppTestMake(Map("tasks", Map("sell", AppFakeTask("sell", 6), "biomeitems", bi, "fishing", AppFakeTask("fishing", 99))))
    t.app.Start()
    t.app.state.needRepath := false
    t.app._RunTask(bi)
    AssertEq(t.app.state.needRepath, false, "biome items: no trip")
}

Test_App_TestRouteWalksAndPressesTheKey() {
    walks := []
    t := AppTestMake(Map("walkRoute", (steps, key, ctx) => (walks.Push({n: steps.Length, key: key, ctx: ctx}), "")))
    ; not recorded: nothing walks
    r := t.app.OnTestRoute("quest_board")
    AssertEq(r.ok, false, "no route -> refused")
    AssertTrue(InStr(r.msg, "Record"), "tells the user to record it")
    AssertEq(walks.Length, 0, "nothing walked")
    t.cfg.routes := Map("quest_board", Map("steps", [["w", "down", 100], ["w", "up", 0]]))
    ; Roblox not fullscreen: refused
    t.rb.fs := false
    r := t.app.OnTestRoute("quest_board")
    AssertTrue(!r.ok && InStr(r.msg, "fullscreen"), "not fullscreen refused")
    AssertEq(walks.Length, 0, "still nothing walked")
    t.rb.fs := true
    ; running macro is stopped first, then the route is walked and E pressed
    t.app.Start()
    r := t.app.OnTestRoute("quest_board")
    AssertEq(t.app._started, false, "macro stopped first")
    AssertEq(walks.Length, 1, "walked once")
    AssertEq(walks[1].n, 2, "the recorded steps")
    AssertEq(walks[1].key, "e", "quest board -> E")
    AssertEq(r.ok, true, "ok")
    AssertTrue(InStr(r.msg, "pressed E") && InStr(r.msg, "quest board"), "says what to look for")
    AssertEq(t.app._testCtx, "", "test ctx cleared")
    ; F3 during the walk stops it and is reported
    t2 := AppTestMake(Map("walkRoute", (steps, key, ctx) => (t2.app.Stop("F3"), AssertTrue(ctx.ShouldStop(), "F3 reaches the walk"), "")))
    t2.cfg.routes := Map("cauldron", Map("steps", [["d", "down", 100], ["d", "up", 0]]))
    r := t2.app.OnTestRoute("cauldron")
    AssertEq(r.ok, false, "stopped -> not ok")
    AssertTrue(InStr(r.msg, "stopped"), "says it was stopped")
    ; Roblox losing focus stops it
    t3 := AppTestMake(Map("walkRoute", (steps, key, ctx) => (t3.rb.activeOk := false, ctx.ShouldStop() ? "" : "kept going")))
    t3.cfg.routes := Map("cauldron", Map("steps", [["d", "down", 100], ["d", "up", 0]]))
    r := t3.app.OnTestRoute("cauldron")
    AssertTrue(!r.ok && InStr(r.msg, "focus"), "focus loss stops the test")
}

; A fake obby task that records the Sailor swap in `order`.
AppSailorFake(order, ok := true) {
    return {name: "obby", priority: 5, CanRun: (*) => false, Run: (*) => 0
        , PutOnSailor: (self, ctx) => (order.Push("sailor"), {ok: ok, had: false, prev: "Glock", unknown: false, why: ok ? "" : "no 'Sailor' tile"})
        , PutBack: (self, ctx, info) => (order.Push("back " info.prev), true)}
}

Test_App_ObbyRouteTestWearsSailor() {
    order := []
    t := AppTestMake(Map("tasks", Map("fishing", AppFakeTask("fishing", 99), "obby", AppSailorFake(order))
        , "walkRoute", (steps, key, ctx) => (order.Push("walk"), "")))
    t.cfg.routes := Map("obby", Map("steps", [["w", "down", 100], ["w", "up", 0]]), "quest_board", Map("steps", [["w", "down", 100], ["w", "up", 0]]))
    r := t.app.OnTestRoute("obby")
    AssertEq(r.ok, true, "ok")
    AssertEq(order.Length, 3, "three steps")
    AssertEq(order[1], "sailor", "Sailor equipped before the walk")
    AssertEq(order[2], "walk", "then the route")
    AssertEq(order[3], "back Glock", "then the old aura back")
    ; another route: no swap
    order.Length := 0
    t.app.OnTestRoute("quest_board")
    AssertEq(order.Length, 1, "quest_board: only the walk")
    ; Sailor not equipped: nothing walked, the user is told
    order2 := []
    t2 := AppTestMake(Map("tasks", Map("fishing", AppFakeTask("fishing", 99), "obby", AppSailorFake(order2, false))
        , "walkRoute", (steps, key, ctx) => (order2.Push("walk"), "")))
    t2.cfg.routes := Map("obby", Map("steps", [["w", "down", 100], ["w", "up", 0]]))
    r := t2.app.OnTestRoute("obby")
    AssertEq(r.ok, false, "refused")
    AssertTrue(InStr(r.msg, "Sailor"), "says Sailor could not be equipped")
    AssertEq(order2.Length, 1, "no walk, nothing to put back")
}

Test_App_ObbyRecordWearsSailor() {
    order := []
    t := AppTestMake(Map("tasks", Map("fishing", AppFakeTask("fishing", 99), "obby", AppSailorFake(order))
        , "recordRespawn", (ctx) => (order.Push("respawn"), true)
        , "recordRoute", (name, path) => (order.Push("record"), {ok: true, msg: "saved", steps: [], routes: ""})))
    t.app.OnRecordRoute("obby")
    AssertEq(order[1], "sailor", "Sailor first")
    AssertEq(order[2], "respawn", "then the respawn")
    AssertEq(order[3], "record", "then the recording")
    AssertEq(order[4], "back Glock", "then the old aura back")
}

; 2026-10-27: the dashboard minimizes itself for Record / Test and Windows
; gives the focus to the next window (the browser) just after Roblox was
; focused, so both stopped at once: "could not equip Sailor (stopped)",
; "the respawn did not finish", "stopped: Roblox lost focus"
Test_App_RouteToolsRefocusAfterTheDashboardMinimizes() {
    order := []
    t := AppTestMake(Map("tasks", Map("fishing", AppFakeTask("fishing", 99), "obby", AppSailorFake(order))
        , "walkRoute", (steps, key, ctx) => (order.Push(ctx.ShouldStop() ? "walk stopped" : "walk"), "")))
    t.cfg.routes := Map("obby", Map("steps", [["w", "down", 100], ["w", "up", 0]]))
    lost := [true]
    t.rb.afterSleep := () => (lost[1] ? (t.rb.activeOk := false, lost[1] := false) : 0)
    r := t.app.OnTestRoute("obby")
    AssertEq(r.ok, true, "the test walks after focusing Roblox again")
    AssertEq(order[1], "sailor", "Sailor first")
    AssertEq(order[2], "walk", "then the walk, not stopped")
    AssertTrue(t.rb.focusCalls >= 2, "Roblox focused again after the focus was lost")
    ; Record: the same
    order.Length := 0
    lost[1] := true
    t2 := AppTestMake(Map("tasks", Map("fishing", AppFakeTask("fishing", 99), "obby", AppSailorFake(order))
        , "recordRespawn", (ctx) => (order.Push(ctx.ShouldStop() ? "respawn stopped" : "respawn"), true)
        , "recordRoute", (name, path) => (order.Push("record"), {ok: true, msg: "saved", steps: [], routes: ""})))
    t2.rb.afterSleep := () => (lost[1] ? (t2.rb.activeOk := false, lost[1] := false) : 0)
    t2.app.OnRecordRoute("obby")
    AssertEq(order[1], "sailor", "Sailor first")
    AssertEq(order[2], "respawn", "the respawn ran (not stopped)")
    ; focus that never comes back: refused, nothing done
    order.Length := 0
    t3 := AppTestMake(Map("tasks", Map("fishing", AppFakeTask("fishing", 99), "obby", AppSailorFake(order))
        , "walkRoute", (steps, key, ctx) => (order.Push("walk"), "")))
    t3.cfg.routes := Map("obby", Map("steps", [["w", "down", 100], ["w", "up", 0]]))
    t3.rb.afterSleep := () => (t3.rb.activeOk := false)
    r := t3.app.OnTestRoute("obby")
    AssertTrue(!r.ok && InStr(r.msg, "focus"), "refused: Roblox does not stay in front")
    AssertEq(order.Length, 0, "nothing equipped or walked")
}

; review 2026-10-27: F1 during a route Test / Record started a task while
; the tool held keys; a Record during a Test took its F3 handle
Test_App_RouteToolsBlockStartAndEachOther() {
    t := AppTestMake(Map("walkRoute", (steps, key, ctx) => (
        AssertEq(t.app.Start(), false, "F1 refused during a route test"),
        AssertEq(t.app.OnRecordRoute("quest_board").ok, false, "Record refused during a test"),
        "")))
    t.cfg.routes := Map("quest_board", Map("steps", [["w", "down", 100], ["w", "up", 0]]))
    r := t.app.OnTestRoute("quest_board")
    AssertEq(r.ok, true, "the test itself ran")
    AssertEq(t.app._toolBusy, false, "free again after the test")
    AssertEq(t.app.Start(), true, "F1 works after it")
}

; F3 then F1 while the stop webhook drains: the new run's timer survived
; nothing (status "Running", no tick) before the fix
Test_App_StartDuringTheStopDrainKeepsTheTimer() {
    t := AppTestMake()
    t.app.Start()
    t.app.Stop("F3")
    t.wh.DefineProp("Drain", {Call: (self, ms := 0) => (self.drains++, t.app.Start())})
    t.app._Finish()
    AssertEq(t.app._started, true, "running")
    AssertEq(t.app._timerOn, true, "its timer is still on")
    AssertTrue(t.timers[t.timers.Length] != 0, "the timer was not deleted after the drain")
}

; quests / obby cut short by a preempt did nothing: no 30 / 10 min wait
Test_App_PreemptedIntervalTaskIsNotMarkedRun() {
    t := AppTestMake()
    q := AppFakeTask("quests", 5, true, (self, ctx) => t.app.ctx.RequestPreempt())
    t.app._RunTask(q)
    AssertTrue(!t.app.state.lastRun.Has("quests"), "not marked: it may run again right away")
    q2 := AppFakeTask("quests", 5)
    t.app.ctx.ClearPreempt()
    t.app._RunTask(q2)
    AssertTrue(t.app.state.lastRun.Has("quests"), "a finished run is marked")
}

; a rare biome kept from the last session blocked tasks after it ended
Test_App_StartClearsTheOldRareState() {
    t := AppTestMake()
    t.app.state.rareActive := true
    t.app.state.rareTs := "x"
    t.app.Start()
    AssertEq(t.app.state.rareActive, false, "cleared on start (the log backfill sets it again)")
}

; fishing switched off while it runs stops it now (it only checked its
; switch before starting)
Test_App_FishingSwitchedOffStopsIt() {
    fish := AppFakeTask("fishing", 99)
    t := AppTestMake(Map("tasks", Map("fishing", fish)))
    t.app._running := fish
    fish.can := false
    t.app.OnSaved("Fishing")
    AssertEq(t.app.ctx.IsPreempted(), true, "the running fishing is told to stop")
    t.app._running := ""
}

; the dashboard kept its log only in memory: after a bad run nothing could
; be read back (2026-10-27). Every line goes to logs\macro.log, scrubbed.
Test_App_LogGoesToAFile() {
    t := AppTestMake(Map("cfgVals", Map("General.sound", 0, "Medal.onRareBiome", 0
        , "General.privateServer", "https://www.roblox.com/share?code=SECRETPS1")))
    dir := A_Temp "\vesper_logtest_" A_TickCount
    DirCreate(dir)
    try {
        t.app.root := dir
        t.app.Log("obby: hello from the test")
        t.app.Log("link https://www.roblox.com/share?code=SECRETPS1 must not show")
        txt := FileRead(dir "\logs\macro.log", "UTF-8")
        AssertTrue(InStr(txt, "obby: hello from the test"), "the line is in the file")
        AssertTrue(RegExMatch(txt, "\d{4}-\d\d-\d\d \d\d:\d\d:\d\d"), "with date and time")
        AssertTrue(!InStr(txt, "SECRETPS1"), "the private server link is scrubbed")
    } finally {
        try DirDelete(dir, true)
    }
}

; a reader that holds macro.log without write sharing (Git Bash tail -F,
; 2026-11-10) made every FileAppend fail: 36 minutes of lines were lost.
; Lines that could not be written are kept and written with the next line.
Test_App_LogKeepsLinesWhileTheFileIsLocked() {
    t := AppTestMake(Map("cfgVals", Map("General.sound", 0, "Medal.onRareBiome", 0)))
    dir := A_Temp "\vesper_loglock_" A_TickCount
    DirCreate(dir "\logs")
    try {
        t.app.root := dir
        t.app.Log("first line")
        f := FileOpen(dir "\logs\macro.log", "r -w")   ; deny write sharing
        t.app.Log("written while locked 1")
        t.app.Log("written while locked 2")
        f.Close()
        t.app.Log("after the lock")
        txt := FileRead(dir "\logs\macro.log", "UTF-8")
        p1 := InStr(txt, "written while locked 1"), p2 := InStr(txt, "written while locked 2"), p3 := InStr(txt, "after the lock")
        AssertTrue(p1 && p2 && p3, "no line lost")
        AssertTrue(p1 < p2 && p2 < p3, "in order")
        AssertTrue(InStr(txt, "first line") && InStr(txt, "first line") < p1, "the earlier line is still first")
    } finally {
        try DirDelete(dir, true)
    }
}

Test_App_HasObbyAndMemoryMatch() {
    t := AppTestMake(Map("defaultTasks", 1))
    AssertTrue(t.app._taskMap.Has("obby"), "obby task built")
    AssertTrue(t.app._taskMap.Has("memorymatch"), "memory match task built")
    q := 0
    for i, n in App.Order
        if (n = "quests")
            q := i
    AssertEq(App.Order[q + 1], "obby", "obby right after quests")
    AssertEq(App.Order[q + 2], "memorymatch", "memory match after obby")
    AssertEq(t.app._taskMap["obby"].name, "obby", "task name")
    AssertEq(t.app._taskMap["memorymatch"].name, "memorymatch", "task name")
}

Test_App_ObbyIntervalFromSettings() {
    t := AppTestMake(Map("cfgVals", Map("Obby.intervalMin", "15")))
    t.app.OnSaved("x")
    AssertEq(t.app.state.obbyIntervalMs, 900000, "15 min")
    t.cfg.Set("Obby.intervalMin", "0")
    t.app.OnSaved("x")
    AssertEq(t.app.state.obbyIntervalMs, 600000, "0 -> default 10 min")
    t.cfg.Set("Obby.intervalMin", "20")
    t.app.Start()
    AssertEq(t.app.state.obbyIntervalMs, 1200000, "Start applies it too")
}

; ---- v1.6 services (lib\Stats.ahk, Schedule.ahk, DailySummary.ahk, Remote.ahk)

class AfFakeSched {
    __New() {
        this.acts := []
        this.notes := []
    }
    Tick(now, running, runMs) => this.acts.Length ? this.acts.RemoveAt(1) : ""
    NoteStart(bySchedule) => this.notes.Push("start:" (bySchedule ? 1 : 0))
    NoteStop() => this.notes.Push("stop")
}

Test_App_V16_DayCountersFollowBumpsAndRuns() {
    dir := A_Temp "\vesper_v16_" A_TickCount
    DirCreate(dir)
    try {
        t := AppTestMake()
        daily := DailyStats(dir "\stats.json")
        t.app.daily := daily
        t.app.state.onBump := ObjBindMethod(t.app, "_DailyAdd")
        t.app.Start()
        t.app.state.Bump("fishCaught", 2)
        t.app.state.Bump("rejoins")
        AssertEq(daily.Day()["fishCaught"], 2, "fish counted for today")
        AssertEq(daily.Session()["rejoins"], 1, "rejoin counted for this run")
        AssertEq(t.app.state.stats["fishCaught"], 2, "session stats as before")
        t.app.Stop("test")
        AssertTrue(FileExist(dir "\stats.json"), "saved on stop")
    } finally
        try DirDelete(dir, true)
}

Test_App_V16_ScheduleStartsAndStops() {
    t := AppTestMake()
    s := AfFakeSched()
    t.app.sched := s
    s.acts.Push("start")
    t.app._ScheduleTick()
    AssertTrue(t.app._started, "started by the schedule")
    AssertTrue(t.rb.focusCalls >= 1, "Roblox brought to the front first")
    AssertEq(s.notes[1], "start:1", "noted as a schedule start")
    s.acts.Push("stop")
    t.app._ScheduleTick()
    AssertTrue(!t.app._started, "stopped by the schedule")
    AssertEq(s.notes[2], "stop", "stop noted")
    t.app.Start()
    AssertEq(s.notes[3], "start:0", "a manual start is not the schedule's")
    t.app.Stop("test")
}

Test_App_V16_SummaryNeedsAStopWebhook() {
    t := AppTestMake()
    t.app.daily := DailyStats(A_Temp "\vesper_v16_none_" A_TickCount ".json")
    t.wh.Route := (self, ev) => []
    AssertTrue(InStr(t.app.SendSummary(), "no webhook has Stop ticked"), "says why")
    AssertEq(t.wh.sent.Length, 0, "nothing sent")
    t.wh.Route := (self, ev) => [Map("url", "x")]
    AssertEq(t.app.SendSummary(), "Sent to 1 webhook", "sent")
    AssertEq(t.wh.sent[t.wh.sent.Length], "startstop", "on the start / stop webhooks")
}

Test_App_V16_RemoteCommands() {
    t := AppTestMake()
    h := t.app._RemoteHandlers()
    AssertTrue(InStr(h["status"].Call("", ""), "Stopped"), "status while stopped")
    AssertEq(h["start"].Call("", ""), "Started.", "start")
    AssertTrue(t.app._started, "running")
    AssertEq(h["start"].Call("", ""), "Already running.", "start twice")
    AssertTrue(InStr(h["status"].Call("", ""), "Running"), "status while running")
    AssertEq(h["pause"].Call("", ""), "Paused.", "pause")
    AssertEq(h["stop"].Call("", ""), "Stopped.", "stop")
    AssertEq(h["stop"].Call("", ""), "It was not running.", "stop twice")
    for k in ["status", "stats", "start", "stop", "pause", "resume", "screenshot", "log"]
        AssertTrue(h.Has(k), "handler " k)
}

Test_App_V16_FocusPauseNamesTheApp() {
    AssertEq(App.FrontNote(() => "MSPCManager.exe"), " In front: MSPCManager.exe. Microsoft PC Manager's toolbar takes focus: close PC Manager or turn its toolbar off.", "PC Manager named with a hint")
    AssertEq(App.FrontNote(() => "notepad.exe"), " In front: notepad.exe.", "other apps: the name only")
    AssertEq(App.FrontNote(() => ""), "", "unknown: nothing")
}

; PC Manager's toolbar took the focus after every F1: Roblox is put back in
; front (no pause), at most 3 times a minute; other apps still pause.
Test_App_V16_FocusThiefRefocused() {
    t := AppTestMake()
    t.app._frontFn := () => "MSPCManager.exe"
    t.app.Start()
    t.app.Tick()                                   ; fishing starts (the start focuses Roblox itself)
    Loop 3 {
        t.rb.activeOk := false
        t.app.Tick()
        AssertTrue(!t.app.ctx.IsPaused(), "refocus " A_Index ": not paused")
        AssertTrue(t.rb.activeOk, "refocus " A_Index ": Roblox in front again")
    }
    AssertEq(t.app._refocusAt.Length, 3, "three refocuses")
    t.rb.activeOk := false
    t.app.Tick()
    AssertTrue(t.app.ctx.IsPaused(), "the fourth in a minute pauses")
    t.app.Stop("test")
    t2 := AppTestMake()
    t2.app._frontFn := () => "notepad.exe"
    t2.app.Start()
    t2.app.Tick()
    t2.rb.activeOk := false
    t2.app.Tick()
    AssertTrue(t2.app.ctx.IsPaused(), "another app: paused as before")
    t2.app.Stop("test")
}

; live 2026-11-12: a ghost rejoin stopped by F3 left state.ghost set and the
; next Start closed the healthy private server again; Start clears it (the
; log decides again at the first poll)
Test_App_V17_StartClearsGhost() {
    t := AppTestMake()
    t.app.state.ghost := true
    t.app.Start()
    AssertEq(t.app.state.ghost, false, "cleared at Start")
    t.app.Stop("test")
}

; review 2026-11-12: "Send one now" marked the day sent, so tonight's real
; summary never went; only the scheduled send marks it
Test_App_V17_ManualSummaryKeepsTonights() {
    t := AppTestMake()
    dir := A_Temp "\vesper_v17_sum_" A_TickCount
    DirCreate(dir "\data")
    try {
        t.app.root := dir
        t.app.daily := DailyStats(dir "\data\stats.json")
        t.wh.Route := (self, ev) => [Map("url", "x")]
        AssertEq(t.app.SendSummary(), "Sent to 1 webhook", "sent now")
        AssertTrue(!FileExist(t.app._SummaryPath()), "the day is not marked by a manual send")
        t.app.SendSummary(true)
        AssertEq(Trim(FileRead(t.app._SummaryPath())), FormatTime(A_Now, "yyyyMMdd"), "the scheduled send marks it")
    } finally {
        try DirDelete(dir, true)
    }
}

; review 2026-11-12: a refused schedule start focused Roblox every 15 s
Test_App_V17_ScheduleWaitsForARouteTool() {
    t := AppTestMake()
    s := AfFakeSched()
    t.app.sched := s
    t.app._toolBusy := true
    s.acts.Push("start")
    f0 := t.rb.focusCalls
    t.app._ScheduleTick()
    AssertTrue(!t.app._started, "not started while the tool runs")
    AssertEq(t.rb.focusCalls, f0, "Roblox not pulled to the front")
    t.app._toolBusy := false
    s.acts.Push("start")
    t.app._ScheduleTick()
    AssertTrue(t.app._started, "started once the tool is done")
    t.app.Stop("test")
}

; review 2026-11-12: !start while paused resumed but said "Started."
Test_App_V17_RemoteStartWhilePausedSaysResumed() {
    t := AppTestMake()
    h := t.app._RemoteHandlers()
    t.app.Start()
    t.app.Pause()
    AssertEq(h["start"].Call("", ""), "Resumed.", "resumed")
    t.app.Stop("test")
}

; idea 8 (2026-11-13): Home's NEXT UP names the soonest timed task
Test_App_V17_NextUp() {
    t := AppTestMake()
    AssertEq(t.app.NextUp(), "", "stopped: nothing")
    t.app.Start()
    for k in ["quests", "obby", "memorymatch"]
        if t.app._taskMap.Has(k)
            t.app._taskMap.Delete(k)
    t.app._taskMap["quests"] := {name: "quests"}
    t.app.cfg.Set("quests.enabled", 1)
    t.app.cfg.Set("Obby.enabled", 0)
    t.app.cfg.Set("MemoryMatch.enabled", 0)
    t.app.state.questIntervalMs := 30 * 60000
    t.app.state.lastRun["quests"] := t.app.Now() - 18 * 60000
    AssertEq(t.app.NextUp(), "Quests in 12 min", "minutes")
    t.app.state.lastRun["quests"] := t.app.Now() - 31 * 60000
    AssertEq(t.app.NextUp(), "Quests now", "due")
    t.app.state.questIntervalMs := 150 * 60000
    t.app.state.lastRun["quests"] := t.app.Now()
    AssertEq(t.app.NextUp(), "Quests in 2h 30m", "hours")
    t.app.cfg.Set("quests.enabled", 0)
    AssertEq(t.app.NextUp(), "", "nothing on")
    t.app.Stop("test")
}
