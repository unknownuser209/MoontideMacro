#Requires AutoHotkey v2.0
; Tests for the plugin system (lib\Plugins.ahk), the built-in hunting plugin
; (lib\plugins\hunting\Hunting.ahk, the Limited tab before 2026-11-26), the
; [Limited] -> [Hunting] settings move and the Plugins tab.
#Include ..\lib\App.ahk

PlTmp() {
    d := A_Temp "\vesper_plugins_" A_TickCount "_" Random(1000, 9999)
    DirCreate(d)
    return d
}
PlPut(path, text) {
    SplitPath(path, , &dir)
    if !DirExist(dir)
        DirCreate(dir)
    f := FileOpen(path, "w", "UTF-8")
    f.Write(text)
    f.Close()
}
PlHeader(id, cls, extra := "") => "; @moontide-plugin`n; id: " id "`n; name: " StrTitle(id) "`n; version: 1.0`n; api: 1`n; class: " cls "`n" extra
PlFind(entries, file) {
    for e in entries
        if (e["file"] = file)
            return e
    return ""
}

class PlFakeCfg {
    __New() {
        this.vals := Map()
        this.vals.CaseSense := "Off"
        this.saves := 0
    }
    Get(path, default := "") => this.vals.Has(path) ? this.vals[path] : default
    Set(path, v) => this.vals[path] := v
    Save() => this.saves++
}

; a plugin class the tests load (it is "in" _enabled.ahk)
class PlTestPlugin extends MoontidePlugin {
    static Calls := []
    OnLoad() => PlTestPlugin.Calls.Push("load")
    OnStart() => PlTestPlugin.Calls.Push("start:" this.api.Get("speed"))
    OnBiome(b, prev) => PlTestPlugin.Calls.Push("biome:" b)
    OnTick() {
        throw Error("tick broke")
    }
    Task() => {priority: 1, CanRun: (self, st) => true, Run: (self, ctx) => 7}
}

; ---- manifest ----------------------------------------------------------------

Test_Plugins_ManifestReads() {
    m := Plugins.ReadManifest("#Requires AutoHotkey v2.0`n" PlHeader("my_plugin", "MyPlugin"
        , "; author: someone`n; description: Does a thing.`n; setting: speed | int | 30 | Seconds between checks`n; setting: on | bool | 1 | Turn it on`n; setting: key | secret |  | API key`n")
        . "class MyPlugin extends MoontidePlugin {`n}`n")
    AssertEq(m["id"], "my_plugin", "id")
    AssertEq(m["class"], "MyPlugin", "class")
    AssertEq(m["api"], 1, "api")
    AssertEq(m["author"], "someone", "author")
    AssertEq(m["settings"].Length, 3, "three settings")
    AssertEq(m["settings"][1]["type"], "int", "int setting")
    AssertEq(m["settings"][1]["label"], "Seconds between checks", "its label")
    AssertEq(m["settings"][2]["def"], "1", "bool default")
    ; the header ends at the first line that is not a comment
    m := Plugins.ReadManifest(PlHeader("abc", "Abc") "x := 1`n; setting: late | int | 1 | Late`n")
    AssertEq(m["settings"].Length, 0, "a setting after the code is not read")
}

; the example that ships in plugins\ and the README's example both read
Test_Plugins_ShippedExamplesRead() {
    root := RegExReplace(A_LineFile, "\\tests\\[^\\]+$")
    m := Plugins.ReadManifest(FileRead(root "\plugins\example_plugin.ahk.txt", "UTF-8"))
    AssertEq(m["id"], "hello", "example id")
    AssertEq(m["settings"].Length, 2, "example settings")
    rd := FileRead(root "\README.md", "UTF-8")
    AssertTrue(RegExMatch(rd, "s)``````ahk\R(; @moontide-plugin.*?)``````", &mm), "README has the example")
    m := Plugins.ReadManifest(mm[1])
    AssertEq(m["id"], "hello", "README example id (inline comments allowed)")
    AssertEq(m["class"], "HelloPlugin", "README example class")
    AssertTrue(InStr(mm[1], "class HelloPlugin extends MoontidePlugin"), "README example has its class")
}

