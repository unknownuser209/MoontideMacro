#Requires AutoHotkey v2.0
; Tests for lib\Calibrate.ahk. Store lives in a temp dir under A_Temp, never
; the repo's data\calibration.json. Pixel colors come from a fake getter.
; The live click capture / GUI is a manual check (see task-9 report).
#Include ..\lib\Calibrate.ahk
#Include ..\lib\Config.ahk

; ---- helpers (names must not start with Test_) -----------------------------

CalTempDir() {
    d := A_Temp "\vesper_caltest_" A_TickCount "_" Random(100000, 999999)
    DirCreate(d)
    return d
}

CalCleanup(d) {
    Calibrate.Use(A_Temp "\vesper_cal_unused.json")
    try DirDelete(d, true)
}

CalIds(steps) {
    out := []
    for s in steps
        out.Push(s["id"])
    return out
}

CalHas(arr, v) {
    for x in arr {
        if (x = v)
            return true
    }
    return false
}

; ---- store -----------------------------------------------------------------

Test_Calibrate_roundtrip() {
    d := CalTempDir()
    try {
        p := d "\cal.json"
        Calibrate.Use(p)
        Calibrate.SetPoint("fisher_qty", 1200, 800, 0xF2A93B)
        Calibrate.SetRect("chat_rect", 300, 900, 10, 100)    ; reversed corners
        Calibrate.Use(p)                                      ; forces a reload from disk
        pt := Calibrate.Point("fisher_qty")
        AssertEq(pt.x, 1200, "x")
        AssertEq(pt.y, 800, "y")
        AssertEq(pt.color, 0xF2A93B, "color")
        r := Calibrate.Rect("chat_rect")
        AssertEq(r.x, 10, "rect x")
        AssertEq(r.y, 100, "rect y")
        AssertEq(r.w, 290, "rect w")
        AssertEq(r.h, 800, "rect h")
        AssertEq(FileExist(p ".tmp"), "", "no tmp left")
    } finally {
        CalCleanup(d)
    }
}

Test_Calibrate_missing_id_returns_empty() {
    d := CalTempDir()
    try {
        Calibrate.Use(d "\none.json")                        ; file does not exist
        AssertEq(Calibrate.Point("inv_open"), "", "missing point")
        AssertEq(Calibrate.Rect("chat_rect"), "", "missing rect")
        Calibrate.SetPoint("inv_open", 5, 6, 0x112233)
        AssertEq(Calibrate.Rect("inv_open"), "", "point id is not a rect")
        Calibrate.SetRect("chat_rect", 1, 2, 30, 40)
        AssertEq(Calibrate.Point("chat_rect"), "", "rect id is not a point")
        AssertEq(Calibrate.Point("no_such_step"), "", "unknown id")
    } finally {
        CalCleanup(d)
    }
}

Test_Calibrate_bad_file_treated_empty_and_backed_up() {
    d := CalTempDir()
    try {
        p := d "\cal.json"
        FileAppend("{ not json", p, "UTF-8-RAW")
        Calibrate.Use(p)
        AssertEq(Calibrate.Point("inv_open"), "", "bad file -> empty")
        AssertEq(Calibrate.LoadStatus(), "bad", "status")
        AssertTrue(FileExist(p), "bad file untouched by load")
        Calibrate.SetPoint("inv_open", 5, 6, 0x112233)       ; save backs up the bad file
        AssertTrue(FileExist(p ".bad"), "backup written")
        AssertEq(FileRead(p ".bad", "UTF-8"), "{ not json", "backup content")
        Calibrate.Use(p)
        AssertEq(Calibrate.Point("inv_open").x, 5, "saved after bad")
    } finally {
        CalCleanup(d)
    }
}

Test_Calibrate_malformed_entries_ignored() {
    d := CalTempDir()
    try {
        p := d "\cal.json"
        FileAppend('{"steps":{"a":{"x":"zz","y":2,"color":"0x112233"},"b":{"x":1,"y":2,"color":"nope"},"c":{"x":1,"y":2,"w":0,"h":5},"ok":{"x":1,"y":2,"color":"#0D1117"}}}', p, "UTF-8-RAW")
        Calibrate.Use(p)
        AssertEq(Calibrate.Point("a"), "", "non-int x")
        AssertEq(Calibrate.Point("b"), "", "bad color")
        AssertEq(Calibrate.Rect("c"), "", "zero-width rect")
        AssertEq(Calibrate.Point("ok").color, 0x0D1117, "good entry survives")
    } finally {
        CalCleanup(d)
    }
}

