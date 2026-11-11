#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\Screen.ahk
; ---------------------------------------------------------------------------
; RECTS ARE DESIGN PX (2560x1440). Off that size Screen maps each rect to the
; Roblox client and the crop is stretched to the size the design read had
; (scale / Screen.s), so a small client is OCR'd larger; FindText returns
; design px. At 2560x1440 nothing changes.
; Off 2560x1440 one stretch reads small text unreliably (1080p frames: each
; filter / factor misreads some box: "Sturt", "Cloge", "Auro Gtornge"), so a
; read there tries OffVariants in turn: FindText until a line matches its
; regex, Read until every word is a known one (Lexicon: the UI's words and
; the data files' names), else the read with the most known words.
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
    static GreenInkDiff := 25   ; ReadInk "g": green above red and blue by this (25: 'Accevi' through Eden's skill list)
    static InkPad := 24          ; ReadInk: white px around (the recognizer needs a margin)
    static TimeoutMs := 5000
    ; off 2560x1440 (not ReadInk): [factor of Screen.OcrScale, filter] tried
    ; in order; "b" GDI+ high-quality bicubic, "h" GDI HALFTONE (the one
    ; filter before). Measured on 1080p frames (tests\test_resample.ahk):
    ; bicubic misses fewest, x1.5 reads most of the rest, x2 the 768p ones.
    ; x2 before the HALFTONE one: small text (Mari's name in her dialog at
    ; 1366x768) reads only at x2, and an empty box stops after three tries
    static OffVariants := [[1, "b"], [1.5, "b"], [2, "b"], [1, "h"]]
    static Lexicon := ""         ; Map of known lowercase words (built on first use)
    static UiWords := "aura auro storage equip equipped remove unlock delete inventory inventorv items item "
        . "shop shoo ugc close start stort memory match available after left location sol world fish fishing "
        . "exit purchase buy robux daily rewards reward claim collections quest quests objects board see leave "
        . "sell confirm cancel mari jester jock merchant craft crafting workshop stella open play change logs "
        . "information success caught you difficulty select raid limbo crack void contract failed gone "
        . "completed turn ready skip who are hide respawn resume cutscene settings menu "
        . "roll rolls auto quick player captain flarg fisher island main tool gears search regular special "
        . "rolled luck time discovered unknown lucky potion speed gear selected weight sells for here friends "
        . "server message tip merchants periodically appear arrived taunt impale deadeye voidrush nothing common"

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
            return ((IsNumber(ink) && ink > 0) || ink == "g") ? Ocr._Read(x, y, w, h, scale, "", ink) : ""
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

    ; FindText, but {x, y} is the centre of the words matching wordRe in that
    ; line (the whole line when none does): "[Exit]" at the end of "Aura
    ; Collections [Exit]" is clicked on the word, not the title's middle.
    static _wordRe := ""
    static FindWord(x, y, w, h, re, wordRe, scale := 1) {
        Ocr._wordRe := wordRe
        try
            return Ocr.FindText(x, y, w, h, re, scale)
        finally
            Ocr._wordRe := ""
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
        ; DESIGN rect -> the client's screen rect; k = screen px per design px
        k := 1
        if !Screen.IsIdentity() {
            r := Screen.Rect(x, y, w, h)
            x := r.x, y := r.y, w := r.w, h := r.h, k := Screen.s
        }
        if (k = 1 || ink)
            return Ocr._Once(x, y, w, h, scale, find, ink, k)
        ; off 2560x1440: OffVariants until one reads (see the header)
        base := Screen.OcrScale(Max(1, Integer(scale))), tried := Map()
        best := "", bestN := -1, empties := 0
        for v in Ocr.OffVariants {
            key := Min(base * v[1], Ocr.MaxScale) "|" v[2]
            if tried.Has(key)
                continue
            tried[key] := 1
            try
                got := Ocr._Once(x, y, w, h, scale, find, 0, k, v)
            catch Any
                continue
            if (find != "") {
                if IsObject(got)
                    return got
                continue
            }
            known := Ocr._Known(got, &words)
            n := known * 2 + (got != "")             ; more known words, then any text
            if (n > bestN)
                best := got, bestN := n
            ; speed (every variant cost ~60 ms: ~250 ms a read at 1080p): stop
            ; at a read whose words are mostly known, and at an empty box
            ; (three variants with no text at all: a poll for a popup not up)
            if (words > 0 && known * 2 >= words + 1)
                break
            empties := (Trim(got) = "") ? empties + 1 : 0
            if (empties >= 3 && best = "")
                break
        }
        return (find != "") ? "" : best
    }

    ; text -> how many of its words (3+ letters) are in Lexicon; words = all
    static _Known(text, &words := 0) {
        lex := Ocr._Lexicon(), known := 0, words := 0, p := 1
        while (p := RegExMatch(text, "[A-Za-z]{3,}", &m, p)) {
            words++, known += lex.Has(StrLower(m[0])), p += m.Len
        }
        return known
    }

    static _Lexicon() {
        if IsObject(Ocr.Lexicon)
            return Ocr.Lexicon
        txt := Ocr.UiWords, lex := Map()
        for f in ["auras", "biomes", "merchants", "potions", "quests"]
            try txt .= " " FileRead(A_LineFile "\..\..\data\" f ".json", "UTF-8")
        p := 1
        while (p := RegExMatch(txt, "[A-Za-z]{3,}", &m, p))
            lex[StrLower(m[0])] := 1, p += m.Len
        return Ocr.Lexicon := lex
    }

    ; One read of the SCREEN rect (k = screen px per design px; 1 at
    ; 2560x1440). v = [factor, filter] off 2560x1440 ("" = [1, "h"]).
    static _Once(x, y, w, h, scale, find, ink, k, v := "") {
        f := IsObject(v) ? v[1] : 1, smooth := IsObject(v) && v[2] = "b"
        objs := []      ; WinRT/COM pointers to Release
        hstrs := []     ; HSTRINGs to delete
        gdi := ""       ; capture handles
        try {
            statics := Ocr._Factory("Windows.Media.Ocr.OcrEngine", "OcrEngineStatics", objs, hstrs)
            ComCall(6, statics, "UInt*", &maxDim := 0)           ; get_MaxImageDimension
            pad := ink ? Ocr.InkPad : 0
            maxS := ink ? Ocr.InkMaxScale : Ocr.MaxScale
            if (k = 1) {
                s := Max(1, Min(Integer(scale), maxS))
                while (s > 1 && (w * s + 2 * pad > maxDim || h * s + 2 * pad > maxDim))
                    s--
            } else {
                ; off 2560x1440: stretch the screen crop to the size the
                ; design read had (Screen.OcrScale: up when smaller, down on 4K)
                s := Min(Screen.OcrScale(Max(1, Integer(scale))) * f, maxS)
                while (s > 1 && (Round(w * s) + 2 * pad > maxDim || Round(h * s) + 2 * pad > maxDim))
                    s := Max(1, s - 1)
            }
            iw := Round(w * s), ih := Round(h * s)
            if (iw + 2 * pad > maxDim || ih + 2 * pad > maxDim)
                return ""

            engine := Ocr._Engine(statics, objs, hstrs)
            if !engine
                return ""

            sw := iw + 2 * pad, sh := ih + 2 * pad, size := sw * sh * 4
            if ink {
                gdi := Ocr._Capture(x, y, w, h, w, h)
                gdi := Ocr._Ink(gdi, w, h, ink, iw, ih, pad)
            } else
                gdi := Ocr._Capture(x, y, w, h, sw, sh, smooth)

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
                        if IsObject(b) {
                            cx := x + Round((b.x1 + b.x2) / 2 / s), cy := y + Round((b.y1 + b.y2) / 2 / s)
                            if (k != 1)                                 ; back to design px for the click
                                d := Screen.Inv(cx, cy), cx := d.x, cy := d.y
                            return {x: cx, y: cy, text: text}
                        }
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
        b := "", bw := ""
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
            if (Ocr._wordRe != "") {
                wt := ""
                try {
                    ComCall(7, pWord, "Ptr*", &hw := 0)             ; IOcrWord.get_Text
                    wt := Ocr._HStrText(hw)
                    DllCall("combase\WindowsDeleteString", "Ptr", hw)
                }
                if RegExMatch(wt, Ocr._wordRe) {
                    if !IsObject(bw)
                        bw := {x1: wx, y1: wy, x2: wx + ww, y2: wy + wh}
                    else
                        bw.x1 := Min(bw.x1, wx), bw.y1 := Min(bw.y1, wy), bw.x2 := Max(bw.x2, wx + ww), bw.y2 := Max(bw.y2, wy + wh)
                }
            }
        }
        return IsObject(bw) ? bw : b
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
    ; smooth: a stretch is GDI+ high-quality bicubic, not HALFTONE.
    static _Capture(x, y, w, h, sw, sh, smooth := false) {
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
            } else if smooth {
                ok := Ocr._Bicubic(g, src, x, y, w, h, sw, sh)
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
    ; elsewhere, then stretched to iw x ih (COLORONCOLOR: no smoothing) into a
    ; white DIB pad px bigger on each side. g is freed. -> the new capture.
    static _Ink(g, w, h, ink, iw, ih, pad) {
        try {
            p := g.bits
            if (ink == "g") {
                ; green ink: the quest board's Accept / Claim words, read
                ; through the white skill names an aura lays over them
                Loop w * h {
                    bl := NumGet(p, 0, "UChar"), gr := NumGet(p, 1, "UChar"), rd := NumGet(p, 2, "UChar")
                    NumPut("UInt", (gr - Max(rd, bl) > Ocr.GreenInkDiff) ? 0xFF000000 : 0xFFFFFFFF, p)
                    p += 4
                }
            } else {
                Loop w * h {
                    NumPut("UInt", NumGet(p, 2, "UChar") < ink ? 0xFF000000 : 0xFFFFFFFF, p)
                    p += 4
                }
            }
            sw := iw + 2 * pad, sh := ih + 2 * pad
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
                if !DllCall("StretchBlt", "Ptr", n.hdcMem, "Int", pad, "Int", pad, "Int", iw, "Int", ih
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

    ; The w x h rect of DC src at x, y -> g's DIB (sw x sh), GDI+ high-quality
    ; bicubic (edges mirrored, so the border is not darkened). -> success
    static _Bicubic(g, src, x, y, w, h, sw, sh) {
        hdc := 0, hbm := 0, old := 0, tok := 0, b1 := 0, b2 := 0, gr := 0, ia := 0
        try {
            hdc := DllCall("CreateCompatibleDC", "Ptr", g.hdcScreen, "Ptr")
            bi := Buffer(40, 0)
            NumPut("UInt", 40, bi, 0), NumPut("Int", w, bi, 4), NumPut("Int", -h, bi, 8)
            NumPut("UShort", 1, bi, 12), NumPut("UShort", 32, bi, 14)
            hbm := DllCall("CreateDIBSection", "Ptr", hdc, "Ptr", bi, "UInt", 0, "Ptr*", &bits := 0, "Ptr", 0, "UInt", 0, "Ptr")
            if (!hbm || !bits)
                return false
            old := DllCall("SelectObject", "Ptr", hdc, "Ptr", hbm, "Ptr")
            if !DllCall("BitBlt", "Ptr", hdc, "Int", 0, "Int", 0, "Int", w, "Int", h, "Ptr", src, "Int", x, "Int", y, "UInt", 0x00CC0020)
                return false
            DllCall("GdiFlush")
            DllCall("LoadLibrary", "Str", "gdiplus", "Ptr")
            si := Buffer(24, 0), NumPut("UInt", 1, si, 0)
            if DllCall("gdiplus\GdiplusStartup", "Ptr*", &tok, "Ptr", si, "Ptr", 0)
                return false
            ; PixelFormat32bppRGB over both DIBs' bits (no copies)
            DllCall("gdiplus\GdipCreateBitmapFromScan0", "Int", w, "Int", h, "Int", w * 4, "Int", 0x22009, "Ptr", bits, "Ptr*", &b1)
            DllCall("gdiplus\GdipCreateBitmapFromScan0", "Int", sw, "Int", sh, "Int", sw * 4, "Int", 0x22009, "Ptr", g.bits, "Ptr*", &b2)
            if (!b1 || !b2)
                return false
            DllCall("gdiplus\GdipGetImageGraphicsContext", "Ptr", b2, "Ptr*", &gr)
            DllCall("gdiplus\GdipSetInterpolationMode", "Ptr", gr, "Int", 7)        ; HighQualityBicubic
            DllCall("gdiplus\GdipSetPixelOffsetMode", "Ptr", gr, "Int", 4)          ; HighQuality
            DllCall("gdiplus\GdipCreateImageAttributes", "Ptr*", &ia)
            DllCall("gdiplus\GdipSetImageAttributesWrapMode", "Ptr", ia, "Int", 3, "UInt", 0, "Int", 0)   ; TileFlipXY
            return !DllCall("gdiplus\GdipDrawImageRectRectI", "Ptr", gr, "Ptr", b1, "Int", 0, "Int", 0, "Int", sw, "Int", sh
                , "Int", 0, "Int", 0, "Int", w, "Int", h, "Int", 2, "Ptr", ia, "Ptr", 0, "Ptr", 0)   ; UnitPixel
        } finally {
            if ia
                DllCall("gdiplus\GdipDisposeImageAttributes", "Ptr", ia)
            if gr
                DllCall("gdiplus\GdipDeleteGraphics", "Ptr", gr)
            if b2
                DllCall("gdiplus\GdipDisposeImage", "Ptr", b2)
            if b1
                DllCall("gdiplus\GdipDisposeImage", "Ptr", b1)
            if tok
                DllCall("gdiplus\GdiplusShutdown", "Ptr", tok)
            if old
                DllCall("SelectObject", "Ptr", hdc, "Ptr", old)
            if hbm
                DllCall("DeleteObject", "Ptr", hbm)
            if hdc
                DllCall("DeleteDC", "Ptr", hdc)
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
