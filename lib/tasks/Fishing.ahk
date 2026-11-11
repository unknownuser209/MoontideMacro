#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\FishLogic.ahk
; ---------------------------------------------------------------------------
; FishingTask: the default loop (priority 99, always runnable).
;
;   task := FishingTask(cfg, state [, deps])
;   task.name / .priority / .CanRun(state) / .Run(ctx)   (Scheduler contract)
;
; One catch (CatchOnce):
;   1. click the rod; right after the rod settle (before any real bite) the
;      bite pixel must NOT already be the bite colour: if it is, the scene
;      itself is white (snow, spawn floor = not at the fishing spot) ->
;      "repath" at once, nothing else clicked
;   2. wait for the bite pixel on FishLogic.BitePolls (2) consecutive polls
;      - no bite after fishingFailsafeSec: click the failsafe sequence once
;        and keep waiting (arrow reel + io.Ocr: no click on the panel's
;        button while it reads Exit, and a new cast if it reads Fish after)
;      - no bite after pathingFailsafeSec: "repath"
;   3. park the mouse, sample the bar color once
;   4. minigame for up to minigameCapMs. The bar color must show up in the
;      strip within FishLogic.BarSeenMs; until it does nothing is clicked,
;      and if it never does the catch is dropped ("nobite": no clicks, no
;      fishLoops++). FishLogic.NonBiteRepath (2) non-bites in a row ->
;      "repath". Once seen: click whenever FishLogic.ShouldClick says the bar
;      color left the strip (or, advanced mode, got too narrow)
;   5. wait for the catch card ("Fish Caught!" / "Fishing Failed"), click
;      its X until it is gone (CloseTries), state.fishLoops++
;   A catch card still open before a cast (it covers the panel) is closed
;   the same way instead of re-pathing.
; "repath" sets state.needRepath, so the Sell task (reset + walk to the
; fisher + sell + walk back) runs next; fishLoops is never inflated.
; Run() repeats catches (a "nobite" just recasts) until ctx.ShouldStop() or a
; sell/re-path is due, then returns so the scheduler can start Sell. It also
; returns between catches (after at least one) when state.chatDue is set, so
; the app can read the chat for merchants (ChatWatch only runs between
; tasks) and start fishing again.
;
; Every coordinate, color and timing comes from data\coords.json. Settings:
; see the header of FishLogic.ahk. No pixel or key access except through
; Pixel / Input (the deps.io backend).
; ---------------------------------------------------------------------------

class FishingTask {
    name := "fishing"
    priority := 99

    __New(cfg, state, deps := "") {
        this.cfg := cfg
        this.state := state
        this.deps := FishLogic.Deps(deps)
        this._coords := FishLogic.Require("FishingTask", cfg)
        this._logged := false
        this._nonBites := 0         ; consecutive "no reel bar" catches
        this._fcKey := ""           ; _Fc: client rect of the cached mapping
        this._fcMapped := ""
    }

    ; ---- off 2560x1440 ---------------------------------------------------
    ; The fishing panel, its reel bar and the catch card do not scale x0.75
    ; with the rest of the UI. Live 1920x1080 (2026-11-10, frames measured):
    ; they scale x0.84 about a fixed share of the client (the panel / reel
    ; about 0.5 / 0.804, the card about the centre) and their TEXT keeps its
    ; 1440p pixel size. Under x0.75 the status box cut the L off "Location"
    ; and fishing never started; the reel strip ran past the bar. Their
    ; coords are moved there (MapFishing) and handed on as the design px
    ; that Screen maps onto them. At 2560x1440 nothing changes.
    ; Their scale off 1440 is not a power of Screen.s: measured (live,
    ; windowed) 1920x1080 s 0.75 -> 0.84 (reel / card), 1366x768 s 0.533 ->
    ; 0.726 (reel bar 345 of 475 px, card 312 of 430). UiK interpolates
    ; between the measured sizes (UiPoints, s ascending) and extends the end
    ; segments past them.
    static PanelAnchor := [0.5, 0.804]
    static CardAnchor := [0.5, 0.5]
    static UiPoints := [[0.5333, 0.726], [0.75, 0.84], [1.0, 1.0]]
    static UiK(s) {
        p := FishingTask.UiPoints
        i := 1
        while (i < p.Length - 1 && s > p[i + 1][1])
            i++
        a := p[i], b := p[i + 1]
        return a[2] + (s - a[1]) * (b[2] - a[2]) / (b[1] - a[1])
    }

