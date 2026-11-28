#Requires AutoHotkey v2.0
; Bug hunt 2026-11-27, plugins and dashboard: a plugin is told when it stops
; (OnOff), Settings shows for a plugin that draws its own page, the
; Crafting page shows / saves the potion list the task buys, a data json that does not parse is never replaced by
; the defaults, and Dev tools' dim settings save.
; Helpers from test_plugins.ahk (PlTmp, PlPut, PlHeader, PlFakeCfg, PlHost,
; PlCheckFake, PlPagePlugin) and test_ui_dash.ahk (UiDashTmp, UiDashClose,
; UiDashPotions, UiDashRow).
#Include ..\lib\App.ahk

; ---- plugins ----------------------------------------------------------------

; a loaded plugin that counts the OnOff calls it gets
class PlFixOffPlugin extends MoontidePlugin {
    static Offs := 0
    OnOff() => PlFixOffPlugin.Offs++
}

; switched off on the Plugins tab, stopped for errors or replaced by a new
; file: its hooks stop, and it is told once (OnOff) so its own background
; work (a reader process, timers) stops too
Test_PlFix_HostTellsAPluginWhenItStops() {
    root := PlTmp()
    PlCheckFake.root := root
    try {
        PlPut(Plugins.Dir(root) "\quiet.ahk", PlHeader("quiet", "PlFixOffPlugin"))
        cfg := PlFakeCfg()
        cfg.Set("Plugins.quiet", 1)
        opts := {resolve: (n) => (n = "PlFixOffPlugin" ? PlFixOffPlugin : "")}
        PlHost(root, cfg, [], opts).BootExternal()       ; checked + included
        h := PlHost(root, cfg, [], opts)
        h.Boot(), h.BootExternal()
        AssertTrue(h.IsOn("quiet"), "loaded and on")
        PlFixOffPlugin.Offs := 0
        h.SetOn("quiet", 0)
        AssertEq(PlFixOffPlugin.Offs, 1, "switched off on the Plugins tab: told at once")
        h.SetOn("quiet", 0)
        AssertEq(PlFixOffPlugin.Offs, 1, "already off: not told again")
        h.SetOn("quiet", 1)
        AssertTrue(h.IsOn("quiet"), "on again")
        AssertEq(PlFixOffPlugin.Offs, 1, "switched on: no OnOff")
        Loop Plugins.MaxErrors
            h.Failed(h.Find("quiet"), "OnTick", Error("broke"))
        AssertTrue(!h.IsOn("quiet"), "stopped for errors")
        AssertEq(PlFixOffPlugin.Offs, 2, "stopped for errors: told")
        h.SetOn("quiet", 1)
        AssertTrue(h.IsOn("quiet"), "one more chance")
        PlPut(Plugins.Dir(root) "\quiet.ahk", PlHeader("quiet", "PlFixOffPlugin") "; one more line`n")
        h.Rescan()
        AssertTrue(!h.IsOn("quiet"), "a changed file waits for a restart")
        AssertEq(PlFixOffPlugin.Offs, 3, "the copy that was running is told it stops")
    } finally DirDelete(root, true)
}

