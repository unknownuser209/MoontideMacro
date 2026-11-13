#Requires AutoHotkey v2.0
; Offline tests for lib\tasks\Recovery.ahk: fake clock, io, window, webhook.
; Helpers are prefixed Rc (must not start with Test_).
#Include ..\lib\Config.ahk
#Include ..\lib\tasks\Recovery.ahk

class RcClock {
    __New(t := 1000000) {
        this.t := t
    }
}

; Input io that records keys and advances the fake clock on Wait.
class RcIO {
    __New(clock) {
        this.clock := clock
        this.ev := []
    }
    Down(k) {
        this.ev.Push("d:" k)
    }
    Up(k) {
        this.ev.Push("u:" k)
    }
    MoveTo(x, y) {
        this.ev.Push("m")
    }
    ClickHere() {
        this.ev.Push("c")
    }
    Wait(ms, ctx := "") {
        if (IsObject(ctx) && ctx.ShouldStop())
            return false
        this.clock.t += ms
        return true
    }
    Count(e) {
        n := 0
        for x in this.ev
            if (x = e)
                n++
        return n
    }
}

class RcHook {
    __New() {
        this.sent := []
    }
    Send(event, title, desc, color := 0) {
        this.sent.Push({event: event, title: title, desc: desc})
    }
    Text() {
        s := ""
        for m in this.sent
            s .= m.event "|" m.title "|" m.desc "`n"
        return s
    }
}

class RcCfg {
    __New(link := "", extra := "") {
        this.v := Map("general.privateserver", link)
        if IsObject(extra)
            for k, val in extra
                this.v[StrLower(k)] := val
    }
    Get(path, default := "") {
        p := StrLower(path)
        return this.v.Has(p) ? this.v[p] : default
    }
    Data(name) => Map()
}

class RcCal {
    Point(id) => ""
    Rect(id) => ""
}

; Bundles all fakes. win: whether the Roblox window currently exists.
class RcRig {
    __New(link := "https://www.roblox.com/games/1/x?privateServerLinkCode=SECRET123", cfgExtra := "", cal := "") {
        this.clock := RcClock()
        this.io := RcIO(this.clock)
        this.hook := RcHook()
        this.logs := []
        this.win := true
        this.focus := true
        this.canFocus := true       ; result of the focus() dep
        this.focusCalls := 0
        this.runs := []
        this.windowAt := 0          ; set by Run(link): window appears at this fake time
        this.openMs := 5000         ; delay between Run(link) and the window
        this.screen := ""           ; OCR text of the screen centre
        this.ocrCalls := 0
        this.closes := 0
        this.paused := 0
        this.updateUntil := 0       ; a Roblox launcher process runs until this fake time
        this.updateName := "RobloxPlayerInstaller.exe"
        this.state := SchedState()
        rig := this
        this.task := RecoveryTask({
            cfg: RcCfg(link, cfgExtra),
            webhook: this.hook,
            log: (s) => rig.logs.Push(s),
            io: this.io,
            cal: IsObject(cal) ? cal : RcCal(),
            now: () => rig.clock.t,
            hwnd: () => (rig.win && rig.clock.t >= rig.windowAt) ? 1234 : 0,
            active: () => rig.focus,
            focus: () => (rig.focusCalls++, rig.canFocus),
            ocr: (x, y, w, h) => (rig.ocrCalls++, rig.screen),
            procs: (name) => (name = rig.updateName && rig.clock.t < rig.updateUntil),
            close: () => (rig.closes++, rig.win := false, true),
            run: (target) => (rig.runs.Push(target), rig.windowAt := rig.clock.t + rig.openMs, rig.win := true)
        })
    }
    Ctx() {
        rig := this
        return {
            ShouldStop: (*) => false,
            Pause: (*) => rig.paused++
        }
    }
    AllText() {
        s := this.hook.Text()
        for l in this.logs
            s .= l "`n"
        return s
    }
}

RcThrowRun(target) {
    throw Error("Failed attempt to launch program or document: " target)
}

