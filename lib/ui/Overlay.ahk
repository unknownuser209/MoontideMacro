#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\Theme.ahk
#Include %A_LineFile%\..\UiLogic.ahk
; ---------------------------------------------------------------------------
; Overlay: small always-on-top status window (280x120, no caption).
;
; API (for Vesper.ahk / Task 14b)
;   o := Overlay(cfg, callbacks)    callbacks Map: "start" / "pause" / "stop"
;                                   (all optional). Stop is also the potion
;                                   kill switch (spec 4.6a).
;   o.Show()   shows without taking focus, at [Overlay] x/y from cfg, else
;              near the top-right corner of the primary screen.
;   o.Hide()
;   o.SetStatus(state, task, biome, rare, uptimeMs, loops)   same contract as
;              Dashboard.SetStatus; unchanged values are not redrawn. Rare
;              biomes are shown in gold.
;   o.Log(text)  accepted for API symmetry; the overlay shows no log.
;   o.PauseText()  current Pause button label ("Resume" while Paused).
;
; WS_EX_NOACTIVATE: clicks and drags never take focus from the game window.
;   o.Hwnd
;
; Drag anywhere except the buttons. The position is saved to [Overlay] x, y
; (cfg.Save) when a drag ends. No timers.
; ---------------------------------------------------------------------------

class Overlay {
    static W := 280
    static H := 120

    __New(cfg, callbacks := "") {
        this.cfg := cfg
        this._cb := (callbacks is Map) ? callbacks : Map()
        this._key := ""
        this._shown := false
        this._Build()
        this.SetStatus("Stopped", "", "", false, 0, 0)
    }

    Hwnd => this._gui.Hwnd

    PauseText() => this._pauseBtn.Text

    _Build() {
        ; WS_EX_NOACTIVATE: clicking the overlay never takes focus from Roblox
        g := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x08000000", Brand.Name " Overlay")
        this._gui := g
        g.BackColor := Theme.Bg
        g.MarginX := 0, g.MarginY := 0
        sink := Theme.Sink
        Theme.Sink := ""
        Theme.Rect(g, 0, 0, Overlay.W, 2, Theme.Accent)
        Theme.Moon(g, 10, 9, 20)
        Theme.Label(g, "x36 y9 w140 h20 +0x200", Brand.Name, "button", Theme.Bg)
        Theme.Font(g, "caps")
        this._pill := g.Add("Text", "x178 y9 w92 h20 +0x80 +0x200 Center Background" Theme.OffBg, "")
        Theme.Label(g, "x12 y36 w44 h18", "TASK", "caps", Theme.Bg)
        this._task := Theme.Label(g, "x58 y35 w212 h18", "", "body", Theme.Bg)
        Theme.Label(g, "x12 y54 w44 h18", "BIOME", "caps", Theme.Bg)
        this._biome := Theme.Label(g, "x58 y53 w212 h18", "", "body", Theme.Bg)
        Theme.Label(g, "x12 y72 w44 h18", "UP", "caps", Theme.Bg)
        this._up := Theme.Label(g, "x58 y71 w90 h18", "", "body", Theme.Bg)
        Theme.Label(g, "x150 y72 w44 h18", "LOOPS", "caps", Theme.Bg)
        this._loops := Theme.Label(g, "x196 y71 w74 h18", "", "body", Theme.Bg)
        Theme.Button(g, "x10 y92 w82 h22", "Start", (*) => this._Fire("start"), "primary")
        this._pauseBtn := Theme.Button(g, "x99 y92 w82 h22", "Pause", (*) => this._Fire("pause"))
        Theme.Button(g, "x188 y92 w82 h22", "Stop", (*) => this._Fire("stop"))
        Theme.Sink := sink
        try {
            v := Buffer(4, 0)
            NumPut("Int", 2, v)    ; DWMWCP_ROUND
            DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", g.Hwnd, "UInt", 33, "Ptr", v, "UInt", 4)
            NumPut("UInt", Theme.BGR(Theme.PanelC), v)
            DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", g.Hwnd, "UInt", 34, "Ptr", v, "UInt", 4)
        }
        ; WDA_EXCLUDEFROMCAPTURE (Windows 10 2004+): you see it, screen grabs
        ; do not. Dragged over the quest panel (2253,497 at 2560x1440, live
        ; 2026-11-11) the board read 'Moontide Macro'; it also sat on the
        ; merchant's item list. Older Windows: no effect, same as before.
        try DllCall("SetWindowDisplayAffinity", "Ptr", g.Hwnd, "UInt", 0x11)
        OnMessage(0x0201, ObjBindMethod(this, "_OnLButton"))      ; WM_LBUTTONDOWN
        OnMessage(0x0232, ObjBindMethod(this, "_OnMoved"))        ; WM_EXITSIZEMOVE
    }

