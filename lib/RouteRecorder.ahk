#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\Brand.ahk
#Include %A_LineFile%\..\Json.ahk
#Include %A_LineFile%\..\Input.ahk
; ---------------------------------------------------------------------------
; RouteRecorder: records a walking route by WATCHING the keyboard and stores
; it in data\routes.json in the Input.PlayRoute step format.
;
; It NEVER sends input: keys are only observed with GetKeyState(k, "P")
; polling (physical state), and the mouse through Raw Input
; (RegisterRawInputDevices with RIDEV_INPUTSINK on a hidden window: it only
; listens, Roblox still gets every event). Nothing is pressed, clicked or
; moved.
;
; CAMERA: while the RIGHT mouse button is held, mouse movement is recorded
; as ["look", dx, dy, ms] steps (raw deltas, merged every LookMs), the
; wheel as ["zoom", n, ms]; arrow keys and I / O are recorded as keys. The
; respawn before every route re-aims the camera (Input.ResetToSpawn), so a
; recorded turn replays the same way.
;
; How the user records (README "Recording routes"):
;   1. In Roblox, reset to spawn (Esc, R, Enter).
;   2. Start the recorder (Dashboard > Tools > Record, or
;      tools\record_route.ahk <name>), click back into Roblox.
;   3. Press F7 (RouteRecorder.Key), walk with W A S D / Space (E and F are
;      recorded too), turn the camera with the right mouse button / arrow
;      keys, zoom with the wheel / I / O, press F7 again to stop and save.
;      Esc cancels while recording. Before F7 a tap of Esc is the game's own
;      respawn (Esc, R, Enter: the app asks for it when its respawn failed),
;      so only holding Esc HoldCancelMs cancels then.
;   Routes after which the macro presses a key itself (quest_board: E;
;   cauldron: F) should end BEFORE that key; an E / F tap at the very end
;   is dropped on save (TrimInteract), so pressing it out of habit is fine.
;
; API
;   RouteRecorder.Run(name, path) -> {ok, msg, steps, routes}
;       blocking session with a small always-on-top status window (shown
;       without activating, so Roblox keeps focus). ok = saved.
;   RouteRecorder.Session(keys, startKey)   pure state machine (tests):
;       .Feed(t, isDown, mouse := "") once per poll; isDown(key) -> bool
;       (physical); mouse() -> {dx, dy, wheel} raw input since the last
;       call (wheel in WHEEL_DELTA units, 120 = one notch).
;       .state "waiting" | "recording" | "done" | "cancelled" | "toolong"
;       .events  Array of {key, action, t} (look: + dx, dy; zoom: + n)
;       .Steps() -> PlayRoute steps
;   RouteRecorder.RawMouse()   live raw-input listener: .ok, .Take(), .Close()
;   RouteRecorder.EventsToSteps(events, tStop) -> [[key, action, ms], ...]
;       ms of a step = time until the next event (last step 0). Keys still
;       held at tStop get an "up". Repeated downs / stray ups are dropped.
;   RouteRecorder.TrimInteract(steps) -> {steps, dropped}: removes E / F
;       down+up pairs at the end (the macro presses the interaction key
;       itself; pressing it twice would close the board again). dropped =
;       Array of the keys removed. The new last step waits 0 ms.
;   RouteRecorder.InteractKey(name) -> "e" (quest_board) | "f" (cauldron) | ""
;   RouteRecorder.Merge(routes, name, steps, stamp) -> routes (in place):
;       routes[name] := {"steps": steps, "_recorded": stamp} (an existing
;       "_note" is kept; a {"routes": {...}} wrapper is respected).
;   RouteRecorder.Save(path, name, steps) -> merged routes Map. A routes
;       file that exists but does not parse is NEVER overwritten (throws).
;   RouteRecorder.WriteAtomic(path, text)   tmp file + FileMove; refuses
;       when path or path.tmp is a directory.
;   RouteRecorder.ValidName(name)  lower-case [a-z][a-z0-9_]*, not the
;       FishSol sell routes (vip / nonvip) or "_source".
; ---------------------------------------------------------------------------

