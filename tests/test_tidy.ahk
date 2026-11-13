#Requires AutoHotkey v2.0
; ---------------------------------------------------------------------------
; Task transitions: the between-tasks tidy (Tidy, App._Tidy), the
; "task: <name> start / end" lines, and the tasks that returned on a
; preempt with something still open (2026-11-09: the Biome Randomizer
; preempted fishing mid reel and the "Fishing Failed" card sat over the
; screen through the aura swap and the whole HEAVEN hunt).
; Fakes from test_app / test_questmatch / test_fishing / test_reel /
; test_biomeitems / test_craft / test_obby; the shared screens and the sell
; shop are also read on REAL frames (tests\screens).
; ---------------------------------------------------------------------------

; A leftover on a fake screen: up reads `label` until a close takes it away
; (closes = false: it stays). next: what shows under it once closed.
class TdLeft {
    __New(label, closes := true, next := "") {
        this.label := label
        this.closes := closes
        this.next := next
        this.ups := 0
        this.closed := 0
        this.ctxs := []
    }
    Item() => {up: () => (this.ups++, this.label), close: (l, ctx) => this._Close(ctx)}
    _Close(ctx) {
        this.closed++
        this.ctxs.Push(ctx)
        if !this.closes
            return 2
        this.label := this.next
        this.next := ""
        return 1
    }
}

; An App task with leftovers on screen after its run.
class TdTask extends AppFakeTask {
    left := ""
    Leftovers() => IsObject(this.left) ? [this.left.Item()] : []
}

; The shared screens' fake: records TidyItem(full).
class TdScreen {
    __New(left := "") {
        this.fulls := []
        this.left := left
    }
    TidyItem(full := true) {
        this.fulls.Push(full)
        return IsObject(this.left) ? this.left.Item() : {up: () => "", close: (l, c) => 0}
    }
}

; A ctx that is preempted (halt: stopped) once `entry` is in io.log.
class TdPreemptAt extends SchedCtx {
    __New(io, entry, halt := false) {
        super.__New()
        this.io := io
        this.entry := entry
        this.halt := halt
        this.at := 0
    }
    _Check() {
        if (!this.at && this.io.Index(this.entry)) {
            this.at := this.io.log.Length
            if this.halt
                this.Stop()
            else
                this.RequestPreempt()
        }
    }
    ShouldStop() {
        this._Check()
        return super.ShouldStop()
    }
    IsHalted() {
        this._Check()
        return super.IsHalted()
    }
}

TdIdxFrom(io, entry, from) {
    for i, e in io.log
        if (i > from && e = entry)
            return i
    return 0
}

TdLogIdx(logs, text) {
    for i, l in logs
        if (l == text)
            return i
    return 0
}

TdLogCount(logs, prefix) {
    n := 0
    for l in logs
        n += (SubStr(l, 1, StrLen(prefix)) == prefix) ? 1 : 0
    return n
}

; ---- Tidy --------------------------------------------------------------------

Test_Tidy_CleanScreenDoesNothing() {
    a := TdLeft(""), b := TdLeft("")
    logs := []
    r := Tidy.Run("fishing", [a.Item(), b.Item()], SchedCtx(), (m) => logs.Push(m))
    AssertEq(r.Length, 0, "nothing closed")
    AssertEq(a.ups + b.ups, 2, "one read per detector")
    AssertEq(a.closed + b.closed, 0, "no close (no click, no Esc)")
    AssertEq(logs.Length, 0, "no log line")
}

Test_Tidy_ClosesEachLeftoverAndLogsIt() {
    a := TdLeft("Fishing Failed card"), b := TdLeft(""), c := TdLeft("Inventory")
    logs := []
    r := Tidy.Run("fishing", [a.Item(), b.Item(), c.Item()], SchedCtx(), (m) => logs.Push(m))
    AssertEq(r.Length, 2, "two closed")
    AssertEq(logs.Length, 2, "one line per item")
    AssertEq(logs[1], "tidy after fishing: closed the Fishing Failed card", "exact wording")
    AssertEq(logs[2], "tidy after fishing: closed the Inventory", "second item")
    AssertEq(a.closed, 1, "closed once")
    AssertEq(b.closed, 0, "the clean one untouched")
    ; one screen hid another: both closed, in order
    s := TdLeft("Inventory", true, "Quest Board page")
    logs2 := []
    Tidy.Run("minions", [s.Item()], SchedCtx(), (m) => logs2.Push(m))
    AssertEq(s.closed, 2, "both closed")
    AssertEq(logs2[2], "tidy after minions: closed the Quest Board page", "the one under it")
}

