#Requires AutoHotkey v2.0
; Offline tests for lib\Profiles.ahk (one-click profiles, settings export /
; import) and the Setup > Profiles page. Temp folders under A_Temp. Helpers
; are prefixed Pf.
#Include ..\lib\Profiles.ahk
#Include ..\lib\ui\Dashboard.ahk
#Include ..\lib\Updater.ahk

PfHook() => "https://discord.com/api/webhooks/123456789012345678/PfHookTokenSECRET"
PfLink() => "https://www.roblox.com/share?code=PFLINKCODE42&type=Server"
PfToken() => "PfBotToken.SECRET.xyz987"
PfUser() => "112233445566778899"

PfDir() {
    d := A_Temp "\vesper_pftest_" A_TickCount "_" Random(100000, 999999)
    DirCreate(d "\data")
    return d
}

; a Config with every kind of secret planted
PfCfg(dir) {
    cfg := Config.Load(dir)
    cfg.Set("General.privateServer", PfLink())
    cfg.Set("Remote.enabled", 1)
    cfg.Set("Remote.token", PfToken())
    cfg.Set("Remote.channel", "998877665544332211")
    cfg.Set("Remote.users", PfUser())
    cfg.Set("Craft.craftTarget", "see " PfHook())               ; a link in a plain key
    cfg.Set("General.alertSound", "C:\Users\PfZephyr\ding.wav")  ; a user path
    cfg.Set("Misc.apiKey", "PfApiKeyValue123")
    cfg.SetWebhooks([Map("name", "Main", "url", PfHook(), "mention", "<@" PfUser() ">", "enabled", 1, "events", "biome,rare")])
    cfg.Save()
    return cfg
}

PfHasSecret(text) {
    for s in [PfHook(), PfLink(), "PFLINKCODE42", PfToken(), PfUser(), "998877665544332211", "PfApiKeyValue123", "PfHookTokenSECRET", "PfZephyr"]
        if InStr(text, s)
            return s
    return ""
}

Test_Profiles_NamesAndOnlyRealKeys() {
    AssertEq(UiLogic.ArrayToCsv(Profiles.Names), "AFK fishing,Biome hunting,Overnight safe,Memory Match only", "four profiles")
    for name in Profiles.Names {
        AssertTrue(StrLen(Profiles.Description(name)) > 10 && !InStr(Profiles.Description(name), "`n"), name " one-line description")
        s := Profiles.Settings(name)
        AssertTrue(s.Length >= 5, name " sets several keys")
        for kv in s {
            dot := InStr(kv[1], ".", , -1)
            canon := Profiles.Canon(SubStr(kv[1], 1, dot - 1), SubStr(kv[1], dot + 1))
            AssertEq(canon, kv[1], name ": " kv[1] " is a real config key")
            AssertTrue(!RegExMatch(kv[1], "i)dryRun|privateServer|^Remote\.|^Webhook|^Update\."), name ": never " kv[1])
            AssertTrue(kv[2] = 0 || kv[2] = 1, name ": " kv[1] " is an on/off")
        }
    }
    ; every key a profile sets is a key the macro reads with that spelling
    d := Config.IniDefaults()
    AssertTrue(d["General"].Has("fishing") && d["Recovery"].Has("antiGhost") && d["MemoryMatch"].Has("enabled"), "defaults hold the main switches")
    AssertTrue(Profiles.Canon("General", "nope") = "" && Profiles.Canon("Bogus", "enabled") = "", "unknown keys are not real")
    try {
        Profiles.Settings("Nope")
        AssertTrue(false, "unknown profile throws")
    } catch ValueError {
    }
}

