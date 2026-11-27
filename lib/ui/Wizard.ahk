#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\Theme.ahk
#Include %A_LineFile%\..\UiLogic.ahk
#Include %A_LineFile%\..\..\Config.ahk
#Include %A_LineFile%\..\..\Brand.ahk
; ---------------------------------------------------------------------------
; SetupWizard: the first-run setup, page by page. Every page can be skipped
; (Next leaves an empty field as it was) and "Skip setup" closes it at once.
; Finished or skipped, UI.setupDone = 1 is saved so it does not come back;
; Help > Check & help runs it again.
;
;   w := SetupWizard(cfg, callbacks := "")
;     callbacks Map (all optional):
;       "checkSetup" ()  -> Array of {level, name, detail, fix} (SetupCheck.Run)
;       "lang"       (code)      after it closes, when the language picked on
;                                page 1 is not the one the app started in
;       "done"       (finished)  after it closes: finished 1 = Finish, 0 = skipped
;   w.Show(owner := "")   owner: a Gui to centre on (the dashboard)
;   w.Step                1..7, the page shown
;   w.Next() / w.Back() / w.Skip() / w.Finish()   (buttons; tests call them)
;   w.PickLanguage(lang)  page 1: a code or a name from I18n.Names -> the code
;   w.Ctrl(id)            tests: "ps", "hook", "run:<key>", "vip", "checkOut", "title",
;                         "lang:<code>"
;   w.Destroy()           not closed yet: drops a language pick (the app's
;                         language back) -> its code, "" when none
;   SetupWizard.ShouldShow(cfg)  -> true while UI.setupDone is not 1
;
; Pages: 1 Language, 2 Welcome, 3 Roblox check, 4 Private server, 5 Discord
; alerts, 6 What to run (and the VIP gamepass: General.vip), 7 Done. Picking a language saves UI.lang at once and
; builds the window again in that language (I18n.Use), still on page 1; when
; the wizard closes the app's own language is put back and "lang" tells the
; app (it restarts to show the new language everywhere). Other values reach
; cfg when you leave their page with Next (cfg.Save() each time), so a skip
; later keeps what was entered before.
; Secrets (the server link, the webhook URL) are never shown back: a
; password field and a masked "now: ..." line.
; ---------------------------------------------------------------------------

