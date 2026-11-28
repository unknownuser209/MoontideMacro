#Requires AutoHotkey v2.0
#Include ..\lib\Screen.ahk
#Include ..\lib\Ocr.ahk
#Include ..\lib\Pixel.ahk
#Include ..\lib\Input.ahk
#Include ..\lib\TileDigits.ahk
#Include ..\lib\Calibrate.ahk
#Include ..\lib\tasks\BiomeItems.ahk
; ---------------------------------------------------------------------------
; Bug hunt 2026-11-27: design px vs screen px and Screen modes in the
; screen readers (Ocr hits at s = 1 off 2560x1440, TileDigits' box, the
; calibration wizard's colour, the Biome Selector's rect) and the Selector's
; "Drive not found" back-off. Real frames from tests\screens placed on a
; canvas of another client size / origin (GDI+ bicubic, as test_resample).
; Every test puts Screen back to identity.
; ---------------------------------------------------------------------------

; Frame src drawn as dw x dh at dx, dy on a black cw x ch canvas -> path of
; a PNG in A_Temp (made once per run): a client of another size, or a
; 2560x1440 client that does not start at 0,0 (a second monitor).
SfCanvas(src, cw, ch, dx, dy, dw, dh) {
    static made := Map()
    AssertTrue(FileExist(src), "frame " src " exists")
    dir := A_Temp "\vesper_screen_fixes"
    if !DirExist(dir)
        DirCreate(dir)
    SplitPath(src, , , , &stem)
    out := dir "\" stem "_" cw "x" ch "_" dx "_" dy "_" dw "x" dh ".png"
    if made.Has(out)
        return out
    DllCall("LoadLibrary", "Str", "gdiplus", "Ptr")
    si := Buffer(24, 0), NumPut("UInt", 1, si, 0)
    DllCall("gdiplus\GdiplusStartup", "Ptr*", &tok := 0, "Ptr", si, "Ptr", 0)
    bmp := 0, dst := 0, g := 0
    try {
        if DllCall("gdiplus\GdipCreateBitmapFromFile", "WStr", src, "Ptr*", &bmp) || !bmp
            throw Error("cannot load " src)
        DllCall("gdiplus\GdipCreateBitmapFromScan0", "Int", cw, "Int", ch, "Int", 0, "Int", 0x26200A, "Ptr", 0, "Ptr*", &dst)
        DllCall("gdiplus\GdipGetImageGraphicsContext", "Ptr", dst, "Ptr*", &g)
        DllCall("gdiplus\GdipGraphicsClear", "Ptr", g, "UInt", 0xFF000000)
        DllCall("gdiplus\GdipSetInterpolationMode", "Ptr", g, "Int", 7)        ; HighQualityBicubic
        DllCall("gdiplus\GdipSetPixelOffsetMode", "Ptr", g, "Int", 4)          ; HighQuality
        DllCall("gdiplus\GdipDrawImageRectI", "Ptr", g, "Ptr", bmp, "Int", dx, "Int", dy, "Int", dw, "Int", dh)
        clsid := Buffer(16, 0)
        DllCall("ole32\CLSIDFromString", "WStr", "{557CF406-1A04-11D3-9A73-0000F81EF32E}", "Ptr", clsid)
        if DllCall("gdiplus\GdipSaveImageToFile", "Ptr", dst, "WStr", out, "Ptr", clsid, "Ptr", 0)
            throw Error("cannot save " out)
    } finally {
        if g
            DllCall("gdiplus\GdipDeleteGraphics", "Ptr", g)
        if dst
            DllCall("gdiplus\GdipDisposeImage", "Ptr", dst)
        if bmp
            DllCall("gdiplus\GdipDisposeImage", "Ptr", bmp)
        DllCall("gdiplus\GdiplusShutdown", "Ptr", tok)
    }
    made[out] := true
    return out
}

; Ocr.FindWord on a saved frame (Ocr._srcFile), [Exit] in Input.ExitWide
SfExit(path) {
    b := Input.ExitWide
    Ocr._srcFile := path
    try
        return Ocr.FindWord(b.x, b.y, b.w, b.h, "i)\bexit\b", "i)exit", 2)
    finally
        Ocr._srcFile := ""
}

