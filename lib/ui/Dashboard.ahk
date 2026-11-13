#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\Theme.ahk
#Include %A_LineFile%\..\Anim.ahk
#Include %A_LineFile%\..\..\Credits.ahk
#Include %A_LineFile%\..\UiLogic.ahk
#Include %A_LineFile%\..\..\Config.ahk
#Include %A_LineFile%\..\..\GameLists.ahk
#Include %A_LineFile%\..\..\Calibrate.ahk
#Include %A_LineFile%\..\..\Clip.ahk
#Include %A_LineFile%\..\..\RouteRecorder.ahk
#Include %A_LineFile%\..\..\tasks\BiomeItems.ahk
#Include %A_LineFile%\..\..\tasks\MemoryMatch.ahk
; ---------------------------------------------------------------------------
; Dashboard: the main Moontide Macro window (1040x680). The sidebar lists six
; hubs (Dashboard.Hubs); a hub shows its title, a tab strip of its pages and
; the active page. Pages keep their own load / save / revert / validate;
; switching tabs or hubs only hides controls, so unsaved edits stay. A tab
; with unsaved edits shows a gold dot (a bound control differs from its
; loaded value, or the page marked itself dirty: list Add / Remove, ...).
;
; Look: the darkened art (assets\moontide_bg_dim.png, tools\make_bg.py) sits
; behind the content; every group of settings is on a solid Theme.Panel()
; (left column x 204, right column x 616, both 396 wide; content y 152-616,
; the Save bar below). Long explanations are "?" help tips (Theme.Help);
; every on/off is a pill switch; list names are title-cased on Add/Update and
; an empty Merchants list shows a hint. Ids: "panel:<page>:<title>",
; "merch.empty:<who>" (hint), "merch.who:<who>", "merch.status".
;
; API (for Vesper.ahk / Task 14b)
;   d := Dashboard(cfg, callbacks)
;       cfg        Config instance (lib\Config.ahk).
;       callbacks  Map of optional callables (all may be missing):
;         "start" / "pause" / "stop"   ()        header + Run page buttons
;         "calibrate"                  (ids)     run the wizard; default is
;                                                Calibrate.Run(ids). ids is an
;                                                Array of step ids or "all".
;         "saved"                      (page)    after a page saved (page name)
;         "potionsChanged"             ()        potions.json / biomes.json
;                                                changed on disk: fired after
;                                                Unlock, Re-lock and the
;                                                Biomes & Potions Save. PotionSafety
;                                                snapshots caps and locks when it
;                                                is constructed, so the app must
;                                                rebuild it on this callback or
;                                                the change does not reach a
;                                                running macro.
;         "close"                      ()        window X; default: hide
;         "recordRoute"                (name)    Routes tab Record button ->
;                                                {ok, msg, ...}; default runs
;                                                RouteRecorder.Run on
;                                                <cfg dir>\data\routes.json and
;                                                reloads cfg routes
;         "testRoute"                  (name)    Routes tab route "Test" button
;                                                -> {ok, msg}: the app respawns,
;                                                walks the route and presses
;                                                its E / F (no default: needs
;                                                the running app)
;         "testWebhook"                (index)   Alerts > Discord row "Test" button
;                                                (index of the SAVED webhook) ->
;                                                status text shown in the page
;                                                status line (scrubbed again)
;         "testEvent"                  (kind)    Setup > Dev tools test buttons
;                                                ("biome" | "merchant") ->
;                                                message shown (the app
;                                                refuses unless dry run ON)
;   Pause buttons read "Resume" while the state is Paused.
;   d.Show() / d.Hide()
;   d.Destroy()      tests: destroys the window, stops its animations, frees
;                    the moon frames (the app never destroys its Dashboard)
;   d.SetStatus(state, task, biome, rare, uptimeMs, loops)
;       state "Running" | "Paused" | "Stopped" (any case). Cheap: unchanged
;       values are not redrawn, so it can be called every scheduler tick.
;   d.Log(text)      adds "HH:mm:ss  text" to the 200-line log. Text is
;                    scrubbed first (Discord webhook URLs, roblox links, the
;                    configured webhook URLs and private-server link).
;   d.RecordRoute(name), d.TestRoute(name)   (Setup > Routes buttons)
;   d.TestEvent(kind)                        (Setup > Dev tools buttons)
;   d.SelectHub(i)   hub i on its last-opened tab (its first tab at start)
;   d.SelectPage(i)  page i of Dashboard.Pages, with its hub and tab
;   d.SavePage(name), d.RevertPage(name), d.LogText(), d.ActivePage (name),
;   d.ActiveHub (index), d.PageOf(ctrl) (page name), d.Ctrl(id), d.Hwnd
;       (tests / harness). Header ids: "hub:" hub name, "hubTitle",
;       "tab:" page, "tabDot:" page, "tabUnderline", "desc:" page.
;   Dashboard.Hubs, Dashboard.TabLabel(page), Dashboard.HubOf(page),
;   Dashboard.PageIndex(name)
;
;   d.SetStats(stats)  Map of this session's counters (App state.stats:
;       "fishCaught", "biomes", "rareBiomes", optional "loops"; missing = 0,
;       Loops falls back to SetStatus' loops). Home "Stats" tiles, ids
;       "stat:loops", "stat:fish", "stat:biomes", "stat:rare".
;
; Animations (lib\ui\Anim.ahk; the constructor sets Anim.gateFn to "window
; visible, not minimized and in the foreground" and Anim.enabledFn to cfg
; UI.animations, both read live). All are gated: while Roblox (or anything
; else) is in front they do not step; a tween then jumps to its end.
;   "underline" 180 ms  tab underline glides to the clicked tab
;   "fade"      150 ms  a Theme.Bg cover (layered child window over x 176..1040,
;                       y 150..620) fades 255 -> 0 after a tab switch, then hides
;   "count"     600 ms  Home stat tiles count up from 0 when Home opens
;   "pulse"     loop 1600 ms while Running: header pill (and the sidebar chip
;                       while it is gold) between Theme.Accent and PulseDark
;   "moon"      loop 3200 ms: header logo through assets\ui\moon_0..7.png
;   "stars"     loop: 8 stars in the header / sidebar, each its own period
; Loops start in Show() and after a Settings save (UI.animations may have
; changed); WM_ACTIVATE on the window calls Anim.Wake() so frozen loops resume.
;
; No polling.
;
; Config keys written (Section.key, default):
;   General: fishing 1 (0 = never fish), sellEvery 15 (min 1), sellAll 1, advancedFishing 0, advancedThreshold 20,
;     fishingFailsafeSec 31, pathingFailsafeSec 61, vip 1, questIntervalMin 30,
;     sound 1, everyonePing 1, everyoneBiomes "DREAMSPACE,GLITCHED,CYBERSPACE",
;     dryRun 1 (saved immediately; turning it off asks first),
;     privateServer (SECRET: masked, never shown or logged)
;   Craft (the keys lib\tasks\Craft.ahk reads): enabled 1, cauldron 0,
;     craftTarget "", potions (csv of names), qty_<id> per potion where
;     <id> = SubStr(Calibrate.PotionId(name), StrLen(Calibrate.PotionPrefix) + 1);
;     a potion without qty_<id> shows Craft.qty (default 1).
;   quests.enabled 1, quests.dismissDisabled 0 | merchant.enabled 1,
;     merchant.chatPollSec 5
;   recovery: enabled 1, afkMin 15, stuckMin 10, loadSec 20
;   Limbo: enabled 0 (Automate > Limbo)
;   Medal (Alerts > Clips): enabled 0, clipHotkey F8 (Clips save refuses a key that
;     Clip.HotkeyProblem rejects: not F4-F24, or a macro / capture /
;     recorder key), delaySec 3, cooldownSec 30, onRareBiome 1,
;     onRareAura 0, auras "", auraMinRarity 100000000 (field shows commas,
;     accepts "100m" / "1b" / "1,000,000,000"; unparsable -> not saved),
;     auraAlwaysCategories "Challenged,Challenged+"
;   Tools page (tab "Routes"): Record route buttons (data\routes.json via
;     RouteRecorder). Dev tools page: test events (refused by the app
;     unless dry run is ON).
;   Webhook.N via cfg.SetWebhooks (URL masked, only replaced when a new
;     https://discord.com/api/webhooks/... URL is typed)
;   data\biomes.json (rare, potions[{name: <potion id>, qty}]; the dropdown
;   lists potions.json ids so the three Godly Potions are distinct),
;   potions.json (caps; locked
;   only via Unlock/Re-lock, saved at once), quests.json (enabled flags),
;   merchants.json (Mari/Jester [{name,qty}]). Data saves copy the edited
;   fields into the cfg.Data Maps (entries matched by id, else name; unknown
;   extra fields are kept) and write the file. Modules that copied data at
;   construction (PotionSafety) do NOT see it: use "potionsChanged".
; ---------------------------------------------------------------------------

class Dashboard {
    static W := 1040
    static H := 680
    ; Internal page names (SavePage / tests); the user sees TabLabel(name).
    static Pages := ["Run", "Fishing", "Craft", "Quests", "Merchants", "Biomes & Potions", "Biome items", "Obby & Memory", "Webhooks", "Calibrate", "Settings", "Tools", "Limbo", "Clips", "Dev tools"
        , "Stats", "Hunting", "Summary", "Remote", "Check", "Schedule", "Credits", "Log"]
    static Builders := ["_PageRun", "_PageFishing", "_PageCraft", "_PageQuests", "_PageMerchants", "_PageBiomes", "_PageBiomeItems", "_PageObbyMemory", "_PageWebhooks", "_PageCalibrate", "_PageSettings", "_PageTools", "_PageLimbo", "_PageClips", "_PageDevTools"
        , "_PageStats", "_PageHunting", "_PageSummary", "_PageRemote", "_PageCheck", "_PageSchedule", "_PageCredits", "_PageLog"]
    static Subtitles := [
        "Status at a glance. F1 start  " Chr(0xB7) "  F2 pause / resume  " Chr(0xB7) "  F3 stop",
        "Selling rhythm, minigame mode and failsafes.",
        "Potions bought at the Fisher, and the optional Stella cauldron step.",
        "Which quests the board may accept.",
        "Mari and Jester want-lists. Items are found by name in the shop.",
        "Rare biomes, the potions used in them, and per-potion safety caps.",
        "Strange Controller, Biome Randomizer and Biome Selector, used in NORMAL when off cooldown.",
        "The obby for the Basic Blessing, and the Memory Match board.",
        "Discord webhooks and the events each one receives.",
        "Record the click points new features need.",
        "Private server, routes, intervals, recovery, alerts and hotkeys.",
        "Record, test and reset the walking routes.",
        "Wait in THE LIMBO for Eden instead of fishing.",
        "Medal clips of rare biomes and rare auras.",
        "Send fake events through the running macro (dry run only).",
        "Today, this run and the last 7 days.",
        "Limited-time game features. They leave the macro when the game removes them.",
        "One Discord message a day with what the macro did.",
        "Control the macro from Discord with your own bot.",
        "Check what the macro can see on your PC, and make a log zip for support.",
        "Start and stop by the clock, or stop after a number of hours.",
        "Who made " Brand.Name ".",
        "The newest 200 lines. Links and webhook URLs are always hidden."
    ]
    ; Sidebar hubs, each a tab strip of pages (every page is in exactly one).
    static Hubs := [
        {name: "Home", icon: "home", pages: ["Run", "Stats"]},
        {name: "Automate", icon: "bolt", pages: ["Fishing", "Craft", "Quests", "Merchants", "Biome items", "Obby & Memory", "Limbo"]},
        {name: "Limited", icon: "clock", pages: ["Hunting"]},
        {name: "Alerts", icon: "bell", pages: ["Biomes & Potions", "Webhooks", "Clips", "Summary", "Remote"]},
        {name: "Setup", icon: "gear", pages: ["Check", "Calibrate", "Tools", "Schedule", "Settings", "Dev tools"]},
        {name: "Log", icon: "list", pages: ["Log"]},
        {name: "About", icon: "info", pages: ["Credits"]}
    ]
    static TabLabels := Map("Craft", "Crafting", "Biomes & Potions", "Biomes", "Webhooks", "Discord", "Tools", "Routes", "Summary", "Daily summary", "Check", "Check & help")
    static MaxHooks := 8
    static Events := ["biome", "rare", "merchant", "quests", "craft", "errors", "startstop", "potions", "clips", "obby", "memorymatch", "sinister"]
    static EventCaps := ["Biome", "Rare", "Merch", "Quest", "Craft", "Error", "Stop", "Pot.", "Clip", "Obby", "Mem.", "Boss"]
    ; one column per event: 12 x 28 px end before the Test button (x 926);
    ; at 38 px the obby / memorymatch boxes (added later, without captions)
    ; sat on top of Test and X and took their clicks (review 2026-10-27).
    ; "Boss" = sinister: the GRAVEYARD boss message (MinionsTask)
    static EventPitch := 28
    static EventBoxDx := 6
    static LogPage := 23
    ; animation look
    static PulseDark := "B5772A"       ; darker gold the Running pill pulses to
    static StarC := "F7F1E8"
    ; [x, y, period ms]: header stars clear of the brand, credits banner
    ; (x 372..612, y 17..43), status pill and buttons (y 16..44); sidebar
    ; stars between the hub list (7 hubs, ends y 348) and the chip (y 622).
    static Stars := [[392, 3, 2300], [548, 45, 2700], [700, 3, 2000], [902, 45, 3100]
        , [34, 380, 2500], [140, 430, 2900], [70, 500, 2150], [150, 566, 2650]]
    static StatTiles := [["stat:loops", "LOOPS"], ["stat:fish", "FISH CAUGHT"], ["stat:biomes", "BIOMES SEEN"], ["stat:rare", "RARE BIOMES"]]
    static _wins := Map()              ; Dashboard window hwnds (WM_ACTIVATE -> Anim.Wake)
    static _actHooked := false

    static TabLabel(page) => Dashboard.TabLabels.Has(page) ? Dashboard.TabLabels[page] : page

    ; Index in Dashboard.Hubs of the hub holding `page`, 0 if none.
    static HubOf(page) {
        for i, h in Dashboard.Hubs {
            for p in h.pages {
                if (p = page)
                    return i
            }
        }
        return 0
    }

    ; Index in Dashboard.Pages, 0 if none.
    static PageIndex(name) {
        for i, p in Dashboard.Pages {
            if (p = name)
                return i
        }
        return 0
    }

    __New(cfg, callbacks := "") {
        this.cfg := cfg
        this._cb := (callbacks is Map) ? callbacks : Map()
        this._logBuf := UiLogBuffer(200)
        this._pages := []
        this._ctrlPage := Map()
        this._hidden := Map()
        this._ids := Map()
        this._binds := []
        this._active := 0
        this._hub := 0
        this._hubLast := Map()        ; hub index -> page index last opened there
        this._statusKey := ""
        this._shown := false
        this._dryChecks := []
        this._dryOff := []
        this._dryOn := []
        this._capturing := false
        this._pauseBtns := []
        ; animation state
        this._running := false        ; state is Running (pulse loop wanted)
        this._pulseLvl := -1          ; last pulse shade drawn (-1 = none)
        this._chipLive := false       ; sidebar chip is gold (dry run OFF)
        this._moonFrame := 0
        this._moonFrames := []        ; HBITMAPs (made in _Build)
        this._moonFreed := 0
        this._stars := []
        this._statTiles := Map()      ; id -> value Text
        this._statVals := Map()       ; id -> target number
        this._loopsN := 0             ; SetStatus' loops (Loops tile fallback)
        this._cover := ""             ; page-fade cover (child Gui)
        ; focus hooks (tests replace them)
        this._focusFn := () => DllCall("GetFocus", "Ptr")
        this._setFocusFn := (h) => DllCall("SetFocus", "Ptr", h)
        ; confirm hooks (tests replace them): -> true only when the user agrees
        this._confirm := (title, text) => Theme.Confirm(this._gui, title, text, "Unlock", "Keep locked")
        this._confirmDry := () => Theme.Confirm(this._gui, "Turn off dry run?"
            , "Unlocked potions will REALLY be used during rare biomes.`n`nLocked potions stay locked. You can turn dry run back on at any time."
            , "Turn off", "Keep dry run")
        ; a switch for a part still known to be buggy: a warning before it goes on
        this._confirmBuggy := (title, text) => Theme.Confirm(this._gui, title, text, "Turn on", "Keep off")
        this._confirmBig := (title, text) => Theme.Confirm(this._gui, title, text, "Use it", "Change it")
        this._bigWarned := ""
        this._Build()
        ; animations: gated on this window, switched by UI.animations (live)
        hwnd := this._gui.Hwnd
        Anim.gateFn := () => Dashboard._GateOpen(hwnd)
        c := cfg
        Anim.enabledFn := () => Dashboard._AnimOn(c)
        Dashboard._HookActivate(hwnd)
        for page in this._pages
            this._LoadPage(page)
        this._RefreshDry()
        this.SetStatus("Stopped", "", "", false, 0, 0)
        this.SelectPage(1)
    }

    ; Anim gate: the window is visible, not minimized and the foreground window.
    static _GateOpen(hwnd) {
        try return (DllCall("IsWindowVisible", "Ptr", hwnd) && !DllCall("IsIconic", "Ptr", hwnd)
            && DllCall("GetForegroundWindow", "Ptr") = hwnd) ? true : false
        return false
    }

    ; Anim switch: cfg UI.animations (default 1), read on every call.
    static _AnimOn(cfg) {
        try return String(cfg.Get("UI.animations", 1)) != "0"
        return true
    }

    static _HookActivate(hwnd) {
        Dashboard._wins[hwnd] := true
        if !Dashboard._actHooked {
            Dashboard._actHooked := true
            OnMessage(0x0006, ObjBindMethod(Dashboard, "_OnActivate"))     ; WM_ACTIVATE
            OnMessage(0x0005, ObjBindMethod(Dashboard, "_OnRestore"))      ; WM_SIZE
        }
    }

    ; WM_ACTIVATE (shown, restored, clicked back into): frozen loops resume.
    ; Woken again a moment later in case the foreground switch (or the
    ; restore from minimized) is not yet complete while the message is handled.
    static _OnActivate(wParam, lParam, msg, hwnd) {
        if ((wParam & 0xFFFF) && Dashboard._wins.Has(hwnd))
            Dashboard._Wake()
    }

    ; WM_SIZE SIZE_RESTORED on a Dashboard window: same as activation, plus
    ; one full repaint once restored (a page switched or a fade cover hidden
    ; while minimized can leave a list's frame painted over the list).
    static _OnRestore(wParam, lParam, msg, hwnd) {
        if (wParam = 0 && Dashboard._wins.Has(hwnd)) {
            Dashboard._Wake()
            SetTimer(() => DllCall("RedrawWindow", "Ptr", hwnd, "Ptr", 0, "Ptr", 0, "UInt", 0x0185), -40)
        }
    }

    static _Wake() {
        Anim.Wake()
        if (!Anim.running && Anim.Active())        ; gate not open yet: once more shortly
            SetTimer(Dashboard._wakeLater, -60)
    }
    static _wakeLater := (*) => Anim.Wake()

    Hwnd => this._gui.Hwnd

    Ctrl(id) => this._ids.Has(id) ? this._ids[id] : ""

    ActivePage => this._active ? Dashboard.Pages[this._active] : ""

    ActiveHub => this._hub

    ; Name of the page a control belongs to ("" for header / sidebar controls).
    PageOf(ctrl) => (IsObject(ctrl) && this._ctrlPage.Has(ctrl.Hwnd)) ? Dashboard.Pages[this._ctrlPage[ctrl.Hwnd]] : ""

    ; ---- public ---------------------------------------------------------------

    Show() {
        if !this._shown {
            this._gui.Show("w" Dashboard.W " h" Dashboard.H " Center")
            this._shown := true
        } else
            this._gui.Show()
        DllCall("SetFocus", "Ptr", this._gui.Hwnd)     ; no control starts focused
        if this._active {
            for c in this._pages[this._active].ctrls
                if (c.Type = "ListView" && c.Visible)
                    Theme.FitLastCol(c)
        }
        this._FlushLog()
        this._StartLoops()
        Anim.Wake()
    }

    Hide() {
        this._gui.Hide()
    }

    ; Destroys the window (tests; the app keeps its Dashboard): stops its
    ; animations, forgets the window for the wake hooks, frees the moon frames.
    Destroy() {
        for k in ["underline", "fade", "count", "pulse", "moon", "stars"]
            Anim.Stop(k)
        try Dashboard._wins.Delete(this._gui.Hwnd)
        try Theme.Forget(this._gui)
        try this._gui.Destroy()
        this._FreeMoon()
    }

    ; -> number of frames deleted (DeleteObject succeeded)
    _FreeMoon() {
        n := 0
        for h in this._moonFrames
            n += DllCall("DeleteObject", "Ptr", h) ? 1 : 0
        this._moonFrames := []
        this._moonFreed := n
        return n
    }

    ; Home stat tiles. Cheap when nothing changed (called every status tick).
    SetStats(stats) {
        g := (k) => (stats is Map && stats.Has(k)) ? stats[k] : 0
        vals := Map("stat:loops", (stats is Map && stats.Has("loops")) ? stats["loops"] : this._loopsN
            , "stat:fish", g("fishCaught"), "stat:biomes", g("biomes"), "stat:rare", g("rareBiomes"))
        for id, v in vals {
            v := IsNumber(v) ? Integer(v) : 0
            if (this._statVals.Has(id) && this._statVals[id] = v)
                continue
            this._statVals[id] := v
            if (this._active = 1 && !Anim.Has("count"))     ; a count-up reads the new target itself
                Theme.SetText(this._statTiles[id], Dashboard._Num(v))
        }
    }

    ; 1234567 -> "1,234,567"
    static _Num(n) {
        t := String(Integer(n)), out := ""
        neg := SubStr(t, 1, 1) = "-"
        if neg
            t := SubStr(t, 2)
        while (StrLen(t) > 3)
            out := "," SubStr(t, -3) out, t := SubStr(t, 1, StrLen(t) - 3)
        return (neg ? "-" : "") t out
    }

    ; Credits banner: SetModified(true) shows Credits.Banner() in the header.
    _modified := false
    Modified => this._modified
    SetModified(on) {
        this._modified := on ? true : false
        b := this._ids["credits.banner"]
        b.Text := Credits.Banner()
        b.Visible := this._modified
    }

    ; Live check: the credits name on the Credits page and the title's by-line
    ; must be unchanged. Shows the banner when not (never hides it); -> true if intact.
    LiveCheck() {
        c := this.Ctrl("credits.name")
        ok := IsObject(c) && c.Text == Credits.Name() && InStr(this._gui.Title, Credits.ByLine())
        if !ok
            this.SetModified(true)
        return ok ? true : false
    }

    SetStatus(state, task := "", biome := "", rare := false, uptimeMs := 0, loops := 0) {
        st := UiLogic.NormState(state)
        up := UiLogic.Uptime(uptimeMs)
        key := st "|" task "|" biome "|" (rare ? 1 : 0) "|" up "|" loops
        if (key == this._statusKey)
            return
        this._statusKey := key
        pl := (st = "Paused") ? "Resume" : "Pause"
        for b in this._pauseBtns {
            if (b.Text != pl)
                b.Text := pl
        }
        switch st {
            case "Running": bg := Theme.Accent, fg := Theme.Ink, vc := Theme.Accent
            case "Paused": bg := Theme.PanelC, fg := Theme.Text, vc := Theme.Text
            default: bg := Theme.OffBg, fg := Theme.Muted, vc := Theme.Muted
        }
        pill := Chr(0x25CF) "  " StrUpper(st)
        if (this._pill.Text != pill) {
            this._pill.Text := pill
            Theme.SetColors(this._pill, bg, fg)
            this._stState.Text := st
            Theme.SetColors(this._stState, Theme.CardBg, vc)
        }
        Theme.SetText(this._stTask, task = "" ? Chr(0x2014) : task)
        bText := biome = "" ? Chr(0x2014) : biome (rare ? "   " Chr(0x2726) " rare" : "")
        if (this._stBiome.Text != bText) {
            this._stBiome.Text := bText
            Theme.SetColors(this._stBiome, Theme.CardBg, rare ? Theme.Accent : Theme.Text)
        }
        Theme.SetText(this._stUp, up)
        Theme.SetText(this._stLoops, String(loops))
        this._loopsN := IsNumber(loops) ? Integer(loops) : 0
        run := (st = "Running")
        if (run != this._running) {
            this._running := run
            if run
                Anim.Loop("pulse", 1600, ObjBindMethod(this, "_PulseStep"))
            else {
                Anim.Stop("pulse")
                this._pulseLvl := -1
                this._PaintChip()          ; the pill got its colours above
            }
        }
    }

    Log(text) {
        line := SubStr(UiLogic.LogLine(text, this._Secrets()), 1, 400)
        this._logBuf.Push(line)
        if (this._active = 1 || this._active = Dashboard.LogPage)
            this._FlushLog()
    }

    LogText() => this._logBuf.Text()

    SelectPage(i) {
        if (i = this._active || i < 1 || i > this._pages.Length)
            return
        old := this._active
        ; the cover hides the swap, then fades out (only when it would animate)
        fade := old && Anim.enabledFn.Call() && Anim.gateFn.Call()
        if fade
            this._CoverShow()
        try {
            if old {
                this._FocusOff(old)                ; never leave focus on a hidden control
                for c in this._pages[old].ctrls
                    c.Visible := false
            }
            this._active := i
            h := Dashboard.HubOf(Dashboard.Pages[i])
            this._hubLast[h] := i
            if (h != this._hub)
                this._ShowHub(h)                       ; refreshes every dot
            else {
                this._RefreshDot(this._pages[old])     ; the tab left and the
                this._RefreshDot(this._pages[i])       ; one opened
            }
            this._PaintTabs()
            for c in this._pages[i].ctrls {
                c.Visible := !this._hidden.Has(c.Hwnd)
                if (c.Type = "ListView" && c.Visible)
                    Theme.FitLastCol(c)                ; scrollbar size is final once shown
            }
            if (i = 1 || i = Dashboard.LogPage)
                this._FlushLog()
            if (i = 1)
                this._CountUp()
            if (this._pages[i].HasProp("onShow") && IsObject(this._pages[i].onShow))
                try this._pages[i].onShow.Call()
            Theme.Repaint(this._gui)
        } catch Any as e {
            this._CoverHide()
            throw e
        }
        if fade
            Anim.Tween("fade", 150, ObjBindMethod(this, "_CoverStep"), ObjBindMethod(this, "_CoverHide"))
    }

    ; Focus on a control of page `old` (or a child of one) moves to the window.
    _FocusOff(old) {
        f := 0
        try f := this._focusFn.Call()
        top := this._gui.Hwnd
        while (f && f != top) {
            if this._ctrlPage.Has(f) {
                if (this._ctrlPage[f] = old)
                    this._Unfocus()
                return
            }
            f := DllCall("GetParent", "Ptr", f, "Ptr")
        }
    }

    _Unfocus() {
        this._setFocusFn.Call(this._gui.Hwnd)
    }

    ; Hub i on the tab last opened there (its first tab the first time).
    SelectHub(i) {
        if (i < 1 || i > Dashboard.Hubs.Length)
            return
        this.SelectPage(this._hubLast.Has(i) ? this._hubLast[i] : Dashboard.PageIndex(Dashboard.Hubs[i].pages[1]))
    }

    SavePage(name) {
        page := this._PageByName(name)
        note := ""
        ; page check BEFORE anything reaches cfg (a refused value must not
        ; become live in memory)
        if (page.HasProp("validate") && IsObject(page.validate)) {
            why := ""
            try why := page.validate.Call()
            catch Any as e
                why := e.Message
            if (why != "") {
                msg := UiLogic.Scrub(why, this._Secrets())
                this._SetPageStatus(page, "Not saved: " msg, true)
                this.Log("Settings: " name " not saved: " msg)
                this._RefreshDot(page)
                return false
            }
        }
        try {
            this._SaveBinds(page)
            if IsObject(page.save)
                note := page.save.Call()
            this.cfg.Save()
        } catch Any as e {
            msg := UiLogic.Scrub(e.Message, this._Secrets())
            this._SetPageStatus(page, "Not saved: " msg, true)
            this.Log("Settings: " name " not saved: " msg)
            this._RefreshDot(page)
            return false
        }
        page.dirty := false
        this._Snap(page)
        this._RefreshDot(page)
        this._SetPageStatus(page, "Saved " FormatTime(, "HH:mm:ss") (note ? "   " note : ""))
        this.Log("Settings: " name " saved")
        if (name = "Settings" && this._shown)
            this._StartLoops(true)         ; UI.animations takes effect now
        if this._cb.Has("saved")
            try this._cb["saved"].Call(name)
        return true
    }

    RevertPage(name) {
        page := this._PageByName(name)
        this._LoadPage(page)
        this._SetPageStatus(page, "Reverted to saved values")
    }

    ; ---- build ----------------------------------------------------------------

    _Build() {
        g := Theme.Window(Brand.Name " " Chr(0xB7) " " Credits.ByLine(), "-MaximizeBox")
        this._gui := g
        g.OnEvent("Close", (*) => this._OnClose())
        bg := Theme.AssetPath(Theme.BgImage)             ; the theme's darkened art: panels and text read on it
        if !FileExist(bg)
            bg := Theme.AssetPath("moontide_bg_dim.png")
        if !FileExist(bg)
            bg := Theme.AssetPath("moontide_bg.png")
        if FileExist(bg)
            g.Add("Picture", "x176 y60 w864 h620", bg)      ; first = painted under everything

        ; header: the moon logo cycles through assets\ui\moon_0..7.png, decoded
        ; once here (HBITMAPs owned by the Dashboard, freed in Destroy())
        this._moonFrames := []
        Loop 8 {
            f := Theme.AssetPath("ui\moon_" (A_Index - 1) ".png")
            h := 0
            if FileExist(f)
                try h := LoadPicture(f)
            if !h
                break
            this._moonFrames.Push(h)
        }
        if (this._moonFrames.Length = 8)
            this._moon := g.Add("Picture", "x18 y10 w40 h40 BackgroundTrans", "HBITMAP:*" this._moonFrames[1])
        else {
            this._FreeMoon()
            this._moon := Theme.Moon(g, 18, 10, 40)
        }
        Theme.Label(g, "x66 y5 w300 h36", Brand.Name, "brand", Theme.Bg)
        Theme.Label(g, "x68 y39 w300 h16", "Sol's RNG", "small", Theme.Bg)
        Theme.Rect(g, 0, 59, Dashboard.W, 1, Theme.PanelC)
        Theme.Font(g, "caps", Theme.Accent)
        this._ids["credits.banner"] := g.Add("Text", "x372 y17 w240 h26 +0x80 +0x200 Center Background" Theme.Bg, Credits.Banner())
        this._ids["credits.banner"].Visible := false
        Theme.Font(g, "caps")
        this._pill := g.Add("Text", "x618 y17 w132 h26 +0x80 +0x200 Center Background" Theme.OffBg, "")
        Theme.Button(g, "x764 y16 w80 h28", "Start", (*) => this._Fire("start"), "primary")
        this._PauseBtn(Theme.Button(g, "x852 y16 w80 h28", "Pause", (*) => this._Fire("pause")))
        Theme.Button(g, "x940 y16 w80 h28", "Stop", (*) => this._Fire("stop"))

        ; sidebar
        Theme.Rect(g, 0, 60, 176, 620, Theme.SideBg)
        Theme.Rect(g, 175, 60, 1, 620, Theme.PanelC)
        this._nav := []
        this._navBar := []
        for i, hub in Dashboard.Hubs {
            y := 74 + (i - 1) * 40
            this._navBar.Push(Theme.Rect(g, 0, y, 3, 34, Theme.SideBg))
            Theme.Font(g, "nav")
            c := g.Add("Text", "x12 y" y " w152 h34 +0x80 +0x100 +0x200 Background" Theme.SideBg, "   " hub.name)
            Theme.Clickable(c, ObjBindMethod(this, "_NavClick", i), ObjBindMethod(this, "_PaintNav", i))
            this._nav.Push(c)
            this._ids["hub:" hub.name] := c
        }
        Theme.Font(g, "caps")
        this._chip := g.Add("Text", "x14 y622 w148 h30 +0x80 +0x200 Center Background" Theme.OffBg, "")

        ; twinkling stars (header y < 59, sidebar x < 176), loop "stars"
        for i, s in Dashboard.Stars {
            bg := s[2] < 59 ? Theme.Bg : Theme.SideBg
            g.SetFont("s7 norm c" Dashboard._Blend(bg, Theme.Text, 0.56), "Segoe UI Symbol")
            c := g.Add("Text", "x" s[1] " y" s[2] " w12 h12 +0x80 Center Background" bg, Chr(0x2726))
            this._stars.Push({c: c, bg: bg, period: s[3], off: i * 397, lvl: 3})
            this._ids["star" i] := c
        }

        ; hub header: title, tab strip (one tab + dot per page, only the
        ; active hub's are shown), the underline under the active tab
        this._hubTitle := Theme.Label(g, "x204 y66 w600 h36", "", "title")
        this._ids["hubTitle"] := this._hubTitle
        this._tabs := []
        this._dots := []
        for hub in Dashboard.Hubs {
            x := 204
            for name in hub.pages {
                i := Dashboard.PageIndex(name)
                t := Theme.Label(g, "x" x " y104 h26 +0x100 +0x200", Dashboard.TabLabel(name), "nav")
                t.GetPos(, , &tw)
                Theme.Clickable(t, ObjBindMethod(this, "_TabClick", i), ObjBindMethod(this, "_PaintTab", i))
                dot := Theme.Label(g, "x" x + tw + 3 " y104 w10 h26 +0x200", Chr(0x2022), "body", "", Theme.Accent)
                t.Visible := false
                dot.Visible := false
                this._tabs.Length := Max(this._tabs.Length, i)
                this._dots.Length := Max(this._dots.Length, i)
                this._tabs[i] := t
                this._dots[i] := dot
                this._ids["tab:" name] := t
                this._ids["tabDot:" name] := dot
                x += tw + 28
            }
        }
        this._underline := Theme.Rect(g, 204, 130, 40, 2, Theme.Accent)
        this._underline.Visible := false
        this._ids["tabUnderline"] := this._underline

        ; pages
        for i, name in Dashboard.Pages {
            Theme.Sink := []
            page := {name: name, idx: i, ctrls: [], load: "", save: "", status: "", dirty: false}
            this._curPage := page
            this._ids["desc:" name] := Theme.Label(g, "x204 y132 w808 h16", Dashboard.Subtitles[i], "muted")
            m := Dashboard.Builders[i]
            this.%m%(page)
            page.ctrls := Theme.Sink
            Theme.Sink := ""
            for c in page.ctrls {
                c.Visible := false
                this._ctrlPage[c.Hwnd] := i
            }
            this._pages.Push(page)
        }
        this._curPage := ""
    }

    _SaveBar(page) {
        g := this._gui
        n := page.name
        page.status := Theme.Label(g, "x330 y634 w462 h20 Right", "", "muted")
        Theme.Button(g, "x804 y628 w100 h30", "Revert", (*) => this.RevertPage(n))
        Theme.Button(g, "x912 y628 w100 h30", "Save", (*) => this.SavePage(n), "primary")
    }

    _SetPageStatus(page, text, bad := false) {
        if !IsObject(page.status)
            return
        page.status.SetFont("c" (bad ? Theme.Accent : Theme.Muted))
        Theme.SetText(page.status, text)
        Theme.RepaintCtrl(page.status)
    }

    ; Solid panel on the page being built; a titled one is also
    ; Ctrl("panel:<page>:<title>"). help: text of a "?" at the title's right.
    _Panel(x, y, w, h, title := "", help := "") {
        parts := Theme.Panel(this._gui, x, y, w, h, title)
        if (title != "" && IsObject(this._curPage))
            this._ids["panel:" this._curPage.name ":" title] := parts[1]
        if (help != "")
            Theme.Help(this._gui, x + w - 28, y + 8, help)
        return parts
    }

    ; "?" right after a switch's label (made as wide as its text).
    _HelpAfter(chk, text) {
        chk._lbl.GetPos(&lx, &ly, &lw)
        return Theme.Help(this._gui, lx + lw + 8, ly + 2, text)
    }

    _PageByName(name) {
        for p in this._pages {
            if (p.name = name)
                return p
        }
        throw ValueError("Dashboard: no page '" name "'")
    }

    _LoadPage(page) {
        this._LoadBinds(page)
        if IsObject(page.load)
            page.load.Call()
        page.dirty := false
        this._RefreshDot(page)
    }

    ; ---- unsaved-edit dot -------------------------------------------------------

    ; The page changed something only Save keeps (list Add / Remove, ...).
    ; p: page object or name.
    _MarkDirty(p, *) {
        page := IsObject(p) ? p : this._PageByName(p)
        page.dirty := true
        this._RefreshDot(page)
    }

    ; true when the page has unsaved edits: marked dirty, or a bound control
    ; differs from the value it was loaded / saved with.
    _PageDirty(page) {
        if page.dirty
            return true
        for b in this._binds {
            if (b.page == page && String(b.ctrl.Value) !== b.loaded)
                return true
        }
        return false
    }

    ; Bound controls' current values become the "loaded" ones.
    _Snap(page) {
        for b in this._binds {
            if (b.page == page)
                b.loaded := String(b.ctrl.Value)
        }
    }

    ; Shows the page's tab dot while its hub is open and it has unsaved edits.
    _RefreshDot(page, *) {
        if (!IsObject(page) || page.idx > this._dots.Length)
            return
        dot := this._dots[page.idx]
        h := Dashboard.HubOf(page.name)
        want := (h = this._hub && Dashboard.Hubs[h].pages.Length > 1 && this._PageDirty(page)) ? true : false
        if (dot.Visible != want) {
            dot.Visible := want
            if !want
                Theme.RepaintCtrl(dot)
        }
    }

    ; ---- nav ------------------------------------------------------------------

    _NavClick(i, *) {
        this.SelectHub(i)
    }

    _TabClick(i, *) {
        this.SelectPage(i)
    }

    ; Hub h's header: title, its tabs (none for a one-page hub) and dots.
    _ShowHub(h) {
        old := this._hub
        this._hub := h
        multi := Dashboard.Hubs[h].pages.Length > 1
        for i, name in Dashboard.Pages {
            on := multi && Dashboard.HubOf(name) = h
            if (this._tabs[i].Visible != on)
                this._tabs[i].Visible := on
        }
        for page in this._pages
            this._RefreshDot(page)
        this._underline.Visible := multi
        Theme.SetText(this._hubTitle, Dashboard.Hubs[h].name)
        if old
            this._PaintNav(old, false)
        this._PaintNav(h, false)
    }

    ; Active tab gold, the underline (a single control) moved under it.
    _PaintTabs() {
        for name in Dashboard.Hubs[this._hub].pages
            this._PaintTab(Dashboard.PageIndex(name), false)
        if this._underline.Visible {
            this._tabs[this._active].GetPos(&tx, , &tw)
            this._underline.GetPos(&ux, , &uw)
            u := this._underline
            Anim.Tween("underline", 180, (p) => u.Move(Round(Anim.Lerp(ux, tx, p)), 130, Round(Anim.Lerp(uw, tw, p)), 2))
        }
    }

    ; ---- animations ---------------------------------------------------------------

    ; Moon, stars and (while Running) pulse loops. Existing loops are kept
    ; unless force (after a Settings save: UI.animations may have changed;
    ; when it is off every loop settles at once and is dropped).
    _StartLoops(force := false) {
        if (force || !Anim.Has("moon"))
            Anim.Loop("moon", 3200, ObjBindMethod(this, "_MoonStep"))
        if (force || !Anim.Has("stars"))
            Anim.Loop("stars", 1000, ObjBindMethod(this, "_StarStep"))
        if (this._running && (force || !Anim.Has("pulse")))
            Anim.Loop("pulse", 1600, ObjBindMethod(this, "_PulseStep"))
    }

    _MoonStep(phase) {
        f := Min(7, Max(0, Floor(phase * 8)))
        if (f = this._moonFrame || this._moonFrames.Length < 8)
            return
        this._moonFrame := f
        try this._moon.Value := "HBITMAP:*" this._moonFrames[f + 1]
    }

    ; Each star blinks on its own period (from the clock, not the loop phase);
    ; with animations off they rest at a mid brightness.
    _StarStep(phase) {
        on := Anim.enabledFn.Call()
        now := Anim.nowFn.Call()
        for s in this._stars {
            k := on ? (1 - Cos(2 * 3.14159265 * Mod(now + s.off, s.period) / s.period)) / 2 : 0.5
            lvl := Round(k * 6)
            if (lvl = s.lvl)
                continue
            s.lvl := lvl
            try {
                s.c.SetFont("c" Dashboard._Blend(s.bg, Theme.Text, 0.12 + 0.88 * lvl / 6))
                s.c.Redraw()
            }
        }
    }

    ; Running: the header pill (and the sidebar chip while it is gold)
    ; between Theme.Accent and PulseDark.
    _PulseStep(phase) {
        lvl := Round((1 - Cos(2 * 3.14159265 * phase)) / 2 * 10)
        if (lvl = this._pulseLvl)
            return
        this._pulseLvl := lvl
        col := Dashboard._Blend(Theme.Accent, Theme.Pulse, lvl / 10)
        try {
            Theme.SetColors(this._pill, col, Theme.Ink)
            if this._chipLive
                Theme.SetColors(this._chip, col, Theme.Ink)
        }
    }

    ; "RRGGBB" a..b at t (0..1)
    static _Blend(a, b, t) {
        va := Integer("0x" a), vb := Integer("0x" b), out := ""
        for sh in [16, 8, 0] {
            x := (va >> sh) & 0xFF, y := (vb >> sh) & 0xFF
            out .= Format("{:02X}", Round(x + (y - x) * t))
        }
        return out
    }

    ; Home opened: every stat tile counts up from 0 to its value.
    _CountUp() {
        tiles := this._statTiles, vals := this._statVals
        Anim.Tween("count", 600, (p) => Dashboard._CountStep(tiles, vals, p))
    }

    static _CountStep(tiles, vals, p) {
        for id, c in tiles
            Theme.SetText(c, Dashboard._Num(Round((vals.Has(id) ? vals[id] : 0) * p)))
    }

    ; Page-fade cover: a layered child window in Theme.Bg over the content area,
    ; made on first use. Clicks pass through it (WS_EX_TRANSPARENT).
    _CoverShow() {
        Anim.Stop("fade")
        try {
            if !IsObject(this._cover) {
                c := Gui("-Caption +E0x80020 +Parent" this._gui.Hwnd)    ; WS_EX_LAYERED | WS_EX_TRANSPARENT
                c.BackColor := Theme.Bg
                c.MarginX := 0, c.MarginY := 0
                this._cover := c
            }
            this._CoverAlpha(255)
            this._cover.Show("x176 y150 w864 h470 NoActivate")
            ; HWND_TOP among the window's controls; SWP_NOMOVE|NOSIZE|NOACTIVATE|SHOWWINDOW
            DllCall("SetWindowPos", "Ptr", this._cover.Hwnd, "Ptr", 0, "Int", 0, "Int", 0, "Int", 0, "Int", 0, "UInt", 0x53)
        } catch
            this._CoverHide()
    }

    _CoverAlpha(a) {
        DllCall("SetLayeredWindowAttributes", "Ptr", this._cover.Hwnd, "UInt", 0, "UChar", a, "UInt", 2)   ; LWA_ALPHA
    }

    _CoverStep(p) {
        if (p >= 1)
            return this._CoverHide()
        try this._CoverAlpha(Round(255 * (1 - p)))
        catch
            this._CoverHide()
    }

    ; Hides the cover; the content under it is repainted in one pass (controls
    ; on the page overlap their frames, which must not paint over them).
    _CoverHide(*) {
        if !this.CoverShown()
            return
        try this._cover.Hide()
        try Theme.Repaint(this._gui)
    }

    ; true while the page-fade cover is shown (tests).
    CoverShown() => IsObject(this._cover) && (DllCall("GetWindowLong", "Ptr", this._cover.Hwnd, "Int", -16) & 0x10000000) != 0

    _PaintTab(i, hot, *) {
        c := this._tabs[i]
        c.SetFont("c" (i = this._active ? Theme.Accent : hot ? Theme.Text : Theme.Muted))
        Theme.RepaintCtrl(c)
    }

    _PaintNav(i, hot, *) {
        c := this._nav[i]
        if (i = this._hub) {
            Theme.SetColors(c, Theme.PanelC, Theme.Accent)
            Theme.SetColors(this._navBar[i], Theme.Accent, Theme.Accent)
        } else {
            Theme.SetColors(c, hot ? "0F2242" : Theme.SideBg, hot ? Theme.Text : Theme.Muted)
            Theme.SetColors(this._navBar[i], Theme.SideBg, Theme.SideBg)
        }
    }

    ; ---- generic bindings -----------------------------------------------------

    _Bind(kind, key, def, ctrl) {
        page := this._curPage
        this._binds.Push({page: page, kind: kind, key: key, def: def, ctrl: ctrl, loaded: ""})
        this._ids[key] := ctrl
        ; user edits re-check the tab dot (programmatic sets fire no event);
        ; a switch keeps its own callback, the dot check runs after it
        if (ctrl is ThemeCheck) {
            dot := ObjBindMethod(this, "_RefreshDot", page)
            own := ctrl._fn
            ctrl._fn := IsObject(own) ? ((c) => (own.Call(c), dot.Call())) : dot
        } else
            ctrl.OnEvent("Change", ObjBindMethod(this, "_RefreshDot", page))
    }

    _IntField(x, y, label, key, def, unit := "", lw := 170, min := "") {
        g := this._gui
        Theme.Label(g, "x" x " y" y + 4 " w" lw - 8 " h20", label)
        e := Theme.Edit(g, x + lw, y, 72, 28, "", "Number")
        if (unit != "")
            Theme.Label(g, "x" x + lw + 80 " y" y + 5 " w70 h20", unit, "muted")
        this._Bind("int", key, def, e)
        if (min != "")
            this._binds[this._binds.Length].min := min
        return e
    }

    _StrField(x, y, label, key, def, w := 120, lw := 170) {
        g := this._gui
        Theme.Label(g, "x" x " y" y + 4 " w" lw - 8 " h20", label)
        e := Theme.Edit(g, x + lw, y, w, 28)
        this._Bind("str", key, def, e)
        return e
    }

    ; Pill switch bound to key. help: a "?" after the label.
    ; Turning the switch ON asks first (title / text); "Keep off" leaves it off.
    _WarnOn(c, title, text) {
        c._fn := (ctl) => (ctl.Value && this._confirmBuggy.Call(title, text) != true) ? (ctl.Value := 0) : 0
        return c
    }

    ; A big combat aura (Minions.bigAuras, default Equinox, Luminosity) blocks
    ; the view: asked once per name typed. "Change it" puts the saved aura
    ; back (Eden when that one is big too).
    ; (MinionsTask.IsBig, like MemoryMatchTask above: the App loads every task)
    _BigAuraCheck(ctl) {
        v := Trim(ctl.Value)
        if (v = "" || v = this._bigWarned || !MinionsTask.IsBig(this.cfg, v))
            return
        this._bigWarned := v
        if (this._confirmBig.Call("Big auras fail more", v " is a big aura: it covers the view, so hunts miss targets and fail much more often. "
            . "The camera zooms all the way out for it. Smaller auras (like Eden) work best.") = true)
            return
        was := Trim(this.cfg.Get("Minions.aura", "Eden"))
        ctl.Value := (was = "" || MinionsTask.IsBig(this.cfg, was)) ? "Eden" : was
    }

    _BoolField(x, y, label, key, def, w := 310, help := "") {
        c := Theme.Check(this._gui, x, y, label, 0, "", "pill", help != "" ? -1 : w)
        this._Bind("bool", key, def, c)
        if (help != "")
            this._HelpAfter(c, help)
        return c
    }

    _LoadBinds(page) {
        for b in this._binds {
            if (b.page !== page)
                continue
            v := this.cfg.Get(b.key, b.def)
            if (b.kind = "bool")
                b.ctrl.Value := v ? 1 : 0
            else if (b.kind = "rarity")
                b.ctrl.Value := Auras.Format(Auras.MinRarity(this.cfg))
            else
                b.ctrl.Value := String(v)
        }
        this._Snap(page)
    }

    _SaveBinds(page) {
        for b in this._binds {
            if (b.page !== page)
                continue
            switch b.kind {
                case "int":
                    v := UiLogic.UInt(b.ctrl.Value, b.def)
                    if (b.HasProp("min") && v < b.min)
                        v := b.min
                    b.ctrl.Value := String(v)
                    this.cfg.Set(b.key, v)
                case "str":
                    this.cfg.Set(b.key, Trim(b.ctrl.Value))
                case "rarity":             ; "100m" / "1b" / "1,000,000" -> integer
                    v := Auras.ParseRarity(b.ctrl.Value)
                    if (v = "")
                        v := Auras.MinRarity(this.cfg)
                    this.cfg.Set(b.key, v)
                    b.ctrl.Value := Auras.Format(v)
                default:
                    this.cfg.Set(b.key, b.ctrl.Value ? 1 : 0)
            }
        }
    }

    _SetHidden(ctrl, hide) {
        if hide
            this._hidden[ctrl.Hwnd] := true
        else if this._hidden.Has(ctrl.Hwnd)
            this._hidden.Delete(ctrl.Hwnd)
        onPage := !this._ctrlPage.Has(ctrl.Hwnd) || this._ctrlPage[ctrl.Hwnd] = this._active
        want := !hide && onPage
        if (ctrl.Visible != want) {
            ctrl.Visible := want
            if !want
                Theme.RepaintCtrl(ctrl)
        }
    }

    _PauseBtn(btn) {
        this._pauseBtns.Push(btn)
        this._ids["pauseBtn" this._pauseBtns.Length] := btn
        return btn
    }

    _Fire(name, args*) {
        if !this._cb.Has(name)
            return ""
        try
            return this._cb[name].Call(args*)
        catch Any as e
            this.Log("UI: " name " failed: " e.Message)
        return ""
    }

    _OnClose() {
        if this._cb.Has("close") {
            this._Fire("close")
            return true
        }
        this._gui.Hide()
        return true
    }

    _Secrets() {
        arr := []
        try {
            for h in this.cfg.Webhooks()
                arr.Push(h["url"])
            link := this.cfg.Get("General.privateServer", "")
            arr.Push(link)
            arr.Push(this.cfg.Get("Remote.token", ""))
            ; the share / link code alone is as secret as the whole link
            pos := 1
            while (pos := RegExMatch(link, "i)(?:code|privateServerLinkCode|linkCode)=([^&\s]+)", &m, pos)) {
                arr.Push(m[1])
                pos += m.Len
            }
        }
        return arr
    }

    _FlushLog() {
        if (this._active = 1) {
            this._recent.Value := this._logBuf.Tail(40)
            Dashboard._ScrollEnd(this._recent)
        } else if (this._active = Dashboard.LogPage) {
            this._logEdit.Value := this._logBuf.Text()
            Dashboard._ScrollEnd(this._logEdit)
            Theme.SetText(this._logCount, this._logBuf.Count() " / 200 lines")
        }
    }

    static _ScrollEnd(edit) {
        DllCall("SendMessage", "Ptr", edit.Hwnd, "UInt", 0x115, "Ptr", 7, "Ptr", 0)   ; WM_VSCROLL SB_BOTTOM
    }

    ; ---- dry run --------------------------------------------------------------

    _DryCheck(x, y) {
        c := Theme.Check(this._gui, x, y, "Dry run", 1, ObjBindMethod(this, "_DryFlip"), "pill", 90)
        this._dryChecks.Push(c)
        this._ids["dryRun" this._dryChecks.Length] := c
        return c
    }

    _DryFlip(chk) {
        ; turning OFF needs a yes from _confirmDry; turning ON never asks
        if (!chk.Value && this._confirmDry.Call() != true) {
            this._RefreshDry()
            return
        }
        this._ApplyDry(chk.Value)
    }

    ; true when the "dry run is OFF" banner is set to show (tests).
    DryBannerShown() => this._dryOff.Length && !this._hidden.Has(this._dryOff[1].Hwnd)

    _ApplyDry(v) {
        this.cfg.Set("General.dryRun", v ? 1 : 0)
        try this.cfg.Save()
        catch Any as e
            this.Log("Settings: dry run not saved: " e.Message)
        this._RefreshDry()
        this.Log(v ? "Dry run ON: potion checks only, nothing is clicked" : "Dry run OFF: unlocked potions will be used")
    }

    ; preview: render as if dryRun were `preview` (0/1) without touching cfg
    ; (harness screenshots only).
    _RefreshDry(preview := "") {
        v := (preview != "") ? (preview ? 1 : 0) : (this.cfg.Get("General.dryRun", 1) ? 1 : 0)
        for c in this._dryChecks
            c.Value := v
        for c in this._dryOff
            this._SetHidden(c, v)
        for c in this._dryOn
            this._SetHidden(c, !v)
        this._chipLive := !v
        this._chip.Text := v ? "DRY RUN  " Chr(0xB7) "  SAFE" : "LIVE  " Chr(0xB7) "  POTIONS ARMED"
        this._pulseLvl := -1           ; a running pulse repaints the chip next step
        this._PaintChip()
    }

    ; Sidebar chip at rest: gold while live, grey in dry run.
    _PaintChip() {
        if this._chipLive
            Theme.SetColors(this._chip, Theme.Accent, Theme.Ink)
        else
            Theme.SetColors(this._chip, Theme.OffBg, Theme.Muted)
    }

    ; ---- page: Run --------------------------------------------------------------

    _PageRun(p) {
        g := this._gui
        this._Panel(204, 152, 396, 200, "Status")
        Theme.Label(g, "x220 y180 w200 h16", "STATE", "caps", Theme.CardBg)
        this._stState := Theme.Label(g, "x220 y196 w364 h32", "Stopped", "big", Theme.CardBg, Theme.Muted)
        Theme.Rect(g, 220, 234, 364, 1, Theme.PanelC)
        Theme.Label(g, "x220 y246 w170 h16", "TASK", "caps", Theme.CardBg)
        this._stTask := Theme.Label(g, "x220 y264 w176 h24", "", "value", Theme.CardBg)
        Theme.Label(g, "x404 y246 w170 h16", "UPTIME", "caps", Theme.CardBg)
        this._stUp := Theme.Label(g, "x404 y264 w180 h24", "", "value", Theme.CardBg)
        Theme.Label(g, "x220 y298 w170 h16", "BIOME", "caps", Theme.CardBg)
        this._stBiome := Theme.Label(g, "x220 y316 w176 h24", "", "value", Theme.CardBg)
        Theme.Label(g, "x404 y298 w170 h16", "LOOPS", "caps", Theme.CardBg)
        this._stLoops := Theme.Label(g, "x404 y316 w180 h24", "", "value", Theme.CardBg)

        Theme.Button(g, "x204 y368 w124 h36", "Start", (*) => this._Fire("start"), "primary")
        this._PauseBtn(Theme.Button(g, "x340 y368 w124 h36", "Pause", (*) => this._Fire("pause")))
        Theme.Button(g, "x476 y368 w124 h36", "Stop", (*) => this._Fire("stop"))

        this._Panel(204, 420, 396, 196, "Potion safety")
        this._DryCheck(220, 452)
        this._dryOn.Push(Theme.Label(g, "x220 y484 w364 h40", "On: every potion check runs and is logged, nothing is clicked.", "muted"))
        this._dryOff.Push(Theme.Label(g, "x220 y484 w364 h40", "Dry run is OFF: unlocked potions will really be used in rare biomes.", "body", "", Theme.Accent))
        Theme.Label(g, "x220 y576 w364 h20", "F3 stops everything, including potion use, at once.", "muted")

        ; this session's counters (SetStats); they count up when Home opens
        this._Panel(616, 152, 396, 108, "Stats")
        for i, t in Dashboard.StatTiles {
            x := 632 + (i - 1) * 93
            Theme.Rect(g, x, 182, 85, 62, Theme.FieldBg)
            Theme.Label(g, "x" x " y188 w85 h16 Center", t[2], "caps", Theme.FieldBg)
            c := Theme.Label(g, "x" x " y206 w85 h30 Center", "0", "big", Theme.FieldBg, Theme.Accent)
            this._statTiles[t[1]] := c
            this._statVals[t[1]] := 0
            this._ids[t[1]] := c
        }

        ; Updates (lib\Updater.ahk): only when [Update] repo is set
        dy := 0
        if (Trim(this.cfg.Get("Update.repo", "")) != "") {
            dy := 96
            this._Panel(616, 276, 396, 88, "Updates")
            this._updMsg := Theme.Label(g, "x632 y306 w364 h18", "Moontide Macro v" Brand.Version, "muted")
            this._updCheck := Theme.Button(g, "x632 y328 w132 h28", "Check for updates", (*) => this._Fire("checkUpdate"))
            this._updInstall := Theme.Button(g, "x776 y328 w100 h28", "Install", (*) => this._Fire("installUpdate"), "primary")
            this._updLater := Theme.Button(g, "x888 y328 w100 h28", "Later", (*) => this.SetUpdate(""))
            this._SetHidden(this._updInstall, true)
            this._SetHidden(this._updLater, true)
        }
        this._Panel(616, 276 + dy, 396, 340 - dy, "Recent activity")
        this._recent := Theme.Edit(g, 632, 308 + dy, 364, 292 - dy, "", "Multi ReadOnly -WantReturn VScroll")
    }

    ; "Update available: vX.Y.Z - Install / Later" notice on Home (version "" = hide it).
    ; No-op when the Updates panel is not built (no [Update] repo).
    SetUpdate(version, note := "") {
        if !HasProp(this, "_updMsg")
            return
        on := (version != "")
        this._updMsg.Text := on ? "Update available: v" version : (note != "" ? note : "Moontide Macro v" Brand.Version)
        this._SetHidden(this._updInstall, !on)
        this._SetHidden(this._updLater, !on)
    }

    ; ---- page: Fishing ----------------------------------------------------------

    _PageFishing(p) {
        g := this._gui
        this._Panel(204, 152, 396, 116, "Selling")
        this._IntField(220, 186, "Sell every", "General.sellEvery", 15, "loops", 170, 1)
        this._BoolField(220, 228, "Sell all fish (otherwise selected only)", "General.sellAll", 1)
        this._Panel(204, 284, 396, 120, "Failsafes")
        ; 0 made every cast give up at once and walk to the shop (review)
        this._IntField(220, 318, "Fishing failsafe", "General.fishingFailsafeSec", 31, "seconds", , 5)
        this._IntField(220, 356, "Pathing failsafe", "General.pathingFailsafeSec", 61, "seconds", , 10)
        this._Panel(616, 152, 396, 116, "Minigame")
        this._BoolField(632, 188, "Advanced mode (track bar width)", "General.advancedFishing", 0)
        this._IntField(632, 222, "Advanced threshold", "General.advancedThreshold", 20, "px")
        this._Panel(616, 284, 396, 120, "Fishing", "Click spots, colours and timings come from data\coords.json (2560x1440). "
            . "The VIP route switch is under Setup > Settings.")
        this._BoolField(632, 318, "Fish when nothing else is due", "General.fishing", 1)
        Theme.Label(g, "x632 y348 w364 h40", "Off = only the quest board, craft, merchants and rare-biome potions run.", "muted")
        this._SaveBar(p)
    }

    ; ---- page: Limbo --------------------------------------------------------------

    _PageLimbo(p) {
        g := this._gui
        this._Panel(204, 152, 808, 112, "Limbo (Eden)", "On: fishing, selling, crafting, quests, merchants and biome items stop; biome webhooks, "
            . "clips and rare-biome potions stay on. Uses your Portable Crack, turns the camera top-down, walks limbo_eden (Setup > Routes), "
            . "presses E by Eden's spot and clicks Contract with it (needs a Void Heart and the Darklight Core, Orb and Shard). "
            . "A rare biome: back to Sol's Island (rejoin), into Limbo again after it.")
        this._BoolField(220, 188, "Wait in Limbo for Eden instead of fishing", "Limbo.enabled", 0, 420)
        Theme.Label(g, "x220 y222 w776 h20", "Needs a Void Heart and the Darklight Core, Orb and Shard.", "muted")
        this._SaveBar(p)
    }

    ; ---- page: Craft ------------------------------------------------------------

    ; Shop rows and recipes come from lib\GameLists.ahk (what the game sells / crafts).
    _PageCraft(p) {
        g := this._gui
        this._Panel(204, 152, 396, 100, "Auto-craft")
        this._BoolField(220, 186, "Craft cycle", "Craft.enabled", 1)
        this._BoolField(220, 216, "Stella cauldron step", "Craft.cauldron", 0)
        this._Panel(616, 152, 396, 100, "Stella's cauldron recipe")
        items := ["(none)"]
        for n in GameLists.Recipes
            items.Push(n)
        this._craftTarget := Theme.Dropdown(g, 632, 184, 260, items)
        this._craftTarget.OnEvent("Change", ObjBindMethod(this, "_MarkDirty", p))
        this._ids["Craft.craftTarget"] := this._craftTarget
        Theme.Label(g, "x632 y218 w364 h20", "Typed into the cauldron search, first result is used.", "muted")

        names := GameLists.Shop
        this._Panel(204, 268, 808, 348, "Buy at the Fisher shop"
            , "Bought on start and after each 'Potion Crafted' notification (at most every [Craft] minIntervalMin minutes, default 10).")
        this._craftRows := []
        Loop Min(names.Length, 16) {
            i := A_Index
            col := (i - 1) // 8, row := Mod(i - 1, 8)
            x := 220 + col * 412, y := 298 + row * 38
            chk := Theme.Check(g, x, y + 4, names[i], 0, ObjBindMethod(this, "_MarkDirty", p), "pill", 200)
            qty := Theme.Edit(g, x + 262, y, 56, 28, "1", "Number")
            qty.OnEvent("Change", ObjBindMethod(this, "_MarkDirty", p))
            Theme.Label(g, "x" x + 324 " y" y + 5 " w30 h20", "qty", "muted")
            this._craftRows.Push({name: names[i], chk: chk, qty: qty})
            this._ids["craft:" names[i]] := chk
            this._ids["craftqty:" names[i]] := qty
        }
        p.load := ObjBindMethod(this, "_CraftLoad")
        p.save := ObjBindMethod(this, "_CraftSave")
        this._SaveBar(p)
    }

    _CraftLoad() {
        sel := Map()
        sel.CaseSense := "Off"
        for n in UiLogic.CsvToArray(this.cfg.Get("Craft.potions", ""))
            sel[n] := true
        for r in this._craftRows {
            r.chk.Value := sel.Has(r.name)
            r.qty.Value := String(this.cfg.Get(Dashboard.CraftQtyKey(r.name), this.cfg.Get("Craft.qty", 1)))
        }
        cur := this.cfg.Get("Craft.craftTarget", "")
        idx := 1
        for i, n in GameLists.Recipes {
            if (n = cur)
                idx := i + 1
        }
        this._craftTarget.Choose(idx)
    }

    ; "Craft.qty_<id>" exactly as lib\tasks\Craft.ahk (CraftTask._Qty) reads it.
    static CraftQtyKey(name) => "Craft.qty_" SubStr(Calibrate.PotionId(name), StrLen(Calibrate.PotionPrefix) + 1)

    _CraftSave() {
        list := []
        for r in this._craftRows {
            if r.chk.Value
                list.Push(r.name)
            q := Max(1, Min(999, UiLogic.UInt(r.qty.Value, 1)))    ; CraftTask.MaxQty range 1..999
            r.qty.Value := String(q)
            this.cfg.Set(Dashboard.CraftQtyKey(r.name), q)
        }
        this.cfg.Set("Craft.potions", UiLogic.ArrayToCsv(list))
        t := this._craftTarget.Text
        this.cfg.Set("Craft.craftTarget", (t = "(none)") ? "" : t)
        return ""
    }

    ; ---- page: Quests -----------------------------------------------------------

    _PageQuests(p) {
        g := this._gui
        this._Panel(204, 152, 456, 464, "Quest list")
        this._BoolField(220, 184, "Quest board", "quests.enabled", 1)
        this._tv := Theme.TreeView(g, 220, 218, 424, 382, "Checked")
        this._tv.OnEvent("ItemCheck", ObjBindMethod(this, "_QuestCheck"))
        this._ids["questTree"] := this._tv
        this._Panel(676, 152, 336, 92, "How it works"
            , "Every interval the macro reads the board with OCR and matches each quest to this list.`n`n"
            . "Ticked quests are accepted. Unticked ones are skipped (left on the board). "
            . "Ticking a type ticks all of its quests.`n`nThe interval is under Setup > Settings.")
        Theme.Button(g, "x692 y186 w148 h30", "Tick all", (*) => this._QuestAll(true))
        Theme.Button(g, "x848 y186 w148 h30", "Untick all", (*) => this._QuestAll(false))
        this._Panel(676, 260, 336, 100, "Dismiss")
        this._BoolField(692, 294, "Dismiss unticked quests", "quests.dismissDisabled", 0, , "WARNING: Dismiss abandons the quest and its progress. "
            . "Off (default): unticked quests are only skipped, never abandoned.")
        Theme.Label(g, "x692 y324 w304 h20", "Abandons the quest and its progress.", "muted")
        p.load := ObjBindMethod(this, "_QuestLoad")
        p.save := ObjBindMethod(this, "_QuestSave")
        this._SaveBar(p)
    }

    _QuestLoad() {
        tv := this._tv
        tv.Opt("-Redraw")
        tv.Delete()
        types := []
        try types := this.cfg.Data("quests")["types"]
        for t in types {
            tp := tv.Add(t["name"], 0, (t.Has("enabled") && t["enabled"]) ? "Check Expand" : "Expand")
            if (t.Has("quests") && t["quests"] is Array) {
                for q in t["quests"]
                    tv.Add(q["name"], tp, (q.Has("enabled") && q["enabled"]) ? "Check" : "")
            }
        }
        tv.Opt("+Redraw")
    }

    _QuestCheck(tv, item, checked) {
        this._MarkDirty("Quests")
        if tv.GetParent(item)
            return
        ch := tv.GetChild(item)
        while ch {
            tv.Modify(ch, checked ? "Check" : "-Check")
            ch := tv.GetNext(ch)
        }
    }

    _QuestAll(on) {
        tv := this._tv
        item := 0
        while (item := tv.GetNext(item, "Full"))
            tv.Modify(item, on ? "Check" : "-Check")
        this._MarkDirty("Quests")
    }

    _QuestSave() {
        tv := this._tv
        live := this.cfg.Data("quests")
        if !(live.Has("types") && live["types"] is Array)
            return "quests.json has no types: nothing saved"
        work := []
        item := tv.GetChild(0)
        while item {
            qs := []
            ch := tv.GetChild(item)
            while ch {
                qs.Push(Map("name", tv.GetText(ch), "enabled", tv.Get(ch, "Checked") ? 1 : 0))
                ch := tv.GetNext(ch)
            }
            work.Push(Map("name", tv.GetText(item), "enabled", tv.Get(item, "Checked") ? 1 : 0, "qs", qs))
            item := tv.GetNext(item)
        }
        UiLogic.MergeByKey(live["types"], work, ["enabled"])
        for w in work {
            for lt in live["types"] {
                if (lt["name"] = w["name"] && lt.Has("quests") && lt["quests"] is Array)
                    UiLogic.MergeByKey(lt["quests"], w["qs"], ["enabled"])
            }
        }
        this.cfg.SaveData("quests")
        return ""
    }

    ; ---- page: Merchants --------------------------------------------------------

    _PageMerchants(p) {
        g := this._gui
        widths := [310, "54 Center"]
        this._mlv := Map()
        this._mEmpty := Map()
        for who in ["Mari", "Jester"] {
            x := (who = "Mari") ? 204 : 616
            this._Panel(x, 152, 396, 248, who)
            Theme.ListHeader(g, x + 16, 180, widths, ["Item", "Qty"])
            lv := Theme.ListView(g, x + 16, 198, 364, 186, ["Item", "Qty"], widths)
            lv.OnEvent("ItemSelect", ObjBindMethod(this, "_MerchSelect", who))
            this._mlv[who] := lv
            this._ids["merch:" who] := lv
            this._mEmpty[who] := Theme.EmptyHint(g, lv, "Add what " who " should buy")
            this._ids["merch.empty:" who] := this._mEmpty[who]
        }
        this._Panel(204, 416, 396, 200, "Edit item")
        ; which list Add / Update / Remove work on: a two-option segmented choice
        this._mWho := Theme.Segmented(g, 220, 444, ["Mari", "Jester"], 1, ObjBindMethod(this, "_MerchWho"))
        for who, c in this._mWho
            this._ids["merch.who:" who] := c
        Theme.Label(g, "x220 y482 w32 h16", "ITEM", "caps")
        Theme.Help(g, 256, 482, "Type the item's name as the shop shows it (e.g. Lucky Potion). The macro finds it in the shop's tabs; what the merchant sells changes every visit.")
        Theme.Label(g, "x468 y482 w40 h16", "QTY", "caps")
        this._mName := Theme.Edit(g, 220, 500, 240, 28)
        this._mQty := Theme.Edit(g, 468, 500, 60, 28, "1", "Number")
        this._ids["merch.name"] := this._mName, this._ids["merch.qty"] := this._mQty
        Theme.Button(g, "x220 y540 w100 h30", "Add", (*) => this.MerchAdd(), "primary")
        Theme.Button(g, "x328 y540 w100 h30", "Update", (*) => this._MerchUpdate())
        Theme.Button(g, "x436 y540 w100 h30", "Remove", (*) => this._MerchRemove())
        this._mStatus := Theme.Label(g, "x220 y580 w364 h28", "", "muted")
        this._ids["merch.status"] := this._mStatus
        this._Panel(616, 416, 396, 200, "Buying")
        this._BoolField(632, 450, "Merchant buying", "merchant.enabled", 1)
        Theme.Label(g, "x632 y480 w364 h40", "Buys what is on these lists when Mari or Jester visits.", "muted")
        p.load := ObjBindMethod(this, "_MerchLoad")
        p.save := ObjBindMethod(this, "_MerchSave")
        this._SaveBar(p)
    }

    _MerchWho(who, *) {
        for k, c in this._mWho
            c.Value := (k = who)
    }

    _CurWho() => this._mWho["Jester"].Value ? "Jester" : "Mari"

    _MerchLoad() {
        d := this.cfg.Data("merchants")
        this._merch := Map()
        for who in ["Mari", "Jester"] {
            arr := []
            src := (d.Has(who) && d[who] is Array) ? d[who] : []
            for it in src {
                if (it is Map && it.Has("name"))
                    arr.Push(UiLogic.Copy(it))
                else if !IsObject(it) && Trim(String(it)) != ""
                    arr.Push(Map("name", Trim(String(it)), "qty", 1))
            }
            this._merch[who] := arr
            this._MerchFill(who)
        }
    }

    _MerchFill(who) {
        lv := this._mlv[who]
        lv.Delete()
        for it in this._merch[who]
            lv.Add(, it["name"], it.Has("qty") ? it["qty"] : 1)
        ; an empty list shows its hint instead
        empty := this._merch[who].Length = 0
        this._SetHidden(lv, empty)
        this._SetHidden(this._mEmpty[who], !empty)
        Theme.FitLastCol(lv)                    ; after showing: final scrollbar
    }

    _MerchSelect(who, lv, item, selected) {
        if (!selected || item < 1 || item > this._merch[who].Length)
            return
        this._MerchWho(who)
        it := this._merch[who][item]
        this._mName.Value := it["name"]
        this._mQty.Value := String(it.Has("qty") ? it["qty"] : 1)
    }

    ; Item from the edit boxes, its name title-cased ("gear b" -> "Gear B").
    _MerchItemFromEdits() {
        name := UiLogic.TitleCase(Trim(this._mName.Value))
        if (name = "")
            return ""
        this._mName.Value := name
        return Map("name", name, "qty", Max(1, UiLogic.UInt(this._mQty.Value, 1)))
    }

    MerchAdd() {
        it := this._MerchItemFromEdits()
        if !IsObject(it)
            return Theme.SetText(this._mStatus, "Type an item name first.")
        who := this._CurWho()
        this._merch[who].Push(it)
        this._MerchFill(who)
        this._MarkDirty("Merchants")
        Theme.SetText(this._mStatus, "Added to " who ". Save to keep it.")
    }

    _MerchUpdate() {
        who := this._CurWho()
        row := this._mlv[who].GetNext(0)
        it := this._MerchItemFromEdits()
        if (!row || !IsObject(it))
            return Theme.SetText(this._mStatus, "Select a " who " row and fill in the item name.")
        this._merch[who][row] := it
        this._MerchFill(who)
        this._MarkDirty("Merchants")
        Theme.SetText(this._mStatus, "Updated. Save to keep it.")
    }

    _MerchRemove() {
        who := this._CurWho()
        row := this._mlv[who].GetNext(0)
        if !row
            return Theme.SetText(this._mStatus, "Select a " who " row first.")
        this._merch[who].RemoveAt(row)
        this._MerchFill(who)
        this._MarkDirty("Merchants")
        Theme.SetText(this._mStatus, "Removed. Save to keep it.")
    }

    _MerchSave() {
        live := this.cfg.Data("merchants")
        for who in ["Mari", "Jester"]
            live[who] := UiLogic.Copy(this._merch[who])
        this.cfg.SaveData("merchants")
        return ""
    }

    ; ---- page: Biomes & Potions -------------------------------------------------

    _PageBiomes(p) {
        g := this._gui
        this._Panel(204, 152, 808, 44)
        this._DryCheck(220, 164)
        this._dryOff.Push(Theme.Rect(g, 372, 160, 628, 28, Theme.Accent))
        this._dryOff.Push(Theme.Label(g, "x384 y164 w608 h20 +0x200"
            , Chr(0x26A0) "  DRY RUN IS OFF  " Chr(0x2014) "  unlocked potions WILL be used in rare biomes", "button", Theme.Accent, Theme.Ink))
        this._dryOn.Push(Theme.Label(g, "x380 y166 w616 h20", "Dry run is on: every potion check runs and is logged, nothing is clicked.", "muted"))

        ; biomes (left)
        this._Panel(204, 208, 396, 408, "Biomes")
        bw := [180, 64, 120]
        Theme.ListHeader(g, 220, 234, bw, ["Biome", "Rare", "Potions"])
        this._lvB := Theme.ListView(g, 220, 252, 364, 140, ["Biome", "Rare", "Potions"], bw, , ObjBindMethod(this, "_BiomeColor"))
        this._lvB.OnEvent("ItemSelect", ObjBindMethod(this, "_BiomeSelect"))
        this._ids["biomes"] := this._lvB
        this._bName := Theme.Label(g, "x220 y402 w220 h24", "Select a biome", "value")
        this._bRare := Theme.Check(g, 456, 404, "Rare", 0, ObjBindMethod(this, "_BiomeRareFlip"), "pill", 60)
        this._ids["biomeRare"] := this._bRare
        pw := [310, "54 Center"]
        Theme.ListHeader(g, 220, 436, pw, ["Potion used here", "Qty"])
        this._lvBP := Theme.ListView(g, 220, 454, 364, 88, ["Potion", "Qty"], pw)
        this._bpEmpty := Theme.EmptyHint(g, this._lvBP, "Select a biome above")
        ; biome lists name potions by potions.json id (the three "Godly
        ; Potion"s share a name): items show the id (+ desc), Add writes the id
        ch := this._PotionChoices()
        this._bpIds := ch.ids
        this._bpDdl := Theme.Dropdown(g, 220, 554, 190, ch.labels)
        this._bpQty := Theme.Edit(g, 416, 553, 48, 28, "1", "Number")
        Theme.Button(g, "x470 y553 w52 h28", "Add", (*) => this.BiomePotionAdd())
        Theme.Button(g, "x528 y553 w56 h28", "Remove", (*) => this._BiomePotionRemove())
        this._ids["bpDdl"] := this._bpDdl, this._ids["bpQty"] := this._bpQty

        ; potions (right)
        this._Panel(616, 208, 396, 408, "Potions")
        cw := [148, 76, 46, 46, 48]
        Theme.ListHeader(g, 632, 234, cw, ["Potion", "Status", "Biome", "Day", "Run"])
        this._lvP := Theme.ListView(g, 632, 252, 364, 140, ["Potion", "Status", "Biome", "Day", "Run"], cw, , ObjBindMethod(this, "_PotionColor"))
        this._lvP.OnEvent("ItemSelect", ObjBindMethod(this, "_PotionSelect"))
        this._ids["potions"] := this._lvP
        this._pName := Theme.Label(g, "x632 y402 w364 h24", "Select a potion", "value")
        for cap in [["PER BIOME", 632], ["PER DAY", 716], ["PER RUN", 800]]
            Theme.Label(g, "x" cap[2] " y436 w80 h16", cap[1], "caps")
        this._capB := Theme.Edit(g, 632, 454, 76, 28, "", "Number")
        this._capD := Theme.Edit(g, 716, 454, 76, 28, "", "Number")
        this._capR := Theme.Edit(g, 800, 454, 76, 28, "", "Number")
        this._ids["capBiome"] := this._capB, this._ids["capDay"] := this._capD, this._ids["capRun"] := this._capR
        Theme.Button(g, "x884 y454 w112 h28", "Apply caps", (*) => this._PotionCaps())
        this._btnUnlock := Theme.Button(g, "x632 y498 w180 h32", "Unlock" Chr(0x2026), (*) => this.UnlockSelected(), "primary")
        this._btnRelock := Theme.Button(g, "x632 y498 w180 h32", "Re-lock", (*) => this.RelockSelected())
        this._SetHidden(this._btnUnlock, true)
        this._SetHidden(this._btnRelock, true)
        Theme.Help(g, 822, 506, "Top-tier potions are locked by default. Unlock asks first and names the caps. "
            . "Unlock and re-lock are saved at once; caps and biome lists on Save.")
        p.load := ObjBindMethod(this, "_BiomesLoad")
        p.save := ObjBindMethod(this, "_BiomesSave")
        this._SaveBar(p)
    }

    _BiomesLoad() {
        this._bio := []
        this._pot := []
        try this._bio := UiLogic.Copy(this.cfg.Data("biomes")["biomes"])
        try this._pot := UiLogic.Copy(this.cfg.Data("potions")["potions"])
        this._bSel := 0
        this._pSel := 0
        this._FillBiomes()
        this._FillPotions()
        this._BiomeShow()
        this._PotionShow()
    }

    _FillBiomes() {
        lv := this._lvB
        lv.Opt("-Redraw")
        lv.Delete()
        for b in this._bio
            lv.Add(, b["name"], (b.Has("rare") && b["rare"]) ? Chr(0x2726) " rare" : "", this._BiomePotSummary(b))
        lv.Opt("+Redraw")
        Theme.FitLastCol(lv)           ; after +Redraw: the scrollbar is known then
        if this._bSel
            lv.Modify(this._bSel, "Select Focus Vis")
    }

    _BiomePotSummary(b) {
        if !(b.Has("potions") && b["potions"] is Array && b["potions"].Length)
            return ""
        n := 0
        for e in b["potions"]
            n += (e is Map && e.Has("qty")) ? e["qty"] : 1
        return b["potions"].Length " (" n " uses)"
    }

    _BiomeColor(row) {
        return (row <= this._bio.Length && this._bio[row].Has("rare") && this._bio[row]["rare"]) ? Theme.Accent : ""
    }

    _BiomeSelect(lv, item, selected) {
        if (selected && item >= 1 && item <= this._bio.Length) {
            this._bSel := item
            this._BiomeShow()
        }
    }

    _BiomeShow() {
        b := this._bSel ? this._bio[this._bSel] : ""
        Theme.SetText(this._bName, IsObject(b) ? b["name"] : "Select a biome")
        this._bRare.Value := IsObject(b) && b.Has("rare") && b["rare"]
        lv := this._lvBP
        lv.Delete()
        if (IsObject(b) && b.Has("potions") && b["potions"] is Array) {
            for e in b["potions"]
                lv.Add(, e["name"], e.Has("qty") ? e["qty"] : 1)
        }
        ; an empty list shows a hint instead
        empty := lv.GetCount() = 0
        Theme.SetText(this._bpEmpty, IsObject(b) ? "No potions for " b["name"] " yet" : "Select a biome above")
        this._SetHidden(lv, empty)
        this._SetHidden(this._bpEmpty, !empty)
        Theme.FitLastCol(lv)
    }

    _BiomeRareFlip(chk) {
        if !this._bSel {
            chk.Value := 0
            return
        }
        this._bio[this._bSel]["rare"] := chk.Value ? 1 : 0
        this._FillBiomes()
        this._MarkDirty("Biomes & Potions")
    }

    SelectBiome(name) {
        for i, b in this._bio {
            if (b["name"] = name) {
                this._bSel := i
                this._lvB.Modify(i, "Select Focus Vis")
                this._BiomeShow()
                return true
            }
        }
        return false
    }

    ; Potion ids (entry "id", else its name; first of each id) and dropdown
    ; labels: the id, plus " - <desc>" when the entry has a desc.
    _PotionChoices() {
        ids := [], labels := []
        seen := Map()
        try {
            for e in this.cfg.Data("potions")["potions"] {
                if !(e is Map)
                    continue
                id := (e.Has("id") && Trim(String(e["id"])) != "") ? Trim(String(e["id"]))
                    : (e.Has("name") ? Trim(String(e["name"])) : "")
                if (id = "" || seen.Has(id))
                    continue
                seen[id] := true
                desc := e.Has("desc") ? Trim(String(e["desc"])) : ""
                ids.Push(id)
                labels.Push(desc != "" ? id " " Chr(0x2014) " " desc : id)
            }
        }
        return {ids: ids, labels: labels}
    }

    BiomePotionAdd() {
        i := this._bpDdl.Value
        name := (i >= 1 && i <= this._bpIds.Length) ? this._bpIds[i] : ""
        if (!this._bSel || name = "")
            return
        qty := Max(1, UiLogic.UInt(this._bpQty.Value, 1))
        b := this._bio[this._bSel]
        if !(b.Has("potions") && b["potions"] is Array)
            b["potions"] := []
        found := false
        for e in b["potions"] {
            if (e["name"] = name) {
                e["qty"] := qty
                found := true
            }
        }
        if !found
            b["potions"].Push(Map("name", name, "qty", qty))
        this._FillBiomes()
        this._BiomeShow()
        this._MarkDirty("Biomes & Potions")
    }

    _BiomePotionRemove() {
        row := this._lvBP.GetNext(0)
        if (!this._bSel || !row)
            return
        this._bio[this._bSel]["potions"].RemoveAt(row)
        this._FillBiomes()
        this._BiomeShow()
        this._MarkDirty("Biomes & Potions")
    }

    _FillPotions() {
        lv := this._lvP
        lv.Opt("-Redraw")
        lv.Delete()
        for e in this._pot
            lv.Add(, this._PotionLabel(e), this._Locked(e) ? "Locked" : "Unlocked", e.Has("perBiome") ? e["perBiome"] : "", e.Has("perDay") ? e["perDay"] : "", e.Has("perRun") ? e["perRun"] : "")
        lv.Opt("+Redraw")
        Theme.FitLastCol(lv)           ; after +Redraw: the scrollbar is known then
        if this._pSel
            lv.Modify(this._pSel, "Select Focus Vis")
    }

    _Locked(e) => !(e.Has("locked") && e["locked"] = 0)

    _PotionColor(row) {
        if (row > this._pot.Length)
            return ""
        return this._Locked(this._pot[row]) ? Theme.Muted : Theme.Accent
    }

    _PotionSelect(lv, item, selected) {
        if (selected && item >= 1 && item <= this._pot.Length) {
            this._pSel := item
            this._PotionShow()
        }
    }

    SelectPotion(name) {
        for i, e in this._pot {
            if (e["name"] = name) {
                this._pSel := i
                this._lvP.Modify(i, "Select Focus Vis")
                this._PotionShow()
                return true
            }
        }
        return false
    }

    _PotionShow() {
        e := this._pSel ? this._pot[this._pSel] : ""
        Theme.SetText(this._pName, IsObject(e) ? this._PotionLabel(e) (this._Locked(e) ? "   " Chr(0xB7) "  locked" : "   " Chr(0xB7) "  unlocked") : "Select a potion")
        this._capB.Value := IsObject(e) && e.Has("perBiome") ? String(e["perBiome"]) : ""
        this._capD.Value := IsObject(e) && e.Has("perDay") ? String(e["perDay"]) : ""
        this._capR.Value := IsObject(e) && e.Has("perRun") ? String(e["perRun"]) : ""
        this._SetHidden(this._btnUnlock, !(IsObject(e) && this._Locked(e)))
        this._SetHidden(this._btnRelock, !(IsObject(e) && !this._Locked(e)))
    }

    _PotionCaps() {
        if !this._pSel
            return
        e := this._pot[this._pSel]
        e["perBiome"] := UiLogic.UInt(this._capB.Value, e.Has("perBiome") ? e["perBiome"] : 1)
        e["perDay"] := UiLogic.UInt(this._capD.Value, e.Has("perDay") ? e["perDay"] : 3)
        e["perRun"] := UiLogic.UInt(this._capR.Value, e.Has("perRun") ? e["perRun"] : 3)
        this._FillPotions()
        this._PotionShow()
        this._MarkDirty("Biomes & Potions")
    }

    ; The saved (cfg.Data) entry with the same id / name as page entry e.
    _LivePotion(e) {
        k := UiLogic.KeyOf(e)
        try {
            for l in this.cfg.Data("potions")["potions"] {
                if (k != "" && UiLogic.KeyOf(l) == k)
                    return l
            }
        }
        return ""
    }

    static _CapText(p) {
        g := (k) => p.Has(k) ? p[k] : "?"
        return g("perBiome") "/biome, " g("perDay") "/day, " g("perRun") "/run"
    }

    ; Unlock the selected potion after the confirm dialog (this._confirm).
    ; The dialog shows the SAVED caps (live entry); unsaved cap edits on this
    ; page are neither shown nor saved by the unlock. Saves potions.json at
    ; once and fires "potionsChanged".
    UnlockSelected() {
        if !this._pSel
            return false
        e := this._pot[this._pSel]
        live := this._LivePotion(e)
        if !IsObject(live) {
            this.Log("Potions: " e["name"] " is not in the saved potions.json; not unlocked")
            return false
        }
        if !UiLogic.RequestUnlock(UiLogic.Copy(live), this._confirm)
            return false
        live["locked"] := 0
        e["locked"] := 0
        try this.cfg.SaveData("potions")
        catch Any as err
            this.Log("Potions: unlock of " e["name"] " not saved: " err.Message)
        this.Log("Potions: unlocked " e["name"] " (saved caps " Dashboard._CapText(live) ")")
        this._Fire("potionsChanged")
        this._FillPotions()
        this._PotionShow()
        return true
    }

    RelockSelected() {
        if !this._pSel
            return
        e := this._pot[this._pSel]
        UiLogic.Relock(e)
        live := this._LivePotion(e)
        if IsObject(live) {
            live["locked"] := 1
            try this.cfg.SaveData("potions")
            catch Any as err
                this.Log("Potions: re-lock of " e["name"] " not saved: " err.Message)
        }
        this.Log("Potions: re-locked " e["name"])
        this._Fire("potionsChanged")
        this._FillPotions()
        this._PotionShow()
    }

    ; Row label: the name, plus the id when another entry shares the name.
    _PotionLabel(e) {
        n := e.Has("name") ? String(e["name"]) : "?"
        if !(e.Has("id") && Trim(String(e["id"])) != "")
            return n
        dup := 0
        for o in this._pot
            dup += (o.Has("name") && o["name"] = n)
        return dup > 1 ? n " (" e["id"] ")" : n
    }

    _BiomesSave() {
        liveB := this.cfg.Data("biomes")
        liveP := this.cfg.Data("potions")
        if (liveB.Has("biomes") && liveB["biomes"] is Array)
            UiLogic.MergeByKey(liveB["biomes"], this._bio, ["rare", "potions"])
        if (liveP.Has("potions") && liveP["potions"] is Array)
            UiLogic.MergeByKey(liveP["potions"], this._pot, ["perBiome", "perDay", "perRun"])   ; never "locked"
        this.cfg.SaveData("biomes")
        this.cfg.SaveData("potions")
        this._Fire("potionsChanged")
        return ""
    }

    ; ---- page: Webhooks ---------------------------------------------------------

    _PageWebhooks(p) {
        g := this._gui
        x := {on: 216, name: 266, url: 354, mask: 452, men: 508, ev: 580, test: 926, del: 972}
        this._hx := x
        this._Panel(204, 152, 808, 388, "Webhooks"
            , "URLs are stored only in settings.ini and are never shown again after saving (" UiLogic.Dots " + last 4). "
            . "Leave URL empty to keep the saved one, or paste a new one to replace it.`n"
            . "Stop = stop message (every enabled webhook also gets a start message). Error = errors and recovery. "
            . "Mention = Discord user or role ID, used for rare biomes. Test sends one message to that row's saved webhook.")
        for h in [["ON", x.on], ["NAME", x.name], ["URL", x.url], ["MENTION", x.men]]
            Theme.Label(g, "x" h[2] + 2 " y182 w80 h16", h[1], "caps")
        for j, cap in Dashboard.EventCaps
            Theme.Label(g, "x" x.ev + (j - 1) * Dashboard.EventPitch " y182 w" Dashboard.EventPitch " h16 Center", cap, "caps")
        this._hookEmpty := Theme.Label(g, "x216 y214 w600 h20", "No webhooks yet. Add one to get Discord alerts.", "muted")
        this._rows := []
        Loop Dashboard.MaxHooks {
            i := A_Index
            y := 202 + (i - 1) * 36
            n0 := Theme.Sink.Length
            r := {}
            dirty := ObjBindMethod(this, "_MarkDirty", p)
            r.on := Theme.Check(g, x.on, y + 4, "", 1, dirty, "pill")
            r.name := Theme.Edit(g, x.name, y, 82, 28)
            r.url := Theme.Edit(g, x.url, y, 94, 28, "", "Password")
            r.mask := Theme.Label(g, "x" x.mask " y" y + 6 " w52 h18", "", "small")
            r.men := Theme.Edit(g, x.men, y, 66, 28)
            for e in [r.name, r.url, r.men]
                e.OnEvent("Change", dirty)
            r.ev := []
            for j, e in Dashboard.Events
                r.ev.Push(Theme.Check(g, x.ev + (j - 1) * Dashboard.EventPitch + Dashboard.EventBoxDx, y + 4, "", 0, dirty, "box"))
            r.test := Theme.Button(g, "x" x.test " y" y " w42 h28", "Test", ObjBindMethod(this, "HookTest", i), "quiet")
            Theme.Button(g, "x" x.del " y" y " w28 h28", Chr(0x2715), ObjBindMethod(this, "HookRemove", i), "quiet")
            r.ctrls := []
            Loop Theme.Sink.Length - n0
                r.ctrls.Push(Theme.Sink[n0 + A_Index])
            this._rows.Push(r)
            for k in ["on", "name", "url", "mask", "men", "test"]
                this._ids["hook" i "." k] := r.%k%
            for j, c in r.ev
                this._ids["hook" i ".ev" j] := c
        }
        this._hookAdd := Theme.Button(g, "x216 y" 202 + Dashboard.MaxHooks * 36 + 4 " w150 h30", "+  Add webhook", (*) => this.HookAdd())
        p.load := ObjBindMethod(this, "_HooksLoad")
        p.save := ObjBindMethod(this, "_HooksSave")
        this._SaveBar(p)
    }

    _HooksLoad() {
        this._hooks := UiLogic.Copy(this.cfg.Webhooks())
        this._hooksDirty := false
        this._HooksRender()
    }

    _HooksPull() {
        for i, h in this._hooks {
            if (i > Dashboard.MaxHooks)
                break
            r := this._rows[i]
            h["name"] := r.name.Value
            h["mention"] := r.men.Value
            h["enabled"] := r.on.Value
            ev := []
            for j, c in r.ev {
                if c.Value
                    ev.Push(Dashboard.Events[j])
            }
            h["events"] := ev
            h["_pending"] := r.url.Value
        }
    }

    _HooksRender() {
        for i, r in this._rows {
            has := i <= this._hooks.Length
            if has {
                h := this._hooks[i]
                r.name.Value := h["name"]
                r.men.Value := h["mention"]
                r.on.Value := h["enabled"]
                r.url.Value := h.Has("_pending") ? h["_pending"] : ""
                evs := Map()
                for e in h["events"]
                    evs[e] := true
                for j, c in r.ev
                    c.Value := evs.Has(Dashboard.Events[j])
                Theme.SetText(r.mask, h["url"] = "" ? "(none)" : UiLogic.MaskSecret(h["url"]))
            }
            for c in r.ctrls
                this._SetHidden(c, !has)
        }
        n := Min(this._hooks.Length, Dashboard.MaxHooks)
        this._SetHidden(this._hookEmpty, n > 0)
        this._hookAdd.Move(216, n ? 202 + n * 36 + 4 : 244)    ; right under the last row
        if (this._hookAdd.Visible)
            Theme.Repaint(this._gui)
        Theme.SetEnabled(this._hookAdd, this._hooks.Length < Dashboard.MaxHooks)
    }

    HookAdd() {
        this._HooksPull()
        if (this._hooks.Length >= Dashboard.MaxHooks)
            return
        this._hooks.Push(Map("name", "Webhook " (this._hooks.Length + 1), "url", "", "mention", "", "enabled", 1
            , "events", ["rare", "errors", "startstop"]))
        this._hooksDirty := true
        this._HooksRender()
        this._MarkDirty("Webhooks")
    }

    ; "Test" button on row i: one message to that saved webhook only (no
    ; mention, no @everyone; ignores its enabled and event boxes). The result
    ; goes to the page status. It only tests what is STORED, and only while
    ; the rows on screen match the stored list: Add/Remove set _hooksDirty
    ; (cleared by load/save), and every field is compared with the saved
    ; entry, so edits are caught too and row i can never be a different
    ; webhook than saved[i] (remove-then-add keeps the length equal).
    HookTest(i, *) {
        page := this._PageByName("Webhooks")
        this._HooksPull()
        saved := this.cfg.Webhooks()
        msg := ""
        if (i > this._hooks.Length || this._hooks.Length != saved.Length || i > saved.Length)
            msg := "Test not sent: this webhook row is not saved yet. Save first."
        else if (this._hooksDirty || this._HookDiffers(this._hooks[i], saved[i]))
            msg := "Test not sent: this webhook has unsaved changes. Save first."
        else if !(saved[i].Has("url") && UiLogic.IsWebhookUrl(saved[i]["url"]))
            msg := "Test not sent: this row has no valid Discord webhook URL. Paste one and Save."
        else if !this._cb.Has("testWebhook")
            msg := "Test needs the running " Brand.Name " app."
        else {
            this._SetPageStatus(page, "Sending test...")
            msg := String(this._Fire("testWebhook", i))
            if (msg = "")
                msg := "Test failed: no answer from the app."
        }
        msg := UiLogic.Scrub(msg, this._Secrets())
        this._SetPageStatus(page, msg, !(msg ~= "^Test sent"))
        this.Log("Webhooks: " msg)
        return msg
    }

    ; true when the on-screen row (after _HooksPull) differs from the saved entry.
    _HookDiffers(row, sv) {
        g := (m, k) => m.Has(k) ? m[k] : ""
        if (g(row, "url") != g(sv, "url"))
            return true
        if (Trim(g(row, "_pending")) != "")
            return true
        if (Trim(g(row, "name")) != Trim(g(sv, "name")) || Trim(g(row, "mention")) != Trim(g(sv, "mention")))
            return true
        if ((g(row, "enabled") ? 1 : 0) != (g(sv, "enabled") ? 1 : 0))
            return true
        a := Map(), b := Map()
        for e in (row.Has("events") ? row["events"] : [])
            a[StrLower(e)] := 1
        for e in (sv.Has("events") ? sv["events"] : [])
            b[StrLower(e)] := 1
        if (a.Count != b.Count)
            return true
        for e in a {
            if !b.Has(e)
                return true
        }
        return false
    }

    HookRemove(i, *) {
        this._HooksPull()
        if (i <= this._hooks.Length)
            this._hooks.RemoveAt(i)
        this._hooksDirty := true
        this._HooksRender()
        this._MarkDirty("Webhooks")
    }

    _HooksSave() {
        this._HooksPull()
        bad := []
        list := []
        for i, h in this._hooks {
            typed := h.Has("_pending") ? Trim(h["_pending"]) : ""
            if (typed != "") {
                if UiLogic.IsWebhookUrl(typed)
                    h["url"] := typed
                else
                    bad.Push(i)
            }
            if h.Has("_pending")
                h.Delete("_pending")
            list.Push(h)
        }
        this.cfg.SetWebhooks(list)
        this._hooks := UiLogic.Copy(this.cfg.Webhooks())
        this._hooksDirty := false
        this._HooksRender()
        if bad.Length
            return "Row " UiLogic.ArrayToCsv(bad) ": not a Discord webhook URL, kept the old one"
        return ""
    }

    ; ---- page: Calibrate --------------------------------------------------------

    _PageCalibrate(p) {
        g := this._gui
        this._Panel(204, 152, 808, 68, "Preset", "A ready calibration recorded fullscreen at one resolution and Windows display scale. "
            . "Apply copies it over your calibration (the old one is kept as data\calibration.json.bak).")
        this._calPreset := Theme.Dropdown(g, 220, 184, 220)
        this._ids["calPreset"] := this._calPreset
        this._ids["calPresetApply"] := Theme.Button(g, "x448 y182 w130 h30", "Apply preset", (*) => this._CalApplyPreset())
        this._calPresetNote := Theme.Label(g, "x590 y188 w406 h20", "", "muted")
        this._ids["calPresetNote"] := this._calPresetNote
        this._calPresets := []
        this._Panel(204, 232, 808, 384, "Steps", "Hover each target in Roblox and press the capture key (" this._CapKey() "). Nothing is clicked. Esc cancels the wizard.")
        cw := [200, 110, 466]
        Theme.ListHeader(g, 220, 260, cw, ["Step", "Status", "What to hover"])
        this._lvC := Theme.ListView(g, 220, 278, 776, 322, ["Step", "Status", "What to hover"], cw, "+Multi", ObjBindMethod(this, "_CalColor"))
        this._ids["calibrate"] := this._lvC
        Theme.Button(g, "x204 y628 w170 h30", "Record selected", (*) => this._CalRun("selected"), "primary")
        Theme.Button(g, "x382 y628 w110 h30", "Run all", (*) => this._CalRun("all"))
        Theme.Button(g, "x500 y628 w100 h30", "Refresh", (*) => this._CalLoad(), "quiet")
        this._calStatus := Theme.Label(g, "x610 y634 w402 h20 Right", "", "muted")
        this._ids["calStatus"] := this._calStatus
        this._calOk := []
        p.load := ObjBindMethod(this, "_CalLoad")
        p.onShow := ObjBindMethod(this, "_CalLoad")
    }

    _CalLoad() {
        lv := this._lvC
        lv.Opt("-Redraw")
        lv.Delete()
        this._calOk := []
        done := 0
        steps := []
        try steps := Calibrate.Steps()
        for s in steps {
            rec := ""
            try rec := (s["kind"] = "rect") ? Calibrate.Rect(s["id"])
                : (s["kind"] = "sig") ? Calibrate.Sig(s["id"]) : Calibrate.Point(s["id"])
            ok := IsObject(rec)
            done += ok
            this._calOk.Push(ok)
            lv.Add(, s["id"], ok ? Chr(0x2713) " recorded" : "missing", s["prompt"])
        }
        lv.Opt("+Redraw")
        Theme.FitLastCol(lv)           ; after +Redraw: the scrollbar is known then
        Theme.SetText(this._calStatus, done " of " steps.Length " steps recorded")
        this._CalPresetsLoad()
    }

    ; Preset list (whatever data\presets holds), pre-selected to the one
    ; made at this system's display; the note says when none matches.
    _CalPresetsLoad() {
        list := [], sys := ""
        try list := Calibrate.Presets()
        try sys := Calibrate.SystemFn.Call()
        this._calPresets := list
        labels := []
        for p in list
            labels.Push(p.label)
        dd := this._calPreset
        dd.Delete()
        if labels.Length
            dd.Add(labels)
        match := Calibrate.MatchPreset(list, sys)
        idx := 0
        for i, p in list
            if (IsObject(match) && p.path = match.path)
                idx := i
        if (idx || list.Length)
            dd.Choose(idx ? idx : 1)
        mine := IsObject(sys) ? Calibrate.PresetLabel(sys) : "unknown"
        Theme.SetText(this._calPresetNote, !list.Length ? "No presets installed: calibrate the steps below."
            : idx ? "Matches your display (" mine ")."
            : "No preset for your display (" mine "): calibrate the steps below.")
    }

    _CalApplyPreset() {
        i := this._calPreset.Value
        if !(i >= 1 && i <= this._calPresets.Length)
            return Theme.SetText(this._calPresetNote, "Pick a preset first.")
        p := this._calPresets[i]
        err := Calibrate.ApplyPreset(p.path)
        this.Log("Calibrate: " (err = "" ? "preset " p.label " applied (the old calibration is in data\calibration.json.bak)" : "preset not applied: " err))
        this._CalLoad()
        if (err != "")
            Theme.SetText(this._calPresetNote, "Not applied: " err)
    }

    _CalColor(row) {
        return (row <= this._calOk.Length && !this._calOk[row]) ? Theme.Accent : ""
    }

    _CalRun(which) {
        ids := "all"
        if (which = "selected") {
            ids := []
            row := 0
            while (row := this._lvC.GetNext(row))
                ids.Push(this._lvC.GetText(row, 1))
            if !ids.Length
                return Theme.SetText(this._calStatus, "Select one or more steps first.")
        }
        n := 0
        this._gui.Minimize()
        try {
            n := this._cb.Has("calibrate") ? this._cb["calibrate"].Call(ids) : Calibrate.Run(ids)
        } catch Any as e {
            this.Log("Calibrate: " e.Message)
        }
        this._gui.Restore()
        this._CalLoad()
        this.Log("Calibrate: " (IsInteger(n) ? n : 0) " step(s) recorded")
    }

    ; ---- page: Settings ---------------------------------------------------------

    _PageSettings(p) {
        g := this._gui
        this._Panel(204, 152, 396, 80, "Private server", "Secret. Stored only in settings.ini, never shown or logged.")
        this._psEdit := Theme.Edit(g, 220, 186, 236, 28, "", "Password")
        this._psEdit.OnEvent("Change", ObjBindMethod(this, "_MarkDirty", p))
        this._psMask := Theme.Label(g, "x462 y192 w66 h18", "", "small")
        Theme.Button(g, "x532 y186 w52 h28", "Clear", (*) => this._PsClear(), "quiet")
        this._ids["privateServer"] := this._psEdit, this._ids["privateServerMask"] := this._psMask

        this._Panel(204, 248, 396, 68, "Routes", "Every walk that comes with the macro was recorded with Sol's RNG VIP gamepass, which walks faster. "
            . "Without VIP you walk slower and the walks fall short: turn this off and record your own walks under Setup > Routes.")
        this._BoolField(220, 280, "VIP gamepass routes", "General.vip", 1)

        this._Panel(204, 332, 396, 164, "Intervals")
        this._IntField(220, 362, "Quest board every", "General.questIntervalMin", 30, "min", 160, 1)
        this._IntField(220, 395, "Anti-AFK every", "recovery.afkMin", 15, "min", 160)
        this._IntField(220, 428, "Stuck reset after", "recovery.stuckMin", 10, "min", 160)
        this._IntField(220, 461, "Merchant chat check", "merchant.chatPollSec", 5, "s", 160)

        this._Panel(204, 512, 396, 134, "Recovery")
        this._BoolField(220, 544, "Auto-rejoin and anti-AFK", "recovery.enabled", 1)
        this._IntField(220, 574, "Load wait", "recovery.loadSec", 20, "s", 160)
        this._BoolField(220, 610, "Anti ghost server (rejoin if moved out of it)", "recovery.antiGhost", 1, 360)

        this._Panel(616, 152, 396, 132, "Alerts")
        this._BoolField(632, 186, "Sound on rare biome", "General.sound", 1)
        this._BoolField(632, 214, "Ping @everyone on the biomes below", "General.everyonePing", 1)
        this._StrField(632, 244, "@everyone biomes", "General.everyoneBiomes", "DREAMSPACE,GLITCHED,CYBERSPACE", 234, 130)

        this._Panel(616, 300, 396, 96, "Hotkeys")
        this._hkText := Theme.Label(g, "x632 y330 w364 h44", "", "body")

        this._Panel(616, 412, 396, 152, "Look", "Theme: the colours and the background picture (Sol's RNG art). A new theme shows after Apply now or the next start. "
            . "Animations: the tab underline, page fade, moon, stars, running pulse and Home count-up. "
            . "They only move while this window is in front, never while Roblox is.")
        this._BoolField(632, 446, "Animations", "UI.animations", 1)
        Theme.Label(g, "x632 y482 w90 h20", "Theme")
        this._themeDdl := Theme.Dropdown(g, 722, 478, 150, Theme.Names)
        this._themeDdl.OnEvent("Change", ObjBindMethod(this, "_MarkDirty", p))
        this._ids["UI.theme"] := this._themeDdl
        this._themeApply := Theme.Button(g, "x880 y478 w116 h28", "Apply now", (*) => this.ApplyTheme(), "quiet")
        this._ids["themeApply"] := this._themeApply
        this._ids["themeNote"] := Theme.Label(g, "x632 y516 w364 h40", "", "muted")
        p.load := ObjBindMethod(this, "_SettingsLoad")
        p.save := ObjBindMethod(this, "_SettingsSave")
        this._SaveBar(p)
    }

    ; ---- page: Clips ----------------------------------------------------------------

    _PageClips(p) {
        g := this._gui
        this._Panel(204, 152, 396, 300, "Medal clips")
        this._BoolField(220, 186, "Clip with Medal", "Medal.enabled", 0)
        this._StrField(220, 216, "Clip hotkey", "Medal.clipHotkey", "F8", 80, 130)
        this._IntField(220, 252, "Delay (s)", "Medal.delaySec", 3, "", 90)
        this._IntField(398, 252, "Cooldown (s)", "Medal.cooldownSec", 30, "", 110)
        this._BoolField(220, 290, "Clip on rare biome", "Medal.onRareBiome", 1)
        this._BoolField(220, 318, "Clip on rare aura", "Medal.onRareAura", 0)
        ; aura rule (lib\Auras.ahk): listed OR class listed OR 1-in-N >= threshold
        this._StrField(220, 348, "Clip auras rarer than 1 in", "Medal.auraMinRarity", "100000000", 150, 180)
        this._binds[this._binds.Length].kind := "rarity"
        this._StrField(220, 382, "Always clip classes", "Medal.auraAlwaysCategories", "Challenged,Challenged+", 224, 140)
        this._StrField(220, 416, "Always clip auras", "Medal.auras", "", 224, 140)
        this._Panel(616, 152, 396, 84, "Medal", "Medal (medal.exe) must be running. The macro presses the clip hotkey, "
            . "so set the same key in Medal. The hotkey is one of F4-F24, never a macro, capture or recorder key.`n`n"
            . "A rare aura is clipped when it is listed, its class is listed, or it is rarer than the threshold.")
        Theme.Label(g, "x632 y184 w364 h20", "Medal (medal.exe) must be running.", "muted")
        Theme.Label(g, "x632 y206 w364 h20", "Set the same hotkey in Medal (F8, Alt+9, Shift+F5+T).", "muted")
        p.validate := ObjBindMethod(this, "_ClipsCheck")
        this._SaveBar(p)
    }

    ; Configured calibration capture key ([Calibrate] captureKey, default
    ; Calibrate.DefaultCaptureKey = F4; F9 is Roblox's developer console).
    _CapKey() {
        k := Trim(this.cfg.Get("Calibrate.captureKey", Calibrate.DefaultCaptureKey))
        return (k = "" || StrUpper(k) = "F9") ? Calibrate.DefaultCaptureKey : k
    }

    ; "" or why Clips cannot be saved (checked before cfg is touched).
    _ClipsCheck() {
        if (Auras.ParseRarity(this.Ctrl("Medal.auraMinRarity").Value) = "")
            return "aura rarity: type a number like 100,000,000, 100m or 1b"
        hk := Trim(this.Ctrl("Medal.clipHotkey").Value)
        if (hk = "")
            return ""
        return Clip.HotkeyProblem(hk, this.cfg)
    }

    _SettingsLoad() {
        this._psWipe := false
        this._psEdit.Value := ""
        cur := this.cfg.Get("General.privateServer", "")
        Theme.SetText(this._psMask, cur = "" ? "(not set)" : UiLogic.MaskSecret(cur))
        hk := (k, d) => this.cfg.Get("Hotkeys." k, d)
        Theme.SetText(this._hkText, hk("start", "F1") " start   " hk("pause", "F2") " pause / resume   " hk("stop", "F3") " stop (halts potions)`n"
            . "Capture key " this._CapKey() "   Route recorder " RouteRecorder.Key)
        this._themeDdl.Choose(Theme.ThemeName(this.cfg.Get("UI.theme", "Moontide")))
        this._ThemeNote()
    }

    ; Settings > Look "Apply now": the page is saved first (the theme picked
    ; and anything else changed here; no separate Save), then the macro
    ; restarts to show it. -> true when the restart was asked for.
    ApplyTheme() {
        if !this.SavePage("Settings")
            return false
        this._Fire("restart")
        return true
    }

    ; "Now: X" or "X after Apply now" under the theme dropdown
    _ThemeNote() {
        saved := Theme.ThemeName(this.cfg.Get("UI.theme", "Moontide"))
        Theme.SetText(this._ids["themeNote"], saved = Theme.Current ? "Now: " Theme.Current " (" Theme.Presets[Theme.Current].Note ")"
            : saved " shows after Apply now (saves and restarts the macro while it is stopped) or the next start.")
    }

    _PsClear() {
        this._psWipe := true
        this._psEdit.Value := ""
        Theme.SetText(this._psMask, "(clear on Save)")
        this._MarkDirty("Settings")
    }

    _SettingsSave() {
        this.cfg.Set("UI.theme", Theme.ThemeName(this._themeDdl.Text))
        this._ThemeNote()
        cur := this.cfg.Get("General.privateServer", "")
        new := this._psWipe ? "" : UiLogic.NewSecret(cur, this._psEdit.Value)
        this.cfg.Set("General.privateServer", new)
        this._psWipe := false
        this._psEdit.Value := ""
        Theme.SetText(this._psMask, new = "" ? "(not set)" : UiLogic.MaskSecret(new))
        return ""
    }

    ; ---- page: Biome items --------------------------------------------------------

    _PageBiomeItems(p) {
        g := this._gui
        this._Panel(204, 152, 808, 236, "Biome items", "Used in any biome you have NOT marked rare (Alerts > Biomes), so a rare biome is never changed away. "
            . "One item per 20 minutes (the game's server cooldown); the first ticked item that is off its own cooldown goes first. "
            . "The ONE-TIME Biome Randomizer is never used: a tile or description that says one-time / single use is refused. "
            . "Needs the inventory calibration steps; the Biome Selector also needs selector_list_rect (the list of Drives) and selector_confirm.")
        this._BoolField(220, 186, "Use biome items", "BiomeItems.enabled", 0)
        Theme.Rect(g, 220, 218, 776, 1, Theme.PanelC)
        this._BoolField(220, 232, "Biome Randomizer  (35 min cooldown)", "BiomeItems.biomeRandomizer", 0, 420)
        this._BoolField(220, 264, "Strange Controller  (20 min cooldown)", "BiomeItems.strangeController", 0, 420)
        this._BoolField(220, 296, "Biome Selector  (60 min cooldown, spends one Drive)", "BiomeItems.biomeSelector", 0, 420)
        Theme.Label(g, "x274 y334 w140 h20", "Drive to summon", "muted")
        items := ["(pick one)"]
        for d in BiomeItemsTask.Drives
            items.Push(d)
        this._selDrive := Theme.Dropdown(g, 420, 330, 260, items)
        this._selDrive.OnEvent("Change", ObjBindMethod(this, "_MarkDirty", p))
        this._ids["BiomeItems.selectorDrive"] := this._selDrive
        p.load := ObjBindMethod(this, "_BiomeItemsLoad")
        p.save := ObjBindMethod(this, "_BiomeItemsSave")
        this._SaveBar(p)
    }

    _BiomeItemsLoad() {
        cur := this.cfg.Get("BiomeItems.selectorDrive", "")
        idx := 1
        for i, d in BiomeItemsTask.Drives
            if (d = cur)
                idx := i + 1
        this._selDrive.Choose(idx)
    }

    _BiomeItemsSave() {
        t := this._selDrive.Text
        this.cfg.Set("BiomeItems.selectorDrive", (t = "(pick one)") ? "" : t)
        return ""
    }

    ; ---- page: Obby & Memory ------------------------------------------------------

    _PageObbyMemory(p) {
        g := this._gui
        this._Panel(204, 152, 396, 220, "Obby", "Runs the obby for the Basic Blessing on a timer: equips the Sailor aura (it walks on water), plays the obby route, then puts your aura back. "
            . "Record the obby route WITH Sailor on (from a respawn to the star) on Setup > Routes, and calibrate the aura storage steps (aura_open ... aura_close). "
            . "With buff_expand and obby_blessing calibrated the buff list is expanded, the blessing checked and the list collapsed again; a failed run is tried again Retries times.")
        this._BoolField(220, 186, "Run the obby", "Obby.enabled", 0)
        this._IntField(220, 224, "Every", "Obby.intervalMin", 10, "minutes", 170, 1)
        this._IntField(220, 262, "Retries", "Obby.retries", 1)
        this._ids["obbyBlessingNote"] := Theme.Label(g, "x220 y306 w364 h56", "", "muted")
        this._Panel(616, 152, 396, 220, "Memory Match", "Plays the Memory Match board (20 tiles, 10 turns, every 12 hours) and keeps the best pairs. "
            . "Record the memory_match route (to the board) on Setup > Routes. It stays off until the board layout is added from a clip of one round.")
        this._memSwitch := this._BoolField(632, 186, "Play Memory Match", "MemoryMatch.enabled", 0)
        this._WarnOn(this._memSwitch, "Memory Match is not perfect", "Memory Match works better at some screen sizes than others, and it can miss the board or skip a round. Keep an eye on it the first times.")
        if !MemoryMatchTask.LayoutKnown {
            ; no layout yet: the switch cannot be turned on
            this._memSwitch.DefineProp("Flip", {Call: (*) => 0})
            Theme.SetColors(this._memSwitch._box, Theme.OffBg, "5E6B80")
        }
        this._ids["memoryLayoutNote"] := Theme.Label(g, "x632 y224 w364 h40", "", "muted")
        this._ids["memoryNote"] := Theme.Label(g, "x632 y272 w364 h20", "", "muted")
        ; every aura swap (the obby's Sailor, the combat aura, putting yours back)
        this._Panel(204, 388, 808, 100, "Aura swaps")
        this._BoolField(220, 422, "Equip the first search result", "Auras.equipFirst", 0, , "Equip the first search result (no name reading): use this if aura swaps fail at your resolution. "
            . "Make sure the search finds only the aura you want. Used for every aura swap: Sailor for the obby, the combat aura, and putting your aura back.")
        Theme.Label(this._gui, "x220 y454 w776 h20", "For aura swaps that fail at your resolution (the obby and Limited > Hunting too).", "muted")
        p.load := ObjBindMethod(this, "_ObbyMemoryLoad")
        p.validate := ObjBindMethod(this, "_ObbyMemoryCheck")
        this._SaveBar(p)
    }

    _ObbyMemoryLoad() {
        cal := IsObject(Calibrate.Point("obby_blessing")) && IsObject(Calibrate.Point("buff_expand"))
        Theme.SetText(this._ids["obbyBlessingNote"], cal
            ? "buff_expand + obby_blessing calibrated: the blessing is checked after each run"
            : "buff_expand / obby_blessing not calibrated: runs are unchecked (Setup > Calibrate)")
        known := MemoryMatchTask.LayoutKnown
        if !known
            this._memSwitch.Value := 0
        Theme.SetText(this._ids["memoryLayoutNote"], known ? "" : "waiting for the board layout (send a clip of one round)")
        nt := ""
        try nt := MemoryMatchTask({cfg: this.cfg}).NextTry()
        Theme.SetText(this._ids["memoryNote"], (nt = "")
            ? "next try: when it is turned on"
            : "next try: " FormatTime(nt, "HH:mm") " on " FormatTime(nt, "dd MMM"))
    }

    ; "" or why Obby & Memory cannot be saved (checked before cfg is touched).
    _ObbyMemoryCheck() {
        mins := UiLogic.UInt(this.Ctrl("Obby.intervalMin").Value, 10)
        if (mins < 1 || mins > 120)
            return "obby: every must be 1 to 120 minutes"
        tries := UiLogic.UInt(this.Ctrl("Obby.retries").Value, 1)
        if (tries > 3)
            return "obby: retries must be 0 to 3"
        return ""
    }

    ; ---- page: Stats (Home) -----------------------------------------------------

    ; [key, label] rows of the Today / This run panels. Keys are DailyStats
    ; counters or DailyStats.Derived values (reelRate, fishPerHour, uptimeText).
    static StatRows := [["fishCaught", "Fish caught"], ["fishFailed", "Fish missed"], ["reelRate", "Reel success"]
        , ["fishPerHour", "Fish per hour"], ["sells", "Sell trips"], ["biomes", "Biomes seen"], ["rareBiomes", "Rare biomes"]
        , ["rareAuras", "Rare auras"], ["rejoins", "Rejoins"], ["uptimeText", "Uptime"]]

    _PageStats(p) {
        g := this._gui
        for col in [["day", 204, "Today"], ["run", 616, "This run"]] {
            this._Panel(col[2], 152, 396, 300, col[3])
            for i, r in Dashboard.StatRows {
                y := 184 + (i - 1) * 26
                Theme.Label(g, "x" col[2] + 16 " y" y " w200 h22", r[2], "body", Theme.CardBg)
                this._ids["stats:" col[1] ":" r[1]] := Theme.Label(g, "x" col[2] + 216 " y" y " w164 h22 Right", "0", "value", Theme.CardBg)
            }
        }
        this._Panel(204, 468, 808, 148, "Last 7 days")
        hw := [120, 90, 90, 80, 90, 80, 90, 110]
        Theme.ListHeader(g, 220, 496, hw, ["Day", "Fish", "Missed", "Reel", "Biomes", "Rare", "Rejoins", "Uptime"])
        this._statsHist := Theme.ListView(g, 220, 520, 776, 84, ["Day", "Fish", "Missed", "Reel", "Biomes", "Rare", "Rejoins", "Uptime"], hw)
        this._ids["stats:history"] := this._statsHist
    }

    ; Stats page. day / run: Maps of counters plus DailyStats.Derived keys
    ; (missing = 0); history: Array of {label, m} newest first, or "" to keep it.
    SetStatsPage(day, run, history := "") {
        for col in [["day", day], ["run", run]] {
            for r in Dashboard.StatRows {
                c := this._ids["stats:" col[1] ":" r[1]]
                v := Dashboard.StatText(col[2], r[1])
                if (c.Text != v)
                    Theme.SetText(c, v)
            }
        }
        if !IsObject(history)
            return
        lv := this._statsHist
        lv.Opt("-Redraw")
        lv.Delete()
        for h in history
            lv.Add(, h.label, Dashboard.StatText(h.m, "fishCaught"), Dashboard.StatText(h.m, "fishFailed"), Dashboard.StatText(h.m, "reelRate")
                , Dashboard.StatText(h.m, "biomes"), Dashboard.StatText(h.m, "rareBiomes"), Dashboard.StatText(h.m, "rejoins"), Dashboard.StatText(h.m, "uptimeText"))
        lv.Opt("+Redraw")
    }

    ; one Stats cell: reelRate "87%" ("-" with no tries), uptimeText as given
    ; ("0m" when missing), counters as whole numbers (missing = 0)
    static StatText(m, k) {
        v := (m is Map && m.Has(k)) ? m[k] : ""
        if (k = "reelRate")
            return (v = "") ? "-" : Round(v) "%"
        if (k = "uptimeText")
            return (v = "") ? "0m" : String(v)
        if (k = "fishPerHour")
            return (v = "") ? "0" : String(Round(v, 1))
        return (v = "") ? "0" : String(Round(v))
    }

    ; ---- page: Daily summary (Alerts) -------------------------------------------

    _PageSummary(p) {
        g := this._gui
        this._Panel(204, 152, 396, 200, "Daily summary", "Once a day at the time below, one Discord message with what the macro did that day. "
            . "It goes to every webhook that has Stop (start / stop messages) ticked on Alerts > Discord. Send one now sends today's so far.")
        this._BoolField(220, 186, "Send a daily summary to Discord", "Summary.enabled", 0)
        this._StrField(220, 224, "Send at (24 h)", "Summary.time", "23:55", 70)
        Theme.Label(g, "x220 y262 w364 h36", "Goes to the webhooks that get start / stop messages (Alerts > Discord).", "muted")
        Theme.Button(g, "x220 y306 w150 h30", "Send one now", (*) => this._SummaryNow())
        this._ids["summaryStatus"] := Theme.Label(g, "x380 y312 w210 h20", "", "muted")
        this._Panel(616, 152, 396, 200, "What it says")
        Theme.Label(g, "x632 y184 w364 h150", "Fish caught and missed, reel success`nSell trips`nBiomes and rare biomes seen`nRare auras rolled`nRejoins`nHow long the macro ran", "body", Theme.CardBg)
        p.validate := () => Dashboard.TimeOk(this.Ctrl("Summary.time").Value) ? "" : "summary: send at must be a time like 23:55"
        this._SaveBar(p)
    }

    _SummaryNow() {
        r := this._Fire("sendSummary")
        Theme.SetText(this._ids["summaryStatus"], r = "" ? "Not sent: the macro is not ready" : r)
    }

    ; "HH:mm" 24 h (one-digit hour allowed)
    static TimeOk(s) => RegExMatch(Trim(String(s)), "^([01]?\d|2[0-3]):[0-5]\d$") ? true : false

    ; ---- page: Remote (Alerts) --------------------------------------------------

    _PageRemote(p) {
        g := this._gui
        this._Panel(204, 152, 396, 464, "Discord bot", "Your own Discord bot reads one channel and runs commands from the user ids below only. "
            . "The token is secret: stored only in settings.ini, never shown or logged.")
        this._BoolField(220, 186, "Allow commands from Discord", "Remote.enabled", 0)
        Theme.Label(g, "x220 y228 w160 h20", "Bot token")
        this._rmEdit := Theme.Edit(g, 380, 224, 136, 28, "", "Password")
        this._rmEdit.OnEvent("Change", ObjBindMethod(this, "_MarkDirty", p))
        Theme.Button(g, "x524 y224 w60 h28", "Clear", (*) => this._RmClear(), "quiet")
        this._rmMask := Theme.Label(g, "x380 y254 w204 h18", "", "small")
        this._ids["remoteToken"] := this._rmEdit, this._ids["remoteTokenMask"] := this._rmMask
        this._StrField(220, 280, "Channel id", "Remote.channel", "", 204, 160)
        this._StrField(220, 318, "Allowed user ids", "Remote.users", "", 204, 160)
        this._StrField(220, 356, "Command prefix", "Remote.prefix", "!", 40, 160)
        Theme.Button(g, "x220 y402 w150 h30", "Test connection", (*) => this._RemoteTest())
        this._ids["remoteStatus"] := Theme.Label(g, "x220 y442 w364 h56", "", "muted")
        Theme.Label(g, "x220 y516 w364 h80", "Several user ids: separate them with commas.", "muted")
        this._Panel(616, 152, 396, 464, "Set it up")
        Theme.Label(g, "x632 y184 w364 h300", "1. discord.com/developers: New Application, then Bot: Reset Token and paste it here.`n`n"
            . "2. On the same Bot page turn on MESSAGE CONTENT INTENT.`n`n"
            . "3. OAuth2 > URL Generator: tick bot, then View Channels, Send Messages, Attach Files and Read Message History. Open the link and add the bot to your server.`n`n"
            . "4. Discord Settings > Advanced: Developer Mode on. Right-click your channel: Copy Channel ID. Right-click yourself: Copy User ID.", "body", Theme.CardBg)
        Theme.Label(g, "x632 y500 w364 h16", "COMMANDS", "caps", Theme.CardBg)
        Theme.Label(g, "x632 y520 w364 h80", "!status   !stats   !screenshot   !log`n!start   !stop   !pause   !resume   !help", "body", Theme.CardBg)
        p.load := ObjBindMethod(this, "_RemoteLoad")
        p.save := ObjBindMethod(this, "_RemoteSave")
        p.validate := ObjBindMethod(this, "_RemoteCheck")
        this._SaveBar(p)
    }

    _RemoteLoad() {
        this._rmWipe := false
        this._rmEdit.Value := ""
        cur := this.cfg.Get("Remote.token", "")
        Theme.SetText(this._rmMask, cur = "" ? "(not set)" : UiLogic.MaskSecret(cur))
    }

    _RmClear() {
        this._rmWipe := true
        this._rmEdit.Value := ""
        Theme.SetText(this._rmMask, "(clear on Save)")
        this._MarkDirty("Remote")
    }

    _RemoteSave() {
        cur := this.cfg.Get("Remote.token", "")
        new := this._rmWipe ? "" : UiLogic.NewSecret(cur, this._rmEdit.Value)
        this.cfg.Set("Remote.token", new)
        this._rmWipe := false
        this._rmEdit.Value := ""
        Theme.SetText(this._rmMask, new = "" ? "(not set)" : UiLogic.MaskSecret(new))
        return ""
    }

    ; "" or why Remote cannot be saved. Ids: Discord snowflakes (15-21 digits).
    _RemoteCheck() {
        ch := Trim(this.Ctrl("Remote.channel").Value)
        users := Trim(this.Ctrl("Remote.users").Value)
        if (ch != "" && !RegExMatch(ch, "^\d{15,21}$"))
            return "remote: the channel id is a long number (right-click the channel, Copy Channel ID)"
        for u in StrSplit(users, ",", " `t")
            if (u != "" && !RegExMatch(u, "^\d{15,21}$"))
                return "remote: user ids are long numbers separated by commas"
        pre := Trim(this.Ctrl("Remote.prefix").Value)
        if (StrLen(pre) < 1 || StrLen(pre) > 3 || InStr(pre, " "))
            return "remote: the prefix is 1 to 3 characters, like !"
        if this.Ctrl("Remote.enabled").Value {
            tok := this._rmWipe ? "" : UiLogic.NewSecret(this.cfg.Get("Remote.token", ""), this._rmEdit.Value)
            if (tok = "" || ch = "" || users = "")
                return "remote: needs the bot token, the channel id and at least one user id"
        }
        return ""
    }

    _RemoteTest() {
        Theme.SetText(this._ids["remoteStatus"], "Testing...")
        r := this._Fire("testRemote")
        Theme.SetText(this._ids["remoteStatus"], UiLogic.Scrub(r = "" ? "Not tested: the macro is not ready" : r, this._Secrets()))
    }

    ; ---- page: Check & help (Setup) ---------------------------------------------

    static CheckTags := Map("ok", "[OK]", "warn", "[!]", "fail", "[X]", "info", "[i]")

    _PageCheck(p) {
        g := this._gui
        this._Panel(204, 152, 396, 464, "Check my setup", "Looks at Roblox, your screen, the Roblox logs, your private server link, Discord webhooks, "
            . "calibration and apps that pull focus away from Roblox. It sends no input. [!] = may cause trouble, [X] = will not work.")
        Theme.Button(g, "x220 y186 w130 h30", "Check now", (*) => this._CheckNow(), "primary")
        this._ids["checkSummary"] := Theme.Label(g, "x362 y192 w222 h20", "", "muted")
        this._checkOut := Theme.Edit(g, 220, 228, 364, 372, "", "Multi ReadOnly -WantReturn VScroll")
        this._ids["checkOut"] := this._checkOut
        this._Panel(616, 152, 396, 200, "Send my log")
        Theme.Label(g, "x632 y184 w364 h60", "Makes a zip of your log and this check. Webhook links, server links, the bot token, Discord ids and your Windows name are taken out. "
            . "Send it to whoever helps you.", "body", Theme.CardBg)
        Theme.Button(g, "x632 y250 w150 h30", "Make support zip", (*) => this._LogZip())
        this._zipBtn := Theme.Button(g, "x792 y250 w100 h30", "Show it", (*) => this._ZipShow(), "quiet")
        this._SetHidden(this._zipBtn, true)
        this._zipShots := Theme.Check(g, 632, 288, "Add recent screenshots (they can show your Roblox name and chat)", 0, "", "box", 364)
        this._ids["zipShots"] := this._zipShots
        this._ids["zipStatus"] := Theme.Label(g, "x632 y314 w364 h34", "", "muted")
        this._Panel(616, 368, 396, 248, "Setup wizard")
        Theme.Label(g, "x632 y400 w364 h60", "Walks through the basics: the Roblox check, your private server, Discord and what to run. Every step can be skipped.", "body", Theme.CardBg)
        Theme.Button(g, "x632 y472 w180 h30", "Run the setup wizard", (*) => this._Fire("wizard"))
        this._zipPath := ""
    }

    _CheckNow() {
        Theme.SetText(this._ids["checkSummary"], "Checking...")
        this.ShowCheck(this._Fire("checkSetup"))
    }

    ; results: Array of {level, name, detail, fix} (SetupCheck.Run)
    ShowCheck(results) {
        if !IsObject(results) {
            Theme.SetText(this._ids["checkSummary"], "Not checked: the macro is not ready")
            return
        }
        text := "", n := Map("ok", 0, "warn", 0, "fail", 0, "info", 0)
        for r in results {
            lv := r.HasProp("level") ? r.level : "info"
            n[lv] := (n.Has(lv) ? n[lv] : 0) + 1
            tag := Dashboard.CheckTags.Has(lv) ? Dashboard.CheckTags[lv] : "[i]"
            text .= tag "  " r.name (r.HasProp("detail") && r.detail != "" ? ": " r.detail : "") "`r`n"
            if (r.HasProp("fix") && r.fix != "" && lv != "ok")
                text .= "       " r.fix "`r`n"
        }
        this._checkOut.Value := UiLogic.Scrub(text, this._Secrets(), true)
        Theme.SetText(this._ids["checkSummary"], n["ok"] " ok, " n["warn"] " warning" (n["warn"] = 1 ? "" : "s") ", " n["fail"] " problem" (n["fail"] = 1 ? "" : "s"))
    }

    _LogZip() {
        Theme.SetText(this._ids["zipStatus"], "Making the zip...")
        r := this._Fire("logBundle", this._zipShots.Value ? true : false)
        ok := IsObject(r) && r.HasProp("ok") && r.ok
        this._zipPath := ok ? r.path : ""
        this._SetHidden(this._zipBtn, !ok)
        msg := !IsObject(r) ? "Not made: the macro is not ready" : ok ? "Made " RegExReplace(r.path, "^.*\\") " in the logs folder" : "Not made: " r.msg
        Theme.SetText(this._ids["zipStatus"], UiLogic.Scrub(msg, this._Secrets()))
    }

    _ZipShow() {
        if (this._zipPath != "" && FileExist(this._zipPath))
            try Run('explorer.exe /select,"' this._zipPath '"')
    }

    ; ---- page: Schedule (Setup) -------------------------------------------------

    _PageSchedule(p) {
        g := this._gui
        this._Panel(204, 152, 396, 264, "Run schedule")
        this._BoolField(220, 186, "Start and stop on a schedule", "Schedule.enabled", 0)
        this._StrField(220, 224, "Start at (24 h)", "Schedule.start", "22:00", 70)
        this._StrField(220, 262, "Stop at (24 h)", "Schedule.end", "08:00", 70)
        this._IntField(220, 300, "Stop after", "Schedule.maxHours", 0, "hours", 170, 0)
        Theme.Label(g, "x220 y342 w364 h40", "0 hours = no limit. The same start and stop time = all day.", "muted")
        this._Panel(616, 152, 396, 264, "How it works")
        Theme.Label(g, "x632 y184 w364 h220", "At the start time the macro brings Roblox to the front and starts, as if you pressed F1. At the stop time it stops, as F3 does.`n`n"
            . "Stop it yourself during the window and it stays stopped until the next one.`n`n"
            . "Stop after also ends a run you started yourself (while the schedule is on).`n`n"
            . "Roblox must be open; with auto-rejoin on the macro opens your private server when it is not.", "body", Theme.CardBg)
        p.validate := ObjBindMethod(this, "_ScheduleCheck")
        this._SaveBar(p)
    }

    _ScheduleCheck() {
        if !Dashboard.TimeOk(this.Ctrl("Schedule.start").Value) || !Dashboard.TimeOk(this.Ctrl("Schedule.end").Value)
            return "schedule: start and stop must be times like 22:00"
        h := UiLogic.UInt(this.Ctrl("Schedule.maxHours").Value, 0)
        if (h > 48)
            return "schedule: stop after 0 to 48 hours"
        return ""
    }

    ; ---- page: Hunting (Limited) ------------------------------------------------

    ; Halloween minion / orb hunting: the game removes it later in November,
    ; then this page (and the Limited hub, if nothing else is in it) goes.
    _PageHunting(p) {
        g := this._gui
        this._Panel(204, 152, 808, 64, "Limited time")
        this._ids["limitedNote"] := Theme.Label(g, "x220 y184 w776 h20", "Halloween event: the game removes hunting later in November.", "muted")
        this._Panel(204, 232, 808, 220, "Hunting (Halloween)", "In every weather biome (not rare, not event): puts on the combat aura, respawns, finds the orbs' and minions' health bars, "
            . "walks up and uses the aura's skills (any aura with skills; never the number keys), then respawns (and puts your aura back when that is on). Once per biome. "
            . "NORMAL has shown no orbs: it is not hunted unless Hunt in NORMAL too is on, only the aura and a respawn are made ready there. "
            . "Needs the aura storage steps calibrated (as the obby). Auto roll can equip a new aura mid-hunt; the skills then do nothing until the next hunt. "
            . "Shift lock keeps the character facing the target in fights; it needs Roblox's Shift Lock Switch setting on. "
            . "Graveyard boss: once per GRAVEYARD start it looks around ~20 s for the boss (before any aura swap) and fights it up to 10 min.")
        this._WarnOn(this._BoolField(220, 266, "Hunt orbs and minions", "Minions.enabled", 0), "Minion hunting is buggy", "Hunting orbs and minions is still very buggy at every screen size: it can get stuck, miss targets or walk off. Watch it when you use it.")
        auraEdit := this._StrField(220, 304, "Combat aura", "Minions.aura", "Eden", 160)
        auraEdit.OnEvent("LoseFocus", (ctl, *) => this._BigAuraCheck(ctl))
        this._IntField(220, 342, "Hunt at most", "Minions.maxSec", 120, "seconds", 170, 60)
        this._BoolField(632, 266, "Put my aura back after", "Minions.putBack", 0)
        this._BoolField(632, 304, "Use shift lock in fights", "Minions.shiftLock", 1)
        this._BoolField(632, 342, "Fight the Graveyard boss", "Minions.boss", 1)
        this._BoolField(632, 380, "Hunt in NORMAL too", "Minions.normal", 0)
        p.validate := ObjBindMethod(this, "_HuntingCheck")
        this._SaveBar(p)
    }

    ; "" or why Hunting cannot be saved (checked before cfg is touched).
    _HuntingCheck() {
        secs := UiLogic.UInt(this.Ctrl("Minions.maxSec").Value, 120)
        if (secs < 60 || secs > 900)
            return "hunting: hunt at most 60 to 900 seconds"
        if (Trim(this.Ctrl("Minions.aura").Value) = "")
            return "hunting: name the combat aura"
        return ""
    }

    ; ---- page: Tools ------------------------------------------------------------

    _PageTools(p) {
        g := this._gui
        this._Panel(204, 152, 808, Max(236, 108 + RouteRecorder.Names.Length * 40), "Routes", "Press Record: the macro respawns you like playback does, then press "
            . RouteRecorder.Key " and walk with W A S D / Space, press " RouteRecorder.Key " again to save. Esc cancels. "
            . "Test respawns you, walks the route and presses E / F, so you can see it work. F3 stops it.`n`n"
            . "quest_board and cauldron come recorded by the creator. If yours stops working, Reset puts the creator's recording back. limbo_eden (only for Limbo): stand where the Portable Crack puts you in THE LIMBO (no respawn there), press Record: the camera is re-aimed and turned top-down, then walk to Eden's spot. obby: from a respawn to the green star. memory_match: from a respawn to the Memory Match board.")
        for i, name in RouteRecorder.Names {
            y := 186 + (i - 1) * 40
            Theme.Label(g, "x220 y" y + 5 " w130 h20", name)
            st := Theme.Label(g, "x356 y" y + 5 " w200 h20", "", "muted")
            this._ids["route:" name] := st
            this._ids["routeBtn:" name] := Theme.Button(g, "x560 y" y " w82 h28", "Record", ObjBindMethod(this, "_RouteBtn", name))
            this._ids["routeTest:" name] := Theme.Button(g, "x648 y" y " w62 h28", "Test", ObjBindMethod(this, "_RouteTestBtn", name))
            this._ids["routeReset:" name] := Theme.Button(g, "x716 y" y " w66 h28", "Reset", ObjBindMethod(this, "_RouteResetBtn", name), "quiet")
        }
        this._routeStatus := Theme.Label(g, "x220 y" 194 + RouteRecorder.Names.Length * 40 " w776 h60", "", "muted")
        this._ids["routeStatus"] := this._routeStatus
        p.load := ObjBindMethod(this, "_RoutesLoad")
    }

    _RouteBtn(name, *) => this.RecordRoute(name)
    _RouteTestBtn(name, *) => this.TestRoute(name)
    _RouteResetBtn(name, *) {
        if (this._shown && !Theme.Confirm(this._gui, "Reset " name "?", "Your recording of " name " is replaced by the creator's default recording.", "Reset"))
            return
        this.ResetRoute(name)
    }

    ; Copies route `name` from the shipped defaults (RouteRecorder.DefaultsPath,
    ; or `path`) into data\routes.json. -> true when reset.
    ResetRoute(name, path := "") {
        path := (path = "") ? RouteRecorder.DefaultsPath : path
        def := ""
        try def := Json.Parse(FileRead(path, "UTF-8"))
        if !(def is Map && def.Has(name)) {
            Theme.SetText(this._routeStatus, name ": no default recording to reset to.")
            return false
        }
        ; a routes.json that does not parse loads as empty: saving now would
        ; replace every recording with this one route (review)
        if (this.cfg.DataStatus("routes") = "bad") {
            Theme.SetText(this._routeStatus, name ": data\routes.json does not parse; fix or restore it first (nothing changed).")
            return false
        }
        live := this.cfg.Data("routes")
        if (live is Map && live.Has("routes") && live["routes"] is Map)
            live := live["routes"]
        live[name] := Json.Parse(Json.Stringify(def[name]))
        this.cfg.SaveData("routes")
        this._RoutesLoad()
        Theme.SetText(this._routeStatus, name ": reset to the default recording.")
        this.Log("Routes: " name " reset to the default recording")
        return true
    }

    ; "N steps (recorded <stamp>)" | "not recorded"
    _RouteText(name) {
        r := ""
        try r := this.cfg.Data("routes")
        if (r is Map && r.Has("routes") && r["routes"] is Map)
            r := r["routes"]
        if !(r is Map && r.Has(name)) {
            b := RouteRecorder.BuiltinWalk(r, name, this.cfg.Get("General.vip", 1) != 0)
            return IsObject(b) ? b.label ", " b.steps.Length " steps" : "not recorded"
        }
        e := r[name]
        steps := (e is Array) ? e : (e is Map && e.Has("steps") && e["steps"] is Array) ? e["steps"] : []
        if (steps.Length = 0)
            return "not recorded"
        stamp := (e is Map && e.Has("_recorded")) ? "  (" RegExReplace(String(e["_recorded"]), "^\d{4}-") ")" : ""
        return steps.Length " steps" stamp
    }

    _RoutesLoad() {
        for name in RouteRecorder.Names
            Theme.SetText(this._ids["route:" name], this._RouteText(name))
    }

    RecordRoute(name) {
        res := ""
        if this._shown
            this._gui.Minimize()
        try {
            res := this._cb.Has("recordRoute") ? this._cb["recordRoute"].Call(name) : this._RecordRouteDirect(name)
        } catch Any as e {
            res := {ok: false, msg: "not saved: " e.Message}
        }
        if this._shown
            this._gui.Restore()
        msg := (IsObject(res) && res.HasProp("msg")) ? res.msg : "not saved"
        Theme.SetText(this._routeStatus, name ": " msg)
        if !this._cb.Has("recordRoute")
            this.Log("Route recorder: " msg)
        this._RoutesLoad()
        return res
    }

    TestRoute(name) {
        if !this._cb.Has("testRoute") {
            Theme.SetText(this._routeStatus, name ": Test needs the running " Brand.Name " app.")
            return {ok: false, msg: "no app"}
        }
        Theme.SetText(this._routeStatus, name ": testing... watch Roblox (F3 stops).")
        if this._shown
            this._gui.Minimize()
        try {
            res := this._cb["testRoute"].Call(name)
        } catch Any as e {
            res := {ok: false, msg: "test failed: " e.Message}
        }
        if this._shown
            this._gui.Restore()
        msg := (IsObject(res) && res.HasProp("msg")) ? res.msg : "test failed"
        Theme.SetText(this._routeStatus, name ": " msg)
        return res
    }

    _RecordRouteDirect(name) {
        res := RouteRecorder.Run(name, this.cfg.dataDir "\routes.json")
        if (res.ok && IsObject(res.routes))
            this.cfg.SetData("routes", res.routes)
        return res
    }

    ; ---- page: Dev tools ------------------------------------------------------------

    _PageDevTools(p) {
        g := this._gui
        this._Panel(204, 152, 396, 212, "Test events (dev)", "Sends a fake LIVE event through the running macro so you can check "
            . "webhooks, the potion dry run and the merchant visit. Refused unless Potion dry run is ON. "
            . "Webhooks are marked [TEST].")
        this._ids["testEvent:biome"] := Theme.Button(g, "x220 y186 w220 h30", "Fake GLITCHED biome", (*) => this.TestEvent("biome"))
        this._ids["testEvent:merchant"] := Theme.Button(g, "x220 y224 w220 h30", "Fake Mari arrival", (*) => this.TestEvent("merchant"))
        this._testStatus := Theme.Label(g, "x220 y268 w364 h80", "", "muted")
        this._ids["testStatus"] := this._testStatus
    }

    TestEvent(kind) {
        msg := this._cb.Has("testEvent") ? this._Fire("testEvent", kind) : "Test events need the running " Brand.Name " app."
        Theme.SetText(this._testStatus, String(msg))
        return msg
    }

    ; ---- page: Credits ----------------------------------------------------------

    _PageCredits(p) {
        g := this._gui
        this._Panel(204, 152, 808, 176, "Creator")
        pic := Theme.AssetPath("credits\avatar.png")
        if FileExist(pic)
            this._ids["credits.avatar"] := Theme.Add(g, "Picture", "x220 y184 w128 h128", pic)
        this._ids["credits.name"] := Theme.Label(g, "x368 y190 w600 h36", Credits.Name(), "head")
        Theme.Label(g, "x368 y230 w600 h20", "Creator of " Brand.Name, "muted")
        this._ids["credits.discord"] := Theme.Label(g, "x368 y256 w600 h20", "Discord: " Credits.Discord(), "body")
        this._Panel(204, 344, 808, 80, "A message from " Credits.Name())
        this._ids["credits.message"] := Theme.Label(g, "x220 y372 w776 h40", Chr(0x201C) Credits.Message() Chr(0x201D), "body")
        this._Panel(204, 440, 808, 112, "Discord server")
        Theme.Label(g, "x220 y468 w776 h20", Credits.Server(), "muted")
        this._ids["credits.join"] := Theme.Button(g, "x220 y496 w180 h30", "Join the Discord", (*) => this._OpenDiscord(), "primary")
    }

    _OpenDiscord() {
        try Run(Brand.DiscordUrl)
    }

    ; ---- page: Log --------------------------------------------------------------

    _PageLog(p) {
        g := this._gui
        this._Panel(204, 152, 808, 464)
        this._logEdit := Theme.Edit(g, 216, 164, 784, 440, "", "Multi ReadOnly -WantReturn VScroll")
        Theme.Button(g, "x204 y628 w100 h30", "Clear", (*) => (this._logBuf.Clear(), this._FlushLog()), "quiet")
        Theme.Button(g, "x312 y628 w100 h30", "Copy", (*) => (A_Clipboard := this._logBuf.Text()))
        this._logCount := Theme.Label(g, "x612 y634 w400 h20 Right", "", "muted")
    }
}
