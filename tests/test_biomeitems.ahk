#Requires AutoHotkey v2.0
; Tests for lib\tasks\BiomeItems.ahk. Offline: fake IO, calibration, OCR, clock.
#Include ..\lib\tasks\BiomeItems.ahk

class BiIO {
    __New(ocr) {
        this.log := []
        this.ocr := ocr
        this.x := 0, this.y := 0
    }
    Down(k) {
        this.log.Push("down " k)
        this.ocr.Key(k)
    }
    Up(k) => this.log.Push("up " k)
    MoveTo(x, y) {
        this.x := x, this.y := y
        this.log.Push("move " x "," y)
    }
    ClickHere() {
        this.log.Push("click")
        this.ocr.Clicked(this.x, this.y)
    }
    Index(entry) {
        for i, e in this.log
            if (e = entry)
                return i
        return 0
    }
    Type(t) => this.log.Push("type " t)
    Wheel(dir, n := 1, gapMs := 25) {
        this.log.Push("wheel " dir " " n)
        this.ocr.Scroll(dir = "down" ? n : -n)
    }
    Wait(ms, ctx := "") => !(IsObject(ctx) && ctx.ShouldStop())
    Moved(x, y) {
        for e in this.log
            if (e = "move " x "," y)
                return true
        return false
    }
    Typed() {
        s := ""
        for e in this.log
            if (SubStr(e, 1, 5) = "type ")
                s .= SubStr(e, 6)
        return s
    }
}