Test_Plugins_ManifestRefusesWithReasons() {
    bad := Map(
        "no header", ["; just a script`nx := 1`n", "no Moontide plugin header"],
        "no class", ["; @moontide-plugin`n; id: abc`n; name: A`n; version: 1`n; api: 1`n", "no class:"],
        "bad id", [PlHeader("Bad-Id", "A"), "id `"Bad-Id`""],
        "new api", [StrReplace(PlHeader("abc", "A"), "api: 1", "api: 99"), "needs plugin API 99"],
        "bad version", [StrReplace(PlHeader("abc", "A"), "version: 1.0", "version: one"), "version"],
        "bad type", [PlHeader("abc", "A", "; setting: x | colour | 1 | X`n"), "type `"colour`""],
        "bad int", [PlHeader("abc", "A", "; setting: x | int | many | X`n"), "whole number"],
        "twice", [PlHeader("abc", "A", "; setting: x | int | 1 | X`n; setting: x | int | 2 | Y`n"), "twice"])
    for name, c in bad {
        why := ""
        try Plugins.ReadManifest(c[1])
        catch Any as e
            why := e.Message
        AssertTrue(why != "" && InStr(why, c[2]), name ": " why)
    }
}

; ---- scan --------------------------------------------------------------------

Test_Plugins_ScanListsGoodAndBroken() {
    root := PlTmp()
    try {
        dir := Plugins.Dir(root)
        PlPut(dir "\good.ahk", PlHeader("good", "GoodPlugin") "class GoodPlugin extends MoontidePlugin {`n}`n")
        PlPut(dir "\folder_one\plugin.ahk", PlHeader("folder_one", "FolderOne") "#Include %A_LineFile%\..\helper.ahk`n")
        PlPut(dir "\folder_one\helper.ahk", "class FolderOne extends MoontidePlugin {`n}`n")
        PlPut(dir "\broken.ahk", "x := (`n")
        PlPut(dir "\virus.exe", "MZ")
        PlPut(dir "\README.txt", "how to")
        PlPut(dir "\twin.ahk", PlHeader("good", "Twin"))
        PlPut(dir "\mine.ahk", PlHeader("hunting", "Mine"))
        PlPut(dir "\empty_folder\notes.md", "x")
        PlPut(dir "\.loaded\_enabled.ahk", "; made")
        es := Plugins.Scan(dir, ["mover"])
        AssertEq(es.Length, 7, "README and .loaded get no row")
        g := PlFind(es, "good.ahk")
        AssertTrue(g["ok"] && g["id"] = "good" && g["stamp"] != "", "good file ok")
        f := PlFind(es, "folder_one")
        AssertTrue(f["ok"] && f["folder"] && InStr(f["path"], "plugin.ahk"), "folder plugin ok")
        AssertTrue(InStr(PlFind(es, "broken.ahk")["reason"], "no Moontide plugin header"), "broken: why")
        AssertTrue(InStr(PlFind(es, "virus.exe")["reason"], ".ahk files"), "exe: why")
        AssertTrue(InStr(PlFind(es, "twin.ahk")["reason"], "already used"), "same id twice: why")
        AssertTrue(InStr(PlFind(es, "mine.ahk")["reason"], "already used by the macro"), "a macro id: why")
        AssertTrue(InStr(PlFind(es, "empty_folder")["reason"], "no plugin.ahk"), "folder without plugin.ahk: why")
        AssertEq(Plugins.Scan(root "\nope").Length, 0, "no plugins folder: no rows")
    } finally DirDelete(root, true)
}

Test_Plugins_StampChangesWithTheFile() {
    root := PlTmp()
    try {
        dir := Plugins.Dir(root)
        PlPut(dir "\a\plugin.ahk", PlHeader("a_one", "A"))
        e := Plugins.Scan(dir)[1]
        s1 := Plugins.Stamp(e)
        PlPut(dir "\a\more.ahk", "; another file")
        AssertTrue(Plugins.Stamp(e) != s1, "a new file in the folder changes the stamp")
    } finally DirDelete(root, true)
}

