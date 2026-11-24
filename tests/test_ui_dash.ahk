#Requires AutoHotkey v2.0
; Dashboard / overlay tests that need real GUI objects.
; NOTE: these build the real Dashboard / Overlay windows but NEVER show them
; (hidden, no focus change, nothing on screen). They are the only UI tests that
; create windows; needed to prove every page binds to Config/data.
; Scratch config dirs under A_Temp (copies of data\*.json) only, never the
; repo / user settings.ini. Potion names are read from the data, not hardcoded.
#Include ..\lib\ui\Dashboard.ahk
#Include ..\lib\ui\Overlay.ahk
#Include ..\lib\tasks\Craft.ahk
#Include ..\lib\ui\Wizard.ahk

UiDashTmp() {
    d := A_Temp "\vesper_uidash_" A_TickCount "_" Random(100000, 999999)
    DirCreate(d "\data")
    src := RegExReplace(A_LineFile, "\\tests\\[^\\]+$", "") "\data"
    for n in ["biomes", "potions", "quests", "merchants"]
        FileCopy(src "\" n ".json", d "\data\" n ".json", 1)
    return d
}

UiDashFind(arr, name) {
    for e in arr {
        if (e["name"] = name)
            return e
    }
    return ""
}

; -> {all: [names], locked: first locked name}
UiDashPotions(cfg) {
    all := [], locked := ""
    for e in cfg.Data("potions")["potions"] {
        all.Push(e["name"])
        if (locked = "" && !(e.Has("locked") && e["locked"] = 0))
            locked := e["name"]
    }
    return {all: all, locked: locked}
}

; What CraftTask (lib\tasks\Craft.ahk) reads as a potion's quantity.
UiDashCraftQty(cfg, name) => CraftTask.Prototype._Qty.Call({_env: {cfg: cfg}}, name)

; row of the ListView whose first cell is id (0 = none)
UiDashRow(lv, id) {
    Loop lv.GetCount()
        if (lv.GetText(A_Index, 1) = id)
            return A_Index
    return 0
}

UiDashClose(g) {
    Anim.Reset()                      ; the Dashboard set gateFn / enabledFn
    if !IsObject(g)
        return
    if HasMethod(g, "Destroy") {
        g.Destroy()
        return
    }
    try Theme.Forget(g._gui)
    try g._gui.Destroy()
}

Test_Dashboard_TabsSaveAndReload() {
    dir := UiDashTmp()
    d := "", d2 := ""
    hook := "https://discord.com/api/webhooks/111111111111111111/TOKENroundtrip_wxyz"
    link := "https://www.roblox.com/share?code=SECRETCODE123&type=Server"
    try {
        cfg := Config.Load(dir)
        pn := UiDashPotions(cfg)
        AssertTrue(pn.all.Length >= 3 && pn.locked != "", "scratch data has potions and a locked one")
        pCraft := GameLists.Shop[3], pTarget := GameLists.Recipes[2], pBiome := pn.all[1], pLocked := pn.locked
        changed := [0]
        d := Dashboard(cfg, Map("potionsChanged", () => changed[1]++))
        AssertEq(d.Ctrl("General.sellEvery").Value, "15", "fishing loaded default")

        d.Ctrl("General.sellEvery").Value := "22"
        d.Ctrl("General.sellAll").Value := 1
        AssertTrue(d.SavePage("Fishing"), "fishing saved")

        d.Ctrl("craft:" pCraft).Value := 1
        d.Ctrl("craftqty:" pCraft).Value := "4"
        d.Ctrl("Craft.craftTarget").Choose(pTarget)
        AssertTrue(d.SavePage("Craft"), "craft saved")

        d.Ctrl("privateServer").Value := link
        d.Ctrl("Medal.clipHotkey").Value := "F6"
        d.Ctrl("General.questIntervalMin").Value := "45"
        AssertTrue(d.SavePage("Settings"), "settings saved")
        AssertTrue(d.SavePage("Clips"), "clips saved")
        AssertEq(d.Ctrl("privateServer").Value, "", "secret edit cleared after save")
        AssertEq(d.Ctrl("privateServerMask").Text, UiLogic.MaskSecret(link), "secret shown masked only")

        d.HookAdd()
        d.Ctrl("hook1.name").Value := "Main"
        d.Ctrl("hook1.url").Value := hook
        d.Ctrl("hook1.men").Value := "424242"
        d.Ctrl("hook1.ev1").Value := 1     ; biome
        AssertTrue(d.SavePage("Webhooks"), "webhooks saved")
        AssertEq(d.Ctrl("hook1.url").Value, "", "url edit cleared after save")
        AssertEq(d.Ctrl("hook1.mask").Text, UiLogic.MaskSecret(hook), "url masked")
        d.Ctrl("hook1.url").Value := "https://evil.example/not-a-hook"
        d.SavePage("Webhooks")
        AssertEq(cfg.Webhooks()[1]["url"], hook, "invalid url does not replace saved one")

        d.Ctrl("merch.name").Value := "Some Item"
        d.Ctrl("merch.qty").Value := "3"
        d.MerchAdd()
        d.Ctrl("merch.name").Value := "Paused Item"
        d.MerchAdd()
        d.Ctrl("merch:Mari").Modify(2, "Select")
        AssertTrue(d.MerchPause(), "row 2 paused")
        AssertTrue(InStr(d.Ctrl("merch:Mari").GetText(2), "(Paused)"), "the row shows it is paused")
        AssertEq(d.Ctrl("merch.pause").Text, "Resume", "the button turns into Resume")
        AssertTrue(d.SavePage("Merchants"), "merchants saved")

        AssertTrue(d.SelectBiome("WINDY"), "select biome")
        d.Ctrl("biomeRare").Flip()
        d.Ctrl("bpDdl").Choose(pBiome)
        d.Ctrl("bpQty").Value := "2"
        d.BiomePotionAdd()
        n0 := changed[1]
        AssertTrue(d.SavePage("Biomes & Potions"), "biomes saved")
        AssertEq(changed[1], n0 + 1, "potionsChanged after biomes/caps save")

        tv := d.Ctrl("questTree")
        firstQuest := tv.GetChild(tv.GetChild(0))
        tv.Modify(firstQuest, "-Check")
        AssertTrue(d.SavePage("Quests"), "quests saved")

        AssertTrue(d.SelectPotion(pLocked), "select potion")
        live := UiDashFind(cfg.Data("potions")["potions"], pLocked)
        ; unsaved page caps must neither appear in nor ride along with an unlock
        d.Ctrl("capDay").Value := "77"
        d._PotionCaps()
        asked := [""]
        d._confirm := (title, text) => (asked[1] := text, false)
        n0 := changed[1]
        AssertEq(d.UnlockSelected(), false, "cancelled unlock")
        AssertEq(changed[1], n0, "no potionsChanged on cancel")
        AssertTrue(InStr(asked[1], pLocked), "dialog names potion")
        AssertTrue(RegExMatch(asked[1], live["perDay"] "\D+per day") && !InStr(asked[1], "77"), "dialog shows live saved caps")

        ; ---- reload from disk ----
        c2 := Config.Load(dir)
        AssertEq(c2.Get("General.sellEvery", 0), 22, "sellEvery persisted")
        AssertEq(c2.Get("General.sellAll", 0), 1, "sellAll persisted")
        AssertTrue(InStr(c2.Get("Craft.potions", ""), pCraft), "craft potion persisted")
        qid := SubStr(Calibrate.PotionId(pCraft), StrLen(Calibrate.PotionPrefix) + 1)
        AssertEq(c2.Get("Craft.qty_" qid, 0), 4, "craft qty_<id> persisted")
        AssertEq(UiDashCraftQty(c2, pCraft), 4, "CraftTask reads the saved qty")
        AssertEq(c2.Get("Craft.craftTarget", ""), pTarget, "craftTarget persisted (CraftTask key)")
        AssertEq(c2.Get("CraftQty." pCraft, "none"), "none", "no [CraftQty] section")
        AssertEq(c2.Get("General.privateServer", ""), link, "private link persisted")
        AssertEq(c2.Get("Medal.clipHotkey", ""), "F6", "medal hotkey persisted")
        AssertEq(c2.Get("General.questIntervalMin", 0), 45, "interval persisted")
        AssertEq(c2.Get("General.dryRun", -1), 1, "dry run untouched")
        h := c2.Webhooks()[1]
        AssertEq(h["name"], "Main", "hook name")
        AssertEq(h["url"], hook, "hook url")
        AssertEq(h["mention"], "424242", "hook mention")
        AssertEq(h["events"][1], "biome", "hook first event")
        m := c2.Data("merchants")["Mari"][1]
        AssertEq(m["name"] "|" m["qty"], "Some Item|3", "merchant item (found by name in the shop, no position)")
        AssertEq(m.Has("x"), false, "no x/y stored")
        m2 := c2.Data("merchants")["Mari"][2]
        AssertEq(m2["name"] "|" UiLogic.MerchPaused(m2), "Paused Item|1", "paused item kept on the list, paused")
        AssertEq(UiLogic.MerchPaused(m), false, "the other item is not paused")
        w := UiDashFind(c2.Data("biomes")["biomes"], "WINDY")
        AssertEq(w["rare"], 1, "windy rare")
        AssertEq(w["potions"][1]["name"] "|" w["potions"][1]["qty"], pBiome "|2", "biome potion")
        AssertEq(c2.Data("quests")["types"][1]["quests"][1]["enabled"], 0, "quest unticked")
        AssertEq(UiDashFind(c2.Data("potions")["potions"], pLocked)["locked"], 1, "cancel leaves locked on disk")

        d._confirm := (title, text) => true
        n0 := changed[1]
        AssertEq(d.UnlockSelected(), true, "confirmed unlock")
        AssertEq(changed[1], n0 + 1, "potionsChanged on unlock")
        onDisk := UiDashFind(Config.Load(dir).Data("potions")["potions"], pLocked)
        AssertEq(onDisk["locked"], 0, "unlock saved")
        AssertTrue(onDisk["perDay"] != 77, "unsaved caps not saved by unlock")
        d.RelockSelected()
        AssertEq(changed[1], n0 + 2, "potionsChanged on relock")
        AssertEq(UiDashFind(Config.Load(dir).Data("potions")["potions"], pLocked)["locked"], 1, "relock saved")

        ; revert = reload saved values into the page
        d.Ctrl("General.sellEvery").Value := "99"
        d.RevertPage("Fishing")
        AssertEq(d.Ctrl("General.sellEvery").Value, "22", "revert")

        ; a fresh dashboard shows the saved values
        d2 := Dashboard(c2, Map())
        AssertEq(d2.Ctrl("General.sellEvery").Value, "22", "reload fishing")
        AssertEq(d2.Ctrl("craft:" pCraft).Value, 1, "reload craft")
        AssertEq(d2.Ctrl("craftqty:" pCraft).Value, "4", "reload craft qty")
        AssertEq(d2.Ctrl("Craft.craftTarget").Text, pTarget, "reload craft target")
        AssertEq(d2.Ctrl("hook1.mask").Text, UiLogic.MaskSecret(hook), "reload hook mask")
        AssertEq(d2.Ctrl("hook1.url").Value, "", "reload never fills url")
        AssertEq(d2.Ctrl("privateServer").Value, "", "reload never fills private link")

        ; log never shows secrets, even ones not shaped like URLs
        d.Log("joining " link " via " hook)
        d.Log("raw code SECRETCODE123&type=Server")
        lt := d.LogText()
        AssertTrue(!InStr(lt, "SECRETCODE") && !InStr(lt, "TOKENroundtrip"), "log scrubbed")
        Loop 230
            d.Log("line " A_Index)
        AssertEq(StrSplit(d.LogText(), "`r`n").Length, 200, "log capped at 200")
    } finally {
        UiDashClose(d)
        UiDashClose(d2)
        try DirDelete(dir, true)
    }
}

; Biome potion dropdown lists potions.json ids: the three Godly Potions
; (same in-game name) are separate items and Add writes the id.
Test_Dashboard_BiomePotionById() {
    dir := UiDashTmp()
    d := ""
    try {
        cfg := Config.Load(dir)
        d := Dashboard(cfg, Map())
        items := ControlGetItems(d.Ctrl("bpDdl"))
        godly := 0
        for it in items
            godly += (SubStr(it, 1, 13) = "Godly Potion ")
        AssertEq(godly, 3, "three distinct Godly items")
        AssertTrue(d.SelectBiome("GLITCHED"), "select biome")
        d.Ctrl("bpDdl").Choose("Godly Potion (Sea)")
        d.Ctrl("bpQty").Value := "1"
        d.BiomePotionAdd()
        d.Ctrl("bpDdl").Choose("Godly Potion (Sky)")
        d.BiomePotionAdd()
        d.Ctrl("bpDdl").Choose("Lucky Potion")
        d.BiomePotionAdd()
        AssertTrue(d.SavePage("Biomes & Potions"), "saved")
        g := UiDashFind(Config.Load(dir).Data("biomes")["biomes"], "GLITCHED")
        AssertEq(g["potions"].Length, 3, "three entries")
        AssertEq(g["potions"][1]["name"], "Godly Potion (Sea)", "Sea id written")
        AssertEq(g["potions"][2]["name"], "Godly Potion (Sky)", "Sky id written")
        AssertEq(g["potions"][3]["name"], "Lucky Potion", "plain id = name")
        ; the ids written are exactly what PotionsTask / PotionSafety accept
        s := PotionSafety(Config.Load(dir).Data("potions"), dir "\data\pu.json")
        for e in g["potions"]
            AssertTrue(IsObject(s.Info(e["name"])), "known id " e["name"])
    } finally {
        UiDashClose(d)
        try DirDelete(dir, true)
    }
}

; Dry-run toggle: confirm hook (_confirmDry), banner, pills in sync.
; Scratch config in A_Temp only; never the repo / user settings.ini.
Test_Dashboard_DryRunToggle() {
    dir := UiDashTmp()
    d := ""
    try {
        cfg := Config.Load(dir)
        d := Dashboard(cfg, Map())
        p1 := d.Ctrl("dryRun1"), p2 := d.Ctrl("dryRun2")
        AssertEq(p1.Value p2.Value, "11", "both pills on")
        AssertEq(d.DryBannerShown(), false, "no banner while dry run on")
        asked := [0]
        d._confirmDry := () => (asked[1]++, false)
        p1.Flip()
        AssertEq(asked[1], 1, "turning off asks")
        AssertEq(cfg.Get("General.dryRun", -1), 1, "declined keeps dryRun=1")
        AssertEq(Config.Load(dir).Get("General.dryRun", -1), 1, "declined: disk still 1")
        AssertEq(p1.Value p2.Value, "11", "declined: pills back on")
        AssertEq(d.DryBannerShown(), false, "declined: no banner")
        d._confirmDry := () => (asked[1]++, true)
        p2.Flip()
        AssertEq(asked[1], 2, "asked again")
        AssertEq(Config.Load(dir).Get("General.dryRun", -1), 0, "accepted: 0 saved to disk")
        AssertEq(p1.Value p2.Value, "00", "accepted: both pills off")
        AssertEq(d.DryBannerShown(), true, "banner shown when off")
        d._confirmDry := () => (asked[1]++, false)
        p1.Flip()
        AssertEq(asked[1], 2, "turning back on needs no confirm")
        AssertEq(Config.Load(dir).Get("General.dryRun", -1), 1, "back on saved")
        AssertEq(p1.Value p2.Value, "11", "both pills on again")
        AssertEq(d.DryBannerShown(), false, "banner hidden again")
    } finally {
        UiDashClose(d)
        try DirDelete(dir, true)
    }
}

; Pause buttons read Resume while paused; overlay never activates.
Test_Ui_PauseRelabelAndOverlayNoActivate() {
    dir := UiDashTmp()
    d := "", o := ""
    try {
        cfg := Config.Load(dir)
        d := Dashboard(cfg, Map())
        o := Overlay(cfg, Map())
        d.SetStatus("Paused", "Fishing", "", false, 0, 1)
        o.SetStatus("Paused", "Fishing", "", false, 0, 1)
        AssertEq(d.Ctrl("pauseBtn1").Text, "Resume", "header pause -> Resume")
        AssertEq(d.Ctrl("pauseBtn2").Text, "Resume", "run page pause -> Resume")
        AssertEq(o.PauseText(), "Resume", "overlay pause -> Resume")
        d.SetStatus("Running", "Fishing", "", false, 0, 1)
        o.SetStatus("Running", "Fishing", "", false, 0, 1)
        AssertEq(d.Ctrl("pauseBtn1").Text, "Pause", "back to Pause")
        AssertEq(o.PauseText(), "Pause", "overlay back to Pause")
        ex := DllCall("GetWindowLongPtr", "Ptr", o.Hwnd, "Int", -20, "Ptr")
        AssertTrue(ex & 0x08000000, "overlay has WS_EX_NOACTIVATE")
        AssertTrue(ex & 0x8, "overlay is topmost")
    } finally {
        UiDashClose(d)
        UiDashClose(o)
        try DirDelete(dir, true)
    }
}

; ---- final fix wave ---------------------------------------------------------

Test_Dashboard_CalibrateCountsRectAndPointSteps() {
    dir := UiDashTmp()
    d := ""
    try {
        cfg := Config.Load(dir)
        Calibrate.Use(dir "\cal.json", cfg)
        Calibrate.SetPoint("inv_open", 42, 685, 0x112233)
        Calibrate.SetRect("inv_amount_box", 684, 752, 824, 792)
        d := Dashboard(cfg)
        n := Calibrate.Steps().Length
        opt := 0                                ; optional steps have built-in positions: ready unrecorded
        auto := 0                               ; steps the macro finds on screen: ready unrecorded too
        for s in Calibrate.Steps() {
            opt += Dashboard._CalIsOptional(s["id"])
            auto += (s["auto"] && !Dashboard._CalIsOptional(s["id"]))
        }
        AssertTrue(opt >= 3, "the Daily Rewards / Daily Quests steps are optional")
        AssertTrue(auto >= 8, "the Fisher tiles, Stella's Workshop and the Biome Selector's list are found on screen")
        AssertEq(d.Ctrl("calStatus").Text, (2 + opt + auto) " of " n " steps ready", "point and rect steps counted, optional and automatic ones ready")
        lv := d.Ctrl("calibrate")
        rows := Map()
        Loop lv.GetCount()
            rows[lv.GetText(A_Index, 1)] := lv.GetText(A_Index, 2)
        AssertTrue(InStr(rows["inv_amount_box"], "recorded"), "inv_amount_box shows recorded")
        AssertTrue(!rows.Has("inv_amount_one"), "no '1' signature step any more")
        AssertEq(rows["inv_tile2_rect"], "missing", "unrecorded step still missing")
        AssertEq(rows["daily_claim"], "default (optional)", "an optional step is not 'missing'")
        AssertEq(rows["cauldron_craft"], "default (optional)", "the Craft button is optional (found on screen when not recorded)")
        for id in ["fisher_item_lucky_potion", "cauldron_gui", "cauldron_search", "cauldron_close", "selector_list_rect", "selector_confirm"]
            AssertEq(rows[id], Chr(0x2713) " automatic", id ": found on screen, not 'missing'")
        AssertEq(rows["cauldron_add_all"], "missing", "Add All has no text to find it by: still asked for")
        ; recorded by hand it shows recorded like any other step
        Calibrate.SetRect("cauldron_gui", 1861, 222, 2447, 257)
        d._CalLoad()
        AssertTrue(InStr(lv.GetText(UiDashRow(lv, "cauldron_gui"), 2), "recorded"), "an automatic step recorded by hand shows recorded")
    } finally {
        UiDashClose(d)
        Calibrate.Use(A_Temp "\vesper_cal_unused.json")
        try DirDelete(dir, true)
    }
}

Test_Dashboard_ToolsRoutesAndTestEvents() {
    dir := UiDashTmp()
    d := ""
    try {
        cfg := Config.Load(dir)
        got := []
        cb := Map(
            "recordRoute", (name) => (cfg.SetData("routes", Map(name, Map("steps", [["w", "down", 100], ["w", "up", 0]], "_recorded", "2026-10-25 12:00")))
                , {ok: true, msg: "saved route '" name "' (2 steps)"}),
            "testEvent", (kind) => (got.Push(kind), "Test event refused: dry run is OFF."),
            "testRoute", (name) => (got.Push("route:" name), {ok: true, msg: "walked 2 steps and pressed F"}))
        d := Dashboard(cfg, cb)
        AssertEq(Dashboard.Pages[Dashboard.LogPage], "Log", "LogPage index still the Log page")
        AssertTrue(Dashboard.Pages.Length = Dashboard.Builders.Length && Dashboard.Subtitles.Length = Dashboard.Pages.Length, "pages, builders, subtitles aligned")
        for name in RouteRecorder.Names {
            AssertTrue(IsObject(d.Ctrl("routeBtn:" name)), "Record button for " name)
            AssertTrue(IsObject(d.Ctrl("routeTest:" name)), "Test button for " name)
            AssertEq(d.Ctrl("route:" name).Text, "not recorded", name " starts unrecorded")
        }
        d.RecordRoute("cauldron")
        AssertTrue(InStr(d.Ctrl("route:cauldron").Text, "2 steps"), "status refreshed after recording")
        AssertTrue(InStr(d.Ctrl("routeStatus").Text, "saved"), "result shown")
        AssertEq(d.Ctrl("route:cauldron").Text, "2 steps  (10-25 12:00)", "short date (no year) so it fits next to the buttons")
        d.TestRoute("cauldron")
        AssertEq(got[1], "route:cauldron", "Test callback fired for that route")
        AssertTrue(InStr(d.Ctrl("routeStatus").Text, "pressed F"), "test result shown")
        got := []
        msg := d.TestEvent("biome")
        AssertEq(got.Length, 1, "test event callback fired")
        AssertEq(got[1], "biome", "kind passed")
        AssertEq(d.Ctrl("testStatus").Text, msg, "refusal shown to the user")
        d.TestEvent("merchant")
        AssertEq(got[2], "merchant", "merchant kind passed")
    } finally {
        UiDashClose(d)
        try DirDelete(dir, true)
    }
}

Test_Dashboard_SellEveryMinClipHotkeyQuestDismiss() {
    dir := UiDashTmp()
    d := ""
    try {
        cfg := Config.Load(dir)
        d := Dashboard(cfg)
        d.Ctrl("General.sellEvery").Value := "0"
        AssertTrue(d.SavePage("Fishing"), "fishing saved")
        AssertEq(cfg.Get("General.sellEvery", 15), 1, "sellEvery clamped to 1")
        AssertEq(d.Ctrl("General.sellEvery").Value, "1", "field shows the clamped value")
        ; clip hotkey equal to the capture / recorder / macro keys is refused
        before := cfg.Get("Medal.clipHotkey", "F8")
        for bad in ["F4", "F7", "F3", "e"] {
            d.Ctrl("Medal.clipHotkey").Value := bad
            d.Ctrl("Medal.delaySec").Value := "44"
            AssertEq(d.SavePage("Clips"), false, "clip hotkey " bad " refused")
            AssertEq(cfg.Get("Medal.clipHotkey", "F8"), before, "refused value never reaches cfg")
            AssertTrue(cfg.Get("Medal.delaySec", 3) != 44, "nothing else saved either")
        }
        d.Ctrl("Medal.clipHotkey").Value := "F6"
        AssertTrue(d.SavePage("Clips"), "F6 accepted (capture key is F4)")
        AssertEq(cfg.Get("Medal.clipHotkey", "F8"), "F6", "saved")
        ; quests: never abandon by default
        AssertEq(d.Ctrl("quests.dismissDisabled").Value, 0, "dismiss unticked quests off by default")
        d.Ctrl("quests.dismissDisabled").Value := 1
        AssertTrue(d.SavePage("Quests"), "quests saved")
        AssertEq(cfg.Get("quests.dismissDisabled", 0), 1, "opt-in saved")
    } finally {
        UiDashClose(d)
        try DirDelete(dir, true)
    }
}

; ---- rebrand: one app-name constant drives every user-visible title -----------

Test_Rebrand_AppNameUsedEverywhere() {
    AssertEq(Brand.Name, "Moontide Macro", "app name constant")
    AssertEq(InStr(Brand.Name, "Vesper"), 0, "no Vesper in the app name")
    dir := UiDashTmp()
    d := "", o := ""
    root := RegExReplace(A_LineFile, "\\tests\\[^\\]+$", "")
    try {
        cfg := Config.Load(dir)
        d := Dashboard(cfg, Map())
        o := Overlay(cfg, Map())
        DetectHiddenWindows(true)
        AssertEq(WinGetTitle("ahk_id " d.Hwnd), Brand.Name " " Chr(0xB7) " " Credits.ByLine(), "dashboard window title")
        AssertEq(WinGetTitle("ahk_id " o.Hwnd), Brand.Name " Overlay", "overlay window title")
        src := FileRead(root "\lib\ui\Dashboard.ahk")
        AssertTrue(!InStr(src, "quiet watch") && !InStr(src, "composed"), "taglines removed")
        AssertTrue(FileExist(root "\assets\moontide_bg.png") != "", "background asset present")
        AssertTrue(FileGetSize(root "\assets\moontide_bg.png") < 300 * 1024, "background under 300 KB")
    } finally {
        UiDashClose(d)
        UiDashClose(o)
        try DirDelete(dir, true)
    }
}

Test_Dashboard_RouteResetToTheShippedDefault() {
    dir := UiDashTmp()
    try {
        cfg := Config.Load(dir)
        cfg.SetData("routes", Map("quest_board", Map("steps", [["w", "down", 5], ["w", "up", 0]], "_recorded", "2026-10-26 15:00")))
        d := Dashboard(cfg)
        AssertTrue(IsObject(d.Ctrl("routeReset:quest_board")) && IsObject(d.Ctrl("routeReset:cauldron")), "Reset buttons")
        defs := dir "\defaults.json"
        FileAppend('{"quest_board": {"steps": [["d", "down", 10], ["d", "up", 0], ["e", "down", 0]], "_recorded": "creator"}}', defs, "UTF-8")
        AssertTrue(d.ResetRoute("quest_board", defs), "reset")
        r := cfg.Data("routes")["quest_board"]
        AssertEq(r["steps"].Length, 3, "the default recording")
        AssertEq(r["_recorded"], "creator", "its stamp")
        saved := Json.Parse(FileRead(dir "\data\routes.json", "UTF-8"))
        AssertEq(saved["quest_board"]["steps"].Length, 3, "written to data\routes.json")
        AssertEq(d.ResetRoute("cauldron", defs), false, "no default for it: nothing changed")
        AssertEq(d.ResetRoute("quest_board", dir "\nope.json"), false, "no defaults file")
    } finally CfgTmpClean(dir)
    ; the shipped defaults are the creator's two recordings
    root := RegExReplace(A_LineFile, "\\tests\\[^\\]+$", "")
    AssertEq(RouteRecorder.DefaultsPath, root "\data\default_routes.json", "defaults file path")
    defs := Json.Parse(FileRead(RouteRecorder.DefaultsPath, "UTF-8"))
    for name in RouteRecorder.Names {
        if (name = "obby" || name = "memory_match" || name = "sell_to_fisher" || name = "fisher_to_fishing")
            continue                    ; the user records these; no shipped default (the sell walks fall back to vip / nonvip)
        AssertTrue(defs.Has(name) && defs[name]["steps"].Length > 0, name " is recorded in the shipped defaults")
    }
}

Test_Dashboard_CreditsPage() {
    dir := UiDashTmp()
    try {
        d := Dashboard(Config.Load(dir))
        AssertTrue(Dashboard.Pages[Dashboard.LogPage - 1] = "Credits", "Credits page before Log")
        AssertEq(d.Ctrl("credits.name").Text, "Vesper", "creator")
        AssertTrue(InStr(d.Ctrl("credits.discord").Text, ".unavailableuser."), "discord name")
        AssertTrue(InStr(d.Ctrl("credits.message").Text, "does anyone remember dolphsol?"), "message")
        AssertTrue(IsObject(d.Ctrl("credits.avatar")), "discord picture shown")
        AssertTrue(IsObject(d.Ctrl("credits.join")), "Discord server button")
        AssertTrue(FileExist(Theme.AssetPath("credits\avatar.png")), "avatar shipped")
    } finally CfgTmpClean(dir)
}

Test_Dashboard_CalibrateListFollowsTheSettings() {
    ; the list was once built before the settings were bound (the built-in
    ; Lucky + Speed Potion steps); the wizard then refused fisher_item_speed_potion
    dir := UiDashTmp()
    try {
        Calibrate.Use(dir "\cal.json")                 ; no settings bound yet
        cfg := Config.Load(dir)
        cfg.Set("Craft.potions", "Lucky Potion")
        d := Dashboard(cfg)
        Calibrate.Use(dir "\cal.json", cfg)            ; the app binds them
        for i, p in Dashboard.Pages
            if (p = "Calibrate")
                d.SelectPage(i)
        lv := d.Ctrl("calibrate")
        ids := []
        Loop lv.GetCount()
            ids.Push(lv.GetText(A_Index, 1))
        AssertTrue(UiDashHas(ids, "fisher_item_lucky_potion"), "the potion in the settings")
        AssertEq(UiDashHas(ids, "fisher_item_speed_potion"), false, "no step the wizard would refuse")
        for id in ids
            Calibrate.ResolveIds([id])                  ; throws on an unknown id
    } finally {
        Calibrate.Use(A_Temp "\vesper_cal_unused.json")
        CfgTmpClean(dir)
    }
}

UiDashHas(arr, v) {
    for x in arr
        if (x = v)
            return true
    return false
}

; ---- hubs and tabs ------------------------------------------------------------

UiDashPageIdx(name) {
    for i, p in Dashboard.Pages
        if (p = name)
            return i
    return 0
}

UiDashPos(c) {
    x := 0, y := 0, w := 0, h := 0
    c.GetPos(&x, &y, &w, &h)
    return {x: x, y: y, w: w, h: h}
}

; Spec 2026-11-18 section 6: the hubs, their icons and their pages in order;
; every page in exactly one hub.
Test_Hubs_EveryPageOnce() {
    want := [["Home", "home", "Run,Stats,Log"]
        , ["Farming", "bolt", "Fishing,Craft,Merchants,Limbo"]
        , ["Quests & events", "star", "Quests,Obby & Memory,Biome items,Hunting"]
        , ["Biomes & Potions", "moon", "Biomes & Potions,Potions"]
        , ["Discord & Clips", "bell", "Webhooks,Clips,Summary,Remote"]
        , ["Settings", "gear", "Settings,Look,Schedule,Profiles"]
        , ["Help", "info", "Check,Calibrate,Tools,Dev tools,Credits"]]
    AssertEq(Dashboard.Hubs.Length, want.Length, "seven hubs")
    for i, w in want {
        h := Dashboard.Hubs[i]
        AssertEq(h.name, w[1], "hub " i " name")
        AssertEq(h.icon, w[2], w[1] " icon")
        AssertEq(UiLogic.ArrayToCsv(h.pages), w[3], w[1] " pages in order")
    }
    AssertTrue(UiDashPageIdx("Potions") > 0 && UiDashPageIdx("Look") > 0, "the two new pages")
    AssertEq(Dashboard.Pages.Length, Dashboard.Builders.Length, "a builder per page")
    AssertEq(Dashboard.Pages.Length, Dashboard.Subtitles.Length, "a subtitle per page")
    AssertEq(Dashboard.Builders[UiDashPageIdx("Potions")], "_PagePotions", "Potions builder")
    AssertEq(Dashboard.Builders[UiDashPageIdx("Look")], "_PageLook", "Look builder")
    for name in Dashboard.Pages {
        n := 0, at := 0
        for i, h in Dashboard.Hubs
            for p in h.pages
                if (p = name)
                    n++, at := i
        AssertEq(n, 1, name " is in exactly one hub")
        AssertEq(Dashboard.HubOf(name), at, name " HubOf")
    }
    for h in Dashboard.Hubs
        for p in h.pages
            AssertTrue(UiDashPageIdx(p) > 0, p " (hub " h.name ") is a page")
    AssertEq(Dashboard.Pages[Dashboard.LogPage], "Log", "LogPage is the Log page")
}

; The two splits: a potion cap on Potions and a biome's potion on Biomes,
; each page saved on its own, and the data files hold both changes; saving
; one page never writes the other's unsaved edits. Look holds the theme,
; language and animations and saves them; Apply saves Look.
Test_Hubs_SplitsSaveTheSame() {
    dir := UiDashTmp()
    d := ""
    try {
        cfg := Config.Load(dir)
        pn := UiDashPotions(cfg)
        pBiome := pn.all[1], pCap := pn.all[2]
        changed := [0], restarts := [0]
        d := Dashboard(cfg, Map("potionsChanged", () => changed[1]++, "restart", () => restarts[1]++))
        ; where the controls live now
        for id in ["biomes", "biomeRare", "bpDdl", "bpQty"]
            AssertEq(d.PageOf(d.Ctrl(id)), "Biomes & Potions", id " on Biomes")
        for id in ["potions", "capBiome", "capDay", "capRun"]
            AssertEq(d.PageOf(d.Ctrl(id)), "Potions", id " on Potions")
        for id in ["look:list", "UI.lang", "look:apply", "look:note"]
            AssertEq(d.PageOf(d.Ctrl(id)), "Look", id " on Look")
        AssertEq(d.PageOf(d.Ctrl("UI.animations")._box), "Look", "UI.animations on Look")
        for id in ["privateServer", "General.vip", "recovery.enabled", "General.everyonePing"]
            AssertEq(d.PageOf(d.Ctrl(id)), "Settings", id " stays on Settings")
        AssertEq(Dashboard.TabLabel("Settings"), "General", "Settings tab reads General")
        ; both edits, neither saved
        AssertTrue(d.SelectPotion(pCap), "select potion")
        live := UiDashFind(cfg.Data("potions")["potions"], pCap)
        newDay := live["perDay"] + 7
        d.Ctrl("capDay").Value := String(newDay)
        d._PotionCaps()
        AssertTrue(d.SelectBiome("WINDY"), "select biome")
        d.Ctrl("biomeRare").Flip()
        d.Ctrl("bpDdl").Choose(pBiome)
        d.Ctrl("bpQty").Value := "2"
        d.BiomePotionAdd()
        AssertTrue(d._PageDirty(d._PageByName("Potions")), "Potions dirty")
        AssertTrue(d._PageDirty(d._PageByName("Biomes & Potions")), "Biomes dirty")
        ; Biomes saved: biomes.json only, the cap edit stays unsaved on Potions
        n0 := changed[1]
        AssertTrue(d.SavePage("Biomes & Potions"), "biomes saved")
        AssertEq(changed[1], n0 + 1, "potionsChanged after the biomes save")
        c2 := Config.Load(dir)
        w := UiDashFind(c2.Data("biomes")["biomes"], "WINDY")
        AssertEq(w["rare"], 1, "windy rare")
        AssertEq(w["potions"][1]["name"] "|" w["potions"][1]["qty"], pBiome "|2", "biome potion")
        AssertEq(UiDashFind(c2.Data("potions")["potions"], pCap)["perDay"], live["perDay"], "the unsaved cap is not written by the Biomes save")
        AssertTrue(d._PageDirty(d._PageByName("Potions")), "Potions still dirty")
        AssertEq(d.Ctrl("capDay").Value, String(newDay), "the cap edit is still on the page")
        ; Potions saved: the cap, and the biome change stays
        n0 := changed[1]
        AssertTrue(d.SavePage("Potions"), "potions saved")
        AssertEq(changed[1], n0 + 1, "potionsChanged after the potions save")
        c3 := Config.Load(dir)
        AssertEq(UiDashFind(c3.Data("potions")["potions"], pCap)["perDay"], newDay, "cap written")
        w := UiDashFind(c3.Data("biomes")["biomes"], "WINDY")
        AssertEq(w["rare"] "|" w["potions"][1]["name"], "1|" pBiome, "biome change kept")
        AssertEq(UiDashFind(c3.Data("potions")["potions"], pn.locked)["locked"], 1, "locks untouched by Save")
        ; a Biomes edit is never written by a Potions save, and Revert keeps the other page
        d.Ctrl("biomeRare").Flip()
        d.Ctrl("capRun").Value := "5"
        d._PotionCaps()
        AssertTrue(d.SavePage("Potions"), "potions saved again")
        AssertEq(UiDashFind(Config.Load(dir).Data("biomes")["biomes"], "WINDY")["rare"], 1, "the unsaved rare flip is not written by the Potions save")
        d.RevertPage("Biomes & Potions")
        AssertEq(d._PageDirty(d._PageByName("Biomes & Potions")), false, "Biomes reverted")
        AssertEq(UiDashFind(Config.Load(dir).Data("potions")["potions"], pCap)["perRun"], 5, "Potions save kept")
        ; Look: Settings never writes the theme; Look does; Apply saves Look
        d._lookAsk := (*) => true
        AssertTrue(d.LookSelect("Galaxy"), "Galaxy picked on Look")
        d.Ctrl("General.questIntervalMin").Value := "44"
        AssertTrue(d.SavePage("Settings"), "settings saved")
        AssertEq(Config.Load(dir).Get("UI.theme", ""), "Moontide", "Settings save leaves the theme")
        AssertEq(Config.Load(dir).Get("General.questIntervalMin", 0), 44, "Settings save writes General")
        AssertTrue(d.ApplyTheme(), "applied")
        AssertEq(Config.Load(dir).Get("UI.theme", ""), "Galaxy", "Apply saved the Look page")
        AssertEq(restarts[1], 1, "restart asked once")
        AssertEq(d._PageDirty(d._PageByName("Look")), false, "Look saved")
    } finally {
        Theme.Use("Moontide")
        UiDashClose(d)
        try DirDelete(dir, true)
    }
}

Test_Hubs_TabLabels() {
    AssertEq(Dashboard.TabLabel("Craft"), "Crafting", "Craft")
    AssertEq(Dashboard.TabLabel("Webhooks"), "Discord", "Webhooks")
    AssertEq(Dashboard.TabLabel("Tools"), "Routes", "Tools")
    AssertEq(Dashboard.TabLabel("Biomes & Potions"), "Biomes", "Biomes & Potions")
    AssertEq(Dashboard.TabLabel("Quests"), "Quests", "Quests")
    AssertEq(Dashboard.TabLabel("Dev tools"), "Dev tools", "Dev tools")
    AssertEq(Dashboard.TabLabel("Run"), "Overview", "Run")
    AssertEq(Dashboard.TabLabel("Settings"), "General", "Settings")
    AssertEq(Dashboard.TabLabel("Hunting"), "Limited", "Hunting")
    AssertEq(Dashboard.TabLabel("Look"), "Look", "Look")
    AssertEq(Dashboard.TabLabel("Potions"), "Potions", "Potions")
    AssertEq(Dashboard.TabLabel("Summary"), "Daily summary", "Summary")
    AssertEq(Dashboard.TabLabel("Check"), "Check & help", "Check")
}

Test_Hubs_SelectHubAndTab() {
    dir := UiDashTmp()
    d := ""
    try {
        d := Dashboard(Config.Load(dir))
        AssertEq(d.ActivePage, "Run", "opens on Home / Run")
        AssertEq(d.ActiveHub, 1, "Home hub")
        for i, h in Dashboard.Hubs
            AssertTrue(IsObject(d.Ctrl("hub:" h.name)), "sidebar entry " h.name)
        for p in Dashboard.Pages
            AssertTrue(IsObject(d.Ctrl("tab:" p)) && IsObject(d.Ctrl("tabDot:" p)), "tab and dot for " p)
        AssertEq(d.Ctrl("tab:Craft").Text, "Crafting", "tab shows its label")
        d.SelectHub(2)
        AssertEq(d.ActivePage, "Fishing", "Farming opens on its first tab")
        AssertTrue(d.Ctrl("General.sellEvery").Visible, "Fishing controls shown")
        AssertEq(d.Ctrl("merch.name").Visible, false, "Merchants controls hidden")
        AssertTrue(d.Ctrl("tab:Merchants").Visible && d.Ctrl("tab:Limbo").Visible, "Farming tabs shown")
        AssertEq(d.Ctrl("tab:Calibrate").Visible, false, "Help tabs hidden")
        d.SelectPage(UiDashPageIdx("Merchants"))
        AssertEq(d.ActivePage, "Merchants", "Merchants selected")
        AssertEq(d.ActiveHub, 2, "still Farming")
        AssertTrue(d.Ctrl("merch.name").Visible, "Merchants controls shown")
        AssertEq(d.Ctrl("General.sellEvery").Visible, false, "Fishing controls hidden")
        u := UiDashPos(d.Ctrl("tabUnderline")), t := UiDashPos(d.Ctrl("tab:Merchants"))
        AssertTrue(d.Ctrl("tabUnderline").Visible, "underline shown")
        AssertEq(u.x "," u.w, t.x "," t.w, "underline under the Merchants tab")
        AssertEq(u.y "," u.h, "130,2", "underline y 130 h 2")
        AssertEq(t.y "," t.h, "104,26", "tab strip y 104 h 26")
        d.SelectHub(1)
        AssertEq(d.ActivePage, "Run", "Home")
        AssertEq(d.Ctrl("tab:Merchants").Visible, false, "Farming tabs hidden on Home")
        d.SelectHub(2)
        AssertEq(d.ActivePage, "Merchants", "Farming reopens on its last tab")
        ; SelectPage of a page in another hub moves the hub too
        d.SelectPage(UiDashPageIdx("Clips"))
        AssertEq(d.ActiveHub, 5, "Clips -> Discord & Clips hub")
        AssertTrue(d.Ctrl("Medal.clipHotkey").Visible, "Clips controls shown")
        d.SelectPage(Dashboard.LogPage)
        AssertEq(d.ActiveHub, 1, "Log is on Home")
    } finally {
        UiDashClose(d)
        try DirDelete(dir, true)
    }
}

Test_Hubs_UnsavedEditsSurviveSwitching() {
    dir := UiDashTmp()
    d := ""
    try {
        cfg := Config.Load(dir)
        d := Dashboard(cfg)
        d.SelectPage(UiDashPageIdx("Merchants"))
        AssertEq(d.Ctrl("tabDot:Merchants").Visible, false, "no dot before an edit")
        lv := d.Ctrl("merch:Mari")
        n0 := lv.GetCount()
        d.Ctrl("merch.name").Value := "Hub Switch Item"
        d.MerchAdd()
        d.Ctrl("merch.name").Value := "typed, not added"
        AssertTrue(d.Ctrl("tabDot:Merchants").Visible, "dot after Add")
        d.SelectHub(4)
        AssertEq(d.ActiveHub, 4, "Setup hub")
        AssertEq(d.Ctrl("tabDot:Merchants").Visible, false, "dot hidden with its hub")
        d.SelectHub(2)
        AssertEq(d.ActivePage, "Merchants", "back on Merchants")
        AssertEq(d.Ctrl("merch.name").Value, "typed, not added", "typed text kept")
        AssertEq(lv.GetCount(), n0 + 1, "added row kept")
        AssertEq(lv.GetText(n0 + 1, 1), "Hub Switch Item", "the added item")
        AssertTrue(d.Ctrl("tabDot:Merchants").Visible, "dot still shown")
        AssertTrue(d.SavePage("Merchants"), "saved")
        AssertEq(d.Ctrl("tabDot:Merchants").Visible, false, "Save clears the dot")
        ; a bound control that differs from its loaded value
        d.SelectPage(UiDashPageIdx("Fishing"))
        d.Ctrl("General.sellEvery").Value := "37"
        d.SelectHub(3)
        d.SelectHub(2)
        AssertEq(d.ActivePage, "Fishing", "back on Fishing")
        AssertEq(d.Ctrl("General.sellEvery").Value, "37", "edit kept")
        AssertTrue(d.Ctrl("tabDot:Fishing").Visible, "dot on Fishing")
        AssertEq(d.Ctrl("tabDot:Merchants").Visible, false, "saved tab has no dot")
        d.RevertPage("Fishing")
        AssertEq(d.Ctrl("General.sellEvery").Value, "15", "reverted")
        AssertEq(d.Ctrl("tabDot:Fishing").Visible, false, "Revert clears the dot")
        ; typing the loaded value back clears it too
        d.Ctrl("General.sellEvery").Value := "16"
        d.SelectPage(UiDashPageIdx("Craft"))
        AssertTrue(d.Ctrl("tabDot:Fishing").Visible, "dot again")
        d.Ctrl("General.sellEvery").Value := "15"
        d.SelectPage(UiDashPageIdx("Fishing"))
        AssertEq(d.Ctrl("tabDot:Fishing").Visible, false, "same as loaded: no dot")
        ; a refused save keeps the dot
        d.SelectPage(UiDashPageIdx("Clips"))
        d.Ctrl("Medal.clipHotkey").Value := "F4"
        AssertEq(d.SavePage("Clips"), false, "F4 refused")
        AssertTrue(d.Ctrl("tabDot:Clips").Visible, "refused save keeps the dot")
    } finally {
        UiDashClose(d)
        try DirDelete(dir, true)
    }
}

Test_Hubs_MovedSections() {
    dir := UiDashTmp()
    d := ""
    try {
        cfg := Config.Load(dir)
        d := Dashboard(cfg)
        AssertEq(d.PageOf(d.Ctrl("Limbo.enabled")), "Limbo", "Limbo switch on the Limbo tab")
        AssertEq(d.PageOf(d.Ctrl("General.sellEvery")), "Fishing", "sellEvery still on Fishing")
        for k in ["Medal.enabled", "Medal.clipHotkey", "Medal.auraMinRarity", "Medal.auras"]
            AssertEq(d.PageOf(d.Ctrl(k)), "Clips", k " on the Clips tab")
        AssertEq(d.PageOf(d.Ctrl("General.everyonePing")), "Settings", "@everyone stays in Settings")
        AssertEq(d.PageOf(d.Ctrl("testEvent:biome")), "Dev tools", "fake biome button")
        AssertEq(d.PageOf(d.Ctrl("testEvent:merchant")), "Dev tools", "fake merchant button")
        AssertEq(d.PageOf(d.Ctrl("testStatus")), "Dev tools", "test status")
        AssertEq(d.PageOf(d.Ctrl("routeBtn:cauldron")), "Tools", "routes stay on Tools (Routes tab)")
        d.Ctrl("Limbo.enabled").Value := 1
        AssertTrue(d.SavePage("Limbo"), "Limbo saved on its own")
        AssertEq(Config.Load(dir).Get("Limbo.enabled", 0), 1, "Limbo.enabled persisted")
        d.Ctrl("Medal.delaySec").Value := "7"
        AssertTrue(d.SavePage("Clips"), "Clips saved")
        AssertEq(Config.Load(dir).Get("Medal.delaySec", 0), 7, "Medal.delaySec persisted")
        ; header layout and page content below it
        AssertEq(UiDashPos(d.Ctrl("hubTitle")).y, 66, "hub title y 66")
        for i, name in Dashboard.Pages {
            pd := UiDashPos(d.Ctrl("desc:" name))
            AssertEq(pd.y "," pd.h, "132,16", name " description y 132 h 16")
            for c in d._pages[i].ctrls {
                if (c.Hwnd = d.Ctrl("desc:" name).Hwnd)
                    continue
                AssertTrue(UiDashPos(c).y >= 152, name ": content at y >= 152 (" c.Type " y " UiDashPos(c).y ")")
            }
        }
    } finally {
        UiDashClose(d)
        try DirDelete(dir, true)
    }
}

; ---- the look (Task 4) ----------------------------------------------------------

; Sum of a ListView's column widths and its client width.
UiDashLvFit(lv) {
    sum := 0
    Loop lv.GetCount("Col")
        sum += SendMessage(0x101D, A_Index - 1, 0, lv)     ; LVM_GETCOLUMNWIDTH
    rc := Buffer(16, 0)
    DllCall("GetClientRect", "Ptr", lv.Hwnd, "Ptr", rc)
    return {cols: sum, client: NumGet(rc, 8, "Int")}
}

Test_Dashboard_MerchantNamesTitleCased() {
    dir := UiDashTmp()
    d := ""
    try {
        d := Dashboard(Config.Load(dir))
        d.SelectPage(UiDashPageIdx("Merchants"))
        lv := d.Ctrl("merch:Mari")
        d.Ctrl("merch.name").Value := "gear b"
        d.Ctrl("merch.qty").Value := "2"
        d.MerchAdd()
        AssertEq(lv.GetText(lv.GetCount(), 1), "Gear B", "list row title-cased on Add")
        lv.Modify(lv.GetCount(), "Select")
        d.Ctrl("merch.name").Value := "mixed potion"
        d._MerchUpdate()
        AssertEq(lv.GetText(lv.GetCount(), 1), "Mixed Potion", "title-cased on Update")
        d.Ctrl("merch.name").Value := "gear b"
        d.MerchAdd()
        AssertTrue(d.SavePage("Merchants"), "saved")
        mari := Config.Load(dir).Data("merchants")["Mari"]
        AssertEq(mari[mari.Length]["name"], "Gear B", "saved data name title-cased")
        AssertEq(mari[mari.Length - 1]["name"], "Mixed Potion", "updated row saved title-cased")
        ; no empty extra column: the last column fills the list
        for who in ["Mari", "Jester"] {
            f := UiDashLvFit(d.Ctrl("merch:" who))
            AssertEq(f.cols, f.client, who " columns fill the list width")
        }
        f := UiDashLvFit(d.Ctrl("potions"))
        AssertEq(f.cols, f.client, "potions columns fill the list width")
    } finally {
        UiDashClose(d)
        try DirDelete(dir, true)
    }
}

; Merchant and biome potion qty take "all" (2026-11-22 tester ask): typed in
; any case (or max), listed and saved as all, and the "?" says what it does.
Test_Dashboard_QtyAll() {
    dir := UiDashTmp()
    d := ""
    try {
        cfg := Config.Load(dir)
        pBiome := UiDashPotions(cfg).all[1]
        d := Dashboard(cfg)
        d.SelectPage(UiDashPageIdx("Merchants"))
        lv := d.Ctrl("merch:Mari")
        d.Ctrl("merch.name").Value := "lucky potion"
        d.Ctrl("merch.qty").Value := "All"
        d.MerchAdd()
        AssertEq(lv.GetText(lv.GetCount(), 2), "all", "merchant list shows all")
        d.Ctrl("merch.name").Value := "speed potion"
        d.Ctrl("merch.qty").Value := "max"
        d.MerchAdd()
        d.Ctrl("merch.name").Value := "mixed potion"
        d.Ctrl("merch.qty").Value := "7"
        d.MerchAdd()
        d._MerchSelect("Mari", lv, lv.GetCount() - 2, true)
        AssertEq(d.Ctrl("merch.qty").Value, "all", "selecting the row shows all")
        AssertTrue(d.SavePage("Merchants"), "merchants saved")
        mari := Config.Load(dir).Data("merchants")["Mari"]
        n := mari.Length
        AssertEq(mari[n - 2]["qty"] "|" mari[n - 1]["qty"] "|" mari[n]["qty"], "all|all|7", "saved all, all, 7")
        AssertTrue(MerchantTask.ParseItem(mari[n - 2]).all, "the task reads the saved all")
        ; biome potions
        AssertTrue(d.SelectBiome("WINDY"), "select biome")
        d.Ctrl("bpDdl").Choose(pBiome)
        d.Ctrl("bpQty").Value := "ALL"
        d.BiomePotionAdd()
        bp := d._lvBP
        AssertEq(bp.GetText(bp.GetCount(), 2), "all", "biome potion list shows all")
        AssertEq(d._BiomePotSummary(d._bio[d._bSel]), "1 (all owned)", "biome list summary")
        AssertEq(d._BiomePotSummary(Map("potions", [Map("name", "a", "qty", "all"), Map("name", "b", "qty", 3)])), "2 (3 uses + all)", "mixed summary")
        AssertEq(d._BiomePotSummary(Map("potions", [Map("name", "a", "qty", 2), Map("name", "b", "qty", 3)])), "2 (5 uses)", "numbers as before")
        AssertTrue(d.SavePage("Biomes & Potions"), "biomes saved")
        w := UiDashFind(Config.Load(dir).Data("biomes")["biomes"], "WINDY")
        AssertEq(w["potions"][w["potions"].Length]["qty"], "all", "saved all")
        AssertTrue(PotionsTask.IsAll(w["potions"][w["potions"].Length]["qty"]), "the potions task reads it as all")
        ; the "?" texts
        for page, text in Map("Merchants", "buy the whole stock", "Biomes & Potions", "within the potion safety caps") {
            found := false
            for c in d._pages[UiDashPageIdx(page)].ctrls
                found := found || InStr(Theme.HelpText(c), text)
            AssertTrue(found, page ": a help says " text)
        }
    } finally {
        UiDashClose(d)
        try DirDelete(dir, true)
    }
}

Test_Dashboard_EmptyListHint() {
    dir := UiDashTmp()
    d := ""
    try {
        FileDelete(dir "\data\merchants.json")
        FileAppend('{"Mari": [], "Jester": []}', dir "\data\merchants.json", "UTF-8")
        d := Dashboard(Config.Load(dir))
        d.SelectPage(UiDashPageIdx("Merchants"))
        h := d.Ctrl("merch.empty:Jester")
        AssertTrue(IsObject(h) && h.Visible, "empty Jester list shows its hint")
        AssertEq(h.Text, "Add what Jester should buy", "hint text")
        AssertEq(d.Ctrl("merch.empty:Mari").Text, "Add what Mari should buy", "Mari hint text")
        d.Ctrl("merch.who:Jester").Flip()
        d.Ctrl("merch.name").Value := "Lucky Potion"
        d.MerchAdd()
        AssertEq(d.Ctrl("merch:Jester").GetCount(), 1, "added to Jester")
        AssertEq(h.Visible, false, "hint hidden after adding an item")
        AssertTrue(d.Ctrl("merch:Jester").Visible, "list shown")
        AssertTrue(d.Ctrl("merch.empty:Mari").Visible, "Mari still empty: hint stays")
        ; hidden with its page, back with it
        d.SelectPage(UiDashPageIdx("Fishing"))
        AssertEq(d.Ctrl("merch.empty:Mari").Visible, false, "hint hidden on another tab")
        d.SelectPage(UiDashPageIdx("Merchants"))
        AssertTrue(d.Ctrl("merch.empty:Mari").Visible, "hint back on its tab")
        AssertEq(h.Visible, false, "Jester hint stays hidden")
    } finally {
        UiDashClose(d)
        try DirDelete(dir, true)
    }
}

Test_Dashboard_SwitchesArePills() {
    dir := UiDashTmp()
    d := ""
    try {
        d := Dashboard(Config.Load(dir))
        n := 0
        for b in d._binds {
            if (b.kind != "bool")
                continue
            n++
            AssertEq(b.ctrl._style, "pill", b.key " is a pill switch")
        }
        AssertTrue(n >= 15, "bool bindings found (" n ")")
        AssertEq(d.Ctrl("biomeRare")._style, "pill", "rare biome switch is a pill")
        crafts := 0
        for name in GameLists.Shop {
            if !IsObject(d.Ctrl("craft:" name))
                continue
            crafts++
            AssertEq(d.Ctrl("craft:" name)._style, "pill", "craft:" name " is a pill switch")
        }
        AssertTrue(crafts >= 1, "craft potion switches found (" crafts ")")
        AssertEq(d.Ctrl("hook1.on")._style, "pill", "hook1.on is a pill switch")
    } finally {
        UiDashClose(d)
        try DirDelete(dir, true)
    }
}

Test_Dashboard_NoLongMutedText() {
    dir := UiDashTmp()
    d := ""
    try {
        d := Dashboard(Config.Load(dir))
        tips := 0
        for i, name in Dashboard.Pages {
            d.SelectPage(i)
            skip := Map(d.Ctrl("desc:" name).Hwnd, 1)
            if IsObject(d._pages[i].status)
                skip[d._pages[i].status.Hwnd] := 1
            for k in ["calStatus", "routeStatus", "testStatus", "merch.status", "logCount"]
                if IsObject(d.Ctrl(k))
                    skip[d.Ctrl(k).Hwnd] := 1
            for c in d._pages[i].ctrls {
                if (Theme.HelpText(c) != "")
                    tips++
                if (c.Type != "Text" || !c.Visible || skip.Has(c.Hwnd) || Theme.RoleOf(c) != "muted")
                    continue
                AssertTrue(StrLen(c.Text) <= 90, name ": muted text of " StrLen(c.Text) " chars belongs in a help tip: " SubStr(c.Text, 1, 50))
            }
        }
        AssertTrue(tips >= 10, "long texts moved into help tips (" tips ")")
        AssertEq(d.Ctrl("routeStatus").Text, "", "Routes status starts empty (its help is a tip)")
        AssertEq(d.Ctrl("merch.status").Text, "", "Merchants status starts empty (its help is a tip)")
    } finally {
        UiDashClose(d)
        try DirDelete(dir, true)
    }
}

; A bound switch updates its tab dot, also when it already had a callback.
Test_Dashboard_BoundPillUpdatesDot() {
    dir := UiDashTmp()
    d := ""
    try {
        d := Dashboard(Config.Load(dir))
        d.SelectPage(UiDashPageIdx("Fishing"))
        dot := d.Ctrl("tabDot:Fishing")
        sw := d.Ctrl("General.sellAll")
        AssertEq(dot.Visible, false, "no dot at start")
        sw.Flip()
        AssertTrue(dot.Visible, "flip: dot shown")
        sw.Flip()
        AssertEq(dot.Visible, false, "flip back: dot hidden")
        ; a switch made with its own callback, then bound: both run
        hits := [0]
        page := d._PageByName("Fishing")
        c := Theme.Check(d._gui, 220, 600, "", 0, (*) => hits[1]++, "pill")
        d._curPage := page
        d._Bind("bool", "Test.chained", 0, c)
        d._curPage := ""
        d._Snap(page)
        c.Flip()
        AssertEq(hits[1], 1, "own callback ran")
        AssertTrue(dot.Visible, "chained: dot shown")
        c.Flip()
        AssertEq(hits[1], 2, "own callback ran again")
        AssertEq(dot.Visible, false, "chained: dot hidden")
    } finally {
        UiDashClose(d)
        try DirDelete(dir, true)
    }
}

; Every page's help tips sit inside a panel and nothing overlaps them.
Test_Dashboard_HelpTipsOnPanels() {
    dir := UiDashTmp()
    d := ""
    try {
        d := Dashboard(Config.Load(dir))
        inR := (a, b) => a.x >= b.x && a.y >= b.y && a.x + a.w <= b.x + b.w && a.y + a.h <= b.y + b.h
        ovR := (a, b) => !(a.x + a.w <= b.x || b.x + b.w <= a.x || a.y + a.h <= b.y || b.y + b.h <= a.y)
        for i, name in Dashboard.Pages {
            d.SelectPage(i)
            panels := []
            for c in d._pages[i].ctrls
                if Theme.IsPanel(c)
                    panels.Push(UiDashPos(c))
            for c in d._pages[i].ctrls {
                if (Theme.HelpText(c) = "" || d._hidden.Has(c.Hwnd))   ; a label too long for its "?" hides it
                    continue
                t := UiDashPos(c)
                AssertEq(t.w "," t.h, "16,16", name ": help tip is 16x16")
                inside := false
                for p in panels
                    inside := inside || inR(t, p)
                AssertTrue(inside, name ": help tip at " t.x "," t.y " sits on a panel")
                for o in d._pages[i].ctrls {
                    if (o.Hwnd = c.Hwnd || !o.Visible || Theme.IsPanel(o))
                        continue
                    AssertTrue(!ovR(t, UiDashPos(o)), name ": help tip at " t.x "," t.y " is not covered by a " o.Type " '" SubStr(o.Text, 1, 20) "'")
                }
            }
        }
    } finally {
        UiDashClose(d)
        try DirDelete(dir, true)
    }
}

; ---- animations (Task 5) ----------------------------------------------------
; The Dashboard constructor sets Anim.gateFn / enabledFn, so the fakes go in
; AFTER it; Anim.Reset() in finally puts the real engine back.

; Fake clock (r.t), timer recorder (r.timers: periods) and gate (r.open).
UiDashAnimRig(open := true) {
    r := {t: 0, timers: [], open: open}
    Anim.nowFn := () => r.t
    Anim.timerFn := (fn, ms) => r.timers.Push(ms)
    Anim.gateFn := () => r.open
    return r
}

UiDashTickTo(r, t) {
    r.t := t
    Anim.Tick()
}

; colour levels drawn by the pulse and every star (changes = they stepped)
UiDashAnimLevels(d) {
    s := d._pulseLvl ":" d._moonFrame
    for st in d._stars
        s .= ":" st.lvl
    return s
}

Test_Dash_UnderlineGlides() {
    dir := UiDashTmp()
    d := ""
    Anim.Reset()
    try {
        d := Dashboard(Config.Load(dir))
        d.SelectPage(UiDashPageIdx("Fishing"))        ; window hidden: gate closed, jumps
        u := d.Ctrl("tabUnderline")
        f := UiDashPos(d.Ctrl("tab:Fishing"))
        AssertEq(UiDashPos(u).x, f.x, "closed gate: underline at once under Fishing")
        r := UiDashAnimRig(true)
        d.SelectPage(UiDashPageIdx("Merchants"))
        q := UiDashPos(d.Ctrl("tab:Merchants"))
        AssertTrue(q.x > f.x, "Merchants tab is right of Fishing")
        xs := []
        for t in [0, 90, 180] {
            UiDashTickTo(r, t)
            xs.Push(UiDashPos(u).x)
        }
        AssertEq(xs[1], f.x, "t 0: still at Fishing")
        AssertTrue(xs[2] > xs[1] && xs[2] < q.x, "t 90: on the way (" xs[2] ")")
        AssertTrue(xs[3] >= xs[2], "monotonic")
        p := UiDashPos(u)
        AssertEq(p.x "," p.w "," p.y "," p.h, q.x "," q.w ",130,2", "t 180: exactly under Merchants")
        AssertEq(d.CoverShown(), false, "fade cover hidden after the switch")
        AssertEq(Anim.Active(), 0, "nothing left running")
    } finally {
        Anim.Reset()
        UiDashClose(d)
        try DirDelete(dir, true)
    }
}

Test_Dash_CountUp() {
    dir := UiDashTmp()
    d := ""
    Anim.Reset()
    try {
        d := Dashboard(Config.Load(dir))
        for id in ["stat:loops", "stat:fish", "stat:biomes", "stat:rare"] {
            c := d.Ctrl(id)
            AssertTrue(IsObject(c), id " tile")
            AssertEq(d.PageOf(c), "Run", id " is on Home")
        }
        d.SelectPage(2)
        r := UiDashAnimRig(true)
        d.SetStats(Map("fishCaught", 148, "biomes", 7, "rareBiomes", 1, "loops", 1234))
        d.SelectPage(1)
        UiDashTickTo(r, 0)
        AssertEq(d.Ctrl("stat:fish").Text, "0", "t 0: from 0")
        UiDashTickTo(r, 300)
        v := d.Ctrl("stat:fish").Text
        AssertTrue(RegExMatch(v, "^\d+$") && Integer(v) >= 1 && Integer(v) <= 147, "t 300: whole number between 1 and 147 (" v ")")
        UiDashTickTo(r, 600)
        AssertEq(d.Ctrl("stat:fish").Text, "148", "t 600: fish")
        AssertEq(d.Ctrl("stat:biomes").Text, "7", "t 600: biomes")
        AssertEq(d.Ctrl("stat:rare").Text, "1", "t 600: rare")
        AssertEq(d.Ctrl("stat:loops").Text, "1,234", "t 600: loops")
        ; on Home with nothing counting: new values show at once
        d.SetStats(Map("fishCaught", 150))
        AssertEq(d.Ctrl("stat:fish").Text, "150", "live update on Home")
        ; no "loops" key: SetStatus' loops
        d.SetStatus("Stopped", "", "", false, 0, 42)
        d.SetStats(Map("fishCaught", 150))
        AssertEq(d.Ctrl("stat:loops").Text, "42", "loops from SetStatus")
    } finally {
        Anim.Reset()
        UiDashClose(d)
        try DirDelete(dir, true)
    }
}

Test_Dash_AnimationsOff() {
    dir := UiDashTmp()
    d := ""
    Anim.Reset()
    try {
        cfg := Config.Load(dir)
        cfg.Set("UI.animations", 0)
        d := Dashboard(cfg)
        d.SelectPage(UiDashPageIdx("Fishing"))
        r := UiDashAnimRig(true)                      ; gate open: only the setting stops it
        d.SelectPage(UiDashPageIdx("Quests"))
        q := UiDashPos(d.Ctrl("tab:Quests")), p := UiDashPos(d.Ctrl("tabUnderline"))
        AssertEq(p.x "," p.w, q.x "," q.w, "underline at its end at once")
        AssertEq(d.CoverShown(), false, "no fade cover")
        AssertEq(Anim.Active(), 0, "nothing running")
        d.SetStats(Map("fishCaught", 9))
        d.SelectPage(1)
        AssertEq(d.Ctrl("stat:fish").Text, "9", "count-up ends at once")
        d._StartLoops()
        d.SetStatus("Running")
        AssertEq(Anim.Active(), 0, "moon, stars and pulse do not run")
        AssertEq(r.timers.Length, 0, "no timer started")
        ; live: turned back on, loops run (no restart needed)
        cfg.Set("UI.animations", 1)
        d._StartLoops(true)
        AssertTrue(Anim.Has("moon") && Anim.Has("stars") && Anim.Has("pulse"), "on again: loops run")
    } finally {
        Anim.Reset()
        UiDashClose(d)
        try DirDelete(dir, true)
    }
}

Test_Dash_PulseOnlyWhileRunning() {
    dir := UiDashTmp()
    d := ""
    Anim.Reset()
    try {
        d := Dashboard(Config.Load(dir))
        r := UiDashAnimRig(true)
        d.SetStatus("Running", "Fishing")
        AssertTrue(Anim.Has("pulse"), "Running starts loop pulse")
        UiDashTickTo(r, 400)                          ; quarter cycle: halfway dark
        AssertTrue(d._pulseLvl > 0, "pulse stepped (" d._pulseLvl ")")
        d.SetStatus("Paused", "Fishing")
        AssertEq(Anim.Has("pulse"), false, "Paused stops it")
        d.SetStatus("Running", "Fishing")
        AssertTrue(Anim.Has("pulse"), "Running again")
        d.SetStatus("Stopped")
        AssertEq(Anim.Has("pulse"), false, "Stopped stops it")
        AssertEq(d._pulseLvl, -1, "pulse shade reset")
    } finally {
        Anim.Reset()
        UiDashClose(d)
        try DirDelete(dir, true)
    }
}

; Roblox in front = the Dashboard is not the foreground window: the real gate
; is closed, so pulse, moon and stars never step and no timer runs.
Test_Dash_NothingAnimatesBehindRoblox() {
    dir := UiDashTmp()
    d := ""
    Anim.Reset()
    try {
        d := Dashboard(Config.Load(dir))
        AssertEq(Anim.gateFn.Call(), false, "real gate closed: window not in front")
        r := {t: 0, timers: []}
        Anim.nowFn := () => r.t                       ; the real gate stays
        Anim.timerFn := (fn, ms) => r.timers.Push(ms)
        d.SetStatus("Running", "Fishing")
        d._StartLoops()
        before := UiDashAnimLevels(d)
        for t in [400, 800, 1300, 2100, 2900]
            UiDashTickTo(r, t)
        AssertEq(UiDashAnimLevels(d), before, "pulse, moon and stars unchanged")
        AssertEq(r.timers.Length, 0, "no timer started")
        AssertTrue(Anim.Has("pulse") && Anim.Has("stars"), "loops kept, frozen")
    } finally {
        Anim.Reset()
        UiDashClose(d)
        try DirDelete(dir, true)
    }
}

; Closed gate: loops frozen. Gate open + WM_ACTIVATE (the wake path): the
; timer starts and they step again.
Test_Dash_WakeResumesLoops() {
    dir := UiDashTmp()
    d := ""
    Anim.Reset()
    try {
        d := Dashboard(Config.Load(dir))
        r := UiDashAnimRig(false)
        d.SetStatus("Running", "Fishing")
        d._StartLoops()
        before := UiDashAnimLevels(d)
        UiDashTickTo(r, 1000)
        AssertEq(UiDashAnimLevels(d), before, "closed: frozen")
        AssertEq(r.timers.Length, 0, "closed: no timer")
        r.open := true
        Dashboard._OnActivate(1, 0, 0x0006, d.Hwnd + 1)  ; another window: ignored
        AssertEq(r.timers.Length, 0, "other window's activation does not wake")
        Dashboard._OnActivate(1, 0, 0x0006, d.Hwnd)
        AssertEq(r.timers.Length, 1, "activation starts the timer")
        AssertEq(r.timers[1], Anim.FrameMs, "at the frame period")
        UiDashTickTo(r, 1000)
        AssertTrue(UiDashAnimLevels(d) != before, "open: they step again")
        AssertEq(d._moonFrame, 3, "moon frame = Floor(phase * 12) (1000 / 3200)")
    } finally {
        Anim.Reset()
        UiDashClose(d)
        try DirDelete(dir, true)
    }
}

; Restored from minimized (WM_SIZE SIZE_RESTORED): the same wake path.
Test_Dash_RestoreWakesLoops() {
    dir := UiDashTmp()
    d := ""
    Anim.Reset()
    try {
        d := Dashboard(Config.Load(dir))
        r := UiDashAnimRig(false)
        d._StartLoops()
        AssertEq(r.timers.Length, 0, "closed: no timer")
        r.open := true
        Dashboard._OnRestore(1, 0, 0x0005, d.Hwnd)    ; SIZE_MINIMIZED: ignored
        AssertEq(r.timers.Length, 0, "minimized: no wake")
        Dashboard._OnRestore(0, 0, 0x0005, d.Hwnd)
        AssertEq(r.timers.Length, 1, "restore starts the timer once")
        AssertEq(r.timers[1], Anim.FrameMs, "at the frame period")
    } finally {
        Anim.Reset()
        UiDashClose(d)
        try DirDelete(dir, true)
    }
}

; The fade cover never stays: it hides after 150 ms, when the gate closes
; mid-fade, and when the switch throws.
Test_Dash_FadeCoverAlwaysEndsHidden() {
    dir := UiDashTmp()
    d := ""
    Anim.Reset()
    try {
        d := Dashboard(Config.Load(dir))
        r := UiDashAnimRig(true)
        d.SelectPage(UiDashPageIdx("Fishing"))
        AssertTrue(d.CoverShown(), "cover shown over the switch")
        UiDashTickTo(r, 100)
        AssertTrue(d.CoverShown(), "t 100: still fading")
        UiDashTickTo(r, 150)
        AssertEq(d.CoverShown(), false, "t 150: hidden")
        ; gate closes mid-fade (minimized / Roblox in front)
        d.SelectPage(UiDashPageIdx("Quests"))
        AssertTrue(d.CoverShown(), "second switch: shown")
        r.open := false
        UiDashTickTo(r, 200)
        AssertEq(d.CoverShown(), false, "gate closed: hidden at the next tick")
        ; quick switches: the newer fade owns the cover
        r.open := true
        d.SelectPage(UiDashPageIdx("Craft"))
        d.SelectPage(UiDashPageIdx("Merchants"))
        AssertTrue(d.CoverShown(), "switch during a fade: shown")
        UiDashTickTo(r, 400)
        AssertEq(d.CoverShown(), false, "then hidden")
        ; an error during the switch
        page := d._pages[UiDashPageIdx("Limbo")]
        page.ctrls.Push({})                           ; no Hwnd: SelectPage throws
        threw := false
        try d.SelectPage(UiDashPageIdx("Limbo"))
        catch
            threw := true
        page.ctrls.Pop()
        AssertTrue(threw, "the broken page throws")
        AssertEq(d.CoverShown(), false, "error: hidden")
        AssertEq(Anim.Has("fade"), false, "error: no fade left")
    } finally {
        Anim.Reset()
        UiDashClose(d)
        try DirDelete(dir, true)
    }
}

; Leaving a page moves keyboard focus off its controls (to the window).
Test_Dash_SelectPageMovesFocus() {
    dir := UiDashTmp()
    d := ""
    Anim.Reset()
    try {
        d := Dashboard(Config.Load(dir))
        d.SelectPage(UiDashPageIdx("Fishing"))
        n := [0]
        foc := [d.Ctrl("General.sellEvery").Hwnd]
        d._focusFn := () => foc[1]
        to := [0]
        d._setFocusFn := (h) => (n[1]++, to[1] := h)
        d.SelectPage(UiDashPageIdx("Quests"))
        AssertEq(n[1], 1, "focus on the old page's edit: moved")
        AssertEq(to[1], d.Hwnd, "to the window")
        foc[1] := d.Ctrl("hub:Home").Hwnd               ; header control: not on a page
        d.SelectPage(UiDashPageIdx("Craft"))
        AssertEq(n[1], 1, "focus outside the page: left alone")
        foc[1] := d.Ctrl("Craft.craftTarget").Hwnd
        d.SelectPage(UiDashPageIdx("Merchants"))
        AssertEq(n[1], 2, "focus on the old page's dropdown: moved")
        foc[1] := d.Ctrl("merch.name").Hwnd
        d.SelectPage(UiDashPageIdx("Merchants"))      ; same page: no switch
        AssertEq(n[1], 2, "no switch: nothing moved")
    } finally {
        Anim.Reset()
        UiDashClose(d)
        try DirDelete(dir, true)
    }
}

; Stars sit in the header (y < 59) or sidebar (x < 176) only, clear of the
; brand, the credits banner, the status pill, the buttons and the hub list.
Test_Dash_StarsClearOfEverything() {
    dir := UiDashTmp()
    d := ""
    Anim.Reset()
    try {
        d := Dashboard(Config.Load(dir))
        ovR := (a, b) => !(a.x + a.w <= b.x || b.x + b.w <= a.x || a.y + a.h <= b.y || b.y + b.h <= a.y)
        keep := [{x: 18, y: 10, w: 40, h: 40}, {x: 66, y: 5, w: 300, h: 50}, UiDashPos(d.Ctrl("credits.banner"))
            , UiDashPos(d._pill), {x: 764, y: 16, w: 256, h: 28}, {x: 0, y: 66, w: 176, h: 316}, UiDashPos(d._chip)]
        n := 0
        while IsObject(s := d.Ctrl("star" (n + 1))) {
            n++
            p := UiDashPos(s)
            AssertTrue(p.y + p.h <= 59 || p.x + p.w <= 175, "star " n " in header or sidebar")
            for k in keep
                AssertTrue(!ovR(p, k), "star " n " at " p.x "," p.y " clear of " k.x "," k.y)
        }
        AssertTrue(n >= 6 && n <= 8, "6-8 stars (" n ")")
    } finally {
        Anim.Reset()
        UiDashClose(d)
        try DirDelete(dir, true)
    }
}

; The header moon takes the theme's Accent (2026-11-13: Equinox white, not
; gold) and the new moon frame shows only its faint disc.
Test_Dash_MoonTintedToTheTheme() {
    px := (h, x, y) => UiDashBmpPixel(h, x, y)
    full := Theme.AssetPath("ui\moon_8.png"), newm := Theme.AssetPath("ui\moon_2.png")
    for c in [["E6E6E6", "0E0E0E"], ["F2A93B", "0D1117"], ["FF4D57", "120A0C"]] {
        h := Theme.MoonBitmap(full, c[1], c[2])
        AssertTrue(h, c[1] ": a bitmap")
        AssertEq(px(h, 20, 20), Integer("0x" c[1]), c[1] ": the full moon's middle is the accent")
        AssertEq(px(h, 1, 1), Integer("0x" c[2]), c[1] ": the corner is the header colour")
        DllCall("DeleteObject", "Ptr", h)
        h := Theme.MoonBitmap(newm, c[1], c[2])
        mid := px(h, 20, 20)
        AssertTrue(mid != Integer("0x" c[1]) && mid != Integer("0x" c[2]), c[1] ": the new moon is a faint disc (" Format("{:06X}", mid) ")")
        DllCall("DeleteObject", "Ptr", h)
    }
    AssertEq(Theme.MoonBitmap(A_Temp "\missing_moon_x.png", "FFFFFF", "000000"), 0, "a missing file: 0 (LoadPicture then)")
    Loop 12
        AssertTrue(FileExist(Theme.AssetPath("ui\moon_" (A_Index - 1) ".png")), "frame " (A_Index - 1) " shipped")
}

