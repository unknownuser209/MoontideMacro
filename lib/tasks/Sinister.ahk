#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\..\Webhook.ahk
; ---------------------------------------------------------------------------
; SinisterReport: ONE Discord message per natural spawn of the GRAVEYARD boss
; "Sinister S." that MinionsTask fights (boss mode), edited when it dies.
;
;   rep := SinisterReport(deps)   deps (all optional):
;     webhook  Webhook-like: PostText(event, content, opts) -> handle,
;              EditText(handle, content)
;     cfg      Get(path, default): General.privateServer (the link)
;     ghost    callable ghost() -> true in a ghost server (App: state.ghost
;              or the last join "other"). No ghost dep = unknown = no link.
;     log      callable log(text); text never holds the link or a URL
;     now      callable now() -> ms (default A_TickCount)
;     hook     one webhook Map: post to it only (tools\sinister_test.ahk),
;              in place of the "sinister" event's routing
;
;   rep.Spawn(key [, who])  the fight with the boss begins (MinionsTask:
;                    boss in sight). key = this spawn (the GRAVEYARD's start): the
;                    same key again posts nothing (one message per spawn,
;                    whether it was posted or skipped). Posts a card like
;                    the biome cards ("Sinister S. has spawned" + Join
;                    Server) on the "sinister" event. who = "s" / "p" or
;                    "orb:<Name>" (ChatWatch: an orb in the chat): an orb's
;                    card ("Typhoon orb has spawned") goes once per orb per
;                    OrbGapMs and leaves the boss fight's state alone (no
;                    dead edit for orbs). The Join Server link
;                    is left out (the card still goes, as the biome cards)
;                    when General.joinButton is off, the link is empty or
;                    not a roblox.com link, or ghost() is not false (audit
;                    2026-11-20: these sent no boss card at all).
;   rep.Note(fill, seen [, now])  a fight tick: fill = the boss plate's HP
;                    fill (0..1) read this tick, "" = none read; seen = its
;                    plate (any bar, or the boss bar UI) in sight
;   rep.Died()       the player died: the plate out of sight means nothing,
;                    the low reads start over
;   rep.Killed(why)  dead for sure (a kill toast): the edit
;   rep.Gone()       the biome changed: the spawn is over; not dead by then
;                    = it despawned, the message stays as it is
;   rep.dead         true once the edit to "<boss> is dead" was made
;   rep.msg          the WebhookText handle ("" = nothing posted)
;
; KILLED (GUESSED: the boss not seen dying yet). The boss (2500 HP, its
; plate "2,497/2,500") is dead when:
;   - an award toast is read in the boss fight (MinionsTask's Orb Awards
;     toast check; Killed("toast")), or
;   - its plate read LowReads times at DeadFill or less (~200 HP), the last
;     of them LowKeepMs at most before the plate went out of sight, and then
;     no plate (no bar, no boss bar UI) for GoneMs, no death in between and
;     the biome still GRAVEYARD (Gone not called).
; Not dead (no edit): the biome changes (its timer ended), the plate goes at
; a high fill, the fight times out or stops. GoneMs is long because a bar's
; yellow gets too short to read at low fill (the orbs: L47 16:50:30) and
; flashes wash plates out for seconds.
; ---------------------------------------------------------------------------

