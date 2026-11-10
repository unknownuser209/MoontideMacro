#Requires AutoHotkey v2.0
; Tests for the screen I/O layer: lib\Input.ahk (route parse + dry play,
; reset sequence), lib\Pixel.ahk (tolerance math, injected colors),
; lib\Roblox.ahk (pure rect check), lib\Ocr.ahk (smoke test on a temp Gui).
#Include ..\lib\Json.ahk
#Include ..\lib\Scheduler.ahk
#Include ..\lib\Roblox.ahk
#Include ..\lib\Input.ahk
#Include ..\lib\Pixel.ahk
#Include ..\lib\Ocr.ahk

; ---- helpers (names must not start with Test_) -----------------------------

; Recording IO backend: logs every action, sums waited ms, never sleeps.
; stopAtWait = n: the n-th Wait() call stops ctx (like F3 mid-sleep).
; throwAtWait = n: the n-th Wait() call throws.
class RtRecIO {
    __New(stopAtWait := 0, throwAtWait := 0) {
        this.log := []
        this.totalMs := 0
        this._waits := 0
        this._stopAt := stopAtWait
        this._throwAt := throwAtWait
    }
    Down(k) => this.log.Push("down " k)
    Up(k) => this.log.Push("up " k)
    MoveTo(x, y) => this.log.Push("move " x "," y)
    ClickHere() => this.log.Push("click")
    Wait(ms, ctx := "") {
        this._waits++
        if (this._throwAt && this._waits = this._throwAt)
            throw Error("rt boom")
        if (this._stopAt && this._waits = this._stopAt) {
            ctx.Stop()
            this.log.Push("wait-stopped")
            return false
        }
        this.log.Push("wait " ms)
        this.totalMs += ms
        return true
    }
}

RtJoin(arr) {
    s := ""
    for v in arr
        s .= (A_Index > 1 ? "|" : "") v
    return s
}

RtIndexOf(arr, val) {
    for v in arr
        if (v == val)
            return A_Index
    return 0
}

; ---- route parse + dry play ------------------------------------------------

Test_Route_ParseAndDryPlay() {
    src := '
    (
    [
      {"key": "w", "action": "down", "ms": 0},
      {"key": "a", "action": "down", "ms": 4150},
      {"key": "w", "action": "up", "ms": 600},
      {"key": "a", "action": "up", "ms": 200},
      ["Space", "tap", 25],
      {"action": "wait", "ms": 300},
      {"key": "e", "action": "tap", "ms": 300}
    ]
    )'
    steps := Input.ParseRoute(src)
    AssertEq(steps.Length, 7, "parsed step count")
    AssertEq(steps[2].key, "a", "step 2 key")
    AssertEq(steps[2].action, "down", "step 2 action")
    AssertEq(steps[2].ms, 4150, "step 2 ms")
    AssertEq(steps[5].key, "Space", "compact step key")
    AssertEq(steps[5].action, "tap", "compact step action")
    AssertEq(Input.RouteMs(steps), 5575, "RouteMs total")

    io := RtRecIO()
    ok := Input.PlayRoute(steps, SchedCtx(), io)
    AssertEq(ok, true, "route completed")
    expect := "down w|down a|wait 4150|up w|wait 600|up a|wait 200|down Space|wait 25|up Space|wait 300|down e|wait 300|up e"
    AssertEq(RtJoin(io.log), expect, "dry-play key log order")
    AssertEq(io.totalMs, 5575, "dry-play total ms")

    ; PlayRoute also accepts the raw JSON text and raw Json.Parse output.
    io2 := RtRecIO()
    Input.PlayRoute(src, SchedCtx(), io2)
    AssertEq(RtJoin(io2.log), expect, "raw json string")
    io3 := RtRecIO()
    Input.PlayRoute(Json.Parse(src), SchedCtx(), io3)
    AssertEq(RtJoin(io3.log), expect, "raw parsed array")
    ; Wrapped form {"steps": [...]}.
    io4 := RtRecIO()
    Input.PlayRoute('{"steps": [["w", "tap", 40]]}', SchedCtx(), io4)
    AssertEq(RtJoin(io4.log), "down w|wait 40|up w", "wrapped steps object")
}

Test_Route_InRouteWhilePlaying() {
    seen := []
    io := RtRecIO()
    io.DefineProp("Wait", {Call: (self, ms, ctx := "") => (seen.Push(Input.InRoute), true)})
    AssertEq(Input.InRoute, false, "not in a route before")
    Input.PlayRoute('[["w","down",0],["w","up",300]]', SchedCtx(), io)
    AssertTrue(seen.Length > 0 && seen[1], "InRoute while the route waits")
    AssertEq(Input.InRoute, false, "cleared after the route")
    ctx := SchedCtx()
    ctx.Stop()
    Input.PlayRoute('[["w","down",0],["w","up",300]]', ctx, RtRecIO())
    AssertEq(Input.InRoute, false, "cleared after a stopped route too")
}