Test_Tidy_StillOpenIsLoggedOnce() {
    a := TdLeft("Jock dialog", false)
    logs := []
    r := Tidy.Run("minions", [a.Item()], SchedCtx(), (m) => logs.Push(m))
    AssertEq(r.Length, 0, "not closed")
    AssertEq(a.closed, 1, "one try (its close has its own tries)")
    AssertEq(logs.Length, 1, "one line")
    AssertEq(logs[1], "tidy after minions: the Jock dialog is still open", "exact wording")
}

Test_Tidy_HaltSkipsItPreemptDoesNot() {
    for how in ["pause", "stop", "halt"] {
        a := TdLeft("Fishing Failed card")
        ctx := SchedCtx()
        if (how = "pause")
            ctx.Pause()
        else if (how = "stop")
            ctx.Stop()
        else
            ctx.RequestPreempt(true)        ; Roblox gone (recovery)
        logs := []
        Tidy.Run("fishing", [a.Item()], ctx, (m) => logs.Push(m))
        AssertEq(a.ups, 0, how ": nothing read")
        AssertEq(a.closed, 0, how ": nothing sent")
        AssertEq(logs.Length, 0, how ": no line")
    }
    a := TdLeft("Fishing Failed card")
    ctx := SchedCtx()
    ctx.RequestPreempt()
    Tidy.Run("fishing", [a.Item()], ctx, "")
    AssertEq(a.closed, 1, "a plain preempt still closes it")
    AssertEq(a.ctxs[1].ShouldStop(), false, "on a CleanupCtx")
}

; ---- App: task boundaries and the tidy step ------------------------------------

Test_App_TaskBoundaryLines() {
    cases := Map("", (self, ctx) => 0
        , "preempted", (self, ctx) => ctx.RequestPreempt()
        , "paused", (self, ctx) => ctx.Pause()
        , "stopped", (self, ctx) => ctx.Stop()
        , "error", (self, ctx) => AppTestThrow("boom"))
    for how, fn in cases {
        fish := TdTask("fishing", 99, true, fn)
        t := AppTestMake(Map("tasks", Map("fishing", fish)))
        t.app.Start()
        t.app._RunTask(fish)
        iStart := TdLogIdx(t.ui.logs, "task: fishing start")
        iE := TdLogIdx(t.ui.logs, "task: fishing end" (how = "" ? "" : " (" how ")"))
        AssertTrue(iStart > 0, how ": start line")
        AssertTrue(iE > iStart, how ": end line after it")
        AssertEq(TdLogCount(t.ui.logs, "task: fishing end"), 1, how ": one end line")
    }
}

Test_App_TidyClosesWhatTheTaskLeft() {
    left := TdLeft("Fishing Failed card")
    fish := TdTask("fishing", 99, true, (self, ctx) => ctx.RequestPreempt())
    fish.left := left
    t := AppTestMake(Map("tasks", Map("fishing", fish)))
    t.app.Start()
    t.app._RunTask(fish)
    AssertEq(left.closed, 1, "closed after the preempted run")
    iE := TdLogIdx(t.ui.logs, "task: fishing end (preempted)")
    iT := TdLogIdx(t.ui.logs, "tidy after fishing: closed the Fishing Failed card")
    AssertTrue(iE > 0 && iT > iE, "one tidy line, after the end line")
    AssertEq(t.app.TaskRunning(), false, "the next task can start")
    ; clean screen next time: no line, no close
    n := t.ui.logs.Length
    fish.runFn := ""
    t.app._RunTask(fish)
    AssertEq(left.closed, 1, "nothing closed")
    AssertEq(TdLogCount(t.ui.logs, "tidy after"), 1, "no new tidy line")
    AssertEq(t.ui.logs.Length, n + 2, "only the start / end lines")
}

; live 2026-11-10 02:29: fishing was preempted with the line out, the card
; showed once the obby walked off and stayed through obby, hunt and sell
Test_App_TidyClosesTheFishingCardAfterAnyTask() {
    left := TdLeft("")
    fish := TdTask("fishing", 99)
    fish.left := left
    obby := TdTask("obby", 5, true, (self, ctx) => (left.label := "Fishing Failed card"))
    t := AppTestMake(Map("tasks", Map("fishing", fish, "obby", obby)))
    t.app.Start()
    t.app._RunTask(obby)
    AssertEq(left.closed, 1, "closed after the obby")
    AssertTrue(TdLogIdx(t.ui.logs, "tidy after obby: closed the Fishing Failed card") > 0, "logged")
}

