#Requires AutoHotkey v2.0
; ---------------------------------------------------------------------------
; Plugins (2026-11-26): extra features dropped into the plugins\ folder next
; to MoontideMacro.exe, plus the built-in ones (lib\plugins\). Shown on
; Quests & events > Plugins, switched on and off there.
;
; WHY IN-PROCESS + A GENERATED INCLUDE + A RESTART
;   AutoHotkey v2 resolves #Include while it loads the script: code cannot be
;   added to a running macro. Plugins need what the macro has (the scheduler's
;   turns, input, OCR, webhooks), and two processes sending keys to Roblox
;   would fight over it, so plugins run INSIDE the macro and are loaded by a
;   generated file, plugins\.loaded\_enabled.ahk, that Vesper.ahk includes
;   (#Include *i: missing = no plugins). A newly switched-on plugin is
;   loaded by the next start ("Restart to load"). Turning one off needs no
;   restart: its hooks are simply no longer called.
;   A plugin with a syntax error would stop the whole macro from loading, so
;   before a plugin goes into _enabled.ahk it is checked in a SEPARATE
;   process: AutoHotkey /Validate (loads, never runs) of the macro plus the
;   plugin, which also catches names that clash with the macro's. Only a
;   plugin that passes is copied to plugins\.loaded\<id>[\] and included:
;   the copy is what loads, so editing or breaking the original later can
;   never stop the macro from starting (the change is checked first).
;   At run time every hook call is wrapped in try/catch; a plugin that
;   throws MaxErrors times is switched off for the session.
;
; MANIFEST: comment lines at the top of the plugin's .ahk file (a single
;   file plugins\name.ahk, or a folder plugins\name\plugin.ahk):
;     ; @moontide-plugin
;     ; id: my_plugin              a-z 0-9 _, 2-32 chars, starts with a letter
;     ; name: My plugin            shown on the Plugins tab
;     ; version: 1.0.0
;     ; api: 1                     the plugin API it was written for
;     ; class: MyPlugin            the class (extends MoontidePlugin)
;     ; author: someone            optional
;     ; description: What it does. optional, one line
;     ; setting: key | bool | 1 | Label shown on its settings page
;     ; setting: key2 | int | 30 | Seconds between checks
;     ;   (types: bool, int, text, secret; at most MaxSettings)
;   The header ends at the first line that is not a comment.
;
; API (Plugins.ApiVersion 1): class MyPlugin extends MoontidePlugin, with any
;   of the hooks below (the base's do nothing). this.api is a PluginApi:
;     OnLoad()              once, after the macro started up
;     OnStart() / OnStop()  F1 / F3
;     OnTick()              every service tick (~250 ms), started or not:
;                           keep it short, never Sleep here
;     OnBiome(biome, prev)  the biome changed (from the Roblox log)
;     Task()                -> a scheduler task {priority, CanRun(state),
;                           Run(ctx)} or "": it gets turns like the macro's
;                           own tasks (Run may send input; check
;                           ctx.ShouldStop() often). Priority is held to
;                           ExternalMinPri..ExternalMaxPri for files in
;                           plugins\ (fishing is 99).
;   PluginApi: Log(text), Get(key [, default]) / Set(key, value) / Save()
;   (the plugin's own settings, ini section [Plugin.<id>]), Notify(event,
;   title, text [, color]) (a Discord card to the webhooks that have `event`
;   ticked: biome, rare, merchant, ... see Config.EventTypes), Biome(),
;   IsStarted(), Dir (the plugin's folder), Id, Name.
;
;   Plugins.ReadManifest(text)   -> Map, or throws ValueError(reason)
;   Plugins.Scan(dir [, taken])  -> Array of entries (below); taken: ids in
;                                   use (the built-ins)
;   entry: Map id, name, version, author, description, class, settings
;          (Array of Maps key/type/def/label), path (the .ahk), dir, folder,
;          builtin, ok, reason, file (the name in plugins\)
; ---------------------------------------------------------------------------

class MoontidePlugin {
    api := ""
    OnLoad() {
    }
    OnStart() {
    }
    OnStop() {
    }
    OnTick() {
    }
    OnBiome(biome, prev) {
    }
    Task() => ""
}

class Plugins {
    static ApiVersion := 1
    static DirName := "plugins"
    static CacheName := ".loaded"
    static IdRe := "^[a-z][a-z0-9_]{1,31}$"
    static ClassRe := "^[A-Za-z_][A-Za-z0-9_]{0,63}$"
    static VersionRe := "^\d{1,4}(\.\d{1,4}){0,3}$"
    static Types := Map("bool", 1, "int", 1, "text", 1, "secret", 1)
    static MaxSettings := 8
    static MaxBytes := 2 * 1024 * 1024
    static HeaderLines := 80
    static MaxErrors := 3
    static ExternalMinPri := 3
    static ExternalMaxPri := 97
    ; ids a plugin may not take (sections and pages of the macro itself)
    static Reserved := ["plugins", "plugin", "general", "hotkeys", "webhook", "minions", "hunting", "sniper", "limited"]
    ; files in plugins\ that are not plugins and get no row
    static Quiet := "i)^(readme.*|.*\.(md|txt|ini|json|png|jpg|ico|wav|log|bak))$"

    static Dir(root) => RTrim(root, "\/") "\" Plugins.DirName
    static CacheDir(root) => Plugins.Dir(root) "\" Plugins.CacheName

    ; The on / off key of plugin id (Plugins.<id>)
    static Key(id) => "Plugins." id
    ; plugin id switched on in cfg (def: its default when never set)
    static On(cfg, id, def := 0) {
        if !IsObject(cfg)
            return def ? true : false
        try return cfg.Get(Plugins.Key(id), def) ? true : false
        return def ? true : false
    }

    ; ---- manifest ---------------------------------------------------------

    static ReadManifest(text) {
        lines := StrSplit(StrReplace(String(text), "`r"), "`n")
        start := 0
        Loop Min(lines.Length, Plugins.HeaderLines) {
            if RegExMatch(lines[A_Index], "i)^\s*;\s*@moontide-plugin\b") {
                start := A_Index
                break
            }
        }
        if !start
            throw ValueError("no Moontide plugin header (a line `"; @moontide-plugin`" at the top)")
        m := Map()
        m.CaseSense := "Off"
        settings := []
        i := start + 1
        while (i <= lines.Length) {
            ln := lines[i]
            if !RegExMatch(ln, "^\s*;")
                break
            if RegExMatch(ln, "^\s*;\s*([A-Za-z]+)\s*:\s*(.*?)\s*$", &mm) {
                k := StrLower(mm[1]), v := mm[2]
                if (k != "description")
                    v := RegExReplace(v, "\s+;.*$")        ; "; id: hello   ; a comment"
                if (k = "setting")
                    settings.Push(Plugins._Setting(v))
                else if !m.Has(k)
                    m[k] := v
            }
            i++
        }
        for k in ["id", "name", "version", "api", "class"]
            if (!m.Has(k) || m[k] = "")
                throw ValueError("the header has no " k ":")
        id := m["id"]
        if !RegExMatch(id, Plugins.IdRe)
            throw ValueError("id `"" Plugins._Short(id) "`": use a-z, 0-9 and _ (2-32 characters, a letter first)")
        if !RegExMatch(m["version"], Plugins.VersionRe)
            throw ValueError("version `"" Plugins._Short(m["version"]) "`": use numbers like 1.0.2")
        if !RegExMatch(m["api"], "^\d{1,3}$")
            throw ValueError("api `"" Plugins._Short(m["api"]) "`": a whole number like 1")
        if (Integer(m["api"]) > Plugins.ApiVersion)
            throw ValueError("needs plugin API " m["api"] ": this " Plugins._Brand() " has API " Plugins.ApiVersion ". Update the macro")
        if (Integer(m["api"]) < 1)
            throw ValueError("api must be 1 or more")
        if !RegExMatch(m["class"], Plugins.ClassRe)
            throw ValueError("class `"" Plugins._Short(m["class"]) "`" is not a class name")
        if (settings.Length > Plugins.MaxSettings)
            throw ValueError("more than " Plugins.MaxSettings " settings")
        seen := Map()
        seen.CaseSense := "Off"
        for s in settings {
            if seen.Has(s["key"])
                throw ValueError("setting `"" s["key"] "`" twice")
            seen[s["key"]] := 1
        }
        if (StrLen(m["name"]) > 40)
            m["name"] := SubStr(m["name"], 1, 40)
        out := Map("id", id, "name", m["name"], "version", m["version"], "api", Integer(m["api"]), "class", m["class"]
            , "author", m.Has("author") ? SubStr(m["author"], 1, 40) : ""
            , "description", m.Has("description") ? SubStr(m["description"], 1, 300) : ""
            , "settings", settings)
        return out
    }

    ; "key | type | default | label"
    static _Setting(v) {
        p := StrSplit(v, "|", " `t")
        if (p.Length < 4)
            throw ValueError("setting `"" Plugins._Short(v) "`": write key | type | default | label")
        key := p[1], type := StrLower(p[2]), def := p[3]
        label := p[4]
        Loop p.Length - 4
            label .= "|" p[A_Index + 4]      ; a | inside the label
        if !RegExMatch(key, "^[A-Za-z][A-Za-z0-9_]{0,31}$")
            throw ValueError("setting key `"" Plugins._Short(key) "`": letters, digits and _")
        if !Plugins.Types.Has(type)
            throw ValueError("setting " key ": type `"" Plugins._Short(type) "`" (use bool, int, text or secret)")
        if (type = "bool" && !(def = "0" || def = "1"))
            throw ValueError("setting " key ": a bool's default is 0 or 1")
        if (type = "int" && !RegExMatch(def, "^-?\d{1,9}$"))
            throw ValueError("setting " key ": an int's default is a whole number")
        if (type = "secret" && def != "")
            throw ValueError("setting " key ": a secret has no default")
        if (Trim(label) = "")
            label := key
        return Map("key", key, "type", type, "def", def, "label", SubStr(Trim(label), 1, 60))
    }

    static _Short(s) => StrLen(s) > 40 ? SubStr(s, 1, 40) "..." : s
    static _Brand() {
        try return Brand.Name
        return "macro"
    }

    ; ---- scan -----------------------------------------------------------------

    static Scan(dir, taken := "") {
        out := []
        if !DirExist(dir)
            return out
        used := Map()
        used.CaseSense := "Off"
        for r in Plugins.Reserved
            used[r] := "the macro"
        if IsObject(taken)
            for t in taken
                used[t] := "a built-in plugin"
        names := []
        Loop Files dir "\*", "FD"
            names.Push([A_LoopFileName, InStr(A_LoopFileAttrib, "D") ? true : false])
        ; the same order on every PC
        Plugins._SortNames(names)
        for it in names {
            name := it[1], isDir := it[2]
            if (SubStr(name, 1, 1) = "." || SubStr(name, 1, 1) = "_")
                continue
            if (!isDir && RegExMatch(name, Plugins.Quiet))
                continue
            e := Plugins._Blank(name)
            e["folder"] := isDir
            if isDir {
                e["dir"] := dir "\" name
                main := ""
                for cand in [e["dir"] "\plugin.ahk", e["dir"] "\" name ".ahk"]
                    if (main = "" && FileExist(cand))
                        main := cand
                if (main = "") {
                    e["reason"] := "the folder has no plugin.ahk"
                    out.Push(e)
                    continue
                }
                e["path"] := main
            } else {
                e["dir"] := dir
                e["path"] := dir "\" name
                if !RegExMatch(name, "i)\.ahk$") {
                    e["reason"] := "not a plugin: Moontide plugins are .ahk files"
                    out.Push(e)
                    continue
                }
            }
            text := ""
            try {
                if (FileGetSize(e["path"]) > Plugins.MaxBytes) {
                    e["reason"] := "too big (over 2 MB)"
                    out.Push(e)
                    continue
                }
                text := FileRead(e["path"], "UTF-8")
            } catch {
                e["reason"] := "could not be read"
                out.Push(e)
                continue
            }
            try {
                m := Plugins.ReadManifest(text)
            } catch Any as err {
                e["reason"] := err.Message
                out.Push(e)
                continue
            }
            for k, v in m
                e[k] := v
            if used.Has(m["id"]) {
                e["reason"] := "id `"" m["id"] "`" is already used by " used[m["id"]]
                out.Push(e)
                continue
            }
            used[m["id"]] := "`"" name "`""
            e["ok"] := true
            e["stamp"] := Plugins.Stamp(e)
            out.Push(e)
        }
        return out
    }

    static _Blank(file) {
        e := Map()
        e.CaseSense := "Off"
        for k, v in Map("id", "", "name", file, "version", "", "author", "", "description", "", "class", "", "settings", []
            , "path", "", "dir", "", "folder", false, "builtin", false, "ok", false, "reason", "", "file", file, "stamp", "", "page", "", "def", 0)
            e[k] := v
        return e
    }

    static _SortNames(arr) {
        n := arr.Length
        Loop n - 1 {
            i := A_Index
            Loop n - i {
                j := A_Index
                if (StrCompare(arr[j][1], arr[j + 1][1]) > 0) {
                    t := arr[j], arr[j] := arr[j + 1], arr[j + 1] := t
                }
            }
        }
    }

    ; What the plugin's files are now: size + modified time of its file, or of
    ; every file in its folder. A different stamp = it changed.
    static Stamp(e) {
        if !e["folder"] {
            try return FileGetSize(e["path"]) ":" FileGetTime(e["path"], "M")
            return ""
        }
        n := 0, total := 0, newest := "", sum := 0
        try {
            Loop Files e["dir"] "\*", "FR" {
                n++
                total += A_LoopFileSize
                if (StrCompare(A_LoopFileTimeModified, newest) > 0)
                    newest := A_LoopFileTimeModified
                for ch in StrSplit(A_LoopFileFullPath)
                    sum := Mod(sum * 31 + Ord(ch), 1000000007)
            }
        }
        return n ":" total ":" newest ":" sum
    }

    ; ---- the generated include ------------------------------------------------

    ; Where the loaded copy of entry e goes, and the file to include.
    static CachePath(root, e) => e["folder"]
        ? Plugins.CacheDir(root) "\" e["id"] "\" Plugins._MainName(e)
        : Plugins.CacheDir(root) "\" e["id"] ".ahk"

    static _MainName(e) {
        SplitPath(e["path"], &n)
        return n
    }

    ; The text of _enabled.ahk for these entries (their copies, by
    ; %A_ScriptDir% so the macro folder can be moved; *i = a copy gone
    ; missing is skipped, never a load error).
    static IncludeText(root, entries) {
        t := "; Made by " Plugins._Brand() " (lib\Plugins.ahk). Do not edit: the Plugins tab writes it.`r`n"
        for e in entries {
            rel := SubStr(Plugins.CachePath(root, e), StrLen(RTrim(root, "\/")) + 2)
            t .= "#Include *i %A_ScriptDir%\" rel "`r`n"
        }
        return t
    }

    ; The checker script for entries' copies (absolute paths): the macro's
    ; own code plus the plugins, so a clash with a macro name fails too.
    static LibDir := RegExReplace(A_LineFile, "\\[^\\]+$")
    static CheckText(root, entries) {
        t := "#Requires AutoHotkey v2.0`r`n#Include " Plugins.LibDir "\App.ahk`r`n"
        for e in entries
            t .= "#Include " Plugins.CachePath(root, e) "`r`n"
        return t
    }

    ; AutoHotkey's error text made short: the copy's path becomes the
    ; plugin's file, the root and user name go.
    static CleanError(root, text, entries := "") {
        s := Trim(String(text), " `t`r`n")
        r := RTrim(root, "\/")
        if IsObject(entries)
            for e in entries
                s := StrReplace(s, Plugins.CachePath(root, e), e["file"] (e["folder"] ? "\" Plugins._MainName(e) : ""))
        s := StrReplace(s, Plugins.CacheDir(root) "\", "")
        s := StrReplace(s, r "\", "")
        s := RegExReplace(s, "i)\b([A-Z]:[\\/]Users[\\/])[^\\/\s]+", "$1<user>")
        s := RegExReplace(s, "\s*[\r\n]+\s*", "  ")
        s := StrReplace(s, "==> ", "")
        return SubStr(s, 1, 300)
    }

    ; The entry whose file the error names ("" = none named)
    static Culprit(root, text, entries) {
        for e in entries
            if InStr(text, Plugins.CachePath(root, e))
                return e
        for e in entries
            if (e["folder"] && InStr(text, Plugins.CacheDir(root) "\" e["id"] "\"))
                return e
        return ""
    }
}

; ---------------------------------------------------------------------------
; PluginApi: what a plugin gets as this.api (see the API above).
; ---------------------------------------------------------------------------
class PluginApi {
    __New(host, entry) {
        this._host := host
        this._e := entry
        this.Id := entry["id"]
        this.Name := entry["name"]
        this.Dir := entry["dir"]
        this.Section := entry["builtin"] && entry.Has("section") && entry["section"] != "" ? entry["section"] : "Plugin." entry["id"]
    }
    Log(text) => this._host.Log(this.Name ": " String(text))
    _Setting(key) {
        for s in this._e["settings"]
            if (s["key"] = key)
                return s
        return ""
    }
    _Path(key) {
        s := this._Setting(key)
        return IsObject(s) ? PluginHost.SettingPath(this._e, s) : this.Section "." key
    }
    Get(key, default?) {
        cfg := this._host.cfg
        s := this._Setting(key)
        d := IsSet(default) ? default : !IsObject(s) ? "" : s["type"] = "int" ? Integer(s["def"]) : s["def"]
        return IsObject(cfg) ? cfg.Get(this._Path(key), d) : d
    }
    Set(key, value) {
        if IsObject(this._host.cfg)
            this._host.cfg.Set(this._Path(key), value)
    }
    Save() {
        if IsObject(this._host.cfg)
            this._host.cfg.Save()
    }
    Notify(event, title, text := "", color := 0x8FD3FF) => this._host.Notify(this._e, event, title, text, color)
    Biome() => this._host.Biome()
    IsStarted() => this._host.IsStarted()
    ; the macro itself (built-in plugins only; not part of the public API)
    App => this._e["builtin"] ? this._host.app : ""
}

; ---------------------------------------------------------------------------
; PluginTask: a plugin's Task() as a scheduler task (lib\Scheduler.ahk):
; only while the plugin is on, every call guarded.
; ---------------------------------------------------------------------------
class PluginTask {
    __New(host, entry, task) {
        this._host := host
        this._e := entry
        this._t := task
        this.name := "plugin:" entry["id"]
        p := 50
        try p := task.priority
        if !IsInteger(p)
            p := 50
        if !entry["builtin"]
            p := Max(Plugins.ExternalMinPri, Min(Plugins.ExternalMaxPri, p))
        this.priority := p
    }
    Inner => this._t
    CanRun(state) {
        if !this._host.IsOn(this._e["id"])
            return false
        try return this._t.CanRun(state) ? true : false
        catch Any as e {
            this._host.Failed(this._e, "CanRun", e)
            return false
        }
    }
    Run(ctx) {
        try return this._t.Run(ctx)
        catch Any as e {
            this._host.Failed(this._e, "Run", e)
            return 0
        }
    }
    Holds(nxt) {
        if !HasMethod(this._t, "Holds")
            return false
        try return this._t.Holds(nxt) ? true : false
        return false
    }
}

; ---------------------------------------------------------------------------
; PluginHost: the plugins of one running macro.
;
;   h := PluginHost(deps)   deps (all optional except cfg):
;     cfg        Config
;     root       the macro folder (default App.DefaultRoot())
;     log        (text) -> logs
;     app        the App (built-in plugins, Notify, Biome, IsStarted)
;     builtins   Array of [className, manifest Map] (default PluginHost.Builtins)
;     validate   (root, entries) -> {ok, text}: the checker (default: a
;                separate AutoHotkey /Validate, PluginHost.RunCheck)
;     resolve    (className) -> the class or "" (default: by name)
;   h.Boot()            scan, start the plugins loaded this run, OnLoad
;   h.Entries           built-in first, then plugins\ in name order
;   h.Rescan()          scan plugins\ again (new / changed / removed files)
;   h.SetOn(id, on)     -> status text; switching a plugin on that is not
;                       loaded yet checks it and asks for a restart
;   h.IsOn(id)          on in cfg, loaded, not stopped for errors
;   h.Status(e)         "On", "Off", "Restart to load", "Error: ..."
;   h.RestartWanted     true when a restart would load / unload something
;   h.Call(hook, args*) every loaded plugin that is on
;   h.Tasks()           Array of PluginTask
; ---------------------------------------------------------------------------
class PluginHost {
    ; built-in plugins: [class name, manifest]. They ship with the macro
    ; (lib\plugins\), are always loaded and need no check or restart.
    static Builtins := []

    __New(deps := "") {
        g := (k, d) => (IsObject(deps) && deps.HasOwnProp(k)) ? deps.%k% : d
        this.cfg := g("cfg", "")
        this.root := g("root", "")
        if (this.root = "")
            try this.root := App.DefaultRoot()
        this._logFn := g("log", "")
        this.app := g("app", "")
        this._builtins := g("builtins", PluginHost.Builtins)
        this._validateFn := g("validate", "")
        if !IsObject(this._validateFn)
            this._validateFn := (root, entries) => PluginHost.RunCheck(root, entries)
        this._resolveFn := g("resolve", "")
        if !IsObject(this._resolveFn)
            this._resolveFn := (name) => PluginHost.Resolve(name)
        this.Entries := []
        this._obj := Map()          ; id -> plugin object (loaded this run)
        this._errs := Map()         ; id -> errors this session
        this._dead := Map()         ; id -> why it was stopped this session
        this._loaded := Map()       ; id -> stamp of the copy loaded this run
        this._tasks := Map()        ; id -> PluginTask
        this._need := Map()         ; id -> "load" / "unload" / "reload"
        this.Busy := false
    }

    Log(text) {
        if IsObject(this._logFn)
            try this._logFn.Call(text)
    }

    static Resolve(name) {
        try {
            c := %name%
            if ((c is Class) && HasBase(c.Prototype, MoontidePlugin.Prototype))
                return c
        }
        return ""
    }

    ; ---- boot / scan ---------------------------------------------------------

    ; The built-in plugins (App: at construction, tests too).
    Boot() {
        this.Entries := []
        for b in this._builtins {
            e := Plugins._Blank(b[1])
            for k, v in b[2]
                e[k] := v
            e["builtin"] := true
            e["class"] := b[1]
            e["ok"] := true
            this.Entries.Push(e)
            if this._Start(e)
                this._Hook(e, "OnLoad")
        }
    }

    ; The plugins in plugins\ (App.Boot, a normal start only): the ones
    ; _enabled.ahk loaded this run start; new / changed ones are checked.
    BootExternal() {
        stamps := this._ReadStamps()
        ext := []
        for e in this._ScanExternal() {
            this.Entries.Push(e)
            if (e["ok"] && stamps.Has(e["id"]) && IsObject(this._resolveFn.Call(e["class"]))) {
                this._loaded[e["id"]] := stamps[e["id"]]
                if this._Start(e)
                    ext.Push(e)
            }
        }
        ; loaded from an older _enabled.ahk but its file is gone now
        for id, st in stamps
            if !this._loaded.Has(id) && IsObject(this._resolveFn.Call(this._ClassFromStamps(id)))
                this._loaded[id] := st
        this._Settle()
        for e in ext
            if this.IsOn(e["id"])
                this._Hook(e, "OnLoad")
    }

    _ScanExternal() {
        taken := []
        for b in this._builtins
            taken.Push(b[2]["id"])
        return Plugins.Scan(Plugins.Dir(this.root), taken)
    }

    _Start(e) {
        id := e["id"]
        cls := this._resolveFn.Call(e["class"])
        if !IsObject(cls) {
            e["ok"] := false
            e["reason"] := "class " e["class"] " not found in the plugin (it must extend MoontidePlugin)"
            return false
        }
        try {
            obj := cls()
            obj.api := PluginApi(this, e)
            this._obj[id] := obj
            t := obj.Task()
            if IsObject(t)
                this._tasks[id] := PluginTask(this, e, t)
            return true
        } catch Any as err {
            this._obj.Delete(id)
            e["ok"] := false
            e["reason"] := "could not start: " this._ErrText(err)
            return false
        }
    }

    ; Scan plugins\ again: new files get rows, changed ones are checked.
    Rescan() {
        keep := []
        for e in this.Entries
            if e["builtin"]
                keep.Push(e)
        old := Map()
        for e in this.Entries
            if !e["builtin"]
                old[e["id"] "|" e["file"]] := e
        for e in this._ScanExternal() {
            ; a plugin that stopped itself / failed to start keeps its reason
            k := e["id"] "|" e["file"]
            if (old.Has(k) && !old[k]["ok"] && e["ok"] && old[k]["stamp"] = e["stamp"] && this._loaded.Has(e["id"]))
                e := old[k]
            keep.Push(e)
        }
        this.Entries := keep
        this._Settle()
        return this.Entries
    }

    ; Makes _enabled.ahk match what is switched on: each plugin that is on,
    ; ok and not loaded as it is now is checked (alone, then all together);
    ; the ones that pass are copied and included. Works out RestartWanted.
    _Settle() {
        this._need := Map()
        want := []
        fresh := []
        for e in this.Entries {
            if (e["builtin"] || !e["ok"] || !this._Wanted(e))
                continue
            if (this._loaded.Has(e["id"]) && this._loaded[e["id"]] = e["stamp"]) {
                want.Push(e)
                continue
            }
            fresh.Push(e)
        }
        stamps := this._ReadStamps()
        for e in fresh {
            ; checked before with this very stamp: no second check
            if (stamps.Has(e["id"]) && stamps[e["id"]] = e["stamp"] && FileExist(Plugins.CachePath(this.root, e))) {
                want.Push(e)
                this._need[e["id"]] := this._loaded.Has(e["id"]) ? "reload" : "load"
                continue
            }
            why := this._CheckOne(e, want)
            if (why = "") {
                want.Push(e)
                this._need[e["id"]] := this._loaded.Has(e["id"]) ? "reload" : "load"
            } else {
                e["ok"] := false
                e["reason"] := why
                this.Log("Plugins: " e["file"] " not loaded: " why)
            }
        }
        for id, st in this._loaded {
            found := false
            for e in want
                if (e["id"] = id)
                    found := true
            if !found
                this._need[id] := "unload"
        }
        this._Write(want)
    }

    _Wanted(e) => Plugins.On(this.cfg, e["id"], e["def"])

    ; "" when e's copy (with the ones already in) passes the checker, else why.
    _CheckOne(e, others) {
        this.Busy := true
        try {
            try this._Copy(e)
            catch Any as err
                return "could not copy it to plugins\" Plugins.CacheName ": " this._ErrText(err)
            r := this._validateFn.Call(this.root, [e])
            if !r.ok
                return "error in the code: " Plugins.CleanError(this.root, r.text, [e])
            if others.Length {
                all := others.Clone()
                all.Push(e)
                r := this._validateFn.Call(this.root, all)
                if !r.ok {
                    c := Plugins.Culprit(this.root, r.text, all)
                    return "clashes with " ((IsObject(c) && c !== e) ? c["file"] : "another plugin") ": " Plugins.CleanError(this.root, r.text, all)
                }
            }
            return ""
        } finally {
            this.Busy := false
        }
    }

    _Copy(e) {
        cache := Plugins.CacheDir(this.root)
        if !DirExist(cache)
            DirCreate(cache)
        if e["folder"] {
            dst := cache "\" e["id"]
            if DirExist(dst)
                DirDelete(dst, true)
            DirCopy(e["dir"], dst, 1)
        } else
            FileCopy(e["path"], Plugins.CachePath(this.root, e), 1)
    }

    _Write(want) {
        cache := Plugins.CacheDir(this.root)
        if (!want.Length && !DirExist(cache))
            return
        try {
            if !DirExist(cache)
                DirCreate(cache)
            PluginHost._Put(cache "\_enabled.ahk", Plugins.IncludeText(this.root, want))
            st := ""
            for e in want
                st .= e["id"] "=" e["stamp"] "|" e["class"] "`r`n"
            PluginHost._Put(cache "\stamps.txt", st)
        } catch Any as err {
            this.Log("Plugins: could not write the plugin list: " this._ErrText(err))
        }
    }

    static _Put(path, text) {
        tmp := path ".tmp"
        if FileExist(tmp)
            FileDelete(tmp)
        FileAppend(text, tmp, "UTF-8")
        FileMove(tmp, path, 1)
    }

    _ReadStamps() {
        m := Map()
        this._stampCls := Map()
        p := Plugins.CacheDir(this.root) "\stamps.txt"
        if !FileExist(p)
            return m
        try {
            for ln in StrSplit(FileRead(p, "UTF-8"), "`n", "`r") {
                if RegExMatch(ln, "^([a-z][a-z0-9_]*)=(.*)\|([A-Za-z_]\w*)$", &mm) {
                    m[mm[1]] := mm[2]
                    this._stampCls[mm[1]] := mm[3]
                }
            }
        }
        return m
    }
    _ClassFromStamps(id) => (this.HasOwnProp("_stampCls") && this._stampCls.Has(id)) ? this._stampCls[id] : ""

    ; The default checker: AutoHotkey (this very exe) /Validate on the macro
    ; plus the plugins, in a hidden separate process. -> {ok, text}
    static RunCheck(root, entries) {
        cache := Plugins.CacheDir(root)
        if !DirExist(cache)
            DirCreate(cache)
        stub := cache "\_check.ahk"
        out := cache "\_check.txt"
        PluginHost._Put(stub, Plugins.CheckText(root, entries))
        try FileDelete(out)
        rc := RunWait(A_ComSpec ' /c ""' A_AhkPath '" /ErrorStdOut /Validate "' stub '" > "' out '" 2>&1"', cache, "Hide")
        text := ""
        try text := FileRead(out, "UTF-8")
        try FileDelete(out)
        try FileDelete(stub)
        return {ok: rc = 0, text: text}
    }

    ; ---- on / off ---------------------------------------------------------

    Find(id) {
        if (id = "")
            return ""
        for e in this.Entries
            if (e["id"] = id)
                return e
        return ""
    }
    Obj(id) => this._obj.Has(id) ? this._obj[id] : ""

    IsOn(id) {
        if (!this._obj.Has(id) || this._dead.Has(id))
            return false
        e := this.Find(id)
        if !IsObject(e)
            return false
        if (!e["builtin"] && (!this._loaded.Has(id) || this._loaded[id] != e["stamp"]))
            return false                 ; changed since it was loaded: the new code waits for a restart
        return this._Wanted(e)
    }

    RestartWanted {
        get {
            for id, why in this._need
                if (why != "unload")
                    return true
            return false
        }
    }

    ; -> what the switch did, for the page's status line
    SetOn(id, on) {
        e := this.Find(id)
        if !IsObject(e)
            return "No plugin " id
        if !IsObject(this.cfg)
            return "No settings"
        this.cfg.Set(Plugins.Key(id), on ? 1 : 0)
        this.cfg.Save()
        if this._dead.Has(id) && on {
            this._dead.Delete(id)          ; switched on again: one more chance
            this._errs.Delete(id)
        }
        if e["builtin"] {
            this.Log("Plugins: " e["name"] (on ? " on" : " off"))
            return e["name"] (on ? " is on" : " is off")
        }
        if (on && !e["ok"])
            return e["name"] " cannot load: " e["reason"]
        this._Settle()
        this.Log("Plugins: " e["name"] (on ? " on" : " off"))
        if !on
            return e["name"] " is off"
        if !e["ok"]
            return e["name"] " cannot load: " e["reason"]
        return this.IsOn(id) ? e["name"] " is on" : e["name"] " checked: restart the macro to load it"
    }

    ; Status(e) for the page: the English words translated, the reason kept
    static StatusText(s) {
        if RegExMatch(s, "^(Error|Stopped): (.*)$", &m)
            return PluginHost._T(m[1]) ": " m[2]
        ; "On" / "Off" are the pill switches' own words: the list says "Is on"
        return PluginHost._T(s = "On" ? "Is on" : s = "Off" ? "Is off" : s)
    }
    static _T(s) {
        try return I18n.T(s)
        return s
    }

    ; The cfg path of setting s (Map key/type/def/label) of plugin entry e:
    ; [Plugin.<id>] key (a built-in plugin: its own section); a secret's key
    ; ends in _secret, so settings exports and log zips leave it out
    ; (LogBundle.SecretKeyRe).
    static SettingPath(e, s) {
        sec := (e["builtin"] && e.Has("section") && e["section"] != "") ? e["section"] : "Plugin." e["id"]
        return sec "." s["key"] (s["type"] = "secret" ? "_secret" : "")
    }

    Status(e) {
        id := e["id"]
        if !e["ok"]
            return "Error: " e["reason"]
        if this._dead.Has(id)
            return "Stopped: " this._dead[id]
        on := this._Wanted(e)
        if e["builtin"]
            return on ? "On" : "Off"
        if on && this._need.Has(id) && this._need[id] != "unload"
            return this._need[id] = "reload" ? "Changed: restart to load the new version" : "Restart to load"
        return on ? "On" : "Off"
    }

    ; ---- hooks ------------------------------------------------------------

    Call(hook, args*) {
        for e in this.Entries {
            if this.IsOn(e["id"])
                this._Hook(e, hook, args*)
        }
    }

    _Hook(e, hook, args*) {
        obj := this._obj[e["id"]]
        if !HasMethod(obj, hook)
            return ""
        try return obj.%hook%(args*)
        catch Any as err
            this.Failed(e, hook, err)
        return ""
    }

    Failed(e, where, err) {
        id := e["id"]
        n := (this._errs.Has(id) ? this._errs[id] : 0) + 1
        this._errs[id] := n
        msg := this._ErrText(err)
        this.Log("Plugins: " e["name"] " error in " where ": " msg)
        if (n >= Plugins.MaxErrors && !this._dead.Has(id)) {
            this._dead[id] := "too many errors (last: " msg ")"
            this.Log("Plugins: " e["name"] " stopped for this session after " n " errors")
        }
    }

    _ErrText(err) {
        s := (err is Error) ? err.Message (err.Extra != "" ? " (" err.Extra ")" : "") : String(err)
        s := RegExReplace(s, "\s*[\r\n]+\s*", " ")
        try s := UiLogic.Scrub(s)
        return SubStr(s, 1, 200)
    }

    Tasks() {
        out := []
        for id, t in this._tasks
            out.Push(t)
        return out
    }

    ; ---- for the API ----------------------------------------------------

    Notify(e, event, title, text, color) {
        ok := false
        for ev in Config.EventTypes
            if (ev = event)
                ok := true
        if !ok
            throw ValueError("Notify: unknown event " event)
        wh := (IsObject(this.app) && this.app.HasOwnProp("wh")) ? this.app.wh : ""
        if !IsObject(wh)
            return false
        wh.Send(event, String(title), String(text), color)
        return true
    }
    Biome() {
        try return this.app.state.biome
        return ""
    }
    IsStarted() {
        try return this.app.IsStarted() ? true : false
        return false
    }
}