; Plugins tab: a plugin that draws its own page (BuildPage) and has no
; "; setting:" lines still gets the Settings button (it was hidden: the page
; could not be opened from anywhere)
Test_PlFix_SettingsShowsForAPluginWithItsOwnPage() {
    dir := PlTmp()
    d := ""
    try {
        cfg := Config.Load(dir)
        host := PluginHost({cfg: cfg, root: dir, builtins: App.BuiltinPlugins()})
        host.Boot()
        e := Plugins._Blank("pagey.ahk")
        e["id"] := "pagey", e["name"] := "Pagey", e["builtin"] := false, e["ok"] := true
        host.Entries.Push(e)
        o := PlPagePlugin()
        o.api := PluginApi(host, e)
        host._obj["pagey"] := o
        d := Dashboard(cfg, Map("plugins", () => host))
        AssertEq(e["settings"].Length, 0, "no setting lines")
        d.SelectPage(Dashboard.PageIndex("Plugins"))
        lv := d.Ctrl("pluginList")
        row := UiDashRow(lv, "Pagey")
        AssertTrue(row > 0, "listed")
        lv.Modify(row, "Select Focus")
        d._PluginShow()
        AssertTrue(d.Ctrl("pluginSettings").Visible, "Settings shows for a plugin that draws its own page")
        d._PluginSettingsBtn()
        AssertEq(d.ActivePage, "Plugin page", "and opens it")
        ; a file plugin with neither setting lines nor a page: still no button
        e2 := Plugins._Blank("plain.ahk")
        e2["id"] := "plain", e2["name"] := "Plain", e2["builtin"] := false, e2["ok"] := true
        host.Entries.Push(e2)
        d.SelectPage(Dashboard.PageIndex("Plugins"))
        row := UiDashRow(lv, "Plain")
        lv.Modify(row, "Select Focus")
        d._PluginShow()
        AssertTrue(!d.Ctrl("pluginSettings").Visible, "nothing to set: no Settings")
    } finally {
        try IsObject(d) && d.Destroy()
        try DirDelete(dir, true)
    }
}
; ---- dashboard ----------------------------------------------------------------

; Crafting: an older settings.ini with no potion list buys the default
; (Calibrate.DefaultPotions): the page shows that row ticked, not none
Test_PlFix_CraftPageShowsTheDefaultPotion() {
    dir := UiDashTmp()
    d := ""
    try {
        f := FileOpen(dir "\settings.ini", "w", "UTF-8-RAW")
        f.Write("[Craft]`r`nenabled=1`r`n")
        f.Close()
        cfg := Config.Load(dir)
        AssertEq(cfg.Get("Craft.potions", "none"), "none", "an older settings.ini: no potion list")
        d := Dashboard(cfg, Map())
        AssertEq(d.Ctrl("craft:" Calibrate.DefaultPotions).Value, 1, "the page ticks the potion the task buys")
    } finally {
        UiDashClose(d)
        try DirDelete(dir, true)
    }
}

; Crafting: every Fisher shop row unticked with Fish shop on is refused (an
; empty list still bought the default potion); with Fish shop off it saves
Test_PlFix_CraftNoPotionTickedIsRefusedWhileShopOn() {
    dir := UiDashTmp()
    d := ""
    try {
        cfg := Config.Load(dir)
        d := Dashboard(cfg, Map())
        for n in GameLists.Shop
            if IsObject(d.Ctrl("craft:" n))
                d.Ctrl("craft:" n).Value := 0
        d.Ctrl("Craft.enabled").Value := 1
        AssertEq(d.SavePage("Craft"), false, "nothing ticked with Fish shop on: not saved")
        AssertEq(Config.Load(dir).Get("Craft.potions", ""), Calibrate.DefaultPotions, "the saved list is kept")
        AssertTrue(InStr(d._PageByName("Craft").status.Text, "Fish shop"), "the page says why: " d._PageByName("Craft").status.Text)
        d.Ctrl("Craft.enabled").Value := 0
        AssertTrue(d.SavePage("Craft"), "Fish shop off: saved")
        c2 := Config.Load(dir)
        AssertEq(c2.Get("Craft.enabled", 1), 0, "Fish shop off saved")
        d.Ctrl("craft:" GameLists.Shop[2]).Value := 1
        d.Ctrl("Craft.enabled").Value := 1
        AssertTrue(d.SavePage("Craft"), "a potion ticked: saved")
        AssertEq(Config.Load(dir).Get("Craft.potions", ""), GameLists.Shop[2], "the ticked potion")
    } finally {
        UiDashClose(d)
        try DirDelete(dir, true)
    }
}

