#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\Theme.ahk
; ---------------------------------------------------------------------------
; ThemeStore: saved themes (2026-11-18 themes + layout design, spec 1 and 4).
;
; A theme is a Map:
;   name, preset (true for the built-in ones),
;   colors   Map: Bg PanelC Text Accent, and the 10 derived keys ("" = Derive works it out),
;   fonts    Map: role -> [family, size] (ThemeStore.FontRoles),
;   ui       Map: scale (100 / 115 / 130), sidebar (left / right / top),
;   picture  Map: file ("none", a preset name, or a file in the themes folder), fit, dim (0-90),
;   layout   Map: "<page>:<card>" -> [x, y, w, h, hidden] (100 % units).
;
; Files live in <settings folder>\themes\<name>.moontheme (INI text, UTF-8).
; The 9 presets are built in and read-only. Clean never throws: every bad
; key falls back to its default. ToText / FromText are the one reader and
; writer that Save / Load and Export / Import share.
; ---------------------------------------------------------------------------

class ThemeStore {
    static FontRoles := ["title", "head", "body", "button", "nav", "small"]
    static DerivedKeys := ["SideBg", "CardBg", "FieldBg", "FrameC", "HoverBg", "OffBg", "Muted", "Ink", "AccentHi", "Pulse"]
    static Scales := [100, 115, 130]
    static Sidebars := ["left", "right", "top"]
    static Fits := ["fill", "fit", "center", "tile"]
    static FallbackName := "My theme"
    static FallbackFont := "Segoe UI"
    static Ext := ".moontheme"
    static MaxFile := 8 * 1024 * 1024
    static MaxPicture := 5 * 1024 * 1024
    static MaxLayout := 400
    static MaxPixels := 8192        ; a picture wider or taller than this is refused
    static LayoutMax := 4000        ; a layout value beyond this is kept but marked for clamping
    static PicExts := ["png", "jpg", "bmp", "gif"]

    ; Font check, Call(family) -> true when installed. Tests replace it.
    static FontExistsFn := (fam) => ThemeStore.SystemHasFont(fam)

    ; Picture check, Call(bytes Buffer) -> true when GDI+ loads it. Tests replace it.
    static PictureOkFn := (bytes) => ThemeStore._PictureLoads(bytes)

    ; ---- built-in themes ----------------------------------------------------

    static Default() => ThemeStore.Preset("Moontide")

    ; Preset `name` (any case) as a full theme, "" when it is not one of the 9.
    static Preset(name) {
        n := ThemeStore.PresetName(name)
        if (n = "")
            return ""
        p := Theme.Presets[n]
        colors := Map()
        for k in Theme.BaseKeys
            colors[k] := p.%k%
        for k in ThemeStore.DerivedKeys
            colors[k] := p.%k%
        fonts := Map()
        for r in ThemeStore.FontRoles {
            f := Theme.DefaultFonts()[r]
            fonts[r] := [f[2], Integer(RegExReplace(f[1], "^s(\d+).*$", "$1"))]
        }
        return Map("name", n, "preset", true, "colors", colors, "fonts", fonts
            , "ui", Map("scale", 100, "sidebar", "left")
            , "picture", Map("file", n, "fit", "fill", "dim", 60)
            , "layout", Map())
    }

    ; The built-in name written the way Theme.Names has it ("" if none).
    static PresetName(name) {
        name := Trim(String(name))
        for n in Theme.Names
            if (StrCompare(n, name) = 0 || n = name)
                return n
        return ""
    }

    ; ---- validation ------------------------------------------------------------

    static NameOk(name) => RegExMatch(String(name), "^[A-Za-z0-9 _()-]{1,32}$") ? true : false

    static _Map(v) => (v is Map) ? v : Map()

    static _Int(v, def) {
        try {
            s := Trim(String(v))
            if IsInteger(s)
                return Integer(s)
        }
        return def
    }

