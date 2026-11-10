#Requires AutoHotkey v2.0
; Tests for lib\Json.ahk and lib\Config.ahk.
; Config tests ONLY use a temp dir under A_Temp, never the repo's settings.ini.
#Include ..\lib\Json.ahk
#Include ..\lib\Config.ahk

; ---- helpers (names must not start with Test_) -----------------------------

CfgTmpDir() {
    d := A_Temp "\vesper_cfgtest_" A_TickCount "_" Random(100000, 999999)
    DirCreate(d)
    return d
}

CfgTmpClean(d) {
    try DirDelete(d, true)
}

CfgThrows(fn) {
    try fn()
    catch
        return true
    return false
}

; ---- Json ------------------------------------------------------------------

Test_Json_RoundTrip() {
    uni := "h" Chr(0xE9) "llo " Chr(0x2603) " " Chr(0x65E5) Chr(0x672C) " " Chr(0x1F600)
    tricky := 'he said "hi" \ back / slash`n`ttab' Chr(1)
    src := Map(
        "name", "Vesper",
        "quote", tricky,
        "uni", uni,
        "int", 42,
        "neg", -7,
        "float", 2.5,
        "nested", Map("list", [1, "two", Map("k", "v"), [3, [4]]], "empty", Map(), "none", []),
        "emptyStr", ""
    )
    for indent in [2, 0, 4] {
        text := Json.Stringify(src, indent)
        back := Json.Parse(text)
        AssertEq(Type(back), "Map", "root type indent " indent)
        AssertEq(back["quote"], tricky, "quote/escapes indent " indent)
        AssertEq(back["uni"], uni, "unicode indent " indent)
        AssertEq(back["int"], 42, "int indent " indent)
        AssertEq(back["neg"], -7, "neg indent " indent)
        AssertEq(back["float"], 2.5, "float indent " indent)
        AssertEq(back["emptyStr"], "", "empty string indent " indent)
        AssertEq(Type(back["nested"]["list"]), "Array", "array type indent " indent)
        AssertEq(back["nested"]["list"][3]["k"], "v", "nested map indent " indent)
        AssertEq(back["nested"]["list"][4][2][1], 4, "nested array indent " indent)
        AssertEq(back["nested"]["empty"].Count, 0, "empty map indent " indent)
        AssertEq(back["nested"]["none"].Length, 0, "empty array indent " indent)
        AssertEq(Json.Stringify(back, indent), text, "stable re-stringify indent " indent)
    }
    ; compact has no newlines; indented does
    AssertTrue(!InStr(Json.Stringify(src, 0), "`n"), "indent 0 is single line")
    AssertTrue(InStr(Json.Stringify(src, 2), "`n"), "indent 2 is multi line")
}

Test_Json_ParseValues() {
    v := Json.Parse('{"t":true,"f":false,"n":null,"e":1e2,"x":-0.5,"u":"é😀","s":"a\/b\b\f\n\r\t"}')
    AssertEq(v["t"], 1, "true -> 1")
    AssertEq(v["f"], 0, "false -> 0")
    AssertEq(v["n"], "", "null -> empty string")
    AssertEq(Type(v["e"]), "Float", "exponent is Float")
    AssertEq(v["x"], -0.5, "negative float")
    AssertEq(v["u"], Chr(0xE9) Chr(0x1F600), "unicode escapes incl surrogate pair")
    AssertEq(v["s"], "a/b`b`f`n`r`t", "simple escapes")
    ; whitespace and BOM tolerated
    w := Json.Parse(Chr(0xFEFF) " `r`n[ 1 , 2 ]`t")
    AssertEq(w.Length, 2, "BOM+whitespace array")
}

Test_Json_ParseErrors() {
    bad := ["", "{", "[1,]", '{"a":1,}', "tru", '"abc', "01", "[1] x", "nul", '{"a" 1}', "{1:2}", '"\q"', '"\u12G4"', "[", '{"a":}']
    for s in bad {
        thrown := false
        try Json.Parse(s)
        catch
            thrown := true
        AssertTrue(thrown, "should reject <" s ">")
    }
}

; ---- Config: ini + defaults ------------------------------------------------

