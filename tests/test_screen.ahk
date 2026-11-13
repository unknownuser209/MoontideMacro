#Requires AutoHotkey v2.0
#Include ..\lib\Screen.ahk
#Include ..\lib\Roblox.ahk
#Include ..\lib\Pixel.ahk
#Include ..\lib\Ocr.ahk
#Include ..\lib\Input.ahk
#Include ..\lib\Calibrate.ahk
#Include ..\lib\tasks\FishLogic.ahk
; ---------------------------------------------------------------------------
; Screen mapper (design 2560x1440 -> the fullscreen Roblox client), the
; fullscreen gate, and the lowest layers routed through it (Pixel, Ocr,
; Input's real io, Calibrate capture). Every test puts Screen back to
; identity (ScrnAt restores it), so the rest of the suite runs at 2560x1440.
; ---------------------------------------------------------------------------

; Runs fn() with the client at x, y, w, h; identity afterwards, always.
ScrnAt(x, y, w, h, fn) {
    Screen.SetClient(x, y, w, h)
    try
        return fn()
    finally
        Screen.Reset()
}

ScrnPtIs(p, x, y, name) {
    AssertEq(p.x, x, name " x")
    AssertEq(p.y, y, name " y")
}

ScrnRectIs(r, x, y, w, h, name) {
    AssertEq(r.x " " r.y " " r.w " " r.h, x " " y " " w " " h, name)
}

Test_Screen_IdentityAt1440IsUnchanged() {
    Screen.Reset()
    AssertEq(Screen.IsIdentity(), true, "default is identity")
    ; no rounding at all: floats and odd values pass through untouched
    p := Screen.Pt(1280.5, 7.25)
    AssertEq(p.x, 1280.5, "float x as is")
    AssertEq(p.y, 7.25, "float y as is")
    r := Screen.Rect({x: 900, y: 500, w: 800, h: 80, scale: 2})
    ScrnRectIs(r, 900, 500, 800, 80, "rect as is")
    AssertEq(r.scale, 2, "extra props kept")
    AssertEq(Screen.Len(25), 25, "len as is")
    q := Screen.Inv(1886.5, 393)
    AssertEq(q.x " " q.y, "1886.5 393", "inv as is")
    AssertEq(Screen.OcrScale(3), 3, "ocr scale as is")
    for a in ["L", "R", "T", "B", "BR"]
        ScrnPtIs(Screen.Pt(100, 200, a), 100, 200, "anchor " a)
}

Test_Screen_1920x1080() {
    ScrnAt(0, 0, 1920, 1080, () => (
        AssertEq(Screen.s, 0.75, "scale"),
        ScrnPtIs(Screen.Pt(1280, 720), 960, 540, "centre"),
        ScrnPtIs(Screen.Pt(1000, 400), 750, 300, "point"),
        ScrnRectIs(Screen.Rect({x: 900, y: 500, w: 800, h: 80}), 675, 375, 600, 60, "rect"),
        ScrnRectIs(Screen.Rect(900, 500, 800, 80), 675, 375, 600, 60, "rect args"),
        ScrnPtIs(Screen.Inv(750, 300), 1000, 400, "inverse"),
        AssertEq(Screen.Len(40), 30, "len"),
        AssertEq(Screen.OcrScale(1), 1 / 0.75, "ocr scale up"),
        ScrnPtIs(Screen.Pt(2500, 50, "R"), 1875, 38, "R anchor = C on 16:9")
    ))
}

Test_Screen_3840x2160() {
    ScrnAt(0, 0, 3840, 2160, () => (
        AssertEq(Screen.s, 1.5, "scale"),
        ScrnPtIs(Screen.Pt(1000, 400), 1500, 600, "point"),
        ScrnRectIs(Screen.Rect({x: 900, y: 500, w: 800, h: 80}), 1350, 750, 1200, 120, "rect"),
        ScrnPtIs(Screen.Inv(1500, 600), 1000, 400, "inverse"),
        AssertEq(Screen.OcrScale(1), 1 / 1.5, "ocr shrinks to the design size")
    ))
}

Test_Screen_1366x768() {
    ; 1366 is not exactly 16:9: s = 768/1440, the box (1365.3 wide) centred
    ScrnAt(0, 0, 1366, 768, () => (
        AssertEq(Round(Screen.s, 5), Round(768 / 1440, 5), "scale by height"),
        ScrnPtIs(Screen.Pt(1280, 720), 683, 384, "centre"),
        ScrnPtIs(Screen.Pt(2560, 1440), 1366, 768, "bottom right corner"),
        ScrnPtIs(Screen.Pt(0, 0), 0, 0, "top left corner"),
        ScrnRectIs(Screen.Rect({x: 900, y: 500, w: 800, h: 80}), 480, 267, 427, 42, "rect"),
        ScrnPtIs(Screen.Inv(683, 384), 1280, 720, "inverse centre")
    ))
}

; Sol's RNG stretches its UI to the client (x by W/2560, y by H/1440;
; live 1440x900, 2026-11-11): no letterbox, anchors move nothing
Test_Screen_Ultrawide3440x1440() {
    ScrnAt(0, 0, 3440, 1440, () => (
        AssertTrue(Screen.s = 1, "lengths at the smaller scale (height)"),
        ScrnPtIs(Screen.Pt(1280, 720), 1720, 720, "centre"),
        ScrnPtIs(Screen.Pt(100, 50, "L"), 134, 50, "x stretched (anchor ignored)"),
        ScrnPtIs(Screen.Pt(2560, 1440), 3440, 1440, "corner to corner"),
        ScrnPtIs(Screen.Inv(1720, 720), 1280, 720, "inverse"),
        AssertTrue(Screen.OcrScale(2) = 2, "same OCR scale")
    ))
}

