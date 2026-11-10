#Requires AutoHotkey v2.0
; Tests for lib\Webhook.ahk and lib\Screenshot.ahk (offline: no network, a
; fake WinHttp-like request object is injected via Webhook.httpFactory).
#Include ..\lib\Json.ahk
#Include ..\lib\Config.ahk
#Include ..\lib\Webhook.ahk
#Include ..\lib\Screenshot.ahk

; ---- helpers (names must not start with Test_) -----------------------------

class WhStubCfg {
    __New(list) {
        this._list := list
    }
    Webhooks() {
        return this._list
    }
}

WhMake(name, url, mention, enabled, events) {
    return Map("name", name, "url", url, "mention", mention, "enabled", enabled, "events", events)
}

WhFakeUrl(tag) {
    return "https://discord.com/api/webhooks/123456789/SECRET" tag
}

WhWriteBytes(path, bytes) {
    buf := Buffer(bytes.Length)
    for i, v in bytes
        NumPut("UChar", v, buf, i - 1)
    fh := FileOpen(path, "w")
    fh.RawWrite(buf)
    fh.Close()
}

WhThrows(fn) {
    try fn()
    catch
        return true
    return false
}

; Fake request. plan item: {status, sendError, pending}
class WhFakeReq {
    __New(step, owner) {
        this._step := step
        this._owner := owner
        this._polls := 0
        this._hdr := Map()
        this.aborted := false
    }
    Open(method, url, async) {
        this._owner.opened.Push(Map("method", method, "url", url, "async", async))
    }
    SetRequestHeader(k, v) {
        this._hdr[k] := v
    }
    SetTimeouts(a, b, c, d) {
    }
    Send(body := "") {
        this._owner.bodies.Push(body)
        this._owner.headers.Push(this._hdr)
        if (this._step.sendError != "")
            throw Error(this._step.sendError)
    }
    WaitForResponse(t := 0) {
        this._polls++
        return this._polls > this._step.pending
    }
    Abort() {
        this.aborted := true
    }
    Status => this._step.status
    ; plan item may add body (response text) and headers (Map); a missing
    ; header throws like WinHttp's GetResponseHeader
    ResponseText => this._step.HasOwnProp("body") ? this._step.body : ""
    GetResponseHeader(name) {
        if (this._step.HasOwnProp("headers") && this._step.headers.Has(name))
            return this._step.headers[name]
        throw Error("header not found")
    }
}

class WhFakeHttp {
    __New(plan) {
        this.plan := plan
        this.made := 0
        this.opened := []
        this.bodies := []
        this.headers := []
        this.reqs := []
    }
    Make() {
        this.made++
        step := this.plan.Length >= this.made ? this.plan[this.made] : {status: 204, sendError: "", pending: 0}
        r := WhFakeReq(step, this)
        this.reqs.Push(r)
        return r
    }
}

; SAFEARRAY(VT_UI1) body -> Buffer
WhBytes(arr) {
    n := arr.MaxIndex(1) - arr.MinIndex(1) + 1
    buf := Buffer(n)
    if (n > 0)
        DllCall("RtlMoveMemory", "Ptr", buf.Ptr, "Ptr", NumGet(ComObjValue(arr), 8 + A_PtrSize, "Ptr"), "UPtr", n)
    return buf
}

; 1-based offset of byte sequence (array of ints) in buf, 0 if absent
WhFind(buf, bytes) {
    last := buf.Size - bytes.Length
    Loop last + 1 {
        i := A_Index - 1
        hit := true
        for j, v in bytes {
            if (NumGet(buf, i + j - 1, "UChar") != v) {
                hit := false
                break
            }
        }
        if hit
            return i + 1
    }
    return 0
}

WhFindStr(buf, s) {
    bytes := []
    Loop Parse, s
        bytes.Push(Ord(A_LoopField))
    return WhFind(buf, bytes)
}

