#Requires AutoHotkey v2.0
; Offline tests for lib\tasks\Limbo.ahk (and its Scheduler / Fishing /
; Recovery hooks). Fakes from test_questmatch.ahk (QmIO, QmCal, QmWh, QmCfg)
; and test_recovery.ahk (RcRig). Helpers are prefixed Lm.
#Include ..\lib\tasks\Limbo.ahk

; stops after `limit` ShouldStop() calls (the watch loop asks every round)
class LmCtx {
    __New(limit := 1000000) {
        this.n := 0
        this.limit := limit
    }
    ShouldStop() => (++this.n > this.limit)
}

LmCal() {
    p := Map("inv_open", {x: 100, y: 100}, "inv_items_tab", {x: 110, y: 110}
        , "inv_search", {x: 120, y: 120}, "inv_use", {x: 130, y: 130})
    r := Map("inv_tile1_rect", {x: 200, y: 200, w: 100, h: 30}, "inv_desc_rect", {x: 300, y: 300, w: 200, h: 40})
    return QmCal(p, r)
}

; Inventory on top of QmIO: inv_open (100,100) opens / closes it, except the
; first click after typing, which only takes the focus off the search box
; (TaskEnv.CloseInv); LmMake reads its tabs (around inv_items_tab) while it
; is open. onUse: called when Use (130,130) is clicked.
class LmInvIO extends QmIO {
    __New() {
        super.__New()
        this.open := false
        this.focus := false
        this.x := 0, this.y := 0
        this.onUse := ""
    }
    MoveTo(x, y) {
        super.MoveTo(x, y)
        this.x := x, this.y := y
    }
    Type(t) {
        super.Type(t)
        this.focus := true
    }
    ClickHere() {
        super.ClickHere()
        if (this.x = 100 && this.y = 100) {
            if this.focus
                this.focus := false
            else
                this.open := !this.open
            return
        }
        this.focus := false
        if (this.x = 130 && this.y = 130 && IsObject(this.onUse))
            this.onUse.Call()
    }
}

; opts: tile, desc (inventory OCR), findAfter (Eden's dialog shows after N
; find() calls; 0 = never), route (limbo_eden steps or ""), io (QmIO-like;
; an LmInvIO's inventory tabs read while it is open; default a new LmInvIO:
; the crack is used only once the inventory reads open), shot (what the
; screenshot dep returns). m.box.tile / .desc change what the inventory
; shows; m.reads lists every inventory read's scale.
LmMake(opts := "") {
    o := (opts is Map) ? opts : Map()
    get := (k, d) => o.Has(k) ? o[k] : d
    m := {io: get("io", LmInvIO()), wh: QmWh(), logs: [], finds: 0, island: 0, shots: 0, reads: []}
    m.state := SchedState()
    routes := Map()
    r := get("route", [["w", "down", 100], ["w", "up", 0]])
    if IsObject(r)
        routes["limbo_eden"] := Map("steps", r)
    box := {tile: get("tile", "Portable`nCrack"), desc: get("desc", "Opens a crack into THE LIMBO")}
    m.box := box
    io := m.io
    findAfter := get("findAfter", 0)
    shot := get("shot", "")
    m.t := LimboTask({cfg: QmCfg(Map("Limbo.enabled", get("enabled", 1)), Map("routes", routes))
        , io: m.io, webhook: m.wh, cal: LmCal(), log: (s) => m.logs.Push(s)
        , ocr: (x, y, w, h, scale := 1) => (x = 200 || x = 300) ? (m.reads.Push(scale), x = 200 ? box.tile : box.desc)
            : (x = 20 && y = 85 && HasProp(io, "open") && io.open && !(HasProp(io, "loading") && io.loading)) ? "Gears   Items" : ""
        , find: (x, y, w, h, re, scale := 1) => (++m.finds, (findAfter && m.finds >= findAfter && RegExMatch("Contract with it", re)) ? {x: 1300, y: 1258, text: "Contract with it"} : "")
        , toIsland: get("toIsland", true) ? ((ctx) => (++m.island, true)) : ""
        , shot: () => (++m.shots, shot)})
    return m
}