Test_Route_StopMidRouteReleasesKeys() {
    steps := Input.ParseRoute('[["w","down",0],["a","down",4150],["w","up",600],["a","up",200],["e","tap",300]]')
    ctx := SchedCtx()
    io := RtRecIO(1)    ; F3 during the 4150 ms wait
    ok := Input.PlayRoute(steps, ctx, io)
    AssertEq(ok, false, "stopped route returns false")
    stopAt := RtIndexOf(io.log, "wait-stopped")
    AssertTrue(stopAt > 0, "stop happened")
    after := []
    Loop io.log.Length - stopAt
        after.Push(io.log[stopAt + A_Index])
    AssertTrue(RtIndexOf(after, "up w") > 0, "w released after stop")
    AssertTrue(RtIndexOf(after, "up a") > 0, "a released after stop")
    AssertEq(after.Length, 2, "only releases after stop")
    AssertEq(RtIndexOf(io.log, "down e"), 0, "no further steps")

    ; Already stopped before start: nothing pressed.
    ctx2 := SchedCtx()
    ctx2.Stop()
    io2 := RtRecIO()
    AssertEq(Input.PlayRoute(steps, ctx2, io2), false, "pre-stopped returns false")
    AssertEq(io2.log.Length, 0, "pre-stopped presses nothing")

    ; Paused counts as stop too (ShouldStop), keys released.
    ctx3 := SchedCtx()
    io3 := RtRecIO()
    steps3 := Input.ParseRoute('[["w","down",100],["w","up",0]]')
    ctx3.Pause()
    AssertEq(Input.PlayRoute(steps3, ctx3, io3), false, "paused returns false")
    AssertEq(io3.log.Length, 0, "paused presses nothing")

    ; Exception mid-route still releases held keys, then rethrows.
    io4 := RtRecIO(0, 1)
    threw := false
    try Input.PlayRoute(steps, SchedCtx(), io4)
    catch Error as e
        threw := (e.Message = "rt boom")
    AssertTrue(threw, "error propagates")
    AssertTrue(RtIndexOf(io4.log, "up w") > 0, "w released after throw")
    AssertTrue(RtIndexOf(io4.log, "up a") > 0, "a released after throw")

    ; A route that ends with a key still down gets it released at the end.
    io5 := RtRecIO()
    AssertEq(Input.PlayRoute('[["d","down",50]]', SchedCtx(), io5), true, "dangling route completes")
    AssertEq(RtJoin(io5.log), "down d|wait 50|up d", "dangling key released")
}

; Recorder that runs a callback on every Wait (sees mid-route state).
class RtHookIO extends RtRecIO {
    __New(hook) {
        super.__New()
        this._hook := hook
    }
    Wait(ms, ctx := "") {
        (this._hook)(this, ctx)
        return super.Wait(ms, ctx)
    }
}

; Recorder whose Down("a") throws after logging.
class RtDownThrowIO extends RtRecIO {
    Down(k) {
        this.log.Push("down " k)
        if (k = "a")
            throw Error("down boom")
    }
}

Test_Input_HeldRegistryAndReleaseAll() {
    Input.ReleaseAll()      ; start clean
    AssertEq(Input._held.Count, 0, "registry starts empty")
    AssertTrue(Input._exitHooked, "ReleaseAll registered via OnExit")
    route := '[["w","down",0],["a","down",4150],["w","up",600],["a","up",200],["e","tap",300]]'

    ; Mid-route the registry holds what is down; empty after a normal run.
    seen := []
    io := RtHookIO((self, ctx) => seen.Push(Input._held.Count))
    AssertEq(Input.PlayRoute(route, SchedCtx(), io), true, "normal route")
    AssertEq(seen[1], 2, "w+a registered mid-route")
    AssertEq(Input._held.Count, 0, "registry empty after normal route")

    ; Empty after a stopped route.
    AssertEq(Input.PlayRoute(route, SchedCtx(), RtRecIO(1)), false, "stopped route")
    AssertEq(Input._held.Count, 0, "registry empty after stopped route")

    ; Empty after Key().
    Input.Key("e", 10, RtRecIO())
    AssertEq(Input._held.Count, 0, "registry empty after Key")

    ; Simulated exit mid-route (finally never runs): ReleaseAll lifts keys.
    io2 := RtRecIO()
    Input._Press("w", io2)
    Input._Press("a", io2)
    AssertEq(Input._held.Count, 2, "two keys left held")
    Input.ReleaseAll()
    AssertEq(Input._held.Count, 0, "ReleaseAll clears registry")
    AssertTrue(RtIndexOf(io2.log, "up w") > 0, "ReleaseAll released w")
    AssertTrue(RtIndexOf(io2.log, "up a") > 0, "ReleaseAll released a")
    AssertEq(io2.log.Length, 4, "two downs + two ups")

    ; Down that throws still leaves the key registered (registered first),
    ; and the route's finally releases it.
    io3 := RtDownThrowIO()
    threw := false
    try Input.PlayRoute('[["w","down",0],["a","down",10]]', SchedCtx(), io3)
    catch Error
        threw := true
    AssertTrue(threw, "down error propagates")
    AssertTrue(RtIndexOf(io3.log, "up a") > 0, "a released even though Down threw")
    AssertTrue(RtIndexOf(io3.log, "up w") > 0, "w released")
    AssertEq(Input._held.Count, 0, "registry empty after Down throw")
}