Test_Config_CreatesIniWithDefaults() {
    d := CfgTmpDir()
    try {
        AssertTrue(!FileExist(d "\settings.ini"), "precondition: no ini")
        cfg := Config.Load(d)
        AssertTrue(FileExist(d "\settings.ini") != "", "ini created")
        AssertEq(cfg.Get("Hotkeys.start", ""), "F1", "default start hotkey")
        AssertEq(cfg.Get("Hotkeys.pause", ""), "F2", "default pause hotkey")
        AssertEq(cfg.Get("Hotkeys.stop", ""), "F3", "default stop hotkey")
        AssertEq(cfg.Get("General.sellEvery", 0), 15, "default sellEvery is Integer")
        AssertEq(cfg.Get("Obby.intervalMin"), "10", "default obby interval")
        AssertEq(cfg.Get("Obby.enabled"), "0", "obby off by default")
        AssertEq(cfg.Get("Obby.route"), "obby", "default obby route")
        AssertEq(cfg.Get("Obby.retries"), "1", "default obby retries")
        AssertEq(cfg.Get("MemoryMatch.enabled"), "0", "memory match off by default")
        AssertEq(cfg.Get("MemoryMatch.route"), "memory_match", "default memory match route")
        AssertEq(cfg.Webhooks().Length, 0, "no webhooks by default")
        ; missing key falls back to caller default, typed
        AssertEq(cfg.Get("fishing.sellEvery", 15), 15, "missing -> default")
        AssertEq(cfg.Get("fishing.name", "x"), "x", "missing string -> default")
        ; set + save + reload
        cfg.Set("fishing.sellEvery", 9)
        cfg.Set("General.note", "caf" Chr(0xE9) " = ok; fine")
        cfg.Save()
        cfg2 := Config.Load(d)
        AssertEq(cfg2.Get("fishing.sellEvery", 15), 9, "persisted int")
        AssertEq(cfg2.Get("General.note", ""), "caf" Chr(0xE9) " = ok; fine", "persisted utf8 string with equals and semicolon")
        ; numeric coercion follows default type
        cfg2.Set("General.flag", "true")
        AssertEq(cfg2.Get("General.flag", 0), 1, "true -> 1 for Integer default")
        cfg2.Set("General.junk", "abc")
        AssertEq(cfg2.Get("General.junk", 7), 7, "non-numeric -> default for Integer default")
        AssertEq(cfg2.Get("General.junk", ""), "abc", "string default returns raw")
    } finally CfgTmpClean(d)
}

Test_Config_ExistingIniNotOverwritten() {
    d := CfgTmpDir()
    try {
        f := FileOpen(d "\settings.ini", "w", "UTF-8-RAW")
        f.Write("; comment`r`n[General]`r`nsellEvery=4`r`n`r`nbad line no equals`r`n[Hotkeys]`r`nstart = F5 `r`n")
        f.Close()
        cfg := Config.Load(d)
        AssertEq(cfg.Get("General.sellEvery", 15), 4, "reads existing value")
        AssertEq(cfg.Get("Hotkeys.start", ""), "F5", "trims spaces")
        AssertEq(cfg.Get("Hotkeys.stop", "F3"), "F3", "absent key not injected")
    } finally CfgTmpClean(d)
}

; ---- Config: data json -----------------------------------------------------

Test_Config_MissingOrBadJson_Defaults() {
    d := CfgTmpDir()
    try {
        cfg := Config.Load(d)
        b := cfg.Data("biomes")
        AssertEq(Type(b), "Map", "biomes is Map")
        AssertEq(b["biomes"].Length, 20, "20 default biomes (incl. LOST FOREST)")
        names := []
        for e in b["biomes"]
            names.Push(e["name"])
        AssertEq(names[9] "|" names[10], "LOST FOREST|NULL", "LOST FOREST right above NULL")
        ; the shipped data\biomes.json has the same order
        shipped := Json.Parse(FileRead(RegExReplace(A_LineFile, "\\tests\\[^\\]+$", "") "\data\biomes.json", "UTF-8"))["biomes"]
        sn := []
        for e in shipped
            sn.Push(e["name"])
        for i, n in names
            AssertEq(sn[i], n, "shipped biome " i)
        AssertEq(cfg.DataStatus("biomes"), "missing", "missing status")
        AssertEq(cfg.Data("merchants")["Mari"].Length, 0, "merchants Mari empty")
        ; unknown data name -> empty Map, not an error
        AssertEq(cfg.Data("nosuch").Count, 0, "unknown data empty Map")
        ; bad json -> defaults, file left untouched
        DirCreate(d "\data")
        f := FileOpen(d "\data\potions.json", "w", "UTF-8-RAW")
        f.Write("{ this is not json")
        f.Close()
        cfg2 := Config.Load(d)
        p := cfg2.Data("potions")
        AssertEq(Type(p), "Map", "bad json -> Map defaults")
        AssertTrue(p["potions"].Length > 0, "bad json -> default potions")
        AssertEq(cfg2.DataStatus("potions"), "bad", "bad status")
        AssertEq(FileRead(d "\data\potions.json", "UTF-8"), "{ this is not json", "bad file not overwritten")
        ; root that is not an object -> bad
        f := FileOpen(d "\data\quests.json", "w", "UTF-8-RAW")
        f.Write("[1,2,3]")
        f.Close()
        AssertEq(Config.Load(d).DataStatus("quests"), "bad", "array root is bad")
        ; good file wins over defaults and survives SaveData round trip
        cfg3 := Config.Load(d)
        m := Map("biomes", [Map("name", "ONLY", "rare", 1, "potions", [])])
        cfg3.SetData("biomes", m)
        cfg3.SaveData("biomes")
        cfg4 := Config.Load(d)
        AssertEq(cfg4.DataStatus("biomes"), "ok", "saved file ok")
        AssertEq(cfg4.Data("biomes")["biomes"][1]["name"], "ONLY", "saved data loaded")
        AssertTrue(CfgThrows(() => cfg4.Data("..\evil")), "data name with path chars rejected")
    } finally CfgTmpClean(d)
}

