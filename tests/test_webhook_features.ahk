#Requires AutoHotkey v2.0
; Tests for the webhook features: @everyone on top-tier rare biomes, the
; per-row Test button (Webhook.SendTo / App.OnTestWebhook / Dashboard.HookTest)
; and the start announcement (Webhook.Broadcast / App.StartSummary).
; Offline only: Webhook.dryRun or a fake WinHttp object; Dashboard windows are
; built hidden (never shown). No real URL is ever requested.
#Include ..\lib\App.ahk
#Include test_webhook.ahk
#Include test_app.ahk
#Include test_ui_dash.ahk

; ---- helpers (names must not start with Test_) -----------------------------

class WfCfg extends AppFakeCfg {
    __New(vals, hooks) {
        super.__New(vals)
        this._hooks := hooks
    }
    Webhooks() => this._hooks
}

class WfState {
    __New() {
        this.rareActive := false
        this.biome := ""
        this.rareTs := ""
    }
}

WfTmpDir() {
    d := A_Temp "\vesper_wf_" A_TickCount "_" Random(100000, 999999)
    DirCreate(d)
    return d
}

WfHook(name, tag, enabled, events, mention := "") {
    return WhMake(name, WhFakeUrl(tag), mention, enabled, events)
}

; dry-run records of one webhook (name "" = all), each parsed: {rec, p}
WfRecs(wh, name := "", event := "") {
    out := []
    for r in wh.sent {
        if (name != "" && r.name != name)
            continue
        if (event != "" && r.event != event)
            continue
        out.Push({rec: r, p: Json.Parse(r.json)})
    }
    return out
}

WfContent(p) => p.Has("content") ? p["content"] : ""

WfParse(p) => p["allowed_mentions"].Has("parse") ? p["allowed_mentions"]["parse"] : []

WfHasEveryone(p) {
    for v in WfParse(p) {
        if (v = "everyone")
            return true
    }
    return false
}

; BiomeEvents + real Webhook (dry run) + real Config in a scratch dir.
class WfRig {
    __New(settings := "", lastFile := "") {
        this.dir := WfTmpDir()
        this.cfg := Config.Load(this.dir)
        if (settings is Map) {
            for k, v in settings
                this.cfg.Set(k, v)
        }
        this.cfg.SetWebhooks([WhMake("Main", WhFakeUrl("main"), "424242", 1, ["biome", "rare"])])
        this.wh := Webhook(this.cfg)
        this.wh.dryRun := true
        this.state := WfState()
        this.lastFile := lastFile
        this.be := this.NewEvents()
    }
    ; a fresh BiomeEvents on the same state (lastFile kept: a macro restart
    ; is NewEvents with a fresh WfState)
    NewEvents() => BiomeEvents(Map("cfg", this.cfg, "state", this.state, "wh", this.wh
        , "shotFn", () => "", "soundFn", (s) => 0, "clip", {Trigger: (self, r) => 0}, "lastFile", this.lastFile))
    ; live biome event -> parsed "rare" record (or "") ; biome record via .last
    Rare(name, ts := "2026-10-25T01:00:00.000Z", extra := "") {
        this.wh.sent := []
        ev := Map("type", "biome", "name", name, "ts", ts, "live", true)
        if (extra is Map) {
            for k, v in extra
                ev[k] := v
        }
        this.be.Handle(ev)
        this.wh.Flush()
        r := WfRecs(this.wh, "", "rare")
        return r.Length ? r[1].p : ""
    }
    Done() {
        try DirDelete(this.dir, true)
    }
}

; ---- config defaults --------------------------------------------------------

Test_Wf_ConfigDefaults() {
    d := Config.IniDefaults()
    AssertEq(d["General"]["everyonePing"], "1", "everyonePing default")
    AssertEq(d["General"]["everyoneBiomes"], "DREAMSPACE,GLITCHED,CYBERSPACE", "everyoneBiomes default")
    dir := WfTmpDir()
    try {
        cfg := Config.Load(dir)
        AssertEq(cfg.Get("General.everyonePing", 0), 1, "loaded default ping")
        AssertEq(cfg.Get("General.everyoneBiomes", ""), "DREAMSPACE,GLITCHED,CYBERSPACE", "loaded default list")
    } finally {
        try DirDelete(dir, true)
    }
}

; ---- @everyone --------------------------------------------------------------

Test_Wf_EveryoneOnlyForListedLiveRareBiomes() {
    r := WfRig()
    try {
        for name in ["DREAMSPACE", "GLITCHED", "CYBERSPACE"] {
            p := r.Rare(name)
            AssertTrue(IsObject(p), name ": rare message sent")
            AssertEq(WfContent(p), "@everyone <@424242>", name ": everyone + the webhook's own mention")
            AssertTrue(WfHasEveryone(p), name ": allowed_mentions parse everyone")
            AssertEq(p["allowed_mentions"]["users"][1], "424242", name ": user id still allowed")
            ; a rare biome gets only the rare message (no extra biome card)
            for b in WfRecs(r.wh, "", "biome")
                AssertEq(WfContent(b.p), "", name ": a biome card never pings")
        }
        ; a rare biome that is NOT in the list: the mention only
        p := r.Rare("RADIANT FOREST")
        AssertTrue(IsObject(p), "radiant forest rare message")
        AssertEq(WfContent(p), "<@424242>", "unlisted rare biome: mention only")
        AssertTrue(!WfHasEveryone(p), "unlisted rare biome: no everyone permission")
        ; non-rare biome: no rare message at all
        AssertEq(r.Rare("WINDY"), "", "non-rare biome sends no rare message")
        for x in WfRecs(r.wh) {
            AssertTrue(!InStr(x.rec.json, "@everyone"), "no @everyone anywhere for a normal biome")
            AssertTrue(!WfHasEveryone(x.p), "no parse everyone for a normal biome")
        }
        ; startup backfill (not live) into a rare biome after WINDY: the
        ; Ended card and the rare message, but nobody is pinged
        r.wh.sent := []
        r.be.Handle(Map("type", "biome", "name", "GLITCHED", "ts", "x", "live", false))
        r.wh.Flush()
        AssertEq(WfRecs(r.wh, "", "rare").Length, 1, "rare message for the biome found at start")
        AssertEq(WfRecs(r.wh, "", "biome").Length, 1, "plus WINDY's Ended card, no Started card")
        for x in WfRecs(r.wh)
            AssertEq(WfContent(x.p), "", "non-live: nobody pinged")
    } finally {
        r.Done()
    }
}

