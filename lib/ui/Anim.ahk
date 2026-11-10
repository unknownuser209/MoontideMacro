#Requires AutoHotkey v2.0
; ---------------------------------------------------------------------------
; Anim: the UI animation engine. ONE shared timer drives every tween and loop.
;
;   Anim.Ease(t)                   cubic ease-out of t (clamped to 0..1).
;   Anim.Lerp(a, b, t)             a + (b - a) * t, as a Float.
;   Anim.Tween(key, ms, stepFn, doneFn := "", gated := true)
;                                  stepFn.Call(p) with the eased progress p
;                                  (0..1) each frame, then doneFn.Call() once.
;                                  A new tween on the same key replaces the old
;                                  one: the old one gets stepFn(1) first (its
;                                  doneFn is NOT called).
;   Anim.Loop(key, periodMs, stepFn, gated := true)
;                                  stepFn.Call(phase), phase 0..1 repeating,
;                                  until Anim.Stop(key). A loop on an existing
;                                  key replaces it.
;   Anim.Stop(key)                 drop a tween or loop without stepping it.
;   Anim.Tick()                    advance everything (the shared timer calls it).
;   Anim.Wake()                   restart the timer after the gate reopens (see Gating).
;   Anim.Active()                  number of running tweens + loops.
;   Anim.Has(key)                  true while a tween or loop runs on key.
;   Anim.Reset()                   stop everything and restore the defaults (tests).
;   Anim.FrameMs := 33             timer period.
;
; Gating: a GATED animation (the default) follows Anim.gateFn (the Dashboard
; sets it to "window visible and not minimized"). While the gate is closed a
; gated tween is finished at the next Tick (step(1), done) and a gated loop is
; frozen at its current phase and not stepped. UNGATED animations (the
; splash screen) keep running while the gate is closed.
; Both kinds obey Anim.enabledFn (UI.animations): when it is false a Tween
; steps to 1 and finishes at once, and a Loop steps to phase 0 once and does
; not run; anything already running settles the same way at the next Tick.
;
; The timer starts with the first Tween/Loop and stops (timerFn(fn, 0)) when
; nothing needs it: no animations left, or the gate is closed and only gated
; loops remain. It is restarted by the next Tween/Loop call or by Anim.Wake().
; A gated Tween created while the gate is closed finishes at once; a gated Loop
; created then waits (frozen, no timer) for Wake().
;
; Injectables (tests replace them): nowFn, timerFn, gateFn, enabledFn.
; ---------------------------------------------------------------------------

class Anim {
    static FrameMs := 33
    static nowFn := () => A_TickCount
    static timerFn := (fn, ms) => SetTimer(fn, ms)
    static gateFn := () => true
    static enabledFn := () => true
    static items := Map()       ; key -> {loop, gated, start, span, step, done}
    static running := false
    static tickCb := (*) => Anim.Tick()

    static Ease(t) {
        if (t < 0)
            t := 0
        else if (t > 1)
            t := 1
        return 1.0 - (1.0 - t) ** 3
    }

    static Lerp(a, b, t) => a + (b - a) * t + 0.0

    static Tween(key, ms, stepFn, doneFn := "", gated := true) {
        this.Replace(key)
        if (!this.enabledFn.Call() || (gated && !this.gateFn.Call())) {
            stepFn.Call(1.0)
            if IsObject(doneFn)
                doneFn.Call()
            this.Sync()
            return
        }
        this.items[key] := {loop: false, gated: gated, start: this.nowFn.Call(), span: ms, step: stepFn, done: doneFn}
        this.Start()
    }

    static Loop(key, periodMs, stepFn, gated := true) {
        this.Replace(key)
        if !this.enabledFn.Call() {
            stepFn.Call(0)
            this.Sync()
            return
        }
        this.items[key] := {loop: true, gated: gated, start: this.nowFn.Call(), span: periodMs, step: stepFn, done: ""}
        this.Start()
    }

    static Stop(key) {
        if this.items.Has(key) {
            this.items.Delete(key)
            this.Sync()
        }
    }

    static Active() => this.items.Count

    static Has(key) => this.items.Has(key)

    static Tick() {
        now := this.nowFn.Call()
        open := this.gateFn.Call()
        enabled := this.enabledFn.Call()
        keys := []
        for k in this.items
            keys.Push(k)
        for k in keys {
            e := this.items.Has(k) ? this.items[k] : ""
            if !IsObject(e)     ; removed by an earlier callback in this Tick
                continue
            if e.loop {
                if !enabled {
                    this.items.Delete(k)
                    e.step.Call(0)
                } else if (open || !e.gated) {
                    e.step.Call(e.span > 0 ? Mod(now - e.start, e.span) / e.span : 0.0)
                }
            } else {
                t := e.span > 0 ? (now - e.start) / e.span : 1
                if (t >= 1 || !enabled || (e.gated && !open)) {
                    this.items.Delete(k)
                    e.step.Call(1.0)
                    if IsObject(e.done)
                        e.done.Call()
                } else {
                    e.step.Call(this.Ease(t))
                }
            }
        }
        this.Sync()
    }

    static Reset() {
        if this.running
            this.timerFn.Call(this.tickCb, 0)
        this.running := false
        this.items := Map()
        this.FrameMs := 33
        this.nowFn := () => A_TickCount
        this.timerFn := (fn, ms) => SetTimer(fn, ms)
        this.gateFn := () => true
        this.enabledFn := () => true
    }

    ; A new animation on `key` finishes the old tween there (loops just stop).
    static Replace(key) {
        if !this.items.Has(key)
            return
        old := this.items[key]
        this.items.Delete(key)
        if !old.loop
            old.step.Call(1.0)
    }

    ; Call when the gate reopens (the Dashboard's show/restore/activate handler):
    ; restarts the timer for loops frozen by a closed gate. Does nothing when
    ; the timer already runs, nothing is active, or the gate is still closed
    ; with only gated entries left.
    static Wake() {
        this.Start()
    }

    ; Does anything need the timer? Any tween (a gated one is finished by the next
    ; Tick), any ungated loop, or any loop while the gate is open.
    static Needed() {
        open := this.gateFn.Call()
        for k, e in this.items {
            if (!e.loop || !e.gated || open)
                return true
        }
        return false
    }

    static Start() {
        if (this.running || !this.Needed())
            return
        this.running := true
        this.timerFn.Call(this.tickCb, this.FrameMs)
    }

    ; Stop the timer when nothing needs it any more.
    static Sync() {
        if (!this.running || this.Needed())
            return
        this.running := false
        this.timerFn.Call(this.tickCb, 0)
    }
}
