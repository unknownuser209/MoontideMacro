#Requires AutoHotkey v2.0
; Tests for the GRAVEYARD boss's Discord message: Webhook.PostText /
; EditText (fake WinHttp from test_webhook.ahk, no network) and
; SinisterReport (lib\tasks\Sinister.ahk), and its wiring in MinionsTask
; (MnBoss from test_minions.ahk).
#Include ..\lib\tasks\Sinister.ahk

SnLink() => "https://www.roblox.com/share?code=abc123def&type=Server"

; body (SAFEARRAY) -> parsed JSON Map
SnJson(arr) {
    buf := WhBytes(arr)
    return Json.Parse(StrGet(buf, buf.Size, "UTF-8"))
}

; a Webhook with a fake http; hooks: "Boss" (sinister, mention 555) and
; "Other" (rare only). plan as WhFakeHttp's.
SnWh(plan, logs := "", url := "") {
    hooks := [WhMake("Boss", url = "" ? WhFakeUrl("b") : url, "555", 1, ["sinister", "rare"])
        , WhMake("Other", WhFakeUrl("o"), "666", 1, ["rare"])]
    wh := Webhook(WhStubCfg(hooks), IsObject(logs) ? (t) => logs.Push(t) : "")
    fake := WhFakeHttp(plan)
    wh.httpFactory := () => fake.Make()
    wh.retryDelayMs := 0
    return {wh: wh, fake: fake}
}

; fake webhook for SinisterReport: posts / edits recorded
class SnFakeWh {
    __New() {
        this.posts := [], this.edits := []
    }
    PostText(ev, content, opts := "") {
        this.posts.Push({event: ev, content: content, opts: opts})
        h := WebhookText(ev)
        h.parts.Push({name: "Boss", url: "", id: "42", state: "ok", edit: "", edited: ""})
        return h
    }
    EditText(h, content) {
        this.edits.Push({handle: h, content: content})
        return 1
    }
}

; -> {rep, wh, logs, t: {now}}; ghost: the ghost dep ("" = none)
SnRep(link := "", ghost := "no") {
    wh := SnFakeWh(), logs := [], clock := {now: 1000}
    deps := {webhook: wh, cfg: QmCfg(Map("General.privateServer", link = "" ? SnLink() : link)), log: (t) => logs.Push(t)
        , now: () => clock.now}
    if (ghost = "no")
        deps.ghost := () => false
    else if IsObject(ghost)
        deps.ghost := ghost
    return {rep: SinisterReport(deps), wh: wh, logs: logs, t: clock}
}

; ---- Webhook ---------------------------------------------------------------

Test_Sinister_PostTextIsPlainAndNeverPings() {
    w := SnWh([{status: 200, sendError: "", pending: 0, body: '{"author":{"id":"9"},"id":"111222333","content":"x"}'}])
    h := w.wh.PostText("sinister", SnLink() " sinister s natrual spawn")
    AssertEq(h.parts.Length, 1, "only the hook with the sinister event")
    w.wh.Flush(), w.wh.Flush()
    AssertEq(w.fake.opened.Length, 1, "one request")
    AssertEq(w.fake.opened[1]["method"], "POST", "POST")
    AssertEq(w.fake.opened[1]["url"], WhFakeUrl("b") "?wait=true", "?wait=true: Discord returns the message")
    j := SnJson(w.fake.bodies[1])
    AssertEq(j["content"], SnLink() " sinister s natrual spawn", "the exact text")
    AssertEq(j.Has("embeds"), false, "no embed")
    AssertEq(Json.Stringify(j["allowed_mentions"], 0), '{"parse":[]}', "allowed_mentions parse []")
    AssertEq(InStr(j["content"], "<@") || InStr(j["content"], "@everyone"), 0, "no mention, even with one set on the hook")
    AssertEq(h.Ids()["Boss"], "111222333", "the message id kept per webhook entry (top-level id)")
    AssertEq(w.wh.PostText("craft", "x"), "", "no webhook routed -> no handle")
}