class RouteRecorder {
    static Key := "F7"
    static Keys := ["w", "a", "s", "d", "Space", "e", "f", "RButton", "Left", "Right", "Up", "Down", "i", "o"]
    static LookMs := 40           ; camera movement is merged into one look step per 40 ms
    static Names := ["sell_to_fisher", "fisher_to_fishing", "quest_board", "cauldron", "limbo_eden", "obby", "memory_match"]   ; sell_to_fisher: spawn -> Captain Flarg (stop before E); fisher_to_fishing: stand at Flarg -> the fishing spot. Recorded, they replace the shipped sell walks   ; merchants use the teleporter; craft respawns after the cauldron; limbo_eden: Limbo spawn -> Eden; obby / memory_match: no shipped default (the user records them)
    ; The creator's recordings, shipped: Dashboard > Tools "Reset" copies a
    ; route from here back into data\routes.json.
    static DefaultsPath := RegExReplace(A_LineFile, "\\[^\\]*\\[^\\]*$") "\data\default_routes.json"
    static Interact := Map("quest_board", "e", "cauldron", "f", "memory_match", "e", "sell_to_fisher", "e")   ; QuestsTask / CraftTask / MemoryMatchTask OpenKey
    static Reserved := Map("vip", 1, "nonvip", 1, "_source", 1, "routes", 1)
    static MaxMs := 180000
    static HoldCancelMs := 1500     ; Esc held this long cancels before F7
    static PollMs := 5             ; with the 1 ms timer (Input.HiRes) while recording
    static _running := false

    static ValidName(name) {
        n := String(name)
        return RegExMatch(n, "^[a-z][a-z0-9_]{0,39}$") && !RouteRecorder.Reserved.Has(n)
    }

    ; "W" -> "w", "space" -> "Space"; unknown key -> "".
    static NormKey(k) {
        for want in RouteRecorder.Keys
            if (StrLower(String(k)) == StrLower(want))
                return want
        return ""
    }

    static EventsToSteps(events, tStop := "") {
        if !(events is Array)
            throw ValueError("RouteRecorder: events must be an Array")
        clean := []
        held := Map()
        order := []
        lastT := ""
        for ev in events {
            if (ev.action = "look" || ev.action = "zoom") {
                if !IsInteger(ev.t) || (lastT !== "" && ev.t < lastT)
                    throw ValueError("RouteRecorder: event times must be ascending integers")
                lastT := ev.t
                clean.Push(ev)
                continue
            }
            k := RouteRecorder.NormKey(ev.key)
            if (k = "")
                throw ValueError("RouteRecorder: key not recordable")
            if !(ev.action = "down" || ev.action = "up")
                throw ValueError("RouteRecorder: bad action")
            if !IsInteger(ev.t) || (lastT !== "" && ev.t < lastT)
                throw ValueError("RouteRecorder: event times must be ascending integers")
            lastT := ev.t
            isHeld := held.Has(k) && held[k]
            if (ev.action = "down") {
                if isHeld
                    continue                    ; auto-repeat / duplicate
                held[k] := true
                order.Push(k)
            } else {
                if !isHeld
                    continue                    ; released before recording started
                held[k] := false
            }
            clean.Push({key: k, action: ev.action, t: Integer(ev.t)})
        }
        if (clean.Length = 0)
            return []
        tEnd := (tStop !== "" && IsInteger(tStop) && tStop >= lastT) ? Integer(tStop) : lastT
        for k in order {
            if (held.Has(k) && held[k]) {
                held[k] := false
                clean.Push({key: k, action: "up", t: tEnd})
            }
        }
        steps := []
        for i, ev in clean {
            ms := (i < clean.Length) ? clean[i + 1].t - ev.t : 0
            if (ev.action = "look")
                steps.Push(["look", Integer(ev.dx), Integer(ev.dy), ms])
            else if (ev.action = "zoom")
                steps.Push(["zoom", Integer(ev.n), ms])
            else
                steps.Push([ev.key, ev.action, ms])
        }
        return steps
    }

    static InteractKey(name) => RouteRecorder.Interact.Has(String(name)) ? RouteRecorder.Interact[String(name)] : ""

