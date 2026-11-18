#Requires AutoHotkey v2.0
; Tests for lib\tasks\DailyQuests.ahk: a fake Daily Quests window (reads
; react to the clicks) and the real frames daily_quests_*.
#Include ..\lib\tasks\DailyQuests.ahk

; ---- helpers (names must not start with Test_) -----------------------------

; The window: rows Map y -> {name, done, claimed}; free = free rerolls left;
; queue = the names rerolls bring.
class DqWin {
    __New(rows, queue := "", free := 3) {
        this.rows := rows, this.queue := IsObject(queue) ? queue : [], this.free := free
        this.open := false, this.sel := 0, this.opens := true, this.bought := 0, this.badClaims := 0
        this.panelLie := false, this.purchase := false
    }
    Click(x, y) {
        D := DailyQuestsTask
        if (x = D.OpenPt[1] && y = D.OpenPt[2])
            this.open := this.opens ? true : this.open
        if !this.open
            return
        if (x = D.ClosePt[1] && y = D.ClosePt[2])
            this.open := false, this.sel := 0
        else if (x = D.RowX && (this.rows.Has(y) || y = D.BonusY))
            this.sel := y
        else if (x = D.ClaimPt[1] && y = D.ClaimPt[2] && this.sel) {
            r := this._Sel()
            if (r.done && !r.claimed)
                r.claimed := true
            else if !r.done
                this.badClaims++
        } else if (x = D.RerollPt[1] && y = D.RerollPt[2] && this.sel && this.rows.Has(this.sel)) {
            r := this.rows[this.sel]
            if r.done
                return
            if (this.free <= 0) {
                this.bought++
                return
            }
            this.free--
            r.name := this.queue.Length ? this.queue.RemoveAt(1) : r.name
        }
    }
    _Sel() {
        if this.rows.Has(this.sel)
            return this.rows[this.sel]
        all := true
        for y, r in this.rows
            all := all && r.done
        if !this.HasOwnProp("bonus")
            this.bonus := {name: "Good job today", done: all, claimed: false}
        this.bonus.done := all
        return this.bonus
    }
    Ocr(x, y, w, h, scale := 1) {
        D := DailyQuestsTask
        if (x = Input.PurchaseBox.x && y = Input.PurchaseBox.y)
            return this.purchase ? "Buy Robux and item" : ""
        if !this.open
            return ""
        if (x = D.TitleBox.x && y = D.TitleBox.y)
            return "noily Ouests"
        if (x = D.RowBox.x) {
            ry := y + D.RowBox.up
            if (ry = D.BonusY)
                return "Good job todoy`nComplete 011 3 doily quests"
            return this.rows.Has(ry) ? this.rows[ry].name : ""
        }
        if !this.sel
            return ""
        r := this._Sel()
        if (x = D.PanelBox.x && y = D.PanelBox.y)
            return this.panelLie ? "Something else entirely" : r.name
        if (x = D.RerollBox.x && y = D.RerollBox.y)
            return (r.done || this.sel = D.BonusY) ? "" : (this.free > 0 ? "Reroll Quest`n[" this.free "/3]" : "Buv Reroll`n10R$")
        if (x = D.ClaimBox.x && y = D.ClaimBox.y)
            return r.claimed ? "Claimed" : "Claim Rewords"
        return ""
    }
}

class DqIO extends QmIO {
    __New(win) {
        super.__New()
        this.win := win, this.last := [0, 0]
    }
    MoveTo(x, y) {
        this.last := [x, y]
        super.MoveTo(x, y)
    }
    ClickHere() {
        super.ClickHere()
        this.win.Click(this.last[1], this.last[2])
    }
}

DqRows(specs*) {
    m := Map(), ys := DailyQuestsTask.RowYs
    for i, s in specs
        m[ys[i]] := {name: s[1], done: s[2], claimed: s.Length > 2 ? s[3] : false}
    return m
}

; -> {t, win, io, wh, logs, clock}
DqTask(win, gets := "") {
    g := Map("DailyQuests.enabled", 1, "DailyQuests.reroll", "craft, fish")
    if (gets is Map)
        for k, v in gets
            g[k] := v
    io := DqIO(win), wh := QmWh(), logs := [], clock := QmClock(0)
    t := DailyQuestsTask({cfg: QmCfg(g), io: io, webhook: wh, cal: QmCal(), log: (s) => logs.Push(s)
        , ocr: (x, y, w, h, scale := 1) => win.Ocr(x, y, w, h, scale), now: () => clock.t})
    return {t: t, win: win, io: io, wh: wh, logs: logs, clock: clock}
}

DqLogged(d, part) {
    for l in d.logs
        if InStr(l, part)
            return true
    return false
}

