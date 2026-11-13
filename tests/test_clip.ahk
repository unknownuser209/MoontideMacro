#Requires AutoHotkey v2.0
; Tests for lib\Clip.ahk (Medal clip trigger). Offline: fake process check,
; fake clock, fake one-shot timer, recording IO. Never sends real keys.
#Include ..\lib\Json.ahk
#Include ..\lib\Config.ahk
#Include ..\lib\Input.ahk
#Include ..\lib\Clip.ahk

; ---- helpers (names must not start with Test_) -----------------------------

class ClIO {
    __New() {
        this.log := []
    }
    Down(k) => this.log.Push("down " k)
    Up(k) => this.log.Push("up " k)
    MoveTo(x, y) => this.log.Push("move " x "," y)
    ClickHere() => this.log.Push("click")
    Text(s) => this.log.Push("text " s)
    Wait(ms, ctx := "") => true
}

class ClWh {
    __New() {
        this.sent := []
    }
    Send(ev, title, desc, color, opts := "") => this.sent.Push({event: ev, title: title, desc: desc, opts: opts})
}

; Fake environment: clock (ms), process check, one-shot timer queue.
class ClEnv {
    __New() {
        this.now := 100000
        this.medal := 4242          ; pid; 0 = not running
        this.timers := []           ; {fn, ms}
        this.logs := []
        this.io := ClIO()
        this.wh := ClWh()
        this.stopped := false
    }
    Opts() => Map(
        "procFn", (name) => (name = "medal.exe") ? this.medal : 0,
        "clockFn", () => this.now,
        "timerFn", (fn, ms) => this.timers.Push({fn: fn, ms: ms}),
        "io", this.io,
        "stopFn", () => this.stopped)
    RunTimers() {
        t := this.timers
        this.timers := []
        for x in t
            x.fn.Call()
    }
}

ClTmpDir() {
    d := A_Temp "\vesper_cliptest_" A_TickCount "_" Random(100000, 999999)
    DirCreate(d)
    return d
}

ClSetup(env, &dir, enabled := 1, hotkey := "F8") {
    dir := ClTmpDir()
    cfg := Config.Load(dir)
    cfg.Set("Medal.enabled", enabled)
    cfg.Set("Medal.clipHotkey", hotkey)
    Clip.Setup(cfg, env.wh, (t) => env.logs.Push(t), env.Opts())
    return cfg
}

ClCount(arr, needle) {
    n := 0
    for v in arr
        if InStr(v, needle)
            n++
    return n
}

; ---- tests -----------------------------------------------------------------

Test_Clip_CooldownBlocksDuplicate() {
    env := ClEnv()
    ClSetup(env, &dir)
    try {
        AssertEq(Clip.Trigger("rare"), "scheduled", "first rare scheduled")
        AssertEq(env.timers.Length, 1, "one timer")
        AssertEq(env.timers[1].ms, 3000, "default delaySec 3")
        AssertEq(env.io.log.Length, 0, "no key before delay")
        env.RunTimers()
        AssertEq(env.io.log.Length, 2, "hotkey tapped once")
        AssertEq(env.io.log[1], "down F8", "hotkey down")
        AssertEq(env.io.log[2], "up F8", "hotkey up")
        AssertEq(env.wh.sent.Length, 1, "clips webhook")
        AssertEq(env.wh.sent[1].event, "clips", "clips event")
        env.now += 10000
        AssertEq(Clip.Trigger("rare"), "cooldown", "duplicate within 30 s blocked")
        AssertEq(env.timers.Length, 0, "no timer for duplicate")
        AssertEq(Clip.Trigger("aura:Abyssal Hunter"), "scheduled", "other reason class not blocked")
        env.RunTimers()
        env.now += 5000
        AssertEq(Clip.Trigger("aura:Other"), "cooldown", "aura class shares one cooldown")
        env.now += 16000                       ; 31 s after first rare
        AssertEq(Clip.Trigger("rare"), "scheduled", "rare allowed after 30 s")
        AssertEq(ClCount(env.io.log, "down F8"), 2, "two clips sent so far")
    } finally {
        try DirDelete(dir, true)
        Clip.Reset()
    }
}