Test_Recovery_Contract() {
    rig := RcRig()
    AssertEq(rig.task.name, "recovery", "name")
    AssertEq(rig.task.priority, 2, "priority")
    AssertEq(rig.task.priority, Sched.Priority["recovery"], "matches scheduler table")
}

Test_Recovery_CanRun_MissingWindow() {
    rig := RcRig()
    AssertEq(rig.task.CanRun(rig.state), false, "healthy and idle: no")
    rig.win := false
    AssertEq(rig.task.CanRun(rig.state), true, "window gone: yes")
}

Test_Recovery_DisconnectScreenClosesAndRejoins() {
    ; no Reconnect button in game: the disconnect screen is read, the client
    ; closed and the private server opened again
    rig := RcRig()
    AssertEq(rig.task.CanRun(rig.state), false, "normal screen: no")
    rig.screen := "Disconnected`nLost connection to the game server, please reconnect (Error Code: 277)"
    AssertEq(rig.task.CanRun(rig.state), false, "screen read at most every 5 s")
    rig.clock.t += 5000
    n := rig.ocrCalls
    AssertEq(rig.task.CanRun(rig.state), true, "disconnect screen seen")
    AssertEq(rig.ocrCalls - n, 1, "one read")
    AssertEq(rig.task.Run(rig.Ctx()), 1, "rejoined")
    AssertEq(rig.closes, 1, "old client closed first")
    AssertEq(rig.runs.Length, 1, "then the link opened once")
    AssertTrue(!InStr(rig.AllText(), "SECRET123"), "link never logged")
    rig.screen := ""
    rig.clock.t += 5000
    AssertEq(rig.task.CanRun(rig.state), false, "handled: back to normal")
    ; no link: the client is NOT closed (nothing to rejoin with)
    rig2 := RcRig("")
    rig2.screen := "You were kicked from this experience"
    AssertEq(rig2.task.CanRun(rig2.state), true, "kicked screen seen")
    AssertEq(rig2.task.Run(rig2.Ctx()), 0, "cannot rejoin")
    AssertEq(rig2.closes, 0, "Roblox left open without a link")
}

Test_Recovery_CanRun_StuckTimeout() {
    rig := RcRig()
    rig.task.CanRun(rig.state)
    ; 9 min with polls every 30 s: not stuck yet
    Loop 18 {
        rig.clock.t += 30000
        AssertEq(rig.task.CanRun(rig.state), false, "not stuck at poll " A_Index)
    }
    ; keep polling: stuck once 10 min have passed since the baseline
    rig.clock.t += 30000
    AssertEq(rig.task.CanRun(rig.state), false, "9:30")
    rig.clock.t += 30000
    AssertEq(rig.task.CanRun(rig.state), true, "10:00 stuck")
    ; fishing switched off: waiting between quest runs is not "stuck"
    rig2 := RcRig(, Map("General.fishing", 0))
    rig2.task.CanRun(rig2.state)
    Loop 25 {                           ; 12.5 min (anti-AFK is 15)
        rig2.clock.t += 30000
        AssertEq(rig2.task.CanRun(rig2.state), false, "not stuck without fishing, poll " A_Index)
    }
}

Test_Recovery_Stuck_ProgressResetsClock() {
    rig := RcRig(, Map("recovery.afkMin", 9999))
    rig.task.CanRun(rig.state)
    Loop 16 {
        rig.clock.t += 30000             ; 8 min
        rig.task.CanRun(rig.state)
    }
    rig.state.fishLoops := 1             ; progress
    rig.task.CanRun(rig.state)
    Loop 18 {
        rig.clock.t += 30000             ; +9 min since progress
        AssertEq(rig.task.CanRun(rig.state), false, "fishLoops progress restarted clock " A_Index)
    }
    ; a completed task (lastRun stamp) is progress too
    rig.state.lastRun["sell"] := rig.clock.t
    rig.task.CanRun(rig.state)
    Loop 18 {
        rig.clock.t += 30000
        AssertEq(rig.task.CanRun(rig.state), false, "task completion restarted clock " A_Index)
    }
    ; recovery's own stamp is NOT progress
    rig.state.lastRun["recovery"] := rig.clock.t
    rig.clock.t += 60000
    AssertEq(rig.task.CanRun(rig.state), true, "recovery stamp ignored -> stuck")
}

