#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\TaskEnv.ahk
#Include %A_LineFile%\..\..\Screenshot.ahk
; ---------------------------------------------------------------------------
; LimboTask: stays in THE LIMBO next to Eden's spawn and contracts with Eden.
;
;   t := LimboTask(deps)   deps as TaskEnv (cfg, webhook, log, io, cal, ocr,
;                          now) plus, optional:
;     find      callable find(x, y, w, h, re, scale) -> {x, y, text} or ""
;               (default Ocr.FindText: where on screen text matching re is)
;     toIsland  callable toIsland(ctx) -> bool: back to Sol's Island (the App
;               wires RecoveryTask.ReturnToIsland: rejoin the private server)
;     shot      callable shot() -> png path or ""   (default Screenshot)
;   t.name = "limbo", t.priority = 98. Limbo.enabled=1 is a MODE: the App
;   sets state.limboMode and the Scheduler then runs only limbo, potions and
;   recovery (no fishing, selling, crafting, quests, merchants or biome
;   items; biome webhooks and clips go on as usual). state.inLimbo says
;   where the player is; while it is true only limbo and recovery run (buffs
;   and the island do not work in Limbo).
;
; Sol's RNG wiki (2026): Eden (the NPC) spawns 1 in 50,000 every 2 minutes,
; client-sided, on the LAST island of THE LIMBO. Talking to it with a Void
; Heart plus a Darklight Core, Orb and Shard in the inventory offers "Contract
; with it". The Portable Crack takes the player into THE LIMBO; rejoining the
; private server puts them back on Sol's Island.
;
; Run(ctx):
;   - in Limbo and a rare biome is up (state.rareActive): toIsland (rejoin),
;     state.inLimbo := false. The island tasks (potions first) run next.
;   - in Limbo with Limbo switched off (also after a stop and start): the
;     same way back; when it fails, inLimbo is cleared anyway (errors
;     webhook: rejoin yourself), so the other tasks are never blocked.
;   - not in Limbo (and no rare biome): use the Portable Crack from the
;     inventory (search, typed again up to SearchTries when no tile reads
;     "crack", the description must mention the crack / Limbo / void, else
;     nothing is used, the inventory is closed (checked) and no new try for
;     RetryMin). state.inLimbo := true the moment Use is clicked, the
;     inventory is closed (checked), then EnterMs. Cut short after Use: the
;     next run walks (no second crack).
;   - right after entering (THE LIMBO has no working reset, so the walk
;     starts where the crack puts the player): Input.ReAim (Aura Collections
;     open + close: fixed camera angle), camera top-down (Input.CameraSteps),
;     walk the "limbo_eden" route (recorded in Dashboard > Tools from the
;     same spot and view; not recorded = stand there yourself). A run that
;     starts already in Limbo does not walk (the player is where the last
;     one left them). Then until stopped, a rare biome or Limbo switched
;     off: press E,
;     look for "Contract with it" in the dialog area (DialogBox) and click it
;     where the text is. A contract click sends the `rare` webhook with a
;     screenshot (mention on), at most once per ReportGapMin.
; ---------------------------------------------------------------------------

class LimboTask {
    static CrackName := "Portable Crack"
    static TileRe := "i)crack"
    static DescRe := "i)crack|limbo|void"
    static EnterMs := 9000          ; after Use, before walking (teleport + caption)
    static InvMs := 700
    static SearchMs := 700
    static SelectMs := 500
    static TalkKey := "e"
    static PollMs := 2500           ; E presses while waiting for Eden
    static DialogMs := 2500         ; how long the dialog may take to show its buttons
    static DialogPollMs := 250
    static ContractRe := "i)c[ao]ntr[ao]ct"
    ; NPC dialog buttons (2560x1440)
    static DialogBox := {x: 560, y: 1120, w: 1440, h: 220}
    static ReportGapMin := 10
    static RouteName := "limbo_eden"
    static RetryMin := 10           ; after the crack could not be used
    static SearchTries := 3         ; typed search attempts (a dropped letter finds nothing)

    name := "limbo"
    priority := 98

    __New(deps := "") {
        this._env := TaskEnv(deps)
        this._findFn := TaskEnv.Dep(deps, "find", "")
        if !IsObject(this._findFn)
            this._findFn := (x, y, w, h, re, scale := 1) => Ocr.FindText(x, y, w, h, re, scale)
        this._toIsland := TaskEnv.Dep(deps, "toIsland", "")
        this._shotFn := TaskEnv.Dep(deps, "shot", "")
        if !IsObject(this._shotFn)
            this._shotFn := () => Screenshot.Capture(Roblox.Hwnd())
        this._state := ""
        this._reportedAt := ""
        this._holdUntil := 0        ; env.Now() before which no new crack attempt
        this._walkDue := false      ; the crack was used, the walk to Eden not done yet
        this._usedAt := 0           ; env.Now() of the last Use click
    }

