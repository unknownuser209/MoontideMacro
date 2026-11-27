#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\Json.ahk
; ---------------------------------------------------------------------------
; Config: settings.ini (user settings, secrets) + data\*.json (game data).
;
;   cfg := Config.Load(dir)        dir holds settings.ini and a data\ folder.
;                                  Missing settings.ini is created with defaults.
;   cfg.Get("General.sellEvery", 15)   path = "Section.key" (split at the LAST
;                                  dot). Section and key are case-insensitive.
;                                  Missing -> default. Webhook.N sections are
;                                  NOT reachable via Get/Set: use Webhooks().
;                                  Result is coerced to the default's type:
;                                  Integer default accepts ints and true/false/
;                                  yes/no/on/off (-> 1/0); Float default accepts
;                                  numbers; anything unparsable -> default.
;   cfg.Set("Section.key", value)  in memory; call cfg.Save() to persist.
;   cfg.Webhooks()                 live Array of Maps {name,url,mention,enabled,
;                                  events}. enabled is Integer 0/1, events is an
;                                  Array of lowercase event names. Edit then
;                                  cfg.SetWebhooks(arr) (normalises) + Save().
;   cfg.Data("biomes")             Map parsed from data\biomes.json. Missing or
;                                  bad JSON (or non-object root) -> built-in
;                                  Config.Defaults(name) (empty Map if unknown
;                                  name). Bad files are never overwritten by a
;                                  load. cfg.DataStatus(name) = ok|missing|bad.
;   cfg.SetData(name, obj) / cfg.SaveData(name) persist a data file.
;
; SECRETS: settings.ini holds webhook URLs and the private-server link. Nothing
; in this file prints, logs or puts those values in an error message.
; ---------------------------------------------------------------------------

class Config {
    static EventTypes := ["biome", "rare", "merchant", "quests", "craft", "errors", "startstop", "potions", "clips", "obby", "memorymatch", "sinister"]

    ; Section write order in settings.ini (others follow alphabetically,
    ; then Webhook.N numerically).
    static SectionOrder := ["General", "Hotkeys", "Medal"]

    ; ---- construction ------------------------------------------------------

    static Load(dir) {
        return Config(dir)
    }

    __New(dir) {
        dir := RTrim(dir, "\/")
        if (dir = "")
            throw ValueError("Config: empty directory")
        if !DirExist(dir)
            DirCreate(dir)
        this.dir := dir
        this.iniPath := dir "\settings.ini"
        this.dataDir := dir "\data"
        this.sections := Config._CIMap()
        this.hooks := []
        this.readFail := false
        this.dcache := Map()
        this.dstat := Map()
        if FileExist(this.iniPath) {
            this._ReadIni()
            this._DropRetired()
        } else {
            this._ApplyIniDefaults()
            this.Save()
        }
    }

    ; Settings the app no longer has (2026-11-23: Minions.putBack, "Put my
    ; aura back after", nobody used it; 2026-11-25: General.joinButton and
    ; its marker joinDefaultOn, the Join Server link is always on, the user):
    ; dropped on load, gone from the file at the next Save.
    static RetiredKeys := ["Minions.putBack", "General.joinButton", "General.joinDefaultOn"]

    ; Settings that moved (old path -> new path), on load: the old value goes
    ; to the new key unless the new key is already set, then the old key is
    ; dropped (gone from the file at the next Save). 2026-11-26: the Limited
    ; tab became the built-in "Orb & boss hunting" plugin (Plugins tab), its
    ; keys moved from [Limited] to [Hunting].
    static RenamedKeys := Map("Limited.bossAlert", "Hunting.bossAlert", "Limited.orbAlert", "Hunting.orbAlert"
        , "Limited.cursedRune", "Hunting.cursedRune")

