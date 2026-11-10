#Requires AutoHotkey v2.0
; ---------------------------------------------------------------------------
; Auras: aura rarity table (data\auras.json) and the "clip this aura?" rule.
;
; data\auras.json: {"_source": {...}, "auras": [{name, rarity, category,
;   aliases?, note?, conflict?}, ...]}. rarity = base 1-in-N denominator
;   (Integer; 0 = odds not published). category = the game's rarity class
;   (Basic ... Glorious, Transcendent, Challenged, Challenged+, Event, ...).
;   Loaded ONLY from the file: when it is missing or bad, Config.Defaults
;   gives an empty list, so every aura is "unknown" (never clipped unless
;   listed in [Medal] auras).
;
;   Auras.Key(name)        lookup key: surrounding quotes/whitespace dropped,
;                          lower-case, all whitespace and ASCII punctuation
;                          removed ("Quartz : Rose" == "quartz: ROSE").
;   Auras.List(cfg)        Array of entries (Maps) from cfg.Data("auras"),
;                          [] when missing.
;   Auras.Find(cfg, name)  entry Map (by name or any alias) or "".
;   Auras.ParseRarity(s)   "100m" / "1b" / "1.5b" / "250k" / "100,000,000" /
;                          "1 in 100m" / "1/100m" / "2 billion" -> Integer
;                          (>= 0), "" when unparsable.
;   Auras.Format(n)        100000000 -> "100,000,000".
;   Auras.MinRarity(cfg)   [Medal] auraMinRarity parsed (default 100000000;
;                          unparsable -> default; 0 = rarity rule off).
;   Auras.Decide(cfg, name) -> Map{clip, why, known, entry, name, rarity,
;                          category}. Clip when (first match wins):
;                            1. the name is in [Medal] auras (comma list),
;                            2. its category is in [Medal] auraAlwaysCategories
;                               (default "Challenged,Challenged+"),
;                            3. rarity > 0 and rarity >= MinRarity.
;                          Unknown (not in auras.json) and not listed -> no clip.
;   Auras.Describe(cfg, name) multi-line text for the `clips` webhook:
;                          aura, 1-in-N rarity + class, and why it clipped.
;   Auras.EquippedInText(text) Array of aura names in raw Roblox log text
;                          (the BloxstrapRPC state `Equipped \"Name\"`, quotes
;                          escaped inside the JSON). Pure.
;   Auras.EquippedInLogs(dir) Map Key -> name over every dir\*.log (read
;                          shared; unreadable files skipped). Seeds the
;                          "had" set in BiomeEvents.
; ---------------------------------------------------------------------------