Test_Wf_EveryoneOffAndListIsConfigurable() {
    r := WfRig(Map("General.everyonePing", 0))
    try {
        p := r.Rare("DREAMSPACE")
        AssertEq(WfContent(p), "<@424242>", "everyonePing=0: mention only")
        AssertTrue(!WfHasEveryone(p), "everyonePing=0: no everyone permission")
        AssertTrue(!InStr(Json.Stringify(p, 0), "@everyone"), "everyonePing=0: no @everyone text")
    } finally {
        r.Done()
    }
    r2 := WfRig(Map("General.everyoneBiomes", " glitched , Radiant Forest"))
    try {
        AssertEq(WfContent(r2.Rare("DREAMSPACE")), "<@424242>", "custom list: dreamspace dropped")
        AssertEq(WfContent(r2.Rare("GLITCHED")), "@everyone <@424242>", "custom list: case/space-insensitive")
        AssertEq(WfContent(r2.Rare("RADIANT FOREST")), "@everyone <@424242>", "custom list: extra biome")
    } finally {
        r2.Done()
    }
    ; a webhook without a mention still gets @everyone alone
    r3 := WfRig()
    try {
        r3.cfg.SetWebhooks([WhMake("Plain", WhFakeUrl("plain"), "", 1, ["rare"])])
        p := r3.Rare("CYBERSPACE")
        AssertEq(WfContent(p), "@everyone", "no mention configured: everyone alone")
        AssertTrue(WfHasEveryone(p), "parse everyone")
        AssertTrue(!p["allowed_mentions"].Has("users") && !p["allowed_mentions"].Has("roles"), "no id allowed")
    } finally {
        r3.Done()
    }
}

Test_Wf_TestEventsNeverPing() {
    r := WfRig()
    try {
        p := r.Rare("GLITCHED", "TEST-20261025010000-123")
        AssertTrue(IsObject(p), "test event still sends the rare message")
        AssertEq(WfContent(p), "", "TEST- ts: no mention, no everyone")
        AssertEq(WfParse(p).Length, 0, "TEST- ts: strict allowed_mentions")
        AssertTrue(!p["allowed_mentions"].Has("users"), "TEST- ts: no user id allowed")
        p := r.Rare("DREAMSPACE", "2026-10-25T01:00:00.000Z", Map("test", 1))
        AssertEq(WfContent(p), "", "ev.test flag: no mention, no everyone")
    } finally {
        r.Done()
    }
    ; the whole App path: App.FakeEvent routes a synthetic GLITCHED biome
    cfg := WfCfg(Map("General.sound", 0, "Medal.onRareBiome", 0, "General.dryRun", 1)
        , [WhMake("Main", WhFakeUrl("a"), "424242", 1, ["rare", "biome", "startstop"])])
    wh := Webhook(cfg)
    wh.dryRun := true
    t := AppTestMake(Map("cfgObj", cfg, "whObj", wh))
    t.app.Start()
    msg := t.app.FakeEvent("biome")
    AssertTrue(InStr(msg, "Sent"), "fake event sent: " msg)
    wh.Flush()
    rare := WfRecs(wh, "", "rare")
    AssertEq(rare.Length, 1, "one rare message from the fake event")
    AssertEq(WfContent(rare[1].p), "", "App.FakeEvent: no mention / everyone")
    AssertEq(WfParse(rare[1].p).Length, 0, "App.FakeEvent: strict allowed_mentions")
    AssertEq(SubStr(rare[1].p["embeds"][1]["title"], 1, 7), "[TEST] ", "title marked [TEST]")
    for x in WfRecs(wh) {
        AssertTrue(!WfHasEveryone(x.p) && WfContent(x.p) = "", "no @everyone ping in any message of the fake event")
        AssertTrue(!InStr(x.rec.json, "<@"), "no mention in any message of the fake event")
    }
}

Test_Wf_OnlyRareEventsCanCarryEveryone() {
    cfg := WfCfg(Map(), [WhMake("A", WhFakeUrl("a"), "424242", 1, ["biome", "errors", "rare"])])
    wh := Webhook(cfg)
    wh.dryRun := true
    wh.Send("biome", "t", "d", 0, {mention: true, everyone: true})
    wh.Send("errors", "t", "d", 0, {mention: true, everyone: true})
    wh.Send("rare", "[TEST] t", "d", 0, {mention: true, everyone: true})
    wh.Send("rare", "t", "@everyone in the embed text", 0, {everyone: false})
    wh.Flush()
    recs := WfRecs(wh)
    AssertEq(recs.Length, 4, "four messages")
    AssertEq(WfContent(recs[1].p), "<@424242>", "biome: mention kept")
    AssertTrue(!WfHasEveryone(recs[1].p), "biome: no everyone permission")
    AssertEq(WfContent(recs[2].p), "<@424242>", "errors: mention kept")
    AssertTrue(!WfHasEveryone(recs[2].p), "errors: no everyone permission")
    AssertEq(WfContent(recs[3].p), "", "[TEST] title: no mention at all")
    AssertEq(WfParse(recs[3].p).Length, 0, "[TEST] title: strict")
    AssertEq(WfContent(recs[4].p), "", "embed text cannot add content")
    AssertEq(WfParse(recs[4].p).Length, 0, "embed text cannot add permissions")
}

; ---- SendTo (single webhook) ------------------------------------------------

Test_Wf_SendToIgnoresRoutingAndNeverMentions() {
    a := WfHook("Off", "a", 0, [], "424242")                ; disabled, no events
    b := WfHook("Other", "b", 1, ["rare", "errors", "startstop"], "999")
    cfg := WhStubCfg([a, b])
    wh := Webhook(cfg)
    wh.dryRun := true
    got := []
    wh.SendTo(a, "Vesper test message", "hello", 0xF2A93B
        , {event: "test", mention: true, everyone: true, done: (ok, why) => got.Push(ok)})
    wh.Flush()
    AssertEq(wh.sent.Length, 1, "exactly one message")
    AssertEq(wh.sent[1].name, "Off", "only to the chosen (disabled, no events) webhook")
    AssertEq(wh.sent[1].event, "test", "event label")
    p := Json.Parse(wh.sent[1].json)
    AssertEq(p["embeds"][1]["title"], "Vesper test message", "title")
    AssertEq(WfContent(p), "", "no mention")
    AssertEq(WfParse(p).Length, 0, "strict allowed_mentions")
    AssertTrue(!p["allowed_mentions"].Has("users"), "no user id allowed")
    AssertEq(got.Length, 1, "done called once")
    AssertEq(got[1], 1, "done ok")
    ; a biome card sent to one webhook keeps its picture and Join Server button
    wh.sent := []
    pic := BiomeEvents.Picture("WINDY")
    wh.SendTo(a, "", "card", 1, {event: "biome", thumbnail: pic, mention: true
        , buttons: [{label: "Join Server", url: "https://www.roblox.com/share?code=X&type=Server"}]})
    wh.Flush()
    p := Json.Parse(wh.sent[1].json)
    AssertEq(p["embeds"][1]["thumbnail"]["url"], "attachment://thumb_WINDY.png", "picture kept")
    AssertEq(wh.sent[1].thumb, pic, "picture uploaded")
    AssertEq(p["components"][1]["components"][1]["label"], "Join Server", "button kept")
    AssertEq(WfContent(p), "", "still no mention")
}