Test_Webhook_LinkButtonUsesWithComponentsAndFallsBack() {
    wh := WhNewLive([WhStep(400), WhStep(204)], &fake, &logs)
    wh.Send("biome", "", "card", 0x123456, {buttons: [{label: "Join Server", url: "https://www.roblox.com/share?code=X&type=Server"}
        , {label: "bad", url: "javascript:alert(1)"}]})
    wh.Flush()
    wh.Flush()
    AssertEq(fake.opened.Length, 2, "sent, refused, sent again")
    AssertTrue(InStr(fake.opened[1]["url"], "?with_components=true"), "first send asks Discord to keep the button")
    AssertTrue(!InStr(fake.opened[2]["url"], "with_components"), "the resend has no button and no flag")
    b1 := WhBytes(fake.bodies[1])
    AssertTrue(WhFindStr(b1, '"style":5') > 0, "link button in the first body")
    AssertEq(WhFindStr(b1, "javascript"), 0, "a non-https button is dropped")
    AssertEq(WhFindStr(WhBytes(fake.bodies[2]), "components"), 0, "resend without components")
    for l in logs
        AssertTrue(!InStr(l, "discord.com/api/webhooks"), "no webhook url in the log")
    ; without buttons the URL is unchanged
    wh2 := WhNewLive([WhStep(204)], &fake2, &logs2)
    wh2.Send("biome", "t", "d", 0)
    wh2.Flush()
    AssertTrue(!InStr(fake2.opened[1]["url"], "with_components"), "plain message: plain URL")
}

WhStep(status, sendError := "", pending := 0) {
    return {status: status, sendError: sendError, pending: pending}
}

WhNewLive(plan, &fake, &logs) {
    logs := []
    list := [WhMake("main", WhFakeUrl("A"), "", 1, ["biome", "errors"])]
    wh := Webhook(WhStubCfg(list), (msg) => logs.Push(msg))
    fake := WhFakeHttp(plan)
    wh.httpFactory := fake.Make.Bind(fake)
    wh.retryDelayMs := 0
    return wh
}

; ---- Routing ---------------------------------------------------------------

Test_Webhook_RoutesOnlyEnabledAndChecked() {
    list := [
        WhMake("a", WhFakeUrl("a"), "", 1, ["biome", "rare"]),
        WhMake("b", WhFakeUrl("b"), "", 0, ["biome", "rare"]),      ; disabled
        WhMake("c", WhFakeUrl("c"), "", 1, ["merchant"]),           ; not checked
        WhMake("d", WhFakeUrl("d"), "", 1, ["biome"])
    ]
    wh := Webhook(WhStubCfg(list))
    r := wh.Route("biome")
    AssertEq(r.Length, 2, "biome route count")
    AssertEq(r[1]["name"], "a", "first routed")
    AssertEq(r[2]["name"], "d", "second routed")
    AssertEq(wh.Route("rare").Length, 1, "rare route count")
    AssertEq(wh.Route("merchant").Length, 1, "merchant route count (c only)")
    AssertEq(wh.Route("merchant")[1]["name"], "c", "merchant route name")
    AssertEq(wh.Route("clips").Length, 0, "unchecked event routes nowhere")
    AssertTrue(WhThrows(() => wh.Route("bogus")), "unknown event throws")
}

Test_Webhook_EventTypesMatchConfig() {
    AssertEq(Webhook.EventTypes.Length, Config.EventTypes.Length, "event count")
    for i, e in Config.EventTypes
        AssertEq(Webhook.EventTypes[i], e, "event " i)
    for ev in ["obby", "memorymatch"] {
        has := false
        for e in Webhook.EventTypes
            has := has || (e = ev)
        AssertTrue(has, "Webhook has " ev)
    }
    AssertEq(Dashboard.Events.Length, Config.EventTypes.Length, "dashboard event count")
    for i, e in Config.EventTypes
        AssertEq(Dashboard.Events[i], e, "dashboard event " i)
}

Test_Webhook_SendQueuesOnePerRoute() {
    list := [
        WhMake("a", WhFakeUrl("a"), "", 1, ["biome"]),
        WhMake("b", WhFakeUrl("b"), "", 0, ["biome"]),
        WhMake("c", WhFakeUrl("c"), "", 1, ["biome"])
    ]
    wh := Webhook(WhStubCfg(list))
    wh.dryRun := true
    wh.Send("biome", "t", "d", 0x112233)
    wh.Send("merchant", "t", "d", 0x112233)   ; nobody listens
    AssertEq(wh.sent.Length, 0, "nothing sent before Flush")
    wh.Flush()
    AssertEq(wh.sent.Length, 2, "two recipients")
    AssertEq(wh.sent[1].name, "a", "rec1 name")
    AssertEq(wh.sent[2].name, "c", "rec2 name")
    AssertEq(wh.sent[1].event, "biome", "rec1 event")
    AssertEq(wh.Pending(), 0, "queue drained")
}