; RRGGBB of an HBITMAP's pixel.
UiDashBmpPixel(h, x, y) {
    dc := DllCall("CreateCompatibleDC", "Ptr", 0, "Ptr")
    old := DllCall("SelectObject", "Ptr", dc, "Ptr", h, "Ptr")
    c := DllCall("GetPixel", "Ptr", dc, "Int", x, "Int", y, "UInt")
    DllCall("SelectObject", "Ptr", dc, "Ptr", old)
    DllCall("DeleteDC", "Ptr", dc)
    return ((c & 0xFF) << 16) | (c & 0xFF00) | ((c >> 16) & 0xFF)      ; COLORREF is BGR
}

; Destroy frees the moon frames, forgets the window for the wake hooks and
; stops the Dashboard's animations.
Test_Dash_DestroyCleansUp() {
    dir := UiDashTmp()
    d := ""
    Anim.Reset()
    try {
        d := Dashboard(Config.Load(dir))
        AssertEq(d._moonFrames.Length, 12, "12 moon frames (a whole cycle, new moon included) decoded once")
        for h in d._moonFrames
            AssertEq(DllCall("GetObjectType", "Ptr", h, "UInt"), 7, "frame is a live bitmap")    ; OBJ_BITMAP
        hwnd := d.Hwnd
        AssertTrue(Dashboard._wins.Has(hwnd), "window known to the wake hooks")
        UiDashAnimRig(false)
        d._StartLoops()
        d.SetStatus("Running")
        d.Destroy()
        AssertEq(Dashboard._wins.Has(hwnd), false, "window forgotten")
        AssertEq(d._moonFrames.Length, 0, "frames released")
        AssertEq(d._moonFreed, 12, "all 12 bitmaps deleted")
        AssertTrue(!Anim.Has("moon") && !Anim.Has("stars") && !Anim.Has("pulse"), "its loops stopped")
        d.Destroy()                                   ; twice is harmless
    } finally {
        Anim.Reset()
        UiDashClose(d)
        try DirDelete(dir, true)
    }
}

