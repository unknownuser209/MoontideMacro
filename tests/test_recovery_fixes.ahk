#Requires AutoHotkey v2.0
; Bug hunt 2026-11-27: recovery, ghost server and schedule fixes. Uses the
; fakes of test_recovery.ahk (RcRig, RcIO ...), test_logwatch.ahk (LwTmpDir),
; test_ghost.ahk (GhReq, GhLoad, GhTicket), test_stats.ahk (StatFakeCfg) and
; test_app.ahk (AppTestMake, AppFakeTask). Helpers are prefixed Rf.
#Include ..\lib\tasks\Recovery.ahk
#Include ..\lib\LogWatch.ahk
#Include ..\lib\Schedule.ahk
#Include ..\lib\App.ahk

; ---- recovery-2: F3 during the close opens no Roblox ------------------------

; A stop (F3 / F2) pressed while the old client closes (WinWaitClose /
; ProcessWaitClose, hotkeys run meanwhile) was not seen: Run(link) opened
; the private server anyway.
Test_RecoveryFix_NoLaunchAfterStopDuringClose() {
    rig := RcRig()
    stop := [false]
    ctx := {ShouldStop: (*) => stop[1], Pause: (*) => 0}
    rig.task.FakeDisconnect()
    rig.task._closeFn := () => (rig.closes++, rig.win := false, stop[1] := true)
    AssertEq(rig.task.CanRun(rig.state), true, "disconnect pending")
    AssertEq(rig.task.Run(ctx), 0, "stopped")
    AssertEq(rig.closes, 1, "the old client was closed")
    AssertEq(rig.runs.Length, 0, "F3 during the close: the link is not opened")
    AssertEq(rig.task._attempts.Length, 0, "no launch: not counted toward the rejoin limit")
    ; the next run still knows about the disconnect and rejoins once
    AssertEq(rig.task.Rejoining(rig.state), true, "the rejoin still waits")
    AssertEq(rig.task.CanRun(rig.state), true, "runs again (no window)")
    AssertEq(rig.task.Run(rig.Ctx()), 1, "rejoined")
    AssertEq(rig.runs.Length, 1, "one launch in all")
}

; ---- recovery-1: leaving THE LIMBO opens the link once ----------------------

; The App halts the limbo task as soon as the window is gone (its rejoin
; runs inside the limbo task, not as "recovery"): the rejoin opened the link
; after the halt, then recovery opened it a second time ~100 ms later.
Test_RecoveryFix_LimboLeaveCutByAHaltOpensTheLinkOnce() {
    rig := RcRig()
    rig.state.inLimbo := true
    rig.task.CanRun(rig.state)
    stop := [false]
    ctx := {ShouldStop: (*) => stop[1], Pause: (*) => 0}
    rig.task._closeFn := () => (rig.closes++, rig.win := false, stop[1] := true)
    AssertEq(rig.task.ReturnToIsland(ctx), false, "cut by the halt")
    AssertEq(rig.closes, 1, "the Limbo client was closed")
    AssertEq(rig.runs.Length, 0, "halted: the link is not opened inside the limbo task")
    AssertEq(rig.task._attempts.Length, 0, "not counted toward the rejoin limit")
    AssertEq(rig.task.CanRun(rig.state), true, "no window: recovery runs next")
    AssertEq(rig.task.Run(rig.Ctx()), 1, "rejoined")
    AssertEq(rig.runs.Length, 1, "the private server opened once in all")
    AssertEq(rig.state.inLimbo, false, "a fresh join is on Sol's Island")
    AssertTrue(!InStr(rig.AllText(), "SECRET123"), "link never logged")
}

