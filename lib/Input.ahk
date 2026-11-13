#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\Json.ahk
#Include %A_LineFile%\..\Ocr.ahk
#Include %A_LineFile%\..\Screenshot.ahk
#Include %A_LineFile%\..\Screen.ahk
#Include %A_LineFile%\..\Pixel.ahk
#Include %A_LineFile%\..\ChatGuard.ahk
; ---------------------------------------------------------------------------
; Input: keyboard/mouse helpers and the timed route player.
; DESIGN coordinates (2560x1440); the real io (InputScreenIO) maps them to
; the Roblox client through Screen (CoordMode Mouse Screen). Keyboard +
; mouse only.
;
; ROUTE FORMAT (data/routes.json, Task 8+)
;   A route is an Array of steps, or {"steps": [...]}. A step is either
;     {"key": "w", "action": "down", "ms": 4150}    object form
;     ["w", "down", 4150]                            compact form
;     {"action": "wait", "ms": 300} / ["wait", 300]  pure wait
;     ["look", dx, dy, ms]  camera: relative mouse move (raw mickeys, the
;                           recorder takes them while the right mouse
;                           button is held), then wait ms
;     ["zoom", n, ms]       camera: n wheel notches (n > 0 in / up,
;                           n < 0 out / down, never 0), then wait ms
;     object forms: {"action": "look", "dx", "dy", "ms"} /
;                   {"action": "zoom", "n", "ms"}
;   action:
;     down  press key, then wait ms
;     up    release key, then wait ms
;     tap   press key, hold ms, release (no extra wait)
;     wait  wait ms
;     look / zoom   see above (io.Look(dx, dy) / io.Wheel(dir, n, 25))
;   key: AHK key name, letters/digits/underscore only (w, Space, LShift, e).
;   ms: Integer >= 0.
;   Steps are validated before any key is pressed (ValueError on bad data).
;
; TIMING: with a backend that has Now() (the real one) a route is played on
; ONE timeline: each step happens at start + (sum of the ms before it), so
; the time a key press or a wait takes never adds up along the route (it
; used to: every Sleep overshot by up to a 15.6 ms timer tick, and routes
; full of short taps and arrow-key camera turns ran long). The Windows timer
; runs at 1 ms while a route plays (Input.HiRes) and Wait spins the last
; few ms. Input.LastRouteMs = how long the last route really took.
;
; STOP RULE: ctx.ShouldStop() is checked before every step and every 50 ms
; while waiting. On stop, error, or route end, every key the route still
; holds is released. PlayRoute never leaves a key held down. Every pressed
; key is also tracked in Input._held; Input.ReleaseAll() runs via OnExit
; (auto-registered) so ExitApp/Reload mid-route also lifts W/A.
;
; IO BACKEND: all side effects go through an io object with
;   Down(k) Up(k) MoveTo(x, y) ClickHere() Wait(ms, ctx := "") -> bool
;   Wheel(dir, n := 1, gapMs := 25)   (only the zoom/camera code calls it)
;   Type(text) or Text(s)              (Input.TypeText only; literal SendText)
;   Ocr(x, y, w, h [, scale]) -> String  optional; when present ResetToSpawn
;                                      checks the screen after each step
;   Shot() -> png path or ""           optional; debug screenshot (Sell)
;   MouseAt(x, y) MousePos() -> {x, y} KeyEvent(keys)
;                                      optional; Input.ShiftLock only (absolute
;                                      move, no nudge; SendEvent)
;   GrabScreen(sx, sy, w, h) -> Array  optional; colours of a SCREEN px rect
;                                      (ChatGuard reads Roblox's fixed-size
;                                      chat button; without it the chat is
;                                      never hidden)
; Input._io is the real one (InputScreenIO); tests pass a recorder.
;
;   Input.TypeText(s, io, gap)   types literal text (SendText) one char per
;                                io call, io.Wait(gap) between (default
;                                Input.TypeGapMs = 80); printable chars
;                                only, else ValueError (nothing sent)
;   Input.Combo(mods, k, io)     e.g. Combo(["Ctrl"], "a"): mods down in
;                                order, tap k, mods up in reverse (always)
; ---------------------------------------------------------------------------

class InputScreenIO {
    ; Callers give DESIGN coords (2560x1440); the real mouse gets Screen's
    ; mapping to the Roblox client (unchanged at 2560x1440). Unmap: back.
    static Map(x, y) => Screen.Pt(x, y)
    static Unmap(x, y) => Screen.Inv(x, y)
    Down(k) {
        SendInput("{" k " down}")
    }
    Up(k) {
        SendInput("{" k " up}")
    }
    MoveTo(x, y) {
        p := InputScreenIO.Map(x, y)
        CoordMode("Mouse", "Screen")
        MouseMove(p.x, p.y, 0)
        ; 1 px nudge so Roblox registers the hover before a click.
        MouseMove(1, 0, 0, "R")
        MouseMove(-1, 0, 0, "R")
    }
    ClickHere() {
        Click("Down")
        Sleep(20)
        Click("Up")
    }
    ; n wheel notches ("up" | "down") at the current mouse position,
    ; gapMs apart. Tasks call this in short chunks so they can check stop.
    Wheel(dir, n := 1, gapMs := 25) {
        key := (StrLower(dir) = "up") ? "WheelUp" : "WheelDown"
        Loop n {
            Click(key)
            if (gapMs > 0)
                Sleep(gapMs)
        }
    }
    ; Relative mouse move (mouse_event MOUSEEVENTF_MOVE): Roblox turns the
    ; camera from these raw deltas while the right button is held.
    Look(dx, dy) {
        DllCall("mouse_event", "UInt", 0x0001, "Int", dx, "Int", dy, "UInt", 0, "UPtr", 0)
    }
    ; Screen text in a rect ("" on any failure). scale 1..4 upscales first.
    Ocr(x, y, w, h, scale := 1) => Ocr.Read(x, y, w, h, scale)
    ; PNG of the Roblox window in A_Temp (Screenshot.Capture) -> path or "".
    Shot() => Screenshot.Capture(WinExist("ahk_exe RobloxPlayerBeta.exe"))
    ; Shift lock probe (Input.ShiftLockOn): a plain absolute move (no nudge,
    ; no click) and where the cursor is now.
    MouseAt(x, y) {
        p := InputScreenIO.Map(x, y)
        CoordMode("Mouse", "Screen")
        MouseMove(p.x, p.y, 0)
    }
    MousePos() {
        CoordMode("Mouse", "Screen")
        MouseGetPos(&x, &y)
        return InputScreenIO.Unmap(x, y)
    }
    ; SendEvent (live 2026-11-02: Roblox's shift lock took Left Shift's scan
    ; code this way, not a plain {Shift}).
    KeyEvent(keys) {
        SendEvent(keys)
    }
    ; Colours of a SCREEN px rect (not design px: Roblox's own top bar and
    ; chat keep their pixel size at every resolution; ChatGuard) -> Array
    ; of w*h 0xRRGGBB, or "".
    GrabScreen(sx, sy, w, h) => Pixel._ScreenGrab(sx, sy, w, h)
    ; First text line matching re in a DESIGN rect -> {x, y, text} (SCREEN
    ; px of its centre) or "" (Ocr.FindText).
    FindText(x, y, w, h, re, scale := 1) => Ocr.FindText(x, y, w, h, re, scale)
    ; ... the matching words' centre (Ocr.FindWord), in DESIGN px
    FindWord(x, y, w, h, re, wordRe, scale := 1) => Ocr.FindWord(x, y, w, h, re, wordRe, scale)
    ; Types literal text (SendText: no hotkey/modifier parsing).
    Type(text) {
        SendText(text)
    }
    Text(s) {
        SendText(s)
    }
    ; High-resolution clock in ms (QueryPerformanceCounter).
    Now() => Input.NowMs()
    ; Sleeps ms in slices of at most 50 ms on the precise clock; the last
    ; few ms are spun (Sleep -1 still handles messages, so F3 works) because
    ; a Sleep can overshoot by a whole timer tick. -> false as soon as
    ; ctx.ShouldStop().
    Wait(ms, ctx := "") {
        deadline := Input.NowMs() + ms
        Loop {
            if (IsObject(ctx) && ctx.ShouldStop())
                return false
            left := deadline - Input.NowMs()
            if (left <= 0)
                return true
            ; AHK's Sleep rounds to its own ~10 ms message timer; with the 1 ms
            ; Windows timer on (Input.HiRes), kernel32 Sleep is precise
            ; (slices <= 50 ms, so F3 still gets through between them)
            if (Input._hiRes > 0 && left > 2)
                DllCall("Sleep", "UInt", Min(50, Floor(left - 2)))
            else if (left > 16)
                Sleep(Min(50, Floor(left - 16)))
            else
                Sleep(-1)
        }
    }
}

