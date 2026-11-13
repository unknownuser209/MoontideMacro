#Requires AutoHotkey v2.0
; ---------------------------------------------------------------------------
; Scheduler: pure logic that picks which single task runs next.
; No SetTimer, no screen I/O. Time is injected (ms) so tests never wait.
;
; TASK CONTRACT (implemented by later tasks)
;   .name          string, one of the Sched.Priority keys
;   .priority      int, lower runs first
;   .CanRun(state) -> bool
;   .Run(ctx)      long task; must poll ctx.ShouldStop() between steps
;
; STATE FIELDS read/written (any object with these members works; SchedState
; below is the default implementation)
;   rareActive      bool   read only here; cleared elsewhere when LogWatch
;                          reports a non-rare biome
;   lastRun         Map    task name -> ms timestamp of last run (MarkRun)
;   fishLoops       int    fishing loops since last sell (owned by fishing/sell)
;   questIntervalMs int    min ms between quest runs, default 30 min
;   obbyIntervalMs  int    min ms between obby runs, default 10 min
;   progressAt      int    ms timestamp of the last "fishing progress"
;                          (fishLoops changed or any non-recovery task
;                          completed). Written by RecoveryTask; 0 = unseen.
;   busy            string name of the task currently inside task.Run(), "" when
;                          idle. CONTRACT: the main loop (Task 14) sets it before
;                          task.Run and clears it after. RecoveryTask reads it:
;                          a non-fishing, non-recovery task running counts as
;                          progress, and anti-AFK taps only when busy == "".
;   biome           string current biome (BiomeEvents; "" = unknown)
;   rareTs          string log ts of the live rare-biome event, "" when not
;                          rare (BiomeEvents; PotionsTask matches its event)
;   chatDue         bool   the main loop wants to read the chat: FishingTask
;                          returns between catches so ChatWatch can run
;                          (App sets it every merchant.chatPollSec, clears it
;                          when it checks the chat)
;   stats           Map    session counters (Bump): fishCaught, fishFailed,
;                          falseBites, repaths, sells, fishTypesSold, biomes,
;                          rareBiomes, runs.<task>. Shown in the stop summary.
;   needRepath      bool   a re-path is due: SellTask.CanRun is true and
;                          fishing yields until a sell run finishes (which
;                          clears it). Set by App.Start (General.repathOnStart)
;                          and by FishingTask on a failsafe / false bite.
;   startSell       bool   App.Start: the start trip (sell, buy at the
;                          Fisher in the same visit, walk to fishing) is still
;                          to come; craft waits for it. Quests / biome items
;                          (priority 5) run BEFORE it, so the trip ends at the
;                          fishing spot. Cleared by App when the first sell
;                          run ends (any outcome).
;
; RULES enforced by Scheduler.Next
;   - Lowest .priority among eligible tasks wins; ties go to array order.
;   - rareActive blocks merchant, craft and quests (not potions/recovery/sell).
;   - startSell blocks craft only (the Fisher buy happens inside the start
;     sell). Quests and biome items run first, then sell + buy + fishing.
;   - inLimbo: only limbo and recovery run (Sched.InLimboOk).
;   - limboMode (Limbo.enabled): only limbo, potions, recovery (LimboModeOk).
;   - quests are also gated by questIntervalMs since lastRun["quests"]
;     (never run = due); obby by obbyIntervalMs since lastRun["obby"].
;   - A task with priority >= Sched.FishingPriority (99) skips the rare /
;     interval rules and only asks CanRun (fishing: General.fishing); it is
;     the default when nothing else is.
; ---------------------------------------------------------------------------

class Sched {
    static FishingPriority := 99
    static QuestIntervalMs := 30 * 60 * 1000
    static ObbyIntervalMs := 10 * 60 * 1000
    static Priority := Map(
        "potions", 1,
        "recovery", 2,
        "merchant", 3,
        "craft", 4,
        "biomeitems", 5,
        "quests", 5,
        "obby", 5,
        "memorymatch", 5,
        "minions", 6,
        "sell", 6,
        "limbo", 98,
        "fishing", 99
    )
    ; Task names blocked while state.rareActive.
    static RareBlocked := Map("merchant", true, "craft", true, "quests", true, "biomeitems", true
        , "obby", true, "memorymatch", true, "minions", true)
    ; Task names that wait for the start sell (state.startSell). Quests and
    ; biome items go BEFORE it (quests, sell, buy, fish: no walk back first).
    static AfterStartSell := Map("craft", true)

