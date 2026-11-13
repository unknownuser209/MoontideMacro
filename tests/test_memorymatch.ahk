#Requires AutoHotkey v2.0
; Tests for lib\tasks\MemoryMatch.ahk. Offline: a fake board that behaves
; like the one on the user's clip 2026-10-27 (notification, Start, tiles that
; deal in, flip, flip back and turn green over time, Close at the end), a
; fake clock, a temp state file. The real-screen side (boxes, tile states,
; pictures) is checked on the clip's frames in test_screens.ahk.
; Uses QmCfg / QmWh / QmCal from test_questmatch.ahk.
#Include ..\lib\tasks\MemoryMatch.ahk

; ---- helpers (names must not start with Test_) -----------------------------

; The game. pid[i] = the reward a tile hides (equal pid = a pair), width[pid]
; = its amount text width. Fake time t moves only in io.Wait.
class MmBoard {
    FlipMs := 250        ; a tile turning face up
    PicMs := 450         ; until its picture is still
    GreenMs := 600       ; a pair turning green
    BackMs := 1300       ; a miss flipping back down
    DealMs := 2000       ; the tiles dealing in after Start
    __New(pid, widths) {
        this.pid := pid
        this.widths := widths
        this.t := 0
        this.ready := true
        this.cooldown := "Available after 11h 59m Left"
        this.title := "Notification`nStart Memory Match?"
        this.noNotify := false
        this.notify := false
        this.started := false
        this.dealAt := 0
        this.closed := false
        this.openAt := Map()        ; tile -> time it was clicked
        this.downAt := Map()        ; tile -> time it is face down again
        this.greenAt := Map()       ; tile -> time it is green
        this.pending := 0
        this.chances := 10
        this.endAt := 0             ; time the whole board shows + Close
        this.log := []              ; "tile N" | "start" | "notifyX" | "close" | "?"
        this.early := 0             ; tile clicks while a tile was still moving
        this.slowPic := Map()       ; tile -> its own PicMs (lag: the picture keeps moving)
        this.slowGreen := Map()     ; tile -> its own GreenMs when it completes a pair
        this.gone := false          ; the Roblox window vanished: nothing of the board reads
        this.startDrops := 0        ; Start clicks the game drops (the first n)
        this.closeDelay := 800      ; after the last chance: the board shown, Close after this
        this.dropTiles := Map()     ; tile -> clicks on it the game drops (lag)
        this.titleGoneAfter := 0    ; the title stops reading once this many tiles were clicked
        this.io := MmIO(this)
        this.vision := MmVision(this)
    }

    Ended() => this.endAt && this.t >= this.endAt

    PicFor(i) => this.slowPic.Has(i) ? this.slowPic[i] : this.PicMs

    ; The mouse rests on tile i: a face-down tile under it shows a lighter
    ; corner that reads "open" (MemoryMatchTask.Layout.park; 2026-10-27
    ; review: the cursor left on tile 12 by the Start click)
    Hovered(i) {
        r := MatchVision.Tile(i)
        return this.io.x >= r.x && this.io.x < r.x + r.w && this.io.y >= r.y && this.io.y < r.y + r.h
    }

    Moving() {
        for i, at in this.openAt {
            if this.greenAt.Has(i) {
                if (this.t < this.greenAt[i])
                    return true
            } else if this.downAt.Has(i) {
                if (this.t < this.downAt[i])
                    return true
            } else if (this.t < at + this.PicFor(i)) {
                return true
            }
        }
        return false
    }

    Click(x, y) {
        L := MemoryMatchTask.Layout
        if (x = L.start.x && y = L.start.y && this.notify) {
            this.log.Push("start")
            if (this.startDrops > 0) {          ; Roblox dropped the click
                this.startDrops--
                return
            }
            if this.ready {
                this.notify := false
                this.started := true
                this.dealAt := this.t + this.DealMs
            }
            return
        }
        if (x = L.notifyClose.x && y = L.notifyClose.y && this.notify) {
            this.log.Push("notifyX")
            this.notify := false
            return
        }
        if (x = L.close.x && y = L.close.y) {
            this.log.Push("close")
            if this.Ended()
                this.closed := true
            return
        }
        Loop 20 {
            c := MatchVision.Center(A_Index)
            if (x = c.x && y = c.y) {
                this.TileClick(A_Index)
                return
            }
        }
        this.log.Push("?")
    }