Test_Limbo_CanRun() {
    m := LmMake(Map("enabled", 0))
    AssertEq(m.t.CanRun(m.state), false, "off by default")
    m := LmMake()
    AssertEq(m.t.priority, Sched.Priority["limbo"], "scheduler table")
    AssertEq(m.t.CanRun(m.state), true, "on the island, no rare biome: go to Limbo")
    m.state.rareActive := true
    AssertEq(m.t.CanRun(m.state), false, "rare biome on the island: stay")
    m.state.inLimbo := true
    AssertEq(m.t.CanRun(m.state), true, "in Limbo during a rare biome: leave")
    m2 := LmMake(Map("toIsland", false))
    m2.state.inLimbo := true, m2.state.rareActive := true
    AssertEq(m2.t.CanRun(m2.state), false, "no way back: not eligible")
}

Test_Limbo_EntersWalksAndContractsWithEden() {
    m := LmMake(Map("findAfter", 3))
    m.t.CanRun(m.state)
    clicks := m.t.Run(LmCtx(300))
    io := m.io
    AssertTrue(io.Index("move 130,130") > 0, "Portable Crack used")
    typed := ""
    for e in io.log
        if (SubStr(e, 1, 5) = "type ")
            typed .= SubStr(e, 6)
    AssertEq(typed, "Portable Crack", "searched for it")
    AssertEq(m.state.inLimbo, true, "in Limbo now")
    AssertEq(io.Index("down Esc"), 0, "no respawn in Limbo (Esc + R does not work there)")
    AssertTrue(io.Index("down RButton") > io.Index("move 130,130"), "camera turned top-down after entering")
    AssertTrue(io.Index("look 0," Input.TopDownDy) > io.Index("down RButton"), "mouse moved down with the right button held")
    AssertTrue(io.Index("up RButton") > io.Index("look 0," Input.TopDownDy), "right button released")
    AssertTrue(io.Index("down w") > io.Index("up RButton"), "walked the limbo_eden route from the top-down view")
    AssertTrue(io.Index("down e") > io.Index("down w"), "then E by Eden's spot")
    AssertTrue(io.Moved(1300, 1258), "clicked Contract with it where it was read")
    AssertTrue(clicks >= 1, "contract clicks counted")
    AssertEq(m.wh.Count("rare"), 1, "one Eden report (mention) however many clicks")
    AssertEq(m.shots, 1, "with a screenshot")
}

Test_Limbo_NoContractWithoutEden() {
    m := LmMake()                                ; find() never sees the button
    m.state.inLimbo := true
    m.t.CanRun(m.state)
    m.t.Run(LmCtx(200))
    AssertEq(m.io.Index("move 130,130"), 0, "already in Limbo: no crack")
    AssertEq(m.io.Index("down w") + m.io.Index("down RButton") + m.io.Index("down Esc"), 0, "already in Limbo: no respawn, no walk")
    AssertTrue(m.io.Index("down e") > 0, "keeps pressing E")
    AssertEq(m.io.Moved(1300, 1258), false, "nothing clicked")
    AssertEq(m.wh.Count("rare"), 0, "no report")
}

Test_Limbo_LeavesForARareBiomeAndComesBack() {
    m := LmMake()
    m.state.inLimbo := true
    m.state.rareActive := true
    m.state.biome := "GLITCHED"
    AssertEq(m.t.CanRun(m.state), true, "eligible")
    AssertEq(m.t.Run(LmCtx()), 1, "left")
    AssertEq(m.island, 1, "rejoined the island")
    AssertEq(m.state.inLimbo, false, "on Sol's Island")
    AssertEq(m.io.log.Length, 0, "no keys or clicks for it")
    AssertTrue(m.wh.Count("biome") = 1, "reported")
    ; the rare biome ends: back to Limbo
    m.state.rareActive := false
    AssertEq(m.t.CanRun(m.state), true, "goes back")
    ; a rare biome that starts while waiting by Eden ends the watch
    m2 := LmMake()
    m2.state.inLimbo := true
    m2.t.CanRun(m2.state)
    st := m2.state
    m2.t._findFn := (x, y, w, h, re, scale := 1) => (st.rareActive := true, "")
    m2.t.Run(LmCtx())
    AssertEq(m2.state.inLimbo, true, "still in Limbo: the next run leaves")
}

