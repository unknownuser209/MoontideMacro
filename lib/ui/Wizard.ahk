#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\Theme.ahk
#Include %A_LineFile%\..\UiLogic.ahk
#Include %A_LineFile%\..\..\Config.ahk
#Include %A_LineFile%\..\..\Brand.ahk
; ---------------------------------------------------------------------------
; SetupWizard: the first-run setup, page by page. Every page can be skipped
; (Next leaves an empty field as it was) and "Skip setup" closes it at once.
; Finished or skipped, UI.setupDone = 1 is saved so it does not come back;
; Setup > Check & help runs it again.
;
;   w := SetupWizard(cfg, callbacks := "")
;     callbacks Map (all optional):
;       "checkSetup" ()  -> Array of {level, name, detail, fix} (SetupCheck.Run)
;       "done"       (finished)  after it closes: finished 1 = Finish, 0 = skipped
;   w.Show(owner := "")   owner: a Gui to centre on (the dashboard)
;   w.Step                1..6, the page shown
;   w.Next() / w.Back() / w.Skip() / w.Finish()   (buttons; tests call them)
;   w.Ctrl(id)            tests: "ps", "hook", "run:<key>", "checkOut", "title"
;   w.Destroy()
;   SetupWizard.ShouldShow(cfg)  -> true while UI.setupDone is not 1
;
; Pages: 1 Welcome, 2 Roblox check, 3 Private server, 4 Discord alerts,
; 5 What to run, 6 Done. Values reach cfg when you leave their page with Next
; (cfg.Save() each time), so a skip later keeps what was entered before.
; Secrets (the server link, the webhook URL) are never shown back: a
; password field and a masked "now: ..." line.
; ---------------------------------------------------------------------------

class SetupWizard {
    static W := 600
    static H := 440
    static Steps := 6
    static RunKeys := [["General.fishing", "Fish when nothing else is due", 1], ["Quests.enabled", "Quest board", 1]
        , ["Craft.enabled", "Crafting at the Fisher", 1], ["Merchant.enabled", "Buy from Mari and Jester", 1]
        , ["MemoryMatch.enabled", "Memory Match (every 12 hours)", 0]]

    static ShouldShow(cfg) => !cfg.Get("UI.setupDone", 0)

    __New(cfg, callbacks := "") {
        this.cfg := cfg
        this._cb := (callbacks is Map) ? callbacks : Map()
        this.Step := 1
        this._ids := Map()
        this._pages := []          ; pages[i] = Array of controls
        this._closed := false
        this._finished := 0
        this._Build()
    }

    Ctrl(id) => this._ids[id]

    _Build() {
        g := Theme.Window(Brand.Name " setup", "-MinimizeBox -MaximizeBox")
        this._gui := g
        g.OnEvent("Close", (*) => this.Skip())
        g.OnEvent("Escape", (*) => this.Skip())
        W := SetupWizard.W
        Theme.Moon(g, 24, 20, 32)
        this._ids["title"] := Theme.Label(g, "x68 y20 w420 h28", "", "head", Theme.Bg)
        this._ids["stepText"] := Theme.Label(g, "x" W - 140 " y26 w116 h20 Right", "", "muted", Theme.Bg)
        Theme.Rect(g, 24, 62, W - 48, 1, Theme.PanelC)
        ; pages (each control remembered so only one page shows)
        Loop SetupWizard.Steps {
            Theme.Sink := []
            m := "_Page" A_Index
            this.%m%(g)
            this._pages.Push(Theme.Sink)
            Theme.Sink := ""
        }
        ; buttons
        y := SetupWizard.H - 56
        Theme.Rect(g, 24, y - 14, W - 48, 1, Theme.PanelC)
        this._ids["skipAll"] := Theme.Button(g, "x24 y" y " w120 h32", "Skip setup", (*) => this.Skip(), "quiet")
        this._ids["back"] := Theme.Button(g, "x" W - 24 - 120 - 10 - 120 " y" y " w120 h32", "Back", (*) => this.Back())
        this._ids["next"] := Theme.Button(g, "x" W - 24 - 120 " y" y " w120 h32", "Next", (*) => this.Next(), "primary")
        this._Show(1)
    }

    ; ---- pages ------------------------------------------------------------------

