#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\..\Brand.ahk
#Include %A_LineFile%\..\..\I18n.ahk
; ---------------------------------------------------------------------------
; Theme: Moontide Macro palette, fonts and light-weight styled controls.
;
; Palette (spec 5): bg #0D1117, panel/borders #0B2A5B (PanelC), text #F7F1E8,
; accent/active #F2A93B. Derived shades below are mixes of those four.
;
; Everything is built from plain Win32 controls (Text, Edit, ListView,
; TreeView, DropDownList, Picture): no ActiveX, no WebView, no timers.
;   - Buttons, checkboxes and on/off pills are Text controls with SS_NOTIFY
;     (themed Win32 buttons/checkboxes ignore custom colours).
;   - Hover uses one WM_MOUSEMOVE / WM_MOUSELEAVE hook (installed on first
;     use), so there is no polling.
;   - ListViews are custom-drawn (NM_CUSTOMDRAW) so selection is navy/gold
;     instead of system blue; scrollbars use the DarkMode_Explorer theme.
;     The last column fills the list (FitLastCol), so no empty extra column.
;   - Panel: a solid card (1 px FrameC border, CardBg fill) with an optional
;     gold caps title; every group of settings sits on one.
;   - Help: a 16x16 "?" whose text shows as a ToolTip while hovered (long
;     explanations live there instead of in grey sentences).
;
; Collector: while Theme.Sink is an Array, every control created through
; Theme is pushed into it (the dashboard uses this to group page controls).
;
; Language (lib\I18n.ahk): Window titles, Label / Panel / Section / ListHeader
; texts, Help tips, Button and Check labels, Segmented captions and Confirm
; texts go through I18n.T when made (unchanged in English). Dropdown items
; and Theme.SetText are not translated (callers wrap visible texts).
; ---------------------------------------------------------------------------

class Theme {
    ; spec palette
    static Bg := "0D1117"
    static PanelC := "0B2A5B"     ; navy (was "Panel"; that name is now the Panel() card)
    static Text := "F7F1E8"
    static Accent := "F2A93B"
    ; derived shades
    static SideBg := "0A1628"      ; sidebar / cards
    static CardBg := "0A1628"
    static FieldBg := "0A1A36"     ; inputs and lists
    static FrameC := "1E4780"      ; input borders, hairlines
    static HoverBg := "143A73"     ; hover / selection on navy
    static OffBg := "1B2D4F"       ; off switch, empty checkbox
    static Muted := "A8A199"       ; secondary text (warm grey)
    static Ink := "0D1117"         ; text on gold
    static AccentHi := "F7BD5E"    ; gold hover
    static Face := "Segoe UI"
    ; colour theme (Settings > Look, UI.theme): Theme.Use(name) before any
    ; window is built swaps every colour above, the running pulse shade and
    ; the dashboard background (assets\themes\, tools\make_theme_bg.py).
    static Current := "Moontide"
    static Pulse := "B5772A"       ; darker accent the Running pill pulses to
    static BgImage := "moontide_bg_dim.png"
    static Names := ["Moontide", "Overdrive", "Galaxy", "Boss", "Equinox", "Matrix", "Radiant", "Illusionary", "Contrast"]
    static Presets := Map(
        "Moontide", {Bg: "0D1117", PanelC: "0B2A5B", Text: "F7F1E8", Accent: "F2A93B", SideBg: "0A1628", CardBg: "0A1628", FieldBg: "0A1A36"
            , FrameC: "1E4780", HoverBg: "143A73", OffBg: "1B2D4F", Muted: "A8A199", Ink: "0D1117", AccentHi: "F7BD5E", Pulse: "B5772A"
            , BgImage: "moontide_bg_dim.png", Note: "Navy and gold"},
        "Overdrive", {Bg: "120A0C", PanelC: "5B0B16", Text: "F7EDEB", Accent: "FF4D57", SideBg: "1F0A0E", CardBg: "1F0A0E", FieldBg: "2A0D13"
            , FrameC: "80202E", HoverBg: "731426", OffBg: "4F1B26", Muted: "B09C9C", Ink: "120A0C", AccentHi: "FF7A82", Pulse: "B52A33"
            , BgImage: "themes\overdrive.png", Note: "Red, Matrix : Overdrive"},
        "Galaxy", {Bg: "0B0B1A", PanelC: "1E1B5B", Text: "EEF0FA", Accent: "8F9BFF", SideBg: "100F28", CardBg: "100F28", FieldBg: "141336"
            , FrameC: "3A3A8F", HoverBg: "26256E", OffBg: "22214A", Muted: "A4A6C2", Ink: "0B0B1A", AccentHi: "B3BCFF", Pulse: "5A63C2"
            , BgImage: "themes\galaxy.png", Note: "Blue-violet, a galaxy"},
        "Boss", {Bg: "11120A", PanelC: "3F4A12", Text: "F5F4E6", Accent: "C8E04A", SideBg: "1B1F0B", CardBg: "1B1F0B", FieldBg: "232A0E"
            , FrameC: "66782A", HoverBg: "4A5A18", OffBg: "343D1A", Muted: "ABAE96", Ink: "11120A", AccentHi: "DCF07A", Pulse: "8A9E2C"
            , BgImage: "themes\boss.png", Note: "Green and gold, Boss Preview"},
        "Equinox", {Bg: "0E0E0E", PanelC: "3A3A3A", Text: "F4F4F4", Accent: "E6E6E6", SideBg: "181818", CardBg: "181818", FieldBg: "222222"
            , FrameC: "6A6A6A", HoverBg: "4A4A4A", OffBg: "2E2E2E", Muted: "A8A8A8", Ink: "0E0E0E", AccentHi: "FFFFFF", Pulse: "8A8A8A"
            , BgImage: "themes\equinox.png", Note: "Black and white, 1 in 2,500,000,000"},
        "Matrix", {Bg: "140C07", PanelC: "5B2A0B", Text: "F7EFE8", Accent: "FF8A2B", SideBg: "24120A", CardBg: "24120A", FieldBg: "30170C"
            , FrameC: "80421E", HoverBg: "733614", OffBg: "4F2C1B", Muted: "B0A196", Ink: "140C07", AccentHi: "FFA95E", Pulse: "B55E1E"
            , BgImage: "themes\matrix.png", Note: "Orange, Matrix"},
        "Radiant", {Bg: "0D0A18", PanelC: "2E1660", Text: "F1EEFA", Accent: "A97BFF", SideBg: "160F2C", CardBg: "160F2C", FieldBg: "1D1338"
            , FrameC: "4F3196", HoverBg: "3A2278", OffBg: "2C2150", Muted: "ABA3C4", Ink: "0D0A18", AccentHi: "C4A5FF", Pulse: "7048C2"
            , BgImage: "themes\radiant.png", Note: "Purple, The Radiant Forest"},
        "Illusionary", {Bg: "060A1C", PanelC: "0B2A8F", Text: "F2F5FF", Accent: "4D7CFF", SideBg: "0A1236", CardBg: "0A1236", FieldBg: "0C1744"
            , FrameC: "2447C2", HoverBg: "1A35A6", OffBg: "1A2A5E", Muted: "A2ACCC", Ink: "060A1C", AccentHi: "85A6FF", Pulse: "2E55C2"
            , BgImage: "themes\illusionary.png", Note: "Electric blue, Illusionary"},
        ; high contrast (idea 8): black, white text, yellow highlights, no picture
        "Contrast", {Bg: "000000", PanelC: "4A4A4A", Text: "FFFFFF", Accent: "FFD400", SideBg: "000000", CardBg: "0A0A0A", FieldBg: "1C1C1C"
            , FrameC: "BDBDBD", HoverBg: "333333", OffBg: "2A2A2A", Muted: "E0E0E0", Ink: "000000", AccentHi: "FFE45C", Pulse: "A68A00"
            , BgImage: "themes\contrast.png", Note: "High contrast: black, white and yellow, easy to read"})
    static ThemeKeys := ["Bg", "PanelC", "Text", "Accent", "SideBg", "CardBg", "FieldBg", "FrameC", "HoverBg", "OffBg", "Muted", "Ink", "AccentHi", "Pulse", "BgImage"]

    ; A preset's name as listed (any case), "Moontide" when it is no preset.
    static ThemeName(name) {
        name := Trim(String(name))
        for n in Theme.Names
            if (n = name)
                return n
        return "Moontide"
    }

