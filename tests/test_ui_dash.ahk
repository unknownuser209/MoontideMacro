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
        AssertEq(d.Ctrl("calStatus").Text, "2 of " n " steps recorded", "point and rect steps counted as recorded")
        lv := d.Ctrl("calibrate")
        rows := Map()
        Loop lv.GetCount()
            rows[lv.GetText(A_Index, 1)] := lv.GetText(A_Index, 2)
        AssertTrue(InStr(rows["inv_amount_box"], "recorded"), "inv_amount_box shows recorded")
        AssertTrue(!rows.Has("inv_amount_one"), "no '1' signature step any more")
        AssertEq(rows["inv_items_tab"], "missing", "unrecorded step still missing")
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
        if (name = "obby" || name = "memory_match")
            continue                    ; the user records these; no shipped default
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

Test_Hubs_EveryPageReachable() {
    AssertEq(Dashboard.Hubs.Length, 6, "six hubs")
    names := []
    for h in Dashboard.Hubs
        names.Push(h.name)
    AssertEq(UiLogic.ArrayToCsv(names), "Home,Automate,Alerts,Setup,Log,About", "hub names in order")
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
    for p in ["Limbo", "Clips", "Dev tools"]
        AssertTrue(UiDashPageIdx(p) > 0, "new page " p)
    AssertEq(Dashboard.Pages[Dashboard.LogPage], "Log", "LogPage is the Log page")
    AssertEq(Dashboard.Hubs[2].pages[7], "Limbo", "Limbo is the last Automate tab")
    AssertEq(Dashboard.Hubs[2].pages[6], "Obby & Memory", "Obby & Memory follows Biome items")
    AssertEq(Dashboard.Hubs[2].pages[5], "Biome items", "Biome items before Obby & Memory")
    AssertEq(Dashboard.Hubs[3].pages[3], "Clips", "Clips is an Alerts tab")
    AssertEq(Dashboard.Hubs[4].pages[4], "Dev tools", "Dev tools is the last Setup tab")
}