    static TrimInteract(steps) {
        out := []
        for s in steps
            out.Push(s)
        dropped := []
        while (out.Length >= 2) {
            last := out[out.Length], prev := out[out.Length - 1]
            k := StrLower(String(last[1]))
            if !((k = "e" || k = "f") && last[2] = "up" && StrLower(String(prev[1])) = k && prev[2] = "down")
                break
            out.Pop(), out.Pop()
            dropped.InsertAt(1, k)
        }
        if (dropped.Length > 0 && out.Length > 0)
            out[out.Length] := [out[out.Length][1], out[out.Length][2], 0]
        return {steps: out, dropped: dropped}
    }

    static Merge(routes, name, steps, stamp := "") {
        if !(routes is Map)
            throw ValueError("RouteRecorder: routes must be a Map")
        if !RouteRecorder.ValidName(name)
            throw ValueError("RouteRecorder: bad route name")
        target := (routes.Has("routes") && routes["routes"] is Map) ? routes["routes"] : routes
        entry := Map("steps", steps, "_recorded", stamp != "" ? stamp : FormatTime(, "yyyy-MM-dd HH:mm"))
        if (target.Has(name) && target[name] is Map && target[name].Has("_note"))
            entry["_note"] := target[name]["_note"]
        target[name] := entry
        return routes
    }

    static Save(path, name, steps) {
        if !RouteRecorder.ValidName(name)
            throw ValueError("RouteRecorder: bad route name")
        if !(steps is Array) || steps.Length = 0
            throw ValueError("RouteRecorder: nothing recorded")
        Input.ParseRoute(steps)                 ; same validation as playback
        routes := Map()
        if FileExist(path) && !DirExist(path) {
            try {
                routes := Json.Parse(FileRead(path, "UTF-8"))
            } catch Any {
                throw Error("RouteRecorder: " path " does not parse; fix it first (it was not changed)")
            }
            if !(routes is Map)
                throw Error("RouteRecorder: " path " is not a JSON object; fix it first (it was not changed)")
        }
        RouteRecorder.Merge(routes, name, steps)
        RouteRecorder.WriteAtomic(path, Json.Stringify(routes) "`n")
        return routes
    }

    static WriteAtomic(path, text) {
        if DirExist(path)
            throw Error("RouteRecorder: " path " is a directory")
        tmp := path ".tmp"
        if DirExist(tmp)
            throw Error("RouteRecorder: " tmp " is a directory")
        f := FileOpen(tmp, "w", "UTF-8-RAW")
        if !IsObject(f)
            throw Error("RouteRecorder: cannot write " tmp)
        try {
            f.Write(text)
        } finally {
            f.Close()
        }
        try {
            FileMove(tmp, path, 1)
        } catch Any as e {
            try FileDelete(tmp)
            throw e
        }
    }

    class Session {
        __New(keys := "", startKey := "") {
            this.keys := (keys is Array) ? keys : RouteRecorder.Keys
            this.startKey := (startKey != "") ? startKey : RouteRecorder.Key
            this.state := "waiting"
            this.events := []
            this.t0 := ""
            this.tStop := ""
            this._prev := Map()
            this._prevStart := false
            this._prevEsc := false
            this._escAt := ""          ; when Esc went down (hold-to-cancel while waiting)
            this._lookDx := 0, this._lookDy := 0, this._lookT := ""
            this._wheel := 0
        }

        Done() => (this.state != "waiting" && this.state != "recording")

