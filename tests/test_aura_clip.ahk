#Requires AutoHotkey v2.0
; Tests for aura clips by rarity (lib\Auras.ahk + BiomeEvents aura path +
; Clip hotkey vs capture key). Offline only: fake clip, fake webhook, scratch
; Config dirs under A_Temp. Never sends keys, never touches Roblox.
#Include ..\lib\Json.ahk
#Include ..\lib\Config.ahk
#Include ..\lib\Auras.ahk
#Include ..\lib\Clip.ahk
#Include ..\lib\BiomeEvents.ahk
#Include ..\lib\Calibrate.ahk
#Include ..\lib\ui\Dashboard.ahk

; ---- helpers (names must not start with Test_) -----------------------------

AcRepoData() => RegExReplace(A_LineFile, "\\tests\\[^\\]+$", "") "\data"

AcTmpDir() {
    d := A_Temp "\vesper_auraclip_" A_TickCount "_" Random(100000, 999999)
    DirCreate(d)
    return d
}

; Small aura table injected into a scratch Config (no file needed).
AcAuras() {
    mk := (n, r, c) => Map("name", n, "rarity", r, "category", c)
    list := [
        mk("Common", 2, "Basic"),
        mk("Starscourge", 10000000, "Exalted"),
        mk("Quartz : Rose", 97500000, "Exalted"),
        mk("Starscourge : Radiant", 100000000, "Glorious"),
        mk("Gargantua", 430000000, "Glorious"),
        mk("Equinox", 2500000000, "Transcendent"),
        mk("Memory", 100, "Challenged"),
        mk("Illusionary", 10000000, "Challenged+"),
        mk("True Jade", 0, "Challenged")
    ]
    a := mk("Abyssal Hunter", 400000000, "Glorious")
    a["aliases"] := ["Abyssal"]
    list.Push(a)
    return Map("auras", list)
}

class AcRig {
    __New() {
        Auras.QuietUntil := 0                      ; no aura swap test window left over
        this.dir := AcTmpDir()
        this.cfg := Config.Load(this.dir)
        this.cfg.SetData("auras", AcAuras())
        this.cfg.Set("Medal.onRareAura", 1)
        this.clips := [], this.logs := []
        this.clip := {Trigger: (self, r) => this.clips.Push(r)}
        this.state := {biome: "", rareActive: false, rareTs: ""}
        this.be := BiomeEvents(Map("cfg", this.cfg, "state", this.state,
            "log", (t) => this.logs.Push(t), "clip", this.clip,
            "shotFn", () => "", "soundFn", (s) => 0))
    }
    Aura(name, live := 1, test := 0) {
        ev := Map("type", "aura", "name", name, "ts", test ? "TEST-1" : "2026-10-25T10:00:00.000Z", "live", live)
        if test
            ev["test"] := 1
        this.be.Handle(ev)
    }
    Done() {
        try DirDelete(this.dir, true)
    }
}

AcCount(arr, needle) {
    n := 0
    for v in arr
        if InStr(v, needle)
            n++
    return n
}

; ---- data file ---------------------------------------------------------------

Test_AuraClip_DataFileParses() {
    v := Json.Parse(FileRead(AcRepoData() "\auras.json", "UTF-8"))
    AssertTrue(v is Map && v.Has("auras") && v["auras"] is Array, "auras.json has an auras array")
    AssertTrue(v.Has("_source"), "auras.json has _source")
    list := v["auras"]
    AssertTrue(list.Length >= 200, "many auras sourced (" list.Length ")")
    seen := Map()
    cats := Map()
    for e in list {
        AssertTrue(e is Map && e.Has("name") && e.Has("rarity") && e.Has("category"), "entry has name/rarity/category")
        AssertTrue(Trim(e["name"]) != "", "non-empty name")
        AssertTrue(e["rarity"] is Integer && e["rarity"] >= 0, "integer rarity for " e["name"])
        AssertTrue(Trim(e["category"]) != "", "category for " e["name"])
        k := Auras.Key(e["name"])
        AssertTrue(!seen.Has(k), "unique name " e["name"])
        seen[k] := 1
        cats[e["category"]] := 1
    }
    AssertTrue(cats.Has("Challenged") && cats.Has("Challenged+"), "Challenged and Challenged+ present")
    cfg := { Data: (self, n) => v }
    e := Auras.Find(cfg, "Gargantua")
    AssertTrue(IsObject(e) && e["rarity"] >= 100000000, "Gargantua is in the file and >= 100M")
}

