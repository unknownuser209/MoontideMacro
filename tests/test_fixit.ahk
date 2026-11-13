#Requires AutoHotkey v2.0
; Tests for lib\FixIt.ahk and lib\ui\FixCard.ahk (idea 10, 2026-11-13).
#Include ..\lib\FixIt.ahk
#Include ..\lib\ui\FixCard.ahk

Test_FixIt_CardAfterRepeats() {
    f := FixIt()
    focus := "Paused: " App.Msg["unfocused"][2] " In front: notepad.exe."
    AssertEq(f.Seen(focus), "", "one focus loss: no card yet")
    r := f.Seen(focus)
    AssertTrue(IsObject(r) && r.key = "focus", "the second one: the focus card")
    AssertEq(f.Seen(focus), "", "shown once")
    f.Reset()
    f.Seen(focus)
    AssertTrue(IsObject(f.Seen(focus)), "a new run: it may show again")
    AssertEq(f.Seen("task: fishing start"), "", "ordinary lines: nothing")
}

Test_FixIt_RealLogLines() {
    cases := Map("notfs", "Paused: " App.Msg["notfs"][2]
        , "nolink", "recovery: no private server link set (General.privateServer): cannot rejoin"
        , "rejoins", "recovery: rejoin limit reached (3 in 10 min): trying again when the oldest attempt is 10 min old"
        , "webhook", 'Webhook "main": send failed (HTTP 404), giving up'
        , "inventory", "Potions: the inventory did not open (its tab labels did not read): all potion use stopped")
    for key, line in cases {
        f := FixIt()
        r := ""
        Loop FixIt.Rule(key).n
            r := f.Seen(line)
        AssertTrue(IsObject(r) && r.key = key, key " card from its real log line")
    }
    for r in FixIt.Rules {
        AssertTrue(r.title != "" && StrLen(r.fix) >= 30, r.key ": a title and a plain fix")
        AssertTrue(r.page = "" || Dashboard.PageIndex(r.page) > 0, r.key ": a real page")
    }
}

Test_FixIt_DismissAndCard() {
    f := FixIt()
    f.Dismiss("notfs")
    AssertEq(f.Seen("Paused: " App.Msg["notfs"][2]), "", "dismissed: not shown")
    got := []
    c := FixCard(FixIt.Rule("notfs"), Map("act", (a) => (got.Push("act:" a), "done"), "dismiss", (k) => got.Push("dismiss:" k)))
    try {
        AssertEq(c.Ctrl("title").Text, "Roblox is not fullscreen", "title")
        AssertTrue(IsObject(c.Ctrl("act")), "a Fix it for me button")
        c._Act()
        AssertEq(got[1], "act:fullscreen", "the action asked")
        AssertEq(c.Ctrl("note").Text, "done", "its answer shown")
        c.Dismiss()
        AssertEq(got[2], "dismiss:notfs", "dismiss told")
    } finally
        c.Destroy()
    c2 := FixCard(FixIt.Rule("nolink"))
    try {
        AssertTrue(!c2._ids.Has("act") && IsObject(c2.Ctrl("page")), "no action: only Open the page")
    } finally
        c2.Destroy()
}