Test_Config_ShippedDataMatchesDefaults() {
    repo := A_ScriptDir "\.."
    for name in ["biomes", "potions", "quests", "merchants"] {
        path := repo "\data\" name ".json"
        AssertTrue(FileExist(path) != "", name ".json shipped")
        parsed := Json.Parse(FileRead(path, "UTF-8"))
        AssertEq(Json.Stringify(parsed), Json.Stringify(Config.Defaults(name)), name ".json == built-in defaults")
    }
    ; spec rulings
    bio := Json.Parse(FileRead(repo "\data\biomes.json", "UTF-8"))["biomes"]
    rare := ""
    for b in bio {
        AssertEq(Type(b["potions"]), "Array", b["name"] " has potions list")
        if b["rare"]
            rare .= (rare = "" ? "" : ",") b["name"]
    }
    AssertEq(rare, "GLITCHED,DREAMSPACE,CYBERSPACE,SINGULARITY,RADIANT FOREST", "rare set")
    pot := Json.Parse(FileRead(repo "\data\potions.json", "UTF-8"))["potions"]
    unlocked := ""
    ids := Map()
    descs := Map()
    for p in pot {
        AssertEq(p["perBiome"], 1, p["id"] " perBiome")
        AssertEq(p["perDay"], 3, p["id"] " perDay")
        AssertEq(p["perRun"], 3, p["id"] " perRun")
        AssertTrue(p.Has("name") && p.Has("desc"), p["id"] " has name + desc")
        AssertTrue(!ids.Has(p["id"]), p["id"] " id unique")
        ids[p["id"]] := 1
        descs[p["id"]] := p["desc"]
        if !p["locked"]
            unlocked .= (unlocked = "" ? "" : ",") p["id"]
    }
    ; everything else (all top tier, every Godly, every new variant) locked
    AssertEq(unlocked, "Lucky Potion,Speed Potion,Fortune Potion I,Haste Potion I", "unlocked set")
    for id in ["Transcendent Potion", "Heavenly Potion", "Oblivion Potion", "Godlike Potion", "Warp Potion"
        , "Godly Potion (Sky)", "Godly Potion (Sea)", "Godly Potion (Hell)"]
        AssertTrue(ids.Has(id), "has " id)
    AssertEq(descs["Godly Potion (Sky)"], "Lord of the Sky", "Sky desc")
    AssertEq(descs["Godly Potion (Sea)"], "Lord of the Sea", "Sea desc")
    AssertEq(descs["Godly Potion (Hell)"], "Lord of Hell", "Hell desc")
    AssertEq(descs["Lucky Potion"], "", "other descs left for the user")
    for id in ["Zeus Potion", "Poseidon Potion", "Hades Potion", "Fortune Potion", "Haste Potion"]
        AssertTrue(!ids.Has(id), "no fake name " id)
    q := Json.Parse(FileRead(repo "\data\quests.json", "UTF-8"))["types"]
    n := 0
    for t in q {
        AssertEq(t["enabled"], 1, t["name"] " type enabled")
        for qq in t["quests"] {
            AssertEq(qq["enabled"], 1, qq["name"] " enabled")
            n++
        }
    }
    AssertEq(n, 25, "25 quests (3+5+1+1+5+4+1+1+1, spec 4.4, + Meditation I-III seen on the 2026 board)")
}

; ---- Config: webhooks ------------------------------------------------------