; Auto-rejoin off: the App pauses for the missing window instead of a
; rejoin, so the leave still opens the private server (as before), else the
; game stayed closed.
Test_RecoveryFix_LimboLeaveWithAutoRejoinOffStillOpensTheLink() {
    rig := RcRig(, Map("recovery.enabled", 0))
    rig.state.inLimbo := true
    stop := [false]
    ctx := {ShouldStop: (*) => stop[1], Pause: (*) => 0}
    rig.task._closeFn := () => (rig.closes++, rig.win := false, stop[1] := true)
    AssertEq(rig.task.ReturnToIsland(ctx), false, "cut by the pause")
    AssertEq(rig.runs.Length, 1, "the private server still opened: nothing else would reopen the game")
    ; a plain stop (no Limbo leave) with auto-rejoin off: nothing opened
    rig2 := RcRig(, Map("recovery.enabled", 0))
    stop2 := [false]
    ctx2 := {ShouldStop: (*) => stop2[1], Pause: (*) => 0}
    rig2.task._discSeen := true, rig2.task._discFake := true     ; a disconnect seen (no re-read)
    rig2.task._closeFn := () => (rig2.closes++, rig2.win := false, stop2[1] := true)
    AssertEq(rig2.task.Run(ctx2), 0, "stopped")
    AssertEq(rig2.closes, 1, "the client was closed")
    AssertEq(rig2.runs.Length, 0, "not a Limbo leave: no launch after the stop")
}

; The same through the App: a limbo task leaving THE LIMBO with a real
; RecoveryTask, the App ticking while the client closes.
Test_RecoveryFix_LimboLeaveInTheAppOpensTheLinkOnce() {
    clock := RcClock(), io := RcIO(clock), hook := RcHook(), runs := [], openAt := [0]
    t := ""
    rec := RecoveryTask({cfg: RcCfg("https://www.roblox.com/games/1/x?privateServerLinkCode=SECRET123")
        , webhook: hook, log: (s) => 0, io: io, cal: RcCal(), now: () => clock.t
        , hwnd: () => RfWin(t, clock, openAt), active: () => t.rb.win != 0, focus: () => true
        , ocr: (x, y, w, h, scale := 1) => "", procs: (name) => false
        , close: () => (t.rb.win := 0, t.app.Tick(), true)
        , run: (l) => (runs.Push(l), openAt[1] := clock.t + 5000)})
    limbo := AppFakeTask("limbo", 98, true, (self, ctx) => (self.can := false, self.ok := t.app._ToIsland(ctx), self.stop := ctx.ShouldStop()))
    t := AppTestMake(Map("tasks", Map("recovery", rec, "limbo", limbo)))
    try {
        t.app.Start()
        t.app.Tick()
        AppTestRunLaunched(t)
        AssertEq(limbo.runs, 1, "the limbo task ran")
        AssertTrue(runs.Length <= 1, "at most one launch while leaving (" runs.Length ")")
        Loop 3 {
            t.app.Tick()
            AppTestRunLaunched(t)
        }
        AssertEq(runs.Length, 1, "the private server link opened once for one Limbo leave")
    } finally {
        Auras.QuietUntil := 0
    }
}

; the fake window: up from the link's launch + 5 s (the App reads t.rb.win)
RfWin(t, clock, openAt) {
    if (openAt[1] && clock.t >= openAt[1])
        t.rb.win := 1, openAt[1] := 0
    return t.rb.win
}

; ---- live-3: the warm tray client is ended before the link opens ------------

; live 2026-11-27 14:11 and 04:42: while the old client exited, Roblox
; started a tray-only RobloxPlayerBeta; the link handed the join to it and it
; died 120 s after it started ("Roblox window gone", a second rejoin).
RfTrayApi(f) {
    return {
        hwnd: (_) => f.win ? 77 : 0,
        pid: (_, h) => 4242,
        winClose: (_, h) => (f.log.Push("winclose " h), f.win := false),
        winWaitClose: (_, h, sec) => !f.win,
        procWait: (_, pid, sec) => (f.log.Push("wait " pid), 0),
        procExist: (_, n) => (f.names.Push(n), f.checks++, (f.trayAt && f.checks >= f.trayAt && !f.trayGone) ? 777 : 0),
        procClose: (_, x) => (f.log.Push("kill " x), (x = 777 && !f.stubborn) ? (f.trayGone := true) : 0),
        sleep: (_, ms) => (f.slept += ms)
    }
}
RfTray(trayAt, stubborn := false) {
    return {win: true, log: [], names: [], checks: 0, trayAt: trayAt, trayGone: false, stubborn: stubborn, slept: 0}
}