Test_Screen_16by10() {
    ScrnAt(0, 0, 1440, 900, () => (
        AssertTrue(Abs(Screen.sx - 0.5625) < 0.0001, "x by width"),
        AssertTrue(Abs(Screen.sy - 0.625) < 0.0001, "y by height"),
        ; the Fishing Shop measured live: design 576..1984 x 322..1113
        ScrnRectIs(Screen.Rect({x: 576, y: 322, w: 1408, h: 791}), 324, 201, 792, 495, "the shop as measured (323..1116 x 202..697)"),
        ScrnPtIs(Screen.Inv(720, 450), 1280, 720, "inverse centre")
    ))
    ScrnAt(0, 0, 2560, 1600, () => (
        AssertTrue(Screen.s = 1, "lengths by width"),
        ScrnPtIs(Screen.Pt(1280, 720), 1280, 800, "centre"),
        ScrnPtIs(Screen.Pt(10, 1430, "B"), 10, 1589, "y stretched (anchor ignored)")
    ))
}

Test_Screen_SecondMonitorOrigin() {
    ; fullscreen on a monitor left of the primary one: origin -1920,0
    ScrnAt(-1920, 0, 1920, 1080, () => (
        ScrnPtIs(Screen.Pt(1000, 400), -1170, 300, "point"),
        ScrnPtIs(Screen.Inv(-1170, 300), 1000, 400, "inverse"),
        AssertEq(Screen.Verified(), true, "1920x1080 is a tested size")
    ))
    ; 2560x1440 on a second monitor: same size, so no scaling, only the shift
    ScrnAt(2560, 0, 2560, 1440, () => (
        ScrnPtIs(Screen.Pt(1000, 400), 3560, 400, "shifted"),
        AssertEq(Screen.Verified(), true, "verified size")
    ))
}

Test_Screen_RoundTripEveryDesignPointAt1080() {
    ; screen -> design -> screen lands on the same screen pixel (calibration)
    ScrnAt(0, 0, 1920, 1080, () => ScrnRoundTrip())
    ScrnAt(0, 0, 1366, 768, () => ScrnRoundTrip())
    ScrnAt(0, 0, 1440, 900, () => ScrnRoundTrip())    ; (above 1:1 not every screen px has a design px)
}