Test_Profiles_ApplyChangesOnlyItsKeys() {
    dir := PfDir()
    try {
        cfg := PfCfg(dir)
        cfg.Set("General.dryRun", 1)
        before := FileRead(dir "\settings.ini", "UTF-8")
        changed := Profiles.Apply(cfg, "Memory Match only")
        AssertTrue(changed.Length >= 4, "several keys changed: " changed.Length)
        AssertEq(cfg.Get("MemoryMatch.enabled", 0), 1, "Memory Match on")
        AssertEq(cfg.Get("General.fishing", 1), 0, "fishing off")
        AssertEq(cfg.Get("quests.enabled", 1), 0, "quests off (read the way the macro reads it)")
        AssertEq(cfg.Get("merchant.enabled", 1), 0, "merchants off")
        AssertEq(cfg.Get("Recovery.enabled", 0), 1, "recovery on")
        AssertEq(cfg.Get("General.dryRun", 0), 1, "dry run untouched")
        AssertEq(cfg.Get("General.privateServer", ""), PfLink(), "link untouched")
        AssertEq(cfg.Get("Remote.token", ""), PfToken(), "token untouched")
        AssertEq(cfg.Webhooks()[1]["url"], PfHook(), "webhook untouched")
        for k in changed {
            found := false
            for kv in Profiles.Settings("Memory Match only")
                if (kv[1] = k)
                    found := true
            AssertTrue(found, k " is one of the profile's keys")
        }
        ; recovery was already on: not counted
        for k in changed
            AssertTrue(k != "Recovery.enabled", "unchanged keys are not counted")
        AssertEq(Profiles.Apply(cfg, "Memory Match only").Length, 0, "applied twice: nothing changes")
        changed := Profiles.Apply(cfg, "AFK fishing")
        AssertEq(cfg.Get("General.fishing", 0), 1, "AFK fishing turns fishing back on")
        AssertEq(cfg.Get("MemoryMatch.enabled", 1), 0, "and Memory Match off")
        AssertTrue(changed.Length >= 4, "AFK fishing changed keys")
        AssertEq(FileRead(dir "\settings.ini", "UTF-8"), before, "Apply alone does not save")
    } finally {
        try DirDelete(dir, true)
    }
}

Test_Profiles_ExportHasNoSecrets() {
    dir := PfDir()
    try {
        cfg := PfCfg(dir)
        cfg.Set("General.sellEvery", 22)
        cfg.Set("Craft.qty_lucky_potion", 3)
        r := Profiles.Export(cfg, "20261113120000")
        AssertEq(r.ok, 1, "exported: " r.msg)
        AssertEq(r.path, dir "\exports\moontide_settings_20261113.ini", "file name and folder")
        text := FileRead(r.path, "UTF-8")
        AssertEq(PfHasSecret(text), "", "no secret value in the export")
        AssertEq(PfHasSecret(r.msg), "", "no secret in the message")
        AssertTrue(!RegExMatch(text, "im)^(privateServer|token|channel|users|url|mention|apiKey|prefix)="), "secret keys removed entirely")
        AssertTrue(!RegExMatch(text, "im)^\[(Webhook|Remote|Misc|Update)"), "no webhook / Remote / unknown / updater sections")
        AssertTrue(!InStr(text, "dryRun="), "dry run not exported")
        AssertTrue(!RegExMatch(text, "im)^craftTarget="), "a value holding a link is left out")
        AssertTrue(!RegExMatch(text, "im)^alertSound="), "a value with a user path is left out")
        AssertTrue(InStr(text, "sellEvery=22") && InStr(text, "qty_lucky_potion=3") && InStr(text, "[MemoryMatch]"), "normal settings are in it")
        AssertTrue(InStr(text, "`r`n") > 0, "CRLF lines")
        AssertTrue(r.n > 20, "counted settings: " r.n)
        ; ExportText scrubs the Windows user name too
        cfg.Set("Minions.aura", "PfZephyr")
        AssertTrue(!InStr(Profiles.ExportText(cfg, "PfZephyr"), "PfZephyr"), "the user name is left out")
    } finally {
        try DirDelete(dir, true)
    }
}

