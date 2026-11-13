#Requires AutoHotkey v2.0
; Offline tests for lib\SetupCheck.ahk: every system call is a fake probe.
; Helpers are prefixed Sc (must not start with Test_).
#Include ..\lib\SetupCheck.ahk

class ScCfg {
    __New(link := "", hooks := "", extra := "") {
        this.v := Map("general.privateserver", link)
        this.hooks := hooks is Array ? hooks : []
        if IsObject(extra)
            for k, val in extra
                this.v[StrLower(k)] := val
    }
    Get(path, default := "") {
        p := StrLower(path)
        return this.v.Has(p) ? this.v[p] : default
    }
    Webhooks() => this.hooks
}

ScThrow() {
    throw Error("probe failed")
}

ScSeen(list, n) {
    list.Push(n)
    return n = "MSPCManager.exe"
}

ScCount(c) {
    c.n++
    return "Roll"
}

ScLink() =>"https://www.roblox.com/games/1/x?privateServerLinkCode=SECRETCODE99"
ScHook() => "https://discord.com/api/webhooks/123456789/AbCdEfTokenSECRET"

; Every probe answered with a healthy PC; overrides replace single keys.
ScProbes(over := "") {
    p := Map(
        "hwnd", () => 4242,
        "clientOk", () => "ok",
        "sizeText", () => "1920x1080",
        "verified", () => true,
        "scale", () => 100,
        "hdr", () => 0,
        "logAge", () => 30,
        "calMissing", () => [],
        "procs", (n) => false,
        "ahkVersion", () => "2.0.19",
        "front", () => 1,
        "rollText", () => "Roll")
    if IsObject(over)
        for k, v in over
            p[k] := v
    return p
}

ScGoodCfg() => ScCfg(ScLink(), [Map("url", ScHook(), "enabled", 1)])

ScFind(res, id) {
    for r in res
        if (r.id = id)
            return r
    return ""
}

ScAllText(res) {
    s := ""
    for r in res
        s .= r.id "|" r.name "|" r.level "|" r.detail "|" r.fix "`n"
    return s
}

Test_SetupCheck_HealthyPc() {
    res := SetupCheck.Run(ScGoodCfg(), ScProbes())
    for r in res
        AssertTrue(r.level = "ok" || r.level = "info", "no warning or problem: " r.id " " r.level " " r.detail)
    for id in ["roblox", "size", "scale", "hdr", "logs", "private", "webhooks", "calibration", "focus", "ahk", "live"]
        AssertTrue(IsObject(ScFind(res, id)), "row " id)
    AssertEq(ScFind(res, "live").level, "ok", "live read ok")
    AssertEq(SetupCheck.Summary(res), "11 ok, 0 warnings, 0 problems", "summary")
    for r in res {
        AssertTrue(r.name != "" && r.detail != "", "plain text on " r.id)
        AssertTrue(HasProp(r, "fix"), "fix field on " r.id)
    }
}

Test_SetupCheck_RobloxClosed() {
    res := SetupCheck.Run(ScGoodCfg(), ScProbes(Map("hwnd", () => 0, "clientOk", () => "missing", "front", () => 0)))
    AssertEq(ScFind(res, "roblox").level, "warn", "closed warns")
    AssertEq(ScFind(res, "size").level, "info", "size skipped")
    AssertEq(ScFind(res, "live").level, "info", "live read skipped")
    AssertTrue(InStr(ScFind(res, "live").detail, "not in front"), "says why")
}

Test_SetupCheck_WindowedIsAProblem() {
    res := SetupCheck.Run(ScGoodCfg(), ScProbes(Map("clientOk", () => "notfs")))
    r := ScFind(res, "size")
    AssertEq(r.level, "fail", "windowed fails")
    AssertTrue(InStr(r.detail, "not fullscreen"), "says windowed")
    AssertTrue(r.fix != "", "has a fix")
    AssertEq(SetupCheck.Summary(res), "10 ok, 0 warnings, 1 problem", "summary with a problem")
}

Test_SetupCheck_UntestedSizeWarns() {
    res := SetupCheck.Run(ScGoodCfg(), ScProbes(Map("sizeText", () => "1234x777", "verified", () => false)))
    r := ScFind(res, "size")
    AssertEq(r.level, "warn", "untested size warns")
    AssertTrue(InStr(r.detail, "1234x777"), "names the size")
    AssertTrue(InStr(r.detail, Screen.NotTestedNote), "reuses Screen.NotTestedNote")
}

Test_SetupCheck_Hdr() {
    res := SetupCheck.Run(ScGoodCfg(), ScProbes(Map("hdr", () => 1)))
    r := ScFind(res, "hdr")
    AssertEq(r.level, "info", "HDR on is info")
    AssertTrue(InStr(r.detail, "most PCs"), "works on most PCs")
    AssertTrue(InStr(r.fix, "turning HDR off"), "try turning it off")
    res := SetupCheck.Run(ScGoodCfg(), ScProbes(Map("hdr", () => "")))
    AssertEq(ScFind(res, "hdr").level, "info", "unknown HDR is info")
}

