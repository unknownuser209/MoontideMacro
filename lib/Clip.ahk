#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\Input.ahk
#Include %A_LineFile%\..\tasks\Potions.ahk
#Include %A_LineFile%\..\RouteRecorder.ahk
#Include %A_LineFile%\..\Auras.ahk
; ---------------------------------------------------------------------------
; Clip: Medal.tv clip trigger (spec 4.6b). Static; configure once with Setup.
;
;   Clip.Setup(cfg, wh := "", logFn := "", opts := "")
;     cfg    Config ([Medal] enabled, clipHotkey, delaySec, cooldownSec, auras)
;     wh     object with Send(event, title, desc, color, opts) (Webhook)
;     logFn  callable(text)
;     opts   Map (all optional, tests inject):
;              procFn(name) -> pid/0   default ProcessExist
;              clockFn() -> ms         default A_TickCount
;              timerFn(fn, ms)         default one-shot SetTimer(fn, -ms)
;              io                      Input backend (default real input)
;              stopFn() -> bool        optional; true = macro stopped, a
;                                      scheduled clip is dropped at fire time
;   Clip.Trigger(reason) -> "scheduled" | "disabled" | "no_medal" | "cooldown"
;                           | "bad_hotkey"
;     reason "rare" or "aura:<name>". Reason class = text before ":"; one
;     cooldown (cooldownSec, default 30) per class. Non-blocking: the hotkey
;     is tapped delaySec (default 3) later from a one-shot timer, and only if
;     medal.exe is still running then. The cooldown starts when a clip is
;     scheduled; skipped triggers (Medal missing etc.) do not consume it.
;     Medal missing: logged once (re-armed when Medal is seen again), skipped.
;     After the tap a `clips` webhook notes the clip; for "aura:<name>" it
;     states the aura, its 1-in-N rarity + class and why it clipped
;     (Auras.Describe; the decision itself is Auras.Decide, called by
;     BiomeEvents).
;   Clip.AuraWanted(name)  name is in [Medal] auras (comma list,
;                          case/space-insensitive)
;   Clip.HotkeyAllowed(k)  one key F4-F24, or a combo of 2-4 keys joined by
;                          "+" ("Alt+9", "Shift+F5+T"; any case, spaces ok):
;                          Ctrl / Alt / Shift, F4-F24, letters and digits,
;                          at least one of them a modifier or an F key (a bare
;                          "T+Y" types into a text box). Never mouse buttons
;                          (a click could land on Use), never F1-F3 (macro
;                          hotkeys, F3 = stop), never Win (Windows shortcuts:
;                          Win+D hides Roblox), never Alt+F4 (closes Roblox),
;                          no key twice. Clip.Keys(k) -> the keys in press
;                          order (modifiers first), "" when not allowed;
;                          Clip.HotkeyText(k) -> "Shift+F5+T".
;   Clip.HotkeyProblem(k, cfg) -> "" or why k cannot be the clip hotkey:
;                          not HotkeyAllowed, or equal to a configured macro
;                          hotkey ([Hotkeys] start / pause / stop), the
;                          ACTUAL calibration capture key ([Calibrate]
;                          captureKey, default F4 = Clip.DefaultCaptureKey,
;                          same as Calibrate.DefaultCaptureKey) or the route
;                          recorder key (F7). F6 is free unless captureKey
;                          is set to F6. Trigger and the dashboard Clips
;                          save both use it.
;   Clip.CancelAll()       drop every scheduled clip. The main loop (Task 14b)
;                          MUST call it on F3 / stop.
;   Clip.Reset()           clear state (tests)
; Busy guard: while PotionsTask.busy is set (a potion is being handled) the
; timer callback does not press anything; it re-arms itself every
; DeferMs (1 s), up to MaxDefers times, then drops the clip.
; [Medal] enabled=0 (the shipped default) -> every Trigger is "disabled".
; ---------------------------------------------------------------------------

class Clip {
    static DefaultDelaySec := 3
    static DefaultCooldownSec := 30
    static DefaultCaptureKey := "F4"   ; must equal Calibrate.DefaultCaptureKey (tested)
    static DeferMs := 1000
    static MaxDefers := 120
    static _gen := 0              ; bumped by CancelAll/Reset; stale timers no-op
    static _stopFn := ""
    static _cfg := ""
    static _wh := ""
    static _logFn := ""
    static _procFn := ""
    static _clockFn := ""
    static _timerFn := ""
    static _io := ""
    static _last := Map()         ; reason class -> ms when last scheduled
    static _warnedMissing := false
    static _warnedKey := false

    static Setup(cfg, wh := "", logFn := "", opts := "") {
        Clip.Reset()
        Clip._cfg := cfg
        Clip._wh := wh
        Clip._logFn := logFn
        o := (opts is Map) ? opts : Map()
        Clip._procFn := o.Has("procFn") ? o["procFn"] : ((name) => ProcessExist(name))
        Clip._clockFn := o.Has("clockFn") ? o["clockFn"] : (() => A_TickCount)
        Clip._timerFn := o.Has("timerFn") ? o["timerFn"] : ((fn, ms) => SetTimer(fn, -Max(1, ms)))
        Clip._io := o.Has("io") ? o["io"] : ""
        Clip._stopFn := o.Has("stopFn") ? o["stopFn"] : ""
    }

