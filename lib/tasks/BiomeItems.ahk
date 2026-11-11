#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\TaskEnv.ahk
#Include %A_LineFile%\..\..\Biomes.ahk
#Include %A_LineFile%\..\..\GameLists.ahk
#Include %A_LineFile%\..\..\PotionSafety.ahk
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
;                                 Then Confirm (selector_confirm). Each use
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
;
; SETTINGS [BiomeItems]: enabled 0, biomeRandomizer 0, strangeController 0,
;   biomeSelector 0, selectorDrive "" (one of BiomeItemsTask.Drives).
; Calibration: inv_open, inv_items_tab, inv_search, inv_tile1_rect, inv_use,
;   inv_desc_rect (inv_tile2_rect optional), selector_list_rect +
;   selector_confirm for the Selector.
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
    static ServerCdMin := 20
    static CdMarginSec := 30
    static MissingRetryMin := 30     ; first hold; doubled per refusal in a row
    static MissingMaxMin := 240      ; longest hold
    ; "once" counts unless it is "once every / per / each" (a cooldown text)
    static Forbidden := "i)one[\s\-]*time|single[\s\-]*use|consumed|\bonce\b(?!\s+(?:every|per|each|a\b))"
    static InvMs := 700
    static SearchMs := 700
    static SearchTries := 3          ; typed search attempts (a dropped letter finds nothing)
    static SelectMs := 500
    static DescAgainMs := 400        ; between the two description reads
    static DescMinChars := 25        ; a shorter mustSay description = not drawn yet / cut
    static UseMs := 1500
    static PickMs := 800

    name := "biomeitems"
    priority := 5

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
        try PotionSafety._AtomicWrite(this._path, Json.Stringify(data) "`n")
        catch as err
            this._env.Log("biome items: could not write " this._path ": " err.Message)
    }

    static Forbid(text) => RegExMatch(String(text), BiomeItemsTask.Forbidden) ? true : false

    ; The selected item's description lets Use be clicked: no forbidden word
    ; in either read and, for an item with mustSay (the Randomizer), the two
    ; reads agree, are at least DescMinChars long and match mustSay.
    static DescIs(it, a, b) {
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
    static TileIs(text, word) => InStr(GameLists.Fold(text), GameLists.Fold(word)) && !BiomeItemsTask.Forbid(text)

    CanRun(state) {
        env := this._env
        if !(IsObject(env.cfg) && env.cfg.Get("BiomeItems.enabled", 0))
            return false
        if (IsObject(state) && state.HasProp("rareActive") && state.rareActive)
            return false
        biome := (IsObject(state) && state.HasProp("biome")) ? Trim(String(state.biome)) : ""
        ; overnight review: only rare=1 was refused, so PUMPKIN MOON (an event
        ; biome, rare 0) and any biome missing from biomes.json were changed
        ; away. Now it must be listed AND a normal biome (Biomes.Normal).
        b := Biomes.Find(env.cfg, biome)
        if (biome = "" || b["rare"] || !b["known"] || !Biomes.IsNormal(biome))
            return false                        ; unknown yet, rare, event or unlisted: never changed
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

    ; First enabled item off its cooldown, or "".
    _Ready(now) {
        env := this._env
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
                    env.Problem("selector:drive", "biome items: pick the Drive for the Biome Selector in Automate > Biome items: skipped")
                    continue
                }
                if !(IsObject(env.cal.Rect("selector_list_rect")) && IsObject(env.cal.Point("selector_confirm"))) {
                    env.Problem("cal:selector", "biome items: Biome Selector needs calibration steps selector_list_rect and selector_confirm: skipped")
                    continue
                }
            }
            return it
        }
        return ""
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
        it := this._Ready(env.Now())
        if !IsObject(it)
            return 0
        c := this._InvCal()
        if (c == "")
            return 0
        r := this._Use(it, c, ctx)
        ; told to stop part way: every wait returned -1 with the inventory
        ; still open over the next task. A preempt closes it first (checked,
        ; only while its tabs read); a halt sends nothing.
        if (r < 0 && !CleanupCtx.Halted(ctx) && env.InvOpen(c.inv_items_tab)) {
            env.Log("biome items: stopped with the inventory open: closing it first")
            env.CloseInv(c.inv_open, c.inv_items_tab, CleanupCtx(ctx))
        }
        return (r = 1) ? 1 : 0
    }

    ; The App's between-tasks check (Tidy): the Biome Selector list (Esc, the
    ; way _CloseSelector does; only while a Drive's name reads in it).
    Leftovers() {
        sel := {up: () => this._SelectorUp() ? "Biome Selector list" : ""
            , close: (label, ctx) => this._EscSelector(ctx)}
        return [sel]
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
            return this._Fail(c, it, "the Daily Rewards popup is over the game and was not closed: nothing clicked")
        ; Aura Collections left open covers the inventory (live 2026-11-02)
        r := Input.CloseCollections(ctx, io, env.ocrFn)
        if (r < 0)
            return -1
        if (r > 0)
            env.Log("biome items: the Aura Collections screen was open: " (r = 1 ? "closed it" : "it would not close"))
        if !env.InvOpen(c.inv_items_tab) {
            if ((why := this._Unsafe(c, false)) != "")
                return this._Fail(c, it, why)
            env.Click(c.inv_open)
            if !env.Wait(BiomeItemsTask.InvMs, ctx)
                return -1
        }
        if ((why := this._Unsafe(c)) != "")
            return this._Fail(c, it, why)
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
                return this._Fail(c, it, why)
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
                if BiomeItemsTask.TileIs(t, it.word)
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
                return this._Fail(c, it, why)
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
        if !BiomeItemsTask.TileIs(t, it.word)
            return this._Fail(c, it, "the tile changed before Use; Use not clicked")
        if ctx.ShouldStop()
            return -1
        if ((why := this._Unsafe(c)) != "")
            return this._Fail(c, it, why)
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
            p := this._PickDrive(drive, ctx)
            if (p < 0)
                return this._Cut(c, it, ctx)
            if (p = 0)
                return this._NoDrive(c, it, drive, ctx)
            if !env.Wait(BiomeItemsTask.PickMs, ctx)
                return this._Cut(c, it, ctx)
            if (env.BuyPrompt("biome items") || !this._SelectorUp()) {
                env.Log("biome items: a purchase prompt came up or the Biome Selector list is gone before Confirm: not confirmed")
                return this._NoDrive(c, it, drive, ctx)
            }
            env.Click(env.cal.Point("selector_confirm"))
            this._Used(it)
            if !env.Wait(BiomeItemsTask.UseMs, ctx)
                return -1
        }
        env.Log("biome items: used " it.name)
        env.Report("biome", "Biome item used", "Used **" it.name "**. Next one in " BiomeItemsTask.ServerCdMin " min (server cooldown).", 0x5865F2)
        if (BiomeItemsTask.TileIs(this._Read(c.inv_tile1_rect), it.word) || env.InvOpen(c.inv_items_tab))
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

    ; Finds `drive` in selector_list_rect by reading horizontal strips (the
    ; window bobs, so positions are read, not remembered), re-reads the
    ; strip, clicks its middle. Not in view: scroll the list down, try again.
    ; -> 1 clicked, 0 not found, -1 stopped.
    _PickDrive(drive, ctx) {
        env := this._env
        key := BiomeItemsTask.DriveKey(drive)
        r := env.cal.Rect("selector_list_rect")
        if (key = "" || !IsObject(r))
            return 0
        sh := Max(24, r.h // 9)                 ; about one row
        step := Max(8, sh // 3)
        Loop 2 {
            hits := []
            y := r.y
            while (y + sh <= r.y + r.h) {
                if ctx.ShouldStop()
                    return -1
                if InStr(StrLower((env.ocrFn)(r.x, y, r.w, sh)), key)
                    hits.Push(y)
                y += step
            }
            if (hits.Length > 0) {
                top := hits[1], bot := hits[1]
                for h in hits                   ; the first run of hits = the row
                    if (h - bot <= step)
                        bot := h
                cy := (top + bot) // 2
                if InStr(StrLower((env.ocrFn)(r.x, cy, r.w, sh)), key) {
                    if env.BuyPrompt("biome items")
                        return 0
                    env.Click({x: r.x + r.w // 2, y: cy + sh // 2})
                    return 1
                }
            }
            if (A_Index = 1) {                  ; below the fold: scroll the list
                env.io.MoveTo(r.x + r.w // 2, r.y + r.h // 2)
                Input.Wheel("down", 5, env.io)
                if !env.Wait(BiomeItemsTask.PickMs, ctx)
                    return -1
            }
        }
        return 0
    }

    ; Use clicked (Selector: Drive confirmed): its own and the server
    ; cooldown start now.
    _Used(it) {
        now := this._env.Now()
        this._lastUse[it.key] := now
        this._lastAny := now
        for m in [this._missing, this._holdMs, this._fails]
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
        env.Report("errors", "Biome Selector: Drive not found", drive " was not read in the list (selector_list_rect); nothing confirmed"
            . (r ? "; the Selector and the inventory were closed." : ". The Selector is still open: close it yourself."), 0xE74C3C)
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
        if (this._SelectorUp() && this._EscSelector(cctx) < 0)
            return -1
        if (BiomeItemsTask.TileIs(this._Read(c.inv_tile1_rect), it.word) || env.InvOpen(c.inv_items_tab))
            env.CloseInv(c.inv_open, c.inv_items_tab, cctx)
        if cctx.ShouldStop()
            return -1
        return this._SelectorUp() ? 0 : 1
    }

    ; The BIOME SELECTOR list is on screen: a Drive's name reads in it.
    _SelectorUp() {
        r := this._env.cal.Rect("selector_list_rect")
        if !IsObject(r)
            return false
        t := StrLower((this._env.ocrFn)(r.x, r.y, r.w, r.h))
        for d in BiomeItemsTask.Drives
            if InStr(t, BiomeItemsTask.DriveKey(d))
                return true
        return false
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
    ; the first one sends the webhook; a use starts both over. -> 0
    _Fail(c, it, why) {
        env := this._env
        n := (this._fails.Has(it.key) ? this._fails[it.key] : 0) + 1
        this._fails[it.key] := n
        holdMin := Min(BiomeItemsTask.MissingRetryMin * 2 ** (n - 1), BiomeItemsTask.MissingMaxMin)
        this._missing[it.key] := env.Now()
        this._holdMs[it.key] := holdMin * 60000
        env.Log("biome items: " it.name " not used: " why " (next try in " Round(holdMin) " min)")
        if (n = 1)
            env.Report("errors", "Biome item not used", it.name ": " why
                . ". Tried again later (back-off up to " BiomeItemsTask.MissingMaxMin " min, not reported again until it is used).", 0xE74C3C)
        if !Input.PurchaseUp(env.io, env.ocrFn)       ; a prompt that would not close: no more clicks
            env.CloseInv(c.inv_open, c.inv_items_tab)
        return 0
    }
}