Test_ObbyMemory_Page() {
    dir := UiDashTmp()
    d := ""
    try {
        AssertEq(Dashboard.Pages.Length, Dashboard.Builders.Length, "pages and builders aligned")
        AssertEq(Dashboard.Builders[UiDashPageIdx("Obby & Memory")], "_PageObbyMemory", "builder at the page's index")
        AssertEq(Dashboard.Pages[UiDashPageIdx("Obby & Memory")], "Obby & Memory", "page name")
        cfg := Config.Load(dir)
        d := Dashboard(cfg)
        AssertEq(d.PageOf(d.Ctrl("Obby.enabled")), "Obby & Memory", "Obby switch on the page")
        AssertEq(d.PageOf(d.Ctrl("Obby.intervalMin")), "Obby & Memory", "interval on the page")
        AssertEq(d.PageOf(d.Ctrl("Obby.retries")), "Obby & Memory", "retries on the page")
        AssertEq(d.PageOf(d.Ctrl("MemoryMatch.enabled")), "Obby & Memory", "Memory Match switch on the page")
        AssertEq(d.PageOf(d.Ctrl("Minions.normal")), "Hunting", "NORMAL hunt switch on Quests & events > Limited")
        AssertEq(d.Ctrl("Minions.normal").Value, 0, "NORMAL not hunted by default")
        AssertEq(d.PageOf(d.Ctrl("Auras.equipFirst")), "Obby & Memory", "equip-first switch on the page")
        AssertEq(d.Ctrl("Auras.equipFirst").Value, 0, "equip first off by default")
        AssertEq(Config.IniDefaults()["Auras"]["equipFirst"], "0", "Auras.equipFirst default 0 in settings.ini")
        AssertEq(d.Ctrl("Obby.intervalMin").Value, "10", "interval default shown")
        AssertTrue(InStr(d.Ctrl("obbyBlessingNote").Text, "obby_blessing"), "blessing note names the calibration step")
        AssertTrue(InStr(d.Ctrl("memoryNote").Text, "next try: "), "next try note")
        ; Reset timer (2026-11-16): on a temp state file, never the real one
        mp := dir "\mm_state.json"
        FileAppend('{"nextTry":"20991231235900","lastPlayed":"20261116120000"}', mp, "UTF-8")
        Dashboard.MemoryStatePath := mp
        try {
            d._ObbyMemoryLoad()
            AssertTrue(InStr(d.Ctrl("memoryNote").Text, "31 Dec"), "the saved next try: " d.Ctrl("memoryNote").Text)
            AssertEq(d.ResetMemoryTimer(), true, "reset")
            AssertTrue(InStr(d.Ctrl("memoryNote").Text, "now"), "next try now: " d.Ctrl("memoryNote").Text)
            AssertTrue(!InStr(FileRead(mp, "UTF-8"), "nextTry") && InStr(FileRead(mp, "UTF-8"), "lastPlayed"), "nextTry gone, lastPlayed kept")
        } finally {
            Dashboard.MemoryStatePath := ""
        }
        if !MemoryMatchTask.LayoutKnown {
            AssertTrue(InStr(d.Ctrl("memoryLayoutNote").Text, "waiting for the board layout"), "layout note while unknown")
            d.Ctrl("MemoryMatch.enabled").Flip()
            AssertEq(d.Ctrl("MemoryMatch.enabled").Value, 0, "Memory Match switch cannot be turned on without a layout")
        }
        ; interval 1..120, retries 0..3 refused before cfg is touched
        d.Ctrl("Obby.intervalMin").Value := "0"
        AssertEq(d.SavePage("Obby & Memory"), false, "interval 0 refused")
        AssertTrue(InStr(d._PageByName("Obby & Memory").status.Text, "Not saved"), "refusal shows a message")
        AssertEq(cfg.Get("Obby.intervalMin", 10), 10, "refused interval not in cfg")
        d.Ctrl("Obby.intervalMin").Value := "121"
        AssertEq(d.SavePage("Obby & Memory"), false, "interval 121 refused")
        d.Ctrl("Obby.intervalMin").Value := "15"
        d.Ctrl("Obby.retries").Value := "4"
        AssertEq(d.SavePage("Obby & Memory"), false, "retries 4 refused")
        d.Ctrl("Obby.retries").Value := "2"
        d.Ctrl("Obby.enabled").Value := 1
        AssertTrue(d.SavePage("Obby & Memory"), "15 / 2 saved")
        c2 := Config.Load(dir)
        AssertEq(c2.Get("Obby.intervalMin", 0), 15, "interval persisted")
        AssertEq(c2.Get("Obby.retries", -1), 2, "retries persisted")
        AssertEq(c2.Get("Obby.enabled", 0), 1, "Obby.enabled persisted")
    } finally {
        UiDashClose(d)
        try DirDelete(dir, true)
    }
}