Test_SetupCheck_Scale() {
    res := SetupCheck.Run(ScGoodCfg(), ScProbes(Map("scale", () => 150)))
    r := ScFind(res, "scale")
    AssertEq(r.level, "ok", "any scale is supported")
    AssertTrue(InStr(r.detail, "150%"), "shows the scale")
}

Test_SetupCheck_Logs() {
    res := SetupCheck.Run(ScGoodCfg(), ScProbes(Map("logAge", () => "")))
    AssertEq(ScFind(res, "logs").level, "warn", "no log warns")
    res := SetupCheck.Run(ScGoodCfg(), ScProbes(Map("logAge", () => 7200)))
    AssertEq(ScFind(res, "logs").level, "warn", "stale log while Roblox is open warns")
    res := SetupCheck.Run(ScGoodCfg(), ScProbes(Map("logAge", () => 3600, "hwnd", () => 0, "front", () => 0)))
    AssertEq(ScFind(res, "logs").level, "ok", "an old log is normal while Roblox is closed")
    res := SetupCheck.Run(ScGoodCfg(), ScProbes(Map("logAge", () => ScThrow())))
    AssertEq(ScFind(res, "logs").level, "info", "a failing probe is an info row")
}

Test_SetupCheck_PrivateServer() {
    res := SetupCheck.Run(ScCfg("", []), ScProbes())
    r := ScFind(res, "private")
    AssertEq(r.level, "warn", "no link warns")
    AssertTrue(InStr(r.detail, "auto-rejoin"), "says what it is for")
    res := SetupCheck.Run(ScCfg(ScLink(), []), ScProbes())
    r := ScFind(res, "private")
    AssertEq(r.level, "ok", "a good link is ok (real RecoveryTask.LinkOk)")
    AssertTrue(!InStr(ScAllText(res), "SECRETCODE99") && !InStr(ScAllText(res), "roblox.com/games"), "the link is never printed")
    res := SetupCheck.Run(ScCfg("http://example.com/abc", []), ScProbes())
    AssertEq(ScFind(res, "private").level, "warn", "a wrong-looking link warns")
    AssertTrue(!InStr(ScAllText(res), "example.com"), "a bad link is not printed either")
}

Test_SetupCheck_Webhooks() {
    AssertEq(ScFind(SetupCheck.Run(ScCfg(ScLink(), []), ScProbes()), "webhooks").level, "info", "none enabled is info")
    hooks := [Map("url", ScHook(), "enabled", 1), Map("url", ScHook(), "enabled", 1), Map("url", "not a url", "enabled", 1)
        , Map("url", ScHook(), "enabled", 0)]
    res := SetupCheck.Run(ScCfg(ScLink(), hooks), ScProbes())
    r := ScFind(res, "webhooks")
    AssertEq(r.level, "warn", "an enabled webhook with a bad address warns")
    AssertTrue(InStr(r.detail, "2 of 3"), "counts enabled and valid: " r.detail)
    AssertTrue(!InStr(ScAllText(res), "discord.com") && !InStr(ScAllText(res), "AbCdEfToken"), "URLs never printed")
    res := SetupCheck.Run(ScCfg(ScLink(), [Map("url", ScHook(), "enabled", 1)]), ScProbes())
    AssertEq(ScFind(res, "webhooks").level, "ok", "one good webhook")
    AssertTrue(InStr(ScFind(res, "webhooks").detail, "1 webhook is"), "singular")
}

Test_SetupCheck_Calibration() {
    miss := ["fisher_buy_button", "quest_accept", "selector_confirm", "obby_blessing", "chat_rect", "stella_dialog"]
    ; Craft and quests on (their defaults), BiomeItems and Obby off
    res := SetupCheck.Run(ScGoodCfg(), ScProbes(Map("calMissing", () => miss)))
    r := ScFind(res, "calibration")
    AssertEq(r.level, "warn", "needed points missing warns")
    AssertTrue(InStr(r.detail, "2 calibration points"), "only the needed ones counted: " r.detail)
    AssertTrue(InStr(r.detail, "fisher_buy_button") && InStr(r.detail, "quest_accept"), "names them")
    AssertTrue(!InStr(r.detail, "selector_confirm") && !InStr(r.detail, "obby_blessing"), "features that are off are not listed")
    ; BiomeItems on too
    cfg := ScCfg(ScLink(), [], Map("BiomeItems.enabled", 1, "Obby.enabled", 1))
    r := ScFind(SetupCheck.Run(cfg, ScProbes(Map("calMissing", () => miss))), "calibration")
    AssertTrue(InStr(r.detail, "4 calibration points"), "BiomeItems and Obby add theirs: " r.detail)
    ; everything needed is there: the rest is only counted
    cfg := ScCfg(ScLink(), [], Map("Craft.enabled", 0, "quests.enabled", 0))
    r := ScFind(SetupCheck.Run(cfg, ScProbes(Map("calMissing", () => miss))), "calibration")
    AssertEq(r.level, "info", "nothing needed missing is info")
    AssertTrue(InStr(r.detail, "6 calibration points"), "counts all: " r.detail)
    ; optional steps never warn
    r := ScFind(SetupCheck.Run(ScGoodCfg(), ScProbes(Map("calMissing", () => ["stella_dialog", "fisher_leave", "cauldron_result_2"]))), "calibration")
    AssertEq(r.level, "info", "optional steps do not warn")
    AssertEq(ScFind(SetupCheck.Run(ScGoodCfg(), ScProbes()), "calibration").level, "ok", "none missing")
}

