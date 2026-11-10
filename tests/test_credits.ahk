#Requires AutoHotkey v2.0
; Offline tests for lib\Credits.ahk (encoded credits, SHA-256, tamper check)
; and tools\update_credits.ahk. Helpers are prefixed CreditsT.
#Include ..\lib\Credits.ahk
#Include ..\tools\update_credits.ahk
#Include test_webhook_features.ahk

CreditsTRepo() {
    SplitPath(A_LineFile, , &dir)
    SplitPath(dir, , &root)
    return root
}

; Copies the four files that make up the check into a fresh temp root.
CreditsTCopy(withAvatar := true) {
    src := CreditsTRepo()
    tmp := A_Temp "\vesper_credits_" A_TickCount "_" Random(1000, 9999)
    DirCreate(tmp "\lib\ui")
    DirCreate(tmp "\assets\credits")
    FileCopy(src "\lib\Credits.ahk", tmp "\lib\Credits.ahk")
    FileCopy(src "\lib\Brand.ahk", tmp "\lib\Brand.ahk")
    FileCopy(src "\lib\ui\Splash.ahk", tmp "\lib\ui\Splash.ahk")
    if withAvatar
        FileCopy(src "\assets\credits\avatar.png", tmp "\assets\credits\avatar.png")
    return tmp
}

CreditsTFlipByte(path) {
    b := FileRead(path, "RAW")
    NumPut("UChar", NumGet(b, 100, "UChar") ^ 0xFF, b, 100)
    f := FileOpen(path, "w")
    f.RawWrite(b)
    f.Close()
}

Test_Credits_Decode() {
    AssertEq(Credits.Name(), "Vesper", "name")
    AssertEq(Credits.Discord(), ".unavailableuser.", "discord name")
    AssertEq(Credits.Message(), "thanks for using this, hopefully it helped you as much as it helped me also does anyone remember dolphsol?", "message")
    AssertEq(Credits.MadeBy(), "made by Vesper", "made by")
    AssertEq(Credits.ByLine(), "by Vesper", "by line")
    AssertEq(Credits.Banner(), "Modified copy " Chr(0xB7) " original by Vesper", "banner")
    AssertEq(Credits.Server(), Brand.DiscordUrl, "server")
}

Test_Credits_NotInPlainText() {
    txt := FileRead(CreditsTRepo() "\lib\Credits.ahk", "UTF-8")
    AssertTrue(!InStr(txt, "Vesper"), "no plain name")
    AssertTrue(!InStr(txt, "unavailableuser"), "no plain discord name")
    AssertTrue(!InStr(txt, "dolphsol"), "no plain message")
}

