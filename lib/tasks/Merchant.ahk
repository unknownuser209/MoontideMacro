#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\TaskEnv.ahk
#Include %A_LineFile%\..\..\GameLists.ahk
; ---------------------------------------------------------------------------
; MerchantTask: visit Mari / Jester and buy their want-list (spec 4.5).
;
;   t := MerchantTask(deps)   deps as TaskEnv (cfg, webhook, log, io, cal, pixel, now)
;   t.name = "merchant", t.priority = 3   (Scheduler task contract)
;   t.Notify(name)        "Mari" | "Jester" arrived (queues a visit). The same
;                         merchant is ignored while already queued or within
;                         MerchantTask.DedupeSec (120 s) of the last notice (sliding: each notice
;                         restarts the window), so
;                         the log and the chat can both report one arrival.
;   t.OnLogEvent(ev)      feed LogWatch events: type "merchant" AND live=true
;                         queue a visit; everything else is ignored.
;   t.CanRun(state)       true when a visit is pending (and merchant.enabled,
;                         default 1). Scheduler blocks it during rare biomes.
;   t.Run(ctx)            serves each pending merchant; -> visits made.
;
; VISIT (per merchant)
;   Want-list = cfg.Data("merchants")[name]: Array of items, each
;     {"name": "Lucky Potion", "qty": 3}  or a bare string (qty 1). The item
;     is found BY NAME in the shop's tab row (what Mari sells changes every
;     visit); old "x"/"y" fields are ignored. qty is clamped to 1..MaxQty and
;     to the "Stock Left" the shop shows. Empty want-list -> no walk, one
;     webhook "arrived, nothing wanted".
;   Preflight (nothing pressed or clicked unless all pass): the inventory
;     steps (inv_open, inv_items_tab, inv_search, inv_tile1_rect, inv_use,
;     inv_desc_rect, the same ones the potions use). No walking routes:
;     merchant.teleporter=1 (default) uses the Merchant Teleporter item; 0 =
;     merchants are not visited. The dialog and shop positions are fixed
;     (MerchantTask.Layout, read from a clip of Mari's shop at 2560x1440), so
;     there is nothing to calibrate while the merchant is there.
;   TELEPORT: open the inventory, Items tab, search "Teleporter" (Roblox
;     drops typed letters now and then: when the first tile does not read
;     "teleporter" the search is cleared and typed again, SearchTries in all),
;     the first tile's name must read "...teleporter" (OCR), select it, the
;     description must then read "teleport" or "merchant" (proof that the
;     teleporter, never a potion, is selected) -> Use -> close the inventory.
;     Any check failing: inventory closed, nothing used, errors webhook.
;     No blind clicks (live 2026-11-02): every inventory click only while
;     its tabs read and no Roblox purchase prompt is up (TaskEnv.Unsafe); a
;     prompt after Use is closed with Esc and the visit dropped. The shop's
;     X likewise only while its title reads.
;   teleport -> press E -> the dialog must show the merchant's name (OCR;
;     not within DialogMs -> E again, DialogTries presses in all: one E right
;     after the teleport can land before her prompt is there)
;     -> her line types out slowly ("Click to skip"); her buttons (Open /
;     Who are you? / Leave) only appear when it is done (clip 2026-10-26: name
;     at 6 s, buttons at 11 s): click the dialog to skip, wait until "Open"
;     reads on its button (ButtonMs, one more skip click halfway)
;     -> click Open -> the "<Name>'s Shop" title must show (else abort +
;     errors webhook) -> per item: read the 5 tabs, click the one with the
;     item's name and exactly its tier (I / II / III: MerchantTask.Tier; not
;     there: "not sold this visit"), the item title must
;     then name it, read "Stock Left" (0: sold out), type the amount into
;     the box, click Purchase, look for the "You purchased ..." notice ->
;     close the shop (X) -> her dialog is LEFT (Leave, checked: a respawn with
;     her dialog open keeps it on screen) -> ResetToSpawn. One `merchant`
;     webhook lists what was bought (confirmed by the notice or not).
; ---------------------------------------------------------------------------

class MerchantTask {
    static DedupeSec := 120
    static MaxQty := 50
    static OpenKey := "e"
    static SettleMs := 300
    static ShopOpenMs := 1200
    static Order := ["Mari", "Jester"]

    name := "merchant"
    priority := 3