; 2026-11-11 (the owner's ask): Minion hunting is still buggy; turning it on
; warns first, and "Keep off" leaves it off (Memory Match warned too until
; 2026-11-16: the owner says it is not buggy any more)
; 2026-11-11: a friend's Equinox hunts failed. A big combat aura asks first
; (once per name); "Change it" puts the saved aura back
Test_Dashboard_BigAuraWarns() {
    dir := UiDashTmp()
    d := ""
    try {
        cfg := Config.Load(dir)
        d := Dashboard(cfg, Map())
        e := d.Ctrl("Minions.aura")
        asked := []
        d._confirmBig := (title, text) => (asked.Push(text), false)
        e.Value := "Eden"
        d._BigAuraCheck(e)
        AssertEq(asked.Length, 0, "Eden: no warning")
        e.Value := "Equinox"
        d._BigAuraCheck(e)
        AssertEq(asked.Length, 1, "Equinox: warned")
        AssertTrue(InStr(asked[1], "fail much more often"), "says it fails more")
        AssertEq(e.Value, "Eden", "Change it: the saved aura back")
        d._confirmBig := (title, text) => (asked.Push(text), true)
        e.Value := "Luminosity"
        d._BigAuraCheck(e)
        AssertEq(e.Value, "Luminosity", "Use it: kept")
        d._BigAuraCheck(e)
        AssertEq(asked.Length, 2, "asked once per name")
        AssertTrue(MinionsTask.IsBig("", "Equinox : You Are An Idiot"), "the event Equinox too")
    } finally {
        UiDashClose(d)
        try DirDelete(dir, true)
    }
}

Test_Dashboard_BuggyPartsWarnBeforeTheyGoOn() {
    dir := UiDashTmp()
    d := ""
    try {
        cfg := Config.Load(dir)
        d := Dashboard(cfg, Map())
        sw := ""
        for b in d._binds
            if (b.key = "Minions.enabled")
                sw := b.ctrl
        AssertTrue(IsObject(sw), "the minions switch")
        asked := []
        d._confirmBuggy := (title, text) => (asked.Push(title), false)
        sw.Value := 0
        sw.Flip()
        AssertEq(asked.Length, 1, "turning on asks")
        AssertTrue(InStr(asked[1], "buggy"), "says it is buggy")
        AssertEq(sw.Value, 0, "declined: still off")
        d._confirmBuggy := (title, text) => (asked.Push(title), true)
        sw.Flip()
        AssertEq(sw.Value, 1, "accepted: on")
        sw.Flip()
        AssertEq(asked.Length, 2, "turning off never asks")
        AssertEq(sw.Value, 0, "off")
        ; Memory Match turns on without asking
        mem := ""
        for b in d._binds
            if (b.key = "MemoryMatch.enabled")
                mem := b.ctrl
        mem.Value := 0
        mem.Flip()
        AssertEq(asked.Length, 2, "Memory Match: no warning")
        AssertEq(mem.Value, 1, "Memory Match: on")
    } finally {
        UiDashClose(d)
        try DirDelete(dir, true)
    }
}

; A switch with a warning still shows the tab's unsaved dot (Memory Match,
; given a warning here: its own was removed 2026-11-16).
Test_Dashboard_WarnedSwitchUpdatesDot() {
    dir := UiDashTmp()
    d := ""
    try {
        d := Dashboard(Config.Load(dir), Map())
        sw := "", page := ""
        for b in d._binds
            if (b.key = "MemoryMatch.enabled")
                sw := b.ctrl, page := b.page
        AssertTrue(IsObject(sw), "the memory match switch")
        d._WarnOn(sw, "Test warning", "test")
        d.SelectPage(page.idx)
        dot := d.Ctrl("tabDot:" page.name)
        d._confirmBuggy := (title, text) => true
        sw.Value := 0
        d._RefreshDot(page)
        AssertEq(dot.Visible, false, "no dot at start")
        sw.Flip()
        AssertEq(sw.Value, 1, "accepted: on")
        AssertTrue(dot.Visible, "turned on: dot shown")
        d._confirmBuggy := (title, text) => false
        sw.Flip()
        sw.Flip()
        AssertEq(sw.Value, 0, "declined: off")
        AssertEq(dot.Visible, false, "declined: back to the saved value, no dot")
    } finally {
        UiDashClose(d)
        try DirDelete(dir, true)
    }
}

; Settings refuses a typed private server link the rejoin would refuse.
Test_Dashboard_SettingsRefusesBadServerLink() {
    dir := UiDashTmp()
    d := ""
    try {
        cfg := Config.Load(dir)
        d := Dashboard(cfg, Map())
        d._psEdit.Value := "my-private-link-123"
        AssertEq(d.SavePage("Settings"), false, "a non-roblox link is not saved")
        AssertEq(cfg.Get("General.privateServer", ""), "", "nothing stored")
        d._psEdit.Value := "https://www.roblox.com/"
        AssertEq(d.SavePage("Settings"), false, "the bare prefix is not a link")
        d._psEdit.Value := "https://www.roblox.com/share?code=abc123&type=Server"
        AssertTrue(d.SavePage("Settings"), "a roblox link is saved")
        AssertEq(cfg.Get("General.privateServer", ""), "https://www.roblox.com/share?code=abc123&type=Server", "stored")
        d._psEdit.Value := ""
        AssertTrue(d.SavePage("Settings"), "an empty box keeps the saved link")
        AssertEq(cfg.Get("General.privateServer", ""), "https://www.roblox.com/share?code=abc123&type=Server", "still there")
    } finally {
        UiDashClose(d)
        try DirDelete(dir, true)
    }
}

; ---- v1.6 pages: Stats, Hunting, Daily summary, Remote, Check & help, Schedule

Test_Dashboard_V16Pages() {
    dir := UiDashTmp()
    d := ""
    try {
        cfg := Config.Load(dir)
        calls := []
        cb := Map("checkSetup", () => (calls.Push("check"), [{level: "ok", name: "Roblox open", detail: "1920x1080 fullscreen", fix: ""}
                , {level: "warn", name: "Focus", detail: "PC Manager is running", fix: "Close it"}, {level: "fail", name: "Private server", detail: "not set", fix: "Paste your link"}])
            , "logBundle", (shots := false) => (calls.Push(shots ? "zip+shots" : "zip"), {ok: 1, path: dir "\logs\support_1.zip", msg: ""})
            , "sendSummary", () => "Sent to 1 webhook"
            , "testRemote", () => "Connected as Bot")
        d := Dashboard(cfg, cb)
        ; Check & help
        d._CheckNow()
        out := d.Ctrl("checkOut").Value
        AssertTrue(InStr(out, "[OK]  Roblox open: 1920x1080 fullscreen") && InStr(out, "[!]  Focus") && InStr(out, "[X]  Private server"), "check lines tagged")
        AssertTrue(InStr(out, "Close it") && InStr(out, "Paste your link"), "fixes shown for problems")
        AssertEq(d.Ctrl("checkSummary").Text, "1 ok, 1 warning, 1 problem", "summary line")
        d._LogZip()
        AssertTrue(InStr(d.Ctrl("zipStatus").Text, "support_1.zip"), "zip name shown")
        ; Daily summary: time checked
        d.Ctrl("Summary.time").Value := "25:00"
        AssertEq(d.SavePage("Summary"), false, "25:00 refused")
        d.Ctrl("Summary.time").Value := "7:30"
        AssertTrue(d.SavePage("Summary"), "7:30 saved")
        d._SummaryNow()
        AssertEq(d.Ctrl("summaryStatus").Text, "Sent to 1 webhook", "send now reports")
        ; Schedule
        d.Ctrl("Schedule.start").Value := "nope"
        AssertEq(d.SavePage("Schedule"), false, "bad start refused")
        d.Ctrl("Schedule.start").Value := "21:00"
        d.Ctrl("Schedule.maxHours").Value := "49"
        AssertEq(d.SavePage("Schedule"), false, "49 h refused")
        d.Ctrl("Schedule.maxHours").Value := "6"
        AssertTrue(d.SavePage("Schedule"), "schedule saved")
        AssertEq(Config.Load(dir).Get("Schedule.start", ""), "21:00", "start written")
        ; Remote: ids checked, token secret
        d.Ctrl("Remote.enabled").Value := 1
        d.Ctrl("Remote.channel").Value := "123456789012345678"
        d.Ctrl("Remote.users").Value := "234567890123456789"
        AssertEq(d.SavePage("Remote"), false, "on without a token refused")
        tok := "MTIzNDU2Nzg5.FAKE.TOKENtokenTOKEN1234"
        d.Ctrl("remoteToken").Value := tok
        d.Ctrl("Remote.users").Value := "abc"
        AssertEq(d.SavePage("Remote"), false, "user id not a number refused")
        d.Ctrl("Remote.users").Value := "234567890123456789, 345678901234567890"
        AssertTrue(d.SavePage("Remote"), "remote saved")
        AssertEq(Config.Load(dir).Get("Remote.token", ""), tok, "token stored")
        AssertEq(d.Ctrl("remoteToken").Value, "", "token field emptied")
        AssertTrue(!InStr(d.Ctrl("remoteTokenMask").Text, "TOKENtoken"), "token masked")
        d.Log("leak " tok)
        AssertTrue(!InStr(d.LogText(), tok), "token scrubbed from the log")
        ; Stats
        day := Map("fishCaught", 42, "fishFailed", 8, "reelRate", 84, "fishPerHour", 12.25, "uptimeText", "3h 26m")
        d.SetStatsPage(day, Map(), [{label: "12 Nov", m: day}])
        AssertEq(d.Ctrl("stats:day:fishCaught").Text, "42", "fish today")
        AssertEq(d.Ctrl("stats:day:reelRate").Text, "84%", "reel rate")
        AssertEq(d.Ctrl("stats:day:fishPerHour").Text, "12.3", "fish per hour")
        AssertEq(d.Ctrl("stats:run:reelRate").Text, "-", "no tries yet")
        AssertEq(d.Ctrl("stats:run:uptimeText").Text, "0m", "no uptime yet")
        AssertEq(d.Ctrl("stats:history").GetCount(), 1, "one history row")
        ; Hunting moved to the Limited hub
        AssertEq(d.PageOf(d.Ctrl("Minions.enabled")), "Hunting", "hunting switch on Hunting")
        d.Ctrl("Minions.maxSec").Value := "30"
        AssertEq(d.SavePage("Hunting"), false, "30 s refused")
    } finally {
        UiDashClose(d)
        try DirDelete(dir, true)
    }
}

; ---- setup wizard (lib\ui\Wizard.ahk) ---------------------------------------

Test_Wizard_StepsSaveAndSkip() {
    dir := UiDashTmp()
    dir2 := ""
    w := "", w2 := ""
    try {
        cfg := Config.Load(dir)
        AssertTrue(SetupWizard.ShouldShow(cfg), "shown on a new install")
        done := []
        w := SetupWizard(cfg, Map("checkSetup", () => [{level: "warn", name: "Focus", detail: "PC Manager", fix: "Close it"}], "done", (f) => done.Push(f)))
        AssertEq(w.Step, 1, "starts on Language")
        w.Next()
        AssertEq(w.Step, 2, "then Welcome")
        AssertEq(Config.Load(dir).Get("UI.lang", ""), "en", "Next without a pick keeps the language")
        w.Next()
        w._Check()
        AssertTrue(InStr(w.Ctrl("checkOut").Value, "[!]  Focus: PC Manager"), "check shown")
        w.Next()
        AssertEq(w.Step, 4, "private server page")
        w.Ctrl("ps").Value := "not a link"
        AssertEq(w.Next(), false, "a non-Roblox link stays on the page")
        w.Ctrl("ps").Value := "https://roblox.com/share?code=WIZCODE123&type=Server"
        AssertEq(w.Next(), false, "a link auto-rejoin would refuse (no www.) stays on the page")
        link := "https://www.roblox.com/share?code=WIZCODE123&type=Server"
        w.Ctrl("ps").Value := link
        AssertTrue(w.Next(), "a Roblox link moves on")
        AssertEq(Config.Load(dir).Get("General.privateServer", ""), link, "link saved")
        w.Ctrl("hook").Value := "https://example.com/hook"
        AssertEq(w.Next(), false, "not a webhook URL")
        w.Ctrl("hook").Value := ""
        AssertTrue(w.Next(), "empty webhook skips")
        AssertEq(Config.Load(dir).Webhooks().Length, cfg.Webhooks().Length, "no webhook added")
        w.Ctrl("run:MemoryMatch.enabled").Value := 1
        w.Ctrl("run:Quests.enabled").Value := 0
        w.Next()
        c2 := Config.Load(dir)
        AssertEq(c2.Get("MemoryMatch.enabled", 0), 1, "memory match on")
        AssertEq(c2.Get("Quests.enabled", 1), 0, "quests off")
        AssertEq(w.Step, 7, "done page")
        w.Next()
        AssertEq(done.Length, 1, "done called once")
        AssertEq(done[1], 1, "finished")
        AssertTrue(!SetupWizard.ShouldShow(Config.Load(dir)), "not shown again")
        w := ""
        ; Skip setup on page 1: nothing else changes, never shown again
        dir2 := UiDashTmp()
        c3 := Config.Load(dir2)
        w2 := SetupWizard(c3, Map("done", (f) => done.Push(f)))
        w2.Skip()
        AssertEq(done[2], 0, "skipped")
        AssertEq(Config.Load(dir2).Get("UI.setupDone", 0), 1, "skip remembered")
        AssertEq(Config.Load(dir2).Get("General.privateServer", ""), "", "nothing else written")
        w2 := ""
    } finally {
        try w.Destroy()
        try w2.Destroy()
        try DirDelete(dir, true)
        if (dir2 != "")
            try DirDelete(dir2, true)
    }
}