; ---- Payload / mention -----------------------------------------------------

Test_Webhook_PayloadShape() {
    list := [WhMake("a", WhFakeUrl("a"), "", 1, ["biome"])]
    wh := Webhook(WhStubCfg(list))
    wh.dryRun := true
    wh.Send("biome", "Biome: GLITCHED", "desc text", 0xF2A93B)
    wh.Flush()
    obj := Json.Parse(wh.sent[1].json)
    AssertEq(obj.Has("content"), false, "no content without mention")
    e := obj["embeds"][1]
    AssertEq(e["title"], Emoji.Globe " Biome: GLITCHED", "title gets the biome emoji")
    AssertEq(e["footer"]["text"], Brand.Footer, "footer")
    AssertEq(e["description"], "desc text", "desc")
    AssertEq(e["color"], 0xF2A93B, "color")
    AssertEq(e.Has("timestamp"), true, "timestamp")
    AssertTrue(RegExMatch(e["timestamp"], "^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$"), "timestamp format")
    AssertEq(wh.sent[1].screenshot, "", "no screenshot")
}

Test_Webhook_MentionOnlyWhenRequested() {
    list := [
        WhMake("user", WhFakeUrl("u"), "123456789", 1, ["rare"]),
        WhMake("role", WhFakeUrl("r"), "@&987654321", 1, ["rare"]),
        WhMake("none", WhFakeUrl("n"), "", 1, ["rare"]),
        WhMake("junk", WhFakeUrl("j"), "everyone!", 1, ["rare"])
    ]
    wh := Webhook(WhStubCfg(list))
    wh.dryRun := true

    wh.Send("rare", "t", "d", 1)                              ; default opts
    wh.Send("rare", "t", "d", 1, {mention: false})
    wh.Flush()
    for rec in wh.sent
        AssertEq(Json.Parse(rec.json).Has("content"), false, "no mention " rec.name)

    wh.sent := []
    wh.Send("rare", "t", "d", 1, {mention: true})
    wh.Flush()
    AssertEq(wh.sent.Length, 4, "four recipients")
    AssertEq(Json.Parse(wh.sent[1].json)["content"], "<@123456789>", "user mention")
    AssertEq(Json.Parse(wh.sent[2].json)["content"], "<@&987654321>", "role mention")
    AssertEq(Json.Parse(wh.sent[3].json).Has("content"), false, "no mention id set")
    AssertEq(Json.Parse(wh.sent[4].json).Has("content"), false, "invalid mention ignored")
    ; allowed_mentions restricts pings to the intended id
    am := Json.Parse(wh.sent[1].json)["allowed_mentions"]
    AssertEq(am["users"][1], "123456789", "allowed user")
    am2 := Json.Parse(wh.sent[2].json)["allowed_mentions"]
    AssertEq(am2["roles"][1], "987654321", "allowed role")
    AssertEq(Json.Parse(wh.sent[3].json)["allowed_mentions"]["parse"].Length, 0, "no pings when no mention")

    ; opts as Map works too
    wh.sent := []
    wh.Send("rare", "t", "d", 1, Map("mention", true))
    wh.Flush()
    AssertEq(Json.Parse(wh.sent[1].json)["content"], "<@123456789>", "Map opts mention")
}

Test_Webhook_MentionNormalise() {
    AssertEq(Webhook.NormalizeMention("123"), "<@123>", "plain id")
    AssertEq(Webhook.NormalizeMention("@123"), "<@123>", "at id")
    AssertEq(Webhook.NormalizeMention("@&123"), "<@&123>", "at-amp role")
    AssertEq(Webhook.NormalizeMention("&123"), "<@&123>", "amp role")
    AssertEq(Webhook.NormalizeMention("<@123>"), "<@123>", "already user")
    AssertEq(Webhook.NormalizeMention("<@&123>"), "<@&123>", "already role")
    AssertEq(Webhook.NormalizeMention("  123  "), "<@123>", "trim")
    AssertEq(Webhook.NormalizeMention(""), "", "empty")
    AssertEq(Webhook.NormalizeMention("@everyone"), "", "everyone rejected")
    AssertEq(Webhook.NormalizeMention("12ab"), "", "garbage rejected")
}