Test_Calibrate_atomic_write_directory_guard() {
    d := CalTempDir()
    try {
        p := d "\cal.json"
        DirCreate(p)                                          ; a directory squats on the target
        Calibrate.Use(p)
        threw := false
        try Calibrate.SetPoint("inv_open", 5, 6, 0x112233)
        catch
            threw := true
        AssertTrue(threw, "save onto a directory throws")
        AssertTrue(InStr(FileExist(p), "D"), "target still a directory")
        AssertEq(FileExist(p "\cal.json.tmp"), "", "tmp not moved into dir")
        AssertEq(FileExist(p ".tmp"), "", "tmp deleted on failure")
        ; value stays usable in memory for this run
        AssertEq(Calibrate.Point("inv_open").x, 5, "in-memory value kept")
    } finally {
        CalCleanup(d)
    }
}

; ---- rect normalisation / input validation ---------------------------------

Test_Calibrate_rect_normalised_any_order() {
    d := CalTempDir()
    try {
        Calibrate.Use(d "\cal.json")
        Calibrate.SetRect("a", 10, 20, 110, 70)
        Calibrate.SetRect("b", 110, 70, 10, 20)
        Calibrate.SetRect("c", 110, 20, 10, 70)
        Calibrate.SetRect("d", 10, 70, 110, 20)
        for id in ["a", "b", "c", "d"] {
            r := Calibrate.Rect(id)
            AssertEq(r.x, 10, id " x")
            AssertEq(r.y, 20, id " y")
            AssertEq(r.w, 100, id " w")
            AssertEq(r.h, 50, id " h")
        }
    } finally {
        CalCleanup(d)
    }
}

Test_Calibrate_degenerate_rect_rejected() {
    d := CalTempDir()
    try {
        Calibrate.Use(d "\cal.json")
        threw := false
        try Calibrate.SetRect("a", 10, 20, 10, 70)
        catch ValueError
            threw := true
        AssertTrue(threw, "zero width")
        AssertEq(Calibrate.Rect("a"), "", "nothing stored")
    } finally {
        CalCleanup(d)
    }
}

; ---- step list -------------------------------------------------------------

Test_Calibrate_steplist_has_all_binding_ids() {
    d := CalTempDir()
    try {
        Calibrate.Use(d "\cal.json")
        ids := CalIds(Calibrate.Steps())
        for want in ["notify_rect", "fisher_open_shop", "fisher_qty", "fisher_confirm",
            "cauldron_gui", "cauldron_search", "cauldron_result", "cauldron_open_recipe", "cauldron_add_all", "cauldron_close", "stella_dialog",
            "inv_open", "inv_items_tab", "inv_search", "inv_tile1_rect", "inv_tile2_rect", "inv_count_rect", "inv_use",
            "inv_desc_rect", "inv_amount_box",
            "quest_board_rect", "quest_accept", "quest_dismiss", "quest_close", "obby_blessing",
            "aura_open", "aura_search", "aura_tile_rect", "aura_equip", "aura_close", "buff_expand",
            "chat_rect"]
            AssertTrue(CalHas(ids, want), "has " want)
        ; Claim Rewards shares the Accept spot; the game has no Reconnect button;
        ; notifications are read as text in notify_rect
        for gone in ["quest_turnin", "reconnect_btn", "craft_notify", "mari_buy", "jester_buy"]
            AssertTrue(!CalHas(ids, gone), "removed " gone)
        ; superseded by the tile scan / description box / amount signature (12b)
        for gone in ["inv_item_name_rect", "inv_selected_name_rect", "inv_amount_rect"]
            AssertTrue(!CalHas(ids, gone), "removed " gone)
        seen := Map()
        for id in ids {
            AssertTrue(!seen.Has(id), "unique " id)
            seen[id] := 1
        }
        kinds := Map()
        for s in Calibrate.Steps()
            kinds[s["id"]] := s["kind"]
        for id in ["inv_tile1_rect", "inv_tile2_rect", "inv_count_rect", "inv_desc_rect", "quest_board_rect", "chat_rect"]
            AssertEq(kinds[id], "rect", id " is rect")
        AssertEq(kinds["inv_open"], "point", "inv_open is point")
        AssertEq(kinds["obby_blessing"], "point", "obby_blessing is point")
        AssertEq(kinds["inv_amount_box"], "rect", "the amount box is a plain box (a lone 1 cannot be told from empty)")
        for gone in ["inv_amount_empty", "inv_amount_one"]
            AssertTrue(!kinds.Has(gone), "no " gone " step")
        for id in ["cauldron_gui", "cauldron_result", "cauldron_result_2", "stella_dialog", "fisher_picked_name"]
            AssertEq(kinds[id], "rect", id " is a text box (OCR)")
        AssertEq(kinds["fisher_leave"], "point", "fisher_leave is a point")
        iOp := 0, iTab := 0, iSe := 0
        for i, id in ids {
            if (id = "inv_open")
                iOp := i
            if (id = "inv_items_tab")
                iTab := i
            if (id = "inv_search")
                iSe := i
        }
        AssertTrue(iOp > 0 && iOp < iTab && iTab < iSe, "inv_open -> inv_items_tab -> inv_search")
        AssertEq(kinds["inv_items_tab"], "point", "inv_items_tab is a point")
        for s in Calibrate.Steps()
            AssertTrue(s["prompt"] != "", "prompt " s["id"])
    } finally {
        CalCleanup(d)
    }
}