Test_Plugins_IncludeAndCheckText() {
    e := Map("id", "good", "file", "good.ahk", "folder", false, "path", "C:\x\plugins\good.ahk")
    f := Map("id", "fold", "file", "fold", "folder", true, "path", "C:\x\plugins\fold\plugin.ahk")
    t := Plugins.IncludeText("C:\x", [e, f])
    AssertTrue(InStr(t, "#Include *i %A_ScriptDir%\plugins\.loaded\good.ahk"), "file copy by A_ScriptDir: " t)
    AssertTrue(InStr(t, "#Include *i %A_ScriptDir%\plugins\.loaded\fold\plugin.ahk"), "folder copy")
    c := Plugins.CheckText("C:\x", [e])
    AssertTrue(InStr(c, Plugins.LibDir "\App.ahk") && InStr(c, "C:\x\plugins\.loaded\good.ahk"), "the checker loads the macro and the copy")
    msg := Plugins.CleanError("C:\x", "C:\x\plugins\.loaded\good.ahk (5) : ==> Missing `")`"`n     Specifically: x", [e])
    AssertTrue(InStr(msg, "good.ahk (5) : Missing") && !InStr(msg, "C:\x"), "error text short: " msg)
}

; ---- host --------------------------------------------------------------------

PlHost(root, cfg, checks, opts := "") {
    deps := {cfg: cfg, root: root, log: (t) => 0, builtins: [], validate: (r, es) => (checks.Push(es.Length), PlCheckFake(es))
        , resolve: (name) => (name = "PlTestPlugin" ? PlTestPlugin : "")}
    if IsObject(opts)
        for k, v in opts.OwnProps()
            deps.%k% := v
    return PluginHost(deps)
}
; the fake checker: a plugin whose file says "BROKEN" fails
PlCheckFake(es) {
    for e in es
        if InStr(FileRead(Plugins.CachePath(PlCheckFake.root, e), "UTF-8"), "BROKEN")
            return {ok: false, text: Plugins.CachePath(PlCheckFake.root, e) " (2) : ==> This line does not contain a recognized action."}
    return {ok: true, text: ""}
}

Test_Plugins_SwitchOnChecksCopiesAndWantsRestart() {
    root := PlTmp()
    PlCheckFake.root := root
    try {
        dir := Plugins.Dir(root)
        PlPut(dir "\fast.ahk", PlHeader("fast", "PlTestPlugin"))
        PlPut(dir "\bad.ahk", PlHeader("bad", "PlTestPlugin") "BROKEN`n")
        cfg := PlFakeCfg(), checks := []
        h := PlHost(root, cfg, checks)
        h.Boot(), h.BootExternal()
        e := h.Find("fast")
        AssertEq(h.Status(e), "Off", "a new plugin is off")
        AssertEq(checks.Length, 0, "nothing checked while off")
        msg := h.SetOn("fast", 1)
        AssertTrue(InStr(msg, "restart"), "on: asks for a restart: " msg)
        AssertEq(h.Status(e), "Restart to load", "status")
        AssertTrue(h.RestartWanted, "restart wanted")
        AssertTrue(FileExist(Plugins.CacheDir(root) "\fast.ahk"), "the checked copy is made")
        AssertTrue(InStr(FileRead(Plugins.CacheDir(root) "\_enabled.ahk", "UTF-8"), "fast.ahk"), "and included")
        AssertTrue(!h.IsOn("fast"), "not running before the restart")
        ; broken: an error row, never included
        msg := h.SetOn("bad", 1)
        b := h.Find("bad")
        AssertTrue(!b["ok"] && InStr(h.Status(b), "Error: error in the code: bad.ahk (2)"), "broken: error status: " h.Status(b))
        AssertTrue(!InStr(FileRead(Plugins.CacheDir(root) "\_enabled.ahk", "UTF-8"), "bad.ahk"), "broken never included")
        ; the next start: fast is loaded (stamps + class), runs its hooks
        PlTestPlugin.Calls := []
        cfg.Set("Plugin.fast.speed", 5)
        h2 := PlHost(root, cfg, checks2 := [])
        h2.Boot(), h2.BootExternal()
        AssertTrue(h2.IsOn("fast"), "loaded after the restart")
        AssertEq(checks2.Length, 1, "only the broken one is checked again (it is still on)")
        AssertEq(h2.Status(h2.Find("fast")), "On", "On")
        AssertTrue(!h2.RestartWanted, "nothing more to load")
        h2.Call("OnStart")
        AssertEq(PlTestPlugin.Calls.Length, 2, "OnLoad then OnStart")
        AssertEq(PlTestPlugin.Calls[2], "start:5", "its setting through the api")
        ; a throwing hook: switched off for the session after MaxErrors
        Loop Plugins.MaxErrors
            h2.Call("OnTick")
        AssertTrue(!h2.IsOn("fast"), "stopped after errors")
        AssertTrue(InStr(h2.Status(h2.Find("fast")), "Stopped: too many errors (last: tick broke"), "why")
        ; switching off needs no restart
        h2.SetOn("fast", 1)
        AssertTrue(h2.IsOn("fast"), "switched on again: one more chance")
        h2.SetOn("fast", 0)
        AssertTrue(!h2.IsOn("fast") && !h2.RestartWanted, "off at once, no restart")
        AssertTrue(!InStr(FileRead(Plugins.CacheDir(root) "\_enabled.ahk", "UTF-8"), "fast.ahk"), "left out of the next start")
    } finally DirDelete(root, true)
}

