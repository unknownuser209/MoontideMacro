#Requires AutoHotkey v2.0
; Tests for lib\Remote.ahk (Discord remote control). Offline: the http seam
; hands out fake WinHttp requests; nothing ever reaches Discord.
#Include ..\lib\Remote.ahk

; ---- helpers (names must not start with Test_) -----------------------------

class RemK {
    static Tok := "fake-test-only.Qx9Zk2.not-a-real-bot-token-000"
    static Chan := "111222333444555666"
    static Me := "900000000000000001"
}

; Fake Discord: every request is recorded; async ones stay pending until
; Respond(); sync ones (Test()) are answered at once by .route.
class RemFakeSrv {
    __New() {
        this.reqs := []
        this.maxOpen := 0
        this.route := ""
        this.throwOnSend := false
    }
    New() => RemFakeReq(this)
    Open() {
        n := 0
        for r in this.reqs
            if (!r.done && !r.aborted)
                n++
        return n
    }
    Last() => this.reqs[this.reqs.Length]
    ; Answer the oldest pending request.
    Respond(status, body := "", hdr := "") {
        for r in this.reqs {
            if (!r.done && !r.aborted) {
                r.Status := status, r.ResponseText := body, r.hdr := hdr, r.done := true
                return r
            }
        }
        throw Error("RemFakeSrv: nothing pending")
    }
}

class RemFakeReq {
    __New(srv) {
        this.srv := srv, this.headers := Map(), this.done := false, this.aborted := false
        this.Status := 0, this.ResponseText := "", this.hdr := "", this.body := "", this.method := "", this.url := ""
        this.waitThrows := false
    }
    SetTimeouts(a*) {
    }
    Open(method, url, async := false) {
        this.method := method, this.url := url, this.async := async
    }
    SetRequestHeader(k, v) {
        this.headers[k] := v
    }
    Send(body := "") {
        if this.srv.throwOnSend
            throw Error("The server name or address could not be resolved")
        this.body := IsObject(body) ? RemBytes(body) : String(body)
        this.srv.reqs.Push(this)
        this.srv.maxOpen := Max(this.srv.maxOpen, this.srv.Open())
        if (!this.async && HasMethod(this.srv.route, "Call")) {
            a := this.srv.route.Call(this)
            this.Status := a[1], this.ResponseText := a[2], this.done := true
        }
    }
    WaitForResponse(t := -1) {
        if this.waitThrows
            throw Error("connection reset")
        return this.done
    }
    GetResponseHeader(h) => this.hdr
    Abort() {
        this.aborted := true
    }
}

; SAFEARRAY of bytes -> text (UTF-8)
RemBytes(arr) {
    n := arr.MaxIndex() + 1
    if (n <= 0)
        return ""
    pv := NumGet(ComObjValue(arr), 8 + A_PtrSize, "Ptr")
    return StrGet(pv, n, "UTF-8")
}

class RemClock {
    t := 100000
}

; -> {r, srv, clk, logs, calls}
RemMake(extra := "") {
    srv := RemFakeSrv()
    clk := RemClock()
    logs := []
    calls := []
    h := Map()
    for c in ["status", "stats", "start", "stop", "pause", "resume", "log"]
        h[c] := RemHandler.Bind(calls, c)
    d := Map("token", RemK.Tok, "channelId", RemK.Chan, "allowedIds", "12345, " RemK.Me, "pollSec", 5
        , "log", (t) => logs.Push(t), "now", () => clk.t, "http", () => srv.New(), "handlers", h)
    if (extra is Map)
        for k, v in extra
            d[k] := v
    return {r: DiscordRemote(d), srv: srv, clk: clk, logs: logs, calls: calls}
}

RemHandler(calls, name, args, msg) {
    calls.Push(name "|" args "|" msg.authorId)
    return name " ok"
}

; one Discord message as a Map
RemMsg(id, content, author := "", bot := false, extra := "") {
    a := Map("id", author = "" ? RemK.Me : author, "username", "u")
    if bot
        a["bot"] := Json.Raw("true")
    m := Map("id", id, "content", content, "type", 0, "author", a, "attachments", [], "embeds", [])
    if (extra is Map)
        for k, v in extra
            m[k] := v
    return m
}