Test_AuraClip_ConfigDefaultsEmpty() {
    dir := AcTmpDir()
    try {
        cfg := Config.Load(dir)                ; no data\auras.json there
        AssertEq(cfg.DataStatus("auras"), "missing", "missing file")
        AssertEq(Auras.List(cfg).Length, 0, "fallback is an empty list")
        AssertEq(Auras.Find(cfg, "Gargantua"), "", "nothing known without the file")
        AssertEq(cfg.Get("Medal.auraMinRarity", ""), "100000000", "ini default threshold 100M")
        AssertEq(cfg.Get("Medal.auraAlwaysCategories", ""), "Challenged,Challenged+", "ini default always-clip classes")
        AssertEq(cfg.Get("Calibrate.captureKey", ""), "F4", "ini default capture key F4")
    } finally
        try DirDelete(dir, true)
}

; ---- lookup / parsing -------------------------------------------------------

Test_AuraClip_FindNormalisesNames() {
    r := AcRig()
    try {
        AssertEq(Auras.Find(r.cfg, "gargantua")["name"], "Gargantua", "case-insensitive")
        AssertEq(Auras.Find(r.cfg, '  "Gargantua"  ')["name"], "Gargantua", "quotes and spaces ignored")
        AssertEq(Auras.Find(r.cfg, "Quartz: ROSE")["name"], "Quartz : Rose", "spacing around ':' ignored")
        AssertEq(Auras.Find(r.cfg, "abyssal")["name"], "Abyssal Hunter", "alias")
        AssertEq(Auras.Find(r.cfg, "Nope"), "", "unknown")
        AssertEq(Auras.Find(r.cfg, ""), "", "empty")
    } finally
        r.Done()
}

Test_AuraClip_ParseRarity() {
    for pair in [["100m", 100000000], ["100M", 100000000], ["1,000,000,000", 1000000000], ["1b", 1000000000]
        , ["1.5b", 1500000000], ["100,000,000", 100000000], ["250k", 250000], ["1 in 100m", 100000000]
        , ["1/2,500,000", 2500000], [" 42 ", 42], ["100 million", 100000000], ["2 billion", 2000000000]
        , ["0", 0], [100000000, 100000000]]
        AssertEq(Auras.ParseRarity(pair[1]), pair[2], "parse <" pair[1] ">")
    for bad in ["", "abc", "1.5", "-5", "10x", "1,2,3m.4", "99999999999999999999"]
        AssertEq(Auras.ParseRarity(bad), "", "invalid <" bad ">")
    AssertEq(Auras.Format(100000000), "100,000,000", "format with commas")
    AssertEq(Auras.Format(999), "999", "small number")
    AssertEq(Auras.Format(2644600640), "2,644,600,640", "big number")
}

Test_AuraClip_MinRarityFromConfig() {
    r := AcRig()
    try {
        AssertEq(Auras.MinRarity(r.cfg), 100000000, "default 100M")
        r.cfg.Set("Medal.auraMinRarity", "1b")
        AssertEq(Auras.MinRarity(r.cfg), 1000000000, "suffix in ini accepted")
        r.cfg.Set("Medal.auraMinRarity", "junk")
        AssertEq(Auras.MinRarity(r.cfg), 100000000, "junk -> default")
    } finally
        r.Done()
}

; ---- decisions through BiomeEvents ------------------------------------------