Test_Clip_SkipsWhenMedalMissing() {
    env := ClEnv()
    env.medal := 0
    ClSetup(env, &dir)
    try {
        AssertEq(Clip.Trigger("rare"), "no_medal", "skipped without Medal")
        AssertEq(Clip.Trigger("rare"), "no_medal", "skipped again")
        AssertEq(env.timers.Length, 0, "no timer")
        AssertEq(env.io.log.Length, 0, "no key")
        AssertEq(ClCount(env.logs, "Medal"), 1, "warning logged once")
        ; Medal starts: missing runs did not consume the cooldown
        env.medal := 99
        AssertEq(Clip.Trigger("rare"), "scheduled", "scheduled once Medal runs")
        ; Medal closes before the delay ends: nothing sent
        env.medal := 0
        env.RunTimers()
        AssertEq(env.io.log.Length, 0, "no key when Medal gone at fire time")
        AssertEq(env.wh.sent.Length, 0, "no clips webhook when not sent")
    } finally {
        try DirDelete(dir, true)
        Clip.Reset()
    }
}

Test_Clip_DisabledAndUnsafeHotkeys() {
    env := ClEnv()
    ClSetup(env, &dir, 0)
    try {
        AssertEq(Clip.Trigger("rare"), "disabled", "Medal.enabled=0 -> nothing")
        AssertEq(env.timers.Length, 0, "no timer when disabled")
    } finally {
        try DirDelete(dir, true)
        Clip.Reset()
    }
    ; mouse buttons, macro hotkeys and letters are never sent
    for hk in ["LButton", "RButton", "F1", "F2", "F3", "e", "5", "^F8", "", "Numpad5", "PrintScreen", "Insert", "Space"] {
        env := ClEnv()
        ClSetup(env, &dir, 1, hk)
        try {
            AssertEq(Clip.Trigger("rare"), "bad_hotkey", "refused hotkey <" hk ">")
            AssertEq(env.timers.Length, 0, "no timer for <" hk ">")
        } finally {
            try DirDelete(dir, true)
            Clip.Reset()
        }
    }
    AssertTrue(Clip.HotkeyAllowed("F4") && Clip.HotkeyAllowed("F8") && Clip.HotkeyAllowed("F24"), "F4-F24 allowed")
    AssertTrue(!Clip.HotkeyAllowed("F25") && !Clip.HotkeyAllowed("Numpad5"), "nothing else")
}

