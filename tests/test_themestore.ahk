#Requires AutoHotkey v2.0
; Tests for lib\ui\ThemeStore.ahk (saved themes: model, validation, files, migration).
; Files only go to scratch folders under A_Temp, never the repo or settings.ini.
#Include ..\lib\Config.ahk
#Include ..\lib\ui\ThemeStore.ahk

; ---- helpers (names must not start with Test_) -----------------------------

TsTmpCfg() {
    d := A_Temp "\vesper_themetest_" A_TickCount "_" Random(100000, 999999)
    DirCreate(d)
    return Config.Load(d)
}

TsClean(cfg) {
    try DirDelete(cfg.dir, true)
}

; every font "installed" except the one named, so tests do not depend on the machine
TsFakeFonts(missing := "Zzz Not A Font") {
    ThemeStore.FontExistsFn := (fam) => (fam != missing)
}

TsRealFonts() {
    ThemeStore.FontExistsFn := (fam) => ThemeStore.SystemHasFont(fam)
}

; ---- tests -----------------------------------------------------------------

Test_ThemeStore_PresetsAreFullThemes() {
    for n in Theme.Names {
        t := ThemeStore.Preset(n)
        AssertTrue(IsObject(t), "preset " n " exists")
        AssertEq(t["name"], n, n " name")
        AssertEq(t["preset"], true, n " preset flag")
        for k in Theme.BaseKeys
            AssertEq(t["colors"][k], Theme.Presets[n].%k%, n " " k)
        for k in ThemeStore.DerivedKeys
            AssertEq(t["colors"][k], Theme.Presets[n].%k%, n " " k)
        AssertEq(t["ui"]["scale"], 100, n " scale")
        AssertEq(t["ui"]["sidebar"], "left", n " sidebar")
        for r in ThemeStore.FontRoles
            AssertTrue(t["fonts"].Has(r), n " font " r)
    }
    AssertEq(ThemeStore.Preset("Nope"), "", "unknown preset")
    AssertEq(ThemeStore.Default()["name"], "Moontide", "default is Moontide")
}

Test_ThemeStore_CleanFallsBack() {
    TsFakeFonts()
    try {
    d := ThemeStore.Default()
    m := ThemeStore.Default()
    m["name"] := "bad\name"
    m["colors"]["Bg"] := "zzz"
    m["colors"]["SideBg"] := "12"
    m["ui"]["scale"] := 120
    m["ui"]["sidebar"] := "up"
    m["picture"]["fit"] := "zoom"
    m["picture"]["dim"] := 140
    m["fonts"]["body"] := ["Segoe UI", 2]
    m["fonts"]["head"] := ["Segoe UI", 40]
    c := ThemeStore.Clean(m)
    AssertEq(c["name"], "My theme", "bad name")
    AssertEq(c["colors"]["Bg"], d["colors"]["Bg"], "bad hex")
    AssertEq(c["colors"]["SideBg"], "", "bad derived hex is left auto")
    AssertEq(c["ui"]["scale"], 100, "scale")
    AssertEq(c["ui"]["sidebar"], "left", "sidebar")
    AssertEq(c["picture"]["fit"], "fill", "fit")
    AssertEq(c["picture"]["dim"], 60, "dim")
    AssertEq(c["fonts"]["body"][2], d["fonts"]["body"][2], "size 2")
    AssertEq(c["fonts"]["head"][2], 28, "size 40")
    AssertEq(ThemeStore.Clean("junk")["name"], "Moontide", "not a map")
    AssertEq(ThemeStore.Clean(Map())["ui"]["scale"], 100, "empty map")
    } finally
        TsRealFonts()
}

Test_ThemeStore_MissingFontFallsBack() {
    TsFakeFonts()
    try {
        m := ThemeStore.Default()
        m["fonts"]["nav"] := ["Zzz Not A Font", 12]
        c := ThemeStore.Clean(m)
        AssertEq(c["fonts"]["nav"][1], "Segoe UI", "missing family")
        AssertEq(c["fonts"]["nav"][2], 12, "size kept")
    } finally
        TsRealFonts()
    ; the real check knows Segoe UI and not the made-up name
    AssertTrue(ThemeStore.SystemHasFont("Segoe UI"), "Segoe UI installed")
    AssertTrue(!ThemeStore.SystemHasFont("Zzz Not A Font"), "made-up family")
}

; the default hook, through Clean: installed families are kept (a bare method Func
; as the hook lost its `this`, threw, and turned every family into Segoe UI)
Test_ThemeStore_RealFontHookKeepsInstalledFonts() {
    TsRealFonts()
    AssertTrue(ThemeStore.FontExistsFn.Call("Segoe UI"), "hook finds Segoe UI")
    AssertTrue(!ThemeStore.FontExistsFn.Call("Zzz Not A Font"), "hook rejects a made-up family")
    c := ThemeStore.Clean(ThemeStore.Default())
    AssertEq(c["fonts"]["title"][1], "Segoe UI Light", "title family kept")
    AssertEq(c["fonts"]["head"][1], "Segoe UI Semibold", "head family kept")
    m := ThemeStore.Default()
    m["fonts"]["body"] := ["Zzz Not A Font", 11]
    AssertEq(ThemeStore.Clean(m)["fonts"]["body"][1], "Segoe UI", "missing family with the real hook")
}