Test_App_TidySkippedWhenHaltedOrRobloxNotInFront() {
    cases := Map("paused", (self, ctx) => ctx.Pause(), "stopped", (self, ctx) => ctx.Stop()
        , "halt", (self, ctx) => ctx.RequestPreempt(true), "unfocused", (self, ctx) => (t.rb.activeOk := false))
    for how, fn in cases {
        left := TdLeft("Inventory")
        q := TdTask("quests", 5, true, fn)
        q.left := left
        t := AppTestMake(Map("tasks", Map("quests", q)))
        t.app.Start()
        t.app._RunTask(q)
        AssertEq(left.ups, 0, how ": nothing read")
        AssertEq(left.closed, 0, how ": nothing sent")
        AssertEq(TdLogCount(t.ui.logs, "tidy after"), 0, how ": no tidy line")
    }
}

Test_App_TidySharedScreensOnlyPurchaseAfterFishing() {
    scr := TdScreen(TdLeft("purchase prompt"))
    fish := TdTask("fishing", 99)
    q := TdTask("quests", 5)
    t := AppTestMake(Map("tasks", Map("fishing", fish, "quests", q), "tidyScreen", scr))
    t.app.Start()
    t.app._RunTask(fish)
    t.app._RunTask(q)
    AssertEq(scr.fulls.Length, 2, "after every task")
    AssertEq(scr.fulls[1], false, "fishing: the purchase prompt only")
    AssertEq(scr.fulls[2], true, "quests: every shared screen")
    AssertTrue(TdLogIdx(t.ui.logs, "tidy after fishing: closed the purchase prompt") > 0, "logged")
}

; ---- the shared screens on REAL frames ------------------------------------------

; read on the frame until the first click, the plain world after it
Test_Tidy_RealFramesSharedScreensClosed() {
    world := A_ScriptDir "\screens\world_day.jpg"
    for f, want in Map("inventory_open_sand", "Inventory", "inventory_open_rainy", "Inventory"
        , "inventory_open_day", "Inventory", "ugc_shop_windy", "UGC Shop") {
        o := QmObbyTask("Glock")
        path := A_ScriptDir "\screens\" f ".jpg"
        o.t._env.ocrFn := (x, y, w, h, scale := 1) => Ocr.ReadFile(o.io.Clicks() ? world : path, x, y, w, h, scale)
        logs := []
        r := Tidy.Run("biomeitems", [o.t.TidyItem()], SchedCtx(), (m) => logs.Push(m))
        AssertEq(r.Length, 1, f ": closed")
        AssertEq(logs.Length, 1, f ": one line")
        AssertEq(logs[1], "tidy after biomeitems: closed the " want, f ": wording")
        AssertEq(o.io.Clicks(), 1, f ": one click")
        AssertEq(QmObbyLastMove(o.io), "move " ObbyTask.InvX[1] "," ObbyTask.InvX[2], f ": on its X")
        AssertEq(QmObbyFirst(o.io, "down Esc"), 0, f ": no Esc")
    }
    ; Jock's dialog (crop x 680.., y 890..): his Leave
    o := QmObbyTask("Glock")
    path := A_ScriptDir "\screens\jock_dialog_rainy_x680_y890.png"
    o.t._env.ocrFn := (x, y, w, h, scale := 1) => o.io.Clicks() ? Ocr.ReadFile(world, x, y, w, h, scale)
        : (x >= 680 && y >= 890 && x + w <= 1880 && y + h <= 1350) ? Ocr.ReadFile(path, x - 680, y - 890, w, h, scale) : ""
    logs := []
    Tidy.Run("minions", [o.t.TidyItem()], SchedCtx(), (m) => logs.Push(m))
    AssertEq(logs.Length, 1, "jock: one line")
    AssertEq(logs[1], "tidy after minions: closed the Jock dialog", "jock: wording")
    AssertEq(QmObbyLastMove(o.io), "move " ObbyTask.JockLeave[1] "," ObbyTask.JockLeave[2], "jock: on Leave")
    ; the Quest Board page (crop x 1160.., y 480..): its Exit, never Esc
    o := QmObbyTask("Glock")
    path := A_ScriptDir "\screens\quest_page_a.jpg"
    o.t._env.ocrFn := (x, y, w, h, scale := 1) => o.io.Clicks() ? Ocr.ReadFile(world, x, y, w, h, scale)
        : (x >= 1160 && y >= 480 && x + w <= 2460 && y + h <= 1290) ? Ocr.ReadFile(path, x - 1160, y - 480, w, h, scale) : ""
    logs := []
    Tidy.Run("quests", [o.t.TidyItem()], SchedCtx(), (m) => logs.Push(m))
    AssertEq(logs.Length, 1, "quest: one line")
    AssertEq(logs[1], "tidy after quests: closed the Quest Board page", "quest: wording")
    AssertEq(QmObbyLastMove(o.io), "move " ObbyTask.QuestExit[1] "," ObbyTask.QuestExit[2], "quest: on Exit")
    AssertEq(QmObbyFirst(o.io, "down Esc"), 0, "quest: no Esc")
}