    ; m cleaned into a full theme: every key checked, a bad one becomes its
    ; default (a font size above 28 is clamped to 28, below 7 is the default
    ; size, a family that is not installed is Segoe UI). Never throws.
    static Clean(m) {
        d := ThemeStore.Default()
        if !(m is Map)
            return d
        out := Map()
        try {
            nm := Trim(String(m.Get("name", "")))
            out["name"] := ThemeStore.NameOk(nm) ? nm : ThemeStore.FallbackName
            out["preset"] := m.Get("preset", false) ? true : false
            ; colours
            cin := ThemeStore._Map(m.Get("colors", ""))
            colors := Map()
            for k in Theme.BaseKeys
                colors[k] := Theme.HexOr(cin.Get(k, ""), d["colors"][k])
            for k in ThemeStore.DerivedKeys
                colors[k] := Theme.HexOk(cin.Get(k, ""))
            out["colors"] := colors
            ; fonts
            fin := ThemeStore._Map(m.Get("fonts", ""))
            fonts := Map()
            for r in ThemeStore.FontRoles {
                df := d["fonts"][r]
                fam := df[1], size := df[2]
                if (fin.Has(r) && fin[r] is Array && fin[r].Length >= 2) {
                    f := String(fin[r][1])
                    f := Trim(f)
                    if (f != "" && !RegExMatch(f, "[,\r\n=]") && StrLen(f) <= 31)
                        fam := ThemeStore._FontOr(f)
                    sz := ThemeStore._Int(fin[r][2], 0)
                    if (sz > 28)
                        size := 28
                    else if (sz >= 7)
                        size := sz
                }
                fonts[r] := [fam, size]
            }
            out["fonts"] := fonts
            ; window
            uin := ThemeStore._Map(m.Get("ui", ""))
            sc := ThemeStore._Int(uin.Get("scale", 100), 100)
            sb := StrLower(Trim(String(uin.Get("sidebar", ""))))
            out["ui"] := Map("scale", ThemeStore._Has(ThemeStore.Scales, sc) ? sc : 100
                , "sidebar", ThemeStore._Has(ThemeStore.Sidebars, sb) ? sb : "left")
            ; picture
            pin := ThemeStore._Map(m.Get("picture", ""))
            fit := StrLower(Trim(String(pin.Get("fit", ""))))
            dim := ThemeStore._Int(pin.Get("dim", 60), 60)
            out["picture"] := Map("file", ThemeStore._PictureOk(pin.Get("file", "")), "fit", ThemeStore._Has(ThemeStore.Fits, fit) ? fit : "fill"
                , "dim", (dim >= 0 && dim <= 90) ? dim : 60)
            ; layout
            lay := Map()
            lin := ThemeStore._Map(m.Get("layout", ""))
            for id, v in lin {
                id := Trim(String(id))
                if (id = "" || !InStr(id, ":") || RegExMatch(id, "[=\r\n]") || !(v is Array) || v.Length < 4)
                    continue
                e := []
                ok := true
                Loop 4 {
                    n := ThemeStore._Int(v[A_Index], "")
                    if (n = "" || Abs(n) > 100000)
                        ok := false
                    e.Push(n)
                }
                if (!ok || e[3] < 1 || e[4] < 1)
                    continue
                e.Push((v.Length >= 5 && ThemeStore._Int(v[5], 0)) ? 1 : 0)
                lay[id] := e
            }
            out["layout"] := lay
        } catch
            return d
        return out
    }

    static _Has(arr, v) {
        for x in arr
            if (x = v)
                return true
        return false
    }

    static _FontOr(fam) {
        ok := false
        try ok := ThemeStore.FontExistsFn.Call(fam)
        return ok ? fam : ThemeStore.FallbackFont
    }