Test_Wf_SendToReportsFailureScrubbed() {
    h := WfHook("Main", "main", 1, ["rare"])
    secretUrl := h["url"]
    wh := Webhook(WhStubCfg([h]))
    wh.retryDelayMs := 0
    plan := [{status: 0, sendError: "boom talking to " secretUrl, pending: 0}
        , {status: 500, sendError: "", pending: 0}]
    fake := WhFakeHttp(plan)
    wh.httpFactory := ObjBindMethod(fake, "Make")
    logs := []
    wh2 := Webhook(WhStubCfg([h]), (t) => logs.Push(t))
    wh2.retryDelayMs := 0
    wh2.httpFactory := wh.httpFactory
    res := []
    wh2.SendTo(h, "Vesper test message", "x", 0, {done: (ok, why) => res.Push({ok: ok, why: why})})
    wh2.Drain(3000)
    AssertEq(res.Length, 1, "done called exactly once after the retry")
    AssertEq(res[1].ok, 0, "failed")
    AssertTrue(!InStr(res[1].why, "SECRET") && !InStr(res[1].why, "discord.com"), "why has no URL: " res[1].why)
    for l in logs
        AssertTrue(!InStr(l, "SECRET") && !InStr(l, "discord.com/api"), "log has no URL: " l)
    ; success path
    fake2 := WhFakeHttp([{status: 204, sendError: "", pending: 0}])
    wh3 := Webhook(WhStubCfg([h]))
    wh3.httpFactory := ObjBindMethod(fake2, "Make")
    res3 := []
    wh3.SendTo(h, "t", "x", 0, {done: (ok, why) => res3.Push(ok)})
    wh3.Drain(3000)
    AssertEq(res3.Length, 1, "success done once")
    AssertEq(res3[1], 1, "success ok")
    AssertEq(fake2.opened.Length, 1, "one request")
    ; invalid url: skipped, done(0)
    bad := WhMake("Bad", "https://evil.example/api/webhooks/1/x", "", 1, [])
    wh4 := Webhook(WhStubCfg([bad]))
    fake4 := WhFakeHttp([])
    wh4.httpFactory := ObjBindMethod(fake4, "Make")
    res4 := []
    wh4.SendTo(bad, "t", "x", 0, {done: (ok, why) => res4.Push({ok: ok, why: why})})
    wh4.Drain(1000)
    AssertEq(fake4.made, 0, "no request to a non-Discord url")
    AssertEq(res4[1].ok, 0, "invalid url reported")
    AssertTrue(!InStr(res4[1].why, "evil"), "invalid url not echoed")
}

Test_Wf_AppTestWebhookSendsToOneHookOnly() {
    hooks := [WfHook("Disabled", "a", 0, [], "111")
        , WfHook("Second", "b", 1, ["rare", "startstop", "errors"], "222")
        , WfHook("NoUrl", "c", 1, ["rare"])]
    hooks[3]["url"] := ""
    cfg := WfCfg(Map(), hooks)
    wh := Webhook(cfg)
    wh.dryRun := true
    t := AppTestMake(Map("cfgObj", cfg, "whObj", wh))
    msg := t.app.OnTestWebhook(1)
    AssertEq(msg, "Test sent to Disabled", "status text")
    AssertEq(wh.sent.Length, 1, "one message total")
    AssertEq(wh.sent[1].name, "Disabled", "only the tested webhook, though disabled")
    p := Json.Parse(wh.sent[1].json)
    AssertEq(p["embeds"][1]["title"], Emoji.Check " Webhook test", "title")
    AssertEq(WfContent(p), "", "no mention")
    AssertEq(WfParse(p).Length, 0, "strict allowed_mentions")
    AssertTrue(!WfHasEveryone(p), "no @everyone ping rights")
    ; row 2 (enabled, with events) also only itself
    wh.sent := []
    AssertEq(t.app.OnTestWebhook(2), "Test sent to Second", "second ok")
    AssertEq(wh.sent.Length, 1, "one message")
    AssertEq(wh.sent[1].name, "Second", "only second")
    ; refusals
    wh.sent := []
    AssertTrue(InStr(t.app.OnTestWebhook(3), "no valid Discord webhook URL"), "missing url refused")
    AssertTrue(InStr(t.app.OnTestWebhook(9), "not saved"), "unsaved row refused")
    AssertTrue(InStr(t.app.OnTestWebhook(0), "not saved"), "bad index refused")
    wh.Flush()
    AssertEq(wh.sent.Length, 0, "refusals send nothing")
}

Test_Wf_AppTestWebhookFailureNeverShowsUrl() {
    h := WfHook("Main", "main", 1, ["rare"])
    cfg := WfCfg(Map(), [h])
    wh := Webhook(cfg, (x) => 0)
    wh.retryDelayMs := 0
    fake := WhFakeHttp([{status: 0, sendError: "cannot reach " h["url"], pending: 0}
        , {status: 404, sendError: "", pending: 0}])
    wh.httpFactory := ObjBindMethod(fake, "Make")
    t := AppTestMake(Map("cfgObj", cfg, "whObj", wh))
    msg := t.app.OnTestWebhook(1)
    AssertTrue(InStr(msg, "Test failed for Main"), "failure reported: " msg)
    AssertTrue(!InStr(msg, "SECRET") && !InStr(msg, "discord.com"), "status has no url: " msg)
    for l in t.ui.logs
        AssertTrue(!InStr(l, "SECRET"), "log has no url: " l)
    AssertEq(fake.made, 2, "one retry")
}

; ---- start announcement -----------------------------------------------------

