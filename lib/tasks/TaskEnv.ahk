#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\..\Json.ahk
#Include %A_LineFile%\..\..\Scheduler.ahk
#Include %A_LineFile%\..\..\Roblox.ahk
#Include %A_LineFile%\..\..\Input.ahk
#Include %A_LineFile%\..\..\Pixel.ahk
#Include %A_LineFile%\..\..\Ocr.ahk
#Include %A_LineFile%\..\..\Calibrate.ahk
; ---------------------------------------------------------------------------
; TaskEnv: the injectable dependencies shared by the quest and merchant tasks
; (and ChatWatch). Every side effect goes through here so tests can swap it.
;
;   env := TaskEnv(deps)   deps = object literal; every key optional:
;     cfg      Config-like: Get(path, default), Data(name)       (default "")
;     webhook  Webhook-like: Send(event, title, desc, color)     (default "")
;     log      callable log(text)                                (default none)
;     io       Input io backend (Down/Up/MoveTo/ClickHere/Wait)  (default real)
;     cal      object with Point(id) / Rect(id)                  (default Calibrate)
;     ocr      callable ocr(x, y, w, h [, scale]) -> String      (default Ocr.Read)
;     pixel    callable pixel(x, y, color, tol) -> bool          (default Pixel.Is)
;     rect     callable rect(x, y, w, h) -> Array of w*h 0xRRGGBB (default Pixel._grabber)
;     now      callable now() -> ms                              (default A_TickCount)
;
;   env.Point(id) / env.Rect(id) -> calibration or "". A missing step is
;     logged and reported ONCE per id as an `errors` webhook; the caller must
;     skip the action. Coordinates are never guessed.
;   env.Route(name) -> validated route steps or "" (logged once when absent).
;     Routes come from cfg.Data("routes") (data\routes.json, Task 8): either
;     {"name": [...steps]} or {"routes": {"name": [...steps]}}.
;   env.Click(pt) / env.Wait(ms, ctx) / env.Report(event, title, desc [, color])
;     Report only sends the webhook.
;   env.BuyPrompt(who) -> true when a Roblox purchase prompt was on screen
;     (Input.ClosePurchase: closed with Esc, never clicked); logged and
;     reported. The caller aborts its step.
;   env.Unsafe(who [, invTab]) -> why a click must not be made now ("" =
;     safe): a purchase prompt was up (BuyPrompt), or invTab given and the
;     inventory's tabs do not read around it (InvOpen).
; Never prints webhook URLs (it never sees them).
; ---------------------------------------------------------------------------

class TaskEnv {
    __New(deps := "") {
        this.cfg := TaskEnv.Dep(deps, "cfg", "")
        this.wh := TaskEnv.Dep(deps, "webhook", "")
        this._logFn := TaskEnv.Dep(deps, "log", "")
        if IsObject(this._logFn)
            Input.LogFn := this._logFn          ; Input.ClickGuard's lines
        this.io := TaskEnv.Dep(deps, "io", "")
        if !IsObject(this.io)
            this.io := InputScreenIO()
        this.cal := TaskEnv.Dep(deps, "cal", "")
        if !IsObject(this.cal)
            this.cal := Calibrate
        ; ink reads (Ocr.ReadInk): a faked ocr (tests) gets a faked ink read
        ; too ("" unless deps "ink"), never the real screen
        this.inkFn := TaskEnv.Dep(deps, "ink", "")
        if !IsObject(this.inkFn)
            this.inkFn := IsObject(TaskEnv.Dep(deps, "ocr", "")) ? ((x, y, w, h, scale := 1, ink := 0) => "")
                : ((x, y, w, h, scale := 1, ink := 0) => Ocr.ReadInk(x, y, w, h, scale, ink))
        this.ocrFn := TaskEnv.Dep(deps, "ocr", "")
        if !IsObject(this.ocrFn)
            this.ocrFn := (x, y, w, h, scale := 1) => Ocr.Read(x, y, w, h, scale)
        this.pixelFn := TaskEnv.Dep(deps, "pixel", "")
        if !IsObject(this.pixelFn)
            this.pixelFn := (x, y, c, tol) => Pixel.Is(x, y, c, tol)
        this.rectFn := TaskEnv.Dep(deps, "rect", "")
        if !IsObject(this.rectFn)
            this.rectFn := (x, y, w, h) => Pixel.Grab(x, y, w, h)      ; design px at any client size
        this.nowFn := TaskEnv.Dep(deps, "now", "")
        if !IsObject(this.nowFn)
            this.nowFn := () => A_TickCount
        this._warned := Map()
    }