Test_Recovery_Stuck_PollGapIsNotStuck() {
    ; macro paused for an hour: the first poll afterwards must not reset.
    rig := RcRig(, Map("recovery.afkMin", 9999))
    rig.task.CanRun(rig.state)
    rig.clock.t += 3600000
    AssertEq(rig.task.CanRun(rig.state), false, "gap restarts clock")
}

Test_Recovery_Stuck_RunResetsToSpawn() {
    rig := RcRig()
    rig.task.CanRun(rig.state)
    Loop 20 {
        rig.clock.t += 30000
        rig.task.CanRun(rig.state)
    }
    AssertEq(rig.task.CanRun(rig.state), true, "stuck")
    AssertEq(rig.task.Run(rig.Ctx()), 1, "acted")
    AssertEq(rig.io.Count("d:Esc"), 1, "ResetToSpawn pressed Esc")
    AssertEq(rig.io.Count("d:Enter"), 1, "ResetToSpawn pressed Enter")
    AssertEq(rig.runs.Length, 0, "no rejoin when window exists")
    AssertEq(rig.task.CanRun(rig.state), false, "clock restarted after reset")
    AssertTrue(InStr(rig.hook.Text(), "errors|Recovery: stuck"), "errors webhook")
}

Test_Recovery_Rejoin_WaitsAndSucceeds() {
    rig := RcRig()
    rig.win := false
    AssertEq(rig.task.CanRun(rig.state), true, "can run")
    t0 := rig.clock.t
    AssertEq(rig.task.Run(rig.Ctx()), 1, "rejoined")
    AssertEq(rig.runs.Length, 1, "Run(link) once")
    AssertEq(rig.runs[1], "https://www.roblox.com/games/1/x?privateServerLinkCode=SECRET123", "link passed to Run")
    el := rig.clock.t - t0
    AssertTrue(el >= 5000 + 20000, "waited for window + load, elapsed " el)
    AssertEq(rig.io.Count("d:Esc"), 1, "reset to spawn after load")
    AssertEq(rig.state.progressAt, rig.clock.t, "progress clock restarted")
    AssertTrue(InStr(rig.hook.Text(), "errors|Recovery: rejoined"), "errors webhook")
    AssertTrue(!InStr(rig.AllText(), "SECRET123"), "link never logged or sent")
    AssertTrue(!InStr(rig.AllText(), "roblox.com"), "no url fragment logged or sent")
}

Test_Recovery_Rejoin_LoadSecConfigurable() {
    rig := RcRig(, Map("recovery.loadSec", 40))
    rig.openMs := 0
    rig.win := false
    t0 := rig.clock.t
    rig.task.Run(rig.Ctx())
    AssertTrue(rig.clock.t - t0 >= 40000, "loadSec=40 honored")
}

Test_Recovery_Rejoin_Timeout() {
    rig := RcRig()
    rig.win := false
    rig.openMs := 10 ** 9                ; window never appears
    t0 := rig.clock.t
    AssertEq(rig.task.Run(rig.Ctx()), 0, "failed")
    el := rig.clock.t - t0
    AssertTrue(el >= 90000 && el < 95000, "waited ~90 s, elapsed " el)
    AssertEq(rig.io.Count("d:Esc"), 0, "no reset without window")
    AssertTrue(InStr(rig.hook.Text(), "errors|Recovery failed"), "errors webhook")
    ; backoff: CanRun false right away, true after RetryMs
    rig.win := false
    AssertEq(rig.task.CanRun(rig.state), false, "held after failure")
    rig.clock.t += RecoveryTask.RetryMs
    AssertEq(rig.task.CanRun(rig.state), true, "retry allowed later")
}

