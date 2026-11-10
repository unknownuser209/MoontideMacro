#Requires AutoHotkey v2.0
#Include ..\lib\Screen.ahk
#Include ..\lib\Ocr.ahk
#Include ..\lib\Pixel.ahk
#Include ..\lib\tasks\Obby.ahk
#Include ..\lib\tasks\Merchant.ahk
#Include ..\lib\tasks\MemoryMatch.ahk
; ---------------------------------------------------------------------------
; Other resolutions on REAL frames: tests\screens (2560x1440 clips) scaled
; to another fullscreen size (GDI+ high-quality bicubic, a stand-in for the
; game drawing at that size), then read by the tasks' own DESIGN-space boxes
; through Screen (Ocr / Pixel map them to the smaller client).
;
; Results (2026-11-10), 20 reads per size (RsChecks):
;   3840x2160: all read (the crop is shrunk to the design size).
;   1366x768:  all read.
;   1920x1080: all but two: Mari's name on mari_day_buttons (reads nothing at
;              the 2.67 stretch; 1x and 2x read "Mori") and Memory Match's
;              "Start" (1.33 reads "Sturt"; 2x and 4x read it). Pinned below
;              as known misses so a change shows. Whole-number stretches
;              were measured too and missed more (5 over the sizes; see
;              Screen.OcrScale). Real game frames at 1080p (drawn at that
;              size, not scaled down) are still to be checked.
;   Rect grabs (Pixel.Grab): the inventory title box's signature at 1080p is
;   within 2 of the 1440 one.
; ---------------------------------------------------------------------------

; Frame `name` (tests\screens, .jpg unless the name has an extension)
; scaled by f -> path of a PNG in A_Temp (made once per run).
RsFrame(name, f) {
    static made := Map()
    src := A_ScriptDir "\screens\" (InStr(name, ".") ? name : name ".jpg")
    AssertTrue(FileExist(src), "frame " name " exists")
    dir := A_Temp "\vesper_resample"
    if !DirExist(dir)
        DirCreate(dir)
    out := dir "\" RegExReplace(name, "\.\w+$") "_" Round(f * 10000) ".png"
    if !made.Has(out) {
        RsScaleImage(src, out, f)
        made[out] := true
    }
    return out
}

RsScaleImage(src, out, f) {
    DllCall("LoadLibrary", "Str", "gdiplus", "Ptr")
    si := Buffer(24, 0), NumPut("UInt", 1, si, 0)
    DllCall("gdiplus\GdiplusStartup", "Ptr*", &tok := 0, "Ptr", si, "Ptr", 0)
    bmp := 0, dst := 0, g := 0
    try {
        if DllCall("gdiplus\GdipCreateBitmapFromFile", "WStr", src, "Ptr*", &bmp) || !bmp
            throw Error("cannot load " src)
        DllCall("gdiplus\GdipGetImageWidth", "Ptr", bmp, "UInt*", &w := 0)
        DllCall("gdiplus\GdipGetImageHeight", "Ptr", bmp, "UInt*", &h := 0)
        w2 := Round(w * f), h2 := Round(h * f)
        DllCall("gdiplus\GdipCreateBitmapFromScan0", "Int", w2, "Int", h2, "Int", 0, "Int", 0x26200A, "Ptr", 0, "Ptr*", &dst)
        DllCall("gdiplus\GdipGetImageGraphicsContext", "Ptr", dst, "Ptr*", &g)
        DllCall("gdiplus\GdipSetInterpolationMode", "Ptr", g, "Int", 7)        ; HighQualityBicubic
        DllCall("gdiplus\GdipSetPixelOffsetMode", "Ptr", g, "Int", 4)          ; HighQuality
        DllCall("gdiplus\GdipDrawImageRectI", "Ptr", g, "Ptr", bmp, "Int", 0, "Int", 0, "Int", w2, "Int", h2)
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
}

; Screen at a fullscreen client cw x ch whose design point (ox, oy) is the
; image's 0,0 (a crop taken at ox, oy of the 2560x1440 frame). Callers
; Screen.Reset() in finally.
RsAt(cw, ch, ox := 0, oy := 0) {
    s := Min(ch / 1440, cw / 2560)
    Screen.SetClient(-Round(ox * s), -Round(oy * s), cw, ch)
}

RsRead(path, r, scale := 1) => Ocr.ReadFile(path, r.x, r.y, r.w, r.h, scale)

RsOcrFn(p) => (x, y, w, h, scale := 1) => Ocr.ReadFile(p, x, y, w, h, scale)

; the checks, run at a client size; f = cw / 2560. -> Array of failed names
RsChecks(cw, ch) {
    f := cw / 2560
    bad := []
    try {
        RsAt(cw, ch)
        ; inventory open: the tabs (TaskEnv.InvOpen) and the title
        for name in ["inventory_open_sand", "inventory_open_rainy", "inventory_open_day"] {
            p := RsFrame(name, f)
            if !TaskEnv({ocr: RsOcrFn(p)}).InvOpen({x: 1684, y: 445})
                bad.Push(name " tabs")
            if !RegExMatch(RsRead(p, ObbyTask.InvBox), ObbyTask.InvRe)
                bad.Push(name " title")
        }
        for name in ["world_day", "mari_day_dialog"]
            if RegExMatch(RsRead(RsFrame(name, f), ObbyTask.InvBox), ObbyTask.InvRe)
                bad.Push(name " inventory title on a game screen")
        ; Mari's dialog: her name (at the task's scale) and "is it up"
        L := MerchantTask.Layout
        for name in ["mari_night_dialog", "mari_day_dialog", "mari_day_buttons"] {
            p := RsFrame(name, f)
            if !RegExMatch(RsRead(p, L.dialogName, MerchantTask.NameScale), MerchantTask.NameRe["Mari"])
                bad.Push(name " name")
            if !MerchantTask.DialogUp(RsRead(p, L.dialogArea), "Mari")
                bad.Push(name " dialog up")
        }
        if MerchantTask.DialogUp(RsRead(RsFrame("world_day", f), L.dialogArea), "Mari")
            bad.Push("world_day dialog seen")
        ; Memory Match notification + Start
        M := MemoryMatchTask.Layout
        p := RsFrame("mm_prompt_ready", f)
        if !RegExMatch(RsRead(p, M.notify), MemoryMatchTask.NotifyRe)
            bad.Push("mm notify")
        if !RegExMatch(RsRead(p, M.startBox), MemoryMatchTask.StartRe)
            bad.Push("mm start")
        ; quest page (crops at 1160, 480 of the frame)
        RsAt(cw, ch, 1160, 480)
        for name in ["quest_page_a", "quest_page_b", "quest_page_c"] {
            p := RsFrame(name, f)
            if !RegExMatch(RsRead(p, ObbyTask.QuestBox), ObbyTask.QuestRe)
                bad.Push(name " Objects")
            if !RegExMatch(RsRead(p, ObbyTask.QuestExitBox), ObbyTask.QuestExitRe)
                bad.Push(name " Exit")
        }
    } finally
        Screen.Reset()
    return bad
}

