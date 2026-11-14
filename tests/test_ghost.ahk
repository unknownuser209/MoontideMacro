#Requires AutoHotkey v2.0
; Anti ghost server: a join that did not come from the private server link
; (Sol's own "Player will automatically rejoin" teleport, seen in the user's
; logs 2026-10-26 as UgcExperienceController doTeleport) lands in a server
; nobody can join. LogWatch reports each join, RecoveryTask rejoins the
; private server, the rare alert does not ping anyone into it.

GhReq(ts, type) => ts ',1.0,1,6,Warning [FLog::NewWebView2Browser] Webview handles hybrid javascript event {"moduleID":"Game","functionName":"launchGame","params":{"request":{"requestType":"' type '","placeId":"15532962292","accessCode":"SECRETCODE"}}}'
GhJoin(ts) => ts ",1.0,1,6 [FLog::Output] ! Joining game 'job-1' place 15532962292 at 10.8.2.30"
GhTeleport(ts) => ts ",1.0,1,6,Info [FLog::UgcExperienceController] UgcExperienceController: doTeleport: url "

; Roblox 0.745 writes this right after every join; on a warm start (the
; macro's own rejoin, 2026-10-27) it is the ONLY private marker
GhLoad(ts, ref) => ts ",1.0,1,6 [FLog::GameJoinLoadTime] Report game_join_loadtime: placeid:15532962292, join_time:0.79, universeid:5361032378, referral_page:" ref ", sid:c9288314"

GhJoins(evs) {
    out := []
    for ev in evs
        if (ev["type"] = "join")
            out.Push(ev)
    return out
}

Test_Ghost_LiveJoinEvents() {
    d := LwTmpDir()
    try {
        path := d "\0.1_20261026T000000Z_Player_AAAAA_last.log"
        FileAppend("", path)
        lw := LogWatch(d)
        AssertEq(lw.Poll().Length, 0, "empty log")
        FileAppend(GhReq("2026-10-26T20:00:00.000Z", "RequestPrivateGame") "`n" GhJoin("2026-10-26T20:00:01.000Z") "`n", path, "UTF-8-RAW")
        j := GhJoins(lw.Poll())
        AssertEq(j.Length, 1, "one join")
        AssertEq(j[1]["name"], "private", "the link join is private")
        AssertEq(j[1]["live"], true, "live")
        FileAppend(GhTeleport("2026-10-26T22:52:41.000Z") "`n" GhJoin("2026-10-26T22:52:41.500Z") "`n", path, "UTF-8-RAW")
        AssertEq(GhJoins(lw.Poll()).Length, 0, "a live join waits for its GameJoinLoadTime line")
        t0 := A_TickCount
        LogWatch.TickFn := () => t0 + LogWatch.JOIN_WAIT_MS + 1000
        j := GhJoins(lw.Poll())
        LogWatch.TickFn := () => A_TickCount
        AssertEq(j.Length, 1, "the teleport join")
        AssertEq(j[1]["name"], "other", "a teleport is not the private server")
        AssertEq(lw.CurrentJoin, "other", "current join kept")
        ; a public join (any other request type) is not private either
        FileAppend(GhReq("2026-10-26T23:00:00.000Z", "RequestGame") "`n" GhJoin("2026-10-26T23:00:01.000Z") "`n", path, "UTF-8-RAW")
        lw.Poll()
        t1 := A_TickCount
        LogWatch.TickFn := () => t1 + LogWatch.JOIN_WAIT_MS + 1000
        pj := GhJoins(lw.Poll())
        LogWatch.TickFn := () => A_TickCount
        AssertEq(pj.Length ? pj[1]["name"] : "", "other", "public join")
        for ev in GhJoins(lw.Poll())
            AssertTrue(!InStr(ev["name"] ev["ts"], "SECRET"), "never the access code")
    } finally {
        LwTmpClean(d)
    }
}

Test_Ghost_StartupFindsTheLastJoinBeyondTheTail() {
    ; the join is far above the 64 KB startup tail of a long log
    filler := ""
    Loop 1200
        filler .= "2026-10-26T21:00:00.000Z,1.0,1,6,Info [FLog::Output] filler line number " A_Index " ........................`n"
    d := LwTmpDir()
    try {
        path := d "\0.1_20261026T000000Z_Player_BBBBB_last.log"
        FileAppend(GhReq("2026-10-26T20:00:00.000Z", "RequestPrivateGame") "`n" GhJoin("2026-10-26T20:00:01.000Z") "`n"
            . GhTeleport("2026-10-26T20:30:00.000Z") "`n" GhJoin("2026-10-26T20:30:01.000Z") "`n" filler, path, "UTF-8-RAW")
        AssertTrue(FileGetSize(path) > LogWatch.TAIL_BYTES, "longer than the tail")
        j := GhJoins(LogWatch(d).Poll())
        AssertEq(j.Length, 1, "one join at startup")
        AssertEq(j[1]["name"], "other", "the last join was the teleport")
        AssertEq(j[1]["live"], false, "startup: not live")
        ; private last
        path2 := d "\0.1_20261026T000000Z_Player_CCCCC_last.log"
        FileAppend(GhReq("2026-10-26T20:00:00.000Z", "RequestPrivateGame") "`n" GhJoin("2026-10-26T20:00:01.000Z") "`n" filler, path2, "UTF-8-RAW")
        FileSetTime(A_Now, path2, "M")
        FileSetTime("20200101000000", path, "M")
        j := GhJoins(LogWatch(d).Poll())
        AssertEq(j[1]["name"], "private", "private join found")
    } finally {
        LwTmpClean(d)
    }
}

Test_Ghost_Decision() {
    st := SchedState()
    cfg := QmCfg()
    AssertEq(RecoveryTask.GhostDecision("other", st, cfg), "ghost", "teleport join -> ghost")
    AssertEq(RecoveryTask.GhostDecision("private", st, cfg), "clear", "private join -> clear")
    AssertEq(RecoveryTask.GhostDecision("other", st, QmCfg(Map("recovery.antiGhost", 0))), "", "switched off")
    AssertEq(RecoveryTask.GhostDecision("other", st, QmCfg(Map("Limbo.enabled", 1))), "", "Limbo mode: the Portable Crack is a teleport too")
    st.inLimbo := true
    AssertEq(RecoveryTask.GhostDecision("other", st, cfg), "", "in THE LIMBO")
}

Test_Ghost_RecoveryRejoinsThePrivateServer() {
    rig := RcRig()
    AssertEq(rig.task.CanRun(rig.state), false, "healthy")
    rig.state.ghost := true
    AssertEq(rig.task.CanRun(rig.state), true, "ghost server -> rejoin")
    AssertEq(rig.task.Run(rig.Ctx()), 1, "rejoined")
    AssertEq(rig.closes, 1, "the ghost client is closed first")
    AssertEq(rig.runs.Length, 1, "the private link opened")
    AssertEq(rig.state.ghost, false, "cleared after the rejoin")
    AssertTrue(InStr(rig.AllText(), "ghost server"), "logged / reported as a ghost server")
    AssertTrue(!InStr(rig.AllText(), "SECRET123"), "link never logged")
    AssertEq(rig.task.CanRun(rig.state), false, "back to normal")
}

; review 2026-10-27: a ghost with no usable private link made recovery
; eligible every minute: it interrupted fishing, sent a "Ghost server"
; webhook and refused, forever
Test_Ghost_NoLinkIsNotEligible() {
    rig := RcRig("")
    rig.state.ghost := true
    AssertEq(rig.task.CanRun(rig.state), false, "no link: not eligible")
    rig.clock.t += 120000
    AssertEq(rig.task.CanRun(rig.state), false, "still not, two minutes later")
    n := 0
    for m in rig.hook.sent
        n += (m.event = "errors") ? 1 : 0
    AssertEq(n, 1, "told once")
    rig2 := RcRig("not a roblox link")
    rig2.state.ghost := true
    AssertEq(rig2.task.CanRun(rig2.state), false, "bad link: not eligible")
}

; one "Ghost server" webhook per ghost, not one per failed rejoin
Test_Ghost_ReportedOncePerGhost() {
    rig := RcRig()
    rig.state.ghost := true
    rig.canFocus := false            ; the rejoin fails
    rig.task.CanRun(rig.state), rig.task.Run(rig.Ctx())
    rig.clock.t += 120000
    rig.task.CanRun(rig.state), rig.task.Run(rig.Ctx())
    n := 0
    for m in rig.hook.sent
        n += InStr(m.title, "Ghost") ? 1 : 0
    AssertEq(n, 1, "one ghost webhook for two tries")
}

Test_Ghost_RareAlertDoesNotPingIntoIt() {
    r := WfRig(Map("General.privateServer", "https://www.roblox.com/share?code=abc&type=Server", "General.joinButton", 1))   ; opt-in
    try {
        p := r.Rare("GLITCHED")
        AssertTrue(InStr(r.wh.sent[r.wh.sent.Length].json, "Join Server"), "normal: Join button")
        AssertTrue(WfHasEveryone(p), "normal: @everyone")
        r.state.ghost := true
        p := r.Rare("DREAMSPACE", "2026-10-25T02:00:00.000Z")
        AssertTrue(IsObject(p), "still reported")
        AssertTrue(!WfHasEveryone(p), "no @everyone in a ghost server")
        for rec in WfRecs(r.wh, "", "rare")
            AssertTrue(!InStr(rec.rec.json, "Join Server"), "no Join button")
        AssertTrue(InStr(Json.Stringify(p), "ghost server"), "says why")
    } finally {
        r.Done()
    }
}

; The real 0.745 line order (log of 2026-10-27 21:32): no "requestType"
; line, the join, then "referral_page:RequestPrivateGame". It read as a
; ghost server, so every Start closed a healthy Roblox and rejoined.
Test_Ghost_WarmStartPrivateJoinIsPrivate() {
    d := LwTmpDir()
    try {
        path := d "\0.745_20261028T023155Z_Player_46C54_last.log"
        FileAppend("", path)
        lw := LogWatch(d)
        lw.Poll()
        FileAppend(GhJoin("2026-10-28T02:32:00.665Z") "`n" GhLoad("2026-10-28T02:32:00.665Z", "RequestPrivateGame") "`n", path, "UTF-8-RAW")
        j := GhJoins(lw.Poll())
        AssertEq(j.Length, 1, "one join event")
        AssertEq(j[1]["name"], "private", "the warm-start rejoin is the private server")
        ; a teleport: referral_page empty
        FileAppend(GhJoin("2026-10-28T02:56:12.684Z") "`n" GhLoad("2026-10-28T02:56:12.684Z", "") "`n", path, "UTF-8-RAW")
        j := GhJoins(lw.Poll())
        AssertEq(j[1]["name"], "other", "a teleport is still a ghost server")
        ; the same at startup, far above the tail
        filler := ""
        Loop 1200
            filler .= "2026-10-28T02:40:00.000Z,1.0,1,6,Info [FLog::Output] filler line number " A_Index " ........................`n"
        path2 := d "\0.745_20261028T030000Z_Player_77777_last.log"
        FileAppend(GhJoin("2026-10-28T03:00:00.000Z") "`n" GhLoad("2026-10-28T03:00:00.000Z", "RequestPrivateGame") "`n" filler, path2, "UTF-8-RAW")
        FileSetTime(A_Now, path2, "M")
        FileSetTime("20200101000000", path, "M")
        j := GhJoins(LogWatch(d).Poll())
        AssertEq(j[1]["name"], "private", "startup: private")
        AssertEq(j[1]["live"], false, "startup: not live")
    } finally {
        LwTmpClean(d)
    }
}


; live 2026-11-11 15:24:58: the macro's own private rejoin: the read ended
; after "Joining game" and before the GameJoinLoadTime line; the join was
; taken as a ghost server and it rejoined until the limit (3 in 10 min)
Test_Ghost_JoinSplitAcrossReadsIsPrivate() {
    d := LwTmpDir()
    try {
        path := d "\0.1_20261111T000000Z_Player_CCCCC_last.log"
        FileAppend("", path)
        lw := LogWatch(d)
        lw.Poll()
        FileAppend(GhJoin("2026-11-11T21:24:57.000Z") "`n", path, "UTF-8-RAW")
        AssertEq(GhJoins(lw.Poll()).Length, 0, "no verdict yet")
        FileAppend(GhLoad("2026-11-11T21:24:58.000Z", "RequestPrivateGame") "`n", path, "UTF-8-RAW")
        j := GhJoins(lw.Poll())
        AssertEq(j.Length, 1, "one join")
        AssertEq(j.Length ? j[1]["name"] : "", "private", "the rejoin is the private server")
    } finally {
        LogWatch.TickFn := () => A_TickCount
        LwTmpClean(d)
    }
}

; live 2026-11-12 20:57: Sol's restart teleported the user into a new copy of
; their own private server (ticket RequestType 2, JoinTypeId 4). It read as a
; ghost server and every Start closed Roblox and rejoined. The game's boss
; arenas (RequestType 2, JoinTypeId 6) and public servers (0 / 10) stay ghosts.
GhTicket(ts, req, jt) => ts ',1.0,1,6,Info [FLog::UgcExperienceController] UgcExperienceController: doTeleport: joinScriptUrl https://assetgame.roblox.com/Game/Join.ashx?ticketVersion=2&ticket={"UserId"%3a1%2c"PlaceId"%3a15532962292%2c"IsTeleport"%3atrue%2c"FollowUserId"%3anull%2c"JoinTypeId"%3a' jt '%2c"MatchmakingDecisionId"%3anull%2c"RequestType"%3a' req '}'

Test_Ghost_TeleportIntoThePrivateServerIsPrivate() {
    AssertEq(LogWatch.TeleportKind(GhTicket("2026-11-13T02:57:14.632Z", 2, 4)).jt, 4, "JoinTypeId read")
    AssertEq(LogWatch.TeleportKind(GhTicket("2026-11-13T02:57:14.632Z", 2, 4)).req, 2, "RequestType read")
    AssertEq(LogWatch.TeleportKind("no ticket here").req, -1, "no ticket")
    d := LwTmpDir()
    try {
        path := d "\0.747_20261113T004754Z_Player_077A8_last.log"
        FileAppend("", path)
        lw := LogWatch(d)
        lw.Poll()
        cases := [[2, 4, "private", "a teleport into the private server"]
            , [2, 6, "other", "a reserved boss arena"]
            , [0, 10, "other", "a public server"]]
        for c in cases {
            FileAppend(GhTicket("2026-11-13T02:57:14.632Z", c[1], c[2]) "`n" GhTeleport("2026-11-13T02:57:14.700Z") "`n"
                . GhJoin("2026-11-13T02:57:15.104Z") "`n" GhLoad("2026-11-13T02:57:15.104Z", "") "`n", path, "UTF-8-RAW")
            j := GhJoins(lw.Poll())
            AssertEq(j.Length, 1, c[4] ": one join")
            AssertEq(j[1]["name"], c[3], c[4])
        }
        ; the ticket is used once: a later plain teleport is a ghost again
        FileAppend(GhTicket("2026-11-13T03:00:00.000Z", 2, 4) "`n" GhJoin("2026-11-13T03:00:01.000Z") "`n" GhLoad("2026-11-13T03:00:01.000Z", "") "`n"
            . GhJoin("2026-11-13T03:05:00.000Z") "`n" GhLoad("2026-11-13T03:05:00.000Z", "") "`n", path, "UTF-8-RAW")
        j := GhJoins(lw.Poll())
        AssertEq(j.Length, 2, "two joins")
        AssertEq(j[1]["name"], "private", "the ticketed one")
        AssertEq(j[2]["name"], "other", "the next one without a ticket")
        ; at startup (the user's case: F1 long after the teleport)
        filler := ""
        Loop 1200
            filler .= "2026-11-13T03:10:00.000Z,1.0,1,6,Info [FLog::Output] filler line number " A_Index " ........................`n"
        path2 := d "\0.747_20261113T031000Z_Player_88888_last.log"
        FileAppend(GhReq("2026-11-13T02:22:30.312Z", "RequestPrivateGame") "`n" GhJoin("2026-11-13T02:22:30.779Z") "`n"
            . GhTicket("2026-11-13T02:57:14.632Z", 2, 4) "`n" GhJoin("2026-11-13T02:57:15.104Z") "`n" GhLoad("2026-11-13T02:57:15.104Z", "") "`n" filler, path2, "UTF-8-RAW")
        FileSetTime(A_Now, path2, "M")
        FileSetTime("20200101000000", path, "M")
        j := GhJoins(LogWatch(d).Poll())
        AssertEq(j[1]["name"], "private", "startup: still the private server, no rejoin")
    } finally {
        LwTmpClean(d)
    }
}

; review 2026-11-12: a teleport ticket left by a teleport that never joined
; must not make the next (public) launch read as private
Test_Ghost_StaleTicketIsDropped() {
    d := LwTmpDir()
    try {
        path := d "\0.747_20261113T050000Z_Player_99999_last.log"
        FileAppend("", path)
        lw := LogWatch(d)
        lw.Poll()
        FileAppend(GhTicket("2026-11-13T05:00:00.000Z", 2, 4) "`n" GhReq("2026-11-13T05:01:00.000Z", "RequestGame") "`n"
            . GhJoin("2026-11-13T05:01:01.000Z") "`n" GhLoad("2026-11-13T05:01:01.000Z", "") "`n", path, "UTF-8-RAW")
        j := GhJoins(lw.Poll())
        AssertEq(j.Length, 1, "one join")
        AssertEq(j[1]["name"], "other", "the public launch is a ghost")
    } finally {
        LwTmpClean(d)
    }
}

; bug hunt 2026-11-13: a teleport ticket more than 10 s before a join is not
; that join's (a teleport that never joined, then a public warm start)
Test_Ghost_OldTicketIsNotThisJoins() {
    d := LwTmpDir()
    old := LogWatch.TickFn
    try {
        path := d "\0.747_20261113T060000Z_Player_12121_last.log"
        FileAppend("", path)
        lw := LogWatch(d)
        lw.Poll()
        t := 1000000
        LogWatch.TickFn := () => t
        FileAppend(GhTicket("2026-11-13T06:00:00.000Z", 2, 4) "`n", path, "UTF-8-RAW")
        lw.Poll()
        t += 60000
        FileAppend(GhJoin("2026-11-13T06:01:00.000Z") "`n" GhLoad("2026-11-13T06:01:00.000Z", "") "`n", path, "UTF-8-RAW")
        j := GhJoins(lw.Poll())
        AssertEq(j.Length, 1, "one join")
        AssertEq(j[1]["name"], "other", "a minute-old ticket does not make it private")
    } finally {
        LogWatch.TickFn := old
        LwTmpClean(d)
    }
}
