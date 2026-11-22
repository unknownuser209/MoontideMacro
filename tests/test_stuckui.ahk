#Requires AutoHotkey v2.0
; Tests for the stuck game UI work (package B, 2026-11-20): lib\UiStuck.ahk,
; the App's rejoin for it, and the fix card kept off the game and closed
; when its problem is gone (lib\ui\FixCard.ahk, lib\FixIt.ahk). Uses the App
; rig from test_app.ahk. No window is shown: the cards here are fakes or
; built hidden.
#Include ..\lib\UiStuck.ahk

; a fix card stand-in: records where it was put
class StuckFakeCard {
    __New(key) {
        this.rule := FixIt.Rule(key)
        this.shows := []
        this.hides := 0
        this.gone := false
    }
    ShowAt(x, y) => this.shows.Push(x "," y)
    Hide() => this.hides++
    Destroy() => this.gone := true
}

StuckLogHas(t, text) {
    for l in t.ui.logs
        if InStr(l, text)
            return true
    return false
}

Test_UiStuck_CountsPerKind() {
    UiStuck.Reset()
    try {
        UiStuck.Fail("aura storage")
        UiStuck.Fail("aura search")
        UiStuck.Fail("aura search")
        AssertEq(UiStuck.Due(), false, "3 of " UiStuck.TripAt)
        UiStuck.Ok("aura storage")                 ; the storage opened: its own count only
        AssertEq(UiStuck.Total(), 2, "the search misses stay")
        UiStuck.Fail("aura search"), UiStuck.Fail("inventory")
        AssertEq(UiStuck.Due(), true, "due at " UiStuck.TripAt)
        AssertTrue(InStr(UiStuck.Text(), "aura search 3") && InStr(UiStuck.Text(), "inventory 1"), "named: " UiStuck.Text())
        UiStuck.Reset()
        UiStuck.Fail("memory match board", UiStuck.TripAt)
        AssertEq(UiStuck.Due(), true, "a board left open trips at once")
    } finally {
        UiStuck.Reset()
    }
}