; ---- tests -----------------------------------------------------------------

Test_DailyQuests_ClaimsFinishedRerollsUnwanted() {
    win := DqWin(DqRows(["Roll 100 times", true], ["Craft Fortune Potion II", false], ["Play Sol's RNG for 30 minutes", false])
        , ["Craft Heavenly Potion", "Collect 10 Lucky Potions"])
    d := DqTask(win)
    AssertEq(d.t.Run(SchedCtx()), 3, "1 claim + 2 rerolls")
    AssertTrue(win.rows[699].claimed, "the finished quest claimed")
    AssertEq(win.rows[797].name, "Collect 10 Lucky Potions", "craft rerolled until it was not craft")
    AssertEq(win.free, 1, "two free rerolls used")
    AssertEq(win.rows[897].name, "Play Sol's RNG for 30 minutes", "a wanted quest kept")
    AssertEq(win.badClaims, 0, "Claim never pressed on an unfinished quest")
    AssertTrue(!win.open, "closed by its X")
    AssertEq(d.wh.Count("quests"), 1, "one quests webhook")
    AssertTrue(DqLogged(d, "rerolled 'Craft Fortune Potion II' -> 'Craft Heavenly Potion'"), "each reroll logged")
}

Test_DailyQuests_NeverBuysAReroll() {
    win := DqWin(DqRows(["Roll 100 times", true, true], ["Craft Fortune Potion II", false], ["Catch 5 fish", false]), ["Craft X", "Craft Y"], 0)
    d := DqTask(win)
    d.t.Run(SchedCtx())
    AssertEq(win.bought, 0, "Buy Reroll never pressed")
    AssertEq(QmClicksAt(d.io, DailyQuestsTask.RerollPt[1] "," DailyQuestsTask.RerollPt[2]), 0, "no click on the reroll spot at all")
    AssertTrue(DqLogged(d, "no free rerolls left: never bought"), "said why")
    AssertTrue(!win.open, "closed")
}

Test_DailyQuests_ClaimedAndBonus() {
    win := DqWin(DqRows(["Roll 100 times", true, true], ["Collect 10 Lucky Potions", true], ["Play Sol's RNG for 30 minutes", true]))
    d := DqTask(win)
    AssertEq(d.t.Run(SchedCtx()), 3, "two claims + the bonus")
    AssertTrue(win.rows[797].claimed && win.rows[897].claimed, "both finished quests claimed")
    AssertTrue(win.bonus.claimed, "Good job today claimed once all 3 are done")
    AssertTrue(DqLogged(d, "'Roll 100 times' already claimed"), "the claimed one left alone")
}

Test_DailyQuests_NoBonusUntilAllDone() {
    win := DqWin(DqRows(["Roll 100 times", true], ["Collect 10 Lucky Potions", false], ["Play Sol's RNG for 30 minutes", true]))
    d := DqTask(win)
    d.t.Run(SchedCtx())
    AssertTrue(!d.io.Moved(DailyQuestsTask.RowX, DailyQuestsTask.BonusY), "the bonus row not even selected")
    AssertEq(win.badClaims, 0, "no claim on unfinished")
}

Test_DailyQuests_WindowNotOpenNothingElse() {
    win := DqWin(DqRows(["Roll 100 times", true]))
    win.opens := false
    d := DqTask(win)
    AssertEq(d.t.Run(SchedCtx()), 0, "nothing done")
    AssertEq(d.io.Clicks(), 1, "only the button")
    AssertTrue(DqLogged(d, "did not open"), "logged")
}

Test_DailyQuests_PanelMismatchLeavesTheRow() {
    win := DqWin(DqRows(["Roll 100 times", true], ["Craft Fortune Potion II", false], ["Catch 5 fish", false]), ["Craft Z"])
    win.panelLie := true
    d := DqTask(win)
    AssertEq(d.t.Run(SchedCtx()), 0, "nothing claimed or rerolled")
    AssertTrue(!win.rows[699].claimed, "not claimed blind")
    AssertEq(win.free, 3, "no reroll blind")
}

Test_DailyQuests_NoClickUnderAPurchasePrompt() {
    win := DqWin(DqRows(["Roll 100 times", true]))
    win.open := true, win.purchase := true
    d := DqTask(win)
    d.t.Run(SchedCtx())
    AssertTrue(!win.rows[699].claimed, "nothing clicked while a Roblox prompt reads")
}

