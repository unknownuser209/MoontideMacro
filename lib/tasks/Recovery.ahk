#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\TaskEnv.ahk
#Include %A_LineFile%\..\..\Auras.ahk
; ---------------------------------------------------------------------------
; RecoveryTask: rejoin the private server, anti-AFK, stuck reset (spec 4.8).
;
;   t := RecoveryTask(deps)   deps as TaskEnv (cfg, webhook, log, io, cal,
;                             pixel, now) plus, all optional:
;     hwnd    callable hwnd() -> window id or 0   (default Roblox.Hwnd)
;     active  callable active() -> bool, Roblox window focused
;                                                 (default WinActive on it)
;     run     callable run(link)                  (default AHK Run)
;     focus   callable focus() -> bool, bring Roblox to the foreground
;                                                 (default Roblox.Focus)
;     close   callable close() -> bool, close the Roblox client (default:
;             WinClose, then ProcessClose RobloxPlayerBeta.exe after 10 s)
;   t.name = "recovery", t.priority = 2   (Scheduler task contract)
;
; CanRun(state) is true when ANY of (checked in this order):
;   1. DISCONNECTED: no Roblox window, or Roblox's disconnect screen is up:
;      OCR of DiscBox (screen centre, read at most every DiscPollMs) matches
;      DiscRe ("Disconnected", "lost connection", "Error Code", "kicked").
;      There is no Reconnect button to press: the client is closed and the
;      private server link opened again. Only while the rejoin hold (below)
;      has passed.
;   1b. GHOST SERVER: state.ghost (App sets it from LogWatch "join" events
;      through GhostDecision: the game moved the player to a server the
;      private server link does not reach, so nobody can join). Handled like
;      a disconnect: the client is closed and the link opened again; a
;      successful rejoin clears state.ghost. Same rejoin limits and hold.
;   2. STUCK: Roblox is up and no fishing progress for Recovery.stuckMin
;      minutes (default 10). Never while General.fishing = 0.
;   3. ANTI-AFK: Roblox is up AND focused, state.busy == "" (truly idle:
;      deferred while any task, fishing included, is running) and Recovery.afkMin minutes
;      (default 15) passed since the last tap / rejoin / first observation.
;   Disabled with Recovery.enabled=0.
;
; Run(ctx) does the first reason that applies; -> 1 if it acted, else 0.
;   Rejoin: link = cfg General.privateServer (SECRET: never logged, sent or
;     put in an error text; AHK's own Run error text contains it, so it is
;     never used either). Empty -> log + errors webhook once, then hold
;     RetryMs. Not starting with https://www.roblox.com/ (or containing
;     whitespace / quotes / <>`\|^) -> refused, same handling, value not
;     logged. At most Recovery.maxRejoins (3) Run(link) calls per
;     Recovery.rejoinWindowMin (10) minutes; beyond that: errors webhook
;     (once until a rejoin works), no pause, and no more attempts until the
;     oldest one leaves the window. On the disconnect screen the old client is closed first
;     (close(), then wait up to CloseWaitMs for the window to go). Then
;     Run(link), wait up to WindowWaitMs (90 s, polled, aborts on
;     ctx.ShouldStop) for the window, wait Recovery.loadSec (20) for the game
;     to load, Roblox.Focus, Input.ResetToSpawn. Timeout -> errors webhook,
;     hold RetryMs.
;   Stuck: Roblox.Focus, Input.ResetToSpawn, then errors webhook and progress
;     clock restart (an aborted/unfocused reset does neither); the
;     scheduler re-paths (fishing resumes by itself).
;   Anti-AFK: one Space tap via Input.Key.
;   ReturnToIsland(ctx): LimboTask leaving THE LIMBO: the running client is
;     closed and the private server joined again (same limits as a rejoin).
;   Any successful rejoin clears state.inLimbo (a fresh join is on Sol's
;   Island).
;
;   Keys/clicks are NEVER sent unless Roblox took focus: if focus fails the
;   action is skipped, logged, one errors webhook (once per key), hold RetryMs.
;
; PROGRESS (stuck detection) is observed in CanRun: state.busy names a task
;   other than "fishing"/"recovery" (a long craft/quest/merchant is never
;   stuck), or state.fishLoops changed
;   (it also resets to 0 on sell: still progress) or the newest
;   state.lastRun stamp of any task other than "recovery" changed (a task
;   completed). RecoveryTask writes state.progressAt (ms; see SchedState).
;   If CanRun was not polled for GapMs (2 min: macro paused, or one long
;   task) the clock is restarted, so unpausing never causes a false reset.
;   Run() uses the state object most recently passed to CanRun.
;
;   ROBLOX UPDATE: a rejoin after a Roblox update starts the launcher /
;   installer, which downloads the update before any game window exists. While
;   no window is up and one of RecoveryTask.Launchers is running, the window
;   wait keeps going (that time does not count toward WindowWaitMs: no failed
;   rejoin, no second Run(link)), for at most UpdateMaxMs (10 min) in total;
;   logged once as "Roblox is updating - waiting for it to finish". Dep
;   procs(name) -> bool, a process with that name runs (default ProcessExist).
; ---------------------------------------------------------------------------

class RecoveryTask {
    static WindowWaitMs := 90000
    static UpdateMaxMs := 600000    ; most time a Roblox update may add to the window wait
    static TitleWaitMs := 30000    ; past loadSec: the title screen shows within this
    static TitlePollMs := 1000
    static Launchers := ["RobloxPlayerInstaller.exe", "RobloxPlayerLauncher.exe", "Bloxstrap.exe", "Fishstrap.exe", "Voidstrap.exe"]
    static RetryMs := 60000         ; hold after a failed/refused rejoin
    static GapMs := 120000
    static PixelTol := 30
    static AfkKey := "Space"
    static LinkPrefix := "https://www.roblox.com/"
    static DiscBox := {x: 780, y: 420, w: 1000, h: 560}     ; centre of a 2560x1440 screen
    static DiscRe := "i)\bdisconnected\b|lost connection|error code|\bkicked\b|shut ?down"
    static DiscPollMs := 5000
    static CloseWaitMs := 10000

    name := "recovery"
    priority := 2

    __New(deps := "") {
        this._env := TaskEnv(deps)
        this._hwndFn := TaskEnv.Dep(deps, "hwnd", "")
        if !IsObject(this._hwndFn)
            this._hwndFn := () => Roblox.Hwnd()
        this._activeFn := TaskEnv.Dep(deps, "active", "")
        if !IsObject(this._activeFn)
            this._activeFn := () => (h := Roblox.Hwnd()) && WinActive("ahk_id " h)
        this._runFn := TaskEnv.Dep(deps, "run", "")
        if !IsObject(this._runFn)
            this._runFn := (target) => Run(target)
        this._focusFn := TaskEnv.Dep(deps, "focus", "")
        if !IsObject(this._focusFn)
            this._focusFn := () => Roblox.Focus()
        this._procsFn := TaskEnv.Dep(deps, "procs", "")
        if !IsObject(this._procsFn)
            this._procsFn := (name) => ProcessExist(name) ? true : false
        this._closeFn := TaskEnv.Dep(deps, "close", "")
        if !IsObject(this._closeFn)
            this._closeFn := () => RecoveryTask._CloseRoblox()
        this._discAt := ""          ; env.Now() of the last disconnect-screen read
        this._discSeen := false     ; disconnect screen seen, not yet handled
        this._ghostTold := false    ; the ghost server webhook was sent for this ghost
        this._state := ""
        this._seen := false
        this._lastObs := 0
        this._lastLoops := 0
        this._lastStamp := 0
        this._afkAt := 0
        this._holdUntil := 0
        this._attempts := []        ; ms of each Run(link) call
        this._limitTold := false    ; the rejoin limit was reported (until a rejoin works)
        this._leaving := false      ; ReturnToIsland: close the healthy client too
        this._ghosting := false     ; rejoining out of a ghost server: close its client too
    }

    ; A LogWatch join kind ("private" | "other") -> "ghost" | "clear" | ""
    ; (no change). Off with Recovery.antiGhost=0; never while Limbo is on or
    ; the player is in THE LIMBO (the Portable Crack is a teleport too).
    static GhostDecision(kind, state, cfg) {
        if (kind = "private")
            return "clear"
        if (kind != "other")
            return ""
        if IsObject(cfg) && (!cfg.Get("recovery.antiGhost", 1) || cfg.Get("Limbo.enabled", 0))
            return ""
        if (IsObject(state) && HasProp(state, "inLimbo") && state.inLimbo)
            return ""
        return "ghost"
    }

    _Ghost(state) => IsObject(state) && HasProp(state, "ghost") && state.ghost

    ; LimboTask: back to Sol's Island by rejoining. -> true when back.
    ReturnToIsland(ctx) {
        this._leaving := true
        try {
            return this._Rejoin(ctx) ? true : false
        } finally {
            this._leaving := false
        }
    }

    ; ---- config ----------------------------------------------------------

    _Cfg(key, default) {
        env := this._env
        v := IsObject(env.cfg) ? env.cfg.Get("recovery." key, default) : default
        return (IsInteger(v) && v > 0) ? Integer(v) : default
    }

    _Link() {
        env := this._env
        v := IsObject(env.cfg) ? env.cfg.Get("General.privateServer", "") : ""
        return Trim(String(v))
    }

    ; Pure: is this link acceptable to hand to Run()?
    static LinkOk(link) {
        return (StrLen(link) > StrLen(RecoveryTask.LinkPrefix)
            && SubStr(link, 1, StrLen(RecoveryTask.LinkPrefix)) = RecoveryTask.LinkPrefix
            && !RegExMatch(link, "[\s`"<>``\\|^]"))
    }

    ; ---- Scheduler contract ------------------------------------------------

    CanRun(state) {
        env := this._env
        if IsObject(env.cfg) && !env.cfg.Get("recovery.enabled", 1)
            return false
        this._state := state
        now := env.Now()
        this._Observe(state, now)
        if this._Disconnected()
            return now >= this._holdUntil
        ; a ghost server can only be left with a usable private server link:
        ; without one the task interrupted fishing every minute only to
        ; refuse (review). Told once.
        if this._Ghost(state) {
            if !RecoveryTask.LinkOk(this._Link()) {
                env.Problem("recovery:ghostnolink", "recovery: you are in a server your friends can't join, but there is no usable private server link (Settings) to rejoin with")
                return false
            }
            return now >= this._holdUntil
        }
        if (now >= this._holdUntil && this._Stuck(state, now))
            return true
        return this._AfkDue(now)
    }

    Run(ctx) {
        env := this._env
        state := this._state
        now := env.Now()
        if this._Disconnected()
            return this._Rejoin(ctx) ? 1 : 0
        if this._Ghost(state) {
            msg := "ghost server: the game moved you to a server your friends can't join (a teleport, not your private server link): rejoining your private server"
            env.Log("recovery: " msg)
            if !this._ghostTold                 ; once per ghost, not per retry
                env.Report("errors", "Ghost server", msg, 0xF2A93B)
            this._ghostTold := true
            this._ghosting := true
            try {
                ok := this._Rejoin(ctx)
            } finally {
                this._ghosting := false
            }
            if ok
                state.ghost := false, this._ghostTold := false
            return ok ? 1 : 0
        }
        if (IsObject(state) && this._Stuck(state, now)) {
            msg := "no fishing progress for " this._Cfg("stuckMin", 10) " min: reset to spawn"
            env.Log("recovery: " msg)
            if !this._FocusOk()
                return 0
            if !Input.ResetToSpawn(ctx, env.io) {
                env.Log("recovery: stuck reset aborted")
                return 0
            }
            env.Report("errors", "Recovery: stuck", msg)
            state.progressAt := env.Now()
            this._afkAt := env.Now()
            return 1
        }
        if this._AfkDue(now) {
            this._afkAt := now
            Input.Key(RecoveryTask.AfkKey, 50, env.io)
            return 1
        }
        return 0
    }

    ; ---- detection -----------------------------------------------------------

    _Observe(state, now) {
        busy := HasProp(state, "busy") ? state.busy : ""
        loops := HasProp(state, "fishLoops") ? state.fishLoops : 0
        stamp := 0
        if HasProp(state, "lastRun") && (state.lastRun is Map) {
            for name, ms in state.lastRun {
                if (name != "recovery" && IsNumber(ms) && ms > stamp)
                    stamp := ms
            }
        }
        if !this._seen {
            this._seen := true
            this._afkAt := now
            state.progressAt := now
        } else if (now - this._lastObs > RecoveryTask.GapMs) {
            state.progressAt := now          ; paused / long task: restart clock
        } else if (busy != "" && busy != "fishing" && busy != "recovery") {
            state.progressAt := now          ; another task is working
        } else if (loops != this._lastLoops || stamp != this._lastStamp) {
            state.progressAt := now
        } else if (!HasProp(state, "progressAt") || state.progressAt = 0) {
            state.progressAt := now
        }
        this._lastLoops := loops
        this._lastStamp := stamp
        this._lastObs := now
    }

    _Disconnected() {
        if !(this._hwndFn)()
            return true
        return this._DiscScreen()
    }

    ; Roblox's disconnect screen (read at most every DiscPollMs; a hit is
    ; kept until a rejoin handles it).
    _DiscScreen() {
        env := this._env
        if this._discSeen
            return true
        ; this runs from CanRun on the App's tick: a 1000x560 OCR there froze
        ; a walk mid-route with a key held (review). A route is not walked on
        ; a disconnect screen anyway.
        if Input.InRoute
            return false
        now := env.Now()
        if (this._discAt !== "" && now - this._discAt < RecoveryTask.DiscPollMs)
            return false
        this._discAt := now
        b := RecoveryTask.DiscBox
        t := ""
        try t := (env.ocrFn)(b.x, b.y, b.w, b.h)
        if RegExMatch(t, RecoveryTask.DiscRe) {
            this._discSeen := true
            env.Log("recovery: Roblox shows a disconnect screen")
        }
        return this._discSeen
    }

    static _CloseRoblox() {
        h := Roblox.Hwnd()
        if !h
            return true
        pid := 0
        try pid := WinGetPID("ahk_id " h)
        try WinClose("ahk_id " h)
        if WinWaitClose("ahk_id " h, , 10)
            return true
        ; the process that owns the window: Roblox runs two
        ; RobloxPlayerBeta.exe, and closing "the" one by name could hit the
        ; small helper and leave the game window up (live 2026-11-11 15:23:
        ; "the old Roblox window did not close")
        if pid
            try ProcessClose(pid)
        if Roblox.Hwnd()
            try ProcessClose("RobloxPlayerBeta.exe")
        return !Roblox.Hwnd()
    }

    _Stuck(state, now) {
        env := this._env
        if (IsObject(env.cfg) && (!env.cfg.Get("General.fishing", 1) || env.cfg.Get("Limbo.enabled", 0)))
            return false                    ; not fishing (or waiting in Limbo): idle is normal
        if !HasProp(state, "progressAt") || state.progressAt = 0
            return false
        return now - state.progressAt >= this._Cfg("stuckMin", 10) * 60000
    }

    _AfkDue(now) {
        if (IsObject(this._state) && HasProp(this._state, "busy")
            && this._state.busy != "" && this._state.busy != "recovery")
            return false
        if (now - this._afkAt < this._Cfg("afkMin", 15) * 60000)
            return false
        return (this._activeFn)() ? true : false
    }

    ; Roblox must own the keyboard before any key/click. -> false (hold, once-
    ; per-key errors webhook) when it does not.
    _FocusOk() {
        env := this._env
        ok := false
        try ok := (this._focusFn)() ? true : false
        if !ok {
            this._holdUntil := env.Now() + RecoveryTask.RetryMs
            env.Problem("recovery:focus", "recovery: could not focus the Roblox window: no keys sent")
        }
        return ok
    }

    ; A Roblox launcher / installer is running (the update is downloading).
    _Updating() {
        for name in RecoveryTask.Launchers {
            running := false
            try running := (this._procsFn)(name) ? true : false
            if running
                return true
        }
        return false
    }

    ; ---- rejoin ---------------------------------------------------------------

    ; -> true when the window is back and the game was reset to spawn.
    _Rejoin(ctx) {
        env := this._env
        link := this._Link()
        if (link = "") {
            this._holdUntil := env.Now() + RecoveryTask.RetryMs
            env.Problem("recovery:nolink", "recovery: no private server link set (General.privateServer): cannot rejoin")
            return false
        }
        if !RecoveryTask.LinkOk(link) {
            this._holdUntil := env.Now() + RecoveryTask.RetryMs
            env.Problem("recovery:badlink", "recovery: private server link refused (not an https roblox.com link): cannot rejoin")
            return false
        }

        now := env.Now()
        winMs := this._Cfg("rejoinWindowMin", 10) * 60000
        fresh := []
        for t in this._attempts {
            if (now - t < winMs)
                fresh.Push(t)
        }
        this._attempts := fresh
        ; overnight review: this used to ctx.Pause(), and nothing resumed the
        ; macro until F2 (a 10 min outage at 3 AM = no recovery all night).
        ; Now it is held until the oldest attempt leaves the window, then
        ; tries again; reported once until a rejoin works.
        if (fresh.Length >= this._Cfg("maxRejoins", 3)) {
            this._holdUntil := fresh[1] + winMs
            if !this._limitTold {
                this._limitTold := true
                msg := "rejoin limit reached (" fresh.Length " in " (winMs // 60000) " min): trying again when the oldest attempt is "
                    . (winMs // 60000) " min old"
                env.Log("recovery: " msg)
                env.Report("errors", "Recovery on hold", msg)
            }
            return false
        }

        this._attempts.Push(now)
        if ((this._discSeen || this._leaving || this._ghosting) && (this._hwndFn)()) {
            env.Log(this._leaving ? "recovery: closing Roblox to leave Limbo"
                : this._ghosting ? "recovery: closing the ghost server's Roblox client"
                : "recovery: closing the disconnected Roblox client")
            try (this._closeFn)()
            deadline := env.Now() + RecoveryTask.CloseWaitMs
            while (this._hwndFn)() {
                if (env.Now() >= deadline) {
                    this._holdUntil := env.Now() + RecoveryTask.RetryMs
                    env.Log("recovery: the old Roblox window did not close")
                    env.Report("errors", "Recovery failed", "the disconnected Roblox window did not close")
                    return false
                }
                if !env.Wait(500, ctx)
                    return false
            }
        }
        this._discSeen := false
        env.Log("recovery: rejoining private server")
        ; the new client's first "Equipped" line is the aura you wear, not a
        ; roll (2026-10-31: a Medal clip after every rejoin): quiet from the
        ; launch through the window wait, and again once it is in
        Auras.Quiet(RecoveryTask.WindowWaitMs + this._Cfg("loadSec", 20) * 1000 + Auras.JoinQuietMs)
        try {
            (this._runFn)(link)
        } catch Any {
            ; AHK's error text contains the link: report generically only.
            this._holdUntil := env.Now() + RecoveryTask.RetryMs
            env.Log("recovery: could not open the link")
            env.Report("errors", "Recovery failed", "could not open the private server link")
            return false
        }

        deadline := env.Now() + RecoveryTask.WindowWaitMs
        lastTick := env.Now()
        updMs := 0
        updTold := false
        while !(this._hwndFn)() {
            tick := env.Now()
            if (updMs < RecoveryTask.UpdateMaxMs && this._Updating()) {
                if !updTold {
                    updTold := true
                    env.Log("recovery: Roblox is updating - waiting for it to finish")
                    Auras.Quiet(RecoveryTask.UpdateMaxMs)
                }
                updMs += tick - lastTick
                deadline += tick - lastTick      ; update time is not a failed wait
            }
            lastTick := tick
            if (env.Now() >= deadline) {
                this._holdUntil := env.Now() + RecoveryTask.RetryMs
                env.Log("recovery: Roblox window did not appear in 90 s")
                env.Report("errors", "Recovery failed", "Roblox window did not appear within 90 s")
                return false
            }
            if !env.Wait(1000, ctx)
                return false
        }
        if (IsObject(this._state) && HasProp(this._state, "inLimbo"))
            this._state.inLimbo := false        ; a fresh join starts on Sol's Island
        ; the title screen after every join (live 2026-11-09): every reset
        ; failed on it, the rejoins ran to their limit, then every task failed.
        ; It is looked for from the moment the window is up (live 2026-11-12:
        ; it showed during the blind loadSec wait, or after it when checked
        ; once, and Play was never clicked): Play as soon as it reads, else
        ; loadSec + TitleWaitMs at most.
        waited := 0, limit := this._Cfg("loadSec", 20) * 1000 + RecoveryTask.TitleWaitMs
        while (waited < limit && !Input.TitleUp(env.io, env.ocrFn)) {
            if !env.Wait(RecoveryTask.TitlePollMs, ctx)
                return false
            waited += RecoveryTask.TitlePollMs
        }
        if (waited >= limit)
            env.Log("recovery: no title screen " (limit // 1000) " s after the window opened; going on")
        if !this._FocusOk()
            return false
        p := Input.ClickPlay(ctx, env.io, env.ocrFn)
        if (p < 0)
            return false
        if (p = 1)
            env.Log("recovery: title screen: clicked Play")
        else if (p = 2)
            env.Log("recovery: title screen: Play clicked, the title screen is still up")
        if !Input.ResetToSpawn(ctx, env.io) {
            if !(IsObject(ctx) && ctx.ShouldStop())
                env.Log("recovery: reset to spawn after the rejoin failed (" Input.LastResetError ")")
            return false
        }
        if IsObject(this._state)
            this._state.progressAt := env.Now()
        this._afkAt := env.Now()
        this._limitTold := false
        Auras.Quiet(Auras.JoinQuietMs)
        env.Log("recovery: rejoined")
        if (IsObject(this._state) && HasMethod(this._state, "Bump"))
            this._state.Bump("rejoins")         ; Stats / daily summary
        if !this._leaving
            env.Report("errors", "Recovery: rejoined", "Roblox window is back, reset to spawn", 0xF2A93B)
        return true
    }
}
