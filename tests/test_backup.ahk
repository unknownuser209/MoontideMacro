#Requires AutoHotkey v2.0
; Offline tests for lib\Backup.ahk ("Move to another PC": export / import
; everything) and its buttons on Settings > Profiles. Temp folders under
; A_Temp. Helpers are prefixed Bk.
#Include ..\lib\Backup.ahk
#Include ..\lib\ui\Dashboard.ahk

BkHook() => "https://discord.com/api/webhooks/123456789012345678/BkHookTokenSECRET"
BkHook2() => "https://discord.com/api/webhooks/123456789012345678/BkOtherTokenSECRET"
BkLink() => "https://www.roblox.com/share?code=BKLINKCODE42&type=Server"
BkToken() => "BkBotToken.SECRET.xyz987"
BkSecrets() => [BkHook(), BkHook2(), BkLink(), "BKLINKCODE42", BkToken(), "BkHookTokenSECRET", "BkOtherTokenSECRET", "BkBotToken"]

BkDir(tag := "") {
    d := A_Temp "\vesper_bktest_" tag A_TickCount "_" Random(100000, 999999)
    DirCreate(d "\data")
    return d
}

BkHasSecret(text) {
    for s in BkSecrets()
        if InStr(text, s)
            return s
    return ""
}

BkWrite(path, text) {
    SplitPath(path, , &dir)
    if !DirExist(dir)
        DirCreate(dir)
    f := FileOpen(path, "w", "UTF-8-RAW")
    f.Write(text)
    f.Close()
}

BkWriteBytes(path, bytes) {
    SplitPath(path, , &dir)
    if !DirExist(dir)
        DirCreate(dir)
    buf := Buffer(bytes.Length)
    for i, b in bytes
        NumPut("UChar", b, buf, i - 1)
    f := FileOpen(path, "w")
    f.RawWrite(buf, buf.Size)
    f.Close()
}

; every file under dir: rel path -> contents (read the same way each time)
BkSnap(dir) {
    m := Map()
    if !DirExist(dir)
        return m
    Loop Files, dir "\*", "FR"
        m[SubStr(A_LoopFilePath, StrLen(dir) + 2)] := FileRead(A_LoopFilePath, "RAW").Size "|" FileRead(A_LoopFilePath, "UTF-8")
    return m
}

BkSameSnap(a, b, what) {
    AssertEq(b.Count, a.Count, what ": same number of files")
    for k, v in a {
        AssertTrue(b.Has(k), what ": still has " k)
        AssertTrue(b[k] == v, what ": " k " unchanged")
    }
}

BkSameBytes(p1, p2) {
    a := FileRead(p1, "RAW"), b := FileRead(p2, "RAW")
    if (a.Size != b.Size)
        return false
    Loop a.Size
        if (NumGet(a, A_Index - 1, "UChar") != NumGet(b, A_Index - 1, "UChar"))
            return false
    return true
}