Test_Plugins_EditedFileIsCheckedAgain() {
    root := PlTmp()
    PlCheckFake.root := root
    try {
        dir := Plugins.Dir(root)
        PlPut(dir "\fast.ahk", PlHeader("fast", "PlTestPlugin"))
        cfg := PlFakeCfg()
        cfg.Set("Plugins.fast", 1)
        h := PlHost(root, cfg, [])
        h.Boot(), h.BootExternal()
        h2 := PlHost(root, cfg, [])
        h2.Boot(), h2.BootExternal()
        AssertTrue(h2.IsOn("fast"), "loaded")
        ; the player breaks the file while the macro runs
        Sleep(1100)
        PlPut(dir "\fast.ahk", PlHeader("fast", "PlTestPlugin") "BROKEN`n")
        h2.Rescan()
        e := h2.Find("fast")
        AssertTrue(InStr(h2.Status(e), "Error"), "the new version's error shows: " h2.Status(e))
        AssertTrue(!h2.IsOn("fast"), "the old copy stops too")
        AssertTrue(!InStr(FileRead(Plugins.CacheDir(root) "\_enabled.ahk", "UTF-8"), "fast.ahk"), "the next start does not load it")
    } finally DirDelete(root, true)
}

Test_Plugins_TaskOnlyWhileOn() {
    root := PlTmp()
    PlCheckFake.root := root
    try {
        PlPut(Plugins.Dir(root) "\fast.ahk", PlHeader("fast", "PlTestPlugin"))
        cfg := PlFakeCfg()
        cfg.Set("Plugins.fast", 1)
        PlHost(root, cfg, []).BootExternal()        ; checked + included
        h := PlHost(root, cfg, [])
        h.Boot(), h.BootExternal()
        ts := h.Tasks()
        AssertEq(ts.Length, 1, "its task")
        t := ts[1]
        AssertEq(t.name, "plugin:fast", "named")
        AssertEq(t.priority, Plugins.ExternalMinPri, "an outside plugin cannot go before recovery")
        AssertTrue(t.CanRun({}), "runs while on")
        AssertEq(t.Run(""), 7, "Run passed through")
        h.SetOn("fast", 0)
        AssertTrue(!t.CanRun({}), "never while off")
    } finally DirDelete(root, true)
}

