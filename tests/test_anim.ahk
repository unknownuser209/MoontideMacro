#Requires AutoHotkey v2.0
; Offline tests for lib\ui\Anim.ahk (one shared timer, tweens, loops, gate).
; A fake clock and a fake timer stand in for A_TickCount and SetTimer.
; Helpers are prefixed AnimT.
#Include ..\lib\ui\Anim.ahk

; Fresh engine wired to a fake clock (clk.t) and a recorder of timerFn calls.
AnimTRig() {
    Anim.Reset()
    r := {clk: {t: 0}, timers: [], log: []}
    Anim.nowFn := () => r.clk.t
    Anim.timerFn := (fn, ms) => r.timers.Push(ms)
    return r
}

Test_Anim_Ease() {
    AssertEq(Anim.Ease(0), 0.0, "Ease(0)")
    AssertEq(Anim.Ease(1), 1.0, "Ease(1)")
    AssertTrue(Anim.Ease(0.5) > 0.5, "ease-out is ahead of linear at the midpoint")
    AssertEq(Anim.Ease(-1), 0.0, "Ease clamps below 0")
    AssertEq(Anim.Ease(2), 1.0, "Ease clamps above 1")
    AssertEq(Anim.Lerp(10, 20, 0.5), 15.0, "Lerp midpoint")
    AssertEq(Anim.Lerp(10, 20, 0), 10.0, "Lerp start")
}

Test_Anim_TweenRunsAndStops() {
    r := AnimTRig()
    try {
        done := 0
        Anim.Tween("fade", 180, (p) => r.log.Push(p), () => (done++))
        AssertEq(Anim.Active(), 1, "one tween running")
        AssertEq(r.timers.Length, 1, "timer started once")
        AssertEq(r.timers[1], 33, "timer period is FrameMs")
        r.clk.t := 0
        Anim.Tick()
        r.clk.t := 90
        Anim.Tick()
        r.clk.t := 200
        Anim.Tick()
        AssertEq(r.log.Length, 3, "one step per tick")
        AssertEq(r.log[1], 0.0, "first p")
        AssertTrue(r.log[2] > r.log[1] && r.log[2] < 1, "p rising mid-way")
        AssertEq(r.log[3], 1.0, "last p is 1")
        AssertEq(done, 1, "doneFn called once")
        AssertEq(Anim.Active(), 0, "no animations left")
        AssertEq(r.timers.Length, 2, "timer started then stopped")
        AssertEq(r.timers[2], 0, "stopped with 0")
        r.clk.t := 400
        Anim.Tick()
        AssertEq(done, 1, "a finished tween never fires again")
    } finally {
        Anim.Reset()
    }
}

Test_Anim_SameKeyReplaces() {
    r := AnimTRig()
    try {
        first := [], second := []
        firstDone := 0
        Anim.Tween("ul", 100, (p) => first.Push(p), () => (firstDone++))
        Anim.Tween("ul", 100, (p) => second.Push(p))
        AssertEq(first.Length, 1, "the replaced tween was stepped once")
        AssertEq(first[1], 1.0, "...to p = 1")
        AssertEq(Anim.Active(), 1, "only the second keeps running")
        AssertEq(r.timers.Length, 1, "the timer was not restarted")
        r.clk.t := 100
        Anim.Tick()
        AssertEq(first.Length, 1, "the replaced tween is not stepped again")
        AssertEq(firstDone, 0, "the replaced tween's doneFn is not called")
        AssertEq(second.Length, 1, "the second tween ran")
        AssertEq(second[1], 1.0, "...and finished")
        AssertEq(Anim.Active(), 0, "nothing left")
    } finally {
        Anim.Reset()
    }
}

Test_Anim_LoopPhase() {
    r := AnimTRig()
    try {
        Anim.Loop("pulse", 1600, (ph) => r.log.Push(ph))
        AssertEq(Anim.Active(), 1, "loop counts as active")
        for t in [0, 400, 800, 1600] {
            r.clk.t := t
            Anim.Tick()
        }
        AssertEq(r.log.Length, 4, "one step per tick")
        for i, want in [0, 0.25, 0.5, 0] {
            AssertTrue(Abs(r.log[i] - want) < 0.001, "phase " i)
        }
        AssertEq(Anim.Active(), 1, "a loop runs until stopped")
        Anim.Stop("pulse")
        AssertEq(Anim.Active(), 0, "stopped")
        AssertEq(r.timers[r.timers.Length], 0, "timer stopped with the last loop")
        Anim.Stop("pulse")
    } finally {
        Anim.Reset()
    }
}

