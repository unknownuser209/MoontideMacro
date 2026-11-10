#Requires AutoHotkey v2.0
; Tests for lib\PotionSafety.ahk (pure logic). Usage files live in a temp dir
; under A_Temp, never the repo's data\potion_usage.json. Date is injected.
#Include ..\lib\PotionSafety.ahk

; ---- helpers (names must not start with Test_) -----------------------------

SafetyTempDir() {
    d := A_Temp "\vesper_safetytest_" A_TickCount "_" Random(100000, 999999)
    DirCreate(d)
    return d
}

SafetyCleanup(d) {
    try DirDelete(d, true)
}

; One potion entry Map. locked: 0/1 (JSON false/true after Parse). id
; defaults to name (no "id" key); desc defaults to a filled-in value unique
; per name (descs must not contain one another: desc_not_unique).
SafetyEntry(name, locked, perBiome, perDay, perRun, desc := "<default>") {
    if (desc == "<default>")
        desc := "#" name "#"
    return Map("name", name, "desc", desc, "locked", locked, "perBiome", perBiome, "perDay", perDay, "perRun", perRun)
}

; potionsCfg shaped like cfg.Data("potions").
SafetyCfg(entries*) {
    list := []
    for e in entries
        list.Push(e)
    return Map("potions", list)
}

; Mutable injected clock: obj.day is "yyyyMMdd".
class SafetyClock {
    __New(day) {
        this.day := day
    }
    Call() => this.day
}

SafetyNew(cfg, path, clock := "") {
    if (clock = "")
        clock := SafetyClock("20261023")
    return PotionSafety(cfg, path, clock)
}

SafetyLuckyCfg(perBiome := 1, perDay := 3, perRun := 3) {
    return SafetyCfg(SafetyEntry("Lucky Potion", 0, perBiome, perDay, perRun))
}

; BeginEvent every key, asserting each claim succeeds.
SafetyBegin(s, keys*) {
    for k in keys
        AssertTrue(s.BeginEvent(k), "BeginEvent " k)
}

; True when fn() throws.
SafetyThrows(fn) {
    try fn()
    catch
        return true
    return false
}

; ---- tests -----------------------------------------------------------------

Test_Safety_LockedSkips() {
    d := SafetyTempDir()
    try {
        cfg := SafetyCfg(SafetyEntry("Transcendent Potion", 1, 5, 5, 5), SafetyEntry("Lucky Potion", 0, 5, 5, 5))
        s := SafetyNew(cfg, d "\potion_usage.json")
        SafetyBegin(s, "Glitched|2026-10-23T10:00:00.000Z")
        r := s.Plan("Transcendent Potion", 5, "Glitched|2026-10-23T10:00:00.000Z", 5)
        AssertEq(r.qty, 0, "locked qty")
        AssertEq(r.reason, "locked", "locked reason")
        ; Missing locked flag also counts as locked (default refuse).
        e := Map("name", "Mystery", "perBiome", 5, "perDay", 5, "perRun", 5)
        s2 := SafetyNew(SafetyCfg(e), d "\u2.json")
        SafetyBegin(s2, "Glitched|t1")
        AssertEq(s2.Plan("Mystery", 1, "Glitched|t1", 5).reason, "locked", "missing flag locked")
        ; Non-boolean locked value ("false" string) is still locked.
        s3 := SafetyNew(SafetyCfg(SafetyEntry("Odd", "false", 5, 5, 5)), d "\u3.json")
        SafetyBegin(s3, "Glitched|t1")
        AssertEq(s3.Plan("Odd", 1, "Glitched|t1", 5).reason, "locked", "string false locked")
        ; Unlocked potion is fine.
        AssertEq(s.Plan("Lucky Potion", 1, "Glitched|2026-10-23T10:00:00.000Z", 5).reason, "ok", "unlocked ok")
    } finally SafetyCleanup(d)
}

Test_Safety_ShippedConfigLocksTopTier() {
    d := SafetyTempDir()
    try {
        cfg := Json.Parse(FileRead(A_ScriptDir "\..\data\potions.json", "UTF-8"))
        s := SafetyNew(cfg, d "\potion_usage.json")
        SafetyBegin(s, "Glitched|t1")
        for name in ["Transcendent Potion", "Heavenly Potion", "Oblivion Potion", "Godlike Potion"
            , "Godly Potion (Sky)", "Godly Potion (Sea)", "Godly Potion (Hell)", "Warp Potion"
            , "Potion of Bound", "Strange Potion II", "Jewelry Potion", "Mixed Potion", "Red Moon Potion I", "Void Heart"] {
            r := s.Plan(name, 1, "Glitched|t1", 5)
            AssertEq(r.qty, 0, name " qty")
            AssertEq(r.reason, "locked", name " locked")
        }
        ; the shared display name is not an id
        AssertEq(s.Plan("Godly Potion", 1, "Glitched|t1", 5).reason, "unknown", "display name is not an id")
        ; retired / non-luck potions are not shipped at all
        for name in ["Heavenly Potion I", "Heavenly Potion II", "Sizemax Potion", "Sizemin Potion"]
            AssertEq(s.Plan(name, 1, "Glitched|t1", 5).reason, "unknown", name " not shipped")
    } finally SafetyCleanup(d)
}

Test_Safety_ShippedConfigLuckyNeedsDesc() {
    d := SafetyTempDir()
    try {
        cfg := Json.Parse(FileRead(A_ScriptDir "\..\data\potions.json", "UTF-8"))
        s := SafetyNew(cfg, d "\potion_usage.json")
        SafetyBegin(s, "Glitched|t1")
        ; shipped desc is "" until the user fills it in from the game
        r := s.Plan("Lucky Potion", 1, "Glitched|t1", 5)
        AssertEq(r.reason, "no_desc", "shipped Lucky (JSON false) needs a desc")
        AssertEq(r.qty, 0, "no_desc qty")
        ; with a desc the unlocked shipped entry is usable
        for e in cfg["potions"]
            if (e["id"] = "Lucky Potion")
                e["desc"] := "[Lucky]"
        s2 := SafetyNew(cfg, d "\u2.json")
        SafetyBegin(s2, "Glitched|t1")
        r := s2.Plan("Lucky Potion", 1, "Glitched|t1", 5)
        AssertEq(r.reason, "ok", "shipped Lucky with desc ok")
        AssertEq(r.qty, 1, "shipped Lucky qty")
        AssertEq(s2.Info("Lucky Potion").desc, "[Lucky]", "Info desc")
        AssertEq(s2.Info("Godly Potion (Sea)").name, "Godly Potion", "Info name")
        AssertEq(s2.Info("Godly Potion (Sea)").desc, "Lord of the Sea", "Info Sea desc")
        AssertEq(s2.Info("Nope"), "", "Info unknown")
    } finally SafetyCleanup(d)
}

