#Requires AutoHotkey v2.0
; Tests for lib\tasks\Potions.ahk (PotionsTask) and lib\BiomeEvents.ahk.
; Offline: fake game (IO + OCR + amount signature + calibration), temp usage
; file, fake clock. Every test asserts on the fake IO's click log.
#Include ..\lib\Json.ahk
#Include ..\lib\Config.ahk
#Include ..\lib\Scheduler.ahk
#Include ..\lib\PotionSafety.ahk
#Include ..\lib\Input.ahk
#Include ..\lib\Clip.ahk
#Include ..\lib\tasks\Potions.ahk
#Include ..\lib\BiomeEvents.ahk

; ---- helpers (names must not start with Test_) -----------------------------

PtItem(real, ocr, desc, count) {
    return {real: real, ocr: ocr, desc: desc, count: count}
}

; Fake game modelled on the 2026-10-25 recon:
; - inventory items; searching shows every item whose real name CONTAINS the
;   typed text, in item order ("Speed Potion" -> "Speed Potion L" first)
; - result tiles on a 136 px pitch; tile names OCR with the game font's
;   confusions ("Hoste" for "Haste"); a tile under the pointer OCRs ""
; - clicking a tile's name selects that item; the selected-item panel has
;   NO name, only the description box (OCR of inv_desc_rect)
; - the amount box (typed text) is read by OCR: a lone "1" reads as nothing;
;   with the pointer over the box the read is junk (cursor in the picture)
; - Use consumes consumeBy * amount of the SELECTED item; an item at count
;   0 leaves the results (only owned items are listed) and the selection
;   (2026-10-27 review); useLag > 0 delays the count change until that many
;   ms of non-stopped Wait have passed (the game updates it late)
; - the inventory is open or closed (inv_open toggles it, it opens on
;   Gears; closed: no tiles, no description, clicks in it do nothing, typed
;   text goes into the game world = worldText). Its Gears / Items tab labels
;   OCR around inv_items_tab while open. A click on inv_open while a text
;   box has focus only takes the focus off it (swallowClose; TaskEnv.CloseInv)
; - counts OCR as "x<n>" (countText can add confusable glyphs)
; Hooks: onOcr(kind, result) after each OCR (kind tile|count|desc), onSig()
; after each signature read, onUse() after each Use click.
class PtGame {
    __New() {
        this.log := []
        this.pts := Map(
            "inv_open", {x: 42, y: 685, color: 0},
            "inv_items_tab", {x: 1693, y: 448, color: 0},
            "inv_search", {x: 1400, y: 489, color: 0},
            "inv_use", {x: 917, y: 771, color: 0})
        this.rects := Map(
            "inv_tile1_rect", {x: 1076, y: 610, w: 112, h: 50},
            "inv_tile2_rect", {x: 1212, y: 610, w: 112, h: 50},
            "inv_count_rect", {x: 1100, y: 662, w: 92, h: 26},
            "inv_desc_rect", {x: 652, y: 815, w: 360, h: 60},
            "inv_amount_box", {x: 684, y: 752, w: 140, h: 40})
        this.sigs := Map()          ; an old inv_amount_empty recording (fallback for the box)
        ; Descriptions as OCR'd in the 2026-10-25 recon (R\desc.txt): sibling
        ; potions SHARE them (Speed Potion L reads "1 minute of [Quick Roll]"
        ; like Speed Potion; Lucky L like Lucky; the Heavenly family "[Heavenly]").
        quick := "Gives you 1 minute of [Quick Roll]`n[Quick Roll]: +10% Roll Speed"
        lucky := "Gives you 1 minute of [Lucky]`n[Lucky]: +25% Luck"
        heav := "Gives you [Heavenly]`n[Heavenly]: +150,000 Luck kir Next 1 Roll"
        this.items := [
            PtItem("Speed Potion L", "Speed`nPotion L", quick, 7),
            PtItem("Speed Potion", "Speed`nPotion", quick, 5),
            PtItem("Lucky Potion", "Lucky`nPotion", lucky, 5),
            PtItem("Lucky Potion L", "Lucky`nPotion L", lucky, 9),
            PtItem("Haste Potion I", "Hoste`nPotion I", "Gives you 5 minutes of [Haste II`n[Haste I]: +2096 Roll Speed", 4),
            PtItem("Heavenly Potion II", "Heavenly`nPotion II", heav, 2),
            PtItem("Heavenly Potion", "Heavenly`nPotion", heav, 3),
            PtItem("Godly Potion", "Godly`nPotion", "Gives you 4 hours of [Lord of the Sky]`n[Lord of the Sky]: +100% Luck", 29),
            PtItem("Godly Potion", "Godly`nPotion", "Gives you 4 hours of [Lord of Hell]`n[Lord of Hell]: +100% Luck", 4),
            PtItem("Godly Potion", "Godly`nPotion", "Gives you 4 hours of [Lord of the Sea]`n[Lord of the Sea]: -50% Luck, +75% Roll Speed", 5),
            PtItem("Godlike Potion", "Godlike`nPotion", "Drinking this potion blesses you with poværof 3 LORDS.`nGives you [Deification]`n[Deification]: +400,000 Luck Next 1 Roll", 1)]
        this.selected := ""         ; item Use acts on (object)
        this.selectFails := false   ; every tile click is dropped
        this.dropClicks := 0        ; drop the next N tile clicks
        this.dropTile := 0          ; drop every click on result tile N
        this.descGarble := 0        ; next N description reads return garbage
        this.descThrow := 0         ; next N description reads throw (OCR error)
        this.descEmpty := 0         ; next N description reads return "" (Ocr.Read failure)
        this.tab := "gears"         ; inventory opens on Gears; results only on Items
        this.noBackspace := false   ; amount box ignores Backspace
        this.typeTwice := false     ; amount box shows every typed char twice
        this.typed := ""            ; search box text
        this.searches := []         ; search box text after every typed char
        this.amount := "5"          ; amount box text (left over from a manual use)
        this.amountStuck := false   ; true: amount box ignores input
        this.focus := ""            ; "search" | "amount" | ""
        this.selAll := false
        this.ctrl := false
        this.nameFn := ""           ; (item) -> tile OCR text override
        this.countFn := ""          ; (item) -> count OCR text override
        this.consumeBy := 1
        this.open := false          ; inventory open
        this.swallowClose := true   ; inv_open click with a text box focused only unfocuses it
        this.worldText := ""        ; text typed with no box focused (into the game world)
        this.dropAmountClicks := 0  ; next N clicks on the amount box are swallowed
        this.elevenBlank := false   ; the narrow "11" OCRs as nothing (like a lone "1")
        this.useLag := 0            ; ms of Wait before a Use changes the count
        this.pendingUse := ""
        this.lagLeft := 0
        this.onOcr := ""
        this.onSig := ""
        this.onUse := ""
        this.mx := -1, this.my := -1
    }
    ; calibration
    Point(id) => this.pts.Has(id) ? this.pts[id] : ""
    Rect(id) => this.rects.Has(id) ? this.rects[id] : ""
    Sig(id) => this.sigs.Has(id) ? this.sigs[id] : ""
    ; search results / tiles
    Results() {
        out := []
        if (!this.open || Trim(this.typed) = "" || this.tab != "items")
            return out
        for it in this.items
            if (InStr(it.real, this.typed) && it.count > 0)
                out.Push(it)
        return out
    }
    ResultAt(k) {
        res := this.Results()
        return (k >= 1 && k <= res.Length) ? res[k] : ""
    }
    ; 1-based tile index whose name rect starts at x (pitch 136), else 0
    TileAt(x0, x) => (x >= x0 && Mod(x - x0, 136) = 0) ? (x - x0) // 136 + 1 : 0
    Over(r) => (this.mx >= r.x && this.mx <= r.x + r.w && this.my >= r.y && this.my <= r.y + r.h)
    ; io
    Down(k) {
        this.log.Push("down " k)
        if (k = "Ctrl")
            this.ctrl := true
        else if (k = "a" && this.ctrl)
            this.selAll := true
        else if (k = "Backspace" && this.noBackspace && this.focus = "amount") {
            this.selAll := false
        } else if (k = "Backspace" || k = "Delete") {
            if this.selAll
                this._SetField("")
            else if (k = "Backspace")
                this._SetField(SubStr(this._Field(), 1, -1))
            this.selAll := false
        }
    }
    Up(k) {
        this.log.Push("up " k)
        if (k = "Ctrl")
            this.ctrl := false
    }
    MoveTo(x, y) {
        this.mx := x, this.my := y
        this.log.Push("move " x "," y)
    }
    ClickHere() {
        this.log.Push("click " this.mx "," this.my)
        this.selAll := false
        onOpen := (this.mx = 42 && this.my = 685)
        onAmount := (this.mx = 754 && this.my = 772)
        if (onOpen && this.swallowClose && this.focus != "") {
            this.focus := ""                         ; only takes the focus off the box
            return
        }
        if (onAmount && this.dropAmountClicks > 0) {
            this.dropAmountClicks--
            this.focus := ""
            return
        }
        this.focus := !this.open ? "" : (this.mx = 1400 && this.my = 489) ? "search" : onAmount ? "amount" : ""
        if onOpen {
            this.open := !this.open
            if this.open
                this.tab := "gears"                  ; inventory opens on Gears
            return
        }
        if !this.open
            return                                   ; a click on the game world
        if (this.mx = 1693 && this.my = 448)
            this.tab := "items"
        if (this.my = 635) {
            k := this.TileAt(1132, this.mx)          ; tile name centre x = 1076 + 56
            it := this.ResultAt(k)
            drop := this.selectFails || (this.dropTile && k = this.dropTile)
            if (!drop && this.dropClicks > 0)
                this.dropClicks--, drop := true
            if (IsObject(it) && !drop)
                this.selected := it
        }
        if (this.mx = 917 && this.my = 771) {
            amt := IsInteger(this.amount) ? Integer(this.amount) : 1
            if IsObject(this.selected) {
                if (this.useLag > 0)
                    this.pendingUse := {it: this.selected, n: this.consumeBy * amt}, this.lagLeft := this.useLag
                else
                    this._Consume(this.selected, this.consumeBy * amt)
            }
            if IsObject(this.onUse)
                this.onUse.Call()
        }
    }
    _Consume(it, n) {
        it.count -= n
        if (it.count <= 0 && this.selected == it)
            this.selected := ""                      ; gone from the inventory
    }
    Text(s) {
        this.log.Push("text " s)
        if (this.focus = "") {
            this.worldText .= s                      ; no box focused: keys reach the game
            return
        }
        if (this.typeTwice && this.focus = "amount")
            s := s s
        this._SetField(this.selAll ? s : this._Field() s)
        this.selAll := false
    }
    _Field() => (this.focus = "search") ? this.typed : (this.focus = "amount") ? this.amount : ""
    _SetField(v) {
        if (this.focus = "search") {
            this.typed := v
            this.searches.Push(v)
        } else if (this.focus = "amount" && !this.amountStuck)
            this.amount := v
    }
    Wait(ms, ctx := "") {
        if (IsObject(ctx) && ctx.ShouldStop())
            return false                             ; no time passes
        if IsObject(this.pendingUse) {
            this.lagLeft -= ms
            if (this.lagLeft <= 0) {
                p := this.pendingUse, this.pendingUse := ""
                this._Consume(p.it, p.n)
            }
        }
        return true
    }
    ; ocr
    Ocr(r) {
        kind := "", res := ""
        if (r.x = 1603 && r.y = 423) {               ; tab labels around inv_items_tab
            kind := "tabs"
            res := this.open ? "Gears        Items" : ""
        } else if (r.y = 610) {
            kind := "tile"
            it := this.ResultAt(this.TileAt(1076, r.x))
            if (IsObject(it) && !this.Over(r))
                res := IsObject(this.nameFn) ? this.nameFn.Call(it) : it.ocr
        } else if (r.y = 662) {
            kind := "count"
            it := this.ResultAt(this.TileAt(1100, r.x))
            if IsObject(it)
                res := IsObject(this.countFn) ? this.countFn.Call(it) : "x" it.count
        } else if (r.x = 652) {
            kind := "desc"
            if (this.descThrow > 0) {
                this.descThrow--
                throw Error("simulated OCR failure")
            }
            if (this.open && IsObject(this.selected) && !this.Over(r))
                res := this.selected.desc
            if (this.descEmpty > 0)
                this.descEmpty--, res := ""
            if (this.descGarble > 0)
                this.descGarble--, res := "Gxv3s y0u 1 m!nute"
        }
        if IsObject(this.onOcr)
            this.onOcr.Call(kind, res)
        return res
    }
    ; what OCR reads in the amount box: a lone "1" never OCRs (""), the
    ; pointer drawn over the box reads as junk
    AmountOcr(r) {
        res := this.Over(r) ? "8|" : (this.amount = "1" || (this.elevenBlank && this.amount = "11")) ? "" : this.amount
        if IsObject(this.onSig)
            this.onSig.Call()
        return res
    }
    UseClicks() {
        n := 0
        for v in this.log
            if (v = "click 917,771")
                n++
        return n
    }
    AnyClicks() {
        n := 0
        for v in this.log
            if (SubStr(v, 1, 6) = "click ")
                n++
        return n
    }
    Searched(text) {
        for v in this.searches
            if (v == text)
                return true
        return false
    }
    Item(real, nth := 1) {
        for it in this.items
            if (it.real == real && --nth = 0)
                return it
        return ""
    }
}

