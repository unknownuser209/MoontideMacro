#Requires AutoHotkey v2.0
; Tests for lib\LogWatch.ahk. Only uses temp dirs under A_Temp (copies of
; tests\fixtures\*.log); never touches the real Roblox log folder.
#Include ..\lib\Json.ahk
#Include ..\lib\LogWatch.ahk

; ---- helpers (names must not start with Test_) -----------------------------

LwTmpDir() {
    d := A_Temp "\vesper_lwtest_" A_TickCount "_" Random(100000, 999999)
    DirCreate(d)
    return d
}

LwTmpClean(d) {
    try DirDelete(d, true)
}

; Copy a fixture into dir under a Roblox-style name with a given mtime (YYYYMMDDHH24MISS).
LwPut(dir, fixture, name, mtime := "") {
    dest := dir "\" name
    FileCopy(A_ScriptDir "\fixtures\" fixture, dest, true)
    if (mtime != "")
        FileSetTime(mtime, dest, "M")
    return dest
}

; Make a watcher that has already finished its startup backfill (empty Player log),
; then append the fixture so a following Poll yields live events.
LwLiveWatch(dir, fixture, name) {
    path := dir "\" name
    FileAppend("", path)
    lw := LogWatch(dir)
    AssertEq(lw.Poll().Length, 0, "LwLiveWatch: empty log, nothing")
    FileAppend(FileRead(A_ScriptDir "\fixtures\" fixture, "UTF-8-RAW"), path, "UTF-8-RAW")
    return lw
}

LwRpc(ts, state, biome) {
    return ts ',1.0,1,6,Info [FLog::CreatorOutput] [BloxstrapRPC] {"command":"SetRichPresence","data":{"state":"' state '","smallImage":{"hoverText":"Sol`'s RNG","assetId":1},"largeImage":{"hoverText":"' biome '","assetId":2}}}'
}

LwEvStr(evs) {
    s := ""
    for ev in evs
        s .= (s = "" ? "" : "|") ev["type"] ":" ev["name"]
    return s
}

; ---- ParseLine -------------------------------------------------------------

Test_LogWatch_ParseBiome() {
    line := '2026-10-24T02:52:32.155Z,15110.155273,7564,6,Info [FLog::CreatorOutput] [BloxstrapRPC] {"command":"SetRichPresence","data":{"state":"Equipped _None_","smallImage":{"hoverText":"Sol`'s RNG","assetId":116713281523271},"largeImage":{"hoverText":"SAND STORM","assetId":102180669654341}}}'
    r := LogWatch.ParseLine(line)
    AssertTrue(r is Map, "LogWatch_ParseBiome: Map result")
    AssertEq(r["biome"], "SAND STORM", "LogWatch_ParseBiome: biome")
    AssertEq(r["aura"], "", "LogWatch_ParseBiome: _None_ means no aura")
    AssertEq(r["ts"], "2026-10-24T02:52:32.155Z", "LogWatch_ParseBiome: ts")
    ; CRLF line ending must not matter
    r2 := LogWatch.ParseLine(line "`r")
    AssertEq(r2["biome"], "SAND STORM", "LogWatch_ParseBiome: CRLF")
    ; non-RPC and garbage lines
    AssertEq(LogWatch.ParseLine("2026-10-24T02:52:20.001Z,1.0,1,6,Info [FLog::Output] hello"), "", "LogWatch_ParseBiome: non-RPC")
    AssertEq(LogWatch.ParseLine(""), "", "LogWatch_ParseBiome: empty")
    AssertEq(LogWatch.ParseLine("x [BloxstrapRPC] {not json"), "", "LogWatch_ParseBiome: bad json")
    AssertEq(LogWatch.ParseLine("x [BloxstrapRPC] [1,2]"), "", "LogWatch_ParseBiome: json not object")
    AssertEq(LogWatch.ParseLine('x [BloxstrapRPC] {"command":"SetLaunchData","data":{}}'), "", "LogWatch_ParseBiome: other command")
}

Test_LogWatch_ParseAura() {
    line := LwRpc("2026-10-24T02:52:40.100Z", 'Equipped \"Eternal Flame\"', "NORMAL")
    r := LogWatch.ParseLine(line)
    AssertEq(r["aura"], "Eternal Flame", "LogWatch_ParseAura: name")
    AssertEq(r["biome"], "NORMAL", "LogWatch_ParseAura: biome")
    AssertEq(r["ts"], "2026-10-24T02:52:40.100Z", "LogWatch_ParseAura: ts")
    r := LogWatch.ParseLine(LwRpc("2026-10-24T02:52:40.100Z", "In Main Menu", "Sol's RNG"))
    AssertEq(r["aura"], "", "LogWatch_ParseAura: main menu no aura")
    AssertEq(r["biome"], "", "LogWatch_ParseAura: main menu no biome")
    r := LogWatch.ParseLine(LwRpc("2026-10-24T02:52:40.100Z", "Equipped _None_", "WINDY"))
    AssertEq(r["aura"], "", "LogWatch_ParseAura: _None_")
}

; ---- PickLog ---------------------------------------------------------------

Test_LogWatch_PicksPlayerLogOverStudio() {
    d := LwTmpDir()
    try {
        player := LwPut(d, "player_biome.log", "0.744.0.7441080_20261023T224042Z_Player_A4304_last.log", "20261024010000")
        LwPut(d, "studio.log", "0.744.0.7441080_20261023T224042Z_Studio_C853B_last.log", "20261024020000")
        LwPut(d, "crashhandler.log", "0.744.0.7441080_20261023T224042Z_Player_E9A51_CrashHandler_last.log", "20261024030000")
        AssertEq(LogWatch.PickLog(d), player, "LogWatch_PicksPlayerLogOverStudio: only Player non-crash")
        ; two player logs: newest by modified wins
        newer := LwPut(d, "player_biome.log", "0.744.0.7441080_20261024T010000Z_Player_B1111_last.log", "20261024015000")
        AssertEq(LogWatch.PickLog(d), newer, "LogWatch_PicksPlayerLogOverStudio: newest player")
    } finally {
        LwTmpClean(d)
    }
    ; no Player log at all
    d2 := LwTmpDir()
    try {
        LwPut(d2, "studio.log", "x_Studio_C853B_last.log")
        AssertEq(LogWatch.PickLog(d2), "", "LogWatch_PicksPlayerLogOverStudio: none")
    } finally {
        LwTmpClean(d2)
    }
    AssertEq(LogWatch.PickLog(A_Temp "\vesper_no_such_dir_xyz"), "", "LogWatch_PicksPlayerLogOverStudio: missing dir")
}

; ---- Poll ------------------------------------------------------------------

Test_LogWatch_DuplicateLines_OneEvent() {
    d := LwTmpDir()
    try {
        lw := LwLiveWatch(d, "player_biome.log", "a_Player_A_last.log")
        evs := lw.Poll()
        ; NORMAL (first seen), SAND STORM x3 -> one, aura None -> none, Eternal Flame x2 -> one
        AssertEq(LwEvStr(evs), "biome:NORMAL|biome:SAND STORM|aura:Eternal Flame", "LogWatch_DuplicateLines_OneEvent: events")
        AssertEq(evs[2]["ts"], "2026-10-24T02:52:32.155Z", "LogWatch_DuplicateLines_OneEvent: ts of first SAND STORM line")
        AssertEq(evs[1].type, "biome", "LogWatch_DuplicateLines_OneEvent: property access")
        AssertEq(evs[1]["live"], true, "LogWatch_DuplicateLines_OneEvent: live")
        AssertEq(lw.Poll().Length, 0, "LogWatch_DuplicateLines_OneEvent: nothing on re-poll")
        AssertEq(lw.CurrentBiome, "SAND STORM", "LogWatch_DuplicateLines_OneEvent: current biome")
        AssertEq(lw.CurrentAura, "Eternal Flame", "LogWatch_DuplicateLines_OneEvent: current aura")
    } finally {
        LwTmpClean(d)
    }
}

Test_LogWatch_OnlyNewBytesRead() {
    d := LwTmpDir()
    try {
        path := LwPut(d, "player_biome.log", "a_Player_A_last.log")
        lw := LogWatch(d)
        lw.Poll()
        size0 := FileGetSize(path)
        AssertEq(lw.Offset, size0, "LogWatch_OnlyNewBytesRead: offset at EOF")
        ; Roblox holds the file open for writing while we read it.
        h := FileOpen(path, "a", "UTF-8-RAW")
        try {
            h.Write(LwRpc("2026-10-24T02:55:00.000Z", "Equipped _None_", "SAND STORM") "`n")   ; same biome, aura cleared
            h.Write(LwRpc("2026-10-24T02:55:10.000Z", "Equipped _None_", "HEAVEN") "`n")
            h.Write(LwRpc("2026-10-24T02:55:20.000Z", "Equipped _None_", "HEAVEN") "`n")
            h.Write(LwRpc("2026-10-24T02:55:30.000Z", "Equipped _None_", "HEAVEN"))           ; partial: no newline yet
            h.Read(0)
            evs := lw.Poll()
            AssertEq(LwEvStr(evs), "aura:|biome:HEAVEN", "LogWatch_OnlyNewBytesRead: new events only (aura cleared, biome)")
            AssertEq(evs[1]["ts"], "2026-10-24T02:55:00.000Z", "LogWatch_OnlyNewBytesRead: aura cleared ts")
            AssertEq(evs[2]["ts"], "2026-10-24T02:55:10.000Z", "LogWatch_OnlyNewBytesRead: biome ts")
            AssertEq(lw.Poll().Length, 0, "LogWatch_OnlyNewBytesRead: partial line not consumed twice")
            h.Write("`n" LwRpc("2026-10-24T02:56:00.000Z", "Equipped _None_", "WINDY") "`n")
        } finally {
            h.Close()
        }
        evs := lw.Poll()
        AssertEq(LwEvStr(evs), "biome:WINDY", "LogWatch_OnlyNewBytesRead: completed partial + next line")
        AssertEq(lw.Offset, FileGetSize(path), "LogWatch_OnlyNewBytesRead: offset advanced to EOF")
    } finally {
        LwTmpClean(d)
    }
}

Test_LogWatch_StartsNearEndOfBigFile() {
    d := LwTmpDir()
    try {
        path := d "\big_Player_A_last.log"
        f := FileOpen(path, "w", "UTF-8-RAW")
        f.Write(LwRpc("2026-10-24T01:00:00.000Z", "Equipped _None_", "HELL") "`n")   ; far outside the tail window
        filler := "2026-10-24T01:00:01.000Z,1.0,1,6,Info [FLog::Output] " Format("{:0200}", 1) "`n"
        Loop 800   ; ~ 200 KB
            f.Write(filler)
        f.Write(LwRpc("2026-10-24T02:00:00.000Z", "Equipped _None_", "GRAVEYARD") "`n")
        f.Close()
        AssertTrue(FileGetSize(path) > 150000, "LogWatch_StartsNearEndOfBigFile: fixture is big")
        lw := LogWatch(d)
        evs := lw.Poll()
        AssertEq(LwEvStr(evs), "biome:GRAVEYARD", "LogWatch_StartsNearEndOfBigFile: only tail window parsed")
        AssertEq(evs[1]["live"], false, "LogWatch_StartsNearEndOfBigFile: backfill event not live")
    } finally {
        LwTmpClean(d)
    }
}

Test_LogWatch_FileSwitchAndTruncate() {
    d := LwTmpDir()
    try {
        LwPut(d, "player_biome.log", "a_Player_A_last.log", "20261024010000")
        lw := LogWatch(d)
        lw.Poll()
        ; new, newer Player log appears: offset resets, whole new file is read
        LwPut(d, "studio.log", "b_Player_B_last.log", "20261024020000")   ; GLITCHED fixture content
        evs := lw.Poll()
        AssertEq(LwEvStr(evs), "biome:GLITCHED|aura:", "LogWatch_FileSwitchAndTruncate: new file read from start; state carried over")
        AssertEq(lw.Poll().Length, 0, "LogWatch_FileSwitchAndTruncate: quiet after switch")
        ; same path rewritten shorter: offset resets
        b := d "\b_Player_B_last.log"
        FileDelete(b)
        FileAppend(LwRpc("2026-10-24T05:00:00.000Z", "Equipped _None_", "WINDY") "`n", b, "UTF-8-RAW")
        FileSetTime("20261024030000", b, "M")
        AssertEq(LwEvStr(lw.Poll()), "biome:WINDY", "LogWatch_FileSwitchAndTruncate: truncated file")
    } finally {
        LwTmpClean(d)
    }
}

Test_LogWatch_NoLogYet() {
    d := LwTmpDir()
    try {
        lw := LogWatch(d)
        AssertEq(lw.Poll().Length, 0, "LogWatch_NoLogYet: empty dir")
    } finally {
        LwTmpClean(d)
    }
    lw := LogWatch(A_Temp "\vesper_no_such_dir_xyz")
    AssertEq(lw.Poll().Length, 0, "LogWatch_NoLogYet: missing dir")
}

Test_LogWatch_StartupBackfill_OneSilentBiome() {
    d := LwTmpDir()
    try {
        ; player_biome: NORMAL, SAND STORM, aura Eternal Flame; merchant: Mari + Jester lines.
        path := LwPut(d, "player_biome.log", "a_Player_A_last.log")
        FileAppend(FileRead(A_ScriptDir "\fixtures\merchant.log", "UTF-8-RAW"), path, "UTF-8-RAW")
        lw := LogWatch(d)
        evs := lw.Poll()
        AssertEq(LwEvStr(evs), "biome:SAND STORM", "LogWatch_Backfill: one biome event, no aura/merchant")
        AssertEq(evs[1]["live"], false, "LogWatch_Backfill: live false")
        AssertEq(evs[1]["ts"], "2026-10-24T02:52:32.155Z", "LogWatch_Backfill: ts of the change into final biome")
        AssertEq(lw.CurrentBiome, "SAND STORM", "LogWatch_Backfill: state set")
        AssertEq(lw.CurrentAura, "Eternal Flame", "LogWatch_Backfill: aura state set silently")
        AssertEq(lw.Poll().Length, 0, "LogWatch_Backfill: nothing on re-poll")
        ; later events are live
        FileAppend(LwRpc("2026-10-24T04:00:00.000Z", "Equipped _None_", "HEAVEN") "`n"
            . "2026-10-24T04:00:01.000Z,1.0,1,6,Info [FLog::Output] Mari has arrived`n", path, "UTF-8-RAW")
        evs := lw.Poll()
        AssertEq(LwEvStr(evs), "biome:HEAVEN|aura:|merchant:Mari", "LogWatch_Backfill: later events")
        for ev in evs
            AssertEq(ev["live"], true, "LogWatch_Backfill: later event live " ev["type"])
    } finally {
        LwTmpClean(d)
    }
}

; Non-I/O errors must propagate and must not advance the offset.
class LwThrowingWatch extends LogWatch {
    _Process(text, events, backfill) {
        throw ValueError("boom")
    }
}

Test_LogWatch_LogicErrorPropagates_OffsetNotAdvanced() {
    d := LwTmpDir()
    try {
        LwPut(d, "player_biome.log", "a_Player_A_last.log")
        lw := LwThrowingWatch(d)
        threw := false
        try
            lw.Poll()
        catch ValueError
            threw := true
        AssertTrue(threw, "LogWatch_LogicError: propagated")
        AssertEq(lw.Offset, 0, "LogWatch_LogicError: offset not advanced")
    } finally {
        LwTmpClean(d)
    }
}

; ---- Merchant --------------------------------------------------------------

Test_LogWatch_MerchantKeyword() {
    AssertEq(LogWatch.ParseMerchant("Info Mari has arrived at the Hub"), "Mari", "LogWatch_MerchantKeyword: Mari arrived")
    AssertEq(LogWatch.ParseMerchant("Jester appeared near the pier"), "Jester", "LogWatch_MerchantKeyword: Jester appeared")
    AssertEq(LogWatch.ParseMerchant("The Jester spawned!"), "Jester", "LogWatch_MerchantKeyword: spawned")
    AssertEq(LogWatch.ParseMerchant("Marigold has arrived"), "", "LogWatch_MerchantKeyword: word boundary")
    AssertEq(LogWatch.ParseMerchant("mari arrived"), "", "LogWatch_MerchantKeyword: case-sensitive")
    AssertEq(LogWatch.ParseMerchant("Mari is selling potions"), "", "LogWatch_MerchantKeyword: no arrival word")
    AssertEq(LogWatch.ParseMerchant("something arrived"), "", "LogWatch_MerchantKeyword: no merchant")
    d := LwTmpDir()
    try {
        lw := LwLiveWatch(d, "merchant.log", "m_Player_A_last.log")
        evs := lw.Poll()
        ; Mari x2 (1 s apart) collapse to one; Marigold/lowercase/no-arrival ignored; Jester once.
        AssertEq(LwEvStr(evs), "merchant:Mari|merchant:Jester", "LogWatch_MerchantKeyword: events")
        AssertEq(evs[1]["ts"], "2026-10-24T03:00:00.000Z", "LogWatch_MerchantKeyword: ts")
        AssertEq(lw.Poll().Length, 0, "LogWatch_MerchantKeyword: no repeat")
    } finally {
        LwTmpClean(d)
    }
}

; 2026-10-27: the log grows ~100 KB a minute, so the last "Equipped" line
; was above the 64 KB tail when the macro started; the aura stayed unknown
; and the obby skipped itself every minute. The skipped part is scanned.
Test_LogWatch_AuraKnownFromAboveTheTail() {
    d := LwTmpDir()
    try {
        path := d "\0.745.0.7451137_20261028T023155Z_Player_46C54_last.log"
        filler := ""
        Loop 1200
            filler .= "2026-10-28T02:35:10.000Z,1.0,1,6,Info [FLog::Output] some other line that pads the log out " A_Index "`n"
        FileAppend(LwRpc("2026-10-28T02:30:00.000Z", "Equipped _None_", "NORMAL") "`n"
            . LwRpc("2026-10-28T02:35:06.514Z", 'Equipped \"Sailor\"', "WINDY") "`n" filler, path, "UTF-8-RAW")
        AssertTrue(FileGetSize(path) > LogWatch.TAIL_BYTES + 1000, "the aura line is above the tail")
        lw := LogWatch(d)
        evs := lw.Poll()
        AssertEq(lw.AuraKnown, true, "aura known at start")
        AssertEq(lw.CurrentAura, "Sailor", "the last aura line above the tail")
        for ev in evs
            AssertTrue(ev["type"] != "aura", "no aura event from the startup scan")
        ; the biome too: rich presence lines only come on a change
        AssertEq(lw.CurrentBiome, "WINDY", "the biome from above the tail")
        bs := []
        for ev in evs
            if (ev["type"] = "biome")
                bs.Push(ev)
        AssertEq(bs.Length, 1, "one startup biome event")
        AssertEq(bs[1]["live"], false, "startup: not live")
        ; a later line in the log wins as before
        FileAppend(LwRpc("2026-10-28T02:40:00.000Z", "Equipped _None_", "WINDY") "`n", path, "UTF-8-RAW")
        lw.Poll()
        AssertEq(lw.CurrentAura, "", "a newer line updates it")
    } finally {
        LwTmpClean(d)
    }
}

