#Requires AutoHotkey v2.0
; ScreenDim (dev copy: dim every monitor while the macro runs, invisible to
; the screen reads). The windows themselves are checked live (2026-11-25:
; reads at 90% dim 131 vs 129 / 137 bright, ffmpeg ddagrab bright too).
#Include ..\lib\ScreenDim.ahk

Test_ScreenDim_PctAndAlpha() {
    AssertEq(ScreenDim.Pct(60), 60, "as set")
    AssertEq(ScreenDim.Pct(0), 5, "at least 5")
    AssertEq(ScreenDim.Pct(150), 98, "at most 98 (never black)")
    AssertEq(ScreenDim.Pct("abc"), 95, "junk: the default")
    AssertEq(ScreenDim.Pct("75"), 75, "an ini string")
    AssertEq(ScreenDim.Alpha(100), 250, "98% of 255")
    AssertEq(ScreenDim.Alpha(40), 102, "40%")
}

Test_ScreenDim_OffWithoutWindows() {
    AssertEq(ScreenDim.Apply(false, 60), "off", "off is always fine")
    AssertEq(ScreenDim.guis.Length, 0, "no windows")
}

; fades (2026-11-25): in over FadeMs when the macro starts, out over FadeMs
; when it stops; the windows go once faded out. Timer and windows faked.
SdFake(&timers) {
    timers := []
    ScreenDim.TimerFn := (fn, ms) => timers.Push(ms)
    ScreenDim.MakeFn := () => (ScreenDim.guis := [{Hwnd: 0}], 1)
}
SdUnfake() {
    ScreenDim.TimerFn := "", ScreenDim.MakeFn := ""
    ScreenDim.Off()
}

Test_ScreenDim_FadesInAndOut() {
    SdFake(&timers)
    try {
        AssertEq(ScreenDim.Apply(true, 95), "on", "on")
        AssertEq(ScreenDim._cur, 0, "starts clear")
        AssertEq(timers[1], ScreenDim.TickMs, "a timer, no wait")
        ScreenDim.Step(ScreenDim.FadeMs / 2)
        AssertTrue(Abs(ScreenDim._cur - ScreenDim.Alpha(95) / 2) < 2, "half way after half the fade: " ScreenDim._cur)
        ScreenDim.Step(ScreenDim.FadeMs / 2)
        AssertEq(ScreenDim._cur, ScreenDim.Alpha(95), "full after FadeMs")
        AssertEq(timers[timers.Length], 0, "timer stopped")
        AssertEq(ScreenDim.Apply(true, 95), "on", "same again")
        AssertEq(timers.Length, 2, "no new fade")
        AssertEq(ScreenDim.Apply(false), "off", "off")
        AssertEq(ScreenDim.guis.Length, 1, "windows stay while it fades out")
        ScreenDim.Step(ScreenDim.FadeMs / 2)
        AssertTrue(ScreenDim._cur > 0, "still fading")
        ScreenDim.Step(ScreenDim.FadeMs / 2)
        AssertEq(ScreenDim._cur, 0, "clear after FadeMs")
        AssertEq(ScreenDim.guis.Length, 0, "windows gone")
    } finally
        SdUnfake()
}

Test_ScreenDim_TurnsBackMidFade() {
    SdFake(&timers)
    try {
        ScreenDim.Apply(true, 95)
        ScreenDim.Step(ScreenDim.FadeMs)
        ScreenDim.Apply(false)
        ScreenDim.Step(ScreenDim.FadeMs / 2)
        mid := ScreenDim._cur
        AssertEq(ScreenDim.Apply(true, 95), "on", "back on mid fade-out")
        AssertEq(ScreenDim.guis.Length, 1, "same windows")
        ScreenDim.Step(ScreenDim.FadeMs)
        AssertEq(ScreenDim._cur, ScreenDim.Alpha(95), "fades back up from " mid)
    } finally
        SdUnfake()
}

Test_ScreenDim_UnsupportedStaysBright() {
    SdFake(&timers)
    try {
        ScreenDim.MakeFn := () => 0
        AssertEq(ScreenDim.Apply(true, 95), "unsupported", "flag refused")
        AssertEq(ScreenDim.guis.Length, 0, "no windows")
        AssertEq(timers.Length, 0, "no fade")
    } finally
        SdUnfake()
}
