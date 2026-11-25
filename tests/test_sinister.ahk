#Requires AutoHotkey v2.0
; Tests for the GRAVEYARD boss's Discord message: Webhook.PostText /
; EditText (fake WinHttp from test_webhook.ahk, no network) and
; SinisterReport (lib\tasks\Sinister.ahk), and its wiring in MinionsTask
; (MnBoss from test_minions.ahk).
#Include ..\lib\tasks\Sinister.ahk

SnLink() => "https://www.roblox.com/share?code=abc123def&type=Server"

; a SinisterReport card (object {desc, color, buttons}) holds text
SnHas(card, text) => IsObject(card) && InStr(card.desc, text)

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
    AssertTrue(SnHas(r.wh.posts[1].content, "## Sinister S. has spawned") && SnHas(r.wh.posts[1].content, "[Join Server](" SnLink() ")"), "the user's text")
}

; audit 2026-11-20: with Join link on (the default) and no private link, or
; in a public / ghost server, NO boss card was sent while the biome cards
; were. Now the card goes without the link and its button, as theirs do.
SnNoLink(wh, what) {
    AssertEq(wh.posts.Length, 1, what ": the card is sent")
    c := wh.posts[1].content
    AssertTrue(SnHas(c, "Sinister S. has spawned"), what ": the boss named")
    AssertTrue(!InStr(c.desc, "roblox.com") && !InStr(c.desc, "Join Server") && !IsObject(c.buttons), what ": no link, no button")
}

Test_Sinister_NoLinkInAGhostServerOrWithoutALink() {
    r := SnRep(, () => true)
    r.rep.Spawn("k")
    SnNoLink(r.wh, "ghost server")
    AssertTrue(SnLogged(r.logs, "without the Join Server link"), "logged why")
    r := SnRep(, "")
    r.rep.Spawn("k")
    SnNoLink(r.wh, "ghost not known")
    r := SnRep(, () => (1 / 0))
    r.rep.Spawn("k")
    SnNoLink(r.wh, "ghost dep failing")
    for link in ["   ", "not a link", "https://evil.example/x", "https://www.roblox.com/share?code=a b"] {
        wh := SnFakeWh(), logs := []
        rep := SinisterReport({webhook: wh, cfg: QmCfg(Map("General.privateServer", link)), ghost: () => false, log: (t) => logs.Push(t)})
        rep.Spawn("k")
        SnNoLink(wh, "unusable link " A_Index)
        AssertTrue(SnLogged(logs, "no usable private server link"), "logged why " A_Index)
    }
    ; a link pasted without https:// is made clickable (as the biome cards)
    wh := SnFakeWh()
    rep := SinisterReport({webhook: wh, cfg: QmCfg(Map("General.privateServer", "roblox.com/share?code=abc&type=Server")), ghost: () => false})
    rep.Spawn("k")
    AssertTrue(InStr(wh.posts[1].content.desc, "[Join Server](https://www.roblox.com/share?code=abc&type=Server)"), "the link fixed up")
    ; posted without the link: the kill edit has none either
    r := SnRep(, () => true)
    r.rep.Spawn("k"), r.rep.Killed("toast")
    AssertEq(r.wh.edits.Length, 1, "edited to dead")
    AssertTrue(!IsObject(r.wh.edits[1].content.buttons) && !InStr(r.wh.edits[1].content.desc, "roblox.com"), "the dead card has no link")
}

SnLogged(logs, s) {
    for l in logs
        if InStr(l, s)
            return true
    return false
}