Test_Limbo_NoCrackNoUseAndHolds() {
    m := LmMake(Map("tile", "Lucky`nPotion", "desc", "Gives you [Lucky]"))
    m.t.CanRun(m.state)
    AssertEq(m.t.Run(LmCtx()), 0, "not entered")
    AssertEq(m.io.Index("move 130,130"), 0, "Use never clicked")
    AssertEq(m.state.inLimbo, false, "still on the island")
    AssertEq(m.wh.Count("errors"), 1, "reported")
    AssertEq(m.t.CanRun(m.state), false, "no new try right away")
    ; a crack tile whose description is not the crack's
    m2 := LmMake(Map("desc", "Gives you [Heavenly] for 1 roll"))
    m2.t.CanRun(m2.state)
    m2.t.Run(LmCtx())
    AssertEq(m2.io.Index("move 130,130"), 0, "Use never clicked without the crack's description")
}

Test_Limbo_SchedulerAndFishing() {
    st := SchedState()
    AssertEq(st.inLimbo, false, "SchedState declares inLimbo")
    st.inLimbo := true
    tasks := [SchedFakeTask("potions", 1), SchedFakeTask("recovery", 2), SchedFakeTask("sell", 6), SchedFakeTask("limbo", 98), SchedFakeTask("fishing", 99)]
    AssertEq(Scheduler.Next(tasks, st, 0).name, "recovery", "in Limbo: recovery still runs")
    AssertEq(Scheduler.Next([SchedFakeTask("potions", 1), SchedFakeTask("limbo", 98), SchedFakeTask("fishing", 99)], st, 0).name, "limbo", "no potions or fishing in Limbo")
    st.inLimbo := false
    AssertEq(Scheduler.Next(tasks, st, 0).name, "potions", "on the island everything runs again")
    ; Limbo replaces fishing as the idle task
    t := FsMakeCfg()
    try {
        t.cfg.Set("Limbo.enabled", 1)
        AssertEq(FishingTask(t.cfg, SchedState()).CanRun(SchedState()), false, "no fishing with Limbo on")
        t.cfg.Set("Limbo.enabled", 0)
        AssertEq(FishingTask(t.cfg, SchedState()).CanRun(SchedState()), true, "fishing again")
    } finally {
        FsClean(t.dir)
    }
}

Test_Limbo_RecoveryReturnsToTheIsland() {
    rig := RcRig()
    rig.state.inLimbo := true
    rig.task.CanRun(rig.state)
    AssertEq(rig.task.ReturnToIsland(rig.Ctx()), true, "back")
    AssertEq(rig.closes, 1, "the running client was closed")
    AssertEq(rig.runs.Length, 1, "the private server opened")
    AssertEq(rig.state.inLimbo, false, "a fresh join is on Sol's Island")
    AssertTrue(!InStr(rig.AllText(), "SECRET123"), "link never logged")
    AssertTrue(!InStr(rig.hook.Text(), "Recovery: rejoined"), "leaving Limbo is not reported as an error")
    ; stuck detection is off while Limbo is the idle task
    rig2 := RcRig(, Map("Limbo.enabled", 1))
    rig2.task.CanRun(rig2.state)
    Loop 25 {
        rig2.clock.t += 30000
        AssertEq(rig2.task.CanRun(rig2.state), false, "not stuck with Limbo on, poll " A_Index)
    }
}

Test_Limbo_TopDownCameraSteps() {
    c := Input.CameraSteps("limbo_eden")
    AssertEq(c[1][1] "|" c[1][2], "RButton|down", "right button first")
    AssertEq(c[c.Length][1] "|" c[c.Length][2], "RButton|up", "released last")
    looks := 0, dx := 0
    for s in c
        if (s[1] = "look")
            looks++, dx += s[2]
    AssertEq(looks, Input.TopDownLooks, "mouse moved down in steps")
    AssertEq(dx, 0, "no turn left or right: the respawn's camera angle is kept")
    AssertTrue(Input.TopDownDy * Input.TopDownLooks >= 2000, "far enough to reach the pitch limit")
    AssertEq(Input.ParseRoute(c).Length, c.Length, "valid route steps")
    AssertEq(Input.CameraSteps("quest_board").Length, 0, "other routes keep the respawn camera")
    w := Input.WithCamera("limbo_eden", Map("steps", [["w", "down", 100], ["w", "up", 0]]))
    AssertEq(w.Length, c.Length + 2, "camera, then the route")
    AssertEq(w[w.Length][1], "w", "route last")
}