        ; One poll. isDown(key) -> physical key state; mouse() -> raw deltas
        ; since the last poll (taken every poll, so input before F7 is dropped).
        Feed(t, isDown, mouse := "") {
            if this.Done()
                return this.state
            m := IsObject(mouse) ? mouse.Call() : ""
            s := isDown.Call(this.startKey) ? true : false
            esc := isDown.Call("Escape") ? true : false
            startEdge := (s && this._prevStart == false)
            escEdge := (esc && this._prevEsc == false)
            this._prevStart := s, this._prevEsc := esc
            if escEdge
                this._escAt := t
            if (this.state = "recording" && escEdge) {
                this.state := "cancelled"
                return this.state
            }
            if (this.state = "waiting" && esc && this._escAt !== "" && t - this._escAt >= RouteRecorder.HoldCancelMs) {
                this.state := "cancelled"
                return this.state
            }
            if (this.state = "waiting") {
                if startEdge {
                    this.state := "recording"
                    this.t0 := t
                    for k in this.keys {
                        d := isDown.Call(k) ? true : false
                        this._prev[k] := d
                        if d                        ; already held when recording starts
                            this.events.Push({key: k, action: "down", t: t})
                    }
                }
                return this.state
            }
            ; recording
            if startEdge {
                this._FlushLook()
                this.tStop := t
                this.state := "done"
                return this.state
            }
            if (t - this.t0 > RouteRecorder.MaxMs) {
                this.state := "toolong"
                return this.state
            }
            ; camera: movement only while the right button is (or was) held
            if IsObject(m) {
                rHeld := (this._prev.Has("RButton") && this._prev["RButton"]) || isDown.Call("RButton")
                if (rHeld && (m.dx != 0 || m.dy != 0)) {
                    if (this._lookT = "")
                        this._lookT := t
                    this._lookDx += m.dx, this._lookDy += m.dy
                }
                this._wheel += m.wheel
            }
            changes := []
            for k in this.keys {
                d := isDown.Call(k) ? true : false
                if (d != this._prev[k])
                    changes.Push({key: k, action: d ? "down" : "up", t: t})
                this._prev[k] := d
            }
            if (changes.Length || (this._lookT != "" && t - this._lookT >= RouteRecorder.LookMs))
                this._FlushLook()
            for ev in changes
                this.events.Push(ev)
            notches := (this._wheel >= 0) ? this._wheel // 120 : -((-this._wheel) // 120)
            if (notches != 0) {
                this._FlushLook()
                this.events.Push({key: "zoom", action: "zoom", t: t, n: notches})
                this._wheel -= notches * 120
            }
            return this.state
        }

        _FlushLook() {
            if (this._lookT != "" && (this._lookDx != 0 || this._lookDy != 0))
                this.events.Push({key: "look", action: "look", t: this._lookT, dx: this._lookDx, dy: this._lookDy})
            this._lookDx := 0, this._lookDy := 0, this._lookT := ""
        }

        Steps() => RouteRecorder.EventsToSteps(this.events, this.tStop)
    }