Test_Recovery_Rejoin_AbortsOnStop() {
    rig := RcRig()
    rig.win := false
    rig.openMs := 10 ** 9
    ctx := {ShouldStop: (*) => true, Pause: (*) => 0}
    t0 := rig.clock.t
    AssertEq(rig.task.Run(ctx), 0, "aborted")
    AssertTrue(rig.clock.t - t0 < 5000, "did not sit out the 90 s")
}

Test_Recovery_Rejoin_RateLimit() {
    rig := RcRig()
    rig.openMs := 10 ** 9                ; every attempt times out
    rig.win := false
    Loop 3 {
        AssertEq(rig.task.CanRun(rig.state), true, "attempt " A_Index " allowed")
        rig.task.Run(rig.Ctx())
        rig.win := false
        rig.clock.t += RecoveryTask.RetryMs
    }
    AssertEq(rig.runs.Length, 3, "three attempts")
    ; 4th within 10 min of the first: refused and held, the macro NOT paused
    ; (overnight review: a pause stopped recovery until someone pressed F2)
    AssertEq(rig.task.CanRun(rig.state), true, "polled")
    AssertEq(rig.task.Run(rig.Ctx()), 0, "limited")
    AssertEq(rig.runs.Length, 3, "no 4th Run(link)")
    AssertEq(rig.paused, 0, "the macro is not paused")
    AssertTrue(InStr(rig.hook.Text(), "errors|Recovery on hold"), "errors webhook")
    AssertEq(rig.task.CanRun(rig.state), false, "held while limited")
    ; once the oldest attempt leaves the 10 min window it tries again
    rig.clock.t += 11 * 60000
    AssertEq(rig.task.CanRun(rig.state), true, "allowed again")
    Loop 3 {
        rig.task.Run(rig.Ctx())
        rig.win := false
        rig.clock.t += RecoveryTask.RetryMs
    }
    AssertEq(rig.runs.Length, 6, "three more attempts after the window")
    ; the limit again: held again, but the hold is reported only once
    AssertEq(rig.task.Run(rig.Ctx()), 0, "limited again")
    n := 0
    for l in StrSplit(rig.hook.Text(), "`n")
        n += InStr(l, "Recovery on hold") ? 1 : 0
    AssertEq(n, 1, "the hold reported once")
    AssertEq(rig.paused, 0, "still not paused")
    rig.clock.t += 11 * 60000
    rig.openMs := 1000
    rig.task.Run(rig.Ctx())
    AssertEq(rig.runs.Length, 7, "next attempt after the window")
}

Test_Recovery_Rejoin_QuietsAuraClips() {
    ; 2026-10-31: the fresh client's first "Equipped" line (your own aura)
    ; clipped as a roll after every rejoin
    try {
        Auras.QuietUntil := 0
        rig := RcRig()
        rig.win := false
        AssertEq(rig.task.Run(rig.Ctx()), 1, "rejoined")
        AssertTrue(Auras.QuietUntil >= A_TickCount + Auras.JoinQuietMs - 1000, "auras quiet after the rejoin")
    } finally {
        Auras.QuietUntil := 0
    }
}

Test_Recovery_EmptyLink_NeverRuns() {
    rig := RcRig("")
    rig.win := false
    AssertEq(rig.task.CanRun(rig.state), true, "disconnected")
    AssertEq(rig.task.Run(rig.Ctx()), 0, "cannot rejoin")
    AssertEq(rig.runs.Length, 0, "Run(link) never called")
    AssertEq(rig.hook.sent.Length, 1, "one errors webhook")
    AssertEq(rig.hook.sent[1].event, "errors", "event is errors")
    ; backoff, and no second webhook even when retried
    AssertEq(rig.task.CanRun(rig.state), false, "backs off (no spin)")
    rig.clock.t += RecoveryTask.RetryMs
    AssertEq(rig.task.CanRun(rig.state), true, "polled again later")
    rig.task.Run(rig.Ctx())
    AssertEq(rig.runs.Length, 0, "still never Run")
    AssertEq(rig.hook.sent.Length, 1, "webhook only once")
}

