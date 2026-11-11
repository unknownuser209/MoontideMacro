#Requires AutoHotkey v2.0
; Tests for lib\RouteRecorder.ahk (pure parts: events -> steps, session state
; machine, JSON merge, atomic save). No keyboard is read, nothing is sent.
#Include ..\lib\RouteRecorder.ahk

RrEv(key, action, t) => {key: key, action: action, t: t}

RrTmp() {
    d := A_Temp "\vesper_rrtest_" A_TickCount "_" Random(100000, 999999)
    DirCreate(d)
    return d
}

; Fake physical keyboard for Session.Feed: a Map of held keys.
class RrKeys {
    __New() {
        this.down := Map()
        this.down.CaseSense := "Off"
    }
    Set(k, d) => this.down[k] := d
    Fn() => ((k) => this.down.Has(k) && this.down[k])
}

RrStepsText(steps) {
    s := ""
    for st in steps
        s .= (s = "" ? "" : " ") st[1] "/" st[2] "/" st[3]
    return s
}

Test_RouteRec_EventsToSteps() {
    ev := [RrEv("w", "down", 1000), RrEv("a", "down", 1500), RrEv("w", "up", 2100), RrEv("a", "up", 2300)]
    steps := RouteRecorder.EventsToSteps(ev, 2500)
    AssertEq(RrStepsText(steps), "w/down/500 a/down/600 w/up/200 a/up/0", "ms = time to the next event, last 0")
    AssertEq(Input.ParseRoute(steps).Length, 4, "PlayRoute format")
    ; a key still held at stop is released at the stop time
    steps := RouteRecorder.EventsToSteps([RrEv("w", "down", 0), RrEv("Space", "down", 300)], 800)
    AssertEq(RrStepsText(steps), "w/down/300 Space/down/500 w/up/0 Space/up/0", "held keys get an up at the end")
    ; duplicates (auto-repeat) and stray ups dropped, names normalised
    steps := RouteRecorder.EventsToSteps([RrEv("d", "up", 5), RrEv("W", "down", 10), RrEv("w", "down", 40)
        , RrEv("space", "down", 60), RrEv("w", "up", 90), RrEv("SPACE", "up", 100)], 100)
    AssertEq(RrStepsText(steps), "w/down/50 Space/down/30 w/up/10 Space/up/0", "dupes dropped, keys normalised")
    AssertEq(RouteRecorder.EventsToSteps([], 50).Length, 0, "no events -> no steps")
    for bad in [[RrEv("q", "down", 1)], [RrEv("w", "tap", 1)], [RrEv("w", "down", 10), RrEv("w", "up", 5)], [RrEv("w", "down", "x")]] {
        threw := false
        try RouteRecorder.EventsToSteps(bad, 20)
        catch ValueError
            threw := true
        AssertTrue(threw, "bad event list rejected")
    }
}

Test_RouteRec_TrimInteractDropsTheFinalE() {
    ; the user's real quest_board recording ended "... w up, E down, E up":
    ; the macro presses E itself, a second E would close the board again
    steps := [["w", "down", 400], ["w", "up", 1266], ["e", "down", 78], ["e", "up", 0]]
    tr := RouteRecorder.TrimInteract(steps)
    AssertEq(RrStepsText(tr.steps), "w/down/400 w/up/0", "final E tap removed, last wait 0")
    AssertEq(tr.dropped.Length, 1, "one key dropped")
    AssertEq(tr.dropped[1], "e", "it was E")
    AssertEq(steps.Length, 4, "input not changed")
    ; F (cauldron) too, and a double tap
    tr := RouteRecorder.TrimInteract([["d", "down", 10], ["d", "up", 5], ["f", "down", 50], ["f", "up", 90], ["f", "down", 40], ["f", "up", 0]])
    AssertEq(RrStepsText(tr.steps), "d/down/10 d/up/0", "both F taps removed")
    ; E pressed mid-route stays; a route without E is unchanged
    tr := RouteRecorder.TrimInteract([["e", "down", 50], ["e", "up", 100], ["w", "down", 300], ["w", "up", 0]])
    AssertEq(RrStepsText(tr.steps), "e/down/50 e/up/100 w/down/300 w/up/0", "E in the middle kept")
    AssertEq(tr.dropped.Length, 0, "nothing dropped")
    ; E held while W is released (overlapping) is not a clean tap: kept
    tr := RouteRecorder.TrimInteract([["w", "down", 100], ["e", "down", 50], ["w", "up", 50], ["e", "up", 0]])
    AssertEq(tr.steps.Length, 4, "overlapping E kept")
    AssertEq(RouteRecorder.InteractKey("quest_board"), "e", "quest board key")
    AssertEq(RouteRecorder.InteractKey("cauldron"), "f", "cauldron key")
    AssertEq(RouteRecorder.InteractKey("nudge"), "", "other routes: none")
}