; screen-1: off 2560x1440 with Screen.s = 1 (a 3440x1440 ultrawide, a
; 2560x1600 screen, 1440p on a second monitor) FindWord gave SCREEN px:
; [Exit] at 688,156 / 512,173 / 3072,156, so Aura Collections was clicked
; beside its [Exit] and never closed (every respawn failed)
Test_ScreenFix_FindWordDesignPxAtScaleOne() {
    src := A_ScriptDir "\screens\collections_chat_052142.jpg"
    try {
        Screen.Reset()
        base := SfExit(src)
        AssertTrue(IsObject(base), "[Exit] reads at 2560x1440")
        for c in [[3440, 1440, 0, 0, 3440, 1440, "3440x1440"], [2560, 1600, 0, 0, 2560, 1600, "2560x1600"]
            , [5120, 1440, 2560, 0, 2560, 1440, "1440p on a second monitor"]] {
            p := SfCanvas(src, c[1], c[2], c[3], c[4], c[5], c[6])
            Screen.SetClient(c[3], c[4], c[5], c[6])
            AssertTrue(Screen.s = 1 && !Screen.IsIdentity(), c[7] ": the scale is 1, not the identity")
            r := SfExit(p)
            AssertTrue(IsObject(r), c[7] ": [Exit] reads")
            AssertTrue(Abs(r.x - base.x) <= 6 && Abs(r.y - base.y) <= 6
                , c[7] ": [Exit] in DESIGN px, " r.x "," r.y " (at 2560x1440: " base.x "," base.y ")")
            AssertTrue(r.l <= r.x && r.x <= r.r && r.t <= r.y && r.y <= r.b && r.r - r.l < 200
                , c[7] ": its box in design px too: " r.l "," r.t ".." r.r "," r.b)
            Screen.Reset()
        }
    } finally {
        Ocr._srcFile := ""
        Screen.Reset()
    }
}

; quests-1: TileDigits.Read took its box as SCREEN px, so off 2560x1440 at
; 0,0 (1080p, a second monitor) it read other pixels and the tile count of
; a potion fell back to the OCR that garbles 5-6 digit counts.
; tests\screens\inv_potion_grid_counts.png is the frame cut at 1090,640,
; inv_crack_searched_1440_x620_y360.png at 620,360 (count "x1").
; (At 1080p the box now lands on the count too, real frame
; inv_crack_searched_1080_x465_y270.png, but glyphs ~10 px tall match no
; template: "", the OCR fallback, as before.)
Test_ScreenFix_TileDigitsMapsTheDesignBox() {
    src := A_ScriptDir "\screens\inv_potion_grid_counts.png"
    rows := [[16, ["5", "14", "21", "80", "55"]], [152, ["1", "8", "90", "87", "77"]], [288, ["2037", "821", "550", "1057", "2036"]]]
    try {
        ; 2560x1440 whose top-left sits at screen -1090,-640 (the cut's
        ; origin: like Roblox on a monitor left of / above the primary)
        Ocr._srcFile := src
        Screen.SetClient(-1090, -640, 2560, 1440)
        for rr in rows
            for k, want in rr[2]
                AssertEq(TileDigits.Read(1095 + (k - 1) * 136, 640 + rr[1], 124, 34), want, "offset client: count " want)
        ; the preset's count box (1075,661 114x23 padded by CountPad) in
        ; mode "C", as PotionsTask._ReadCount reads it
        Ocr._srcFile := A_ScriptDir "\screens\inv_crack_searched_1440_x620_y360.png"
        Screen.SetClient(-620, -360, 2560, 1440)
        AssertEq(Screen.WithMode("C", () => TileDigits.Read(1070, 656, 124, 33)), "1", "the first tile's count box")
    } finally {
        Ocr._srcFile := ""
        Screen.Reset()
    }
}

; calib-3: the wizard maps a capture back in its window's mode (fisher_confirm:
; "C") but sampled its colour in "S": at 16:10 the colour came from ~8 px
; below the hovered pixel, the one Craft's purchase check reads
Test_ScreenFix_CalibrateSamplesTheHoveredPixel() {
    d := A_Temp "\vesper_sf_cal_" A_TickCount "_" Random(100000, 999999)
    DirCreate(d)
    old := Pixel._getter
    try {
        Calibrate.Use(d "\cal.json")
        Screen.SetClient(0, 0, 1920, 1200)
        hover := Screen.WithMode("C", () => Screen.Pt(1499, 821))     ; where Craft reads fisher_confirm
        Pixel._getter := (x, y) => (Abs(x - hover.x) <= 1 && Abs(y - hover.y) <= 1) ? 0x00FFFF : 0x101010
        s := Calibrate.NewSession(Calibrate.ResolveIds(["fisher_confirm"]))
        p := Calibrate.CaptureDesign("fisher_confirm", hover.x, hover.y)
        s.Capture(p.x, p.y)
        AssertEq(Format("0x{:06X}", Calibrate.Point("fisher_confirm").color), "0x00FFFF", "the hovered pixel's colour")
        AssertEq(Screen.Mode, "S", "the mode is left as it was")
    } finally {
        Pixel._getter := old
        Screen.Reset()
        Calibrate.Use(A_Temp "\vesper_cal_unused.json")
        try DirDelete(d, true)
    }
}

