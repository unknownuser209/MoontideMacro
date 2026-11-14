#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\Screen.ahk
#Include %A_LineFile%\..\Roblox.ahk
#Include %A_LineFile%\..\LogWatch.ahk
#Include %A_LineFile%\..\Calibrate.ahk
#Include %A_LineFile%\..\Ocr.ahk
#Include %A_LineFile%\..\ui\UiLogic.ahk
#Include %A_LineFile%\..\tasks\Recovery.ahk
; ---------------------------------------------------------------------------
; SetupCheck: the "Check my setup" button. Plain-English checks of everything
; the macro needs from the PC. Reads only; it never sends a key or a click.
;
;   SetupCheck.Run(cfg, probes := "") -> Array of
;       {id, name, level: "ok"|"warn"|"fail"|"info", detail, fix}
;     cfg     the Config (General.privateServer, Webhooks(), the feature
;             switches); "" is allowed (everything unset).
;     probes  optional Map of callables; EVERY system call goes through one,
;             so tests run offline. Keys (defaults use the real functions):
;       hwnd ()            Roblox window id or 0          (Roblox.Hwnd)
;       clientOk ()        "ok" | "missing" | "notfs"     (Roblox.ClientOk)
;       sizeText ()        "1920x1080"                    (Screen.SizeText)
;       verified ()        size was tested in game        (Screen.Verified)
;       scale ()           Windows display scale, percent (Screen.ScaleAt)
;       hdr ()             1 on, 0 off, "" unknown        (Screen.HdrOn)
;       logAge ()          seconds since the newest Roblox log was written,
;                          "" = no log found  (LogWatch folder, PickLog)
;       privateOk (link)   the link looks right           (RecoveryTask.LinkOk)
;       calMissing ()      Array of calibration step ids not recorded yet
;       procs (name)       a process with that name runs  (ProcessExist)
;       ahkVersion ()      A_AhkVersion
;       front ()           Roblox is the foreground window
;       rollText ()        OCR text of the Roll button box (design px
;                          1160,1290,240,70), read only when Roblox is in front
;     A probe that throws gives an "info" row ("could not check"), never an error.
;   SetupCheck.Summary(results) -> "8 ok, 1 warning, 0 problems"
;   SetupCheck.Report(results)  -> plain text block (for the support zip)
;
; SECRETS: the private server link and the webhook URLs are only counted /
; tested, never printed.
; ---------------------------------------------------------------------------

class SetupCheck {
    ; Programs that pull focus away from Roblox mid-run (the macro pauses when
    ; Roblox loses focus). First entry: Microsoft PC Manager's floating toolbar
    ; took focus 1.5 s after F1 in a live test.
    static FocusStealers := ["MSPCManager.exe"]
    static StealerText := Map("mspcmanager.exe", "Microsoft PC Manager's toolbar can pull focus away from Roblox; close it or turn its toolbar off")
    static MinAhk := "2.0.10"
    static LogFreshSec := 1800         ; Roblox open and no log line this long = stalled
    static RollBox := {x: 1160, y: 1290, w: 240, h: 70}
    static RollRe := "i)\broll\b"

    ; calibration step id prefix -> [config key, default] pairs: the step is
    ; needed when ANY of them is on. Prefixes not listed here are only counted.
    static CalNeeds := [
        ["fisher_", [["Craft.enabled", 1]]],
        ["cauldron_", [["Craft.enabled", 1]]],
        ["stella_", [["Craft.enabled", 1]]],
        ["notify_rect", [["Craft.enabled", 1], ["quests.enabled", 1]]],
        ["quest_", [["quests.enabled", 1]]],
        ["selector_", [["BiomeItems.enabled", 0]]],
        ["buff_expand", [["Obby.enabled", 0]]],
        ["obby_", [["Obby.enabled", 0]]]]
    ; recorded when the user wants them, never needed (the tasks work without)
    static CalOptional := ["cauldron_result_2", "fisher_leave", "fisher_shop_close", "stella_dialog", "daily_claim", "daily_close"]