    __New(deps := "") {
        this._env := TaskEnv(deps)
        this._pending := Map()       ; name -> true
        this._noticed := Map()       ; name -> ms of last accepted notice
        this._last := ""             ; last OCR text read by _See (for messages)
        this._noMerchant := false    ; the teleporter said no merchant has spawned
        this._used := false          ; Use was clicked this visit (the character may have moved)
    }

    Notify(name) {
        if !(name = "Mari" || name = "Jester")
            return false
        now := this._env.Now()
        ; Sliding window: every notice (accepted or not) restarts the
        ; DedupeSec window, so a repeating source cannot queue extra trips.
        suppressed := this._pending.Has(name)
            || (this._noticed.Has(name) && now - this._noticed[name] < MerchantTask.DedupeSec * 1000)
        this._noticed[name] := now
        if suppressed
            return false
        this._pending[name] := true
        this._env.Log("merchant: " name " queued")
        return true
    }

    OnLogEvent(ev) {
        try {
            if (ev["type"] = "merchant" && ev["live"])
                return this.Notify(ev["name"])
        }
        return false
    }

    Pending() => this._pending.Count

    ; App.Start: merchants announced before a Stop are gone by now
    Reset() {
        this._pending := Map()
    }

    CanRun(state) {
        env := this._env
        if (this._pending.Count = 0)
            return false
        return IsObject(env.cfg) ? (env.cfg.Get("merchant.enabled", 1) ? true : false) : true
    }

    Run(ctx) {
        visits := 0
        for name in MerchantTask.Order {
            if !this._pending.Has(name)
                continue
            if ctx.ShouldStop()
                break
            this._pending.Delete(name)          ; cleared first: a failure never loops
            if this._Visit(name, ctx)
                visits++
        }
        return visits
    }