Test_Safety_NoDescRefusedAndRecordThrows() {
    d := SafetyTempDir()
    try {
        cfg := SafetyCfg(SafetyEntry("Lucky Potion", 0, 5, 5, 5, ""), SafetyEntry("Zeus", 1, 5, 5, 5, ""))
        s := SafetyNew(cfg, d "\potion_usage.json")
        ; locked beats no_desc; no_desc beats bad_event / not begun
        AssertEq(s.Plan("Zeus", 1, "Glitched|t1", 5).reason, "locked", "locked before no_desc")
        AssertEq(s.Plan("Lucky Potion", 1, "", 5).reason, "no_desc", "no_desc before bad_event")
        AssertEq(s.Plan("Lucky Potion", 1, "Glitched|t1", 5).reason, "no_desc", "no_desc before not begun")
        SafetyBegin(s, "Glitched|t1")
        AssertTrue(SafetyThrows(() => s.Record("Lucky Potion", "Glitched|t1")), "Record refuses no desc")
        AssertEq(s.Plan("Lucky Potion", 1, "Glitched|t1", 5).reason, "record_failed", "halted after")
        ; whitespace-only desc counts as empty
        s2 := SafetyNew(SafetyCfg(SafetyEntry("Lucky Potion", 0, 5, 5, 5, "   ")), d "\u2.json")
        SafetyBegin(s2, "Glitched|t1")
        AssertEq(s2.Plan("Lucky Potion", 1, "Glitched|t1", 5).reason, "no_desc", "blank desc")
        ; missing desc key counts as empty
        e := Map("name", "Lucky Potion", "locked", 0, "perBiome", 5, "perDay", 5, "perRun", 5)
        s3 := SafetyNew(SafetyCfg(e), d "\u3.json")
        SafetyBegin(s3, "Glitched|t1")
        AssertEq(s3.Plan("Lucky Potion", 1, "Glitched|t1", 5).reason, "no_desc", "missing desc")
    } finally SafetyCleanup(d)
}

Test_Safety_DescMustBeUnique() {
    d := SafetyTempDir()
    try {
        cfg := SafetyCfg(SafetyEntry("Lucky Potion", 0, 5, 5, 5, "[Lucky]")
            , SafetyEntry("Lucky Potion L", 0, 5, 5, 5, "3 minutes of [LUCKY]")       ; contains "[Lucky]" (canonical)
            , SafetyEntry("Speed Potion", 0, 5, 5, 5, "Quick Roll")
            , SafetyEntry("Speed Potion L", 0, 5, 5, 5, "quick  roll")                ; same desc
            , SafetyEntry("Haste Potion I", 0, 5, 5, 5, "[Haste I]:")
            , SafetyEntry("Haste Potion II", 0, 5, 5, 5, "[Haste II]:")               ; not a substring
            , SafetyEntry("Warp Potion", 0, 5, 5, 5, ""))                              ; empty never counts
        s := SafetyNew(cfg, d "\potion_usage.json")
        SafetyBegin(s, "Glitched|t1")
        for id in ["Lucky Potion", "Lucky Potion L", "Speed Potion", "Speed Potion L"]
            AssertEq(s.Plan(id, 1, "Glitched|t1", 5).reason, "desc_not_unique", id " refused")
        AssertEq(s.Plan("Haste Potion I", 1, "Glitched|t1", 5).reason, "ok", "distinct desc ok")
        AssertEq(s.Plan("Haste Potion II", 1, "Glitched|t1", 5).reason, "ok", "distinct desc ok 2")
        AssertEq(s.Plan("Warp Potion", 1, "Glitched|t1", 5).reason, "no_desc", "empty desc is no_desc")
        AssertTrue(SafetyThrows(() => s.Record("Speed Potion", "Glitched|t1")), "Record refuses")
        ; shipped Godly descs are mutually distinct
        s2 := SafetyNew(Json.Parse(FileRead(A_ScriptDir "\..\data\potions.json", "UTF-8")), d "\u2.json")
        for id in ["Godly Potion (Sky)", "Godly Potion (Sea)", "Godly Potion (Hell)"]
            AssertEq(s2.Plan(id, 1, "Glitched|t1", 5).reason, "locked", id " only locked, not desc_not_unique")
    } finally SafetyCleanup(d)
}

Test_Safety_IdentityIsIdNotName() {
    d := SafetyTempDir()
    try {
        mk := (id, desc, lk, pb) => Map("id", id, "name", "Godly Potion", "desc", desc, "locked", lk, "perBiome", pb, "perDay", 9, "perRun", 9)
        cfg := SafetyCfg(mk("Godly Potion (Sky)", "Lord of the Sky", 0, 1), mk("Godly Potion (Sea)", "Lord of the Sea", 0, 2)
            , mk("Godly Potion (Hell)", "Lord of Hell", 1, 5))
        p := d "\potion_usage.json"
        s := SafetyNew(cfg, p)
        SafetyBegin(s, "Glitched|t1")
        AssertEq(s.Plan("Godly Potion (Sky)", 5, "Glitched|t1", 9).qty, 1, "Sky own cap 1")
        AssertEq(s.Plan("Godly Potion (Sea)", 5, "Glitched|t1", 9).qty, 2, "Sea own cap 2")
        AssertEq(s.Plan("Godly Potion (Hell)", 5, "Glitched|t1", 9).reason, "locked", "Hell own lock")
        s.Record("Godly Potion (Sky)", "Glitched|t1")
        AssertEq(s.Plan("Godly Potion (Sky)", 1, "Glitched|t1", 9).reason, "cap_biome", "Sky used up")
        AssertEq(s.Plan("Godly Potion (Sea)", 5, "Glitched|t1", 9).qty, 2, "Sea untouched by Sky's use")
        u := Json.Parse(FileRead(p, "UTF-8"))
        AssertEq(u["biome"]["GLITCHED|t1"]["Godly Potion (Sky)"], 1, "usage keyed by id")
        AssertTrue(!u["biome"]["GLITCHED|t1"].Has("Godly Potion"), "never by display name")
        ; duplicate id with a different name/desc -> locked (most restrictive)
        dup := SafetyCfg(Map("id", "X", "name", "Lucky Potion", "desc", "a", "locked", 0, "perBiome", 1, "perDay", 1, "perRun", 1)
            , Map("id", "X", "name", "Speed Potion", "desc", "a", "locked", 0, "perBiome", 1, "perDay", 1, "perRun", 1))
        s2 := SafetyNew(dup, d "\u2.json")
        SafetyBegin(s2, "Glitched|t1")
        AssertEq(s2.Plan("X", 1, "Glitched|t1", 5).reason, "locked", "conflicting duplicate id locked")
        ; bad id value -> entry ignored (unknown)
        s3 := SafetyNew(SafetyCfg(Map("id", 5, "name", "Lucky Potion", "desc", "a", "locked", 0, "perBiome", 1, "perDay", 1, "perRun", 1)), d "\u3.json")
        AssertEq(s3.Plan("Lucky Potion", 1, "Glitched|t1", 5).reason, "unknown", "non-string id ignored")
    } finally SafetyCleanup(d)
}

