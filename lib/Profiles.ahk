#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\Config.ahk
#Include %A_LineFile%\..\LogBundle.ahk
; ---------------------------------------------------------------------------
; Profiles: one-click setting sets, and settings export / import (Setup >
; Profiles). Pure logic on a Config; the Dashboard only adds buttons.
;
;   Profiles.Names                      ["AFK fishing", "Biome hunting", ...]
;   Profiles.Description(name)          one line for the button
;   Profiles.Settings(name)             Array of ["Section.key", value]
;   Profiles.Apply(cfg, name)           -> Array of the keys whose value changed
;                                       (in memory; the caller saves). Throws
;                                       ValueError on an unknown name.
;   A profile never touches General.dryRun / Potions.dryRun, webhooks, the
;   private server link or the Remote bot.
;
;   Profiles.ExportText(cfg, userName := A_UserName) -> ini text
;   Profiles.Export(cfg, now := A_Now)  -> {ok, path, n, msg}: writes
;       <cfg.dir>\exports\moontide_settings_<yyyyMMdd>.ini
;   Profiles.ImportText(cfg, text)      -> {n, skipped} (in memory)
;   Profiles.Import(cfg, path)          -> {ok, n, skipped, msg} (in memory)
;
;   Only "shareable" keys are exported or imported (Profiles.Shareable):
;   a key in Config.IniDefaults() (or Profiles.Extra, or Craft.qty_<id>),
;   not a secret by LogBundle._SecretKey (webhook URLs, the private server
;   link, every Remote key, mentions, tokens...), not on Profiles.NoShare
;   (dry run, the updater, first-run flag), and a value the LogBundle scrub
;   leaves alone (no Discord / Roblox links, Windows user paths or secret
;   values). Webhook.N and Remote sections are never read or written. A secret key is
;   left out of the export entirely, and an import never changes one.
; ---------------------------------------------------------------------------

class Profiles {
    static Names := ["AFK fishing", "Biome hunting", "Overnight safe", "Memory Match only"]

    ; real settings the macro reads that have no settings.ini default
    ; ([key, default the code uses])
    static Extra := [["Quests.enabled", "1"], ["Merchant.enabled", "1"], ["Merchant.chatPollSec", "5"], ["Minions.normal", "0"]]

    ; never exported or imported: dry run is only turned off with its own
    ; question, a shared file must not point the updater elsewhere or put
    ; the private server link into webhooks (joinButton)
    static NoShare := ["General.dryRun", "Potions.dryRun", "General.joinButton", "UI.setupDone", "Update.repo", "Update.check", "Update.auto"]

    static Description(name) {
        switch name {
            case "AFK fishing": return "Fish, sell, quests, merchants and crafting. No obby, Memory Match or hunting."
            case "Biome hunting": return "Fishing plus biome items and rare biome alerts. No obby, Memory Match or hunting."
            case "Overnight safe": return "Only the steady parts, with auto-rejoin and anti-AFK. Nothing that spends Drives."
            case "Memory Match only": return "Plays the Memory Match board. Fishing, quests, merchants and crafting off."
        }
        throw ValueError("Profiles: no profile '" name "'")
    }

