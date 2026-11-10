#Requires AutoHotkey v2.0
; ---------------------------------------------------------------------------
; Ocr: Windows.Media.Ocr (WinRT, built into Windows 10/11) on a small screen
; region. Original code: raw RoGetActivationFactory + vtable ComCall.
;
;   Ocr.Read(x, y, w, h, scale := 1) -> String
;     Screen coords. Lines joined with "`n". English recognizer (en-US, then
;     en). Optional `scale` (1..4) upscales the region (HALFTONE) before
;     OCR for very small text; 1 read 11pt Segoe UI cleanest in testing.
;     scale shrinks automatically to fit OcrEngine.MaxImageDimension.
;     Returns "" on ANY failure, never throws. ~20 ms per 400x80 read.
;
;   Ocr.ReadInk(x, y, w, h, scale, ink) -> String
;     Text drawn darker than its background in red (a Biome Orb's health
;     bar: dark "300 / 300" on yellow / orange / red, 5 px tall, that the
;     plain read never reads): every pixel with red under `ink` black, the
;     rest white, upscaled by `scale` with no smoothing (1..8) and InkPad px
;     of white around. Same "" on any failure.
;   Ocr.FindText(x, y, w, h, re, scale := 1) -> {x, y, text} or ""
;   Ocr.ReadFile(path, x, y, w, h, scale := 1, ink := 0) -> String
;     The same read on a saved 2560x1440 frame (PNG / JPG) instead of the
;     screen: the same blit, scaling and recognizer. Used by the screen
;     regression tests (tests\screens), which check every box the tasks read
;     on real frames from the user's clips.
;     Same read; the first LINE whose text matches regex `re`: x, y = the
;     screen centre of that line's words (for clicking a button by its
;     label), text = the line.
;
; Pipeline per call (nothing cached, every COM/WinRT object and HSTRING is
; released and every GDI handle freed in `finally`):
;   GetDC(0) -> StretchBlt into a 32bpp top-down DIB section
;   -> Windows.Storage.Streams.Buffer (IBufferByteAccess memcpy)
;   -> SoftwareBitmap.CreateCopyWithAlphaFromBuffer(Bgra8, alpha Ignore)
;   -> OcrEngine.TryCreateFromLanguage(Language("en-US"))
;   -> RecognizeAsync, poll IAsyncInfo.Status (Sleep 10) -> OcrResult.Lines
;
; Vtable slots: IUnknown 0-2, IInspectable 3-5, interface methods from 6.
; Needs the English OCR language component (present on English Windows).
; ---------------------------------------------------------------------------

class Ocr {
    static Langs := ["en-US", "en"]
    static MaxScale := 4
    static InkMaxScale := 8      ; ReadInk: no smoothing, a bigger upscale is cheap
    static InkPad := 24          ; ReadInk: white px around (the recognizer needs a margin)
    static TimeoutMs := 5000

    static IID := Map(
        "OcrEngineStatics", "{5BFFA85A-3384-3540-9940-699120D428A8}",
        "LanguageFactory", "{9B0252AC-0C27-44F8-B792-9793FB66C63E}",
        "BufferFactory", "{71AF914D-C10F-484B-BC50-14BC623B3A27}",
        "BufferByteAccess", "{905A0FEF-BC53-11DF-8C49-001E4FC686DA}",
        "SoftwareBitmapStatics", "{DF0385DB-672F-4A9D-806E-C2442F343E86}",
        "AsyncInfo", "{00000036-0000-0000-C000-000000000046}"
    )

    static _srcFile := ""        ; ReadFile: blit from this image instead of the screen

    static ReadFile(path, x, y, w, h, scale := 1, ink := 0) {
        if !FileExist(path)
            return ""
        Ocr._srcFile := path
        try {
            return ink ? Ocr.ReadInk(x, y, w, h, scale, ink) : Ocr.Read(x, y, w, h, scale)
        } finally {
            Ocr._srcFile := ""
        }
    }

    static Read(x, y, w, h, scale := 1) {
        try {
            return Ocr._Read(x, y, w, h, scale)
        } catch Any {
            return ""
        }
    }

