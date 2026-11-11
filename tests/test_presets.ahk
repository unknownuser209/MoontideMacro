#Requires AutoHotkey v2.0
#Include ..\lib\Calibrate.ahk
; ---------------------------------------------------------------------------
; Calibration presets (data\presets\calibration_<W>x<H>_<scale>.json): the
; names, matching this system's display, Apply (with a .bak) and the
; first-run rule (only a preset made at this display is applied).
; ---------------------------------------------------------------------------

PrTmp() {
    d := A_Temp "\vesper_presets_" A_TickCount
    DirCreate(d "\presets")
    return d
}

PrWrite(path, steps := '"inv_open":{"x":42,"y":685,"color":"0x112233"}') {
    try FileDelete(path)
    FileAppend('{"version":1,"steps":{' steps '}}', path, "UTF-8")
}

; runs fn with Calibrate on dir\calibration.json and the system display sys
PrWith(dir, sys, fn) {
    old := Calibrate.SystemFn
    Calibrate.SystemFn := () => sys
    try {
        Calibrate.Use(dir "\calibration.json")
        return fn()
    } finally {
        Calibrate.SystemFn := old
        Calibrate.Use(A_Temp "\vesper_cal_unused.json")
        try DirDelete(dir, true)
    }
}

Test_Presets_ParseName() {
    p := Calibrate.ParsePresetName("calibration_2560x1440_100.json")
    AssertEq(p.w " " p.h " " p.scale, "2560 1440 100", "parsed")
    p := Calibrate.ParsePresetName("C:\x\presets\calibration_1920x1080_125.json")
    AssertEq(p.w " " p.h " " p.scale, "1920 1080 125", "full path")
    for bad in ["calibration.json", "calibration_2560x1440.json", "calibration_2560x1440_100.json.bak", "notes_1920x1080_100.json", "calibration_axb_100.json"]
        AssertEq(Calibrate.ParsePresetName(bad), "", bad " is not a preset")
    AssertEq(Calibrate.PresetLabel({w: 2560, h: 1440, scale: 100}), "2560x1440 " Chr(0xB7) " 100%", "label")
}

