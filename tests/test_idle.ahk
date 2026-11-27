#Requires AutoHotkey v2.0
; Tests for idle mode (General.idleMode, 2026-11-17): Start only reads the
; Roblox log, the chat and the biome clock; no task, no focus, no mouse, no
; keys. App parts use the fakes of test_app.ahk; the window source (Ocr.Win /
; Screenshot.FromWindow) is checked on a small window of our own placed off
; every screen (never shown over Roblox, never activated).
#Include %A_LineFile%\..\test_app.ahk
#Include %A_LineFile%\..\test_clip.ahk
#Include %A_LineFile%\..\test_ui_dash.ahk
#Include ..\lib\Json.ahk
#Include ..\lib\Config.ahk
#Include ..\lib\Clip.ahk
#Include ..\lib\ChatWatch.ahk
#Include ..\lib\Ocr.ahk
#Include ..\lib\Screenshot.ahk

; ---- helpers (names must not start with Test_) -----------------------------

class IdleFakeClip extends AppFakeCounter {
    idle := ""
    SetIdle(on) => this.idle := on ? 1 : 0
}

class IdleFakeClock {
    n := 0
    Tick(biome) => this.n++
}

class IdleIO {
    __New() {
        this.log := []
    }
    MoveTo(x, y) => this.log.Push("move " x "," y)
    Wait(ms, ctx := "") => (this.log.Push("wait " ms), true)
    Down(k) => this.log.Push("down " k)
    Up(k) => this.log.Push("up " k)
    ClickHere() => this.log.Push("click")
}

class IdleCal {
    Rect(id) => (id = "chat_rect") ? {x: 10, y: 20, w: 400, h: 200} : ""
    Point(id) => ""
}

IdleMake(vals := "", tasks := "") {
    v := Map("General.sound", 0, "Medal.onRareBiome", 0, "General.idleMode", 1)
    if (vals is Map)
        for k, x in vals
            v[k] := x
    o := Map("cfgVals", v, "be", "fake", "input", AppFakeShift())
    if (tasks is Map)
        o["tasks"] := tasks
    t := AppTestMake(o)
    t.clipx := IdleFakeClip()
    t.app.clip := t.clipx
    return t
}

IdleTicks(t, n := 3) {
    Loop n {
        t.clk.t += 1000
        t.app.Tick()
    }
}

IdleHas(arr, needle) {
    for v in arr
        if InStr(v, needle)
            return true
    return false
}

IdleClear() {
    Ocr.Win := 0
    Screenshot.FromWindow := false
    ChatWatch.NoHover := false
}

; A borderless window off every screen: blue client with a red block at
; client x 100..199. -> Gui (Destroy it)
IdleWindow() {
    g := Gui("+ToolWindow -Caption -DPIScale +E0x08000000")     ; WS_EX_NOACTIVATE
    g.BackColor := "2040C0"
    g.MarginX := 0, g.MarginY := 0
    g.Add("Text", "x100 y0 w100 h100 BackgroundFF0000")
    g.Show("NoActivate x-20000 y-20000 w200 h100")
    DllCall("UpdateWindow", "Ptr", g.Hwnd)
    Sleep(250)                                  ; the background paints a moment after Show
    return g
}

IdleOrigin(hwnd) {
    pt := Buffer(8, 0)
    DllCall("ClientToScreen", "Ptr", hwnd, "Ptr", pt, "Int")
    return {x: NumGet(pt, 0, "Int"), y: NumGet(pt, 4, "Int")}
}

; colour 0xRRGGBB of the 1x1 capture at screen x, y (Ocr._Capture)
IdleCapPixel(x, y) {
    g := Ocr._Capture(x, y, 1, 1, 1, 1)
    try
        return NumGet(g.bits, 0, "UInt") & 0xFFFFFF
    finally
        Ocr._FreeCapture(g)
}

; ---- tests -----------------------------------------------------------------

