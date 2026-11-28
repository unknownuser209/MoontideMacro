#Requires AutoHotkey v2.0
; Bug hunt 2026-11-27: App fixes (lib\App.ahk). Uses the App rig from
; test_app.ahk, StuckFakeCard from test_stuckui.ahk and RrNonVipFile from
; test_route_recorder.ahk. Everything is faked: no timers, no windows.

; The rig with a REAL PotionsTask behind the proxy (its _pending / _needClose
; are what a potions save must hand over).
CoreFixPotionsRig() {
    t := AppTestMake(Map("be", "fake"))
    t.app.potionsFactory := (s) => PotionsTask(Map("cfg", t.cfg, "safety", s, "state", t.app.state))
    t.app.potions := ""
    t.app.OnPotionsChanged()                    ; rebuilt with the real task
    return t
}

; live 2026-11-27 15:09:41-15:17:39: one fishing task of 18 catches with no
; biome / chat line, then four held-back biomes in the same second. The task
; thread started on top of the unfinished Tick (AHK runs the -1 timer when
; the Tick is interrupted), so _inTick stayed set and every later Tick
; returned at once. The "sync" launch runs the task right where the launch
; is made, as that interrupt did.
Test_CoreFix_TaskOnTopOfTheTickLeavesTheTickWorking() {
    seen := {d: -1, pre: ""}
    q := AppFakeTask("quests", 5, false)
    fish := AppFakeTask("fishing", 99, true, (self, ctx) => (seen.t.clk.t += App.LogPollMs, q.can := true
        , seen.b := seen.t.lw.polls, seen.t.app.Tick(), seen.d := seen.t.lw.polls - seen.b, seen.pre := ctx.IsPreempted()))
    t := AppTestMake(Map("tasks", Map("fishing", fish, "quests", q), "sync", true))
    seen.t := t
    t.app.Start()
    t.app.Tick()
    AssertEq(fish.runs, 1, "fishing ran")
    AssertEq(seen.d, 1, "the tick during the task still polled the Roblox log")
    AssertEq(seen.pre, true, "and still preempted fishing for the due quests")
    AssertEq(t.app._inTick, false, "cleared")
    ; a launch outside a tick (nothing to wait for) still goes at once
    t2 := AppTestMake()
    t2.app.Start()
    t2.app._Launch(t2.tasks["fishing"])
    AssertEq(t2.launched.Length, 1, "launched at once outside a tick")
}

; A daily quest "Use 3 Lucky Potion" waits; the player saves the Biomes &
; Potions page. The rebuild queued _proxy.last (an old rare biome) instead,
; and DailyQuests never asks again that day.
Test_CoreFix_PotionsSaveKeepsAPendingQuest() {
    t := CoreFixPotionsRig()
    t.app._proxy.Queue("GLITCHED", "ts1")      ; a rare biome hours ago
    old := t.app.potions
    old._pending := ""                          ; ...that ran
    AssertEq(old.QueueQuest("Lucky Potion", 3), true, "quest queued")
    t.cfg.Bump()
    t.app.OnPotionsChanged()
    p := t.app.potions
    AssertTrue(p !== old, "rebuilt")
    ev := p._pending
    AssertTrue(IsObject(ev) && ev.biome = "QUEST", "the quest event survives the save, not the stale biome")
    AssertTrue(ev.HasOwnProp("quest") && ev.quest.qty = 3 && ev.quest.name = "Lucky Potion", "same quest and count")
    ; no rare biome since boot (_proxy.last empty): the quest is kept too
    t2 := CoreFixPotionsRig()
    t2.app.potions.QueueQuest("Lucky Potion", 2)
    t2.cfg.Bump()
    t2.app.OnPotionsChanged()
    ev2 := t2.app.potions._pending
    AssertTrue(IsObject(ev2) && ev2.HasOwnProp("quest") && ev2.quest.qty = 2, "kept with nothing in the proxy")
}

