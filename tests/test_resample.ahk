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
;              "Start" (1.33 reads "Sturt"; 2x and 4x read it). Whole-number
;              stretches were measured too and missed more (5 over the
;              sizes; see Screen.OcrScale). Real game frames at 1080p (drawn
;              at that size, not scaled down) are still to be checked.
;   Later 2026-11-10 (a friend at 1080p: fishing, quests, the aura swap did
;   not read): 10 of the tests\screens checks missed at 1080p with the one
;   HALFTONE stretch, every filter / factor missing some. Ocr.OffVariants
;   (bicubic, then other factors, kept by known words) reads all of them and
;   the two above, at 1080p, 900p and 768p (RsScreensChecks). Pixel reads:
;   Test_Resample_PixelReads.
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
    AssertEq(RsJoin(RsChecks(1920, 1080)), "", "every read at 1920x1080")
}

; The tests\screens reads that missed at 1080p before Ocr.OffVariants (a
; friend at 1920x1080, 2026-11-10: fishing, quests, the aura swap, Memory
; Match): the aura panel's name and Equip, the storage / UGC titles, Memory
; Match's Start / Close, the fishing status line; and the pixel reads
; (Memory Match pictures, aura result tiles) through a grab mapped like
; StripGrab.Rows / Pixel.Grab (RsMapGrab), as in the game. -> failed names
RsScreensChecks(cw, ch) {
    f := cw / 2560
    bad := []
    try {
        RsAt(cw, ch)
        ; aura panel (the user's aura_equip point 840, 843)
        n := ObbyTask.NameBox, b := ObbyTask.ButtonBox
        nb := {x: 840 + n.dx, y: 843 + n.dy, w: n.w, h: n.h}
        sailor := RsNames(RsFrame("aura_selected_sailor", f), nb)
        dutch := RsNames(RsFrame("aura_selected_dutchman", f), nb)
        if (ObbyTask.NameVerdict(sailor, "Sailor") != "same")
            bad.Push("Sailor name")
        if (ObbyTask.NameVerdict(sailor, "Sailor_Flying_Dutchman") = "same")
            bad.Push("Sailor read as Flying Dutchman")
        if (ObbyTask.NameVerdict(dutch, "Sailor_Flying_Dutchman") != "same")
            bad.Push("Flying Dutchman name")
        if (ObbyTask.NameVerdict(dutch, "Sailor") != "other")
            bad.Push("Flying Dutchman read as Sailor")
        if (ObbyTask.NameVerdict(RsNames(RsFrame("aura_search_sailor", f), nb), "Sailor") != "unread")
            bad.Push("no aura selected")
        if !RegExMatch(RsRead(RsFrame("aura_selected_sailor", f), {x: 840 + b.dx, y: 843 + b.dy, w: b.w, h: b.h}), "i)^\W*equip\W*$")
            bad.Push("Equip")
        ; the storage title (aura_search 1146, 490) and its tiles
        sb := ObbyTask.StorageBox, box := {x: 1146 + sb.dx, y: 490 + sb.dy, w: sb.w, h: sb.h}
        for name in ["aura_search_sailor", "aura_selected_sailor", "aura_selected_dutchman"] {
            p := RsFrame(name, f)
            if !RegExMatch(RsRead(p, box), ObbyTask.StorageRe)
                bad.Push(name " storage title")
        }
        if RegExMatch(RsRead(RsFrame("world_day", f), box), ObbyTask.StorageRe)
            bad.Push("world_day storage title")
        ; the UGC Shop in the Inventory's frame
        t := RsRead(RsFrame("ugc_shop_windy", f), ObbyTask.InvBox)
        if (!RegExMatch(t, ObbyTask.ShopRe) || RegExMatch(t, ObbyTask.InvRe))
            bad.Push("UGC title")
        ; Memory Match: Start, Close, the pictures
        M := MemoryMatchTask.Layout
        t := RsRead(RsFrame("mm_prompt_ready", f), M.startBox)
        if (!RegExMatch(t, MemoryMatchTask.StartRe) || RegExMatch(t, MemoryMatchTask.CooldownRe))
            bad.Push("mm Start")
        if !RegExMatch(RsRead(RsFrame("mm_prompt_cooldown", f), M.startBox), MemoryMatchTask.CooldownRe)
            bad.Push("mm cooldown")
        if !RegExMatch(RsRead(RsFrame("mm_end", f), M.closeBox), MemoryMatchTask.CloseRe)
            bad.Push("mm Close")
        if RegExMatch(RsRead(RsFrame("mm_board_start", f), M.closeBox), MemoryMatchTask.CloseRe)
            bad.Push("mm Close mid-round")
        ; the fishing panel's status line (under Eden's combo bar)
        s := FishingTask.StatusRect, sr := {x: s[1], y: s[2], w: s[3], h: s[4]}
        if !RegExMatch(RsRead(RsFrame("fish_status_ready_eden", f), sr), FishingTask.ReadyRe)
            bad.Push("fishing Location")
        for name in ["fish_status_waiting_eden", "fish_status_anyminute_eden"]
            if RegExMatch(RsRead(RsFrame(name, f), sr), FishingTask.ReadyRe)
                bad.Push(name " read as ready")
    } finally
        Screen.Reset()
    return bad
}