Test_Safety_TransferRunCountsById() {
    ; TransferRunCountsFrom (Task 14b) carries per-run counts keyed by id,
    ; never lowers a count, never clears a halt
    d := SafetyTempDir()
    try {
        mk := (id, desc) => Map("id", id, "name", "Godly Potion", "desc", desc, "locked", 0, "perBiome", 5, "perDay", 9, "perRun", 2)
        cfg := SafetyCfg(mk("Godly Potion (Sky)", "Lord of the Sky"), mk("Godly Potion (Sea)", "Lord of the Sea"))
        p := d "\potion_usage.json"
        s1 := SafetyNew(cfg, p)
        SafetyBegin(s1, "Glitched|t1")
        s1.Record("Godly Potion (Sky)", "Glitched|t1")
        s1.Record("Godly Potion (Sky)", "Glitched|t1")
        s2 := SafetyNew(cfg, p)
        s2._runCounts["Godly Potion (Sea)"] := 1
        AssertTrue(s2.TransferRunCountsFrom(s1), "transfer")
        AssertEq(s2.Plan("Godly Potion (Sky)", 1, "Glitched|t1", 9).reason, "cap_run", "Sky run cap carried (open event carried)")
        AssertEq(s2.Plan("Godly Potion (Sea)", 5, "Glitched|t1", 9).qty, 1, "Sea own count kept (not lowered, not mixed with Sky)")
    } finally SafetyCleanup(d)
}

Test_Safety_CanonConfusables() {
    d := SafetyTempDir()
    try {
        s := SafetyNew(SafetyLuckyCfg(), d "\potion_usage.json")
        ; recon OCR reads (font draws a like o)
        AssertTrue(s.NameMatches("Hoste`nPotion I", "Haste Potion I"), "Hoste = Haste")
        AssertTrue(s.NameMatches("Tronscendent Potion", "Transcendent Potion"), "Tronscendent")
        AssertTrue(s.NameMatches("Wnrp potion", "Warp Potion"), "Wnrp")
        AssertTrue(s.NameMatches("Strange Potion Il", "Strange Potion II"), "Il = II")
        AssertTrue(s.NameMatches("Red Moon Potion |", "Red Moon Potion I"), "| = I")
        AssertTrue(s.NameMatches("F0rtune Potion 1", "Fortune Potion I"), "0/1")
        AssertTrue(s.NameMatches("Speed Potion L", "Speed Potion L"), "L suffix")
        ; still exact on the canonical string
        AssertTrue(!s.NameMatches("Heovenly Potion II", "Heavenly Potion"), "II never matches plain")
        AssertTrue(!s.NameMatches("Heavenly Potion", "Heavenly Potion II"), "plain never matches II")
        AssertTrue(!s.NameMatches("Speed Potion", "Speed Potion L"), "Speed != Speed L")
        AssertTrue(!s.NameMatches("Speed Potion L", "Speed Potion"), "Speed L != Speed")
        AssertTrue(s.NameMatches("SPEED POTION L", "Speed Potion L"), "case-insensitive incl. L")
        AssertTrue(!s.NameMatches("Godly Potion", "Godlike Potion"), "Godly != Godlike")
        AssertTrue(!s.NameMatches("Godlike Potion", "Godly Potion"), "Godlike != Godly")
        AssertTrue(!s.NameMatches("Haste Potion II", "Haste Potion I"), "II != I")
        AssertTrue(!s.NameMatches("Huge Fortune Potion I", "Fortune Potion I"), "Huge prefix")
        ; desc substring, canonical
        AssertTrue(s.DescMatches("Gives you 4 hours of [Lord of the Sky]", "Lord of the Sky"), "Sky desc")
        AssertTrue(!s.DescMatches("Gives you 4 hours of [Lord of the Sea]", "Lord of the Sky"), "Sea is not Sky")
        AssertTrue(!s.DescMatches("Gives you 4 hours of [Lord of the Sky]", "Lord of the Sea"), "Sky is not Sea")
        AssertTrue(!s.DescMatches("Gives you 4 hours of [Lord of Hell]", "Lord of the Sky"), "Hell is not Sky")
        AssertTrue(s.DescMatches("Gives you 4 hours of`n[Lord of Hell]: -50% Luck", "lord  of hell"), "case/ws")
        AssertTrue(!s.DescMatches("anything", ""), "empty desc never matches")
        AssertTrue(!s.DescMatches("", "Lord of Hell"), "empty OCR never matches")
        AssertTrue(!s.DescMatches(["x"], "x"), "object never matches")
        AssertEq(PotionSafety.Canon("  Haste`n Potion  I "), "hoste potioo i", "canon form")
    } finally SafetyCleanup(d)
}

Test_Safety_AllRealNamesCanonDistinct() {
    ; recon list of in-game potion names + every shipped entry name
    names := ["Oblivion Potion", "Godlike Potion", "Transcendent Potion", "Godly Potion", "Heavenly Potion II", "Heavenly Potion"
        , "Heavenly Potion I", "Warp Potion", "Sizemax Potion", "Sizemin Potion", "Potion of Bound", "Strange Potion II"
        , "Strange Potion I", "Jewelry Potion", "Rage Potion", "Diver Potion", "Zombie Potion", "Popping Potion"
        , "Gladiator Potion", "Huge Fortune Potion I", "Fortune Potion I", "Fortune Potion II", "Fortune Potion III"
        , "Haste Potion I", "Haste Potion II", "Haste Potion III", "Mixed Potion", "Speed Potion", "Speed Potion L"
        , "Speed Potion XL", "Lucky Potion", "Lucky Potion L", "Lucky Potion XL", "Red Moon Potion I", "Red Moon Potion II"
        , "Raid Potion", "Potion of the Dune", "Universe Potion I", "Tidal Shifter Potion", "Santa Claus Potion"
        , "Rudolph Potion", "Elf Potion", "NPC Potion"]
    seen := Map()
    for n in names
        seen[n] := 1
    for e in Json.Parse(FileRead(A_ScriptDir "\..\data\potions.json", "UTF-8"))["potions"]
        if !seen.Has(e["name"])
            names.Push(e["name"]), seen[e["name"]] := 1
    canon := Map()
    for n in names {
        c := PotionSafety.Canon(n)
        AssertTrue(!canon.Has(c), n " collides with " (canon.Has(c) ? canon[c] : ""))
        canon[c] := n
    }
}