; text in any embed field (name or value) of a recorded Send
PtFieldsHave(s, text) {
    f := Webhook._Opt(s.opts, "fields", "")
    if !(f is Array)
        return false
    for x in f {
        if (InStr(x["name"], text) || InStr(x["value"], text))
            return true
    }
    return false
}

class PtWh {
    __New() {
        this.sent := []
    }
    Send(ev, title, desc, color, opts := "") => this.sent.Push({event: ev, title: title, desc: desc, opts: opts})
    Count(ev) {
        n := 0
        for s in this.sent
            if (s.event = ev)
                n++
        return n
    }
    Has(ev, text) {
        for s in this.sent
            if (s.event = ev && (InStr(s.title, text) || InStr(s.desc, text) || PtFieldsHave(s, text)))
                return true
        return false
    }
}

class PtState {
    __New() {
        this.rareActive := false
        this.biome := ""
        this.rareTs := ""
    }
}

; Safety double whose Record always throws (simulates a failed persist).
class PtThrowSafety extends PotionSafety {
    Record(potion, eventKey) {
        throw Error("simulated record failure")
    }
}

; Safety double that runs a hook right after a successful Record.
class PtHookSafety extends PotionSafety {
    static afterRecord := ""
    Record(potion, eventKey) {
        super.Record(potion, eventKey)
        if IsObject(PtHookSafety.afterRecord)
            PtHookSafety.afterRecord.Call()
    }
}

PtTmpDir() {
    d := A_Temp "\vesper_pottest_" A_TickCount "_" Random(100000, 999999)
    DirCreate(d)
    return d
}

PtEntry(id, name, desc, locked := 0, perBiome := 2) {
    return Map("id", id, "name", name, "desc", desc, "locked", locked, "perBiome", perBiome, "perDay", 10, "perRun", 10)
}

PtPotCfg(lockedSpeed := 0, perBiome := 2, luckyDesc := "[Lucky]") {
    return Map("potions", [
        PtEntry("Lucky Potion", "Lucky Potion", luckyDesc, 0, perBiome),
        PtEntry("Speed Potion", "Speed Potion", "Quick Roll", lockedSpeed, perBiome),
        PtEntry("Haste Potion I", "Haste Potion I", "[Haste I]:", 0, perBiome),
        PtEntry("Godly Potion (Sky)", "Godly Potion", "Lord of the Sky", 0, perBiome),
        PtEntry("Godly Potion (Sea)", "Godly Potion", "Lord of the Sea", 0, perBiome),
        PtEntry("Godly Potion (Hell)", "Godly Potion", "Lord of Hell", 0, perBiome)])
}

; Bundle: cfg (temp dir), safety, game, wh, state, task. dryRun 0 unless given.
; opts: dryRun, qty1, qty2, list (biome potion list), perBiome, lockedSpeed,
;       luckyDesc, safetyClass, potCfg (replaces PtPotCfg), usageText
;       (written to the usage file before the safety loads)
class PtRig {
    __New(opts := "") {
        o := IsObject(opts) ? opts : Map()
        g := (k, d) => o.Has(k) ? o[k] : d
        this.dir := PtTmpDir()
        this.cfg := Config.Load(this.dir)
        this.cfg.Set("General.dryRun", g("dryRun", 0))
        list := g("list", [Map("name", "Lucky Potion", "qty", g("qty1", 1)), Map("name", "Speed Potion", "qty", g("qty2", 1))])
        this.cfg.SetData("biomes", Map("biomes", [
            Map("name", "NORMAL", "rare", 0, "potions", []),
            Map("name", "GLITCHED", "rare", 1, "potions", list)]))
        this.usage := this.dir "\data\potion_usage.json"
        if (g("usageText", "") != "") {
            DirCreate(this.dir "\data")
            FileAppend(g("usageText", ""), this.usage, "UTF-8-RAW")
        }
        cls := g("safetyClass", PotionSafety)
        pc := g("potCfg", "")
        if !IsObject(pc)
            pc := PtPotCfg(g("lockedSpeed", 0), g("perBiome", 2), g("luckyDesc", "[Lucky]"))
        this.safety := cls(pc, this.usage, () => "20261024")
        this.game := PtGame()
        this.wh := PtWh()
        this.logs := []
        this.state := PtState()
        this.state.biome := "GLITCHED"
        this.state.rareActive := true
        this.state.rareTs := "2026-10-24T10:00:00.000Z"
        this.ctx := SchedCtx()
        this.front := true          ; Roblox is the foreground window
        this.task := PotionsTask(Map(
            "cfg", this.cfg, "safety", this.safety, "wh", this.wh,
            "log", (t) => this.logs.Push(t), "io", this.game,
            "ocr", (r, scale := 1) => this.game.Ocr(r), "cal", this.game, "state", this.state,
            "amount", (r) => this.game.AmountOcr(r),
            "active", () => this.front,
            "poll", () => 0))
        this.key := "GLITCHED|2026-10-24T10:00:00.000Z"
    }
    Run() {
        this.task.Queue("GLITCHED", "2026-10-24T10:00:00.000Z")
        AssertTrue(this.task.CanRun(this.state), "queued task can run")
        this.task.Run(this.ctx)
        AssertTrue(!this.task.CanRun(this.state), "task consumed its event")
    }
    BiomeUses(potion) {
        if !FileExist(this.usage)
            return 0
        u := Json.Parse(FileRead(this.usage, "UTF-8"))
        for k, m in u["biome"]
            if m.Has(potion)
                return m[potion]
        return 0
    }
    Count(real, nth := 1) => this.game.Item(real, nth).count
    Done() {
        PtHookSafety.afterRecord := ""
        try DirDelete(this.dir, true)
    }
}

PtEv(type, name, ts, live) {
    ev := LogWatchEventLike()
    ev["type"] := type, ev["name"] := name, ev["ts"] := ts, ev["live"] := live
    return ev
}

class LogWatchEventLike extends Map {
}

; BiomeEvents rig with fakes for screenshot / sound / clip / potions task.
class PtBioRig {
    __New() {
        this.dir := PtTmpDir()
        this.cfg := Config.Load(this.dir)
        this.wh := PtWh()
        this.state := PtState()
        this.shots := 0, this.sounds := [], this.clips := [], this.queued := [], this.logs := []
        this.potions := {Queue: (self, b, ts) => this.queued.Push(b "|" ts)}
        this.clip := {Trigger: (self, r) => this.clips.Push(r)}
        this.be := BiomeEvents(Map(
            "cfg", this.cfg, "state", this.state, "wh", this.wh, "potions", this.potions,
            "log", (t) => this.logs.Push(t),
            "shotFn", () => (this.shots++, ""),
            "soundFn", (s) => this.sounds.Push(s),
            "clip", this.clip))
    }
    Done() {
        try DirDelete(this.dir, true)
    }
}

; ---- BiomeEvents -----------------------------------------------------------