; ---- Sending (fake transport) ----------------------------------------------

Test_Webhook_AsyncSendAndRelease() {
    wh := WhNewLive([WhStep(204, "", 2)], &fake, &logs)
    wh.Send("biome", "t", "d", 1)
    wh.Flush()
    AssertEq(fake.made, 1, "one request made")
    AssertEq(fake.opened[1]["async"], true, "Open async=true")
    AssertEq(fake.opened[1]["method"], "POST", "POST")
    AssertEq(wh.Pending(), 1, "in flight after first Flush")
    wh.Flush()   ; poll 1: still pending (no blocking)
    AssertEq(wh.Pending(), 1, "still in flight")
    wh.Flush()   ; poll 2 pending
    wh.Flush()   ; poll 3 done
    AssertEq(wh.Pending(), 0, "released after done")
    AssertEq(fake.made, 1, "no retry on 2xx")
}

Test_Webhook_RetriesOnce() {
    ; non-2xx then success -> exactly 2 requests
    wh := WhNewLive([WhStep(500), WhStep(204)], &fake, &logs)
    wh.Send("biome", "t", "d", 1)
    wh.Flush()          ; send #1
    wh.Flush()          ; poll #1 -> fail, requeue
    wh.Flush()          ; send #2
    wh.Flush()          ; poll #2 -> ok
    AssertEq(fake.made, 2, "retried once then ok")
    AssertEq(wh.Pending(), 0, "drained")

    ; exception then non-2xx -> gives up after 2 attempts (429 is a rate
    ; limit, not a failure: Test_Webhook_RateLimit429WaitsRetryAfter)
    wh := WhNewLive([WhStep(0, "boom"), WhStep(503), WhStep(204)], &fake, &logs)
    wh.Send("biome", "t", "d", 1)
    Loop 8
        wh.Flush()
    AssertEq(fake.made, 2, "gave up after one retry")
    AssertEq(wh.Pending(), 0, "nothing left")
}

; 2026-10-27 review: one rare event queues 9+ cards at once; Discord allows
; about 5 per 2 s per webhook and the rest were lost to HTTP 429.
Test_Webhook_PacedPerUrl() {
    wh := WhNewLive([], &fake, &logs)
    t := 10000
    wh.clock := () => t
    Loop 6
        wh.Send("biome", "t" A_Index, "d", 1)
    wh.Flush()
    AssertEq(fake.made, 4, "at most 4 requests per 2 s to one webhook")
    t += 1000
    wh.Flush()
    AssertEq(fake.made, 4, "still inside the window")
    t += 1001
    wh.Flush()
    AssertEq(fake.made, 6, "the rest once the window has passed")
    b5 := WhBytes(fake.bodies[5])
    AssertTrue(WhFindStr(b5, ' t5"') > 0, "order kept")
    ; the limit is per URL: two webhooks get 3 each at once
    list := [WhMake("a", WhFakeUrl("A"), "", 1, ["biome"]), WhMake("b", WhFakeUrl("B"), "", 1, ["biome"])]
    wh2 := Webhook(WhStubCfg(list))
    fake2 := WhFakeHttp([])
    wh2.httpFactory := fake2.Make.Bind(fake2)
    wh2.clock := () => t
    Loop 3
        wh2.Send("biome", "t", "d", 1)
    wh2.Flush()
    AssertEq(fake2.made, 6, "3 + 3 on two webhooks: none held back")
    ; dry run is not paced
    wh3 := Webhook(WhStubCfg(list))
    wh3.dryRun := true
    Loop 5
        wh3.Send("biome", "t", "d", 1)
    wh3.Flush()
    AssertEq(wh3.sent.Length, 10, "dry run records everything at once")
}

