#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\Brand.ahk
#Include %A_LineFile%\..\ui\UiLogic.ahk
; ---------------------------------------------------------------------------
; LogBundle: the "Send my log" button. Packs what a helper needs to see into
; one zip, with every secret and personal detail removed first.
;
;   LogBundle.Make(root, opts := "") -> {ok, path, msg}
;     root   program folder (holds settings.ini and logs\)
;     Writes <outDir>\support_<yyyyMMdd_HHmmss>.zip (outDir = <root>\logs):
;       macro.log        the last 4000 lines of <root>\logs\macro.log, scrubbed
;       settings.ini     SCRUBBED: see below
;       vesper_shot_*.png  the newest (up to 5) screenshots in A_Temp written
;                        in the last 24 h
;       setup_check.txt  opts.report (the SetupCheck report), if given
;       about.txt        version, AutoHotkey, Windows, screen size
;     ok = 1: path = the zip, msg = a sentence for the user. ok = 0: msg says
;     why. NEVER throws.
;     opts (Map or object, all optional; tests use them):
;       logPath, settingsPath, tempDir, outDir   override the folders
;       report     text for setup_check.txt
;       userName   the Windows user name to hide (default A_UserName)
;       now        "yyyyMMddHHmmss" timestamp (default A_Now)
;       zip        callable (stageDir, zipFile) that makes the zip
;                  (default: PowerShell Compress-Archive)
;
;   Scrubbing (LogBundle.ScrubText / ScrubIni, both pure):
;     UiLogic.Scrub: Discord webhook URLs, roblox.com / ro.blox.com links,
;       private server codes, C:\Users\<name>\ -> C:\Users\<user>\ ; plus
;       every secret value found in settings.ini, plus the user name itself.
;     settings.ini: the value of every key named like privateServer, token,
;       webhook, url, secret, password, auth, cookie, link or mention, and of
;       every key in a [Remote*] section except enabled/port, becomes
;       "[hidden]" (blank stays blank); the other values go through the same
;       text scrub.
; ---------------------------------------------------------------------------

class LogBundle {
    static MaxLogLines := 4000
    static MaxShots := 5
    static ShotHours := 24
    static SecretKeyRe := "i)private|token|webhook|url|secret|passw|pass$|apikey|api_key|auth|cookie|link|mention"
    static RemoteOpenRe := "i)^(enabled|port|poll\w*|interval\w*)$"

    static Make(root, opts := "") {
        try {
            return LogBundle._Make(root, opts)
        } catch Any as e {
            msg := "could not make the support file"
            try msg .= ": " UiLogic.Scrub(e is Error ? e.Message : String(e))
            return {ok: 0, path: "", msg: msg}
        }
    }

    ; ---- pure scrubbers ---------------------------------------------------

    ; One piece of text: UiLogic.Scrub, the extra secrets, then the user name.
    static ScrubText(text, secrets := "", userName := "") {
        s := UiLogic.Scrub(text, secrets, true)
        ; Discord user / channel ids (17-20 digits; Remote logs who wrote)
        s := RegExReplace(s, "(?<!\d)\d{17,20}(?!\d)", "[id]")
        userName := Trim(String(userName))
        if (StrLen(userName) >= 3)
            s := RegExReplace(s, "i)(?<![\w])" LogBundle._Esc(userName) "(?![\w])", "<user>")
        return s
    }

    static _Esc(s) => RegExReplace(s, "[\\.*?+\[\](){}|^$]", "\$0")

    ; -> true when a settings.ini key (in that section) holds a secret
    static _SecretKey(section, key) {
        if RegExMatch(section, "i)^remote")
            return !RegExMatch(key, LogBundle.RemoteOpenRe)
        return RegExMatch(key, LogBundle.SecretKeyRe) ? true : false
    }

    ; Array of the secret values of an ini text (for scrubbing other files).
    static IniSecrets(text) {
        out := []
        sec := ""
        for line in StrSplit(StrReplace(String(text), "`r", ""), "`n") {
            line := Trim(line)
            if RegExMatch(line, "^\[(.*)\]$", &m) {
                sec := m[1]
                continue
            }
            p := InStr(line, "=")
            if (SubStr(line, 1, 1) = ";" || p < 2)
                continue
            if (LogBundle._SecretKey(sec, Trim(SubStr(line, 1, p - 1)))) {
                v := Trim(SubStr(line, p + 1))
                if (StrLen(v) >= 4)
                    out.Push(v)
            }
        }
        return out
    }

    static ScrubIni(text, userName := "") {
        secrets := LogBundle.IniSecrets(text)
        sec := ""
        out := ""
        for line in StrSplit(StrReplace(String(text), "`r", ""), "`n") {
            t := Trim(line)
            if RegExMatch(t, "^\[(.*)\]$", &m)
                sec := m[1]
            else if (SubStr(t, 1, 1) != ";" && (p := InStr(line, "=")) > 1) {
                key := Trim(SubStr(line, 1, p - 1))
                val := Trim(SubStr(line, p + 1))
                if LogBundle._SecretKey(sec, key)
                    line := SubStr(line, 1, p) . (val = "" ? "" : "[hidden]")
                else
                    line := SubStr(line, 1, p) LogBundle.ScrubText(val, secrets, userName)
                out .= line "`r`n"
                continue
            }
            out .= LogBundle.ScrubText(line, secrets, userName) "`r`n"
        }
        return RTrim(out, "`r`n") "`r`n"
    }

