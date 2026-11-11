#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\TaskEnv.ahk
#Include %A_LineFile%\..\FishLogic.ahk
#Include %A_LineFile%\..\..\GameLists.ahk
; ---------------------------------------------------------------------------
; CraftTask: buy potions from the fisher, optionally visit Stella's cauldron
; (spec 4.3, priority 4).
;
;   t := CraftTask(deps)   deps as TaskEnv (cfg, webhook, log, io, cal, pixel,
;                          now) plus  roblox  (object with Focus(), default Roblox)
;   t.name = "craft", t.priority = 4   (Scheduler task contract)
;   t.CanRun(state)  true on the first run since start, after an aborted run, or
;                    when the game's crafted notification ("... crafted
;                    ...", read by OCR in the calibrated notify_rect, at
;                    most every NotifyPollMs) shows AND at least
;                    Craft.minIntervalMin (default 10) minutes have passed
;                    since the last Run started (no loop of fisher trips).
;                    A seen notification is latched until Run happens, so
;                    a fading toast is not lost. Without notify_rect only
;                    the first run happens. false when Craft.enabled = 0.
;   t.Run(ctx)       -> number of potions whose confirm was clicked with the shop UI seen.
;
; SETTINGS (settings.ini [Craft]; defaults in Config.IniDefaults)
;   enabled      1                       task on/off
;   potions      Lucky Potion                comma list of full names, each must be
;                                        sold in the Fisher shop (GameLists.Shop;
;                                        Calibrate.Potions()
;                                        validates it: the app must have called
;                                        Calibrate.Use(path, cfg))
;   qty          1                       units per potion per visit (1..999)
;   minIntervalMin 10                    minutes between notification-triggered
;                                        runs (1..1440; else 10)
;   qty_<id>     (optional)              per-potion override; <id> is the potion
;                                        name lower-cased, non-alphanumerics as "_"
;                                        (qty_lucky_potion = 3)
;   cauldron     0                       1 = also visit Stella's cauldron
;   craftTarget  ""                      a Stella recipe (GameLists.Recipes); its
;                                        GameLists.SearchName is typed into the
;                                        cauldron search box (empty = step skipped)
;   General.vip  (shared with Sell)      picks vip / nonvip route
;
; DATA
;   Fisher = the same NPC and path as Sell: routes vip|nonvip .toShop / .back
;   (data\routes.json; toShop ends with the E press that opens the dialog). The
;   dialog clicks and shop-close click are data\coords.json "craft" (FishSol
;   1440p values). Camera zoom reuses coords sell.camera. Route "cauldron"
;   (spawn -> a spot OUT of Stella's range) ships EMPTY ("_todo": "record in
;   game"): movement is never invented.
;
; FLOW
;   Preflight (nothing is pressed or clicked unless a part is fully
;   configured; each missing item is logged + one errors webhook per session):
;     buy part: >=1 potion with a fisher_item_<potion> point (its tile),
;       fisher_buy_button, fisher_qty, fisher_confirm, fisher_purchase_close,
;       fisher_open_shop, the fisher_picked_name rect (the picked item's name
;       in the shop; nothing is bought without reading it), the craft coords
;       and the fisher routes. fisher_leave (Captain Flarg's Leave button) is
;       optional.
;     cauldron part (Craft.cauldron=1): craftTarget, the rects cauldron_gui
;       (the "Stella's Workshop" title) and cauldron_result (the first search
;       result card), the points cauldron_search, _open_recipe, _add_all,
;       _close, and a NON-EMPTY cauldron route.
;   Roblox focus (failure -> log, ctx-aware wait, retry later) -> ResetToSpawn.
;   Buy: camera zoom -> toShop route -> dialog clicks -> Captain Flarg shows
;     two buttons, Sell Fish and Open Shop: wait up to ShopWaitMs until OCR
;     around fisher_open_shop reads "shop" (and not "sell"), then click it.
;     Never seen -> nothing else is clicked or typed, the visit reports it
;     (errors webhook) and goes back. Then per potion:
;     PICK: the shop grid keeps its scroll position (a player may leave it
;     scrolled down), so first scroll it to the top (wheel up over the tile),
;     click the potion's tile (fisher_item_<potion>) and READ the picked
;     item's name (fisher_picked_name, OCR). Not the potion -> one wheel notch
;     down and click / read again, up to ScrollTries times. Never found ->
;     Buy is NOT pressed, the potion is reported and skipped.
;     BUY: the Buy button (fisher_buy_button, the same for every potion),
;     THEN check the purchase window: the fisher_confirm pixel matches its
;     calibrated color OR its title "Confirm Purchase" reads in PurchaseTitle
;     (placed from fisher_confirm). The pixel alone is not enough: the
;     button shows the price in cyan and the digits move with the price
;     ("25" vs "2,500"), so a pixel recorded on a digit can miss. Not seen -> nothing typed, one retry, then errors
;     webhook (fishing continues). Seen -> click fisher_qty, Input.ClearText, type
;     qty, re-check the pixel, click fisher_confirm. The purchase window stays
;     open after a purchase: close it (fisher_purchase_close) and check that
;     the pixel is gone (up to CloseTries clicks); a failed try closes it too.
;     CLOSE: click the shop's X (fisher_shop_close; not recorded = coords
;     craft.close) until the name box no longer shows a shop item (up to
;     CloseTries), then make sure Captain Flarg's dialog is gone (the box
;     around fisher_open_shop reads none of Open Shop / Sell / Leave; else
;     click fisher_leave). Anything still open is reported as an error.
;   After buying: with the cauldron part, ResetToSpawn; otherwise the "back" route.
;   SAME VISIT AS THE SELL: when a buy is due (BuyDue) while Sell is at the
;   fisher, Sell calls BuyHere right after closing its shop: E (skipped when
;   his Open Shop button is still up, or when the Fishing Shop itself is
;   still open: E over the open shop brings his dialog back on top of it and
;   its "Click to skip" eats the next tile click), dialog, Open Shop, the
;   Buy tab, buy, close; Sell then walks back. No second trip.
;   Open Shop never readable (ShopWaitMs, one extra skip click halfway) ->
;   nothing is bought and Captain Flarg's dialog is LEFT (fisher_leave) and
;   checked, so the walk back never starts with his dialog open. In BuyHere
;   the buy then stays due, so a craft trip retries it.
;   PREEMPTED at Captain Flarg (a higher task is due; not F3 / pause): the
;   purchase window, the shop and his dialog are closed first (checked), so
;   the next task does not start with them on screen.
;   Cauldron: play the cauldron route, then press F (never earlier). Open =
;     OCR of cauldron_gui reads "workshop". Not open: Esc only if Stella's
;     dialog is up (OCR of the stella_dialog rect, her name, reads "stel";
;     not calibrated = never Esc), short S tap back, retry, up to 3 tries.
;     Then click search, Input.ClearText (the box keeps the last visit's
;     text), type craftTarget's search name, read the first result
;     card: its title must BE that name ("Fortune Potion I" never accepts
;     "Fortune Potion II"), else nothing more is clicked. A Godly Potion
;     (Zeus / Poseidon / Hades) shares its title with the other two: up to
;     ResultCards cards are read (card N = cauldron_result moved N-1 times by
;     the cauldron_result_2 offset; without that step only the first) and the
;     one whose description shows its Lord (GameLists.DescHint) is used.
;     Click it, Open Recipe, Add
;     All, close (click out of the cauldron), then
;     ResetToSpawn: the next task starts from spawn (fishing walks back by
;     itself when it sees no fishing panel). There is no return route.
;   One `craft` webhook lists what was done.
;   NO BLIND CLICKS (live 2026-11-02: a click on an empty spot went through
;   a panel into the world and opened Roblox's "Buy Robux" prompt): the
;   dialog clicks and the skip click only while his dialog reads
;   (_DialogUp, waited for up to DialogWaitMs), the Buy tab and every tile
;   only while the shop's title reads, each cauldron click after the search
;   only while "Workshop" reads; none while a Roblox purchase prompt is up
;   (TaskEnv.Unsafe), and that prompt is looked for (closed with Esc) after
;   each. Refused -> the step stops, logged.
;
; "(shop UI seen)" means the fisher_confirm pixel matched its calibrated color
; before ANY click/typing of that purchase and again right before the confirm
; click. It is not an inventory read and does not prove a purchase: the webhook
; says "clicked Buy xN ... (shop UI seen)" and never claims the potions arrived.
; The cauldron line likewise reports clicks only.
;
; ESC SAFETY: Esc opens the Roblox menu when nothing is open, so the cauldron
; retry presses Esc only when Stella's dialog is recognised by its name text.
; If it is not recognised (or not calibrated) it just steps back and retries.
; The return route is played without a menu check (documented, not detected).
;
; ASSUMPTIONS (manual check pending): the quantity box accepts typed digits
; after End + Backspaces; fisher_item_<potion> selects the potion entry; FishSol's
; "betweenItemAndQty" click (coords.json craft.unmapped) is the Buy button
; (fisher_buy_button); its "afterConfirm" click is not needed.
; ---------------------------------------------------------------------------

class CraftTask {
    static MaxQty := 999      ; 3 digits; Input.ClearText (End + Backspaces) empties the box first
    static PixelTol := 30
    static BuyAttempts := 2
    static NotOpened := -2    ; _ShopPhase: his Open Shop button never read, nothing bought
    static TypeSettleMs := 150
    static OpenKey := "f"
    static TalkKey := "e"          ; talks to Captain Flarg (BuyHere, after the sell)
    static GuiTries := 3
    static GuiOpenMs := 900
    static EscMs := 500
    static ChangeTol := 12      ; pre-F vs post-F pixel: beyond this = something opened
    static StepBackMs := 250
    static SettleMs := 500
    static NotifyPollMs := 1000    ; notify_rect OCR at most once a second
    ; "Auto crafted ...", "Potion Crafted". The game font draws "a" like "o"
    ; ("Auto crofted": 2026-10-27 review), as in MemoryMatch's st[ao]rt.
    static NotifyRe := "i)cr[ao]ft"
    static ShopWaitMs := 4000      ; Open Shop button must be read within this (one extra skip click halfway)
    static DialogWaitMs := 2500    ; his dialog must read within this before the dialog clicks (as SellTask.FisherCheck)
    static ShopPollMs := 250
    static ShopBox := {dx: -150, dy: -35, w: 300, h: 70}   ; OCR box around fisher_open_shop
    ; his "Open Shop" button reads in that box (not "Sell Fish"): live misreads
    ; 'Open Slpep' (2026-11-10: nothing bought, a whole extra trip to buy)
    ; S read as $ (live 1920x1080, 2026-11-11: 'open$hop')
    static OpenShopRe := "i)[s$]h[o0]p|\bopen\s*[s$][a-z]"
    static OpenShopUp(t) => RegExMatch(t, CraftTask.OpenShopRe) && !RegExMatch(t, "i)sell")
    static ScrollTopNotches := 10  ; wheel up over the grid: back to its top row
    static ScrollTries := 8        ; then one notch down at a time to find a potion
    static ScrollMs := 250
    static NameScales := [1, 2]    ; the item name is OCR'd at 1x, then 2x if that did not match
    static CloseTries := 3         ; clicks on a close button before reporting
    static DialogRe := "i)shop|sell|leave"     ; Captain Flarg's buttons
    ; The Fishing Shop window (fixed layout at 2560x1440, read 2026-10-26 on
    ; two screenshots): its title, and the Buy tab
    ; the sell's own title box: y 312 read nothing on real frames (tests\screens)
    static ShopTitle := {x: 570, y: 325, w: 380, h: 70, re: "i)fishing\s*sh[ao]p"}
    static BuyTab := {x: 1241, y: 397}
    ; "Confirm Purchase" title, relative to fisher_confirm (2560x1440, read
    ; 2026-10-26: title 1098..1443 x 493..527 for a button point 1499,821)
    static PurchaseTitle := {dx: -470, dy: -345, w: 520, h: 70, re: "i)c[ao]nfirm|purch"}
    ; Captain Flarg's dialog body (the box SellTask.FisherCheck reads): any word = his dialog is up
    static DialogBody := {x: 960, y: 915, w: 940, h: 265, scale: 2
        , words: ["skip", "click", "flarg", "florg", "captain", "want", "avvv", "arrr"]}
    static DefaultMinIntervalMin := 10
    static CauldronIds := ["cauldron_search", "cauldron_open_recipe", "cauldron_add_all", "cauldron_close"]   ; points
    static CauldronRects := ["cauldron_gui", "cauldron_result"]
    static ResultCards := 3        ; Godly Potion: three cards share the title
    static GuiRe := "i)workshop"
    static StellaRe := "i)\bstel"
    static CraftInts := ["dialog.aClicks", "dialog.aGapMs", "dialog.aAfterMs", "dialog.bPreMs"
        , "dialog.bAfterMs", "stepMs", "closePreMs", "closeMoveMs", "closePostMs"]
    static CameraInts := ["wheelUp", "wheelDown", "wheelGapMs", "pauseMs", "afterMs"]

    name := "craft"
    priority := 4

    __New(deps := "") {
        this._env := TaskEnv(deps)
        rb := TaskEnv.Dep(deps, "roblox", "")
        this._roblox := IsObject(rb) ? rb : Roblox
        sm := TaskEnv.Dep(deps, "sample", "")      ; (x, y) -> 0xRRGGBB
        this._sample := IsObject(sm) ? sm : (x, y) => Pixel.Get(x, y)
        this._ranOnce := false       ; a Run has started since launch
        this._notified := false      ; crafted notification seen, Run not yet done
        this._notifyReadAt := ""     ; env.Now() of the last notify_rect read
        this._retry := false         ; last Run was cut short
        this._lastRunAt := ""        ; env.Now() when the last Run started
        this._skipBuy := false       ; BuyHere bought during the sell visit
        this._aborts := 0            ; runs in a row that ended early with no stop asked
        this._abortAt := 0           ; env.Now() when the last of them ended
    }

    ; A run that ends early on its own (no stop / pause / preempt: a failed
    ; respawn on the title screen, live 2026-11-09) is tried again only
    ; after this gap, doubled per such run in a row: it relaunched every
    ; ~14 s for 7+ minutes, logging only "craft: starting".
    static RetryGapMs := 60000
    static RetryGapMaxMs := 600000
    _RetryGapMs() => Min(CraftTask.RetryGapMs * 2 ** (this._aborts - 1), CraftTask.RetryGapMaxMs)

    ; Craft.minIntervalMin (1..1440, else 10) in ms.
    _MinIntervalMs() {
        env := this._env
        m := CraftTask.DefaultMinIntervalMin
        if IsObject(env.cfg)
            try m := env.cfg.Get("Craft.minIntervalMin", CraftTask.DefaultMinIntervalMin)
        if !(IsInteger(m) && m >= 1 && m <= 1440)
            m := CraftTask.DefaultMinIntervalMin
        return Integer(m) * 60000
    }

    CanRun(state) {
        env := this._env
        if (IsObject(env.cfg) && !env.cfg.Get("Craft.enabled", 1))
            return false
        if (this._aborts > 0 && env.Now() - this._abortAt < this._RetryGapMs())
            return false
        if (!this._ranOnce || this._notified || this._retry)
            return true
        ; minimum interval between notification-triggered runs
        if (this._lastRunAt !== "" && env.Now() - this._lastRunAt < this._MinIntervalMs())
            return false
        r := env.cal.Rect("notify_rect")
        if !IsObject(r)
            return false
        ; CanRun runs on the App's tick while a route plays: a slow OCR here
        ; freezes the walk with a key held (2026-10-27 review). Read later.
        if Input.InRoute
            return false
        now := env.Now()
        if (this._notifyReadAt !== "" && now - this._notifyReadAt < CraftTask.NotifyPollMs)
            return false
        this._notifyReadAt := now
        if !RegExMatch((env.ocrFn)(r.x, r.y, r.w, r.h), CraftTask.NotifyRe)
            return false
        this._notified := true
        return true
    }

    ; Sell hook: is a Fisher buy due (the first one since Start, a "crafted"
    ; notification, a cut-short run)? Sell then buys in the same visit.
    BuyDue() {
        env := this._env
        if (IsObject(env.cfg) && !env.cfg.Get("Craft.enabled", 1))
            return false
        return !this._ranOnce || this._notified || this._retry
    }

    ; Buys while already standing at Captain Flarg (Sell just closed its
    ; shop): E opens his dialog again, then the same shop steps as a craft
    ; trip, without the respawn and the walk. The craft task then has no
    ; buying left to do (a cauldron step still runs on its own).
    ; -> purchases with the shop UI seen, or -1 when stopped.
    BuyHere(ctx) {
        env := this._env
        plan := this._Plan()
        if !plan.buy
            return 0
        env.Log("craft: buying while at the Fisher (same visit as the sell)")
        lines := []
        if this._ShopIsOpen() {
            env.Log("craft: the Fishing Shop is still open after the sell: no E")
        } else if this._ShopButtonUp(plan) {
            env.Log("craft: Captain Flarg's Open Shop button is still up: no E")
        } else {
            Input.Key(CraftTask.TalkKey, 80, env.io)
            if !env.Wait(CraftTask.SettleMs, ctx)
                return -1
        }
        r := this._ShopPhase(ctx, plan, lines)
        if (r = -1) {
            this._retry := true
            return -1
        }
        if (r = CraftTask.NotOpened) {
            ; nothing was bought: the buy stays due (the craft trip tries
            ; again) instead of waiting for the next crafted notification
            ; (2026-10-27 review). 0, not < 0: Sell still walks back.
            this._retry := true
            return 0
        }
        this._lastRunAt := env.Now()
        this._notified := false
        this._retry := false
        if plan.cauldron
            this._skipBuy := true                ; Run does the cauldron only
        else
            this._ranOnce := true
        desc := ""
        for line in lines
            desc .= (desc = "" ? "" : "`n") "- " line
        env.Report("craft", "Auto craft", desc)
        return r
    }

    Run(ctx) {
        this._lastRunAt := this._env.Now()
        this._ranOnce := true
        this._notified := false
        this._retry := false
        done := false
        try {
            return this._Visit(ctx, &done)
        } finally {
            if !done {
                this._retry := true      ; stopped / unfocused: try again later
                if ctx.ShouldStop() {
                    this._aborts := 0    ; cut short: again once the stop is over
                } else {
                    this._aborts += 1
                    this._abortAt := this._env.Now()
                    this._env.Log("craft: the run ended early (nothing asked it to stop): next try in " this._RetryGapMs() // 1000 " s")
                }
            } else
                this._aborts := 0
        }
    }

    ; -> buys confirmed with the shop UI seen. Sets done := true when the visit ended normally.
    _Visit(ctx, &done) {
        env := this._env
        if ctx.ShouldStop()
            return 0
        plan := this._Plan()
        if this._skipBuy {                       ; bought during the sell visit
            this._skipBuy := false
            plan.buy := false
        }
        if (!plan.buy && !plan.cauldron) {
            done := true
            return 0
        }
        d := {io: env.io, roblox: this._roblox, log: (m) => env.Log(m)}
        if !FishLogic.FocusOrWait(d, ctx, "craft")
            return 0
        env.Log("craft: starting")
        io := env.io
        if !Input.ResetToSpawn(ctx, io)
            return 0
        lines := []
        shopSeen := 0
        if plan.buy {
            r := this._BuyPhase(ctx, plan, lines)
            if (r = -1)
                return 0
            shopSeen := Max(r, 0)                ; NotOpened: reported, nothing bought
            if plan.cauldron {
                if !Input.ResetToSpawn(ctx, io)
                    return 0
            } else if !Input.PlayRoute(plan.back, ctx, io) {
                return 0
            }
        }
        if plan.cauldron {
            if !this._CauldronPhase(ctx, plan, lines)
                return 0
        }
        desc := ""
        for line in lines
            desc .= (desc = "" ? "" : "`n") "- " line
        env.Report("craft", "Auto craft", desc)
        env.Log("craft: done")
        done := true
        return shopSeen
    }

    ; ---- preflight --------------------------------------------------------

    _Plan() {
        env := this._env
        plan := {buy: false, items: [], qtyPt: "", confPt: "", toShop: "", back: "", coords: ""
            , cauldron: false, cpts: Map(), cRoute: "", cReturn: "", target: ""}
        if !IsObject(env.cfg) {
            env.Problem("craft:cfg", "craft: no config bound: skipped")
            return plan
        }
        this._PlanBuy(plan)
        this._PlanCauldron(plan)
        return plan
    }

    _PlanBuy(plan) {
        env := this._env
        items := []
        for name in this._Potions() {
            pt := env.Point(Calibrate.PotionId(name))
            if IsObject(pt)
                items.Push({name: name, pt: pt, qty: this._Qty(name)})
        }
        qtyPt := env.Point("fisher_qty")
        confPt := env.Point("fisher_confirm")
        shopPt := env.Point("fisher_open_shop")
        buyPt := env.Point("fisher_buy_button")
        pcPt := env.Point("fisher_purchase_close")
        if (items.Length = 0 || !IsObject(qtyPt) || !IsObject(confPt) || !IsObject(shopPt) || !IsObject(buyPt) || !IsObject(pcPt))
            return
        nameR := env.cal.Rect("fisher_picked_name")
        if !IsObject(nameR) {
            env.Problem("cal:fisher_picked_name", "craft: buying skipped until the calibration step 'fisher_picked_name' is recorded"
                . " (the picked item's name in the Fisher shop: it is read so the wrong item is never bought)")
            return
        }
        coords := env.cfg.Data("coords")
        bad := []
        for p in CraftTask.CraftInts
            if !CraftTask._IsInt(FishLogic._Dig(coords, "craft." p))
                bad.Push("coords.craft." p)
        for p in ["craft.dialog.a", "craft.close"]
            if !FishLogic._IsNums(FishLogic._Dig(coords, p), 2)
                bad.Push("coords." p)
        for p in CraftTask.CameraInts
            if !CraftTask._IsInt(FishLogic._Dig(coords, "sell.camera." p))
                bad.Push("coords.sell.camera." p)
        variant := env.cfg.Get("General.vip", 1) ? "vip" : "nonvip"
        routes := env.cfg.Data("routes")
        toShop := CraftTask._Steps(FishLogic._Dig(routes, variant ".toShop"))
        back := CraftTask._Steps(FishLogic._Dig(routes, variant ".back"))
        if !IsObject(toShop)
            bad.Push("routes." variant ".toShop")
        if !IsObject(back)
            bad.Push("routes." variant ".back")
        if (bad.Length) {
            names := ""
            for p in bad
                names .= (names = "" ? "" : ", ") p
            env.Problem("craft:data", "craft: fisher visit skipped, data incomplete: " names)
            return
        }
        plan.buy := true
        plan.items := items
        plan.qtyPt := qtyPt
        plan.confPt := confPt
        plan.shopPt := shopPt
        plan.buyPt := buyPt
        plan.pcPt := pcPt
        plan.nameR := nameR
        plan.leavePt := env.cal.Point("fisher_leave")     ; optional
        plan.coords := coords
        plan.toShop := toShop
        plan.back := back
    }

    _PlanCauldron(plan) {
        env := this._env
        if !env.cfg.Get("Craft.cauldron", 0)
            return
        ok := true
        target := Trim(String(env.cfg.Get("Craft.craftTarget", "")))
        if (target = "") {
            env.Problem("craft:target", "craft: cauldron step skipped, [Craft] craftTarget is empty")
            ok := false
        }
        for id in CraftTask.CauldronIds {
            pt := env.Point(id)
            if IsObject(pt)
                plan.cpts[id] := pt
            else
                ok := false
        }
        for id in CraftTask.CauldronRects {
            r := env.Rect(id)
            if IsObject(r)
                plan.cpts[id] := r
            else
                ok := false
        }
        route := this._NonEmptyRoute("cauldron")
        if !IsObject(route)
            ok := false
        if !ok
            return
        plan.cauldron := true
        plan.target := target
        plan.search := GameLists.SearchName(target)
        plan.hint := GameLists.DescHint(target)
        r2 := env.cal.Rect("cauldron_result_2")      ; optional: only the Godly Potions use it
        plan.cpts["cauldron_result_2"] := IsObject(r2) ? r2 : ""
        plan.cRoute := route
    }

    ; Parsed steps of a route that exists and has steps, else "" (logged).
    _NonEmptyRoute(name) {
        env := this._env
        raw := env.Route(name)
        if !IsObject(raw)
            return ""
        steps := Input.ParseRoute(raw)
        if (steps.Length = 0) {
            env.Problem("route:" name ":empty", "route '" name "' is empty (record it in game): cauldron step skipped")
            return ""
        }
        return steps
    }

    ; -> parsed route Array with >= 1 step, or "".
    static _Steps(raw) {
        try {
            steps := Input.ParseRoute(raw)
            return steps.Length > 0 ? steps : ""
        }
        return ""
    }

    static _IsInt(v) => (v is Integer) || (v is String && IsInteger(v))

    _Potions() {
        env := this._env
        if HasMethod(env.cal, "Potions") {
            try return env.cal.Potions()
        }
        out := []
        for part in StrSplit(env.cfg.Get("Craft.potions", Calibrate.DefaultPotions), ",") {
            n := Trim(part)
            if (n != "")
                out.Push(n)
        }
        return out
    }

    _Qty(name) {
        cfg := this._env.cfg
        id := SubStr(Calibrate.PotionId(name), StrLen(Calibrate.PotionPrefix) + 1)
        q := cfg.Get("Craft.qty_" id, cfg.Get("Craft.qty", 1))
        return IsInteger(q) ? Max(1, Min(Integer(q), CraftTask.MaxQty)) : 1
    }

    ; ---- fisher -----------------------------------------------------------

    ; -> buys confirmed with the shop UI seen, or -1 when stopped.
    _BuyPhase(ctx, plan, lines) {
        env := this._env
        io := env.io
        if !FishLogic.Zoom(io, ctx, plan.coords["sell"]["camera"])
            return -1
        if !Input.PlayRoute(plan.toShop, ctx, io)
            return -1
        return this._ShopPhase(ctx, plan, lines)
    }

    ; At Captain Flarg with his dialog open (the toShop route's E, or E
    ; pressed by BuyHere): dialog clicks, Open Shop, every potion, close.
    ; -> purchases with the shop UI seen, NotOpened (his Open Shop button
    ; never read: nothing bought), or -1 when stopped.
    _ShopPhase(ctx, plan, lines) {
        r := this._ShopSteps(ctx, plan, lines)
        if (r = -1)
            this._CloseOnPreempt(ctx, plan)
        return r
    }

    ; Told to stop at Captain Flarg. On a preempt (not F3 / pause / Roblox
    ; gone) the purchase window, the shop and his dialog are closed first:
    ; the next task would start with them on screen (2026-10-27 review).
    ; A halt sends nothing.
    _CloseOnPreempt(ctx, plan) {
        if (!ctx.ShouldStop() || CleanupCtx.Halted(ctx))
            return
        env := this._env
        cc := CleanupCtx(ctx)
        env.Log("craft: preempted at Captain Flarg: closing what is open first")
        if this._ShopOpen(plan)
            this._CloseShop(cc, plan, plan.coords["craft"])
        else
            this._LeaveDialog(cc, plan)
    }

    _ShopSteps(ctx, plan, lines) {
        env := this._env
        io := env.io
        c := plan.coords["craft"]
        dlg := c["dialog"]
        a := dlg["a"]
        if this._ShopIsOpen()
            return this._InShop(ctx, plan, lines, c)
        seen := this._ShopButtonUp(plan) ? 1 : 0
        if !seen {
            ; the dialog clicks only while his dialog reads (as the sell's
            ; FisherCheck): a click on an empty spot can go through into
            ; the world (live 2026-11-02)
            up := (env.Unsafe("craft") = "") ? this._WaitDialog(ctx, plan) : 0
            if (up < 0)
                return -1
            if !up
                return this._NotOpened(ctx, plan, lines, "Captain Flarg's dialog not seen after E; nothing clicked or bought")
            io.MoveTo(a[1], a[2])
            if !io.Wait(dlg["aGapMs"], ctx)
                return -1
            Loop dlg["aClicks"] {
                io.ClickHere()
                if !io.Wait(A_Index < dlg["aClicks"] ? dlg["aGapMs"] : dlg["aAfterMs"], ctx)
                    return -1
            }
            if !io.Wait(dlg["bPreMs"], ctx)
                return -1
            if env.BuyPrompt("craft")
                return this._NotOpened(ctx, plan, lines, "a Roblox purchase prompt came up after the dialog clicks (closed with Esc); nothing bought")
            seen := this._WaitOpenShop(ctx, plan, a)
        }
        if (seen < 0)
            return -1
        if !seen
            return this._NotOpened(ctx, plan, lines, "Captain Flarg's Open Shop button not seen (read: '" this._shopText "'); nothing bought")
        if !FishLogic.ClickAt(io, ctx, [plan.shopPt.x, plan.shopPt.y], 0, dlg["bAfterMs"])
            return -1
        return this._InShop(ctx, plan, lines, c)
    }

    ; Nothing bought at Captain Flarg: his dialog is left (checked), the
    ; reason logged and reported. -> NotOpened, or -1 when stopped.
    _NotOpened(ctx, plan, lines, msg) {
        env := this._env
        gone := this._LeaveDialog(ctx, plan)
        if (gone < 0)
            return -1
        if !gone
            msg .= "; his dialog is still open" (IsObject(plan.leavePt) ? "" : " (record fisher_leave so it can be closed)")
        env.Log("craft: " msg)
        env.Report("errors", "Craft: shop not opened", msg, 0xE74C3C)
        lines.Push(msg)
        return CraftTask.NotOpened
    }

    ; The Fishing Shop is open: the Buy tab, every potion, close everything.
    ; -> purchases with the shop UI seen, NotOpened (the shop never showed
    ; after Open Shop: nothing clicked in it), or -1 when stopped.
    _InShop(ctx, plan, lines, c) {
        env := this._env
        io := env.io
        ; the Buy tab only once the shop's title reads (no blind clicks)
        up := (env.Unsafe("craft") = "") ? this._WaitShop(ctx) : 0
        if (up < 0)
            return -1
        if !up
            return this._NotOpened(ctx, plan, lines, "the Fishing Shop did not open after Open Shop (its title did not read); nothing bought")
        env.Click(CraftTask.BuyTab)                ; the shop may still be on Sell
        if !env.Wait(CraftTask.SettleMs, ctx)
            return -1
        shopSeen := 0
        items := plan.items
        if env.BuyPrompt("craft") {
            msg := "a Roblox purchase prompt came up after the Buy tab (closed with Esc); nothing bought"
            env.Log("craft: " msg)
            lines.Push(msg)
            items := []
        }
        for item in items {
            r := this._BuyOne(ctx, plan, item)
            if !IsObject(r)
                return -1
            lines.Push(r.line)
            shopSeen += r.ok ? 1 : 0
        }
        if !io.Wait(c["closePreMs"], ctx)
            return -1
        left := this._CloseShop(ctx, plan, c)
        if (left == -1)
            return -1
        if (left != "") {
            msg := "still open after closing: " left " (the next task may not work)"
            env.Log("craft: " msg)
            env.Report("errors", "Fisher shop not closed", msg, 0xE74C3C)
            lines.Push(msg)
        }
        return shopSeen
    }

    ; Closes the purchase window, the shop and Captain Flarg's dialog, checking
    ; each. -> "" all closed, a list of what stayed open, or -1 when stopped.
    _CloseShop(ctx, plan, c) {
        env := this._env
        io := env.io
        left := []
        r := this._ClosePurchase(ctx, plan)
        if (r < 0)
            return -1
        if !r
            left.Push("the purchase window")
        sc := env.cal.Point("fisher_shop_close")     ; optional: else the FishSol spot
        shut := false
        Loop CraftTask.CloseTries {
            if !FishLogic.ClickAt(io, ctx, IsObject(sc) ? [sc.x, sc.y] : c["close"], c["closeMoveMs"], c["closePostMs"])
                return -1
            if !this._ShopOpen(plan) {
                shut := true
                break
            }
            env.Log("craft: the shop is still open after its X (try " A_Index "/" CraftTask.CloseTries ")")
        }
        if !shut
            left.Push("the shop")
        gone := this._LeaveDialog(ctx, plan)
        if (gone < 0)
            return -1
        if !gone
            left.Push(IsObject(plan.leavePt) ? "Captain Flarg's dialog" : "Captain Flarg's dialog (record fisher_leave so it can be closed)")
        out := ""
        for s in left
            out .= (out = "" ? "" : ", ") s
        return out
    }

    ; Captain Flarg's dialog gone? While his buttons (or his dialog text) are
    ; still up, click Leave (fisher_leave). -> 1 gone, 0 still up, -1 stopped.
    _LeaveDialog(ctx, plan) {
        env := this._env
        Loop CraftTask.CloseTries {
            if !this._DialogUp(plan)
                return 1
            if !IsObject(plan.leavePt)
                return 0
            env.Log("craft: Captain Flarg's dialog is still up: Leave")
            env.Click(plan.leavePt)
            if !env.Wait(CraftTask.SettleMs, ctx)
                return -1
        }
        return this._DialogUp(plan) ? 0 : 1
    }

    ; His buttons read in the box around fisher_open_shop, or his dialog text.
    _DialogUp(plan) {
        env := this._env
        b := CraftTask.ShopBox, pt := plan.shopPt
        if RegExMatch((env.ocrFn)(pt.x + b.dx, pt.y + b.dy, b.w, b.h), CraftTask.DialogRe)
            return true
        d := CraftTask.DialogBody
        t := StrLower((env.ocrFn)(d.x, d.y, d.w, d.h, d.scale))
        for w in d.words
            if InStr(t, w)
                return true
        return false
    }

    ; Polls _DialogUp up to DialogWaitMs (after E his dialog can take a
    ; moment). -> 1 up | 0 not in time | -1 stopped
    _WaitDialog(ctx, plan) {
        env := this._env
        waited := 0
        Loop {
            if this._DialogUp(plan)
                return 1
            if (waited >= CraftTask.DialogWaitMs)
                return 0
            if !env.Wait(CraftTask.ShopPollMs, ctx)
                return -1
            waited += CraftTask.ShopPollMs
        }
    }

    ; Polls _ShopIsOpen up to ShopWaitMs. -> 1 open | 0 not in time | -1 stopped
    _WaitShop(ctx) {
        env := this._env
        waited := 0
        Loop {
            if this._ShopIsOpen()
                return 1
            if (waited >= CraftTask.ShopWaitMs)
                return 0
            if !env.Wait(CraftTask.ShopPollMs, ctx)
                return -1
            waited += CraftTask.ShopPollMs
        }
    }

    ; One read: the Fishing Shop window is open (its title).
    _ShopIsOpen() {
        t := CraftTask.ShopTitle
        return RegExMatch((this._env.ocrFn)(t.x, t.y, t.w, t.h), t.re) > 0
    }

    ; One read: the Open Shop button is showing right now.
    _ShopButtonUp(plan) {
        b := CraftTask.ShopBox, pt := plan.shopPt
        t := (this._env.ocrFn)(pt.x + b.dx, pt.y + b.dy, b.w, b.h)
        return CraftTask.OpenShopUp(t)
    }

    ; Purchase window (fisher_confirm pixel) closed? Clicks fisher_purchase_close
    ; while it is still up. -> 1 closed, 0 still open, -1 stopped.
    ; The purchase window is a centred popup like the Sell Confirm one (even
    ; scale at 16:10 where the shop stretches): its checks and clicks map in
    ; Screen mode "C" (the same pixels at 16:9).
    _ClosePurchase(ctx, plan) => Screen.WithMode("C", () => this._ClosePurchaseM(ctx, plan))
    _ClosePurchaseM(ctx, plan) {
        env := this._env
        conf := plan.confPt
        gap := plan.coords["craft"]["stepMs"]
        Loop CraftTask.CloseTries {
            if !this._PurchaseUp(plan)
                return 1
            env.Click(plan.pcPt)
            if !env.Wait(gap, ctx)
                return -1
        }
        return this._PurchaseUp(plan) ? 0 : 1
    }

    ; The purchase window is up: fisher_confirm pixel, or its title.
    _PurchaseUp(plan) => Screen.WithMode("C", () => this._PurchaseUpM(plan))
    _PurchaseUpM(plan) {
        env := this._env
        conf := plan.confPt
        if (env.pixelFn)(conf.x, conf.y, conf.color, CraftTask.PixelTol)
            return true
        t := CraftTask.PurchaseTitle
        return RegExMatch((env.ocrFn)(conf.x + t.dx, conf.y + t.dy, t.w, t.h), t.re) > 0
    }

    ; The shop is open: the purchase window is still over it, or the name
    ; box shows a shop item, or the start of one (the purchase window or an
    ; overlay can cover the end of the name: "Lucky Po").
    _ShopOpen(plan) {
        if (this._PurchaseUp(plan) || this._ShopIsOpen())
            return true
        r := plan.nameR
        for sc in CraftTask.NameScales {
            t := (this._env.ocrFn)(r.x, r.y, r.w, r.h, sc)
            f := GameLists.Fold(t)
            if (StrLen(f) < 4)
                continue
            for n in GameLists.Shop {
                if (CraftTask.IsItem(t, n) || InStr(GameLists.Fold(n), f) = 1)
                    return true
            }
        }
        return false
    }

    ; Is the OCR text of the name box the potion `name`? The whole text or
    ; its first line, letters only, game font look-alikes folded. OCR of the
    ; game font still slips a letter or two ("Lucl«y", "Hour Gloss", "Warp
    ; Poti"), so a read that is a few letters off is accepted, but ONLY when
    ; `name` is the one shop item closest to it (any tie, or another item at
    ; least as close, means no): the wrong potion is never accepted.
    static IsItem(text, name) {
        want := GameLists.Fold(name)
        if (want = "")
            return false
        reads := [GameLists.Fold(text)]
        for line in StrSplit(String(text), "`n", "`r") {
            if (Trim(line) != "") {
                reads.Push(GameLists.Fold(line))
                break
            }
        }
        for f in reads {
            if (f = "")
                continue
            if (f = want)
                return true
            d := GameLists.Distance(f, want)
            if (d > CraftTask.NameSlack(want))
                continue
            closest := true
            for n in GameLists.Shop {
                o := GameLists.Fold(n)
                if (o != want && GameLists.Distance(f, o) <= d) {
                    closest := false
                    break
                }
            }
            if closest
                return true
        }
        return false
    }

    ; Letters an OCR read may be off by: 1, 2 from 8 letters, 3 from 14.
    static NameSlack(folded) => StrLen(folded) >= 14 ? 3 : StrLen(folded) >= 8 ? 2 : 1

    ; Scrolls the grid to the top, clicks the potion's tile and reads the
    ; picked name; not it -> one notch down, click, read again (ScrollTries).
    ; -> {found, read} (read = the first name read), {found, read, why} when
    ; a tile click was refused or brought up a purchase prompt, or "" when
    ; stopped.
    _PickItem(ctx, plan, item) {
        env := this._env
        io := env.io
        gap := plan.coords["craft"]["stepMs"]
        r := plan.nameR
        read := ""
        Loop CraftTask.ScrollTries + 2 {
            if ctx.ShouldStop()
                return ""
            io.MoveTo(item.pt.x, item.pt.y)
            if (A_Index = 1)
                Input.Wheel("up", CraftTask.ScrollTopNotches, io)
            else if (A_Index > 2)                  ; try 2: the same tile again (a click can be lost)
                Input.Wheel("down", 1, io)
            if !env.Wait(CraftTask.ScrollMs, ctx)
                return ""
            ; the tile only while the shop's title reads (no blind clicks)
            if ((why := env.Unsafe("craft")) != "")
                return {found: false, read: read, why: why}
            if !this._ShopIsOpen()
                return {found: false, read: read, why: "the Fishing Shop is not open (its title did not read): tile not clicked"}
            env.Click(item.pt)
            if !env.Wait(gap, ctx)
                return ""
            if env.BuyPrompt("craft")
                return {found: false, read: read, why: "a Roblox purchase prompt came up after the tile click (closed with Esc)"}
            for sc in CraftTask.NameScales {
                t := (env.ocrFn)(r.x, r.y, r.w, r.h, sc)
                if (A_Index = 1 && read = "")
                    read := t
                if CraftTask.IsItem(t, item.name)
                    return {found: true, read: t}
            }
        }
        return {found: false, read: read}
    }

    ; -> 1 the button at fisher_open_shop reads "shop" (not "sell"), 0 not
    ; within ShopWaitMs (this._shopText = last read), -1 stopped.
    _WaitOpenShop(ctx, plan, skipPt := "") {
        env := this._env
        b := CraftTask.ShopBox, pt := plan.shopPt
        this._shopText := ""
        waited := 0
        skipped := false
        Loop {
            if (IsObject(skipPt) && !skipped && waited >= CraftTask.ShopWaitMs // 2) {
                skipped := true                  ; his text may still be typing: one more skip click
                if (env.Unsafe("craft") = "" && this._DialogUp(plan)) {     ; only on his dialog
                    env.io.MoveTo(skipPt[1], skipPt[2])
                    env.io.ClickHere()
                    env.BuyPrompt("craft")
                } else
                    env.Log("craft: Captain Flarg's dialog is not up: no skip click")
            }
            t := Trim(RegExReplace((env.ocrFn)(pt.x + b.dx, pt.y + b.dy, b.w, b.h), "\s+", " "))
            if (t != "")
                this._shopText := SubStr(t, 1, 60)
            if CraftTask.OpenShopUp(t)
                return 1
            if (waited >= CraftTask.ShopWaitMs)
                return 0
            if !env.Wait(CraftTask.ShopPollMs, ctx)
                return -1
            waited += CraftTask.ShopPollMs
        }
    }

    ; Each attempt first checks that the shop UI is up (fisher_confirm pixel
    ; still has its calibrated color). Until it is seen NOTHING is clicked or
    ; typed: digits typed into the world equip hotbar slots. The same pixel is
    ; checked again right before the confirm click.
    ; -> {ok, line} or "" when stopped.
    _BuyOne(ctx, plan, item) {
        env := this._env
        io := env.io
        gap := plan.coords["craft"]["stepMs"]
        conf := plan.confPt
        ; pick the potion and READ its name: Buy is never pressed on anything else
        pick := this._PickItem(ctx, plan, item)
        if !IsObject(pick)
            return ""
        if pick.HasOwnProp("why") {
            msg := item.name ": " pick.why "; nothing bought"
            env.Log("craft: " msg)
            env.Report("errors", "Craft: shop not open", msg, 0xE74C3C)
            return {ok: false, line: msg}
        }
        if !pick.found {
            msg := item.name ": not found in the shop (picked: '" SubStr(Trim(RegExReplace(pick.read, "\s+", " ")), 1, 40) "'); nothing bought"
            env.Log("craft: " msg)
            env.Report("errors", "Craft: wrong item in the shop", msg, 0xE74C3C)
            return {ok: false, line: msg}
        }
        Loop CraftTask.BuyAttempts {
            if ctx.ShouldStop()
                return ""
            ; the Buy button (the same for all)
            env.Click(plan.buyPt)
            if !env.Wait(gap, ctx)
                return ""
            ; the purchase popup must be up before anything is typed
            if !this._PurchaseUp(plan) {
                env.Log("craft: purchase window not seen for " item.name " (attempt " A_Index "/" CraftTask.BuyAttempts "): nothing typed")
                if !env.Wait(CraftTask.SettleMs, ctx)
                    return ""
                continue
            }
            Screen.WithMode("C", () => env.Click(plan.qtyPt))
            if !env.Wait(gap, ctx)
                return ""
            ; End first: the box keeps its old number and the click can put
            ; the caret before it, where Backspaces delete nothing ("1" + "3"
            ; = 31 bought; 2026-10-27 review)
            Input.ClearText(io)
            Input.TypeText(item.qty, io)
            if !env.Wait(CraftTask.TypeSettleMs, ctx)
                return ""
            if this._PurchaseUp(plan) {
                Screen.WithMode("C", () => env.Click(conf))
                if !env.Wait(gap, ctx)
                    return ""
                if (this._ClosePurchase(ctx, plan) < 0)      ; it stays open after a purchase
                    return ""
                return {ok: true, line: "clicked Buy x" item.qty " for " item.name " (shop UI seen)"}
            }
            env.Log("craft: confirm button not seen for " item.name " (attempt " A_Index "/" CraftTask.BuyAttempts ")")
            if (this._ClosePurchase(ctx, plan) < 0)
                return ""
        }
        if (this._ClosePurchase(ctx, plan) < 0)
            return ""
        msg := item.name ": shop UI (confirm button) not seen after " CraftTask.BuyAttempts " tries; nothing confirmed"
        env.Log("craft: " msg)
        env.Report("errors", "Craft purchase not confirmed", msg, 0xE74C3C)
        return {ok: false, line: msg}
    }

    ; ---- Stella ------------------------------------------------------------

    ; -> false when stopped.
    ; Is the first line of a result card the recipe `target`? Case, spaces and
    ; punctuation do not matter, nor the game font's look-alikes ("o" read for
    ; "a", "I<" for "k", l/1/| for "i": "Worp Potion" is "Warp Potion"); a
    ; longer name does ("Fortune Potion I" is not "Fortune Potion II").
    static IsRecipe(text, target) {
        norm := (s) => Trim(RegExReplace(StrReplace(RegExReplace(RegExReplace(StrLower(String(s))
            , "[il1|]<", "k"), "[l1|!]", "i"), "o", "a"), "[^a-z0-9]+", " "))
        t := norm(target)
        if (t = "")
            return false
        for line in StrSplit(String(text), "`n", "`r") {
            n := norm(line)
            if (n = "")
                continue
            return n = t                    ; the title is the first non-empty line
        }
        return false
    }

    ; The result card to click, or "" (read = the first card's text). Plain
    ; recipes: the first card only. A Godly Potion: the first of up to
    ; ResultCards cards whose title matches and whose description shows its
    ; Lord; cards past the first need the cauldron_result_2 offset.
    _FindCard(plan, &read) {
        env := this._env
        res := plan.cpts["cauldron_result"]
        r2 := plan.cpts.Has("cauldron_result_2") ? plan.cpts["cauldron_result_2"] : ""
        n := (plan.hint != "" && IsObject(r2)) ? CraftTask.ResultCards : 1
        read := ""
        Loop n {
            dx := (A_Index - 1) * (IsObject(r2) ? r2.x - res.x : 0)
            dy := (A_Index - 1) * (IsObject(r2) ? r2.y - res.y : 0)
            card := {x: res.x + dx, y: res.y + dy, w: res.w, h: res.h}
            t := (env.ocrFn)(card.x, card.y, card.w, card.h)
            if (A_Index = 1)
                read := t
            if !CraftTask.IsRecipe(t, plan.search)
                continue
            if (plan.hint = "" || InStr(GameLists.Fold(t), GameLists.Fold(plan.hint)))
                return card
        }
        return ""
    }

    ; One click in Stella's Workshop, only while its title (cauldron_gui)
    ; reads and no purchase prompt is up: cauldron_close clicks out of it,
    ; and a click on an empty spot can go through into the world (live
    ; 2026-11-02). The prompt guard runs after it.
    ; -> 1 clicked | 0 refused or a prompt came up (logged) | -1 stopped
    _CauldronClick(ctx, gui, pt, what) {
        env := this._env
        why := env.Unsafe("craft")
        if (why = "" && !RegExMatch((env.ocrFn)(gui.x, gui.y, gui.w, gui.h), CraftTask.GuiRe))
            why := "Stella's Workshop is not open (its title did not read)"
        if (why != "") {
            env.Log("craft: " what " not clicked: " why)
            return 0
        }
        env.Click(pt)
        if !env.Wait(CraftTask.SettleMs, ctx)
            return -1
        return env.BuyPrompt("craft") ? 0 : 1
    }

    _CauldronPhase(ctx, plan, lines) {
        if this._CauldronSteps(ctx, plan, lines)
            return true
        this._CloseCauldron(ctx, plan.cpts)
        return false
    }

    ; Told to stop at the cauldron: every wait returned with Stella's
    ; Workshop still open over the next task. A preempt (not F3 / pause /
    ; Roblox gone) clicks cauldron_close first, only while its title reads
    ; (_CauldronClick); a halt sends nothing.
    _CloseCauldron(ctx, p) {
        if (!ctx.ShouldStop() || CleanupCtx.Halted(ctx) || !this._WorkshopUp(p))
            return
        this._env.Log("craft: preempted at the cauldron: closing Stella's Workshop first")
        this._CauldronClick(CleanupCtx(ctx), p["cauldron_gui"], p["cauldron_close"], "cauldron_close")
    }

    ; Stella's Workshop title (cauldron_gui) reads right now.
    _WorkshopUp(p) {
        gui := (p is Map && p.Has("cauldron_gui")) ? p["cauldron_gui"] : ""
        return IsObject(gui) && RegExMatch((this._env.ocrFn)(gui.x, gui.y, gui.w, gui.h), CraftTask.GuiRe) > 0
    }

    ; The App's between-tasks check (Tidy): Stella's Workshop (cauldron_close,
    ; only while its title reads). Not calibrated: nothing.
    Leftovers() {
        env := this._env
        p := Map()
        for id in ["cauldron_gui", "cauldron_close"] {
            v := ""
            try v := (id = "cauldron_gui") ? env.cal.Rect(id) : env.cal.Point(id)
            if !IsObject(v)
                return []
            p[id] := v
        }
        return [{up: () => this._WorkshopUp(p) ? "cauldron panel" : ""
            , close: (label, ctx) => (r := this._CauldronClick(ctx, p["cauldron_gui"], p["cauldron_close"], "cauldron_close")) < 0 ? -1 : r ? 1 : 2}]
    }

    _CauldronSteps(ctx, plan, lines) {
        env := this._env
        io := env.io
        if !Input.PlayRoute(plan.cRoute, ctx, io)
            return false
        gui := plan.cpts["cauldron_gui"]
        stellaR := env.cal.Rect("stella_dialog")      ; optional: no missing-step report
        opened := false
        Loop CraftTask.GuiTries {
            if ctx.ShouldStop()
                return false
            Input.Key(CraftTask.OpenKey, 80, io)
            if !env.Wait(CraftTask.GuiOpenMs, ctx)
                return false
            if RegExMatch((env.ocrFn)(gui.x, gui.y, gui.w, gui.h), CraftTask.GuiRe) {
                opened := true
                break
            }
            ; Esc only when Stella's dialog is recognised by her name (Esc with
            ; nothing open opens the Roblox menu).
            stella := IsObject(stellaR) && RegExMatch((env.ocrFn)(stellaR.x, stellaR.y, stellaR.w, stellaR.h), CraftTask.StellaRe)
            if stella {
                env.Log("craft: cauldron GUI not open (attempt " A_Index "/" CraftTask.GuiTries "), Stella's dialog seen: Esc")
                Input.Key("Esc", 80, io)
                if !env.Wait(CraftTask.EscMs, ctx)
                    return false
            } else {
                env.Log("craft: cauldron GUI not open (attempt " A_Index "/" CraftTask.GuiTries "), nothing opened: no Esc")
            }
            if (A_Index < CraftTask.GuiTries) {
                Input.Key("s", CraftTask.StepBackMs, io)
                if !env.Wait(CraftTask.SettleMs, ctx)
                    return false
            }
        }
        if opened {
            p := plan.cpts
            env.Click(p["cauldron_search"])
            if !env.Wait(CraftTask.SettleMs, ctx)
                return false
            ; the box keeps the last visit's text: typed on top of it the
            ; search finds nothing (2026-10-27 review)
            Input.ClearText(io)
            Input.TypeText(plan.search, io)
            if !env.Wait(CraftTask.SettleMs, ctx)
                return false
            card := this._FindCard(plan, &read)
            if !IsObject(card) {
                msg := (plan.hint = "" ? "the first search result is not " : "no search result is ") plan.target
                    . " (read: '" SubStr(Trim(RegExReplace(read, "\s+", " ")), 1, 60) "'); nothing added"
                env.Log("craft: " msg)
                env.Report("errors", "Cauldron recipe not found", msg, 0xE74C3C)
                lines.Push("cauldron: " msg)
                if (this._CauldronClick(ctx, gui, p["cauldron_close"], "cauldron_close") < 0)
                    return false
                return Input.ResetToSpawn(ctx, io)
            }
            r := this._CauldronClick(ctx, gui, {x: card.x + card.w // 2, y: card.y + card.h // 2}, "the result card")
            for id in ["cauldron_open_recipe", "cauldron_add_all", "cauldron_close"] {
                if (r < 1)
                    break
                r := this._CauldronClick(ctx, gui, p[id], id)
            }
            if (r < 0)
                return false
            lines.Push(r ? "cauldron: opened (Stella's Workshop seen), " plan.target " found, clicked Open Recipe and Add All (contents not verified)"
                : "cauldron: " plan.target " found, but Stella's Workshop went away (or a purchase prompt came up): stopped before Add All was confirmed")
        } else {
            msg := "cauldron GUI did not open after " CraftTask.GuiTries " tries (Stella's dialog?); nothing crafted"
            env.Log("craft: " msg)
            env.Report("errors", "Cauldron not opened", msg, 0xE74C3C)
            lines.Push("cauldron: " msg)
        }
        ; Done at the cauldron (its close button was clicked above): respawn so
        ; the next task starts from spawn; fishing notices it is not at the
        ; fishing spot (no fishing panel) and walks back on its own.
        return Input.ResetToSpawn(ctx, io)
    }
}