; a clean screen: one read per detector, nothing sent, no line
Test_Tidy_RealFrameCleanScreenSendsNothing() {
    for f in ["world_day", "inventory_day"] {
        o := QmObbyTask("Glock")
        path := A_ScriptDir "\screens\" f ".jpg"
        o.t._env.ocrFn := (x, y, w, h, scale := 1) => Ocr.ReadFile(path, x, y, w, h, scale)
        logs := []
        r := Tidy.Run("quests", [o.t.TidyItem()], SchedCtx(), (m) => logs.Push(m))
        AssertEq(r.Length, 0, f ": nothing closed")
        AssertEq(o.io.log.Length, 0, f ": no click, no key, no move")
        AssertEq(logs.Length, 0, f ": no line")
    }
    ; after fishing only the purchase prompt is looked for: an inventory
    ; frame is left alone (fishing opens none)
    o := QmObbyTask("Glock")
    path := A_ScriptDir "\screens\inventory_open_day.jpg"
    o.t._env.ocrFn := (x, y, w, h, scale := 1) => Ocr.ReadFile(path, x, y, w, h, scale)
    AssertEq(Tidy.Run("fishing", [o.t.TidyItem(false)], SchedCtx(), "").Length, 0, "fishing: purchase prompt only")
    AssertEq(o.io.log.Length, 0, "fishing: nothing sent")
}

; ---- fishing / sell leftovers ---------------------------------------------------

Test_Tidy_FishingCardClosedByItsX() {
    t := FsMakeCfg()
    try {
        io := RlResultIO("Fishing Foiled`nThe fish is g0ne")
        io.cast := true
        task := FishingTask(t.cfg, SchedState(), FsDeps(io))
        logs := []
        r := Tidy.Run("fishing", task.Leftovers(), SchedCtx(), (m) => logs.Push(m))
        AssertEq(r.Length, 1, "closed")
        AssertEq(logs[1], "tidy after fishing: closed the Fishing Failed card", "wording")
        AssertEq(io.Count("click@1457,491"), 1, "its X once")
        ; no card: nothing clicked
        io2 := RlResultIO("")
        io2.cast := true
        task2 := FishingTask(t.cfg, SchedState(), FsDeps(io2))
        AssertEq(Tidy.Run("fishing", task2.Leftovers(), SchedCtx(), "").Length, 0, "clean")
        AssertEq(io2.log.Length, 0, "no click")
        AssertEq(FishingTask.CardLabel("caught"), "Fish Caught card", "the other card")
    } finally {
        FsClean(t.dir)
    }
}

; FsIO reading a real frame until the first click, then the plain world.
class TdFrameIO extends FsIO {
    __New(path) {
        super.__New()
        this.path := path
    }
    Ocr(x, y, w, h, scale := 1) {
        clicked := false
        for e in this.log
            clicked := clicked || (SubStr(e, 1, 6) = "click@")
        return Ocr.ReadFile(clicked ? A_ScriptDir "\screens\world_day.jpg" : this.path, x, y, w, h, scale)
    }
}