Test_RouteRec_SessionStateMachine() {
    kb := RrKeys()
    s := RouteRecorder.Session()
    f := kb.Fn()
    AssertEq(s.Feed(0, f), "waiting", "waits for F7")
    kb.Set("w", true)
    s.Feed(10, f)
    AssertEq(s.events.Length, 0, "keys before F7 are not recorded")
    kb.Set("F7", true)
    AssertEq(s.Feed(100, f), "recording", "F7 starts")
    AssertEq(s.events.Length, 1, "key already held at start recorded as down")
    s.Feed(110, f)                                  ; F7 still held: not a stop
    kb.Set("F7", false)
    s.Feed(120, f)
    kb.Set("a", true)
    s.Feed(400, f)
    kb.Set("w", false)
    s.Feed(900, f)
    kb.Set("F7", true)
    AssertEq(s.Feed(1000, f), "done", "F7 again stops")
    AssertEq(RrStepsText(s.Steps()), "w/down/300 a/down/500 w/up/100 a/up/0", "steps from the session")
    AssertTrue(s.Done(), "done")
    ; Esc cancels, too long discards
    kb2 := RrKeys(), s2 := RouteRecorder.Session(), f2 := kb2.Fn()
    kb2.Set("F7", true), s2.Feed(0, f2)
    kb2.Set("Escape", true)
    AssertEq(s2.Feed(50, f2), "cancelled", "Esc cancels")
    ; before F7 a tap of Esc is the game's respawn (Esc, R, Enter), not a
    ; cancel (review 2026-10-27); holding it cancels
    kb4 := RrKeys(), s4 := RouteRecorder.Session(), f4 := kb4.Fn()
    kb4.Set("Escape", true)
    AssertEq(s4.Feed(0, f4), "waiting", "Esc tap while waiting: still waiting")
    kb4.Set("Escape", false)
    AssertEq(s4.Feed(100, f4), "waiting", "released")
    kb4.Set("F7", true)
    AssertEq(s4.Feed(200, f4), "recording", "F7 still starts after the respawn")
    kb5 := RrKeys(), s5 := RouteRecorder.Session(), f5 := kb5.Fn()
    kb5.Set("Escape", true)
    s5.Feed(0, f5)
    AssertEq(s5.Feed(RouteRecorder.HoldCancelMs + 10, f5), "cancelled", "Esc held while waiting cancels")
    kb3 := RrKeys(), s3 := RouteRecorder.Session(), f3 := kb3.Fn()
    kb3.Set("F7", true), s3.Feed(0, f3), kb3.Set("F7", false)
    AssertEq(s3.Feed(RouteRecorder.MaxMs + 1, f3), "toolong", "over MaxMs discarded")
}