    Enabled() {
        cfg := this._env.cfg
        return IsObject(cfg) ? (cfg.Get("Limbo.enabled", 0) ? true : false) : false
    }

    CanRun(state) {
        this._state := state
        inLimbo := HasProp(state, "inLimbo") && state.inLimbo
        ; switched off in Limbo (or still in it after a stop and start): go
        ; back, else inLimbo blocks every other task for good (2026-10-27
        ; review). Run clears inLimbo even when the way back fails.
        if !this.Enabled()
            return inLimbo
        rare := HasProp(state, "rareActive") && state.rareActive
        if (inLimbo && rare)
            return IsObject(this._toIsland)
        if (!inLimbo && this._env.Now() < this._holdUntil)
            return false
        return !rare
    }

    Run(ctx) {
        env := this._env
        st := this._state
        if !IsObject(st)
            return 0
        off := !this.Enabled()
        if (st.inLimbo && (st.rareActive || off)) {
            env.Log("limbo: " (off ? "Limbo was switched off" : "rare biome " st.biome) ": back to Sol's Island (rejoining)")
            ok := false
            if IsObject(this._toIsland)
                try ok := this._toIsland.Call(ctx)
            if ok {
                st.inLimbo := false
                env.Report("biome", "Left Limbo", off ? "Back on Sol's Island: Limbo is off." : "Back on Sol's Island for **" st.biome "**.")
            } else if (off && !ctx.ShouldStop()) {
                ; Limbo is off and will not come back for this: inLimbo would
                ; block every other task for good, so the user rejoins
                st.inLimbo := false
                env.Log("limbo: could not rejoin Sol's Island; Limbo is off, so the island tasks run again (rejoin yourself if still in Limbo)")
                env.Report("errors", "Limbo is off", "Could not rejoin Sol's Island after Limbo was switched off. If the player is still in THE LIMBO, rejoin the private server yourself.", 0xE74C3C)
            }
            return ok ? 1 : 0
        }
        if (st.inLimbo && !this._walkDue)
            return this._Watch(ctx, st)
        if !st.inLimbo {
            if !this._Enter(ctx, st) {
                if (!st.inLimbo && !ctx.ShouldStop())
                    this._holdUntil := env.Now() + LimboTask.RetryMin * 60000
                return 0
            }
        } else {
            ; the crack was used but the run was cut short before the walk
            ; (2026-10-27 review): finish the teleport wait, then walk
            left := LimboTask.EnterMs - (env.Now() - this._usedAt)
            if (left > 0 && !env.Wait(Min(left, LimboTask.EnterMs), ctx))
                return 0
        }
        env.Log("limbo: in THE LIMBO")
        if !Input.ReAim(ctx, env.io) {
            if !ctx.ShouldStop()
                this._walkDue := false          ; watch from here next time (as before)
            return 0
        }
        steps := []
        route := env.cfg.Data("routes")
        if (route is Map && route.Has(LimboTask.RouteName)) {
            r := env.Route(LimboTask.RouteName)
            if IsObject(r)
                steps := Input.RouteList(r)
        }
        this._walkDue := false              ; a walk cut short is not walked again from mid-way
        if !Input.PlayRoute(Input.WithCamera(LimboTask.RouteName, steps), ctx, env.io)
            return 0
        return this._Watch(ctx, st)
    }

    ; Presses E near Eden's spot until stopped, a rare biome starts or Limbo
    ; is switched off (2026-10-27 review: it then pressed E there forever);
    ; clicks "Contract with it" when it shows. -> number of contract clicks.
    _Watch(ctx, st) {
        env := this._env
        b := LimboTask.DialogBox
        clicks := 0
        while !(ctx.ShouldStop() || st.rareActive || !this.Enabled()) {
            Input.Key(LimboTask.TalkKey, 80, env.io)
            waited := 0
            hit := ""
            Loop {
                try hit := this._findFn.Call(b.x, b.y, b.w, b.h, LimboTask.ContractRe, 2)
                if IsObject(hit) || waited >= LimboTask.DialogMs
                    break
                if !env.Wait(LimboTask.DialogPollMs, ctx)
                    return clicks
                waited += LimboTask.DialogPollMs
            }
            if IsObject(hit) {
                env.Log("limbo: Eden is here: clicking '" Trim(hit.text) "'")
                env.Click({x: hit.x, y: hit.y})
                clicks++
                if !env.Wait(3000, ctx)
                    return clicks
                this._ReportContract(hit.text)
            }
            if !env.Wait(LimboTask.PollMs, ctx)
                break
        }
        return clicks
    }