    ; "none", a preset name, or a plain file name in the themes folder; else Moontide's picture.
    static _PictureOk(v) {
        s := Trim(String(v))
        if (s = "none")
            return "none"
        n := ThemeStore.PresetName(s)
        if (n != "")
            return n
        if (RegExMatch(s, "^[^\\/:*?`"<>|\r\n=]{1,120}$") && SubStr(s, 1, 1) != ".")
            return s
        return "Moontide"
    }

    ; true when a font family of this name is installed (EnumFontFamiliesExW)
    static SystemHasFont(fam) {
        static cache := Map()
        fam := String(fam)
        if (fam = "" || StrLen(fam) > 31)
            return false
        if cache.Has(fam)
            return cache[fam]
        flag := Buffer(4, 0)
        cb := 0, dc := 0
        try {
            lf := Buffer(92, 0)
            NumPut("UChar", 1, lf, 23)                     ; lfCharSet = DEFAULT_CHARSET
            StrPut(fam, lf.Ptr + 28, 32, "UTF-16")        ; lfFaceName
            cb := CallbackCreate((lpelf, lpntm, ft, lp) => (NumPut("Int", 1, lp), 0))
            dc := DllCall("GetDC", "Ptr", 0, "Ptr")
            DllCall("gdi32\EnumFontFamiliesExW", "Ptr", dc, "Ptr", lf, "Ptr", cb, "Ptr", flag.Ptr, "UInt", 0)
        }
        if dc
            DllCall("ReleaseDC", "Ptr", 0, "Ptr", dc)
        if cb
            CallbackFree(cb)
        cache[fam] := NumGet(flag, 0, "Int") ? true : false
        return cache[fam]
    }

    ; ---- text format (spec 4) ----------------------------------------------------

    ; The .moontheme text of a theme (cleaned first). withPicture (an export):
    ; a theme with its own picture writes data=<base64> and ext= from pic
    ; (Map bytes, ext), never a local file name; with no pic it writes Moontide.
    static ToText(th, withPicture := false, pic := "") {
        t := ThemeStore.Clean(th)
        s := "[Theme]`nformat=1`nname=" t["name"] "`n[Colors]`n"
        for k in Theme.BaseKeys
            s .= k "=" t["colors"][k] "`n"
        for k in ThemeStore.DerivedKeys
            if (t["colors"][k] != "")
                s .= k "=" t["colors"][k] "`n"
        s .= "[Fonts]`n"
        for r in ThemeStore.FontRoles
            s .= r "=" t["fonts"][r][1] "," t["fonts"][r][2] "`n"
        s .= "[UI]`nscale=" t["ui"]["scale"] "`nsidebar=" t["ui"]["sidebar"] "`n"
        pf := t["picture"]["file"]
        pt := "fit=" t["picture"]["fit"] "`ndim=" t["picture"]["dim"] "`n"
        if (withPicture && pf != "none" && ThemeStore.PresetName(pf) = "") {
            if (pic is Map && pic.Has("bytes"))
                s .= "[Picture]`next=" pic["ext"] "`n" pt "data=" ThemeStore._B64Encode(pic["bytes"]) "`n"
            else
                s .= "[Picture]`nfile=Moontide`n" pt
        } else
            s .= "[Picture]`nfile=" pf "`n" pt
        s .= "[Layout]`n"
        for id, e in t["layout"]
            s .= id "=" e[1] "," e[2] "," e[3] "," e[4] "," e[5] "`n"
        return s
    }

    ; Text -> a Clean'd theme. Unknown sections and keys are ignored, a
    ; cut-off or empty text gives defaults for what is missing. Never throws.
    static FromText(s) => ThemeStore.Clean(ThemeStore._Parse(s))

    ; Text -> the raw sections (picture keeps data and ext). Reads at most
    ; MaxLayout layout lines; a picture file keeps only its base name.
    static _Parse(s) {
        raw := Map("colors", Map(), "fonts", Map(), "ui", Map(), "picture", Map(), "layout", Map())
        try {
            s := String(s)
            if (SubStr(s, 1, 1) = Chr(0xFEFF))
                s := SubStr(s, 2)
            sec := ""
        nLay := 0
            for line in StrSplit(s, "`n", "`r") {
                line := Trim(line)
                if (line = "" || SubStr(line, 1, 1) = ";")
                    continue
                if RegExMatch(line, "^\[([^\]]*)\]$", &m) {
                    sec := StrLower(Trim(m[1]))
                    continue
                }
                if (sec = "layout" && ++nLay > ThemeStore.MaxLayout)
                    continue
                if (sec = "layout")
                    p := InStr(line, "=", , -1)
                else
                    p := InStr(line, "=")
                if (p < 2)
                    continue
                k := Trim(SubStr(line, 1, p - 1)), v := Trim(SubStr(line, p + 1))
                switch sec {
                    case "theme":
                        if (StrLower(k) = "name")
                            raw["name"] := v
                    case "colors":
                        raw["colors"][k] := v
                    case "fonts":
                        q := InStr(v, ",", , -1)
                        if q
                            raw["fonts"][StrLower(k)] := [Trim(SubStr(v, 1, q - 1)), ThemeStore._Int(SubStr(v, q + 1), 0)]
                    case "ui":
                        raw["ui"][StrLower(k)] := v
                    case "picture":
                        if (StrLower(k) = "file")
                            v := RegExReplace(v, "^.*[\\/:]")
                        raw["picture"][StrLower(k)] := v
                    case "layout":
                        parts := StrSplit(v, ",", " `t")
                        if (parts.Length >= 4)
                            raw["layout"][k] := parts
                }
            }
        }
        return raw
    }

    ; ---- files --------------------------------------------------------------------

    static Dir(cfg) => RTrim(cfg.dir, "\/") "\themes"

    static _Path(cfg, name) => ThemeStore.Dir(cfg) "\" name ThemeStore.Ext

    ; Preset names first, then saved themes sorted by name.
    static List(cfg) {
        out := Theme.Names.Clone()
        saved := ""
        try {
            Loop Files, ThemeStore.Dir(cfg) "\*" ThemeStore.Ext {
                n := RegExReplace(A_LoopFileName, "\.moontheme$")
                if (ThemeStore.NameOk(n) && ThemeStore.PresetName(n) = "")
                    saved .= n "`n"
            }
        }
        saved := Sort(RTrim(saved, "`n"), "D`n")
        if (saved != "")
            for n in StrSplit(saved, "`n")
                out.Push(n)
        return out
    }

    ; A preset or saved theme by name (Clean'd). Unknown or unreadable -> Default().
    static Load(cfg, name) => ThemeStore.LoadWhy(cfg, name).theme

    ; Load, and why it fell back to Moontide: {theme, why} with why "" when
    ; `name` was used, else a short reason for the log (never a path).
    static LoadWhy(cfg, name) {
        p := ""
        try p := ThemeStore.Preset(name)
        if IsObject(p)
            return {theme: p, why: ""}
        why := "it is not a theme name"
        try {
            name := Trim(String(name))
            if ThemeStore.NameOk(name) {
                why := "its file is missing"
                path := ThemeStore._Path(cfg, name)
                if FileExist(path) {
                    why := "its file could not be read"
                    t := ThemeStore.FromText(FileRead(path, "UTF-8"))
                    t["name"] := name
                    return {theme: t, why: ""}
                }
            }
        }
        return {theme: ThemeStore.Default(), why: why}
    }

    ; The boot log line when the theme in use could not be used: its name
    ; (only when it is a theme name) and why. "" when there is no why.
    static FallbackLine(name, why) {
        if (why = "")
            return ""
        nm := ""
        try nm := Trim(String(name))
        return "Theme: " (ThemeStore.NameOk(nm) ? nm : "the saved theme") " could not be used (" why "), using Moontide"
    }

    static Exists(cfg, name) {
        name := Trim(String(name))
        if (ThemeStore.PresetName(name) != "")
            return true
        try return ThemeStore.NameOk(name) && FileExist(ThemeStore._Path(cfg, name)) != ""
        return false
    }

    ; Why `name` cannot be used for a saved theme, "" when it can.
    static _NameProblem(name) {
        name := Trim(String(name))
        if !ThemeStore.NameOk(name)
            return I18n.T("A theme name is 1 to 32 letters, digits, spaces, - _ ( or ).")
        if (ThemeStore.PresetName(name) != "")
            return I18n.T("That name belongs to a built-in theme.")
        return ""
    }

    ; -> true, or why not. Writes <themes dir>\<name>.moontheme; presets are refused.
    static Save(cfg, th) {
        nm := (th is Map) ? Trim(String(th.Get("name", ""))) : ""
        why := ThemeStore._NameProblem(nm)
        if (why != "")
            return why
        t := ThemeStore.Clean(th)
        t["name"] := nm
        t["preset"] := false
        return ThemeStore._Write(cfg, nm, ThemeStore.ToText(t))
    }

    static _Write(cfg, name, text) {
        path := ThemeStore._Path(cfg, name)
        tmp := path ".tmp"
        try {
            DirCreate(ThemeStore.Dir(cfg))
            f := FileOpen(tmp, "w", "UTF-8-RAW")
            f.Write(text)
            f.Close()
            FileMove(tmp, path, 1)
            return true
        }
        try FileDelete(tmp)
        return I18n.T("The theme file could not be written.")
    }

    ; -> true when a saved theme was removed (presets never are)
    static Delete(cfg, name) {
        name := Trim(String(name))
        if (ThemeStore._NameProblem(name) != "")
            return false
        try {
            path := ThemeStore._Path(cfg, name)
            if !FileExist(path)
                return false
            pic := ThemeStore._OwnPicture(cfg, name, ThemeStore.Load(cfg, name))
            FileDelete(path)
            if (pic != "")
                try FileDelete(pic)
            return true
        }
        return false
    }

    ; -> true, or why not
    static Rename(cfg, old, new) {
        old := Trim(String(old)), new := Trim(String(new))
        if (ThemeStore._NameProblem(old) != "" || !FileExist(ThemeStore._Path(cfg, old)))
            return I18n.T("That theme cannot be renamed.")
        why := ThemeStore._NameProblem(new)
        if (why != "")
            return why
        if (StrLower(old) != StrLower(new) && ThemeStore.Exists(cfg, new))
            return I18n.T("A theme with that name already exists.")
        t := ThemeStore.Load(cfg, old)
        pic := ThemeStore._OwnPicture(cfg, old, t)
        newPic := ""
        if (pic != "") {
            SplitPath(pic, , , &pe)
            t["picture"]["file"] := new "." pe
            newPic := ThemeStore.Dir(cfg) "\" new "." pe
        }
        t["name"] := new
        ; the picture moves first: if it cannot, nothing has changed
        if (pic != "") {
            try
                FileMove(pic, newPic, 1)
            catch
                return I18n.T("The theme's picture could not be moved.")
        }
        r := ThemeStore.Save(cfg, t)
        if (r != true) {
            if (pic != "")
                try FileMove(newPic, pic, 1)
            return r
        }
        if (StrLower(old) != StrLower(new))
            try FileDelete(ThemeStore._Path(cfg, old))
        return true
    }

    ; A copy of a preset or saved theme under a new name -> true, or why not
    static Duplicate(cfg, name, newName) {
        newName := Trim(String(newName))
        why := ThemeStore._NameProblem(newName)
        if (why != "")
            return why
        if ThemeStore.Exists(cfg, newName)
            return I18n.T("A theme with that name already exists.")
        if !ThemeStore.Exists(cfg, name)
            return I18n.T("That theme cannot be copied.")
        t := ThemeStore.Load(cfg, name)
        pic := ThemeStore._OwnPicture(cfg, Trim(String(name)), t)
        newPic := ""
        if (pic != "") {
            SplitPath(pic, , , &pe)
            t["picture"]["file"] := newName "." pe
            newPic := ThemeStore.Dir(cfg) "\" newName "." pe
            try
                FileCopy(pic, newPic, 1)
            catch
                t["picture"]["file"] := "Moontide"
        }
        t["name"] := newName
        t["preset"] := false
        r := ThemeStore.Save(cfg, t)
        if (r != true && newPic != "")
            try FileDelete(newPic)
        return r
    }

    ; ---- export and import (spec 4) ----------------------------------------------

    ; base64 text of a Buffer, one line
    static _B64Encode(buf) {
        n := 0
        if (!IsObject(buf) || buf.Size = 0)
            return ""
        if !DllCall("Crypt32\CryptBinaryToStringW", "Ptr", buf, "UInt", buf.Size, "UInt", 1 | 0x40000000, "Ptr", 0, "UInt*", &n) || n = 0
            return ""
        out := Buffer(n * 2, 0)
        if !DllCall("Crypt32\CryptBinaryToStringW", "Ptr", buf, "UInt", buf.Size, "UInt", 1 | 0x40000000, "Ptr", out, "UInt*", &n)
            return ""
        return StrGet(out, "UTF-16")
    }

    ; base64 text -> Buffer, "" when it is not base64
    static _B64Decode(s) {
        s := RegExReplace(String(s), "\s+")
        if (s = "" || !RegExMatch(s, "^[A-Za-z0-9+/]+=*$"))
            return ""
        n := 0
        if !DllCall("Crypt32\CryptStringToBinaryW", "Str", s, "UInt", 0, "UInt", 1, "Ptr", 0, "UInt*", &n, "Ptr", 0, "Ptr", 0) || n = 0
            return ""
        buf := Buffer(n)
        if !DllCall("Crypt32\CryptStringToBinaryW", "Str", s, "UInt", 0, "UInt", 1, "Ptr", buf, "UInt*", &n, "Ptr", 0, "Ptr", 0)
            return ""
        if (n != buf.Size)
            buf.Size := n
        return buf
    }

    ; the picture type from its first bytes: png, jpg, bmp, gif, "" if none
    static _PicExt(b) {
        if (!IsObject(b) || b.Size < 4)
            return ""
        a := NumGet(b, 0, "UChar"), c := NumGet(b, 1, "UChar"), d := NumGet(b, 2, "UChar"), e := NumGet(b, 3, "UChar")
        if (a = 0x89 && c = 0x50 && d = 0x4E && e = 0x47)
            return "png"
        if (a = 0xFF && c = 0xD8 && d = 0xFF)
            return "jpg"
        if (a = 0x42 && c = 0x4D)
            return "bmp"
        if (a = 0x47 && c = 0x49 && d = 0x46 && e = 0x38)
            return "gif"
        return ""
    }

    ; true when GDI+ loads the bytes as an image (the default PictureOkFn)
    static _PictureLoads(bytes) {
        tok := 0, bmp := 0, stm := 0, ok := false
        try {
            if (!IsObject(bytes) || bytes.Size = 0)
                return false
            if !ThemeStore._Whole(bytes, ThemeStore._PicExt(bytes))
                return false
            DllCall("LoadLibrary", "Str", "gdiplus", "Ptr")
            si := Buffer(24, 0), NumPut("UInt", 1, si, 0)
            if DllCall("gdiplus\GdiplusStartup", "Ptr*", &tok, "Ptr", si, "Ptr", 0)
                return false
            stm := DllCall("shlwapi\SHCreateMemStream", "Ptr", bytes, "UInt", bytes.Size, "Ptr")
            if (stm && !DllCall("gdiplus\GdipCreateBitmapFromStream", "Ptr", stm, "Ptr*", &bmp) && bmp) {
                ; the header alone is not enough: refuse a huge canvas, then really decode
                ; the whole picture by drawing it into a small bitmap
                w := 0, h := 0
                DllCall("gdiplus\GdipGetImageWidth", "Ptr", bmp, "UInt*", &w)
                DllCall("gdiplus\GdipGetImageHeight", "Ptr", bmp, "UInt*", &h)
                if (w >= 1 && h >= 1 && w <= ThemeStore.MaxPixels && h <= ThemeStore.MaxPixels)
                    ok := ThemeStore._Decodes(bmp, w, h)
            }
        }
        if bmp
            DllCall("gdiplus\GdipDisposeImage", "Ptr", bmp)
        if stm
            ObjRelease(stm)
        if tok
            DllCall("gdiplus\GdiplusShutdown", "Ptr", tok)
        return ok
    }

    ; the file must be whole: PNG chunks all there with good CRCs up to IEND, JPEG ends
    ; with its end marker, GIF with its trailer, BMP no shorter than its header says.
    ; GDI+ alone happily shows the top of a cut-off picture.
    static _Whole(b, ext) {
        n := b.Size
        if (ext = "png") {
            pos := 8
            while (pos + 12 <= n) {
                len := (NumGet(b, pos, "UChar") << 24) | (NumGet(b, pos + 1, "UChar") << 16) | (NumGet(b, pos + 2, "UChar") << 8) | NumGet(b, pos + 3, "UChar")
                if (len < 0 || pos + 12 + len > n)
                    return false
                crc := DllCall("ntdll\RtlComputeCrc32", "UInt", 0, "Ptr", b.Ptr + pos + 4, "UInt", len + 4, "UInt")
                got := (NumGet(b, pos + 8 + len, "UChar") << 24) | (NumGet(b, pos + 9 + len, "UChar") << 16) | (NumGet(b, pos + 10 + len, "UChar") << 8) | NumGet(b, pos + 11 + len, "UChar")
                if (crc != got)
                    return false
                if (NumGet(b, pos + 4, "UInt") = 0x444E4549)      ; "IEND"
                    return true
                pos += 12 + len
            }
            return false
        }
        if (ext = "jpg") {
            i := n
            while (i > 2 && i > n - 16 && NumGet(b, i - 1, "UChar") = 0)
                i -= 1
            return (i >= 2 && NumGet(b, i - 2, "UChar") = 0xFF && NumGet(b, i - 1, "UChar") = 0xD9)
        }
        if (ext = "gif")
            return NumGet(b, n - 1, "UChar") = 0x3B
        if (ext = "bmp")
            return (n >= 14 && NumGet(b, 2, "UInt") <= n)
        return false
    }

    ; The picture's pixels in a new PNG (no metadata: the pixels are drawn
    ; into a fresh bitmap first), drawn smaller (a half each time, 6 times at
    ; most) while the PNG is over MaxPicture or a side over 4096. -> Buffer | ""
    static _ToPng(bytes) {
        tok := 0, src := 0, stm := 0, out := ""
        try {
            if (!IsObject(bytes) || bytes.Size = 0 || ThemeStore._PicExt(bytes) = "")
                return ""
            DllCall("LoadLibrary", "Str", "gdiplus", "Ptr")
            si := Buffer(24, 0), NumPut("UInt", 1, si, 0)
            if DllCall("gdiplus\GdiplusStartup", "Ptr*", &tok, "Ptr", si, "Ptr", 0)
                return ""
            stm := DllCall("shlwapi\SHCreateMemStream", "Ptr", bytes, "UInt", bytes.Size, "Ptr")
            if (!stm || DllCall("gdiplus\GdipCreateBitmapFromStream", "Ptr", stm, "Ptr*", &src) || !src)
                return ""
            w := 0, h := 0
            DllCall("gdiplus\GdipGetImageWidth", "Ptr", src, "UInt*", &w)
            DllCall("gdiplus\GdipGetImageHeight", "Ptr", src, "UInt*", &h)
            if (w < 1 || h < 1 || w > ThemeStore.MaxPixels || h > ThemeStore.MaxPixels)
                return ""
            while (Max(w, h) > 4096)
                w := Max(1, w // 2), h := Max(1, h // 2)
            Loop 7 {
                b := ThemeStore._DrawPng(src, w, h)
                if !IsObject(b)
                    break
                if (b.Size <= ThemeStore.MaxPicture) {
                    out := b
                    break
                }
                w := Max(1, w // 2), h := Max(1, h // 2)
            }
        }
        if src
            DllCall("gdiplus\GdipDisposeImage", "Ptr", src)
        if stm
            ObjRelease(stm)
        if tok
            DllCall("gdiplus\GdiplusShutdown", "Ptr", tok)
        return out
    }

    ; src drawn into a new w x h 32-bit bitmap, saved as PNG -> Buffer | ""
    static _DrawPng(src, w, h) {
        dst := 0, gr := 0, out := ""
        try {
            if (!DllCall("gdiplus\GdipCreateBitmapFromScan0", "Int", w, "Int", h, "Int", 0, "Int", 0x26200A, "Ptr", 0, "Ptr*", &dst) && dst
                && !DllCall("gdiplus\GdipGetImageGraphicsContext", "Ptr", dst, "Ptr*", &gr) && gr) {
                DllCall("gdiplus\GdipSetInterpolationMode", "Ptr", gr, "Int", 7)      ; high quality bicubic
                if !DllCall("gdiplus\GdipDrawImageRectI", "Ptr", gr, "Ptr", src, "Int", 0, "Int", 0, "Int", w, "Int", h) {
                    DllCall("gdiplus\GdipDeleteGraphics", "Ptr", gr), gr := 0
                    out := ThemeStore._Encode(dst, "png")
                }
            }
        }
        if gr
            DllCall("gdiplus\GdipDeleteGraphics", "Ptr", gr)
        if dst
            DllCall("gdiplus\GdipDisposeImage", "Ptr", dst)
        return out
    }

    ; A GDI+ image saved as "png" or "jpg" (GDI+ must be started) -> Buffer | ""
    static _Encode(img, fmt := "png") {
        stm := 0, out := ""
        try {
            clsid := Buffer(16, 0)
            DllCall("ole32\CLSIDFromString", "Str", fmt = "jpg" ? "{557CF401-1A04-11D3-9A73-0000F81EF32E}" : "{557CF406-1A04-11D3-9A73-0000F81EF32E}", "Ptr", clsid)
            stm := DllCall("shlwapi\SHCreateMemStream", "Ptr", 0, "UInt", 0, "Ptr")
            if (stm && !DllCall("gdiplus\GdipSaveImageToStream", "Ptr", img, "Ptr", stm, "Ptr", clsid, "Ptr", 0)) {
                size := 0
                ComCall(5, stm, "Int64", 0, "UInt", 2, "UInt64*", &size)       ; IStream::Seek to the end
                ComCall(5, stm, "Int64", 0, "UInt", 0, "Ptr", 0)               ; back to the start
                if (size > 0) {
                    b := Buffer(size, 0)
                    got := 0
                    ComCall(3, stm, "Ptr", b, "UInt", size, "UInt*", &got)     ; IStream::Read
                    if (got = size)
                        out := b
                }
            }
        }
        if stm
            ObjRelease(stm)
        return out
    }

    ; draws the whole bitmap into a 32x32 one: false when GDI+ cannot decode it
    static _Decodes(bmp, w, h) {
        dst := 0, gr := 0, ok := false
        try {
            if (!DllCall("gdiplus\GdipCreateBitmapFromScan0", "Int", 32, "Int", 32, "Int", 0, "Int", 0x26200A, "Ptr", 0, "Ptr*", &dst) && dst
                && !DllCall("gdiplus\GdipGetImageGraphicsContext", "Ptr", dst, "Ptr*", &gr) && gr
                && !DllCall("gdiplus\GdipDrawImageRectI", "Ptr", gr, "Ptr", bmp, "Int", 0, "Int", 0, "Int", 32, "Int", 32))
                ok := true
        }
        if gr
            DllCall("gdiplus\GdipDeleteGraphics", "Ptr", gr)
        if dst
            DllCall("gdiplus\GdipDisposeImage", "Ptr", dst)
        return ok
    }

    static ExportDir(cfg) => RTrim(cfg.dir, "\/") "\exports"

    ; Writes <cfg dir>\exports\<name>.moontheme -> the path | "" when it failed.
    ; A theme with its own picture carries the picture as base64, drawn
    ; again into a PNG through GDI+ (only the pixels: a phone photo's EXIF /
    ; GPS block never leaves the PC); a PNG over MaxPicture is drawn smaller
    ; until it fits. `note` is "" or why the picture was left out (the Look
    ; page shows it).
    static Export(cfg, name, &note := "") {
        note := ""
        try {
            name := Trim(String(name))
            if !ThemeStore.Exists(cfg, name)
                return ""
            t := ThemeStore.Load(cfg, name)
            pic := ""
            pf := t["picture"]["file"]
            if (pf != "none" && ThemeStore.PresetName(pf) = "") {
                pp := ThemeStore.Dir(cfg) "\" pf
                if (FileExist(pp) != "" && !InStr(FileExist(pp), "D")) {
                    if (FileGetSize(pp) > ThemeStore.MaxPicture)
                        note := I18n.T("The picture is too big to share, so the theme was exported without it.")
                    else {
                        png := ThemeStore._ToPng(FileRead(pp, "RAW"))
                        if IsObject(png)
                            pic := Map("bytes", png, "ext", "png")
                        else
                            note := I18n.T("The picture could not be read, so the theme was exported without it.")
                    }
                }
            }
            DirCreate(ThemeStore.ExportDir(cfg))
            path := ThemeStore.ExportDir(cfg) "\" t["name"] ThemeStore.Ext
            tmp := path ".tmp"
            f := FileOpen(tmp, "w", "UTF-8-RAW")
            try
                f.Write(ThemeStore.ToText(t, true, pic))
            finally
                f.Close()
            FileMove(tmp, path, 1)
            return path
        }
        if (IsSet(tmp))
            try FileDelete(tmp)
        return ""
    }

    ; Reads a .moontheme file, writes nothing. -> Map("theme", Map, "picBytes", Buffer | "",
    ; "picExt", "png" etc | "", "notes", [text], "clamp", [layout ids with values far
    ; outside the window]) | Map("error", why)
    static ReadFile(path) {
        try {
            path := String(path)
            a := FileExist(path)
            if (a = "" || InStr(a, "D"))
                return Map("error", I18n.T("That file could not be read."))
            if (FileGetSize(path) > ThemeStore.MaxFile)
                return Map("error", I18n.F("That file is too big (the limit is {1} MB).", ThemeStore.MaxFile // (1024 * 1024)))
            fb := FileRead(path, "RAW")
            raw := ThemeStore._Parse(StrGet(fb, fb.Size, "UTF-8"))
            notes := []
            pin := raw["picture"]
            bytes := "", ext := ""
            if (pin.Has("data") && pin["data"] != "") {
                tooBig := false
                if (StrLen(pin["data"]) > ThemeStore.MaxPicture * 4 // 3 + 8)
                    tooBig := true
                else {
                    b := ThemeStore._B64Decode(pin["data"])
                    if (IsObject(b) && b.Size > ThemeStore.MaxPicture)
                        tooBig := true
                    else if IsObject(b) {
                        e := ThemeStore._PicExt(b)
                        ok := false
                        if (e != "")
                            try ok := ThemeStore.PictureOkFn.Call(b) ? true : false
                        if ok
                            bytes := b, ext := e
                    }
                }
                if tooBig
                    notes.Push(I18n.T("The picture in the file is too big, so it was left out."))
                else if !IsObject(bytes)
                    notes.Push(I18n.T("The picture in the file is not an image, so it was left out."))
                pin["file"] := "Moontide"
            }
            if pin.Has("data")
                pin.Delete("data")
            th := ThemeStore.Clean(raw)
            if IsObject(bytes)
                th["picture"]["file"] := th["name"] "." ext
            clamp := []
            lim := ThemeStore.LayoutMax
            for id, e in th["layout"]
                if (e[1] < 0 || e[2] < 0 || e[1] > lim || e[2] > lim || e[3] < 0 || e[4] < 0 || e[3] > lim || e[4] > lim)
                    clamp.Push(id)
            if (clamp.Length)
                notes.Push(I18n.T("Some card positions were outside the window and will be pulled back in."))
            return Map("theme", th, "picBytes", bytes, "picExt", ext, "notes", notes, "clamp", clamp)
        }
        return Map("error", I18n.T("That file could not be read."))
    }

    ; Adds the theme of a ReadFile result -> the name added ("" when it failed).
    ; A taken name gets " (2)", " (3)" ... added. The picture goes to <themes dir>\<name>.<ext>.
    static Import(cfg, read) {
        pic := ""
        try {
            if (!(read is Map) || read.Has("error") || !(read.Get("theme", "") is Map))
                return ""
            t := ThemeStore.Clean(read["theme"])
            base := t["name"]
            nm := base
            n := 1
            while (ThemeStore.Exists(cfg, nm)) {
                n += 1
                suf := " (" n ")"
                nm := SubStr(base, 1, 32 - StrLen(suf)) suf
                if (n > 999)
                    return ""
            }
            t["name"] := nm
            t["preset"] := false
            bytes := read.Get("picBytes", "")
            ext := read.Get("picExt", "")
            pf := t["picture"]["file"]
            if (IsObject(bytes) && RegExMatch(ext, "^[a-z]{3,4}$")) {
                DirCreate(ThemeStore.Dir(cfg))
                pic := ThemeStore.Dir(cfg) "\" nm "." ext
                f := FileOpen(pic, "w")
                try
                    f.RawWrite(bytes)
                finally
                    f.Close()
                t["picture"]["file"] := nm "." ext
            } else if (pf != "none" && ThemeStore.PresetName(pf) = "")
                t["picture"]["file"] := "Moontide"      ; a picture file of the sender is not here
            if (ThemeStore.Save(cfg, t) = true)
                return nm
        }
        if (pic != "")
            try FileDelete(pic)
        return ""
    }

    ; The path of the theme's own picture (<themes dir>\<name>.<ext>), "" when it has none
    static _OwnPicture(cfg, name, t) {
        pf := t["picture"]["file"]
        if (SubStr(pf, 1, StrLen(name) + 1) = name "." && RegExMatch(SubStr(pf, StrLen(name) + 2), "^[A-Za-z0-9]{1,5}$")) {
            p := ThemeStore.Dir(cfg) "\" pf
            if (FileExist(p) != "" && !InStr(FileExist(p), "D"))
                return p
        }
        return ""
    }

    ; ---- migration ---------------------------------------------------------------

    ; Today's [UI] custom* colours and picture become the theme "My theme"
    ; once; UI.theme=Custom becomes "My theme". The old keys stay.
    ; -> true when something changed.
    static Migrate(cfg) {
        changed := false
        try {
            keys := Map("Bg", "UI.customBg", "PanelC", "UI.customPanel", "Text", "UI.customText", "Accent", "UI.customAccent")
            ; settings.ini always carries the custom* defaults (Moontide's): only a changed one counts
            has := false
            mp := Theme.Presets["Moontide"]
            for k, key in keys
                if (Theme.HexOk(cfg.Get(key, "")) != "" && Theme.HexOk(cfg.Get(key, "")) != mp.%k%)
                    has := true
            if !(StrLower(Trim(String(cfg.Get("UI.customPicture", "Moontide")))) = "moontide")
                has := true
            wasCustom := (Trim(String(cfg.Get("UI.theme", ""))) = Theme.CustomName)
            made := FileExist(ThemeStore._Path(cfg, ThemeStore.FallbackName)) != ""
            if (!made && (has || wasCustom) && cfg.Get("UI.themesMigrated", "") != "1") {
                t := ThemeStore.Default()
                t["name"] := ThemeStore.FallbackName
                t["preset"] := false
                for k, key in keys
                    t["colors"][k] := Theme.HexOr(cfg.Get(key, ""), t["colors"][k])
                for k in ThemeStore.DerivedKeys
                    t["colors"][k] := ""
                t["picture"]["file"] := ThemeStore._MigratePicture(cfg)
                if (ThemeStore.Save(cfg, t) = true) {
                    made := true
                    cfg.Set("UI.themesMigrated", "1")
                    changed := true
                }
            }
            if (wasCustom) {
                cfg.Set("UI.theme", made ? ThemeStore.FallbackName : "Moontide")
                changed := true
            }
            if changed
                try cfg.Save()
        }
        return changed
    }

    ; the customPicture choice as a theme picture; a picture file of your own is copied into the themes folder
    static _MigratePicture(cfg) {
        choice := Trim(String(cfg.Get("UI.customPicture", "Moontide")))
        if (choice = "none")
            return "none"
        if (choice = "file") {
            src := Trim(String(cfg.Get("UI.customPictureFile", "")), " `t`"")
            try {
                if (Theme.IsOwnPicture(src) && FileExist(src) != "" && !InStr(FileExist(src), "D")) {
                    SplitPath(src, , , &ext)
                    if RegExMatch(ext, "^[A-Za-z0-9]{1,5}$") {
                        DirCreate(ThemeStore.Dir(cfg))
                        dest := ThemeStore.FallbackName "." StrLower(ext)
                        FileCopy(src, ThemeStore.Dir(cfg) "\" dest, 1)
                        return dest
                    }
                }
            }
            return "Moontide"
        }
        n := ThemeStore.PresetName(choice)
        return (n != "") ? n : "Moontide"
    }
}