Test_Hubs_TabLabels() {
    AssertEq(Dashboard.TabLabel("Craft"), "Crafting", "Craft")
    AssertEq(Dashboard.TabLabel("Webhooks"), "Discord", "Webhooks")
    AssertEq(Dashboard.TabLabel("Tools"), "Routes", "Tools")
    AssertEq(Dashboard.TabLabel("Biomes & Potions"), "Biomes", "Biomes & Potions")
    AssertEq(Dashboard.TabLabel("Quests"), "Quests", "Quests")
    AssertEq(Dashboard.TabLabel("Dev tools"), "Dev tools", "Dev tools")
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
        AssertEq(d.ActivePage, "Fishing", "Automate opens on its first tab")
        AssertTrue(d.Ctrl("General.sellEvery").Visible, "Fishing controls shown")
        AssertEq(d.Ctrl("merch.name").Visible, false, "Merchants controls hidden")
        AssertTrue(d.Ctrl("tab:Merchants").Visible && d.Ctrl("tab:Limbo").Visible, "Automate tabs shown")
        AssertEq(d.Ctrl("tab:Calibrate").Visible, false, "Setup tabs hidden")
        d.SelectPage(UiDashPageIdx("Merchants"))
        AssertEq(d.ActivePage, "Merchants", "Merchants selected")
        AssertEq(d.ActiveHub, 2, "still Automate")
        AssertTrue(d.Ctrl("merch.name").Visible, "Merchants controls shown")
        AssertEq(d.Ctrl("General.sellEvery").Visible, false, "Fishing controls hidden")
        u := UiDashPos(d.Ctrl("tabUnderline")), t := UiDashPos(d.Ctrl("tab:Merchants"))
        AssertTrue(d.Ctrl("tabUnderline").Visible, "underline shown")
        AssertEq(u.x "," u.w, t.x "," t.w, "underline under the Merchants tab")
        AssertEq(u.y "," u.h, "130,2", "underline y 130 h 2")
        AssertEq(t.y "," t.h, "104,26", "tab strip y 104 h 26")
        d.SelectHub(1)
        AssertEq(d.ActivePage, "Run", "Home")
        AssertEq(d.Ctrl("tab:Merchants").Visible, false, "Automate tabs hidden on Home")
        d.SelectHub(2)
        AssertEq(d.ActivePage, "Merchants", "Automate reopens on its last tab")
        ; SelectPage of a page in another hub moves the hub too
        d.SelectPage(UiDashPageIdx("Clips"))
        AssertEq(d.ActiveHub, 3, "Clips -> Alerts hub")
        AssertTrue(d.Ctrl("Medal.clipHotkey").Visible, "Clips controls shown")
        d.SelectPage(Dashboard.LogPage)
        AssertEq(d.ActiveHub, 5, "Log hub")
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
                if (Theme.HelpText(c) = "")
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
        d.SelectPage(UiDashPageIdx("Quests"))
        q := UiDashPos(d.Ctrl("tab:Quests"))
        AssertTrue(q.x > f.x, "Quests tab is right of Fishing")
        xs := []
        for t in [0, 90, 180] {
            UiDashTickTo(r, t)
            xs.Push(UiDashPos(u).x)
        }
        AssertEq(xs[1], f.x, "t 0: still at Fishing")
        AssertTrue(xs[2] > xs[1] && xs[2] < q.x, "t 90: on the way (" xs[2] ")")
        AssertTrue(xs[3] >= xs[2], "monotonic")
        p := UiDashPos(u)
        AssertEq(p.x "," p.w "," p.y "," p.h, q.x "," q.w ",130,2", "t 180: exactly under Quests")
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
        AssertEq(d._moonFrame, 2, "moon frame = Floor(phase * 8) (1000 / 3200)")
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

Test_Dash_LookSwitches() {
    dir := UiDashTmp()
    d := ""
    Anim.Reset()
    try {
        cfg := Config.Load(dir)
        d := Dashboard(cfg)
        a := d.Ctrl("UI.animations")
        AssertTrue(IsObject(a), "the switch exists")
        AssertEq(d.PageOf(a), "Settings", "Animations on Settings")
        AssertTrue(a is ThemeCheck && a._style = "pill", "Animations is a pill")
        AssertTrue(IsObject(d.Ctrl("panel:Settings:Look")), "Look panel")
        AssertEq(a.Value, 1, "animations on by default")
        AssertEq(Anim.enabledFn.Call(), true, "enabledFn follows the setting")
        a.Value := 0
        AssertTrue(d.SavePage("Settings"), "saved")
        AssertEq(String(cfg.Get("UI.animations", 1)), "0", "UI.animations saved 0")
        AssertEq(Anim.enabledFn.Call(), false, "live: animations off without a restart")
        AssertEq(String(Config.Load(dir).Get("UI.animations", 1)), "0", "written to settings.ini")
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
            , UiDashPos(d._pill), {x: 764, y: 16, w: 256, h: 28}, {x: 0, y: 74, w: 176, h: 240}, UiDashPos(d._chip)]
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

; Destroy frees the moon frames, forgets the window for the wake hooks and
; stops the Dashboard's animations.
Test_Dash_DestroyCleansUp() {
    dir := UiDashTmp()
    d := ""
    Anim.Reset()
    try {
        d := Dashboard(Config.Load(dir))
        AssertEq(d._moonFrames.Length, 8, "8 moon frames decoded once")
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
        AssertEq(d._moonFreed, 8, "all 8 bitmaps deleted")
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
        AssertEq(d.PageOf(d.Ctrl("Minions.normal")), "Obby & Memory", "NORMAL hunt switch on the page")
        AssertEq(d.Ctrl("Minions.normal").Value, 0, "NORMAL not hunted by default")
        AssertEq(d.Ctrl("Obby.intervalMin").Value, "10", "interval default shown")
        AssertTrue(InStr(d.Ctrl("obbyBlessingNote").Text, "obby_blessing"), "blessing note names the calibration step")
        AssertTrue(InStr(d.Ctrl("memoryNote").Text, "next try: "), "next try note")
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