Test_Pt_LiveFalseNeverTriggers() {
    r := PtBioRig()
    try {
        r.be.Handle(PtEv("biome", "GLITCHED", "2026-10-24T09:00:00.000Z", false))
        AssertEq(r.state.biome, "GLITCHED", "backfill sets state.biome")
        AssertEq(r.state.rareActive, false, "backfill does not set rareActive")
        AssertEq(r.queued.Length, 0, "no potions queued from backfill")
        AssertEq(r.wh.sent.Length, 0, "no webhook from backfill")
        AssertEq(r.clips.Length, 0, "no clip from backfill")
        AssertEq(r.sounds.Length, 0, "no sound from backfill")
        AssertEq(r.shots, 0, "no screenshot from backfill")
        ; aura events with live=false also do nothing
        r.cfg.Set("Medal.onRareAura", 1)
        r.cfg.Set("Medal.auras", "Gargantua")
        r.be.Handle(PtEv("aura", "Gargantua", "2026-10-24T09:00:01.000Z", false))
        AssertEq(r.clips.Length, 0, "no aura clip from non-live event")
    } finally
        r.Done()
}

Test_Pt_LiveRareAlertsAndQueues() {
    r := PtBioRig()
    try {
        r.be.Handle(PtEv("biome", "GLITCHED", "2026-10-24T10:00:00.000Z", true))
        AssertEq(r.state.biome, "GLITCHED", "state.biome")
        AssertEq(r.state.rareActive, true, "rareActive set")
        AssertEq(r.state.rareTs, "2026-10-24T10:00:00.000Z", "rareTs = event ts")
        AssertEq(r.wh.Count("biome"), 0, "rare biome: only the rare message, no Started card")
        AssertEq(r.wh.Count("rare"), 1, "rare webhook")
        for s in r.wh.sent
            if (s.event = "rare")
                AssertTrue(s.opts.mention = true && s.opts.HasProp("screenshot"), "rare webhook has mention + screenshot opt")
        AssertEq(r.shots, 1, "screenshot taken")
        AssertEq(r.sounds.Length, 1, "sound played")
        AssertEq(r.sounds[1], "*48", "default system sound")
        AssertEq(r.clips.Length, 1, "clip triggered")
        AssertEq(r.clips[1], "rare", "clip reason rare")
        AssertEq(r.queued.Length, 1, "potions queued")
        AssertEq(r.queued[1], "GLITCHED|2026-10-24T10:00:00.000Z", "queued with event ts")
        ; unknown biome: normal biome report, clears rareActive
        r.be.Handle(PtEv("biome", "SOMETHING NEW", "2026-10-24T10:05:00.000Z", true))
        AssertEq(r.state.rareActive, false, "non-rare clears rareActive")
        AssertEq(r.state.rareTs, "", "non-rare clears rareTs")
        AssertEq(r.state.biome, "SOMETHING NEW", "unknown biome tolerated")
        AssertEq(r.wh.Count("biome"), 2, "unknown biome reported (GLITCHED ended, new one started; GLITCHED had only its rare message)")
        AssertEq(r.wh.Count("rare"), 1, "no extra rare webhook")
        AssertEq(r.queued.Length, 1, "nothing more queued")
        ; LOST FOREST known non-rare
        r.be.Handle(PtEv("biome", "LOST FOREST", "2026-10-24T10:06:00.000Z", true))
        AssertEq(r.wh.Count("rare"), 1, "LOST FOREST not rare")
        ; backfill non-rare also clears rareActive
        r.state.rareActive := true
        r.be.Handle(PtEv("biome", "NORMAL", "2026-10-24T10:07:00.000Z", false))
        AssertEq(r.state.rareActive, false, "backfill non-rare clears rareActive")
    } finally
        r.Done()
}

Test_Pt_JoinLinkNeverLogged() {
    r := PtBioRig()
    try {
        link := "https://www.roblox.com/share?code=SECRETCODE123&type=Server"
        r.cfg.Set("General.privateServer", link)
        r.cfg.Set("General.joinButton", 1)
        r.be.Handle(PtEv("biome", "DREAMSPACE", "2026-10-24T11:00:00.000Z", true))
        found := false
        for s in r.wh.sent
            if (s.event = "rare" && (InStr(s.desc, link) || PtFieldsHave(s, link)))
                found := true
        AssertTrue(found, "join link in rare webhook")
        for t in r.logs
            AssertTrue(!InStr(t, "SECRETCODE123"), "link never logged")
        ; joinButton off -> no link
        r.cfg.Set("General.joinButton", 0)
        r.be.Handle(PtEv("biome", "NORMAL", "2026-10-24T11:01:00.000Z", true))
        r.be.Handle(PtEv("biome", "CYBERSPACE", "2026-10-24T11:02:00.000Z", true))
        n := 0
        for s in r.wh.sent
            if (InStr(s.desc, "SECRETCODE123") || PtFieldsHave(s, "SECRETCODE123"))
                n++
        AssertEq(n, 1, "link only when joinButton=1 (the rare alert)")
    } finally
        r.Done()
}

Test_Pt_AuraClipOnlyListed() {
    Auras.QuietUntil := 0                          ; no aura swap test window left over
    r := PtBioRig()
    try {
        r.cfg.Set("Medal.onRareAura", 1)
        r.cfg.Set("Medal.auras", "Gargantua, Abyssal Hunter")
        r.be.Handle(PtEv("aura", "Common", "2026-10-24T12:00:00.000Z", true))
        AssertEq(r.clips.Length, 0, "unlisted aura ignored")
        r.be.Handle(PtEv("aura", "Abyssal Hunter", "2026-10-24T12:00:01.000Z", true))
        AssertEq(r.clips.Length, 1, "listed aura clips")
        AssertEq(r.clips[1], "aura:Abyssal Hunter", "aura reason")
        r.cfg.Set("Medal.onRareAura", 0)
        r.be.Handle(PtEv("aura", "Gargantua", "2026-10-24T12:00:02.000Z", true))
        AssertEq(r.clips.Length, 1, "onRareAura=0 -> no clip")
    } finally
        r.Done()
}

; ---- PotionsTask -----------------------------------------------------------

Test_Pt_RealRunUsesAndRecords() {
    r := PtRig(Map("qty1", 2))
    try {
        r.Run()
        AssertEq(r.game.UseClicks(), 3, "2 Lucky + 1 Speed use clicks")
        AssertEq(r.Count("Lucky Potion"), 3, "lucky consumed 2")
        AssertEq(r.Count("Speed Potion"), 4, "speed consumed 1")
        ; "Speed Potion" search shows "Speed Potion L" FIRST: never touched
        AssertEq(r.Count("Speed Potion L"), 7, "wrong first tile untouched")
        AssertEq(r.Count("Lucky Potion L"), 9, "Lucky L untouched")
        AssertEq(r.BiomeUses("Lucky Potion"), 2, "lucky recorded 2")
        AssertEq(r.BiomeUses("Speed Potion"), 1, "speed recorded 1")
        AssertEq(r.wh.Count("potions"), 3, "one potions webhook per use")
        AssertTrue(r.wh.Has("potions", "5 -> 4"), "counts before/after reported")
        AssertEq(r.wh.Count("errors"), 0, "no errors")
        AssertTrue(r.game.Searched("Speed Potion"), "typed the exact tile name")
        u := Json.Parse(FileRead(r.usage, "UTF-8"))
        AssertEq(u["events"]["GLITCHED|2026-10-24T10:00:00.000Z"], 2, "event marked done")
        ; same event again: never used twice
        r.task.Queue("GLITCHED", "2026-10-24T10:00:00.000Z")
        r.task.Run(r.ctx)
        AssertEq(r.game.UseClicks(), 3, "re-queued event never clicks")
    } finally
        r.Done()
}

Test_Pt_SearchTypedPerChar() {
    r := PtRig(Map("list", [Map("name", "Lucky Potion", "qty", 1)]))
    try {
        r.game.selected := r.game.Item("Godlike Potion")    ; readable other description: no priming search
        r.Run()
        n := 0
        for v in r.game.log
            if (SubStr(v, 1, 5) = "text ")
                n++, AssertEq(StrLen(v), 6, "one char per text call: " v)
        AssertEq(n, StrLen("Lucky Potion") + 1, "search chars + the amount '1'")
    } finally
        r.Done()
}

Test_Pt_DryRunNeverClicksUseNorRecords() {
    r := PtRig(Map("dryRun", 1))
    try {
        r.Run()
        AssertEq(r.game.UseClicks(), 0, "dry run: no Use click")
        AssertEq(r.BiomeUses("Lucky Potion") + r.BiomeUses("Speed Potion"), 0, "dry run: no Record")
        AssertEq(r.Count("Lucky Potion"), 5, "nothing consumed")
        AssertTrue(r.wh.Has("potions", "would use"), "dry run reports what would be used")
        AssertTrue(r.wh.Has("potions", "[Quick Roll]"), "dry report shows the description read")
    } finally
        r.Done()
    ; [Potions] dryRun alone also blocks
    r := PtRig(Map("dryRun", 0))
    try {
        r.cfg.Set("Potions.dryRun", 1)
        r.Run()
        AssertEq(r.game.UseClicks(), 0, "[Potions] dryRun: no Use click")
        AssertEq(r.BiomeUses("Lucky Potion"), 0, "[Potions] dryRun: no Record")
    } finally
        r.Done()
}

Test_Pt_TileNotFoundNoClick() {
    r := PtRig()
    try {
        r.game.nameFn := (it) => it.ocr " II"      ; every tile reads a different name
        r.Run()
        AssertEq(r.game.UseClicks(), 0, "no exact tile: no Use click")
        AssertEq(r.BiomeUses("Lucky Potion"), 0, "no Record")
        AssertTrue(r.wh.Has("potions", "tile_not_found"), "skip reported")
        AssertTrue(r.wh.Count("errors") >= 1, "errors webhook")
        AssertTrue(!IsObject(r.game.selected), "no tile even selected")
    } finally
        r.Done()
}

Test_Pt_TileNameChangedNoClick() {
    ; the tile found by the scan reads differently on the per-click re-check
    r := PtRig(Map("list", [Map("name", "Lucky Potion", "qty", 1)]))
    try {
        n := 0
        r.game.selected := r.game.Item("Godlike Potion")    ; no priming: tile reads stay countable
        r.game.nameFn := (it) => (++n > 2) ? "Lucky Potion XL" : it.ocr
        r.Run()
        AssertEq(r.game.UseClicks(), 0, "name changed: no Use click")
        AssertTrue(r.wh.Has("potions", "name_mismatch"), "skip reported")
    } finally
        r.Done()
}

