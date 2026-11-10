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
#Include %A_LineFile%\..\tasks\BiomeItems.ahk
#Include %A_LineFile%\..\tasks\Obby.ahk
#Include %A_LineFile%\..\tasks\Minions.ahk
#Include %A_LineFile%\..\tasks\MemoryMatch.ahk
#Include %A_LineFile%\..\tasks\Limbo.ahk
#Include %A_LineFile%\..\tasks\Merchant.ahk
#Include %A_LineFile%\..\tasks\Recovery.ahk
#Include %A_LineFile%\..\tasks\Potions.ahk
#Include %A_LineFile%\..\Updater.ahk
#Include %A_LineFile%\..\ui\Dashboard.ahk
#Include %A_LineFile%\..\ui\Overlay.ahk
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
    ; tasks that leave you away from the fishing spot: the sell trip (back
    ; to the spot through the Fisher) runs next when fishing is on
    static MovesAway := Map("quests", 1, "obby", 1, "minions", 1, "merchant", 1, "memorymatch", 1)
    static DrainMs := 5000
    static Order := ["potions", "recovery", "merchant", "craft", "biomeitems", "quests", "obby", "memorymatch", "minions", "sell", "limbo", "fishing"]
    static KeyNames := ["start", "pause", "stop"]
    static KeyDefaults := Map("start", "F1", "pause", "F2", "stop", "F3")
    static Msg := Map(
        "missing", ["Roblox not found", "Roblox not found. Open Roblox fullscreen, then press F2."],
        "notfs", ["Roblox not fullscreen", "Moontide needs Roblox fullscreen (any resolution; windowed and minimized are not supported). Make it fullscreen, then press F2."],
        "unfocused", ["Roblox lost focus", "Roblox is not the active window (alt-tab?). Input stopped. Click into Roblox, then press F2."])

    ; Absolute repo dir (lib\App.ahk -> repo).
    static DefaultRoot() => RegExReplace(A_LineFile, "\\lib\\[^\\]+$")

    static _Dep(d, k, def := "") => d.Has(k) ? d[k] : def

    __New(deps) {
        d := (deps is Map) ? deps : Map()
        if !d.Has("cfg")
            throw ValueError("App: cfg is required")
        this.cfg := d["cfg"]
        this.root := App._Dep(d, "root", App.DefaultRoot())
        this.nowFn := App._Dep(d, "now", () => A_TickCount)
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
        this._running := ""
        this._startedAt := 0
        this._uptime := 0
        this._loops := 0
        this._lastLoops := 0
        this._lastPoll := ""
        this._pauseReason := ""
        this._note := ""
        this._display := ""          ; "Roblox 1920x1080 (x0.75): only 2560x1440 is verified so far"
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

        ; tasks
        this._taskMap := Map()
        if d.Has("tasks") {
            for name, t in d["tasks"]
                this._taskMap[name] := t
        } else {
            for name in ["recovery", "merchant", "craft", "biomeitems", "quests", "obby", "memorymatch", "minions", "sell", "limbo", "fishing"] {
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
                , onFound: ObjBindMethod(this, "_OnChatMerchant")})
        }
    }

    Now() => (this.nowFn).Call()
    TaskRunning() => IsObject(this._running)
    IsStarted() => this._started

    _DefaultTask(name) {
        cfg := this.cfg
        try {
            switch name {
                case "fishing": return FishingTask(cfg, this.state, {log: this._logFn})
                case "sell": return SellTask(cfg, this.state, {log: this._logFn, afterSell: (ctx) => this._AfterSell(ctx)
                    , stuck: (msg) => this._Error("Stuck: " msg), cal: Calibrate})
                case "craft": return CraftTask({cfg: cfg, webhook: this.wh, log: this._logFn})
                case "quests": return QuestsTask({cfg: cfg, webhook: this.wh, log: this._logFn})
                case "biomeitems": return BiomeItemsTask({cfg: cfg, webhook: this.wh, log: this._logFn})
                case "obby": return ObbyTask({cfg: cfg, webhook: this.wh, log: this._logFn, aura: () => this._AuraNow()})
                case "minions": return MinionsTask({cfg: cfg, webhook: this.wh, log: this._logFn, aura: () => this._AuraNow()
                    , biome: () => this._BiomeNow(), ghost: () => this._GhostNow()})
                case "memorymatch": return MemoryMatchTask({cfg: cfg, webhook: this.wh, log: this._logFn})
                case "merchant": return MerchantTask({cfg: cfg, webhook: this.wh, log: this._logFn})
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
        if this._everStarted {
            try {
                this.lw := this.lwFactory.Call()
            } catch Any as e {
                this._Error("LogWatch: could not restart (" App._ErrText(e) ")")
            }
        }
        this._everStarted := true
        this.ctx.Reset()
        this._started := true
        this._startedAt := this.Now()
        this._uptime := 0
        this._loops := 0
        this._lastLoops := this.state.fishLoops
        this.state.stats := Map()          ; this session's counters (stop summary)
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
        this.state.repathStreak := 0
        this.state.limboMode := this._LimboMode()
        if this.state.limboMode {
            this.Log("Limbo is on: using the Portable Crack and waiting for Eden (fishing, selling, crafting, quests and merchants are off)")
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
        ; One start message per ENABLED webhook (whatever its event boxes say),
        ; no mention, no @everyone. It replaces the old `startstop` start
        ; message, so a webhook never gets two. Stop still routes `startstop`.
        this._Broadcast(Emoji.Moon " " Brand.Name, "## Macro started`nMade by " Credits.Name() "`n" App.DiscordLine, 0xF2A93B, App.StartFields(this.cfg))
        this.CheckCredits()
        win := this._Window()
        if (win != "ok")
            this._PauseFor(win)
        this.timerFn.Call(this._tickFn, App.TickMs)
        this._timerOn := true
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
        try this.input.ReleaseAll()
        try this.clip.CancelAll()
        this.Log("Paused")
        this._Status()
        return true
    }

    Resume() {
        if !this._started
            return false
        win := this._Window()
        if (win != "ok") {
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
        this._ShiftOff()          ; a halted hunt can leave it on: other clicks would miss
        was := this._started
        this._started := false
        this._pauseReason := ""
        this._note := ""
        try this._RestoreFake(true)
        if was {
            this._uptime := this.Now() - this._startedAt
            this.Log("Stopped (" why ")")
            this._Send("startstop", "Macro stopped", "## Session summary`nStopped: " App._Cap(why), 0x0B2A5B, this._StopFields(this._uptime))
        }
        this._Status()
        return was
    }

    _PauseFor(kind) {
        m := App.Msg[kind]
        if (this._pauseReason != m[1])
            this.Log("Paused: " m[2])
        this._pauseReason := m[1]
        this.ctx.Pause()
        try this.input.ReleaseAll()
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
        if !walking
            try this.wh.Flush()
        this._TrackLoops()
        this._MaybeRestoreFake()
        if (!this._started || this.ctx.IsStopped()) {
            if !IsObject(this._running)
                this._Finish()
            this._Status()
            return
        }
        win := this._Window()
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
        if (IsObject(nxt) && nxt !== cur && nxt.priority < cur.priority) {
            this.ctx.RequestPreempt()
            this.Log(StrTitle(cur.name) ": interrupted for " StrTitle(nxt.name))
        }
    }

    _LimboMode() => (this._taskMap.Has("limbo") && this.cfg.Get("Limbo.enabled", 0)) ? true : false

    _Pick(now, win) {
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
                    this._note := "Idle"
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
                this._note := "Idle"
            return
        }
        this._note := ""
        this._Launch(nxt)
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
            ; shift lock on makes every UI click miss (live 2026-11-02: a
            ; click at the screen centre opened the Donation prompt): not
            ; confirmed off after one more try -> the task is skipped
            if (!this._ShiftOff(this.ctx) && !this._ShiftOff(this.ctx)) {
                skipped := true
                ; skipped again and again: wait longer each time (5 s, 10 s
                ; ... up to SkipHoldMaxMs), not a retry every 7 s all night
                this._skipStreak := (this.HasOwnProp("_skipStreak") ? this._skipStreak : 0) + 1
                this._holdUntil := this.Now() + Min(App.ErrorHoldMs * (2 ** Min(this._skipStreak - 1, 6)), App.SkipHoldMaxMs)
                if !this.ctx.ShouldStop()
                    this.Log(StrTitle(task.name) ": shift lock may still be on - skipped (no click)")
                return
            }
            this._skipStreak := 0
            task.Run(this.ctx)
        } catch Any as e {
            failed := true
            this._holdUntil := this.Now() + App.ErrorHoldMs
            this._Error(StrTitle(task.name) ": error: " App._ErrText(e))
        } finally {
            how := this._EndHow(failed)
            this.Log("task: " task.name " end" (how != "" ? " (" how ")" : ""))
            if !skipped
                try this._Tidy(task)
            this.state.busy := ""
            if (task.name = "sell" && !skipped)
                this.state.startSell := false      ; the start sell happened (or failed): buying may follow
            ; the board run ends at spawn: go back through the Fisher (sell +
            ; buy if due) to the fishing spot right away, instead of fishing
            ; failing to find its panel first
            ; the same after every task that walks away from the fishing spot
            ; (live 2026-11-10: after minions / obby / merchant fishing
            ; looked for its panel, failed, saved a screen, then re-pathed)
            if (App.MovesAway.Has(task.name) && !skipped && this._taskMap.Has("sell") && this.cfg.Get("General.fishing", 1))
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
        if !this.cfg.Get("merchant.enabled", 1)
            return
        if !this._Active()
            return
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
        if (!IsObject(this.chat) || !this.cfg.Get("merchant.enabled", 1) || this.state.rareActive || this._LimboMode())
            return false
        try {
            if !IsObject(this.calibrate.Rect("chat_rect"))
                return false                    ; not calibrated: ChatWatch would read nothing
        }
        return true
    }

    _ChatPollMs() {
        s := this.cfg.Get("merchant.chatPollSec", ChatWatch.DefaultPollSec)
        if (!IsNumber(s) || s < 1)
            s := ChatWatch.DefaultPollSec
        return Round(s * 1000)
    }

    _OnChatMerchant(name) {
        if IsObject(this.merchant)
            try this.merchant.Notify(name)
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

    ; "ok" | "missing" | "notfs" (windowed / minimized). "ok" also refreshes
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
        this._display := this.roblox.Verified() ? "" : "Roblox " this.roblox.SizeText() ": only 2560x1440 is verified so far"
    }

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
        return n
    }

    RouteEvent(ev) {
        try {
            type := ev["type"]
            if (type = "biome" || type = "aura") {
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
        d := RecoveryTask.GhostDecision(ev["name"], this.state, this.cfg)
        if (d = "clear") {
            this.state.ghost := false
        } else if (d = "ghost" && !this.state.ghost) {
            this.state.ghost := true
            this.Log("Ghost server: the game moved you to a server your friends can't join; rejoining your private server")
        }
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

    _Status() {
        st := !this._started ? "Stopped" : this.ctx.IsPaused() ? "Paused" : "Running"
        if (this._pauseReason != "")
            task := this._pauseReason
        else if IsObject(this._running)
            task := StrTitle(this._running.name)
        else
            task := this._started ? this._note : ""
        if (this._display != "" && (task = "" || task = "Idle"))
            task := (task = "" ? "" : task ". ") this._display
        up :=this._started ? this.Now() - this._startedAt : this._uptime
        biome := this.state.biome
        rare := this.state.rareActive ? true : false
        stats := (this.state.HasProp("stats") && this.state.stats is Map) ? this.state.stats : Map()
        for u in this.ui {
            try u.SetStatus(st, task, biome, rare, up, this._loops)
            if HasMethod(u, "SetStats")            ; Dashboard Home tiles (cheap when unchanged)
                try u.SetStats(stats)
        }
    }

    ; Every log line also goes to <root>\logs\macro.log (date, time, secrets
    ; scrubbed): the dashboard keeps its log only in memory, so after a bad
    ; run there was nothing to read back (2026-10-27). Moved to
    ; macro.old.log past LogFileMax.
    static LogFileMax := 1048576
    _LogFile(text) {
        if (this.root = "")
            return
        try {
            dir := this.root "\logs"
            if !DirExist(dir)
                DirCreate(dir)
            path := dir "\macro.log"
            if (FileExist(path) && FileGetSize(path) > App.LogFileMax)
                FileMove(path, dir "\macro.old.log", 1)
            FileAppend(FormatTime(, "yyyy-MM-dd ") UiLogic.LogLine(text, this._Secrets()) "`n", path, "UTF-8")
        }
    }

    Log(text) {
        this._LogFile(text)
        if (this.ui.Length = 0) {
            if (this._early.Length < 100)
                this._early.Push(text)
            return
        }
        for u in this.ui
            try u.Log(text)
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
            (cfg.Get("General.sellAll", 0) ? " (all fish)" : ""))))
        craft := cfg.Get("Craft.enabled", 1)
        pots := ""
        if craft {
            for p in StrSplit(cfg.Get("Craft.potions", "Lucky Potion,Speed Potion"), ",", " `t")
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
        F.Push(Webhook.Field(Emoji.Clapper " Medal clips", ok(medal, medal ? App._MedalDetail(cfg) : "")))
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
        try arr.Push(this.cfg.Get("General.privateServer", ""))
        try {
            for w in this.cfg.Webhooks()
                arr.Push(w["url"])
        }
        return arr
    }

    _DryRun() => this.cfg.Get("General.dryRun", 1) ? true : false

    static _ErrText(e) => (e is Error) ? e.Message : String(e)

    ; ---- dashboard callbacks ----------------------------------------------------

    OnSaved(page) {
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
            return {ok: false, msg: (win = "notfs") ? "Roblox is not fullscreen" : "Roblox is not open"}
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
        if !(r is Map && r.Has(name))
            return "not recorded yet: press Record first"
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
            this.dash._gui.Show("x" x " y0 w" Dashboard.W " h" Dashboard.H " NoActivate")
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
            "testWebhook", (i) => this.OnTestWebhook(i),
            "checkUpdate", () => this.OnCheckUpdate(true),
            "installUpdate", () => this.OnInstallUpdate(),
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
            }
        }
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
                . ", main monitor " A_ScreenWidth "x" A_ScreenHeight " at " Screen.ScaleAt() "%")
            try {
                if (inst._Window() != "ok")
                    inst.Log("Display: Roblox is not open fullscreen yet; it is checked again at F1")
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