    ; The saved-themes folder lives under this Config (settings.ini's folder).
    ; App sets it at start; it stays "" in tests and tools, where Use and
    ; Apply know the nine presets only.
    static Cfg := ""
    static Scale := 100            ; window size in percent (theme.ui.scale)
    static Sidebar := "left"       ; left | right | top (theme.ui.sidebar)
    static Layout := Map()         ; theme.layout: "<page>:<card>" -> [x, y, w, h, hidden] (Dashboard reads it)
    static PictureSpec := Map("file", "Moontide", "fit", "fill", "dim", 60)
    static _FontBase := ""         ; the built-in Theme.Fonts, kept before the first Apply

    ; Every colour of theme `name` (a preset in any case, a saved theme when
    ; Theme.Cfg is set; unknown -> Moontide). Call before windows are built:
    ; existing controls keep their colours. A shim over Apply. -> the name used.
    static Use(name) {
        raw := Trim(String(name))
        n := Theme.ThemeName(raw)
        if (ThemeStore.PresetName(raw) = "" && IsObject(Theme.Cfg)) {
            try {
                if ThemeStore.Exists(Theme.Cfg, raw) {
                    Theme.Apply(ThemeStore.Load(Theme.Cfg, raw))
                    return Theme.Current
                }
            }
        }
        Theme.Apply(ThemeStore.Preset(n))
        return n
    }

    ; Make `th` (a ThemeStore Map) the one shown: every colour (the 4 base
    ; ones, Derive for the rest, then the derived colours the theme sets
    ; itself), Theme.Fonts, Scale, Sidebar, PictureSpec and BgImage. Call
    ; before windows are built. A bad theme never throws: Moontide is applied
    ; instead (and the reason goes to the debug output).
    static Apply(th) {
        Theme.ApplyWhy := ""
        try {
            Theme._Apply(ThemeStore.Clean(th))
            return Theme.Current
        } catch as e {
            try OutputDebug("Theme.Apply failed, using Moontide: " e.Message)
            Theme.ApplyWhy := "its settings could not be used"
        }
        try Theme._Apply(ThemeStore.Default())
        return Theme.Current
    }
    static ApplyWhy := ""          ; why the last Apply fell back to Moontide ("" when it did not)

    static _Apply(t) {
        c := t["colors"]
        d := Theme.Derive(c["Bg"], c["PanelC"], c["Text"], c["Accent"])
        for k in Theme.BaseKeys
            Theme.%k% := d.%k%
        for k in ThemeStore.DerivedKeys
            Theme.%k% := (c[k] != "") ? c[k] : d.%k%
        Theme._ApplyFonts(t["fonts"])
        Theme.Scale := t["ui"]["scale"]
        Theme.Sidebar := t["ui"]["sidebar"]
        Theme.Layout := t["layout"]
        pic := t["picture"]
        Theme.PictureSpec := Map("file", pic["file"], "fit", pic["fit"], "dim", pic["dim"])
        Theme.BgImage := Theme._PictureFile(pic["file"])
        Theme.Current := t["name"]
    }

    ; the dashboard picture for a theme's picture.file: "" (none), a preset's
    ; art (relative to assets), or the full path of a file in the themes folder
    static _PictureFile(file) {
        file := Trim(String(file))
        if (file = "" || file = "none")
            return ""
        n := ThemeStore.PresetName(file)
        if (n != "")
            return Theme.Presets[n].BgImage
        if IsObject(Theme.Cfg) {
            path := ThemeStore.Dir(Theme.Cfg) "\" file
            if (!RegExMatch(file, "[\\/:]") && FileExist(path) != "" && !InStr(FileExist(path), "D"))
                return path
        }
        return ""
    }

    ; The built-in Theme.Fonts as they were before any Apply (a copy kept on
    ; first use; Apply rewrites Theme.Fonts, never this).
    static DefaultFonts() {
        if !IsObject(Theme._FontBase) {
            Theme._FontBase := Map()
            for r, f in Theme.Fonts
                Theme._FontBase[r] := f.Clone()
        }
        return Theme._FontBase
    }

    ; fonts: title, head, body, button, nav, small as the theme says. muted and
    ; caps take small's family and grow with its size (their own size + small's
    ; size - 8), brand follows title, value and big follow head's family. A
    ; family the theme leaves at its built-in one keeps that role's own
    ; built-in family (caps stays semibold), so the presets are unchanged.
    static _ApplyFonts(fonts) {
        b := Theme.DefaultFonts()
        out := Map()
        for r, f in b
            out[r] := f.Clone()
        size := (r) => Integer(RegExReplace(b[r][1], "^s(\d+).*$", "$1"))
        follow := (role, base, fam, sz) => out[role] := ["s" Max(6, sz) " norm", (fam = b[base][2]) ? b[role][2] : fam, b[role][3]]
        for r in ["title", "head", "body", "button", "nav", "small"]
            out[r] := ["s" fonts[r][2] " norm", fonts[r][1], b[r][3]]
        ds := fonts["small"][2] - size("small")
        follow("muted", "small", fonts["small"][1], size("muted") + ds)
        follow("caps", "small", fonts["small"][1], size("caps") + ds)
        dt := fonts["title"][2] - size("title")
        follow("brand", "title", fonts["title"][1], size("brand") + dt)
        follow("value", "head", fonts["head"][1], size("value"))
        follow("big", "head", fonts["head"][1], size("big"))
        for r, f in out
            Theme.Fonts[r] := f
    }