Test_ThemeStore_SaveLoadRoundTrip() {
    TsFakeFonts()
    cfg := TsTmpCfg()
    try {
        t := ThemeStore.Default()
        t["name"] := "Night sea"
        t["preset"] := false
        t["colors"]["Bg"] := "010203"
        t["colors"]["Muted"] := "AABBCC"
        t["fonts"]["title"] := ["Segoe UI", 24]
        t["fonts"]["button"] := ["Segoe UI", 12]
        t["ui"]["scale"] := 115
        t["ui"]["sidebar"] := "top"
        t["picture"]["fit"] := "tile"
        t["picture"]["dim"] := 35
        t["layout"] := Map("Settings:Recovery", [204, 512, 396, 134, 0], "Fishing:#2", [8, 16, 200, 100, 1], "Look:Theme", [0, 0, 64, 64, 0])
        AssertEq(ThemeStore.Save(cfg, t), true, "save")
        AssertTrue(FileExist(ThemeStore.Dir(cfg) "\Night sea.moontheme") != "", "file written")
        l := ThemeStore.Load(cfg, "Night sea")
        AssertEq(l["name"], "Night sea", "name")
        AssertEq(l["preset"], false, "not a preset")
        for k, v in t["colors"]
            AssertEq(l["colors"][k], v, "colour " k)
        for r, f in t["fonts"] {
            AssertEq(l["fonts"][r][1], f[1], "family " r)
            AssertEq(l["fonts"][r][2], f[2], "size " r)
        }
        AssertEq(l["ui"]["scale"], 115, "scale")
        AssertEq(l["ui"]["sidebar"], "top", "sidebar")
        AssertEq(l["picture"]["fit"], "tile", "fit")
        AssertEq(l["picture"]["dim"], 35, "dim")
        AssertEq(l["picture"]["file"], t["picture"]["file"], "picture file")
        AssertEq(l["layout"].Count, 3, "layout count")
        for id, v in t["layout"]
            for i, n in v
                AssertEq(l["layout"][id][i], n, "layout " id " " i)
        ; a derived colour left empty stays empty
        t2 := ThemeStore.Default()
        t2["name"] := "Auto"
        t2["colors"]["Pulse"] := ""
        ThemeStore.Save(cfg, t2)
        AssertEq(ThemeStore.Load(cfg, "Auto")["colors"]["Pulse"], "", "empty derived")
        ; unknown / unsafe names load the default
        AssertEq(ThemeStore.Load(cfg, "Nothing here")["name"], "Moontide", "unknown name")
        AssertEq(ThemeStore.Load(cfg, "..\..\x")["name"], "Moontide", "unsafe name")
        AssertEq(ThemeStore.Load(cfg, "Galaxy")["preset"], true, "preset load")
    } finally {
        TsRealFonts()
        TsClean(cfg)
    }
}

Test_ThemeStore_PresetNamesRefused() {
    cfg := TsTmpCfg()
    try {
        t := ThemeStore.Default()
        t["name"] := "Galaxy"
        r := ThemeStore.Save(cfg, t)
        AssertTrue(r != true && r != "", "reason returned")
        AssertTrue(!FileExist(ThemeStore.Dir(cfg) "\Galaxy.moontheme"), "no file")
        t["name"] := "galaxy"
        AssertTrue(ThemeStore.Save(cfg, t) != true, "case-insensitive")
        t["name"] := "a\b"
        AssertTrue(ThemeStore.Save(cfg, t) != true, "bad name refused")
        AssertEq(ThemeStore.Delete(cfg, "Galaxy"), false, "preset cannot be deleted")
    } finally
        TsClean(cfg)
}

Test_ThemeStore_ListRenameDuplicateDelete() {
    cfg := TsTmpCfg()
    try {
        for n in ["Zed", "alpha", "Mid"] {
            t := ThemeStore.Default()
            t["name"] := n
            ThemeStore.Save(cfg, t)
        }
        l := ThemeStore.List(cfg)
        p := Theme.Names.Length
        AssertEq(l.Length, p + 3, "list count")
        AssertEq(l[1], "Moontide", "presets first")
        AssertEq(l[p + 1], "alpha", "sorted 1")
        AssertEq(l[p + 2], "Mid", "sorted 2")
        AssertEq(l[p + 3], "Zed", "sorted 3")
        AssertEq(ThemeStore.Rename(cfg, "Zed", "Omega"), true, "rename")
        AssertEq(ThemeStore.Load(cfg, "Omega")["name"], "Omega", "renamed name")
        AssertTrue(!FileExist(ThemeStore.Dir(cfg) "\Zed.moontheme"), "old file gone")
        AssertTrue(ThemeStore.Rename(cfg, "Omega", "Mid") != true, "rename onto existing")
        AssertTrue(ThemeStore.Rename(cfg, "Omega", "Overdrive") != true, "rename onto preset")
        AssertEq(ThemeStore.Duplicate(cfg, "Galaxy", "Galaxy 2"), true, "duplicate a preset")
        d := ThemeStore.Load(cfg, "Galaxy 2")
        AssertEq(d["preset"], false, "copy is editable")
        AssertEq(d["colors"]["Accent"], Theme.Presets["Galaxy"].Accent, "copy colours")
        AssertTrue(ThemeStore.Duplicate(cfg, "Galaxy", "Galaxy 2") != true, "duplicate onto existing")
        AssertEq(ThemeStore.Delete(cfg, "Galaxy 2"), true, "delete")
        AssertTrue(!FileExist(ThemeStore.Dir(cfg) "\Galaxy 2.moontheme"), "deleted")
    } finally
        TsClean(cfg)
}

