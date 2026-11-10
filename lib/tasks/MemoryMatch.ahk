#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\TaskEnv.ahk
#Include %A_LineFile%\..\..\MatchLogic.ahk
#Include %A_LineFile%\..\..\MatchVision.ahk
#Include %A_LineFile%\..\..\PotionSafety.ahk
; ---------------------------------------------------------------------------
; MemoryMatchTask: plays the Memory Match board (20 tiles, 10 chances, 12 h
; cooldown) and keeps the best pairs. The thinking is in lib\MatchLogic.ahk,
; the eyes (tile pixels) in lib\MatchVision.ahk.
;
;   t := MemoryMatchTask(deps)  deps as TaskEnv, plus
;                               clock      callable -> YYYYMMDDHHMMSS (A_Now)
;                               statePath  data\memory_match_state.json
;                               vision     MatchVision-like: State(i), Sig(i)
;                                          (default: MatchVision on the screen)
;   t.name = "memorymatch", t.priority = 5   (Scheduler task contract)
;   t.CanRun(state) -> MemoryMatch.enabled AND the route (MemoryMatch.route,
;                      default "memory_match") exists AND Due().
;   t.Due()         -> now >= nextTry from the state file; a missing,
;                      unparsable or bad file = due.
;   t.Run(ctx)      -> 1 when a round was played, else 0.
;
; THE GAME (user's clip 2026-10-27, 2560x1440, MemoryMatchTask.Layout):
;   E at the board shows a "Start Memory Match?" notification. Its button
;   reads "Start Memory Match" when a round is ready, or "Available after
;   11h 59m Left" on cooldown. Start opens the "Memory Match" window: 10
;   CHANCES and the MATCHED count on the left, the 5x4 tiles on the right
;   (they deal in for ~2 s). A flipped tile shows an icon and an amount; a
;   pair turns green with a check; a miss flips both back. After the 10th
;   chance every tile is shown and a red Close button appears under the
;   board. Every flip, flip-back and match is animated: nothing is clicked
;   until the tiles it touched are still (the user's rule).
;
; RUN
;   1. ResetToSpawn, walk the route, press E, wait for the notification
;      (OpenWaitMs): its title or its button reads (NotifyUp). None: errors
;      webhook, retry in RetryMin minutes.
;   2. Button reads "available ... left": nextTry = that time + 60 s
;      (RetryMin minutes when unreadable), close the notification (X), done.
;      No webhook.
;   3. Click Start, park the mouse (Layout.park: Start lies on tile 12), wait
;      for the board title and all 20 tiles face down and still (DealMs).
;   4. Play (Turns chances): MatchLogic.First / Second pick the tiles. A flip:
;      click its centre, wait until its corner is "open" and two pictures
;      PollMs apart are equal (FlipReadMs); the picture is the tile's key
;      (equal pictures = the same reward and amount, MatchVision.Same). Equal
;      keys: both corners must turn green and stay (GreenWaitMs) to count.
;      Else wait until both are face down and still (FlipBackMs); both green
;      by then = a pair after all. Then AnimMs more before the next click. A
;      tile already green when flipped costs no chance and is skipped.
;   5. Wait for Close (CloseWaitMs), click it until the title is gone,
;      respawn, nextTry = now + CooldownHours, one `memorymatch` webhook.
;   Anything unexpected (a failed respawn included): a finally closes what is
;   closable (the notification's X, or Close when it reads), respawns unless
;   stopped and writes nextTry = now + RetryMin minutes unless step 5 / 2
;   wrote it. Mid-round nothing but tiles is clicked (leaving loses the
;   chances), and a preempt does not end the round: only F3 / pause does.
;
; VALUE: a tile's key is "w<amount text width>#<n>": MatchLogic.Value ranks
; the narrow amounts first (x1 = the rare rewards, then x5, x10-x25,
; x100-x200, coins), see MatchVision.
;
; STATE FILE: {"nextTry": "...", "lastPlayed": "..."}, written like the
; potion usage file (tmp file + move, read back), so a failed write keeps the
; old file.
; ---------------------------------------------------------------------------

class MemoryMatchTask {
    static LayoutKnown := true     ; the board was measured on the user's clip (Dashboard)
    static Layout := {
        notify: {x: 940, y: 640, w: 680, h: 60},          ; "Start Memory Match?"
        startBox: {x: 910, y: 795, w: 740, h: 45},        ; its button's text
        start: {x: 1280, y: 817},                         ; the button
        notifyClose: {x: 1644, y: 607},                   ; the notification's X
        title: {x: 1100, y: 362, w: 360, h: 60},          ; "Memory Match" (board)
        closeBox: {x: 1180, y: 1095, w: 200, h: 55},      ; "Close" (after the last chance)
        close: {x: 1280, y: 1121},
        ; the mouse waits on the left panel after each flip: a face-down tile
        ; under it shows a lighter corner (0x454545 on the clip)
        park: {x: 880, y: 820}
    }
    ; the game font: "Stort Memory Motch?" / "Memory -Motch" (tests\screens)
    ; the title can lose letters ("Stort Memor Moach?" on the 19:43 clip), so
    ; the notification also counts as up when its button reads (NotifyUp)
    static NotifyRe := "i)st[ao]rt\s*mem"
    static ButtonRe := "i)st[ao]rt\s*mem"
    static StartRe := "i)st[ao]rt"
    static CooldownRe := "i)avail|after|left"
    static TitleRe := "i)mem[ao]ry"
    static CloseRe := "i)cl[o0]se"
    static OpenWaitMs := 4000
    static DealMs := 8000          ; the tiles deal in (~2 s on the clip)
    static FlipReadMs := 2500
    static FlipBackMs := 4000
    static GreenWaitMs := 3000
    static AnimMs := 350           ; after a flip-back / match is still
    static CloseWaitMs := 8000
    static GoneMs := 1000          ; preempted: no board title for this long = the board is gone
    static SettleMs := 450
    static PollMs := 150
    static RetryMin := 60
    static CooldownHours := 12
    static Turns := 10
    static CloseTries := 3
    static OpenKey := "e"

    name := "memorymatch"
    priority := 5

    __New(deps := "") {
        this._env := TaskEnv(deps)
        this._clock := TaskEnv.Dep(deps, "clock", "")
        if !IsObject(this._clock)
            this._clock := () => A_Now
        this._path := TaskEnv.Dep(deps, "statePath", "")
        if (this._path = "")
            this._path := MemoryMatchTask.DefaultStatePath()
        this._vis := TaskEnv.Dep(deps, "vision", "")
        if !IsObject(this._vis)
            this._vis := MatchVision()
        this._wrote := false
        this._notify := false       ; the notification is up
        this._board := false        ; the board is up
        this._sigs := []            ; distinct tile pictures seen this round
    }

    ; Absolute <repo>\data\memory_match_state.json (lib\tasks\ -> repo root).
    static DefaultStatePath() {
        return RegExReplace(A_LineFile, "\\[^\\]*\\[^\\]*\\[^\\]*$") "\data\memory_match_state.json"
    }

    CanRun(state) {
        env := this._env
        if !IsObject(env.cfg)
            return false
        on := env.cfg.Get("MemoryMatch.enabled", 0)
        if !(IsNumber(on) && on != 0)
            return false
        if !this.Due()
            return false
        return env.Route(env.cfg.Get("MemoryMatch.route", "memory_match")) != ""
    }

    Due() {
        nt := this.NextTry()
        return nt = "" || StrCompare((this._clock)(), nt) >= 0
    }

    NextTry() {
        v := this._Load()
        if (v.Has("nextTry") && v["nextTry"] is String && RegExMatch(v["nextTry"], "^\d{14}$"))
            return v["nextTry"]
        return ""
    }

    _Load() {
        try {
            v := Json.Parse(FileRead(this._path, "UTF-8"))
            if (v is Map)
                return v
        }
        return Map()
    }

    ; nextTry = now + secs (+ lastPlayed = now when played). -> true written.
    _Write(secs, played := false) {
        now := (this._clock)()
        data := this._Load()
        data["nextTry"] := DateAdd(now, secs, "Seconds")
        if played
            data["lastPlayed"] := now
        try {
            PotionSafety._AtomicWrite(this._path, Json.Stringify(data) "`n")
            this._wrote := true
            return true
        } catch as err {
            this._env.Log("memory match: could not write " this._path ": " err.Message)
            return false
        }
    }

    ; Seconds from the cooldown text, -1 when unknown. "11h 42m", "42m 10s",
    ; "45s", "1h", "03:12:09", "12:30" (MM:SS); O = 0 and I / l = 1 inside digits.
    static ParseCooldown(text) {
        t := String(text)
        d := "[0-9OoIl|]"
        if RegExMatch(t, "(?<![0-9A-Za-z])(" d "{1,2}):(" d "{2})(?::(" d "{2}))?(?![0-9A-Za-z:])", &m) {
            a := MemoryMatchTask._Num(m[1]), b := MemoryMatchTask._Num(m[2])
            c := (m[3] = "") ? 0 : MemoryMatchTask._Num(m[3])
            if (a < 0 || b < 0 || c < 0)
                return -1
            return (m[3] = "") ? a * 60 + b : a * 3600 + b * 60 + c
        }
        total := 0, found := false, pos := 1
        while (pos := RegExMatch(t, "(?<![A-Za-z])(" d "+)\s*([hHmMsS])(?![A-Za-z])", &m, pos)) {
            pos += m.Len
            n := MemoryMatchTask._Num(m[1])
            if (n < 0)
                continue
            u := StrLower(m[2])
            total += n * (u = "h" ? 3600 : u = "m" ? 60 : 1)
            found := true
        }
        return found ? total : -1
    }

    ; Digits with the game font's O = 0, I / l / | = 1; -1 without a real
    ; digit, except a two-letter look-alike ("Ilh" = 11h on the clip's button).
    static _Num(s) {
        if (!RegExMatch(s, "\d") && !RegExMatch(s, "^[OoIl|]{2}$"))
            return -1
        s := RegExReplace(RegExReplace(s, "[Oo]", "0"), "[Il|]", "1")
        return Integer(SubStr(s, 1, 9))
    }

    Run(ctx) {
        env := this._env
        io := env.io
        L := MemoryMatchTask.Layout
        steps := env.Route(IsObject(env.cfg) ? env.cfg.Get("MemoryMatch.route", "memory_match") : "")
        if (steps == "")
            return 0
        this._wrote := false, this._notify := false, this._board := false, this._sigs := []
        entered := false
        played := false
        won := []
        cctx := CleanupCtx(ctx)
        try {
            if !Input.ResetToSpawn(ctx, io) {
                ; 2026-10-27 review: a respawn that failed (no stop) wrote no
                ; nextTry, so the task ran again on every tick ahead of fishing
                if !ctx.ShouldStop() {
                    env.Log("memory match: respawn failed (" Input.LastResetError "): next try in " MemoryMatchTask.RetryMin " min")
                    this._Write(MemoryMatchTask.RetryMin * 60)
                }
                return 0
            }
            if !Input.PlayRoute(steps, ctx, io)
                return 0
            entered := true
            Input.Key(MemoryMatchTask.OpenKey, 80, io)
            r := this._WaitNotify(MemoryMatchTask.OpenWaitMs, ctx)
            if (r < 0)
                return 0
            if !r {
                env.Report("errors", "Memory Match", "the Start Memory Match notification did not show after E (check the memory_match route with Test)", 0xE74C3C)
                env.Log("memory match: no Start Memory Match notification after E; nothing clicked")
                this._Write(MemoryMatchTask.RetryMin * 60)
                return 0
            }
            this._notify := true
            btn := this._Read(L.startBox)
            if RegExMatch(btn, MemoryMatchTask.CooldownRe) {
                secs := MemoryMatchTask.ParseCooldown(btn)
                this._Write((secs >= 0) ? secs + 60 : MemoryMatchTask.RetryMin * 60)
                env.Log("memory match: on cooldown ('" btn "'), next try at " FormatTime(this.NextTry(), "HH:mm"))
                return 0
            }
            if !RegExMatch(btn, MemoryMatchTask.StartRe) {
                env.Log("memory match: the notification's button reads '" btn "', not Start; nothing clicked")
                this._Write(MemoryMatchTask.RetryMin * 60)
                return 0
            }
            env.Click(L.start)
            ; the cursor left on Start rests on tile 12, whose hover corner
            ; reads "open": the board never counted as dealt (2026-10-27 review)
            io.MoveTo(L.park.x, L.park.y)
            this._notify := false
            r := this._WaitDealt(ctx)
            if (r < 0)
                return 0
            if !r {
                env.Report("errors", "Memory Match", "the board did not open after Start (or its tiles never settled)", 0xE74C3C)
                this._Write(MemoryMatchTask.RetryMin * 60)
                return 0
            }
            this._board := true
            env.Log("memory match: started")
            ; a started round is finished: leaving mid-round loses the
            ; chances and left the board over the next task (2026-10-27
            ; review). Only a real halt (F3, pause, Roblox not in front) stops
            ; it; a preempt waits about a minute for the round to end, unless
            ; the board is gone (App preempts when the Roblox window vanishes).
            if !this._Play(cctx, won, ctx) || cctx.ShouldStop()
                return 0                    ; finally: retry in RetryMin (the button tells the rest)
            played := true
            this._Close(cctx)
            this._Write(MemoryMatchTask.CooldownHours * 3600, true)
        } catch as err {
            env.Log("memory match: stopped by an error: " err.Message)
            env.Report("errors", "Memory Match", "the Memory Match task failed: " err.Message, 0xE74C3C)
            if !this._wrote
                this._Write(MemoryMatchTask.RetryMin * 60)      ; never again on the next tick
        } finally {
            try {
                if this._notify
                    this._CloseNotify(ctx)
                if (this._board && RegExMatch(this._Read(L.closeBox), MemoryMatchTask.CloseRe))
                    this._Close(cctx)
                if (entered && !this._wrote)
                    this._Write(MemoryMatchTask.RetryMin * 60)
                ; not on a preempt: the next task does not need it, and a
                ; preempt for a vanished Roblox window must send no keys
                if !ctx.ShouldStop()
                    Input.ResetToSpawn(ctx, io)
            }
        }
        if !played
            return 0
        env.Report("memorymatch", "Memory Match", MemoryMatchTask._Summary(won))
        return 1
    }

    ; "- <reward> " per won pair, best first; or "no pairs matched".
    static _Summary(won) {
        if (won.Length = 0)
            return "no pairs matched"
        keys := []
        for k in won {
            at := keys.Length + 1
            for i, o in keys {
                if (MatchLogic.Value(k) < MatchLogic.Value(o)) {
                    at := i
                    break
                }
            }
            keys.InsertAt(at, k)
        }
        desc := ""
        for k in keys
            desc .= (desc = "" ? "" : "`n") "- " MemoryMatchTask.Label(k)
        return desc
    }

    ; A won key -> what it is, by its amount's width (MatchVision, clip widths:
    ; x1 16, x5 22, x20 34, x100 42, x200 47, x1,000 60, x3,000 / x5,000 66).
    static Label(key) {
        if !RegExMatch(String(key), "^w(\d+)#", &m)
            return String(key)
        w := Integer(m[1])
        return (w <= 18) ? "a rare reward (x1: Godlike / Heavenly / Godly / Bound / Void Coin / Rune)"
            : (w <= 27) ? "x5 (Fortune / Haste III)"
            : (w <= 38) ? "x10 - x25 potions"
            : (w <= 52) ? "x100 / x200 Lucky or Speed Potions"
            : "Coins (x1,000 or more)"
    }

    ; ---- screen -----------------------------------------------------------

    _Read(box) => Trim((this._env.ocrFn)(box.x, box.y, box.w, box.h), " `t`r`n")

    ; Polls OCR of box for re. -> 1 | 0 not within ms | -1 stopped
    _WaitRead(box, re, ms, ctx) {
        waited := 0
        Loop {
            if RegExMatch(this._Read(box), re)
                return 1
            if (waited >= ms)
                return 0
            if !this._env.Wait(MemoryMatchTask.PollMs, ctx)
                return -1
            waited += MemoryMatchTask.PollMs
        }
    }

    ; The board's title reads and all 20 tiles are face down twice in a row.
    ; -> 1 | 0 | -1 stopped
    _WaitDealt(ctx) {
        env := this._env
        waited := 0, ok := 0
        Loop {
            all := RegExMatch(this._Read(MemoryMatchTask.Layout.title), MemoryMatchTask.TitleRe) > 0
            if all {
                Loop 20 {
                    if (this._vis.State(A_Index) != "hidden") {
                        all := false
                        break
                    }
                }
            }
            ok := all ? ok + 1 : 0
            if (ok >= 2)
                return 1
            if (waited >= MemoryMatchTask.DealMs)
                return 0
            if !env.Wait(MemoryMatchTask.PollMs, ctx)
                return -1
            waited += MemoryMatchTask.PollMs
        }
    }

    ; The notification is up: its title reads, or its button does (the title
    ; alone missed it on the 19:43 clip and the macro reset with it open).
    static NotifyUp(title, btn) {
        return RegExMatch(title, MemoryMatchTask.NotifyRe) || RegExMatch(btn, MemoryMatchTask.CooldownRe)
            || RegExMatch(btn, MemoryMatchTask.ButtonRe)
    }

    ; -> 1 the notification is up | 0 not within ms | -1 stopped
    _WaitNotify(ms, ctx) {
        L := MemoryMatchTask.Layout
        waited := 0
        Loop {
            if MemoryMatchTask.NotifyUp(this._Read(L.notify), this._Read(L.startBox))
                return 1
            if (waited >= ms)
                return 0
            if !this._env.Wait(MemoryMatchTask.PollMs, ctx)
                return -1
            waited += MemoryMatchTask.PollMs
        }
    }

    _CloseNotify(ctx) {
        this._env.Click(MemoryMatchTask.Layout.notifyClose)
        this._env.Wait(MemoryMatchTask.SettleMs, ctx)
        this._notify := false
    }

    ; Waits for Close under the board, clicks it until the title is gone.
    _Close(ctx) {
        env := this._env
        L := MemoryMatchTask.Layout
        if (this._WaitRead(L.closeBox, MemoryMatchTask.CloseRe, MemoryMatchTask.CloseWaitMs, ctx) != 1) {
            env.Log("memory match: no Close button under the board")
            return false
        }
        Loop MemoryMatchTask.CloseTries {
            env.Click(L.close)
            stopped := !env.Wait(MemoryMatchTask.SettleMs, ctx)
            if !RegExMatch(this._Read(L.title), MemoryMatchTask.TitleRe) {
                this._board := false
                return true
            }
            if stopped
                return false
        }
        env.Log("memory match: the board is still open after " MemoryMatchTask.CloseTries " clicks on Close")
        return false
    }

    ; Tiles i (and j) reach state `want` and stay there two polls in a row.
    _WaitState(ctx, want, ms, i, j := 0) {
        waited := 0, ok := 0
        Loop {
            hit := this._vis.State(i) = want && (!j || this._vis.State(j) = want)
            ok := hit ? ok + 1 : 0
            if (ok >= 2)
                return true
            if (waited >= ms || !this._env.Wait(MemoryMatchTask.PollMs, ctx))
                return false
            waited += MemoryMatchTask.PollMs
        }
    }

    ; Clicks tile i and waits until it is face up and its picture is still.
    ; -> its key ("" when it never settled), or "matched" when it turned green
    ; first (the game confirming a pair; recorded by _Play, not here).
    _Flip(ctx, board, i) {
        env := this._env
        env.Click(MatchVision.Center(i))
        env.io.MoveTo(MemoryMatchTask.Layout.park.x, MemoryMatchTask.Layout.park.y)
        waited := 0, prev := ""
        key := ""
        Loop {
            st := this._vis.State(i)
            if (st = "matched")
                return "matched"
            if (st = "open") {
                s := this._vis.Sig(i)
                if (s.width = 0) {
                    prev := ""                      ; no amount yet: still the star side
                } else if (IsObject(prev) && MatchVision.Stable(prev, s)) {
                    key := this._KeyOf(s)
                    break
                } else {
                    prev := s
                }
            } else {
                prev := ""
            }
            if (waited >= MemoryMatchTask.FlipReadMs || !env.Wait(MemoryMatchTask.PollMs, ctx))
                break
            waited += MemoryMatchTask.PollMs
        }
        MatchLogic.Record(board, i, key)
        if (key = "" && !ctx.ShouldStop())
            env.Log("memory match: tile " i " never showed a still picture; left out")
        return key
    }

    ; One key per distinct picture: "w<amount width>#<n>".
    _KeyOf(sig) {
        for n, s in this._sigs
            if MatchVision.Same(s, sig)
                return "w" s.width "#" n
        this._sigs.Push(sig)
        return "w" sig.width "#" this._sigs.Length
    }

    ; Plays the round. ctx: the round's (CleanupCtx: a preempt does not end
    ; it); raw: the task's own ctx. While a preempt is pending, the board
    ; title must still read before each turn (MemoryMatchTask.GoneMs): App
    ; preempts when the Roblox window vanishes, and the round must not click
    ; on whatever is left on screen. -> false when the board is gone.
    _Play(ctx, won, raw := "") {
        env := this._env
        board := MatchLogic.NewBoard(20)
        turns := MemoryMatchTask.Turns
        while (turns > 0 && !ctx.ShouldStop()) {
            if (IsObject(raw) && HasMethod(raw, "IsPreempted") && raw.IsPreempted()
                && this._WaitRead(MemoryMatchTask.Layout.title, MemoryMatchTask.TitleRe, MemoryMatchTask.GoneMs, ctx) = 0) {
                env.Log("memory match: the board is gone mid-round; stopping")
                return false
            }
            a := MatchLogic.First(board, turns)
            if !a
                break
            ka := this._Flip(ctx, board, a)
            if ctx.ShouldStop()
                break
            if (ka = "matched") {
                ; already green (a pair the macro did not see matched): the game
                ; ignores the click and spends no chance. Flipping a second tile
                ; now would be the game's FIRST flip of a new pair and put every
                ; later turn one off (2026-10-27 review).
                MatchLogic.Matched(board, a)
                env.Log("memory match: tile " a " was already matched; picking again")
                continue
            }
            b := MatchLogic.Second(board, a, turns)
            if !b
                break
            kb := this._Flip(ctx, board, b)
            if ctx.ShouldStop()
                break
            if (kb = "matched") {                   ; green before its picture was read
                kb := ka
                MatchLogic.Record(board, b, kb)
            }
            turns -= 1
            if (ka != "" && ka == kb && this._WaitState(ctx, "matched", MemoryMatchTask.GreenWaitMs, a, b)) {
                MatchLogic.Matched(board, a, b)
                won.Push(ka)
                env.Log("memory match: matched " MemoryMatchTask.Label(ka))
            } else {
                if (ka != "" && ka == kb)
                    env.Log("memory match: tiles " a " and " b " looked alike but did not turn green; not counted")
                ; the last chance shows the whole board instead of flipping back
                if (turns > 0 && !this._WaitState(ctx, "hidden", MemoryMatchTask.FlipBackMs, a, b)) {
                    if (this._vis.State(a) = "matched" && this._vis.State(b) = "matched") {
                        ; green, not a miss: a picture that never held still
                        ; (lag) hid the pair (2026-10-27 review: b stayed
                        ; "seen" and was flipped again later)
                        MatchLogic.Matched(board, a, b)
                        k := (ka != "") ? ka : (kb != "") ? kb : "an unread pair"
                        won.Push(k)
                        env.Log("memory match: tiles " a " and " b " turned green after all: matched " MemoryMatchTask.Label(k))
                    } else
                        env.Log("memory match: tiles " a " and " b " did not flip back in time")
                }
            }
            if !env.Wait(MemoryMatchTask.AnimMs, ctx)
                break
        }
        return true
    }
}