; the real checker: a separate AutoHotkey /Validate on the macro + the copy
Test_Plugins_RealCheckCatchesBrokenCode() {
    root := PlTmp()
    try {
        good := Map("id", "rc_good", "file", "rc_good.ahk", "folder", false, "path", root "\plugins\rc_good.ahk")
        bad := Map("id", "rc_bad", "file", "rc_bad.ahk", "folder", false, "path", root "\plugins\rc_bad.ahk")
        clash := Map("id", "rc_clash", "file", "rc_clash.ahk", "folder", false, "path", root "\plugins\rc_clash.ahk")
        PlPut(Plugins.CachePath(root, good), "class RcGood extends MoontidePlugin {`n    OnTick() {`n    }`n}`n")
        PlPut(Plugins.CachePath(root, bad), "class RcBad extends MoontidePlugin {`n    OnTick() {`n        x := (`n    }`n}`n")
        PlPut(Plugins.CachePath(root, clash), "class Config {`n}`n")
        r := PluginHost.RunCheck(root, [good])
        AssertTrue(r.ok, "good code passes: " r.text)
        r := PluginHost.RunCheck(root, [bad])
        AssertTrue(!r.ok && InStr(r.text, "rc_bad.ahk"), "broken code fails, the file named: " r.text)
        r := PluginHost.RunCheck(root, [clash])
        AssertTrue(!r.ok, "a class the macro has fails")
        AssertTrue(!FileExist(Plugins.CacheDir(root) "\_check.ahk"), "the checker script is removed")
    } finally DirDelete(root, true)
}

; ---- the built-in hunting plugin and the [Limited] move ------------------------------

Test_Plugins_LimitedKeysMoveToHunting() {
    d := PlTmp()
    try {
        f := FileOpen(d "\settings.ini", "w", "UTF-8-RAW")
        f.Write("[Limited]`r`nbossAlert=0`r`norbAlert=1`r`ncursedRune=1`r`n[Minions]`r`nenabled=1`r`n")
        f.Close()
        cfg := Config.Load(d)
        AssertEq(cfg.Get("Hunting.bossAlert", 1), 0, "boss alert moved")
        AssertEq(cfg.Get("Hunting.orbAlert", 0), 1, "orb alert moved")
        AssertEq(cfg.Get("Hunting.cursedRune", 0), 1, "rune moved")
        AssertEq(cfg.Get("Limited.bossAlert", "gone"), "gone", "old key gone")
        AssertEq(cfg.Get("Minions.enabled", 0), 1, "hunt settings kept")
        cfg.Save()
        t := FileRead(d "\settings.ini", "UTF-8")
        AssertTrue(!InStr(t, "[Limited]") && InStr(t, "[Hunting]"), "the file has [Hunting], no [Limited]")
        ; a value already in [Hunting] wins over an old [Limited] one
        f := FileOpen(d "\settings.ini", "w", "UTF-8-RAW")
        f.Write("[Hunting]`r`norbAlert=0`r`n[Limited]`r`norbAlert=1`r`n")
        f.Close()
        AssertEq(Config.Load(d).Get("Hunting.orbAlert", 9), 0, "the new key kept")
        ; a new install has the plugin on
        d2 := PlTmp()
        c2 := Config.Load(d2)
        AssertEq(c2.Get("Plugins.hunting", 0), 1, "hunting plugin on by default")
        AssertEq(c2.Get("Plugins.mover", "none"), "none", "a file plugin has no default (off until switched on)")
        DirDelete(d2, true)
    } finally DirDelete(d, true)
}

Test_Plugins_HuntingSwitchGatesEverything() {
    cfg := PlFakeCfg()
    cfg.Set("Hunting.bossAlert", 1), cfg.Set("Hunting.orbAlert", 1), cfg.Set("Hunting.cursedRune", 1), cfg.Set("Minions.enabled", 1)
    AssertTrue(HuntingPlugin.BossOn(cfg) && HuntingPlugin.OrbOn(cfg) && HuntingPlugin.RuneOn(cfg) && HuntingPlugin.HuntOn(cfg), "on by default: works as before")
    AssertTrue(HuntingPlugin.ChatWanted(cfg), "the chat is read for it")
    cfg.Set("Plugins.hunting", 0)
    AssertTrue(!HuntingPlugin.BossOn(cfg) && !HuntingPlugin.OrbOn(cfg) && !HuntingPlugin.RuneOn(cfg) && !HuntingPlugin.HuntOn(cfg), "off: nothing")
    AssertTrue(!HuntingPlugin.ChatWanted(cfg), "no chat read for it")
    m := MinionsTask({cfg: cfg})
    AssertEq(m.CanRun(SchedState()), false, "no hunt with the plugin off")
}