Test_Webhook_RateLimit429WaitsRetryAfter() {
    body := '{"message": "You are being rate limited.", "retry_after": 3.5, "global": false}'
    wh := WhNewLive([{status: 429, sendError: "", pending: 0, body: body}, WhStep(500), WhStep(204)], &fake, &logs)
    t := 50000
    wh.clock := () => t
    wh.Send("biome", "t", "d", 1)
    wh.Flush()                                  ; send #1 -> 429
    wh.Flush()                                  ; poll: hold 3.5 s
    AssertEq(fake.made, 1, "not resent at once")
    t += 3000
    wh.Flush()
    AssertEq(fake.made, 1, "waits Discord's retry_after")
    t += 600
    wh.Flush()
    AssertEq(fake.made, 2, "resent after retry_after")
    Loop 4
        wh.Flush()                              ; #2 -> 500 (a real failure): one retry
    AssertEq(fake.made, 3, "the 429 did not use up the one retry")
    AssertEq(wh.Pending(), 0, "delivered")
    for l in logs
        AssertTrue(!InStr(l, "discord.com/api/webhooks"), "no url in the log: " l)
    ; Retry-After header (no body): every message to that URL waits
    wh := WhNewLive([{status: 429, sendError: "", pending: 0, headers: Map("Retry-After", "2")}, WhStep(204), WhStep(204), WhStep(204)], &fake, &logs)
    wh.clock := () => t
    wh.Send("biome", "a", "d", 1)
    wh.Send("biome", "b", "d", 1)
    wh.Flush()                                  ; a -> 429, b -> 204
    wh.Flush()                                  ; poll
    wh.Send("biome", "c", "d", 1)
    t += 1500
    wh.Flush()
    AssertEq(fake.made, 2, "the URL is held: c waits too")
    t += 600
    wh.Flush()
    AssertEq(fake.made, 4, "a and c sent after Retry-After")
    ; a message limited again and again is given up in the end
    plan := []
    Loop 10
        plan.Push({status: 429, sendError: "", pending: 0, body: '{"retry_after": 0.3}'})
    wh := WhNewLive(plan, &fake, &logs)
    wh.clock := () => t
    res := []
    wh.SendTo(WhMake("main", WhFakeUrl("A"), "", 1, ["biome"]), "t", "d", 1, {done: (ok, why) => res.Push(ok)})
    Loop 30 {
        t += 400
        wh.Flush()
    }
    AssertEq(fake.made, Webhook.MaxRateLimited + 1, "bounded")
    AssertEq(res.Length, 1, "done once")
    AssertEq(res[1], 0, "reported as failed")
}

Test_Webhook_UrlNeverInLogText() {
    url := WhFakeUrl("A")
    ; exception message contains the URL, plus non-2xx, plus success paths
    wh := WhNewLive([WhStep(0, "request to " url " failed"), WhStep(404), WhStep(204)], &fake, &logs)
    wh.Send("biome", "t", "d", 1)
    wh.Send("errors", "t2", "d2", 1)
    Loop 10
        wh.Flush()
    AssertTrue(logs.Length > 0, "something was logged")
    for line in logs {
        AssertEq(InStr(line, "discord.com/api/webhooks"), 0, "log leaks url: " line)
        AssertEq(InStr(line, "SECRET"), 0, "log leaks token")
        AssertEq(InStr(line, "123456789"), 0, "log leaks id")
    }

    ; invalid url: rejected, logged without the url
    logs2 := []
    bad := "https://evil.example/api/webhooks/1/SECRETX"
    w2 := Webhook(WhStubCfg([WhMake("bad", bad, "", 1, ["biome"])]), (m) => logs2.Push(m))
    f2 := WhFakeHttp([])
    w2.httpFactory := f2.Make.Bind(f2)
    w2.Send("biome", "t", "d", 1)
    w2.Flush()
    AssertEq(f2.made, 0, "non-discord url never requested")
    AssertTrue(logs2.Length > 0, "rejection logged")
    for line in logs2 {
        AssertEq(InStr(line, "evil.example"), 0, "log leaks bad url")
        AssertEq(InStr(line, "SECRETX"), 0, "log leaks bad token")
    }
}

Test_Webhook_DryRunNoHttp() {
    logs := []
    wh := Webhook(WhStubCfg([WhMake("a", WhFakeUrl("a"), "", 1, ["biome"])]), (m) => logs.Push(m))
    wh.dryRun := true
    fake := WhFakeHttp([])
    wh.httpFactory := fake.Make.Bind(fake)
    wh.Send("biome", "t", "d", 1)
    wh.Flush()
    AssertEq(fake.made, 0, "dry run makes no request")
    AssertEq(wh.sent.Length, 1, "recorded")
    for line in logs
        AssertEq(InStr(line, "discord.com"), 0, "dry-run log leaks url")
}

