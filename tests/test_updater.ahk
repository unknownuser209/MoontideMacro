#Requires AutoHotkey v2.0
; Tests for lib\Updater.ahk. Offline: http / download / unzip are fakes; files
; live in a temp dir under A_Temp, never the repo.
#Include ..\lib\Updater.ahk
#Include ..\lib\Config.ahk
#Include ..\lib\ui\Dashboard.ahk
#Include ..\lib\ui\WhatsNew.ahk

; ---- helpers (names must not start with Test_) -----------------------------

UpdTmp() {
    d := A_Temp "\vesper_updtest_" A_TickCount "_" Random(100000, 999999)
    DirCreate(d)
    return d
}

UpdPut(path, text) {
    DirCreate(RegExReplace(path, "\\[^\\]*$"))
    try FileDelete(path)
    FileAppend(text, path, "UTF-8-RAW")
}

UpdGet(path) => FileExist(path) ? FileRead(path, "UTF-8") : "<missing>"

; Installed program: old Vesper.ahk + user files.
UpdMakeRoot() {
    r := UpdTmp()
    UpdPut(r "\Vesper.ahk", "old main")
    UpdPut(r "\lib\App.ahk", "old app")
    UpdPut(r "\settings.ini", "USER settings")
    UpdPut(r "\data\routes.json", "USER routes")
    UpdPut(r "\data\calibration.json", "USER calib")
    UpdPut(r "\data\memory_match_state.json", "USER state")
    UpdPut(r "\data\auras_had.txt", "USER auras")
    UpdPut(r "\logs\macro.log", "USER log")
    return r
}

