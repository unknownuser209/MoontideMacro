#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\TaskEnv.ahk
#Include %A_LineFile%\..\..\Biomes.ahk
#Include %A_LineFile%\..\..\GameLists.ahk
#Include %A_LineFile%\..\..\PotionSafety.ahk
#Include %A_LineFile%\..\..\QuestMatch.ahk
#Include %A_LineFile%\..\..\Plugins.ahk
; ---------------------------------------------------------------------------
; BiomeItemsTask: uses the biome-changing items from the inventory when their
; cooldowns allow: Biome Randomizer, Strange Controller, Biome Selector.
;
;   t := BiomeItemsTask(deps)   deps as TaskEnv (cfg, webhook, log, io, cal, ocr, now),
;                               plus clock (-> YYYYMMDDHHMMSS, A_Now) and
;                               statePath (data\biome_items_state.json)
;   t.name = "biomeitems", t.priority = 5   (Scheduler task contract; it is
;   before "quests" in App.Order, so it wins the tie)
;   t.CanRun(state)  -> BiomeItems.enabled AND the current biome is listed
;                       in data\biomes.json, is a normal biome
;                       (Biomes.IsNormal: never an event or new one) and is
;                       NOT one the user marked rare (data\biomes.json "rare";
;                       a rare biome is never changed away) AND
;                       ServerCdMin passed since the last use of ANY of them
;                       (the game's 20 min server cooldown) AND the inventory
;                       steps are calibrated AND one enabled item is off its
;                       own cooldown and not held (missing / refused).
;   t.Run(ctx)       -> 1 when Use was clicked, else 0.
;
; ITEMS (Sol's RNG wiki / guides, 2026): reusable, used with the inventory's
; Use button. Cooldowns are the game's, plus CdMarginSec.
;   Biome Randomizer     35 min   (the crafted one)
;   Strange Controller   20 min
;   Biome Selector       60 min   Use opens the BIOME SELECTOR list of 9
;                                 Drives. The Drive picked in settings
;                                 (BiomeItems.selectorDrive) is FOUND by
;                                 reading the list (selector_list_rect) in
;                                 horizontal strips: the window bobs slowly
;                                 up and down, so no fixed point is used.
;                                 The strip is read again right before the
;                                 click. Not in view (Angelic Hymn is below
;                                 the fold) -> scroll the list, read again.
;                                 Its prompt must name that Drive (read in
;                                 the text's own colour, up to PromptTries
;                                 times; a name never read is ours only
;                                 when the row clicked read as ours; any
;                                 other Drive named = Cancel).
;                                 Then Confirm (selector_confirm). The window
;                                 closes itself when the biome changes (~4 s):
;                                 waited for, else closed by its X. Each use
;                                 SPENDS one Drive. Its cooldowns start at
;                                 Confirm; a Drive not read (or a preempt
;                                 before Confirm) = nothing used: the
;                                 Selector (Esc) and the inventory are
;                                 closed, the Selector is held.
; The ONE-TIME Biome Randomizer (a Season Pass item that is gone after one
; use) is NEVER used: a tile or description that says "one-time" /
; "one time" / "single use" / "consumed" / "once" (not "once every") is
; refused (Forbidden), and when the
; first search result is the one-time item (by its tile or its description)
; the second tile is checked. Its tile can read plain "Biome Randomizer",
; so the Randomizer also needs a POSITIVE match (2026-11-01: an empty, not
; yet drawn description let the one-time one through three times): its
; description must hold the reusable one's cooldown wording (mustSay), be
; at least DescMinChars long and read the same twice (DescAgainMs apart).
;
; STATE: the last-use times are saved to data\biome_items_state.json
; (git-ignored, written at runtime) as wall-clock times, so a restart keeps
; the cooldowns. A missing or broken file = nothing used yet.
;
; FLOW (nothing is clicked unless every check passes; any doubt = close the
; inventory, log, errors webhook):
;   inventory open -> Items tab -> search the name -> read tile 1 (and tile 2
;   when calibrated): the tiles whose text holds the item's word and no
;   forbidden word are selected in turn until one's description passes
;   DescIs -> the tile is read again -> Use -> (Selector: Drive,
;   Confirm) -> close the inventory if it is still open.
;   NO BLIND CLICKS (live 2026-11-02: a click that missed a panel went into
;   the world and opened Roblox's purchase prompt): before every click a
;   Roblox purchase prompt on screen is closed with Esc (TaskEnv.BuyPrompt,
;   never a click) and the item is refused; every click inside the inventory
;   needs its Gears / Items tabs read right before (TaskEnv.InvOpen), and
;   Confirm needs the Selector's list read. Its button is not clicked when
;   the inventory is open already (it toggles).
;   An item whose tile is not found, or that is refused, is held for
;   MissingRetryMin, doubled per refusal in a row up to MissingMaxMin; only
;   the first refusal sends the errors webhook (both start over on a use).
;   A try stopped by the screen (a purchase prompt, the inventory that did
;   not open, the Daily Rewards popup) says nothing about the item: held
;   ScreenRetryMin, not doubled, one webhook until a use (audit 2026-11-20: an inventory
;   lockout pushed the Selector's wait to 240 min and it was never used).
;   Of the items ready, the one used longest ago goes first (the Selector
;   only got a turn when both others were cooling down).
;
; SETTINGS [BiomeItems]: enabled 0, biomeRandomizer 0, strangeController 0,
;   biomeSelector 0, selectorDrive "" (one of BiomeItemsTask.Drives).
; Calibration: inv_open, inv_items_tab, inv_search, inv_tile1_rect, inv_use,
;   inv_desc_rect (inv_tile2_rect optional). The Selector's
;   selector_list_rect + selector_confirm need NO calibration: the Drive
;   list is found on screen by its Drives' names (_FindSelector,
;   lib\AutoCal.ahk) when they are not recorded, or when no Drive reads in
;   the recorded rect; a recorded rect a Drive reads in is used as before.
; ---------------------------------------------------------------------------

class BiomeItemsTask {
    ; mustSay: the description must match it; "" = only the Forbidden check
    ; (no one-time version of the item exists). The reusable Randomizer's
    ; real description (the user's screenshot 2026-11-09): "A Fully
    ; Functional Dimension-Manipulating device. Changes the Current Biome
    ; Regardless of Natural Spawnrate. *(Except for Rare Biomes.) Has a
    ; 1/5000 chance to spawn Cyberspace." - no cooldown wording (the old
    ; guess), so it was refused every time (21:24:35)
    static Items := [
        {key: "biomeRandomizer", name: "Biome Randomizer", word: "randomizer", cdMin: 35
            , mustSay: "i)cyber\s*space|1\s*/\s*5\s*,?\s*000|natural\s*spawn\s*rate|cool[\s\-]*down|\bevery\s+\d+\s*m|\b35\s*m"},
        {key: "strangeController", name: "Strange Controller", word: "controller", cdMin: 20, mustSay: ""},
        {key: "biomeSelector", name: "Biome Selector", word: "selector", cdMin: 60, mustSay: ""}
    ]
    ; the Biome Selector's Drives, top to bottom (first word = OCR key)
    static Drives := ["Radiant Star Drive", "Infernal Flame Drive", "Unknown Void Drive", "Corrupt Ruin Drive"
        , "Golden Dune Drive", "Chilling Frost Drive", "Abyss Curse Drive", "Raging Gale Drive", "Angelic Hymn Drive"]
    ; LIMITED (Halloween 2026, the user): ONE Cursed Rune Fragment when
    ; GRAVEYARD or PUMPKIN MOON starts (Hunting.cursedRune). The fragment
    ; starts Blood Rain and is used up, so it skips the one-time check and
    ; the server cooldown; after a use none is used again until a normal
    ; biome (the night is over): Blood Rain ending back into GRAVEYARD does
    ; not spend a second one.
    static Rune := {key: "cursedRune", name: "Cursed Rune Fragment", word: "cursed", cdMin: 0, mustSay: "", consumable: true}
    static RuneBiomes := ["GRAVEYARD", "PUMPKIN MOON"]
    static ServerCdMin := 20
    static CdMarginSec := 30
    static MissingRetryMin := 30     ; first hold; doubled per refusal in a row
    static MissingMaxMin := 240      ; longest hold
    static ScreenRetryMin := 10      ; hold after a try the screen stopped (not the item's fault)
    ; "once" counts unless it is "once every / per / each" (a cooldown text)
    static Forbidden := "i)one[\s\-]*time|single[\s\-]*use|consumed|\bonce\b(?!\s+(?:every|per|each|a\b))"
    static InvMs := 450
    static SearchMs := 450
    static SearchTries := 3          ; typed search attempts (a dropped letter finds nothing)
    static SelectMs := 500
    static DescAgainMs := 400        ; between the two description reads
    static DescMinChars := 25        ; a shorter mustSay description = not drawn yet / cut
    static UseMs := 900
    static RereadMs := 300         ; before the tile is read once more (a read mid-redraw)
    static PickMs := 800
    ; The Selector's list boots after Use (live 2026-11-21: one row at 0.3 s,
    ; all nine at 1.2 s): looked at only after this much more.
    static BootMs := 1500
    ; The Biome Selector window, as fractions of selector_list_rect (live
    ; 2026-11-21 at 2560x1440: list rect 822,515,672,416; rows 51 px apart,
    ; the first row's middle 30 below its top; the bottom bar "BIOME SELECTOR
    ; IS READY TO BE USED" 432 below the first row; its X 916 right of the
    ; list's left and 66 above the first row; the prompt's Confirm / Cancel
    ; 159 above the bar, Cancel 458 right of the list's left; the prompt's
    ; "You have selected [ Drive ]" 310-350 above the bar). The window bobs
    ; ~32 px up and down, so every place is worked out from a row or the bar
    ; read just before.
    static Geo := {pitch: 0.125, row1: 0.072, bar: 1.038, closeDx: 1.363, closeDy: -0.159
        , cancelDx: 0.68, btnDy: -0.382, promptDx: 0.1, promptW: 0.75, promptTop: -0.90, promptH: 0.26
        , barLo: 0.95, barHi: 1.30}
    static BarRe := "i)ready|be\s*used|us[e3]d|t[o0]\s*be"
    static PromptRe := "i)selected|sure|c[o0]nfirm|cancel"
    ; any word of the prompt, misread too ('You av selecte', 'You hm w
    ; —select ed'): a read with none of them is not the prompt
    static PromptWordsRe := "i)y[o0]u\b|s[ae]l[ae]ct|sure|c[o0]nfirm|cancel"
    static BtnRe := "i)c[o0]nfirm|cancel"     ; the prompt's buttons: dark on light, read where the bar is not (bright sky)
    static CloseTries := 3
    ; After Confirm the Selector stays up until the new biome starts, then
    ; closes by itself (live 2026-11-22..24: 28 uses, the biome ~3-5 s after
    ; Confirm; every tidy found it gone without a click, most of them after
    ; 3-6 s of _Locate reads that could not place the closing window). The
    ; task waits for that itself (_AfterConfirm, SelfCloseMs); a window seen
    ; up by the tidy later only waits out what is left of SelfCloseMs since
    ; Confirm (nothing once that has passed), reading only whether it is up.
    static SelfPollMs := 250
    ; The prompt's text is drawn solid in the selected Drive's colour (Abyss
    ; Curse blue 0x548EE0, Corrupt Ruin purple) on the see-through window: on
    ; a bright green / sky scene the plain read lost the Drive's name
    ; ('hb spurse Drive', 'C Drive', nothing: 13 of 26 uses cancelled,
    ; 2026-11-21..23). The text's colour is found in the prompt's pixels
    ; (TextColors: the commonest colour at sharp edges) and that colour alone
    ; is read (Ocr "#RRGGBB" ink). The prompt is read up to PromptTries times
    ; (the window bobs, the scene behind it moves); Cancel only when another
    ; Drive is named.
    static PromptTries := 4
    static PromptRetryMs := 350
    static InkColors := 3            ; colours tried, commonest first
    static InkScale := 2
    static InkEdge := 60             ; a channel this far from the pixel InkDx to the left or right: an edge
    static InkDx := 4
    static InkMinCount := 25         ; edge samples a colour needs (the prompt's text: ~550)
    static InkBright := 150          ; text is bright: a channel at least this
    static FuzzyMin := 0.55          ; a misread name ('hb spurse'): Levenshtein similarity to the Drive's
    static FuzzyGap := 0.2           ; ... and this far ahead of the next Drive's

    name := "biomeitems"
    priority := 5

    _selRow1 := ""
    _selByName := false              ; _PickDrive clicked a row that read as the Drive (not by its place)
    _selAuto := ""                   ; the Drive list's rect found on screen (_FindSelector)
    _scanPrompt := ""                ; the prompt's words the last _ScanRows read over the list ("" = none)
    _closeTry := ""
    _confirmAt := ""                 ; env.Now() of the last Selector Confirm click (_TidySelector)

    __New(deps := "") {
        this._env := TaskEnv(deps)
        this._clock := TaskEnv.Dep(deps, "clock", "")
        if !IsObject(this._clock)
            this._clock := () => A_Now
        this._path := TaskEnv.Dep(deps, "statePath", "")
        if (this._path = "")
            this._path := BiomeItemsTask.DefaultStatePath()
        this._lastUse := Map()       ; key -> env.Now() of the last Use click
        this._lastAny := ""          ; env.Now() of the last Use of any item
        this._missing := Map()       ; key -> env.Now() when its tile was not found or it was refused
        this._holdMs := Map()        ; key -> how long that hold lasts (default MissingRetryMin)
        this._fails := Map()         ; key -> refusals in a row (since its last use)
        this._screenTold := Map()    ; key -> a screen stop was reported (since its last use)
        this._runeSpent := false     ; a Cursed Rune Fragment was used this night
        this._state := ""            ; the state CanRun saw last (Run reads its biome)
        this._Load()
    }

    ; Absolute <repo>\data\biome_items_state.json (lib\tasks\ -> repo root).
    static DefaultStatePath() {
        return RegExReplace(A_LineFile, "\\[^\\]*\\[^\\]*\\[^\\]*$") "\data\biome_items_state.json"
    }

    ; State file {"lastUse": {key: YYYYMMDDHHMMSS}, "lastAny": ...} -> the
    ; same times on env.Now()'s scale (a time in the future counts as now).
    _Load() {
        try {
            v := Json.Parse(FileRead(this._path, "UTF-8"))
            if !(v is Map)
                return
            now := this._env.Now()
            wall := (this._clock)()
            at := (ts) => (ts is String && RegExMatch(ts, "^\d{14}$")) ? now - Max(0, DateDiff(wall, ts, "Seconds")) * 1000 : ""
            if (v.Has("lastUse") && v["lastUse"] is Map)
                for it in BiomeItemsTask.Items
                    if (v["lastUse"].Has(it.key) && (t := at(v["lastUse"][it.key])) !== "")
                        this._lastUse[it.key] := t
            if (v.Has("lastAny") && (t := at(v["lastAny"])) !== "")
                this._lastAny := t
            if v.Has("runeSpent")
                this._runeSpent := v["runeSpent"] ? true : false
        }
    }

    ; Writes the last-use times as wall-clock times (see _Load).
    _Save() {
        now := this._env.Now()
        wall := (this._clock)()
        ts := (t) => DateAdd(wall, -((now - t) // 1000), "Seconds")
        lu := Map()
        for k, t in this._lastUse
            lu[k] := ts(t)
        data := Map("lastUse", lu)
        if (this._lastAny !== "")
            data["lastAny"] := ts(this._lastAny)
        if this._runeSpent
            data["runeSpent"] := 1
        try PotionSafety._AtomicWrite(this._path, Json.Stringify(data) "`n")
        catch as err
            this._env.Log("biome items: could not write " this._path ": " err.Message)
    }

    static Forbid(text) => RegExMatch(String(text), BiomeItemsTask.Forbidden) ? true : false

    ; The selected item's description lets Use be clicked: no forbidden word
    ; in either read and, for an item with mustSay (the Randomizer), the two
    ; reads agree, are at least DescMinChars long and match mustSay.
    static DescIs(it, a, b) {
        if (it.HasProp("consumable") && it.consumable)
            return true                         ; used up by design: no one-time check
        if (BiomeItemsTask.Forbid(a) || BiomeItemsTask.Forbid(b))
            return false
        if (it.mustSay = "")
            return true
        na := Trim(RegExReplace(String(a), "\s+", " "))
        nb := Trim(RegExReplace(String(b), "\s+", " "))
        ; both reads long enough and naming the reusable one (its last line:
        ; drawn through); OCR of its coloured words differs read to read, so
        ; not the same text twice
        return (StrLen(na) >= BiomeItemsTask.DescMinChars && StrLen(nb) >= BiomeItemsTask.DescMinChars
            && RegExMatch(na, it.mustSay) && RegExMatch(nb, it.mustSay)) ? true : false
    }

    ; The tile names the item: its word in the OCR text with the game font's
    ; look-alikes folded ("Biome Rondomizer" = randomizer), and not one-time.
    ; The tile names the item: its word in the folded text, or (words of 7+
    ; letters) one letter off, with 0 read as o (live 2026-11-21: 'biome
    ; seleet0rrme' was the Selector: c as e, o as 0; 30 min unused).
    static TileIs(text, word, consumable := false) {
        t := GameLists.Fold(StrReplace(String(text), "0", "o")), w := GameLists.Fold(word)
        hit := (w != "" && InStr(t, w) > 0)
        if (!hit && StrLen(w) >= 7 && StrLen(t) >= StrLen(w)) {
            Loop StrLen(t) - StrLen(w) + 1
                if (GameLists.Distance(SubStr(t, A_Index, StrLen(w)), w) <= 1) {
                    hit := true
                    break
                }
        }
        return hit && (consumable || !BiomeItemsTask.Forbid(text))
    }

    _TileIs(text, it) => BiomeItemsTask.TileIs(text, it.word, it.HasProp("consumable") && it.consumable)

    ; BiomeItems.blacklist (comma list) -> Map of normalised biome names
    static Blacklist(cfg) {
        m := Map()
        v := IsObject(cfg) ? cfg.Get("BiomeItems.blacklist", "") : ""
        for n in StrSplit(String(v), ",")
            if ((n := Biomes.Norm(n)) != "")
                m[n] := true
        return m
    }

    ; A Cursed Rune Fragment is due: Hunting.cursedRune on, GRAVEYARD or
    ; PUMPKIN MOON up, none used this night, not held. A normal biome ends
    ; the night (the next GRAVEYARD / PUMPKIN MOON may use one again).
    _RuneDue(biome) {
        env := this._env
        b := Biomes.Norm(biome)
        if (this._runeSpent && b != "" && Biomes.IsNormal(b)) {
            this._runeSpent := false
            this._Save()
        }
        if !(IsObject(env.cfg) && env.cfg.Get("Hunting.cursedRune", 0) && Plugins.On(env.cfg, "hunting", 1))   ; the hunting plugin on (Plugins tab)
            return false
        ok := false
        for n in BiomeItemsTask.RuneBiomes
            ok := ok || (b = n)
        if (!ok || this._runeSpent)
            return false
        k := BiomeItemsTask.Rune.key
        if (this._missing.Has(k) && env.Now() - this._missing[k]
            < (this._holdMs.Has(k) ? this._holdMs[k] : BiomeItemsTask.MissingRetryMin * 60000))
            return false
        return true
    }

    CanRun(state) {
        env := this._env
        this._state := state
        if (IsObject(state) && state.HasProp("rareActive") && state.rareActive)
            return false
        biome := (IsObject(state) && state.HasProp("biome")) ? Trim(String(state.biome)) : ""
        if (this._RuneDue(biome) && this._InvCal() != "")
            return true                         ; Limited: its own switch, not BiomeItems.enabled
        if !(IsObject(env.cfg) && env.cfg.Get("BiomeItems.enabled", 0))
            return false
        ; overnight review: only rare=1 was refused, so PUMPKIN MOON (an event
        ; biome, rare 0) and any biome missing from biomes.json were changed
        ; away. Now it must be listed AND a normal biome (Biomes.Normal).
        b := Biomes.Find(env.cfg, biome)
        if (biome = "" || b["rare"] || !b["known"] || !Biomes.IsNormal(biome))
            return false                        ; unknown yet, rare, event or unlisted: never changed
        ; the user's blacklist (e.g. STARFALL): no item until the biome changes
        if BiomeItemsTask.Blacklist(env.cfg).Has(Biomes.Norm(biome))
            return false
        now := env.Now()
        if (this._lastAny !== "" && now - this._lastAny < BiomeItemsTask.ServerCdMin * 60000 + BiomeItemsTask.CdMarginSec * 1000)
            return false
        ; 2026-10-27 review: a missing inventory step made Run return at once,
        ; so the task was picked again every tick and fishing never ran (env
        ; tells about each missing step once)
        if (this._InvCal() == "")
            return false
        return IsObject(this._Ready(now))
    }

    ; The enabled item off its cooldown that was used longest ago (never
    ; used first, then in Items order), or "".
    _Ready(now) {
        env := this._env
        pick := ""
        for it in BiomeItemsTask.Items {
            if !env.cfg.Get("BiomeItems." it.key, 0)
                continue
            if (this._missing.Has(it.key) && now - this._missing[it.key]
                < (this._holdMs.Has(it.key) ? this._holdMs[it.key] : BiomeItemsTask.MissingRetryMin * 60000))
                continue
            if (this._lastUse.Has(it.key) && now - this._lastUse[it.key] < it.cdMin * 60000 + BiomeItemsTask.CdMarginSec * 1000)
                continue
            if (it.key = "biomeSelector") {
                if (BiomeItemsTask.DriveKey(env.cfg.Get("BiomeItems.selectorDrive", "")) = "") {
                    env.Problem("selector:drive", "biome items: pick the Drive for the Biome Selector in Quests & events > Biome items: skipped")
                    continue
                }
            }
            if !IsObject(pick)
                pick := it
            else if (this._lastUse.Has(pick.key) && (!this._lastUse.Has(it.key) || this._lastUse[it.key] < this._lastUse[pick.key]))
                pick := it
        }
        return pick
    }

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
        c.inv_tile2_rect := env.cal.Rect("inv_tile2_rect")     ; optional
        return ok ? c : ""
    }

    _Read(r) => StrLower(String((this._env.ocrFn)(r.x, r.y, r.w, r.h)))

    Run(ctx) {
        env := this._env
        st := this._state
        biome := (IsObject(st) && st.HasProp("biome")) ? Trim(String(st.biome)) : ""
        it := this._RuneDue(biome) ? BiomeItemsTask.Rune : this._Ready(env.Now())
        if !IsObject(it)
            return 0
        c := this._InvCal()
        if (c == "")
            return 0
        r := this._Use(it, c, ctx)
        ; told to stop part way: every wait returned -1 with the inventory
        ; still open over the next task. A preempt closes it first (checked,
        ; only while its tabs read); a halt sends nothing.
        if (r < 0 && !CleanupCtx.Halted(ctx) && Screen.WithMode("C", () => env.InvOpen(c.inv_items_tab))) {
            env.Log("biome items: stopped with the inventory open: closing it first")
            Screen.WithMode("C", () => env.CloseInv(c.inv_open, c.inv_items_tab, CleanupCtx(ctx)))
        }
        return (r = 1) ? 1 : 0
    }

    ; The App's between-tasks check (Tidy): the Biome Selector list (Esc, the
    ; way _CloseSelector does; only while a Drive's name reads in it).
    Leftovers() {
        sel := {up: () => this._SelectorUp() ? "Biome Selector list" : ""
            , close: (label, ctx) => this._TidySelector(ctx)}
        return [sel]
    }

    ; The tidy's close: right after a Confirm the Selector is left to close
    ; by itself (SelfCloseMs, polled); still up after that, or no Confirm
    ; just now: its X (_CloseSelectorX). -> 1 closed, 0 still up, -1 halted
    _TidySelector(ctx) {
        env := this._env
        at := this._confirmAt
        if (at != "") {
            left := BiomeItemsTask.SelfCloseMs - (env.Now() - at), waited := 0
            while (waited < left) {
                if !env.Wait(BiomeItemsTask.SelfPollMs, ctx)
                    return -1
                waited += BiomeItemsTask.SelfPollMs
                if !this._SelectorUp() {
                    this._confirmAt := ""
                    return 1
                }
            }
            this._confirmAt := ""
        }
        return this._CloseSelectorX(ctx)
    }

    ; Esc on the Selector list (and once more when Esc only brought up the
    ; Roblox menu). -> 1 | -1 halted
    _EscSelector(ctx) {
        env := this._env
        Input.Key("Esc", Input.TapHoldMs, env.io)
        if !env.Wait(BiomeItemsTask.InvMs, ctx)
            return -1
        if this._MenuUp() {
            Input.Key("Esc", Input.TapHoldMs, env.io)
            if !env.Wait(BiomeItemsTask.InvMs, ctx)
                return -1
        }
        return 1
    }

    ; -> 1 used, 0 refused / not found (inventory closed), -1 stopped.
    ; the inventory scales evenly, centred (16:10): mode "C" around it
    _Use(it, c, ctx) {
        old := Screen.Mode
        Screen.Mode := "C"
        try
            return this._UseM(it, c, ctx)
        finally
            Screen.Mode := old
    }

    _UseM(it, c, ctx) {
        env := this._env
        io := env.io
        ; the Daily Rewards popup covers it too (live 2026-11-03): closed
        ; first, and no inventory opened under it
        r := Input.CloseDaily(ctx, io, env.ocrFn)
        if (r < 0)
            return -1
        if (r = 1)
            env.Log("biome items: the Daily Rewards popup was over the game: closed it")
        else if (r = 2)
            return this._Fail(c, it, "the Daily Rewards popup is over the game and was not closed: nothing clicked", true)
        ; Aura Collections left open covers the inventory (live 2026-11-02)
        r := Input.CloseCollections(ctx, io, env.ocrFn)
        if (r < 0)
            return -1
        if (r > 0)
            env.Log("biome items: the Aura Collections screen was open: " (r = 1 ? "closed it" : "it would not close"))
        if !env.InvOpen(c.inv_items_tab) {
            if ((why := this._Unsafe(c, false)) != "")
                return this._Fail(c, it, why, true)
            env.Click(c.inv_open)
            if !env.Wait(BiomeItemsTask.InvMs, ctx)
                return -1
        }
        if ((why := this._Unsafe(c)) != "")
            return this._Fail(c, it, why, true)
        env.Click(c.inv_items_tab)
        if !env.Wait(BiomeItemsTask.InvMs, ctx)
            return -1
        ; Roblox drops a typed letter now and then ("Biome Rndomizer"): no
        ; matching tile -> clear the search and type it again (SearchTries)
        tiles := []
        Loop BiomeItemsTask.SearchTries {
            if ctx.ShouldStop()
                return -1
            if ((why := this._Unsafe(c)) != "")
                return this._Fail(c, it, why, true)
            env.Click(c.inv_search)
            Input.ClearText(io)
            Input.TypeText(it.name, io)
            if !env.Wait(BiomeItemsTask.SearchMs, ctx)
                return -1
            ; every tile with the item's word and no "one-time": the one-time
            ; Biome Randomizer may be listed first
            seen := ""
            for r in [c.inv_tile1_rect, c.inv_tile2_rect] {
                if !IsObject(r)
                    continue
                t := this._Read(r)
                seen .= (seen = "" ? "" : " / ") SubStr(Trim(RegExReplace(t, "\s+", " ")), 1, 30)
                if this._TileIs(t, it)
                    tiles.Push(r)
            }
            if (tiles.Length > 0)
                break
            if (A_Index < BiomeItemsTask.SearchTries)
                env.Log("biome items: no " it.name " tile after typing the search (a letter may have been dropped): typing it again")
        }
        if (tiles.Length = 0)
            return this._Fail(c, it, "no reusable '" it.name "' tile after searching " BiomeItemsTask.SearchTries " times (tiles read: '" seen "'; do you own one? the one-time Biome Randomizer is never used)")
        ; the description decides: the one-time Randomizer's tile can read
        ; plain "Biome Randomizer", so a refused tile 1 hands over to tile 2
        ; (2026-10-27 review: tile 2 was never tried)
        tile := "", d := ""
        for i, r in tiles {
            if ((why := this._Unsafe(c)) != "")
                return this._Fail(c, it, why, true)
            env.Click({x: r.x + r.w // 2, y: r.y + r.h // 2})
            if !env.Wait(BiomeItemsTask.SelectMs, ctx)
                return -1
            d := this._Read(c.inv_desc_rect)
            if !env.Wait(BiomeItemsTask.DescAgainMs, ctx)
                return -1
            if BiomeItemsTask.DescIs(it, d, this._Read(c.inv_desc_rect)) {
                tile := r
                break
            }
            if (i < tiles.Length)
                env.Log("biome items: this " it.name "'s description is single-use or not the reusable one's: trying the next tile")
        }
        if !IsObject(tile)
            return this._Fail(c, it, "the selected item's description is single-use or not the reusable " it.name "'s (read: '"
                . SubStr(Trim(RegExReplace(d, "\s+", " ")), 1, 200) "'); Use not clicked")
        t := this._Read(tile)
        if !this._TileIs(t, it) {
            ; one more look: a read can catch the tile mid-redraw (live
            ; 2026-11-13: a Randomizer missed its use on one bad read)
            if !env.Wait(BiomeItemsTask.RereadMs, ctx)
                return -1
            t := this._Read(tile)
        }
        if !this._TileIs(t, it)
            return this._Fail(c, it, "the tile changed before Use; Use not clicked")
        if ctx.ShouldStop()
            return -1
        if ((why := this._Unsafe(c)) != "")
            return this._Fail(c, it, why, true)
        env.Click(c.inv_use)
        ; the Selector is only used once a Drive is confirmed: its cooldowns
        ; start there (2026-10-27 review: a Drive not found started the 20 min
        ; server cooldown although nothing was used). Until then it is held,
        ; so no exit before Confirm brings it back on the next tick.
        sel := (it.key = "biomeSelector")
        if sel
            this._missing[it.key] := env.Now()
        else
            this._Used(it)
        if !env.Wait(BiomeItemsTask.UseMs, ctx)
            return sel ? this._Cut(c, it, ctx) : -1
        if sel {
            drive := env.cfg.Get("BiomeItems.selectorDrive", "")
            if !env.Wait(BiomeItemsTask.BootMs, ctx)       ; the list boots
                return this._Cut(c, it, ctx)
            if (this._FindSelector(ctx) < 0)               ; the calibrated list rect, or found on screen
                return this._Cut(c, it, ctx)
            p := this._PickDrive(drive, ctx)
            if (p < 0)
                return this._Cut(c, it, ctx)
            if (p = 0)
                return this._NoDrive(c, it, drive, ctx)
            if !env.Wait(BiomeItemsTask.PickMs, ctx)
                return this._Cut(c, it, ctx)
            if env.BuyPrompt("biome items") {
                env.Log("biome items: a purchase prompt came up before Confirm: not confirmed")
                return this._NoDrive(c, it, drive, ctx)
            }
            ; the prompt names the Drive Confirm would use: only ours (live
            ; 2026-11-21: a click through the open Selector picked Corrupt
            ; Ruin Drive)
            v := this._ReadPrompt(drive, ctx)
            if (v.state = "stop")
                return this._Cut(c, it, ctx)
            if (v.state = "unread" && this._selByName && v.up && IsObject(v.confirmPt)) {
                ; its row read as the Drive and was clicked, the prompt is up,
                ; no other Drive is named in any read: it is ours
                env.Log("biome items: the Selector's prompt is up but no Drive's name read in it (read: '" BiomeItemsTask._Brief(v.pt)
                    . "'); " drive "'s own row was clicked: Confirm")
                v.state := "ours"
            }
            if (v.state != "ours") {
                loc := v.loc, pt := v.pt, cp := v.cp, wide := v.wide
                shot := HasMethod(env.io, "Shot") ? env.io.Shot() : ""
                if (shot != "")
                    env.Log("biome items: screen at the Selector's prompt saved to " shot (IsObject(loc) ? " (bar " loc.bar ")" : ""))
                n := BiomeItemsTask.PromptDrive(pt)
                if !v.up
                    env.Log("biome items: the Selector's prompt did not come up after the click on " drive " (read: '" BiomeItemsTask._Brief(pt) "'): nothing confirmed")
                else
                    env.Log("biome items: the Selector's prompt " (v.state = "other" && n ? "names " BiomeItemsTask.Drives[n] ", not " drive : "does not name " drive)
                        . " (read: '" BiomeItemsTask._Brief(pt) "'): Cancel, nothing confirmed")
                if (IsObject(loc) && RegExMatch(pt, BiomeItemsTask.PromptRe)) {
                    env.Click(this._PromptBtn(loc, "cancel"))
                    env.Wait(BiomeItemsTask.InvMs, ctx)
                } else if (IsObject(cp) && RegExMatch(wide, BiomeItemsTask.PromptRe)) {
                    r := this._SelRect()           ; Cancel: the calibrated Confirm's row, its own x
                    env.Click({x: Round(r.x + BiomeItemsTask.Geo.cancelDx * r.w), y: cp.y})
                    env.Wait(BiomeItemsTask.InvMs, ctx)
                }
                return this._NoDrive(c, it, drive, ctx)
            }
            if env.BuyPrompt("biome items") {
                env.Log("biome items: a purchase prompt came up before Confirm: not confirmed")
                return this._NoDrive(c, it, drive, ctx)
            }
            env.Click(v.confirmPt)
            this._confirmAt := env.Now()
            this._Used(it)
            if !env.Wait(BiomeItemsTask.UseMs, ctx)
                return -1
        }
        env.Log("biome items: used " it.name)
        if (it.HasProp("consumable") && it.consumable)
            env.Report("biome", "Cursed Rune Fragment used", "Used one **" it.name "** (Blood Rain). No other one until the next Graveyard / Pumpkin Moon night.", 0x8E44AD)
        else
            env.Report("biome", "Biome item used", "Used **" it.name "**. Next one in " BiomeItemsTask.ServerCdMin " min (server cooldown).", 0x5865F2)
        ; the Selector closes itself when the biome changes: waited for here,
        ; not left to the tidy (a preempt still finishes it; a halt not)
        if (sel && this._AfterConfirm(CleanupCtx(ctx)) < 0)
            return 1
        if (this._TileIs(this._Read(c.inv_tile1_rect), it) || env.InvOpen(c.inv_items_tab))
            env.CloseInv(c.inv_open, c.inv_items_tab, ctx)       ; inventory still open: close it (checked)
        env.Wait(BiomeItemsTask.InvMs, ctx)
        env.BuyPrompt("biome items")            ; after the last click: a prompt is closed and reported
        return 1
    }

    ; Right before a click: TaskEnv.Unsafe (a purchase prompt; inv (default):
    ; the inventory's tabs). -> why the click is refused, or "" (safe).
    _Unsafe(c, inv := true) => this._env.Unsafe("biome items", inv ? c.inv_items_tab : "")

    ; "Abyss Curse Drive" -> "abyss" (the word looked for in the list); "" for
    ; a name that is not one of the Drives.
    static DriveKey(name) {
        for d in BiomeItemsTask.Drives
            if (StrLower(Trim(String(name))) = StrLower(d))
                return StrLower(StrSplit(d, " ")[1])
        return ""
    }

    ; A Drive's key word in an OCR read, through the game-font fold
    ; (GameText): "abyss" reads 'obyss', "chilling" 'chiIIing', "infernal"
    ; 'infemal'. The nine keys stay apart folded (tested).
    static DriveIn(text, key) => GameText.Has(text, key)

    ; Index (1-based) of a Drive name in Drives, else 0.
    static DriveIndex(name) {
        for d in BiomeItemsTask.Drives
            if (StrLower(Trim(String(name))) = StrLower(d))
                return A_Index
        return 0
    }

    ; Drive i's first or second word reads in the text: a pale row loses one
    ; ('Ab ss Curse' still has "curse"; live 2026-11-21).
    static RowIs(text, i) {
        w := StrSplit(BiomeItemsTask.Drives[i], " ")
        return GameText.Has(text, w[1]) || GameText.Has(text, w[2])
    }

    ; A read of the list rect shows the Selector: a Drive's row, or its prompt.
    static ListOrPrompt(t) {
        for d in BiomeItemsTask.Drives
            if BiomeItemsTask.RowIs(t, A_Index)
                return true
        return RegExMatch(t, BiomeItemsTask.PromptRe) > 0
    }

    ; The prompt's text names Drive i and no other one (PromptDrive).
    static PromptIs(text, i) => i >= 1 && BiomeItemsTask.PromptDrive(text) = i

    ; The Drive the prompt's text names -> its index, 0 = none (or no one
    ; Drive for sure). One Drive's word in it (RowIs) and no other's; else
    ; the name in its brackets matched loosely (QuestMatch.Similarity of the
    ; folded name: 'hb spurse Drive ]' is Abyss Curse, live 2026-11-23), the
    ; best Drive FuzzyMin alike and FuzzyGap ahead of the next.
    static PromptDrive(text) {
        text := String(text)
        named := []
        for d in BiomeItemsTask.Drives
            if BiomeItemsTask.RowIs(text, A_Index)
                named.Push(A_Index)
        if (named.Length = 1)
            return named[1]
        ; two Drives' words: the list's rows (live 2026-11-24 00:26: the
        ; prompt never came up, 'Unknown Void Drive Corrupt Ruin' was taken
        ; for it); a prompt names one Drive
        if (named.Length >= 2)
            return 0
        score := []
        for d in BiomeItemsTask.Drives
            score.Push(0)
        for line in StrSplit(text, "`n") {
            name := BiomeItemsTask.PromptName(line)
            if (StrLen(name) < 5)
                continue
            for d in BiomeItemsTask.Drives {
                w := StrSplit(d, " ")
                score[A_Index] := Max(score[A_Index], QuestMatch.Similarity(name, GameText.Fold(w[1] " " w[2])))
            }
        }
        best := 0, bs := 0, second := 0
        for i, s in score {
            if (s > bs)
                second := bs, bs := s, best := i
            else if (s > second)
                second := s
        }
        return (best && bs >= BiomeItemsTask.FuzzyMin && bs - second >= BiomeItemsTask.FuzzyGap) ? best : 0
    }

    ; One line of the prompt -> the Drive's name in it, folded (GameText):
    ; inside the brackets, without the prompt's own words ("You have
    ; selected", "Drive", "Are you sure?") -> 'hb spurse Drive ]' -> "hbspurse"
    static PromptStop := Map("you", 1, "hope", 1, "ore", 1, "sure", 1, "dripe", 1, "confirm", 1, "concei", 1)
    static PromptName(line) {
        s := String(line)
        if (p := InStr(s, "["))
            s := SubStr(s, p + 1)
        if (p := InStr(s, "]"))
            s := SubStr(s, 1, p - 1)
        ws := []
        for w in StrSplit(s, [" ", "`t"])
            if ((f := GameText.Fold(w)) != "")
                ws.Push(f)
        from := 1                       ; after "selected" ('You av selecte hb spurse')
        for i, f in ws
            if (SubStr(f, 1, 3) = "sei")
                from := i + 1
        out := ""
        for i, f in ws
            if (i >= from && !BiomeItemsTask.PromptStop.Has(f))
                out .= f
        return out
    }

    static _Brief(t) => SubStr(Trim(RegExReplace(String(t), "\s+", " ")), 1, 60)

    ; The prompt text's colour(s) from its pixels (px: Array of w*h
    ; 0xRRGGBB, row-major): bright pixels at a sharp edge (a channel InkEdge
    ; away from the pixel InkDx to the left or right), counted per 16-level
    ; colour box; the k commonest boxes' mean colours (each kept apart from
    ; the ones before it). The solid text is the commonest: the scene behind
    ; is shaded, its edges spread over many colours. -> Array of 0xRRGGBB
    static TextColors(px, w, h, k := 3) {
        out := []
        if (!(px is Array) || w < 2 * BiomeItemsTask.InkDx + 2 || px.Length < w * h)
            return out
        d := BiomeItemsTask.InkDx, e := BiomeItemsTask.InkEdge, lo := BiomeItemsTask.InkBright
        cnt := Map(), sum := Map()
        y := 0
        while (y < h) {
            row := y * w
            x := d
            while (x < w - d) {
                c := px[row + x + 1]
                r := (c >> 16) & 255, g := (c >> 8) & 255, b := c & 255
                if (Max(r, g, b) >= lo) {
                    a := px[row + x - d + 1], z := px[row + x + d + 1]
                    if (BiomeItemsTask._Far(r, g, b, a, e) || BiomeItemsTask._Far(r, g, b, z, e)) {
                        key := ((r >> 4) << 8) | ((g >> 4) << 4) | (b >> 4)
                        if !cnt.Has(key)
                            cnt[key] := 0, sum[key] := [0, 0, 0]
                        cnt[key] += 1, s := sum[key], s[1] += r, s[2] += g, s[3] += b
                    }
                }
                x += 2
            }
            y += 2
        }
        used := Map()
        while (out.Length < k) {
            best := "", bn := BiomeItemsTask.InkMinCount - 1
            for key, n in cnt
                if (!used.Has(key) && n > bn)
                    best := key, bn := n
            if (best = "")
                break
            used[best] := 1
            s := sum[best], n := cnt[best]
            r := Round(s[1] / n), g := Round(s[2] / n), b := Round(s[3] / n)
            near := false
            for o in out
                near := near || BiomeItemsTask._Far(r, g, b, o, 24) = false
            if !near
                out.Push((r << 16) | (g << 8) | b)
        }
        return out
    }

    ; r, g, b and colour c differ by more than e in some channel
    static _Far(r, g, b, c, e) => Abs(r - ((c >> 16) & 255)) > e || Abs(g - ((c >> 8) & 255)) > e || Abs(b - (c & 255)) > e

    ; Reads selector_list_rect in horizontal strips (the window bobs, so
    ; places are read, not remembered). -> Map(Drive index -> row middle y)
    ; for every Drive whose row read, or "" when stopped. A strip showing the
    ; prompt's words is no row (the prompt hides the rows; its "[ Drive ]"
    ; would pass for one): its text is kept in this._scanPrompt.
    _ScanRows(r, ctx) {
        env := this._env
        sh := Max(24, r.h // 9)                 ; about one row
        step := Max(8, sh // 3)
        hits := Map()
        this._scanPrompt := ""
        y := r.y
        while (y + sh <= r.y + r.h) {
            if ctx.ShouldStop()
                return ""
            t := (env.ocrFn)(r.x, y, r.w, sh)
            if RegExMatch(t, BiomeItemsTask.PromptRe) {
                this._scanPrompt .= (this._scanPrompt = "" ? "" : " ") Trim(RegExReplace(t, "\s+", " "))
                y += step
                continue
            }
            for d in BiomeItemsTask.Drives
                if BiomeItemsTask.RowIs(t, A_Index) {
                    if !hits.Has(A_Index)
                        hits[A_Index] := []
                    hits[A_Index].Push(y + sh // 2)
                }
            y += step
        }
        rows := Map()
        for i, ys in hits {
            top := ys[1], bot := ys[1]
            for h in ys                         ; the first run of hits = the row
                if (h - bot <= step)
                    bot := h
            rows[i] := (top + bot) // 2
        }
        return rows
    }

    ; The first row's middle y from the rows read (each row put back by its
    ; place in the fixed order; rows off the list's spacing left out, see
    ; FitRows). "" when no row read or the rows disagree.
    static Row1(rows, r) {
        f := BiomeItemsTask.FitRows(rows, r)
        return f.ok ? f.row1 : ""
    }

    ; The rows read checked against each other: each row gives the first
    ; row's y (its y less its place times the pitch); the y most rows give
    ; (within RowFitTol of a pitch) wins, the rows off it are left out. Usable
    ; (ok) with one row, or with two or more that agree and outnumber the
    ; rows left out. A row read where another Drive's is (a strip over two
    ; rows, a stray word) or a mix of reads from before and after the list
    ; moved do not agree. -> {ok, row1, keep: Map, drop: Map}
    static RowFitTol := 0.35
    static FitRows(rows, r) {
        keep := Map(), drop := Map()
        if (!IsObject(rows) || rows.Count = 0 || !IsObject(r))
            return {ok: false, row1: "", keep: keep, drop: drop}
        p := r.h * BiomeItemsTask.Geo.pitch, tol := BiomeItemsTask.RowFitTol * p
        best := "", bn := 0
        for i, y in rows {
            c := y - (i - 1) * p, n := 0
            for j, y2 in rows
                n += (Abs(y2 - (j - 1) * p - c) <= tol) ? 1 : 0
            if (n > bn)
                bn := n, best := c
        }
        sum := 0
        for i, y in rows {
            if (Abs(y - (i - 1) * p - best) <= tol)
                keep[i] := y, sum += y - (i - 1) * p
            else
                drop[i] := y
        }
        ok := rows.Count = 1 || (keep.Count >= 2 && keep.Count > drop.Count)
        return {ok: ok, row1: Round(sum / keep.Count), keep: keep, drop: drop}
    }

    ; "1@538 3@635" (Drive index @ row middle y), top to bottom
    static RowsBrief(rows) {
        if (!IsObject(rows) || rows.Count = 0)
            return "none"
        s := ""
        for i, y in rows                       ; a Map lists its keys in order
            s .= (s = "" ? "" : " ") i "@" y
        return s
    }

    ; The Drive list's rect: found on screen this run (_FindSelector), else
    ; the calibrated selector_list_rect. "" = neither.
    _SelRect() => IsObject(this._selAuto) ? this._selAuto : this._env.cal.Rect("selector_list_rect")

    ; The prompt's Confirm x: the calibrated selector_confirm with the
    ; calibrated rect, else worked out from the rect found.
    _ConfirmX(r) {
        pt := IsObject(this._selAuto) ? "" : this._env.cal.Point("selector_confirm")
        return IsObject(pt) ? pt.x : AutoCal.SelectorConfirmX(r)
    }

    ; A Drive's name reads in rect r (one read).
    _DriveReads(r) {
        t := (this._env.ocrFn)(r.x, r.y, r.w, r.h)
        for d in BiomeItemsTask.Drives
            if BiomeItemsTask.RowIs(t, A_Index)
                return true
        return false
    }

    ; The Selector's list just opened: where is it? The calibrated rect while
    ; both steps are recorded and a Drive reads in it (as before). Else it is
    ; FOUND ON SCREEN by its Drives' names (AutoCal.Selector: the whole
    ; screen at 1x, then its middle at 2x; FindTries looks, the window bobs
    ; and its rows read differently each time), and used only when a Drive
    ; reads in the rect found. Nothing found: the calibrated rect stays.
    ; -> 1 calibrated / found, 0 neither, -1 stopped
    static FindTries := 3
    static FindMs := 400
    static FindBox := {x: 640, y: 300, w: 1280, h: 840}
    _FindSelector(ctx := "") {
        env := this._env
        cal := env.cal.Rect("selector_list_rect")
        this._selAuto := ""
        tried := IsObject(cal) && IsObject(env.cal.Point("selector_confirm"))
        if (tried && this._DriveReads(cal)) {
            CalHealth.Ok("selector_list_rect", cal)
            return 1
        }
        Loop BiomeItemsTask.FindTries {
            for look in [["", 1], [BiomeItemsTask.FindBox, 2]] {
                r := AutoCal.Selector(env.Lines(look[1], look[2]), BiomeItemsTask.Drives)
                if (IsObject(r) && this._DriveReads(r)) {
                    this._selAuto := r
                    if tried
                        CalHealth.Fail("selector_list_rect", "no Drive read in it; the list was found elsewhere on screen", cal)
                    env.Log("biome items: the Biome Selector's Drive list found on screen at " r.x "," r.y " (" r.w "x" r.h ")"
                        . (IsObject(cal) ? ": no Drive read in the calibrated selector_list_rect" : ": selector_list_rect is not calibrated"))
                    return 1
                }
            }
            if (IsObject(ctx) && A_Index < BiomeItemsTask.FindTries && !env.Wait(BiomeItemsTask.FindMs, ctx))
                return -1
        }
        return IsObject(cal) ? 1 : 0
    }

    ; Finds `drive` in the list and clicks its row: by its name, or, when its
    ; row does not read (pale on a bright sky), by its place in the fixed
    ; order from the rows that did. Not in view: scroll the list down, try
    ; again. The prompt it opens is checked before Confirm. Sets
    ; this._selRow1 (the first row's y at the click).
    ;
    ; A click by place is only made on rows that agree (FitRows: a stray
    ; Drive word or a strip over two rows is left out; rows that do not fit
    ; the list's spacing at all: read again), never while the prompt is up
    ; over the list (its "[ Drive ]" is no row), never on a place that reads
    ; as another Drive, and only when a second read of the rows puts the list
    ; at the same place (live 2026-11-25 09:27: the click by place opened
    ; Angelic Hymn Drive's prompt, two rows below Abyss Curse: the rows it
    ; was worked out from were not where the list was at the click). The log
    ; line carries the rows read ("rows read: 1@538 3@635").
    ; -> 1 clicked, 0 not found / refused, -1 stopped.
    static PickScans := 4
    _PickDrive(drive, ctx) {
        env := this._env
        ti := BiomeItemsTask.DriveIndex(drive)
        r := this._SelRect()
        this._selRow1 := "", this._selByName := false
        if (!ti || !IsObject(r))
            return 0
        p := r.h * BiomeItemsTask.Geo.pitch
        sh := Max(24, r.h // 9)
        scrolled := false, prev := "", why := "", rows := ""
        Loop BiomeItemsTask.PickScans {
            rows := this._ScanRows(r, ctx)
            if !IsObject(rows)
                return -1
            if (this._scanPrompt != "") {
                env.Log("biome items: the Selector's prompt is up over the list (read: '" BiomeItemsTask._Brief(this._scanPrompt)
                    . "'; rows read: " BiomeItemsTask.RowsBrief(rows) "): no row clicked")
                return 0
            }
            f := BiomeItemsTask.FitRows(rows, r)
            if (rows.Count && !f.ok) {
                why := "the rows read do not fit the list's spacing (rows read: " BiomeItemsTask.RowsBrief(rows) ")"
                prev := ""
                if !env.Wait(BiomeItemsTask.SelfPollMs, ctx)
                    return -1
                continue
            }
            cy := f.keep.Has(ti) ? rows[ti] : (f.ok ? Round(f.row1 + (ti - 1) * p) : "")
            if (cy = "" || cy < r.y || cy > r.y + r.h) {
                if scrolled
                    break
                scrolled := true, prev := ""        ; below the fold: scroll the list
                env.io.MoveTo(r.x + r.w // 2, r.y + r.h // 2)
                Input.Wheel("down", 5, env.io)
                if !env.Wait(BiomeItemsTask.PickMs, ctx)
                    return -1
                continue
            }
            if f.drop.Count
                env.Log("biome items: Selector rows off the list's spacing left out: " BiomeItemsTask.RowsBrief(f.drop)
                    . " (rows read: " BiomeItemsTask.RowsBrief(rows) ")")
            byName := f.keep.Has(ti)
            if !byName {
                ; not read in the scan: the strip centred on its place, 1x
                ; then 2x (live 2026-11-23..25: the scan's strips sat off the
                ; row, 'Ab ss Curs-'; centred it read 'Ab ss Curse')
                other := 0
                for sc in [1, 2] {
                    t := (env.ocrFn)(r.x, cy - sh // 2, r.w, sh, sc)
                    if (byName := BiomeItemsTask.RowIs(t, ti))
                        break
                    other := other || BiomeItemsTask.OtherDrive(t, ti)
                }
                if byName {
                    env.Log("biome items: " drive "'s row read at its place in the list")
                } else if other {
                    why := drive "'s place (y " cy ") reads as " BiomeItemsTask.Drives[other] " (rows read: " BiomeItemsTask.RowsBrief(rows) ")"
                    prev := ""
                    continue
                } else if (!IsObject(prev) || Abs(prev.row1 - f.row1) > p / 2) {
                    ; by place only: the rows read once more must put the
                    ; list at the same place (it scrolled or slid since)
                    if IsObject(prev)
                        why := "the list moved between two reads of its rows (first row at y " prev.row1 ", then " f.row1
                            . "; rows read: " prev.rows ", then " BiomeItemsTask.RowsBrief(rows) ")"
                    prev := {row1: f.row1, rows: BiomeItemsTask.RowsBrief(rows)}
                    continue
                }
            }
            if env.BuyPrompt("biome items")
                return 0
            if !byName
                env.Log("biome items: " drive "'s row did not read; clicked by its place in the list at y " cy
                    . " (rows read: " BiomeItemsTask.RowsBrief(rows) (IsObject(prev) ? "; before: " prev.rows : "") ")")
            this._selRow1 := f.row1, this._selByName := byName
            env.Click({x: r.x + r.w // 2, y: cy})
            return 1
        }
        if (why != "")
            env.Log("biome items: " drive " not clicked: " why)
        else
            env.Log("biome items: " drive "'s row not placed (rows read: " BiomeItemsTask.RowsBrief(rows) ")")
        return 0
    }

    ; Another Drive than i (the first one) whose word reads in text, 0 = none
    static OtherDrive(text, i) {
        for d in BiomeItemsTask.Drives
            if (A_Index != i && BiomeItemsTask.RowIs(text, A_Index))
                return A_Index
        return 0
    }

    ; Where the Selector window is now: its bottom bar read (1x, then 2x),
    ; else its rows. -> {bar, row1} (y values) or "".
    _Locate(ctx) {
        env := this._env
        r := this._SelRect()
        if !IsObject(r)
            return ""
        g := BiomeItemsTask.Geo
        for sc in [1, 2] {
            sh := Round(Max(40, r.h // 10) * (sc = 1 ? 1 : 1.5))
            ys := []
            y := Round(r.y + g.barLo * r.h)
            while (y <= r.y + g.barHi * r.h) {
                if ctx.ShouldStop()
                    return ""
                if RegExMatch((env.ocrFn)(r.x, y, r.w, sh, sc), BiomeItemsTask.BarRe)
                    ys.Push(y + sh / 2)
                y += 10
            }
            if ys.Length {
                sum := 0
                for v in ys
                    sum += v
                bar := Round(sum / ys.Length)
                return {bar: bar, row1: Round(bar - g.bar * r.h)}
            }
        }
        ; the prompt's Confirm / Cancel row (live 2026-11-21: the pale bar did
        ; not read on a bright sky, the dark button text did)
        sh := Max(36, r.h // 10)
        for sc in [1, 2] {
            ys := []
            y := r.y
            while (y + sh <= r.y + r.h) {
                if ctx.ShouldStop()
                    return ""
                if RegExMatch((env.ocrFn)(r.x, y, r.w, sh, sc), BiomeItemsTask.BtnRe)
                    ys.Push(y + sh / 2)
                y += 12
            }
            if ys.Length {
                sum := 0
                for v in ys
                    sum += v
                bar := Round(sum / ys.Length - g.btnDy * r.h)
                return {bar: bar, row1: Round(bar - g.bar * r.h)}
            }
        }
        rows := this._ScanRows(r, ctx)
        row1 := BiomeItemsTask.Row1(rows, r)
        return (row1 = "") ? "" : {bar: Round(row1 + g.bar * r.h), row1: row1}
    }

    ; The prompt's text ("You have selected [ Drive ] Are you sure?") at loc,
    ; read at 1x then 2x. -> text ("" when nothing reads)
    _PromptText(loc) {
        env := this._env
        r := this._SelRect()
        g := BiomeItemsTask.Geo
        x := Round(r.x + g.promptDx * r.w), y := Round(loc.bar + g.promptTop * r.h)
        w := Round(g.promptW * r.w), h := Round(g.promptH * r.h)
        ; the text's own colour first (bright scenes: the plain read lost
        ; the Drive's name, live 2026-11-21..23)
        k := this._KeyedText(x, y, w, h)
        if BiomeItemsTask.PromptDrive(k)
            return k
        ; 1x, and 2x unless 1x already names exactly one Drive (live 03:21:
        ; 1x read 'Youzah e selected' without the Drive line): both reads
        ; together, so the Drive's name has two chances
        t := (k != "" ? k "`n" : "") String((env.ocrFn)(x, y, w, h, 1))
        named := 0
        for d in BiomeItemsTask.Drives
            named += BiomeItemsTask.RowIs(t, A_Index) ? 1 : 0
        if (named != 1)
            t .= "`n" String((env.ocrFn)(x, y, w, h, 2))
        return t
    }

    ; The rect read in its text's own colour: the commonest colours at sharp
    ; edges (TextColors) tried in turn, the first read showing the prompt's
    ; words (PromptRe) kept. -> text ("" when none does)
    _KeyedText(x, y, w, h) {
        env := this._env
        px := ""
        try px := (env.rectFn)(x, y, w, h)
        for c in BiomeItemsTask.TextColors(px, w, h, BiomeItemsTask.InkColors) {
            t := ""
            try t := String((env.inkFn)(x, y, w, h, BiomeItemsTask.InkScale, Format("#{:06X}", c)))
            if RegExMatch(t, BiomeItemsTask.PromptRe)
                return t
        }
        return ""
    }

    ; The prompt that _PickDrive's click opened, read up to PromptTries
    ; times: placed (_Locate), read (_PromptText; the window read whole when
    ; that names no Drive and selector_confirm is recorded). Ours as soon as
    ; a read names it while no read named another; another Drive read twice
    ; ends it. -> {state: "ours" / "other" / "unread" / "stop", up (the
    ; prompt's words read), loc, pt, confirmPt, cp, wide} of the last read
    _ReadPrompt(drive, ctx) {
        env := this._env
        ti := BiomeItemsTask.DriveIndex(drive)
        others := 0, up := false, v := ""
        Loop BiomeItemsTask.PromptTries {
            if ctx.ShouldStop()
                return {state: "stop"}
            loc := this._Locate(ctx)
            if ctx.ShouldStop()
                return {state: "stop"}
            if (!IsObject(loc) && this._selRow1 != "")
                loc := {row1: this._selRow1, bar: Round(this._selRow1 + BiomeItemsTask.Geo.bar * this._SelRect().h)}
            pt := IsObject(loc) ? this._PromptText(loc) : ""
            confirmPt := IsObject(loc) ? this._PromptBtn(loc, "confirm") : ""
            n := BiomeItemsTask.PromptDrive(pt)
            ; a Drive named without any of the prompt's own words while the
            ; list's rows read (the prompt hides them): a row, not the prompt
            ; (live 2026-11-24 00:26: CONNECTION UNSTABLE, no prompt came up,
            ; 'Unknown Void Drive' read where the prompt is placed)
            if (n && !RegExMatch(pt, BiomeItemsTask.PromptWordsRe) && this._RowsShow(ctx))
                n := 0
            if ctx.ShouldStop()
                return {state: "stop"}
            wide := "", cp := ""
            if (n != ti) {
                ; the window read whole (live 05:09: pale bar and buttons on a
                ; bright sky placed the prompt read on the title): while the
                ; prompt is up its rows are hidden, so the only Drive named in
                ; the window is the selected one. Confirm at the calibrated
                ; spot then (Cancel is far to its right: a bob only misses).
                wide := this._WideText()
                cp := IsObject(this._selAuto) ? "" : env.cal.Point("selector_confirm")
                if (IsObject(cp) && RegExMatch(wide, BiomeItemsTask.PromptRe)) {
                    nw := BiomeItemsTask.PromptDrive(wide)
                    if (nw = ti && !n) {
                        env.Log("biome items: the Selector's prompt names " drive " (read across the window): Confirm at its calibrated spot")
                        pt := wide, confirmPt := {x: cp.x, y: cp.y}, n := ti
                    } else if !n
                        n := nw
                }
            }
            up := up || RegExMatch(pt, BiomeItemsTask.PromptRe) > 0 || (IsObject(cp) && RegExMatch(wide, BiomeItemsTask.PromptRe) > 0)
            v := {loc: loc, pt: pt, confirmPt: confirmPt, cp: cp, wide: wide, up: up}
            if (n = ti && !others) {
                if (A_Index > 1)
                    env.Log("biome items: the Selector's prompt named " drive " on read " A_Index)
                v.state := "ours"
                return v
            }
            if (n && n != ti && ++others >= 2)
                break                           ; another Drive, read twice
            if (A_Index < BiomeItemsTask.PromptTries && !env.Wait(BiomeItemsTask.PromptRetryMs, ctx))
                return {state: "stop"}
        }
        v.state := others ? "other" : "unread"
        return v
    }

    ; The list's rows read now (two or more): the prompt is not over them.
    _RowsShow(ctx) {
        r := this._SelRect()
        if !IsObject(r)
            return false
        rows := this._ScanRows(r, ctx)
        return IsObject(rows) && rows.Count >= 2
    }

    ; The whole Selector window read (the list rect with room for the title
    ; above and the bottom bar below), 1x and 2x together.
    _WideText() {
        r := this._SelRect()
        if !IsObject(r)
            return ""
        y := Max(0, Round(r.y - 0.15 * r.h)), h := Round(1.35 * r.h)
        return String((this._env.ocrFn)(r.x, y, r.w, h, 1)) "`n" String((this._env.ocrFn)(r.x, y, r.w, h, 2))
    }

    ; The prompt's Confirm / Cancel button at loc (Confirm: selector_confirm's
    ; x, the y from the bar: the calibrated y was one moment of the bob).
    _PromptBtn(loc, which) {
        env := this._env
        r := this._SelRect()
        g := BiomeItemsTask.Geo
        y := Round(loc.bar + g.btnDy * r.h)
        if (which = "confirm")
            return {x: this._ConfirmX(r), y: y}
        return {x: Round(r.x + g.cancelDx * r.w), y: y}
    }

    ; Closes the Selector with its X (Esc does not close it: it only opens
    ; the Roblox menu over it; live 2026-11-21). A prompt still up is
    ; cancelled first, a Roblox menu left by an Esc is closed. Never clicks
    ; without the window placed by a read. -> 1 closed, 0 still up / not
    ; placed, -1 halted
    _CloseSelectorX(ctx) {
        env := this._env
        r := this._SelRect()
        if !IsObject(r)
            return 0
        g := BiomeItemsTask.Geo
        Loop BiomeItemsTask.CloseTries {
            if this._MenuUp() {
                Input.Key("Esc", Input.TapHoldMs, env.io)
                if !env.Wait(BiomeItemsTask.InvMs, ctx)
                    return -1
            }
            if !this._SelectorUp()
                return 1
            loc := this._Locate(ctx)
            if ctx.ShouldStop()
                return -1
            if !IsObject(loc) {
                ; a window going (its close after Confirm / Cancel) still
                ; reads as up for a moment while its bar and rows no longer
                ; do: looked at again for FadeMs before it is reported
                g2 := this._Fading(ctx)
                if (g2 != 0)
                    return g2
                env.Log("biome items: the Biome Selector is up but could not be placed (its bar and rows did not read): not clicked")
                return 0
            }
            if env.BuyPrompt("biome items")
                return 0
            if RegExMatch(this._PromptText(loc), BiomeItemsTask.PromptRe) {
                env.Click(this._PromptBtn(loc, "cancel"))
                if !env.Wait(BiomeItemsTask.InvMs, ctx)
                    return -1
                continue                        ; placed again: the window moved meanwhile
            }
            xp := {x: Round(r.x + g.closeDx * r.w), y: Round(loc.row1 + g.closeDy * r.h)}
            this._closeTry := "bar " loc.bar ", X " xp.x "," xp.y
            env.Click(xp)
            if !env.Wait(BiomeItemsTask.InvMs, ctx)
                return -1
        }
        if !this._SelectorUp()
            return 1
        shot := HasMethod(env.io, "Shot") ? env.io.Shot() : ""
        env.Log("biome items: the Biome Selector did not close (" this._closeTry ")" (shot != "" ? "; screen saved to " shot : ""))
        return 0
    }

    ; The Selector up but not placed: gone within FadeMs (its close
    ; animation)? -> 1 gone, 0 still up, -1 halted
    static FadeMs := 2000
    static FadePollMs := 300
    _Fading(ctx) {
        env := this._env
        waited := 0
        while (waited < BiomeItemsTask.FadeMs) {
            if !env.Wait(BiomeItemsTask.FadePollMs, ctx)
                return -1
            waited += BiomeItemsTask.FadePollMs
            if !this._SelectorUp()
                return 1
        }
        return 0
    }

    ; After Confirm the Selector stays up a few seconds and closes by itself
    ; when the biome changes (live 2026-11-22..24: the biome changed ~4 s
    ; after Confirm; the tidy that looked at it while it went logged "is up
    ; but could not be placed" and the window was gone a moment later, and a
    ; tidy before it clicked its X). Waited for up to SelfCloseMs; still up
    ; then: closed by its X (_CloseSelectorX: placed by a read first).
    ; -> 1 gone, 0 still up, -1 halted
    static SelfCloseMs := 7000
    static SelfClosePollMs := 400
    _AfterConfirm(cctx) {
        env := this._env
        waited := 0
        while this._SelectorUp() {
            if (waited >= BiomeItemsTask.SelfCloseMs) {
                env.Log("biome items: the Biome Selector is still up " Round(waited / 1000, 1) " s after Confirm: closing it")
                return this._CloseSelectorX(cctx)
            }
            if !env.Wait(BiomeItemsTask.SelfClosePollMs, cctx)
                return -1
            waited += BiomeItemsTask.SelfClosePollMs
        }
        return 1
    }

    ; Use clicked (Selector: Drive confirmed): its own and the server
    ; cooldown start now.
    _Used(it) {
        now := this._env.Now()
        this._lastUse[it.key] := now
        if (it.HasProp("consumable") && it.consumable)
            this._runeSpent := true             ; one per night; no server cooldown
        else
            this._lastAny := now
        for m in [this._missing, this._holdMs, this._fails, this._screenTold]
            if m.Has(it.key)
                m.Delete(it.key)
        this._Save()
    }

    ; The Drive did not read after Use: nothing confirmed. Closes the
    ; Selector and the inventory instead of leaving them over the screen for
    ; the next task (2026-10-27 review); the Selector stays held for
    ; MissingRetryMin. -> 0, or -1 halted (F3 / pause)
    _NoDrive(c, it, drive, ctx) {
        env := this._env
        env.Log("biome items: " drive " not found in the Biome Selector list; nothing confirmed")
        r := this._CloseSelector(c, it, CleanupCtx(ctx))     ; a preempt still closes what Use opened
        if (r < 0)
            return -1
        ; not calibrated and not found on screen: it cannot be seen or closed
        placed := IsObject(this._SelRect())
        env.Report("errors", "Biome Selector: Drive not found", drive " was not read in the list (selector_list_rect); nothing confirmed"
            . (!placed ? ". The Selector's list was not found on screen: if it is still open, close it yourself (recording selector_list_rect on the Calibrate page helps)."
            : r ? "; the Selector and the inventory were closed." : ". The Selector is still open: close it yourself."), 0xE74C3C)
        return 0
    }

    ; Told to stop between the Selector's Use and Confirm: a preempt still
    ; closes the Selector and the inventory (quietly); a real halt (F3,
    ; pause) sends nothing more. -> -1
    _Cut(c, it, ctx) {
        if !CleanupCtx.Halted(ctx)
            this._CloseSelector(c, it, CleanupCtx(ctx))
        return -1
    }

    ; Closes the BIOME SELECTOR list, then the inventory (checked). There is
    ; no calibrated close for the Selector: Esc is tried, and when it only
    ; brought up the Roblox menu (Roblox keeps Esc), Esc again closes that
    ; menu. -> 1 closed, 0 the Selector still reads, -1 halted
    _CloseSelector(c, it, cctx) {
        env := this._env
        if (this._SelectorUp() && this._CloseSelectorX(cctx) < 0)
            return -1
        if (this._TileIs(this._Read(c.inv_tile1_rect), it) || env.InvOpen(c.inv_items_tab))
            env.CloseInv(c.inv_open, c.inv_items_tab, cctx)
        if cctx.ShouldStop()
            return -1
        return this._SelectorUp() ? 0 : 1
    }

    ; The BIOME SELECTOR list is on screen: a Drive's name reads in it.
    _SelectorUp() {
        r := this._SelRect()
        if !IsObject(r) {
            ; not calibrated and not found yet this run: looked for on screen
            ; (one read), only with the Selector switched on
            if !(IsObject(this._env.cfg) && this._env.cfg.Get("BiomeItems.biomeSelector", 0))
                return false
            r := AutoCal.Selector(this._env.Lines(), BiomeItemsTask.Drives)
            if !(IsObject(r) && this._DriveReads(r))
                return false
            this._selAuto := r
            return true
        }
        t := (this._env.ocrFn)(r.x, r.y, r.w, r.h)
        if BiomeItemsTask.ListOrPrompt(t)
            return true
        if (StrLen(Trim(t)) >= 8 && BiomeItemsTask.ListOrPrompt((this._env.ocrFn)(r.x, r.y, r.w, r.h, 2)))
            return true
        ; the prompt hides the rows: its bottom bar (below the list rect)
        g := BiomeItemsTask.Geo
        y := Round(r.y + g.barLo * r.h)
        return RegExMatch((this._env.ocrFn)(r.x, y, r.w, Round((g.barHi - g.barLo) * r.h) + Max(40, r.h // 10)), BiomeItemsTask.BarRe) > 0
    }

    ; The Roblox menu is open (its Resume button reads; Input.ResetChecks).
    _MenuUp() {
        m := Input.ResetChecks["menu"]
        return InStr(StrLower((this._env.ocrFn)(m.x, m.y, m.w, m.h)), m.text) > 0
    }

    ; Refused: log, close the inventory, hold the item for MissingRetryMin
    ; (2026-10-27 review: without the hold a refused item was picked again on
    ; every tick and fishing never ran). Overnight review: owning only the
    ; one-time Randomizer sent an errors webhook every 30 min all night, so
    ; each refusal in a row doubles the hold (up to MissingMaxMin) and only
    ; the first one sends the webhook; a use starts both over. screen: the
    ; screen stopped the try (a prompt, the inventory, a popup), not the
    ; item: ScreenRetryMin, the refusals in a row unchanged, the webhook only
    ; for the first such stop until a use. -> 0
    _Fail(c, it, why, screen := false) {
        env := this._env
        n := (this._fails.Has(it.key) ? this._fails[it.key] : 0) + (screen ? 0 : 1)
        this._fails[it.key] := n
        holdMin := screen ? BiomeItemsTask.ScreenRetryMin : Min(BiomeItemsTask.MissingRetryMin * 2 ** (n - 1), BiomeItemsTask.MissingMaxMin)
        this._missing[it.key] := env.Now()
        this._holdMs[it.key] := holdMin * 60000
        env.Log("biome items: " it.name " not used: " why " (next try in " Round(holdMin) " min)")
        first := screen ? !this._screenTold.Has(it.key) : (n = 1)
        if screen
            this._screenTold[it.key] := true
        if first
            env.Report("errors", "Biome item not used", it.name ": " why
                . ". Tried again later (back-off up to " BiomeItemsTask.MissingMaxMin " min, not reported again until it is used).", 0xE74C3C)
        if !Input.PurchaseUp(env.io, env.ocrFn)       ; a prompt that would not close: no more clicks
            env.CloseInv(c.inv_open, c.inv_items_tab)
        return 0
    }
}