class Input {
    static _io := InputScreenIO()
    static TapHoldMs := 50
    static ClickSettleMs := 30
    static Actions := Map("down", true, "up", true, "tap", true, "wait", true, "look", true, "zoom", true)
    static LookMax := 100000      ; |dx|, |dy| per look step
    static ZoomMax := 200         ; |n| per zoom step

    ; FishSol 1440p reset values (RunForcedRespawnAction, 1440p branch):
    ; Esc, R, Enter with the waits below, then two clicks (open the left
    ; side menu, close it) each with 220 ms before and after.
    static ResetCoords := Map(
        "menuOpen", [52, 621],
        "menuClose", [525, 158]
    )
    static ResetTiming := Map(
        "afterEsc", 650,
        "afterR", 650,
        "afterEnter", 2600,
        "aroundClick", 220
    )
    ; A hunt's reset and re-aim (QuickReset, QuickAim): every step and check
    ; of the plain ones, shorter waits, biomes last ~120 s. A wait cut too
    ; far costs a retry, nothing is left open: R before the menu is up -> no
    ; prompt, the retry's menu check; Enter before the prompt takes it ->
    ; _Settle; a click lost -> _ClickUntil's next try. afterEnter: at most,
    ; the respawn's log lines end it (live: ~1.7 s after Enter, L34..L38, 63
    ; resets) and afterLine after them; poll: _See's reads. GUESSED: afterEsc,
    ; afterR, aroundClick. afterLine: deaths' clicks landed ~0.2 s after the
    ; lines (L34..L37).
    static ResetQuick := Map(
        "afterEsc", 400,
        "afterR", 200,
        "afterEnter", 2600,
        "aroundClick", 100,
        "afterLine", 300,
        "poll", 100
    )
    static _quick := false
    static _settled := ""
    ; Keys and clicks sent through Input so far: the same count later = nothing
    ; moved the player or opened a menu since (MinionsTask._StillAtSpawn).
    static Sent := 0

    static Click(x, y, io := "") {
        io := Input._Backend(io)
        ChatGuard.ClearFor(io, "", [x, y])       ; the chat over it (below 1440p): hidden first
        Input.Sent++
        io.MoveTo(x, y)
        io.Wait(Input.ClickSettleMs)
        io.ClickHere()
    }

    ; Gap between typed characters. Roblox drops characters from one fast
    ; SendText ("Potion" -> "Potin"); one char per call 80 ms apart was
    ; reliable 15/15 in the 2026-10-25 recon.
    static TypeGapMs := 80

    ; Types literal text through the io backend (SendText: no hotkey
    ; syntax), ONE CHARACTER PER CALL with io.Wait(gapMs) between characters
    ; (gapMs "" = Input.TypeGapMs; 0 = no waits). Used for the cauldron
    ; search, fisher qty and inventory search/amount boxes.
    ; String or Integer; "" types nothing. Printable chars only, <= 100 long,
    ; else ValueError (nothing sent). Backend needs Type() or Text(), else Error.
    static TypeText(text, io := "", gapMs := "") {
        if (Type(text) != "String" && Type(text) != "Integer")
            throw ValueError("Input.TypeText: text must be a string")
        s := String(text)
        if (s = "")
            return
        if (StrLen(s) > 100 || RegExMatch(s, "[\x00-\x1F\x7F]"))
            throw ValueError("Input.TypeText: bad text")
        gap := (gapMs = "") ? Input.TypeGapMs : gapMs
        if !(IsInteger(gap) && gap >= 0)
            throw ValueError("Input.TypeText: bad gap")
        io := Input._Backend(io)
        if HasMethod(io, "Type")
            put := (c) => io.Type(c)
        else if HasMethod(io, "Text")
            put := (c) => io.Text(c)
        else
            throw Error("Input.TypeText: io backend has no Type()/Text()")
        n := StrLen(s)
        Loop Parse s {
            put(A_LoopField)
            if (A_Index < n && gap > 0)
                io.Wait(gap)
        }
    }

    ; Empties the focused Roblox text box: End, then ClearKeys Backspaces.
    ; Roblox search boxes ignore Ctrl+A and keep their text between opens
    ; (clip 2026-10-27 20:17: "Sailor" typed again made "SailoSailor").
    static ClearKeys := 40
    static ClearText(io := "", n := "") {
        io := Input._Backend(io)
        Input.Key("End", 30, io)
        Loop (n = "") ? Input.ClearKeys : n
            Input.Key("Backspace", 20, io)
    }

    ; Mouse wheel through the io backend. dir = "up" | "down".
    static Wheel(dir, n := 1, io := "") {
        if (StrLower(dir) != "up" && StrLower(dir) != "down")
            throw ValueError("Input.Wheel: dir must be up or down")
        Input._Backend(io).Wheel(dir, n)
    }

    static Key(k, holdMs := 50, io := "") {
        Input._CheckKey(k, "Input.Key")
        io := Input._Backend(io)
        try {
            Input._Press(k, io)
            if (holdMs > 0)
                io.Wait(holdMs)
        } finally {
            Input._Release(k, io)
        }
    }

    ; Modifier combo: mods pressed in order, k tapped, mods released in
    ; reverse (also on error).
    static Combo(mods, k, holdMs := 50, io := "") {
        if !(mods is Array)
            throw ValueError("Input.Combo: mods must be an Array")
        for m in mods
            Input._CheckKey(m, "Input.Combo")
        Input._CheckKey(k, "Input.Combo")
        io := Input._Backend(io)
        down := []
        try {
            for m in mods {
                down.Push(m)
                Input._Press(m, io)
            }
            Input.Key(k, holdMs, io)
        } finally {
            Loop down.Length {
                try Input._Release(down[down.Length - A_Index + 1], io)
            }
        }
    }

    ; Plays a route (Array, {"steps"} Map, or JSON text). -> true when every
    ; step ran, false when ctx.ShouldStop() cut it short.
    static LastRouteMs := 0
    static _qpf := 0
    static _hiRes := 0

    ; ms on the QueryPerformanceCounter clock (sub-ms precise; A_TickCount
    ; only moves every ~15.6 ms).
    static NowMs() {
        if !Input._qpf {
            f := 0
            DllCall("QueryPerformanceFrequency", "Int64*", &f)
            Input._qpf := f
        }
        c := 0
        DllCall("QueryPerformanceCounter", "Int64*", &c)
        return c * 1000.0 / Input._qpf
    }

    ; 1 ms Windows timer resolution while on (counted, so nested users are
    ; fine). Used while a route is recorded or played.
    ; Windows 11 ignores timeBeginPeriod from a process whose windows are
    ; all hidden or covered (fullscreen Roblox in front): the Waits then
    ; overshot ~8 ms (2026-11-11, 1920x1080 fullscreen). The process opts out
    ; of that throttling once (ProcessPowerThrottling,
    ; PROCESS_POWER_THROTTLING_IGNORE_TIMER_RESOLUTION; this process only,
    ; no system setting). Older Windows: the call fails, nothing changes.
    static _timerOptOut := false
    static HiRes(on) {
        if (on && !Input._timerOptOut) {
            Input._timerOptOut := true
            st := Buffer(12, 0)
            NumPut("UInt", 1, st, 0)                  ; Version
            NumPut("UInt", 0x4, st, 4)                ; ControlMask: IGNORE_TIMER_RESOLUTION
            NumPut("UInt", 0, st, 8)                  ; StateMask 0: always honour the request
            try DllCall("SetProcessInformation", "Ptr", DllCall("GetCurrentProcess", "Ptr"), "Int", 4, "Ptr", st, "UInt", 12)
        }
        if on {
            if (Input._hiRes++ = 0)
                DllCall("winmm\timeBeginPeriod", "UInt", 1)
        } else if (Input._hiRes > 0) {
            if (--Input._hiRes = 0)
                DllCall("winmm\timeEndPeriod", "UInt", 1)
        }
    }

    ; True while a route plays (InRoute): checks that run on the App's tick
    ; meanwhile (CanRun) must skip slow screen reads, or the walk freezes with
    ; a key held and overshoots (2026-10-27 review: the disconnect and craft
    ; notification OCR ran inside CanRun every tick).
    static InRoute := false

    static PlayRoute(steps, ctx, io := "") {
        steps := Input.ParseRoute(steps)
        io := Input._Backend(io)
        held := Map()   ; lowercased key -> key as sent (this route's keys)
        timeline := HasMethod(io, "Now")       ; real backend: one timeline (TIMING)
        t0 := 0, due := 0
        ; wait until the step's place on the timeline (or ms without one)
        WaitFor(ms) {
            if (ms <= 0)
                return true
            if !timeline
                return io.Wait(ms, ctx)
            due += ms
            left := Round(due - (io.Now() - t0))
            return (left <= 0) ? true : io.Wait(left, ctx)
        }
        if timeline {
            Input.HiRes(true)
            t0 := io.Now()
        }
        outer := Input.InRoute
        Input.InRoute := true
        try {
            for s in steps {
                if (IsObject(ctx) && ctx.ShouldStop())
                    return false
                k := s.key
                switch s.action {
                    case "down":
                        held[StrLower(k)] := k      ; register before pressing
                        Input._Press(k, io)
                    case "up":
                        if held.Has(StrLower(k))
                            held.Delete(StrLower(k))
                        Input._Release(k, io)
                    case "tap":
                        held[StrLower(k)] := k
                        Input._Press(k, io)
                        if !WaitFor(s.ms)
                            return false
                        held.Delete(StrLower(k))
                        Input._Release(k, io)
                        continue
                    case "look":
                        if !HasMethod(io, "Look")
                            throw Error("Input.PlayRoute: io backend has no Look()")
                        io.Look(s.dx, s.dy)
                    case "zoom":
                        io.Wheel(s.n > 0 ? "up" : "down", Abs(s.n), 25)
                }
                if !WaitFor(s.ms)
                    return false
            }
            return true
        } finally {
            Input.InRoute := outer
            for , k in held {
                try Input._Release(k, io)
            }
            if timeline {
                Input.LastRouteMs := Round(io.Now() - t0)
                Input.HiRes(false)
            }
        }
    }

    ; ---- held-key registry ---------------------------------------------
    ; Every key pressed through Input is recorded here BEFORE io.Down and
    ; removed BEFORE io.Up, so a key is never down without an entry.
    ; `finally` does not run on ExitApp/Reload, so ReleaseAll is registered
    ; with OnExit the first time the Input class is touched (_exitHooked).
    ; The app may also call Input.ReleaseAll() itself (e.g. on F3).
    static _held := Map()       ; lowercased key -> {key, io}
    static _exitHooked := Input._HookExit()

    ; Releases every key still in the registry (through the io that pressed
    ; it, unless io is given) and empties it. Never throws.
    static ReleaseAll(io := "") {
        pending := []
        for , e in Input._held
            pending.Push(e)
        Input._held := Map()
        for e in pending {
            try (IsObject(io) ? io : e.io).Up(e.key)
        }
    }

    static _Press(k, io) {
        Input.Sent++
        Input._held[StrLower(k)] := {key: k, io: io}
        io.Down(k)
    }

    static _Release(k, io) {
        lk := StrLower(k)
        if Input._held.Has(lk)
            Input._held.Delete(lk)
        io.Up(k)
    }

    static _HookExit() {
        OnExit((*) => (Input.ReleaseAll(), 0))
        return true
    }

    ; Screen checks for ResetToSpawn (2560x1440 screen px; OCR text holds
    ; `text`, case-insensitive). Read 2026-10-25 in game.
    ;   prompt      Esc + R opens "Are you sure you want to respawn your
    ;               character?"
    ;   collection  the Aura Collections screen ("[Exit]" top left, the chat
    ;               overlaps the title). Opening and closing it re-aims the
    ;               camera; without that a camera the player turned sends
    ;               every timed route the wrong way.
    ;   menu        the Roblox menu itself (its "Resume" button), read over the
    ;               middle of the screen: Esc toggles the menu, so a try that
    ;               failed may have left it open
    ;   prompt.alt  the prompt's buttons ("Respawn" / "Don't Respawn"), read
    ;               when the question does not: an aura's big title behind
    ;               it (Eden's "The Void Contractor / Eden") garbles the
    ;               question ("Are you sure ou want spaw o r character?",
    ;               loop L19 2026-11-03: 9 respawns failed, the prompt left
    ;               open over the next storage swap); the buttons read on
    ;               every real frame (tests\screens\respawn_prompt_*)
    ;   collection.marks  more of the Collections screen, each read on its
    ;               own (loop L19 05:19 / 05:21: the chat, back after a
    ;               respawn, lay over the title and the wide read lost
    ;               "[Exit]"; ReAim clicked its open button 3 times INTO the
    ;               open screen and left it open): "[Exit]" alone (a tight
    ;               box right of the chat), "Replay Cutscene" (bottom left),
    ;               "Hide UI" (bottom right). Any one = the screen is up;
    ;               gone = none reads. Its close click only when "[Exit]"
    ;               itself reads (title or tight box: _ExitSeen). Real
    ;               frames: tests\screens\collections_*
    static ResetChecks := Map(
        "prompt", {x: 900, y: 500, w: 800, h: 80, text: "respawn", alt: {x: 1050, y: 625, w: 460, h: 80}
            ; Roblox draws this prompt itself and it does not scale like the
            ; game's UI: at 1366x768 the question sat at y 246, the buttons at
            ; 369 (client px), out of both boxes (live 2026-11-11). Below 1440p
            ; only: one wide box from just right of the chat (x >= 490 px at
            ; 768p, so its "[Respawn]: You can reset" line is never read)
            , wide: {x: 920, y: 250, w: 1100, h: 700}},
        "collection", {x: 60, y: 115, w: 560, h: 75, text: "exit", marks: [
            {x: 455, y: 120, w: 130, h: 65, text: "exit"},
            {x: 560, y: 1305, w: 420, h: 80, text: "cutscene"},
            {x: 2140, y: 1370, w: 410, h: 70, text: "hide"}]},
        "menu", {x: 400, y: 150, w: 1760, h: 1200, text: "resume"}
    )
    static ResetTries := 3        ; attempts per checked step
    static ResetRetryMs := 1500   ; before another try: the game allows a reset about once a second
    static ResetSeeMs := 1500     ; how long one attempt waits for its screen
    static ResetPollMs := 250
    static LastResetError := ""   ; why the last ResetToSpawn returned false ("" = stopped/ok)

    ; Camera set-up a route needs right after the respawn (whose Aura
    ; Collections step leaves the camera at a fixed angle), as route steps.
    ; "limbo_eden": TOP-DOWN, right button held and the mouse moved down
    ; until Roblox's camera pitch stops at its limit (overshooting is
    ; harmless), so THE LIMBO's dark islands are seen from above; the yaw
    ; the respawn set is kept (no dx). Recording, Test and playback all add
    ; the same steps, so a route always starts from the same view.
    static TopDownLooks := 8
    static TopDownDy := 300
    static CameraSteps(name) {
        out := []
        if (name = "limbo_eden") {
            out.Push(["RButton", "down", 50])
            Loop Input.TopDownLooks
                out.Push(["look", 0, Input.TopDownDy, 15])
            out.Push(["RButton", "up", 150])
        }
        return out
    }

    ; CameraSteps(name) followed by the route's own steps.
    static WithCamera(name, steps) {
        out := Input.CameraSteps(name)
        for s in Input.RouteList(steps)
            out.Push(s)
        return out
    }

    ; A route value ({"steps": [...]} or the bare Array) -> its step Array.
    static RouteList(r) => (r is Map && r.Has("steps")) ? r["steps"] : (r is Array ? r : [])

    ; Routes that start WITHOUT a respawn: THE LIMBO has no working reset
    ; (Esc + R there never respawns, 2026-10-26), so limbo_eden starts where
    ; the Portable Crack puts the player and only the camera is re-aimed
    ; (Input.ReAim) before it.
    ; fisher_to_fishing starts at Captain Flarg (the sell walks there first):
    ; recording / testing it re-aims the camera where you stand.
    static NoRespawn := Map("limbo_eden", true, "fisher_to_fishing", true)

    ; Esc, R, Enter, then open + close Aura Collections (FishSol 1440p
    ; clicks). With io.Ocr each step is checked on screen and retried
    ; (Input.ResetTries): Esc + R must show the respawn prompt, the
    ; Collections screen must open and then close. Esc TOGGLES the Roblox
    ; menu, so before another try the menu is looked for: already open -> only
    ; R (another Esc would close it again: reset, menu, reset, menu...). A
    ; reset that gives up closes the menu it may have left open. Without
    ; io.Ocr (test recorders) or with blind = true the sequence is sent
    ; without checks.
    ; -> false if stopped or a check failed (Input.LastResetError says which).
    static ResetToSpawn(ctx := "", io := "", blind := false) {
        io := Input._Backend(io)
        Input.LastResetError := ""
        if (blind || !HasMethod(io, "Ocr"))
            return Input._ResetBlind(ctx, io)
        t := Input._Timing()
        seen := 0
        Loop Input.ResetTries {
            keys := [["Esc", t["afterEsc"]], ["r", t["afterR"]]]
            if (A_Index > 1) {
                if !io.Wait(Input.ResetRetryMs, ctx)
                    return false
                if Input._Has(io, "menu")
                    keys := [["r", t["afterR"]]]        ; the menu is open: Esc would close it
            }
            for pair in keys {
                if (IsObject(ctx) && ctx.ShouldStop())
                    return false
                Input.Key(pair[1], Input.TapHoldMs, io)
                if !io.Wait(pair[2], ctx)
                    return false
            }
            seen := Input._See(io, ctx, "prompt", true)
            if (seen != 0)
                break
        }
        if (seen < 0)
            return false
        if (seen = 0) {
            ; do not leave the menu (or a prompt read only now) open
            if (Input._Has(io, "menu") || Input._Has(io, "prompt")) {
                Input.Key("Esc", Input.TapHoldMs, io)
                io.Wait(t["afterEsc"], ctx)
            }
            Input.LastResetError := "respawn prompt never showed after Esc + R"
            return false
        }
        if (IsObject(ctx) && ctx.ShouldStop())
            return false
        Input.Key("Enter", Input.TapHoldMs, io)
        if !Input._Settle(io, ctx, t)
            return false
        return Input.ReAim(ctx, io)
    }

    static _Timing() => Input._quick ? Input.ResetQuick : Input.ResetTiming

    ; ResetToSpawn with ResetQuick's waits. settled: fn -> true once the
    ; respawn shows in Roblox's log ("" = afterEnter in full). No screen
    ; checks (no io.Ocr): the plain waits, nothing would catch a miss.
    static QuickReset(ctx := "", io := "", settled := "") {
        Input._quick := HasMethod(Input._Backend(io), "Ocr"), Input._settled := settled
        try
            return Input.ResetToSpawn(ctx, io)
        finally
            Input._quick := false, Input._settled := ""
    }

    ; ReAim with ResetQuick's waits (the same rule).
    static QuickAim(ctx := "", io := "") {
        Input._quick := HasMethod(Input._Backend(io), "Ocr")
        try
            return Input.ReAim(ctx, io)
        finally
            Input._quick := false
    }

    ; After the reset's Enter: the wait for the respawn. Quick: over at the
    ; log's lines; none by afterEnter and the prompt still up (the Enter came
    ; too soon for it) -> Enter again, afterEnter once more. -> false if stopped.
    static _Settle(io, ctx, t) {
        f := Input._settled
        if !(Input._quick && IsObject(f)) {
            if !io.Wait(t["afterEnter"], ctx)
                return false
        } else {
            left := t["afterEnter"]
            Loop {
                if f()
                    return io.Wait(t["afterLine"], ctx)
                if (left <= 0)
                    break
                if !io.Wait(50, ctx)
                    return false
                left -= 50
            }
        }
        if (!Input._quick || !Input._Has(io, "prompt"))
            return true
        if (IsObject(ctx) && ctx.ShouldStop())
            return false
        Input.Key("Enter", Input.TapHoldMs, io)
        return io.Wait(t["afterEnter"], ctx)
    }

    ; Only the camera part of ResetToSpawn: open + close Aura Collections,
    ; which leaves the camera at a fixed angle (no respawn, works in THE
    ; LIMBO). Checked with io.Ocr like ResetToSpawn. -> false if stopped or a
    ; check failed.
    static ReAim(ctx := "", io := "", blind := false) {
        io := Input._Backend(io)
        Input.LastResetError := ""
        ; below 1440p the chat lies over the close (and its "[Exit]"): hidden
        ; first, shown again after the task (ChatGuard, App._Tidy)
        if (ChatGuard.ClearFor(io, ctx, Input.ResetCoords["menuOpen"], Input.ResetCoords["menuClose"]) < 0)
            return false
        if (blind || !HasMethod(io, "Ocr")) {
            for name in ["menuOpen", "menuClose"]
                if (Input._ClickPoint(io, ctx, name) <= 0)
                    return false
            return true
        }
        r := Input._ClickUntil(io, ctx, "menuOpen", true)
        if (r <= 0) {
            if (r = 0 && Input.LastResetError = "")     ; else ClickGuard's reason
                Input.LastResetError := "Aura Collections did not open (camera not re-aimed)"
            return false
        }
        r := Input._ClickUntil(io, ctx, "menuClose", false)
        if (r <= 0) {
            if (r = 0 && Input.LastResetError = "")
                Input.LastResetError := "Aura Collections did not close"
            return false
        }
        return true
    }

    ; The original FishSol sequence, no screen checks. -> false if stopped.
    static _ResetBlind(ctx, io) {
        t := Input.ResetTiming
        for pair in [["Esc", t["afterEsc"]], ["r", t["afterR"]], ["Enter", t["afterEnter"]]] {
            if (IsObject(ctx) && ctx.ShouldStop())
                return false
            Input.Key(pair[1], Input.TapHoldMs, io)
            if !io.Wait(pair[2], ctx)
                return false
        }
        return Input.ReAim(ctx, io, true)
    }

    ; One click on ResetCoords[name], ClickGuard first. -> 1 clicked | 0
    ; refused (shift lock stuck on, no click) | -1 stopped
    static _ClickPoint(io, ctx, name, at := "") {
        pt := IsObject(at) ? [at.x, at.y] : Input.ResetCoords[name]
        t := Input._Timing()
        if (IsObject(ctx) && ctx.ShouldStop())
            return -1
        g := Input.ClickGuard(io, ctx, "the " name " click")
        if (g <= 0)
            return g
        io.MoveTo(pt[1], pt[2])
        if !io.Wait(t["aroundClick"], ctx)
            return -1
        Input.Sent++
        io.ClickHere()
        return io.Wait(t["aroundClick"], ctx) ? 1 : -1
    }

    ; The Aura Collections screen left open (a run killed mid camera-reset,
    ; live 2026-11-02) covers the aura storage and the inventory: every aura
    ; search then read an empty first tile. Looked for once (one read) and
    ; closed with ReAim's close click. ocr = fn(x, y, w, h) for an io without
    ; Ocr (a task's env.ocrFn). -> 1 was open, closed | 0 not open | 2 still
    ; open after Input.ResetTries clicks | -1 stopped
    ; The Aura Collections screen shows (one read, its "[Exit]"). ocr as
    ; CloseCollections. Nothing to read with -> false.
    static CollectionsUp(io := "", ocr := "") {
        io := Input._Backend(io)
        if (!IsObject(ocr) && !HasMethod(io, "Ocr"))
            return false
        return Input._Has(io, "collection", ocr)
    }

    static CloseCollections(ctx, io := "", ocr := "") {
        io := Input._Backend(io)
        if !Input._Has(io, "collection", ocr)
            return 0
        if (ChatGuard.ClearFor(io, ctx, Input.ResetCoords["menuClose"]) < 0)
            return -1
        r := Input._ClickUntil(io, ctx, "menuClose", false, ocr)
        return (r = 0) ? 2 : r
    }

    ; SHIFT LOCK (live 2026-11-02, Roblox setting Shift Lock Switch on): Left
    ; Shift's scan code (ShiftKey, held ShiftHoldMs, through io.KeyEvent)
    ; toggles it. While it is on the character faces where the camera looks
    ; and Roblox pins the cursor to the screen centre (ShiftCentre, 2560x1440):
    ; a move to ShiftProbe comes back there within ShiftSettleMs. The mouse
    ; then cannot be used on any UI, so it must be off for every click.
    ; A not-pinned read does NOT prove it off: a game screen that frees the
    ; cursor hides it (live 2026-11-03 18:28: the "Snowy Breakthrough" page
    ; over the game read off with the lock on; the Collections open click
    ; landed, Collections took the page's place and pinned the cursor again,
    ; and its close click went to the centre). So ClickGuard looks again
    ; right before every UI click.
    static ShiftKey := "sc02A"
    static ShiftHoldMs := 120
    static ShiftProbe := [900, 400]
    static ShiftCentre := [1280, 720]
    static ShiftTol := 4          ; px from the centre still pinned
    static ShiftSettleMs := 150
    static ShiftTries := 2        ; toggles at most (one retry)
    static FirstPersonOut := 15   ; wheel-down notches when Shift cannot free the cursor

    ; The io has the hooks (MouseAt, MousePos, KeyEvent).
    static CanShiftLock(io := "") {
        io := Input._Backend(io)
        return HasMethod(io, "MouseAt") && HasMethod(io, "MousePos") && HasMethod(io, "KeyEvent")
    }

    ; Shift lock on now? One probe: the cursor moved to ShiftProbe, then
    ; read. -> 1 on (pinned to the centre) | 0 off | -1 stopped or no hooks
    ; (nothing sent)
    static ShiftLockOn(io := "", ctx := "") {
        io := Input._Backend(io)
        if (!Input.CanShiftLock(io) || (IsObject(ctx) && ctx.ShouldStop()))
            return -1
        io.MouseAt(Input.ShiftProbe[1], Input.ShiftProbe[2])
        if !io.Wait(Input.ShiftSettleMs, ctx)
            return -1
        p := io.MousePos()
        c := Input.ShiftCentre
        return (Abs(p.x - c[1]) <= Input.ShiftTol && Abs(p.y - c[2]) <= Input.ShiftTol) ? 1 : 0
    }

    ; Shift lock to `on` (true / false): detected, toggled only when it
    ; differs, detected again (ShiftTries toggles at most). -> true when the
    ; state matches afterwards; false when it did not, when stopped, or the
    ; io has no hooks. Never clicks.
    static ShiftLock(on, io := "", ctx := "") {
        io := Input._Backend(io)
        want := on ? 1 : 0
        Loop Input.ShiftTries {
            s := Input.ShiftLockOn(io, ctx)
            if (s < 0)
                return false
            if (s = want)
                return true
            Input._ShiftTap(io)
        }
        s := Input.ShiftLockOn(io, ctx)
        ; still pinned after the toggles: first person (the camera zoomed all
        ; the way in) pins the cursor too and Shift cannot free it (live
        ; 2026-11-10 04:09: every task skipped for 10 min) -> zoom out
        if (!on && s = 1 && HasMethod(io, "Wheel")) {
            io.Wheel("down", Input.FirstPersonOut, 25)
            if !io.Wait(Input.ShiftSettleMs, ctx)
                return false
            s := Input.ShiftLockOn(io, ctx)
            if (s = 1) {                         ; zoomed out, now shift lock itself
                Input._ShiftTap(io)
                s := Input.ShiftLockOn(io, ctx)
            }
            if (s = 0)
                Input._Log("input: the camera was in first person (cursor pinned) - zoomed out")
        }
        return s = want
    }

    ; Right before a UI click (what: for the log): shift lock looked for and
    ; turned off when on, logged, so a click is never spent on a pinned
    ; cursor. An io without the hooks has no probe. Not off afterwards:
    ; logged, LastResetError says so, and the caller must not click.
    ; -> 1 click | 0 refused | -1 stopped
    static ClickGuard(io, ctx, what) {
        io := Input._Backend(io)
        if !Input.CanShiftLock(io)
            return 1
        s := Input.ShiftLockOn(io, ctx)
        if (s <= 0)
            return s ? -1 : 1
        if Input.ShiftLock(false, io, ctx) {
            Input._Log("input: shift lock was on before " what " - turned it off")
            return 1
        }
        if (IsObject(ctx) && ctx.ShouldStop())
            return -1
        Input.LastResetError := "shift lock would not turn off: no click"
        Input._Log("input: shift lock would not turn off before " what " - not clicked")
        return 0
    }

    ; Input has no task env: TaskEnv hands it its log (LogFn).
    static LogFn := ""
    static _Log(text) {
        if IsObject(Input.LogFn)
            try (Input.LogFn)(text)
    }

    ; One Left Shift tap by scan code (held-key registry as _Press /
    ; _Release, so ReleaseAll lifts it too). The hold is not cut short.
    static _ShiftTap(io) {
        k := Input.ShiftKey
        Input._held[StrLower(k)] := {key: k, io: io}
        try {
            io.KeyEvent("{" k " down}")
            io.Wait(Input.ShiftHoldMs)
        } finally {
            if Input._held.Has(StrLower(k))
                Input._held.Delete(StrLower(k))
            io.KeyEvent("{" k " up}")
        }
    }

    ; ROBLOX PURCHASE PROMPT (live 2026-11-02 09:20): a click on an empty aura
    ; tile went through the storage into the world, hit a Donation board and
    ; opened "Buy Robux and item: R$1,000 Donation - Buy $4.99". One more
    ; click there can spend real money. So it is looked for over the middle
    ; of the screen (PurchaseBox, 2560x1440) and closed with Esc only: no
    ; code path ever clicks on it. Not the shops' own "Purchase for N Coins"
    ; (Mari / Jester): PurchaseRe holds only Roblox's own wording.
    static PurchaseBox := {x: 680, y: 320, w: 1200, h: 800}
    static PurchaseRe := "i)buy\s*r[o0]bux|r[o0]bux\s*and\s*item|payment\s*meth[o0]d|be\s*charged|balance\s*after|would\s*y[o0]u\s*like\s*t[o0]\s*buy|buy\s*\$\s*\d"
    static PurchaseTries := 3     ; Esc presses before giving up
    static PurchaseMs := 500      ; after each Esc

    ; A Roblox purchase prompt reads in PurchaseBox (one read). ocr = fn(x,
    ; y, w, h) for an io without Ocr; neither -> false (nothing to read with).
    static PurchaseUp(io := "", ocr := "") {
        io := Input._Backend(io)
        if (!IsObject(ocr) && !HasMethod(io, "Ocr"))
            return false
        return RegExMatch(Input._Read(io, Input.PurchaseBox, ocr), Input.PurchaseRe) > 0
    }

    ; Closes a Roblox purchase prompt with Esc (never a click), even when the
    ; task is told to stop. -> 0 none | 1 was up, closed | 2 still up after
    ; PurchaseTries Esc presses
    static ClosePurchase(io := "", ocr := "") {
        io := Input._Backend(io)
        if !Input.PurchaseUp(io, ocr)
            return 0
        Loop Input.PurchaseTries {
            Input.Key("Esc", Input.TapHoldMs, io)
            io.Wait(Input.PurchaseMs)
            if !Input.PurchaseUp(io, ocr)
                return 1
        }
        return 2
    }

    ; DAILY REWARDS POPUP (live 2026-11-03 18:18): it came up after a rejoin
    ; and sat over the storage, so the Eden swap read its "x 10 x 2,000" as
    ; the Equip button. Seen by its title (DailyBox, 2560x1440; real frames
    ; read "noily Rewords" at 1x and 2x, the game font's a as o, D as n or O)
    ; and closed by its X only (sell.dailyReward.close). Its Claim is
    ; SellTask's: never pressed here.
    static DailyBox := {x: 1040, y: 495, w: 480, h: 66}
    static DailyRe := "i)[ao]ily\s*rew[ao]rd"
    static DailyX := [1890, 527]
    static DailyTries := 3        ; clicks on the X before giving up
    static DailyHoverMs := 150    ; on the X before the click (Roblox drops a click right after a move)
    static DailyMs := 500         ; after the click

    ; The popup's title reads (one read). ocr as PurchaseUp.
    static DailyUp(io := "", ocr := "") {
        io := Input._Backend(io)
        if (!IsObject(ocr) && !HasMethod(io, "Ocr"))
            return false
        return RegExMatch(Input._Read(io, Input.DailyBox, ocr), Input.DailyRe) > 0
    }

    ; Closes the popup by its X and checks that it went. A click only with
    ; its title read right then, shift lock off (ClickGuard; on, the click
    ; would land at the screen centre) and no purchase prompt up (those: Esc,
    ; never a click; the caller's).
    ; -> 0 not up | 1 was up, closed | 2 still up (given up or refused) |
    ; -1 stopped
    static CloseDaily(ctx, io := "", ocr := "") {
        io := Input._Backend(io)
        if !Input.DailyUp(io, ocr)
            return 0
        pt := Input.DailyX
        Loop Input.DailyTries {
            if (IsObject(ctx) && ctx.ShouldStop())
                return -1
            g := Input.ClickGuard(io, ctx, "the Daily Rewards X")
            if (g <= 0)
                return g ? -1 : 2
            io.MoveTo(pt[1], pt[2])
            if !io.Wait(Input.DailyHoverMs, ctx)
                return -1
            if Input.PurchaseUp(io, ocr)
                return 2
            if !Input.DailyUp(io, ocr)
                return 1
            io.ClickHere()
            if !io.Wait(Input.DailyMs, ctx)
                return -1
            if !Input.DailyUp(io, ocr)
                return 1
        }
        return 2
    }

    ; THE TITLE SCREEN (live 2026-11-09): Sol's RNG shows it after every join
    ; ("Sol's RNG" logo, "Changelogs" and a big "Play" bottom left); Play
    ; just enters the game (same server, no teleport). Until it is clicked
    ; every reset and every task fails. Seen when BOTH its words read, at
    ; scale 2 (real frame title_play_windy: "Ploy" / "Changelogs"; at 1x
    ; "Rhonaeloqg"); the boxes read nothing in game. Only Play is clicked.
    static TitlePlayBox := {x: 200, y: 1290, w: 320, h: 90}
    static TitlePlayRe := "i)^\W*pl[ao0]y\W*$"
    static TitleLogsBox := {x: 50, y: 1150, w: 500, h: 90}
    static TitleLogsRe := "i)ch[ao]n[gq][e3]\s*l[o0][gq]"
    static TitleScale := 2
    static TitlePlay := [352, 1334]
    static TitleTries := 3        ; clicks on Play before giving up
    static TitleGoneMs := 5000    ; the screen may take this long to go after a click
    static TitlePollMs := 500

    ; A read at `scale`; a reader without the scale argument reads nothing.
    static _ReadAt(io, c, ocr, scale) {
        try return String(IsObject(ocr) ? ocr(c.x, c.y, c.w, c.h, scale) : io.Ocr(c.x, c.y, c.w, c.h, scale))
        return ""
    }

    ; Both its words read (Play first: in game one small read). ocr as PurchaseUp.
    static TitleUp(io := "", ocr := "") {
        io := Input._Backend(io)
        if (!IsObject(ocr) && !HasMethod(io, "Ocr"))
            return false
        s := Input.TitleScale
        return RegExMatch(Input._ReadAt(io, Input.TitlePlayBox, ocr, s), Input.TitlePlayRe) > 0
            && RegExMatch(Input._ReadAt(io, Input.TitleLogsBox, ocr, s), Input.TitleLogsRe) > 0
    }

    ; Clicks Play while the title screen reads, until it is gone. Shift lock
    ; off first (ClickGuard), no purchase prompt up (the caller's: Esc).
    ; -> 0 not up | 1 was up, gone | 2 still up (given up or refused) | -1 stopped
    static ClickPlay(ctx, io := "", ocr := "") {
        io := Input._Backend(io)
        if !Input.TitleUp(io, ocr)
            return 0
        pt := Input.TitlePlay
        Loop Input.TitleTries {
            if (IsObject(ctx) && ctx.ShouldStop())
                return -1
            g := Input.ClickGuard(io, ctx, "the title screen's Play")
            if (g <= 0)
                return g ? -1 : 2
            if Input.PurchaseUp(io, ocr)
                return 2
            io.MoveTo(pt[1], pt[2])
            if !io.Wait(Input.DailyHoverMs, ctx)
                return -1
            io.ClickHere()
            waited := 0
            Loop {
                if !io.Wait(Input.TitlePollMs, ctx)
                    return -1
                waited += Input.TitlePollMs
                if !Input.TitleUp(io, ocr)
                    return 1
                if (waited >= Input.TitleGoneMs)
                    break
            }
        }
        return 2
    }

    ; Clicks point `name` until the Collections screen is shown (want true)
    ; or gone (want false). Never a click inside the screen: the open
    ; button (want true) only while no mark of it reads (it covers that
    ; spot), the close (want false) only on its "[Exit]" read right then
    ; (_ExitSeen; looked for up to ResetSeeMs: the chat fades). A click
    ; ClickGuard refuses ends it at once, not spent as a try. -> 1 done |
    ; 0 gave up or refused | -1 stopped
    static _ClickUntil(io, ctx, name, want, ocr := "") {
        c := Input.ResetChecks["collection"]
        Loop Input.ResetTries {
            if (want && Input._Found(io, c, ocr))
                return 1                                 ; up already: no click on it
            if !want {
                r := Input._SeeExit(io, ctx, ocr)
                if (r <= 0)
                    return r                             ; stopped / no "[Exit]" to click
                if (r = 2)
                    return 1                             ; gone meanwhile
            }
            ; the close below 1440p: where "[Exit]" reads (_ExitAt)
            r := Input._ClickPoint(io, ctx, name, (!want && name = "menuClose") ? Input._ExitAt(io) : "")
            if (r <= 0)
                return r
            r := Input._See(io, ctx, "collection", want, ocr)
            if (r != 0)
                return r
        }
        return 0
    }

    ; Polls for the Collections screen's "[Exit]" up to ResetSeeMs. -> 1 it
    ; reads | 2 the screen is gone (no mark) | 0 up without a readable
    ; "[Exit]" | -1 stopped
    static _PollMs() => Input._quick ? Input.ResetQuick["poll"] : Input.ResetPollMs

    static _SeeExit(io, ctx, ocr := "") {
        waited := 0
        Loop {
            if Input._ExitSeen(io, ocr)
                return 1
            if !Input._Found(io, Input.ResetChecks["collection"], ocr)
                return 2
            if (waited >= Input.ResetSeeMs)
                return 0
            if !io.Wait(Input._PollMs(), ctx)
                return -1
            waited += Input._PollMs()
        }
    }

    ; Check `name`'s text on screen right now (one read).
    static _Has(io, name, ocr := "") => Input._Found(io, Input.ResetChecks[name], ocr)

    ; Check c's text read in its rect, else in its alt rect (if any).
    static _Found(io, c, ocr) {
        if InStr(StrLower(Input._Read(io, c, ocr)), c.text)
            return true
        if (c.HasOwnProp("alt") && InStr(StrLower(Input._Read(io, c.alt, ocr)), c.text))
            return true
        if (c.HasOwnProp("wide") && !Screen.IsIdentity() && InStr(StrLower(Input._Read(io, c.wide, ocr)), c.text))
            return true
        if c.HasOwnProp("marks")
            for m in c.marks
                if InStr(StrLower(Input._Read(io, m, ocr)), m.text)
                    return true
        return false
    }

    ; The Collections screen's own "[Exit]" reads (its title box or the
    ; tight box round it): the only spot its close click may go. Nothing
    ; else on that screen is clicked.
    static _ExitSeen(io, ocr := "") {
        c := Input.ResetChecks["collection"]
        if InStr(StrLower(Input._Read(io, c, ocr)), "exit")
            return true
        if InStr(StrLower(Input._Read(io, c.marks[1], ocr)), "exit")
            return true
        return IsObject(Input._ExitAt(io))
    }

    ; Below 1440p the Collections screen does not scale like the rest of the
    ; UI: at 1366x768 its "[Exit]" sat at client 277,108, about 24 px under
    ; the scaled close point and out of both "[Exit]" boxes, so it was never
    ; closed (live 2026-11-11). There "[Exit]" is looked for in a wide box at
    ; the top left and clicked where it reads. -> DESIGN {x, y} or "" (at
    ; 2560x1440, or an io that cannot find text).
    static ExitWide := {x: 0, y: 40, w: 1300, h: 380}
    static ExitFromCommon := 206      ; design px, [Exit]'s centre right of "Common"'s
    static TitleAboveCommon := 123    ; design px, the title row above "Common"
    static _ExitAt(io) {
        if (Screen.IsIdentity() || !HasMethod(io, "FindWord"))
            return ""
        b := Input.ExitWide
        r := ""
        try r := io.FindWord(b.x, b.y, b.w, b.h, "i)\bexit\b", "i)exit", 2)
        if IsObject(r)
            return {x: r.x, y: r.y}                     ; FindText gives DESIGN px off 1440p
        ; 5:4 (1280x1024, live 2026-11-11): the narrow title squeezes
        ; "[Exit]" into "Collections" and only "Aura" reads. The title spans
        ; the list's width: its "Aura" sits at the left end, the rows'
        ; "Common" at the centre, so "[Exit]" is as far right of the centre
        ; (x1.15: its middle, not the frame). The close is checked after.
        a := "", c := ""
        try a := io.FindWord(b.x, b.y, b.w, b.h, "i)^\W*aur[aou]\b", "i)aur[aou]", 2)     ; "Auru" at 1280x800
        try c := io.FindWord(b.x, b.y, b.w, b.h, "i)^\W*common\W*$", "i)common", 2)
        ; the title text sits differently at 5:4 and 1280x800, the list does
        ; not: "[Exit]" is centred ExitFromCommon design px right of the
        ; "Common" row's centre (both sizes measured live), on the title row
        if !IsObject(c)
            return ""
        y := (IsObject(a) && a.y < c.y) ? a.y : c.y - Input.TitleAboveCommon
        return {x: c.x + Input.ExitFromCommon, y: y}
    }

    ; Check rect c read by ocr (fn), else by io.Ocr.
    static _Read(io, c, ocr) => String(IsObject(ocr) ? ocr(c.x, c.y, c.w, c.h) : io.Ocr(c.x, c.y, c.w, c.h))

    ; Polls check `name` until its text is present (want true) or absent
    ; (want false), for up to Input.ResetSeeMs. -> 1 | 0 timeout | -1 stopped
    static _See(io, ctx, name, want, ocr := "") {
        c := Input.ResetChecks[name]
        waited := 0
        Loop {
            has := Input._Found(io, c, ocr)
            if (has = want)
                return 1
            if (waited >= Input.ResetSeeMs)
                return 0
            if !io.Wait(Input._PollMs(), ctx)
                return -1
            waited += Input._PollMs()
        }
    }

    ; -> Array of {key, action, ms}. Throws ValueError on any bad step.
    static ParseRoute(src) {
        if (Type(src) = "String")
            src := Json.Parse(src)
        if (src is Map) {
            if !(src.Has("steps"))
                throw ValueError("Route: object has no 'steps'")
            src := src["steps"]
        }
        if !(src is Array)
            throw ValueError("Route: expected an array of steps")
        out := []
        for item in src
            out.Push(Input._ParseStep(item, A_Index))
        return out
    }

    ; Sum of every step's ms (tap ms counts as hold time).
    static RouteMs(steps) {
        total := 0
        for s in Input.ParseRoute(steps)
            total += s.ms
        return total
    }

    static _ParseStep(item, i) {
        key := "", action := "", ms := "", dx := 0, dy := 0, n := 0
        if (item is Map) {
            key := item.Has("key") ? item["key"] : ""
            action := item.Has("action") ? item["action"] : ""
            ms := item.Has("ms") ? item["ms"] : ""
            dx := item.Has("dx") ? item["dx"] : 0
            dy := item.Has("dy") ? item["dy"] : 0
            n := item.Has("n") ? item["n"] : 0
        } else if (item is Array) {
            if (item.Length = 2 && item[1] == "wait")
                action := "wait", ms := item[2]
            else if (item.Length = 4 && item[1] == "look")
                action := "look", dx := item[2], dy := item[3], ms := item[4]
            else if (item.Length = 3 && item[1] == "zoom")
                action := "zoom", n := item[2], ms := item[3]
            else if (item.Length = 3)
                key := item[1], action := item[2], ms := item[3]
            else
                throw ValueError("Route: step " i ": compact step needs 3 items")
        } else if (Type(item) = "Object" && item.HasOwnProp("action")) {
            key := item.HasOwnProp("key") ? item.key : ""
            action := item.action
            ms := item.HasOwnProp("ms") ? item.ms : ""
        } else {
            throw ValueError("Route: step " i ": not an object or array")
        }
        action := StrLower(String(action))
        if !Input.Actions.Has(action)
            throw ValueError("Route: step " i ": bad action")
        if (Type(ms) != "Integer" || ms < 0)
            throw ValueError("Route: step " i ": ms must be an integer >= 0")
        if (action = "look") {
            if (Type(dx) != "Integer" || Type(dy) != "Integer" || Abs(dx) > Input.LookMax || Abs(dy) > Input.LookMax)
                throw ValueError("Route: step " i ": look needs integer dx, dy")
            return {key: "", action: action, ms: ms, dx: dx, dy: dy}
        }
        if (action = "zoom") {
            if (Type(n) != "Integer" || n = 0 || Abs(n) > Input.ZoomMax)
                throw ValueError("Route: step " i ": zoom needs a non-zero integer n")
            return {key: "", action: action, ms: ms, n: n}
        }
        if (action = "wait")
            key := ""
        else
            Input._CheckKey(key, "Route: step " i)
        return {key: key, action: action, ms: ms}
    }

    static _CheckKey(k, where) {
        if (Type(k) != "String" || !RegExMatch(k, "^\w+$"))
            throw ValueError(where ": bad key name")
    }

    static _Backend(io) => IsObject(io) ? io : Input._io
}
