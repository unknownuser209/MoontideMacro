#Requires AutoHotkey v2.0
; Tests for lib\Scheduler.ahk (pure logic, injected clock, fake tasks).
#Include ..\lib\Scheduler.ahk

; ---- helpers (names must not start with Test_) -----------------------------

class SchedFakeTask {
    __New(name, priority, can := true) {
        this.name := name
        this.priority := priority
        this._can := can
    }
    CanRun(state) => this._can
    Run(ctx) => 0
}

SchedTestAllTasks(canMap := "") {
    ; Every task runnable unless canMap[name] says false; limbo (off unless
    ; Limbo.enabled) only when canMap says so.
    tasks := []
    for name, prio in Sched.Priority {
        can := (canMap is Map && canMap.Has(name)) ? canMap[name] : (name != "limbo")
        tasks.Push(SchedFakeTask(name, prio, can))
    }
    return tasks
}

; ---- tests -----------------------------------------------------------------

Test_Sched_PotionsPreemptAll() {
    state := SchedState()
    t := Scheduler.Next(SchedTestAllTasks(), state, 0)
    AssertEq(t.name, "potions", "potions first when all runnable")
    ; Shuffled input order must not matter.
    tasks := SchedTestAllTasks()
    rev := []
    Loop tasks.Length
        rev.Push(tasks[tasks.Length - A_Index + 1])
    AssertEq(Scheduler.Next(rev, state, 0).name, "potions", "order independent")
    ; Potions not runnable -> recovery next.
    t := Scheduler.Next(SchedTestAllTasks(Map("potions", false)), state, 0)
    AssertEq(t.name, "recovery", "recovery after potions")
    ; Potions runnable even while rare is active.
    state.rareActive := true
    AssertEq(Scheduler.Next(SchedTestAllTasks(), state, 0).name, "potions", "potions during rare")
}

Test_Sched_RareBlocksQuestsMerchantCraft() {
    state := SchedState()
    state.rareActive := true
    can := Map("potions", false, "recovery", false, "sell", false)
    ; merchant, craft, quests all CanRun but rare blocks them -> fishing.
    AssertEq(Scheduler.Next(SchedTestAllTasks(can), state, 0).name, "fishing", "rare blocks m/c/q")
    ; Sell is not blocked by rare.
    can.Delete("sell")
    AssertEq(Scheduler.Next(SchedTestAllTasks(can), state, 0).name, "sell", "sell not blocked")
    ; Recovery not blocked by rare.
    can := Map("potions", false)
    AssertEq(Scheduler.Next(SchedTestAllTasks(can), state, 0).name, "recovery", "recovery not blocked")
    ; Rare cleared -> merchant allowed again.
    state.rareActive := false
    can := Map("potions", false, "recovery", false)
    AssertEq(Scheduler.Next(SchedTestAllTasks(can), state, 0).name, "merchant", "merchant when not rare")
    ; Craft and quests individually blocked.
    state.rareActive := true
    for nm in ["craft", "quests"] {
        only := [SchedFakeTask(nm, Sched.Priority[nm]), SchedFakeTask("fishing", 99)]
        AssertEq(Scheduler.Next(only, state, 0).name, "fishing", nm " blocked by rare")
    }
}

Test_Sched_QuestIntervalDefault30Min() {
    state := SchedState()
    AssertEq(state.questIntervalMs, 1800000, "default 30 min")
    tasks := [SchedFakeTask("quests", 5), SchedFakeTask("fishing", 99)]
    ; Never run -> due immediately.
    AssertEq(Scheduler.Next(tasks, state, 100000).name, "quests", "never run is due")
    Scheduler.MarkRun(state, tasks[1], 100000)
    AssertEq(state.lastRun["quests"], 100000, "MarkRun stores lastRun")
    ; 1 ms short of 30 min -> not due.
    AssertEq(Scheduler.Next(tasks, state, 100000 + 1799999).name, "fishing", "29:59.999 not due")
    ; Exactly 30 min -> due.
    AssertEq(Scheduler.Next(tasks, state, 100000 + 1800000).name, "quests", "30:00 due")
    ; Custom interval honoured.
    state.questIntervalMs := 60000
    AssertEq(Scheduler.Next(tasks, state, 100000 + 60000).name, "quests", "custom interval due")
    AssertEq(Scheduler.Next(tasks, state, 100000 + 59999).name, "fishing", "custom interval not due")
    ; CanRun false still blocks even when due.
    off := [SchedFakeTask("quests", 5, false), SchedFakeTask("fishing", 99)]
    AssertEq(Scheduler.Next(off, SchedState(), 0).name, "fishing", "CanRun false blocks")
}

