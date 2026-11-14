#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\FishLogic.ahk
; ---------------------------------------------------------------------------
; SellTask: walk the timed route to the seller, sell, walk back (priority 6).
;
;   task := SellTask(cfg, state [, deps])
;   .CanRun(state): FishLogic.SellDue: state.fishLoops >= General.sellEvery,
;                   or state.needRepath (Start / fishing failsafe re-path)
;   .Run(ctx): a re-path after MaxRepathStreak re-paths in a row without a
;              catch (state.repathStreak, FishingTask) does NOT walk again:
;              something on screen is stuck open (a shop, a menu), so the
;              macro is paused (ctx.Pause) and deps.stuck(msg) reports it.
;              On success state.fishLoops := 0 and state.needRepath := false;
;              if stopped part way both are left untouched, so the next Sell
;              run starts over (it begins with a reset to spawn, which also
;              fixes a half-finished walk).
;
; Sequence:
;   Roblox focus -> Input.ResetToSpawn -> claim the daily reward if its green
;   button is up (max 3x) -> camera zoom (wheel) -> route "toShop" (VIP or
;   non-VIP, General.vip, default 1 = VIP) -> the route's E must open
;   Captain Flarg's dialog (OCR via io.Ocr), else reset + walk again, up to
;   SellTask.WalkTries walks (a failed checked reset also uses up a walk).
;   The last walk never gives up: its reset falls back to the blind FishSol
;   sequence and a missing dialog is logged and the shop tried anyway, so a
;   misread screen is never worse than the old blind flow -> open the shop
;   dialog -> sell
;   rounds (sell-all or selected, General.sellAll) while the item list still
;   shows white -> close the shop (its X until the title is gone) -> the
;   buy (deps.afterSell) -> leave Captain Flarg's dialog (his buttons stay
;   up after the shop's X: deps.cal "fisher_leave") -> route "back".
;   The Fishing Shop never opened -> nothing was sold, so it is NOT a sell:
;   his dialog is left, fishLoops / needRepath stay and Sell runs again;
;   MaxShopMisses such visits in a row pause the macro (deps.stuck).
;   Preempted at the fisher (a higher task due; not F3 / pause): the Sell
;   Confirm popup is cancelled, the shop closed and his dialog left first.
;   The window checks need io.Ocr; without it the old blind flow runs.
;
; deps (FishLogic.Deps) also: afterSell(ctx), stuck(msg), cal (object with
; Point(id): fisher_leave / fisher_open_shop; the App passes Calibrate).
;
; Routes come from data\routes.json (Input.PlayRoute format); coordinates,
; colors and timings from data\coords.json.
; ---------------------------------------------------------------------------

class SellTask {
    name := "sell"
    priority := 6

    __New(cfg, state, deps := "") {
        this.cfg := cfg
        this.state := state
        this.deps := FishLogic.Deps(deps)
        this._coords := FishLogic.Require("SellTask", cfg)
        this._routes := cfg.Data("routes")
        this._shopMisses := 0       ; visits in a row whose shop never opened
    }

    ; Walks per run (the last one goes on even when its checks fail).
    static WalkTries := 3
    ; Re-paths in a row without a catch before the macro pauses itself.
    static MaxRepathStreak := 4
    ; _SellRounds: the Fishing Shop never opened (nothing sold, not a sell).
    static ShopMissed := 2
    ; Visits in a row whose shop never opened before the macro pauses (else
    ; it would walk to the fisher and back forever without fishing).
    static MaxShopMisses := 3
    ; Clicks on the shop's X / his Leave before reporting; how long the shop
    ; title may take to go after an X click; the wait after Leave.
    static CloseTries := 3
    static CloseGoneMs := 1000
    static LeaveMs := 500
    ; Captain Flarg's buttons (Open Shop / Sell / Leave), read around the
    ; fisher_open_shop point (the box Craft reads; game font: "Sh0p", "Leove").
    static ButtonBox := {dx: -150, dy: -35, w: 300, h: 70, re: "i)sh[ao0]p|sell|le[ao]ve"}
    ; Short hops forward + E (routes.json "nudge") after a walk that stopped
    ; short, before a full re-walk.
    static Nudges := 3
    ; Captain Flarg's dialog after the route's E (2560x1440 px, read
    ; 2026-10-25): title "Captain Flarg" (stylized font) over the body and
    ; "Click to skip." (plain font), body "Avvvvvv... What do you want??".
    ; Any word below = the dialog is open. Read at 2x (small grey text).
    static FisherCheck := {x: 960, y: 915, w: 940, h: 265, scale: 2, waitMs: 2500, pollMs: 250
        , words: ["skip", "click", "flarg", "florg", "captain", "want", "avvv"]}