; General.joinButton off: the boss card goes out without the private server
; link or its button (as the biome cards); in a ghost server too
Test_Sinister_JoinButtonOffSendsNoLink() {
    wh := SnFakeWh()
    rep := SinisterReport({webhook: wh, cfg: QmCfg(Map("General.privateServer", SnLink(), "General.joinButton", 0)), ghost: () => false})
    AssertTrue(rep.Spawn("k"), "posted")
    c := wh.posts[1].content
    AssertTrue(SnHas(c, "Sinister S. has spawned"), "the boss named")
    AssertTrue(!InStr(c.desc, "roblox.com") && !InStr(c.desc, "Join Server"), "no link in the card")
    AssertTrue(!IsObject(c.buttons), "no Join Server button")
    rep.Killed("toast")
    d := wh.edits[1].content
    AssertTrue(!IsObject(d.buttons) && !InStr(d.desc, "roblox.com"), "the dead card has no link either")
    wh2 := SnFakeWh()
    rep2 := SinisterReport({webhook: wh2, cfg: QmCfg(Map("General.privateServer", SnLink(), "General.joinButton", 0)), ghost: () => true})
    rep2.Spawn("k")
    SnNoLink(wh2, "ghost server")
}

Test_Sinister_OneMessagePerSpawn() {
    r := SnRep()
    r.rep.Spawn("GRAVEYARD@1"), r.rep.Note(0.9, true), r.rep.Spawn("GRAVEYARD@1")
    AssertEq(r.wh.posts.Length, 1, "fought again in the same spawn: no second post")
    r.rep.Gone(), r.rep.Spawn("GRAVEYARD@1")
    AssertEq(r.wh.posts.Length, 1, "same key after the biome: still one")
    r.t.now += SinisterReport.SpawnGapMs
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
    AssertTrue(SnHas(r.wh.edits[1].content, "Sinister S. is dead"), "<link> dead")
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
    AssertTrue(SnHas(m.sw.posts[1].content, "## Sinister S. has spawned") && SnHas(m.sw.posts[1].content, "[Join Server](" SnLink() ")"), "its text")
    AssertEq(m.sw.edits.Length, 1, "the plate went low, then gone: edited")
    AssertTrue(SnHas(m.sw.edits[1].content, "Sinister S. is dead"), "dead")
    AssertTrue(MnLogged(m, "sinister: boss down (its plate went"), "by the plate rule")
    ; the same GRAVEYARD fought again (a stop let it in): no second message
    m.t._hunted := ""
    n0 := MnSkills(m.io)
    m.t._scanFn := () => (MnSkills(m.io) < n0 + 4) ? full : []
    m.t.Run(SchedCtx())
    AssertTrue(MnLogged(m, "boss in sight"), "seen again")
    AssertEq(m.sw.posts.Length, 1, "still one message")
    ; a new GRAVEYARD (a later night): a new message
    m.io.t += SinisterReport.SpawnGapMs
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
    ; no ghost dep (the default from deps): never the link
    m := MnBoss(, Map("General.privateServer", SnLink()))
    m.s.logName := "Eden"
    m.t._scanFn := () => (MnSkills(m.io) < 4) ? [{x: 1280, y: 680, w: 200}] : []
    AssertTrue(m.t._sin is SinisterReport, "built from the deps")
    m.t.Run(SchedCtx())
    AssertEq(m.t._sin._link, "", "no ghost dep: no link")
}


; ---- the bosses from the chat (2026-11-15: Sinister S. spawned with hunting
; off and nothing was sent) ---------------------------------------------------

Test_Sinister_LetterPicksTheBoss() {
    AssertEq(SinisterReport.BossName("s"), "Sinister S.", "S")
    AssertEq(SinisterReport.BossName("P"), "Sinister P.", "P")
    AssertEq(SinisterReport.BossName("x"), "Sinister S.", "anything else: S")
    r := SnRep()
    r.rep.Spawn("chat:p:1", "p")
    AssertTrue(SnHas(r.wh.posts[1].content, "## Sinister P. has spawned") && SnHas(r.wh.posts[1].content, "[Join Server](" SnLink() ")"), "P's message")
}