Test_Pt_ConfusableTileNameAndCountUsed() {
    ; "Hoste Potion I" tile, count "xS" (S for 5 in the game font)
    r := PtRig(Map("list", [Map("name", "Haste Potion I", "qty", 1)]))
    try {
        r.game.Item("Haste Potion I").count := 5
        r.game.countFn := (it) => "x" StrReplace(String(it.count), "5", "S")
        r.Run()
        AssertEq(r.game.UseClicks(), 1, "Hoste tile matched Haste Potion I")
        AssertEq(r.Count("Haste Potion I"), 4, "consumed one")
        AssertTrue(r.wh.Has("potions", "5 -> 4"), "confusable count read as 5")
        AssertEq(r.wh.Count("errors"), 0, "no errors")
    } finally
        r.Done()
}

Test_Pt_GodlySeaChosenByDescription() {
    ; three tiles named "Godly Potion" (Sky, Hell, Sea): only Sea may be used
    r := PtRig(Map("list", [Map("name", "Godly Potion (Sea)", "qty", 1)]))
    try {
        r.Run()
        AssertEq(r.game.UseClicks(), 1, "one Use click")
        AssertEq(r.Count("Godly Potion", 3), 4, "Sea consumed")
        AssertEq(r.Count("Godly Potion", 1), 29, "Sky untouched")
        AssertEq(r.Count("Godly Potion", 2), 4, "Hell untouched")
        AssertEq(r.BiomeUses("Godly Potion (Sea)"), 1, "recorded under the Sea id")
        AssertEq(r.BiomeUses("Godly Potion (Sky)"), 0, "Sky not recorded")
        AssertEq(r.wh.Count("errors"), 0, "no errors")
    } finally
        r.Done()
    ; Sky: the first tile
    r := PtRig(Map("list", [Map("name", "Godly Potion (Sky)", "qty", 1)]))
    try {
        r.Run()
        AssertEq(r.Count("Godly Potion", 1), 28, "Sky consumed")
        AssertEq(r.Count("Godly Potion", 3), 5, "Sea untouched")
    } finally
        r.Done()
}

Test_Pt_GodlyNoDescMatchAmbiguousNoClick() {
    r := PtRig(Map("list", [Map("name", "Godly Potion (Sea)", "qty", 1)]))
    try {
        r.game.Item("Godly Potion", 3).desc := "Gives you 4 hours of [Lord of the Sky]"   ; two Sky, no Sea
        r.Run()
        AssertEq(r.game.UseClicks(), 0, "no tile has the Sea description: no Use click")
        AssertTrue(r.wh.Has("potions", "select_unverified"), "reported (no proven selection: stop all)")
        AssertEq(r.BiomeUses("Godly Potion (Sea)"), 0, "no Record")
    } finally
        r.Done()
    ; two tiles with the Sea description -> ambiguous, skipped
    r := PtRig(Map("list", [Map("name", "Godly Potion (Sea)", "qty", 1)]))
    try {
        r.game.Item("Godly Potion", 1).desc := r.game.Item("Godly Potion", 3).desc
        r.Run()
        AssertEq(r.game.UseClicks(), 0, "two Sea tiles: no Use click")
        AssertTrue(r.wh.Has("potions", "tile_ambiguous"), "ambiguous reported")
    } finally
        r.Done()
}

Test_Pt_AmbiguousTilesNoClick() {
    ; two tiles both read "Lucky Potion" with the same description
    r := PtRig(Map("list", [Map("name", "Lucky Potion", "qty", 1)]))
    try {
        r.game.items.InsertAt(1, PtItem("Lucky Potion", "Lucky`nPotion", "Gives you 1 minute of [Lucky]", 8))
        r.Run()
        AssertEq(r.game.UseClicks(), 0, "two exact tiles: no Use click")
        AssertTrue(r.wh.Has("potions", "tile_ambiguous"), "reported")
        AssertTrue(r.wh.Count("errors") >= 1, "errors webhook")
    } finally
        r.Done()
}

Test_Pt_EmptyDescNeverUsedWhenNotDry() {
    r := PtRig(Map("list", [Map("name", "Lucky Potion", "qty", 1)], "luckyDesc", ""))
    try {
        r.Run()
        AssertEq(r.game.UseClicks(), 0, "empty desc: no Use click")
        AssertEq(r.game.AnyClicks(), 0, "not even searched")
        AssertTrue(r.wh.Has("potions", "no_desc"), "reported")
        AssertTrue(r.wh.Count("errors") >= 1, "errors webhook")
    } finally
        r.Done()
    ; dry run: walks to the tile and reports the description so the user can fill it in
    r := PtRig(Map("list", [Map("name", "Lucky Potion", "qty", 1)], "luckyDesc", "", "dryRun", 1))
    try {
        r.Run()
        AssertEq(r.game.UseClicks(), 0, "dry: no Use click")
        AssertTrue(r.wh.Has("potions", "no_desc"), "dry: reported")
        AssertTrue(r.wh.Has("potions", "[Lucky]: +25% Luck"), "dry: description text reported")
        AssertEq(r.BiomeUses("Lucky Potion"), 0, "dry: no Record")
    } finally
        r.Done()
}

Test_Pt_BiomeChangeMidLoopStops() {
    r := PtRig(Map("qty1", 2, "perBiome", 3))
    try {
        r.game.onUse := () => (r.state.biome := "NORMAL", r.state.rareActive := false)
        r.Run()
        AssertEq(r.game.UseClicks(), 1, "stopped after biome changed")
        AssertEq(r.Count("Speed Potion"), 5, "later potions untouched")
        AssertTrue(r.wh.Has("potions", "biome_ended"), "biome_ended reported")
    } finally
        r.Done()
    ; biome already gone before the task runs: no clicks at all
    r := PtRig()
    try {
        r.state.biome := "NORMAL"
        r.state.rareActive := false
        r.Run()
        AssertEq(r.game.AnyClicks(), 0, "biome gone: no clicks at all")
    } finally
        r.Done()
}

Test_Pt_PollFnRefreshesBiome() {
    r := PtRig(Map("qty1", 2, "perBiome", 3))
    try {
        polls := 0
        ; the log reports a biome change only after the first Use click
        r.task.pollFn := () => (polls++, (r.game.UseClicks() >= 1) ? (r.state.biome := "NORMAL") : 0)
        r.Run()
        AssertTrue(polls >= 3, "pollFn called during the task")
        AssertEq(r.game.UseClicks(), 1, "exactly one Use click, then stop")
        AssertEq(r.Count("Lucky Potion"), 4, "one Lucky consumed")
        AssertEq(r.Count("Speed Potion"), 5, "later potion untouched")
    } finally
        r.Done()
}

Test_Pt_BeginEventFalseNoClicks() {
    r := PtRig()
    try {
        AssertTrue(r.safety.BeginEvent(r.key), "pre-claim event")
        r.Run()
        AssertEq(r.game.AnyClicks(), 0, "already claimed: no clicks at all")
        AssertTrue(r.wh.Has("potions", "event_claimed"), "skip reported")
    } finally
        r.Done()
}

Test_Pt_VerifyFailureStopsAll() {
    r := PtRig(Map("qty1", 2))
    try {
        r.game.consumeBy := 2
        r.Run()
        AssertEq(r.game.UseClicks(), 1, "only the first click, then stop all")
        AssertEq(r.Count("Speed Potion"), 5, "next potion never used")
        AssertTrue(r.wh.Has("potions", "verify_failed"), "verify failure reported")
        AssertTrue(r.wh.Has("potions", "Potion used (verify failed)"), "reported as used, not skipped")
        AssertTrue(r.wh.Count("errors") >= 1, "errors webhook")
    } finally
        r.Done()
}

Test_Pt_RecordThrowsNoClick() {
    r := PtRig(Map("safetyClass", PtThrowSafety))
    try {
        r.Run()
        AssertEq(r.game.UseClicks(), 0, "Record threw: no Use click")
        AssertEq(r.Count("Speed Potion"), 5, "stop all after record failure")
        AssertTrue(r.wh.Has("potions", "record_failed"), "record failure reported")
    } finally
        r.Done()
}

Test_Pt_LockedPotionNoClick() {
    r := PtRig(Map("lockedSpeed", 1))
    try {
        r.Run()
        AssertEq(r.game.UseClicks(), 1, "only the unlocked Lucky used")
        AssertEq(r.Count("Speed Potion"), 5, "locked Speed never used")
        AssertTrue(r.wh.Has("potions", "locked"), "locked skip reported")
        AssertTrue(!r.game.Searched("Speed Potion"), "locked potion never even searched")
    } finally
        r.Done()
}

Test_Pt_ItemsTabClickedAfterOpen() {
    ; the inventory opens on Gears: the Items tab is clicked right after
    ; inv_open, before anything is typed into the search box
    r := PtRig(Map("list", [Map("name", "Lucky Potion", "qty", 1)]))
    try {
        r.Run()
        iOpen := 0, iTab := 0, iText := 0
        for i, v in r.game.log {
            if (!iOpen && v = "click 42,685")
                iOpen := i
            else if (!iTab && v = "click 1693,448")
                iTab := i
            else if (!iText && SubStr(v, 1, 5) = "text ")
                iText := i
        }
        AssertTrue(iOpen > 0 && iTab > iOpen && iText > iTab, "open -> Items tab -> type")
        AssertEq(r.game.UseClicks(), 1, "used after switching to Items")
    } finally
        r.Done()
}

