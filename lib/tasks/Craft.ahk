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
;   t.CanRun(state)  THE BUY HAPPENS ONLY AFTER THE GAME'S CRAFTED
;                    NOTIFICATION ("... crafted ...", read by OCR in the
;                    calibrated notify_rect, at most every NotifyPollMs, and
;                    only once Craft.minIntervalMin (default 10) minutes
;                    have passed since the last run or buy: one toast that
;                    stays up is one buy). Nothing else buys: not the Start,
;                    not a timer, not a Sell visit on its own (2026-11-23:
;                    the owner had 30k Lucky Potions and no fish points
;                    left; the buy on every Start, the timed buy every 30
;                    min at each Sell visit and the retry after ANY cut-short
;                    run all bought without a toast). A seen notification is
;                    latched (_notified) until ONE buy happens: the next
;                    Sell visit (BuyDue / BuyHere) or a craft trip, whichever
;                    is first; the other then has nothing to buy. A buy cut
;                    short before any Confirm was clicked keeps the latch
;                    (retried); once a Confirm was clicked it is cleared
;                    (never bought twice for one toast). Without notify_rect
;                    nothing is ever bought (logged once).
;                    THE CAULDRON (Craft.cauldron) keeps its own triggers
;                    (_cauldronDue): its first visit since Start, each
;                    crafted notification, a cut-short cauldron run. A
;                    cauldron-only run never buys.
;                    false when Craft.enabled = 0 and Craft.cauldron = 0
;                    (the cauldron runs alone with only it on).
;   t.Run(ctx)       -> number of potions whose confirm was clicked with the shop UI seen.
;
; SETTINGS (settings.ini [Craft]; defaults in Config.IniDefaults)
;   enabled      1                       Fish shop: buy the potions at the Fisher (task on/off with cauldron 0)
;   potions      Lucky Potion                comma list of full names, each must be
;                                        sold in the Fisher shop (GameLists.Shop;
;                                        Calibrate.Potions()
;                                        validates it: the app must have called
;                                        Calibrate.Use(path, cfg))
;   qty          1                       units per potion per buy (1..999), typed
;                                        once per crafted notification
;   minIntervalMin 10                    minutes after a run / buy before the
;                                        notification is read again (1..1440;
;                                        else 10)
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
;     buy part: >=1 potion (its tile needs NO calibration: a potion with no
;       fisher_item_<potion> point is placed in the open shop by AutoCal, by
;       its name under its picture or its place in the grid from the shop's
;       title; a recorded tile is tried first and still has to read right),
;       fisher_buy_button, fisher_qty, fisher_confirm, fisher_purchase_close,
;       fisher_open_shop, the fisher_picked_name rect (the picked item's name
;       in the shop; nothing is bought without reading it), the craft coords
;       and the fisher routes. fisher_leave (Captain Flarg's Leave button) is
;       optional.
;     cauldron part (Craft.cauldron=1): craftTarget, the point
;       cauldron_add_all and a NON-EMPTY cauldron route. The title
;       (cauldron_gui), the search box, the result cards, Open Recipe and
;       the X are FOUND ON SCREEN when they are not recorded, or when the
;       recorded title box does not read (_Workshop, lib\AutoCal.ahk); a
;       full calibration whose title box reads is used as before. The
;       Craft button (cauldron_craft) is optional: found on screen by its
;       word when it is not recorded.
;   Roblox focus (failure -> log, ctx-aware wait, retry later) -> ResetToSpawn.
;   Buy: camera zoom -> toShop route -> dialog clicks -> Captain Flarg shows
;     two buttons, Sell Fish and Open Shop: wait up to ShopWaitMs until OCR
;     around fisher_open_shop reads "shop" (and not "sell"), then click it.
;     Never seen -> nothing else is clicked or typed, the visit reports it
;     (errors webhook) and goes back. The walk is checked first (_AtFisher:
;     his dialog, his buttons or the shop reads after the route's E): not
;     there -> the "nudge" hops, then respawn + walk again, FisherWalks
;     walks in all (the last one's shop steps run anyway). Then per potion:
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
;   SAME VISIT AS THE SELL: when a buy is due (BuyDue: a crafted notification
;   is latched) while Sell is at the fisher, Sell calls BuyHere right after
;   closing its shop (BuyHere itself refuses without the latch): E (skipped when
;   his Open Shop button is still up, or when the Fishing Shop itself is
;   still open: E over the open shop brings his dialog back on top of it and
;   its "Click to skip" eats the next tile click), dialog, Open Shop, the
;   Buy tab, buy, close; Sell then walks back. No second trip.
;   Open Shop never readable (ShopWaitMs, one extra skip click halfway) ->
;   nothing is bought and Captain Flarg's dialog is LEFT (fisher_leave) and
;   checked, so the walk back never starts with his dialog open. In BuyHere
;   the buy then stays due, so a craft trip retries it (once: a craft trip
;   whose shop does not open clears the latch, reported).
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
;     Click it, Open Recipe, Add All, then CRAFT (just in case auto craft
;     did not: the recorded cauldron_craft, else the button found on
;     screen by its word, CraftTask.IsCraftButton, in CraftBox around Add
;     All and the Workshop's left panel; not found -> logged, a screen of
;     the open recipe saved (io.Shot), the trip still counts and closes),
;     close (click out of the cauldron), then
;     ResetToSpawn: the next task starts from spawn (LeftSpot() tells the
;     App, which runs the sell trip next: it walks to the fishing spot).
;     There is no return route.
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
    static GuiOpenMs := 900        ; first look after F
    ; F fades the screen to dark first; the Workshop shows ~1-2 s later (live
    ; 2026-11-21: dark at 0.9 s, open at 2.4 s). One look at 0.9 s missed it
    ; every time, then S + F walked away: "cauldron GUI did not open" on every
    ; run, the user's and a tester's. Looked for this long, every GuiPollMs.
    static GuiWaitMs := 4500
    static GuiPollMs := 300
    ; THE PORTAL (live 2026-11-21, four recorded walks): the cauldron route
    ; walks into the portal of Stella's Sanctuary (~35.3 s), the screen goes
    ; black for ~0.5 s (the teleport, ~36.2 s) and the player stands inside
    ; at ~37 s; its last move (A held 1 s from 37.1 s) is meant for inside.
    ; One walk in four reached the portal and did not go through: the strafe
    ; then happened outside and F opened nothing ("cauldron GUI did not
    ; open", the user's and a tester's). So the route is split at the portal:
    ; walk to it, wait for the teleport (the black frame, or the "Stella's
    ; Sanctuary" banner, which the aura's name above the player covers to
    ; 'ell..'s'), then the rest; no teleport: respawn and walk again. The
    ; split is the route's "portalAt" (steps up to the portal), else the
    ; shipped route's own (PortalRoute: its step count and length).
    static PortalRoute := {steps: 88, ms: 38123, at: 86}
    ; The black frame comes only ~0.25 s after the walk to the portal ends
    ; (recorded: in at 35.3 s, black at ~36.2 s, the walk's last key up at
    ; 35.95 s): a walk a little ahead went black while its last steps still
    ; played (live 2026-11-25 03:24: "no dark frame", the screen saved at
    ; the miss shows the player inside). The walk's tail (from the last
    ; moment no key is held, at least TailMinMs before its end) is played
    ; with the black frame looked for (PortalTail, _WatchCtx).
    static TailMinMs := 1500
    ; A walk that stopped in front of the portal (live 2026-11-25 03:45,
    ; 04:37: its corridor, its glow beside the player) holds the last key
    ; walked into it NudgeMs more and waits NudgeWaitMs, before the respawn
    ; and the whole walk again (~40 s).
    static NudgeMs := 800
    static NudgeWaitMs := 2500
    static TeleportWaitMs := 4500
    static TeleportPollMs := 100
    static WalkTries := 3
    static FisherWalks := 3        ; walks to Captain Flarg per trip (the last one's shop steps run anyway)
    static FisherNudges := 3       ; "nudge" hops + E after a walk that stopped short (as SellTask.Nudges)
    static DarkPts := [[640, 360], [1280, 360], [1920, 360], [640, 720], [1920, 720], [640, 1080], [1280, 1080], [1920, 1080]]
    static DarkMax := 24           ; every channel at or below this = the black teleport frame
    static BannerBox := {x: 990, y: 225, w: 580, h: 75}
    static BannerRe := "i)s[ao]nct|e[il1|][il1|d].{0,2}s"
    static GuiSettleMs := 700      ; after the title reads: the window may still be coming in
    static SearchTries := 2        ; live 2026-11-21: the first search left the list unfiltered
    ; The title box as calibrated (preset h 35) cuts the letters: it read ''
    ; at 1x and 'Workst!pp' at 2x on the live frame; 10 px more above and 15
    ; below read 'Stello's Workshop'.
    static GuiPad := {top: 10, bottom: 15}
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
    ; live 2026-11-21 08:55: 'Opq6 *hoo' and 'ghøp_ Op' (S as g, o as ø / q,
    ; n as 6; the two words swapped): nothing bought on a craft trip
    ; live 2026-11-23 05:35: 'Opw% *hop' (S as *): "hop" after any one
    ; non-letter mark at a word start, not inside a word ('hope')
    static OpenShopRe := "i)[s$g]h[o0øq]+[pq]|\bopen\s*[s$][a-z]|\bop[eqo][n6]\b|(?:^|\s)[^a-z\s]h[o0øq]+[pq](?![a-z])"
    static OpenShopUp(t) => RegExMatch(t, CraftTask.OpenShopRe) && !RegExMatch(t, "i)sell")
    static ScrollTopNotches := 10  ; wheel up over the grid: back to its top row
    static ScrollTries := 8        ; then one notch down at a time to find a potion
    static ScrollMs := 250
    ; The shop's BUY grid (design coords 2560x1440; live frame 2026-11-21
    ; 03:17, tests\screens\fishshop_buy_tab.jpg): 4 columns of tall tiles 243
    ; apart, rows 304 apart, tile 1's centre 1125,596 (tiles 229 x 293). Two
    ; rows are in sight (8 of GameLists.Shop's 15 items), the rest comes up
    ; with the wheel. It is NOT the Sell tab's grid (5 columns, 190 apart),
    ; which this was first measured on: a tile worked out for row 3 was a
    ; click under the grid.
    static TilePitch := 243        ; columns
    static TilePitchY := 304       ; rows
    static GridCols := 4
    static GridBox := {x: 1005, y: 442, w: 973, h: 665}
    static GridEdge := 60          ; a tile's centre this far inside the box's top / bottom: enough of it shows to click
    static LabelScales := [1, 2]   ; the names under the pictures: row 2's smaller names read at 2x only
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
    ; THE CRAFT BUTTON (owner 2026-11-23: "click add all and craft just in
    ; case"). No frame of the opened recipe yet: the button is found by its
    ; word in a box around Add All (cauldron_add_all, preset 1104,911: the
    ; recipe window in the middle) that also takes in the Workshop's left
    ; panel (Open Recipe / Auto at y ~1095 on tests\screens\workshop_open),
    ; never the result list on the right. Read at 1x, then 2x.
    static CraftBox := {right: 900, up: 500, down: 450}
    static CraftScales := [1, 2]
    ; the word through the game-font fold (a as o, G for C, ! / l as i):
    ; 'Craft', 'Croft', 'CRAFT', 'Craft!', 'Cratt', 'Craff', '(raft',
    ; 'Grafl', 'Cr aft'; never 'Crafted' (the toast), 'Crafting', 'Auto',
    ; 'Add All'.
    static CraftWordRe := "^[cs]?ro(ft|ff|tt|fi|it|f)i?$"
    ; A line that is the Craft button's label: ONE real word (3+ letters
    ; after the fold; an icon read as 'o' or a dot is let through) and that
    ; word is Craft. "Auto Craft", "Add All Craft", a chat sentence: no.
    static IsCraftButton(text) {
        if RegExMatch(GameText.Fold(text), CraftTask.CraftWordRe)   ; 'Cr aft': a space inside the word
            return true
        hit := false
        for w in StrSplit(GameText.Norm(text), " ") {
            if (StrLen(w) < 3)
                continue
            if (hit || !RegExMatch(w, CraftTask.CraftWordRe))
                return false
            hit := true
        }
        return hit
    }
    static GuiRe := "i)workshop"
    static StellaRe := "i)\bstel"
    ; Both through the game-font fold (GameText): "workshop" has a k, which
    ; the font draws as l< / I< ('Worl<shop'), and "Stella" may read 'Gtello'
    ; (S as G). Live 2026-11-19 / 11-20: 0 of 6 cauldron opens read, and
    ; StellaRe never matched. The title wording itself has no frame yet.
    static WorkshopUp(t) => RegExMatch(String(t), CraftTask.GuiRe) > 0 || GameText.Has(t, "workshop")
    ; The Workshop title box (cauldron_gui) with GuiPad, read at 1x then 2x.
    ; -> the text that matched, else the 1x read.
    _GuiText(gui) {
        pd := CraftTask.GuiPad
        y := Max(0, gui.y - pd.top), h := gui.h + pd.top + pd.bottom
        first := ""
        for sc in [1, 2] {
            t := String((this._env.ocrFn)(gui.x, y, gui.w, h, sc))
            if (A_Index = 1)
                first := t
            if CraftTask.WorkshopUp(t)
                return t
        }
        return first
    }
    static StellaSeen(t) => RegExMatch(String(t), CraftTask.StellaRe) > 0 || GameText.StartsWord(t, "stel")
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
        this._notified := false      ; crafted notification seen, its ONE buy not yet done (the only buy trigger)
        this._cauldronDue := true    ; a cauldron visit is due: the first since Start, a notification, a cut-short visit
        this._notifyReadAt := ""     ; env.Now() of the last notify_rect read
        this._lastRunAt := ""        ; env.Now() when the last Run started or BuyHere bought
        this._confirmed := 0         ; Confirm clicks in the current buy (a cut-short buy with one is not retried)
        this._toldNoNotify := false  ; "no notify_rect: nothing is bought" logged
        this._portalAt := ""         ; the cauldron route's "portalAt" (steps up to the portal), "" = PortalRoute
        this._bannerRead := ""       ; the last non-empty read of the Sanctuary banner's box (_WaitTeleport)
        this._ws := ""               ; Stella's Workshop as found on screen this run (_Workshop)
        this._cur := ""              ; ... the parts in use while it is open
        this._wsTold := false
        this._guiRead := ""
        this._leftSpot := false      ; the last Run respawned and did not walk the "back" route to its end
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

    ; The buy part is the "Fish shop" switch (Craft.enabled), the cauldron
    ; part its own (Craft.cauldron). The cauldron never ran with the Fish
    ; shop (then "Craft cycle") off, 2026-11-19: only both off stops the task.
    _BuyOn() => (IsObject(this._env.cfg) && !this._env.cfg.Get("Craft.enabled", 1)) ? false : true
    _CauldronOn() => (IsObject(this._env.cfg) && this._env.cfg.Get("Craft.cauldron", 0)) ? true : false

    CanRun(state) {
        env := this._env
        if (!this._BuyOn() && !this._CauldronOn())
            return false
        if (this._aborts > 0 && env.Now() - this._abortAt < this._RetryGapMs())
            return false
        ; a latched notification's buy (or its retry), a due cauldron visit
        if (this.BuyDue() || (this._CauldronOn() && this._cauldronDue))
            return true
        ; minimum interval after a run / buy: a toast still up (or the next
        ; craft right after) is not a second buy
        if (this._lastRunAt !== "" && env.Now() - this._lastRunAt < this._MinIntervalMs())
            return false
        r := env.cal.Rect("notify_rect")
        if !IsObject(r) {
            if (this._BuyOn() && !this._toldNoNotify) {
                this._toldNoNotify := true
                env.Log("craft: notify_rect is not calibrated: the Fish shop buys nothing (it buys only after the crafted notification)")
            }
            return false
        }
        ; CanRun runs on the App's tick while a route plays: a slow OCR here
        ; freezes the walk with a key held (2026-10-27 review), or pauses the
        ; fishing reel (Input.InReel). Read later.
        if Input.Hot()
            return false
        now := env.Now()
        if (this._notifyReadAt !== "" && now - this._notifyReadAt < CraftTask.NotifyPollMs)
            return false
        this._notifyReadAt := now
        t := (env.ocrFn)(r.x, r.y, r.w, r.h)
        if !RegExMatch(t, CraftTask.NotifyRe)
            return false
        CalHealth.Ok("notify_rect", r)
        buy := this._BuyOn()
        this._notified := buy
        if this._CauldronOn()
            this._cauldronDue := true
        env.Log("craft: crafted notification seen ('" SubStr(RegExReplace(t, "\s+", " "), 1, 50) "'): "
            . (buy ? "one buy at the Fisher" : "cauldron visit"))
        return true
    }

    ; Sell hook: is a Fisher buy due? Only a latched crafted notification
    ; (CanRun) makes one; Sell then buys in the same visit, once.
    BuyDue() => this._BuyOn() && this._notified

    ; Buys while already standing at Captain Flarg (Sell just closed its
    ; shop): E opens his dialog again, then the same shop steps as a craft
    ; trip, without the respawn and the walk. The craft task then has no
    ; buying left to do (a cauldron step still runs on its own). Without a
    ; latched crafted notification (BuyDue) it buys nothing.
    ; -> purchases with the shop UI seen, or -1 when stopped.
    BuyHere(ctx) {
        env := this._env
        if !this.BuyDue()
            return 0
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
        this._confirmed := 0
        r := this._ShopPhase(ctx, plan, lines)
        if (r = -1) {
            ; cut short: retried (the latch stays) only if no Confirm was
            ; clicked yet; one clicked = this toast's buy is done
            this._BuyDone(true)
            return -1
        }
        if (r = CraftTask.NotOpened) {
            ; nothing was bought: the buy stays due (the craft trip tries
            ; again) instead of waiting for the next crafted notification
            ; (2026-10-27 review). 0, not < 0: Sell still walks back.
            return 0
        }
        this._BuyDone()
        for line in lines
            env.Log("craft: " line)
        desc := ""
        for line in lines
            desc .= (desc = "" ? "" : "`n") "- " line
        env.Report("craft", "Auto craft", desc)
        return r
    }

    ; The last Run left the player away from the fishing spot (respawned,
    ; and the "back" route was not walked to its end): the App then runs the
    ; sell trip next, which walks there, instead of fishing failing first.
    LeftSpot() => this._leftSpot

    ; The latched notification's buy happened: cleared, and the notification
    ; is not read again for minIntervalMin. cutShort: only when a Confirm was
    ; clicked (else the latch stays and the buy is retried).
    _BuyDone(cutShort := false) {
        if (cutShort && this._confirmed = 0)
            return
        this._notified := false
        this._lastRunAt := this._env.Now()
    }

    Run(ctx) {
        this._leftSpot := false
        this._lastRunAt := this._env.Now()
        if !this._BuyOn()
            this._notified := false      ; no latch kept for when the Fish shop is turned on
        this._confirmed := 0
        done := false
        try {
            return this._Visit(ctx, &done)
        } finally {
            if (this._confirmed > 0)
                this._BuyDone()          ; a Confirm was clicked: never bought twice for one toast
            if !done {
                ; stopped / unfocused: a latched buy (no Confirm clicked)
                ; and a due cauldron visit stay due and are tried again later
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
        ; ONLY a latched crafted notification buys (BuyDue); a part that is
        ; due but cannot run (not set up: _Plan reported it) is cleared, so
        ; the task does not come back every tick for nothing
        want := this.BuyDue()
        if (want && !plan.buy)
            this._notified := false
        plan.buy := plan.buy && want
        cDue := this._cauldronDue && plan.cauldron
        if !plan.cauldron
            this._cauldronDue := false
        plan.cauldron := cDue
        if (!plan.buy && !plan.cauldron) {
            done := true
            return 0
        }
        d := {io: env.io, roblox: this._roblox, log: (m) => env.Log(m)}
        if !FishLogic.FocusOrWait(d, ctx, "craft")
            return 0
        env.Log("craft: starting")
        if !plan.buy
            env.Log("craft: cauldron only" (this._BuyOn() ? "" : " (Fish shop off)"))
        io := env.io
        this._leftSpot := true                   ; from here until the "back" route is walked
        if !Input.ResetToSpawn(ctx, io)
            return 0
        lines := []
        shopSeen := 0
        if plan.buy {
            r := this._BuyPhase(ctx, plan, lines)
            if (r = -1)
                return 0                         ; (finally: retried unless a Confirm was clicked)
            ; this toast's buy is done; NotOpened (reported, nothing
            ; bought) too: a trip is not repeated until the next toast
            this._BuyDone()
            shopSeen := Max(r, 0)
            if plan.cauldron {
                if !Input.ResetToSpawn(ctx, io)
                    return 0
            } else if !Input.PlayRoute(plan.back, ctx, io) {
                return 0
            } else
                this._leftSpot := false          ; back at the fishing spot
        }
        if plan.cauldron {
            if !this._CauldronPhase(ctx, plan, lines)
                return 0
            this._cauldronDue := false
        }
        desc := ""
        for line in lines {
            desc .= (desc = "" ? "" : "`n") "- " line
            env.Log("craft: " line)
        }
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
        if this._BuyOn()
            this._PlanBuy(plan)
        this._PlanCauldron(plan)
        return plan
    }

    _PlanBuy(plan) {
        env := this._env
        items := []
        for name in this._Potions() {
            ; no tile recorded: placed in the shop's grid once it is open
            ; (_AutoTile); a recorded tile is tried first
            pt := env.cal.Point(Calibrate.PotionId(name))
            items.Push({name: name, pt: IsObject(pt) ? pt : "", qty: this._Qty(name)})
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
        if (variant = "nonvip") {               ; the shipped non-VIP recording first (as Sell)
            if IsObject(s := CraftTask._Steps(RouteRecorder.NonVip("toShop")))
                toShop := s
            if IsObject(s := CraftTask._Steps(RouteRecorder.NonVip("back")))
                back := s
        }
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
            ; not recorded: found on screen once the Workshop is open
            ; (_Workshop); Add All has no text to find it by
            auto := AutoCal.IsAuto(id)
            pt := auto ? env.cal.Point(id) : env.Point(id)
            if IsObject(pt)
                plan.cpts[id] := pt
            else if !auto
                ok := false
        }
        for id in CraftTask.CauldronRects {
            r := env.cal.Rect(id)
            if IsObject(r)
                plan.cpts[id] := r
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
        cb := env.cal.Point("cauldron_craft")         ; optional: found on screen when not recorded (_CraftPoint)
        plan.cpts["cauldron_craft"] := IsObject(cb) ? cb : ""
        plan.cRoute := route
    }

    ; The cauldron route split at the portal: {to: steps up to the portal
    ; (the last one's wait dropped: the teleport is waited for instead),
    ; inside: the rest}, or "" (no split known: played whole).
    static PortalSplit(steps, at := "") {
        if !(steps is Array)
            return ""
        if (at = "") {
            pr := CraftTask.PortalRoute
            total := 0
            for st in steps
                total += st.ms
            if (steps.Length != pr.steps || total != pr.ms)
                return ""
            at := pr.at
        }
        if (at < 1 || at >= steps.Length)
            return ""
        a := [], b := []
        for st in steps
            (A_Index <= at ? a : b).Push(st)
        last := a[a.Length].Clone()
        last.ms := 0
        a[a.Length] := last
        return {to: a, inside: b}
    }

    ; The walk to the portal split where its tail starts: the last moment no
    ; key is held (so the head's end releases nothing the tail still needs)
    ; at least TailMinMs before the end. None: the whole walk is the tail.
    ; -> {head, tail} (Arrays of steps)
    static PortalTail(steps) {
        held := Map(), cut := 0, left := 0
        for st in steps
            left += st.ms
        for i, st in steps {
            left -= st.ms
            if (st.action = "down")
                held[StrLower(st.key)] := true
            else if (st.action = "up" && held.Has(StrLower(st.key)))
                held.Delete(StrLower(st.key))
            if (i < steps.Length && held.Count = 0 && left >= CraftTask.TailMinMs)
                cut := i
        }
        head := [], tail := []
        for i, st in steps
            (i <= cut ? head : tail).Push(st)
        return {head: head, tail: tail}
    }

    ; The movement key (W A S D) pressed last in steps, lowercased; "" none.
    static LastMoveKey(steps) {
        k := ""
        for st in steps
            if (st.action = "down" && RegExMatch(st.key, "i)^[wasd]$"))
                k := StrLower(st.key)
        return k
    }

    ; A ctx for a walk that looks for the black frame at every wait slice
    ; (Input.Wait asks ShouldStop): .dark latches it; stops as ctx does.
    _WatchCtx(ctx) => CraftPortalWatch(ctx, () => this._Dark())

    ; The black teleport frame: every DarkPts sample dark.
    _Dark() {
        for pt in CraftTask.DarkPts {
            c := (this._sample)(pt[1], pt[2])
            if (((c >> 16) & 0xFF) > CraftTask.DarkMax || ((c >> 8) & 0xFF) > CraftTask.DarkMax || (c & 0xFF) > CraftTask.DarkMax)
                return false
        }
        return true
    }

    ; After the walk to the portal: the teleport seen (the black frame, then
    ; light again; or the banner) within waitMs. dark: the black frame was
    ; already seen during the walk (_WatchCtx). -> 1, 0 not, -1 stopped
    _WaitTeleport(ctx, dark := false, waitMs := "") {
        env := this._env
        b := CraftTask.BannerBox
        waited := 0, dark := dark ? true : false
        waitMs := (waitMs = "") ? CraftTask.TeleportWaitMs : waitMs
        this._bannerRead := ""
        Loop {
            if this._Dark() {
                dark := true
            } else if dark {
                return 1                            ; through the black frame
            } else if (Mod(A_Index, 4) = 1) {
                t := String((env.ocrFn)(b.x, b.y, b.w, b.h))
                if (Trim(t) != "")
                    this._bannerRead := SubStr(Trim(RegExReplace(t, "\s+", " ")), 1, 40)
                if RegExMatch(t, CraftTask.BannerRe)
                    return 1
            }
            if (waited >= waitMs)
                return dark ? 1 : 0
            if !env.Wait(CraftTask.TeleportPollMs, ctx)
                return -1
            waited += CraftTask.TeleportPollMs
        }
    }

    ; Walks the cauldron route: to the portal, the teleport waited for, then
    ; inside. The walk's tail is watched for the black frame (PortalTail). No
    ; teleport: the last key walked into the portal is held NudgeMs more
    ; (a walk that stopped in front of it), then respawn and walk again
    ; (WalkTries); after the last try the rest is walked anyway (F then
    ; reports what it finds). -> true, false stopped
    _WalkToCauldron(ctx, steps) {
        env := this._env
        io := env.io
        split := CraftTask.PortalSplit(steps, this._portalAt)
        if !IsObject(split)
            return Input.PlayRoute(steps, ctx, io)
        parts := CraftTask.PortalTail(split.to)
        nk := CraftTask.LastMoveKey(split.to)
        Loop CraftTask.WalkTries {
            if (A_Index > 1 && !Input.ResetToSpawn(ctx, io))
                return false
            if (parts.head.Length && !Input.PlayRoute(parts.head, ctx, io))
                return false
            w := this._WatchCtx(ctx)
            if !Input.PlayRoute(parts.tail, w, io)
                return false
            t := this._WaitTeleport(ctx, w.dark)
            if (t = 0 && nk != "") {
                w := this._WatchCtx(ctx)
                if !Input.PlayRoute([[nk, "down", CraftTask.NudgeMs], [nk, "up", 0]], w, io)
                    return false
                t := this._WaitTeleport(ctx, w.dark, CraftTask.NudgeWaitMs)
                if (t > 0)
                    env.Log("craft: the walk stopped short of the portal: nudged into the portal (" StrUpper(nk) " held "
                        . Round(CraftTask.NudgeMs / 1000, 1) " s more, walk " A_Index ")")
            }
            if (t < 0)
                return false
            if t {
                if (A_Index > 1)
                    env.Log("craft: through the portal on walk " A_Index)
                if !env.Wait(300, ctx)
                    return false
                return Input.PlayRoute(split.inside, ctx, io)
            }
            ; live 2026-11-23..24: six first walks missed, every second one
            ; went through, nothing kept to tell why: the first miss saves
            ; the screen, each says what was seen
            if (A_Index = 1) {
                shot := HasMethod(io, "Shot") ? io.Shot() : ""
                if (shot != "")
                    env.Log("craft: screen where the walk missed the portal saved to " shot)
            }
            env.Log("craft: the walk did not go through the portal into Stella's Sanctuary (walk " A_Index "/" CraftTask.WalkTries
                . "; no dark frame in " Round(CraftTask.TeleportWaitMs / 1000, 1) " s" (nk != "" ? " nor after the nudge" : "")
                . ", banner read: '" this._bannerRead "')"
                . (A_Index < CraftTask.WalkTries ? ": respawning to walk again" : ""))
        }
        return Input.PlayRoute(split.inside, ctx, io)
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
        this._portalAt := (raw is Map && raw.Has("portalAt") && CraftTask._IsInt(raw["portalAt"])) ? Integer(raw["portalAt"]) : ""
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
        ; THE WALK TO THE FISHER (2026-11-21 route audit): the craft trip
        ; played the route once and, with no dialog after its E, reported
        ; "Captain Flarg's dialog not seen" and bought nothing. The sell trip
        ; walks the same route with a check (live: 1 walk in 241 missed him,
        ; the walk after it arrived): the same here. No dialog, no Open Shop
        ; button and no shop: the "nudge" hops (as Sell), then a respawn and
        ; the walk again, FisherWalks walks in all; after the last one the
        ; shop steps run anyway and report what they find, as before.
        Loop CraftTask.FisherWalks {
            if (A_Index > 1) {
                env.Log("craft: Captain Flarg's dialog did not open, the walk missed the Fisher (walk " (A_Index - 1) "/" CraftTask.FisherWalks "): respawning to walk again")
                if !Input.ResetToSpawn(ctx, io)
                    return -1
            }
            if !FishLogic.Zoom(io, ctx, plan.coords["sell"]["camera"])
                return -1
            if !Input.PlayRoute(plan.toShop, ctx, io)
                return -1
            r := this._AtFisher(ctx, plan)
            nudge := CraftTask._Steps(FishLogic._Dig(env.cfg.Data("routes"), "nudge.steps"))
            Loop (IsObject(nudge) ? CraftTask.FisherNudges : 0) {
                if (r != 0)
                    break
                env.Log("craft: not at the Fisher yet - hopping forward (" A_Index "/" CraftTask.FisherNudges ")")
                if !Input.PlayRoute(nudge, ctx, io)
                    return -1
                r := this._AtFisher(ctx, plan)
            }
            if (r < 0)
                return -1
            if r {
                if (A_Index > 1)
                    env.Log("craft: at the Fisher on walk " A_Index)
                break
            }
            if (A_Index = 1) {
                shot := HasMethod(io, "Shot") ? io.Shot() : ""
                if (shot != "")
                    env.Log("craft: screen where the walk missed the Fisher saved to " shot)
            }
        }
        return this._ShopPhase(ctx, plan, lines)
    }

    ; After the walk's E: Captain Flarg's dialog, his Open Shop button or the
    ; Fishing Shop reads (the dialog waited for, DialogWaitMs).
    ; -> 1 | 0 not there | -1 stopped
    _AtFisher(ctx, plan) {
        if (this._ShopIsOpen() || this._ShopButtonUp(plan))
            return 1
        return this._WaitDialog(ctx, plan)
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
            if (seen = 0)                       ; his dialog was up: the button's own read missed
                CalHealth.Fail("fisher_open_shop", "Open Shop did not read at it while Captain Flarg's dialog was up", plan.shopPt)
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
        if !up {
            CalHealth.Fail("fisher_open_shop", "a click on it did not open the Fishing Shop", plan.shopPt)
            return this._NotOpened(ctx, plan, lines, "the Fishing Shop did not open after Open Shop (its title did not read); nothing bought")
        }
        CalHealth.Ok("fisher_open_shop", plan.shopPt)
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
        ; folded (GameText): the real popup reads "wont" for want, l< for k
        return GameText.HasAny((env.ocrFn)(d.x, d.y, d.w, d.h, d.scale), d.words)
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
    ; A Roblox Robux prompt reads in Input.PurchaseBox: its Robux-only lines
    ; ("Buy Robux and item", "balance after this transaction", "be charged",
    ; "payment method"), never the shop's own words
    static RobuxRe := "i)r[o0]bux|balance\s*after|be\s*charged|payment\s*meth[o0]d"
    _RobuxPrompt() {
        b := Input.PurchaseBox, t := ""
        try t := (this._env.ocrFn)(b.x, b.y, b.w, b.h)
        return RegExMatch(t, CraftTask.RobuxRe) > 0
    }

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
    ; A potion with no recorded tile is looked for by its name under its
    ; picture (else by its place in the two rows in sight at the top). A
    ; tile that did not show the potion: its name is looked for again, there
    ; and after every notch down, recorded tile or not (the rows below the
    ; two in sight only come up with the wheel).
    ; -> {found, read} (read = the first name read), {found, read, why} when
    ; a tile click was refused or brought up a purchase prompt, or "" when
    ; stopped.
    _PickItem(ctx, plan, item) {
        env := this._env
        io := env.io
        read := ""
        auto := !IsObject(item.pt)
        readAt := ""                                ; the tile whose click gave `read`
        b := CraftTask.GridBox
        mid := {x: b.x + b.w // 2, y: b.y + b.h // 2}      ; the wheel needs the mouse over the grid
        clicked := false
        Loop CraftTask.ScrollTries + 2 {
            if ctx.ShouldStop()
                return ""
            at := IsObject(item.pt) ? item.pt : mid
            io.MoveTo(at.x, at.y)
            if (A_Index = 1)
                Input.Wheel("up", CraftTask.ScrollTopNotches, io)
            else if (A_Index > 2)                  ; try 2: the same tile again (a click can be lost)
                Input.Wheel("down", 1, io)
            if !env.Wait(CraftTask.ScrollMs, ctx)
                return ""
            if ((auto && A_Index = 1) || A_Index >= 2) {
                t := this._AutoTile(item.name, A_Index = 1)
                if (IsObject(t) && !(IsObject(item.pt) && t.x = item.pt.x && t.y = item.pt.y)) {
                    env.Log("craft: " item.name ": tile found on screen at " t.x "," t.y " (" t.how (A_Index > 2 ? ", " (A_Index - 2) " down the list" : "") ")"
                        . (auto ? "" : "; its recorded tile shows '" SubStr(Trim(RegExReplace(read, "\s+", " ")), 1, 30) "': recalibrate " Calibrate.PotionId(item.name) " (or delete it: the tile is found on screen)"))
                    item := {name: item.name, pt: {x: t.x, y: t.y}, qty: item.qty, auto: true, k: t.k}
                }
            }
            if !IsObject(item.pt)
                continue                            ; not in sight yet: the next notch
            clicked := true
            res := this._ClickRead(ctx, plan, item.pt, item.name)
            if !IsObject(res)
                return ""
            if (read = "" && res.read != "")
                read := res.read, readAt := item.pt
            if res.HasOwnProp("why")
                return {found: false, read: read, why: res.why}
            if res.found
                return {found: true, read: res.found}
            if (A_Index = 2 && IsObject(readAt)) {
                ; the tile shows another shop item: the other tiles in
                ; sight, found from where that item sits in the grid (a
                ; tester's Potion of Bound tile showed Rainy Bottle, 2026-11-21)
                at := {name: item.name, pt: readAt, qty: item.qty}
                for k in ["auto", "k"]
                    if (item.HasOwnProp(k) && item.pt = readAt)
                        at.%k% := item.%k%
                g := this._GridSearch(ctx, plan, at, read)
                if !IsObject(g)
                    return ""
                if (g.found || g.HasOwnProp("why"))
                    return g
            }
        }
        if !clicked
            return {found: false, read: "", why: "its tile could not be placed in the shop's grid: its name did not read there, at the top or " CraftTask.ScrollTries " notches down (not a Fisher shop item?)"}
        return {found: false, read: read}
    }

    ; Where the potion's tile is, found on screen (lib\AutoCal.ahk; the shop
    ; is open): its name under its picture in the grid when that reads (at
    ; 1x, then 2x), else, with place = true (the grid is at its top), its
    ; place in the grid (GameLists.Shop's order, the two rows in sight) from
    ; the shop's title, else from the shop's usual place (the title reads in
    ; its fixed box before any tile click). The pick is still checked by the
    ; name read.
    ; -> {x, y, k (its place in the grid, 0 = by its name), how} or "" (not
    ; a shop item / not in sight)
    _AutoTile(name, place := true) {
        b := CraftTask.GridBox, t := CraftTask.ShopTitle
        inBox := (q) => IsObject(q) && q.x >= b.x && q.x <= b.x + b.w && q.y >= b.y && q.y <= b.y + b.h
        x0 := t.x - 60, y0 := t.y - 40
        title := ""
        for sc in CraftTask.LabelScales {
            lines := this._env.Lines({x: x0, y: y0, w: b.x + b.w + 40 - x0, h: b.y + b.h + 40 - y0}, sc)
            tl := AutoCal.ShopTitle(lines)
            if !IsObject(title)
                title := tl
            lab := AutoCal.ShopLabel(lines, IsObject(tl) ? tl : title, (txt) => CraftTask.IsItem(txt, name))
            if inBox(lab)
                return {x: lab.x, y: lab.y, k: 0, how: "its name read in the grid"}
        }
        if !place
            return ""
        k := 0
        for n in GameLists.Shop
            if (GameLists.Fold(n) = GameLists.Fold(name))
                k := A_Index
        q := k ? AutoCal.ShopTile(title, k) : ""
        if !inBox(q)
            return ""
        return {x: q.x, y: q.y, k: k, how: "tile " k " of the grid" (IsObject(title) ? ", from the shop's title" : "")}
    }

    ; Clicks pt (only while the shop's title reads, no Roblox prompt) and
    ; reads the picked name. -> {found (the matching read or ""), read} |
    ; {found: "", read, why} | "" when stopped.
    _ClickRead(ctx, plan, pt, name) {
        env := this._env
        gap := plan.coords["craft"]["stepMs"]
        r := plan.nameR
        if ((why := env.Unsafe("craft")) != "")
            return {found: "", read: "", why: why}
        if !this._ShopIsOpen()
            return {found: "", read: "", why: "the Fishing Shop is not open (its title did not read): tile not clicked"}
        env.Click(pt)
        if !env.Wait(gap, ctx)
            return ""
        if env.BuyPrompt("craft")
            return {found: "", read: "", why: "a Roblox purchase prompt came up after the tile click (closed with Esc)"}
        first := "", named := false
        for sc in CraftTask.NameScales {
            t := (env.ocrFn)(r.x, r.y, r.w, r.h, sc)
            if (A_Index = 1)
                first := t
            if CraftTask.IsItem(t, name) {
                CalHealth.Ok("fisher_picked_name", r)
                return {found: t, read: first}
            }
            named := named || CraftTask.ShopIndex(t) > 0
        }
        ; another item's name reads: the box is right (the tile was not)
        named ? CalHealth.Ok("fisher_picked_name", r) : CalHealth.Fail("fisher_picked_name", "no shop item's name read in it after a tile click", r)
        return {found: "", read: first}
    }

    ; Index (1-based) in GameLists.Shop of the item the text names, else 0.
    static ShopIndex(text) {
        for n in GameLists.Shop
            if CraftTask.IsItem(text, n)
                return A_Index
        return 0
    }

    ; The shop tiles IN SIGHT, in design coords, when the tile at pt shows
    ; shop item k: [{i, x, y}] for every GameLists.Shop item whose tile lies
    ; in the grid box (4 columns; the rows above / below the box are under
    ; the wheel and left out), or [] when pt or a column falls outside the
    ; box (another layout: nothing is clicked).
    static GridTiles(pt, k) {
        PX := CraftTask.TilePitch, PY := CraftTask.TilePitchY, C := CraftTask.GridCols
        b := CraftTask.GridBox, e := CraftTask.GridEdge
        if (!IsObject(pt) || k < 1 || k > GameLists.Shop.Length)
            return []
        x0 := pt.x - Mod(k - 1, C) * PX, y0 := pt.y - ((k - 1) // C) * PY
        if (x0 < b.x || x0 + (C - 1) * PX > b.x + b.w || pt.y < b.y || pt.y > b.y + b.h)
            return []
        out := []
        Loop GameLists.Shop.Length {
            x := x0 + Mod(A_Index - 1, C) * PX, y := y0 + ((A_Index - 1) // C) * PY
            if (y >= b.y + e && y <= b.y + b.h - e)
                out.Push({i: A_Index, x: x, y: y})
        }
        return out
    }

    ; The calibrated tile read another shop item: click the potion's own
    ; place in the grid first, then the other tiles, reading each name.
    ; A tile placed on the grid by the macro (no calibration) that read
    ; nothing, or no shop item: the grid is known from its own place, the
    ; other tiles are read the same way.
    ; -> {found, read} | "" when stopped.
    _GridSearch(ctx, plan, item, read) {
        none := {found: false, read: read}
        k := CraftTask.ShopIndex(read)
        if (!k && item.HasOwnProp("k"))
            k := item.k
        if !k
            return none
        tiles := CraftTask.GridTiles(item.pt, k)
        if !tiles.Length
            return none
        want := 0
        for n in GameLists.Shop
            if (GameLists.Fold(n) = GameLists.Fold(item.name))
                want := A_Index
        order := []
        for t in tiles
            if (want && want != k && t.i = want)    ; (its own place was just tried when the macro placed it)
                order.Push(t)
        ; its place is below the rows in sight: the wheel search finds it
        ; by its name, no scan of the tiles that cannot be it
        if (want && want != k && !order.Length)
            return none
        for t in tiles
            if (t.i != k && t.i != want)
                order.Push(t)
        for t in order {
            if ctx.ShouldStop()
                return ""
            res := this._ClickRead(ctx, plan, {x: t.x, y: t.y}, item.name)
            if !IsObject(res)
                return ""
            if res.HasOwnProp("why")
                return {found: false, read: read, why: res.why}
            if res.found {
                shows := "'" SubStr(Trim(RegExReplace(read, "\s+", " ")), 1, 30) "'"
                this._env.Log("craft: " item.name " found on another shop tile (" t.x "," t.y "); "
                    . (item.HasOwnProp("auto") ? "the place worked out for it shows " shows " (the shop's order changed)"
                    : "its calibrated tile shows " shows ": recalibrate " Calibrate.PotionId(item.name) " (or delete it: the tile is found on screen)"))
                return {found: true, read: res.found}
            }
        }
        return none
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
            ; the confirm is seen by one pixel colour or a title: a Roblox
            ; purchase prompt (Robux) over that spot must never take the
            ; click. Only its Robux lines count here (the shop's own window
            ; is up and is no Roblox prompt). Closed with Esc, nothing bought.
            if this._RobuxPrompt() {
                env.BuyPrompt("craft")
                msg := item.name ": not bought: a Roblox purchase prompt was up (closed with Esc, never clicked)"
                env.Log("craft: " msg)
                return {ok: false, line: msg}
            }
            if this._PurchaseUp(plan) {
                Screen.WithMode("C", () => env.Click(conf))
                this._confirmed += 1             ; bought (or as good as): a cut-short buy is not repeated
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
        norm := (s) => Trim(RegExReplace(StrReplace(RegExReplace(StrLower(GameText.FixK(s))
            , "[l1|!]", "i"), "o", "a"), "[^a-z0-9]+", " "))
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

    ; Every part the calibrated Workshop needs is recorded.
    static CalParts := ["cauldron_gui", "cauldron_search", "cauldron_result", "cauldron_open_recipe", "cauldron_close"]
    static _Full(c) {
        for id in CraftTask.CalParts
            if !(c.Has(id) && IsObject(c[id]))
                return false
        return true
    }

    ; Stella's Workshop on screen right now -> its parts (a Map by step id),
    ; or "". The calibrated ones while the calibrated title box reads and
    ; every part is recorded (a full calibration works as before). Else
    ; FOUND ON SCREEN (AutoCal.Workshop, one read of the screen): the
    ; title's own line places the search box, the X and the result cards,
    ; "Open Recipe" is found by its words; the title is read once more at
    ; the place found before anything is used. this._guiRead = the title read.
    _Workshop(plan) {
        env := this._env
        c := plan.cpts
        gui := c.Has("cauldron_gui") ? c["cauldron_gui"] : ""
        this._guiRead := ""
        if IsObject(gui) {
            this._guiRead := this._GuiText(gui)
            if CraftTask.WorkshopUp(this._guiRead) {
                CalHealth.Ok("cauldron_gui", gui)
                if CraftTask._Full(c)
                    return c
            }
        }
        ws := AutoCal.Workshop(env.Lines())
        if !IsObject(ws)
            return ""
        t := this._GuiText(ws.gui)
        if !CraftTask.WorkshopUp(t)
            return ""
        if (IsObject(gui) && !CraftTask.WorkshopUp(this._guiRead))
            CalHealth.Fail("cauldron_gui", "Stella's Workshop title did not read in it; the window was found elsewhere on screen", gui)
        this._guiRead := t
        p := Map("cauldron_gui", ws.gui, "cauldron_search", ws.search, "cauldron_close", ws.close
            , "cauldron_open_recipe", IsObject(ws.open) ? ws.open : (c.Has("cauldron_open_recipe") ? c["cauldron_open_recipe"] : "")
            , "cauldron_add_all", c.Has("cauldron_add_all") ? c["cauldron_add_all"] : ""
            , "cauldron_craft", c.Has("cauldron_craft") ? c["cauldron_craft"] : "", "auto", ws)
        if !this._wsTold {
            this._wsTold := true
            env.Log("craft: Stella's Workshop found on screen (its title at " ws.title.x "," ws.title.y "): the search box, the result cards, Open Recipe and its X are placed from it"
                . (IsObject(gui) ? " (the calibrated title box did not read it)" : ""))
        }
        this._ws := p
        return p
    }

    ; The result card to click, or "" (read = the first card's text). Plain
    ; recipes: the first card only. A Godly Potion: the first of up to
    ; ResultCards cards whose title matches and whose description shows its
    ; Lord; cards past the first need the cauldron_result_2 offset.
    ; p found on screen (p["auto"]): the cards are found by their titles in
    ; the list (AutoCal.Card), the one picked is read again as a card.
    _FindCard(plan, p, &read) {
        env := this._env
        if p.Has("auto") {
            ws := p["auto"]
            lines := env.Lines(ws.list)
            read := ""
            for L in lines
                if (A_Index <= 2)
                    read .= (read = "" ? "" : "`n") L.text
            card := AutoCal.Card(lines, (t) => CraftTask.IsRecipe(t, plan.search), plan.hint, ws)
            if !IsObject(card)
                return ""
            t := (env.ocrFn)(card.x, card.y, card.w, card.h)
            if (!CraftTask.IsRecipe(t, plan.search) || (plan.hint != "" && !InStr(GameLists.Fold(t), GameLists.Fold(plan.hint)))) {
                read := t
                return ""
            }
            return card
        }
        res := p["cauldron_result"]
        r2 := (p.Has("cauldron_result_2") && IsObject(p["cauldron_result_2"])) ? p["cauldron_result_2"] : ""
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
        if (why = "" && !CraftTask.WorkshopUp(this._GuiText(gui)))
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

    ; Where to click Craft, or "": the recorded cauldron_craft first, else
    ; the button found on screen by its word (_FindCraft).
    _CraftPoint(p) {
        pt := p.Has("cauldron_craft") ? p["cauldron_craft"] : ""
        return IsObject(pt) ? pt : this._FindCraft(p)
    }

    ; The box the Craft button is looked for in (design px), or "" without
    ; Add All: from the screen's left edge (the Workshop's left panel is in
    ; it) to CraftBox.right past Add All, but short of the Workshop's title
    ; (the result list on the right is never searched); CraftBox.up above
    ; Add All to CraftBox.down under it.
    static CraftSearchBox(p) {
        add := p.Has("cauldron_add_all") ? p["cauldron_add_all"] : ""
        if !IsObject(add)
            return ""
        gui := p.Has("cauldron_gui") ? p["cauldron_gui"] : ""
        b := CraftTask.CraftBox
        x1 := Min(Screen.DesignW, add.x + b.right)
        if (IsObject(gui) && gui.x > add.x + 50)
            x1 := Min(x1, gui.x - 20)
        y0 := Max(0, add.y - b.up), y1 := Min(Screen.DesignH, add.y + b.down)
        return {x: 0, y: y0, w: x1, h: y1 - y0}
    }

    ; The Craft button by its word (IsCraftButton) in CraftSearchBox, the
    ; line nearest Add All; 1x first, then 2x. -> {x, y} or "".
    _FindCraft(p) {
        env := this._env
        box := CraftTask.CraftSearchBox(p)
        if !IsObject(box)
            return ""
        add := p["cauldron_add_all"]
        for sc in CraftTask.CraftScales {
            best := "", bestD := ""
            for L in env.Lines(box, sc) {
                if (L.x < box.x || L.x > box.x + box.w || L.y < box.y || L.y > box.y + box.h || !CraftTask.IsCraftButton(L.text))
                    continue
                d := (L.x - add.x) ** 2 + (L.y - add.y) ** 2
                if (!IsObject(best) || d < bestD)
                    best := L, bestD := d
            }
            if IsObject(best) {
                env.Log("craft: the Craft button found on screen at " best.x "," best.y " (read '" Trim(best.text) "')")
                return {x: best.x, y: best.y}
            }
        }
        return ""
    }

    _CauldronPhase(ctx, plan, lines) {
        this._cur := ""                         ; the Workshop's parts once it is open
        if this._CauldronSteps(ctx, plan, lines)
            return true
        this._CloseCauldron(ctx, IsObject(this._cur) ? this._cur : plan.cpts)
        return false
    }

    ; Told to stop at the cauldron: every wait returned with Stella's
    ; Workshop still open over the next task. A preempt (not F3 / pause /
    ; Roblox gone) clicks cauldron_close first, only while its title reads
    ; (_CauldronClick); a halt sends nothing.
    _CloseCauldron(ctx, p) {
        if (!ctx.ShouldStop() || CleanupCtx.Halted(ctx) || !this._WorkshopUp(p)
            || !(p.Has("cauldron_close") && IsObject(p["cauldron_close"])))
            return
        this._env.Log("craft: preempted at the cauldron: closing Stella's Workshop first")
        this._CauldronClick(CleanupCtx(ctx), p["cauldron_gui"], p["cauldron_close"], "cauldron_close")
    }

    ; Stella's Workshop title (cauldron_gui) reads right now.
    _WorkshopUp(p) {
        gui := (p is Map && p.Has("cauldron_gui")) ? p["cauldron_gui"] : ""
        return IsObject(gui) && CraftTask.WorkshopUp(this._GuiText(gui))
    }

    ; The App's between-tasks check (Tidy): Stella's Workshop (cauldron_close,
    ; only while its title reads). Not calibrated: where it was found on
    ; screen this run (_Workshop), else nothing.
    Leftovers() {
        env := this._env
        p := Map()
        for id in ["cauldron_gui", "cauldron_close"] {
            v := ""
            try v := (id = "cauldron_gui") ? env.cal.Rect(id) : env.cal.Point(id)
            if IsObject(v)
                p[id] := v
        }
        if (p.Count < 2) {
            if !IsObject(this._ws)
                return []
            p := this._ws
        }
        return [{up: () => this._WorkshopUp(p) ? "cauldron panel" : ""
            , close: (label, ctx) => (r := this._CauldronClick(ctx, p["cauldron_gui"], p["cauldron_close"], "cauldron_close")) < 0 ? -1 : r ? 1 : 2}]
    }

    _CauldronSteps(ctx, plan, lines) {
        env := this._env
        io := env.io
        if !this._WalkToCauldron(ctx, plan.cRoute)
            return false
        this._wsTold := false
        p := "", gt := ""
        stellaR := env.cal.Rect("stella_dialog")      ; optional: no missing-step report
        opened := false
        Loop CraftTask.GuiTries {
            if ctx.ShouldStop()
                return false
            Input.Key(CraftTask.OpenKey, 80, io)
            if !env.Wait(CraftTask.GuiOpenMs, ctx)
                return false
            waited := CraftTask.GuiOpenMs
            Loop {
                p := this._Workshop(plan)        ; calibrated, or found on screen
                gt := this._guiRead
                if IsObject(p) {
                    opened := true
                    break
                }
                if (waited >= CraftTask.GuiWaitMs)
                    break
                if !env.Wait(CraftTask.GuiPollMs, ctx)
                    return false
                waited += CraftTask.GuiPollMs
            }
            if opened
                break
            ; Esc only when Stella's dialog is recognised by her name (Esc with
            ; nothing open opens the Roblox menu).
            st := IsObject(stellaR) ? String((env.ocrFn)(stellaR.x, stellaR.y, stellaR.w, stellaR.h)) : ""
            stella := CraftTask.StellaSeen(st)
            ; what the title box and her name box read, for the next look at
            ; why it did not open (no frame of her window yet)
            reads := " (title read: '" SubStr(Trim(RegExReplace(gt, "\s+", " ")), 1, 40) "'" (IsObject(stellaR) ? ", name read: '" SubStr(Trim(RegExReplace(st, "\s+", " ")), 1, 30) "'" : "") ")"
            if stella {
                env.Log("craft: cauldron GUI not open (attempt " A_Index "/" CraftTask.GuiTries "), Stella's dialog seen: Esc" reads)
                Input.Key("Esc", 80, io)
                if !env.Wait(CraftTask.EscMs, ctx)
                    return false
            } else {
                env.Log("craft: cauldron GUI not open (attempt " A_Index "/" CraftTask.GuiTries "), nothing opened: no Esc" reads)
            }
            if (A_Index < CraftTask.GuiTries) {
                Input.Key("s", CraftTask.StepBackMs, io)
                if !env.Wait(CraftTask.SettleMs, ctx)
                    return false
            }
        }
        if opened {
            this._cur := p
            gui := p["cauldron_gui"]
            if !env.Wait(CraftTask.GuiSettleMs, ctx)
                return false
            card := "", read := ""
            Loop CraftTask.SearchTries {
                if (A_Index > 1)
                    env.Log("craft: the first search result is not " plan.target " (read: '" SubStr(Trim(RegExReplace(read, "\s+", " ")), 1, 40) "'): searching again")
                if !this._WorkshopUp(p)
                    break
                env.Click(p["cauldron_search"])
                if !env.Wait(CraftTask.SettleMs, ctx)
                    return false
                ; the box keeps the last visit's text: typed on top of it the
                ; search finds nothing (2026-10-27 review)
                Input.ClearText(io)
                Input.TypeText(plan.search, io)
                ; the list filters when the box lets go of the text (live
                ; 2026-11-21: "Heavenly Potion" typed, list unchanged)
                Input.Key("Enter", 50, io)
                if !env.Wait(CraftTask.SettleMs, ctx)
                    return false
                card := this._FindCard(plan, p, &read)
                if IsObject(card)
                    break
            }
            if !IsObject(card) {
                shot := HasMethod(io, "Shot") ? io.Shot() : ""
                if (shot != "")
                    env.Log("craft: screen at the cauldron search saved to " shot)
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
            for id in ["cauldron_open_recipe", "cauldron_add_all"] {
                if (r < 1)
                    break
                if !IsObject(p[id]) {           ; "Open Recipe" did not read and is not recorded
                    env.Log("craft: " id " not clicked: it was not found on screen and is not calibrated")
                    r := 0
                    break
                }
                r := this._CauldronClick(ctx, gui, p[id], id)
            }
            if (r < 0)
                return false
            if (r = 0) {
                lines.Push("cauldron: " plan.target " found, but Stella's Workshop went away (or a purchase prompt came up): stopped before Add All was confirmed")
                return Input.ResetToSpawn(ctx, io)
            }
            ; Add All clicked: Craft (just in case auto craft did not), then
            ; the close as before. A Craft button not found never fails the
            ; trip: a screen of the open recipe is saved for the next look.
            done := "Open Recipe and Add All", why := ""
            cpt := this._CraftPoint(p)
            if IsObject(cpt) {
                r := this._CauldronClick(ctx, gui, cpt, "the Craft button")
                if (r < 0)
                    return false
                if r
                    done := "Open Recipe, Add All and Craft"
                else
                    why := "; Craft not clicked (Stella's Workshop went away or a purchase prompt came up)"
            } else {
                shot := HasMethod(io, "Shot") ? io.Shot() : ""
                env.Log("craft: the Craft button was not found on screen (and is not calibrated): not clicked")
                if (shot != "")
                    env.Log("craft: screen of the open recipe saved to " shot)
                why := "; Craft button not found" (shot != "" ? " (screen saved)" : "")
            }
            if (this._CauldronClick(ctx, gui, p["cauldron_close"], "cauldron_close") < 0)
                return false
            lines.Push("cauldron: opened (Stella's Workshop seen), " plan.target " found, clicked " done " (contents not verified)" why)
        } else {
            msg := "cauldron GUI did not open after " CraftTask.GuiTries " tries (Stella's dialog?); nothing crafted"
            shot := HasMethod(io, "Shot") ? io.Shot() : ""
            if (shot != "")
                env.Log("craft: screen where the cauldron did not open saved to " shot)
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

; The ctx a walk into the portal is played with (CraftTask._WatchCtx): each
; ShouldStop (Input.Wait asks it every slice) also looks for the black
; teleport frame until it is seen once (.dark); it stops as ctx does.
class CraftPortalWatch {
    __New(ctx, darkFn) {
        this._ctx := ctx
        this._darkFn := darkFn
        this.dark := false
    }
    ShouldStop() {
        if !this.dark
            this.dark := (this._darkFn)() ? true : false
        return IsObject(this._ctx) && this._ctx.ShouldStop()
    }
    IsHalted() => CleanupCtx.Halted(this._ctx)
    Stop() => (IsObject(this._ctx) && HasMethod(this._ctx, "Stop")) ? this._ctx.Stop() : ""
    Pause() => (IsObject(this._ctx) && HasMethod(this._ctx, "Pause")) ? this._ctx.Pause() : ""
}