    ; Obby interval (ms) from a settings value: whole minutes 1..120, anything
    ; else (0, blank, text, too big) falls back to ObbyIntervalMs.
    static ObbyIntervalFrom(v) {
        if (IsInteger(v) && v >= 1 && v <= 120)
            return Integer(v) * 60000
        return Sched.ObbyIntervalMs
    }
    ; The only tasks that run while state.inLimbo (buffs, the island and its
    ; NPCs are out of reach there; LimboTask leaves for a rare biome).
    static InLimboOk := Map("limbo", true, "recovery", true)
    ; With Limbo on (state.limboMode) also on Sol's Island: the rare-biome
    ; potions still run; fishing, selling, crafting, quests, merchants and
    ; biome items do not.
    static LimboModeOk := Map("limbo", true, "recovery", true, "potions", true)
}

class SchedState {
    __New() {
        this.rareActive := false
        this.lastRun := Map()
        this.fishLoops := 0
        this.questIntervalMs := Sched.QuestIntervalMs
        this.obbyIntervalMs := Sched.ObbyIntervalMs
        this.progressAt := 0
        this.busy := ""
        this.biome := ""          ; current biome name (BiomeEvents writes it)
        this.rareTs := ""         ; log ts of the live rare event, "" when not rare (BiomeEvents)
        this.chatDue := false     ; App: chat check wanted; fishing yields between catches
        this.needRepath := false  ; re-path due: Sell (reset + walk + return) runs before fishing
        this.repathStreak := 0    ; re-paths since the last catch (Sell pauses the macro at SellTask.MaxRepathStreak)
        this.startSell := false   ; App.Start: the first sell run is still to come
        this.inLimbo := false     ; LimboTask: the player is in THE LIMBO
        this.ghost := false       ; App: the last join was not the private server (RecoveryTask rejoins)
        this.limboMode := false   ; App: Limbo.enabled (Sched.LimboModeOk only)
        this.stats := Map()       ; session counters for the stop summary (App resets on Start)
        this.onBump := ""         ; App: (key, n) -> the day counters too (DailyStats)
    }

    ; stats[key] += n (and onBump, when set)
    Bump(key, n := 1) {
        this.stats[key] := (this.stats.Has(key) ? this.stats[key] : 0) + n
        if IsObject(this.onBump)
            try this.onBump.Call(key, n)
    }
}

class SchedCtx {
    ; Hotkey handlers (F2/F3) call Pause/Resume/Stop; tasks call ShouldStop().
    ; Preemption (spec section 3): the main loop calls RequestPreempt() when a
    ; higher-priority task becomes runnable while another task is running; the
    ; running task sees ShouldStop() == true at its next safe checkpoint and
    ; returns. The main loop then calls ClearPreempt() before starting the next
    ; task. Resume() does not clear a preempt; Reset() clears everything.
    __New() {
        this._stop := false
        this._paused := false
        this._preempt := false
        this._halt := false
    }
    ; halt: the Roblox window is gone (App stops the task for recovery). Also
    ; a halt for CleanupCtx: closing steps would click on whatever is left on
    ; screen (2026-10-27 review).
    RequestPreempt(halt := false) {
        this._preempt := true
        if halt
            this._halt := true
    }
    ClearPreempt() {
        this._preempt := false
        this._halt := false
    }
    IsPreempted() => this._preempt
    Stop() {
        this._stop := true
    }
    Pause() {
        this._paused := true
    }
    Resume() {
        this._paused := false
    }
    Reset() {
        this._stop := false
        this._paused := false
        this._preempt := false
        this._halt := false
    }
    IsStopped() => this._stop
    IsPaused() => this._paused
    ShouldStop() => this._stop || this._paused || this._preempt
    ; Stopped (F3), paused (F2, Roblox lost focus) or the Roblox window gone:
    ; input must stop now. A plain preempt is not a halt: the task may still
    ; close what it opened.
    IsHalted() => this._stop || this._paused || this._halt
}