    static Run(cfg, probes := "") {
        out := []
        P := (key) => (probes is Map && probes.Has(key)) ? probes[key] : ""
        add := (id, name, level, detail, fix := "") => out.Push({id: id, name: name, level: level, detail: detail, fix: fix})
        ; call a probe (own or default); -> {ok, v}
        call := (key, def, args*) => SetupCheck._Call(P(key), def, args*)

        ; ---- Roblox window, size ------------------------------------------
        h := call("hwnd", () => Roblox.Hwnd())
        open := h.ok && h.v ? true : false
        if !h.ok
            add("roblox", "Roblox is open", "info", "could not look for the Roblox window")
        else if !open
            add("roblox", "Roblox is open", "warn", "Roblox is not running", "Open Roblox and join your server before you press F1")
        else
            add("roblox", "Roblox is open", "ok", "the Roblox window was found")

        if !open {
            add("size", "Roblox screen size", "info", "skipped: Roblox is not open")
        } else {
            c := call("clientOk", () => Roblox.ClientOk())
            st := call("sizeText", () => Screen.SizeText())
            vf := call("verified", () => Screen.Verified())
            sz := st.ok ? st.v : "unknown size"
            if !c.ok
                add("size", "Roblox screen size", "info", "could not read the Roblox window size")
            else if (c.v = "notfs")
                add("size", "Roblox screen size", "fail", "Roblox is in a window, not fullscreen (the macro needs fullscreen)", "Press F11 in Roblox (or Alt+Enter) to go fullscreen")
            else if (c.v != "ok")
                add("size", "Roblox screen size", "info", "skipped: Roblox is not open")
            else if (vf.ok && vf.v)
                add("size", "Roblox screen size", "ok", "fullscreen at " sz ", a size the macro was tested at")
            else
                add("size", "Roblox screen size", "warn", "fullscreen at " sz ": " Screen.NotTestedNote
                    , "If something misbehaves, switch Windows to one of: " Screen.TestedText())
        }

        ; ---- Windows scale, HDR -------------------------------------------
        sc := call("scale", () => Screen.ScaleAt())
        if !sc.ok || !IsNumber(sc.v)
            add("scale", "Windows display scale", "info", "could not read the display scale")
        else
            add("scale", "Windows display scale", "ok", "Windows display scale is " Round(sc.v) "%")
        hd := call("hdr", () => Screen.HdrOn())
        if (!hd.ok || hd.v = "")
            add("hdr", "HDR", "info", "could not tell whether HDR is on")
        else if (hd.v = 1)
            add("hdr", "HDR", "info", "HDR is on: this works on most PCs", "If fishing or Memory Match misbehave, try turning HDR off in Windows display settings")
        else
            add("hdr", "HDR", "ok", "HDR is off")

        ; ---- Roblox logs --------------------------------------------------
        la := call("logAge", () => SetupCheck._LogAge())
        if !la.ok
            add("logs", "Roblox logs", "info", "could not read the Roblox log folder")
        else if (la.v = "")
            add("logs", "Roblox logs", "warn", "no Roblox log was found (the macro reads biome and aura changes from it)"
                , "Start Roblox once, then check again. Logs live in %LOCALAPPDATA%\Roblox\logs")
        else if (open && IsNumber(la.v) && la.v > SetupCheck.LogFreshSec)
            add("logs", "Roblox logs", "warn", "the newest Roblox log was last written " SetupCheck._Ago(la.v) " ago while Roblox is open"
                , "Restart Roblox so it writes a fresh log")
        else if open
            add("logs", "Roblox logs", "ok", "the Roblox log is readable and recent (" SetupCheck._Ago(la.v) " ago)")
        else
            add("logs", "Roblox logs", "ok", "a Roblox log was found (last written " SetupCheck._Ago(la.v) " ago)")

        ; ---- private server link (never printed) ---------------------------
        link := IsObject(cfg) ? Trim(String(cfg.Get("General.privateServer", ""))) : ""
        if (link = "") {
            add("private", "Private server link", "warn", "no private server link is set, so auto-rejoin cannot work"
                , "Paste your private server link in Settings (General)")
        } else {
            po := call("privateOk", (l) => RecoveryTask.LinkOk(l), link)
            if (po.ok && !po.v)
                add("private", "Private server link", "warn", "a private server link is set, but it does not look like a roblox.com link"
                    , "Copy the link again from your private server's page on roblox.com")
            else
                add("private", "Private server link", "ok", "a private server link is set")
        }

        ; ---- Discord webhooks (never printed) ------------------------------
        hooks := []
        try hooks := cfg.Webhooks()
        total := 0, good := 0
        if (hooks is Array) {
            for w in hooks {
                if !(w is Map) || !w.Has("enabled") || !w["enabled"]
                    continue
                total++
                if UiLogic.IsWebhookUrl(w.Has("url") ? w["url"] : "")
                    good++
            }
        }
        if (total = 0)
            add("webhooks", "Discord webhooks", "info", "no Discord webhook is turned on (optional: it sends you updates)")
        else if (good < total)
            add("webhooks", "Discord webhooks", "warn", good " of " total " enabled webhooks have a valid-looking address"
                , "Open Settings and paste the webhook address again (Discord: channel settings, Integrations, Webhooks)")
        else
            add("webhooks", "Discord webhooks", "ok", good . (good = 1 ? " webhook is" : " webhooks are") . " turned on with a valid-looking address")

        ; ---- calibration ----------------------------------------------------
        cm := call("calMissing", () => SetupCheck._CalMissing())
        if !cm.ok || !(cm.v is Array)
            add("calibration", "Calibration", "info", "could not read the calibration")
        else
            SetupCheck._CalRow(cfg, cm.v, add)

        ; ---- focus stealers --------------------------------------------------
        found := []
        for n in SetupCheck.FocusStealers {
            r := call("procs", (nm) => ProcessExist(nm) ? true : false, n)
            if (r.ok && r.v)
                found.Push(n)
        }
        if (found.Length = 0) {
            add("focus", "Apps that steal focus", "ok", "none of the known focus-stealing apps are running")
        } else {
            det := ""
            for n in found {
                k := StrLower(n)
                txt := SetupCheck.StealerText.Has(k) ? SetupCheck.StealerText[k] : n " can pull focus away from Roblox; close it"
                det .= (det = "" ? "" : "; ") . txt
            }
            add("focus", "Apps that steal focus", "warn", det, "Close it before you press F1; the macro pauses when Roblox loses focus")
        }

        ; ---- AutoHotkey --------------------------------------------------------
        av := call("ahkVersion", () => A_AhkVersion)
        if (!av.ok || av.v = "")
            add("ahk", "AutoHotkey version", "info", "could not read the AutoHotkey version")
        else if (VerCompare(av.v, SetupCheck.MinAhk) >= 0)
            add("ahk", "AutoHotkey version", "ok", "AutoHotkey " av.v)
        else
            add("ahk", "AutoHotkey version", "fail", "AutoHotkey " av.v " is too old (needs " SetupCheck.MinAhk " or newer)"
                , "Install the latest AutoHotkey v2 from autohotkey.com")

        ; ---- live read ----------------------------------------------------------
        fr := call("front", () => WinActive("ahk_exe " Roblox.Exe) ? 1 : 0)
        if !(open && fr.ok && fr.v) {
            add("live", "Reading your screen", "info", "skipped: Roblox is not in front (click Roblox, then check again)")
        } else {
            rt := call("rollText", () => SetupCheck._ReadRoll())
            if !rt.ok
                add("live", "Reading your screen", "info", "could not try reading the screen")
            else if RegExMatch(String(rt.v), SetupCheck.RollRe)
                add("live", "Reading your screen", "ok", "the macro can read your screen (it read the Roll button)")
            else
                add("live", "Reading your screen", "warn", "the macro could not read the Roll button on your screen"
                    , "Close anything covering the game, and check HDR, the Windows scale and that Roblox is fullscreen")
        }
        return out
    }

