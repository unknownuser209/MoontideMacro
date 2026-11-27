#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\TaskEnv.ahk
; ---------------------------------------------------------------------------
; InvFindTask: one look at the open inventory, to place the inventory steps
; that can be found by their text (lib\AutoCal.ahk: inv_items_tab,
; inv_search, inv_use, inv_tile1_rect, inv_desc_rect). Setup that calibrates
; itself, for the inventory.
;
; A full calibration never runs this: CanRun is false while every one of
; those steps is recorded and the inventory works. It runs only when
;   - a step is MISSING (not recorded, not found yet this run), or
;   - the inventory FAILED ITS OWN READ: the tasks said FailsAt times in a
;     row that it did not open (UiStuck "inventory": its Gears / Items tabs
;     did not read around the recorded inv_items_tab). One look per run.
; and an inventory feature is switched on (Needs) and inv_open is recorded
; (the inventory button is a picture: it has no text to find it by).
;
;   t := InvFindTask(deps)   deps as TaskEnv; cal must have SetFound /
;                            Stored (Calibrate)
;   t.name = "autocal", t.priority = 5
;   t.Run(ctx) -> the number of steps placed
;
; THE LOOK (Screen mode "C": the inventory scales evenly, centred, as the
; tasks use it): is the Inventory on screen (its title, and the tasks' own
; check passes at the tab found: TaskEnv.InvOpen reads Gears / Items there)?
; No: one click on inv_open (not with a Roblox purchase prompt up), then
; read again. A part that did not read in the whole-screen read is looked
; for once more in the window alone, at 2x. Then
;   a step that is not recorded          -> kept for this run (Calibrate.
;                                           SetFound; never written to the
;                                           file, the Calibrate page still
;                                           shows it as automatic)
;   the recorded tab does not read where it is recorded, the found one does
;                                        -> every part found is used
;                                           INSTEAD of its recording until
;                                           the next Start (logged, errors
;                                           webhook: apply the preset or
;                                           record the steps again)
;   a recording that reads right         -> left alone
; A part is only placed when something reads where it would be (the search
; box's text, "use", a tile's name). The inventory is closed again with
; inv_open while it still reads on screen (checked, up to CloseTries).
; Steps still missing after MaxTries looks are reported once.
; ---------------------------------------------------------------------------

class InvFindTask {
    static MaxTries := 3
    static RetryMs := 600000       ; between two looks
    static OpenMs := 900
    static CloseTries := 3
    static FailsAt := 2            ; UiStuck "inventory" failures in a row
    ; the features that use the inventory (SetupCheck.InvNeeds; tested equal)
    static Needs := [["merchant.enabled", 1], ["Limbo.enabled", 0], ["BiomeItems.enabled", 0], ["Hunting.cursedRune", 0], ["DailyQuests.usePotions", 0]]

    name := "autocal"
    priority := 5

    __New(deps := "") {
        this._env := TaskEnv(deps)
        this._tries := 0
        this._lastAt := ""
        this._failLooked := false
        this._told := false
        this._gen := Calibrate.UseCount
    }

    ; the inventory steps with no place yet
    _Missing() {
        cal := this._env.cal
        out := []
        for id in AutoCal.InvIds
            if !(IsObject(cal.Point(id)) || IsObject(cal.Rect(id)))
                out.Push(id)
        return out
    }

    _Needed() {
        cfg := this._env.cfg
        if !IsObject(cfg)
            return false
        for kv in InvFindTask.Needs
            if cfg.Get(kv[1], kv[2])
                return true
        return false
    }

    _Failing() => UiStuck.counts.Has("inventory") && UiStuck.counts["inventory"] >= InvFindTask.FailsAt

    CanRun(state) {
        env := this._env
        if (this._gen != Calibrate.UseCount) {          ; a new Start / calibration: start over
            this._gen := Calibrate.UseCount
            this._tries := 0, this._lastAt := "", this._failLooked := false, this._told := false
        }
        if !(HasMethod(env.cal, "SetFound") && HasMethod(env.cal, "Stored"))
            return false
        if (!this._Needed() || !IsObject(env.cal.Point("inv_open")) || Input.Hot())
            return false
        if (this._lastAt !== "" && env.Now() - this._lastAt < InvFindTask.RetryMs)
            return false
        if (this._Missing().Length && this._tries < InvFindTask.MaxTries)
            return true
        return this._Failing() && !this._failLooked
    }

    Run(ctx) {
        old := Screen.Mode
        Screen.Mode := "C"
        try
            return this._Look(ctx)
        finally
            Screen.Mode := old
    }