    static ReadInk(x, y, w, h, scale, ink) {
        try {
            return IsNumber(ink) && ink > 0 ? Ocr._Read(x, y, w, h, scale, "", ink) : ""
        } catch Any {
            return ""
        }
    }

    static FindText(x, y, w, h, re, scale := 1) {
        try {
            r := Ocr._Read(x, y, w, h, scale, re)
            return IsObject(r) ? r : ""
        } catch Any {
            return ""
        }
    }

    ; find = "": the text. find = a regex: {x, y, text} of the first matching
    ; line (screen coords of its words' centre), or "".
    ; ink > 0: ReadInk's black / white upscale instead of the HALFTONE one.
    static _Read(x, y, w, h, scale, find := "", ink := 0) {
        for v in [x, y, w, h, scale]
            if !IsNumber(v)
                return ""
        x := Integer(x), y := Integer(y), w := Integer(w), h := Integer(h)
        if (w < 1 || h < 1)
            return ""
        objs := []      ; WinRT/COM pointers to Release
        hstrs := []     ; HSTRINGs to delete
        gdi := ""       ; capture handles
        try {
            statics := Ocr._Factory("Windows.Media.Ocr.OcrEngine", "OcrEngineStatics", objs, hstrs)
            ComCall(6, statics, "UInt*", &maxDim := 0)           ; get_MaxImageDimension
            pad := ink ? Ocr.InkPad : 0
            s := Max(1, Min(Integer(scale), ink ? Ocr.InkMaxScale : Ocr.MaxScale))
            while (s > 1 && (w * s + 2 * pad > maxDim || h * s + 2 * pad > maxDim))
                s--
            if (w + 2 * pad > maxDim || h + 2 * pad > maxDim)
                return ""

            engine := Ocr._Engine(statics, objs, hstrs)
            if !engine
                return ""

            sw := w * s + 2 * pad, sh := h * s + 2 * pad, size := sw * sh * 4
            if ink {
                gdi := Ocr._Capture(x, y, w, h, w, h)
                gdi := Ocr._Ink(gdi, w, h, ink, s, pad)
            } else
                gdi := Ocr._Capture(x, y, w, h, sw, sh)

            bufFactory := Ocr._Factory("Windows.Storage.Streams.Buffer", "BufferFactory", objs, hstrs)
            ComCall(6, bufFactory, "UInt", size, "Ptr*", &pBuf := 0)   ; Create(capacity)
            objs.Push(pBuf)
            ComCall(8, pBuf, "UInt", size)                              ; put_Length
            pAccess := Ocr._Query(pBuf, "BufferByteAccess", objs)
            ComCall(3, pAccess, "Ptr*", &pData := 0)                    ; IBufferByteAccess::Buffer
            DllCall("RtlMoveMemory", "Ptr", pData, "Ptr", gdi.bits, "UPtr", size)
            Ocr._FreeCapture(gdi), gdi := ""

            bmpStatics := Ocr._Factory("Windows.Graphics.Imaging.SoftwareBitmap", "SoftwareBitmapStatics", objs, hstrs)
            ; CreateCopyWithAlphaFromBuffer(buf, Bgra8=87, w, h, AlphaMode Ignore=2)
            ComCall(10, bmpStatics, "Ptr", pBuf, "Int", 87, "Int", sw, "Int", sh, "Int", 2, "Ptr*", &pBmp := 0)
            objs.Push(pBmp)

            ComCall(6, engine, "Ptr", pBmp, "Ptr*", &pOp := 0)          ; RecognizeAsync
            objs.Push(pOp)
            pInfo := Ocr._Query(pOp, "AsyncInfo", objs)
            deadline := A_TickCount + Ocr.TimeoutMs
            Loop {
                ComCall(7, pInfo, "Int*", &status := 0)                 ; get_Status
                if (status != 0)
                    break
                if (A_TickCount > deadline) {
                    try ComCall(9, pInfo)                               ; Cancel
                    return ""
                }
                Sleep(10)
            }
            if (status != 1) {                                          ; 1 = Completed
                try ComCall(10, pInfo)                                  ; Close
                return ""
            }
            ComCall(8, pOp, "Ptr*", &pRes := 0)                         ; GetResults
            objs.Push(pRes)
            try ComCall(10, pInfo)                                      ; Close

            ComCall(6, pRes, "Ptr*", &pLines := 0)                      ; get_Lines
            objs.Push(pLines)
            ComCall(7, pLines, "UInt*", &n := 0)                        ; IVectorView.get_Size
            out := ""
            Loop n {
                ComCall(6, pLines, "UInt", A_Index - 1, "Ptr*", &pLine := 0)  ; GetAt
                objs.Push(pLine)
                ComCall(7, pLine, "Ptr*", &hText := 0)                  ; IOcrLine.get_Text
                hstrs.Push(hText)
                text := Ocr._HStrText(hText)
                if (find != "") {
                    if RegExMatch(text, find) {
                        b := Ocr._LineBox(pLine, objs)
                        if IsObject(b)
                            return {x: x + Round((b.x1 + b.x2) / 2 / s), y: y + Round((b.y1 + b.y2) / 2 / s), text: text}
                    }
                    continue
                }
                out .= (A_Index > 1 ? "`n" : "") text
            }
            return (find != "") ? "" : out
        } finally {
            if IsObject(gdi)
                Ocr._FreeCapture(gdi)
            Loop objs.Length {
                p := objs[objs.Length - A_Index + 1]
                if p
                    ObjRelease(p)
            }
            for hs in hstrs
                if hs
                    DllCall("combase\WindowsDeleteString", "Ptr", hs)
        }
    }

    ; Bounding box (image px) of an IOcrLine's words, or "".
    static _LineBox(pLine, objs) {
        ComCall(6, pLine, "Ptr*", &pWords := 0)                     ; IOcrLine.get_Words
        objs.Push(pWords)
        ComCall(7, pWords, "UInt*", &n := 0)
        if (n = 0)
            return ""
        rc := Buffer(16, 0)
        b := ""
        Loop n {
            ComCall(6, pWords, "UInt", A_Index - 1, "Ptr*", &pWord := 0)
            objs.Push(pWord)
            ComCall(6, pWord, "Ptr", rc)                            ; IOcrWord.get_BoundingRect
            wx := NumGet(rc, 0, "Float"), wy := NumGet(rc, 4, "Float")
            ww := NumGet(rc, 8, "Float"), wh := NumGet(rc, 12, "Float")
            if !IsObject(b)
                b := {x1: wx, y1: wy, x2: wx + ww, y2: wy + wh}
            else
                b.x1 := Min(b.x1, wx), b.y1 := Min(b.y1, wy), b.x2 := Max(b.x2, wx + ww), b.y2 := Max(b.y2, wy + wh)
        }
        return b
    }

    ; English recognizer or 0. The engine pointer is added to objs.
    static _Engine(statics, objs, hstrs) {
        langFactory := Ocr._Factory("Windows.Globalization.Language", "LanguageFactory", objs, hstrs)
        for tag in Ocr.Langs {
            try {
                hTag := Ocr._HStr(tag, hstrs)
                ComCall(6, langFactory, "Ptr", hTag, "Ptr*", &pLang := 0)   ; CreateLanguage
                objs.Push(pLang)
                ComCall(9, statics, "Ptr", pLang, "Ptr*", &pEng := 0)       ; TryCreateFromLanguage
                if pEng {
                    objs.Push(pEng)
                    return pEng
                }
            }
        }
        return 0
    }

    static _Factory(className, iidName, objs, hstrs) {
        hCls := Ocr._HStr(className, hstrs)
        DllCall("combase\RoGetActivationFactory", "Ptr", hCls, "Ptr", Ocr._Guid(iidName), "Ptr*", &pFactory := 0, "HRESULT")
        objs.Push(pFactory)
        return pFactory
    }

    static _Query(p, iidName, objs) {
        ComCall(0, p, "Ptr", Ocr._Guid(iidName), "Ptr*", &pOut := 0)    ; QueryInterface
        objs.Push(pOut)
        return pOut
    }

    static _Guid(iidName) {
        buf := Buffer(16)
        DllCall("ole32\CLSIDFromString", "WStr", Ocr.IID[iidName], "Ptr", buf, "HRESULT")
        return buf
    }

    static _HStr(str, hstrs) {
        DllCall("combase\WindowsCreateString", "WStr", str, "UInt", StrLen(str), "Ptr*", &h := 0, "HRESULT")
        hstrs.Push(h)
        return h
    }

    static _HStrText(h) {
        if !h
            return ""
        p := DllCall("combase\WindowsGetStringRawBuffer", "Ptr", h, "UInt*", &len := 0, "Ptr")
        return p ? StrGet(p, len, "UTF-16") : ""
    }

    ; Screen rect -> 32bpp top-down DIB of sw x sh. -> {hdcScreen, hdcMem, hbm, old, bits}
    static _Capture(x, y, w, h, sw, sh) {
        g := {hdcScreen: 0, hdcMem: 0, hbm: 0, old: 0, bits: 0, hdcSrc: 0, hbmSrc: 0, oldSrc: 0, gdip: 0}
        try {
            g.hdcScreen := DllCall("GetDC", "Ptr", 0, "Ptr")
            src := g.hdcScreen
            if (Ocr._srcFile != "") {
                Ocr._LoadFile(g, Ocr._srcFile)
                src := g.hdcSrc
            }
            g.hdcMem := DllCall("CreateCompatibleDC", "Ptr", g.hdcScreen, "Ptr")
            bi := Buffer(40, 0)                         ; BITMAPINFOHEADER
            NumPut("UInt", 40, bi, 0)
            NumPut("Int", sw, bi, 4)
            NumPut("Int", -sh, bi, 8)                   ; negative = top-down
            NumPut("UShort", 1, bi, 12)
            NumPut("UShort", 32, bi, 14)
            g.hbm := DllCall("CreateDIBSection", "Ptr", g.hdcMem, "Ptr", bi, "UInt", 0, "Ptr*", &bits := 0, "Ptr", 0, "UInt", 0, "Ptr")
            if (!g.hbm || !bits)
                throw Error("Ocr: CreateDIBSection failed")
            g.bits := bits
            g.old := DllCall("SelectObject", "Ptr", g.hdcMem, "Ptr", g.hbm, "Ptr")
            SRCCOPY := 0x00CC0020
            if (sw = w && sh = h) {
                ok := DllCall("BitBlt", "Ptr", g.hdcMem, "Int", 0, "Int", 0, "Int", sw, "Int", sh
                    , "Ptr", src, "Int", x, "Int", y, "UInt", SRCCOPY)
            } else {
                DllCall("SetStretchBltMode", "Ptr", g.hdcMem, "Int", 4)          ; HALFTONE
                DllCall("SetBrushOrgEx", "Ptr", g.hdcMem, "Int", 0, "Int", 0, "Ptr", 0)
                ok := DllCall("StretchBlt", "Ptr", g.hdcMem, "Int", 0, "Int", 0, "Int", sw, "Int", sh
                    , "Ptr", src, "Int", x, "Int", y, "Int", w, "Int", h, "UInt", SRCCOPY)
            }
            if !ok
                throw Error("Ocr: blit failed")
            DllCall("GdiFlush")
            return g
        } catch Any as e {
            Ocr._FreeCapture(g)
            throw e
        }
    }

    ; ReadInk: the 1x capture g (w x h) made black where red < ink, white
    ; elsewhere, then copied s times up (COLORONCOLOR: no smoothing) into a
    ; white DIB pad px bigger on each side. g is freed. -> the new capture.
    static _Ink(g, w, h, ink, s, pad) {
        try {
            p := g.bits
            Loop w * h {
                NumPut("UInt", NumGet(p, 2, "UChar") < ink ? 0xFF000000 : 0xFFFFFFFF, p)
                p += 4
            }
            sw := w * s + 2 * pad, sh := h * s + 2 * pad
            n := {hdcScreen: 0, hdcMem: 0, hbm: 0, old: 0, bits: 0}
            try {
                n.hdcScreen := DllCall("GetDC", "Ptr", 0, "Ptr")
                n.hdcMem := DllCall("CreateCompatibleDC", "Ptr", n.hdcScreen, "Ptr")
                bi := Buffer(40, 0)
                NumPut("UInt", 40, bi, 0), NumPut("Int", sw, bi, 4), NumPut("Int", -sh, bi, 8)
                NumPut("UShort", 1, bi, 12), NumPut("UShort", 32, bi, 14)
                n.hbm := DllCall("CreateDIBSection", "Ptr", n.hdcMem, "Ptr", bi, "UInt", 0, "Ptr*", &bits := 0, "Ptr", 0, "UInt", 0, "Ptr")
                if (!n.hbm || !bits)
                    throw Error("Ocr: CreateDIBSection failed")
                n.bits := bits
                n.old := DllCall("SelectObject", "Ptr", n.hdcMem, "Ptr", n.hbm, "Ptr")
                DllCall("PatBlt", "Ptr", n.hdcMem, "Int", 0, "Int", 0, "Int", sw, "Int", sh, "UInt", 0x00FF0062)   ; WHITENESS
                DllCall("SetStretchBltMode", "Ptr", n.hdcMem, "Int", 3)                                        ; COLORONCOLOR
                if !DllCall("StretchBlt", "Ptr", n.hdcMem, "Int", pad, "Int", pad, "Int", w * s, "Int", h * s
                    , "Ptr", g.hdcMem, "Int", 0, "Int", 0, "Int", w, "Int", h, "UInt", 0x00CC0020)
                    throw Error("Ocr: blit failed")
                DllCall("GdiFlush")
                return n
            } catch Any as e {
                Ocr._FreeCapture(n)
                throw e
            }
        } finally {
            Ocr._FreeCapture(g)
        }
    }

    ; ReadFile: the image as a GDI bitmap in its own memory DC (g.hdcSrc).
    static _LoadFile(g, path) {
        DllCall("LoadLibrary", "Str", "gdiplus", "Ptr")
        si := Buffer(24, 0), NumPut("UInt", 1, si, 0)
        if DllCall("gdiplus\GdiplusStartup", "Ptr*", &tok := 0, "Ptr", si, "Ptr", 0)
            throw Error("Ocr: GdiplusStartup failed")
        g.gdip := tok
        if DllCall("gdiplus\GdipCreateBitmapFromFile", "WStr", path, "Ptr*", &pBmp := 0) || !pBmp
            throw Error("Ocr: cannot load the image")
        r := DllCall("gdiplus\GdipCreateHBITMAPFromBitmap", "Ptr", pBmp, "Ptr*", &hbm := 0, "UInt", 0xFF000000)
        DllCall("gdiplus\GdipDisposeImage", "Ptr", pBmp)
        if (r || !hbm)
            throw Error("Ocr: cannot convert the image")
        g.hbmSrc := hbm
        g.hdcSrc := DllCall("CreateCompatibleDC", "Ptr", g.hdcScreen, "Ptr")
        g.oldSrc := DllCall("SelectObject", "Ptr", g.hdcSrc, "Ptr", hbm, "Ptr")
    }

    static _FreeCapture(g) {
        if (HasProp(g, "hdcSrc") && g.hdcSrc) {
            if g.oldSrc
                DllCall("SelectObject", "Ptr", g.hdcSrc, "Ptr", g.oldSrc)
            DllCall("DeleteDC", "Ptr", g.hdcSrc)
            g.hdcSrc := 0
        }
        if (HasProp(g, "hbmSrc") && g.hbmSrc)
            DllCall("DeleteObject", "Ptr", g.hbmSrc), g.hbmSrc := 0
        if (HasProp(g, "gdip") && g.gdip)
            DllCall("gdiplus\GdiplusShutdown", "Ptr", g.gdip), g.gdip := 0
        if g.old
            DllCall("SelectObject", "Ptr", g.hdcMem, "Ptr", g.old)
        if g.hbm
            DllCall("DeleteObject", "Ptr", g.hbm)
        if g.hdcMem
            DllCall("DeleteDC", "Ptr", g.hdcMem)
        if g.hdcScreen
            DllCall("ReleaseDC", "Ptr", 0, "Ptr", g.hdcScreen)
        g.old := 0, g.hbm := 0, g.hdcMem := 0, g.hdcScreen := 0, g.bits := 0
    }
}