RsJoin(a) {
    s := ""
    for v in a
        s .= (s = "" ? "" : ", ") v
    return s
}

Test_Resample_1920x1080() {
    ; known misses (see the header): pinned so a fix or a new miss shows
    AssertEq(RsJoin(RsChecks(1920, 1080)), "mari_day_buttons name, mm start", "1920x1080 reads")
}

Test_Resample_3840x2160() {
    AssertEq(RsJoin(RsChecks(3840, 2160)), "", "every read at 3840x2160")
}

Test_Resample_1366x768() {
    AssertEq(RsJoin(RsChecks(1366, 768)), "", "every read at 1366x768")
}

; A rect grab of design px on the scaled frame: the same signature grid as
; on the 2560x1440 frame (Pixel.Grab stretches the client crop back).
Test_Resample_SignatureSameAt1080() {
    old := Pixel._grabber
    try {
        for fr in ["inventory_open_day", "mari_day_dialog"] {
            big := MatchFileGrab(A_ScriptDir "\screens\" fr ".jpg")
            Pixel._grabber := ((g) => (x, y, w, h, dw := "", dh := "") => RsGrab(g, x, y, w, h, dw, dh))(big)
            want := Pixel.Signature(ObbyTask.InvBox.x, ObbyTask.InvBox.y, ObbyTask.InvBox.w, ObbyTask.InvBox.h)
            small := MatchFileGrab(RsFrame(fr, 0.75))
            Pixel._grabber := ((g) => (x, y, w, h, dw := "", dh := "") => RsGrab(g, x, y, w, h, dw, dh))(small)
            RsAt(1920, 1080)
            try
                got := Pixel.Signature(ObbyTask.InvBox.x, ObbyTask.InvBox.y, ObbyTask.InvBox.w, ObbyTask.InvBox.h)
            finally
                Screen.Reset()
            d := Pixel.SigMaxDiff(got, want)
            AssertTrue(d >= 0 && d <= 2, fr ": signature within 2 (max diff " d ")")
        }
    } finally
        Pixel._grabber := old
}

; nearest-pixel grab from a MatchFileGrab, like Pixel._ScreenGrab
RsGrab(g, x, y, w, h, dw, dh) {
    if (dw = "")
        dw := w, dh := h
    out := []
    Loop dh {
        sy := y + ((A_Index - 1) * h) // dh
        xs := []
        Loop dw
            xs.Push(x + ((A_Index - 1) * w) // dw)
        for sx in xs {
            DllCall("gdiplus\GdipBitmapGetPixel", "Ptr", g._bmp, "Int", sx, "Int", sy, "UInt*", &c := 0)
            out.Push(c & 0xFFFFFF)
        }
    }
    return out
}