Test_Credits_Sha256Known() {
    b := Buffer(3)
    StrPut("abc", b, 3, "CP0")
    AssertEq(Credits.Sha256(b), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", "sha256 abc")
}

Test_Credits_VerifyShippedCopy() {
    r := Credits.Verify()
    AssertTrue(r.ok, "shipped copy is original: " r.why)
    AssertEq(Credits.Decode(Brand._ck), Credits.Fingerprint(CreditsTRepo()), "Brand check value")
    AssertEq(Credits.Decode(Splash._ck), Credits.Fingerprint(CreditsTRepo()), "Splash check value")
}

Test_Credits_EditedFileIsModified() {
    tmp := CreditsTCopy()
    try {
        AssertTrue(Credits.Verify(tmp).ok, "untouched copy is original")
        CreditsTFlipByte(tmp "\assets\credits\avatar.png")
        r := Credits.Verify(tmp)
        AssertTrue(!r.ok, "edited avatar is modified")
        AssertTrue(r.why != "", "why is given")
    } finally DirDelete(tmp, true)
    tmp := CreditsTCopy()
    try {
        CreditsTFlipByte(tmp "\lib\Credits.ahk")
        AssertTrue(!Credits.Verify(tmp).ok, "edited Credits.ahk is modified")
    } finally DirDelete(tmp, true)
}

Test_Credits_MissingAvatarIsModified() {
    tmp := CreditsTCopy(false)
    try {
        r := Credits.Verify(tmp)
        AssertTrue(!r.ok, "missing avatar is modified")
        AssertEq(Credits.Fingerprint(tmp), "", "no fingerprint without the avatar")
    } finally DirDelete(tmp, true)
}

Test_Credits_UpdateToolRoundTrip() {
    tmp := CreditsTCopy()
    try {
        CreditsTFlipByte(tmp "\assets\credits\avatar.png")
        AssertTrue(!Credits.Verify(tmp).ok, "edited avatar fails before the update")
        UpdateCredits(tmp)
        r := Credits.Verify(tmp)
        AssertTrue(r.ok, "passes after the update: " r.why)
    } finally DirDelete(tmp, true)
}

; ---- placements (Task 7): everything below builds the Dashboard hidden ------

Test_Credits_VerifyNeverThrows() {
    saved := Credits.Sha256
    try {
        Credits.DefineProp("Sha256", {call: (this, buf) => AppTestThrow("no cng")})
        r := Credits.Verify()
        AssertTrue(!r.ok, "hash failure is not ok")
        AssertEq(r.why, "hash unavailable", "why")
    } finally Credits.DefineProp("Sha256", {call: saved})
}

Test_Credits_ShownEverywhere() {
    dir := UiDashTmp()
    d := ""
    try {
        d := Dashboard(Config.Load(dir), Map())
        AssertEq(d._gui.Title, Brand.Name " " Chr(0xB7) " by Vesper", "dashboard title")
        AssertEq(d.Ctrl("credits.name").Text, "Vesper", "credits page name")
        AssertEq(Splash.Text(), "Moontide Macro " Chr(0xB7) " made by Vesper", "splash text")
        AssertTrue(InStr(Splash.Text(), "made by Vesper"), "splash made by")
        hooks := [WfHook("All", "a", 1, Webhook.EventTypes.Clone())]
        wcfg := WfCfg(Map("General.sound", 0, "Medal.onRareBiome", 0, "Craft.enabled", 0), hooks)
        wh := Webhook(wcfg)
        wh.dryRun := true
        t := AppTestMake(Map("cfgObj", wcfg, "whObj", wh))
        t.app.dash := d
        t.ui.logs := []
        t.app.ui := []
        t.app.Log("early line")          ; logged before the UI exists
        t.app.ui := [t.ui]
        t.app.FlushEarly()
        AssertEq(t.ui.logs[1], Brand.Name " by Vesper", "by-line is the first log line")
        AssertEq(t.ui.logs[2], "early line", "early lines follow the by-line")
        found := false
        for line in t.ui.logs
            if (line = Brand.Name " by Vesper")
                found := true
        AssertTrue(found, "log has the by-Vesper line")
        t.app.Start()
        wh.Flush()
        e := WfRecs(wh, "All")[1].p["embeds"][1]
        AssertTrue(InStr(e["description"], "Made by Vesper"), "start message has the credit")
        AssertTrue(InStr(e["description"], "Made by Vesper`n## " Emoji.Chat), "credit sits above the Discord line")
        AssertEq(e["footer"]["text"], Brand.Footer, "webhook footer unchanged")
        AssertTrue(!d.Modified, "shipped copy shows no banner")
    } finally {
        UiDashClose(d)
        CfgTmpClean(dir)
    }
}

Test_Credits_BannerOnModified() {
    dir := UiDashTmp()
    d := ""
    try {
        d := Dashboard(Config.Load(dir), Map())
        t := AppTestMake(Map("creditsVerify", () => ({ok: false, why: "forced"})))
        t.app.dash := d
        t.app.CheckCredits()
        AssertTrue(d.Ctrl("credits.banner").Visible, "banner visible")
        AssertEq(d.Ctrl("credits.banner").Text, Credits.Banner(), "banner text")
        t2 := AppTestMake(Map("creditsVerify", () => ({ok: true, why: ""})))
        t2.app.dash := d
        t2.app.CheckCredits()
        AssertTrue(!d.Ctrl("credits.banner").Visible, "banner hidden when ok")
        AssertTrue(!d.Modified, "not modified")
    } finally {
        UiDashClose(d)
        CfgTmpClean(dir)
    }
}

Test_Credits_LiveCheck() {
    dir := UiDashTmp()
    d := ""
    try {
        d := Dashboard(Config.Load(dir), Map())
        AssertTrue(d.LiveCheck(), "untouched window passes")
        AssertTrue(!d.Ctrl("credits.banner").Visible, "no banner yet")
        d.Ctrl("credits.name").Text := "Someone"
        AssertTrue(!d.LiveCheck(), "changed name fails")
        AssertTrue(d.Ctrl("credits.banner").Visible, "banner shown")
        d.SetModified(false)
        AssertTrue(!d.Ctrl("credits.banner").Visible, "SetModified(false) hides")
        d.Ctrl("credits.name").Text := Credits.Name()
        d._gui.Title := "Moontide Macro"
        AssertTrue(!d.LiveCheck(), "title without the by-line fails")
        AssertTrue(d.Ctrl("credits.banner").Visible, "banner shown for the title")
        ; App wires the live check too
        d.SetModified(false)
        d._gui.Title := Brand.Name " " Chr(0xB7) " " Credits.ByLine()
        d.Ctrl("credits.name").Text := "Someone"
        t := AppTestMake()
        t.app.dash := d
        t.app.CheckCredits()
        AssertTrue(d.Ctrl("credits.banner").Visible, "App.CheckCredits runs the live check")
    } finally {
        UiDashClose(d)
        CfgTmpClean(dir)
    }
}

Test_Credits_AppVerifiesWithoutRoot() {
    seen := []
    t := AppTestMake(Map("creditsVerify", (args*) => (seen.Push(args.Length), {ok: true, why: ""})))
    dir := UiDashTmp()
    d := ""
    try {
        d := Dashboard(Config.Load(dir), Map())
        t.app.dash := d
        t.app.CheckCredits()
        AssertEq(seen.Length, 1, "verify called once")
        AssertEq(seen[1], 0, "verify gets no root argument")
    } finally {
        UiDashClose(d)
        CfgTmpClean(dir)
    }
}

Test_Credits_SplashRunsHeadless() {
    Anim.Reset()
    t0 := A_TickCount
    Splash.Show(Map("animations", 1, "noshow", 1, "holdMs", 40))
    ms := A_TickCount - t0
    AssertTrue(ms >= 600 && ms < 3000, "fade in + hold + fade out ran for " ms " ms")
    AssertEq(Anim.Active(), 0, "no tween left behind")
    t0 := A_TickCount
    Splash.Show(Map("animations", 0, "noshow", 1))
    ms := A_TickCount - t0
    AssertTrue(ms >= 550 && ms < 1500, "no-fade splash shows about 600 ms: " ms)
}

; opacity of a layered window, read back: {alpha, flags}
CreditsTAlpha(g) {
    key := 0, alpha := 0, flags := 0
    DllCall("GetLayeredWindowAttributes", "Ptr", g.Hwnd, "UInt*", &key, "UChar*", &alpha, "UInt*", &flags)
    return {alpha: alpha, flags: flags}
}

Test_Credits_SplashIsDrawnWithoutFades() {
    Anim.Reset()
    seen := []
    Splash.Show(Map("animations", 0, "noshow", 1, "hook", (g, c) => seen.Push(CreditsTAlpha(g))))
    AssertEq(seen.Length, 1, "hook ran")
    AssertEq(seen[1].alpha, 255, "no fades: fully opaque (a layered window is blank until this is set)")
    AssertTrue((seen[1].flags & 2) != 0, "LWA_ALPHA is set")
    Splash.Show(Map("animations", 1, "noshow", 1, "holdMs", 10, "hook", (g, c) => seen.Push(CreditsTAlpha(g))))
    AssertEq(seen[2].alpha, 0, "fades start from transparent")
}

Test_Credits_SplashClickSkips() {
    Anim.Reset()
    hook := (g, c) => SetTimer(() => DllCall("PostMessage", "Ptr", g.Hwnd, "UInt", 0x111
        , "UPtr", DllCall("GetDlgCtrlID", "Ptr", c.Hwnd), "Ptr", c.Hwnd), -150)     ; WM_COMMAND, STN_CLICKED
    t0 := A_TickCount
    Splash.Show(Map("animations", 1, "noshow", 1, "holdMs", 5000, "hook", hook))
    ms := A_TickCount - t0
    AssertTrue(ms < 1000, "a click ends the splash early: " ms " ms")
    AssertEq(Anim.Active(), 0, "no tween left behind")
    t0 := A_TickCount
    Splash.Show(Map("animations", 0, "noshow", 1, "hook", hook))
    ms := A_TickCount - t0
    AssertTrue(ms < 450, "a click also skips the no-fade splash: " ms " ms")
}

Test_Credits_SplashErrorLeavesNoWindow() {
    Anim.Reset()
    box := {h: 0}
    try Splash.Show(Map("noshow", 1, "hook", (g, c) => (box.h := g.Hwnd, AppTestThrow("boom"))))
    catch Any as e
        AssertEq(e.Message, "boom", "the error comes through")
    AssertTrue(box.h != 0 && !DllCall("IsWindow", "Ptr", box.h), "window destroyed after an error")
    AssertEq(Anim.Active(), 0, "no tween left behind")
}

Test_Credits_SplashSkippedWithoutRealUi() {
    calls := []
    t := AppTestMake(Map("splash", (o) => calls.Push(o)))
    t.app.ShowSplash("hidden")
    t.app.ShowSplash("offscreen")
    AssertEq(calls.Length, 0, "no splash in hidden / offscreen modes")
    t.app.ShowSplash("normal")
    AssertEq(calls.Length, 1, "splash in normal mode")
    AssertEq(calls[1]["animations"], 1, "animations default on")
    t2 := AppTestMake(Map("splash", (o) => calls.Push(o), "cfgObj", AppFakeCfg(Map("UI.animations", 0))))
    t2.app.ShowSplash("normal")
    AssertEq(calls[2]["animations"], 0, "animations off is passed on")
    t3 := AppTestMake()
    t3.app.ShowSplash("normal")
    AssertEq(calls.Length, 2, "a test app with a given ui never opens the real splash")
}