Test_Anim_GateClosedFinishesAndStops() {
    r := AnimTRig()
    try {
        loopSteps := 0, tweenLog := [], done := 0
        Anim.Loop("pulse", 1000, (ph) => (loopSteps++))
        Anim.Tween("fade", 500, (p) => tweenLog.Push(p), () => (done++))
        r.clk.t := 100
        Anim.Tick()
        AssertEq(loopSteps, 1, "loop stepped while the gate is open")
        Anim.gateFn := () => false
        r.clk.t := 200
        Anim.Tick()
        AssertEq(tweenLog[tweenLog.Length], 1.0, "tween jumped to its end")
        AssertEq(done, 1, "tween done")
        AssertEq(loopSteps, 1, "loop not stepped while the gate is closed")
        AssertEq(Anim.Active(), 1, "the loop is kept, frozen")
        AssertEq(r.timers[r.timers.Length], 0, "timer stopped")
    } finally {
        Anim.Reset()
    }
}

Test_Anim_DisabledJumpsToEnd() {
    r := AnimTRig()
    try {
        Anim.enabledFn := () => false
        done := 0, tweenLog := [], loopLog := []
        Anim.Tween("fade", 300, (p) => tweenLog.Push(p), () => (done++))
        AssertEq(tweenLog.Length, 1, "tween stepped at once")
        AssertEq(tweenLog[1], 1.0, "...to p = 1")
        AssertEq(done, 1, "done called at once")
        Anim.Loop("pulse", 1000, (ph) => loopLog.Push(ph))
        AssertEq(loopLog.Length, 1, "loop stepped once")
        AssertEq(loopLog[1], 0, "...at phase 0")
        AssertEq(Anim.Active(), 0, "nothing runs")
        AssertEq(r.timers.Length, 0, "no timer")
    } finally {
        Anim.Reset()
    }
}

Test_Anim_DisabledMidRunSettles() {
    r := AnimTRig()
    try {
        tweenLog := [], loopLog := []
        Anim.Tween("fade", 500, (p) => tweenLog.Push(p))
        Anim.Loop("pulse", 1000, (ph) => loopLog.Push(ph))
        Anim.enabledFn := () => false
        r.clk.t := 100
        Anim.Tick()
        AssertEq(tweenLog[tweenLog.Length], 1.0, "tween settled at its end")
        AssertEq(loopLog[loopLog.Length], 0, "loop settled at phase 0")
        AssertEq(Anim.Active(), 0, "nothing left running")
        AssertEq(r.timers[r.timers.Length], 0, "timer stopped")
    } finally {
        Anim.Reset()
    }
}

Test_Anim_UngatedRunsWhileGateClosed() {
    r := AnimTRig()
    try {
        Anim.gateFn := () => false
        gatedLog := [], freeLog := [], gatedDone := 0, freeDone := 0
        Anim.Tween("gated", 150, (p) => gatedLog.Push(p), () => (gatedDone++))
        Anim.Tween("free", 150, (p) => freeLog.Push(p), () => (freeDone++), false)
        r.clk.t := 50
        Anim.Tick()
        AssertEq(gatedLog[gatedLog.Length], 1.0, "gated tween finished at the first tick")
        AssertEq(gatedDone, 1, "gated tween done")
        AssertEq(freeLog.Length, 1, "ungated tween stepped")
        AssertTrue(freeLog[1] > 0 && freeLog[1] < 1, "ungated tween still in progress")
        AssertEq(freeDone, 0, "ungated tween not done yet")
        AssertEq(Anim.Active(), 1, "ungated tween still running")
        AssertTrue(r.timers[r.timers.Length] != 0, "timer keeps running for the ungated tween")
        r.clk.t := 100
        Anim.Tick()
        AssertTrue(freeLog[2] > freeLog[1] && freeLog[2] < 1, "p rising")
        r.clk.t := 160
        Anim.Tick()
        AssertEq(freeLog[freeLog.Length], 1.0, "ungated tween reached 1")
        AssertEq(freeDone, 1, "ungated tween done once")
        AssertEq(Anim.Active(), 0, "nothing left")
        AssertEq(r.timers[r.timers.Length], 0, "timer stopped at the end")
    } finally {
        Anim.Reset()
    }
}