    ; data\coords.json's fishing section for the current client (cached per
    ; client rect); the whole coords Map with it for FishLogic.Settings.
    _Fc() {
        fc := this._coords["fishing"]
        if Screen.IsIdentity()
            return fc
        key := Screen.cx "," Screen.cy "," Screen.cw "," Screen.ch
        if (this._fcKey != key)
            this._fcMapped := FishingTask.MapFishing(fc), this._fcKey := key
        return this._fcMapped
    }

    _CoordsNow() {
        if Screen.IsIdentity()
            return this._coords
        c := this._coords.Clone()
        c["fishing"] := this._Fc()
        return c
    }

    ; A design point on the panel (or, a = CardAnchor, the card) -> the
    ; design point Screen maps onto where the game draws it now -> {x, y}
    static PanelPt(x, y, a := "") {
        if Screen.IsIdentity()
            return {x: x, y: y}
        a := IsObject(a) ? a : FishingTask.PanelAnchor
        k := FishingTask.UiK(Screen.s)
        sx := Screen.cx + a[1] * Screen.cw + k * (x - a[1] * Screen.DesignW)
        sy := Screen.cy + a[2] * Screen.ch + k * (y - a[2] * Screen.DesignH)
        return Screen.Inv(Round(sx), Round(sy))
    }

    static MapPt(v, a := "") {
        p := FishingTask.PanelPt(v[1], v[2], a)
        return [p.x, p.y]
    }

    static MapRect(v, a := "") {
        p := FishingTask.PanelPt(v[1], v[2], a), q := FishingTask.PanelPt(v[1] + v[3], v[2] + v[4], a)
        return [p.x, p.y, q.x - p.x, q.y - p.y]
    }

    static MapX(x) => FishingTask.PanelPt(x, 1440).x
    static MapY(y) => FishingTask.PanelPt(1280, y).y

    static MapYs(ys) {
        out := []
        for y in ys
            out.Push(FishingTask.MapY(y))
        return out
    }

    ; fishing section -> a copy with every panel and card coord moved (the
    ; other failsafe clicks keep the x0.75 mapping)
    static MapFishing(fc) {
        m := FishingTask._Copy(fc)
        m["rod"] := FishingTask.MapPt(m["rod"])
        m["bite"]["pixel"] := FishingTask.MapPt(m["bite"]["pixel"])
        m["parkMouse"] := FishingTask.MapPt(m["parkMouse"])
        m["barSample"] := FishingTask.MapPt(m["barSample"])
        for k in ["strip", "advanced", "reel"] {
            r := m[k]
            r["x1"] := FishingTask.MapX(r["x1"]), r["x2"] := FishingTask.MapX(r["x2"])
        }
        m["strip"]["rows"] := FishingTask.MapYs(m["strip"]["rows"])
        m["advanced"]["y"] := FishingTask.MapY(m["advanced"]["y"])
        r := m["reel"]
        r["arrowY"] := FishingTask.MapY(r["arrowY"]), r["barY"] := FishingTask.MapY(r["barY"])
        r["borderYs"] := FishingTask.MapYs(r["borderYs"])
        m["panelTitle"]["rect"] := FishingTask.MapRect(m["panelTitle"]["rect"])
        m["fishButton"]["rect"] := FishingTask.MapRect(m["fishButton"]["rect"])
        card := FishingTask.CardAnchor
        close := fc["close"]
        m["close"] := FishingTask.MapPt(close, card)
        m["result"]["rect"] := FishingTask.MapRect(m["result"]["rect"], card)
        clicks := m["failsafe"]["clicks"]
        for i, c in clicks {
            if FishingTask._OnPanel(c)
                clicks[i] := FishingTask.MapPt(c)
            else if (c[1] = close[1] && c[2] = close[2])
                clicks[i] := FishingTask.MapPt(c, card)
        }
        return m
    }

    ; a design point inside the panel's 1440 box (title to button row)
    static _OnPanel(c) => c[1] >= 1000 && c[1] <= 1560 && c[2] >= 960 && c[2] <= 1180

    static _Copy(v) {
        if (Type(v) = "Map") {
            m := Map()
            for k, x in v
                m[k] := FishingTask._Copy(x)
            return m
        }
        if (Type(v) = "Array") {
            a := []
            for x in v
                a.Push(FishingTask._Copy(x))
            return a
        }
        return v
    }

    ; Extra wait before deciding "no fishing panel" (it can come back late
    ; after a catch).
    static PanelRecheckMs := 1500
    ; The panel's status line under its "Fishing" title (2560x1440): idle it
    ; reads "Location - Sol's World - Main Island", with the line out "Any
    ; minute now...", "Is something tugging...", "It's quiet...". With Eden
    ; on, its combo bar covers the Fish / Exit button, so the button never
    ; read and every cast waited the whole fishButton.waitMs (live
    ; 2026-11-10: cast 5.8 s instead of ~1 s); the status line is never
    ; covered. Read at 1x on real frames.
    static StatusRect := [1040, 1022, 480, 40]
    static ReadyRe := "i)l[o0]c[a4]ti[o0]n"

    ; The catch card after the reel ("Fish Caught!" / "You've got X!"; a miss
    ; is fishing.result.failWords): what shows it is up, the OCR scale, clicks
    ; on its X before giving up, and how long it may take to go after a click.
    ; The game font draws "a" like "o": at scale 1 Windows OCR reads the card
    ; as "Fish Cought!" / "You've qöt Stonefish!" (screenshot 2026-10-26), so
    ; the old "caught" / "you've got" words never matched and the X was
    ; clicked blind before the card was up. Scale 2 reads it right.
    static CardRe := "i)c[ao]u?ght|fish\W*c[ao]|you\W?ve|success"
    ; A miss in the same font: "Fishing Failed" reads "Fishing Foiled", so
    ; the shipped failWords ("failed", "gone") only caught the body line and
    ; a title-only read counted a lost fish as caught (2026-10-27 review).
    ; Checked besides failWords, so data\coords.json stays as shipped.
    static FailRe := "i)f[ao][il1|]{2}ed|g[o0]ne\b"     ; also "FoiIed" (l read as I)
    static CardScale := 2
    static CloseTries := 3
    static CloseGoneMs := 1500

    ; General.fishing = 0: never fish (the user runs only the other tasks).
    ; Limbo.enabled = 1: LimboTask is the idle task instead.
    CanRun(state) {
        if !(IsObject(this.cfg) && HasMethod(this.cfg, "Get"))
            return true
        return (this.cfg.Get("General.fishing", 1) && !this.cfg.Get("Limbo.enabled", 0)) ? true : false
    }

    Run(ctx) {
        d := this.deps
        if (ctx.ShouldStop() || this._SellDue())
            return
        if !FishLogic.FocusOrWait(d, ctx, "fishing")
            return
        caught := 0
        Loop {
            if (ctx.ShouldStop() || this._SellDue())
                return
            if (caught > 0 && this._ChatDue())
                return                                      ; app reads the chat, then fishing restarts
            r := this.CatchOnce(ctx)
            if (r = "error")
                d.io.Wait(FishLogic.FocusRetryMs, ctx)     ; no hot respin
            if (r = "nobite")
                continue                                    ; recast (2nd in a row is "repath")
            if (r != "ok")
                return
            caught++
        }
    }

    _SellDue() => FishLogic.SellDue(this.state, this.cfg)
    _ChatDue() => this.state.HasProp("chatDue") && this.state.chatDue

    ; -> "ok" | "stopped" | "repath" | "nobite" (no reel bar, nothing clicked)
    ;    | "error" (bad strip capture)
    CatchOnce(ctx) {
        fc := this._Fc()
        io := this.deps.io
        now := this.deps.now
        bite := fc["bite"]
        bx := bite["pixel"][1], by := bite["pixel"][2]
        opt := FishLogic.Settings(this.cfg, this._CoordsNow())
        tStart := now.Call()               ; per-catch timing line (speed work)

        ; ---- cast: the panel's button must read Fish --------------------------
        ; Arrow reel + io.Ocr: no Fish button in time -> no "Fishing" panel at
        ; all = not at the fishing spot (snow-proof, unlike the old white
        ; pixel): re-path now. Button reads Exit = the line is already out:
        ; do not click (that would reel it in), just wait for the bite.
        if (this._CloseLeftoverCard(ctx) < 0)
            return "stopped"
        fb := this._WaitFishButton(ctx)
        if (fb < 0)
            return "stopped"
        cast := true
        if (fb = 0 && !opt.legacyReel && HasMethod(io, "Ocr")) {
            panel := this._PanelState()
            if (panel = "") {                       ; a late panel gets one more look
                if !io.Wait(FishingTask.PanelRecheckMs, ctx)
                    return "stopped"
                panel := this._PanelState()
                if InStr(StrLower(io.Ocr(fc["fishButton"]["rect"]*)), fc["fishButton"]["word"])
                    panel := "panel"
            }
            if (panel = "") {                       ; a late card can cover the panel
                lc := this._CloseLeftoverCard(ctx)
                if (lc < 0)
                    return "stopped"
                if (lc = 0)
                    fb := 0
                else
                    fb := this._WaitFishButton(ctx)
                if (fb < 0)
                    return "stopped"
                if (lc > 0)
                    panel := fb ? "panel" : this._PanelState()
            }
            if (panel = "") {
                shot := HasMethod(io, "Shot") ? io.Shot() : ""
                if (shot != "")
                    this.deps.log.Call("fishing: screen saved to " shot)
                this.deps.log.Call("fishing: no fishing panel (not at the fishing spot) - re-pathing")
                this._ForceSell()
                return "repath"
            }
            cast := (panel != "exit")
        }
        if cast && !FishLogic.ClickAt(io, ctx, fc["rod"], fc["rodPreMs"], fc["rodSettleMs"]) {
            this._LineInForNext(ctx, opt, FishingTask.LineOutWaitMs)    ; the line may be going out
            return "stopped"
        }
        tCast := now.Call()

        ; ---- baseline (legacy reel only): no bite can be up yet -----------------
        ; Only a pixel that STAYS white for FishLogic.BaselineMs is scenery:
        ; the fishing panel slides in after the click and its white diamond
        ; icon can cross the bite pixel for a moment (seen 2026-10-25). And a
        ; fish that bites within a second keeps it white too: when the reel
        ; bar is up, that is a quick bite, not scenery.
        ; The arrow reel never uses the bite pixel: the waiting panel's width
        ; follows its tip text, and with a long tip its white right border
        ; sits exactly on (1536,1119) (screenshot 2026-10-25 22:26:58). Its
        ; bite is the reel bar itself showing up (_WaitBite).
        quick := false
        if opt.legacyReel && Pixel.Is(bx, by, bite["color"], bite["tol"]) {
            steady := true
            t0 := now.Call()
            while (now.Call() - t0 < FishLogic.BaselineMs) {
                if !io.Wait(bite["pollMs"], ctx)
                    return "stopped"
                if !Pixel.Is(bx, by, bite["color"], bite["tol"]) {
                    steady := false
                    break
                }
            }
            if (steady && !opt.legacyReel && this._ReelUp()) {
                this.deps.log.Call("fishing: quick bite")
                quick := true
            } else if steady {
                shot := HasMethod(io, "Shot") ? io.Shot() : ""
                if (shot != "")
                    this.deps.log.Call("fishing: screen saved to " shot)
                this.deps.log.Call("fishing: bite pixel stays white (not at fishing spot / white scenery) - re-pathing")
                this._ForceSell()
                return "repath"
            }
        }

        ; ---- wait for the bite ----------------------------------------------
        if !quick {
            r := this._WaitBite(ctx, opt)
            if (r = "stopped")
                this._LineInForNext(ctx, opt, FishingTask.LineInReadMs, false, true)
            if (r != "bite")
                return r
        }

        ; ---- the fish is on: landed (or lost) and its card closed before any
        ; other task. 2026-11-09 22:11:17 the Biome Randomizer took over mid
        ; reel: the reel bar ran on under the inventory, then the "Fishing
        ; Failed" card sat over the middle of the screen through the aura
        ; swap and the HEAVEN hunt (0 casts). A preempt waits these few
        ; seconds; a halt (F3, recovery) still stops at once.
        ctx := CleanupCtx(ctx)
        tBite := now.Call()

        ; ---- sample the bar color -------------------------------------------
        io.MoveTo(fc["parkMouse"][1], fc["parkMouse"][2])
        if !io.Wait(fc["parkSettleMs"], ctx)
            return "stopped"
        bar := Pixel.Get(fc["barSample"][1], fc["barSample"][2])

        ; ---- minigame ---------------------------------------------------------
        mg := opt.legacyReel ? this._Minigame(ctx, bar, opt) : this._Reel(ctx, opt)
        if (mg = "nobar")
            return this._NoBite()
        if (mg != "ok")
            return mg
        this._nonBites := 0
        tReel := now.Call()
        if !io.Wait(fc["afterMinigameMs"], ctx)
            return "stopped"
        res := this._Result(ctx)
        if (res = "stopped")
            return "stopped"
        if (this._CloseCard(ctx) < 0)
            return "stopped"
        if (res = "failed") {
            FishLogic.Bump(this.state, "fishFailed")
            this.deps.log.Call("fishing: the fish got away")
        } else {
            FishLogic.Bump(this.state, "fishCaught")
            this.state.fishLoops += 1
        }
        this.state.repathStreak := 0       ; fishing works: re-walks are not stuck
        tEnd := now.Call()
        this.deps.log.Call(Format("fishing: catch {:.1f} s (cast {:.1f}, bite wait {:.1f}, reel {:.1f}, card {:.1f})"
            , (tEnd - tStart) / 1000, (tCast - tStart) / 1000, (tBite - tCast) / 1000, (tReel - tBite) / 1000, (tEnd - tReel) / 1000))
        return "ok"
    }

    ; Result card after the reel (io.Ocr): waits for it so the close click
    ; does not land before it shows. "failed" ("Fishing Failed" / "The fish
    ; is gone..." card) | "caught" ("Fish Caught!" card, or no card read in
    ; time) | "stopped". No io.Ocr: "caught".
    _Result(ctx) {
        io := this.deps.io
        if !HasMethod(io, "Ocr")
            return "caught"
        rc := this._Fc()["result"]
        waited := 0
        Loop {
            txt := this._CardText()
            k := this._CardKind(txt)
            if (k != "")
                return k
            if (waited >= rc["waitMs"]) {
                this.deps.log.Call("fishing: no catch card seen in " Round(rc["waitMs"] / 1000, 1) " s (read: '" SubStr(RegExReplace(txt, "\s+", " "), 1, 60) "')")
                return "caught"
            }
            if !io.Wait(rc["pollMs"], ctx)
                return "stopped"
            waited += rc["pollMs"]
        }
    }

    _CardText() {
        r := this._Fc()["result"]["rect"]
        return this.deps.io.Ocr(r[1], r[2], r[3], r[4], FishingTask.CardScale)
    }

    ; -> "failed" | "caught" | "" (no catch card in this text)
    _CardKind(txt) {
        txt := StrLower(txt)
        for w in this._Fc()["result"]["failWords"]
            if InStr(txt, w)
                return "failed"
        if RegExMatch(txt, FishingTask.FailRe)
            return "failed"
        return RegExMatch(txt, FishingTask.CardRe) ? "caught" : ""
    }

    ; A catch card still open before a cast covers the panel: close it.
    ; -> 1 there was one and it closed | 0 none (or it would not close)
    ;    | -1 stopped
    _CloseLeftoverCard(ctx) {
        if !this._CardUp()
            return 0
        this.deps.log.Call("fishing: a catch card was still open - closing it")
        r := this._CloseCard(ctx)
        return r < 0 ? -1 : r
    }

    _CardUp() => HasMethod(this.deps.io, "Ocr") && this._CardKind(this._CardText()) != ""

    ; The App's between-tasks check (Tidy): the catch card, read and closed
    ; by its X the way a catch closes it. Without io.Ocr: nothing (no blind
    ; click on a card that may not be there).
    Leftovers() {
        if !HasMethod(this.deps.io, "Ocr")
            return []
        up := () => FishingTask.CardLabel(this._CardKind(this._CardText()))
        close := (label, ctx) => (r := this._CloseCard(ctx)) < 0 ? -1 : r ? 1 : 2
        return [{up: up, close: close}]
    }

    static CardLabel(kind) => kind = "failed" ? "Fishing Failed card" : kind = "caught" ? "Fish Caught card" : ""

    ; Clicks the catch card's X until the card is gone (io.Ocr), up to
    ; CloseTries clicks. -> 1 closed | 0 still up (logged) | -1 stopped.
    ; No io.Ocr: one click, 1.
    _CloseCard(ctx) {
        fc := this._Fc()
        io := this.deps.io
        pollMs := fc["result"]["pollMs"]
        Loop FishingTask.CloseTries {
            if !FishLogic.ClickAt(io, ctx, fc["close"], A_Index = 1 ? fc["closePreMs"] : fc["afterCloseMs"], fc["afterCloseMs"])
                return -1
            if !HasMethod(io, "Ocr")
                return 1
            waited := 0
            Loop {
                if !this._CardUp()
                    return 1
                if (waited >= FishingTask.CloseGoneMs)
                    break
                if !io.Wait(pollMs, ctx)
                    return -1
                waited += pollMs
            }
        }
        this.deps.log.Call("fishing: the catch card is still open after " FishingTask.CloseTries " clicks on its X")
        return 0
    }

    ; Is the arrow reel's bar on screen? Arrow + click bar or fish, and the
    ; bar's solid white top border (>= 90 % of its width) on one of the
    ; borderYs rows (it sits a few px off y 1030 while the panel slides in).
    ; The waiting panel's title underline reaches ~70 %, never 90 %.
    ; Below 1440p the arrow's wide base line is a few px off the mapped
    ; arrowY (1366x768, live 2026-11-11: base at client 524..525, mapped row
    ; 521 = its 3 px stem, so the marker was never seen and every reel
    ; failed). There the rows ArrowTries (design px from arrowY) are tried
    ; and the one that shows the marker is kept (this._arrowRow) for the reel.
    ; At 2560x1440: arrowY alone, as before.
    static ArrowTries := [0, 2, 4, 6, 8, 10, -2, -4]
    _arrowRow := ""
    _ArrowY(rc) => (this._arrowRow != "" && !Screen.IsIdentity()) ? this._arrowRow : rc["arrowY"]

    ; The reel's [arrow row, bar row]. Below 1440p every ArrowTries row is
    ; grabbed and the first that shows the arrow is used: the row found at
    ; the bite (the panel still sliding in) was a few px off once it settled.
    _ReelRows(rc) {
        if Screen.IsIdentity()
            return this.deps.grab.Call(rc["x1"], rc["x2"], [rc["arrowY"], rc["barY"]], rc["stride"])
        ys := []
        for d in FishingTask.ArrowTries
            ys.Push(rc["arrowY"] + d)
        ys.Push(rc["barY"])
        all := this.deps.grab.Call(rc["x1"], rc["x2"], ys, rc["stride"])
        n := FishingTask.ArrowTries.Length
        for i, d in FishingTask.ArrowTries
            if FishLogic.ReelArrow(all[i], rc["x1"], rc["stride"]) {
                this._arrowRow := rc["arrowY"] + d
                return [all[i], all[n + 1]]
            }
        return [all[1], all[n + 1]]
    }

    _ReelUp() {
        rc := this._Fc()["reel"]
        tries := Screen.IsIdentity() ? [0] : FishingTask.ArrowTries
        nt := tries.Length
        ys := []
        for d in tries
            ys.Push(rc["arrowY"] + d)
        ys.Push(rc["barY"])
        for y in rc["borderYs"]
            ys.Push(y)
        try {
            all := this.deps.grab.Call(rc["x1"], rc["x2"], ys, rc["stride"])
        } catch {
            return false
        }
        found := false
        for i, d in tries {
            s := FishLogic.ReelScan(all[i], all[nt + 1], rc["x1"], rc["stride"])
            if (s.m && (s.p2 || s.fill != "")) {
                found := true
                this._arrowRow := rc["arrowY"] + d
                break
            }
        }
        if !found
            return false
        rows := [all[1], all[nt + 1]]               ; rows[3..] = the border rows, as before
        Loop all.Length - nt - 1
            rows.Push(all[nt + 1 + A_Index])
        Loop rows.Length - 2 {
            row := rows[A_Index + 2]
            n := 0
            for c in row
                if FishLogic.ReelWhite(c)
                    n++
            if (n * 10 >= row.Length * 9)
                return true
        }
        return false
    }

    ; Waits for the bite, FishLogic.BitePolls polls in a row: the reel bar up
    ; (arrow reel) or the white bite pixel (legacy reel). With the fishing
    ; failsafe clicks and the pathing failsafe.
    ; -> "bite" | "stopped" | "repath"
    _WaitBite(ctx, opt) {
        fc := this._Fc()
        io := this.deps.io
        now := this.deps.now
        fs := fc["failsafe"]
        bite := fc["bite"]
        bx := bite["pixel"][1], by := bite["pixel"][2]
        fishingMs := opt.fishingSec * 1000
        pathingMs := opt.pathingSec * 1000
        start := now.Call()
        failsafeRan := false
        hits := 0
        Loop {
            if ctx.ShouldStop()
                return "stopped"
            if (opt.legacyReel ? Pixel.Is(bx, by, bite["color"], bite["tol"]) : this._ReelUp()) {
                hits++
                if (hits >= FishLogic.BitePolls)
                    break
            } else {
                hits := 0
            }
            elapsed := now.Call() - start
            if (elapsed > pathingMs) {
                this.deps.log.Call("fishing: pathing failsafe, forcing a re-path")
                this._ForceSell()
                return "repath"
            }
            if (elapsed > fishingMs && !failsafeRan) {
                failsafeRan := true
                this.deps.log.Call("fishing: fishing failsafe")
                ; Arrow reel: the last failsafe click lands on the panel's
                ; button. With the line out it reads Exit and that click
                ; reeled the line in, then nothing cast again until the
                ; pathing failsafe re-pathed (2026-10-27 review). Skip it
                ; while the button reads Exit, and cast again if the button
                ; reads Fish after the clicks (the line is in).
                checked := !opt.legacyReel && HasMethod(io, "Ocr")
                lineOut := checked && this._PanelState() = "exit"
                btn := fc["fishButton"]["rect"]
                for pt in fs["clicks"] {
                    if (lineOut && FishingTask._InRect(pt, btn)) {
                        this.deps.log.Call("fishing: the line is out (Exit) - failsafe click on the button skipped")
                        continue
                    }
                    if !FishLogic.ClickAt(io, ctx, pt, fs["gapMs"], fs["gapMs"])
                        return "stopped"
                }
                if (checked && InStr(StrLower(io.Ocr(btn*)), fc["fishButton"]["word"])) {
                    this.deps.log.Call("fishing: the button reads Fish after the failsafe - casting again")
                    if !FishLogic.ClickAt(io, ctx, fc["rod"], fc["rodPreMs"], fc["rodSettleMs"])
                        return "stopped"
                }
                continue
            }
            if !io.Wait(bite["pollMs"], ctx)
                return "stopped"
        }
        return "bite"
    }

    ; Point [x, y] inside rect [x, y, w, h].
    static _InRect(pt, r) => pt[1] >= r[1] && pt[1] < r[1] + r[3] && pt[2] >= r[2] && pt[2] < r[2] + r[4]

    ; Waits until the panel's button reads "Fish" (io.Ocr), so the cast click
    ; does not land before the button is back after a catch or a miss.
    ; -> 1 seen | 0 not seen in time (cast anyway) | -1 stopped. No io.Ocr: 1.
    _WaitFishButton(ctx) {
        io := this.deps.io
        if !HasMethod(io, "Ocr")
            return 1
        fb := this._Fc()["fishButton"]
        r := fb["rect"]
        waited := 0
        s := FishingTask.MapRect(FishingTask.StatusRect)
        Loop {
            if InStr(StrLower(io.Ocr(r[1], r[2], r[3], r[4])), fb["word"])
                return io.Wait(fb["settleMs"], ctx) ? 1 : -1
            ; button covered (Eden's combo bar): the idle status line says the
            ; same thing
            if RegExMatch(io.Ocr(s[1], s[2], s[3], s[4]), FishingTask.ReadyRe)
                return io.Wait(fb["settleMs"], ctx) ? 1 : -1
            if (waited >= fb["waitMs"])
                return 0
            if !io.Wait(fb["pollMs"], ctx)
                return -1
            waited += fb["pollMs"]
        }
    }

    ; The fishing panel right now (io.Ocr): "exit" (button reads Exit: the
    ; line is out) | "panel" (the "Fishing" title is there) | "" (no panel:
    ; not at the fishing spot).
    ; Another task takes over (a preempt, not a halt) while the line is out:
    ; reel it in (the panel's button reads Exit) so no fish bites during that
    ; task and leaves its "Fishing Failed" card over it (1366x768 soak,
    ; 2026-11-11: it covered the Aura Storage title and the Memory Match
    ; notification).
    ; waitMs: right after the rod click the button may still read Fish for a
    ; moment: wait up to that long for Exit.
    static LineOutWaitMs := 1500
    static LineInReadMs := 1000      ; in the bite wait: a missed Exit read gets this long (06:50, 1080p)
    ; Start: a line left out by a stop mid-cast (the button reads Exit) is
    ; reeled in before the first task: its catch card came up during the
    ; quest walk and the board never opened (live 1920x1080, 2026-11-11).
    ; Not at the fishing spot: nothing reads, nothing clicked.
    LineInAtStart(ctx) {
        try {
            opt := FishLogic.Settings(this.cfg, this._CoordsNow())
            io := this.deps.io
            ; the fish already gone: its card hides the panel (live 1600x900)
            if (this._CloseLeftoverCard(CleanupCtx(ctx)) < 0)
                return
            if (!opt.legacyReel && HasMethod(io, "Ocr")) {
                t := Trim(RegExReplace(String(io.Ocr(this._Fc()["fishButton"]["rect"]*)), "\s+", " "))
                if (t != "" && !InStr(StrLower(t), "fish"))     ; nothing / Fish: nothing to say
                    this.deps.log.Call("fishing: at Start the panel button reads '" SubStr(t, 1, 30) "'")
            }
            this._LineInForNext(ctx, opt, 0, true)
        }
    }

    ; blind: the line is out for sure (cast, waiting for the bite): when the
    ; button reads neither Exit nor Fish it is clicked anyway. At 2560x1440
    ; the waiting panel shows no readable button ("It's quiet... too quiet."),
    ; the line stayed out and its card covered the next obby (live
    ; 2026-11-11 12:12). A button that reads Fish = the line is in: no click.
    _LineInForNext(ctx, opt, waitMs := 0, quiet := false, blind := false) {
        io := this.deps.io
        if (opt.legacyReel || !HasMethod(io, "Ocr"))
            return
        cctx := CleanupCtx(ctx)
        if cctx.ShouldStop()
            return
        b := this._Fc()["fishButton"]["rect"]
        waited := 0
        while ((st := this._PanelState()) != "exit") {
            if (waited >= waitMs || !io.Wait(250, cctx)) {
                t := Trim(RegExReplace(String(io.Ocr(b*)), "\s+", " "))
                if InStr(StrLower(t), "fish")
                    return                      ; the line is in
                if blind {
                    this.deps.log.Call("fishing: next task: the button reads '" SubStr(t, 1, 30) "', not Exit - clicked once to reel the line in")
                    FishLogic.ClickAt(io, cctx, [b[1] + b[3] // 2, b[2] + b[4] // 2], 80, 300)
                } else if !quiet
                    this.deps.log.Call("fishing: next task: the button did not read Exit ('" SubStr(t, 1, 30) "'): line left as it is")
                return
            }
            waited += 250
        }
        this.deps.log.Call("fishing: line in before the next task")
        FishLogic.ClickAt(io, cctx, [b[1] + b[3] // 2, b[2] + b[4] // 2], 80, 300)
    }

    _PanelState() {
        io := this.deps.io
        fc := this._Fc()
        b := fc["fishButton"]["rect"]
        if InStr(StrLower(io.Ocr(b[1], b[2], b[3], b[4])), "exit")
            return "exit"
        t := fc["panelTitle"]
        r := t["rect"]
        return InStr(StrLower(io.Ocr(r[1], r[2], r[3], r[4])), t["word"]) ? "panel" : ""
    }

    ; Arrow controller (FishLogic.ReelScan / ReelDecide) until minigameCapMs.
    ; -> "ok" | "stopped" | "error" | "nobar" (neither the click bar nor the
    ; fish within FishLogic.ReelSeenMs: not a real bite, nothing clicked; a
    ; screenshot is saved when the io can take one)
    _Reel(ctx, opt) {
        fc := this._Fc()
        rc := fc["reel"]
        io := this.deps.io
        now := this.deps.now
        start := now.Call()
        st := {}
        seen := false
        lastUp := 0
        lastClick := -100000
        while (now.Call() - start <= fc["minigameCapMs"]) {
            if ctx.ShouldStop()
                return "stopped"
            try {
                rows := this._ReelRows(rc)
            } catch as e {
                this._LogOnce("fishing: strip capture failed (" e.Message "); abandoning this catch")
                return "error"
            }
            if FishLogic.AllBlack(rows) {
                this._LogOnce("fishing: strip capture is all black (exclusive fullscreen?); not clicking")
                return "error"
            }
            s := FishLogic.ReelScan(rows[1], rows[2], rc["x1"], rc["stride"])
            if (s.m && (s.p2 || s.fill != "")) {
                seen := true                            ; arrow + bar up (also "Ready!")
                lastUp := now.Call()
            } else if (seen && now.Call() - lastUp >= rc["endMs"]) {
                return "ok"                             ; the reel is over (caught or not)
            }
            scan := (s.m && s.p2) ? s : ""
            t := now.Call()
            if !IsObject(scan) {
                if (!seen && t - start >= FishLogic.ReelSeenMs) {
                    shot := HasMethod(io, "Shot") ? io.Shot() : ""
                    if (shot != "")
                        this.deps.log.Call("fishing: reel bar not found; screen saved to " shot)
                    return "nobar"
                }
            } else {
                seen := true
                if (FishLogic.ReelDecide(scan, st, t, rc["leadMs"], rc["aim"]) && t - lastClick >= rc["clickGapMs"]) {
                    io.ClickHere()
                    lastClick := t
                }
            }
            if !io.Wait(rc["pollMs"], ctx)
                return "stopped"
        }
        return "ok"
    }

    ; Clicks until minigameCapMs. -> "ok" | "stopped" | "error" | "nobar"
    ; "error": the strip capture threw or came back all black; nothing is
    ; clicked and the catch is abandoned (logged once per task).
    ; "nobar": the bar color never showed in the strip within
    ; FishLogic.BarSeenMs; nothing was clicked (not a real bite).
    _Minigame(ctx, bar, opt) {
        fc := this._Fc()
        io := this.deps.io
        now := this.deps.now
        adv := opt.advanced
        a := fc["advanced"]
        s := fc["strip"]
        z := adv ? a : s
        ys := adv ? [a["y"]] : s["rows"]
        start := now.Call()
        seen := false
        while (now.Call() - start <= fc["minigameCapMs"]) {
            if ctx.ShouldStop()
                return "stopped"
            try {
                rows := this.deps.grab.Call(z["x1"], z["x2"], ys, z["stride"])
            } catch as e {
                this._LogOnce("fishing: strip capture failed (" e.Message "); abandoning this catch")
                return "error"
            }
            if FishLogic.AllBlack(rows) {
                this._LogOnce("fishing: strip capture is all black (exclusive fullscreen?); not clicking")
                return "error"
            }
            if !seen {
                for row in rows
                    if FishLogic.RowHasColor(row, bar, z["tol"]) {
                        seen := true
                        break
                    }
                if !seen {
                    if (now.Call() - start >= FishLogic.BarSeenMs)
                        return "nobar"
                    if !io.Wait(fc["minigamePollMs"], ctx)
                        return "stopped"
                    continue
                }
            }
            if FishLogic.ShouldClick(rows, z["stride"], bar, z["tol"], adv, opt.threshold, a["extendTol"]) {
                io.ClickHere()
                if (adv && !io.Wait(a["afterClickMs"], ctx))
                    return "stopped"
            }
            if !io.Wait(fc["minigamePollMs"], ctx)
                return "stopped"
        }
        return "ok"
    }

    _LogOnce(msg) {
        if this._logged
            return
        this._logged := true
        this.deps.log.Call(msg)
    }

    ; Not a real bite (no reel bar): nothing was clicked, nothing counted.
    ; -> "nobite", or "repath" after FishLogic.NonBiteRepath in a row.
    _NoBite() {
        FishLogic.Bump(this.state, "falseBites")
        this.deps.log.Call("fishing: no reel bar - not a real bite")
        this._nonBites += 1
        if (this._nonBites < FishLogic.NonBiteRepath)
            return "nobite"
        this.deps.log.Call("fishing: " this._nonBites " false bites in a row - re-pathing")
        this._ForceSell()
        return "repath"
    }

    ; Make Sell due now: its reset + walk + return re-paths the character.
    ; Uses state.needRepath, so fishLoops (the catch count) is never inflated.
    _ForceSell() {
        FishLogic.Bump(this.state, "repaths")
        this._nonBites := 0
        this.state.needRepath := true
        this.state.repathStreak := (this.state.HasProp("repathStreak") ? this.state.repathStreak : 0) + 1
    }
}