Test_Route_RejectsBadSteps() {
    bad := [
        '[{"key":"w","action":"hold","ms":10}]',
        '[{"key":"{w}","action":"tap","ms":10}]',
        '[{"key":"w","action":"tap","ms":-5}]',
        '[{"key":"w","action":"tap"}]',
        '[{"action":"down","ms":10}]',
        '[["w","tap"]]',
        '{"nosteps": 1}',
        '[42]'
    ]
    for src in bad {
        threw := false
        try Input.ParseRoute(src)
        catch ValueError
            threw := true
        AssertTrue(threw, "rejects bad route #" A_Index)
    }
    ; Validation happens before any key is pressed.
    io := RtRecIO()
    threw := false
    try Input.PlayRoute('[["w","down",10],["x","bogus",10]]', SchedCtx(), io)
    catch ValueError
        threw := true
    AssertTrue(threw, "PlayRoute validates")
    AssertEq(io.log.Length, 0, "nothing pressed on invalid route")
    ; Empty route is valid and completes.
    AssertEq(Input.PlayRoute("[]", SchedCtx(), RtRecIO()), true, "empty route ok")
}

Test_Input_ResetToSpawnDry() {
    io := RtRecIO()
    ok := Input.ResetToSpawn(SchedCtx(), io)
    AssertEq(ok, true, "reset completes")
    c := Input.ResetCoords
    AssertEq(c["menuOpen"][1], 52, "menuOpen x")
    AssertEq(c["menuOpen"][2], 621, "menuOpen y")
    AssertEq(c["menuClose"][1], 525, "menuClose x")
    AssertEq(c["menuClose"][2], 158, "menuClose y")
    expect := "down Esc|wait 50|up Esc|wait 650"
        . "|down r|wait 50|up r|wait 650"
        . "|down Enter|wait 50|up Enter|wait 2600"
        . "|move 52,621|wait 220|click|wait 220"
        . "|move 525,158|wait 220|click|wait 220"
    AssertEq(RtJoin(io.log), expect, "reset sequence")
    ; Stop during the 2600 ms respawn wait: no clicks afterwards.
    io2 := RtRecIO(6)
    AssertEq(Input.ResetToSpawn(SchedCtx(), io2), false, "reset stopped")
    AssertEq(RtIndexOf(io2.log, "click"), 0, "no clicks after stop")
}

Test_Input_KeyAndClickDry() {
    io := RtRecIO()
    Input.Key("e", 80, io)
    Input.Click(100, 200, io)
    AssertEq(RtJoin(io.log), "down e|wait 80|up e|move 100,200|wait 30|click", "key + click")
}

; ---- pixel -----------------------------------------------------------------

Test_Pixel_ToleranceMath() {
    AssertEq(Pixel.ToRgb(0xFF8000), 0xFF8000, "int passthrough")
    AssertEq(Pixel.ToRgb("0xFF8000"), 0xFF8000, "0x string")
    AssertEq(Pixel.ToRgb("#ff8000"), 0xFF8000, "# string")
    AssertEq(Pixel.ToRgb("ff8000"), 0xFF8000, "bare hex")
    AssertEq(Pixel.Match(0x102030, 0x1A2A3A, 10), true, "diff 10 each in tol")
    AssertEq(Pixel.Match(0x102030, 0x1B2030, 10), false, "red diff 11 out")
    AssertEq(Pixel.Match(0x102030, 0x10203B, 10), false, "blue diff 11 out")
    AssertEq(Pixel.Match(0x102030, 0x06162A, 10), true, "negative diffs in tol")
    AssertEq(Pixel.Match(0xFFFFFF, 0xFFFFFF, 0), true, "exact tol 0")
    AssertEq(Pixel.Match(0xFFFFFF, 0xFFFFFE, 0), false, "off by one tol 0")
    AssertEq(Pixel.Match("0x000000", "#FFFFFF", 255), true, "tol 255 matches all")
    bad := false
    try Pixel.ToRgb("nothex")
    catch ValueError
        bad := true
    AssertTrue(bad, "bad color string throws")
}