Test_Anim_WakeResumesFrozenLoop() {
    r := AnimTRig()
    try {
        steps := 0
        Anim.Loop("pulse", 1000, (ph) => (steps++))
        r.clk.t := 100
        Anim.Tick()
        AssertEq(steps, 1, "loop stepped while the gate is open")
        Anim.gateFn := () => false
        r.clk.t := 200
        Anim.Tick()
        AssertEq(steps, 1, "loop frozen while the gate is closed")
        AssertEq(r.timers[r.timers.Length], 0, "timer stopped")
        Anim.Wake()
        AssertEq(r.timers.Length, 2, "Wake with the gate still closed does nothing")
        Anim.gateFn := () => true
        Anim.Wake()
        AssertEq(r.timers.Length, 3, "Wake restarted the timer")
        AssertEq(r.timers[3], 33, "...at FrameMs")
        Anim.Wake()
        AssertEq(r.timers.Length, 3, "Wake with the timer running does nothing")
        r.clk.t := 300
        Anim.Tick()
        AssertEq(steps, 2, "loop steps again after Wake")
        Anim.Stop("pulse")
        Anim.Wake()
        AssertEq(r.timers[r.timers.Length], 0, "Wake with nothing active starts no timer")
    } finally {
        Anim.Reset()
    }
}

Test_Anim_GatedCreatedWhileClosedStartsNoTimer() {
    r := AnimTRig()
    try {
        Anim.gateFn := () => false
        loopSteps := 0, tweenLog := [], done := 0
        Anim.Loop("pulse", 1000, (ph) => (loopSteps++))
        Anim.Tween("fade", 200, (p) => tweenLog.Push(p), () => (done++))
        AssertEq(r.timers.Length, 0, "no timer for gated entries behind a closed gate")
        AssertEq(tweenLog.Length, 1, "gated tween finished at once")
        AssertEq(tweenLog[1], 1.0, "...at p = 1")
        AssertEq(done, 1, "...with done")
        AssertEq(Anim.Active(), 1, "the loop waits, frozen")
        Anim.gateFn := () => true
        Anim.Wake()
        AssertEq(r.timers.Length, 1, "Wake starts the timer once the gate opens")
    } finally {
        Anim.Reset()
    }
}

Test_Anim_UngatedLoopRunsWhileGateClosed() {
    r := AnimTRig()
    try {
        Anim.gateFn := () => false
        free := [], gated := 0
        Anim.Loop("free", 1000, (ph) => free.Push(ph), false)
        Anim.Loop("gated", 1000, (ph) => (gated++))
        AssertEq(r.timers.Length, 1, "timer started for the ungated loop")
        for t in [250, 500] {
            r.clk.t := t
            Anim.Tick()
        }
        AssertEq(free.Length, 2, "ungated loop stepped on each tick")
        AssertTrue(Abs(free[1] - 0.25) < 0.001 && Abs(free[2] - 0.5) < 0.001, "ungated loop phases")
        AssertEq(gated, 0, "gated loop frozen")
        AssertEq(r.timers.Length, 1, "timer kept running")
        Anim.Stop("free")
        AssertEq(r.timers[r.timers.Length], 0, "timer stops once only the frozen gated loop is left")
    } finally {
        Anim.Reset()
    }
}
Test_Anim_Has() {
    r := AnimTRig()
    try {
        AssertEq(Anim.Has("x"), false, "nothing yet")
        Anim.Loop("x", 1000, (p) => 0)
        AssertEq(Anim.Has("x"), true, "loop running")
        Anim.Stop("x")
        AssertEq(Anim.Has("x"), false, "stopped")
        Anim.Tween("y", 100, (p) => 0)
        AssertEq(Anim.Has("y"), true, "tween running")
        r.clk.t := 100
        Anim.Tick()
        AssertEq(Anim.Has("y"), false, "tween finished")
    } finally Anim.Reset()
}