Test_Wf_StartAnnouncementGoesToEveryEnabledHook() {
    hooks := [WfHook("OnlyErrors", "a", 1, ["errors"], "111")
        , WfHook("All", "b", 1, Webhook.EventTypes.Clone(), "222")
        , WfHook("Off", "c", 0, Webhook.EventTypes.Clone(), "333")
        , WfHook("NoEvents", "d", 1, [])]
    cfg := WfCfg(Map("General.sound", 0, "Medal.onRareBiome", 0, "Craft.enabled", 0), hooks)
    wh := Webhook(cfg)
    wh.dryRun := true
    t := AppTestMake(Map("cfgObj", cfg, "whObj", wh))
    t.app.Start()
    wh.Flush()
    for nm in ["OnlyErrors", "All", "NoEvents"] {
        r := WfRecs(wh, nm)
        started := 0
        for x in r {
            if (x.p["embeds"][1]["title"] = Emoji.Moon " " Brand.Name)
                started++
        }
        AssertEq(started, 1, nm ": exactly one start message")
        AssertEq(r.Length, 1, nm ": nothing else sent")
    }
    AssertEq(WfRecs(wh, "Off").Length, 0, "disabled webhook gets nothing")
    for x in WfRecs(wh) {
        AssertEq(WfContent(x.p), "", "no mention in the start message")
        AssertEq(WfParse(x.p).Length, 0, "strict allowed_mentions")
        AssertTrue(!x.p["allowed_mentions"].Has("users"), "no user id allowed")
        AssertTrue(!WfHasEveryone(x.p), "no @everyone ping rights")
        e := x.p["embeds"][1]
        AssertEq(e["description"], "## Macro started`nMade by Vesper`n## " Emoji.Chat " [Join our Discord](https://discord.gg/TPuxESDxe7)", "heading + big clickable Discord link")
        AssertEq(InStr(WfFieldText(e), "discord.gg"), 0, "no raw link text in the fields")
        AssertTrue(InStr(WfFieldText(e), "Fishing"), "lists fishing")
        AssertTrue(InStr(WfFieldText(e), Emoji.Cross " Off"), "craft off reflected")
    }
    ; stop keeps its old behaviour: only `startstop` hooks, and no second start message
    wh.sent := []
    t.app.Stop()
    wh.Flush()
    AssertEq(WfRecs(wh, "All").Length, 1, "stop message to the startstop webhook")
    AssertEq(WfRecs(wh, "OnlyErrors").Length, 0, "stop not sent to a hook without startstop")
    AssertEq(WfRecs(wh, "All")[1].p["embeds"][1]["title"], Emoji.Stop " Macro stopped", "stop title")
    ; each start announces again
    wh.sent := []
    t.app.Start()
    wh.Flush()
    AssertEq(WfRecs(wh, "All").Length, 1, "second start announces again")
}

; "name: value" lines of every field of an embed (flattened, `n` kept)
WfFieldText(e) {
    out := ""
    if !e.Has("fields")
        return out
    for f in e["fields"]
        out .= f["name"] ": " f["value"] "`n"
    return out
}

; value of the field whose name contains `key` ("" if none)
WfField(e, key) {
    if e.Has("fields") {
        for f in e["fields"] {
            if InStr(f["name"], key)
                return f["value"]
        }
    }
    return ""
}

Test_Wf_StartFieldsReflectConfig() {
    s := ""
    for f in App.StartFields(AppFakeCfg(Map()))
        s .= f["name"] ": " f["value"] "`n"
    AssertEq(App.StartFields(AppFakeCfg(Map())).Length, 9, "9 inline status fields (three clean rows of three); the Discord link is in the description")
    for need in ["Fishing: " Emoji.Check " On`nsells every 15 catches"
        , "Auto-craft: " Emoji.Check " On`nLucky Potion"
        , "Quests: " Emoji.Check " On", "Merchants: " Emoji.Check " On`nMari, Jester"
        , "Potions: " Emoji.Shield " Dry run (none used)"
        , "@everyone: " Emoji.Check " On`nDreamspace " Chr(0xB7) " Glitched " Chr(0xB7) " Cyberspace"
        , "Medal clips: " Emoji.Cross " Off", "Auto-rejoin: " Emoji.Check " On", "Route: VIP"]
        AssertTrue(InStr(s, need), "default fields have: " need)
    fl := App.StartFields(AppFakeCfg(Map()))
    AssertEq(fl[1]["inline"], 1, "status fields are inline")
    s := ""
    for f in App.StartFields(AppFakeCfg(Map("General.sellEvery", 7, "Craft.enabled", 0, "quests.enabled", 0
        , "merchant.enabled", 0, "General.dryRun", 0, "General.everyonePing", 0, "General.fishing", 0, "Medal.enabled", 1
        , "Medal.clipHotkey", "F9", "recovery.enabled", 0, "General.vip", 0)))
        s .= f["name"] ": " f["value"] "`n"
    AssertTrue(!InStr(s, "sells every"), "no sell detail with fishing off (2026-11-02: it said On with fishing=0)")
    for need in ["Fishing: " Emoji.Cross " Off", "Auto-craft: " Emoji.Cross " Off", "Quests: " Emoji.Cross " Off"
        , "Merchants: " Emoji.Cross " Off", "Potions: " Emoji.Warn " LIVE", "@everyone: " Emoji.Cross " Off"
        , "Medal clips: " Emoji.Check " On`nKey F9`nrare biomes`n"
        , "Auto-rejoin: " Emoji.Cross " Off", "Route: Standard"]
        AssertTrue(InStr(s, need), "changed fields have: " need)
    AssertTrue(!InStr(s, "Lucky Potion"), "no potions listed when craft is off")
    AssertTrue(!InStr(s, "auras"), "aura rule not listed while onRareAura is off")
    ; Medal field is built from the aura config: custom threshold + categories
    s := ""
    for f in App.StartFields(AppFakeCfg(Map("Medal.enabled", 1, "Medal.clipHotkey", "F8", "Medal.onRareBiome", 0
        , "Medal.onRareAura", 1, "Medal.auraMinRarity", "1000000000", "Medal.auraAlwaysCategories", "Challenged")))
        s .= f["name"] ": " f["value"] "`n"
    AssertTrue(InStr(s, "Medal clips: " Emoji.Check " On`nKey F8`nauras " Chr(0x2265) " 1 in 1,000,000,000 + Challenged"), "custom threshold: " s)
    AssertTrue(!InStr(s, "rare biomes"), "rare biomes omitted when onRareBiome=0")
    s := ""
    for f in App.StartFields(AppFakeCfg(Map("Medal.enabled", 1, "Medal.clipHotkey", "F8", "Medal.onRareAura", 1)))
        s .= f["name"] ": " f["value"] "`n"
    AssertTrue(InStr(s, "auras " Chr(0x2265) " 1 in 100,000,000 + Challenged, Challenged+"), "default threshold + classes: " s)
    s := ""
    for f in App.StartFields(AppFakeCfg(Map("Medal.enabled", 0, "Medal.onRareAura", 1)))
        s .= f["name"] ": " f["value"] "`n"
    AssertTrue(InStr(s, "Medal clips: " Emoji.Cross " Off") && !InStr(s, "auras"), "disabled: just Off")
}