Test_Recovery_InvalidLink_NeverRuns() {
    bad := [
        "http://www.roblox.com/games/1",
        "https://www.roblox.com.evil.test/x",
        "https://evil.test/https://www.roblox.com/",
        "file:///C:/Windows/System32/calc.exe",
        "calc.exe",
        "https://www.roblox.com/",
        "https://www.roblox.com/x y",
        "https://www.roblox.com/x`"y"
    ]
    for link in bad {
        rig := RcRig(link)
        rig.win := false
        rig.task.CanRun(rig.state)
        rig.task.Run(rig.Ctx())
        AssertEq(rig.runs.Length, 0, "never Run: " A_Index)
        AssertEq(rig.hook.sent.Length, 1, "one webhook: " A_Index)
        AssertEq(rig.hook.sent[1].event, "errors", "errors event: " A_Index)
        AssertTrue(!InStr(rig.AllText(), link), "value not in logs/webhook: " A_Index)
    }
    AssertTrue(RecoveryTask.LinkOk("https://www.roblox.com/games/1/x?privateServerLinkCode=1"), "valid accepted")
    AssertTrue(RecoveryTask.LinkOk("https://www.roblox.com/share?code=abc&type=Server"), "share link accepted")
}

Test_Recovery_RunError_NeverLeaksLink() {
    rig := RcRig()
    rig.win := false
    rig.task._runFn := RcThrowRun
    rig.task.Run(rig.Ctx())
    AssertTrue(!InStr(rig.AllText(), "SECRET123"), "error text not forwarded")
    AssertEq(rig.hook.sent.Length, 1, "errors webhook sent")
}

Test_Recovery_AntiAfk_Interval() {
    rig := RcRig()
    AssertEq(rig.task.CanRun(rig.state), false, "not due at start")
    Loop 14 {
        rig.clock.t += 60000
        rig.state.fishLoops++
        AssertEq(rig.task.CanRun(rig.state), false, "not due at min " A_Index)
    }
    rig.clock.t += 60000                 ; 15 min
    rig.state.fishLoops++
    AssertEq(rig.task.CanRun(rig.state), true, "due at 15 min")
    AssertEq(rig.task.Run(rig.Ctx()), 1, "tapped")
    AssertEq(rig.io.Count("d:Space"), 1, "one Space down")
    AssertEq(rig.io.Count("u:Space"), 1, "one Space up")
    AssertEq(rig.runs.Length, 0, "no rejoin")
    AssertEq(rig.task.CanRun(rig.state), false, "not due right after tap")
    Loop 14 {
        rig.clock.t += 60000
        rig.state.fishLoops++
        rig.task.CanRun(rig.state)
    }
    rig.clock.t += 60000
    rig.state.fishLoops++
    AssertEq(rig.task.CanRun(rig.state), true, "due again 15 min later")
}

Test_Recovery_AntiAfk_NeedsFocus_AndConfigurable() {
    rig := RcRig(, Map("recovery.afkMin", 5))
    rig.task.CanRun(rig.state)
    rig.focus := false
    Loop 6 {
        rig.clock.t += 60000
        rig.state.fishLoops++
        AssertEq(rig.task.CanRun(rig.state), false, "unfocused: no tap " A_Index)
    }
    rig.focus := true
    AssertEq(rig.task.CanRun(rig.state), true, "focused and past afkMin=5")
}

Test_Recovery_Disabled() {
    rig := RcRig(, Map("recovery.enabled", 0))
    rig.win := false
    AssertEq(rig.task.CanRun(rig.state), false, "recovery.enabled=0")
}