Test_Limbo_ModeTurnsTheIslandTasksOff() {
    st := SchedState()
    AssertEq(st.limboMode, false, "SchedState declares limboMode")
    st.limboMode := true
    for name in ["merchant", "craft", "biomeitems", "quests", "sell"]
        AssertEq(Scheduler.Next([SchedFakeTask(name, Sched.Priority[name]), SchedFakeTask("limbo", 98)], st, 0).name, "limbo", name " is off with Limbo on")
    AssertEq(Scheduler.Next([SchedFakeTask("fishing", 99)], st, 0), "", "no fishing")
    AssertEq(Scheduler.Next([SchedFakeTask("potions", 1), SchedFakeTask("limbo", 98)], st, 0).name, "potions", "rare-biome potions still run")
    AssertEq(Scheduler.Next([SchedFakeTask("recovery", 2), SchedFakeTask("limbo", 98)], st, 0).name, "recovery", "recovery still runs")
    ; App: no start sell trip, and the mode follows the switch
    sell := AppFakeTask("sell", 6)
    t := AppTestMake(Map("tasks", Map("sell", sell, "limbo", AppFakeTask("limbo", 98), "fishing", AppFakeTask("fishing", 99))
        , "cfgVals", Map("Limbo.enabled", 1, "General.sound", 0, "Medal.onRareBiome", 0)))
    t.app.Start()
    AssertEq(t.app.state.limboMode, true, "Limbo mode at start")
    AssertEq(t.app.state.startSell || t.app.state.needRepath, false, "no sell trip first")
    AssertEq(t.app._ChatWanted(), false, "no merchant chat reads")
    t.cfg.Set("Limbo.enabled", 0)
    t.app._Pick(t.app.Now(), "ok")
    AssertEq(t.app.state.limboMode, false, "switched off: island tasks again")
}

Test_Limbo_RouteTestTurnsTheCameraFirst() {
    walks := []
    t := AppTestMake(Map("walkRoute", (steps, key, ctx) => (walks.Push(steps), "")))
    t.cfg.routes := Map("limbo_eden", Map("steps", [["d", "down", 100], ["d", "up", 0]]))
    r := t.app.OnTestRoute("limbo_eden")
    AssertEq(r.ok, true, "walked")
    s := walks[1]
    AssertEq(s[1][1] "|" s[1][2], "RButton|down", "camera turned top-down first")
    AssertEq(s[s.Length][1], "d", "then the recorded steps")
}

Test_Limbo_RecordAndTestWithoutRespawn() {
    calls := []
    t := AppTestMake(Map("recordRoute", (name, path) => (calls.Push(name), {ok: false, msg: "cancelled", steps: [], routes: ""})
        , "walkRoute", (steps, key, ctx) => (calls.Push("walk"), "")))
    t.app.OnRecordRoute("limbo_eden")
    AssertEq(t.HasOwnProp("respawns") ? t.respawns : 0, 0, "no respawn before recording in Limbo")
    AssertEq(calls[1], "limbo_eden", "the recorder ran")
    t.app.OnRecordRoute("quest_board")
    AssertEq(t.respawns, 1, "the island routes still respawn first")
    AssertTrue(Input.NoRespawn.Has("limbo_eden") && !Input.NoRespawn.Has("quest_board"), "only limbo_eden")
    ; the default walk re-aims instead of respawning
    io := QmIO()
    AssertTrue(Input.ReAim("", io), "re-aim")
    AssertEq(io.Index("down Esc") + io.Index("down r") + io.Index("down Enter"), 0, "no Esc, R, Enter")
    AssertTrue(io.Clicks() = 2, "Aura Collections opened and closed")
}