Test_RecoveryFix_CloseAlsoEndsTheWarmTrayClient() {
    f := RfTray(1)
    AssertEq(RecoveryTask._CloseRoblox(RfTrayApi(f)), true, "closed")
    AssertTrue(RcLogHas(f.log, "kill 777"), "the tray-only client Roblox started during the close is ended before the link opens")
    AssertEq(f.trayGone, true, "gone")
    AssertEq(f.names.Length ? f.names[1] : "", "RobloxPlayerBeta.exe", "looked for by the player's exe name")
    ; one that shows up a moment after the old process ended
    g := RfTray(3)
    AssertEq(RecoveryTask._CloseRoblox(RfTrayApi(g)), true, "closed")
    AssertTrue(RcLogHas(g.log, "kill 777"), "a tray client that starts a moment later is ended too")
    ; none: nothing more is ended, and only a short wait
    h := RfTray(0)
    AssertEq(RecoveryTask._CloseRoblox(RfTrayApi(h)), true, "closed")
    AssertTrue(!RcLogHas(h.log, "kill 777"), "nothing else ended")
    AssertTrue(h.slept <= 1500, "a short look only (" h.slept " ms)")
    ; one that will not end: the look is bounded
    s := RfTray(1, true)
    AssertEq(RecoveryTask._CloseRoblox(RfTrayApi(s)), true, "closed")
    AssertTrue(s.slept <= 6000, "bounded (" s.slept " ms)")
    ; no window: nothing to close, nothing looked for
    n := RfTray(1)
    n.win := false
    AssertEq(RecoveryTask._CloseRoblox(RfTrayApi(n)), true, "no window")
    AssertEq(n.log.Length, 0, "nothing done")
}

; ---- live-2: Roblox's own reconnect into the same server stays private -------

RfJoin(ts, job) => ts ",1.0,1,6 [FLog::Output] ! Joining game '" job "' place 15532962292 at 10.8.2.30"
RfDisc(ts) => ts ",1.0,1,6,Info [DFLog::NetworkClient] Client:Disconnect"