; REAL frames: the Sell Confirm popup left open is cancelled (never Sell),
; the Fishing Shop is seen, the plain world is not
Test_Tidy_RealFramesSellLeftovers() {
    t := FsMakeCfg()
    try {
        io := TdFrameIO(A_ScriptDir "\screens\sellconfirm_hell.jpg")
        task := SellTask(t.cfg, SchedState(), FsDeps(io))
        logs := []
        r := Tidy.Run("sell", task.Leftovers(), SchedCtx(), (m) => logs.Push(m))
        AssertEq(logs.Length, 1, "one line")
        AssertEq(logs[1], "tidy after sell: closed the Sell Confirm popup", "wording")
        cn := SellTask.ShopChecks.cancel
        AssertEq(io.Count("click@" cn[1] "," cn[2]), 1, "its Cancel once")
        cf := t.cfg.Data("coords")["sell"]["loop"]["confirm"]
        AssertEq(io.Count("click@" cf[1] "," cf[2]), 0, "never Sell")
        shop := SellTask(t.cfg, SchedState(), FsDeps(TdFrameIO(A_ScriptDir "\screens\fishshop_hell_sell.jpg"))).Leftovers()
        AssertEq(shop[2].up.Call(), "Fishing Shop", "the shop is seen")
        AssertEq(shop[1].up.Call(), "", "no popup on the shop frame")
        world := TdFrameIO(A_ScriptDir "\screens\world_day.jpg")
        AssertEq(Tidy.Run("sell", SellTask(t.cfg, SchedState(), FsDeps(world)).Leftovers(), SchedCtx(), "").Length, 0, "world: nothing")
        AssertEq(world.log.Length, 0, "world: nothing sent")
    } finally {
        FsClean(t.dir)
    }
}

; ---- source fixes: a preempt closes what the task opened --------------------------

; preempted while buying: her dialog was left on screen (the finally only
; left it when not told to stop); now Leave is clicked, no respawn
Test_Merchant_PreemptLeavesHerDialog() {
    L := MerchantTask.Layout
    wants := Map("Mari", [Map("name", "Lucky Potion", "qty", 1), Map("name", "Speed Potion", "qty", 1)], "Jester", [])
    io := QmIO()
    shop := QmShop(io, ["Lucky Potion", "Speed Potion", "Mixed Potion", "Fortune Spoid I", "Gear B"])
    t := QmMerchTask(wants, shop, io, QmWh())
    t.Notify("Mari")
    ctx := TdPreemptAt(io, "move " L.buy.x "," L.buy.y)
    t.Run(ctx)
    AssertTrue(ctx.at > 0, "the preempt came")
    AssertTrue(TdIdxFrom(io, "move " L.leave.x "," L.leave.y, ctx.at) > 0, "Leave clicked after the preempt")
    AssertEq(TdIdxFrom(io, "down Esc", ctx.at), 0, "no respawn on a preempt")
    ; preempted while waiting for her buttons: Leave too
    io2 := QmIO()
    shop2 := QmShop(io2, ["Lucky Potion", "", "", "", ""])
    t2 := QmMerchTask(wants, shop2, io2, QmWh())
    t2.Notify("Mari")
    ctx2 := TdPreemptAt(io2, "move " L.skip.x "," L.skip.y)
    t2.Run(ctx2)
    AssertTrue(TdIdxFrom(io2, "move " L.leave.x "," L.leave.y, ctx2.at) > 0, "Leave clicked")
    AssertEq(TdIdxFrom(io2, "move " L.open.x "," L.open.y, ctx2.at), 0, "Open never clicked after it")
    ; a halt (F3): nothing more at all, not even the shop's X
    io3 := QmIO()
    shop3 := QmShop(io3, ["Lucky Potion", "Speed Potion", "Mixed Potion", "Fortune Spoid I", "Gear B"])
    t3 := QmMerchTask(wants, shop3, io3, QmWh())
    t3.Notify("Mari")
    ctx3 := TdPreemptAt(io3, "move " L.buy.x "," L.buy.y, true)
    t3.Run(ctx3)
    AssertTrue(ctx3.at > 0, "halted")
    AssertEq(TdIdxFrom(io3, "move " L.leave.x "," L.leave.y, ctx3.at), 0, "halt: no Leave")
    AssertEq(TdIdxFrom(io3, "move " L.close.x "," L.close.y, ctx3.at), 0, "halt: no X")
}

; preempted with the inventory open (teleporter search): closed first
Test_Merchant_PreemptClosesTheInventory() {
    wants := Map("Mari", [Map("name", "Lucky Potion", "qty", 1)], "Jester", [])
    io := QmIO()
    shop := QmShop(io, ["Lucky Potion", "", "", "", ""])
    t := QmMerchTask(wants, shop, io, QmWh())
    t.Notify("Mari")
    ctx := TdPreemptAt(io, "type T")
    t.Run(ctx)
    AssertTrue(ctx.at > 0, "the preempt came")
    AssertEq(io.InvOpen(), false, "the inventory is closed")
    AssertEq(io.Index("move 130,130"), 0, "Use never clicked")
    io2 := QmIO()
    t2 := QmMerchTask(wants, QmShop(io2, ["Lucky Potion", "", "", "", ""]), io2, QmWh())
    t2.Notify("Mari")
    t2.Run(TdPreemptAt(io2, "type T", true))
    AssertEq(io2.InvOpen(), true, "halt: left as it is (nothing sent)")
}