Test_Idle_StartRunsNoTaskAndSendsNoInput() {
    fish := AppFakeTask("fishing", 99)
    quests := AppFakeTask("quests", 5)
    t := IdleMake(, Map("fishing", fish, "quests", quests))
    try {
        t.rb.activeOk := false                  ; Roblox behind another window
        t.rb.fs := false                        ; and not usable for the normal run
        AssertTrue(t.app.Start(), "started")
        AssertTrue(t.app.IsStarted(), "is started")
        AssertTrue(IdleHas(t.ui.logs, "Idle mode: reading biomes, auras, chat and the biome clock only"), "idle start logged")
        AssertTrue(!t.app.ctx.IsPaused(), "not paused for the window")
        AssertEq(t.timers.Length, 1, "the tick runs")
        IdleTicks(t, 4)
        AssertEq(t.launched.Length, 0, "no task launched")
        AssertEq(fish.runs + quests.runs, 0, "no task ran")
        AssertEq(t.rb.focusCalls, 0, "Roblox never focused")
        AssertTrue(!t.app.ctx.IsPaused(), "still not paused")
        AssertTrue(t.lw.polls >= 1, "the Roblox log is read")
        AssertTrue(t.wh.flushes >= 1, "webhooks are sent")
        AssertEq(t.ui.status.state, "Running", "status Running")
        AssertEq(t.ui.status.task, App.IdleNote, "status says idle")
        AssertEq(t.app.NextUp(), "", "no timed task shown")
        AssertEq(Ocr.Win, 1, "reads come from the Roblox window")
        AssertTrue(Screenshot.FromWindow, "screenshots from the window")
        AssertTrue(ChatWatch.NoHover, "chat read without a hover")
        AssertEq(t.clipx.idle, 1, "clips off")
        t.rb.activeOk := true                   ; even with Roblox in front at Stop
        t.app.Stop("test")
        AssertEq(t.input.shifts.Length, 0, "no shift lock key at stop")
        AssertEq(Ocr.Win, 0, "window source cleared")
        AssertTrue(!Screenshot.FromWindow, "screenshot back to Roblox-in-front only")
        AssertTrue(!ChatWatch.NoHover, "hover back")
        AssertEq(t.clipx.idle, 0, "clips back")
    } finally {
        IdleClear()
    }
}

Test_Idle_BiomesAndChatRead() {
    t := IdleMake()
    try {
        chat := AppFakeChat(t.app)
        t.app.chat := chat
        t.rb.activeOk := false
        t.app.Start()
        t.lw.Push(AppTestEv("biome", "GLITCHED", "2026-11-17T10:00:00Z", true))
        IdleTicks(t, 2)
        AssertEq(t.be.handled.Length, 1, "biome event handled")
        AssertEq(chat.checks, 2, "chat read every tick (ChatWatch throttles itself)")
        t.rb.win := 0                           ; Roblox closed
        IdleTicks(t, 2)
        AssertEq(chat.checks, 2, "no chat read without Roblox")
        AssertEq(Ocr.Win, 0, "no window source")
        AssertEq(t.ui.status.task, "Idle: Roblox not open", "status says why")
        AssertTrue(!t.app.ctx.IsPaused(), "no pause, no rejoin")
        AssertEq(t.launched.Length, 0, "recovery not launched")
        t.app.Stop("test")
    } finally {
        IdleClear()
    }
}

Test_Idle_StartWithoutRobloxAndResume() {
    t := IdleMake()
    try {
        t.rb.win := 0
        AssertTrue(t.app.Start(), "starts with Roblox closed")
        AssertTrue(!t.app.ctx.IsPaused(), "not paused")
        AssertEq(t.ui.status.task, "Idle: Roblox not open", "status")
        t.app.Pause()
        AssertTrue(t.app.ctx.IsPaused(), "F2 pauses")
        AssertTrue(t.app.Resume(), "F2 resumes without a window")
        AssertTrue(!t.app.ctx.IsPaused(), "resumed")
        t.app._FrontRoblox()                    ; schedule / Discord start
        AssertEq(t.rb.focusCalls, 0, "no focus grab for a scheduled start")
        t.app.Stop("test")
    } finally {
        IdleClear()
    }
}

Test_Idle_ClockReadWithRobloxBehind() {
    t := IdleMake()
    try {
        ck := IdleFakeClock()
        t.app.clock := ck
        t.rb.activeOk := false
        t.app.ServiceTick()
        AssertEq(ck.n, 0, "stopped, Roblox behind: no clock read")
        t.app.Start()
        t.app.ServiceTick()
        AssertEq(ck.n, 1, "idle: clock read with Roblox behind")
        t.app.Stop("test")
        t.app.ServiceTick()
        AssertEq(ck.n, 1, "stopped again: no read")
    } finally {
        IdleClear()
    }
}

; stopped, the log is not polled: the biome is the last run's, so the clock
; is not read even with Roblox in front (a frozen clock pinged a boss)
Test_Idle_ClockNotReadWhileStopped() {
    t := IdleMake(Map("General.idleMode", 0))
    try {
        ck := IdleFakeClock()
        t.app.clock := ck
        t.rb.activeOk := true
        t.app.state.biome := "GRAVEYARD"
        t.app.ServiceTick()
        AssertEq(ck.n, 0, "stopped, Roblox in front: no clock read")
    } finally {
        IdleClear()
    }
}