; Merchants, Biomes, Potions and Quests: a data json that does not parse
; loads as the built-in defaults; Save (and Unlock / Re-lock, which save at
; once) never write those over the player's file
Test_PlFix_BadDataJsonIsNeverReplaced() {
    dir := UiDashTmp()
    d := ""
    try {
        bad := '{ "Mari": [ {"name": "Void Coin"} ,, ] }'
        pages := Map("Merchants", "merchants", "Biomes & Potions", "biomes", "Potions", "potions", "Quests", "quests")
        for page, n in pages {
            f := FileOpen(dir "\data\" n ".json", "w", "UTF-8-RAW")
            f.Write(bad)
            f.Close()
        }
        cfg := Config.Load(dir)
        d := Dashboard(cfg, Map())
        for page, n in pages {
            AssertEq(cfg.DataStatus(n), "bad", n " does not parse")
            AssertEq(d.SavePage(page), false, page ": not saved")
            AssertEq(FileRead(dir "\data\" n ".json", "UTF-8"), bad, n ".json kept")
            AssertTrue(InStr(d._PageByName(page).status.Text, n ".json does not parse"), page " says why: " d._PageByName(page).status.Text)
        }
        locked := UiDashPotions(cfg).locked
        AssertTrue(locked != "", "the defaults have a locked potion")
        AssertTrue(d.SelectPotion(locked), "select it")
        asked := [0]
        d._confirm := (title, text) => (asked[1]++, true)
        AssertEq(d.UnlockSelected(), false, "Unlock refused")
        AssertEq(asked[1], 0, "not even asked")
        AssertEq(FileRead(dir "\data\potions.json", "UTF-8"), bad, "potions.json kept by Unlock")
        d.RelockSelected()
        AssertEq(FileRead(dir "\data\potions.json", "UTF-8"), bad, "potions.json kept by Re-lock")
        ; a file that parses saves as before
        FileDelete(dir "\data\merchants.json")
        c2 := Config.Load(dir)
        d2 := Dashboard(c2, Map())
        try AssertTrue(d2.SavePage("Merchants"), "a missing merchants.json: saved")
        finally UiDashClose(d2)
    } finally {
        UiDashClose(d)
        try DirDelete(dir, true)
    }
}

; Dev tools (dev copy): "Dim my screens" and "How dark" have a Save bar and
; reach settings.ini; How dark is held to what ScreenDim uses (5..98)
Test_PlFix_DevToolsDimSaves() {
    dir := UiDashTmp()
    d := ""
    try {
        FileAppend("", dir "\" Updater.DevMarker)
        cfg := Config.Load(dir)
        d := Dashboard(cfg, Map())
        page := d._PageByName("Dev tools")
        AssertTrue(IsObject(page.status), "Dev tools has a Save bar")
        d.Ctrl("devDim").Value := 1
        d.Ctrl("devDimPct").Value := "99"
        AssertTrue(d.SavePage("Dev tools"), "saved")
        c2 := Config.Load(dir)
        AssertEq(c2.Get("Dev.dim", 0), 1, "dim saved to settings.ini")
        AssertEq(c2.Get("Dev.dimPct", 0), 98, "How dark held to 98")
        AssertEq(d._PageDirty(page), false, "no unsaved dot after Save")
    } finally {
        UiDashClose(d)
        try DirDelete(dir, true)
    }
}

; dashboard-1, the root: an explicit empty list (every row unticked, saved
; before the page refused it) buys nothing; only a missing key means the
; default (Calibrate.Potions turned "" into Lucky Potion)
Test_PlFix_EmptyPotionListBuysNothing() {
    dir := UiDashTmp()
    oldCfg := Calibrate._cfg
    try {
        f := FileOpen(dir "\settings.ini", "w", "UTF-8-RAW")
        f.Write("[Craft]`r`nenabled=1`r`npotions=`r`n")
        f.Close()
        Calibrate._cfg := Config.Load(dir)
        AssertEq(Calibrate.Potions().Length, 0, "Craft.potions= (nothing ticked): no potion")
        f := FileOpen(dir "\settings.ini", "w", "UTF-8-RAW")
        f.Write("[Craft]`r`nenabled=1`r`n")
        f.Close()
        Calibrate._cfg := Config.Load(dir)
        p := Calibrate.Potions()
        AssertEq(p.Length = 1 ? p[1] : p.Length, Calibrate.DefaultPotions, "no key (an older settings.ini): the default")
    } finally {
        Calibrate._cfg := oldCfg
        try DirDelete(dir, true)
    }
}