; ---- colour themes and the Look page (Theme, ThemeStore, Dashboard Look) -------

Test_Theme_Presets() {
    root := RegExReplace(A_LineFile, "\\tests\\[^\\]+$", "")
    try {
        for n in Theme.Names {
            p := Theme.Presets[n]
            for k in Theme.ThemeKeys
                AssertTrue(p.HasProp(k), n " has " k)
            AssertTrue(FileExist(root "\assets\" p.BgImage) != "", n " background exists")
            AssertTrue(FileGetSize(root "\assets\" p.BgImage) < 300 * 1024, n " background under 300 KB")
        }
        AssertEq(Theme.Use("overdrive"), "Overdrive", "any case")
        AssertEq(Theme.Accent, "FF4D57", "red accent")
        AssertEq(Theme.BgImage, "themes\overdrive.png", "red background")
        AssertEq(Theme.Use("nope"), "Moontide", "unknown -> Moontide")
        AssertEq(Theme.Accent, "F2A93B", "gold again")
        AssertEq(Theme.Use("Custom"), "Moontide", "the old Custom theme is gone (Migrate made it My theme)")
        AssertEq(Theme.ThemeName("custom"), "Moontide", "Custom is no theme name any more")
    } finally {
        Theme.Use("Moontide")
    }
}

UiDashOverlap(a, b) => !(a.x + a.w <= b.x || b.x + b.w <= a.x || a.y + a.h <= b.y || b.y + b.h <= a.y)

; a file that is not a picture, with a picture's name
UiDashBadPng(dir) {
    p := dir "\not_a_picture.png"
    FileAppend("this is text, not a png", p, "UTF-8-RAW")
    return p
}

; the colour maths the Look page uses (Theme.Derive and friends)
Test_Theme_DeriveColours() {
    root := RegExReplace(A_LineFile, "\\tests\\[^\\]+$", "")
    dir := UiDashTmp()
    bg := Theme.Bg
    try {
        AssertEq(Theme.HexOk("#0d1117"), "0D1117", "hash and lower case")
        AssertEq(Theme.HexOk(" F2A93B "), "F2A93B", "spaces")
        AssertEq(Theme.HexOk("12345"), "", "5 digits")
        AssertEq(Theme.HexOk("GGGGGG"), "", "not hex")
        AssertEq(Theme.HexOk(""), "", "empty")
        AssertEq(Theme.HexOr("000000", "FFFFFF"), "000000", "black is a colour")
        AssertEq(Theme.Mix("000000", "FFFFFF", 0.5), "808080", "mix")
        ; derived from Moontide's 4 colours: close to the hand-made preset
        m := Theme.Presets["Moontide"]
        o := Theme.Derive(m.Bg, m.PanelC, m.Text, m.Accent)
        for k in Theme.ThemeKeys
            AssertTrue(o.HasProp(k), "derive has " k)
        for k in ["SideBg", "FieldBg", "FrameC", "HoverBg", "OffBg", "Muted", "AccentHi", "Pulse"] {
            a := Integer("0x" o.%k%), b := Integer("0x" m.%k%)
            loop 3 {
                sh := (A_Index - 1) * 8
                AssertTrue(Abs(((a >> sh) & 0xFF) - ((b >> sh) & 0xFF)) <= 48, k " near the preset (" o.%k% " vs " m.%k% ")")
            }
        }
        AssertEq(o.Ink, m.Bg, "ink = the dark background on gold")
        AssertEq(o.TextFixed, false, "text reads")
        l := Theme.Derive("F4F4F4", "D0D8E8", "1A1A1A", "FFE14D")
        AssertTrue(Theme.Contrast(l.Ink, l.Accent) >= 4.5, "ink readable on a pale accent (" l.Ink ")")
        dk := Theme.Derive("0D1117", "0B2A5B", "1A1A1A", "1030A0")
        AssertTrue(Theme.Contrast(dk.Ink, dk.Accent) >= 4.5, "ink readable on a dark accent (" dk.Ink ")")
        f := Theme.Derive("101010", "202020", "141414", "F2A93B")
        AssertTrue(f.TextFixed, "unreadable text fixed")
        AssertEq(f.Text, "FFFFFF", "white on dark panels")
        b := Theme.Derive("nope", "", "#12", "zzzzzz")
        AssertEq(b.Bg b.PanelC b.Text b.Accent, m.Bg m.PanelC m.Text m.Accent, "bad hex -> Moontide's")
        ; pictures: darkened and scaled, a bad one -> 0
        png := root "\assets\themes\galaxy.png"
        h := Theme.DimPicture(png, 864, 620, "0D1117")
        AssertTrue(h != 0, "picture loaded")
        if h
            DllCall("DeleteObject", "Ptr", h)
        AssertEq(Theme.DimPicture(dir "\missing.png", 864, 620, "0D1117"), 0, "missing")
        AssertEq(Theme.DimPicture(UiDashBadPng(dir), 864, 620, "0D1117"), 0, "not a picture")
        ; a light background gets Windows' light control look
        Theme.Bg := "F2F2F2"
        AssertTrue(Theme.IsLight(), "F2F2F2 is light")
        Theme.Bg := "0D1117"
        AssertTrue(!Theme.IsLight(), "Moontide is dark")
        for n in Theme.Names
            AssertTrue(Theme.Lum(Theme.Presets[n].Bg) <= 0.4, n " stays dark")
        ; profiles never carry a picture's path
        AssertEq(Profiles.Shareable("UI", "customPictureFile", "D:\art\x.png"), "", "picture path not shared")
    } finally {
        Theme.Bg := bg
        try DirDelete(dir, true)
    }
}

; A Look test dashboard: every question answered yes, imports added, no
; folder opened, names asked answered with `askName`.
UiLookDash(cfg, cbs := "", askName := "") {
    d := Dashboard(cfg, cbs)
    d._lookAsk := (*) => true
    d._importOk := (*) => true
    d._openFolder := (*) => 0
    d._askName := (*) => askName
    return d
}

; a saved theme `name` (Moontide's base colours, one changed; a copy of a
; preset keeps the preset's own 10 shades, this one mixes them)
UiLookSaved(cfg, name, accent := "33CCFF") {
    t := ThemeStore.Default()
    t["name"] := name
    t["preset"] := false
    t["colors"]["Accent"] := accent
    for k in ThemeStore.DerivedKeys
        t["colors"][k] := ""                 ; every other shade mixed (Auto)
    AssertEq(ThemeStore.Save(cfg, t), true, "test theme " name " saved")
}

UiLookFiles(cfg) {
    n := 0
    Loop Files, ThemeStore.Dir(cfg) "\*.*"
        n++
    return n
}

Test_Look_EditAndSave() {
    dir := UiDashTmp()
    d := ""
    oldWa := Theme.WorkAreaFn, oldSc := Theme.Scale
    try {
        Theme.WorkAreaFn := () => {w: 1366, h: 728}       ; only 100 % fits this screen
        cfg := Config.Load(dir)
        d := UiLookDash(cfg)
        AssertTrue(d.LookSelect("Moontide"), "Moontide picked")
        AssertEq(d.LookDuplicate(), "Moontide copy", "Duplicate makes Moontide copy")
        AssertTrue(ThemeStore.Exists(cfg, "Moontide copy"), "the copy is saved at once")
        AssertEq(d.LookName(), "Moontide copy", "and picked")
        AssertTrue(InStr(d.Ctrl("look:list").GetText(d.Ctrl("look:list").GetNext()), "Moontide copy"), "the list shows it picked")
        AssertTrue(d.LookSet("Accent", "ff00aa"), "accent")
        AssertTrue(d.LookSet("font:title", "Georgia"), "title font")
        AssertTrue(d.LookSet("size:title", 22), "title size")
        AssertTrue(d.LookSet("scale", 115), "UI size")
        AssertEq(d.LookSet("size:title", 40), false, "a size over 28 refused")
        AssertEq(d.LookSet("Accent", "nope"), false, "bad hex refused")
        AssertEq(d.LookSet("font:title", "No Such Font 12345"), false, "a font that is not installed refused")
        AssertEq(d.LookSet("nonsense", 1), false, "an unknown key refused")
        AssertEq(d.Ctrl("look:color:Accent").Value, "FF00AA", "the field shows the accent")
        AssertEq(d.Ctrl("look:font:title").Text, "Georgia", "the family list shows Georgia")
        AssertEq(d.Ctrl("look:size:title").Value, "22", "the size field shows 22")
        AssertEq(d.Ctrl("look:scale").Value, 2, "115 % picked")
        AssertTrue(InStr(d.Ctrl("look:textNote").Text, "115 %") && InStr(d.Ctrl("look:textNote").Text, "100 %")
            , "the note says the largest size that fits: " d.Ctrl("look:textNote").Text)
        AssertEq(d.PreviewColor("button"), "FF00AA", "the preview button takes the new accent")
        AssertEq(d.PreviewFont("title"), "Georgia", "the preview title takes the new font")
        AssertTrue(d._PageDirty(d._PageByName("Look")), "unsaved dot on Look")
        AssertEq(d.LookSave(), true, "saved")
        AssertEq(d._PageDirty(d._PageByName("Look")), false, "no dot after Save")
        t := ThemeStore.Load(cfg, "Moontide copy")
        AssertEq(t["colors"]["Accent"], "FF00AA", "accent written")
        AssertEq(t["fonts"]["title"][1] "," t["fonts"]["title"][2], "Georgia,22", "title font written")
        AssertEq(t["ui"]["scale"], 115, "the size asked for is saved, not the size that fits")
        AssertEq(Config.Load(dir).Get("UI.theme", ""), "Moontide", "Save leaves the theme in use")
        ; Revert puts the saved values back
        AssertTrue(d.LookSet("Accent", "00FF00"), "another accent")
        d.RevertPage("Look")
        AssertEq(d.Ctrl("look:color:Accent").Value, "FF00AA", "Revert shows the saved accent")
        AssertEq(d.LookName(), "Moontide copy", "Revert keeps the picked theme")
        ; the page Save button writes the edited theme too
        AssertTrue(d.LookSet("Text", "EEEEEE"), "text colour")
        AssertTrue(d.SavePage("Look"), "page saved")
        AssertEq(ThemeStore.Load(cfg, "Moontide copy")["colors"]["Text"], "EEEEEE", "the page Save wrote the theme")
    } finally {
        Theme.WorkAreaFn := oldWa, Theme.Scale := oldSc
        Theme.Use("Moontide")
        UiDashClose(d)
        try DirDelete(dir, true)
    }
}

Test_Look_PresetReadOnly() {
    dir := UiDashTmp()
    d := ""
    try {
        cfg := Config.Load(dir)
        d := UiLookDash(cfg)
        asked := []
        d._lookAsk := (title, text, ok, cancel) => (asked.Push(title), false)
        gal := Theme.Presets["Galaxy"].Accent
        AssertTrue(d.LookSelect("Galaxy"), "Galaxy picked")
        AssertEq(d.LookSet("Accent", "FF00AA"), false, "a preset's colour is refused")
        AssertEq(asked.Length, 1, "asked to make a copy")
        AssertTrue(d.LookSave() != true, "a preset is never saved")
        AssertEq(UiLookFiles(cfg), 0, "nothing written")
        AssertEq(d.Ctrl("look:color:Accent").Value, gal, "the field shows the preset's colour")
        ; typing in the field asks the same and puts the colour back
        e := d.Ctrl("look:color:Accent")
        e.Value := "123456"
        d._LookHexEdit("Accent", e)
        AssertEq(asked.Length, 2, "typing asks too")
        AssertEq(e.Value, gal, "the typed colour is taken back")
        AssertEq(UiLookFiles(cfg), 0, "still nothing written")
        AssertTrue(d.LookResetLayout(), "Reset all on a preset with no layout")
        AssertEq(asked.Length, 2, "asks nothing (nothing to reset)")
        AssertEq(UiLookFiles(cfg), 0, "and writes nothing")
        AssertEq(d.LookDelete(), false, "a preset cannot be deleted")
        AssertTrue(d.LookRename("Mine") != true, "a preset cannot be renamed")
        AssertTrue(ThemeStore.Exists(cfg, "Galaxy") && !ThemeStore.Exists(cfg, "Mine"), "nothing renamed")
        ; a yes: the copy takes the edit, the preset is unchanged
        d._lookAsk := (*) => true
        AssertTrue(d.LookSet("Accent", "FF00AA"), "with a yes the copy takes it")
        AssertEq(d.LookName(), "Galaxy copy", "the copy is picked")
        AssertEq(ThemeStore.Load(cfg, "Galaxy copy")["colors"]["Accent"], gal, "the copy starts as Galaxy (the edit is not saved yet)")
        AssertEq(d.LookSave(), true, "the copy saves")
        AssertEq(ThemeStore.Load(cfg, "Galaxy copy")["colors"]["Accent"], "FF00AA", "the edit is in the copy")
        AssertEq(ThemeStore.Load(cfg, "Galaxy")["colors"]["Accent"], gal, "Galaxy unchanged")
    } finally {
        UiDashClose(d)
        try DirDelete(dir, true)
    }
}

Test_Look_AutoDerived() {
    dir := UiDashTmp()
    d := ""
    try {
        cfg := Config.Load(dir)
        UiLookSaved(cfg, "Mine")
        d := UiLookDash(cfg)
        AssertTrue(d.LookSelect("Mine"), "Mine picked")
        a := d.Ctrl("look:auto:Muted")
        AssertEq(a.Value, 1, "Muted starts on Auto")
        auto := d.Ctrl("look:color:Muted").Value
        AssertTrue(Theme.HexOk(auto) != "", "the field shows the mixed colour (" auto ")")
        AssertTrue(d.LookSet("auto:Muted", 0), "Auto off")
        AssertEq(a.Value, 0, "the box is unticked")
        AssertTrue(d.LookSet("Muted", "123456"), "own colour typed")
        AssertEq(d.LookSave(), true, "saved")
        AssertEq(ThemeStore.Load(cfg, "Mine")["colors"]["Muted"], "123456", "the override is saved")
        AssertTrue(d.LookSet("auto:Muted", 1), "Auto on again")
        AssertEq(d.Ctrl("look:color:Muted").Value, auto, "the field shows the mixed colour again")
        AssertEq(d.LookSave(), true, "saved")
        AssertEq(ThemeStore.Load(cfg, "Mine")["colors"]["Muted"], "", "the override is gone")
        ; typing a colour while on Auto unticks it
        AssertTrue(d.LookSet("Ink", "ABCDEF"), "Ink typed")
        AssertEq(d.Ctrl("look:auto:Ink").Value, 0, "Ink no longer Auto")
        ; the user's tick goes the same way
        d.Ctrl("look:auto:Ink").Flip()
        AssertEq(d.LookTheme()["colors"]["Ink"], "", "ticking the box drops the override")
        ; a copy of a preset keeps its hand-made shades; a new base colour mixes
        ; again every shade not set by hand on this page, a hand-set one stays
        AssertTrue(d.LookSelect("Moontide", true), "Moontide picked")
        AssertEq(d.LookDuplicate(), "Moontide copy", "copy made")
        m := Theme.Presets["Moontide"]
        AssertEq(d.LookTheme()["colors"]["CardBg"], m.CardBg, "the copy keeps Moontide's own card shade")
        AssertEq(d.Ctrl("look:auto:CardBg").Value, 0, "so CardBg is not on Auto")
        AssertTrue(d.LookSet("Muted", "123456"), "Muted set by hand")
        AssertTrue(d.LookSet("PanelC", "3A1F5C"), "new panel colour")
        mix := Theme.Derive(m.Bg, "3A1F5C", m.Text, m.Accent)
        AssertEq(d.Ctrl("look:color:CardBg").Value, mix.CardBg, "CardBg follows the new panels")
        AssertEq(d.Ctrl("look:color:FieldBg").Value, mix.FieldBg, "FieldBg follows the new panels")
        AssertEq(d.LookTheme()["colors"]["CardBg"], "", "CardBg is on Auto now")
        AssertEq(d.Ctrl("look:auto:FieldBg").Value, 1, "its box ticked")
        AssertEq(d.LookTheme()["colors"]["Muted"], "123456", "the hand-set Muted stays")
        AssertEq(d.Ctrl("look:auto:Muted").Value, 0, "and stays off Auto")
        AssertEq(d.LookSave(), true, "saved")
        t := ThemeStore.Load(cfg, "Moontide copy")
        AssertEq(t["colors"]["CardBg"] "|" t["colors"]["Muted"], "|123456", "written that way")
    } finally {
        UiDashClose(d)
        try DirDelete(dir, true)
    }
}

Test_Look_ImportExport() {
    root := RegExReplace(A_LineFile, "\\tests\\[^\\]+$", "")
    dir := UiDashTmp()
    d := "", pv := ""
    try {
        cfg := Config.Load(dir)
        d := UiLookDash(cfg)
        d.LookSelect("Moontide")
        AssertEq(d.LookDuplicate(), "Moontide copy", "copy made")
        d.LookSet("Accent", "FF00AA"), d.LookSet("font:head", "Georgia"), d.LookSet("size:body", 12), d.LookSet("dim", 40)
        d.LookSet("fit", "tile"), d.LookSet("sidebar", "right")
        AssertTrue(d.LookSet("pic", root "\assets\themes\boss.png"), "a picture of your own")
        AssertEq(d.LookSet("pic", UiDashBadPng(dir)), false, "a file that is not a picture is refused")
        AssertTrue(InStr(d.Ctrl("look:note").Text, "could not be read") && !InStr(d.Ctrl("look:note").Text, dir), "the note says why, without the path")
        AssertEq(d.LookSave(), true, "saved")
        AssertTrue(FileExist(ThemeStore.Dir(cfg) "\Moontide copy.png") != "", "the picture is copied into the themes folder")
        AssertEq(ThemeStore.Load(cfg, "Moontide copy")["picture"]["file"], "Moontide copy.png", "the theme names its own copy")
        ; a save that fails keeps the picture already there, and the language unsaved
        own := ThemeStore.Dir(cfg) "\Moontide copy.png"
        size0 := FileGetSize(own)
        AssertTrue(d.LookSet("pic", root "\assets\themes\radiant.png"), "another png chosen")
        d.Ctrl("UI.lang").Choose(2)
        f := FileOpen(ThemeStore.Dir(cfg) "\Moontide copy.moontheme", "r -rwd")
        AssertEq(d.SavePage("Look"), false, "the theme file is held open: not saved")
        f.Close()
        AssertEq(FileGetSize(own), size0, "the picture there is untouched")
        AssertEq(FileExist(own ".new"), "", "no temporary picture left")
        AssertEq(cfg.Get("UI.lang", ""), "en", "the language waits for the theme save")
        AssertTrue(d.SavePage("Look"), "saved now")
        AssertTrue(FileGetSize(own) != size0, "the new picture took its place")
        AssertEq(Config.Load(dir).Get("UI.lang", ""), "es", "language saved with it")
        d.Ctrl("UI.lang").Choose(1)
        AssertTrue(d.SavePage("Look"), "English again")
        path := d.LookExport()
        AssertTrue(path != "" && FileExist(path) != "", "exported")
        AssertTrue(InStr(path, ThemeStore.ExportDir(cfg)), "into the exports folder")
        AssertTrue(InStr(d.Ctrl("look:note").Text, "exports folder"), "the note names the exports folder")
        AssertTrue(!InStr(FileRead(path, "UTF-8"), dir), "no local path in the file")
        ; the import preview shows the theme before it is added
        pv := d._ImportPreview(ThemeStore.ReadFile(path))
        AssertTrue(IsObject(pv.add) && IsObject(pv.cancel), "the preview has Add and Cancel")
        AssertTrue(pv.swatches.Length = 4 && IsObject(pv.picture), "colours and the picture in the preview")
        AssertTrue(InStr(pv.fonts.Text, "Georgia"), "fonts in the preview")
        pv.gui.Destroy(), pv := ""
        AssertTrue(d.LookDelete(), "deleted")
        AssertTrue(!ThemeStore.Exists(cfg, "Moontide copy"), "gone")
        AssertEq(FileExist(ThemeStore.Dir(cfg) "\Moontide copy.png"), "", "its picture gone too")
        ; Cancel in the preview adds nothing
        d._importOk := (*) => false
        r := d.LookImport(path)
        AssertTrue(r.HasProp("error") && !ThemeStore.Exists(cfg, "Moontide copy"), "cancelled: nothing added")
        d._importOk := (*) => true
        r := d.LookImport(path)
        AssertEq(r.HasProp("name") ? r.name : r.error, "Moontide copy", "imported")
        AssertEq(d.LookName(), "Moontide copy", "and picked")
        t := ThemeStore.Load(cfg, "Moontide copy")
        AssertEq(t["colors"]["Accent"] "|" t["fonts"]["head"][1] "|" t["fonts"]["body"][2] "|" t["picture"]["dim"] "|" t["picture"]["fit"] "|" t["ui"]["sidebar"]
            , "FF00AA|Georgia|12|40|tile|right", "the same values")
        AssertTrue(FileExist(ThemeStore.Dir(cfg) "\Moontide copy.png") != "", "the picture is back")
        r := d.LookImport(dir "\missing.moontheme")
        AssertTrue(r.HasProp("error"), "a missing file gives an error")
    } finally {
        if IsObject(pv)
            try pv.gui.Destroy()
        UiDashClose(d)
        try DirDelete(dir, true)
    }
}

; A DROPFILES block (what Explorer posts with WM_DROPFILES) for `paths`.
UiLookHDrop(paths) {
    s := ""
    for p in paths
        s .= p Chr(0)
    s .= Chr(0)
    bytes := 20 + StrLen(s) * 2
    h := DllCall("GlobalAlloc", "UInt", 0x42, "UPtr", bytes, "Ptr")     ; GHND
    p := DllCall("GlobalLock", "Ptr", h, "Ptr")
    NumPut("UInt", 20, p, 0)            ; pFiles
    NumPut("Int", 1, p, 16)             ; fWide
    Loop Parse, s
        NumPut("UShort", Ord(A_LoopField), p, 20 + (A_Index - 1) * 2)
    DllCall("GlobalUnlock", "Ptr", h)
    return h
}

Test_Look_DropFile() {
    dir := UiDashTmp()
    d := ""
    try {
        cfg := Config.Load(dir)
        UiLookSaved(cfg, "Dropped", "11AA22")
        path := ThemeStore.Export(cfg, "Dropped")
        AssertTrue(path != "", "exported")
        ThemeStore.Delete(cfg, "Dropped")
        d := UiLookDash(cfg)
        AssertTrue(DllCall("GetWindowLong", "Ptr", d.Hwnd, "Int", -20) & 0x10, "the window takes dropped files")
        r := d.DropFiles([path])
        AssertEq(r.HasProp("name") ? r.name : r.error, "Dropped", "a dropped .moontheme is imported")
        AssertEq(d.ActivePage, "Look", "the Look page shows")
        AssertEq(ThemeStore.Load(cfg, "Dropped")["colors"]["Accent"], "11AA22", "its colours")
        txt := dir "\notes.txt"
        FileAppend("hello", txt, "UTF-8-RAW")
        r := d.DropFiles([txt])
        AssertTrue(r.HasProp("error"), "a .txt is refused")
        AssertTrue(InStr(d.Ctrl("look:note").Text, ".moontheme"), "the note says what to drop: " d.Ctrl("look:note").Text)
        AssertTrue(!InStr(d.Ctrl("look:note").Text, dir), "no path in the note")
        AssertTrue(d.DropFiles([path, path]).HasProp("error"), "two files are refused")
        ; the real message: WM_DROPFILES posted to the window
        ThemeStore.Delete(cfg, "Dropped")
        DllCall("PostMessage", "Ptr", d.Hwnd, "UInt", 0x233, "Ptr", UiLookHDrop([path]), "Ptr", 0)
        Loop 40 {
            Sleep(25)
            if ThemeStore.Exists(cfg, "Dropped")
                break
        }
        AssertTrue(ThemeStore.Exists(cfg, "Dropped"), "WM_DROPFILES imported it")
    } finally {
        UiDashClose(d)
        try DirDelete(dir, true)
    }
}

Test_Look_DeleteInUse() {
    dir := UiDashTmp()
    d := ""
    try {
        cfg := Config.Load(dir)
        UiLookSaved(cfg, "Night")
        UiLookSaved(cfg, "Day")
        cfg.Set("UI.theme", "Night")
        cfg.Save()
        d := UiLookDash(cfg, "", "Dusk")
        AssertEq(d.LookName(), "Night", "the theme in use is picked at start")
        AssertTrue(InStr(d.Ctrl("look:list").GetText(d.Ctrl("look:list").GetNext()), "in use"), "marked in use in the list")
        d._lookAsk := (*) => false
        AssertEq(d.LookDelete(), false, "No keeps it")
        AssertTrue(ThemeStore.Exists(cfg, "Night"), "still there")
        d._lookAsk := (*) => true
        ; the file cannot be deleted (held open): it stays the theme in use
        f := FileOpen(ThemeStore.Dir(cfg) "\Night.moontheme", "r -rwd")
        AssertEq(d.LookDelete(), false, "a file that cannot be deleted")
        f.Close()
        AssertEq(Config.Load(dir).Get("UI.theme", ""), "Night", "it stays the theme in use")
        AssertTrue(d.LookDelete(), "deleted")
        AssertEq(Config.Load(dir).Get("UI.theme", ""), "Moontide", "Moontide is in use first")
        AssertTrue(!ThemeStore.Exists(cfg, "Night"), "Night is gone")
        AssertEq(d.LookName(), "Moontide", "Moontide picked")
        ; renaming the theme in use keeps it in use
        cfg.Set("UI.theme", "Day")
        cfg.Save()
        AssertTrue(d.LookSelect("Day"), "Day picked")
        AssertEq(d.LookRename(), true, "renamed (asked: Dusk)")
        AssertEq(d.LookName(), "Dusk", "the new name is picked")
        AssertTrue(ThemeStore.Exists(cfg, "Dusk") && !ThemeStore.Exists(cfg, "Day"), "file renamed")
        AssertEq(Config.Load(dir).Get("UI.theme", ""), "Dusk", "still in use")
        AssertTrue(d.LookRename("Moontide") != true, "a preset's name is refused")
    } finally {
        UiDashClose(d)
        try DirDelete(dir, true)
    }
}

; Apply saves the Look page, makes the picked theme the one in use and asks
; for the restart; it refuses while another page has unsaved edits (the
; restart would drop them) and names that page.
Test_Look_ApplySavesAndRestarts() {
    dir := UiDashTmp()
    d := ""
    fired := []
    try {
        cfg := Config.Load(dir)
        d := UiLookDash(cfg, Map("restart", () => fired.Push("restart")))
        AssertTrue(d.LookSelect("Galaxy"), "Galaxy picked")
        d.Ctrl("General.questIntervalMin").Value := "44"
        AssertEq(d.ApplyTheme(), false, "refused while General has unsaved edits")
        AssertEq(fired.Length, 0, "no restart")
        AssertTrue(InStr(d.Ctrl("look:note").Text, "General"), "the note names General: " d.Ctrl("look:note").Text)
        AssertEq(Config.Load(dir).Get("UI.theme", ""), "Moontide", "nothing written")
        d.RevertPage("Settings")
        d.Ctrl("UI.animations").Value := 0
        AssertTrue(d.ApplyTheme(), "applied")
        AssertEq(Config.Load(dir).Get("UI.theme", ""), "Galaxy", "the picked theme is in use")
        AssertEq(String(Config.Load(dir).Get("UI.animations", 1)), "0", "the Look page was saved")
        AssertEq(fired.Length, 1, "restart asked once")
        AssertEq(d._PageDirty(d._PageByName("Look")), false, "Look saved")
    } finally {
        Anim.Reset()
        Theme.Use("Moontide")
        UiDashClose(d)
        try DirDelete(dir, true)
    }
}

; Every Look id exists on the Look page inside its card; the Advanced
; colours fold swaps the fonts for the 10 other shades in the same card;
; shown controls never overlap; the font list; the colour and picture pickers.
Test_Look_PageLayout() {
    root := RegExReplace(A_LineFile, "\\tests\\[^\\]+$", "")
    dir := UiDashTmp()
    d := ""
    Anim.Reset()
    try {
        cfg := Config.Load(dir)
        d := UiLookDash(cfg)
        AssertEq(UiCardIds(d, "Look"), "Look:Theme|Look:Colours|Look:Background|Look:Text|Look:Layout|Look:Preview", "Look cards")
        ids := ["look:list", "look:apply", "look:duplicate", "look:rename", "look:delete", "look:import", "look:export"
            , "look:scale", "look:pic", "look:fit", "look:dim", "look:sidebar", "look:editLayout", "look:resetAll", "look:preview"
            , "look:advanced", "look:note", "look:textNote", "UI.animations", "UI.lang"]
        for k in Theme.BaseKeys
            ids.Push("look:color:" k, "look:pick:" k)
        for k in ThemeStore.DerivedKeys
            ids.Push("look:color:" k, "look:auto:" k)
        for r in ThemeStore.FontRoles
            ids.Push("look:font:" r, "look:size:" r)
        for id in ids {
            c := d.Ctrl(id)
            AssertTrue(IsObject(c), id " exists")
            if (id != "look:note")
                AssertEq(d.PageOf(c is ThemeCheck ? c._box : c), "Look", id " on Look")
        }
        AssertEq(d.CardOf(d.Ctrl("look:color:Accent")), "Look:Colours", "base colours in Colours")
        AssertEq(d.CardOf(d.Ctrl("look:color:Muted")), "Look:Text", "advanced colours in the Text card")
        AssertEq(d.CardOf(d.Ctrl("look:font:title")), "Look:Text", "fonts in Text")
        AssertEq(d.CardOf(d.Ctrl("look:advanced")._box), "Look:Text", "the Advanced colours switch is in the card it changes")
        AssertEq(d.CardOf(d.Ctrl("UI.lang")), "Look:Text", "language in Text")
        AssertEq(d.CardOf(d.Ctrl("UI.animations")._box), "Look:Layout", "animations in Layout")
        AssertEq(d.CardOf(d.Ctrl("look:preview")), "Look:Preview", "preview card")
        ; the fold
        d.SelectPage(UiDashPageIdx("Look"))
        AssertTrue(d.Ctrl("look:font:title").Visible && !d.Ctrl("look:color:Muted").Visible, "fonts shown, advanced colours folded")
        UiLookNoOverlap(d, "fonts")
        d.Ctrl("look:advanced").Flip()
        AssertTrue(!d.Ctrl("look:font:title").Visible && d.Ctrl("look:color:Muted").Visible, "advanced colours in place of the fonts")
        AssertEq(d.Ctrl("panelTitle:Look:Text").Text, StrUpper(I18n.T("Advanced colours")), "the card says so")
        AssertTrue(d.Ctrl("look:scale").Visible && d.Ctrl("UI.lang").Visible, "UI size and language stay")
        UiLookNoOverlap(d, "advanced")
        d.Ctrl("look:advanced").Flip()
        AssertTrue(d.Ctrl("look:font:title").Visible, "fonts back")
        ; installed fonts: sorted, no vertical @ fonts, no repeats
        fl := d.LookFonts()
        AssertTrue(fl.Length >= 10 && UiDashHas(fl, "Segoe UI"), "installed fonts listed (" fl.Length ")")
        prev := ""
        for f in fl {
            AssertTrue(SubStr(f, 1, 1) != "@", "no vertical font: " f)
            AssertTrue(prev = "" || StrCompare(prev, f) < 0, "sorted, once: " prev " / " f)
            prev := f
        }
        ; the colour picker (a yes makes a copy of the preset first)
        d.LookSelect("Moontide")
        d._pickColor := (hex) => "123456"
        d._LookPick("Text")
        AssertEq(d.LookName(), "Moontide copy", "picking on a preset made a copy")
        AssertEq(d.Ctrl("look:color:Text").Value, "123456", "picked colour")
        d._pickColor := (hex) => ""
        d._LookPick("Text")
        AssertEq(d.Ctrl("look:color:Text").Value, "123456", "a cancelled pick changes nothing")
        d._pickColor := (hex) => "ABCDEF"
        d._LookPick("Pulse")
        AssertEq(d.LookTheme()["colors"]["Pulse"], "ABCDEF", "a derived colour picked from its swatch")
        ; the picture: Choose a file
        dd := d.Ctrl("look:pic")
        d._pickFile := () => root "\assets\themes\boss.png"
        AssertTrue(d.LookChooseFile(), "a picture accepted")
        AssertTrue(InStr(dd.Text, I18n.T("Your own picture")), "the list shows your own picture: " dd.Text)
        d._pickFile := () => UiDashBadPng(dir)
        AssertEq(d.LookChooseFile(), false, "a file that is not a picture is refused")
        AssertTrue(InStr(dd.Text, I18n.T("Your own picture")), "the good one kept")
        d._pickFile := () => ""
        AssertEq(d.LookChooseFile(), false, "cancelled")
        AssertTrue(d.LookSet("pic", "none"), "no picture")
        AssertEq(dd.Value, 1, "None shown")
        ; animations switch (moved from Settings)
        a := d.Ctrl("UI.animations")
        AssertTrue(a is ThemeCheck && a._style = "pill", "Animations is a pill")
        AssertEq(Anim.enabledFn.Call(), true, "enabledFn follows the setting")
        a.Value := 0
        AssertTrue(d.SavePage("Look"), "saved")
        AssertEq(Anim.enabledFn.Call(), false, "live: animations off without a restart")
        AssertEq(String(Config.Load(dir).Get("UI.animations", 1)), "0", "written to settings.ini")
        ; edit layout: the switch reaches EditLayout; Reset all clears the layout
        d.Ctrl("look:editLayout").Flip()
        AssertEq(d.LayoutEditing(), true, "edit layout on")
        d.Ctrl("look:editLayout").Flip()
        t := d.LookTheme()
        t["layout"]["Settings:Recovery"] := [204, 428, 396, 134, 0]
        AssertTrue(d.LookResetLayout(), "reset all")
        AssertEq(d.LookTheme()["layout"].Count, 0, "every card back in place")
    } finally {
        Anim.Reset()
        UiDashClose(d)
        try DirDelete(dir, true)
    }
}

; no two shown, clickable or editable Look controls overlap
UiLookNoOverlap(d, what) {
    items := []
    for c in d._pages[UiDashPageIdx("Look")].ctrls {
        if (!c.Visible || Theme.IsPanel(c))
            continue
        if (c.Type = "Edit" || c.Type = "DDL" || c.Type = "ListView" || Theme._hot.Has(c.Hwnd))
            items.Push({c: c, p: UiDashPos(c)})
    }
    AssertTrue(items.Length >= 20, what ": controls found (" items.Length ")")
    for i, a in items {
        loop items.Length - i {
            b := items[i + A_Index]
            AssertTrue(!UiDashOverlap(a.p, b.p), what ": '" a.c.Text "' " a.p.x "," a.p.y " clear of '" b.c.Text "' " b.p.x "," b.p.y)
        }
    }
}

; Home > Stats: the second panel switches between this run and all time
; the hunt rows (orbs, minions, hunts, deaths) in all three views, every row
; inside its panel and clear of the next, the 7-day list below them
Test_Dashboard_StatsHuntRows() {
    dir := UiDashTmp()
    d := ""
    try {
        d := Dashboard(Config.Load(dir))
        d.SelectPage(UiDashPageIdx("Stats"))
        d.SetStatsPage(Map("huntOrbs", 2, "huntMinions", 9), Map("hunts", 3, "huntDeaths", 1), "", Map("huntOrbs", 40), "20261101")
        AssertEq(d.Ctrl("stats:day:huntOrbs").Text, "2", "orbs today")
        AssertEq(d.Ctrl("stats:day:huntMinions").Text, "9", "minions today")
        AssertEq(d.Ctrl("stats:run:hunts").Text, "3", "hunts this run")
        AssertEq(d.Ctrl("stats:run:huntDeaths").Text, "1", "deaths this run")
        d.Ctrl("statsView")["All time"].Flip()
        AssertEq(d.Ctrl("stats:run:huntOrbs").Text, "40", "orbs all time")
        hist := UiDashPos(d.Ctrl("stats:history"))
        for col in ["day", "run"] {
            prev := ""
            for r in Dashboard.StatRows {
                p := UiDashPos(d.Ctrl("stats:" col ":" r[1]))
                AssertTrue(p.y >= 184 && p.y + p.h <= 152 + 318, col " " r[1] " inside its panel")
                if IsObject(prev)
                    AssertTrue(prev.y + prev.h <= p.y, col " " r[1] " clear of the row above")
                prev := p
            }
            AssertTrue(prev.y + prev.h + 12 <= hist.y, col ": the rows end above the 7-day list")
        }
        AssertTrue(hist.y + hist.h <= 620 - 8, "the 7-day list inside its card (page area ends y 620)")
    } finally {
        UiDashClose(d)
        try DirDelete(dir, true)
    }
}

Test_Dashboard_StatsAllTime() {
    dir := UiDashTmp()
    d := ""
    try {
        d := Dashboard(Config.Load(dir))
        d.SelectPage(UiDashPageIdx("Stats"))
        run := Map("fishCaught", 5, "uptimeText", "0h 10m")
        all := Map("fishCaught", 1234, "fishFailed", 66, "reelRate", 95, "fishPerHour", 41.2, "uptimeText", "30h 00m")
        d.SetStatsPage(Map(), run, "", all, "20261101")
        AssertEq(d.Ctrl("stats:run:fishCaught").Text, "5", "this run first")
        AssertEq(d.Ctrl("stats:runTitle").Text, "THIS RUN", "title")
        d.Ctrl("statsView")["All time"].Flip()
        AssertEq(d.Ctrl("stats:run:fishCaught").Text, "1234", "all-time fish")
        AssertEq(d.Ctrl("stats:run:reelRate").Text, "95%", "all-time reel rate")
        AssertEq(d.Ctrl("stats:run:uptimeText").Text, "30h 00m", "all-time uptime")
        AssertTrue(InStr(d.Ctrl("stats:runTitle").Text, "ALL TIME, SINCE 1 "), "since date (" d.Ctrl("stats:runTitle").Text ")")
        ; the timer keeps feeding: all time stays shown, a new run map is kept
        d.SetStatsPage(Map(), Map("fishCaught", 6), "", Map("fishCaught", 1235), "20261101")
        AssertEq(d.Ctrl("stats:run:fishCaught").Text, "1235", "updates while shown")
        d.SetStatsPage(Map(), Map("fishCaught", 7))
        AssertEq(d.Ctrl("stats:run:fishCaught").Text, "1235", "no all-time map given: kept")
        d.Ctrl("statsView")["This run"].Flip()
        AssertEq(d.Ctrl("stats:run:fishCaught").Text, "7", "back to this run")
        ; layout: the title ends before the choice, the choice inside the panel
        t := UiDashPos(d.Ctrl("stats:runTitle"))
        a := UiDashPos(d.Ctrl("statsView")["This run"]._c)
        b := UiDashPos(d.Ctrl("statsView")["All time"]._c)
        AssertTrue(t.x + t.w <= a.x, "title clear of the choice")
        AssertTrue(b.x + b.w <= 1012 - 8 && a.y >= 152 && a.y + a.h <= 184, "choice inside the panel header")
    } finally {
        UiDashClose(d)
        try DirDelete(dir, true)
    }
}

; idea 4 (2026-11-13): every help text belongs to a real setting, and the
; settings with one show a "?" on their page
Test_Help_TextsMatchSettings() {
    dir := UiDashTmp()
    d := ""
    try {
        cfg := Config.Load(dir)
        d := Dashboard(cfg)
        bound := Map()
        for b in d._binds
            bound[StrLower(b.key)] := true
        for k, t in HelpTexts.Map {
            AssertTrue(bound.Has(k) || cfg.Get(k, "__none__") != "__none__", "a real setting: " k)
            AssertTrue(StrLen(t) >= 20 && StrLen(t) <= 220, "short plain text: " k)
        }
        n := 0
        for hwnd, txt in Theme._help
            n++
        AssertTrue(n >= 50, "a ? on most settings (" n ")")
        AssertEq(HelpTexts.For("general.FISHING"), HelpTexts.For("General.fishing"), "any case")
        AssertEq(HelpTexts.For("No.such"), "", "unknown key")
    } finally {
        UiDashClose(d)
        try DirDelete(dir, true)
    }
}

; 2026-11-16, the user: more clip apps (Discord clipping): the Clip app
; dropdown fills in the app's usual hotkey and is saved by id
Test_Dashboard_ClipAppPicker() {
    dir := UiDashTmp()
    d := ""
    try {
        cfg := Config.Load(dir)
        d := Dashboard(cfg)
        d.SelectPage(Dashboard.PageIndex("Clips"))
        dd := d.Ctrl("Medal.app")
        AssertEq(dd.Text, "Medal", "Medal by default")
        AssertTrue(InStr(d.Ctrl("clipAppRun").Text, "medal.exe"), "Medal must run")
        dd.Choose(Clip.AppIndex("discord"))
        d._ClipAppChange(dd)
        AssertEq(d.Ctrl("Medal.clipHotkey").Value, "Alt+C", "Medal's F8 became Discord's Alt+C")
        AssertTrue(InStr(d.Ctrl("clipAppTip").Text, "Discord"), "the Discord tip")
        AssertTrue(d.SavePage("Clips"), "saved")
        AssertEq(cfg.Get("Medal.app", ""), "discord", "saved by id")
        AssertEq(cfg.Get("Medal.clipHotkey", ""), "Alt+C", "with its hotkey")
        ; a key typed by hand stays when another app is picked
        d.Ctrl("Medal.clipHotkey").Value := "F6"
        dd.Choose(Clip.AppIndex("nvidia"))
        d._ClipAppChange(dd)
        AssertEq(d.Ctrl("Medal.clipHotkey").Value, "F6", "own key kept")
        d2 := Dashboard(Config.Load(dir))
        AssertEq(d2.Ctrl("Medal.app").Text, "Discord", "reloaded: Discord")
        UiDashClose(d2)
    } finally {
        UiDashClose(d)
        try DirDelete(dir, true)
    }
}

; Downloads (dev): only in a git checkout; GitHub's counts, nobody tracked
Test_Dashboard_DownloadsPanelDevOnly() {
    dir := UiDashTmp()
    d := "", d2 := ""
    old := Dashboard.DownloadsHttp
    try {
        d := Dashboard(Config.Load(dir))
        AssertEq(d.Ctrl("dlText"), "", "an unzipped release: no Downloads panel")
        AssertEq(d.PageShown("Dev tools"), false, "and no Dev tools tab")
        FileAppend("", dir "\" Updater.DevMarker)
        ; no [Update] repo in the dev copy's settings: the public repo is asked
        Dashboard.DownloadsHttp := (url) => (InStr(url, "/repos/" Brand.Repo "/releases") ? '[{"tag_name":"v1.4.5","assets":[{"download_count":7}]}]' : "")
        cfg2 := Config.Load(dir)
        cfg2.Set("Update.repo", "")
        d2 := Dashboard(cfg2)
        AssertTrue(IsObject(d2.Ctrl("dlText")), "the dev copy: the panel")
        AssertEq(d2.PageShown("Dev tools"), true, "and the Dev tools tab")
        msg := d2.RefreshDownloads()
        AssertTrue(InStr(msg, "Total: 7 downloads") && InStr(msg, "v1.4.5: 7"), "counts shown: " msg)
        Dashboard.DownloadsHttp := (url) => Updater._Fail("HTTP 403")
        AssertTrue(InStr(d2.RefreshDownloads(), "Could not read the counts"), "an error is said, not thrown")
    } finally {
        Dashboard.DownloadsHttp := old
        UiDashClose(d), UiDashClose(d2)
        try DirDelete(dir, true)
    }
}

; ---- UI size 100 / 115 / 130 % (Theme.Scale) ---------------------------------

Test_Scale_Opts() {
    old := Theme.Scale
    try {
        Theme.Scale := 130
        AssertEq(Theme.ScaleOpts("x204 y152 w396 h80 +0x200 Limit7 BackgroundFF0000"), "x265 y198 w515 h104 +0x200 Limit7 BackgroundFF0000", "x y w h scaled, the rest kept")
        AssertEq(Theme.ScaleOpts("xm+10 yp+4 s10 cFFFFFF -E0x200 r3"), "xm+13 yp+5 s10 cFFFFFF -E0x200 r3", "relative offsets scale, s / c / r stay")
        AssertEq(Theme.S(10), 13, "S rounds")
        Theme.Scale := 100
        AssertEq(Theme.ScaleOpts("x204 y152"), "x204 y152", "100 % keeps the text")
    } finally {
        Theme.Scale := old
    }
}

Test_Scale_FitScale() {
    old := Theme.DpiFn
    try {
        Theme.DpiFn := () => 96
        AssertEq(Theme.FitScale(130, 1920, 1040, 1040, 680), 130, "fits")
        AssertEq(Theme.FitScale(130, 1366, 728, 1040, 680), 100, "a small laptop")
        AssertEq(Theme.FitScale(130, 1920, 840, 1040, 680), 115, "in between")
        AssertEq(Theme.FitScale(115, 1920, 1040, 1040, 680), 115, "never above the wish")
        AssertEq(Theme.FitScale(100, 640, 480, 1040, 680), 100, "nothing fits: 100")
        Theme.DpiFn := () => 120
        AssertEq(Theme.FitScale(100, 1920, 1080, 1040, 680), 100, "1080p at 125 %: 100 fits")
        AssertEq(Theme.FitScale(130, 1920, 1080, 1040, 680), 115, "1080p at 125 %: 115 fits, 130 does not")
    } finally {
        Theme.DpiFn := old
    }
}

Test_Scale_FontsGrow() {
    old := Theme.Scale
    try {
        Theme.Scale := 130
        AssertTrue(InStr(Theme.FontOpt("body"), "s13"), "body at 130: " Theme.FontOpt("body"))
        AssertTrue(InStr(Theme.FontOpt("body", false), "s10"), "unscaled stays s10: " Theme.FontOpt("body", false))
    } finally {
        Theme.Scale := old
    }
}

Test_Scale_EveryControlInsideWindow() {
    old := Theme.Scale
    oldWa := Theme.WorkAreaFn
    Theme.WorkAreaFn := () => {w: 3840, h: 2160}
    for sc in [115, 130] {
        dir := UiDashTmp()
        d := ""
        try {
            Theme.Scale := sc
            d := Dashboard(Config.Load(dir))
            AssertEq(Theme.Scale, sc, "built at " sc)
            gw := Theme.S(Dashboard.W), gh := Theme.S(Dashboard.H)   ; GetPos is in Gui units (DPI undone)
            bad := ""
            for i, page in d._pages {
                d.SelectPage(i)
                for c in page.ctrls {
                    c.GetPos(&x, &y, &w, &h)
                    if (w = 0 || h = 0)
                        continue
                    if (x < 0 || y < 0 || x + w > gw + 1 || y + h > gh + 1) {
                        bad .= Dashboard.Pages[i] ":" c.Type ":" x "," y "," w "," h "  "
                        if (StrLen(bad) > 600)
                            break
                    }
                }
            }
            t := Theme.Pos(d.Ctrl("tab:Run")), u := UiDashPos(d.Ctrl("tab:Run"))
            AssertEq(t.y "," t.h, "104,26", "the tab strip reads back in 100 % units at " sc " %")
            AssertTrue(u.y > 104 && u.h > 26, "and is really bigger on screen: " u.y "," u.h)
            AssertEq(bad, "", "controls outside the " gw "x" gh " client at " sc " %")
        } finally {
            Theme.Scale := old
            UiDashClose(d)
            try DirDelete(dir, true)
        }
    }
    Theme.WorkAreaFn := oldWa
}

Test_Scale_RefusedOverWorkArea() {
    old := Theme.Scale
    oldWa := Theme.WorkAreaFn
    dir := UiDashTmp()
    d := ""
    try {
        Theme.WorkAreaFn := () => {w: 1366, h: 728}
        Theme.Scale := 130
        d := Dashboard(Config.Load(dir))
        AssertEq(Theme.Scale, 100, "built at 100")
        AssertTrue(InStr(d.LogText(), "100 %") && InStr(d.LogText(), "130 %"), "the log names the size used: " d.LogText())
    } finally {
        Theme.WorkAreaFn := oldWa
        Theme.Scale := old
        UiDashClose(d)
        try DirDelete(dir, true)
    }
}

; ---- cards (every control of a page belongs to exactly one card) -----------

; "Type 'text' x,y wxh" of a control, for failure messages.
UiCardDesc(c) {
    p := Theme.Pos(c)
    t := ""
    try t := SubStr(RegExReplace(c.Text, "\s+", " "), 1, 24)
    return c.Type " '" t "' " p.x "," p.y " " p.w "x" p.h
}

; Every page: each control has one card (a card, loose or fixed), the cards'
; lists hold each control once, no control is loose, and each control of a
; card lies inside that card's frame (1 px slack for rounding).
Test_Cards_EveryControlHasOneCard() {
    dir := UiDashTmp()
    d := ""
    try {
        d := Dashboard(Config.Load(dir))
        AssertTrue(!(Theme.Sink is Array), "Sink cleared after the build (a later control cannot slip into a page)")
        bad := ""
        for name in Dashboard.Pages {
            page := d._PageByName(name)
            cards := d.Cards(name)
            AssertTrue(cards is Array, name ": Cards is an Array")
            seen := Map(), ids := Map()
            for card in cards {
                AssertEq(SubStr(card.id, 1, StrLen(name) + 1), name ":", "card id starts with the page")
                if ids.Has(card.id)
                    bad .= "`n" name ": card id twice: " card.id
                ids[card.id] := true
                f := Theme.Pos(card.frame)
                AssertEq(card.x "," card.y "," card.w "," card.h, f.x "," f.y "," f.w "," f.h, card.id ": x/y/w/h are the frame's")
                if (f.x < 204 || f.x + f.w > 1012 || f.y < 152 || f.y + f.h > 620)
                    bad .= "`n" card.id ": frame outside the page area (204..1012 x 152..620): " f.x "," f.y " " f.w "x" f.h
                for c in card.ctrls {
                    if seen.Has(c.Hwnd)
                        bad .= "`n" name ": in two cards: " UiCardDesc(c)
                    seen[c.Hwnd] := card.id
                    if (d.CardOf(c) != card.id)
                        bad .= "`n" name ": CardOf " d.CardOf(c) " but listed in " card.id
                    p := Theme.Pos(c)
                    if (p.x < f.x - 1 || p.y < f.y - 1 || p.x + p.w > f.x + f.w + 1 || p.y + p.h > f.y + f.h + 1)
                        bad .= "`n" card.id ": outside its card (" f.x "," f.y " " f.w "x" f.h "): " UiCardDesc(c)
                }
            }
            for c in page.ctrls {
                id := d.CardOf(c)
                if (id = name ":fixed")
                    continue
                if (Theme.Pos(c).y >= 622)
                    bad .= "`n" name ": in the save-bar row but not fixed (" id "): " UiCardDesc(c)
                if (id = name ":loose")
                    bad .= "`n" name ": loose: " UiCardDesc(c)
                else if !seen.Has(c.Hwnd)
                    bad .= "`n" name ": no card (" id "): " UiCardDesc(c)
            }
        }
        AssertEq(d.CardOf(d.Ctrl("desc:Settings")), "Settings:fixed", "the subtitle is fixed")
        AssertEq(d.CardOf(d.Ctrl("hubTitle")), "", "a header control has no card")
        AssertEq(d.CardOf(""), "", "not a control: no card")
        AssertEq(d.Cards("NoSuchPage").Length, 0, "an unknown page has no cards")
        AssertEq(bad, "", "card offenders")
        AssertEq(d.CardOf(d.Ctrl("calStatus")), "Calibrate:fixed", "the Calibrate bottom bar is fixed")
        AssertEq(d.CardOf(d._logCount), "Log:fixed", "the Log bottom bar is fixed")
        AssertTrue(InStr(UiCardIds(d, "Run"), "Run:#1"), "Run's Start / Pause / Stop row is a card: " UiCardIds(d, "Run"))
    } finally {
        UiDashClose(d)
        try DirDelete(dir, true)
    }
}

UiCardIds(d, page) {
    s := ""
    for card in d.Cards(page)
        s .= (s = "" ? "" : "|") card.id
    return s
}

Test_Cards_IdsStable() {
    dir := UiDashTmp()
    d := ""
    try {
        d := Dashboard(Config.Load(dir))
        ids := Map()
        for card in d.Cards("Settings")
            ids[card.id] := card
        for t in ["Private server", "Routes", "Intervals", "Recovery", "Alerts", "Hotkeys"]
            AssertTrue(ids.Has("Settings:" t), "Settings has card " t ": " UiCardIds(d, "Settings"))
        AssertTrue(!ids.Has("Settings:Look"), "Look moved off Settings: " UiCardIds(d, "Settings"))
        for card in d.Cards("Look")
            ids[card.id] := card
        look := ids["Look:Theme"]
        AssertEq(look.title, "Theme", "title is the English title")
        AssertTrue(look.frame == d.Ctrl("panel:Look:Theme"), "frame is the panel frame")
        AssertTrue(look.caption == d.Ctrl("panelTitle:Look:Theme"), "caption is the panel title")
        AssertTrue(IsObject(look.fill) && Theme.IsPanel(look.fill), "fill is the panel fill")
        AssertEq(d.CardOf(look.frame), "Look:Theme", "the frame belongs to its card")
        AssertEq(d.CardOf(d.Ctrl("look:list")), "Look:Theme", "a Look control is in its card")
        AssertTrue(InStr(UiCardIds(d, "Biomes & Potions"), "Biomes & Potions:#1"), "an untitled card is #1: " UiCardIds(d, "Biomes & Potions"))
        AssertEq(UiCardIds(d, "Biomes & Potions"), "Biomes & Potions:#1|Biomes & Potions:Biomes", "Biomes cards")
        AssertEq(UiCardIds(d, "Potions"), "Potions:#1|Potions:Potions", "Potions cards")
    } finally {
        UiDashClose(d)
        try DirDelete(dir, true)
    }
}

; Built in Spanish every page has the same card ids as in English.
Test_Cards_IdsIgnoreLanguage() {
    dir := UiDashTmp()
    d := "", d2 := ""
    try {
        I18n.Use("en")
        d := Dashboard(Config.Load(dir))
        en := Map()
        for name in Dashboard.Pages
            en[name] := UiCardIds(d, name)
        UiDashClose(d), d := ""
        AssertEq(I18n.Use("es"), "es", "Spanish in use")
        d2 := Dashboard(Config.Load(dir))
        AssertTrue(d2.Ctrl("panelTitle:Look:Colours").Text != "COLOURS", "built in Spanish")
        for name in Dashboard.Pages
            AssertEq(UiCardIds(d2, name), en[name], name " card ids")
    } finally {
        I18n.Use("en")
        UiDashClose(d)
        UiDashClose(d2)
        try DirDelete(dir, true)
    }
}

; ---- sidebar left / right / top ----------------------------------------------

; Builds a dashboard for each sidebar side, runs fn(side, d) and closes it.
; Theme.Sidebar / Scale / Layout are restored after each.
SbEach(fn, sides := "") {
    oldSb := Theme.Sidebar, oldSc := Theme.Scale, oldLy := Theme.Layout
    oldWa := Theme.WorkAreaFn
    for side in (sides = "" ? ["left", "right", "top"] : sides) {
        dir := UiDashTmp()
        d := ""
        try {
            Theme.WorkAreaFn := () => {w: 3840, h: 2160}
            Theme.Scale := 100
            Theme.Layout := Map()
            Theme.Sidebar := side
            d := Dashboard(Config.Load(dir))
            fn.Call(side, d)
        } finally {
            Theme.Sidebar := oldSb, Theme.Scale := oldSc, Theme.Layout := oldLy
            Theme.WorkAreaFn := oldWa
            Anim.Reset()
            UiDashClose(d)
            try DirDelete(dir, true)
        }
    }
}

; Hub and chip controls that are shown (the sidebar's contents).
SbNavCtrls(d) {
    out := [d._chip]
    for i, c in d._nav {
        if c.Visible
            out.Push(c)
    }
    return out
}

Test_Sidebar_PageShift() {
    s := Dashboard.PageShift("left")
    AssertEq(s.dx "," s.dy "," s.extraH, "0,0,0", "left")
    s := Dashboard.PageShift("right")
    AssertEq(s.dx "," s.dy "," s.extraH, "-176,0,0", "right")
    s := Dashboard.PageShift("top")
    AssertEq(s.dx "," s.dy "," s.extraH, "-176,48,48", "top")
    s := Dashboard.PageShift("nonsense")
    AssertEq(s.dx "," s.dy "," s.extraH, "0,0,0", "an unknown side is left")
}

Test_Sidebar_NoPageUnderIt() {
    SbEach((side, d) => SbCheckNoPageUnder(side, d))
}

SbCheckNoPageUnder(side, d) {
    ovR := (a, b) => !(a.x + a.w <= b.x || b.x + b.w <= a.x || a.y + a.h <= b.y || b.y + b.h <= a.y)
    gw := Dashboard.W, gh := Dashboard.H + Dashboard.PageShift(side).extraH
    band := side = "right" ? {x: 864, y: 60, w: 176, h: 620} : side = "top" ? {x: 0, y: 59, w: 1040, h: 49} : {x: 0, y: 60, w: 176, h: 620}
    keep := [band]
    for c in SbNavCtrls(d)
        keep.Push(UiDashPos(c))
    bad := ""
    for i, page in d._pages {
        for c in page.ctrls {
            p := UiDashPos(c)
            if (p.w = 0 || p.h = 0)
                continue
            if (p.x < 0 || p.y < 0 || p.x + p.w > gw || p.y + p.h > gh)
                bad .= side " outside: " Dashboard.Pages[i] ":" UiCardDesc(c) "  "
            for k in keep {
                if ovR(p, k)
                    bad .= side " under sidebar: " Dashboard.Pages[i] ":" UiCardDesc(c) "  "
            }
            if (StrLen(bad) > 700)
                break 2
        }
    }
    AssertEq(bad, "", "page controls, " side)
    ; every control of the window is inside it
    for c in d._gui {
        p := UiDashPos(c)
        if (p.w && p.h && (p.x < 0 || p.y < 0 || p.x + p.w > gw || p.y + p.h > gh))
            bad .= c.Type ":" p.x "," p.y "," p.w "," p.h "  "
    }
    AssertEq(bad, "", "window controls inside " gw "x" gh ", " side)
    ; the page area follows the shift, and the cards lie where the left layout had them, moved
    a := d.PageArea(), sh := Dashboard.PageShift(side)
    AssertEq(a.x "," a.y "," a.w, 204 + sh.dx "," 152 + sh.dy "," (side = "top" ? 984 : 808), side " page area")
    card := LyCard(d, "Settings:Recovery")
    AssertEq(card.x "," card.y, 204 + sh.dx "," 428 + sh.dy, side " Recovery card moved with the page")
    AssertTrue(card.x >= a.x && card.y >= a.y, side " card inside the page area's corner")
    ; ApplyLayout with no entry puts a card back in the shifted place
    card := d.Cards("Run")[1]
    x0 := card.x, y0 := card.y
    d.ApplyLayout("Run", Map("Run:#1", [x0 + 16, y0 + 8, card.w, card.h, 0]))
    d.ApplyLayout("Run", Map())
    AssertEq(card.x "," card.y, x0 "," y0, side ": back in the shifted built place")
    ; the tab strip, title and underline sit with the page
    sh := Dashboard.PageShift(side)
    AssertEq(UiDashPos(d.Ctrl("hubTitle")).x "," UiDashPos(d.Ctrl("hubTitle")).y, 204 + sh.dx "," 66 + sh.dy, side " hub title")
}

Test_Sidebar_HubsClickable() {
    SbEach((side, d) => SbCheckHubs(side, d))
}

SbCheckHubs(side, d) {
    d._NavClick(3)
    AssertEq(d.ActivePage, Dashboard.Hubs[3].pages[1], side ": hub 3 shows its first page")
    n := d._nav[3]
    AssertTrue(n.Visible, side ": hub 3 control shown")
    p := UiDashPos(n)
    AssertTrue(p.w > 20 && p.h > 10, side ": hub 3 has a size")
    ; hubs never overlap each other
    ovR := (a, b) => !(a.x + a.w <= b.x || b.x + b.w <= a.x || a.y + a.h <= b.y || b.y + b.h <= a.y)
    all := SbNavCtrls(d)
    for i, a in all {
        for j, b in all {
            if (i < j)
                AssertTrue(!ovR(UiDashPos(a), UiDashPos(b)), side ": sidebar controls " i " and " j " overlap")
        }
    }
    d._NavClick(1)
    AssertEq(d.ActivePage, "Run", side ": back to Home")
    ; the fade cover reaches over the page area
    b := d.PageBox()
    sh := Dashboard.PageShift(side)
    AssertEq(b.x "," b.y "," b.w "," b.h, (side = "left" ? "176" : "0") "," 150 + sh.dy "," (side = "top" ? 1040 : 864) ",470", side ": cover box")
}

Test_Sidebar_StarsClear() {
    SbEach((side, d) => SbCheckStars(side, d))
}

SbCheckStars(side, d) {
    ovR := (a, b) => !(a.x + a.w <= b.x || b.x + b.w <= a.x || a.y + a.h <= b.y || b.y + b.h <= a.y)
    keep := [{x: 18, y: 10, w: 40, h: 40}, {x: 66, y: 5, w: 300, h: 50}, UiDashPos(d.Ctrl("credits.banner"))
        , UiDashPos(d._pill), {x: 764, y: 16, w: 256, h: 28}]
    for c in SbNavCtrls(d)
        keep.Push(UiDashPos(c))
    sb := side = "right" ? {x: 864, y: 60, w: 176, h: 620} : {x: 0, y: 60, w: 176, h: 620}
    n := 0
    while IsObject(s := d.Ctrl("star" (n + 1))) {
        n++
        p := UiDashPos(s)
        inSide := side != "top" && !(p.x < sb.x || p.x + p.w > sb.x + sb.w || p.y < sb.y)
        AssertTrue(p.y + p.h <= 59 || inSide, side ": star " n " in the header or sidebar: " p.x "," p.y)
        for k in keep
            AssertTrue(!ovR(p, k), side ": star " n " at " p.x "," p.y " clear of " k.x "," k.y "," k.w "," k.h)
    }
    AssertTrue(n >= 6 && n <= 12, side ": 6-12 stars (" n ")")
}

; The shown size counts the top mode's extra 48 px, and the work-area fit
; check counts it too: a screen that fits 130 % for left but not for top.
Test_Sidebar_FitCountsTopExtraHeight() {
    oldSb := Theme.Sidebar, oldSc := Theme.Scale, oldWa := Theme.WorkAreaFn, oldDpi := Theme.DpiFn
    try {
        Theme.DpiFn := () => 96
        ; left 680 * 1.3 = 884 + 40 = 924 fits 930; top 728 * 1.3 = 946 + 40 = 986 does not (115 % = 877 does)
        Theme.WorkAreaFn := () => {w: 1920, h: 930}
        res := Map()
        for side in ["left", "top"] {
            dir := UiDashTmp()
            d := ""
            try {
                Theme.Sidebar := side
                Theme.Scale := 130
                d := Dashboard(Config.Load(dir))
                res[side] := Theme.Scale
                sz := d.ShownSize()
                AssertEq(sz.h, Theme.S(Dashboard.H + Dashboard.PageShift(side).extraH), side ": shown height")
            } finally {
                Anim.Reset()
                UiDashClose(d)
                try DirDelete(dir, true)
            }
        }
        AssertEq(res["left"], 130, "left fits 130 %")
        AssertEq(res["top"], 115, "top does not fit 130 % (48 px taller)")
    } finally {
        Theme.Sidebar := oldSb, Theme.Scale := oldSc, Theme.WorkAreaFn := oldWa, Theme.DpiFn := oldDpi
    }
}

; ---- Edit layout mode (spec 2026-11-18 section 2) ----------------------------
; Uses LyCard / LyPositions from test_layout.ahk (same script).

; every control inside the dashboard window (the edit overlay's included)
EdCount(d) {
    old := DetectHiddenWindows(true)
    try return WinGetControls("ahk_id " d.Hwnd).Length
    finally DetectHiddenWindows(old)
    return -1
}

; real (pixel) place of every control of a card, hwnd -> "x,y,w,h"
EdReal(card) {
    m := Map()
    for c in card.ctrls {
        p := UiDashPos(c)
        m[c.Hwnd] := p.x "," p.y "," p.w "," p.h
    }
    return m
}

EdSame(a, b) {
    if (a.Count != b.Count)
        return false
    for k, v in a
        if (!b.Has(k) || b[k] != v)
            return false
    return true
}

EdRect(card) {
    p := Theme.Pos(card.frame)
    return p.x "," p.y "," p.w "," p.h
}

EdEntry(d, id) {
    m := d.LayoutEntries()
    if !m.Has(id)
        return ""
    e := m[id]
    return e[1] "," e[2] "," e[3] "," e[4] "," e[5]
}

Test_EditLayout_DragSnapsAndClamps() {
    dir := UiDashTmp()
    d := ""
    try {
        cfg := Config.Load(dir)
        d := UiLookDash(cfg)
        d.SelectPage(UiDashPageIdx("Settings"))
        page := d._PageByName("Settings")
        n0 := EdCount(d), nCtl := page.ctrls.Length, nCard := d._cardOf.Count
        AssertTrue(n0 > 100, "controls counted (" n0 ")")
        AssertEq(d.Ctrl("layout:handle:Settings:Recovery"), "", "no handle out of edit mode")
        AssertEq(d.EditLayout(true), true, "edit mode on")
        AssertEq(d.Ctrl("look:editLayout").Value, 1, "the Look switch shows it")
        for id in ["layout:handle:Settings:Recovery", "layout:grip:Settings:Recovery", "layout:eye:Settings:Recovery"
                , "layout:handle:Settings:Intervals", "layout:done", "layout:cancel", "layout:note"]
            AssertTrue(IsObject(d.Ctrl(id)), id " exists while editing")
        AssertTrue(EdCount(d) > n0, "the handles are extra controls")
        AssertEq(page.ctrls.Length, nCtl, "no edit control joins the page")
        AssertEq(d._cardOf.Count, nCard, "nor the card registry")
        card := LyCard(d, "Settings:Recovery")
        a := d.PageArea()
        x0 := card.x
        AssertEq(d.DragCard("Settings:Recovery", 13, -1000), true, "dragged")
        f := Theme.Pos(card.frame)
        AssertEq(f.x, x0 + 16, "13 snaps to 16")
        AssertEq(Mod(f.x - a.x, Layout.Grid), 0, "x on the grid")
        AssertEq(f.y, a.y, "-1000 stops at the top of the page area")
        AssertEq(EdEntry(d, "Settings:Recovery"), EdRect(card) ",0", "the entry is the place shown")
        h := Theme.Pos(d.Ctrl("layout:handle:Settings:Recovery"))
        AssertTrue(h.x >= f.x && h.y >= f.y && h.x + h.w <= f.x + f.w && h.y + h.h <= f.y + f.h, "the handle moved with the card")
        d.DragCard("Settings:Recovery", 5000, 0)
        f := Theme.Pos(card.frame)
        AssertEq(f.x + f.w, a.x + a.w, "the right edge stops at the page area")
        AssertEq(EdEntry(d, "Settings:Recovery"), EdRect(card) ",0", "the entry is the clamped place, not the asked one")
        AssertEq(d.DragCard("Nope:Card", 8, 8), false, "an unknown card is refused")
        AssertEq(d.DragCard("Settings:Recovery", "x", []), false, "bad deltas refused")
        ; the mouse loop core: pixels -> 100 % units, snapped; Escape puts it back
        before := StrSplit(EdRect(card), ","), ent := EdEntry(d, "Settings:Recovery")
        d._DragBegin("move", "Settings:Recovery", 500, 500)
        AssertTrue(d.Dragging(), "a drag runs")
        d._DragStep(500 - Theme.Dpi(Theme.S(26)), 500 + Theme.Dpi(Theme.S(10)), true, false)
        f := Theme.Pos(card.frame)
        AssertEq(f.x "," f.y, (before[1] - 24) "," (before[2] + 8), "moved by the snapped mouse delta")
        d._DragStep(500, 500, true, true)
        AssertEq(EdRect(card), before[1] "," before[2] "," before[3] "," before[4], "Escape puts the card back")
        AssertEq(EdEntry(d, "Settings:Recovery"), ent, "and its entry")
        AssertTrue(!d.Dragging(), "Escape ends the drag")
        d._DragBegin("size", "Settings:Recovery", 0, 0)
        d._DragStep(-Theme.Dpi(Theme.S(40)), Theme.Dpi(Theme.S(16)), false, false)
        AssertEq(Theme.Pos(card.frame).h, before[4] + 16, "the grip resizes")
        AssertTrue(!d.Dragging(), "released: the drag ends")
        ; the loop stops by itself when the window is not in front (tests:
        ; hidden), and the half-done drag is put back like Escape
        r1 := EdRect(card), e1 := EdEntry(d, "Settings:Recovery")
        d._DragBegin("move", "Settings:Recovery", 0, 0)
        d._DragStep(-Theme.Dpi(Theme.S(48)), 0, true, false)
        AssertTrue(EdRect(card) != r1, "the drag moved the card")
        d._DragTick()
        AssertTrue(!d.Dragging(), "not in front: the loop ends")
        AssertEq(EdRect(card), r1, "and the card goes back")
        AssertEq(EdEntry(d, "Settings:Recovery"), e1, "with its entry")
        ; Cancel: every edit control is gone
        AssertTrue(d.LayoutCancel(), "cancelled")
        AssertEq(d.LayoutEditing(), false, "edit mode off")
        AssertEq(d.Ctrl("look:editLayout").Value, 0, "the Look switch is off")
        for id in ["layout:handle:Settings:Recovery", "layout:grip:Settings:Recovery", "layout:eye:Settings:Recovery", "layout:done", "layout:note"]
            AssertEq(d.Ctrl(id), "", id " gone")
        AssertEq(EdCount(d), n0, "no extra control out of edit mode")
        AssertEq(page.ctrls.Length, nCtl, "page controls unchanged")
    } finally {
        UiDashClose(d)
        try DirDelete(dir, true)
    }
}

Test_EditLayout_ResizeMin() {
    dir := UiDashTmp()
    d := ""
    try {
        d := UiLookDash(Config.Load(dir))
        d.SelectPage(UiDashPageIdx("Settings"))
        d.EditLayout(true)
        card := LyCard(d, "Settings:Recovery")
        mn := Layout.MinSize(card)
        x0 := card.x, y0 := card.y
        AssertTrue(d.ResizeCard("Settings:Recovery", -1000, -1000), "resized")
        f := Theme.Pos(card.frame), fl := Theme.Pos(card.fill)
        AssertEq(f.w "x" f.h, mn.w "x" mn.h, "at its MinSize")
        AssertEq(fl.w "x" fl.h, (mn.w - 2) "x" (mn.h - 2), "the fill follows")
        AssertEq(f.x "," f.y, x0 "," y0, "a resize does not move the card")
        AssertEq(EdEntry(d, "Settings:Recovery"), EdRect(card) ",0", "the entry is the size shown")
        gp := Theme.Pos(d.Ctrl("layout:grip:Settings:Recovery"))
        AssertTrue(gp.x + gp.w <= f.x + f.w && gp.x + gp.w >= f.x + f.w - 4 && gp.y + gp.h <= f.y + f.h && gp.y + gp.h >= f.y + f.h - 4
            , "the grip sits in the new bottom right corner")
        d.ResizeCard("Settings:Recovery", 5000, 0)
        f := Theme.Pos(card.frame)
        a := d.PageArea()
        AssertEq(f.x, x0, "growing does not move it either")
        AssertEq(f.x + f.w, a.x + a.w, "it grows up to the page area's edge")
        AssertEq(d.ResizeCard("Nope:Card", 8, 8), false, "an unknown card is refused")
        d.LayoutCancel()
    } finally {
        UiDashClose(d)
        try DirDelete(dir, true)
    }
}

Test_EditLayout_OverlapNote() {
    dir := UiDashTmp()
    d := ""
    try {
        d := UiLookDash(Config.Load(dir))
        d.SelectPage(UiDashPageIdx("Settings"))
        d.EditLayout(true)
        note := d.Ctrl("layout:note")
        AssertEq(note.Text, "", "no note while nothing overlaps")
        rec := LyCard(d, "Settings:Recovery"), itv := LyCard(d, "Settings:Intervals")
        d.DragCard("Settings:Recovery", 0, itv.y - rec.y)
        AssertTrue(InStr(note.Text, I18n.T("Recovery")) && InStr(note.Text, I18n.T("Intervals")), "the note names both cards: " note.Text)
        AssertTrue(note.Visible, "and is shown")
        AssertEq(d.LayoutOutline("Settings:Recovery"), "red", "Recovery has the red outline")
        AssertEq(d.LayoutOutline("Settings:Intervals"), "red", "so has Intervals")
        AssertTrue(d.Ctrl("layout:outline:Settings:Recovery").Visible, "the outline is shown")
        AssertEq(d.LayoutOutline("Settings:Private server"), "", "a card clear of both has none")
        d.DragCard("Settings:Recovery", 0, 180)
        AssertEq(note.Text, "", "moved apart: the note clears")
        AssertEq(d.LayoutOutline("Settings:Recovery") d.LayoutOutline("Settings:Intervals"), "", "and both outlines")
        ; the eye hides a card: a dashed outline while editing, its controls hidden
        AssertTrue(d.ToggleCard("Settings:Recovery"), "hidden")
        AssertEq(d.LayoutOutline("Settings:Recovery"), "dashed", "a hidden card is a dashed outline")
        vis := 0
        for c in rec.ctrls
            vis += c.Visible ? 1 : 0
        AssertEq(vis, 0, "its controls are hidden")
        AssertTrue(!d.Ctrl("layout:handle:Settings:Recovery").Visible && d.Ctrl("layout:eye:Settings:Recovery").Visible, "no handle, the eye stays")
        AssertEq(SubStr(EdEntry(d, "Settings:Recovery"), -1), "1", "the entry says hidden")
        d.DragCard("Settings:Recovery", 0, itv.y - rec.y)
        AssertEq(note.Text, "", "a hidden card overlaps nothing")
        d.DragCard("Settings:Recovery", 0, 180)
        AssertTrue(d.ToggleCard("Settings:Recovery"), "shown again")
        AssertEq(d.LayoutOutline("Settings:Recovery"), "", "no outline")
        AssertTrue(rec.frame.Visible, "its frame is back")
        AssertEq(d.ToggleCard("Nope:Card"), false, "an unknown card is refused")
        d.LayoutCancel()
    } finally {
        UiDashClose(d)
        try DirDelete(dir, true)
    }
}

Test_EditLayout_CancelRestores() {
    dir := UiDashTmp()
    d := ""
    oldLay := Theme.Layout
    try {
        cfg := Config.Load(dir)
        UiLookSaved(cfg, "Mine")
        cfg.Set("UI.theme", "Mine")
        file := ThemeStore.Dir(cfg) "\Mine" ThemeStore.Ext
        AssertTrue(FileExist(file) != "", "Mine's file: " file)
        text0 := FileRead(file, "UTF-8")
        d := UiLookDash(cfg)
        AssertEq(d.LookName(), "Mine", "Mine is open on Look")
        idx := UiDashPageIdx("Settings")
        d.SelectPage(idx)
        page := d._PageByName("Settings")
        built := LyPositions(page)
        vis0 := Map()
        for c in page.ctrls
            vis0[c.Hwnd] := c.Visible
        stats := d._PageByName("Stats")
        builtStats := LyPositions(stats)
        d.EditLayout(true)
        d.DragCard("Settings:Recovery", 40, -24)
        d.ResizeCard("Settings:Private server", 24, 16)
        d.ToggleCard("Settings:Intervals")
        d.DragCard("Stats:Last 7 days", 0, -16)
        AssertTrue(!LyCard(d, "Settings:Intervals").frame.Visible, "Intervals hidden while editing")
        AssertTrue(d.LayoutCancel(), "cancelled")
        AssertTrue(EdSame(LyPositions(page), built), "every Settings control is back where it was")
        AssertTrue(EdSame(LyPositions(stats), builtStats), "and on Stats")
        bad := ""
        for c in page.ctrls
            if (c.Visible != vis0[c.Hwnd])
                bad .= " " UiCardDesc(c)
        AssertEq(bad, "", "every control shown or hidden as before")
        AssertEq(FileRead(file, "UTF-8"), text0, "the theme file is unchanged")
        AssertTrue(Theme.Layout = oldLay, "the theme layout in use is unchanged")
        ; ApplyLayout (carried from the layout review): the same layout twice
        ; gives the same places; removing the entry puts every control back
        lay := Map("Settings:Recovery", [300, 200, 420, 150, 0])
        d.ApplyLayout("Settings", lay)
        p1 := LyPositions(page)
        d.ApplyLayout("Settings", lay)
        AssertTrue(EdSame(LyPositions(page), p1), "the same layout twice: the same places")
        d.ApplyLayout("Settings", Map())
        AssertTrue(EdSame(LyPositions(page), built), "entry removed: every control at its built place")
        ; a layout-hidden card's control stays hidden through _SetHidden
        rec := LyCard(d, "Settings:Recovery")
        d.ApplyLayout("Settings", Map("Settings:Recovery", [rec.x, rec.y, rec.w, rec.h, 1]))
        c := ""
        for x in rec.ctrls
            if (x != rec.frame && x != rec.fill && !d._hidden.Has(x.Hwnd))
                c := x
        AssertTrue(IsObject(c), "a control of Recovery")
        d._SetHidden(c, false)
        AssertEq(c.Visible, false, "_SetHidden(false) keeps a layout-hidden control hidden")
        d.ApplyLayout("Settings", Map())
        AssertEq(c.Visible, true, "shown again once the layout lets it")
        ; one bad card does not stop the rest of the page
        fx := StrSplit(built[rec.frame.Hwnd], ",")[1]
        cards := d._cards["Settings"]
        cards.InsertAt(1, {id: "Settings:Bad", title: "Bad", frame: "", fill: "", caption: "", ctrls: ["junk"], x: 210, y: 160, w: 40, h: 40})
        try {
            d.ApplyLayout("Settings", Map("Settings:Bad", [220, 170, 40, 40, 0], "Settings:Recovery", [rec.x + 8, rec.y, rec.w, rec.h, 0]))
        } finally
            cards.RemoveAt(1)
        AssertEq(Theme.Pos(rec.frame).x, fx + 8, "the card after a bad one is still placed")
        d.ApplyLayout("Settings", Map())
    } finally {
        Theme.Layout := oldLay
        Theme.Use("Moontide")
        UiDashClose(d)
        try DirDelete(dir, true)
    }
}

Test_EditLayout_DoneSaves() {
    dir := UiDashTmp()
    d := ""
    oldLay := Theme.Layout
    try {
        cfg := Config.Load(dir)
        d := UiLookDash(cfg)
        asked := []
        d._lookAsk := (title, text, ok, cancel) => (asked.Push(title), false)
        d.SelectPage(UiDashPageIdx("Settings"))
        card := LyCard(d, "Settings:Recovery")
        ; nothing changed: Done just ends, a preset is not copied
        d.EditLayout(true)
        AssertEq(d.LayoutDone(), true, "Done with no change")
        AssertEq(asked.Length, 0, "nothing asked")
        AssertEq(UiLookFiles(cfg), 0, "nothing written")
        ; a preset in use: Done asks to make a copy; a no keeps editing
        d.EditLayout(true)
        d.DragCard("Settings:Recovery", 0, -16)
        want := EdRect(card)
        AssertTrue(d.LayoutDone() != true, "a no: not saved")
        AssertTrue(InStr(d.Ctrl("layout:note").Text, "built in") && d.Ctrl("layout:note").Visible, "the reason shows above the page: " d.Ctrl("layout:note").Text)
        AssertTrue(InStr(d.Ctrl("look:note").Text, "built in"), "and on Look")
        AssertEq(asked.Length, 1, "asked to make a copy")
        AssertEq(d.LayoutEditing(), true, "still editing")
        AssertEq(UiLookFiles(cfg), 0, "nothing written")
        d._lookAsk := (title, text, ok, cancel) => (asked.Push(title), true)
        AssertEq(d.LayoutDone(), true, "a yes: saved")
        AssertEq(asked.Length, 2, "asked once more")
        AssertTrue(ThemeStore.Exists(cfg, "Moontide copy"), "the copy was made")
        e := ThemeStore.Load(cfg, "Moontide copy")["layout"]
        AssertTrue(e.Has("Settings:Recovery"), "the copy holds the entry")
        AssertEq(e["Settings:Recovery"][1] "," e["Settings:Recovery"][2] "," e["Settings:Recovery"][3] "," e["Settings:Recovery"][4], want, "the place shown")
        AssertEq(Config.Load(dir).Get("UI.theme", ""), "Moontide copy", "the copy is the theme in use")
        AssertEq(ThemeStore.Load(cfg, "Moontide")["layout"].Count, 0, "Moontide unchanged")
        AssertEq(d.LayoutEditing(), false, "edit mode ends")
        AssertEq(EdRect(card), want, "the card stays where it was put")
        AssertTrue(Theme.Layout.Has("Settings:Recovery"), "the layout in use holds it")
        ; a saved theme in use: Done saves at once
        d.EditLayout(true)
        d.DragCard("Settings:Recovery", 0, 8)
        want := EdRect(card)
        AssertEq(d.LayoutDone(), true, "saved")
        AssertEq(asked.Length, 2, "nothing asked")
        e := ThemeStore.Load(cfg, "Moontide copy")["layout"]["Settings:Recovery"]
        AssertEq(e[1] "," e[2] "," e[3] "," e[4], want, "the new place is saved")
        ; while editing, the open theme cannot change (Done saves into it)
        UiLookSaved(cfg, "Other")
        other := ThemeStore.Dir(cfg) "\Other" ThemeStore.Ext
        otherText := FileRead(other, "UTF-8")
        d._LookFillList()
        d.EditLayout(true)
        d.DragCard("Settings:Recovery", 0, -8)
        want := EdRect(card)
        AssertEq(d.LookSelect("Other"), false, "picking another theme is refused")
        AssertTrue(InStr(d.Ctrl("look:note").Text, I18n.T("Finish or cancel the layout edit first.")), "the note says why")
        AssertEq(d.LookName(), "Moontide copy", "the open theme is unchanged")
        AssertEq(d.LookDuplicate(), "", "Duplicate refused")
        AssertTrue(d.LookRename("Renamed") != true, "Rename refused")
        AssertEq(d.LookDelete(), false, "Delete refused")
        AssertTrue(d.LookImport(other).HasProp("error"), "Import refused")
        AssertTrue(ThemeStore.Exists(cfg, "Moontide copy") && !ThemeStore.Exists(cfg, "Renamed") && !ThemeStore.Exists(cfg, "Moontide copy copy"), "no theme made, renamed or deleted")
        AssertEq(d.ApplyTheme(), false, "Apply waits too")
        ; Done also saves other unsaved Look changes, and says so
        AssertTrue(d.LookSet("Accent", "FF00AA"), "an unsaved colour")
        AssertEq(d.LayoutDone(), true, "Done")
        AssertTrue(InStr(d.Ctrl("look:note").Text, I18n.F("Layout and your other Look changes saved into {1}.", "Moontide copy")), "the note says both were saved: " d.Ctrl("look:note").Text)
        t := ThemeStore.Load(cfg, "Moontide copy")
        AssertEq(t["layout"]["Settings:Recovery"][2], Integer(StrSplit(want, ",")[2]), "saved into the theme being edited")
        AssertEq(t["colors"]["Accent"], "FF00AA", "with the colour")
        AssertEq(FileRead(other, "UTF-8"), otherText, "Other's file unchanged")
        ; the switch: off with changes asks; a yes saves
        d.Ctrl("look:editLayout").Flip()
        AssertEq(d.LayoutEditing(), true, "the switch starts edit mode")
        d.DragCard("Settings:Recovery", 0, 8)
        want := EdRect(card)
        d.Ctrl("look:editLayout").Flip()
        AssertEq(asked.Length, 3, "switching off with changes asks")
        AssertEq(d.LayoutEditing(), false, "and ends edit mode")
        e := ThemeStore.Load(cfg, "Moontide copy")["layout"]["Settings:Recovery"]
        AssertEq(e[2], Integer(StrSplit(want, ",")[2]), "a yes saved it")
    } finally {
        Theme.Layout := oldLay
        Theme.Use("Moontide")
        UiDashClose(d)
        try DirDelete(dir, true)
    }
}

Test_EditLayout_Resets() {
    dir := UiDashTmp()
    d := ""
    try {
        d := UiLookDash(Config.Load(dir))
        d.SelectPage(UiDashPageIdx("Settings"))
        rec := LyCard(d, "Settings:Recovery"), itv := LyCard(d, "Settings:Intervals"), st := LyCard(d, "Stats:Last 7 days")
        r0 := EdRect(rec), i0 := EdRect(itv), s0 := EdRect(st)
        AssertEq(d.ResetCard("Settings:Recovery"), false, "nothing to reset out of edit mode")
        d.EditLayout(true)
        d.DragCard("Settings:Recovery", 16, 0)
        d.DragCard("Settings:Intervals", 16, 0)
        d.DragCard("Stats:Last 7 days", 0, -16)
        AssertEq(d.LayoutEntries().Count, 3, "three entries")
        AssertTrue(d.ResetCard("Settings:Recovery"), "reset card")
        AssertEq(EdEntry(d, "Settings:Recovery"), "", "Recovery's entry removed")
        AssertTrue(EdEntry(d, "Settings:Intervals") != "" && EdEntry(d, "Stats:Last 7 days") != "", "the others kept")
        AssertEq(EdRect(rec), r0, "Recovery back at its built place")
        d.ToggleCard("Settings:Recovery")
        AssertTrue(d.ResetPage("Settings"), "reset page")
        AssertEq(EdEntry(d, "Settings:Recovery") EdEntry(d, "Settings:Intervals"), "", "no Settings entry left")
        AssertTrue(EdEntry(d, "Stats:Last 7 days") != "", "Stats kept")
        AssertEq(EdRect(rec) "|" EdRect(itv), r0 "|" i0, "Settings cards back")
        AssertTrue(rec.frame.Visible, "the hidden card is shown again")
        AssertTrue(d.ResetLayout(), "reset all")
        AssertEq(d.LayoutEntries().Count, 0, "no entry left")
        AssertEq(EdRect(st), s0, "Stats card back")
        ; Look's Reset all button while editing resets the cards being edited
        d.DragCard("Settings:Recovery", 16, 0)
        AssertTrue(d.LookResetLayout(), "Look > Reset all")
        AssertEq(d.LayoutEntries().Count, 0, "the edited layout is empty")
        AssertEq(EdRect(rec), r0, "the card is back")
        ; every page in edit mode: its own handles, and no card overlaps at the start
        for i, name in Dashboard.Pages {
            d.SelectPage(i)
            AssertEq(d.Ctrl("layout:note").Text, "", name ": nothing overlaps as built")
            for card in d.Cards(name)
                AssertTrue(IsObject(d.Ctrl("layout:handle:" card.id)), name ": a handle for " card.id)
            AssertEq(d.Ctrl("layout:handle:Settings:Recovery") = "", name != "Settings", name ": no handle of another page")
        }
        ; Destroy while editing (and dragging) ends edit mode cleanly
        d.SelectPage(UiDashPageIdx("Settings"))
        d._DragBegin("move", "Settings:Recovery", 0, 0)
        ov := d._edGui.Hwnd
        d.Destroy()
        AssertTrue(!d.LayoutEditing() && !d.Dragging(), "Destroy ends edit mode and the drag")
        AssertEq(Dashboard._edActive, "", "nothing points at the old window")
        AssertEq(DllCall("IsWindow", "Ptr", ov), 0, "the overlay is gone")
        AssertEq(d.Ctrl("layout:done"), "", "no edit ids left")
        d := ""
    } finally {
        UiDashClose(d)
        try DirDelete(dir, true)
    }
}

; Drag and resize back and forth at UI size 115 and 130: the controls end at
; the same pixels (no rounding drift), the card does not grow.
Test_EditLayout_NoDriftAtUiSize() {
    oldSc := Theme.Scale, oldWa := Theme.WorkAreaFn
    try {
        Theme.WorkAreaFn := () => {w: 4000, h: 3000}
        for sc in [115, 130] {
            dir := UiDashTmp()
            d := ""
            try {
                Theme.Scale := sc
                d := UiLookDash(Config.Load(dir))
                AssertEq(Theme.Scale, sc, "built at " sc " %")
                d.SelectPage(UiDashPageIdx("Settings"))
                card := LyCard(d, "Settings:Recovery")
                real0 := EdReal(card), r0 := EdRect(card)
                d.EditLayout(true)
                Loop 12 {
                    d.DragCard("Settings:Recovery", 24, -40)
                    d.ResizeCard("Settings:Recovery", 16, 8)
                    d.DragCard("Settings:Recovery", -24, 40)
                    d.ResizeCard("Settings:Recovery", -16, -8)
                }
                AssertEq(EdRect(card), r0, sc " %: back at the same place and size")
                AssertTrue(EdSame(EdReal(card), real0), sc " %: every control on the same pixels")
                d.DragCard("Settings:Recovery", 24, -40)
                d.ResetCard("Settings:Recovery")
                AssertTrue(EdSame(EdReal(card), real0), sc " %: reset gives the built pixels")
                d.LayoutCancel()
            } finally {
                Anim.Reset()
                UiDashClose(d)
                try DirDelete(dir, true)
            }
        }
    } finally {
        Theme.Scale := oldSc, Theme.WorkAreaFn := oldWa
    }
}

; ---- a destroyed dashboard is freed ---------------------------------------

class UiFreedFlag {
    __New(arr) => this.arr := arr
    __Delete() => this.arr[1] += 1
}

; Build + Destroy leaves nothing pointing at the Dashboard (hooks made with
; `this`, bound timer functions, pages' load / save, the search keys' map):
; AutoHotkey frees it, which a flag object stored on it reports. The Look
; page's edit-layout and search flash paths are opened first.
Test_Dashboard_DestroyFreesIt() {
    dir := UiDashTmp()
    freed := [0]
    d := "", d2 := ""
    try {
        cfg := Config.Load(dir)
        d := Dashboard(cfg)
        d2 := Dashboard(cfg)
        h := d.Hwnd, h2 := d2.Hwnd
        AssertTrue(Dashboard._searchBy.Has(h) && Dashboard._searchBy.Has(h2), "both windows are in the search keys' map")
        d._freedFlag := UiFreedFlag(freed)
        d2._freedFlag := UiFreedFlag(freed)
        d.SelectPage(Dashboard.PageIndex("Look"))
        d.EditLayout(true)
        d.DragCard("Settings:Recovery", 8, 0)
        d.LayoutCancel()
        d.SearchFor("dry run")
        d.SearchGo(1)
        UiDashClose(d), d := ""
        AssertTrue(!Dashboard._searchBy.Has(h), "a destroyed window leaves the map")
        AssertTrue(Dashboard._searchBy.Has(h2), "the other stays")
        AssertEq(freed[1], 1, "the destroyed dashboard was freed")
        UiDashClose(d2), d2 := ""
        AssertEq(freed[1], 2, "the second one too")
    } finally {
        UiDashClose(d)
        UiDashClose(d2)
        try DirDelete(dir, true)
    }
}

; Editing a built-in theme while the layout is edited: the change is refused
; with the "finish the layout edit" note and nothing asks "Make a copy?".
Test_EditLayout_PresetChangeNeverAsks() {
    dir := UiDashTmp()
    d := ""
    try {
        d := UiLookDash(Config.Load(dir))
        asked := [0]
        d._lookAsk := (*) => (asked[1]++, true)
        d.SelectPage(Dashboard.PageIndex("Look"))
        d.LookSelect("Moontide", true)
        d.EditLayout(true)
        AssertEq(d.LookSet("Accent", "ff00aa"), false, "refused")
        AssertEq(asked[1], 0, "no Make a copy? question")
        AssertTrue(InStr(d.Ctrl("look:note").Text, I18n.T("Finish or cancel the layout edit first.")), "the note says why: " d.Ctrl("look:note").Text)
        AssertEq(ThemeStore.Exists(d.cfg, "Moontide copy"), false, "no copy made")
        d.LayoutCancel()
    } finally {
        UiDashClose(d)
        try DirDelete(dir, true)
    }
}

; Look > Export of a theme whose picture is too big to share: the Look page
; says the picture was left out.
Test_Look_ExportBigPictureNote() {
    dir := UiDashTmp()
    d := ""
    try {
        cfg := Config.Load(dir)
        t := ThemeStore.Default()
        t["name"] := "Huge", t["preset"] := false
        t["picture"]["file"] := "Huge.png"
        AssertEq(ThemeStore.Save(cfg, t), true, "saved")
        f := FileOpen(ThemeStore.Dir(cfg) "\Huge.png", "w")
        f.Length := ThemeStore.MaxPicture + 1
        f.Close()
        d := UiLookDash(cfg)
        d.SelectPage(Dashboard.PageIndex("Look"))
        AssertTrue(d.LookSelect("Huge", true), "picked")
        AssertTrue(d.LookExport() != "", "exported")
        AssertTrue(InStr(d.Ctrl("look:note").Text, I18n.T("The picture is too big to share, so the theme was exported without it.")), "the note says so: " d.Ctrl("look:note").Text)
    } finally {
        UiDashClose(d)
        try DirDelete(dir, true)
    }
}

; The import preview closes with Theme.Forget given the window itself (a
; plain {Hwnd} made Forget's control walk throw): no _src / _roles / _help /
; _act entry of its controls is left behind.
Test_Look_ImportPreviewForgotten() {
    dir := UiDashTmp()
    d := ""
    try {
        cfg := Config.Load(dir)
        d := UiLookDash(cfg)
        path := ThemeStore.Export(cfg, "Galaxy")
        pv := d._ImportPreview(ThemeStore.ReadFile(path))
        hw := []
        for c in pv.gui
            hw.Push(c.Hwnd)
        left := (hw) => UiThemeEntries(hw)
        AssertTrue(left(hw) > 0, "the preview's labels are known to Theme")
        d._ImportClose(pv.gui)
        AssertEq(left(hw), 0, "nothing left after the preview closed")
        Theme.Forget({Hwnd: 0})                 ; never throws
    } finally {
        UiDashClose(d)
        try DirDelete(dir, true)
    }
}

; entries of these hwnds in Theme's per-control maps
UiThemeEntries(hw) {
    n := 0
    for h in hw
        for m in [Theme._src, Theme._roles, Theme._help, Theme._act, Theme._trans, Theme._frames, Theme._panels]
            n += m.Has(h) ? 1 : 0
    return n
}

; Top sidebar + edit layout: Reset page, Cancel and Done never cover the
; search box (same row, y 118) and stay inside the window.
Test_EditLayout_TopHeaderClearOfSearch() {
    ovR := (a, b) => !(a.x + a.w <= b.x || b.x + b.w <= a.x || a.y + a.h <= b.y || b.y + b.h <= a.y)
    SbEach((side, d) => (
        d._lookAsk := (*) => true,
        d.SelectPage(Dashboard.PageIndex("Settings")),
        d.EditLayout(true),
        UiEdHeaderCheck(side, d, ovR),
        d.LayoutCancel()
    ), ["top", "left"])
}

UiEdHeaderCheck(side, d, ovR) {
    box := UiDashPos(d.Ctrl("search:box"))
    for id in ["layout:resetPage", "layout:cancel", "layout:done"] {
        p := UiDashPos(d.Ctrl(id))
        AssertTrue(!ovR(p, box), side ": " id " at " p.x "," p.y "," p.w " covers the search box at " box.x "," box.y "," box.w)
        AssertTrue(p.x >= 0 && p.x + p.w <= Dashboard.W, side ": " id " inside the window")
    }
}