; ---- dashboard --------------------------------------------------------------

Test_Wf_DashboardTestButton() {
    dir := UiDashTmp()
    d := ""
    hook := "https://discord.com/api/webhooks/222222222222222222/TOKENtestbtn_abcd"
    try {
        cfg := Config.Load(dir)
        calls := []
        reply := ["Test sent to Main"]
        d := Dashboard(cfg, Map("testWebhook", (i) => (calls.Push(i), reply[1])))
        page := d._PageByName("Webhooks")
        AssertTrue(IsObject(d.Ctrl("hook1.test")), "row 1 has a Test button")
        ; nothing saved yet
        AssertTrue(InStr(d.HookTest(1), "not saved"), "no rows: refused")
        d.HookAdd()
        d.Ctrl("hook1.name").Value := "Main"
        d.Ctrl("hook1.url").Value := hook
        AssertTrue(InStr(d.HookTest(1), "not saved"), "unsaved row refused")
        AssertEq(calls.Length, 0, "callback not called for an unsaved row")
        AssertTrue(d.SavePage("Webhooks"), "saved")
        ; typed-but-unsaved replacement url
        d.Ctrl("hook1.url").Value := hook
        AssertTrue(InStr(d.HookTest(1), "Save first"), "typed url not saved yet: refused")
        AssertEq(calls.Length, 0, "still no callback")
        d.Ctrl("hook1.url").Value := ""
        ; an edited (unsaved) field is refused too
        d.Ctrl("hook1.on").Value := 0
        AssertTrue(InStr(d.HookTest(1), "unsaved changes"), "unsaved enabled toggle: refused")
        AssertEq(calls.Length, 0, "still no callback")
        ; ok path once saved: enabled / event boxes are irrelevant to the test
        AssertTrue(d.SavePage("Webhooks"), "saved with the hook disabled")
        AssertEq(cfg.Webhooks()[1]["enabled"], 0, "hook disabled in cfg")
        msg := d.HookTest(1)
        AssertEq(msg, "Test sent to Main", "result text")
        AssertEq(calls.Length, 1, "callback called once")
        AssertEq(calls[1], 1, "with the saved row index")
        AssertEq(page.status.Text, "Test sent to Main", "shown in the page status")
        ; failure text is shown, but a URL in it never is
        reply[1] := "Test failed for Main: boom " hook
        msg := d.HookTest(1)
        AssertTrue(InStr(page.status.Text, "Test failed for Main"), "failure shown")
        AssertTrue(!InStr(page.status.Text, "TOKENtestbtn") && !InStr(page.status.Text, "discord.com/api"), "status scrubbed: " page.status.Text)
        AssertTrue(!InStr(d.LogText(), "TOKENtestbtn"), "log scrubbed")
        ; a saved row without a url
        d.HookAdd()
        d.Ctrl("hook2.name").Value := "Empty"
        AssertTrue(d.SavePage("Webhooks"), "saved with an empty url row")
        n0 := calls.Length
        AssertTrue(InStr(d.HookTest(2), "no valid Discord webhook URL"), "empty url refused")
        AssertEq(calls.Length, n0, "callback not called")
        ; row removed but not saved -> indexes no longer match the saved list
        d.HookRemove(1)
        AssertTrue(InStr(d.HookTest(1), "Save first"), "unsaved list change refused")
        AssertEq(calls.Length, n0, "callback not called after unsaved removal")
        ; without the app callback
        d2 := Dashboard(cfg, Map())
        try
            AssertTrue(InStr(d2.HookTest(1), "running " Brand.Name " app"), "no app callback")
        finally
            UiDashClose(d2)
    } finally {
        UiDashClose(d)
        try DirDelete(dir, true)
    }
}

Test_Wf_DashboardEveryoneSetting() {
    dir := UiDashTmp()
    d := "", d2 := ""
    try {
        cfg := Config.Load(dir)
        d := Dashboard(cfg, Map())
        AssertEq(d.Ctrl("General.everyonePing").Value, 1, "checkbox default on")
        AssertEq(d.Ctrl("General.everyoneBiomes").Value, "DREAMSPACE,GLITCHED,CYBERSPACE", "list default")
        d.Ctrl("General.everyonePing").Value := 0
        d.Ctrl("General.everyoneBiomes").Value := "GLITCHED"
        AssertTrue(d.SavePage("Settings"), "settings saved")
        AssertEq(cfg.Get("General.everyonePing", 1), 0, "ping off stored")
        AssertEq(cfg.Get("General.everyoneBiomes", ""), "GLITCHED", "list stored")
        c2 := Config.Load(dir)
        AssertEq(c2.Get("General.everyonePing", 1), 0, "ping off persisted")
        d2 := Dashboard(c2, Map())
        AssertEq(d2.Ctrl("General.everyonePing").Value, 0, "reload shows off")
        AssertEq(d2.Ctrl("General.everyoneBiomes").Value, "GLITCHED", "reload shows list")
    } finally {
        UiDashClose(d)
        UiDashClose(d2)
        try DirDelete(dir, true)
    }
}

; Remove row 1 then add a new one: the list length is the same again, but row 1
; is now a different webhook than the saved row 1. Test must refuse.
Test_Wf_DashboardTestRefusedAfterRemoveThenAdd() {
    dir := UiDashTmp()
    d := ""
    hookA := "https://discord.com/api/webhooks/333333333333333333/TOKENaaaa_1111"
    hookB := "https://discord.com/api/webhooks/444444444444444444/TOKENbbbb_2222"
    try {
        cfg := Config.Load(dir)
        calls := []
        d := Dashboard(cfg, Map("testWebhook", (i) => (calls.Push(i), "Test sent to x")))
        d.HookAdd()
        d.Ctrl("hook1.name").Value := "A"
        d.Ctrl("hook1.url").Value := hookA
        d.HookAdd()
        d.Ctrl("hook2.name").Value := "B"
        d.Ctrl("hook2.url").Value := hookB
        AssertTrue(d.SavePage("Webhooks"), "two hooks saved")
        AssertEq(d.HookTest(1), "Test sent to x", "clean list: test goes through")
        AssertEq(calls.Length, 1, "one call")
        d.HookRemove(1)                 ; B moves to row 1
        d.HookAdd()                     ; new empty row 2: same length as saved
        for i in [1, 2] {
            AssertTrue(InStr(d.HookTest(i), "Save first"), "row " i " refused while dirty")
        }
        AssertEq(calls.Length, 1, "no callback while dirty")
        AssertTrue(!InStr(d.Ctrl("hook1.name").Value, "A"), "row 1 now shows another webhook")
        ; after Save the list is consistent again
        AssertTrue(d.SavePage("Webhooks"), "saved")
        AssertEq(d.HookTest(1), "Test sent to x", "clean again")
        AssertEq(calls.Length, 2, "callback after save")
        ; Revert also clears the dirty state
        d.HookRemove(2)
        AssertTrue(InStr(d.HookTest(1), "Save first"), "dirty after removal")
        d.RevertPage("Webhooks")
        AssertEq(d.HookTest(1), "Test sent to x", "Revert reloads the saved list")
    } finally {
        UiDashClose(d)
        try DirDelete(dir, true)
    }
}