    TileClick(i) {
        if (this.dropTiles.Has(i) && this.dropTiles[i] > 0 && this.started && this.t >= this.dealAt) {
            this.dropTiles[i] -= 1
            this.log.Push("drop " i)
            return
        }
        this.log.Push("tile " i)
        if (!this.started || this.t < this.dealAt || this.endAt)
            return
        if this.Moving()
            this.early += 1
        if (this.greenAt.Has(i) || (this.openAt.Has(i) && (!this.downAt.Has(i) || this.t < this.downAt[i])))
            return                                      ; already face up
        this.openAt[i] := this.t
        if this.downAt.Has(i)
            this.downAt.Delete(i)
        if !this.pending {
            this.pending := i
            return
        }
        a := this.pending, this.pending := 0
        this.chances -= 1
        if (this.pid[a] = this.pid[i]) {
            g := this.slowGreen.Has(i) ? this.slowGreen[i] : this.GreenMs
            this.greenAt[a] := this.t + g
            this.greenAt[i] := this.t + g
        } else if this.chances > 0 {
            this.downAt[a] := this.t + this.BackMs
            this.downAt[i] := this.t + this.BackMs
        }
        if (this.chances = 0)
            this.endAt := this.t + this.closeDelay
    }

    State(i) {
        if (this.gone || !this.started || this.t < this.dealAt)
            return ""
        if (this.greenAt.Has(i) && this.t >= this.greenAt[i])
            return "matched"
        if this.Ended()
            return "open"
        if !this.openAt.Has(i)
            return this.Hovered(i) ? "open" : "hidden"
        if this.downAt.Has(i) {
            if (this.t >= this.downAt[i])
                return this.Hovered(i) ? "open" : "hidden"
            if (this.t >= this.downAt[i] - 200)
                return ""
        }
        return (this.t < this.openAt[i] + this.FlipMs) ? "" : "open"
    }

    Sig(i) {
        p := this.pid[i]
        moving := this.openAt.Has(i) && this.t < this.openAt[i] + this.PicFor(i) && !this.Ended()
        icon := []
        Loop 10
            icon.Push(moving ? 0x808080 + this.t : (A_Index = p ? 0xFFFFFF : 0x000000))
        prof := []
        Loop this.widths[p]
            prof.Push(3)
        return {icon: icon, prof: prof, width: prof.Length}
    }

    Ocr(x, y, w, h, scale := 1) {
        L := MemoryMatchTask.Layout
        if this.gone
            return ""
        if (x = L.notify.x && y = L.notify.y)
            return this.notify ? this.title : ""
        if (x = L.startBox.x && y = L.startBox.y)
            return this.notify ? (this.ready ? "Start Memory Match" : this.cooldown) : ""
        if (x = L.title.x && y = L.title.y)
            return (this.started && !this.closed && !(this.titleGoneAfter && this.Tiles().Length >= this.titleGoneAfter)) ? "Memory Match" : ""
        if (x = L.closeBox.x && y = L.closeBox.y)
            return (this.Ended() && !this.closed) ? "Close" : ""
        return ""
    }

    Tiles() {
        r := []
        for e in this.log
            if RegExMatch(e, "^tile (\d+)$", &m)
                r.Push(Integer(m[1]))
        return r
    }

    Count(what) {
        n := 0
        for e in this.log
            n += (e = what) ? 1 : 0
        return n
    }

    Won() => this.greenAt.Count // 2
}

class MmVision {
    __New(b) => this.b := b
    State(i) => this.b.State(i)
    Sig(i) => this.b.Sig(i)
}