; the chat line and the fight see one spawn: one message, the fight's edit
; still goes to it
Test_Sinister_OneMessageWhenChatAndFightSeeIt() {
    r := SnRep()
    AssertEq(r.rep.Spawn("chat:s:1000", "s"), true, "chat first: posted")
    r.t.now += 60000
    AssertEq(r.rep.Spawn("GRAVEYARD@5"), false, "the fight a minute later: no second post")
    AssertEq(r.wh.posts.Length, 1, "one message")
    r.rep.Killed("toast")
    AssertEq(r.wh.edits.Length, 1, "the fight's kill edits the chat's message")
    r.t.now += SinisterReport.SpawnGapMs
    r.rep.Spawn("chat:s:999999", "s")
    AssertEq(r.wh.posts.Length, 2, "15 min later: a new spawn, a new message")
}

Test_ChatWatch_DetectsTheBosses() {
    AssertEq(ChatWatch.DetectBoss("[Graveyard]: Sinister S. has spawned!").Length, 1, "S")
    AssertEq(ChatWatch.DetectBoss("[Graveyard]: Sinister S. has spawned!")[1], "s", "S letter")
    AssertEq(ChatWatch.DetectBoss("Sinlster P has appeared")[1], "p", "game font i as l, P")
    AssertEq(ChatWatch.DetectBoss("S1nister 5.")[1], "s", "5 read for S")
    both := ChatWatch.DetectBoss("Sinister S. spawned`nSinister P. spawned`nSinister S. again")
    AssertEq(both.Length, 2, "each boss once")
    AssertEq(ChatWatch.DetectBoss("Player found Sinister, chance of 1 in 15,000,000").Length, 0, "the aura in a roll line")
    AssertEq(ChatWatch.DetectBoss("Sinister Pumpkin").Length, 0, "a longer word after it")
    AssertEq(ChatWatch.DetectBoss("Nameless ghosts pass by you...").Length, 0, "biome line")
}

Test_ChatWatch_BossOncePerSpawnAndNotAtStart() {
    clock := QmClock(1000)
    text := "Sinister S. has spawned"
    bosses := []
    mk := (old) => ChatWatch({io: QmIO(), cal: QmCal(, Map("chat_rect", {x: 10, y: 20, w: 400, h: 200}))
        , ocr: (*) => text, now: () => clock.Now(), onBoss: (b) => bosses.Push(b), startOld: old})
    cw := mk(false)
    cw.Check()
    AssertEq(bosses.Length, 1, "reported")
    clock.t += 60000
    cw.Check()
    AssertEq(bosses.Length, 1, "still in the chat a minute later: once")
    clock.t += ChatWatch.BossGapSec * 1000
    cw.Check()
    AssertEq(bosses.Length, 1, "the same line 15 min later: still once")
    text := "Sinister S. has spawned`nhi`nSinister S. has spawned"
    clock.t += 5000
    cw.Check()
    AssertEq(bosses.Length, 2, "a second line: a new spawn")
    ; at the start the line already there is old
    bosses := []
    cw2 := mk(true)
    cw2.Check()
    AssertEq(bosses.Length, 0, "line there at the start: not announced")
    text := "Sinister P. has spawned"
    clock.t += 5000
    cw2.Check()
    AssertEq(bosses.Length, 1, "a new boss line after the start: announced")
    AssertEq(bosses[1], "p", "P")
}