RemJson(arr) => Json.Stringify(arr, 0)

; Learn step done: newest id = 1000.
RemLearned(t) {
    t.r.Tick()
    t.srv.Respond(200, RemJson([RemMsg("1000", "!stop")]))
    t.r.Tick()
}

; Advance to the next poll and answer it with msgs.
RemPoll(t, msgs) {
    t.clk.t += 5000
    t.r.Tick()
    AssertTrue(InStr(t.srv.Last().url, "after=") > 0, "poll request started")
    t.srv.Respond(200, RemJson(msgs))
    t.r.Tick()
}

; Drain queued replies: tick + answer 200 until nothing is pending (a poll
; that starts meanwhile gets an empty list).
RemDrain(t) {
    loop 20 {
        t.clk.t += 300
        t.r.Tick()
        if (t.srv.Open() = 0)
            return
        t.srv.Respond(200, RemPending(t).method = "GET" ? "[]" : "{}")
    }
}

RemPending(t) {
    for q in t.srv.reqs
        if (!q.done && !q.aborted)
            return q
    return ""
}

; Tick on until a request is pending -> it.
RemNextReq(t) {
    loop 30 {
        if (q := RemPending(t))
            return q
        t.clk.t += 2500
        t.r.Tick()
    }
    throw Error("no request started")
}

RemReplies(t) {
    out := []
    for q in t.srv.reqs
        if (q.method = "POST")
            out.Push(q)
    return out
}

; ---- Parse ------------------------------------------------------------------

Test_Remote_Parse_Cases() {
    p := DiscordRemote.Parse("!help", "!")
    AssertEq(p.cmd, "help", "plain")
    AssertEq(p.args, "", "no args")
    p := DiscordRemote.Parse("  !STATUS  now please ", "!")
    AssertEq(p.cmd, "status", "lower-cased, leading space ok")
    AssertEq(p.args, "now please", "args trimmed")
    p := DiscordRemote.Parse("?log 20", "?")
    AssertEq(p.cmd " " p.args, "log 20", "custom prefix")
    p := DiscordRemote.Parse("mm start", "mm ")
    AssertEq(p.cmd, "start", "word prefix")
    AssertEq(DiscordRemote.Parse("help", "!"), "", "no prefix")
    AssertEq(DiscordRemote.Parse("!", "!"), "", "prefix only")
    AssertEq(DiscordRemote.Parse("! help", "!"), "", "space after prefix")
    AssertEq(DiscordRemote.Parse("!!help", "!"), "", "double prefix")
    AssertEq(DiscordRemote.Parse("", "!"), "", "empty")
    AssertEq(DiscordRemote.Parse("!123", "!"), "", "digits are not a command")
    p := DiscordRemote.Parse("!log`nline two", "!")
    AssertEq(p.args, "line two", "args over a newline")
    AssertEq(DiscordRemote.Parse("!help", "").cmd, "help", "empty prefix -> !")
}

Test_Remote_Enabled() {
    AssertTrue(RemMake().r.Enabled, "all set")
    AssertTrue(!RemMake(Map("allowedIds", "")).r.Enabled, "no users")
    AssertTrue(!RemMake(Map("allowedIds", "bob, alice")).r.Enabled, "non-numeric users")
    AssertTrue(!RemMake(Map("token", "")).r.Enabled, "no token")
    AssertTrue(!RemMake(Map("channelId", "general")).r.Enabled, "channel not digits")
    AssertTrue(!RemMake(Map("token", "abc def ghi jkl mno pqr stu")).r.Enabled, "token with spaces")
    t := RemMake(Map("token", "Bot " RemK.Tok, "pollSec", 1))
    AssertEq(t.r.token, RemK.Tok, "Bot prefix stripped")
    AssertEq(t.r.pollSec, 3, "pollSec at least 3")
    AssertEq(RemMake().r.State, "starting", "state before the first poll")
    AssertEq(RemMake(Map("token", "")).r.State, "off", "state off")
    t := RemMake(Map("allowedIds", ""))
    t.r.Tick()
    AssertEq(t.srv.reqs.Length, 0, "disabled: no request")
}

