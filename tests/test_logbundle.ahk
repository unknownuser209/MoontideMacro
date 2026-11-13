#Requires AutoHotkey v2.0
; Offline tests for lib\LogBundle.ahk: temp folders under A_Temp, a fake zip
; step (one test runs the real PowerShell zip). Helpers are prefixed Lb.
#Include ..\lib\LogBundle.ahk

LbHook() => "https://discord.com/api/webhooks/987654321/ZzYyXxTokenSECRET"
LbLink() => "https://www.roblox.com/games/1/x?privateServerLinkCode=LBCODE777"

; A fake program folder + temp folder; returns {root, temp, out, cap, opts}.
; "zip" copies the staged files to <cap> instead of zipping.
LbRig(nLog := 10, user := "Zephyrine") {
    base := A_Temp "\vesper_lbtest_" A_TickCount "_" Random(1000, 9999)
    root := base "\prog"
    DirCreate(root "\logs")
    DirCreate(base "\temp")
    DirCreate(base "\cap")
    log := ""
    Loop nLog
        log .= "12:00:" Format("{:02}", Mod(A_Index, 60)) "  line " A_Index "`n"
    log .= "12:01:00  saved to C:\Users\" user "\AppData\Local\Temp\x.png`n"
    log .= "12:01:01  webhook " LbHook() " failed`n"
    log .= "12:01:02  join " LbLink() "`n"
    log .= "12:01:03  secret value " LbSecretValue() " seen`n"
    FileAppend(log, root "\logs\macro.log", "UTF-8")
    ini := "[General]`r`nsellEvery=15`r`nprivateServer=" LbLink() "`r`nhotkeys=F1,F2`r`n`r`n"
        . "[Webhook.1]`r`nname=Main`r`nurl=" LbHook() "`r`nmention=<@1234567>`r`nenabled=1`r`n`r`n"
        . "[Remote]`r`nenabled=1`r`nport=8080`r`npin=" LbSecretValue() "`r`n"
        . "[Misc]`r`napiToken=" LbSecretValue() "`r`nfolder=C:\Users\" user "\Documents`r`nempty_token=`r`n"
    FileAppend(ini, root "\settings.ini", "UTF-8")
    cap := base "\cap"
    r := {root: root, temp: base "\temp", out: base "\out", cap: cap, dir: base, user: user}
    r.opts := Map("tempDir", base "\temp", "outDir", base "\out", "userName", user
        , "zip", (stage, zip) => LbFakeZip(stage, zip, cap))
    return r
}

LbSecretValue() => "tiger7-REMOTE-PIN-9"