; Live: the line of a spawn stays in a quiet chat, and 15 min after it was
; read it was announced again, the boss long dead and its biome over:
; 2026-11-23 00:33:39 Sinister S. in HELL (spawn 00:18, dead 00:28),
; 11-24 07:57:39 Sinister P. in SNOWY (07:42), 10:37:21 P in RAINY (10:22,
; dead 10:28). A new spawn is a new line: one more boss line than the
; chat has shown, and the old one counts until it has been gone 15 min.
Test_ChatWatch_OldBossLineIsNotASecondSpawn() {
    clock := QmClock(0)
    line := "[Graveyard]: Sinister S. has spawned!"
    text := line
    bosses := []
    cw := ChatWatch({io: QmIO(), cal: QmCal(, Map("chat_rect", {x: 10, y: 20, w: 400, h: 200}))
        , ocr: (*) => text, now: () => clock.Now(), onBoss: (b) => bosses.Push(b), startOld: true})
    text := "Mari has arrived"
    cw.Check()                                         ; the start: no boss line yet
    text := line
    clock.t := 5000
    cw.Check()
    AssertEq(bosses.Length, 1, "the spawn")
    ; the line stays; OCR misses it now and then (reads 5 s apart)
    t := 5000
    Loop 400 {
        t += 5000, clock.t := t
        text := (Mod(A_Index, 60) < 3) ? "Mari has arrived" : line
        cw.Check()
    }
    AssertEq(bosses.Length, 1, "the same line for 33 min, missed a few reads: no second message")
    ; a new spawn while the old line is still there
    text := line "`n" line
    clock.t := t + 5000
    cw.Check()
    AssertEq(bosses.Length, 2, "a second line: the next spawn")
    ; both scroll away, gone 15 min; a new one later is a spawn again
    text := "Mari has arrived"
    t := clock.t
    Loop 190 {
        t += 5000, clock.t := t
        cw.Check()
    }
    text := line
    clock.t := t + 5000
    cw.Check()
    AssertEq(bosses.Length, 3, "after the old lines left: a new line is a spawn")
}

; review: S then P are two bosses (two messages); "Sinister 5000" is no boss
Test_Sinister_EachBossGetsItsOwnMessage() {
    r := SnRep()
    r.rep.Spawn("chat:s:1", "s")
    r.t.now += 300000
    r.rep.Spawn("chat:p:2", "p")
    AssertEq(r.wh.posts.Length, 2, "P five minutes after S: its own message")
    AssertTrue(SnHas(r.wh.posts[2].content, "## Sinister P. has spawned") && SnHas(r.wh.posts[2].content, "[Join Server](" SnLink() ")"), "P's text")
    r.t.now += 60000
    r.rep.Spawn("chat:p:3", "p")
    AssertEq(r.wh.posts.Length, 2, "P again inside 15 min: no second P message")
    AssertEq(ChatWatch.DetectBoss("Sinister 5000 rolls").Length, 0, "a number is not S")
    AssertEq(ChatWatch.DetectBoss("Sinister 5, nice").Length, 0, "5 and a comma is not S")
}


; 2026-11-16, the user: the boss message looks like the "Biome Started" card
Test_Sinister_CardLooksLikeTheBiomeCard() {
    c := SinisterReport.SpawnCard(SnLink(), "p", 1700000000)
    AssertEq(c.desc, "<t:1700000000:F> (<t:1700000000:R>)`n> ## Sinister P. has spawned`n> **[Join Server](" SnLink() ")**", "the biome card's layout")
    AssertEq(c.buttons[1].url, SnLink(), "Join Server button")
    d := SinisterReport.DeadCard(SnLink(), "s", 1700000060)
    AssertEq(d.desc, "<t:1700000060:F> (<t:1700000060:R>)`n> ## Sinister S. is dead", "dead card")
    ; sent as an embed with no title and no ping, edited as an embed
    w := SnWh([{status: 200, sendError: "", pending: 0, body: '{"id":"9"}'}, {status: 200, sendError: "", pending: 0}])
    h := w.wh.PostText("sinister", c)
    w.wh.Flush(), w.wh.Flush()
    j := SnJson(w.fake.bodies[1])
    AssertEq(j["embeds"][1]["description"], c.desc, "embed text")
    AssertEq(j["embeds"][1].Has("title"), false, "no title, like the biome cards")
    AssertEq(j["embeds"][1]["color"], 0xE8731C, "P's colour")
    AssertEq(j["components"][1]["components"][1]["url"], SnLink(), "the button")
    AssertEq(Json.Stringify(j["allowed_mentions"], 0), '{"parse":[]}', "never a ping")
    AssertEq(j.Has("content"), false, "no plain text")
    w.wh.EditText(h, d), w.wh.Flush(), w.wh.Flush()
    AssertEq(w.fake.opened[2]["method"], "PATCH", "edited")
    AssertEq(SnJson(w.fake.bodies[2])["embeds"][1]["description"], d.desc, "the dead card")
}

