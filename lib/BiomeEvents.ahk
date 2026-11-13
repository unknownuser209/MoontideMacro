#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\Biomes.ahk
#Include %A_LineFile%\..\Clip.ahk
#Include %A_LineFile%\..\Screenshot.ahk
#Include %A_LineFile%\..\Roblox.ahk
; ---------------------------------------------------------------------------
; BiomeEvents: reacts to LogWatch events (spec 4.6, 4.6b, 4.7).
; The main loop calls be.Handle(ev) for EVERY event from LogWatch.Poll()
; (also from the PotionsTask poll callback while potions are running).
;
;   be := BiomeEvents(deps)       deps Map:
;     cfg      Config (required)
;     state    object; .biome, .rareActive and .rareTs (ts of the live rare
;              event, "" when not rare) are written here (required)
;     wh       object with Send(event, title, desc, color, opts) (Webhook)
;     potions  object with Queue(biome, ts) (PotionsTask)
;     log      callable(text)
;     shotFn   () -> png path or ""   default Screenshot.Capture(Roblox.Hwnd())
;     soundFn  (arg) -> plays it       default SoundPlay(arg)
;     clip     object with Trigger(reason)   default the Clip class
;     lastFile path of a text file that keeps the last biome seen across
;              Stop/Start and macro restarts ("" = none, the default; the App
;              passes <dir>\data\last_biome.txt)
;     hadFile  path of a text file of auras equipped before ("had"), one
;              Auras.Key per line ("" = none, the default; the App and
;              tools\biome_watch.ahk pass <dir>\data\auras_had.txt). Local
;              to each player: never stage or commit it (nor data\*.json).
;     hadLogDir Roblox log folder that seeds hadFile when it does not exist
;              yet (default %LOCALAPPDATA%\Roblox\logs; "" = no seeding)
;     picDir   folder of square biome pictures, NAME.png with spaces as "_"
;              (default assets\biomes)
;   be.Handle(ev)   ev = Map with type, name, ts, live (LogWatchEvent)
;
; Rules:
;   - live is true ONLY for Integer 1 (LogWatch true). Not live (startup
;     backfill): state.biome is set (and rareActive cleared if the biome is
;     not rare); no sound, clip, potions or rare alert. When it differs
;     from the last biome seen (state.biome, else lastFile: it changed while
;     the macro was stopped or closed) the `biome` webhook gets "Biome
;     Ended - OLD" and "Biome Started - NEW" (a rare NEW: the rare message
;     with a screenshot but no ping, no potions). (While PAUSED the log is
;     still read, so changes then come in live.)
;   - Biome Started cards and the rare alert carry the biome's square
;     picture (picDir\NAME.png) as the embed thumbnail. The pictures are the
;     Sol's RNG wiki's (most re-shot after the 2026-10-03 VFX update); NORMAL
;     and SAND STORM are cut from the creator's own clips of 2026-10-25/26.
;     Drop your own NAME.png there to replace one.
;   - Live biome: log, and `biome` webhook cards (Coteab style: no title,
;     "<t:..:F> (<t:..:R>)" then a quoted "## Biome Started - NAME" [+ Join
;     Server link], side colour per biome, BiomeEvents.Color): "Biome Ended -
;     PREV" for the biome it replaces and "Biome Started - NAME" for a
;     NON-RARE one. A rare biome gets ONLY the `rare` message below (no
;     Started card next to it). Test events send no cards. Unknown names (not in biomes.json) are reported as
;     normal, non-rare biomes. state.stats: biomes, rareBiomes.
;   - Non-rare biome (live or not) clears state.rareActive.
;   - Live rare biome: rareActive := true, `rare` webhook with mention and a
;     Roblox screenshot (+ "[Join server](link)" if [General] joinButton=1 and
;     privateServer is an https://www.roblox.com/ link; the link is never
;     logged). If [General] everyonePing=1 (default) and the biome is in
;     [General] everyoneBiomes (default DREAMSPACE,GLITCHED,CYBERSPACE) the
;     message also pings @everyone (opts.everyone; Webhook allows it for this
;     message only). Test events (ts "TEST-..." or ev.test) never mention or
;     ping anyone. SoundPlay([General] alertSound, default *48) if [General]
;     sound=1, Clip.Trigger("rare") if [Medal] onRareBiome=1, then
;     potions.Queue(name, ts).
;   - Live aura with [Medal] onRareAura=1: Auras.Decide (lib\Auras.ahk,
;     data\auras.json) -> Clip.Trigger("aura:" name) when listed in [Medal]
;     auras, its class is in [Medal] auraAlwaysCategories (default
;     Challenged,Challenged+) or its 1-in-N rarity >= [Medal] auraMinRarity
;     (default 100000000). Unknown aura (not in auras.json, not listed): no
;     clip, logged once per name. A TEST aura event (ev["test"] or ts
;     "TEST-...") only clips while General.dryRun=1.
;   - Had auras (hadFile set): the Roblox log only says `Equipped "X"`, the
;     same for a roll and for putting on an aura you own from storage
;     (2026-11-02: hand equips of Luminosity, EQUINOX, Eden, Borealis each
;     clipped). An aura already in the set: no clip ("equipped before"). A
;     new one is decided as above and joins the set either way; so does
;     the startup (not live) aura and the macro's own swaps. The set is
;     seeded once, when hadFile does not exist, with every aura equipped in
;     hadLogDir\*.log. Test events never touch it.
;   - Other event types are ignored here.
; ---------------------------------------------------------------------------