; live 2026-11-27 19:08: Client:Disconnect, then a join to the same job with
; "referral_page:" empty (Roblox's own reconnect). It read as a ghost server
; and Start closed a client that was in the private server all along.
Test_RecoveryFix_ReconnectToTheSameServerStaysPrivate() {
    d := LwTmpDir()
    try {
        path := d "\0.748_20261127T104501Z_Player_DDDDD_last.log"
        FileAppend("", path)
        lw := LogWatch(d)
        lw.Poll()
        FileAppend(GhReq("2026-11-27T18:38:47.000Z", "RequestPrivateGame") "`n" RfJoin("2026-11-27T18:38:47.748Z", "job-A") "`n", path, "UTF-8-RAW")
        j := GhJoins(lw.Poll())
        AssertEq(j.Length ? j[1]["name"] : "", "private", "the link join")
        FileAppend(RfDisc("2026-11-27T19:08:29.984Z") "`n" RfJoin("2026-11-27T19:08:34.738Z", "job-A") "`n" GhLoad("2026-11-27T19:08:34.738Z", "") "`n", path, "UTF-8-RAW")
        j := GhJoins(lw.Poll())
        AssertEq(j.Length, 1, "one join")
        AssertEq(j.Length ? j[1]["name"] : "", "private", "a reconnect to the same server is the private server")
        ; the game's teleport into the same server (live 2026-11-27 05:26, ticket 1 / 6)
        FileAppend(GhTicket("2026-11-27T19:20:00.000Z", 1, 6) "`n" RfDisc("2026-11-27T19:20:00.100Z") "`n" RfJoin("2026-11-27T19:20:00.300Z", "job-A") "`n"
            . GhLoad("2026-11-27T19:20:00.300Z", "") "`n", path, "UTF-8-RAW")
        j := GhJoins(lw.Poll())
        AssertEq(j.Length ? j[1]["name"] : "", "private", "a teleport into the same server is the private server")
        ; another server: a ghost as before
        FileAppend(RfDisc("2026-11-27T19:30:00.000Z") "`n" RfJoin("2026-11-27T19:30:01.000Z", "job-B") "`n" GhLoad("2026-11-27T19:30:01.000Z", "") "`n", path, "UTF-8-RAW")
        j := GhJoins(lw.Poll())
        AssertEq(j.Length ? j[1]["name"] : "", "other", "another server is still a ghost server")
        ; a join still waiting for its GameJoinLoadTime line: the same rule
        FileAppend(RfDisc("2026-11-27T19:40:00.000Z") "`n" RfJoin("2026-11-27T19:40:01.000Z", "job-A") "`n", path, "UTF-8-RAW")
        AssertEq(GhJoins(lw.Poll()).Length, 0, "waits for its GameJoinLoadTime line")
        t0 := A_TickCount
        LogWatch.TickFn := () => t0 + LogWatch.JOIN_WAIT_MS + 1000
        j := GhJoins(lw.Poll())
        LogWatch.TickFn := () => A_TickCount
        AssertEq(j.Length ? j[1]["name"] : "", "private", "back to the private server's job: private")
        for ev in j
            AssertTrue(!InStr(ev["name"] ev["ts"], "job-A"), "the job id is never in an event")
    } finally {
        LogWatch.TickFn := () => A_TickCount
        LwTmpClean(d)
    }
}

; the same at Start (backfill: the 14:11:54 ghost server and close)
Test_RecoveryFix_ReconnectAtStartupStaysPrivate() {
    filler := ""
    Loop 1200
        filler .= "2026-11-27T19:30:00.000Z,1.0,1,6,Info [FLog::Output] filler line number " A_Index " ........................`n"
    d := LwTmpDir()
    try {
        path := d "\0.748_20261127T104501Z_Player_DDDDD_last.log"
        FileAppend(GhReq("2026-11-27T18:38:47.000Z", "RequestPrivateGame") "`n" RfJoin("2026-11-27T18:38:47.748Z", "job-A") "`n"
            . RfDisc("2026-11-27T19:08:29.984Z") "`n" RfJoin("2026-11-27T19:08:34.738Z", "job-A") "`n" GhLoad("2026-11-27T19:08:34.738Z", "") "`n" filler, path, "UTF-8-RAW")
        AssertTrue(FileGetSize(path) > LogWatch.TAIL_BYTES, "longer than the tail")
        j := GhJoins(LogWatch(d).Poll())
        AssertEq(j.Length, 1, "one join at startup")
        AssertEq(j.Length ? j[1]["name"] : "", "private", "startup: the reconnect is the private server, no rejoin")
        ; another server at startup: a ghost
        path2 := d "\0.748_20261127T200000Z_Player_33333_last.log"
        FileAppend(GhReq("2026-11-27T18:38:47.000Z", "RequestPrivateGame") "`n" RfJoin("2026-11-27T18:38:47.748Z", "job-A") "`n"
            . RfDisc("2026-11-27T19:08:29.984Z") "`n" RfJoin("2026-11-27T19:08:34.738Z", "job-B") "`n" GhLoad("2026-11-27T19:08:34.738Z", "") "`n" filler, path2, "UTF-8-RAW")
        FileSetTime(A_Now, path2, "M")
        FileSetTime("20200101000000", path, "M")
        j := GhJoins(LogWatch(d).Poll())
        AssertEq(j.Length ? j[1]["name"] : "", "other", "startup: another server is a ghost server")
    } finally {
        LwTmpClean(d)
    }
}

; ---- recovery-3: an all-day schedule starts again the next day --------------

; "all" was the window key of an all-day schedule (start = end) and it was
; kept in the state file: after the first stop it never started again.
Test_RecoveryFix_ScheduleAllDayStartsAgainNextDay() {
    p := A_Temp "\vesper_sched_" A_TickCount "_" Random(1, 99999) ".txt"
    try {
        cfg := StatFakeCfg(Map("Schedule.enabled", 1, "Schedule.start", "06:00", "Schedule.end", "06:00", "Schedule.maxHours", 8))
        r := RunSchedule(cfg, p)
        AssertEq(r.Tick("20261112130000", false, 0), "start", "first")
        r.NoteStart(true)
        AssertEq(r.Tick("20261112210000", true, 8 * 3600000), "stop", "8 h")
        r.NoteStop()
        AssertEq(r.Tick("20261112220000", false, 0), "", "same day: once")
        AssertEq(r.Tick("20261113030000", false, 0), "", "before 06:00: still the same window")
        AssertEq(RunSchedule(cfg, p).Tick("20261112230000", false, 0), "", "a restart the same day stays stopped")
        AssertEq(r.Tick("20261113070000", false, 0), "start", "the next day")
        AssertEq(RunSchedule(cfg, p).Tick("20261114070000", false, 0), "start", "after a restart days later")
        ; an old "all" left in the file by an older version: one fresh start
        FileDelete(p)
        FileAppend("all", p, "UTF-8-RAW")
        AssertEq(RunSchedule(cfg, p).Tick("20261115120000", false, 0), "start", "an old key in the file")
        ; a normal window keeps its keys
        r2 := RunSchedule(StatFakeCfg(Map("Schedule.enabled", 1)))
        AssertEq(r2._WindowKey("20261113030000"), "20261112", "overnight: the evening's date")
        AssertEq(r2._WindowKey("20261112230000"), "20261112", "overnight evening")
        r3 := RunSchedule(cfg)
        AssertEq(r3._WindowKey("20261113055900"), "20261112", "all day before 06:00: yesterday's window")
        AssertEq(r3._WindowKey("20261113060000"), "20261113", "all day from 06:00: today's window")
    } finally {
        try FileDelete(p)
    }
}

; recovery-1, App side: the Limbo leave runs the recovery rejoin inside the
; limbo task; the window going while it closes the Limbo client must not halt
; it like any other task (it then ended as a "Recovery: rejoined" error and
; LimboTask never saw its own leave finish).
Test_RecoveryFix_LimboLeaveIsNotHaltedByTheMonitor() {
    clock := RcClock(), io := RcIO(clock), hook := RcHook(), runs := [], openAt := [0]
    t := ""
    rec := RecoveryTask({cfg: RcCfg("https://www.roblox.com/games/1/x?privateServerLinkCode=SECRET123")
        , webhook: hook, log: (s) => 0, io: io, cal: RcCal(), now: () => clock.t
        , hwnd: () => RfWin(t, clock, openAt), active: () => t.rb.win != 0, focus: () => true
        , ocr: (x, y, w, h, scale := 1) => "", procs: (name) => false
        , close: () => (t.rb.win := 0, t.app.Tick(), true)
        , run: (l) => (runs.Push(l), openAt[1] := clock.t + 5000)})
    limbo := AppFakeTask("limbo", 98, true, (self, ctx) => (self.can := false, self.ok := t.app._ToIsland(ctx), self.stop := ctx.ShouldStop()))
    t := AppTestMake(Map("tasks", Map("recovery", rec, "limbo", limbo)))
    try {
        t.app.Start()
        t.app.Tick()
        AppTestRunLaunched(t)
        AssertEq(limbo.runs, 1, "the limbo task ran")
        AssertEq(limbo.stop, false, "the window going during the Limbo leave did not halt it")
        AssertEq(limbo.ok, true, "the Limbo leave finished its own rejoin")
        AssertEq(runs.Length, 1, "one launch")
    } finally {
        Auras.QuietUntil := 0
    }
}

; ---- follow-ups after the review (bug hunt 2026-11-27) ----------------------

; recovery-2: a stop already there before the close closes nothing (a healthy
; client was closed, and then nothing was launched: Roblox left closed)
Test_RecoveryFix_StopBeforeTheCloseClosesNothing() {
    rig := RcRig()
    ctx := {ShouldStop: (*) => true, Pause: (*) => 0}
    rig.task.FakeDisconnect()
    rig.task._closeFn := () => (rig.closes++, rig.win := false)
    rig.task.Run(ctx)
    AssertEq(rig.closes, 0, "stopped before: the client is not closed")
    AssertEq(rig.runs.Length, 0, "nothing launched")
    AssertEq(rig.task._attempts.Length, 0, "not counted toward the rejoin limit")
    AssertEq(rig.task.Rejoining(rig.state), true, "the rejoin still waits")
}

; live-3: macro.log says when a leftover client was ended before the link
; opened (the only way to see live whether the tray case still happens)
Test_RecoveryFix_EndedTrayClientIsCounted() {
    f := RfTray(1)
    RecoveryTask._CloseRoblox(RfTrayApi(f))
    AssertEq(RecoveryTask.TrayEnded, 1, "one leftover client ended")
    h := RfTray(0)
    RecoveryTask._CloseRoblox(RfTrayApi(h))
    AssertEq(RecoveryTask.TrayEnded, 0, "none")
}