Test_Calibrate_steplist_default_potions() {
    d := CalTempDir()
    try {
        Calibrate.Use(d "\cal.json")
        ids := CalIds(Calibrate.Steps())
        AssertTrue(CalHas(ids, "fisher_item_lucky_potion"), "lucky")
        ; 2026-11-11: Lucky only (a fresh copy asked a friend for a Speed
        ; Potion tile no preset has)
        AssertTrue(!CalHas(ids, "fisher_item_speed_potion"), "no speed step by default")
    } finally {
        CalCleanup(d)
    }
}

Test_Calibrate_steplist_per_potion_from_config() {
    d := CalTempDir()
    try {
        cfg := Config.Load(d)
        cfg.Set("Craft.potions", "Lucky Potion, Wind Essence,  Lucky Potion , haste  potion iii")
        Calibrate.Use(d "\cal.json", cfg)
        ids := CalIds(Calibrate.Steps())
        buys := []
        for id in ids {
            if (SubStr(id, 1, 12) = "fisher_item_")
                buys.Push(id)
        }
        AssertEq(buys.Length, 3, "dedup, trimmed, one per potion")
        AssertEq(buys[1], "fisher_item_lucky_potion", "1")
        AssertEq(buys[2], "fisher_item_wind_essence", "2")
        AssertEq(buys[3], "fisher_item_haste_potion_iii", "3")
        ; buy steps sit between fisher_open_shop and fisher_qty
        AssertEq(ids[1], "notify_rect", "first")
        AssertEq(ids[2], "fisher_open_shop", "Open Shop before the buy buttons")
        AssertEq(ids[3], "fisher_item_lucky_potion", "then the potions")
        AssertTrue(InStr(Calibrate.Steps()[4]["prompt"], "Wind essence"), "prompt names the potion (shop spelling)")
    } finally {
        CalCleanup(d)
    }
}

Test_Calibrate_unknown_potions_skipped_and_logged() {
    d := CalTempDir()
    try {
        cfg := Config.Load(d)
        cfg.Set("Craft.potions", "Lucky Potion,Lucky,Mystery Brew,Speed Potion")
        logged := []
        Calibrate.Logger := (m) => logged.Push(m)
        Calibrate.Use(d "\cal.json", cfg)
        ids := CalIds(Calibrate.Steps())
        AssertTrue(CalHas(ids, "fisher_item_lucky_potion"), "known kept")
        AssertTrue(CalHas(ids, "fisher_item_speed_potion"), "known kept 2")
        AssertTrue(!CalHas(ids, "fisher_item_lucky"), "short name not invented")
        AssertTrue(!CalHas(ids, "fisher_item_mystery_brew"), "unknown skipped")
        sk := Calibrate.Skipped()
        AssertEq(sk.Length, 2, "two skipped")
        AssertEq(sk[1], "Lucky", "skipped 1")
        AssertEq(sk[2], "Mystery Brew", "skipped 2")
        AssertEq(logged.Length, 2, "logged both")
        AssertTrue(InStr(logged[2], "Mystery Brew"), "log names entry")
    } finally {
        Calibrate.Logger := ""
        CalCleanup(d)
    }
}