Test_Webhook_ScreenshotAndThumbnailBothUploaded() {
    f := A_Temp "\vesper_whtest_s_" A_TickCount ".png"
    t := A_Temp "\vesper_whtest_WINDY_" A_TickCount ".png"
    WhWriteBytes(f, [0x89, 0x50, 0x4E, 0x47, 0x11, 0x22])
    WhWriteBytes(t, [0x89, 0x50, 0x4E, 0x47, 0x33, 0x44])
    try {
        wh := WhNewLive([WhStep(204)], &fake, &logs)
        wh.Send("biome", "t", "d", 1, {screenshot: f, thumbnail: t})
        wh.Flush()
        wh.Flush()
        AssertEq(fake.made, 1, "one request")
        body := WhBytes(fake.bodies[1])
        AssertTrue(WhFindStr(body, 'name="files[0]"; filename="' RegExReplace(f, "^.*\\") '"'), "screenshot is files[0]")
        AssertTrue(WhFindStr(body, 'name="files[1]"; filename="thumb_' RegExReplace(t, "^.*\\") '"'), "thumbnail is files[1]")
        AssertTrue(WhFind(body, [0x89, 0x50, 0x4E, 0x47, 0x11, 0x22]), "screenshot bytes")
        AssertTrue(WhFind(body, [0x89, 0x50, 0x4E, 0x47, 0x33, 0x44]), "thumbnail bytes")
        AssertTrue(WhFindStr(body, '"thumbnail":{"url":"attachment://thumb_'), "embed thumbnail refs its attachment")
        ; thumbnail only
        wh2 := WhNewLive([WhStep(204)], &fake2, &logs2)
        wh2.Send("biome", "t", "d", 1, {thumbnail: t})
        wh2.Flush()
        wh2.Flush()
        body2 := WhBytes(fake2.bodies[1])
        AssertTrue(WhFindStr(body2, 'name="files[0]"; filename="thumb_'), "thumbnail alone is files[0]")
        AssertEq(WhFindStr(body2, '"image"'), 0, "no big image")
    } finally {
        try FileDelete(f)
        try FileDelete(t)
    }
    ; a missing picture is simply left out
    wh3 := Webhook(WhStubCfg([WhMake("a", WhFakeUrl("a"), "", 1, ["biome"])]))
    wh3.dryRun := true
    wh3.Send("biome", "t", "d", 1, {thumbnail: A_Temp "\nope_" A_TickCount ".png"})
    wh3.Flush()
    AssertEq(wh3.sent[1].thumb, "", "missing thumbnail dropped")
    AssertEq(Json.Parse(wh3.sent[1].json)["embeds"][1].Has("thumbnail"), false, "no thumbnail ref")
}