    _Look(ctx) {
        env := this._env
        cal := env.cal
        this._lastAt := env.Now()
        missing := this._Missing()
        if missing.Length
            this._tries += 1
        else
            this._failLooked := true
        openPt := cal.Point("inv_open")
        if !IsObject(openPt)
            return 0
        inv := this._Up()
        clicked := false
        if !IsObject(inv) {
            if ((why := env.Unsafe("setup")) != "") {
                env.Log("setup: the inventory was not looked at: " why)
                return 0
            }
            env.Click(openPt)
            clicked := true
            if !env.Wait(InvFindTask.OpenMs, ctx)       ; preempted: closed first; a halt sends nothing
                return CleanupCtx.Halted(ctx) ? 0 : this._Close(CleanupCtx(ctx), openPt, 0)
            inv := this._Up()
        }
        if clicked                                      ; Test my calibration reads it (lib\CalHealth.ahk)
            IsObject(inv) ? CalHealth.Ok("inv_open", openPt) : CalHealth.Fail("inv_open", "a click on it did not open the inventory", openPt)
        if !IsObject(inv) {
            env.Log("setup: the inventory did not show after a click on inv_open (its title and tabs did not read): no step placed")
            return this._GiveUp(0)
        }
        ; small words a whole-screen read missed: the window alone, at 2x
        if !(IsObject(inv.search) && IsObject(inv.use) && IsObject(inv.tile1))
            inv := AutoCal.InvMerge(inv, AutoCal.Inventory(env.Lines(inv.box, 2), inv.title))
        if !IsObject(inv.use)                           ; ... and "use" in its own corner
            inv := AutoCal.InvMerge(inv, AutoCal.Inventory(env.Lines(inv.useBox, 2), inv.title))
        ; the recorded tab does not read where it is recorded: the recording
        ; is for another screen
        moved := false
        if cal.Stored("inv_items_tab") {
            rec := cal.Point("inv_items_tab")
            moved := IsObject(rec) && (Abs(rec.x - inv.tab.x) > 5 || Abs(rec.y - inv.tab.y) > 5) && !env.InvOpen(rec)
            if moved
                CalHealth.Fail("inv_items_tab", "the inventory's tabs did not read there; its Items tab was found at " inv.tab.x "," inv.tab.y, rec)
        }
        parts := Map("inv_items_tab", inv.tab, "inv_search", inv.search, "inv_use", inv.use, "inv_tile1_rect", inv.tile1, "inv_desc_rect", inv.desc)
        placed := "", n := 0
        for id in AutoCal.InvIds {
            v := parts[id]
            if !IsObject(v)
                continue
            if !cal.Stored(id)
                cal.SetFound(id, v)
            else if moved
                cal.SetFound(id, v, true)
            else
                continue
            n++
            placed .= (placed = "" ? "" : ", ") id " " v.x "," v.y
        }
        if moved {
            msg := "the inventory is not where it is calibrated (its tabs do not read at the recorded inv_items_tab): its steps found on screen are used until the next Start (" placed "). Apply the preset for your screen or record the inventory steps again on the Calibrate page."
            env.Log("setup: " msg)
            env.Report("errors", "Inventory calibration is off", msg, 0xE74C3C)
        } else if n
            env.Log("setup: inventory steps found on screen (" placed ")")
        else
            env.Log("setup: the inventory was looked at: nothing to place")
        return this._GiveUp(this._Close(ctx, openPt, n))
    }

    ; Steps still missing after the last look: told once.
    _GiveUp(n) {
        left := this._Missing()
        if (left.Length && this._tries >= InvFindTask.MaxTries && !this._told) {
            this._told := true
            names := ""
            for id in left
                names .= (names = "" ? "" : ", ") id
            this._env.Problem("setup:inv", "setup: these inventory steps could not be found on screen: " names ". Record them on the Calibrate page (or apply the preset).")
        }
        return n
    }

    ; The inventory on screen right now: its title read (AutoCal) AND its
    ; tabs read at the tab found (the tasks' own check). -> its parts or ""
    _Up() {
        env := this._env
        inv := AutoCal.Inventory(env.Lines())
        return (IsObject(inv) && env.InvOpen(inv.tab)) ? inv : ""
    }

    ; Closes the inventory with inv_open while it still reads on screen.
    ; -> n
    _Close(ctx, openPt, n) {
        env := this._env
        Loop InvFindTask.CloseTries {
            if !IsObject(this._Up())
                return n
            if (env.Unsafe("setup") != "")
                return n
            env.Click(openPt)
            if !env.Wait(700, ctx)
                return n
        }
        if IsObject(this._Up())
            env.Log("setup: the inventory is still open after " InvFindTask.CloseTries " clicks on its button")
        return n
    }
}
