#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\Json.ahk
; ---------------------------------------------------------------------------
; DailyStats: persistent per-day counters next to the session ones.
; Keys are free-form strings (fishCaught, fishFailed, falseBites, sells,
; repaths, loops, biomes, rareBiomes, rareAuras, rejoins, runs.<task>, ...).
; "runMs" is the time the macro ran, kept by StartSession / StopSession.
;
;   s := DailyStats(path := "", nowFn := "")
;       path   default <repo>\data\stats.json
;       nowFn  () -> yyyyMMddHHmmss stamp (default A_Now; tests inject it)
;   s.Add(key, n := 1)     adds to today's counters and the session ones
;   s.StartSession()       resets the session counters, remembers the start
;   s.StopSession()        adds the run time to the day(s) as "runMs"; a run
;                          over midnight is split between the two days
;   s.RunMs()              ms this session has run so far
;   s.Day(ymd := "")       Map copy of a day (today by default); runMs
;                          includes the running session's time
;   s.Session()            Map copy of the session counters (incl runMs)
;   s.Save()               write JSON (only the last 30 days), atomic. While
;                          a session runs it first books the time so far, so
;                          a crash loses at most one Save interval.
;   s.Load()               read the file; missing / corrupt = empty, no throw
;   DailyStats.Derived(m) -> Map(fishPerHour, reelRate, uptimeText)
;       fishPerHour  fishCaught per run hour (0 when runMs < 60000)
;       reelRate     percent, fishCaught / (fishCaught + fishFailed);
;                    "" when there were no attempts
;       uptimeText   "3h 05m"
; Never throws on file errors, never shows UI. Times have 1 s resolution.
; ---------------------------------------------------------------------------

class DailyStats {
    static KeepDays := 30

    __New(path := "", nowFn := "") {
        this.path := (path != "") ? path : DailyStats.DefaultPath()
        this._nowFn := nowFn
        this._days := Map()
        this._sess := Map()
        this._running := false
        this._segStart := ""     ; stamp: start of the part not yet booked
        this._sessMs := 0        ; booked ms of this session
    }

    static DefaultPath() => RegExReplace(A_LineFile, "\\[^\\]*\\[^\\]*$") "\data\stats.json"

    _Now() {
        if IsObject(this._nowFn) {
            s := String(this._nowFn.Call())
            if RegExMatch(s, "^\d{14}$")
                return s
        }
        return A_Now
    }

    _Today() => SubStr(this._Now(), 1, 8)

    _DayMap(ymd) {
        if !this._days.Has(ymd)
            this._days[ymd] := Map()
        return this._days[ymd]
    }

    Add(key, n := 1) {
        key := String(key)
        if (key = "")
            return
        d := this._DayMap(this._Today())
        d[key] := (d.Has(key) ? d[key] : 0) + n
        this._sess[key] := (this._sess.Has(key) ? this._sess[key] : 0) + n
    }

    ; ---- run time ------------------------------------------------------------

    ; ms of [from, to] per local day -> Map(ymd -> ms)
    static _Split(from, to) {
        out := Map()
        cur := from
        if (to <= from)
            return out
        while (SubStr(cur, 1, 8) < SubStr(to, 1, 8)) {
            nextMid := DateAdd(SubStr(cur, 1, 8) "000000", 1, "Days")
            out[SubStr(cur, 1, 8)] := DateDiff(nextMid, cur, "Seconds") * 1000
            cur := nextMid
        }
        day := SubStr(cur, 1, 8)
        out[day] := (out.Has(day) ? out[day] : 0) + DateDiff(to, cur, "Seconds") * 1000
        return out
    }

    ; Book the time since _segStart into the days and the session total.
    _Book(now) {
        if !this._running
            return
        for ymd, ms in DailyStats._Split(this._segStart, now) {
            d := this._DayMap(ymd)
            d["runMs"] := (d.Has("runMs") ? d["runMs"] : 0) + ms
            this._sessMs += ms
        }
        this._segStart := now
    }

    StartSession() {
        now := this._Now()
        this._Book(now)
        this._sess := Map()
        this._sessMs := 0
        this._running := true
        this._segStart := now
    }

    StopSession() {
        if !this._running
            return
        this._Book(this._Now())
        this._running := false
        this._segStart := ""
    }

    RunMs() {
        if !this._running
            return this._sessMs
        t := 0
        for _, ms in DailyStats._Split(this._segStart, this._Now())
            t += ms
        return this._sessMs + t
    }

    ; ---- reads ---------------------------------------------------------------

    Day(ymd := "") {
        if (ymd = "")
            ymd := this._Today()
        out := Map()
        if this._days.Has(ymd) {
            for k, v in this._days[ymd]
                out[k] := v
        }
        if this._running {
            live := DailyStats._Split(this._segStart, this._Now())
            if live.Has(ymd)
                out["runMs"] := (out.Has("runMs") ? out["runMs"] : 0) + live[ymd]
        }
        return out
    }

    Session() {
        out := Map()
        for k, v in this._sess
            out[k] := v
        out["runMs"] := this.RunMs()
        return out
    }

    ; ---- save / load ---------------------------------------------------------

    _Prune() {
        keys := []
        for k, _ in this._days
            keys.Push(k)
        if (keys.Length <= DailyStats.KeepDays)
            return
        ; Map enumeration is key-sorted, so the oldest days come first.
        loop keys.Length - DailyStats.KeepDays
            this._days.Delete(keys[A_Index])
    }

    Save() {
        try {
            this._Book(this._Now())
            this._Prune()
            days := Map()
            for ymd, m in this._days {
                o := Map()
                for k, v in m
                    o[k] := v
                days[ymd] := o
            }
            text := Json.Stringify(Map("days", days))
            DirCreate(RegExReplace(this.path, "\\[^\\]*$"))
            tmp := this.path ".tmp"
            try FileDelete(tmp)
            FileAppend(text, tmp, "UTF-8-RAW")
            FileMove(tmp, this.path, 1)
            return true
        } catch
            return false
    }

    Load() {
        this._days := Map()
        try {
            if !FileExist(this.path)
                return
            root := Json.Parse(FileRead(this.path, "UTF-8"))
            if !(root is Map) || !root.Has("days") || !(root["days"] is Map)
                return
            for ymd, m in root["days"] {
                if !RegExMatch(ymd, "^\d{8}$") || !(m is Map)
                    continue
                d := Map()
                for k, v in m {
                    if (v is Integer || v is Float)
                        d[String(k)] := v
                }
                this._days[ymd] := d
            }
            this._Prune()
        } catch {
            this._days := Map()
        }
    }

    ; ---- derived numbers -----------------------------------------------------

    static Derived(m) {
        caught := m.Has("fishCaught") ? m["fishCaught"] : 0
        failed := m.Has("fishFailed") ? m["fishFailed"] : 0
        ms := m.Has("runMs") ? m["runMs"] : 0
        out := Map()
        out["fishPerHour"] := (ms < 60000) ? 0 : Number(Round(caught / (ms / 3600000), 1))
        out["reelRate"] := (caught + failed > 0) ? Round(caught * 100 / (caught + failed)) : ""
        mins := ms // 60000
        out["uptimeText"] := (mins // 60) "h " Format("{:02}", Mod(mins, 60)) "m"
        return out
    }
}