class SinisterReport {
    static Event := "sinister"
    static Color := Map("s", 0x5B2A86, "p", 0xE8731C)    ; GRAVEYARD purple, PUMPKIN MOON orange
    ; orbs (2026-11-22): their biome's colour; an orb not listed gets OrbColor
    static OrbColors := Map("Typhoon", 0x3FA7D6, "Flame", 0xD62828, "Raincloud", 0x4A6FD0)
    static OrbColor := 0x8FD3FF
    static OrbGapMs := 120000        ; one message per orb per 2 min (ChatWatch dedupes the line too)
    static DeadFill := 0.08
    static LowReads := 2
    static LowKeepMs := 5000
    static GoneMs := 20000
    static LinkRe := "i)^https://(?:www\.)?roblox\.com/[^\s()\[\]<>`"]+$"

    __New(deps := "") {
        this._wh := SinisterReport._Dep(deps, "webhook")
        this._cfg := SinisterReport._Dep(deps, "cfg")
        this._ghostFn := SinisterReport._Dep(deps, "ghost")
        this._logFn := SinisterReport._Dep(deps, "log")
        this._nowFn := SinisterReport._Dep(deps, "now")
        this._hook := SinisterReport._Dep(deps, "hook")
        this._test := SinisterReport._Dep(deps, "test") ? true : false   ; Dev tools: cards marked [TEST]
        this._key := "", this._has := false, this._postedAt := Map()   ; boss -> ms of its last message
        this._Reset()
    }

    static SpawnGapMs := 900000      ; one message per 15 min, whoever saw it first

    ; "s" / "p" / "orb:<Name>" (anything else counts as S); an orb's name
    ; comes from the OCR: letters and digits only, so it can never break
    ; the card's markdown
    static Who(boss := "s") {
        boss := String(boss)
        if RegExMatch(boss, "i)^orb:(.*)$", &m) {
            name := SubStr(RegExReplace(m[1], "[^A-Za-z0-9]"), 1, 20)
            return "orb:" (name != "" ? name : "Biome")
        }
        return (StrLower(boss) = "p") ? "p" : "s"
    }

    static IsOrb(boss) => SubStr(SinisterReport.Who(boss), 1, 4) = "orb:"

    ; "Sinister S." / "Sinister P." / "Typhoon orb" (2026-11-22, a tester:
    ; "__ has spawned", orbs "__ orb has spawned")
    static BossName(boss := "s") {
        w := SinisterReport.Who(boss)
        if (SubStr(w, 1, 4) = "orb:")
            return SubStr(w, 5) " orb"
        return "Sinister " StrUpper(w) "."
    }

    static ColorOf(boss := "s") {
        w := SinisterReport.Who(boss)
        if (SubStr(w, 1, 4) != "orb:")
            return SinisterReport.Color[w]
        n := SubStr(w, 5)
        return SinisterReport.OrbColors.Has(n) ? SinisterReport.OrbColors[n] : SinisterReport.OrbColor
    }

    ; The cards, in the style of the biome cards (2026-11-16, the user: match
    ; "Biome Started"): time, a quoted heading, the Join Server link + button.
    ; unix: seconds (default now). 2026-11-22: "<name> has spawned" (was
    ; "Boss Spawned - <name>"), the same for an orb.
    static SpawnCard(link, boss := "s", unix := "") {
        u := (unix = "") ? DateDiff(A_NowUTC, "19700101000000", "Seconds") : unix
        ; link "": General.joinButton is off, the card names no server
        return {desc: "<t:" u ":F> (<t:" u ":R>)`n> ## " SinisterReport.BossName(boss) " has spawned" (link != "" ? "`n> **[Join Server](" link ")**" : "")
            , color: SinisterReport.ColorOf(boss), buttons: (link != "") ? [{label: "Join Server", url: link}] : ""}
    }

    static DeadCard(link, boss := "s", unix := "") {
        u := (unix = "") ? DateDiff(A_NowUTC, "19700101000000", "Seconds") : unix
        return {desc: "<t:" u ":F> (<t:" u ":R>)`n> ## " SinisterReport.BossName(boss) " is dead"
            , color: SinisterReport.ColorOf(boss), buttons: (link != "") ? [{label: "Join Server", url: link}] : ""}
    }

    _Reset() {
        this.msg := "", this.dead := false, this._link := "", this._open := false, this._boss := "s"
        this._lows := 0, this._lowAt := "", this._goneAt := ""
    }

    ; boss: "s" (Sinister S., GRAVEYARD) or "p" (Sinister P., the November
    ; 2026 one), as the message names it; "orb:<Name>" -> _OrbSpawn
    Spawn(key, boss := "s") {
        if SinisterReport.IsOrb(boss)
            return this._OrbSpawn(SinisterReport.Who(boss))
        key := String(key)
        if (this._has && key == this._key)
            return false
        ; the chat line and the fight see the same spawn (App shares one
        ; report): one message per SpawnGapMs; a fight's edit still goes to it
        now := this._Now()
        b := (StrLower(String(boss)) = "p") ? "p" : "s"
        if (this._postedAt.Has(b) && now - this._postedAt[b] < SinisterReport.SpawnGapMs) {
            this._has := true, this._key := key
            if (this._boss != b || this.dead)       ; another boss's report, or already dead: start over
                this._Reset(), this._boss := b
            this._open := true
            this._Log("sinister: Sinister " StrUpper(b) ". already announced " Round((now - this._postedAt[b]) / 60000) " min ago - no second message")
            return false
        }
        this._has := true, this._key := key
        this._Reset()
        this._boss := b
        this._open := true
        link := this._JoinLink("boss")
        h := this._Post(SinisterReport.SpawnCard(link, b))
        if !IsObject(h)
            return false
        this.msg := h, this._link := link, this._postedAt[b] := now
        this._Log("sinister: boss spawn message queued (" h.parts.Length " webhook(s))")
        return true
    }

    ; An orb's card (who "orb:<Name>"): once per orb per OrbGapMs, the boss
    ; fight's message and state untouched (orbs get no dead edit)
    _OrbSpawn(who) {
        now := this._Now()
        name := SinisterReport.BossName(who)
        if (this._postedAt.Has(who) && now - this._postedAt[who] < SinisterReport.OrbGapMs) {
            this._Log("sinister: " name " already announced " Round((now - this._postedAt[who]) / 1000) " s ago - no second message")
            return false
        }
        h := this._Post(SinisterReport.SpawnCard(this._JoinLink("orb"), who))
        if !IsObject(h)
            return false
        this._postedAt[who] := now
        this._Log("sinister: " name " spawn message queued (" h.parts.Length " webhook(s))")
        return true
    }

    ; the Join Server link for a card, "" when General.joinButton is off
    ; (Alerts), there is no usable link or not in the private server: the
    ; card goes out without it, as the biome cards (BiomeEvents._JoinLink)
    _JoinLink(what) {
        link := this._LinkNow()
        off := false
        try off := !this._cfg.Get("General.joinButton", 1)
        if off
            return ""
        if (link = "") {
            this._Log("sinister: no usable private server link - the " what " message goes without the Join Server link")
            return ""
        }
        if this._Ghost() {
            this._Log("sinister: not in your private server (or not known) - the " what " message goes without the Join Server link")
            return ""
        }
        return link
    }

    ; the card on the "sinister" event -> the handle, "" = not sent (logged)
    _Post(card) {
        if !IsObject(this._wh)
            return ""
        h := ""
        ; pings each webhook's Mention (2026-11-16, the user: it never @'d me)
        try h := this._wh.PostText(SinisterReport.Event, this._Mark(card)
            , IsObject(this._hook) ? {hook: this._hook, mention: true} : {mention: true})
        catch Any as e {
            this._Log("sinister: the Discord message failed (" Webhook.ScrubText(e is Error ? e.Message : String(e)) ")")
            return ""
        }
        if !IsObject(h) {
            this._Log("sinister: no webhook has the sinister event - no Discord message")
            return ""
        }
        return h
    }

    ; a test report's cards say so on their first line
    _Mark(card) {
        if this._test
            card.desc := "**[TEST]** from Dev tools, no boss spawned`n" card.desc
        return card
    }

    Note(fill, seen, now := "") {
        if (!this._open || this.dead)
            return
        now := now = "" ? this._Now() : now
        if seen {
            this._goneAt := ""
            if (fill != "" && fill <= SinisterReport.DeadFill)
                this._lows++, this._lowAt := now
            return
        }
        if (this._goneAt = "")
            this._goneAt := now
        if (this._lows >= SinisterReport.LowReads && this._goneAt - this._lowAt <= SinisterReport.LowKeepMs
            && now - this._goneAt >= SinisterReport.GoneMs)
            this.Killed("its plate went at fill " SinisterReport.DeadFill " or less and stayed gone")
    }

    Died() {
        this._lows := 0, this._lowAt := "", this._goneAt := ""
    }

    Gone() {
        if (this._open && !this.dead && IsObject(this.msg))
            this._Log("sinister: the biome changed with the boss not seen dead - message left as it is")
        this._open := false
    }

    Killed(why := "") {
        if (!this._open || this.dead)
            return false
        this.dead := true
        this._Log("sinister: boss down (" why ")")
        if !IsObject(this.msg)
            return false
        try this._wh.EditText(this.msg, this._Mark(SinisterReport.DeadCard(this._link, this._boss)))
        catch Any as e {
            this._Log("sinister: the edit failed (" Webhook.ScrubText(e is Error ? e.Message : String(e)) ")")
            return false
        }
        this._Log("sinister: message edited to dead")
        return true
    }

    ; the private server link, "" when unset or not a roblox.com link; one
    ; pasted without https:// is made clickable (as BiomeEvents.JoinUrl)
    _LinkNow() {
        link := ""
        try link := Trim(String(this._cfg.Get("General.privateServer", "")), " `t`r`n<>")
        if RegExMatch(link, "i)^(?:https?://)?((?:www\.)?roblox\.com/[^\s()\[\]]+)$", &m)
            link := "https://" (SubStr(m[1], 1, 4) = "www." ? "" : "www.") m[1]
        return RegExMatch(link, SinisterReport.LinkRe) ? link : ""
    }

    ; true unless the ghost dep says false (unknown = ghost: no send)
    _Ghost() {
        if !IsObject(this._ghostFn)
            return true
        try return (this._ghostFn)() ? true : false
        return true
    }

    _Now() => IsObject(this._nowFn) ? (this._nowFn)() : A_TickCount

    _Log(text) {
        if IsObject(this._logFn)
            try (this._logFn)(Webhook.ScrubText(text))
    }

    static _Dep(deps, key) {
        if (deps is Map)
            return deps.Has(key) ? deps[key] : ""
        return (IsObject(deps) && HasProp(deps, key)) ? deps.%key% : ""
    }
}