class MmIO {
    __New(board) {
        this.b := board
        this.x := 0
        this.y := 0
    }
    Down(k) {
        if (StrLower(k) = "e") {
            this.b.es := (this.b.HasOwnProp("es") ? this.b.es : 0) + 1
            if (this.b.HasOwnProp("missFirst") && this.b.es <= this.b.missFirst)
                return                      ; this walk missed the board
            if (this.b.HasOwnProp("readyFirst") && this.b.es <= this.b.readyFirst)
                this.b.cooldown := "Available after Ready!", this.b.ready := false
            else if this.b.HasOwnProp("readyFirst")
                this.b.ready := true
        }
        if (StrLower(k) = "e" && !this.b.noNotify && !this.b.started)
            this.b.notify := true
    }
    Up(k) => 0
    MoveTo(x, y) {
        this.x := x
        this.y := y
    }
    Look(dx, dy) => 0
    Type(t) => 0
    ClickHere() {
        ; the respawn's two menu clicks are not game clicks
        for name, pt in Input.ResetCoords
            if (this.x = pt[1] && this.y = pt[2])
                return
        this.b.Click(this.x, this.y)
    }
    Wait(ms, ctx := "") {
        this.b.t += ms
        return !(IsObject(ctx) && ctx.ShouldStop())
    }
}

; Standard board: tile i (1..10) and i+10 hold reward i. Rewards 1-4 are x1
; (rare), 5 x5, 6 x20, 7 x1,000, 8 x3,000, 9 x100, 10 x200 (clip widths).
MmStd() {
    pid := []
    Loop 20
        pid.Push(Mod(A_Index - 1, 10) + 1)
    return MmBoard(pid, [16, 16, 16, 16, 22, 34, 60, 66, 42, 47])
}

MmRoutes() => Map("routes", Map("memory_match", [["w", "down", 100], ["w", "up", 0]]))

; -> {t, board, wh, logs, clock, path}. clock.t is the fake YYYYMMDDHHMMSS.
MmMake(board, clockStr := "20261027120000", route := true) {
    m := {board: board, wh: QmWh(), logs: [], clock: {t: clockStr}}
    m.path := A_Temp "\vesper_mm_" A_TickCount "_" Random(1, 99999) ".json"
    cfg := QmCfg(Map("MemoryMatch.enabled", "1", "MemoryMatch.route", "memory_match"), route ? MmRoutes() : Map())
    clk := m.clock
    m.t := MemoryMatchTask({cfg: cfg, io: board.io, webhook: m.wh, cal: QmCal()
        , ocr: (x, y, w, h, s := 1) => board.Ocr(x, y, w, h), vision: board.vision
        , log: (s) => m.logs.Push(s), clock: () => clk.t, statePath: m.path})
    return m
}

MmClean(m) {
    for p in [m.path, m.path ".tmp"]
        try FileDelete(p)
}

; ---- tests -----------------------------------------------------------------

Test_MM_ParseCooldown() {
    AssertEq(MemoryMatchTask.ParseCooldown("Available after 11h 59m Left"), 43140, "the game's button")
    AssertEq(MemoryMatchTask.ParseCooldown("Available after 2h 5m Left"), 7500, "short")
    AssertEq(MemoryMatchTask.ParseCooldown("03:12:09"), 11529, "h:m:s")
    AssertEq(MemoryMatchTask.ParseCooldown("45s"), 45, "seconds")
    AssertEq(MemoryMatchTask.ParseCooldown("I1h O5m"), 39900, "game font digits")
    AssertEq(MemoryMatchTask.ParseCooldown("Available after Ilh 07m Left"), 40020, "the 19:43 clip's button")
    AssertEq(MemoryMatchTask.ParseCooldown("Start Memory Match"), -1, "no time")
    AssertEq(MemoryMatchTask.ParseCooldown(""), -1, "empty")
}

