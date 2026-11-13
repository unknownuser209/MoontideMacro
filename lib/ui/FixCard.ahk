#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\Theme.ahk
; ---------------------------------------------------------------------------
; FixCard (idea 10, 2026-11-13): a small window with a FixIt rule's plain fix.
; Shown WITHOUT taking focus (Roblox keeps it, the macro keeps running),
; bottom-right of the main screen, always on top.
;
;   c := FixCard(rule, callbacks)   callbacks (Map, all optional):
;       "page" (name) -> opens that dashboard page
;       "act"  (act)  -> "Fix it for me"; returns a line for the card
;       "zip"  ()     -> makes the support zip; returns a line for the card
;       "dismiss" (key)
;   c.Ctrl(id), c.Destroy()
; ---------------------------------------------------------------------------

class FixCard {
    static W := 440
    static H := 214

    __New(rule, callbacks := "") {
        this.rule := rule
        this._cb := (callbacks is Map) ? callbacks : Map()
        this._ids := Map()
        g := Theme.Window("Moontide: something needs a fix", "+AlwaysOnTop -MinimizeBox -MaximizeBox +Owner")
        this._gui := g
        g.OnEvent("Close", (*) => this.Dismiss())
        g.OnEvent("Escape", (*) => this.Dismiss())
        W := FixCard.W
        this._ids["title"] := Theme.Label(g, "x20 y16 w" W - 40 " h26", rule.title, "head", Theme.Bg)
        this._ids["fix"] := Theme.Label(g, "x20 y50 w" W - 40 " h80", rule.fix, "body", Theme.Bg)
        this._ids["note"] := Theme.Label(g, "x20 y132 w" W - 40 " h20", "", "muted", Theme.Bg)
        y := FixCard.H - 50
        x := 20
        if (rule.act != "") {
            this._ids["act"] := Theme.Button(g, "x" x " y" y " w120 h30", "Fix it for me", (*) => this._Act(), "primary")
            x += 128
        }
        if (rule.page != "") {
            this._ids["page"] := Theme.Button(g, "x" x " y" y " w104 h30", "Open the page", (*) => this._Page())
            x += 112
        }
        this._ids["zip"] := Theme.Button(g, "x" x " y" y " w92 h30", "Support zip", (*) => this._Zip(), "quiet")
        this._ids["dismiss"] := Theme.Button(g, "x" W - 20 - 84 " y" y " w84 h30", "Dismiss", (*) => this.Dismiss(), "quiet")
    }

    Ctrl(id) => this._ids[id]
    Hwnd => this._gui.Hwnd

    ; bottom-right of the primary screen's work area, no activation
    Show() {
        MonitorGetWorkArea(MonitorGetPrimary(), , , &r, &b)
        this._gui.Show("x" r - FixCard.W - 24 " y" b - FixCard.H - 24 " w" FixCard.W " h" FixCard.H " NA")
    }

    _Fire(name, args*) {
        if !this._cb.Has(name)
            return ""
        try
            return this._cb[name].Call(args*)
        return ""
    }

    _Note(text) {
        if (text != "")
            Theme.SetText(this._ids["note"], text)
    }

    _Act() => this._Note(this._Fire("act", this.rule.act))
    _Page() => this._Fire("page", this.rule.page)
    _Zip() => this._Note(this._Fire("zip"))

    Dismiss() {
        this._Fire("dismiss", this.rule.key)
        this.Destroy()
    }

    Destroy() {
        try this._gui.Destroy()
    }
}
