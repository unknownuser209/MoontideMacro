#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\Stats.ahk
#Include %A_LineFile%\..\Schedule.ahk
; ---------------------------------------------------------------------------
; DailySummary: pure logic for the end-of-day Discord summary (no network).
;
;   DailySummary.Due(cfg, nowStamp, lastSentYmd) -> true when Summary.enabled
;       = 1, the local time is at or past Summary.time (HH:mm, default
;       "23:55"; a bad value = the default) and lastSentYmd != today.
;   DailySummary.Build(dayMap, ymd) -> {title, desc, fields}
;       title   "Daily summary - 12 Nov"
;       fields  Array of Map(name, value, inline), the same shape as
;               Webhook.Field; pass as opts.fields. Missing keys count as 0.
; Config keys: Summary.enabled (0), Summary.time ("23:55").
; ---------------------------------------------------------------------------

class DailySummary {
    static DefaultTime := "23:55"

    static Due(cfg, nowStamp, lastSentYmd) {
        if (Integer(cfg.Get("Summary.enabled", 0)) != 1)
            return false
        t := RunSchedule.ValidTime(String(cfg.Get("Summary.time", DailySummary.DefaultTime)))
        if (t = "")
            t := DailySummary.DefaultTime
        nowStamp := String(nowStamp)
        if (SubStr(nowStamp, 1, 8) = String(lastSentYmd))
            return false
        return RunSchedule.Mins(SubStr(nowStamp, 9, 2) ":" SubStr(nowStamp, 11, 2)) >= RunSchedule.Mins(t)
    }

    static Build(dayMap, ymd) {
        static months := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        ymd := String(ymd)
        title := "Daily summary"
        if RegExMatch(ymd, "^(\d{4})(\d{2})(\d{2})$", &m) && Integer(m[2]) >= 1 && Integer(m[2]) <= 12
            title .= " - " Integer(m[3]) " " months[Integer(m[2])]
        n := (k) => dayMap.Has(k) ? dayMap[k] : 0
        dv := DailyStats.Derived(dayMap)
        fields := [
            DailySummary._F("Fish caught", n("fishCaught"))
            , DailySummary._F("Fish missed", n("fishFailed"))
            , DailySummary._F("Reel success", dv["reelRate"] = "" ? "n/a" : dv["reelRate"] "%")
            , DailySummary._F("Sell trips", n("sells"))
            , DailySummary._F("Biomes seen", n("biomes"))
            , DailySummary._F("Rare biomes", n("rareBiomes"))
            , DailySummary._F("Rare auras", n("rareAuras"))
            , DailySummary._F("Rejoins", n("rejoins"))
            , DailySummary._F("Uptime", dv["uptimeText"])
        ]
        return {title: title, desc: "", fields: fields}
    }

    static _F(name, value) => Map("name", name, "value", String(value), "inline", 1)
}
