#Requires AutoHotkey v2.0
; Tests for lib\Stats.ahk, lib\Schedule.ahk and lib\DailySummary.ahk. Offline;
; files live in a temp dir under A_Temp, never the repo.
#Include ..\lib\Stats.ahk
#Include ..\lib\Schedule.ahk
#Include ..\lib\DailySummary.ahk

; ---- helpers (names must not start with Test_) -----------------------------

class StatFakeCfg {
    __New(m := "") {
        this.m := (m is Map) ? m : Map()
    }
    Get(path, default := "") => this.m.Has(path) ? this.m[path] : default
}

class StatClock {
    __New(stamp) {
        this.t := stamp
    }
    Now() => this.t
    Set(stamp) {
        this.t := stamp
    }
}

StatTmpPath() {
    d := A_Temp "\vesper_stattest_" A_TickCount "_" Random(100000, 999999)
    DirCreate(d)
    return d "\stats.json"
}

StatNew(clock, path := "") => DailyStats(path, () => clock.Now())

; ---- DailyStats ------------------------------------------------------------

Test_Stats_add_day_and_session() {
    c := StatClock("20261112100000")
    s := StatNew(c)
    s.Add("fishCaught")
    s.Add("fishCaught", 4)
    s.Add("runs.fishing", 2)
    AssertEq(s.Day()["fishCaught"], 5, "day total")
    AssertEq(s.Session()["fishCaught"], 5, "session total")
    AssertEq(s.Day("20261112")["runs.fishing"], 2, "day by ymd")
    AssertEq(s.Day("20261111").Count, 0, "other day empty")
    s.StartSession()
    AssertEq(s.Session().Has("fishCaught"), false, "session reset")
    AssertEq(s.Day()["fishCaught"], 5, "day kept")
    c.Set("20261113000100")
    s.Add("fishCaught")
    AssertEq(s.Day("20261113")["fishCaught"], 1, "new day")
    AssertEq(s.Day("20261112")["fishCaught"], 5, "old day untouched")
}

Test_Stats_runms_and_midnight() {
    c := StatClock("20261112100000")
    s := StatNew(c)
    s.StartSession()
    c.Set("20261112103000")
    AssertEq(s.RunMs(), 1800000, "running ms")
    AssertEq(s.Day()["runMs"], 1800000, "day live runMs")
    AssertEq(s.Session()["runMs"], 1800000, "session runMs")
    s.StopSession()
    AssertEq(s.Day()["runMs"], 1800000, "booked on stop")
    c.Set("20261112233000")
    s.StartSession()
    c.Set("20261113003000")
    s.StopSession()
    AssertEq(s.Day("20261112")["runMs"], 1800000 + 1800000, "before midnight part")
    AssertEq(s.Day("20261113")["runMs"], 1800000, "after midnight part")
    AssertEq(s.RunMs(), 3600000, "session total after stop")
    s.StopSession()
    AssertEq(s.Day("20261113")["runMs"], 1800000, "second stop is a no-op")
}

Test_Stats_save_load_roundtrip() {
    p := StatTmpPath()
    c := StatClock("20261112100000")
    s := StatNew(c, p)
    s.StartSession()
    s.Add("fishCaught", 7)
    c.Set("20261112110000")
    AssertTrue(s.Save(), "save ok")
    AssertTrue(!FileExist(p ".tmp"), "temp file gone")
    c.Set("20261112120000")
    s.StopSession()
    AssertEq(s.Day()["runMs"], 7200000, "no double count after save")
    s.Save()
    t := StatNew(c, p)
    t.Load()
    AssertEq(t.Day()["fishCaught"], 7, "loaded counter")
    AssertEq(t.Day()["runMs"], 7200000, "loaded runMs")
}

Test_Stats_load_bad_files() {
    p := StatTmpPath()
    c := StatClock("20261112100000")
    s := StatNew(c, p)
    s.Load()
    AssertEq(s.Day().Count, 0, "missing file")
    FileAppend("{not json", p, "UTF-8-RAW")
    s.Load()
    AssertEq(s.Day().Count, 0, "corrupt file")
    FileDelete(p)
    FileAppend('{"days": [1, 2]}', p, "UTF-8-RAW")
    s.Load()
    AssertEq(s.Day().Count, 0, "wrong shape")
    FileDelete(p)
    FileAppend('{"days": {"20261112": {"fishCaught": 3, "bad": "x"}, "oops": {"a": 1}}}', p, "UTF-8-RAW")
    s.Load()
    AssertEq(s.Day()["fishCaught"], 3, "good part kept")
    AssertEq(s.Day().Has("bad"), false, "non-numbers dropped")
}