    _fisherText := ""     ; last OCR read of the dialog area (for the log)

    CanRun(state) => FishLogic.SellDue(state, this.cfg)

    Run(ctx) {
        d := this.deps
        io := d.io
        if ctx.ShouldStop()
            return
        streak := this.state.HasProp("repathStreak") ? this.state.repathStreak : 0
        if (this.state.needRepath && streak >= SellTask.MaxRepathStreak) {
            msg := "re-walked " streak " times in a row without catching a fish, so the macro is PAUSED."
                . " Something on screen is probably stuck open (a shop, a dialog, the Roblox menu): close it, then press F2."
            d.log.Call("sell: " msg)
            if (d.HasOwnProp("stuck") && IsObject(d.stuck))
                try d.stuck.Call(msg)
            this.state.repathStreak := 0          ; F2 gives it fresh tries
            if HasMethod(ctx, "Pause")
                ctx.Pause()
            return
        }
        if !FishLogic.FocusOrWait(d, ctx, "sell")
            return
        d.log.Call("sell: starting")
        tS := A_TickCount, tR := tS, tC := tS      ; per-trip timing line (speed work)
        opt := FishLogic.Settings(this.cfg, this._coords)
        variant := opt.vip ? "vip" : "nonvip"
        Loop SellTask.WalkTries {
            last := (A_Index = SellTask.WalkTries)
            if (A_Index > 1)
                d.log.Call("sell: walking again from spawn (try " A_Index "/" SellTask.WalkTries ")")
            ; the full waits: with the quick ones (hunts) the camera re-aim's
            ; clicks came too fast and the walk sometimes went off toward the
            ; portal (live 2026-11-10); every walk test used these
            if !Input.ResetToSpawn(ctx, io) {
                if ctx.ShouldStop()
                    return
                d.log.Call("sell: reset failed: " Input.LastResetError)
                if !last
                    continue
                d.log.Call("sell: last try - resetting without screen checks")
                if !Input.ResetToSpawn(ctx, io, true)
                    return
            }
            tR := A_TickCount
            if !this._DailyReward(ctx)
                return
            if !this._Camera(ctx)
                return
            tC := A_TickCount
            if !Input.PlayRoute(this._Walk(variant, "toShop"), ctx, io)
                return this._Cleanup(ctx)
            r := this._AtFisher(ctx)
            nudge := this._routes.Has("nudge") ? this._routes["nudge"]["steps"] : []
            Loop (nudge.Length ? SellTask.Nudges : 0) {
                if (r != 0)
                    break
                d.log.Call("sell: not at the fisher yet - hopping forward (" A_Index "/" SellTask.Nudges ")")
                if !Input.PlayRoute(nudge, ctx, io)
                    return this._Cleanup(ctx)
                r := this._AtFisher(ctx)
            }
            if (r < 0)
                return this._Cleanup(ctx)
            if r
                break
            seen := SubStr(RegExReplace(this._fisherText, "\s+", " "), 1, 60)
            shot := HasMethod(io, "Shot") ? io.Shot() : ""
            if (shot != "")
                d.log.Call("sell: screen at the miss saved to " shot)
            if last {
                d.log.Call("sell: Captain Flarg's dialog not seen after " SellTask.WalkTries " walks (read: '" seen "') - trying the shop anyway")
                break
            }
            d.log.Call("sell: Captain Flarg's dialog did not open, the walk missed the shop (read: '" seen "')")
        }
        tW := A_TickCount
        ; nothing caught since the last sell (the walk back after a hunt, the
        ; obby or a lost fishing spot): his shop has nothing to sell, so it is
        ; skipped - live 2026-11-10: 77 of 132 trips sold 0 fish, ~8 s each in
        ; the shop. The start-of-run sell (fish from before) always sells.
        empty := (this.state.HasProp("fishLoops") ? this.state.fishLoops : 0) = 0
            && !(this.state.HasProp("startSell") && this.state.startSell)
        if empty {
            d.log.Call("sell: nothing caught since the last sell - skipping the shop")
            ; his text first: the Leave button only shows once it is clicked
            ; through (live 10:28: three Leave clicks on the text did nothing)
            if !this._SkipText(ctx)
                return this._Cleanup(ctx)
        } else {
            if !this._Dialog(ctx)
                return this._Cleanup(ctx)
            r := this._SellRounds(ctx, opt)
            if (r < 0)
                return this._Cleanup(ctx)
            if (r = SellTask.ShopMissed) {
                ; nothing was sold, so this is not a sell: fishLoops and
                ; needRepath stay and Sell runs again from a respawn, instead of
                ; fishing a full sellEvery first (2026-10-27 review). His dialog
                ; is left so the next task does not start with it open.
                if (this._LeaveDialog(ctx) < 0)
                    return this._Cleanup(ctx)
                this._shopMisses += 1
                if (this._shopMisses >= SellTask.MaxShopMisses) {
                    msg := "the Fishing Shop did not open on " this._shopMisses " visits in a row, so the macro is PAUSED."
                        . " Check Captain Flarg's dialog clicks (Setup) or close what is open, then press F2."
                    d.log.Call("sell: " msg)
                    if (d.HasOwnProp("stuck") && IsObject(d.stuck))
                        try d.stuck.Call(msg)
                    this._shopMisses := 0             ; F2 gives it fresh tries
                    if HasMethod(ctx, "Pause")
                        ctx.Pause()
                }
                return
            }
            this._shopMisses := 0
            ; one X click could be lost and leave the whole shop open for the
            ; walk back (2026-10-27 review): clicked until its title is gone
            c := this._CloseShop(ctx)
            if (c < 0)
                return this._Cleanup(ctx)
            if (c = 0)
                d.log.Call("sell: the Fishing Shop is still open after " SellTask.CloseTries " clicks on its X")
        }
        ; still at the fisher: buy now if a buy is due (deps.afterSell, the
        ; App wires CraftTask.BuyHere) -> sell, buy, then back to fishing
        if (d.HasOwnProp("afterSell") && IsObject(d.afterSell)) {
            r := 0
            try r := d.afterSell.Call(ctx)
            catch Any as e
                d.log.Call("sell: buying at the fisher failed: " (e is Error ? e.Message : "error"))
            if (r < 0 || ctx.ShouldStop())
                return this._Cleanup(ctx)
        }
        ; his Open Shop / Sell / Leave buttons stay up after the shop's X: a
        ; walk back with them open covers the fishing panel, fishing re-paths
        ; and Sell runs again until the stuck pause (2026-10-27 review)
        g := this._LeaveDialog(ctx)
        if (g < 0)
            return this._Cleanup(ctx)
        if (g = 0)
            d.log.Call("sell: Captain Flarg's dialog is still open"
                . (IsObject(this._CalPoint("fisher_leave")) ? "" : " (record fisher_leave in Setup so it can be closed)"))
        tL := A_TickCount
        if !Input.PlayRoute(this._Walk(variant, "back"), ctx, io)
            return
        d.log.Call(Format("sell: trip {:.1f} s (respawn {:.1f}, camera {:.1f}, walk {:.1f}, fisher {:.1f}, back {:.1f})"
            , (A_TickCount - tS) / 1000, (tR - tS) / 1000, (tC - tR) / 1000, (tW - tC) / 1000, (tL - tW) / 1000, (A_TickCount - tL) / 1000))
        this.state.fishLoops := 0
        this.state.needRepath := false
        FishLogic.Bump(this.state, "sells")
        d.log.Call("sell: done")
    }