    static Summary(results) {
        ok := 0, warn := 0, fail := 0
        for r in results {
            if (r.level = "ok")
                ok++
            else if (r.level = "warn")
                warn++
            else if (r.level = "fail")
                fail++
        }
        return ok . " ok, " . warn . (warn = 1 ? " warning, " : " warnings, ") . fail . (fail = 1 ? " problem" : " problems")
    }

    static Report(results) {
        tag := Map("ok", "[ OK ]", "warn", "[WARN]", "fail", "[FAIL]", "info", "[INFO]")
        s := "Setup check: " SetupCheck.Summary(results) "`r`n`r`n"
        for r in results {
            s .= (tag.Has(r.level) ? tag[r.level] : "[ ?? ]") " " r.name ": " r.detail "`r`n"
            if (r.level != "ok" && r.fix != "")
                s .= "        What to do: " r.fix "`r`n"
        }
        return s
    }

    ; ---- helpers --------------------------------------------------------------

    ; -> {ok, v}; a missing probe uses def; a throwing probe gives ok false.
    static _Call(fn, def, args*) {
        try {
            return {ok: true, v: IsObject(fn) ? fn(args*) : def(args*)}
        } catch Any {
            return {ok: false, v: ""}
        }
    }

    static _Ago(sec) {
        sec := Round(sec)
        return sec < 90 ? sec " s" : sec < 5400 ? Round(sec / 60) " min" : Round(sec / 3600, 1) " h"
    }

