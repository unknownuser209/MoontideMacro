#Requires AutoHotkey v2.0
; Bug hunt 2026-11-27 (privacy / remote): a Windows user name with a space
; only half hidden, and the Discord remote replaying a channel's whole
; history after an empty first read. Uses the helpers of test_remote.ahk
; (RemMake, RemMsg, ...), which run.ahk includes before this file.
; Helpers here are prefixed Pf.
#Include ..\lib\ui\UiLogic.ahk
#Include ..\lib\LogBundle.ahk
#Include ..\lib\Remote.ahk

; ---- the Windows user name ----------------------------------------------------

; A local Windows account with a space ("Jane Doe", profile C:\Users\Jane Doe)
; came out as "C:\Users\<user> Doe\...": the path rule stopped at the space,
; and LogBundle's name pass then found no "Jane Doe" left, so the surname went
; into macro.log, the errors webhook card and the support zip.
Test_PrivacyFix_Scrub_SpacedUserName() {
    p := "ERROR x | line 5 | C:\Users\Jane Doe\Downloads\Moontide\lib\App.ahk"
    AssertEq(UiLogic.Scrub(p, "", false, "Jane Doe"), "ERROR x | line 5 | C:\Users\<user>\Downloads\Moontide\lib\App.ahk", "whole name hidden")
    AssertEq(UiLogic.Scrub("saved to c:/users/jane doe/x.png", "", false, "Jane Doe"), "saved to c:/users/<user>/x.png", "any case, forward slashes")
    AssertEq(UiLogic.Scrub("home is C:\Users\Jane Doe", "", false, "Jane Doe"), "home is C:\Users\<user>", "at the end of the text")
    AssertEq(UiLogic.Scrub("C:\Users\Jane Doe\a`r`nC:\Users\Jane Doe\b", "", true, "Jane Doe"), "C:\Users\<user>\a`r`nC:\Users\<user>\b", "every line")
    AssertEq(UiLogic.Scrub("C:\Users\SomeName\x", "", false, "Jane Doe"), "C:\Users\<user>\x", "another account: the old rule")
    AssertEq(UiLogic.Scrub("biome GLITCHED"), "biome GLITCHED", "plain text untouched")
}

; The profile folder keeps the account's first name after a rename (A_UserName
; then differs from it), so this PC's own USERPROFILE folder is hidden too.
Test_PrivacyFix_Scrub_ProfileFolderWithSpace() {
    old := EnvGet("USERPROFILE")
    try {
        EnvSet("USERPROFILE", "C:\Users\Jane Q Public")
        AssertEq(UiLogic.Scrub("could not write C:\Users\Jane Q Public\OneDrive\x.json"), "could not write C:\Users\<user>\OneDrive\x.json", "profile folder hidden")
    } finally {
        EnvSet("USERPROFILE", old)
    }
}

Test_PrivacyFix_LogBundle_SpacedUserName() {
    s := LogBundle.ScrubText("biome items: could not write C:\Users\Jane Doe\OneDrive\x.json: x", "", "Jane Doe")
    AssertEq(s, "biome items: could not write C:\Users\<user>\OneDrive\x.json: x", "support zip text")
    ini := LogBundle.ScrubIni("[General]`r`nalertSound=C:\Users\Jane Doe\Music\ding.wav`r`n", "Jane Doe")
    AssertEq(ini, "[General]`r`nalertSound=C:\Users\<user>\Music\ding.wav`r`n", "settings.ini path value")
    log := LogBundle.TailScrubbed("12:00:00  saved to C:\Users\Jane Doe\AppData\x.png`n", 10, "", "Jane Doe")
    AssertTrue(!InStr(log, "Doe"), "macro.log tail: " log)
}

; ---- the Discord remote -------------------------------------------------------

; Discord's snowflake id for a unix time in ms
PfSnow(ms) => String((ms - 1420070400000) << 22)