    static Settings(name) {
        switch name {
            case "AFK fishing": return [
                ["General.fishing", 1], ["General.sellAll", 1], ["Quests.enabled", 1], ["Merchant.enabled", 1], ["Craft.enabled", 1],
                ["Obby.enabled", 0], ["MemoryMatch.enabled", 0], ["Minions.enabled", 0], ["Limbo.enabled", 0],
                ["Recovery.enabled", 1], ["Recovery.antiGhost", 1]]
            case "Biome hunting": return [
                ["General.fishing", 1], ["BiomeItems.enabled", 1], ["BiomeItems.strangeController", 1], ["BiomeItems.biomeRandomizer", 1],
                ["General.everyonePing", 1], ["Medal.onRareBiome", 1], ["Merchant.enabled", 1],
                ["Obby.enabled", 0], ["MemoryMatch.enabled", 0], ["Minions.enabled", 0], ["Limbo.enabled", 0],
                ["Recovery.enabled", 1], ["Recovery.antiGhost", 1]]
            case "Overnight safe": return [
                ["General.fishing", 1], ["Quests.enabled", 1], ["Merchant.enabled", 1], ["Craft.enabled", 1], ["Craft.cauldron", 0],
                ["BiomeItems.biomeSelector", 0], ["Obby.enabled", 0], ["MemoryMatch.enabled", 0], ["Minions.enabled", 0], ["Limbo.enabled", 0],
                ["Recovery.enabled", 1], ["Recovery.antiGhost", 1]]
            case "Memory Match only": return [
                ["MemoryMatch.enabled", 1], ["General.fishing", 0], ["Quests.enabled", 0], ["Merchant.enabled", 0], ["Craft.enabled", 0],
                ["BiomeItems.enabled", 0], ["Obby.enabled", 0], ["Minions.enabled", 0], ["Limbo.enabled", 0],
                ["Recovery.enabled", 1], ["Recovery.antiGhost", 1]]
        }
        throw ValueError("Profiles: no profile '" name "'")
    }

    ; -> keys whose value changed (Array of "Section.key")
    static Apply(cfg, name) {
        changed := []
        for kv in Profiles.Settings(name) {
            key := kv[1], want := String(kv[2])
            if (String(cfg.Get(key, Profiles.DefaultOf(key))) != want) {
                cfg.Set(key, want)
                changed.Push(key)
            }
        }
        return changed
    }

    ; ---- known keys ---------------------------------------------------------

    ; "Section.key" with the defaults' spelling, or "" when the macro has no
    ; such setting.
    static Canon(section, key) {
        d := Config.IniDefaults()
        if (d.Has(section) && d[section].Has(key)) {
            for s, keys in d {
                if (s = section) {
                    for k in keys
                        if (k = key)
                            return s "." k
                }
            }
        }
        for e in Profiles.Extra {
            if (e[1] = section "." key)
                return e[1]
        }
        if (section = "Craft" && RegExMatch(key, "i)^qty_\w+$"))
            return "Craft." key
        return ""
    }

    ; default string of a known key ("" when unknown)
    static DefaultOf(path) {
        dot := InStr(path, ".", , -1)
        sec := SubStr(path, 1, dot - 1), key := SubStr(path, dot + 1)
        d := Config.IniDefaults()
        if (d.Has(sec) && d[sec].Has(key))
            return d[sec][key]
        for e in Profiles.Extra {
            if (e[1] = path)
                return e[2]
        }
        return ""
    }