Test_MM_DueAndBrokenState() {
    m := MmMake(MmStd())
    try {
        AssertTrue(m.t.Due(), "no file -> due")
        FileAppend("{garbage", m.path)
        AssertTrue(m.t.Due(), "broken file -> due")
        FileDelete(m.path)
        FileAppend('{"nextTry": "20261028001000"}', m.path)
        m.clock.t := "20261027235000"
        AssertTrue(!m.t.Due(), "before nextTry (across midnight)")
        m.clock.t := "20261028001000"
        AssertTrue(m.t.Due(), "at nextTry")
        AssertTrue(m.t.CanRun(SchedState()), "enabled + route + due -> eligible")
    } finally {
        MmClean(m)
    }
}

Test_MM_CooldownButtonSetsNextTry() {
    b := MmStd()
    b.ready := false
    m := MmMake(b)
    try {
        AssertEq(m.t.Run(SchedCtx()), 0, "not played")
        AssertEq(m.t.NextTry(), DateAdd(m.clock.t, 43140 + 60, "Seconds"), "next try from the button's 11h 59m")
        AssertEq(b.Count("start"), 0, "Start never clicked")
        AssertEq(b.Count("notifyX"), 1, "the notification closed")
        AssertEq(b.Tiles().Length, 0, "no tile clicked")
        AssertEq(m.wh.sent.Length, 0, "no webhook for a cooldown")
    } finally {
        MmClean(m)
    }
}

; The 19:43 clip: the title read "Stort Memor Moach?" (or nothing), the macro
; waited out OpenWaitMs and reset with the notification still open.
Test_MM_UnreadableTitleStillSeesTheButton() {
    for title in ["", "Notification`nStort Memor Moach?"] {
        b := MmStd()
        b.ready := false
        b.title := title
        m := MmMake(b)
        try {
            AssertEq(m.t.Run(SchedCtx()), 0, "not played")
            AssertEq(m.t.NextTry(), DateAdd(m.clock.t, 43140 + 60, "Seconds"), "next try from the button")
            AssertEq(b.Count("notifyX"), 1, "the notification closed")
            AssertEq(m.wh.Count("errors"), 0, "no error report")
        } finally {
            MmClean(m)
        }
    }
}

Test_MM_NoNotificationNothingClicked() {
    b := MmStd()
    b.noNotify := true
    m := MmMake(b)
    try {
        AssertEq(m.t.Run(SchedCtx()), 0, "not played")
        AssertEq(b.log.Length, 0, "nothing clicked")
        AssertEq(m.wh.Count("errors"), 1, "reported")
        AssertEq(m.t.NextTry(), DateAdd(m.clock.t, 3600, "Seconds"), "retry in an hour")
    } finally {
        MmClean(m)
    }
}

Test_MM_PlaysAndReports() {
    b := MmStd()
    m := MmMake(b)
    try {
        AssertEq(m.t.Run(SchedCtx()), 1, "played")
        if (b.Won() != 5) {                          ; what happened, for the failure
            dump := "tiles:"
            for i in b.Tiles()
                dump .= " " i
            for l in m.logs
                dump .= "`n" l
            dumpPath := A_Temp "/vesper_mm_play.txt"
            try FileDelete(dumpPath)
            FileAppend(dump, dumpPath)
        }
        AssertEq(b.Tiles().Length, 20, "10 chances, 2 flips each")
        AssertEq(b.Won(), 5, "5 pairs (learn 5 turns, then a pair every turn)")
        AssertEq(b.Count("close"), 1, "Close clicked once, at the end")
        AssertTrue(b.closed, "board closed")
        AssertEq(b.Count("?"), 0, "no click outside the tiles, Start and Close")
        AssertEq(m.t.NextTry(), DateAdd(m.clock.t, 12 * 3600, "Seconds"), "next round in 12 h")
        AssertEq(m.wh.Count("memorymatch"), 1, "one webhook")
        AssertTrue(InStr(m.wh.sent[1].desc, "- a rare reward") = 1, "the rare x1 rewards listed first")
    } finally {
        MmClean(m)
    }
}