ScrnRoundTrip() {
    for sx in [0, 1, 393, 959, 1414, Screen.cw - 1]
        for sy in [0, 7, 295, 540, Screen.ch - 1] {
            d := Screen.Inv(sx, sy)
            p := Screen.Pt(d.x, d.y)
            AssertEq(p.x " " p.y, sx " " sy, Screen.cw "x" Screen.ch " round trip " sx "," sy)
        }
}

Test_Screen_DescribeNamesSizeAndVerified() {
    AssertTrue(InStr(Screen.Describe(), "2560x1440"), "size at identity")
    AssertTrue(!InStr(Screen.Describe(), "verified"), "no warning at 2560x1440")
    ScrnAt(0, 0, 1920, 1080, () => (
        AssertTrue(InStr(Screen.Describe(), "1920x1080"), "size"),
        AssertTrue(!InStr(Screen.Describe(), "not tested"), "a tested size: no warning"),
        AssertEq(Screen.SizeText(), "1920x1080 (x0.75)", "size text")
    ))
}

; ---- the fullscreen gate ---------------------------------------------------

Test_Roblox_CoversMonitor() {
    AssertEq(Roblox.CoversMonitor(0, 0, 2560, 1440, 0, 0, 2560, 1440), true, "1440p fullscreen")
    AssertEq(Roblox.CoversMonitor(0, 0, 1920, 1080, 0, 0, 1920, 1080), true, "1080p fullscreen")
    AssertEq(Roblox.CoversMonitor(0, 0, 3840, 2160, 0, 0, 3840, 2160), true, "4K fullscreen")
    AssertEq(Roblox.CoversMonitor(0, 0, 3440, 1440, 0, 0, 3440, 1440), true, "ultrawide fullscreen")
    AssertEq(Roblox.CoversMonitor(-1920, 0, 1920, 1080, -1920, 0, 1920, 1080), true, "second monitor")
    AssertEq(Roblox.CoversMonitor(8, 31, 1904, 1009, 0, 0, 1920, 1080), false, "windowed (maximized)")
    AssertEq(Roblox.CoversMonitor(100, 100, 1280, 720, 0, 0, 2560, 1440), false, "small window")
    AssertEq(Roblox.CoversMonitor(0, 0, 2560, 1400, 0, 0, 2560, 1440), false, "taskbar showing")
    AssertEq(Roblox.CoversMonitor(0, 0, 0, 0, 0, 0, 0, 0), false, "minimized (no client)")
    AssertTrue(Type(Roblox.Hwnd()) = "Integer", "Hwnd returns integer")
}

; ---- lowest layers through the mapper (fakes) ------------------------------

Test_Screen_PixelGetMapsDesignPoints() {
    seen := []
    old := Pixel._getter
    Pixel._getter := (x, y) => (seen.Push(x "," y), 0xFFFFFF)
    try {
        Pixel.Get(1000, 400)
        ScrnAt(0, 0, 1920, 1080, () => (Pixel.Get(1000, 400), Pixel.Is(1280, 720, 0xFFFFFF)))
    } finally
        Pixel._getter := old
    AssertEq(seen[1], "1000,400", "identity untouched")
    AssertEq(seen[2], "750,300", "1080p mapped")
    AssertEq(seen[3], "960,540", "Is mapped")
}

Test_Screen_PixelGrabStaysDesignSized() {
    calls := []
    old := Pixel._grabber
    ; a screen whose pixel is white when screen x >= 750
    Pixel._grabber := (x, y, w, h, dw := "", dh := "") => ScrnFakeGrab(calls, x, y, w, h, dw, dh)
    try {
        a := Pixel.Grab(990, 400, 20, 8)
        b := ScrnAt(0, 0, 1920, 1080, () => Pixel.Grab(990, 400, 20, 8))
    } finally
        Pixel._grabber := old
    AssertEq(calls[1], "990,400,20,8,,", "identity: the old 4-arg call")
    AssertEq(calls[2], "743,300,15,6,20,8", "1080p: screen rect, design size")
    AssertEq(a.Length, 160, "identity size")
    AssertEq(b.Length, 160, "design-sized array at 1080p")
}