Test_Rebrand_StartAnnouncementUsesAppName() {
    cfg := WfCfg(Map("General.sound", 0, "Medal.onRareBiome", 0), [WfHook("A", "a", 1, ["startstop"])])
    wh := Webhook(cfg)
    wh.dryRun := true
    t := AppTestMake(Map("cfgObj", cfg, "whObj", wh))
    t.app.Start()
    wh.Flush()
    r := WfRecs(wh, "A")
    AssertEq(r.Length, 1, "one start message")
    e := r[1].p["embeds"][1]
    AssertEq(e["title"], Emoji.Moon " " Brand.Name, "start title uses Brand.Name")
    AssertEq(e["footer"]["text"], Brand.Name " v" Brand.Version, "footer uses Brand.Name + version")
    AssertEq(r[1].p.Has("username"), false, "no username override: the webhook keeps its server name")
    AssertTrue(!InStr(StrReplace(r[1].rec.json, "Made by " Credits.Name(), ""), "Vesper"), "no Vesper in the payload apart from the credit line")
}

; ---- polished embeds: fields, newlines, footer, timestamp ------------------------

Test_Embed_StartPayloadShape() {
    cfg := WfCfg(Map("General.sound", 0, "Medal.onRareBiome", 0), [WfHook("A", "a", 1, ["startstop"])])
    wh := Webhook(cfg)
    wh.dryRun := true
    t := AppTestMake(Map("cfgObj", cfg, "whObj", wh))
    t.app.Start()
    wh.Flush()
    raw := wh.sent[1].json
    AssertTrue(InStr(raw, '"inline":true'), "inline is a real JSON boolean")
    AssertTrue(!InStr(raw, "`n"), "no raw newline in compact JSON")
    p := Json.Parse(raw)
    e := p["embeds"][1]
    AssertEq(e["description"], "## Macro started`nMade by Vesper`n## " Emoji.Chat " [Join our Discord](https://discord.gg/TPuxESDxe7)", "heading + big clickable Discord link")
    AssertEq(e["color"], 0xF2A93B, "gold")
    AssertTrue(RegExMatch(e["timestamp"], "^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$"), "timestamp")
    AssertEq(e["footer"]["text"], "Moontide Macro v" Brand.Version, "footer")
    AssertEq(p.Has("username"), false, "no username override")
    AssertEq(e["fields"].Length, 9, "9 inline (3x3 grid)")
    ; real newline between craft state and potion list
    AssertTrue(InStr(WfField(e, "Merchants"), "`n"), "newline inside a field value")
    AssertTrue(InStr(raw, "\n"), "newline escaped as backslash-n on the wire")
    for f in e["fields"]
        AssertTrue(StrLen(f["name"]) <= 256 && StrLen(f["value"]) <= 1024 && f["value"] != "", "field limits: " f["name"])
}

Test_Json_RawOnlyLiterals() {
    AssertEq(Json.Stringify(Map("a", Json.Raw("true"), "b", Json.Raw("false"), "c", Json.Raw("null")), 0), '{"a":true,"b":false,"c":null}', "literals")
    for bad in ["1", "True", '"x"', "true,", "", "{}"] {
        thrown := false
        try Json.Raw(bad)
        catch
            thrown := true
        AssertTrue(thrown, "Json.Raw refuses: " bad)
    }
    thrown := false
    try Json.Raw(1)
    catch
        thrown := true
    AssertTrue(thrown, "Json.Raw refuses non-strings")
}

Test_Embed_FieldsApiNormalises() {
    cfg := WfCfg(Map(), [WfHook("A", "a", 1, ["errors"])])
    wh := Webhook(cfg)
    wh.dryRun := true
    flds := [Webhook.Field("A", "x"), Webhook.Field("", "dropped"), Webhook.Field("B", ""), {name: "C", value: "y", inline: 1}
        , Map("name", "D", "value", "z")]
    Loop 30
        flds.Push(Webhook.Field("n" A_Index, "v"))
    wh.Send("errors", "boom", "d", 0xE74C3C, {fields: flds})
    wh.Flush()
    e := Json.Parse(wh.sent[1].json)["embeds"][1]
    AssertEq(e["fields"].Length, 25, "capped at 25, empties dropped")
    AssertEq(e["fields"][2]["name"], "C", "object form accepted")
    AssertEq(e["fields"][2]["inline"], 1, "inline kept")
    AssertEq(e["fields"][3]["inline"], 0, "default not inline")
    AssertEq(e["title"], Emoji.Warn " boom", "errors emoji")
    wh.sent := []
    wh.Send("errors", "[TEST] boom", "d", 0xE74C3C)
    wh.Flush()
    e := Json.Parse(wh.sent[1].json)["embeds"][1]
    AssertEq(e["title"], "[TEST] " Emoji.Warn " boom", "[TEST] tag stays first")
    AssertTrue(!e.Has("fields"), "no fields when none given")
}

Test_Embed_StopHasUptimeAndLoops() {
    hooks := [WfHook("All", "b", 1, ["startstop"])]
    cfg := WfCfg(Map("General.sound", 0, "Medal.onRareBiome", 0), hooks)
    wh := Webhook(cfg)
    wh.dryRun := true
    t := AppTestMake(Map("cfgObj", cfg, "whObj", wh))
    t.app.Start()
    t.app._loops := 12
    wh.Flush()
    wh.sent := []
    t.app.Stop("manual")
    wh.Flush()
    e := WfRecs(wh, "All")[1].p["embeds"][1]
    AssertEq(e["title"], Emoji.Stop " Macro stopped", "stop title")
    AssertEq(WfField(e, "Loops"), "12", "loops field")
    AssertTrue(RegExMatch(WfField(e, "Ran for"), "^(\d+h )?(\d+m )?\d+s$"), "ran-for field: " WfField(e, "Ran for"))
    AssertEq(e["footer"]["text"], Brand.Footer, "footer")
}