Test_Idle_OffRunsTasksAsBefore() {
    fish := AppFakeTask("fishing", 99)
    t := IdleMake(Map("General.idleMode", 0), Map("fishing", fish))
    try {
        t.app.Start()
        IdleTicks(t, 1)
        AssertEq(t.launched.Length, 1, "fishing launched")
        AssertEq(Ocr.Win, 0, "screen reads")
        AssertTrue(!ChatWatch.NoHover, "hover kept")
        t.app.Stop("test")
    } finally {
        IdleClear()
    }
}

Test_Idle_ChatWatchSkipsHover() {
    io := IdleIO()
    reads := []
    clock := {t: 0}
    cw := ChatWatch({io: io, cal: IdleCal(), now: () => clock.t
        , ocr: (x, y, w, h, scale := 1) => (reads.Push(x "," y "," w "," h), "Mari has arrived")})
    try {
        ChatWatch.NoHover := true
        hits := cw.Check()
        AssertEq(reads.Length, 1, "chat read")
        AssertEq(reads[1], "10,20,400,200", "on the chat rect")
        AssertEq(io.log.Length, 0, "no mouse move, no wait, no key")
        AssertEq(hits.Length, 1, "merchant found")
        ChatWatch.NoHover := false
        clock.t := 10000
        cw.Check()
        AssertTrue(IdleHas(io.log, "move 210,120"), "normal mode still hovers")
    } finally {
        ChatWatch.NoHover := false
    }
}

Test_Idle_ClipRefused() {
    env := ClEnv()
    ClSetup(env, &dir)
    try {
        Clip.SetIdle(true)
        AssertEq(Clip.Trigger("rare"), "idle", "rare clip refused")
        AssertEq(Clip.Trigger("aura:Celestial"), "idle", "aura clip refused")
        AssertEq(env.timers.Length, 0, "nothing scheduled")
        AssertEq(ClCount(env.logs, "idle mode"), 1, "logged once")
        Clip.SetIdle(false)
        AssertEq(Clip.Trigger("rare"), "scheduled", "back to normal")
        Clip.SetIdle(true)                      ; idle starts with a clip pending
        env.RunTimers()
        AssertEq(env.io.log.Length, 0, "the pending clip never presses its key")
        Clip.SetIdle(false)
        ClSetup(env, &dir2, 0)
        Clip.SetIdle(true)
        AssertEq(Clip.Trigger("rare"), "disabled", "clips off stays disabled")
        try DirDelete(dir2, true)
    } finally {
        try DirDelete(dir, true)
        Clip.Reset()
    }
    AssertTrue(!Clip.Idle, "Reset clears idle")
}

Test_Idle_OcrWindowSource() {
    p := Ocr.WinPoint(500, 300, 100, 50)
    AssertEq(p.x " " p.y, "400 250", "screen point -> client point")
    p := Ocr.WinPoint(-19900, -19950, -20000, -20000)
    AssertEq(p.x " " p.y, "100 50", "negative origin")
    g := IdleWindow()
    try {
        o := IdleOrigin(g.Hwnd)
        Ocr.Win := g.Hwnd
        Loop 20 {                               ; the window's background paints a moment after Show
            if IdleCapPixel(o.x + 50, o.y + 50)
                break
            Sleep(100)
        }
        AssertEq(Format("{:06X}", IdleCapPixel(o.x + 50, o.y + 50)), "2040C0", "client 50,50 is the blue background")
        AssertEq(Format("{:06X}", IdleCapPixel(o.x + 150, o.y + 50)), "FF0000", "client 150,50 is the red block")
        Ocr.Win := 0x7FFFFFF0                   ; no such window
        AssertEq(Ocr.Read(0, 0, 50, 20), "", "a gone window reads nothing, no throw")
    } finally {
        Ocr.Win := 0
        g.Destroy()
    }
}