; biome-1: the Biome Selector is worked in mode "C" (BiomeItemsTask._Use)
; but its steps were recorded in "S": at 1920x1200 a list drawn at design
; y 515..931 was stored as 535..910 (10 % short), so its X was missed
Test_ScreenFix_SelectorRecordedInItsMode() {
    try {
        Screen.SetClient(0, 0, 1920, 1200)
        tl := Screen.WithMode("C", () => Screen.Pt(822, 515))
        br := Screen.WithMode("C", () => Screen.Pt(1494, 931))
        a := Calibrate.CaptureDesign("selector_list_rect", tl.x, tl.y)
        b := Calibrate.CaptureDesign("selector_list_rect", br.x, br.y)
        AssertTrue(Abs(a.x - 822) <= 2 && Abs(a.y - 515) <= 2 && Abs(b.x - 1494) <= 2 && Abs(b.y - 931) <= 2
            , "16:10 corners back to the design rect: " a.x "," a.y ".." b.x "," b.y)
        AssertEq(Calibrate.ModeOf("selector_list_rect") "," Calibrate.ModeOf("selector_confirm"), "C,C", "both Selector steps")
        AssertEq(Screen.Mode, "S", "the mode is left as it was")
    } finally
        Screen.Reset()
}

; biome-1: the between-tasks tidy (App._Tidy, mode "S") read and clicked
; the Selector with the stretched mapping, the task with "C"
Test_ScreenFix_TidyWorksTheSelectorInModeC() {
    m := BiMake(Map("BiomeItems.biomeSelector", 1, "BiomeItems.selectorDrive", "Abyss Curse Drive"), ["Biome Selector"], ["x"])
    m.ocr.selector := true
    m.ocr.pick := "Corrupt Ruin Drive"
    modes := Map()
    ocr := m.t._env.ocrFn
    m.t._env.ocrFn := (x, y, w, h, scale := 1) => (modes[Screen.Mode] := 1, ocr.Call(x, y, w, h, scale))
    clicks := Map()
    m.io.DefineProp("ClickHere", {call: (self) => (clicks[Screen.Mode] := 1, BiIO.Prototype.ClickHere.Call(self))})
    lo := m.t.Leftovers()[1]
    AssertTrue(lo.up.Call() != "", "seen")
    AssertEq(lo.close.Call("", SchedCtx()), 1, "closed")
    AssertTrue(modes.Count = 1 && modes.Has("C"), "every read in mode C (" BiSfKeys(modes) ")")
    AssertTrue(clicks.Count = 1 && clicks.Has("C"), "every click in mode C (" BiSfKeys(clicks) ")")
    AssertEq(Screen.Mode, "S", "the mode is left as it was")
}

BiSfKeys(m) {
    s := ""
    for k in m
        s .= (s = "" ? "" : ",") k
    return s
}

; biome-2: a Drive not found sent the errors webhook every time and kept
; whatever hold the last refusal left (10 min after a screen stop): an
; errors webhook and an inventory + Selector opened every 10-30 min all
; night. Now as a refusal: held MissingRetryMin, doubled per one in a row,
; reported once
Test_ScreenFix_DriveNotFoundBacksOffAndReportsOnce() {
    m := BiMake(Map("BiomeItems.biomeSelector", 1, "BiomeItems.selectorDrive", "Unknown Void Drive"), ["Biome Selector"], ["Select a biome using a Drive"])
    m.ocr.rowsBlank := true                     ; no row reads: the Drive is never found
    holds := []
    Loop 3 {
        AssertEq(m.t.Run(SchedCtx()), 0, "not found " A_Index)
        AssertEq(m.ocr.selector, false, "the Selector closed " A_Index)
        wait := 0
        while !m.t.CanRun(BiState()) && wait < 1000 {
            m.clk.t += 60000
            wait++
        }
        holds.Push(wait)
    }
    exp := [30, 60, 120]
    for i, w in holds
        AssertTrue(w >= exp[i] && w <= exp[i] + 1, "hold " i ": " w " min, expected " exp[i])
    AssertEq(m.wh.Count("errors"), 1, "the errors webhook only for the first")
    ; after a screen stop (10 min hold) a Drive not found holds a full one
    m2 := BiMake(Map("BiomeItems.biomeSelector", 1, "BiomeItems.selectorDrive", "Unknown Void Drive"), ["Biome Selector"], ["Select a biome using a Drive"])
    m2.ocr.noOpen := true
    AssertEq(m2.t.Run(SchedCtx()), 0, "stopped by the screen")
    m2.clk.t += (BiomeItemsTask.ScreenRetryMin + 1) * 60000
    m2.ocr.noOpen := false, m2.ocr.rowsBlank := true
    AssertTrue(m2.t.CanRun(BiState()), "tried again after the screen hold")
    AssertEq(m2.t.Run(SchedCtx()), 0, "not found")
    AssertEq(m2.t._holdMs["biomeSelector"], BiomeItemsTask.MissingRetryMin * 60000, "a full hold, not the screen stop's")
    ; found and used at last: the back-off starts over
    m.ocr.rowsBlank := false
    AssertEq(m.t.Run(SchedCtx()), 1, "used")
    AssertEq(m.t._fails.Has("biomeSelector"), false, "no refusals left after a use")
}