Test_MM_NeverClicksWhileTilesMove() {
    ; the user's rule: wait for the flip / flip-back / match animation
    b := MmStd()
    m := MmMake(b)
    try {
        m.t.Run(SchedCtx())
        AssertEq(b.early, 0, "no tile clicked while a tile was still moving")
        AssertTrue(b.Tiles().Length = 20, "still every chance used")
    } finally {
        MmClean(m)
    }
}

Test_MM_PrefersTheRarePair() {
    ; two known pairs at once: the x1 (narrow amount) one is claimed first
    board := MatchLogic.NewBoard(20)
    MatchLogic.Record(board, 1, "w60#1"), MatchLogic.Record(board, 2, "w60#1")     ; coins
    MatchLogic.Record(board, 3, "w16#2"), MatchLogic.Record(board, 4, "w16#2")     ; x1
    AssertEq(MatchLogic.First(board, 5), 3, "the x1 pair first")
    AssertTrue(MatchLogic.Value("w16#2") < MatchLogic.Value("w22#3"), "x1 before x5")
    AssertTrue(MatchLogic.Value("w42#4") < MatchLogic.Value("w60#5"), "potions before coins")
    AssertTrue(InStr(MemoryMatchTask.Label("w16#2"), "rare"), "label")
}

Test_MM_StopMidRoundNeverClicksClose() {
    b := MmStd()
    m := MmMake(b)
    ctx := SchedCtx()
    try {
        ; stop once 6 tiles were clicked
        b.io := MmStopIO(b, ctx, 6)
        m.t := MemoryMatchTask({cfg: QmCfg(Map("MemoryMatch.enabled", "1"), MmRoutes()), io: b.io, webhook: m.wh, cal: QmCal()
            , ocr: (x, y, w, h, s := 1) => b.Ocr(x, y, w, h), vision: b.vision, clock: () => m.clock.t, statePath: m.path})
        AssertEq(m.t.Run(ctx), 0, "stopped")
        AssertEq(b.Count("close"), 0, "Close never clicked mid-round")
        AssertEq(b.Count("?"), 0, "nothing else clicked")
    } finally {
        MmClean(m)
    }
}

; Stops (F3) once `after` tiles were clicked; preempt = true: asks for a
; preempt instead (a merchant / potion task became due).
class MmStopIO extends MmIO {
    __New(b, ctx, after, preempt := false) {
        super.__New(b)
        this.ctx := ctx
        this.after := after
        this.preempt := preempt
    }
    ClickHere() {
        super.ClickHere()
        if (this.b.Tiles().Length < this.after)
            return
        if this.preempt
            this.ctx.RequestPreempt()
        else
            this.ctx.Stop()
    }
}

Test_MM_ParksTheMouseAfterStart() {
    ; 2026-10-27 review: the Start click left the cursor on tile 12, whose
    ; hover corner reads "open", so the board never counted as dealt
    b := MmStd()
    AssertTrue(b.Hovered(12) = false && (b.io.MoveTo(MemoryMatchTask.Layout.start.x, MemoryMatchTask.Layout.start.y), b.Hovered(12)), "Start sits on tile 12")
    b.io.MoveTo(0, 0)
    m := MmMake(b)
    try {
        AssertEq(m.t.Run(SchedCtx()), 1, "played")
        AssertEq(m.wh.Count("errors"), 0, "no 'board did not open' report")
        AssertEq(b.Tiles().Length, 20, "every chance used")
    } finally {
        MmClean(m)
    }
}

; live 1920x1080 2026-11-11 19:03: Roblox dropped the Start click, the
; notification stayed up and the run respawned with it open, nothing logged.
; Start is clicked again while the notification is up; never more than
; StartTries times, and a notification that never goes is logged.
Test_MM_DroppedStartIsClickedAgain() {
    b := MmStd()
    b.startDrops := 1
    m := MmMake(b)
    try {
        AssertEq(m.t.Run(SchedCtx()), 1, "played after the second Start")
        n := 0
        for e in b.log
            n += (e = "start") ? 1 : 0
        AssertEq(n, 2, "Start clicked twice")
        AssertTrue(MmHasLog(m, "clicking it again"), "logged")
    } finally {
        MmClean(m)
    }
    b2 := MmStd()
    b2.startDrops := 99
    m2 := MmMake(b2)
    try {
        AssertEq(m2.t.Run(SchedCtx()), 0, "not played")
        n := 0
        for e in b2.log
            n += (e = "start") ? 1 : 0
        AssertEq(n, MemoryMatchTask.StartTries, "Start clicked StartTries times")
        AssertTrue(MmHasLog(m2, "stayed up"), "the failure is in the log")
        AssertTrue(!b2.notify, "the notification closed after")
    } finally {
        MmClean(m2)
    }
}