Test_Limbo_StopRightAfterTheCrackStillInLimbo() {
    ; 2026-10-27 review: a preempt / pause in the 9.7 s after Use left
    ; inLimbo false while the player was in Limbo (potions ran there, the
    ; next run used ANOTHER crack) and the inventory open
    ctx := SchedCtx()
    io := LmInvIO()
    io.onUse := () => ctx.RequestPreempt()
    m := LmMake(Map("io", io))
    m.t.CanRun(m.state)
    AssertEq(m.t.Run(ctx), 0, "cut short")
    AssertTrue(io.Index("move 130,130") > 0, "the crack was used")
    AssertEq(m.state.inLimbo, true, "in Limbo: only limbo and recovery run")
    AssertEq(io.open, false, "the inventory closed although the wait was cut short")
    ; the next run: no second crack; the walk that was cut short is done now
    io.log := []
    AssertEq(m.t.CanRun(m.state), true, "limbo runs again")
    m.t.Run(LmCtx(300))
    AssertEq(io.Index("move 130,130") + io.Index("move 100,100"), 0, "no second Portable Crack, no inventory")
    AssertTrue(io.Index("down RButton") > 0 && io.Index("down w") > io.Index("down RButton"), "camera top-down, then the walk to Eden")
    AssertTrue(io.Index("down e") > io.Index("down w"), "then E by Eden's spot")
    ; a real halt (F3) right after Use: in Limbo too, but nothing more is sent
    ctx2 := SchedCtx()
    io2 := LmInvIO()
    io2.onUse := () => ctx2.Stop()
    m2 := LmMake(Map("io", io2))
    m2.t.CanRun(m2.state)
    m2.t.Run(ctx2)
    AssertEq(m2.state.inLimbo, true, "halted after Use: in Limbo")
    AssertEq(io2.log[io2.log.Length], "click", "nothing after the Use click")
    AssertEq(io2.Index("move 130,130"), io2.log.Length - 1, "the Use click was the last input")
}

Test_Limbo_FailedSearchRetypesAndClosesTheInventory() {
    ; 2026-10-27 review: no crack tile -> one click on the inventory button
    ; right after typing only left the search box: the inventory stayed open
    ; for the potions (their first click closed it); the search was never
    ; typed again after a dropped letter
    io := LmInvIO()
    m := LmMake(Map("io", io, "tile", "Lucky`nPotion", "desc", "Gives you [Lucky]"))
    m.t.CanRun(m.state)
    AssertEq(m.t.Run(LmCtx()), 0, "not entered")
    n := 0
    for e in io.log
        n += (e = "type P") ? 1 : 0
    AssertEq(n, LimboTask.SearchTries, "search typed SearchTries times")
    AssertEq(io.open, false, "the inventory closed (checked)")
    AssertEq(io.Index("move 130,130"), 0, "Use never clicked")
    AssertEq(m.wh.Count("errors"), 1, "reported once")
    ; a dropped letter: the search typed again finds the crack
    io2 := LmInvIO()
    m2 := LmMake(Map("io", io2, "tile", "Lucky`nPotion"))
    starts := [0]
    io2.DefineProp("Type", {call: (self, t) => (LmInvIO.Prototype.Type.Call(self, t), (t = "P" && ++starts[1] >= 2) ? (m2.box.tile := "Portable`nCrack") : 0)})
    m2.t.CanRun(m2.state)
    m2.t.Run(LmCtx(300))
    AssertEq(starts[1], 2, "typed twice")
    AssertTrue(io2.Index("move 130,130") > 0, "the crack used after typing the search again")
    AssertEq(m2.state.inLimbo, true, "in Limbo")
    AssertEq(io2.open, false, "the inventory closed after Use")
    AssertEq(m2.wh.Count("errors"), 0, "no error")
}

Test_Limbo_SwitchedOffInLimboGoesBack() {
    ; 2026-10-27 review: unticking Limbo in Limbo kept E pressed there
    ; forever, or (after a stop and start) left every task blocked by inLimbo
    m := LmMake(Map("enabled", 0))
    m.state.inLimbo := true
    AssertEq(m.t.CanRun(m.state), true, "off while in Limbo: the way back is due")
    AssertEq(m.t.Run(LmCtx()), 1, "went back")
    AssertEq(m.island, 1, "rejoined the island")
    AssertEq(m.state.inLimbo, false, "on Sol's Island: the island tasks run again")
    AssertEq(m.t.CanRun(m.state), false, "off on the island: idle")
    AssertEq(m.io.Index("move 130,130"), 0, "no crack")
    AssertTrue(Scheduler.Eligible(m.t, SchedState()) = false, "not picked once back")
    ; switched off while waiting by Eden: the watch ends
    m2 := LmMake()
    m2.state.inLimbo := true
    m2.t.CanRun(m2.state)
    cfg := m2.t._env.cfg
    m2.t._findFn := (x, y, w, h, re, scale := 1) => (cfg.g["Limbo.enabled"] := 0, "")
    ctx := LmCtx(5000)
    m2.t.Run(ctx)
    AssertTrue(ctx.n < 30, "the watch ended when Limbo was switched off (" ctx.n " checks)")
    AssertEq(m2.t.CanRun(m2.state), true, "then the way back runs")
    ; no way back (or it failed): never blocked for good
    m3 := LmMake(Map("enabled", 0, "toIsland", false))
    m3.state.inLimbo := true
    AssertEq(m3.t.CanRun(m3.state), true, "eligible")
    AssertEq(m3.t.Run(LmCtx()), 0, "could not go back")
    AssertEq(m3.state.inLimbo, false, "inLimbo cleared: the other tasks are not blocked forever")
    AssertEq(m3.wh.Count("errors"), 1, "the user is told to rejoin")
}

