#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\Brand.ahk
#Include %A_LineFile%\..\Config.ahk
#Include %A_LineFile%\..\Scheduler.ahk
#Include %A_LineFile%\..\LogWatch.ahk
#Include %A_LineFile%\..\Webhook.ahk
#Include %A_LineFile%\..\Screenshot.ahk
#Include %A_LineFile%\..\Roblox.ahk
#Include %A_LineFile%\..\Input.ahk
#Include %A_LineFile%\..\Calibrate.ahk
#Include %A_LineFile%\..\PotionSafety.ahk
#Include %A_LineFile%\..\BiomeEvents.ahk
#Include %A_LineFile%\..\Clip.ahk
#Include %A_LineFile%\..\ChatWatch.ahk
#Include %A_LineFile%\..\RouteRecorder.ahk
#Include %A_LineFile%\..\tasks\Fishing.ahk
#Include %A_LineFile%\..\tasks\Sell.ahk
#Include %A_LineFile%\..\tasks\Craft.ahk
#Include %A_LineFile%\..\tasks\Quests.ahk
#Include %A_LineFile%\..\tasks\DailyQuests.ahk
#Include %A_LineFile%\..\tasks\BiomeItems.ahk
#Include %A_LineFile%\..\tasks\InvFind.ahk
#Include %A_LineFile%\..\tasks\Obby.ahk
#Include %A_LineFile%\..\tasks\Minions.ahk
#Include %A_LineFile%\..\tasks\MemoryMatch.ahk
#Include %A_LineFile%\..\tasks\Limbo.ahk
#Include %A_LineFile%\..\tasks\Merchant.ahk
#Include %A_LineFile%\..\tasks\Recovery.ahk
#Include %A_LineFile%\..\tasks\Potions.ahk
#Include %A_LineFile%\..\Updater.ahk
#Include %A_LineFile%\..\Stats.ahk
#Include %A_LineFile%\..\Schedule.ahk
#Include %A_LineFile%\..\DailySummary.ahk
#Include %A_LineFile%\..\Remote.ahk
#Include %A_LineFile%\..\ClockWatch.ahk
#Include %A_LineFile%\..\SetupCheck.ahk
#Include %A_LineFile%\..\LogBundle.ahk
#Include %A_LineFile%\..\ui\Dashboard.ahk
#Include %A_LineFile%\..\ui\Overlay.ahk
#Include %A_LineFile%\..\ui\Wizard.ahk
#Include %A_LineFile%\..\FixIt.ahk
#Include %A_LineFile%\..\ui\FixCard.ahk
#Include %A_LineFile%\..\ui\WhatsNew.ahk
; ---------------------------------------------------------------------------
; App: wires every module into the running macro (Task 14b). Vesper.ahk only
; calls App.Main(A_ScriptDir, A_Args).
;
;   app := App(deps)     deps Map; only cfg is required. Every other key is a
;                        test seam (default = the real module):
;     cfg, root (repo dir, absolute), now () -> ms, state (SchedState),
;     ctx (SchedCtx), roblox (Hwnd/ClientOk/Focus), clip (Clip),
;     input (Input: ReleaseAll), calibrate (Calibrate), wh (Webhook),
;     logWatch (LogWatch), biomeEvents, chatWatch ("" = none),
;     tasks (Map name -> task; when given, ONLY these are used),
;     safetyFactory () -> PotionSafety, potionsFactory (safety) -> PotionsTask,
;     ui (Array of objects with Log/SetStatus; default built by Boot),
;     launch (fn) -> runs fn in a new thread (default SetTimer(fn, -1)),
;     timer (fn, ms) (default SetTimer; ms 0 = off), shotFn / soundFn
;     (passed to BiomeEvents).
;   START ANNOUNCEMENT: each Start sends ONE embed (title Emoji.Moon + Brand.Name, "## Macro started" + fields) to every
;   ENABLED webhook (Webhook.Broadcast: event boxes ignored, never a mention
;   or @everyone) listing what will run (App.StartFields) and the Discord
;   invite. It replaces the old `startstop` start message (no duplicates);
;   the stop message is unchanged.
;   app.OnTestWebhook(i)  Dashboard Webhooks "Test": one message to saved
;                        webhook i only; returns scrubbed status text.
;   app.Boot(mode)       Screenshot.Cleanup, UI, Calibrate.Use(<root>\data\
;                        calibration.json, cfg), Clip.Setup, OnExit hook.
;                        mode "normal" shows the windows; "hidden" /
;                        "offscreen" are for tools\app_smoke.ahk only.
;   app.InstallHotkeys() F1 start, F2 pause/resume, F3 stop ([Hotkeys] keys,
;                        F1-F24 only, else the defaults).
;
; THREADS AND TIMERS
;   One repeating timer: Tick every 250 ms, only between Start and the end
;   of Stop. Each Start after the first makes a fresh LogWatch (silent
;   backfill), so a restart never alerts on biome lines from before. LogWatch is polled inside Tick at most once per second. A task
;   is started with a one-shot SetTimer(fn, -1) so it runs in its own thread
;   and blocks there (tasks Sleep in small steps); the 250 ms tick keeps
;   interrupting it, so Flush, LogWatch, Recovery.CanRun (stuck clock needs
;   gaps < 2 min) and the preempt check keep running during long tasks.
;   Re-entrancy: _running is set at launch and cleared in the task's
;   finally; while it is set no task is started. PollLogs has its own guard
;   (the PotionsTask poll callback and the tick can both call it).
;
; PER TASK  (thread started by _Launch)
;   ctx.ClearPreempt -> state.busy := name -> task.Run(ctx) -> finally:
;   busy := "", Scheduler.MarkRun, _running := "", deferred potion rebuild.
;   A throw is logged + `errors` webhook, then no task starts for
;   ErrorHoldMs (no hot loop on a broken task).
; PREEMPT: while a task runs, each tick asks Scheduler.Next; a runnable task
;   with a lower priority number -> ctx.RequestPreempt() (the task returns at
;   its next checkpoint).
; WINDOW (spec 7): Start / Resume with Roblox missing or not fullscreen
;   (any resolution; windowed / minimized are not supported) -> paused with
;   that status (F2 resumes after a re-check). A fullscreen size other than
;   the verified 2560x1440 runs, with a status note and a "Display:" log line.
;   During any task except recovery (checked every tick): not fullscreen
;   -> pause; window gone -> preempt for recovery (recovery off -> pause
;   "Roblox not found"); Roblox not the active window (alt-tab) -> pause
;   "Roblox lost focus". Every pause also releases held keys.
;   Between tasks: window missing -> only RecoveryTask may run (rejoin).
;   Window ok -> Roblox.Focus FIRST (merchant, quests and potions do not
;   focus it themselves; focus fails -> wait), then re-check started / not
;   stopped / not paused (hotkeys can fire during WinWaitActive), ChatWatch,
;   re-check, and only then pick + launch. _Launch also swaps a replaced
;   PotionsTask for the current one (rebuild race).
; LOG EVENTS: biome/aura -> BiomeEvents.Handle (it ignores non-live except
;   for state); merchant + live -> MerchantTask.OnLogEvent.
; CHAT: ChatWatch.Check (it moves the mouse) only between tasks, running,
;   not paused, window ok, merchant.enabled, NOT during a rare biome. It
;   throttles itself to merchant.chatPollSec. onFound -> MerchantTask.Notify.
;   A chat a task hid (ChatGuard: below 1440p it lies over clicks) is shown
;   again after the task (_Tidy) and before each chat read.
;   Fishing runs until a sell, so while it runs the tick sets state.chatDue
;   every merchant.chatPollSec (chat watching on, chat_rect calibrated, no
;   rare biome); FishingTask returns after its current catch, the chat is
;   read between tasks and fishing starts again.
; TICK GUARD: the whole Tick body runs in try/catch; an error is logged
;   (scrubbed) + `errors` webhook (once per distinct text until the next
;   Resume) and the macro is PAUSED (keys released): a broken CanRun can
;   never leave a task sending input with a dead scheduler.
; TEST EVENTS (Dashboard > Tools, dev only): FakeEvent("biome" | "merchant")
;   routes a synthetic LIVE event (fake GLITCHED biome / Mari arrival, ts
;   "TEST-...") through RouteEvent. REFUSED unless General.dryRun = 1, the
;   macro is started and no real rare biome is active. Webhooks sent while
;   routing it get "[TEST] " in the title. PotionsTask never clicks Use for
;   a TEST- event outside dry run. After the fake biome's potion pass, the
;   previous biome is restored with a silent (non-live) event.
; ROUTES: OnRecordRoute(name) (Dashboard > Tools) stops the macro, respawns
;   the player with the SAME Input.ResetToSpawn playback uses (same spot,
;   camera re-aimed), then runs RouteRecorder (watches keys only) and reloads
;   cfg routes. Without Roblox open/fullscreen/focused it records without the
;   respawn (logged). dep "recordRespawn" (ctx) -> bool.
;   OnTestRoute(name) (Tools "Test") stops the macro, needs Roblox open,
;   fullscreen and focused, then respawns, walks the route and presses its
;   interaction key (E / F) so the user sees whether the board / cauldron
;   opens. F3 or Roblox losing focus stops it. dep "walkRoute"
;   (steps, key, ctx) -> "" ok | reason.
; POTIONS: ONE PotionSafety (absolute PotionsTask.DefaultUsagePath()).
;   "potionsChanged" rebuilds PotionSafety + PotionsTask unless the potion
;   task is running (then deferred until it ends). A pending, not yet run
;   event is re-queued on the new task (it re-checks everything). A failed
;   build leaves NO potion task (BiomeEvents logs "could not queue").
;   Rebuild only when the serialized potions.json + biomes.json changed;
;   the new PotionSafety gets TransferRunCountsFrom(old) so per-run counts,
;   open events and a halt survive (per-biome / per-day are in the file).
; STOP (F3 / buttons): ctx.Stop (potion use stops before its next click),
;   Clip.CancelAll, Input.ReleaseAll, `startstop` webhook (F2 pause also
;   releases keys and cancels clips); the tick runs on
;   until the task thread ended, then Webhook.Drain and the timer stops.
; EXIT: OnExit(cb) ADDS a callback (verified: callbacks run in registration
;   order while each returns 0), so Input's own ReleaseAll hook stays. Ours
;   sends the stop webhook if running, CancelAll, ReleaseAll, Drain,
;   Screenshot.Cleanup and returns 0.
; ---------------------------------------------------------------------------

class AppPotionsProxy {
    ; BiomeEvents holds this; the real PotionsTask can be rebuilt behind it.
    __New(app) {
        this._app := app
        this.last := ""
    }
    Queue(biome, ts) {
        this.last := {biome: String(biome), ts: String(ts)}
        p := this._app.potions
        if !IsObject(p)
            throw Error("potion task not available")
        return p.Queue(biome, ts)
    }
}

; Webhook wrapper: adds "[TEST] " to titles while App routes a fake test
; event; everything else is passed through unchanged.
class AppTagWh {
    __New(app, inner) {
        this._app := app
        this._inner := inner
    }
    Send(ev, title, desc, color := 0, opts := "") {
        if this._app._testTag {
            title := "[TEST] " title
            ; fake events never mention anyone and never ping @everyone
            opts := {screenshot: Webhook._Opt(opts, "screenshot", ""), fields: Webhook._Opt(opts, "fields", "")}
        }
        return this._inner.Send(ev, title, desc, color, opts)
    }
    __Call(name, params) => this._inner.%name%(params*)
}

class App {
    static TickMs := 250
    static LogPollMs := 1000
    static ErrorHoldMs := 5000
    static SkipHoldMaxMs := 120000   ; longest wait after repeated shift lock skips
    static SkipRejoinAt := 3         ; that many skips in a row: rejoin (RecoveryTask.RequestUnlock)
    ; tasks that leave you away from the fishing spot: the sell trip (back
    ; to the spot through the Fisher) runs next when fishing is on
    static MovesAway := Map("quests", 1, "obby", 1, "minions", 1, "merchant", 1, "memorymatch", 1)
    static DrainMs := 5000
    static Order := ["potions", "recovery", "merchant", "craft", "autocal", "biomeitems", "quests", "obby", "memorymatch", "dailyquests", "minions", "sell", "limbo", "fishing"]
    static KeyNames := ["start", "pause", "stop"]
    static KeyDefaults := Map("start", "F1", "pause", "F2", "stop", "F3")
    static Msg := Map(
        "missing", ["Roblox not found", "Roblox not found. Open Roblox fullscreen, then press F2."],
        "notfs", ["Roblox window not usable", "The Roblox window can't be used (minimized, too small or partly off the screen). Restore it or make it fullscreen (F11), then press F2."],
        "unfocused", ["Roblox lost focus", "Roblox is not the active window (alt-tab?). Input stopped. Click into Roblox, then press F2."],
        "notprivate", ["Not in your private server", "You are not in your private server and recovery is off, so the macro does not rejoin it. Join your private server, then press F2."])

    ; Absolute repo dir (lib\App.ahk -> repo).
    static DefaultRoot() => RegExReplace(A_LineFile, "\\lib\\[^\\]+$")

    static _Dep(d, k, def := "") => d.Has(k) ? d[k] : def

    __New(deps) {
        d := (deps is Map) ? deps : Map()
        if !d.Has("cfg")
            throw ValueError("App: cfg is required")
        this.cfg := d["cfg"]
        ; Windowed: Yes / No (Help > Calibrate): a window is used only with Yes
        try Roblox.AllowWindowed := (this.cfg.Get("General.windowed", 0) = 1)
        try Calibrate.ScaleOverride := Calibrate.ScaleFromText(this.cfg.Get("General.displayScale", 0))   ; Scale: Auto / picked
        this.root := App._Dep(d, "root", App.DefaultRoot())
        try ChatGuard.FlagPath := this.root "\logs\chat_hidden.flag"
        this.nowFn := App._Dep(d, "now", () => A_TickCount)
        this._frontFn := App._Dep(d, "front", "")     ; () -> exe in front (focus pause note); "" = the real one
        this._refocusAt := []                        ; _Refocus times (ms)
        this.fixit := FixIt()                        ; fix-it cards (idea 10): rules over the log
        this._fixOn := false                         ; cards only in the real app (Boot), never in tests
        this._fixCard := ""
        this._hiResOn := App._Dep(d, "hiRes", true)  ; Start / Stop hold the 1 ms timer (tests: off)
        ; v1.6 services (Boot "normal" makes the real ones; tests may pass them)
        this.daily := App._Dep(d, "daily", "")       ; DailyStats: today / this run / 30 days
        this.sched := App._Dep(d, "schedule", "")    ; RunSchedule
        this.remote := ""                            ; DiscordRemote while Remote.enabled
        this._wizard := ""
        this._wizLang := ""          ; a language picked in the setup wizard (restart on close)
        this._whatsNew := ""
        this._schedStarting := false
        this._svc := Map("sched", 0, "sum", 0, "save", 0, "stats", 0, "hist", 0)
        this._svcErr := Map()
        this.state := App._Dep(d, "state", "")
        if !IsObject(this.state)
            this.state := SchedState()
        this.ctx := App._Dep(d, "ctx", "")
        if !IsObject(this.ctx)
            this.ctx := SchedCtx()
        this.roblox := App._Dep(d, "roblox", Roblox)
        this.clip := App._Dep(d, "clip", Clip)
        this.input := App._Dep(d, "input", Input)
        this.calibrate := App._Dep(d, "calibrate", Calibrate)
        this._recordFn := App._Dep(d, "recordRoute", (name, path) => RouteRecorder.Run(name, path))
        this._walkFn := App._Dep(d, "walkRoute", ObjBindMethod(this, "_WalkRoute"))
        this._walkName := ""         ; route OnTestRoute is walking (for _WalkRoute)
        this._recRespawnFn := App._Dep(d, "recordRespawn", (ctx) => this.input.ResetToSpawn(ctx))
        this._sleepFn := App._Dep(d, "sleep", (ms) => Sleep(ms))
        this._testCtx := ""
        this._toolBusy := false      ; a route Record / Test or Calibrate is running (Start refused)
        this.launchFn := App._Dep(d, "launch", (fn) => SetTimer(fn, -1))
        this.timerFn := App._Dep(d, "timer", (fn, ms) => SetTimer(fn, ms))
        this._creditsFn := App._Dep(d, "creditsVerify", () => Credits.Verify())     ; NO root: the compiled-in values
        this._splashFn := App._Dep(d, "splash", "")
        this._uiGiven := d.Has("ui")
        this.ui := this._uiGiven ? d["ui"] : []
        this.dash := ""
        this.overlay := ""
        this._updater := App._Dep(d, "updater", "")
        this._early := []
        this._logFn := ObjBindMethod(this, "Log")
        this._tickFn := ObjBindMethod(this, "Tick")

        ; run state
        this._started := false
        this._idle := false          ; this run is idle mode (General.idleMode at Start): reads only
        this._running := ""
        this._startedAt := 0
        this._uptime := 0
        this._loops := 0
        this._lastLoops := 0
        this._lastPoll := ""
        this._pauseReason := ""
        this._note := ""
        this._limboTrip := false     ; App._Pick: the walk to fishing asked for since the last time in Limbo
        this._limboChecked := false  ; inLimbo restored from the flag after Start (first poll)
        this._limboMarked := false   ; logs\limbo_session.flag written for the current inLimbo
        this._limboFlagPath := ""        ; that file ("" = <root>\logs\limbo_session.flag)
        this._display := ""          ; "Roblox 1280x1024 (x0.5): not tested at this size yet ...
        this._displayLogged := ""
        this._holdUntil := 0
        this._polling := false
        this._rebuildPending := false
        this._timerOn := false
        this._problems := Map()

        this._testTag := false       ; true while a fake test event is routed
        this._fakeRestore := ""      ; {biome, ts} after a fake rare biome
        this._lastChat := ""         ; ms of the last chat check
        this._joinKind := ""         ; the last join's kind (LogWatch): "private" / "other" / ""
        this.wh := AppTagWh(this, d.Has("wh") ? d["wh"] : Webhook(this.cfg, this._logFn))
        ; LogWatch is re-created on every Start after the first, so a restart
        ; backfills silently (live=false) instead of alerting on old lines.
        this.lwFactory := App._Dep(d, "logWatchFactory", "")
        if !IsObject(this.lwFactory) {
            given := App._Dep(d, "logWatch", "")
            this.lwFactory := IsObject(given) ? (() => given) : (() => LogWatch())
        }
        this.lw := this.lwFactory.Call()
        this._everStarted := false

        ; one boss report for the chat line and the hunt's fight (no double
        ; message for one spawn); made before the tasks (MinionsTask takes it)
        this.sinister := d.Has("sinister") ? d["sinister"]
            : SinisterReport({webhook: this.wh, cfg: this.cfg, log: this._logFn, ghost: () => this._GhostNow()})
        ; the boss without the chat: the biome clock stops while it lives
        this.clock := d.Has("clock") ? d["clock"] : ClockWatch({report: this.sinister, log: this._logFn})
        ; tasks
        this._taskMap := Map()
        if d.Has("tasks") {
            for name, t in d["tasks"]
                this._taskMap[name] := t
        } else {
            for name in ["recovery", "merchant", "craft", "autocal", "biomeitems", "quests", "obby", "memorymatch", "dailyquests", "minions", "sell", "limbo", "fishing"] {
                t := this._DefaultTask(name)
                if IsObject(t)
                    this._taskMap[name] := t
            }
        }
        if d.Has("tidyScreen")
            this._tidyScr := d["tidyScreen"]
        this.merchant := this._taskMap.Has("merchant") ? this._taskMap["merchant"] : ""
        this.recovery := this._taskMap.Has("recovery") ? this._taskMap["recovery"] : ""