Test_Pt_MissingCalibrationNoClick() {
    for id in ["inv_use", "inv_open", "inv_items_tab", "inv_search", "inv_tile1_rect", "inv_tile2_rect", "inv_count_rect", "inv_desc_rect", "inv_amount_box"] {
        r := PtRig()
        try {
            if r.game.pts.Has(id)
                r.game.pts.Delete(id)
            else if r.game.rects.Has(id)
                r.game.rects.Delete(id)
            else
                r.game.sigs.Delete(id)
            r.Run()
            AssertEq(r.game.AnyClicks(), 0, id " missing: no clicks at all")
            AssertEq(r.wh.Count("errors"), 1, id " missing: one errors webhook")
            AssertTrue(r.wh.Has("potions", "uncalibrated"), id " missing: skip reported")
        } finally
            r.Done()
    }
    ; tile 2 recorded on top of tile 1 (no spacing) and a '1' signature without
    ; any bright content both count as uncalibrated
    r := PtRig()
    try {
        r.game.rects["inv_tile2_rect"] := {x: 1080, y: 610, w: 112, h: 50}
        r.Run()
        AssertEq(r.game.AnyClicks(), 0, "bad tile spacing: no clicks")
        AssertTrue(r.wh.Has("errors", "inv_tile2_rect"), "named")
    } finally
        r.Done()
    ; an older inv_amount_empty recording still gives the box
    r := PtRig(Map("list", [Map("name", "Lucky Potion", "qty", 1)]))
    try {
        r.game.rects.Delete("inv_amount_box")
        r.game.sigs["inv_amount_empty"] := {x: 684, y: 752, w: 140, h: 40, sig: "s1:4x2:170:30003000"}
        r.Run()
        AssertEq(r.game.UseClicks(), 1, "box from the old recording: used")
    } finally
        r.Done()
    ; tile 2 overlapping tile 1 / a different size: uncalibrated
    for t2 in [{x: 1150, y: 610, w: 112, h: 50}, {x: 1212, y: 610, w: 140, h: 50}, {x: 1212, y: 610, w: 112, h: 39}] {
        r := PtRig()
        try {
            r.game.rects["inv_tile2_rect"] := t2
            r.Run()
            AssertEq(r.game.AnyClicks(), 0, "bad tile 2 " t2.x "/" t2.w "/" t2.h ": no clicks")
            AssertTrue(r.wh.Has("errors", "tile spacing"), "named " t2.x "/" t2.w "/" t2.h)
        } finally
            r.Done()
    }
    ; within 20% is fine
    r := PtRig(Map("list", [Map("name", "Lucky Potion", "qty", 1)]))
    try {
        r.game.rects["inv_tile2_rect"] := {x: 1212, y: 610, w: 120, h: 46}
        r.Run()
        AssertEq(r.game.UseClicks(), 1, "tile 2 size within 20%: used")
    } finally
        r.Done()
}

Test_Pt_StopBeforeClick() {
    r := PtRig()
    try {
        r.ctx.Stop()                     ; F3 before the task starts
        r.Run()
        AssertEq(r.game.AnyClicks(), 0, "stopped: no clicks at all")
    } finally
        r.Done()
    ; F3 pressed mid-task (first biome poll): no Use click
    r := PtRig()
    try {
        r.task.pollFn := () => r.ctx.Stop()
        r.Run()
        AssertEq(r.game.UseClicks(), 0, "stop during task: no Use click")
    } finally
        r.Done()
}

Test_Pt_StopDuringSequenceNoClickNotCritical() {
    ; F3 lands while the checks before the Use click run (here: during the
    ; last amount box read, after Record). The sequence must not be
    ; Critical (Critical would buffer the F3 hotkey until after the click)
    ; and the stop check right before the click must see it.
    r := PtRig()
    try {
        crit := []
        n := [0]
        r.game.onSig := () => (crit.Push(A_IsCritical)
            , (r.game.amount = "1" && r.BiomeUses("Lucky Potion") = 1 && ++n[1] = 1) ? r.ctx.Stop() : 0)
        r.Run()
        AssertEq(n[1], 1, "stop injected after Record")
        AssertEq(r.game.UseClicks(), 0, "stop during the sequence: no Use click")
        AssertEq(r.Count("Lucky Potion"), 5, "nothing consumed")
        AssertTrue(crit.Length > 0, "amount box reads happened")
        for c in crit
            AssertEq(c, 0, "not Critical during the click sequence")
        AssertTrue(r.wh.Has("potions", "aborted"), "reported as aborted")
    } finally
        r.Done()
}

Test_Pt_TestEventNeverUsedOutsideDryRun() {
    ; a fake Dashboard test event (ts "TEST-...") while dry run is off
    r := PtRig()
    try {
        r.state.rareTs := "TEST-20261025-1"
        r.task.Queue("GLITCHED", "TEST-20261025-1")
        r.task.Run(r.ctx)
        AssertEq(r.game.AnyClicks(), 0, "test event, dry run off: no clicks at all")
        AssertTrue(r.wh.Has("potions", "test_event"), "reported")
    } finally
        r.Done()
    r := PtRig(Map("dryRun", 1))
    try {
        r.state.rareTs := "TEST-20261025-2"
        r.task.Queue("GLITCHED", "TEST-20261025-2")
        r.task.Run(r.ctx)
        AssertEq(r.game.UseClicks(), 0, "dry run: no Use click")
        AssertTrue(r.wh.Has("potions", "would use"), "dry run pass runs for a test event")
    } finally
        r.Done()
}

Test_Pt_AmountNotOneNoClick() {
    r := PtRig()
    try {
        r.game.amountStuck := true      ; box keeps "5" whatever is typed
        r.Run()
        AssertEq(r.game.UseClicks(), 0, "amount box stuck: no Use click")
        AssertEq(r.Count("Lucky Potion"), 5, "nothing consumed")
        AssertTrue(r.wh.Has("potions", "amount_not_empty"), "clearing failed reported")
    } finally
        r.Done()
    ; Backspace ignored, a "1" left over (a lone 1 does not OCR, so it passes
    ; as cleared): typing 1 makes "11", which reads as 11 -> refused
    r := PtRig(Map("list", [Map("name", "Lucky Potion", "qty", 1)]))
    try {
        r.game.amount := "1"
        r.game.noBackspace := true
        r.Run()
        AssertEq(r.game.UseClicks(), 0, "left-over 1 + typed 1: no Use click")
        AssertEq(r.game.amount, "11", "box shows 11")
        AssertTrue(r.wh.Has("potions", "amount_not_one"), "reported")
    } finally
        r.Done()
    ; a bigger number left over that Backspace cannot clear: refused before typing
    r := PtRig(Map("list", [Map("name", "Lucky Potion", "qty", 1)]))
    try {
        r.game.amount := "100"
        r.game.noBackspace := true
        r.Run()
        AssertEq(r.game.UseClicks(), 0, "100 left over: no Use click")
        AssertTrue(r.wh.Has("potions", "amount_not_empty"), "reported")
        AssertEq(r.game.amount, "100", "nothing typed after the failed clear")
    } finally
        r.Done()
    ; box shows "11" after typing 1 (within per-cell tol of "1")
    r := PtRig(Map("list", [Map("name", "Lucky Potion", "qty", 1)]))
    try {
        r.game.typeTwice := true
        r.Run()
        AssertEq(r.game.amount, "11", "box shows 11")
        AssertEq(r.game.UseClicks(), 0, "'11' rejected: no Use click")
        AssertTrue(r.wh.Has("potions", "amount_not_one"), "reported")
    } finally
        r.Done()
    ; how a read is judged
    for pair in [["", "blank"], [" `n", "blank"], ["1", "one"], ["l", "one"], ["I", "one"]
            , ["10", "other"], ["11", "other"], ["5", "other"], ["100", "other"], ["7|", "other"]]
        AssertEq(PotionsTask.AmountClass(pair[1]), pair[2], "amount read '" pair[1] "'")
    ; never relies on Ctrl+A in the amount box: End + Backspace
    r := PtRig(Map("list", [Map("name", "Lucky Potion", "qty", 1)]))
    try {
        r.Run()
        AssertEq(r.game.UseClicks(), 1, "normal run used")
        iAmt := 0
        for i, v in r.game.log
            if (v = "click 754,772" && !iAmt)
                iAmt := i
        AssertTrue(iAmt > 0, "amount box clicked")
        AssertEq(r.game.log[iAmt + 1], "down End", "End right after the click")
        n := 0, ctrlA := false, clicks := 0
        i := iAmt + 1
        while (i <= r.game.log.Length && r.game.log[i] != "text 1") {
            n += (r.game.log[i] = "down Backspace")
            ctrlA := ctrlA || (r.game.log[i] = "down Ctrl")
            clicks += (SubStr(r.game.log[i], 1, 6) = "click ")
            i++
        }
        AssertEq(n, Input.ClearKeys, "Input.ClearKeys Backspaces")
        AssertTrue(!ctrlA, "no Ctrl+A in the amount box")
        AssertEq(clicks, 0, "1 typed in the same focus: no second click")
    } finally
        r.Done()
}

Test_Pt_AmountReadRetriesThenMatches() {
    ; blinking caret: the first read of each check is junk, the next is clean
    r := PtRig(Map("list", [Map("name", "Lucky Potion", "qty", 1)]))
    try {
        reads := 0
        r.game.onSig := () => (reads++)
        r.task._amountFn := (rr) => (r.game.AmountOcr(rr), Mod(reads, 2) = 1 ? "8|" : (r.game.amount = "1" ? "" : r.game.amount))
        r.Run()
        AssertEq(r.game.UseClicks(), 1, "matched on a retry")
        AssertTrue(reads >= 4, "re-read before Record and before the click")
    } finally
        r.Done()
    ; never clean within Potions.sigReads -> no click
    r := PtRig(Map("list", [Map("name", "Lucky Potion", "qty", 1)]))
    try {
        reads := 0
        r.task._amountFn := (rr) => (reads++, "88")
        r.Run()
        AssertEq(r.game.UseClicks(), 0, "never clean: no Use click")
        AssertEq(reads, 3, "default 3 reads")
    } finally
        r.Done()
}

Test_Pt_PointerParkedOffAmountBox() {
    ; the fake draws the pointer into the amount box picture: the task must
    ; move it away before every signature read
    r := PtRig(Map("list", [Map("name", "Lucky Potion", "qty", 1)]))
    try {
        over := 0
        r.game.onSig := () => (r.game.Over(r.game.rects["inv_amount_box"]) ? over++ : 0)
        r.Run()
        AssertEq(over, 0, "pointer never over the box during a read")
        AssertEq(r.game.UseClicks(), 1, "used")
    } finally
        r.Done()
}

Test_Pt_UnreadableCountNoClick() {
    r := PtRig()
    try {
        r.game.countFn := (it) => "x?5"
        r.Run()
        AssertEq(r.game.UseClicks(), 0, "unreadable count: no Use click")
        AssertTrue(r.wh.Has("potions", "unreadable"), "reported")
    } finally
        r.Done()
}

Test_Pt_CountReadsDisagreeNoClick() {
    r := PtRig()
    try {
        n := 0
        r.game.countFn := (it) => "x" (it.count + Mod(++n, 2))      ; 6, 5, 6, 5 ...
        r.Run()
        AssertEq(r.game.UseClicks(), 0, "two reads disagree: no Use click")
        AssertTrue(r.wh.Has("potions", "unreadable"), "reported unreadable")
    } finally
        r.Done()
}