; ---- polling ----------------------------------------------------------------

Test_Remote_FirstPollOnlyLearns() {
    t := RemMake()
    t.r.Tick()
    q := t.srv.Last()
    AssertEq(q.method, "GET", "GET")
    AssertEq(q.url, DiscordRemote.Api "/channels/" RemK.Chan "/messages?limit=1", "learn url")
    AssertTrue(q.async, "async open")
    AssertEq(q.headers["Authorization"], "Bot " RemK.Tok, "auth header")
    AssertEq(q.headers["User-Agent"], "DiscordBot (MoontideMacro, 1.0)", "user agent")
    t.srv.Respond(200, RemJson([RemMsg("1000", "!start")]))
    t.r.Tick()
    AssertEq(t.calls.Length, 0, "old command never run")
    AssertEq(t.srv.Open(), 0, "no reply to the old command")
    AssertEq(t.r.State, "listening", "listening")
    t.clk.t += 1000
    t.r.Tick()
    AssertEq(t.srv.reqs.Length, 1, "no poll before pollSec")
    t.clk.t += 4000
    t.r.Tick()
    AssertEq(t.srv.Last().url, DiscordRemote.Api "/channels/" RemK.Chan "/messages?after=1000&limit=10", "poll url after learnt id")
}

Test_Remote_EmptyChannelLearnsZero() {
    t := RemMake()
    t.r.Tick()
    t.srv.Respond(200, "[]")
    t.r.Tick()
    t.clk.t += 5000
    t.r.Tick()
    AssertTrue(InStr(t.srv.Last().url, "after=0&") > 0, "empty channel: after=0")
}

Test_Remote_DispatchOldestFirst() {
    t := RemMake()
    RemLearned(t)
    ; Discord lists newest first
    RemPoll(t, [RemMsg("1003", "!stop"), RemMsg("1002", "!stats"), RemMsg("1001", "!start fast", "12345")])
    AssertEq(t.calls.Length, 3, "three commands run")
    AssertEq(t.calls[1], "start|fast|12345", "oldest first, args, author")
    AssertEq(t.calls[2], "stats||" RemK.Me, "second")
    AssertEq(t.calls[3], "stop||" RemK.Me, "newest last")
    RemDrain(t)
    reps := RemReplies(t)
    AssertEq(reps.Length, 3, "three replies")
    AssertEq(reps[1].url, DiscordRemote.Api "/channels/" RemK.Chan "/messages", "reply url")
    AssertTrue(InStr(reps[1].body, '"content":"start ok"'), "reply text")
    AssertTrue(InStr(reps[1].body, '"message_id":"1001"'), "replies to the command")
    AssertTrue(InStr(reps[1].body, '"parse":[]'), "never pings")
    AssertTrue(InStr(reps[1].headers["Content-Type"], "application/json"), "json reply")
    ; next poll continues after the newest
    t.clk.t += 5000
    t.r.Tick()
    AssertTrue(InStr(t.srv.Last().url, "after=1003&"), "lastId moved to newest")
    ; the same messages again (overlap) are not run twice
    t.srv.Respond(200, RemJson([RemMsg("1003", "!stop")]))
    t.r.Tick()
    AssertEq(t.calls.Length, 3, "no re-run")
}

Test_Remote_IgnoresStrangersBotsNoPrefix() {
    t := RemMake()
    RemLearned(t)
    RemPoll(t, [RemMsg("1001", "!start", "555555555555")
        , RemMsg("1002", "!stop", "555555555555")
        , RemMsg("1003", "!start", RemK.Me, true)
        , RemMsg("1004", "just chatting")
        , RemMsg("1005", "!status", RemK.Me, false, Map("webhook_id", "77777"))])
    AssertEq(t.calls.Length, 0, "nothing run")
    RemDrain(t)
    AssertEq(RemReplies(t).Length, 0, "no replies")
    n := 0
    for l in t.logs {
        if InStr(l, "555555555555")
            n++
        AssertTrue(!InStr(l, "!start") && !InStr(l, "chatting"), "message text never logged: " l)
    }
    AssertEq(n, 1, "stranger logged once")
}