    ; The last n lines of a text, each scrubbed.
    static TailScrubbed(text, n, secrets := "", userName := "") {
        lines := StrSplit(StrReplace(String(text), "`r", ""), "`n")
        if (lines.Length > 0 && lines[lines.Length] = "")
            lines.Pop()
        first := Max(1, lines.Length - n + 1)
        out := ""
        i := first
        while (i <= lines.Length) {
            out .= LogBundle.ScrubText(lines[i], secrets, userName) "`r`n"
            i++
        }
        return out
    }

    ; ---- the bundle -----------------------------------------------------------

    static _Make(root, opts) {
        root := RTrim(String(root), "\/")
        if (root = "")
            return {ok: 0, path: "", msg: "no program folder given"}
        o := (key, def) => LogBundle._Opt(opts, key, def)
        logPath := o("logPath", root "\logs\macro.log")
        iniPath := o("settingsPath", root "\settings.ini")
        tempDir := RTrim(o("tempDir", A_Temp), "\/")
        outDir := RTrim(o("outDir", root "\logs"), "\/")
        user := o("userName", A_UserName)
        now := o("now", A_Now)
        zipFn := o("zip", "")
        if !IsObject(zipFn)
            zipFn := (stage, zip) => LogBundle._Zip(stage, zip)
        stamp := FormatTime(now, "yyyyMMdd_HHmmss")

        if !DirExist(outDir)
            DirCreate(outDir)
        zip := outDir "\support_" stamp ".zip"
        n := 1
        while FileExist(zip)
            zip := outDir "\support_" stamp "_" (++n) ".zip"

        stage := tempDir "\vesper_support_" stamp "_" A_TickCount
        DirCreate(stage)
        try {
            ; settings first: its secrets are also removed from the log
            secrets := []
            iniText := ""
            if FileExist(iniPath) {
                try iniText := FileRead(iniPath, "UTF-8")
                secrets := LogBundle.IniSecrets(iniText)
            }
            LogBundle._Put(stage "\settings.ini", iniText != "" ? LogBundle.ScrubIni(iniText, user) : "(no settings.ini found)`r`n")

            logText := ""
            if FileExist(logPath)
                try logText := FileRead(logPath, "UTF-8")
            LogBundle._Put(stage "\macro.log", logText != "" ? LogBundle.TailScrubbed(logText, LogBundle.MaxLogLines, secrets, user)
                : "(no macro.log found)`r`n")

            ; screenshots can show the Roblox name, players and chat: only
            ; when the user ticks them (privacy review 2026-11-12)
            if o("shots", false) {
                shots := LogBundle._Shots(tempDir, now)
                for s in shots
                    FileCopy(s, stage "\" LogBundle._Base(s), 1)
            }

            report := String(o("report", ""))
            LogBundle._Put(stage "\setup_check.txt", report != "" ? LogBundle.ScrubText(report, secrets, user)
                : "(the setup check was not run)`r`n")
            LogBundle._Put(stage "\about.txt", LogBundle._About())

            zipFn(stage, zip)
            if !FileExist(zip)
                return {ok: 0, path: "", msg: "could not make the support file (the zip was not created)"}
        } finally {
            try DirDelete(stage, 1)
        }
        return {ok: 1, path: zip, msg: "Saved " zip}
    }

    static _Opt(opts, key, def) {
        if (opts is Map)
            return opts.Has(key) ? opts[key] : def
        if (IsObject(opts) && HasProp(opts, key))
            return opts.%key%
        return def
    }

    static _Base(path) => RegExReplace(path, "^.*[\\/]")

    static _Put(path, text) {
        f := FileOpen(path, "w", "UTF-8")
        f.Write(text)
        f.Close()
    }

    ; The newest MaxShots vesper_shot_*.png written within ShotHours of now.
    static _Shots(dir, now) {
        cutoff := DateAdd(now, -LogBundle.ShotHours, "Hours")
        found := []
        Loop Files, dir "\vesper_shot_*.png" {
            t := A_LoopFileTimeModified
            if (t >= cutoff)
                found.Push([t, A_LoopFileFullPath])
        }
        ; newest first (insertion sort: a handful of files)
        i := 2
        while (i <= found.Length) {
            x := found[i], j := i - 1
            while (j >= 1 && found[j][1] < x[1]) {
                found[j + 1] := found[j]
                j--
            }
            found[j + 1] := x
            i++
        }
        out := []
        for f in found {
            if (out.Length >= LogBundle.MaxShots)
                break
            out.Push(f[2])
        }
        return out
    }

    static _About() {
        return Brand.Name " " Brand.Version "`r`n"
            . "AutoHotkey " A_AhkVersion "`r`n"
            . "Windows " A_OSVersion . (A_Is64bitOS ? " (64-bit)" : "") . "`r`n"
            . "Screen " A_ScreenWidth "x" A_ScreenHeight "`r`n"
            . "Made " FormatTime(, "yyyy-MM-dd HH:mm:ss") "`r`n"
    }

    ; PowerShell Compress-Archive, like Updater._Unzip uses Expand-Archive.
    static _Zip(stage, zip) {
        q := (s) => "'" StrReplace(s, "'", "''") "'"
        cmd := 'powershell.exe -NoProfile -NonInteractive -Command "Compress-Archive -Path ' q(stage "\*")
            . ' -DestinationPath ' q(zip) ' -Force"'
        if (RunWait(cmd, , "Hide") != 0)
            throw Error("could not zip the files")
    }
}