Test_SetupCheck_FocusStealers() {
    AssertEq(SetupCheck.FocusStealers[1], "MSPCManager.exe", "PC Manager is first")
    seen := []
    res := SetupCheck.Run(ScGoodCfg(), ScProbes(Map("procs", (n) => ScSeen(seen, n))))
    r := ScFind(res, "focus")
    AssertEq(r.level, "warn", "PC Manager running warns")
    AssertEq(r.detail, "Microsoft PC Manager's toolbar can pull focus away from Roblox; close it or turn its toolbar off", "detail text")
    AssertEq(seen[1], "MSPCManager.exe", "asked for the process by name")
    AssertEq(ScFind(SetupCheck.Run(ScGoodCfg(), ScProbes()), "focus").level, "ok", "none running")
}

Test_SetupCheck_AhkVersion() {
    AssertEq(ScFind(SetupCheck.Run(ScGoodCfg(), ScProbes(Map("ahkVersion", () => "2.0.10"))), "ahk").level, "ok", "2.0.10 ok")
    AssertEq(ScFind(SetupCheck.Run(ScGoodCfg(), ScProbes(Map("ahkVersion", () => "2.0.9"))), "ahk").level, "fail", "2.0.9 too old")
    AssertEq(ScFind(SetupCheck.Run(ScGoodCfg(), ScProbes(Map("ahkVersion", () => "2.1-alpha.3"))), "ahk").level, "ok", "2.1 alpha ok")
}

Test_SetupCheck_LiveRead() {
    r := ScFind(SetupCheck.Run(ScGoodCfg(), ScProbes(Map("rollText", () => "Auto Roll"))), "live")
    AssertEq(r.level, "ok", "Roll found in the text")
    AssertTrue(InStr(r.detail, "can read your screen"), "says it can read the screen")
    r := ScFind(SetupCheck.Run(ScGoodCfg(), ScProbes(Map("rollText", () => "xx"))), "live")
    AssertEq(r.level, "warn", "unreadable warns")
    r := ScFind(SetupCheck.Run(ScGoodCfg(), ScProbes(Map("rollText", () => ""))), "live")
    AssertEq(r.level, "warn", "empty read warns")
    called := {n: 0}
    r := ScFind(SetupCheck.Run(ScGoodCfg(), ScProbes(Map("front", () => 0, "rollText", () => ScCount(called)))), "live")
    AssertEq(r.level, "info", "not in front is info")
    AssertEq(called.n, 0, "no OCR while Roblox is not in front")
    r := ScFind(SetupCheck.Run(ScGoodCfg(), ScProbes(Map("rollText", () => ScThrow()))), "live")
    AssertEq(r.level, "info", "a throwing OCR is info")
}

Test_SetupCheck_SummaryAndReport() {
    res := [{id: "a", name: "A", level: "ok", detail: "fine", fix: ""}
        , {id: "b", name: "B", level: "warn", detail: "hmm", fix: "do this"}
        , {id: "c", name: "C", level: "info", detail: "fyi", fix: ""}]
    AssertEq(SetupCheck.Summary(res), "1 ok, 1 warning, 0 problems", "summary, singular warning")
    AssertEq(SetupCheck.Summary([]), "0 ok, 0 warnings, 0 problems", "summary of nothing")
    rep := SetupCheck.Report(res)
    AssertTrue(InStr(rep, "Setup check: 1 ok, 1 warning, 0 problems"), "report header")
    AssertTrue(InStr(rep, "[WARN] B: hmm"), "warn line")
    AssertTrue(InStr(rep, "What to do: do this"), "fix line")
    AssertTrue(!InStr(rep, "What to do: `r`n"), "no empty fix lines")
    full := SetupCheck.Report(SetupCheck.Run(ScGoodCfg(), ScProbes()))
    AssertTrue(!InStr(full, "SECRETCODE99") && !InStr(full, "AbCdEfToken"), "the report holds no secrets")
}

Test_SetupCheck_NoCfgDoesNotThrow() {
    res := SetupCheck.Run("", ScProbes())
    AssertEq(ScFind(res, "private").level, "warn", "no cfg = no link")
    AssertEq(ScFind(res, "webhooks").level, "info", "no cfg = no webhooks")
}