    static Dep(deps, key, default) {
        if (IsObject(deps) && HasProp(deps, key))
            return deps.%key%
        return default
    }

    Now() => (this.nowFn)()

    Log(text) {
        if IsObject(this._logFn)
            try (this._logFn)(text)
    }

    Report(event, title, desc, color := 0xF2A93B) {
        if IsObject(this.wh)
            try this.wh.Send(event, title, desc, color)
    }

    ; Logs and sends the errors webhook once per key (polling callers such as
    ; ChatWatch would otherwise log every poll).
    Problem(key, text) {
        if this._warned.Has(key)
            return
        this._warned[key] := true
        this.Log(text)
        this.Report("errors", "Task skipped", text, 0xE74C3C)
    }

    Point(id) {
        p := this.cal.Point(id)
        if (p == "")
            this.Problem("cal:" id, "calibration step '" id "' missing: action skipped")
        return p
    }

    Rect(id) {
        r := this.cal.Rect(id)
        if (r == "")
            this.Problem("cal:" id, "calibration step '" id "' missing: action skipped")
        return r
    }

    Route(name) {
        if (!IsObject(this.cfg) || name = "") {
            this.Problem("route:" name, "route name not configured: skipped")
            return ""
        }
        r := this.cfg.Data("routes")
        if (r is Map && r.Has("routes") && r["routes"] is Map)
            r := r["routes"]
        if !(r is Map && r.Has(name)) {
            this.Problem("route:" name, "route '" name "' not found in data\routes.json (record it first): skipped")
            return ""
        }
        try {
            Input.ParseRoute(r[name])
        } catch Any {
            this.Problem("route:" name, "route '" name "' is invalid: skipped")
            return ""
        }
        return r[name]
    }

    Click(pt) {
        Input.Click(pt.x, pt.y, this.io)
    }

    ; A Roblox purchase prompt up (a click went through a panel into the
    ; world, live 2026-11-02): closed with Esc, never a click on it.
    ; -> true when one was up (closed or not): the caller stops its step.
    BuyPrompt(who) {
        r := Input.ClosePurchase(this.io, this.ocrFn)
        if (r = 0)
            return false
        msg := who ": " (r = 1 ? "purchase prompt closed (Esc), step stopped"
            : "a Roblox purchase prompt is open and did not close with Esc: close it yourself (never press Buy)")
        this.Log(msg)
        this.Report("errors", "Purchase prompt " (r = 1 ? "closed" : "still open"), msg, 0xE74C3C)
        return true
    }

    ; Right before a click (no blind clicks, live 2026-11-02). -> why the
    ; click is refused, or "" (safe).
    Unsafe(who, invTab := "") {
        if this.BuyPrompt(who)
            return "a Roblox purchase prompt was on screen (closed with Esc, never clicked): stopped"
        if (IsObject(invTab) && !this.InvOpen(invTab))
            return "the inventory is not open (its Gears / Items tabs did not read): nothing clicked"
        return ""
    }

    ; The inventory is open: its tab labels (Gears / Items) read around the
    ; calibrated inv_items_tab point, at 2x: at 1x "Items" reads "'terns" over
    ; every open inventory (L22..L26), so it read closed, CloseInv clicked
    ; nothing, and the next try's click on inv_open shut it again.
    InvOpen(tabPt) {
        if !IsObject(tabPt)
            return false
        return RegExMatch((this.ocrFn)(tabPt.x - 90, tabPt.y - 25, 180, 50, 2), "i)item|gear") > 0
    }

    ; Closes the inventory: clicks inv_open while its tabs still read (a
    ; click right after typing may only take the focus off the search box;
    ; not open -> no click). -> true closed, false still open or stopped.
    CloseInv(openPt, tabPt, ctx := "", tries := 3) {
        Loop tries {
            if !this.InvOpen(tabPt)
                return true                     ; closed (or never open): no click that would open it
            this.Click(openPt)
            if !this.Wait(700, ctx)
                return false
        }
        if this.InvOpen(tabPt) {
            this.Log("the inventory is still open after " tries " clicks on its button")
            return false
        }
        return true
    }

    Wait(ms, ctx := "") => this.io.Wait(ms, ctx)

    ; Rect center, for hover.
    static Center(r) => [r.x + r.w // 2, r.y + r.h // 2]
}