; Fake unzip: writes the "release" into dest. wrap = top folder like a zipball.
UpdFakeUnzip(wrap := "", withMain := true) {
    return (zip, dest) => UpdFill(wrap != "" ? dest "\" wrap : dest, withMain)
}

UpdFill(dest, withMain) {
    if withMain
        UpdPut(dest "\Vesper.ahk", "new main")
    UpdPut(dest "\lib\App.ahk", "new app")
    UpdPut(dest "\lib\Updater.ahk", "new file")
    UpdPut(dest "\settings.ini", "ZIP settings")
    UpdPut(dest "\data\routes.json", "ZIP routes")
    UpdPut(dest "\data\calibration.json", "ZIP calib")
    UpdPut(dest "\data\memory_match_state.json", "ZIP state")
    UpdPut(dest "\data\auras_had.txt", "ZIP auras")
    UpdPut(dest "\data\default_routes.json", "ZIP default routes")
    UpdPut(dest "\logs\macro.log", "ZIP log")
    UpdPut(dest "\backup\1.0\x.txt", "ZIP backup")
}

UpdRelease(tag, zipUrl := "https://github.com/o/r/releases/download/v9/M.zip", zipball := "https://api.github.com/repos/o/r/zipball/v9") {
    return '{"tag_name":"' tag '","zipball_url":"' zipball '","assets":[{"name":"notes.txt","browser_download_url":"https://github.com/o/r/notes.txt"},{"name":"M.zip","browser_download_url":"' zipUrl '"}]}'
}

; Updater with fakes. o: Map of overrides. Returns [updater, calls Map].
UpdMake(root, o := "") {
    calls := Map("http", 0, "download", 0, "restart", 0, "logs", [], "urls", [])
    d := Map("root", root, "version", "1.0", "repo", "o/r")
    d["http"] := (url) => (calls["http"]++, calls["urls"].Push(url), calls["reply"])
    d["download"] := (url, dest) => (calls["download"]++, calls["urls"].Push(url), UpdPut(dest, "zip"))
    d["unzip"] := UpdFakeUnzip()
    d["log"] := (t) => calls["logs"].Push(t)
    d["restart"] := () => calls["restart"]++
    calls["reply"] := UpdRelease("v1.1.0")
    if (o is Map) {
        for k, v in o
            d[k] := v
    }
    return [Updater(d), calls]
}

UpdClean(r) {
    try DirDelete(r, true)
}

UpdThrowing(*) {
    throw Error("boom")
}

; ---- versions ----------------------------------------------------------------

Test_Updater_Versions() {
    AssertEq(Updater.Compare("v1.1", "1.0"), 1, "newer minor")
    AssertEq(Updater.Compare("1.0.1", "1.0"), 1, "newer patch")
    AssertEq(Updater.Compare("v2", "1.9.9"), 1, "newer major")
    AssertEq(Updater.Compare("v0.9", "1.0"), -1, "older")
    AssertEq(Updater.Compare("v1.0.0", "1.0"), 0, "equal")
    AssertEq(Updater.Compare("v1.10", "v1.9"), 1, "numeric not text order")
    for bad in ["", "latest", "v1.x", "1.2.3.4", "v-1", "1.0-beta", "release 2"]
        AssertEq(Updater.Compare(bad, "1.0"), "", "garbage tag <" bad ">")
}

Test_Updater_CheckNewerOlderEqualGarbage() {
    r := UpdTmp()
    try {
        for t in [["v1.1.0", "available"], ["1.0", "uptodate"], ["v0.5", "uptodate"], ["nightly", "error"]] {
            m := UpdMake(r)
            m[2]["reply"] := UpdRelease(t[1])
            res := m[1].Check()
            AssertEq(res["status"], t[2], "status for " t[1])
        }
        m := UpdMake(r)
        res := m[1].Check()
        AssertEq(res["version"], "1.1.0", "available version")
        AssertEq(res["url"], "https://github.com/o/r/releases/download/v9/M.zip", "prefers the .zip asset")
        AssertEq(m[2]["urls"][1], "https://api.github.com/repos/o/r/releases/latest", "api url")
    } finally {
        UpdClean(r)
    }
}

Test_Updater_ZipballFallback() {
    r := UpdTmp()
    try {
        m := UpdMake(r)
        m[2]["reply"] := '{"tag_name":"v2.0","zipball_url":"https://api.github.com/repos/o/r/zipball/v2.0","assets":[]}'
        res := m[1].Check()
        AssertEq(res["url"], "https://api.github.com/repos/o/r/zipball/v2.0", "zipball fallback")
    } finally {
        UpdClean(r)
    }
}

; The real web call and unzip are static methods: passed as plain values
; they kept the hidden `this` and every real check failed with "Missing a
; required parameter" (a friend's log, 2026-11-11). Fakes hid it.
Test_Updater_RealHelpersTakeTheirOwnArgs() {
    u := Updater(Map("root", A_Temp))
    AssertEq(u._http.MinParams, 1, "http(url)")
    AssertEq(u._unzip.MinParams, 2, "unzip(zip, dest)")
}

Test_Updater_EmptyRepoDoesNothing() {
    r := UpdTmp()
    try {
        m := UpdMake(r, Map("repo", ""))
        AssertEq(m[1].Check()["status"], "disabled", "auto check")
        AssertEq(m[1].Check(true)["status"], "disabled", "manual check")
        AssertEq(m[2]["http"], 0, "no request")
        AssertEq(m[2]["logs"].Length, 0, "says nothing")
        AssertTrue(!m[1].Enabled, "not enabled")
    } finally {
        UpdClean(r)
    }
}

Test_Updater_CheckOncePerStartAndErrorsLogOnce() {
    r := UpdTmp()
    try {
        m := UpdMake(r, Map("http", UpdThrowing))
        AssertEq(m[1].Check()["status"], "error", "network error does not throw")
        AssertEq(m[1].Check()["status"], "skipped", "second auto check skipped")
        AssertEq(m[2]["logs"].Length, 1, "logged once")
        m2 := UpdMake(r, Map("check", 0))
        AssertEq(m2[1].Check()["status"], "skipped", "check=0")
        AssertEq(m2[2]["http"], 0, "check=0 makes no request")
        AssertEq(m2[1].Check(true)["status"], "available", "manual check ignores check=0")
        m3 := UpdMake(r)
        m3[2]["reply"] := "not json"
        AssertEq(m3[1].Check()["status"], "error", "bad json")
        m4 := UpdMake(r, Map("repo", "no-slash"))
        AssertEq(m4[1].Check()["status"], "error", "bad repo setting")
        AssertEq(m4[2]["http"], 0, "bad repo: no request")
    } finally {
        UpdClean(r)
    }
}

; ---- install -------------------------------------------------------------------

Test_Updater_RejectsNonGithubUrl() {
    r := UpdMakeRoot()
    try {
        for u in ["http://github.com/o/r/M.zip", "https://evil.example.com/M.zip", "https://github.com.evil.com/M.zip"
            , "https://github.com@evil.com/M.zip", "ftp://github.com/M.zip", "https://notgithub.com/M.zip"] {
            m := UpdMake(r)
            res := m[1].Install(Map("url", u, "tag", "v1.1"))
            AssertTrue(!res["ok"], "refused " u)
            AssertEq(m[2]["download"], 0, "no download for " u)
            AssertEq(m[2]["restart"], 0, "no restart for " u)
        }
        for u in ["https://github.com/o/r/M.zip", "https://api.github.com/repos/o/r/zipball/v1", "https://codeload.github.com/o/r/zip/v1"
            , "https://objects.githubusercontent.com/x/M.zip"]
            AssertTrue(Updater.IsAllowedUrl(u), "allowed " u)
        AssertEq(UpdGet(r "\Vesper.ahk"), "old main", "untouched")
    } finally {
        UpdClean(r)
    }
}

Test_Updater_InstallKeepsUserFiles() {
    r := UpdMakeRoot()
    try {
        m := UpdMake(r)
        res := m[1].Install(Map("url", "https://github.com/o/r/M.zip", "tag", "v1.1"))
        AssertTrue(res["ok"], "install ok")
        AssertEq(UpdGet(r "\Vesper.ahk"), "new main", "program updated")
        AssertEq(UpdGet(r "\lib\App.ahk"), "new app", "lib updated")
        AssertEq(UpdGet(r "\lib\Updater.ahk"), "new file", "new program file added")
        AssertEq(UpdGet(r "\data\default_routes.json"), "ZIP default routes", "new data file added")
        AssertEq(UpdGet(r "\settings.ini"), "USER settings", "settings.ini kept")
        AssertEq(UpdGet(r "\data\routes.json"), "USER routes", "routes kept")
        AssertEq(UpdGet(r "\data\calibration.json"), "USER calib", "calibration kept")
        AssertEq(UpdGet(r "\data\memory_match_state.json"), "USER state", "state json kept")
        AssertEq(UpdGet(r "\data\auras_had.txt"), "USER auras", "auras_had kept")
        AssertEq(UpdGet(r "\logs\macro.log"), "USER log", "logs kept")
        AssertTrue(!FileExist(r "\backup\1.0\x.txt"), "backup\ from the zip ignored")
        AssertEq(UpdGet(r "\backup\1.0\Vesper.ahk"), "old main", "old program backed up")
        AssertEq(UpdGet(r "\backup\1.0\lib\App.ahk"), "old app", "old lib backed up")
        AssertTrue(!FileExist(r "\backup\1.0\settings.ini"), "user files are not in the backup")
        AssertEq(m[2]["restart"], 1, "restarted")
        AssertTrue(!DirExist(r "\update_tmp"), "temp folder removed")
    } finally {
        UpdClean(r)
    }
}

Test_Updater_ZipballTopFolder() {
    r := UpdMakeRoot()
    try {
        m := UpdMake(r, Map("unzip", UpdFakeUnzip("o-r-abc123")))
        res := m[1].Install(Map("url", "https://api.github.com/repos/o/r/zipball/v1.1", "tag", "v1.1"))
        AssertTrue(res["ok"], "install ok")
        AssertEq(UpdGet(r "\Vesper.ahk"), "new main", "wrapped zip installed")
    } finally {
        UpdClean(r)
    }
}

Test_Updater_MissingMainAborts() {
    r := UpdMakeRoot()
    try {
        m := UpdMake(r, Map("unzip", UpdFakeUnzip("", false)))
        res := m[1].Install(Map("url", "https://github.com/o/r/M.zip", "tag", "v1.1"))
        AssertTrue(!res["ok"], "aborted")
        AssertEq(UpdGet(r "\Vesper.ahk"), "old main", "main untouched")
        AssertEq(UpdGet(r "\lib\App.ahk"), "old app", "lib untouched")
        AssertTrue(!FileExist(r "\lib\Updater.ahk"), "nothing added")
        AssertEq(m[2]["restart"], 0, "no restart")
        AssertTrue(!DirExist(r "\update_tmp"), "temp folder removed")
    } finally {
        UpdClean(r)
    }
}

Test_Updater_FailureRestoresBackup() {
    r := UpdMakeRoot()
    try {
        n := [0]
        ; fail on the 5th copy: backups are done, the new files are half copied
        cp := (s, t) => (++n[1] = 5 ? UpdThrowing() : FileCopy(s, t, 1))
        m := UpdMake(r, Map("copyFile", cp))
        res := m[1].Install(Map("url", "https://github.com/o/r/M.zip", "tag", "v1.1"))
        AssertTrue(!res["ok"], "failed")
        AssertTrue(n[1] >= 5, "reached the failing copy")
        AssertEq(UpdGet(r "\Vesper.ahk"), "old main", "main restored")
        AssertEq(UpdGet(r "\lib\App.ahk"), "old app", "lib restored")
        AssertTrue(!FileExist(r "\lib\Updater.ahk"), "added file removed")
        AssertTrue(!FileExist(r "\data\default_routes.json"), "added data file removed")
        AssertEq(UpdGet(r "\settings.ini"), "USER settings", "user file intact")
        AssertEq(m[2]["restart"], 0, "no restart")
        AssertTrue(!DirExist(r "\update_tmp"), "temp folder removed")
    } finally {
        UpdClean(r)
    }
}

Test_Updater_DownloadFailureKeepsOldVersion() {
    r := UpdMakeRoot()
    try {
        m := UpdMake(r, Map("download", UpdThrowing))
        res := m[1].Install(Map("url", "https://github.com/o/r/M.zip", "tag", "v1.1"))
        AssertTrue(!res["ok"], "failed")
        AssertEq(UpdGet(r "\Vesper.ahk"), "old main", "untouched")
        AssertEq(m[2]["restart"], 0, "no restart")
    } finally {
        UpdClean(r)
    }
}

Test_Updater_OnlyWhenStopped() {
    r := UpdMakeRoot()
    try {
        running := [true]
        m := UpdMake(r, Map("isStopped", () => !running[1]))
        info := Map("url", "https://github.com/o/r/M.zip", "tag", "v1.1")
        res := m[1].Install(info)
        AssertTrue(!res["ok"], "refused while running")
        AssertEq(m[2]["download"], 0, "no download while running")
        AssertEq(UpdGet(r "\Vesper.ahk"), "old main", "untouched while running")
        running[1] := false
        AssertTrue(m[1].Install(info)["ok"], "installs once stopped")
        AssertEq(UpdGet(r "\Vesper.ahk"), "new main", "updated once stopped")
    } finally {
        UpdClean(r)
    }
}

Test_Updater_ProtectedPaths() {
    for p in ["settings.ini", "Settings.INI", "data\calibration.json", "data/routes.json", "data\quests.json", "data\merchants.json"
        , "data\potions.json", "data\biomes.json", "data\auras_had.txt", "data\biome_items_state.json", "data\auras_learnt.json", "data\aura_hints.json", "logs\a.log", "backup\1.0\Vesper.ahk"]
        AssertTrue(Updater.IsProtected(p), "protected " p)
    for p in ["Vesper.ahk", "lib\App.ahk", "data\default_routes.json", "data\coords.json", "data\auras.json", "data\auras_abilities.json", "assets\ui\moon_0.png"]
        AssertTrue(!Updater.IsProtected(p), "not protected " p)
}

; ---- config + dashboard ----------------------------------------------------------

Test_Updater_ConfigDefaults() {
    r := UpdTmp()
    try {
        cfg := Config.Load(r)
        AssertEq(cfg.Get("Update.repo", "x"), "unknownuser209/MoontideMacro", "follows the public repo by default")
        AssertEq(cfg.Get("Update.check", 0), 1, "check on by default")
        AssertEq(cfg.Get("Update.auto", 1), 0, "auto off by default")
    } finally {
        UpdClean(r)
    }
}

Test_Updater_DashboardNotice() {
    r := UpdTmp()
    d := "", d0 := ""
    try {
        DirCreate(r "\data")
        src := RegExReplace(A_LineFile, "\\tests\\[^\\]+$", "") "\data"
        for n in ["biomes", "potions", "quests", "merchants"]
            FileCopy(src "\" n ".json", r "\data\" n ".json", 1)
        d0 := Dashboard(Config.Load(r), Map())
        d0.SetUpdate("9.9.9")           ; no [Update] repo: no panel, no error
        d0.Destroy()
        d0 := ""
        UpdPut(r "\settings.ini", "[Update]`r`nrepo=o/r`r`n")
        d := Dashboard(Config.Load(r), Map())
        AssertTrue(d._hidden.Has(d._updInstall.Hwnd), "install hidden at first")
        d.SetUpdate("1.2.3")
        AssertEq(d._updMsg.Text, "Update available: v1.2.3", "notice text")
        AssertTrue(!d._hidden.Has(d._updInstall.Hwnd), "install offered")
        d.SetUpdate("")
        AssertTrue(d._hidden.Has(d._updInstall.Hwnd), "install hidden again")
    } finally {
        if IsObject(d0)
            d0.Destroy()
        if IsObject(d)
            d.Destroy()
        UpdClean(r)
    }
}

; ---- what's new + go back (safer updates) ------------------------------------------

UpdReadJson(path) => Json.Parse(FileRead(path, "UTF-8"))

UpdHas(arr, v) {
    for x in arr {
        if (x = v)
            return true
    }
    return false
}

; Release with notes; the zip also adds a file in a new folder.
UpdInstallWithNotes(r, body := "## Fixes`n- **Faster** rejoin`n- ``F1`` works") {
    m := UpdMake(r, Map("unzip", (zip, dest) => (UpdFill(dest, true), UpdPut(dest "\assets\new\a.png", "new asset"))))
    m[2]["reply"] := '{"tag_name":"v1.1.0","body":' Json.Stringify(body, 0) ',"assets":[{"name":"M.zip","browser_download_url":"https://github.com/o/r/releases/download/v9/M.zip"}]}'
    info := m[1].Check(true)
    AssertEq(info["status"], "available", "release found")
    res := m[1].Install(info)
    AssertTrue(res["ok"], "install ok")
    return m
}

Test_Updater_InstallWritesManifestAndWhatsNew() {
    r := UpdMakeRoot()
    try {
        UpdInstallWithNotes(r)
        AssertTrue(FileExist(r "\backup\1.0\manifest.json"), "manifest written")
        mf := UpdReadJson(r "\backup\1.0\manifest.json")
        AssertEq(mf["from"], "1.0", "from")
        AssertEq(mf["to"], "1.1.0", "to")
        AssertTrue(UpdHas(mf["replaced"], "Vesper.ahk") && UpdHas(mf["replaced"], "lib\App.ahk"), "replaced files listed")
        AssertTrue(UpdHas(mf["added"], "lib\Updater.ahk") && UpdHas(mf["added"], "data\default_routes.json"), "added files listed")
        AssertTrue(UpdHas(mf["added"], "assets\new\a.png"), "file in a new folder listed")
        AssertTrue(!UpdHas(mf["replaced"], "settings.ini") && !UpdHas(mf["added"], "settings.ini"), "user files not listed")
        wn := UpdReadJson(r "\data\whatsnew.json")
        AssertEq(wn["version"], "1.1.0", "whatsnew version")
        AssertEq(wn["tag"], "v1.1.0", "whatsnew tag")
        AssertTrue(InStr(wn["notes"], "**Faster** rejoin"), "release notes saved as they came")
        AssertEq(UpdGet(r "\settings.ini"), "USER settings", "settings kept")
    } finally {
        UpdClean(r)
    }
}

Test_Updater_TakeWhatsNewOnceAndOnlyForThisVersion() {
    r := UpdTmp()
    try {
        AssertEq(Updater.TakeWhatsNew(r, "1.1"), "", "no file")
        UpdPut(r "\data\whatsnew.json", '{"version":"1.1.0","tag":"v1.1.0","notes":"- a"}')
        wn := Updater.TakeWhatsNew(r, "1.1")
        AssertTrue(IsObject(wn), "1.1.0 matches Brand-style 1.1")
        AssertEq(wn["notes"], "- a", "notes")
        AssertTrue(!FileExist(r "\data\whatsnew.json"), "deleted after it is shown")
        AssertEq(Updater.TakeWhatsNew(r, "1.1"), "", "shown once")
        UpdPut(r "\data\whatsnew.json", '{"version":"1.2","notes":"x"}')
        AssertEq(Updater.TakeWhatsNew(r, "1.1"), "", "other version not shown")
        AssertTrue(!FileExist(r "\data\whatsnew.json"), "other version deleted")
        UpdPut(r "\data\whatsnew.json", 'not json')
        AssertEq(Updater.TakeWhatsNew(r, "1.1"), "", "garbage not shown")
        AssertTrue(!FileExist(r "\data\whatsnew.json"), "garbage deleted")
        AssertTrue(Updater.IsProtected("data\whatsnew.json"), "a release zip never overwrites it")
    } finally {
        UpdClean(r)
    }
}

Test_Updater_NotesTextPlain() {
    md := "# Moontide v1.8`r`n`r`n`r`n## What's new`r`n* **Faster** rejoin`r`n- Fixed ``F1`` key`r`n  - nested [link](https://x.y/z)`r`n---`r`n#12 stays`r`nDone"
    want := "Moontide v1.8`r`n`r`nWhat's new`r`n- Faster rejoin`r`n- Fixed F1 key`r`n  - nested link`r`n`r`n#12 stays`r`nDone"
    AssertEq(Updater.NotesText(md), want, "markdown stripped, bullets kept")
    AssertEq(Updater.NotesText(""), "", "empty")
    long := ""
    loop 900
        long .= "- line " A_Index "`n"
    AssertTrue(StrLen(Updater.NotesText(long)) <= Updater.NotesMax + 3, "capped")
}

Test_Updater_WhatsNewWindow() {
    w := WhatsNewWindow("1.8", "## Hi`n- **one**")
    try {
        AssertEq(w.Title, "What's new in v1.8", "title")
        AssertEq(w.Text, "Hi`r`n- one", "plain text")
        AssertEq(w._box.Value, "Hi`n- one", "shown in the box (Value gives `n line ends)")
        AssertEq(w._gui.Title, "What's new in v1.8", "window caption")
    } finally {
        w.Close()
    }
    AssertEq(WhatsNewWindow("1.8", "").Text, "No notes came with this version.", "no notes")
}

Test_Updater_RollbackRestoresLastVersion() {
    r := UpdMakeRoot()
    try {
        UpdInstallWithNotes(r)
        UpdPut(r "\settings.ini", "USER settings changed after the update")
        UpdPut(r "\data\routes.json", "USER routes 2")
        m := UpdMake(r, Map("version", "1.1"))
        b := m[1].LastBackup()
        AssertTrue(IsObject(b), "backup found")
        AssertEq(b["from"], "1.0", "goes back to 1.0")
        res := m[1].Rollback()
        AssertTrue(res["ok"], "rollback ok")
        AssertEq(UpdGet(r "\Vesper.ahk"), "old main", "main restored")
        AssertEq(UpdGet(r "\lib\App.ahk"), "old app", "lib restored")
        AssertTrue(!FileExist(r "\lib\Updater.ahk"), "added file removed")
        AssertTrue(!FileExist(r "\data\default_routes.json"), "added data file removed")
        AssertTrue(!DirExist(r "\assets"), "empty new folders removed")
        AssertTrue(DirExist(r "\lib"), "folder with old files kept")
        AssertEq(UpdGet(r "\settings.ini"), "USER settings changed after the update", "settings untouched")
        AssertEq(UpdGet(r "\data\routes.json"), "USER routes 2", "routes untouched")
        AssertEq(UpdGet(r "\data\calibration.json"), "USER calib", "calibration untouched")
        AssertEq(UpdGet(r "\logs\macro.log"), "USER log", "logs untouched")
        AssertTrue(!DirExist(r "\backup\1.0"), "used backup removed")
        AssertTrue(!FileExist(r "\data\whatsnew.json"), "whatsnew removed")
        AssertTrue(!DirExist(r "\update_tmp"), "temp folder removed")
        AssertEq(m[2]["restart"], 1, "restarted")
        AssertEq(m[1].LastBackup(), "", "nothing left to go back to")
    } finally {
        UpdClean(r)
    }
}

Test_Updater_RollbackRefusals() {
    r := UpdMakeRoot()
    try {
        m := UpdMake(r, Map("version", "1.1"))
        AssertEq(m[1].LastBackup(), "", "no backup folder")
        AssertTrue(!m[1].Rollback()["ok"], "no backup: refused")
        UpdPut(r "\backup\1.0\Vesper.ahk", "old main")      ; old-style backup, no manifest
        AssertEq(m[1].LastBackup(), "", "backup without a manifest is not offered")
        UpdInstallWithNotes(r)
        m2 := UpdMake(r, Map("version", "1.2"))
        AssertEq(m2[1].LastBackup(), "", "backup made for another version is not offered")
        running := [true]
        m3 := UpdMake(r, Map("version", "1.1.0", "isStopped", () => !running[1]))
        AssertTrue(IsObject(m3[1].LastBackup()), "offered")
        AssertTrue(!m3[1].Rollback()["ok"], "refused while running")
        AssertEq(UpdGet(r "\Vesper.ahk"), "new main", "untouched while running")
        AssertEq(m3[2]["restart"], 0, "no restart while running")
    } finally {
        UpdClean(r)
    }
}

; A tampered / broken manifest never reaches user files or leaves the folder.
Test_Updater_RollbackSkipsUnsafePaths() {
    r := UpdMakeRoot()
    outside := r "_outside.txt"
    try {
        UpdPut(outside, "OUTSIDE")
        UpdPut(r "\Vesper.ahk", "new main")
        UpdPut(r "\backup\1.0\Vesper.ahk", "old main")
        UpdPut(r "\backup\1.0\settings.ini", "BACKUP settings")
        mf := Map("from", "1.0", "to", "1.1", "made", A_Now
            , "replaced", ["Vesper.ahk", "settings.ini", "..\x.txt"]
            , "added", ["data\routes.json", "..\" RegExReplace(outside, "^.*\\"), "C:\Windows\win.ini", "\abs.txt", "logs\macro.log"])
        UpdPut(r "\backup\1.0\manifest.json", Json.Stringify(mf))
        m := UpdMake(r, Map("version", "1.1"))
        AssertTrue(m[1].Rollback()["ok"], "rollback ok")
        AssertEq(UpdGet(r "\Vesper.ahk"), "old main", "program file restored")
        AssertEq(UpdGet(r "\settings.ini"), "USER settings", "settings never copied back")
        AssertEq(UpdGet(r "\data\routes.json"), "USER routes", "user file never deleted")
        AssertEq(UpdGet(r "\logs\macro.log"), "USER log", "logs never deleted")
        AssertEq(UpdGet(outside), "OUTSIDE", "nothing outside the folder deleted")
    } finally {
        try FileDelete(outside)
        UpdClean(r)
    }
}

Test_Updater_RollbackFailureKeepsNewVersion() {
    r := UpdMakeRoot()
    try {
        UpdInstallWithNotes(r)
        n := [0]
        ; the current files are kept first, then the backup is copied back: fail on the 2nd copy back
        cp := (s, t) => (InStr(s, "\backup\") && ++n[1] = 2 ? UpdThrowing() : FileCopy(s, t, 1))
        m := UpdMake(r, Map("version", "1.1", "copyFile", cp))
        res := m[1].Rollback()
        AssertTrue(!res["ok"], "failed")
        AssertTrue(n[1] >= 2, "reached the failing copy")
        AssertEq(UpdGet(r "\Vesper.ahk"), "new main", "main kept new")
        AssertEq(UpdGet(r "\lib\App.ahk"), "new app", "lib kept new")
        AssertEq(UpdGet(r "\lib\Updater.ahk"), "new file", "added file kept")
        AssertTrue(DirExist(r "\backup\1.0"), "backup kept for another try")
        AssertTrue(!DirExist(r "\update_tmp"), "temp folder removed")
        AssertEq(m[2]["restart"], 0, "no restart")
    } finally {
        UpdClean(r)
    }
}

Test_Updater_DashboardGoBackButton() {
    r := UpdTmp()
    d := ""
    try {
        DirCreate(r "\data")
        src := RegExReplace(A_LineFile, "\\tests\\[^\\]+$", "") "\data"
        for n in ["biomes", "potions", "quests", "merchants"]
            FileCopy(src "\" n ".json", r "\data\" n ".json", 1)
        UpdPut(r "\settings.ini", "[Update]`r`nrepo=o/r`r`n")
        fired := []
        d := Dashboard(Config.Load(r), Map("rollback", () => fired.Push(1)))
        AssertTrue(d._hidden.Has(d._updBack.Hwnd), "hidden without a backup")
        d.SetRollback("1.7")
        AssertTrue(!d._hidden.Has(d._updBack.Hwnd), "shown with a backup")
        AssertEq(d._updBack.Text, "Go back to v1.7", "button text")
        d.SetUpdate("1.9")
        AssertTrue(d._hidden.Has(d._updBack.Hwnd), "hidden while an update is offered")
        d.SetUpdate("")
        AssertTrue(!d._hidden.Has(d._updBack.Hwnd), "back after Later")
        d.SetRollback("")
        AssertTrue(d._hidden.Has(d._updBack.Hwnd), "hidden again")
        d._AskRollback()                 ; no backup: no question, nothing fired
        AssertEq(fired.Length, 0, "nothing fired without a backup")
    } finally {
        if IsObject(d)
            d.Destroy()
        UpdClean(r)
    }
}

UpdFakeRollbackUpdater(calls) {
    u := {Enabled: true}
    u.Rollback := (*) => (calls.Push("rollback"), Map("ok", false, "msg", "Go back: no backup of the last version"))
    u.LastBackup := (*) => ""
    return u
}

Test_Updater_AppGoBackOnlyWhenStopped() {
    t := AppTestMake()
    calls := []
    t.app._updater := UpdFakeRollbackUpdater(calls)
    t.app._started := true
    AssertEq(t.app.OnRollback(), false, "refused while running")
    AssertEq(calls.Length, 0, "updater not asked while running")
    t.app._started := false
    t.app._toolBusy := true
    AssertEq(t.app.OnRollback(), false, "refused while a route tool runs")
    AssertEq(calls.Length, 0, "updater not asked while busy")
    t.app._toolBusy := false
    AssertEq(t.app.OnRollback(), false, "updater result passed on")
    AssertEq(calls.Length, 1, "updater asked once stopped")
}

Test_Updater_AppShowWhatsNewOnce() {
    t := AppTestMake()
    r := UpdTmp()
    try {
        t.app.root := r
        AssertEq(t.app.ShowWhatsNew(), "", "nothing to show")
        UpdPut(r "\data\whatsnew.json", Json.Stringify(Map("version", Brand.Version, "tag", "v" Brand.Version, "notes", "- hi")))
        wn := t.app.ShowWhatsNew()
        AssertTrue(IsObject(wn), "shown for this version")
        AssertEq(wn["notes"], "- hi", "notes")
        AssertTrue(!FileExist(r "\data\whatsnew.json"), "file removed")
        AssertEq(t.app.ShowWhatsNew(), "", "only once")
    } finally {
        UpdClean(r)
    }
}

; idea 1 (2026-11-13): MoontideMacro.exe runs the macro, so an update must
; not try to overwrite it (locked); a copy without one gets it
Test_Updater_LauncherKeptWhenPresent() {
    AssertTrue(Updater.IsLauncher("MoontideMacro.exe"), "the launcher")
    AssertTrue(Updater.IsLauncher("moontidemacro.EXE"), "any case")
    AssertTrue(!Updater.IsLauncher("lib\MoontideMacro.exe"), "only at the top")
    AssertTrue(!Updater.IsLauncher("Vesper.ahk"), "not the scripts")
}

; 2026-11-16, the user: see how many people use the macro, without tracking
; anyone: the GitHub download counts of each release (dev copy only)
Test_Updater_DownloadCounts() {
    body := '[{"tag_name":"v1.4.5","assets":[{"name":"MoontideMacro-v1.4.5.zip","download_count":3}]}'
        . ',{"tag_name":"v1.4","assets":[{"name":"a.zip","download_count":4},{"name":"b.txt","download_count":1}]}'
        . ',{"tag_name":"v1.3","assets":[]}]'
    r := Updater.DownloadCounts(body)
    AssertEq(r.total, 8, "every asset of every release")
    AssertEq(r.rows.Length, 3, "one row per release")
    AssertEq(r.rows[1].tag " " r.rows[1].n, "v1.4.5 3", "newest first")
    AssertEq(r.rows[2].n, 5, "assets added up")
    AssertEq(r.rows[3].n, 0, "no assets: 0")
    AssertEq(Updater.DownloadText(r), "Total: 8 downloads`nv1.4.5: 3   v1.4: 5   v1.3: 0", "the text")
    AssertEq(Updater.DownloadCounts("not json"), "", "bad reply: nothing")
    many := {total: 9, rows: []}
    Loop 9
        many.rows.Push({tag: "v0." A_Index, n: 1})
    AssertTrue(InStr(Updater.DownloadText(many), "v0.6: 1") && !InStr(Updater.DownloadText(many), "v0.7"), "6 newest per line set: " Updater.DownloadText(many))
    ; the rest is added up, so the line matches the total (it showed 14 of 26)
    AssertTrue(InStr(Updater.DownloadText(many), "older: 3"), "older releases added up: " Updater.DownloadText(many))
    AssertTrue(!InStr(Updater.DownloadText(r), "older"), "6 or fewer releases: no older")
    ; the dev copy is the folder with the marker file (never published); a
    ; clone of the public repo has .git but no marker
    d := A_Temp "\vesper_dlc_" A_TickCount
    DirCreate(d)
    try {
        AssertEq(Updater.IsDevCopy(d), false, "an unzipped release: no")
        DirCreate(d "\.git")
        AssertEq(Updater.IsDevCopy(d), false, "a clone of the public repo: no")
        FileAppend("", d "\" Updater.DevMarker)
        AssertEq(Updater.IsDevCopy(d), true, "the owner's copy: yes")
    } finally
        try DirDelete(d, true)
}

; ---- nothing in an update can hang (bug hunt 2026-11-26) ---------------------
; A PowerShell that never returned kept "Making the zip..." up for 20+ minutes
; on a player's PC. The updater had the same kind of waits: AHK's Download()
; (no time cap, the dashboard frozen) and Expand-Archive under RunWait.

; a WinHttp request stand-in: answers after `polls` WaitForResponse(0) calls
; (-1 = never), with status / body
class UpdFakeReq {
    __New(polls := 0, status := 200, body := "") {
        this.polls := polls, this.Status := status, this.body := body
        this.calls := [], this.aborted := false, this.async := ""
    }
    SetTimeouts(a*) => this.calls.Push("timeouts")
    Open(m, url, async) => (this.async := async, this.calls.Push("open " m))
    SetRequestHeader(k, v) => this.calls.Push(k ": " v)
    Send(*) => this.calls.Push("send")
    Abort() => this.aborted := true
    WaitForResponse(sec := -1) {
        if (this.polls < 0)
            return false
        return this.polls-- <= 0
    }
    ResponseText => this.body
    ResponseBody {
        get {
            if (this.body = "")
                return ""
            a := ComObjArray(0x11, StrLen(this.body))
            Loop Parse this.body
                a[A_Index - 1] := Ord(A_LoopField)
            return a
        }
    }
}

Test_Updater_DownloadHasATimeCap() {
    d := UpdTmp()
    try {
        q := UpdFakeReq(-1)
        t0 := A_TickCount
        err := ""
        try Updater._Download("https://github.com/o/r/M.zip", d "\r.zip", 400, () => q)
        catch Error as e
            err := e.Message
        ms := A_TickCount - t0
        AssertTrue(InStr(err, "no answer"), "a download that never answers throws: " err)
        AssertTrue(ms >= 350 && ms < 3000, "gave up at the cap, not later (" ms " ms)")
        AssertTrue(q.aborted, "the request is aborted")
        AssertTrue(q.async = true, "asked asynchronously (the GUI keeps running)")
        AssertTrue(!FileExist(d "\r.zip"), "no file left")
    } finally
        UpdClean(d)
}

Test_Updater_DownloadWritesTheBody() {
    d := UpdTmp()
    try {
        q := UpdFakeReq(3, 200, "PK-zip-bytes")
        Updater._Download("https://github.com/o/r/M.zip", d "\r.zip", 5000, () => q)
        AssertEq(FileRead(d "\r.zip", "UTF-8-RAW"), "PK-zip-bytes", "the body is the file")
        err := ""
        try Updater._Download("https://github.com/o/r/M.zip", d "\x.zip", 5000, () => UpdFakeReq(0, 404, "no"))
        catch Error as e
            err := e.Message
        AssertEq(err, "HTTP 404", "a refused download throws")
        err := ""
        try Updater._Download("https://github.com/o/r/M.zip", d "\y.zip", 5000, () => UpdFakeReq(0, 200, ""))
        catch Error as e
            err := e.Message
        AssertTrue(InStr(err, "empty"), "an empty download throws: " err)
        ; the update check has a cap too
        AssertTrue(Updater.HttpCapMs > 0 && Updater.HttpCapMs <= 60000, "update check capped")
        AssertTrue(Updater.DownloadCapMs > 0 && Updater.DownloadCapMs <= 600000, "download capped")
        AssertEq(Updater(Map("root", A_Temp))._download.MinParams, 2, "download(url, dest)")
    } finally
        UpdClean(d)
}

Test_Updater_UnzipNeverWaitsForGood() {
    cmds := Updater._UnzipCmds("C:\a b\r.zip", "C:\a b\x")
    last := cmds[cmds.Length]
    AssertEq(last.name, "PowerShell", "PowerShell is the last resort")
    AssertTrue(InStr(last.cmd, "-NonInteractive") && InStr(last.cmd, "-NoProfile"), "no prompt, no profile")
    AssertTrue(InStr(last.cmd, "$ErrorActionPreference='Stop'"), "an error is exit code 1 (a broken zip exited 0)")
    if FileExist(A_WinDir "\System32\tar.exe")
        AssertEq(cmds[1].name, "tar", "Windows' tar first (no PowerShell)")
    ; every try gets the cap; one that runs past it is given up
    seen := []
    run := (cmd, capMs) => (seen.Push(capMs), {code: "", timedOut: true})
    err := ""
    try Updater._Unzip("C:\r.zip", "C:\x", run)
    catch Error as e
        err := e.Message
    AssertEq(seen.Length, cmds.Length, "each way tried once")
    AssertEq(seen[1], Updater.UnzipCapMs, "with the cap")
    AssertTrue(InStr(err, "could not unzip") && InStr(err, "was stopped"), "says it was stopped: " err)
    ; the first way stuck, the next one works
    n := [0]
    run2 := (cmd, capMs) => (++n[1] < cmds.Length ? {code: "", timedOut: true} : {code: 0, timedOut: false})
    AssertEq(Updater._Unzip("C:\r.zip", "C:\x", run2), last.name, "falls back and succeeds")
    ; a way that cannot start, then one that fails
    run3 := (cmd, capMs) => InStr(cmd, "tar.exe") ? UpdThrowing() : {code: 1, timedOut: false}
    err := ""
    try Updater._Unzip("C:\r.zip", "C:\x", run3)
    catch Error as e
        err := e.Message
    AssertTrue(InStr(err, "PowerShell failed (code 1)"), "the exit code is said: " err)
    ; no RunWait or Download() left in the updater
    src := FileRead(A_LineFile "\..\..\lib\Updater.ahk", "UTF-8")
    AssertTrue(!RegExMatch(src, "m)^[^;]*\bRunWait\("), "no RunWait")
    AssertTrue(!RegExMatch(src, "m)^[^;]*[^._\w]Download\("), "no Download()")
}

; the real unzip on a real zip (made by Windows' tar), as the updater runs it
Test_Updater_UnzipRealZip() {
    tar := A_WinDir "\System32\tar.exe"
    if !FileExist(tar)
        return
    d := UpdTmp()
    try {
        UpdPut(d "\src\Vesper.ahk", "new main")
        UpdPut(d "\src\lib\App.ahk", "new app")
        r := Proc.RunCapped('"' tar '" -a -cf "' d '\r.zip" -C "' d '\src" Vesper.ahk lib', "", 30000)
        AssertEq(r.code, 0, "zip made")
        DirCreate(d "\x")
        AssertEq(Updater._Unzip(d "\r.zip", d "\x"), "tar", "unzipped by tar")
        AssertEq(UpdGet(d "\x\Vesper.ahk"), "new main", "main file out")
        AssertEq(UpdGet(d "\x\lib\App.ahk"), "new app", "sub folder out")
        ; the PowerShell way (no tar.exe), its command line as built
        cmds := Updater._UnzipCmds(d "\r.zip", d "\p s")
        DirCreate(d "\p s")
        r := Proc.RunCapped(cmds[cmds.Length].cmd, "", Updater.UnzipCapMs)
        AssertTrue(!r.timedOut && r.code = 0, "PowerShell unzipped (code " r.code ")")
        AssertEq(UpdGet(d "\p s\lib\App.ahk"), "new app", "PowerShell: files out")
        ; a broken zip fails (tar, then PowerShell), it does not hang
        UpdPut(d "\bad.zip", "not a zip")
        DirCreate(d "\y")
        err := ""
        try Updater._Unzip(d "\bad.zip", d "\y")
        catch Error as e
            err := e.Message
        AssertTrue(InStr(err, "could not unzip"), "a broken zip fails: " err)
    } finally
        UpdClean(d)
}

Test_Updater_InstallWhileInstallingOrStarted() {
    r := UpdMakeRoot()
    try {
        inner := [""]
        u := [""]
        m := UpdMake(r, Map("download", (url, dest) => (inner[1] := u[1].Install(Map("url", url, "tag", "v1.1")), UpdPut(dest, "zip"))))
        u[1] := m[1]
        res := m[1].Install(Map("url", "https://github.com/o/r/M.zip", "tag", "v1.1"))
        AssertTrue(res["ok"], "the first install goes on")
        AssertTrue(!inner[1]["ok"] && InStr(inner[1]["msg"], "already installing"), "a second click is refused")
        AssertTrue(!m[1]._busy, "not busy afterwards")
    } finally {
        UpdClean(r)
    }
    ; F1 while it downloaded: nothing replaced
    r2 := UpdMakeRoot()
    try {
        running := [false]
        m2 := UpdMake(r2, Map("isStopped", () => !running[1]
            , "download", (url, dest) => (running[1] := true, UpdPut(dest, "zip"))))
        res := m2[1].Install(Map("url", "https://github.com/o/r/M.zip", "tag", "v1.1"))
        AssertTrue(!res["ok"] && InStr(res["msg"], "started"), "refused: " res["msg"])
        AssertEq(UpdGet(r2 "\Vesper.ahk"), "old main", "old version kept")
        AssertEq(m2[2]["restart"], 0, "no restart")
    } finally
        UpdClean(r2)
}

class UpdFakeDash {
    notes := []
    SetUpdate(version, note := "") => this.notes.Push(version "|" note)
}

class UpdFakeInstaller {
    __New(dash) {
        this.dash := dash, this.seen := ""
        this.last := Map("status", "available", "version", "9.9.9", "url", "https://github.com/o/r/M.zip")
    }
    Install(info) {
        this.seen := this.dash.notes.Length ? this.dash.notes[this.dash.notes.Length] : ""
        return Map("ok", false, "msg", "Update failed, kept the old version: x")
    }
}

; Install can take a while now that it waits without freezing: the notice
; says so and the Install button is hidden (no second click) meanwhile
Test_Updater_AppSaysInstalling() {
    t := AppTestMake()
    old := t.app.dash
    try {
        d := UpdFakeDash()
        t.app.dash := d
        u := UpdFakeInstaller(d)
        t.app._updater := u
        t.app.OnInstallUpdate()
        AssertEq(u.seen, "|Installing the update...", "said before the install, Install hidden (version empty)")
        AssertEq(d.notes[d.notes.Length], "|Update failed, kept the old version: x", "the failure shown after")
    } finally
        t.app.dash := old
}

; Proc.RunCapped: the helper the updater waits on
Test_Proc_RunCappedStopsAHang() {
    t0 := A_TickCount
    r := Proc.RunCapped('"' A_WinDir '\System32\PING.EXE" -n 30 127.0.0.1', "", 500)
    ms := A_TickCount - t0
    AssertTrue(r.timedOut, "a program past the cap is stopped")
    AssertEq(r.code, "", "no exit code then")
    AssertTrue(ms < 4000, "stopped near the cap (" ms " ms)")
    r := Proc.RunCapped('"' A_WinDir '\System32\cmd.exe" /c exit 7', "", 10000)
    AssertTrue(!r.timedOut, "a quick one ends")
    AssertEq(r.code, 7, "its exit code")
    err := ""
    try Proc.RunCapped('"C:\no\such\program_x.exe"', "", 1000)
    catch Error as e
        err := e.Message
    AssertTrue(InStr(err, "cannot start"), "a missing program throws: " err)
}
