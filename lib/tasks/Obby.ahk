#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\TaskEnv.ahk
#Include %A_LineFile%\..\..\GameLists.ahk
#Include %A_LineFile%\..\..\Auras.ahk
; ---------------------------------------------------------------------------
; ObbyTask: walk the obby with the Sailor aura and claim its Basic Blessing.
;
;   t := ObbyTask(deps)     deps as TaskEnv (cfg, webhook, log, io, cal, ocr,
;                           pixel, now) plus:
;     aura   callable aura() -> {known: bool, name: String}: the aura equipped
;            right now, from the Roblox log ("Equipped ..." in the rich
;            presence; name "" = none). App passes LogWatch.CurrentAura after
;            a poll. Default: unknown (the task never runs).
;   t.name = "obby", t.priority = 5   (Scheduler task contract)
;   t.CanRun(state)  -> cfg Obby.enabled (default 0) AND the route named by
;                       cfg Obby.route (default "obby") exists AND the aura
;                       storage steps are calibrated (aura_open, aura_search,
;                       aura_tile_rect, aura_equip, aura_close) AND the aura
;                       on now is known (deps.aura). Missing steps are
;                       logged once (env), the task is not eligible.
;                       The interval is enforced by Scheduler; App calls
;                       Scheduler.MarkRun after every run.
;   t.Run(ctx)       -> 1 when the blessing was seen, 0 otherwise.
;   t.PutOnSailor(ctx) -> {ok, had, prev, unknown, why}: Sailor on (step 2
;                       below); also used by the obby route's Test / Record
;                       buttons (App), so the route is walked as it plays.
;   t.PutBack(ctx, info) -> the aura from before PutOnSailor back (step 4);
;                       true when done or nothing to do.
;   t.Covered()      -> what covers the game now: "purchase" (a Roblox
;                       purchase prompt) | "daily rewards" (its popup) |
;                       "quest" (the Quest Board's page) |
;                       "collections" (Aura Collections) |
;                       "inventory" (its title reads) |
;                       "storage" (Aura Storage: its title or its
;                       "[ Information ]" panel reads) | "" (nothing)
;   t.ClearView(ctx) -> closes what Covered finds (Esc for a prompt, the
;                       popup's X, the quest page's Exit, the Collections close click, the inventory's X, the storage's X or its
;                       sidebar button: _ShutStorage). -> "" clear | what is
;                       still up (logged). MinionsTask runs it before and
;                       during a hunt (live 2026-11-02 23:29: the storage
;                       stayed open over a whole hunt).
;
; WHY SAILOR: Sailor walks on water, so the recorded route skips the jumps
; (the user records it with Sailor on).
;
; PASS
;   1. The aura on now is read (unknown -> errors webhook, nothing done).
;   2. SetAura("Sailor", equip): the storage's button says whether Sailor
;      is on already (the log can say "Sailor" for minutes after an
;      unequip: then the aura before was none). Not confirmed (the button
;      never flipped, nor the log) -> errors webhook, no run.
;   3. ResetToSpawn -> play the route. Check (buff_expand and obby_blessing
;      calibrated): the buff list only shows every buff when expanded, so
;      click buff_expand, poll the obby_blessing pixel for up to BlessingMs,
;      click buff_expand again (collapsed). Not seen -> play again, up to
;      Obby.retries more times (default 1, 0..3), then errors webhook.
;      Uncalibrated check -> one run, reported as unchecked. buff_expand is
;      clicked only while it shows its calibrated colour and no purchase
;      prompt is up (else, or a prompt after the click: no more clicks or
;      replays, errors webhook "not checked").
;   4. ResetToSpawn, then the aura goes back: the previous aura equipped
;      again, or (none before) Sailor unequipped. Failure -> errors webhook
;      naming the aura to put back by hand.
;
; SET AURA (never anything but Equip / Unequip)
;   aura_open -> the Regular / Special tab (Tabs, in turn per try) ->
;   aura_search: Input.ClearText (no Ctrl+A), type
;   the name (not found: typed again, SearchTries) -> click the result tiles
;   in turn (the first ScanTiles from aura_tile_rect, TileRect) until the
;   selected aura's name above [ Information ] (NameBox, plain text, read
;   at each NameScales scale) is exactly the aura (NameVerdict: folded
;   names equal; "Sailor" and "Sailor: Admiral" never match each other, a
;   stale or unsettled read is read again). No tile reads as it ->
;   _LogPick equips the results whose names did not read, in turn, until
;   the Roblox log names it, and stops there (a result whose name read as
;   another aura is never equipped) -> the button around
;   aura_equip must read "Equip" (or "Unequip" to unequip) and nothing like
;   delete / lock / sell (NeverRe) -> click it -> it must flip to the other
;   word within AuraWaitMs (else the log must already show the change) ->
;   aura_close. The change is remembered for LogLagMs: the log's "Equipped"
;   line follows an unequip only ~2 min later (live 2026-10-27).
;   Already in the wanted state (the button reads the other word) -> no
;   click on it. Every check failing -> nothing clicked on the button.
;
; EQUIP FIRST (settings.ini [Auras] equipFirst=1, default 0; for resolutions
; where the name / button reads fail, 1920x1080 and below): no read of the
; tiles' names, the name panel or the button (_SetAuraFirst). Whether the
; aura is on comes from the last swap seen, else the Roblox log (_Aura): on
; already (or off already, to unequip) -> the storage is not opened (a
; click on Equip would toggle it the wrong way). Else aura_open -> per try
; the Regular / Special tab, the search typed -> result tile 1 clicked when
; its pixels show one (an empty first slot: the other tab next try) ->
; Equip clicked at aura_equip (its calibrated point, never anywhere else)
; -> aura_close. Kept: the storage title before every click (_Refused),
; the purchase prompt guard, the Daily Rewards / Collections checks, the
; checked close. The search must list only the wanted aura first (the
; user's setup: "Sailor" lists "Sailor: Admiral" in front when owned).
;
; NO BLIND CLICKS (live 2026-11-02 09:20: "Eden" searched on the Regular
; tab left the grid empty; a click on the empty slot went through the
; storage into the world, hit a Donation board and opened Roblox's "Buy
; Robux and item ... Buy $4.99" prompt):
;   - a result tile is clicked only when its pixels show one (TileShown: an
;     aura's name / icon has bright pixels, an empty slot is the dim world
;     behind the panel); the first empty slot ends that tab's try (the next
;     try takes the other tab)
;   - every click on the storage (tabs, search box, tiles, Equip, close)
;     needs its title "Aura Storage" read right before (StorageBox)
;   - before every click, a Roblox purchase prompt on screen is closed with
;     Esc (TaskEnv.BuyPrompt, never a click) and the swap stops (0, logged,
;     errors webhook)
; ---------------------------------------------------------------------------

class ObbyTask {
    static BlessingMs := 1500      ; how long the blessing pixel is polled after the route
    static PollMs := 150
    static PixelTol := 20
    static MaxRetries := 3
    static Sailor := "Sailor"
    static AuraIds := ["aura_open", "aura_search", "aura_equip", "aura_close"]
    static MenuMs := 700           ; after opening the storage / typing the search
    static SelectMs := 500         ; after clicking the tile / the button
    static ExpandMs := 400         ; after clicking buff_expand
    static AuraWaitMs := 3000      ; the button flips after Equip / Unequip
    static ClickTries := 3         ; Equip / Unequip clicks while the button keeps its old word
    static HoverMs := 300          ; the mouse rests on Equip this long before the click
    static ClickHoverMs := 150     ; ... and on tabs / the search box / tiles (_Click)
    static LogPickMs := 6000       ; the log has this long to name the aura after Equip (~2 s live; a slow PC more)
    static LogLagMs := 150000      ; the log's "Equipped" line can lag an unequip this long
    static SearchTries := 4
    ; Regular / Special tab buttons from aura_search (2560x1440, live
    ; 2026-10-31: search 1146,490; Regular 1248,445; Special 1693,445)
    static Tabs := [{dx: 102, dy: -45}, {dx: 547, dy: -45}]
    ; "Sailor" also lists "Sailor: Admiral" / "Sailor: Flying Dutchman", in
    ; front of plain Sailor (8th on the clip), and the tiles show the names
    ; as logos OCR cannot read live. So the tiles are clicked in turn
    ; (ScanTiles, TileCols per row, TileStep apart, 2560x1440) and the
    ; selected aura's name is read in plain text above [ Information ]
    ; (NameBox, from aura_equip like ButtonBox; live 2026-10-27: "Sailor /
    ; 1 in 12,000,000", only clean at NameScale 2).
    static ScanTiles := 16
    static TileCols := 8
    static TileStep := {dx: 108, dy: 110}
    static NameBox := {dx: -180, dy: -388, w: 350, h: 80}
    static NameScale := 2
    ; the panel is read at each of these (NameVerdict): real frames read
    ; plain Sailor at all of them, Sailor: Flying Dutchman whole only at 3
    ; ("Sailor: tchman" at 2, "Sailor:" at 4)
    static NameScales := [2, 3, 1]
    static PickMs := 400           ; after clicking a tile, before its name is read
    ; Speed (2026-11-13): this._tileHint = the tile each aura was last found
    ; on, per tab ("sailor|1" -> 11). _FindTile checks it first: Sailor was
    ; result 11 on all 52 logged swaps, ~25 s of tile reads every obby run.

    static LogPickEquips := 6      ; _LogPick: at most this many unread results equipped
    static ButtonBox := {dx: -150, dy: -35, w: 300, h: 70}
    ; "[ Information ]" lines under the name (2560x1440, live 2026-11-01:
    ; Equip 840,843, "Rolled at" ~670..900 x 650..700)
    static InfoBox := {dx: -190, dy: -205, w: 380, h: 90}
    static NeverRe := "i)delete|lock|sell|remove|discard"
    ; "Aura Storage" title, from aura_search (2560x1440 frames: "Auro Storage")
    static StorageBox := {dx: -200, dy: -135, w: 650, h: 85}
    static StorageRe := "i)st[o0]r[ao][go][e3]"
    ; a title read that missed is read again at this scale (live 2026-11-02
    ; 23:27: the PUMPKIN MOON banner's flames over the title; that frame
    ; reads "Storage" at 1x, "Auro Storage" at 2x)
    static StorageScale := 2
    ; the "[ Information ]" header of the storage's left panel, from
    ; aura_equip (2560x1440, every storage frame reads it, no game screen
    ; does): the storage is up even when a banner hides its title
    static PanelBox := {dx: -210, dy: -262, w: 260, h: 66}
    static PanelRe := "i)nf[o0]rmati[o0]n"
    static CloseTries := 3         ; clicks on the storage's X before giving up
    static TitleWaitMs := 3000     ; panel up, title unread: re-read this long (a banner passes)
    static TitlePollMs := 250
    static ClearTries := 4         ; ClearView rounds (one menu can hide another; four can be up)
    ; a result tile shows: at least TileInk pixels of luminance >= TileLum in
    ; its name rect (real frames: tiles 30..1450 of ~5100, empty slots 0 by
    ; night, day and Hell; the dim world behind the panel peaks ~130)
    static TileLum := 170
    static TileInk := 12

    name := "obby"
    priority := 5
    wear := ObbyTask.Sailor      ; the aura PutOnSailor puts on (MinionsTask reuses the swap with its own)
    _logMute := false            ; _LogPick saw no log line after an equip (this swap): no more equips
    logoOk := false              ; first result accepted when its name is an unreadable logo (_FindTile)

    __New(deps := "") {
        this._tileHint := Map()
        this._tabHint := Map()       ; aura -> the storage tab it was last found on (searched first)
        this._env := TaskEnv(deps)
        this._auraFn := TaskEnv.Dep(deps, "aura", "")
        if !IsObject(this._auraFn)
            this._auraFn := () => {known: false, name: ""}
        this._set := ""              ; {name, at}: the last aura change seen on the button
        this._owed := ""             ; {prev}: the aura still to put back after a halted run
        this._btn := ""              ; the button's last OCR read
        this._tab := 1               ; storage tab of the current search try (Tabs index)
        this._abort := false         ; a click was refused (no blind clicks): the swap stops
        if IsObject(this._env.cfg)
            ObbyTask.LoadKnown(this._env.cfg)
    }

    CanRun(state) {
        env := this._env
        if (!IsObject(env.cfg) || !env.cfg.Get("Obby.enabled", 0))
            return false
        if (env.Route(env.cfg.Get("Obby.route", "obby")) == "")
            return false
        ; the aura on now must be known (to put it back after): unknown, the
        ; obby would interrupt another task every interval only to skip itself
        return IsObject(this._AuraCal()) && this._Aura().known
    }

    Run(ctx) {
        env := this._env
        if !IsObject(env.cfg)
            return 0
        steps := env.Route(env.cfg.Get("Obby.route", "obby"))
        c := this._AuraCal()
        if (steps == "" || !IsObject(c))
            return 0
        sw := this.PutOnSailor(ctx)
        if !sw.ok {
            if sw.unknown {
                env.Problem("obby:aura", "obby: " sw.why ": obby skipped")
            } else if (sw.why != "stopped") {
                msg := "could not equip Sailor (" sw.why "): obby skipped"
                env.Log("obby: " msg)
                env.Report("errors", "Obby failed", msg, 0xE74C3C)
                ; the search's log pick can leave another aura on (Sailor:
                ; Admiral, live 2560x1440 11:10): the one from before back
                now := this._LogAura()
                if (sw.prev != "" && now != "?" && !ObbyTask.SameAura(now, sw.prev)) {
                    env.Log("obby: " now " went on during the search: " sw.prev " put back")
                    this.PutBack(ctx, {ok: true, had: false, prev: sw.prev})
                }
            }
            return 0
        }

        expand := env.cal.Point("buff_expand")
        pt := env.cal.Point("obby_blessing")
        check := (expand != "" && pt != "")
        retries := check ? ObbyTask.Retries(env.cfg.Get("Obby.retries", 1)) : 0
        io := env.io
        plays := 0, seen := false, stopped := false, unchecked := false
        try {
            Loop retries + 1 {
                if !Input.ResetToSpawn(ctx, io)
                    break
                if !Input.PlayRoute(steps, ctx, io)
                    break
                plays++
                if !check
                    break
                r := this._CheckBlessing(ctx, expand, pt)
                unchecked := (r < 0)
                seen := (r > 0)
                if (seen || unchecked || ctx.ShouldStop())
                    break
            }
        } finally {
            ; a preempt (merchant, potions) still respawns and puts the aura
            ; back; only a real halt (F3, pause, Roblox not in front) skips it,
            ; and then the aura is owed to the next run (2026-10-27 review: a
            ; preempted obby left Sailor on and the old aura was lost)
            stopped := ctx.ShouldStop()
            if !CleanupCtx.Halted(ctx) {
                cctx := CleanupCtx(ctx)
                Input.ResetToSpawn(cctx, io)
                this.PutBack(cctx, sw)
            } else {
                this.Owe(sw)
            }
        }
        if stopped
            return seen ? 1 : 0

        if seen {
            env.Log("obby: Basic Blessing claimed")
            env.Report("obby", "Obby", "Basic Blessing claimed")
            return 1
        }
        if !check {
            if (plays > 0) {
                env.Log("obby: ran the obby (unchecked: buff_expand / obby_blessing not calibrated)")
                env.Report("obby", "Obby", "ran the obby (unchecked: calibrate buff_expand and obby_blessing to check it)")
            }
            return 0
        }
        if unchecked {
            msg := "ran the obby, but the Basic Blessing was not checked: " this._why
            env.Log("obby: " msg)
            env.Report("errors", "Obby not checked", msg, 0xE74C3C)
            return 0
        }
        if (plays > 0) {
            msg := "the Basic Blessing never showed after " plays " run(s) (a jump missed? Test the obby route on Setup > Routes, or re-record it)"
            env.Log("obby: " msg)
            env.Report("errors", "Obby failed", msg, 0xE74C3C)
        }
        return 0
    }

    ; Sailor on. -> {ok, had (already on), prev (the aura before), unknown
    ; (the aura on now is not known: nothing done), why}.
    PutOnSailor(ctx) {
        c := this._AuraCal()
        if !IsObject(c)
            return {ok: false, had: false, prev: "", unknown: false
                , why: "the aura storage is not calibrated (Setup > Calibrate: aura_open, aura_search, aura_tile_rect, aura_equip, aura_close)"}
        ; the swap finishes on a preempt (it takes seconds); only a real halt
        ; cuts it short
        cctx := CleanupCtx(ctx)
        if IsObject(this._owed) {
            ; a run was halted with Sailor on: its aura from before still goes back
            r := this._SetAura(c, this.wear, true, cctx)
            return {ok: r > 0, had: false, prev: this._owed.prev, unknown: false, why: (r < 0) ? "stopped" : this._why}
        }
        cur := this._Aura()
        if !cur.known
            return {ok: false, had: false, prev: "", unknown: true
                , why: "the aura you have on is unknown (no 'Equipped' line in the Roblox log yet)"}
        ; the storage's button, not the log, says whether Sailor is on: after
        ; an unequip the log can say "Sailor" for minutes (live 2026-10-27),
        ; and then the aura before was none
        r := this._SetAura(c, this.wear, true, cctx, &was)
        had := (was = "on")
        prev := had ? this.wear : ObbyTask.SameAura(cur.name, this.wear) ? "" : cur.name
        if (r < 0 && !had)
            this.Owe({ok: true, had: false, prev: prev})   ; halted mid-swap: Sailor may be on
        return {ok: r > 0, had: had, prev: prev, unknown: false, why: (r < 0) ? "stopped" : this._why}
    }

    ; The aura from before PutOnSailor (info) back. -> true when done / nothing
    ; to do. Halted part way, the aura stays owed to the next PutOnSailor.
    PutBack(ctx, info) {
        if (!IsObject(info) || !info.ok || info.had)
            return true
        c := this._AuraCal()
        if !IsObject(c)
            return false
        cctx := CleanupCtx(ctx)
        ok := this._Restore(c, info.prev, cctx)
        if (ok || !cctx.ShouldStop())
            this._owed := ""                            ; done, or failed and reported
        else
            this.Owe(info)
        return ok
    }

    ; PutBack could not run (F3 / pause / Roblox not in front, or a route
    ; Record cancelled): the next PutOnSailor keeps info.prev as the aura to
    ; put back, instead of taking Sailor for the user's own aura.
    Owe(info) {
        if (IsObject(info) && info.ok && !info.had)
            this._owed := {ok: true, had: false, prev: info.prev}
    }

    Owed() => IsObject(this._owed) ? this._owed.prev : ""

    ; Obby.retries as a whole number in 0..MaxRetries (junk -> 1).
    static Retries(v) {
        if !IsNumber(v)
            return 1
        return Max(0, Min(ObbyTask.MaxRetries, Integer(v)))
    }

    ; Two aura names are the same aura (game font folded).
    static SameAura(a, b) => (GameLists.Fold(a) != "" && GameLists.Fold(a) == GameLists.Fold(b))

    ; The name panel's OCR names `aura`: every line but the rarity ("1 in
    ; 12,000,000", any line with a digit), joined, folds to the name, a
    ; letter of slack from 8. "Sailor:" + "Flying Dutchman" is not Sailor.
    ; What to type in the storage search: the name's longest word. The log
    ; writes names as ":Flushed:_Pumpkinity" / "Kyawthuite_Remembrance"
    ; (emoji codes, _ for spaces), which the search never matches
    ; (live 2026-11-01); the tiles are still checked by NameIs.
    static SearchText(name) {
        best := "", p := 1
        while (p := RegExMatch(String(name), "[A-Za-z]+", &m, p)) {
            if (StrLen(m[0]) > StrLen(best))
                best := m[0]
            p += m.Len
        }
        return (best != "") ? best : String(name)
    }

    static NameIs(text, aura) => ObbyTask.NameRead(text, aura) = "same"

    ; One read of the name panel against `aura` (exact name after folding:
    ; case, _ / : / spaces, the game font's o = a and l = i).
    ; -> "same" | "other" (a different aura: letters `aura` does not have,
    ; or "Sailor:" for Sailor, a name that goes on past it) | "unread"
    ; (nothing, or a partial / garbled read that could still be `aura`).
    ; "Sailor" and "Sailor: Admiral" never match each other either way.
    static NameRead(text, aura) {
        want := GameLists.Fold(aura)
        p := ObbyTask._NameParts(text)
        f := p.f
        if (f = "" || want = "")
            return "unread"
        if p.cont                                       ; "Sailor:" + a name the read lost
            return (StrLen(f) < StrLen(want) && SubStr(want, 1, StrLen(f)) == f) ? "unread" : "other"
        if ((f == want) || (StrLen(want) >= 8 && GameLists.Distance(f, want) <= 1))
            return "same"
        ; small UI (16:10 at 1440x900, live 2026-11-11): plain Sailor read
        ; 'Sanor'. Two letters off a 5+ letter name counts, unless the read
        ; is itself a real aura name (the search already narrowed the tiles)
        if (StrLen(want) >= 5 && Abs(StrLen(f) - StrLen(want)) <= 2 && GameLists.Distance(f, want) <= 2 && !ObbyTask._IsKnownOther(f, want))
            return "same"
        v := ObbyTask._Extra(f, want) > Max(1, StrLen(f) // 5) ? "other" : "unread"
        ; a read that is no real aura name is noise (logo fonts: Luminosity
        ; read 'LVIßTOSITY' / 'xvnmrosrrr', live 2026-11-10), not "another
        ; aura": it stays unread so the log check may try that tile. A real
        ; lookalike (Sailor: Admiral) is a known name and stays "other".
        if (v = "other" && !ObbyTask._IsKnown(f))
            v := "unread"
        return v
    }

    ; Folded names of every aura in data\auras.json (set by __New from the
    ; config; "" = no list, then every read counts as a real name).
    static Known := ""

    static _IsKnown(f) {
        if !(IsObject(ObbyTask.Known) && ObbyTask.Known.Count)
            return true
        if ObbyTask.Known.Has(f)
            return true
        for k in ObbyTask.Known
            if (Abs(StrLen(k) - StrLen(f)) <= 1 && GameLists.Distance(f, k) <= 1)
                return true
        return false
    }

    ; f is a known aura name other than want, or one letter off one that the
    ; search for want can list (its name holds want: Sailor: Admiral for
    ; Sailor). 'Sanor' is one letter off Solar too, but a Sailor search never
    ; lists Solar (live 1366x768, 2026-11-11)
    static _IsKnownOther(f, want) {
        if !(IsObject(ObbyTask.Known) && ObbyTask.Known.Count)
            return false
        if (f != want && ObbyTask.Known.Has(f))
            return true
        for k in ObbyTask.Known
            if (k != want && InStr(k, want) && Abs(StrLen(k) - StrLen(f)) <= 1 && GameLists.Distance(f, k) <= 1)
                return true
        return false
    }

    static LoadKnown(cfg) {
        m := Map()
        try {
            for e in Auras.List(cfg) {
                n := GameLists.Fold(e["name"])
                if (n != "")
                    m[n] := true
            }
        }
        if m.Count
            ObbyTask.Known := m
    }

    ; Reads of the same panel at several scales (NameScales) -> one verdict.
    ; "same" only when no read contradicts it: a read with letters the same
    ; read lacks, or one that reads the same name and then a colon
    ; ("Sailor:" next to "Sailor" is Sailor: Admiral cut short), makes it
    ; "unread". Else
    ; "other" when any read is another aura, else "unread".
    static NameVerdict(texts, aura) {
        same := "", other := false
        for t in texts {
            v := ObbyTask.NameRead(t, aura)
            if (v = "same" && same = "")
                same := ObbyTask._NameParts(t).f
            other := other || (v = "other")
        }
        if (same = "")
            return other ? "other" : "unread"
        for t in texts {
            p := ObbyTask._NameParts(t)
            if (p.f = "")
                continue
            if ((p.cont && p.f == same) || ObbyTask._Extra(p.f, same) > Max(1, StrLen(p.f) // 5))
                return "unread"
        }
        return "same"
    }

    ; The panel text's name lines (the rarity line left out: any line with a
    ; digit, or "i in" as 3x reads "1 in 80,000,000") -> {f: folded, cont:
    ; ends with a colon (the name goes on)}.
    static _NameParts(text) {
        s := ""
        for line in StrSplit(String(text), "`n", "`r") {
            ; the rarity on the name's line, misread without digits: 'Sailor
            ; npoo,ooo' / 'Sailor 12poopoo' for "1 in 100,000" (live 1600x900,
            ; 2560x1440): cut at the first word with a comma or a digit
            line := RegExReplace(RegExReplace(line, "(^|\s+)\S*[,\d]\S*.*$"), "(\s+\S{0,3})?\s+in(\s.*)?$")
            ; ...and with no digit or comma at all: "npoopoo" (live 2560x1440)
            line := RegExReplace(line, "i)(^|\s+)[nu1il2]{0,2}[po0][po0.]{3,}\s*$")
            if !RegExMatch(line, "\d|^\W*\S{0,2}\s+in(\s|$)")
                s .= line " "
        }
        return {f: GameLists.Fold(s), cont: RegExMatch(s, ":[^A-Za-z]*$") > 0}
    }

    ; Letters of a not matched in b (in order: a - the longest common
    ; subsequence). OCR drops letters; letters b lacks mean another name.
    static _Extra(a, b) {
        la := StrLen(a), lb := StrLen(b)
        if (la = 0 || lb = 0)
            return la
        prev := []
        Loop lb + 1
            prev.Push(0)
        Loop la {
            ch := SubStr(a, A_Index, 1)
            cur := [0]
            Loop lb
                cur.Push((ch == SubStr(b, A_Index, 1)) ? prev[A_Index] + 1 : Max(prev[A_Index + 1], cur[A_Index]))
            prev := cur
        }
        return la - prev[lb + 1]
    }

    ; Pure: px (Array of w*h 0xRRGGBB, a tile's name rect) shows a result
    ; tile (bright name / icon pixels), not an empty slot. Malformed -> false.
    static TileShown(px, w, h) {
        if !(px is Array && w > 0 && h > 0 && px.Length = w * h)
            return false
        n := 0
        for c in px {
            c := c & 0xFFFFFF
            if ((((c >> 16) & 0xFF) * 299 + ((c >> 8) & 0xFF) * 587 + (c & 0xFF) * 114) // 1000 >= ObbyTask.TileLum)
                if (++n >= ObbyTask.TileInk)
                    return true
        }
        return false
    }

    ; Result tile k (1 = top left) of the storage grid from the first tile's rect.
    static TileRect(first, k) {
        s := ObbyTask.TileStep, cols := ObbyTask.TileCols
        return {x: first.x + Mod(k - 1, cols) * s.dx, y: first.y + ((k - 1) // cols) * s.dy, w: first.w, h: first.h}
    }

    ; c's calibrated spots named (the ones it has), for ChatGuard.ClearFor.
    static _Spots(c, names*) {
        out := []
        for n in names
            if (IsObject(c) && c.HasOwnProp(n) && IsObject(c.%n%))
                out.Push(c.%n%)
        return out
    }

    ; -> {open, search, tile, equip, close} or "" (missing steps logged once).
    _AuraCal() {
        env := this._env
        c := {}
        for id in ObbyTask.AuraIds {
            p := env.Point(id)
            if (p == "")
                return ""
            c.%id% := p
        }
        r := env.Rect("aura_tile_rect")
        if (r == "")
            return ""
        c.aura_tile_rect := r
        return c
    }

    ; The aura worn now: the last change this task saw on the button for
    ; LogLagMs (the log's "Equipped" line only follows an unequip ~2 min
    ; later: live 2026-10-27), else the Roblox log (deps.aura).
    _Aura() {
        if (IsObject(this._set) && this._env.Now() - this._set.at < ObbyTask.LogLagMs)
            return {known: true, name: this._set.name}
        a := ""
        try a := (this._auraFn)()
        if !IsObject(a)
            return {known: false, name: ""}
        return {known: a.known ? true : false, name: String(a.name)}
    }

    ; The selected aura's name panel read at every NameScales scale.
    ; -> {v: NameVerdict, text: the NameScale read, all: the reads joined}
    _ReadName(c, aura) {
        n := ObbyTask.NameBox, texts := [], all := ""
        for s in ObbyTask.NameScales {
            t := String((this._env.ocrFn)(c.aura_equip.x + n.dx, c.aura_equip.y + n.dy, n.w, n.h, s))
            texts.Push(t)
            all .= t "|"
        }
        return {v: ObbyTask.NameVerdict(texts, aura), text: texts[1], all: all}
    }

    ; Speed (2026-11-13): the search starts on the tab the aura was found on
    ; last time (Eden: Special; the Regular pass before it cost ~4 s a swap).
    _TabOffset(aura) {
        t := this._tabHint.Has(StrLower(aura)) ? this._tabHint[StrLower(aura)] : 1
        return t - 1
    }

    ; Clicks the result tiles in turn until the selected aura's name is
    ; `aura` (it stays selected). -> its tile number | 0 none of the first
    ; ScanTiles | -1 stopped. first = the first tile's name (for the log).
    ; Every tile's verdict lands in this._tileReads (k -> "other" | "unread")
    ; for _LogPick, which never equips a tile that read as another aura.
    ; A read that did not settle (nothing, or the same text as the tile
    ; before: the panel still showing the last aura) is read once more
    ; after PickMs, so a stale name never marks the wanted tile "other".
    _FindTile(c, aura, ctx, &first) {
        env := this._env
        first := ""
        this._tileReads := Map()
        seen := "", last := ""
        tabName := (this._tab = 2 ? "Special" : "Regular")
        hintKey := StrLower(aura) "|" this._tab
        hint := this._tileHint.Has(hintKey) ? this._tileHint[hintKey] : 0
        order := []
        if (hint > 1 && hint <= ObbyTask.ScanTiles && this._TileHere(ObbyTask.TileRect(c.aura_tile_rect, hint)))
            order.Push(hint)                     ; where it was last time, first
        Loop ObbyTask.ScanTiles
            if !(order.Length && A_Index = hint)
                order.Push(A_Index)
        for k in order {
            if ctx.ShouldStop()
                return -1
            r := ObbyTask.TileRect(c.aura_tile_rect, k)
            if !this._TileHere(r) {
                ; an empty slot: no more results on this tab (and never a
                ; click there: it goes through into the world)
                env.Log("obby: result tile " k " on the " tabName " tab is empty: no more results there")
                break
            }
            if !this._Click({x: r.x + r.w // 2, y: r.y + r.h // 2}, ctx, c)
                return -1
            if !env.Wait(ObbyTask.PickMs, ctx)
                return -1
            rd := this._ReadName(c, aura)
            if (rd.v != "same" && (rd.v = "unread" || rd.all == last)) {
                if !env.Wait(ObbyTask.PickMs, ctx)
                    return -1
                rd := this._ReadName(c, aura)
            }
            last := rd.all
            text := rd.text
            if (k = 1)
                first := text
            this._tileReads[k] := rd.v
            seen .= (seen = "" ? "" : ", ") k " '" SubStr(Trim(RegExReplace(text, "\s+", " ")), 1, 24) "'"
            if (rd.v = "same") {
                env.Log("obby: " aura " is result " k " on the " tabName " tab (its name read)")
                this._tileHint[hintKey] := k
                this._tabHint[StrLower(aura)] := this._tab
                return k
            }
            ; the name in the first read but no match: every scale's read, to
            ; see which one said no (live 2560x1440: 'Sailor 12poopoo')
            if InStr(GameLists.Fold(text), GameLists.Fold(aura))
                env.Log("obby: tile " k " reads " rd.v ": '" SubStr(RegExReplace(rd.all, "\s+", " "), 1, 120) "'")
            ; logoOk: some auras' names show as a logo there that OCR cannot
            ; read (Eden, live 2026-10-31). Then the first result is taken
            ; when its panel reads nothing but its button reads Equip /
            ; Unequip (MinionsTask; the obby keeps the strict check).
            ; The button shows with nothing selected too (an empty search,
            ; live 2026-11-01), so the info panel must show the selected
            ; aura's lines ("Rolled at: ...", "With luck of ...").
            ; Special tab only: Luminosity's name is a logo too, and a search
            ; that did not take listed every Regular aura (2026-11-01: it
            ; equipped Luminosity for Eden)
            if (k = 1 && this.logoOk && this._tab = 2 && RegExReplace(rd.all, "[\s|]") = "" && this._Selected(c) && RegExMatch(this._Button(c), "^(on|off)$"))
                return 1
        }
        if (seen != "")
            env.Log("obby: no result on the " tabName " tab reads as " aura ": " SubStr(seen, 1, 300))
        return 0
    }

    ; Equip (equip=true) or unequip `aura` from the aura storage. -> 1 done
    ; (confirmed by the button flipping) | 0 not (this._why says why) | -1
    ; stopped. was = the button before any click: "on" | "off" | "".
    ; Stopped part way, the storage is still closed unless halted (Roblox may
    ; not be in front then): the next task must not find it open.
    ; The Aura Collections screen left open covers the storage: closed first,
    ; and looked for once more after a search whose first tile read nothing
    ; (the chat overlaps its title, so a read can miss it), then one retry.
    ; A click refused by the checks (no blind clicks, header) stops it too:
    ; 0, this._why says why.
    ; The Aura Storage scales evenly and stays centred where the rest of the
    ; UI stretches (16:10, live 1440x900): the whole swap maps in Screen
    ; mode "C" (the same pixels at 16:9).
    _SetAura(c, aura, equip, ctx, &was := "") {
        ; an early return (stopped while closing a Collections screen left
        ; open) left `was` unset and PutOnSailor threw (live 2026-11-10 23:31
        ; and 11-11 03:26, "local variable has not been assigned", Obby:316)
        was := ""
        old := Screen.Mode
        Screen.Mode := "C"
        try
            return this._SetAuraM(c, aura, equip, ctx, &was)
        finally
            Screen.Mode := old
    }

    _SetAuraM(c, aura, equip, ctx, &was := "") {
        if (this._Uncover(ctx) < 0)
            return -1
        env := this._env
        if Input.DailyUp(env.io, env.ocrFn) {           ; its tiles would read as the storage's
            this._why := "the Daily Rewards popup is over the game: not clicked"
            was := ""
            return 0
        }
        this._empty := false
        r := this._SetAuraOnce(c, aura, equip, ctx, &was)
        ; the popup may have come up during the swap
        if (r = 0 && (this._empty || Input.DailyUp(env.io, env.ocrFn)) && this._Uncover(ctx) = 1)
            r := this._SetAuraOnce(c, aura, equip, ctx, &was)
        ; done or not: no popup or Collections screen left over the game either
        if !CleanupCtx.Halted(ctx)
            this._Uncover(CleanupCtx(ctx))
        return r
    }

    Covered() {
        env := this._env
        if Input.PurchaseUp(env.io, env.ocrFn)
            return "purchase"
        if Input.DailyUp(env.io, env.ocrFn)
            return "daily rewards"
        if this.QuestUp()
            return "quest"
        if Input.CollectionsUp(env.io, env.ocrFn)
            return "collections"
        if this.InvUp()
            return "inventory"
        if this.ShopUp()
            return "ugc shop"
        if this.RaidUp()
            return "raid"
        if this.JockUp()
            return "jock dialog"
        c := this._AuraCal()
        if (IsObject(c) && Screen.WithMode("C", () => this._Open(c) || this._Panel(c)))
            return "storage"
        return ""
    }

    ; ClearView's lines per screen: [closed, not closed] ("" = none; the
    ; popups' lines come from _Uncover / BuyPrompt / _ShutStorage)
    static ClearLogs := Map(
        "quest", ["the Quest Board page was over the game: closed it", "the Quest Board page is over the game and was not closed"],
        "raid", ["the raid window was over the game: closed it", "the raid window is over the game and was not closed"],
        "inventory", ["the Inventory was over the game: closed it", "the Inventory is over the game and was not closed"],
        "ugc shop", ["the UGC Shop was over the game: closed it", "the UGC Shop is over the game and was not closed"],
        "jock dialog", ["Jock's dialog was over the game: Leave clicked, closed", "Jock's dialog is over the game and was not closed"],
        "storage", ["the Aura Storage window was open over the game: closed it", ""])

    ClearView(ctx) {
        env := this._env
        Loop ObbyTask.ClearTries {
            what := this.Covered()
            if (what = "" || ctx.ShouldStop())          ; halted: nothing sent (Roblox may not be in front)
                return what
            r := this.CloseCovered(what, ctx)
            if ((r = 1 || r = 2) && ObbyTask.ClearLogs.Has(what) && ObbyTask.ClearLogs[what][r] != "")
                env.Log("obby: " ObbyTask.ClearLogs[what][r])
            if (r < 0 || r = 2)
                return what
        }
        what := this.Covered()
        if (what != "")
            env.Log("obby: the " what " screen is still over the game")
        return what
    }

    ; Closes one Covered() screen, each by its own checked way (a purchase
    ; prompt: Esc, never a click). quiet: no "obby:" lines (Tidy logs).
    ; -> 1 closed (or gone) | 0 not up | 2 still up or refused | -1 stopped
    CloseCovered(what, ctx, quiet := false) {
        env := this._env
        switch what {
            case "purchase":
                if quiet
                    return Input.ClosePurchase(env.io, env.ocrFn) = 2 ? 2 : 1
                env.BuyPrompt("obby")                   ; Esc, logged (never a click)
                return 1
            case "daily rewards":
                r := quiet ? Input.CloseDaily(ctx, env.io, env.ocrFn) : this._Uncover(ctx)
                return (r < 0) ? -1 : (r = 2) ? 2 : 1
            case "collections":
                r := quiet ? Input.CloseCollections(ctx, env.io, env.ocrFn) : this._Uncover(ctx)
                return (r < 0) ? -1 : (quiet && r = 2) ? 2 : 1
            case "quest":
                return this._CloseQuest(ctx)
            case "raid":
                return this._CloseRaid(ctx)
            case "inventory":
                return Screen.WithMode("C", () => this._CloseInventory(ctx))
            case "ugc shop":
                return Screen.WithMode("C", () => this._CloseByX(ctx, () => this.ShopUp(), "the UGC Shop's X"))
            case "jock dialog":
                return this._CloseByX(ctx, () => this.JockUp(), "Jock's Leave", ObbyTask.JockLeave)
            case "storage":
                return Screen.WithMode("C", () => this._ShutStorage(this._AuraCal(), ctx)) ? 1 : 2
            case "title":
                r := Input.ClickPlay(ctx, env.io, env.ocrFn)
                return (r = 0) ? 1 : r
        }
        return 0
    }

    ; Tidy's names for the Covered() screens.
    static TidyLabels := Map("title", "title screen", "purchase", "purchase prompt", "daily rewards", "Daily Rewards popup"
        , "quest", "Quest Board page", "collections", "Aura Collections screen", "inventory", "Inventory"
        , "ugc shop", "UGC Shop", "raid", "raid window", "jock dialog", "Jock dialog", "storage", "Aura Storage")

    ; The App's between-tasks leftover (Tidy): every screen Covered() knows
    ; (full), or only a purchase prompt (after fishing / limbo: they open
    ; nothing else, and run between every chat check).
    TidyItem(full := true) {
        env := this._env
        names := Map()
        for k, v in ObbyTask.TidyLabels
            names[v] := k
        up := full ? () => this._TidyLabel(Input.TitleUp(env.io, env.ocrFn) ? "title" : this.Covered())
            : () => Input.TitleUp(env.io, env.ocrFn) ? ObbyTask.TidyLabels["title"]
                : Input.PurchaseUp(env.io, env.ocrFn) ? ObbyTask.TidyLabels["purchase"] : ""
        return {up: up, close: (label, ctx) => this.CloseCovered(names.Has(label) ? names[label] : "", ctx, true)}
    }

    ; The title screen alone (App, before a task is launched).
    TitleItem() {
        env := this._env
        return {up: () => Input.TitleUp(env.io, env.ocrFn) ? ObbyTask.TidyLabels["title"] : ""
            , close: (label, ctx) => this.CloseCovered("title", ctx, true)}
    }

    _TidyLabel(what) => (what = "") ? "" : ObbyTask.TidyLabels.Has(what) ? ObbyTask.TidyLabels[what] : what


    ; THE INVENTORY (L22 17:11:25, L26 22:40..23:13): left open over the game
    ; it ran through whole fights. Its title reads "Inventorv" over any
    ; background; its X needs no calibration (real frames inventory_open_*).
    static InvBox := {x: 1100, y: 365, w: 360, h: 50}
    static InvRe := "i)invent[o0]r[yv]"
    static InvX := [1884, 399]

    ; The title reads (one read).
    InvUp() => Screen.WithMode("C", () => this._Reads(ObbyTask.InvBox, ObbyTask.InvRe))

    ; THE UGC SHOP (L63 01:17:39 WINDY): E is also the shop keeper's interact
    ; key at spawn; the shop came up over the fight, the orb behind it. The
    ; same frame as the Inventory: its title in InvBox, its X at InvX. Only
    ; the X is ever clicked, never Purchase (Robux).
    static ShopRe := "i)(ugc|ugg|[il1|\x22'-]{1,3}g[cg]|l[il1]gg?)\s*sh[o0][opqn]"   ; reads "UGC Shoo" in InvBox; "UGG Shon", "IIGC Shon", "I-IGC Shoo" below 1440p
    ShopUp() => Screen.WithMode("C", () => this._Reads(ObbyTask.InvBox, ObbyTask.ShopRe))

    ; Closes it by its X and checks that it went. -> 1 closed | 0 not up |
    ; 2 still up or refused | -1 stopped
    _CloseInventory(ctx) => this._CloseByX(ctx, () => this.InvUp(), "the Inventory's X")

    ; THE JOCK DIALOG (L72 04:32..04:55, SAND STORM to RAINY): E is also the
    ; pumpkin-head NPC's interact key; his dialog stayed up over hunt after
    ; hunt. His name over the panel reads "Jock" (JockBox, 1x; real crops
    ; jock_dialog_*); his Leave button is a fixed point (JockLeave). Only
    ; Leave is ever clicked, never Jock's Shop, Bounty Hunt, Roll or a
    ; purchase. The Leave word itself is not read: the faint "Player will
    ; automatically rejoin." over the buttons blanks it on some frames.
    static JockBox := {x: 975, y: 925, w: 200, h: 60}
    static JockRe := "i)^\W*j[o0a]c(k|l<?)\W*$"
    static JockLeave := [1730, 1256]
    static NudgeMs := 150        ; after the nudge, before the click (_CloseByX)

    ; His name reads (one read).
    JockUp() => this._Reads(ObbyTask.JockBox, ObbyTask.JockRe)

    ; A window in the Inventory's frame (up = its title reads), closed by
    ; InvX (or pt). -> as _CloseInventory
    _CloseByX(ctx, up, what, pt := ObbyTask.InvX) {
        env := this._env, io := env.io
        if !up()
            return 0
        Loop ObbyTask.QuestTries {
            if ctx.ShouldStop()
                return -1
            g := Input.ClickGuard(io, ctx, what)
            if (g <= 0)
                return g ? -1 : 2
            io.MoveTo(pt[1], pt[2])
            if !env.Wait(ObbyTask.ClickHoverMs, ctx)
                return -1
            if Input.PurchaseUp(io, env.ocrFn)
                return 2
            if !up()
                return 1
            ; a nudge so Roblox sees the cursor over the button (L79 21:14:04:
            ; Jock's Leave clicked 3 times, still up; moved twice and clicked
            ; by hand at the same point, it closed)
            io.MoveTo(pt[1] + 3, pt[2] + 2)
            if !env.Wait(ObbyTask.NudgeMs, ctx)
                return -1
            io.MoveTo(pt[1], pt[2])
            io.ClickHere()
            if !env.Wait(ObbyTask.QuestMs, ctx)
                return -1
            if !up()
                return 1
        }
        return 2
    }

    ; THE RAID WINDOW (L45 14:15): E is also the Bossraid Portal's interact key;
    ; "The Amalgamation" opened over the fight and stayed. Only its X is ever
    ; clicked, never Go to Lobby or Play Solo (they leave the server).
    static RaidBox := {x: 1530, y: 885, w: 230, h: 45}
    static RaidRe := "i)selectw*s*diff|difficulty"
    static RaidX := [1897, 436]

    ; "Selected Difficulty" reads (one read).
    RaidUp() => this._Reads(ObbyTask.RaidBox, ObbyTask.RaidRe)

    ; As _CloseInventory. -> 1 closed | 0 not up | 2 still up or refused | -1 stopped
    _CloseRaid(ctx) {
        env := this._env, io := env.io, pt := ObbyTask.RaidX
        if !this.RaidUp()
            return 0
        Loop ObbyTask.QuestTries {
            if ctx.ShouldStop()
                return -1
            g := Input.ClickGuard(io, ctx, "the raid window's X")
            if (g <= 0)
                return g ? -1 : 2
            io.MoveTo(pt[1], pt[2])
            if !env.Wait(ObbyTask.ClickHoverMs, ctx)
                return -1
            if Input.PurchaseUp(io, env.ocrFn)
                return 2
            if !this.RaidUp()
                return 1
            io.ClickHere()
            if !env.Wait(ObbyTask.QuestMs, ctx)
                return -1
            if !this.RaidUp()
                return 1
        }
        return 2
    }

    ; THE QUEST BOARD PAGE (live 2026-11-03 18:27 and 18:32): E is also the
    ; board's interact key, a skill pressed in its reach opened the page
    ; ("Snowy Breakthrough"...), the fight's F and V ran behind it, and it
    ; frees the cursor. Its title changes with the quest; "Objects" over
    ; the panel does not (QuestBox, 2560x1440; real crops quest_page_*).
    ; Esc opens the Roblox menu over it and a respawn leaves it up (clip
    ; 183351): only its Exit word closes it. Accept, Dismiss and the arrows
    ; are QuestsTask's: never clicked here.
    static QuestBox := {x: 2060, y: 490, w: 380, h: 80}
    static QuestRe := "i)[o0]bjects"
    static QuestExitBox := {x: 1200, y: 1236, w: 160, h: 44}
    static QuestExitRe := "i)ex[il1|]t"
    static QuestExit := [1280, 1256]
    static QuestTries := 3        ; clicks on Exit before giving up
    static QuestMs := 500         ; after the click

    ; The page reads (one read).
    QuestUp() => this._Reads(ObbyTask.QuestBox, ObbyTask.QuestRe)

    _Reads(box, re) {
        env := this._env
        if (!IsObject(env.ocrFn) && !HasMethod(env.io, "Ocr"))
            return false
        return RegExMatch(Input._Read(env.io, box, env.ocrFn), re) > 0
    }

    ; Closes the page by its Exit and checks that it went. A click only with
    ; the page and the word Exit read right then, no purchase prompt up
    ; (those: Esc, the caller's) and Input.ClickGuard's yes.
    ; -> 0 not up | 1 was up, closed | 2 still up (given up or refused) |
    ; -1 stopped
    _CloseQuest(ctx) {
        env := this._env, io := env.io, pt := ObbyTask.QuestExit
        if !this.QuestUp()
            return 0
        Loop ObbyTask.QuestTries {
            if ctx.ShouldStop()
                return -1
            g := Input.ClickGuard(io, ctx, "the Quest Board page's Exit")
            if (g <= 0)
                return g ? -1 : 2
            io.MoveTo(pt[1], pt[2])
            if !env.Wait(ObbyTask.ClickHoverMs, ctx)
                return -1
            if Input.PurchaseUp(io, env.ocrFn)
                return 2
            if !this.QuestUp()
                return 1
            if !this._Reads(ObbyTask.QuestExitBox, ObbyTask.QuestExitRe)
                return 2
            io.ClickHere()
            if !env.Wait(ObbyTask.QuestMs, ctx)
                return -1
            if !this.QuestUp()
                return 1
        }
        return 2
    }

    ; Input.CloseDaily, then Input.CloseCollections, logged. -> as they: 2
    ; one is still up, 1 one was closed
    _Uncover(ctx) {
        d := Input.CloseDaily(ctx, this._env.io, this._env.ocrFn)
        if (d < 0)
            return -1
        if (d = 1)
            this._env.Log("obby: the Daily Rewards popup was over the game: closed it")
        else if (d = 2)
            this._env.Log("obby: the Daily Rewards popup is over the game and was not closed")
        r := Input.CloseCollections(ctx, this._env.io, this._env.ocrFn)
        if (r = 1)
            this._env.Log("obby: the Aura Collections screen was open: closed it")
        else if (r = 2)
            this._env.Log("obby: the Aura Collections screen is open and would not close")
        return (r < 0) ? -1 : Max(r, d)
    }

    _SetAuraOnce(c, aura, equip, ctx, &was) {
        this._opened := false, this._closed := false, this._abort := false
        ; below 1440p the chat lies over the storage's button (and more):
        ; hidden first, shown again after the task (ChatGuard, App._Tidy)
        if (ChatGuard.ClearFor(this._env.io, ctx, ObbyTask._Spots(c, "aura_open", "aura_search", "aura_equip", "aura_close", "aura_tile_rect")*) < 0)
            return -1
        try {
            r := this._SetAuraIn(c, aura, equip, ctx, &was)
            return this._abort ? 0 : r
        } finally {
            if (this._opened && !this._closed && !CleanupCtx.Halted(ctx))
                this._ShutStorage(c, CleanupCtx(ctx))
        }
    }

    ; Closes the Aura Storage window and checks that it went (live
    ; 2026-11-02 23:29: one unchecked click on its X, and the storage stayed
    ; open over the whole hunt). Its X (aura_close) is clicked only while its
    ; title reads and no purchase prompt is up (a prompt: Esc, never a
    ; click), shift lock off (Input.ClickGuard, a refusal logged there), the
    ; mouse resting on it first (Roblox drops a click right after a move),
    ; CloseTries times at most. Its panel up but its title
    ; unread (23:27: a biome banner over the title): the title is re-read
    ; for TitleWaitMs, then the storage's own sidebar button (aura_open, a
    ; HUD button: never a click into the world) toggles it shut once.
    ; Never a click on anything inside the storage but its X.
    ; -> true closed (or never open) | false still up (logged) or halted
    _ShutStorage(c, ctx) {
        if !IsObject(c)
            return true
        env := this._env
        io := env.io
        tries := 0, waited := 0, toggled := false
        ChatGuard.ClearFor(io, ctx, ObbyTask._Spots(c, "aura_open", "aura_close")*)
        Loop ObbyTask.CloseTries + 8 + ObbyTask.TitleWaitMs // ObbyTask.TitlePollMs {
            if env.BuyPrompt("obby")
                continue
            if this._Open(c) {
                if (tries >= ObbyTask.CloseTries)
                    break
                if (Input.ClickGuard(io, ctx, "the Aura Storage X") <= 0)
                    return false
                tries++
                io.MoveTo(c.aura_close.x, c.aura_close.y)
                if !env.Wait(ObbyTask.ClickHoverMs, ctx)
                    return false
                if (Input.PurchaseUp(io, env.ocrFn) || !this._Open(c))
                    continue
                io.ClickHere()
                if !env.Wait(ObbyTask.SelectMs, ctx)
                    return false
                continue
            }
            if !this._Panel(c)
                return true
            if (waited < ObbyTask.TitleWaitMs) {
                if !env.Wait(ObbyTask.TitlePollMs, ctx)
                    return false
                waited += ObbyTask.TitlePollMs
                continue
            }
            if toggled
                break
            toggled := true
            if (Input.ClickGuard(io, ctx, "the Aura Storage sidebar button") <= 0)
                return false
            env.Log("obby: the Aura Storage panel shows but its title does not read: its sidebar button pressed to close it")
            io.MoveTo(c.aura_open.x, c.aura_open.y)
            if !env.Wait(ObbyTask.ClickHoverMs, ctx)
                return false
            if Input.PurchaseUp(io, env.ocrFn)
                continue
            io.ClickHere()
            if !env.Wait(ObbyTask.MenuMs, ctx)
                return false
        }
        if !(this._Open(c) || this._Panel(c))
            return true
        env.Log("obby: the Aura Storage window would not close: close it yourself (its X, top right)")
        env.Report("errors", "Aura Storage left open", "The Aura Storage window would not close: close it yourself (its X, top right).", 0xE74C3C)
        return false
    }

    ; The Aura Storage window is open: its title reads (StorageBox; a miss
    ; is read again at StorageScale).
    _Open(c) {
        b := ObbyTask.StorageBox
        x := c.aura_search.x + b.dx, y := c.aura_search.y + b.dy
        if RegExMatch(String((this._env.ocrFn)(x, y, b.w, b.h)), ObbyTask.StorageRe)
            return true
        return RegExMatch(String((this._env.ocrFn)(x, y, b.w, b.h, ObbyTask.StorageScale)), ObbyTask.StorageRe) > 0
    }

    ; The storage's left panel shows ("[ Information ]", PanelBox): it is up
    ; even when its title does not read. Never a reason to click inside it.
    _Panel(c) {
        b := ObbyTask.PanelBox
        return RegExMatch(String((this._env.ocrFn)(c.aura_equip.x + b.dx, c.aura_equip.y + b.dy, b.w, b.h)), ObbyTask.PanelRe) > 0
    }

    ; The title, re-read for TitleWaitMs while the panel shows (a biome
    ; banner over the title passes). -> true when it read
    _OpenWait(c) {
        if this._Open(c)
            return true
        waited := 0
        while (waited < ObbyTask.TitleWaitMs && this._Panel(c)) {
            this._env.Wait(ObbyTask.TitlePollMs)
            waited += ObbyTask.TitlePollMs
            if this._Open(c)
                return true
        }
        return false
    }

    ; Result tile rect r shows a tile (TileShown on its pixels).
    _TileHere(r) {
        px := ""
        try px := (this._env.rectFn)(r.x, r.y, r.w, r.h)
        return ObbyTask.TileShown(px, r.w, r.h)
    }

    ; Right before a click: a purchase prompt up -> closed with Esc, refused;
    ; storage (c given) and its title not read -> refused. Refused ->
    ; this._abort, this._why, true.
    _Refused(c := "") {
        if this._env.BuyPrompt("obby") {
            this._abort := true
            this._why := "a Roblox purchase prompt was on screen: closed with Esc, swap stopped"
            return true
        }
        if (IsObject(c) && !this._OpenWait(c)) {
            this._abort := true
            this._why := "the Aura Storage window is not open (its title did not read): not clicked"
            this._env.Log("obby: " this._why)
            return true
        }
        return false
    }

    ; settings.ini [Auras] equipFirst: swaps equip the first search result
    ; without reading names or the button (EQUIP FIRST above).
    static EquipFirst(cfg) {
        v := 0
        if IsObject(cfg)
            try v := cfg.Get("Auras.equipFirst", 0)
        return v ? true : false
    }

    _SetAuraIn(c, aura, equip, ctx, &was) {
        env := this._env
        io := env.io
        this._why := ""
        was := ""
        this._logMute := false                  ; _LogPick: no log line once -> no more equips in this swap
        if ObbyTask.EquipFirst(env.cfg)
            return this._SetAuraFirst(c, aura, equip, ctx, &was)
        ; left open (a halted run): no click on its button (it would close it);
        ; its panel up with the title hidden (a banner) counts as open
        if !this._Open(c) && !this._Panel(c) {
            if !this._Click(c.aura_open, ctx)
                return -1
            if !env.Wait(ObbyTask.MenuMs, ctx)
                return -1
        }
        this._opened := true
        if !this._OpenWait(c) {
            ; covered by the Aura Collections screen? (_SetAura looks once more)
            this._empty := true
            this._why := "the Aura Storage window did not open (its title did not read)"
            return 0
        }
        found := 0, text := "", picked := 0
        Loop ObbyTask.SearchTries {
            if ctx.ShouldStop()
                return -1
            ; the storage has two tabs and searches only the open one: Eden
            ; is under Special (live 2026-10-31), Sailor under Regular. The
            ; tries take Regular, Special, Regular, ... in turn.
            this._tab := Mod(A_Index - 1 + this._TabOffset(aura), ObbyTask.Tabs.Length) + 1
            tab := ObbyTask.Tabs[this._tab]
            if !this._Click({x: c.aura_search.x + tab.dx, y: c.aura_search.y + tab.dy}, ctx, c)
                return -1
            if !env.Wait(ObbyTask.SelectMs, ctx)
                return -1
            ; hover first: a dropped click left the search empty, so the tab
            ; listed every aura (2026-11-01)
            if !this._Click(c.aura_search, ctx, c)
                return -1
            Input.ClearText(io)
            Input.TypeText(ObbyTask.SearchText(aura), io)
            if !env.Wait(ObbyTask.MenuMs, ctx)
                return -1
            found := this._FindTile(c, aura, ctx, &text)
            if (found < 0)
                return -1
            if found
                break
            ; no tile's name read right (a logo, a garbled read): equip the
            ; results in turn and let the Roblox log say which went on
            if equip {
                picked := this._LogPick(c, aura, ctx)
                if (picked < 0)
                    return -1
                if picked
                    break
            }
        }
        done := false, seen := false
        if picked {
            done := true, seen := true, was := "off"
        } else if !found {
            this._empty := Trim(text) = ""
            this._why := "no '" aura "' in the aura storage search (first tile's name read: '" SubStr(Trim(RegExReplace(text, "\s+", " ")), 1, 40) "')"
        } else {
            st := this._Button(c)
            was := st
            if (st = "never") {
                this._why := "the button reads '" Trim(this._btn) "', not Equip: not clicked"
            } else if (st = (equip ? "on" : "off")) {
                done := true, seen := true      ; already as wanted
            } else if (st = (equip ? "off" : "on")) {
                done := true
                ; the button flips at once (Equip <-> Unequip); the log's
                ; "Equipped" line only follows an unequip ~2 min later.
                ; Roblox can drop a click on a button the mouse just reached
                ; (live 2026-10-31: Eden's Equip): still the old word after
                ; AuraWaitMs -> one more click, from a small move
                Loop ObbyTask.ClickTries {
                    if (A_Index > 1 && this._Button(c) != (equip ? "off" : "on"))
                        break                           ; neither word: no blind click
                    ; the mouse rests on the button first: a click 30 ms after
                    ; the move was dropped twice in a row (live 2026-11-01)
                    if (A_Index > 1)
                        io.MoveTo(c.aura_equip.x + 6, c.aura_equip.y + 4)      ; off and back: a fresh hover
                    io.MoveTo(c.aura_equip.x, c.aura_equip.y)
                    if !env.Wait(ObbyTask.HoverMs, ctx)
                        return -1
                    if this._Refused(c)
                        return -1
                    Auras.Quiet(Auras.QuietMs)       ; our swap: no clip (a longer join quiet stays)
                    io.ClickHere()
                    waited := 0
                    Loop {
                        if !env.Wait(ObbyTask.PollMs, ctx)
                            return -1
                        waited += ObbyTask.PollMs
                        if (this._Button(c) = (equip ? "on" : "off")) {
                            seen := true
                            break
                        }
                        if (waited >= ObbyTask.AuraWaitMs)
                            break
                    }
                    if seen
                        break
                }
            } else {
                this._why := "the button reads '" Trim(this._btn) "', not " (equip ? "Equip" : "Unequip") ": not clicked"
            }
        }
        this._closed := this._ShutStorage(c, ctx)
        if !env.Wait(ObbyTask.SelectMs, ctx)
            return -1
        env.BuyPrompt("obby")                   ; after the last click: a prompt is closed and reported
        if !done
            return 0
        if seen {
            this._set := {name: equip ? aura : "", at: env.Now()}
            return 1
        }
        ; no log fallback: it lags an unequip by minutes and would confirm
        ; the opposite of what the click did (2026-10-27 review)
        this._why := "the button never turned to " (equip ? "Unequip" : "Equip") " after the click"
        return 0
    }

    ; [Auras] equipFirst: the first search result equipped (or unequipped),
    ; no name or button read (EQUIP FIRST above). -> as _SetAuraIn; was =
    ; "on" | "off" from the log / the last swap ("" unknown and not clicked).
    _SetAuraFirst(c, aura, equip, ctx, &was) {
        env := this._env
        io := env.io
        cur := this._Aura()
        on := (cur.known && ObbyTask.SameAura(cur.name, aura)) ? true : false
        if (cur.known && on = (equip ? true : false)) {
            ; already as wanted: a click on Equip would toggle it back
            was := on ? "on" : "off"
            return 1
        }
        ; left open (a halted run): no click on its button (it would close it)
        if !this._Open(c) && !this._Panel(c) {
            if !this._Click(c.aura_open, ctx)
                return -1
            if !env.Wait(ObbyTask.MenuMs, ctx)
                return -1
        }
        this._opened := true
        if !this._OpenWait(c) {
            this._empty := true
            this._why := "the Aura Storage window did not open (its title did not read)"
            return 0
        }
        text := ObbyTask.SearchText(aura)
        tile := "", tabName := "", done := false
        ; Regular, Special, Regular, ... (Eden is under Special). When
        ; equipping, the Roblox log says which aura went on: a first result
        ; that is another aura (live 2026-11-11: "Eden" listed something on
        ; the Regular tab) sends the search on to the other tab; no log line
        ; at all keeps the click (nothing better to go by).
        Loop ObbyTask.SearchTries {
            if (ctx.ShouldStop() || done)
                break
            this._tab := Mod(A_Index - 1 + this._TabOffset(aura), ObbyTask.Tabs.Length) + 1
            tab := ObbyTask.Tabs[this._tab]
            tabName := (this._tab = 2 ? "Special" : "Regular")
            if !this._Click({x: c.aura_search.x + tab.dx, y: c.aura_search.y + tab.dy}, ctx, c)
                return -1
            if !env.Wait(ObbyTask.SelectMs, ctx)
                return -1
            if !this._Click(c.aura_search, ctx, c)
                return -1
            Input.ClearText(io)
            Input.TypeText(text, io)
            if !env.Wait(ObbyTask.MenuMs, ctx)
                return -1
            r := ObbyTask.TileRect(c.aura_tile_rect, 1)
            if !this._TileHere(r) {                     ; never a click on an empty slot
                env.Log("obby: no result for '" text "' on the " tabName " tab")
                continue
            }
            tile := r
            if !this._Click({x: tile.x + tile.w // 2, y: tile.y + tile.h // 2}, ctx, c)
                return -1
            if !env.Wait(ObbyTask.PickMs, ctx)
                return -1
            ; Equip at its calibrated point only, the mouse resting on it first
            io.MoveTo(c.aura_equip.x, c.aura_equip.y)
            if !env.Wait(ObbyTask.HoverMs, ctx)
                return -1
            if this._Refused(c)
                return -1
            before := this._LogAura()
            Auras.Quiet(Auras.QuietMs)
            io.ClickHere()
            was := equip ? "off" : "on"
            if !equip {
                done := true
                env.Log("obby: equip first: the first result for '" text "' on the " tabName " tab unequipped as " aura " (names not read)")
                break
            }
            ; the log's aura from before the click is no verdict: its new
            ; line follows ~2 s later (a 250 ms read named the old aura and
            ; sent the swap on to the other tab's first result, which went on)
            got := this._LogChange(before, ctx, &stopped)
            if stopped
                return -1
            ; the searched text in its name counts (the option takes what the
            ; search lists first: "Sailor: Admiral" for Sailor), anything else not
            if (got = "?" || ObbyTask.SameAura(got, aura) || InStr(GameLists.Fold(got), GameLists.Fold(text))) {
                done := true
                env.Log("obby: equip first: the first result for '" text "' on the " tabName " tab equipped as " aura (got = "?" ? " (names not read, no log line)" : " (the log agrees)"))
                break
            }
            env.Log("obby: equip first: the first result on the " tabName " tab is " got ", not " aura ": trying the other tab")
        }
        if (!done && !IsObject(tile)) {
            this._empty := true
            this._why := "no '" aura "' in the aura storage search (no result tile showed)"
        } else if !done
            this._why := "the first results were other auras (the log named them)"
        this._closed := this._ShutStorage(c, ctx)
        if !env.Wait(ObbyTask.SelectMs, ctx)
            return -1
        env.BuyPrompt("obby")                   ; after the last click: a prompt is closed and reported
        if !done
            return 0
        this._set := {name: equip ? aura : "", at: env.Now()}
        return 1
    }

    ; The button around aura_equip -> "on" (Unequip: the selected aura is
    ; worn) | "off" (Equip) | "never" (delete / lock / sell...) | "" (unread).
    ; A click after the mouse rested on the spot (Roblox drops clicks that
    ; arrive right after a move), checked right before (_Refused; c given =
    ; a click on the storage). -> false when stopped or refused.
    _Click(pt, ctx, c := "") {
        io := this._env.io
        io.MoveTo(pt.x, pt.y)
        if !this._env.Wait(ObbyTask.ClickHoverMs, ctx)
            return false
        if this._Refused(c)
            return false
        io.ClickHere()
        return true
    }

    ; The log's aura right now: name, or "?" when unknown.
    _LogAura() {
        a := ""
        try a := (this._auraFn)()
        return (IsObject(a) && a.known) ? String(a.name) : "?"
    }

    ; Equip the current results one by one until the Roblox log names aura,
    ; and stop there. A result whose name read as another aura (_FindTile's
    ; this._tileReads "other") is never equipped; at most LogPickEquips are.
    ; -> 1 on | 0 not among them (or no log) | -1 stopped
    _LogPick(c, aura, ctx) {
        env := this._env
        io := env.io
        if (this._LogAura() == "?" || this._logMute)
            return 0
        reads := (this.HasOwnProp("_tileReads") && this._tileReads is Map) ? this._tileReads : Map()
        equips := 0
        Loop ObbyTask.ScanTiles {
            if (equips >= ObbyTask.LogPickEquips)
                return 0
            if (reads.Has(A_Index) && reads[A_Index] = "other")
                continue                                ; its name read: another aura
            r := ObbyTask.TileRect(c.aura_tile_rect, A_Index)
            if !this._TileHere(r)
                return 0                                ; an empty slot: past the last result (never clicked)
            if !this._Click({x: r.x + r.w // 2, y: r.y + r.h // 2}, ctx, c)
                return -1
            if !env.Wait(ObbyTask.PickMs, ctx)
                return -1
            if !this._Selected(c)
                return 0                                ; past the last result
            st := this._Button(c)
            if (st = "on") {
                if ObbyTask.SameAura(this._LogAura(), aura)
                    return 1
                continue
            }
            if (st != "off")
                continue
            if (this._ReadName(c, aura).v = "other")
                continue                                ; its name reads now: another aura
            io.MoveTo(c.aura_equip.x, c.aura_equip.y)
            if !env.Wait(ObbyTask.HoverMs, ctx)
                return -1
            if this._Refused(c)
                return -1
            before := this._LogAura()
            Auras.Quiet(Auras.QuietMs)
            equips++
            io.ClickHere()
            ; only a CHANGE of the log's aura belongs to this click: a late
            ; line for the result before, read while the next one was being
            ; equipped, said "found" with that other aura on
            got := this._LogChange(before, ctx, &stopped)
            if stopped
                return -1
            if (ObbyTask.SameAura(got, aura) || (got = "?" && ObbyTask.SameAura(before, aura))) {
                this._set := {name: aura, at: env.Now()}
                this._tabHint[StrLower(aura)] := this._tab
                env.Log("obby: " aura " found by the log (its name did not read)")
                return 1
            }
            if (got = "?") {
                ; no line: which aura is on is unknown, so no more are tried
                env.Log("obby: result " A_Index " equipped, but the Roblox log named no aura after it: no more results tried")
                this._logMute := true
                return 0
            }
            env.Log("obby: result " A_Index " is " got ", not " aura)
        }
        return 0
    }

    ; Waits up to LogPickMs for the log's aura to change from before (the
    ; "Equipped" line follows the click by ~2 s, live 2026-11-10; the first
    ; reads still name the aura from before). -> the new name ("" = none) |
    ; "?" no change; stopped := true when halted.
    _LogChange(before, ctx, &stopped) {
        stopped := false, waited := 0
        Loop {
            if !this._env.Wait(250, ctx) {
                stopped := true
                return "?"
            }
            waited += 250
            got := this._LogAura()
            if (got != "?" && got != before)
                return got
            if (waited >= ObbyTask.LogPickMs)
                return "?"
        }
    }

    ; An aura is selected: its info lines read in InfoBox (from aura_equip).
    _Selected(c) {
        b := ObbyTask.InfoBox
        t := String((this._env.ocrFn)(c.aura_equip.x + b.dx, c.aura_equip.y + b.dy, b.w, b.h))
        return RegExMatch(t, "i)r[o0][lI1|]{2}ed|[lI1|]uck") > 0
    }

    _Button(c) {
        b := ObbyTask.ButtonBox
        this._btn := String((this._env.ocrFn)(c.aura_equip.x + b.dx, c.aura_equip.y + b.dy, b.w, b.h))
        if RegExMatch(this._btn, ObbyTask.NeverRe)
            return "never"
        if RegExMatch(this._btn, "i)n\s*equ")      ; "Unequip", or "nequip" with the U lost
            return "on"
        return RegExMatch(this._btn, "i)equip") ? "off" : ""
    }

    ; After the run: the previous aura back (or Sailor off when there was none).
    _Restore(c, prev, ctx) {
        env := this._env
        r := (prev != "") ? this._SetAura(c, prev, true, ctx) : this._SetAura(c, this.wear, false, ctx)
        if (r > 0) {
            env.Log("obby: " (prev != "" ? prev " equipped again" : this.wear " unequipped"))
            return true
        }
        if (r = 0) {
            msg := (prev != "" ? "could not equip " prev " again" : "could not unequip " this.wear) " (" this._why "): put it back by hand"
            env.Log("obby: " msg)
            env.Report("errors", "Obby: aura not restored", msg, 0xE74C3C)
        }
        return false
    }

    ; Expand the buff list, poll the blessing pixel, collapse it again.
    ; buff_expand is clicked only while it shows its calibrated colour and
    ; no purchase prompt is up (a click on an empty spot can go through
    ; into the world, live 2026-11-02); the collapse click only when the
    ; blessing showed (the list is open) or the button still shows. The
    ; prompt guard runs after each click.
    ; -> 1 seen | 0 not seen | -1 not checked (refused or a prompt: this._why)
    _CheckBlessing(ctx, expand, pt) {
        env := this._env
        if env.BuyPrompt("obby") {
            this._why := "a Roblox purchase prompt was on screen (closed with Esc)"
            return -1
        }
        if !(env.pixelFn)(expand.x, expand.y, expand.color, ObbyTask.PixelTol) {
            this._why := "the buff list button (buff_expand) does not show its calibrated colour: not clicked (recalibrate it if this repeats)"
            env.Log("obby: " this._why)
            return -1
        }
        env.Click(expand)
        if env.BuyPrompt("obby") {
            this._why := "a Roblox purchase prompt came up after the buff_expand click (closed with Esc)"
            return -1
        }
        seen := false
        if env.Wait(ObbyTask.ExpandMs, ctx) {
            waited := 0
            Loop {
                if (env.pixelFn)(pt.x, pt.y, pt.color, ObbyTask.PixelTol) {
                    seen := true
                    break
                }
                if (waited >= ObbyTask.BlessingMs || !env.Wait(ObbyTask.PollMs, ctx))
                    break
                waited += ObbyTask.PollMs
            }
        }
        if (env.Unsafe("obby") = "" && (seen || (env.pixelFn)(expand.x, expand.y, expand.color, ObbyTask.PixelTol))) {
            env.Click(expand)                      ; collapsed again
            env.Wait(ObbyTask.ExpandMs, ctx)
            env.BuyPrompt("obby")
        } else
            env.Log("obby: buff_expand does not show: the buff list is not collapsed (no blind click)")
        return seen ? 1 : 0
    }
}
