#Requires AutoHotkey v2.0
; ---------------------------------------------------------------------------
; RunSchedule: decides when the macro should start / stop; the app acts.
;
; Config keys (read live from cfg.Get each tick):
;   Schedule.enabled  0
;   Schedule.start    "22:00"   (HH:mm local; a bad value = the default)
;   Schedule.end      "08:00"   start = end means all day; start > end is an
;                               overnight window
;   Schedule.maxHours 0         0 = no limit
;
;   r := RunSchedule(cfg)
;   r.Tick(nowStamp, running, runMs) -> "start" | "stop" | ""
;       Everything needs Schedule.enabled = 1.
;       "stop"  running and runMs >= maxHours (any start, manual too), or
;               outside the window and the run was started by the schedule
;               (a manual start outside the window is left alone).
;       "start" inside the window, not running, and this window has not been
;               used yet. Once per window: a stop inside the window (yours,
;               or the schedule's) means no new start until the next window.
;   r.NoteStart(bySchedule)   call after any run starts
;   r.NoteStop()              call after any run stops
;   RunSchedule.InWindow(start, end, hhmm) -> true / false
;   RunSchedule.ValidTime(s)  -> "HH:mm" (zero padded) or "" when bad
;   RunSchedule.Describe(cfg) -> "Runs 22:00 to 08:00, stops after 6 h" / "Off"
; Pure logic, no UI, no input.
; ---------------------------------------------------------------------------

class RunSchedule {
    static DefaultStart := "22:00"
    static DefaultEnd := "08:00"

    __New(cfg) {
        this.cfg := cfg
        this._now := ""
        this._bySchedule := false
        this._usedKey := ""
    }

    static ValidTime(s) {
        if !RegExMatch(Trim(String(s)), "^(\d{1,2}):(\d{2})$", &m)
            return ""
        h := Integer(m[1])
        mi := Integer(m[2])
        if (h > 23 || mi > 59)
            return ""
        return Format("{:02}:{:02}", h, mi)
    }

    static InWindow(start, end, hhmm) {
        s := RunSchedule.ValidTime(start)
        e := RunSchedule.ValidTime(end)
        t := RunSchedule.ValidTime(hhmm)
        if (s = "")
            s := RunSchedule.DefaultStart
        if (e = "")
            e := RunSchedule.DefaultEnd
        if (t = "")
            return false
        s := RunSchedule.Mins(s), e := RunSchedule.Mins(e), t := RunSchedule.Mins(t)
        if (s = e)
            return true
        if (s < e)
            return t >= s && t < e
        return t >= s || t < e
    }

    ; "HH:mm" -> minutes since midnight (compares as numbers, not text)
    static Mins(hhmm) => Integer(SubStr(hhmm, 1, 2)) * 60 + Integer(SubStr(hhmm, 4, 2))

    _Times() {
        s := RunSchedule.ValidTime(this.cfg.Get("Schedule.start", RunSchedule.DefaultStart))
        e := RunSchedule.ValidTime(this.cfg.Get("Schedule.end", RunSchedule.DefaultEnd))
        return [s = "" ? RunSchedule.DefaultStart : s, e = "" ? RunSchedule.DefaultEnd : e]
    }

    ; Identifies the window a stamp is in: the date the window began.
    _WindowKey(stamp) {
        tm := this._Times()
        if (tm[1] = tm[2])
            return "all"
        hhmm := SubStr(stamp, 9, 2) ":" SubStr(stamp, 11, 2)
        if (RunSchedule.Mins(tm[1]) > RunSchedule.Mins(tm[2]) && RunSchedule.Mins(hhmm) < RunSchedule.Mins(tm[2]))
            return SubStr(DateAdd(SubStr(stamp, 1, 8) "000000", -1, "Days"), 1, 8)
        return SubStr(stamp, 1, 8)
    }

    _InWindow(stamp) {
        tm := this._Times()
        return RunSchedule.InWindow(tm[1], tm[2], SubStr(stamp, 9, 2) ":" SubStr(stamp, 11, 2))
    }

    _Enabled() => Integer(this.cfg.Get("Schedule.enabled", 0)) = 1

    _MaxHours() {
        v := this.cfg.Get("Schedule.maxHours", 0)
        return IsNumber(v) ? Max(0, v + 0) : 0
    }

    Tick(nowStamp, running, runMs) {
        nowStamp := String(nowStamp)
        this._now := nowStamp
        if !this._Enabled()
            return ""
        mh := this._MaxHours()
        if (running && mh > 0 && runMs >= mh * 3600000)
            return "stop"
        inWin := this._InWindow(nowStamp)
        if running
            return (!inWin && this._bySchedule) ? "stop" : ""
        if (inWin && this._WindowKey(nowStamp) != this._usedKey)
            return "start"
        return ""
    }

    NoteStart(bySchedule) {
        this._bySchedule := bySchedule ? true : false
        if (bySchedule && this._now != "")
            this._usedKey := this._WindowKey(this._now)
    }

    NoteStop() {
        if (this._now != "" && this._InWindow(this._now))
            this._usedKey := this._WindowKey(this._now)
        this._bySchedule := false
    }

    static Describe(cfg) {
        if (Integer(cfg.Get("Schedule.enabled", 0)) != 1)
            return "Off"
        s := RunSchedule.ValidTime(cfg.Get("Schedule.start", RunSchedule.DefaultStart))
        e := RunSchedule.ValidTime(cfg.Get("Schedule.end", RunSchedule.DefaultEnd))
        if (s = "")
            s := RunSchedule.DefaultStart
        if (e = "")
            e := RunSchedule.DefaultEnd
        txt := (s = e) ? "Runs all day" : "Runs " s " to " e
        v := cfg.Get("Schedule.maxHours", 0)
        mh := IsNumber(v) ? Max(0, v + 0) : 0
        if (mh > 0)
            txt .= ", stops after " (mh = Integer(mh) ? Integer(mh) : Round(mh, 1)) " h"
        return txt
    }
}