Test_RouteRec_MergeKeepsOthers() {
    routes := Json.Parse(FileRead(A_ScriptDir "\..\data\routes.json", "UTF-8"))
    vipBefore := Json.Stringify(routes["vip"], 0)
    note := routes["cauldron"]["_note"]
    steps := [["w", "down", 500], ["w", "up", 0]]
    RouteRecorder.Merge(routes, "cauldron", steps, "2026-10-25 12:00")
    AssertEq(routes["cauldron"]["steps"].Length, 2, "steps stored")
    AssertEq(routes["cauldron"]["_recorded"], "2026-10-25 12:00", "stamp stored")
    AssertEq(routes["cauldron"]["_note"], note, "_note kept")
    AssertTrue(!routes["cauldron"].Has("_todo"), "_todo dropped once recorded")
    AssertEq(Json.Stringify(routes["vip"], 0), vipBefore, "other routes untouched")
    RouteRecorder.Merge(routes, "quest_board", steps, "x")
    AssertEq(Input.ParseRoute(routes["quest_board"]).Length, 2, "new route added, readable by Input.ParseRoute")
    ; {"routes": {...}} wrapper respected
    w := Map("routes", Map("mari", [["a", "down", 1], ["a", "up", 0]]))
    RouteRecorder.Merge(w, "jester", steps, "x")
    AssertTrue(w["routes"].Has("jester") && !w.Has("jester"), "merged inside the routes wrapper")
    ; names
    for bad in ["vip", "nonvip", "_source", "Quest", "", "a b", "1x"] {
        AssertTrue(!RouteRecorder.ValidName(bad), "name refused: <" bad ">")
        threw := false
        try RouteRecorder.Merge(Map(), bad, steps)
        catch ValueError
            threw := true
        AssertTrue(threw, "merge refuses <" bad ">")
    }
    for good in RouteRecorder.Names
        AssertTrue(RouteRecorder.ValidName(good), "name allowed: " good)
}

Test_RouteRec_SaveAtomicAndGuards() {
    d := RrTmp()
    try {
        p := d "\routes.json"
        FileCopy(A_ScriptDir "\..\data\routes.json", p)
        steps := [["w", "down", 400], ["a", "down", 200], ["w", "up", 100], ["a", "up", 0]]
        r := RouteRecorder.Save(p, "mari", steps)
        back := Json.Parse(FileRead(p, "UTF-8"))
        AssertEq(Input.ParseRoute(back["mari"]).Length, 4, "saved and re-read")
        AssertTrue(back.Has("vip") && back.Has("nonvip") && back.Has("cauldron"), "existing routes kept")
        AssertTrue(r is Map && r.Has("mari"), "returns the merged routes")
        AssertTrue(!FileExist(p ".tmp"), "no tmp left")
        ; missing file -> created
        p2 := d "\new.json"
        RouteRecorder.Save(p2, "jester", steps)
        AssertTrue(Json.Parse(FileRead(p2, "UTF-8")).Has("jester"), "missing file created")
        ; a file that does not parse is never overwritten
        p3 := d "\bad.json"
        FileAppend("{not json", p3, "UTF-8-RAW")
        threw := false
        try RouteRecorder.Save(p3, "mari", steps)
        catch Error
            threw := true
        AssertTrue(threw, "bad JSON refused")
        AssertEq(FileRead(p3, "UTF-8"), "{not json", "bad file unchanged")
        ; directory guards (FileMove onto a directory)
        DirCreate(d "\isdir.json")
        threw := false
        try RouteRecorder.Save(d "\isdir.json", "mari", steps)
        catch Error
            threw := true
        AssertTrue(threw, "target is a directory: refused")
        DirCreate(d "\t2.json.tmp")
        threw := false
        try RouteRecorder.WriteAtomic(d "\t2.json", "x")
        catch Error
            threw := true
        AssertTrue(threw, "tmp is a directory: refused")
        AssertTrue(!FileExist(d "\t2.json"), "nothing written")
        ; empty / invalid steps never saved
        for bad in [[], [["w", "down", -1]]] {
            threw := false
            try RouteRecorder.Save(p, "mari", bad)
            catch Error
                threw := true
            AssertTrue(threw, "bad steps refused")
        }
        AssertEq(Input.ParseRoute(Json.Parse(FileRead(p, "UTF-8"))["mari"]).Length, 4, "file kept after refusals")
    } finally {
        try DirDelete(d, true)
    }
}

; Fake raw mouse: queue of {dx, dy, wheel} handed out one per poll.
class RrMouse {
    __New() {
        this.q := []
    }
    Add(dx, dy, wheel := 0) => this.q.Push({dx: dx, dy: dy, wheel: wheel})
    Fn() => (() => this.q.Length ? this.q.RemoveAt(1) : {dx: 0, dy: 0, wheel: 0})
}