Test_AuraClip_ThresholdClips() {
    r := AcRig()
    try {
        r.Aura("Gargantua")
        AssertEq(r.clips.Length, 1, "430M >= 100M clips")
        AssertEq(r.clips[1], "aura:Gargantua", "reason")
        r.Aura("Starscourge : Radiant")
        AssertEq(r.clips.Length, 2, "exactly 100M clips (>=)")
        r.Aura("Quartz : Rose")
        AssertEq(r.clips.Length, 2, "97.5M below threshold: no clip")
        r.Aura("Common")
        AssertEq(r.clips.Length, 2, "common: no clip")
        r.cfg.Set("Medal.auraMinRarity", "1b")
        r.Aura("Gargantua")
        AssertEq(r.clips.Length, 2, "raised threshold: 430M no longer clips")
        r.Aura("Equinox")
        AssertEq(r.clips.Length, 3, "2.5B still clips")
        d := Auras.Decide(r.cfg, "Equinox")
        AssertTrue(InStr(d["why"], "2,500,000,000") && InStr(d["why"], "1,000,000,000"), "why names both rarities")
    } finally
        r.Done()
}

Test_AuraClip_ChallengedAlwaysClips() {
    r := AcRig()
    try {
        r.Aura("Memory")
        AssertEq(r.clips.Length, 1, "Challenged 1 in 100 clips")
        r.Aura("Illusionary")
        AssertEq(r.clips.Length, 2, "Challenged+ below threshold clips")
        r.Aura("True Jade")
        AssertEq(r.clips.Length, 3, "Challenged with unpublished odds clips")
        AssertTrue(InStr(Auras.Decide(r.cfg, "Illusionary")["why"], "Challenged+"), "why names the class")
        r.cfg.Set("Medal.auraAlwaysCategories", "Challenged+")
        r.Aura("Memory")
        AssertEq(r.clips.Length, 3, "class list honoured: plain Challenged no longer listed")
        r.Aura("Illusionary")
        AssertEq(r.clips.Length, 4, "Challenged+ still listed")
    } finally
        r.Done()
}

Test_AuraClip_ExplicitListClips() {
    r := AcRig()
    try {
        r.cfg.Set("Medal.auras", "Common, Some Unlisted Aura")
        r.Aura("common")
        AssertEq(r.clips.Length, 1, "listed common aura clips")
        r.Aura("Some Unlisted Aura")
        AssertEq(r.clips.Length, 2, "listed aura clips even if not in auras.json")
        AssertEq(AcCount(r.logs, "unknown aura"), 0, "listed unknown aura not reported")
        AssertTrue(InStr(Auras.Decide(r.cfg, "Common")["why"], "[Medal] auras"), "why = listed")
    } finally
        r.Done()
}

Test_AuraClip_UnknownLoggedOnce() {
    r := AcRig()
    try {
        r.Aura("Brand New Aura")
        r.Aura("Brand New Aura")
        r.Aura("brand new aura")
        AssertEq(r.clips.Length, 0, "unknown aura: no clip")
        AssertEq(AcCount(r.logs, "unknown aura"), 1, "logged once")
        AssertTrue(AcCount(r.logs, "data/auras.json") = 1, "log says where to add it")
        r.Aura("Other New Aura")
        AssertEq(AcCount(r.logs, "unknown aura"), 2, "another name is logged too")
    } finally
        r.Done()
}

Test_AuraClip_NeverWhenNotLiveOrOff() {
    r := AcRig()
    try {
        r.Aura("Gargantua", false)
        r.Aura("Memory", 0)
        AssertEq(r.clips.Length, 0, "live=false never clips")
        r.Aura("", 1)
        AssertEq(r.clips.Length, 0, "empty aura never clips")
        r.cfg.Set("Medal.onRareAura", 0)
        r.Aura("Gargantua")
        AssertEq(r.clips.Length, 0, "onRareAura=0 -> no clip")
        r.cfg.Set("Medal.onRareAura", 1)
        r.cfg.Set("General.dryRun", 0)
        r.Aura("Gargantua", 1, 1)
        AssertEq(r.clips.Length, 0, "TEST aura outside dry run: no clip")
        r.cfg.Set("General.dryRun", 1)
        r.Aura("Gargantua", 1, 1)
        AssertEq(r.clips.Length, 1, "TEST aura in dry run clips (test path)")
    } finally
        r.Done()
}

