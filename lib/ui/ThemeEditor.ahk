#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\Theme.ahk
#Include %A_LineFile%\..\HelpTexts.ahk
; ---------------------------------------------------------------------------
; ThemeEditor: the "Custom theme" window (Settings > Look > Edit custom).
; Four base colours (Background, Panels, Text, Accent), each a hex field, a
; swatch and a Pick button (Windows' colour dialog, Theme.PickColor); "Start
; from" copies a preset's colours and picture; the background picture is
; none, a preset's picture or a file of your own. A preview shows the mixed
; colours (Theme.Derive) as they change.
;
;   ed := ThemeEditor(cfg, owner := "")   built hidden, from [UI] custom*
;   ed.ShowModal()      shows it over owner until closed -> true when saved
;   ed.SetHex(key, s)   key Bg / PanelC / Text / Accent; -> true when s is a
;                       colour (a bad one leaves the last good value)
;   ed.CopyFrom(name)   a preset's 4 colours and its picture
;   ed.SetPicture(choice, file := "")  "none", a preset name or "file"
;   ed.Save()           writes [UI] custom* and saves settings.ini -> true
;   ed.Close()          destroys the window
; Never throws on bad input: a field that is not 6 hex digits is ignored
; (the note says so) and its last good colour is saved.
; ---------------------------------------------------------------------------

class ThemeEditor {
    static Labels := Map("Bg", "Background", "PanelC", "Panels", "Text", "Text", "Accent", "Accent")
    static W := 560

    __New(cfg, owner := "") {
        this.cfg := cfg
        this.owner := owner
        this.saved := false
        this._vals := Map()
        this._edits := Map()
        this._swatches := Map()
        for k in Theme.BaseKeys                  ; cfg values, bad ones -> Moontide's
            this._vals[k] := Theme.HexOr(cfg.Get(Theme.CustomCfgKeys[k], ""), Theme.Presets["Moontide"].%k%)
        pic := Trim(String(cfg.Get("UI.customPicture", "Moontide")))
        this._pic := (pic = "none" || pic = "file") ? StrLower(pic) : Theme.ThemeName(pic)
        if (this._pic = Theme.CustomName)
            this._pic := "Moontide"
        this._file := Trim(String(cfg.Get("UI.customPictureFile", "")))
        ; file picker hook (tests replace it): -> a path or ""
        this._pickFile := () => FileSelect(3, , I18n.T("Pick a background picture"), "Pictures (*.png; *.jpg; *.jpeg; *.bmp; *.gif)")
        this._pickColor := (hex) => Theme.PickColor(this._gui.Hwnd, hex)
        this._Build()
        this._Refresh()
    }

    _Build() {
        sink := Theme.Sink
        Theme.Sink := ""
        try {
            d := Gui("-MinimizeBox -MaximizeBox" (IsObject(this.owner) ? " +Owner" this.owner.Hwnd : ""), Brand.Name " " Chr(0xB7) " " I18n.T("Custom theme"))
            this._gui := d
            d.BackColor := Theme.Bg
            d.MarginX := 0, d.MarginY := 0
            Theme.DarkCaption(d.Hwnd)
            W := ThemeEditor.W
            ; the moon in the accent being picked (the dashboard header's
            ; moon takes the theme's Accent the same way), else the plain one
            this._moonHbm := 0, this._moonAccent := ""
            mf := Theme.AssetPath("ui\moon_0.png")
            this._moon := FileExist(mf) ? d.Add("Picture", "x20 y18 w32 h32 BackgroundTrans", mf) : Theme.Moon(d, 20, 18, 32)
            Theme.Label(d, "x64 y22 w400 h24", "Custom theme", "head", Theme.Bg)
            Theme.Help(d, W - 36, 26, HelpTexts.For("UI.customBg"))
            ; start from a preset
            Theme.Label(d, "x20 y64 w110 h20", "Start from", "body", Theme.Bg)
            this._from := Theme.Dropdown(d, 130, 60, 150)
            this._from.Add(Theme.Names)
            this._from.Choose(1)
            Theme.Button(d, "x290 y60 w130 h28", "Copy colours", (*) => this.CopyFrom(this._from.Text))
            ; the 4 base colours
            for i, k in Theme.BaseKeys {
                y := 104 + (i - 1) * 38
                Theme.Label(d, "x20 y" y + 4 " w110 h20", ThemeEditor.Labels[k], "body", Theme.Bg)
                Theme.Rect(d, 130, y, 28, 28, Theme.FrameC)
                this._swatches[k] := Theme.Rect(d, 131, y + 1, 26, 26, this._vals[k])
                e := Theme.Edit(d, 166, y, 96, 28, this._vals[k], "Limit7")
                e.OnEvent("Change", ObjBindMethod(this, "_OnEdit", k))
                this._edits[k] := e
                Theme.Button(d, "x270 y" y " w70 h28", "Pick", ObjBindMethod(this, "_Pick", k))
            }
            ; preview
            this._pv := Map()
            this._pv["bg"] := Theme.Rect(d, 360, 104, 180, 142, Theme.Bg)
            this._pv["frame"] := Theme.Rect(d, 372, 116, 156, 118, Theme.FrameC)
            this._pv["card"] := Theme.Rect(d, 373, 117, 154, 116, Theme.CardBg)
            Theme.Font(d, "caps")
            this._pv["title"] := d.Add("Text", "x384 y124 w132 h16 +0x80", I18n.T("PREVIEW"))
            Theme.Font(d, "body")
            this._pv["text"] := d.Add("Text", "x384 y144 w132 h20 +0x80", I18n.T("Text"))
            Theme.Font(d, "muted")
            this._pv["muted"] := d.Add("Text", "x384 y166 w132 h18 +0x80", I18n.T("Muted text"))
            Theme.Font(d, "button")
            this._pv["button"] := d.Add("Text", "x384 y194 w100 h26 +0x80 +0x200 Center", I18n.T("Button"))
            ; background picture
            Theme.Label(d, "x20 y266 w110 h20", "Picture", "body", Theme.Bg)
            this._picDdl := Theme.Dropdown(d, 130, 262, 210)
            this._picDdl.Add(this._PicItems())
            this._picDdl.OnEvent("Change", ObjBindMethod(this, "_OnPicPick"))
            Theme.Button(d, "x350 y262 w110 h28", "Browse...", (*) => this._Browse())
            Theme.Help(d, 470, 268, HelpTexts.For("UI.customPicture"))
            this._fileNote := Theme.Label(d, "x20 y300 w520 h20", "", "muted", Theme.Bg)
            this._note := Theme.Label(d, "x20 y326 w520 h38", "", "muted", Theme.Bg)
            Theme.Button(d, "x" W - 20 - 130 - 8 - 130 " y376 w130 h32", "Cancel", (*) => this.Close())
            Theme.Button(d, "x" W - 20 - 130 " y376 w130 h32", "Save", (*) => (this.Save() ? this.Close() : ""), "primary")
            Theme.Rect(d, 0, 428, W, 1, Theme.Bg)
            d.OnEvent("Close", (*) => this.Close())
            d.OnEvent("Escape", (*) => this.Close())
        } finally
            Theme.Sink := sink
    }

    ; "None", "<preset> picture" for each preset, "My own picture"
    _PicItems() {
        out := [I18n.T("None")]
        for n in Theme.Names
            out.Push(I18n.F("{1} picture", n))
        out.Push(I18n.T("My own picture"))
        return out
    }

    _PicIndex() {
        if (this._pic = "none")
            return 1
        if (this._pic = "file")
            return Theme.Names.Length + 2
        for i, n in Theme.Names
            if (n = this._pic)
                return i + 1
        return 2
    }

    ; the current values as Theme.Derive sees them
    Derived() => Theme.Derive(this._vals["Bg"], this._vals["PanelC"], this._vals["Text"], this._vals["Accent"], Theme.CustomPicture(this._pic, this._file))

    Value(k) => this._vals[k]
    Picture() => this._pic
    File() => this._file
    Hwnd => this._gui.Hwnd

    SetHex(k, s) {
        h := Theme.HexOk(s)
        if (h = "" || !this._vals.Has(k))
            return false
        this._vals[k] := h
        if (Theme.HexOk(this._edits[k].Value) != h)
            this._edits[k].Value := h
        this._Refresh()
        return true
    }

    CopyFrom(name) {
        n := Theme.ThemeName(name)
        if (n = Theme.CustomName)
            return false
        p := Theme.Presets[n]
        for k in Theme.BaseKeys {
            this._vals[k] := p.%k%
            this._edits[k].Value := p.%k%
        }
        this._pic := n
        this._Refresh()
        return true
    }

    ; "none", a preset name or "file" (file: the path; "" keeps the last one)
    SetPicture(choice, file := "") {
        c := Trim(String(choice))
        if (c = "file") {
            if (file != "")
                this._file := file
            this._pic := "file"
        } else if (c = "none")
            this._pic := "none"
        else {
            n := Theme.ThemeName(c)
            this._pic := (n = Theme.CustomName) ? "Moontide" : n
        }
        this._Refresh()
    }

    Save() {
        try {
            for k in Theme.BaseKeys
                this.cfg.Set(Theme.CustomCfgKeys[k], this._vals[k])
            this.cfg.Set("UI.customPicture", this._pic)
            this.cfg.Set("UI.customPictureFile", this._file)
            this.cfg.Save()
        } catch Any as e {
            Theme.SetText(this._note, I18n.T("Not saved:") " " e.Message)
            return false
        }
        this.saved := true
        return true
    }

    ShowModal() {
        d := this._gui
        hwnd := d.Hwnd
        owner := this.owner
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
        if ownerVisible {
            owner.Opt("-Disabled")
            try WinActivate("ahk_id " owner.Hwnd)
        }
        return this.saved
    }

    Close() {
        if !this.HasOwnProp("_gui") || !IsObject(this._gui)
            return
        g := this._gui
        this._gui := ""
        try Theme.Forget(g)
        try g.Destroy()
        if this._moonHbm
            try DllCall("DeleteObject", "Ptr", this._moonHbm)
        this._moonHbm := 0
    }

    ; the header moon tinted to the accent (once per accent change)
    _TintMoon(accent) {
        if (accent = this._moonAccent || !this.HasOwnProp("_moon"))
            return
        this._moonAccent := accent
        mf := Theme.AssetPath("ui\moon_0.png")
        if !FileExist(mf)
            return
        h := 0
        try h := Theme.MoonBitmap(mf, accent, Theme.Bg)
        if !h
            return
        try this._moon.Value := "HBITMAP:*" h
        catch {
            DllCall("DeleteObject", "Ptr", h)
            return
        }
        if this._moonHbm
            try DllCall("DeleteObject", "Ptr", this._moonHbm)
        this._moonHbm := h
    }

    ; ---- events -------------------------------------------------------------

    _OnEdit(k, ctrl, *) {
        if (Theme.HexOk(ctrl.Value) != "")
            this.SetHex(k, ctrl.Value)
        else
            this._Refresh()
    }

    _Pick(k, *) {
        h := this._pickColor.Call(this._vals[k])
        if (h != "")
            this.SetHex(k, h)
    }

    _OnPicPick(ctrl, *) {
        i := ctrl.Value
        if (i = 1)
            return this.SetPicture("none")
        if (i >= 2 && i <= Theme.Names.Length + 1)
            return this.SetPicture(Theme.Names[i - 1])
        ; "My own picture": the last file, or pick one now
        if (this._file != "" && Theme.CustomPicture("file", this._file) != "")
            return this.SetPicture("file")
        this._Browse()
    }

    ; pick a picture file; one that will not load is refused (the note says why)
    _Browse() {
        f := ""
        try f := this._pickFile.Call()
        f := Trim(String(f))
        if (f = "")
            return this._Refresh()
        hbm := Theme.DimPicture(f, 32, 24, this._vals["Bg"])
        if !hbm {
            this._Refresh()
            Theme.SetText(this._fileNote, I18n.T("That picture could not be read. Pick a PNG, JPG or BMP file."))
            return false
        }
        DllCall("DeleteObject", "Ptr", hbm)
        this.SetPicture("file", f)
        return true
    }

    ; swatches, preview, picture line and the readability note
    _Refresh() {
        if !IsObject(this._gui)
            return
        o := this.Derived()
        this._TintMoon(o.Accent)
        for k in Theme.BaseKeys
            Theme.SetColors(this._swatches[k], this._vals[k], this._vals[k])
        Theme.SetColors(this._pv["bg"], o.Bg, o.Bg)
        Theme.SetColors(this._pv["frame"], o.FrameC, o.FrameC)
        Theme.SetColors(this._pv["card"], o.CardBg, o.CardBg)
        Theme.SetColors(this._pv["title"], o.CardBg, o.Accent)
        Theme.SetColors(this._pv["text"], o.CardBg, o.Text)
        Theme.SetColors(this._pv["muted"], o.CardBg, o.Muted)
        Theme.SetColors(this._pv["button"], o.Accent, o.Ink)
        this._picDdl.Choose(this._PicIndex())
        if (this._pic = "file")
            line := (Theme.CustomPicture("file", this._file) != "") ? I18n.F("Your picture: {1}", RegExReplace(this._file, "^.*\\")) : I18n.T("Your picture is missing: no picture will show.")
        else if (this._pic = "none")
            line := I18n.T("No picture: the plain background colour.")
        else
            line := I18n.F("The {1} theme's picture.", this._pic)
        Theme.SetText(this._fileNote, line)
        bad := []
        for k in Theme.BaseKeys
            if (Theme.HexOk(this._edits[k].Value) = "")
                bad.Push(I18n.T(ThemeEditor.Labels[k]))
        if bad.Length {
            names := ""
            for i, b in bad
                names .= (i > 1 ? ", " : "") b
            note := I18n.F("{1}: type 6 hex digits like 0D1117. The last good colour is kept.", names)
        } else if o.TextFixed
            note := I18n.T(o.Text = "FFFFFF" ? "The text colour is too close to the panels, so the theme uses white text instead."
                : "The text colour is too close to the panels, so the theme uses black text instead.")
        else if (Theme.Lum(o.Bg) > 0.4)
            note := I18n.T("A light background: buttons and lists use Windows' light look, and the pictures are made for dark themes, so some parts may look off.")
        else
            note := I18n.T("Other shades (fields, borders, hover, muted text) are mixed from these four. Save picks Custom; then Apply now on Settings > Look shows it.")
        Theme.SetText(this._note, note)
    }
}