Test_Calibrate_potion_names_match_the_fisher_shop() {
    ; every Fisher shop item is a valid [Craft] potions entry; case is
    ; canonicalised; what the shop does not sell is skipped
    d := CalTempDir()
    try {
        names := ""
        for n in GameLists.Shop
            names .= (names = "" ? "" : ",") StrUpper(n)
        local2 := Config.Load(d)
        local2.Set("Craft.potions", names)
        Calibrate.Use(d "\cal.json", local2)
        AssertEq(Calibrate.Skipped().Length, 0, "all shop names accepted")
        AssertEq(Calibrate.Potions().Length, GameLists.Shop.Length, "one each")
        AssertEq(Calibrate.Potions()[1], "Lucky Potion", "canonical spelling restored")
        AssertEq(Calibrate.Potions()[3], "Wind essence", "game spelling kept")
        local2.Set("Craft.potions", "Lucky Potion,Fortune Potion I,Godlike Potion")
        sk := Calibrate.Skipped()
        AssertEq(sk.Length, 2, "craft-only potions are not bought")
        AssertEq(sk[1], "Fortune Potion I", "not sold 1")
        AssertEq(sk[2], "Godlike Potion", "not sold 2")
    } finally {
        CalCleanup(d)
    }
}

Test_Calibrate_craft_potions_in_ini_defaults() {
    d := CalTempDir()
    try {
        cfg := Config.Load(d)
        AssertEq(cfg.Get("Craft.potions", "x"), "Lucky Potion", "default registered")
        AssertTrue(InStr(FileRead(d "\settings.ini", "UTF-8"), "[Craft]"), "written to new ini")
    } finally {
        CalCleanup(d)
    }
}

Test_Calibrate_capture_key_default_and_config() {
    d := CalTempDir()
    try {
        Calibrate.Use(d "\cal.json")
        AssertEq(Calibrate.CaptureKey(), "F4", "default F4")
        cfg := Config.Load(d)
        cfg.Set("Calibrate.captureKey", "F7")
        Calibrate.Use(d "\cal.json", cfg)
        AssertEq(Calibrate.CaptureKey(), "F7", "override")
        cfg.Set("Calibrate.captureKey", "F9")
        AssertEq(Calibrate.CaptureKey(), "F4", "an old F9 (Roblox dev console) becomes F4")
    } finally {
        CalCleanup(d)
    }
}

Test_Calibrate_prompts_hover_never_click() {
    d := CalTempDir()
    try {
        Calibrate.Use(d "\cal.json")
        for s in Calibrate.Steps() {
            AssertTrue(!RegExMatch(s["prompt"], "i)\bclick"), s["id"] " prompt tells user to click")
            AssertTrue(RegExMatch(s["prompt"], "i)hover"), s["id"] " prompt says hover")
        }
        sess := Calibrate.NewSession(Calibrate.ResolveIds("inv_open,chat_rect"))
        t := sess.PromptText()
        AssertTrue(InStr(t, "F4"), "names capture key")
        AssertTrue(InStr(t, "Nothing is clicked"), "says nothing is clicked")
        sess.Skip()
        AssertTrue(InStr(sess.PromptText(), "TOP-LEFT"), "rect asks top-left first")
    } finally {
        CalCleanup(d)
    }
}

Test_Calibrate_potion_id() {
    AssertEq(Calibrate.PotionId("Lucky Potion"), "fisher_item_lucky_potion", "plain")
    AssertEq(Calibrate.PotionId("  Heavenly  Potion #2 "), "fisher_item_heavenly_potion_2", "punct/space")
}