; every wait returned -1 with the inventory open
Test_BiomeItems_PreemptClosesTheInventory() {
    m := BiMake(Map("BiomeItems.strangeController", 1), ["Strange Controller"], ["Use to change the biome. Usable once every 20 minutes."])
    ctx := TdPreemptAt(m.io, "type S")
    AssertEq(m.t.Run(ctx), 0, "not used")
    AssertEq(m.ocr.open, false, "the inventory is closed")
    AssertEq(m.io.Moved(40, 40), false, "Use never clicked")
    m2 := BiMake(Map("BiomeItems.strangeController", 1), ["Strange Controller"], ["Use to change the biome. Usable once every 20 minutes."])
    m2.t.Run(TdPreemptAt(m2.io, "type S", true))
    AssertEq(m2.ocr.open, true, "halt: nothing sent")
    ; Tidy: the Selector list left up is closed with Esc, only while it reads
    m3 := BiMake(Map(), ["Biome Selector"], ["x"])
    m3.ocr.selector := true
    logs := []
    Tidy.Run("biomeitems", m3.t.Leftovers(), SchedCtx(), (s) => logs.Push(s))
    AssertEq(m3.ocr.selector, false, "closed")
    AssertEq(logs[1], "tidy after biomeitems: closed the Biome Selector list", "wording")
    m4 := BiMake(Map(), ["Biome Selector"], ["x"])
    Tidy.Run("biomeitems", m4.t.Leftovers(), SchedCtx(), "")
    AssertEq(m4.io.log.Length, 0, "not up: no Esc")
}

; preempted in Stella's Workshop: cauldron_close first, no respawn
Test_Craft_PreemptInTheCauldronClosesIt() {
    m := CrMake(Map("cauldron", true))
    io := m.io
    ctx := CrPreemptCtx(io, "type Heavenly Potion")
    m.t.Run(ctx)
    AssertTrue(ctx.at > 0, "the preempt came")
    AssertTrue(io.Idx("move 1100,100", ctx.at) > 0, "cauldron_close clicked")
    AssertEq(io.Idx("down Esc", ctx.at), 0, "no respawn")
    AssertEq(io.Idx("move 950,140", ctx.at), 0, "the recipe never clicked")
    m2 := CrMake(Map("cauldron", true))
    ctx2 := CrPreemptCtx(m2.io, "type Heavenly Potion", true)
    m2.t.Run(ctx2)
    AssertEq(m2.io.Idx("move 1100,100", ctx2.at), 0, "halt: nothing sent")
    ; Tidy: the Workshop left open is closed by cauldron_close
    m3 := CrMake(Map("cauldron", true))
    io3 := m3.io
    m3.ocr.map.Delete("600,100,200,40")
    m3.ocr.dyn["600,100,200,40"] := () => io3.Idx("move 1100,100") ? "" : "Stella's Workshop"
    logs := []
    Tidy.Run("craft", m3.t.Leftovers(), SchedCtx(), (s) => logs.Push(s))
    AssertEq(logs.Length, 1, "one line")
    AssertEq(logs[1], "tidy after craft: closed the cauldron panel", "wording")
    AssertEq(io3.Count("move 1100,100"), 1, "cauldron_close clicked once")
    ; closed: nothing more
    AssertEq(Tidy.Run("craft", m3.t.Leftovers(), SchedCtx(), "").Length, 0, "clean")
}

; ---- the title screen (live 2026-11-09: shown after every join) ------------------

TdTitle() => A_ScriptDir "\screens\title_play_windy.jpg"

; REAL frame: both words read at scale 2; every other frame (in game,
; menus, crops): never the title screen, so Play is never clicked in play
Test_Title_RealFrameReadsNeverInGame() {
    p := TdTitle()
    AssertTrue(FileExist(p), "frame exists")
    AssertTrue(Input.TitleUp("", (x, y, w, h, scale := 1) => Ocr.ReadFile(p, x, y, w, h, scale)), "the title screen is seen")
    n := 0
    Loop Files A_ScriptDir "\screens\*.*" {
        if InStr(A_LoopFileName, "title_")
            continue
        f := A_LoopFileFullPath
        AssertTrue(!Input.TitleUp("", (x, y, w, h, scale := 1) => Ocr.ReadFile(f, x, y, w, h, scale)), A_LoopFileName ": not the title screen")
        n++
    }
    AssertTrue(n > 100, "checked on every other frame")
}