Test_Profiles_ImportSkipsSecretAndUnknownKeys() {
    dir := PfDir(), src := PfDir()
    try {
        cfg := PfCfg(dir)
        cfg.Set("Remote.enabled", 0)
        other :="https://discord.com/api/webhooks/555/OtherPersonHook"
        text := "; shared`r`n[General]`r`nsellEvery=42`r`nfishing=0`r`nprivateServer=https://www.roblox.com/share?code=OTHERCODE`r`n"
            . "dryRun=0`r`njoinButton=1`r`nmadeUpKey=7`r`n`r`n[Webhook.1]`r`nname=Theirs`r`nurl=" other "`r`nmention=<@1>`r`n`r`n"
            . "[Remote]`r`nenabled=1`r`ntoken=OtherToken123`r`nchannel=111111111111111111`r`nusers=222222222222222222`r`n`r`n"
            . "[Update]`r`nrepo=evil/repo`r`nauto=1`r`n`r`n[quests]`r`nenabled=0`r`n`r`n[Craft]`r`nqty_speed_potion=4`r`ncraftTarget=" other "`r`n"
            . "[Bogus]`r`nenabled=1`r`n[Obby]`r`nintervalMin=25`r`nretries=-3`r`n[Limbo]`r`nenabled=yes please`r`n"
        FileAppend(text, src "\theirs.ini", "UTF-8")
        r := Profiles.Import(cfg, src "\theirs.ini")
        AssertEq(r.ok, 1, "imported: " r.msg)
        AssertEq(r.n, 5, "sellEvery, fishing, quests.enabled, qty_speed_potion, intervalMin")
        AssertTrue(r.skipped >= 10, "the rest skipped: " r.skipped)
        AssertEq(r.msg, "Imported 5 settings (" r.skipped " skipped)", "message")
        AssertEq(cfg.Get("General.sellEvery", 0), 42, "known key merged")
        AssertEq(cfg.Get("General.fishing", 1), 0, "switch merged")
        AssertEq(cfg.Get("quests.enabled", 1), 0, "lower-case section merged")
        AssertEq(cfg.Get("Craft.qty_speed_potion", 0), 4, "per-potion qty merged")
        AssertEq(cfg.Get("Obby.intervalMin", 0), 25, "Obby interval merged")
        AssertEq(cfg.Get("Obby.retries", 0), 1, "a negative number skipped")
        AssertEq(cfg.Get("Limbo.enabled", 9), 0, "a switch that is not a number skipped")
        AssertEq(cfg.Get("General.privateServer", ""), PfLink(), "own link kept")
        AssertEq(cfg.Get("Remote.token", ""), PfToken(), "own token kept")
        AssertEq(cfg.Get("Remote.users", ""), PfUser(), "own user ids kept")
        AssertEq(cfg.Get("Remote.channel", ""), "998877665544332211", "own channel kept")
        AssertEq(cfg.Get("Remote.enabled", 1), 0, "the Discord bot is never switched on by an import")
        AssertEq(cfg.Webhooks().Length, 1, "no webhook added")
        AssertEq(cfg.Webhooks()[1]["url"], PfHook(), "own webhook kept")
        AssertEq(cfg.Get("General.dryRun", 1), 1, "dry run never imported")
        AssertEq(cfg.Get("General.joinButton", 1), 0, "the Join Server link switch never imported")
        AssertEq(cfg.Get("Update.repo", ""), Config.IniDefaults()["Update"]["repo"], "updater repo never imported")
        AssertEq(cfg.Get("Update.auto", 0), 0, "auto update never imported")
        AssertEq(cfg.Get("General.madeUpKey", ""), "", "unknown key skipped")
        AssertEq(cfg.Get("Bogus.enabled", ""), "", "unknown section skipped")
        AssertTrue(!InStr(cfg.Get("Craft.craftTarget", ""), "OtherPersonHook"), "a value with a link skipped")
        ; round trip: an export imports back into a fresh install
        ex := Profiles.Export(cfg, "20261113000000")
        cfg2 := Config.Load(src)
        back := Profiles.Import(cfg2, ex.path)
        AssertEq(back.ok, 1, "export imports back")
        AssertEq(cfg2.Get("General.sellEvery", 0), 42, "round trip keeps sellEvery")
        AssertEq(cfg2.Get("General.privateServer", "x"), "", "round trip carries no link")
        AssertEq(cfg2.Get("Remote.token", "x"), "", "round trip carries no token")
        AssertEq(Profiles.Import(cfg2, src "\missing.ini").ok, 0, "a missing file is refused")
        FileAppend("just text`r`n", src "\junk.ini", "UTF-8")
        AssertEq(Profiles.Import(cfg2, src "\junk.ini").msg, "Nothing imported: no settings found in that file", "a file without settings")
    } finally {
        try DirDelete(dir, true)
        try DirDelete(src, true)
    }
}