Test_Calibrate_resolve_ids() {
    d := CalTempDir()
    try {
        Calibrate.Use(d "\cal.json")
        all := Calibrate.ResolveIds("all")
        AssertEq(all.Length, Calibrate.Steps().Length, "all")
        two := Calibrate.ResolveIds("inv_open, chat_rect")
        AssertEq(two.Length, 2, "csv")
        AssertEq(two[2]["id"], "chat_rect", "order kept")
        arr := Calibrate.ResolveIds(["quest_close"])
        AssertEq(arr[1]["kind"], "point", "array")
        threw := false
        try Calibrate.ResolveIds("inv_open,bogus")
        catch ValueError
            threw := true
        AssertTrue(threw, "unknown id throws")
    } finally {
        CalCleanup(d)
    }
}

; ---- session (wizard logic without the GUI) --------------------------------

CalFakeColor(x, y) {
    return 0x100000 + x
}

Test_Calibrate_session_point_and_rect_clicks() {
    d := CalTempDir()
    old := Pixel._getter
    try {
        Pixel._getter := CalFakeColor
        Calibrate.Use(d "\cal.json")
        s := Calibrate.NewSession(Calibrate.ResolveIds("inv_open,chat_rect,inv_use"))
        AssertEq(s.Current()["id"], "inv_open", "start")
        s.Capture(40, 50)
        AssertEq(Calibrate.Point("inv_open").color, 0x100028, "sampled at click")
        AssertEq(s.Current()["id"], "chat_rect", "advanced")
        s.Capture(500, 600)                                     ; first corner (bottom-right first)
        AssertEq(Calibrate.Rect("chat_rect"), "", "half rect not stored")
        AssertEq(s.Current()["id"], "chat_rect", "still waiting")
        s.Capture(100, 200)
        r := Calibrate.Rect("chat_rect")
        AssertEq(r.x, 100, "x")
        AssertEq(r.y, 200, "y")
        AssertEq(r.w, 400, "w")
        AssertEq(r.h, 400, "h")
        AssertEq(s.Current()["id"], "inv_use", "advanced after rect")
        s.Capture(7, 8)
        AssertTrue(s.IsDone(), "done")
        AssertEq(s.Count(), 3, "recorded count")
        AssertTrue(!s.WasCancelled(), "not cancelled")
        ; clicks after done are ignored
        s.Capture(1, 1)
        AssertEq(Calibrate.Point("inv_use").x, 7, "post-done click ignored")
    } finally {
        Pixel._getter := old
        CalCleanup(d)
    }
}

Test_Calibrate_session_degenerate_second_click_ignored() {
    d := CalTempDir()
    old := Pixel._getter
    try {
        Pixel._getter := CalFakeColor
        Calibrate.Use(d "\cal.json")
        s := Calibrate.NewSession(Calibrate.ResolveIds("chat_rect"))
        s.Capture(100, 100)
        s.Capture(100, 300)                                     ; same x -> zero width
        AssertTrue(!s.IsDone(), "still waiting")
        AssertEq(Calibrate.Rect("chat_rect"), "", "nothing stored")
        s.Capture(200, 300)
        AssertTrue(s.IsDone(), "done after valid corner")
        AssertEq(Calibrate.Rect("chat_rect").w, 100, "w from first corner")
    } finally {
        Pixel._getter := old
        CalCleanup(d)
    }
}

Test_Calibrate_session_skip_redo_cancel() {
    d := CalTempDir()
    old := Pixel._getter
    try {
        Pixel._getter := CalFakeColor
        Calibrate.Use(d "\cal.json")
        s := Calibrate.NewSession(Calibrate.ResolveIds("inv_open,chat_rect,inv_use"))
        s.Skip()
        AssertEq(Calibrate.Point("inv_open"), "", "skip stores nothing")
        AssertEq(s.Current()["id"], "chat_rect", "skip advances")
        s.Capture(1, 1)
        s.Redo()                                              ; drops the pending corner
        s.Capture(50, 60)
        AssertEq(Calibrate.Rect("chat_rect"), "", "redo discarded first corner")
        s.Capture(10, 20)
        AssertEq(Calibrate.Rect("chat_rect").x, 10, "rect from post-redo clicks")
        AssertEq(s.Current()["id"], "inv_use", "now on third")
        s.Redo()                                              ; no pending corner -> back one step
        AssertEq(s.Current()["id"], "chat_rect", "redo goes back")
        s.Cancel()
        AssertTrue(s.IsDone() && s.WasCancelled(), "cancelled")
        AssertEq(Calibrate.Rect("chat_rect").x, 10, "earlier results kept after cancel")
        s.Capture(1, 1)
        AssertEq(Calibrate.Rect("chat_rect").x, 10, "click after cancel ignored")
    } finally {
        Pixel._getter := old
        CalCleanup(d)
    }
}