; Records what PlayRoute sends.
class RrPlayIO {
    __New() {
        this.log := []
    }
    Down(k) => this.log.Push("down " k)
    Up(k) => this.log.Push("up " k)
    Look(dx, dy) => this.log.Push("look " dx "," dy)
    Wheel(dir, n := 1, gapMs := 25) => this.log.Push("wheel " dir " " n)
    Wait(ms, ctx := "") => (this.log.Push("wait " ms), true)
    Text() {
        t := ""
        for l in this.log
            t .= (t = "" ? "" : " | ") l
        return t
    }
}

Test_RouteRec_CameraRecordedWhileRightButtonHeld() {
    kb := RrKeys(), ms := RrMouse()
    s := RouteRecorder.Session()
    f := kb.Fn(), m := ms.Fn()
    ms.Add(500, 0)                                   ; before F7: dropped
    s.Feed(0, f, m)
    kb.Set("F7", true)
    s.Feed(10, f, m)
    kb.Set("F7", false)
    ms.Add(300, 0)                                   ; no right button: cursor move, not recorded
    s.Feed(20, f, m)
    kb.Set("RButton", true)
    s.Feed(100, f, m)                                ; right button down
    ms.Add(40, -5)
    s.Feed(110, f, m)
    ms.Add(60, 5)
    s.Feed(120, f, m)
    ms.Add(100, 0)
    s.Feed(160, f, m)                                ; 50 ms after the first move: merged step
    kb.Set("RButton", false)
    ms.Add(0, 0, 240)                                ; two wheel notches up = zoom in 2
    s.Feed(300, f, m)
    ms.Add(0, 0, -120)
    s.Feed(400, f, m)
    kb.Set("F7", true)
    AssertEq(s.Feed(500, f, m), "done", "stopped")
    AssertEq(RrStepsText(s.Steps()), "RButton/down/10 look/200/0 RButton/up/0 zoom/2/100 zoom/-1/0", "camera steps")
    steps := s.Steps()
    AssertEq(steps[2].Length, 4, "look step has 4 items")
    AssertEq(steps[2][4], 190, "look waits until the button release")
    AssertEq(Input.ParseRoute(steps).Length, 5, "valid PlayRoute steps")
}

Test_RouteRec_CameraStepsReplay() {
    io := RrPlayIO()
    ok := Input.PlayRoute([["RButton", "down", 10], ["look", 200, -15, 30], ["RButton", "up", 0], ["zoom", 3, 0], ["zoom", -2, 50], ["w", "down", 100], ["w", "up", 0]], "", io)
    AssertTrue(ok, "played")
    AssertEq(io.Text(), "down RButton | wait 10 | look 200,-15 | wait 30 | up RButton | wheel up 3 | wheel down 2 | wait 50 | down w | wait 100 | up w", "replay order")
    for bad in [[["look", 1, 30]], [["look", "x", 0, 10]], [["zoom", 0, 10]], [["look", 200000, 0, 10]], [["zoom", 1.5, 10]]] {
        threw := false
        try Input.ParseRoute(bad)
        catch ValueError
            threw := true
        AssertTrue(threw, "bad camera step rejected")
    }
    AssertEq(Input.ParseRoute([Map("action", "look", "dx", 5, "dy", 6, "ms", 7)])[1].dx, 5, "object form look")
}

; Clock-driven fake: every key press/release costs 7 ms and every Wait
; oversleeps by 15 ms (a timer tick), like the real thing without the fix.
class RrSlowIO {
    __New(withClock := true) {
        this.t := 0
        this.marks := []          ; [key action, time]
        this.withClock := withClock
    }
    Now() => this.t
    Down(k) => (this.t += 7, this.marks.Push([k " down", this.t]))
    Up(k) => (this.t += 7, this.marks.Push([k " up", this.t]))
    Wait(ms, ctx := "") => (this.t += ms + 15, true)
}

class RrSlowNoClockIO {
    __New() {
        this.t := 0
    }
    Down(k) => this.t += 7
    Up(k) => this.t += 7
    Wait(ms, ctx := "") => (this.t += ms + 15, true)
}