Test_Scheduler_ObbyInterval() {
    state := SchedState()
    AssertEq(state.obbyIntervalMs, 600000, "default obby interval 10 min")
    AssertEq(Sched.Priority["obby"], 5, "obby priority 5")
    tasks := [SchedFakeTask("obby", 5), SchedFakeTask("fishing", 99)]
    AssertEq(Scheduler.Next(tasks, state, 0).name, "obby", "never run is due")
    Scheduler.MarkRun(state, tasks[1], 1000)
    AssertEq(Scheduler.Next(tasks, state, 1000 + 9 * 60000).name, "fishing", "9 min not due")
    AssertEq(Scheduler.Next(tasks, state, 1000 + 10 * 60000).name, "obby", "10 min due")
    AssertTrue(!Scheduler.ObbyDue(state, 1000 + 9 * 60000), "ObbyDue false at 9 min")
    AssertTrue(Scheduler.ObbyDue(state, 1000 + 10 * 60000), "ObbyDue true at 10 min")
    fresh := SchedState()
    AssertTrue(Scheduler.ObbyDue(fresh, 0), "ObbyDue true when never run")
    fresh.rareActive := true
    AssertTrue(!Scheduler.Eligible(tasks[1], fresh, 0), "obby blocked by rareActive")
}

Test_Scheduler_ObbyIntervalFrom() {
    AssertEq(Sched.ObbyIntervalFrom(5), 300000, "5 min")
    AssertEq(Sched.ObbyIntervalFrom(120), 7200000, "120 min")
    AssertEq(Sched.ObbyIntervalFrom(0), 600000, "0 -> default")
    AssertEq(Sched.ObbyIntervalFrom(""), 600000, "blank -> default")
    AssertEq(Sched.ObbyIntervalFrom("abc"), 600000, "text -> default")
    AssertEq(Sched.ObbyIntervalFrom(500), 600000, "over 120 -> default")
}

Test_Scheduler_MemoryMatchRareBlocked() {
    AssertEq(Sched.Priority["memorymatch"], 5, "memorymatch priority 5")
    mm := SchedFakeTask("memorymatch", 5)
    state := SchedState()
    AssertTrue(Scheduler.Eligible(mm, state, 0), "eligible normally")
    state.rareActive := true
    AssertTrue(!Scheduler.Eligible(mm, state, 0), "blocked by rareActive")
    state := SchedState()
    state.limboMode := true
    AssertTrue(!Scheduler.Eligible(mm, state, 0), "blocked by limboMode")
}

Test_Sched_StartSellsThenBuys() {
    ; on Start: quests / biome items first, then the sell trip (it buys in the
    ; same visit and ends at the fishing spot); craft waits for that trip
    state := SchedState()
    state.startSell := true
    tasks := [SchedFakeTask("craft", 4), SchedFakeTask("quests", 5), SchedFakeTask("sell", 6), SchedFakeTask("fishing", 99)]
    AssertEq(Scheduler.Next(tasks, state, 0).name, "quests", "quests first")
    Scheduler.MarkRun(state, tasks[2], 0)
    AssertEq(Scheduler.Next(tasks, state, 1).name, "sell", "then the sell + buy trip")
    AssertEq(Scheduler.Next([SchedFakeTask("biomeitems", 5), SchedFakeTask("sell", 6)], state, 1).name, "biomeitems", "biome items before it too")
    state.startSell := false                  ; the start sell ran
    AssertEq(Scheduler.Next(tasks, state, 1).name, "craft", "craft no longer held (cauldron part)")
    ; potions / recovery / merchant are never held back
    state.startSell := true
    AssertEq(Scheduler.Next([SchedFakeTask("merchant", 3), SchedFakeTask("sell", 6)], state, 0).name, "merchant", "merchant not blocked")
    AssertEq(SchedState().startSell, false, "SchedState declares startSell = false")
}