Test_MM_PreemptFinishesTheRound() {
    ; 2026-10-27 review: a merchant / potion preempt mid-round left the board
    ; open for the next task and lost the chances. The round is finished and
    ; closed first; a real halt (F3, pause) still stops at once (above).
    b := MmStd()
    m := MmMake(b)
    ctx := SchedCtx()
    try {
        b.io := MmStopIO(b, ctx, 6, true)
        m.t := MemoryMatchTask({cfg: QmCfg(Map("MemoryMatch.enabled", "1"), MmRoutes()), io: b.io, webhook: m.wh, cal: QmCal()
            , ocr: (x, y, w, h, s := 1) => b.Ocr(x, y, w, h), vision: b.vision, clock: () => m.clock.t, statePath: m.path})
        AssertEq(m.t.Run(ctx), 1, "the round was played to the end")
        AssertTrue(ctx.IsPreempted(), "the preempt was asked mid-round")
        AssertEq(b.Tiles().Length, 20, "every chance used")
        AssertTrue(b.closed, "the board closed")
        AssertEq(m.t.NextTry(), DateAdd(m.clock.t, 12 * 3600, "Seconds"), "next round in 12 h")
    } finally {
        MmClean(m)
    }
    ; App also preempts when the Roblox window vanishes: the board is gone,
    ; so the round stops instead of clicking on whatever is left on screen
    b2 := MmStd()
    m2 := MmMake(b2)
    ctx2 := SchedCtx()
    try {
        b2.io := MmStopIO(b2, ctx2, 6, true)
        b2.io.DefineProp("ClickHere", {call: (self) => (MmStopIO.Prototype.ClickHere.Call(self), (b2.Tiles().Length >= 6) ? (b2.gone := true) : 0)})
        m2.t := MemoryMatchTask({cfg: QmCfg(Map("MemoryMatch.enabled", "1"), MmRoutes()), io: b2.io, webhook: m2.wh, cal: QmCal()
            , ocr: (x, y, w, h, s := 1) => b2.Ocr(x, y, w, h), vision: b2.vision, clock: () => m2.clock.t, statePath: m2.path})
        AssertEq(m2.t.Run(ctx2), 0, "not played")
        AssertTrue(b2.Tiles().Length <= 8, "at most the turn under way finished (" b2.Tiles().Length " tiles)")
        AssertEq(b2.Count("close"), 0, "no Close clicked blind")
    } finally {
        MmClean(m2)
    }
}

Test_MM_FailedRespawnWaitsRetryMin() {
    ; 2026-10-27 review: a respawn that failed (no stop) wrote no nextTry, so
    ; the task ran again on every tick ahead of fishing
    b := MmStd()
    m := MmMake(b)
    try {
        b.io := MmNoRespawnIO(b)
        m.t := MemoryMatchTask({cfg: QmCfg(Map("MemoryMatch.enabled", "1"), MmRoutes()), io: b.io, webhook: m.wh, cal: QmCal()
            , ocr: (x, y, w, h, s := 1) => b.Ocr(x, y, w, h), vision: b.vision, log: (s) => m.logs.Push(s)
            , clock: () => m.clock.t, statePath: m.path})
        AssertEq(m.t.Run(SchedCtx()), 0, "not played")
        AssertEq(m.t.NextTry(), DateAdd(m.clock.t, 3600, "Seconds"), "retry in RetryMin")
        AssertTrue(!m.t.Due(), "not picked again at once")
        said := false
        for l in m.logs
            said := said || InStr(l, "respawn prompt never showed")
        AssertTrue(said, "the reason is logged")
        AssertEq(b.log.Length, 0, "nothing on the board clicked")
    } finally {
        MmClean(m)
    }
}