Test_Calibrate_session_save_failure_reported_not_fatal() {
    d := CalTempDir()
    old := Pixel._getter
    try {
        Pixel._getter := CalFakeColor
        p := d "\cal.json"
        DirCreate(p)
        Calibrate.Use(p)
        s := Calibrate.NewSession(Calibrate.ResolveIds("inv_open"))
        s.Capture(3, 4)
        AssertTrue(s.LastError() != "", "error surfaced")
        AssertTrue(!InStr(s.LastError(), d), "no paths leaked into UI text? (message only)")
        AssertEq(Calibrate.Point("inv_open").x, 3, "kept in memory")
    } finally {
        Pixel._getter := old
        CalCleanup(d)
    }
}

; ---- signature steps (kind "sig", 12b) ------------------------------------

CalSig(cells) => "s1:4x2:170:" cells

Test_Calibrate_sig_store_roundtrip() {
    d := CalTempDir()
    try {
        p := d "\cal.json"
        Calibrate.Use(p)
        Calibrate.SetSig("inv_amount_one", 820, 790, 680, 750, CalSig("09900000"))   ; reversed corners
        Calibrate.Use(p)                                                          ; reload from disk
        s := Calibrate.Sig("inv_amount_one")
        AssertEq(s.x, 680, "x")
        AssertEq(s.y, 750, "y")
        AssertEq(s.w, 140, "w")
        AssertEq(s.h, 40, "h")
        AssertEq(s.sig, CalSig("09900000"), "sig kept")
        AssertEq(Calibrate.Rect("inv_amount_one"), "", "sig step is not a rect")
        AssertEq(Calibrate.Point("inv_amount_one"), "", "sig step is not a point")
        Calibrate.SetRect("chat_rect", 1, 2, 30, 40)
        AssertEq(Calibrate.Sig("chat_rect"), "", "rect step is not a sig")
        AssertEq(Calibrate.Sig("nope"), "", "missing sig")
        threw := false
        try Calibrate.SetSig("inv_amount_one", 1, 1, 50, 50, "garbage")
        catch ValueError
            threw := true
        AssertTrue(threw, "malformed sig rejected")
        AssertEq(Calibrate.Sig("inv_amount_one").sig, CalSig("09900000"), "old value kept")
        ; metadata lists the sig kind
        j := Json.Parse(FileRead(p, "UTF-8"))
        AssertEq(j["steps"]["inv_amount_one"]["sig"], CalSig("09900000"), "sig on disk")
    } finally {
        CalCleanup(d)
    }
}

Test_Calibrate_sig_malformed_entry_ignored() {
    d := CalTempDir()
    try {
        p := d "\cal.json"
        FileAppend('{"steps":{"a":{"x":1,"y":2,"w":10,"h":5,"sig":"s1:2x2:170:12"},"b":{"x":1,"y":2,"w":10,"h":5,"sig":"s1:2x1:170:12"},"c":{"x":1,"y":2,"w":0,"h":5,"sig":"s1:2x1:170:12"}}}', p, "UTF-8-RAW")
        Calibrate.Use(p)
        AssertEq(Calibrate.Sig("a"), "", "cell count mismatch")
        AssertEq(Calibrate.Sig("b").sig, "s1:2x1:170:12", "good sig entry")
        AssertEq(Calibrate.Sig("c"), "", "zero width")
    } finally {
        CalCleanup(d)
    }
}

; 8x4 pixels: background bg, bright (white) pixels in the given columns.
CalPx(bg, brightCols*) {
    px := []
    Loop 4 {
        Loop 8 {
            x := A_Index - 1
            on := false
            for c in brightCols
                on := on || (c = x)
            px.Push(on ? 0xF0F0F0 : bg)
        }
    }
    return px
}