        ; potions: one PotionSafety, rebuilt on potionsChanged
        this.safetyFactory := App._Dep(d, "safetyFactory", "")
        if !IsObject(this.safetyFactory)
            this.safetyFactory := () => PotionSafety(this.cfg.Data("potions"), PotionsTask.DefaultUsagePath())
        this.potionsFactory := App._Dep(d, "potionsFactory", "")
        if !IsObject(this.potionsFactory)
            this.potionsFactory := (safety) => PotionsTask(Map("cfg", this.cfg, "safety", safety, "state", this.state
                , "wh", this.wh, "log", this._logFn, "poll", ObjBindMethod(this, "PollLogs")))
        this.potions := ""
        this._safety := ""
        this._snap := ""
        this._proxy := AppPotionsProxy(this)
        this._BuildPotions()
        this._tasks := this._TaskList()

        ; log consumers
        if d.Has("biomeEvents") {
            this.be := d["biomeEvents"]
        } else {
            bd := Map("cfg", this.cfg, "state", this.state, "wh", this.wh, "potions", this._proxy
                , "log", this._logFn, "clip", this.clip)
            if (IsObject(this.cfg) && this.cfg.HasProp("dataDir"))   ; biome changes while stopped
                bd["lastFile"] := this.cfg.dataDir "\last_biome.txt"
            if (IsObject(this.cfg) && this.cfg.HasProp("dataDir"))   ; auras you own: no clip on equip
                bd["hadFile"] := this.cfg.dataDir "\auras_had.txt"
            for k in ["shotFn", "soundFn", "hadLogDir"]
                if d.Has(k)
                    bd[k] := d[k]
            this.be := BiomeEvents(bd)
        }
        if d.Has("chatWatch") {
            this.chat := d["chatWatch"]
        } else {
            this.chat := ChatWatch({cfg: this.cfg, webhook: this.wh, log: this._logFn
                , onFound: ObjBindMethod(this, "_OnChatMerchant"), onBoss: ObjBindMethod(this, "_OnChatBoss"), startOld: true})
        }
    }

    Now() => (this.nowFn).Call()
    TaskRunning() => IsObject(this._running)
    IsStarted() => this._started

    _DefaultTask(name) {
        cfg := this.cfg
        ; tasks that walk away skip their last respawn when the sell trip back
        ; to the fishing spot comes next and respawns anyway (speed, 2026-11-17)
        ra := () => !(this.cfg.Get("General.fishing", 1) && this._taskMap.Has("sell"))
        try {
            switch name {
                case "fishing": return FishingTask(cfg, this.state, {log: this._logFn})
                case "sell": return SellTask(cfg, this.state, {log: this._logFn, afterSell: (ctx) => this._AfterSell(ctx)
                    , stuck: (msg) => this._Error("Stuck: " msg), cal: Calibrate})
                case "craft": return CraftTask({cfg: cfg, webhook: this.wh, log: this._logFn})
                case "quests": return QuestsTask({cfg: cfg, webhook: this.wh, log: this._logFn, cards: (c) => this._ClearCards(c), respawnAfter: ra})
                case "dailyquests": return DailyQuestsTask({cfg: cfg, webhook: this.wh, log: this._logFn
                    , potionQuest: (p, n) => this._PotionQuest(p, n)})
                case "biomeitems": return BiomeItemsTask({cfg: cfg, webhook: this.wh, log: this._logFn})
                ; one look at the inventory when one of its steps is missing or
                ; it failed its own read (never with a full calibration that works)
                case "autocal": return InvFindTask({cfg: cfg, webhook: this.wh, log: this._logFn})
                case "obby": return ObbyTask({cfg: cfg, webhook: this.wh, log: this._logFn, aura: () => this._AuraNow()
                    , hintPath: App.DefaultRoot() "\data\aura_hints.json"
                    , respawnAfter: ra})
                case "minions": return MinionsTask({cfg: cfg, webhook: this.wh, log: this._logFn, aura: () => this._AuraNow()
                    , hintPath: App.DefaultRoot() "\data\aura_hints.json"
                    , biome: () => this._BiomeNow(), ghost: () => this._GhostNow(), sinister: this.sinister, state: this.state})
                case "memorymatch": return MemoryMatchTask({cfg: cfg, webhook: this.wh, log: this._logFn, respawnAfter: ra})
                case "merchant": return MerchantTask({cfg: cfg, webhook: this.wh, log: this._logFn, respawnAfter: ra})
                case "recovery": return RecoveryTask({cfg: cfg, webhook: this.wh, log: this._logFn})
                case "limbo": return LimboTask({cfg: cfg, webhook: this.wh, log: this._logFn
                    , toIsland: (ctx) => this._ToIsland(ctx)})
            }
        } catch Any as e {
            this._Error(StrTitle(name) " task disabled: " App._ErrText(e))
        }
        return ""
    }

    ; LimboTask leaving THE LIMBO: the recovery task rejoins the private server.
    _ToIsland(ctx) {
        r := this.recovery
        if !(IsObject(r) && HasMethod(r, "ReturnToIsland")) {
            this.Log("Limbo: no recovery task to rejoin with; staying in Limbo")
            return false
        }
        return r.ReturnToIsland(ctx)
    }

    ; Sell is at the fisher: buy in the same visit when a buy is due.
    _AfterSell(ctx) {
        c := this._taskMap.Has("craft") ? this._taskMap["craft"] : ""
        if !(IsObject(c) && HasMethod(c, "BuyDue") && HasMethod(c, "BuyHere"))
            return 0
        return c.BuyDue() ? c.BuyHere(ctx) : 0
    }

    _TaskList() {
        out := []
        for name in App.Order {
            if (name = "potions") {
                if IsObject(this.potions)
                    out.Push(this.potions)
            } else if this._taskMap.Has(name)
                out.Push(this._taskMap[name])
        }
        return out
    }

    ; ---- potions --------------------------------------------------------------

    ; old = the previous PotionSafety (rebuild) or "" (first build).
    _BuildPotions(old := "") {
        this._snap := this._PotionsSnapshot()
        try {
            safety := this.safetyFactory.Call()
            ; keep per-run caps across settings rebuilds (fails closed: a
            ; transfer error leaves no potion task)
            if (IsObject(old) && HasMethod(safety, "TransferRunCountsFrom"))
                safety.TransferRunCountsFrom(old)
            this.potions := this.potionsFactory.Call(safety)
            this._safety := safety
            return true
        } catch Any as e {
            this.potions := ""
            this._Error("Potions: potion safety could not load (" App._ErrText(e) "); potion use is OFF")
            return false
        }
    }

    ; Serialized potions.json + biomes.json (rebuild only when it changed).
    _PotionsSnapshot() {
        s := ""
        for name in ["potions", "biomes"] {
            try s .= name "=" Json.Stringify(this.cfg.Data(name), 0) "`n"
            catch
                s .= name "=?" A_TickCount "`n"     ; unreadable -> always "changed"
        }
        return s
    }

    _PotionsBusy() {
        if (IsObject(this._running) && this._running.name = "potions")
            return true
        return PotionsTask.busy ? true : false
    }

    ; Dashboard "potionsChanged".
    OnPotionsChanged() {
        if this._PotionsBusy() {
            this._rebuildPending := true
            this.Log("Potions: new settings apply when the current potion task ends")
            return false
        }
        this._RebuildPotions()
        return true
    }

    _MaybeRebuild() {
        if (this._rebuildPending && !this._PotionsBusy())
            this._RebuildPotions()
    }

    _RebuildPotions() {
        this._rebuildPending := false
        if (IsObject(this.potions) && this._PotionsSnapshot() == this._snap)
            return false                        ; Save without changes: keep the instance
        old := this.potions
        hadPending := false
        try hadPending := IsObject(old) && old.CanRun(this.state)
        ok := this._BuildPotions(this._safety)
        this._tasks := this._TaskList()
        if ok
            this.Log("Potions: settings reloaded")
        last := this._proxy.last
        if (ok && hadPending && IsObject(last)) {
            try this.potions.Queue(last.biome, last.ts)
        }
    }

    ; ---- control (hotkeys, buttons) ------------------------------------------

    Start() {
        if this._started {
            if this.ctx.IsPaused()
                return this.Resume()
            return false
        }
        if IsObject(this._running) {
            this.Log("Still stopping the last task; press Start again in a moment")
            return false
        }
        ; a route Record / Test / Calibrate holds keys in the dashboard's
        ; thread: a task started now would run with them down (review)
        if this._toolBusy {
            this.Log("Finish the route record / test / calibration first (F3 stops it)")
            return false
        }
        ; the biome comes again from the log's backfill: a rare biome kept
        ; from the last session blocked tasks for minutes after it ended
        this.state.rareActive := false
        this.state.rareTs := ""
        this.state.biome := ""
        ; a ghost server is decided again from the log at the first poll
        ; (live 2026-11-12: a rejoin stopped by F3 left it set, and the next
        ; Start closed the healthy private server again)
        this.state.ghost := false
        if this._everStarted {
            try {
                this.lw := this.lwFactory.Call()
            } catch Any as e {
                this._Error("LogWatch: could not restart (" App._ErrText(e) ")")
            }
        }
        this._everStarted := true
        this.ctx.Reset()
        this._idle := this._IdleOn()            ; idle mode: reads only, no input (see _IdleTick)
        try this.fixit.Reset()                  ; a new run: cards may show again
        this._StuckUiStart()                    ; package B: last run's fix card and stuck-UI streak gone
        if (this._fixOn && !this._idle)         ; windowed: the overlay off the game
            try this._WindowedStart()
        if this._fixOn                          ; the real app: the preset that fits Roblox's screen now
            try this._UseCalibration()
        this._started := true
        ; speed (2026-11-13): 1 ms timer while running, so every wait and
        ; screen poll lands on time (Windows' default 15.6 ms ticks rounded
        ; each one up; counted with the walks' and hunts' own requests)
        if this._hiResOn
            try Input.HiRes(true)
        this._startedAt := this.Now()
        this._uptime := 0
        this._loops := 0
        this._lastLoops := this.state.fishLoops
        this.state.stats := Map()          ; this session's counters (stop summary)
        if IsObject(this.daily)
            try this.daily.StartSession()
        this._pauseReason := ""
        this._note := ""
        this._holdUntil := 0
        this._lastPoll := ""
        this._lastChat := ""
        this.state.chatDue := false
        ; Quests first, then one trip: Sell (reset to spawn, walk to the
        ; fisher, sell, buy in the same visit, walk to the fishing spot), then
        ; fishing. Quests / biome items (priority 5) run before Sell (6); craft
        ; waits for the trip (state.startSell). Only with a Sell task: without
        ; one the flag would block craft forever.
        this.state.startSell := false
        this.state.needRepath := false          ; a re-path left from the last run is not this one's
        this.state.repathStreak := 0
        this.state.limboHeld := false
        this._limboChecked := false             ; the first poll restores inLimbo (_LimboRestore)
        this._limboTrip := false
        if (this._taskMap.Has("merchant") && HasMethod(this._taskMap["merchant"], "Reset"))
            this._taskMap["merchant"].Reset()   ; a merchant announced before Stop is long gone
        if (IsObject(this.recovery) && HasMethod(this.recovery, "Reset"))
            try this.recovery.Reset()           ; a disconnect / hold from the last run is not this one's
        this.state.limboMode := this._LimboMode()
        if this._idle {
            this.Log(App.IdleStartMsg)
        } else if this.state.limboMode {
            this.Log("Limbo is on: using the Portable Crack and waiting for Eden (fishing, selling, crafting, quests and merchants are off;"
                . " when the crack cannot be used they run until the next try)")
        } else if (this.cfg.Get("General.repathOnStart", 1) && FishLogic.TripWanted(this.cfg) && this._taskMap.Has("sell")) {
            ; (fishing and crafting off: no trip; it walked there and idled, 2026-10-31)
            this.state.needRepath := true
            this.state.startSell := true
            this.Log("Quests first, then sell + buy at the Fisher, then fishing (start)")
        }
        qi :=this.cfg.Get("General.questIntervalMin", 30)
        if (IsInteger(qi) && qi > 0)
            this.state.questIntervalMs := qi * 60000
        this.state.obbyIntervalMs := Sched.ObbyIntervalFrom(this.cfg.Get("Obby.intervalMin", 10))
        dry := this._DryRun()
        this.Log("Started. Potion dry run " (dry ? "ON" : "OFF"))
        if (IsObject(this.chat) && HasMethod(this.chat, "Rebase"))
            this.chat.Rebase()                  ; a merchant line already in the chat is old
        ; One start message per ENABLED webhook (whatever its event boxes say),
        ; no mention, no @everyone. It replaces the old `startstop` start
        ; message, so a webhook never gets two. Stop still routes `startstop`.
        this._Broadcast(Emoji.Moon " " Brand.Name, "## Macro started`nMade by " Credits.Name() "`n" App.DiscordLine, 0xF2A93B, App.StartFields(this.cfg))
        this.CheckCredits()
        win := this._idle ? "idle" : this._Window()
        if (win = "idle")
            this._IdleStart()                   ; no focus, no pause for the window, no input
        else if (win = "missing" && this._RejoinReady())
            this.Log("Roblox is not open: auto-rejoin opens your private server")
        else if (win != "ok")
            this._PauseFor(win)
        else if (this._Active() && this._taskMap.Has("fishing") && HasMethod(this._taskMap["fishing"], "LineInAtStart"))
            this._taskMap["fishing"].LineInAtStart(this.ctx)     ; a line a stop left out
        this.timerFn.Call(this._tickFn, App.TickMs)
        this._timerOn := true
        if IsObject(this.sched)
            try this.sched.NoteStart(this._schedStarting)
        this._Status()
        return true
    }

    TogglePause() {
        if !this._started
            return false
        return this.ctx.IsPaused() ? this.Resume() : this.Pause()
    }

    Pause() {
        if !this._started
            return false
        this.ctx.Pause()
        this._pauseReason := ""          ; by hand: never resumed by the macro
        try this.input.ReleaseAll()
        try this.clip.CancelAll()
        this.Log("Paused")
        this._Status()
        return true
    }

    Resume() {
        if !this._started
            return false
        win := this._idle ? "ok" : this._Window()          ; idle mode needs no usable window
        if (win != "ok" && !(win = "missing" && this._RejoinReady())) {
            this._PauseFor(win)
            this._Status()
            return false
        }
        this._pauseReason := ""
        if this._problems.Has("tick")
            this._problems.Delete("tick")      ; a repeat of a tick error is reported again
        this.ctx.Resume()
        this.Log("Resumed")
        this._Status()
        return true
    }

    ; F3 / Stop buttons. Also the potion kill switch (spec 4.6a).
    Stop(why := "F3") {
        this.ctx.Stop()
        if IsObject(this._testCtx)
            this._testCtx.Stop()
        try this.clip.CancelAll()
        try this.input.ReleaseAll()
        if !this._idle            ; idle mode never touches the mouse or keys
            this._ShiftOff()      ; a halted hunt can leave it on: other clicks would miss
        this._IdleOff()
        was := this._started
        this._started := false
        if (was && this._hiResOn)
            try Input.HiRes(false)
        this._pauseReason := ""
        this._note := ""
        try this._RestoreFake(true)
        if was {
            this._uptime := this.Now() - this._startedAt
            if IsObject(this.daily)
                try this.daily.StopSession(), this.daily.Save()
            if IsObject(this.sched)
                try this.sched.NoteStop()
            this.Log("Stopped (" why ")")
            this._Send("startstop", "Macro stopped", "## Session summary`nStopped: " App._Cap(why), 0x0B2A5B, this._StopFields(this._uptime))
        }
        this._Status()
        return was
    }

    _PauseFor(kind) {
        if (kind = "unfocused" && this._Refocus())
            return
        m := App.Msg[kind]
        if (this._pauseReason != m[1])
            this.Log("Paused: " m[2] (kind = "unfocused" ? App.FrontNote(this._frontFn) : "")
                . ((kind = "notfs" && Roblox.Problem != "") ? " (" Roblox.Problem ")" : ""))
        this._pauseReason := m[1]
        this.ctx.Pause()
        try this.input.ReleaseAll()
    }

    ; Apps that pull focus away from Roblox on their own (exe -> what to do).
    static FocusThieves := Map("mspcmanager.exe", "Microsoft PC Manager's toolbar takes focus: close PC Manager or turn its toolbar off"
        , "medal.exe", "Medal's overlay or a clip notice took focus: turn off Medal's in-game notifications")

    ; A known focus thief (FocusThieves) took the focus: Roblox is put back in
    ; front, at most RefocusMax times in RefocusWindowMs (live 2026-11-12: PC
    ; Manager's toolbar took it 1.5 s after every F1 and every run paused).
    ; -> true when Roblox is in front again (no pause).
    static RefocusMax := 3
    static RefocusWindowMs := 60000
    _Refocus() {
        exe := ""
        try exe := IsObject(this._frontFn) ? this._frontFn.Call() : WinGetProcessName("A")
        if !App.FocusThieves.Has(StrLower(exe))
            return false
        now := this.Now()
        while (this._refocusAt.Length && now - this._refocusAt[1] > App.RefocusWindowMs)
            this._refocusAt.RemoveAt(1)
        if (this._refocusAt.Length >= App.RefocusMax)
            return false
        this._refocusAt.Push(now)
        try this.roblox.Focus(2)
        if !this._Active()
            return false
        this.Log("Roblox put back in front (" exe " took the focus)")
        return true
    }

    ; " In front: <exe>." (+ a hint for a known focus thief) or "" when it
    ; cannot be told. frontFn: () -> exe name of the foreground window.
    static FrontNote(frontFn := "") {
        exe := ""
        try exe := IsObject(frontFn) ? frontFn.Call() : WinGetProcessName("A")
        if (exe = "")
            return ""
        k := StrLower(exe)
        return " In front: " exe "." (App.FocusThieves.Has(k) ? " " App.FocusThieves[k] "." : "")
    }

    ; ---- idle mode ----------------------------------------------------------------
    ; General.idleMode=1 (the owner, 2026-11-17): Start only WATCHES. Biomes
    ; and auras come from the Roblox log (no focus needed); the chat and the
    ; biome clock are read from Roblox's own window image (Ocr.Win:
    ; PrintWindow, so Roblox may sit behind other windows, not minimized);
    ; rare biome / aura screenshots likewise (Screenshot.FromWindow). No task
    ; runs and nothing is sent: no clicks, no mouse moves (ChatWatch.NoHover),
    ; no keys (Clip idle: no clip hotkey), no focus taking, no pause for the
    ; window. No anti-AFK either: Roblox's own 20 minute idle kick can still
    ; disconnect an untouched client.

    static IdleStartMsg := "Idle mode: reading biomes, auras, chat and the biome clock only; no clicks or keys, Roblox can stay behind other windows."
        . " No anti-AFK or auto-rejoin either: Roblox's 20 minute idle kick ends the watch"
    static IdleNote := "Idle (watching)"

    _IdleOn() {
        try return (this.cfg.Get("General.idleMode", 0) = 1) ? true : false
        return false
    }

    _IdleStart() {
        Screenshot.FromWindow := true
        ChatWatch.NoHover := true
        if HasMethod(this.clip, "SetIdle")
            try this.clip.SetIdle(true)
        this._IdleWin()
    }

    ; back to normal (every Stop; harmless when idle mode was not on)
    _IdleOff() {
        this._idle := false
        Ocr.Win := 0
        Screenshot.FromWindow := false
        ChatWatch.NoHover := false
        if HasMethod(this.clip, "SetIdle")
            try this.clip.SetIdle(false)
    }

    ; Ocr.Win := the Roblox window (0 when it is missing or minimized: no
    ; read then) and Screen mapped to its client, which may be covered or
    ; partly off the screen (PrintWindow reads it anyway). Sets the status.
    _IdleWin() {
        h := 0
        try h := this.roblox.Hwnd()
        mini := false
        if h {
            try mini := DllCall("IsIconic", "Ptr", h, "Int") ? true : false
            if !mini {
                ; the usual check maps Screen; a window it refuses (Windowed
                ; No, partly off the screen) is mapped as it is
                if (this._Window() != "ok" && this.roblox == Roblox)
                    try Screen.Refresh(h)
            }
        }
        Ocr.Win := (h && !mini) ? h : 0
        this._note := !h ? "Idle: Roblox not open" : mini ? "Idle: Roblox minimized" : App.IdleNote
    }

    ; One idle tick (the log poll and the webhooks ran already): the window
    ; source refreshed, then the chat read (ChatWatch throttles itself to
    ; merchant.chatPollSec) without a hover. Paused (F2): nothing is read.
    _IdleTick(now) {
        this._IdleWin()
        if (this.ctx.IsPaused() || !Ocr.Win || !IsObject(this.chat) || !this._ChatOn())
            return
        try {
            this.chat.Check()
        } catch Any as e {
            this._Problem("chat", "ChatWatch: " App._ErrText(e))
        }
    }

    ; ---- tick -------------------------------------------------------------------

    ; Timer callback. Nothing may escape it: an uncaught error would show an
    ; AHK dialog and freeze the tick while a task may still send input.
    Tick() {
        try {
            this._TickBody()
        } catch Any as e {
            this._TickError(e)
        }
    }

    _TickError(e) {
        try this._Problem("tick", "Scheduler error: " App._ErrText(e) ". Macro paused; fix the cause, then press F2.")
        try this.Pause()
        try this.input.ReleaseAll()
        try this._Status()
    }

    _TickBody() {
        now := this.Now()
        ; a timed walk is playing: a Roblox log read or a webhook post here
        ; runs between the walk's key down and up and holds the key longer,
        ; so the walk overshoots (live 2026-11-10: the sell route missed the
        ; Fisher 1 in 3 inside the macro, 6 of 6 alone). Both wait for it.
        walking := Input.InRoute         ; set by Input.PlayRoute (every walk)
        if (!walking && (this._lastPoll == "" || now - this._lastPoll >= App.LogPollMs)) {
            this._lastPoll := now
            this.PollLogs()
        }
        if !walking {
            ; an error here stops every Discord message without a word: say it
            ; (once a minute) - 2026-11-16, the boss card that never came
            try this.wh.Flush()
            catch Any as e {
                if (!this.HasOwnProp("_flushErrAt") || now - this._flushErrAt > 60000) {
                    this._flushErrAt := now
                    this.Log("Webhook: sending failed: " Webhook.ScrubText(e is Error ? e.Message " (" e.What ", line " e.Line ")" : String(e)))
                }
            }
        }
        this._TrackLoops()
        this._MaybeRestoreFake()
        if (!this._started || this.ctx.IsStopped()) {
            if !IsObject(this._running)
                this._Finish()
            this._Status()
            return
        }
        if this._idle {
            this._IdleTick(now)
            this._Status()
            return
        }
        win := this._Window()
        this._MaybeAutoResume(win)
        if IsObject(this._running) {
            this._Monitor(now, win)
            this._Status()
            return
        }
        this._MaybeRebuild()
        if (!this.ctx.IsPaused() && now >= this._holdUntil)
            this._StartNext(now, win)
        this._Status()
    }

    _Finish() {
        if !this._timerOn
            return
        try this.wh.Drain(App.DrainMs)
        ; Drain sleeps: F1 pressed meanwhile re-armed the timer for the new
        ; run, and deleting it now left "Running" with nothing ticking
        if this._started
            return
        this.timerFn.Call(this._tickFn, 0)
        this._timerOn := false
    }

    _Monitor(now, win) {
        cur := this._running
        if this.ctx.IsPaused()
            return
        ; Input must never land outside Roblox. Recovery is exempt: it
        ; rejoins (no window yet) and focuses Roblox itself.
        if (cur.name != "recovery") {
            ; a rejoin is waiting (disconnect screen, ghost server): a crashed
            ; client that loses focus or shrinks is halted for recovery, not
            ; paused (live 2026-11-16: paused 14 s after the disconnect was
            ; read, recovery never ran, 2.5 h lost)
            if ((win = "notfs" || win = "missing" || !this._Active()) && this._RejoinWaiting()) {
                if !this.ctx.IsHalted() {
                    this.ctx.RequestPreempt(true)
                    try this.input.ReleaseAll()
                    this.Log(StrTitle(cur.name) ": Roblox " (win = "ok" ? "lost focus" : win = "missing" ? "window gone" : "window not usable") " with a rejoin waiting, stopping for recovery")
                }
                return
            }
            if (win = "notfs") {
                this._PauseFor("notfs")
                return
            }
            if (win = "missing") {
                if this._RecoveryOn() {
                    ; a halt too, even on top of a plain preempt: the task's
                    ; closing steps (CleanupCtx) must not click with no window
                    if !this.ctx.IsHalted() {
                        this.ctx.RequestPreempt(true)
                        this.Log(StrTitle(cur.name) ": Roblox window gone, stopping for recovery")
                    }
                } else
                    this._PauseFor("missing")
                return
            }
            if !this._Active() {
                this._PauseFor("unfocused")
                return
            }
        }
        this._MaybeChatDue(now, cur)
        if this.ctx.IsPreempted()
            return
        nxt := this._Pick(now, win)
        if (IsObject(nxt) && nxt !== cur && nxt.priority < cur.priority && !(HasMethod(cur, "Holds") && cur.Holds(nxt))) {
            this.ctx.RequestPreempt()
            this.Log(StrTitle(cur.name) ": interrupted for " StrTitle(nxt.name))
        }
    }

    ; Limbo mode: Limbo on, except while the crack is on hold (LimboTask.Held:
    ; it could not be used, the next try is RetryMin away), when the island
    ; tasks run until that try (2026-11-20: nothing could run for those 10
    ; minutes and the status said "Idle", read as idle mode)
    _LimboMode() => (this._taskMap.Has("limbo") && this.cfg.Get("Limbo.enabled", 0) && !this._LimboHeld()) ? true : false

    _LimboHeld() {
        if !(this._taskMap.Has("limbo") && this.cfg.Get("Limbo.enabled", 0))
            return false
        ; the last join was not the private server (a ghost server) while one
        ; is set: the island tasks wait for the rejoin / the crack (2026-11-20
        ; review). No private server (public play): the hold applies.
        if (this._joinKind = "other" && RecoveryTask.LinkOk(Trim(String(this.cfg.Get("General.privateServer", "")))))
            return false
        l := this._taskMap["limbo"], held := false
        if HasMethod(l, "Held")
            try held := l.Held(this.state) ? true : false
        return held
    }

    _Pick(now, win) {
        held := this._LimboHeld()
        if (held && !this.state.limboHeld) {
            ; Limbo mode never walked to the fishing spot: the sell trip
            ; walks there first (once until the player is in Limbo again:
            ; a crack try only opens the inventory)
            if (!this._limboTrip && FishLogic.TripWanted(this.cfg) && this._taskMap.Has("sell")) {
                this.state.needRepath := true
                this._limboTrip := true
            }
        }
        if this.state.inLimbo
            this._limboTrip := false
        this._LimboSync()
        this.state.limboHeld := held
        this.state.limboMode := this._LimboMode()     ; follows the Fishing page switch
        list := this._tasks
        if (win = "missing") {
            list := []
            if IsObject(this.recovery)
                list.Push(this.recovery)
        }
        return Scheduler.Next(list, this.state, now)
    }

    _StartNext(now, win) {
        ; a rejoin is waiting: recovery runs first, without the focus / window
        ; checks (it closes the client and focuses Roblox itself)
        if this._RejoinWaiting() {
            nxt := Scheduler.Next([this.recovery], this.state, now)
            if IsObject(nxt) {
                this._note := ""
                this._Launch(nxt)
            } else
                this._note := "Waiting to rejoin"
            return
        }
        if (win = "notfs") {
            this._PauseFor("notfs")
            return
        }
        if (win = "ok") {
            ; overnight review: Roblox was focused on every idle tick, taking
            ; it back from the browser within 250 ms. Idle (nothing to pick),
            ; chat is read only when Roblox is already in front, and focus is
            ; taken only when something will launch.
            if !IsObject(this._Pick(now, win)) {
                if this._Active()
                    this._CheckChat()               ; a merchant may make a task eligible
                if !IsObject(this._Pick(now, win)) {
                    this._note := this._WaitNote()
                    return
                }
            }
            ; Focus first (may block up to 2 s in WinWaitActive): hotkeys and
            ; dashboard events can run meanwhile, so everything is re-checked
            ; and the task is picked again AFTER focus and chat.
            if !this._Focus() {
                if (this._note != "Waiting for Roblox focus")
                    this.Log("Roblox did not take focus; waiting")
                this._note := "Waiting for Roblox focus"
                return
            }
            if !this._CanLaunch()
                return
            this._CheckChat()
            if !this._CanLaunch()
                return
            this._TitleGate()
            if !this._CanLaunch()
                return
        }
        nxt := this._Pick(now, win)
        if !IsObject(nxt) {
            if (win = "missing") {
                if (!IsObject(this.recovery) || !this.cfg.Get("recovery.enabled", 1))
                    this._PauseFor("missing")
                else
                    this._note := "Waiting for Roblox"
            } else
                this._note := this._WaitNote()
            return
        }
        this._note := ""
        this._Launch(nxt)
    }

    ; The status when nothing can run: why the macro waits, never a bare
    ; "Idle" (2026-11-20: a user read it as idle mode while the Portable
    ; Crack was on hold). Dashboard / overlay translate it (UiLogic.TaskText).
    _WaitNote() {
        if (this._taskMap.Has("limbo") && this.cfg.Get("Limbo.enabled", 0) && !this.state.inLimbo) {
            l := this._taskMap["limbo"], at := ""
            if HasMethod(l, "HoldClock")
                try at := l.HoldClock()
            if (at != "")
                return "Waiting: next Portable Crack try at " at
        }
        if !this.cfg.Get("General.fishing", 1)
            return "Waiting: fishing is off and nothing else is due"
        return "Waiting: nothing is due right now"
    }

    ; Stop / pause pressed (e.g. during _Focus) -> do not launch.
    _CanLaunch() => this._started && !this.ctx.IsStopped() && !this.ctx.IsPaused()

    _Launch(task) {
        this._running := task
        ; Once _running is set a potion rebuild is deferred, so this check
        ; cannot race: never launch a PotionsTask that a rebuild replaced.
        if (task.name = "potions" && task !== this.potions) {
            task := this.potions
            if !(IsObject(task) && task.CanRun(this.state)) {
                this._running := ""
                return false
            }
            this._running := task
        }
        this.launchFn.Call(ObjBindMethod(this, "_RunTask", task))
        return true
    }

    ; Runs in its own thread (one-shot timer). Blocks until the task returns.
    _RunTask(task) {
        this.ctx.ClearPreempt()
        this.state.busy := task.name
        skipped := false
        failed := false
        this.Log("task: " task.name " start")
        try {
            ; a Daily Quests window left open (a Stop in the middle of it)
            ; covers the whole game: the sell after it clicked Open Shop under
            ; it and Captain Flarg's dialog stuck with the mouse locked (live
            ; 2026-11-14). Closed before any other task starts.
            if (task.name != "dailyquests" && this._taskMap.Has("dailyquests"))
                try this._taskMap["dailyquests"]._Close(this.ctx)
            ; shift lock on makes every UI click miss (live 2026-11-02: a
            ; click at the screen centre opened the Donation prompt): not
            ; confirmed off after one more try -> the task is skipped
            ; the unlock rejoin itself never waits on the check that keeps failing
            unlocking := (task.name = "recovery" && HasMethod(task, "Unlocking") && task.Unlocking())
            if (!unlocking && !this._ShiftOff(this.ctx) && !this._ShiftOff(this.ctx)) {
                skipped := true
                ; skipped again and again: wait longer each time (5 s, 10 s
                ; ... up to SkipHoldMaxMs), not a retry every 7 s all night
                this._skipStreak := (this.HasOwnProp("_skipStreak") ? this._skipStreak : 0) + 1
                this._holdUntil := this.Now() + Min(App.ErrorHoldMs * (2 ** Min(this._skipStreak - 1, 6)), App.SkipHoldMaxMs)
                if !this.ctx.ShouldStop()
                    this.Log(StrTitle(task.name) ": shift lock may still be on - skipped (no click)")
                ; still locked after SkipRejoinAt skips in a row: game windows
                ; stacked on each other hold the mouse and only a rejoin frees
                ; it (live 2026-11-15: 35 min of skips until a manual rejoin)
                if (this._skipStreak >= App.SkipRejoinAt && this._RecoveryOn() && HasMethod(this.recovery, "RequestUnlock")
                    && !this.ctx.ShouldStop() && this.recovery.RequestUnlock()) {
                    this._holdUntil := this.Now()
                    this.Log("still locked after " this._skipStreak " skips: rejoining to clear the game's windows")
                }
                return
            }
            if !unlocking                           ; the rejoin skipped the check: not proof the lock is gone
                this._skipStreak := 0
            Prof.on := this.cfg.Get("General.timing", 0) = 1     ; where the time goes (speed work)
            if (Prof.on && this.HasOwnProp("_endedAt")) {          ; the gap since the last task ended
                this._gapMs := (this.HasOwnProp("_gapMs") ? this._gapMs : 0) + Prof.Now() - this._endedAt
                this._gapN := (this.HasOwnProp("_gapN") ? this._gapN : 0) + 1
                if (this._gapN >= 50) {
                    this.Log(Format("time: between tasks {:.2f} s on average (50 tasks)", this._gapMs / this._gapN / 1000))
                    this._gapMs := 0, this._gapN := 0
                }
            }
            Prof.Start(task.name)
            task.Run(this.ctx)
        } catch Any as e {
            failed := true
            this._holdUntil := this.Now() + App.ErrorHoldMs
            this._Error(StrTitle(task.name) ": error: " App._ErrText(e) App._ErrWhere(e))
        } finally {
            how := this._EndHow(failed)
            pt := Prof.Text(), Prof.Stop()
            if (pt != "")
                this.Log(pt)
            this._endedAt := Prof.Now()
            this.Log("task: " task.name " end" (how != "" ? " (" how ")" : ""))
            if !skipped
                try this._Tidy(task)
            try this._UiStuckCheck()               ; game windows that keep failing: rejoin
            this.state.busy := ""
            if (task.name = "sell" && !skipped)
                this.state.startSell := false      ; the start sell happened (or failed): buying may follow
            ; the board run ends at spawn: go back through the Fisher (sell +
            ; buy if due) to the fishing spot right away, instead of fishing
            ; failing to find its panel first
            ; the same after every task that walks away from the fishing spot
            ; (live 2026-11-10: after minions / obby / merchant fishing
            ; looked for its panel, failed, saved a screen, then re-pathed)
            ; craft (its cauldron part ends with a respawn) and recovery (a
            ; stuck reset, a rejoin) only sometimes: they say so themselves
            ; (LeftSpot). Live 2026-11-20: 11 of 17 "no fishing panel"
            ; re-paths came right after one of the two, ~7 s and a saved
            ; screen each before the walk back started.
            away := App.MovesAway.Has(task.name)
            if (!away && HasMethod(task, "LeftSpot"))
                try away := task.LeftSpot() ? true : false
            if (away && !skipped && this._taskMap.Has("sell") && this.cfg.Get("General.fishing", 1))
                this.state.needRepath := true
            if !skipped                            ; a skipped task did not run: due again
                try this.state.Bump("runs." task.name)
            ; an interval task cut short (preempt, pause) did nothing yet: it
            ; may run again right away instead of in 30 / 10 min (review)
            if !(skipped || (task.name = "quests" || task.name = "obby") && (this.ctx.IsPreempted() || this.ctx.IsPaused()))
                try Scheduler.MarkRun(this.state, task, this.Now())
            this._running := ""
            this._MaybeRebuild()
        }
    }

    ; How a task ended, for its "task: <name> end (...)" line: "error" |
    ; "stopped" | "paused" | "preempted" | "" (returned on its own).
    _EndHow(failed) {
        c := this.ctx
        return failed ? "error" : c.IsStopped() ? "stopped" : c.IsPaused() ? "paused" : c.IsPreempted() ? "preempted" : ""
    }

    ; Between tasks (after every one, a preempted one too): what the task
    ; may have left on screen is closed before the next task starts (Tidy:
    ; the tasks' own detectors, one log line per item closed, nothing on a
    ; clean screen). Only with Roblox in front and not stopped / paused /
    ; halted: then nothing is sent.
    _Tidy(task) {
        c := this.ctx
        if (c.IsStopped() || c.IsPaused() || CleanupCtx.Halted(c) || !this._Active())
            return
        items := this._TidyItems(task)
        if items.Length
            Tidy.Run(task.name, items, c, this._logFn)
        this._ChatBack(c)
    }

    ; The chat a task hid (ChatGuard: it lay over a click below 1440p) is
    ; shown again between tasks, so ChatWatch can read the merchants' lines.
    ; Nothing read or sent when no task hid it.
    _ChatBack(c) {
        if ChatGuard.Hidden()
            try ChatGuard.Restore(CleanupCtx(c), "", this._logFn)
    }

    ; The task's own leftovers (Leftovers()), Captain Flarg's after craft
    ; (it buys at the fisher), then the shared screens (ObbyTask.TidyItem:
    ; purchase prompt, Daily Rewards, Quest Board page, Collections,
    ; Inventory, UGC Shop, raid window, Jock, Aura Storage). Fishing only
    ; gets the purchase prompt: it opens nothing else and returns before
    ; every chat check.
    _TidyItems(task) {
        items := []
        owners := [task]
        if (task.name = "craft" && this._taskMap.Has("sell"))
            owners.Push(this._taskMap["sell"])
        ; the catch card after EVERY task: a preempted cast fails only once
        ; the next task walks off, so "Fishing Failed" shows up after the
        ; fishing tidy (live 2026-11-10 02:29: it sat over the obby's Aura
        ; Storage, the hunt and the sell walk for 2 minutes)
        if (task.name != "fishing" && this._taskMap.Has("fishing"))
            owners.Push(this._taskMap["fishing"])
        ; the Daily Quests window covers everything too (2026-11-14)
        if (task.name != "dailyquests" && this._taskMap.Has("dailyquests"))
            owners.Push(this._taskMap["dailyquests"])
        for t in owners
            if HasMethod(t, "Leftovers")
                try {
                    for it in t.Leftovers()
                        items.Push(it)
                }
        scr := this._TidyScreen()
        if IsObject(scr)
            try items.Push(scr.TidyItem(task.name != "fishing"))
        return items
    }

    ; A fishing catch card over the screen closed (the fishing task's
    ; leftovers, as in the tidy) -> true when one was. Quests: the board did
    ; not open after E.
    _ClearCards(c) {
        if !this._taskMap.Has("fishing")
            return false
        f := this._taskMap["fishing"]
        if !HasMethod(f, "Leftovers")
            return false
        try
            return Tidy.Run("quests", f.Leftovers(), c, this._logFn).Length > 0
        return false
    }

    ; Before a launch (Roblox in front): the title screen a disconnect or a
    ; teleport can land on (live 2026-11-09) is left by its Play first, so
    ; no task starts on it. One small read when it is not up; nothing sent.
    _TitleGate() {
        scr := this._TidyScreen()
        if !(IsObject(scr) && HasMethod(scr, "TitleItem"))
            return
        try {
            it := scr.TitleItem()
            if (it.up.Call() = "")
                return
            r := it.close.Call("title screen", CleanupCtx(this.ctx))
            if (r >= 0)
                this.Log(r = 1 ? "title screen: clicked Play" : "title screen: clicked Play, it is still up")
        }
        this._DailyGate(scr)
    }

    ; Before a launch too: the Daily Rewards popup (it shows after a join)
    ; claimed and closed, always (no setting). One small read when it is
    ; not up.
    _DailyGate(scr) {
        if !HasMethod(scr, "DailyItem")
            return
        try {
            it := scr.DailyItem()
            if (it.up.Call() = "")
                return
            r := it.close.Call("Daily Rewards popup", CleanupCtx(this.ctx))
            if (r >= 0)
                this.Log(r = 1 ? "Daily Rewards: claimed and closed" : "Daily Rewards: still up after the X")
        }
    }

    ; The shared screen detectors: deps "tidyScreen", else the obby task's.
    _TidyScreen() {
        if this.HasOwnProp("_tidyScr")
            return this._tidyScr
        t := this._taskMap.Has("obby") ? this._taskMap["obby"] : ""
        return (IsObject(t) && HasMethod(t, "TidyItem")) ? t : ""
    }

    ; Moves the mouse over the chat: only between tasks and only while Roblox
    ; is the active window.
    _CheckChat() {
        this.state.chatDue := false
        this._lastChat := this.Now()
        if this.state.rareActive
            return                              ; no chat reads during a rare biome
        if !IsObject(this.chat)
            return
        if !this._ChatOn()
            return
        if !this._Active()
            return
        this._ChatBack(this.ctx)                ; a tidy that was skipped (paused, unfocused) left it hidden
        try {
            this.chat.Check()
        } catch Any as e {
            this._Problem("chat", "ChatWatch: " App._ErrText(e))
        }
    }

    ; Fishing is running: ask it to yield between catches when a chat check is
    ; due (merchant.chatPollSec since the last one).
    _MaybeChatDue(now, cur) {
        if (cur.name != "fishing" || this.state.chatDue)
            return
        if !this._ChatWanted()
            return
        if (this._lastChat !== "" && now - this._lastChat < this._ChatPollMs())
            return
        this.state.chatDue := true
    }

    _ChatWanted() {
        if (!IsObject(this.chat) || !this._ChatOn() || this.state.rareActive || this._LimboMode())
            return false
        try {
            if !IsObject(this.calibrate.Rect("chat_rect"))
                return false                    ; not calibrated: ChatWatch would read nothing
        }
        return true
    }

    ; the chat is read for the merchants and for the bosses' lines
    _ChatOn() => (this.cfg.Get("merchant.enabled", 1) || this.cfg.Get("Limited.bossAlert", 1)) ? true : false

    _ChatPollMs() {
        s := this.cfg.Get("merchant.chatPollSec", ChatWatch.DefaultPollSec)
        if (!IsNumber(s) || s < 1)
            s := ChatWatch.DefaultPollSec
        return Round(s * 1000)
    }

    _OnChatMerchant(name) {
        if !this.cfg.Get("merchant.enabled", 1)  ; the chat is read for the bosses: no visits
            return
        if IsObject(this.merchant)
            try this.merchant.Notify(name)
    }

    ; A boss named in the chat: its Discord message (the "sinister" event),
    ; whether hunting is on or not (the user, 2026-11-15). Limited.bossAlert 0
    ; turns it off.
    _OnChatBoss(boss) {
        if !this.cfg.Get("Limited.bossAlert", 1)
            return
        if IsObject(this.sinister)
            try this.sinister.Spawn("chat:" boss ":" this.Now(), boss)
    }

    _Focus() {
        try return this.roblox.Focus() ? true : false
        return false
    }

    ; Roblox in front and staying there. Record / Test minimize the
    ; dashboard first, and Windows hands the focus to the next window a
    ; moment AFTER _Focus returned (2026-10-27: the browser took it, so every
    ; Record / Test stopped at once with "Roblox lost focus" before Sailor
    ; was equipped). -> true when Roblox is still active after the settle.
    static FocusSettleMs := 500
    static FocusTries := 3
    _FocusSettled() {
        Loop App.FocusTries {
            if !this._Focus()
                return false
            this._sleepFn.Call(App.FocusSettleMs)
            if this._Active()
                return true
        }
        return false
    }

    ; Shift lock off (Input.ShiftLock: only toggles when on; never clicks).
    ; Best effort; only with Roblox in front (it moves the mouse and taps
    ; Left Shift). No ctx on stop: the stopped ctx would refuse it.
    ; -> false only when it was tried and not confirmed off (or stopped).
    _ShiftOff(ctx := "") {
        try {
            if (this._Active() && HasMethod(this.input, "ShiftLock"))
                return this.input.ShiftLock(false, "", ctx) ? true : false
        }
        return true
    }

    ; Roblox is the foreground window.
    _Active() {
        try {
            if HasMethod(this.roblox, "IsActive")
                return this.roblox.IsActive() ? true : false
            h := this.roblox.Hwnd()
            return (h && WinActive("ahk_id " h)) ? true : false
        }
        return false
    }

    _RecoveryOn() => IsObject(this.recovery) && this.cfg.Get("recovery.enabled", 1)

    ; RecoveryTask has a rejoin waiting (disconnect screen seen, ghost server,
    ; locked mouse) that it can do (link ok).
    _RejoinWaiting() {
        if !(this._RecoveryOn() && HasMethod(this.recovery, "Rejoining"))
            return false
        try return this.recovery.Rejoining(this.state) ? true : false
        return false
    }

    ; Paused by the macro itself (focus / window), never by F2: Roblox closed
    ; or a rejoin is waiting -> resumed so recovery rejoins (live 2026-11-16:
    ; a crash left it paused for hours). No screen read here: Roblox is not
    ; in front, an OCR would read whatever is.
    _MaybeAutoResume(win) {
        if !this.ctx.IsPaused() || this.ctx.IsStopped() || IsObject(this._running)
            return
        if !(this._pauseReason = App.Msg["unfocused"][1] || this._pauseReason = App.Msg["notfs"][1] || this._pauseReason = App.Msg["missing"][1])
            return
        if !((win = "missing" && this._RejoinReady()) || this._RejoinWaiting())
            return
        this.Log("Resumed: Roblox " (win = "missing" ? "closed" : "needs a rejoin") " while paused (" this._pauseReason "), auto-rejoin takes over")
        this._pauseReason := ""
        this.ctx.Resume()
    }
    ; Roblox closed at F1 / F2: auto-rejoin can open the private server (on,
    ; with a usable link). Before, Start paused ("Roblox not found") and F2
    ; was refused until Roblox was opened by hand (live 2026-11-11: Roblox
    ; had closed after a rejoin).
    ; A daily quest's "Use N <potion>": the name as read -> the potions.json
    ; id with the same canonical name, queued on the potion task (only when
    ; potion use is set up). -> true when queued.
    _PotionQuest(potion, n) {
        if !IsObject(this.potions) {
            this.Log("Potions: '" potion "' for a daily quest not used: potion use is not set up (Potions page)")
            return false
        }
        want := PotionSafety.Canon(potion), id := ""
        try for e in this.cfg.Data("potions")["potions"] {
            if (e is Map && e.Has("name") && PotionSafety.Canon(e["name"]) == want) {
                id := (e.Has("id") && Trim(e["id"]) != "") ? Trim(e["id"]) : Trim(e["name"])
                break
            }
        }
        if (id = "") {
            this.Log("Potions: '" potion "' (a daily quest) is not in the potion list: not used")
            return false
        }
        return this.potions.QueueQuest(id, n)
    }

    _RejoinReady() => this._RecoveryOn() && RecoveryTask.LinkOk(Trim(String(this.cfg.Get("General.privateServer", ""))))

    ; Windowed Roblox (General.windowed=1, 2026-11-14): the window is used as
    ; the player sized it (never moved or resized); at Start the overlay
    ; moves off the game if it covers it.
    _WindowedStart() {
        Roblox.AllowWindowed := (this.cfg.Get("General.windowed", 0) = 1)
        try Calibrate.ScaleOverride := Calibrate.ScaleFromText(this.cfg.Get("General.displayScale", 0))
        if !(Roblox.AllowWindowed && Roblox.Hwnd())
            return
        if (Roblox.ClientOk() = "ok" && Roblox.Windowed && IsObject(this.overlay) && HasMethod(this.overlay, "AvoidRect"))
            try this.overlay.AvoidRect(Screen.cx, Screen.cy, Screen.cw, Screen.ch)
    }

    ; "ok" | "missing" | "notfs" (minimized / unusable window). "ok" also refreshes
    ; Screen's mapping to the client (Roblox.ClientOk) and logs the display
    ; once per change.
    _Window() {
        try {
            if !this.roblox.Hwnd()
                return "missing"
            win := this.roblox.ClientOk()
            if (win = "ok")
                this._DisplayCheck()
            return win
        }
        return "missing"
    }

    ; Self-check line (client size, DPI scale, mapping) when it changes, and
    ; the status note when the size is not the verified 2560x1440.
    _DisplayCheck() {
        if !HasMethod(this.roblox, "Describe")
            return
        d := this.roblox.Describe()
        if (d != this._displayLogged) {
            this._displayLogged := d
            this.Log("Display: " d)
        }
        this._display := this.roblox.Verified() ? "" : "Roblox " this.roblox.SizeText() ": " Screen.NotTestedNote
    }

    ; Below 2560x1440 Roblox's chat keeps its pixel size and covers the left
    ; menu (Aura Storage / Collections): ChatGuard hides it right before such
    ; a click and _Tidy opens it again, so merchants work there too (the old
    ; "turn Merchants off" warning is gone, 2026-11-11).

    ; ---- log events -------------------------------------------------------------

    ; LogWatch.Poll -> routed events. Also the PotionsTask poll callback.
    PollLogs() {
        if this._polling
            return 0
        this._polling := true
        n := 0
        try {
            for ev in this.lw.Poll() {
                this.RouteEvent(ev)
                n++
            }
        } catch Any as e {
            this._Problem("logwatch", "LogWatch: " App._ErrText(e))
        } finally {
            this._polling := false
        }
        if (this._started && !this._limboChecked) {
            this._limboChecked := true
            this._LimboRestore()
        }
        return n
    }

    RouteEvent(ev) {
        try {
            type := ev["type"]
            if (type = "biome" || type = "aura" || type = "roll") {
                this.be.Handle(ev)
            } else if (type = "merchant") {
                live := ev.Has("live") && ev["live"] is Integer && ev["live"] = 1
                if (live && IsObject(this.merchant))
                    this.merchant.OnLogEvent(ev)
            } else if (type = "join") {
                this._OnJoin(ev)
            }
        } catch Any as e {
            this._Problem("route", "Event handling failed: " App._ErrText(e))
        }
    }

    ; The aura equipped now, from the Roblox log (ObbyTask's Sailor swap).
    _AuraNow() {
        this.PollLogs()
        lw := this.lw
        return {known: IsObject(lw) && HasProp(lw, "AuraKnown") && lw.AuraKnown, name: IsObject(lw) && HasProp(lw, "CurrentAura") ? lw.CurrentAura : ""}
    }

    ; The biome now, from the Roblox log (MinionsTask ends a hunt when it
    ; changes): the log polled, then state.biome (BiomeEvents).
    _BiomeNow() {
        this.PollLogs()
        return this.state.biome
    }

    ; A join (live, or the last one at startup): a teleport / public join is a
    ; ghost server (RecoveryTask rejoins the private server), a private one
    ; clears it. A live join quiets aura clips for Auras.JoinQuietMs (the new
    ; client's first "Equipped" line is no roll).
    _OnJoin(ev) {
        if (ev.Has("live") && ev["live"])
            Auras.Quiet(Auras.JoinQuietMs)
        this._joinKind := ev["name"]
        this._LimboJoin(ev)
        d := RecoveryTask.GhostDecision(ev["name"], this.state, this.cfg)
        if (d = "clear") {
            this.state.ghost := false
        } else if (d = "ghost" && !this.state.ghost) {
            this.state.ghost := true
            ; recovery off with a private server set: not rejoined, so the
            ; island tasks would run in the wrong server: paused with why
            ; (2026-11-20 live: tasks ran in a server that was not the private one)
            link := Trim(String(this.cfg.Get("General.privateServer", "")))
            if (!this._RecoveryOn() && RecoveryTask.LinkOk(link) && this._started && !this._idle) {
                this.Log("Ghost server: you are not in your private server and recovery is off")
                this._PauseFor("notprivate")
            } else
                this.Log("Ghost server: the game moved you to a server your friends can't join; rejoining your private server")
        }
    }

    ; THE LIMBO across restarts (live 2026-11-20 16:16): the Portable Crack
    ; takes the player to THE LIMBO inside the same server (Workspace
    ; .GlobalRolls.Limbo; no join in the Roblox log), so after a Stop + Start
    ; or an app restart nothing in the log says the player is still there:
    ; with Limbo switched off the macro ran quests, the obby and minions in
    ; it. inLimbo is kept in logs\limbo_session.flag with the Roblox session
    ; it was set in (log file + last join): the first poll after Start puts
    ; it back while that session goes on (Limbo on: waits by Eden; Limbo off:
    ; LimboTask rejoins Sol's Island first, only limbo / recovery run until
    ; then). Any new join is a fresh server on Sol's Island: cleared.
    _LimboFlag() => this._limboFlagPath != "" ? this._limboFlagPath : this.root "\logs\limbo_session.flag"

    ; the Roblox session now: "<log file name>|<ts of its last join>" or ""
    _LimboKey() {
        k := ""
        if (IsObject(this.lw) && HasMethod(this.lw, "JoinKey"))
            try k := String(this.lw.JoinKey())
        return k
    }

    _LimboRestore() {
        f := this._LimboFlag(), mark := ""
        try mark := Trim(FileRead(f, "UTF-8"), " `t`r`n")
        key := this._LimboKey()
        if (mark != "" && key != "" && mark == key) {
            this._limboMarked := true
            if !this.state.inLimbo {
                this.state.inLimbo := true
                off := !this.cfg.Get("Limbo.enabled", 0)
                this.Log("Limbo: still in THE LIMBO (the Portable Crack was used in this Roblox session, no rejoin since)"
                    . (off ? ": Limbo is off, so the macro rejoins Sol's Island first" : ": waiting by Eden"))
            }
            return
        }
        if (mark != "")
            try FileDelete(f)
        this._limboMarked := false
        ; kept in memory from the last run, but Roblox joined again since
        if (this.state.inLimbo && mark != "" && key != "") {
            this.state.inLimbo := false
            this.Log("Limbo: Roblox joined a server since THE LIMBO: on Sol's Island")
        }
    }

    ; the flag follows state.inLimbo (only once the first poll restored it)
    _LimboSync() {
        if (!this._limboChecked || this._limboMarked == (this.state.inLimbo ? true : false))
            return
        f := this._LimboFlag()
        if this.state.inLimbo {
            key := this._LimboKey()
            if (key = "")
                return
            try {
                DirCreate(RegExReplace(f, "\\[^\\]+$"))
                if FileExist(f)
                    FileDelete(f)
                FileAppend(key, f, "UTF-8")
                this._limboMarked := true
            }
        } else {
            try FileDelete(f)
            this._limboMarked := false
        }
    }

    ; A new join (live) is a fresh server on Sol's Island: never THE LIMBO.
    ; The backfilled last join at Start is _LimboRestore's.
    _LimboJoin(ev) {
        if !(ev.Has("live") && ev["live"])
            return
        if (IsObject(this.recovery) && HasMethod(this.recovery, "OnJoin"))
            try this.recovery.OnJoin()
        if this.state.inLimbo {
            this.state.inLimbo := false
            this.Log("Limbo: Roblox joined a server: on Sol's Island")
        }
        this._LimboSync()
    }

    ; A ghost server now (MinionsTask's boss message is never sent from one):
    ; state.ghost, or the last join was not from the private server link
    ; (state.ghost stays false with recovery.antiGhost off). The log polled
    ; first.
    _GhostNow() {
        this.PollLogs()
        return (HasProp(this.state, "ghost") && this.state.ghost) || this._joinKind = "other"
    }

    ; ---- status -----------------------------------------------------------------

    _TrackLoops() {
        n := this.state.fishLoops
        d := n - this._lastLoops
        if (d > 0 && d <= 3)        ; bigger jumps are the repath shortcut, not catches
            this._loops += d
        this._lastLoops := n
    }

    ; Home's NEXT UP (idea 8, 2026-11-13): the soonest timed task while
    ; running -> "Quests in 12 min" / "Obby now" / "" (stopped, none on)
    NextUp() {
        if (!this._started || this._idle)       ; idle mode runs no timed task
            return ""
        now := this.Now()
        best := "", bestMs := -1
        ; t[5]: the switch's default, as the task reads it (quests on: a
        ; missing key never showed Quests here, audit 2026-11-20)
        for t in [["quests", "Quests", "quests.enabled", "questIntervalMs", 1], ["obby", "Obby", "Obby.enabled", "obbyIntervalMs", 0]] {
            if !(this._taskMap.Has(t[1]) && this.cfg.Get(t[3], t[5]))
                continue
            ms := this.state.lastRun.Has(t[1]) ? Max(0, this.state.lastRun[t[1]] + this.state.%t[4]% - now) : 0
            if (bestMs < 0 || ms < bestMs)
                best := t[2], bestMs := ms
        }
        if (this._taskMap.Has("memorymatch") && this.cfg.Get("MemoryMatch.enabled", 0)) {
            ms := 0
            try {
                if (!this.HasOwnProp("_mmNext") || A_TickCount - this._mmNext.at > 30000)
                    this._mmNext := {at: A_TickCount, v: this._taskMap["memorymatch"].NextTry()}
                nt := this._mmNext.v
                if (nt != "")
                    ms := Max(0, DateDiff(nt, A_Now, "Seconds") * 1000)
            }
            if (bestMs < 0 || ms < bestMs)
                best := "Memory Match", bestMs := ms
        }
        if (bestMs < 0)
            return ""
        if (bestMs < 60000)
            return best " now"
        m := bestMs // 60000
        return best " in " (m < 60 ? m " min" : (m // 60) "h " Mod(m, 60) "m")
    }

    ; Orb mode on and not hunting now: why (MinionsTask.WaitNote), else "".
    _OrbNote() {
        if (!this._taskMap.Has("minions") || !this.cfg.Get("Minions.enabled", 0))
            return ""
        try return this._taskMap["minions"].WaitNote(this.state.biome)
        return ""
    }

    _Status() {
        st := !this._started ? "Stopped" : this.ctx.IsPaused() ? "Paused" : "Running"
        if (this._pauseReason != "")
            task := this._pauseReason
        else if IsObject(this._running)
            task := StrTitle(this._running.name)
        else
            task := this._started ? this._note : ""
        if (this._display != "" && (task = "" || task = "Idle" || SubStr(task, 1, 8) = "Waiting:"))
            task := (task = "" ? "" : task ". ") this._display
        if (task = "Fishing" && (n := this._OrbNote()) != "")
            task .= ", " n
        up :=this._started ? this.Now() - this._startedAt : this._uptime
        biome := this.state.biome
        rare := this.state.rareActive ? true : false
        stats := (this.state.HasProp("stats") && this.state.stats is Map) ? this.state.stats : Map()
        for u in this.ui {
            try u.SetStatus(st, task, biome, rare, up, this._loops)
            if HasMethod(u, "SetNext")
                try u.SetNext(this.NextUp())
            if HasMethod(u, "SetStats")            ; Dashboard Home tiles (cheap when unchanged)
                try u.SetStats(stats)
        }
    }

    ; Every log line also goes to <root>\logs\macro.log (date, time, secrets
    ; scrubbed): the dashboard keeps its log only in memory, so after a bad
    ; run there was nothing to read back (2026-10-27). Moved to
    ; macro.old.log past LogFileMax. A line that cannot be written (another
    ; program holds the file without write sharing, e.g. Git Bash tail -F) is
    ; kept and written with the next line, up to LogPendingMax characters
    ; (oldest dropped), so a lock never loses the run's log (2026-11-10).
    static LogFileMax := 1048576
    static LogPendingMax := 262144
    _logPending := ""
    _LogFile(text) {
        if (this.root = "")
            return
        line := ""
        try line := FormatTime(, "yyyy-MM-dd ") UiLogic.LogLine(text, this._Secrets()) "`n"
        this._logPending .= line
        if (StrLen(this._logPending) > App.LogPendingMax)
            this._logPending := SubStr(this._logPending, -App.LogPendingMax)
        try {
            dir := this.root "\logs"
            if !DirExist(dir)
                DirCreate(dir)
            path := dir "\macro.log"
            if (FileExist(path) && FileGetSize(path) > App.LogFileMax)
                FileMove(path, dir "\macro.old.log", 1)
            FileAppend(this._logPending, path, "UTF-8")
            this._logPending := ""
        }
    }

    Log(text) {
        this._LogFile(text)
        this._FixCheck(text)
        if (this.ui.Length = 0) {
            if (this._early.Length < 100)
                this._early.Push(text)
            return
        }
        for u in this.ui
            try u.Log(text)
    }

    ; ---- fix-it cards (idea 10, 2026-11-13) ----

    ; a log line that makes a FixIt rule trip -> its card (no focus taken)
    _FixCheck(text) {
        if !(this._fixOn && IsObject(this.fixit) && IsObject(this.dash))
            return
        r := ""
        try r := this.fixit.Seen(text, this.Now())
        if !IsObject(r)
            return
        try this._fixCard.Destroy()
        try {
            this._fixCard := FixCard(r, Map("page", (n) => this._FixPage(n), "act", (a) => this._FixAct(a)
                , "zip", () => this._FixZip(), "dismiss", (k) => (this.fixit.Dismiss(k), this._fixCard := "")))
            this._fixHid := false
            this._FixCardPlace()
        }
    }

    ; ---- package B (2026-11-20): the fix card off the game, the stuck-UI escape ----

    static FixQuietMs := 10 * 60000      ; the card's line not seen for this long: the problem is gone, card closed
    ; only rules whose line keeps coming while the problem lasts (a missing
    ; link or calibration is logged once and stays a problem)
    static FixAutoClose := Map("shift", 1, "focus", 1, "notfs", 1, "inventory", 1, "rejoins", 1)
    static UiRejoinGapMs := 20 * 60000   ; stuck-UI rejoins at most this often (a misread must not rejoin all night)

    ; Start: the last run's card closed (FixIt.Reset lets it come back), the
    ; stuck-UI streak cleared.
    _StuckUiStart() {
        try this._fixCard.Destroy()
        this._fixCard := ""
        UiStuck.Reset()
        this._uiStuckTold := false
    }

    ; The card where it covers no game (FixCard.Spot); with no room it is
    ; hidden while the macro runs and shown when paused or stopped.
    _FixCardPlace() {
        c := this._fixCard
        if !IsObject(c)
            return
        running := this._started && !this.ctx.IsPaused() && !this.ctx.IsStopped()
        w := Theme.Dpi(FixCard.W), h := Theme.Dpi(FixCard.H)
        mons := []
        Loop MonitorGetCount() {
            MonitorGetWorkArea(A_Index, &l, &t, &r, &b)
            mons.Push({l: l, t: t, r: r, b: b})
        }
        MonitorGetWorkArea(MonitorGetPrimary(), , , &pr, &pb)
        pref := FixCard.Pos(pr, pb)
        game := ""
        if (running && Roblox.Hwnd() && Screen.cw > 0)
            game := {x: Screen.cx, y: Screen.cy, w: Screen.cw, h: Screen.ch}
        p := FixCard.Spot(w, h, game, mons, pref)
        if IsObject(p) {
            c.ShowAt(p.x, p.y)
            this._fixHid := false
            return
        }
        c.Hide()
        if !(this.HasOwnProp("_fixHid") && this._fixHid) {
            this._fixHid := true
            this.Log("fix card '" c.rule.title "' waits until the macro pauses or stops (it would cover the game)")
        }
    }

    ; ServiceTick: placed again (pause, stop, a moved window), and closed
    ; once its line has not come back for FixQuietMs.
    _FixCardTick() {
        c := this._fixCard
        if !IsObject(c)
            return
        q := this.fixit.QuietFor(c.rule.key, this.Now())
        if (App.FixAutoClose.Has(c.rule.key) && q >= App.FixQuietMs) {
            try c.Destroy()
            this._fixCard := ""
            this.fixit.Forget(c.rule.key)
            this.Log("fix card '" c.rule.title "' closed: the problem has not shown for " App.FixQuietMs // 60000 " min")
            return
        }
        this._FixCardPlace()
    }

    ; After every task: UiStuck.TripAt game windows in a row did not read
    ; (Aura Storage, inventory, aura search, a Memory Match board left
    ; open) -> the recovery task rejoins, at most once per UiRejoinGapMs.
    ; Live 2026-11-20: a board left open locked the macro out 00:12-06:39.
    _UiStuckCheck() {
        if (!UiStuck.Due() || this.ctx.IsStopped() || this.ctx.IsPaused())
            return
        if !(this._RecoveryOn() && HasMethod(this.recovery, "RequestUnlock")) {
            if !(this.HasOwnProp("_uiStuckTold") && this._uiStuckTold)
                this.Log("the game's windows look stuck (" UiStuck.Text() "); auto-rejoin is off, so nothing clears them: close them in Roblox or rejoin")
            this._uiStuckTold := true
            UiStuck.Reset()
            return
        }
        now := this.Now()
        if (this.HasOwnProp("_uiRejoinAt") && now - this._uiRejoinAt < App.UiRejoinGapMs)
            return
        if !this.recovery.RequestUnlock()
            return                              ; a rejoin is already asked for
        this._uiRejoinAt := now
        this.Log("the game's windows look stuck (" UiStuck.Text() "): rejoining to clear them")
        UiStuck.Reset()
        this._holdUntil := now
    }

    _FixPage(name) {
        i := Dashboard.PageIndex(name)
        if !i
            return
        if !this.dash.PageShown(name)
            this.dash.SetSimple(false)          ; simple mode hides it: every page shows
        try this.dash.Show()
        this.dash.SelectPage(i)
    }

    ; "Fix it for me" -> a line for the card
    _FixAct(act) {
        if (act = "fullscreen") {
            if !WinExist("ahk_exe RobloxPlayerBeta.exe")
                return "Roblox is not open."
            if (this._Window() != "notfs")
                return "The Roblox window is fine now: press F2 (or F1)."
            try {
                if DllCall("IsIconic", "Ptr", WinExist("ahk_exe RobloxPlayerBeta.exe"), "Int") {
                    WinRestore("ahk_exe RobloxPlayerBeta.exe")
                    WinActivate("ahk_exe RobloxPlayerBeta.exe")
                    return "Restored the Roblox window. Press F2 (or F1)."
                }
                WinActivate("ahk_exe RobloxPlayerBeta.exe")
                WinWaitActive("ahk_exe RobloxPlayerBeta.exe", , 2)
                Sleep(250)
                Send("{F11}")
            }
            return "Pressed F11 in Roblox. When it is fullscreen, press F2."
        }
        return ""
    }

    _FixZip() {
        r := this.OnLogBundle(false)
        if !(IsObject(r) && r.ok)
            return "Not made: " (IsObject(r) ? r.msg : "the macro is not ready")
        try Run('explorer.exe /select,"' r.path '"')
        return "Made " RegExReplace(r.path, "^.*\\") ": send it to whoever helps you."
    }

    _Send(ev, title, desc, color, fields := "") {
        if IsObject(this.wh)
            try this.wh.Send(ev, title, UiLogic.Scrub(desc, this._Secrets(), true), color, {fields: this._ScrubFields(fields)})
    }

    _Broadcast(title, desc, color, fields := "") {
        if IsObject(this.wh)
            try this.wh.Broadcast(title, UiLogic.Scrub(desc, this._Secrets(), true), color, {fields: this._ScrubFields(fields)})
    }

    _ScrubFields(fields) {
        if !(fields is Array)
            return ""
        out := []
        sec := this._Secrets()
        for f in fields
            out.Push(Webhook.Field(Webhook._Opt(f, "name", ""), UiLogic.Scrub(String(Webhook._Opt(f, "value", "")), sec, true)
                , Webhook._Opt(f, "inline", false)))
        return out
    }

    ; Session summary fields for the stop message ("" when nothing ran):
    ; uptime, loops, fishing (caught / got away / catch rate), selling and
    ; whatever else ran (state.stats, reset on Start). Zero rows are left out
    ; except the fishing ones once anything was reeled.
    _StopFields(upMs) {
        st := (this.state.HasProp("stats") && this.state.stats is Map) ? this.state.stats : Map()
        if !this._loops && upMs <= 0 && st.Count = 0
            return ""
        g := (k) => st.Has(k) ? st[k] : 0
        f := [Webhook.Field(Emoji.Timer " Ran for", App._Duration(upMs)), Webhook.Field(Emoji.Cycle " Loops", String(this._loops))]
        caught := g("fishCaught"), lost := g("fishFailed")
        if (caught + lost > 0) {
            f.Push(Webhook.Field(Emoji.Fish " Fish caught", App._Num(caught)))
            f.Push(Webhook.Field(Emoji.Cross " Got away", App._Num(lost)))
            f.Push(Webhook.Field(Emoji.Check " Catch rate", Round(100 * caught / (caught + lost)) "%"))
        }
        rows := [["falseBites", Emoji.Warn " False bites"], ["repaths", Emoji.Compass " Re-walks"]
            , ["sells", Emoji.Money " Sell trips"], ["fishTypesSold", Emoji.Money " Fish types sold"]
            , ["biomes", Emoji.Globe " Biomes seen"], ["rareBiomes", Emoji.Siren " Rare biomes"]
            , ["runs.potions", Emoji.Potion " Potion runs"], ["runs.craft", Emoji.Alembic " Craft runs"]
            , ["runs.quests", Emoji.Scroll " Quest board runs"], ["runs.merchant", Emoji.Cart " Merchant visits"]]
        for r in rows
            if g(r[1])
                f.Push(Webhook.Field(r[2], App._Num(g(r[1]))))
        return f
    }

    ; 3725000 -> "1h 2m 5s"
    static _Duration(ms) {
        s := Max(0, Integer(ms // 1000))
        h := s // 3600, m := Mod(s // 60, 60), sec := Mod(s, 60)
        return (h ? h "h " : "") ((h || m) ? m "m " : "") sec "s"
    }

    ; 1234567 -> "1,234,567"
    static _Num(n) {
        t := String(Integer(n)), out := ""
        while (StrLen(t) > 3)
            out := "," SubStr(t, -3) out, t := SubStr(t, 1, StrLen(t) - 3)
        return t out
    }

    ; "manual" -> "Manual."
    static _Cap(t) => StrUpper(SubStr(Trim(t), 1, 1)) SubStr(Trim(t), 2) "."

    ; Start announcement fields (what this run will do), from the current config.
    ; -> Array of Webhook.Field maps; inline ones show three per row.
    static StartFields(cfg) {
        ok := (on, detail := "") => (on ? Emoji.Check " On" : Emoji.Cross " Off") (on && detail != "" ? "`n" detail : "")
        F := []
        n := cfg.Get("General.sellEvery", 15)
        F.Push(Webhook.Field(Emoji.Fish " Fishing", ok(cfg.Get("General.fishing", 1), "sells every " n " catches"
            (cfg.Get("General.sellAll", 1) ? " (all fish)" : ""))))     ; the sell's own default (FishLogic.Settings)
        craft := cfg.Get("Craft.enabled", 1)
        pots := ""
        if craft {
            for p in StrSplit(cfg.Get("Craft.potions", "Lucky Potion"), ",", " `t")
                pots .= (pots = "" || p = "" ? "" : ", ") p
        }
        F.Push(Webhook.Field(Emoji.Alembic " Auto-craft", ok(craft, pots)))
        F.Push(Webhook.Field(Emoji.Scroll " Quests", ok(cfg.Get("quests.enabled", 1))))
        F.Push(Webhook.Field(Emoji.Cart " Merchants", ok(cfg.Get("merchant.enabled", 1), "Mari, Jester")))
        F.Push(Webhook.Field(Emoji.Potion " Potions", cfg.Get("General.dryRun", 1)
            ? Emoji.Shield " Dry run (none used)" : Emoji.Warn " LIVE (unlocked potions are used)"))
        evOn := cfg.Get("General.everyonePing", 1)
        biomes := ""
        if evOn {
            for b in StrSplit(cfg.Get("General.everyoneBiomes", BiomeEvents.EveryoneDefault), ",", " `t")
                biomes .= (b = "" ? "" : (biomes = "" ? "" : " " Chr(0xB7) " ") StrTitle(b))
        }
        F.Push(Webhook.Field(Emoji.Megaphone " @everyone", ok(evOn, biomes)))
        medal := cfg.Get("Medal.enabled", 0)
        F.Push(Webhook.Field(Emoji.Clapper " Clips", ok(medal, medal ? App._MedalDetail(cfg) : "")))
        F.Push(Webhook.Field(Emoji.Repeat " Auto-rejoin", ok(cfg.Get("recovery.enabled", 1))))
        F.Push(Webhook.Field(Emoji.Compass " Route", cfg.Get("General.vip", 1) ? "VIP" : "Standard"))
        return F
    }

    ; Big clickable invite line for an embed description (Discord does not
    ; render [text](url) links inside field values from webhooks).
    static DiscordLine => "## " Emoji.Chat " [Join our Discord](" Brand.DiscordUrl ")"

    ; What the Medal clips field lists, from config: key, rare biomes, aura rule.
    static _MedalDetail(cfg) {
        key := Trim(cfg.Get("Medal.clipHotkey", "") != "" ? cfg.Get("Medal.clipHotkey", "") : cfg.Get("Medal.hotkey", ""))
        L := []
        a := Clip.App(cfg.Get("Medal.app", "medal"))
        L.Push(a.id = "other" ? "Other app" : a.name)       ; the clip app (2026-11-16)
        if (key = "")
            key := a.key
        if (key != "")
            L.Push("Key " key)
        if cfg.Get("Medal.onRareBiome", 1)
            L.Push("rare biomes")
        if cfg.Get("Medal.onRareAura", 0) {
            s := Chr(0x2265) " 1 in " Auras.Format(Auras.MinRarity(cfg))
            cats := ""
            for c in StrSplit(cfg.Get("Medal.auraAlwaysCategories", Auras.DefaultAlways), ",", " `t")
                cats .= (c = "" ? "" : (cats = "" ? "" : ", ") c)
            L.Push("auras " s (cats != "" ? " + " cats : ""))
        }
        out := ""
        for line in L
            out .= (out = "" ? "" : "`n") line
        return out
    }

    ; Dashboard > Webhooks "Test" (row i of the SAVED list). Sends one message
    ; to that webhook only: no mention, no @everyone, ignores its enabled box
    ; and event boxes. Blocks (<= 8 s) until delivered or failed. Returns the
    ; page-status text (scrubbed: never a URL).
    OnTestWebhook(i) {
        hooks := this.cfg.Webhooks()
        if !(IsInteger(i) && i >= 1 && i <= hooks.Length)
            return "Test not sent: this webhook row is not saved yet. Save first."
        h := hooks[i]
        name := (h.Has("name") && Trim(h["name"]) != "") ? Trim(h["name"]) : "row " i
        if !(h.Has("url") && UiLogic.IsWebhookUrl(h["url"]))
            return "Test not sent: " name " has no valid Discord webhook URL. Paste one and Save."
        res := {ok: -1, why: ""}
        try {
            this.wh.SendTo(h, Emoji.Check " Webhook test"
                , "## Connected`nIf you can read this, **" name "** works. Sent by the Test button; nothing is routed from it.`n" App.DiscordLine, 0xF2A93B
                , {event: "test", done: (ok, why) => (res.ok := ok, res.why := why)})
            this.wh.Drain(8000)
        } catch Any as e {
            res.ok := 0
            res.why := App._ErrText(e)
        }
        if (res.ok = 1)
            msg := "Test sent to " name
        else if (res.ok = 0)
            msg := "Test failed for " name ": " res.why
        else
            msg := "Test queued for " name ", no answer yet (see the Log)"
        msg := UiLogic.Scrub(msg, this._Secrets())
        this.Log("Webhook test: " msg)
        return msg
    }

    _Error(text) {
        this.Log(UiLogic.Scrub(text, this._Secrets()))
        this._Send("errors", Brand.Name " error", text, 0xE74C3C)
    }

    ; Logs once per distinct text for a key (polling callers would spam).
    _Problem(key, text) {
        if (this._problems.Has(key) && this._problems[key] == text)
            return
        this._problems[key] := text
        this._Error(text)
    }

    _Secrets() {
        arr := []
        try {
            link := this.cfg.Get("General.privateServer", "")
            arr.Push(link)
            ; the share / link code alone is as secret as the whole link
            pos := 1
            while (pos := RegExMatch(link, "i)(?:code|privateServerLinkCode|linkCode)=([^&\s]+)", &m, pos)) {
                if (StrLen(m[1]) >= 6)
                    arr.Push(m[1])
                pos += m.Len
            }
        }
        try arr.Push(this.cfg.Get("Remote.token", ""))
        try {
            for w in this.cfg.Webhooks()
                arr.Push(w["url"])
        }
        return arr
    }

    _DryRun() => this.cfg.Get("General.dryRun", 1) ? true : false

    static _ErrText(e) => (e is Error) ? e.Message : String(e)

    ; " (Obby.ahk:812 in _Swap, x)" for a code error, so a log line points at
    ; it (the message alone named no variable or line, 2026-11-10)
    static _ErrWhere(e) {
        if !(e is Error)
            return ""
        f := ""
        try SplitPath(e.File, &f)
        w := ""
        try w := (f != "" ? f ":" e.Line : "") (e.What != "" ? " in " e.What : "") (e.Extra != "" ? ", " SubStr(String(e.Extra), 1, 40) : "")
        return (w != "") ? " (" w ")" : ""
    }

    ; ---- dashboard callbacks ----------------------------------------------------

    OnSaved(page) {
        if (page = "Remote")
            this._RemoteSetup()
        qi := this.cfg.Get("General.questIntervalMin", 30)
        if (IsInteger(qi) && qi > 0)
            this.state.questIntervalMs := qi * 60000
        this.state.obbyIntervalMs := Sched.ObbyIntervalFrom(this.cfg.Get("Obby.intervalMin", 10))
        if (page = "Craft")
            this._UseCalibration()
        ; fishing switched off while it runs: stop it now, not after the next
        ; sell (it only checks its switch before it starts; review)
        cur := this._running
        if (IsObject(cur) && cur.name = "fishing" && !cur.CanRun(this.state))
            this.ctx.RequestPreempt()
    }

    _UseCalibration() {
        try {
            this.calibrate.Use(this.root "\data\calibration.json", this.cfg)
            note := ""
            try note := this.calibrate.AutoNote
            if (note != "")
                this.Log("Calibration: " note)
        } catch Any as e {
            this._Error("Calibration: data\calibration.json could not be loaded (" App._ErrText(e) "); calibrated steps are skipped")
        }
    }

    ; ---- test events (dev only) --------------------------------------------------

    static TestBiome := "GLITCHED"
    static TestMerchant := "Mari"

    ; kind "biome" | "merchant" -> message for the UI (always a String).
    FakeEvent(kind) {
        if (this.cfg.Get("General.dryRun", 1) != 1)
            return this._TestRefused("dry run is OFF. Test events only run with dry run ON, so no potion can be used.")
        if !this._started
            return this._TestRefused("the macro is not running. Start it (F1) first; the scheduler handles the event.")
        if (kind = "biome" && this.state.rareActive)
            return this._TestRefused("a rare biome is active right now.")
        ts := "TEST-" FormatTime(, "yyyyMMddHHmmss") "-" Mod(this.Now(), 100000)
        prev := "", what := "", ev := ""
        switch kind {
            case "biome":
                prev := this.state.biome
                ev := Map("type", "biome", "name", App.TestBiome, "ts", ts, "live", 1, "test", 1)
                what := "fake " App.TestBiome " biome"
            case "merchant":
                ev := Map("type", "merchant", "name", App.TestMerchant, "ts", ts, "live", 1, "test", 1)
                what := "fake " App.TestMerchant " arrival"
            default:
                return this._TestRefused("unknown test event '" kind "'.")
        }
        this.Log("Test event: " what " (dry run)")
        this._testTag := true
        try {
            this.RouteEvent(ev)
        } finally {
            this._testTag := false
        }
        if (kind = "biome")
            this._fakeRestore := {biome: prev, ts: ts}
        return "Sent " what ". Webhooks are marked [TEST]."
    }

    ; Dev tools (2026-11-16): kind "sinister" | "aura" -> that alert sent to
    ; the webhook named hookName only, marked [TEST]; "disconnect" -> the
    ; running macro closes Roblox and rejoins (a real rejoin). -> message.
    FakeAlert(kind, hookName := "") {
        if (kind = "disconnect") {
            if !this._started
                return this._TestRefused("the macro is not running. Start it (F1) first.")
            if !(this._RecoveryOn() && HasMethod(this.recovery, "FakeDisconnect"))
                return this._TestRefused("auto-rejoin is off (Settings > General, Recovery).")
            if !this.recovery.FakeDisconnect()
                return this._TestRefused("auto-rejoin needs your private server link (Settings).")
            this.Log("Test event: fake disconnect (Dev tools)")
            return "Fake disconnect: the macro closes Roblox and rejoins your private server now. Watch the log."
        }
        hook := ""
        for w in this.cfg.Webhooks()
            if (w.Has("name") && w["name"] = hookName && w.Has("url") && Trim(w["url"]) != "")
                hook := w
        if !IsObject(hook)
            return this._TestRefused("pick a webhook with a saved URL first.")
        switch kind {
            case "sinister":
                rep := SinisterReport({webhook: this.wh, cfg: this.cfg, ghost: () => false, hook: hook, test: true
                    , log: (t) => this.Log(t)})
                if !rep.Spawn("TEST-" this.Now(), "p")
                    return this._TestRefused("the boss card was not sent (the log says why; a private server link is needed).")
                ; the dead edit 15 s later, as when the hunt sees it die
                this.timerFn.Call(() => rep.Killed("test"), -15000)
                this.Log("Test event: fake Sinister P. spawn to webhook " hookName)
                return "Sent a fake Sinister P. card to " hookName ". It changes to Boss Dead in 15 s."
            case "aura":
                name := ""
                try name := this.be.AuraAlertTo(hook)
                if (name = "")
                    return this._TestRefused("no aura in data\auras.json is as rare as the alert's threshold.")
                return "Sent a fake rare aura alert (" name ") to " hookName "."
        }
        return this._TestRefused("unknown test event '" kind "'.")
    }

    _TestRefused(why) {
        msg := "Test event refused: " why
        this.Log(msg)
        return msg
    }

    ; After a fake rare biome: once its potion pass is over (not pending, not
    ; running), put the previous biome back with a silent non-live event.
    ; A real biome event since then (rareTs changed) -> nothing to restore.
    _MaybeRestoreFake() {
        if !IsObject(this._fakeRestore)
            return
        if this._PotionsBusy()
            return
        p := this.potions
        pending := false
        try pending := IsObject(p) && p.CanRun(this.state)
        if pending
            return
        this._RestoreFake(false)
    }

    _RestoreFake(force) {
        fr := this._fakeRestore
        if !IsObject(fr)
            return
        this._fakeRestore := ""
        if (String(this.state.rareTs) !== fr.ts)
            return                              ; a real biome event replaced the fake one
        b := (Trim(fr.biome) = "") ? "NORMAL" : fr.biome
        try this.be.Handle(Map("type", "biome", "name", b, "ts", "", "live", 0, "test", 1))
        this.Log("Test event: biome state restored to " b)
    }

    ; ---- routes ---------------------------------------------------------------

    ; Dashboard > Tools "Record". Blocks while recording (watches keys only).
    ; One route tool at a time: a Record started during a Test took over its
    ; F3 handle (review).
    OnRecordRoute(name) {
        if this._toolBusy
            return {ok: false, msg: "a route record / test is already running", steps: [], routes: ""}
        this._toolBusy := true
        try {
            return this._RecordRoute(name)
        } finally {
            this._toolBusy := false
        }
    }

    _RecordRoute(name) {
        if this._started
            this.Stop("recording a route")
        if IsObject(this._running)
            return {ok: false, msg: "the macro is still finishing a task; press Record again in a moment", steps: [], routes: ""}
        ; start exactly where playback starts: the macro's own respawn
        ; (Esc, R, Enter + Aura Collections, which re-aims the camera); a
        ; Limbo route has no respawn (Input.NoRespawn): only the re-aim
        ob := "", sw := ""
        if (this._Window() = "ok" && this._FocusSettled()) {
            ctx := App.RouteTestCtx(() => this._Active())
            this._testCtx := ctx
            ok := false
            ob := this._SailorTask(name)
            if IsObject(ob) {
                this.Log("Route recorder: equipping Sailor first (the obby is walked with it on)")
                try sw := ob.PutOnSailor(ctx)
                if (IsObject(sw) && !sw.ok)
                    this.Log("Route recorder: could not equip Sailor (" sw.why "): equip it yourself before pressing " RouteRecorder.Key)
            }
            if Input.NoRespawn.Has(name) {
                this.Log(name = "fisher_to_fishing"
                    ? "Route recorder: no respawn: stand at Captain Flarg (dialog closed); re-aiming the camera (Aura Collections)"
                    : "Route recorder: no respawn in THE LIMBO: stand where the Portable Crack puts you; re-aiming the camera (Aura Collections)")
                ok := true
                if HasMethod(this.input, "ReAim")
                    try ok := this.input.ReAim(ctx)
            } else {
                this.Log("Route recorder: respawning first, so the recording starts like playback does")
                try ok := this._recRespawnFn.Call(ctx)
            }
            this._testCtx := ""
            if ctx.stopped {
                this._SailorOwed(ob, sw, "Route recorder")
                return {ok: false, msg: "cancelled (F3)", steps: [], routes: ""}
            }
            if !ok
                this.Log("Route recorder: the respawn did not finish; respawn yourself (Esc, R, Enter) before pressing " RouteRecorder.Key)
            cam := Input.CameraSteps(name)
            if (ok && cam.Length && HasMethod(this.input, "PlayRoute")) {
                this.Log("Route recorder: camera top-down, like playback does")
                try this.input.PlayRoute(cam, ctx)
            }
            ; the obby's start alignment (Obby.align / alignOffset), as its runs play it
            al := IsObject(ob) ? ObbyTask.AlignSteps(this.cfg) : []
            if (ok && al.Length && HasMethod(this.input, "PlayRoute")) {
                this.Log("Route recorder: the obby's start alignment first, like its runs")
                try this.input.PlayRoute(al, ctx)
            }
        } else {
            this.Log("Route recorder: Roblox is not open, fullscreen and focused: no automatic respawn; respawn yourself before pressing " RouteRecorder.Key)
        }
        res := this._recordFn.Call(name, this.root "\data\routes.json")
        if (res.ok && IsObject(res.routes))
            try this.cfg.SetData("routes", res.routes)
        this.Log("Route recorder: " res.msg)
        if (IsObject(ob) && IsObject(sw) && sw.ok && !sw.had && this._FocusSettled()) {
            this.Log("Route recorder: putting your aura back")
            ctx := App.RouteTestCtx(() => this._Active())
            this._testCtx := ctx
            try ob.PutBack(ctx, sw)
            this._testCtx := ""
        }
        return res
    }

    ; Sailor was put on for a route tool that ended before PutBack (F3,
    ; Roblox lost focus): the obby keeps the aura to put back on its next run,
    ; and the user is told (review: it was silently lost).
    _SailorOwed(ob, sw, who) {
        if !(IsObject(ob) && IsObject(sw) && sw.ok && !sw.had)
            return
        try ob.Owe(sw)
        this.Log(who ": Sailor stays on; " (sw.prev != "" ? sw.prev : "no aura") " goes back on the next obby run (or put it back yourself)")
    }

    ; The obby task when route `name` is walked with Sailor on, else "".
    _SailorTask(name) {
        if (name != "obby" || !this._taskMap.Has("obby"))
            return ""
        t := this._taskMap["obby"]
        return HasMethod(t, "PutOnSailor") ? t : ""
    }

    ; Dashboard > Tools "Test". Blocks while walking. -> {ok, msg}
    OnTestRoute(name) {
        if this._toolBusy
            return {ok: false, msg: "a route record / test is already running"}
        this._toolBusy := true
        try {
            return this._TestRoute(name)
        } finally {
            this._toolBusy := false
        }
    }

    _TestRoute(name) {
        if this._started
            this.Stop("testing a route")
        if IsObject(this._running)
            return {ok: false, msg: "the macro is still finishing a task; press Test again in a moment"}
        if IsObject(this._testCtx)
            return {ok: false, msg: "a route test is already running"}
        steps := this._RouteSteps(name)
        if !(steps is Array)
            return {ok: false, msg: steps}
        steps := Input.WithCamera(name, steps)          ; e.g. top-down for limbo_eden
        win := this._Window()
        if (win != "ok")
            return {ok: false, msg: (win = "notfs") ? "the Roblox window can't be used (minimized, too small or off the screen)" : "Roblox is not open"}
        if !this._FocusSettled()
            return {ok: false, msg: "Roblox did not take focus; click into it and press Test again"}
        key := RouteRecorder.InteractKey(name)
        ctx := App.RouteTestCtx(() => this._Active())
        this._testCtx := ctx
        this._ShiftOff(ctx)
        this._walkName := name
        ob := this._SailorTask(name)
        sw := ""
        this.Log("Route test '" name "': respawning, then walking " steps.Length " steps (F3 stops)")
        try {
            why := ""
            if IsObject(ob) {
                ; walked as it plays: with Sailor on (it walks on water)
                this.Log("Route test 'obby': equipping Sailor first")
                sw := ob.PutOnSailor(ctx)
                if !sw.ok
                    why := (sw.why = "stopped") ? "" : "could not equip Sailor: " sw.why
            }
            if (why = "" && !ctx.ShouldStop())
                why := this._walkFn.Call(steps, key, ctx)
        } catch Any as e {
            why := App._ErrText(e)
        } finally {
            if (IsObject(ob) && IsObject(sw) && sw.ok && !ctx.ShouldStop()) {
                try ob.PutBack(ctx, sw)
            } else {
                this._SailorOwed(ob, sw, "Route test 'obby'")
            }
            this._testCtx := ""
            try this.input.ReleaseAll()
        }
        if (why = "" && ctx.stopped)
            why := "stopped (F3)"
        else if (why = "" && ctx.ShouldStop())
            why := "stopped: Roblox lost focus"
        if (why != "") {
            this.Log("Route test '" name "': " why)
            return {ok: false, msg: why}
        }
        took := ""
        if (Input.LastRouteMs > 0)
            took := " in " Round(Input.LastRouteMs / 1000, 2) " s (recorded " Round(Input.RouteMs(steps) / 1000, 2) " s)"
        msg := "walked " steps.Length " steps" took (key != "" ? " and pressed " StrUpper(key) : "")
            . ". If the " (name = "quest_board" ? "quest board" : name = "cauldron" ? "cauldron" : "target") " opened, the route works. If not, record it again."
        this.Log("Route test '" name "': " msg)
        return {ok: true, msg: msg}
    }

    ; Validated steps, or the reason as a String.
    _RouteSteps(name) {
        r := ""
        try r := this.cfg.Data("routes")
        if (r is Map && r.Has("routes") && r["routes"] is Map)
            r := r["routes"]
        if !(r is Map && r.Has(name)) {
            b := RouteRecorder.BuiltinWalk(r, name, this.cfg.Get("General.vip", 1) != 0)
            return IsObject(b) ? b.steps : "not recorded yet: press Record first"
        }
        e := r[name]
        steps := (e is Map && e.Has("steps")) ? e["steps"] : e
        try {
            if (Input.ParseRoute(steps).Length > 0)
                return steps
        }
        return "not recorded yet (empty or broken): press Record again"
    }

    ; Default walkRoute: respawn (screen-checked; a Limbo route only re-aims
    ; the camera, Input.NoRespawn), walk, press the key.
    _WalkRoute(steps, key, ctx) {
        io := ""
        if Input.NoRespawn.Has(this._walkName) {
            if !this.input.ReAim(ctx, io)
                return ctx.ShouldStop() ? "" : "camera re-aim failed: " (Input.LastResetError != "" ? Input.LastResetError : "Aura Collections did not open")
        } else if !this.input.ResetToSpawn(ctx, io)
            return ctx.ShouldStop() ? "" : "respawn failed: " (Input.LastResetError != "" ? Input.LastResetError : "Esc, R, Enter did not work")
        al := (this._walkName = "obby") ? ObbyTask.AlignSteps(this.cfg) : []
        if (al.Length && !this.input.PlayRoute(al, ctx, io))
            return ""
        if !this.input.PlayRoute(steps, ctx, io)
            return ""
        if (key != "" && !ctx.ShouldStop())
            this.input.Key(key, 80, io)
        return ""
    }

    ; ctx for a route test: Stop() (F3) or Roblox losing focus stops it.
    class RouteTestCtx {
        __New(activeFn) {
            this._activeFn := activeFn
            this.stopped := false
        }
        Stop() => (this.stopped := true)
        ShouldStop() => this.stopped || !this._activeFn.Call()
    }

    OnCalibrate(ids) {
        if (this._started || IsObject(this._running)) {
            this.Log("Stop the macro (F3) before calibrating")
            return 0
        }
        if this._toolBusy
            return 0
        this._toolBusy := true
        try {
            return this.calibrate.Run(ids)
        } finally {
            this._toolBusy := false
        }
    }

    ; ---- boot, hotkeys, exit ----------------------------------------------------

    Boot(mode := "normal") {
        if (mode = "normal") {
            Theme.Cfg := this.cfg                               ; saved themes live next to settings.ini
            ThemeStore.Migrate(this.cfg)                        ; [UI] custom* (and theme=Custom) -> "My theme", once
            want := this.cfg.Get("UI.theme", "Moontide")
            lt := ThemeStore.LoadWhy(this.cfg, want)
            Theme.Apply(lt.theme)                               ; before any window
            line := ThemeStore.FallbackLine(want, lt.why != "" ? lt.why : Theme.ApplyWhy)
            if (line != "")
                this.Log(line)                                  ; spec 7: the log says why
            I18n.Use(this.cfg.Get("UI.lang", "en"))             ; texts are translated when made
        }
        this._fixOn := (mode = "normal")
        ; speed: every respawn with the quick waits, over at Roblox's respawn
        ; lines when the aura writes them (Input.FastReset)
        if (mode = "normal") {
            try {
                tail := RespawnTail()
                Input.SettledFn := () => tail.Poll()
                Input.RespawnSyncFn := () => tail.Sync()
            }
            Input.FastReset := true
            Input.DailyPointFn := (id) => Calibrate.Point(id)   ; Setup's daily_claim / daily_close
        }
        ; a new install (the setup wizard will show) starts in simple mode
        if (mode = "normal" && SetupWizard.ShouldShow(this.cfg) && !this.cfg.Get("UI.simple", 0)) {
            this.cfg.Set("UI.simple", 1)
            try this.cfg.Save()
        }
        this.ShowSplash(mode)
        try Screenshot.Cleanup()
        ; calibration first: the Dashboard's Calibrate list is built from it
        ; (the potion steps follow [Craft] potions; unbound it would list the
        ; built-in defaults, steps the wizard then refuses as unknown)
        if (this.calibrate == Calibrate)
            Calibrate.Logger := this._logFn
        this._UseCalibration()
        if !this._uiGiven
            this._BuildUi()
        this.FlushEarly()
        this.clip.Setup(this.cfg, this.wh, this._logFn, Map("stopFn", () => (!this._started || this.ctx.IsStopped())))
        OnExit(ObjBindMethod(this, "OnExitApp"))
        if IsObject(this.dash)
            OnMessage(0x0005, ObjBindMethod(this, "_OnSize"))      ; WM_SIZE: trim when minimized
        if (mode = "normal" && IsObject(this.dash)) {
            A_IconTip := Brand.Name " " Chr(0xB7) " " Credits.ByLine()
            A_TrayMenu.Add("Show " Brand.Name, (*) => this.dash.Show())
            A_TrayMenu.Default := "Show " Brand.Name
            this.dash.Show()
            this.overlay.Show()
        } else if (mode = "offscreen" && IsObject(this.dash)) {
            x := SysGet(76) + SysGet(78) + 200        ; right of the virtual desktop
            sz := this.dash.ShownSize()
            this.dash._gui.Show("x" x " y0 w" sz.w " h" sz.h " NoActivate")
            this.dash._shown := true
            this.overlay._gui.Show("x" (x + 1100) " y0 w" Overlay.W " h" Overlay.H " NoActivate")
            this.overlay._shown := true
        }
        this._Status()
        this.Log(Brand.Name " ready. F1 start, F2 pause/resume, F3 stop. Potion dry run " (this._DryRun() ? "ON" : "OFF"))
        this.CheckCredits()
        ; update check shortly after start, off the boot path (silent when [Update] repo is empty)
        if (mode = "normal" && this.Updater().Enabled)
            SetTimer(ObjBindMethod(this, "OnCheckUpdate", false), -2500)
        if (mode = "normal") {
            this.RefreshRollback()
            if (IsObject(this.dash) && FileExist(this.root "\" Updater.WhatsNewFile))
                SetTimer(ObjBindMethod(this, "ShowWhatsNew"), -800)
            this.StartServices()
            if (IsObject(this.dash) && SetupWizard.ShouldShow(this.cfg))
                SetTimer(ObjBindMethod(this, "OpenWizard"), -1500)
        }
    }

    ; ---- v1.6 services: stats, schedule, daily summary, Discord remote --------------

    ; Normal start only (tests build them by hand): the day counters, the
    ; schedule, the remote, and one 500 ms service timer that runs while the
    ; macro is stopped too.
    StartServices() {
        if !IsObject(this.daily) {
            this.daily := DailyStats(this.root "\data\stats.json")
            try this.daily.Load()
        }
        this.state.onBump := ObjBindMethod(this, "_DailyAdd")
        if !IsObject(this.sched)
            this.sched := RunSchedule(this.cfg, this.root "\data\schedule_state.txt")
        this._RemoteSetup()
        SetTimer(ObjBindMethod(this, "ServiceTick"), 500)
    }

    _DailyAdd(key, n) {
        if IsObject(this.daily)
            this.daily.Add(key, n)
    }

    ; Never throws (a timer). Remote polling waits while a timed walk plays:
    ; a request there would hold its key down longer (see _TickBody).
    ServiceTick() {
        now := A_TickCount
        if (IsObject(this.remote) && !Input.InRoute)
            this._ServiceStep("remote", () => this.remote.Tick())
        ; PUMPKIN MOON / GRAVEYARD: a stopped clock = a Sinister boss (no
        ; chat needed); never mid-walk (a read there stretches a key hold).
        ; Only while started: stopped, the log is not polled, so the biome is
        ; the last run's and a frozen clock (a disconnect, the title screen)
        ; would ping a boss that is not there
        if (IsObject(this.clock) && this._started && !Input.InRoute && this.cfg.Get("Limited.bossAlert", 1) && (this._Active() || (this._idle && Ocr.Win)))
            this._ServiceStep("clock", () => this.clock.Tick(this.state.biome))
        ; the run's tick sends Discord messages, but it only runs while the
        ; macro is started: stopped, Dev tools' fake alerts (and the dashboard's
        ; messages) sat in the queue (2026-11-16, "theres nothing in discord")
        if (!this._timerOn && !Input.InRoute && IsObject(this.wh))
            this._ServiceStep("webhooks", () => this.wh.Flush())
        if (now - this._svc["sched"] >= 15000) {
            this._svc["sched"] := now
            this._ServiceStep("schedule", () => this._ScheduleTick())
        }
        if (now - this._svc["sum"] >= 30000) {
            this._svc["sum"] := now
            this._ServiceStep("daily summary", () => this._SummaryTick())
        }
        if (now - this._svc["save"] >= 60000) {
            this._svc["save"] := now
            if IsObject(this.daily)
                this._ServiceStep("stats save", () => this.daily.Save())
        }
        if (now - this._svc["stats"] >= 3000) {
            this._svc["stats"] := now
            this._ServiceStep("stats page", () => this._StatsPageTick())
        }
        if IsObject(this._fixCard)                 ; package B: off the game, closed when the problem is gone
            this._ServiceStep("fix card", () => this._FixCardTick())
    }

    ; one service step; its first error of each kind is logged, never thrown
    _ServiceStep(what, fn) {
        try {
            fn.Call()
        } catch Any as e {
            k := what ": " e.Message
            if !this._svcErr.Has(k) {
                this._svcErr[k] := true
                try this.Log("Service " what " failed: " App._ErrText(e))
            }
        }
    }

    ; Run schedule: start (Roblox brought to the front first) / stop.
    _ScheduleTick() {
        if !IsObject(this.sched)
            return
        act := this.sched.Tick(A_Now, this._started, IsObject(this.daily) ? this.daily.RunMs() : 0)
        if (act = "start") {
            ; a route tool or a task still stopping refuses Start: no focus
            ; grab every 15 s (review 2026-11-12); told once, tried again
            if (this._toolBusy || IsObject(this._running)) {
                if !(this.HasOwnProp("_schedBusyTold") && this._schedBusyTold)
                    this.Log("Schedule: start time, but a route tool or the last task is still busy; starting when it is done")
                this._schedBusyTold := true
                return
            }
            this._schedBusyTold := false
            this.Log("Schedule: start time, starting")
            this._FrontRoblox()
            this._schedStarting := true
            try this.Start()
            this._schedStarting := false
        } else if (act = "stop") {
            this.Log("Schedule: stop time")
            this.Stop("schedule")
        }
    }

    ; Roblox to the front before a start that no key press made (schedule,
    ; Discord): Start pauses at once while another window is in front.
    _FrontRoblox() {
        if this._IdleOn()                       ; idle mode: Roblox may stay behind
            return
        try this.roblox.Focus(3)
    }

    ; ---- daily summary ----

    _SummaryPath() => this.root "\data\summary_last.txt"

    _SummaryLast() {
        try return Trim(FileRead(this._SummaryPath()))
        return ""
    }

    _SummaryTick() {
        if (IsObject(this.daily) && DailySummary.Due(this.cfg, A_Now, this._SummaryLast()))
            this.SendSummary(true)
    }

    ; Today's numbers to the webhooks with Stop (startstop) ticked. -> a line
    ; for the dashboard. scheduled (the daily time): the day counts as sent,
    ; even with no webhook (asked again tomorrow, not every 30 s). "Send one
    ; now" marks nothing, so tonight's summary still goes (review 2026-11-12).
    SendSummary(scheduled := false) {
        if !IsObject(this.daily)
            return "Not sent: the macro is not ready"
        today := FormatTime(A_Now, "yyyyMMdd")
        if scheduled {
            try {
                f := FileOpen(this._SummaryPath(), "w", "UTF-8-RAW")
                f.Write(today), f.Close()
            }
        }
        n := 0
        try n := this.wh.Route("startstop").Length
        if !n {
            this.Log("Daily summary: no webhook has Stop ticked (Discord & Clips > Discord)")
            return "Not sent: no webhook has Stop ticked (Discord & Clips > Discord)"
        }
        b := DailySummary.Build(this.daily.Day(), today)
        this._Send("startstop", b.title, b.desc, 0xF2A93B, b.fields)
        this.Log("Daily summary sent")
        return "Sent to " n " webhook" (n = 1 ? "" : "s")
    }

    ; ---- stats page ----

    static WithDerived(m) {
        out := (m is Map) ? m.Clone() : Map()
        try {
            for k, v in DailyStats.Derived(out)
                out[k] := v
        }
        return out
    }

    _StatsPageTick() {
        if !(IsObject(this.daily) && IsObject(this.dash) && this.dash._shown && this.dash.ActivePage = "Stats")
            return
        hist := ""
        if (A_TickCount - this._svc["hist"] >= 30000) {
            this._svc["hist"] := A_TickCount
            hist := []
            Loop 7 {
                ts := DateAdd(A_Now, 1 - A_Index, "Days")
                hist.Push({label: A_Index = 1 ? "Today" : FormatTime(ts, "ddd d MMM"), m: App.WithDerived(this.daily.Day(FormatTime(ts, "yyyyMMdd")))})
            }
        }
        all := "", since := ""
        if HasMethod(this.daily, "AllTime")
            all := App.WithDerived(this.daily.AllTime()), since := this.daily.Since()
        this.dash.SetStatsPage(App.WithDerived(this.daily.Day()), App.WithDerived(this.daily.Session()), hist, all, since)
    }

    ; ---- Discord remote ----

    _RemoteSetup() {
        this.remote := ""
        if !this.cfg.Get("Remote.enabled", 0)
            return
        r := DiscordRemote(this._RemoteDeps())
        if !r.Enabled {
            this.Log("Remote: needs the bot token, the channel id and at least one user id (Discord & Clips > Remote)")
            return
        }
        this.remote := r
        this.Log("Remote: listening for commands in your Discord channel")
    }

    _RemoteDeps() {
        c := this.cfg
        return Map("token", c.Get("Remote.token", ""), "channelId", Trim(c.Get("Remote.channel", "")), "allowedIds", c.Get("Remote.users", "")
            , "prefix", c.Get("Remote.prefix", "!"), "pollSec", c.Get("Remote.pollSec", 5)
            , "log", (t) => this.Log(RegExMatch(t, "i)^Remote:") ? t : "Remote: " t), "handlers", this._RemoteHandlers())
    }

    _RemoteHandlers() {
        return Map(
            "status", (args, msg) => this._RemoteStatus(),
            "stats", (args, msg) => this._RemoteStats(args),
            "start", (args, msg) => (this._FrontRoblox(), paused := this._started && this.ctx.IsPaused()
                , this.Start() ? (paused ? "Resumed." : "Started.") : this._started ? "Already running." : "Not started: see the log."),
            "stop", (args, msg) => (this.Stop("Discord") ? "Stopped." : "It was not running."),
            "pause", (args, msg) => (this.Pause() ? "Paused." : "It is not running."),
            "resume", (args, msg) => (this._FrontRoblox(), this.Resume() ? "Resumed." : "Not resumed: " (this._pauseReason != "" ? this._pauseReason : "it is not paused") "."),
            "screenshot", (args, msg) => this._RemoteShot(),
            "log", (args, msg) => this._RemoteLog())
    }

    _RemoteStatus() {
        st := !this._started ? "Stopped" : this.ctx.IsPaused() ? "Paused" : "Running"
        task := (this._pauseReason != "") ? this._pauseReason : IsObject(this._running) ? StrTitle(this._running.name) : ""
        up := this._started ? this.Now() - this._startedAt : 0
        t := "**" st "**" (task != "" ? " - " task : "")
        if (this.state.biome != "")
            t .= "`nBiome: " this.state.biome (this.state.rareActive ? " (rare)" : "")
        if this._started
            t .= "`nUptime: " DailyStats.Derived(Map("runMs", up))["uptimeText"]
        return t
    }

    ; "!stats" today's numbers, "!stats all" the all-time totals
    _RemoteStats(args := "") {
        if !IsObject(this.daily)
            return "No stats yet."
        if (StrLower(Trim(String(args))) = "all" && HasMethod(this.daily, "AllTime")) {
            since := this.daily.Since()
            b := DailySummary.Build(this.daily.AllTime(), "")
            t := "**All time**" (RegExMatch(since, "^\d{8}$") ? " (since " FormatTime(since "000000", "d MMM yyyy") ")" : "")
            for f in b.fields
                t .= "`n" f["name"] ": " f["value"]
            return t
        }
        b := DailySummary.Build(this.daily.Day(), FormatTime(A_Now, "yyyyMMdd"))
        t := "**Today**"
        for f in b.fields
            t .= "`n" f["name"] ": " f["value"]
        return t
    }

    _RemoteShot() {
        path := ""
        try path := Screenshot.Capture(this.roblox.Hwnd())
        return (path != "" && FileExist(path)) ? {text: "Screenshot", file: path} : "Roblox is not open."
    }

    _RemoteLog() {
        lines := []
        try {
            for ln in StrSplit(RTrim(this.dash.LogText(), "`r`n"), "`n")
                lines.Push(ln)
        }
        t := ""
        i := Max(1, lines.Length - 9)
        while (i <= lines.Length)
            t .= RTrim(lines[i], "`r") "`n", i++
        t := UiLogic.Scrub(t, this._Secrets(), true)
        t := StrReplace(t, "``", "'")            ; a backtick in a line would end the code block
        return (t = "") ? "The log is empty." : "``````" SubStr(t, -1800) "``````"
    }

    ; Dashboard "Test connection" with the saved settings (blocking, a button).
    OnTestRemote() {
        r := DiscordRemote(this._RemoteDeps())
        if !r.Enabled
            return "Not tested: save the bot token, the channel id and a user id first"
        res := r.Test()
        if (res.ok && IsObject(this.remote))
            try this.remote.Reset()
        return res.msg
    }

    ; Settings > Look "Apply": a new theme needs new windows, so the macro
    ; restarts (only while stopped: a run is never cut short for a colour).
    OnRestart() {
        if (this._started || IsObject(this._running)) {
            this.Log("Theme: stop the macro first (F3), then press Apply")
            return false
        }
        if this._toolBusy {
            this.Log("Theme: finish the route record / test first, then press Apply")
            return false
        }
        this.Log("Theme: restarting to show " Trim(String(this.cfg.Get("UI.theme", "Moontide"))))
        Reload()
        return true
    }

    ; ---- check & help, setup wizard ----

    OnCheckSetup() => SetupCheck.Run(this.cfg)

    OnLogBundle(shots := false) {
        rep := ""
        try rep := SetupCheck.Report(SetupCheck.Run(this.cfg))
        r := LogBundle.Make(this.root, Map("report", rep, "shots", shots ? true : false))
        if r.ok
            this.Log("Support zip made: " RegExReplace(r.path, "^.*\\"))
        return r
    }

    OpenWizard() {
        if !IsObject(this.dash)
            return
        ; an open wizard goes; a language picked there (saved in UI.lang, not
        ; yet shown) still restarts the window when the new one closes
        dropped := ""
        try dropped := this._wizard.Destroy()
        this._wizLang := dropped
        this._wizard := SetupWizard(this.cfg, Map("checkSetup", () => this.OnCheckSetup()
            , "lang", (code) => this._wizLang := code, "done", (f) => this._WizardDone(f)))
        this._wizard.Show(this.dash._gui)
    }

    _WizardDone(finished) {
        this._wizard := ""
        this.Log("Setup wizard " (finished ? "finished" : "skipped") (finished ? "" : " (Help > Check & help runs it again)"))
        for page in ["Settings", "Fishing", "Craft", "Quests", "Merchants", "Obby & Memory", "Webhooks"]
            try this.dash.RevertPage(page)
        ; a language picked in the wizard: the windows were built in the old
        ; one, so restart to show it (only while stopped, like Look > Apply)
        code := this._wizLang, this._wizLang := ""
        if (code != "") {
            if (this._started || IsObject(this._running) || this._toolBusy) {
                this.Log("Language " code " saved: it shows after the next start")
                return
            }
            this.Log("Language: restarting to show " code)
            Reload()
        }
    }

    ; ---- updates (lib\Updater.ahk) -----------------------------------------------

    ; The Updater (built once from [Update]; a dep "updater" replaces it in tests).
    Updater() {
        if !IsObject(this._updater) {
            c := this.cfg
            this._updater := Updater(Map("root", this.root
                , "repo", c.Get("Update.repo", ""), "check", c.Get("Update.check", 1), "auto", c.Get("Update.auto", 0)
                , "log", this._logFn, "isStopped", () => this._UpdateSafe()))
        }
        return this._updater
    }

    ; Installing is only safe while nothing runs.
    _UpdateSafe() => !this._started && !IsObject(this._running)

    ; Dashboard "Check for updates" (manual) and the start-up check (false).
    OnCheckUpdate(manual := true) {
        u := this.Updater()
        try {
            res := u.Check(manual)
            st := res["status"]
            if (st = "available") {
                if (u.auto && this._UpdateSafe())
                    return u.Install(res)
                if IsObject(this.dash)
                    this.dash.SetUpdate(res["version"])
            } else if (manual && IsObject(this.dash)) {
                this.dash.SetUpdate("", st = "uptodate" ? "Up to date (v" Brand.Version ")" : "Update check failed, see Log")
            }
        } catch Any as e {
            this.Log("Update check failed: " App._ErrText(e))
        }
    }

    ; Dashboard "Install".
    OnInstallUpdate() {
        u := this.Updater()
        if !(u.last is Map && u.last["status"] = "available")
            return
        res := u.Install(u.last)
        if (!res["ok"] && IsObject(this.dash))
            this.dash.SetUpdate("", res["msg"])
    }

    ; "What's new in vX" once after the updater put this version in
    ; (data\whatsnew.json; deleted when read, also when it is for another version).
    ; -> the Map shown, or "".
    ShowWhatsNew() {
        wn := ""
        try wn := Updater.TakeWhatsNew(this.root, Brand.Version)
        if !IsObject(wn)
            return ""
        this.Log("Updated to v" Brand.Version)
        if (IsObject(this.dash) && this.dash is Dashboard) {
            try this._whatsNew.Close()
            try {
                this._whatsNew := WhatsNewWindow(Brand.Version, wn["notes"])
                this._whatsNew.Show(this.dash._gui)
            } catch Any as e {
                this.Log("What's new: could not show it (" App._ErrText(e) ")")
            }
        }
        return wn
    }

    ; Dashboard "Go back to vX": shown only while a backup of the version
    ; before this update exists (backup\<ver>\manifest.json).
    RefreshRollback() {
        if !IsObject(this.dash)
            return
        ver := ""
        try {
            b := this.Updater().LastBackup()
            if IsObject(b)
                ver := b["from"]
        }
        try this.dash.SetRollback(ver)
    }

    ; Dashboard "Go back to vX" (after its Yes/No): only while stopped, like OnRestart.
    OnRollback() {
        if (this._started || IsObject(this._running)) {
            this.Log("Go back: stop the macro first (F3), then try again")
            return false
        }
        if this._toolBusy {
            this.Log("Go back: finish the route record / test first")
            return false
        }
        res := this.Updater().Rollback()
        if (!res["ok"] && IsObject(this.dash)) {
            this.dash.SetUpdate("", res["msg"])
            this.RefreshRollback()
        }
        return res["ok"]
    }

    ; Startup splash: blocks ~1.6 s, before the Dashboard exists. Normal mode only;
    ; the real Splash only when the app builds its own UI (not with a given ui / splash dep).
    ShowSplash(mode) {
        if (mode != "normal")
            return
        fn := this._splashFn
        if !IsObject(fn) {
            if this._uiGiven
                return
            fn := (o) => Splash.Show(o)
        }
        try fn.Call(Map("animations", String(this.cfg.Get("UI.animations", 1)) = "0" ? 0 : 1))
    }

    ; The creator by-line is always the first log line; the lines logged before
    ; the UI existed follow it.
    FlushEarly() {
        this.LogCreditLine()
        for t in this._early
            this.Log(t)
        this._early := []
    }

    LogCreditLine() {
        this.Log(Brand.Name " by " Credits.Name())
    }

    ; Banner on when Credits.Verify() fails (called with NO root, so it checks the
    ; compiled-in values) or the window's own credit text was changed (Dashboard.LiveCheck).
    CheckCredits() {
        if !IsObject(this.dash)
            return
        ok := false
        try ok := this._creditsFn.Call().ok
        this.dash.SetModified(!ok)
        this.dash.LiveCheck()
    }

    ; Dashboard minimized -> hand idle pages back to Windows (memory target
    ; spec 6). Pages are faulted back in when needed; no timer involved.
    _OnSize(wParam, lParam, msg, hwnd) {
        if (IsObject(this.dash) && hwnd = this.dash.Hwnd && wParam = 1)     ; SIZE_MINIMIZED
            App.TrimMemory()
    }

    static TrimMemory() {
        try DllCall("psapi\EmptyWorkingSet", "Ptr", DllCall("GetCurrentProcess", "Ptr"))
    }

    _BuildUi() {
        cb := Map(
            "start", () => this.Start(),
            "pause", () => this.TogglePause(),
            "stop", () => this.Stop("button"),
            "potionsChanged", () => this.OnPotionsChanged(),
            "saved", (page) => this.OnSaved(page),
            "calibrate", (ids) => this.OnCalibrate(ids),
            "recordRoute", (name) => this.OnRecordRoute(name),
            "testRoute", (name) => this.OnTestRoute(name),
            "testEvent", (kind) => this.FakeEvent(kind),
            "testAlert", (kind, hook) => this.FakeAlert(kind, hook),
            "testWebhook", (i) => this.OnTestWebhook(i),
            "checkUpdate", () => this.OnCheckUpdate(true),
            "installUpdate", () => this.OnInstallUpdate(),
            "rollback", () => this.OnRollback(),
            "checkSetup", () => this.OnCheckSetup(),
            "logBundle", (shots := false) => this.OnLogBundle(shots),
            "wizard", () => this.OpenWizard(),
            "sendSummary", () => this.SendSummary(),
            "testRemote", () => this.OnTestRemote(),
            "restart", () => this.OnRestart(),
            "close", () => (this.dash.Hide(), App.TrimMemory()))
        this.dash := Dashboard(this.cfg, cb)
        this.overlay := Overlay(this.cfg, Map("start", cb["start"], "pause", cb["pause"], "stop", cb["stop"]))
        this.ui := [this.dash, this.overlay]
    }

    ; F1-F24 only (never combos, letters or mouse buttons).
    static HotkeyName(v, default) {
        k := Trim(String(v))
        if RegExMatch(k, "i)^F([1-9]|1\d|2[0-4])$")
            return StrUpper(k)
        return default
    }

    ; -> Map start/pause/stop -> key; any duplicate -> all defaults.
    static HotkeyKeys(cfg) {
        keys := Map()
        seen := Map()
        for name in App.KeyNames {
            k := App.HotkeyName(cfg.Get("Hotkeys." name, App.KeyDefaults[name]), App.KeyDefaults[name])
            if seen.Has(k)
                return App.KeyDefaults.Clone()
            seen[k] := true
            keys[name] := k
        }
        return keys
    }

    InstallHotkeys() {
        keys := App.HotkeyKeys(this.cfg)
        fns := Map("start", (*) => this.Start(), "pause", (*) => this.TogglePause(), "stop", (*) => this.Stop("F3"))
        for name in App.KeyNames {
            try {
                Hotkey(keys[name], fns[name], "On")
            } catch {
                try {
                    Hotkey(App.KeyDefaults[name], fns[name], "On")
                    this.Log("Hotkey " keys[name] " could not be set; using " App.KeyDefaults[name])
                } catch Any as e {
                    this._Error("Hotkey for " name " could not be set (" App._ErrText(e) "); use the dashboard buttons")
                }
            }
        }
    }

    ; Added with OnExit (Input's ReleaseAll hook stays registered). -> 0.
    OnExitApp(reason := "", code := 0) {
        try {
            if this._started {
                this._started := false
                this.ctx.Stop()
                this._Send("startstop", "Macro stopped", "## Session summary`nStopped: app exited.", 0x0B2A5B
                    , this._StopFields(this.Now() - this._startedAt))
                if IsObject(this.daily)
                    try this.daily.StopSession()
            }
        }
        if IsObject(this.daily)
            try this.daily.Save()
        try this.clip.CancelAll()
        try this.input.ReleaseAll()
        try this.wh.Drain(3000)
        try Screenshot.Cleanup()
        return 0
    }

    ; ---- entry --------------------------------------------------------------------

    ; Vesper.ahk entry. args: none = normal run. Dev harness only:
    ;   /harness hidden|offscreen <holdMs>   boot, print memory, exit
    ;   (never starts the scheduler, installs no hotkeys, touches no window
    ;   but its own).
    static Main(root, args) {
        mode := "normal"
        holdMs := 1000
        if (args.Length && args[1] = "/harness") {
            mode := (args.Length > 1 && args[2] = "offscreen") ? "offscreen" : "hidden"
            if (args.Length > 2 && IsInteger(args[3]))
                holdMs := Integer(args[3])
            OnError((e, *) => (FileAppend(App.HarnessErrorText(e, App._harnessCfg) "`n", "*"), ExitApp(3)))
        }
        cfg := Config.Load(root)
        App._harnessCfg := cfg
        inst := App(Map("cfg", cfg, "root", root))
        inst.Boot(mode)
        if (mode = "normal") {
            ; display self-check (Vesper.ahk set the DPI awareness first)
            inst.Log("Display: DPI awareness " (Screen.dpiSet = "" ? "not set" : Screen.dpiSet)
                . ", main monitor " A_ScreenWidth "x" A_ScreenHeight " at " Screen.ScaleAt() "%, " Screen.HdrText())
            try {
                if (inst._Window() != "ok")
                    inst.Log("Display: Roblox is not open (or minimized) yet; it is checked again at F1")
            }
            inst.InstallHotkeys()
        }
        else
            inst._Harness(mode, holdMs)
        return inst
    }

    static _harnessCfg := ""

    ; Harness error line; message scrubbed (webhook URLs, roblox links and the
    ; configured secrets never reach stdout).
    static HarnessErrorText(e, cfg := "") {
        sec := []
        if IsObject(cfg) {
            try sec.Push(cfg.Get("General.privateServer", ""))
            try sec.Push(cfg.Get("Remote.token", ""))
            try {
                for w in cfg.Webhooks()
                    sec.Push(w["url"])
            }
        }
        msg := (e is Error) ? e.Message : String(e)
        line := (e is Error) ? e.Line : ""
        file := (e is Error) ? e.File : ""
        return "ERROR " UiLogic.Scrub(msg, sec) " | line " line " | " UiLogic.Scrub(file, sec)
    }

    _Harness(mode, holdMs) {
        out := (s) => FileAppend(s "`n", "*")
        out("VESPER BOOT OK mode=" mode " started=" (this._started ? 1 : 0) " tasks=" this._tasks.Length
            . " potions=" (IsObject(this.potions) ? 1 : 0) " dryRun=" this.cfg.Get("General.dryRun", 1))
        Sleep(holdMs // 2)
        out("MEM " (mode = "offscreen" ? "visible " : "idle ") App.MemLine())
        if (mode = "offscreen" && IsObject(this.dash)) {
            DllCall("ShowWindow", "Ptr", this.dash.Hwnd, "Int", 7)     ; SW_SHOWMINNOACTIVE
            Sleep(holdMs // 2)
            out("MEM minimized " App.MemLine())
        }
        out("VESPER EXIT OK")
        ExitApp(0)
    }

    static MemLine() {
        pmc := Buffer(A_PtrSize = 8 ? 72 : 40, 0)
        NumPut("UInt", pmc.Size, pmc, 0)
        DllCall("psapi\GetProcessMemoryInfo", "Ptr", DllCall("GetCurrentProcess", "Ptr"), "Ptr", pmc, "UInt", pmc.Size)
        ws := NumGet(pmc, A_PtrSize = 8 ? 16 : 12, "UPtr")
        priv := NumGet(pmc, A_PtrSize = 8 ? 56 : 32, "UPtr")
        return Format("ws={:.1f}MB private={:.1f}MB pid={}", ws / 1048576, priv / 1048576, DllCall("GetCurrentProcessId"))
    }
}