Test_Pt_ReasonTextCoversAllPlanReasons() {
    for reason in ["usage_unreadable", "usage_write_failed", "record_failed", "unknown", "locked", "no_desc", "bad_event"
        , "event_done", "event_not_begun", "bad_qty", "unreadable", "bad_clock", "cap_biome", "cap_day", "cap_run", "none_owned"
        , "tile_not_found", "tile_ambiguous", "desc_not_unique", "select_unverified", "amount_not_empty"] {
        AssertTrue(PotionsTask.ReasonText.Has(reason), "text for " reason)
    }
    AssertEq(PotionsTask.ParseCount("x12"), "12", "x prefix stripped")
    AssertEq(PotionsTask.ParseCount(" 7 "), "7", "trimmed")
    AssertEq(PotionsTask.ParseCount("1,234"), "1,234", "ambiguous left as-is (Plan rejects)")
    ; recon misreads, digit confusables mapped
    AssertEq(PotionsTask.ParseCount("xT2"), "12", "T -> 1")
    AssertEq(PotionsTask.ParseCount("x5G"), "x5G", "G unreadable (recon read a 4 as G)")
    AssertEq(PotionsTask.ParseCount("x9125G"), "x9125G", "G unreadable 2")
    AssertEq(PotionsTask.ParseCount("Oil"), "Oil", "no digit and no x: text")
    AssertEq(PotionsTask.ParseCount("SOS"), "SOS", "no digit and no x: text 2")
    AssertEq(PotionsTask.ParseCount("1O"), "10", "one real digit is enough")
    AssertEq(PotionsTask.ParseCount("xIl|"), "111", "I l | -> 1")
    AssertEq(PotionsTask.ParseCount("xO"), "0", "O -> 0")
    AssertEq(PotionsTask.ParseCount("xS"), "5", "S -> 5")
    AssertEq(PotionsTask.ParseCount("xB"), "8", "B -> 8")
    AssertEq(PotionsTask.ParseCount("X12"), "12", "X prefix")
    AssertEq(PotionsTask.ParseCount("x?5"), "x?5", "unknown glyph left as-is")
    AssertEq(PotionsTask.ParseCount("g125L"), "g125L", "g / L not mapped")
    AssertEq(PotionsTask.ParseCount(""), "", "empty")
}

Test_Pt_SelectionStaysOnOtherPotionNoClick() {
    r := PtRig()
    try {
        r.game.selected := r.game.Item("Heavenly Potion")   ; left selected from before
        r.game.selectFails := true                          ; our tile click does nothing
        r.Run()
        AssertEq(r.game.UseClicks(), 0, "wrong selected item: zero Use clicks")
        AssertEq(r.Count("Heavenly Potion"), 3, "Heavenly untouched")
        AssertEq(r.Count("Speed Potion"), 5, "stop all: Speed untouched")
        AssertTrue(r.wh.Has("potions", "select_unverified"), "reported")
        AssertTrue(r.wh.Count("errors") >= 1, "errors webhook")
    } finally
        r.Done()
}

Test_Pt_StaleSiblingSelectionDroppedClickNoClick() {
    ; Speed Potion L (same description as Speed Potion) is still selected and
    ; every tile click is dropped: the description check alone would pass
    r := PtRig(Map("list", [Map("name", "Speed Potion", "qty", 1)]))
    try {
        r.game.selected := r.game.Item("Speed Potion L")
        r.game.dropClicks := 999
        r.Run()
        AssertEq(r.game.UseClicks(), 0, "stale sibling + dropped clicks: zero Use clicks")
        AssertEq(r.Count("Speed Potion L"), 7, "Speed L untouched")
        AssertEq(r.Count("Speed Potion"), 5, "Speed untouched")
        AssertTrue(r.wh.Has("potions", "select_unverified"), "reported")
        AssertEq(r.BiomeUses("Speed Potion"), 0, "no Record")
    } finally
        r.Done()
    ; stale sibling, priming works, but the click on the target tile is dropped
    r := PtRig(Map("list", [Map("name", "Speed Potion", "qty", 1)]))
    try {
        r.game.selected := r.game.Item("Speed Potion L")
        r.game.dropTile := 2
        r.Run()
        AssertEq(r.game.UseClicks(), 0, "target click dropped: zero Use clicks")
        AssertEq(r.Count("Speed Potion L"), 7, "Speed L untouched")
        AssertTrue(r.wh.Has("potions", "select_unverified"), "reported")
    } finally
        r.Done()
    ; nothing selected before (empty description = unknown -> priming), and
    ; every click on tile 1 (the target) is dropped
    r := PtRig(Map("list", [Map("name", "Lucky Potion", "qty", 1)]))
    try {
        r.game.dropTile := 1
        r.Run()
        AssertEq(r.game.UseClicks(), 0, "dropped first click: zero Use clicks")
        AssertTrue(r.wh.Has("potions", "select_unverified"), "reported")
    } finally
        r.Done()
}

TileClicks(game) {
    n := 0
    for v in game.log
        n += (SubStr(v, 1, 6) = "click " && SubStr(v, -4) = ",635")
    return n
}

Test_Pt_PreClickOcrFailsClosed() {
    ; stale Speed L + ONE garbled pre-read + dropped target click: a single
    ; "not matching" read would let the stale sibling pass after the click
    r := PtRig(Map("list", [Map("name", "Speed Potion", "qty", 1)]))
    try {
        r.game.selected := r.game.Item("Speed Potion L")
        r.game.descGarble := 1
        r.game.dropTile := 2
        r.Run()
        AssertEq(r.game.UseClicks(), 0, "garbled pre-read + dropped click: zero Use clicks")
        AssertEq(r.Count("Speed Potion L"), 7, "Speed L untouched")
        AssertTrue(r.wh.Has("potions", "select_unverified"), "reported")
    } finally
        r.Done()
    ; OCR exception on the pre-read: unknown -> no tile click at all
    r := PtRig(Map("list", [Map("name", "Speed Potion", "qty", 1)]))
    try {
        r.game.selected := r.game.Item("Speed Potion L")
        r.game.descThrow := 1
        r.Run()
        AssertEq(r.game.UseClicks(), 0, "OCR error: zero Use clicks")
        AssertEq(TileClicks(r.game), 0, "OCR error: no select click")
        AssertTrue(r.wh.Has("potions", "select_unverified"), "reported")
    } finally
        r.Done()
    ; OCR exception on the second pre-read too (first read: another description)
    r := PtRig(Map("list", [Map("name", "Lucky Potion", "qty", 1)]))
    try {
        r.game.selected := r.game.Item("Godlike Potion")
        cnt := [0]
        r.task._ocrFn := (rr, scale := 1) => PtOcrNth(r.game, rr, cnt, 2)
        r.Run()
        AssertEq(r.game.UseClicks(), 0, "OCR error on read 2: zero Use clicks")
        AssertEq(TileClicks(r.game), 0, "no select click")
    } finally
        r.Done()
    ; garbled read INSIDE priming (looks like "another description") +
    ; dropped target click: the two-read check after priming catches it
    r := PtRig(Map("list", [Map("name", "Speed Potion", "qty", 1)]))
    try {
        r.game.selected := r.game.Item("Speed Potion L")
        r.game.dropTile := 2
        r.game.dropClicks := 1                 ; the priming click on tile 1 is dropped too
        cnt := [0]
        r.task._ocrFn := (rr, scale := 1) => PtOcrGarbleNth(r.game, rr, cnt, 2)
        r.Run()
        AssertEq(r.game.UseClicks(), 0, "garbled priming read: zero Use clicks")
        AssertEq(r.Count("Speed Potion L"), 7, "Speed L untouched")
    } finally
        r.Done()
    ; one garbled read with nothing stale selected: still works (2nd read clean)
    r := PtRig(Map("list", [Map("name", "Lucky Potion", "qty", 1)]))
    try {
        r.game.descGarble := 1
        r.Run()
        AssertEq(r.game.UseClicks(), 1, "garbled first read alone does not block a clean selection")
    } finally
        r.Done()
    ; Ocr.Read never throws: it returns "" on failure. Stale Speed L + BOTH
    ; pre-reads empty + dropped target click: "" must not count as "not
    ; matching" (else the stale sibling passes the post-click check)
    r := PtRig(Map("list", [Map("name", "Speed Potion", "qty", 1)]))
    try {
        r.game.selected := r.game.Item("Speed Potion L")
        r.game.descEmpty := 2
        r.game.dropTile := 2
        r.Run()
        AssertEq(r.game.UseClicks(), 0, "empty pre-reads + dropped click: zero Use clicks")
        AssertEq(r.Count("Speed Potion L"), 7, "Speed L untouched")
        AssertTrue(r.wh.Has("potions", "select_unverified"), "reported")
    } finally
        r.Done()
    ; OCR returns "" for every description read: never proven -> the target
    ; tile is never clicked from its own search (priming may select tiles
    ; of the "Potion" search, which is harmless), zero Use clicks, no
    ; Record, all potion use stopped
    r := PtRig(Map("list", [Map("name", "Speed Potion", "qty", 1)]))
    try {
        r.game.selected := r.game.Item("Speed Potion L")
        r.game.descEmpty := 999999
        tgt := r.game.Item("Speed Potion")
        r.Run()
        AssertEq(r.game.UseClicks(), 0, "OCR always empty: zero Use clicks")
        AssertEq(r.BiomeUses("Speed Potion"), 0, "OCR always empty: no Record")
        AssertEq(r.game.selected == tgt ? 1 : 0, 0, "OCR always empty: target not left selected")
        AssertEq(r.Count("Speed Potion"), 5, "Speed untouched")
        AssertTrue(r.wh.Has("potions", "select_unverified"), "reported")
    } finally
        r.Done()
    ; OCR "" on the FIRST pre-read only, nothing else wrong: primed, then used
    r := PtRig(Map("list", [Map("name", "Lucky Potion", "qty", 1)]))
    try {
        r.game.selected := r.game.Item("Godlike Potion")
        cnt := [0]
        r.task._ocrFn := (rr, scale := 1) => PtOcrEmptyNth(r.game, rr, cnt, 1)
        r.Run()
        AssertEq(r.game.UseClicks(), 1, "one empty read is unknown, not fatal")
        AssertEq(r.Count("Lucky Potion"), 4, "the right potion consumed")
    } finally
        r.Done()
    ; _Prime: every tile selected while priming reads "" -> never accepted
    ; as "another description"; stale Lucky L + dropped target click
    r := PtRig(Map("list", [Map("name", "Lucky Potion", "qty", 1)]))
    try {
        r.game.selected := r.game.Item("Lucky Potion L")
        r.game.dropTile := 1
        r.task._ocrFn := (rr, scale := 1) => PtOcrEmptyUnless(r.game, rr, "Lucky")
        r.Run()
        AssertEq(r.game.UseClicks(), 0, "priming on empty reads: zero Use clicks")
        AssertEq(r.Count("Lucky Potion L"), 9, "Lucky L untouched")
        AssertTrue(r.wh.Has("potions", "select_unverified"), "reported")
    } finally
        r.Done()
    ; _Prime skips tiles whose description reads "" (Speed L / Speed in the
    ; "Potion" search) and primes from the first READABLE other one (Haste)
    r := PtRig(Map("list", [Map("name", "Lucky Potion", "qty", 1)]))
    try {
        r.game.selected := r.game.Item("Lucky Potion L")
        r.task._ocrFn := (rr, scale := 1) => PtOcrEmptyIf(r.game, rr, "Quick Roll")
        r.Run()
        AssertEq(r.game.UseClicks(), 1, "primed past unreadable tiles, then used")
        AssertEq(r.Count("Lucky Potion"), 4, "Lucky consumed")
        AssertEq(r.Count("Lucky Potion L"), 9, "Lucky L untouched")
    } finally
        r.Done()
}