    static CancelAll() {
        Clip._gen += 1
    }

    static Reset() {
        Clip._gen += 1
        Clip._stopFn := ""
        Clip._cfg := "", Clip._wh := "", Clip._logFn := ""
        Clip._procFn := "", Clip._clockFn := "", Clip._timerFn := "", Clip._io := ""
        Clip._last := Map()
        Clip._warnedMissing := false
        Clip._warnedKey := false
    }

    static ReasonClass(reason) {
        r := StrLower(Trim(String(reason)))
        p := InStr(r, ":")
        return p ? Trim(SubStr(r, 1, p - 1)) : r
    }

    static Mods := ["Ctrl", "Alt", "Shift"]
    static MaxKeys := 4

    static HotkeyAllowed(k) => IsObject(Clip.Keys(k))

    ; The keys of hotkey k in press order: modifiers first (Ctrl, Alt,
    ; Shift as typed), then the rest as typed; the last one is tapped while
    ; the others are held. Names: "Ctrl", "Alt", "Shift", "F5", "T", "9".
    ; -> Array, or "" when k is not allowed (see HotkeyAllowed).
    static Keys(k) {
        if !(k is String) || Trim(k) = ""
            return ""
        parts := StrSplit(Trim(k), "+", " `t")
        if (parts.Length > Clip.MaxKeys)
            return ""
        mods := [], rest := [], seen := Map()
        for p in parts {
            n := Clip._KeyName(p)
            if (n = "" || seen.Has(n))
                return ""
            seen[n] := true
            (Clip._IsMod(n) ? mods : rest).Push(n)
        }
        if (rest.Length = 0)
            return ""                                   ; modifiers alone
        if (parts.Length = 1)
            return RegExMatch(rest[1], "^F(?:[4-9]|1\d|2[0-4])$") ? rest : ""
        fkey := false
        for n in rest {
            if RegExMatch(n, "^F(?:[1-3])$")
                return ""                               ; macro start / pause / stop
            fkey := fkey || RegExMatch(n, "^F\d+$")
        }
        if (mods.Length = 0 && !fkey)
            return ""                                   ; "T+Y" types into a text box
        if (seen.Has("Alt") && seen.Has("F4"))
            return ""                                   ; Alt+F4 closes Roblox
        for n in rest
            mods.Push(n)
        return mods
    }

    ; "Shift+F5+T" (press order), "" when not allowed.
    static HotkeyText(k) {
        keys := Clip.Keys(k)
        if !IsObject(keys)
            return ""
        s := ""
        for n in keys
            s .= (s = "" ? "" : "+") n
        return s
    }

    ; A typed key -> its name, "" when it is no clip key.
    static _KeyName(p) {
        p := StrLower(Trim(p))
        if (p = "ctrl" || p = "control" || p = "ctl")
            return "Ctrl"
        if (p = "alt")
            return "Alt"
        if (p = "shift")
            return "Shift"
        if RegExMatch(p, "^f([1-9]|1\d|2[0-4])$", &m)
            return "F" m[1]
        if RegExMatch(p, "^[a-z0-9]$")
            return StrUpper(p)
        return ""
    }

    static _IsMod(n) {
        for m in Clip.Mods
            if (m = n)
                return true
        return false
    }

    static HotkeyProblem(k, cfg := "") {
        if !Clip.HotkeyAllowed(k)
            return "clip hotkey '" k "' is not allowed: use one of F4-F24, or a combo like Alt+9 or Shift+F5+T"
        kk := StrUpper(Clip.HotkeyText(k))
        for name, def in Map("start", "F1", "pause", "F2", "stop", "F3") {
            v := def
            if IsObject(cfg)
                try v := cfg.Get("Hotkeys." name, def)
            if (StrUpper(Trim(String(v))) == kk)
                return "clip hotkey " kk " is the macro " name " hotkey: pick another F4-F24 key"
        }
        cap := Clip.DefaultCaptureKey
        if IsObject(cfg)
            try cap := cfg.Get("Calibrate.captureKey", Clip.DefaultCaptureKey)
        if (Trim(String(cap)) = "")
            cap := Clip.DefaultCaptureKey
        if (StrUpper(Trim(String(cap))) == kk)
            return "clip hotkey " kk " is the calibration capture key: pick another F4-F24 key"
        if (StrUpper(RouteRecorder.Key) == kk)
            return "clip hotkey " kk " is the route recorder key: pick another F4-F24 key"
        ; a combo holding the capture or recorder key presses it too
        keys := Clip.Keys(k)
        if (keys.Length > 1) {
            for n in keys {
                if (StrUpper(n) == StrUpper(Trim(String(cap))))
                    return "clip hotkey " kk " holds the calibration capture key " n ": pick another key"
                if (StrUpper(n) == StrUpper(RouteRecorder.Key))
                    return "clip hotkey " kk " holds the route recorder key " n ": pick another key"
            }
        }
        return ""
    }