Test_ThemeStore_FromTextBadInput() {
    c := ThemeStore.FromText("")
    AssertEq(c["name"], "My theme", "empty text")
    c := ThemeStore.FromText("[Theme]`nformat=1`nname=Cut off`n[Colors]`nBg=11")
    AssertEq(c["name"], "Cut off", "cut-off name")
    AssertEq(c["colors"]["Bg"], ThemeStore.Default()["colors"]["Bg"], "cut-off bad hex")
    c := ThemeStore.FromText("[Theme]`nname=X`n[Weird]`nfoo=bar`n[Layout]`nA:B=1,2,3,4,0`nA:C=junk`nA:D=1,2,0,4,0")
    AssertEq(c["layout"].Count, 1, "only the good layout entry")
    AssertTrue(!InStr(ThemeStore.ToText(c), "Weird"), "unknown sections are not kept")
}

Test_ThemeStore_MigrateCustom() {
    TsFakeFonts()
    cfg := TsTmpCfg()
    try {
        cfg.Set("UI.customBg", "101010")
        cfg.Set("UI.customPanel", "#203040")
        cfg.Set("UI.customText", "eeeeee")
        cfg.Set("UI.customAccent", "FF00AA")
        cfg.Set("UI.customPicture", "Galaxy")
        cfg.Set("UI.theme", "Custom")
        AssertEq(ThemeStore.Migrate(cfg), true, "migrated")
        AssertEq(cfg.Get("UI.theme", ""), "My theme", "theme switched")
        t := ThemeStore.Load(cfg, "My theme")
        AssertEq(t["colors"]["Bg"], "101010", "Bg")
        AssertEq(t["colors"]["PanelC"], "203040", "Panel")
        AssertEq(t["colors"]["Text"], "EEEEEE", "Text")
        AssertEq(t["colors"]["Accent"], "FF00AA", "Accent")
        AssertEq(t["picture"]["file"], "Galaxy", "picture")
        AssertEq(cfg.Get("UI.customBg", ""), "101010", "old keys kept")
        before := FileRead(ThemeStore.Dir(cfg) "\My theme.moontheme", "UTF-8")
        AssertEq(ThemeStore.Migrate(cfg), false, "second run changes nothing")
        AssertEq(FileRead(ThemeStore.Dir(cfg) "\My theme.moontheme", "UTF-8"), before, "file unchanged")
        AssertEq(cfg.Get("UI.theme", ""), "My theme", "still My theme")
        ; nothing to migrate in a clean cfg
        cfg2 := TsTmpCfg()
        try {
            AssertEq(ThemeStore.Migrate(cfg2), false, "nothing to do")
            AssertTrue(!FileExist(ThemeStore.Dir(cfg2) "\My theme.moontheme"), "no file made")
        } finally
            TsClean(cfg2)
    } finally {
        TsRealFonts()
        TsClean(cfg)
    }
}

; ---- .moontheme file: export and import -------------------------------------

; a real 1x1 PNG
TsPng() => ThemeStore._B64Decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==")

TsBytesEq(a, b) {
    if (a.Size != b.Size)
        return false
    return DllCall("msvcrt\memcmp", "Ptr", a, "Ptr", b, "UPtr", a.Size, "Int") = 0
}