    Show() {
        if this._shown {
            this._gui.Show("NoActivate")
            return
        }
        x := this.cfg.Get("Overlay.x", -99999)
        y := this.cfg.Get("Overlay.y", -99999)
        ; on a real screen, not only inside the box around all of them (a
        ; second screen of another size, or one switched off, leaves parts of
        ; that box nobody sees: a player never saw it, 2026-11-26)
        if !(IsNumber(x) && IsNumber(y) && Overlay.OnScreen(x, y, Theme.Dpi(Overlay.W), Theme.Dpi(Overlay.H), Overlay.Monitors())) {
            p := Overlay.DefaultPos(A_ScreenWidth)
            x := p.x, y := p.y
        }
        this._gui.Show("x" x " y" y " w" Overlay.W " h" Overlay.H " NoActivate")
        this._shown := true
    }

    ; Tray "Show the small window": back at the top right of the main screen,
    ; shown and saved there (a lost window: off screen, hidden by Win+D).
    ResetPos() {
        p := Overlay.DefaultPos(A_ScreenWidth)
        this._gui.Show("x" p.x " y" p.y " w" Overlay.W " h" Overlay.H " NoActivate")
        this._shown := true
        WinSetAlwaysOnTop(1, "ahk_id " this._gui.Hwnd)
        this.cfg.Set("Overlay.x", p.x)
        this.cfg.Set("Overlay.y", p.y)
        try this.cfg.Save()
    }