; Inventory fake. tiles: the names shown in tile 1 / tile 2 after a search;
; desc: description per tile index (shown after that tile is clicked).
; Points: inv_open 10,10  items tab 20,20  search 30,30  use 40,40
; tile1 rect 100,100,80,40 (centre 140,120)  tile2 rect 200,100,80,40 (240,120)
; desc rect 300,300,200,60  confirm 600,600
; Biome Selector list rect 500,400,600,800: Drive i fills y 400+(i-1)*100
; .. +100 (Drive 9 is below the fold until the list is scrolled 100 px).
; The list is only up after Use on a Selector tile, until Confirm (or Esc
; when escCloses; else Esc toggles the Roblox menu, read in its menu box).
class BiOcr {
    __New(tiles, descs) {
        this.tiles := tiles
        this.descs := descs
        this.sel := 0
        this.open := false
        this.scrolled := 0
        this.strips := 0
        this.selector := false      ; the BIOME SELECTOR list is up
        this.menu := false          ; the Roblox menu (Esc)
        this.escCloses := true      ; Esc closes the Selector (else it opens the Roblox menu)
        this.useCloses := true      ; Use closes the inventory
        this.missing := ""          ; a Drive whose row never reads (OCR miss, none left)
        this.descReads := 0
        this.descFn := ""           ; (n) -> the n-th description read (one still drawing)
        this.coll := false          ; Aura Collections left open: covers the inventory button
        this.daily := false         ; the Daily Rewards popup is up
        this.dailyStuck := false    ; ... and its X does nothing
        this.prompt := false        ; a Roblox purchase prompt is up (Esc closes it)
        this.noOpen := false        ; the inventory button does nothing
    }
    Scroll(n) => this.scrolled := (n > 0) ? 100 : 0
    ; the Drive under screen y (or "")
    DriveAt(y) {
        i := (y - 400 + this.scrolled) // 100 + 1
        return (y >= 400 && y < 1200 && i >= 1 && i <= 9) ? BiomeItemsTask.Drives[i] : ""
    }
    Key(k) {
        if (k != "Esc")
            return
        if this.prompt {
            this.prompt := false
            return
        }
        if (this.selector && this.escCloses)
            this.selector := false
        else
            this.menu := !this.menu
    }
    Clicked(x, y) {
        if (x = 525 && y = 158)
            this.coll := false              ; Input.ResetCoords menuClose
        else if (x = Input.DailyX[1] && y = Input.DailyX[2])
            this.daily := this.dailyStuck
        else if (x = 10 && y = 10)
            this.open := !this.coll && !this.noOpen && !this.open
        else if (x = 140 && y = 120)
            this.sel := 1
        else if (x = 240 && y = 120)
            this.sel := 2
        else if (x = 40 && y = 40) {
            if (this.sel && this.tiles.Length >= this.sel && InStr(this.tiles[this.sel], "Selector"))
                this.selector := true
            if this.useCloses
                this.open := false          ; Use closes the inventory
        } else if (x = 600 && y = 600)
            this.selector := false          ; Confirm
    }
    Read(x, y, w, h) {
        r := x "," y "," w "," h
        if (x = 500 && w = 600) {               ; a strip of the Selector list: the Drive under its middle
            this.strips++
            d := this.selector ? this.DriveAt(y + h // 2) : ""
            return (d = this.missing) ? "" : d
        }
        cb := Input.ResetChecks["collection"]
        if (x = cb.x && y = cb.y)
            return this.coll ? "Aura Collections [Exit]" : ""
        db := Input.DailyBox
        if (x = db.x && y = db.y)
            return this.daily ? "noily Rewords" : ""
        mb := Input.ResetChecks["menu"]
        if (x = mb.x && y = mb.y)
            return this.menu ? "Resume Game" : ""
        pb := Input.PurchaseBox
        if (x = pb.x && y = pb.y)
            return this.prompt ? "Buy Robux and item`nR$1,000 Donation`nBuy $4.99" : ""
        if !this.open
            return ""
        if (r = "100,100,80,40")
            return this.tiles.Length >= 1 ? this.tiles[1] : ""
        if (r = "200,100,80,40")
            return this.tiles.Length >= 2 ? this.tiles[2] : ""
        if (r = "300,300,200,60" && IsObject(this.descFn))
            return (this.descFn)(++this.descReads)
        if (r = "300,300,200,60")
            return (this.sel && this.descs.Length >= this.sel) ? this.descs[this.sel] : ""
        if (r = "-70,-5,180,50")                ; the inventory's tabs, around inv_items_tab 20,20
            return "Gears   Items"
        return ""
    }
}

class BiCal {
    __New(extra := "") {
        pt := (x, y) => {x: x, y: y, color: 0}
        this.p := Map("inv_open", pt(10, 10), "inv_items_tab", pt(20, 20), "inv_search", pt(30, 30), "inv_use", pt(40, 40)
            , "selector_confirm", pt(600, 600))
        this.r := Map("inv_tile1_rect", {x: 100, y: 100, w: 80, h: 40}, "inv_tile2_rect", {x: 200, y: 100, w: 80, h: 40}
            , "inv_desc_rect", {x: 300, y: 300, w: 200, h: 60}, "selector_list_rect", {x: 500, y: 400, w: 600, h: 800})
        if (extra is Map)
            for k, v in extra
                if (v = "DEL")
                    this.p.Has(k) ? this.p.Delete(k) : this.r.Delete(k)
    }
    Point(id) => this.p.Has(id) ? this.p[id] : ""
    Rect(id) => this.r.Has(id) ? this.r[id] : ""
}

class BiCfg {
    __New(gets := "") {
        this.g := Map("BiomeItems.enabled", 1)
        if (gets is Map)
            for k, v in gets
                this.g[k] := v
    }
    Get(path, default := "") => this.g.Has(path) ? this.g[path] : default
    ; WINDY is a normal biome, GLITCHED and HEAVEN are marked rare, PUMPKIN
    ; MOON is an event biome (not rare in biomes.json)
    Data(name) => (name = "biomes") ? Map("biomes", [Map("name", "NORMAL", "rare", 0), Map("name", "WINDY", "rare", 0)
        , Map("name", "GLITCHED", "rare", 1), Map("name", "HEAVEN", "rare", 1), Map("name", "PUMPKIN MOON", "rare", 0)
        , Map("name", "SAND STORM", "rare", 0)]) : Map()
}

class BiWh {
    __New() {
        this.sent := []
    }
    Send(event, title, desc, color, opts := "") => this.sent.Push({event: event, title: title, desc: desc})
    Count(ev) {
        n := 0
        for s in this.sent
            n += (s.event = ev) ? 1 : 0
        return n
    }
}

BiState(biome := "NORMAL") {
    s := SchedState()
    s.biome := biome
    return s
}

; -> {t, io, ocr, wh, logs, clk, deps}. The state file is a fresh temp file;
; the wall clock (YYYYMMDDHHMMSS) follows clk.t, so a "restart" (a new task
; on the same deps) sees the time that passed.
BiMake(gets, tiles, descs, calExtra := "") {
    ocr := BiOcr(tiles, descs)
    io := BiIO(ocr)
    wh := BiWh()
    logs := []
    clk := {t: 10000000}
    path := A_Temp "\vesper_bi_test.json"
    for p in [path, path ".tmp"]
        try FileDelete(p)
    deps := {cfg: BiCfg(gets), io: io, webhook: wh, cal: BiCal(calExtra), log: (s) => logs.Push(s)
        , ocr: (x, y, w, h, scale := 1) => ocr.Read(x, y, w, h), now: () => clk.t
        , clock: () => DateAdd("20261102000000", clk.t // 1000, "Seconds"), statePath: path}
    t := BiomeItemsTask(deps)
    return {t: t, io: io, ocr: ocr, wh: wh, logs: logs, clk: clk, deps: deps}
}

Test_BiomeItems_OffByDefaultAndOnlyInNormal() {
    m := BiMake(Map("BiomeItems.enabled", 0, "BiomeItems.strangeController", 1), ["Strange Controller"], ["Changes the biome"])
    AssertEq(m.t.CanRun(BiState()), false, "off unless enabled")
    m := BiMake(Map("BiomeItems.strangeController", 1), ["Strange Controller"], ["Changes the biome"])
    AssertEq(m.t.CanRun(BiState()), true, "NORMAL + enabled item")
    AssertEq(m.t.CanRun(BiState("WINDY")), true, "any biome not marked rare")
    AssertEq(m.t.CanRun(BiState("HEAVEN")), false, "a biome the user marked rare: never changed")
    AssertEq(m.t.CanRun(BiState("")), false, "biome not known yet")
    ; overnight review: PUMPKIN MOON (rare 0) was changed away 12 s in
    AssertEq(m.t.CanRun(BiState("PUMPKIN MOON")), false, "an event biome: never changed")
    AssertEq(m.t.CanRun(BiState("AURORA")), false, "a biome missing from biomes.json: never changed")
    AssertEq(m.t.CanRun(BiState("sand  storm")), true, "a normal biome, any spacing / case")
    rare := BiState("GLITCHED")
    rare.rareActive := true
    AssertEq(m.t.CanRun(rare), false, "never in a rare biome")
    m2 := BiMake(Map(), ["Strange Controller"], ["x"])
    AssertEq(m2.t.CanRun(BiState()), false, "no item ticked")
    AssertEq(Sched.Priority["biomeitems"], 5, "scheduler priority")
    AssertTrue(Sched.RareBlocked.Has("biomeitems"), "blocked during rare biomes")
}

Test_Biomes_NormalAllowlist() {
    for n in ["NORMAL", "WINDY", "RAINY", "SNOWY", "SAND STORM", "HELL", "STARFALL", "CORRUPTION", "LOST FOREST", "HEAVEN"]
        AssertTrue(Biomes.IsNormal(n), "normal: " n)
    AssertTrue(Biomes.IsNormal(" lost   forest "), "normalized")
    for n in ["PUMPKIN MOON", "GRAVEYARD", "BLOOD RAIN", "GLITCHED", "NULL", "EGGLAND", "", "SOMETHING NEW"]
        AssertTrue(!Biomes.IsNormal(n), "not normal: '" n "'")
}

Test_BiomeItems_UsesTheItemAfterChecks() {
    m := BiMake(Map("BiomeItems.strangeController", 1), ["Strange Controller"], ["Use to change the biome. Usable once every 20 minutes."])
    AssertEq(m.t.Run(SchedCtx()), 1, "used")
    AssertEq(m.io.Typed(), "Strange Controller", "searched by name")
    AssertTrue(m.io.Moved(140, 120), "tile selected")
    AssertTrue(m.io.Moved(40, 40), "Use clicked")
    AssertEq(m.wh.Count("biome"), 1, "reported")
    ; cooldowns: own 20 min and the 20 min server cooldown
    AssertEq(m.t.CanRun(BiState()), false, "right after: server cooldown")
    m.clk.t += 20 * 60000
    AssertEq(m.t.CanRun(BiState()), false, "20:00: still inside the margin")
    m.clk.t += 31000
    AssertEq(m.t.CanRun(BiState()), true, "20:31: ready again")
}

Test_BiomeItems_ClosesAuraCollectionsLeftOpen() {
    m := BiMake(Map("BiomeItems.strangeController", 1), ["Strange Controller"], ["Use to change the biome. Usable once every 20 minutes."])
    m.ocr.coll := true
    AssertEq(m.t.Run(SchedCtx()), 1, "used")
    AssertTrue(m.io.Index("move 525,158") > 0 && m.io.Index("move 525,158") < m.io.Index("move 10,10"), "closed before the inventory")
    found := false
    for s in m.logs
        found := found || InStr(s, "Aura Collections")
    AssertTrue(found, "logged")
}

Test_BiomeItems_ClosesDailyRewardsBeforeTheInventory() {
    m := BiMake(Map("BiomeItems.strangeController", 1), ["Strange Controller"], ["Use to change the biome. Usable once every 20 minutes."])
    m.ocr.daily := true
    AssertEq(m.t.Run(SchedCtx()), 1, "used")
    x := m.io.Index("move " Input.DailyX[1] "," Input.DailyX[2])
    AssertTrue(x > 0 && x < m.io.Index("move 10,10"), "closed before the inventory")
    AssertTrue(!m.io.Moved(1280, 895), "its Claim never pressed")
    ; would not close: no inventory opened under it
    m := BiMake(Map("BiomeItems.strangeController", 1), ["Strange Controller"], ["Use to change the biome. Usable once every 20 minutes."])
    m.ocr.daily := true, m.ocr.dailyStuck := true
    AssertEq(m.t.Run(SchedCtx()), 0, "not used")
    AssertTrue(!m.io.Moved(10, 10), "the inventory not opened")
    AssertEq(m.wh.Count("errors"), 1, "reported")
}

Test_BiomeItems_SearchRetypedWhenALetterDrops() {
    ; the first search finds nothing ("Biome Rndomizer"), the retyped one does
    m := BiMake(Map("BiomeItems.biomeRandomizer", 1), [], ["Randomizes the biome. Usable once every 35 minutes."])
    starts := [0]
    m.io.DefineProp("Type", {call: (self, t) => (self.log.Push("type " t), (t = "B" && ++starts[1] >= 2) ? (m.ocr.tiles := ["Biome Randomizer"]) : 0)})
    AssertEq(m.t.Run(SchedCtx()), 1, "used after typing the search again")
    AssertEq(starts[1], 2, "typed twice")
    AssertTrue(m.io.Moved(40, 40), "Use clicked")
    AssertEq(m.wh.Count("errors"), 0, "no error")
    ; never found: typed SearchTries times, then the inventory is closed and checked
    m2 := BiMake(Map("BiomeItems.biomeRandomizer", 1), [], ["x"])
    m2.t.Run(SchedCtx())
    n := 0
    for e in m2.io.log
        n += (e = "type B") ? 1 : 0
    AssertEq(n, BiomeItemsTask.SearchTries, "typed SearchTries times")
    AssertEq(m2.ocr.open, false, "inventory closed in the end")
    AssertEq(m2.wh.Count("errors"), 1, "reported once")
}

Test_BiomeItems_GameFontTileStillMatches() {
    ; the game font draws "a" like "o": "Biome Rondomizer" is the item
    m := BiMake(Map("BiomeItems.biomeRandomizer", 1), ["Biome Rondomizer"], ["Randomizes the biome. Usable once every 35 minutes."])
    AssertEq(m.t.Run(SchedCtx()), 1, "used")
    AssertTrue(BiomeItemsTask.TileIs("Strange Contraller", "controller"), "controller folded")
    AssertTrue(!BiomeItemsTask.TileIs("One-time Biome Rondomizer", "randomizer"), "one-time still refused")
    ; nothing found: the report says what the tiles read
    m2 := BiMake(Map("BiomeItems.biomeRandomizer", 1), ["Lucky Potion"], ["x"])
    m2.t.Run(SchedCtx())
    found := false
    for s in m2.wh.sent
        found := found || InStr(s.desc, "Lucky Potion")
    AssertTrue(found, "the failure report names what was read")
}

Test_BiomeItems_NeverTheOneTimeRandomizer() {
    ; only the one-time Biome Randomizer is owned: nothing is used
    m := BiMake(Map("BiomeItems.biomeRandomizer", 1), ["One-time Biome Randomizer"], ["Spawns a biome."])
    AssertEq(m.t.Run(SchedCtx()), 0, "not used")
    AssertTrue(!m.io.Moved(40, 40), "Use NEVER clicked")
    AssertTrue(!m.io.Moved(140, 120), "the one-time tile is not even selected")
    AssertEq(m.wh.Count("errors"), 1, "reported")
    ; listed first, the reusable one second: the second tile is used
    m2 := BiMake(Map("BiomeItems.biomeRandomizer", 1), ["One time Biome Randomizer", "Biome Randomizer"], ["", "Randomizes the biome. Usable once every 35 minutes."])
    AssertEq(m2.t.Run(SchedCtx()), 1, "reusable one used")
    AssertTrue(m2.io.Moved(240, 120) && !m2.io.Moved(140, 120), "tile 2 selected, never tile 1")
    ; the description gives it away (tile text cut short): Use not clicked
    m3 := BiMake(Map("BiomeItems.biomeRandomizer", 1), ["Biome Randomizer"], ["A free Biome Randomizer. Can only be used once."])
    AssertEq(m3.t.Run(SchedCtx()), 0, "refused")
    AssertTrue(!m3.io.Moved(40, 40), "Use not clicked")
    m4 := BiMake(Map("BiomeItems.biomeRandomizer", 1), ["Biome Randomizer"], ["Single-use item. Spawns any biome."])
    AssertEq(m4.t.Run(SchedCtx()), 0, "single-use refused")
    for txt in ["One-time Biome Randomizer", "one time use", "single use", "consumed on use", "can be used once"]
        AssertTrue(BiomeItemsTask.Forbid(txt), "forbidden: " txt)
    for txt in ["Biome Randomizer", "usable once every 35 minutes", "Strange Controller"]
        AssertTrue(!BiomeItemsTask.Forbid(txt), "allowed: " txt)
}

Test_BiomeItems_MissingItemWaitsAndOrder() {
    ; Randomizer ticked but not owned: marked missing, the Controller goes next
    m := BiMake(Map("BiomeItems.biomeRandomizer", 1, "BiomeItems.strangeController", 1), [], [])
    AssertEq(m.t.Run(SchedCtx()), 0, "randomizer not found")
    AssertTrue(InStr(m.io.Typed(), "Biome Randomizer"), "randomizer tried first")
    m.ocr.tiles := ["Strange Controller"], m.ocr.descs := ["Changes the biome"]
    m.io.log := []
    AssertEq(m.t.Run(SchedCtx()), 1, "controller used while the randomizer is missing")
    AssertEq(m.io.Typed(), "Strange Controller", "controller searched")
}

Test_BiomeItems_SelectorPicksTheDriveFromTheList() {
    ; the Drive is found by reading the list, then Confirm
    m := BiMake(Map("BiomeItems.biomeSelector", 1, "BiomeItems.selectorDrive", "Unknown Void Drive"), ["Biome Selector"], ["Select a biome using a Drive"])
    AssertEq(m.t.Run(SchedCtx()), 1, "used")
    pick := "", iUse := 0, iPick := 0, iConf := 0
    for i, e in m.io.log {
        if (e = "move 40,40")
            iUse := i
        if RegExMatch(e, "^move 800,(\d+)$", &mm)
            iPick := i, pick := Integer(mm[1])
        if (e = "move 600,600")
            iConf := i
    }
    AssertTrue(iUse > 0 && iPick > iUse && iConf > iPick, "Use, then the Drive, then Confirm")
    AssertEq(m.ocr.DriveAt(pick), "Unknown Void Drive", "clicked inside the Unknown Void row (y " pick ")")
    wheels := 0
    for e in m.io.log
        wheels += (SubStr(e, 1, 6) = "wheel ") ? 1 : 0
    AssertEq(wheels, 0, "no scrolling needed")
    ; the last Drive is below the fold: the list is scrolled, then found
    m2 := BiMake(Map("BiomeItems.biomeSelector", 1, "BiomeItems.selectorDrive", "Angelic Hymn Drive"), ["Biome Selector"], ["x"])
    AssertEq(m2.t.Run(SchedCtx()), 1, "used after scrolling")
    scrolled := false, pick2 := 0
    for e in m2.io.log {
        scrolled := scrolled || (e = "wheel down 5")
        if RegExMatch(e, "^move 800,(\d+)$", &mm)
            pick2 := Integer(mm[1])
    }
    AssertTrue(scrolled, "scrolled down")
    AssertEq(m2.ocr.DriveAt(pick2), "Angelic Hymn Drive", "Angelic Hymn clicked")
    ; no Drive picked in settings / not calibrated: not eligible
    m3 := BiMake(Map("BiomeItems.biomeSelector", 1), ["Biome Selector"], ["x"])
    AssertEq(m3.t.CanRun(BiState()), false, "no Drive chosen -> not eligible")
    m4 := BiMake(Map("BiomeItems.biomeSelector", 1, "BiomeItems.selectorDrive", "Raging Gale Drive"), ["Biome Selector"], ["x"], Map("selector_list_rect", "DEL"))
    AssertEq(m4.t.CanRun(BiState()), false, "no list rect -> not eligible")
    m5 := BiMake(Map("BiomeItems.biomeSelector", 1, "BiomeItems.selectorDrive", "Raging Gale Drive"), ["Biome Selector"], ["x"], Map("selector_confirm", "DEL"))
    AssertEq(m5.t.CanRun(BiState()), false, "no confirm point -> not eligible")
    AssertEq(BiomeItemsTask.DriveKey("abyss curse drive"), "abyss", "drive key")
    AssertEq(BiomeItemsTask.DriveKey("Nonsense Drive"), "", "unknown drive")
    AssertEq(BiomeItemsTask.Drives.Length, 9, "nine Drives")
}

Test_BiomeItems_RefusedItemWaitsAndTile2IsTried() {
    ; 2026-10-27 review: the Season Pass one-time Randomizer (its tile reads
    ; plain "Biome Randomizer", its description refuses it) was picked again
    ; on every tick: inventory, search, refuse, errors webhook; no fishing
    m := BiMake(Map("BiomeItems.biomeRandomizer", 1), ["Biome Randomizer"], ["A free Biome Randomizer. Can only be used once."])
    AssertEq(m.t.Run(SchedCtx()), 0, "refused")
    AssertEq(m.t.CanRun(BiState()), false, "held after the refusal, not picked again at once")
    m.clk.t += BiomeItemsTask.MissingRetryMin * 60000 + 1000
    AssertEq(m.t.CanRun(BiState()), true, "tried again after MissingRetryMin")
    ; the description refuses tile 1: tile 2 is checked before giving up
    m2 := BiMake(Map("BiomeItems.biomeRandomizer", 1), ["Biome Randomizer", "Biome Randomizer"]
        , ["A free Biome Randomizer. Can only be used once.", "Randomizes the biome. Usable once every 35 minutes."])
    AssertEq(m2.t.Run(SchedCtx()), 1, "the reusable one in tile 2 used")
    i1 := m2.io.Index("move 140,120"), i2 := m2.io.Index("move 240,120"), iUse := m2.io.Index("move 40,40")
    AssertTrue(i1 > 0 && i2 > i1 && iUse > i2, "tile 1 refused by its description, tile 2 selected, then Use")
    AssertEq(m2.wh.Count("errors"), 0, "no error")
    ; an inventory step not calibrated: not eligible (fishing runs), told once
    m3 := BiMake(Map("BiomeItems.strangeController", 1), ["Strange Controller"], ["x"], Map("inv_desc_rect", "DEL"))
    Loop 5
        AssertEq(m3.t.CanRun(BiState()), false, "inventory not calibrated: not eligible (" A_Index ")")
    AssertEq(m3.wh.Count("errors"), 1, "reported once")
    AssertEq(m3.io.log.Length, 0, "nothing pressed")
}

Test_BiomeItems_RefusedAgainBacksOffAndReportsOnce() {
    ; overnight review: owning only the one-time Randomizer sent an errors
    ; webhook (and opened the inventory) every 30 min all night
    m := BiMake(Map("BiomeItems.biomeRandomizer", 1), ["Biome Randomizer"], ["A free Biome Randomizer. Can only be used once."])
    holds := []
    Loop 5 {
        AssertEq(m.t.Run(SchedCtx()), 0, "refused " A_Index)
        wait := 0
        while !m.t.CanRun(BiState()) && wait < 1000 {
            m.clk.t += 60000
            wait++
        }
        holds.Push(wait)
    }
    ; held 30, 60, 120, 240, 240 min (+ the minute the loop steps over)
    exp := [30, 60, 120, 240, 240]
    for i, w in holds
        AssertTrue(w >= exp[i] && w <= exp[i] + 1, "hold " i ": " w " min, expected " exp[i])
    AssertEq(m.wh.Count("errors"), 1, "the errors webhook only for the first refusal")
    ; used at last: the back-off and the report start over
    m.ocr.descs := ["Randomizes the biome. Usable once every 35 minutes."]
    AssertEq(m.t.Run(SchedCtx()), 1, "used")
    m.clk.t += 36 * 60000
    m.ocr.descs := ["Can only be used once."]
    AssertEq(m.t.Run(SchedCtx()), 0, "refused after a use")
    AssertEq(m.wh.Count("errors"), 2, "reported again after a use")
    m.clk.t += BiomeItemsTask.MissingRetryMin * 60000 + 1000
    AssertEq(m.t.CanRun(BiState()), true, "the hold is back to MissingRetryMin")
}

Test_BiomeItems_SelectorDriveNotFoundClosesAll() {
    ; 2026-10-27 review: Use opened the Selector, the Drive did not read, and
    ; the Selector and the inventory stayed over the screen for 20-60 min
    ; (the server cooldown had started although nothing was confirmed)
    m := BiMake(Map("BiomeItems.biomeSelector", 1, "BiomeItems.selectorDrive", "Unknown Void Drive"), ["Biome Selector"], ["Select a biome using a Drive"])
    m.ocr.missing := "Unknown Void Drive"
    m.ocr.useCloses := false                    ; the inventory stays behind the Selector
    AssertEq(m.t.Run(SchedCtx()), 0, "nothing confirmed")
    AssertTrue(m.io.Moved(40, 40) && !m.io.Moved(600, 600), "Use clicked, Confirm never")
    AssertEq(m.ocr.selector, false, "the Selector closed")
    AssertEq(m.ocr.open, false, "the inventory closed")
    AssertEq(m.ocr.menu, false, "no Roblox menu left open")
    AssertEq(m.wh.Count("errors"), 1, "reported")
    AssertEq(m.wh.Count("biome"), 0, "not reported as used")
    ; no server cooldown: another item may go at once; the Selector waits
    m.t._env.cfg.g["BiomeItems.strangeController"] := 1
    AssertEq(m.t.CanRun(BiState()), true, "no server cooldown started")
    AssertEq(m.t._Ready(m.clk.t).key, "strangeController", "the Selector is held, the Controller is next")
    ; Esc does not close it (it toggles the Roblox menu): the menu is closed
    ; again, the inventory is closed, and the report says the Selector is up
    m2 := BiMake(Map("BiomeItems.biomeSelector", 1, "BiomeItems.selectorDrive", "Unknown Void Drive"), ["Biome Selector"], ["x"])
    m2.ocr.missing := "Unknown Void Drive"
    m2.ocr.escCloses := false
    m2.ocr.useCloses := false
    AssertEq(m2.t.Run(SchedCtx()), 0, "nothing confirmed")
    AssertEq(m2.ocr.menu, false, "the Roblox menu Esc opened was closed again")
    AssertEq(m2.ocr.open, false, "the inventory closed")
    said := false
    for s in m2.wh.sent
        said := said || InStr(s.desc, "still open")
    AssertTrue(said, "the report says the Selector is still open")
    ; preempted between Use and Confirm: closed all the same, held, no cooldown
    m3 := BiMake(Map("BiomeItems.biomeSelector", 1, "BiomeItems.selectorDrive", "Unknown Void Drive"), ["Biome Selector"], ["x"])
    m3.ocr.useCloses := false
    ctx := SchedCtx()
    m3.io.DefineProp("ClickHere", {call: (self) => (BiIO.Prototype.ClickHere.Call(self), (self.x = 40 && self.y = 40) ? ctx.RequestPreempt() : 0)})
    AssertEq(m3.t.Run(ctx), 0, "preempted")
    AssertTrue(!m3.io.Moved(600, 600), "Confirm never clicked")
    AssertEq(m3.ocr.selector, false, "the Selector closed")
    AssertEq(m3.ocr.open, false, "the inventory closed")
    m3.t._env.cfg.g["BiomeItems.strangeController"] := 1
    AssertEq(m3.t._Ready(m3.clk.t).key, "strangeController", "no server cooldown; the Selector is held")
}

Test_BiomeItems_RandomizerNeedsItsOwnDescription() {
    ; 2026-11-01: the one-time Randomizer was used three times because an
    ; empty / not yet drawn description had no forbidden word in it. Use is
    ; only clicked when the description names the reusable one (its cooldown
    ; wording), is long enough and reads the same twice.
    good := "Randomizes the biome. Usable once every 35 minutes."
    for d in ["", "Biome", "every 35 min", "Randomizes the current biome into another one."] {
        m := BiMake(Map("BiomeItems.biomeRandomizer", 1), ["Biome Randomizer"], [d])
        AssertEq(m.t.Run(SchedCtx()), 0, "refused: '" d "'")
        AssertTrue(!m.io.Moved(40, 40), "Use not clicked: '" d "'")
        AssertEq(m.ocr.open, false, "inventory closed: '" d "'")
    }
    ; the report says what was read, to check it against the game
    said := false
    for s in m.wh.sent
        said := said || InStr(s.desc, "into another one")
    AssertTrue(said, "the report quotes the description read")
    ; the description is still drawing: the two reads differ
    m := BiMake(Map("BiomeItems.biomeRandomizer", 1), ["Biome Randomizer"], [good])
    m.ocr.descFn := (n) => (n = 1) ? "Randomizes the biome. Usable" : good
    AssertEq(m.t.Run(SchedCtx()), 0, "two reads that differ: refused")
    AssertTrue(!m.io.Moved(40, 40), "Use not clicked when the reads differ")
    AssertTrue(m.ocr.descReads >= 2, "the description was read twice")
    ; the reusable one: used
    m := BiMake(Map("BiomeItems.biomeRandomizer", 1), ["Biome Randomizer"], [good])
    AssertEq(m.t.Run(SchedCtx()), 1, "own description, twice the same: used")
    ; the real reusable one (the user's screenshot 2026-11-09), as OCR reads it
    real := "a fully functional dimension-manipulating device. changes the current biome regardless of natural spawnrate. *(except for rare biomes.) has a 1/5000 chance to spawn cyberspace."
    AssertTrue(BiomeItemsTask.DescIs(BiomeItemsTask.Items[1], real, StrReplace(real, "regardless", "regardiess")), "real text, two slightly different reads")
    AssertTrue(!BiomeItemsTask.DescIs(BiomeItemsTask.Items[1], "a fully functional dimension-manipulating device. changes the current biome of n", real), "the 21:24:35 read: cut before its last line")
    AssertTrue(!BiomeItemsTask.DescIs(BiomeItemsTask.Items[1], "One-time item. " real, "One-time item. " real), "the one-time wording still refuses")
    m := BiMake(Map("BiomeItems.biomeRandomizer", 1), ["Biome Randomizer"], [real])
    AssertEq(m.t.Run(SchedCtx()), 1, "the real reusable description: used")
    cd := "Cooldown: 35 minutes. Changes the current biome."
    AssertTrue(BiomeItemsTask.DescIs(BiomeItemsTask.Items[1], cd, cd), "cooldown wording")
    AssertTrue(!BiomeItemsTask.DescIs(BiomeItemsTask.Items[1], "One-time. " cd, "One-time. " cd), "a forbidden word still refuses")
    ; the other items keep the plain check (there is no one-time version)
    AssertTrue(BiomeItemsTask.DescIs(BiomeItemsTask.Items[2], "Changes the biome", "Changes the biome"), "controller: plain check")
}

Test_BiomeItems_CooldownsSurviveARestart() {
    ; 2026-11-01: the last-use times lived in memory, so every restart used
    ; the items again at once
    m := BiMake(Map("BiomeItems.biomeRandomizer", 1), ["Biome Randomizer"], ["Randomizes the biome. Usable once every 35 minutes."])
    AssertEq(m.t.Run(SchedCtx()), 1, "used")
    AssertTrue(FileExist(m.deps.statePath), "state file written")
    m.clk.t += 60000
    t2 := BiomeItemsTask(m.deps)                    ; the macro restarted
    AssertEq(t2.CanRun(BiState()), false, "after a restart: server cooldown kept")
    m.clk.t += 21 * 60000
    AssertEq(t2.CanRun(BiState()), false, "22 min: the Randomizer's own 35 min cooldown kept")
    m.clk.t += 13 * 60000 + 31000
    AssertEq(BiomeItemsTask(m.deps).CanRun(BiState()), true, "35:31: ready again")
    ; a broken file: nothing remembered, no error
    m2 := BiMake(Map("BiomeItems.strangeController", 1), ["Strange Controller"], ["x"])
    FileAppend("{garbage", m2.deps.statePath)
    AssertEq(BiomeItemsTask(m2.deps).CanRun(BiState()), true, "unreadable file: ready")
    try FileDelete(m2.deps.statePath)
}

; ---- no blind clicks (live 2026-11-02) ----------------------------------------

BiClicks(io) {
    n := 0
    for e in io.log
        n += (e = "click") ? 1 : 0
    return n
}

Test_BiomeItems_PurchasePromptClosedWithEscNeverClicked() {
    m := BiMake(Map("BiomeItems.strangeController", 1), ["Strange Controller"], ["Changes the biome"])
    m.ocr.prompt := true
    AssertEq(m.t.Run(SchedCtx()), 0, "not used")
    AssertEq(BiClicks(m.io), 0, "nothing clicked")
    AssertTrue(m.io.Index("down Esc") > 0, "closed with Esc")
    AssertTrue(!m.ocr.prompt, "the prompt is gone")
    found := false
    for x in m.wh.sent
        found := found || (x.event = "errors" && InStr(x.title, "Purchase prompt"))
    AssertTrue(found, "errors webhook")
    logged := false
    for l in m.logs
        logged := logged || InStr(l, "purchase prompt closed")
    AssertTrue(logged, "logged")
}

Test_BiomeItems_InventoryNotOpenNothingClickedInside() {
    m := BiMake(Map("BiomeItems.strangeController", 1), ["Strange Controller"], ["Changes the biome"])
    m.ocr.noOpen := true
    AssertEq(m.t.Run(SchedCtx()), 0, "not used")
    AssertEq(BiClicks(m.io), 1, "only the inventory button clicked")
    AssertTrue(!m.io.Moved(20, 20) && !m.io.Moved(30, 30) && !m.io.Moved(40, 40), "no tab, search or Use click")
    AssertTrue(InStr(m.wh.sent[1].desc, "inventory is not open"), "says why")
}

Test_BiomeItems_OpenInventoryIsNotClickedShut() {
    m := BiMake(Map("BiomeItems.strangeController", 1), ["Strange Controller"], ["Changes the biome"])
    m.ocr.open := true
    AssertEq(m.t.Run(SchedCtx()), 1, "used")
    AssertTrue(m.io.Index("move 20,20") < m.io.Index("move 10,10") || !m.io.Moved(10, 10), "its button not clicked before the tab (it would close it)")
}