Test_Sched_FishingDefault() {
    state := SchedState()
    ; Fishing only asks its own CanRun (General.fishing); no interval/rare rule.
    tasks := [SchedFakeTask("fishing", 99)]
    AssertEq(Scheduler.Next(tasks, state, 0).name, "fishing", "fishing runnable")
    state.rareActive := true
    AssertEq(Scheduler.Next(tasks, state, 0).name, "fishing", "rare biome does not block fishing")
    state.rareActive := false
    AssertEq(Scheduler.Next([SchedFakeTask("fishing", 99, false)], state, 0), "", "fishing switched off -> nothing (idle)")
    AssertEq(Scheduler.Next([SchedFakeTask("quests", 5), SchedFakeTask("fishing", 99, false)], state, 0).name, "quests", "only the quest board runs")
    ; Nothing else runnable -> fishing.
    can := Map("potions", false, "recovery", false, "merchant", false, "craft", false, "biomeitems", false, "quests", false, "dailyquests", false, "obby", false, "memorymatch", false, "minions", false, "sell", false)
    AssertEq(Scheduler.Next(SchedTestAllTasks(can), state, 0).name, "fishing", "default fishing")
    ; Sell outranks fishing.
    can.Delete("sell")
    AssertEq(Scheduler.Next(SchedTestAllTasks(can), state, 0).name, "sell", "sell before fishing")
    ; Empty list -> "".
    AssertEq(Scheduler.Next([], state, 0), "", "no tasks")
    ; Priority table values.
    AssertEq(Sched.Priority["potions"], 1, "prio potions")
    AssertEq(Sched.Priority["recovery"], 2, "prio recovery")
    AssertEq(Sched.Priority["merchant"], 3, "prio merchant")
    AssertEq(Sched.Priority["craft"], 4, "prio craft")
    AssertEq(Sched.Priority["quests"], 5, "prio quests")
    AssertEq(Sched.Priority["sell"], 6, "prio sell")
    AssertEq(Sched.Priority["fishing"], 99, "prio fishing")
}

Test_Sched_CtxStopPause() {
    ctx := SchedCtx()
    AssertEq(ctx.ShouldStop(), false, "fresh ctx runs")
    ctx.Pause()
    AssertEq(ctx.ShouldStop(), true, "paused stops")
    AssertEq(ctx.IsPaused(), true, "IsPaused")
    ctx.Resume()
    AssertEq(ctx.ShouldStop(), false, "resumed")
    ctx.Stop()
    AssertEq(ctx.ShouldStop(), true, "stopped")
    AssertEq(ctx.IsStopped(), true, "IsStopped")
    ctx.Resume()
    AssertEq(ctx.ShouldStop(), true, "resume does not clear stop")
    ctx.Reset()
    AssertEq(ctx.ShouldStop(), false, "reset clears")
}

Test_Sched_CtxPreempt() {
    ctx := SchedCtx()
    ctx.RequestPreempt()
    AssertEq(ctx.IsPreempted(), true, "IsPreempted")
    AssertEq(ctx.ShouldStop(), true, "preempt stops task")
    ctx.Resume()
    AssertEq(ctx.ShouldStop(), true, "resume does not clear preempt")
    ctx.ClearPreempt()
    AssertEq(ctx.ShouldStop(), false, "ClearPreempt clears")
    ctx.RequestPreempt()
    ctx.Reset()
    AssertEq(ctx.IsPreempted(), false, "Reset clears preempt")
    AssertEq(ctx.ShouldStop(), false, "Reset clears ShouldStop")
}

Test_Sched_CleanupCtxIgnoresOnlyThePreempt() {
    ctx := SchedCtx()
    c := CleanupCtx(ctx)
    ctx.RequestPreempt()
    AssertEq(ctx.ShouldStop(), true, "the task itself stops on a preempt")
    AssertEq(c.ShouldStop(), false, "its cleanup still runs")
    ctx.Pause()
    AssertEq(c.ShouldStop(), true, "a pause (or Roblox losing focus) halts the cleanup")
    ctx.Reset()
    ctx.Stop()
    AssertEq(c.ShouldStop(), true, "F3 halts the cleanup")
    ctx.Reset()
    ctx.RequestPreempt()
    ctx.RequestPreempt(true)
    AssertEq(c.ShouldStop(), true, "the Roblox window gone halts the cleanup, even on top of a preempt")
    ctx.ClearPreempt()
    AssertEq(ctx.IsHalted(), false, "ClearPreempt clears the window-gone halt")
    ; a ctx without IsHalted (route tests): halted when it says ShouldStop
    rt := {stopped: false}
    rt.DefineProp("ShouldStop", {Call: (self) => self.stopped})
    AssertEq(CleanupCtx.Halted(rt), false, "route ctx running")
    rt.stopped := true
    AssertEq(CleanupCtx(rt).ShouldStop(), true, "route ctx stopped")
}

Test_Sched_NextTwoArgs() {
    state := SchedState()
    tasks := [SchedFakeTask("quests", 5), SchedFakeTask("fishing", 99)]
    ; Default now = A_TickCount; never run -> due.
    AssertEq(Scheduler.Next(tasks, state).name, "quests", "2-arg Next, quests due")
    Scheduler.MarkRun(state, tasks[1])
    AssertTrue(state.lastRun["quests"] > 0, "MarkRun default now")
    AssertEq(Scheduler.Next(tasks, state).name, "fishing", "2-arg Next, quests just ran")
    AssertEq(Scheduler.QuestDue(state), false, "QuestDue default now")
}
