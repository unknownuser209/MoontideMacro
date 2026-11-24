#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\Json.ahk
#Include %A_LineFile%\..\Calibrate.ahk
; ---------------------------------------------------------------------------
; CalHealth: how each RECORDED calibration step did when a task used it.
; The tasks say so at the places where they already check a spot's own read
; (the Open Shop button read at fisher_open_shop, Stella's Workshop title in
; cauldron_gui, a Drive in selector_list_rect, the Aura Storage title over
; aura_search, ...). "Test my calibration" (lib\CalTest.ahk) turns it into
; a verdict for the steps it cannot test without walking.
;
;   CalHealth.Ok(id [, used])          the step's read worked
;   CalHealth.Fail(id, why [, used])   the step's read did not work (why: a
;                                      few plain words, shown to the user)
;     used: the point / rect the task used. Given and not the recording
;     (a place found on screen this run, lib\AutoCal.ahk), nothing is
;     noted: only recordings are judged. A step that is not recorded is
;     never noted either.
;   CalHealth.Get(id) -> "" | {ok, fail, run (fails in a row, 0 after a
;     success), lastOk, lastFail (A_Now stamps or ""), why (last failure)}
;     The history belongs to one recording: record the step again (or apply
;     a preset that moves it) and it starts over.
;   CalHealth.Use(path)   load the store, note uses and save to it from
;     now on. App: data\cal_health.json (user-local, gitignored; never
;     settings.ini). Until then (and in every test) nothing is noted;
;     CalHealth.On := true notes in memory only (this file's own tests).
;   CalHealth.Flush()     write now when something changed
;
; Saves: a failure at once, a success at most every SaveGapMs (or when it
; ends a run of failures). Never throws into a task.
; ---------------------------------------------------------------------------

class CalHealth {
    static SaveGapMs := 60000
    static On := false
    ; (id) -> the recording as a string ("" = not recorded). Tests swap it.
    static KeyFn := (id) => Calibrate.StoredKey(id)
    static NowFn := () => A_Now
    static TickFn := () => A_TickCount
    static _path := ""
    static _m := Map()
    static _dirty := false
    static _savedAt := ""

    static Use(path := "") {
        CalHealth._path := path
        CalHealth.On := (path != "")
        CalHealth._m := Map()
        CalHealth._dirty := false
        CalHealth._savedAt := ""
        if (path = "" || !FileExist(path))
            return
        root := ""
        try root := Json.Parse(FileRead(path, "UTF-8"))
        if !(root is Map && root.Has("steps") && root["steps"] is Map)
            return
        for id, e in root["steps"] {
            if !(e is Map && e.Has("key"))
                continue
            n := Map("key", String(e["key"]))
            for k in ["ok", "fail", "run"]
                n[k] := (e.Has(k) && IsInteger(e[k]) && e[k] >= 0) ? Integer(e[k]) : 0
            for k in ["lastOk", "lastFail", "why"]
                n[k] := e.Has(k) ? String(e[k]) : ""
            CalHealth._m[String(id)] := n
        }
    }

    ; for the tests: forget everything (memory only again)
    static Reset() => CalHealth.Use("")

    static Ok(id, used := "") => CalHealth._Note(id, true, "", used)
    static Fail(id, why, used := "") => CalHealth._Note(id, false, why, used)

    static Get(id) {
        key := CalHealth._Key(id)
        if (key = "" || !CalHealth._m.Has(id))
            return ""
        e := CalHealth._m[id]
        if (e["key"] != key)
            return ""
        return {ok: e["ok"], fail: e["fail"], run: e["run"], lastOk: e["lastOk"], lastFail: e["lastFail"], why: e["why"]}
    }

    static Flush() {
        if CalHealth._dirty
            CalHealth._Save()
    }

    ; a point / rect -> the string a recording is compared by
    static KeyOf(v) {
        if !(IsObject(v) && HasProp(v, "x") && HasProp(v, "y"))
            return ""
        return Round(v.x) "," Round(v.y) (HasProp(v, "w") ? "," Round(v.w) "," Round(v.h) : "")
    }

    static _Key(id) {
        k := ""
        try k := String(CalHealth.KeyFn.Call(id))
        return k
    }

    static _Note(id, ok, why, used) {
        if !CalHealth.On
            return
        try {
            key := CalHealth._Key(id)
            if (key = "")
                return
            if (IsObject(used) && CalHealth.KeyOf(used) != key)
                return                          ; a place found on screen, not the recording
            e := CalHealth._m.Has(id) ? CalHealth._m[id] : ""
            if (!IsObject(e) || e["key"] != key)
                e := Map("key", key, "ok", 0, "fail", 0, "run", 0, "lastOk", "", "lastFail", "", "why", "")
            CalHealth._m[id] := e
            now := CalHealth.NowFn.Call()
            wasFailing := e["run"] > 0
            if ok {
                e["ok"] += 1, e["run"] := 0, e["lastOk"] := now
            } else {
                e["fail"] += 1, e["run"] += 1, e["lastFail"] := now, e["why"] := SubStr(Trim(String(why)), 1, 160)
            }
            CalHealth._dirty := true
            if (!ok || wasFailing || CalHealth._savedAt = "" || CalHealth.TickFn.Call() - CalHealth._savedAt >= CalHealth.SaveGapMs)
                CalHealth._Save()
        }
    }

    static _Save() {
        CalHealth._savedAt := CalHealth.TickFn.Call()
        if (CalHealth._path = "") {
            CalHealth._dirty := false
            return
        }
        try {
            steps := Map()
            for id, e in CalHealth._m
                steps[id] := e
            text := Json.Stringify(Map("version", 1, "steps", steps)) "`n"
            SplitPath(CalHealth._path, , &dir)
            if (dir != "" && !DirExist(dir))
                DirCreate(dir)
            tmp := CalHealth._path ".tmp"
            f := FileOpen(tmp, "w", "UTF-8-RAW")
            f.Write(text)
            f.Close()
            FileMove(tmp, CalHealth._path, 1)
            CalHealth._dirty := false
        }
    }
}
