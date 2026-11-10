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
;              or the last join "other"). No ghost dep = unknown = NO send.
;     log      callable log(text); text never holds the link or a URL
;     now      callable now() -> ms (default A_TickCount)
;     hook     one webhook Map: post to it only (tools\sinister_test.ahk),
;              in place of the "sinister" event's routing
;
;   rep.Spawn(key)   the fight with the boss begins (MinionsTask: boss in
;                    sight). key = this spawn (the GRAVEYARD's start): the
;                    same key again posts nothing (one message per spawn,
;                    whether it was posted or skipped). Posts
;                    "<link> sinister s natrual spawn" (the user's words) on
;                    the "sinister" event, unless the link is empty or not a
;                    https://www.roblox.com/ link, or ghost() is not false.
;   rep.Note(fill, seen [, now])  a fight tick: fill = the boss plate's HP
;                    fill (0..1) read this tick, "" = none read; seen = its
;                    plate (any bar, or the boss bar UI) in sight
;   rep.Died()       the player died: the plate out of sight means nothing,
;                    the low reads start over
;   rep.Killed(why)  dead for sure (a kill toast): the edit
;   rep.Gone()       the biome changed: the spawn is over; not dead by then
;                    = it despawned, the message stays as it is
;   rep.dead         true once the edit to "<link> dead" was made
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
    static SpawnText := "sinister s natrual spawn"     ; the user's words, typo kept
    static DeadText := "dead"
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
        this._key := "", this._has := false
        this._Reset()
    }

    _Reset() {
        this.msg := "", this.dead := false, this._link := "", this._open := false
        this._lows := 0, this._lowAt := "", this._goneAt := ""
    }

    Spawn(key) {
        key := String(key)
        if (this._has && key == this._key)
            return false
        this._has := true, this._key := key
        this._Reset()
        this._open := true
        link := this._LinkNow()
        if (link = "") {
            this._Log("sinister: no usable private server link - no Discord message")
            return false
        }
        if this._Ghost() {
            this._Log("sinister: ghost server (or not known) - no Discord message")
            return false
        }
        if !IsObject(this._wh)
            return false
        h := ""
        try h := this._wh.PostText(SinisterReport.Event, link " " SinisterReport.SpawnText
            , IsObject(this._hook) ? {hook: this._hook} : "")
        catch Any as e {
            this._Log("sinister: the Discord message failed (" Webhook.ScrubText(e is Error ? e.Message : String(e)) ")")
            return false
        }
        if !IsObject(h) {
            this._Log("sinister: no webhook has the sinister event - no Discord message")
            return false
        }
        this.msg := h, this._link := link
        this._Log("sinister: boss spawn message queued (" h.parts.Length " webhook(s))")
        return true
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
        try this._wh.EditText(this.msg, this._link " " SinisterReport.DeadText)
        catch Any as e {
            this._Log("sinister: the edit failed (" Webhook.ScrubText(e is Error ? e.Message : String(e)) ")")
            return false
        }
        this._Log("sinister: message edited to dead")
        return true
    }

    ; the private server link, "" when unset or not a roblox.com https link
    _LinkNow() {
        link := ""
        try link := Trim(String(this._cfg.Get("General.privateServer", "")))
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