; 2026-11-16, the user: "its still not @ing me". The boss card pings the
; webhook's Mention when asked (opts.mention); the dead edit does not ping again
Test_Sinister_CardPingsTheMention() {
    logs := []
    w := SnWh([{status: 200, sendError: "", pending: 0, body: '{"id":"9"}'}, {status: 200, sendError: "", pending: 0}], logs)
    h := w.wh.PostText("sinister", SinisterReport.SpawnCard(SnLink(), "p", 1700000000), {mention: true})
    w.wh.Flush(), w.wh.Flush()
    AssertTrue(InStr(logs.Length ? logs[logs.Length] : "", 'Webhook "Boss": sinister message posted'), "the post is logged")
    j := SnJson(w.fake.bodies[1])
    AssertEq(j["content"], "<@555>", "the Boss hook's mention")
    AssertEq(Json.Stringify(j["allowed_mentions"], 0), '{"users":["555"]}', "only that user can be pinged")
    AssertTrue(InStr(j["embeds"][1]["description"], "has spawned"), "the card is still there")
    w.wh.EditText(h, SinisterReport.DeadCard(SnLink(), "p", 1700000060)), w.wh.Flush(), w.wh.Flush()
    AssertEq(SnJson(w.fake.bodies[2]).Has("content"), false, "the edit keeps the text: no second ping")
    ; plain text with a mention
    w2 := SnWh([{status: 200, sendError: "", pending: 0, body: '{"id":"9"}'}])
    w2.wh.PostText("sinister", "hi", {mention: true}), w2.wh.Flush(), w2.wh.Flush()
    AssertEq(SnJson(w2.fake.bodies[1])["content"], "<@555> hi", "text after the mention")
    ; the report asks for the ping, real or picked from Dev tools
    r := SnRep()
    r.rep.Spawn("chat:p:1", "p")
    AssertEq(r.wh.posts[1].opts.mention, true, "a real spawn pings")
    wh := SnFakeWh()
    rep := SinisterReport({webhook: wh, cfg: QmCfg(Map("General.privateServer", SnLink())), ghost: () => false, test: true, log: (t) => 0
        , hook: Map("name", "Dev", "url", "https://discord.com/api/webhooks/1/x", "mention", "555")})
    rep.Spawn("TEST-1", "p")
    AssertEq(wh.posts[1].opts.mention, true, "the Dev tools fake pings too")
}

; Dev tools: a fake spawn goes to the one webhook picked, marked as a test,
; and can be edited to dead like a real one
Test_Sinister_TestCardIsMarked() {
    wh := SnFakeWh(), logs := []
    hook := Map("name", "Dev", "url", "https://discord.com/api/webhooks/1/x")
    rep := SinisterReport({webhook: wh, cfg: QmCfg(Map("General.privateServer", SnLink())), log: (t) => logs.Push(t)
        , ghost: () => false, hook: hook, test: true})
    AssertEq(rep.Spawn("TEST-1", "p"), true, "posted")
    AssertTrue(wh.posts[1].opts.hook == hook, "only to the picked webhook")
    AssertTrue(SnHas(wh.posts[1].content, "[TEST]") && SnHas(wh.posts[1].content, "Sinister P. has spawned"), "marked as a test")
    rep.Killed("test")
    AssertTrue(SnHas(wh.edits[1].content, "[TEST]") && SnHas(wh.edits[1].content, "is dead"), "the dead edit is marked too")
}