Test_Webhook_ScreenshotUsesMultipart() {
    f := A_Temp "\vesper_whtest_" A_TickCount ".png"
    WhWriteBytes(f, [0x89, 0x50, 0x4E, 0x47, 0x00, 0xFF, 0x0D, 0x0A])
    try {
        wh := WhNewLive([WhStep(204), WhStep(204)], &fake, &logs)
        wh.Send("biome", "t", "d", 1, {screenshot: f})
        wh.Flush()
        wh.Flush()
        AssertEq(fake.made, 1, "one request")
        AssertEq(wh.Pending(), 0, "done")
        ct := fake.headers[1]["Content-Type"]
        AssertEq(SubStr(ct, 1, 30), "multipart/form-data; boundary=", "multipart content-type")
        boundary := SubStr(ct, 31)
        AssertTrue(StrLen(boundary) > 8, "boundary present")
        body := WhBytes(fake.bodies[1])
        AssertTrue(WhFindStr(body, "--" boundary "`r`n"), "body uses header boundary")
        AssertTrue(WhFindStr(body, 'name="payload_json"'), "payload_json part")
        AssertTrue(WhFindStr(body, 'name="files[0]"; filename="'), "files[0] part")
        AssertTrue(WhFindStr(body, "Content-Type: image/png"), "png part type")
        AssertTrue(WhFind(body, [0x89, 0x50, 0x4E, 0x47, 0x00, 0xFF, 0x0D, 0x0A]), "png bytes in body")
        AssertTrue(WhFindStr(body, "attachment://"), "embed references attachment")

        ; contrast: no screenshot -> plain JSON, no file part
        wh.Send("biome", "t", "d", 1)
        wh.Flush()
        wh.Flush()
        AssertEq(fake.made, 2, "second request")
        AssertEq(SubStr(fake.headers[2]["Content-Type"], 1, 16), "application/json", "json content-type")
        body2 := WhBytes(fake.bodies[2])
        AssertEq(WhFindStr(body2, "files[0]"), 0, "no file part without screenshot")
        AssertTrue(WhFindStr(body2, '"embeds"'), "json body")
    } finally {
        try FileDelete(f)
    }
    ; dry run records the screenshot path and the attachment reference
    wh2 := Webhook(WhStubCfg([WhMake("a", WhFakeUrl("a"), "", 1, ["biome"])]))
    wh2.dryRun := true
    FileOpen(f, "w").Write("x")
    try {
        wh2.Send("biome", "t", "d", 1, {screenshot: f})
        wh2.Flush()
        AssertEq(wh2.sent[1].screenshot, f, "screenshot path recorded")
        e := Json.Parse(wh2.sent[1].json)["embeds"][1]
        AssertEq(e["image"]["url"], "attachment://" RegExReplace(f, "^.*\\"), "embed image refs attachment")
    } finally {
        try FileDelete(f)
    }
    ; missing file is ignored
    wh2.sent := []
    wh2.Send("biome", "t", "d", 1, {screenshot: A_Temp "\nope_" A_TickCount ".png"})
    wh2.Flush()
    AssertEq(wh2.sent[1].screenshot, "", "missing screenshot dropped")
    AssertEq(Json.Parse(wh2.sent[1].json)["embeds"][1].Has("image"), false, "no image ref")
}

Test_Webhook_ScreenshotOversizeFallsBackToJson() {
    f := A_Temp "\vesper_whbig_" A_TickCount ".png"
    WhWriteBytes(f, [1, 2, 3, 4, 5, 6])
    try {
        wh := WhNewLive([WhStep(204)], &fake, &logs)
        wh.maxFileBytes := 3
        wh.Send("biome", "t", "d", 1, {screenshot: f})
        wh.Flush()
        wh.Flush()
        AssertEq(fake.made, 1, "still sends one request")
        AssertEq(SubStr(fake.headers[1]["Content-Type"], 1, 16), "application/json", "json fallback")
        body := WhBytes(fake.bodies[1])
        AssertEq(WhFindStr(body, "files[0]"), 0, "no file part")
        AssertEq(WhFindStr(body, "attachment://"), 0, "image ref removed")
        AssertEq(WhFindStr(body, '"image"'), 0, "no image key")
        AssertTrue(logs.Length > 0 && InStr(logs[1], "screenshot"), "fallback logged")
    } finally {
        try FileDelete(f)
    }
}

Test_Webhook_ScreenshotUnreadableFallsBackToJson() {
    f := A_Temp "\vesper_whgone_" A_TickCount ".png"
    WhWriteBytes(f, [1, 2, 3])
    wh := WhNewLive([WhStep(204)], &fake, &logs)
    wh.Send("biome", "t", "d", 1, {screenshot: f})   ; exists at Send time
    FileDelete(f)                                     ; gone by Flush time
    wh.Flush()
    wh.Flush()
    AssertEq(fake.made, 1, "still sends one request")
    AssertEq(SubStr(fake.headers[1]["Content-Type"], 1, 16), "application/json", "json fallback")
    body := WhBytes(fake.bodies[1])
    AssertEq(WhFindStr(body, "files[0]"), 0, "no file part")
    AssertEq(WhFindStr(body, "attachment://"), 0, "image ref removed")
    AssertTrue(logs.Length > 0 && InStr(logs[1], "screenshot"), "fallback logged")
}