Test_Stats_keeps_30_days() {
    p := StatTmpPath()
    c := StatClock("20261001100000")
    s := StatNew(c, p)
    loop 40 {
        c.Set(SubStr(DateAdd("20261001100000", A_Index - 1, "Days"), 1, 14))
        s.Add("loops")
    }
    s.Save()
    t := StatNew(c, p)
    t.Load()
    AssertEq(t.Day("20261001").Count, 0, "oldest dropped")
    AssertEq(t.Day("20261010").Count, 0, "10th dropped")
    AssertEq(t.Day("20261011")["loops"], 1, "30th newest kept")
    AssertEq(t.Day("20261109")["loops"], 1, "newest kept")
}

Test_Stats_derived() {
    d := DailyStats.Derived(Map("fishCaught", 90, "fishFailed", 10, "runMs", 3 * 3600000 + 5 * 60000))
    AssertEq(d["reelRate"], 90, "reel rate")
    AssertEq(d["uptimeText"], "3h 05m", "uptime")
    AssertEq(d["fishPerHour"], 29.2, "fish per hour")
    e := DailyStats.Derived(Map("fishCaught", 5, "runMs", 59000))
    AssertEq(e["fishPerHour"], 0, "short run")
    AssertEq(e["reelRate"], 100, "no fails")
    AssertEq(DailyStats.Derived(Map())["reelRate"], "", "no attempts")
    AssertEq(DailyStats.Derived(Map())["uptimeText"], "0h 00m", "empty uptime")
}

; ---- RunSchedule -----------------------------------------------------------

Test_Schedule_helpers() {
    AssertEq(RunSchedule.ValidTime("7:05"), "07:05", "pad")
    AssertEq(RunSchedule.ValidTime("24:00"), "", "hour range")
    AssertEq(RunSchedule.ValidTime("12:60"), "", "minute range")
    AssertEq(RunSchedule.ValidTime("abc"), "", "junk")
    AssertTrue(RunSchedule.InWindow("22:00", "08:00", "23:30"), "overnight evening")
    AssertTrue(RunSchedule.InWindow("22:00", "08:00", "03:00"), "overnight morning")
    AssertTrue(!RunSchedule.InWindow("22:00", "08:00", "08:00"), "end exclusive")
    AssertTrue(!RunSchedule.InWindow("22:00", "08:00", "12:00"), "overnight day")
    AssertTrue(RunSchedule.InWindow("09:00", "17:00", "09:00"), "day window start")
    AssertTrue(!RunSchedule.InWindow("09:00", "17:00", "17:00"), "day window end")
    AssertTrue(RunSchedule.InWindow("06:00", "06:00", "13:00"), "all day")
}

Test_Schedule_describe() {
    AssertEq(RunSchedule.Describe(StatFakeCfg()), "Off", "off")
    c := StatFakeCfg(Map("Schedule.enabled", 1, "Schedule.maxHours", 6))
    AssertEq(RunSchedule.Describe(c), "Runs 22:00 to 08:00, stops after 6 h", "default window")
    c := StatFakeCfg(Map("Schedule.enabled", 1, "Schedule.start", "9:00", "Schedule.end", "17:30"))
    AssertEq(RunSchedule.Describe(c), "Runs 09:00 to 17:30", "no limit")
    c := StatFakeCfg(Map("Schedule.enabled", 1, "Schedule.start", "x", "Schedule.end", "08:00", "Schedule.maxHours", 1.5))
    AssertEq(RunSchedule.Describe(c), "Runs 22:00 to 08:00, stops after 1.5 h", "bad time falls back")
}

Test_Schedule_overnight_cycle() {
    cfg := StatFakeCfg(Map("Schedule.enabled", 1))
    r := RunSchedule(cfg)
    AssertEq(r.Tick("20261112200000", false, 0), "", "before window")
    AssertEq(r.Tick("20261112220000", false, 0), "start", "window opens")
    r.NoteStart(true)
    AssertEq(r.Tick("20261112230000", true, 3600000), "", "running inside")
    AssertEq(r.Tick("20261113030000", true, 5 * 3600000), "", "after midnight")
    AssertEq(r.Tick("20261113080000", true, 10 * 3600000), "stop", "window closes")
    r.NoteStop()
    AssertEq(r.Tick("20261113080100", false, 0), "", "outside")
    AssertEq(r.Tick("20261113220000", false, 0), "start", "next window")
}

Test_Schedule_once_per_window() {
    cfg := StatFakeCfg(Map("Schedule.enabled", 1))
    r := RunSchedule(cfg)
    AssertEq(r.Tick("20261112220000", false, 0), "start", "first")
    r.NoteStart(true)
    AssertEq(r.Tick("20261113010000", true, 1000), "", "running")
    r.NoteStop()
    AssertEq(r.Tick("20261113020000", false, 0), "", "user stopped, no restart (after midnight)")
    AssertEq(r.Tick("20261113070000", false, 0), "", "still none")
    AssertEq(r.Tick("20261113220000", false, 0), "start", "next window")
}