; live 2026-11-20 00:12-06:39: every Aura Storage / inventory use failed and
; nothing rejoined. TripAt failures -> the recovery task is asked to rejoin,
; once per UiRejoinGapMs.
Test_App_StuckUiAsksForARejoin() {
    UiStuck.Reset()
    rec := AppFakeUnlockRecovery()
    obby := AppFakeTask("obby", 7, true, (self, ctx) => (UiStuck.Fail("aura storage"), UiStuck.Fail("aura storage")))
    t := AppTestMake(Map("tasks", Map("obby", obby, "recovery", rec)))
    try {
        t.app.Start()
        t.app._RunTask(obby)
        AssertEq(rec.asks, 0, "2 failures: not yet")
        t.app._RunTask(obby)
        AssertEq(rec.asks, 1, "4 failures: rejoin asked")
        AssertTrue(StuckLogHas(t, "the game's windows look stuck (4 in a row: aura storage 4): rejoining"), "logged")
        AssertEq(UiStuck.Total(), 0, "count cleared")
        rec.pending := false                        ; the rejoin ran
        t.app._RunTask(obby), t.app._RunTask(obby)
        AssertEq(rec.asks, 1, "not again within " App.UiRejoinGapMs // 60000 " min")
        t.clk.t += App.UiRejoinGapMs
        t.app._RunTask(obby)
        AssertEq(rec.asks, 2, "again after the gap")
        ; Start forgets the count
        UiStuck.Fail("inventory", 3)
        t.app.Stop()
        t.app.Start()
        AssertEq(UiStuck.Total(), 0, "Start clears it")
    } finally {
        UiStuck.Reset()
    }
}

Test_App_StuckUiWithoutAutoRejoinSaysSoOnce() {
    UiStuck.Reset()
    rec := AppFakeUnlockRecovery()
    obby := AppFakeTask("obby", 7, true, (self, ctx) => UiStuck.Fail("aura search", UiStuck.TripAt))
    t := AppTestMake(Map("tasks", Map("obby", obby, "recovery", rec), "cfgVals", Map("recovery.enabled", 0, "General.sound", 0)))
    try {
        t.app.Start()
        t.app._RunTask(obby), t.app._RunTask(obby)
        AssertEq(rec.asks, 0, "auto-rejoin off: no rejoin")
        n := 0
        for l in t.ui.logs
            n += InStr(l, "auto-rejoin is off") ? 1 : 0
        AssertEq(n, 1, "said once")
    } finally {
        UiStuck.Reset()
    }
}

; live 2026-11-20: the card sat over the game's bottom right for 3 hours
Test_FixCard_SpotKeepsOffTheGame() {
    mon := [{l: 0, t: 0, r: 2560, b: 1400}]
    pref := FixCard.Pos(2560, 1400)
    w := Theme.Dpi(FixCard.W), h := Theme.Dpi(FixCard.H)
    AssertEq(FixCard.Spot(w, h, "", mon, pref).x, pref.x, "no game: the usual corner")
    full := {x: 0, y: 0, w: 2560, h: 1440}
    AssertEq(FixCard.Spot(w, h, full, mon, pref), "", "fullscreen on one monitor: no room (hidden while running)")
    two := [{l: 0, t: 0, r: 2560, b: 1400}, {l: 2560, t: 0, r: 4480, b: 1040}]
    p := FixCard.Spot(w, h, full, two, pref)
    AssertTrue(IsObject(p) && p.x >= 2560 && p.x + w <= 4480 && p.y + h <= 1040, "the other monitor's corner")
    win := {x: 100, y: 100, w: 1280, h: 720}
    p := FixCard.Spot(w, h, win, mon, pref)
    AssertTrue(IsObject(p) && p.x = pref.x && p.y = pref.y, "a small window: the corner is clear")
    big := {x: 0, y: 0, w: 2200, h: 1300}
    p := FixCard.Spot(w, h, big, mon, pref)
    AssertTrue(!IsObject(p) || (p.x >= 2200 || p.y >= 1300 || p.x + w <= 0), "never over the game")
}

Test_FixIt_QuietForAndForget() {
    f := FixIt()
    AssertEq(f.QuietFor("shift", 1000), -1, "never seen")
    r := f.Seen("Fishing: shift lock may still be on - skipped (no click)", 1000)
    r := f.Seen("Sell: shift lock may still be on - skipped (no click)", 5000)
    AssertTrue(IsObject(r), "the card")
    AssertEq(f.QuietFor("shift", 65000), 60000, "quiet 60 s")
    AssertEq(f.Seen("Fishing: shift lock may still be on - skipped (no click)", 70000), "", "shown once")
    f.Forget("shift")
    f.Seen("Fishing: shift lock may still be on - skipped (no click)", 80000)
    AssertTrue(IsObject(f.Seen("Sell: shift lock may still be on - skipped (no click)", 81000)), "forgotten: may show again")
}

; the card closes itself once its line stops coming (the problem is gone);
; while the macro runs it never lies over the game
Test_App_FixCardClosesWhenTheProblemIsGone() {
    t := AppTestMake(Map())
    c := StuckFakeCard("shift")
    t.app.fixit.Seen("Sell: shift lock may still be on - skipped (no click)", t.clk.t)
    t.app._fixCard := c
    t.app._FixCardTick()
    AssertTrue(c.shows.Length >= 1 && !c.gone, "stopped: shown")
    t.clk.t += App.FixQuietMs - 1000
    t.app._FixCardTick()
    AssertTrue(!c.gone, "not yet")
    t.clk.t += 2000
    t.app._FixCardTick()
    AssertTrue(c.gone, "closed")
    AssertEq(t.app._fixCard, "", "forgotten")
    AssertTrue(StuckLogHas(t, "closed: the problem has not shown for"), "logged")
    ; a link problem is logged once and stays a problem: its card stays
    c3 := StuckFakeCard("nolink")
    t.app.fixit.Seen("recovery: no usable private server link", t.clk.t)
    t.app._fixCard := c3
    t.clk.t += App.FixQuietMs * 3
    t.app._FixCardTick()
    AssertTrue(!c3.gone, "nolink card kept")
    ; Start closes a card left from the last run
    c2 := StuckFakeCard("focus")
    t.app._fixCard := c2
    t.app.Start()
    AssertTrue(c2.gone, "Start closed it")
}