    ; ---- colours (the Look page edits a theme's 4 base colours) -----------------
    ; Derive mixes the other keys from Bg, PanelC, Text and Accent the way
    ; the presets relate to their own 4 (checked against Moontide / Galaxy).
    ; CustomName: the old [UI] theme=Custom, which ThemeStore.Migrate turns
    ; into "My theme"; it is no theme name any more.
    static CustomName := "Custom"
    static BaseKeys := ["Bg", "PanelC", "Text", "Accent"]

    ; the short description of a preset
    static NoteOf(name) => Theme.Presets[Theme.ThemeName(name)].Note

    ; "RRGGBB" (upper case) from "rrggbb" / "#RRGGBB" with spaces; "" when not
    ; exactly 6 hex digits. Never throws.
    static HexOk(s) {
        try {
            s := Trim(String(s))
            if (SubStr(s, 1, 1) = "#")
                s := SubStr(s, 2)
            return RegExMatch(s, "^[0-9A-Fa-f]{6}$") ? StrUpper(s) : ""
        }
        return ""
    }

    ; HexOk(s), or def when s is no colour ("000000" is a colour, so no ||)
    static HexOr(s, def) {
        h := Theme.HexOk(s)
        return (h != "") ? h : def
    }

    ; a + (b - a) * t per channel (t 0..1) -> "RRGGBB"
    static Mix(a, b, t) {
        va := Integer("0x" a), vb := Integer("0x" b)
        out := 0
        for sh in [16, 8, 0] {
            ca := (va >> sh) & 0xFF, cb := (vb >> sh) & 0xFF
            out |= Max(0, Min(255, Round(ca + (cb - ca) * t))) << sh
        }
        return Format("{:06X}", out)
    }

    ; WCAG relative luminance 0..1 and contrast ratio 1..21
    static Lum(hex) {
        v := Integer("0x" hex), l := 0
        wt := [0.2126, 0.7152, 0.0722]
        for i, sh in [16, 8, 0] {
            c := ((v >> sh) & 0xFF) / 255
            c := (c <= 0.03928) ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4
            l += wt[i] * c
        }
        return l
    }

    static Contrast(a, b) {
        la := Theme.Lum(a), lb := Theme.Lum(b)
        return (Max(la, lb) + 0.05) / (Min(la, lb) + 0.05)
    }

    ; of the candidates, the one that reads best on bg
    static BestOn(bg, cands*) {
        best := cands[1], bc := -1
        for c in cands {
            r := Theme.Contrast(c, bg)
            if (r > bc)
                best := c, bc := r
        }
        return best
    }

    ; Every theme key from the 4 base colours (bad hex -> Moontide's) and a
    ; BgImage ("" = none, an assets-relative path or a file of your own).
    ; Text too close to the panels for reading becomes white or black
    ; (.TextFixed true); Ink (text on the accent) is the dark background
    ; when it reads, else whichever of the text, black or white reads best.
    static Derive(bg, panel, text, accent, bgImage := "") {
        m := Theme.Presets["Moontide"]
        bg := Theme.HexOr(bg, m.Bg)
        panel := Theme.HexOr(panel, m.PanelC)
        text := Theme.HexOr(text, m.Text)
        accent := Theme.HexOr(accent, m.Accent)
        card := Theme.Mix(bg, panel, 0.22)
        fixed := false
        if (Theme.Contrast(text, card) < 3) {
            text := Theme.BestOn(card, "FFFFFF", "000000")
            fixed := true
        }
        ink := (Theme.Contrast(bg, accent) >= 4.5) ? bg : Theme.BestOn(accent, text, "000000", "FFFFFF")
        o := {Bg: bg, PanelC: panel, Text: text, Accent: accent
            , SideBg: card, CardBg: card
            , FieldBg: Theme.Mix(bg, panel, 0.42)
            , FrameC: Theme.Mix(panel, text, 0.15)
            , HoverBg: Theme.Mix(panel, text, 0.08)
            , OffBg: Theme.Mix(Theme.Mix(panel, bg, 0.35), Theme.Mix(text, bg, 0.33), 0.1)
            , Muted: Theme.Mix(text, card, 0.33)
            , Ink: ink
            , AccentHi: Theme.Mix(accent, Theme.Lum(accent) > 0.6 ? "000000" : "FFFFFF", 0.2)
            , Pulse: Theme.Mix(accent, bg, 0.28)
            , BgImage: String(bgImage), Note: "Your own colours", TextFixed: fixed}
        o.Sig := bg panel text accent "|" o.BgImage
        return o
    }

    ; true when BgImage is a picture of the user's own (a full path)
    static IsOwnPicture(p) => RegExMatch(String(p), "^([A-Za-z]:\\|\\\\)") ? true : false

    ; Win32 colour dialog (comdlg32 ChooseColorW) opened on hex. -> the
    ; picked "RRGGBB", or "" when cancelled / on any failure.
    static PickColor(ownerHwnd, hex) {
        static cust := Buffer(64, 0xFF)
        try {
            hex := Theme.HexOr(hex, "000000")
            ps := A_PtrSize
            cc := Buffer(ps = 8 ? 72 : 36, 0)
            NumPut("UInt", cc.Size, cc, 0)
            NumPut("Ptr", ownerHwnd, cc, ps)
            NumPut("UInt", Theme.BGR(hex), cc, ps * 3)
            NumPut("Ptr", cust.Ptr, cc, ps * 4)
            NumPut("UInt", 0x3, cc, ps * 5)            ; CC_RGBINIT | CC_FULLOPEN
            if !DllCall("comdlg32\ChooseColorW", "Ptr", cc, "Int")
                return ""
            v := NumGet(cc, ps * 3, "UInt")
            return Format("{:02X}{:02X}{:02X}", v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF)
        }
        return ""
    }

    ; A picture for the dashboard background placed in w x h and darkened
    ; with bg at `dim` (0..1) so panels and text read on it. fit: "fill" =
    ; cover, centred crop; "fit" = the whole picture, letterboxed in bg;
    ; "center" = no scaling, bg around it; "tile" = repeated at its own
    ; size. Only the w x h result stays in memory.
    ; -> HBITMAP (the Picture control takes it) | 0 when the file is
    ; missing, too big, not a picture or GDI+ fails.
    static DimPicture(path, w, h, bg, dim := 0.6, fit := "fill") {
        tok := 0, src := 0, dst := 0, gr := 0, br := 0, tb := 0, hbm := 0
        try {
            a := FileExist(path)
            if (a = "" || InStr(a, "D") || FileGetSize(path) > 40 * 1024 * 1024)
                return 0
            DllCall("LoadLibrary", "Str", "gdiplus", "Ptr")
            si := Buffer(24, 0), NumPut("UInt", 1, si, 0)
            if DllCall("gdiplus\GdiplusStartup", "Ptr*", &tok, "Ptr", si, "Ptr", 0)
                return 0
            if (DllCall("gdiplus\GdipCreateBitmapFromFile", "WStr", path, "Ptr*", &src) || !src)
                return 0
            iw := 0, ih := 0
            DllCall("gdiplus\GdipGetImageWidth", "Ptr", src, "UInt*", &iw)
            DllCall("gdiplus\GdipGetImageHeight", "Ptr", src, "UInt*", &ih)
            if (iw < 1 || ih < 1 || iw * ih > 80000000)
                return 0
            if (DllCall("gdiplus\GdipCreateBitmapFromScan0", "Int", w, "Int", h, "Int", 0, "Int", 0x26200A, "Ptr", 0, "Ptr*", &dst) || !dst)
                return 0
            if DllCall("gdiplus\GdipGetImageGraphicsContext", "Ptr", dst, "Ptr*", &gr)
                return 0
            DllCall("gdiplus\GdipSetInterpolationMode", "Ptr", gr, "Int", 7)
            bgc := 0xFF000000 | (Integer("0x" bg) & 0xFFFFFF)
            DllCall("gdiplus\GdipGraphicsClear", "Ptr", gr, "UInt", bgc)
            fit := StrLower(String(fit))
            if (fit = "tile") {
                if (!DllCall("gdiplus\GdipCreateTexture", "Ptr", src, "Int", 0, "Ptr*", &tb) && tb)
                    DllCall("gdiplus\GdipFillRectangleI", "Ptr", gr, "Ptr", tb, "Int", 0, "Int", 0, "Int", w, "Int", h)
            } else {
                if (fit = "center")
                    s := 1
                else if (fit = "fit")
                    s := Min(w / iw, h / ih)
                else
                    s := Max(w / iw, h / ih)
                dw := Max(1, Round(iw * s)), dh := Max(1, Round(ih * s))
                DllCall("gdiplus\GdipDrawImageRectI", "Ptr", gr, "Ptr", src, "Int", (w - dw) // 2, "Int", (h - dh) // 2, "Int", dw, "Int", dh)
            }
            DllCall("gdiplus\GdipDisposeImage", "Ptr", src), src := 0
            argb := (Round(Max(0, Min(1, dim)) * 255) << 24) | (Integer("0x" bg) & 0xFFFFFF)
            DllCall("gdiplus\GdipCreateSolidFill", "UInt", argb, "Ptr*", &br)
            if br
                DllCall("gdiplus\GdipFillRectangleI", "Ptr", gr, "Ptr", br, "Int", 0, "Int", 0, "Int", w, "Int", h)
            if DllCall("gdiplus\GdipCreateHBITMAPFromBitmap", "Ptr", dst, "Ptr*", &hbm, "UInt", bgc)
                return 0
            return hbm
        } catch
            return 0
        finally {
            if tb
                DllCall("gdiplus\GdipDeleteBrush", "Ptr", tb)
            if br
                DllCall("gdiplus\GdipDeleteBrush", "Ptr", br)
            if gr
                DllCall("gdiplus\GdipDeleteGraphics", "Ptr", gr)
            if src
                DllCall("gdiplus\GdipDisposeImage", "Ptr", src)
            if dst
                DllCall("gdiplus\GdipDisposeImage", "Ptr", dst)
            if tok
                DllCall("gdiplus\GdiplusShutdown", "Ptr", tok)
        }
    }

    static Sink := ""
    static _hot := Map()           ; hwnd -> {gui, click, hover, enabled}
    static _frames := Map()        ; edit hwnd -> frame Text ctrl
    static _trans := Map()         ; hwnd of BackgroundTrans labels
    static _roles := Map()         ; label hwnd -> font role ("muted", ...)
    static _help := Map()          ; "?" hwnd -> its help text
    static _act := Map()           ; switch caption / button hwnd -> true (a setting's own text, for the search ranking)
    static _btn := Map()           ; Theme.Button hwnd -> the point size its text uses (FitButton)
    static _src := Map()           ; Label / button / switch caption / "?" hwnd -> the English text it was made from
    static _panels := Map()        ; panel frame / fill hwnd -> true
    static HelpTip := 20           ; ToolTip number used by Help
    static _hoverHwnd := 0
    static _hooked := false

    ; ---- basics -------------------------------------------------------------

    static AssetPath(name) {
        return RegExReplace(A_LineFile, "\\lib\\ui\\[^\\]+$", "") "\assets\" name
    }

    ; A window size in Gui units -> screen px. A Gui (DPIScale on) grows its
    ; w / h with the Windows scale, but a Show x / y is plain screen px: a
    ; spot worked out from the size must use this (1920x1080 at 125%: the
    ; card / overlay put "W px from the right" ran off the screen).
    ; DpiFn: tests set it (A_ScreenDPI is read-only).
    static DpiFn := () => A_ScreenDPI
    static Dpi(n) {
        d := 96
        try d := Theme.DpiFn.Call()
        return Round(n * ((IsNumber(d) && d > 0) ? d : 96) / 96)
    }

    ; "RRGGBB" -> COLORREF (0x00BBGGRR)
    static BGR(hex) {
        v := Integer("0x" hex)
        return ((v & 0xFF) << 16) | (v & 0xFF00) | ((v >> 16) & 0xFF)
    }

    static Fonts := Map(
        "body", ["s10 norm", "Segoe UI", "Text"],
        "muted", ["s9 norm", "Segoe UI", "Muted"],
        "small", ["s8 norm", "Segoe UI", "Muted"],
        "caps", ["s8 norm", "Segoe UI Semibold", "Muted"],
        "head", ["s11 norm", "Segoe UI Semibold", "Accent"],
        "title", ["s20 norm", "Segoe UI Light", "Text"],
        "brand", ["s20 norm", "Segoe UI Semilight", "Text"],
        "value", ["s12 norm", "Segoe UI Semibold", "Text"],
        "big", ["s16 norm", "Segoe UI Semibold", "Text"],
        "button", ["s10 norm", "Segoe UI Semibold", "Text"],
        "nav", ["s10 norm", "Segoe UI", "Muted"],
        "glyph", ["s9 bold", "Segoe UI Symbol", "Ink"]
    )

    ; The font option string of a role ("s10 norm"), its size multiplied by
    ; the UI size when `scaled` (s10 at 130 % -> s13).
    static FontOpt(role := "body", scaled := true) {
        f := Theme.Fonts.Has(role) ? Theme.Fonts[role] : Theme.Fonts["body"]
        o := f[1]
        if (scaled && Theme.Scale != 100 && RegExMatch(o, "(?<=^|\s)s(\d+)", &m))
            o := SubStr(o, 1, m.Pos) Max(6, Theme.S(m[1])) SubStr(o, m.Pos + m.Len)
        return o
    }

    static Font(g, role := "body", color := "") {
        f := Theme.Fonts.Has(role) ? Theme.Fonts[role] : Theme.Fonts["body"]
        c := (color != "") ? color : Theme.%f[3]%
        g.SetFont(Theme.FontOpt(role, Theme.IsScaled(g)) " c" c, f[2])
    }

    ; ---- UI size (Theme.Scale 100 / 115 / 130) ------------------------------
    ; Only windows made with Theme.Window(..., true) (the dashboard) scale;
    ; the overlay, wizard, cards and dialogs keep their own sizes. All page
    ; code works in 100 % units: Theme.Add scales x / y / w / h, Theme.Pos
    ; reads a control back in 100 % units and Theme.MoveTo moves in them, so
    ; nothing is scaled twice. Theme.Dpi (the Windows scale, for screen px)
    ; is a separate factor.

    static _scaled := Map()        ; hwnd of the windows that scale

    static IsScaled(g) {
        try return Theme._scaled.Has(g.Hwnd)
        return false
    }

    static S(n) => Round(n * Theme.Scale / 100)

    ; Every x / y / w / h number of an options string times the UI size
    ; (also after xm / yp / xs ..., "xm+10" -> "xm+13"). Options like +0x200,
    ; -E0x200, Limit7, Background.., c.., s.. and r.. stay as they are.
    static ScaleOpts(opts) {
        if (Theme.Scale = 100)
            return opts
        out := "", pos := 1
        while RegExMatch(opts, "i)(?<=^|\s)([xywh][mps]?)([+-]?)(\d+)(?=\s|$)", &m, pos) {
            out .= SubStr(opts, pos, m.Pos - pos) m[1] m[2] Theme.S(m[3])
            pos := m.Pos + m.Len
        }
        return out SubStr(opts, pos)
    }

    ; A ListView column width ("54" or "54 Center") times the UI size.
    static _ColOpt(g, wd) {
        if (!Theme.IsScaled(g) || !RegExMatch(String(wd), "^(\s*)(\d+)(.*)$", &m))
            return wd
        return m[1] Theme.S(m[2]) m[3]
    }

    ; A control's place in 100 % units (GetPos undone).
    static Pos(ctrl) {
        ctrl.GetPos(&x, &y, &w, &h)
        if (Theme.IsScaled(ctrl.Gui) && Theme.Scale != 100)
            x := Round(x * 100 / Theme.Scale), y := Round(y * 100 / Theme.Scale), w := Round(w * 100 / Theme.Scale), h := Round(h * 100 / Theme.Scale)
        return {x: x, y: y, w: w, h: h}
    }

    ; ctrl.Move in 100 % units; "" leaves a value as it is.
    static MoveTo(ctrl, x := "", y := "", w := "", h := "") {
        ctrl.GetPos(&cx, &cy, &cw, &ch)         ; an omitted value keeps the current one
        k := Theme.IsScaled(ctrl.Gui)
        ctrl.Move(x = "" ? cx : (k ? Theme.S(x) : x), y = "" ? cy : (k ? Theme.S(y) : y)
            , w = "" ? cw : (k ? Theme.S(w) : w), h = "" ? ch : (k ? Theme.S(h) : h))
    }

    ; The largest of 130 / 115 / 100 that is at most `want` and whose window
    ; (winW x winH in 100 % units) fits workW x workH screen px. The window
    ; is counted at the Windows scale (Theme.Dpi) plus an allowance for the
    ; title bar and borders (16 px wide, 40 px high); 100 when nothing fits.
    static FitScale(want, workW, workH, winW, winH) {
        for sc in [130, 115, 100] {
            if (sc > want)
                continue
            if (Theme.Dpi(Round(winW * sc / 100)) + 16 <= workW && Theme.Dpi(Round(winH * sc / 100)) + 40 <= workH)
                return sc
        }
        return 100
    }

    ; The primary monitor's work area -> {w, h}. Tests replace the hook.
    static WorkAreaFn := () => Theme._WorkArea()
    static _WorkArea() {
        l := 0, t := 0, r := 1920, b := 1080
        try MonitorGetWorkArea(MonitorGetPrimary(), &l, &t, &r, &b)
        return {w: r - l, h: b - t}
    }

    static Add(g, type, opts := "", text := "") {
        if (type = "Text")
            opts .= " +0x80"                ; SS_NOPREFIX: show "&" literally
        if Theme.IsScaled(g)
            opts := Theme.ScaleOpts(opts)
        c := g.Add(type, opts, text)
        if (Theme.Sink is Array)
            Theme.Sink.Push(c)
        return c
    }

    ; Window with the palette, dark title bar (Win10 1809+/Win11 caption colours).
    ; scaled true: the window follows the UI size (Theme.Scale); see above.
    static Window(title, opts := "", scaled := false) {
        g := Gui(opts, I18n.T(title))
        if scaled
            Theme._scaled[g.Hwnd] := true
        g.BackColor := Theme.Bg
        g.MarginX := 0, g.MarginY := 0
        Theme.Font(g, "body")
        Theme.DarkCaption(g.Hwnd)
        return g
    }

    static DarkCaption(hwnd) {
        try {
            v := Buffer(4, 0)
            NumPut("Int", Theme.IsLight() ? 0 : 1, v)          ; a light custom theme: the light caption
            DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", hwnd, "UInt", 20, "Ptr", v, "UInt", 4)
            for attr, col in Map(34, Theme.PanelC, 35, Theme.Bg, 36, Theme.Text) {
                NumPut("UInt", Theme.BGR(col), v)
                DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", hwnd, "UInt", attr, "Ptr", v, "UInt", 4)
            }
        }
    }

    ; A light background (a light saved theme): the system's light control
    ; look (Explorer / CFD), so drop-downs, scrollbars and lists are not
    ; drawn dark with light text on a light window
    static DarkTheme(hwnd, cls := "DarkMode_Explorer") {
        if Theme.IsLight()
            cls := RegExReplace(cls, "^DarkMode_")
        try DllCall("uxtheme\SetWindowTheme", "Ptr", hwnd, "Str", cls, "Ptr", 0)
    }

    ; the window background is light (luminance over 0.4: a light saved theme)
    static IsLight() {
        try return Theme.Lum(Theme.HexOr(Theme.Bg, "000000")) > 0.4
        return false
    }

    ; ---- static shapes / labels ----------------------------------------------

    static Rect(g, x, y, w, h, color) {
        return Theme.Add(g, "Text", "x" x " y" y " w" w " h" h " Background" color)
    }

    ; bg = "" -> transparent over whatever is behind (e.g. the art).
    static Label(g, opts, text, role := "body", bg := "", color := "") {
        Theme.Font(g, role, color)
        c := Theme.Add(g, "Text", opts (bg = "" ? " BackgroundTrans" : " Background" bg), I18n.T(text))
        if (bg = "")
            Theme._trans[c.Hwnd] := true
        Theme._roles[c.Hwnd] := role
        Theme._src[c.Hwnd] := String(text)
        return c
    }

    ; The English text a Label, Button, switch caption or "?" was made from
    ; ("" for any other control). The search index reads it.
    static IsActionText(ctrl) => Theme._act.Has(ctrl.Hwnd)

    static SourceOf(ctrl) {
        try return Theme._src.Has(ctrl.Hwnd) ? Theme._src[ctrl.Hwnd] : ""
        return ""
    }

    ; Font role a Label was made with ("" for other controls).
    static RoleOf(ctrl) => Theme._roles.Has(ctrl.Hwnd) ? Theme._roles[ctrl.Hwnd] : ""

    ; Solid card: 1 px FrameC border, CardBg fill, optional title in small
    ; gold capitals at x+12, y+8. -> Array of its ctrls (frame first).
    static Panel(g, x, y, w, h, title := "") {
        parts := [Theme.Rect(g, x, y, w, h, Theme.FrameC), Theme.Rect(g, x + 1, y + 1, w - 2, h - 2, Theme.CardBg)]
        Theme.Inset(parts[1], parts[2])
        for c in parts
            Theme._panels[c.Hwnd] := true
        if (title != "")
            parts.Push(Theme.Label(g, "x" x + 12 " y" y + 8 " w" w - 52 " h16", StrUpper(title), "caps", Theme.CardBg, Theme.Accent))
        return parts
    }

    static IsPanel(ctrl) => Theme._panels.Has(ctrl.Hwnd)

    ; `inner` to `outer`'s real place less d px on every side. At 115 / 130 %
    ; a frame and its fill scaled one by one round apart (x 204 w 808 at
    ; 130 %: frame 265..1315, fill 267..1315), so the fill hid the frame's
    ; right or bottom line; the fill is placed from the frame instead.
    static Inset(outer, inner, d := 1) {
        try {
            outer.GetPos(&x, &y, &w, &h)
            inner.Move(x + d, y + d, Max(0, w - 2 * d), Max(0, h - 2 * d))
        }
    }

    ; 16x16 "?" in Muted; hovering (or clicking) shows `text` as a ToolTip
    ; by the mouse, leaving hides it.
    static Help(g, x, y, text) {
        src := String(text)
        text := I18n.T(text)
        Theme.Font(g, "caps")
        c := Theme.Add(g, "Text", "x" x " y" y " w16 h16 +0x100 +0x200 Center Background" Theme.OffBg " c" Theme.Muted, "?")
        Theme._help[c.Hwnd] := text
        Theme._src[c.Hwnd] := src
        Theme.Clickable(c, (*) => Theme._HelpTip(c, true), (on) => Theme._HelpTip(c, on))
        return c
    }

    ; The help text of a "?" made by Help ("" for any other control).
    static HelpText(ctrl) => Theme._help.Has(ctrl.Hwnd) ? Theme._help[ctrl.Hwnd] : ""

    static _HelpTip(c, on) {
        Theme.SetColors(c, Theme.OffBg, on ? Theme.Accent : Theme.Muted)
        if on
            ToolTip(Theme.Wrap(Theme._help[c.Hwnd]), , , Theme.HelpTip)
        else
            ToolTip(, , , Theme.HelpTip)
    }

    ; Word-wraps each line of s at `width` characters (ToolTips do not wrap).
    static Wrap(s, width := 64) {
        lines := []
        for para in StrSplit(String(s), "`n", "`r") {
            line := ""
            for word in StrSplit(para, " ") {
                if (line != "" && StrLen(line) + 1 + StrLen(word) > width) {
                    lines.Push(line)
                    line := word
                } else
                    line := (line = "") ? word : line " " word
            }
            lines.Push(line)
        }
        out := ""
        for i, l in lines
            out .= (i > 1 ? "`n" : "") l
        return out
    }

    ; Gold section header with a short gold rule under it.
    static Section(g, x, y, title, bg := "") {
        c := Theme.Label(g, "x" x " y" y " w300 h22", title, "head", bg)
        Theme.Rect(g, x + 1, y + 24, 24, 1, Theme.Accent)
        return c
    }

    static Moon(g, x, y, size := 40) {
        p := Theme.AssetPath("vesper_moon.png")
        if FileExist(p)
            return Theme.Add(g, "Picture", "x" x " y" y " w" size " h" size, p)
        return Theme.Label(g, "x" x " y" y " w" size " h" size " Center", Chr(0x263E), "big", "", Theme.Accent)
    }

    ; A header moon frame (a white PNG, tools\make_moon.py) in color (hex
    ; RRGGBB, the theme's Accent: Equinox white) laid on bg (hex): every
    ; pixel keeps its alpha and takes color, then GDI+ blends it onto bg.
    ; -> an HBITMAP the caller frees | 0 on any failure (LoadPicture then)
    static MoonBitmap(path, color, bg) {
        tok := 0, bmp := 0, hbm := 0
        try {
            DllCall("LoadLibrary", "Str", "gdiplus", "Ptr")
            si := Buffer(24, 0), NumPut("UInt", 1, si, 0)
            if DllCall("gdiplus\GdiplusStartup", "Ptr*", &tok, "Ptr", si, "Ptr", 0)
                return 0
            if (DllCall("gdiplus\GdipCreateBitmapFromFile", "WStr", path, "Ptr*", &bmp) || !bmp)
                return 0
            w := 0, h := 0
            DllCall("gdiplus\GdipGetImageWidth", "Ptr", bmp, "UInt*", &w)
            DllCall("gdiplus\GdipGetImageHeight", "Ptr", bmp, "UInt*", &h)
            rect := Buffer(16, 0), NumPut("Int", w, rect, 8), NumPut("Int", h, rect, 12)
            bd := Buffer(32, 0)     ; BitmapData: Width, Height, Stride, PixelFormat, Scan0, Reserved
            if DllCall("gdiplus\GdipBitmapLockBits", "Ptr", bmp, "Ptr", rect, "UInt", 3, "Int", 0x26200A, "Ptr", bd)
                return 0
            stride := NumGet(bd, 8, "Int"), scan := NumGet(bd, 16, "Ptr")
            rgb := Integer("0x" color) & 0xFFFFFF
            Loop h {
                row := scan + (A_Index - 1) * stride
                Loop w {
                    p := row + (A_Index - 1) * 4
                    NumPut("UInt", (NumGet(p, 3, "UChar") << 24) | rgb, p)
                }
            }
            DllCall("gdiplus\GdipBitmapUnlockBits", "Ptr", bmp, "Ptr", bd)
            if DllCall("gdiplus\GdipCreateHBITMAPFromBitmap", "Ptr", bmp, "Ptr*", &hbm, "UInt", 0xFF000000 | (Integer("0x" bg) & 0xFFFFFF))
                return 0
            return hbm
        } catch
            return 0
        finally {
            if bmp
                DllCall("gdiplus\GdipDisposeImage", "Ptr", bmp)
            if tok
                DllCall("gdiplus\GdiplusShutdown", "Ptr", tok)
        }
    }

    ; Width of `text` (the control's own text when omitted) in the
    ; control's font, real (Gui) px; 0 when it cannot be measured.
    static TextW(ctrl, text?) {
        w := 0
        try {
            t := IsSet(text) ? String(text) : ctrl.Text
            hdc := DllCall("GetDC", "Ptr", ctrl.Hwnd, "Ptr")
            old := DllCall("SelectObject", "Ptr", hdc, "Ptr", SendMessage(0x31, 0, 0, ctrl.Hwnd), "Ptr")   ; WM_GETFONT
            sz := Buffer(8, 0)
            DllCall("GetTextExtentPoint32W", "Ptr", hdc, "Str", t, "Int", StrLen(t), "Ptr", sz)
            DllCall("SelectObject", "Ptr", hdc, "Ptr", old)
            DllCall("ReleaseDC", "Ptr", ctrl.Hwnd, "Ptr", hdc)
            w := NumGet(sz, 0, "Int")
        }
        return w
    }

    ; Real px of a control's window -> 100 % units (rounded up).
    static Units(g, px) => (Theme.IsScaled(g) && Theme.Scale != 100) ? Ceil(px * 100 / Theme.Scale) : px

    ; Height of one line of the control's text in its font, real px.
    static TextH(ctrl) {
        h := 0
        try {
            hdc := DllCall("GetDC", "Ptr", ctrl.Hwnd, "Ptr")
            old := DllCall("SelectObject", "Ptr", hdc, "Ptr", SendMessage(0x31, 0, 0, ctrl.Hwnd), "Ptr")   ; WM_GETFONT
            sz := Buffer(8, 0)
            DllCall("GetTextExtentPoint32W", "Ptr", hdc, "Str", "Ag", "Int", 2, "Ptr", sz)
            DllCall("SelectObject", "Ptr", hdc, "Ptr", old)
            DllCall("ReleaseDC", "Ptr", ctrl.Hwnd, "Ptr", hdc)
            h := NumGet(sz, 4, "Int")
        }
        return h
    }

    ; The smallest point size a long translation may shrink a text to
    ; (polish rule 2026-11-19): 9 pt for labels, 8 pt for buttons; a role
    ; that is already small (caps, small: 8 pt) does not shrink at all. A
    ; text that still does not fit needs a shorter translation (the fit
    ; tests check every language).
    static MinPt(role) {
        f := Theme.Fonts.Has(role) ? Theme.Fonts[role] : Theme.Fonts["body"]
        base := RegExMatch(f[1], "(?<=^|\s)s(\d+)", &m) ? Integer(m[1]) : 10
        return Min(base, role = "button" ? 8 : 9)
    }

    ; Point size (at 100 %) of each text FitFont shrank, by hwnd; the fit
    ; tests read it.
    static _fit := Map()
    static FitPt(ctrl) => Theme._fit.Has(ctrl.Hwnd) ? Theme._fit[ctrl.Hwnd] : 0

    ; A text too wide for maxW real px (a long translation): the control's
    ; font a point smaller each step, down to Theme.MinPt(role), until it
    ; fits. The colour and family stay. A top-aligned label (no
    ; SS_CENTERIMAGE) moves down by half the height it lost, so its text
    ; keeps the middle of the row (it sat higher than its neighbours).
    ; -> the point size used (at 100 %).
    static FitFont(ctrl, role, maxW) {
        f := Theme.Fonts.Has(role) ? Theme.Fonts[role] : Theme.Fonts["body"]
        pt := RegExMatch(f[1], "(?<=^|\s)s(\d+)", &m) ? Integer(m[1]) : 10
        base := pt, minPt := Theme.MinPt(role)
        try {
            k := Theme.IsScaled(ctrl.Gui)
            h0 := Theme.TextH(ctrl)
            while (pt > minPt && Theme.TextW(ctrl) > maxW) {
                pt--
                ctrl.SetFont("s" (k ? Max(6, Theme.S(pt)) : pt), f[2])
            }
            if (pt < base) {
                Theme._fit[ctrl.Hwnd] := pt
                if !(ControlGetStyle(ctrl.Hwnd) & 0x200) {
                    d := (h0 - Theme.TextH(ctrl)) // 2
                    if (d > 0) {
                        ctrl.GetPos(&cx, &cy)
                        ctrl.Move(cx, cy + d)
                    }
                }
            } else if Theme._fit.Has(ctrl.Hwnd)
                Theme._fit.Delete(ctrl.Hwnd)
        }
        return pt
    }

    ; Change text; transparent labels get their background repainted.
    static SetText(ctrl, text) {
        text := String(text)
        if (ctrl.Text == text)
            return
        ctrl.Text := text
        if Theme._btn.Has(ctrl.Hwnd)
            Theme.FitButton(ctrl)
        if Theme._trans.Has(ctrl.Hwnd)
            Theme.RepaintCtrl(ctrl)
    }

    static SetColors(ctrl, bg, fg) {
        ctrl.Opt("+Background" bg)
        ctrl.SetFont("c" fg)
        ctrl.Redraw()
    }

    static Repaint(g) {
        DllCall("RedrawWindow", "Ptr", g.Hwnd, "Ptr", 0, "Ptr", 0, "UInt", 0x0185)
    }

    static RepaintCtrl(ctrl) {
        rc := Buffer(16, 0)
        DllCall("GetWindowRect", "Ptr", ctrl.Hwnd, "Ptr", rc)
        parent := DllCall("GetParent", "Ptr", ctrl.Hwnd, "Ptr")
        DllCall("MapWindowPoints", "Ptr", 0, "Ptr", parent, "Ptr", rc, "UInt", 2)
        DllCall("RedrawWindow", "Ptr", parent, "Ptr", rc, "Ptr", 0, "UInt", 0x0185)
    }

    ; ---- clickable Text controls (buttons, nav, checks) ----------------------

    static Clickable(ctrl, clickFn, hoverFn := "") {
        Theme._Hook()
        Theme._hot[ctrl.Hwnd] := {gui: ctrl.Gui.Hwnd, click: clickFn, hover: hoverFn, enabled: true}
        ctrl.OnEvent("Click", Theme._OnClick.Bind(Theme))
        ctrl.OnEvent("DoubleClick", Theme._OnClick.Bind(Theme))
    }

    static _OnClick(ctrl, *) {
        if !Theme._hot.Has(ctrl.Hwnd)
            return
        e := Theme._hot[ctrl.Hwnd]
        if (e.enabled && IsObject(e.click))
            e.click.Call(ctrl)
    }

    ; An Edit's frame to colour `col` (focus gold, else the frame colour).
    ; Never throws: focus moves while a window is destroyed, after Forget
    ; has dropped the frame (an error there would be a dialog).
    static _FrameColor(e, col) {
        try {
            if Theme._frames.Has(e.Hwnd)
                Theme.SetColors(Theme._frames[e.Hwnd], col, Theme.Text)
        }
    }

    static Forget(g) {
        dead := []
        for hwnd, e in Theme._hot {
            if (e.gui = g.Hwnd)
                dead.Push(hwnd)
        }
        for hwnd in dead
            Theme._hot.Delete(hwnd)
        try Theme._scaled.Delete(g.Hwnd)
        try {
            for c in g {
                for m in [Theme._src, Theme._help, Theme._act, Theme._btn, Theme._roles, Theme._trans, Theme._panels, Theme._frames, Theme._fit] {
                    if m.Has(c.Hwnd)
                        m.Delete(c.Hwnd)
                }
            }
        }
        if !Theme._hot.Has(Theme._hoverHwnd)
            Theme._hoverHwnd := 0
    }

    static _Hook() {
        if Theme._hooked
            return
        Theme._hooked := true
        OnMessage(0x0200, ObjBindMethod(Theme, "_OnMove"))     ; WM_MOUSEMOVE
        OnMessage(0x02A3, ObjBindMethod(Theme, "_OnLeave"))    ; WM_MOUSELEAVE
    }

    static _OnMove(wParam, lParam, msg, hwnd) {
        if (hwnd = Theme._hoverHwnd)
            return
        Theme._Unhover()
        if !Theme._hot.Has(hwnd)
            return
        e := Theme._hot[hwnd]
        if !e.enabled
            return
        Theme._hoverHwnd := hwnd
        if IsObject(e.hover)
            e.hover.Call(true)
        tme := Buffer(8 + 2 * A_PtrSize, 0)            ; TRACKMOUSEEVENT
        NumPut("UInt", tme.Size, tme, 0)
        NumPut("UInt", 0x2, tme, 4)                     ; TME_LEAVE
        NumPut("Ptr", hwnd, tme, 8)
        DllCall("TrackMouseEvent", "Ptr", tme)
    }

    static _OnLeave(wParam, lParam, msg, hwnd) {
        if (hwnd = Theme._hoverHwnd)
            Theme._Unhover()
    }

    static _Unhover() {
        h := Theme._hoverHwnd
        Theme._hoverHwnd := 0
        if (h && Theme._hot.Has(h) && IsObject(Theme._hot[h].hover))
            Theme._hot[h].hover.Call(false)
    }

    ; kind: "normal" (navy) | "primary" (gold) | "quiet" (flat on bg)
    static Button(g, opts, label, clickFn, kind := "normal") {
        Theme.Font(g, "button")
        c := Theme.Add(g, "Text", opts " +0x100 +0x200 Center", I18n.T(label))
        Theme._src[c.Hwnd] := String(label)
        Theme._act[c.Hwnd] := true
        Theme._btn[c.Hwnd] := 0
        Theme.FitButton(c)
        Theme._PaintButton(c, kind, false, true)
        Theme.Clickable(c, clickFn, (on) => Theme._PaintButton(c, kind, on, Theme._hot[c.Hwnd].enabled))
        return c
    }

    ; A button's text keeps BtnPad px clear on each side: a text too wide
    ; for that (a long translation: fr "Exporter les paramètres") gets the
    ; button font a point smaller each step, down to 8 pt (Theme.FitFont);
    ; a shorter text later (SetText) goes back to the full size.
    static BtnPad := 6
    static IsButton(ctrl) => Theme._btn.Has(ctrl.Hwnd)
    static FitButton(c) {
        try {
            c.GetPos(, , &w)
            k := Theme.IsScaled(c.Gui)
            room := w - 2 * (k ? Theme.S(Theme.BtnPad) : Theme.BtnPad)
            f := Theme.Fonts["button"]
            if Theme._btn[c.Hwnd] {                       ; shrunk before: back to the full size
                c.SetFont(Theme.FontOpt("button", k), f[2])
                Theme._btn[c.Hwnd] := 0
                try Theme._fit.Delete(c.Hwnd)
            }
            if (Theme.TextW(c) > room)
                Theme._btn[c.Hwnd] := Theme.FitFont(c, "button", room)
        }
    }

    static SetEnabled(ctrl, enabled, kind := "normal") {
        if !Theme._hot.Has(ctrl.Hwnd)
            return
        Theme._hot[ctrl.Hwnd].enabled := enabled ? true : false
        Theme._PaintButton(ctrl, kind, false, enabled)
    }

    static _PaintButton(c, kind, hot, enabled) {
        if !enabled
            return Theme.SetColors(c, Theme.OffBg, Theme.Muted)
        switch kind {
            case "primary": Theme.SetColors(c, hot ? Theme.AccentHi : Theme.Accent, Theme.Ink)
            case "quiet": Theme.SetColors(c, hot ? Theme.HoverBg : Theme.Bg, hot ? Theme.Text : Theme.Muted)
            default: Theme.SetColors(c, hot ? Theme.HoverBg : Theme.PanelC, Theme.Text)
        }
    }

    ; style "box" (16x16 checkbox + optional label) or "pill" (ON/OFF switch).
    ; labelW: label width (0 = 240, -1 = as wide as the text).
    static Check(g, x, y, label := "", value := 0, onChange := "", style := "box", labelW := 0) {
        if (style = "pill") {
            Theme.Font(g, "caps")
            box := Theme.Add(g, "Text", "x" x " y" y " w44 h20 +0x100 +0x200 Center", "")
            lx := x + 54
        } else {
            Theme.Font(g, "glyph")
            box := Theme.Add(g, "Text", "x" x " y" y + 2 " w16 h16 +0x100 +0x200 Center", "")
            lx := x + 24
        }
        lbl := ""
        if (label != "") {
            w := (labelW < 0) ? "" : " w" (labelW ? labelW : 240)
            Theme.Font(g, "body")
            lbl := Theme.Add(g, "Text", "x" lx " y" y w " h20 +0x100 +0x200 BackgroundTrans", I18n.T(label))
            Theme._trans[lbl.Hwnd] := true
            Theme._src[lbl.Hwnd] := String(label)
            Theme._act[lbl.Hwnd] := true
        }
        return ThemeCheck(box, lbl, value, onChange, style)
    }

    ; ---- inputs ----------------------------------------------------------------

    ; Padded flat edit: navy frame + field fill + borderless Edit inside.
    ; extra: e.g. "Password", "Number", "Multi ReadOnly VScroll".
    static Edit(g, x, y, w, h := 28, text := "", extra := "") {
        frame := Theme.Rect(g, x, y, w, h, Theme.FrameC)
        Theme.Inset(frame, Theme.Rect(g, x + 1, y + 1, w - 2, h - 2, Theme.FieldBg))
        Theme.Font(g, "body")
        multi := InStr(extra, "Multi")
        ey := multi ? y + 6 : y + (h - 20) // 2
        eh := multi ? h - 12 : 20
        ro := InStr(extra, "ReadOnly")
        e := Theme.Add(g, "Edit", "x" x + 8 " y" ey " w" w - 14 " h" eh " -E0x200 Background" Theme.FieldBg (ro ? " -TabStop " : " ") extra, text)
        if multi
            Theme.DarkTheme(e.Hwnd)
        if ro
            return e
        Theme._frames[e.Hwnd] := frame
        e.OnEvent("Focus", (c, *) => Theme._FrameColor(c, Theme.Accent))
        e.OnEvent("LoseFocus", (c, *) => Theme._FrameColor(c, Theme.FrameC))
        return e
    }

    static Dropdown(g, x, y, w, items := "") {
        Theme.Font(g, "body")
        d := Theme.Add(g, "DropDownList", "x" x " y" y " w" w " Background" Theme.FieldBg, IsObject(items) ? items : [])
        Theme.DarkTheme(d.Hwnd, "DarkMode_CFD")
        return d
    }

    ; Header-less custom-drawn ListView with a 1px navy frame (and a field
    ; fill under it, seen while the list is hidden behind an EmptyHint).
    ; colorFn(row) -> "RRGGBB" text colour for that row, or "" for default.
    ; The last column fills the rest of the width (FitLastCol). A width may be
    ; "54 Center" (number + ModifyCol options) to centre that column.
    static ListView(g, x, y, w, h, cols, widths, extra := "", colorFn := "") {
        frame := Theme.Rect(g, x - 1, y - 1, w + 2, h + 2, Theme.FrameC)
        fill := Theme.Rect(g, x, y, w, h, Theme.FieldBg)
        Theme.Font(g, "body")
        lv := Theme.Add(g, "ListView", "x" x " y" y " w" w " h" h " -E0x200 -Hdr -Multi +LV0x10000 Background" Theme.FieldBg " c" Theme.Text " " extra, cols)
        Theme.Inset(frame, fill)                   ; the frame line stays 1 px at every UI size
        Theme.Inset(frame, lv)
        for i, wd in widths
            lv.ModifyCol(i, Theme._ColOpt(g, wd))
        Theme.FitLastCol(lv)
        Theme.DarkTheme(lv.Hwnd)
        lv.OnNotify(-12, ObjBindMethod(Theme, "_LvDraw", colorFn))
        return lv
    }

    ; Last column to the remaining width (LVM_SETCOLUMNWIDTH with
    ; LVSCW_AUTOSIZE_USEHEADER = -2, then checked against the client width:
    ; -2 can ignore a vertical scrollbar and leave a horizontal one). Call
    ; again after rows change: a scrollbar coming or going changes the room.
    static FitLastCol(lv) {
        n := lv.GetCount("Col")
        if !n
            return
        SendMessage(0x101E, n - 1, -2, lv)                  ; LVM_SETCOLUMNWIDTH
        rc := Buffer(16, 0)
        DllCall("GetClientRect", "Ptr", lv.Hwnd, "Ptr", rc)
        room := NumGet(rc, 8, "Int")
        Loop n - 1
            room -= SendMessage(0x101D, A_Index - 1, 0, lv)  ; LVM_GETCOLUMNWIDTH
        if (room > 0 && SendMessage(0x101D, n - 1, 0, lv) != room)
            SendMessage(0x101E, n - 1, room, lv)
    }

    ; Muted centred hint over an empty ListView's area (the caller hides the
    ; list and shows the hint while it has no rows).
    static EmptyHint(g, lv, text) {
        p := Theme.Pos(lv)
        return Theme.Label(g, "x" p.x + 8 " y" p.y + (p.h - 20) // 2 " w" p.w - 16 " h20 Center +0x200", text, "muted", Theme.FieldBg)
    }

    ; Column captions over a header-less ListView (a "54 Center" width centres
    ; its caption too).
    static ListHeader(g, x, y, widths, names) {
        for i, n in names {
            wd := Theme.ColW(widths[i])
            if InStr(widths[i], "Center")
                Theme.Label(g, "x" x " y" y " w" wd " h16 Center", StrUpper(n), "caps")
            else
                Theme.Label(g, "x" x + 4 " y" y " w" wd - 4 " h16", StrUpper(n), "caps")
            x += wd
        }
    }

    ; Pixel width of a ListView width entry (54 or "54 Center").
    static ColW(wd) => Integer(RegExReplace(String(wd), "^\s*(\d+).*$", "$1"))

    ; Segmented choice: adjacent w x h buttons, one per label, the picked one
    ; gold with ink text, the others navy. -> Map label -> ThemeOption (.Value
    ; 0/1, .Flip() picks it). onPick(label) runs after a pick.
    static Segmented(g, x, y, labels, picked := 1, onPick := "", w := 70, h := 26) {
        opts := Map()
        Theme.Font(g, "button")
        for i, lb in labels {
            c := Theme.Add(g, "Text", "x" x + (i - 1) * w " y" y " w" w " h" h " +0x100 +0x200 Center", I18n.T(lb))
            opts[lb] := ThemeOption(c, lb, opts, onPick, i = picked)
        }
        return opts
    }

    static _LvDraw(colorFn, lv, lParam) {
        nm := 3 * A_PtrSize
        stage := NumGet(lParam, nm, "UInt")
        if (stage = 0x1)                                ; CDDS_PREPAINT
            return 0x20                                 ; CDRF_NOTIFYITEMDRAW
        if (stage != 0x10001)                           ; CDDS_ITEMPREPAINT
            return 0
        offSpec := nm + 2 * A_PtrSize + 16
        offState := offSpec + A_PtrSize
        offClr := offState + 2 * A_PtrSize
        item := NumGet(lParam, offSpec, "UPtr")
        fg := Theme.Text, bg := Theme.FieldBg
        if IsObject(colorFn) {
            c := colorFn.Call(item + 1)
            if (c != "")
                fg := c
        }
        if SendMessage(0x102C, item, 0x2, lv.Hwnd)     ; LVM_GETITEMSTATE, LVIS_SELECTED
            bg := Theme.HoverBg
        ; drop selected/focus/hot so the control does not paint system colours
        NumPut("UInt", NumGet(lParam, offState, "UInt") & ~0x51, lParam, offState)
        NumPut("UInt", Theme.BGR(fg), lParam, offClr)
        NumPut("UInt", Theme.BGR(bg), lParam, offClr + 4)
        return 0x2                                      ; CDRF_NEWFONT
    }

    static TreeView(g, x, y, w, h, extra := "") {
        Theme.Rect(g, x - 1, y - 1, w + 2, h + 2, Theme.FrameC)
        Theme.Font(g, "body")
        tv := Theme.Add(g, "TreeView", "x" x " y" y " w" w " h" h " -E0x200 Background" Theme.FieldBg " c" Theme.Text " " extra)
        Theme.DarkTheme(tv.Hwnd)
        return tv
    }

    ; ---- themed modal confirm ----------------------------------------------------

    ; Blocks (pumping messages) until answered. -> true only for okLabel.
    static Confirm(owner, title, body, okLabel := "OK", cancelLabel := "Cancel") {
        res := [false]
        title := I18n.T(title), body := I18n.T(body), okLabel := I18n.T(okLabel), cancelLabel := I18n.T(cancelLabel)
        d := Gui("-MinimizeBox -MaximizeBox" (IsObject(owner) ? " +Owner" owner.Hwnd : ""), Brand.Name)
        d.BackColor := Theme.Bg
        d.MarginX := 0, d.MarginY := 0
        Theme.DarkCaption(d.Hwnd)
        sink := Theme.Sink
        Theme.Sink := ""
        Theme.Moon(d, 20, 18, 32)
        Theme.Label(d, "x64 y20 w380", title, "head", Theme.Bg)
        b := Theme.Label(d, "x64 y50 w380", body, "body", Theme.Bg)
        b.GetPos(, &by, , &bh)
        y := by + bh + 22
        close := (ok) => (res[1] := ok, d.Destroy())
        Theme.Button(d, "x" 444 - 130 - 8 - 130 " y" y " w130 h32", cancelLabel, (*) => close(false))
        Theme.Button(d, "x" 444 - 130 " y" y " w130 h32", okLabel, (*) => close(true), "primary")
        Theme.Rect(d, 0, y + 32 + 20, 464, 1, Theme.Bg)
        Theme.Sink := sink
        d.OnEvent("Close", (*) => close(false))
        d.OnEvent("Escape", (*) => close(false))
        hwnd := d.Hwnd
        ownerVisible := IsObject(owner) && DllCall("IsWindowVisible", "Ptr", owner.Hwnd)
        if ownerVisible
            owner.Opt("+Disabled")
        d.Show("AutoSize Hide")
        d.GetPos(, , &dw, &dh)
        if ownerVisible {
            owner.GetPos(&ox, &oy, &ow, &oh)
            d.Show("x" ox + (ow - dw) // 2 " y" oy + (oh - dh) // 2)
        } else
            d.Show("Center")
        WinWaitClose("ahk_id " hwnd)
        Theme.Forget({Hwnd: hwnd})
        if ownerVisible {
            owner.Opt("-Disabled")
            try WinActivate("ahk_id " owner.Hwnd)
        }
        return res[1]
    }
}

; One button of a Theme.Segmented choice. .Value is 0/1; Flip() picks it
; (the others turn off) and calls onPick(label).
class ThemeOption {
    __New(ctrl, label, group, onPick, on) {
        this._c := ctrl
        this._label := label
        this._group := group
        this._fn := onPick
        this._val := on ? 1 : 0
        this._Paint(false)
        Theme.Clickable(ctrl, (*) => this.Flip(), (hot) => this._Paint(hot))
    }

    Value {
        get => this._val
        set {
            this._val := value ? 1 : 0
            this._Paint(false)
        }
    }

    Hwnd => this._c.Hwnd

    Flip() {
        for lb, o in this._group
            o.Value := (o == this)
        if IsObject(this._fn)
            this._fn.Call(this._label)
    }

    _Paint(hot) {
        if this._val
            Theme.SetColors(this._c, hot ? Theme.AccentHi : Theme.Accent, Theme.Ink)
        else
            Theme.SetColors(this._c, hot ? Theme.HoverBg : Theme.PanelC, Theme.Text)
    }
}

; Checkbox / ON-OFF pill built from Text controls. .Value is 0/1.
class ThemeCheck {
    __New(box, lbl, value, onChange, style) {
        this._box := box
        this._lbl := lbl
        this._fn := onChange
        this._style := style
        this._val := value ? 1 : 0
        this._Paint(false)
        Theme.Clickable(box, (*) => this.Flip(), (on) => this._Paint(on))
        if IsObject(lbl)
            Theme.Clickable(lbl, (*) => this.Flip())
    }

    Value {
        get => this._val
        set {
            this._val := value ? 1 : 0
            this._Paint(false)
        }
    }

    Hwnd => this._box.Hwnd

    Flip() {
        this.Value := !this._val
        if IsObject(this._fn)
            this._fn.Call(this)
    }

    _Paint(hot) {
        on := this._val
        if (this._style = "pill") {
            this._box.Text := on ? "ON" : "OFF"
            Theme.SetColors(this._box, on ? (hot ? Theme.AccentHi : Theme.Accent) : (hot ? Theme.HoverBg : Theme.OffBg)
                , on ? Theme.Ink : Theme.Muted)
        } else {
            this._box.Text := on ? Chr(0x2713) : ""
            Theme.SetColors(this._box, on ? (hot ? Theme.AccentHi : Theme.Accent) : (hot ? Theme.HoverBg : Theme.OffBg), Theme.Ink)
        }
    }
}

; Use and Apply read saved themes through ThemeStore (it includes this file first).
#Include %A_LineFile%\..\ThemeStore.ahk