; A "Use N <potion>" row: the potion task gets it only after the window is
; closed. Queued mid-visit, the waiting potion event preempted the visit, so
; the rows after it (here a claim) were never done.
Test_DailyQuests_PotionQuestQueuedAfterTheWindow() {
    win := DqWin(DqRows(["Use 10 Lucky Potions", false], ["Roll 100 times", true], ["Play Sol's RNG for 30 minutes", false]))
    io := DqIO(win), wh := QmWh(), logs := [], clock := QmClock(0), ctx := SchedCtx()
    calls := []
    pq := (p, n) => (calls.Push({p: p, n: n, open: win.open}), ctx.RequestPreempt(), true)   ; as the App's monitor would
    w := DailyQuestsTask.BarX1 - DailyQuestsTask.BarX0 + 1
    bar := []
    Loop w
        bar.Push(A_Index <= w * 3 // 10 ? 0xFFFFFF : 0x202020)              ; 3/10 done
    t := DailyQuestsTask({cfg: QmCfg(Map("DailyQuests.enabled", 1, "DailyQuests.usePotions", 1)), io: io, webhook: wh
        , cal: QmCal(), log: (s) => logs.Push(s), ocr: (x, y, wd, h, scale := 1) => win.Ocr(x, y, wd, h, scale)
        , now: () => clock.t, rect: (x, y, wd, h) => bar, potionQuest: pq})
    t.Run(ctx)
    AssertEq(calls.Length, 1, "one potion request")
    AssertEq(calls.Length ? calls[1].p "|" calls[1].n : "", "Lucky Potion|7", "the potion and the uses left")
    AssertTrue(calls.Length && !calls[1].open, "asked once the window was closed")
    AssertTrue(win.rows[797].claimed, "the row after it still claimed")
    AssertEq(win.free, 3, "the potion quest never rerolled")
}

; The same uses are asked for once a day (dry run / none owned: the bar never
; moves, and every visit opened the inventory again); a moved bar asks again.
Test_DailyQuests_PotionQuestAskedOncePerBar() {
    win := DqWin(DqRows(["Use 10 Lucky Potions", false], ["Roll 100 times", true, true], ["Play Sol's RNG for 30 minutes", false]))
    io := DqIO(win), logs := [], clock := QmClock(0)
    calls := []
    w := DailyQuestsTask.BarX1 - DailyQuestsTask.BarX0 + 1
    fill := w * 2 // 10
    rect := (x, y, wd, h) => DqFill(w, fill)
    t := DailyQuestsTask({cfg: QmCfg(Map("DailyQuests.enabled", 1, "DailyQuests.usePotions", 1)), io: io, webhook: QmWh()
        , cal: QmCal(), log: (s) => logs.Push(s), ocr: (x, y, wd, h, scale := 1) => win.Ocr(x, y, wd, h, scale)
        , now: () => clock.t, rect: rect, potionQuest: (p, n) => (calls.Push(n), true)})
    t.Run(SchedCtx())
    t.Run(SchedCtx())
    AssertEq(calls.Length, 1, "the same 8 asked for once")
    fill := w * 3 // 10                                                     ; 3/10 now
    t.Run(SchedCtx())
    AssertEq(calls.Length, 2, "the bar moved: the rest asked for")
    AssertEq(calls.Length = 2 ? calls[2] : 0, 7, "7 left")
}

DqFill(w, fill) {
    bar := []
    Loop w
        bar.Push(A_Index <= fill ? 0xFFFFFF : 0x202020)
    return bar
}

Test_DailyQuests_CanRunAndInterval() {
    win := DqWin(DqRows(["Roll 100 times", true]))
    d := DqTask(win, Map("DailyQuests.intervalMin", 20))
    AssertTrue(d.t.CanRun(SchedState()), "due at first")
    d.t.Run(SchedCtx())
    AssertTrue(!d.t.CanRun(SchedState()), "not again right away")
    d.clock.t += 19 * 60000
    AssertTrue(!d.t.CanRun(SchedState()), "not before 20 min")
    d.clock.t += 60000
    AssertTrue(d.t.CanRun(SchedState()), "due after 20 min")
    off := DqTask(win, Map("DailyQuests.enabled", 0))
    AssertTrue(!off.t.CanRun(SchedState()), "off by default switch")
    bad := DqTask(win, Map("DailyQuests.intervalMin", 1))
    AssertEq(bad.t.IntervalMs(), 30 * 60000, "out of range -> 30 min")
}

Test_DailyQuests_SchedulerContract() {
    ; live 2026-11-13 22:53: the real scheduler read t.priority, which was
    ; missing -> "Scheduler error" and the macro paused at every F1
    d := DqTask(DqWin(DqRows(["Roll 100 times", true])))
    AssertEq(d.t.name, "dailyquests", "name")
    AssertEq(d.t.priority, Sched.Priority["dailyquests"], "priority as the scheduler's table")
    st := SchedState()
    t := Scheduler.Next([d.t, SchedFakeTask("fishing", 99)], st, 0)
    AssertEq(IsObject(t) ? t.name : "", "dailyquests", "picked by the real scheduler before fishing")
    ; every default task the App builds answers the contract
    a := AppTestMake(Map("defaultTasks", 1))
    for name, task in a.app._taskMap {
        AssertTrue(task.HasProp("priority") && IsNumber(task.priority), name ": has a priority")
        AssertEq(task.name, name, name ": its name")
    }
}

Test_DailyQuests_RerollWords() {
    AssertTrue(!DailyQuestsTask.Wanted("Craft Fortune Potion II", ["craft"]), "craft matched")
    AssertTrue(DailyQuestsTask.Wanted("Aircraft show", ["craft"]), "whole words only")
    AssertTrue(DailyQuestsTask.Wanted("Roll 100 times", []), "no words: everything kept")
    AssertTrue(DailyQuestsTask.Same("Ploy sol's RNG for ao`nminutes", "Ploy Sol's RNG for 30 minutes"), "panel wraps and misreads digits")
    AssertTrue(!DailyQuestsTask.Same("Collect 10 Lucky Potions", "Roll 100 times"), "another quest")
}

Test_DailyQuests_RealFrames() {
    ; live 2026-11-13 22:16 (2560x1440): a claimed quest selected, then an
    ; unfinished one with the free rerolls used ("Buy Reroll 10R$")
    D := DailyQuestsTask
    mk := (f) => DailyQuestsTask({cfg: QmCfg(Map()), io: QmIO(), ocr: (x, y, w, h, scale := 1) => ScrRead(f, {x: x, y: y, w: w, h: h}, scale)})
    t := mk("daily_quests_claimed_1440")
    AssertTrue(t.TitleUp(), "claimed frame: the title reads")
    AssertEq(t._RowName(699), "Roll 100 times", "row 1 name")
    AssertTrue(InStr(t._RowName(897), "Lucky Potions"), "row 3 name")
    s := t._State()
    AssertEq(s.reroll, "", "finished: no reroll button")
    AssertEq(s.claim, "claimed", "Claimed reads")
    t := mk("daily_quests_buy_reroll_1440")
    s := t._State()
    AssertEq(s.reroll, "paid", "Buy Reroll is paid (never pressed)")
    AssertEq(s.claim, "claim", "Claim Rewards reads")
    b := D.PanelBox
    AssertTrue(D.Same(ScrRead("daily_quests_buy_reroll_1440", b), t._RowName(797)), "the panel shows the selected row")
    ; the user's screenshot (2000x1125, scaled up): a free reroll left
    t := mk("daily_quests_reroll_user_upscaled")
    AssertTrue(t.TitleUp(), "user frame: the title reads")
    AssertEq(t._State().reroll, "free", "Reroll Quest [3/3] is free")
    ; no other frame shows the window
    Loop Files A_ScriptDir "\screens\*.*" {
        if InStr(A_LoopFileName, "daily_quests")
            continue
        tb := D.TitleBox
        AssertTrue(!RegExMatch(Ocr.ReadFile(A_LoopFileFullPath, tb.x, tb.y, tb.w, tb.h), D.TitleRe), A_LoopFileName ": no Daily Quests window")
    }
}

; live 2026-11-14 (Roblox windowed at 1920x1200): the window scales evenly
; and is centred; read stretched, the title box fell below the title and
; the window was left open over the next task (sell)
Test_DailyQuests_WindowedFrameReads() {
    f := ScrPath("daily_quests_1920x1200_window")
    rd := (x, y, w, h, scale := 1) => Ocr.ReadFile(f, x, y, w, h, scale)     ; Ocr maps design -> client itself
    t := DailyQuestsTask({cfg: QmCfg(Map()), io: QmIO(), ocr: rd})
    try {
        Screen.SetClient(0, 0, 1920, 1200)
        AssertTrue(t.TitleUp(), "the title reads at 1920x1200")
        AssertEq(Screen.Mode, "S", "the mode is put back")
        n := Screen.WithMode("C", () => t._RowName(699))
        AssertTrue(InStr(n, "Roll") && InStr(n, "times"), "row 1 name (" n ")")
        x := Screen.WithMode("C", () => Screen.Pt(DailyQuestsTask.ClosePt[1], DailyQuestsTask.ClosePt[2]))
        AssertTrue(Abs(x.x - 1418) <= 8 && Abs(x.y - 357) <= 8, "the X maps onto the X (" x.x "," x.y ")")
    } finally
        Screen.Reset()
}
