#Requires AutoHotkey v2.0
; Tests for lib\tasks\Craft.ahk (fisher potion buying + Stella cauldron) and
; Input.TypeText. Offline: fake io / calibration / pixel / clock / webhook /
; Roblox. Shipped data\coords.json + routes.json are loaded for real.
#Include ..\lib\Json.ahk
#Include ..\lib\Config.ahk
#Include ..\lib\tasks\Craft.ahk

; ---- helpers (names must not start with Test_) -----------------------------

; Input.TypeText types one char per Type() call with a Wait(gap) between
; chars (12b). The fake joins chars of ONE TypeText back into one log line
; ("type Heavenly Potion"): a Type() right after a Type()+Wait() appends.
class CrIO {
    __New() {
        this.log := []
        this._typing := false   ; last io calls were Type(), Wait()
        this._gap := false
    }
    Down(k) => (this._typing := false, this.log.Push("down " k))
    Up(k) => (this._typing := false, this.log.Push("up " k))
    MoveTo(x, y) => (this._typing := false, this.log.Push("move " x "," y))
    ClickHere() => (this._typing := false, this.log.Push("click"))
    Type(text) {
        if (this._typing && this._gap)
            this.log[this.log.Length] .= text
        else
            this.log.Push("type " text)
        this._typing := true
        this._gap := false
    }
    Wheel(dir, n := 1, gapMs := 25) => (this._typing := false, this.log.Push("wheel " dir " " n))
    Wait(ms, ctx := "") {
        if (this._typing && !this._gap && ms = Input.TypeGapMs)
            this._gap := true
        else
            this._typing := false
        return !(IsObject(ctx) && ctx.ShouldStop())
    }
    Count(text, from := 1) {
        n := 0
        i := from
        while (i <= this.log.Length) {
            n += (this.log[i] = text) ? 1 : 0
            i++
        }
        return n
    }
    ; 1-based index of the first entry equal to text at or after `from`, else 0.
    Idx(text, from := 1) {
        i := from
        while (i <= this.log.Length) {
            if (this.log[i] = text)
                return i
            i++
        }
        return 0
    }
    ; Every key pressed was released.
    Balanced() {
        held := Map()
        for e in this.log {
            if (SubStr(e, 1, 5) = "down ")
                held[SubStr(e, 6)] := (held.Has(SubStr(e, 6)) ? held[SubStr(e, 6)] : 0) + 1
            else if (SubStr(e, 1, 3) = "up ") {
                k := SubStr(e, 4)
                held[k] := (held.Has(k) ? held[k] : 0) - 1
            }
        }
        for , n in held
            if (n != 0)
                return false
        return true
    }
}

class CrCal {
    __New(points, pots, rects := "") {
        this.p := points
        this.pots := pots
        this.r := (rects is Map) ? rects : Map()
    }
    Point(id) => this.p.Has(id) ? this.p[id] : ""
    Rect(id) => this.r.Has(id) ? this.r[id] : ""
    Potions() => this.pots
}

class CrCfg {
    __New(gets, data) {
        this.g := gets
        this.d := data
    }
    Get(path, default := "") => this.g.Has(path) ? this.g[path] : default
    Data(name) => this.d.Has(name) ? this.d[name] : Map()
}

class CrWh {
    __New() {
        this.sent := []
    }
    Send(event, title, desc, color := 0, opts := "") {
        this.sent.Push({event: event, title: title, desc: desc})
    }
    Count(event) {
        n := 0
        for s in this.sent
            n += (s.event = event) ? 1 : 0
        return n
    }
    Desc(event) {
        for s in this.sent
            if (s.event = event)
                return s.desc
        return ""
    }
}

class CrRoblox {
    __New(ok := true) {
        this.canFocus := ok
        this.calls := 0
    }
    Focus() {
        this.calls += 1
        return this.canFocus
    }
}

; Pixel fake. Default true. Set(key, seq): seq is a bool or an Array of bools
; returned in order (the last one repeats). key = "x,y".
class CrPx {
    __New() {
        this.seq := Map()
        this.i := Map()
        this.queried := []
        this.cols := Map()
        this.ci := Map()
        this.dyn := Map()       ; key -> () => Bool, used when no Set() sequence
    }
    ; Colors returned by Color(x, y) in order (the last repeats); default 0x101010.
    SetSample(key, list) {
        this.cols[key] := list
        this.ci[key] := 0
    }
    Color(x, y) {
        key := x "," y
        if !this.cols.Has(key)
            return 0x101010
        this.ci[key] := Min(this.ci[key] + 1, this.cols[key].Length)
        return this.cols[key][this.ci[key]]
    }
    Queries(key) {
        n := 0
        for q in this.queried
            n += (q = key) ? 1 : 0
        return n
    }
    Set(key, seq) {
        this.seq[key] := (seq is Array) ? seq : [seq]
        this.i[key] := 0
    }
    Is(x, y, c, tol) {
        key := x "," y
        this.queried.Push(key)
        if !this.seq.Has(key)
            return this.dyn.Has(key) ? this.dyn[key].Call() : true
        this.i[key] := Min(this.i[key] + 1, this.seq[key].Length)
        return this.seq[key][this.i[key]]
    }
}

; ShouldStop turns true after `n` calls; remembers how long the io log was.
class CrStopCtx {
    __New(n, io) {
        this.n := n
        this.calls := 0
        this.io := io
        this.stopAt := -1
    }
    ShouldStop() {
        this.calls += 1
        if (this.calls > this.n) {
            if (this.stopAt < 0)
                this.stopAt := this.io.log.Length
            return true
        }
        return false
    }
}

CrPoints() {
    pt := (x, c) => {x: x, y: 100, color: c}
    return Map(
        "fisher_item_lucky_potion", pt(100, 0x111111),
        "fisher_item_speed_potion", pt(200, 0x111112),
        "fisher_qty", pt(300, 0x111113),
        "fisher_confirm", pt(400, 0x222222),
        "fisher_open_shop", pt(1300, 0x333333),
        "fisher_buy_button", pt(1400, 0x333334),
        "fisher_purchase_close", pt(1500, 0x333335),
        "cauldron_search", pt(700, 0x555555),
        "cauldron_open_recipe", pt(900, 0x555557),
        "cauldron_add_all", pt(1000, 0x555558),
        "cauldron_close", pt(1100, 0x555559)
    )
}