    _Page1(g) {
        Theme.Label(g, "x24 y84 w552 h80", "A few quick steps get the macro ready: a check of your PC, your private server, Discord alerts and what to run.`n`n"
            . "Every step can be skipped, and everything can be changed later in the dashboard.", "body", Theme.Bg)
        Theme.Label(g, "x24 y196 w552 h60", "Hotkeys: F1 start   F2 pause / resume   F3 stop", "body", Theme.Bg, Theme.Accent)
    }

    _Page2(g) {
        Theme.Label(g, "x24 y80 w440 h40", "Open Roblox in fullscreen, join Sol's RNG, then press Check. Nothing is clicked.", "body", Theme.Bg)
        Theme.Button(g, "x476 y82 w100 h30", "Check", (*) => this._Check(), "primary")
        this._ids["checkOut"] := Theme.Edit(g, 24, 128, 552, 230, "", "Multi ReadOnly -WantReturn VScroll")
    }

    _Page3(g) {
        Theme.Label(g, "x24 y80 w552 h60", "Paste your private server link. The macro uses it to rejoin you after a disconnect, a crash or a Roblox update. "
            . "It is stored only in settings.ini and never shown or logged.", "body", Theme.Bg)
        this._ids["ps"] := Theme.Edit(g, 24, 160, 552, 30, "", "Password")
        this._ids["psNow"] := Theme.Label(g, "x24 y198 w552 h20", "", "muted", Theme.Bg)
        this._ids["psWhy"] := Theme.Label(g, "x24 y226 w552 h40", "", "body", Theme.Bg, Theme.Accent)
    }

    _Page4(g) {
        Theme.Label(g, "x24 y80 w552 h60", "Optional: paste a Discord webhook URL to get rare biome alerts, errors and start / stop messages. "
            . "Discord: channel settings > Integrations > Webhooks > New Webhook > Copy Webhook URL.", "body", Theme.Bg)
        this._ids["hook"] := Theme.Edit(g, 24, 160, 552, 30, "", "Password")
        this._ids["hookNow"] := Theme.Label(g, "x24 y198 w552 h20", "", "muted", Theme.Bg)
        this._ids["hookWhy"] := Theme.Label(g, "x24 y226 w552 h40", "", "body", Theme.Bg, Theme.Accent)
    }

    _Page5(g) {
        Theme.Label(g, "x24 y80 w552 h20", "What should the macro do? Rare-biome alerts always run.", "body", Theme.Bg)
        for i, k in SetupWizard.RunKeys
            this._ids["run:" k[1]] := Theme.Check(g, 24, 116 + (i - 1) * 36, k[2], 0, "", "pill", 400)
        Theme.Label(g, "x24 y310 w552 h40", "Hunting (Limited tab) and the obby stay off here: turn them on in the dashboard when you want them.", "muted", Theme.Bg)
    }

    _Page6(g) {
        Theme.Label(g, "x24 y84 w552 h100", "You are set. Click into Roblox and press F1 to start, F2 to pause, F3 to stop.`n`n"
            . "Setup > Check & help checks your PC again and makes a log zip if you need help. Potion use starts in dry run: nothing is drunk until you turn dry run off on Home.", "body", Theme.Bg)
    }

    ; ---- flow -------------------------------------------------------------------

    static Titles := ["Welcome to " Brand.Name, "Check your PC", "Private server", "Discord alerts", "What to run", "All done"]

    _Show(n) {
        this.Step := n
        for i, ctrls in this._pages
            for c in ctrls
                c.Visible := (i = n)
        Theme.SetText(this._ids["title"], SetupWizard.Titles[n])
        Theme.SetText(this._ids["stepText"], "Step " n " of " SetupWizard.Steps)
        this._ids["back"].Visible := (n > 1)
        this._ids["skipAll"].Visible := (n < SetupWizard.Steps)
        Theme.SetText(this._ids["next"], n = SetupWizard.Steps ? "Finish" : n = 1 ? "Start" : "Next")
        this._Load(n)
    }

    _Load(n) {
        switch n {
            case 3:
                cur := this.cfg.Get("General.privateServer", "")
                this._ids["ps"].Value := ""
                Theme.SetText(this._ids["psNow"], cur = "" ? "Now: not set (Next with an empty box skips this)" : "Now: " UiLogic.MaskSecret(cur) " (leave the box empty to keep it)")
                Theme.SetText(this._ids["psWhy"], "")
            case 4:
                n := 0
                for h in this.cfg.Webhooks()
                    n += (h.Has("url") && UiLogic.IsWebhookUrl(h["url"])) ? 1 : 0
                this._ids["hook"].Value := ""
                Theme.SetText(this._ids["hookNow"], n ? "Now: " n " webhook" (n = 1 ? "" : "s") " set (a new URL is added as another one)" : "Now: none (Next with an empty box skips this)")
                Theme.SetText(this._ids["hookWhy"], "")
            case 5:
                for k in SetupWizard.RunKeys
                    this._ids["run:" k[1]].Value := this.cfg.Get(k[1], k[3]) ? 1 : 0
        }
    }