    ; For the log at launch: "x,y WxH on screen N" or why it cannot be seen.
    Where() {
        try {
            WinGetPos(&x, &y, &w, &h, "ahk_id " this._gui.Hwnd)
            vis := DllCall("IsWindowVisible", "Ptr", this._gui.Hwnd) ? "" : ", NOT visible"
            n := Overlay.MonitorAt(x + w // 2, y + h // 2, Overlay.Monitors())
            return x "," y " " w "x" h (n ? " on screen " n : ", off every screen") vis
        }
        return "unknown"
    }

    ; The work areas of the screens: Array of {l, t, r, b} (screen px).
    static Monitors() {
        out := []
        try {
            Loop MonitorGetCount() {
                MonitorGetWorkArea(A_Index, &l, &t, &r, &b)
                out.Push({l: l, t: t, r: r, b: b})
            }
        }
        return out
    }

    ; Pure: the screen (1-based) whose work area holds the point, or 0.
    static MonitorAt(px, py, mons) {
        for i, m in mons
            if (px >= m.l && px < m.r && py >= m.t && py < m.b)
                return i
        return 0
    }

    ; Pure: a w x h window at x, y can be seen: its centre and its top band
    ; (where it is dragged) lie on a screen's work area. No screens known
    ; (the call failed): true, as before.
    static OnScreen(x, y, w, h, mons) {
        if !(mons is Array && mons.Length)
            return true
        return Overlay.MonitorAt(x + w // 2, y + h // 2, mons) > 0
            && Overlay.MonitorAt(x + w // 2, y + 10, mons) > 0
    }

    ; top right of a screen screenW px wide, its width in screen px at the
    ; Windows scale (Theme.Dpi: at 125% the old spot ran 70 px off the edge)
    static DefaultPos(screenW) => {x: screenW - Theme.Dpi(Overlay.W + 24), y: Theme.Dpi(24)}

    Hide() {
        this._gui.Hide()
    }

    ; Windowed Roblox (2026-11-14): when the overlay covers the client rect
    ; (screen px), it moves just right of it, else left, else above, else
    ; below; it stays where it is when there is no room (the position is not
    ; saved: it is the run's, not the player's).
    AvoidRect(rx, ry, rw, rh) {
        if !this._shown
            return
        WinGetPos(&x, &y, &w, &h, "ahk_id " this._gui.Hwnd)
        ; within the screen Roblox is on (the box around all screens could
        ; put it on one switched off, or between two of different sizes)
        mons := Overlay.Monitors()
        n := Overlay.MonitorAt(rx + rw // 2, ry + rh // 2, mons)
        if n {
            m := mons[n]
            p := Overlay.Avoid(x, y, w, h, rx, ry, rw, rh, m.l, m.t, m.r - m.l, m.b - m.t)
        } else
            p := Overlay.Avoid(x, y, w, h, rx, ry, rw, rh, SysGet(76), SysGet(77), SysGet(78), SysGet(79))
        if (p.x != x || p.y != y)
            this._gui.Move(p.x, p.y)
    }

    ; Pure: where a w x h box at x, y goes so it does not cover the r rect,
    ; inside the virtual screen v -> {x, y} (unchanged when it does not
    ; overlap or nothing fits). v = the work area of Roblox's screen.
    static Avoid(x, y, w, h, rx, ry, rw, rh, vx, vy, vw, vh) {
        if (x >= rx + rw || x + w <= rx || y >= ry + rh || y + h <= ry)
            return {x: x, y: y}
        g := 8
        ty := Min(Max(y, vy), vy + vh - h)
        if (rx + rw + g + w <= vx + vw)
            return {x: rx + rw + g, y: ty}
        if (rx - g - w >= vx)
            return {x: rx - g - w, y: ty}
        tx := Min(Max(x, vx), vx + vw - w)
        if (ry - g - h >= vy)
            return {x: tx, y: ry - g - h}
        if (ry + rh + g + h <= vy + vh)
            return {x: tx, y: ry + rh + g}
        return {x: x, y: y}
    }

    Log(text) {
    }

    SetStatus(state, task := "", biome := "", rare := false, uptimeMs := 0, loops := 0) {
        st := UiLogic.NormState(state)
        up := UiLogic.Uptime(uptimeMs)
        key := st "|" task "|" biome "|" (rare ? 1 : 0) "|" up "|" loops
        if (key == this._key)
            return
        this._key := key
        pl := I18n.T((st = "Paused") ? "Resume" : "Pause")
        if (this._pauseBtn.Text != pl)
            this._pauseBtn.Text := pl
        switch st {
            case "Running": bg := Theme.Accent, fg := Theme.Ink
            case "Paused": bg := Theme.PanelC, fg := Theme.Text
            default: bg := Theme.OffBg, fg := Theme.Muted
        }
        pill := Chr(0x25CF) " " StrUpper(I18n.T(st))
        if (this._pill.Text != pill) {
            this._pill.Text := pill
            Theme.SetColors(this._pill, bg, fg)
        }
        Theme.SetText(this._task, task = "" ? Chr(0x2014) : UiLogic.TaskText(task))
        b := biome = "" ? Chr(0x2014) : biome (rare ? "  " Chr(0x2726) : "")
        if (this._biome.Text != b) {
            this._biome.Text := b
            Theme.SetColors(this._biome, Theme.Bg, rare ? Theme.Accent : Theme.Text)
        }
        Theme.SetText(this._up, up)
        Theme.SetText(this._loops, String(loops))
    }

    _Fire(name) {
        if this._cb.Has(name)
            try this._cb[name].Call()
    }

    ; Drag: a press on the window or a non-button child starts a caption drag.
    _OnLButton(wParam, lParam, msg, hwnd) {
        g := this._gui
        if (hwnd != g.Hwnd) {
            if (DllCall("GetParent", "Ptr", hwnd, "Ptr") != g.Hwnd || Theme._hot.Has(hwnd))
                return
        }
        DllCall("ReleaseCapture")
        PostMessage(0xA1, 2, 0, , "ahk_id " g.Hwnd)              ; WM_NCLBUTTONDOWN, HTCAPTION
        return 0
    }

    _OnMoved(wParam, lParam, msg, hwnd) {
        if (hwnd != this._gui.Hwnd)
            return
        WinGetPos(&x, &y, , , "ahk_id " hwnd)
        this.cfg.Set("Overlay.x", x)
        this.cfg.Set("Overlay.y", y)
        try this.cfg.Save()
    }
}