Test_Recovery_ConfigDefaults() {
    d := Config.IniDefaults()
    AssertEq(d["Recovery"]["stuckMin"], "10", "stuckMin default")
    AssertEq(d["Recovery"]["afkMin"], "15", "afkMin default")
    AssertEq(d["Recovery"]["loadSec"], "20", "loadSec default")
    AssertEq(d["Recovery"]["maxRejoins"], "3", "maxRejoins default")
    AssertEq(d["Recovery"]["rejoinWindowMin"], "10", "window default")
    AssertEq(d["General"]["privateServer"], "", "link default empty")
}

Test_Recovery_Busy_LongTaskNotStuck() {
    rig := RcRig(, Map("recovery.afkMin", 9999))
    rig.task.CanRun(rig.state)
    ; a craft task runs 30 min; main loop polls CanRun while busy
    rig.state.busy := "craft"
    Loop 60 {
        rig.clock.t += 30000
        AssertEq(rig.task.CanRun(rig.state), false, "busy craft is never stuck " A_Index)
    }
    rig.state.busy := ""
    ; progress clock was refreshed by the last busy poll: not stuck right away
    rig.clock.t += 30000
    AssertEq(rig.task.CanRun(rig.state), false, "fresh clock after the task")
    ; fishing busy is NOT progress: a truly stuck fisher is still caught
    rig.state.busy := "fishing"
    Loop 20 {
        rig.clock.t += 30000
        rig.task.CanRun(rig.state)
    }
    AssertEq(rig.task.CanRun(rig.state), true, "stuck while busy=fishing")
}

Test_Recovery_Busy_AfkDeferred() {
    rig := RcRig()
    rig.task.CanRun(rig.state)
    rig.state.busy := "fishing"
    Loop 16 {
        rig.clock.t += 60000
        rig.state.fishLoops++
        AssertEq(rig.task.CanRun(rig.state), false, "no AFK tap while busy " A_Index)
    }
    rig.state.busy := ""
    AssertEq(rig.task.CanRun(rig.state), true, "AFK once idle")
    rig.state.busy := "recovery"         ; main loop marks recovery itself busy
    AssertEq(rig.task.Run(rig.Ctx()), 1, "tap runs while busy=recovery")
    AssertEq(rig.io.Count("d:Space"), 1, "Space tapped")
}

Test_Recovery_Focus_FailureSendsNoKeys() {
    ; stuck path
    rig := RcRig()
    rig.task.CanRun(rig.state)
    Loop 21 {
        rig.clock.t += 30000
        rig.task.CanRun(rig.state)
    }
    rig.canFocus := false
    AssertEq(rig.task.CanRun(rig.state), true, "stuck")
    AssertEq(rig.task.Run(rig.Ctx()), 0, "skipped")
    AssertEq(rig.io.ev.Length, 0, "zero key events (stuck)")
    AssertEq(rig.hook.sent.Length, 1, "one errors webhook")
    AssertEq(rig.hook.sent[1].event, "errors", "errors event")
    AssertEq(rig.task.CanRun(rig.state), false, "backs off")
    rig.clock.t += RecoveryTask.RetryMs
    AssertEq(rig.task.CanRun(rig.state), true, "retries later")
    rig.task.Run(rig.Ctx())
    AssertEq(rig.hook.sent.Length, 1, "webhook once per key")
    AssertEq(rig.io.ev.Length, 0, "still zero key events")
    ; focus returns: the reset goes through
    rig.canFocus := true
    rig.clock.t += RecoveryTask.RetryMs
    AssertEq(rig.task.Run(rig.Ctx()), 1, "reset once focused")
    AssertTrue(rig.io.Count("d:Esc") = 1, "Esc sent")
}

Test_Recovery_Focus_RejoinPath() {
    rig := RcRig()
    rig.win := false
    rig.canFocus := false
    AssertEq(rig.task.Run(rig.Ctx()), 0, "not completed")
    AssertEq(rig.runs.Length, 1, "link opened")
    AssertEq(rig.io.ev.Length, 0, "zero key events after rejoin without focus")
    AssertTrue(rig.focusCalls >= 1, "focus attempted")
    ; focus is requested before the reset on success
    rig2 := RcRig()
    rig2.win := false
    AssertEq(rig2.task.Run(rig2.Ctx()), 1, "rejoined")
    AssertTrue(rig2.focusCalls >= 1, "focus called before reset")
}