; Discord answers 200 [] (not 403) when the bot lacks Read Message History, so
; the first read learnt "0"; once the permission was given, after=0 listed the
; channel's OLDEST messages and every old !start / !stop ran, oldest first.
Test_PrivacyFix_Remote_HiddenHistoryNeverReplays() {
    utc := 1795000000000
    t := RemMake(Map("utcMs", () => utc))
    t.r.Tick()
    t.srv.Respond(200, "[]")                  ; the bot cannot read the history
    t.r.Tick()
    t.clk.t += 5000
    t.r.Tick()
    ; the permission is fixed: Discord now lists the channel's oldest messages
    t.srv.Respond(200, RemJson([RemMsg("5", "!start"), RemMsg("4", "!stop")]))
    t.r.Tick()
    AssertEq(t.calls.Length, 0, "messages from before the remote started are never run")
    q := RemNextReq(t)
    AssertEq(q.url, DiscordRemote.Api "/channels/" RemK.Chan "/messages?limit=1", "learns the newest message again")
    newest := PfSnow(utc + 60000)
    t.srv.Respond(200, RemJson([RemMsg(newest, "!pause")]))
    t.r.Tick()
    AssertEq(t.calls.Length, 0, "the newest message is only learnt")
    t.clk.t += 5000
    t.r.Tick()
    AssertTrue(InStr(t.srv.Last().url, "after=" newest "&"), "then polls after the newest: " t.srv.Last().url)
    RemDrain(t)
    AssertEq(RemReplies(t).Length, 0, "no replies to old messages")
}

; A new, really empty channel still runs what is typed after the start.
Test_PrivacyFix_Remote_EmptyChannelRunsNewCommands() {
    utc := 1795000000000
    t := RemMake(Map("utcMs", () => utc))
    t.r.Tick()
    t.srv.Respond(200, "[]")
    t.r.Tick()
    RemPoll(t, [RemMsg(PfSnow(utc + 3000), "!status")])
    AssertEq(t.calls.Length, 1, "a command typed after the start runs")
    RemDrain(t)
    RemPoll(t, [RemMsg(PfSnow(utc + 9000), "!stats")])
    AssertEq(t.calls.Length, 2, "and the next one")
}

PfRoute(chanJson, req) {
    if InStr(req.url, "/oauth2/applications/@me")
        return [200, '{"flags":524288}']
    if InStr(req.url, "/users/@me")
        return [200, '{"id":"5","username":"MyBot","discriminator":"0"}']
    if InStr(req.url, "/messages")
        return [200, "[]"]
    return [200, chanJson]
}

; Test said "can read #macro" while the bot saw no message at all: the
; channel has a last message, so its history is hidden from the bot.
Test_PrivacyFix_Remote_TestSeesHiddenHistory() {
    t := RemMake()
    t.srv.route := PfRoute.Bind('{"id":"' RemK.Chan '","name":"macro","last_message_id":"' PfSnow(1795000000000) '"}')
    res := t.r.Test()
    AssertTrue(!res.ok, "not ok: " res.msg)
    AssertTrue(InStr(res.msg, "Read Message History") && InStr(res.msg, "#macro"), "says what to give: " res.msg)
    ; a channel that never had a message reads fine
    t.srv.route := PfRoute.Bind('{"id":"' RemK.Chan '","name":"macro","last_message_id":null}')
    res := t.r.Test()
    AssertTrue(res.ok, "empty channel ok: " res.msg)
    AssertEq(res.msg, "Connected as MyBot, can read #macro", "empty channel message")
}

; review: commands typed while the bot still could not read the channel (every
; poll 200 []) ran late once the permission came: the floor stays at the first
; empty read unless it moves on with every empty poll
Test_PrivacyFix_Remote_FloorMovesWhileStillHidden() {
    utc := [1795000000000]
    t := RemMake(Map("utcMs", () => utc[1]))
    t.r.Tick()
    t.srv.Respond(200, "[]")                  ; the first read: nothing readable
    t.r.Tick()
    utc[1] += 600000                          ; ten minutes of empty polls
    RemPoll(t, [])
    utc[1] += 600000
    RemPoll(t, [])
    ; the permission is given: Discord lists a !stop typed 15 min ago, unseen then
    RemPoll(t, [RemMsg(PfSnow(utc[1] - 900000), "!stop")])
    AssertEq(t.calls.Length, 0, "a command the bot could not see when it was typed never runs late")
}