; Play clicked once (its centre), read on the frame until the click, the
; game after it; in game or halted: nothing sent
Test_Title_ClickPlayOnRealFrame() {
    io := QmIO()
    p := TdTitle(), world := A_ScriptDir "\screens\world_day.jpg"
    rd := (x, y, w, h, scale := 1) => Ocr.ReadFile(io.Clicks() ? world : p, x, y, w, h, scale)
    AssertEq(Input.ClickPlay(SchedCtx(), io, rd), 1, "gone after Play")
    AssertEq(io.Clicks(), 1, "one click")
    AssertTrue(io.Index("move " Input.TitlePlay[1] "," Input.TitlePlay[2]) > 0, "on Play")
    AssertEq(io.Index("down Esc"), 0, "no Esc")
    io2 := QmIO()
    AssertEq(Input.ClickPlay(SchedCtx(), io2, (x, y, w, h, scale := 1) => Ocr.ReadFile(world, x, y, w, h, scale)), 0, "in game: not up")
    AssertEq(io2.log.Length, 0, "in game: nothing sent")
    io3 := QmIO()
    c := SchedCtx()
    c.Pause()
    AssertEq(Input.ClickPlay(c, io3, (x, y, w, h, scale := 1) => Ocr.ReadFile(p, x, y, w, h, scale)), -1, "halted")
    AssertEq(io3.Clicks(), 0, "halted: no click")
}

; the between-tasks tidy (after fishing too) leaves the title screen by Play
Test_Title_TidyClicksPlay() {
    for full in [true, false] {
        o := QmObbyTask("Glock")
        p := TdTitle(), world := A_ScriptDir "\screens\world_day.jpg"
        o.t._env.ocrFn := (x, y, w, h, scale := 1) => Ocr.ReadFile(o.io.Clicks() ? world : p, x, y, w, h, scale)
        logs := []
        Tidy.Run("recovery", [o.t.TidyItem(full)], SchedCtx(), (m) => logs.Push(m))
        AssertEq(logs.Length, 1, full ": one line")
        AssertEq(logs[1], "tidy after recovery: closed the title screen", full ": wording")
        AssertEq(QmObbyLastMove(o.io), "move " Input.TitlePlay[1] "," Input.TitlePlay[2], full ": on Play")
    }
}

class TdTitleScreen extends TdScreen {
    TitleItem() => this.left.Item()
}

; before a launch: the App leaves the title screen first
Test_App_TitleGateBeforeLaunch() {
    scr := TdTitleScreen(TdLeft("title screen"))
    t := AppTestMake(Map("tasks", Map("fishing", TdTask("fishing", 99)), "tidyScreen", scr))
    t.app.Start()
    t.app._TitleGate()
    AssertEq(scr.left.closed, 1, "Play clicked")
    AssertTrue(TdLogIdx(t.ui.logs, "title screen: clicked Play") > 0, "logged")
    n := t.ui.logs.Length
    t.app._TitleGate()
    AssertEq(scr.left.closed, 1, "clean: nothing")
    AssertEq(t.ui.logs.Length, n, "clean: no line")
    ; through a tick: the gate, then the launch
    scr2 := TdTitleScreen(TdLeft("title screen"))
    t2 := AppTestMake(Map("tasks", Map("fishing", TdTask("fishing", 99)), "tidyScreen", scr2))
    t2.app.Start()
    t2.app.Tick()
    AssertEq(scr2.left.closed, 1, "tick: Play clicked")
    AssertEq(t2.launched.Length, 1, "then launched")
}

; recovery: the title screen after the rejoin is left by Play, then the reset
Test_Recovery_Rejoin_TitleScreenClicksPlay() {
    rig := RcRig()
    rig.win := false
    p := TdTitle(), world := A_ScriptDir "\screens\world_day.jpg"
    rig.task._env.ocrFn := (x, y, w, h, scale := 1) => Ocr.ReadFile(rig.io.Count("c") ? world : p, x, y, w, h, scale)
    AssertEq(rig.task.Run(rig.Ctx()), 1, "rejoined")
    AssertTrue(InStr(rig.AllText(), "recovery: title screen: clicked Play"), "logged")
    iC := 0, iE := 0
    for i, e in rig.io.ev {
        if (e = "c" && !iC)
            iC := i
        if (e = "d:Esc" && !iE)
            iE := i
    }
    AssertTrue(iC > 0 && iE > iC, "Play before the reset")
    n := 0
    for i, e in rig.io.ev
        n += (i < iE && e = "c") ? 1 : 0
    AssertEq(n, 1, "one click before the reset")
}