Test_Remote_UnknownCommandAndHelp() {
    t := RemMake(Map("handlers", Map("status", (a, m) => "fine", "explode", (a, m) => "x")))
    RemLearned(t)
    RemPoll(t, [RemMsg("1001", "!dance"), RemMsg("1002", "!start"), RemMsg("1003", "!help"), RemMsg("1004", "!explode")])
    RemDrain(t)
    reps := RemReplies(t)
    AssertEq(reps.Length, 4, "four replies")
    AssertTrue(InStr(reps[1].body, "Unknown command. Try !help"), "unknown")
    AssertTrue(InStr(reps[2].body, "Unknown command"), "whitelisted but no handler")
    AssertTrue(InStr(reps[3].body, "!status") && InStr(reps[3].body, "!help"), "help lists handlers")
    AssertTrue(!InStr(reps[3].body, "!start") && !InStr(reps[3].body, "explode"), "help leaves out missing / non-whitelisted")
    AssertTrue(InStr(reps[4].body, "Unknown command"), "non-whitelisted handler ignored")
}

Test_Remote_HandlerThrowsAndEmptyReply() {
    boom(a, m) {
        throw Error("bad thing with " RemK.Tok)
    }
    t := RemMake(Map("handlers", Map("stop", boom, "pause", (a, m) => "")))
    RemLearned(t)
    RemPoll(t, [RemMsg("1001", "!stop"), RemMsg("1002", "!pause")])
    RemDrain(t)
    reps := RemReplies(t)
    AssertEq(reps.Length, 1, "empty reply sends nothing")
    AssertTrue(InStr(reps[1].body, "That command failed."), "failure reply")
    for l in t.logs
        AssertTrue(!InStr(l, RemK.Tok), "token scrubbed from error log")
}

Test_Remote_FileReplyMultipart() {
    png := A_Temp "\rem_test_" A_TickCount ".png"
    try FileDelete(png)
    FileAppend("PNGDATA", png, "UTF-8-RAW")
    t := RemMake(Map("handlers", Map("status", (a, m) => {text: "here", file: png}, "stats", (a, m) => Map("text", "gone", "file", png ".missing"))))
    RemLearned(t)
    RemPoll(t, [RemMsg("1001", "!status"), RemMsg("1002", "!stats")])
    RemDrain(t)
    try FileDelete(png)
    reps := RemReplies(t)
    AssertEq(reps.Length, 2, "two replies")
    ct := reps[1].headers["Content-Type"]
    AssertTrue(InStr(ct, "multipart/form-data; boundary=") = 1, "multipart content type")
    b := reps[1].body
    AssertTrue(InStr(b, 'name="payload_json"') && InStr(b, '"content":"here"'), "payload_json part")
    AssertTrue(InStr(b, 'name="files[0]"; filename="') && InStr(b, "Content-Type: image/png"), "file part")
    AssertTrue(InStr(b, "PNGDATA"), "file bytes")
    AssertTrue(InStr(reps[2].headers["Content-Type"], "application/json"), "missing file -> plain json")
    AssertTrue(InStr(reps[2].body, "could not be attached"), "missing file noted")
}

Test_Remote_OneRequestInFlight() {
    t := RemMake()
    RemLearned(t)
    RemPoll(t, [RemMsg("1001", "!status"), RemMsg("1002", "!stats"), RemMsg("1003", "!log")])
    loop 5 {
        t.clk.t += 1000
        t.r.Tick()
    }
    AssertEq(t.srv.Open(), 1, "only one pending while not answered")
    RemDrain(t)
    AssertEq(t.srv.maxOpen, 1, "never two at once")
    AssertEq(RemReplies(t).Length, 3, "all replies sent one by one")
}

; ---- errors -----------------------------------------------------------------

