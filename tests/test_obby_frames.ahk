#Requires AutoHotkey v2.0
; ---------------------------------------------------------------------------
; The obby's aura swap on REAL 2560x1440 frames (the macro's own failure
; screenshots, live 2026-11-24), read with the real Windows OCR and pixels
; through the task's own methods and the user's calibration (aura_search
; 1146,490 / aura_equip 840,843 / first tile 1054,544 77x70).
;
;   storage_pumpkinity_selected_day / _night / _dark (03:42, 08:48, 13:27):
;     the put-back of :Flushed:_Pumpkinity. It WAS listed (result 1 on the
;     Special tab; the frame is the last try, the Regular tab, with it still
;     selected), but its name is a script logo OCR never reads, and the log
;     pick bailed out without a word: the see-through panel's info lines
;     read 'Rolle a : ... With luc of' (day) / 'Roll4Ft ... lck' (night), so
;     "no aura selected"; the button read 'Equin' (dark). The swap then took
;     the empty last try for "the game's search is stuck" and rejoined.
;   storage_styx_selected_sailor_stuck / _fishing_banner (19:18, 18:15):
;     "Sailor" typed (the box reads 'Soilor'), neither tab lists anything:
;     the game's search really was stuck (7 obbies skipped 18:15-19:18, a
;     rejoin at 19:52 cured it).
; ---------------------------------------------------------------------------

ObfPath(name) => FileExist(A_ScriptDir "\screens\" name ".png") ? A_ScriptDir "\screens\" name ".png" : A_ScriptDir "\screens\" name ".jpg"

; an ObbyTask whose OCR and pixels are the frame's
ObfTask(name) {
    p := ObfPath(name)
    AssertTrue(FileExist(p), "frame " name " exists")
    return ObbyTask({ocr: (x, y, w, h, scale := 1) => Ocr.ReadFile(p, x, y, w, h, scale), rect: AcFileRect(p), log: (m) => 0})
}

ObfCal() => {aura_equip: {x: 840, y: 843}, aura_search: {x: 1146, y: 490}, aura_tile_rect: {x: 1054, y: 544, w: 77, h: 70}}

ObfStorageFrames() => ["storage_pumpkinity_selected_day", "storage_pumpkinity_selected_night", "storage_pumpkinity_selected_dark"
    , "storage_styx_selected_sailor_stuck", "storage_styx_selected_fishing_banner", "aura_selected_sailor", "aura_selected_dutchman"]

Test_ObbyFrames_SelectedAuraSeenThroughTheSeeThroughPanel() {
    c := ObfCal()
    for f in ObfStorageFrames()
        AssertTrue(ObfTask(f)._Selected(c), f ": an aura is selected (its info lines read)")
    ; the open storage with nothing selected: no info lines (its button still says Equip)
    AssertTrue(!ObfTask("aura_search_sailor")._Selected(c), "aura_search_sailor: nothing selected")
    for f in ["world_day", "inventory_day"]
        AssertTrue(!ObfTask(f)._Selected(c), f ": no storage, nothing selected")
}

Test_ObbyFrames_EquipButtonReadsOnEveryFrame() {
    c := ObfCal()
    for f in ObfStorageFrames() {
        t := ObfTask(f)
        AssertEq(t._Button(c), "off", f ": the button reads Equip ('" t._btn "')")
    }
    AssertEq(ObbyTask.ButtonState("Equin"), "off", "the dark frame's 1x read")
    AssertEq(ObbyTask.ButtonState("Unequin"), "on", "...and its Unequip")
}

; the logo names (with the live list of aura names, data\auras.json): the
; read is never taken for the aura nor for another one, so the log pick
; may still try that tile
Test_ObbyFrames_LogoNamesNeverReadAsAnotherAura() {
    c := ObfCal()
    old := ObbyTask.Known
    try {
        m := Map()
        for e in Json.Parse(FileRead(A_ScriptDir "\..\data\auras.json", "UTF-8"))["auras"]
            m[GameLists.Fold(e["name"])] := true
        ObbyTask.Known := m
        for f in ["storage_pumpkinity_selected_day", "storage_pumpkinity_selected_night", "storage_pumpkinity_selected_dark"]
            AssertEq(ObfTask(f)._ReadName(c, ":Flushed:_Pumpkinity").v, "unread", f ": the logo stays unread (the log pick decides)")
        for f in ["storage_styx_selected_sailor_stuck", "storage_styx_selected_fishing_banner"]
            AssertTrue(ObfTask(f)._ReadName(c, "Sailor").v != "same", f ": Lost Soul: Styx is never Sailor")
    } finally ObbyTask.Known := old
}

; what the stuck-search check looks at: result tile 1 empty, the box holding the name
Test_ObbyFrames_StuckSearchListsNothing() {
    c := ObfCal(), b := ObbyTask.SearchBox
    for f, want in Map("storage_styx_selected_sailor_stuck", "Sailor", "storage_styx_selected_fishing_banner", "Sailor"
        , "storage_pumpkinity_selected_day", "Pumpkinity", "storage_pumpkinity_selected_night", "Pumpkinity") {
        t := ObfTask(f)
        AssertTrue(!t._TileHere(ObbyTask.TileRect(c.aura_tile_rect, 1)), f ": result tile 1 is empty")
        rd := Ocr.ReadFile(ObfPath(f), c.aura_search.x + b.dx, c.aura_search.y + b.dy, b.w, b.h, ObbyTask.SearchScale)
        AssertTrue(ObbyTask.SearchHolds(rd, want), f ": the box holds " want " ('" rd "')")
    }
    AssertTrue(ObfTask("aura_search_sailor")._TileHere(ObbyTask.TileRect(c.aura_tile_rect, 1)), "a search that lists: tile 1 shows")
}