    ; Claims the daily reward popup when its green button is showing.
    _DailyReward(ctx) {
        dr := this._coords["sell"]["dailyReward"]
        io := this.deps.io
        r := dr["rect"]
        xs := FishLogic.Xs(r[1], r[3], dr["stride"])
        Loop dr["maxTries"] {
            if !FishLogic.GridHas(xs, dr["rows"], dr["color"], dr["tol"])
                return true
            if !FishLogic.ClickAt(io, ctx, dr["claim"], dr["gapMs"], dr["gapMs"])
                return false
            if !FishLogic.ClickAt(io, ctx, dr["close"], dr["gapMs"], dr["gapMs"])
                return false
        }
        return true
    }

    _Camera(ctx) => FishLogic.Zoom(this.deps.io, ctx, this._coords["sell"]["camera"])

    ; Is Captain Flarg's dialog up? -> 1 | 0 (not within waitMs) | -1 stopped.
    ; An io without Ocr (test recorders) is taken as yes.
    _AtFisher(ctx) {
        io := this.deps.io
        if !HasMethod(io, "Ocr")
            return 1
        c := SellTask.FisherCheck
        waited := 0
        Loop {
            this._fisherText := io.Ocr(c.x, c.y, c.w, c.h, c.scale)
            txt := StrLower(this._fisherText)
            for w in c.words
                if InStr(txt, w)
                    return 1
            if (waited >= c.waitMs)
                return 0
            if !io.Wait(c.pollMs, ctx)
                return -1
            waited += c.pollMs
        }
    }