Test_Sinister_EditUsesTheStoredIdWithPatch() {
    w := SnWh([{status: 200, sendError: "", pending: 0, body: '{"id":"777"}'}, {status: 200, sendError: "", pending: 0}])
    h := w.wh.PostText("sinister", "a")
    w.wh.Flush(), w.wh.Flush()
    AssertEq(w.wh.EditText(h, SnLink() " dead"), 1, "one part edited")
    w.wh.Flush(), w.wh.Flush()
    AssertEq(w.fake.opened.Length, 2, "post + edit")
    AssertEq(w.fake.opened[2]["method"], "PATCH", "PATCH")
    AssertEq(w.fake.opened[2]["url"], WhFakeUrl("b") "/messages/777", "{webhook}/messages/{id}, no wait")
    j := SnJson(w.fake.bodies[2])
    AssertEq(j["content"], SnLink() " dead", "the new text")
    AssertEq(Json.Stringify(j["allowed_mentions"], 0), '{"parse":[]}', "same allowed_mentions")
    AssertEq(h.parts[1].edited, 1, "edit done")
    ; an edit asked while the post is on its way: sent once the id comes
    w := SnWh([{status: 200, sendError: "", pending: 2, body: '{"id":"888"}'}])
    h := w.wh.PostText("sinister", "a")
    w.wh.Flush()
    AssertEq(w.wh.EditText(h, "b"), 1, "waits for the id")
    w.wh.Flush()
    AssertEq(w.fake.opened.Length, 1, "no PATCH before the id")
    Loop 4
        w.wh.Flush()
    AssertEq(w.fake.opened.Length, 2, "PATCH after the post's answer")
    AssertEq(w.fake.opened[2]["url"], WhFakeUrl("b") "/messages/888", "with that id")
    ; a thread webhook keeps its thread_id on both
    w := SnWh([{status: 200, sendError: "", pending: 0, body: '{"id":"5"}'}], , WhFakeUrl("t") "?thread_id=99")
    h := w.wh.PostText("sinister", "a")
    w.wh.Flush(), w.wh.Flush(), w.wh.EditText(h, "b"), w.wh.Flush(), w.wh.Flush()
    AssertEq(w.fake.opened[1]["url"], WhFakeUrl("t") "?thread_id=99&wait=true", "post in the thread")
    AssertEq(w.fake.opened[2]["url"], WhFakeUrl("t") "/messages/5?thread_id=99", "edit in the thread")
}

Test_Sinister_FailedOrRateLimitedPost() {
    w := SnWh([{status: 500, sendError: "", pending: 0}, {status: 500, sendError: "", pending: 0}])
    h := w.wh.PostText("sinister", "a")
    Loop 4
        w.wh.Flush()
    AssertEq(h.parts[1].state, "failed", "failed after the retry")
    AssertEq(w.wh.EditText(h, "b"), 0, "nothing to edit")
    Loop 3
        w.wh.Flush()
    AssertEq(w.fake.opened.Length, 2, "no PATCH")
    ; 429: held and sent again (no attempt spent), then the id kept
    w := SnWh([{status: 429, sendError: "", pending: 0, body: '{"retry_after": 0.3}'}, {status: 200, sendError: "", pending: 0, body: '{"id":"31"}'}])
    clock := {t: 0}
    w.wh.clock := () => clock.t
    h := w.wh.PostText("sinister", "a")
    w.wh.Flush(), w.wh.Flush()
    clock.t += 400
    w.wh.Flush(), w.wh.Flush()
    AssertEq(h.Ids().Get("Boss", ""), "31", "rate limited, then posted")
    AssertEq(w.fake.opened[2]["url"], WhFakeUrl("b") "?wait=true", "the resend waits too")
    ; dry run: a made-up id, the edit recorded as PATCH
    w := SnWh([])
    w.wh.dryRun := true
    h := w.wh.PostText("sinister", "a"), w.wh.Flush(), w.wh.EditText(h, "b"), w.wh.Flush()
    AssertEq(w.wh.sent.Length "/" w.wh.sent[2].method "/" (w.wh.sent[2].msgId != ""), "2/PATCH/1", "dry run")
}

; ---- SinisterReport ----------------------------------------------------------

Test_Sinister_SpawnMessageText() {
    r := SnRep()
    AssertEq(r.rep.Spawn("GRAVEYARD@1"), true, "posted")
    AssertEq(r.wh.posts.Length, 1, "one post")
    AssertEq(r.wh.posts[1].event, "sinister", "the sinister event")
    AssertEq(r.wh.posts[1].content, SnLink() " sinister s natrual spawn", "the user's text")
}

Test_Sinister_NoSendInAGhostServerOrWithoutALink() {
    r := SnRep(, () => true)
    r.rep.Spawn("k")
    AssertEq(r.wh.posts.Length, 0, "ghost server: no send")
    r := SnRep(, "")
    r.rep.Spawn("k")
    AssertEq(r.wh.posts.Length, 0, "ghost not known: no send")
    r := SnRep(, () => (1 / 0))
    r.rep.Spawn("k")
    AssertEq(r.wh.posts.Length, 0, "ghost dep failing: no send")
    for link in ["   ", "not a link", "https://evil.example/x", "https://www.roblox.com/share?code=a b"] {
        wh := SnFakeWh()
        rep := SinisterReport({webhook: wh, cfg: QmCfg(Map("General.privateServer", link)), ghost: () => false})
        rep.Spawn("k")
        AssertEq(wh.posts.Length, 0, "unusable link: no send (" A_Index ")")
    }
    ; ghost later: still nothing for this spawn, and no edit
    r := SnRep(, () => true)
    r.rep.Spawn("k"), r.rep.Killed("toast")
    AssertEq(r.wh.edits.Length, 0, "nothing posted: nothing edited")
}