    static AuraWanted(name) {
        if !IsObject(Clip._cfg)
            return false
        return Clip.NameInList(Clip._cfg.Get("Medal.auras", ""), name)
    }

    ; name is one of the comma-separated entries (case/space-insensitive).
    static NameInList(csv, name) {
        n := Clip._Norm(name)
        if (n = "")
            return false
        for part in StrSplit(String(csv), ",")
            if (Clip._Norm(part) == n)
                return true
        return false
    }

    static Trigger(reason) {
        cfg := Clip._cfg
        if !IsObject(cfg) || !cfg.Get("Medal.enabled", 0)
            return "disabled"
        key := Clip._Hotkey()
        why := Clip.HotkeyProblem(key, cfg)
        if (why != "") {
            if !Clip._warnedKey {
                Clip._warnedKey := true
                Clip._Log("Clip: " why "; clips skipped")
            }
            return "bad_hotkey"
        }
        if !Clip._MedalRunning() {
            if !Clip._warnedMissing {
                Clip._warnedMissing := true
                Clip._Log("Clip: Medal (medal.exe) is not running; clip skipped")
            }
            return "no_medal"
        }
        Clip._warnedMissing := false
        cls := Clip.ReasonClass(reason)
        now := Clip._clockFn.Call()
        cool := Max(0, cfg.Get("Medal.cooldownSec", Clip.DefaultCooldownSec)) * 1000
        if (Clip._last.Has(cls) && now - Clip._last[cls] < cool)
            return "cooldown"
        Clip._last[cls] := now
        delay := Max(0, cfg.Get("Medal.delaySec", Clip.DefaultDelaySec)) * 1000
        r := String(reason)
        gen := Clip._gen
        Clip._timerFn.Call(() => Clip._Fire(r, key, gen, 0), delay)
        return "scheduled"
    }

    ; Timer callback: tap the hotkey if not cancelled/stopped, no potion is
    ; being handled (else re-arm) and Medal is still running.
    static _Fire(reason, key, gen, defers) {
        if (gen != Clip._gen)
            return                                  ; cancelled (stop / reset)
        if IsObject(Clip._stopFn) {
            stopped := true
            try stopped := Clip._stopFn.Call() ? true : false
            if stopped {
                Clip._Log("Clip: macro stopped; scheduled clip dropped")
                return
            }
        }
        if PotionsTask.busy {
            if (defers >= Clip.MaxDefers) {
                Clip._Log("Clip: potions busy too long; clip dropped (" reason ")")
                return
            }
            Clip._timerFn.Call(() => Clip._Fire(reason, key, gen, defers + 1), Clip.DeferMs)
            return
        }
        if !Clip._MedalRunning() {
            Clip._Log("Clip: Medal closed before the clip; skipped")
            return
        }
        try {
            Clip.Press(key, Clip._io)
        } catch Any as e {
            Clip._Log("Clip: hotkey send failed: " (e is Error ? e.Message : "error"))
            return
        }
        Clip._Log("Clip: Medal clip hotkey sent (" reason ")")
        if IsObject(Clip._wh) {
            desc := "Medal clip hotkey sent for: " reason
            if (Clip.ReasonClass(reason) = "aura") {
                try desc := "Medal clip hotkey sent for a rare aura.`n"
                    . Auras.Describe(Clip._cfg, SubStr(reason, InStr(reason, ":") + 1))
            }
            try Clip._wh.Send("clips", "Clip saved", desc
                . "`n(the clip stays in Medal; it is not uploaded)", 0x9B59B6)
        }
    }

    ; Presses hotkey k: one key tapped, or a combo (the keys held in press
    ; order, the last tapped, released in reverse). Letters go out lower
    ; case: a capital in a send adds a Shift of its own.
    static Press(k, io := "") {
        keys := Clip.Keys(k)
        if !IsObject(keys)
            throw ValueError("Clip.Press: bad hotkey")
        send := []
        for n in keys
            send.Push(StrLen(n) = 1 ? StrLower(n) : n)
        if (send.Length = 1)
            return Input.Key(send[1], 50, io)
        last := send.Pop()
        Input.Combo(send, last, 50, io)
    }

    static _Hotkey() {
        k := Clip._cfg.Get("Medal.clipHotkey", "")
        if (Trim(k) = "")
            k := Clip._cfg.Get("Medal.hotkey", "")
        return Trim(k)
    }

    static _MedalRunning() {
        try return Clip._procFn.Call("medal.exe") ? true : false
        catch
            return false
    }

    static _Norm(s) => StrLower(Trim(RegExReplace(String(s), "\s+", " ")))

    static _Log(t) {
        if IsObject(Clip._logFn)
            try Clip._logFn.Call(t)
    }
}