; A rare biome's potion run paused by focus loss (_Requeue: resumes, the
; inventory left open). A save while paused rebuilt the task with a fresh
; {biome, ts}: resumed = false, BeginEvent refused the still-open event and
; every remaining potion was skipped as event_claimed.
Test_CoreFix_PotionsSaveKeepsAPausedEvent() {
    t := CoreFixPotionsRig()
    t.app._proxy.Queue("GLITCHED", "ts9")
    old := t.app.potions
    ev := old._pending
    old._pending := ""                          ; Run took it
    AssertEq(old._Requeue(ev, t.app.ctx), true, "paused: re-queued as the task does")
    old._needClose := true                      ; the pause left the inventory open
    t.cfg.Bump()
    t.app.OnPotionsChanged()
    p := t.app.potions
    AssertTrue(p !== old, "rebuilt")
    AssertTrue(IsObject(p._pending) && p._pending.ts = "ts9", "same event")
    AssertEq(p._pending.HasOwnProp("resumes") ? p._pending.resumes : 0, 1, "resumes kept: the open event goes on")
    AssertEq(p._needClose, true, "the inventory left open is still closed first")
    ; nothing pending: nothing queued (no stale event from the proxy)
    p._pending := ""
    t.cfg.Bump()
    t.app.OnPotionsChanged()
    AssertEq(t.app.potions._pending, "", "nothing pending stays nothing")
}

; F3 / the overlay / Discord "!stop" with the macro already stopped moved
; the mouse to the shift probe and could tap Shift and scroll in Roblox.
Test_CoreFix_StopWhenNotRunningLeavesShiftLockAlone() {
    inp := AppFakeShift()
    t := AppTestMake(Map("input", inp))
    AssertEq(t.app.Stop("F3"), false, "not running")
    AssertEq(inp.shifts.Length, 0, "no probe or Shift tap while stopped")
    t.app.Start()
    t.app.Stop()
    AssertEq(inp.shifts.Length, 1, "a real stop still turns it off")
    t.app.Stop()
    AssertEq(inp.shifts.Length, 1, "a second F3 sends nothing")
    ; a second F3 while the stopped task is still ending (a halted hunt)
    t.app.Start()
    t.app.Tick()                                ; fishing launched, its thread not run yet
    t.app.Stop()
    AssertEq(inp.shifts.Length, 2, "stop with a task")
    t.app.Stop()
    AssertEq(inp.shifts.Length, 3, "the task is still ending: turned off again")
    AppTestRunLaunched(t)
}

; The "Roblox window can't be used" card closed itself after 10 min while
; the same pause was still on: its line is logged once per pause.
Test_CoreFix_PauseFixCardStaysWhilePaused() {
    t := AppTestMake(Map())
    t.app.Start()
    t.rb.fs := false
    t.app.Tick()
    AssertEq(t.app._pauseReason, App.Msg["notfs"][1], "paused for the window")
    t.app.fixit.Seen("Paused: The Roblox window can't be used (x)", t.clk.t)
    c := StuckFakeCard("notfs")
    t.app._fixCard := c
    Loop 50 {
        t.clk.t += 15000
        t.app.Tick()
        t.app._FixCardTick()
    }
    AssertEq(t.app._pauseReason, App.Msg["notfs"][1], "still paused")
    AssertTrue(!c.gone, "notfs card kept while the pause lasts")
    t.rb.fs := true
    t.app.Resume()
    t.app._FixCardTick()
    AssertTrue(c.gone, "closed once the pause is over")
    ; the focus card the same
    t2 := AppTestMake(Map())
    t2.app._frontFn := () => "chrome.exe"       ; not a known focus thief: a plain pause
    t2.app.Start()
    t2.app._PauseFor("unfocused")
    AssertEq(t2.app._pauseReason, App.Msg["unfocused"][1], "paused: focus")
    t2.app.fixit.Seen("Paused: Roblox is not the active window (alt-tab?)", t2.clk.t)
    t2.app.fixit.Seen("Paused: Roblox is not the active window (alt-tab?)", t2.clk.t)
    c2 := StuckFakeCard("focus")
    t2.app._fixCard := c2
    t2.clk.t += App.FixQuietMs * 2
    t2.app._FixCardTick()
    AssertTrue(!c2.gone, "focus card kept while that pause lasts")
    t2.app.Resume()
    t2.app._FixCardTick()
    AssertTrue(c2.gone, "closed after it")
}