Test_Sinister_OneMessagePerSpawn() {
    r := SnRep()
    r.rep.Spawn("GRAVEYARD@1"), r.rep.Note(0.9, true), r.rep.Spawn("GRAVEYARD@1")
    AssertEq(r.wh.posts.Length, 1, "fought again in the same spawn: no second post")
    r.rep.Gone(), r.rep.Spawn("GRAVEYARD@1")
    AssertEq(r.wh.posts.Length, 1, "same key after the biome: still one")
    r.rep.Spawn("GRAVEYARD@2")
    AssertEq(r.wh.posts.Length, 2, "a new GRAVEYARD: a new message")
}

Test_Sinister_KilledByLowPlateThenGone() {
    r := SnRep()
    r.rep.Spawn("k")
    for fill in [1.0, 0.5, 0.06, 0.03] {
        r.t.now += 1000
        r.rep.Note(fill, true)
    }
    r.t.now += 1000
    r.rep.Note("", false)                           ; the plate gone
    t0 := r.t.now
    while (r.t.now - t0 < SinisterReport.GoneMs - 300) {
        r.t.now += 300
        r.rep.Note("", false)
    }
    AssertEq(r.wh.edits.Length, 0, "not before GoneMs")
    r.t.now += 600
    r.rep.Note("", false)
    AssertEq(r.wh.edits.Length, 1, "edited")
    AssertEq(r.wh.edits[1].content, SnLink() " dead", "<link> dead")
    AssertTrue(r.wh.edits[1].handle == r.rep.msg, "the same message")
    r.rep.Killed("toast"), r.rep.Note("", false)
    AssertEq(r.wh.edits.Length, 1, "edited once")
    ; the award toast alone
    r := SnRep()
    r.rep.Spawn("k"), r.rep.Killed("an award toast")
    AssertEq(r.wh.edits.Length "/" r.rep.dead, "1/1", "toast -> edit")
}

Test_Sinister_DespawnIsNotDead() {
    ; the plate gone at a high fill
    r := SnRep()
    r.rep.Spawn("k")
    r.rep.Note(0.9, true), r.rep.Note(0.85, true)
    Loop 200
        r.t.now += 1000, r.rep.Note("", false)
    AssertEq(r.wh.edits.Length, 0, "gone at a high fill: no edit")
    ; one low read is no proof (a misread)
    r := SnRep()
    r.rep.Spawn("k"), r.rep.Note(0.9, true), r.rep.Note(0.04, true)
    Loop 60
        r.t.now += 1000, r.rep.Note("", false)
    AssertEq(r.wh.edits.Length, 0, "a single low read: no edit")
    ; low, but the biome changed before GoneMs: its timer ended
    r := SnRep()
    r.rep.Spawn("k"), r.rep.Note(0.05, true), r.rep.Note(0.04, true)
    r.t.now += 5000, r.rep.Note("", false)
    r.rep.Gone()
    Loop 60
        r.t.now += 1000, r.rep.Note("", false)
    r.rep.Killed("toast")
    AssertEq(r.wh.edits.Length, 0, "the biome ended first: no edit")
    ; low, then the player died: the plate out of sight means nothing
    r := SnRep()
    r.rep.Spawn("k"), r.rep.Note(0.05, true), r.rep.Note(0.04, true), r.rep.Died()
    Loop 60
        r.t.now += 1000, r.rep.Note("", false)
    AssertEq(r.wh.edits.Length, 0, "a death: no edit")
    ; low long before the plate went (seen again at no fill read)
    r := SnRep()
    r.rep.Spawn("k"), r.rep.Note(0.05, true), r.rep.Note(0.04, true)
    r.t.now += SinisterReport.LowKeepMs + 1000, r.rep.Note("", true)
    Loop 60
        r.t.now += 1000, r.rep.Note("", false)
    AssertEq(r.wh.edits.Length, 0, "the low reads too old: no edit")
}