Test_Idle_ScreenshotOnlyViaWindow() {
    AssertEq(Screenshot.Source(false, false), "", "not in front, screen copy: refused")
    AssertEq(Screenshot.Source(true, false), "screen", "in front: screen copy")
    AssertEq(Screenshot.Source(false, true), "window", "idle: window copy")
    AssertEq(Screenshot.Source(true, true), "window", "idle in front: still the window copy")
    g := IdleWindow()
    path := ""
    try {
        AssertTrue(!WinActive("ahk_id " g.Hwnd), "test window not active")
        AssertEq(Screenshot.Capture(g.Hwnd), "", "behind, no idle: refused")
        Screenshot.FromWindow := true
        path := Screenshot.Capture(g.Hwnd)
        AssertTrue(path != "" && FileExist(path), "idle: PNG made from the window")
    } finally {
        Screenshot.FromWindow := false
        g.Destroy()
        if (path != "")
            try FileDelete(path)
    }
}

; PrintWindow waits on the window's own thread: a Roblox that is not
; responding would freeze the macro inside it (F3 too). Such a window is
; not read and not copied (bug hunt 2026-11-26).
Test_Idle_HungWindowNotRead() {
    AssertEq(Ocr.Hung(DllCall("GetDesktopWindow", "Ptr")), false, "the real check answers (desktop not hung)")
    g := IdleWindow()
    path := ""
    try {
        o := IdleOrigin(g.Hwnd)
        Ocr.Win := g.Hwnd
        Loop 20 {
            if IdleCapPixel(o.x + 50, o.y + 50)
                break
            Sleep(100)
        }
        AssertTrue(IdleCapPixel(o.x + 50, o.y + 50) != 0, "a responding window is read")
        asked := [0]
        Ocr.HungFn := (h) => (asked[1]++, h = g.Hwnd)
        got := ""
        try got := IdleCapPixel(o.x + 50, o.y + 50)
        catch Error as e
            got := e.Message
        AssertTrue(InStr(got, "not responding"), "a hung window is not copied: " got)
        AssertTrue(asked[1] > 0, "asked before the copy")
        AssertEq(Ocr.Read(0, 0, 50, 20), "", "Ocr.Read on it: nothing, no throw")
        Screenshot.FromWindow := true
        Screenshot.HungFn := (h) => (h = g.Hwnd)
        AssertEq(Screenshot.Capture(g.Hwnd), "", "a hung window is not copied")
        Screenshot.HungFn := ""
        path := Screenshot.Capture(g.Hwnd)
        AssertTrue(path != "" && FileExist(path), "responding again: copied")
    } finally {
        Ocr.HungFn := "", Screenshot.HungFn := ""
        Ocr.Win := 0
        Screenshot.FromWindow := false
        g.Destroy()
        if (path != "")
            try FileDelete(path)
    }
}

; Home > Overview: the switch sits in the Potion safety panel, overlaps nothing,
; and a flip is saved at once (the Run page has no Save button)
Test_Idle_DashboardSwitch() {
    dir := UiDashTmp()
    d := ""
    try {
        cfg := Config.Load(dir)
        AssertEq(cfg.Get("General.idleMode", ""), "0", "default off")
        d := Dashboard(cfg)
        d.SelectPage(1)
        sw := d.Ctrl("General.idleMode")
        AssertTrue(IsObject(sw), "switch bound")
        AssertEq(sw.Value, 0, "loaded off")
        own := Map(sw._box.Hwnd, 1, sw._lbl.Hwnd, 1)
        mine := [UiDashPos(sw._box), UiDashPos(sw._lbl)]
        for c in d._pages[1].ctrls
            if (Theme.HelpText(c) = HelpTexts.For("General.idleMode"))
                own[c.Hwnd] := 1, mine.Push(UiDashPos(c))
        AssertEq(mine.Length, 3, "box, label and its ?")
        pn := UiDashPos(d.Ctrl("panel:Run:Potion safety"))
        ovR := (a, b) => !(a.x + a.w <= b.x || b.x + b.w <= a.x || a.y + a.h <= b.y || b.y + b.h <= a.y)
        for r in mine {
            AssertTrue(r.x >= pn.x && r.y >= pn.y && r.x + r.w <= pn.x + pn.w && r.y + r.h <= pn.y + pn.h
                , "inside the panel: " r.x "," r.y " " r.w "x" r.h)
            for c in d._pages[1].ctrls {
                if (own.Has(c.Hwnd) || Theme.IsPanel(c))
                    continue
                AssertTrue(!ovR(r, UiDashPos(c)), "not over '" SubStr(c.Text, 1, 30) "'")
            }
        }
        sw.Flip()
        AssertEq(String(Config.Load(dir).Get("General.idleMode", "")), "1", "saved at once")
        sw.Flip()
        AssertEq(String(Config.Load(dir).Get("General.idleMode", "")), "0", "off saved")
    } finally {
        UiDashClose(d)
        try DirDelete(dir, true)
    }
}