; The pixel reads of tests\screens through RsMapGrab: Memory Match's tile
; states and pairs, the aura result tiles (shown / empty). -> failed names
RsPixelChecks(cw, ch) {
    f := cw / 2560
    bad := []
    try {
        RsAt(cw, ch)
        for name in ["aura_search_sailor", "aura_selected_sailor", "aura_selected_dutchman"] {
            g := RsMapGrab(MatchFileGrab(RsFrame(name, f)))
            Loop 16 {
                r := ObbyTask.TileRect({x: 1056, y: 548, w: 78, h: 66}, A_Index)
                if (ObbyTask.TileShown(ScrTilePixels(g, r), r.w, r.h) != (A_Index <= 8))
                    bad.Push(name " tile " A_Index)
            }
        }
        v := MatchVision(RsMapGrab(MatchFileGrab(RsFrame("mm_board_start", f))))
        Loop 20
            if (v.State(A_Index) != "hidden")
                bad.Push("mm tile " A_Index " face down")
        v := MatchVision(RsMapGrab(MatchFileGrab(RsFrame("mm_end", f))))
        found := ""
        Loop 20 {
            i := A_Index
            Loop 20
                if (A_Index > i && v.State(i) = "open" && v.State(A_Index) = "open" && MatchVision.Same(v.Sig(i), v.Sig(A_Index)))
                    found .= i "-" A_Index " "
        }
        if (found != "1-19 2-12 3-11 4-17 5-16 6-18 7-10 8-14 13-20 ")
            bad.Push("mm pairs")
    } finally
        Screen.Reset()
    return bad
}

; the aura panel at every scale the swap reads it (ObbyTask._ReadName)
RsNames(p, r) {
    out := []
    for s in ObbyTask.NameScales
        out.Push(RsRead(p, r, s))
    return out
}

; grab(x1, x2, ys, stride) in DESIGN px over a scaled frame: each sample at
; its Screen-mapped pixel (nearest), as StripGrab.Rows does on the screen
RsMapGrab(g) => (x1, x2, ys, stride := 1) => RsMapRows(g, x1, x2, ys, stride)

RsMapRows(g, x1, x2, ys, stride) {
    xs := []
    x := x1
    while (x <= x2)
        xs.Push(Screen.X(x)), x += stride
    out := []
    for y in ys {
        sy := Screen.Y(y), row := []
        for sx in xs {
            DllCall("gdiplus\GdipBitmapGetPixel", "Ptr", g._bmp, "Int", sx, "Int", sy, "UInt*", &c := 0)
            row.Push(c & 0xFFFFFF)
        }
        out.Push(row)
    }
    return out
}

Test_Resample_ScreensAt1920x1080() {
    AssertEq(RsJoin(RsScreensChecks(1920, 1080)), "", "every screen read at 1920x1080")
}