Test_MM_PairMatchedButNotReadKeepsInStep() {
    ; 2026-10-27 review: tile 1's picture never held still (lag), tile 2 was
    ; its partner and both turned green. The macro took it for a miss, kept
    ; tile 2 "seen", flipped the green tile on the last turn, and from then
    ; on its turns were one off the game's: Close never came, board left open.
    ; Tiles 1 and 2 are a pair; tiles 3..11 and 12..20 hold rewards 2..10.
    pid := [1, 1]
    Loop 2
        Loop 9
            pid.Push(A_Index + 1)
    for greenMs in [1200, 6000] {               ; green by the flip-back check / only after it
        b := MmBoard(pid, [16, 16, 16, 16, 22, 34, 60, 66, 42, 47])
        b.slowPic[1] := 5000
        b.slowGreen[2] := greenMs
        m := MmMake(b)
        try {
            AssertEq(m.t.Run(SchedCtx()), 1, "played (" greenMs ")")
            AssertTrue(b.closed, "the board closed: the turns stayed in step with the game (" greenMs ")")
            AssertEq(b.chances, 0, "every chance used (" greenMs ")")
            if (greenMs = 1200)
                AssertEq(StrSplit(m.wh.sent[m.wh.sent.Length].desc, "`n").Length, b.Won(), "every pair the game gave is counted")
        } finally {
            MmClean(m)
        }
    }
}

; Respawn screens never show (io.Ocr reads nothing): ResetToSpawn fails
; without a stop.
class MmNoRespawnIO extends MmIO {
    Ocr(x, y, w, h, scale := 1) => ""
}

Test_MM_StateSurvivesNewInstance() {
    m := MmMake(MmStd())
    try {
        AssertEq(m.t.Run(SchedCtx()), 1, "played")
        m2 := MemoryMatchTask({cfg: QmCfg(Map("MemoryMatch.enabled", "1"), MmRoutes()), clock: () => m.clock.t, statePath: m.path})
        AssertTrue(!m2.Due(), "a new instance (macro restart) remembers the 12 h")
    } finally {
        MmClean(m)
    }
}

; live 2026-11-11: about 1 in 10 walks missed the board; one more walk
Test_MM_MissedWalkIsWalkedOnceMore() {
    b := MmStd()
    b.ready := false
    b.missFirst := 1
    m := MmMake(b)
    try {
        AssertEq(m.t.Run(SchedCtx()), 0, "on cooldown")
        AssertEq(b.es, 2, "E on two walks")
        AssertEq(m.t.NextTry(), DateAdd(m.clock.t, 43140 + 60, "Seconds"), "the second walk read the cooldown")
    } finally {
        MmClean(m)
    }
}

; live 2026-11-11: "Available after Ready!" for hours; the notification is
; closed and E pressed again: when it reads Start then, the round starts
Test_MM_ReadyIsOpenedAgain() {
    b := MmStd()
    b.readyFirst := 1
    m := MmMake(b)
    try {
        m.t.Run(SchedCtx())
        AssertEq(b.Count("notifyX"), 1, "the Ready notification closed")
        AssertEq(b.Count("start"), 1, "Start clicked after E again")
        AssertTrue(b.started, "the round started")
    } finally {
        MmClean(m)
    }
}

; a task log line holding text
MmHasLog(m, text) {
    for l in m.logs
        if InStr(l, text)
            return true
    return false
}

; ---- friend's 1080p round 2026-11-12: Roblox lagged and dropped clicks ------
; The macro counted 10 chances while the game had 3 left, waited for a Close
; that never came, reset and went hunting with the board still open.