Test_Schedule_manual_run_left_alone() {
    cfg := StatFakeCfg(Map("Schedule.enabled", 1))
    r := RunSchedule(cfg)
    r.Tick("20261112120000", false, 0)
    r.NoteStart(false)
    AssertEq(r.Tick("20261112130000", true, 3600000), "", "manual outside window")
    cfg.m["Schedule.maxHours"] := 2
    AssertEq(r.Tick("20261112140000", true, 2 * 3600000), "stop", "max hours stops manual run")
    r.NoteStop()
    AssertEq(r.Tick("20261112140100", false, 0), "", "no start outside window")
}

Test_Schedule_max_hours_needs_enabled() {
    cfg := StatFakeCfg(Map("Schedule.maxHours", 1))
    r := RunSchedule(cfg)
    AssertEq(r.Tick("20261112120000", true, 5 * 3600000), "", "disabled does nothing")
    cfg.m["Schedule.enabled"] := 1
    AssertEq(r.Tick("20261112120000", true, 5 * 3600000), "stop", "enabled stops")
    AssertEq(r.Tick("20261112120000", true, 3599000), "", "below limit")
    cfg.m["Schedule.maxHours"] := 0
    AssertEq(r.Tick("20261112120000", true, 99 * 3600000), "", "0 = no limit")
}

Test_Schedule_all_day_and_live_config() {
    cfg := StatFakeCfg(Map("Schedule.enabled", 1, "Schedule.start", "06:00", "Schedule.end", "06:00"))
    r := RunSchedule(cfg)
    AssertEq(r.Tick("20261112130000", false, 0), "start", "all day starts")
    r.NoteStart(true)
    AssertEq(r.Tick("20261112230000", true, 1000), "", "all day keeps running")
    cfg.m["Schedule.enabled"] := 0
    AssertEq(r.Tick("20261112230000", true, 1000), "", "disabled live")
}

; ---- DailySummary ----------------------------------------------------------

Test_DailySummary_due() {
    cfg := StatFakeCfg(Map("Summary.enabled", 1))
    AssertTrue(!DailySummary.Due(cfg, "20261112235400", ""), "before 23:55")
    AssertTrue(DailySummary.Due(cfg, "20261112235500", ""), "at 23:55")
    AssertTrue(DailySummary.Due(cfg, "20261112235900", "20261111"), "after, sent yesterday")
    AssertTrue(!DailySummary.Due(cfg, "20261112235900", "20261112"), "already sent today")
    cfg.m["Summary.time"] := "18:30"
    AssertTrue(DailySummary.Due(cfg, "20261112183000", ""), "custom time")
    cfg.m["Summary.time"] := "nope"
    AssertTrue(!DailySummary.Due(cfg, "20261112183000", ""), "bad time uses default")
    cfg.m["Summary.enabled"] := 0
    AssertTrue(!DailySummary.Due(cfg, "20261112235900", ""), "disabled")
}

Test_DailySummary_build() {
    day := Map("fishCaught", 90, "fishFailed", 10, "sells", 4, "biomes", 12, "rareBiomes", 1
        , "rareAuras", 2, "rejoins", 3, "runMs", 3 * 3600000 + 5 * 60000)
    b := DailySummary.Build(day, "20261112")
    AssertEq(b.title, "Daily summary - 12 Nov", "title")
    AssertEq(b.fields.Length, 9, "field count")
    AssertEq(b.fields[1]["name"], "Fish caught", "first name")
    AssertEq(b.fields[1]["value"], "90", "first value")
    AssertEq(b.fields[3]["value"], "90%", "reel success")
    AssertEq(b.fields[9]["value"], "3h 05m", "uptime")
    AssertEq(b.fields[7]["value"], "2", "rare auras")
    e := DailySummary.Build(Map(), "20260105")
    AssertEq(e.title, "Daily summary - 5 Jan", "empty title")
    AssertEq(e.fields[1]["value"], "0", "missing = 0")
    AssertEq(e.fields[3]["value"], "n/a", "no attempts")
}

; review 2026-11-12: a restart inside the window (theme Apply now) started a
; run the user had stopped: the used window is kept in a file
Test_Schedule_UsedWindowSurvivesRestart() {
    p := A_Temp "\vesper_sched_" A_TickCount "_" Random(1, 99999) ".txt"
    try {
        cfg := StatFakeCfg(Map("Schedule.enabled", 1))
        r := RunSchedule(cfg, p)
        AssertEq(r.Tick("20261112220000", false, 0), "start", "first")
        r.NoteStart(true)
        r.Tick("20261112230000", true, 1000)
        r.NoteStop()
        r2 := RunSchedule(cfg, p)
        AssertEq(r2.Tick("20261112230500", false, 0), "", "after a restart: still no new start in this window")
        AssertEq(r2.Tick("20261113220000", false, 0), "start", "the next window starts")
        AssertEq(RunSchedule(cfg).Tick("20261112230500", false, 0), "start", "without a file: as before")
    } finally {
        try FileDelete(p)
    }
}
