#Requires AutoHotkey v2.0
; Tests for ClockWatch (lib\plugins\hunting\ClockWatch.ahk): a Sinister boss seen from the
; stopped biome clock (2026-11-17, the owner).
#Include ..\lib\plugins\hunting\ClockWatch.ahk

class CwRep {
    __New() {
        this.spawns := [], this.kills := []
    }
    Spawn(key, boss) => this.spawns.Push(boss)
    Killed(why) => this.kills.Push(why)
}

; reads[i] is the HUD text at the i-th read; the clock steps 1 s a tick
CwRun(reads, biome := "PUMPKIN MOON", disc := "") {
    clock := {t: 0}, i := {n: 0}, rep := CwRep(), logs := []
    cw := ClockWatch({read: () => (i.n++, reads[Min(i.n, reads.Length)]), now: () => clock.t, report: rep, log: (t) => logs.Push(t)
        , disc: IsObject(disc) ? disc : () => false})
    Loop reads.Length {
        cw.Tick(biome)
        clock.t += ClockWatch.ReadMs
    }
    return {cw: cw, rep: rep, logs: logs}
}

Test_Clock_ParseFixesTheFont() {
    AssertEq(ClockWatch.Parse("[ CORRUPTION ] NIGHTTIME (OO : 3B)"), "00:38", "O and B")
    AssertEq(ClockWatch.Parse("NIGHTTIME (21 : 28)"), "21:28", "plain")
    AssertEq(ClockWatch.Parse("(23 : aa)-"), "", "unread minutes")
    AssertEq(ClockWatch.Parse(""), "", "nothing")
    AssertEq(ClockWatch.Parse("DAYTIME (25 : 10)"), "", "not a time")
}

Test_Clock_StoppedClockIsASpawnAndRunningAgainADeath() {
    t := "NIGHTTIME (02 : 10)"
    r := CwRun(["NIGHTTIME (01 : 50)", "NIGHTTIME (02 : 00)", t, t, t, t, t, t, "NIGHTTIME (02 : 12)", "NIGHTTIME (02 : 24)"])
    AssertEq(r.rep.spawns.Length, 1, "one spawn")
    AssertEq(r.rep.spawns[1], "p", "PUMPKIN MOON: Sinister P.")
    AssertEq(r.rep.kills.Length, 1, "dead once the clock ran again")
    AssertEq(r.cw.Paused, false, "running again")
}

Test_Clock_RunningClockAndOtherBiomesSayNothing() {
    r := CwRun(["NIGHTTIME (01 : 00)", "NIGHTTIME (01 : 12)", "NIGHTTIME (01 : 24)", "NIGHTTIME (01 : 36)", "NIGHTTIME (01 : 48)"], "GRAVEYARD")
    AssertEq(r.rep.spawns.Length, 0, "a running clock: no boss")
    t := "NIGHTTIME (03 : 00)"
    r2 := CwRun([t, t, t, t, t, t, t], "WINDY")
    AssertEq(r2.rep.spawns.Length, 0, "another biome: never read")
    ; misreads in a stop do not end it
    r3 := CwRun([t, t, "", t, "garbage", t, t, t], "GRAVEYARD")
    AssertEq(r3.rep.spawns.Length, 1, "stopped through misreads")
    AssertEq(r3.rep.spawns[1], "s", "GRAVEYARD: Sinister S.")
    AssertEq(r3.rep.kills.Length, 0, "a misread is not the clock running")
}

; a disconnect (or "will automatically rejoin") screen freezes the clock too:
; no boss card while it shows, one once the clock really stops without it
Test_Clock_NoBossCardBehindADisconnect() {
    t := "NIGHTTIME (04 : 00)"
    up := {on: true}
    r := CwRun([t, t, t, t, t, t, t, t], "GRAVEYARD", () => up.on)
    AssertEq(r.rep.spawns.Length, 0, "disconnected: no boss card")
    found := false
    for l in r.logs
        found := found || InStr(l, "disconnect screen shows")
    AssertTrue(found, "logged why")
    AssertTrue(RegExMatch("Disconnected`nLost connection to the game server (Error Code: 277)", ClockWatch.DiscRe), "Roblox's disconnect box")
    AssertTrue(RegExMatch("The server is restarting. Player will automatically rejoin", ClockWatch.DiscRe), "the rejoin notice")
    AssertTrue(!RegExMatch("NIGHTTIME (04 : 00)`nGRAVEYARD", ClockWatch.DiscRe), "the HUD alone is no disconnect")
}