Test_Recovery_Stuck_AbortedResetKeepsClock() {
    rig := RcRig()
    rig.task.CanRun(rig.state)
    Loop 20 {
        rig.clock.t += 30000
        rig.task.CanRun(rig.state)
    }
    AssertEq(rig.task.CanRun(rig.state), true, "stuck")
    stopCtx := {ShouldStop: (*) => true, Pause: (*) => 0}
    AssertEq(rig.task.Run(stopCtx), 0, "aborted reset is not success")
    AssertEq(rig.hook.sent.Length, 0, "no stuck webhook for an aborted reset")
    AssertEq(rig.task.CanRun(rig.state), true, "progress clock not restarted")
    AssertEq(rig.task.Run(rig.Ctx()), 1, "completes next time")
    AssertEq(rig.task.CanRun(rig.state), false, "clock restarted after success")
}

; ---- Roblox update: the launcher downloads before the window exists --------

Test_Recovery_Update_WaitsForTheLauncher() {
    rig := RcRig()
    rig.win := false
    rig.openMs := 250000                 ; window after 250 s: the update downloaded
    rig.updateUntil := rig.clock.t + 250000
    t0 := rig.clock.t
    AssertEq(rig.task.Run(rig.Ctx()), 1, "rejoined after the update")
    AssertEq(rig.runs.Length, 1, "the link was opened once (no second attempt)")
    AssertTrue(rig.clock.t - t0 >= 250000, "waited the whole update")
    AssertTrue(!InStr(rig.hook.Text(), "Recovery failed"), "no failed-rejoin report")
    log := rig.AllText()
    AssertTrue(InStr(log, "Roblox is updating - waiting for it to finish"), "update logged")
    StrReplace(log, "Roblox is updating", , , &n)
    AssertEq(n, 1, "update logged once")
    AssertEq(rig.task.CanRun(rig.state), false, "no hold after a good rejoin")
}

Test_Recovery_Update_CappedAtTenMinutes() {
    rig := RcRig()
    rig.win := false
    rig.openMs := 10 ** 9
    rig.updateUntil := 10 ** 12          ; the launcher never ends
    t0 := rig.clock.t
    AssertEq(rig.task.Run(rig.Ctx()), 0, "gave up")
    el := rig.clock.t - t0
    AssertTrue(el >= 90000 + RecoveryTask.UpdateMaxMs && el < 90000 + RecoveryTask.UpdateMaxMs + 5000, "90 s + 10 min, elapsed " el)
    AssertTrue(InStr(rig.hook.Text(), "errors|Recovery failed"), "errors webhook after the cap")
}

Test_Recovery_Update_NoLauncherNoExtraWait() {
    rig := RcRig()
    rig.win := false
    rig.openMs := 10 ** 9
    t0 := rig.clock.t
    rig.task.Run(rig.Ctx())
    AssertTrue(rig.clock.t - t0 < 95000, "90 s wait when no launcher runs")
    AssertTrue(!InStr(rig.AllText(), "Roblox is updating"), "nothing logged")
}

Test_Recovery_Update_LauncherList() {
    for n in ["RobloxPlayerInstaller.exe", "RobloxPlayerLauncher.exe", "Bloxstrap.exe", "Fishstrap.exe", "Voidstrap.exe"] {
        found := false
        for l in RecoveryTask.Launchers
            if (l = n)
                found := true
        AssertTrue(found, "launcher listed: " n)
    }
    ; each name alone counts as an update
    for n in RecoveryTask.Launchers {
        rig := RcRig()
        rig.win := false
        rig.openMs := 120000
        rig.updateName := n
        rig.updateUntil := rig.clock.t + 120000
        AssertEq(rig.task.Run(rig.Ctx()), 1, "waited for " n)
    }
}