Test_Safety_UnknownPotion_Refused() {
    d := SafetyTempDir()
    try {
        s := SafetyNew(SafetyLuckyCfg(), d "\potion_usage.json")
        SafetyBegin(s, "Glitched|t1")
        r := s.Plan("Lucky", 1, "Glitched|t1", 5)
        AssertEq(r.qty, 0, "unknown qty")
        AssertEq(r.reason, "unknown", "unknown reason")
        AssertEq(s.Plan("lucky", 1, "Glitched|t1", 5).reason, "unknown", "lookup is exact")
        ; Malformed config -> everything unknown.
        s2 := SafetyNew(Map("nope", 1), d "\u2.json")
        AssertEq(s2.Plan("Lucky Potion", 1, "Glitched|t1", 5).reason, "unknown", "bad cfg")
        s3 := SafetyNew("", d "\u3.json")
        AssertEq(s3.Plan("Lucky Potion", 1, "Glitched|t1", 5).reason, "unknown", "no cfg")
    } finally SafetyCleanup(d)
}

Test_Safety_CapsClampQty() {
    d := SafetyTempDir()
    try {
        s := SafetyNew(SafetyLuckyCfg(1, 3, 3), d "\potion_usage.json")
        SafetyBegin(s, "Glitched|t1", "Glitched|t2")
        r := s.Plan("Lucky Potion", 5, "Glitched|t1", 10)
        AssertEq(r.qty, 1, "want 5 perBiome 1")
        AssertEq(r.reason, "ok", "ok reason")
        ; perDay clamps when lower than perBiome.
        s2 := SafetyNew(SafetyLuckyCfg(5, 2, 9), d "\u2.json")
        SafetyBegin(s2, "Glitched|t1")
        AssertEq(s2.Plan("Lucky Potion", 5, "Glitched|t1", 10).qty, 2, "perDay clamp")
        ; perRun clamps when lowest.
        s3 := SafetyNew(SafetyLuckyCfg(5, 9, 3), d "\u3.json")
        SafetyBegin(s3, "Glitched|t1")
        AssertEq(s3.Plan("Lucky Potion", 5, "Glitched|t1", 10).qty, 3, "perRun clamp")
        ; wantQty lowest.
        AssertEq(s3.Plan("Lucky Potion", 2, "Glitched|t1", 10).qty, 2, "want clamp")
        ; Per-biome is hard: after 1 recorded use, the same event gets 0.
        s.Record("Lucky Potion", "Glitched|t1")
        r := s.Plan("Lucky Potion", 5, "Glitched|t1", 10)
        AssertEq(r.qty, 0, "biome cap hit qty")
        AssertEq(r.reason, "cap_biome", "biome cap reason")
        ; A different begun event is fine (day 1/3 used, run 1/3 used).
        AssertEq(s.Plan("Lucky Potion", 5, "Glitched|t2", 10).qty, 1, "next event ok")
    } finally SafetyCleanup(d)
}

Test_Safety_CapDayAndRun() {
    d := SafetyTempDir()
    try {
        p := d "\potion_usage.json"
        s := SafetyNew(SafetyLuckyCfg(1, 2, 9), p)
        SafetyBegin(s, "Glitched|t1", "Glitched|t2", "Glitched|t3")
        s.Record("Lucky Potion", "Glitched|t1")
        s.Record("Lucky Potion", "Glitched|t2")
        r := s.Plan("Lucky Potion", 1, "Glitched|t3", 10)
        AssertEq(r.qty, 0, "day cap qty")
        AssertEq(r.reason, "cap_day", "day cap reason")
        ; Run cap: per instance only.
        p2 := d "\u2.json"
        s2 := SafetyNew(SafetyLuckyCfg(1, 9, 2), p2)
        SafetyBegin(s2, "Glitched|t1", "Glitched|t2", "Glitched|t3")
        s2.Record("Lucky Potion", "Glitched|t1")
        s2.Record("Lucky Potion", "Glitched|t2")
        r := s2.Plan("Lucky Potion", 1, "Glitched|t3", 10)
        AssertEq(r.reason, "cap_run", "run cap reason")
        AssertEq(r.qty, 0, "run cap qty")
        ; New instance (new run) resets only the run counter.
        s3 := SafetyNew(SafetyLuckyCfg(1, 9, 2), p2)
        SafetyBegin(s3, "Glitched|t4")
        AssertEq(s3.Plan("Lucky Potion", 1, "Glitched|t4", 10).reason, "ok", "new run ok")
        ; Zero caps refuse.
        s4 := SafetyNew(SafetyLuckyCfg(0, 3, 3), d "\u4.json")
        SafetyBegin(s4, "Glitched|t1")
        AssertEq(s4.Plan("Lucky Potion", 1, "Glitched|t1", 10).reason, "cap_biome", "zero biome cap")
        ; Non-integer cap counts as 0.
        s5 := SafetyNew(SafetyCfg(SafetyEntry("Lucky Potion", 0, 1, "3", 3)), d "\u5.json")
        SafetyBegin(s5, "Glitched|t1")
        AssertEq(s5.Plan("Lucky Potion", 1, "Glitched|t1", 10).reason, "cap_day", "string cap = 0")
    } finally SafetyCleanup(d)
}

Test_Safety_OwnedClamps() {
    d := SafetyTempDir()
    try {
        s := SafetyNew(SafetyLuckyCfg(5, 5, 5), d "\potion_usage.json")
        SafetyBegin(s, "Glitched|t1")
        r := s.Plan("Lucky Potion", 5, "Glitched|t1", 2)
        AssertEq(r.qty, 2, "owned 2 clamps")
        AssertEq(r.reason, "ok", "owned clamp ok")
        AssertEq(s.Plan("Lucky Potion", 5, "Glitched|t1", "3").qty, 3, "owned as OCR string")
        AssertEq(s.Plan("Lucky Potion", 5, "Glitched|t1", " 4 ").qty, 4, "owned trimmed")
        r := s.Plan("Lucky Potion", 5, "Glitched|t1", 0)
        AssertEq(r.qty, 0, "owned 0 qty")
        AssertEq(r.reason, "none_owned", "owned 0 reason")
    } finally SafetyCleanup(d)
}