    _DropRetired() {
        for old, new in Config.RenamedKeys {
            o := Config._SplitPath(old), n := Config._SplitPath(new)
            if !(this.sections.Has(o[1]) && this.sections[o[1]].Has(o[2]))
                continue
            if !this.sections.Has(n[1])
                this.sections[n[1]] := Config._CIMap()
            if !this.sections[n[1]].Has(n[2])
                this.sections[n[1]][n[2]] := this.sections[o[1]][o[2]]
            this.sections[o[1]].Delete(o[2])
            if !this.sections[o[1]].Count
                this.sections.Delete(o[1])
        }
        for path in Config.RetiredKeys {
            p := Config._SplitPath(path)
            if (this.sections.Has(p[1]) && this.sections[p[1]].Has(p[2]))
                this.sections[p[1]].Delete(p[2])
        }
        ; sections whose missing keys get their defaults (see BackfillSections)
        defs := ""
        for sec in Config.BackfillSections {
            if !IsObject(defs)
                defs := Config.IniDefaults()
            if !this.sections.Has(sec)
                this.sections[sec] := Config._CIMap()
            for k, v in defs[sec]
                if !this.sections[sec].Has(k)
                    this.sections[sec][k] := v
        }
    }

    ; A settings.ini from before the updater had no [Update], and a missing
    ; repo hid the Home page's Updates box (Check for updates) and the start
    ; check for good (the owner's PC, 2026-11-26). Its missing keys are filled
    ; on load; a key that is there, even empty (repo= : never check), stays.
    ; Other sections keep "absent = the caller's default".
    static BackfillSections := ["Update"]

    ; Quests removed from the list (2026-11-23, nobody had seen them on the
    ; board). An older quests.json loses them on load (saved with the next
    ; SaveData); a type left empty goes too.
    static RetiredQuests := ["Time of Patience", "Your First Gear"]

    static _DropRetiredQuests(data) {
        if !(data.Has("types") && data["types"] is Array)
            return
        gone := Map()
        gone.CaseSense := "Off"
        for n in Config.RetiredQuests
            gone[n] := 1
        i := data["types"].Length
        while (i >= 1) {
            t := data["types"][i]
            if (t is Map && t.Has("quests") && t["quests"] is Array) {
                had := t["quests"].Length
                j := had
                while (j >= 1) {
                    q := t["quests"][j]
                    if (q is Map && q.Has("name") && gone.Has(String(q["name"])))
                        t["quests"].RemoveAt(j)
                    j--
                }
                if (had > 0 && t["quests"].Length = 0)
                    data["types"].RemoveAt(i)
            }
            i--
        }
    }

    static _CIMap() {
        m := Map()
        m.CaseSense := "Off"
        return m
    }

    static IniDefaults() {
        d := Config._CIMap()
        g := Config._CIMap()
        g["privateServer"] := ""
        g["windowed"] := "0"          ; 1 = Roblox may be in a window (used as the player sized it); 0 = fullscreen only
        g["idleMode"] := "0"          ; 1 = Start only reads (biomes, auras, chat, biome clock): no clicks, no keys, Roblox may stay behind other windows
        g["vip"] := "1"
        g["fishing"] := "1"           ; 0 = never fish (only quests, craft, merchants, potions...)
        g["sellEvery"] := "15"
        g["sellAll"] := "1"
        g["advancedFishing"] := "0"
        g["legacyReel"] := "0"        ; 1 = FishSol minigame logic (old reel UI)
        g["advancedThreshold"] := "20"
        g["fishingFailsafeSec"] := "31"
        g["pathingFailsafeSec"] := "61"
        g["repathOnStart"] := "1"     ; 1 = each Start walks to the fisher and back (Sell) before fishing
        g["awayRefocus"] := "1"       ; 1 = "Roblox lost focus" while nobody uses the PC (2 min): Roblox back in front, resumed (a few times an hour)
        g["questIntervalMin"] := "30"
        g["dryRun"] := "1"
        g["sound"] := "1"
        g["alertSound"] := "*48"      ; SoundPlay arg: *48 = Windows exclamation, or a .wav path
        g["everyonePing"] := "1"      ; 1 = live rare webhook for the biomes below also pings @everyone
        g["everyoneBiomes"] := "DREAMSPACE,GLITCHED,CYBERSPACE"
        g["biomePings"] := ""         ; BIOME=role or user ID, comma list (SINGULARITY=&123): the live rare message also pings it (2026-11-22)
        d["General"] := g
        ; Which potions the craft/fisher tasks buy: comma list of full names,
        ; each must match a name in data\potions.json.
        cr := Config._CIMap()
        cr["potions"] := "Lucky Potion"
        cr["enabled"] := "0"          ; Fish shop buys on/off: off for a new install (it spends in-game money; audit 2026-11-20). Only a NEW settings.ini gets these; a missing key still reads 1 (the code defaults), so no existing user changes
        cr["qty"] := "1"              ; units bought per potion per crafted notification (1..999)
        cr["minIntervalMin"] := "10"  ; minutes after a craft run / buy before the crafted notification is read again
        ; Optional per-potion override: qty_<id> = number, <id> = the potion
        ; name lower-cased with non-alphanumerics as "_" (qty_lucky_potion = 3).
        cr["cauldron"] := "0"         ; 1 = also visit Stella's cauldron (needs recorded routes)
        cr["craftTarget"] := ""       ; full potion name typed into the cauldron search box
        d["Craft"] := cr
        h := Config._CIMap()
        h["start"] := "F1"
        h["pause"] := "F2"
        h["stop"] := "F3"
        d["Hotkeys"] := h
        ; Recovery task (lib/tasks/Recovery.ahk). The private-server link is
        ; General.privateServer (secret: never logged or sent).
        rc := Config._CIMap()
        rc["enabled"] := "1"
        rc["stuckMin"] := "10"          ; minutes without fishing progress
        rc["afkMin"] := "15"            ; Space tap interval (anti-AFK)
        rc["loadSec"] := "20"           ; wait after the window appears
        rc["maxRejoins"] := "3"         ; Run(link) attempts per window
        rc["rejoinWindowMin"] := "10"
        rc["antiGhost"] := "1"          ; rejoin when the game teleports you out of the private server
        d["Recovery"] := rc
        ; Biome items (lib/tasks/BiomeItems.ahk): used only in NORMAL, never the
        ; one-time Biome Randomizer.
        bi := Config._CIMap()
        bi["enabled"] := "0"
        bi["biomeRandomizer"] := "0"
        bi["strangeController"] := "0"
        bi["biomeSelector"] := "0"    ; spends one Drive per use
        bi["selectorDrive"] := ""     ; which Drive the Selector picks (BiomeItemsTask.Drives)
        bi["blacklist"] := ""         ; comma list of biomes: no items used while one is up (wait for the next biome)
        d["BiomeItems"] := bi
        ; Hunting (the built-in "Orb & boss hunting" plugin, lib\plugins\hunting;
        ; [Limited] before 2026-11-26, RenamedKeys): the bosses' Discord message
        ; from the chat (hunting on or off) and one Cursed Rune Fragment per
        ; GRAVEYARD / PUMPKIN MOON night. All of it only while the plugin is on.
        lm := Config._CIMap()
        lm["bossAlert"] := "1"        ; 1 = a Sinister S. / P. line in the chat sends the "sinister" message
        lm["orbAlert"] := "0"         ; 1 = an orb line in the chat ("Typhoon Orb has spawned") sends the "sinister" message (2026-11-22; off: orbs come in most biomes)
        lm["cursedRune"] := "0"       ; 1 = use ONE Cursed Rune Fragment when GRAVEYARD or PUMPKIN MOON starts
        d["Hunting"] := lm
        ; Plugins (lib\Plugins.ahk): <id> = 1 on / 0 off. The built-in ones;
        ; a plugin dropped into plugins\ is off until switched on.
        pl := Config._CIMap()
        pl["hunting"] := "1"
        pl["sniper"] := "0"
        d["Plugins"] := pl
        ; Rare aura alert (2026-11-16): a new aura the player rolled, as rare
        ; as minRarity or rarer, goes to the Rare webhooks with a screenshot
        ; and pings userId.
        g0 := d["General"]
        g0["displayScale"] := "0"     ; Calibrate > Scale: 0 = Auto (read from Windows), else 100/125/150/175/200
        aa := Config._CIMap()
        aa["enabled"] := "0"
        aa["userId"] := ""            ; Discord user ID (or &role ID) to ping; "" = no ping
        aa["minRarity"] := "10000000" ; 1 in N or rarer (datauras.json)
        d["AuraAlert"] := aa
        ; Limbo (lib/tasks/Limbo.ahk): stay in THE LIMBO by Eden's spawn instead
        ; of fishing; leave for rare biomes.
        li := Config._CIMap()
        li["enabled"] := "0"
        d["Limbo"] := li
        ; Obby (lib/tasks/Obby.ahk) and Memory Match (lib/tasks/MemoryMatch.ahk).
        ob := Config._CIMap()
        ob["enabled"] := "0"
        ob["intervalMin"] := "10"     ; minutes between obby runs (1..120)
        ob["route"] := "obby"         ; routes.json route that walks to the obby
        ob["retries"] := "2"          ; extra tries after a failed run (2: a recorded walk misses ~1 in 2 from the random spawn spot)
        ob["align"] := ""             ; "key:ms, ..." (w a s d) held after the camera reset, before the route: "" = off
        ob["alignOffset"] := ""       ; the same, after align: from the aligned spot to where the recording starts
        d["Obby"] := ob
        ; Daily Quests (lib/tasks/DailyQuests.ahk): claim the finished ones,
        ; reroll (free rerolls only) the ones holding a word of reroll.
        dq := Config._CIMap()
        dq["enabled"] := "0"
        dq["intervalMin"] := "30"     ; minutes between visits (5..720)
        dq["reroll"] := ""            ; comma list: quests holding one of these words are rerolled
        dq["usePotions"] := "0"       ; "Use N <potion>" quests: the potion task uses what is left
        d["DailyQuests"] := dq
        mm := Config._CIMap()
        mm["enabled"] := "0"
        mm["route"] := "memory_match" ; routes.json route that walks to the game
        d["MemoryMatch"] := mm
        ; Minions (lib/tasks/Minions.ahk): fight the weather biomes' orbs.
        mn := Config._CIMap()
        mn["enabled"] := "0"
        mn["aura"] := "Eden"          ; combat aura worn for the hunt
        mn["maxSec"] := "120"         ; longest hunt per biome
        mn["shiftLock"] := "1"        ; 1 = shift lock on in fights (Roblox's Shift Lock Switch setting on)
        mn["boss"] := "1"             ; 1 = look for (and fight) the boss once per GRAVEYARD start
        mn["bigAuras"] := "Equinox,Luminosity"   ; big auras: the fight camera stays zoomed all the way out (and a warning)
        d["Minions"] := mn
        ; Aura swaps (ObbyTask's storage swap: Sailor for the obby, the
        ; Minions combat aura, putting the aura from before back).
        au := Config._CIMap()
        au["equipFirst"] := "0"       ; 1 = equip the first search result, no name / button reads (low resolutions)
        d["Auras"] := au
        m := Config._CIMap()
        m["enabled"] := "0"
        m["app"] := "medal"           ; clip app (Clip.Apps): medal, discord, nvidia, amd, obs, other
        m["clipHotkey"] := "F8"
        m["delaySec"] := "3"
        m["cooldownSec"] := "30"
        m["onRareBiome"] := "1"
        m["onRareAura"] := "0"
        m["auras"] := ""              ; comma list of aura names that always clip
        m["auraMinRarity"] := "100000000"   ; clip auras with rarity 1 in N >= this (data\auras.json; 0 = off)
        m["auraAlwaysCategories"] := "Challenged,Challenged+"   ; aura classes that always clip
        m["clipCutscenes"] := "0"     ; 1 = clip every new aura that plays a roll cutscene, whatever its rarity
        d["Medal"] := m
        ca := Config._CIMap()
        ca["captureKey"] := "F4"      ; calibration capture key (F9 = Roblox dev console; F6 / F8 Medal)
        d["Calibrate"] := ca
        q := Config._CIMap()
        q["dismissDisabled"] := "0"   ; 1 = Dismiss (abandon) unticked quests; 0 = skip them
        d["Quests"] := q
        ; UI (lib/ui/Anim.ahk): animations.
        u := Config._CIMap()
        u["animations"] := "1"        ; 0 = no UI animations
        u["setupDone"] := "0"         ; 1 = the first-run setup wizard was finished or skipped
        u["theme"] := "Moontide"      ; the theme in use: a preset (Theme.Names) or a saved theme (ThemeStore, Settings > Look)
        u["lang"] := "en"             ; window language (lib/I18n.ahk, lang\<code>.json): en, es, pt, fil, fr, de, vi
        ; the old custom theme (before saved themes): ThemeStore.Migrate turns these into the theme "My theme" once
        u["customBg"] := "0D1117"     ; window background
        u["customPanel"] := "0B2A5B"  ; panels and borders
        u["customText"] := "F7F1E8"   ; text
        u["customAccent"] := "F2A93B" ; accent: titles, buttons, the active tab
        u["customPicture"] := "Moontide"   ; background picture: none, a theme name (its picture) or file (customPictureFile)
        u["customPictureFile"] := ""  ; a picture of your own (png / jpg / bmp), darkened to fit
        d["UI"] := u
        ; Run schedule (lib/Schedule.ahk): start / stop by the clock, stop after N hours.
        sc := Config._CIMap()
        sc["enabled"] := "0"
        sc["start"] := "22:00"        ; HH:mm, local time
        sc["end"] := "08:00"          ; HH:mm; start = end means all day
        sc["maxHours"] := "0"         ; stop after this many hours of running (0 = no limit)
        d["Schedule"] := sc
        ; Daily Discord summary (lib/DailySummary.ahk), to the webhooks with Start/Stop on.
        su := Config._CIMap()
        su["enabled"] := "0"
        su["time"] := "23:55"         ; HH:mm, local time
        d["Summary"] := su
        ; Discord remote control (lib/Remote.ahk): a bot polls one channel.
        rm := Config._CIMap()
        rm["enabled"] := "0"
        rm["token"] := ""             ; SECRET: the bot token, never shown or logged
        rm["channel"] := ""           ; channel id the bot reads
        rm["users"] := ""             ; comma list of Discord user ids allowed to command
        rm["prefix"] := "!"
        rm["pollSec"] := "5"
        d["Remote"] := rm
        ; Auto-updater (lib/Updater.ahk). repo empty = no update checks at all.
        up := Config._CIMap()
        up["repo"] := "unknownuser209/MoontideMacro"   ; GitHub owner/name whose Releases to follow ("" = never check)
        up["check"] := "1"            ; 1 = look for a new version once per start
        up["auto"] := "0"             ; 0 = ask in the dashboard, 1 = install without asking
        d["Update"] := up
        ; Dev copy only (Help > Dev tools): dim every monitor while the macro
        ; runs, invisible to its screen reads and recordings (lib/ScreenDim.ahk)
        dv := Config._CIMap()
        dv["dim"] := "0"
        dv["dimPct"] := "95"          ; how dark, 5..98
        dv["lights"] := "1"           ; 1 = the PC's lights fade with it (dev\lights helper, when built)
        d["Dev"] := dv
        return d
    }

    _ApplyIniDefaults() {
        this.sections := Config.IniDefaults()
        this.hooks := []
    }

    ; ---- ini read/write ----------------------------------------------------

    _ReadIni() {
        this.sections := Config._CIMap()
        text := ""
        ok := false
        Loop 4 {
            try {
                text := FileRead(this.iniPath, "UTF-8")
                ok := true
                break
            }
            Sleep(100)
        }
        if !ok {
            ; Existing file unreadable (lock etc.): never let Save() clobber it.
            this.readFail := true
            this.hooks := []
            return
        }
        sec := ""
        for line in StrSplit(text, "`n", "`r") {
            line := Trim(line)
            if (line = "" || SubStr(line, 1, 1) = ";" || SubStr(line, 1, 1) = "#")
                continue
            if (SubStr(line, 1, 1) = "[") {
                if (SubStr(line, -1) = "]" && StrLen(line) > 2) {
                    sec := Trim(SubStr(line, 2, StrLen(line) - 2))
                    if (sec != "" && !this.sections.Has(sec))
                        this.sections[sec] := Config._CIMap()
                } else
                    sec := ""
                continue
            }
            eq := InStr(line, "=")
            if (sec = "" || eq < 2)
                continue
            this.sections[sec][Trim(SubStr(line, 1, eq - 1))] := Trim(SubStr(line, eq + 1))
        }
        ; pull Webhook.N sections out into the webhook array (numeric order)
        nums := ""
        names := Map()
        for name, keys in this.sections {
            if RegExMatch(name, "^Webhook\.(\d+)$", &m) {
                nums .= (nums = "" ? "" : "`n") m[1]
                names[Integer(m[1])] := name
            }
        }
        this.hooks := []
        if (nums != "") {
            nums := Sort(nums, "N")
            for n in StrSplit(nums, "`n") {
                sect := this.sections[names[Integer(n)]]
                hook := Map()
                for k in ["name", "url", "mention", "enabled", "events"]
                    hook[k] := sect.Has(k) ? sect[k] : (k = "enabled" ? "1" : "")
                this.hooks.Push(Config._NormHook(hook))
            }
        }
        for _, name in names
            this.sections.Delete(name)
    }

    Save() {
        if this.readFail
            throw Error("Config: settings.ini exists but could not be read; refusing to overwrite it. Reload after closing whatever has it open.")
        out := ""
        done := Map()
        for name in Config.SectionOrder {
            if this.sections.Has(name) {
                out .= Config._SectionText(name, this.sections[name])
                done[name] := true
            }
        }
        rest := []
        for name, keys in this.sections {
            if (!done.Has(name))
                rest.Push(name)
        }
        for name in rest
            out .= Config._SectionText(name, this.sections[name])
        for i, hook in this.hooks {
            sect := Config._CIMap()
            sect["name"] := hook["name"]
            sect["url"] := hook["url"]
            sect["mention"] := hook["mention"]
            sect["enabled"] := String(hook["enabled"])
            ev := ""
            for e in hook["events"]
                ev .= (ev = "" ? "" : ",") e
            sect["events"] := ev
            out .= Config._SectionText("Webhook." i, sect)
        }
        Config._WriteText(this.iniPath, out)
    }

    ; Reads settings.ini again and forgets the loaded data files (the next
    ; Data() reads them from disk): after Settings > Profiles "Import
    ; everything" wrote new files under this object.
    Reload() {
        this.readFail := false
        this.dcache := Map()
        this.dstat := Map()
        if FileExist(this.iniPath) {
            this._ReadIni()
            this._DropRetired()
        }
    }

    static _SectionText(name, keys) {
        s := "[" name "]`r`n"
        for k, v in keys
            s .= k "=" v "`r`n"
        return s "`r`n"
    }

    ; Atomic-ish UTF-8 (no BOM) write: temp file then replace.
    static _WriteText(path, text) {
        tmp := path ".tmp"
        f := FileOpen(tmp, "w", "UTF-8-RAW")
        f.Write(text)
        f.Close()
        try
            FileMove(tmp, path, 1)
        catch as e {
            try FileDelete(tmp)     ; tmp may hold secrets: never leave it behind
            throw e
        }
    }

    ; ---- settings access ---------------------------------------------------

    static _SplitPath(path) {
        dot := InStr(path, ".", , -1)
        if (dot < 2 || dot = StrLen(path))
            throw ValueError("Config: path must look like Section.key")
        return [SubStr(path, 1, dot - 1), SubStr(path, dot + 1)]
    }

    Get(path, default := "") {
        p := Config._SplitPath(path)
        if !(this.sections.Has(p[1]) && this.sections[p[1]].Has(p[2]))
            return default
        return Config._Coerce(this.sections[p[1]][p[2]], default)
    }

    Set(path, value) {
        p := Config._SplitPath(path)
        if RegExMatch(p[1], "^Webhook\.\d+$")
            throw ValueError("Config: use SetWebhooks() for webhook entries")
        if !this.sections.Has(p[1])
            this.sections[p[1]] := Config._CIMap()
        this.sections[p[1]][p[2]] := Config._Clean(value)
    }

    static _Clean(v) {
        return Trim(RegExReplace(String(v), "[\r\n]+", " "))
    }

    static _ToBool(v) {
        if (v is Integer || v is Float)
            return v ? 1 : 0
        s := Trim(String(v))
        if (s = "1" || s = "true" || s = "yes" || s = "on")
            return 1
        return 0
    }

    static _Coerce(raw, default) {
        if (default is Integer) {
            if (raw = "true" || raw = "yes" || raw = "on")
                return 1
            if (raw = "false" || raw = "no" || raw = "off")
                return 0
            if IsInteger(raw)
                return Integer(raw)
            return default
        }
        if (default is Float)
            return IsNumber(raw) ? Float(raw) : default
        return raw
    }

    ; ---- webhooks ----------------------------------------------------------

    Webhooks() {
        return this.hooks
    }

    SetWebhooks(arr) {
        list := []
        for hook in arr
            list.Push(Config._NormHook(hook))
        this.hooks := list
    }

    ; Returns a fresh normalised Map. Error text never includes field values.
    static _NormHook(hook) {
        if !(hook is Map)
            throw TypeError("Config: webhook entry must be a Map")
        ev := hook.Has("events") ? hook["events"] : []
        events := []
        if (ev is Array)
            list := ev
        else if (ev is String)
            list := StrSplit(ev, ",")
        else
            throw TypeError("Config: webhook events must be an Array or comma-separated String")
        for e in list {
            e := StrLower(Trim(String(e)))
            if (e != "")
                events.Push(e)
        }
        return Map(
            "name", Config._Clean(hook.Has("name") ? hook["name"] : ""),
            "url", Config._Clean(hook.Has("url") ? hook["url"] : ""),
            "mention", Config._Clean(hook.Has("mention") ? hook["mention"] : ""),
            "enabled", Config._ToBool(hook.Has("enabled") ? hook["enabled"] : 1),
            "events", events
        )
    }

    ; ---- data json ---------------------------------------------------------

    static _CheckName(name) {
        if !RegExMatch(name, "^[A-Za-z0-9_\-]+$")
            throw ValueError("Config: invalid data name")
    }

    _LoadData(name) {
        Config._CheckName(name)
        if this.dcache.Has(name)
            return
        path := this.dataDir "\" name ".json"
        status := "ok"
        result := ""
        if !FileExist(path) {
            status := "missing"
        } else {
            try {
                v := Json.Parse(FileRead(path, "UTF-8"))
                if (v is Map)
                    result := v
                else
                    status := "bad"
            } catch
                status := "bad"
        }
        if (status != "ok")
            result := Config.Defaults(name)
        else if (name = "quests")
            Config._DropRetiredQuests(result), Config._AddMissingQuests(result)
        this.dcache[name] := result
        this.dstat[name] := status
    }

    ; A quests.json from an older version lacks quests added since (To the
    ; Temple, Your First Gear: 2026-11-18). Known default quests missing by
    ; name are appended DISABLED, in memory (saved with the next SaveData).
    static _AddMissingQuests(data) {
        if !(data.Has("types") && data["types"] is Array)
            return
        have := Map()
        have.CaseSense := "Off"
        for t in data["types"]
            if (t is Map && t.Has("quests") && t["quests"] is Array)
                for q in t["quests"]
                    if (q is Map && q.Has("name"))
                        have[String(q["name"])] := 1
        for dt in Config._DefQuests()["types"] {
            for dq in dt["quests"] {
                if have.Has(dq["name"])
                    continue
                dest := ""
                for t in data["types"]
                    if (t is Map && t.Has("name") && t["name"] = dt["name"] && t.Has("quests") && t["quests"] is Array)
                        dest := t
                if (dest = "") {
                    dest := Map("name", dt["name"], "enabled", 1, "quests", [])
                    data["types"].Push(dest)
                }
                dest["quests"].Push(Map("name", dq["name"], "enabled", 0))
            }
        }
    }

    Data(name) {
        this._LoadData(name)
        return this.dcache[name]
    }

    DataStatus(name) {
        this._LoadData(name)
        return this.dstat[name]
    }

    SetData(name, obj) {
        Config._CheckName(name)
        if !(obj is Map)
            throw TypeError("Config: data must be a Map")
        this.dcache[name] := obj
        this.dstat[name] := "ok"
    }

    SaveData(name) {
        Config._CheckName(name)
        if !this.dcache.Has(name)
            this._LoadData(name)
        if !DirExist(this.dataDir)
            DirCreate(this.dataDir)
        Config._WriteText(this.dataDir "\" name ".json", Json.Stringify(this.dcache[name]) "`n")
        this.dstat[name] := "ok"
    }

    ; ---- built-in data defaults (must match shipped data\*.json) -----------

    static Defaults(name) {
        switch name {
            case "biomes": return Config._DefBiomes()
            case "potions": return Config._DefPotions()
            case "quests": return Config._DefQuests()
            case "merchants": return Map("Mari", [], "Jester", [])
            case "auras": return Map("auras", [])     ; file only (data\auras.json); no built-in table
        }
        return Map()
    }

    static _DefBiomes() {
        names := ["NORMAL", "WINDY", "SNOWY", "RAINY", "SAND STORM", "HELL", "STARFALL", "CORRUPTION"
            , "LOST FOREST", "NULL", "HEAVEN", "GLITCHED", "DREAMSPACE", "CYBERSPACE", "SINGULARITY", "RADIANT FOREST"
            , "PUMPKIN MOON", "GRAVEYARD", "BLOOD RAIN", "EGGLAND"]
        rare := Map("GLITCHED", 1, "DREAMSPACE", 1, "CYBERSPACE", 1, "RADIANT FOREST", 1, "SINGULARITY", 1)
        list := []
        for n in names
            list.Push(Map("name", n, "rare", rare.Has(n) ? 1 : 0, "potions", []))
        return Map("biomes", list)
    }

    ; id = identity (caps/locks/biome lists), name = exact in-game tile name,
    ; desc = distinctive description substring ("" = fill in from the game;
    ; such a potion is never used outside dry run; a dry run reports the
    ; description it read). Pick text that only this potion has, e.g.
    ; "1 minute of [Lucky]" (Lucky Potion L also says "[Lucky]"). Only the
    ; first four are unlocked; the three "Godly Potion"s differ only by
    ; description.
    static _DefPotions() {
        unlocked := ["Lucky Potion", "Speed Potion", "Fortune Potion I", "Haste Potion I"]
        locked := ["Lucky Potion L", "Lucky Potion XL", "Speed Potion L", "Speed Potion XL"
            , "Fortune Potion II", "Fortune Potion III", "Huge Fortune Potion I", "Haste Potion II", "Haste Potion III"
            , "Transcendent Potion", "Heavenly Potion"
            , "Oblivion Potion", "Godlike Potion"]
        ; In the game's potion list (2026-10-26) after the ones above. Heavenly
        ; Potion I / II and Sizemax / Sizemin are deliberately absent and on
        ; PotionSafety.NeverUse.
        more := ["Potion of Bound", "Strange Potion I", "Strange Potion II", "Jewelry Potion", "Rage Potion"
            , "Diver Potion", "Zombie Potion", "Popping Potion", "Gladiator Potion", "Fortune Spoid I"
            , "Fortune Spoid II", "Fortune Spoid III", "Mixed Potion", "Raid Potion", "Potion of the Dune"
            , "Red Moon Potion I", "Red Moon Potion II", "Void Heart"]
        list := []
        mk := (id, name, desc, lk) => Map("id", id, "name", name, "desc", desc, "locked", lk, "perBiome", 1, "perDay", 3, "perRun", 3)
        for n in unlocked
            list.Push(mk(n, n, "", 0))
        for n in locked
            list.Push(mk(n, n, "", 1))
        list.Push(mk("Godly Potion (Sky)", "Godly Potion", "Lord of the Sky", 1))
        list.Push(mk("Godly Potion (Sea)", "Godly Potion", "Lord of the Sea", 1))
        list.Push(mk("Godly Potion (Hell)", "Godly Potion", "Lord of Hell", 1))
        list.Push(mk("Warp Potion", "Warp Potion", "", 1))
        for n in more
            list.Push(mk(n, n, "", 1))
        return Map("potions", list)
    }

    static _DefQuests() {
        types := [
            ["Player Hunt", ["Player Hunt I", "Player Hunt II", "Player Hunt III"]],
            ["Aura Hunt", ["Basic Aura Hunt", "Epic Aura Hunt", "Unique Aura Hunt", "Legendary Aura Hunt", "Mythic Aura Hunt"]],
            ["Breakthroughs", ["Breakthroughs"]],
            ["Resonance", ["Resonance"]],
            ["Delivery", ["Delivery I", "Delivery II", "Delivery III", "Delivery IV", "Delivery V"]],
            ["Fishing", ["River Angler", "Minnow Rookie", "Deep-Sea Hunter", "Legendary Fisher"]],
            ["Finding a Person", ["Finding a Person"]],
            ["Lucky Clover", ["Lucky Clover"]],
            ["Meditation", ["Meditation I", "Meditation II", "Meditation III"]],   ; "play for N minutes" (2026 board)
            ["Obby", ["To the Temple"]]         ; complete the obby, get a Basic Blessing (user list 2026-11-18)
        ]   ; Time of Patience and Gear (Your First Gear) removed 2026-11-23: nobody had seen them
        out := []
        for t in types {
            qs := []
            for q in t[2]
                qs.Push(Map("name", q, "enabled", 1))
            out.Push(Map("name", t[1], "enabled", 1, "quests", qs))
        }
        return Map("types", out)
    }
}
