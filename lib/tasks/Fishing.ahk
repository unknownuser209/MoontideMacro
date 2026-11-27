#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\FishLogic.ahk
#Include %A_LineFile%\..\ReelPause.ahk
#Include %A_LineFile%\..\ReelTrace.ahk
#Include %A_LineFile%\..\..\GameText.ahk
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
    _cardGone := false          ; the last catch card was seen closing (no leftover check before the next cast)
    _yieldClean := false        ; YieldedClean: the last run returned before a cast, its last card seen closing
    _cardSettled := false       ; Leftovers(true): no catch card after a task that walked off; none can come

    __New(cfg, state, deps := "") {
        this.cfg := cfg
        this.state := state
        this.deps := FishLogic.Deps(deps)
        this._coords := FishLogic.Require("FishingTask", cfg)
        this._logged := false
        this._nonBites := 0         ; consecutive "no reel bar" catches
        this._fcKey := ""           ; _Fc: client rect of the cached mapping
        this._fcMapped := ""
        this._pause := ReelPause()  ; slow-PC warning, fed once per reel after it ends
        this._lastReel := ""        ; the last reel's gap / grab / work / wait (_ReelLoop)
    }

    ; App.Start: a new session for the slow-PC warning
    Reset() {
        this._pause.Reset()
        this._lastReel := ""
        this._yieldClean := false           ; the player had the game between sessions
        this._cardSettled := false
    }

    ; The last run returned between catches (chat check, sell due, a
    ; preempt at the top of the loop) before casting again, with its last
    ; catch card seen closing: no line is out and no catch card can come up.
    ; The App reads no catch card in the tidy then, and fishing started
    ; again right after it needs no shift lock probe (the card's X click
    ; landed) and no leftover card read before its first cast.
    YieldedClean() => this._yieldClean

    ; The loop's top (no line out): clean when the last card was seen closing
    _Yield() {
        this._yieldClean := this._cardGone
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
    ; The size UiK is read at: the client's WIDTH factor (Screen.E), not the
    ; smaller of width / height. Live 1920x991 (a 1080p monitor at 125 %
    ; with Roblox maximized, a tester's size; windowed here 2026-11-26): the
    ; panel, its reel bar and the card were exactly their 1920x1080 size
    ; (panel frame 500 x 144 px, bar borders 21 px apart, 406 px wide), only
    ; moved up with the anchor. Read at the height (s 0.688 -> k 0.81) the
    ; reel rows sat 6 design px under the bar and the reel was not seen
    ; (nothing clicked) until the once-a-run bar search (_ReelUnseen) moved
    ; them; that search needs the reel prompt to read. At 16:9 and narrower
    ; the width is the smaller factor, so every tested size maps as before.
    static UiS() => Screen.sx
    ; The panel's scale now (screen px per design px). Windows above 100 %
    ; (Screen.Ui): Roblox draws the layout of a client Ui times smaller, Ui
    ; times bigger, so the table is read at UiS / Ui and grown by Ui (a
    ; 1920x1080 client at 150 %: 1.5 x UiK(0.5) = 1.06, not UiK(0.75) = 0.84;
    ; testers at 125 % / 150 %, 2026-11-26: the reel bar not found).
    static KNow() {
        d := Screen.Ui
        return d * FishingTask.UiK(FishingTask.UiS() / d)
    }
    static PanelAnchor := [0.5, 0.804]

    ; The reel bar measured on screen (_FitFind), for the session: {k, ox,
    ; oy, cw, ch} = the panel's scale (screen px per design px) and its bar's
    ; top border centre in px from the client's top left, for a client of
    ; cw x ch (another size drops it), or "". Set by _ReelUnseen when the bar
    ; is nowhere near where the scale table puts it (a tester at 1920x991,
    ; 125 %, 2026-11-26: the border rows 10 bright, no border pair within 45
    ; px; the game may draw its UI another size there). Every panel coord
    ; then follows the measured bar; the card keeps its centre, at k.
    static Fit := ""
    static FitCx := 1279.5, FitTop := 1030, FitW := 475   ; the bar's top border: centre x, y, width (design)
    static FitOn() => IsObject(FishingTask.Fit) && FishingTask.Fit.cw = Screen.cw && FishingTask.Fit.ch = Screen.ch
    ; the coords as they are: 2560x1440 and no measured bar
    static Native() => Screen.IsIdentity() && Screen.Ui = 1 && !FishingTask.FitOn()
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
        dy := FishingTask.ReelDy
        if (FishingTask.Native() && !dy)
            return fc
        f := FishingTask.FitOn() ? FishingTask.Fit : ""
        key := Screen.cx "," Screen.cy "," Screen.cw "," Screen.ch "," Screen.Ui "," dy (IsObject(f) ? "," f.k "," f.ox "," f.oy : "")
        if (this._fcKey != key) {
            m := FishingTask.Native() ? FishingTask._Copy(fc) : FishingTask.MapFishing(fc)
            if dy
                FishingTask._ShiftReel(m["reel"], dy)
            this._fcMapped := m, this._fcKey := key
        }
        return this._fcMapped
    }

    _CoordsNow() {
        if FishingTask.Native()
            return this._coords
        c := this._coords.Clone()
        c["fishing"] := this._Fc()
        return c
    }

    ; A design point on the panel (or, a = CardAnchor, the card) -> the
    ; design point Screen maps onto where the game draws it now -> {x, y}
    static PanelPt(x, y, a := "") {
        if FishingTask.Native()
            return {x: x, y: y}
        a := IsObject(a) ? a : FishingTask.PanelAnchor
        k := FishingTask.KNow()
        if FishingTask.FitOn() {
            f := FishingTask.Fit, k := f.k
            if (a == FishingTask.PanelAnchor)       ; the panel: where its bar was measured
                return Screen.Inv(Round(Screen.cx + f.ox + k * (x - FishingTask.FitCx)), Round(Screen.cy + f.oy + k * (y - FishingTask.FitTop)))
        }
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

    ; Design rows ys (ascending) -> one design row per SCREEN row from the
    ; first to the last. The bar's top border is 1 screen px tall off 1440p;
    ; the 2 px steps of borderYs mapped one by one can step over it (1920x991,
    ; live 2026-11-26: rows 159 and 161 read, the border on 160). At
    ; 2560x1440 the rows stay as they are.
    static EveryRow(ys) {
        if (ys.Length < 2 || FishingTask.Native())
            return ys
        out := [], last := ""
        y := ys[1]
        while (y <= ys[ys.Length]) {
            sy := Screen.Y(y)
            if (sy != last)
                out.Push(y), last := sy
            y++
        }
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
        r["borderYs"] := FishingTask.EveryRow(FishingTask.MapYs(r["borderYs"]))
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

    ; Short hops toward the fishing spot when its panel is missing right after
    ; Sell's walk back (state.backHops, SellTask.BackHops). The shipped walks
    ; were recorded with the VIP gamepass's faster walking; a tester without
    ; VIP (and "VIP gamepass routes" on, the default) stopped ~0.9 s short of
    ; the spot every walk back and re-walked until the stuck pause
    ; (2026-11-24). The walk back ends holding a + w; non-VIP needs ~25% more
    ; of each (a 926 ms, w 648 ms): 3 hops of a 320 / w 220 ms cover it.
    static HopSteps := [["a", "down", 100], ["w", "down", 220], ["a", "up", 0], ["w", "up", 150]]
    static VipHint := "the walk back stopped short of the fishing spot. If you don't own the VIP gamepass in Sol's RNG,"
        . " untick 'VIP gamepass routes' (Settings page) so the walks fit your walking speed"

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
    ; On snow (live 2026-11-24 09:40, tests\screens\fish_failed_card_snowy_*)
    ; the red title does not read at all and the body reads only "The fis":
    ; the card counted as gone, the next cast found no panel and re-pathed.
    ; Checked after CardRe, so a caught fish named "The Fis..." stays caught.
    static GoneRe := "i)\bthe\s*f[il1|]s(?:h\b|\b)"
    static CardScale := 2
    ; the card's X takes a click only after the mouse has rested on it ~1 s
    ; (live 2026-11-13: closePreMs 450 -> card 3.9 s, 700 + quick retries ->
    ; 2.5 s; the measured 1100 stays: 2.1 s)
    ; (2026-11-17: the mouse put on the X right after the reel, before the
    ; card was up, made every first click miss: card 2.2 -> 4.1 s. The rest
    ; counts only once the card is there.)
    static CloseTries := 3
    static CloseGoneMs := 1500
    ; Live 2026-11-22 (03:44, 06:11): the catch card can freeze mid-slide with
    ; the whole panel raised ~346 px above its place (top edge y 632). Its
    ; Fish button then reads here instead of at fishButton, the card's words
    ; are garbled by the panel title under them (CardRe never matched), and
    ; it survives respawns: every cast saw "no panel" and re-walked until the
    ; macro paused. 2x reads "Fis" on all 5 frozen frames and nothing on
    ; normal ones (tests\screens\fish_raised_*); the frozen card's X is at
    ; RaisedClose (one click after the usual rest closed it, live 03:50).
    static RaisedRect := [1040, 742, 230, 60]
    static RaisedRe := "i)\bf[il1|][sg]"
    static RaisedClose := [1523, 645]

    ; General.fishing = 0: never fish (the user runs only the other tasks).
    ; Limbo.enabled = 1: LimboTask is the idle task instead, except while
    ; the crack is on hold (state.limboHeld: it could not be used; fishing
    ; until the next try, 2026-11-20).
    CanRun(state) {
        if !(IsObject(this.cfg) && HasMethod(this.cfg, "Get"))
            return true
        held := IsObject(state) && HasProp(state, "limboHeld") && state.limboHeld
        return (this.cfg.Get("General.fishing", 1) && (!this.cfg.Get("Limbo.enabled", 0) || held)) ? true : false
    }

    Run(ctx) {
        d := this.deps
        if (ctx.ShouldStop() || this._SellDue())
            return
        if !FishLogic.FocusOrWait(d, ctx, "fishing") {
            this._yieldClean := false           ; Roblox was not in front: the next run checks it all again
            return
        }
        ; a new run: look for a leftover card once, unless the last run
        ; returned clean (its card seen closing, nothing cast since) or a tidy
        ; after a walk found none (Leftovers(true))
        this._cardGone := this._yieldClean || this._cardSettled
        this._yieldClean := false
        this._cardSettled := false
        caught := 0
        Loop {
            if (ctx.ShouldStop() || this._SellDue()) {
                this._Yield()
                return
            }
            if (caught > 0 && this._ChatDue()) {
                this._Yield()
                return                                      ; app reads the chat, then fishing restarts
            }
            r := this.CatchOnce(ctx)
            if (r = "error")
                d.io.Wait(FishLogic.FocusRetryMs, ctx)     ; no hot respin
            if (r = "nobite" || r = "hopped")
                continue                                    ; recast (2nd nobite in a row is "repath")
            if (r != "ok")
                return
            caught++
        }
    }

    _SellDue() => FishLogic.SellDue(this.state, this.cfg)
    _ChatDue() => this.state.HasProp("chatDue") && this.state.chatDue

    ; -> "ok" | "stopped" | "repath" | "nobite" (no reel bar, nothing clicked)
    ;    | "error" (bad strip capture) | "hopped" (no panel after the walk
    ;    back, hopped forward onto the spot: cast again)
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
        ; the last catch's card was seen closing (speed, 2026-11-13): no
        ; second read of the whole card area before this cast
        if (!this._cardGone && this._CloseLeftoverCard(ctx) < 0)
            return "stopped"
        this._cardGone := false
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
            if (panel = "") {                       ; a frozen card over a raised panel
                rz := this._CloseRaisedCard(ctx)
                if (rz < 0)
                    return "stopped"
                if (rz > 0) {
                    fb := this._WaitFishButton(ctx)
                    if (fb < 0)
                        return "stopped"
                    panel := fb ? "panel" : this._PanelState()
                }
            }
            if (panel = "") {                       ; stopped short after the walk back
                hp := this._HopToSpot(ctx)
                if (hp < 0)
                    return "stopped"
                if (hp > 0)
                    return "hopped"
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
            if (r = "stopped" && this._LineInForNext(ctx, opt, FishingTask.LineInReadMs, false, true) = "bite") {
                this.deps.log.Call("fishing: the fish bit as the next task came up - landing it first")
                r := "bite"
            }
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
        this._lastReel := ""
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
        if IsObject(this.deps.trace)
            try this.deps.trace.Outcome(res = "failed" ? "got away" : (res = "caught" ? "caught" : "card: " res))
        if (res = "failed") {
            FishLogic.Bump(this.state, "fishFailed")
            this.deps.log.Call("fishing: the fish got away")
        } else {
            FishLogic.Bump(this.state, "fishCaught")
            this.state.fishLoops += 1
        }
        this._PauseCheck(res = "failed")
        this.state.repathStreak := 0       ; fishing works: re-walks are not stuck
        this.state.backHops := 0           ; at the spot: no hops for a later lost panel
        this.state.repathRejoin := false   ; and a later stuck streak may rejoin again (SellTask)
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
    _CardKind(txt) => FishingTask.CardKindOf(txt, this._Fc()["result"]["failWords"])

    ; failWords: data\coords.json fishing.result.failWords
    static CardKindOf(txt, failWords) {
        txt := StrLower(txt)
        for w in failWords
            if InStr(txt, w)
                return "failed"
        if RegExMatch(txt, FishingTask.FailRe)
            return "failed"
        if RegExMatch(txt, FishingTask.CardRe)
            return "caught"
        return RegExMatch(txt, FishingTask.GoneRe) ? "failed" : ""
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

    ; The frozen card over a raised panel (RaisedRect): is it there?
    _RaisedUp() {
        io := this.deps.io
        if !HasMethod(io, "Ocr")
            return false
        r := FishingTask.RaisedRect
        return RegExMatch(io.Ocr(r[1], r[2], r[3], r[4], 2), FishingTask.RaisedRe) ? true : false
    }

    ; Closes it by its X (RaisedClose), up to CloseTries clicks.
    ; -> 1 there was one and it went | 0 none (or it would not go) | -1 stopped
    _CloseRaisedCard(ctx) {
        if !this._RaisedUp()
            return 0
        this.deps.log.Call("fishing: the catch card froze over a raised fishing panel - closing it by its X")
        fc := this._Fc()
        io := this.deps.io
        Loop FishingTask.CloseTries {
            if !FishLogic.ClickAt(io, ctx, FishingTask.RaisedClose, A_Index = 1 ? fc["closePreMs"] : fc["afterCloseMs"], fc["afterCloseMs"])
                return -1
            if !io.Wait(FishingTask.CloseGoneMs, ctx)
                return -1
            if !this._RaisedUp()
                return 1
        }
        this.deps.log.Call("fishing: the frozen catch card is still up after " FishingTask.CloseTries " clicks on its X")
        return 0
    }

    ; The App's between-tasks check (Tidy): the catch card, read and closed
    ; by its X the way a catch closes it. Without io.Ocr: nothing (no blind
    ; click on a card that may not be there).
    ; settle (App: the task before this tidy walked off, or was the sell
    ; trip): a preempted cast's "Fishing Failed" card shows once the player
    ; walks off (live 2026-11-10), so a card not up now never comes; no more
    ; reads of it until fishing runs again. After a clean return
    ; (YieldedClean) there is no card to read at all.
    Leftovers(settle := false) {
        if !HasMethod(this.deps.io, "Ocr")
            return []
        up := () => (this._yieldClean || this._cardSettled) ? "" : this._CardUpLabel(settle)
        close := (label, ctx) => (r := this._CloseCard(ctx)) < 0 ? -1 : r ? 1 : 2
        ; the frozen card over a raised panel blocks every task (live 06:11:
        ; the Merchant Teleporter search found nothing with it up)
        rUp := () => this._RaisedUp() ? "frozen Fish Caught card" : ""
        rClose := (label, ctx) => (r := this._CloseRaisedCard(ctx)) < 0 ? -1 : r ? 1 : 2
        return [{up: up, close: close}, {up: rUp, close: rClose}]
    }

    _CardUpLabel(settle) {
        label := FishingTask.CardLabel(this._CardKind(this._CardText()))
        if (settle && label = "")
            this._cardSettled := true
        return label
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
                if !this._CardUp() {
                    this._cardGone := true
                    return 1
                }
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

    ; The reel's [arrow row, bar row, border rows...] (borderYs: rows of the
    ; bar's top border to read, [] = none). They sit inside the same copy of
    ; the screen as the arrow and bar rows (StripGrab blits their bounding
    ; box), so they cost no extra screen read. Below 1440p every ArrowTries
    ; row is grabbed and the first that shows the arrow is used: the row
    ; found at the bite (the panel still sliding in) was a few px off once
    ; it settled.
    _ReelRows(rc, borderYs := "") {
        bys := IsObject(borderYs) ? borderYs : []
        if Screen.IsIdentity() {
            ys := [rc["arrowY"], rc["barY"]]
            for y in bys
                ys.Push(y)
            return this.deps.grab.Call(rc["x1"], rc["x2"], ys, rc["stride"])
        }
        ys := []
        for d in FishingTask.ArrowTries
            ys.Push(rc["arrowY"] + d)
        ys.Push(rc["barY"])
        for y in bys
            ys.Push(y)
        all := this.deps.grab.Call(rc["x1"], rc["x2"], ys, rc["stride"])
        n := FishingTask.ArrowTries.Length
        pick := 1
        for i, d in FishingTask.ArrowTries
            if FishLogic.ReelArrow(all[i], rc["x1"], rc["stride"]) {
                this._arrowRow := rc["arrowY"] + d
                pick := i
                break
            }
        out := [all[pick], all[n + 1]]
        Loop bys.Length
            out.Push(all[n + 1 + A_Index])
        return out
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
        hits := 0, lastBtn := start
        Loop {
            if ctx.ShouldStop()
                return "stopped"
            if (opt.legacyReel ? Pixel.Is(bx, by, bite["color"], bite["tol"]) : this._ReelUp()) {
                hits++
                if (hits >= FishLogic.BitePolls)
                    break
            } else {
                hits := 0
                ; the minigame running (its button reads "Click / Touch
                ; Screen to Reel") with no bar seen: measured and said once
                if (!opt.legacyReel && !this._dimTried && HasMethod(io, "Ocr")
                    && now.Call() - start >= FishingTask.UnseenAfterMs && now.Call() - lastBtn >= FishingTask.UnseenEveryMs) {
                    lastBtn := now.Call()
                    if RegExMatch(String(io.Ocr(fc["fishButton"]["rect"]*)), FishingTask.ReelRe)
                        this._ReelUnseen()
                }
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
                if (checked && FishingTask.IsFish(io.Ocr(btn*), fc["fishButton"]["word"])) {
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

    ; The reel is up (its button says so) but _ReelUp saw no bar. The bar is
    ; searched for in a band around where it should be: its top and bottom
    ; white borders, one bar height apart (the only such pair there; the
    ; panel's frame above has dark panel under it). Found: its row and
    ; brightness (the level 90 % of the row reaches). A dimmer white (over
    ; DimFloor) puts FishLogic.WhiteMin under it, a bar drawn higher or lower
    ; (another Roblox top bar) moves the reel rows (FishingTask.ReelDy), both
    ; for the session. Logged with the HDR state and a screenshot. Once per
    ; task (this._dimTried). A friend's PC, 2026-11-11: border 133 at the
    ; expected rows, nothing clicked.
    static UnseenAfterMs := 3000
    static UnseenEveryMs := 1500
    static DimFloor := 100
    static DimMargin := 15
    static SearchUp := 45, SearchDown := 45, PairTol := 3, PairNear := 12
    static ReelDy := 0
    _dimTried := false
    _unseenTries := 0
    static UnseenTries := 3
    _ReelUnseen() {
        this._dimTried := true
        rc := this._Fc()["reel"]
        io := this.deps.io
        ; where the top border should be: the border row as far above the bar
        ; row as y 1030 is above 1044 (borderYs[3] at 2560x1440)
        want := rc["barY"] - (FishingTask.MapY(1044) - FishingTask.MapY(1030))
        ref := rc["borderYs"][1]
        for y in rc["borderYs"]
            if (Abs(y - want) < Abs(ref - want))
                ref := y
        gap := Max(1, FishingTask.MapY(1055) - FishingTask.MapY(1030))
        ys := [], lv := []
        y := ref - FishingTask.SearchUp
        while (y <= ref + FishingTask.SearchDown + gap + FishingTask.PairTol)
            ys.Push(y), y++
        try {
            for row in this.deps.grab.Call(rc["x1"], rc["x2"], ys, rc["stride"])
                lv.Push(FishingTask._Level90(row))
        }
        bestI := 0, best := 0, top := 0
        if (lv.Length = ys.Length) {
            sc := []
            for i, y in ys {
                pair := 0
                if (y <= ref + FishingTask.SearchDown) {
                    k := i + gap - FishingTask.PairTol
                    while (k <= i + gap + FishingTask.PairTol) {
                        if (k >= 1 && k <= lv.Length)
                            pair := Max(pair, lv[k])
                        k++
                    }
                }
                sc.Push(Min(lv[i], pair))
                top := Max(top, sc[i])
            }
            for i, v in sc
                if (v > FishingTask.DimFloor && v >= top - FishingTask.PairNear) {
                    bestI := i, best := lv[i]
                    break
                }
        }
        here := 0
        for y in rc["borderYs"] {
            i := y - ys[1] + 1
            if (i >= 1 && i <= lv.Length)
                here := Max(here, lv[i])
        }
        shot := HasMethod(io, "Shot") ? io.Shot() : ""
        dy := bestI ? ys[bestI] - ref : 0
        this.deps.log.Call("fishing: the minigame is running (its button reads the reel prompt) but the bar was not seen: its border is "
            here " bright here, white needs over " FishLogic.WhiteMin
            . (bestI ? "; the bar's borders found " (dy = 0 ? "in place" : Abs(dy) " px " (dy > 0 ? "lower" : "higher")) ", " best " bright" : "; no bar border found near it")
            . ", " Screen.HdrText() (shot != "" ? "; screen saved to " shot : ""))
        if !bestI {
            ; nowhere near: the bar measured anywhere in the lower middle of
            ; the client. Not found: tried again on a later reel (UnseenTries)
            f := this._FitFind()
            if !IsObject(f) {
                this._dimTried := (++this._unseenTries >= FishingTask.UnseenTries)
                this.deps.log.Call("fishing: no reel bar found anywhere in the lower middle of the screen either"
                    . (this._dimTried ? "" : "; looking again on the next reel"))
                return
            }
            k0 := FishingTask.KNow()
            FishingTask.Fit := {k: f.k, ox: f.ox, oy: f.oy, cw: Screen.cw, ch: Screen.ch}
            FishingTask.ReelDy := 0
            this.deps.log.Call("fishing: the reel bar found on screen at " f.x1 ".." f.x2 ", y " f.y " (drawn x" Format("{:.3f}", f.k)
                . ", the macro expected x" Format("{:.3f}", k0) "): the fishing panel follows it for this session")
            return
        }
        if (best <= FishLogic.WhiteMin) {
            FishLogic.WhiteMin := best - FishingTask.DimMargin
            this.deps.log.Call("fishing: white lowered to " FishLogic.WhiteMin " for this session (a dimmer screen: HDR or colour settings?)")
        }
        if (Abs(dy) >= 2) {
            FishingTask.ReelDy += dy
            this.deps.log.Call("fishing: the reel rows moved " Abs(dy) " px " (dy > 0 ? "down" : "up") " for this session")
        }
    }

    ; The reel bar anywhere in the lower middle of the client (x 20..80 %,
    ; y 45..98 %): two bright rows (min channel over DimFloor) through the
    ; client's centre column whose bright runs end at the same x (FitEndTol
    ; px) and are FitRatio times wider than they are apart (the bar's frame:
    ; 475 x 25 design px, 19x; measured 406 x 21 at 1920x991), with the bar's
    ; inside between them not one solid block. The panel's frame (500 x 144)
    ; and the white progress bar under it (narrower) do not pass; nor does
    ; scenery running out of the band. -> {k, ox, oy, x1, x2, y} (screen px
    ; from the client's top left; ox, oy = the top border's centre) or "".
    static FitEndTol := 4, FitRatio := [15.5, 23], FitGap := [8, 120], FitStride := 2, FitMinW := 0.12, FitGrey := 90
    _FitFind() {
        p := Screen.Inv(Screen.cx + Round(Screen.cw * 0.2), Screen.cy + Round(Screen.ch * 0.45))
        q := Screen.Inv(Screen.cx + Round(Screen.cw * 0.8), Screen.cy + Round(Screen.ch * 0.98))
        ys := [], sys := [], last := ""
        y := p.y
        while (y <= q.y) {
            s := Screen.Y(y)
            if (s != last)
                ys.Push(y), sys.Push(s), last := s
            y++
        }
        st := FishingTask.FitStride
        rows := ""
        try rows := this.deps.grab.Call(p.x, q.x, ys, st)
        if !(IsObject(rows) && rows.Length = ys.Length && rows.Length && rows[1].Length >= 10)
            return ""
        n := rows[1].Length
        sxOf := (i) => Screen.X(p.x + (i - 1) * st)
        mid := Screen.cx + Screen.cw / 2, ic := 1
        Loop n
            if (Abs(sxOf(A_Index) - mid) < Abs(sxOf(ic) - mid))
                ic := A_Index
        ; lit: whitish (min channel over DimFloor, channels within FitGrey:
        ; bright green hedges and grass are not; a dim HDR white is)
        lit := (c) => FishingTask._FitLit(c)
        runs := []
        for i, row in rows {
            if !lit(row[ic])
                continue
            a := ic, j := ic, miss := 0
            while (j > 1 && miss <= 1) {
                j--
                if lit(row[j])
                    a := j, miss := 0
                else
                    miss++
            }
            b := ic, j := ic, miss := 0
            while (j < n && miss <= 1) {
                j++
                if lit(row[j])
                    b := j, miss := 0
                else
                    miss++
            }
            if (a <= 2 || b >= n - 1)               ; runs out of the band: scenery
                continue
            runs.Push({i: i, l: sxOf(a), r: sxOf(b), a: a, b: b})
        }
        tol := FishingTask.FitEndTol
        ; inner rows (ys[i1..i2]) lit within a few px of sample j: the frame's
        ; 1 px side, read at every design px (the scan's stride can skip it)
        sides := (i1, i2, j) => FishingTask._SideRows(this.deps.grab, p.x + (j - 1 - 3) * st, p.x + (j - 1 + 3) * st, ys, i1, i2, lit)
        for u in runs {
            w := u.r - u.l
            if (w < Screen.cw * FishingTask.FitMinW)
                continue
            for v in runs {
                g := sys[v.i] - sys[u.i]
                if (g < FishingTask.FitGap[1] || g > FishingTask.FitGap[2])
                    continue
                if (Abs(u.l - v.l) > tol || Abs(u.r - v.r) > tol)
                    continue
                if (w / g < FishingTask.FitRatio[1] || w / g > FishingTask.FitRatio[2])
                    continue
                same := 0
                for t in runs
                    if (t.i > u.i + 1 && t.i < v.i - 1 && Abs(t.l - u.l) <= tol && Abs(t.r - u.r) <= tol)
                        same++
                if (same * 2 > Max(0, v.i - u.i - 3))   ; a solid block, not the bar's frame
                    continue
                inner := v.i - u.i - 1                  ; the frame's sides join the two rows
                if (inner > 0 && (sides(u.i + 1, v.i - 1, u.a) * 10 < inner * 8 || sides(u.i + 1, v.i - 1, u.b) * 10 < inner * 8))
                    continue
                return {k: w / FishingTask.FitW, ox: (u.l + u.r) / 2 - Screen.cx, oy: sys[u.i] - Screen.cy
                    , x1: u.l - Screen.cx, x2: u.r - Screen.cx, y: sys[u.i] - Screen.cy}
            }
        }
        return ""
    }

    static _FitLit(c) {
        r := (c >> 16) & 0xFF, g := (c >> 8) & 0xFF, b := c & 0xFF
        lo := Min(r, g, b)
        return lo > FishingTask.DimFloor && Max(r, g, b) - lo < FishingTask.FitGrey
    }

    ; how many of the rows ys[i1..i2] have a lit sample in design x1..x2
    static _SideRows(grab, x1, x2, ys, i1, i2, lit) {
        sub := []
        Loop i2 - i1 + 1
            sub.Push(ys[i1 + A_Index - 1])
        n := 0
        try {
            for row in grab.Call(x1, x2, sub, 1)
                for c in row
                    if lit(c) {
                        n++
                        break
                    }
        }
        return n
    }

    ; the level (min channel) 90 % of a row's pixels reach
    static _Level90(row) {
        hist := [], n := 0
        Loop 256
            hist.Push(0)
        for c in row {
            hist[Min((c >> 16) & 0xFF, (c >> 8) & 0xFF, c & 0xFF) + 1]++
            n++
        }
        need := Ceil(n * 0.9), got := 0, v := 255
        while (v > 0) {
            got += hist[v + 1]
            if (got >= need)
                break
            v--
        }
        return v
    }

    ; reel section shifted dy design px (arrow, bar and border rows)
    static _ShiftReel(r, dy) {
        r["arrowY"] += dy, r["barY"] += dy
        ys := []
        for y in r["borderYs"]
            ys.Push(y + dy)
        r["borderYs"] := ys
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
                if RegExMatch(t, FishingTask.ReelRe) {
                    this._ReelEndAtStart(ctx)
                    return
                }
            }
            this._LineInForNext(ctx, opt, 0, true)
        }
    }

    ; Start with a reel running ("Click / Touch Screen to Reel": stopped mid
    ; reel): the fish is lost. Its "Fishing Failed" card comes when the reel
    ; runs out; before, the sell respawned and walked with the reel up and
    ; the card then rode along over Captain Flarg's dialog (live 1920x1080,
    ; 2026-11-11 18:51). Waits up to ReelEndMs for that card, then closes it.
    static ReelRe := "i)t[o0]u[cv]h|cl[il1|]ck\s*/|t[o0]\s*re[ae][lI1]"
    static ReelEndMs := 20000
    _ReelEndAtStart(ctx) {
        io := this.deps.io
        this.deps.log.Call("fishing: a reel was still running at Start - waiting for it to end before the first task")
        cctx := CleanupCtx(ctx)
        waited := 0
        while !this._CardUp() {
            if (waited >= FishingTask.ReelEndMs) {
                this.deps.log.Call("fishing: the reel did not end within " (FishingTask.ReelEndMs // 1000) " s")
                return
            }
            if !io.Wait(250, cctx)
                return
            waited += 250
        }
        this._CloseLeftoverCard(cctx)
    }

    ; blind: the line is out for sure (cast, waiting for the bite): when the
    ; button reads neither Exit nor Fish it is clicked anyway. At 2560x1440
    ; the waiting panel shows no readable button ("It's quiet... too quiet."),
    ; the line stayed out and its card covered the next obby (live
    ; 2026-11-11 12:12). A button that reads Fish = the line is in: no click.
    ; blind -> "bite" when the fish is on the line instead (_FishOn): the
    ; reel bar is up, or the button reads something else than Exit / Fish
    ; and the bar follows within BiteOnMs. Live 2026-11-23/24, 7 times in 2
    ; days: the next task came up as the fish bit, the button read 'This fe'
    ; / 'This tee' (the bite) or 'Clink / Tru•r' (the reel); its one click
    ; lost the fish, whose "Fishing Failed" card then covered the next task
    ; (09:40: the next cast found no panel and re-pathed). The caller lands
    ; it first, as after a bite already seen. -> "bite" | ""
    static BiteOnMs := 2000
    _LineInForNext(ctx, opt, waitMs := 0, quiet := false, blind := false) {
        io := this.deps.io
        if (opt.legacyReel || !HasMethod(io, "Ocr"))
            return ""
        cctx := CleanupCtx(ctx)
        if cctx.ShouldStop()
            return ""
        b := this._Fc()["fishButton"]["rect"]
        waited := 0
        while ((st := this._PanelState()) != "exit") {
            if (blind && this._ReelUp() && !FishingTask.IsFish(io.Ocr(b*)))
                return "bite"                   ; (a button that reads Fish: the line is in)
            if (waited >= waitMs || !io.Wait(250, cctx)) {
                t := Trim(RegExReplace(String(io.Ocr(b*)), "\s+", " "))
                if FishingTask.IsFish(t)
                    return ""                   ; the line is in
                if (blind && this._FishOn(cctx, t))
                    return "bite"
                if blind {
                    this.deps.log.Call("fishing: next task: the button reads '" SubStr(t, 1, 30) "', not Exit - clicked once to reel the line in")
                    FishLogic.ClickAt(io, cctx, [b[1] + b[3] // 2, b[2] + b[4] // 2], 80, 300)
                } else if !quiet
                    this.deps.log.Call("fishing: next task: the button did not read Exit ('" SubStr(t, 1, 30) "'): line left as it is")
                return ""
            }
            waited += 250
        }
        this.deps.log.Call("fishing: line in before the next task")
        FishLogic.ClickAt(io, cctx, [b[1] + b[3] // 2, b[2] + b[4] // 2], 80, 300)
        return ""
    }

    ; The fish is on the line (t: the button's text, neither Exit nor Fish):
    ; the reel prompt, or any other text (the bite) followed by the reel bar
    ; within BiteOnMs. A button that reads nothing (the 1440p waiting panel
    ; with a long tip) is a line out with nothing biting.
    _FishOn(ctx, t) {
        if (RegExMatch(t, FishingTask.ReelRe) || this._ReelUp())
            return true
        if (t = "")
            return false
        io := this.deps.io
        waited := 0
        while (waited < FishingTask.BiteOnMs) {
            if !io.Wait(50, ctx)
                return false
            waited += 50
            if this._ReelUp()
                return true
        }
        return false
    }

    ; The Fish / Exit button reads Exit. Live 2026-11-20 it read 'EX it' (a
    ; space inside) and 'Exim' (t as m): plain "exit" missed both, so the
    ; line was left out before the next task and the failsafe click reeled
    ; it in. Folded (GameText) and t / m alike.
    static IsExit(t) => RegExMatch(GameText.Fold(t), "exi[tm]") > 0

    ; The button reads Fish (the line is in); folded like IsExit.
    static IsFish(t, word := "fish") => GameText.Has(t, word)

    _PanelState() {
        io := this.deps.io
        fc := this._Fc()
        b := fc["fishButton"]["rect"]
        if FishingTask.IsExit(io.Ocr(b[1], b[2], b[3], b[4]))
            return "exit"
        t := fc["panelTitle"]
        r := t["rect"]
        return InStr(StrLower(io.Ocr(r[1], r[2], r[3], r[4])), t["word"]) ? "panel" : ""
    }

    ; Arrow controller (FishLogic.ReelScan / ReelDecide) until minigameCapMs.
    ; -> "ok" | "stopped" | "error" | "nobar" (neither the click bar nor the
    ; fish within FishLogic.ReelSeenMs: not a real bite, nothing clicked; a
    ; screenshot is saved when the io can take one)
    ; The reel is over once the arrow + bar are gone for endMs, or, when the
    ; bar's frame (FishLogic.ReelFrame) read steady for FrameSteady passes
    ; this reel, once the frame is gone for FrameGoneMs: snow kept arrow +
    ; "bar" up after SNOWY reels until the 9 s cap (16 of 19 capped reels,
    ; log 2026-11-15..18). A reel whose frame never reads steady (a dim
    ; screen, an odd size) ends as before, and its border rows are no
    ; longer read after FrameLookPolls passes. The longer FrameGoneMs lets
    ; a frame that flickers mid-reel (something drawn over the border) pass.
    static FrameSteady := 10
    static FrameGoneMs := 1000
    static FrameLookPolls := 60
    ; Input.InReel while it runs: the App's tick leaves its slow work (task
    ; checks with OCR, log reads, webhooks) until the reel is over.
    _Reel(ctx, opt) {
        outer := Input.InReel
        Input.InReel := true
        tr := this.deps.trace
        this._traceHow := ""
        r := "error"
        try
            return r := this._ReelLoop(ctx, opt)
        finally {
            Input.InReel := outer
            if IsObject(tr)
                try tr.End(r . (this._traceHow != "" ? "/" this._traceHow : ""))
        }
    }

    ; ReelTrace's header: where the strip lands and what the controller uses
    _TraceHead(rc) {
        return "client " Screen.cw "x" Screen.ch " ui " Round(Screen.Ui, 2) " white " FishLogic.WhiteMin
            . " dy " FishingTask.ReelDy " x1 " Screen.X(rc["x1"]) " x2 " Screen.X(rc["x2"])
            . " aim " Round(rc["aim"], 3) " lead " rc["leadMs"]
    }
    ; The reel line ends with the slowest capture / work / wait of one pass:
    ; a long wait = something else ran meanwhile (the App's timers), a long
    ; capture = the screen copy stalled, long work = a slow CPU.
    _ReelLoop(ctx, opt) {
        fc := this._Fc()
        rc := fc["reel"]
        io := this.deps.io
        now := this.deps.now
        start := now.Call()
        st := {}
        seen := false
        lastUp := 0
        lastClick := -100000
        blackAt := ""                           ; first all-black pass of the run in a row
        ; empty level learnt from the bar (FishLogic.ReelScan), its source
        em := 0, emOwn := false
        ; the bar's frame: rows to read (narrowed to the one that shows it),
        ; passes in a row it read, steady this reel, last time it read
        bys := rc["borderYs"], frameRun := 0, frameSteady := false, lastFrame := 0
        tr := this.deps.trace
        if IsObject(tr)
            tr.Begin(this._TraceHead(rc))
        ; one line per reel (fishing: reel ...): passes, gaps between them,
        ; clicks; to tell a slow PC (fewer passes) from a slow controller
        polls := 0, firstT := 0, prevT := 0, maxGap := 0, clicks := 0, how := "cap"
        maxGrab := 0, maxWork := 0, maxWait := 0
        while (now.Call() - start <= fc["minigameCapMs"]) {
            if ctx.ShouldStop()
                return "stopped"
            tGrab := now.Call()
            try {
                rows := this._ReelRows(rc, bys)
            } catch as e {
                this._LogOnce("fishing: strip capture failed (" e.Message "); abandoning this catch")
                return "error"
            }
            if FishLogic.AllBlack(rows) {
                ; no click on it; given up only when it stays black (a failed
                ; capture), not on a dark moment of the scene (FishLogic.BlackGraceMs)
                if (blackAt = "")
                    blackAt := tGrab
                if (now.Call() - blackAt >= FishLogic.BlackGraceMs) {
                    this._LogOnce(FishLogic.BlackMsg(this.state, now.Call() - blackAt))
                    return "error"
                }
                if !io.Wait(rc["pollMs"], ctx)
                    return "stopped"
                continue
            }
            blackAt := ""
            t := now.Call()
            maxGrab := Max(maxGrab, t - tGrab)
            if (polls++)
                maxGap := Max(maxGap, t - prevT)
            else
                firstT := t
            prevT := t
            s := FishLogic.ReelScan(rows[1], rows[2], rc["x1"], rc["stride"], em)
            if (s.empty && (s.own || !emOwn))
                em := s.empty, emOwn := emOwn || s.own
            frame := false
            Loop rows.Length - 2 {
                if FishLogic.ReelFrame(rows[A_Index + 2], rows[2]) {
                    frame := true
                    if (bys.Length > 1)
                        bys := [bys[A_Index]]
                    break
                }
            }
            if (!frame && bys.Length = 1 && rc["borderYs"].Length > 1)
                bys := rc["borderYs"]                   ; lost it: every row again
            if (!frameSteady && polls >= FishingTask.FrameLookPolls)
                bys := []                               ; never steady: stop reading it (old end rule)
            up := s.m && (s.p2 || s.fill != "")
            frameRun := (frame && up) ? frameRun + 1 : 0
            if (frameRun >= FishingTask.FrameSteady)
                frameSteady := true
            if (frame && up)
                lastFrame := t
            if up {
                seen := true                            ; arrow + bar up (also "Ready!")
                lastUp := t
            }
            if (seen && (t - lastUp >= rc["endMs"] || (frameSteady && t - lastFrame >= FishingTask.FrameGoneMs))) {
                how := "ended"
                break                                   ; the reel is over (caught or not)
            }
            scan := (s.m && s.p2) ? s : ""
            if !IsObject(scan) {
                if IsObject(tr)
                    tr.Add(t - start, s, {}, false, false)
                if (!seen && t - start >= FishLogic.ReelSeenMs) {
                    shot := HasMethod(io, "Shot") ? io.Shot() : ""
                    if (shot != "")
                        this.deps.log.Call("fishing: reel bar not found; screen saved to " shot)
                    return "nobar"
                }
            } else {
                seen := true
                dec := FishLogic.ReelDecide(scan, st, t, rc["leadMs"], rc["aim"])
                hit := dec && t - lastClick >= rc["clickGapMs"]
                if hit {
                    io.ClickHere()
                    lastClick := t
                    clicks++
                }
                if IsObject(tr)
                    tr.Add(t - start, scan, st, dec, hit)
            }
            tWait := now.Call()
            maxWork := Max(maxWork, tWait - t)
            if !io.Wait(rc["pollMs"], ctx)
                return "stopped"
            maxWait := Max(maxWait, now.Call() - tWait)
        }
        ms := now.Call() - start
        this._traceHow := how
        this.deps.log.Call(Format("fishing: reel {} ms ({}), polls {}, avg gap {} ms, max gap {} ms, clicks {}, empty up to {}{}, frame {}, slowest grab {} / work {} / wait {} ms"
            , ms, how, polls, polls > 1 ? Round((prevT - firstT) / (polls - 1)) : 0, maxGap, clicks
            , em, em ? (emOwn ? " (bar)" : " (short)") : "", frameSteady ? "seen" : "not seen"
            , Round(maxGrab), Round(maxWork), Round(maxWait)))
        this._lastReel := {gap: maxGap, grab: Round(maxGrab), work: Round(maxWork), wait: Round(maxWait)}
        return "ok"
    }

    ; After the reel and its card (never inside the reel loop): the reel's
    ; pauses go to ReelPause; a warning is one log line (FixIt turns it into
    ; a dashboard card, lib\FixIt.ahk "reelpause") and one errors webhook.
    static PauseTitle := "Slow PC: reels keep pausing"
    _PauseCheck(lost) {
        r := this._lastReel
        this._lastReel := ""
        if !IsObject(r)
            return                          ; legacy reel: no pass timings
        r.lost := lost
        w := this._pause.Add(r, this.deps.now.Call())
        if !IsObject(w)
            return
        this.deps.log.Call("fishing: slow PC: " w.text)
        wh := this.deps.webhook
        if (IsObject(wh) && HasMethod(wh, "Send"))
            try wh.Send("errors", FishingTask.PauseTitle, w.text, 0xF2A93B)
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
        blackAt := ""
        while (now.Call() - start <= fc["minigameCapMs"]) {
            if ctx.ShouldStop()
                return "stopped"
            tGrab := now.Call()
            try {
                rows := this.deps.grab.Call(z["x1"], z["x2"], ys, z["stride"])
            } catch as e {
                this._LogOnce("fishing: strip capture failed (" e.Message "); abandoning this catch")
                return "error"
            }
            if FishLogic.AllBlack(rows) {
                if (blackAt = "")
                    blackAt := tGrab
                if (now.Call() - blackAt >= FishLogic.BlackGraceMs) {
                    this._LogOnce(FishLogic.BlackMsg(this.state, now.Call() - blackAt))
                    return "error"
                }
                if !io.Wait(fc["minigamePollMs"], ctx)
                    return "stopped"
                continue
            }
            blackAt := ""
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

    ; No panel right after Sell's walk back: hop forward (HopSteps) up to
    ; state.backHops times, looking for the panel after each.
    ; -> 1 at the spot | 0 no hops left / still no panel | -1 stopped
    _HopToSpot(ctx) {
        st := this.state
        left := st.HasProp("backHops") ? st.backHops : 0
        if (left <= 0)
            return 0
        io := this.deps.io
        Loop left {
            st.backHops := left - A_Index
            this.deps.log.Call("fishing: no fishing panel after the walk back - stepping forward (" A_Index "/" left ")")
            if !Input.PlayRoute(FishingTask.HopSteps, ctx, io)
                return -1
            fb := this._WaitFishButton(ctx)
            if (fb < 0)
                return -1
            if (fb > 0 || this._PanelState() != "") {
                st.backHops := 0
                this._HintVip()
                return 1
            }
        }
        return 0
    }

    ; Once per session: the walk fell short, likely VIP routes without VIP.
    _HintVip() {
        if this.HasOwnProp("_vipHinted")
            return
        this._vipHinted := true
        vip := IsObject(this.cfg) && HasMethod(this.cfg, "Get") ? this.cfg.Get("General.vip", 1) : 1
        this.deps.log.Call("fishing: " (vip ? FishingTask.VipHint : "the walk back stopped short of the fishing spot (hopped forward onto it)"))
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