; ---- clips webhook text ----------------------------------------------------

class AcWh {
    __New() {
        this.sent := []
    }
    Send(ev, title, desc, color, opts := "") => this.sent.Push({event: ev, title: title, desc: desc})
}

Test_AuraClip_WebhookStatesRarityAndWhy() {
    dir := AcTmpDir()
    wh := AcWh()
    timers := []
    try {
        cfg := Config.Load(dir)
        cfg.SetData("auras", AcAuras())
        cfg.Set("Medal.enabled", 1)
        cfg.Set("Medal.clipHotkey", "F8")
        io := {Down: (s, k) => 0, Up: (s, k) => 0, Wait: (s, ms, ctx := "") => true}
        Clip.Setup(cfg, wh, (t) => 0, Map("procFn", (n) => 1, "clockFn", () => 1000
            , "timerFn", (fn, ms) => timers.Push(fn), "io", io, "stopFn", () => false))
        AssertEq(Clip.Trigger("aura:Gargantua"), "scheduled", "scheduled")
        for fn in timers
            fn.Call()
        AssertEq(wh.sent.Length, 1, "clips webhook sent")
        d := wh.sent[1].desc
        AssertEq(wh.sent[1].event, "clips", "clips event")
        AssertTrue(InStr(d, "Gargantua"), "names the aura")
        AssertTrue(InStr(d, "1 in 430,000,000"), "states 1-in-N rarity")
        AssertTrue(InStr(d, "Glorious"), "states the class")
        AssertTrue(InStr(d, "100,000,000"), "says why (threshold)")
    } finally {
        Clip.Reset()
        try DirDelete(dir, true)
    }
}

; ---- F6 free for Medal -------------------------------------------------------

Test_AuraClip_F6FreeForMedal() {
    AssertEq(Calibrate.DefaultCaptureKey, "F4", "capture key default F4 (F9 = Roblox dev console)")
    AssertEq(Clip.DefaultCaptureKey, Calibrate.DefaultCaptureKey, "Clip uses the same default")
    dir := AcTmpDir()
    try {
        cfg := Config.Load(dir)
        AssertEq(Clip.HotkeyProblem("F6", cfg), "", "F6 accepted as Medal hotkey with default capture key")
        AssertEq(Clip.HotkeyProblem("F6", ""), "", "F6 accepted with no cfg")
        AssertTrue(InStr(Clip.HotkeyProblem("F4", cfg), "capture key"), "F4 (capture default) refused")
        cfg.Set("Calibrate.captureKey", "F6")
        AssertTrue(InStr(Clip.HotkeyProblem("F6", cfg), "capture key"), "F6 refused when captureKey=F6")
        AssertEq(Clip.HotkeyProblem("F4", cfg), "", "F4 free once capture key is F6")
        cfg.Set("Calibrate.captureKey", "")
        AssertTrue(InStr(Clip.HotkeyProblem("F4", cfg), "capture key"), "blank capture key = default F4")
        AssertTrue(InStr(Clip.HotkeyProblem("F7", cfg), "recorder"), "F7 still the recorder key")
    } finally
        try DirDelete(dir, true)
}

; ---- Dashboard Settings > Medal ----------------------------------------------
; Builds the real Dashboard hidden (never shown, no focus change).

AcDashClose(g) {
    if !IsObject(g)
        return
    try Theme.Forget(g._gui)
    try g._gui.Destroy()
}