    _ReportContract(text) {
        env := this._env
        now := env.Now()
        if (this._reportedAt !== "" && now - this._reportedAt < LimboTask.ReportGapMin * 60000)
            return
        this._reportedAt := now
        shot := ""
        try shot := this._shotFn.Call()
        if IsObject(env.wh)
            try env.wh.Send("rare", "EDEN", "## Eden spawned`nClicked **" Trim(text) "**.", 0x111111
                , {mention: true, screenshot: shot})
    }

    ; The Portable Crack from the inventory, with proof it is the selected
    ; item. -> true when Use was clicked and EnterMs passed. st.inLimbo is
    ; set the moment Use is clicked: a stop, pause or preempt in the wait
    ; after it left the player in Limbo with inLimbo false, and the next run
    ; used another crack (2026-10-27 review); the walk is then still due.
    _Enter(ctx, st) {
        env := this._env
        io := env.io
        this._walkDue := false
        c := {}
        for id in ["inv_open", "inv_items_tab", "inv_search", "inv_use"] {
            c.%id% := env.Point(id)
            if (c.%id% == "")
                return false
        }
        for id in ["inv_tile1_rect", "inv_desc_rect"] {
            c.%id% := env.Rect(id)
            if (c.%id% == "")
                return false
        }
        env.Click(c.inv_open)
        if !env.Wait(LimboTask.InvMs, ctx)
            return false
        env.Click(c.inv_items_tab)
        if !env.Wait(LimboTask.InvMs, ctx)
            return false
        ; Roblox drops a typed letter now and then ("Portble Crack"): no crack
        ; tile -> clear the search and type it again, as the merchant does
        ; (2026-10-27 review: one try, then a 10 min hold)
        t := c.inv_tile1_rect
        found := false
        Loop LimboTask.SearchTries {
            if ctx.ShouldStop()
                return false
            env.Click(c.inv_search)
            Input.ClearText(io)
            Input.TypeText(LimboTask.CrackName, io)
            if !env.Wait(LimboTask.SearchMs, ctx)
                return false
            if RegExMatch(this._Read(t), LimboTask.TileRe) {
                found := true
                break
            }
            if (A_Index < LimboTask.SearchTries)
                env.Log("limbo: no Portable Crack tile after typing the search (a letter may have been dropped): typing it again")
        }
        if !found
            return this._Fail(c, "no 'Portable Crack' tile after searching " LimboTask.SearchTries " times (do you own one?)", ctx)
        env.Click({x: t.x + t.w // 2, y: t.y + t.h // 2})
        if !env.Wait(LimboTask.SelectMs, ctx)
            return false
        if !RegExMatch(this._Read(c.inv_desc_rect), LimboTask.DescRe)
            return this._Fail(c, "the selected item's description does not mention the crack / Limbo; Use not clicked", ctx)
        if !RegExMatch(this._Read(t), LimboTask.TileRe)
            return this._Fail(c, "the first tile changed before Use; Use not clicked", ctx)
        if ctx.ShouldStop()
            return false
        env.Click(c.inv_use)
        st.inLimbo := true
        this._walkDue := true
        this._usedAt := env.Now()
        env.Log("limbo: used the Portable Crack")
        waited := env.Wait(LimboTask.InvMs, ctx)
        ; close the inventory (checked), even when that wait was cut short by a
        ; preempt; a real halt (F3, pause) sends nothing more
        cctx := CleanupCtx(ctx)
        if (!cctx.ShouldStop() && !env.CloseInv(c.inv_open, c.inv_items_tab, cctx) && !cctx.ShouldStop())
            env.Report("errors", "Inventory left open", "the inventory did not close after the Portable Crack", 0xE74C3C)
        return waited && env.Wait(LimboTask.EnterMs, ctx)
    }

    _Read(r) => String((this._env.ocrFn)(r.x, r.y, r.w, r.h))

    ; Not used: log + errors webhook, close the inventory (checked: a click
    ; right after typing may only leave the search box). -> false
    _Fail(c, why, ctx := "") {
        env := this._env
        env.Log("limbo: Portable Crack not used: " why)
        env.Report("errors", "Limbo: Portable Crack not used", why, 0xE74C3C)
        env.CloseInv(c.inv_open, c.inv_items_tab, ctx)
        return false
    }
}