class BiomeEvents {
    static EveryoneDefault := "DREAMSPACE,GLITCHED,CYBERSPACE"
    static DefaultColor := 0x9B59B6
    static Colors := Map("WINDY", 0x9AE5FF, "RAINY", 0x2E6BD8, "SNOWY", 0xE8F4FF, "SAND STORM", 0xE3A857
        , "HELL", 0xC0392B, "STARFALL", 0x5B5BD6, "CORRUPTION", 0x9B59B6, "NULL", 0x6E6E6E
        , "HEAVEN", 0xF5E6A8, "GLITCHED", 0x00FF66, "DREAMSPACE", 0xFF77E1, "CYBERSPACE", 0x1E90FF
        , "SINGULARITY", 0x2B0A3D, "RADIANT FOREST", 0x7CFC00)

    ; Side colour for a biome card.
    static Color(name) {
        n := StrUpper(Trim(String(name)))
        return BiomeEvents.Colors.Has(n) ? BiomeEvents.Colors[n] : BiomeEvents.DefaultColor
    }

    __New(deps) {
        d := (deps is Map) ? deps : Map()
        if !(d.Has("cfg") && d.Has("state"))
            throw ValueError("BiomeEvents: cfg and state are required")
        this._cfg := d["cfg"]
        this._state := d["state"]
        this._wh := d.Has("wh") ? d["wh"] : ""
        this._potions := d.Has("potions") ? d["potions"] : ""
        this._logFn := d.Has("log") ? d["log"] : ""
        this._shotFn := d.Has("shotFn") ? d["shotFn"] : (() => Screenshot.Capture(Roblox.Hwnd()))
        this._soundFn := d.Has("soundFn") ? d["soundFn"] : ((s) => SoundPlay(s))
        this._clip := d.Has("clip") ? d["clip"] : Clip
        this._lastFile := d.Has("lastFile") ? String(d["lastFile"]) : ""
        this._picDir := d.Has("picDir") ? String(d["picDir"]) : BiomeEvents.PicDir
        this._hadFile := d.Has("hadFile") ? String(d["hadFile"]) : ""
        this._hadLogDir := d.Has("hadLogDir") ? String(d["hadLogDir"]) : EnvGet("LOCALAPPDATA") "\Roblox\logs"
        this._had := ""
        if (this._hadFile != "")
            this._HadLoad()
    }

    ; Loads the had set from hadFile, or seeds it from the Roblox logs (and
    ; writes hadFile) when the file does not exist yet.
    _HadLoad() {
        this._had := Map()
        if FileExist(this._hadFile) {
            text := ""
            try text := FileRead(this._hadFile, "UTF-8")
            loop parse text, "`n", " `t`r"
                if (A_LoopField != "")
                    this._had[A_LoopField] := true
            return
        }
        keys := ""
        for k in Auras.EquippedInLogs(this._hadLogDir) {
            this._had[k] := true
            keys .= k "`n"
        }
        try {
            SplitPath(this._hadFile, , &dir)
            if (dir != "" && !DirExist(dir))
                DirCreate(dir)
            f := FileOpen(this._hadFile, "w", "UTF-8-RAW")
            f.Write(keys)
            f.Close()
        }
        this._Log("Auras: " this._had.Count " aura(s) equipped before, from the Roblox logs (no clip when put on again)")
    }

    _HadHas(name) => IsObject(this._had) && this._had.Has(Auras.Key(name))