Test_AuraClip_DashboardMedalFields() {
    dir := AcTmpDir()
    d := "", d2 := ""
    try {
        cfg := Config.Load(dir)
        d := Dashboard(cfg)
        AssertEq(d.Ctrl("Medal.auraMinRarity").Value, "100,000,000", "threshold shown with commas")
        AssertEq(d.Ctrl("Medal.auraAlwaysCategories").Value, "Challenged,Challenged+", "default classes shown")
        AssertEq(d.Ctrl("Medal.auras").Value, "", "explicit list kept (empty)")

        d.Ctrl("Medal.auraMinRarity").Value := "1b"
        d.Ctrl("Medal.auraAlwaysCategories").Value := "Challenged+, Transcendent"
        d.Ctrl("Medal.auras").Value := "Gargantua"
        AssertTrue(d.SavePage("Clips"), "clips saved")
        AssertEq(cfg.Get("Medal.auraMinRarity", ""), "1000000000", "suffix parsed to an integer")
        AssertEq(d.Ctrl("Medal.auraMinRarity").Value, "1,000,000,000", "field re-shown with commas")

        d.Ctrl("Medal.auraMinRarity").Value := "1,000,000,000"
        AssertTrue(d.SavePage("Clips"), "commas accepted")
        AssertEq(cfg.Get("Medal.auraMinRarity", ""), "1000000000", "commas parsed")

        d.Ctrl("Medal.auraMinRarity").Value := "lots"
        d.Ctrl("Medal.delaySec").Value := "44"
        AssertEq(d.SavePage("Clips"), false, "unparsable threshold refused")
        AssertEq(cfg.Get("Medal.auraMinRarity", ""), "1000000000", "refused value never reaches cfg")
        AssertTrue(cfg.Get("Medal.delaySec", 3) != 44, "nothing else saved either")

        d.Ctrl("Medal.auraMinRarity").Value := "100m"
        d.Ctrl("Medal.delaySec").Value := "3"
        AssertTrue(d.SavePage("Clips"), "100m accepted")

        c2 := Config.Load(dir)
        AssertEq(c2.Get("Medal.auraMinRarity", ""), "100000000", "threshold persisted")
        AssertEq(c2.Get("Medal.auraAlwaysCategories", ""), "Challenged+, Transcendent", "classes persisted")
        AssertEq(c2.Get("Medal.auras", ""), "Gargantua", "explicit list persisted")
        d2 := Dashboard(c2)
        AssertEq(d2.Ctrl("Medal.auraMinRarity").Value, "100,000,000", "reloaded with commas")
        AssertEq(d2.Ctrl("Medal.auraAlwaysCategories").Value, "Challenged+, Transcendent", "reloaded classes")
    } finally {
        AcDashClose(d)
        AcDashClose(d2)
        try DirDelete(dir, true)
    }
}

