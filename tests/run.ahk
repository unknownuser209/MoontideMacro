#Requires AutoHotkey v2.0
#SingleInstance Force
; ---------------------------------------------------------------------------
; Vesper test runner.
; Run from repo root:
;   "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" /ErrorStdOut tests\run.ahk
; Prints "PASS name" / "FAIL name: detail" per test and "N passed, M failed".
; Exit code 1 if any test failed (or threw), else 0.
;
; HOW TO ADD TESTS (later tasks):
;   1. Create tests\test_<thing>.ahk and define global functions named Test_*
;      (e.g. Test_Parse_basic()). Use AssertEq(actual, expected, name) and
;      AssertTrue(cond, name); a thrown Error also counts as FAIL.
;   2. Append ONE line below the marker: #Include test_<thing>.ahk
;   Nothing else. The runner scans every tests\test_*.ahk file for lines
;   starting with "Test_name(" and calls each by name; no manual registration.
;   Test files must not call ExitApp or run code at top level (auto-execute
;   section) since they share this script's global scope.
; ---------------------------------------------------------------------------

#Include lib\Assert.ahk

; ---- test includes (append new #Include lines below this marker) ----------
#Include test_runner.ahk
#Include test_config.ahk
#Include test_scheduler.ahk
#Include test_logwatch.ahk
#Include test_webhook.ahk
#Include test_safety.ahk
#Include test_routes.ahk
#Include test_calibrate.ahk
#Include test_questmatch.ahk
#Include test_fishing.ahk
#Include test_recovery.ahk
#Include test_ui.ahk
#Include test_ui_dash.ahk
#Include test_craft.ahk
#Include test_clip.ahk
#Include test_potions.ahk
#Include test_app.ahk
#Include test_app_fix1.ahk
#Include test_route_recorder.ahk
#Include test_app_final.ahk
#Include test_webhook_features.ahk
#Include test_aura_clip.ahk
#Include test_fishing_repath.ahk
#Include test_reset_checks.ahk
#Include test_reel.ahk
#Include test_biomeitems.ahk
#Include test_limbo.ahk
#Include test_anim.ahk
#Include test_credits.ahk
#Include test_matchlogic.ahk
#Include test_obby.ahk
#Include test_minions.ahk
#Include test_memorymatch.ahk
#Include test_ghost.ahk
#Include test_screens.ahk
#Include test_orbbeacon.ahk
#Include test_sinister.ahk
#Include test_chatguard.ahk
#Include test_tidy.ahk
#Include test_updater.ahk
#Include test_screen.ahk
#Include test_resample.ahk
#Include test_presets.ahk
#Include test_stats.ahk
#Include test_i18n.ahk

Main()

Main() {
    names := DiscoverTests()
    passed := 0
    failed := 0
    for name in names {
        try {
            %name%()
            passed++
            Out("PASS " name)
        } catch Any as e {
            failed++
            Out("FAIL " name ": " (e is Error ? e.Message : AssertShow(e)))
        }
    }
    Out(passed " passed, " failed " failed")
    ExitApp(failed > 0 ? 1 : 0)
}

; Collect Test_* function names from tests\test_*.ahk, sorted by file then order.
DiscoverTests() {
    names := []
    seen := Map()
    Loop Files, A_ScriptDir "\test_*.ahk" {
        text := FileRead(A_LoopFilePath, "UTF-8")
        pos := 1
        while (pos := RegExMatch(text, "m)^[ \t]*(Test_\w+)[ \t]*\(", &m, pos)) {
            if !seen.Has(m[1]) {
                seen[m[1]] := true
                names.Push(m[1])
            }
            pos += m.Len
        }
    }
    return names
}

Out(line) {
    FileAppend(line "`n", "*")
}
#Include test_remote.ahk
#Include test_setupcheck.ahk
#Include test_logbundle.ahk
#Include test_fixit.ahk
#Include test_profiles.ahk