CrRead(name) => Json.Parse(FileRead(A_ScriptDir "\..\data\" name ".json", "UTF-8"))

; Builds a task with fakes. opts (all optional, Map):
;   "gets" Map, "drop" Array of calibration ids to remove, "pots" Array,
;   "cauldron" true -> toggle on + target + recorded cauldron routes,
;   "cauldronRoute"/"returnRoute" -> override those route steps ("DEL" removes the key),
;   "roblox" CrRoblox, "px" CrPx
; -> {t, io, wh, px, rb, cfg}
CrMake(opts := "") {
    if !(opts is Map)
        opts := Map()
    gets := opts.Has("gets") ? opts["gets"] : Map()
    points := CrPoints()
    ; text boxes: cauldron_gui (the "Stella's Workshop" title) OCR "600,100,200,40",
    ; cauldron_result (first result card) "800,100,300,80" (centre 950,140),
    ; stella_dialog (her name) "1200,100,100,30", notify_rect "5,6,70,80"
    rects := Map("notify_rect", {x: 5, y: 6, w: 70, h: 80}
        , "cauldron_gui", {x: 600, y: 100, w: 200, h: 40}
        , "cauldron_result", {x: 800, y: 100, w: 300, h: 80}
        , "fisher_picked_name", {x: 2000, y: 200, w: 400, h: 60})     ; the picked item's name: OCR "2000,200,400,60"
    if (opts.Has("stella") && opts["stella"])
        rects["stella_dialog"] := {x: 1200, y: 100, w: 100, h: 30}
    if (opts.Has("result2") && opts["result2"])          ; second card 90 px lower: card 2 "800,190,300,80", card 3 "800,280,300,80"
        rects["cauldron_result_2"] := {x: 800, y: 190, w: 300, h: 80}
    if (opts.Has("noNotifyRect") && opts["noNotifyRect"])
        rects.Delete("notify_rect")
    if opts.Has("drop")
        for id in opts["drop"] {
            if points.Has(id)
                points.Delete(id)
            if rects.Has(id)
                rects.Delete(id)
        }
    pots := opts.Has("pots") ? opts["pots"] : ["Lucky Potion", "Speed Potion"]
    routes := CrRead("routes")
    ; simple distinguishable fisher routes (the shipped ones are checked in Test_Craft_ShippedData)
    for variant in ["vip", "nonvip"] {
        routes[variant]["toShop"] := [["w", "down", 100], ["w", "up", 0], ["e", "down", 50], ["e", "up", 0]]
        routes[variant]["back"] := [["q", "down", 100], ["q", "up", 0]]
    }
    if (opts.Has("cauldron") && opts["cauldron"]) {
        gets["Craft.cauldron"] := 1
        if !gets.Has("Craft.craftTarget")
            gets["Craft.craftTarget"] := "Heavenly Potion"
        routes["cauldron"] := Map("steps", [["a", "down", 100], ["a", "up", 0]])
    }
    for key, name in Map("cauldronRoute", "cauldron") {
        if !opts.Has(key)
            continue
        if (opts[key] = "DEL")
            routes.Delete(name)
        else
            routes[name] := Map("steps", opts[key])
    }
    cfg := CrCfg(gets, Map("coords", CrRead("coords"), "routes", routes))
    io := CrIO()
    wh := CrWh()
    px := opts.Has("px") ? opts["px"] : CrPx()
    px.dyn["400,100"] := () => CrLast(io, ["move 1400,100"]) > CrLast(io, ["move 1500,100", "move 1945,355", "move 1600,100"])
    rb := opts.Has("roblox") ? opts["roblox"] : CrRoblox()
    ; OCR fake: "1150,65,300,70" is the box around fisher_open_shop (1300,100);
    ; "5,6,70,80" is notify_rect. opts "ocr" Map rect -> text overrides.
    ; Unless overridden, the shop follows the clicks: the Open Shop box reads
    ; "Open Shop" until the shop's X, the name box the potion whose tile was
    ; clicked last (nothing once the shop is closed), and the purchase window
    ; (fisher_confirm pixel "400,100") is up from Buy until its X or the shop's.
    ocrMap := Map("600,100,200,40", "Stella's Workshop"
        , "800,100,300,80", "Heavenly Potion`nThose who take this Potion will be Blessed.")
    if opts.Has("ocr")
        for k, v in opts["ocr"]
            ocrMap[k] := v
    tiles := Map()
    for name in pots {
        id := Calibrate.PotionId(name)
        if points.Has(id)
            tiles["move " points[id].x "," points[id].y] := name
    }
    ; The Fishing Shop's title (CraftTask.ShopTitle) reads from Open Shop
    ; until its X; Captain Flarg's dialog body (CraftTask.DialogBody) from E
    ; until Open Shop, Leave or the shop's X; a Roblox purchase prompt
    ; (Input.PurchaseBox) after the opts "promptAfter" entry until an Esc.
    pa := opts.Has("promptAfter") ? opts["promptAfter"] : ""
    dyn := Map("1150,65,300,70", () => CrLast(io, ["down e"]) > CrLast(io, ["move 1945,355", "move 1600,100"]) ? "Open Shop" : ""
        , "2000,200,400,60", () => CrPicked(io, tiles)
        , "570,325,380,70", () => CrLast(io, ["move 1300,100"]) > CrLast(io, ["move 1945,355", "move 1600,100"]) ? "Fishing Shop" : ""
        , "960,915,940,265", () => CrLast(io, ["down e"]) > CrLast(io, ["move 1300,100", "move 1700,100", "move 1945,355", "move 1600,100"])
            ? "Captain Flarg`nClick to skip" : ""
        , "680,320,1200,800", () => (pa != "" && io.Idx(pa) && !io.Idx("down Esc", io.Idx(pa))) ? "Buy Robux and item`nR$1,000 Donation`nBuy $4.99" : "")
    ocr := {map: ocrMap, reads: [], dyn: dyn}
    t := CraftTask({
        cfg: cfg, io: io, webhook: wh, cal: CrCal(points, pots, rects), roblox: rb,
        ocr: (x, y, w, h, scale := 1) => CrOcrRead(ocr, x, y, w, h),
        now: opts.Has("now") ? opts["now"] : "",
        pixel: (x, y, c, tol) => px.Is(x, y, c, tol),
        sample: (x, y) => px.Color(x, y)
    })
    return {t: t, io: io, wh: wh, px: px, rb: rb, cfg: cfg, ocr: ocr}
}

; ocr.map values: a String, or an Array read in order (the last repeats);
; keys not in the map but in ocr.dyn are computed from the clicks so far.
CrOcrRead(ocr, x, y, w, h) {
    k := x "," y "," w "," h
    ocr.reads.Push(k)
    if !ocr.map.Has(k)
        return (ocr.HasOwnProp("dyn") && ocr.dyn.Has(k)) ? ocr.dyn[k].Call() : ""
    v := ocr.map[k]
    if !(v is Array)
        return v
    return (v.Length > 1) ? v.RemoveAt(1) : v[1]
}

; ---- Input.TypeText / config / data -----------------------------------------

Test_Craft_TypeTextGoesThroughIo() {
    io := CrIO()
    Input.TypeText("Heavenly Potion", io)
    io.MoveTo(1, 1)
    Input.TypeText(12, io)
    AssertEq(io.log.Length, 3, "two typed texts + a move")
    AssertEq(io.log[1], "type Heavenly Potion", "text typed literally")
    AssertEq(io.log[3], "type 12", "integer typed as text")
    Input.TypeText("", io)
    AssertEq(io.log.Length, 3, "empty text types nothing")
    threw := false
    try
        Input.TypeText(Object(), io)
    catch ValueError
        threw := true
    AssertTrue(threw, "non-text rejected")
    threw := false
    try
        Input.TypeText("x", {})
    catch Error
        threw := true
    AssertTrue(threw, "backend without Type() rejected")
}

; Recorder that logs every Type/Text/Wait call separately.
class CrRawIO {
    __New(useText := false) {
        this.log := []
        if useText
            this.DefineProp("Text", {Call: (self, s) => self.log.Push("text " s)})
        else
            this.DefineProp("Type", {Call: (self, s) => self.log.Push("type " s)})
    }
    Wait(ms, ctx := "") => (this.log.Push("wait " ms), true)
}

Test_Input_TypeTextPerCharWithGap() {
    io := CrRawIO()
    Input.TypeText("Ab 1", io)
    AssertEq(io.log.Length, 7, "4 chars + 3 gaps")
    want := ["type A", "wait 80", "type b", "wait 80", "type  ", "wait 80", "type 1"]
    for w in want
        AssertEq(io.log[A_Index], w, "step " A_Index)
    ; custom gap, Text() backend
    io2 := CrRawIO(true)
    Input.TypeText("xy", io2, 25)
    AssertEq(io2.log.Length, 3, "2 chars + 1 gap")
    AssertEq(io2.log[1], "text x", "Text backend char 1")
    AssertEq(io2.log[2], "wait 25", "custom gap")
    AssertEq(io2.log[3], "text y", "Text backend char 2")
    ; gap 0: still per char, no waits
    io3 := CrRawIO()
    Input.TypeText("ok", io3, 0)
    AssertEq(io3.log.Length, 2, "no waits with gap 0")
    ; printable guard still applies before anything is sent
    io4 := CrRawIO()
    threw := false
    try Input.TypeText("a`tb", io4)
    catch ValueError
        threw := true
    AssertTrue(threw, "control char rejected")
    AssertEq(io4.log.Length, 0, "nothing sent")
    AssertEq(Input.TypeGapMs, 80, "default gap 80 ms")
}

Test_Craft_ConfigDefaultsRegistered() {
    cr := Config.IniDefaults()["Craft"]
    AssertEq(cr["potions"], "Lucky Potion,Speed Potion", "potions default kept")
    AssertEq(cr["enabled"], "1", "enabled default")
    AssertEq(cr["qty"], "1", "qty default")
    AssertEq(cr["cauldron"], "0", "cauldron toggle default off")
    AssertEq(cr["craftTarget"], "", "craftTarget default empty")
    AssertEq(cr["minIntervalMin"], "10", "minIntervalMin default 10")
}

Test_Craft_ShippedData() {
    coords := CrRead("coords")
    routes := CrRead("routes")
    c := coords["craft"]
    AssertTrue(c.Has("_source") && InStr(c["_source"], "L1961"), "craft coords carry a FishSol line-ref audit note")
    AssertEq(c["dialog"]["a"][1] "," c["dialog"]["a"][2], "1308,1073", "shop dialog click a")
    AssertEq(c["dialog"]["b"][1] "," c["dialog"]["b"][2], "870,1264", "shop dialog click b (FishSol craft value)")
    AssertEq(c["close"][1] "," c["close"][2], "1945,355", "shop close click")
    AssertTrue(!routes.Has("cauldron_return"), "no cauldron return route (craft respawns after the cauldron)")
    ; the cauldron route ships recorded by the creator (Tools > Reset restores it)
    AssertTrue(routes.Has("cauldron") && Input.ParseRoute(routes["cauldron"]).Length > 0, "cauldron route recorded")
    AssertTrue(routes["cauldron"].Has("_recorded"), "with its recording stamp")
    AssertTrue(!routes.Has("fisher"), "fisher reuses vip/nonvip toShop+back, no duplicate route")
}

; ---- CanRun ------------------------------------------------------------------

Test_Craft_FirstRunBuysConfiguredPotions() {
    m := CrMake(Map("gets", Map("Craft.qty_lucky_potion", 3)))
    AssertEq(m.t.name, "craft", "task name")
    AssertEq(m.t.priority, 4, "task priority")
    AssertEq(m.t.CanRun(SchedState()), true, "first run")
    AssertEq(m.t.Run(SchedCtx()), 2, "two buys with the shop UI seen")
    io := m.io
    iWalk := io.Idx("down w")
    iLucky := io.Idx("move 100,100")
    iQty := io.Idx("move 300,100", iLucky)
    iType := io.Idx("type 3", iQty)
    iConf := io.Idx("move 400,100", iType)
    iSpeed := io.Idx("move 200,100", iConf)
    AssertTrue(iWalk > 0 && iWalk < iLucky, "walked to the fisher before clicking")
    AssertTrue(iLucky > 0 && iQty > iLucky && iType > iQty && iConf > iType, "lucky: item, qty box, text 3, confirm")
    AssertTrue(io.Idx("move 300,100", iSpeed) > iSpeed && io.Idx("type 1", iSpeed) > iSpeed, "speed bought with the default qty 1")
    AssertTrue(io.Idx("move 1500,100", iConf) > iConf && io.Idx("move 1500,100", iConf) < iSpeed, "purchase window closed after the Lucky confirm, before Speed")
    AssertTrue(io.Idx("move 1945,355") > io.Idx("move 1500,100", iSpeed), "then the shop itself")
    AssertTrue(io.Idx("move 1945,355") > iSpeed, "shop closed afterwards")
    AssertTrue(io.Idx("down q") > io.Idx("move 1945,355"), "back route after closing")
    AssertEq(io.Count("down f"), 0, "no cauldron key when the toggle is off")
    ; 250 Lucky (the user's real need) is typed as is; above 999 is capped
    m2 := CrMake(Map("gets", Map("Craft.qty_lucky_potion", "250")))
    m2.t.Run(SchedCtx())
    AssertTrue(m2.io.Idx("type 250") > 0, "250 typed in the qty box")
    m3 := CrMake(Map("gets", Map("Craft.qty_lucky_potion", 5000)))
    m3.t.Run(SchedCtx())
    AssertTrue(m3.io.Idx("type 999") > 0, "capped at 999")
    AssertTrue(io.Balanced(), "no key left down")
    AssertEq(m.wh.Count("craft"), 1, "one craft webhook")
    AssertEq(m.wh.Count("errors"), 0, "no errors")
    d := m.wh.Desc("craft")
    AssertTrue(InStr(d, "clicked Buy x3 for Lucky Potion (shop UI seen)"), "lucky report")
    AssertTrue(InStr(d, "clicked Buy x1 for Speed Potion (shop UI seen)"), "speed report")
    AssertEq(m.t.CanRun(SchedState()), false, "not again until the notification")
}

Test_Craft_NotifyTriggersRerun() {
    clk := {t: 1000000}
    m := CrMake(Map("now", () => clk.t))
    AssertEq(m.t.CanRun(SchedState()), true, "first run")
    m.t.Run(SchedCtx())
    AssertEq(m.t.CanRun(SchedState()), false, "idle without notification")
    clk.t += 10 * 60000                 ; past the default 10 min interval
    m.ocr.map["5,6,70,80"] := "Auto crafted Lucky Potion x1"
    AssertEq(m.t.CanRun(SchedState()), true, "crafted notification read in notify_rect")
    m.ocr.map["5,6,70,80"] := ""
    clk.t += 2000
    AssertEq(m.t.CanRun(SchedState()), true, "notification latched until the run happens")
    m.io.log := []
    AssertEq(m.t.Run(SchedCtx()), 2, "second visit buys again")
    AssertTrue(m.io.Count("move 400,100") = 2, "confirm clicked for both potions again")
    AssertEq(m.t.CanRun(SchedState()), false, "latch cleared by the run")
    ; disabled in settings -> never
    m2 := CrMake(Map("gets", Map("Craft.enabled", 0)))
    AssertEq(m2.t.CanRun(SchedState()), false, "Craft.enabled=0")
}

Test_Craft_NotifyNeedsIntervalAndCraftedText() {
    clk := {t: 5000000}
    m := CrMake(Map("now", () => clk.t))
    m.t.Run(SchedCtx())                 ; first run at t0
    m.ocr.map["5,6,70,80"] := "Potion Crafted!"
    AssertEq(m.t.CanRun(SchedState()), false, "within 10 min of the last run: no rerun")
    AssertEq(CrCount(m.ocr.reads, "5,6,70,80"), 0, "notify_rect not even read during the interval")
    clk.t += 9 * 60000 + 59000
    AssertEq(m.t.CanRun(SchedState()), false, "9:59 later: still no rerun")
    clk.t += 1000
    AssertEq(m.t.CanRun(SchedState()), true, "10 min later + crafted text: rerun")
    m.t.Run(SchedCtx())
    ; other notifications do not trigger, and reads are throttled
    clk.t += 10 * 60000
    m.ocr.map["5,6,70,80"] := "There are no quests available"
    n0 := CrCount(m.ocr.reads, "5,6,70,80")
    AssertEq(m.t.CanRun(SchedState()), false, "a different notification is not a craft")
    AssertEq(m.t.CanRun(SchedState()), false, "polled again at once")
    AssertEq(CrCount(m.ocr.reads, "5,6,70,80") - n0, 1, "read at most once per NotifyPollMs")
    ; no notify_rect: only the first run
    m3 := CrMake(Map("now", () => clk.t, "noNotifyRect", true))
    m3.t.Run(SchedCtx())
    clk.t += 60 * 60000
    AssertEq(m3.t.CanRun(SchedState()), false, "no notify_rect -> no notification reruns")
    ; configurable interval; bad values fall back to 10
    m2 := CrMake(Map("now", () => clk.t, "gets", Map("Craft.minIntervalMin", 2)))
    m2.t.Run(SchedCtx())
    m2.ocr.map["5,6,70,80"] := "Auto crafted Speed Potion"
    clk.t += 2 * 60000
    AssertEq(m2.t.CanRun(SchedState()), true, "Craft.minIntervalMin = 2 honoured")
    m4 := CrMake(Map("now", () => clk.t, "gets", Map("Craft.minIntervalMin", 0)))
    m4.t.Run(SchedCtx())
    m4.ocr.map["5,6,70,80"] := "Auto crafted Speed Potion"
    clk.t += 2 * 60000
    AssertEq(m4.t.CanRun(SchedState()), false, "0 is not allowed: default 10 min applies")
}

Test_Craft_NotifyInTheGameFont() {
    ; 2026-10-27 review: the game font draws "a" like "o", so the toast reads
    ; "Auto crofted ..." and "i)craft" never matched after the first run
    clk := {t: 2000000}
    for toast in ["Auto crofted Lucky Potion x1", "Potion Crofted!", "Auto crafted Speed Potion"] {
        m := CrMake(Map("now", () => clk.t))
        m.t.Run(SchedCtx())
        clk.t += 10 * 60000
        m.ocr.map["5,6,70,80"] := toast
        AssertEq(m.t.CanRun(SchedState()), true, "'" toast "' triggers a rerun")
        AssertEq(m.t.BuyDue(), true, "'" toast "': Sell buys in its visit too")
    }
    m := CrMake(Map("now", () => clk.t))
    m.t.Run(SchedCtx())
    clk.t += 10 * 60000
    m.ocr.map["5,6,70,80"] := "Stort Memor Moach?"
    AssertEq(m.t.CanRun(SchedState()), false, "another toast in the game font is not a craft")
}

Test_Craft_NoNotifyReadWhileARoutePlays() {
    ; CanRun runs on the App's tick: an OCR there while a route plays froze
    ; the walk with a key held (2026-10-27 review)
    clk := {t: 3000000}
    m := CrMake(Map("now", () => clk.t))
    m.t.Run(SchedCtx())
    clk.t += 10 * 60000
    m.ocr.map["5,6,70,80"] := "Auto crofted Lucky Potion x1"
    n0 := CrCount(m.ocr.reads, "5,6,70,80")
    Input.InRoute := true
    try {
        AssertEq(m.t.CanRun(SchedState()), false, "not while a route plays")
        AssertEq(CrCount(m.ocr.reads, "5,6,70,80") - n0, 0, "notify_rect not read during the walk")
    } finally {
        Input.InRoute := false
    }
    AssertEq(m.t.CanRun(SchedState()), true, "read once the walk is over")
}

; A Roblox text box as the game keeps it: its text survives between visits
; (`start`); a click on `pt` focuses it with the caret at `caretAt` ("end",
; or 0 = the click landed left of the text); End moves the caret to the end,
; Backspace deletes before it, typing inserts at it. Ctrl+A does nothing.
; Reads the io log up to entry `upto` (0 = all).
CrBox(io, pt, start, caretAt := "end", upto := 0) {
    text := start, caret := StrLen(start), focused := false
    Loop (upto ? upto : io.log.Length) {
        e := io.log[A_Index]
        if (SubStr(e, 1, 5) = "move ") {
            focused := (e = "move " pt)
            if focused
                caret := (caretAt = "end") ? StrLen(text) : caretAt
        } else if !focused {
            continue
        } else if (e = "down End") {
            caret := StrLen(text)
        } else if (e = "down Backspace") {
            if (caret > 0) {
                text := SubStr(text, 1, caret - 1) SubStr(text, caret + 1)
                caret--
            }
        } else if (SubStr(e, 1, 5) = "type ") {
            s := SubStr(e, 6)
            text := SubStr(text, 1, caret) s SubStr(text, caret + 1)
            caret += StrLen(s)
        }
    }
    return text
}

Test_Craft_CauldronSearchBoxIsClearedFirst() {
    ; the box still holds the last visit's search (or a manual one): typed on
    ; top of it the search shows no result (2026-10-27 review)
    CrCauldronWithLeftover("Heavenly Potion")
    CrCauldronWithLeftover("Fortune")
}

; One cauldron visit whose search box starts with `left`; the first result
; card shows the recipe only when the box reads exactly its name.
CrCauldronWithLeftover(left) {
    m := CrMake(Map("cauldron", true))
    io := m.io
    m.ocr.map.Delete("800,100,300,80")
    m.ocr.dyn["800,100,300,80"] := () => (CrBox(io, "700,100", left) = "Heavenly Potion")
        ? "Heavenly Potion`nThose who take this Potion will be Blessed." : ""
    m.t.Run(SchedCtx())
    AssertEq(CrBox(io, "700,100", left), "Heavenly Potion", "'" left "' left in the box: emptied, then typed")
    AssertTrue(io.Idx("move 950,140") > 0, "'" left "': the result card clicked")
    AssertEq(m.wh.Count("errors"), 0, "'" left "': no 'recipe not found' error")
}

Test_Craft_QtyBoxKeepsItsNumber() {
    ; the qty box keeps "1" and the click can put the caret before it: the old
    ; 6 Backspaces deleted nothing and "3" made "31" (2026-10-27 review)
    m := CrMake(Map("pots", ["Lucky Potion"], "gets", Map("Craft.qty_lucky_potion", 3)))
    AssertEq(m.t.Run(SchedCtx()), 1, "bought")
    iConf := m.io.Idx("move 400,100")
    AssertTrue(iConf > 0, "confirm clicked")
    AssertEq(CrBox(m.io, "300,100", "1", 0, iConf), "3", "the box reads 3 when Confirm is pressed")
}

Test_Craft_BuyHereShopNotOpenedStaysDue() {
    ; his Open Shop button never read: nothing bought, so the buy must stay
    ; due instead of waiting for the next crafted toast (2026-10-27 review)
    m := CrMake(Map("ocr", Map("1150,65,300,70", "Sell Fish")))
    r := m.t.BuyHere(SchedCtx())
    AssertEq(r, 0, "nothing bought (0, not < 0: Sell still walks back)")
    AssertEq(m.io.Count("move 100,100"), 0, "no potion clicked")
    AssertEq(m.t.BuyDue(), true, "the buy is still due")
    AssertEq(m.t.CanRun(SchedState()), true, "a craft trip retries it")
    ; a craft trip whose shop never opens is reported and does not spin
    m2 := CrMake(Map("ocr", Map("1150,65,300,70", "Sell Fish")))
    AssertEq(m2.t.Run(SchedCtx()), 0, "trip: nothing bought")
    AssertTrue(m2.io.Idx("down q") > 0, "trip: walked back")
    AssertEq(m2.t.CanRun(SchedState()), false, "trip: no instant retry loop")
}

; SchedCtx that turns preempted (or stopped: halt = true) the first time
; ShouldStop is asked after `trigger` shows in the io log. at = the log
; length at that moment.
class CrPreemptCtx extends SchedCtx {
    __New(io, trigger, halt := false) {
        super.__New()
        this.io := io
        this.trigger := trigger
        this.halt := halt
        this.at := 0
    }
    ShouldStop() {
        if (!this.at && this.io.Idx(this.trigger)) {
            this.at := this.io.log.Length
            if this.halt
                this.Stop()
            else
                this.RequestPreempt()
        }
        return super.ShouldStop()
    }
}

Test_Craft_PreemptInTheShopClosesIt() {
    ; preempted right after Buy (purchase window up, shop open, his dialog
    ; behind it): the purchase window, the shop and his dialog are closed
    ; before the next task starts (2026-10-27 review)
    m := CrMake(Map("pots", ["Lucky Potion"]))
    io := m.io
    m.t._env.cal.p["fisher_leave"] := {x: 1700, y: 100, color: 0}
    m.ocr.dyn["1150,65,300,70"] := () => CrLast(io, ["move 1700,100"]) ? "" : CrLast(io, ["down e"]) ? "Open Shop" : ""
    ctx := CrPreemptCtx(io, "move 1400,100")
    AssertEq(m.t.Run(ctx), 0, "preempted: nothing confirmed")
    AssertTrue(ctx.at > 0, "the preempt came")
    iPc := io.Idx("move 1500,100", ctx.at)
    iX := io.Idx("move 1945,355", ctx.at)
    iLeave := io.Idx("move 1700,100", ctx.at)
    AssertTrue(iPc > 0 && iX > iPc && iLeave > iX, "purchase window, shop X, then Leave")
    AssertEq(io.Count("move 400,100"), 0, "Confirm never pressed")
    AssertEq(io.Count("down q"), 0, "no walk back (the next task runs)")
    AssertTrue(io.Balanced(), "no key left down")
    AssertEq(m.t.CanRun(SchedState()), true, "retried later")
    ; F3 / pause at the same moment: nothing more is sent
    m2 := CrMake(Map("pots", ["Lucky Potion"]))
    ctx2 := CrPreemptCtx(m2.io, "move 1400,100", true)
    m2.t.Run(ctx2)
    i := ctx2.at + 1
    while (i <= m2.io.log.Length) {
        e := m2.io.log[i]
        if (SubStr(e, 1, 4) = "move" || e = "click" || SubStr(e, 1, 4) = "type")
            throw Error("'" e "' sent after a halt")
        i++
    }
}

Test_Craft_BuyHereDuringTheSellVisit() {
    ; Sell is at Captain Flarg: buy in the same visit, no respawn, no walk
    m := CrMake()
    AssertTrue(m.t.BuyDue(), "first buy since start is due")
    AssertEq(m.t.BuyHere(SchedCtx()), 2, "both potions bought")
    io := m.io
    AssertEq(io.Idx("down e"), 1, "first thing: E to talk to Flarg again")
    AssertEq(io.Count("down Esc"), 0, "no respawn")
    AssertEq(io.Count("down w") + io.Count("down q"), 0, "no walking (Sell walks back afterwards)")
    AssertTrue(io.Idx("move 1300,100") > 0 && io.Idx("move 100,100") > io.Idx("move 1300,100"), "Open Shop, then the potions")
    AssertTrue(InStr(m.wh.Desc("craft"), "Lucky Potion"), "reported")
    AssertEq(m.t.BuyDue(), false, "nothing left to buy")
    AssertEq(m.t.CanRun(SchedState()), false, "no separate buying trip after it")
    ; with the cauldron step: the craft run afterwards only does the cauldron
    m2 := CrMake(Map("cauldron", true))
    m2.t.BuyHere(SchedCtx())
    m2.io.log := []
    AssertEq(m2.t.CanRun(SchedState()), true, "cauldron still to do")
    m2.t.Run(SchedCtx())
    AssertEq(m2.io.Count("move 100,100"), 0, "no second purchase")
    AssertEq(m2.io.Count("down f"), 1, "the cauldron step ran")
    ; disabled: never due
    m3 := CrMake(Map("gets", Map("Craft.enabled", 0)))
    AssertEq(m3.t.BuyDue(), false, "Craft.enabled = 0")
}

Test_Craft_ClosesPurchaseWindowThenShop() {
    ; recorded shop X wins over the FishSol spot; purchase window needed
    m := CrMake(Map("pots", ["Lucky Potion"]))
    m.t._env.cal.p["fisher_shop_close"] := {x: 1600, y: 100, color: 0}
    m.t.Run(SchedCtx())
    iPc := m.io.Idx("move 1500,100")
    iShop := m.io.Idx("move 1600,100")
    AssertTrue(iPc > 0 && iShop > iPc, "purchase window, then the recorded shop X")
    AssertEq(m.io.Count("move 1945,355"), 0, "FishSol spot not used when recorded")
    m2 := CrMake(Map("drop", ["fisher_purchase_close"]))
    AssertEq(m2.t.Run(SchedCtx()), 0, "no purchase-window close recorded: buying skipped")
    AssertEq(m2.io.log.Length, 0, "no input at all")
}

Test_Craft_OpenShopButtonMustReadShop() {
    ; Captain Flarg shows Sell Fish and Open Shop: only a button reading "shop" is clicked
    m := CrMake(Map("ocr", Map("1150,65,300,70", "Sell Fish")))
    AssertEq(m.t.Run(SchedCtx()), 0, "nothing bought")
    AssertTrue(m.io.Idx("move 1300,100") = 0, "Sell Fish never clicked as Open Shop")
    AssertTrue(m.io.Idx("move 100,100") = 0 && m.io.Idx("move 300,100") = 0 && m.io.Idx("move 400,100") = 0, "no potion, qty or confirm click")
    AssertEq(m.io.Count("type 1"), 0, "nothing typed")
    AssertEq(m.wh.Count("errors"), 1, "reported")
    AssertTrue(InStr(m.wh.Desc("craft"), "Open Shop button not seen"), "craft report says why")
    ; the button text shows a moment later: waited for, then clicked before buying
    m2 := CrMake(Map("ocr", Map("1150,65,300,70", ["", "", "Open Shop"])))
    AssertEq(m2.t.Run(SchedCtx()), 2, "bought after the button appeared")
    iShop := m2.io.Idx("move 1300,100")
    AssertTrue(iShop > 0 && iShop < m2.io.Idx("move 100,100"), "Open Shop clicked before the first potion")
    ; not calibrated: the buy part is skipped without input
    m3 := CrMake(Map("drop", ["fisher_open_shop"]))
    AssertEq(m3.t.Run(SchedCtx()), 0, "no buys")
    AssertEq(m3.io.log.Length, 0, "no input without the Open Shop step")
}

; Index of the last io log entry equal to one of `texts`, 0 if none.
CrLast(io, texts) {
    i := io.log.Length
    while (i >= 1) {
        for t in texts
            if (io.log[i] = t)
                return i
        i--
    }
    return 0
}

; The shop's X (FishSol spot or the recorded one) was clicked after Open Shop.
CrShopShut(io) => CrLast(io, ["move 1945,355", "move 1600,100"]) > CrLast(io, ["move 1300,100"])

; The potion whose tile was clicked last while the shop is open, else "".
CrPicked(io, tiles) {
    if CrShopShut(io)
        return ""
    i := io.log.Length
    while (i >= 1) {
        if tiles.Has(io.log[i])
            return tiles[io.log[i]]
        if (io.log[i] = "move 1300,100")
            return ""
        i--
    }
    return ""
}

CrCount(arr, v) {
    n := 0
    for x in arr
        n += (x = v) ? 1 : 0
    return n
}

Test_Craft_FocusFailureDoesNotSpin() {
    rb := CrRoblox(false)
    clk := {t: 1000000}
    m := CrMake(Map("roblox", rb, "now", () => clk.t))
    AssertEq(m.t.Run(SchedCtx()), 0, "nothing done")
    AssertEq(m.io.log.Length, 0, "no input without Roblox focus")
    ; live 2026-11-09 (title screen): it relaunched every ~14 s for 7+ min
    AssertEq(m.t.CanRun(SchedState()), false, "no instant relaunch")
    clk.t += CraftTask.RetryGapMs
    AssertEq(m.t.CanRun(SchedState()), true, "retried after the gap")
    m.t.Run(SchedCtx())
    clk.t += CraftTask.RetryGapMs
    AssertEq(m.t.CanRun(SchedState()), false, "a second early end in a row: the gap doubles")
    clk.t += CraftTask.RetryGapMs
    AssertEq(m.t.CanRun(SchedState()), true, "after twice the gap")
    ; cut short by a stop / preempt: again as soon as it is over
    m2 := CrMake(Map("now", () => clk.t))
    c := SchedCtx()
    c.RequestPreempt()
    m2.t.Run(c)
    AssertEq(m2.t.CanRun(SchedState()), true, "a preempted run is retried at once")
}

; ---- missing calibration -------------------------------------------------------

Test_Craft_MissingCalibrationSkipsPartWithoutClicks() {
    ; no quantity box -> the whole buying part is skipped: no walk, no clicks
    m := CrMake(Map("drop", ["fisher_qty"]))
    AssertEq(m.t.Run(SchedCtx()), 0, "no buys")
    AssertEq(m.io.log.Length, 0, "no input at all")
    AssertEq(m.wh.Count("errors"), 1, "errors webhook once")
    AssertEq(m.wh.Count("craft"), 0, "no craft claim")
    m.t.Run(SchedCtx())
    AssertEq(m.wh.Count("errors"), 1, "still once on the next run")
    ; no confirm button
    m2 := CrMake(Map("drop", ["fisher_confirm"]))
    m2.t.Run(SchedCtx())
    AssertEq(m2.io.log.Length, 0, "no confirm calibration: no input")
    ; one potion's buy button missing: only that potion is skipped
    m3 := CrMake(Map("drop", ["fisher_item_speed_potion"]))
    AssertEq(m3.t.Run(SchedCtx()), 1, "lucky only")
    AssertEq(m3.io.Count("move 200,100"), 0, "speed never clicked")
    AssertTrue(!InStr(m3.wh.Desc("craft"), "Speed"), "speed not claimed")
    AssertEq(m3.wh.Count("errors"), 1, "missing speed button reported once")
    ; nothing calibrated at all
    m4 := CrMake(Map("drop", ["fisher_item_lucky_potion", "fisher_item_speed_potion"]))
    m4.t.Run(SchedCtx())
    AssertEq(m4.io.log.Length, 0, "no potion buttons: no walk")
}

; ---- purchase verification ---------------------------------------------------------

Test_Craft_VerifyFailureRetriesOnceThenReports() {
    px := CrPx()
    px.Set("400,100", false)                 ; shop UI never shows the confirm button
    m := CrMake(Map("px", px, "pots", ["Lucky Potion"]))
    px.Set("500,100", false)
    AssertEq(m.t.Run(SchedCtx()), 0, "nothing bought")
    ; purchase window never opens: the tile and Buy are tried, but nothing is
    ; typed (digits equip hotbar slots) and the qty box is never clicked
    AssertEq(m.io.Count("move 100,100"), 2, "tile picked once (hover to scroll, then the click)")
    AssertEq(m.io.Count("move 1400,100"), 2, "Buy pressed on each try")
    AssertEq(m.io.Count("move 300,100"), 0, "qty box never clicked")
    AssertEq(m.io.Count("down Backspace"), 0, "no Backspace")
    for e in m.io.log
        if (SubStr(e, 1, 4) = "type")
            throw Error("typed '" e "' with the shop closed")
    AssertEq(m.io.Count("move 400,100"), 0, "confirm never clicked blind")
    AssertEq(px.Queries("400,100"), 5, "purchase window checked on both tries, twice more to be sure it is closed, once more before calling the shop closed")
    AssertEq(m.io.Count("move 1500,100"), 0, "no purchase window to close")
    AssertEq(m.wh.Count("errors"), 1, "errors webhook after the retry")
    d := m.wh.Desc("craft")
    AssertTrue(!InStr(d, "(shop UI seen)") && !InStr(d, "clicked Buy"), "no success claimed")
    AssertTrue(InStr(d, "Lucky Potion") && InStr(d, "not seen"), "failure worded as not seen")
    AssertTrue(m.io.Idx("down q") > 0, "continues: walks back to fishing")
    AssertEq(m.t.CanRun(SchedState()), false, "no respin after a verify failure")
    ; first attempt fails, retry works
    px2 := CrPx()
    px2.Set("400,100", [false, true, true, false])       ; not up, up, up at confirm, closed
    m2 := CrMake(Map("px", px2, "pots", ["Lucky Potion"]))
    px2.Set("400,100", [false, true, true, false])
    AssertEq(m2.t.Run(SchedCtx()), 1, "retry works")
    AssertEq(m2.io.Count("move 400,100"), 1, "confirm clicked once")
    AssertEq(m2.io.Count("type 1"), 1, "typed only once the shop was seen")
    AssertEq(m2.wh.Count("errors"), 0, "no error when the retry works")
    AssertTrue(InStr(m2.wh.Desc("craft"), "clicked Buy x1 for Lucky Potion (shop UI seen)"), "shop UI seen after retry")
    ; shop seen at first but the confirm button gone after typing: retry, then clicked
    px3 := CrPx()
    px3.Set("400,100", [true, false, false, true, true, false])   ; up, gone after typing (closed), up, up, closed
    m3 := CrMake(Map("px", px3, "pots", ["Lucky Potion"]))
    px3.Set("400,100", [true, false, false, true, true, false])
    AssertEq(m3.t.Run(SchedCtx()), 1, "second attempt confirmed")
    AssertEq(m3.io.Count("move 400,100"), 1, "confirm clicked once")
    AssertEq(m3.io.Count("down Backspace"), 2 * Input.ClearKeys, "field cleared before each typing")
    AssertEq(m3.io.Count("down End"), 2, "End first each time (the caret may sit before the old number)")
}

; ---- what is bought, and that everything closes ------------------------------

Test_Craft_WrongItemIsNeverBought() {
    ; the shop was left scrolled: Lucky Potion's tile shows Eternal Flame
    m := CrMake(Map("pots", ["Lucky Potion"], "ocr", Map("2000,200,400,60", ["Eternal Flame", "Eternal Flame", "Eternal Flame", "Eternal Flame", "Eternal Flame", "Eternal Flame", "Eternal Flame", "Eternal Flame", "Eternal Flame", ""])))
    AssertEq(m.t.Run(SchedCtx()), 0, "nothing bought")
    io := m.io
    AssertEq(io.Count("move 1400,100"), 0, "Buy never pressed on the wrong item")
    AssertEq(io.Count("move 300,100") + io.Count("move 400,100"), 0, "no quantity, no confirm")
    for e in io.log
        if (SubStr(e, 1, 4) = "type")
            throw Error("typed '" e "' while the wrong item was picked")
    iShop := io.Idx("move 1300,100")                  ; Open Shop (the camera zoom before it also wheels)
    AssertEq(io.Count("wheel up " CraftTask.ScrollTopNotches, iShop), 1, "scrolled to the top first")
    AssertEq(io.Count("wheel down 1", iShop), CraftTask.ScrollTries, "then searched one notch at a time")
    AssertEq(m.wh.Count("errors"), 1, "reported")
    AssertTrue(InStr(m.wh.Desc("craft"), "not found in the shop") && InStr(m.wh.Desc("craft"), "Eternal Flame"), "report names what was picked")
    AssertTrue(io.Idx("move 1945,355") > 0, "the shop is still closed")
}

Test_Craft_ScrollsDownToFindTheItem() {
    m := CrMake(Map("pots", ["Lucky Potion"], "ocr", Map("2000,200,400,60", ["Eternal Flame", "Eternal Flame", "Eternal Flame", "Eternal Flame", "Hour Glass", "Hour Glass", "LucI<y Potion", ""])))   ; each try reads at 1x and 2x; try 2 clicks the same tile again
    AssertEq(m.t.Run(SchedCtx()), 1, "bought once found")
    io := m.io
    iUp := io.Idx("wheel up " CraftTask.ScrollTopNotches, io.Idx("move 1300,100"))
    iBuy := io.Idx("move 1400,100")
    AssertTrue(iUp > 0 && iBuy > iUp, "top first, Buy after")
    AssertEq(io.Count("wheel down 1", iUp), 2, "two notches down to reach it")
    AssertEq(io.Count("move 1400,100"), 1, "Buy pressed once")
    AssertEq(m.wh.Count("errors"), 0, "no error")
}

Test_Craft_ShopThatWillNotCloseIsReported() {
    ; the name box keeps showing a shop item: the X is tried CloseTries times
    m := CrMake(Map("pots", ["Lucky Potion"], "ocr", Map("2000,200,400,60", "Lucky Potion")))
    AssertEq(m.t.Run(SchedCtx()), 1, "the purchase itself worked")
    AssertEq(m.io.Count("move 1945,355"), CraftTask.CloseTries, "shop X tried CloseTries times")
    AssertEq(m.wh.Count("errors"), 1, "reported")
    AssertTrue(InStr(m.wh.Desc("craft"), "still open after closing: the shop"), "report says the shop stayed open")
}

Test_Craft_FlargDialogIsLeft() {
    ; after the shop closes Captain Flarg's buttons are still up: Leave
    m := CrMake(Map("pots", ["Lucky Potion"], "ocr", Map("1150,65,300,70", ["Open Shop", "Open Shop", ""])))
    m.t._env.cal.p["fisher_leave"] := {x: 1700, y: 100, color: 0}
    AssertEq(m.t.Run(SchedCtx()), 1, "bought")
    iShop := m.io.Idx("move 1945,355")
    AssertTrue(m.io.Idx("move 1700,100") > iShop, "Leave clicked after the shop's X")
    AssertEq(m.wh.Count("errors"), 0, "closed: no error")
    ; without the Leave step the dialog is only reported
    m2 := CrMake(Map("pots", ["Lucky Potion"], "ocr", Map("1150,65,300,70", "Open Shop")))
    m2.t.Run(SchedCtx())
    AssertEq(m2.wh.Count("errors"), 1, "reported")
    AssertTrue(InStr(m2.wh.Desc("craft"), "fisher_leave"), "report says which step to record")
}

Test_Craft_PurchaseWindowClosedAndChecked() {
    ; the purchase window needs two clicks on its X
    px := CrPx()
    px.Set("400,100", [true, true, true, true, false])   ; up, up at confirm, still up, still up, closed
    m := CrMake(Map("px", px, "pots", ["Lucky Potion"]))
    px.Set("400,100", [true, true, true, true, false])
    AssertEq(m.t.Run(SchedCtx()), 1, "bought")
    AssertEq(m.io.Count("move 1500,100"), 2, "its X clicked until it was gone")
    AssertTrue(m.io.Idx("move 1945,355") > m.io.Idx("move 1500,100"), "then the shop")
    AssertEq(m.wh.Count("errors"), 0, "no error")
}

Test_Craft_OpenShopNotSeenLeavesTheDialog() {
    ; his dialog is up but Open Shop never reads: nothing bought, Leave clicked
    m := CrMake(Map("pots", ["Lucky Potion"], "ocr", Map("1150,65,300,70", "Sell Fish")))
    m.t._env.cal.p["fisher_leave"] := {x: 1700, y: 100, color: 0}
    AssertEq(m.t.Run(SchedCtx()), 0, "nothing bought")
    AssertEq(m.io.Count("move 1300,100"), 0, "Open Shop never clicked")
    AssertEq(m.io.Count("move 1700,100"), CraftTask.CloseTries, "Leave clicked while his dialog stays up")
    AssertEq(m.wh.Count("errors"), 1, "one report")
    AssertTrue(InStr(m.wh.Desc("errors"), "still open"), "says the dialog stayed open")
    ; Leave works the first time
    m2 := CrMake(Map("pots", ["Lucky Potion"], "ocr", Map("1150,65,300,70", "Sell Fish")))
    m2.t._env.cal.p["fisher_leave"] := {x: 1700, y: 100, color: 0}
    m2.ocr.map.Delete("1150,65,300,70")
    m2.ocr.dyn["1150,65,300,70"] := () => CrLast(m2.io, ["move 1700,100"]) ? "" : "Sell Fish"
    m2.t.Run(SchedCtx())
    AssertEq(m2.io.Count("move 1700,100"), 1, "Leave once")
    AssertTrue(!InStr(m2.wh.Desc("errors"), "still open"), "closed: not reported as open")
    ; his dialog TEXT still up (no buttons yet) also counts as open
    m3 := CrMake(Map("pots", ["Lucky Potion"], "ocr", Map("1150,65,300,70", "", "960,915,940,265", "Captain Flarg / Click to skip.")))
    m3.t._env.cal.p["fisher_leave"] := {x: 1700, y: 100, color: 0}
    m3.t.Run(SchedCtx())
    AssertTrue(m3.io.Count("move 1700,100") >= 1, "Leave clicked for his dialog text")
    AssertTrue(m3.io.Idx("move 1308,1073") > 0, "skip clicks tried before giving up")
}

Test_Craft_BuyHereWithButtonsStillUp() {
    ; after the sell his Open Shop button is still showing: no E, straight to the shop
    m := CrMake(Map("ocr", Map("1150,65,300,70", ["Open Shop", "Open Shop", "Open Shop", ""])))
    AssertEq(m.t.BuyHere(SchedCtx()), 2, "both potions bought")
    AssertEq(m.io.Count("down e"), 0, "no E (it would close his dialog)")
    AssertTrue(m.io.Idx("move 1300,100") > 0, "Open Shop clicked")
    AssertEq(m.io.Count("move 1308,1073"), 0, "no skip clicks needed")
}

Test_Craft_PurchaseWindowSeenByItsTitle() {
    ; the confirm pixel sits between the price digits ("2,500"): the title
    ; "Confirm Purchase" (box "-70,-245,520,70" from fisher_confirm 400,100) still shows it
    px := CrPx()
    px.Set("400,100", false)
    m := CrMake(Map("px", px, "pots", ["Lucky Potion"]))
    px.Set("400,100", false)
    m.ocr.dyn["-70,-245,520,70"] := () => CrLast(m.io, ["move 1400,100"]) > CrLast(m.io, ["move 1500,100", "move 1945,355"]) ? "Confirm Purchose" : ""
    AssertEq(m.t.Run(SchedCtx()), 1, "bought")
    AssertEq(m.io.Count("move 400,100"), 1, "confirm clicked")
    AssertEq(m.io.Count("move 1500,100"), 1, "purchase window closed with its X")
    AssertTrue(m.io.Idx("move 1945,355") > m.io.Idx("move 1500,100"), "then the shop")
    AssertEq(m.wh.Count("errors"), 0, "no error")
}

Test_Craft_PartlyCoveredNameMeansShopOpen() {
    ; after the X the name box reads "Lucky Po": still open, the X is tried again
    m := CrMake(Map("pots", ["Lucky Potion"]))
    m.ocr.dyn["2000,200,400,60"] := () => CrLast(m.io, ["move 1945,355"]) = 0 ? CrPicked(m.io, Map("move 100,100", "Lucky Potion"))
        : (m.io.Count("move 1945,355") < 2 ? "Lucky Po" : "")
    AssertEq(m.t.Run(SchedCtx()), 1, "bought")
    AssertEq(m.io.Count("move 1945,355"), 2, "a partial name is still the shop: X clicked again")
    AssertEq(m.wh.Count("errors"), 0, "closed in the end: no error")
}

Test_Craft_LostTileClickIsClickedAgain() {
    ; the first click is lost (the panel still shows an older pick): the same
    ; tile is clicked again before any scrolling
    m := CrMake(Map("pots", ["Lucky Potion"], "ocr", Map("2000,200,400,60", ["Speed Potion", "Speed Potion", "Lucky Potion", ""])))
    AssertEq(m.t.Run(SchedCtx()), 1, "bought")
    AssertEq(m.io.Count("wheel down 1"), 0, "no scrolling needed")
    AssertEq(m.wh.Count("errors"), 0, "no error")
}

Test_Craft_ShopStillOpenAfterTheSell() {
    ; the Fishing Shop is still open when the buy starts: no E (it would bring
    ; Captain Flarg's dialog over the shop), no Open Shop, the Buy tab instead
    m := CrMake()
    m.ocr.dyn["570,325,380,70"] := () => CrLast(m.io, ["move 1945,355", "move 1600,100"]) ? "" : "Fishing Shop"
    AssertEq(m.t.BuyHere(SchedCtx()), 2, "both potions bought")
    AssertEq(m.io.Count("down e"), 0, "no E")
    AssertEq(m.io.Count("move 1300,100"), 0, "no Open Shop click")
    AssertEq(m.io.Count("move 1308,1073"), 0, "no dialog clicks")
    iTab := m.io.Idx("move 1241,397")
    AssertTrue(iTab > 0 && iTab < m.io.Idx("move 100,100"), "Buy tab before the first potion")
}

Test_Craft_NameBoxRequiredToBuy() {
    m := CrMake(Map("drop", ["fisher_picked_name"]))
    AssertEq(m.t.Run(SchedCtx()), 0, "no buys")
    AssertEq(m.io.log.Length, 0, "no input at all")
    AssertEq(m.wh.Count("errors"), 1, "reported")
    AssertTrue(InStr(m.wh.Desc("errors"), "fisher_picked_name"), "names the step to record")
}

Test_Craft_IsItem() {
    for t in [["Lucky Potion", "Lucky Potion", true], ["LucI<y Potion", "Lucky Potion", true]
            , ["Haste Potion III`nThe Power of the Wind", "Haste Potion III", true]
            , ["Fortune Potion III", "Fortune Potion II", false], ["Eternal Flame", "Lucky Potion", false]
            , ["", "Lucky Potion", false], ["NULL?", "NULL?", true]
            ; real Windows OCR reads of the creator's shop screenshots (2026-10-26)
            , ["Lucl" Chr(0xAB) "y Potion", "Lucky Potion", true], ["Roiny Bottle", "Rainy Bottle", true]
            , ["Hoste Potion III", "Haste Potion III", true], ["Eternal Flome", "Eternal Flame", true]
            , ["Curruptoine", "Curruptaine", true], ["Hour Gloss", "Hour Glass", true], ["Warp Poti", "Warp Potion", true]
            ; a near read never passes as a different potion
            , ["Fortune Potion III", "Haste Potion III", false], ["Speed Potion", "Lucky Potion", false]
            , ["Warp Poti", "Heavenly Potion", false], ["Lucl" Chr(0xAB) "y Potion", "Speed Potion", false]]
        AssertEq(CraftTask.IsItem(t[1], t[2]), t[3], "IsItem '" t[1] "' vs '" t[2] "'")
    AssertEq(GameLists.Distance("kitten", "sitting"), 3, "edit distance")
    AssertEq(GameLists.Distance("", "abc"), 3, "edit distance from empty")
}

; ---- cauldron -------------------------------------------------------------------------

Test_Craft_CauldronFullSequence() {
    m := CrMake(Map("cauldron", true))
    AssertEq(m.t.Run(SchedCtx()), 2, "buys done")
    io := m.io
    iRoute := io.Idx("down a")
    iFkey := io.Idx("down f", iRoute)
    AssertTrue(iRoute > 0, "cauldron route walked")
    AssertEq(io.Count("down f"), 1, "F pressed once (GUI opened first try)")
    AssertEq(io.Count("down e", iRoute), 0, "E never pressed for the cauldron")
    AssertTrue(iFkey > iRoute + 1, "F only after the route ended")
    iSearch := io.Idx("move 700,100", iFkey)
    iType := io.Idx("type Heavenly Potion", iSearch)
    iResult := io.Idx("move 950,140", iType)
    iOpen := io.Idx("move 900,100", iResult)
    iAdd := io.Idx("move 1000,100", iOpen)
    iClose := io.Idx("move 1100,100", iAdd)
    iReset := io.Idx("down Esc", iClose)
    AssertTrue(iSearch > 0 && iType > iSearch && iResult > iType && iOpen > iResult && iAdd > iOpen && iClose > iAdd && iReset > iClose,
        "search, type, result, open recipe, add all, close, then respawn")
    AssertTrue(io.Idx("down Enter", iReset) > iReset, "the respawn is confirmed")
    AssertEq(io.Count("down q"), 0, "no fisher back route when the cauldron follows")
    AssertTrue(io.Balanced(), "no key left down")
    d := m.wh.Desc("craft")
    AssertTrue(InStr(d, "cauldron") && InStr(d, "Heavenly Potion"), "cauldron outcome reported")
    AssertTrue(!InStr(d, "crafted"), "never claims the potion was crafted")
    AssertEq(m.wh.Count("errors"), 0, "no errors")
}

Test_Craft_CauldronGuiNotOpenEscAndRetry() {
    ; Stella's dialog twice (her name is read), then the cauldron opens
    m := CrMake(Map("cauldron", true, "stella", true
        , "ocr", Map("600,100,200,40", ["", "", "Stella's Workshop"], "1200,100,100,30", "Stello")))
    m.t.Run(SchedCtx())
    io := m.io
    iRoute := io.Idx("down a")
    AssertEq(io.Count("down f", iRoute), 3, "F pressed three times")
    AssertEq(io.Count("down Esc", iRoute), 3, "Esc after each failed attempt where Stella's dialog showed (+1 = the respawn after the cauldron)")
    AssertEq(io.Count("down s", iRoute), 2, "stepped back twice")
    AssertTrue(io.Idx("move 700,100", iRoute) > 0, "carried on once the Workshop opened")
    AssertEq(m.wh.Count("errors"), 0, "no error when a retry succeeds")
    ; never opens: gives up after exactly 3 tries, no cauldron clicks
    m2 := CrMake(Map("cauldron", true, "stella", true, "ocr", Map("600,100,200,40", "", "1200,100,100,30", "Stello")))
    m2.t.Run(SchedCtx())
    io2 := m2.io
    iRoute2 := io2.Idx("down a")
    AssertEq(io2.Count("down f", iRoute2), 3, "gives up after 3 tries")
    AssertEq(io2.Count("down Esc", iRoute2), 4, "dialog closed after each try (+1 = the respawn)")
    AssertEq(io2.Count("move 700,100"), 0, "search never clicked")
    AssertEq(io2.Count("type Heavenly Potion"), 0, "nothing typed")
    AssertEq(m2.wh.Count("errors"), 1, "errors webhook")
    AssertTrue(io2.Idx("down Enter", iRoute2) > 0, "still respawns")
    AssertTrue(io2.Balanced(), "no key left down")
}

Test_Craft_StellaNotRecognisedNeverPressesEsc() {
    ; stella_dialog calibrated but her name not read: no Esc
    m := CrMake(Map("cauldron", true, "stella", true, "ocr", Map("600,100,200,40", "", "1200,100,100,30", "")))
    m.t.Run(SchedCtx())
    iRoute := m.io.Idx("down a")
    AssertEq(m.io.Count("down f", iRoute), 3, "F tried three times")
    AssertEq(m.io.Count("down Esc", iRoute), 1, "no Esc while trying (1 = only the respawn)")
    AssertEq(m.io.Count("down s", iRoute), 2, "stepped back")
    AssertEq(m.wh.Count("errors"), 1, "errors webhook")
    ; stella_dialog not calibrated: never Esc while trying
    m2 := CrMake(Map("cauldron", true, "ocr", Map("600,100,200,40", "")))
    m2.t.Run(SchedCtx())
    iRoute2 := m2.io.Idx("down a")
    AssertEq(m2.io.Count("down Esc", iRoute2), 1, "not calibrated: no Esc (1 = the respawn)")
    AssertTrue(m2.io.Idx("down Esc", iRoute2) > m2.io.Idx("down s", m2.io.Idx("down s", iRoute2) + 1), "that Esc comes after the last try")
    AssertEq(m2.io.Count("move 700,100"), 0, "search never clicked")
    AssertTrue(m2.io.Idx("down Enter", iRoute2) > 0, "still respawns")
}

Test_Craft_CauldronWrongRecipeAddsNothing() {
    ; the first result is a different recipe: nothing is opened or added
    m := CrMake(Map("cauldron", true, "gets", Map("Craft.craftTarget", "Fortune Potion I")
        , "ocr", Map("800,100,300,80", "Fortune Potion II`nThose who take this Potion will be Blessed.")))
    m.t.Run(SchedCtx())
    io := m.io
    AssertTrue(io.Idx("type Fortune Potion I") > 0, "searched")
    AssertEq(io.Count("move 950,140"), 0, "result not clicked")
    AssertEq(io.Count("move 900,100") + io.Count("move 1000,100"), 0, "no Open Recipe, no Add All")
    AssertTrue(io.Idx("move 1100,100") > 0, "cauldron closed")
    AssertEq(m.wh.Count("errors"), 1, "reported")
    AssertTrue(io.Idx("down Enter", io.Idx("move 1100,100")) > 0, "respawns afterwards")
    ; the right one: clicked in the middle of the card
    m2 := CrMake(Map("cauldron", true, "gets", Map("Craft.craftTarget", "Fortune Potion I")
        , "ocr", Map("800,100,300,80", "Fortune Potion I`nThose who take this Potion will be Blessed.")))
    m2.t.Run(SchedCtx())
    AssertTrue(m2.io.Idx("move 950,140") > 0 && m2.io.Idx("move 1000,100") > m2.io.Idx("move 950,140"), "result, then Add All")
    for pair in [["Fortune Potion I`nx", "Fortune Potion I", true], ["FORTUNE  POTION I", "fortune potion i", true]
            , ["Fortune Potion II", "Fortune Potion I", false], ["Fortune Potion I", "Fortune Potion II", false]
            , ["", "Fortune Potion I", false], ["Haste Potion I", "Fortune Potion I", false]
            , ["Worp Potion", "Warp Potion", true], ["Forbidden Potion lI", "Forbidden Potion II", true]
            , ["Forbidden Potion I", "Forbidden Potion II", false], ["Godly Potion", "Godly Potion", true]]
        AssertEq(CraftTask.IsRecipe(pair[1], pair[2]), pair[3], "IsRecipe '" pair[1] "' vs '" pair[2] "'")
}

CrGodlyOcr() => Map("800,100,300,80", "Godly Potion`nGives you 4 hours of [Lord of the Sky]"
    , "800,190,300,80", "Godly Potion`nGives you 4 hours of [Lord of the Seo]"
    , "800,280,300,80", "Godly Potion`nGives you 4 hours of [Lord of HeII]")

Test_Craft_GodlyPicksTheCardOfItsLord() {
    ; the three Godly Potions share a title: the description picks the card
    for t in [["Godly Potion (Zeus)", "move 950,140"], ["Godly Potion (Poseidon)", "move 950,230"], ["Godly Potion (Hades)", "move 950,320"]] {
        m := CrMake(Map("cauldron", true, "result2", true, "gets", Map("Craft.craftTarget", t[1]), "ocr", CrGodlyOcr()))
        m.t.Run(SchedCtx())
        AssertTrue(m.io.Idx("type Godly Potion") > 0, t[1] ": plain name typed")
        AssertEq(m.io.Count("type " t[1]), 0, t[1] ": the label is never typed")
        iCard := m.io.Idx(t[2])
        AssertTrue(iCard > 0, t[1] ": its card clicked (" t[2] ")")
        AssertTrue(m.io.Idx("move 1000,100") > iCard, t[1] ": then Add All")
        AssertEq(m.wh.Count("errors"), 0, t[1] ": no error")
    }
}

Test_Craft_GodlyWithoutSecondCardOnlyReadsTheFirst() {
    ; without cauldron_result_2 only the first card can be read: Zeus works,
    ; Hades (third card) is reported and nothing is added
    m := CrMake(Map("cauldron", true, "gets", Map("Craft.craftTarget", "Godly Potion (Zeus)"), "ocr", CrGodlyOcr()))
    m.t.Run(SchedCtx())
    AssertTrue(m.io.Idx("move 950,140") > 0, "Zeus: first card clicked")
    m2 := CrMake(Map("cauldron", true, "gets", Map("Craft.craftTarget", "Godly Potion (Hades)"), "ocr", CrGodlyOcr()))
    m2.t.Run(SchedCtx())
    AssertEq(m2.io.Count("move 950,140") + m2.io.Count("move 950,320"), 0, "Hades: no card clicked")
    AssertEq(m2.io.Count("move 1000,100"), 0, "Hades: no Add All")
    AssertEq(m2.wh.Count("errors"), 1, "Hades: reported")
}

Test_GameLists_ShopAndRecipes() {
    AssertEq(GameLists.Shop.Length, 15, "15 shop items")
    AssertEq(GameLists.Shop[1], "Lucky Potion", "shop starts with Lucky Potion")
    AssertEq(GameLists.Recipes[GameLists.Recipes.Length], "Void Heart", "Void Heart is a recipe")
    AssertEq(GameLists.SearchName("Godly Potion (Hades)"), "Godly Potion", "label dropped")
    AssertEq(GameLists.DescHint("Godly Potion (Poseidon)"), "Lord of the Sea", "Poseidon = sea")
    AssertEq(GameLists.DescHint("Godly Potion (zeus)"), "Lord of the Sky", "Zeus = sky")
    AssertEq(GameLists.DescHint("Fortune Potion II"), "", "no hint")
    AssertTrue(InStr(GameLists.Fold("[Lord of HeII]"), GameLists.Fold("Lord of Hell")), "font look-alikes folded")
    for g in ["Godly Potion (Zeus)", "Godly Potion (Poseidon)", "Godly Potion (Hades)"] {
        found := false
        for r in GameLists.Recipes
            found := found || (r = g)
        AssertTrue(found, g " is a recipe")
    }
    AssertEq(GameLists.SearchName("Fortune Potion II"), "Fortune Potion II", "plain name unchanged")
    AssertEq(GameLists.ShopName("  wind   ESSENCE "), "Wind essence", "shop spelling")
    AssertEq(GameLists.ShopName("Fortune Potion I"), "", "not sold")
    seen := Map()
    for n in GameLists.Shop {
        AssertTrue(!seen.Has(StrLower(n)), "unique " n)
        seen[StrLower(n)] := 1
    }
}

Test_Craft_EmptyOrMissingCauldronRouteSkipsWithoutF() {
    ; an empty cauldron route (as a user may leave it)
    m := CrMake(Map("gets", Map("Craft.cauldron", 1, "Craft.craftTarget", "Heavenly Potion"), "cauldronRoute", []))
    AssertEq(m.t.Run(SchedCtx()), 2, "buying unaffected")
    AssertEq(m.io.Count("down f"), 0, "no F press")
    AssertEq(m.io.Count("move 600,100") + m.io.Count("move 700,100"), 0, "no cauldron clicks")
    AssertTrue(m.wh.Count("errors") >= 1, "errors webhook for the empty route")
    AssertTrue(m.io.Idx("down q") > 0, "fisher back route used instead")
    n := m.wh.Count("errors")
    m.t.Run(SchedCtx())
    AssertEq(m.wh.Count("errors"), n, "reported once only")
    ; empty cauldron route only
    m2 := CrMake(Map("cauldron", true, "cauldronRoute", []))
    m2.t.Run(SchedCtx())
    AssertEq(m2.io.Count("down f"), 0, "empty cauldron route: no F")
    AssertEq(m2.wh.Count("errors"), 1, "one error")
    ; missing route key
    m3 := CrMake(Map("cauldron", true, "cauldronRoute", "DEL"))
    m3.t.Run(SchedCtx())
    AssertEq(m3.io.Count("down f"), 0, "missing cauldron route: no F")
    AssertEq(m3.wh.Count("errors"), 1, "one error")
    ; no craft target configured
    m5 := CrMake(Map("cauldron", true, "gets", Map("Craft.craftTarget", "")))
    m5.t.Run(SchedCtx())
    AssertEq(m5.io.Count("down f"), 0, "no target: no F")
    AssertEq(m5.wh.Count("errors"), 1, "one error")
    ; missing cauldron calibration
    m6 := CrMake(Map("cauldron", true, "drop", ["cauldron_add_all"]))
    m6.t.Run(SchedCtx())
    AssertEq(m6.io.Count("down f"), 0, "missing calibration: no F")
    AssertEq(m6.wh.Count("errors"), 1, "one error")
}

Test_Craft_CauldronOnlyWhenBuyingImpossible() {
    ; nothing to buy but the cauldron is fully set up: still goes to Stella
    m := CrMake(Map("cauldron", true, "drop", ["fisher_confirm"]))
    m.t.Run(SchedCtx())
    AssertEq(m.io.Count("move 100,100"), 0, "no fisher clicks")
    AssertEq(m.io.Count("down w"), 0, "fisher not visited")
    AssertEq(m.io.Count("down f"), 1, "cauldron still done")
}

; ---- stop ------------------------------------------------------------------------------

Test_Craft_StopMidFlowReleasesKeysAndAborts() {
    n := 1
    while (n <= 260) {
        m := CrMake(Map("cauldron", true))
        ctx := CrStopCtx(n, m.io)
        m.t.Run(ctx)
        if !m.io.Balanced()
            throw Error("keys left down when stopped after " n " checks")
        if (ctx.stopAt >= 0) {
            i := ctx.stopAt + 1
            while (i <= m.io.log.Length) {
                e := m.io.log[i]
                if (SubStr(e, 1, 4) = "move" || e = "click" || SubStr(e, 1, 4) = "type" || e = "down f")
                    throw Error("'" e "' after stop at check " n)
                i++
            }
            AssertEq(m.t.CanRun(SchedState()), true, "aborted run is retried (stop at " n ")")
        }
        n += 13
    }
    ; stopped before anything: F never pressed
    m := CrMake(Map("cauldron", true))
    c := SchedCtx()
    c.Stop()
    m.t.Run(c)
    AssertEq(m.io.log.Length, 0, "pre-stopped run does nothing")
}

; ---- no blind clicks (live 2026-11-02: a click on an empty spot went
; through a panel into the world and opened Roblox's "Buy Robux" prompt) ----

CrLogs(m) {
    logs := []
    m.t._env._logFn := (s) => logs.Push(s)
    return logs
}

CrSaid(logs, text) {
    for l in logs
        if InStr(l, text)
            return true
    return false
}

; Clicks at a point (its move followed by a click; the move over a tile
; before the wheel is not one).
CrClicksAt(io, move) {
    n := 0
    for i, e in io.log
        n += (e = move && i < io.log.Length && io.log[i + 1] = "click") ? 1 : 0
    return n
}

CrPromptReported(wh) {
    for s in wh.sent
        if (s.event = "errors" && InStr(s.title, "Purchase prompt"))
            return true
    return false
}

Test_Craft_DialogClicksOnlyWithHisDialogUp() {
    ; E did not open his dialog: the dialog clicks (1308,1073) are never made
    m := CrMake(Map("ocr", Map("1150,65,300,70", "", "960,915,940,265", "")))
    logs := CrLogs(m)
    AssertEq(m.t.Run(SchedCtx()), 0, "nothing bought")
    AssertEq(m.io.Count("move 1308,1073"), 0, "no dialog click without his dialog")
    AssertEq(m.io.Count("move 1300,100"), 0, "no Open Shop click")
    AssertTrue(CrSaid(logs, "dialog not seen"), "logged why")
    AssertEq(m.wh.Count("errors"), 1, "reported")
    ; his dialog is up but Open Shop shows late: the dialog clicks happen
    m2 := CrMake(Map("ocr", Map("1150,65,300,70", ["", "", "Open Shop"])))
    AssertEq(m2.t.Run(SchedCtx()), 2, "bought")
    AssertTrue(m2.io.Idx("move 1308,1073") > 0, "dialog clicked")
    ; the halfway skip click only while his dialog is still up
    m3 := CrMake(Map("ocr", Map("1150,65,300,70", ["", "", "", ""])))
    m3.ocr.dyn["960,915,940,265"] := () => (m3.io.Idx("down e") && m3.io.Count("click", m3.io.Idx("down e")) < 2) ? "Captain Flarg`nClick to skip" : ""
    m3.t.Run(SchedCtx())
    AssertEq(m3.io.Count("move 1308,1073"), 1, "dialog clicks once, no skip click once the dialog is gone")
}

Test_Craft_BuyTabOnlyWithTheShopOpen() {
    ; Open Shop clicked but the shop never opens: no Buy tab, no tile click
    m := CrMake(Map("ocr", Map("570,325,380,70", "")))
    logs := CrLogs(m)
    AssertEq(m.t.BuyHere(SchedCtx()), 0, "nothing bought")
    AssertTrue(m.io.Idx("move 1300,100") > 0, "Open Shop clicked")
    AssertEq(m.io.Count("move 1241,397"), 0, "Buy tab never clicked blind")
    AssertEq(m.io.Count("move 100,100") + m.io.Count("move 200,100"), 0, "no tile clicked")
    AssertTrue(CrSaid(logs, "Fishing Shop did not open"), "logged why")
    AssertEq(m.t.BuyDue(), true, "the buy stays due")
    ; a purchase prompt after the Buy tab: closed with Esc, no tile clicked
    m2 := CrMake(Map("promptAfter", "move 1241,397"))
    m2.t.BuyHere(SchedCtx())
    AssertTrue(m2.io.Idx("down Esc", m2.io.Idx("move 1241,397")) > 0, "closed with Esc")
    AssertEq(m2.io.Count("move 100,100") + m2.io.Count("move 200,100"), 0, "no tile clicked after the prompt")
    AssertTrue(CrPromptReported(m2.wh), "reported")
}

Test_Craft_TileOnlyWhileTheShopIsOpen() {
    ; the shop went away after the first purchase: the next tile is never clicked
    m := CrMake()
    io := m.io
    m.ocr.dyn["570,325,380,70"] := () => (io.Idx("move 400,100") || !io.Idx("move 1300,100")) ? "" : "Fishing Shop"
    logs := CrLogs(m)
    m.t.Run(SchedCtx())
    AssertTrue(io.Idx("move 100,100") > 0, "first tile clicked")
    AssertEq(CrClicksAt(io, "move 200,100"), 0, "second tile never clicked without the shop")
    AssertTrue(CrSaid(logs, "Fishing Shop is not open"), "logged why")
    ; a purchase prompt after a tile click: closed, Buy never pressed
    m2 := CrMake(Map("pots", ["Lucky Potion"], "promptAfter", "move 100,100"))
    m2.t.Run(SchedCtx())
    AssertTrue(m2.io.Idx("down Esc", m2.io.Idx("move 100,100")) > 0, "closed with Esc")
    AssertEq(m2.io.Count("move 1400,100"), 0, "Buy never pressed after the prompt")
    AssertTrue(CrPromptReported(m2.wh), "reported")
}

Test_Craft_CauldronClicksOnlyWithTheWorkshopOpen() {
    ; the workshop is gone after the card click: Open Recipe, Add All and the
    ; close click are never made
    m := CrMake(Map("cauldron", true))
    io := m.io
    m.ocr.map.Delete("600,100,200,40")
    m.ocr.dyn["600,100,200,40"] := () => io.Idx("move 950,140") ? "" : "Stella's Workshop"
    logs := CrLogs(m)
    m.t.Run(SchedCtx())
    AssertTrue(io.Idx("move 950,140") > 0, "card clicked")
    AssertEq(io.Count("move 900,100") + io.Count("move 1000,100") + io.Count("move 1100,100"), 0, "nothing clicked after the workshop went")
    AssertTrue(CrSaid(logs, "Workshop is not open"), "logged why")
    ; wrong recipe and the workshop gone: no close click
    m2 := CrMake(Map("cauldron", true, "gets", Map("Craft.craftTarget", "Fortune Potion I")
        , "ocr", Map("800,100,300,80", "Fortune Potion II`nThose who take this Potion will be Blessed.")))
    io2 := m2.io
    m2.ocr.map.Delete("600,100,200,40")
    m2.ocr.dyn["600,100,200,40"] := () => io2.Idx("type Fortune Potion I") ? "" : "Stella's Workshop"
    m2.t.Run(SchedCtx())
    AssertEq(io2.Count("move 1100,100"), 0, "close never clicked without the workshop")
    ; a purchase prompt after Open Recipe: closed, Add All never clicked
    m3 := CrMake(Map("cauldron", true, "promptAfter", "move 900,100"))
    m3.t.Run(SchedCtx())
    AssertTrue(m3.io.Idx("down Esc", m3.io.Idx("move 900,100")) > 0, "closed with Esc")
    AssertEq(m3.io.Count("move 1000,100"), 0, "Add All never clicked after the prompt")
    AssertTrue(CrPromptReported(m3.wh), "reported")
}