class Auras {
    ; Until this A_TickCount an "Equipped" aura is the macro's own swap
    ; (obby / minions), not a roll: no clip (2026-11-01: every hunt clipped
    ; Equinox going on and off). Set by ObbyTask around Equip / Unequip,
    ; and for JoinQuietMs after a join (App._OnJoin, RecoveryTask's rejoin):
    ; a fresh client's first "Equipped" line is the aura you already wear
    ; (2026-10-31: every rejoin clipped your own Equinox).
    static QuietUntil := 0
    static QuietMs := 20000
    static JoinQuietMs := 60000

    ; Auras stay quiet for at least `ms` from now (never shortens a window).
    static Quiet(ms) => Auras.QuietUntil := Max(Auras.QuietUntil, A_TickCount + ms)
    static DefaultMinRarity := 100000000
    static DefaultAlways := "Challenged,Challenged+"
    static _idxList := ""          ; list object the index was built from
    static _idx := ""

    ; Aura names in `Equipped \"Name\"` states of raw log text, in order.
    static EquippedInText(text) {
        names := []
        pos := 1
        while (pos := RegExMatch(text, 'Equipped \\"(.*?)\\"', &m, pos)) {
            if (Trim(m[1]) != "")
                names.Push(m[1])
            pos += Max(1, m.Len(0))
        }
        return names
    }

    ; Map Key -> name of every aura equipped in dir\*.log (Roblox's logs).
    static EquippedInLogs(dir) {
        found := Map()
        if (dir = "" || !DirExist(dir))
            return found
        loop files dir "\*.log" {
            text := ""
            try {
                f := FileOpen(A_LoopFileFullPath, "r", "UTF-8")
                text := f.Read()
                f.Close()
            } catch {
                continue
            }
            for n in Auras.EquippedInText(text) {
                k := Auras.Key(n)
                if (k != "")
                    found[k] := n
            }
        }
        return found
    }

    static Key(name) {
        s := Trim(String(name), " `t`r`n`"'")
        return StrLower(RegExReplace(s, "[\s!-/:-@\[-``{-~]+", ""))
    }

    static List(cfg) {
        d := ""
        try d := cfg.Data("auras")
        if (d is Map && d.Has("auras") && d["auras"] is Array)
            return d["auras"]
        return []
    }

    static Find(cfg, name) {
        k := Auras.Key(name)
        if (k = "")
            return ""
        idx := Auras._Index(Auras.List(cfg))
        return idx.Has(k) ? idx[k] : ""
    }

    static _Index(list) {
        if (Auras._idxList == list && Auras._idx is Map)
            return Auras._idx
        idx := Map()
        for e in list {
            if !(e is Map && e.Has("name"))
                continue
            names := [e["name"]]
            if (e.Has("aliases") && e["aliases"] is Array)
                for a in e["aliases"]
                    names.Push(a)
            for n in names {
                k := Auras.Key(n)
                if (k != "" && !idx.Has(k))
                    idx[k] := e
            }
        }
        Auras._idxList := list
        Auras._idx := idx
        return idx
    }

    static ParseRarity(s) {
        if (s is Integer)
            return s >= 0 ? s : ""
        t := StrLower(RegExReplace(String(s), "[\s,_]+", ""))
        t := RegExReplace(t, "^1(?:in|/)(?=\d)", "")
        if !RegExMatch(t, "^(\d{1,15})(?:\.(\d{1,9}))?(k|m|b|t|thousand|mil|million|billion|trillion)?$", &m)
            return ""
        static mult := Map("k", 1000, "thousand", 1000, "m", 1000000, "mil", 1000000, "million", 1000000
            , "b", 1000000000, "billion", 1000000000, "t", 1000000000000, "trillion", 1000000000000)
        if (m[3] = "")
            return (m[2] = "") ? Integer(m[1]) : ""
        f := mult[m[3]]
        if (Float(m[1] (m[2] != "" ? "." m[2] : "")) * f >= 1.0e15)
            return ""
        v := Integer(m[1]) * f
        if (m[2] != "")
            v += Round(Float("0." m[2]) * f)
        return Integer(v)
    }

    static Format(n) {
        s := String(Integer(n))
        neg := (SubStr(s, 1, 1) = "-")
        if neg
            s := SubStr(s, 2)
        out := ""
        while (StrLen(s) > 3) {
            out := "," SubStr(s, -3) out
            s := SubStr(s, 1, StrLen(s) - 3)
        }
        return (neg ? "-" : "") s out
    }

    static MinRarity(cfg) {
        raw := ""
        try raw := cfg.Get("Medal.auraMinRarity", String(Auras.DefaultMinRarity))
        v := Auras.ParseRarity(raw)
        return (v = "") ? Auras.DefaultMinRarity : v
    }

    static _CsvHas(csv, item, keyFn) {
        k := keyFn.Call(item)
        if (k = "")
            return false
        for part in StrSplit(String(csv), ",")
            if (keyFn.Call(part) == k)
                return true
        return false
    }

    static Decide(cfg, name) {
        e := Auras.Find(cfg, name)
        disp := Trim(String(name), " `t`"")
        r := Map("clip", false, "why", "", "known", IsObject(e), "entry", e
            , "name", IsObject(e) ? e["name"] : disp, "rarity", 0, "category", "")
        if IsObject(e) {
            r["rarity"] := (e.Has("rarity") && e["rarity"] is Integer) ? e["rarity"] : 0
            r["category"] := e.Has("category") ? String(e["category"]) : ""
        }
        listed := ""
        try listed := cfg.Get("Medal.auras", "")
        names := [disp]
        if IsObject(e) {
            names.Push(e["name"])
            if (e.Has("aliases") && e["aliases"] is Array)
                for a in e["aliases"]
                    names.Push(a)
        }
        for n in names {
            if Auras._CsvHas(listed, n, (s) => Auras.Key(s)) {
                r["clip"] := true, r["why"] := "listed in [Medal] auras"
                return r
            }
        }
        if !IsObject(e)
            return r
        always := Auras.DefaultAlways
        try always := cfg.Get("Medal.auraAlwaysCategories", Auras.DefaultAlways)
        catKey := (s) => StrLower(Trim(RegExReplace(String(s), "\s+", " ")))
        if (r["category"] != "" && Auras._CsvHas(always, r["category"], catKey)) {
            r["clip"] := true, r["why"] := "class " r["category"] " always clips ([Medal] auraAlwaysCategories)"
            return r
        }
        min := Auras.MinRarity(cfg)
        if (min > 0 && r["rarity"] > 0 && r["rarity"] >= min) {
            r["clip"] := true
            r["why"] := "1 in " Auras.Format(r["rarity"]) " is at least as rare as the 1 in " Auras.Format(min) " threshold ([Medal] auraMinRarity)"
        }
        return r
    }

    static Describe(cfg, name) {
        d := Auras.Decide(cfg, name)
        t := "Aura: " d["name"]
        if d["known"]
            t .= "`nRarity: " (d["rarity"] > 0 ? "1 in " Auras.Format(d["rarity"]) : "odds not published")
                . (d["category"] != "" ? " (" d["category"] ")" : "")
        else
            t .= "`nRarity: unknown (not in data/auras.json)"
        if (d["why"] != "")
            t .= "`nWhy: " d["why"]
        return t
    }
}