Test_Safety_UnreadableCount_Skip() {
    d := SafetyTempDir()
    try {
        s := SafetyNew(SafetyLuckyCfg(5, 5, 5), d "\potion_usage.json")
        SafetyBegin(s, "Glitched|t1")
        for bad in ["", "abc", "1,000", "-1", "2.5", "0x10", "3 4", "1e3", 2.0, -3] {
            r := s.Plan("Lucky Potion", 5, "Glitched|t1", bad)
            AssertEq(r.qty, 0, "bad owned <" bad "> qty")
            AssertEq(r.reason, "unreadable", "bad owned <" bad "> reason")
        }
        AssertEq(s.Plan("Lucky Potion", 5, "Glitched|t1", [1]).reason, "unreadable", "object owned")
    } finally SafetyCleanup(d)
}

Test_Safety_BadWantQtyAndEventKey() {
    d := SafetyTempDir()
    try {
        s := SafetyNew(SafetyLuckyCfg(5, 5, 5), d "\potion_usage.json")
        SafetyBegin(s, "Glitched|t1")
        for bad in [0, -1, "", "x", 1.5]
            AssertEq(s.Plan("Lucky Potion", bad, "Glitched|t1", 5).reason, "bad_qty", "want <" bad ">")
        AssertEq(s.Plan("Lucky Potion", "2", "Glitched|t1", 5).qty, 2, "want numeric string ok")
        for bad in ["", "Glitched", "|t1", "Glitched|", "a|b|c", " | "] {
            AssertEq(s.Plan("Lucky Potion", 1, bad, 5).reason, "bad_event", "event <" bad ">")
            AssertTrue(!s.BeginEvent(bad), "BeginEvent rejects <" bad ">")
        }
        ; Record with a bad key throws AND halts the instance.
        AssertTrue(SafetyThrows(() => s.Record("Lucky Potion", "Glitched")), "Record bad event throws")
        r := s.Plan("Lucky Potion", 1, "Glitched|t1", 5)
        AssertEq(r.reason, "record_failed", "bad key halts")
        AssertEq(r.qty, 0, "bad key halts qty")
        AssertTrue(!s.BeginEvent("Glitched|t9"), "halted BeginEvent false")
    } finally SafetyCleanup(d)
}

Test_Safety_RecordBadArgs_Halts() {
    d := SafetyTempDir()
    try {
        cfg := SafetyCfg(SafetyEntry("Lucky Potion", 0, 1, 9, 9), SafetyEntry("Zeus Potion", 1, 9, 9, 9))
        cases := [
            ["unknown potion", "Nope", "Glitched|t1"],
            ["locked potion", "Zeus Potion", "Glitched|t1"],
            ["non-string potion", 5, "Glitched|t1"],
            ["event not begun", "Lucky Potion", "Glitched|t2"],
            ["over biome cap", "Lucky Potion", "Glitched|t1"]   ; second Record on perBiome 1
        ]
        for c in cases {
            s := SafetyNew(cfg, d "\u" A_Index ".json")
            SafetyBegin(s, "Glitched|t1", "Glitched|t3")
            if (c[1] = "over biome cap")
                s.Record("Lucky Potion", "Glitched|t1")
            threw := false
            try s.Record(c[2], c[3])
            catch
                threw := true
            AssertTrue(threw, c[1] " throws")
            AssertEq(s.Plan("Lucky Potion", 1, "Glitched|t3", 5).reason, "record_failed", c[1] " halts")
        }
    } finally SafetyCleanup(d)
}

Test_Safety_BeginEvent_Duplicate() {
    d := SafetyTempDir()
    try {
        p := d "\potion_usage.json"
        cfg := SafetyLuckyCfg(3, 9, 9)
        s := SafetyNew(cfg, p)
        AssertTrue(s.BeginEvent("Glitched|t1"), "first claim")
        AssertTrue(!s.BeginEvent("Glitched|t1"), "duplicate same run false")
        ; Normalised: case/whitespace variants are the same event.
        AssertTrue(!s.BeginEvent("  glitched |t1 "), "normalised duplicate false")
        AssertTrue(!s.BeginEvent("GLITCHED|t1"), "upper duplicate false")
        ; Claim persisted before any click.
        u := Json.Parse(FileRead(p, "UTF-8"))
        AssertTrue(u["events"].Has("GLITCHED|t1"), "claim persisted (normalised)")
        ; Same run still uses the begun event, any key spelling.
        AssertEq(s.Plan("Lucky Potion", 1, " glitched | t1", 5).reason, "ok", "normalised Plan")
        s.Record("Lucky Potion", "Glitched|t1")
        AssertEq(s.Plan("Lucky Potion", 3, "Glitched|t1", 5).qty, 2, "repeat Plan in begun event")
        ; Restart: duplicate claim false, Plan event_done.
        s2 := SafetyNew(cfg, p)
        AssertTrue(!s2.BeginEvent("Glitched|t1"), "duplicate after restart false")
        AssertEq(s2.Plan("Lucky Potion", 1, "Glitched|t1", 5).reason, "event_done", "restart event_done")
        ; Never-begun event refused.
        AssertEq(s2.Plan("Lucky Potion", 1, "Glitched|t2", 5).reason, "event_not_begun", "not begun")
    } finally SafetyCleanup(d)
}

Test_Safety_RestartSameEvent_NoReuse() {
    d := SafetyTempDir()
    try {
        p := d "\potion_usage.json"
        ; perBiome 3 so the cap alone would still allow more uses.
        cfg := SafetyCfg(SafetyEntry("Lucky Potion", 0, 3, 9, 9), SafetyEntry("Speed Potion", 0, 3, 9, 9))
        s := SafetyNew(cfg, p)
        ev := "Glitched|2026-10-23T10:00:00.000Z"
        AssertEq(s.Plan("Lucky Potion", 3, ev, 10).reason, "event_not_begun", "plan before begin")
        SafetyBegin(s, ev)
        AssertEq(s.Plan("Lucky Potion", 3, ev, 10).qty, 3, "first plan")
        s.Record("Lucky Potion", ev)
        ; Same instance: other potions in the same event still allowed.
        AssertEq(s.Plan("Speed Potion", 1, ev, 10).reason, "ok", "same run, other potion")
        AssertEq(s.Plan("Lucky Potion", 3, ev, 10).qty, 2, "same run, remaining biome cap")
        ; Restart (new instance, same file): the event is done for every potion.
        s2 := SafetyNew(cfg, p)
        AssertTrue(!s2.BeginEvent(ev), "restart cannot re-claim")
        r := s2.Plan("Lucky Potion", 3, ev, 10)
        AssertEq(r.qty, 0, "restart qty")
        AssertEq(r.reason, "event_done", "restart reason")
        AssertEq(s2.Plan("Speed Potion", 1, ev, 10).reason, "event_done", "restart other potion")
        ; A new event after restart is fine.
        ev2 := "Glitched|2026-10-23T11:00:00.000Z"
        SafetyBegin(s2, ev2)
        AssertEq(s2.Plan("Lucky Potion", 1, ev2, 10).reason, "ok", "new event")
        ; Record persisted immediately: file has the count (normalised key).
        u := Json.Parse(FileRead(p, "UTF-8"))
        nk := "GLITCHED|2026-10-23T10:00:00.000Z"
        AssertEq(u["biome"][nk]["Lucky Potion"], 1, "persisted biome count")
        AssertEq(u["day"]["20261023"]["Lucky Potion"], 1, "persisted day count")
        AssertTrue(u["events"].Has(nk), "persisted event key")
        AssertTrue(!FileExist(p ".tmp"), "no tmp left")
        AssertTrue(!FileExist(p ".probe"), "no probe left")
    } finally SafetyCleanup(d)
}