; the whole path through a real Webhook: no webhook URL and no link in any log
Test_Sinister_UrlAndLinkNeverLogged() {
    logs := []
    w := SnWh([{status: 500, sendError: "boom " WhFakeUrl("b"), pending: 0}, {status: 200, sendError: "", pending: 0, body: '{"id":"1"}'}
        , {status: 404, sendError: "", pending: 0}, {status: 404, sendError: "", pending: 0}], logs)
    rep := SinisterReport({webhook: w.wh, cfg: QmCfg(Map("General.privateServer", SnLink())), ghost: () => false
        , log: (t) => logs.Push(t), now: () => 0})
    rep.Spawn("k")
    Loop 4
        w.wh.Flush()
    rep.Killed("toast")
    Loop 4
        w.wh.Flush()
    AssertEq(w.fake.opened.Length, 4, "post (retried), edit (retried)")
    AssertTrue(logs.Length >= 4, "lines were logged")
    for l in logs {
        AssertEq(InStr(l, "discord.com") || InStr(l, "SECRET") || InStr(l, "roblox.com") || InStr(l, "abc123def"), 0, "clean: " l)
    }
}

; ---- MinionsTask -------------------------------------------------------------

; MnBoss with a SinisterReport on a fake webhook (not a ghost server)
SnBoss() {
    m := MnBoss()
    m.s.logName := "Eden"
    m.sw := SnFakeWh()
    m.t._sin := SinisterReport({webhook: m.sw, cfg: QmCfg(Map("General.privateServer", SnLink())), ghost: () => false
        , log: (t) => m.logs.Push(t), now: () => m.io.t})
    return m
}

Test_Sinister_MinionsBossKilledEditsTheMessage() {
    m := SnBoss()
    full := [{x: 1280, y: 680, w: 200, full: 200, fill: 1.0}], low := [{x: 1280, y: 680, w: 10, full: 200, fill: 0.04}]
    m.t._scanFn := () => (MnSkills(m.io) < 4) ? full : (MnSkills(m.io) < 10) ? low : []
    m.t.Run(SchedCtx())
    AssertEq(m.sw.posts.Length, 1, "one message at boss in sight")
    AssertEq(m.sw.posts[1].content, SnLink() " sinister s natrual spawn", "its text")
    AssertEq(m.sw.edits.Length, 1, "the plate went low, then gone: edited")
    AssertEq(m.sw.edits[1].content, SnLink() " dead", "dead")
    AssertTrue(MnLogged(m, "sinister: boss down (its plate went"), "by the plate rule")
    ; the same GRAVEYARD fought again (a stop let it in): no second message
    m.t._hunted := ""
    n0 := MnSkills(m.io)
    m.t._scanFn := () => (MnSkills(m.io) < n0 + 4) ? full : []
    m.t.Run(SchedCtx())
    AssertTrue(MnLogged(m, "boss in sight"), "seen again")
    AssertEq(m.sw.posts.Length, 1, "still one message")
    ; a new GRAVEYARD: a new message
    m.state.biome := "NORMAL", m.t.CanRun(m.state), m.state.biome := "GRAVEYARD", m.t.CanRun(m.state)
    n1 := MnSkills(m.io)
    m.t._scanFn := () => (MnSkills(m.io) < n1 + 4) ? full : []
    m.t.Run(SchedCtx())
    AssertEq(m.sw.posts.Length, 2, "new spawn, new message")
    AssertEq(m.sw.edits.Length, 1, "gone at full: no edit")
}

Test_Sinister_MinionsDespawnLeavesTheMessage() {
    m := SnBoss()
    full := [{x: 1280, y: 680, w: 200, full: 200, fill: 0.9}]
    m.t._scanFn := () => (MnSkills(m.io) < 6) ? full : []
    m.t.Run(SchedCtx())
    AssertEq(m.sw.posts.Length "/" m.sw.edits.Length, "1/0", "gone at a high fill: posted, not edited")
    ; low, then the biome changes: no edit
    m := SnBoss()
    low := [{x: 1280, y: 680, w: 10, full: 200, fill: 0.04}]
    m.t._scanFn := () => (MnSkills(m.io) < 6) ? low : []
    m.t._biomeFn := () => (MnSkills(m.io) >= 6) ? "NORMAL" : "GRAVEYARD"
    m.t.Run(SchedCtx())
    AssertTrue(MnLogged(m, "the biome changed (GRAVEYARD -> NORMAL)"), "the biome ended")
    AssertEq(m.sw.posts.Length "/" m.sw.edits.Length, "1/0", "despawn with the biome: no edit")
    ; no ghost dep (the default from deps): never posts
    m := MnBoss(, Map("General.privateServer", SnLink()))
    m.s.logName := "Eden"
    m.t._scanFn := () => (MnSkills(m.io) < 4) ? [{x: 1280, y: 680, w: 200}] : []
    AssertTrue(m.t._sin is SinisterReport, "built from the deps")
    m.t.Run(SchedCtx())
    AssertEq(m.t._sin.msg, "", "no ghost dep: nothing posted")
}