Test_Embed_RareBiomeFieldsAndJoinLink() {
    rig := WfRig(Map("General.joinButton", 1, "General.privateServer", "https://www.roblox.com/share?code=ABC123&type=Server"))
    p := rig.Rare("GLITCHED")
    AssertTrue(IsObject(p), "one rare message")
    e := p["embeds"][1]
    AssertEq(e["title"], Emoji.Siren " RARE BIOME: GLITCHED", "title")
    AssertTrue(RegExMatch(WfField(e, "Started"), "^<t:\d+:T> \(<t:\d+:R>\)$"), "discord timestamp field")
    AssertTrue(InStr(WfField(e, "Join server"), "https://www.roblox.com/share?code=ABC123"), "join link field")
    AssertEq(e["footer"]["text"], Brand.Footer, "footer")
}

; ---- biome cards (Coteab style) and the stop summary --------------------------

WfBiome(r, name) {
    r.wh.sent := []
    r.be.Handle(Map("type", "biome", "name", name, "ts", "2026-10-26T01:00:00.000Z", "live", true))
    r.wh.Flush()
    out := []
    for x in WfRecs(r.wh, "", "biome")
        out.Push(x.p["embeds"][1])
    return out
}

Test_Embed_BiomeCardsStartedAndEnded() {
    r := WfRig(Map("General.joinButton", 1, "General.privateServer", "https://www.roblox.com/share?code=ABC123&type=Server"))
    try {
        c := WfBiome(r, "WINDY")
        AssertEq(c.Length, 1, "WINDY: one card")
        AssertEq(c[1].Has("title"), false, "no title line")
        AssertTrue(InStr(c[1]["description"], "> ## Biome Started - WINDY"), "started heading")
        AssertTrue(RegExMatch(c[1]["description"], "^<t:\d+:F> \(<t:\d+:R>\)"), "Discord timestamps first")
        AssertTrue(InStr(c[1]["description"], "> **[Join Server](https://www.roblox.com/share?code=ABC123&type=Server)**"), "join link")
        AssertEq(c[1]["color"], BiomeEvents.Color("WINDY"), "windy colour")
        AssertEq(c[1]["footer"]["text"], Brand.Footer, "footer")
        c := WfBiome(r, "CORRUPTION")
        AssertEq(c.Length, 2, "ended + started")
        AssertTrue(InStr(c[1]["description"], "> ## Biome Ended - WINDY"), "windy ended first")
        AssertEq(InStr(c[1]["description"], "Join Server"), 0, "no join link on an ended card")
        AssertTrue(InStr(c[2]["description"], "> ## Biome Started - CORRUPTION"), "corruption started")
        ; every biome gets cards, NORMAL and rare ones included
        c := WfBiome(r, "NORMAL")
        AssertEq(c.Length, 2, "NORMAL: corruption ended + normal started")
        AssertTrue(InStr(c[1]["description"], "Biome Ended - CORRUPTION"), "corruption ended")
        AssertTrue(InStr(c[2]["description"], "Biome Started - NORMAL"), "normal started")
        c := WfBiome(r, "WINDY")
        AssertEq(c.Length, 2, "after NORMAL: normal ended + windy started")
        AssertTrue(InStr(c[1]["description"], "Biome Ended - NORMAL"), "normal ended")
        c := WfBiome(r, "GLITCHED")
        AssertEq(c.Length, 1, "rare: only windy ended as a card")
        AssertTrue(InStr(c[1]["description"], "Biome Ended - WINDY"), "windy ended")
        AssertEq(WfRecs(r.wh, "", "rare").Length, 1, "the rare message instead of a Started card")
        c := WfBiome(r, "NORMAL")
        AssertTrue(InStr(c[1]["description"], "Biome Ended - GLITCHED"), "a rare biome still gets its Ended card")
    } finally {
        r.Done()
    }
}

Test_Embed_BiomeStartedHasJoinServerButton() {
    link := "https://www.roblox.com/share?code=ABC123&type=Server"
    r := WfRig(Map("General.privateServer", link, "General.joinButton", 1))   ; opt-in (default off since the privacy audit)
    try {
        WfBiome(r, "WINDY")
        recs := WfRecs(r.wh, "", "biome")
        AssertEq(recs.Length, 1, "one card")
        p := recs[1].p
        AssertTrue(p.Has("components"), "card has a component row")
        btn := p["components"][1]["components"][1]
        AssertEq(p["components"][1]["type"], 1, "action row")
        AssertEq(btn["type"], 2, "button")
        AssertEq(btn["style"], 5, "link button")
        AssertEq(btn["label"], "Join Server", "label")
        AssertEq(btn["url"], link, "opens the private server link")
        WfBiome(r, "NORMAL")
        for x in WfRecs(r.wh, "", "biome")
            if InStr(x.p["embeds"][1]["description"], "Ended")
                AssertTrue(!x.p.Has("components"), "no button on an ended card")
        ; no link set -> no button
        r2 := WfRig(Map("General.privateServer", ""))
        try {
            WfBiome(r2, "WINDY")
            AssertTrue(!WfRecs(r2.wh, "", "biome")[1].p.Has("components"), "no link, no button")
        } finally
            r2.Done()
    } finally {
        r.Done()
    }
}

Test_Embed_BiomeCardsNotForTestEvents() {
    r := WfRig()
    try {
        WfBiome(r, "WINDY")
        r.Rare("GLITCHED", "TEST-20261026010000-1")
        AssertEq(WfRecs(r.wh, "", "biome").Length, 0, "a fake biome sends no biome cards")
    } finally {
        r.Done()
    }
}

; startup (not live) event -> parsed biome card embeds
WfStartup(r, name, extra := "") {
    r.wh.sent := []
    ev := Map("type", "biome", "name", name, "ts", "2026-10-26T01:00:00.000Z", "live", 0)
    if (extra is Map)
        for k, v in extra
            ev[k] := v
    r.be.Handle(ev)
    r.wh.Flush()
    out := []
    for x in WfRecs(r.wh, "", "biome")
        out.Push(x.p["embeds"][1])
    return out
}

; width, height of a PNG file (IHDR)
WfPngSize(path) {
    b := FileRead(path, "RAW")
    be := (o) => (NumGet(b, o, "UChar") << 24) | (NumGet(b, o + 1, "UChar") << 16) | (NumGet(b, o + 2, "UChar") << 8) | NumGet(b, o + 3, "UChar")
    return [be(16), be(20)]
}

