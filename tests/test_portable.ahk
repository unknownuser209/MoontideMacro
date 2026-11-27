#Requires AutoHotkey v2.0
; Bugs that the dev PC (US keyboard, English Windows 11, PowerShell set up)
; never shows and players' PCs do (bug hunt 2026-11-26): keys by place on
; AZERTY / QWERTZ layouts, Windows' text recognizer on non-US / non-English
; Windows, the updater's unzip without a usable PowerShell.
; Helpers are prefixed Pt (must not start with Test_).
#Include ..\lib\Input.ahk
#Include ..\lib\Ocr.ahk
#Include ..\lib\Updater.ahk

; ---- keys by their place (Input.PhysKey) ------------------------------------

Test_Portable_LettersAndDigitsGoByScanCode() {
    for pair in [["w", "sc011"], ["a", "sc01E"], ["s", "sc01F"], ["d", "sc020"], ["q", "sc010"], ["z", "sc02C"]
        , ["y", "sc015"], ["e", "sc012"], ["f", "sc021"], ["r", "sc013"], ["m", "sc032"], ["p", "sc019"], ["l", "sc026"]
        , ["1", "sc002"], ["9", "sc00A"], ["0", "sc00B"]]
        AssertEq(Input.PhysKey(pair[1]), pair[2], "key " pair[1])
    AssertEq(Input.ScanCodes.Count, 36, "a-z and 0-9")
    ; everything else is sent as it was (the same key on every layout)
    for k in ["Space", "Esc", "Enter", "LShift", "sc02A", "RButton", "Left", "F11", "W", "ww", ""]
        AssertEq(Input.PhysKey(k), k, "kept " k)
    AssertEq(Input.PhysKey(5), 5, "not a string: kept")
}

; every scan code names the key AutoHotkey reads back as that letter on a
; US layout (GetKeyName), so a US / UK player's keys did not change
Test_Portable_ScanCodesAreTheUsKeys() {
    for k, sc in Input.ScanCodes
        AssertEq(Format("sc{:03X}", GetKeySC(k)), sc, "GetKeySC " k)
}

; ---- Windows' text recognizer --------------------------------------------------

Test_Portable_OcrLangOrder() {
    AssertEq(Ocr.Langs[1], "en-US", "en-US first")
    for t in ["en-GB", "en-AU", "en-IN", "en"]
        AssertTrue(PtHas(Ocr.LangOrder(""), t), "tries " t)
    o := Ocr.LangOrder("en-GB")
    AssertEq(o[1], "en-GB", "the one that worked last first")
    AssertEq(o.Length, Ocr.Langs.Length, "each tag once")
    AssertEq(Ocr.LangOrder("user").Length, 0, "only the user's language worked: no English tries")
}

; No English recognizer (a Brazilian / Spanish Windows): reads use the
; Windows user's own language's one instead of returning "" for ever. Here
; that one is this PC's English, so the frame still reads.
Test_Portable_OcrFallsBackToTheUserLanguage() {
    oldLangs := Ocr.Langs, oldTag := Ocr.Tag
    f := A_ScriptDir "\screens\workshop_open.jpg"
    try {
        Ocr.Langs := ["xx-XX"], Ocr.Tag := ""
        t := Ocr.ReadFile(f, 1870, 337, 540, 44)
        AssertEq(Ocr.Tag, "user", "the user-profile recognizer was used")
        AssertTrue(RegExMatch(t, "i)se[ao]rch"), "and it reads ('" t "')")
        info := Ocr.EngineInfo()
        AssertTrue(info.tag != "", "EngineInfo names its language: " info.tag)
        AssertEq(info.english, RegExMatch(info.tag, "i)^en") ? true : false, "english flag from the tag")
    } finally {
        Ocr.Langs := oldLangs, Ocr.Tag := oldTag
    }
    info := Ocr.EngineInfo()
    AssertEq(info.english, true, "this PC: an English recognizer")
    AssertTrue(PtHas(Ocr.Langs, info.tag), "one of the English tags: " info.tag)
}

; ---- the updater's unzip -------------------------------------------------------
; (the tar-then-PowerShell order, the time cap and a real zip are in
; test_updater.ahk; here the quoting of an odd folder name)

Test_Portable_UnzipCommandQuotesAndBypass() {
    ps := ""
    for t in Updater._UnzipCmds("C:\Users\O'Brien\Down loads\update_tmp\release.zip", "C:\Users\O'Brien\Down loads\update_tmp\x")
        if (t.name = "PowerShell")
            ps := t.cmd
    AssertTrue(InStr(ps, "-LiteralPath 'C:\Users\O''Brien\Down loads\update_tmp\release.zip'"), "apostrophe doubled: " ps)
    AssertTrue(InStr(ps, "-DestinationPath 'C:\Users\O''Brien\Down loads\update_tmp\x'"), "dest quoted")
    AssertTrue(InStr(ps, "-ExecutionPolicy Bypass"), "the Restricted default policy cannot block the Archive module")
    AssertTrue(InStr(ps, "-NoProfile -NonInteractive"), "no profile, never asks")
    cq := Chr(0x2019)
    AssertEq(Updater.PsQuote("Bob" cq "s"), "'Bob" cq cq "s'", "a curly apostrophe is a quote to PowerShell too")
    AssertEq(Updater.PsQuote("a" Chr(0x2018) "b"), "'a" Chr(0x2018) Chr(0x2018) "b'", "left curly quote too")
}

; ---- helpers -------------------------------------------------------------------

PtHas(arr, v) {
    for x in arr
        if (x = v)
            return true
    return false
}