; Help > Routes > Test walked the creator's VIP recording for a non-VIP
; player, while the quests task plays the shipped non-VIP walk.
Test_CoreFix_TestRouteNonVipWalksTheNonVipRoute() {
    d := RrNonVipFile()
    keep := RouteRecorder.DefaultsPath
    RouteRecorder.DefaultsPath := d "\def.json"
    try {
        walks := []
        t := AppTestMake(Map("walkRoute", (steps, key, ctx) => (walks.Push(steps), "")))
        last := (i) => walks[i][walks[i].Length][3]
        t.cfg.Set("General.vip", 0)
        t.cfg.routes := Map("quest_board", Map("_recorded", "2026-10-26 13:49", "steps", [["w", "down", 0], ["w", "up", 500]]))
        r := t.app.OnTestRoute("quest_board")
        AssertEq(r.ok, true, "walked: " r.msg)
        AssertEq(last(1), 900, "VIP off: the shipped non-VIP walk, as the task plays it")
        t.cfg.routes := Map("quest_board", Map("_recorded", "2026-11-20 10:00", "steps", [["w", "down", 0], ["w", "up", 650]]))
        t.app.OnTestRoute("quest_board")
        AssertEq(last(2), 650, "VIP off: the player's own recording kept")
        t.cfg.routes := Map()
        r := t.app.OnTestRoute("quest_board")
        AssertEq(r.ok, true, "VIP off, none recorded: the non-VIP walk, not 'not recorded'")
        AssertEq(last(3), 900, "the non-VIP walk")
        t.cfg.Set("General.vip", 1)
        t.cfg.routes := Map("quest_board", Map("_recorded", "2026-10-26 13:49", "steps", [["w", "down", 0], ["w", "up", 500]]))
        t.app.OnTestRoute("quest_board")
        AssertEq(last(4), 500, "VIP on: the VIP walk")
    } finally {
        RouteRecorder.DefaultsPath := keep
        try DirDelete(d, true)
    }
}

; live 2026-11-27 16:50:42: the board was closed, then a craft notification
; preempted quests in its last moment: '(preempted)', no MarkRun, and quests
; walked to the board again a minute later for nothing.
Test_CoreFix_IntervalTaskPreemptedAfterItsWorkIsMarkedRun() {
    t := AppTestMake()
    q := AppFakeTask("quests", 5, true, (self, ctx) => (self.finished := true, t.app.ctx.RequestPreempt()))
    t.app.Start()
    t.app._RunTask(q)
    AssertTrue(t.app.state.lastRun.Has("quests"), "its work was done before the preempt: not due again at once")
    ; cut short before its work: due again (a finished flag left from an
    ; earlier run does not count)
    ob := AppFakeTask("obby", 7, true, (self, ctx) => t.app.ctx.RequestPreempt())
    ob.finished := true
    t.app._RunTask(ob)
    AssertTrue(!t.app.state.lastRun.Has("obby"), "cut short before its work: may run again at once")
}

; ---- follow-ups after the merge (bug hunt 2026-11-27) ---------------------

; craft-2: CraftTask.Reset re-arms the first cauldron visit; Start must call
; it, or an F1 before the cauldron was set up never visits it until restart.
class CoreFixCraftFake extends AppFakeTask {
    __New() {
        super.__New("craft", 50, false)
        this.resets := 0
    }
    Reset() => this.resets++
}
Test_CoreFix_StartResetsTheCraftTask() {
    craft := CoreFixCraftFake()
    t := AppTestMake(Map("tasks", Map("fishing", AppFakeTask("fishing", 99), "craft", craft)))
    t.app.Start()
    AssertEq(craft.resets, 1, "Start re-arms the cauldron visit (CraftTask.Reset)")
    t.app.Stop()
    t.app.Start()
    AssertEq(craft.resets, 2, "every Start, not once per launch")
}

; live-4, task side: quests and obby say when their work got done
; (task.finished), so a preempt in their last moment does not send them
; back at once. Quests: once the board pass returned unstopped.
Test_CoreFix_QuestsSaysWhenTheBoardPassIsDone() {
    board := QmBoardBounce([["Delivery II`nBring 3 crates", "Claim Rewards"]])
    m := QmBoardTask(board)
    AssertTrue(m.t.HasOwnProp("finished"), "QuestsTask has the finished flag")
    m.t.Run(SchedCtx())
    AssertEq(m.t.finished, true, "a full board pass is done")
    ctx := SchedCtx()
    ctx.RequestPreempt()
    board.closed := false
    m.t.finished := false
    m.t.Run(ctx)
    AssertEq(m.t.finished, false, "preempted before the pass: not done")
}

; Obby: only with the blessing seen and no aura left owed.
Test_CoreFix_ObbySaysWhenTheBlessingIsDone() {
    o := QmObbyTask("Glock")
    AssertTrue(o.t.HasOwnProp("finished"), "ObbyTask has the finished flag")
    AssertEq(o.t.Run(SchedCtx()), 1, "blessing claimed")
    AssertEq(o.t.finished, true, "blessing seen, Glock back: done")
    o2 := QmObbyTask("Glock")
    ctx := SchedCtx()
    o2.io.DefineProp("Down", {Call: (self, k) => (self.log.Push("down " k), (k = "w") ? ctx.Pause() : 0)})
    o2.t.Run(ctx)
    AssertEq(o2.t.finished, false, "halted on the walk (aura owed, no blessing): not done")
}