Test_Embed_BiomeStartedHasSquarePicture() {
    r := WfRig()
    try {
        c := WfBiome(r, "WINDY")
        AssertTrue(c[1].Has("thumbnail"), "started card has a picture")
        AssertEq(c[1]["thumbnail"]["url"], "attachment://thumb_WINDY.png", "the WINDY picture")
        rec := WfRecs(r.wh, "", "biome")[1].rec
        AssertTrue(RegExMatch(rec.thumb, "i)\\assets\\biomes\\WINDY\.png$"), "uploaded from assets\biomes (" rec.thumb ")")
        c := WfBiome(r, "SAND STORM")
        AssertEq(c[1].Has("thumbnail"), false, "no picture on the ended card")
        AssertEq(c[2]["thumbnail"]["url"], "attachment://thumb_SAND_STORM.png", "spaces become _")
        p := r.Rare("GLITCHED")
        AssertEq(p["embeds"][1]["thumbnail"]["url"], "attachment://thumb_GLITCHED.png", "rare alert too")
        c := WfBiome(r, "SOME NEW BIOME")
        AssertEq(c[2].Has("thumbnail"), false, "unknown biome: no picture, card still sent")
    } finally {
        r.Done()
    }
    ; every biome in the shipped list has a square picture
    for n in ["NORMAL", "WINDY", "SNOWY", "RAINY", "SAND STORM", "HELL", "STARFALL", "CORRUPTION", "NULL", "HEAVEN"
        , "GLITCHED", "DREAMSPACE", "CYBERSPACE", "SINGULARITY", "RADIANT FOREST", "PUMPKIN MOON", "GRAVEYARD"
        , "BLOOD RAIN", "EGGLAND", "LOST FOREST"] {
        p := BiomeEvents.Picture(n)
        AssertTrue(p != "", n " has a picture")
        sz := WfPngSize(p)
        AssertEq(sz[1], sz[2], n " is square")
        AssertTrue(sz[1] >= 256, n " is big enough (" sz[1] ")")
    }
    AssertEq(BiomeEvents.Picture("..\..\x"), "", "no path tricks")
}

Test_Embed_BiomeChangedWhileStoppedSendsCards() {
    dir := WfTmpDir()
    last := dir "\last_biome.txt"
    r := WfRig("", last)
    try {
        ; first ever start: nothing to compare with -> no cards, remembered
        AssertEq(WfStartup(r, "WINDY").Length, 0, "first start: no cards")
        AssertEq(Trim(FileRead(last, "UTF-8")), "WINDY", "remembered")
        ; Stop/Start in the same biome: nothing
        AssertEq(WfStartup(r, "WINDY").Length, 0, "same biome: no cards")
        ; Stop, the biome changes, Start (state still says WINDY)
        c := WfStartup(r, "RAINY")
        AssertEq(c.Length, 2, "ended + started")
        AssertTrue(InStr(c[1]["description"], "> ## Biome Ended - WINDY"), "old one ended")
        AssertTrue(InStr(c[2]["description"], "> ## Biome Started - RAINY"), "new one started")
        AssertEq(c[2]["thumbnail"]["url"], "attachment://thumb_RAINY.png", "with its picture")
        AssertEq(WfRecs(r.wh, "", "rare").Length, 0, "no rare alert from a startup read")
        ; live changes are remembered too
        WfBiome(r, "NORMAL")
        AssertEq(Trim(FileRead(last, "UTF-8")), "NORMAL", "live biome remembered")
        ; the macro is closed and opened again (fresh state): the file knows NORMAL
        r.state := WfState()
        r.be := r.NewEvents()
        c := WfStartup(r, "LOST FOREST")
        AssertEq(c.Length, 2, "after a restart: ended + started")
        AssertTrue(InStr(c[1]["description"], "Biome Ended - NORMAL"), "NORMAL ended")
        AssertTrue(InStr(c[2]["description"], "Biome Started - LOST FOREST"), "LOST FOREST started")
        ; stopped, a rare biome started: Ended card + the rare message, no ping
        c := WfStartup(r, "GLITCHED")
        AssertEq(c.Length, 1, "only the Ended card")
        AssertTrue(InStr(c[1]["description"], "Biome Ended - LOST FOREST"), "LOST FOREST ended")
        rr := WfRecs(r.wh, "", "rare")
        AssertEq(rr.Length, 1, "the rare message instead of a Started card")
        AssertEq(WfContent(rr[1].p), "", "no ping from a startup read")
        WfStartup(r, "LOST FOREST")
        ; the test-event restore is silent
        AssertEq(WfStartup(r, "HELL", Map("test", 1)).Length, 0, "fake-event restore: no cards")
        AssertEq(Trim(FileRead(last, "UTF-8")), "LOST FOREST", "not remembered either")
        ; without a lastFile (tests, fake cfgs): state only
        r2 := WfRig()
        try {
            AssertEq(WfStartup(r2, "WINDY").Length, 0, "no file, no state: no cards")
            AssertEq(WfStartup(r2, "HELL").Length, 2, "state alone is enough")
        } finally
            r2.Done()
    } finally {
        r.Done()
        try DirDelete(dir, true)
    }
}

Test_Embed_StopSummaryCountsTheSession() {
    hooks := [WfHook("All", "b", 1, ["startstop"])]
    cfg := WfCfg(Map("General.sound", 0, "Medal.onRareBiome", 0), hooks)
    wh := Webhook(cfg)
    wh.dryRun := true
    t := AppTestMake(Map("cfgObj", cfg, "whObj", wh))
    t.app.Start()
    st := t.app.state
    st.Bump("fishCaught", 1234), st.Bump("fishFailed", 66), st.Bump("sells", 3), st.Bump("fishTypesSold", 11)
    t.app._loops := 1234
    wh.Flush()
    wh.sent := []
    t.app.Stop("manual")
    wh.Flush()
    e := WfRecs(wh, "All")[1].p["embeds"][1]
    AssertTrue(InStr(e["description"], "Session summary"), "summary heading")
    AssertEq(WfField(e, "Fish caught"), "1,234", "caught")
    AssertEq(WfField(e, "Got away"), "66", "got away")
    AssertEq(WfField(e, "Catch rate"), "95%", "catch rate")
    AssertEq(WfField(e, "Sell trips"), "3", "sells")
    AssertEq(WfField(e, "Fish types sold"), "11", "types sold")
    AssertEq(WfField(e, "Rare biomes"), "", "zero rows left out")
    t.app.Start()
    AssertEq(t.app.state.stats.Count, 0, "Start resets the counters")
}