Test_Profiles_ExportsNeverShipped() {
    root := RegExReplace(A_LineFile, "\\tests\\[^\\]+$", "")
    AssertTrue(Updater.IsProtected("exports\moontide_settings_20261113.ini"), "the updater never overwrites exports\")
    AssertTrue(RegExMatch(FileRead(root "\.gitignore"), "m)^exports/\r?$"), "exports/ in .gitignore")
    AssertTrue(InStr(FileRead(root "\tools\make_release.ps1"), "'^exports/'"), "exports/ left out of releases")
}

Test_Profiles_DashboardPage() {
    dir := PfDir()
    for n in ["biomes", "potions", "quests", "merchants"]
        FileCopy(RegExReplace(A_LineFile, "\\tests\\[^\\]+$", "") "\data\" n ".json", dir "\data\" n ".json", 1)
    d := ""
    try {
        cfg := PfCfg(dir)
        AssertEq(Dashboard.Pages[Dashboard.Pages.Length], "Profiles", "Profiles appended last")
        AssertEq(Dashboard.Builders[Dashboard.Pages.Length], "_PageProfiles", "its builder")
        AssertEq(Dashboard.Pages[Dashboard.LogPage], "Log", "LogPage unchanged")
        AssertEq(Dashboard.HubOf("Profiles"), 5, "in the Setup hub")
        saved := [0]
        d := Dashboard(cfg, Map("saved", (page) => saved[1]++))
        for name in Profiles.Names
            AssertTrue(IsObject(d.Ctrl("profile:" name)), "button " name)
        AssertEq(d.PageOf(d.Ctrl("profile:AFK fishing")), "Profiles", "buttons on the page")
        AssertTrue(IsObject(d.Ctrl("export")) && IsObject(d.Ctrl("import")), "export and import buttons")
        d.SelectPage(Dashboard.PageIndex("Profiles"))
        AssertEq(d.ActiveHub, 5, "Setup hub")
        AssertTrue(d.Ctrl("tab:Profiles").Visible, "Profiles tab shown")
        AssertEq(d.Ctrl("exportShow").Visible, false, "Show it hidden before an export")

        ; cancelled: nothing changes
        asked := []
        d._confirmProfile := (t, b) => (asked.Push(t), false)
        AssertEq(d.ApplyProfile("Memory Match only"), "", "cancel")
        AssertEq(asked.Length, 1, "asked first")
        AssertEq(cfg.Get("MemoryMatch.enabled", 0), 0, "cancel changes nothing")

        ; an unsaved edit on another page is replaced by the profile's value
        d.Ctrl("MemoryMatch.enabled").Value := 0
        d.Ctrl("General.fishing").Value := 1
        d._confirmProfile := (t, b) => true
        msg := d.ApplyProfile("Memory Match only")
        AssertTrue(RegExMatch(msg, "^Applied: Memory Match only \(\d+ settings changed\)$"), "status: " msg)
        AssertEq(d.Ctrl("profileStatus").Text, msg, "shown on the page")
        AssertEq(Config.Load(dir).Get("MemoryMatch.enabled", 0), 1, "saved to settings.ini")
        AssertEq(d.Ctrl("MemoryMatch.enabled").Value, 1, "Obby & Memory page reloaded")
        AssertEq(d.Ctrl("General.fishing").Value, 0, "Fishing page reloaded")
        AssertEq(saved[1], 1, "saved callback fired")
        AssertTrue(InStr(d.LogText(), "Profiles: Applied: Memory Match only"), "logged")

        ; export
        r := d.ExportSettings()
        AssertEq(r.ok, 1, "exported")
        AssertTrue(FileExist(dir "\exports\moontide_settings_" FormatTime(, "yyyyMMdd") ".ini") != "", "file in exports\")
        AssertEq(PfHasSecret(FileRead(r.path, "UTF-8")), "", "dashboard export has no secrets")
        AssertTrue(InStr(d.Ctrl("shareStatus").Text, "Exported "), "status shows the export")
        AssertTrue(d.Ctrl("exportShow").Visible, "Show it shown")
        AssertEq(PfHasSecret(d.LogText()), "", "nothing secret logged")

        ; import (the picker is replaced; "" = cancelled)
        d._pickImport := () => ""
        AssertEq(d.ImportSettings(), "", "cancelled pick")
        FileAppend("[General]`r`nsellEvery=33`r`nprivateServer=https://www.roblox.com/share?code=NOPE`r`n", dir "\in.ini", "UTF-8")
        d._pickImport := () => dir "\in.ini"
        r := d.ImportSettings()
        AssertEq(r.n, 1, "one imported")
        AssertEq(d.Ctrl("shareStatus").Text, "Imported 1 setting (1 skipped)", "import status")
        AssertEq(d.Ctrl("General.sellEvery").Value, "33", "Fishing page shows the import")
        AssertEq(Config.Load(dir).Get("General.privateServer", ""), PfLink(), "own link kept on disk")
        AssertEq(saved[1], 2, "saved callback fired after import")
    } finally {
        UiDashClose(d)
        try DirDelete(dir, true)
    }
}

; bug hunt 2026-11-13: out-of-range numbers are refused, a header with a
; comment still starts its section, the status says what was switched on
Test_Profiles_ImportRangesHeadersAndTurnedOn() {
    dir := A_Temp "\vesper_prof_bh_" A_TickCount
    DirCreate(dir)
    try {
        cfg := Config.Load(dir)
        cfg.Set("MemoryMatch.enabled", 0)
        r := Profiles.ImportText(cfg, "[Recovery]`nafkMin=0`n[MemoryMatch] `; my note`nenabled=1`n[General]`nfishing=0`n")
        AssertTrue(String(cfg.Get("Recovery.afkMin", "")) != "0", "afkMin=0 refused")
        AssertEq(String(cfg.Get("MemoryMatch.enabled", "")), "1", "the commented header kept its section")
        AssertEq(String(cfg.Get("General.fishing", "")), "0", "a switch may be 0")
        AssertTrue(r.on.Length = 1 && r.on[1] = "MemoryMatch.enabled", "what was switched on")
    } finally {
        try DirDelete(dir, true)
    }
}