    ; -> "" or why the page cannot be left (shown on it); writes its values
    _Leave(n) {
        switch n {
            case 3:
                typed := Trim(this._ids["ps"].Value)
                if (typed = "")
                    return ""
                if !RegExMatch(typed, "i)^https?://(www\.)?roblox\.com/")
                    return this._Why("psWhy", "That is not a Roblox link. Copy it from your private server's Share / Copy Link button.")
                this.cfg.Set("General.privateServer", typed)
                this._ids["ps"].Value := ""
                this._Save()
            case 4:
                typed := Trim(this._ids["hook"].Value)
                if (typed = "")
                    return ""
                if !UiLogic.IsWebhookUrl(typed)
                    return this._Why("hookWhy", "That is not a Discord webhook URL (it starts with https://discord.com/api/webhooks/).")
                hooks := []
                for h in this.cfg.Webhooks()
                    hooks.Push(h)
                if (hooks.Length >= 8)
                    return this._Why("hookWhy", "There are already 8 webhooks: add more under Alerts > Discord.")
                hooks.Push(Map("name", "Webhook " (hooks.Length + 1), "url", typed, "mention", "", "enabled", 1
                    , "events", ["biome", "rare", "errors", "startstop"]))
                this.cfg.SetWebhooks(hooks)
                this._ids["hook"].Value := ""
                this._Save()
            case 5:
                for k in SetupWizard.RunKeys
                    this.cfg.Set(k[1], this._ids["run:" k[1]].Value ? 1 : 0)
                this._Save()
        }
        return ""
    }

    _Why(id, text) {
        Theme.SetText(this._ids[id], text)
        return "bad"
    }

    _Save() {
        try this.cfg.Save()
    }

    Next() {
        if (this._Leave(this.Step) != "")
            return false
        if (this.Step >= SetupWizard.Steps)
            return this.Finish()
        this._Show(this.Step + 1)
        return true
    }

    Back() {
        if (this.Step > 1)
            this._Show(this.Step - 1)
    }

    Skip() => this._Close(0)

    Finish() => this._Close(1)

    _Close(finished) {
        if this._closed
            return true
        this._closed := true
        this._finished := finished
        this.cfg.Set("UI.setupDone", 1)
        this._Save()
        try this._gui.Hide()
        if this._cb.Has("done")
            try this._cb["done"].Call(finished)
        this.Destroy()
        return true
    }

    _Check() {
        out := this._ids["checkOut"]
        if !this._cb.Has("checkSetup") {
            out.Value := "The check is not available here."
            return
        }
        res := ""
        try res := this._cb["checkSetup"].Call()
        text := ""
        if IsObject(res) {
            tags := Map("ok", "[OK]", "warn", "[!]", "fail", "[X]", "info", "[i]")
            for r in res {
                lv := r.HasProp("level") ? r.level : "info"
                text .= (tags.Has(lv) ? tags[lv] : "[i]") "  " r.name (r.HasProp("detail") && r.detail != "" ? ": " r.detail : "") "`r`n"
                if (r.HasProp("fix") && r.fix != "" && lv != "ok")
                    text .= "       " r.fix "`r`n"
            }
        }
        out.Value := (text = "") ? "Nothing to show." : text
    }

    Show(owner := "") {
        g := this._gui
        g.Show("w" SetupWizard.W " h" SetupWizard.H " Hide")
        if IsObject(owner) && DllCall("IsWindowVisible", "Ptr", owner.Hwnd) {
            owner.GetPos(&ox, &oy, &ow, &oh)
            g.Show("x" ox + (ow - SetupWizard.W) // 2 " y" oy + (oh - SetupWizard.H) // 2)
        } else
            g.Show("Center")
    }

    Hwnd => this._gui.Hwnd

    Destroy() {
        try Theme.Forget(this._gui)
        try this._gui.Destroy()
    }
}