; Medal controls (Alerts > Clips tab) sit inside the "Medal clips" panel
; (below its title), never overlap each other or a "?" help tip.
Test_AuraClip_DashboardMedalLayout() {
    dir := AcTmpDir()
    d := ""
    try {
        cfg := Config.Load(dir)
        d := Dashboard(cfg)
        pn := d.Ctrl("panel:Clips:Medal clips")
        AssertTrue(IsObject(pn), "Clips has a Medal clips panel")
        px := 0, py := 0, pw := 0, ph := 0
        pn.GetPos(&px, &py, &pw, &ph)
        tips := []
        for c in d._pages[Dashboard.PageIndex("Clips")].ctrls {
            if (Theme.HelpText(c) != "") {
                tx := 0, ty := 0, tw := 0, th := 0
                c.GetPos(&tx, &ty, &tw, &th)
                tips.Push({k: "help tip", x: tx, y: ty, w: tw, h: th})
            }
        }
        AssertTrue(tips.Length >= 1, "Clips help lives in a tip")
        keys := ["Medal.enabled", "Medal.clipHotkey", "Medal.delaySec", "Medal.cooldownSec", "Medal.onRareBiome"
            , "Medal.onRareAura", "Medal.auraMinRarity", "Medal.auraAlwaysCategories", "Medal.auras"]
        rects := []
        for k in keys {
            c := d.Ctrl(k)
            parts := (c is ThemeCheck) ? [c._box, c._lbl] : [c]
            x := 0, y := 0, w := 0, h := 0
            parts[1].GetPos(&x, &y, &w, &h)
            if (parts.Length > 1 && IsObject(parts[2])) {
                x2 := 0, y2 := 0, w2 := 0, h2 := 0
                parts[2].GetPos(&x2, &y2, &w2, &h2)
                r := Max(x + w, x2 + w2), b := Max(y + h, y2 + h2)
                x := Min(x, x2), y := Min(y, y2), w := r - x, h := b - y
            }
            rects.Push({k: k, x: x, y: y, w: w, h: h})
            AssertTrue(x >= px + 1 && x + w <= px + pw - 1 && y >= py + 28 && y + h <= py + ph - 1
                , k " inside the Medal clips panel, below its title (" x "," y " " w "x" h ")")
            AssertTrue(x + w <= 1020, k " fits the window width")
        }
        for r in rects
            for t in tips
                AssertTrue(r.x + r.w <= t.x || t.x + t.w <= r.x || r.y + r.h <= t.y || t.y + t.h <= r.y
                    , r.k " does not overlap a help tip")
        for i, a in rects
            for j, b in rects
                if (j > i)
                    AssertTrue(a.x + a.w <= b.x || b.x + b.w <= a.x || a.y + a.h <= b.y || b.y + b.h <= a.y
                        , a.k " does not overlap " b.k)
    } finally {
        AcDashClose(d)
        try DirDelete(dir, true)
    }
}

Test_AuraClip_JoinIsNoRoll() {
    ; 2026-10-31: after a rejoin the fresh client's first "Equipped" line (your
    ; own Equinox) counted as a roll: one Medal clip per rejoin overnight
    try {
        Auras.QuietUntil := 0
        t := AppTestMake()
        t.app.RouteEvent(AppTestEv("join", "private", "2026-10-31T14:49:30Z", false))
        AssertEq(Auras.QuietUntil, 0, "the startup join (not live): no quiet window")
        t.app.RouteEvent(AppTestEv("join", "private", "2026-10-31T14:49:30Z", true))
        AssertTrue(Auras.QuietUntil >= A_TickCount + Auras.JoinQuietMs - 1000, "a live join: auras quiet for JoinQuietMs")
        r := AcRig()                                ; resets QuietUntil
        Auras.QuietUntil := A_TickCount + Auras.JoinQuietMs
        r.Aura("Equinox")
        AssertEq(r.clips.Length, 0, "the aura seen right after the join: no clip")
        r.Done()
    } finally {
        Auras.QuietUntil := 0
    }
}

Test_AuraClip_MacroSwapIsNoRoll() {
    r := AcRig()
    try {
        Auras.QuietUntil := A_TickCount + 60000      ; the hunt just put Equinox on
        r.Aura("Equinox")
        AssertEq(r.clips.Length, 0, "the macro's own swap: no clip")
        AssertEq(AcCount(r.logs, "put on by the macro"), 1, "logged why")
        Auras.QuietUntil := 0
        r.Aura("Equinox")
        AssertEq(r.clips.Length, 1, "a real roll still clips")
    } finally {
        Auras.QuietUntil := 0
        r.Done()
    }
}

; ---- had auras (equipped before: no clip) -----------------------------------

AcHadBe(r, hadFile, logDir := "") => BiomeEvents(Map("cfg", r.cfg, "state", r.state,
    "log", (t) => r.logs.Push(t), "clip", r.clip, "shotFn", () => "", "soundFn", (s) => 0,
    "hadFile", hadFile, "hadLogDir", logDir))

AcEquipLine(name) => 'x,1 [FLog::Output] [BloxstrapRPC] {"command":"SetRichPresence","data":{"state":"Equipped \"' name '\""}}`n'