Test_Plugins_UpdaterKeepsThePluginsFolder() {
    AssertTrue(Updater.IsProtected("plugins\my_plugin.ahk"), "a plugin file")
    AssertTrue(Updater.IsProtected("plugins/folder/plugin.ahk"), "a plugin folder")
    AssertTrue(Updater.IsProtected("plugins\.loaded\_enabled.ahk"), "the loaded copies")
    AssertTrue(!Updater.IsProtected("lib\Plugins.ahk"), "the plugin system itself updates")
}

Test_Plugins_SecretSettingKeyIsKeptOutOfExports() {
    e := Map("id", "abc", "builtin", false)
    p := PluginHost.SettingPath(e, Map("key", "apiKey", "type", "secret"))
    AssertEq(p, "Plugin.abc.apiKey_secret", "secret path")
    AssertTrue(LogBundle._SecretKey("Plugin.abc", "apiKey_secret"), "a secret to exports and log zips")
    AssertEq(PluginHost.SettingPath(e, Map("key", "speed", "type", "int")), "Plugin.abc.speed", "plain path")
    AssertEq(PluginHost.SettingPath(Map("id", "hunting", "builtin", true, "section", "Hunting"), Map("key", "x", "type", "int")), "Hunting.x", "built-in: own section")
}

; ---- the Plugins tab ---------------------------------------------------------

Test_Plugins_TabListsPluginsAndErrors() {
    dir := PlTmp()
    PlCheckFake.root := dir
    d := ""
    try {
        PlPut(Plugins.Dir(dir) "\nice.ahk", PlHeader("nice", "PlTestPlugin", "; setting: speed | int | 30 | Speed`n; setting: loud | bool | 0 | Loud`n; setting: key | secret |  | Key`n"))
        PlPut(Plugins.Dir(dir) "\broken.ahk", "oops")
        cfg := Config.Load(dir)
        host := PluginHost({cfg: cfg, root: dir, builtins: App.BuiltinPlugins(), validate: (r, es) => PlCheckFake(es), resolve: (n) => PluginHost.Resolve(n)})
        host.Boot(), host.BootExternal()
        d := Dashboard(cfg, Map("plugins", () => host))
        AssertTrue(Dashboard.HubOf("Plugins") != Dashboard.HubOf("Quests"), "Plugins has its own hub")
        AssertEq(Dashboard.Hubs[Dashboard.HubOf("Plugins")].name, "Plugins", "the Plugins hub")
        AssertTrue(!d.TabShown("Hunting") && d.TabShown("Plugins"), "the Limited tab is gone, Plugins is there")
        AssertEq(Dashboard.TabLabel("Hunting"), "Orb & boss hunting", "the hunting page's name")
        d.SelectPage(Dashboard.PageIndex("Plugins"))
        lv := d.Ctrl("pluginList")
        AssertEq(lv.GetCount(), 3, "one built-in + two files")
        AssertEq(lv.GetText(1, 1), "Orb & boss hunting", "built-in first")
        AssertEq(lv.GetText(1, 4), "Is on", "hunting on")
        row := 0
        Loop lv.GetCount()
            if (lv.GetText(A_Index, 1) = "broken.ahk")
                row := A_Index
        AssertTrue(row && InStr(lv.GetText(row, 4), "no Moontide plugin header"), "broken file: an error row")
        ; Settings of the hunting plugin opens the old Limited page
        AssertTrue(d.OpenPluginPage("hunting"), "opened")
        AssertEq(d.ActivePage, "Hunting", "the hunting page")
        AssertEq(d.PageOf(d.Ctrl("Hunting.bossAlert")), "Hunting", "boss alert on it")
        ; the hunting switch on the tab
        d.SelectPage(Dashboard.PageIndex("Plugins"))
        lv.Modify(1, "Select Focus")
        d._PluginShow()
        d.Ctrl("pluginOn").Flip()
        AssertEq(cfg.Get("Plugins.hunting", 1), 0, "switched off at once")
        AssertTrue(!HuntingPlugin.BossOn(cfg), "boss messages off with it")
        ; an outside plugin's settings page from its manifest
        d.OpenPluginPage("nice")
        AssertEq(d.ActivePage, "Plugin settings", "settings page")
        AssertEq(d.Ctrl("psLabel:1").Text, "Speed", "first setting's label")
        AssertEq(d.Ctrl("psEdit:1").Value, "30", "its default")
        d.Ctrl("psEdit:1").Value := "45"
        d.Ctrl("psCheck:2").Value := 1
        d.Ctrl("psSecret:3").Value := "s3cret-value"
        AssertTrue(d.SavePage("Plugin settings"), "saved")
        AssertEq(cfg.Get("Plugin.nice.speed", 0), 45, "int saved")
        AssertEq(cfg.Get("Plugin.nice.loud", 0), 1, "bool saved")
        AssertEq(cfg.Get("Plugin.nice.key_secret", ""), "s3cret-value", "secret saved")
        AssertEq(d.Ctrl("psSecret:3").Value, "", "the secret is not shown again")
        d.Ctrl("psEdit:1").Value := "fast"
        AssertEq(d.SavePage("Plugin settings"), false, "a word in an int field is refused")
    } finally {
        if IsObject(d)
            UiDashClose(d)
        try DirDelete(dir, true)
    }
}

