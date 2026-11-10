#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\Json.ahk
#Include %A_LineFile%\..\Brand.ahk
; ---------------------------------------------------------------------------
; Updater: new versions from GitHub Releases. The version lives in ONE place,
; Brand.Version (lib\Brand.ahk); tools\make_release.ps1 reads it too.
;
; Settings ([Update] in settings.ini): repo=owner/name (EMPTY = the updater
; does nothing and says nothing), check=1 (check once per start), auto=0
; (0 = the dashboard asks, 1 = install without asking).
;
;   u := Updater(deps)   deps Map (all optional but root):
;     root     program folder (holds Vesper.ahk)
;     version  local version (default Brand.Version)
;     repo, check, auto   the [Update] settings
;     http     (url) -> response text; throws on network / HTTP errors
;     download (url, destFile); unzip (zipFile, destDir)
;     copyFile (src, dst) overwrite; log (text); now () -> ms
;     isStopped () -> true while the macro is stopped (install only then)
;     restart  () called after a good install (default: Run Vesper.ahk, ExitApp)
;   u.Check(manual := false) -> Map(status, version, url, tag)
;       status: disabled | skipped | error | uptodate | available
;       Automatic checks run once per start; manual := true always asks.
;       Errors are logged (once for automatic checks), never thrown.
;   u.Install(info) -> Map(ok, msg). info = the Check result (status
;       "available"). Refuses while the macro runs. Extracts to
;       <root>\update_tmp, needs Vesper.ahk in it, backs the replaced files up
;       to <root>\backup\<old version>\, copies the new ones over (user files
;       are NEVER touched, see Protected) and restarts. Any failure restores
;       the backup and keeps the old version running.
; No tokens, no personal data: one anonymous GET with a fixed User-Agent.
; ---------------------------------------------------------------------------