    ; seconds since the newest Roblox *_Player_* log was written, "" = none
    static _LogAge() {
        dir := EnvGet("LOCALAPPDATA") "\Roblox\logs"
        p := LogWatch.PickLog(dir)
        if (p = "")
            return ""
        return Max(0, DateDiff(A_Now, FileGetTime(p, "M"), "Seconds"))
    }

    ; calibration step ids that have no recording
    static _CalMissing() {
        miss := []
        for st in Calibrate.Steps() {
            id := st["id"]
            if !(IsObject(Calibrate.Point(id)) || IsObject(Calibrate.Rect(id)) || IsObject(Calibrate.Sig(id)))
                miss.Push(id)
        }
        return miss
    }

    ; the Roll button box, as the tasks read it (design px; Screen maps it)
    static _ReadRoll() {
        if (Roblox.ClientOk() != "ok")
            return ""
        b := SetupCheck.RollBox
        return Ocr.Read(b.x, b.y, b.w, b.h, 1)
    }

    static _CalRow(cfg, missing, add) {
        if (missing.Length = 0) {
            add("calibration", "Calibration", "ok", "every calibration point is recorded")
            return
        }
        needed := [], other := 0
        for id in missing {
            if SetupCheck._CalNeeded(cfg, id)
                needed.Push(id)
            else
                other++
        }
        if (needed.Length > 0) {
            list := ""
            for id in needed {
                if (A_Index > 4) {
                    list .= ", +" (needed.Length - 4) " more"
                    break
                }
                list .= (list = "" ? "" : ", ") id
            }
            add("calibration", "Calibration", "warn", needed.Length " calibration point" (needed.Length = 1 ? "" : "s")
                " needed by the features you turned on " (needed.Length = 1 ? "is" : "are") " missing (" list ")"
                , "Open the Calibrate page and record the missing points, or load the preset for your screen size")
        } else {
            add("calibration", "Calibration", "info", other " calibration point" (other = 1 ? " is" : "s are")
                " not recorded; none is needed by the features you turned on")
        }
    }

    ; the step is needed by a feature that is switched on
    static _CalNeeded(cfg, id) {
        for o in SetupCheck.CalOptional {
            if (o = id)
                return false
        }
        for row in SetupCheck.CalNeeds {
            p := row[1]
            if (SubStr(id, 1, StrLen(p)) != p)
                continue
            for kv in row[2] {
                v := kv[2]
                try v := cfg.Get(kv[1], kv[2])
                if v
                    return true
            }
            return false
        }
        return false
    }
}