ScrnFakeGrab(calls, x, y, w, h, dw, dh) {
    calls.Push(x "," y "," w "," h "," dw "," dh)
    n := (dw != "" ? dw * dh : w * h)
    out := []
    Loop n
        out.Push(0)
    return out
}

Test_Screen_StripGrabMapsSamples() {
    m := StripGrab.Map(1000, 1012, [400, 720], 4)
    AssertEq(m.xs.Length " " m.xs[1] " " m.xs[4] " " m.ys[2], "4 1000 1012 720", "identity: design = screen")
    ScrnAt(0, 0, 1920, 1080, () => (
        m := StripGrab.Map(1000, 1012, [400, 720], 4),
        AssertEq(m.xs.Length, 4, "same sample count (design stride)"),
        AssertEq(m.xs[1] " " m.xs[2] " " m.xs[4] " " m.ys[1] " " m.ys[2], "750 753 759 300 540", "mapped samples")
    ))
}

; a held copy read at the mapped pixels (the copy itself is screen px)
Test_Screen_ScreenFrameReadsMappedPixels() {
    fr := ScreenFrame()
    fr.Hold()
    if (fr._w < 1920 || fr._h < 1080)
        return                                  ; a smaller main monitor: nothing to check
    NumPut("UInt", 0xFF112233, fr._bits, 300 * fr._w * 4 + 750 * 4)
    NumPut("UInt", 0xFF445566, fr._bits, 300 * fr._w * 4 + 753 * 4)
    rows := ScrnAt(0, 0, 1920, 1080, () => fr(1000, 1004, [400], 4))
    AssertEq(Format("{:06x} {:06x}", rows[1][1], rows[1][2]), "112233 445566", "design 1000 / 1004 -> screen 750 / 753")
    fr.Let()
}

Test_Screen_InputIoMapsMoves() {
    ; InputScreenIO itself moves the real mouse, so test its mapping helper
    AssertEq(InputScreenIO.Map(1000, 400).x, 1000, "identity x")
    ScrnAt(0, 0, 1920, 1080, () => (
        ScrnPtIs(InputScreenIO.Map(1000, 400), 750, 300, "1080p move"),
        ScrnPtIs(InputScreenIO.Unmap(750, 300), 1000, 400, "1080p mouse pos")
    ))
}

Test_Screen_CalibrationRoundTripAt1080() {
    path := A_Temp "\vesper_cal_screen_test.json"
    try FileDelete(path)
    Calibrate.Use(path)
    try {
        ; the user hovers screen 1414,295 on a 1920x1080 Roblox: stored /0.75
        ScrnAt(0, 0, 1920, 1080, () => Calibrate.SetPoint("cauldron_add", Calibrate.ToDesign(1414, 295).x, Calibrate.ToDesign(1414, 295).y, 0xFFFFFF))
        p := Calibrate.Point("cauldron_add")
        ScrnPtIs(p, 1885, 393, "stored in design space")
        ; and read back at 1080p it lands where the user pointed
        ScrnAt(0, 0, 1920, 1080, () => ScrnPtIs(Screen.Pt(p.x, p.y), 1414, 295, "back on the user's pixel"))
        ; at 2560x1440 the same entry is used as is (old files stay valid)
        ScrnPtIs(Screen.Pt(p.x, p.y), 1885, 393, "identity")
        txt := FileRead(path, "UTF-8")
        AssertTrue(InStr(txt, '"version":2') || InStr(txt, '"version": 2'), "version 2 written")
        AssertTrue(InStr(txt, "design"), "design space noted")
    } finally {
        try FileDelete(path)
        Calibrate.Use(A_Temp "\vesper_cal_unused.json")
    }
}