    ; Opens the seller's dialog after the route's `e` press.
    ; The walk to Captain Flarg / back to the fishing spot: the user's own
    ; recordings (Setup > Routes: sell_to_fisher, fisher_to_fishing) when
    ; present, else the shipped vip / nonvip walk. sell_to_fisher is
    ; recorded up to Flarg; E is pressed after it here (TrimInteract drops a
    ; recorded E at the end).
    _Walk(variant, which) {
        own := (which = "toShop") ? "sell_to_fisher" : "fisher_to_fishing"
        if (this._routes.Has(own) && this._routes[own] is Map && this._routes[own].Has("steps")) {
            raw := this._routes[own]["steps"]
            ok := false
            try ok := (raw is Array) && Input.ParseRoute(raw).Length > 0   ; a broken recording falls back
            if ok {
                steps := raw.Clone()
                if (which = "toShop")
                    steps.Push(["e", "down", 300], ["e", "up", 300])
                return steps
            }
        }
        return this._routes[variant][which]
    }

    ; Clicks through Captain Flarg's text (the dialog's A clicks) so his
    ; Open Shop / Sell / Leave buttons show. -> false when stopped.
    _SkipText(ctx) {
        dlg := this._coords["sell"]["dialog"]
        io := this.deps.io
        a := dlg["a"]
        io.MoveTo(a[1], a[2])
        if !io.Wait(dlg["aGapMs"], ctx)
            return false
        Loop dlg["aClicks"] {
            io.ClickHere()
            if !io.Wait(A_Index < dlg["aClicks"] ? dlg["aGapMs"] : dlg["aAfterMs"], ctx)
                return false
        }
        return true
    }

    _Dialog(ctx) {
        dlg := this._coords["sell"]["dialog"]
        io := this.deps.io
        a := dlg["a"]
        io.MoveTo(a[1], a[2])
        if !io.Wait(dlg["aGapMs"], ctx)
            return false
        Loop dlg["aClicks"] {
            io.ClickHere()
            if !io.Wait(A_Index < dlg["aClicks"] ? dlg["aGapMs"] : dlg["aAfterMs"], ctx)
                return false
        }
        return FishLogic.ClickAt(io, ctx, dlg["b"], dlg["bPreMs"], dlg["bAfterMs"])
    }

    ; Shop screens (2560x1440 px, read from a 2026-10-25 recording):
    ;   title  "Fishing Shop" top left of the shop window
    ;   popup  "Sell Confirm" / "Do you really want to sell all of your X?"
    ; In this shop Sell All sells every fish of the SELECTED type, so a run
    ; is one round per fish type; the checks replace FishSol's fixed 3 s
    ; start delay and its shop-loaded pixel (593,795 now sits on a white
    ; frame corner, so every round sat out the 5 s timeout).
    ; confirmTries: Sell presses on the popup (a press can be lost: clip
    ; 2026-10-26 22:42, the popup stayed while the loop went on); cancel:
    ; the popup's Cancel, pressed when it never closes (tests\screens).
    ; PopupRe: the popup's text in the game font. Live 2026-10-27 it read
    ; "you reo y wont to sell oll your Pironho?" (no "really" / "want"), so
    ; the sell gave up on a popup that was there and walked off with it open.
    static PopupRe := "i)re[ao]\s*[lI1|]*\s*y\b|w[ao]nt\s*t[o0]\s*sell|c[o0]nf[iIl1|]rm"
    ; The popup's Cancel button reads "Concel" in the game font (tests\screens).
    static CancelRe := "i)c[ao]nc[ae][lI1|]"
    static ShopChecks :={pollMs: 150, openMs: 6000, settleMs: 150, popupMs: 3000, afterSellMs: 350
        , confirmTries: 3, cancel: [1492, 830], cancelBox: {dx: -150, dy: -35, w: 300, h: 70}
        , title: {x: 570, y: 325, w: 380, h: 70, words: ["fishing", "shop"]}
        , popup: {x: 970, y: 585, w: 640, h: 165, re: SellTask.PopupRe}}

    ; The second look at the popup (after a 1x read missed it): its text read
    ; at scale 2 (t2), or its Cancel button's label (tCancel).
    static PopupSecond(t2, tCancel) => SellTask.Seen(SellTask.ShopChecks.popup, t2) || RegExMatch(tCancel, SellTask.CancelRe) > 0

    ; A screen check reads: c.re matches, or (without re) one of c.words.
    static Seen(c, txt) {
        if c.HasOwnProp("re")
            return RegExMatch(txt, c.re) > 0
        txt := StrLower(txt)
        for w in c.words
            if InStr(txt, w)
                return true
        return false
    }

    ; With io.Ocr: wait for the shop, then per round (while the first fish
    ; tile is there) select it, Sell All / Sell, wait for the confirm popup,
    ; confirm, wait for it to close. No popup -> stop selling (logged).
    ; Without io.Ocr: the FishSol timed rounds (_SellRoundsBlind).
    ; -> 1 done | ShopMissed (the shop never opened: nothing sold) | -1 stopped
    _SellRounds(ctx, opt) {
        io := this.deps.io
        if !HasMethod(io, "Ocr")
            return this._SellRoundsBlind(ctx, opt) ? 1 : -1
        d := this.deps
        sc := SellTask.ShopChecks
        lp := this._coords["sell"]["loop"]
        option := opt.sellAll ? lp["sellAll"] : lp["sellSelected"]
        more := lp["more"]
        moreXs := FishLogic.Xs(more["rect"][1], more["rect"][3], more["stride"])
        r := this._WaitText(ctx, sc.title, true, sc.openMs)
        if (r < 0)
            return -1
        if (r = 0) {
            d.log.Call("sell: the Fishing Shop did not open")
            return SellTask.ShopMissed
        }
        if !io.Wait(sc.settleMs, ctx)
            return -1
        sold := 0
        Loop lp["maxRounds"] {
            ; the list may still be drawing (after the shop opened or a
            ; sale): it counts as empty only after GridWaitMs of looking
            r := this._GridWait(ctx, moreXs, more)
            if (r < 0)
                return -1
            if !r
                break
            if !FishLogic.ClickAt(io, ctx, lp["item"], lp["itemPreMs"], lp["itemPostMs"])
                return -1
            if !FishLogic.ClickAt(io, ctx, option, lp["optionPreMs"], 0)
                return -1
            ; the Sell Confirm popup scales evenly and stays centred where the
            ; shop stretches (16:10, live 1440x900): its reads and clicks map
            ; in Screen mode "C" (the same pixels at 16:9)
            r := Screen.WithMode("C", () => this._WaitText(ctx, sc.popup, true, sc.popupMs))
            if (r < 0)
                return -1
            if (r = 0) {
                ; a 1x read can miss a popup that is up (live and clip reads
                ; differ): one more look at 2x and at its Cancel label before
                ; walking off with it open (2026-10-27 review)
                if !this._PopupSecondLook() {
                    d.log.Call("sell: no Sell Confirm popup after the sell click - stopping")
                    break
                }
                d.log.Call("sell: the Sell Confirm popup is up after all (second look) - pressing Sell")
            }
            closed := false
            Loop sc.confirmTries {
                if (A_Index > 1) {
                    d.log.Call("sell: the Sell Confirm popup is still open - pressing Sell again")
                    Screen.WithMode("C", () => io.MoveTo(lp["confirm"][1] + 4, lp["confirm"][2] + 3))    ; a small move first
                    if !io.Wait(80, ctx)
                        return -1
                }
                if !Screen.WithMode("C", () => FishLogic.ClickAt(io, ctx, lp["confirm"], lp["confirmPreMs"], 0))
                    return -1
                r := this._WaitPopupGone(ctx)
                if (r < 0)
                    return -1
                if (r = 1) {
                    closed := true
                    break
                }
            }
            if !closed {
                ; never leave it open: everything after the sell (the buy, the
                ; walk back) would click under it
                d.log.Call("sell: the Sell Confirm popup did not close after " sc.confirmTries " presses - Cancel, stopping the sell")
                if !Screen.WithMode("C", () => FishLogic.ClickAt(io, ctx, sc.cancel, lp["confirmPreMs"], 0))
                    return -1
                if (this._WaitPopupGone(ctx) < 0)
                    return -1
                break
            }
            if !io.Wait(sc.afterSellMs, ctx)
                return -1
            sold++
        }
        d.log.Call("sell: sold " sold " fish type" (sold = 1 ? "" : "s"))
        FishLogic.Bump(this.state, "fishTypesSold", sold)
        return 1
    }

    ; The Sell Confirm popup is up: its text at 1x, else the second look.
    _PopupUp() => Screen.WithMode("C", () => this._PopupUpM())
    _PopupUpM() {
        c := SellTask.ShopChecks.popup
        if SellTask.Seen(c, this.deps.io.Ocr(c.x, c.y, c.w, c.h))
            return true
        return this._PopupSecondLook()
    }

    ; Its text at scale 2 (the game font misreads at 1x) or its Cancel label.
    _PopupSecondLook() => Screen.WithMode("C", () => this._PopupSecondLookM())
    _PopupSecondLookM() {
        io := this.deps.io
        sc := SellTask.ShopChecks
        c := sc.popup, b := sc.cancelBox
        return SellTask.PopupSecond(io.Ocr(c.x, c.y, c.w, c.h, 2)
            , io.Ocr(sc.cancel[1] + b.dx, sc.cancel[2] + b.dy, b.w, b.h))
    }

    ; Polls until the popup is gone by every read (_PopupUp): a 1x read alone
    ; can miss it and call it closed. -> 1 gone | 0 still up | -1 stopped
    _WaitPopupGone(ctx) {
        io := this.deps.io
        sc := SellTask.ShopChecks
        waited := 0
        Loop {
            if !this._PopupUp()
                return 1
            if (waited >= sc.popupMs)
                return 0
            if !io.Wait(sc.pollMs, ctx)
                return -1
            waited += sc.pollMs
        }
    }

    ; The Fishing Shop's title reads right now.
    _ShopUp() {
        t := SellTask.ShopChecks.title
        return SellTask.Seen(t, this.deps.io.Ocr(t.x, t.y, t.w, t.h))
    }

    ; Clicks the shop's X until its title is gone (io.Ocr), up to CloseTries
    ; clicks. -> 1 closed (or no io.Ocr) | 0 still open | -1 stopped
    _CloseShop(ctx) {
        io := this.deps.io
        sc := this._coords["sell"]
        Loop SellTask.CloseTries {
            if !FishLogic.ClickAt(io, ctx, sc["close"], sc["closePreMs"], sc["closePostMs"])
                return -1
            if !HasMethod(io, "Ocr")
                return 1
            r := this._WaitText(ctx, SellTask.ShopChecks.title, false, SellTask.CloseGoneMs)
            if (r < 0)
                return -1
            if (r = 1)
                return 1
            this.deps.log.Call("sell: the Fishing Shop is still open after its X (try " A_Index "/" SellTask.CloseTries ")")
        }
        return 0
    }

    ; Captain Flarg's dialog is up: his text (FisherCheck), or his buttons
    ; around fisher_open_shop when that point is recorded.
    _DialogUp() {
        io := this.deps.io
        c := SellTask.FisherCheck
        txt := StrLower(io.Ocr(c.x, c.y, c.w, c.h, c.scale))
        for w in c.words
            if InStr(txt, w)
                return true
        pt := this._CalPoint("fisher_open_shop")
        if !IsObject(pt)
            return false
        b := SellTask.ButtonBox
        return RegExMatch(io.Ocr(pt.x + b.dx, pt.y + b.dy, b.w, b.h), b.re) > 0
    }

    ; While his dialog is up, click Leave (fisher_leave), up to CloseTries.
    ; -> 1 gone (or no io.Ocr) | 0 still up | -1 stopped
    _LeaveDialog(ctx) {
        io := this.deps.io
        if !HasMethod(io, "Ocr")
            return 1
        leave := this._CalPoint("fisher_leave")
        Loop SellTask.CloseTries {
            if !this._DialogUp()
                return 1
            if !IsObject(leave)
                return 0
            this.deps.log.Call("sell: Captain Flarg's dialog is still up - Leave")
            if !FishLogic.ClickAt(io, ctx, [leave.x, leave.y], 0, SellTask.LeaveMs)
                return -1
        }
        return this._DialogUp() ? 0 : 1
    }

    ; The App's between-tasks check (Tidy): the Sell Confirm popup (its
    ; Cancel), the Fishing Shop (its X) and Captain Flarg's dialog (Leave),
    ; each only when it reads. Without io.Ocr: nothing.
    Leftovers() {
        io := this.deps.io
        if !HasMethod(io, "Ocr")
            return []
        lp := this._coords["sell"]["loop"]
        popup := {up: () => this._PopupUp() ? "Sell Confirm popup" : ""
            , close: (label, ctx) => !Screen.WithMode("C", () => FishLogic.ClickAt(io, ctx, SellTask.ShopChecks.cancel, lp["confirmPreMs"], 0)) ? -1
                : (r := this._WaitPopupGone(ctx)) < 0 ? -1 : r ? 1 : 2}
        shop := {up: () => this._ShopUp() ? "Fishing Shop" : ""
            , close: (label, ctx) => (r := this._CloseShop(ctx)) < 0 ? -1 : r ? 1 : 2}
        dialog := {up: () => this._DialogUp() ? "Captain Flarg dialog" : ""
            , close: (label, ctx) => (r := this._LeaveDialog(ctx)) < 0 ? -1 : r ? 1 : 2}
        return [popup, shop, dialog]
    }

    ; A calibrated point from deps.cal, or "" (no cal / not recorded).
    _CalPoint(id) {
        d := this.deps
        if !(d.HasOwnProp("cal") && IsObject(d.cal))
            return ""
        p := ""
        try p := d.cal.Point(id)
        return IsObject(p) ? p : ""
    }

    ; Told to stop at the fisher. ShouldStop() is also true on a preempt (a
    ; higher task is due), and every return then left the popup, the shop or
    ; his dialog open for the next task (2026-10-27 review). On a preempt
    ; the popup is cancelled, the shop closed and his dialog left, each only
    ; when it is seen. A real halt (F3 / pause / Roblox not in front) sends
    ; nothing. Needs io.Ocr.
    _Cleanup(ctx) {
        io := this.deps.io
        if (!ctx.ShouldStop() || CleanupCtx.Halted(ctx) || !HasMethod(io, "Ocr"))
            return
        cc := CleanupCtx(ctx)
        this.deps.log.Call("sell: preempted at the fisher - closing what is open first")
        if this._PopupUp() {
            lp := this._coords["sell"]["loop"]
            if !Screen.WithMode("C", () => FishLogic.ClickAt(io, cc, SellTask.ShopChecks.cancel, lp["confirmPreMs"], 0))
                return
            if (this._WaitPopupGone(cc) < 0)
                return
        }
        if (this._ShopUp() && this._CloseShop(cc) < 0)
            return
        this._LeaveDialog(cc)
    }

    ; Polls OCR rect c until one of c.words is present (want true) or none
    ; is (want false). -> 1 | 0 timeout | -1 stopped
    _WaitText(ctx, c, want, timeoutMs) {
        io := this.deps.io
        sc := SellTask.ShopChecks
        waited := 0
        Loop {
            has := SellTask.Seen(c, io.Ocr(c.x, c.y, c.w, c.h))
            if (has = want)
                return 1
            if (waited >= timeoutMs)
                return 0
            if !io.Wait(sc.pollMs, ctx)
                return -1
            waited += sc.pollMs
        }
    }

    ; The first fish tile shows within GridWaitMs. -> 1 | 0 none | -1 stopped
    static GridWaitMs := 600
    _GridWait(ctx, xs, more) {
        io := this.deps.io
        waited := 0
        Loop {
            if FishLogic.GridHas(xs, more["rows"], more["color"], more["tol"])
                return 1
            if (waited >= SellTask.GridWaitMs)
                return 0
            if !io.Wait(SellTask.ShopChecks.pollMs, ctx)
                return -1
            waited += SellTask.ShopChecks.pollMs
        }
    }

    ; FishSol's timed rounds (no screen text checks).
    _SellRoundsBlind(ctx, opt) {
        lp := this._coords["sell"]["loop"]
        io := this.deps.io
        option := opt.sellAll ? lp["sellAll"] : lp["sellSelected"]
        more := lp["more"]
        moreXs := FishLogic.Xs(more["rect"][1], more["rect"][3], more["stride"])
        Loop lp["maxRounds"] {
            if !io.Wait(lp["startDelayMs"], ctx)
                return false
            if !FishLogic.ClickAt(io, ctx, lp["item"], lp["itemPreMs"], lp["itemPostMs"])
                return false
            if !FishLogic.ClickAt(io, ctx, option, lp["optionPreMs"], lp["optionPostMs"])
                return false
            loaded := this._WaitLoaded(ctx, lp["loaded"])
            if (loaded = "stopped")
                return false
            if (loaded = "timeout") {
                if !FishLogic.ClickAt(io, ctx, lp["loaded"]["closeClick"], lp["loaded"]["closePreMs"], 0)
                    return false
            }
            if !io.Wait(lp["afterLoadMs"], ctx)
                return false
            if !FishLogic.ClickAt(io, ctx, lp["confirm"], lp["confirmPreMs"], lp["confirmPostMs"])
                return false
            if !FishLogic.GridHas(moreXs, more["rows"], more["color"], more["tol"])
                break
        }
        return true
    }

    ; Waits for the shop-loaded pixel. -> "loaded" | "timeout" | "stopped"
    _WaitLoaded(ctx, ld) {
        io := this.deps.io
        now := this.deps.now
        px := ld["pixel"]
        start := now.Call()
        Loop {
            if ctx.ShouldStop()
                return "stopped"
            if Pixel.Is(px[1], px[2], ld["color"], ld["tol"])
                return "loaded"
            if (now.Call() - start >= ld["timeoutMs"])
                return "timeout"
            if !io.Wait(ld["pollMs"], ctx)
                return "stopped"
        }
    }
}