Test_Config_WebhooksRoundTrip() {
    d := CfgTmpDir()
    try {
        cfg := Config.Load(d)
        cfg.SetWebhooks([
            Map("name", "Main", "url", "https://example.invalid/hook/AAA", "mention", "123456",
                "enabled", 1, "events", ["biome", "rare", "errors"]),
            Map("name", "Caf" Chr(0xE9) " backup", "url", "https://example.invalid/hook/BBB", "mention", "",
                "enabled", 0, "events", "startstop, Potions ,clips")
        ])
        cfg.Save()
        cfg2 := Config.Load(d)
        w := cfg2.Webhooks()
        AssertEq(w.Length, 2, "two webhooks")
        AssertEq(Type(w[1]), "Map", "webhook is Map")
        AssertEq(w[1]["name"], "Main", "name 1")
        AssertEq(w[1]["url"], "https://example.invalid/hook/AAA", "url 1")
        AssertEq(w[1]["mention"], "123456", "mention 1")
        AssertEq(w[1]["enabled"], 1, "enabled 1")
        AssertEq(w[1]["events"].Length, 3, "events 1 count")
        AssertEq(w[1]["events"][2], "rare", "events 1 [2]")
        AssertEq(w[2]["name"], "Caf" Chr(0xE9) " backup", "name 2 utf8")
        AssertEq(w[2]["enabled"], 0, "disabled stays disabled")
        AssertEq(w[2]["mention"], "", "empty mention")
        AssertEq(w[2]["events"].Length, 3, "events 2 count (comma string normalised)")
        AssertEq(w[2]["events"][2], "potions", "events 2 trimmed+lowercased")
        ; ini layout: [Webhook.N] with comma events line
        ini := FileRead(d "\settings.ini", "UTF-8")
        AssertTrue(InStr(ini, "[Webhook.1]") && InStr(ini, "[Webhook.2]"), "sections present")
        AssertTrue(InStr(ini, "events=biome,rare,errors"), "events comma list")
        ; removing one renumbers contiguously
        cfg2.SetWebhooks([w[2]])
        cfg2.Save()
        w3 := Config.Load(d).Webhooks()
        AssertEq(w3.Length, 1, "one webhook after removal")
        AssertEq(w3[1]["enabled"], 0, "still disabled")
        AssertTrue(!InStr(FileRead(d "\settings.ini", "UTF-8"), "[Webhook.2]"), "stale section gone")
    } finally CfgTmpClean(d)
}

Test_Config_WebhookErrorsNeverContainUrl() {
    d := CfgTmpDir()
    try {
        cfg := Config.Load(d)
        secret := "https://example.invalid/SECRETTOKEN"
        msg := ""
        try cfg.SetWebhooks([Map("name", "x", "url", secret, "events", 5)])
        catch as e
            msg := e.Message
        AssertTrue(!InStr(msg, "SECRETTOKEN"), "error text must not leak url")
    } finally CfgTmpClean(d)
}

Test_Config_UnreadableIni_SaveRefuses() {
    d := CfgTmpDir()
    try {
        ini := d "\settings.ini"
        Config.Load(d).Save()
        cfg0 := Config.Load(d)
        cfg0.SetWebhooks([Map("name", "keep", "url", "https://example.invalid/hook/KEEPME", "enabled", 1, "events", ["rare"])])
        cfg0.Save()
        before := FileRead(ini, "UTF-8")
        ; lock: deny read/write/delete to other openers
        lock := FileOpen(ini, "r-rwd")
        try {
            cfg := Config.Load(d)
            AssertEq(cfg.Webhooks().Length, 0, "unreadable ini -> nothing loaded")
            msg := ""
            try cfg.Save()
            catch as e
                msg := e.Message
            AssertTrue(msg != "", "Save must refuse when ini was unreadable")
            AssertTrue(!InStr(msg, "KEEPME"), "refusal text has no secrets")
        } finally lock.Close()
        AssertEq(FileRead(ini, "UTF-8"), before, "ini untouched after refused Save")
        ; after lock released a fresh Load works and sees the webhook
        AssertEq(Config.Load(d).Webhooks().Length, 1, "readable again")
    } finally CfgTmpClean(d)
}

Test_Config_FailedReplace_LeavesNoTmp() {
    d := CfgTmpDir()
    try {
        cfg := Config.Load(d)
        cfg.SetWebhooks([Map("name", "x", "url", "https://example.invalid/hook/TMPSECRET", "enabled", 1, "events", [])])
        ; lock target so FileMove(overwrite) fails
        lock := FileOpen(d "\settings.ini", "r-rwd")
        thrown := false
        try {
            try cfg.Save()
            catch
                thrown := true
        } finally lock.Close()
        AssertTrue(thrown, "Save throws when replace fails")
        AssertTrue(!FileExist(d "\settings.ini.tmp"), "tmp file deleted after failed replace")
    } finally CfgTmpClean(d)
}