    ; Adds an aura to the had set (and appends it to hadFile).
    _HadAdd(name) {
        k := Auras.Key(name)
        if (k = "" || !IsObject(this._had) || this._had.Has(k))
            return
        this._had[k] := true
        try FileAppend(k "`n", this._hadFile, "UTF-8-RAW")
    }

    static PicDir := RegExReplace(A_LineFile, "\\[^\\]*\\[^\\]*$") "\assets\biomes"

    ; Square picture for a biome card, or "" when there is none.
    static Picture(name, dir := "") {
        dir := (dir = "") ? BiomeEvents.PicDir : dir
        n := StrUpper(Trim(String(name)))
        if (n = "" || RegExMatch(n, "[\\/:*?`"<>|.]"))
            return ""
        p := dir "\" StrReplace(n, " ", "_") ".png"
        return FileExist(p) ? p : ""
    }

    _LoadLast() {
        if (this._lastFile = "")
            return ""
        try return Trim(FileRead(this._lastFile, "UTF-8"), " `t`r`n")
        return ""
    }

    _SaveLast(name) {
        if (this._lastFile = "" || this._LoadLast() == name)
            return
        try {
            f := FileOpen(this._lastFile, "w", "UTF-8-RAW")
            f.Write(name)
            f.Close()
        }
    }

    Handle(ev) {
        if !(ev is Map)
            return
        type := ev.Has("type") ? String(ev["type"]) : ""
        name := ev.Has("name") ? String(ev["name"]) : ""
        ts := ev.Has("ts") ? String(ev["ts"]) : ""
        live := ev.Has("live") && ev["live"] is Integer && ev["live"] = 1
        test := (SubStr(ts, 1, 5) = "TEST-") || (ev.Has("test") && ev["test"])
        switch type {
            case "biome": this._Biome(name, ts, live, test)
            case "aura": this._Aura(name, live, ev)
        }
    }

    _Biome(name, ts, live, test := false) {
        if (Trim(name) = "")
            return
        info := Biomes.Find(this._cfg, name)
        rare := info["rare"]
        st := this._state
        prev := st.HasProp("biome") ? String(st.biome) : ""
        st.biome := name
        if !rare {
            st.rareActive := false
            st.rareTs := ""
        }
        if !live {
            this._Log("Biome (startup): " name)
            if test
                return
            last := (prev != "") ? prev : this._LoadLast()
            this._SaveLast(name)
            if (last != "" && StrUpper(last) != StrUpper(name)) {
                this._Log("Biome changed while the macro was stopped: " last " -> " name)
                this._Card("Ended", last)
                if rare
                    this._RareMessage(name, false, false)
                else
                    this._Card("Started", name)
            }
            return
        }
        if !test
            this._SaveLast(name)
        this._Log("Biome: " name (rare ? " (RARE)" : "") (info["known"] ? "" : " (not in biomes.json)"))
        if (!test && HasMethod(st, "Bump"))
            st.Bump("biomes")
        ; an Ended card when the biome changes, then a Started card, except
        ; for a rare biome: that one gets only the rare message below
        if (!test && prev != "" && prev != name)
            this._Card("Ended", prev)
        if (!test && !rare)
            this._Card("Started", name)
        if !rare {
            return
        }
        if (!test && HasMethod(st, "Bump"))
            st.Bump("rareBiomes")
        st.rareActive := true
        st.rareTs := ts               ; PotionsTask only acts while this matches its event
        ; Fake test events never ping (no mention, no @everyone). In a ghost
        ; server nobody can join: no @everyone (and no Join button).
        ghost := this._Ghost()
        this._RareMessage(name, !test, !test && !ghost && this._Everyone(name))
        if this._cfg.Get("General.sound", 1) {
            try this._soundFn.Call(this._cfg.Get("General.alertSound", "*48"))
        }
        if this._cfg.Get("Medal.onRareBiome", 1) {
            try this._clip.Trigger("rare")
        }
        if IsObject(this._potions) {
            try {
                this._potions.Queue(name, ts)
            } catch Any as e {
                this._Log("Potions: could not queue (" (e is Error ? e.Message : "error") "); no potion will be used")
            }
        }
    }

    ; The `rare` message: screenshot, Started time, Join server link and
    ; button, the biome's picture. mention / everyone as given.
    _RareMessage(name, mention, everyone) {
        shot := ""
        try shot := this._shotFn.Call()
        desc := "## Rare biome started`n**" name "**"
        if this._Ghost()
            desc .= "`n*Ghost server (nobody can join it): rejoining your private server.*"
        link := this._JoinLink()
        now := DateDiff(A_NowUTC, "19700101000000", "Seconds")
        fields := [Webhook.Field(Emoji.Clock " Started", "<t:" now ":T> (<t:" now ":R>)")]
        if (link != "")
            fields.Push(Webhook.Field(Emoji.Link " Join server", "[Click to join](" link ")"))
        this._Send("rare", "RARE BIOME: " name, desc, 0xF2A93B, {mention: mention, everyone: everyone, screenshot: shot, fields: fields
            , buttons: (link != "") ? [{label: "Join Server", url: link}] : "", thumbnail: BiomeEvents.Picture(name, this._picDir)})
    }

    _Aura(name, live, ev := "") {
        if (Trim(name) = "")
            return
        test := (ev is Map) && ((ev.Has("test") && ev["test"]) || (ev.Has("ts") && SubStr(String(ev["ts"]), 1, 5) = "TEST-"))
        had := false
        if !test {
            had := this._HadHas(name)
            this._HadAdd(name)                 ; startup aura and new ones too
        }
        if !live
            return
        ; Stats (daily summary): a new aura, rolled by the player, as rare as
        ; the clip rule wants (Medal.auraMinRarity / always classes)
        if (!test && !had && A_TickCount >= Auras.QuietUntil && IsObject(this._state) && HasMethod(this._state, "Bump")) {
            try {
                if Auras.Decide(this._cfg, name)["clip"]
                    this._state.Bump("rareAuras")
            }
        }
        if (test && this._cfg.Get("General.dryRun", 1) != 1)
            return
        if !this._cfg.Get("Medal.onRareAura", 0)
            return
        if (A_TickCount < Auras.QuietUntil) {
            this._Log("Aura: " Trim(name) " put on by the macro (no clip)")
            return
        }
        if had {
            this._Log("Aura: " Trim(name) " equipped before (no clip)")
            return
        }
        d := Auras.Decide(this._cfg, name)
        if !d["clip"] {
            k := Auras.Key(name)
            if (!d["known"] && !this.HasOwnProp("_unknownAuras"))
                this._unknownAuras := Map()
            if (!d["known"] && !this._unknownAuras.Has(k)) {
                this._unknownAuras[k] := true
                this._Log("Aura: unknown aura " Trim(name) " " Chr(0x2014) " add to data/auras.json (no clip)")
            }
            return
        }
        this._Log("Aura: " name " (clip: " d["why"] ")")
        try this._clip.Trigger("aura:" name)
    }

    ; true when General.everyonePing=1 and the biome is in General.everyoneBiomes.
    _Everyone(name) {
        if !this._cfg.Get("General.everyonePing", 1)
            return false
        return Clip.NameInList(this._cfg.Get("General.everyoneBiomes", BiomeEvents.EveryoneDefault), name)
    }

    ; Private-server link for the rare webhook, or "". Never logged.
    _JoinLink() {
        if (!this._cfg.Get("General.joinButton", 0) || this._Ghost())
            return ""
        link := Trim(this._cfg.Get("General.privateServer", ""))
        return RegExMatch(link, "i)^https://(?:www\.)?roblox\.com/[^\s()\[\]]+$") ? link : ""
    }

    static IsNormal(name) => StrUpper(Trim(String(name))) = "NORMAL"

    ; The macro is in a ghost server (state.ghost, set by App from LogWatch joins).
    _Ghost() => IsObject(this._state) && HasProp(this._state, "ghost") && this._state.ghost

    ; Coteab-style biome card on the `biome` webhook (no title line). Started
    ; cards carry a "Join Server" link button (and the same link in the text,
    ; in case a client does not show buttons) when the private-server link
    ; is set.
    _Card(what, name) {
        now := DateDiff(A_NowUTC, "19700101000000", "Seconds")
        desc := "<t:" now ":F> (<t:" now ":R>)`n> ## Biome " what " - " name
        opts := ""
        if (what = "Started") {
            opts := {thumbnail: BiomeEvents.Picture(name, this._picDir)}
            link := this._JoinLink()
            if (link != "") {
                desc .= "`n> **[Join Server](" link ")**"
                opts.buttons := [{label: "Join Server", url: link}]
            }
        }
        this._Send("biome", "", desc, BiomeEvents.Color(name), opts)
    }

    _Send(ev, title, desc, color, opts := "") {
        if IsObject(this._wh) {
            try this._wh.Send(ev, title, desc, color, opts)
        }
    }

    _Log(t) {
        if IsObject(this._logFn) {
            try this._logFn.Call(t)
        }
    }
}