Test_Pixel_signature_compare() {
    one := Pixel.SigFromPixels(CalPx(0x202020, 2, 3), 8, 4, 4, 2, 170)
    AssertEq(one, "s1:4x2:170:09000900", "a '1' in column cell 2")
    ; a brighter world behind the box (still under the threshold) changes nothing
    AssertEq(Pixel.SigFromPixels(CalPx(0x909090, 2, 3), 8, 4, 4, 2, 170), one, "background change ignored")
    ; half-covered cell: 2 of 4 px bright -> round(4.5) = 5
    AssertEq(Pixel.SigFromPixels(CalPx(0x202020, 2), 8, 4, 4, 2, 170), "s1:4x2:170:05000500", "partial cell")
    fifteen := Pixel.SigFromPixels(CalPx(0x202020, 2, 3, 5, 6), 8, 4, 4, 2, 170)
    AssertTrue(Pixel.SigMatch(one, one), "same matches")
    AssertTrue(!Pixel.SigMatch(fifteen, one), "extra digit does not match")
    AssertTrue(!Pixel.SigMatch(Pixel.SigFromPixels(CalPx(0x202020), 8, 4, 4, 2, 170), one), "empty box does not match")
    AssertTrue(Pixel.SigMatch("s1:4x2:170:07000900", one, 2), "within tol")
    AssertTrue(!Pixel.SigMatch("s1:4x2:170:06000900", one, 2), "beyond tol")
    AssertTrue(!Pixel.SigMatch("s1:2x4:170:09000900", one), "grid differs")
    AssertTrue(!Pixel.SigMatch("s1:4x2:160:09000900", one), "threshold differs")
    AssertTrue(!Pixel.SigMatch("", one) && !Pixel.SigMatch(one, "") && !Pixel.SigMatch("junk", "junk"), "malformed never matches")
    AssertEq(Pixel.SigMaxDiff("s1:4x2:170:35003500", "s1:4x2:170:30003000"), 5, "max diff")
    AssertEq(Pixel.SigL1("s1:4x2:170:35003500", "s1:4x2:170:30003000"), 10, "L1")
    AssertEq(Pixel.SigL1("s1:4x2:170:35003500", "s1:2x4:170:30003000"), -1, "L1 grid mismatch")
    ; closer-to-target rule with near-margin values (empty E, one O, "11" T)
    E := "s1:4x2:170:30003000", O := "s1:4x2:170:35003500", T := "s1:4x2:170:35203520"
    AssertTrue(Pixel.SigCloser(O, O, E), "exact one accepted")
    AssertTrue(Pixel.SigCloser("s1:4x2:170:35103500", O, E), "one with 1 noise accepted")
    AssertTrue(Pixel.SigMatch(T, O, 2), "'11' is within per-cell tol of '1' ...")
    AssertTrue(!Pixel.SigCloser(T, O, E), "... but rejected by the L1 limit")
    AssertTrue(!Pixel.SigCloser("s1:4x2:170:33003300", O, E), "dim '1' halfway to empty rejected")
    AssertTrue(!Pixel.SigCloser(E, O, E), "empty is not one")
    AssertTrue(Pixel.SigCloser(E, E, O), "empty is empty")
    AssertTrue(!Pixel.SigCloser(O, E, O), "one is not empty")
    ; margin rule alone: target and other close together, live within tol
    ; and sumTol of the target but not clearly closer to it
    E2 := "s1:4x2:170:30003000", O2 := "s1:4x2:170:33003300"
    AssertTrue(!Pixel.SigCloser("s1:4x2:170:32003200", O2, E2), "not clearly closer -> rejected")
    AssertTrue(Pixel.SigCloser(O2, O2, E2), "exact still accepted (margin 6)")
    AssertTrue(Pixel.SigValid(one), "valid with ink")
    AssertTrue(!Pixel.SigValid("s1:4x2:170:00000000"), "flat is not valid")
    AssertTrue(!Pixel.SigValid("s1:4x2:170:0900"), "wrong length is not valid")
    ; through the grabber, with the stored sig's grid
    old := Pixel._grabber
    try {
        Pixel._grabber := (x, y, w, h) => (w = 8 && h = 4) ? CalPx(0x202020, 2, 3) : []
        AssertEq(Pixel.Signature(10, 20, 8, 4, 4, 2, 170), one, "Signature via grabber")
        AssertEq(Pixel.SigLike(one, 10, 20, 8, 4), one, "SigLike reuses grid")
        AssertEq(Pixel.SigLike("junk", 10, 20, 8, 4), "", "SigLike of junk")
        AssertEq(Pixel.Signature(10, 20, 9, 4, 4, 2, 170), "", "grab size mismatch -> empty")
        Pixel._grabber := CalThrowGrab
        AssertEq(Pixel.Signature(10, 20, 8, 4, 4, 2, 170), "", "grab error -> empty")
    } finally {
        Pixel._grabber := old
    }
}