; a theme with its own picture file in cfg's themes folder (not saved yet)
TsOwnPicTheme(cfg, name) {
    t := ThemeStore.Default()
    t["name"] := name
    t["preset"] := false
    t["colors"]["Bg"] := "010203"
    t["colors"]["Muted"] := "AABBCC"
    t["fonts"]["title"] := ["Segoe UI", 24]
    t["ui"]["scale"] := 115
    t["ui"]["sidebar"] := "top"
    t["picture"]["file"] := name ".png"
    t["picture"]["fit"] := "tile"
    t["picture"]["dim"] := 35
    t["layout"] := Map("Settings:Recovery", [204, 512, 396, 134, 0], "Fishing:#2", [8, 16, 200, 100, 1])
    DirCreate(ThemeStore.Dir(cfg))
    f := FileOpen(ThemeStore.Dir(cfg) "\" name ".png", "w")
    f.RawWrite(TsPng())
    f.Close()
    return t
}

TsWriteText(cfg, text, nm := "in") {
    d := cfg.dir "\incoming"
    DirCreate(d)
    p := d "\" nm ".moontheme"
    f := FileOpen(p, "w", "UTF-8-RAW")
    f.Write(text)
    f.Close()
    return p
}

Test_ThemeFile_RoundTrip() {
    TsFakeFonts()
    cfg := TsTmpCfg()
    try {
        t := TsOwnPicTheme(cfg, "Night sea")
        AssertEq(ThemeStore.Save(cfg, t), true, "save")
        p := ThemeStore.Export(cfg, "Night sea")
        AssertEq(p, cfg.dir "\exports\Night sea.moontheme", "export path")
        AssertTrue(FileExist(p) != "", "file written")
        txt := FileRead(p, "UTF-8")
        AssertTrue(InStr(txt, "data="), "picture embedded")
        AssertTrue(InStr(txt, "ext=png"), "ext written")
        AssertTrue(!InStr(txt, "Night sea.png"), "no local picture name")
        r := ThemeStore.ReadFile(p)
        AssertTrue(!r.Has("error"), "read ok")
        AssertTrue(TsIsPng(r["picBytes"], 1, 1), "read picture: a 1x1 PNG")
        cfg2 := TsTmpCfg()
        try {
            AssertEq(ThemeStore.Import(cfg2, r), "Night sea", "imported name")
            l := ThemeStore.Load(cfg2, "Night sea")
            for k, v in t["colors"]
                AssertEq(l["colors"][k], v, "colour " k)
            for ro, f in t["fonts"] {
                AssertEq(l["fonts"][ro][1], f[1], "family " ro)
                AssertEq(l["fonts"][ro][2], f[2], "size " ro)
            }
            AssertEq(l["ui"]["scale"], 115, "scale")
            AssertEq(l["ui"]["sidebar"], "top", "sidebar")
            AssertEq(l["picture"]["fit"], "tile", "fit")
            AssertEq(l["picture"]["dim"], 35, "dim")
            AssertEq(l["picture"]["file"], "Night sea.png", "picture file is the own name")
            AssertEq(l["layout"].Count, 2, "layout count")
            for id, v in t["layout"]
                for i, n in v
                    AssertEq(l["layout"][id][i], n, "layout " id " " i)
            pf := ThemeStore.Dir(cfg2) "\Night sea.png"
            AssertTrue(FileExist(pf) != "", "picture written")
            AssertTrue(TsBytesEq(FileRead(pf, "RAW"), r["picBytes"]), "imported picture bytes")
        } finally
            TsClean(cfg2)
        ; a preset exports its preset picture name and no data
        p2 := ThemeStore.Export(cfg, "Galaxy")
        t2 := FileRead(p2, "UTF-8")
        AssertTrue(InStr(t2, "file=Galaxy") && !InStr(t2, "data="), "preset picture by name")
        AssertEq(ThemeStore.Export(cfg, "bad\name"), "", "bad name fails")
    } finally {
        TsRealFonts()
        TsClean(cfg)
    }
}

Test_ThemeFile_NoSecrets() {
    TsFakeFonts()
    cfg := TsTmpCfg()
    try {
        cfg.Set("Discord.webhook", "https://discord.com/api/webhooks/111/FAKEWEBHOOK")
        cfg.Set("Discord.privateServer", "https://www.roblox.com/games/1/FAKE?privateServerLinkCode=FAKELINK")
        cfg.Set("Discord.botToken", "FAKEBOTTOKEN.abc.def")
        t := TsOwnPicTheme(cfg, "Plain")
        t["layout"] := Map("Fishing:#2", [8, 16, 200, 100, 1])    ; a real layout id would say Settings: that is a page name, not a settings value
        ThemeStore.Save(cfg, t)
        p := ThemeStore.Export(cfg, "Plain")
        txt := FileRead(p, "UTF-8")
        for bad in ["FAKEWEBHOOK", "webhooks", "FAKELINK", "privateServer", "FAKEBOTTOKEN", "botToken", ":\", "settings", "discord"]
            AssertTrue(!InStr(txt, bad), "export has no " bad)
    } finally {
        TsRealFonts()
        TsClean(cfg)
    }
}

Test_ThemeFile_BadFiles() {
    TsFakeFonts()
    cfg := TsTmpCfg()
    try {
        ; cut off after [Colors]
        r := ThemeStore.ReadFile(TsWriteText(cfg, "[Theme]`nformat=1`nname=Cut`n[Colors]`n", "cut"))
        AssertTrue(!r.Has("error"), "cut-off reads")
        AssertEq(r["theme"]["name"], "Cut", "cut name")
        AssertEq(r["theme"]["colors"]["Bg"], ThemeStore.Default()["colors"]["Bg"], "cut default colour")
        AssertEq(r["theme"]["ui"]["scale"], 100, "cut default ui")
        ; unknown sections ignored
        r := ThemeStore.ReadFile(TsWriteText(cfg, "[Theme]`nname=U`n[Weird]`nfoo=bar`n[Settings]`nUI.theme=x`n", "unk"))
        AssertTrue(!r.Has("error"), "unknown sections read")
        AssertTrue(!InStr(ThemeStore.ToText(r["theme"]), "Weird"), "unknown not kept")
        ; picture that is not an image
        b64 := ThemeStore._B64Encode(TsPng())
        txt := "[Theme]`nname=Pic`n[Picture]`next=png`nfit=fill`ndim=50`ndata=" b64 "`n"
        old := ThemeStore.PictureOkFn
        ThemeStore.PictureOkFn := (bytes) => false
        try {
            r := ThemeStore.ReadFile(TsWriteText(cfg, txt, "pic"))
        } finally
            ThemeStore.PictureOkFn := old
        AssertTrue(!r.Has("error"), "bad picture still reads")
        AssertEq(r["picBytes"], "", "picture dropped")
        AssertTrue(r["notes"].Length >= 1, "note about the picture")
        AssertEq(r["theme"]["picture"]["file"], "Moontide", "falls back to Moontide")
        ; the same file with a picture that loads
        r := ThemeStore.ReadFile(TsWriteText(cfg, txt, "pic"))
        AssertTrue(IsObject(r["picBytes"]), "real picture kept")
        AssertEq(r["notes"].Length, 0, "no notes")
        ; a 9 MB file
        big := cfg.dir "\incoming\big.moontheme"
        f := FileOpen(big, "w")
        f.RawWrite(Buffer(9 * 1024 * 1024, 65))
        f.Close()
        r := ThemeStore.ReadFile(big)
        AssertTrue(r.Has("error") && r["error"] != "", "9 MB file is an error")
        ; an oversized picture (5.5 MB decoded; 6 MB would not fit under the file cap)
        bigPic := Buffer(5 * 1024 * 1024 + 512 * 1024, 0)
        png := TsPng()
        DllCall("RtlMoveMemory", "Ptr", bigPic, "Ptr", png, "UPtr", png.Size)
        old := ThemeStore.PictureOkFn
        ThemeStore.PictureOkFn := (bytes) => true
        try {
            r := ThemeStore.ReadFile(TsWriteText(cfg, "[Theme]`nname=Big`n[Picture]`ndata=" ThemeStore._B64Encode(bigPic) "`n", "bigpic"))
        } finally
            ThemeStore.PictureOkFn := old
        AssertTrue(!r.Has("error"), "big picture file reads")
        AssertEq(r["picBytes"], "", "big picture dropped")
        AssertTrue(r["notes"].Length >= 1, "note about the big picture")
        ; no file at all
        AssertTrue(ThemeStore.ReadFile(cfg.dir "\nope.moontheme").Has("error"), "missing file")
    } finally {
        TsRealFonts()
        TsClean(cfg)
    }
}

Test_ThemeFile_NameClash() {
    TsFakeFonts()
    cfg := TsTmpCfg()
    try {
        p := TsWriteText(cfg, "[Theme]`nname=Night sea`n")
        AssertEq(ThemeStore.Import(cfg, ThemeStore.ReadFile(p)), "Night sea", "first")
        AssertEq(ThemeStore.Import(cfg, ThemeStore.ReadFile(p)), "Night sea (2)", "second")
        AssertEq(ThemeStore.Import(cfg, ThemeStore.ReadFile(p)), "Night sea (3)", "third")
        ; a preset name is taken too
        p2 := TsWriteText(cfg, "[Theme]`nname=Galaxy`n", "g")
        AssertEq(ThemeStore.Import(cfg, ThemeStore.ReadFile(p2)), "Galaxy (2)", "preset name")
        AssertEq(ThemeStore.Import(cfg, Map("error", "x")), "", "error read imports nothing")
    } finally {
        TsRealFonts()
        TsClean(cfg)
    }
}

Test_ThemeFile_HostileValues() {
    TsFakeFonts()
    cfg := TsTmpCfg()
    try {
        txt := "[Theme]`nname=Evil`n[Picture]`nfile=..\..\evil.png`nfit=fill`ndim=50`n[Layout]`nA:B=99999,99999,5,5,0`n"
        r := ThemeStore.ReadFile(TsWriteText(cfg, txt, "evil"))
        AssertEq(r["theme"]["picture"]["file"], "evil.png", "only the base name")
        AssertTrue(!InStr(r["theme"]["picture"]["file"], "\"), "no path")
        AssertTrue(r["theme"]["layout"].Has("A:B"), "big layout value kept")
        AssertEq(r["theme"]["layout"]["A:B"][1], 99999, "value kept as is")
        AssertEq(r["clamp"].Length, 1, "marked for clamping")
        AssertEq(r["clamp"][1], "A:B", "the marked id")
        ; imported with no picture data: a local name that does not exist becomes Moontide, nothing is written outside
        n := ThemeStore.Import(cfg, r)
        AssertEq(ThemeStore.Load(cfg, n)["picture"]["file"], "Moontide", "no data, no own picture")
        AssertTrue(!FileExist(cfg.dir "\evil.png") && !FileExist(ThemeStore.Dir(cfg) "\evil.png"), "no file written")
        ; 50 000 layout lines
        s := "[Theme]`nname=Many`n[Layout]`n"
        Loop 50000
            s .= "P:C" A_Index "=1,2,30,40,0`n"
        r := ThemeStore.ReadFile(TsWriteText(cfg, s, "many"))
        AssertEq(r["theme"]["layout"].Count, ThemeStore.MaxLayout, "first 400 layout lines")
        AssertTrue(r["theme"]["layout"].Has("P:C400") && !r["theme"]["layout"].Has("P:C401"), "the first 400, not the rest")
    } finally {
        TsRealFonts()
        TsClean(cfg)
    }
}

Test_ThemeFile_PictureHookDefault() {
    AssertTrue(ThemeStore.PictureOkFn.Call(TsPng()), "default hook loads a real PNG")
    junk := Buffer(64, 7)
    AssertTrue(!ThemeStore.PictureOkFn.Call(junk), "default hook rejects junk")
}

Test_ThemeFile_PictureFollowsRenameDuplicateDelete() {
    TsFakeFonts()
    cfg := TsTmpCfg()
    try {
        t := TsOwnPicTheme(cfg, "Alpha")
        ThemeStore.Save(cfg, t)
        d := ThemeStore.Dir(cfg)
        AssertEq(ThemeStore.Duplicate(cfg, "Alpha", "Beta"), true, "duplicate")
        AssertTrue(FileExist(d "\Beta.png") != "" && FileExist(d "\Alpha.png") != "", "picture copied")
        AssertEq(ThemeStore.Load(cfg, "Beta")["picture"]["file"], "Beta.png", "copy points at its own picture")
        AssertEq(ThemeStore.Rename(cfg, "Beta", "Gamma"), true, "rename")
        AssertTrue(FileExist(d "\Gamma.png") != "" && !FileExist(d "\Beta.png"), "picture moved")
        AssertEq(ThemeStore.Load(cfg, "Gamma")["picture"]["file"], "Gamma.png", "renamed points at the moved picture")
        AssertEq(ThemeStore.Delete(cfg, "Gamma"), true, "delete")
        AssertTrue(!FileExist(d "\Gamma.png"), "picture deleted")
        AssertTrue(FileExist(d "\Alpha.png") != "", "other picture untouched")
        ; a picture that is not the theme's own (another theme's file name) is never deleted
        t2 := ThemeStore.Default()
        t2["name"] := "Shares"
        t2["picture"]["file"] := "Alpha.png"
        ThemeStore.Save(cfg, t2)
        ThemeStore.Delete(cfg, "Shares")
        AssertTrue(FileExist(d "\Alpha.png") != "", "not-own picture kept")
    } finally {
        TsRealFonts()
        TsClean(cfg)
    }
}

; a copy of the PNG whose IHDR declares w x h, with a correct CRC
TsPngSize(w, h) {
    b := TsPng()
    NumPut("UChar", (w >> 24) & 255, b, 16), NumPut("UChar", (w >> 16) & 255, b, 17), NumPut("UChar", (w >> 8) & 255, b, 18), NumPut("UChar", w & 255, b, 19)
    NumPut("UChar", (h >> 24) & 255, b, 20), NumPut("UChar", (h >> 16) & 255, b, 21), NumPut("UChar", (h >> 8) & 255, b, 22), NumPut("UChar", h & 255, b, 23)
    crc := DllCall("ntdll\RtlComputeCrc32", "UInt", 0, "Ptr", b.Ptr + 12, "UInt", 17, "UInt")
    NumPut("UChar", (crc >> 24) & 255, b, 29), NumPut("UChar", (crc >> 16) & 255, b, 30), NumPut("UChar", (crc >> 8) & 255, b, 31), NumPut("UChar", crc & 255, b, 32)
    return b
}

Test_ThemeFile_PictureReallyDecodes() {
    AssertTrue(ThemeStore.PictureOkFn.Call(TsPng()), "real PNG passes")
    AssertTrue(ThemeStore.PictureOkFn.Call(TsPngSize(1, 1)), "the hand-made header has a correct CRC")
    AssertTrue(!ThemeStore.PictureOkFn.Call(TsPngSize(60000, 60000)), "a 60000 x 60000 header is refused")
    AssertTrue(!ThemeStore.PictureOkFn.Call(TsPngSize(8193, 1)), "wider than 8192 is refused")
    ; a real picture from assets, whole, then with its body cut off or damaged
    real := FileRead(A_ScriptDir "/../assets/vesper_moon.png", "RAW")
    AssertTrue(ThemeStore.PictureOkFn.Call(real), "a real asset picture passes")
    cut := Buffer(real.Size // 2)
    DllCall("RtlMoveMemory", "Ptr", cut, "Ptr", real, "UPtr", cut.Size)
    AssertTrue(!ThemeStore.PictureOkFn.Call(cut), "a truncated PNG is refused")
    bad := Buffer(real.Size)
    DllCall("RtlMoveMemory", "Ptr", bad, "Ptr", real, "UPtr", real.Size)
    Loop 200
        NumPut("UChar", 0xAA, bad, 100 + A_Index)
    AssertTrue(!ThemeStore.PictureOkFn.Call(bad), "a damaged body is refused")
}

; the picture cannot move: Rename says so and loses nothing
Test_ThemeFile_RenameKeepsPictureWhenMoveFails() {
    TsFakeFonts()
    cfg := TsTmpCfg()
    try {
        t := TsOwnPicTheme(cfg, "Alpha")
        ThemeStore.Save(cfg, t)
        d := ThemeStore.Dir(cfg)
        lock := FileOpen(d "\Alpha.png", "r-d")
        try
            r := ThemeStore.Rename(cfg, "Alpha", "Omega")
        finally
            lock.Close()
        AssertTrue(r != true && r != "", "rename reports the failure")
        AssertTrue(FileExist(d "\Alpha.moontheme") != "", "old theme still there")
        AssertTrue(!FileExist(d "\Omega.moontheme"), "no half-made new theme")
        AssertEq(ThemeStore.Load(cfg, "Alpha")["picture"]["file"], "Alpha.png", "still points at its picture")
        AssertTrue(FileExist(d "\Alpha.png") != "", "picture still there")
        ; without the lock it works
        AssertEq(ThemeStore.Rename(cfg, "Alpha", "Omega"), true, "rename works unlocked")
        AssertTrue(FileExist(d "\Omega.png") != "" && !FileExist(d "\Alpha.png"), "picture moved")
    } finally {
        TsRealFonts()
        TsClean(cfg)
    }
}

Test_ThemeFile_ClampsNegativeSize() {
    cfg := TsTmpCfg()
    try {
        r := ThemeStore.ReadFile(TsWriteText(cfg, "[Theme]`nname=Neg`n[Layout]`nA:B=1,2,-5,10,0`nA:C=1,2,30,40,0`n", "neg"))
        AssertTrue(!r.Has("error"), "reads")
        AssertTrue(!r["theme"]["layout"].Has("A:B") && r["theme"]["layout"].Has("A:C"), "a negative size is dropped by Clean, never reaches the clamp list")
    } finally
        TsClean(cfg)
}

; Spec 7, "the log says why": LoadWhy names why a theme fell back to
; Moontide, and the boot line names the theme (only a real theme name,
; never a path) and the reason.
Test_ThemeStore_FallbackSaysWhy() {
    cfg := TsTmpCfg()
    try {
        r := ThemeStore.LoadWhy(cfg, "Galaxy")
        AssertEq(r.theme["name"] "|" r.why, "Galaxy|", "a preset is used")
        r := ThemeStore.LoadWhy(cfg, "Gone theme")
        AssertEq(r.theme["name"] "|" r.why, "Moontide|its file is missing", "a missing file")
        r := ThemeStore.LoadWhy(cfg, "C:\Users\x\evil")
        AssertEq(r.theme["name"] "|" r.why, "Moontide|it is not a theme name", "not a name")
        r := ThemeStore.LoadWhy(cfg, {})
        AssertEq(r.theme["name"], "Moontide", "an object never throws")
        t := ThemeStore.Default()
        t["name"] := "Mine", t["preset"] := false
        AssertEq(ThemeStore.Save(cfg, t), true, "saved")
        r := ThemeStore.LoadWhy(cfg, "Mine")
        AssertEq(r.theme["name"] "|" r.why, "Mine|", "a saved theme is used")
        AssertEq(ThemeStore.Load(cfg, "Gone theme")["name"], "Moontide", "Load still falls back")
        AssertEq(ThemeStore.FallbackLine("Gone theme", "its file is missing"), "Theme: Gone theme could not be used (its file is missing), using Moontide", "the line")
        AssertEq(ThemeStore.FallbackLine("C:\Users\x\evil", "it is not a theme name"), "Theme: the saved theme could not be used (it is not a theme name), using Moontide", "no path in the line")
        AssertEq(ThemeStore.FallbackLine("Galaxy", ""), "", "no line when it was used")
        AssertEq(ThemeStore.FallbackLine({}, "x"), "Theme: the saved theme could not be used (x), using Moontide", "an object never throws")
        old := Theme.Current
        Theme.Apply(ThemeStore.Preset("Galaxy"))
        AssertEq(Theme.ApplyWhy, "", "a good theme applies without a why")
        Theme.Apply(ThemeStore.Preset(old != "" ? old : "Moontide"))
    } finally
        TsClean(cfg)
}

; a PNG (signature) whose IHDR says w x h
TsIsPng(b, w, h) {
    if (!IsObject(b) || b.Size < 24 || NumGet(b, 0, "UInt") != 0x474E5089 || NumGet(b, 4, "UInt") != 0x0A1A0A0D)
        return false
    be := (o) => (NumGet(b, o, "UChar") << 24) | (NumGet(b, o + 1, "UChar") << 16) | (NumGet(b, o + 2, "UChar") << 8) | NumGet(b, o + 3, "UChar")
    return be(16) = w && be(20) = h
}

; true when the bytes hold the ASCII text
TsHasText(b, text) {
    n := StrLen(text)
    Loop b.Size - n + 1 {
        i := A_Index - 1, ok := true
        Loop n {
            if (NumGet(b, i + A_Index - 1, "UChar") != Ord(SubStr(text, A_Index, 1))) {
                ok := false
                break
            }
        }
        if ok
            return true
    }
    return false
}

; a real 16 x 12 JPEG made by GDI+, with an EXIF block (APP1) carrying `mark` put in after its SOI
TsJpegWithExif(mark) {
    tok := 0, bmp := 0, jpg := ""
    DllCall("LoadLibrary", "Str", "gdiplus", "Ptr")
    si := Buffer(24, 0), NumPut("UInt", 1, si, 0)
    DllCall("gdiplus\GdiplusStartup", "Ptr*", &tok, "Ptr", si, "Ptr", 0)
    try {
        DllCall("gdiplus\GdipCreateBitmapFromScan0", "Int", 16, "Int", 12, "Int", 0, "Int", 0x26200A, "Ptr", 0, "Ptr*", &bmp)
        jpg := ThemeStore._Encode(bmp, "jpg")
    } finally {
        if bmp
            DllCall("gdiplus\GdipDisposeImage", "Ptr", bmp)
        DllCall("gdiplus\GdiplusShutdown", "Ptr", tok)
    }
    ; APP1: FF E1, length, "Exif\0\0", a little TIFF header with an empty IFD, then the mark
    body := Buffer(6 + 14 + StrLen(mark), 0)
    StrPut("Exif", body, 4, "CP0")
    StrPut("II*", body.Ptr + 6, 3, "CP0")
    NumPut("UInt", 8, body, 10)                      ; IFD0 at 8: 0 entries, no next IFD
    StrPut(mark, body.Ptr + 20, StrLen(mark), "CP0")
    out := Buffer(jpg.Size + 4 + body.Size, 0)
    NumPut("UChar", 0xFF, out, 0), NumPut("UChar", 0xD8, out, 1), NumPut("UChar", 0xFF, out, 2), NumPut("UChar", 0xE1, out, 3)
    len := body.Size + 2
    NumPut("UChar", len >> 8, out, 4), NumPut("UChar", len & 255, out, 5)
    DllCall("RtlMoveMemory", "Ptr", out.Ptr + 6, "Ptr", body, "UPtr", body.Size)
    DllCall("RtlMoveMemory", "Ptr", out.Ptr + 6 + body.Size, "Ptr", jpg.Ptr + 2, "UPtr", jpg.Size - 2)
    return out
}

; Ruling (final review): an own picture is drawn again into a PNG at
; export, so a JPEG's EXIF / GPS block never goes into the shared file.
Test_ThemeFile_ExportDropsPictureMetadata() {
    TsFakeFonts()
    cfg := TsTmpCfg()
    try {
        src := TsJpegWithExif("GPSMARK-51.5N")
        AssertEq(ThemeStore._PicExt(src), "jpg", "the source is a JPEG")
        AssertTrue(TsHasText(src, "Exif") && TsHasText(src, "GPSMARK-51.5N"), "the source carries the EXIF block")
        AssertTrue(ThemeStore.PictureOkFn.Call(src), "GDI+ reads the source")
        t := TsOwnPicTheme(cfg, "Photo")
        t["picture"]["file"] := "Photo.jpg"
        f := FileOpen(ThemeStore.Dir(cfg) "\Photo.jpg", "w")
        f.RawWrite(src)
        f.Close()
        AssertEq(ThemeStore.Save(cfg, t), true, "saved")
        note := "x"
        p := ThemeStore.Export(cfg, "Photo", &note)
        AssertTrue(p != "", "exported")
        AssertEq(note, "", "no note")
        txt := FileRead(p, "UTF-8")
        AssertTrue(InStr(txt, "ext=png"), "the file says png")
        r := ThemeStore.ReadFile(p)
        AssertEq(r["picExt"], "png", "read back as png")
        AssertTrue(TsIsPng(r["picBytes"], 16, 12), "a 16 x 12 PNG")
        AssertTrue(!TsHasText(r["picBytes"], "Exif") && !TsHasText(r["picBytes"], "GPSMARK"), "no EXIF block, no mark")
        AssertEq(ThemeStore._ToPng(Buffer(10, 0)), "", "junk is no picture")
        AssertEq(ThemeStore._ToPng("text"), "", "not bytes")
    } finally {
        TsRealFonts()
        TsClean(cfg)
    }
}

; A picture over MaxPicture (a migrated one can be) is left out of the
; export with a note instead of silently.
Test_ThemeFile_ExportBigPictureNote() {
    TsFakeFonts()
    cfg := TsTmpCfg()
    try {
        t := TsOwnPicTheme(cfg, "Huge")
        AssertEq(ThemeStore.Save(cfg, t), true, "saved")
        f := FileOpen(ThemeStore.Dir(cfg) "\Huge.png", "w")
        f.RawWrite(TsPng())
        f.Length := ThemeStore.MaxPicture + 1
        f.Close()
        note := ""
        p := ThemeStore.Export(cfg, "Huge", &note)
        AssertTrue(p != "", "still exported")
        AssertEq(note, I18n.T("The picture is too big to share, so the theme was exported without it."), "the note")
        AssertTrue(!InStr(FileRead(p, "UTF-8"), "data="), "no picture data")
        AssertEq(ThemeStore.Export(cfg, "Galaxy", &note) != "" && note = "", true, "a preset: no note")
    } finally {
        TsRealFonts()
        TsClean(cfg)
    }
}
