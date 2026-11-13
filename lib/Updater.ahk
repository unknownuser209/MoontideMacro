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
;       the backup and keeps the old version running. A good install also
;       writes backup\<old version>\manifest.json (from, to, made, replaced,
;       added) and data\whatsnew.json (version, tag, notes = the release text).
;   u.LastBackup() -> Map(dir, from, to, replaced, added) of the newest backup
;       whose manifest says it was made by the update to THIS version, or "".
;   u.Rollback() -> Map(ok, msg). Refuses while the macro runs. Puts the
;       replaced files back, deletes the files that update added (user files
;       are never touched), removes that backup and restarts. Any failure puts
;       the new version back as it was.
;   Updater.TakeWhatsNew(root, version) -> Map(version, tag, notes) once after
;       an update to that version, else ""; the file is deleted either way.
;   Updater.NotesText(md) -> release notes as plain text (no **, #, backticks).
; No tokens, no personal data: one anonymous GET with a fixed User-Agent.
; ---------------------------------------------------------------------------

class Updater {
    static UserAgent := "MoontideMacro-Updater"
    static Hosts := ["github.com", "api.github.com", "codeload.github.com", "objects.githubusercontent.com"]
    ; relative paths (lower case) the updater must never overwrite
    static Protected := ["settings.ini", "data\calibration.json", "data\routes.json", "data\quests.json"
        , "data\merchants.json", "data\potions.json", "data\biomes.json", "data\auras_had.txt"
        , "data\potion_usage.json", "data\last_biome.txt", "data\minions_routes.json", "data\auras_learnt.json"
        , "data\stats.json", "data\summary_last.txt", "data\schedule_state.txt", "data\whatsnew.json"]
    static WhatsNewFile := "data\whatsnew.json"
    static NotesMax := 8000
    static ProtectedDirs := ["logs\", "backup\", "update_tmp\", "exports\"]

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

    ; the no-install launcher (tools\make_release.ps1 adds it to the zip)
    static IsLauncher(rel) => StrLower(StrReplace(rel, "/", "\")) = "moontidemacro.exe"

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
        this._http := g("http", (url) => Updater._Http(url))
        this._download := g("download", (url, dest) => Download(url, dest))
        this._unzip := g("unzip", (zip, dest) => Updater._Unzip(zip, dest))
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
        notes := (rel.Has("body") && rel["body"] is String) ? SubStr(rel["body"], 1, Updater.NotesMax) : ""
        this.last := Map("status", "available", "tag", tag, "version", v[1] "." v[2] "." v[3], "url", url, "notes", notes)
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
                ; MoontideMacro.exe (AutoHotkey itself) cannot be replaced while
                ; it runs the macro: kept when there is one, added when not
                if !Updater.IsProtected(rel) && !(Updater.IsLauncher(rel) && FileExist(this.root "\" rel))
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
        this._WriteManifest(backupDir, info, done)
        this._WriteWhatsNew(info)
        this.Log("Updated to " (info.Has("tag") ? info["tag"] : "new version") "; restarting")
        try this._restart.Call()
        return Map("ok", true, "msg", "updated")
    }

    ; backup\<old>\manifest.json: what "Go back" needs. A failure here only
    ; costs the Go back button, never the update.
    _WriteManifest(backupDir, info, done) {
        replaced := [], added := []
        for item in done
            (item[2] ? replaced : added).Push(item[1])
        to := info.Has("version") ? info["version"] : (info.Has("tag") ? RegExReplace(info["tag"], "^[vV]") : "")
        m := Map("from", this.version, "to", to, "made", A_Now, "replaced", replaced, "added", added)
        try Updater._WriteText(backupDir "\manifest.json", Json.Stringify(m))
        catch Any as e
            this.Log("Update: could not save the backup list (" (e is Error ? e.Message : String(e)) ")")
    }

    ; data\whatsnew.json: shown once by the new version after the restart.
    _WriteWhatsNew(info) {
        ver := info.Has("version") ? info["version"] : (info.Has("tag") ? RegExReplace(info["tag"], "^[vV]") : "")
        m := Map("version", ver, "tag", info.Has("tag") ? info["tag"] : "", "notes", info.Has("notes") ? String(info["notes"]) : "")
        try {
            DirCreate(this.root "\data")
            Updater._WriteText(this.root "\" Updater.WhatsNewFile, Json.Stringify(m))
        }
    }

    static _WriteText(path, text) {
        f := FileOpen(path, "w", "UTF-8-RAW")
        if !IsObject(f)
            throw Error("cannot write " RegExReplace(path, "^.*\\"))
        f.Write(text)
        f.Close()
    }

    ; -> Map(version, tag, notes) when data\whatsnew.json is for `version`,
    ; else "". The file is deleted either way (shown once).
    static TakeWhatsNew(root, version) {
        path := RTrim(root, "\/") "\" Updater.WhatsNewFile
        if !FileExist(path)
            return ""
        m := ""
        try m := Json.Parse(FileRead(path, "UTF-8"))
        try FileDelete(path)
        if !(m is Map && m.Has("version") && Updater.Compare(m["version"], version) = 0)
            return ""
        return Map("version", String(m["version"]), "tag", m.Has("tag") ? String(m["tag"]) : ""
            , "notes", m.Has("notes") && m["notes"] is String ? m["notes"] : "")
    }

    ; Release notes (GitHub markdown) as plain text for a read-only box:
    ; headings lose their #, **bold** / `code` marks go, [text](link) keeps
    ; the text, bullets stay (as "- "). CRLF line ends, at most NotesMax chars.
    static NotesText(md) {
        t := StrReplace(StrReplace(String(md), "`r`n", "`n"), "`r", "`n")
        out := ""
        blank := 0
        for line in StrSplit(t, "`n") {
            line := RTrim(line, " `t")
            if RegExMatch(line, "^\s*([-*_])(\s*\1){2,}\s*$")      ; --- rule
                line := ""
            line := RegExReplace(line, "^\s{0,3}#{1,6}(\s+|$)", "")
            line := RegExReplace(line, "^(\s*)[*+]\s+", "$1- ")
            line := StrReplace(line, "**", "")
            line := StrReplace(line, "``", "")
            line := RegExReplace(line, "!?\[([^\]]*)\]\([^)]*\)", "$1")
            if (Trim(line) = "") {
                if (out = "" || ++blank > 1)
                    continue
                out .= "`r`n"
                continue
            }
            blank := 0
            out .= line "`r`n"
        }
        out := RTrim(out, "`r`n")
        return StrLen(out) > Updater.NotesMax ? SubStr(out, 1, Updater.NotesMax) "..." : out
    }

    ; ---- go back to the last version ---------------------------------------------

    ; Newest backup\<ver>\ with a manifest made by the update to this version.
    LastBackup() {
        best := "", bestMade := ""
        loop Files, this.root "\backup\*", "D" {
            mf := A_LoopFilePath "\manifest.json"
            if !FileExist(mf)
                continue
            m := ""
            try m := Json.Parse(FileRead(mf, "UTF-8"))
            if !(m is Map && m.Has("from") && m.Has("to") && m.Has("replaced") && m.Has("added")
                && m["replaced"] is Array && m["added"] is Array)
                continue
            if (Updater.Compare(m["to"], this.version) != 0 || Updater.ParseVersion(m["from"]) = "")
                continue
            made := m.Has("made") ? String(m["made"]) : ""
            if (best = "" || StrCompare(made, bestMade) >= 0) {
                best := Map("dir", A_LoopFilePath, "from", String(m["from"]), "to", String(m["to"])
                    , "replaced", m["replaced"], "added", m["added"])
                bestMade := made
            }
        }
        return best
    }

    ; A manifest path we may touch: relative, inside root, not a user file.
    static _SafeRel(rel) {
        if !(rel is String) || rel = "" || InStr(rel, ":") || InStr(rel, "..") || RegExMatch(rel, "^[\\/]")
            return false
        return !Updater.IsProtected(rel)
    }

    Rollback() {
        if !this._stopped.Call()
            return this._Fail("Go back: stop the macro first")
        b := this.LastBackup()
        if !IsObject(b)
            return this._Fail("Go back: no backup of the last version")
        replaced := [], added := []
        for rel in b["replaced"] {
            if !Updater._SafeRel(rel)
                continue
            if !FileExist(b["dir"] "\" rel)
                return this._Fail("Go back: the backup is missing " rel ", nothing changed")
            replaced.Push(rel)
        }
        for rel in b["added"] {
            if Updater._SafeRel(rel)
                added.Push(rel)
        }
        ; keep the current files first, so a failure can put them back
        undo := this.root "\update_tmp\undo"
        kept := []            ; [rel, existedBefore]
        try {
            try DirDelete(this.root "\update_tmp", true)
            DirCreate(undo)
            for list in [replaced, added] {
                for rel in list {
                    dst := this.root "\" rel
                    existed := FileExist(dst) ? true : false
                    if existed {
                        DirCreate(Updater._Dir(undo "\" rel))
                        this._copy.Call(dst, undo "\" rel)
                    }
                    kept.Push([rel, existed])
                }
            }
            for rel in replaced {
                DirCreate(Updater._Dir(this.root "\" rel))
                this._copy.Call(b["dir"] "\" rel, this.root "\" rel)
            }
            for rel in added {
                if FileExist(this.root "\" rel)
                    FileDelete(this.root "\" rel)
            }
        } catch Any as e {
            this._Restore(undo, kept)
            try DirDelete(this.root "\update_tmp", true)
            return this._Fail("Go back failed, kept v" this.version ": " (e is Error ? e.Message : String(e)))
        }
        for rel in added
            this._PruneDirs(Updater._Dir(this.root "\" rel))
        try DirDelete(this.root "\update_tmp", true)
        try DirDelete(b["dir"], true)
        try FileDelete(this.root "\" Updater.WhatsNewFile)
        this.Log("Went back to v" b["from"] "; restarting")
        try this._restart.Call()
        return Map("ok", true, "msg", "went back", "version", b["from"])
    }

    ; Remove folders an update added once they are empty (never root itself).
    _PruneDirs(dir) {
        while (StrLen(dir) > StrLen(this.root) && SubStr(dir, 1, StrLen(this.root) + 1) = this.root "\") {
            try DirDelete(dir, false)
            catch
                return
            dir := Updater._Dir(dir)
        }
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