Test_Safety_MarkEventDone() {
    d := SafetyTempDir()
    try {
        p := d "\potion_usage.json"
        s := SafetyNew(SafetyLuckyCfg(3, 9, 9), p)
        ev := "Glitched|t1"
        SafetyBegin(s, ev)
        s.MarkEventDone(ev)
        AssertEq(s.Plan("Lucky Potion", 1, ev, 10).reason, "event_done", "same run after done")
        AssertTrue(SafetyThrows(() => s.Record("Lucky Potion", ev)), "Record after done throws")
        AssertEq(SafetyNew(SafetyLuckyCfg(3, 9, 9), p).Plan("Lucky Potion", 1, ev, 10).reason, "event_done", "persisted")
    } finally SafetyCleanup(d)
}

Test_Safety_DayRollover() {
    d := SafetyTempDir()
    try {
        p := d "\potion_usage.json"
        clock := SafetyClock("20261023")
        s := SafetyNew(SafetyLuckyCfg(1, 2, 99), p, clock)
        SafetyBegin(s, "Glitched|t1", "Glitched|t2", "Glitched|t3", "Glitched|t4")
        s.Record("Lucky Potion", "Glitched|t1")
        s.Record("Lucky Potion", "Glitched|t2")
        AssertEq(s.Plan("Lucky Potion", 1, "Glitched|t3", 10).reason, "cap_day", "day full")
        ; Restart same day: still full (per-day survives restart).
        s2 := SafetyNew(SafetyLuckyCfg(1, 2, 99), p, clock)
        SafetyBegin(s2, "Glitched|t5")
        AssertEq(s2.Plan("Lucky Potion", 1, "Glitched|t5", 10).reason, "cap_day", "restart same day")
        ; Next local day: fresh day cap.
        clock.day := "20261024"
        r := s.Plan("Lucky Potion", 1, "Glitched|t3", 10)
        AssertEq(r.reason, "ok", "next day ok")
        AssertEq(r.qty, 1, "next day qty")
        ; Bad clock value refuses.
        clock.day := "garbage"
        AssertEq(s.Plan("Lucky Potion", 1, "Glitched|t4", 10).reason, "bad_clock", "bad clock")
    } finally SafetyCleanup(d)
}

Test_Safety_CorruptUsage_RefusesAll() {
    d := SafetyTempDir()
    try {
        p := d "\potion_usage.json"
        for content in ["{not json", "", "[]", '{"version":1}', '{"version":1,"biome":{},"day":{"20261023":{"Lucky Potion":"x"}},"events":{}}'] {
            try FileDelete(p)
            FileAppend(content, p, "UTF-8-RAW")
            s := SafetyNew(SafetyLuckyCfg(5, 5, 5), p)
            AssertTrue(!s.BeginEvent("Glitched|t1"), "BeginEvent false on corrupt <" content ">")
            r := s.Plan("Lucky Potion", 1, "Glitched|t1", 5)
            AssertEq(r.qty, 0, "corrupt qty <" content ">")
            AssertEq(r.reason, "usage_unreadable", "corrupt reason <" content ">")
            threw := false      ; no closure inside loops (for-var capture gotcha)
            try s.Record("Lucky Potion", "Glitched|t1")
            catch
                threw := true
            AssertTrue(threw, "Record throws on corrupt <" content ">")
            ; File must be left untouched (never reset counters).
            AssertEq(FileRead(p, "UTF-8-RAW"), content, "file untouched <" content ">")
            AssertTrue(!FileExist(p ".probe"), "no probe on corrupt <" content ">")
        }
    } finally SafetyCleanup(d)
}

Test_Safety_ProbeFailure_HaltsAtLoad() {
    d := SafetyTempDir()
    try {
        p := d "\potion_usage.json"
        DirCreate(p ".probe")   ; probe path is a directory -> probe write fails
        s := SafetyNew(SafetyLuckyCfg(5, 5, 5), p)
        AssertTrue(!s.BeginEvent("Glitched|t1"), "BeginEvent false when probe failed")
        r := s.Plan("Lucky Potion", 1, "Glitched|t1", 5)
        AssertEq(r.qty, 0, "probe fail qty")
        AssertEq(r.reason, "usage_write_failed", "probe fail reason")
        AssertTrue(SafetyThrows(() => s.Record("Lucky Potion", "Glitched|t1")), "Record throws")
        AssertTrue(!FileExist(p), "no usage file written")
    } finally SafetyCleanup(d)
}

Test_Safety_WriteFailure_HaltsAll() {
    d := SafetyTempDir()
    try {
        ; Save fails during Record.
        p := d "\potion_usage.json"
        s := SafetyNew(SafetyLuckyCfg(5, 5, 5), p)
        SafetyBegin(s, "Glitched|t1", "Glitched|t2")
        DirCreate(p ".tmp")     ; tmp path is a directory -> write fails
        AssertTrue(SafetyThrows(() => s.Record("Lucky Potion", "Glitched|t1")), "Record throws on write failure")
        r := s.Plan("Lucky Potion", 1, "Glitched|t2", 5)
        AssertEq(r.qty, 0, "halted qty")
        AssertEq(r.reason, "usage_write_failed", "halted reason")
        ; Save fails during BeginEvent: false + halted, no file.
        p2 := d "\u2.json"
        s2 := SafetyNew(SafetyLuckyCfg(5, 5, 5), p2)
        DirCreate(p2 ".tmp")
        AssertTrue(!s2.BeginEvent("Glitched|t1"), "BeginEvent false on save failure")
        AssertEq(s2.Plan("Lucky Potion", 1, "Glitched|t1", 5).reason, "usage_write_failed", "BeginEvent failure halts")
        AssertTrue(!FileExist(p2), "no usage file written")
    } finally SafetyCleanup(d)
}