Test_Clip_HotkeyMustNotClashWithMacroKeys() {
    ; capture key (default F4) and recorder key (F7) are refused
    for hk in ["F4", "F7", "f4"] {
        env := ClEnv()
        ClSetup(env, &dir, 1, hk)
        try {
            AssertEq(Clip.Trigger("rare"), "bad_hotkey", "refused <" hk ">")
            AssertEq(env.timers.Length, 0, "no timer for <" hk ">")
            AssertTrue(ClCount(env.logs, "pick another") = 1, "user told why, once")
        } finally {
            try DirDelete(dir, true)
            Clip.Reset()
        }
    }
    ; remapped macro hotkeys and capture key are honoured
    env := ClEnv()
    cfg := ClSetup(env, &dir, 1, "F6")
    try {
        AssertEq(Clip.Trigger("rare"), "scheduled", "F6 allowed by default (capture key is F4)")
        cfg.Set("Hotkeys.stop", "F6")
        AssertTrue(InStr(Clip.HotkeyProblem("F6", cfg), "stop hotkey"), "same as the stop hotkey")
        cfg.Set("Hotkeys.stop", "F3")
        cfg.Set("Hotkeys.start", "F10")
        AssertTrue(InStr(Clip.HotkeyProblem("F10", cfg), "start hotkey"), "same as the start hotkey")
        cfg.Set("Calibrate.captureKey", "F11")
        AssertTrue(InStr(Clip.HotkeyProblem("F11", cfg), "capture key"), "same as a remapped capture key")
        AssertEq(Clip.HotkeyProblem("F6", cfg), "", "F6 free once the capture key moved")
        AssertTrue(InStr(Clip.HotkeyProblem("F7", cfg), "recorder"), "recorder key always refused")
        AssertTrue(InStr(Clip.HotkeyProblem("e", cfg), "F4-F24"), "non-F key message")
        AssertEq(Clip.HotkeyProblem("F8", cfg), "", "F8 fine")
    } finally {
        try DirDelete(dir, true)
        Clip.Reset()
    }
    ; the Dashboard's Alerts > Clips tab refuses the same keys on Save
    dir := UiDashTmp()
    d := ""
    try {
        cfg := Config.Load(dir)
        d := Dashboard(cfg)
        for bad in ["F4", "F7", "F1"] {
            d.Ctrl("Medal.clipHotkey").Value := bad
            AssertEq(d.SavePage("Clips"), false, "Clips save refuses <" bad ">")
            AssertEq(cfg.Get("Medal.clipHotkey", "F8"), "F8", "refused <" bad "> never reaches cfg")
        }
        d.Ctrl("Medal.clipHotkey").Value := "F6"
        AssertTrue(d.SavePage("Clips"), "Clips save takes F6")
        AssertEq(Config.Load(dir).Get("Medal.clipHotkey", ""), "F6", "F6 on disk")
    } finally {
        UiDashClose(d)
        try DirDelete(dir, true)
    }
}

Test_Clip_AuraList() {
    env := ClEnv()
    cfg := ClSetup(env, &dir)
    try {
        cfg.Set("Medal.auras", " Abyssal Hunter , Gargantua,,")
        AssertTrue(Clip.AuraWanted("abyssal hunter"), "case/space-insensitive match")
        AssertTrue(Clip.AuraWanted("Gargantua"), "second entry")
        AssertTrue(!Clip.AuraWanted("Common"), "not in list")
        AssertTrue(!Clip.AuraWanted(""), "empty aura never")
        AssertEq(Clip.ReasonClass("aura:Gargantua"), "aura", "aura reason class")
        AssertEq(Clip.ReasonClass("rare"), "rare", "rare reason class")
    } finally {
        try DirDelete(dir, true)
        Clip.Reset()
    }
}

Test_Clip_DefersWhileBusy() {
    env := ClEnv()
    ClSetup(env, &dir)
    try {
        PotionsTask.busy := true
        AssertEq(Clip.Trigger("rare"), "scheduled", "scheduled")
        env.RunTimers()
        AssertEq(env.io.log.Length, 0, "no key while a potion is being handled")
        AssertEq(env.timers.Length, 1, "re-armed")
        AssertEq(env.timers[1].ms, 1000, "re-armed ~1 s later")
        env.RunTimers()
        AssertEq(env.io.log.Length, 0, "still no key while busy")
        PotionsTask.busy := false
        env.RunTimers()
        AssertEq(env.io.log.Length, 2, "key sent once potions are done")
    } finally {
        PotionsTask.busy := false
        try DirDelete(dir, true)
        Clip.Reset()
    }
}

Test_Clip_NoFireAfterStop() {
    env := ClEnv()
    ClSetup(env, &dir)
    try {
        AssertEq(Clip.Trigger("rare"), "scheduled", "scheduled")
        Clip.CancelAll()                       ; F3 / stop
        env.RunTimers()
        AssertEq(env.io.log.Length, 0, "CancelAll: scheduled clip never fires")
        AssertEq(env.wh.sent.Length, 0, "no clips webhook")
        env.now += 31000
        AssertEq(Clip.Trigger("aura:X"), "scheduled", "new trigger after cancel")
        env.stopped := true                    ; stop flag seen at fire time
        env.RunTimers()
        AssertEq(env.io.log.Length, 0, "stopFn true: clip dropped")
    } finally {
        try DirDelete(dir, true)
        Clip.Reset()
    }
}