    ; -> canonical "Section.key" when this key / value may be exported or
    ; imported, else "". secrets: values to keep out (the user's own).
    static Shareable(section, key, value, secrets := "") {
        ; webhooks and the Discord bot belong to one person: never shared
        if RegExMatch(section, "i)^(Webhook|Remote)")
            return ""
        if LogBundle._SecretKey(section, key)
            return ""
        path := Profiles.Canon(section, key)
        if (path = "")
            return ""
        for n in Profiles.NoShare {
            if (n = path)
                return ""
        }
        v := String(value)
        if (InStr(v, "`n") || InStr(v, "`r") || StrLen(v) > 400)
            return ""
        ; a number setting (default all digits, or Craft.qty_<id>) takes a
        ; whole number only
        if ((RegExMatch(Profiles.DefaultOf(path), "^\d+$") || RegExMatch(path, "i)^Craft\.qty_")) && !RegExMatch(v, "^\d{1,10}$"))
            return ""
        ; anything the support-zip scrub would hide (links, user paths, a
        ; secret value) stays out
        if (LogBundle.ScrubText(v, secrets) !== v)
            return ""
        return path
    }

    ; the user's secret values (webhook URLs, link, token, Remote ids...)
    static Secrets(cfg) {
        out := []
        for h in cfg.Webhooks() {
            for k in ["url", "mention"]
                if (StrLen(h[k]) >= 4)
                    out.Push(h[k])
        }
        for sec, keys in cfg.sections {
            for k, v in keys {
                if (LogBundle._SecretKey(sec, k) && StrLen(v) >= 4)
                    out.Push(v)
            }
        }
        return out
    }

    ; ---- export ---------------------------------------------------------------

    static ExportText(cfg, userName := "") {
        if (userName = "")
            userName := A_UserName
        secrets := Profiles.Secrets(cfg)
        out := "; " Brand.Name " settings, exported " FormatTime(, "yyyy-MM-dd") "`r`n"
            . "; No webhooks, server links, bot token or ids. Import it on Setup > Profiles.`r`n`r`n"
        for sec, keys in cfg.sections {
            body := "", head := ""
            for k, v in keys {
                path := Profiles.Shareable(sec, k, v, secrets)
                if (path = "")
                    continue
                if (LogBundle.ScrubText(v, secrets, userName) !== v)
                    continue
                dot := InStr(path, ".", , -1)
                head := SubStr(path, 1, dot - 1)
                body .= SubStr(path, dot + 1) "=" v "`r`n"
            }
            if (body != "")
                out .= "[" head "]`r`n" body "`r`n"
        }
        return out
    }

    static Export(cfg, now := "") {
        try {
            if (now = "")
                now := A_Now
            dir := cfg.dir "\exports"
            if !DirExist(dir)
                DirCreate(dir)
            text := Profiles.ExportText(cfg)
            n := 0
            Loop Parse, text, "`n", "`r"
                if (A_LoopField != "" && !InStr("[;", SubStr(A_LoopField, 1, 1)))
                    n++
            path := dir "\moontide_settings_" FormatTime(now, "yyyyMMdd") ".ini"
            f := FileOpen(path, "w", "UTF-8-RAW")
            f.Write(text)
            f.Close()
            return {ok: 1, path: path, n: n, msg: "Exported " n " settings to exports\" RegExReplace(path, "^.*\\")}
        } catch Any as e {
            return {ok: 0, path: "", n: 0, msg: "Not exported: " UiLogic.Scrub(e is Error ? e.Message : String(e))}
        }
    }

    ; ---- import ---------------------------------------------------------------

    ; Merges the shareable keys of an ini text into cfg (in memory).
    static ImportText(cfg, text) {
        secrets := Profiles.Secrets(cfg)
        n := 0, skipped := 0, sec := ""
        for line in StrSplit(StrReplace(String(text), "`r", ""), "`n") {
            t := Trim(line)
            if (t = "" || InStr(";#", SubStr(t, 1, 1)))
                continue
            if RegExMatch(t, "^\[(.*)\]$", &m) {
                sec := Trim(m[1])
                continue
            }
            p := InStr(t, "=")
            if (sec = "" || p < 2) {
                skipped++
                continue
            }
            key := Trim(SubStr(t, 1, p - 1)), val := Trim(SubStr(t, p + 1))
            path := Profiles.Shareable(sec, key, val, secrets)
            if (path = "") {
                skipped++
                continue
            }
            cfg.Set(path, val)
            n++
        }
        return {n: n, skipped: skipped}
    }

    static Import(cfg, path) {
        try {
            text := FileRead(path, "UTF-8")
        } catch {
            return {ok: 0, n: 0, skipped: 0, msg: "Not imported: the file could not be read"}
        }
        r := Profiles.ImportText(cfg, text)
        if (r.n = 0)
            return {ok: 0, n: 0, skipped: r.skipped, msg: "Nothing imported: no settings found in that file"}
        return {ok: 1, n: r.n, skipped: r.skipped, msg: "Imported " r.n " setting" (r.n = 1 ? "" : "s") (r.skipped ? " (" r.skipped " skipped)" : "")}
    }
}
