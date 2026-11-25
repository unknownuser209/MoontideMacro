#Requires AutoHotkey v2.0
; ---------------------------------------------------------------------------
; ScreenDim: dims every monitor for the eyes only (dev copy, Dev tools page:
; [Dev] dim / dimPct). One black, see-through, click-through, never-focused
; window per monitor, marked WDA_EXCLUDEFROMCAPTURE (Windows 10 2004+): the
; macro's screen reads (BitBlt in Pixel / Screenshot / OCR) and desktop
; recorders (ffmpeg ddagrab, OBS display capture) do not see it at all, so
; reads and clips stay exactly as bright as the game (live 2026-11-25: reads
; at 90% dim 131 vs 129 / 137 bright; a ddagrab frame bright; grabs 15 ms
; with or without it).
; If Windows refuses that flag the window is destroyed at once and nothing
; is dimmed: a dim the reads could see would break every colour check.
; The dim fades in over FadeMs and out over FadeMs (a timer, never a wait:
; the macro goes on while it fades); the windows go once it is out.
;
;   ScreenDim.Apply(on, pct)  on: fade to pct (5..98 = how dark); off: fade
;                             out. Same values again: nothing done.
;                             -> "on" | "off" | "unsupported" (the flag was
;                             refused: undimmed)
;   ScreenDim.Off()           undim at once (no fade)
;   ScreenDim.Alpha(pct)      0..255 for the window
;   ScreenDim.Pct(v)          a setting value -> 5..98 (default 95)
;   ScreenDim.Step(ms)        one fade step of ms (the timer; tests call it)
; ---------------------------------------------------------------------------

class ScreenDim {
    static guis := []
    static Last := "off"
    static WDA_EXCLUDEFROMCAPTURE := 0x11
    static FadeMs := 10000             ; a full fade takes this long
    static TickMs := 50
    static _cur := 0                   ; alpha now
    static _target := 0                ; alpha it fades to
    static _from := 0                  ; alpha when this fade began
    static _timer := ""
    static TimerFn := ""               ; tests: (fn, ms) instead of SetTimer
    static MakeFn := ""                ; tests: () -> 1 instead of real windows

    static Pct(v) {
        if !IsNumber(v)
            return 95
        return Max(5, Min(98, Round(v + 0)))
    }

    static Alpha(pct) => Round(ScreenDim.Pct(pct) * 255 / 100)

    static Apply(on, pct := 95) {
        if !on {
            if ScreenDim.guis.Length
                ScreenDim._FadeTo(0)
            return ScreenDim.Last := "off"
        }
        a := ScreenDim.Alpha(pct)
        if !ScreenDim.guis.Length {
            ok := IsObject(ScreenDim.MakeFn) ? ScreenDim.MakeFn.Call() : ScreenDim._Make()
            if !ok
                return ScreenDim.Last := "unsupported"
            ScreenDim._cur := 0
        }
        ScreenDim._FadeTo(a)
        return ScreenDim.Last := "on"
    }

    ; one window per monitor, alpha 0; -> 1, or 0 (the capture flag refused)
    static _Make() {
        Loop MonitorGetCount() {
            MonitorGet(A_Index, &ml, &mt, &mr, &mb)
            ; +E0x20 click-through, +E0x08000000 never activated, layered by WinSetTransparent
            g := Gui("+AlwaysOnTop -Caption +ToolWindow -DPIScale +E0x08000020")
            g.BackColor := "000000"
            g.Show("x" ml " y" mt " w" (mr - ml) " h" (mb - mt) " NA Hide")
            if !DllCall("SetWindowDisplayAffinity", "Ptr", g.Hwnd, "UInt", ScreenDim.WDA_EXCLUDEFROMCAPTURE) {
                try g.Destroy()
                ScreenDim.Off()
                return 0
            }
            WinSetTransparent(0, g.Hwnd)
            g.Show("x" ml " y" mt " w" (mr - ml) " h" (mb - mt) " NA")
            ScreenDim.guis.Push(g)
        }
        return 1
    }

    ; a fade to alpha a over FadeMs (whatever the distance), from where it is
    static _FadeTo(a) {
        if (a = ScreenDim._target && (ScreenDim._timer != "" || ScreenDim._cur = a))
            return
        ScreenDim._target := a
        ScreenDim._from := ScreenDim._cur
        if (ScreenDim._timer = "") {
            ScreenDim._timer := ObjBindMethod(ScreenDim, "Step", ScreenDim.TickMs)
            ScreenDim._SetTimer(ScreenDim._timer, ScreenDim.TickMs)
        }
    }

    static _SetTimer(fn, ms) {
        if IsObject(ScreenDim.TimerFn)
            ScreenDim.TimerFn.Call(fn, ms)
        else
            SetTimer(fn, ms)
    }

    ; moves the alpha toward the target by ms / FadeMs of this fade's distance
    static Step(ms) {
        cur := ScreenDim._cur, tg := ScreenDim._target
        rate := Max(1, Abs(tg - ScreenDim._from)) * ms / ScreenDim.FadeMs
        cur := (cur < tg) ? Min(tg, cur + rate) : Max(tg, cur - rate)
        if (Abs(cur - tg) < 0.001)
            cur := tg                      ; exactly there (Min / Max hand back a float)
        ScreenDim._cur := cur
        for g in ScreenDim.guis
            try WinSetTransparent(Round(cur), g.Hwnd)
        if (cur != tg)
            return
        if (ScreenDim._timer != "") {
            ScreenDim._SetTimer(ScreenDim._timer, 0)
            ScreenDim._timer := ""
        }
        if (tg = 0)                        ; faded out: the windows go
            ScreenDim._Drop()
    }

    static _Drop() {
        for g in ScreenDim.guis
            try g.Destroy()
        ScreenDim.guis := []
        ScreenDim._cur := 0
    }

    static Off() {
        if (ScreenDim._timer != "") {
            ScreenDim._SetTimer(ScreenDim._timer, 0)
            ScreenDim._timer := ""
        }
        ScreenDim._target := 0
        ScreenDim._Drop()
        return ScreenDim.Last := "off"
    }
}