Test_Safety_FileMoveFailure_NoTmpLeft() {
    d := SafetyTempDir()
    try {
        ; Direct: target path is a directory -> FileMove fails, tmp removed.
        target := d "\isdir.json"
        DirCreate(target)
        AssertTrue(SafetyThrows(() => PotionSafety._AtomicWrite(target, "x")), "AtomicWrite throws")
        AssertTrue(!FileExist(target ".tmp"), "no tmp after failed FileMove")
        AssertTrue(InStr(FileExist(target), "D"), "target dir untouched")
        ; Through the instance: target becomes a directory after load.
        p := d "\potion_usage.json"
        s := SafetyNew(SafetyLuckyCfg(5, 5, 5), p)
        DirCreate(p)
        AssertTrue(!s.BeginEvent("Glitched|t1"), "BeginEvent false")
        AssertTrue(!FileExist(p ".tmp"), "instance: no tmp after failed FileMove")
        AssertEq(s.Plan("Lucky Potion", 1, "Glitched|t1", 5).reason, "usage_write_failed", "instance halted")
    } finally SafetyCleanup(d)
}

Test_Safety_ReasonPrecedence() {
    d := SafetyTempDir()
    try {
        p := d "\potion_usage.json"
        cfg := SafetyCfg(SafetyEntry("Zeus Potion", 1, 0, 0, 0), SafetyEntry("Lucky Potion", 0, 1, 1, 1))
        s := SafetyNew(cfg, p)
        ; locked beats caps / unreadable / bad qty / bad event / not begun.
        AssertEq(s.Plan("Zeus Potion", 0, "Glitched|t1", "").reason, "locked", "locked first")
        AssertEq(s.Plan("Zeus Potion", 1, "", 5).reason, "locked", "locked before bad_event")
        ; event_not_begun beats bad_qty / unreadable.
        AssertEq(s.Plan("Lucky Potion", 0, "Glitched|t1", "").reason, "event_not_begun", "not begun before qty")
        SafetyBegin(s, "Glitched|t1", "Glitched|t2")
        s.Record("Lucky Potion", "Glitched|t1")
        ; event_done beats unreadable and caps.
        s2 := SafetyNew(cfg, p)
        AssertEq(s2.Plan("Lucky Potion", 1, "Glitched|t1", "").reason, "event_done", "event_done before unreadable")
        ; unreadable beats caps (count is checked before caps).
        AssertEq(s.Plan("Lucky Potion", 1, "Glitched|t2", "").reason, "unreadable", "unreadable before caps")
        ; cap_biome before cap_day before cap_run.
        AssertEq(s.Plan("Lucky Potion", 1, "Glitched|t1", 5).reason, "cap_biome", "biome first")
        AssertEq(s.Plan("Lucky Potion", 1, "Glitched|t2", 5).reason, "cap_day", "day before run")
        ; usage_unreadable beats everything, even unknown.
        FileDelete(p)
        FileAppend("garbage", p, "UTF-8-RAW")
        s3 := SafetyNew(cfg, p)
        AssertEq(s3.Plan("Nope", 1, "Glitched|t9", 5).reason, "usage_unreadable", "usage first")
    } finally SafetyCleanup(d)
}

Test_Safety_NameMustMatchExactly() {
    d := SafetyTempDir()
    try {
        s := SafetyNew(SafetyLuckyCfg(), d "\potion_usage.json")
        ; (a plain "Heavenly Potion" never matches: never_use_prefix, see
        ; Test_Safety_NeverUsePrefixRefused)
        AssertTrue(s.NameMatches("Godly Potion", "Godly Potion"), "exact")
        AssertTrue(s.NameMatches("  godly   POTION `t", "Godly Potion"), "trim/case/space")
        AssertTrue(s.NameMatches("Godly`nPotion", "Godly Potion"), "newline collapses")
        AssertTrue(!s.NameMatches("Heavenly Potion II", "Heavenly Potion"), "II must not match")
        AssertTrue(!s.NameMatches("Heavenly Potion", "Heavenly Potion II"), "reverse")
        AssertTrue(!s.NameMatches("Heavenly", "Heavenly Potion"), "prefix")
        AssertTrue(!s.NameMatches("HeavenlyPotion", "Heavenly Potion"), "missing space")
        ; "Potlon" is the I/l OCR confusion (canonical-equal by design, 12b);
        ; a letter outside every class is still a mismatch
        AssertTrue(!s.NameMatches("Heavenly Pution", "Heavenly Potion"), "no fuzzy")
        AssertTrue(!s.NameMatches("Heavenly Potio", "Heavenly Potion"), "no dropped char")
        AssertTrue(!s.NameMatches("", ""), "empty never matches")
        AssertTrue(!s.NameMatches("   ", "   "), "blank never matches")
        AssertTrue(!s.NameMatches(["x"], "x"), "object never matches")
    } finally SafetyCleanup(d)
}

Test_Safety_ConsumedMoreThanOne_Abort() {
    d := SafetyTempDir()
    try {
        s := SafetyNew(SafetyLuckyCfg(), d "\potion_usage.json")
        AssertTrue(s.VerifyConsumed(5, 4), "exactly one")
        AssertTrue(s.VerifyConsumed("5", " 4 "), "OCR strings")
        AssertTrue(!s.VerifyConsumed(5, 3), "two consumed")
        AssertTrue(!s.VerifyConsumed(5, 5), "none consumed")
        AssertTrue(!s.VerifyConsumed(5, 6), "went up")
        AssertTrue(!s.VerifyConsumed(5, ""), "after unreadable")
        AssertTrue(!s.VerifyConsumed("", 4), "before unreadable")
        AssertTrue(!s.VerifyConsumed("5", "4x"), "garbage after")
        AssertTrue(s.VerifyConsumed(1, 0), "1 -> 0 ok")
        AssertTrue(!s.VerifyConsumed(5.0, 4.0), "floats rejected")
    } finally SafetyCleanup(d)
}