Test_Webhook_InflightTimeoutAbortsAndRetriesOnce() {
    never := 1000000        ; WaitForResponse never completes
    wh := WhNewLive([WhStep(204, "", never), WhStep(204, "", never)], &fake, &logs)
    t := 5000
    wh.clock := () => t
    wh.Send("biome", "t", "d", 1)
    wh.Flush()                                  ; t=5000: send #1
    AssertEq(fake.made, 1, "sent")
    t := 5000 + 29000
    wh.Flush()                                  ; still within 30 s
    AssertEq(fake.reqs[1].aborted, false, "not aborted before 30 s")
    AssertEq(wh.Pending(), 1, "still in flight")
    AssertEq(fake.made, 1, "no retry yet")
    t := 5000 + 30001
    wh.Flush()                                  ; timeout -> Abort -> retry dispatched
    AssertEq(fake.reqs[1].aborted, true, "aborted after 30 s")
    AssertEq(fake.made, 2, "retried once")
    AssertEq(wh.Pending(), 1, "retry in flight")
    t := 5000 + 30001 + 30001
    wh.Flush()                                  ; retry times out -> give up
    AssertEq(fake.reqs[2].aborted, true, "retry aborted")
    AssertEq(fake.made, 2, "no third attempt")
    AssertEq(wh.Pending(), 0, "released")
    AssertTrue(InStr(logs[logs.Length], "giving up"), "give-up logged")
    for line in logs
        AssertEq(InStr(line, "discord.com"), 0, "timeout log leaks url")
}

Test_Webhook_MultipartBody() {
    bytes := Buffer(6)
    NumPut("UChar", 0x89, "UChar", 0x50, "UChar", 0x00, "UChar", 0xFF, "UChar", 0x0D, "UChar", 0x0A, bytes)
    b := "BOUNDARY123"
    body := Webhook.BuildMultipart('{"a":1}', "shot.png", bytes, b)
    ; locate parts by raw bytes
    txt := StrGet(body, body.Size, "CP0")   ; latin-1-ish view; NUL ends StrGet so use manual scan below
    head := ""
    Loop body.Size
        head .= (c := NumGet(body, A_Index - 1, "UChar")) = 0 ? "~" : Chr(c)
    AssertTrue(InStr(head, "--BOUNDARY123`r`n"), "opening boundary")
    AssertTrue(InStr(head, 'Content-Disposition: form-data; name="payload_json"'), "payload_json field")
    AssertTrue(InStr(head, "Content-Type: application/json"), "json content type")
    AssertTrue(InStr(head, '{"a":1}'), "json value")
    AssertTrue(InStr(head, 'Content-Disposition: form-data; name="files[0]"; filename="shot.png"'), "file field")
    AssertTrue(InStr(head, "Content-Type: image/png"), "png content type")
    AssertTrue(RegExMatch(head, "\r\n--BOUNDARY123--\r\n$"), "closing boundary at end")
    ; binary bytes survive intact between the file header and the closing boundary
    marker := "Content-Type: image/png`r`n`r`n"
    p := InStr(head, marker) + StrLen(marker)
    want := [0x89, 0x50, 0x00, 0xFF, 0x0D, 0x0A]
    for i, v in want
        AssertEq(NumGet(body, p - 1 + i - 1, "UChar"), v, "file byte " i)
    AssertEq(NumGet(body, p - 1 + 6, "UChar"), 0x0D, "CRLF after file")
    ; json with non-ASCII is UTF-8 encoded
    body2 := Webhook.BuildMultipart('{"t":"' Chr(0xE9) '"}', "x.png", bytes, b)
    found := false
    Loop body2.Size - 1
        if (NumGet(body2, A_Index - 1, "UChar") = 0xC3 && NumGet(body2, A_Index, "UChar") = 0xA9)
            found := true
    AssertTrue(found, "utf-8 json")
    AssertEq(Webhook.MultipartType(b), "multipart/form-data; boundary=BOUNDARY123", "content-type header")
}

Test_Webhook_FlushWithNothingIsSafe() {
    wh := Webhook(WhStubCfg([]))
    wh.Flush()
    wh.Send("biome", "t", "d", 1)
    wh.Flush()
    AssertEq(wh.Pending(), 0, "no recipients, nothing pending")
}

; ---- Screenshot ------------------------------------------------------------

Test_Screenshot_BadHwndReturnsEmpty() {
    AssertEq(Screenshot.Capture(0), "", "zero hwnd")
    AssertEq(Screenshot.Capture(0x7FFFFFF1), "", "nonexistent hwnd")
}