; ---- the orbs from the chat (2026-11-22, a tester: "Typhoon orb has
; spawned"). The game's wording is NOT SEEN YET: the guessed lines below. ----

Test_ChatWatch_DetectsTheOrbs() {
    d := ChatWatch.DetectOrb("[Server]: A Typhoon Orb has spawned!")
    AssertEq(d.Length, 1, "one orb")
    AssertEq(d[1], "Typhoon", "Typhoon")
    AssertEq(ChatWatch.DetectOrb("Typhoon orb has spawned")[1], "Typhoon", "the tester's own words")
    AssertEq(ChatWatch.DetectOrb("Typhaon 0rb has spowned")[1], "Typhoon", "game font: o as a / 0, a as o")
    AssertEq(ChatWatch.DetectOrb("A Flame Orb appeared in HELL")[1], "Flame", "appeared")
    AssertEq(ChatWatch.DetectOrb("F1ame Orb has arrived")[1], "Flame", "l as 1, arrived")
    AssertEq(ChatWatch.DetectOrb("Ralncloud Orb emerged")[1], "Raincloud", "i as l, emerged")
    AssertEq(ChatWatch.DetectOrb("A Blizzard Orb has spawned")[1], "Blizzard", "an orb not listed: the word as read")
    AssertEq(ChatWatch.DetectOrb("The orb has spawned")[1], "Biome", "no name: a biome orb")
    two := ChatWatch.DetectOrb("Typhoon Orb has spawned`nFlame Orb has spawned`nTyphoon Orb has spawned")
    AssertEq(two.Length, 2, "each orb once")
    ; not an orb's spawn
    for line in ["Mari has arrived on the island", "[Merchant]: Jester has arrived!", "Nameless ghosts pass by you..."
        , "The wind is picking up...", "Player found Sinister, chance of 1 in 15,000,000", "Sinister S. has spawned"
        , "anyone seen the typhoon orb", "Typhoon Orb", "Player found Orbit, chance of 1 in 500"
        , "Typhoon Orb`nhas spawned", "Typhoon orbital has spawned"]
        AssertEq(ChatWatch.DetectOrb(line).Length, 0, "no orb: " StrReplace(line, "`n", " / "))
    AssertEq(ChatWatch.DetectBoss("Typhoon Orb has spawned").Length, 0, "an orb is no boss")
}

; one report per orb line, again only after it left the chat; a line there
; at the start is old
Test_ChatWatch_OrbOncePerLineAndNotAtStart() {
    clock := QmClock(1000)
    text := "Typhoon Orb has spawned"
    orbs := [], bosses := []
    mk := (old) => ChatWatch({io: QmIO(), cal: QmCal(, Map("chat_rect", {x: 10, y: 20, w: 400, h: 200}))
        , ocr: (*) => text, now: () => clock.Now(), onOrb: (n) => orbs.Push(n), onBoss: (b) => bosses.Push(b), startOld: old})
    cw := mk(false)
    cw.Check()
    AssertEq(orbs.Length, 1, "reported")
    AssertEq(orbs[1], "Typhoon", "its name")
    AssertEq(bosses.Length, 0, "no boss")
    clock.t += 30 * 60000
    cw.Check()
    AssertEq(orbs.Length, 1, "still in the chat half an hour later: once")
    text := "Mari has arrived"
    Loop ChatWatch.AbsentReads {
        clock.t += 60000
        cw.Check()
    }
    text := "Typhoon Orb has spawned"
    clock.t += 10000
    cw.Check()
    AssertEq(orbs.Length, 2, "gone from the chat, then a new line: reported again")
    text := "Flame Orb has spawned`nTyphoon Orb has spawned"
    clock.t += 10000
    cw.Check()
    AssertEq(orbs.Length, 3, "another orb: its own report")
    AssertEq(orbs[3], "Flame", "Flame")
    ; at the start the line already there is old
    orbs := []
    text := "Typhoon Orb has spawned"
    cw2 := mk(true)
    cw2.Check()
    AssertEq(orbs.Length, 0, "line there at the start: not announced")
    text := "Typhoon Orb has spawned`nRaincloud Orb has spawned"
    clock.t += 5000
    cw2.Check()
    AssertEq(orbs.Length, 1, "a new orb line after the start: announced")
    AssertEq(orbs[1], "Raincloud", "Raincloud")
}

Test_Sinister_OrbNamesAndCards() {
    AssertEq(SinisterReport.BossName("orb:Typhoon"), "Typhoon orb", "orb name")
    AssertEq(SinisterReport.BossName("orb:<@everyone>"), "everyone orb", "only letters and digits from the OCR")
    AssertEq(SinisterReport.BossName("orb:"), "Biome orb", "no name")
    AssertEq(SinisterReport.IsOrb("s"), false, "S is no orb")
    c := SinisterReport.SpawnCard(SnLink(), "orb:Typhoon", 1700000000)
    AssertEq(c.desc, "<t:1700000000:F> (<t:1700000000:R>)`n> ## Typhoon orb has spawned`n> **[Join Server](" SnLink() ")**", "the orb's card")
    AssertEq(c.color, 0x3FA7D6, "Typhoon's colour")
    AssertEq(c.buttons[1].url, SnLink(), "Join Server button")
    AssertEq(SinisterReport.SpawnCard("", "orb:Blizzard", 1700000000).color, SinisterReport.OrbColor, "an orb not listed: the orb colour")
    b := SinisterReport.SpawnCard(SnLink(), "s", 1700000000)
    AssertTrue(InStr(b.desc, "## Sinister S. has spawned") && !InStr(b.desc, "orb"), "a boss: no 'orb'")
    AssertEq(b.color, 0x5B2A86, "S keeps its colour")
}

; an orb posts on the sinister event, once per OrbGapMs per orb, and never
; touches the boss fight's message
Test_Sinister_OrbSpawnPostsAndDedupes() {
    r := SnRep()
    AssertEq(r.rep.Spawn("GRAVEYARD@1"), true, "the boss first")
    AssertEq(r.rep.Spawn("chat:orb:Typhoon:1", "orb:Typhoon"), true, "the orb posted")
    AssertEq(r.wh.posts.Length, 2, "two messages")
    AssertEq(r.wh.posts[2].event, "sinister", "the sinister (Boss) event")
    AssertTrue(SnHas(r.wh.posts[2].content, "## Typhoon orb has spawned") && SnHas(r.wh.posts[2].content, "[Join Server](" SnLink() ")"), "the orb's text")
    AssertEq(r.wh.posts[2].opts.mention, true, "pings as the boss card")
    AssertEq(r.rep.Spawn("chat:orb:Typhoon:2", "orb:Typhoon"), false, "the same orb at once: no second")
    AssertEq(r.rep.Spawn("chat:orb:Flame:3", "orb:Flame"), true, "another orb: its own")
    r.rep.Killed("toast")
    AssertEq(r.wh.edits.Length, 1, "the boss's kill still edits")
    AssertTrue(SnHas(r.wh.edits[1].content, "Sinister S. is dead"), "the boss named dead")
    r.t.now += SinisterReport.OrbGapMs
    AssertEq(r.rep.Spawn("chat:orb:Typhoon:4", "orb:Typhoon"), true, "after the gap: a new Typhoon")
    AssertEq(r.wh.posts.Length, 4, "four messages")
}

; no Join link for an orb in a ghost server or with General.joinButton off
Test_Sinister_OrbNoLinkInGhostOrJoinOff() {
    r := SnRep(, () => true)
    r.rep.Spawn("k", "orb:Typhoon")
    c := r.wh.posts[1].content
    AssertTrue(SnHas(c, "Typhoon orb has spawned"), "ghost: the orb named")
    AssertTrue(!InStr(c.desc, "roblox.com") && !InStr(c.desc, "Join Server") && !IsObject(c.buttons), "ghost: no link, no button")
    AssertTrue(SnLogged(r.logs, "orb message goes without the Join Server link"), "logged why")
    wh := SnFakeWh()
    rep := SinisterReport({webhook: wh, cfg: QmCfg(Map("General.privateServer", SnLink(), "General.joinButton", 0)), ghost: () => false})
    AssertTrue(rep.Spawn("k", "orb:Flame"), "posted")
    c := wh.posts[1].content
    AssertTrue(SnHas(c, "Flame orb has spawned"), "join off: the orb named")
    AssertTrue(!InStr(c.desc, "roblox.com") && !InStr(c.desc, "Join Server") && !IsObject(c.buttons), "join off: no link, no button")
}
