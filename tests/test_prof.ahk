#Requires AutoHotkey v2.0
; Tests for Prof (lib\Prof.ahk): where a task's time goes (speed work, 2026-11-17).
#Include ..\lib\Prof.ahk

Test_Prof_OffDoesNothing() {
    Prof.on := false
    Prof.Start("x"), Prof.Begin("wait"), Prof.End()
    AssertEq(Prof.Text(), "", "off: no line")
}

Test_Prof_ExclusiveAndContainers() {
    Prof.on := true
    try {
        Prof.Start("obby")
        Prof.Begin("ocr"), Sleep(40)
        Prof.Begin("wait"), Sleep(60), Prof.End()      ; the wait's time is not the ocr's
        Prof.End()
        Prof.Begin("walk")
        Prof.Begin("wait"), Sleep(60), Prof.End()      ; inside a walk: the walk keeps it
        Prof.End()
        t := Prof.Text()
        AssertTrue(RegExMatch(t, "^time: obby [\d.]+ s = "), "the line: " t)
        AssertTrue(InStr(t, "ocr 0.0 (1 reads)") || InStr(t, "ocr 0.1 (1 reads)"), "ocr about 40 ms, its count: " t)
        RegExMatch(t, "wait ([\d.]+)", &m)
        AssertTrue(IsObject(m) && m[1] + 0 <= 0.1, "only the one wait outside the walk counts: " t)
        RegExMatch(t, "walk ([\d.]+)", &m2)
        AssertTrue(IsObject(m2) && m2[1] + 0 >= 0.05, "the walk keeps its wait: " t)
        AssertTrue(InStr(t, ", other "), "the rest: " t)
        Prof.Stop()
        AssertEq(Prof.Text(), "", "stopped: no line")
    } finally {
        Prof.on := false, Prof.Stop()
    }
}

; speed (2026-11-17): Pixel.AnyIn grabs the grid's bounding rect once on the
; real screen (here a faked grabber standing in for it)
Test_Pixel_AnyInGrabsOnce() {
    g0 := Pixel._grabber, g00 := Pixel._grabber0, t00 := Pixel._getter0
    Pixel._getter0 := Pixel._getter         ; earlier tests may have swapped the getter
    calls := []
    fake := (x, y, w, h, dw := "", dh := "") => (calls.Push([x, y, w, h]), PxFakeRect(w, h, 1043 - x, 584 - y))
    Pixel._grabber := fake, Pixel._grabber0 := fake
    try {
        xs := FishLogic.Xs(1027, 1183, 8), rows := [568, 576, 584, 592]
        AssertEq(Pixel.AnyIn(xs, rows, 0xFFFFFF, 3), true, "the white sample at 1043,584 is found")
        AssertEq(calls.Length, 1, "one grab")
        AssertEq(calls[1][1] " " calls[1][2] " " calls[1][3] " " calls[1][4], "1027 568 " (1179 - 1027 + 1) " " (592 - 568 + 1), "the bounding rect")
        AssertEq(Pixel.AnyIn(xs, [568, 576], 0xFFFFFF, 3), false, "rows without it: none")
    } finally {
        Pixel._grabber := g0, Pixel._grabber0 := g00, Pixel._getter0 := t00
    }
}

; w x h black, one white pixel at (wx, wy)
PxFakeRect(w, h, wx, wy) {
    a := []
    a.Length := w * h
    Loop w * h
        a[A_Index] := 0
    if (wx >= 0 && wy >= 0 && wx < w && wy < h)
        a[wy * w + wx + 1] := 0xFFFFFF
    return a
}