; ---- first person (live 2026-11-10 04:09) ---------------------------------
; The sell's zoom was preempted between the wheel up (all the way in) and the
; wheel down: first person pins the cursor like shift lock, Shift could not
; free it and every task was skipped every 7 s for 10 minutes.

class TdFirstPersonIO extends MnLockIO {
    fp := true
    MousePos() => (this.fp || (this.lock && !this.free)) ? {x: 1280, y: 720} : this.pos
    Wheel(dir, n := 1, gapMs := 25) {
        this.log.Push("wheel " dir " " n)
        if (dir = "down")
            this.fp := false
    }
}

Test_Input_ShiftOffZoomsOutOfFirstPerson() {
    io := TdFirstPersonIO()
    AssertTrue(Input.ShiftLock(false, io), "free after the zoom out")
    AssertTrue(io.Index("wheel down " Input.FirstPersonOut) > 0, "zoomed out")
    AssertEq(io.lock, false, "shift lock itself left off")
    AssertEq(io.Clicks(), 0, "never a click")
    ; plain shift lock: no zoom
    io2 := MnLockIO()
    io2.lock := true
    AssertTrue(Input.ShiftLock(false, io2), "off by Shift")
    AssertEq(io2.Index("wheel down " Input.FirstPersonOut), 0, "no zoom when Shift worked")
    ; turning it ON never zooms
    io3 := TdFirstPersonIO()
    io3.fp := false, io3.works := false
    Input.ShiftLock(true, io3)
    AssertEq(io3.Index("wheel down " Input.FirstPersonOut), 0, "no zoom for on")
}

Test_FishLogic_ZoomFinishesOnAPreempt() {
    cam := Map("wheelUp", 30, "wheelDown", 8, "wheelGapMs", 25, "pauseMs", 100, "afterMs", 100)
    io := FsIO()
    ctx := SchedCtx()
    ctx.RequestPreempt()
    FishLogic.Zoom(io, ctx, cam)
    AssertEq(io.WheelTotal("up") " " io.WheelTotal("down"), "30 8", "preempt: in and back out")
    io2 := FsIO()
    ctx2 := SchedCtx()
    ctx2.Stop()
    AssertEq(FishLogic.Zoom(io2, ctx2, cam), false, "halt: stops")
}

Test_App_RepeatedShiftSkipsWaitLonger() {
    inp := AppFakeShift()
    inp.stuck := true
    fish := AppFakeTask("fishing", 99)
    t := AppTestMake(Map("input", inp, "tasks", Map("fishing", fish)))
    t.app.Start()
    holds := []
    Loop 8 {
        t.app._RunTask(fish)
        holds.Push(t.app._holdUntil - t.app.Now())
    }
    AssertEq(holds[1], App.ErrorHoldMs, "first skip: the usual hold")
    AssertEq(holds[2], App.ErrorHoldMs * 2, "second: twice")
    AssertEq(holds[8], App.SkipHoldMaxMs, "capped")
    inp.stuck := false
    t.app._RunTask(fish)
    inp.stuck := true
    t.app._RunTask(fish)
    AssertEq(t.app._holdUntil - t.app.Now(), App.ErrorHoldMs, "a run resets it")
}

; live 2026-11-12 after the game update: the title screen read "Ploy" and
; "Rhonaelogs", it never counted as up and the rejoin never clicked Play
Test_Title_AfterTheNovemberUpdate() {
    p := A_ScriptDir "\screens\title_play_dark.jpg"
    AssertTrue(FileExist(p), "frame exists")
    AssertTrue(Input.TitleUp("", (x, y, w, h, scale := 1) => Ocr.ReadFile(p, x, y, w, h, scale)), "the new title screen is seen")
    for s in ["Rhonaelogs", "Rhonaeloqg", "Changelogs", "Change logs", "Chonqelogs"]
        AssertTrue(RegExMatch(s, Input.TitleLogsRe), s)
    for s in ["Collections", "Logs", "Close", "Shop"]
        AssertTrue(!RegExMatch(s, Input.TitleLogsRe), "not " s)
}