; CleanupCtx(ctx): the ctx for a task's closing steps (close a window, leave
; a dialog, respawn, put an aura back) once it was told to stop. ShouldStop()
; only on a real halt (F3, pause, Roblox not in front or gone), not on a preempt: the
; 2026-10-27 review found every preempted task leaving its board / shop /
; inventory / storage open for the next task, and the obby losing the aura.
;   cctx := CleanupCtx(ctx)       CleanupCtx.Halted(ctx) -> bool
; A ctx without IsHalted (route tests: ShouldStop = F3 or not in front) is
; halted exactly when it says ShouldStop.
class CleanupCtx {
    __New(ctx) {
        this._ctx := ctx
    }
    static Halted(ctx) {
        if !IsObject(ctx)
            return false
        return HasMethod(ctx, "IsHalted") ? ctx.IsHalted() : ctx.ShouldStop()
    }
    ShouldStop() => CleanupCtx.Halted(this._ctx)
    IsHalted() => CleanupCtx.Halted(this._ctx)
    ; F3 / pause sent through the cleanup ctx reach the real one
    Stop() => HasMethod(this._ctx, "Stop") ? this._ctx.Stop() : ""
    Pause() => HasMethod(this._ctx, "Pause") ? this._ctx.Pause() : ""
}

; Tidy: the between-tasks check (App, after every task, a preempted one
; too). 2026-11-09 the "Fishing Failed" card a preempted fishing run left
; sat over the screen through the aura swap and the whole HEAVEN hunt.
;   closed := Tidy.Run(taskName, items, ctx, log)   -> labels closed
; items: Array of leftovers, each {up, close} (the tasks' own detectors):
;   up.Call()         -> label of what is on screen ("Fishing Failed card"),
;                        "" when nothing is (one read per detector)
;   close.Call(label, ctx) -> 1 closed | 0 not up | 2 still up | -1 halted
; Nothing seen: no click, no key, no log line (never a blind Esc: on a clean
; screen it opens the Roblox menu). Each close is checked by up() again and
; logged ONCE: "tidy after <task>: closed the <label>" or "tidy after
; <task>: the <label> is still open". A halt (F3, pause, Roblox gone or not
; in front) skips it all; a plain preempt does not (CleanupCtx).
class Tidy {
    static MaxRounds := 4        ; per item: one screen can hide another (ObbyTask.ClearTries)

    static Run(taskName, items, ctx, log := "") {
        closed := []
        if (!IsObject(items) || CleanupCtx.Halted(ctx))
            return closed
        cctx := CleanupCtx(ctx)
        say := (t) => IsObject(log) ? log.Call("tidy after " taskName ": " t) : 0
        for it in items {
            label := Tidy._Up(it)
            Loop Tidy.MaxRounds {
                if (label = "")
                    break
                if cctx.ShouldStop()
                    return closed
                r := 2
                try r := it.close.Call(label, cctx)
                if (r < 0 || cctx.ShouldStop())
                    return closed
                again := Tidy._Up(it)
                if (again = label) {
                    say("the " label " is still open")
                    break
                }
                say("closed the " label)
                closed.Push(label)
                label := again           ; another one under it
            }
        }
        return closed
    }

    static _Up(it) {
        try {
            v := it.up.Call()
            return (v = "" || v = 0) ? "" : String(v)
        }
        return ""
    }
}

class Scheduler {
    ; Returns the task to run now, or "" when `tasks` is empty / nothing eligible.
    ; `now` is ms (e.g. A_TickCount); injected for testability.
    static Next(tasks, state, now := A_TickCount) {
        best := ""
        for t in tasks {
            if !Scheduler.Eligible(t, state, now)
                continue
            if (best == "" || t.priority < best.priority)
                best := t
        }
        return best
    }

    static Eligible(task, state, now := A_TickCount) {
        if (state.HasProp("inLimbo") && state.inLimbo && !Sched.InLimboOk.Has(task.name))
            return false
        if (state.HasProp("limboMode") && state.limboMode && !Sched.LimboModeOk.Has(task.name))
            return false
        if (task.priority >= Sched.FishingPriority)
            return task.CanRun(state) ? true : false
        name := task.name
        if (state.rareActive && Sched.RareBlocked.Has(name))
            return false
        if (state.HasProp("startSell") && state.startSell && Sched.AfterStartSell.Has(name))
            return false
        if (name = "quests" && !Scheduler.QuestDue(state, now))
            return false
        if (name = "obby" && !Scheduler.ObbyDue(state, now))
            return false
        return task.CanRun(state) ? true : false
    }

    static ObbyDue(state, now := A_TickCount) {
        if !state.lastRun.Has("obby")
            return true
        return (now - state.lastRun["obby"]) >= state.obbyIntervalMs
    }

    static QuestDue(state, now := A_TickCount) {
        if !state.lastRun.Has("quests")
            return true
        return (now - state.lastRun["quests"]) >= state.questIntervalMs
    }

    static MarkRun(state, task, now := A_TickCount) {
        state.lastRun[task.name] := now
    }
}