class SetupWizard {
    static W := 600
    static H := 470
    static Pages := ["Lang", "Welcome", "Check", "Server", "Discord", "Run", "Done"]
    static Steps => SetupWizard.Pages.Length
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
        this._lang0 := I18n.Lang   ; the app's language, put back on close
        this._Build()
    }

    Ctrl(id) => this._ids[id]

    _Build() {
        g := Theme.Window(I18n.F("{1} setup", Brand.Name), "-MinimizeBox -MaximizeBox")
        this._gui := g
        g.OnEvent("Close", (*) => this.Skip())
        g.OnEvent("Escape", (*) => this.Skip())
        W := SetupWizard.W
        Theme.Moon(g, 24, 20, 32)
        this._ids["title"] := Theme.Label(g, "x68 y20 w420 h28", "", "head", Theme.Bg)
        this._ids["stepText"] := Theme.Label(g, "x" W - 140 " y26 w116 h20 Right", "", "muted", Theme.Bg)
        Theme.Rect(g, 24, 62, W - 48, 1, Theme.PanelC)
        ; pages (each control remembered so only one page shows)
        for name in SetupWizard.Pages {
            Theme.Sink := []
            m := "_Page" name
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

    ; Every language in its own name (never translated), two columns; the
    ; picked one (UI.lang, English when unset) is lit.
    _PageLang(g) {
        Theme.Label(g, "x24 y80 w552 h40", "Pick the language of this window. You can change it later in Settings > Look.", "body", Theme.Bg)
        cur := I18n.IndexOf(this.cfg.Get("UI.lang", "en"))
        group := Map()
        Theme.Font(g, "button")
        for i, name in I18n.Names {
            x := 24 + Mod(i - 1, 2) * 284, y := 136 + ((i - 1) // 2) * 44
            c := Theme.Add(g, "Text", "x" x " y" y " w268 h34 +0x100 +0x200 Center", name)
            group[name] := ThemeOption(c, name, group, (nm) => SetTimer(ObjBindMethod(this, "PickLanguage", nm), -1), i = cur)
            this._ids["lang:" I18n.Codes[i]] := group[name]
        }
    }

    _PageWelcome(g) {
        Theme.Label(g, "x24 y84 w552 h80", "A few quick steps get the macro ready: a check of your PC, your private server, Discord alerts and what to run.`n`n"
            . "Every step can be skipped, and everything can be changed later in the dashboard.", "body", Theme.Bg)
        Theme.Label(g, "x24 y196 w552 h60", "Hotkeys: F1 start   F2 pause / resume   F3 stop", "body", Theme.Bg, Theme.Accent)
    }

    _PageCheck(g) {
        Theme.Label(g, "x24 y80 w440 h40", "Open Roblox (fullscreen or in a window), join Sol's RNG, then press Check. Nothing is clicked.", "body", Theme.Bg)
        Theme.Button(g, "x476 y82 w100 h30", "Check", (*) => this._Check(), "primary")
        this._ids["checkOut"] := Theme.Edit(g, 24, 128, 552, 230, "", "Multi ReadOnly -WantReturn VScroll")
    }

    _PageServer(g) {
        Theme.Label(g, "x24 y80 w552 h60", "Paste your private server link. The macro uses it to rejoin you after a disconnect, a crash or a Roblox update. "
            . "It is stored only in settings.ini and never shown or logged.", "body", Theme.Bg)
        this._ids["ps"] := Theme.Edit(g, 24, 160, 552, 30, "", "Password")
        this._ids["psNow"] := Theme.Label(g, "x24 y198 w552 h20", "", "muted", Theme.Bg)
        this._ids["psWhy"] := Theme.Label(g, "x24 y226 w552 h40", "", "body", Theme.Bg, Theme.Accent)
    }

    _PageDiscord(g) {
        Theme.Label(g, "x24 y80 w552 h60", "Optional: paste a Discord webhook URL to get rare biome alerts, errors and start / stop messages. "
            . "Discord: channel settings > Integrations > Webhooks > New Webhook > Copy Webhook URL.", "body", Theme.Bg)
        this._ids["hook"] := Theme.Edit(g, 24, 160, 552, 30, "", "Password")
        this._ids["hookNow"] := Theme.Label(g, "x24 y198 w552 h20", "", "muted", Theme.Bg)
        this._ids["hookWhy"] := Theme.Label(g, "x24 y226 w552 h40", "", "body", Theme.Bg, Theme.Accent)
    }

    _PageRun(g) {
        Theme.Label(g, "x24 y80 w552 h20", "What should the macro do? Rare-biome alerts always run.", "body", Theme.Bg)
        for i, k in SetupWizard.RunKeys
            this._ids["run:" k[1]] := Theme.Check(g, 24, 116 + (i - 1) * 36, k[2], 0, "", "pill", 400)
        ; the shipped walks were recorded with VIP's faster walking; without it
        ; they stop short of the fishing spot (tester 2026-11-24). Asked here
        ; because General.vip defaults to 1 and nobody finds it in Settings.
        this._ids["vip"] := Theme.Check(g, 24, 116 + SetupWizard.RunKeys.Length * 36 + 6, "I own the VIP gamepass in Sol's RNG (faster walking)", 0, "", "pill", 520)
        Theme.Label(g, "x24 y342 w552 h44", "Orb & boss hunting (Plugins tab) and the obby stay off here: turn them on in the dashboard when you want them.", "muted", Theme.Bg)
    }

    _PageDone(g) {
        Theme.Label(g, "x24 y84 w552 h100", "You are set. Click into Roblox and press F1 to start, F2 to pause, F3 to stop.`n`n"
            . "Help > Check & help checks your PC again and makes a log zip if you need help. Potion use starts in dry run: nothing is drunk until you turn dry run off on Home.", "body", Theme.Bg)
    }

    ; ---- flow -------------------------------------------------------------------

    static Titles := ["Choose your language", "Welcome to " Brand.Name, "Check your PC", "Private server", "Discord alerts", "What to run", "All done"]

    _Show(n) {
        this.Step := n
        for i, ctrls in this._pages
            for c in ctrls
                c.Visible := (i = n)
        Theme.SetText(this._ids["title"], n = 2 ? I18n.F("Welcome to {1}", Brand.Name) : I18n.T(SetupWizard.Titles[n]))
        Theme.SetText(this._ids["stepText"], I18n.F("Step {1} of {2}", n, SetupWizard.Steps))
        this._ids["back"].Visible := (n > 1)
        this._ids["skipAll"].Visible := (n < SetupWizard.Steps)
        Theme.SetText(this._ids["next"], I18n.T(n = SetupWizard.Steps ? "Finish" : n = 2 ? "Start" : "Next"))
        this._Load(n)
    }

    _Load(n) {
        switch SetupWizard.Pages[n] {
            case "Server":
                cur := this.cfg.Get("General.privateServer", "")
                this._ids["ps"].Value := ""
                Theme.SetText(this._ids["psNow"], cur = "" ? I18n.T("Now: not set (Next with an empty box skips this)") : I18n.F("Now: {1} (leave the box empty to keep it)", UiLogic.MaskSecret(cur)))
                Theme.SetText(this._ids["psWhy"], "")
            case "Discord":
                n := 0
                for h in this.cfg.Webhooks()
                    n += (h.Has("url") && UiLogic.IsWebhookUrl(h["url"])) ? 1 : 0
                this._ids["hook"].Value := ""
                Theme.SetText(this._ids["hookNow"], n ? I18n.F(n = 1 ? "Now: {1} webhook set (a new URL is added as another one)" : "Now: {1} webhooks set (a new URL is added as another one)", n)
                    : I18n.T("Now: none (Next with an empty box skips this)"))
                Theme.SetText(this._ids["hookWhy"], "")
            case "Run":
                for k in SetupWizard.RunKeys
                    this._ids["run:" k[1]].Value := this.cfg.Get(k[1], k[3]) ? 1 : 0
                ; first setup: unticked, so it is a question; run again from
                ; Help it shows the saved choice
                this._ids["vip"].Value := (this.cfg.Get("UI.setupDone", 0) && this.cfg.Get("General.vip", 1)) ? 1 : 0
        }
    }

    ; -> "" or why the page cannot be left (shown on it); writes its values
    _Leave(n) {
        switch SetupWizard.Pages[n] {
            case "Server":
                typed := Trim(this._ids["ps"].Value)
                if (typed = "")
                    return ""
                ; the same check auto-rejoin uses (RecoveryTask.LinkOk): a link
                ; without "https://www." was taken here and refused at rejoin
                if (SubStr(typed, 1, 23) != "https://www.roblox.com/" || StrLen(typed) <= 23 || RegExMatch(typed, "[\s`"<>``\\|^]"))
                    return this._Why("psWhy", "That is not a Roblox private server link (it starts with https://www.roblox.com/). Copy it from your private server's Share / Copy Link button.")
                this.cfg.Set("General.privateServer", typed)
                this._ids["ps"].Value := ""
                this._Save()
            case "Discord":
                typed := Trim(this._ids["hook"].Value)
                if (typed = "")
                    return ""
                if !UiLogic.IsWebhookUrl(typed)
                    return this._Why("hookWhy", "That is not a Discord webhook URL (it starts with https://discord.com/api/webhooks/).")
                hooks := []
                for h in this.cfg.Webhooks()
                    hooks.Push(h)
                if (hooks.Length >= 8)
                    return this._Why("hookWhy", "There are already 8 webhooks: add more under Discord & Clips > Discord.")
                hooks.Push(Map("name", "Webhook " (hooks.Length + 1), "url", typed, "mention", "", "enabled", 1
                    , "events", Config.EventTypes.Clone()))   ; every box ticked
                this.cfg.SetWebhooks(hooks)
                this._ids["hook"].Value := ""
                this._Save()
            case "Run":
                for k in SetupWizard.RunKeys
                    this.cfg.Set(k[1], this._ids["run:" k[1]].Value ? 1 : 0)
                this.cfg.Set("General.vip", this._ids["vip"].Value ? 1 : 0)
                this._Save()
        }
        return ""
    }

    _Why(id, text) {
        Theme.SetText(this._ids[id], I18n.T(text))
        return "bad"
    }

    _Save() {
        try this.cfg.Save()
    }

    ; Page 1: `lang` (a code or a name; unknown -> English) becomes UI.lang,
    ; saved at once, and the window is built again in it (same place, page 1).
    ; -> the code saved.
    PickLanguage(lang) {
        if this._closed
            return I18n.Lang
        code := I18n.CodeOf(lang)
        this.cfg.Set("UI.lang", code)
        this._Save()
        if (code = I18n.Lang) {
            for i, c in I18n.Codes
                try this._ids["lang:" c].Value := (c = code)
            return code
        }
        I18n.Use(code)
        this._Rebuild()
        return code
    }

    ; A new window with the texts in the language now in use, where the old
    ; one was (shown only when the old one was shown), then the old one goes.
    _Rebuild() {
        old := this._gui, step := this.Step
        vis := false, x := 0, y := 0
        try {
            vis := DllCall("IsWindowVisible", "Ptr", old.Hwnd)
            if vis
                WinGetPos(&x, &y, , , old.Hwnd)
        }
        this._ids := Map()
        this._pages := []
        this._Build()
        if (step != 1)
            this._Show(step)
        if vis
            try this._gui.Show("x" x " y" y " w" SetupWizard.W " h" SetupWizard.H)
        try Theme.Forget(old)
        try old.Destroy()
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
        picked := I18n.Lang
        if (picked != this._lang0) {
            I18n.Use(this._lang0)          ; the app's windows were built in it
            if this._cb.Has("lang")
                try this._cb["lang"].Call(picked)
        }
        if this._cb.Has("done")
            try this._cb["done"].Call(finished)
        this.Destroy()
        return true
    }

    _Check() {
        out := this._ids["checkOut"]
        if !this._cb.Has("checkSetup") {
            out.Value := I18n.T("The check is not available here.")
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
        out.Value := (text = "") ? I18n.T("Nothing to show.") : text
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

    ; Not closed yet (the app opens the wizard again from Help, or a test):
    ; it counts as closed from now on (a late language pick does nothing), a
    ; language picked here is dropped and the app's own language comes back
    ; (its windows were built in it); nothing is told. -> the code of the
    ; dropped pick ("" when none; UI.lang keeps it, the caller may restart).
    Destroy() {
        dropped := ""
        if !this._closed {
            this._closed := true
            if (I18n.Lang != this._lang0) {
                dropped := I18n.Lang
                I18n.Use(this._lang0)
            }
        }
        try Theme.Forget(this._gui)
        try this._gui.Destroy()
        return dropped
    }
}