; a macro folder with something in every place a backup reads
BkSource(src, soundPath) {
    cfg := Config.Load(src)
    cfg.Set("General.privateServer", BkLink())
    cfg.Set("General.sellEvery", 22)
    cfg.Set("General.alertSound", soundPath)
    cfg.Set("UI.customPictureFile", "C:\BkNoSuchDir_42\pic.png")
    cfg.Set("UI.theme", "Night run")
    cfg.Set("UI.lang", "de")
    cfg.Set("Remote.enabled", 1)
    cfg.Set("Remote.token", BkToken())
    cfg.Set("Remote.channel", "998877665544332211")
    cfg.Set("Dev.dim", 1)
    cfg.Set("Dev.dimPct", 80)
    cfg.Set("Craft.qty_lucky_potion", 4)
    cfg.Set("Merchant.chatPollSec", 7)
    cfg.Set("Obby.align", "w:300, a:120")
    cfg.Set("General.biomePings", "SINGULARITY=&123,GLITCHED=456")
    cfg.SetWebhooks([Map("name", "Main " Chr(0x1F319), "url", BkHook(), "mention", "<@112233445566778899>", "enabled", 1, "events", "biome,rare")
        , Map("name", "Second", "url", BkHook2(), "mention", "", "enabled", 0, "events", "errors")])
    cfg.Save()
    for rel in Backup.Files {
        if (SubStr(rel, -4) = ".txt")
            BkWrite(src "\" rel, "Aura one`r`nAura " Chr(0x2726) " two`r`n")
        else
            BkWrite(src "\" rel, '{"from": "' StrReplace(rel, "\", "/") '", "n": 1.50, "ok": true, "none": null, "list": [1, 2]}' "`n")
    }
    BkWrite(src "\themes\Night run.moontheme", "[Theme]`nname=Night run`n[Picture]`nfile=Night run.png`n")
    BkWrite(src "\themes\Plain.moontheme", "[Theme]`nname=Plain`n")
    BkWriteBytes(src "\themes\Night run.png", [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 1, 2, 255, 254, 0])
    ; not a theme / not ours: left out
    BkWrite(src "\themes\..notes.txt", "x")
    ; run-time state and logs: never in a backup
    BkWrite(src "\data\last_biome.txt", "NORMAL")
    BkWrite(src "\data\schedule_state.txt", "x")
    BkWrite(src "\data\memory_match_state.json", "{}")
    BkWrite(src "\logs\macro.log", "a line")
    return cfg
}

BkBackupPath(root, tag := "") {
    Loop Files, root "\exports\moontide_backup_" (tag != "" ? tag "_" : "") "*.json"
        if (tag != "" || !InStr(A_LoopFileName, "before_import"))
            return A_LoopFilePath
    return ""
}

Test_Backup_RoundTripEverything() {
    src := BkDir("src"), dst := BkDir("dst"), side := BkDir("side")
    old := Backup.ScreenFn
    try {
        Backup.ScreenFn := () => Map("w", 1920, "h", 1080, "dpi", 96)
        BkWriteBytes(side "\ding.wav", [82, 73, 70, 70, 4, 0, 0, 0, 87, 65, 86, 69, 0, 255])
        scfg := BkSource(src, side "\ding.wav")
        r := Backup.Export(src, "20261126101500")
        AssertEq(r.ok, 1, "exported: " r.msg)
        AssertEq(r.path, src "\exports\moontide_backup_20261126_101500.json", "file name")
        AssertTrue(InStr(r.msg, "moontide_backup_20261126_101500.json"), "message names the file")
        AssertEq(r.files, Backup.Files.Length, "every data file")
        AssertEq(r.themes, 2, "both themes")
        AssertEq(BkHasSecret(r.msg), "", "no value in the message")
        data := Json.Parse(FileRead(r.path, "UTF-8"))
        AssertEq(data["format"], "moontide-backup", "format")
        AssertEq(data["version"], 1, "version")
        AssertEq(data["macroVersion"], Brand.Version, "macro version")
        AssertEq(data["screen"]["w"], 1920, "screen width")
        AssertEq(data["settings"]["General"]["privateServer"], BkLink(), "the private server link is in it")
        AssertEq(data["settings"]["Remote"]["token"], BkToken(), "the bot token is in it")
        AssertEq(data["settings"]["Dev"]["dimPct"], "80", "the Dev section is in it")
        AssertEq(data["settings"]["Webhook.2"]["url"], BkHook2(), "webhooks are in it")
        AssertTrue(data["files"].Has("data\calibration.json"), "calibration in it")
        for bad in ["data\last_biome.txt", "data\schedule_state.txt", "data\memory_match_state.json", "logs\macro.log"]
            AssertTrue(!data["files"].Has(bad), bad " left out")
        AssertTrue(data["themes"].Has("Night run.png") && !data["themes"].Has("..notes.txt"), "theme picture in, other files out")
        AssertTrue(data["extras"].Has("General.alertSound") && !data["extras"].Has("UI.customPictureFile"), "the sound file goes in, a missing picture does not")
        n := 0
        for sec, keys in data["settings"]
            n += keys.Count
        AssertEq(r.n, n, "count = every key")

        ; the other PC has its own settings and a theme of its own
        dcfg := Config.Load(dst)
        dcfg.Set("General.sellEvery", 99)
        dcfg.Set("Only.here", "x")
        dcfg.Save()
        BkWrite(dst "\themes\Keep me.moontheme", "[Theme]`nname=Keep me`n")
        BkWrite(dst "\data\calibration.json", '{"mine": 1}')
        res := Backup.Import(dst, r.path, "20261126111500")
        AssertEq(res.ok, 1, "imported: " res.msg)
        AssertEq(res.n, r.n, "same number of settings")
        AssertEq(res.files, r.files, "same number of files")
        AssertEq(res.themes, 2, "two themes")
        AssertEq(res.screenNote, "", "same screen: no calibration note")
        AssertEq(BkHasSecret(res.msg), "", "no value in the message")

        ; the state before the import was saved first
        AssertEq(res.before, dst "\exports\moontide_backup_before_import_20261126_111500.json", "before-import file")
        pre := Json.Parse(FileRead(res.before, "UTF-8"))
        AssertEq(pre["settings"]["General"]["sellEvery"], "99", "it holds the old settings")
        AssertEq(pre["files"]["data\calibration.json"], '{"mine": 1}', "and the old calibration")
        AssertTrue(pre["themes"].Has("Keep me.moontheme"), "and the old themes")

        ; every setting equal (settings.ini replaced as a whole)
        a := Config.Load(src), b := Config.Load(dst)
        for sec, keys in a.sections {
            AssertTrue(b.sections.Has(sec), "section " sec)
            for k, v in keys {
                if (sec "." k = "General.alertSound" || sec "." k = "UI.customPictureFile")
                    continue
                AssertTrue(b.sections[sec].Has(k) && b.sections[sec][k] == v, sec "." k " equal")
            }
            AssertEq(b.sections[sec].Count, keys.Count, sec ": same keys")
        }
        AssertEq(b.sections.Count, a.sections.Count, "same sections")
        AssertTrue(!b.sections.Has("Only"), "the old PC-only section is gone")
        AssertEq(b.Webhooks().Length, 2, "two webhooks")
        for i, h in a.Webhooks()
            for k in ["name", "url", "mention", "enabled"]
                AssertTrue(b.Webhooks()[i][k] == h[k], "webhook " i " " k)
        AssertEq(UiLogic.ArrayToCsv(b.Webhooks()[1]["events"]), "biome,rare", "webhook events")
        ; paths: the sound came along, the missing picture went back to the default
        AssertEq(b.Get("General.alertSound", ""), dst "\imported\ding.wav", "sound path points at the imported copy")
        AssertTrue(BkSameBytes(side "\ding.wav", dst "\imported\ding.wav"), "sound bytes equal")
        AssertEq(b.Get("UI.customPictureFile", "x"), "", "a picture that is not on this PC: default")
        ; every file byte for byte
        for rel in Backup.Files
            AssertTrue(BkSameBytes(src "\" rel, dst "\" rel), rel " equal")
        for t in ["Night run.moontheme", "Plain.moontheme", "Night run.png"]
            AssertTrue(BkSameBytes(src "\themes\" t, dst "\themes\" t), t " equal")
        AssertTrue(FileExist(dst "\themes\Keep me.moontheme") != "", "a theme only this PC had stays")
        AssertTrue(!FileExist(dst "\data\last_biome.txt"), "no run-time state written")
        ; the round trip again is stable: export the imported folder, same settings
        r2 := Backup.Export(dst, "20261126121500")
        AssertEq(r2.n, r.n, "export of the import: same count")
    } finally {
        Backup.ScreenFn := old
        for d in [src, dst, side]
            try DirDelete(d, true)
    }
}

; every refused file: a message, and nothing written at all (no settings, no
; data, not even the before-import copy)
Test_Backup_BadFilesRejected() {
    dst := BkDir("bad"), tmp := BkDir("badin")
    try {
        cfg := Config.Load(dst)
        cfg.Set("General.sellEvery", 41)
        cfg.Save()
        BkWrite(dst "\data\routes.json", '{"keep": 1}')
        before := BkSnap(dst)
        good := () => Map("format", "moontide-backup", "version", 1, "settings", Map("General", Map("sellEvery", "5"))
            , "files", Map("data\routes.json", '{"new": 1}'), "themes", Map(), "extras", Map())
        cases := Map()
        cases["wrong format"] := (m) => m["format"] := "something-else"
        cases["no format"] := (m) => m.Delete("format")
        cases["newer version"] := (m) => m["version"] := 2
        cases["version text"] := (m) => m["version"] := "one"
        cases["traversal"] := (m) => m["files"]["..\..\x.json"] := "{}"
        cases["traversal in data"] := (m) => m["files"]["data\..\..\settings.json"] := "{}"
        cases["absolute"] := (m) => m["files"]["C:\Windows\x.json"] := "{}"
        cases["unc"] := (m) => m["files"]["\\host\share\x.json"] := "{}"
        cases["unknown file"] := (m) => m["files"]["data\coords.json"] := "{}"
        cases["slash spelling twice"] := (m) => m["files"]["data/ROUTES.json"] := "{}"
        cases["broken data json"] := (m) => m["files"]["data\routes.json"] := '{"a": '
        cases["data not text"] := (m) => m["files"]["data\routes.json"] := Map()
        cases["theme traversal"] := (m) => m["themes"]["..\evil.moontheme"] := Map("text", "x")
        cases["theme absolute"] := (m) => m["themes"]["C:\evil.moontheme"] := Map("text", "x")
        cases["theme exe"] := (m) => m["themes"]["evil.exe"] := Map("b64", "QUJD")
        cases["theme device"] := (m) => m["themes"]["CON.moontheme"] := Map("text", "x")
        cases["theme bad picture"] := (m) => m["themes"]["x.png"] := Map("b64", "not base64 !!")
        cases["extra traversal"] := (m) => m["extras"]["General.alertSound"] := Map("name", "..\..\x.wav", "b64", "QUJD")
        cases["extra exe"] := (m) => m["extras"]["General.alertSound"] := Map("name", "x.exe", "b64", "QUJD")
        cases["extra unknown key"] := (m) => m["extras"]["General.sellEvery"] := Map("name", "x.wav", "b64", "QUJD")
        cases["settings missing"] := (m) => m.Delete("settings")
        cases["settings value a map"] := (m) => m["settings"]["General"]["x"] := Map()
        cases["section bracket"] := (m) => m["settings"]["Gen]eral"] := Map("a", "1")
        cases["key with ="] := (m) => m["settings"]["General"]["a=b"] := "1"
        cases["files not a map"] := (m) => m["files"] := "data\routes.json"
        for name, fn in cases {
            m := good()
            fn(m)
            p := tmp "\" StrReplace(name, " ", "_") ".json"
            BkWrite(p, Json.Stringify(m))
            r := Backup.Import(dst, p, "20261126130000")
            AssertEq(r.ok, 0, name ": refused")
            AssertTrue(InStr(r.msg, "Not imported"), name ": says so: " r.msg)
            BkSameSnap(before, BkSnap(dst), name)
        }
        ; not JSON at all, empty, missing
        BkWrite(tmp "\broken.json", "{this is not json")
        BkWrite(tmp "\empty.json", "")
        for p in [tmp "\broken.json", tmp "\empty.json", tmp "\missing.json", tmp]
            AssertEq(Backup.Import(dst, p, "20261126130000").ok, 0, p ": refused")
        BkSameSnap(before, BkSnap(dst), "broken / missing files")
        ; the good one goes through (the cases above really were the only fault)
        BkWrite(tmp "\good.json", Json.Stringify(good()))
        r := Backup.Import(dst, tmp "\good.json", "20261126130000")
        AssertEq(r.ok, 1, "good file imported: " r.msg)
        AssertEq(Config.Load(dst).Get("General.sellEvery", 0), 5, "its setting")
        AssertEq(FileRead(dst "\data\routes.json", "UTF-8"), '{"new": 1}', "its file")
    } finally {
        try DirDelete(dst, true)
        try DirDelete(tmp, true)
    }
}

; no copy of the current state, no import: an "exports" that is a file (the
; folder cannot be made) stops the import before anything is written
Test_Backup_BeforeImportCopyFirst() {
    src := BkDir("bsrc"), dst := BkDir("bdst")
    try {
        c := Config.Load(src)
        c.Set("General.sellEvery", 12)
        c.Save()
        r := Backup.Export(src, "20261126140000")
        AssertEq(r.ok, 1, "exported")
        d := Config.Load(dst)
        d.Set("General.sellEvery", 77)
        d.Save()
        BkWrite(dst "\exports", "I am a file")
        before := BkSnap(dst)
        res := Backup.Import(dst, r.path, "20261126140100")
        AssertEq(res.ok, 0, "refused without the copy")
        AssertTrue(InStr(res.msg, "could not be saved first"), "says why: " res.msg)
        BkSameSnap(before, BkSnap(dst), "nothing written")
        FileDelete(dst "\exports")
        res := Backup.Import(dst, r.path, "20261126140100")
        AssertEq(res.ok, 1, "imported with the copy")
        AssertEq(Json.Parse(FileRead(res.before, "UTF-8"))["settings"]["General"]["sellEvery"], "77", "the copy holds the old value")
        AssertEq(Config.Load(dst).Get("General.sellEvery", 0), 12, "new value written after")
        AssertTrue(FileGetTime(res.before, "M") <= FileGetTime(dst "\settings.ini", "M"), "copy made before settings.ini was written")
    } finally {
        try DirDelete(src, true)
        try DirDelete(dst, true)
    }
}

Test_Backup_ScreenMismatchNote() {
    old := Backup.ScreenFn
    try {
        Backup.ScreenFn := () => Map("w", 2560, "h", 1440, "dpi", 144)
        AssertEq(Backup.ScreenNote(Map("w", 2560, "h", 1440, "dpi", 144)), "", "same screen: nothing")
        AssertEq(Backup.ScreenNote(""), "", "no screen in the file: nothing")
        AssertEq(Backup.ScreenNote(Map("w", "x")), "", "a broken screen entry: nothing")
        n := Backup.ScreenNote(Map("w", 1920, "h", 1080, "dpi", 96))
        AssertTrue(InStr(n, "1920x1080") && InStr(n, "100%") && InStr(n, "2560x1440") && InStr(n, "150%"), "names both screens: " n)
        AssertTrue(InStr(n, "Test my calibration"), "says where to check")
        AssertTrue(Backup.ScreenNote(Map("w", 2560, "h", 1440, "dpi", 96)) != "", "another scale alone counts")
        ; through an import: still imported, with the note
        src := BkDir("ssrc"), dst := BkDir("sdst")
        try {
            Backup.ScreenFn := () => Map("w", 1366, "h", 768, "dpi", 120)
            BkWrite(src "\data\calibration.json", '{"steps": {}}')
            r := Backup.Export(src, "20261126150000")
            Backup.ScreenFn := () => Map("w", 1920, "h", 1080, "dpi", 96)
            res := Backup.Import(dst, r.path, "20261126150100")
            AssertEq(res.ok, 1, "imported anyway")
            AssertTrue(InStr(res.screenNote, "1366x768") && InStr(res.screenNote, "125%"), "note: " res.screenNote)
            AssertEq(FileRead(dst "\data\calibration.json", "UTF-8"), '{"steps": {}}', "calibration written")
        } finally {
            try DirDelete(src, true)
            try DirDelete(dst, true)
        }
    } finally {
        Backup.ScreenFn := old
    }
}

; the buttons, the question, the refusal while running, the restart and the
; log: only counts are logged, never a value
Test_Backup_DashboardButtons() {
    src := BkDir("dsrc"), dst := BkDir("ddst"), side := BkDir("dside")
    for n in ["biomes", "potions", "quests", "merchants"] {
        FileCopy(RegExReplace(A_LineFile, "\\tests\\[^\\]+$", "") "\data\" n ".json", src "\data\" n ".json", 1)
        FileCopy(RegExReplace(A_LineFile, "\\tests\\[^\\]+$", "") "\data\" n ".json", dst "\data\" n ".json", 1)
    }
    old := Backup.ScreenFn
    d := "", d2 := ""
    try {
        Backup.ScreenFn := () => Map("w", 1920, "h", 1080, "dpi", 96)
        BkWriteBytes(side "\ding.wav", [1, 2, 3])
        BkSource(src, side "\ding.wav")
        flushed := [0]
        d := Dashboard(Config.Load(src), Map("backupFlush", () => flushed[1]++))
        shown := []
        d._reveal := (p) => shown.Push(p)
        for id in ["backupWarn", "backupExport", "backupImport", "backupStatus"]
            AssertEq(d.PageOf(d.Ctrl(id)), "Profiles", id " on Settings > Profiles")
        AssertTrue(InStr(d.Ctrl("backupWarn").Text, "Never share it"), "the warning shows")
        ; inside the new card, under Share settings, nothing on top of another
        d.SelectPage(Dashboard.PageIndex("Profiles"))
        card := UiDashPos(d.Ctrl("panel:Profiles:Move to another PC"))
        share := UiDashPos(d.Ctrl("panel:Profiles:Share settings"))
        AssertTrue(share.y + share.h <= card.y, "cards do not overlap")
        AssertTrue(card.y + card.h <= 620, "card inside the page area")
        ids := ["backupWarn", "backupExport", "backupImport", "backupStatus"]
        for i, id in ids {
            p := UiDashPos(d.Ctrl(id))
            AssertTrue(p.x >= card.x && p.y >= card.y && p.x + p.w <= card.x + card.w && p.y + p.h <= card.y + card.h, id " inside its card")
            for j, o in ids {
                q := UiDashPos(d.Ctrl(o))
                if (i < j)
                    AssertTrue(p.x + p.w <= q.x || q.x + q.w <= p.x || p.y + p.h <= q.y || q.y + q.h <= p.y, id " and " o " do not overlap")
            }
        }
        r := d.ExportEverything()
        AssertEq(r.ok, 1, "exported: " r.msg)
        AssertEq(flushed[1], 1, "the app wrote its counters first")
        AssertEq(shown.Length, 1, "shown in Explorer")
        AssertEq(shown[1], r.path, "the file shown")
        AssertEq(d.Ctrl("backupStatus").Text, r.msg, "status")
        AssertTrue(InStr(d.LogText(), "Backup: exported " r.n " settings, " r.files " files, 2 themes"), "counts logged")
        UiDashClose(d), d := ""

        ; the other PC: refused while the macro runs (nothing asked or picked)
        busy := ["busy"], picked := [0], asked := [], restarted := [0], saved := [0]
        d2 := Dashboard(Config.Load(dst), Map("backupBusy", () => busy[1], "backupImported", () => restarted[1]++
            , "saved", (pg) => saved[1]++))
        d2._pickBackup := () => (picked[1]++, r.path)
        d2._confirmBackup := (t, b) => (asked.Push(b), false)
        res := d2.ImportEverything()
        AssertEq(res.ok, 0, "refused while running")
        AssertEq(picked[1], 0, "no file picked")
        AssertTrue(InStr(d2.Ctrl("backupStatus").Text, "Stop the macro first"), "says so")
        ; stopped: cancelled at the question, nothing written
        busy[1] := ""
        snap := BkSnap(dst)
        AssertEq(d2.ImportEverything(), "", "cancelled at the question")
        AssertEq(asked.Length, 1, "asked")
        AssertTrue(InStr(asked[1], "saved in the exports folder first"), "the question says a copy is made")
        BkSameSnap(snap, BkSnap(dst), "cancel writes nothing")
        ; cancelled pick
        d2._pickBackup := () => ""
        AssertEq(d2.ImportEverything(), "", "cancelled pick")
        ; another screen: the question carries the note; yes imports
        Backup.ScreenFn := () => Map("w", 2560, "h", 1440, "dpi", 96)
        d2._confirmBackup := (t, b) => (asked.Push(b), true)
        res := d2.ImportEverything(r.path)
        AssertEq(res.ok, 1, "imported: " res.msg)
        AssertTrue(InStr(asked[2], "1920x1080") && InStr(asked[2], "Test my calibration"), "the calibration note in the question")
        AssertEq(d2.cfg.Get("General.sellEvery", 0), 22, "the dashboard's settings reloaded")
        AssertEq(d2.cfg.Get("General.privateServer", ""), BkLink(), "the link came along")
        AssertEq(d2.Ctrl("General.sellEvery").Value, "22", "the Fishing page shows it")
        AssertEq(restarted[1], 1, "the app restarts")
        AssertEq(saved[1], 1, "saved fired")
        AssertEq(d2.Ctrl("backupStatus").Text, res.msg, "status")
        log := d2.LogText()
        AssertTrue(InStr(log, "Backup: imported " res.n " settings, " res.files " files, 2 themes"), "counts logged")
        AssertTrue(InStr(log, "calibration may need redoing"), "calibration note logged")
        AssertEq(BkHasSecret(log), "", "no value in the log")
        AssertEq(BkHasSecret(d2.Ctrl("backupStatus").Text), "", "no value in the status")
        ; a bad file through the dashboard: refused, logged without detail
        BkWrite(side "\bad.json", '{"format": "moontide-backup", "version": 1, "settings": {}, "files": {"..\\\\x.json": "{}"}}')
        res := d2.ImportEverything(side "\bad.json")
        AssertEq(res.ok, 0, "bad file refused")
        AssertTrue(InStr(d2.Ctrl("backupStatus").Text, "may not write"), "status says why")
        AssertEq(restarted[1], 1, "no restart for a refused file")
    } finally {
        Backup.ScreenFn := old
        UiDashClose(d)
        UiDashClose(d2)
        for dd in [src, dst, side]
            try DirDelete(dd, true)
    }
}

; Backup's messages (built in lib\, outside the UI coverage scan) are in
; every language; the App answers the three dashboard calls
Test_Backup_TranslatedAndWired() {
    keys := ["Saved {1} settings, {2} files and {3} themes to exports\{4}", "your settings could not be read or the file could not be written"
        , "the file is too big", "this is not a Moontide backup file", "the backup was made by a newer version of the macro"
        , "the settings in the backup are broken", "the backup holds a file it may not write", "a data file in the backup is broken"
        , "a theme in the backup is broken", "your current settings could not be saved first"
        , "Import stopped partway. Your old settings are in exports\{1}: import that file to go back."
        , "Imported {1} settings, {2} files and {3} themes. Your old ones are in exports\{4}."
        , "The backup was made on a {1}x{2} screen at {3}%, this PC is {4}x{5} at {6}%. Your calibration may need redoing: Help > Check & help > Test my calibration."
        , "Not imported: {1}", "Not exported: {1}", "Not imported: the file could not be read"]
    for code in I18n.Codes {
        if (code = "en")
            continue
        m := I18n.LoadFile(code)
        for k in keys
            AssertTrue(m.Has(k), code ".json has '" k "'")
    }
    try {
        I18n.Use("de")
        AssertTrue(!InStr(Backup._Bad("the file is too big").msg, "too big"), "a refusal in German")
    } finally {
        I18n.Use("en")
    }
    root := RegExReplace(A_LineFile, "\\tests\\[^\\]+$", "")
    app := FileRead(root "\lib\App.ahk", "UTF-8")
    for s in ['"backupBusy", () => this.BackupBusy()', '"backupFlush", () => this.OnBackupFlush()', '"backupImported", () => this.OnBackupImported()']
        AssertTrue(InStr(app, s), "App wires " s)
    AssertTrue(Updater.IsProtected("imported\ding.wav") && Updater.IsProtected("exports\moontide_backup_x.json"), "the updater leaves imported\ and exports\ alone")
    AssertTrue(RegExMatch(FileRead(root "\.gitignore"), "m)^imported/\r?$"), "imported/ in .gitignore")
    ; the backup's own file list never names run-time state
    for rel in Backup.Files {
        AssertTrue(Updater.IsProtected(rel), rel " is a file updates keep")
        AssertTrue(!RegExMatch(rel, "i)state|last_biome|summary_last|update_skip|whatsnew|cal_health"), rel " is not run-time state")
    }
}

Test_Backup_SafeRel() {
    for r in ["data\calibration.json", "themes\My theme (2).moontheme", "imported\ding.wav"]
        AssertTrue(Backup.SafeRel(r), r " ok")
    for r in ["", "..\x", "data\..\..\x", "C:\x\y.json", "\x\y.json", "\\host\s\x", "data/x.json", "x.json", " data\x.json", ".\data\x.json", "data\x:y.json"]
        AssertTrue(!Backup.SafeRel(r), "'" r "' refused")
    buf := Buffer(3)
    NumPut("UChar", 0, buf, 0), NumPut("UChar", 200, buf, 1), NumPut("UChar", 255, buf, 2)
    back := Backup.B64Decode(Backup.B64Encode(buf))
    AssertTrue(IsObject(back) && back.Size = 3 && NumGet(back, 1, "UChar") = 200 && NumGet(back, 2, "UChar") = 255, "base64 round trip")
    AssertEq(Backup.B64Decode("no!"), "", "not base64")
    AssertEq(Backup.B64Decode(Map()), "", "not text")
}

Test_Config_ReloadReadsTheFileAgain() {
    dir := BkDir("cfg")
    try {
        cfg := Config.Load(dir)
        AssertEq(cfg.Get("General.sellEvery", 0), 15, "default")
        BkWrite(dir "\data\biomes.json", '{"x": 1}')
        AssertEq(cfg.Data("biomes")["x"], 1, "data read")
        other := Config.Load(dir)
        other.Set("General.sellEvery", 31)
        other.SetWebhooks([Map("name", "W", "url", BkHook(), "enabled", 1, "events", "rare")])
        other.Save()
        BkWrite(dir "\data\biomes.json", '{"x": 2}')
        cfg.Reload()
        AssertEq(cfg.Get("General.sellEvery", 0), 31, "setting read again")
        AssertEq(cfg.Webhooks().Length, 1, "webhooks read again")
        AssertEq(cfg.Data("biomes")["x"], 2, "data read again")
    } finally {
        try DirDelete(dir, true)
    }
}
