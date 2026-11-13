#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\Theme.ahk
#Include %A_LineFile%\..\..\Brand.ahk
#Include %A_LineFile%\..\..\Updater.ahk
; ---------------------------------------------------------------------------
; WhatsNewWindow: "What's new in vX.Y" once after the in-app updater put a
; new version in (App.Boot reads data\whatsnew.json with
; Updater.TakeWhatsNew). Same look as the setup wizard.
;
;   w := WhatsNewWindow(version, notes)   notes: the release text (markdown ok)
;   w.Show(owner := "")   owner: a Gui to centre on (the dashboard)
;   w.Text                the plain text shown (tests)
;   w.Close()             OK / Esc / the X
; ---------------------------------------------------------------------------

class WhatsNewWindow {
    static W := 520
    static H := 420

    __New(version, notes) {
        this.Title := "What's new in v" version
        this.Text := Updater.NotesText(notes)
        if (this.Text = "")
            this.Text := "No notes came with this version."
        this._closed := false
        W := WhatsNewWindow.W, H := WhatsNewWindow.H
        g := Theme.Window(this.Title, "-MinimizeBox -MaximizeBox")
        this._gui := g
        g.OnEvent("Close", (*) => this.Close())
        g.OnEvent("Escape", (*) => this.Close())
        Theme.Moon(g, 24, 20, 32)
        Theme.Label(g, "x68 y24 w" W - 92 " h24", this.Title, "head", Theme.Bg)
        Theme.Rect(g, 24, 62, W - 48, 1, Theme.PanelC)
        this._box := Theme.Edit(g, 24, 78, W - 48, H - 156, this.Text, "Multi ReadOnly -WantReturn VScroll")
        y := H - 56
        Theme.Rect(g, 24, y - 14, W - 48, 1, Theme.PanelC)
        this._ok := Theme.Button(g, "x" W - 24 - 120 " y" y " w120 h32", "OK", (*) => this.Close(), "primary")
    }

    Show(owner := "") {
        g := this._gui
        W := WhatsNewWindow.W, H := WhatsNewWindow.H
        g.Show("w" W " h" H " Hide")
        if IsObject(owner) && DllCall("IsWindowVisible", "Ptr", owner.Hwnd) {
            owner.GetPos(&ox, &oy, &ow, &oh)
            g.Show("x" ox + (ow - W) // 2 " y" oy + (oh - H) // 2)
        } else
            g.Show("Center")
        ; the text starts unselected and scrolled to the top
        try SendMessage(0xB1, 0, 0, this._box)        ; EM_SETSEL
    }

    Hwnd => this._gui.Hwnd

    Close() {
        if this._closed
            return
        this._closed := true
        try Theme.Forget(this._gui)
        try this._gui.Destroy()
    }
}