; live 1920x1080 2026-11-11 19:07, after a game update: the face-down tiles
; are brighter (corner 0x3E3E3E, was 0x222222) and the fixed corner colour
; read all 20 as "open", so the board never counted as dealt. A native
; 1080p frame (not a resample).
Test_Resample_MemoryMatchFaceDownAt1080Native() {
    try {
        RsAt(1920, 1080)
        v := MatchVision(RsMapGrab(MatchFileGrab(A_ScriptDir "\screens\mm_board_down_1080.jpg")))
        bad := []
        Loop 20
            if (v.State(A_Index) != "hidden")
                bad.Push(A_Index ":" v.State(A_Index))
        AssertEq(RsJoin(bad), "", "every tile face down")
    } finally {
        Screen.Reset()
    }
}

Test_Resample_ScreensAt1600x900() {
    AssertEq(RsJoin(RsScreensChecks(1600, 900)), "", "every screen read at 1600x900")
}

Test_Resample_ScreensAt1366x768() {
    AssertEq(RsJoin(RsScreensChecks(1366, 768)), "", "every screen read at 1366x768")
}

; Pixel reads below 1440p: Memory Match's pairs and, at 900p / 768p, the
; first aura tiles of one frame. Not OCR: pinned as known misses so a fix or
; a new miss shows. Tile states read at every size. The "mm pairs" miss is
; these frames' own: a 1440p clip shrunk with smoothing blurs each tile's
; thin amount text at another sub-pixel phase (real pairs 0.04-0.12 apart,
; 2026-11-12), while the game draws every tile's text on whole pixels (pairs
; 0.00-0.01 at native 1440p, though tiles sit at fractional x there too).
; Natively the amount is read one sample per screen px
; (Test_Resample_MemoryMatchAmountOncePerPixel).
Test_Resample_PixelReads() {
    AssertEq(RsJoin(RsPixelChecks(1920, 1080)), "mm pairs", "1920x1080 pixel reads")
    AssertEq(RsJoin(RsPixelChecks(1600, 900)), "aura_search_sailor tile 1, aura_search_sailor tile 2, aura_search_sailor tile 3, aura_search_sailor tile 4, aura_search_sailor tile 5, mm pairs", "1600x900 pixel reads")
    AssertEq(RsJoin(RsPixelChecks(1366, 768)), "aura_search_sailor tile 1, aura_search_sailor tile 2, aura_search_sailor tile 3, aura_search_sailor tile 4, aura_search_sailor tile 5, mm pairs", "1366x768 pixel reads")
}

; Memory Match's amount line below 1440p: every screen column and row of it
; read exactly once (a design-px step read some twice, at other columns per
; tile, so a pair's two profiles differed).
Test_Resample_MemoryMatchAmountOncePerPixel() {
    for sz in [[1920, 1080], [1600, 900], [1366, 768], [2560, 1440]] {
        RsAt(sz[1], sz[2])
        try {
            calls := []
            fake := (x1, x2, ys, stride) => (calls.Push({x1: x1, x2: x2, ys: ys, st: stride}), RsZeros(x1, x2, ys, stride))
            v := MatchVision(fake)
            Loop 20 {
                calls.Length := 0
                v.Sig(A_Index)
                c := calls[2]                      ; [1] icon, [2] the amount line
                m := StripGrab.Map(c.x1, c.x2, c.ys, c.st)
                AssertTrue(RsConsecutive(m.xs), sz[2] "p tile " A_Index ": columns once each")
                AssertTrue(RsConsecutive(m.ys), sz[2] "p tile " A_Index ": rows once each")
            }
        } finally
            Screen.Reset()
    }
}

RsZeros(x1, x2, ys, stride) {
    n := 0, x := x1
    while (x <= x2)
        n++, x += stride
    out := []
    for y in ys {
        row := []
        Loop n
            row.Push(0)
        out.Push(row)
    }
    return out
}

RsConsecutive(a) {
    Loop a.Length - 1
        if (a[A_Index + 1] != a[A_Index] + 1)
            return false
    return a.Length > 10
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