; Fake-game OCR: description reads containing `drop` come back "".
PtOcrEmptyIf(game, rr, drop) {
    res := game.Ocr(rr)
    return (rr.x = 652 && InStr(res, drop)) ? "" : res
}

; Fake-game OCR whose n-th description read is "" (Ocr.Read failure).
PtOcrEmptyNth(game, rr, cnt, n) {
    res := game.Ocr(rr)
    return (rr.x = 652 && ++cnt[1] = n) ? "" : res
}

; Fake-game OCR: description reads are "" unless they contain `keep`.
PtOcrEmptyUnless(game, rr, keep) {
    res := game.Ocr(rr)
    return (rr.x = 652 && !InStr(res, keep)) ? "" : res
}

; Fake-game OCR whose n-th description read is garbage.
PtOcrGarbleNth(game, rr, cnt, n) {
    res := game.Ocr(rr)
    return (rr.x = 652 && ++cnt[1] = n) ? "Gxv3s y0u 1 m!nute" : res
}

; Fake-game OCR whose n-th description read throws.
PtOcrNth(game, rr, cnt, n) {
    if (rr.x = 652 && ++cnt[1] = n)
        throw Error("simulated OCR failure")
    return game.Ocr(rr)
}

Test_Pt_StaleSiblingSelectionPrimedThenUsed() {
    ; Lucky Potion L (same description) is selected: another tile with a
    ; different description is selected first ("Potion" search), then Lucky
    r := PtRig(Map("list", [Map("name", "Lucky Potion", "qty", 1)]))
    try {
        r.game.selected := r.game.Item("Lucky Potion L")
        r.Run()
        AssertEq(r.game.UseClicks(), 1, "used after priming")
        AssertEq(r.Count("Lucky Potion"), 4, "Lucky consumed")
        AssertEq(r.Count("Lucky Potion L"), 9, "Lucky L untouched")
        AssertTrue(r.game.Searched("Potion"), "primed through a 'Potion' search")
        AssertEq(r.wh.Count("errors"), 0, "no errors")
    } finally
        r.Done()
    ; Godly Sea already selected: primed with another Godly tile, Sea still used
    r := PtRig(Map("list", [Map("name", "Godly Potion (Sea)", "qty", 1)]))
    try {
        r.game.selected := r.game.Item("Godly Potion", 3)
        r.Run()
        AssertEq(r.game.UseClicks(), 1, "Sea used")
        AssertEq(r.Count("Godly Potion", 3), 4, "Sea consumed")
        AssertEq(r.Count("Godly Potion", 1), 29, "Sky untouched")
        AssertTrue(!r.game.Searched("Potion"), "primed inside the Godly results")
    } finally
        r.Done()
}

Test_Pt_SelectionChangedAfterRecordNoClick() {
    ; something changes the selection between Record and the click
    r := PtRig(Map("safetyClass", PtHookSafety))
    try {
        PtHookSafety.afterRecord := () => (r.game.selected := r.game.Item("Godlike Potion"))
        r.Run()
        AssertEq(r.game.UseClicks(), 0, "description re-check before click: no Use click")
        AssertEq(r.Count("Godlike Potion"), 1, "Godlike untouched")
        AssertEq(r.Count("Speed Potion"), 5, "stop all")
        AssertEq(r.BiomeUses("Lucky Potion"), 1, "reserved but unclicked (safe side)")
        AssertTrue(r.wh.Has("potions", "selected_mismatch"), "reported")
    } finally
        r.Done()
}

Test_Pt_AmountChangedBeforeClickNoClick() {
    ; a timer-like keystroke lands in the amount box after it was verified "1"
    r := PtRig()
    try {
        injected := false
        r.game.onSig := () => (r.game.amount = "1" && !injected) ? (injected := true, r.game.amount := "15") : 0
        r.Run()
        AssertTrue(injected, "injection happened")
        AssertEq(r.game.UseClicks(), 0, "amount changed after check: no Use click")
        AssertEq(r.Count("Lucky Potion"), 5, "nothing consumed")
        AssertEq(r.Count("Speed Potion"), 5, "stop all")
        AssertTrue(r.wh.Has("potions", "amount_changed"), "reported")
    } finally
        r.Done()
}

Test_Pt_BusyFlagAroundPotion() {
    r := PtRig()
    try {
        seen := []
        r.game.onUse := () => seen.Push(PotionsTask.busy)
        AssertEq(PotionsTask.busy, false, "idle before")
        r.Run()
        AssertEq(seen.Length, 2, "two Use clicks")
        AssertTrue(seen[1] && seen[2], "busy during every Use click")
        AssertEq(PotionsTask.busy, false, "cleared after")
        AssertEq(A_IsCritical, 0, "Critical restored")
    } finally {
        PotionsTask.busy := false
        r.Done()
    }
}

Test_Pt_NoPollRefusesClicks() {
    r := PtRig()
    try {
        r.task.pollFn := ""
        r.Run()
        AssertEq(r.game.AnyClicks(), 0, "no poll wired: no clicks at all")
        AssertEq(r.wh.Count("errors"), 1, "one errors webhook")
        AssertTrue(r.wh.Has("potions", "no_poll"), "reported")
    } finally
        r.Done()
    r := PtRig(Map("dryRun", 1))
    try {
        r.task.pollFn := ""
        r.Run()
        AssertEq(r.game.UseClicks(), 0, "dry run without poll: no Use click")
        AssertTrue(r.wh.Has("potions", "would use"), "dry run still allowed without poll")
    } finally
        r.Done()
}

Test_Pt_SameBiomeNewEventStopsOld() {
    r := PtRig(Map("qty1", 2, "perBiome", 3))
    try {
        ; GLITCHED -> GLITCHED with a new ts after the first click
        r.game.onUse := () => (r.state.rareTs := "2026-10-24T10:30:00.000Z")
        r.Run()
        AssertEq(r.game.UseClicks(), 1, "old event stops after the new one starts")
        AssertEq(r.Count("Speed Potion"), 5, "later potion untouched")
        AssertTrue(r.wh.Has("potions", "biome_ended"), "reported")
    } finally
        r.Done()
}

Test_Pt_DryTurnedOnBeforeRecordNoClick() {
    r := PtRig()
    try {
        r.game.onOcr := (kind, res) => (kind = "count") ? r.cfg.Set("General.dryRun", 1) : 0
        r.Run()
        AssertEq(r.game.UseClicks(), 0, "dry run switched on: no Use click")
        AssertEq(r.BiomeUses("Lucky Potion"), 0, "no Record")
        AssertEq(r.Count("Speed Potion"), 5, "stop all")
        AssertTrue(r.wh.Has("potions", "dry_now_on"), "reported")
    } finally
        r.Done()
}

; ---- 2026-10-27 review -----------------------------------------------------

PtLogCount(game, prefix) {
    n := 0
    for v in game.log
        n += (SubStr(v, 1, StrLen(prefix)) = prefix)
    return n
}

PtReportCount(wh, text) {
    n := 0
    for s in wh.sent
        n += (s.event = "potions" && InStr(s.title, text) > 0)
    return n
}

PtUsageEvent(r) {
    u := Json.Parse(FileRead(r.usage, "UTF-8"))
    return u["events"].Has(r.key) ? u["events"][r.key] : 0
}

; Finding 1: the user owns Heavenly Potion I (never use) but no plain
; Heavenly Potion. Its tile OCRs "Heavenly`nPotion" (the lone I is lost) and
; its description has the shared "[Heavenly]".
Test_Pt_NeverUseHeavenlyIWithLostINeverUsed() {
    cfg := PtPotCfg()
    cfg["potions"].Push(PtEntry("Heavenly Potion", "Heavenly Potion", "[Heavenly]"))
    r := PtRig(Map("potCfg", cfg, "list", [Map("name", "Heavenly Potion", "qty", 1)]))
    try {
        hp := r.game.Item("Heavenly Potion")
        hp.real := "Heavenly Potion I", hp.ocr := "Heavenly`nPotion", hp.count := 2
        r.Run()
        AssertEq(r.game.UseClicks(), 0, "Heavenly Potion I never used")
        AssertEq(r.Count("Heavenly Potion I"), 2, "untouched")
        AssertEq(r.BiomeUses("Heavenly Potion"), 0, "no Record")
        AssertTrue(r.wh.Has("potions", "never_use_prefix"), "refused as never_use_prefix")
    } finally
        r.Done()
}

