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
;   c.ShowAt(x, y) / c.Hide()   App places it (FixCard.Spot): never over the
;                               Roblox client while the macro runs
;   FixCard.Spot(w, h, game, mons, pref) -> {x, y} or "" (no room)
;
; Live 2026-11-20: the card sat over the game's bottom right from 12:51 to
; past 15:49. It hid the "no merchant spawned" toast (Jester's visit read
; nothing) and the quests read its title as a game notification
; ("Moontide: something needs a fix", 13:53). So: off the game, else hidden
; while the macro runs, and closed when its problem stops showing (App).
; ---------------------------------------------------------------------------

class FixCard {
    static W := 440
    static H := 214

    __New(rule, callbacks := "") {
        this.rule := rule
        this._cb := (callbacks is Map) ? callbacks : Map()
        this._ids := Map()
        g := Theme.Window("Moontide: something needs a fix", "+AlwaysOnTop -MinimizeBox -MaximizeBox +Owner +ToolWindow +E0x08000000")   ; E0x08000000: never activated (clicks keep Roblox in front)
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
        p := FixCard.Pos(r, b)
        this.ShowAt(p.x, p.y)
    }

    at := ""                        ; "x,y" while shown, "" hidden
    ShowAt(x, y) {
        if (this.at = x "," y)
            return
        this._gui.Show("x" x " y" y " w" FixCard.W " h" FixCard.H " NA")
        this.at := x "," y
    }

    Hide() {
        if (this.at = "")
            return
        try this._gui.Hide()
        this.at := ""
    }

    ; Where a w x h card goes (screen px). game: the Roblox client {x, y, w,
    ; h} ("" = none); mons: the monitors' work areas [{l, t, r, b}]; pref:
    ; its usual top-left. -> pref when it covers no game; else the bottom
    ; right of a monitor clear of the game; else beside the game on a
    ; monitor; else "" (no room: App hides it while the macro runs).
    static Spot(w, h, game, mons, pref) {
        clear := (x, y) => !IsObject(game) || x >= game.x + game.w || x + w <= game.x || y >= game.y + game.h || y + h <= game.y
        inside := (x, y) => FixCard._OnAMonitor(x, y, w, h, mons)
        if (clear(pref.x, pref.y) && inside(pref.x, pref.y))
            return {x: pref.x, y: pref.y}
        g := 24
        for m in mons {
            x := m.r - w - g, y := m.b - h - g
            if (clear(x, y) && inside(x, y))
                return {x: x, y: y}
        }
        if !IsObject(game)
            return ""
        ty := game.y + game.h - h
        for c in [[game.x + game.w + 8, ty], [game.x - 8 - w, ty], [game.x + game.w - w, game.y - 8 - h], [game.x + game.w - w, game.y + game.h + 8]]
            if (clear(c[1], c[2]) && inside(c[1], c[2]))
                return {x: c[1], y: c[2]}
        return ""
    }

    static _OnAMonitor(x, y, w, h, mons) {
        for m in mons
            if (x >= m.l && y >= m.t && x + w <= m.r && y + h <= m.b)
                return true
        return false
    }

    ; its top-left for a work area ending at r, b (screen px): the size in
    ; screen px at the Windows scale (Theme.Dpi), so it stays on the screen
    static Pos(r, b) => {x: r - Theme.Dpi(FixCard.W + 24), y: b - Theme.Dpi(FixCard.H + 24)}

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
        this.at := ""
        try Theme.Forget(this._gui)     ; the hovered Dismiss button must not be painted after it is gone
        try this._gui.Destroy()
    }
}
