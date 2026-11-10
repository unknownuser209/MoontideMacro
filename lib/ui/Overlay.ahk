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
        vx := SysGet(76), vy := SysGet(77), vw := SysGet(78), vh := SysGet(79)   ; virtual screen
        if (x < vx || y < vy || x > vx + vw - 40 || y > vy + vh - 40) {
            x := A_ScreenWidth - Overlay.W - 24
            y := 24
        }
        this._gui.Show("x" x " y" y " w" Overlay.W " h" Overlay.H " NoActivate")
        this._shown := true
    }

    Hide() {
        this._gui.Hide()
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
        pl := (st = "Paused") ? "Resume" : "Pause"
        if (this._pauseBtn.Text != pl)
            this._pauseBtn.Text := pl
        switch st {
            case "Running": bg := Theme.Accent, fg := Theme.Ink
            case "Paused": bg := Theme.PanelC, fg := Theme.Text
            default: bg := Theme.OffBg, fg := Theme.Muted
        }
        pill := Chr(0x25CF) " " StrUpper(st)
        if (this._pill.Text != pill) {
            this._pill.Text := pill
            Theme.SetColors(this._pill, bg, fg)
        }
        Theme.SetText(this._task, task = "" ? Chr(0x2014) : task)
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
