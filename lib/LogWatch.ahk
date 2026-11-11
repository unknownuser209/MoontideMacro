#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\Json.ahk
; ---------------------------------------------------------------------------
; LogWatch: parse + tail the newest Roblox *_Player_*.log.
;
;   LogWatch.ParseLine(line)  -> Map{biome, aura, ts, hasAura} or ""
;   LogWatch.ParseMerchant(line) -> "Mari" | "Jester" | ""
;   LogWatch.PickLog(dir)     -> full path of newest Player log (not
;                                CrashHandler, not Studio), or ""
;   lw := LogWatch(dir)       dir defaults to %LOCALAPPDATA%\Roblox\logs
;   lw.Poll()                 -> Array of events, each a LogWatchEvent (a Map
;                                with keys type/name/ts/live; ev.type etc. also work):
;       type "biome"    name = largeImage.hoverText (e.g. "SAND STORM")
;       type "aura"     name = aura name; "" = aura removed
;       type "merchant" name = "Mari" | "Jester"
;       type "join"     name = "private" (the join came from the private
;                       server link: launch request "RequestPrivateGame")
;                       | "other" (a game teleport, e.g. Sol's "Player will
;                       automatically rejoin", or a public join): a server
;                       the private server link does not reach
;       ts   = leading ISO timestamp of the log line that caused the event
;              (the dedupe key for consumers: biome name + ts).
;       live = false for the single startup-backfill biome event, true for
;              everything else (see "Startup backfill").
;
; Startup backfill (first successful read since construction):
;   The first read replays up to ~64 KB of old log so the current state is
;   known. It updates CurrentBiome/CurrentAura silently and emits at most ONE
;   event: the biome the log ended in, with live := false (consumers must not
;   alert/trigger potions on it, only record state). No aura or merchant
;   events come from backfill. Every later event has live := true (including
;   events from a newer log file picked up after startup).
;
; Errors: only file I/O (OSError from open/seek/read) is tolerated and retried
;   next Poll. Any other error propagates to the caller; Offset advances only
;   after a chunk was fully processed.
;
; Rules:
;   - Only bytes after the stored offset are read; only complete lines
;     (up to the last LF) are consumed. First open starts ~64 KB from the
;     end so the current biome is known. Offset resets when the picked file
;     changes or shrinks. Current biome/aura persist across files, so a
;     re-read or a new log with the same biome emits nothing.
;   - biome/aura events fire only when the value differs from the previous
;     one. The very first aura "none" is not an event (start state is none).
;   - "In Main Menu" and "Equipped _None_" mean no aura. "In Main Menu"
;     carries no biome either (its image is not a biome).
;   - Merchant lines: a merchant name (case-sensitive whole word) plus an
;     arrival word. Same merchant within MERCHANT_DEDUPE_SEC (by log ts) is
;     one event. Unconfirmed in real logs: edit the constants below.
; ---------------------------------------------------------------------------

class LogWatchEvent extends Map {
    ; Allow ev.type / ev.name / ev.ts as well as ev["type"].
    __Get(name, params) {
        return this[name]
    }
}

class LogWatch {
    ; ---- easy-to-edit constants -------------------------------------------
    static MERCHANTS := ["Mari", "Jester"]                                  ; case-sensitive whole words
    static ARRIVAL_WORDS := ["arrived", "has arrived", "appeared", "spawned"] ; case-insensitive whole words
    static MERCHANT_DEDUPE_SEC := 120
    static NO_AURA_STATES := ["Equipped _None_", "In Main Menu"]
    static MENU_STATE := "In Main Menu"
    static PRIVATE_REQUEST := "RequestPrivateGame"   ; launch request of a private server join
    static TAIL_BYTES := 65536       ; first open: start this far from the end
    static MAX_READ := 1048576       ; bytes per read chunk
    ; a live join waits this long for its GameJoinLoadTime line before it
    ; counts as "other": a read can end between the two lines (live
    ; 2026-11-11: the macro's own private rejoin read as a ghost server and
    ; it rejoined until the limit)
    static JOIN_WAIT_MS := 15000
    static TickFn := () => A_TickCount

    ; ---- instance state ----------------------------------------------------
    Dir := ""
    Path := ""
    Offset := -1                     ; -1 = not started on this file
    CurrentBiome := ""
    CurrentAura := ""
    AuraKnown := false               ; an "Equipped ..." state was read (CurrentAura "" = none, not unknown)
    CurrentJoin := ""                ; "private" | "other" | "" (no join seen in this log)
    _lastReq := ""                   ; requestType of the last launch request, until its join
    _pending := false                ; a join waits for its GameJoinLoadTime line (_JoinLine)
    _pendingAt := 0                  ; TickFn when that join was seen
    _pendingTs := ""
    _joinTs := ""                    ; ts of the last join seen during backfill / the prefix scan
    _skipFirst := false
    _backfilling := true             ; true until the first read completes
    _backfillTs := ""                ; ts of the last biome change seen during backfill
    _merchantSeen := Map()           ; name -> YYYYMMDDHH24MISS of last emitted event

    __New(dir := "") {
        this.Dir := (dir != "") ? RTrim(dir, "\/") : EnvGet("LOCALAPPDATA") "\Roblox\logs"
    }

    ; ---- pure parsing ------------------------------------------------------

    static ParseLine(line) {
        marker := "[BloxstrapRPC] "
        p := InStr(line, marker)
        if !p
            return ""
        payload := Trim(SubStr(line, p + StrLen(marker)), " `t`r`n")
        try {
            obj := Json.Parse(payload)
        } catch {
            return ""
        }
        if !(obj is Map) || !obj.Has("command") || obj["command"] != "SetRichPresence"
            return ""
        data := obj.Has("data") ? obj["data"] : ""
        if !(data is Map)
            return ""
        biome := ""
        if (data.Has("largeImage") && data["largeImage"] is Map && data["largeImage"].Has("hoverText")) {
            hv := data["largeImage"]["hoverText"]
            if (hv is String)
                biome := hv
        }
        aura := ""
        hasAura := false
        if (data.Has("state") && data["state"] is String) {
            hasAura := true
            state := data["state"]
            if (state == LogWatch.MENU_STATE)
                biome := ""
            else if (RegExMatch(state, '^Equipped "(.*)"$', &m))
                aura := m[1]
            ; anything else (incl. "Equipped _None_") = no aura
        }
        r := Map()
        r["biome"] := biome
        r["aura"] := aura
        r["ts"] := LogWatch._Ts(line)
        r["hasAura"] := hasAura
        return r
    }

    ; Merchant name if the line has a merchant word and an arrival word, else "".
    static ParseMerchant(line) {
        best := ""
        bestPos := 0
        for name in LogWatch.MERCHANTS {
            if (RegExMatch(line, "\b" name "\b", &m) && (bestPos = 0 || m.Pos < bestPos)) {
                best := name
                bestPos := m.Pos
            }
        }
        if (best = "")
            return ""
        alt := ""
        for w in LogWatch.ARRIVAL_WORDS
            alt .= (alt = "" ? "" : "|") w
        return RegExMatch(line, "i)\b(?:" alt ")\b") ? best : ""
    }

    static _Ts(line) {
        return RegExMatch(line, "^(\d{4}-\d\d-\d\dT[\d:.]+Z),", &m) ? m[1] : ""
    }

    static PickLog(dir) {
        best := ""
        bestTime := ""
        Loop Files, RTrim(dir, "\/") "\*.log", "F" {
            if (!InStr(A_LoopFileName, "_Player_") || InStr(A_LoopFileName, "CrashHandler"))
                continue
            t := A_LoopFileTimeModified
            if (best = "" || t > bestTime || (t = bestTime && StrCompare(A_LoopFileName, best) > 0)) {
                best := A_LoopFileName
                bestTime := t
            }
        }
        return best = "" ? "" : RTrim(dir, "\/") "\" best
    }

    ; ---- tail --------------------------------------------------------------

    Poll() {
        events := []
        path := LogWatch.PickLog(this.Dir)
        if (path = "")
            return events
        if (path !== this.Path) {
            this.Path := path
            this.Offset := -1
            this.CurrentJoin := "", this._lastReq := "", this._joinTs := ""
        }
        try {
            f := FileOpen(path, "r")
        } catch OSError {
            return events      ; locked/vanished: retry next poll
        }
        try {
            this._ReadNew(f, events)
        } finally {
            f.Close()
        }
        ; a live join whose GameJoinLoadTime line never came: "other" now
        if (!this._backfilling && this._JoinWaitOver() && (kind := this._FlushJoin()) != "")
            events.Push(LogWatch._Ev("join", kind, this._pendingTs, true))
        return events
    }

    _JoinWaitOver() => this._pending && ((LogWatch.TickFn)() - this._pendingAt >= LogWatch.JOIN_WAIT_MS)

    _ReadNew(f, events) {
        try {
            size := f.Length
        } catch OSError {
            return
        }
        backfill := this._backfilling
        if (this.Offset < 0 || this.Offset > size) {
            ; first open on this file, or it was truncated/rewritten
            start := (this.Offset < 0) ? Max(0, size - LogWatch.TAIL_BYTES) : 0
            if (start > 0) {
                ; the join is near the top of a session's log, far above the
                ; tail: find the last one in the part that is skipped
                if (this.Offset < 0 && this._ScanJoins(f, start) && !backfill)
                    events.Push(LogWatch._Ev("join", this.CurrentJoin, this._joinTs, true))
                this.Offset := start - 1   ; read one byte early so a window edge exactly on a line start loses nothing
                this._skipFirst := true
            } else {
                this.Offset := 0
                this._skipFirst := false
            }
        }
        while (this.Offset < size) {
            n := Min(size - this.Offset, LogWatch.MAX_READ)
            buf := Buffer(n)
            try {
                f.Seek(this.Offset, 0)
                got := f.RawRead(buf, n)
            } catch OSError {
                return            ; I/O only: Offset untouched, retry next poll
            }
            last := got
            while (last > 0 && NumGet(buf, last - 1, "UChar") != 10)
                last--
            if (last = 0) {
                if (got < LogWatch.MAX_READ)
                    break             ; incomplete line: wait for the rest
                last := got           ; absurdly long line: consume it
            }
            first := 0
            if this._skipFirst {
                this._skipFirst := false
                while (first < last && NumGet(buf, first, "UChar") != 10)
                    first++
                first++               ; step past the LF itself
                if (first > last)
                    first := last
            }
            text := StrGet(buf.Ptr + first, last - first, "UTF-8")
            this._Process(text, events, backfill)
            this.Offset += last   ; only after the chunk was fully processed
        }
        if backfill {
            this._backfilling := false
            if (this.CurrentBiome != "")
                events.Push(LogWatch._Ev("biome", this.CurrentBiome, this._backfillTs, false))
            if (this.CurrentJoin != "")
                events.Push(LogWatch._Ev("join", this.CurrentJoin, this._joinTs, false))
        }
    }

    ; Join lines in bytes [0, upTo) of f, silently, and the last aura state
    ; there (AuraKnown / CurrentAura): the log grows ~100 KB a minute, so
    ; the tail often has no "Equipped" line, and the aura was unknown until
    ; the game wrote a new one (2026-10-27: the obby skipped itself every
    ; minute). -> true when a join was found.
    _ScanJoins(f, upTo) {
        try {
            buf := Buffer(upTo)
            f.Seek(0, 0)
            got := f.RawRead(buf, upTo)
        } catch OSError {
            return false
        }
        found := false
        aura := "", hasAura := false, biome := "", biomeTs := ""
        Loop Parse, StrGet(buf.Ptr, got, "UTF-8"), "`n" {
            line := RTrim(A_LoopField, "`r")
            if (this._JoinLine(line) != "") {
                found := true
                this._joinTs := LogWatch._Ts(line)
            } else if InStr(line, "[BloxstrapRPC]") {
                r := LogWatch.ParseLine(line)
                if (r is Map && r["hasAura"])
                    aura := r["aura"], hasAura := true
                ; the biome too: rich presence lines come only on a change, so
                ; the tail can hold none for many minutes (2026-10-27 review)
                if (r is Map && r["biome"] != "")
                    biome := r["biome"], biomeTs := r["ts"]
            }
        }
        if (this._FlushJoin() != "") {
            found := true
            this._joinTs := this._pendingTs
        }
        if hasAura {
            this.AuraKnown := true
            this.CurrentAura := aura
        }
        if (biome != "") {
            this.CurrentBiome := biome
            this._backfillTs := biomeTs
        }
        return found
    }

    ; A launch request is remembered; a "Joining game" line -> "private" |
    ; "other" (and CurrentJoin set). Anything else -> "".
    ; Roblox 0.745 warm starts (the macro's own rejoin, 2026-10-27) log no
    ; "requestType" line: the only private marker is the GameJoinLoadTime
    ; line right after the join, "referral_page:RequestPrivateGame" (a
    ; teleport has "referral_page:" empty). So a join without a private
    ; request waits for that line; _FlushJoin ends the wait as "other".
    ; Before this every such rejoin read as a ghost server.
    _JoinLine(line) {
        if InStr(line, '"requestType":"') {
            if RegExMatch(line, '"requestType":"(\w+)"', &m)
                this._lastReq := m[1]
            return ""
        }
        if InStr(line, "! Joining game ") {
            if (this._lastReq == LogWatch.PRIVATE_REQUEST) {
                this._lastReq := "", this._pending := false
                this.CurrentJoin := "private"
                return "private"
            }
            this._lastReq := ""
            this._pending := true, this._pendingTs := LogWatch._Ts(line), this._pendingAt := (LogWatch.TickFn)()
            return ""
        }
        if (this._pending && InStr(line, "[FLog::GameJoinLoadTime]")) {
            this._pending := false
            this.CurrentJoin := InStr(line, "referral_page:" LogWatch.PRIVATE_REQUEST) ? "private" : "other"
            return this.CurrentJoin
        }
        return ""
    }

    ; A join still waiting for its GameJoinLoadTime line -> "other" (and
    ; CurrentJoin set), else "".
    _FlushJoin() {
        if !this._pending
            return ""
        this._pending := false
        this.CurrentJoin := "other"
        return "other"
    }

    _Process(text, events, backfill) {
        Loop Parse, text, "`n" {
            line := RTrim(A_LoopField, "`r")
            if (line = "")
                continue
            if ((kind := this._JoinLine(line)) != "") {
                if backfill
                    this._joinTs := LogWatch._Ts(line)
                else
                    events.Push(LogWatch._Ev("join", kind, LogWatch._Ts(line), true))
                continue
            }
            if InStr(line, "[BloxstrapRPC]") {
                r := LogWatch.ParseLine(line)
                if (r is Map) {
                    if (r["biome"] != "" && r["biome"] !== this.CurrentBiome) {
                        this.CurrentBiome := r["biome"]
                        if backfill
                            this._backfillTs := r["ts"]
                        else
                            events.Push(LogWatch._Ev("biome", r["biome"], r["ts"], true))
                    }
                    if r["hasAura"]
                        this.AuraKnown := true
                    if (r["hasAura"] && r["aura"] !== this.CurrentAura) {
                        this.CurrentAura := r["aura"]
                        if !backfill
                            events.Push(LogWatch._Ev("aura", r["aura"], r["ts"], true))
                    }
                }
            }
            if (!backfill && (InStr(line, "Mari") || InStr(line, "Jester"))) {
                who := LogWatch.ParseMerchant(line)
                if (who != "")
                    this._Merchant(who, LogWatch._Ts(line), events)
            }
        }
        ; the GameJoinLoadTime line is written with the join: one missing by
        ; the end of the chunk is not coming (older logs): a plain join. Live,
        ; it may still be on its way: only after JOIN_WAIT_MS (Poll flushes)
        if ((backfill || this._JoinWaitOver()) && (kind := this._FlushJoin()) != "") {
            if backfill
                this._joinTs := this._pendingTs
            else
                events.Push(LogWatch._Ev("join", kind, this._pendingTs, true))
        }
    }

    _Merchant(who, ts, events) {
        stamp := ""
        if RegExMatch(ts, "^(\d{4})-(\d\d)-(\d\d)T(\d\d):(\d\d):(\d\d)", &m)
            stamp := m[1] m[2] m[3] m[4] m[5] m[6]
        if (stamp != "" && this._merchantSeen.Has(who)) {
            if (Abs(DateDiff(stamp, this._merchantSeen[who], "Seconds")) < LogWatch.MERCHANT_DEDUPE_SEC)
                return
        }
        if (stamp != "")
            this._merchantSeen[who] := stamp
        events.Push(LogWatch._Ev("merchant", who, ts, true))
    }

    static _Ev(type, name, ts, live) {
        ev := LogWatchEvent()
        ev["type"] := type
        ev["name"] := name
        ev["ts"] := ts
        ev["live"] := live
        return ev
    }
}

; ---------------------------------------------------------------------------
; RespawnTail: tells a respawn of the player's character from the log, for the
; Minions fight. The game's skill script prints one line per skill when it
; binds them to a new character:
;   ...,Info [FLog::CreatorOutput] Taunt function: 0x1af0... false Enum.KeyCode.T Enum.KeyCode.ButtonL1
; Measured over the fights of loops L22..L26 (2026-11-05): each of the 9
; deaths the macro saw has such lines within 1.5 s, and 12 more came with no
; death seen, among them SNOWY 22:14:56 and the fall in the L26 clip 22:41:59
; (in its black frame). A cast only writes Begin / End lines, a menu Cancel
; lines. The game's own reset (Input.ResetToSpawn) and a new aura print them
; too: Sync after those.
;
;   t := RespawnTail(dir)   dir as LogWatch
;   t.Sync()                from the end of the newest log on (a fight's start)
;   t.Poll()                -> true when a respawn was written since (read
;                           from the file Sync picked; false when none, before
;                           any Sync, or when the file cannot be read)
;   t.Seen                  true once a Poll found such a line: this log has
;                           shown it tells respawns. Sync keeps it; the owner
;                           clears it when another aura goes on (only Eden's
;                           and Equinox's lines are measured, a silent aura
;                           or log must not count as "no respawn")
;   RespawnTail.IsRespawn(text)  -> true when text has such a line
; ---------------------------------------------------------------------------
class RespawnTail {
    static LINE := "\[FLog::CreatorOutput\] [^\r\n]* function: 0x[0-9a-fA-F]+ \w+ Enum\.KeyCode\."
    Dir := ""
    Path := ""
    Offset := -1
    Seen := false
    _f := ""                      ; the log, kept open: Poll runs every tick, and an
                                  ; open + close of it cost 29 ms (live 2026-11-06)

    __New(dir := "") {
        this.Dir := (dir != "") ? RTrim(dir, "\/") : EnvGet("LOCALAPPDATA") "\Roblox\logs"
    }

    __Delete() => this._Close()

    _Close() {
        if IsObject(this._f)
            try this._f.Close()
        this._f := ""
    }

    static IsRespawn(text) => RegExMatch(text, RespawnTail.LINE) > 0

    Sync() {
        this._Close()
        this.Path := LogWatch.PickLog(this.Dir), this.Offset := -1
        if (this.Path != "")
            try this.Offset := FileGetSize(this.Path)
    }

    ; Roblox writes a newer log now (a rejoin, a restart).
    Stale() => this.Path != LogWatch.PickLog(this.Dir)

    Poll() {
        if (this.Offset < 0)
            return false
        try {
            if !IsObject(this._f)
                this._f := FileOpen(this.Path, 0x700)      ; read, all shared
            return this._Read(this._f)
        } catch OSError {
            this._Close()
            return false
        }
    }

    ; the whole lines written after Offset
    _Read(f) {
        size := f.Length
        if (size < this.Offset)
            this.Offset := size
        found := false
        while (this.Offset < size) {
            n := Min(size - this.Offset, LogWatch.MAX_READ)
            buf := Buffer(n)
            f.Seek(this.Offset, 0)
            got := f.RawRead(buf, n)
            last := got
            while (last > 0 && NumGet(buf, last - 1, "UChar") != 10)
                last--
            if (last = 0) {
                if (got < LogWatch.MAX_READ)
                    break                 ; a line still being written
                last := got
            }
            found := RespawnTail.IsRespawn(StrGet(buf.Ptr, last, "UTF-8")) || found
            this.Offset += last
        }
        this.Seen := this.Seen || found
        return found
    }
}
