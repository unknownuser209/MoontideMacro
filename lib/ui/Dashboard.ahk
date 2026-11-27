#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\Theme.ahk
#Include %A_LineFile%\..\Anim.ahk
#Include %A_LineFile%\..\Layout.ahk
#Include %A_LineFile%\..\Search.ahk
#Include %A_LineFile%\..\HelpTexts.ahk
#Include %A_LineFile%\..\..\Credits.ahk
#Include %A_LineFile%\..\UiLogic.ahk
#Include %A_LineFile%\..\..\Config.ahk
#Include %A_LineFile%\..\..\GameLists.ahk
#Include %A_LineFile%\..\..\Calibrate.ahk
#Include %A_LineFile%\..\..\SetupCheck.ahk
#Include %A_LineFile%\..\..\Clip.ahk
#Include %A_LineFile%\..\..\Updater.ahk
#Include %A_LineFile%\..\..\RouteRecorder.ahk
#Include %A_LineFile%\..\..\tasks\BiomeItems.ahk
#Include %A_LineFile%\..\..\tasks\MemoryMatch.ahk
#Include %A_LineFile%\..\..\Profiles.ahk
#Include %A_LineFile%\..\..\Backup.ahk
; ---------------------------------------------------------------------------
; Dashboard: the main Moontide Macro window (1040x680). The sidebar lists seven
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
;                                                Biomes or Potions Save. PotionSafety
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
;         "testWebhook"                (index)   Discord & Clips > Discord row "Test" button
;                                                (index of the SAVED webhook) ->
;                                                status text shown in the page
;                                                status line (scrubbed again)
;         "testEvent"                  (kind)    Help > Dev tools test buttons
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
;   d.RecordRoute(name), d.TestRoute(name)   (Help > Routes buttons)
;   d.TestEvent(kind)                        (Help > Dev tools buttons)
;   d.SelectHub(i)   hub i on its last-opened tab (its first tab at start)
;   d.SelectPage(i)  page i of Dashboard.Pages, with its hub and tab
;   d.SavePage(name), d.RevertPage(name), d.LogText(), d.ActivePage (name),
;   d.ActiveHub (index), d.PageOf(ctrl) (page name), d.Ctrl(id), d.Hwnd
;       (tests / harness). Header ids: "hub:" hub name, "hubTitle",
;       "tab:" page, "tabDot:" page, "tabUnderline", "desc:" page.
;   d.Cards(page)  the page's cards in build order, each {id, title, frame,
;       fill, caption, ctrls, x, y, w, h} (100 % units); d.CardOf(ctrl) its
;       card id: "<page>:<English title>", "<page>:#<n>" (untitled),
;       "<page>:fixed" (subtitle, save bar, Calibrate / Log bottom bar),
;       "<page>:loose" (before the first card; no page has any), "" (not a
;       page control).
;   Look (the theme editor, lib\ui\ThemeStore.ahk): d.LookSelect(name),
;       d.LookSet(key, value) -> true when taken, d.LookSave() -> true | why,
;       d.LookDuplicate() -> new name | "", d.LookRename(new), d.LookDelete(),
;       d.LookExport() -> path | "", d.LookImport(path) -> {name} | {error},
;       d.DropFiles(paths) (WM_DROPFILES: one .moontheme is imported),
;       d.ApplyTheme() (refused while another page has unsaved edits),
;       d.EditLayout(on). Ids "look:<part>" (look:list, look:color:<key>,
;       look:auto:<key>, look:font:<role>, look:size:<role>, look:note ...).
;       Hooks tests replace: _lookAsk, _pickColor, _pickFile, _pickTheme,
;       _askName, _importOk, _openFolder.
;   Edit layout mode (EditLayout(true)): d.DragCard(id, dx, dy),
;       d.ResizeCard(id, dw, dh), d.ToggleCard(id), d.ResetCard(id),
;       d.ResetPage(page), d.ResetLayout() -> true | false; d.LayoutDone()
;       -> true | why (saves into the open theme), d.LayoutCancel();
;       d.LayoutEntries(), d.LayoutOutline(id) ("red" | "dashed" | ""),
;       d.Dragging(). Ids "layout:handle|grip|eye|reset|outline:<card id>",
;       "layout:done", "layout:cancel", "layout:resetPage", "layout:note".
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
;   "moon"      loop 3200 ms: header logo through assets\ui\moon_0..11.png (theme-tinted)
;   "stars"     loop: 8 stars in the header / sidebar, each its own period
; Loops start in Show() and after a Look save (UI.animations may have
; changed); WM_ACTIVATE on the window calls Anim.Wake() so frozen loops resume.
;
; No polling.
;
; Config keys written (Section.key, default):
;   General: fishing 1 (0 = never fish), sellEvery 15 (min 1), sellAll 1,
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
;   UI (Settings > Look): animations 1, theme "Moontide", lang "en" (lib\I18n.ahk;
;     the theme in use and the language show after Apply or the next start;
;     the themes themselves live in <cfg dir>\themes, lib\ui\ThemeStore.ahk)
;   Limbo: enabled 0 (Farming > Limbo)
;   Medal (Discord & Clips > Clips): enabled 0, clipHotkey F8 (Clips save refuses a key that
;     Clip.HotkeyProblem rejects: not F4-F24, or a macro / capture /
;     recorder key), delaySec 3, cooldownSec 30, onRareBiome 1,
;     onRareAura 0, auras "", auraMinRarity 100000000 (field shows commas,
;     accepts "100m" / "1b" / "1,000,000,000"; unparsable -> not saved),
;     auraAlwaysCategories "Challenged,Challenged+"
;   Settings > Profiles (lib\Profiles.ahk): a profile button sets its keys, saves
;     at once and reloads every other page (unsaved edits there are dropped);
;     Export writes <cfg dir>\exports\moontide_settings_<yyyyMMdd>.ini without
;     secrets; Import merges the shareable keys of a chosen .ini (never
;     webhooks, links, the bot or dry run). d.ApplyProfile(name),
;     d.ExportSettings(), d.ImportSettings(path) (tests). Ids: "profile:<name>",
;     "profileStatus", "export", "exportShow", "import", "shareStatus".
;     Move to another PC (lib\Backup.ahk): "Export everything" writes every
;     setting (secrets too), the user's data files and themes to
;     exports\moontide_backup_<stamp>.json; "Import everything" (refused
;     while the app says "backupBusy") checks, asks, saves the current state
;     first, writes, reloads cfg and the pages, then fires "backupImported"
;     (the App restarts). d.ExportEverything(), d.ImportEverything(path);
;     ids "backupWarn", "backupExport", "backupImport", "backupStatus".
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
    static MoonMax := 16          ; header moon frames looked for (assets\ui\moon_0.., 12 shipped)
    static H := 680
    ; Internal page names (SavePage / tests); the user sees TabLabel(name).
    static Pages := ["Run", "Fishing", "Craft", "Quests", "Merchants", "Biomes & Potions", "Biome items", "Obby & Memory", "Webhooks", "Calibrate", "Settings", "Tools", "Limbo", "Clips", "Dev tools"
        , "Stats", "Hunting", "Summary", "Remote", "Check", "Schedule", "Credits", "Log", "Profiles", "Potions", "Look"
        , "Plugins", "Plugin settings", "Plugin page"]
    static Builders := ["_PageRun", "_PageFishing", "_PageCraft", "_PageQuests", "_PageMerchants", "_PageBiomes", "_PageBiomeItems", "_PageObbyMemory", "_PageWebhooks", "_PageCalibrate", "_PageSettings", "_PageTools", "_PageLimbo", "_PageClips", "_PageDevTools"
        , "_PageStats", "_PageHunting", "_PageSummary", "_PageRemote", "_PageCheck", "_PageSchedule", "_PageCredits", "_PageLog", "_PageProfiles", "_PagePotions", "_PageLook"
        , "_PagePlugins", "_PagePluginSettings", "_PagePluginPage"]
    static Subtitles := [
        "Status at a glance. F1 start  " Chr(0xB7) "  F2 pause / resume  " Chr(0xB7) "  F3 stop",
        "Selling rhythm, minigame mode and failsafes.",
        "Potions bought at the Fisher, and the optional Stella cauldron step.",
        "Which quests the board may accept.",
        "Mari and Jester want-lists. Items are found by name in the shop.",
        "Rare biomes and the potions used in them.",
        "Strange Controller, Biome Randomizer and Biome Selector, used off cooldown in the biomes you allow.",
        "The obby for the Basic Blessing, and the Memory Match board.",
        "Discord webhooks and the events each one receives.",
        "Record the click points new features need.",
        "Private server, routes, intervals, recovery, alerts and hotkeys.",
        "Record, test and reset the walking routes.",
        "Wait in THE LIMBO for Eden instead of fishing.",
        "Clips of rare biomes and rare auras.",
        "Send fake events through the running macro (dry run only).",
        "Today, this run and the last 7 days.",
        "Orb & boss hunting, a built-in plugin (the Limited tab before).",
        "One Discord message a day with what the macro did.",
        "Control the macro from Discord with your own bot.",
        "Check what the macro can see on your PC, and make a log zip for support.",
        "Start and stop by the clock, or stop after a number of hours.",
        "Who made " Brand.Name ".",
        "The newest 200 lines. Links and webhook URLs are always hidden.",
        "One-click setups, and your settings in a file to share (no webhooks or links).",
        "Every potion: unlock or re-lock it, and its safety caps.",
        "The theme, the animations and the language of this window.",
        "Extra features: built in, or files you drop into the plugins folder.",
        "A plugin's own settings.",
        "A plugin's own page."
    ]
    ; Sidebar hubs, each a tab strip of pages (every page is in exactly one).
    ; icon: a glyph name (not drawn yet).
    static Hubs := [
        {name: "Home", icon: "home", pages: ["Run", "Stats", "Log"]},
        {name: "Farming", icon: "bolt", pages: ["Fishing", "Craft", "Merchants", "Limbo"]},
        {name: "Quests & events", icon: "star", pages: ["Quests", "Obby & Memory", "Biome items"]},
        {name: "Biomes & Potions", icon: "moon", pages: ["Biomes & Potions", "Potions"]},
        {name: "Discord & Clips", icon: "bell", pages: ["Webhooks", "Clips", "Summary", "Remote"]},
        {name: "Plugins", icon: "puzzle", pages: ["Plugins", "Hunting", "Plugin settings", "Plugin page"]},
        {name: "Settings", icon: "gear", pages: ["Settings", "Look", "Schedule", "Profiles"]},
        {name: "Help", icon: "info", pages: ["Check", "Calibrate", "Tools", "Dev tools", "Credits"]}
    ]
    static TabLabels := Map("Run", "Overview", "Craft", "Crafting", "Biomes & Potions", "Biomes", "Webhooks", "Discord", "Tools", "Routes"
        , "Summary", "Daily summary", "Check", "Check & help", "Settings", "General", "Hunting", "Orb & boss hunting")
    ; Plugin pages: opened from the Plugins tab (Settings), no tab of their
    ; own (the Plugins tab stays lit), found by search like any page
    static SubPages := Map("Hunting", "Plugins", "Plugin settings", "Plugins", "Plugin page", "Plugins")
    static MaxHooks := 8
    static Events := ["biome", "rare", "merchant", "quests", "craft", "errors", "startstop", "potions", "clips", "obby", "memorymatch", "sinister"]
    static EventCaps := ["Biome", "Rare", "Merchant", "Quests", "Craft", "Errors", "Stop", "Potions", "Clips", "Obby", "Memory", "Boss"]
    ; one column per event: 12 x 28 px end before the Test button (x 920);
    ; at 38 px the obby / memorymatch boxes (added later, without captions)
    ; sat on top of Test and X and took their clicks (review 2026-10-27).
    ; "Boss" = sinister: the bosses' messages (MinionsTask, the chat) and,
    ; since 2026-11-22, the orbs' from the chat (Hunting.orbAlert)
    ; Captions (translated, 2026-11-19): two rows, odd columns above, even
    ; below, each EventCapW wide and centred on its column, so neighbours in
    ; a row are two columns apart and never touch (28 px captions ran into
    ; each other: "3iome", "MerchQuest"); a caption still too wide gets a
    ; smaller font (Theme.FitFont).
    static EventCapW := 54
    ; The caption of event column `s` (an EventCaps entry): the language's
    ; short column word when it has one (key "<s> (column)": fil "Potion"
    ; for "Mga potion", vi "Lai buon" for "Thuong nhan"), else the usual
    ; translation. Neighbours in a caption row keep a visible gap.
    static EventCap(s) => I18n.TC(s, "column")
    static HeadRows := [172, 187]          ; y of the upper / lower caption row (14 px each)
    static EventPitch := 28
    static EventBoxDx := 6
    static LogPage := 23
    ; animation look
    static PulseDark := "B5772A"       ; darker gold the Running pill pulses to
    static StarC := "F7F1E8"
    ; [x, y, period ms]: header stars clear of the brand, credits banner
    ; (x 372..612, y 17..43), status pill and buttons (y 16..44); sidebar
    ; stars between the hub list (8 hubs, ends y 422) and the chip (y 622).
    static Stars := [[392, 3, 2300], [548, 45, 2700], [700, 3, 2000], [902, 45, 3100]
        , [34, 448, 2500], [140, 486, 2900], [70, 534, 2150], [150, 580, 2650]]
    ; first hub of the left / right sidebar (the search box sits above it)
    static HubTop := 108
    static StatTiles := [["stat:loops", "LOOPS"], ["stat:fish", "FISH CAUGHT"], ["stat:biomes", "BIOMES SEEN"], ["stat:rare", "RARE BIOMES"]]
    static _wins := Map()              ; Dashboard window hwnds (WM_ACTIVATE -> Anim.Wake)
    static _actHooked := false

    ; Header stars used in top mode instead of the sidebar ones (the hub row
    ; has no free room): y 3 or 45, clear of the brand, banner, pill and buttons.
    static StarsTop := [[470, 3, 2500], [620, 45, 2900], [800, 3, 2150], [980, 45, 2650]]

    ; "left" | "right" | "top"; anything else is "left".
    static NormSide(s) => (s = "right" || s = "top") ? s : "left"

    ; How far the page (and its tab strip) moves for a sidebar side, and how
    ; much taller the window gets: {dx, dy, extraH}. Right: the page moves
    ; 176 px left (the sidebar is drawn at x 864); top: 176 px left and 48 px
    ; down (the hubs are one row at y 59..107).
    static PageShift(side) {
        side := Dashboard.NormSide(side)
        return side = "right" ? {dx: -176, dy: 0, extraH: 0} : side = "top" ? {dx: -176, dy: 48, extraH: 48} : {dx: 0, dy: 0, extraH: 0}
    }

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
        this._cards := Map()          ; page name -> Array of cards (Cards)
        this._cardOf := Map()         ; ctrl hwnd -> card id (CardOf)
        this._fixed := Map()          ; hwnds of the subtitle / save bar while building
        this._hidden := Map()
        this._layoutHidden := Map()   ; ctrl hwnd -> true: hidden by the theme's layout (ApplyLayout)
        ; edit layout mode (EditLayout): the overlay window, its controls per
        ; card, the handles and grips, outline states, the layout being edited
        this._editLayout := false
        this._edSaving := false
        this._edGui := ""
        this._edCtl := Map()
        this._edHot := Map()
        this._edState := Map()
        this._lay := Map()
        this._layStart := Map()
        this._layFrom := ""
        this._drag := ""
        this._dragFn := ""
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
        ; Settings > Profiles: apply a profile (yes / no), the file to import ("" = cancel)
        this._confirmProfile := (title, text) => Theme.Confirm(this._gui, title, text, "Apply", "Cancel")
        this._pickImport := () => this._PickIni()
        ; Move to another PC: the backup to import ("" = cancel), the yes / no
        ; before it, and the export shown in Explorer
        this._pickBackup := () => this._PickBackupFile()
        this._confirmBackup := (title, text) => Theme.Confirm(this._gui, title, text, "Import", "Cancel")
        this._reveal := (path) => Run('explorer.exe /select,"' path '"')
        this._bigWarned := ""
        this._scaleNote := ""
        this._side := Dashboard.NormSide(Theme.Sidebar)
        this._sh := Dashboard.PageShift(this._side)
        this._FitUiSize()
        this._Build()
        this._HookDrop()
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
        if (this._bgNote != "")
            this.Log(this._bgNote)
        if (this._scaleNote != "")
            this.Log(this._scaleNote)
    }

    ; The theme's UI size, or the largest smaller one that fits the primary
    ; monitor's work area (the window is never bigger than the screen). Sets
    ; Theme.Scale to the size used and notes a refusal for the log.
    _FitUiSize() {
        want := Theme.Scale
        wa := {w: 99999, h: 99999}
        try wa := Theme.WorkAreaFn.Call()
        use := Theme.FitScale(want, wa.w, wa.h, Dashboard.W, Dashboard.H + this._sh.extraH)
        if (use != want) {
            Theme.Scale := use
            this._scaleNote := "UI size " want " % does not fit this screen, using " use " %"
        }
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

    ; The cards of a page in build order (an empty Array for an unknown page).
    ; Each: {id, title, frame, fill, caption, ctrls, x, y, w, h}. id is
    ; "<page>:<English title>" or "<page>:#<n>" (n counts the untitled cards);
    ; caption is "" for an untitled card; ctrls holds every control the page
    ; builder made from this card's _Panel to the next (frame, fill and
    ; caption included); x/y/w/h are the frame's place in 100 % units when
    ; the page was built.
    Cards(page) => this._cards.Has(page) ? this._cards[page] : []

    ; The card id of a page control, "<page>:fixed" for the subtitle and the
    ; save bar, "<page>:loose" for one made before the page's first card,
    ; "" for anything else (header, sidebar, not a control).
    CardOf(ctrl) {
        try {
            if (IsObject(ctrl) && this._cardOf.Has(ctrl.Hwnd))
                return this._cardOf[ctrl.Hwnd]
        }
        return ""
    }

    ; The area a card may lie in: {x, y, w, h} in 100 % units (below the
    ; subtitle, above the bottom bar). Left: x 204..1012; right: the page
    ; is 176 px further left; top: also 48 px down and the 176 px freed on
    ; the right belong to the page.
    PageArea() {
        a := {x: 204 + this._sh.dx, y: 152 + this._sh.dy, w: 808, h: 468}
        if (this._side = "top")
            a.w := 984
        return a
    }

    ; The box under the page (picture, fade cover): {x, y, w, h} in 100 %
    ; units. Left: x 176, y 150, 864 x 470; right: from x 0; top: from x 0,
    ; 48 px lower and the whole window wide.
    PageBox() {
        if (this._side = "right")
            return {x: 0, y: 150, w: 864, h: 470}
        if (this._side = "top")
            return {x: 0, y: 198, w: 1040, h: 470}
        return {x: 176, y: 150, w: 864, h: 470}
    }

    ; The background picture's rectangle (x, y, w, h), 100 % units.
    _PicBox() {
        if (this._side = "right")
            return {x: 0, y: 60, w: 864, h: 620}
        if (this._side = "top")
            return {x: 0, y: 108, w: 1040, h: 620}
        return {x: 176, y: 60, w: 864, h: 620}
    }

    ; Take the cards of `page` to the entries of layoutMap (Map card id ->
    ; [x, y, w, h, hidden]; x / y are page places, the place with the sidebar
    ; at the left, so a layout keeps working when the sidebar moves: the page
    ; shift is added here and taken off when an entry is written, _EdPlace):
    ; each card's controls move by the same (dx, dy),
    ; its frame gets w x h and its fill w-2 x h-2, and a hidden card's
    ; controls are all hidden (they stay hidden when the page is shown).
    ; Only a card with an entry is placed and clamped to PageArea(); a card
    ; without one stays where the builder put it (back at its built place
    ; if an earlier call moved it) and is shown. Entries that are no good,
    ; unknown ids and unknown pages are ignored; never throws.
    ApplyLayout(page, layoutMap) {
        try {
            if !(layoutMap is Map)
                layoutMap := Map()
            area := this.PageArea()
            for card in this.Cards(page) {
                try {                                   ; one bad card never skips the rest of the page
                    if !card.HasProp("ox")
                        card.ox := card.x, card.oy := card.y, card.ow := card.w, card.oh := card.h
                    e := layoutMap.Has(card.id) ? Layout.Place(card, this._LayIn(layoutMap[card.id]), area) : ""
                    if IsObject(e) {
                        this._PlaceCard(card, card.x + e.dx, card.y + e.dy, e.w, e.h)
                        this._LayoutHide(card, e.hidden)
                    } else {
                        if (card.x != card.ox || card.y != card.oy || card.w != card.ow || card.h != card.oh)
                            this._PlaceCard(card, card.ox, card.oy, card.ow, card.oh)
                        this._LayoutHide(card, false)
                    }
                } catch Any as err {
                    try OutputDebug("Dashboard.ApplyLayout: card " card.id " failed: " err.Message)
                }
            }
        } catch Any as err {
            try OutputDebug("Dashboard.ApplyLayout failed: " err.Message)
        }
    }

    ; A layout entry (page places) -> the same entry in this window's places
    ; (the page shift added). Anything else comes back as it is, for
    ; Layout.Place to refuse.
    _LayIn(e) {
        try {
            if (e is Array && e.Length >= 4 && IsNumber(e[1]) && IsNumber(e[2])) {
                out := e.Clone()
                out[1] := Number(e[1]) + this._sh.dx, out[2] := Number(e[2]) + this._sh.dy
                return out
            }
        }
        return e
    }

    ; A card's place as a layout entry (page places: the page shift taken off).
    _LayOut(card, hid) => [card.x - this._sh.dx, card.y - this._sh.dy, card.w, card.h, hid ? 1 : 0]

    _PlaceCard(card, nx, ny, nw, nh) {
        ; the frame goes to its place; the rest moves by the frame's real
        ; (Gui px) step, so nothing rounds apart at 115 / 130 %, and the fill
        ; is put back 1 px inside the frame
        card.frame.GetPos(&fx0, &fy0)
        Theme.MoveTo(card.frame, nx, ny, nw, nh)
        card.frame.GetPos(&fx, &fy)
        rdx := fx - fx0, rdy := fy - fy0
        for c in card.ctrls {
            if (c = card.frame)
                continue
            if (c = card.fill) {
                Theme.Inset(card.frame, c)
                continue
            }
            if (rdx || rdy) {
                c.GetPos(&cx, &cy)
                c.Move(cx + rdx, cy + rdy)
            }
        }
        card.x := nx, card.y := ny, card.w := nw, card.h := nh
        Theme.RepaintCtrl(card.frame)
    }

    ; Hide (or give back) every control of a card; a control that comes
    ; back follows its own rule again (_hidden, and the page being shown).
    _LayoutHide(card, hide) {
        for c in card.ctrls {
            if hide
                this._layoutHidden[c.Hwnd] := true
            else if this._layoutHidden.Has(c.Hwnd)
                this._layoutHidden.Delete(c.Hwnd)
            onPage := !this._ctrlPage.Has(c.Hwnd) || this._ctrlPage[c.Hwnd] = this._active
            want := !hide && onPage && !this._hidden.Has(c.Hwnd)
            if (c.Visible != want) {
                c.Visible := want
                if !want
                    Theme.RepaintCtrl(c)
            }
        }
    }

    ; ---- public ---------------------------------------------------------------

    ; The window's client size as shown: {w, h} in Gui units (UI size and the
    ; sidebar side counted). Show and the offscreen mode both use it.
    ShownSize() => {w: Theme.S(Dashboard.W), h: Theme.S(Dashboard.H + this._sh.extraH)}

    ; activate false: shown without taking focus (tests: a live macro
    ; pauses when Roblox loses the front)
    Show(activate := true) {
        na := activate ? "" : " NoActivate"
        if !this._shown {
            sz := this.ShownSize()
            this._gui.Show("w" sz.w " h" sz.h " Center" na)
            this._shown := true
        } else
            this._gui.Show(Trim(na))
        if activate
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
        try this._EdEnd()                     ; the drag loop and the edit overlay
        try this._FlashStop()
        try this._SearchHotkeysOff()
        for k in ["underline", "fade", "count", "pulse", "moon", "stars"]
            Anim.Stop(k)
        try Dashboard._wins.Delete(this._gui.Hwnd)
        try Dashboard._drops.Delete(this._gui.Hwnd)
        try Theme.Forget(this._gui)
        try this._gui.Destroy()
        this._FreeMoon()
        this._Unlink()
    }

    ; After Destroy: every field that holds a function (the hooks and timer
    ; functions made with `this` inside them), a map or a list (cards, ids,
    ; pages with their bound load / save, the search index...) lets go, so
    ; nothing points back at this object and AutoHotkey frees it. Maps and
    ; lists become empty ones, functions "", so a late call finds nothing
    ; instead of a dead window.
    _Unlink() {
        names := []
        for name in this.OwnProps()
            names.Push(name)
        for name in names {
            try {
                v := this.%name%
                if (v is Func)
                    this.%name% := ""
                else if (v is Map)
                    this.%name% := Map()
                else if (v is Array)
                    this.%name% := []
                else if (IsObject(v) && !(v is Gui) && !(v is Gui.Control) && name != "cfg")
                    this.%name% := ""
            }
        }
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

    ; Home's NEXT UP cell ("Quests in 12 min"; "" = nothing timed / stopped)
    SetNext(text) {
        t := (text = "") ? Chr(0x2014) : text
        if (this._stNext.Text != t)
            Theme.SetText(this._stNext, t)
    }

    SetStatus(state, task := "", biome := "", rare := false, uptimeMs := 0, loops := 0) {
        st := UiLogic.NormState(state)
        up := UiLogic.Uptime(uptimeMs)
        key := st "|" task "|" biome "|" (rare ? 1 : 0) "|" up "|" loops
        if (key == this._statusKey)
            return
        this._statusKey := key
        pl := I18n.T((st = "Paused") ? "Resume" : "Pause")
        for b in this._pauseBtns {
            if (b.Text != pl)
                b.Text := pl
        }
        switch st {
            case "Running": bg := Theme.Accent, fg := Theme.Ink, vc := Theme.Accent
            case "Paused": bg := Theme.PanelC, fg := Theme.Text, vc := Theme.Text
            default: bg := Theme.OffBg, fg := Theme.Muted, vc := Theme.Muted
        }
        pill := Chr(0x25CF) "  " StrUpper(I18n.T(st))
        if (this._pill.Text != pill) {
            this._pill.Text := pill
            Theme.SetColors(this._pill, bg, fg)
            this._stState.Text := I18n.T(st)
            Theme.SetColors(this._stState, Theme.CardBg, vc)
        }
        Theme.SetText(this._stTask, task = "" ? Chr(0x2014) : UiLogic.TaskText(task))
        bText := biome = "" ? Chr(0x2014) : biome (rare ? "   " Chr(0x2726) " " I18n.T("rare") : "")
        if (this._stBiome.Text != bText) {
            this._stBiome.Text := bText
            Theme.SetColors(this._stBiome, Theme.CardBg, rare ? Theme.Accent : Theme.Text)
        }
        Theme.SetText(this._stUp, up)
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
        this._FlashStop()
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
                c.Visible := !this._hidden.Has(c.Hwnd) && !this._layoutHidden.Has(c.Hwnd)
                if (c.Type = "ListView" && c.Visible)
                    Theme.FitLastCol(c)                ; scrollbar size is final once shown
            }
            if (i = 1 || i = Dashboard.LogPage)
                this._FlushLog()
            if (i = 1)
                this._CountUp()
            if (this._pages[i].HasProp("onShow") && IsObject(this._pages[i].onShow))
                try this._pages[i].onShow.Call()
            if this._editLayout
                this._EdBuild()                        ; the handles of the page now shown
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
        if (i < 1 || i > Dashboard.Hubs.Length || !this._ShownIn(i).Length)
            return
        last := this._hubLast.Has(i) ? this._hubLast[i] : 0
        this.SelectPage((last && this.PageShown(Dashboard.Pages[last])) ? last : Dashboard.PageIndex(this._ShownIn(i)[1]))
    }

    ; a tab in its hub's strip (plugin pages have none: Dashboard.SubPages)
    TabShown(name) => this.PageShown(name) && !Dashboard.SubPages.Has(name)
    ; the tab lit for page `name`: its own, or the Plugins tab for a plugin page
    static TabFor(name) => Dashboard.SubPages.Has(name) ? Dashboard.SubPages[name] : name

    ; Plugins > Settings of a plugin: its page (built-in ones) or the
    ; Plugin settings page filled with its manifest's settings
    OpenPluginPage(id) {
        host := this._Host()
        e := IsObject(host) ? host.Find(id) : ""
        if !IsObject(e)
            return false
        if (e["builtin"] && e["page"] != "") {
            this.SelectPage(Dashboard.PageIndex(e["page"]))
            return true
        }
        if this.HasOwnProp("_ppGroups") && this._ppGroups.Has(id) {
            this._ppId := id
            for gid, grp in this._ppGroups
                this._HideParts(grp.parts, gid != id)
            pg := this._PageByName("Plugin page")
            this._LoadPage(pg)
            this.SelectPage(Dashboard.PageIndex("Plugin page"))
            return true
        }
        this._psId := id
        this._LoadPage(this._PageByName("Plugin settings"))
        this.SelectPage(Dashboard.PageIndex("Plugin settings"))
        return true
    }

    ; Dev tools only in the owner's dev copy (Updater.IsDevCopy); every other
    ; page shows (simple mode was removed 2026-11-22)
    PageShown(name) => (name != "Dev tools" || this._IsDev())

    _IsDev() {
        if !this.HasOwnProp("_dev")
            this._dev := Updater.IsDevCopy(this.cfg.dir)
        return this._dev
    }

    ; hub h's pages that show now
    _ShownIn(h) {
        out := []
        for p in Dashboard.Hubs[h].pages
            if this.TabShown(p)
                out.Push(p)
        return out
    }

    ; the hub buttons: hidden hubs leave no gap
    _LayoutNav() {
        vi := 0
        for i, hub in Dashboard.Hubs {
            on := this._ShownIn(i).Length > 0
            this._nav[i].Visible := on
            this._navBar[i].Visible := on
            if (on && this._side != "top") {
                y := Dashboard.HubTop + vi * 40
                Theme.MoveTo(this._nav[i], , y)
                Theme.MoveTo(this._navBar[i], , y)
                vi++
            }
        }
        if (this._side = "top")
            this._TopRow()
    }

    ; Top sidebar: the shown hubs in one row from x 12 (6 px apart), then the
    ; magnifier and the chip from the row's end
    ; (TopTail wide, ending by x 1020). A row that does not fit (long names,
    ; a big Menu font) first loses hub padding (24 down to 8), then font size
    ; for this row only (down to 7 pt); a hub's text also has to fit its
    ; 34 px height.
    static TopTail := 188          ; magnifier 32 + 8 + chip 148
    _TopRow() {
        shown := []
        for i, c in this._nav
            if c.Visible
                shown.Push(i)
        room := Dashboard.W - 20 - Dashboard.TopTail - 8 - 12 - 6 * Max(shown.Length - 1, 0)
        base := 10
        try {
            if RegExMatch(Theme.Fonts["nav"][1], "(?<=^|\s)s(\d+)", &m)
                base := Integer(m[1])
        }
        fs := Max(base, 7), pad := 24
        Loop {
            this._NavFont(fs)
            sum := 0, tall := 0
            tws := Map()
            for i in shown {
                t := this._TextSize(this._nav[i])
                tws[i] := t.w, sum += t.w, tall := Max(tall, t.h)
            }
            pad := 24
            while (pad > 8 && sum + pad * shown.Length > room)
                pad -= 4
            if (fs <= 7 || (sum + pad * shown.Length <= room && tall <= 32))
                break
            fs--
        }
        tx := 12
        for i in shown {
            w := tws[i] + pad
            this._navW[i] := w
            Theme.MoveTo(this._nav[i], tx, 64, w, 34)
            Theme.MoveTo(this._navBar[i], tx, 100, w, 3)
            tx += w + 6
        }
        x := Min(tx + 2, Dashboard.W - 20 - Dashboard.TopTail)
        try Theme.MoveTo(this._ids["search:icon"], x, 66)
        Theme.MoveTo(this._chip, x + 40, 65)
    }

    ; The hub buttons' font size (pt at 100 %) for the top row.
    _NavFont(fs) {
        if (this._navFs = fs)
            return
        this._navFs := fs
        px := Theme.IsScaled(this._gui) ? Max(6, Theme.S(fs)) : fs
        fam := "Segoe UI"
        try fam := Theme.Fonts["nav"][2]
        for c in this._nav
            try c.SetFont("s" px, fam)
    }

    ; A Text control's text size with its own font: {w, h} in 100 % units.
    _TextSize(c) {
        w := 0, h := 0
        try {
            hdc := DllCall("GetDC", "Ptr", c.Hwnd, "Ptr")
            old := DllCall("SelectObject", "Ptr", hdc, "Ptr", SendMessage(0x31, 0, 0, c.Hwnd), "Ptr")   ; WM_GETFONT
            sz := Buffer(8, 0)
            t := c.Text
            DllCall("GetTextExtentPoint32W", "Ptr", hdc, "Str", t, "Int", StrLen(t), "Ptr", sz)
            DllCall("SelectObject", "Ptr", hdc, "Ptr", old)
            DllCall("ReleaseDC", "Ptr", c.Hwnd, "Ptr", hdc)
            w := NumGet(sz, 0, "Int"), h := NumGet(sz, 4, "Int")
            if (Theme.IsScaled(this._gui) && Theme.Scale != 100)
                w := Ceil(w * 100 / Theme.Scale), h := Ceil(h * 100 / Theme.Scale)
        }
        return {w: w, h: h}
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
                this._SetPageStatus(page, I18n.T("Not saved:") " " msg, true)
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
            this._SetPageStatus(page, I18n.T("Not saved:") " " msg, true)
            this.Log("Settings: " name " not saved: " msg)
            this._RefreshDot(page)
            return false
        }
        page.dirty := false
        this._Snap(page)
        this._RefreshDot(page)
        this._SetPageStatus(page, I18n.T("Saved") " " FormatTime(, "HH:mm:ss") (note ? "   " note : ""))
        this.Log("Settings: " name " saved")
        if (name = "Look" && this._shown)
            this._StartLoops(true)         ; UI.animations takes effect now
        if this._cb.Has("saved")
            try this._cb["saved"].Call(name)
        return true
    }

    RevertPage(name) {
        page := this._PageByName(name)
        this._LoadPage(page)
        this._SetPageStatus(page, I18n.T("Reverted to saved values"))
    }

    ; ---- build ----------------------------------------------------------------

    _Build() {
        g := Theme.Window(Brand.Name " " Chr(0xB7) " " Credits.ByLine(), "-MaximizeBox", true)
        this._gui := g
        g.OnEvent("Close", (*) => this._OnClose())
        ; the theme's darkened art: panels and text read on it. Custom: none
        ; (BgImage ""), a preset's art, or a picture of the user's own,
        ; darkened and scaled to the art's size (Theme.DimPicture; the
        ; control owns that HBITMAP); a picture that will not load = none
        this._bgNote := ""
        pb := this._PicBox()
        pbOpts := "x" pb.x " y" pb.y " w" pb.w " h" pb.h
        if Theme.IsOwnPicture(Theme.BgImage) {
            sp := Theme.PictureSpec
            hbm := Theme.DimPicture(Theme.BgImage, Theme.S(pb.w), Theme.S(pb.h), Theme.Bg, sp["dim"] / 100, sp["fit"])
            if hbm
                Theme.Add(g, "Picture", pbOpts, "HBITMAP:" hbm)
            else
                this._bgNote := "Theme: the custom background picture could not be loaded, so none is shown"
        } else if (Theme.BgImage != "") {
            bg := Theme.AssetPath(Theme.BgImage)
            if !FileExist(bg)
                bg := Theme.AssetPath("moontide_bg_dim.png")
            if !FileExist(bg)
                bg := Theme.AssetPath("moontide_bg.png")
            if FileExist(bg)
                Theme.Add(g, "Picture", pbOpts, bg)      ; first = painted under everything
        }

        ; header: the moon logo cycles through assets\ui\moon_0..N.png (a
        ; whole cycle, new moon included), decoded once here and tinted to
        ; the theme's Accent (Theme.MoonBitmap: Equinox white) on the header
        ; colour (HBITMAPs owned by the Dashboard, freed in Destroy())
        this._moonFrames := []
        Loop Dashboard.MoonMax {
            f := Theme.AssetPath("ui\moon_" (A_Index - 1) ".png")
            h := 0
            if FileExist(f) {
                try h := Theme.MoonBitmap(f, Theme.Accent, Theme.Bg)
                if !h
                    try h := LoadPicture(f)
            }
            if !h
                break
            this._moonFrames.Push(h)
        }
        if (this._moonFrames.Length >= 2)
            this._moon := Theme.Add(g, "Picture", "x18 y10 w40 h40 BackgroundTrans", "HBITMAP:*" this._moonFrames[1])
        else {
            this._FreeMoon()
            this._moon := Theme.Moon(g, 18, 10, 40)
        }
        Theme.Label(g, "x66 y5 w300 h36", Brand.Name, "brand", Theme.Bg)
        Theme.Label(g, "x68 y39 w300 h16", "Sol's RNG", "small", Theme.Bg)
        Theme.Rect(g, 0, 59, Dashboard.W, 1, Theme.PanelC)
        Theme.Font(g, "caps", Theme.Accent)
        this._ids["credits.banner"] := Theme.Add(g, "Text", "x372 y17 w240 h26 +0x80 +0x200 Center Background" Theme.Bg, Credits.Banner())
        this._ids["credits.banner"].Visible := false
        Theme.Font(g, "caps")
        this._pill := Theme.Add(g, "Text", "x618 y17 w132 h26 +0x80 +0x200 Center Background" Theme.OffBg, "")
        Theme.Button(g, "x764 y16 w80 h28", "Start", (*) => this._Fire("start"), "primary")
        this._PauseBtn(Theme.Button(g, "x852 y16 w80 h28", "Pause", (*) => this._Fire("pause")))
        Theme.Button(g, "x940 y16 w80 h28", "Stop", (*) => this._Fire("stop"))

        this._DrawSidebar(g)

        ; twinkling stars (header y < 59; sidebar band in left / right mode), loop "stars"
        stars := Dashboard.Stars.Clone()
        if (this._side = "top") {
            stars := []
            for s in Dashboard.Stars {
                if (s[2] < 59)
                    stars.Push(s)
            }
            for s in Dashboard.StarsTop
                stars.Push(s)
        }
        sx := this._side = "right" ? 864 : 0
        for i, s in stars {
            bg := s[2] < 59 ? Theme.Bg : Theme.SideBg
            g.SetFont("s" Theme.S(7) " norm c" Dashboard._Blend(bg, Theme.Text, 0.56), "Segoe UI Symbol")
            c := Theme.Add(g, "Text", "x" (s[2] < 59 ? s[1] : s[1] + sx) " y" s[2] " w12 h12 +0x80 Center Background" bg, Chr(0x2726))
            this._stars.Push({c: c, bg: bg, period: s[3], off: i * 397, lvl: 3})
            this._ids["star" i] := c
        }

        ; hub header: title, tab strip (one tab + dot per page, only the
        ; active hub's are shown), the underline under the active tab
        sh := this._sh
        this._hubTitle := Theme.Label(g, "x" 204 + sh.dx " y" 66 + sh.dy " w600 h36", "", "title")
        this._ids["hubTitle"] := this._hubTitle
        this._tabs := []
        this._dots := []
        for hub in Dashboard.Hubs {
            x := 204 + sh.dx
            for name in hub.pages {
                i := Dashboard.PageIndex(name)
                t := Theme.Label(g, "x" x " y" 104 + sh.dy " h26 +0x100 +0x200", Dashboard.TabLabel(name), "nav")
                tw := Theme.Pos(t).w
                Theme.Clickable(t, ObjBindMethod(this, "_TabClick", i), ObjBindMethod(this, "_PaintTab", i))
                dot := Theme.Label(g, "x" x + tw + 3 " y" 104 + sh.dy " w10 h26 +0x200", Chr(0x2022), "body", "", Theme.Accent)
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
        this._underline := Theme.Rect(g, 204 + sh.dx, 130 + sh.dy, 40, 2, Theme.Accent)
        this._LayoutNav()
        this._underline.Visible := false
        this._ids["tabUnderline"] := this._underline

        ; pages
        for i, name in Dashboard.Pages {
            Theme.Sink := []
            page := {name: name, idx: i, ctrls: [], load: "", save: "", status: "", dirty: false}
            this._curPage := page
            this._cards[name] := []
            this._fixed := Map()
            this._ids["desc:" name] := Theme.Label(g, "x204 y132 w808 h16", Dashboard.Subtitles[i], "muted")
            this._fixed[this._ids["desc:" name].Hwnd] := true
            m := Dashboard.Builders[i]
            this.%m%(page)
            page.ctrls := Theme.Sink
            Theme.Sink := ""
            this._AssignCards(page)
            for c in page.ctrls {
                c.Visible := false
                this._ctrlPage[c.Hwnd] := i
            }
            this._pages.Push(page)
        }
        this._curPage := ""
        this._ShiftPages()
        for name in Dashboard.Pages
            this.ApplyLayout(name, Theme.Layout)
        this._BuildSearch(g)
    }

    ; The sidebar for this._side: a band at the left (x 0..176), at the right
    ; (x 864..1040) or across the top (the hubs one row of labels sized to
    ; their text at y 59..107, the chip at the row's right end), with the
    ; hubs and the status chip.
    _DrawSidebar(g) {
        top := this._side = "top"
        sx := this._side = "right" ? 864 : 0
        if top {
            Theme.Rect(g, 0, 60, Dashboard.W, 47, Theme.SideBg)
            Theme.Rect(g, 0, 107, Dashboard.W, 1, Theme.PanelC)
        } else {
            Theme.Rect(g, sx, 60, 176, 620, Theme.SideBg)
            Theme.Rect(g, sx = 0 ? 175 : 864, 60, 1, 620, Theme.PanelC)
        }
        this._nav := []
        this._navBar := []
        this._navW := []
        this._navFs := ""
        for i, hub in Dashboard.Hubs {
            y := top ? 100 : Dashboard.HubTop + (i - 1) * 40
            this._navBar.Push(Theme.Rect(g, top ? 12 : sx + 1, y, top ? 40 : 3, top ? 3 : 34, Theme.SideBg))
            Theme.Font(g, "nav")
            if top
                c := Theme.Add(g, "Text", "x12 y64 h34 +0x80 +0x100 +0x200 Center Background" Theme.SideBg, I18n.T(hub.name))
            else
                c := Theme.Add(g, "Text", "x" sx + 12 " y" y " w152 h34 +0x80 +0x100 +0x200 Background" Theme.SideBg, "   " I18n.T(hub.name))
            this._navW.Push(top ? Theme.Pos(c).w + 24 : 152)
            Theme.Clickable(c, ObjBindMethod(this, "_NavClick", i), ObjBindMethod(this, "_PaintNav", i))
            this._nav.Push(c)
            this._ids["hub:" hub.name] := c
        }
        Theme.Font(g, "caps")
        this._chip := Theme.Add(g, "Text", (top ? "x872 y65 w148 h30" : "x" sx + 14 " y622 w148 h30") " +0x80 +0x200 Center Background" Theme.OffBg, "")
    }

    ; Right / top sidebar: every control of every page (the subtitle and the
    ; bottom bars included) moves by the page shift once, and the cards' built
    ; places move with it, so ApplyLayout puts a card without an entry back
    ; in the shifted place.
    _ShiftPages() {
        dx := this._sh.dx, dy := this._sh.dy
        if (dx = 0 && dy = 0)
            return
        ; one real (Gui px) step for every control: moved one by one in
        ; 100 % units they rounded apart at 115 / 130 % (a fill over its
        ; frame's line)
        k := Theme.IsScaled(this._gui)
        rdx := k ? Theme.S(dx) : dx, rdy := k ? Theme.S(dy) : dy
        for page in this._pages {
            for c in page.ctrls {
                c.GetPos(&cx, &cy)
                c.Move(cx + rdx, cy + rdy)
            }
            for card in this.Cards(page.name)
                card.x += dx, card.y += dy
        }
    }

    _SaveBar(page) {
        g := this._gui
        n := page.name
        n0 := this._FixedBar()
        page.status := Theme.Label(g, "x330 y634 w462 h20 Right", "", "muted")
        Theme.Button(g, "x804 y628 w100 h30", "Revert", (*) => this.RevertPage(n))
        Theme.Button(g, "x912 y628 w100 h30", "Save", (*) => this.SavePage(n), "primary")
        this._FixedBar(n0)
    }

    ; A page's bottom bar (the save-bar row, y 622..664) is fixed, never part
    ; of a card. _FixedBar() before the bar's controls -> a mark;
    ; _FixedBar(mark) after them tags every control made since as fixed.
    _FixedBar(mark := -1) {
        if !(Theme.Sink is Array)
            return 0
        if (mark < 0)
            return Theme.Sink.Length
        Loop Theme.Sink.Length - mark
            this._fixed[Theme.Sink[mark + A_Index].Hwnd] := true
        return mark
    }

    ; After a page builder ran: each control of page.ctrls goes to the card
    ; opened last before it (_Panel noted where each card starts in the
    ; Sink), to fixed (subtitle, save bar) or, before the first card, loose.
    _AssignCards(page) {
        cards := this._cards[page.name]
        k := 0
        for i, c in page.ctrls {
            while (k < cards.Length && cards[k + 1].start <= i)
                k++
            if this._fixed.Has(c.Hwnd)
                id := page.name ":fixed"
            else if (k = 0)
                id := page.name ":loose"
            else {
                id := cards[k].id
                cards[k].ctrls.Push(c)
            }
            this._cardOf[c.Hwnd] := id
        }
        for card in cards {
            p := Theme.Pos(card.frame)
            card.x := p.x, card.y := p.y, card.w := p.w, card.h := p.h
            card.DeleteProp("start")
        }
        this._fixed := Map()
    }

    _SetPageStatus(page, text, bad := false) {
        if !IsObject(page.status)
            return
        page.status.SetFont("c" (bad ? Theme.Accent : Theme.Muted))
        Theme.SetText(page.status, text)
        Theme.RepaintCtrl(page.status)
    }

    ; Solid panel on the page being built; a titled one is also
    ; Ctrl("panel:<page>:<title>") (its frame) and Ctrl("panelTitle:<page>:<title>")
    ; (its caption; Theme translates it, the ids keep the English title).
    ; help: text of a "?" at the title's right.
    ; Each _Panel also opens a card (Cards): the controls made from here to
    ; the next _Panel belong to it.
    _Panel(x, y, w, h, title := "", help := "") {
        start := (Theme.Sink is Array) ? Theme.Sink.Length + 1 : 0
        parts := Theme.Panel(this._gui, x, y, w, h, title)
        if (title != "" && IsObject(this._curPage)) {
            this._ids["panel:" this._curPage.name ":" title] := parts[1]
            this._ids["panelTitle:" this._curPage.name ":" title] := parts[3]
        }
        if (start && IsObject(this._curPage) && this._cards.Has(this._curPage.name)) {
            cards := this._cards[this._curPage.name]
            n := 0
            for c in cards
                n += (c.title = "")
            cards.Push({id: this._curPage.name ":" (title != "" ? title : "#" (n + 1)), title: title
                , frame: parts[1], fill: parts[2], caption: parts.Length >= 3 ? parts[3] : ""
                , ctrls: [], x: x, y: y, w: w, h: h, start: start})
        }
        if (help != "")
            Theme.Help(this._gui, x + w - 28, y + 8, help)
        return parts
    }

    ; An untitled card with no frame or fill to see (both stay hidden): a
    ; row of buttons outside the other cards (Home's Start / Pause / Stop)
    ; becomes a card of its own and moves as one. Like every card it lies
    ; inside the page area (x 204..1012, y 152..620).
    _BarCard(x, y, w, h) {
        parts := this._Panel(x, y, w, h)
        this._SetHidden(parts[1], true)
        this._SetHidden(parts[2], true)
        return parts
    }

    ; "?" right after a switch's label (made as wide as its text). A label
    ; whose "?" would leave its card (a long translation) gets a smaller
    ; font first (Theme.FitFont), so the "?" always shows.
    _HelpAfter(chk, text) {
        l := chk._lbl
        p := Theme.Pos(l)
        right := this._CardRightAt(p.x, p.y)
        if (p.x + p.w + 8 + 16 > right - 8) {
            room := Max(20, right - 8 - 16 - 8 - p.x)
            Theme.FitFont(l, "body", Theme.IsScaled(this._gui) ? Theme.S(room) : room)
            Theme.MoveTo(l, , , Min(room, Theme.Units(this._gui, Theme.TextW(l)) + 1))
            p := Theme.Pos(l)
        }
        return Theme.Help(this._gui, p.x + p.w + 8, p.y + 2, text)
    }

    ; The right edge (100 % units, page places as built) of the card of the
    ; page being built that holds x, y; the page area's edge when none does.
    _CardRightAt(x, y) {
        try {
            if (IsObject(this._curPage) && this._cards.Has(this._curPage.name)) {
                cards := this._cards[this._curPage.name]
                Loop cards.Length {
                    c := cards[cards.Length + 1 - A_Index]
                    if (x >= c.x && x < c.x + c.w && y >= c.y && y < c.y + c.h)
                        return c.x + c.w
                }
            }
        }
        return 1012
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
        if (page.name = "Clips" || page.name = "Webhooks")
            this._RarityNotes()                 ; reverted / reloaded numbers
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
        want := (h = this._hub && this._ShownIn(h).Length > 1 && this.TabShown(page.name) && this._PageDirty(page)) ? true : false
        if (dot.Visible != want) {
            dot.Visible := want
            if !want
                Theme.RepaintCtrl(dot)
        }
    }

    ; ---- search ---------------------------------------------------------------
    ; The box (left / right: the top of the sidebar; top: a magnifier that
    ; opens it beside the hub title), up to SearchRows result rows in a popup
    ; over the page, and a "No setting matches" note. SearchFor(q) -> the rows
    ; shown; SearchGo(i) opens a row's page and flashes its card; SearchClear
    ; closes it. Ctrl+F (only while this window is active) focuses the box;
    ; Enter / Esc / Up / Down work only while the box has the focus.

    static SearchRows := 8

    ; Made after the pages: on top of them, and in no page's controls or cards.
    _BuildSearch(g) {
        sink := Theme.Sink
        Theme.Sink := ""
        try {
            top := this._side = "top"
            sx := this._side = "right" ? 864 : 0
            this._sRes := []
            this._sSel := 0
            this._sRows := []
            this._sBoxCtrls := []
            this._sBusy := false
            this._flash := ""
            this._flashPool := []
            this._flashFn := ObjBindMethod(this, "_FlashStep")
            lw := 460
            lx := top ? 540 : (this._side = "right" ? 864 - 8 - lw : 184)
            ly := top ? 150 : 70
            ; the box and its frame, collected so top mode can show / hide them together
            Theme.Sink := this._sBoxCtrls
            e := top ? Theme.Edit(g, 700, 118, 300, 28) : Theme.Edit(g, sx + 12, 68, 152, 28)
            Theme.Sink := ""
            try SendMessage(0x1501, 1, StrPtr(I18n.T("Search")), e.Hwnd)       ; EM_SETCUEBANNER
            e.OnEvent("Change", (c, *) => this._sBusy ? "" : this.SearchFor(c.Value))
            this._ids["search:box"] := e
            if top {
                Theme.Font(g, "glyph", Theme.Muted)
                ic := Theme.Add(g, "Text", "x676 y66 w32 h28 +0x100 +0x200 Center Background" Theme.SideBg, Chr(0x1F50D))
                Theme.Clickable(ic, (*) => this.SearchFocus(), (on) => Theme.SetColors(ic, Theme.SideBg, on ? Theme.Accent : Theme.Muted))
                this._ids["search:icon"] := ic
                this._TopRow()                   ; the magnifier goes to the row's end
                for c in this._sBoxCtrls
                    c.Visible := false
            }
            Theme.Font(g, "body")
            n := Dashboard.SearchRows
            this._ids["search:list"] := Theme.Add(g, "Text", "x" lx - 1 " y" ly - 1 " w" lw + 2 " h" n * 24 + 2 " Background" Theme.Accent)
            Loop n {
                i := A_Index
                r := Theme.Add(g, "Text", "x" lx " y" ly + (i - 1) * 24 " w" lw " h24 +0x100 +0x200 +0x4000 Background" Theme.FieldBg " c" Theme.Text, "")
                this._SearchRowFns(r, i)
                this._sRows.Push(r)
            }
            this._ids["search:none"] := Theme.Add(g, "Text", "x" lx " y" ly " w" lw " h28 +0x200 Background" Theme.FieldBg " c" Theme.Muted, "   " I18n.T("No setting matches"))
            this._SearchShow([], false)
            this._SearchIndexBuild()
            this._SearchHotkeys()
        } catch Any as err {
            try OutputDebug("Dashboard search UI failed: " err.Message)
        } finally
            Theme.Sink := sink
    }

    ; Row r's click and hover act on row i (a closure in the build loop would
    ; share one i).
    _SearchRowFns(r, i) {
        Theme.Clickable(r, (*) => this.SearchGo(i), (on) => on ? this._SearchSel(i) : "")
    }

    ; Every title, label, switch caption, button and help text, English and
    ; translated, each with its page and card. Text only (never a field's
    ; value), and anything that looks like a link is left out.
    _SearchIndexBuild() {
        idx := []
        for i, hub in Dashboard.Hubs
            this._SearchAdd(idx, hub.name, "title", hub.pages[1], "")
        for i, name in Dashboard.Pages {
            this._SearchAdd(idx, Dashboard.TabLabel(name), "title", name, "")
            this._SearchAdd(idx, Dashboard.Subtitles[i], "help", name, "")
        }
        for page in this._pages {
            skip := Map()
            for card in this.Cards(page.name) {
                this._SearchAdd(idx, card.title, "title", page.name, card.id)
                if IsObject(card.caption)
                    skip[card.caption.Hwnd] := true
            }
            inputs := []
            for c in page.ctrls {
                if (c.Type = "Edit" || c.Type = "DropDownList" || c.Type = "ComboBox" || c.Type = "ListBox" || c.Type = "ListView")
                    inputs.Push(Theme.Pos(c))
            }
            for c in page.ctrls {
                src := Theme.SourceOf(c)
                if (src = "" || skip.Has(c.Hwnd))
                    continue
                id := this._cardOf.Has(c.Hwnd) ? this._cardOf[c.Hwnd] : ""
                if RegExMatch(id, ":fixed$")
                    continue
                if RegExMatch(id, ":loose$")
                    id := ""
                kind := "help"
                if (Theme.HelpText(c) = "")
                    kind := this._SearchIsSetting(c, inputs) ? "label" : "info"
                this._SearchAdd(idx, src, kind, page.name, id)
            }
        }
        this._sIdx := idx
    }

    ; A setting's own text: a switch caption, a button, or a label on the row
    ; of an input; any other label (stat tile, note) is read-only.
    _SearchIsSetting(c, inputs) {
        if Theme.IsActionText(c)
            return true
        p := Theme.Pos(c)
        for q in inputs {
            if (q.y < p.y + p.h && p.y < q.y + q.h + 4 && q.x >= p.x)
                return true
        }
        return false
    }

    _SearchAdd(idx, en, kind, page, card) {
        en := Trim(String(en))
        if (StrLen(en) < 3 || RegExMatch(en, "i)https?:|discord(app)?\.com|roblox\.com|^\W*$"))
            return
        tr := I18n.T(en)
        Search.Add(idx, en, kind, page, card, tr)
        if (tr != en)
            Search.Add(idx, tr, kind, page, card, tr)
    }

    ; The results for q (up to SearchRows, only pages that show now), shown in
    ; the popup. "" closes it.
    SearchFor(q) {
        res := []
        asked := false
        try {
            q := Trim(String(q))
            asked := q != ""
            if asked {
                for r in Search.Find(this._sIdx, q, 40) {
                    if this.PageShown(r.page)
                        res.Push(r)
                    if (res.Length >= Dashboard.SearchRows)
                        break
                }
            }
        }
        this._SearchShow(res, asked)
        return res
    }

    _SearchShow(res, asked) {
        try {
            this._sRes := res
            this._sSel := res.Length ? 1 : 0
            for i, r in this._sRows {
                on := i <= res.Length
                if on {
                    e := res[i]
                    t := StrLen(e.text) > 50 ? SubStr(e.text, 1, 49) Chr(0x2026) : e.text
                    h := Dashboard.HubOf(e.page)
                    r.Text := "  " t "  " Chr(0xB7) "  " (h ? I18n.T(Dashboard.Hubs[h].name) : "") " > " I18n.T(Dashboard.TabLabel(e.page))
                    Theme.SetColors(r, i = 1 ? Theme.HoverBg : Theme.FieldBg, Theme.Text)
                }
                r.Visible := on
            }
            list := this._ids["search:list"]
            if res.Length
                Theme.MoveTo(list, , , , res.Length * 24 + 2)
            list.Visible := res.Length > 0
            this._ids["search:none"].Visible := asked && !res.Length
            if (asked && this._side = "top")
                this._SearchBox(true)
        }
    }

    ; Row i is the one Enter opens (the mouse over it, or Up / Down).
    _SearchSel(i) {
        try {
            if (i < 1 || i > this._sRes.Length || i = this._sSel)
                return
            Theme.SetColors(this._sRows[this._sSel], Theme.FieldBg, Theme.Text)
            this._sSel := i
            Theme.SetColors(this._sRows[i], Theme.HoverBg, Theme.Text)
        }
    }

    ; Top mode: the box shows only while searching.
    _SearchBox(on) {
        try {
            if (this._side != "top")
                return
            for c in this._sBoxCtrls
                c.Visible := on ? true : false
        }
    }

    ; Esc: the box empties and the popup closes.
    SearchClear() {
        try {
            this._sBusy := true
            this._ids["search:box"].Value := ""
        } finally
            this._sBusy := false
        this._SearchShow([], false)
        this._SearchBox(false)
    }

    ; Ctrl+F, or the magnifier: the box takes the focus, its text selected.
    SearchFocus() {
        try {
            this._SearchBox(true)
            e := this._ids["search:box"]
            e.Focus()
            SendMessage(0xB1, 0, -1, e.Hwnd)                 ; EM_SETSEL all
        }
    }

    ; Opens result i's hub and page, and flashes its card.
    SearchGo(i) {
        try {
            if !(IsInteger(i) && i >= 1 && i <= this._sRes.Length)
                return
            r := this._sRes[i]
            this.SearchClear()
            idx := Dashboard.PageIndex(r.page)
            if (idx && this.PageShown(r.page)) {
                this.SelectPage(idx)
                this._Unfocus()
                this._FlashCard(r.page, r.card)
            }
        }
    }

    Flashing => IsObject(this._flash)

    ; A 2 px Accent frame round the card, on and off 3 times in about 1.5 s
    ; (a timer, never Sleep). Skipped for a card the layout hides.
    _FlashCard(page, id) {
        this._FlashStop()
        if (id = "")
            return
        card := ""
        for c in this.Cards(page) {
            if (c.id = id) {
                card := c
                break
            }
        }
        if (!IsObject(card) || this._layoutHidden.Has(card.frame.Hwnd))
            return
        sink := Theme.Sink
        Theme.Sink := ""                         ; never a page control
        try {
            g := this._gui
            if !this._flashPool.Length {
                Loop 4
                    this._flashPool.Push(Theme.Add(g, "Text", "x0 y0 w2 h2 Background" Theme.Accent))
            }
            p := this._flashPool
            Theme.MoveTo(p[1], card.x, card.y, card.w, 2)
            Theme.MoveTo(p[2], card.x, card.y + card.h - 2, card.w, 2)
            Theme.MoveTo(p[3], card.x, card.y, 2, card.h)
            Theme.MoveTo(p[4], card.x + card.w - 2, card.y, 2, card.h)
            for c in p
                DllCall("SetWindowPos", "Ptr", c.Hwnd, "Ptr", 0, "Int", 0, "Int", 0, "Int", 0, "Int", 0, "UInt", 0x13)   ; HWND_TOP, no move / size / activate
            this._flash := {ctrls: p, n: 0}
            this._FlashStep()
            SetTimer(this._flashFn, 250)
        } finally
            Theme.Sink := sink
    }

    _FlashStep() {
        try {
            f := this._flash
            if (!IsObject(f) || f.n >= 6) {
                this._FlashStop()
                return
            }
            on := Mod(f.n, 2) = 0
            for c in f.ctrls
                c.Visible := on
            f.n += 1
        } catch {
            try this._FlashStop()
        }
    }

    _FlashStop() {
        try SetTimer(this._flashFn, 0)
        try {
            if IsObject(this._flash) {
                for c in this._flash.ctrls
                    c.Visible := false
            }
        }
        this._flash := ""
    }

    ; Ctrl+F while a dashboard window is the active one (never in Roblox);
    ; Enter, Esc, Up and Down only while its box has the focus. The keys are
    ; made once for every dashboard, with one handler that finds the
    ; dashboard through the active window (_searchBy), so a window holds no
    ; hotkey of its own and Destroy only takes it out of the map.
    static _searchBy := Map()           ; dashboard hwnd -> Dashboard (search keys)
    static _searchKeys := false

    _SearchHotkeys() {
        Dashboard._searchBy[this._gui.Hwnd] := this
        if Dashboard._searchKeys
            return
        Dashboard._searchKeys := true
        ; the keys pass through (~), and only fire in a dashboard window: a
        ; press in Roblox never reaches the script; the focus check is in the handler
        try {
            HotIf(ObjBindMethod(Dashboard, "_SearchWin"))
            Hotkey("^f", ObjBindMethod(Dashboard, "_SearchHotkey", "focus"), "On")
            Hotkey("~Enter", ObjBindMethod(Dashboard, "_SearchHotkey", "go"), "On")
            Hotkey("~NumpadEnter", ObjBindMethod(Dashboard, "_SearchHotkey", "go"), "On")
            Hotkey("~Escape", ObjBindMethod(Dashboard, "_SearchHotkey", "esc"), "On")
            Hotkey("~Down", ObjBindMethod(Dashboard, "_SearchHotkey", "down"), "On")
            Hotkey("~Up", ObjBindMethod(Dashboard, "_SearchHotkey", "up"), "On")
        } catch Any as err {
            try OutputDebug("Dashboard search keys failed: " err.Message)
        } finally
            HotIf()
    }

    ; The dashboard whose window is the active one | "".
    static _SearchDash() {
        try {
            h := DllCall("GetForegroundWindow", "Ptr")
            if Dashboard._searchBy.Has(h)
                return Dashboard._searchBy[h]
        }
        return ""
    }

    static _SearchWin(*) => IsObject(Dashboard._SearchDash())

    static _SearchHotkey(k, *) {
        d := Dashboard._SearchDash()
        if !IsObject(d)
            return
        try {
            if (k = "focus")
                d.SearchFocus()
            else
                d._SearchKey(k)
        }
    }

    _SearchKey(k) {
        if !this._SearchHot()
            return
        if (k = "go")
            this.SearchGo(this._sSel)
        else if (k = "esc") {
            this.SearchClear()
            this._Unfocus()
        } else
            this._SearchSel(this._sSel + (k = "down" ? 1 : -1))
    }

    _SearchHot() {
        try return DllCall("GetForegroundWindow", "Ptr") = this._gui.Hwnd && this._focusFn.Call() = this._ids["search:box"].Hwnd
        return false
    }

    ; This window leaves the search keys' map (the keys stay for the others).
    _SearchHotkeysOff() {
        try Dashboard._searchBy.Delete(this._gui.Hwnd)
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
        multi := this._ShownIn(h).Length > 1
        x := 204 + this._sh.dx
        for name in this._ShownIn(h) {
            i := Dashboard.PageIndex(name)
            tw := Theme.Pos(this._tabs[i]).w
            Theme.MoveTo(this._tabs[i], x)
            Theme.MoveTo(this._dots[i], x + tw + 3)
            x += tw + 28
        }
        for i, name in Dashboard.Pages {
            on := multi && Dashboard.HubOf(name) = h && this.TabShown(name)
            if (this._tabs[i].Visible != on)
                this._tabs[i].Visible := on
        }
        for page in this._pages
            this._RefreshDot(page)
        this._underline.Visible := multi
        Theme.SetText(this._hubTitle, I18n.T(Dashboard.Hubs[h].name))
        if old
            this._PaintNav(old, false)
        this._PaintNav(h, false)
    }

    ; Active tab gold, the underline (a single control) moved under it. A
    ; page whose tab is not shown (Dev tools outside the dev copy, opened by
    ; a harness or a test) has no underline:
    ; it sat under the tab now in that tab's old place (Credits).
    _PaintTabs() {
        for name in this._ShownIn(this._hub)
            this._PaintTab(Dashboard.PageIndex(name), false)
        lit := Dashboard.PageIndex(Dashboard.TabFor(this.ActivePage))
        on := this._ShownIn(this._hub).Length > 1 && lit && this.TabShown(Dashboard.Pages[lit])
        if (this._underline.Visible != on)
            this._underline.Visible := on
        if on {
            tp := Theme.Pos(this._tabs[lit])
            up := Theme.Pos(this._underline)
            tx := tp.x, tw := tp.w, ux := up.x, uw := up.w
            u := this._underline
            Anim.Tween("underline", 180, (p) => Theme.MoveTo(u, Round(Anim.Lerp(ux, tx, p)), 130 + this._sh.dy, Round(Anim.Lerp(uw, tw, p)), 2))
        }
    }

    ; ---- animations ---------------------------------------------------------------

    ; Moon, stars and (while Running) pulse loops. Existing loops are kept
    ; unless force (after a Look save: UI.animations may have changed;
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
        n := this._moonFrames.Length
        if (n < 2)
            return
        f := Min(n - 1, Max(0, Floor(phase * n)))
        if (f = this._moonFrame)
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
            b := this.PageBox()
            this._cover.Show("x" Theme.Dpi(Theme.S(b.x)) " y" Theme.Dpi(Theme.S(b.y)) " w" Theme.S(b.w) " h" Theme.S(b.h) " NoActivate")
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
        lit := this._active && Dashboard.PageIndex(Dashboard.TabFor(Dashboard.Pages[this._active])) = i
        c.SetFont("c" (lit ? Theme.Accent : hot ? Theme.Text : Theme.Muted))
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

    ; min / max: a typed number outside is saved (and shown) as the nearest
    ; end, where the code that reads the key would otherwise drop it
    _IntField(x, y, label, key, def, unit := "", lw := 170, min := "", max := "") {
        g := this._gui
        late := this._FieldLabel(x, y, label, key, lw)
        e := Theme.Edit(g, x + lw, y, 72, 28, "", "Number")
        if (unit != "")
            Theme.Label(g, "x" x + lw + 80 " y" y + 5 " w70 h20", unit, "muted")
        this._Bind("int", key, def, e)
        if (min != "")
            this._binds[this._binds.Length].min := min
        if (max != "")
            this._binds[this._binds.Length].max := max
        return e
    }

    _StrField(x, y, label, key, def, w := 120, lw := 170) {
        g := this._gui
        late := this._FieldLabel(x, y, label, key, lw)
        e := Theme.Edit(g, x + lw, y, w, 28)
        this._Bind("str", key, def, e)
        return e
    }

    ; Pill switch bound to key. help: a "?" after the label.
    ; Turning the switch ON asks first (title / text); "Keep off" leaves it off.
    _WarnOn(c, title, text) {
        ; keeps the callback _Bind set (the tab's unsaved dot), run after the question
        own := c._fn
        c._fn := (ctl) => ((ctl.Value && this._confirmBuggy.Call(title, text) != true) ? (ctl.Value := 0) : 0
            , IsObject(own) ? own.Call(ctl) : 0)
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

    ; A field's label (lw - 8 wide) and, when HelpTexts has the key, a "?"
    ; right after the text, from the translated text's real width (idea 4,
    ; 2026-11-13). A label too long for both (a translation) gets a smaller
    ; font (Theme.FitFont, down to 9 pt) so the "?" still fits before the
    ; input (it once went hidden: "Aura rarer than 1 in" in fil / pt). -> ""
    _FieldLabel(x, y, label, key, lw) {
        g := this._gui
        help := HelpTexts.For(key)
        if (help = "") {
            Theme.Label(g, "x" x " y" y + 4 " w" lw - 8 " h20", label)
            return ""
        }
        l := Theme.Label(g, "x" x " y" y + 4 " h20", label)
        room := lw - 26
        tw := Theme.Pos(l).w
        if (tw > room) {
            Theme.FitFont(l, "body", Theme.IsScaled(g) ? Theme.S(room) : room)
            tw := Min(room, Theme.Units(g, Theme.TextW(l)) + 1)
            Theme.MoveTo(l, , , tw)
        }
        Theme.Help(g, x + tw + 6, y + 6, help)
        return ""
    }

    _BoolField(x, y, label, key, def, w := 310, help := "") {
        if (help = "")
            help := HelpTexts.For(key)
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
            else if (b.kind = "app")               ; clip app dropdown: by id
                b.ctrl.Choose(Clip.AppIndex(v))
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
                    if (b.HasProp("max") && v > b.max)
                        v := b.max
                    b.ctrl.Value := String(v)
                    this.cfg.Set(b.key, v)
                case "str":
                    this.cfg.Set(b.key, Trim(b.ctrl.Value))
                case "app":
                    this.cfg.Set(b.key, Clip.Apps[Max(1, b.ctrl.Value)].id)
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
        want := !hide && onPage && !this._layoutHidden.Has(ctrl.Hwnd)
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
            host := this._Host()                        ; secrets plugins handed in (PluginApi.Secret)
            if IsObject(host)
                for s in host.Secrets()
                    arr.Push(s)
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
            Theme.SetText(this._logCount, I18n.F("{1} / {2} lines", this._logBuf.Count(), 200))
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
        this._chip.Text := v ? I18n.T("DRY RUN") "  " Chr(0xB7) "  " I18n.T("SAFE") : I18n.T("LIVE") "  " Chr(0xB7) "  " I18n.T("POTIONS ARMED")
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

    ; ---- idle mode -------------------------------------------------------------

    ; Home's "Idle mode" switch (General.idleMode): the _BoolField bind (it
    ; loads with the page, has its "?"), saved at once like Dry run (the Run
    ; page has no Save button). The App reads it at the next Start.
    _IdleSwitch(x, y) {
        key := "General.idleMode"
        c := Theme.Check(this._gui, x, y, "Idle mode (watch only, no input)", 0, ObjBindMethod(this, "_IdleFlip"), "pill", -1)
        this._Bind("bool", key, 0, c)
        help := HelpTexts.For(key)
        if (help != "")
            this._HelpAfter(c, help)
        return c
    }

    _IdleFlip(chk) {
        v := chk.Value ? 1 : 0
        this.cfg.Set("General.idleMode", v)
        try this.cfg.Save()
        catch Any as e {
            this.Log("Settings: idle mode not saved: " e.Message)
            return
        }
        for b in this._binds                    ; saved: not an unsaved edit
            if (b.ctrl == chk)
                b.loaded := String(chk.Value)
        this.Log(v ? "Idle mode ON (from the next Start): only biomes, auras, chat and the biome clock are read; no clicks or keys"
            : "Idle mode OFF (from the next Start): tasks run as usual")
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
        ; what comes next (idea 8): the LOOPS count is also on the Stats tiles
        Theme.Label(g, "x404 y298 w170 h16", "NEXT UP", "caps", Theme.CardBg)
        this._stNext := Theme.Label(g, "x404 y316 w180 h24", "", "value", Theme.CardBg)
        this._ids["stNext"] := this._stNext

        this._BarCard(204, 360, 396, 52)
        Theme.Button(g, "x204 y368 w124 h36", "Start", (*) => this._Fire("start"), "primary")
        this._PauseBtn(Theme.Button(g, "x340 y368 w124 h36", "Pause", (*) => this._Fire("pause")))
        Theme.Button(g, "x476 y368 w124 h36", "Stop", (*) => this._Fire("stop"))

        this._Panel(204, 420, 396, 196, "Potion safety")
        this._DryCheck(220, 452)
        this._dryOn.Push(Theme.Label(g, "x220 y484 w364 h40", "On: every potion check runs and is logged, nothing is clicked.", "muted"))
        this._dryOff.Push(Theme.Label(g, "x220 y484 w364 h40", "Dry run is OFF: unlocked potions will really be used in rare biomes.", "body", "", Theme.Accent))
        this._IdleSwitch(220, 538)
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
            this._updCheck := Theme.Button(g, "x632 y328 w148 h28", "Check for updates", (*) => this._Fire("checkUpdate"))
            this._updInstall := Theme.Button(g, "x788 y328 w96 h28", "Install", (*) => this._Fire("installUpdate"), "primary")
            this._updLater := Theme.Button(g, "x892 y328 w96 h28", "Later", (*) => this.SetUpdate(""))
            ; "Go back to vX" in the same row while no update is offered (SetRollback)
            this._updBack := Theme.Button(g, "x788 y328 w200 h28", "Go back", (*) => this._AskRollback())
            this._rbVer := ""
            this._SetHidden(this._updInstall, true)
            this._SetHidden(this._updLater, true)
            this._SetHidden(this._updBack, true)
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
        this._updMsg.Text := on ? I18n.F("Update available: v{1}", version) : (note != "" ? note : "Moontide Macro v" Brand.Version)
        this._SetHidden(this._updInstall, !on)
        this._SetHidden(this._updLater, !on)
        this._SetHidden(this._updBack, on || this._rbVer = "")
    }

    ; "Go back to vX" button (version "" = no backup: hidden). Hidden while an
    ; update is offered. No-op without the Updates panel.
    SetRollback(version) {
        if !HasProp(this, "_updBack")
            return
        this._rbVer := String(version)
        if (this._rbVer != "")
            Theme.SetText(this._updBack, I18n.F("Go back to v{1}", this._rbVer))
        this._SetHidden(this._updBack, this._rbVer = "" || !this._hidden.Has(this._updInstall.Hwnd))
    }

    _AskRollback() {
        if (this._rbVer = "")
            return
        if (MsgBox(I18n.F("Go back to v{1}? The macro restarts. Your settings and data stay.", this._rbVer), Brand.Name, "YesNo Icon? Owner" this._gui.Hwnd) != "Yes")
            return
        this._Fire("rollback")
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
        ; Advanced mode / threshold left the page (2026-11-26): they only feed the
        ; legacy FishSol reel (General.legacyReel, no switch), so they did nothing.
        this._Panel(616, 152, 396, 120, "Fishing", "Click spots, colours and timings come from data\coords.json (2560x1440). "
            . "The VIP route switch is under Settings > General.")
        this._BoolField(632, 186, "Fish when nothing else is due", "General.fishing", 1)
        Theme.Label(g, "x632 y216 w364 h40", "Off = no fishing; the rest still runs. With Fish shop on, the Start trip still sells fish.", "muted")
        this._SaveBar(p)
    }

    ; ---- page: Limbo --------------------------------------------------------------

    _PageLimbo(p) {
        g := this._gui
        this._Panel(204, 152, 808, 128, "Limbo (Eden)", "On: every other task stops (fishing, selling, crafting, quests, Daily Quests, merchants, "
            . "biome items, the obby, Memory Match and hunting), and so do the anti ghost server rejoin and the stuck reset. Biome webhooks, "
            . "clips and rare-biome potions stay on (used back on Sol's Island). Uses your Portable Crack, turns the camera top-down, walks limbo_eden (Help > Routes), "
            . "presses E by Eden's spot and clicks Contract with it (needs a Void Heart and the Darklight Core, Orb and Shard). "
            . "A rare biome: back to Sol's Island (rejoin), into Limbo again after it. When the crack cannot be used, the other tasks run until "
            . "the next try (10 min). A restart in THE LIMBO is remembered until Roblox joins a server again.")
        this._BoolField(220, 188, "Wait in Limbo for Eden instead of fishing", "Limbo.enabled", 0, 420)
        Theme.Label(g, "x220 y222 w776 h20", "Needs a Void Heart and the Darklight Core, Orb and Shard.", "muted")
        ; the Portable Device is another (placeable luck) item: users mix them up (2026-11-20)
        Theme.Label(g, "x220 y246 w776 h20", "Uses the Portable Crack (from The Limbo achievement), not the Portable Device.", "muted")
        this._SaveBar(p)
    }

    ; ---- page: Craft ------------------------------------------------------------

    ; Shop rows and recipes come from lib\GameLists.ahk (what the game sells / crafts).
    _PageCraft(p) {
        g := this._gui
        this._Panel(204, 152, 396, 100, "Auto-craft")
        this._BoolField(220, 186, "Fish shop", "Craft.enabled", 1)
        this._BoolField(220, 216, "Stella cauldron step", "Craft.cauldron", 0)
        this._Panel(616, 152, 396, 100, "Stella's cauldron recipe")
        items := [I18n.T("(none)")]           ; row 1 = no recipe (saved as "")
        for n in GameLists.Recipes
            items.Push(n)
        this._craftTarget := Theme.Dropdown(g, 632, 184, 260, items)
        this._craftTarget.OnEvent("Change", ObjBindMethod(this, "_MarkDirty", p))
        this._ids["Craft.craftTarget"] := this._craftTarget
        Theme.Label(g, "x632 y218 w364 h20", "Typed into the cauldron search, first result is used.", "muted")

        names := GameLists.Shop
        this._Panel(204, 268, 808, 348, "Buy at the Fisher shop"
            , "Bought only after a 'Potion Crafted' notification: one buy per notification.")
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
        this.cfg.Set("Craft.craftTarget", (this._craftTarget.Value <= 1) ? "" : t)
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
            . "Ticking a type ticks all of its quests.`n`nThe interval is under Settings > General.")
        Theme.Button(g, "x692 y186 w148 h30", "Tick all", (*) => this._QuestAll(true))
        Theme.Button(g, "x848 y186 w148 h30", "Untick all", (*) => this._QuestAll(false))
        this._Panel(676, 260, 336, 100, "Dismiss")
        this._BoolField(692, 294, "Dismiss unticked quests", "quests.dismissDisabled", 0, , "WARNING: Dismiss abandons the quest and its progress. "
            . "Off (default): unticked quests are only skipped, never abandoned.")
        Theme.Label(g, "x692 y324 w304 h20", "Abandons the quest and its progress.", "muted")
        this._Panel(676, 376, 336, 232, "Daily quests")
        this._BoolField(692, 410, "Do daily quests", "DailyQuests.enabled", 0)
        this._IntField(692, 446, "Check every", "DailyQuests.intervalMin", 30, "min", 140, 5, 720)   ; DailyQuestsTask.IntervalMs: 5..720
        this._StrField(692, 482, "Reroll quests with", "DailyQuests.reroll", "", 148, 156)
        Theme.Label(g, "x692 y516 w304 h40", "Words, comma between (e.g. craft, fish). Free rerolls only, never Buy Reroll.", "muted")
        this._BoolField(692, 566, "Use potions for Use quests", "DailyQuests.usePotions", 0)
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
        Theme.Help(g, 512, 482, "How many to buy. Type all to buy the whole stock the shop shows (50 when the stock does not read).")
        this._mName := Theme.Edit(g, 220, 500, 240, 28)
        this._mQty := Theme.Edit(g, 468, 500, 60, 28, "1")      ; a number or all
        this._ids["merch.name"] := this._mName, this._ids["merch.qty"] := this._mQty
        Theme.Button(g, "x220 y540 w84 h30", "Add", (*) => this.MerchAdd(), "primary")
        Theme.Button(g, "x310 y540 w84 h30", "Update", (*) => this._MerchUpdate())
        Theme.Button(g, "x400 y540 w84 h30", "Remove", (*) => this._MerchRemove())
        ; paused items stay on the list and are skipped until resumed
        this._mPause := Theme.Button(g, "x490 y540 w94 h30", "Pause", (*) => this.MerchPause())
        this._ids["merch.pause"] := this._mPause
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
            lv.Add(, it["name"] (UiLogic.MerchPaused(it) ? "  (" I18n.T("Paused") ")" : "")
                , it.Has("qty") ? UiLogic.QtyText(it["qty"]) : 1)
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
        this._mQty.Value := String(it.Has("qty") ? UiLogic.QtyText(it["qty"]) : 1)
        Theme.SetText(this._mPause, I18n.T(UiLogic.MerchPaused(it) ? "Resume" : "Pause"))
    }

    ; Item from the edit boxes, its name title-cased ("gear b" -> "Gear B").
    _MerchItemFromEdits() {
        name := UiLogic.TitleCase(Trim(this._mName.Value))
        if (name = "")
            return ""
        this._mName.Value := name
        return Map("name", name, "qty", UiLogic.QtyOrAll(this._mQty.Value, 1))
    }

    MerchAdd() {
        it := this._MerchItemFromEdits()
        if !IsObject(it)
            return Theme.SetText(this._mStatus, I18n.T("Type an item name first."))
        who := this._CurWho()
        this._merch[who].Push(it)
        this._MerchFill(who)
        this._MarkDirty("Merchants")
        Theme.SetText(this._mStatus, I18n.F("Added to {1}. Save to keep it.", who))
    }

    _MerchUpdate() {
        who := this._CurWho()
        row := this._mlv[who].GetNext(0)
        it := this._MerchItemFromEdits()
        if (!row || !IsObject(it))
            return Theme.SetText(this._mStatus, I18n.F("Select a {1} row and fill in the item name.", who))
        if UiLogic.MerchPaused(this._merch[who][row])
            it["paused"] := 1                   ; editing a paused item keeps it paused
        this._merch[who][row] := it
        this._MerchFill(who)
        this._MarkDirty("Merchants")
        Theme.SetText(this._mStatus, I18n.T("Updated. Save to keep it."))
    }

    _MerchRemove() {
        who := this._CurWho()
        row := this._mlv[who].GetNext(0)
        if !row
            return Theme.SetText(this._mStatus, I18n.F("Select a {1} row first.", who))
        this._merch[who].RemoveAt(row)
        this._MerchFill(who)
        this._MarkDirty("Merchants")
        Theme.SetText(this._mStatus, I18n.T("Removed. Save to keep it."))
    }

    ; Pause / Resume the selected row: a paused item stays on the list and
    ; is not bought until it is resumed. -> true when a row was toggled
    MerchPause() {
        who := this._CurWho()
        row := this._mlv[who].GetNext(0)
        if !row
            return (Theme.SetText(this._mStatus, I18n.F("Select a {1} row first.", who)), false)
        it := this._merch[who][row]
        if UiLogic.MerchPaused(it)
            it.Delete("paused")
        else
            it["paused"] := 1
        on := it.Has("paused")
        this._MerchFill(who)
        this._mlv[who].Modify(row, "Select Focus")
        Theme.SetText(this._mPause, I18n.T(on ? "Resume" : "Pause"))
        this._MarkDirty("Merchants")
        Theme.SetText(this._mStatus, I18n.T(on ? "Paused: it is skipped until you resume it. Save to keep it." : "Resumed. Save to keep it."))
        return true
    }

    _MerchSave() {
        live := this.cfg.Data("merchants")
        for who in ["Mari", "Jester"]
            live[who] := UiLogic.Copy(this._merch[who])
        this.cfg.SaveData("merchants")
        return ""
    }

    ; ---- pages: Biomes ("Biomes & Potions") and Potions -------------------------

    ; The dry-run row at the top of Biomes and Potions: the switch and the
    ; "dry run is OFF" banner (an untitled card).
    _DryRow() {
        g := this._gui
        this._Panel(204, 152, 808, 44)
        this._DryCheck(220, 164)
        this._dryOff.Push(Theme.Rect(g, 372, 160, 628, 28, Theme.Accent))
        this._dryOff.Push(Theme.Label(g, "x384 y164 w608 h20 +0x200"
            , Chr(0x26A0) "  DRY RUN IS OFF  " Chr(0x2014) "  unlocked potions WILL be used in rare biomes", "button", Theme.Accent, Theme.Ink))
        this._dryOn.Push(Theme.Label(g, "x380 y166 w616 h20", "Dry run is on: every potion check runs and is logged, nothing is clicked.", "muted"))
    }

    ; Biomes (page "Biomes & Potions"): the rare biome list and the potions
    ; used in each biome; saves data\biomes.json only. The potion list,
    ; unlock and caps are on the Potions page.
    _PageBiomes(p) {
        g := this._gui
        this._DryRow()
        this._Panel(204, 208, 808, 408, "Biomes", "Qty is how many of a potion to use in that biome. Type all to use every one you own, still within the potion safety caps on the Potions page.")
        ; the biome list (left half)
        bw := [180, 64, 120]
        ; "Rare" here marks one biome (es / pt / fr singular; the Stats
        ; column counts them: plural)
        Theme.ListHeader(g, 220, 234, bw, ["Biome", I18n.TC("Rare", "biome list"), "Potions"])
        this._lvB := Theme.ListView(g, 220, 252, 364, 348, ["Biome", "Rare", "Potions"], bw, , ObjBindMethod(this, "_BiomeColor"))
        this._lvB.OnEvent("ItemSelect", ObjBindMethod(this, "_BiomeSelect"))
        this._ids["biomes"] := this._lvB
        ; the selected biome (right half)
        this._bName := Theme.Label(g, "x632 y230 w220 h24", "Select a biome", "value")
        this._bRare := Theme.Check(g, 868, 232, "Rare", 0, ObjBindMethod(this, "_BiomeRareFlip"), "pill", 60)
        this._ids["biomeRare"] := this._bRare
        pw := [310, "54 Center"]
        Theme.ListHeader(g, 632, 270, pw, ["Potion used here", "Qty"])
        this._lvBP := Theme.ListView(g, 632, 288, 364, 260, ["Potion", "Qty"], pw)
        this._bpEmpty := Theme.EmptyHint(g, this._lvBP, "Select a biome on the left")
        ; biome lists name potions by potions.json id (the three "Godly
        ; Potion"s share a name): items show the id (+ desc), Add writes the id
        ch := this._PotionChoices()
        this._bpIds := ch.ids
        ; the buttons wide enough for their text with a margin (Theme.BtnPad)
        this._bpDdl := Theme.Dropdown(g, 632, 562, 172, ch.labels)
        this._bpQty := Theme.Edit(g, 810, 561, 44, 28, "1")       ; a number or all
        Theme.Button(g, "x860 y561 w64 h28", "Add", (*) => this.BiomePotionAdd())
        Theme.Button(g, "x930 y561 w66 h28", "Remove", (*) => this._BiomePotionRemove())
        this._ids["bpDdl"] := this._bpDdl, this._ids["bpQty"] := this._bpQty
        p.load := ObjBindMethod(this, "_BiomesLoad")
        p.save := ObjBindMethod(this, "_BiomesSave")
        this._SaveBar(p)
    }

    ; Potions: every potion of data\potions.json with its lock and caps.
    ; Unlock / Re-lock save at once; caps on Save (potions.json only).
    _PagePotions(p) {
        g := this._gui
        this._DryRow()
        ; the lock help sits on the card: under the (hidden) Unlock button it
        ; floated alone while no potion was picked
        this._Panel(204, 208, 808, 408, "Potions", "Top-tier potions are locked by default. Unlock asks first and names the caps. "
            . "Unlock and re-lock are saved at once; caps on Save.")
        ; the potion list (left half); the status column fits es / pt
        ; "Desbloqueada" (it showed "Desbloq…"), the number columns as narrow
        ; as their captions allow
        cw := [146, 104, 40, 38, 48]
        Theme.ListHeader(g, 220, 234, cw, ["Potion", "Status", "Biome", "Day", "Run"])
        this._lvP := Theme.ListView(g, 220, 252, 376, 348, ["Potion", "Status", "Biome", "Day", "Run"], cw, , ObjBindMethod(this, "_PotionColor"))
        this._lvP.OnEvent("ItemSelect", ObjBindMethod(this, "_PotionSelect"))
        this._ids["potions"] := this._lvP
        ; the selected potion (right half): name, description, caps, lock
        this._pName := Theme.Label(g, "x632 y230 w340 h24", "Select a potion", "value")      ; clear of the card's "?"
        this._pDesc := Theme.Label(g, "x632 y258 w364 h36", "", "muted")
        this._ids["potionDesc"] := this._pDesc
        ; caps a little narrower so Apply caps fits vi "Ap dung gioi han"
        for cap in [["PER BIOME", 632], ["PER DAY", 710], ["PER RUN", 788]]
            Theme.Label(g, "x" cap[2] " y306 w76 h16", cap[1], "caps")
        this._capB := Theme.Edit(g, 632, 324, 72, 28, "", "Number")
        this._capD := Theme.Edit(g, 710, 324, 72, 28, "", "Number")
        this._capR := Theme.Edit(g, 788, 324, 72, 28, "", "Number")
        this._ids["capBiome"] := this._capB, this._ids["capDay"] := this._capD, this._ids["capRun"] := this._capR
        Theme.Button(g, "x868 y324 w128 h28", "Apply caps", (*) => this._PotionCaps())
        this._btnUnlock := Theme.Button(g, "x632 y372 w180 h32", "Unlock" Chr(0x2026), (*) => this.UnlockSelected(), "primary")
        this._btnRelock := Theme.Button(g, "x632 y372 w180 h32", "Re-lock", (*) => this.RelockSelected())
        this._SetHidden(this._btnUnlock, true)
        this._SetHidden(this._btnRelock, true)
        p.load := ObjBindMethod(this, "_PotionsLoad")
        p.save := ObjBindMethod(this, "_PotionsSave")
        this._SaveBar(p)
    }

    _BiomesLoad() {
        this._bio := []
        try this._bio := UiLogic.Copy(this.cfg.Data("biomes")["biomes"])
        this._bSel := 0
        this._FillBiomes()
        this._BiomeShow()
    }

    _PotionsLoad() {
        this._pot := []
        try this._pot := UiLogic.Copy(this.cfg.Data("potions")["potions"])
        this._pSel := 0
        this._FillPotions()
        this._PotionShow()
    }
    _FillBiomes() {
        lv := this._lvB
        lv.Opt("-Redraw")
        lv.Delete()
        for b in this._bio
            lv.Add(, b["name"], (b.Has("rare") && b["rare"]) ? Chr(0x2726) " " I18n.T("rare") : "", this._BiomePotSummary(b))
        lv.Opt("+Redraw")
        Theme.FitLastCol(lv)           ; after +Redraw: the scrollbar is known then
        if this._bSel
            lv.Modify(this._bSel, "Select Focus Vis")
    }

    _BiomePotSummary(b) {
        if !(b.Has("potions") && b["potions"] is Array && b["potions"].Length)
            return ""
        n := 0, all := false
        for e in b["potions"] {
            q := (e is Map && e.Has("qty")) ? e["qty"] : 1
            if UiLogic.IsAllQty(q)
                all := true
            else if IsNumber(q)
                n += q
        }
        if all
            return n ? I18n.F("{1} ({2} uses + all)", b["potions"].Length, n) : I18n.F("{1} (all owned)", b["potions"].Length)
        return I18n.F("{1} ({2} uses)", b["potions"].Length, n)
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
        Theme.SetText(this._bName, IsObject(b) ? b["name"] : I18n.T("Select a biome"))
        this._bRare.Value := IsObject(b) && b.Has("rare") && b["rare"]
        lv := this._lvBP
        lv.Delete()
        if (IsObject(b) && b.Has("potions") && b["potions"] is Array) {
            for e in b["potions"]
                lv.Add(, e["name"], e.Has("qty") ? UiLogic.QtyText(e["qty"]) : 1)
        }
        ; an empty list shows a hint instead
        empty := lv.GetCount() = 0
        Theme.SetText(this._bpEmpty, IsObject(b) ? I18n.F("No potions for {1} yet", b["name"]) : I18n.T("Select a biome on the left"))
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
        qty := UiLogic.QtyOrAll(this._bpQty.Value, 1)
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
            lv.Add(, this._PotionLabel(e), I18n.T(this._Locked(e) ? "Locked" : "Unlocked"), e.Has("perBiome") ? e["perBiome"] : "", e.Has("perDay") ? e["perDay"] : "", e.Has("perRun") ? e["perRun"] : "")
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
        Theme.SetText(this._pName, IsObject(e) ? this._PotionLabel(e) "   " Chr(0xB7) "  " I18n.T(this._Locked(e) ? "locked" : "unlocked") : I18n.T("Select a potion"))
        this._capB.Value := IsObject(e) && e.Has("perBiome") ? String(e["perBiome"]) : ""
        this._capD.Value := IsObject(e) && e.Has("perDay") ? String(e["perDay"]) : ""
        this._capR.Value := IsObject(e) && e.Has("perRun") ? String(e["perRun"]) : ""
        Theme.SetText(this._pDesc, IsObject(e) && e.Has("desc") ? Trim(String(e["desc"])) : "")
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
        this._MarkDirty("Potions")
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

    ; Biomes Save: biomes.json only (the Potions page's unsaved caps stay
    ; on that page).
    _BiomesSave() {
        liveB := this.cfg.Data("biomes")
        if (liveB.Has("biomes") && liveB["biomes"] is Array)
            UiLogic.MergeByKey(liveB["biomes"], this._bio, ["rare", "potions"])
        this.cfg.SaveData("biomes")
        this._Fire("potionsChanged")
        return ""
    }

    ; Potions Save: the caps into potions.json (never "locked": Unlock /
    ; Re-lock save that at once); the Biomes page's unsaved edits stay there.
    _PotionsSave() {
        liveP := this.cfg.Data("potions")
        if (liveP.Has("potions") && liveP["potions"] is Array)
            UiLogic.MergeByKey(liveP["potions"], this._pot, ["perBiome", "perDay", "perRun"])
        this.cfg.SaveData("potions")
        this._Fire("potionsChanged")
        return ""
    }

    ; ---- page: Webhooks ---------------------------------------------------------

    _PageWebhooks(p) {
        g := this._gui
        x := {on: 216, name: 266, url: 354, mask: 452, men: 508, ev: 580, test: 916, del: 974}
        this._hx := x
        this._Panel(204, 152, 808, 388, "Webhooks"
            , "URLs are stored only in settings.ini and are never shown again after saving (" UiLogic.Dots " + last 4). "
            . "Leave URL empty to keep the saved one, or paste a new one to replace it.`n"
            . "Stop = stop message (every enabled webhook also gets a start message). Error = errors and recovery. "
            . "Mention = Discord user or role ID, used for rare biomes. Test sends one message to that row's saved webhook.")
        ; the title only as wide as it needs: the caption rows start under it
        Theme.MoveTo(this.Ctrl("panelTitle:Webhooks:Webhooks"), , , 200)
        ; column captions on the lower row, each as wide as its column (the
        ; URL's one over the mask too; MENTION up to the 2nd event column)
        y2 := Dashboard.HeadRows[2], cw := Dashboard.EventCapW, pitch := Dashboard.EventPitch
        capX := (j) => x.ev + (j - 1) * pitch + pitch // 2 - cw // 2      ; event caption j's left
        this._hookCaps := []
        for h in [["ON", x.on, 46], ["NAME", x.name, 84], ["URL", x.url, 146], ["MENTION", x.men, capX(2) - x.men - 3]]
            this._hookCaps.Push(this._HookCap("x" h[2] + 2 " y" y2 " w" h[3] " h14", h[1]))
        for j, cap in Dashboard.EventCaps
            this._hookCaps.Push(this._HookCap("x" capX(j) " y" Dashboard.HeadRows[2 - Mod(j, 2)] " w" cw " h14 Center", cap, Dashboard.EventCap(cap)))
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
            r.test := Theme.Button(g, "x" x.test " y" y " w56 h28", "Test", ObjBindMethod(this, "HookTest", i), "quiet")
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
        this._hookAdd := Theme.Button(g, "x216 y" 202 + Dashboard.MaxHooks * 36 + 4 " w164 h30", "+  Add webhook", (*) => this.HookAdd())
        ; rare aura alert (2026-11-16): the Rare webhooks, a screenshot, one ping
        this._Panel(204, 552, 808, 66, "Rare aura alert", "A new aura you roll that is as rare as the number on the right (1 in N) or rarer "
            . "goes to the webhooks with Rare ticked, with a screenshot, and pings the user ID. Leave the ID empty for no ping.")
        this._BoolField(216, 584, "Ping on rare aura", "AuraAlert.enabled", 0, 210)
        this._StrField(452, 584, "User ID", "AuraAlert.userId", "", 150, 110)
        ; the label gets the room up to the box (fr "Plus rare que 1 sur"
        ; shrank to 7 pt beside free space); 10000000 fits 104
        this._StrField(728, 584, "Rarer than 1 in", "AuraAlert.minRarity", "10000000", 104, 168)
        ; the Clips page's own threshold beside this one, on the caption row
        ; (2026-11-20: clips at 1 in 500m, a ping at 1 in 375m from this 50m)
        Theme.MoveTo(this.Ctrl("panelTitle:Webhooks:Rare aura alert"), , , 260)
        this._ids["alertClipNote"] := Theme.Label(g, "x476 y560 w500 h16 Right", "", "small")
        this.Ctrl("AuraAlert.minRarity").OnEvent("Change", ObjBindMethod(this, "_RarityNotes"))
        p.onShow := ObjBindMethod(this, "_RarityNotes")
        p.load := ObjBindMethod(this, "_HooksLoad")
        p.save := ObjBindMethod(this, "_HooksSave")
        p.validate := ObjBindMethod(this, "_HooksCheck")
        this._SaveBar(p)
    }

    ; A Discord column caption (translated; `shown` replaces the usual
    ; translation). Captions do not shrink (Theme.MinPt): a text wider than
    ; its caption needs a shorter word.
    _HookCap(opts, text, shown := "") {
        c := Theme.Label(this._gui, opts, text, "caps")
        if (shown != "" && shown != c.Text)
            c.Text := shown
        c.GetPos(, , &w)
        if (Theme.TextW(c) > w)
            Theme.FitFont(c, "caps", w)
        return c
    }

    ; "" or why the Webhooks page cannot be saved (the rare aura alert fields).
    _HooksCheck() {
        ; each row's MENTION as the sender reads it (Webhook.NormalizeMention):
        ; a name or @everyone was saved and then never pinged anyone
        for i, r in this._rows {
            if (i > this._hooks.Length)
                break
            men := Trim(r.men.Value)
            if (men != "" && Webhook.NormalizeMention(men) = "")
                return "webhook row " i ": the mention is a Discord user ID like 123456789012345678 or a role ID like &123456789012345678 "
                    . "(names and @everyone do not ping; @everyone is the switch on Settings > General)"
        }
        id := Trim(this.Ctrl("AuraAlert.userId").Value)
        if (id != "" && Webhook.NormalizeMention(id) = "")
            return "aura alert: the user ID is a number like 123456789012345678 (Discord: right-click yourself > Copy User ID)"
        if (Auras.ParseRarity(this.Ctrl("AuraAlert.minRarity").Value) = "")
            return "aura alert rarity: type a number like 10,000,000, 10m or 1b"
        return ""
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
                Theme.SetText(r.mask, h["url"] = "" ? I18n.T("(none)") : UiLogic.MaskSecret(h["url"]))
            }
            for c in r.ctrls
                this._SetHidden(c, !has)
        }
        n := Min(this._hooks.Length, Dashboard.MaxHooks)
        this._SetHidden(this._hookEmpty, n > 0)
        Theme.MoveTo(this._hookAdd, 216 + this._sh.dx, (n ? 202 + n * 36 + 4 : 244) + this._sh.dy)    ; right under the last row
        if (this._hookAdd.Visible)
            Theme.Repaint(this._gui)
        Theme.SetEnabled(this._hookAdd, this._hooks.Length < Dashboard.MaxHooks)
    }

    HookAdd() {
        this._HooksPull()
        if (this._hooks.Length >= Dashboard.MaxHooks)
            return
        this._hooks.Push(Map("name", "Webhook " (this._hooks.Length + 1), "url", "", "mention", "", "enabled", 1
            , "events", Config.EventTypes.Clone()))   ; every box ticked (the user, 2026-11-26)
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
        this._Panel(204, 152, 808, 84, "Preset", "A ready calibration recorded at one resolution. "
            . "Apply copies it over your calibration (the old one is kept as data\calibration.json.bak). "
            . "Windowed: Yes lets Roblox run in a window (the window's size is the resolution); the macro never resizes it. No = fullscreen only. "
            . "Scale: your Windows display scale. Auto reads it from Windows; the macro measures the Roblox window, so any scale works with the preset for your resolution.")
        this._calPreset := Theme.Dropdown(g, 220, 184, 160)
        this._ids["calPreset"] := this._calPreset
        this._ids["calPresetApply"] := Theme.Button(g, "x388 y182 w136 h30", "Apply preset", (*) => this._CalApplyPreset())
        Theme.Label(g, "x532 y188 w82 h20", "Windowed", "body")
        this._calWindowed := Theme.Dropdown(g, 614, 184, 70, [I18n.T("No"), I18n.T("Yes")])   ; read by row (1 No, 2 Yes)
        this._calWindowed.Choose(this.cfg.Get("General.windowed", 0) = 1 ? 2 : 1)
        this._calWindowed.OnEvent("Change", ObjBindMethod(this, "_CalWindowedChange"))
        this._ids["calWindowed"] := this._calWindowed
        ; Scale (2026-11-16): like Windowed, saved at once
        Theme.Label(g, "x702 y188 w46 h20", "Scale", "body")
        ; made empty, then filled (as the preset list): made with its 6 items
        ; the control is 6 rows tall and the page below it stopped painting
        this._calScale := Theme.Dropdown(g, 748, 184, 90)
        this._calScale.Add(Calibrate.Scales)
        sc := Calibrate.ScaleFromText(this.cfg.Get("General.displayScale", 0))
        idx := 1
        for i, t in Calibrate.Scales
            if (Calibrate.ScaleFromText(t) = sc && sc > 0)
                idx := i
        this._calScale.Choose(idx)
        this._calScale.OnEvent("Change", ObjBindMethod(this, "_CalScaleChange"))
        this._ids["calScale"] := this._calScale
        this._calPresetNote := Theme.Label(g, "x220 y216 w776 h18", "", "muted")
        this._ids["calPresetNote"] := this._calPresetNote
        this._calPresets := []
        this._Panel(204, 248, 808, 368, "Steps", I18n.F("Hover each target in Roblox and press the capture key ({1}). Nothing is clicked. Esc cancels the wizard.", this._CapKey())
            . " " I18n.T("Steps marked automatic are found on screen by the macro when their window is open: no hovering needed. Record selected still records one by hand."))
        cw := [200, 156, 420]      ; status: de "aufgenommen" with its tick, es "por defecto (opcional)"
        Theme.ListHeader(g, 220, 276, cw, ["Step", "Status", "What to hover"])
        this._lvC := Theme.ListView(g, 220, 294, 776, 306, ["Step", "Status", "What to hover"], cw, "+Multi", ObjBindMethod(this, "_CalColor"))
        this._ids["calibrate"] := this._lvC
        n0 := this._FixedBar()
        Theme.Button(g, "x204 y628 w170 h30", "Record selected", (*) => this._CalRun("selected"), "primary")
        Theme.Button(g, "x382 y628 w110 h30", "Run all", (*) => this._CalRun("all"))
        Theme.Button(g, "x500 y628 w100 h30", "Refresh", (*) => this._CalLoad(), "quiet")
        this._calStatus := Theme.Label(g, "x610 y634 w402 h20 Right", "", "muted")
        this._FixedBar(n0)
        this._ids["calStatus"] := this._calStatus
        this._calOk := []
        p.load := ObjBindMethod(this, "_CalLoad")
        p.onShow := ObjBindMethod(this, "_CalLoad")
    }

    ; A calibration step's "what to hover" in the language in use.
    static CalPrompt(s) {
        try {
            if (s.Has("fmt") && s["fmt"] != "")
                return I18n.F(s["fmt"], s["arg"])
            return I18n.T(s["prompt"])
        }
        return ""
    }

    static _CalIsOptional(id) {
        for o in SetupCheck.CalOptional
            if (o = id)
                return true
        return false
    }

    ; Windowed Yes / No: saved at once and used from the next window check
    ; Scale: Auto (0) or a percent; saved at once, used for the preset match
    _CalScaleChange(ctrl, *) {
        sc := Calibrate.ScaleFromText(ctrl.Text)
        this.cfg.Set("General.displayScale", sc)
        try this.cfg.Save()
        Calibrate.ScaleOverride := sc
        this._CalPresetsLoad()
    }

    _CalWindowedChange(ctrl, *) {
        on := (ctrl.Value = 2)
        this.cfg.Set("General.windowed", on ? 1 : 0)
        try this.cfg.Save()
        Roblox.AllowWindowed := on
        this._CalPresetsLoad()
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
            try ok := ok && Calibrate.Stored(s["id"])       ; a place found on screen this run is not a recording
            ; optional steps have built-in positions: not recorded is fine
            ; (the 3 Daily Rewards / Daily Quests steps showed "missing" on
            ; every preset, 2026-11-14)
            opt := !ok && Dashboard._CalIsOptional(s["id"])
            ; found on screen by the macro (lib\AutoCal.ahk): nothing to
            ; record; recorded by hand it shows "recorded" like the rest
            auto := !ok && s.Has("auto") && s["auto"]
            done += (ok || opt || auto)
            this._calOk.Push(ok || opt || auto)
            lv.Add(, s["id"], ok ? Chr(0x2713) " " I18n.T("recorded") : auto ? Chr(0x2713) " " I18n.T("automatic") : I18n.T(opt ? "default (optional)" : "missing"), Dashboard.CalPrompt(s))
        }
        lv.Opt("+Redraw")
        Theme.FitLastCol(lv)           ; after +Redraw: the scrollbar is known then
        Theme.SetText(this._calStatus, I18n.F("{1} of {2} steps ready", done, steps.Length))
        this._CalPresetsLoad()
    }

    ; Preset list (whatever data\presets holds), pre-selected to the one
    ; made at this system's display; the note says when none matches.
    _CalPresetsLoad() {
        list := [], sys := ""
        try list := Calibrate.Presets()
        try sys := Calibrate.System()
        this._calPresets := list
        labels := []
        for p in list
            labels.Push(p.label)
        dd := this._calPreset
        dd.Delete()
        if labels.Length
            dd.Add(labels)
        match := Calibrate.MatchPreset(list, sys)
        ; none made at this size: the nearest is picked (the one a first run uses)
        near := ""
        try near := Calibrate.NearestPreset(list, sys)
        idx := 0, nidx := 0
        for i, p in list {
            if (IsObject(match) && p.path = match.path)
                idx := i
            if (IsObject(near) && p.path = near.p.path)
                nidx := i
        }
        if (idx || nidx || list.Length)
            dd.Choose(idx ? idx : nidx ? nidx : 1)
        mine := IsObject(sys) ? I18n.F("{1}x{2} at {3}%", sys.w, sys.h, sys.scale) : I18n.T("unknown")
        win := Roblox.AllowWindowed
        Theme.SetText(this._calPresetNote, !list.Length ? I18n.T("No presets installed: calibrate below.")
            : idx ? I18n.F(win ? "Matches your window ({1})." : "Matches your display ({1}).", mine)
                . ((IsObject(sys) && match.scale != sys.scale) ? " " I18n.F("Made at {1}%: it fits any scale (the macro measures the Roblox window).", match.scale) : "")
            : I18n.F(win ? "No preset for your window ({1})." : "No preset for your display ({1}).", mine)
                . (!nidx ? "" : " " I18n.F(near.fit = "scaled" ? "Nearest: {1}, the same shape." : "Nearest: {1}, another shape: check the steps you use.", near.p.label)))
    }

    _CalApplyPreset() {
        i := this._calPreset.Value
        if !(i >= 1 && i <= this._calPresets.Length)
            return Theme.SetText(this._calPresetNote, I18n.T("Pick a preset first."))
        p := this._calPresets[i]
        err := Calibrate.ApplyPreset(p.path)
        this.Log("Calibrate: " (err = "" ? "preset " p.label " applied (the old calibration is in data\calibration.json.bak)" : "preset not applied: " err))
        this._CalLoad()
        if (err != "")
            Theme.SetText(this._calPresetNote, I18n.F("Not applied: {1}", err))
    }

    _CalColor(row) {
        return (row <= this._calOk.Length && !this._calOk[row]) ? Theme.Accent : ""
    }

    ; "all" = every step that needs hovering (the steps found on screen are
    ; left out); "selected" records the selected rows, automatic ones too
    ; (calibrating one by hand)
    _CalRun(which) {
        ids := "hand"
        if (which = "selected") {
            ids := []
            row := 0
            while (row := this._lvC.GetNext(row))
                ids.Push(this._lvC.GetText(row, 1))
            if !ids.Length
                return Theme.SetText(this._calStatus, I18n.T("Select one or more steps first."))
        }
        n := 0
        if this._shown              ; never shown (tests): no window, no focus
            this._gui.Minimize()
        try {
            n := this._cb.Has("calibrate") ? this._cb["calibrate"].Call(ids) : Calibrate.Run(ids)
        } catch Any as e {
            this.Log("Calibrate: " e.Message)
        }
        if this._shown
            this._gui.Restore()
        this._CalLoad()
        this.Log("Calibrate: " (IsInteger(n) ? n : 0) " step(s) recorded")
    }

    ; ---- pages: General ("Settings") and Look ------------------------------------

    ; General (page "Settings"): private server, routes, intervals, recovery,
    ; alerts and hotkeys. The theme, language and animations are on Look.
    _PageSettings(p) {
        g := this._gui
        this._Panel(204, 152, 396, 80, "Private server", "Secret. Stored only in settings.ini, never shown or logged.")
        this._psEdit := Theme.Edit(g, 220, 186, 206, 28, "", "Password")
        this._psEdit.OnEvent("Change", ObjBindMethod(this, "_MarkDirty", p))
        ; room for a translated "(not set)" and a gap before Clear (de
        ; "(nicht gesetzt)" touched "Leeren"); Clear padded like every button
        this._psMask := Theme.Label(g, "x432 y192 w82 h18", "", "small")
        Theme.Button(g, "x522 y186 w66 h28", "Clear", (*) => this._PsClear(), "quiet")
        this._ids["privateServer"] := this._psEdit, this._ids["privateServerMask"] := this._psMask

        this._Panel(204, 248, 396, 164, "Intervals")
        ; 170: vi "Xem chat thuong nhan" fits at 130 % too
        this._IntField(220, 278, "Quest board every", "General.questIntervalMin", 30, "min", 170, 1)
        this._IntField(220, 311, "Anti-AFK every", "recovery.afkMin", 15, "min", 170)
        this._IntField(220, 344, "Stuck reset after", "recovery.stuckMin", 10, "min", 170)
        this._IntField(220, 377, "Merchant chat check", "merchant.chatPollSec", 5, "s", 170)

        this._Panel(204, 428, 396, 164, "Recovery")
        this._BoolField(220, 460, "Auto-rejoin and anti-AFK", "recovery.enabled", 1)
        this._IntField(220, 490, "Load wait", "recovery.loadSec", 20, "s", 160)
        this._BoolField(220, 526, "Anti ghost server (rejoin if moved out of it)", "recovery.antiGhost", 1, 360)
        this._BoolField(220, 556, "Bring Roblox back when I'm away", "General.awayRefocus", 1, 360)

        this._Panel(616, 152, 396, 164, "Alerts")
        this._BoolField(632, 186, "Sound on rare biome", "General.sound", 1)
        this._BoolField(632, 214, "Ping @everyone on the biomes below", "General.everyonePing", 1)
        e := this._StrField(632, 244, "@everyone biomes", "General.everyoneBiomes", "DREAMSPACE,GLITCHED,CYBERSPACE", 214, 150)
        e.SetFont(Theme.FontOpt("muted", Theme.IsScaled(g)))      ; a point smaller: the default list fits the box
        ; a role (or user) ping per rare biome (2026-11-22, a tester: not
        ; only @everyone); checked like the webhook MENTION column on Save
        e := this._StrField(632, 278, "Role pings per biome", "General.biomePings", "", 214, 150)
        e.SetFont(Theme.FontOpt("muted", Theme.IsScaled(g)))

        this._Panel(616, 364, 396, 68, "Routes", "Every walk that comes with the macro was recorded with Sol's RNG VIP gamepass, which walks faster. "
            . "Without VIP you walk slower and the walks fall short: turn this off and record your own walks under Help > Routes.")
        this._BoolField(632, 396, "VIP gamepass routes", "General.vip", 1)

        this._Panel(616, 448, 396, 80, "Hotkeys")
        this._hkText := Theme.Label(g, "x632 y474 w364 h44", "", "body")
        p.load := ObjBindMethod(this, "_SettingsLoad")
        p.save := ObjBindMethod(this, "_SettingsSave")
        p.validate := ObjBindMethod(this, "_SettingsCheck")
        this._SaveBar(p)
    }

    ; "" or why Settings cannot be saved: a typed private server link the
    ; rejoin would refuse (RecoveryTask.LinkOk, as the setup wizard) was
    ; saved quietly and auto-rejoin then failed at 3 AM.
    _SettingsCheck() {
        why := Dashboard.BiomePingsProblem(this.Ctrl("General.biomePings").Value)
        if (why != "")
            return why
        typed := this._psWipe ? "" : Trim(this._psEdit.Value)
        if (typed = "")
            return ""
        if (SubStr(typed, 1, 23) != "https://www.roblox.com/" || StrLen(typed) <= 23 || RegExMatch(typed, "[\s`"<>``\\|^]"))
            return "settings: that is not a Roblox private server link (it starts with https://www.roblox.com/)"
        return ""
    }

    ; "" or why General.biomePings text cannot be saved: each entry is
    ; BIOME=ID with a role ID (&123 / <@&123>) or a user ID, as the webhook
    ; MENTION column (Webhook.NormalizeMention: no @everyone / @here).
    static BiomePingsProblem(text) {
        r := Webhook.ParseBiomePings(text)
        if !r.bad.Length
            return ""
        return 'role pings: "' SubStr(r.bad[1], 1, 40) '" is not BIOME=ID. Write SINGULARITY=&123456789012345678 '
            . "(& + role ID, or a user ID), entries separated by commas"
    }

    ; ---- page: Look (the theme editor) -------------------------------------------

    static LookBaseLabels := Map("Bg", "Background", "PanelC", "Panels", "Text", "Text", "Accent", "Accent")
    static LookDerivedLabels := Map("SideBg", "Sidebar", "CardBg", "Cards", "FieldBg", "Fields", "FrameC", "Borders", "HoverBg", "Hover"
        , "OffBg", "Off switch", "Muted", "Muted text", "Ink", "On accent", "AccentHi", "Accent hover", "Pulse", "Pulse")
    static LookRoleLabels := Map("title", "Titles", "head", "Headings", "body", "Body text", "button", "Buttons", "nav", "Menu", "small", "Small text")
    static LookFits := ["Fill", "Fit", "Center", "Tile"]
    static LookSides := ["Left", "Right", "Top"]

    ; Look: every part of a theme (spec 5). Left: the theme list and its
    ; buttons, the 4 base colours, the background picture. Right: the fonts
    ; (or, with Advanced colours ticked, the 10 other shades in the same
    ; card), the UI size and language, the layout with the animations, and a
    ; preview drawn with the edited values. Built-in themes are read-only: a
    ; change asks to make a copy first. Save writes the edited theme (and the
    ; animations and the language); Apply saves, makes the picked theme the
    ; one in use and restarts the window. Messages go to the save bar's
    ; status line (id "look:note").
    _PageLook(p) {
        g := this._gui
        this._lookPage := p
        this._lk := "", this._lkName := "", this._lkDirty := false, this._lkFill := false
        this._lkPicSrc := "", this._lkPicExt := "", this._lkPicKeys := [], this._lkNames := [], this._lkHand := Map()
        this._lkAdv := false, this._editLayout := false
        this._lkPv := Map(), this._lkPvSeen := Map()
        ; installed font families, once per window
        this._lkFonts := Dashboard.FontFamilies()
        this._lkFontIdx := Map()
        this._lkFontIdx.CaseSense := false
        for i, f in this._lkFonts
            this._lkFontIdx[f] := i
        ; hooks (tests replace them)
        this._lookAsk := (title, text, ok, cancel) => Theme.Confirm(this._gui, title, text, ok, cancel)
        this._pickColor := (hex) => Theme.PickColor(this._gui.Hwnd, hex)
        this._pickFile := () => this._PickPictureFile()
        this._pickTheme := () => this._PickThemeFile()
        this._askName := (title, prompt, def) => this._AskText(title, prompt, def)
        this._importOk := (read) => this._ImportAsk(read)
        this._openFolder := (path) => Run('explorer.exe /select,"' path '"')

        ; Theme: the list and its buttons
        this._Panel(204, 152, 396, 144, "Theme", "Built-in themes cannot be changed: press Duplicate (or just change something) to make your own copy. "
            . "Save keeps your changes. Apply makes the picked theme the one in use and restarts the window.`n`n"
            . "Export writes one .moontheme file (picture included) to send to a friend. Import, or dropping that file on this window, adds it.")
        lv := Theme.ListView(g, 220, 184, 168, 106, ["Theme"], [168], "", (r) => this._LookRowColor(r))
        lv.OnEvent("ItemSelect", ObjBindMethod(this, "_LookListPick"))
        this._ids["look:list"] := lv
        ; 95 wide: de "Übernehmen" / "Umbenennen" fit without a smaller font
        for b in [["apply", 394, 184, "Apply", (*) => this.ApplyTheme(), "primary"]
                , ["duplicate", 493, 184, "Duplicate", (*) => this.LookDuplicate(), "normal"]
                , ["rename", 394, 216, "Rename", (*) => this.LookRename(), "normal"]
                , ["delete", 493, 216, "Delete", (*) => this.LookDelete(), "normal"]
                , ["import", 394, 248, "Import", (*) => this._LookImportPick(), "normal"]
                , ["export", 493, 248, "Export", (*) => this.LookExport(), "normal"]]
            this._ids["look:" b[1]] := Theme.Button(g, "x" b[2] " y" b[3] " w95 h26", b[4], b[5], b[6])

        ; Colours: the 4 base colours and the Advanced colours switch
        this._Panel(204, 304, 396, 196, "Colours", "The four base colours. Every other shade (fields, borders, hover, muted text...) is mixed from them, "
            . "unless you set it yourself under Advanced colours. Type a hex code like 0D1117 or press Pick.")
        this._lkSw := Map()
        for i, k in Theme.BaseKeys {
            y := 336 + (i - 1) * 32
            Theme.Label(g, "x220 y" y + 4 " w100 h20", Dashboard.LookBaseLabels[k])
            Theme.Rect(g, 324, y, 28, 28, Theme.FrameC)
            this._lkSw[k] := Theme.Rect(g, 325, y + 1, 26, 26, Theme.Bg)
            e := Theme.Edit(g, 360, y, 92, 28, "", "Limit7")
            e.OnEvent("Change", ObjBindMethod(this, "_LookHexEdit", k))
            this._ids["look:color:" k] := e
            this._ids["look:pick:" k] := Theme.Button(g, "x460 y" y " w76 h28", "Pick", ObjBindMethod(this, "_LookPick", k))
        }
        Theme.Label(g, "x220 y470 w364 h20", "The other shades: tick Advanced colours on the Text card.", "muted")

        ; Background: the picture, its placement and dim level
        this._Panel(204, 508, 396, 112, "Background", "None, a theme's picture, or a picture of your own (copied into the themes folder). "
            . "Dim darkens it so the text stays readable. Fill covers the window, Fit shows it whole, Center keeps its size, Tile repeats it.")
        Theme.Label(g, "x220 y544 w80 h20", "Picture")
        dd := Theme.Dropdown(g, 304, 540, 280)
        dd.OnEvent("Change", ObjBindMethod(this, "_LookPicPick"))
        this._ids["look:pic"] := dd
        Theme.Label(g, "x220 y580 w80 h20", "Placement")
        dd := Theme.Dropdown(g, 304, 576, 100)
        dd.Add(Dashboard._Tr(Dashboard.LookFits))
        dd.OnEvent("Change", (c, *) => this._LookUser("fit", ThemeStore.Fits[Max(1, c.Value)], c))
        this._ids["look:fit"] := dd
        Theme.Label(g, "x412 y580 w66 h20", "Dim")
        e := Theme.Edit(g, 482, 576, 56, 26, "", "Number Limit2")
        e.OnEvent("Change", (c, *) => this._LookUser("dim", c.Value, c))
        this._ids["look:dim"] := e
        Theme.Label(g, "x546 y580 w30 h20", "%", "muted")

        ; Text: a font and size per kind of text, or the Advanced colours
        parts := this._Panel(616, 152, 396, 262, "Text", "A font and size for each kind of text (installed fonts only). "
            . "UI size makes the whole window bigger. Language shows after Apply or the next start.`n`n"
            . "Advanced colours: a ticked box is Auto (mixed from the 4 base colours); untick it to set your own.")
        this._lkTextCap := parts[3]
        Theme.MoveTo(parts[3], , , 180)
        ; the switch sits in the card it changes (cards move and hide one by one)
        this._ids["look:advanced"] := Theme.Check(g, 816, 158, "Advanced colours", 0, ObjBindMethod(this, "_LookAdvToggle"), "box", 136)
        s0 := Theme.Sink.Length
        for i, r in ThemeStore.FontRoles {
            y := 184 + (i - 1) * 28
            Theme.Label(g, "x632 y" y + 3 " w76 h20", Dashboard.LookRoleLabels[r])
            dd := Theme.Dropdown(g, 712, y, 196)
            dd.Add(this._lkFonts)
            dd.OnEvent("Change", ObjBindMethod(this, "_LookFontPick", r))
            this._ids["look:font:" r] := dd
            e := Theme.Edit(g, 916, y, 52, 24, "", "Number Limit2")
            e.OnEvent("Change", ObjBindMethod(this, "_LookSizeEdit", r))
            this._ids["look:size:" r] := e
            Theme.Label(g, "x974 y" y + 3 " w24 h20", "pt", "muted")
        }
        this._lkFontView := Dashboard._SinkFrom(s0)
        s0 := Theme.Sink.Length
        for j, k in ThemeStore.DerivedKeys {
            cx := 632 + ((j - 1) // 5) * 186, y := 186 + Mod(j - 1, 5) * 30
            Theme.Label(g, "x" cx " y" y + 4 " w66 h18", Dashboard.LookDerivedLabels[k], "small")
            this._ids["look:auto:" k] := Theme.Check(g, cx + 68, y + 2, "", 1, ObjBindMethod(this, "_LookAutoTick", k))
            Theme.Rect(g, cx + 88, y + 1, 22, 22, Theme.FrameC)
            sw := Theme.Add(g, "Text", "x" cx + 89 " y" y + 2 " w20 h20 +0x100 Background" Theme.Bg)
            Theme.Clickable(sw, ObjBindMethod(this, "_LookPick", k))
            this._lkSw[k] := sw
            e := Theme.Edit(g, cx + 114, y, 62, 24, "", "Limit7")
            e.OnEvent("Change", ObjBindMethod(this, "_LookHexEdit", k))
            this._ids["look:color:" k] := e
        }
        this._lkAdvView := Dashboard._SinkFrom(s0)
        for c in this._lkAdvView
            this._SetHidden(c, true)
        Theme.Label(g, "x632 y355 w76 h20", "UI size")
        dd := Theme.Dropdown(g, 712, 352, 80, ["100 %", "115 %", "130 %"])
        dd.OnEvent("Change", (c, *) => this._LookUser("scale", ThemeStore.Scales[Max(1, c.Value)], c))
        this._ids["look:scale"] := dd
        ; language (UI.lang, lib\I18n.ahk): shown after Apply or the next start
        ; wide enough for every name ("Português (BR)" was cut at 104)
        Theme.Label(g, "x800 y355 w68 h20", "Language")
        this._langDdl := Theme.Dropdown(g, 872, 352, 124, I18n.Names)
        this._langDdl.OnEvent("Change", ObjBindMethod(this, "_MarkDirty", p))
        this._ids["UI.lang"] := this._langDdl
        this._ids["look:textNote"] := Theme.Label(g, "x632 y381 w364 h31", "", "muted")

        ; Layout: the sidebar, the layout editor, the animations
        this._Panel(616, 422, 396, 98, "Layout", "Sidebar: left, right or a row across the top. "
            . "Edit layout lets you move, resize and hide the cards of every page. Reset all puts every card back where the page puts it.")
        Theme.Label(g, "x632 y457 w64 h20", "Sidebar")
        dd := Theme.Dropdown(g, 700, 454, 96, Dashboard._Tr(Dashboard.LookSides))
        dd.OnEvent("Change", (c, *) => this._LookUser("sidebar", ThemeStore.Sidebars[Max(1, c.Value)], c))
        this._ids["look:sidebar"] := dd
        this._ids["look:resetAll"] := Theme.Button(g, "x896 y454 w100 h26", "Reset all", (*) => this.LookResetLayout())
        this._ids["look:editLayout"] := Theme.Check(g, 632, 488, "Edit layout", 0, (c) => this.EditLayout(c.Value), "pill", 110)
        this._BoolField(808, 488, "Animations", "UI.animations", 1)

        ; Preview: a small window drawn with the edited colours and fonts
        this._Panel(616, 528, 396, 92, "Preview")
        pv := this._lkPv
        pv["bg"] := Theme.Rect(g, 628, 556, 372, 56, Theme.Bg)
        ; the sidebar wide enough for vi "Trang chu" (it was cut at 56)
        pv["side"] := Theme.Rect(g, 628, 556, 72, 56, Theme.SideBg)
        pv["nav"] := Theme.Add(g, "Text", "x634 y573 w64 h22 +0x200", I18n.T("Home"))
        pv["title"] := Theme.Add(g, "Text", "x704 y556 w100 h38 +0x200", I18n.T("Title"))
        pv["small"] := Theme.Add(g, "Text", "x704 y594 w100 h18", I18n.T("Small text"))
        pv["frame"] := Theme.Rect(g, 808, 560, 108, 48, Theme.FrameC)
        pv["card"] := Theme.Rect(g, 809, 561, 106, 46, Theme.CardBg)
        pv["head"] := Theme.Add(g, "Text", "x814 y563 w98 h20", I18n.T("Heading"))
        pv["body"] := Theme.Add(g, "Text", "x814 y584 w98 h20", I18n.T("Body text"))
        pv["button"] := Theme.Add(g, "Text", "x924 y570 w72 h28 +0x200 Center", I18n.T("Button"))
        this._ids["look:preview"] := pv["bg"]

        p.load := ObjBindMethod(this, "_LookLoad")
        p.save := ObjBindMethod(this, "_LookSave")
        this._SaveBar(p)
        this._ids["look:note"] := p.status
    }

    ; the controls made since Sink position s0
    static _SinkFrom(s0) {
        out := []
        Loop Theme.Sink.Length - s0
            out.Push(Theme.Sink[s0 + A_Index])
        return out
    }

    static _Tr(arr) {
        out := []
        for s in arr
            out.Push(I18n.T(s))
        return out
    }

    ; Installed font families (EnumFontFamiliesExW), sorted, each once,
    ; without the "@" vertical fonts. ["Segoe UI"] when nothing is found.
    static FontFamilies() {
        seen := Map()
        seen.CaseSense := false
        cb := 0, dc := 0
        try {
            lf := Buffer(92, 0)
            NumPut("UChar", 1, lf, 23)                     ; DEFAULT_CHARSET, no face name: every family
            cb := CallbackCreate((lpelf, lpntm, ft, lp) => Dashboard._FontSeen(seen, lpelf), , 4)
            dc := DllCall("GetDC", "Ptr", 0, "Ptr")
            DllCall("gdi32\EnumFontFamiliesExW", "Ptr", dc, "Ptr", lf, "Ptr", cb, "Ptr", 0, "UInt", 0)
        }
        if dc
            DllCall("ReleaseDC", "Ptr", 0, "Ptr", dc)
        if cb
            CallbackFree(cb)
        s := ""
        for n in seen
            s .= n "`n"
        s := Sort(RTrim(s, "`n"), "D`n U")
        return (s = "") ? ["Segoe UI"] : StrSplit(s, "`n")
    }

    static _FontSeen(seen, lpelf) {
        try {
            n := StrGet(lpelf + 28, 32, "UTF-16")
            if (n != "" && SubStr(n, 1, 1) != "@" && StrLen(n) <= 31 && !RegExMatch(n, "[,\r\n=]"))
                seen[n] := 1
        }
        return 1
    }

    ; ---- Look: reading it (tests) ----

    LookName() => this._lkName
    LookTheme() => this._lk
    LookFonts() => this._lkFonts
    LayoutEditing() => this._editLayout
    PreviewColor(part) => this._lkPvSeen.Has(part "|bg") ? this._lkPvSeen[part "|bg"] : ""
    PreviewFont(part) => this._lkPvSeen.Has(part "|font") ? this._lkPvSeen[part "|font"] : ""

    ; ---- Look: picking a theme ----

    _LookLoad() {
        this._langDdl.Choose(I18n.IndexOf(this.cfg.Get("UI.lang", "en")))
        this._langLoaded := this._langDdl.Value
        name := this._lkName
        if (name = "" || !ThemeStore.Exists(this.cfg, name))
            name := Trim(String(this.cfg.Get("UI.theme", "Moontide")))
        if !ThemeStore.Exists(this.cfg, name)
            name := "Moontide"
        this._lkName := name
        this._LookFillList()
        this.LookSelect(name, true)
    }

    ; the page Save: the edited theme first; the language only once that worked
    _LookSave() {
        if this._lkDirty {
            r := this.LookSave()
            if (r != true)
                throw Error(r)
        }
        li := this._langDdl.Value
        this.cfg.Set("UI.lang", (li >= 1 && li <= I18n.Codes.Length) ? I18n.Codes[li] : "en")
        this._langLoaded := li
        return ""
    }

    ; Opens theme `name` in the editor. Unsaved edits of the open theme are
    ; dropped only after a yes (force: no question). -> true when opened.
    LookSelect(name, force := false) {
        name := Trim(String(name))
        if !ThemeStore.Exists(this.cfg, name) {
            this._LookNote(I18n.T("That theme is not there any more."), true)
            this._LookSelectRow()
            return false
        }
        pn := ThemeStore.PresetName(name)
        if (pn != "")
            name := pn
        if (name != this._lkName && this._EdBusy()) {
            this._LookSelectRow()
            return false
        }
        if (!force && this._lkDirty && name != this._lkName) {
            if (this._lookAsk.Call("Drop your changes?", I18n.F("{1} has changes that are not saved. Drop them and open {2}?", this._lkName, name)
                , "Drop them", "Keep editing") != true) {
                this._LookSelectRow()
                return false
            }
        }
        this._lk := ThemeStore.Load(this.cfg, name)
        this._lkName := name
        this._lkPicSrc := "", this._lkPicExt := ""
        this._lkHand := Map()                ; derived colours set by hand on this page
        this._LookClean()
        this._LookFill()
        this._LookSelectRow()
        this._LookNote(this._lk["preset"] ? I18n.F("{1} is built in: Duplicate it (or just change something) to make your own copy.", name)
            : I18n.F("{1}: change anything, then Save. Apply shows it now.", name))
        return true
    }

    _LookListPick(lv, item, selected) {
        if (this._lkFill || !selected || item < 1 || item > this._lkNames.Length)
            return
        n := this._lkNames[item]
        if (n != this._lkName)
            this.LookSelect(n)
    }

    _LookRowColor(r) => (r >= 1 && r <= this._lkNames.Length && this._lkNames[r] = this._InUse()) ? Theme.Accent : ""

    _InUse() => Trim(String(this.cfg.Get("UI.theme", "Moontide")))

    ; the theme list again (presets first, the one in use marked)
    _LookFillList() {
        lv := this._ids["look:list"]
        this._lkFill := true
        try {
            lv.Opt("-Redraw")
            lv.Delete()
            this._lkNames := ThemeStore.List(this.cfg)
            use := this._InUse()
            for n in this._lkNames
                lv.Add(, n (n = use ? "   " I18n.T("(in use)") : ""))
            lv.Opt("+Redraw")
            Theme.FitLastCol(lv)
        } finally
            this._lkFill := false
        this._LookSelectRow()
    }

    _LookSelectRow() {
        lv := this._ids["look:list"]
        this._lkFill := true
        try {
            lv.Modify(0, "-Select -Focus")
            for i, n in this._lkNames {
                if (n = this._lkName) {
                    lv.Modify(i, "Select Focus Vis")
                    break
                }
            }
        } finally
            this._lkFill := false
    }

    ; ---- Look: editing ----

    ; Sets one part of the open theme. key: a colour key (Bg, Accent, Muted...,
    ; "color:" in front allowed), "auto:<derived key>" (1 = mixed, 0 = your
    ; own), "font:<role>" (an installed family), "size:<role>" (7-28),
    ; "scale" (100 / 115 / 130), "sidebar" (left / right / top), "pic"
    ; ("none", a preset name or a picture file), "fit", "dim" (0-90),
    ; "resetAll" (the layout). A built-in theme asks to make a copy first.
    ; -> true when the value was taken.
    LookSet(key, value) {
        r := this._LookSet(key, value)
        if (r != "bad")
            this._LookFill()
        return r = "ok"
    }

    ; A change made in a control: like LookSet, but the control being typed
    ; in is left as it is unless the change was refused.
    _LookUser(key, value, ctrl := "") {
        if this._lkFill
            return false
        before := this._lkName
        r := this._LookSet(key, value)
        if (r = "refused" || r = "bad" && ctrl = "") {
            this._LookFill()
            return false
        }
        if (r = "bad") {
            ; a half-typed value: keep it in the field (a copy just made refilled it)
            if (this._lkName != before && IsObject(ctrl) && ctrl.Type = "Edit") {
                this._lkFill := true
                try {
                    ctrl.Value := value
                    SendMessage(0xB1, StrLen(value), StrLen(value), ctrl)      ; EM_SETSEL: caret at the end
                } finally
                    this._lkFill := false
            }
            return false
        }
        this._LookFill(ctrl)
        return true
    }

    ; -> "ok" | "bad" (a value that is no good; the note says why) | "refused" (built in, no copy)
    _LookSet(key, value) {
        if !IsObject(this._lk)
            return "bad"
        key := RegExReplace(RegExReplace(Trim(String(key)), "i)^look:"), "i)^color:")
        kind := key, arg := ""
        if (p := InStr(key, ":"))
            kind := StrLower(SubStr(key, 1, p - 1)), arg := SubStr(key, p + 1)
        base := Dashboard._Find(Theme.BaseKeys, kind), der := Dashboard._Find(ThemeStore.DerivedKeys, kind)
        if (base || der)
            arg := kind, kind := "color"
        known := Map("color", 1, "auto", 1, "font", 1, "size", 1, "scale", 1, "sidebar", 1, "pic", 1, "fit", 1, "dim", 1, "resetall", 1)
        if !known.Has(StrLower(kind))
            return "bad"
        kind := StrLower(kind)
        if (kind = "auto" && !Dashboard._Find(ThemeStore.DerivedKeys, arg))
            return "bad"
        if ((kind = "font" || kind = "size") && !Dashboard._Find(ThemeStore.FontRoles, arg))
            return "bad"
        if (kind = "resetall" && !this._lk["layout"].Count) {
            this._LookNote(I18n.T("Every card is already where its page puts it."))
            return "ok"
        }
        if !this._LookEditable()
            return "refused"
        t := this._lk
        v := Trim(String(value))
        switch kind {
            case "color":
                k := Dashboard._Find(Theme.BaseKeys, arg) ? Theme.BaseKeys[Dashboard._Find(Theme.BaseKeys, arg)] : ThemeStore.DerivedKeys[Dashboard._Find(ThemeStore.DerivedKeys, arg)]
                h := Theme.HexOk(v)
                if (h = "")
                    return this._LookBad(I18n.F("{1}: type 6 hex digits like 0D1117. The last good colour is kept.", I18n.T(this._LookLabel(k))))
                t["colors"][k] := h
                if Dashboard._Find(Theme.BaseKeys, k) {
                    ; a new base colour: every shade not set by hand here is mixed again
                    for dk in ThemeStore.DerivedKeys
                        if !this._lkHand.Has(dk)
                            t["colors"][dk] := ""
                    c := Dashboard.ThemeColors(t)
                    if c.TextFixed
                        this._LookNote(I18n.T(c.Text = "FFFFFF" ? "The text colour is too close to the panels, so the theme uses white text instead."
                            : "The text colour is too close to the panels, so the theme uses black text instead."))
                } else
                    this._lkHand[k] := true              ; typed or picked: stays when a base colour changes
            case "auto":
                k := ThemeStore.DerivedKeys[Dashboard._Find(ThemeStore.DerivedKeys, arg)]
                if (value && v != "0") {
                    t["colors"][k] := ""
                    if this._lkHand.Has(k)
                        this._lkHand.Delete(k)
                } else {
                    if (t["colors"][k] = "")
                        t["colors"][k] := Dashboard.ThemeColors(t).%k%   ; your own, starting from the mixed shade
                    this._lkHand[k] := true
                }
            case "font":
                r := ThemeStore.FontRoles[Dashboard._Find(ThemeStore.FontRoles, arg)]
                if this._lkFontIdx.Has(v)
                    v := this._lkFonts[this._lkFontIdx[v]]
                else {
                    ok := false
                    try ok := (v != "" && ThemeStore.FontExistsFn.Call(v))
                    if !ok
                        return this._LookBad(I18n.T("That font is not installed on this PC."))
                }
                t["fonts"][r][1] := v
            case "size":
                r := ThemeStore.FontRoles[Dashboard._Find(ThemeStore.FontRoles, arg)]
                if (!IsInteger(v) || Integer(v) < 7 || Integer(v) > 28)
                    return this._LookBad(I18n.T("A font size is 7 to 28."))
                t["fonts"][r][2] := Integer(v)
            case "scale":
                v := RegExReplace(v, "\s*%$")
                if (!IsInteger(v) || !Dashboard._Find(ThemeStore.Scales, Integer(v)))
                    return this._LookBad(I18n.T("The UI size is 100, 115 or 130 %."))
                t["ui"]["scale"] := Integer(v)
            case "sidebar":
                if !Dashboard._Find(ThemeStore.Sidebars, StrLower(v))
                    return "bad"
                t["ui"]["sidebar"] := StrLower(v)
            case "fit":
                if !Dashboard._Find(ThemeStore.Fits, StrLower(v))
                    return "bad"
                t["picture"]["fit"] := StrLower(v)
            case "dim":
                if (!IsInteger(v) || Integer(v) < 0 || Integer(v) > 90)
                    return this._LookBad(I18n.T("Dim is 0 to 90 %."))
                t["picture"]["dim"] := Integer(v)
            case "pic":
                r := this._LookPicture(v)
                if (r != "ok")
                    return r
            case "resetall":
                t["layout"] := Map()
                this._LookNote(I18n.T("Every card goes back to its place after Save and Apply."))
        }
        this._LookChanged()
        return "ok"
    }

    ; the picture: "none", a preset name or a picture file of your own
    _LookPicture(v) {
        t := this._lk
        if (v = "none") {
            t["picture"]["file"] := "none"
            this._lkPicSrc := ""
            return "ok"
        }
        n := ThemeStore.PresetName(v)
        if (n != "") {
            t["picture"]["file"] := n
            this._lkPicSrc := ""
            return "ok"
        }
        a := ""
        try a := FileExist(v)
        if (v = "" || a = "" || InStr(a, "D"))
            return this._LookBad(I18n.T("That picture could not be read. Pick a PNG, JPG, BMP or GIF file."))
        size := 0
        try size := FileGetSize(v)
        if (size > ThemeStore.MaxPicture)
            return this._LookBad(I18n.F("That picture is too big (the limit is {1} MB).", ThemeStore.MaxPicture // (1024 * 1024)))
        b := "", ext := "", ok := false
        try {
            b := FileRead(v, "RAW")
            ext := ThemeStore._PicExt(b)
            ok := (ext != "") && ThemeStore.PictureOkFn.Call(b)
        }
        if !ok
            return this._LookBad(I18n.T("That picture could not be read. Pick a PNG, JPG, BMP or GIF file."))
        this._lkPicSrc := v, this._lkPicExt := ext
        t["picture"]["file"] := this._lkName "." ext
        this._LookNote(I18n.T("Your picture is copied into the themes folder when you Save."))
        return "ok"
    }

    _LookBad(why) {
        this._LookNote(why, true)
        return "bad"
    }

    _LookLabel(k) => Dashboard.LookBaseLabels.Has(k) ? Dashboard.LookBaseLabels[k] : Dashboard.LookDerivedLabels[k]

    static _Find(arr, v) {
        for i, x in arr
            if (x = v)
                return i
        return 0
    }

    _LookChanged() {
        this._lkDirty := true
        this._MarkDirty(this._lookPage)
    }

    ; the theme has no unsaved edits (the language may still have one)
    _LookClean() {
        this._lkDirty := false
        page := this._lookPage
        page.dirty := (this._langDdl.Value != this._langLoaded)
        this._RefreshDot(page)
    }

    ; true when the open theme may be changed; a built-in one asks to make
    ; a copy (a yes makes and opens it)
    _LookEditable() {
        if !this._lk["preset"]
            return true
        if this._EdBusy()                  ; a copy would change the theme being edited: say so, never ask
            return false
        nm := this._LookCopyName(this._lkName)
        if (nm = "" || this._lookAsk.Call("Make a copy?", I18n.F("{1} is a built-in theme and cannot be changed. Make a copy named {2} and change that?", this._lkName, nm)
            , "Make a copy", "Cancel") != true) {
            this._LookNote(I18n.F("{1} is built in: nothing was changed.", this._lkName))
            return false
        }
        return this.LookDuplicate() != ""
    }

    ; "<name> copy", "<name> copy 2" ... a free name (32 characters at most)
    _LookCopyName(base) {
        Loop 99 {
            suf := (A_Index = 1) ? " copy" : " copy " A_Index
            nm := RTrim(SubStr(base, 1, 32 - StrLen(suf))) suf
            if (ThemeStore.NameOk(nm) && !ThemeStore.Exists(this.cfg, nm))
                return nm
        }
        return ""
    }

    ; every Look control from the open theme (skip: the control being typed in)
    _LookFill(skip := "") {
        if !IsObject(this._lk)
            return
        t := this._lk
        c := Dashboard.ThemeColors(t)
        this._lkFill := true
        try {
            set := (ctl, v) => (ctl != skip && String(ctl.Value) != String(v)) ? (ctl.Value := v) : 0
            choose := (ctl, i) => (ctl != skip && ctl.Value != i) ? ctl.Choose(i) : 0
            for k in Theme.BaseKeys {
                set(this._ids["look:color:" k], t["colors"][k])
                Theme.SetColors(this._lkSw[k], t["colors"][k], t["colors"][k])
            }
            for k in ThemeStore.DerivedKeys {
                own := t["colors"][k] != ""
                e := this._ids["look:color:" k]
                set(e, c.%k%)
                ro := (DllCall("GetWindowLong", "Ptr", e.Hwnd, "Int", -16) & 0x800) != 0     ; ES_READONLY while on Auto
                if (ro = own) {
                    e.Opt(own ? "-ReadOnly" : "+ReadOnly")
                    e.SetFont("c" (own ? Theme.Text : Theme.Muted))
                }
                a := this._ids["look:auto:" k]
                if (a.Value != !own)
                    a.Value := !own
                Theme.SetColors(this._lkSw[k], c.%k%, c.%k%)
            }
            for r in ThemeStore.FontRoles {
                f := t["fonts"][r]
                choose(this._ids["look:font:" r], this._lkFontIdx.Has(f[1]) ? this._lkFontIdx[f[1]] : 0)
                set(this._ids["look:size:" r], f[2])
            }
            choose(this._ids["look:scale"], Dashboard._Find(ThemeStore.Scales, t["ui"]["scale"]))
            choose(this._ids["look:sidebar"], Dashboard._Find(ThemeStore.Sidebars, t["ui"]["sidebar"]))
            choose(this._ids["look:fit"], Dashboard._Find(ThemeStore.Fits, t["picture"]["fit"]))
            set(this._ids["look:dim"], t["picture"]["dim"])
            this._LookFillPic()
            for id in ["rename", "delete"]
                Theme.SetEnabled(this._ids["look:" id], !t["preset"])
        } finally
            this._lkFill := false
        this._LookPreview(c)
        Theme.SetText(this._ids["look:textNote"], this._LookTextNote())
    }

    ; the picture list: None, each theme's picture, your own (when the theme
    ; has one), Choose a file...
    _LookFillPic() {
        dd := this._ids["look:pic"]
        keys := ["none"], items := [I18n.T("None")]
        for n in Theme.Names
            keys.Push(n), items.Push(I18n.F("{1} picture", n))
        pf := this._lk["picture"]["file"]
        own := (pf != "none" && ThemeStore.PresetName(pf) = "")
        if own
            keys.Push("own"), items.Push(I18n.T("Your own picture"))
        keys.Push("file"), items.Push(I18n.T("Choose a file..."))
        if (Dashboard._Join(keys) != Dashboard._Join(this._lkPicKeys)) {
            dd.Delete()
            dd.Add(items)
            this._lkPicKeys := keys
        }
        i := own ? keys.Length - 1 : Dashboard._Find(keys, pf = "none" ? "none" : ThemeStore.PresetName(pf))
        if (dd.Value != i)
            dd.Choose(i)
    }

    static _Join(arr) {
        s := ""
        for x in arr
            s .= x "|"
        return s
    }

    ; the note under the fonts: a UI size this screen cannot show, the
    ; Advanced colours hint, or fonts so big they may be cut off
    _LookTextNote() {
        t := this._lk
        want := t["ui"]["scale"]
        wa := {w: 99999, h: 99999}
        try wa := Theme.WorkAreaFn.Call()
        fit := Theme.FitScale(want, wa.w, wa.h, Dashboard.W, Dashboard.H + Dashboard.PageShift(t["ui"]["sidebar"]).extraH)
        if (fit < want)
            return I18n.F("{1} % does not fit this screen: the window uses {2} %, the largest size that fits.", want, fit)
        if this._lkAdv
            return I18n.T("A ticked box is Auto: mixed from the 4 base colours. Untick it to type your own, or click the swatch to pick one.")
        d := ThemeStore.Default()["fonts"]
        for r in ThemeStore.FontRoles
            if (t["fonts"][r][2] > d[r][2] + 2)
                return I18n.T("Big fonts can be cut off in fixed boxes; a bigger UI size grows everything instead.")
        return ""
    }

    ; every colour of a theme Map: the 4 base ones through Theme.Derive, the
    ; derived ones it sets itself, plus TextFixed. -> an object like Derive's
    static ThemeColors(t) {
        c := t["colors"]
        o := Theme.Derive(c["Bg"], c["PanelC"], c["Text"], c["Accent"])
        for k in ThemeStore.DerivedKeys
            if (c.Has(k) && c[k] != "")
                o.%k% := c[k]
        return o
    }

    ; the preview drawn with colours c and the theme's fonts (at the window's UI size)
    _LookPreview(c) {
        f := this._lk["fonts"]
        pv := this._lkPv
        paint := (part, bg, fg := "", role := "") => this._LookPaint(pv[part], part, bg, fg, role != "" ? f[role] : "")
        paint("bg", c.Bg, c.Bg)
        paint("side", c.SideBg, c.SideBg)
        paint("nav", c.SideBg, c.Muted, "nav")
        paint("title", c.Bg, c.Text, "title")
        paint("small", c.Bg, c.Muted, "small")
        paint("frame", c.FrameC, c.FrameC)
        paint("card", c.CardBg, c.CardBg)
        paint("head", c.CardBg, c.Accent, "head")
        paint("body", c.CardBg, c.Text, "body")
        paint("button", c.Accent, c.Ink, "button")
    }

    _LookPaint(ctl, part, bg, fg, font) {
        try {
            ctl.Opt("+Background" bg)
            if IsObject(font) {
                ctl.SetFont("s" Max(6, Theme.S(font[2])) " norm c" fg, font[1])
                this._lkPvSeen[part "|font"] := font[1]
            } else
                ctl.SetFont("c" fg)
            ctl.Redraw()
            this._lkPvSeen[part "|bg"] := bg
        }
    }

    ; ---- Look: control events ----

    _LookHexEdit(k, ctrl, *) => this._LookUser(k, ctrl.Value, ctrl)
    _LookFontPick(r, ctrl, *) => this._LookUser("font:" r, ctrl.Text, ctrl)
    _LookSizeEdit(r, ctrl, *) => this._LookUser("size:" r, ctrl.Value, ctrl)

    _LookAutoTick(k, ctrl) {
        if !this._lkFill
            this._LookUser("auto:" k, ctrl.Value)
    }

    ; Pick (a base colour) or a click on a derived swatch: Windows' colour dialog
    _LookPick(k, *) {
        h := ""
        try h := this._pickColor.Call(this._ids["look:color:" k].Value)
        if (Theme.HexOk(h) != "")
            this._LookUser(k, h)
    }

    _LookPicPick(ctrl, *) {
        if (this._lkFill || ctrl.Value < 1 || ctrl.Value > this._lkPicKeys.Length)
            return
        key := this._lkPicKeys[ctrl.Value]
        if (key = "file")
            return this.LookChooseFile()
        if (key = "own")
            return
        this._LookUser("pic", key)
    }

    ; Choose a file...: a picture of your own (refused when it will not
    ; load; the note says why). -> true when taken
    LookChooseFile() {
        f := ""
        try f := Trim(String(this._pickFile.Call()))
        if (f = "") {
            this._LookFill()
            return false
        }
        return this._LookUser("pic", f)
    }

    _LookAdvToggle(ctrl) {
        this._lkAdv := ctrl.Value ? true : false
        for c in this._lkFontView
            this._SetHidden(c, this._lkAdv)
        for c in this._lkAdvView
            this._SetHidden(c, !this._lkAdv)
        Theme.SetText(this._lkTextCap, StrUpper(I18n.T(this._lkAdv ? "Advanced colours" : "Text")))
        if IsObject(this._lk)
            Theme.SetText(this._ids["look:textNote"], this._LookTextNote())
    }

    _LookNote(text, bad := false) {
        if this.HasOwnProp("_lookPage")
            this._SetPageStatus(this._lookPage, text, bad)
    }

    ; ---- Look: saving, the buttons ----

    ; Writes the open theme. -> true, or why not (built in, a bad name, a
    ; file that could not be written).
    LookSave() {
        if !IsObject(this._lk)
            return I18n.T("No theme is open.")
        name := this._lkName
        if this._lk["preset"]
            return I18n.T("Built-in themes cannot be changed: press Duplicate and change the copy.")
        old := ""
        try old := ThemeStore._OwnPicture(this.cfg, name, ThemeStore.Load(this.cfg, name))
        t := ThemeStore.Clean(this._lk)
        r := this._LookWrite(t, name)
        if (r != true) {
            this._LookNote(I18n.T("Not saved:") " " r, true)
            return r
        }
        if (old != "" && old != ThemeStore.Dir(this.cfg) "\" t["picture"]["file"])
            try FileDelete(old)
        this._lkPicSrc := "", this._lkPicExt := ""
        this._lk := ThemeStore.Load(this.cfg, name)
        this._LookClean()
        this._LookFill()
        this._LookNote(I18n.F("{1} saved.", name) (name = this._InUse() ? " " I18n.T("Apply shows it now.") : ""))
        return true
    }

    ; t (a copy of the open theme) written as `name`, with its picture: one
    ; just chosen is copied in, the open theme's own one is copied for a new
    ; name. The picture goes to a temporary name first and takes its place
    ; only after the theme file was written, so a failed save never loses
    ; the picture already there.
    _LookWrite(t, name) {
        t["name"] := name
        t["preset"] := false
        src := "", dest := ""
        dir := ThemeStore.Dir(this.cfg)
        if (this._lkPicSrc != "")
            src := this._lkPicSrc, dest := dir "\" name "." this._lkPicExt
        else if (name != this._lkName) {
            own := ThemeStore._OwnPicture(this.cfg, this._lkName, this._lk)
            if (own != "") {
                SplitPath(own, , , &ext)
                src := own, dest := dir "\" name "." ext
            }
        }
        tmp := ""
        if (src != "" && src != dest) {
            tmp := dest ".new"
            try {
                DirCreate(dir)
                FileCopy(src, tmp, 1)
            } catch {
                try FileDelete(tmp)
                return I18n.T("The picture could not be copied into the themes folder.")
            }
        }
        if (dest != "")
            SplitPath(dest, &fn), t["picture"]["file"] := fn
        r := ThemeStore.Save(this.cfg, t)
        if (r != true) {
            if (tmp != "")
                try FileDelete(tmp)
            return r
        }
        if (tmp != "") {
            try
                FileMove(tmp, dest, 1)
            catch {
                try FileDelete(tmp)
                return I18n.T("The picture could not be copied into the themes folder.")
            }
        }
        return true
    }

    ; A copy of the open theme with its edits ("<name> copy"), saved and
    ; opened; the theme it came from keeps its saved values. -> the new name | ""
    LookDuplicate() {
        if (!IsObject(this._lk) || this._EdBusy())
            return ""
        from := this._lkName
        nm := this._LookCopyName(from)
        if (nm = "") {
            this._LookNote(I18n.T("No free name for a copy: rename or delete some copies first."), true)
            return ""
        }
        r := this._LookWrite(ThemeStore.Clean(this._lk), nm)
        if (r != true) {
            this._LookNote(r, true)
            return ""
        }
        this._lkName := nm
        hand := this._lkHand
        this._LookFillList()
        this.LookSelect(nm, true)
        this._lkHand := hand                 ; the shades set by hand stay hand-set in the copy
        this._LookNote(I18n.F("Made {2} from {1}. Change anything, then Save.", from, nm))
        this.Log("Theme: made " nm)
        return nm
    }

    ; Renames the open theme (newName "" asks for it); the one in use keeps
    ; being in use, unsaved edits stay. -> true, or why not | false (cancelled)
    LookRename(newName := "") {
        if !IsObject(this._lk)
            return false
        if this._EdBusy()
            return I18n.T("Finish or cancel the layout edit first.")
        old := this._lkName
        if this._lk["preset"] {
            why := I18n.T("Built-in themes cannot be renamed: press Duplicate first.")
            this._LookNote(why, true)
            return why
        }
        if (newName = "") {
            try newName := this._askName.Call("Rename theme", I18n.T("A new name (1 to 32 letters, digits, spaces, - _ ( or )):"), old)
            newName := Trim(String(newName))
            if (newName = "" || newName == old)
                return false
        }
        r := ThemeStore.Rename(this.cfg, old, newName)
        if (r != true) {
            this._LookNote(r, true)
            return r
        }
        newName := Trim(newName)
        pf := this._lk["picture"]["file"]
        if (this._lkPicSrc != "")
            this._lk["picture"]["file"] := newName "." this._lkPicExt
        else if RegExMatch(pf, "^\Q" old "\E\.([A-Za-z0-9]{1,5})$", &m)
            this._lk["picture"]["file"] := newName "." m[1]
        this._lk["name"] := newName
        this._lkName := newName
        if (this._InUse() = old) {
            this.cfg.Set("UI.theme", newName)
            try this.cfg.Save()
        }
        this._LookFillList()
        this._LookNote(I18n.F("Renamed {1} to {2}.", old, newName))
        this.Log("Theme: renamed " old " to " newName)
        return true
    }

    ; Deletes the open theme (and its picture) after a yes; the theme in use
    ; switches to Moontide first. -> true when deleted
    LookDelete() {
        if (!IsObject(this._lk) || this._EdBusy())
            return false
        name := this._lkName
        if this._lk["preset"] {
            this._LookNote(I18n.T("Built-in themes cannot be deleted."), true)
            return false
        }
        if (this._lookAsk.Call("Delete this theme?", I18n.F("{1} and its picture are removed for good. This cannot be undone.", name), "Delete", "Keep it") != true)
            return false
        inUse := (this._InUse() = name)
        if inUse {
            try {
                this.cfg.Set("UI.theme", "Moontide")
                this.cfg.Save()
            } catch Any as e {
                this._LookNote(I18n.T("Not deleted:") " " UiLogic.Scrub(e.Message, this._Secrets()), true)
                return false
            }
        }
        if !ThemeStore.Delete(this.cfg, name) {
            if inUse {                       ; still there: it stays the theme in use
                this.cfg.Set("UI.theme", name)
                try this.cfg.Save()
            }
            this._LookNote(I18n.T("That theme could not be deleted."), true)
            return false
        }
        this._lkPicSrc := ""
        this._lkName := "Moontide"
        this._LookFillList()
        this.LookSelect("Moontide", true)
        this._LookNote(inUse ? I18n.F("Deleted {1}. Moontide is the theme in use now (Apply shows it).", name) : I18n.F("Deleted {1}.", name))
        this.Log("Theme: deleted " name)
        return true
    }

    ; Export: the open theme as one .moontheme file in the exports folder
    ; (unsaved edits are saved first). The folder opens when the window is
    ; shown. -> the path | ""
    LookExport() {
        if !IsObject(this._lk)
            return ""
        if this._lkDirty {
            if (this.LookSave() != true)
                return ""
        }
        note := ""
        path := ThemeStore.Export(this.cfg, this._lkName, &note)
        if (path = "") {
            this._LookNote(I18n.T("The theme could not be exported."), true)
            return ""
        }
        this._LookNote(I18n.F("Saved as {1} in the exports folder. Send that file to a friend.", this._lkName ThemeStore.Ext)
            (note != "" ? " " note : ""), note != "")
        this.Log("Theme: exported " this._lkName)
        if this._shown
            try this._openFolder.Call(path)
        return path
    }

    _LookImportPick() {
        f := ""
        try f := Trim(String(this._pickTheme.Call()))
        if (f != "")
            this.LookImport(f)
    }

    ; Import: reads a .moontheme file, shows its preview, and adds it after
    ; Add. -> {name} | {error}
    LookImport(path) {
        if this._EdBusy()
            return {error: I18n.T("Finish or cancel the layout edit first.")}
        r := ThemeStore.ReadFile(path)
        if r.Has("error") {
            this._LookNote(r["error"], true)
            return {error: r["error"]}
        }
        ok := false
        try ok := this._importOk.Call(r)
        if (ok != true) {
            why := I18n.T("Not added.")
            this._LookNote(why)
            return {error: why}
        }
        name := ThemeStore.Import(this.cfg, r)
        if (name = "") {
            why := I18n.T("That theme could not be added.")
            this._LookNote(why, true)
            return {error: why}
        }
        this._LookFillList()
        if !this._lkDirty
            this.LookSelect(name, true)
        msg := I18n.F("Added {1}.", name)
        for n in r["notes"]
            msg .= " " n
        this._LookNote(msg)
        this.Log("Theme: added " name)
        return {name: name}
    }

    ; Files dropped on the window: one .moontheme file is imported (Look
    ; shows), anything else gets a note. -> LookImport's result | {error}
    DropFiles(paths) {
        if !(paths is Array)
            paths := [paths]
        i := Dashboard.PageIndex("Look")
        if (this.PageShown("Look") && this._active != i)
            this.SelectPage(i)
        if (paths.Length = 1 && RegExMatch(String(paths[1]), "i)\.moontheme$"))
            return this.LookImport(paths[1])
        why := I18n.T("Drop one .moontheme file on this window to add a theme.")
        this._LookNote(why, true)
        return {error: why}
    }

    ; Look > Reset all: the open theme's layout is emptied (every card where
    ; its page puts it); while editing the layout it resets the cards being
    ; edited instead (ResetLayout). -> true when taken
    LookResetLayout() => this._editLayout ? this.ResetLayout() : this.LookSet("resetAll", 1)

    ; ---- Edit layout mode (spec 2 of the 2026-11-18 themes + layout design) ----
    ; While on, the cards of every page take the open theme's layout and the
    ; page shown gets an overlay: a child window whose region is only its
    ; own controls, so a click anywhere else reaches the page. Per card: a
    ; gold handle (drag to move), a corner grip (drag to resize), an eye
    ; (hide / show) and a reset; a red outline on cards that overlap (the
    ; note above the page names two of them), a dashed outline on hidden
    ; ones. Reset page, Cancel and Done sit in the page header. Done saves
    ; the layout into the open theme (a built-in one asks to make a copy
    ; first), Cancel puts back the layout shown before. Nothing of it is a
    ; page control or a card, and out of edit mode none of it exists.
    ; Ids: layout:handle:<card id>, layout:grip:<card id>, layout:eye:<card id>,
    ; layout:reset:<card id>, layout:outline:<card id>, layout:done,
    ; layout:cancel, layout:resetPage, layout:note.

    static OverlapC := "E5484D"         ; the outline of overlapping cards and the note
    static _edActive := ""              ; the Dashboard editing its layout (WM_LBUTTONDOWN)
    static _edHooked := false

    ; Look > Edit layout on / off. Off with unsaved changes asks whether to
    ; save them (Done) or drop them (Cancel). -> the state
    EditLayout(on) {
        if on {
            if !this._editLayout
                this._EdStart()
        } else if this._editLayout {
            if (this._EdChanged() && this._lookAsk.Call("Save the layout?", I18n.T("Keep the cards where you put them? Save puts them into the theme."), "Save", "Drop it") = true)
                this.LayoutDone()
            else
                this.LayoutCancel()
        }
        try this._ids["look:editLayout"].Value := this._editLayout ? 1 : 0
        return this._editLayout
    }

    ; The layout being edited (edit mode) or the one in use: Map card id -> [x, y, w, h, hidden].
    LayoutEntries() => this._editLayout ? this._lay : Theme.Layout

    ; "red" (overlaps another card), "dashed" (hidden) or "" for a card of the page shown while editing.
    LayoutOutline(id) => (IsObject(id) || !this._edState.Has(id)) ? "" : this._edState[id]

    Dragging() => IsObject(this._drag)

    ; Moves card `id` by (dx, dy) (each snapped to the grid), clamped to the
    ; page area; its entry is the place shown. -> true | false (not editing,
    ; an unknown card, deltas that are not numbers)
    DragCard(id, dx, dy) {
        if (!this._editLayout || !IsNumber(dx) || !IsNumber(dy))
            return false
        card := this._EdCard(id)
        if !IsObject(card)
            return false
        try {
            if !this._EdPlace(card, card.x + Layout.Snap(dx), card.y + Layout.Snap(dy), card.w, card.h)
                return false
            this._EdMarks()
            return true
        }
        return false
    }

    ; Resizes card `id` by (dw, dh) (each snapped), never below Layout.MinSize
    ; and never past the page area's right / bottom edge; the card does not
    ; move. -> true | false
    ResizeCard(id, dw, dh) {
        if (!this._editLayout || !IsNumber(dw) || !IsNumber(dh))
            return false
        card := this._EdCard(id)
        if !IsObject(card)
            return false
        try {
            a := this.PageArea()
            w := Min(card.w + Layout.Snap(dw), a.x + a.w - card.x)
            h := Min(card.h + Layout.Snap(dh), a.y + a.h - card.y)
            if !this._EdPlace(card, card.x, card.y, w, h)
                return false
            this._EdMarks()
            return true
        }
        return false
    }

    ; The eye: hides a shown card, shows a hidden one. -> true | false
    ToggleCard(id) {
        if !this._editLayout
            return false
        card := this._EdCard(id)
        if !IsObject(card)
            return false
        try {
            e := this._lay.Has(card.id) ? this._lay[card.id].Clone() : this._LayOut(card, 0)
            while (e.Length < 5)
                e.Push(0)
            e[5] := e[5] ? 0 : 1
            this._lay[card.id] := e
            this._LayoutHide(card, e[5])
            this._EdSync(card)
            this._EdMarks()
            return true
        }
        return false
    }

    ; Card `id` back where its page puts it, shown (its entry removed). -> true | false
    ResetCard(id) {
        if !this._editLayout
            return false
        card := this._EdCard(id)
        if !IsObject(card)
            return false
        try {
            if this._lay.Has(card.id)
                this._lay.Delete(card.id)
            if (card.x != card.ox || card.y != card.oy || card.w != card.ow || card.h != card.oh)
                this._PlaceCard(card, card.ox, card.oy, card.ow, card.oh)
            this._LayoutHide(card, false)
            this._EdSync(card)
            this._EdMarks()
            return true
        }
        return false
    }

    ; Every card of `page` back in place (its entries removed). -> true | false
    ResetPage(page) {
        if (!this._editLayout || IsObject(page) || !Dashboard.PageIndex(page))
            return false
        dead := []
        for id in this._lay
            if (SubStr(id, 1, StrLen(page) + 1) = page ":")
                dead.Push(id)
        for id in dead
            this._lay.Delete(id)
        this.ApplyLayout(page, this._lay)
        this._EdRefresh()
        return true
    }

    ; Every card of every page back in place (the edited layout emptied). -> true | false
    ResetLayout() {
        if !this._editLayout
            return false
        this._lay := Map()
        this._ApplyAll(this._lay)
        this._EdRefresh()
        return true
    }

    ; Done: the edited layout is saved into the open theme. A built-in one
    ; asks to make a copy first (a no keeps editing); a copy of the theme in
    ; use becomes the theme in use. The layout in use (Theme.Layout) follows
    ; when that theme is in use; the cards then show the layout in use.
    ; -> true | why not (edit mode stays on)
    LayoutDone() {
        if !this._editLayout
            return false
        this._DragStop()
        if this._EdChanged() {
            if !IsObject(this._lk)
                return this._EdFail(I18n.T("No theme is open."))
            from := this._lkName
            wasInUse := (from = this._InUse())
            others := this._lkDirty            ; other unsaved Look edits of this theme are saved too
            ok := false
            this._edSaving := true             ; the copy below may open a new theme
            try {
                ok := !this._lk["preset"] || this._LookEditable()
            } finally
                this._edSaving := false
            if !ok
                return this._EdFail(I18n.F("{1} is built in: nothing was changed.", from))
            this._lk["layout"] := Dashboard._LayClone(this._lay)
            this._LookChanged()
            r := this.LookSave()
            if (r != true)
                return this._EdFail(I18n.T("Not saved:") " " r)
            name := this._lkName
            if (wasInUse && name != this._InUse()) {
                try {
                    this.cfg.Set("UI.theme", name)
                    this.cfg.Save()
                }
                this._LookFillList()
            }
            if (name = this._InUse())
                Theme.Layout := Dashboard._LayClone(this._lk["layout"])
            this._EdEnd()
            this._ApplyAll(Theme.Layout)
            if others
                this._LookNote(name = this._InUse() ? I18n.F("Layout and your other Look changes saved into {1}.", name)
                    : I18n.F("Layout and your other Look changes saved into {1}. Apply shows it.", name))
            else
                this._LookNote(name = this._InUse() ? I18n.F("Layout saved into {1}.", name) : I18n.F("Layout saved into {1}. Apply shows it.", name))
            this.Log("Theme: layout saved into " name)
            return true
        }
        this._EdEnd()
        this._ApplyAll(Theme.Layout)
        return true
    }

    ; Cancel: every card back to the layout shown before editing; nothing is written. -> true | false
    LayoutCancel() {
        if !this._editLayout
            return false
        this._DragStop()
        this._ApplyAll(this._layStart)
        this._EdEnd()
        this._LookNote(I18n.T("The cards are back where they were."))
        return true
    }

    ; ---- Edit layout: inside ----

    _EdStart() {
        this._editLayout := true
        this._layStart := Theme.Layout
        src := Theme.Layout
        try {
            if (IsObject(this._lk) && this._lk.Has("layout"))
                src := this._lk["layout"]
        }
        this._lay := Dashboard._LayClone(src)
        this._layFrom := Dashboard._LayKey(this._lay)
        this._drag := ""
        this._dragFn := ObjBindMethod(this, "_DragTick")
        this._ApplyAll(this._lay)
        this._EdBuild()
    }

    ; Edit mode off: the drag loop stopped, the overlay and its ids gone.
    ; Card places are left as they are (the caller applies a layout).
    _EdEnd() {
        this._DragStop()
        this._EdClose()
        this._editLayout := false
        this._lay := Map()
        this._edState := Map()
        this._dragFn := ""
        if (Dashboard._edActive = this)
            Dashboard._edActive := ""
        try this._ids["look:editLayout"].Value := 0
    }

    _EdChanged() => Dashboard._LayKey(this._lay) != this._layFrom

    ; While the layout is edited the open theme must stay the one it came
    ; from (Done saves into it): a theme change is refused with a note.
    ; -> true when refused
    _EdBusy() {
        if (!this._editLayout || this._edSaving)
            return false
        this._LookNote(I18n.T("Finish or cancel the layout edit first."), true)
        return true
    }

    ; Done could not save: why, on the Look page and above the page shown. -> why
    _EdFail(why) {
        this._LookNote(why, true)
        try {
            note := this._ids["layout:note"]
            Theme.SetText(note, why)
            note.Visible := true
            this._EdRegion()
        }
        return why
    }

    _ApplyAll(lay) {
        for name in Dashboard.Pages
            this.ApplyLayout(name, lay)
    }

    ; A copy of a layout Map (each entry copied); a Map for anything else.
    static _LayClone(m) {
        out := Map()
        if !(m is Map)
            return out
        for id, e in m
            out[id] := (e is Array) ? e.Clone() : e
        return out
    }

    ; One line per entry (a Map lists its keys in order): equal layouts, equal keys.
    static _LayKey(m) {
        s := ""
        if !(m is Map)
            return s
        for id, e in m {
            s .= id "="
            if (e is Array)
                for v in e
                    s .= v ","
            s .= "`n"
        }
        return s
    }

    ; The card with id "<page>:<title>" | "" (unknown, not text).
    _EdCard(id) {
        if (IsObject(id) || !InStr(id, ":"))
            return ""
        for card in this.Cards(RegExReplace(id, ":.*$"))
            if (card.id = id)
                return card
        return ""
    }

    _EdHidden(card) {
        try return (this._lay.Has(card.id) && this._lay[card.id].Length >= 5 && this._lay[card.id][5]) ? 1 : 0
        return 0
    }

    ; Card to (x, y, w, h) (window places) through Layout.Place (clamped,
    ; MinSize); the entry written is the place shown, not the one asked for,
    ; in page places (_LayOut).
    _EdPlace(card, x, y, w, h) {
        hid := this._EdHidden(card)
        e := Layout.Place(card, [x, y, w, h, hid], this.PageArea())
        if !IsObject(e)
            return false
        this._PlaceCard(card, card.x + e.dx, card.y + e.dy, e.w, e.h)
        this._lay[card.id] := this._LayOut(card, hid)
        this._EdSync(card)
        return true
    }

    _EdTitle(id) {
        card := this._EdCard(id)
        return (IsObject(card) && card.title != "") ? I18n.T(card.title) : I18n.T("Button row")
    }

    ; The overlay for the page shown (a new one each time the page changes).
    _EdBuild() {
        this._EdClose()
        if (!this._editLayout || !this._active)
            return
        sink := Theme.Sink
        Theme.Sink := ""                     ; never a page control
        try {
            ; layered (opaque) like the fade cover: drawn on top of the page,
            ; which repaints under it without painting over it
            ov := Gui("-Caption +E0x80000 +Parent" this._gui.Hwnd)
            DllCall("SetLayeredWindowAttributes", "Ptr", ov.Hwnd, "UInt", 0, "UChar", 255, "UInt", 2)   ; LWA_ALPHA
            ov.BackColor := Theme.Bg
            ov.MarginX := 0, ov.MarginY := 0
            if Theme.IsScaled(this._gui)
                Theme._scaled[ov.Hwnd] := true
            this._edGui := ov
            Dashboard._edActive := this
            Dashboard._HookEdit()
            a := this.PageArea()
            r := a.x + a.w, hy := a.y - 82
            ; top sidebar: the header row is the search box's row (x 700..1000),
            ; so the buttons end left of the box
            if (this._side = "top")
                try r := Min(r, Theme.Pos(this._ids["search:box"]).x - 8)
            page := this.ActivePage
            this._ids["layout:resetPage"] := Theme.Button(ov, "x" r - 352 " y" hy " w136 h28", "Reset page", (*) => this.ResetPage(page))
            this._ids["layout:cancel"] := Theme.Button(ov, "x" r - 208 " y" hy " w100 h28", "Cancel", (*) => this.LayoutCancel())
            this._ids["layout:done"] := Theme.Button(ov, "x" r - 100 " y" hy " w100 h28", "Done", (*) => this.LayoutDone(), "primary")
            this._ids["layout:note"] := Theme.Label(ov, "x" a.x " y" a.y - 20 " w" a.w " h18", "", "muted", Theme.Bg, Dashboard.OverlapC)
            for card in this.Cards(page)
                this._EdCardCtls(ov, card)
            this._EdMarks()                  ; outlines, the note and the region before it shows
            sz := this.ShownSize()
            ov.Show("x0 y0 w" sz.w " h" sz.h " NoActivate")
            ; HWND_TOP among the window's controls; SWP_NOMOVE|NOSIZE|NOACTIVATE|SHOWWINDOW
            DllCall("SetWindowPos", "Ptr", ov.Hwnd, "Ptr", 0, "Int", 0, "Int", 0, "Int", 0, "Int", 0, "UInt", 0x53)
        } catch Any as err {
            try OutputDebug("Dashboard edit layout overlay failed: " err.Message)
        } finally
            Theme.Sink := sink
    }

    _EdCardCtls(ov, card) {
        id := card.id
        k := {}
        k.outline := Theme.Add(ov, "Text", "x" card.x " y" card.y " w" card.w " h" card.h " Background" Dashboard.OverlapC)
        k.outline.Visible := false
        Theme.Font(ov, "glyph", Theme.Ink)
        k.handle := Theme.Add(ov, "Text", "x0 y0 w22 h18 +0x100 +0x200 Center Background" Theme.Accent, Chr(0x2725))
        k.grip := Theme.Add(ov, "Text", "x0 y0 w12 h12 +0x100 +0x200 Center Background" Theme.Accent, Chr(0x25E2))
        Theme.Font(ov, "glyph", Theme.Text)
        k.eye := Theme.Add(ov, "Text", "x0 y0 w18 h18 +0x100 +0x200 Center Background" Theme.PanelC, Chr(0x25C9))
        k.reset := Theme.Add(ov, "Text", "x0 y0 w18 h18 +0x100 +0x200 Center Background" Theme.PanelC, Chr(0x21BA))
        Theme.Clickable(k.eye, (*) => this.ToggleCard(id))
        Theme.Clickable(k.reset, (*) => this.ResetCard(id))
        this._edHot[k.handle.Hwnd] := ["move", id]
        this._edHot[k.grip.Hwnd] := ["size", id]
        for part in ["handle", "grip", "eye", "reset", "outline"]
            this._ids["layout:" part ":" id] := k.%part%
        this._edCtl[id] := k
        this._edState[id] := ""
        this._EdSync(card)
    }

    ; The overlay controls of a card follow its place: handle, eye and reset
    ; at the title's right (left of the "?"; an untitled card: top left),
    ; the grip in the bottom right corner, the outline on the frame.
    _EdSync(card) {
        if !this._edCtl.Has(card.id)
            return
        k := this._edCtl[card.id]
        x := card.x, y := card.y, w := card.w, h := card.h
        if (card.title != "")
            hx := Max(x + 2, x + w - 98), hy := y + 6
        else
            hx := x + 2, hy := y + 2
        Theme.MoveTo(k.handle, hx, hy)
        Theme.MoveTo(k.eye, hx + 24, hy)
        Theme.MoveTo(k.reset, hx + 44, hy)
        Theme.MoveTo(k.grip, x + w - 14, y + h - 14)
        Theme.MoveTo(k.outline, x, y, w, h)
        hid := this._layoutHidden.Has(card.frame.Hwnd)
        k.handle.Visible := !hid
        k.grip.Visible := !hid
        Theme.SetText(k.eye, Chr(hid ? 0x25CB : 0x25C9))
        this._edState[card.id] := "?"          ; the outline is drawn again (its size may be new)
    }

    _EdRefresh() {
        for card in this.Cards(this.ActivePage)
            this._EdSync(card)
        this._EdMarks()
    }

    ; Overlaps among the shown cards of the page shown: red outlines and the
    ; note; hidden cards dashed. Then the overlay's region again.
    _EdMarks() {
        if !IsObject(this._edGui)
            return
        try {
            page := this.ActivePage
            rects := Map()
            for card in this.Cards(page)
                if !this._layoutHidden.Has(card.frame.Hwnd)
                    rects[card.id] := {x: card.x, y: card.y, w: card.w, h: card.h}
            pairs := Layout.Overlaps(rects)
            red := Map()
            for p in pairs
                red[p[1]] := 1, red[p[2]] := 1
            for card in this.Cards(page)
                this._EdOutline(card, this._layoutHidden.Has(card.frame.Hwnd) ? "dashed" : red.Has(card.id) ? "red" : "")
            txt := pairs.Length ? I18n.F("{1} and {2} overlap.", this._EdTitle(pairs[1][1]), this._EdTitle(pairs[1][2])) : ""
            note := this._ids["layout:note"]
            Theme.SetText(note, txt)
            note.Visible := (txt != "")
            this._EdRegion()
        } catch Any as err {
            try OutputDebug("Dashboard edit layout marks failed: " err.Message)
        }
    }

    _EdOutline(card, st) {
        if !this._edCtl.Has(card.id)
            return
        if (this._edState[card.id] == st)
            return
        this._edState[card.id] := st
        o := this._edCtl[card.id].outline
        if (st = "") {
            o.Visible := false
            return
        }
        o.Opt("+Background" (st = "red" ? Dashboard.OverlapC : Theme.Muted))
        rc := Buffer(16, 0)
        DllCall("GetClientRect", "Ptr", o.Hwnd, "Ptr", rc)
        w := NumGet(rc, 8, "Int"), h := NumGet(rc, 12, "Int")
        t := Max(2, Theme.Dpi(Theme.S(2)))
        rgn := (st = "red") ? Dashboard._RingRgn(w, h, t) : Dashboard._DashRgn(w, h, t, Theme.Dpi(Theme.S(8)), Theme.Dpi(Theme.S(6)))
        if !DllCall("SetWindowRgn", "Ptr", o.Hwnd, "Ptr", rgn, "Int", 1)
            DllCall("DeleteObject", "Ptr", rgn)
        o.Visible := true
        o.Redraw()
    }

    ; A frame t px thick around a w x h box (a region the caller owns).
    static _RingRgn(w, h, t) {
        r := DllCall("CreateRectRgn", "Int", 0, "Int", 0, "Int", w, "Int", h, "Ptr")
        i := DllCall("CreateRectRgn", "Int", t, "Int", t, "Int", Max(t, w - t), "Int", Max(t, h - t), "Ptr")
        DllCall("CombineRgn", "Ptr", r, "Ptr", r, "Ptr", i, "Int", 4)        ; RGN_DIFF
        DllCall("DeleteObject", "Ptr", i)
        return r
    }

    ; The same frame cut into dashes `dash` px long with `gap` px between.
    static _DashRgn(w, h, t, dash, gap) {
        r := DllCall("CreateRectRgn", "Int", 0, "Int", 0, "Int", 0, "Int", 0, "Ptr")
        add := (x1, y1, x2, y2) => Dashboard._RgnAdd(r, x1, y1, x2, y2)
        step := Max(2, dash + gap)
        x := 0
        while (x < w) {
            add(x, 0, Min(x + dash, w), t)
            add(x, h - t, Min(x + dash, w), h)
            x += step
        }
        y := 0
        while (y < h) {
            add(0, y, t, Min(y + dash, h))
            add(w - t, y, w, Min(y + dash, h))
            y += step
        }
        return r
    }

    static _RgnAdd(r, x1, y1, x2, y2) {
        p := DllCall("CreateRectRgn", "Int", x1, "Int", y1, "Int", x2, "Int", y2, "Ptr")
        DllCall("CombineRgn", "Ptr", r, "Ptr", r, "Ptr", p, "Int", 2)        ; RGN_OR
        DllCall("DeleteObject", "Ptr", p)
    }

    ; The overlay window is only where its shown controls are (each control's
    ; own region counted), so the page under it keeps every other click.
    _EdRegion() {
        ov := this._edGui
        if !IsObject(ov)
            return
        all := DllCall("CreateRectRgn", "Int", 0, "Int", 0, "Int", 0, "Int", 0, "Ptr")
        rc := Buffer(16, 0)
        for hwnd, c in ov {
            if !c.Visible
                continue
            DllCall("GetWindowRect", "Ptr", hwnd, "Ptr", rc)
            DllCall("MapWindowPoints", "Ptr", 0, "Ptr", ov.Hwnd, "Ptr", rc, "UInt", 2)
            x := NumGet(rc, 0, "Int"), y := NumGet(rc, 4, "Int")
            cr := DllCall("CreateRectRgn", "Int", 0, "Int", 0, "Int", 0, "Int", 0, "Ptr")
            kind := DllCall("GetWindowRgn", "Ptr", hwnd, "Ptr", cr, "Int")
            if (kind >= 2)                   ; SIMPLEREGION / COMPLEXREGION: the control's own shape
                DllCall("OffsetRgn", "Ptr", cr, "Int", x, "Int", y)
            else if (kind = 0)               ; no region: the whole control
                DllCall("SetRectRgn", "Ptr", cr, "Int", x, "Int", y, "Int", NumGet(rc, 8, "Int"), "Int", NumGet(rc, 12, "Int"))
            DllCall("CombineRgn", "Ptr", all, "Ptr", all, "Ptr", cr, "Int", 2)
            DllCall("DeleteObject", "Ptr", cr)
        }
        if !DllCall("SetWindowRgn", "Ptr", ov.Hwnd, "Ptr", all, "Int", 1)
            DllCall("DeleteObject", "Ptr", all)
    }

    _EdClose() {
        ov := this._edGui
        this._edGui := ""
        if IsObject(ov) {
            try Theme.Forget(ov)
            try {
                for hwnd, c in ov
                    if Theme._roles.Has(hwnd)
                        Theme._roles.Delete(hwnd)
            }
            try ov.Destroy()
        }
        dead := []
        for id in this._ids
            if (SubStr(id, 1, 7) = "layout:")
                dead.Push(id)
        for id in dead
            this._ids.Delete(id)
        this._edCtl := Map()
        this._edHot := Map()
    }

    ; ---- Edit layout: the mouse ----
    ; A handle's (or grip's) WM_LBUTTONDOWN starts a 15 ms loop that reads
    ; the mouse and calls _DragStep until the button is up. Escape puts the
    ; card back. The loop ends when the window is gone or not in front, and
    ; never sends any input.

    static _HookEdit() {
        if Dashboard._edHooked
            return
        Dashboard._edHooked := true
        OnMessage(0x0201, ObjBindMethod(Dashboard, "_OnEdDown"))       ; WM_LBUTTONDOWN
    }

    static _OnEdDown(wParam, lParam, msg, hwnd) {
        d := Dashboard._edActive
        if (!IsObject(d) || !d._edHot.Has(hwnd))
            return
        h := d._edHot[hwnd]
        pt := Buffer(8, 0)
        DllCall("GetCursorPos", "Ptr", pt)
        if (d._DragBegin(h[1], h[2], NumGet(pt, 0, "Int"), NumGet(pt, 4, "Int")) && IsObject(d._dragFn))
            SetTimer(d._dragFn, 15)
        return 0
    }

    ; A drag of card `id` starts at screen point (mx, my). kind "move" | "size".
    _DragBegin(kind, id, mx, my) {
        if (!this._editLayout || IsObject(this._drag) || !IsNumber(mx) || !IsNumber(my))
            return false
        card := this._EdCard(id)
        if !IsObject(card)
            return false
        this._drag := {kind: (kind = "size") ? "size" : "move", card: card, mx: mx, my: my
            , x: card.x, y: card.y, w: card.w, h: card.h, had: this._lay.Has(card.id) ? this._lay[card.id].Clone() : "", hwnd: this._gui.Hwnd}
        return true
    }

    ; One step of a drag: the mouse at (mx, my), the button down or not,
    ; Escape pressed or not. The card goes to its start + the mouse delta in
    ; 100 % units, snapped. -> "move" | "end" (released) | "cancel" (Escape) | ""
    _DragStep(mx, my, down, esc) {
        dr := this._drag
        if !IsObject(dr)
            return ""
        card := dr.card
        try {
            if esc {
                this._EdPlace(card, dr.x, dr.y, dr.w, dr.h)
                if IsObject(dr.had)
                    this._lay[card.id] := dr.had
                else if this._lay.Has(card.id)
                    this._lay.Delete(card.id)
                this._DragStop()
                this._EdMarks()
                return "cancel"
            }
            k := this._PxPerUnit()
            ux := Layout.Snap((mx - dr.mx) / k), uy := Layout.Snap((my - dr.my) / k)
            if (dr.kind = "move")
                x := dr.x + ux, y := dr.y + uy, w := card.w, h := card.h
            else {
                a := this.PageArea()
                x := card.x, y := card.y
                w := Min(dr.w + ux, a.x + a.w - card.x), h := Min(dr.h + uy, a.y + a.h - card.y)
            }
            if (x != card.x || y != card.y || w != card.w || h != card.h) {
                this._EdPlace(card, x, y, w, h)
                this._EdMarks()
            }
        } catch Any as err {
            try OutputDebug("Dashboard drag failed: " err.Message)
            this._DragStop()
            return "end"
        }
        if !down {
            this._DragStop()
            return "end"
        }
        return "move"
    }

    ; screen px per 100 % unit (the Windows scale times the UI size)
    _PxPerUnit() {
        dpi := 96
        try dpi := Theme.DpiFn.Call()
        if !(IsNumber(dpi) && dpi > 0)
            dpi := 96
        return dpi / 96 * (Theme.IsScaled(this._gui) ? Theme.Scale / 100 : 1)
    }

    ; The 15 ms loop: stops when the window is gone; when it is not in front
    ; (or the overlay is gone) the half-done drag is put back like Escape.
    _DragTick() {
        dr := this._drag
        if !IsObject(dr)
            return this._DragStop()
        if !DllCall("IsWindow", "Ptr", dr.hwnd)
            return this._DragStop()
        if (!IsObject(this._edGui) || DllCall("GetForegroundWindow", "Ptr") != dr.hwnd)
            return this._DragStep(0, 0, false, true)     ; cut short: the card goes back like Escape
        pt := Buffer(8, 0)
        DllCall("GetCursorPos", "Ptr", pt)
        this._DragStep(NumGet(pt, 0, "Int"), NumGet(pt, 4, "Int"), GetKeyState("LButton"), GetKeyState("Escape", "P"))
    }

    _DragStop() {
        if IsObject(this._dragFn)
            try SetTimer(this._dragFn, 0)
        this._drag := ""
    }

    ; Look > Apply: refused while another page has unsaved edits (the
    ; restart would drop them); else the Look page is saved, the picked
    ; theme becomes the one in use and the window restarts.
    ; -> true when the restart was asked for.
    ApplyTheme() {
        if this._editLayout {
            this._LookNote(I18n.T("Press Done or Cancel on the layout first: Apply restarts the window."), true)
            return false
        }
        others := ""
        for page in this._pages {
            if (page.name != "Look" && this._PageDirty(page))
                others .= (others = "" ? "" : ", ") I18n.T(Dashboard.TabLabel(page.name))
        }
        if (others != "") {
            this._LookNote(I18n.F("Save or revert {1} first: Apply restarts the window.", others), true)
            return false
        }
        if !this.SavePage("Look")
            return false
        name := this._lkName
        try {
            this.cfg.Set("UI.theme", name)
            this.cfg.Save()
        } catch Any as e {
            this._LookNote(I18n.T("Not saved:") " " UiLogic.Scrub(e.Message, this._Secrets()), true)
            return false
        }
        this._LookFillList()
        this._LookNote(I18n.F("{1} is the theme in use. The window restarts to show it.", name))
        r := this._Fire("restart")
        if (r is Integer && r = 0)
            this._LookNote(I18n.F("{1} is the theme in use. Stop the macro (F3), then press Apply to see it now.", name))
        return true
    }

    ; ---- Look: dialogs ----

    _PickPictureFile() {
        this._gui.Opt("+OwnDialogs")
        f := ""
        try f := FileSelect(3, , I18n.T("Pick a background picture"), I18n.T("Pictures") " (*.png; *.jpg; *.jpeg; *.bmp; *.gif)")
        return f
    }

    _PickThemeFile() {
        ex := ThemeStore.ExportDir(this.cfg)
        this._gui.Opt("+OwnDialogs")
        f := ""
        try f := FileSelect(3, DirExist(ex) ? ex : this.cfg.dir, I18n.T("Import a theme"), I18n.T("Moontide themes") " (*.moontheme)")
        return f
    }

    _AskText(title, prompt, def) {
        this._gui.Opt("+OwnDialogs")
        r := InputBox(prompt, I18n.T(title), "w360 h130", def)
        return (r.Result = "OK") ? r.Value : ""
    }

    ; The import preview, built hidden: the theme's colours on a small
    ; window, its fonts, its picture and the file's notes, with Add and
    ; Cancel. -> {gui, add, cancel, swatches, fonts, picture, res}
    _ImportPreview(read) {
        t := read["theme"]
        c := Dashboard.ThemeColors(t)
        f := t["fonts"]
        res := [false]
        sink := Theme.Sink
        Theme.Sink := ""
        try {
            d := Gui("-MinimizeBox -MaximizeBox +Owner" this._gui.Hwnd, Brand.Name " " Chr(0xB7) " " I18n.T("Import a theme"))
            d.BackColor := Theme.Bg
            d.MarginX := 0, d.MarginY := 0
            Theme.DarkCaption(d.Hwnd)
            Theme.Label(d, "x20 y18 w440 h24", I18n.F("Add the theme {1}?", t["name"]), "head", Theme.Bg)
            ; a small window in its colours and fonts
            Theme.Rect(d, 20, 54, 300, 120, c.Bg)
            Theme.Rect(d, 20, 54, 60, 120, c.SideBg)
            d.SetFont("s" f["nav"][2] " norm c" c.Muted, f["nav"][1])
            d.Add("Text", "x26 y70 w52 h22 +0x80 Background" c.SideBg, I18n.T("Home"))
            d.SetFont("s" f["title"][2] " norm c" c.Text, f["title"][1])
            d.Add("Text", "x90 y58 w220 h36 +0x80 Background" c.Bg, I18n.T("Title"))
            Theme.Rect(d, 90, 98, 220, 66, c.FrameC)
            Theme.Rect(d, 91, 99, 218, 64, c.CardBg)
            d.SetFont("s" f["head"][2] " norm c" c.Accent, f["head"][1])
            d.Add("Text", "x98 y102 w200 h20 +0x80 Background" c.CardBg, I18n.T("Heading"))
            d.SetFont("s" f["body"][2] " norm c" c.Text, f["body"][1])
            d.Add("Text", "x98 y124 w120 h20 +0x80 Background" c.CardBg, I18n.T("Body text"))
            d.SetFont("s" f["button"][2] " norm c" c.Ink, f["button"][1])
            d.Add("Text", "x222 y130 w80 h26 +0x80 +0x200 Center Background" c.Accent, I18n.T("Button"))
            ; the 4 base colours
            sw := []
            for i, k in Theme.BaseKeys {
                x := 20 + (i - 1) * 76
                Theme.Rect(d, x, 186, 20, 20, Theme.FrameC)
                sw.Push(Theme.Rect(d, x + 1, 187, 18, 18, t["colors"][k]))
                Theme.Label(d, "x" x + 24 " y188 w50 h18", t["colors"][k], "small", Theme.Bg)
            }
            ; the picture, darkened and placed as it will be
            pic := ""
            if IsObject(read["picBytes"]) {
                tmp := A_Temp "\moontide_preview_" A_TickCount "." read["picExt"]
                try {
                    fo := FileOpen(tmp, "w")
                    fo.RawWrite(read["picBytes"])
                    fo.Close()
                    hbm := Theme.DimPicture(tmp, 128, 92, c.Bg, t["picture"]["dim"] / 100, t["picture"]["fit"])
                    if hbm
                        pic := d.Add("Picture", "x332 y54 w128 h92", "HBITMAP:" hbm)
                }
                try FileDelete(tmp)
            }
            pf := t["picture"]["file"]
            if !IsObject(pic)
                pic := Theme.Label(d, "x332 y54 w128 h92 +0x200 Center", pf = "none" ? I18n.T("No picture")
                    : ThemeStore.PresetName(pf) != "" ? I18n.F("{1} picture", ThemeStore.PresetName(pf)) : I18n.T("No picture"), "muted", Theme.CardBg)
            ; fonts and sizes
            ft := ""
            for r in ThemeStore.FontRoles
                ft .= (ft = "" ? "" : "`n") I18n.T(Dashboard.LookRoleLabels[r]) ": " f[r][1] " " f[r][2]
            fl := Theme.Label(d, "x20 y216 w440 h96", ft, "small", Theme.Bg)
            nt := ""
            for n in read["notes"]
                nt .= (nt = "" ? "" : "`n") n
            Theme.Label(d, "x20 y316 w440 h36", nt, "muted", Theme.Bg)
            close := (ok) => (res[1] := ok, d.Destroy())
            cancel := Theme.Button(d, "x" 460 - 130 - 8 - 130 " y360 w130 h32", "Cancel", (*) => close(false))
            add := Theme.Button(d, "x" 460 - 130 " y360 w130 h32", "Add", (*) => close(true), "primary")
            Theme.Rect(d, 0, 412, 480, 1, Theme.Bg)
            d.OnEvent("Close", (*) => close(false))
            d.OnEvent("Escape", (*) => close(false))
        } finally
            Theme.Sink := sink
        return {gui: d, add: add, cancel: cancel, swatches: sw, fonts: fl, picture: pic, res: res}
    }

    ; the import preview shown over the dashboard until answered -> true for Add
    _ImportAsk(read) {
        pv := this._ImportPreview(read)
        d := pv.gui
        hwnd := d.Hwnd
        owner := this._gui
        vis := DllCall("IsWindowVisible", "Ptr", owner.Hwnd)
        if vis
            owner.Opt("+Disabled")
        try {
            d.Show("AutoSize Hide")
            d.GetPos(, , &dw, &dh)
            if vis {
                owner.GetPos(&ox, &oy, &ow, &oh)
                d.Show("x" ox + (ow - dw) // 2 " y" oy + (oh - dh) // 2)
            } else
                d.Show("Center")
            WinWaitClose("ahk_id " hwnd)
        } finally {
            this._ImportClose(d)
            if vis {
                owner.Opt("-Disabled")
                try WinActivate("ahk_id " owner.Hwnd)
            }
        }
        return pv.res[1]
    }

    ; The preview window gone with every Theme entry of its controls (Forget
    ; walks the window's controls, so it runs before Destroy).
    _ImportClose(d) {
        try Theme.Forget(d)
        try d.Destroy()
    }

    ; ---- dropped files (WM_DROPFILES) ----

    static _drops := Map()             ; dashboard hwnd -> Dashboard
    static _dropHooked := false

    _HookDrop() {
        hwnd := this._gui.Hwnd
        Dashboard._drops[hwnd] := this
        try DllCall("shell32\DragAcceptFiles", "Ptr", hwnd, "Int", 1)
        ; a macro run as admin still takes files dropped from Explorer
        for msg in [0x233, 0x4A, 0x49]
            try DllCall("ChangeWindowMessageFilterEx", "Ptr", hwnd, "UInt", msg, "UInt", 1, "Ptr", 0)
        if !Dashboard._dropHooked {
            Dashboard._dropHooked := true
            OnMessage(0x233, ObjBindMethod(Dashboard, "_OnDropFiles"))
        }
    }

    static _OnDropFiles(wParam, lParam, msg, hwnd) {
        if !Dashboard._drops.Has(hwnd)
            return
        d := Dashboard._drops[hwnd]
        paths := []
        try {
            n := DllCall("shell32\DragQueryFileW", "Ptr", wParam, "UInt", 0xFFFFFFFF, "Ptr", 0, "UInt", 0, "UInt")
            Loop Min(n, 16) {
                len := DllCall("shell32\DragQueryFileW", "Ptr", wParam, "UInt", A_Index - 1, "Ptr", 0, "UInt", 0, "UInt")
                buf := Buffer((len + 1) * 2, 0)
                DllCall("shell32\DragQueryFileW", "Ptr", wParam, "UInt", A_Index - 1, "Ptr", buf, "UInt", len + 1, "UInt")
                paths.Push(StrGet(buf, "UTF-16"))
            }
        }
        try DllCall("shell32\DragFinish", "Ptr", wParam)
        SetTimer(() => d.DropFiles(paths), -1)          ; the preview is modal: not inside the message
        return 0
    }

    ; ---- page: Clips ----------------------------------------------------------------

    _PageClips(p) {
        g := this._gui
        this._Panel(204, 152, 396, 400, "Clips")
        this._BoolField(220, 186, "Save clips", "Medal.enabled", 0)
        ; the clip app (2026-11-16): made empty, then filled (a dropdown made
        ; with its items is that many rows tall and stops the page painting)
        this._FieldLabel(220, 214, "Clip app", "Medal.app", 130)
        dd := Theme.Dropdown(g, 350, 214, 180)
        dd.Add(Dashboard._ClipAppNames())
        this._Bind("app", "Medal.app", "medal", dd)
        dd.OnEvent("Change", ObjBindMethod(this, "_ClipAppChange"))
        this._StrField(220, 250, "Clip hotkey", "Medal.clipHotkey", "F8", 120, 130)
        this._IntField(220, 286, "Delay (s)", "Medal.delaySec", 3, "", 90)
        this._IntField(398, 286, "Cooldown (s)", "Medal.cooldownSec", 30, "", 110)
        this._BoolField(220, 324, "Clip on rare biome", "Medal.onRareBiome", 1)
        this._BoolField(220, 352, "Clip on rare aura", "Medal.onRareAura", 0)
        ; aura rule (lib\Auras.ahk): listed OR class listed OR 1-in-N >= threshold
        ; the three rule fields share one label column, wide enough for the
        ; translations at full size (fil "Laging i-clip ang klase" was 6-7 pt)
        this._StrField(220, 382, "Clip auras rarer than 1 in", "Medal.auraMinRarity", "100000000", 150, 190)
        this._binds[this._binds.Length].kind := "rarity"
        this._StrField(220, 416, "Always clip classes", "Medal.auraAlwaysCategories", "Challenged,Challenged+", 178, 190)
        this._StrField(220, 450, "Always clip auras", "Medal.auras", "", 178, 190)
        this._BoolField(220, 484, "Clip every aura with a cutscene", "Medal.clipCutscenes", 0)
        ; the Discord page's rare aura alert has its own threshold: shown here
        ; (2026-11-20: a user set clips to 1 in 500m and was pinged for a
        ; 1 in 375m aura by the alert's 50m)
        this._ids["clipPingNote"] := Theme.Label(g, "x220 y516 w364 h32", "", "muted")
        this.Ctrl("Medal.auraMinRarity").OnEvent("Change", ObjBindMethod(this, "_RarityNotes"))
        this._Panel(616, 152, 396, 108, "Clip app", "The macro presses your clip app's save-clip hotkey a few seconds after the moment, "
            . "so set the same key in the app. Picking an app fills in its usual hotkey. The hotkey is F4-F24 or a combo like Alt+C, "
            . "never a macro, capture or recorder key.`n`n"
            . "A rare aura is clipped when it is listed, its class is listed, or it is rarer than the threshold. "
            . "'Clip every aura with a cutscene' clips any new aura that plays a roll cutscene (1 in 1,000 and rarer, and new limited auras), whatever the threshold.")
        this._ids["clipAppRun"] := Theme.Label(g, "x632 y184 w364 h20", "", "muted")
        this._ids["clipAppTip"] := Theme.Label(g, "x632 y206 w364 h44", "", "muted")
        p.onShow := (*) => (this._ClipAppNote(), this._RarityNotes())
        p.validate := ObjBindMethod(this, "_ClipsCheck")
        this._SaveBar(p)
    }

    ; Configured calibration capture key ([Calibrate] captureKey, default
    ; Calibrate.DefaultCaptureKey = F4; F9 is Roblox's developer console).
    _CapKey() {
        k := Trim(this.cfg.Get("Calibrate.captureKey", Calibrate.DefaultCaptureKey))
        return (k = "" || StrUpper(k) = "F9") ? Calibrate.DefaultCaptureKey : k
    }

    ; the clip app dropdown's names, in Clip.Apps order
    static _ClipAppNames() {
        out := []
        for a in Clip.Apps
            out.Push(a.id = "other" ? "Other" : a.name)
        return out
    }

    ; how to set each clip app up (the Clip app panel)
    static ClipAppTips := Map(
        "medal", "Set the same hotkey in Medal (Settings > Clips).",
        "discord", "In Discord: User Settings > Clips, turn on clips and set the same keybind (Discord's default is Alt+C).",
        "nvidia", "In the NVIDIA app: turn on Instant Replay. Its save hotkey is Alt+F10 unless you changed it.",
        "amd", "In AMD Software: turn on Instant Replay. Its save hotkey is Ctrl+Shift+S unless you changed it.",
        "obs", "In OBS: start the Replay Buffer and give 'Save Replay' the same hotkey (Settings > Hotkeys).",
        "other", "Any app with a save-clip hotkey: type the same key above. Nothing checks that it is running.")

    _ClipApp() {
        dd := this.Ctrl("Medal.app")
        return Clip.Apps[(IsObject(dd) && dd.Value >= 1) ? dd.Value : 1]
    }

    ; the Clip app panel's two lines for the picked app
    _ClipAppNote(*) {
        a := this._ClipApp()
        if !IsObject(this.Ctrl("clipAppRun"))
            return
        Theme.SetText(this.Ctrl("clipAppRun"), a.exes.Length ? I18n.F("{1} ({2}) must be running.", StrTitle(SubStr(a.name, 1, 1)) SubStr(a.name, 2), a.exes[1]) : I18n.T("Any clip app (not checked)."))
        Theme.SetText(this.Ctrl("clipAppTip"), I18n.T(Dashboard.ClipAppTips[a.id]))
        this._clipAppShown := a.id
    }

    ; another app picked: its usual hotkey in the field when the field was
    ; empty or held the last app's usual one (a key typed by hand is kept)
    _ClipAppChange(ctrl, *) {
        a := this._ClipApp()
        prev := this.HasOwnProp("_clipAppShown") ? Clip.App(this._clipAppShown) : ""
        hk := this.Ctrl("Medal.clipHotkey")
        cur := Trim(hk.Value)
        if (a.key != "" && (cur = "" || (IsObject(prev) && StrUpper(cur) = StrUpper(prev.key))))
            hk.Value := a.key
        this._ClipAppNote()
    }

    ; The clip and ping thresholds are two settings on two pages, read as one
    ; (2026-11-20): each card says the other's number, from its field as
    ; typed (else the saved value). Never changes a saved value.
    _RarityNotes(*) {
        try {                                   ; an edit's Change event: never throws
            clip := this._RarityTyped("Medal.auraMinRarity", Auras.MinRarity(this.cfg))
            ping := Auras.ParseRarity(this.cfg.Get("AuraAlert.minRarity", "10000000"))
            ping := this._RarityTyped("AuraAlert.minRarity", (ping = "" || ping < 1) ? 10000000 : ping)
            if IsObject(c := this.Ctrl("clipPingNote"))
                Theme.SetText(c, I18n.F("Discord pings use their own limit: 1 in {1} (Discord page)", Auras.Format(ping)))
            if IsObject(c := this.Ctrl("alertClipNote"))
                Theme.SetText(c, I18n.F("Clips use 1 in {1} (Clips page)", Auras.Format(clip)))
        }
    }

    ; the rarity typed in field `key`, else `saved`
    _RarityTyped(key, saved) {
        c := this.Ctrl(key), v := ""
        if IsObject(c)
            try v := Auras.ParseRarity(c.Value)
        return (v = "" || v < 1) ? saved : v
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
        Theme.SetText(this._psMask, cur = "" ? I18n.T("(not set)") : UiLogic.MaskSecret(cur))
        hk := (k, d) => this.cfg.Get("Hotkeys." k, d)
        Theme.SetText(this._hkText, I18n.F("{1} start   {2} pause / resume   {3} stop (halts potions)", hk("start", "F1"), hk("pause", "F2"), hk("stop", "F3")) "`n"
            . I18n.F("Capture key {1}   Route recorder {2}", this._CapKey(), RouteRecorder.Key))
    }

    _PsClear() {
        this._psWipe := true
        this._psEdit.Value := ""
        Theme.SetText(this._psMask, I18n.T("(clear on Save)"))
        this._MarkDirty("Settings")
    }

    _SettingsSave() {
        cur := this.cfg.Get("General.privateServer", "")
        new := this._psWipe ? "" : UiLogic.NewSecret(cur, this._psEdit.Value)
        this.cfg.Set("General.privateServer", new)
        this._psWipe := false
        this._psEdit.Value := ""
        Theme.SetText(this._psMask, new = "" ? I18n.T("(not set)") : UiLogic.MaskSecret(new))
        return ""
    }

    ; ---- page: Biome items --------------------------------------------------------

    _PageBiomeItems(p) {
        g := this._gui
        this._Panel(204, 152, 808, 352, "Biome items", "Used in any biome you have NOT marked rare (Biomes & Potions > Biomes), so a rare biome is never changed away. "
            . "One item per 20 minutes (the game's server cooldown); the first ticked item that is off its own cooldown goes first. "
            . "The ONE-TIME Biome Randomizer is never used: a tile or description that says one-time / single use is refused. "
            . "Needs the inventory calibration steps; the Biome Selector's list of Drives is found on screen by the macro.")
        this._BoolField(220, 186, "Use biome items", "BiomeItems.enabled", 0)
        Theme.Rect(g, 220, 218, 776, 1, Theme.PanelC)
        this._BoolField(220, 232, "Biome Randomizer  (35 min cooldown)", "BiomeItems.biomeRandomizer", 0, 420)
        this._BoolField(220, 264, "Strange Controller  (20 min cooldown)", "BiomeItems.strangeController", 0, 420)
        this._BoolField(220, 296, "Biome Selector  (60 min cooldown, spends one Drive)", "BiomeItems.biomeSelector", 0, 420)
        Theme.Label(g, "x274 y334 w140 h20", "Drive to summon", "muted")
        items := [I18n.T("(pick one)")]       ; row 1 = no Drive (saved as "")
        for d in BiomeItemsTask.Drives
            items.Push(d)
        this._selDrive := Theme.Dropdown(g, 420, 330, 260, items)
        this._selDrive.OnEvent("Change", ObjBindMethod(this, "_MarkDirty", p))
        this._ids["BiomeItems.selectorDrive"] := this._selDrive
        ; blacklist: no item while one of these biomes is up (the user,
        ; 2026-11-15: keep STARFALL); saved as BiomeItems.blacklist
        Theme.Rect(g, 220, 370, 776, 1, Theme.PanelC)
        Theme.Label(g, "x220 y382 w776 h20", "Don't use items during these biomes (wait until the biome changes):", "muted")
        this._biBlack := Map()
        for i, b in Biomes.Normal {
            x := 220 + Mod(i - 1, 5) * 156, y := 410 + ((i - 1) // 5) * 34
            this._biBlack[b] := Theme.Check(g, x, y, StrTitle(b), 0, ObjBindMethod(this, "_MarkDirty", p), "pill", 96)
        }
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
        black := BiomeItemsTask.Blacklist(this.cfg)
        for b, c in this._biBlack
            c.Value := black.Has(b) ? 1 : 0
    }

    _BiomeItemsSave() {
        t := this._selDrive.Text
        this.cfg.Set("BiomeItems.selectorDrive", (this._selDrive.Value <= 1) ? "" : t)
        list := ""
        for b in Biomes.Normal
            if this._biBlack[b].Value
                list .= (list = "" ? "" : ",") b
        this.cfg.Set("BiomeItems.blacklist", list)
        return ""
    }

    ; ---- page: Obby & Memory ------------------------------------------------------

    _PageObbyMemory(p) {
        g := this._gui
        this._Panel(204, 152, 396, 220, "Obby", "Runs the obby for the Basic Blessing on a timer: equips the Sailor aura (it walks on water), plays the obby route, then puts your aura back. "
            . "Record the obby route WITH Sailor on (from a respawn to the star) on Help > Routes, and calibrate the aura storage steps (aura_open ... aura_close). "
            . "With buff_expand and obby_blessing calibrated the buff list is expanded, the blessing checked and the list collapsed again; a failed run is tried again Retries times.")
        this._BoolField(220, 186, "Run the obby", "Obby.enabled", 0)
        this._IntField(220, 224, "Every", "Obby.intervalMin", 10, "minutes", 170, 1)
        this._IntField(220, 262, "Retries", "Obby.retries", 2)
        this._ids["obbyBlessingNote"] := Theme.Label(g, "x220 y306 w364 h56", "", "muted")
        this._Panel(616, 152, 396, 220, "Memory Match", "Plays the Memory Match board (20 tiles, 10 turns, every 12 hours) and keeps the best pairs. "
            . "Record the memory_match route (to the board) on Help > Routes. It stays off until the board layout is added from a clip of one round.")
        this._memSwitch := this._BoolField(632, 186, "Play Memory Match", "MemoryMatch.enabled", 0)
        ; no warning any more (2026-11-16, the owner: Memory Match is not buggy now)
        if !MemoryMatchTask.LayoutKnown {
            ; no layout yet: the switch cannot be turned on
            this._memSwitch.DefineProp("Flip", {Call: (*) => 0})
            Theme.SetColors(this._memSwitch._box, Theme.OffBg, Theme.Muted)
        }
        this._ids["memoryLayoutNote"] := Theme.Label(g, "x632 y224 w364 h40", "", "muted")
        this._ids["memoryNote"] := Theme.Label(g, "x632 y272 w364 h20", "", "muted")
        this._ids["memoryReset"] := Theme.Button(g, "x632 y300 w150 h28", "Reset timer", (*) => this.ResetMemoryTimer())
        ; every aura swap (the obby's Sailor, the combat aura, putting yours back)
        this._Panel(204, 388, 808, 100, "Aura swaps")
        this._BoolField(220, 422, "Equip the first search result", "Auras.equipFirst", 0, , "Equip the first search result (no name reading): use this if aura swaps fail at your resolution. "
            . "Make sure the search finds only the aura you want. Used for every aura swap: Sailor for the obby, the combat aura, and putting your aura back.")
        Theme.Label(this._gui, "x220 y454 w776 h20", "For aura swaps that fail at your resolution (the obby and the hunting plugin too).", "muted")
        p.load := ObjBindMethod(this, "_ObbyMemoryLoad")
        p.validate := ObjBindMethod(this, "_ObbyMemoryCheck")
        this._SaveBar(p)
    }

    _ObbyMemoryLoad() {
        cal := IsObject(Calibrate.Point("obby_blessing")) && IsObject(Calibrate.Point("buff_expand"))
        Theme.SetText(this._ids["obbyBlessingNote"], I18n.T(cal
            ? "buff_expand + obby_blessing calibrated: the blessing is checked after each run"
            : "buff_expand / obby_blessing not calibrated: runs are unchecked (Help > Calibrate)"))
        known := MemoryMatchTask.LayoutKnown
        if !known
            this._memSwitch.Value := 0
        Theme.SetText(this._ids["memoryLayoutNote"], known ? "" : I18n.T("waiting for the board layout (send a clip of one round)"))
        nt := ""
        try nt := MemoryMatchTask({cfg: this.cfg, statePath: Dashboard.MemoryStatePath}).NextTry()
        Theme.SetText(this._ids["memoryNote"], (nt = "")
            ? I18n.T("next try: now (when it is on)")
            : I18n.F("next try: {1} on {2}", FormatTime(nt, "HH:mm"), FormatTime(nt, "dd MMM")))
    }

    ; "Reset timer": Memory Match plays at its next chance instead of waiting
    ; out the 12 hours. The running macro reads the same file, so it counts
    ; at once. Tests point MemoryStatePath at a temp file ("" = the real one).
    static MemoryStatePath := ""
    ResetMemoryTimer() {
        ok := false
        try ok := MemoryMatchTask({cfg: this.cfg, statePath: Dashboard.MemoryStatePath}).ResetTimer()
        this._ObbyMemoryLoad()
        if ok
            this.Log("Memory Match: timer reset, it plays at the next chance")
        return ok
    }

    ; "" or why Obby & Memory cannot be saved (checked before cfg is touched).
    _ObbyMemoryCheck() {
        mins := UiLogic.UInt(this.Ctrl("Obby.intervalMin").Value, 10)
        if (mins < 1 || mins > 120)
            return "obby: every must be 1 to 120 minutes"
        tries := UiLogic.UInt(this.Ctrl("Obby.retries").Value, 2)
        if (tries > 3)
            return "obby: retries must be 0 to 3"
        return ""
    }

    ; ---- page: Stats (Home) -----------------------------------------------------

    ; [key, label] rows of the Today / This run panels. Keys are DailyStats
    ; counters or DailyStats.Derived values (reelRate, fishPerHour, uptimeText).
    static StatRows := [["fishCaught", "Fish caught"], ["fishFailed", "Fish missed"], ["reelRate", "Reel success"]
        , ["fishPerHour", "Fish per hour"], ["sells", "Sell trips"], ["biomes", "Biomes seen"], ["rareBiomes", "Rare biomes"]
        , ["rareAuras", "Rare auras"], ["rejoins", "Rejoins"]
        , ["hunts", "Hunts"], ["huntOrbs", "Orbs killed"], ["huntMinions", "Minions killed"], ["huntDeaths", "Hunt deaths"]   ; MinionsTask._CountHunt
        , ["uptimeText", "Uptime"]]
    ; the Check & help summary, by which counts are 1 (I18n.F with ok, warnings, problems)
    static CheckCounts := ["{1} ok, {2} warnings, {3} problems", "{1} ok, {2} warning, {3} problems"
        , "{1} ok, {2} warnings, {3} problem", "{1} ok, {2} warning, {3} problem"]
    static StatRowH := 20         ; row pitch: 14 rows fit the panels above the 7-day list

    _PageStats(p) {
        g := this._gui
        for col in [["day", 204, "Today"], ["run", 616, "This run"]] {
            parts := this._Panel(col[2], 152, 396, 318, col[3])
            if (col[1] = "run") {
                ; the second panel shows this run or the all-time totals
                ; (DailyStats.AllTime); the title says which, the pick is kept
                ; until the dashboard closes
                Theme.MoveTo(parts[3], , , 200)
                this._ids["stats:runTitle"] := parts[3]
                this._statsMode := "This run"
                this._statsRunMap := Map(), this._statsAllMap := Map(), this._statsSince := ""
                seg := Theme.Segmented(g, 836, 158, ["This run", "All time"], 1, (lb) => this._StatsView(lb), 80, 22)
                this._ids["statsView"] := seg
            }
            for i, r in Dashboard.StatRows {
                y := 184 + (i - 1) * Dashboard.StatRowH
                Theme.Label(g, "x" col[2] + 16 " y" y " w200 h20", r[2], "body", Theme.CardBg)
                this._ids["stats:" col[1] ":" r[1]] := Theme.Label(g, "x" col[2] + 216 " y" y " w164 h20 Right", "0", "value", Theme.CardBg)
            }
        }
        ; the 7-day list ends at y 620 (the page area's bottom)
        this._Panel(204, 482, 808, 138, "Last 7 days")
        hw := [120, 90, 90, 80, 90, 80, 90, 110]
        Theme.ListHeader(g, 220, 510, hw, ["Day", "Fish", "Missed", "Reel", "Biomes", "Rare", "Rejoins", "Uptime"])
        this._statsHist := Theme.ListView(g, 220, 534, 776, 74, ["Day", "Fish", "Missed", "Reel", "Biomes", "Rare", "Rejoins", "Uptime"], hw)
        this._ids["stats:history"] := this._statsHist
    }

    ; Stats page. day / run / all: Maps of counters plus DailyStats.Derived
    ; keys (missing = 0); history: Array of {label, m} newest first, or "" to
    ; keep it. all / since (yyyyMMdd): the all-time totals and their first
    ; day, shown in the second panel when "All time" is picked ("" = keep).
    SetStatsPage(day, run, history := "", all := "", since := "") {
        this._statsRunMap := (run is Map) ? run : Map()
        if (all is Map)
            this._statsAllMap := all, this._statsSince := String(since)
        if (this._statsMode = "All time")
            run := this._statsAllMap
        this._StatsTitle()
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

    ; Stats > "This run" / "All time" picked: the second panel redrawn from
    ; the numbers it was last given
    _StatsView(label) {
        this._statsMode := (label = "All time") ? "All time" : "This run"
        m := (this._statsMode = "All time") ? this._statsAllMap : this._statsRunMap
        this._StatsTitle()
        for r in Dashboard.StatRows {
            c := this._ids["stats:run:" r[1]]
            v := Dashboard.StatText(m, r[1])
            if (c.Text != v)
                Theme.SetText(c, v)
        }
    }

    ; "THIS RUN" or "ALL TIME, SINCE 2 NOV 2026"
    _StatsTitle() {
        t := I18n.T("This run")
        if (this._statsMode = "All time")
            t := RegExMatch(this._statsSince, "^\d{8}$") ? I18n.F("All time, since {1}", FormatTime(this._statsSince "000000", "d MMM yyyy")) : I18n.T("All time")
        Theme.SetText(this._ids["stats:runTitle"], StrUpper(t))
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

    ; ---- page: Daily summary (Discord & Clips) ----------------------------------

    _PageSummary(p) {
        g := this._gui
        this._Panel(204, 152, 396, 200, "Daily summary", "Once a day at the time below, one Discord message with what the macro did that day. "
            . "It goes to every webhook that has Stop (start / stop messages) ticked on Discord & Clips > Discord. Send one now sends today's so far.")
        this._BoolField(220, 186, "Send a daily summary to Discord", "Summary.enabled", 0)
        this._StrField(220, 224, "Send at (24 h)", "Summary.time", "23:55", 70)
        Theme.Label(g, "x220 y262 w364 h36", "Goes to the webhooks that get start / stop messages (Discord & Clips > Discord).", "muted")
        Theme.Button(g, "x220 y306 w150 h30", "Send one now", (*) => this._SummaryNow())
        this._ids["summaryStatus"] := Theme.Label(g, "x380 y312 w210 h20", "", "muted")
        this._Panel(616, 152, 396, 200, "What it says")
        Theme.Label(g, "x632 y184 w364 h150", "Fish caught and missed, reel success`nSell trips`nBiomes and rare biomes seen`nRare auras rolled`nRejoins`nHow long the macro ran", "body", Theme.CardBg)
        p.validate := () => Dashboard.TimeOk(this.Ctrl("Summary.time").Value) ? "" : "summary: send at must be a time like 23:55"
        this._SaveBar(p)
    }

    _SummaryNow() {
        r := this._Fire("sendSummary")
        Theme.SetText(this._ids["summaryStatus"], r = "" ? I18n.T("Not sent: the macro is not ready") : r)
    }

    ; "HH:mm" 24 h (one-digit hour allowed)
    static TimeOk(s) => RegExMatch(Trim(String(s)), "^([01]?\d|2[0-3]):[0-5]\d$") ? true : false

    ; ---- page: Remote (Discord & Clips) -----------------------------------------

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
        Theme.Button(g, "x220 y402 w170 h30", "Test connection", (*) => this._RemoteTest())
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
        Theme.SetText(this._rmMask, cur = "" ? I18n.T("(not set)") : UiLogic.MaskSecret(cur))
    }

    _RmClear() {
        this._rmWipe := true
        this._rmEdit.Value := ""
        Theme.SetText(this._rmMask, I18n.T("(clear on Save)"))
        this._MarkDirty("Remote")
    }

    _RemoteSave() {
        cur := this.cfg.Get("Remote.token", "")
        new := this._rmWipe ? "" : UiLogic.NewSecret(cur, this._rmEdit.Value)
        this.cfg.Set("Remote.token", new)
        this._rmWipe := false
        this._rmEdit.Value := ""
        Theme.SetText(this._rmMask, new = "" ? I18n.T("(not set)") : UiLogic.MaskSecret(new))
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
        Theme.SetText(this._ids["remoteStatus"], I18n.T("Testing..."))
        r := this._Fire("testRemote")
        Theme.SetText(this._ids["remoteStatus"], UiLogic.Scrub(r = "" ? I18n.T("Not tested: the macro is not ready") : r, this._Secrets()))
    }

    ; ---- page: Check & help (Help) ----------------------------------------------

    static CheckTags := Map("ok", "[OK]", "warn", "[!]", "fail", "[X]", "info", "[i]")

    _PageCheck(p) {
        g := this._gui
        this._Panel(204, 152, 396, 464, "Check my setup", "Check now looks at Roblox, your screen, the Roblox logs, your private server link, Discord webhooks, "
            . "calibration and apps that pull focus away from Roblox. It sends no input. [!] = may cause trouble, [X] = will not work. "
            . "Test my calibration tries every recorded calibration spot and says which ones need redoing. Stop the macro first: it opens and closes your inventory and Aura Storage.")
        Theme.Button(g, "x220 y186 w110 h30", "Check now", (*) => this._CheckNow(), "primary")
        Theme.Button(g, "x338 y186 w190 h30", "Test my calibration", (*) => this._TestCal())
        this._ids["checkSummary"] := Theme.Label(g, "x220 y222 w364 h20", "", "muted")
        this._checkOut := Theme.Edit(g, 220, 248, 364, 352, "", "Multi ReadOnly -WantReturn VScroll")
        this._ids["checkOut"] := this._checkOut
        this._Panel(616, 152, 396, 200, "Send my log")
        Theme.Label(g, "x632 y184 w364 h60", "Makes a zip of your log and this check. Webhook links, server links, the bot token, Discord ids and your Windows name are taken out. "
            . "Send it to whoever helps you.", "body", Theme.CardBg)
        Theme.Button(g, "x632 y250 w164 h30", "Make support zip", (*) => this._LogZip())
        this._zipBtn := Theme.Button(g, "x806 y250 w100 h30", "Show it", (*) => this._ZipShow(), "quiet")
        this._SetHidden(this._zipBtn, true)
        ; the label wraps onto two lines so it stays inside the card
        this._zipShots := Theme.Check(g, 632, 288, "Add recent screenshots (they can show your Roblox name and chat)", 0, "", "box", 340)
        this._zipShots._lbl.Opt("-0x200")
        Theme.MoveTo(this._zipShots._lbl, , 286, 340, 34)
        this._ids["zipShots"] := this._zipShots
        this._ids["zipStatus"] := Theme.Label(g, "x632 y320 w364 h30", "", "muted")
        this._Panel(616, 368, 396, 248, "Setup wizard")
        Theme.Label(g, "x632 y400 w364 h60", "Walks through the basics: the Roblox check, your private server, Discord and what to run. Every step can be skipped.", "body", Theme.CardBg)
        Theme.Button(g, "x632 y472 w180 h30", "Run the setup wizard", (*) => this._Fire("wizard"))
        this._zipPath := ""
    }

    _CheckNow() {
        Theme.SetText(this._ids["checkSummary"], I18n.T("Checking..."))
        this.ShowCheck(this._Fire("checkSetup"))
    }

    ; results: Array of {level, name, detail, fix} (SetupCheck.Run)
    ShowCheck(results) {
        if !IsObject(results) {
            Theme.SetText(this._ids["checkSummary"], I18n.T("Not checked: the macro is not ready"))
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
        Theme.SetText(this._ids["checkSummary"], I18n.F(Dashboard.CheckCounts[(n["warn"] = 1 ? 1 : 0) + (n["fail"] = 1 ? 2 : 0) + 1], n["ok"], n["warn"], n["fail"]))
    }

    static CalTags := Map("REDO", "[REDO]", "OK", "[OK]", "NOT TESTED", "[--]", "", "[i]")

    _TestCal() {
        Theme.SetText(this._ids["checkSummary"], I18n.T("Testing your calibration..."))
        this.ShowCalTest(this._Fire("testCalibration"))
    }

    ; rows: Array of {verdict, name, detail, fix} (CalTest.Run): the notes,
    ; then REDO, OK and NOT TESTED steps
    ShowCalTest(rows) {
        if !IsObject(rows) {
            Theme.SetText(this._ids["checkSummary"], I18n.T("Not checked: the macro is not ready"))
            return
        }
        text := "", n := Map("REDO", 0, "OK", 0, "NOT TESTED", 0)
        for r in rows {
            v := r.HasProp("verdict") ? r.verdict : ""
            if n.Has(v)
                n[v] += 1
            tag := Dashboard.CalTags.Has(v) ? Dashboard.CalTags[v] : "[i]"
            text .= tag "  " r.name (r.HasProp("detail") && r.detail != "" ? ": " r.detail : "") "`r`n"
            if (r.HasProp("fix") && r.fix != "")
                text .= "       " r.fix "`r`n"
        }
        this._checkOut.Value := UiLogic.Scrub(text, this._Secrets(), true)
        Theme.SetText(this._ids["checkSummary"], I18n.F("{1} to redo, {2} ok, {3} not tested", n["REDO"], n["OK"], n["NOT TESTED"]))
    }

    _LogZip() {
        Theme.SetText(this._ids["zipStatus"], I18n.T("Making the zip..."))
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

    ; ---- page: Schedule (Settings) ----------------------------------------------

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

    ; ---- page: Hunting (the "Orb & boss hunting" plugin's page) -----------------

    ; Halloween minion / orb hunting, the built-in plugin HuntingPlugin
    ; (lib\plugins\hunting; the Limited tab until 2026-11-26). Opened from
    ; Plugins > Settings; the plugin's switch is on the Plugins tab.
    _PageHunting(p) {
        g := this._gui
        this._Panel(204, 152, 808, 64, "Orb & boss hunting (plugin)")
        this._ids["limitedNote"] := Theme.Label(g, "x220 y184 w776 h20", "A built-in plugin: switched off on the Plugins tab, none of this page runs.", "muted")
        this._Panel(204, 232, 808, 220, "Hunting (Halloween)", "In every weather biome (not rare, not event): puts on the combat aura, respawns, finds the orbs' and minions' health bars, "
            . "walks up and uses the aura's skills (any aura with skills; never the number keys), then respawns. Once per biome. "
            . "NORMAL has shown no orbs: it is not hunted unless Hunt in NORMAL too is on, only the aura and a respawn are made ready there. "
            . "Needs the aura storage steps calibrated (as the obby). Auto roll can equip a new aura mid-hunt; the skills then do nothing until the next hunt. "
            . "Shift lock keeps the character facing the target in fights; it needs Roblox's Shift Lock Switch setting on. "
            . "Graveyard boss: once per GRAVEYARD start it looks around ~20 s for the boss (before any aura swap) and fights it up to 10 min.")
        this._WarnOn(this._BoolField(220, 266, "Hunt orbs and minions", "Minions.enabled", 0), "Minion hunting is buggy", "Hunting orbs and minions is still very buggy at every screen size: it can get stuck, miss targets or walk off. Watch it when you use it.")
        auraEdit := this._StrField(220, 304, "Combat aura", "Minions.aura", "Eden", 160)
        auraEdit.OnEvent("LoseFocus", (ctl, *) => this._BigAuraCheck(ctl))
        this._IntField(220, 342, "Hunt at most", "Minions.maxSec", 120, "seconds", 170, 60)
        ; "Put my aura back after" removed 2026-11-23 (nobody used it)
        this._BoolField(632, 266, "Use shift lock in fights", "Minions.shiftLock", 1)
        this._BoolField(632, 304, "Fight the Graveyard boss", "Minions.boss", 1)
        this._BoolField(632, 342, "Hunt in NORMAL too", "Minions.normal", 0)
        ; 2026-11-22: the orb message (a tester) on its own row, the panel taller
        this._Panel(204, 468, 808, 150, "Bosses, orbs and Blood Rain", "Boss message: when the chat names Sinister S. or Sinister P., the boss message is sent (Discord & Clips > Discord, Boss), "
            . "whether hunting is on or off. Orb message (off by default): the same for a biome orb the chat names, as 'Typhoon orb has spawned'. "
            . "Cursed Rune Fragment: one is used from your inventory when GRAVEYARD or PUMPKIN MOON starts (it starts Blood Rain), "
            . "then none until the next Graveyard / Pumpkin Moon night. Needs the inventory calibration steps.")
        this._BoolField(220, 502, "Send the boss message (Sinister S. / P.)", "Hunting.bossAlert", 1, 420)
        this._BoolField(220, 540, "Send the orb message (e.g. Typhoon orb)", "Hunting.orbAlert", 0, 420)
        this._BoolField(220, 578, "Use ONE Cursed Rune Fragment per Graveyard / Pumpkin Moon", "Hunting.cursedRune", 0, 520)
        p.validate := ObjBindMethod(this, "_HuntingCheck")
        this._BackBar()
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

    ; ---- page: Plugins (Quests & events) ------------------------------------------
    ; The built-in plugins and every file / folder in plugins\ (lib\Plugins.ahk,
    ; the host from the "plugins" callback). A row per plugin, broken files
    ; too (Status: Error: why). The switch acts at once (no Save); Settings
    ; opens the plugin's page. Ids: "pluginList", "pluginOn", "pluginSettings",
    ; "pluginName", "pluginDesc", "pluginStatus", "pluginRestart",
    ; "pluginRescan", "pluginFolder", "pluginEmpty".

    _Host() {
        if !this._cb.Has("plugins")
            return ""
        try return this._cb["plugins"].Call()
        return ""
    }

    _PagePlugins(p) {
        g := this._gui
        this._plRows := []
        this._Panel(204, 152, 808, 300, "Plugins", "Drop a plugin (a .ahk file, or a folder with plugin.ahk) into the plugins folder next to MoontideMacro.exe, then press Rescan. "
            . "A new plugin is off: switch it on and restart the macro to load it. Before it loads it is checked in a separate process, so a broken file only shows an error here. "
            . "Updates never touch the plugins folder. How to write one: the README, Plugins.")
        cw := [230, 80, 90, 376]
        Theme.ListHeader(g, 220, 184, cw, ["Plugin", "Version", "Type", "Status"])
        this._lvPl := Theme.ListView(g, 220, 202, 776, 196, ["Plugin", "Version", "Type", "Status"], cw, "", ObjBindMethod(this, "_PluginColor"))
        this._lvPl.OnEvent("ItemSelect", ObjBindMethod(this, "_PluginSelect"))
        this._ids["pluginList"] := this._lvPl
        this._ids["pluginFolder"] := Theme.Button(g, "x220 y410 w170 h30", "Open plugins folder", (*) => this.OpenPluginsFolder(), "quiet")
        this._ids["pluginRescan"] := Theme.Button(g, "x398 y410 w100 h30", "Rescan", (*) => this.PluginsRescan())
        this._ids["pluginRestart"] := Theme.Button(g, "x506 y410 w170 h30", "Restart to load", (*) => this._PluginRestart(), "primary")
        this._ids["pluginTop"] := Theme.Label(g, "x686 y416 w310 h20 Right", "", "muted")
        this._Panel(204, 468, 808, 148, "Selected plugin")
        this._ids["pluginName"] := Theme.Label(g, "x220 y500 w776 h20", "", "body")
        this._ids["pluginDesc"] := Theme.Label(g, "x220 y522 w776 h40", "", "muted")
        r := this._Grab(() => Theme.Check(g, 220, 574, "Use this plugin", 0, ObjBindMethod(this, "_PluginFlip"), "pill", 200))
        this._ids["pluginOn"] := r.ctl, this._plOnParts := r.parts
        r := this._Grab(() => Theme.Button(g, "x484 y570 w110 h30", "Settings", (*) => this._PluginSettingsBtn()))
        this._ids["pluginSettings"] := r.ctl, this._plSetParts := r.parts
        this._ids["pluginStatus"] := Theme.Label(g, "x604 y576 w392 h20", "", "muted")
        p.load := ObjBindMethod(this, "_PluginsLoad")
        p.onShow := ObjBindMethod(this, "_PluginsLoad")
    }

    _PluginColor(row) {
        e := (row >= 1 && row <= this._plRows.Length) ? this._plRows[row] : ""
        return (IsObject(e) && !e["ok"]) ? Theme.Accent : ""
    }

    ; fills the list (the selection is kept by id)
    _PluginsLoad() {
        host := this._Host()
        lv := this._lvPl
        keep := this._PluginSel()
        lv.Delete()
        this._plRows := []
        if IsObject(host) {
            for e in host.Entries {
                this._plRows.Push(e)
                type := e["builtin"] ? I18n.T("Built-in") : e["folder"] ? I18n.T("Folder") : I18n.T("File")
                lv.Add("", I18n.T(e["name"]), e["version"], type, PluginHost.StatusText(host.Status(e)))
            }
        }
        Theme.FitLastCol(lv)
        sel := 0
        for i, e in this._plRows
            if (IsObject(keep) && e["file"] = keep["file"] && e["id"] = keep["id"])
                sel := i
        if (!sel && this._plRows.Length)
            sel := 1
        if sel
            lv.Modify(sel, "Select Focus Vis")
        this._PluginShow()
        this._SetHidden(this.Ctrl("pluginRestart"), !(IsObject(host) && host.RestartWanted))
        n := 0
        for e in this._plRows
            n += !e["builtin"]
        Theme.SetText(this.Ctrl("pluginTop"), I18n.F("{1} in the plugins folder", n))
    }

    _PluginSel() {
        r := this._lvPl.GetNext(0)
        return (r >= 1 && r <= this._plRows.Length) ? this._plRows[r] : ""
    }

    _PluginSelect(lv, item, selected) {
        if selected
            this._PluginShow()
    }

    _PluginShow() {
        e := this._PluginSel()
        host := this._Host()
        on := this.Ctrl("pluginOn")
        if !IsObject(e) {
            Theme.SetText(this.Ctrl("pluginName"), I18n.T("No plugin selected"))
            Theme.SetText(this.Ctrl("pluginDesc"), "")
            Theme.SetText(this.Ctrl("pluginStatus"), "")
            this._HideParts(this._plOnParts, true)
            this._HideParts(this._plSetParts, true)
            return
        }
        name := I18n.T(e["name"]) (e["version"] != "" ? "  v" e["version"] : "") (e["author"] != "" ? "  " Chr(0xB7) "  " e["author"] : "")
        Theme.SetText(this.Ctrl("pluginName"), name)
        desc := e["ok"] ? I18n.T(e["description"]) : I18n.T("This file is not loaded:") " " e["reason"]
        if !e["builtin"]
            desc := e["file"] ":  " desc
        Theme.SetText(this.Ctrl("pluginDesc"), desc)
        can := e["ok"] || e["builtin"]
        this._HideParts(this._plOnParts, !can)
        on.Value := (can && Plugins.On(this.cfg, e["id"], e["def"])) ? 1 : 0
        hasSet := can && ((e["builtin"] && e["page"] != "") || e["settings"].Length > 0)
        this._HideParts(this._plSetParts, !hasSet)
        Theme.SetText(this.Ctrl("pluginStatus"), IsObject(host) ? PluginHost.StatusText(host.Status(e)) : "")
    }

    _PluginFlip(ctl) {
        e := this._PluginSel()
        host := this._Host()
        if !(IsObject(e) && IsObject(host))
            return
        if (ctl.Value && e.Has("warn") && e["warn"] != "" && this._confirmBuggy.Call(I18n.T(e["name"]), I18n.T(e["warn"])) != true) {
            ctl.Value := 0
            return
        }
        msg := host.SetOn(e["id"], ctl.Value ? 1 : 0)
        this.Log("Plugins: " msg)
        this._PluginsLoad()
        Theme.SetText(this.Ctrl("pluginStatus"), msg)
    }

    _PluginSettingsBtn() {
        e := this._PluginSel()
        if IsObject(e)
            this.OpenPluginPage(e["id"])
    }

    ; Rescan: new / changed / removed files in plugins\
    PluginsRescan() {
        host := this._Host()
        if !IsObject(host)
            return
        try host.Rescan()
        catch Any as e
            this.Log("Plugins: rescan failed: " e.Message)
        this._PluginsLoad()
        Theme.SetText(this.Ctrl("pluginStatus"), I18n.T("Rescanned the plugins folder"))
    }

    OpenPluginsFolder() {
        dir := Plugins.Dir(this.cfg.dir)
        try {
            if !DirExist(dir)
                DirCreate(dir)
            Run('explorer.exe "' dir '"')
        }
    }

    _PluginRestart() {
        if !this._cb.Has("pluginRestart")
            return
        if !this._cb["pluginRestart"].Call()
            Theme.SetText(this.Ctrl("pluginStatus"), I18n.T("Stop the macro first (F3), then press Restart"))
    }

    ; fn() makes controls: -> {ctl: what fn returned, parts: every control it made}
    _Grab(fn) {
        n0 := (Theme.Sink is Array) ? Theme.Sink.Length : 0
        r := fn.Call()
        out := []
        if (Theme.Sink is Array)
            Loop Theme.Sink.Length - n0
                out.Push(Theme.Sink[n0 + A_Index])
        return {ctl: r, parts: out}
    }

    _HideParts(parts, hide) {
        for c in parts
            this._SetHidden(c, hide)
    }

    ; "Back to Plugins" in a plugin page's bottom bar (fixed, left of the save bar)
    _BackBar() {
        n0 := this._FixedBar()
        Theme.Button(this._gui, "x204 y628 w118 h30", Chr(0x2039) " " I18n.T("Plugins"), (*) => this.SelectPage(Dashboard.PageIndex("Plugins")), "quiet")
        this._FixedBar(n0)
    }

    ; ---- page: Plugin settings (a plugin from plugins\) ----------------------------
    ; Up to Plugins.MaxSettings rows from the plugin's manifest (setting:
    ; lines): a switch (bool) or a field (int, text; secret = hidden, kept
    ; when left empty). Filled by OpenPluginPage(id). Ids "psTitle",
    ; "psLabel:<i>", "psEdit:<i>", "psCheck:<i>".

    ; ---- page: Plugin page (a plugin that draws its own page) -----------------------
    ; A loaded plugin with BuildPage(dash, page, hooks) draws its page here,
    ; with the dashboard's own helpers (_Panel, _StrField, _IntField,
    ; _BoolField, Theme..., _MarkDirty(page) for its own controls), so it
    ; looks like every other page. Every such plugin is built once, at start
    ; (plugins load before the dashboard); OpenPluginPage(id) shows only that
    ; plugin's controls. hooks: the plugin sets load / save / validate /
    ; onShow (as a page's) -> called for the plugin shown. Its bound fields
    ; are saved by the page's Save like any other.
    _PagePluginPage(p) {
        this._ppId := ""
        this._ppGroups := Map()
        host := this._Host()
        if IsObject(host) {
            for e in host.Entries {
                o := host.Obj(e["id"])
                if !IsObject(o) || !HasMethod(o, "BuildPage")
                    continue
                hooks := {load: "", save: "", validate: "", onShow: ""}
                try {
                    r := this._Grab(() => o.BuildPage(this, p, hooks))
                    this._ppGroups[e["id"]] := {parts: r.parts, hooks: hooks}
                } catch Any as err
                    host.Log("Plugins: " e["name"] " could not draw its page: " host._ErrText(err))
            }
        }
        p.load := () => this._PpCall("load")
        p.save := () => this._PpCall("save")
        p.validate := () => this._PpCall("validate")
        p.onShow := () => this._PpCall("onShow")
        this._BackBar()
        this._SaveBar(p)
    }

    ; the shown plugin's page hook ("" when it has none)
    _PpCall(kind) {
        if (this._ppId = "" || !this._ppGroups.Has(this._ppId))
            return ""
        fn := this._ppGroups[this._ppId].hooks.%kind%
        if !IsObject(fn)
            return ""
        try return fn.Call()
        catch Any as err {
            host := this._Host()
            if IsObject(host)
                host.Log("Plugins: " this._ppId " page " kind ": " host._ErrText(err))
            return kind = "validate" ? this._ppId ": " host._ErrText(err) : ""
        }
    }

    _PagePluginSettings(p) {
        g := this._gui
        this._psId := ""

        this._Panel(204, 152, 808, 464, "Plugin settings")
        this._ids["psTitle"] := Theme.Label(g, "x220 y184 w776 h20", "", "body")
        this._psParts := []
        Loop Plugins.MaxSettings {
            y := 222 + (A_Index - 1) * 46
            lb := this._Grab(() => Theme.Label(g, "x220 y" y + 4 " w300 h20", ""))
            ed := this._Grab(() => Theme.Edit(g, 530, y, 300, 28))
            ed.ctl.OnEvent("Change", ObjBindMethod(this, "_MarkDirty", p))
            sec := this._Grab(() => Theme.Edit(g, 530, y, 300, 28, "", "Password"))
            sec.ctl.OnEvent("Change", ObjBindMethod(this, "_MarkDirty", p))
            ck := this._Grab(() => Theme.Check(g, 530, y + 4, "", 0, ObjBindMethod(this, "_MarkDirty", p), "pill"))
            this._ids["psLabel:" A_Index] := lb.ctl, this._ids["psEdit:" A_Index] := ed.ctl
            this._ids["psSecret:" A_Index] := sec.ctl, this._ids["psCheck:" A_Index] := ck.ctl
            this._psParts.Push({label: lb.parts, edit: ed.parts, secret: sec.parts, check: ck.parts})
        }
        this._ids["psNone"] := Theme.Label(g, "x220 y222 w776 h20", "", "muted")
        p.load := ObjBindMethod(this, "_PsLoad")
        p.save := ObjBindMethod(this, "_PsSave")
        p.validate := ObjBindMethod(this, "_PsCheck")
        this._BackBar()
        this._SaveBar(p)
    }

    _PsEntry() {
        host := this._Host()
        return (IsObject(host) && this._psId != "") ? host.Find(this._psId) : ""
    }

    _PsLoad() {
        e := this._PsEntry()
        sets := IsObject(e) ? e["settings"] : []
        Theme.SetText(this.Ctrl("psTitle"), IsObject(e) ? e["name"] (e["version"] != "" ? "  v" e["version"] : "") : "")
        Theme.SetText(this.Ctrl("psNone"), IsObject(e) && !sets.Length ? I18n.T("This plugin has no settings.") : "")
        Loop Plugins.MaxSettings {
            s := A_Index <= sets.Length ? sets[A_Index] : ""
            t := IsObject(s) ? s["type"] : ""
            pp := this._psParts[A_Index]
            this._HideParts(pp.label, t = "")
            this._HideParts(pp.edit, !(t = "int" || t = "text"))
            this._HideParts(pp.secret, t != "secret")
            this._HideParts(pp.check, t != "bool")
            if (t = "")
                continue
            Theme.SetText(this.Ctrl("psLabel:" A_Index), s["label"])
            v := this.cfg.Get(PluginHost.SettingPath(e, s), t = "int" ? Integer(s["def"]) : s["def"])
            if (t = "bool")
                this.Ctrl("psCheck:" A_Index).Value := v ? 1 : 0
            else if (t = "secret")
                this.Ctrl("psSecret:" A_Index).Value := ""
            else
                this.Ctrl("psEdit:" A_Index).Value := String(v)
        }
    }

    _PsCheck() {
        e := this._PsEntry()
        if !IsObject(e)
            return ""
        for i, s in e["settings"]
            if (s["type"] = "int" && !RegExMatch(Trim(this.Ctrl("psEdit:" i).Value), "^-?\d{1,9}$"))
                return s["label"] ": " I18n.T("a whole number")
        return ""
    }

    _PsSave() {
        e := this._PsEntry()
        if !IsObject(e)
            return ""
        for i, s in e["settings"] {
            path := PluginHost.SettingPath(e, s)
            switch s["type"] {
                case "bool": this.cfg.Set(path, this.Ctrl("psCheck:" i).Value ? 1 : 0)
                case "int": this.cfg.Set(path, Integer(Trim(this.Ctrl("psEdit:" i).Value)))
                case "secret":
                    v := Trim(this.Ctrl("psSecret:" i).Value)
                    if (v != "")
                        this.cfg.Set(path, v)
                    this.Ctrl("psSecret:" i).Value := ""
                default: this.cfg.Set(path, Trim(this.Ctrl("psEdit:" i).Value))
            }
        }
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
            this._ids["routeBtn:" name] := Theme.Button(g, "x560 y" y " w86 h28", "Record", ObjBindMethod(this, "_RouteBtn", name))
            this._ids["routeTest:" name] := Theme.Button(g, "x652 y" y " w62 h28", "Test", ObjBindMethod(this, "_RouteTestBtn", name))
            this._ids["routeReset:" name] := Theme.Button(g, "x720 y" y " w66 h28", "Reset", ObjBindMethod(this, "_RouteResetBtn", name), "quiet")
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
            Theme.SetText(this._routeStatus, I18n.F("{1}: no default recording to reset to.", name))
            return false
        }
        ; a routes.json that does not parse loads as empty: saving now would
        ; replace every recording with this one route (review)
        if (this.cfg.DataStatus("routes") = "bad") {
            Theme.SetText(this._routeStatus, I18n.F("{1}: data\routes.json does not parse; fix or restore it first (nothing changed).", name))
            return false
        }
        live := this.cfg.Data("routes")
        if (live is Map && live.Has("routes") && live["routes"] is Map)
            live := live["routes"]
        live[name] := Json.Parse(Json.Stringify(def[name]))
        this.cfg.SaveData("routes")
        this._RoutesLoad()
        Theme.SetText(this._routeStatus, I18n.F("{1}: reset to the default recording.", name))
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
            return IsObject(b) ? I18n.F("{1}, {2} steps", b.label, b.steps.Length) : I18n.T("not recorded")
        }
        e := r[name]
        steps := (e is Array) ? e : (e is Map && e.Has("steps") && e["steps"] is Array) ? e["steps"] : []
        if (steps.Length = 0)
            return I18n.T("not recorded")
        stamp := (e is Map && e.Has("_recorded")) ? "  (" RegExReplace(String(e["_recorded"]), "^\d{4}-") ")" : ""
        return I18n.F("{1} steps", steps.Length) stamp
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
            Theme.SetText(this._routeStatus, I18n.F("{1}: Test needs the running {2} app.", name, Brand.Name))
            return {ok: false, msg: "no app"}
        }
        Theme.SetText(this._routeStatus, I18n.F("{1}: testing... watch Roblox (F3 stops).", name))
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
        ; fake alerts (2026-11-16): to one picked webhook, never the routed ones
        this._Panel(204, 380, 396, 236, "Fake alerts (dev)", "The boss card and the rare aura alert go ONLY to the webhook you pick here, "
            . "marked [TEST], so your public channels never see them. They work with dry run on or off. "
            . "Fake disconnect needs the macro running: it closes Roblox and rejoins your private server, like after a crash.")
        Theme.Label(g, "x220 y414 w70 h20", "Send to", "body")
        dd := Theme.Dropdown(g, 292, 410, 200)
        this._ids["testHook"] := dd
        this._ids["testAlert:sinister"] := Theme.Button(g, "x220 y450 w176 h30", "Fake Sinister spawn", (*) => this.TestAlert("sinister"))
        this._ids["testAlert:aura"] := Theme.Button(g, "x404 y450 w176 h30", "Fake rare aura", (*) => this.TestAlert("aura"))
        this._ids["testAlert:disconnect"] := Theme.Button(g, "x220 y488 w176 h30", "Fake disconnect", (*) => this.TestAlert("disconnect"))
        this._ids["testAlertStatus"] := Theme.Label(g, "x220 y528 w364 h76", "", "muted")

        ; download counts (2026-11-16): only in the dev copy (a git checkout)
        if Updater.IsDevCopy(this.cfg.dir) {
            this._Panel(616, 152, 396, 136, "Downloads (dev)", "How many times each release was downloaded, from GitHub's public counters. "
                . "Nothing is sent from anyone's macro and no one is tracked. The dashboard's updater downloads the zip too, "
                . "so the newest release's number is about how many people installed or updated it. One person downloading twice counts twice.")
            this._ids["dlText"] := Theme.Label(g, "x632 y184 w364 h60", "Press Refresh.", "body")
            this._ids["dlRefresh"] := Theme.Button(g, "x632 y248 w110 h28", "Refresh", (*) => this.RefreshDownloads(), "quiet")
            ; dim screens (2026-11-25): the App dims while running (App._DimSync, ScreenDim)
            this._Panel(616, 304, 396, 140, "Dim screens (dev)", "Dims every monitor while the macro runs, so your room stays dark. "
                . "The macro's screen reads and recordings never see the dim.")
            this._ids["devDim"] := this._BoolField(632, 338, "Dim my screens while it runs", "Dev.dim", 0)
            this._ids["devDimPct"] := this._IntField(632, 376, "How dark", "Dev.dimPct", 95, "%", 170, 5)
        }
        p.onShow := ObjBindMethod(this, "_DevToolsShow")
    }

    ; the Downloads (dev) panel: GitHub's counts for [Update] repo
    _dlShown := false
    static DownloadsHttp := ""            ; tests: (url) -> body
    RefreshDownloads() {
        t := this.Ctrl("dlText")
        if !IsObject(t)
            return ""
        Theme.SetText(t, I18n.T("Asking GitHub..."))
        try {
            ; the public repo (a dev copy's settings usually have no [Update] repo,
            ; so it never updates itself)
            repo := Trim(String(this.cfg.Get("Update.repo", "")))
            r := Updater.FetchDownloads(Updater.ValidRepo(repo) ? repo : Brand.Repo, Dashboard.DownloadsHttp)
            msg := Updater.DownloadText(r) "`n(" FormatTime(, "HH:mm") ")"
        } catch Any as e
            msg := "Could not read the counts: " (e is Error ? e.Message : String(e))
        Theme.SetText(t, msg)
        return msg
    }

    ; Dev tools shown: the webhook list again (it may have changed), the
    ; download counts once per session (after the page painted)
    _DevToolsShow(*) {
        this._TestHooksLoad()
        if (IsObject(this.Ctrl("dlText")) && !this._dlShown) {
            this._dlShown := true
            SetTimer(() => this.RefreshDownloads(), -50)
        }
    }

    ; the "Send to" list: webhooks with a saved URL (names only)
    _TestHooksLoad(*) {
        dd := this.Ctrl("testHook")
        if !IsObject(dd)
            return
        keep := dd.Text
        dd.Delete()
        names := []
        for w in this.cfg.Webhooks()
            if (w.Has("name") && Trim(w["name"]) != "" && w.Has("url") && Trim(w["url"]) != "")
                names.Push(w["name"])
        if names.Length {
            dd.Add(names)
            idx := 1
            for i, n in names
                if (n = keep)
                    idx := i
            dd.Choose(idx)
        }
    }

    TestAlert(kind) {
        dd := this.Ctrl("testHook")
        hook := IsObject(dd) ? dd.Text : ""
        msg := this._cb.Has("testAlert") ? this._Fire("testAlert", kind, hook) : "Fake alerts need the running " Brand.Name " app."
        Theme.SetText(this.Ctrl("testAlertStatus"), String(msg))
        return msg
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
        Theme.Label(g, "x368 y230 w600 h20", I18n.F("Creator of {1}", Brand.Name), "muted")
        this._ids["credits.discord"] := Theme.Label(g, "x368 y256 w600 h20", "Discord: " Credits.Discord(), "body")
        ; the card id keeps the English title; the caption shows it translated
        parts := this._Panel(204, 344, 808, 80, "A message from " Credits.Name())
        Theme.SetText(parts[3], StrUpper(I18n.F("A message from {1}", Credits.Name())))
        this._ids["credits.message"] := Theme.Label(g, "x220 y372 w776 h40", Chr(0x201C) Credits.Message() Chr(0x201D), "body")
        this._Panel(204, 440, 808, 112, "Discord server")
        Theme.Label(g, "x220 y468 w776 h20", Credits.Server(), "muted")
        this._ids["credits.join"] := Theme.Button(g, "x220 y496 w180 h30", "Join the Discord", (*) => this._OpenDiscord(), "primary")
    }

    _OpenDiscord() {
        try Run(Brand.DiscordUrl)
    }

    ; ---- page: Profiles (Settings) ----------------------------------------------

    _PageProfiles(p) {
        g := this._gui
        this._Panel(204, 152, 396, 464, "One-click profiles", "Each button turns a few switches on or off and saves at once. "
            . "Potion dry run, webhooks, the server link and the Discord bot are never changed. Unsaved edits on other tabs are dropped.")
        for i, name in Profiles.Names {
            y := 186 + (i - 1) * 88
            this._ids["profile:" name] := Theme.Button(g, "x220 y" y " w180 h30", name, ObjBindMethod(this, "_ProfileBtn", name))
            Theme.Label(g, "x220 y" y + 36 " w364 h36", Profiles.Description(name), "muted")
        }
        this._ids["profileStatus"] := Theme.Label(g, "x220 y546 w364 h56", "", "muted")
        this._Panel(616, 152, 396, 272, "Share settings")
        Theme.Label(g, "x632 y184 w364 h100", "Export saves your settings in a file you can send to a friend. Webhooks, server links, "
            . "the bot token and Discord ids are left out.`n`nImport takes the settings from such a file. Your own webhooks, links and token stay.", "body", Theme.CardBg)
        this._ids["export"] := Theme.Button(g, "x632 y292 w164 h30", "Export settings", (*) => this.ExportSettings(), "primary")
        this._exportBtn := Theme.Button(g, "x806 y292 w100 h30", "Show it", (*) => this._ExportShow(), "quiet")
        this._ids["exportShow"] := this._exportBtn
        this._SetHidden(this._exportBtn, true)
        this._ids["import"] := Theme.Button(g, "x632 y330 w164 h30", "Import settings", (*) => this.ImportSettings())
        this._ids["shareStatus"] := Theme.Label(g, "x632 y368 w364 h48", "", "muted")
        this._exportPath := ""
        ; Move to another PC (lib\Backup.ahk): everything, secrets too
        this._Panel(616, 436, 396, 180, "Move to another PC", "Export everything puts every setting, your calibration, walks, quests, merchants, potions, biomes, "
            . "stats and your own themes in one file in the exports folder. On the other PC, open this tab and press Import everything. "
            . "Your current ones are saved in the exports folder first.")
        this._ids["backupWarn"] := Theme.Label(g, "x632 y466 w340 h40", "The file holds your server link, webhooks and bot token. Never share it.", "body", Theme.CardBg)
        this._ids["backupExport"] := Theme.Button(g, "x632 y512 w176 h30", "Export everything", (*) => this.ExportEverything(), "primary")
        this._ids["backupImport"] := Theme.Button(g, "x820 y512 w176 h30", "Import everything", (*) => this.ImportEverything())
        this._ids["backupStatus"] := Theme.Label(g, "x632 y550 w364 h60", "", "muted")
    }

    _ProfileBtn(name, *) => this.ApplyProfile(name)

    ; Asks, applies profile `name`, saves and reloads the other pages.
    ; -> the status text ("" when cancelled).
    ApplyProfile(name) {
        n := Profiles.Settings(name).Length
        if (this._confirmProfile.Call(I18n.F("Use {1}?", I18n.T(name)), I18n.T(Profiles.Description(name)) "`n`n"
            . I18n.F("Sets up to {1} switches and saves at once. Potion dry run, webhooks and links stay as they are. Unsaved edits on other tabs are dropped.", n)) != true)
            return ""
        try {
            changed := Profiles.Apply(this.cfg, name)
            this.cfg.Save()
        } catch Any as e {
            msg := I18n.F("Not applied: {1}", UiLogic.Scrub(e.Message, this._Secrets()))
            Theme.SetText(this._ids["profileStatus"], msg)
            return msg
        }
        this._ReloadOthers()
        one := changed.Length = 1
        msg := I18n.F(one ? "Applied: {1} ({2} setting changed)" : "Applied: {1} ({2} settings changed)", I18n.T(name), changed.Length)
        Theme.SetText(this._ids["profileStatus"], msg)
        this.Log("Profiles: Applied: " name " (" changed.Length " setting" (one ? "" : "s") " changed)")
        this._Fire("saved", "Profiles")
        return msg
    }

    ; Every page but Profiles shows the saved values again.
    _ReloadOthers() {
        for page in this._pages {
            if (page.name != "Profiles")
                this._LoadPage(page)
        }
        this._RefreshDry()
    }

    ; -> {ok, path, n, msg} (Profiles.Export)
    ExportSettings() {
        r := Profiles.Export(this.cfg)
        this._exportPath := r.ok ? r.path : ""
        this._SetHidden(this._exportBtn, !r.ok)
        Theme.SetText(this._ids["shareStatus"], r.msg)
        if r.ok
            this.Log("Profiles: " r.n " settings exported")
        return r
    }

    _ExportShow() {
        if (this._exportPath != "" && FileExist(this._exportPath))
            try Run('explorer.exe /select,"' this._exportPath '"')
    }

    _PickIni() {
        start := DirExist(this.cfg.dir "\exports") ? this.cfg.dir "\exports" : this.cfg.dir
        this._gui.Opt("+OwnDialogs")
        f := ""
        try f := FileSelect(1, start, "Import settings", "Settings (*.ini)")
        return f
    }

    ; path "" = ask with FileSelect. -> {ok, n, skipped, msg} ("" when cancelled)
    ImportSettings(path := "") {
        if (path = "")
            path := this._pickImport.Call()
        if (path = "")
            return ""
        r := Profiles.Import(this.cfg, path)
        if r.ok {
            try {
                this.cfg.Save()
            } catch Any as e {
                r := {ok: 0, n: 0, skipped: r.skipped, msg: I18n.F("Not imported: {1}", UiLogic.Scrub(e.Message, this._Secrets()))}
            }
        }
        if r.ok {
            this._ReloadOthers()
            this.Log("Profiles: " r.msg)
            this._Fire("saved", "Profiles")
        }
        Theme.SetText(this._ids["shareStatus"], r.msg)
        return r
    }

    ; ---- Move to another PC (lib\Backup.ahk) ----

    ; Everything into exports\moontide_backup_<stamp>.json, shown in
    ; Explorer. -> Backup.Export's result. Only counts are logged.
    ExportEverything() {
        this._Fire("backupFlush")          ; the App writes its day counters first
        r := Backup.Export(this.cfg.dir)
        Theme.SetText(this._ids["backupStatus"], r.msg)
        if r.ok {
            this.Log(Backup.LogLine("exported", r))
            try this._reveal.Call(r.path)
        }
        return r
    }

    _PickBackupFile() {
        start := DirExist(this.cfg.dir "\exports") ? this.cfg.dir "\exports" : this.cfg.dir
        this._gui.Opt("+OwnDialogs")
        f := ""
        try f := FileSelect(1, start, I18n.T("Import everything"), I18n.T("Moontide backup") " (*.json)")
        return f
    }

    ; path "" = ask. Refused while the macro runs (or records / tests a
    ; route). Checks the file, asks, saves the current state, writes, reloads
    ; the settings and every page, then the App restarts the macro so every
    ; part (theme, hotkeys, tasks) starts from the new files.
    ; -> Backup's result, {ok: 0, msg} when refused, "" when cancelled.
    ImportEverything(path := "") {
        st := this._ids["backupStatus"]
        busy := this._Fire("backupBusy")
        if (busy != "" && busy != 0) {
            msg := I18n.T("Stop the macro first (F3), then import.")
            Theme.SetText(st, msg)
            return {ok: 0, msg: msg}
        }
        if (path = "")
            path := this._pickBackup.Call()
        if (path = "")
            return ""
        r := Backup.Read(path)
        if !r.ok {
            Theme.SetText(st, r.msg)
            this.Log("Backup: import refused (the file did not pass the checks)")
            return r
        }
        body := I18n.T("This replaces your settings, calibration, walks, quests, merchants, potions, biomes and stats with the file's, and adds its themes. Your current ones are saved in the exports folder first. Only import your own backup.")
        if (r.screenNote != "")
            body .= "`n`n" r.screenNote
        if (this._confirmBackup.Call(I18n.T("Import everything?"), body) != true)
            return ""
        res := Backup.ImportData(this.cfg.dir, r.data)
        if !res.ok {
            Theme.SetText(st, res.msg)
            this.Log("Backup: import failed" (res.HasOwnProp("beforeName") ? ", the state before it is in exports\" res.beforeName : ""))
            try this.cfg.Reload()
            this._ReloadOthers()
            return res
        }
        try this.cfg.Reload()
        this._ReloadOthers()
        ; (a screen-size note was in the question already; the log keeps it too)
        Theme.SetText(st, res.msg)
        this.Log(Backup.LogLine("imported", res) ", the state before it is in exports\" res.beforeName)
        if (res.screenNote != "")
            this.Log("Backup: the backup was made on another screen size or scale; calibration may need redoing (Help > Check & help > Test my calibration)")
        this._Fire("saved", "Profiles")
        this._Fire("backupImported")
        return res
    }

    ; ---- page: Log --------------------------------------------------------------

    _PageLog(p) {
        g := this._gui
        this._Panel(204, 152, 808, 464)
        this._logEdit := Theme.Edit(g, 216, 164, 784, 440, "", "Multi ReadOnly -WantReturn VScroll")
        n0 := this._FixedBar()
        Theme.Button(g, "x204 y628 w100 h30", "Clear", (*) => (this._logBuf.Clear(), this._FlushLog()), "quiet")
        Theme.Button(g, "x312 y628 w100 h30", "Copy", (*) => (A_Clipboard := this._logBuf.Text()))
        this._logCount := Theme.Label(g, "x612 y634 w400 h20 Right", "", "muted")
        this._FixedBar(n0)
    }
}
