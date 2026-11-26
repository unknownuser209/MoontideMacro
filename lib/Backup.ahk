#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\Config.ahk
#Include %A_LineFile%\..\Json.ahk
#Include %A_LineFile%\..\Brand.ahk
#Include %A_LineFile%\..\I18n.ahk
; ---------------------------------------------------------------------------
; Backup: "Move to another PC" (Settings > Profiles). One JSON file with
; EVERYTHING that is the player's own: every setting (webhooks, the private
; server link, the Discord bot, Dev, ... literally all of settings.ini), the
; calibration, walks, quests, merchants, potions, biomes, stats, auras and
; the saved themes with their pictures. Unlike Profiles' Export (made to send
; to a friend, secrets left out) this file is personal: never share it.
;
;   Backup.Export(root, now := A_Now, tag := "") -> {ok, path, name, n, files,
;       themes, msg}: writes <root>\exports\moontide_backup_[<tag>_]<yyyyMMdd_HHmmss>.json
;   Backup.Read(path) -> Check's result for that file (nothing is written)
;   Backup.Check(data) -> {ok, msg, ...plan} for a parsed backup. Refuses a
;       wrong format / newer version, any file it does not know (only
;       Backup.Files, themes\<theme name>.<ext> and imported\<name>.<ext>:
;       never "..", never an absolute path), broken JSON in a data file, a
;       bad picture and settings that are not section -> key -> text.
;   Backup.ImportData(root, data, now := A_Now) / Backup.Import(root, path, now)
;       -> {ok, msg, n, files, themes, before, beforeName, screenNote}: checks
;       first (nothing written when it fails), then saves the current state as
;       exports\moontide_backup_before_import_<stamp>.json, then writes the
;       files, the themes and settings.ini. Themes on this PC that the file
;       does not have stay; settings.ini is replaced as a whole.
;   Backup.ScreenNote(screen) -> "" or the "calibration may need redoing"
;       line when the backup's screen size / scale is not this PC's.
;   Backup.LogLine(verb, r) -> "Backup: exported 214 settings, 9 files, 3 themes"
;
; File: {format: "moontide-backup", version: 1, macroVersion, made,
;   screen: {w, h, dpi}, settings: {section: {key: value}} (webhooks as the
;   ini's Webhook.N sections), files: {"data\\x.json": text}, themes:
;   {"<name>.moontheme": {text}, "<name>.png": {b64}}, extras: {"General.alertSound":
;   {name, b64}}}.
; Paths in settings (General.alertSound, UI.customPictureFile): the file is
; put in the backup when it is small enough; an import writes it to
; <root>\imported\ and points the setting there. A path that is not in the
; backup and does not exist on the new PC (or is a network path) goes back
; to the default.
; SECRETS: values are never logged, never put in a message or an error.
; Only counts leave this file.
; ---------------------------------------------------------------------------

class Backup {
    static Format := "moontide-backup"
    static Version := 1
    ; the player's own files (Updater.Protected minus run-time state:
    ; last_biome, schedule_state, summary_last, update_skip, whatsnew,
    ; *state*.json and cal_health belong to this PC's runs)
    static Files := ["data\calibration.json", "data\routes.json", "data\quests.json", "data\merchants.json"
        , "data\potions.json", "data\biomes.json", "data\auras_had.txt", "data\potion_usage.json"
        , "data\minions_routes.json", "data\auras_learnt.json", "data\stats.json", "data\aura_hints.json"]
    ; settings that hold a file path: [Section.key, default, extensions]
    static PathKeys := [["General.alertSound", "*48", ["wav", "mp3"]]
        , ["UI.customPictureFile", "", ["png", "jpg", "jpeg", "bmp", "gif"]]]
    static ImportDir := "imported"
    static ExportDir := "exports"
    static MaxBackup := 96 * 1024 * 1024    ; the whole file
    static MaxText := 16 * 1024 * 1024      ; one data file / theme text
    static MaxBin := 5 * 1024 * 1024        ; one picture / sound (ThemeStore.MaxPicture)
    static ThemeRx := "i)^[A-Za-z0-9 _()\-]{1,32}\.(moontheme|png|jpg|jpeg|bmp|gif)$"
    static Reserved := "i)^(CON|PRN|AUX|NUL|COM\d|LPT\d)$"
    static Note := "Your own Moontide Macro backup. It holds your private server link, webhook links and bot token: never share it."
    ; () -> Map(w, h, dpi) of this PC. Tests replace it.
    static ScreenFn := () => Map("w", A_ScreenWidth, "h", A_ScreenHeight, "dpi", A_ScreenDPI)

    ; ---- export ---------------------------------------------------------------

    ; -> {data (Map), n, files, themes, extras}. Throws Error (no value in it)
    ; when settings.ini exists but cannot be read.
    static Build(root, now := "") {
        root := RTrim(root, "\/")
        if (now = "")
            now := A_Now
        settings := Map(), extras := Map(), n := 0
        if FileExist(root "\settings.ini") {
            cfg := Config.Load(root)
            if cfg.readFail
                throw Error("settings.ini could not be read")
            for sec, keys in cfg.sections {
                m := Map()
                for k, v in keys
                    m[k] := String(v), n++
                settings[sec] := m
            }
            for i, h in cfg.Webhooks() {
                ev := ""
                for e in h["events"]
                    ev .= (ev = "" ? "" : ",") e
                settings["Webhook." i] := Map("name", h["name"], "url", h["url"], "mention", h["mention"]
                    , "enabled", String(h["enabled"]), "events", ev)
                n += 5
            }
            ; a sound / picture of your own goes in the file
            for spec in Backup.PathKeys {
                v := Trim(String(cfg.Get(spec[1], "")), " `t`"")
                if (v = "" || SubStr(v, 1, 1) = "*" || SubStr(v, 1, 2) = "\\" || !RegExMatch(v, "^[A-Za-z]:\\"))
                    continue
                try {
                    a := FileExist(v)
                    if (a = "" || InStr(a, "D") || FileGetSize(v) > Backup.MaxBin || FileGetSize(v) = 0)
                        continue
                    name := Backup._SafeName(RegExReplace(v, "^.*\\"), spec[3])
                    if (name = "")
                        continue
                    b64 := Backup.B64Encode(FileRead(v, "RAW"))
                    if (b64 != "")
                        extras[spec[1]] := Map("name", name, "b64", b64)
                }
            }
        }
        files := Map(), nf := 0
        for rel in Backup.Files {
            p := root "\" rel
            a := FileExist(p)
            if (a = "" || InStr(a, "D"))
                continue
            if (FileGetSize(p) > Backup.MaxText)
                continue
            files[rel] := FileRead(p, "UTF-8")
            nf++
        }
        themes := Map(), nt := 0
        if DirExist(root "\themes") {
            Loop Files, root "\themes\*", "F" {
                nm := A_LoopFileName
                if !RegExMatch(nm, Backup.ThemeRx, &m) || RegExMatch(RegExReplace(nm, "\.[^.]*$"), Backup.Reserved)
                    continue
                if (StrLower(m[1]) = "moontheme") {
                    if (A_LoopFileSize > Backup.MaxText)
                        continue
                    themes[nm] := Map("text", FileRead(A_LoopFilePath, "UTF-8"))
                    nt++
                } else {
                    if (A_LoopFileSize = 0 || A_LoopFileSize > Backup.MaxBin)
                        continue
                    b64 := Backup.B64Encode(FileRead(A_LoopFilePath, "RAW"))
                    if (b64 != "")
                        themes[nm] := Map("b64", b64)
                }
            }
        }
        data := Map("format", Backup.Format, "version", Backup.Version, "macroVersion", Brand.Version
            , "made", FormatTime(now, "yyyy-MM-dd HH:mm:ss"), "note", Backup.Note
            , "screen", Backup.ScreenFn.Call()
            , "settings", settings, "files", files, "themes", themes, "extras", extras)
        return {data: data, n: n, files: nf, themes: nt, extras: extras.Count}
    }

    static Export(root, now := "", tag := "") {
        root := RTrim(root, "\/")
        if (now = "")
            now := A_Now
        try {
            b := Backup.Build(root, now)
            dir := root "\" Backup.ExportDir
            if !DirExist(dir)
                DirCreate(dir)
            base := "moontide_backup_" (tag != "" ? tag "_" : "") FormatTime(now, "yyyyMMdd_HHmmss")
            name := base ".json", i := 1
            while FileExist(dir "\" name)
                name := base "_" (++i) ".json"
            Config._WriteText(dir "\" name, Json.Stringify(b.data) "`n")
            return {ok: 1, path: dir "\" name, name: name, n: b.n, files: b.files, themes: b.themes
                , msg: I18n.F("Saved {1} settings, {2} files and {3} themes to exports\{4}", b.n, b.files, b.themes, name)}
        } catch {
            return {ok: 0, path: "", name: "", n: 0, files: 0, themes: 0
                , msg: I18n.F("Not exported: {1}", I18n.T("your settings could not be read or the file could not be written"))}
        }
    }

    static LogLine(verb, r) => "Backup: " verb " " r.n " settings, " r.files " files, " r.themes " themes"

    ; ---- import ---------------------------------------------------------------

    static Read(path) {
        text := ""
        try {
            a := FileExist(path)
            if (a = "" || InStr(a, "D"))
                throw Error("missing")
            if (FileGetSize(path) > Backup.MaxBackup)
                return Backup._Bad("the file is too big")
            text := FileRead(path, "UTF-8")
        } catch {
            return {ok: 0, msg: I18n.T("Not imported: the file could not be read")}
        }
        try
            data := Json.Parse(text)
        catch
            return Backup._Bad("this is not a Moontide backup file")
        return Backup.Check(data)
    }

    static _Bad(why) => {ok: 0, msg: I18n.F("Not imported: {1}", I18n.T(why))}

    ; -> {ok, msg, data, plan [{rel, text} | {rel, bin}], sections, hooks,
    ; extras (Section.key -> rel), n, files, themes, screenNote}
    static Check(data) {
        if !(data is Map) || data.Get("format", "") !== Backup.Format
            return Backup._Bad("this is not a Moontide backup file")
        v := data.Get("version", "")
        if !(IsInteger(v) && Integer(v) >= 1)
            return Backup._Bad("this is not a Moontide backup file")
        if (Integer(v) > Backup.Version)
            return Backup._Bad("the backup was made by a newer version of the macro")
        settings := data.Get("settings", "")
        if !(settings is Map)
            return Backup._Bad("the settings in the backup are broken")
        for k in ["files", "themes", "extras"]
            if (data.Has(k) && !(data[k] is Map))
                return Backup._Bad("this is not a Moontide backup file")
        plan := [], seen := Map()
        seen.CaseSense := "Off"
        ; settings: section -> key -> text
        sections := Config._CIMap(), hookRows := Map(), n := 0
        for sec, keys in settings {
            s := Trim(String(sec))
            if !(keys is Map) || !RegExMatch(s, "^[^\[\]\r\n;#=]{1,64}$") || (sections.Has(s) && !RegExMatch(s, "^Webhook\.\d+$"))
                return Backup._Bad("the settings in the backup are broken")
            row := Config._CIMap()
            for k, val in keys {
                key := Trim(String(k))
                if (val is Object) || !RegExMatch(key, "^[^=\r\n\[\];#][^=\r\n]{0,99}$")
                    return Backup._Bad("the settings in the backup are broken")
                val := Config._Clean(val)
                if (StrLen(val) > 8000)
                    return Backup._Bad("the settings in the backup are broken")
                row[key] := val
                n++
            }
            if RegExMatch(s, "^Webhook\.(\d{1,4})$", &m) {
                if hookRows.Has(Integer(m[1]))
                    return Backup._Bad("the settings in the backup are broken")
                hookRows[Integer(m[1])] := row
            } else
                sections[s] := row
        }
        hooks := []
        for _, row in hookRows {        ; Integer keys enumerate in number order
            h := Map()
            for k in ["name", "url", "mention", "enabled", "events"]
                h[k] := row.Has(k) ? row[k] : (k = "enabled" ? "1" : "")
            hooks.Push(Config._NormHook(h))
        }
        ; data files: only the known ones, JSON that parses
        nf := 0
        for rel, txt in data.Get("files", Map()) {
            canon := Backup._Known(rel)
            if (canon = "" || seen.Has(canon))
                return Backup._Bad("the backup holds a file it may not write")
            if !(txt is String) || StrLen(txt) > Backup.MaxText
                return Backup._Bad("a data file in the backup is broken")
            if (SubStr(canon, -5) = ".json") {
                try
                    pv := Json.Parse(txt)
                catch
                    return Backup._Bad("a data file in the backup is broken")
                if !(pv is Map || pv is Array)
                    return Backup._Bad("a data file in the backup is broken")
            }
            seen[canon] := 1
            plan.Push({rel: canon, text: txt})
            nf++
        }
        ; themes: <theme name>.moontheme text and its pictures
        nt := 0
        for nm, e in data.Get("themes", Map()) {
            nm := String(nm)
            if !RegExMatch(nm, Backup.ThemeRx, &m) || RegExMatch(RegExReplace(nm, "\.[^.]*$"), Backup.Reserved)
                || seen.Has("themes\" nm)
                return Backup._Bad("the backup holds a file it may not write")
            if !(e is Map)
                return Backup._Bad("a theme in the backup is broken")
            seen["themes\" nm] := 1
            if (StrLower(m[1]) = "moontheme") {
                t := e.Get("text", "")
                if !(t is String) || t = "" || StrLen(t) > Backup.MaxText
                    return Backup._Bad("a theme in the backup is broken")
                plan.Push({rel: "themes\" nm, text: t})
                nt++
            } else {
                buf := Backup.B64Decode(e.Get("b64", ""))
                if !IsObject(buf) || buf.Size = 0 || buf.Size > Backup.MaxBin
                    return Backup._Bad("a theme in the backup is broken")
                plan.Push({rel: "themes\" nm, bin: buf})
            }
        }
        ; a sound / picture a setting points at
        extras := Map()
        for path, e in data.Get("extras", Map()) {
            spec := Backup._PathSpec(path)
            if !IsObject(spec) || !(e is Map)
                return Backup._Bad("the backup holds a file it may not write")
            name := String(e.Get("name", ""))
            if (Backup._SafeName(name, spec[3]) !== name || seen.Has(Backup.ImportDir "\" name))
                return Backup._Bad("the backup holds a file it may not write")
            buf := Backup.B64Decode(e.Get("b64", ""))
            if !IsObject(buf) || buf.Size = 0 || buf.Size > Backup.MaxBin
                return Backup._Bad("the backup holds a file it may not write")
            rel := Backup.ImportDir "\" name
            seen[rel] := 1
            plan.Push({rel: rel, bin: buf})
            extras[spec[1]] := rel
        }
        for item in plan
            if !Backup.SafeRel(item.rel)
                return Backup._Bad("the backup holds a file it may not write")
        return {ok: 1, msg: "", data: data, plan: plan, sections: sections, hooks: hooks, extras: extras
            , n: n, files: nf, themes: nt, screenNote: Backup.ScreenNote(data.Get("screen", ""))}
    }

    static Import(root, path, now := "") {
        r := Backup.Read(path)
        if !r.ok
            return r
        return Backup.ImportData(root, r.data, now)
    }

    static ImportData(root, data, now := "") {
        root := RTrim(root, "\/")
        c := Backup.Check(data)
        if !c.ok
            return c
        ; the state before the import first: no copy, no import
        before := Backup.Export(root, now, "before_import")
        if !before.ok
            return Backup._Bad("your current settings could not be saved first")
        try {
            for item in c.plan {
                if !Backup.SafeRel(item.rel)
                    throw Error("unsafe path")
                p := root "\" item.rel
                d := RegExReplace(p, "\\[^\\]*$")
                if !DirExist(d)
                    DirCreate(d)
                if item.HasOwnProp("text")
                    Config._WriteText(p, item.text)
                else
                    Backup._WriteBin(p, item.bin)
            }
            sections := c.sections
            for spec in Backup.PathKeys {
                dot := InStr(spec[1], ".", , -1)
                sec := SubStr(spec[1], 1, dot - 1), key := SubStr(spec[1], dot + 1)
                if c.extras.Has(spec[1]) {
                    if !sections.Has(sec)
                        sections[sec] := Config._CIMap()
                    sections[sec][key] := root "\" c.extras[spec[1]]
                } else if (sections.Has(sec) && sections[sec].Has(key) && !Backup._PathOk(sections[sec][key]))
                    sections[sec][key] := spec[2]
            }
            ; (a backup made where there was no settings.ini has none: the
            ; settings here stay)
            if (sections.Count || c.hooks.Length) {
                cfg := Config.Load(root)
                cfg.readFail := false
                cfg.sections := sections
                cfg.SetWebhooks(c.hooks)
                cfg.Save()
            }
        } catch {
            return {ok: 0, before: before.path, beforeName: before.name
                , msg: I18n.F("Import stopped partway. Your old settings are in exports\{1}: import that file to go back.", before.name)}
        }
        return {ok: 1, n: c.n, files: c.files, themes: c.themes, before: before.path, beforeName: before.name
            , screenNote: c.screenNote
            , msg: I18n.F("Imported {1} settings, {2} files and {3} themes. Your old ones are in exports\{4}.", c.n, c.files, c.themes, before.name)}
    }

    ; "" when the backup's screen matches this PC (or says nothing), else the warning
    static ScreenNote(s) {
        if !(s is Map)
            return ""
        w := s.Get("w", ""), h := s.Get("h", ""), dpi := s.Get("dpi", "")
        if !(IsInteger(w) && IsInteger(h) && IsInteger(dpi)) || Integer(dpi) <= 0
            return ""
        here := Backup.ScreenFn.Call()
        if (Integer(w) = here["w"] && Integer(h) = here["h"] && Integer(dpi) = here["dpi"])
            return ""
        return I18n.F("The backup was made on a {1}x{2} screen at {3}%, this PC is {4}x{5} at {6}%. Your calibration may need redoing: Help > Check & help > Test my calibration.", w, h, Round(dpi * 100 / 96), here["w"], here["h"], Round(here["dpi"] * 100 / 96))
    }

    ; ---- paths ----------------------------------------------------------------

    ; the Backup.Files spelling of rel, "" when it is not one of them
    static _Known(rel) {
        r := StrLower(StrReplace(String(rel), "/", "\"))
        for f in Backup.Files
            if (r == f)
                return f
        return ""
    }

    ; a relative path inside the macro folder: no drive, no leading slash, no
    ; "..", only plain name characters
    static SafeRel(rel) {
        r := String(rel)
        if (r = "" || InStr(r, "..") || InStr(r, ":") || InStr(r, "/") || RegExMatch(r, "^[\\\s.]"))
            return false
        return RegExMatch(r, "^[A-Za-z0-9 _()\-]+(\\[A-Za-z0-9 _()\-.]+)+$") ? true : false
    }

    static _PathSpec(path) {
        for spec in Backup.PathKeys
            if (spec[1] = String(path))
                return spec
        return ""
    }

    ; name kept when it is a plain file name with one of exts, else ""
    static _SafeName(name, exts) {
        name := String(name)
        if !RegExMatch(name, "^([A-Za-z0-9 _()\-]{1,64})\.([A-Za-z0-9]{1,5})$", &m) || RegExMatch(m[1], Backup.Reserved)
            return ""
        for e in exts
            if (StrLower(m[2]) == e)
                return name
        return ""
    }

    ; a setting path still good on this PC: a system sound ("*48"), empty, or
    ; a local file that exists (a network path is never looked at)
    static _PathOk(v) {
        v := Trim(String(v), " `t`"")
        if (v = "" || SubStr(v, 1, 1) = "*")
            return true
        if !RegExMatch(v, "^[A-Za-z]:\\") || InStr(v, "..")
            return false
        a := FileExist(v)
        return (a != "" && !InStr(a, "D"))
    }

    static _WriteBin(path, buf) {
        tmp := path ".tmp"
        f := FileOpen(tmp, "w")
        f.RawWrite(buf, buf.Size)
        f.Close()
        try
            FileMove(tmp, path, 1)
        catch as e {
            try FileDelete(tmp)
            throw e
        }
    }

    ; ---- base64 ---------------------------------------------------------------

    static B64Encode(buf) {
        n := 0
        if (!IsObject(buf) || buf.Size = 0)
            return ""
        if !DllCall("Crypt32\CryptBinaryToStringW", "Ptr", buf, "UInt", buf.Size, "UInt", 1 | 0x40000000, "Ptr", 0, "UInt*", &n) || n = 0
            return ""
        out := Buffer(n * 2, 0)
        if !DllCall("Crypt32\CryptBinaryToStringW", "Ptr", buf, "UInt", buf.Size, "UInt", 1 | 0x40000000, "Ptr", out, "UInt*", &n)
            return ""
        return StrGet(out, "UTF-16")
    }

    ; base64 text -> Buffer, "" when it is not base64
    static B64Decode(s) {
        if !(s is String)
            return ""
        s := RegExReplace(s, "\s+")
        if (s = "" || !RegExMatch(s, "^[A-Za-z0-9+/]+=*$"))
            return ""
        n := 0
        if !DllCall("Crypt32\CryptStringToBinaryW", "Str", s, "UInt", 0, "UInt", 1, "Ptr", 0, "UInt*", &n, "Ptr", 0, "Ptr", 0) || n = 0
            return ""
        buf := Buffer(n)
        if !DllCall("Crypt32\CryptStringToBinaryW", "Str", s, "UInt", 0, "UInt", 1, "Ptr", buf, "UInt*", &n, "Ptr", 0, "Ptr", 0)
            return ""
        if (n < buf.Size)
            buf.Size := n
        return buf
    }
}
