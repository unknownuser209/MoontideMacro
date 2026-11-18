#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\TaskEnv.ahk
#Include %A_LineFile%\..\..\QuestMatch.ahk
; ---------------------------------------------------------------------------
; DailyQuestsTask: claims the finished daily quests and rerolls the unwanted
; ones (2026-11-13, the user's ask: "like the quest board").
;
;   t := DailyQuestsTask(deps)  deps as TaskEnv (cfg, webhook, log, io, cal, ocr, now)
;   t.name = "dailyquests", t.priority = 5   (Scheduler task contract)
;   t.CanRun(state) -> DailyQuests.enabled (default 0) and the interval
;                      (DailyQuests.intervalMin, 5..720, default 30) since
;                      the last run (any outcome) has passed.
;   t.Run(ctx)      -> number of claims + rerolls.
;   t.Leftovers()   -> the window left open (App tidy: closed by its X).
;
; THE WINDOW (live 2026-11-13, 2560x1440; real frames daily_quests_*):
; opened by the checklist button on the left sidebar (OpenPt; Setup step
; daily_quests_open overrides it). Title "Daily Quests" (reads "noily
; Ouests"), X top right. Right: the "Good job today" bonus row (all 3 done)
; and the 3 quest rows; a click on a row selects it. Left: the selected
; quest's text, then, ONLY while it is unfinished, "Reroll Quest [n/3]"
; (free) - or "Buy Reroll 10R$" once the free ones are used (REAL ROBUX:
; never pressed) - and at the bottom "Claim Rewards" / "Claimed".
;
; RUN: open (the title must read) -> for each quest row: read its name,
; click it, check the left panel shows that quest, then
;   panel has no reroll button + button reads "Claim Rewards" -> Claim
;   (finished, not claimed); "Claimed" -> nothing;
;   unfinished + its name holds a word of DailyQuests.reroll (comma list)
;   -> "Reroll Quest" only while that exact wording reads (never Buy / R$),
;   up to MaxRerolls per row while the new quest still holds a word.
; The bonus row is claimed the same way once all 3 rows read finished.
; Every click: shift lock off first (Input.ClickGuard), never with a Roblox
; purchase prompt up. Closed by its X at the end (also when stopped).
; ---------------------------------------------------------------------------

class DailyQuestsTask {
    static OpenPt := [42, 826]                         ; the sidebar's checklist button
    static TitleBox := {x: 1110, y: 375, w: 340, h: 50}
    static TitleRe := "i)[ao]ily\s*[o0q]u[ec]"
    static ClosePt := [1892, 397]
    static BonusY := 575
    static RowYs := [699, 797, 897]                    ; the 3 quests (their name line)
    static RowX := 1300                                ; click spot on a row (its name)
    static RowBox := {x: 1060, up: 22, w: 760, h: 46}  ; a row's name line
    static PanelBox := {x: 650, y: 470, w: 364, h: 90} ; the selected quest's text
    static RerollBox := {x: 690, y: 738, w: 284, h: 60}
    static RerollPt := [832, 759]
    static FreeRe := "i)rer[o0]ll\s*[oq0n]u[ec]s"      ; "Reroll Quest": free (reads "Reroll Ouest")
    static PaidRe := "i)\bb[uo]y\b|\b[bh]uv\b|r\s*\$|robux"   ; "Buy Reroll 10R$" (reads "Buv", "Huv")
    static ClaimBox := {x: 700, y: 1000, w: 264, h: 56}
    static ClaimPt := [832, 1028]
    static ClaimRe := "i)cl[ao0]i?m\s*rew"
    static ClaimedRe := "i)cl[ao0]i?m[eo]d"
    static OpenWaitMs := 2500
    static PollMs := 150
    static HoverMs := 150
    static SelectMs := 500        ; after a row click (the panel redraws)
    static ClaimMs := 700
    static RerollMs := 1000
    static MaxRerolls := 3        ; per row per run
    static MatchMin := 0.7        ; the panel shows the row's quest (letters, similarity)
    ; "Use 10 Lucky Potion" (2026-11-17): its progress is the row's bar (the
    ; "0/10" on it is too small to read): white fill from BarX0, the count
    ; text drawn over TextX0..TextX1 (real frame daily_quests_buy_reroll_1440)
    static UseRe := "i)^\s*use\s+(\d+)\s+(.+?)\s*$"
    static BarX0 := 1068, BarX1 := 1875, BarDy := 34
    static TextX0 := 1433, TextX1 := 1516
    static UseMax := 25

    name := "dailyquests"
    priority := 5                 ; Scheduler task contract (Sched.Priority)

    __New(deps := "") {
        this._env := TaskEnv(deps)
        this._lastAt := ""
        this._potionFn := TaskEnv.Dep(deps, "potionQuest", "")    ; (potion, n) -> true when queued
        this._asked := Map()            ; "yyyyMMdd|quest" -> the uses handed to the potion task that day
    }

    CanRun(state) {
        env := this._env
        if !IsObject(env.cfg)
            return false
        on := env.cfg.Get("DailyQuests.enabled", 0)
        if !(IsNumber(on) && on != 0)
            return false
        return (this._lastAt = "" || env.Now() - this._lastAt >= this.IntervalMs())
    }

    IntervalMs() {
        v := this._env.cfg.Get("DailyQuests.intervalMin", 30)
        return (IsInteger(v) && v >= 5 && v <= 720) ? Integer(v) * 60000 : 30 * 60000
    }

    ; The reroll words (lower case, trimmed, no empties).
    Words() {
        out := []
        for w in StrSplit(String(this._env.cfg.Get("DailyQuests.reroll", "")), ",") {
            w := QuestMatch.Norm(w)
            if (w != "")
                out.Push(w)
        }
        return out
    }

    ; A quest name holds one of the words (whole words, normalised).
    static Wanted(name, words) {
        n := " " QuestMatch.Norm(name) " "
        for w in words
            if InStr(n, " " w " ")
                return false
        return true
    }

    Run(ctx) {
        env := this._env
        this._lastAt := env.Now()           ; any outcome waits the interval
        if !this._Open(ctx) {
            if !ctx.ShouldStop()
                env.Log("daily quests: the window did not open (its title did not read)")
            return 0
        }
        acts := 0, done := 0, lines := []
        this._potionAsks := []
        try {
            words := this.Words()
            for y in DailyQuestsTask.RowYs {
                if ctx.ShouldStop()
                    break
                r := this._RowC(ctx, y, words)
                acts += r.acts
                done += r.finished ? 1 : 0
                if (r.line != "")
                    lines.Push(r.line)
            }
            if (!ctx.ShouldStop() && done = DailyQuestsTask.RowYs.Length) {
                r := this._BonusC(ctx)
                acts += r.acts
                if (r.line != "")
                    lines.Push(r.line)
            }
        } finally {
            this._Close(CleanupCtx(ctx))
        }
        this._QueuePotions(ctx)
        if acts {
            msg := ""
            for l in lines
                msg .= (msg = "" ? "" : "`n") l
            env.Report("quests", "Daily quests", msg)
        }
        return acts
    }

    ; the window's rows and bonus are read and clicked evenly scaled, centred
    _RowC(ctx, y, words) => Screen.WithMode("C", () => this._Row(ctx, y, words))
    _BonusC(ctx) => Screen.WithMode("C", () => this._Bonus(ctx))

    ; One quest row. -> {acts, finished, line}
    _Row(ctx, y, words) {
        env := this._env
        name := this._RowName(y)
        out := {acts: 0, finished: false, line: ""}
        if (name = "") {
            env.Log("daily quests: row at y " y " read nothing: left alone")
            return out
        }
        if !this._Select(ctx, y, name)
            return out
        st := this._State()
        if (st.claim = "claimed") {
            env.Log("daily quests: '" name "' already claimed")
            out.finished := true
            return out
        }
        if (st.reroll = "") {               ; no reroll button: finished
            out.finished := true
            if (st.claim = "claim" && this._Click(ctx, DailyQuestsTask.ClaimPt, "Daily Quests Claim Rewards")) {
                env.Wait(DailyQuestsTask.ClaimMs, ctx)
                env.Log("daily quests: claimed '" name "'")
                out.acts++, out.line := "Claimed: " name
            } else if (st.claim != "claim")
                env.Log("daily quests: '" name "' finished, its button did not read Claim Rewards: left alone")
            return out
        }
        if this._PotionQuest(y, name)      ; a "Use N <potion>" quest: potions queued, never rerolled
            return out
        if DailyQuestsTask.Wanted(name, words) {
            env.Log("daily quests: '" name "' in progress")
            return out
        }
        ; unwanted and unfinished: free rerolls only
        old := name
        Loop DailyQuestsTask.MaxRerolls {
            if ctx.ShouldStop()
                break
            st := this._State()
            if (st.reroll != "free") {
                env.Log("daily quests: '" name "' not rerolled (" (st.reroll = "paid" ? "no free rerolls left: never bought" : "no Reroll Quest button read") ")")
                break
            }
            if !this._Click(ctx, DailyQuestsTask.RerollPt, "Daily Quests Reroll Quest")
                break
            env.Wait(DailyQuestsTask.RerollMs, ctx)
            out.acts++
            nw := this._RowName(y)
            env.Log("daily quests: rerolled '" name "' -> '" nw "'")
            name := nw
            if (nw = "" || DailyQuestsTask.Wanted(nw, words))
                break
        }
        if (name != old)
            out.line := "Rerolled: " old " -> " name
        return out
    }

    ; An unfinished "Use N <potion>" with DailyQuests.usePotions on: the
    ; uses still needed (its bar) go to the potion task. -> true when it is
    ; such a quest (handled, even when nothing was queued).
    _PotionQuest(y, name) {
        env := this._env
        on := env.cfg.Get("DailyQuests.usePotions", 0)
        if !(IsObject(this._potionFn) && IsNumber(on) && on != 0 && RegExMatch(name, DailyQuestsTask.UseRe, &m))
            return false
        n := Integer(m[1])
        potion := RegExReplace(Trim(m[2]), "i)(potion)s$", "$1")
        if (n < 1 || n > DailyQuestsTask.UseMax) {
            env.Log("daily quests: '" name "' wants " n " uses: left alone (" DailyQuestsTask.UseMax " at most)")
            return true
        }
        w := DailyQuestsTask.BarX1 - DailyQuestsTask.BarX0 + 1
        arr := ""
        try arr := (env.rectFn)(DailyQuestsTask.BarX0, y + DailyQuestsTask.BarDy, w, 1)
        if !(arr is Array && arr.Length = w) {
            env.Log("daily quests: '" name "' progress bar did not read: no potion used")
            return true
        }
        done := DailyQuestsTask.BarDone(arr, n)
        left := n - done
        if (left <= 0) {
            env.Log("daily quests: '" name "' bar reads " done "/" n ": nothing to use")
            return true
        }
        ; queued once the window is closed (_QueuePotions): a potion event
        ; waiting now preempted this task, so the rows after this one and the
        ; bonus were never done (and not again for intervalMin)
        ; the same uses already handed over today: not again (dry run, none
        ; owned or a cap: the bar never moves, and every visit opened the
        ; inventory and sent a potions message again). A bar that moved
        ; (some used) asks for the rest once.
        key := FormatTime(, "yyyyMMdd") "|" StrLower(name)
        if (this._asked.Has(key) && this._asked[key] = left) {
            env.Log("daily quests: '" name "' " done "/" n ": the same " left " " potion " were asked for today already: not again")
            return true
        }
        if !this.HasOwnProp("_potionAsks")
            this._potionAsks := []
        this._potionAsks.Push({name: name, potion: potion, left: left, done: done, n: n, key: key})
        env.Log("daily quests: '" name "' " done "/" n ": " left " " potion " for the potion task once this window is closed")
        return true
    }

    ; The "Use N <potion>" uses found this visit, handed to the potion task
    ; after the window closed (not after F3).
    _QueuePotions(ctx) {
        asks := this.HasOwnProp("_potionAsks") ? this._potionAsks : []
        this._potionAsks := []
        if (!asks.Length || !IsObject(this._potionFn))
            return
        if (HasMethod(ctx, "IsStopped") && ctx.IsStopped())
            return
        for a in asks {
            ok := false
            try ok := this._potionFn.Call(a.potion, a.left)
            if ok
                this._asked[a.key] := a.left
            this._env.Log("daily quests: '" a.name "' " a.done "/" a.n ": " (ok ? a.left " " a.potion " queued for the potion task" : "not queued (see the Potions lines)"))
        }
    }

    ; Uses done from one pixel row of the bar (BarX0..BarX1): the white
    ; fill's end; a fill reaching the count text counts up to the text's
    ; end (fewer potions, never more), or on to where it ends past it.
    static BarDone(arr, n) {
        w := arr.Length, x0 := DailyQuestsTask.BarX0
        e := DailyQuestsTask._White(arr[1]) ? DailyQuestsTask._RunEnd(arr, 0) : -1
        t0 := DailyQuestsTask.TextX0 - x0, t1 := DailyQuestsTask.TextX1 - x0
        if (e >= t0 - 3) {
            e := t1
            Loop 9 {
                i := t1 + A_Index - 1
                if (i < w && DailyQuestsTask._White(arr[i + 1])) {
                    e := Max(t1, DailyQuestsTask._RunEnd(arr, i))
                    break
                }
            }
        }
        return Max(0, Min(n, Round((e + 1) / w * n)))
    }
    static _White(c) => ((c >> 16) & 255) >= 200 && ((c >> 8) & 255) >= 200 && (c & 255) >= 200
    ; last white index of the run from index from (gaps of 2 px allowed)
    static _RunEnd(arr, from) {
        e := -1, gap := 0, i := from, w := arr.Length
        while (i < w) {
            if DailyQuestsTask._White(arr[i + 1])
                e := i, gap := 0
            else if (++gap > 2)
                break
            i++
        }
        return e
    }

    _Bonus(ctx) {
        env := this._env
        out := {acts: 0, line: ""}
        if !this._Select(ctx, DailyQuestsTask.BonusY, this._RowName(DailyQuestsTask.BonusY))
            return out
        st := this._State()
        if (st.claim = "claim" && st.reroll = "" && this._Click(ctx, DailyQuestsTask.ClaimPt, "Daily Quests Claim Rewards")) {
            env.Wait(DailyQuestsTask.ClaimMs, ctx)
            env.Log("daily quests: claimed the 'Good job today' bonus")
            out.acts++, out.line := "Claimed: Good job today"
        }
        return out
    }

    ; The left panel: {reroll: "free" | "paid" | "", claim: "claim" | "claimed" | ""}
    _State() {
        env := this._env
        b := DailyQuestsTask.RerollBox
        t := (env.ocrFn)(b.x, b.y, b.w, b.h)
        rr := RegExMatch(t, DailyQuestsTask.PaidRe) ? "paid" : RegExMatch(t, DailyQuestsTask.FreeRe) ? "free"
            : RegExMatch(t, "i)rer[o0]ll") ? "paid" : ""          ; a reroll word without "Quest": not known free
        c := DailyQuestsTask.ClaimBox
        ct := (env.ocrFn)(c.x, c.y, c.w, c.h)
        cl := RegExMatch(ct, DailyQuestsTask.ClaimedRe) ? "claimed" : RegExMatch(ct, DailyQuestsTask.ClaimRe) ? "claim" : ""
        return {reroll: rr, claim: cl}
    }

    ; A row's quest name (its first line).
    _RowName(y) {
        env := this._env
        b := DailyQuestsTask.RowBox
        t := Trim((env.ocrFn)(b.x, y - b.up, b.w, b.h))
        return (t = "") ? "" : Trim(StrSplit(t, "`n", "`r")[1])
    }

    ; Clicks the row and checks the left panel shows that quest.
    _Select(ctx, y, name) {
        env := this._env
        if !this._Click(ctx, [DailyQuestsTask.RowX, y], "a Daily Quests row")
            return false
        if !env.Wait(DailyQuestsTask.SelectMs, ctx)
            return false
        b := DailyQuestsTask.PanelBox
        panel := (env.ocrFn)(b.x, b.y, b.w, b.h)
        if (y = DailyQuestsTask.BonusY || DailyQuestsTask.Same(panel, name))
            return true
        env.Log("daily quests: '" name "' did not show on the left (read '" StrReplace(panel, "`n", " ") "'): left alone")
        return false
    }

    ; The panel's text is the row's quest (letters only; the panel wraps).
    static Same(panel, name) {
        a := RegExReplace(StrLower(panel), "[^a-z]"), b := RegExReplace(StrLower(name), "[^a-z]")
        if (a = "" || b = "")
            return false
        return InStr(a, b) || QuestMatch.Similarity(a, b) >= DailyQuestsTask.MatchMin
    }

    ; The window scales evenly and is centred ("C"; live 1920x1200 window,
    ; 2026-11-14: read stretched, the title box fell below the title and the
    ; window was left open). Only the sidebar button (OpenPt) stretches.
    TitleUp() {
        b := DailyQuestsTask.TitleBox
        return Screen.WithMode("C", () => RegExMatch((this._env.ocrFn)(b.x, b.y, b.w, b.h), DailyQuestsTask.TitleRe) > 0)
    }

    _Open(ctx) {
        env := this._env
        if this.TitleUp()
            return true
        p := ""
        try p := env.cal.Point("daily_quests_open")
        pt := IsObject(p) ? [p.x, p.y] : DailyQuestsTask.OpenPt
        if !this._Click(ctx, pt, "the Daily Quests button")
            return false
        waited := 0
        Loop {
            if this.TitleUp()
                return true
            if (waited >= DailyQuestsTask.OpenWaitMs || !env.Wait(DailyQuestsTask.PollMs, ctx))
                return false
            waited += DailyQuestsTask.PollMs
        }
    }

    ; -> 1 closed | 0 was not up | 2 still up
    _Close(ctx) => Screen.WithMode("C", () => this._CloseM(ctx))
    _CloseM(ctx) {
        env := this._env
        if !this.TitleUp()
            return 0
        Loop 3 {
            if !this._Click(ctx, DailyQuestsTask.ClosePt, "the Daily Quests X")
                return 2
            env.Wait(400, ctx)
            if !this.TitleUp()
                return 1
        }
        env.Log("daily quests: the window is still open after its X")
        return 2
    }

    ; Hover, then click - only with shift lock off and no purchase prompt.
    _Click(ctx, pt, what) {
        env := this._env, io := env.io
        if ctx.ShouldStop()
            return false
        g := Input.ClickGuard(io, ctx, what)
        if (g <= 0)
            return false
        if env.BuyPrompt("daily quests")
            return false
        io.MoveTo(pt[1], pt[2])
        if !env.Wait(DailyQuestsTask.HoverMs, ctx)
            return false
        if Input.PurchaseUp(io, env.ocrFn)
            return false
        io.ClickHere()
        return true
    }

    ; The App's tidy: the window left open is closed by its X.
    Leftovers() {
        return [{up: () => this.TitleUp() ? "Daily Quests window" : "", close: (label, ctx) => this._Close(ctx)}]
    }
}
