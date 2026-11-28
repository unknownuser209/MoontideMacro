#Requires AutoHotkey v2.0
; Bug hunt 2026-11-27: fishing and obby fixes (fishing-1, fishing-2, obby-1,
; obby-2). Helpers come from test_fishing.ahk (FsIO, FsDeps, FsScreen,
; FsMakeCfg), test_fishing_repath.ahk (FsHasLog), test_reel.ahk (RlCardIO,
; RlSim), test_obby.ahk (QmObbyTask, ObStore), test_questmatch.ahk
; (QmCountMoves) and test_minions.ahk (MnTask).

; ---- fishing-1: the frozen raised card off 2560x1440 -------------------------

; The frozen card over the raised panel (Fishing.ahk RaisedRect /
; RaisedClose) on a client that is not native 1440p. Its Fish button text
; centre is given in SCREEN px under the two ways the raise may scale (with
; the panel's k, or as a share of the client); the read must cover both.
; The X is closed only by a click within 4 screen px of (cx, cy).
class FoRaisedIO extends FsIO {
    __New(bx, byPanel, byShare, cx, cy) {
        super.__New()
        this.raised := true
        this.bx := bx, this.by1 := byPanel, this.by2 := byShare
        this.cx := cx, this.cy := cy
        this.clicks := []             ; screen px of every click
    }
    Ocr(x, y, w, h, scale := 1) {
        p := Screen.Pt(x, y), q := Screen.Pt(x + w, y + h)
        inside := (yy) => (this.bx >= p.x && this.bx <= q.x && yy >= p.y && yy <= q.y)
        if (this.raised && inside(this.by1) && inside(this.by2))
            return "Fis"
        return ""
    }
    ClickHere() {
        s := Screen.Pt(this.x, this.y)
        this.clicks.Push(s)
        if (Abs(s.x - this.cx) <= 4 && Abs(s.y - this.cy) <= 4)
            this.raised := false
        super.ClickHere()
    }
}

; 1920x1080 at 100 % / 125 % and 2560x1440 at 150 %: the panel's scale k
; (KNow) is 0.84 / 0.951 / 1.194. The frozen frame (fish_raised_card_day)
; is centred like the panel, so its X sits at 0.5 W + k * 243 (1164 / 1191
; / 1570; the raw 1440p coords gave 1142 / 1142 / 1523: a 7 px X missed).
Test_FishObbyFix_FrozenRaisedCardOff1440p() {
    t := FsMakeCfg()
    t.cfg.Set("General.legacyReel", 0)
    FsScreen.Install()
    FsScreen.fn := (x, y) => 0x101010
    ; [w, h, dpi, button x, button y (panel k), button y (client share), X x, X y]
    sizes := [[1920, 1080, 96, 855, 544, 575, 1164, 469]
        , [1920, 1080, 120, 841, 501, 571, 1191, 450]
        , [2560, 1440, 144, 1131, 697, 764, 1570, 613]]
    try {
        for z in sizes {
            Screen.SetClient(0, 0, z[1], z[2]), Screen.dpi := z[3]
            name := z[1] "x" z[2] "@" z[3]
            io := FoRaisedIO(z[4], z[5], z[6], z[7], z[8])
            lo := FishingTask(t.cfg, SchedState(), FsDeps(io, "", true, [])).Leftovers()
            AssertEq(lo[2].up.Call(), "frozen Fish Caught card", name ": the raised Fish button reads")
            AssertEq(lo[2].close.Call("", SchedCtx()), 1, name ": closed by its X")
            AssertTrue(io.clicks.Length >= 1 && Abs(io.clicks[1].x - z[7]) <= 4, name ": the X click's x follows the panel scale (" (io.clicks.Length ? io.clicks[1].x "," io.clicks[1].y : "no click") ")")
        }
        ; native 1440p: the coords as they are (the live-tested ones)
        Screen.Reset(), Screen.dpi := 96
        AssertEq(FsJoin(FishingTask.RaisedBox(), ","), FsJoin(FishingTask.RaisedRect, ","), "1440p: the read box unchanged")
        AssertEq(FsJoin(FishingTask.RaisedXy(), ","), FsJoin(FishingTask.RaisedClose, ","), "1440p: the X click unchanged")
    } finally {
        Screen.Reset(), Screen.dpi := 0
        FsScreen.Restore()
        FsClean(t.dir)
    }
}

; Real frames (2560x1440, the macro's own screenshots): the read box the
; task uses now still reads the frozen card's Fish button there, and no
; normal frame.
Test_FishObbyFix_RaisedBoxReadsTheRealFrames() {
    try {
        Screen.Reset(), Screen.dpi := 96
        s := FishingTask.RaisedBox()
        r := {x: s[1], y: s[2], w: s[3], h: s[4]}
        for f in ["fish_raised_card_day", "fish_raised_card_night", "fish_raised_card_rain"]
            AssertTrue(RegExMatch(ScrRead(f, r, 2), FishingTask.RaisedRe) > 0, f ": the raised panel's Fish button reads")
        for f in ["fish_status_ready_eden", "world_day", "inventory_day"]
            AssertEq(RegExMatch(ScrRead(f, r, 2), FishingTask.RaisedRe), 0, f ": no raised panel")
    } finally {
        Screen.Reset(), Screen.dpi := 0
    }
}

; ---- fishing-2: a catch card never seen is not "seen closing" ----------------

; live 2026-11-27 04:39 / 04:35: "no catch card seen in 3.0 s", the X
; clicked blind, the run returned for the chat as a clean yield, and the
; late "Fishing Failed" card sat over the next tasks (the tidy skipped it).
Test_FishObbyFix_UnseenCardIsNotACleanYield() {
    t := FsMakeCfg()
    t.cfg.Set("General.legacyReel", 0)
    FsScreen.Install()
    try {
        st := SchedState()
        st.chatDue := true
        io := RlCardIO(5000, 1)                 ; the card shows 5 s after its first read
        sim := RlSim(io)
        FsScreen.fn := (x, y) => sim.Pixel(x, y)
        logs := []
        task := FishingTask(t.cfg, st, FsDeps(io, "", true, logs))
        task.Run(SchedCtx())
        AssertTrue(FsHasLog(logs, "no catch card seen"), "the card was not seen in time")
        AssertEq(task.YieldedClean(), false, "not a clean yield: no card was seen closing")
        io.Wait(3000)
        AssertEq(io.Up(), true, "the late card is up now")
        AssertEq(task.Leftovers()[1].up.Call(), "Fish Caught card", "the tidy reads it")
        ; a card seen and closed still makes a clean yield
        st2 := SchedState()
        st2.chatDue := true
        io2 := RlCardIO(0, 1)
        sim2 := RlSim(io2)
        FsScreen.fn := (x, y) => sim2.Pixel(x, y)
        task2 := FishingTask(t.cfg, st2, FsDeps(io2, "", true, []))
        task2.Run(SchedCtx())
        AssertEq(st2.fishLoops, 1, "one catch")
        AssertEq(task2.YieldedClean(), true, "seen closing: clean")
    } finally {
        FsScreen.Restore()
        FsClean(t.dir)
    }
}

; ---- obby-1: the swap aura already worn, found by the log hint ---------------

Test_FishObbyFix_AlreadySailorFoundByTheLogHintIsKept() {
    o := QmObbyTask("Sailor")
    o.t._logHint["sailor|1"] := 1               ; Sailor's tile from an earlier log pick
    AssertEq(o.t.Run(SchedCtx()), 1, "blessing seen")
    AssertEq(QmCountMoves(o.io, "move 300,300"), 0, "Equip / Unequip never clicked")
    AssertEq(o.s.State().eq, "Sailor", "Sailor kept")
    AssertEq(o.wh.Count("errors"), 0, "no error")
}

; Sailor as a logo (no name reads): _FindTile finds nothing, the log pick
; sees it worn already. No put-back (and no false 'could not unequip').
Test_FishObbyFix_AlreadySailorAsALogoIsKept() {
    o := QmObbyTask("Sailor")
    o.s.logo := ["Sailor"]
    o.t.Run(SchedCtx())
    AssertEq(QmCountMoves(o.io, "move 300,300"), 0, "Equip / Unequip never clicked")
    AssertEq(o.s.State().eq, "Sailor", "Sailor kept")
    AssertEq(o.wh.Count("errors"), 0, "no error")
}

Test_FishObbyFix_MinionsPutBackKeepsTheCombatAuraWornBefore() {
    m := MnTask([[]], Map("Minions.putBack", 1))
    m.s.initial := "Eden", m.s.special := ["Eden"], m.s.logo := ["Eden"]
    m.t._swap._logHint["eden|2"] := 1
    m.t.Run(SchedCtx())
    AssertEq(m.s.State().eq, "Eden", "Eden still on after the hunt")
}

; ---- obby-2: a halt during the blessing check sends no more input ------------

; F3 / pause (Roblox lost focus) on the buff_expand click: no move or click
; after it (a for-loop variable is not captured by a closure: one call each)
FoHaltOnExpand(how) {
    o := QmObbyTask("Glock")
    ctx := SchedCtx()
    at := 0
    o.io.DefineProp("ClickHere", {Call: (self) => (self.log.Push("click"), (!at && self.log.Length >= 2 && self.log[self.log.Length - 1] = "move 500,500") ? (at := self.log.Length, how = "pause" ? ctx.Pause() : ctx.Stop()) : 0)})
    o.t.Run(ctx)
    AssertTrue(at > 0, how ": halted on the buff_expand click")
    sent := 0
    Loop o.io.log.Length - at
        sent += (o.io.log[at + A_Index] = "click" || SubStr(o.io.log[at + A_Index], 1, 5) = "move ") ? 1 : 0
    AssertEq(sent, 0, how ": no move or click after the halt")
    AssertEq(o.t.Owed(), "Glock", how ": Glock owed to the next run")
}

Test_FishObbyFix_HaltDuringBlessingCheckSendsNoClick() {
    FoHaltOnExpand("pause")
    FoHaltOnExpand("stop")
    ; a plain preempt still collapses the list
    o := QmObbyTask("Glock")
    ctx := SchedCtx()
    done := false
    o.io.DefineProp("ClickHere", {Call: (self) => (self.log.Push("click"), (!done && self.log.Length >= 2 && self.log[self.log.Length - 1] = "move 500,500") ? (done := true, ctx.RequestPreempt()) : 0)})
    o.t.Run(ctx)
    AssertEq(QmCountMoves(o.io, "move 500,500"), 2, "preempt: expanded, then collapsed again")
    AssertTrue(!o.s.State().expanded, "preempt: left collapsed")
}