    ; Blocking recording session (see header). Never sends input.
    static Run(name, path) {
        res := {ok: false, msg: "", steps: [], routes: ""}
        if !RouteRecorder.ValidName(name) {
            res.msg := "bad route name '" name "'"
            return res
        }
        if RouteRecorder._running {
            res.msg := "a recording is already running"
            return res
        }
        RouteRecorder._running := true
        g := ""
        raw := ""
        hi := false
        try {
            sess := RouteRecorder.Session()
            g := RouteRecorder._Gui(name)
            raw := RouteRecorder.RawMouse()
            Input.HiRes(true)
            hi := true
            mouse := raw.ok ? ObjBindMethod(raw, "Take") : ""
            isDown := (k) => GetKeyState(k, "P")
            ; keys held when the window opens are not a start / cancel press
            sess._prevStart := isDown.Call(sess.startKey) ? true : false
            sess._prevEsc := isDown.Call("Escape") ? true : false
            shown := ""
            while !sess.Done() {
                sess.Feed(Round(Input.NowMs()), isDown, mouse)     ; precise clock, not the 15.6 ms A_TickCount
                txt := (sess.state = "waiting")
                    ? "Route '" name "': click into Roblox at the start spot, then press " sess.startKey " to start. Hold Esc to cancel."
                    : "RECORDING '" name "': " sess.events.Length " events. Camera: hold right mouse + drag, wheel zooms"
                        . (raw.ok ? "" : " (mouse not readable: use arrow keys / I / O)") ". " sess.startKey " = save, Esc = cancel."
                if (txt != shown) {
                    shown := txt
                    try g.text.Value := txt
                }
                Sleep(RouteRecorder.PollMs)
            }
            if (sess.state = "cancelled") {
                res.msg := "cancelled; routes.json not changed"
                return res
            }
            if (sess.state = "toolong") {
                res.msg := "longer than " (RouteRecorder.MaxMs // 1000) " s; discarded"
                return res
            }
            tr := RouteRecorder.TrimInteract(sess.Steps())
            steps := tr.steps
            if (steps.Length = 0) {
                res.msg := "no movement keys were pressed; nothing saved"
                return res
            }
            res.routes := RouteRecorder.Save(path, name, steps)
            res.steps := steps
            res.ok := true
            res.msg := "saved route '" name "' (" steps.Length " steps)"
                . (tr.dropped.Length ? "; dropped the " StrUpper(tr.dropped[1]) " press at the end (the macro presses it)" : "")
            return res
        } catch Any as e {
            res.msg := "not saved: " ((e is Error) ? e.Message : String(e))
            return res
        } finally {
            if hi
                Input.HiRes(false)
            if IsObject(raw)
                try raw.Close()
            if IsObject(g)
                try g.gui.Destroy()
            RouteRecorder._running := false
        }
    }

    ; Raw Input mouse listener (WM_INPUT to a hidden window, RIDEV_INPUTSINK:
    ; also while Roblox has focus). Listens only; sends nothing.
    class RawMouse {
        __New() {
            this.dx := 0, this.dy := 0, this.wheel := 0
            this.ok := false
            this._fn := ""
            this._gui := Gui("+ToolWindow -Caption")      ; never shown
            rid := Buffer(8 + A_PtrSize, 0)
            NumPut("UShort", 1, "UShort", 2, "UInt", 0x100, rid, 0)   ; generic desktop / mouse, RIDEV_INPUTSINK
            NumPut("Ptr", this._gui.Hwnd, rid, 8)
            if !DllCall("RegisterRawInputDevices", "Ptr", rid, "UInt", 1, "UInt", 8 + A_PtrSize)
                return
            this._fn := ObjBindMethod(this, "_OnInput")
            OnMessage(0x00FF, this._fn)
            this.ok := true
        }

        _OnInput(wParam, lParam, msg, hwnd) {
            hdr := 8 + 2 * A_PtrSize
            size := 0
            DllCall("GetRawInputData", "Ptr", lParam, "UInt", 0x10000003, "Ptr", 0, "UInt*", &size, "UInt", hdr)
            if (size < hdr + 24)
                return
            buf := Buffer(size, 0)
            if (DllCall("GetRawInputData", "Ptr", lParam, "UInt", 0x10000003, "Ptr", buf, "UInt*", &size, "UInt", hdr) <= 0)
                return
            if (NumGet(buf, 0, "UInt") != 0)                 ; RIM_TYPEMOUSE
                return
            if !(NumGet(buf, hdr, "UShort") & 1) {          ; not MOUSE_MOVE_ABSOLUTE
                this.dx += NumGet(buf, hdr + 12, "Int")
                this.dy += NumGet(buf, hdr + 16, "Int")
            }
            if (NumGet(buf, hdr + 4, "UShort") & 0x0400)    ; RI_MOUSE_WHEEL
                this.wheel += NumGet(buf, hdr + 6, "Short")
        }

        ; -> {dx, dy, wheel} since the last call.
        Take() {
            r := {dx: this.dx, dy: this.dy, wheel: this.wheel}
            this.dx := 0, this.dy := 0, this.wheel := 0
            return r
        }

        Close() {
            if this.ok {
                rid := Buffer(8 + A_PtrSize, 0)
                NumPut("UShort", 1, "UShort", 2, "UInt", 0x1, rid, 0)  ; RIDEV_REMOVE
                DllCall("RegisterRawInputDevices", "Ptr", rid, "UInt", 1, "UInt", 8 + A_PtrSize)
                OnMessage(0x00FF, this._fn, 0)
                this.ok := false
            }
            try this._gui.Destroy()
        }
    }

    static _Gui(name) {
        g := Gui("+AlwaysOnTop -Caption +ToolWindow +Border", Brand.Name " route recorder")
        g.BackColor := "0D1117"
        g.SetFont("s10 cF7F1E8", "Segoe UI")
        g.MarginX := 12, g.MarginY := 8
        g.SetFont("s10 bold cF2A93B")
        g.Add("Text", "w560", Brand.Name " route recorder (watches keys only, sends nothing)")
        g.SetFont("s10 norm cF7F1E8")
        t := g.Add("Text", "w560 h40", "")
        g.Show("x20 y20 NoActivate")
        return {gui: g, text: t}
    }
}