Test_AuraClip_EquippedInText() {
    text := AcEquipLine("Blossom_Frozen")
        . 'x [BloxstrapRPC] {"data":{"state":"Equipped _None_"}}`n'
        . 'y {"state":"Equipped \":Flushed:_Pumpkinity\""} {"state":"Equipped \"EQUINOX\""}'
    n := Auras.EquippedInText(text)
    AssertEq(n.Length, 3, "three equips, _None_ skipped")
    AssertEq(n[1], "Blossom_Frozen", "first name")
    AssertEq(n[2], ":Flushed:_Pumpkinity", "colons kept")
    AssertEq(n[3], "EQUINOX", "two on one line")
    AssertEq(Auras.EquippedInText("no auras here").Length, 0, "none")
}

Test_AuraClip_NewRareClipsOnceThenRemembered() {
    r := AcRig()
    try {
        f := r.dir "\auras_had.txt"
        r.be := AcHadBe(r, f)
        AssertTrue(FileExist(f) != "", "had file written on first use")
        r.Aura("Equinox")
        AssertEq(r.clips.Length, 1, "a new rare aura clips")
        AssertTrue(InStr(FileRead(f, "UTF-8"), "equinox`n") > 0, "remembered in the file")
        r.Aura("EQUINOX")
        AssertEq(r.clips.Length, 1, "equipped again from storage: no clip")
        AssertEq(AcCount(r.logs, "equipped before (no clip)"), 1, "logged why")
        r.Aura("Common")
        AssertEq(r.clips.Length, 1, "a common aura never clips")
        AssertTrue(InStr(FileRead(f, "UTF-8"), "common`n") > 0, "a no-clip aura is remembered too")
    } finally {
        r.Done()
    }
}

Test_AuraClip_SeededFromLogsNoClip() {
    r := AcRig()
    try {
        logs := r.dir "\logs"
        DirCreate(logs)
        FileAppend(AcEquipLine("Gargantua"), logs "\0.0.1_20261101_Player_1.log", "UTF-8-RAW")
        FileAppend(AcEquipLine("Abyssal_Hunter"), logs "\0.0.1_20261102_Player_2.log", "UTF-8-RAW")
        f := r.dir "\auras_had.txt"
        r.be := AcHadBe(r, f, logs)
        r.Aura("Gargantua")
        r.Aura("Abyssal Hunter")
        AssertEq(r.clips.Length, 0, "auras seen in the Roblox logs: no clip")
        r.Aura("Equinox")
        AssertEq(r.clips.Length, 1, "a new one still clips")
        ; the file exists now: a later instance does not seed again
        FileAppend(AcEquipLine("Starscourge : Radiant"), logs "\0.0.1_20261102_Player_3.log", "UTF-8-RAW")
        r.be := AcHadBe(r, f, logs)
        r.Aura("Starscourge : Radiant")
        AssertEq(r.clips.Length, 2, "seeding runs only while the file is missing")
    } finally {
        r.Done()
    }
}

Test_AuraClip_HadSurvivesNewInstance() {
    r := AcRig()
    try {
        r.cfg.Set("General.dryRun", 1)
        f := r.dir "\auras_had.txt"
        r.be := AcHadBe(r, f)
        r.be.Handle(Map("type", "aura", "name", "Gargantua", "ts", "2026-11-02T21:00:00Z", "live", false))
        AssertEq(r.clips.Length, 0, "startup aura: no clip")
        r.Aura("Equinox")
        AssertEq(r.clips.Length, 1, "new rare clips")
        r.be := AcHadBe(r, f)                      ; macro restart
        r.Aura("Equinox")
        r.Aura("Gargantua")
        AssertEq(r.clips.Length, 1, "both remembered across instances (startup aura too)")
        r.Aura("Equinox", 1, 1)
        AssertEq(r.clips.Length, 2, "a test event ignores the set")
        r.Aura("Illusionary", 1, 1)
        r.be := AcHadBe(r, f)
        r.Aura("Illusionary")
        AssertEq(r.clips.Length, 4, "a test event is not remembered")
    } finally {
        r.Done()
    }
}