Test_Remote_429Backoff() {
    t := RemMake()
    RemLearned(t)
    t.clk.t += 5000
    t.r.Tick()
    t.srv.Respond(429, '{"message":"You are being rate limited.","retry_after":12.5,"global":false}')
    t.r.Tick()
    n := t.srv.reqs.Length
    t.clk.t += 12000
    t.r.Tick()
    AssertEq(t.srv.reqs.Length, n, "still waiting at 12 s")
    t.clk.t += 600
    t.r.Tick()
    AssertEq(t.srv.reqs.Length, n + 1, "polls again after retry_after")
    ; a reply hit by 429 is resent after the wait
    t.srv.Respond(200, RemJson([RemMsg("1001", "!status")]))
    t.r.Tick()
    AssertEq(t.srv.Last().method, "POST", "reply sent")
    t.srv.Respond(429, "", "3")
    t.r.Tick()
    t.clk.t += 2900
    t.r.Tick()
    AssertEq(RemReplies(t).Length, 1, "reply held by Retry-After header")
    t.clk.t += 200
    t.r.Tick()
    AssertEq(RemReplies(t).Length, 2, "reply resent")
}

Test_Remote_401Stops() {
    t := RemMake()
    t.r.Tick()
    t.srv.Respond(401, '{"message": "401: Unauthorized", "code": 0}')
    t.r.Tick()
    AssertEq(t.r.State, "stopped", "stopped")
    loop 10 {
        t.clk.t += 10000
        t.r.Tick()
    }
    AssertEq(t.srv.reqs.Length, 1, "no more polling")
    n := 0
    for l in t.logs
        if InStr(l, "bot token rejected")
            n++
    AssertEq(n, 1, "logged once")
    AssertTrue(InStr(t.r.LastError, "token rejected"), "LastError")
}

Test_Remote_403Stops() {
    t := RemMake()
    RemLearned(t)
    t.clk.t += 5000
    t.r.Tick()
    t.srv.Respond(403, '{"message": "Missing Access", "code": 50001}')
    t.r.Tick()
    AssertEq(t.r.State, "stopped", "stopped")
    found := false
    for l in t.logs
        if InStr(l, "cannot read that channel - check its permissions and the Message Content intent")
            found := true
    AssertTrue(found, "403 hint logged")
    t.clk.t += 60000
    t.r.Tick()
    AssertEq(t.srv.Open(), 0, "no more requests")
    t.r.Reset()
    t.r.Tick()
    AssertTrue(InStr(t.srv.Last().url, "?limit=1"), "Reset learns again")
}

Test_Remote_NetworkBackoff() {
    t := RemMake()
    t.r.Tick()
    t.srv.Last().waitThrows := true
    t.r.Tick()
    AssertEq(t.r.State, "retrying", "retrying")
    n := t.srv.reqs.Length
    t.clk.t += 4900
    t.r.Tick()
    AssertEq(t.srv.reqs.Length, n, "waits 5 s")
    t.clk.t += 200
    t.r.Tick()
    AssertEq(t.srv.reqs.Length, n + 1, "retry after 5 s")
    ; timeout: nothing answered for 8 s -> aborted, next wait 10 s
    q := t.srv.Last()
    t.clk.t += 8100
    t.r.Tick()
    AssertTrue(q.aborted, "timed-out request aborted")
    n := t.srv.reqs.Length
    t.clk.t += 9900
    t.r.Tick()
    AssertEq(t.srv.reqs.Length, n, "waits 10 s")
    t.clk.t += 200
    t.r.Tick()
    AssertEq(t.srv.reqs.Length, n + 1, "retry after 10 s")
    ; 5xx -> 20 s
    t.srv.Respond(502, "bad gateway")
    t.r.Tick()
    n := t.srv.reqs.Length
    t.clk.t += 19900
    t.r.Tick()
    AssertEq(t.srv.reqs.Length, n, "waits 20 s")
    ; send throws (no network) -> 40, then capped at 60
    t.srv.throwOnSend := true
    loop 4 {
        t.clk.t += 61000
        t.r.Tick()
    }
    AssertEq(t.r._backoff, 60, "capped at 60 s")
    t.srv.throwOnSend := false
    t.clk.t += 61000
    t.r.Tick()
    t.srv.Respond(200, "[]")
    t.r.Tick()
    AssertEq(t.r.State, "listening", "recovered")
    RemNextReq(t).waitThrows := true            ; a second outage
    t.r.Tick()
    nNet := 0
    for l in t.logs
        if InStr(l, "cannot reach Discord")
            nNet++
    AssertEq(nNet, 2, "logged once per outage (two outages)")
}

