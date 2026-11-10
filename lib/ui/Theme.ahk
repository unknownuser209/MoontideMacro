#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\..\Brand.ahk
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

    static Sink := ""
    static _hot := Map()           ; hwnd -> {gui, click, hover, enabled}
    static _frames := Map()        ; edit hwnd -> frame Text ctrl
    static _trans := Map()         ; hwnd of BackgroundTrans labels
    static _roles := Map()         ; label hwnd -> font role ("muted", ...)
    static _help := Map()          ; "?" hwnd -> its help text
    static _panels := Map()        ; panel frame / fill hwnd -> true
    static HelpTip := 20           ; ToolTip number used by Help
    static _hoverHwnd := 0
    static _hooked := false

    ; ---- basics -------------------------------------------------------------

    static AssetPath(name) {
        return RegExReplace(A_LineFile, "\\lib\\ui\\[^\\]+$", "") "\assets\" name
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

    static Font(g, role := "body", color := "") {
        f := Theme.Fonts.Has(role) ? Theme.Fonts[role] : Theme.Fonts["body"]
        c := (color != "") ? color : Theme.%f[3]%
        g.SetFont(f[1] " c" c, f[2])
    }

    static Add(g, type, opts := "", text := "") {
        if (type = "Text")
            opts .= " +0x80"                ; SS_NOPREFIX: show "&" literally
        c := g.Add(type, opts, text)
        if (Theme.Sink is Array)
            Theme.Sink.Push(c)
        return c
    }

    ; Window with the palette, dark title bar (Win10 1809+/Win11 caption colours).
    static Window(title, opts := "") {
        g := Gui(opts, title)
        g.BackColor := Theme.Bg
        g.MarginX := 0, g.MarginY := 0
        Theme.Font(g, "body")
        Theme.DarkCaption(g.Hwnd)
        return g
    }

    static DarkCaption(hwnd) {
        try {
            v := Buffer(4, 0)
            NumPut("Int", 1, v)
            DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", hwnd, "UInt", 20, "Ptr", v, "UInt", 4)
            for attr, col in Map(34, Theme.PanelC, 35, Theme.Bg, 36, Theme.Text) {
                NumPut("UInt", Theme.BGR(col), v)
                DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", hwnd, "UInt", attr, "Ptr", v, "UInt", 4)
            }
        }
    }

    static DarkTheme(hwnd, cls := "DarkMode_Explorer") {
        try DllCall("uxtheme\SetWindowTheme", "Ptr", hwnd, "Str", cls, "Ptr", 0)
    }

    ; ---- static shapes / labels ----------------------------------------------

    static Rect(g, x, y, w, h, color) {
        return Theme.Add(g, "Text", "x" x " y" y " w" w " h" h " Background" color)
    }

    ; bg = "" -> transparent over whatever is behind (e.g. the art).
    static Label(g, opts, text, role := "body", bg := "", color := "") {
        Theme.Font(g, role, color)
        c := Theme.Add(g, "Text", opts (bg = "" ? " BackgroundTrans" : " Background" bg), text)
        if (bg = "")
            Theme._trans[c.Hwnd] := true
        Theme._roles[c.Hwnd] := role
        return c
    }

    ; Font role a Label was made with ("" for other controls).
    static RoleOf(ctrl) => Theme._roles.Has(ctrl.Hwnd) ? Theme._roles[ctrl.Hwnd] : ""

    ; Solid card: 1 px FrameC border, CardBg fill, optional title in small
    ; gold capitals at x+12, y+8. -> Array of its ctrls (frame first).
    static Panel(g, x, y, w, h, title := "") {
        parts := [Theme.Rect(g, x, y, w, h, Theme.FrameC), Theme.Rect(g, x + 1, y + 1, w - 2, h - 2, Theme.CardBg)]
        for c in parts
            Theme._panels[c.Hwnd] := true
        if (title != "")
            parts.Push(Theme.Label(g, "x" x + 12 " y" y + 8 " w" w - 52 " h16", StrUpper(title), "caps", Theme.CardBg, Theme.Accent))
        return parts
    }

    static IsPanel(ctrl) => Theme._panels.Has(ctrl.Hwnd)

    ; 16x16 "?" in Muted; hovering (or clicking) shows `text` as a ToolTip
    ; by the mouse, leaving hides it.
    static Help(g, x, y, text) {
        Theme.Font(g, "caps")
        c := Theme.Add(g, "Text", "x" x " y" y " w16 h16 +0x100 +0x200 Center Background" Theme.OffBg " c" Theme.Muted, "?")
        Theme._help[c.Hwnd] := text
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

    ; Change text; transparent labels get their background repainted.
    static SetText(ctrl, text) {
        text := String(text)
        if (ctrl.Text == text)
            return
        ctrl.Text := text
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

    static Forget(g) {
        dead := []
        for hwnd, e in Theme._hot {
            if (e.gui = g.Hwnd)
                dead.Push(hwnd)
        }
        for hwnd in dead
            Theme._hot.Delete(hwnd)
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
        c := Theme.Add(g, "Text", opts " +0x100 +0x200 Center", label)
        Theme._PaintButton(c, kind, false, true)
        Theme.Clickable(c, clickFn, (on) => Theme._PaintButton(c, kind, on, Theme._hot[c.Hwnd].enabled))
        return c
    }

    static SetEnabled(ctrl, enabled, kind := "normal") {
        if !Theme._hot.Has(ctrl.Hwnd)
            return
        Theme._hot[ctrl.Hwnd].enabled := enabled ? true : false
        Theme._PaintButton(ctrl, kind, false, enabled)
    }

    static _PaintButton(c, kind, hot, enabled) {
        if !enabled
            return Theme.SetColors(c, Theme.OffBg, "5E6B80")
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
            lbl := Theme.Add(g, "Text", "x" lx " y" y w " h20 +0x100 +0x200 BackgroundTrans", label)
            Theme._trans[lbl.Hwnd] := true
        }
        return ThemeCheck(box, lbl, value, onChange, style)
    }

    ; ---- inputs ----------------------------------------------------------------

    ; Padded flat edit: navy frame + field fill + borderless Edit inside.
    ; extra: e.g. "Password", "Number", "Multi ReadOnly VScroll".
    static Edit(g, x, y, w, h := 28, text := "", extra := "") {
        frame := Theme.Rect(g, x, y, w, h, Theme.FrameC)
        Theme.Rect(g, x + 1, y + 1, w - 2, h - 2, Theme.FieldBg)
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
        e.OnEvent("Focus", (c, *) => Theme.SetColors(Theme._frames[c.Hwnd], Theme.Accent, Theme.Text))
        e.OnEvent("LoseFocus", (c, *) => Theme.SetColors(Theme._frames[c.Hwnd], Theme.FrameC, Theme.Text))
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
        Theme.Rect(g, x - 1, y - 1, w + 2, h + 2, Theme.FrameC)
        Theme.Rect(g, x, y, w, h, Theme.FieldBg)
        Theme.Font(g, "body")
        lv := Theme.Add(g, "ListView", "x" x " y" y " w" w " h" h " -E0x200 -Hdr -Multi +LV0x10000 Background" Theme.FieldBg " c" Theme.Text " " extra, cols)
        for i, wd in widths
            lv.ModifyCol(i, wd)
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
        lv.GetPos(&x, &y, &w, &h)
        return Theme.Label(g, "x" x + 8 " y" y + (h - 20) // 2 " w" w - 16 " h20 Center +0x200", text, "muted", Theme.FieldBg)
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
            c := Theme.Add(g, "Text", "x" x + (i - 1) * w " y" y " w" w " h" h " +0x100 +0x200 Center", lb)
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