; ---- the Portable Crack in the game font (live 2026-11-20) -----------------
; A user (1920x1080) and a live run (2560x1440) never used the crack: the
; tile reads "Portoble / Crock" (the game font's a reads as o) and its
; description "It always guides you to the end of the living world." has
; none of crack / limbo / void. Real frames: tests\screens\inv_crack_*
; (<what>_<height>_x<ox>_y<oy>.png = a crop whose top left is screen ox,
; oy; the 1080 ones are the 1440 ones scaled x0.75, Lanczos).

LmLogHas(m, re) {
    for s in m.logs
        if RegExMatch(s, re)
            return true
    return false
}

LmLogText(m) {
    s := ""
    for l in m.logs
        s .= " | " l
    return s
}

Test_Limbo_CrackTileMatchRules() {
    for s in ["Portoble`nCrock", "Portable`nCrack", "Pnrtnble`nCrock", "Portoble Crocl<", "Portable`nCr0ck"
        , "PORTABLE CRACK", "Portoble`nCrock`nx1", "Portable Grock"]
        AssertTrue(LimboTask.IsCrackTile(s), "crack tile: " StrReplace(s, "`n", " / "))
    ; never another item, "portable" alone included (the Portable Device)
    for s in ["", "Portable`nDevice", "Portoble`nDevice", "Strange`nController", "Biome`nRandomizer", "Lucky`nPotion"
        , "Fortune`nPotion", "Heavenly`nPotion", "Oblivion`nPotion", "Void Coin", "Rock", "Clock", "Empty.", "x1"]
        AssertTrue(!LimboTask.IsCrackTile(s), "not the crack: " StrReplace(s, "`n", " / "))
    AssertEq(RegExMatch("Portoble`nCrock", "i)crack"), 0, "the old rule never matched the game font")
}

Test_Limbo_CrackDescMatchRules() {
    for s in ["It always guides you to the end of the living world.", "It always guides you to the end of the living H)rld."
        , "It guides you to the end the living", "tt guides you to the end the living", "Opens a crack into THE LIMBO"]
        AssertTrue(LimboTask.IsCrackDesc(s), "crack description: " s)
    for s in ["", "Empty.", "Ern*y.", "Gives you [Lucky]", "Gives you [Heavenly] for 1 roll", "Changes the biome"
        , "Place it to raise the luck of everyone nearby"]
        AssertTrue(!LimboTask.IsCrackDesc(s), "not the crack's: " s)
    AssertEq(RegExMatch("It always guides you to the end of the living world.", "i)crack|limbo|void"), 0, "the old rule missed the real text")
}

; The task's own reads (LimboTask._ReadIs: ReadScales in turn) with the real
; OCR on the frames, through the user's calibration (2560x1440 design px:
; inv_tile1_rect 1076,578 110x112, inv_desc_rect 648,812 367x243), at
; 2560x1440 and at 1920x1080 (Screen maps the rects as in the game).
Test_Limbo_RealFramesFindAndProveTheCrack() {
    tileR := {x: 1076, y: 578, w: 110, h: 112}, descR := {x: 648, y: 812, w: 367, h: 243}
    for res in ["1440_x620_y360", "1080_x465_y270"] {
        RegExMatch(res, "^(\d+)_x(\d+)_y(\d+)$", &m)
        hi := (m[1] = "1440")
        try {
            Screen.SetClient(-Integer(m[2]), -Integer(m[3]), hi ? 2560 : 1920, hi ? 1440 : 1080)
            dir := A_ScriptDir "\screens\inv_crack_"
            reads := Map()
            for f in ["searched", "selected"] {
                p := dir f "_" res ".png"
                AssertTrue(FileExist(p), "frame " f " " res)
                t := LimboTask({io: QmIO(), ocr: (x, y, w, h, scale := 1) => Ocr.ReadFile(p, x, y, w, h, scale)})
                tile := "", desc := ""
                AssertTrue(t._ReadIs(tileR, "tile", &tile), res " " f ": the first tile is the crack (read '" LimboTask._Short(tile) "')")
                okD := t._ReadIs(descR, "desc", &desc)
                if (f = "selected")
                    AssertTrue(okD, res ": the selected crack's description (read '" LimboTask._Short(desc) "')")
                else
                    AssertTrue(!okD, res ": nothing selected yet, no description (read '" LimboTask._Short(desc) "')")
                reads[f] := {tile: tile, desc: desc}
            }
            ; RED before the fix: the old rules on the same first reads
            sel := dir "selected_" res ".png"
            d1 := Ocr.ReadFile(sel, descR.x, descR.y, descR.w, descR.h, 1)
            AssertEq(RegExMatch(d1, "i)crack|limbo|void"), 0, res ": the old description rule fails on '" LimboTask._Short(d1) "'")
            if hi {
                t1 := Ocr.ReadFile(sel, tileR.x, tileR.y, tileR.w, tileR.h, 1)
                AssertEq(RegExMatch(t1, "i)crack"), 0, res ": the old tile rule fails on '" LimboTask._Short(t1) "'")
            }
        } finally
            Screen.Reset()
    }
}