; copy the staged files to cap and drop an empty "zip" so Make sees it
LbFakeZip(stage, zip, cap) {
    Loop Files, stage "\*", "F"
        FileCopy(A_LoopFileFullPath, cap "\" A_LoopFileName, 1)
    FileAppend("zip", zip)
}

LbClean(rig) {
    try DirDelete(rig.dir, 1)
}

LbRead(rig, name) => FileRead(rig.cap "\" name, "UTF-8")

LbLines(text) {
    n := 0
    Loop Parse, text, "`n", "`r"
        if (A_LoopField != "")
            n++
    return n
}

Test_LogBundle_ContentsAndName() {
    rig := LbRig()
    try {
        r := LogBundle.Make(rig.root, rig.opts)
        AssertEq(r.ok, 1, "ok: " r.msg)
        AssertTrue(RegExMatch(r.path, "\\out\\support_\d{8}_\d{6}\.zip$"), "name support_<stamp>.zip in outDir: " r.path)
        AssertTrue(FileExist(r.path) != "", "the zip exists")
        for f in ["macro.log", "settings.ini", "setup_check.txt", "about.txt"]
            AssertTrue(FileExist(rig.cap "\" f) != "", "contains " f)
        about := LbRead(rig, "about.txt")
        AssertTrue(InStr(about, Brand.Version), "about has the version")
        AssertTrue(InStr(about, A_AhkVersion), "about has the AutoHotkey version")
        AssertTrue(InStr(about, A_OSVersion), "about has the Windows version")
        AssertTrue(InStr(about, A_ScreenWidth "x" A_ScreenHeight), "about has the screen size")
        AssertTrue(!InStr(about, rig.user), "about has no user name")
        AssertTrue(InStr(LbRead(rig, "setup_check.txt"), "not run"), "setup_check placeholder without a report")
        ; no leftovers in the temp folder
        left := 0
        Loop Files, rig.temp "\vesper_support_*", "D"
            left++
        AssertEq(left, 0, "staging folder removed")
    } finally {
        LbClean(rig)
    }
}

Test_LogBundle_ReportIncluded() {
    rig := LbRig()
    try {
        opts := rig.opts
        opts["report"] := "Setup check: 8 ok, 1 warning, 0 problems`r`n[WARN] X: y"
        AssertEq(LogBundle.Make(rig.root, opts).ok, 1, "made")
        AssertTrue(InStr(LbRead(rig, "setup_check.txt"), "8 ok, 1 warning"), "report text is in setup_check.txt")
    } finally {
        LbClean(rig)
    }
}

Test_LogBundle_LogTailAndScrub() {
    rig := LbRig(5000)
    try {
        AssertEq(LogBundle.Make(rig.root, rig.opts).ok, 1, "made")
        log := LbRead(rig, "macro.log")
        AssertEq(LbLines(log), 4000, "last 4000 lines")
        AssertTrue(InStr(log, "line 5000") && !InStr(log, "line 1`r") && !InStr(log, "line 1`n"), "the tail, not the head")
        AssertTrue(!InStr(log, "ZzYyXxToken") && !InStr(log, "discord.com/api"), "webhook scrubbed")
        AssertTrue(!InStr(log, "LBCODE777") && !InStr(log, "roblox.com/games"), "link scrubbed")
        AssertTrue(!InStr(log, LbSecretValue()), "a settings secret is scrubbed from the log too")
        AssertTrue(!InStr(log, "Zephyrine"), "user name gone")
        AssertTrue(InStr(log, "C:\Users\<user>\AppData"), "path keeps its shape")
    } finally {
        LbClean(rig)
    }
}

Test_LogBundle_SettingsScrubbed() {
    rig := LbRig()
    try {
        AssertEq(LogBundle.Make(rig.root, rig.opts).ok, 1, "made")
        ini := LbRead(rig, "settings.ini")
        AssertTrue(!InStr(ini, "LBCODE777") && !InStr(ini, "roblox.com"), "private server blanked")
        AssertTrue(!InStr(ini, "ZzYyXxToken") && !InStr(ini, "discord"), "webhook url blanked")
        AssertTrue(!InStr(ini, "1234567"), "mention blanked")
        AssertTrue(!InStr(ini, LbSecretValue()), "remote pin and token blanked")
        AssertTrue(!InStr(ini, "Zephyrine"), "user name gone")
        AssertTrue(InStr(ini, "C:\Users\<user>\Documents"), "paths keep their shape")
        AssertTrue(InStr(ini, "privateServer=[hidden]"), "a set secret shows as [hidden]")
        AssertTrue(InStr(ini, "empty_token=`r`n"), "an empty secret stays empty")
        AssertTrue(InStr(ini, "sellEvery=15") && InStr(ini, "hotkeys=F1,F2"), "ordinary settings kept")
        AssertTrue(InStr(ini, "[Remote]") && InStr(ini, "enabled=1") && InStr(ini, "port=8080"), "Remote enabled/port kept")
        AssertTrue(InStr(ini, "name=Main"), "webhook name kept")
        ; the user's own settings.ini is untouched
        AssertTrue(InStr(FileRead(rig.root "\settings.ini", "UTF-8"), "LBCODE777"), "the original file is not modified")
    } finally {
        LbClean(rig)
    }
}

Test_LogBundle_ScrubHelpers() {
    s := LogBundle.ScrubText("C:\Users\Zephyrine\x and D:\OneDrive\Zephyrine\y", "", "Zephyrine")
    AssertEq(s, "C:\Users\<user>\x and D:\OneDrive\<user>\y", "user name in any path")
    AssertEq(LogBundle.ScrubText("Zephyrines are fine", "", "Zephyrine"), "Zephyrines are fine", "whole words only")
    AssertEq(LogBundle.ScrubText("a.b c", "", "a.b"), "<user> c", "user name is matched literally")
    AssertEq(LogBundle.ScrubText("hello", "", "ab"), "hello", "too-short names are left alone")
    AssertEq(LogBundle.IniSecrets("[Webhook.1]`r`nurl=https://x.example/abcdef`r`nname=Main`r`n[Remote]`r`ntoken=abcd1234").Length, 2, "two secrets found")
}

Test_LogBundle_Screenshots() {
    rig := LbRig()
    try {
        now := A_Now
        names := []
        Loop 7 {
            n := "vesper_shot_" Format("{:02}", A_Index) ".png"
            FileAppend("png" A_Index, rig.temp "\" n)
            FileSetTime(DateAdd(now, -A_Index * 60, "Minutes"), rig.temp "\" n, "M")    ; 1..7 hours old
            names.Push(n)
        }
        FileAppend("old", rig.temp "\vesper_shot_old.png")
        FileSetTime(DateAdd(now, -30, "Hours"), rig.temp "\vesper_shot_old.png", "M")    ; older than 24 h
        FileAppend("x", rig.temp "\other_shot.png")
        AssertEq(LogBundle.Make(rig.root, rig.opts).ok, 1, "made")
        got := []
        Loop Files, rig.cap "\vesper_shot_*.png"
            got.Push(A_LoopFileName)
        AssertEq(got.Length, 5, "newest five only")
        for n in [1, 2, 3, 4, 5]
            AssertTrue(FileExist(rig.cap "\" names[n]) != "", "has the " n ". newest")
        AssertTrue(!FileExist(rig.cap "\" names[6]) && !FileExist(rig.cap "\" names[7]), "not the older ones")
        AssertTrue(!FileExist(rig.cap "\vesper_shot_old.png"), "nothing older than 24 h")
        AssertTrue(!FileExist(rig.cap "\other_shot.png"), "only vesper_shot_*.png")
    } finally {
        LbClean(rig)
    }
}

Test_LogBundle_OnlyOldShots() {
    rig := LbRig()
    try {
        FileAppend("old", rig.temp "\vesper_shot_old.png")
        FileSetTime(DateAdd(A_Now, -48, "Hours"), rig.temp "\vesper_shot_old.png", "M")
        AssertEq(LogBundle.Make(rig.root, rig.opts).ok, 1, "made without screenshots")
        AssertTrue(!FileExist(rig.cap "\vesper_shot_old.png"), "old one left out")
    } finally {
        LbClean(rig)
    }
}

Test_LogBundle_MissingFilesStillMakeAZip() {
    rig := LbRig()
    try {
        FileDelete(rig.root "\logs\macro.log")
        FileDelete(rig.root "\settings.ini")
        r := LogBundle.Make(rig.root, rig.opts)
        AssertEq(r.ok, 1, "made: " r.msg)
        AssertTrue(InStr(LbRead(rig, "macro.log"), "no macro.log"), "says there is no log")
        AssertTrue(InStr(LbRead(rig, "settings.ini"), "no settings.ini"), "says there is no settings file")
    } finally {
        LbClean(rig)
    }
}

Test_LogBundle_SameSecondGetsAUniqueName() {
    rig := LbRig()
    try {
        opts := rig.opts
        opts["now"] := "20261112101500"
        a := LogBundle.Make(rig.root, opts)
        b := LogBundle.Make(rig.root, opts)
        AssertEq(a.ok, 1, "first")
        AssertEq(b.ok, 1, "second")
        AssertTrue(InStr(a.path, "support_20261112_101500.zip"), "stamp from opts.now: " a.path)
        AssertTrue(a.path != b.path, "no overwrite")
    } finally {
        LbClean(rig)
    }
}

Test_LogBundle_NeverThrows() {
    r := LogBundle.Make("")
    AssertEq(r.ok, 0, "empty root")
    AssertTrue(r.msg != "", "has a message")
    rig := LbRig()
    try {
        opts := rig.opts
        opts["zip"] := (stage, zip) => LbThrowZip()
        r := LogBundle.Make(rig.root, opts)
        AssertEq(r.ok, 0, "a failing zip step is ok 0")
        AssertTrue(InStr(r.msg, "could not"), "plain message: " r.msg)
        AssertTrue(!InStr(r.msg, "ZzYyXxToken"), "message holds no secrets")
        left := 0
        Loop Files, rig.temp "\vesper_support_*", "D"
            left++
        AssertEq(left, 0, "staging folder removed after a failure")
        ; a zip step that makes nothing
        opts["zip"] := (stage, zip) => 0
        AssertEq(LogBundle.Make(rig.root, opts).ok, 0, "no zip made is ok 0")
        ; an output folder that cannot exist
        opts2 := Map("tempDir", rig.temp, "outDir", rig.root "\settings.ini\sub")
        AssertEq(LogBundle.Make(rig.root, opts2).ok, 0, "bad outDir is ok 0")
    } finally {
        LbClean(rig)
    }
}

LbThrowZip() {
    throw Error("boom " LbHook())
}

Test_LogBundle_RealZip() {
    rig := LbRig()
    try {
        opts := Map("tempDir", rig.temp, "outDir", rig.dir "\out", "userName", rig.user)    ; the real zip step
        r := LogBundle.Make(rig.root, opts)
        AssertEq(r.ok, 1, "real zip made: " r.msg)
        AssertTrue(FileExist(r.path) != "" && FileGetSize(r.path) > 100, "the zip has content")
        dest := rig.dir "\unz"
        q := (s) => "'" StrReplace(s, "'", "''") "'"
        rc := RunWait('powershell.exe -NoProfile -NonInteractive -Command "Expand-Archive -LiteralPath ' q(r.path)
            . ' -DestinationPath ' q(dest) ' -Force"', , "Hide")
        AssertEq(rc, 0, "the zip opens")
        for f in ["macro.log", "settings.ini", "setup_check.txt", "about.txt"]
            AssertTrue(FileExist(dest "\" f) != "", "zip holds " f)
        AssertTrue(!InStr(FileRead(dest "\settings.ini", "UTF-8"), "LBCODE777"), "zipped settings scrubbed")
    } finally {
        LbClean(rig)
    }
}