Test_Remote_EmptyContentHint() {
    t := RemMake()
    RemLearned(t)
    RemPoll(t, [RemMsg("1001", ""), RemMsg("1002", ""), RemMsg("1003", "", "555555555555")])
    n := 0
    for l in t.logs
        if InStr(l, "MESSAGE CONTENT INTENT")
            n++
    AssertEq(n, 1, "hint once")
    ; an image post from an allowed user is not a missing intent
    t2 := RemMake()
    RemLearned(t2)
    RemPoll(t2, [RemMsg("1001", "", RemK.Me, false, Map("attachments", [Map("id", "1")]))])
    for l in t2.logs
        AssertTrue(!InStr(l, "MESSAGE CONTENT INTENT"), "no hint for an image post")
}

Test_Remote_TokenNeverLogged() {
    t := RemMake(Map("handlers", Map("log", (a, m) => "token is " RemK.Tok, "status", (a, m) => {text: "Bot " RemK.Tok, file: ""})))
    RemLearned(t)
    RemPoll(t, [RemMsg("1001", "!log"), RemMsg("1002", "!status"), RemMsg("1003", "!x", "444444444444")])
    RemDrain(t)
    RemNextReq(t).waitThrows := true
    t.r.Tick()
    RemNextReq(t)
    t.srv.Respond(401, "")
    t.r.Tick()
    AssertTrue(t.logs.Length >= 4, "several log lines")
    for l in t.logs
        AssertTrue(!InStr(l, RemK.Tok) && !InStr(l, "Qx9Zk2"), "token in log: " l)
    for q in RemReplies(t)
        AssertTrue(!InStr(q.body, RemK.Tok), "token in a reply")
    AssertTrue(!InStr(t.r.LastError, RemK.Tok), "token in LastError")
    AssertTrue(!InStr(t.r.Scrub("x Bot " RemK.Tok " y"), "Qx9Zk2"), "Scrub")
}

Test_Remote_TestButton() {
    t := RemMake()
    t.srv.route := RemRoute.Bind(Map())
    res := t.r.Test()
    AssertTrue(res.ok, "ok: " res.msg)
    AssertEq(res.msg, "Connected as MyBot#1234, can read #macro", "message")
    AssertEq(t.srv.reqs[1].url, DiscordRemote.Api "/users/@me", "users/@me")
    AssertEq(t.srv.reqs[2].url, DiscordRemote.Api "/channels/" RemK.Chan, "channel")
    t.srv.route := RemRoute.Bind(Map("me", 401))
    res := t.r.Test()
    AssertTrue(!res.ok && InStr(res.msg, "token rejected"), "401")
    t.srv.route := RemRoute.Bind(Map("chan", 403))
    res := t.r.Test()
    AssertTrue(!res.ok && InStr(res.msg, "cannot see that channel"), "403 channel")
    t.srv.route := RemRoute.Bind(Map("chan", 404))
    AssertTrue(InStr(t.r.Test().msg, "not found"), "404 channel")
    t.srv.route := RemRoute.Bind(Map("msgs", 403))
    AssertTrue(InStr(t.r.Test().msg, "Read Message History"), "403 messages")
    t.srv.throwOnSend := true
    res := t.r.Test()
    AssertTrue(!res.ok && InStr(res.msg, "Could not reach Discord"), "network error")
    AssertTrue(!RemMake(Map("token", "")).r.Test().ok, "missing token")
}

RemRoute(fail, req) {
    if InStr(req.url, "/users/@me")
        return fail.Has("me") ? [fail["me"], "{}"] : [200, '{"id":"5","username":"MyBot","discriminator":"1234"}']
    if InStr(req.url, "/messages")
        return fail.Has("msgs") ? [fail["msgs"], "{}"] : [200, "[]"]
    return fail.Has("chan") ? [fail["chan"], "{}"] : [200, '{"id":"' RemK.Chan '","name":"macro"}']
}