class Updater {
    static UserAgent := "MoontideMacro-Updater"
    static Hosts := ["github.com", "api.github.com", "codeload.github.com", "objects.githubusercontent.com"]
    ; relative paths (lower case) the updater must never overwrite
    static Protected := ["settings.ini", "data\calibration.json", "data\routes.json", "data\quests.json"
        , "data\merchants.json", "data\potions.json", "data\biomes.json", "data\auras_had.txt"
        , "data\potion_usage.json", "data\last_biome.txt", "data\minions_routes.json", "data\auras_learnt.json"]
    static ProtectedDirs := ["logs\", "backup\", "update_tmp\"]

    static ParseVersion(tag) {
        if !RegExMatch(Trim(String(tag)), "^[vV]?(\d{1,9})(?:\.(\d{1,9}))?(?:\.(\d{1,9}))?$", &m)
            return ""
        return [Integer(m[1]), m[2] = "" ? 0 : Integer(m[2]), m[3] = "" ? 0 : Integer(m[3])]
    }

    ; -> 1 if a > b, -1 if a < b, 0 equal, "" if either is not a version.
    static Compare(a, b) {
        pa := Updater.ParseVersion(a)
        pb := Updater.ParseVersion(b)
        if !(pa is Array && pb is Array)
            return ""
        loop 3 {
            if (pa[A_Index] != pb[A_Index])
                return pa[A_Index] > pb[A_Index] ? 1 : -1
        }
        return 0
    }

    static IsAllowedUrl(url) {
        if !(url is String) || !RegExMatch(url, "i)^https://([a-z0-9.-]+)(?:/|$)", &m)
            return false
        for h in Updater.Hosts {
            if (StrLower(m[1]) = h)
                return true
        }
        return false
    }

    static IsProtected(rel) {
        r := StrLower(StrReplace(rel, "/", "\"))
        for p in Updater.Protected {
            if (r = p)
                return true
        }
        for d in Updater.ProtectedDirs {
            if (SubStr(r, 1, StrLen(d)) = d)
                return true
        }
        return RegExMatch(r, "^data\\[^\\]*state[^\\]*\.json$") ? true : false
    }

    static ValidRepo(repo) => RegExMatch(repo, "^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$") ? true : false

    __New(deps) {
        d := (deps is Map) ? deps : Map()
        g := (k, def) => d.Has(k) ? d[k] : def
        this.root := RTrim(g("root", ""), "\/")
        if (this.root = "")
            throw ValueError("Updater: root is required")
        this.version := g("version", Brand.Version)
        this.repo := Trim(String(g("repo", "")))
        this.checkOnStart := g("check", 1) ? true : false
        this.auto := g("auto", 0) ? true : false
        this._http := g("http", Updater._Http)
        this._download := g("download", (url, dest) => Download(url, dest))
        this._unzip := g("unzip", Updater._Unzip)
        this._copy := g("copyFile", (s, t) => FileCopy(s, t, 1))
        this._log := g("log", (t) => "")
        this._now := g("now", () => A_TickCount)
        this._stopped := g("isStopped", () => true)
        this._restart := g("restart", ObjBindMethod(Updater, "_Restart", this.root))
        this._checked := false
        this._errLogged := false
        this.last := ""
    }

    Enabled => (this.repo != "")

    Log(t) {
        try this._log.Call(t)
    }

    Check(manual := false) {
        if (this.repo = "")
            return Map("status", "disabled")
        if !manual {
            if (!this.checkOnStart || this._checked)
                return Map("status", "skipped")
            this._checked := true
        }
        if !Updater.ValidRepo(this.repo) {
            this._Err("Update check: [Update] repo must look like owner/name", manual)
            return Map("status", "error")
        }
        try {
            body := this._http.Call("https://api.github.com/repos/" this.repo "/releases/latest")
            rel := Json.Parse(body)
            if !(rel is Map && rel.Has("tag_name"))
                throw Error("unexpected reply")
            tag := String(rel["tag_name"])
        } catch Any as e {
            this._Err("Update check failed: " (e is Error ? e.Message : String(e)), manual)
            return Map("status", "error")
        }
        c := Updater.Compare(tag, this.version)
        if (c = "") {
            this._Err("Update check: release tag '" SubStr(tag, 1, 30) "' is not a version", manual)
            return Map("status", "error")
        }
        if (c <= 0) {
            this.last := Map("status", "uptodate", "tag", tag)
            return this.last
        }
        url := ""
        if (rel.Has("assets") && rel["assets"] is Array) {
            for a in rel["assets"] {
                if (a is Map && a.Has("name") && a.Has("browser_download_url") && RegExMatch(String(a["name"]), "i)\.zip$")) {
                    url := String(a["browser_download_url"])
                    break
                }
            }
        }
        if (url = "" && rel.Has("zipball_url"))
            url := String(rel["zipball_url"])
        v := Updater.ParseVersion(tag)
        this.last := Map("status", "available", "tag", tag, "version", v[1] "." v[2] "." v[3], "url", url)
        this.Log("Update available: " tag)
        return this.last
    }

    _Err(text, manual) {
        if (manual || !this._errLogged)
            this.Log(text)
        this._errLogged := true
    }

    Install(info) {
        if !(info is Map && info.Has("url") && info["url"] != "")
            return this._Fail("Update: no download for this release")
        if !this._stopped.Call()
            return this._Fail("Update: stop the macro first")
        url := info["url"]
        if !Updater.IsAllowedUrl(url)
            return this._Fail("Update: refused a download address that is not on GitHub")
        tmp := this.root "\update_tmp"
        backupDir := ""
        done := []        ; [rel, existedBefore]
        try {
            try DirDelete(tmp, true)
            DirCreate(tmp)
            zip := tmp "\release.zip"
            this._download.Call(url, zip)
            ex := tmp "\x"
            DirCreate(ex)
            this._unzip.Call(zip, ex)
            src := Updater._FindRoot(ex)
            if (src = "")
                throw Error("the download has no Vesper.ahk")
            rels := []
            for rel in Updater._List(src) {
                if !Updater.IsProtected(rel)
                    rels.Push(rel)
            }
            backupDir := this._BackupDir()
            for rel in rels {
                dst := this.root "\" rel
                existed := FileExist(dst) ? true : false
                if existed {
                    DirCreate(Updater._Dir(backupDir "\" rel))
                    this._copy.Call(dst, backupDir "\" rel)
                }
                done.Push([rel, existed])
            }
            for item in done {
                rel := item[1]
                DirCreate(Updater._Dir(this.root "\" rel))
                this._copy.Call(src "\" rel, this.root "\" rel)
            }
        } catch Any as e {
            this._Restore(backupDir, done)
            try DirDelete(tmp, true)
            return this._Fail("Update failed, kept the old version: " (e is Error ? e.Message : String(e)))
        }
        try DirDelete(tmp, true)
        this.Log("Updated to " (info.Has("tag") ? info["tag"] : "new version") "; restarting")
        try this._restart.Call()
        return Map("ok", true, "msg", "updated")
    }

    _Fail(msg) {
        this.Log(msg)
        return Map("ok", false, "msg", msg)
    }

    _BackupDir() {
        base := this.root "\backup\" RegExReplace(this.version, "[^\w.\-]", "_")
        dir := base
        n := 1
        while DirExist(dir) {
            n += 1
            dir := base "-" n
        }
        DirCreate(dir)
        return dir
    }

    ; Put every file touched back: backed-up ones copied back, new ones removed.
    _Restore(backupDir, done) {
        for item in done {
            rel := item[1]
            try {
                if item[2]
                    FileCopy(backupDir "\" rel, this.root "\" rel, 1)
                else
                    FileDelete(this.root "\" rel)
            }
        }
    }

    static _Dir(path) => RegExReplace(path, "\\[^\\]*$")

    ; Folder holding Vesper.ahk: the extract itself or its single top folder
    ; (GitHub zipballs wrap everything in one).
    static _FindRoot(ex) {
        if FileExist(ex "\Vesper.ahk")
            return ex
        n := 0
        sub := ""
        loop Files, ex "\*", "D" {
            n++
            sub := A_LoopFilePath
        }
        if (n = 1 && FileExist(sub "\Vesper.ahk"))
            return sub
        return ""
    }

    static _List(dir) {
        out := []
        loop Files, dir "\*", "FR"
            out.Push(SubStr(A_LoopFilePath, StrLen(dir) + 2))
        return out
    }

    ; ---- real implementations of the injectable pieces ------------------------

    static _Http(url) {
        r := ComObject("WinHttp.WinHttpRequest.5.1")
        r.SetTimeouts(5000, 5000, 8000, 8000)
        r.Open("GET", url, false)
        r.SetRequestHeader("User-Agent", Updater.UserAgent)
        r.SetRequestHeader("Accept", "application/vnd.github+json")
        r.Send()
        if (r.Status != 200)
            throw Error("HTTP " r.Status)
        return r.ResponseText
    }

    static _Unzip(zip, dest) {
        q := (s) => "'" StrReplace(s, "'", "''") "'"
        cmd := 'powershell.exe -NoProfile -NonInteractive -Command "Expand-Archive -LiteralPath ' q(zip)
            . ' -DestinationPath ' q(dest) ' -Force"'
        if (RunWait(cmd, , "Hide") != 0)
            throw Error("could not unzip the download")
    }

    static _Restart(root) {
        Run('"' A_AhkPath '" "' root '\Vesper.ahk"', root)
        ExitApp()
    }
}