Test_Safety_NeverUseList() {
    d := SafetyTempDir()
    try {
        ; even configured, unlocked and with a desc: refused
        cfg := Map("potions", [
            Map("id", "Heavenly Potion I", "name", "Heavenly Potion I", "desc", "Heavenly I text", "locked", 0, "perBiome", 1, "perDay", 3, "perRun", 3),
            Map("id", "Sizemax Potion", "name", "Sizemax Potion", "desc", "Bigger", "locked", 0, "perBiome", 1, "perDay", 3, "perRun", 3),
            Map("id", "Heavenly Potion", "name", "Heavenly Potion", "desc", "[Heavenly]", "locked", 0, "perBiome", 1, "perDay", 3, "perRun", 3)])
        s := SafetyNew(cfg, d "\potion_usage.json")
        SafetyBegin(s, "Glitched|t1")
        AssertEq(s.Plan("Heavenly Potion I", 1, "Glitched|t1", 5).reason, "never_use", "Heavenly Potion I refused")
        AssertEq(s.Plan("Sizemax Potion", 1, "Glitched|t1", 5).reason, "never_use", "Sizemax refused")
        AssertEq(s.Plan("Heavenly Potion", 1, "Glitched|t1", 5).reason, "never_use_prefix", "plain Heavenly Potion: its tile may be Heavenly Potion I minus the I")
        threw := false
        try s.Record("Heavenly Potion I", "Glitched|t1")
        catch
            threw := true
        AssertTrue(threw, "recording a never-use potion throws")
        ; a never-use tile matches nothing, OCR confusions included
        AssertTrue(!s.NameMatches("Heavenly Potion I", "Heavenly Potion I"), "never-use tile never matches")
        AssertTrue(!s.NameMatches("Heovenly Potion Il", "Heavenly Potion II"), "confusable never-use tile never matches")
        AssertTrue(!s.NameMatches("Sizemin`nPotion", "Sizemin Potion"), "Sizemin tile never matches")
        AssertTrue(!s.NameMatches("Heovenly Potion", "Heavenly Potion"), "plain Heavenly no longer matches (never_use_prefix)")
        AssertTrue(PotionSafety.IsNeverUse("heavenly potion ii"), "IsNeverUse is canonical")
        AssertTrue(!PotionSafety.IsNeverUse(["x"]), "non-string is not never-use")
    } finally SafetyCleanup(d)
}

; 2026-10-27 review: the lone trailing "I" of the Heavenly Potion I tile is
; often lost by OCR ("Heavenly`nPotion"), and the Heavenly family shares
; "[Heavenly]": a configured "Heavenly Potion" picked and used Heavenly
; Potion I. A word prefix of a never-use name is refused unless its desc is
; proven absent from the recorded never-use descriptions.
Test_Safety_NeverUsePrefixRefused() {
    d := SafetyTempDir()
    saved := PotionSafety.NeverUseDesc
    try {
        PotionSafety.NeverUseDesc := Map()
        hp := (desc) => Map("potions", [Map("id", "Heavenly Potion", "name", "Heavenly Potion", "desc", desc
            , "locked", 0, "perBiome", 1, "perDay", 3, "perRun", 3)
            , SafetyEntry("Godly Potion", 0, 1, 3, 3)])
        s := SafetyNew(hp("[Heavenly]"), d "\u1.json")
        SafetyBegin(s, "Glitched|t1")
        AssertEq(s.Plan("Heavenly Potion", 1, "Glitched|t1", 5).reason, "never_use_prefix", "prefix of Heavenly Potion I refused")
        AssertEq(s.Plan("Godly Potion", 1, "Glitched|t1", 5).reason, "ok", "other potions unaffected")
        AssertTrue(!s.NameMatches("Heavenly`nPotion", "Heavenly Potion"), "its tile never matches")
        AssertTrue(s.NameMatches("Godly`nPotion", "Godly Potion"), "a name that is no prefix still matches")
        AssertTrue(SafetyThrows(() => s.Record("Heavenly Potion", "Glitched|t1")), "Record refuses it too (and halts)")
        ; unconfigured prefix name: no match either
        s0 := SafetyNew(SafetyLuckyCfg(), d "\u0.json")
        AssertTrue(!s0.NameMatches("Heavenly Potion", "Heavenly Potion"), "unconfigured prefix name")
        AssertTrue(!s0.NameMatches("Sizemax", "Sizemax"), "word prefix of Sizemax Potion")
        AssertTrue(PotionSafety.NeverUsePrefixOk("Heavenly Potions", ""), "not a WORD prefix")
        ; only one of the two never-use descriptions recorded: still refused
        PotionSafety.NeverUseDesc := Map("Heavenly Potion I", "Gives you [Heavenly]`n[Heavenly]: +100,000 Luck")
        s2 := SafetyNew(hp("+150,000 Luck"), d "\u2.json")
        SafetyBegin(s2, "Glitched|t2")
        AssertEq(s2.Plan("Heavenly Potion", 1, "Glitched|t2", 5).reason, "never_use_prefix", "HP II not recorded")
        ; both recorded and the desc occurs in neither: allowed, tile matches
        PotionSafety.NeverUseDesc["Heavenly Potion II"] := "Gives you [Heavenly]`n[Heavenly]: +125,000 Luck"
        s3 := SafetyNew(hp("+150,000 Luck"), d "\u3.json")
        SafetyBegin(s3, "Glitched|t3")
        AssertEq(s3.Plan("Heavenly Potion", 1, "Glitched|t3", 5).reason, "ok", "desc rules both out")
        AssertTrue(s3.NameMatches("Heavenly`nPotion", "Heavenly Potion"), "then the tile may match")
        ; a desc the never-use potions share ("[Heavenly]") rules nothing out
        s4 := SafetyNew(hp("[Heavenly]"), d "\u4.json")
        SafetyBegin(s4, "Glitched|t4")
        AssertEq(s4.Plan("Heavenly Potion", 1, "Glitched|t4", 5).reason, "never_use_prefix", "shared desc refused")
    } finally {
        PotionSafety.NeverUseDesc := saved
        SafetyCleanup(d)
    }
}

Test_Safety_StatusEventOpenUsedInEvent() {
    d := SafetyTempDir()
    try {
        s := SafetyNew(SafetyLuckyCfg(2), d "\potion_usage.json")
        AssertEq(s.Status(), "", "healthy")
        AssertTrue(!s.IsEventOpen("Glitched|t1"), "not begun")
        SafetyBegin(s, "Glitched|t1")
        AssertTrue(s.IsEventOpen("glitched | t1"), "begun (normalised key)")
        AssertEq(s.UsedInEvent("Lucky Potion", "Glitched|t1"), 0, "nothing used")
        s.Record("Lucky Potion", "Glitched|t1")
        AssertEq(s.UsedInEvent("Lucky Potion", "GLITCHED|t1"), 1, "one used")
        s.MarkEventDone("Glitched|t1")
        AssertTrue(!s.IsEventOpen("Glitched|t1"), "closed")
        p := d "\bad.json"
        FileAppend("garbage", p, "UTF-8-RAW")
        AssertEq(SafetyNew(SafetyLuckyCfg(), p).Status(), "usage_unreadable", "corrupt usage file")
        s._halt := "usage_write_failed"
        AssertEq(s.Status(), "usage_write_failed", "halted")
    } finally SafetyCleanup(d)
}