; ---- combo clip hotkeys (the user, 2026-11-12: "alt+9 or shift+f5+t") -------

Test_Clip_ComboHotkeysParse() {
    AssertEq(Clip.HotkeyText("alt+9"), "Alt+9", "Alt+9")
    AssertEq(Clip.HotkeyText("shift+f5+t"), "Shift+F5+T", "Shift+F5+T")
    AssertEq(Clip.HotkeyText(" T + shift "), "Shift+T", "modifiers first, spaces and case ignored")
    AssertEq(Clip.HotkeyText("control+alt+F9"), "Ctrl+Alt+F9", "Control = Ctrl")
    AssertEq(Clip.HotkeyText("F8"), "F8", "one key as before")
    AssertEq(Clip.HotkeyText("f10+t"), "F10+T", "an F key with a letter")
    for bad in ["t+y", "9", "e", "alt+shift", "alt+f4", "win+d", "lwin+9", "alt+f1", "ctrl+f3", "alt+9+9"
        , "ctrl+alt+shift+f5+t", "alt+", "+9", "alt+space", "alt+tab", "alt+enter", "^F8", "LButton+alt"]
        AssertEq(Clip.HotkeyText(bad), "", "refused <" bad ">")
}

Test_Clip_ComboHotkeyPressedInOrder() {
    for c in [["alt+9", ["down Alt", "down 9", "up 9", "up Alt"]]
        , ["Shift+F5+T", ["down Shift", "down F5", "down t", "up t", "up F5", "up Shift"]]] {
        env := ClEnv()
        ClSetup(env, &dir, 1, c[1])
        try {
            AssertEq(Clip.Trigger("rare"), "scheduled", c[1] " scheduled")
            env.RunTimers()
            got := ""
            for e in env.io.log
                got .= (got = "" ? "" : ", ") e
            want := ""
            for e in c[2]
                want .= (want = "" ? "" : ", ") e
            AssertEq(got, want, c[1] " held in order, last tapped, released in reverse (letters lower case)")
            AssertEq(env.wh.sent.Length, 1, c[1] " clips webhook")
        } finally {
            try DirDelete(dir, true)
            Clip.Reset()
        }
    }
}

Test_Clip_ComboMustNotHoldMacroKeys() {
    dir := ClTmpDir()
    try {
        cfg := Config.Load(dir)
        AssertEq(Clip.HotkeyProblem("alt+9", cfg), "", "Alt+9 fine")
        AssertTrue(InStr(Clip.HotkeyProblem("shift+f4", cfg), "capture key"), "holds the capture key F4")
        AssertTrue(InStr(Clip.HotkeyProblem("ctrl+f7", cfg), "route recorder"), "holds the recorder key F7")
        AssertTrue(InStr(Clip.HotkeyProblem("t+y", cfg), "Alt+9"), "the refusal shows a combo example")
    } finally {
        try DirDelete(dir, true)
    }
    ; the Clips page saves a combo
    dir := UiDashTmp()
    d := ""
    try {
        cfg := Config.Load(dir)
        d := Dashboard(cfg)
        d.Ctrl("Medal.clipHotkey").Value := "shift+f5+t"
        AssertTrue(d.SavePage("Clips"), "Clips save takes Shift+F5+T")
        AssertEq(Config.Load(dir).Get("Medal.clipHotkey", ""), "shift+f5+t", "on disk")
        d.Ctrl("Medal.clipHotkey").Value := "alt+f4"
        AssertEq(d.SavePage("Clips"), false, "Alt+F4 refused")
    } finally {
        UiDashClose(d)
        try DirDelete(dir, true)
    }
}