; Finding 2: a click right after typing only takes the focus off the box, so
; the old single blind close left the inventory open; the next potion's open
; click then closed it and its name was typed into the game world.
Test_Pt_InventoryOpenedAndClosedChecked() {
    r := PtRig(Map("dryRun", 1))
    try {
        r.Run()
        AssertEq(PtReportCount(r.wh, "would use"), 2, "both potions reached (dry run)")
        AssertTrue(!r.wh.Has("potions", "tile_not_found"), "second potion found its tile")
        AssertEq(r.game.worldText, "", "nothing typed into the game world")
        AssertEq(r.game.open, false, "inventory closed at the end")
    } finally
        r.Done()
    ; left open (e.g. by the user): closed first, then opened fresh
    r := PtRig(Map("list", [Map("name", "Lucky Potion", "qty", 1)]))
    try {
        r.game.open := true, r.game.tab := "items", r.game.focus := "search"
        r.Run()
        AssertEq(r.game.UseClicks(), 1, "used")
        AssertEq(r.game.worldText, "", "nothing typed into the game world")
        AssertEq(r.game.open, false, "closed at the end")
    } finally
        r.Done()
    ; the inventory never opens: no blind typing, all stopped
    r := PtRig()
    try {
        r.game.pts["inv_open"] := {x: 40, y: 600, color: 0}        ; misses the button
        r.Run()
        AssertEq(PtLogCount(r.game, "text "), 0, "nothing typed")
        AssertTrue(r.wh.Has("potions", "inv_not_open"), "reported")
        AssertTrue(r.wh.Has("potions", "stopped"), "rest stopped")
    } finally
        r.Done()
}

; Finding 3: a pause mid-potion left the inventory open and marked the event
; done, so the rest of the list was lost and other tasks ran with it open.
Test_Pt_PauseRequeuesEventAndClosesFirst() {
    r := PtRig()
    try {
        n := [0]
        r.game.onSig := () => (++n[1] = 1) ? r.ctx.Pause() : 0
        r.task.Queue("GLITCHED", "2026-10-24T10:00:00.000Z")
        r.task.Run(r.ctx)
        AssertEq(r.game.UseClicks(), 0, "paused before the Use click")
        AssertEq(r.game.open, true, "nothing sent while paused: still open")
        AssertTrue(r.task.CanRun(r.state), "event queued again")
        AssertEq(PtUsageEvent(r), 1, "event not marked done")
        AssertTrue(!r.wh.Has("potions", "not tried"), "the rest is not reported as stopped")
        ; F2: the next run closes the inventory (checked) and resumes
        r.game.onSig := ""
        r.ctx.Resume()
        r.task.Run(r.ctx)
        AssertEq(r.game.UseClicks(), 2, "both potions used after the resume")
        AssertEq(r.Count("Lucky Potion"), 4, "Lucky used once")
        AssertEq(r.Count("Speed Potion"), 4, "Speed used once")
        AssertEq(r.game.open, false, "closed at the end")
        AssertEq(r.game.worldText, "", "nothing typed into the game world")
        AssertEq(PtUsageEvent(r), 2, "event done now")
        AssertTrue(!r.task.CanRun(r.state), "nothing left queued")
        AssertEq(r.wh.Count("errors"), 0, "no errors")
    } finally
        r.Done()
    ; a use recorded before the interruption is not repeated
    r := PtRig(Map("list", [Map("name", "Lucky Potion", "qty", 1), Map("name", "Speed Potion", "qty", 1)]))
    try {
        r.game.onUse := () => (r.game.UseClicks() = 1) ? r.ctx.Pause() : 0
        r.task.Queue("GLITCHED", "2026-10-24T10:00:00.000Z")
        r.task.Run(r.ctx)
        AssertEq(r.game.UseClicks(), 1, "Lucky used, then paused")
        r.game.onUse := ""
        r.ctx.Resume()
        r.task.Run(r.ctx)
        AssertEq(r.Count("Lucky Potion"), 4, "Lucky not used twice")
        AssertEq(r.Count("Speed Potion"), 4, "Speed used")
        AssertTrue(r.wh.Has("potions", "already_used"), "reported")
    } finally
        r.Done()
}

; Finding 4: Sol's RNG drops a potion at count 0 from the list; the next
; result shifts into the tile and its count was read as "after".
Test_Pt_LastPotionOfKindCountsAsUsed() {
    r := PtRig(Map("qty1", 2))
    try {
        r.game.Item("Lucky Potion").count := 1
        r.Run()
        AssertEq(r.game.UseClicks(), 2, "the last Lucky, then Speed")
        AssertEq(r.Count("Lucky Potion"), 0, "last Lucky used")
        AssertEq(r.Count("Lucky Potion L"), 9, "the tile that moved up untouched")
        AssertEq(r.Count("Speed Potion"), 4, "Speed still used")
        AssertTrue(r.wh.Has("potions", "1 -> 0"), "reported 1 -> 0")
        AssertTrue(!r.wh.Has("potions", "verify_failed"), "no verify failure")
        AssertEq(r.wh.Count("errors"), 0, "no errors")
    } finally
        r.Done()
    ; count 1 and the Use did nothing (tile and description unchanged): failed
    r := PtRig(Map("list", [Map("name", "Lucky Potion", "qty", 1)]))
    try {
        r.game.Item("Lucky Potion").count := 1
        r.game.consumeBy := 0
        r.Run()
        AssertTrue(r.wh.Has("potions", "verify_failed"), "nothing consumed: verify failed")
    } finally
        r.Done()
}

; Finding 5: a corrupt usage file / a halt showed up only as a quiet
; "event_claimed".
Test_Pt_UsageProblemReportedLoudly() {
    r := PtRig(Map("usageText", "garbage"))
    try {
        AssertTrue(r.wh.Has("errors", "unreadable"), "reported when the task is built")
        r.Run()
        AssertEq(r.game.AnyClicks(), 0, "no clicks")
        AssertTrue(r.wh.Has("potions", "usage_unreadable"), "skips name the reason")
        AssertTrue(!r.wh.Has("potions", "event_claimed"), "not a quiet event_claimed")
        AssertTrue(r.wh.Count("errors") >= 2, "errors webhook at the event too")
    } finally
        r.Done()
    r := PtRig(Map("dryRun", 1))
    try {
        r.safety._halt := "usage_write_failed"
        r.Run()
        AssertTrue(r.wh.Has("potions", "usage_write_failed"), "halt reported")
        AssertTrue(!r.wh.Has("potions", "event_claimed"), "not event_claimed")
        AssertTrue(r.wh.Count("errors") >= 1, "errors webhook")
    } finally
        r.Done()
}

; Finding 6: the first click on the amount box is swallowed, a "1" is left
; over (reads as nothing), and live OCR of the narrow "11" is nothing too.
Test_Pt_AmountSwallowedClickNeverMakes11() {
    r := PtRig(Map("list", [Map("name", "Lucky Potion", "qty", 1)]))
    try {
        r.game.amount := "1"
        r.game.dropAmountClicks := 1
        r.game.elevenBlank := true
        r.Run()
        AssertTrue(r.game.amount != "11", "the box never holds 11")
        AssertEq(r.Count("Lucky Potion"), 4, "exactly one used")
        n := 0
        for v in r.game.log
            n += (v = "click 754,772")
        AssertEq(n, 1, "the amount box is clicked once")
    } finally
        r.Done()
}

; Finding 7: focus lost inside the NoTimers section (the App tick cannot see
; it): nothing more may be sent.
Test_Pt_FocusLostInsideSequenceSendsNothing() {
    r := PtRig()
    try {
        at := [0]
        r.game.onSig := () => (!at[1]) ? (r.front := false, at[1] := r.game.log.Length) : 0
        r.task.Queue("GLITCHED", "2026-10-24T10:00:00.000Z")
        r.task.Run(r.ctx)
        AssertTrue(at[1] > 0, "focus lost during the amount check")
        Loop r.game.log.Length - at[1] {
            v := r.game.log[at[1] + A_Index]
            AssertTrue(SubStr(v, 1, 5) != "click" && SubStr(v, 1, 4) != "down" && SubStr(v, 1, 4) != "text", "nothing sent after focus loss: " v)
        }
        AssertEq(r.game.UseClicks(), 0, "no Use click")
        AssertEq(r.Count("Lucky Potion"), 5, "nothing consumed")
        AssertTrue(r.task.CanRun(r.state), "event resumes later")
    } finally
        r.Done()
    r := PtRig()
    try {
        r.front := false
        r.task.Queue("GLITCHED", "2026-10-24T10:00:00.000Z")
        r.task.Run(r.ctx)
        AssertEq(r.game.AnyClicks(), 0, "Roblox not in front: no clicks at all")
        AssertEq(PtLogCount(r.game, "down "), 0, "no keys")
    } finally
        r.Done()
}

; Finding 9: F3 during the wait after Use read the count before the game
; updated it: a false "verify failed" + errors webhook.
Test_Pt_StopDuringAfterUseStillVerifies() {
    r := PtRig()
    try {
        r.game.useLag := 1000
        r.game.onUse := () => r.ctx.Stop()
        r.Run()
        AssertEq(r.game.UseClicks(), 1, "one Use click")
        AssertEq(r.Count("Lucky Potion"), 4, "used")
        AssertTrue(r.wh.Has("potions", "5 -> 4"), "count verified after the wait")
        AssertTrue(!r.wh.Has("potions", "verify_failed"), "no false verify failure")
        AssertEq(r.wh.Count("errors"), 0, "no errors webhook")
    } finally
        r.Done()
    ; Roblox no longer in front: count not read, reported without an error
    r := PtRig()
    try {
        r.game.useLag := 1000
        r.game.onUse := () => (r.ctx.Stop(), r.front := false)
        r.Run()
        AssertTrue(r.wh.Has("potions", "count not verified"), "reported as not verified")
        AssertEq(r.wh.Count("errors"), 0, "no errors webhook")
    } finally
        r.Done()
}

; review 2026-11-12: at 16:10 the inventory scales evenly, centred (mode
; "C"); the potion run mapped it stretched and missed the Items tab at
; 1920x1200. Every potion click happens in mode "C"; the mode is put back.
Test_Potions_InventoryInCenteredMode() {
    rig := PtRig()
    modes := []
    try {
        rig.game.DefineProp("MoveTo", {call: (self, x, y) => (modes.Push(Screen.Mode), self.mx := x, self.my := y, self.log.Push("move " x "," y))})
        rig.Run()
        AssertTrue(modes.Length > 0, "clicked")
        bad := 0
        for m in modes
            bad += (m != "C")
        AssertEq(bad, 0, "every click in mode C (" modes.Length " moves)")
        AssertEq(Screen.Mode, "S", "mode put back")
        AssertEq(rig.BiomeUses("Lucky Potion"), 1, "the potion was still used")
    } finally {
        rig.Done()
    }
}