Test_RouteRec_PlaybackKeepsToTheRecordedTimeline() {
    ; 20 short taps of the Right arrow (camera) and W: 1000 ms recorded
    steps := []
    Loop 10
        steps.Push(["Right", "down", 30]), steps.Push(["Right", "up", 20])
    Loop 5
        steps.Push(["w", "down", 60]), steps.Push(["w", "up", 40])
    planned := Input.RouteMs(steps)
    AssertEq(planned, 1000, "recorded 1000 ms")
    io := RrSlowIO()
    AssertTrue(Input.PlayRoute(steps, "", io), "played")
    AssertTrue(io.t <= planned + 40, "timeline: the whole route takes about what was recorded (" io.t " ms for " planned ")")
    AssertTrue(Abs(Input.LastRouteMs - io.t) <= 1, "LastRouteMs reports the real time")
    ; every key change happens close to its recorded moment, not later and later
    due := 0, worst := 0
    for i, st in steps {
        worst := Max(worst, Abs(io.marks[i][2] - due))
        due += st[3]
    }
    AssertTrue(worst <= 30, "no drift along the route (worst " worst " ms)")
    ; the old way (no clock): every step adds its overshoot
    old := RrSlowNoClockIO()
    Input.PlayRoute(steps, "", old)
    AssertTrue(old.t >= planned + 400, "without the timeline it ran long (" old.t " ms): the bug the user saw")
}

Test_RouteRec_RealWaitIsPrecise() {
    ; the real backend's Wait on the precise clock, 1 ms timer on
    io := InputScreenIO()
    Input.HiRes(true)
    try {
        over := 0
        Loop 10 {
            t := Input.NowMs()
            io.Wait(23)
            over += (Input.NowMs() - t) - 23
        }
    } finally
        Input.HiRes(false)
    AssertTrue(over / 10 < 6, "average overshoot " Round(over / 10, 2) " ms (was up to 15.6)")
    AssertEq(Input._hiRes, 0, "timer resolution handed back")
}

Test_RouteRec_NeverSendsInput() {
    ; the recorder only observes keys: no Send / Click / MouseMove / io calls
    for rel in ["\..\lib\RouteRecorder.ahk", "\..\tools\record_route.ahk"] {
        path := A_ScriptDir rel
        AssertTrue(FileExist(path), rel " exists")
        code := ""
        for line in StrSplit(FileRead(path, "UTF-8"), "`n", "`r") {
            if !RegExMatch(line, "^\s*;")
                code .= RegExReplace(line, "\s;.*$") "`n"
        }
        AssertTrue(!RegExMatch(code, "i)\b(Send\w*|Click|MouseMove|MouseClick|ControlSend|ControlClick)\s*\("), rel ": no input sent")
        AssertTrue(!RegExMatch(code, "i)Input\.(Click|Key|Combo|TypeText|PlayRoute|ResetToSpawn)\b"), rel ": no Input helpers")
    }
}

Test_RouteRec_NamesIncludeObbyAndMemoryMatch() {
    has := Map()
    for n in RouteRecorder.Names
        has[n] := 1
    AssertTrue(has.Has("obby") && has.Has("memory_match"), "obby and memory_match are recordable")
}

; a fresh install shows the shipped sell walks, not "not recorded" (they are
; the vip / nonvip toShop / back the macro walks while none is recorded)
Test_RouteRec_BuiltinSellWalks() {
    routes := Map("vip", Map("toShop", [["w", "down", 0], ["w", "up", 500], ["e", "down", 300], ["e", "up", 300]], "back", [["a", "down", 0], ["a", "up", 900]])
        , "nonvip", Map("toShop", [["w", "down", 0], ["w", "up", 600], ["e", "down", 300], ["e", "up", 300]], "back", [["a", "down", 0], ["a", "up", 1100]]))
    b := RouteRecorder.BuiltinWalk(routes, "sell_to_fisher", true)
    AssertTrue(IsObject(b), "sell_to_fisher has a built-in walk")
    AssertEq(b.steps.Length, 2, "its closing E is left out (the walk test presses it)")
    AssertEq(b.label, "built-in VIP walk", "label")
    b := RouteRecorder.BuiltinWalk(routes, "fisher_to_fishing", false)
    AssertEq(b.steps[2][3], 1100, "non-VIP back walk")
    AssertEq(b.label, "built-in non-VIP walk", "non-VIP label")
    AssertEq(RouteRecorder.BuiltinWalk(routes, "quest_board", true), "", "other routes have none")
    AssertEq(RouteRecorder.BuiltinWalk(Map(), "sell_to_fisher", true), "", "no shipped walk: none")
}