; ---- diagnostics (2026-11-20: a report could not say what was read) --------

Test_Limbo_InventoryNotOpenIsSaid() {
    m := LmMake(Map("io", QmIO()))          ; its tabs never read: the inventory did not open
    m.t.CanRun(m.state)
    AssertEq(m.t.Run(LmCtx()), 0, "not entered")
    AssertEq(m.io.Index("type P"), 0, "nothing typed into the world")
    AssertTrue(LmLogHas(m, "the inventory did not open \(check the inv_open point\)"), "said: " LmLogText(m))
    AssertEq(m.wh.Count("errors"), 1, "reported")
    AssertEq(m.io.Index("move 130,130"), 0, "Use never clicked")
}

Test_Limbo_NoTileSaysWhatItReadWithAScreenshot() {
    m := LmMake(Map("tile", "Lucky`nPotion", "desc", "Gives you [Lucky]", "shot", "C:\Users\someone\AppData\Local\Temp\vesper_shot_1.png"))
    m.t.CanRun(m.state)
    AssertEq(m.t.Run(LmCtx()), 0, "not entered")
    AssertEq(m.shots, 1, "one screenshot")
    AssertTrue(LmLogHas(m, "the first tile read 'Lucky / Potion'"), "what the tile read is logged: " LmLogText(m))
    AssertTrue(LmLogHas(m, "screen when no Portable Crack tile read saved to "), "the screenshot's path logged")
    e := ""
    for s in m.wh.sent
        if (s.event = "errors")
            e := s
    AssertTrue(IsObject(e) && IsObject(e.opts) && e.opts.screenshot != "", "the errors webhook has the screenshot")
    AssertTrue(InStr(e.desc, "Lucky / Potion") && !InStr(e.desc, "C:\"), "and the read, no path")
    AssertEq(m.reads[1] "," m.reads[2], "1,2", "each search read at scale 1, then 2")
}

; ---- 2026-11-20 review ------------------------------------------------------

Test_Limbo_ScreenshotOncePerDistinctRead() {
    m := LmMake(Map("tile", "Lucky`nPotion", "desc", "Gives you [Lucky]", "shot", "C:\Users\someone\AppData\Local\Temp\vesper_shot_1.png"))
    m.t.CanRun(m.state)
    m.t.Run(LmCtx())
    m.t._holdUntil := 0
    m.t.CanRun(m.state)
    m.t.Run(LmCtx())
    AssertEq(m.shots, 1, "the same read twice: one screenshot")
    AssertEq(m.wh.Count("errors"), 2, "the text post every try")
    m.box.tile := "Biome`nRandomizer"
    m.t._holdUntil := 0
    m.t.CanRun(m.state)
    m.t.Run(LmCtx())
    AssertEq(m.shots, 2, "another read: a screenshot again")
}

Test_Limbo_LogsTheScale1Read() {
    t := LimboTask({io: QmIO(), ocr: (x, y, w, h, scale := 1) => (scale = 1) ? "Portoble`nDevice" : "Pnrtnble`nDevice"})
    read := "", more := ""
    AssertEq(t._ReadIs({x: 1, y: 1, w: 9, h: 9}, "tile", &read, &more), false, "not the crack")
    AssertEq(read, "Portoble`nDevice", "read = the scale 1 text")
    AssertEq(more, "Pnrtnble`nDevice", "more = the scale 2 text that differs")
    m := LmMake(Map("tile", "Lucky`nPotion", "desc", "Gives you [Lucky]"))
    m.t.CanRun(m.state)
    m.t.Run(LmCtx())
    AssertTrue(LmLogHas(m, "the first tile read 'Lucky / Potion'; do you own"), "same text at both scales: logged once: " LmLogText(m))
}

Test_Limbo_InventoryAlreadyOpen() {
    ; already open: no click on its button (that closed it, then "did not open")
    io := LmInvIO()
    io.open := true
    m := LmMake(Map("io", io))
    m.t.CanRun(m.state)
    m.t.Run(LmCtx(300))
    first := io.Index("move 100,100"), use := io.Index("move 130,130")
    AssertTrue(use > 0, "the crack used")
    AssertTrue(first = 0 || first > use, "no inventory button click before Use")
    AssertEq(m.wh.Count("errors"), 0, "no error")
}

Test_Limbo_DescVoidIsAWord() {
    AssertTrue(!LimboTask.IsCrackDesc("Helps you avoid danger"), "'avoid' is not void")
    AssertTrue(LimboTask.IsCrackDesc("A tear into the void"), "void still counts")
}

; Live 2026-11-20 16:14: the crack worked, but the inventory was still open
; in THE LIMBO 20 s later: the check right after Use ran during the loading
; screen, where its tabs do not read. Fake: after Use the tabs read nothing
; until the EnterMs wait (the teleport) is over.
LmLoadingIO(neverCloses := false) {
    io := LmInvIO()
    io.loading := false
    io.onUse := () => io.loading := true
    io.DefineProp("Wait", {call: (self, ms, ctx := "") => ((ms >= LimboTask.EnterMs ? self.loading := false : 0)
        , QmIO.Prototype.Wait.Call(self, ms, ctx))})
    if neverCloses
        io.DefineProp("ClickHere", {call: (self) => (LmInvIO.Prototype.ClickHere.Call(self)
            , (self.x = 100 && self.y = 100 && self.loading = false && self.HasOwnProp("used")) ? self.open := true : 0
            , (self.x = 130 && self.y = 130) ? self.used := true : 0)})
    return io
}

Test_Limbo_InventoryClosedAfterTheTeleport() {
    io := LmLoadingIO()
    m := LmMake(Map("io", io))
    m.t.CanRun(m.state)
    m.t.Run(LmCtx(300))
    AssertTrue(io.Index("move 130,130") > 0, "the crack used")
    AssertEq(io.open, false, "closed once its tabs read in THE LIMBO")
    AssertTrue(LmLogHas(m, "the inventory was still open after the teleport: closing it"), "logged: " LmLogText(m))
    ; closed before the walk: the last inventory-button click comes before W
    last := 0
    for i, e in io.log
        if (e = "move 100,100")
            last := i
    AssertTrue(last > io.Index("move 130,130") && last < io.Index("down w"), "closed after Use, before the walk")
    AssertEq(m.wh.Count("errors"), 0, "no error")
    ; one that will not close: logged and reported, the walk goes on
    io2 := LmLoadingIO(true)
    m2 := LmMake(Map("io", io2))
    m2.t.CanRun(m2.state)
    m2.t.Run(LmCtx(300))
    AssertEq(io2.open, true, "still open")
    AssertTrue(LmLogHas(m2, "the inventory is still open in THE LIMBO \(close it yourself\)"), "logged: " LmLogText(m2))
    found := false
    for s in m2.wh.sent
        found := found || (s.event = "errors" && s.title = "Inventory left open")
    AssertTrue(found, "reported")
    AssertTrue(io2.Index("down w") > 0, "the walk went on")
}
