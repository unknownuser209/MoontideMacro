#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\..\..\Ocr.ahk
; ---------------------------------------------------------------------------
; ClockWatch (2026-11-17, the owner): the Sinister bosses seen without the
; chat. In PUMPKIN MOON (Sinister P.) and GRAVEYARD (Sinister S.) the game's
; clock under the biome name ("NIGHTTIME (21 : 28)", bottom left) stops while
; the boss is alive and runs again once it is dead or gone. The clock runs
; ~5 game minutes a second (live), so the same time read for PauseMs is a
; stop.
;
;   cw := ClockWatch(deps)   deps (all optional): read () -> the HUD text,
;                            now () -> ms, report (SinisterReport-like:
;                            Spawn(key, boss), Killed(why)), log (text),
;                            disc () -> true when a disconnect / rejoin
;                            screen shows (default: one read of the screen
;                            centre, made only when the clock looks stopped)
;   cw.Tick(biome)           call often (the App's service tick): reads at
;                            most every ReadMs, only in the two biomes
;   ClockWatch.Parse(text)   "HH:MM" from the read ("" = none), the game
;                            font's O / B / l read as 0 / 8 / 1
; ---------------------------------------------------------------------------
class ClockWatch {
    static Bosses := Map("PUMPKIN MOON", "p", "GRAVEYARD", "s")
    static ReadMs := 2000
    static PauseMs := 8000       ; the same time this long (3+ reads): stopped
    static Rect := {x: 0, y: 1200, w: 420, h: 80, scale: 2}
    ; Roblox's disconnect screen (RecoveryTask.DiscBox / DiscRe) and the
    ; game's "will automatically rejoin" notice
    static DiscBox := {x: 780, y: 420, w: 1000, h: 560}
    static DiscRe := "i)\bdisconnected\b|lost connection|error code|\bkicked\b|shut ?down|shutting down|rejoin|reconnect"

    __New(deps := "") {
        g := (k, def) => (IsObject(deps) && deps.HasOwnProp(k)) ? deps.%k% : def
        r := ClockWatch.Rect
        this._read := g("read", () => Ocr.Read(r.x, r.y, r.w, r.h, r.scale))
        this._now := g("now", () => A_TickCount)
        this._rep := g("report", "")
        this._logFn := g("log", "")
        d := ClockWatch.DiscBox
        this._disc := g("disc", () => RegExMatch(Ocr.Read(d.x, d.y, d.w, d.h), ClockWatch.DiscRe) > 0)
        this._Reset("")
    }

    _Reset(biome) {
        this._biome := biome, this._last := "", this._since := 0, this._same := 0
        this._readAt := "", this._paused := false, this._key := ""
    }

    Tick(biome) {
        biome := StrUpper(Trim(String(biome)))
        if (biome != this._biome)
            this._Reset(biome)
        if !ClockWatch.Bosses.Has(biome)
            return
        now := (this._now)()
        if (this._readAt != "" && now - this._readAt < ClockWatch.ReadMs)
            return
        this._readAt := now
        t := ""
        try t := ClockWatch.Parse((this._read)())
        if (t = "")
            return                          ; covered or misread: no verdict
        boss := ClockWatch.Bosses[biome]
        if (t != this._last) {
            if this._paused {
                this._paused := false
                this._Log("clock: the " biome " clock runs again: Sinister " StrUpper(boss) ". is dead or gone")
                if IsObject(this._rep)
                    try this._rep.Killed("the " biome " clock ran again")
            }
            this._last := t, this._since := now, this._same := 1
            return
        }
        this._same++
        if (!this._paused && this._same >= 3 && now - this._since >= ClockWatch.PauseMs) {
            ; a disconnect (or "will automatically rejoin") freezes the clock
            ; too: no boss card for that, looked at again a while later
            disc := false
            try disc := (this._disc)() ? true : false
            if disc {
                this._Log("clock: the " biome " clock stopped at " t ", but a disconnect screen shows: no boss message")
                this._since := now, this._same := 1
                return
            }
            this._paused := true
            this._key := "clock:" boss ":" now
            this._Log("clock: the " biome " clock stopped at " t ": Sinister " StrUpper(boss) ". spawned")
            if IsObject(this._rep)
                try this._rep.Spawn(this._key, boss)
        }
    }

    Paused => this._paused

    static Parse(text) {
        if !RegExMatch(String(text), "\(\s*(\S{2})\s*:\s*(\S{2})\s*\)", &m)
            return ""
        fix := (s) => StrReplace(StrReplace(StrReplace(StrReplace(StrReplace(StrReplace(StrReplace(s
            , "O", "0"), "o", "0"), "B", "8"), "l", "1"), "I", "1"), "|", "1"), "S", "5")
        h := fix(m[1]), mi := fix(m[2])
        if !(RegExMatch(h, "^\d\d$") && RegExMatch(mi, "^\d\d$") && h + 0 < 24 && mi + 0 < 60)
            return ""
        return h ":" mi
    }

    _Log(t) {
        if IsObject(this._logFn)
            try this._logFn.Call(t)
    }
}
