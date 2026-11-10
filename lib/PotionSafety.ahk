#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\Json.ahk
; ---------------------------------------------------------------------------
; PotionSafety: pure potion-use rules (spec 4.6a). No clicks, no screen I/O.
; Default is REFUSE: anything missing, malformed or unexpected gives qty 0.
;
;   s := PotionSafety(cfg.Data("potions"), "data\potion_usage.json" [, dateFn])
;     potionsCfg  Map {"potions": [{id, name, desc, locked, perBiome, perDay,
;                 perRun}]}
;                 id    IDENTITY of the entry (caps, locks, usage counts,
;                       biome lists). Optional: defaults to name. Needed when
;                       several potions share an in-game name: the three
;                       "Godly Potion"s are "Godly Potion (Sky)" / "(Sea)" /
;                       "(Hell)".
;                 name  exact in-game tile name (what is searched + OCR'd)
;                 desc  distinctive substring of the in-game description
;                       box. "" = not filled in yet -> Plan "no_desc"
;     dateFn      optional callable -> local date "yyyyMMdd" (tests inject)
;   Every `potion` argument below is the entry id.
;   s.Info(id) -> {id, name, desc} | ""   (unknown id)
;   s.BeginEvent(eventKey) -> bool   claim a biome event, persisted; false if
;                                    this run or the file already claimed it,
;                                    or the save failed (halts)
;   s.Plan(potion, wantQty, eventKey, ownedCount) -> {qty, reason}
;   s.Record(potion, eventKey)       reserve ONE use; re-checks rules + caps,
;                                    persists BEFORE returning; any throw halts
;   s.MarkEventDone(eventKey)        optional: close an event early
;   s.Status() -> "" | halt reason   usage_unreadable / usage_write_failed /
;                                    record_failed (report it loudly)
;   s.IsEventOpen(eventKey) -> bool  begun by this instance, not closed
;   s.UsedInEvent(potion, eventKey)  uses recorded for that event
;   s.NameMatches(ocrText, name)     EXACT on the canonical form (Canon);
;                                    false for a never-use tile and for a
;                                    name that never_use_prefix refuses
;   s.DescMatches(ocrText, desc)     canonical desc is a substring of the
;                                    canonical OCR text (desc "" -> false)
;   s.VerifyConsumed(before, after)  true only when before - after = 1
;
; CANON (PotionSafety.Canon): the game font draws "a" like "o", and OCR
; mixes I/l/1/|. Both sides are lower-cased and mapped to one character per
; class, then compared EXACTLY (same length, same classes):
;   whitespace runs -> one space, trimmed
;   a A o O 0 n N             -> o     ("Hoste" = "Haste", "Wnrp" = "Warp")
;   I i L l 1 | !             -> i     (roman numerals: "Il" = "II"; L too,
;                                       so matching stays case-insensitive;
;                                       no real name differs only by L/I)
;   s S 5 -> s    g G 6 -> g    b B 8 -> b
;   everything else lower-cased, kept as is (no fuzzy matching, no dropped
;   or extra characters: "Heavenly Potion" != "Heavenly Potion II").
;   The font's "D" drawn like "O" is NOT folded (it would break case-
;   insensitivity; no configured name has a capital D) -> such a misread
;   just fails to match (safe side).
; Every real potion name maps to a distinct canonical string (tested).
;
; CALLER CONTRACT (per potion use; one Use click each):
;   once per event:  BeginEvent(key)  -- false -> use no potions for it
;   per click:       Plan -> Record (persist) -> click -> VerifyConsumed
;   Plan again before every click. If Record throws, DO NOT click; stop all
;   potion use. If VerifyConsumed is false, abort the potion step.
;
; eventKey = biome name "|" log timestamp (exactly one "|", both sides set).
; Normalised everywhere: each side trimmed, biome whitespace collapsed and
; uppercased ("glitched | t1" == "GLITCHED|t1").
;
; Load: a usage file that exists but is unreadable/corrupt is NEVER reset
; (usage_unreadable, no writes ever). Otherwise a write probe (<path>.probe
; written and deleted) runs at load; if it fails the instance is halted.
;
; Plan reasons, checked in this order (first match wins; qty 0 unless "ok"):
;   usage_unreadable    usage file exists but is unreadable/corrupt
;   usage_write_failed  load probe or a save failed: instance halted
;   record_failed       a Record/MarkEventDone call threw: instance halted
;   unknown             potion id not in config (exact, case-sensitive)
;   never_use           name is on PotionSafety.NeverUse (retired / very rare
;                       or not a luck potion): refused even if configured and
;                       unlocked; such a tile name never matches either
;   locked              config locked flag is not exactly false (missing = locked)
;   never_use_prefix    name is a word prefix of a NeverUse name ("Heavenly
;                       Potion" / "Heavenly Potion I") and its desc is not
;                       proven absent from that potion's description
;                       (NeverUseDesc): its tile may be the never-use one
;   no_desc            config desc is empty: identity cannot be checked
;   desc_not_unique     this desc is (canonically) contained in another
;                       id's desc or contains it: both ids refused
;   bad_event           eventKey malformed
;   event_done          key claimed by an earlier run, or closed this run
;   event_not_begun     key never claimed (BeginEvent) by this instance
;   bad_qty             wantQty not a whole number >= 1
;   unreadable          ownedCount not a plain whole number (OCR "" etc.)
;   bad_clock           dateFn did not return "yyyyMMdd"
;   cap_biome           perBiome used up for this event (hard cap)
;   cap_day             perDay used up for today (local date)
;   cap_run             perRun used up since this instance was created
;   none_owned          ownedCount is 0
;   ok                  qty = min(want, biome left, day left, run left, owned)
; Caps that are not a non-negative Integer count as 0. Duplicate config
; entries (same id) merge to the most restrictive (locked if any, smallest
; caps; locked when their name or desc differ).
;
; Counts: per-biome and per-day persist in the usage file across restarts;
; per-run lives in memory (new instance = new run). A missing usage file is
; a fresh start.
; Usage file: {"version":1, "biome":{eventKey:{potion:n}},
;              "day":{"yyyyMMdd":{potion:n}}, "events":{eventKey:1|2}}
;   events: 1 = claimed, 2 = closed. Written via tmp + FileMove.
; ---------------------------------------------------------------------------

class PotionSafety {
    __New(potionsCfg, usagePath, dateFn := "") {
        this._path := usagePath
        this._dateFn := (dateFn = "") ? ((*) => FormatTime(, "yyyyMMdd")) : dateFn
        this._caps := PotionSafety._ParseCfg(potionsCfg)
        this._runCounts := Map()
        this._openEvents := Map()   ; events started by THIS instance
        this._halt := ""
        this._usageOk := false
        this._usage := ""
        this._LoadUsage()
        if this._usageOk
            this._Probe()
    }

    ; ---- config ------------------------------------------------------------

    static _ParseCfg(potionsCfg) {
        caps := Map()
        if !(potionsCfg is Map && potionsCfg.Has("potions") && potionsCfg["potions"] is Array)
            return caps
        for e in potionsCfg["potions"] {
            if !(e is Map && e.Has("name") && e["name"] is String && Trim(e["name"]) != "")
                continue
            name := Trim(e["name"])
            id := name
            if e.Has("id") {
                if !(e["id"] is String && Trim(e["id"]) != "")
                    continue
                id := Trim(e["id"])
            }
            desc := (e.Has("desc") && e["desc"] is String) ? Trim(e["desc"]) : ""
            c := {
                id: id, name: name, desc: desc,
                locked: !(e.Has("locked") && e["locked"] is Integer && e["locked"] = 0),
                perBiome: PotionSafety._CapVal(e, "perBiome"),
                perDay: PotionSafety._CapVal(e, "perDay"),
                perRun: PotionSafety._CapVal(e, "perRun")
            }
            if caps.Has(id) {
                old := caps[id]
                c.locked := c.locked || old.locked || old.name !== c.name || old.desc !== c.desc
                c.perBiome := Min(c.perBiome, old.perBiome)
                c.perDay := Min(c.perDay, old.perDay)
                c.perRun := Min(c.perRun, old.perRun)
            }
            caps[id] := c
        }
        ; A desc that is (canonically) part of another potion's desc cannot
        ; tell the two apart in the description box: refuse both.
        canon := Map()
        for id, c in caps {
            c.descDup := false
            canon[id] := PotionSafety.Canon(c.desc)
        }
        for id, c in caps {
            if (canon[id] = "")
                continue
            for id2, c2 in caps {
                if (id2 == id || canon[id2] = "")
                    continue
                if InStr(canon[id2], canon[id], true) {
                    c.descDup := true
                    c2.descDup := true
                }
            }
        }
        return caps
    }

    ; -> {id, name, desc} for a configured id, else "".
    Info(id) {
        if !(id is String && this._caps.Has(id))
            return ""
        c := this._caps[id]
        return {id: c.id, name: c.name, desc: c.desc}
    }

    static _CapVal(e, key) {
        if !e.Has(key)
            return 0
        v := e[key]
        return (v is Integer && v >= 0) ? v : 0
    }

    ; ---- usage file --------------------------------------------------------

    _LoadUsage() {
        attr := FileExist(this._path)
        if (attr = "") {
            this._usage := Map("version", 1, "biome", Map(), "day", Map(), "events", Map())
            this._usageOk := true
            return
        }
        if InStr(attr, "D")
            return
        try {
            v := Json.Parse(FileRead(this._path, "UTF-8"))
            if PotionSafety._ValidUsage(v) {
                this._usage := v
                this._usageOk := true
            }
        }
    }

    static _ValidUsage(v) {
        if !(v is Map && v.Has("version") && v["version"] is Integer && v["version"] = 1)
            return false
        for sec in ["biome", "day"] {
            if !(v.Has(sec) && v[sec] is Map)
                return false
            for k, inner in v[sec] {
                if !(inner is Map)
                    return false
                for p, n in inner
                    if !(n is Integer && n >= 0)
                        return false
            }
        }
        if !(v.Has("events") && v["events"] is Map)
            return false
        for k, n in v["events"]
            if !(n is Integer && (n = 1 || n = 2))
                return false
        return true
    }

    _Save() {
        PotionSafety._AtomicWrite(this._path, Json.Stringify(this._usage) "`n")
    }

    static _AtomicWrite(path, text) {
        SplitPath(path, , &dir)
        if (dir != "" && !DirExist(dir))
            DirCreate(dir)
        tmp := path ".tmp"
        f := ""
        try {
            f := FileOpen(tmp, "w", "UTF-8-RAW")
            f.Write(text)
            f.Close()
            f := ""
            ; FileMove onto an existing directory silently moves the file INTO
            ; it and "succeeds": refuse instead.
            if InStr(FileExist(path), "D")
                throw OSError("PotionSafety: usage path is a directory")
            FileMove(tmp, path, 1)
            ; Read back: the save only counts if the file now holds this text.
            if (InStr(FileExist(path), "D") || FileRead(path, "UTF-8-RAW") !== text)
                throw OSError("PotionSafety: usage file read-back mismatch")
        } catch as err {
            f := ""
            try FileDelete(tmp)
            throw err
        }
    }

    ; Load-time write probe: create and delete <path>.probe next to the usage
    ; file. Failure halts the instance before any click can happen.
    _Probe() {
        probe := this._path ".probe"
        f := ""
        try {
            SplitPath(this._path, , &dir)
            if (dir != "" && !DirExist(dir))
                DirCreate(dir)
            f := FileOpen(probe, "w", "UTF-8-RAW")
            f.Write("probe")
            f.Close()
            f := ""
            FileDelete(probe)
        } catch {
            f := ""
            try FileDelete(probe)
            this._halt := "usage_write_failed"
        }
    }

    _RunCount(potion) => this._runCounts.Has(potion) ? this._runCounts[potion] : 0

    _Count(sec, key, potion) {
        m := this._usage[sec]
        return (m.Has(key) && m[key].Has(potion)) ? m[key][potion] : 0
    }

    _Bump(sec, key, potion) {
        m := this._usage[sec]
        if !m.Has(key)
            m[key] := Map()
        m[key][potion] := (m[key].Has(potion) ? m[key][potion] : 0) + 1
    }

    _Today() {
        try d := this._dateFn.Call()
        catch
            return ""
        if !((d is String || d is Integer) && RegExMatch(String(d), "^\d{8}$"))
            return ""
        return String(d)
    }

    ; ---- parsing helpers ---------------------------------------------------

    ; Plain whole number (Integer >= 0, or digit-only String after trim) -> Integer,
    ; anything else -> -1. Rejects floats, signs, hex, separators, exponents.
    static _ParseCount(v) {
        if (v is Integer)
            return v >= 0 ? v : -1
        if !(v is String)
            return -1
        t := Trim(v, " `t`r`n")
        return RegExMatch(t, "^\d{1,9}$") ? Integer(t) : -1
    }

    ; "biome|ts" -> "BIOME|ts" (sides trimmed, biome ws collapsed + uppercased),
    ; or "" when malformed (not a String, not exactly one "|", empty side).
    static _NormEventKey(k) {
        if !(k is String) || !RegExMatch(k, "^([^|]+)\|([^|]+)$", &m)
            return ""
        b := StrUpper(Trim(RegExReplace(m[1], "[\s\x{00A0}]+", " "), " "))
        t := Trim(m[2], " `t`r`n")
        return (b = "" || t = "") ? "" : b "|" t
    }

    ; OCR-confusable classes (see header). Non-String -> "".
    static Canon(s) {
        if !(s is String)
            return ""
        s := Trim(RegExReplace(s, "[\s\x{00A0}]+", " "), " ")
        out := ""
        Loop Parse s
            out .= PotionSafety._CanonChar(A_LoopField)
        return out
    }

    static _CanonChar(c) {
        c := StrLower(c)
        switch c, true {
            case "i", "l", "1", "|", "!": return "i"
            case "a", "o", "0", "n": return "o"
            case "s", "5": return "s"
            case "g", "6": return "g"
            case "b", "8": return "b"
        }
        return c
    }

    static _R(qty, reason) => {qty: qty, reason: reason}

    ; Potions the macro must never use, whatever the config says (user,
    ; 2026-10-26): Heavenly Potion I / II no longer drop and are very rare;
    ; Sizemax / Sizemin are not luck potions.
    static NeverUse := ["Heavenly Potion I", "Heavenly Potion II", "Sizemax Potion", "Sizemin Potion"]

    ; In-game description box text of NeverUse potions (as OCR reads it),
    ; keyed by the NeverUse name. EMPTY until recorded live: while a NeverUse
    ; name has no entry here, a configured name that is a word prefix of it
    ; is refused (never_use_prefix, see NeverUsePrefixOk).
    static NeverUseDesc := Map()

    ; 2026-10-27 review: the game font often loses a lone trailing "I", so
    ; the "Heavenly Potion I" tile OCRs "Heavenly`nPotion" and matched a
    ; configured "Heavenly Potion"; the shared "[Heavenly]" description then
    ; "proved" the selection and Use consumed a Heavenly Potion I. A name that
    ; is a word prefix of a NeverUse name ("Heavenly Potion" of "Heavenly
    ; Potion I" / "II") is therefore only allowed when its desc is proven NOT
    ; to occur in the recorded description of EVERY such NeverUse potion:
    ; the selected item must contain desc before Use, so it cannot be one of
    ; them. No recording (or a desc they share) -> false. Fails closed.
    static NeverUsePrefixOk(name, desc) {
        cn := PotionSafety.Canon(name)
        if (cn = "")
            return true
        cd := PotionSafety.Canon(desc)
        for n in PotionSafety.NeverUse {
            if (SubStr(PotionSafety.Canon(n), 1, StrLen(cn) + 1) !== cn " ")
                continue
            if (cd = "" || !PotionSafety.NeverUseDesc.Has(n))
                return false
            t := PotionSafety.Canon(String(PotionSafety.NeverUseDesc[n]))
            if (t = "" || InStr(t, cd, true))
                return false
        }
        return true
    }

    ; NeverUsePrefixOk for a tile name: every configured entry with that name
    ; must pass (an unconfigured prefix name never does).
    _PrefixOkByName(name) {
        found := false
        cn := PotionSafety.Canon(name)
        for id, c in this._caps {
            if (PotionSafety.Canon(c.name) !== cn)
                continue
            found := true
            if !PotionSafety.NeverUsePrefixOk(c.name, c.desc)
                return false
        }
        return found || PotionSafety.NeverUsePrefixOk(name, "")
    }

    ; true when name is (canonically) one of NeverUse.
    static IsNeverUse(name) {
        if !(name is String)
            return false
        c := PotionSafety.Canon(name)
        if (c = "")
            return false
        for n in PotionSafety.NeverUse
            if (c == PotionSafety.Canon(n))
                return true
        return false
    }

    ; ---- public ------------------------------------------------------------

    Plan(potion, wantQty, eventKey, ownedCount) {
        if !this._usageOk
            return PotionSafety._R(0, "usage_unreadable")
        if (this._halt != "")
            return PotionSafety._R(0, this._halt)
        if !(potion is String && this._caps.Has(potion))
            return PotionSafety._R(0, "unknown")
        c := this._caps[potion]
        if (PotionSafety.IsNeverUse(potion) || PotionSafety.IsNeverUse(c.name))
            return PotionSafety._R(0, "never_use")
        if c.locked
            return PotionSafety._R(0, "locked")
        if !PotionSafety.NeverUsePrefixOk(c.name, c.desc)
            return PotionSafety._R(0, "never_use_prefix")
        if (c.desc = "")
            return PotionSafety._R(0, "no_desc")
        if c.descDup
            return PotionSafety._R(0, "desc_not_unique")
        k := PotionSafety._NormEventKey(eventKey)
        if (k = "")
            return PotionSafety._R(0, "bad_event")
        if !this._openEvents.Has(k)
            return PotionSafety._R(0, this._usage["events"].Has(k) ? "event_done" : "event_not_begun")
        want := PotionSafety._ParseCount(wantQty)
        if (want < 1)
            return PotionSafety._R(0, "bad_qty")
        owned := PotionSafety._ParseCount(ownedCount)
        if (owned < 0)
            return PotionSafety._R(0, "unreadable")
        day := this._Today()
        if (day = "")
            return PotionSafety._R(0, "bad_clock")
        leftBiome := c.perBiome - this._Count("biome", k, potion)
        if (leftBiome <= 0)
            return PotionSafety._R(0, "cap_biome")
        leftDay := c.perDay - this._Count("day", day, potion)
        if (leftDay <= 0)
            return PotionSafety._R(0, "cap_day")
        leftRun := c.perRun - this._RunCount(potion)
        if (leftRun <= 0)
            return PotionSafety._R(0, "cap_run")
        if (owned = 0)
            return PotionSafety._R(0, "none_owned")
        return PotionSafety._R(Min(want, leftBiome, leftDay, leftRun, owned), "ok")
    }

    ; Reserves ONE use of potion in eventKey and persists it before returning.
    ; Call BEFORE the click. Re-checks every rule except the owned count
    ; (known, unlocked, event begun by this run and still open, caps left).
    ; Any throw halts this instance: the caller must not click.
    Record(potion, eventKey) {
        try {
            if !this._usageOk
                throw Error("PotionSafety: usage file unreadable; refusing to record")
            if (this._halt != "")
                throw Error("PotionSafety: halted (" this._halt ")")
            if !(potion is String && this._caps.Has(potion))
                throw ValueError("PotionSafety: unknown potion")
            c := this._caps[potion]
            if (PotionSafety.IsNeverUse(potion) || PotionSafety.IsNeverUse(c.name))
                throw Error("PotionSafety: potion is on the never-use list")
            if c.locked
                throw Error("PotionSafety: potion locked")
            if !PotionSafety.NeverUsePrefixOk(c.name, c.desc)
                throw Error("PotionSafety: name could be a never-use potion's")
            if (c.desc = "")
                throw Error("PotionSafety: potion has no desc")
            if c.descDup
                throw Error("PotionSafety: potion desc not unique")
            k := PotionSafety._NormEventKey(eventKey)
            if (k = "")
                throw ValueError("PotionSafety: bad eventKey")
            if !this._openEvents.Has(k)
                throw Error("PotionSafety: event not begun by this run")
            day := this._Today()
            if (day = "")
                throw Error("PotionSafety: bad clock")
            if (this._Count("biome", k, potion) >= c.perBiome)
                throw Error("PotionSafety: cap_biome reached")
            if (this._Count("day", day, potion) >= c.perDay)
                throw Error("PotionSafety: cap_day reached")
            if (this._RunCount(potion) >= c.perRun)
                throw Error("PotionSafety: cap_run reached")
        } catch as err {
            if (this._halt = "")
                this._halt := "record_failed"
            throw err
        }
        ; Count in memory first: a failed write keeps the over-count and halts.
        this._runCounts[potion] := this._RunCount(potion) + 1
        this._Bump("biome", k, potion)
        this._Bump("day", day, potion)
        try this._Save()
        catch as err {
            this._halt := "usage_write_failed"
            throw err
        }
    }

    ; Claims a biome event for this run and persists the claim before
    ; returning. False if already claimed (this run or any earlier run), the
    ; key is malformed, the instance is halted/unreadable, or the save fails
    ; (which also halts).
    BeginEvent(eventKey) {
        if (!this._usageOk || this._halt != "")
            return false
        k := PotionSafety._NormEventKey(eventKey)
        if (k = "")
            return false
        ev := this._usage["events"]
        if (this._openEvents.Has(k) || ev.Has(k))
            return false
        ev[k] := 1
        this._openEvents[k] := true
        try this._Save()
        catch {
            this._halt := "usage_write_failed"
            return false
        }
        return true
    }

    ; Optional: closes the event early; later Plan for it returns event_done.
    ; Safety never depends on this (BeginEvent already blocks re-triggers).
    ; Any throw halts this instance.
    MarkEventDone(eventKey) {
        try {
            if !this._usageOk
                throw Error("PotionSafety: usage file unreadable; refusing to write")
            k := PotionSafety._NormEventKey(eventKey)
            if (k = "")
                throw ValueError("PotionSafety: bad eventKey")
        } catch as err {
            if (this._halt = "")
                this._halt := "record_failed"
            throw err
        }
        this._usage["events"][k] := 2
        if this._openEvents.Has(k)
            this._openEvents.Delete(k)
        try this._Save()
        catch as err {
            this._halt := "usage_write_failed"
            throw err
        }
    }

    NameMatches(ocrText, name) {
        a := PotionSafety.Canon(ocrText)
        if PotionSafety.IsNeverUse(ocrText)         ; a never-use tile matches nothing
            return false
        ; a prefix of a never-use name may BE that tile minus a lost "I"
        ; (2026-10-27 review): no match unless its desc rules them out
        if !this._PrefixOkByName(name)
            return false
        return (a != "" && a == PotionSafety.Canon(name))
    }

    ; -> "" while potion use is possible, else the reason every Plan gives
    ; first: usage_unreadable | usage_write_failed | record_failed. Callers
    ; report it loudly (2026-10-27 review: it used to show up only as a
    ; quiet "event_claimed" from BeginEvent).
    Status() => !this._usageOk ? "usage_unreadable" : this._halt

    ; true while eventKey was begun by THIS instance and not closed (an
    ; event the caller re-queued after a pause resumes without BeginEvent).
    IsEventOpen(eventKey) {
        k := PotionSafety._NormEventKey(eventKey)
        return (k != "" && this._openEvents.Has(k))
    }

    ; Uses of potion recorded for eventKey (persisted per-biome count).
    UsedInEvent(potion, eventKey) {
        k := PotionSafety._NormEventKey(eventKey)
        if (!this._usageOk || k = "" || !(potion is String))
            return 0
        return this._Count("biome", k, potion)
    }

    DescMatches(ocrText, desc) {
        d := PotionSafety.Canon(desc)
        return (d != "" && InStr(PotionSafety.Canon(ocrText), d, true) > 0)
    }

    VerifyConsumed(before, after) {
        b := PotionSafety._ParseCount(before)
        a := PotionSafety._ParseCount(after)
        return (b >= 0 && a >= 0 && b - a = 1)
    }

    ; ---- rebuild support (Task 14b; additive, touches no other method) -----
    ; s.TransferRunCountsFrom(old) -> bool
    ;   The app rebuilds PotionSafety when potions.json / biomes.json change
    ;   (new caps/locks). A new instance would start a new "run", so this
    ;   carries the in-memory state of `old` (an earlier instance of the SAME
    ;   macro run) into this one: per-run counts (the larger of the two per
    ;   potion), events begun by old and not closed, and old's halt reason
    ;   (fail closed: a rebuild never clears a halt). Per-biome / per-day
    ;   counts live in the usage file and need no transfer. Call it right
    ;   after construction. Caps and locks stay the NEW config's.
    TransferRunCountsFrom(old) {
        if (!(old is PotionSafety) || old == this)
            return false
        for potion, n in old._runCounts {
            if (n > this._RunCount(potion))
                this._runCounts[potion] := n
        }
        for k, v in old._openEvents
            this._openEvents[k] := v
        if (this._halt = "" && old._halt != "")
            this._halt := old._halt
        return true
    }
}