; ---- the API for plugins that move the player (2026-11-27) ----------------

; a plugin that draws its own page (BuildPage): Settings opens it, drawn in
; the dashboard with its helpers, its bound field saved by the page's Save
class PlPagePlugin extends MoontidePlugin {
    loads := 0
    BuildPage(d, page, hooks) {
        this.field := d._StrField(220, 222, "Speed", "Plugin.pagey.speed", "5", 80)
        hooks.load := () => this.loads++
    }
}

Test_Plugins_ApiCallsIntoTheApp() {
    t := AppTestMake()
    host := t.app.plugins                       ; the host whose secrets the app scrubs
    AssertTrue(IsObject(host) && host.app == t.app, "the app has its plugin host")
    e := Plugins._Blank("mover")
    e["id"] := "mover", e["name"] := "Mover", e["builtin"] := false
    api := PluginApi(host, e)
    AssertEq(api.App, "", "a file plugin gets no App")
    AssertEq(api.StopTask(), false, "stopped macro: no task to stop")
    api.HoldRejoin(60000)
    t.app._OnJoin(Map("type", "join", "name", "other", "ts", "x", "live", 1))
    AssertEq(t.app.state.ghost, false, "held: no rejoin of the private server")
    AssertTrue(api.BackToPrivate(), "in another server: back to the private one")
    AssertEq(t.app.state.ghost, true, "recovery rejoins now")
    t.app.state.needRepath := false
    api.Repath()
    AssertTrue(t.app.state.needRepath, "walks to the spot again")
    t.app.state.ghost := false, t.app.state.rareActive := true
    AssertTrue(api.RareHere(), "a rare biome in the own server")
    t.app.state.rareActive := false
    AssertTrue(!api.RareHere(), "none")
    ; a secret handed in is kept out of the log
    api.Secret("tiger-SECRET-77")
    AssertTrue(!InStr(UiLogic.LogLine("x tiger-SECRET-77 y", t.app._Secrets()), "tiger-SECRET-77"), "scrubbed")
    api.Secret("")
    AssertEq(host.Secrets().Length, 0, "cleared")
}

Test_Plugins_PluginDrawsItsOwnPage() {
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
        AssertTrue(d.OpenPluginPage("pagey"), "Settings opens it")
        AssertEq(d.PageOf(o.field), "Plugin page", "drawn in the dashboard")
        AssertEq(o.loads, 1, "its load hook ran")
        AssertEq(o.field.Value, "5", "its bound field loaded")
        AssertTrue(o.field.Visible, "shown")
        o.field.Value := "9"
        d.SavePage("Plugin page")
        AssertEq(cfg.Get("Plugin.pagey.speed", ""), "9", "saved by the page's Save")
        AssertEq(Dashboard.HubOf("Plugin page"), Dashboard.HubOf("Plugins"), "under the Plugins tab")
        AssertTrue(!d.TabShown("Plugin page"), "no tab of its own")
    } finally {
        try IsObject(d) && d.Destroy()
        try DirDelete(dir, true)
    }
}
