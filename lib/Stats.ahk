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
;   s.AllTime()            Map copy of the all-time totals: every Add() and
;                          the run time, never pruned (runMs includes the
;                          running session's time)
;   s.Since()              yyyyMMdd of the first day the totals hold ("" =
;                          nothing counted yet)
;   s.Save()               write JSON (only the last 30 days), atomic. While
;                          a session runs it first books the time so far, so
;                          a crash loses at most one Save interval.
;   s.Load()               read the file; missing / corrupt = empty, no throw.
;                          A file from before the all-time totals seeds them
;                          once from the days it still keeps (since = the
;                          oldest of them).
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
        this._all := Map()       ; all-time totals (never pruned)
        this._since := ""        ; yyyyMMdd: first day in the totals
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
        this._AllAdd(key, n, this._Today())
    }

    _AllAdd(key, n, ymd) {
        this._all[key] := (this._all.Has(key) ? this._all[key] : 0) + n
        if (this._since = "" || ymd < this._since)
            this._since := ymd
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
            this._AllAdd("runMs", ms, ymd)
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

    AllTime() {
        out := Map()
        for k, v in this._all
            out[k] := v
        if this._running {
            t := 0
            for _, ms in DailyStats._Split(this._segStart, this._Now())
                t += ms
            out["runMs"] := (out.Has("runMs") ? out["runMs"] : 0) + t
        }
        return out
    }

    Since() => this._since

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
            all := Map()
            for k, v in this._all
                all[k] := v
            text := Json.Stringify(Map("days", days, "allTime", all, "since", this._since))
            DirCreate(RegExReplace(this.path, "\\[^\\]*$"))
            ; a file Load could not read is kept as .bad before it is
            ; replaced (the all-time totals are never rebuilt from anything)
            if (this.HasOwnProp("_badFile") && this._badFile) {
                if FileExist(this.path)
                    FileCopy(this.path, this.path ".bad", 1)
                this._badFile := false
            }
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
        this._all := Map()
        this._since := ""
        this._badFile := false
        try {
            if !FileExist(this.path)
                return
            text := "", read := false
            Loop 3 {                        ; a scanner holding the file for a moment
                try {
                    text := FileRead(this.path, "UTF-8"), read := true
                    break
                }
                Sleep(100)
            }
            if !read
                throw Error("stats file unreadable")
            root := Json.Parse(text)
            if !(root is Map) || !root.Has("days") || !(root["days"] is Map) {
                this._badFile := true       ; kept as .bad before the next Save replaces it
                return
            }
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
            if (root.Has("allTime") && root["allTime"] is Map) {
                for k, v in root["allTime"] {
                    if (v is Integer || v is Float)
                        this._all[String(k)] := v
                }
                if (root.Has("since") && RegExMatch(String(root["since"]), "^\d{8}$"))
                    this._since := String(root["since"])
            } else {
                ; older file: seed the totals once from the days it keeps
                for ymd, d in this._days {
                    for k, v in d
                        this._AllAdd(k, v, ymd)
                }
            }
            this._Prune()
        } catch {
            this._days := Map()
            this._all := Map()
            this._since := ""
            this._badFile := true           ; kept as .bad before the next Save replaces it
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