CalThrowGrab(*) {
    throw Error("boom")
}

; ---- shipped data file -----------------------------------------------------

Test_Calibrate_shipped_file_is_empty_with_metadata() {
    path := A_ScriptDir "\..\data\calibration.json"
    AssertTrue(FileExist(path), "data\calibration.json exists")
    j := Json.Parse(FileRead(path, "UTF-8"))
    AssertEq(j["steps"].Count, 0, "no recorded steps shipped")
    ids := []
    for e in j["stepList"] {
        AssertTrue(e.Has("id") && e.Has("prompt") && e.Has("kind"), "metadata fields")
        ids.Push(e["id"])
    }
    AssertTrue(CalHas(ids, "chat_rect"), "metadata lists chat_rect")
    AssertTrue(CalHas(ids, "fisher_item_lucky_potion"), "metadata lists default potions")
    AssertTrue(CalHas(ids, "stella_dialog"), "metadata lists stella_dialog")
    AssertTrue(CalHas(ids, "inv_items_tab"), "metadata lists inv_items_tab")
    ; the shipped metadata lists the same ids, in the same order, as Calibrate.Steps()
    d := CalTempDir()
    try {
        Calibrate.Use(d "\cal.json")
        want := CalIds(Calibrate.Steps())
        AssertEq(ids.Length, want.Length, "metadata step count")
        for i, id in want
            AssertEq(ids[i], id, "metadata step " i)
    } finally
        CalCleanup(d)
}
; The shipped 2560x1440 / 100% preset (the owner's calibration) is used when
; there is no calibration yet; a real one, or a broken one, is never replaced.
Test_Calibrate_PresetFillsAnEmptyCalibration() {
    d := CalTempDir()
    old := Calibrate.SystemFn
    Calibrate.SystemFn := () => {w: 2560, h: 1440, scale: 100}     ; the preset's display (the first-run rule)
    try {
        DirCreate(d "\presets")
        FileAppend('{"version": 1, "steps": {"rod": {"x": 10, "y": 20, "color": "0xFFFFFF"}}}', d "\presets\calibration_2560x1440_100.json", "UTF-8")
        ; missing file -> preset
        Calibrate.Use(d "\calibration.json")
        AssertEq(Calibrate.Point("rod").x, 10, "missing: the preset is used")
        AssertTrue(!FileExist(d "\calibration.json"), "read only: nothing written at load")
        ; the shipped empty file -> preset
        FileAppend('{"version": 1, "stepList": [], "steps": {}}', d "\calibration.json", "UTF-8")
        Calibrate.Use(d "\calibration.json")
        AssertEq(Calibrate.Point("rod").y, 20, "empty: the preset is used")
        ; a real calibration is kept
        FileDelete(d "\calibration.json")
        FileAppend('{"version": 1, "steps": {"rod": {"x": 99, "y": 98, "color": "0xFFFFFF"}}}', d "\calibration.json", "UTF-8")
        Calibrate.Use(d "\calibration.json")
        AssertEq(Calibrate.Point("rod").x, 99, "own calibration kept")
        ; a broken file is not replaced
        FileDelete(d "\calibration.json")
        FileAppend('{broken', d "\calibration.json", "UTF-8")
        Calibrate.Use(d "\calibration.json")
        AssertEq(Calibrate.Point("rod"), "", "broken: not replaced by the preset")
    } finally {
        Calibrate.SystemFn := old
        CalCleanup(d)
    }
}

Test_Calibrate_ShippedPresetIsAFullCalibration() {
    path := A_ScriptDir "\..\data\presets\calibration_2560x1440_100.json"
    AssertTrue(FileExist(path), "preset shipped")
    j := Json.Parse(FileRead(path, "UTF-8"))
    AssertTrue(j["steps"].Count >= 30, "preset has the recorded steps")
}