; a dropped tile click is clicked again, and the round stays in step
Test_MM_DroppedTileClickIsClickedAgain() {
    b := MmStd()
    b.dropTiles[1] := 1, b.dropTiles[5] := 2, b.dropTiles[14] := 1
    m := MmMake(b)
    try {
        AssertEq(m.t.Run(SchedCtx()), 1, "played")
        AssertEq(b.Count("drop 1") + b.Count("drop 5") + b.Count("drop 14"), 4, "every dropped click happened")
        AssertEq(b.chances, 0, "every game chance used")
        AssertTrue(b.closed, "the board closed")
        AssertEq(b.Won(), 5, "still 5 pairs")
        AssertTrue(MmHasLog(m, "clicking it again"), "logged")
        AssertEq(b.early, 0, "no click while a tile moved")
    } finally {
        MmClean(m)
    }
}

; a tile that never reacts costs no chance; the round is still finished
Test_MM_DeadTileCostsNoChance() {
    b := MmStd()
    b.dropTiles[3] := 99
    m := MmMake(b)
    try {
        AssertEq(m.t.Run(SchedCtx()), 1, "played")
        AssertEq(b.chances, 0, "every game chance used")
        AssertTrue(b.closed, "the board closed")
        AssertTrue(MmHasLog(m, "never flipped"), "logged")
    } finally {
        MmClean(m)
    }
}

; the game, not the macro's count, ends the round: chances the macro did not
; see counted are played on until Close shows
Test_MM_GameEndsTheRoundNotTheCount() {
    b := MmStd()
    b.chances := 13
    m := MmMake(b)
    try {
        AssertEq(m.t.Run(SchedCtx()), 1, "played")
        AssertEq(b.chances, 0, "the 3 extra chances were played too")
        AssertTrue(b.closed, "the board closed (no board left for the next task)")
        AssertTrue(MmHasLog(m, "playing on"), "logged")
        AssertEq(m.t.NextTry(), DateAdd(m.clock.t, 12 * 3600, "Seconds"), "next round in 12 h")
    } finally {
        MmClean(m)
    }
    ; a normal round never waits for extra turns
    b2 := MmStd()
    m2 := MmMake(b2)
    try {
        AssertEq(m2.t.Run(SchedCtx()), 1, "played")
        AssertTrue(!MmHasLog(m2, "playing on"), "no extra turns")
        AssertEq(b2.Tiles().Length, 20, "20 flips")
    } finally {
        MmClean(m2)
    }
}

; interrupted (merchant / potion due) while the title's OCR misses (1080p):
; the tiles show the board is up, the round is finished
Test_MM_PreemptWithUnreadableTitleFinishes() {
    b := MmStd()
    b.titleGoneAfter := 6
    m := MmMake(b)
    ctx := SchedCtx()
    try {
        b.io := MmStopIO(b, ctx, 6, true)
        m.t := MemoryMatchTask({cfg: QmCfg(Map("MemoryMatch.enabled", "1"), MmRoutes()), io: b.io, webhook: m.wh, cal: QmCal()
            , ocr: (x, y, w, h, s := 1) => b.Ocr(x, y, w, h), vision: b.vision, log: (s) => m.logs.Push(s)
            , clock: () => m.clock.t, statePath: m.path})
        AssertEq(m.t.Run(ctx), 1, "the round was played to the end")
        AssertTrue(!MmHasLog(m, "board is gone"), "not taken for gone")
        AssertEq(b.chances, 0, "every chance used")
        AssertTrue(b.closed, "the board closed")
    } finally {
        MmClean(m)
    }
}

; review 2026-11-12: Close slower than EndCheckMs after the last chance: the
; round counted as unfinished and tiles were clicked on the shown board
Test_MM_SlowCloseIsNoExtraTurn() {
    b := MmStd()
    b.closeDelay := 4500
    m := MmMake(b)
    try {
        AssertEq(m.t.Run(SchedCtx()), 1, "played")
        AssertEq(b.Tiles().Length, 20, "no tile clicked after the 10th chance")
        AssertTrue(b.closed, "closed")
        AssertTrue(!MmHasLog(m, "playing on"), "no extra turn")
    } finally {
        MmClean(m)
    }
}