Test_Presets_ListsWhateverIsThere() {
    d := PrTmp()
    try {
        for n in ["calibration_1920x1080_125.json", "calibration_2560x1440_100.json", "calibration_1920x1080_100.json", "readme.json"]
            PrWrite(d "\presets\" n)
        list := Calibrate.Presets(d "\calibration.json")
        labels := ""
        for p in list
            labels .= p.label "|"
        AssertEq(labels, StrReplace("2560x1440 . 100%|1920x1080 . 100%|1920x1080 . 125%|", ".", Chr(0xB7)), "sorted, the odd file left out")
        AssertTrue(InStr(list[1].path, "calibration_2560x1440_100.json"), "path kept")
        AssertEq(Calibrate.Presets(A_Temp "\vesper_no_such_dir\calibration.json").Length, 0, "no folder: none")
    } finally
        try DirDelete(d, true)
}

Test_Presets_MatchToSystem() {
    list := [{w: 2560, h: 1440, scale: 100, path: "a"}, {w: 1920, h: 1080, scale: 125, path: "b"}]
    AssertEq(Calibrate.MatchPreset(list, {w: 2560, h: 1440, scale: 100}).path, "a", "exact")
    AssertEq(Calibrate.MatchPreset(list, {w: 1920, h: 1080, scale: 125}).path, "b", "1080p at 125%")
    AssertEq(Calibrate.MatchPreset(list, {w: 2560, h: 1440, scale: 150}), "", "same size, other scale: no")
    AssertEq(Calibrate.MatchPreset(list, {w: 1920, h: 1080, scale: 100}), "", "other scale: no")
    AssertEq(Calibrate.MatchPreset(list, ""), "", "unknown system")
    sys := Calibrate.SystemDisplay()
    AssertTrue(sys.w > 0 && sys.h > 0 && sys.scale >= 100, "this system's display is read")
}

Test_Presets_FirstRunAppliesOnlyAMatch() {
    ; a matching preset fills a missing calibration
    d := PrTmp()
    PrWrite(d "\presets\calibration_2560x1440_100.json")
    PrWith(d, {w: 2560, h: 1440, scale: 100}, () => (
        AssertTrue(IsObject(Calibrate.Point("inv_open")), "matching preset applied on first run"),
        AssertEq(Calibrate.LoadStatus(), "ok", "status ok")))
    ; no match (1080p user): left empty, nothing copied
    d := PrTmp()
    PrWrite(d "\presets\calibration_2560x1440_100.json")
    PrWith(d, {w: 1920, h: 1080, scale: 100}, () => (
        AssertEq(Calibrate.Point("inv_open"), "", "no preset for 1080p: empty"),
        AssertTrue(!FileExist(d "\calibration.json"), "nothing written")))
    ; the shipped file with no steps counts as "no calibration yet"
    d := PrTmp()
    PrWrite(d "\presets\calibration_2560x1440_100.json")
    PrWrite(d "\calibration.json", "")
    PrWith(d, {w: 2560, h: 1440, scale: 100}, () => AssertTrue(IsObject(Calibrate.Point("inv_open")), "empty steps replaced"))
    ; the user's own calibration is never replaced
    d := PrTmp()
    PrWrite(d "\presets\calibration_2560x1440_100.json")
    PrWrite(d "\calibration.json", '"inv_open":{"x":7,"y":8,"color":"0x000000"}')
    PrWith(d, {w: 2560, h: 1440, scale: 100}, () => AssertEq(Calibrate.Point("inv_open").x, 7, "own calibration kept"))
}

; Setup > Calibrate: the Preset dropdown, its note and Apply
Test_Presets_DashboardPickerAndApply() {
    dir := UiDashTmp()
    d := ""
    old := Calibrate.SystemFn
    try {
        DirCreate(dir "\presets")
        PrWrite(dir "\presets\calibration_2560x1440_100.json", '"inv_open":{"x":100,"y":200,"color":"0xFFFFFF"}')
        PrWrite(dir "\presets\calibration_1920x1080_100.json", '"inv_open":{"x":75,"y":150,"color":"0xFFFFFF"}')
        PrWrite(dir "\cal.json", '"inv_open":{"x":7,"y":8,"color":"0x000000"}')
        cfg := Config.Load(dir)
        ; a 1080p system: its preset pre-selected
        Calibrate.SystemFn := () => {w: 1920, h: 1080, scale: 100}
        Calibrate.Use(dir "\cal.json", cfg)
        d := Dashboard(cfg)
        dd := d.Ctrl("calPreset")
        AssertEq(dd.Text, "1920x1080 " Chr(0xB7) " 100%", "pre-selected to this display")
        AssertTrue(InStr(d.Ctrl("calPresetNote").Text, "Matches your display"), "note: matches")
        d._CalApplyPreset()
        AssertEq(Calibrate.Point("inv_open").x, 75, "preset applied")
        AssertTrue(InStr(FileRead(dir "\cal.json.bak", "UTF-8"), '"x":7'), "old calibration backed up")
        ; a system with no preset: the note says to calibrate
        Calibrate.SystemFn := () => {w: 3440, h: 1440, scale: 100}
        d._CalLoad()
        AssertTrue(InStr(d.Ctrl("calPresetNote").Text, "calibrate the steps below"), "note: no preset")
        AssertTrue(InStr(d.Ctrl("calPresetNote").Text, "3440x1440"), "note names the display")
    } finally {
        Calibrate.SystemFn := old
        UiDashClose(d)
        Calibrate.Use(A_Temp "\vesper_cal_unused.json")
        try DirDelete(dir, true)
    }
}

Test_Presets_ApplyBacksUp() {
    d := PrTmp()
    PrWrite(d "\presets\calibration_1920x1080_100.json", '"inv_open":{"x":100,"y":200,"color":"0xFFFFFF"}')
    PrWrite(d "\calibration.json", '"inv_open":{"x":7,"y":8,"color":"0x000000"}')
    PrWith(d, {w: 2560, h: 1440, scale: 100}, () => (
        AssertEq(Calibrate.ApplyPreset(d "\presets\calibration_1920x1080_100.json"), "", "applied"),
        AssertEq(Calibrate.Point("inv_open").x, 100, "preset loaded"),
        AssertTrue(InStr(FileRead(d "\calibration.json.bak", "UTF-8"), '"x":7'), "old calibration in .bak"),
        AssertTrue(Calibrate.ApplyPreset(d "\presets\nope.json") != "", "a missing preset is refused"),
        AssertEq(Calibrate.Point("inv_open").x, 100, "refused: nothing changed")))
}

; The shipped 1920x1080 / 100% preset (2026-11-10): Sol's RNG's UI measured
; at a 1920x1080 view sits at 0.75x its 2560x1440 place (left menu, skills,
; Roll, hotbar, inventory), so every value equals the 2560x1440 preset's;
; only Roblox's chat box keeps its pixel size: message area x 13..476,
; y 102..367 at 1080p, stored in design units (px / 0.75).
Test_Presets_Shipped1080MatchesThe1440OneButTheChat() {
    dir := RegExReplace(A_LineFile, "\\tests\\[^\\]+$", "") "\data\presets"
    a := Json.Parse(FileRead(dir "\calibration_2560x1440_100.json", "UTF-8"))["steps"]
    b := Json.Parse(FileRead(dir "\calibration_1920x1080_100.json", "UTF-8"))["steps"]
    AssertEq(b.Count, a.Count, "same steps")
    for id, e in a
        if (id != "chat_rect")
            AssertEq(Json.Stringify(b[id], 0), Json.Stringify(e, 0), id " unchanged")
    c := b["chat_rect"]
    try {
        Screen.SetClient(0, 0, 1920, 1080)
        r := Screen.Rect(c["x"], c["y"], c["w"], c["h"])
        AssertEq(r.x " " r.y " " (r.x + r.w) " " (r.y + r.h), "13 102 476 367", "chat box at its 1080p pixels")
    } finally Screen.Reset()
}