    ; Dialog and shop layout, 2560x1440 screen px, read from a clip of Mari's
    ; shop (2026-10-26) and checked on a clip of Jester's (same day: every
    ; box below reads the same; he has a fourth button, Exchange, between
    ; Open and Who are you?, never clicked). The game font draws "a" like
    ; "o", "k" like "I<" and "g" like "o", so text checks go through
    ; MerchantTask.Norm and the small Slack. Checked with Windows OCR on the
    ; clips' frames: names "Mori" / "Jester", tabs ("Rune of Everythino");
    ; the title and "Stock Left" only read at scale 2 ("Mori's Shop",
    ; "Stock Left: IO" = 10); Jester's Leave reads "Leuve".
    static Layout := {
        ; "Mari" above her line. Read at NameScale (2): at 1x her name never
        ; read on the clips' frames, day or night (tests\screens)
        dialogName: {x: 960, y: 912, w: 520, h: 75},
        ; her whole dialog and its buttons: "Click to skip" reads in every
        ; light, so "is her dialog up?" never depends on one word (DialogUp)
        dialogArea: {x: 680, y: 900, w: 1200, h: 420},
        skip: {x: 1308, y: 1073},                        ; her dialog body ("Click to skip")
        leave: {x: 1690, y: 1258},                       ; her Leave button (clip 2026-10-26)
        open: {x: 868, y: 1258},                          ; Open | Who are you? | Leave
        title: {x: 1600, y: 445, w: 384, h: 35},          ; "Mari's Shop"
        close: {x: 2413, y: 462},                         ; X
        tabs: [{x: 1165, y: 932, w: 241, h: 56}, {x: 1418, y: 932, w: 241, h: 56}
            , {x: 1672, y: 932, w: 241, h: 56}, {x: 1925, y: 932, w: 241, h: 56}
            , {x: 2179, y: 932, w: 241, h: 56}],
        item: {x: 1472, y: 497, w: 947, h: 41},           ; "Lucky Potion | Common"
        stock: {x: 1193, y: 742, w: 236, h: 31},          ; "Stock Left: 10"
        qty: {x: 1402, y: 817},                           ; amount box
        buy: {x: 1572, y: 881},                           ; Purchase for (N Coins)
        notice: {x: 896, y: 1203, w: 768, h: 45}          ; "You purchased 10 Lucky Potions"
    }
    static NameRe := Map("Mari", "i)m[ao]r[il1]", "Jester", "i)j[ae]st[ae]r")
    static SeeMs := 3000          ; dialog / shop wait
    static DialogTries := 3       ; E presses for the merchant's dialog
    static DialogMs := 1600       ; wait for her name after each E
    static AfterTeleMs := 400     ; after the inventory closed, before the first E
    static ButtonMs := 8000       ; her line types out for ~5 s before the buttons show
    static ButtonBox := {dx: -150, dy: -35, w: 300, h: 70}    ; OCR box around a button point
    static LeaveTries := 3
    static LeaveRe := "i)le[aou]ve"   ; "Leave" / "Leuve" (Jester's)
    static OpenRe := "i)\b[o0]pen\b"
    static NameScale := 2
    static LeaveScale := 2            ; "L enve" at 1x by day
    static DialogUpRe := "i)t[o0]\s*skip|wh[o0]\s*[ao]re\s*y[o0]u|le[aou]ve"
    static PollMs := 200
    static NoticeMs := 2000       ; "You purchased" wait
    static QtyClear := 4          ; Backspaces in the amount box
    static SmallScale := 2        ; OCR scale for the title and the stock line
    ; her shop's title "<Name>'s Shop": live 2026-11-10 it read 'Mori's sho'
    ; (the p cut off), the X was not clicked and the shop stayed open; 06:53
    ; 'Mori's stin': any "<name>'s s..." in the title box is her shop; 07:32
    ; 'Mori•s$hop': "hop" alone too
    static ShopRe := "i)h[ao0]p|sh[ao0]|(?:'|\b)s\s*s[a-z]"   ; live misreads: 'Mori's sho', 'Mori's stin', 'Morl s stib' (apostrophe lost)

    ; Letters only, lower case, with the game font's look-alikes folded
    ; ("I<" as "k", "o" as "a", l/1/| as "i"), so OCR text and item names
    ; compare ("LucI<Y Potion" = "Lucky Potion").
    static Norm(s) => GameLists.Fold(s)

    ; Letters a misread may cost on a folded name ("Everythino" = everything).
    static Slack(want) => StrLen(want) >= 14 ? 2 : StrLen(want) >= 8 ? 1 : 0

    ; OCR of Layout.dialogArea -> her dialog is on screen (her name, "Click
    ; to skip", "Who are you?" or Leave). Never "gone" on one missed word.
    static DialogUp(text, name) {
        t := String(text)
        return (MerchantTask.NameRe.Has(name) && RegExMatch(t, MerchantTask.NameRe[name])) || RegExMatch(t, MerchantTask.DialogUpRe) > 0
    }

    ; Text -> {name, tier, cut}: the folded name before its roman numeral,
    ; the numeral's value (I = 1, II = 2, III = 3; 0 = none) and whether a
    ; numeral or separator was found. 2026-10-27 review: folded whole, the
    ; tiers ran together ("fartunespaidii" contains "fartunespaidi", III is
    ; one letter from II, and the title's "|" folds to "i"), so a shop with
    ; only one tier sold it for another. Words are split first: the numeral
    ; is the run of words that fold to only "i" (I, l, 1, |) after the name.
    ; In an item title ("Fortune Spoid II | Rare") the run also holds the
    ; separator: a real "|" ends the numeral; read as "I" ("Stronge Potion I
    ; I Uncommon" on the jester_shop frame) it is the run's last word when
    ; the rarity follows.
    static Tier(text) {
        words := []
        for w in StrSplit(StrReplace(String(text), "|", " | "), [" ", "`t", "`r", "`n"])
            if (GameLists.Fold(w) != "")
                words.Push(w)
        k := 0
        for i, w in words {
            if (i > 1 && RegExMatch(GameLists.Fold(w), "^i+$")) {
                k := i
                break
            }
        }
        if !k {
            base := ""
            for w in words
                base .= GameLists.Fold(w)
            return {name: base, tier: 0, cut: false}
        }
        j := k
        while (j <= words.Length && RegExMatch(GameLists.Fold(words[j]), "^i+$"))
            j++
        last := j - 1                           ; the run is words[k..j-1]
        if (j <= words.Length) {                ; the rarity follows: drop the separator
            last := j - 2
            Loop j - k
                if (words[k + A_Index - 1] = "|") {
                    last := k + A_Index - 2
                    break
                }
        }
        tier := 0
        Loop last - k + 1
            tier += StrLen(GameLists.Fold(words[k + A_Index - 1]))
        base := ""
        Loop k - 1
            base .= GameLists.Fold(words[A_Index])
        return {name: base, tier: tier, cut: true}
    }

    ; Tab texts -> index of the tab that names `item`, or 0. The tier
    ; (MerchantTask.Tier) must be the same; then the exact name first, else
    ; the one tab within Slack letters of it (no other tab as close).
    static FindTab(texts, item) {
        want := MerchantTask.Tier(item)
        if (want.name = "")
            return 0
        tabs := []
        for i, t in texts {
            tabs.Push(MerchantTask.Tier(t))
            if (tabs[i].tier = want.tier && tabs[i].name == want.name)
                return i
        }
        best := 0, bestD := MerchantTask.Slack(want.name) + 1, ties := 0
        for i, n in tabs {
            if (n.tier != want.tier)
                continue
            d := GameLists.Distance(n.name, want.name)
            if (d < bestD)
                best := i, bestD := d, ties := 0
            else if (d = bestD)
                ties++
        }
        return ties ? 0 : best
    }

    ; The item title ("Rune of Everythino | Mythic") names `item`: the same
    ; tier and the name within Slack letters. A title whose numeral and
    ; separator were both lost only names an item without a tier.
    static TitleNames(title, item) {
        want := MerchantTask.Tier(item)
        n := MerchantTask.Tier(title)
        if (want.name = "" || n.name = "")
            return false
        if !n.cut
            return want.tier = 0 && GameLists.Distance(SubStr(n.name, 1, StrLen(want.name)), want.name) <= MerchantTask.Slack(want.name)
        return n.tier = want.tier && GameLists.Distance(n.name, want.name) <= MerchantTask.Slack(want.name)
    }

    ; "Stock Left: 10" -> 10, or "" when unreadable. The font's 1 and 0 read
    ; as I and O ("Stock Left: IO").
    static Stock(text) {
        if !RegExMatch(String(text), "i)left\W*([0-9oOiIl|]+)", &m)
            return ""
        d := RegExReplace(RegExReplace(m[1], "[oO]", "0"), "[iIl|]", "1")
        return Integer(d)
    }

    ; OCR of rect r; scale > 1 only when the OCR function takes a scale.
    _Ocr(r, scale := 1) {
        f := this._env.ocrFn
        try {
            if (scale != 1 && (f.MaxParams >= 5 || f.IsVariadic))
                return String(f.Call(r.x, r.y, r.w, r.h, scale))
            return String(f.Call(r.x, r.y, r.w, r.h))
        } catch {
            return ""
        }
    }

    ; -> true if the merchant was actually visited.
    _Visit(name, ctx) {
        env := this._env
        wants := this._WantList(name)
        if (wants.Length = 0) {
            env.Log("merchant: " name " arrived, want-list empty: not visiting")
            env.Report("merchant", name " arrived", "Want-list is empty, not visiting.")
            return false
        }
        if (IsObject(env.cfg) && !env.cfg.Get("merchant.teleporter", 1)) {
            env.Log("merchant: " name " arrived; the Merchant Teleporter is off (merchant.teleporter=0): not visiting")
            return false
        }
        cal := this._InvCal()
        if !IsObject(cal)
            return false

        L := MerchantTask.Layout
        io := env.io
        bought := []
        this._noMerchant := false
        this._used := false
        this._lastName := name
        try {
            if !this._Teleport(cal, ctx) {
                if this._noMerchant {
                    ; an event merchant's arrival line, or she already left:
                    ; nothing to walk to, nothing moved, no reset needed
                    env.Log("merchant: " name " was announced, but the teleporter says no merchant has spawned (event merchants do not count): not visiting")
                    env.Report("merchant", name " announced", "The Merchant Teleporter says no merchant has spawned (event merchants do not count). Not visiting.")
                }
                return false
            }
            seen := this._OpenDialog(name, ctx)
            if (seen < 0)
                return false
            if !seen
                return this._ShopFail(name, name "'s dialog did not open after E (read: '" this._last "'): nothing bought")
            ready := this._WaitOpen(ctx)
            if (ready < 0)
                return false
            if !ready
                return this._ShopFail(name, name "'s Open button never showed (read: '" this._last "'): nothing bought")
            env.Click(L.open)
            seen := this._See(L.title, MerchantTask.ShopRe, ctx, MerchantTask.SmallScale)
            if (seen < 0)
                return false
            if !seen
                return this._ShopFail(name, name "'s shop did not open after Open (read: '" this._last "'): nothing bought")
            for item in wants {
                if ctx.ShouldStop()
                    break
                line := this._Buy(name, item, ctx)
                if (line != "")
                    bought.Push(line)
            }
            ; X only while the shop's title reads: a click on an empty spot
            ; can go through into the world (live 2026-11-02). Halted (F3,
            ; pause, Roblox gone): nothing more is sent.
            if !CleanupCtx.Halted(ctx) {
                why := env.Unsafe("merchant")
                if (why = "" && this._See(L.title, MerchantTask.ShopRe, ctx, MerchantTask.SmallScale, 0) < 1)
                    why := name "'s shop is not open (title read: '" this._last "')"
                if (why = "") {
                    env.Click(L.close)
                    env.Wait(MerchantTask.SettleMs, ctx)
                    env.BuyPrompt("merchant")
                } else
                    env.Log("merchant: X not clicked: " why)
            }
        } finally {
            if (!ctx.ShouldStop() && !this._noMerchant) {
                ; the teleporter was never used (none owned, a misread tile):
                ; nothing moved, so no dialog to leave and no respawn, which
                ; would drag the character off the fishing spot
                if !this._used {
                } else if !this._LeaveDialog(name, ctx)
                    this._ShopFail(name, name "'s dialog is still open after Leave; not resetting (close it, then press F2)")
                else
                    Input.ResetToSpawn(ctx, io)
            } else
                this._CloseOnPreempt(name, ctx, cal)
        }
        desc := ""
        for line in bought
            desc .= (desc = "" ? "" : "`n") "- " line
        env.Report("merchant", name " visited", desc != "" ? desc : "Nothing bought.")
        return true
    }

    ; Told to stop part way. A preempt (a higher task is due; not F3 / pause
    ; / Roblox gone) used to return with the inventory, her shop or her
    ; dialog still open over the next task: each is closed first, only when
    ; it reads (CleanupCtx). No respawn: the next task starts its own way.
    _CloseOnPreempt(name, ctx, cal) {
        if (!ctx.ShouldStop() || CleanupCtx.Halted(ctx))
            return
        env := this._env
        cc := CleanupCtx(ctx)
        if (IsObject(cal) && Screen.WithMode("C", () => env.InvOpen(cal.inv_items_tab))) {
            env.Log("merchant: preempted with the inventory open: closing it first")
            Screen.WithMode("C", () => env.CloseInv(cal.inv_open, cal.inv_items_tab, cc))
        }
        if this._ShopUp() {
            env.Log("merchant: preempted in " name "'s shop: closing it first")
            if (this._CloseShop(cc) < 0)
                return
        }
        if this._DialogStillUp(name) {
            env.Log("merchant: preempted with " name "'s dialog open: Leave first")
            this._LeaveDialog(name, cc)
        }
    }

    ; The "<Name>'s Shop" title reads right now (one read).
    _ShopUp() {
        t := this._Ocr(MerchantTask.Layout.title, MerchantTask.SmallScale)
        this._last := SubStr(RegExReplace(t, "\s+", " "), 1, 60)
        return RegExMatch(t, MerchantTask.ShopRe) > 0
    }

    ; Her shop's X, only while its title reads and no purchase prompt is up.
    ; -> 1 clicked | 0 not open | 2 refused (logged) | -1 stopped
    _CloseShop(ctx) {
        env := this._env
        if !this._ShopUp()
            return 0
        if ((why := env.Unsafe("merchant")) != "") {
            env.Log("merchant: X not clicked: " why)
            return 2
        }
        env.Click(MerchantTask.Layout.close)
        if !env.Wait(MerchantTask.SettleMs, ctx)
            return -1
        env.BuyPrompt("merchant")
        return 1
    }

    ; The App's between-tasks check (Tidy): her shop (X) and her dialog
    ; (Leave), each only while it reads.
    Leftovers() {
        name := this.HasOwnProp("_lastName") ? this._lastName : "Mari"
        shop := {up: () => this._ShopUp() ? "merchant shop" : ""
            , close: (label, ctx) => this._CloseShop(ctx)}
        dialog := {up: () => this._DialogStillUp(name) ? "merchant dialog" : ""
            , close: (label, ctx) => this._LeaveDialog(name, ctx) ? 1 : (ctx.ShouldStop() ? -1 : 2)}
        return [shop, dialog]
    }

    ; Her line types out before her buttons show: click the dialog to skip,
    ; then wait until "Open" reads on its button (one more skip halfway).
    ; -> 1 | 0 | -1 stopped
    _WaitOpen(ctx) {
        env := this._env
        L := MerchantTask.Layout
        waited := 0, skips := 0
        Loop {
            if this._ButtonReads(L.open, MerchantTask.OpenRe)
                return 1
            if ((skips = 0) || (skips = 1 && waited >= MerchantTask.ButtonMs // 2)) {
                skips++
                env.Click(L.skip)
            }
            if (waited >= MerchantTask.ButtonMs)
                return 0
            if !env.Wait(MerchantTask.PollMs, ctx)
                return -1
            waited += MerchantTask.PollMs
        }
    }

    _ButtonReads(pt, re, scale := 1) {
        b := MerchantTask.ButtonBox
        t := this._Ocr({x: pt.x + b.dx, y: pt.y + b.dy, w: b.w, h: b.h}, scale)
        this._last := SubStr(RegExReplace(t, "\s+", " "), 1, 60)
        return RegExMatch(t, re) > 0
    }

    ; Her dialog gone? While her Leave button or her name still read, click
    ; Leave. -> true gone, false still up or stopped.
    _LeaveDialog(name, ctx) {
        env := this._env
        L := MerchantTask.Layout
        Loop MerchantTask.LeaveTries {
            up := this._DialogStillUp(name)
            if !up
                return true
            env.Log("merchant: " name "'s dialog is still open: Leave")
            env.Click(L.leave)
            if !env.Wait(MerchantTask.SettleMs, ctx)
                return false
        }
        return !this._DialogStillUp(name)
    }

    _DialogStillUp(name) {
        if this._ButtonReads(MerchantTask.Layout.leave, MerchantTask.LeaveRe, MerchantTask.LeaveScale)
            return true
        t := this._Ocr(MerchantTask.Layout.dialogArea, 1)
        this._last := SubStr(RegExReplace(t, "\s+", " "), 1, 60)
        return MerchantTask.DialogUp(t, name)
    }

    ; E until the dialog names the merchant. -> 1 | 0 | -1 stopped
    _OpenDialog(name, ctx) {
        env := this._env
        if !env.Wait(MerchantTask.AfterTeleMs, ctx)
            return -1
        Loop MerchantTask.DialogTries {
            if ctx.ShouldStop()
                return -1
            Input.Key(MerchantTask.OpenKey, 80, env.io)
            seen := this._See(MerchantTask.Layout.dialogName, MerchantTask.NameRe[name], ctx, MerchantTask.NameScale, MerchantTask.DialogMs)
            if (seen != 0)
                return seen
            if (A_Index < MerchantTask.DialogTries)
                env.Log("merchant: " name "'s dialog not open after E (try " A_Index "/" MerchantTask.DialogTries "): E again")
        }
        return 0
    }

    _ShopFail(name, msg) {
        env := this._env
        env.Log("merchant: " msg)
        env.Report("errors", "Merchant visit failed", msg, 0xE74C3C)
        return false
    }

    ; Polls OCR of rect r until it matches re. -> 1 seen | 0 not in time | -1 stopped
    _See(r, re, ctx, scale := 1, ms := "") {
        env := this._env
        ms := (ms = "") ? MerchantTask.SeeMs : ms
        waited := 0
        Loop {
            t := this._Ocr(r, scale)
            this._last := SubStr(RegExReplace(t, "\s+", " "), 1, 60)
            if RegExMatch(t, re)
                return 1
            if (waited >= ms)
                return 0
            if !env.Wait(MerchantTask.PollMs, ctx)
                return -1
            waited += MerchantTask.PollMs
        }
    }

    static TeleporterName := "Merchant Teleporter"
    static TeleporterSearch := "Teleporter"   ; short: fewer letters to drop
    static SearchTries := 3
    static InvMs := 450          ; after opening the inventory / switching tab
    static SearchMs := 450       ; after typing the search
    static SelectMs := 350       ; after selecting the tile
    static TeleportMs := 3000    ; after Use, before talking to the merchant
    ; "There's no merchant spawned. (Event merchant is not counted)": the
    ; game's warning when Use finds no merchant, bottom right where the toasts
    ; show (clip 2026-10-27 20:36: after a "Mari has arrived" chat line)
    static NoMerchantBox := {x: 1980, y: 1080, w: 580, h: 170}
    static NoMerchantRe := "i)n[o0]\s*merc\s*h[ao]n[ft]"

    ; The inventory calibration points / rects, or "" (each missing one is
    ; logged once by env).
    _InvCal() {
        env := this._env
        c := {}
        ok := true
        for id in ["inv_open", "inv_items_tab", "inv_search", "inv_use"] {
            p := env.Point(id)
            ok := ok && (p != "")
            c.%id% := p
        }
        for id in ["inv_tile1_rect", "inv_desc_rect"] {
            r := env.Rect(id)
            ok := ok && (r != "")
            c.%id% := r
        }
        return ok ? c : ""
    }

    _Read(r) => StrLower(String((this._env.ocrFn)(r.x, r.y, r.w, r.h)))

    ; Right before an inventory click: TaskEnv.Unsafe (a purchase prompt, or
    ; the inventory's tabs do not read). -> why the click is refused, or "".
    _Unsafe(c) => this._env.Unsafe("merchant", c.inv_items_tab)

    ; The tile names the teleporter, game font look-alikes folded ("Teleparter").
    static IsTeleporter(text) => InStr(GameLists.Fold(text), GameLists.Fold("teleporter")) > 0

    ; Inventory not used: log + errors webhook, close it (checked). -> false
    _TeleFail(c, why) {
        env := this._env
        env.Log("merchant: teleporter not used: " why)
        env.Report("errors", "Merchant teleporter not used", why, 0xE74C3C)
        env.CloseInv(c.inv_open, c.inv_items_tab)
        return false
    }

    ; Uses the Merchant Teleporter from the inventory with proof that it is
    ; the selected item (module header). -> true when Use was clicked.
    ; the inventory scales evenly, centred (16:10): mode "C" around it
    _Teleport(c, ctx) {
        old := Screen.Mode
        Screen.Mode := "C"
        try
            return this._TeleportM(c, ctx)
        finally
            Screen.Mode := old
    }

    _TeleportM(c, ctx) {
        env := this._env
        io := env.io
        ; no blind clicks (live 2026-11-02: a click on an empty spot went
        ; through into the world): the inventory button only while its tabs
        ; do not read, every later click only while they do (_Unsafe)
        if !env.InvOpen(c.inv_items_tab) {
            if ((why := env.Unsafe("merchant")) != "")
                return this._TeleFail(c, why)
            env.Click(c.inv_open)
            if !env.Wait(MerchantTask.InvMs, ctx)
                return false
        }
        if ((why := this._Unsafe(c)) != "")
            return this._TeleFail(c, why)
        env.Click(c.inv_items_tab)
        if !env.Wait(MerchantTask.InvMs, ctx)
            return false
        t := c.inv_tile1_rect
        found := false
        Loop MerchantTask.SearchTries {
            if ctx.ShouldStop()
                return false
            if ((why := this._Unsafe(c)) != "")
                return this._TeleFail(c, why)
            env.Click(c.inv_search)
            Input.ClearText(io)
            Input.TypeText(MerchantTask.TeleporterSearch, io)
            if !env.Wait(MerchantTask.SearchMs, ctx)
                return false
            if MerchantTask.IsTeleporter(this._Read(t)) {
                found := true
                break
            }
            if (A_Index < MerchantTask.SearchTries)
                env.Log("merchant: no teleporter tile after typing the search (a letter may have been dropped): typing it again")
        }
        if !found
            return this._TeleFail(c, "no 'Merchant Teleporter' tile after searching " MerchantTask.SearchTries " times (do you own one?)")
        if ((why := this._Unsafe(c)) != "")
            return this._TeleFail(c, why)
        env.Click({x: t.x + t.w // 2, y: t.y + t.h // 2})
        if !env.Wait(MerchantTask.SelectMs, ctx)
            return false
        d := this._Read(c.inv_desc_rect)
        if !(InStr(d, "teleport") || InStr(d, "merchant"))
            return this._TeleFail(c, "the selected item's description does not mention teleport/merchant; Use not clicked")
        if !MerchantTask.IsTeleporter(this._Read(t))
            return this._TeleFail(c, "the first tile changed before Use; Use not clicked")
        if ctx.ShouldStop()
            return false
        if ((why := this._Unsafe(c)) != "")
            return this._TeleFail(c, why)
        env.Click(c.inv_use)
        this._used := true
        env.Log("merchant: used the Merchant Teleporter")
        none := this._WaitNoMerchant(ctx)
        if (none < 0)
            return false
        if env.BuyPrompt("merchant") {          ; Use went through into the world: closed (Esc), no visit
            env.CloseInv(c.inv_open, c.inv_items_tab, ctx)
            return false
        }
        this._noMerchant := none > 0
        if !env.CloseInv(c.inv_open, c.inv_items_tab, ctx)       ; close the inventory (checked)
            env.Report("errors", "Inventory left open", "the inventory did not close after the Merchant Teleporter", 0xE74C3C)
        return !ctx.ShouldStop() && !this._noMerchant
    }

    ; Waits TeleportMs after Use, watching for the game's "no merchant
    ; spawned" warning. -> 1 warning seen (stops waiting) | 0 | -1 stopped
    _WaitNoMerchant(ctx) {
        env := this._env
        b := MerchantTask.NoMerchantBox
        waited := 0
        Loop {
            if RegExMatch((env.ocrFn)(b.x, b.y, b.w, b.h), MerchantTask.NoMerchantRe)
                return 1
            if (waited >= MerchantTask.TeleportMs)
                return 0
            if !env.Wait(MerchantTask.PollMs, ctx)
                return -1
            waited += MerchantTask.PollMs
        }
    }

    ; One want-list item in the open shop. -> report line, or "" (bad entry).
    _Buy(who, item, ctx) {
        env := this._env
        L := MerchantTask.Layout
        spec := MerchantTask.ParseItem(item)
        if (spec == "") {
            env.Log("merchant: bad want-list entry skipped")
            return ""
        }
        texts := []
        for r in L.tabs
            texts.Push(this._Ocr(r))
        i := MerchantTask.FindTab(texts, spec.name)
        if !i {
            env.Log("merchant: " spec.name " is not in " who "'s shop this visit")
            return spec.name ": not sold this visit"
        }
        tab := L.tabs[i]
        env.Click({x: tab.x + tab.w // 2, y: tab.y + tab.h // 2})
        if !env.Wait(MerchantTask.SettleMs, ctx)
            return ""
        title := this._Ocr(L.item)
        if !MerchantTask.TitleNames(title, spec.name) {
            env.Log("merchant: picked the " spec.name " tab but the shop shows '" SubStr(title, 1, 40) "': skipped")
            return spec.name ": tab did not open it, skipped"
        }
        qty := spec.qty
        stock := MerchantTask.Stock(this._Ocr(L.stock, MerchantTask.SmallScale))
        if (stock != "") {
            if (stock = 0)
                return spec.name ": sold out"
            qty := Min(qty, stock)
        }
        env.Click(L.qty)
        Input.Key("End", 30, env.io)
        Loop MerchantTask.QtyClear
            Input.Key("Backspace", 30, env.io)
        Input.TypeText(String(qty), env.io)
        if !env.Wait(MerchantTask.SettleMs, ctx) || ctx.ShouldStop()
            return ""
        env.Click(L.buy)
        waited := 0
        Loop {
            if RegExMatch(this._Ocr(L.notice), "i)purch[ao]sed")
                return "bought " qty " " spec.name
            if (waited >= MerchantTask.NoticeMs || !env.Wait(MerchantTask.PollMs, ctx))
                break
            waited += MerchantTask.PollMs
        }
        return "Purchase clicked for " qty " " spec.name " (no 'You purchased' notice seen)"
    }

    ; -> {name, qty} or "".
    static ParseItem(item) {
        if (Type(item) = "String")
            return item = "" ? "" : {name: item, qty: 1}
        if !(item is Map && item.Has("name"))
            return ""
        qty := item.Has("qty") && IsInteger(item["qty"]) ? item["qty"] : 1
        qty := Max(1, Min(Integer(qty), MerchantTask.MaxQty))
        return {name: String(item["name"]), qty: qty}
    }

    _WantList(name) {
        env := this._env
        if !IsObject(env.cfg)
            return []
        d := env.cfg.Data("merchants")
        return (d is Map && d.Has(name) && d[name] is Array) ? d[name] : []
    }
}