Test_Pixel_IsAndWaitForInjected() {
    saved := Pixel._getter
    try {
        Pixel._getter := (x, y) => (x = 5 && y = 6) ? "0x80FF20" : "0x000000"
        AssertEq(Pixel.Is(5, 6, 0x84FB24), true, "Is in tol")
        AssertEq(Pixel.Is(5, 6, 0x80FF20, 0), true, "Is exact")
        AssertEq(Pixel.Is(5, 7, 0x80FF20), false, "Is other pixel")
        AssertEq(Pixel.Is(5, 6, "#90FF20"), false, "Is out of tol")

        ; Matches on the 3rd poll.
        calls := 0
        Pixel._getter := (x, y) => (++calls >= 3) ? 0xFFFFFF : 0x000000
        AssertEq(Pixel.WaitFor(1, 1, 0xFFFFFF, 2000, SchedCtx(), 10, 5), true, "WaitFor match")
        AssertEq(calls, 3, "WaitFor polled 3x")

        ; Never matches -> timeout false.
        Pixel._getter := (x, y) => 0x000000
        t0 := A_TickCount
        AssertEq(Pixel.WaitFor(1, 1, 0xFFFFFF, 120, SchedCtx(), 10, 10), false, "WaitFor timeout")
        AssertTrue(A_TickCount - t0 >= 100, "WaitFor waited ~timeout")

        ; ctx stopped -> false immediately.
        ctx := SchedCtx()
        ctx.Stop()
        t0 := A_TickCount
        AssertEq(Pixel.WaitFor(1, 1, 0xFFFFFF, 5000, ctx), false, "WaitFor stop")
        AssertTrue(A_TickCount - t0 < 1000, "WaitFor stop is quick")
        ; No ctx works too.
        Pixel._getter := (x, y) => 0xFFFFFF
        AssertEq(Pixel.WaitFor(1, 1, 0xFFFFFF, 100), true, "WaitFor no ctx")
    } finally {
        Pixel._getter := saved
    }
}

; ---- roblox ----------------------------------------------------------------

; the fullscreen gate: tests\test_screen.ahk (Test_Roblox_CoversMonitor)

; ---- ocr -------------------------------------------------------------------

Test_Ocr_BadArgsReturnEmpty() {
    AssertEq(Ocr.Read(0, 0, 0, 10), "", "zero width")
    AssertEq(Ocr.Read(0, 0, 10, -1), "", "negative height")
    AssertEq(Ocr.Read("x", 0, 10, 10), "", "non-numeric")
}

; Renders known text in a temporary borderless Gui, OCRs that region.
; Skips with a PASS note if the Gui can't be seen on screen (no desktop,
; locked session); the skip check samples the Gui's background pixel.
Test_Ocr_SmokeGuiText() {
    gx := 120, gy := 160, gw := 640, gh := 110
    g := Gui("+AlwaysOnTop -Caption +ToolWindow -DPIScale")
    g.BackColor := "FFFFFF"
    g.MarginX := 20, g.MarginY := 20
    g.SetFont("s36 c000000", "Segoe UI")
    g.AddText("x20 y20 w600 h70", "VESPER OCR 4217")
    try {
        g.Show("x" gx " y" gy " w" gw " h" gh " NoActivate")
        Sleep(400)
        visible := Pixel.Is(gx + 5, gy + 5, 0xFFFFFF, 8) && Pixel.Is(gx + gw - 5, gy + gh - 5, 0xFFFFFF, 8)
        if !visible {
            FileAppend("NOTE Test_Ocr_SmokeGuiText skipped: temp Gui not visible on screen`n", "*")
            return
        }
        t0 := A_TickCount
        text := Ocr.Read(gx, gy, gw, gh)
        ms := A_TickCount - t0
        FileAppend("NOTE ocr smoke read <" StrReplace(text, "`n", " / ") "> in " ms " ms`n", "*")
        up := StrUpper(text)
        AssertTrue(InStr(up, "VESPER"), "ocr finds VESPER")
        AssertTrue(InStr(up, "4217"), "ocr finds 4217")
        ; Repeated calls must not leak or fail (objects released per call).
        Loop 5
            AssertTrue(InStr(StrUpper(Ocr.Read(gx, gy, gw, gh)), "VESPER"), "ocr repeat " A_Index)
    } finally {
        g.Destroy()
    }
}