; ---- App: the gate and the display note ------------------------------------

class ScrnFakeRoblox extends AppFakeRoblox {
    __New(size, verified) {
        super.__New()
        this._size := size, this._ver := verified
    }
    Describe() => "Roblox client " this._size
    Verified() => this._ver
    SizeText() => this._size
}

Test_App_OtherFullscreenSizeRunsWithNote() {
    t := AppTestMake()
    t.app.roblox := ScrnFakeRoblox("1920x1080 (x0.75)", false)
    t.app.Start()
    AssertEq(t.ui.status.state, "Running", "a fullscreen 1080p client runs")
    AssertTrue(InStr(t.ui.status.task, "1920x1080") && InStr(t.ui.status.task, "not tested at this size"), "status names the size and that it is untested")
    t.app.Tick()
    n := 0
    for l in t.ui.logs
        n += InStr(l, "Display: Roblox client 1920x1080") ? 1 : 0
    AssertEq(n, 1, "display self-check logged once")
}

Test_App_VerifiedSizeHasNoNote() {
    t := AppTestMake()
    t.app.roblox := ScrnFakeRoblox("2560x1440", true)
    t.app.Start()
    AssertTrue(!InStr(t.ui.status.task, "verified"), "no note at 2560x1440")
}

Test_App_WindowedPausesNeedsFullscreen() {
    t := AppTestMake()
    t.rb.fs := false
    t.app.Start()
    AssertEq(t.ui.status.state, "Paused", "windowed / minimized pauses")
    AssertEq(t.ui.status.task, "Roblox not fullscreen", "clear status")
    found := false
    for l in t.ui.logs
        found := found || InStr(l, "Moontide needs Roblox fullscreen")
    AssertTrue(found, "the log says what to do")
}

; panel modes at 16:10, as measured live at 1440x900 (2026-11-11)
Test_Screen_PanelModes16by10() {
    ScrnAt(0, 0, 1440, 900, () => (
        ; Aura Storage: design 640..1920 x 369..1071 -> 360..1080 x 252..646 (centred, even)
        Screen.WithMode("C", () => ScrnRectIs(Screen.Rect({x: 640, y: 369, w: 1280, h: 702}), 360, 253, 720, 394, "C: the storage")),
        ; the quest panel's Claim button (design 2169,1081) -> inside 1137..1261 x 640..672
        Screen.WithMode("RH", () => (p := Screen.Pt(2169, 1081), AssertTrue(p.x >= 1137 && p.x <= 1261 && p.y >= 640 && p.y <= 680, "RH: Claim at " p.x "," p.y))),
        ScrnPtIs(Screen.Pt(1000, 400), 563, 250, "back to S after WithMode"),
        Screen.WithMode("C", () => ScrnPtIs(Screen.Inv(720, 450), 1280, 720, "C inverse")),
        Screen.WithMode("RH", () => (q := Screen.Inv(Screen.X(2300), Screen.Y(900)), AssertTrue(Abs(q.x - 2300) <= 1 && Abs(q.y - 900) <= 1, "RH round trip")))
    ))
    ; 16:9: every mode is the same pixel
    ScrnAt(0, 0, 1920, 1080, () => (
        Screen.WithMode("C", () => ScrnPtIs(Screen.Pt(2169, 1081), 1627, 811, "C at 16:9")),
        Screen.WithMode("RH", () => ScrnPtIs(Screen.Pt(2169, 1081), 1627, 811, "RH at 16:9")),
        ScrnPtIs(Screen.Pt(2169, 1081), 1627, 811, "S at 16:9")
    ))
}

; The HDR self-check never throws and says one of three things (whatever this
; PC's display is set to).
Test_Screen_HdrCheckAnswers() {
    h := Screen.HdrOn()
    AssertTrue(h = 1 || h = 0 || h = "", "1, 0 or unknown (" h ")")
    t := Screen.HdrText()
    AssertTrue(t = "HDR on" || t = "HDR off" || t = "HDR unknown", t)
}
