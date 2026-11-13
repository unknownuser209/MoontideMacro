#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\..\PotionSafety.ahk
#Include %A_LineFile%\..\..\Input.ahk
#Include %A_LineFile%\..\..\Ocr.ahk
#Include %A_LineFile%\..\..\Pixel.ahk
#Include %A_LineFile%\..\..\Calibrate.ahk
#Include %A_LineFile%\..\..\Biomes.ahk
#Include %A_LineFile%\..\..\Scheduler.ahk
; ---------------------------------------------------------------------------
; PotionsTask: uses the rare biome's potion list (spec 4.6 / 4.6a).
; THIS CLICKS "Use" ON REAL POTIONS. Every doubt resolves to NOT clicking.
;
;   t := PotionsTask(deps)           deps Map:
;     cfg     Config (required)  General.dryRun (default 1) / Potions.dryRun
;             Potions.tileScan (6, 1..12) result tiles OCR'd per search
;             Potions.sigReads (3, 1..5)  amount box reads per check (see _AmountOk)
;     safety  PotionSafety (required): ONE instance per run, built with an
;             ABSOLUTE usage path, e.g. PotionsTask.DefaultUsagePath()
;     state   object with .biome / .rareActive (required; BiomeEvents sets them)
;     wh      object with Send(event, title, desc, color, opts) (Webhook)
;     log     callable(text)
;     io      Input backend (default real input)
;     ocr     callable(rect, scale) -> text (default Ocr.Read on the rect)
;     sig     callable(rect, storedSig) -> live signature of the rect with
;             the stored one's grid (default Pixel.SigLike)
;     cal     object with Point(id) / Rect(id) / Sig(id) (default Calibrate)
;     active  callable -> true while Roblox is the foreground window
;             (default WinActive("ahk_exe RobloxPlayerBeta.exe")); checked
;             before every click and key
;     poll    callable, run before every biome re-check. The main loop MUST
;             pass one that polls LogWatch and feeds the events to
;             BiomeEvents.Handle. Without it (and not dry run) every potion
;             is refused (reason no_poll, one errors webhook).
;   state.rareTs must equal the event ts (BiomeEvents sets it on a live
;   rare event), so a newer rare event of the same biome ends the old one.
;   PotionsTask.busy (static) is true while a potion is being handled; Clip
;   defers its hotkey while it is set.
;   t.name = "potions", t.priority = 1   (Scheduler task contract)
;   t.Queue(biome, ts)   BiomeEvents calls this on a LIVE rare biome event.
;                        One pending slot: a newer event replaces an older
;                        one (reported "superseded").
;   t.CanRun(state)      true while an event is pending
;   t.Run(ctx)           handles the pending event; ctx.ShouldStop() (F3,
;                        pause) is checked before every click
;   t.timing             Map of waits in ms (see DefaultTiming)
;
; Biome potion list (data\biomes.json): "potions": [{"name": "<potion id>",
; "qty": N}, ...]  ("id" is accepted instead of "name"). The id is the
; potions.json entry id (= its in-game name, except "Godly Potion (Sky)" /
; "(Sea)" / "(Hell)").
;
; How the game is read (in-game recon 2026-10-25):
;   - the selected-item panel shows NO name; its description box OCRs well
;     -> identity of the selected item = desc substring (potions.json desc)
;   - result tiles show the name in a font that draws a like o -> names are
;     compared with PotionSafety.NameMatches (canonical, still exact)
;   - a lone "1" in the amount box never OCRs, and its pixels look like the
;     empty box (a pixel signature of "1" could not be recorded, 2026-10-26)
;     -> the box (inv_amount_box; an older inv_amount_empty recording is
;     reused) is set by typing and only REFUSED when OCR reads any other
;     number (10, 100, 5...); the count must still drop by exactly 1
;   - sibling potions share descriptions ("Speed Potion L" = "[Quick
;     Roll]") -> every select click is proven: description NOT matching
;     before it, matching after it
;   - counts misread digits -> ParseCount maps confusables (never G) and two
;     reads must agree
;   - every OCR / signature read happens with the pointer parked on the
;     search box (hover only), never over the thing being read
;
; Every click and key goes through the stop check AND the focus check
; (deps "active", default WinActive("ahk_exe RobloxPlayerBeta.exe")): with
; Roblox not in front nothing more is sent (2026-10-27 review: the NoTimers
; section hid focus loss from the App tick, so clicks and Backspaces went to
; whatever window was in front). That counts as an abort.
;
; Per event (eventKey = biome "|" ts):
;   safety Status() not "" (usage file unreadable / halted)? -> skip all,
;   errors webhook -> rare biome still current? -> BeginEvent(key) (false ->
;   skip all), or the event is still open from an interrupted run of this
;   instance -> all 9 inventory calibrations present and sane? (else one
;   errors webhook, skip all) -> each potion in order (qty minus the uses
;   already recorded for the event); MarkEventDone(key) at the end.
;   Interrupted by a pause / focus loss / preempt (not F3): the event is
;   NOT marked done but queued again (MaxResumes), and the next run first
;   closes an inventory left open (_needClose, checked).
; Per potion:
;   Plan with owned unknown (unknown/locked/no_desc/caps/... -> skip, no
;   inventory; no_desc in DRY RUN instead walks to the tile and reports the
;   description text so the user can fill desc in)
;   open the inventory CHECKED (_OpenInv: its Gears / Items tab labels must
;   read; one already open is closed first), click the Items tab
;   (inv_items_tab; it opens on Gears), click inv_search, clear it (End +
;   Backspaces), type the exact tile name one char at a time
;   tile scan: OCR the name of result tiles 1..tileScan (inv_tile1_rect,
;     spacing from inv_tile2_rect); keep tiles whose name matches exactly.
;     0 -> skip (tile_not_found). Each matching tile is selected with PROOF
;     (_ClickFromOther: description must NOT match desc before the click --
;     another tile, or one from a "Potion" search, is selected first if it
;     does -- and MUST match after it); exactly 1 proven match -> that tile;
;     >1 -> skip (tile_ambiguous); 0 or no non-matching start state -> stop
;     ALL (select_unverified).
;   then per Use click (tile re-check .. click runs under Thread
;   "NoTimers": timers wait, F3 / the Stop button still interrupt):
;     OCR the chosen tile again -> NameMatches   else skip (name_mismatch)
;     OCR inv_desc_rect -> DescMatches(desc)     else stop ALL (selected_mismatch)
;     amount box: click its centre ONCE, End + Input.ClearKeys Backspaces
;       (no Ctrl+A), park, OCR must read no number
;                                            else skip potion (amount_not_empty)
;       type "1" in the same focus (no second click), park, OCR must read
;       nothing or "1" (a lone 1 does not OCR) and never another number; up
;       to sigReads (3) reads, sigRetry apart (blinking caret)
;                                            else skip potion (amount_not_one)
;     count (inv_count_rect moved to the tile): two reads, both parse and
;       agree, else "" -> Plan(id, qty left, key, count)  not ok -> skip
;     dry run: report "would use" + description read; stop here
;     poll + biome/event still current + not stopped  else stop ALL
;     dry run switched on meanwhile      -> stop ALL (dry_now_on)
;     Record (persisted)                  throws -> stop ALL (record_failed)
;     description again + amount box read again (no retyping)
;                                         else stop ALL (selected_mismatch /
;                                         amount_changed)
;     not stopped -> ONE click on inv_use, wait afterUse (a stop during it
;     waits out the rest without input, see _AfterUse), read the count again
;     (two agreeing reads) -> VerifyConsumed(before, after) false -> stop ALL
;       (verify_failed, reported as "Potion used (verify failed)"); the last
;       one of a kind (1 -> tile gone) is checked by _LastOneGone instead
;   close the inventory CHECKED (_CloseInv: click inv_open while its tabs
;   still read, CleanupCtx so a preempt still closes); on a halt nothing is
;   sent and the next run closes it first.
; Every use and skip -> `potions` webhook (reason, counts before/after).
; Unexpected skips also -> `errors` webhook.
; ---------------------------------------------------------------------------

class PotionsTask {
    static DefaultTiming := Map(
        "afterOpen", 700,
        "afterTab", 400,         ; after clicking the Items tab (inventory opens on Gears)
        "afterClickField", 200,
        "typeGap", 80,           ; between typed characters (Roblox drops fast input)
        "afterType", 600,
        "afterSelect", 500,
        "afterPark", 120,        ; pointer parked on the search box before a read
        "afterAmount", 300,
        "sigRetry", 250,         ; between amount signature reads
        "countReread", 150,      ; between the two count reads
        "descReread", 150,       ; between the two "not matching" reads before a select click
        "afterUse", 1200,
        "afterClose", 400)

    static PointIds := ["inv_open", "inv_items_tab", "inv_search", "inv_use"]
    static SearchTries := 3       ; typed searches before tile_not_found (Roblox drops letters)
    static RectIds := ["inv_tile1_rect", "inv_tile2_rect", "inv_count_rect", "inv_desc_rect"]
    static AmountId := "inv_amount_box"      ; falls back to the rect of an inv_amount_empty recording
    static OcrScale := 2
    static CloseTries := 3        ; clicks on inv_open while the inventory still reads open
    static MaxResumes := 5        ; re-queues of one event after a pause / focus loss
    ; Searched to find a tile with a different description when the item
    ; already selected has this potion's description (select proof).
    static PrimeSearch := "Potion"

    ; True from opening the inventory until the potion's last Use click is
    ; verified and the inventory closed. Clip defers its hotkey while set so
    ; no key can land in the focused search/amount box.
    static busy := false

    static ReasonText := Map(
        ; PotionSafety.Plan reasons (all 15 + ok)
        "usage_unreadable", "usage file unreadable or corrupt: all potion use refused",
        "usage_write_failed", "usage file could not be written: all potion use halted",
        "record_failed", "recording a use failed: all potion use halted",
        "unknown", "potion id is not in potions.json",
        "never_use", "never used by the macro (Heavenly Potion I/II, Sizemax, Sizemin)",
        "never_use_prefix", "its tile can be a never-use potion's (e.g. Heavenly Potion I with the I unread) and nothing rules that out: never used",
        "locked", "potion is locked (unlock it in Alerts > Biomes)",
        "no_desc", "potion has no desc in potions.json: copy a distinctive part of its in-game description there",
        "desc_not_unique", "this desc is part of another potion's desc (or the other way round): make both distinct in potions.json",
        "bad_event", "malformed biome event key",
        "event_done", "this biome event was already handled",
        "event_not_begun", "biome event was not claimed by this run",
        "bad_qty", "qty in biomes.json is not a whole number >= 1",
        "unreadable", "owned count could not be read (OCR, two reads must agree)",
        "bad_clock", "system date unreadable",
        "cap_biome", "per-biome cap reached",
        "cap_day", "per-day cap reached",
        "cap_run", "per-run cap reached",
        "none_owned", "none owned",
        "ok", "ok",
        ; task reasons
        "used", "used one",
        "dry_run", "dry run: nothing clicked",
        "event_claimed", "biome event already claimed (duplicate line or restart)",
        "biome_ended", "rare biome ended or changed",
        "uncalibrated", "inventory calibration missing (run Calibrate)",
        "tile_not_found", "no search result tile reads exactly this name",
        "tile_ambiguous", "more than one result tile reads this name and the description did not single out one",
        "name_mismatch", "result tile no longer reads this name",
        "select_unverified", "could not prove the tile click selected this potion (description did not change to it): all potion use stopped",
        "amount_not_empty", "amount box did not look empty after clearing it",
        "amount_not_one", "amount box does not look like the calibrated '1'",
        "amount_changed", "amount box changed after it was set to 1: all potion use stopped",
        "selected_mismatch", "selected item's description does not contain this potion's desc: all potion use stopped",
        "no_poll", "no log poll wired: biome cannot be re-checked, clicks refused",
        "dry_now_on", "dry run was switched on mid-task: all potion use stopped",
        "verify_failed", "count did not drop by exactly 1",
        "use_unverified", "stopped right after the Use click with Roblox not in front: count not verified",
        "aborted", "stopped (F3 / pause / Roblox not in front)",
        "already_used", "already used in this biome event (before an interruption)",
        "inv_not_open", "the inventory did not open (its tab labels did not read): all potion use stopped",
        "inv_not_closed", "the inventory left open could not be closed: all potion use stopped",
        "bad_entry", "bad potion entry in biomes.json",
        "stopped", "not tried: potion use stopped earlier in this event",
        "superseded", "replaced by a newer rare biome event",
        "test_event", "fake test event: potions are only ever dry-run for it",
        "input_failed", "input error")

    ; Plan reasons after which the safety instance is halted -> stop all.
    static HaltReasons := Map("usage_unreadable", 1, "usage_write_failed", 1, "record_failed", 1)
    ; Expected outcomes: potions webhook only, no errors webhook.
    static QuietReasons := Map("locked", 1, "cap_biome", 1, "cap_day", 1, "cap_run", 1, "none_owned", 1
        , "used", 1, "dry_run", 1, "aborted", 1, "superseded", 1, "stopped", 1, "event_claimed", 1, "biome_ended", 1
        , "already_used", 1, "use_unverified", 1)

    ; Absolute <repo>\data\potion_usage.json (lib\tasks\ -> repo root).
    static DefaultUsagePath() {
        return RegExReplace(A_LineFile, "\\[^\\]*\\[^\\]*\\[^\\]*$") "\data\potion_usage.json"
    }

    ; OCR count text -> digits. Optional x / X / multiplication-sign prefix,
    ; then digits where the game font's confusable glyphs are mapped:
    ; O o -> 0, T I l | i -> 1, S s -> 5, B -> 8 ("xT2" -> "12"). Without the
    ; prefix at least one real digit is required ("Oil" / "SOS" stay text).
    ; G is NOT mapped (recon read a 4 as G, a 6 as G too): unreadable.
    ; Anything else is returned trimmed and unchanged (PotionSafety rejects
    ; it -> no click).
    static ParseCount(s) {
        t := Trim(String(s), " `t`r`n")
        if RegExMatch(t, "^([xX\x{00D7}]?)\s*([0-9OoTIl|iSsB]+)$", &m) {
            if (m[1] = "" && !RegExMatch(m[2], "\d"))
                return t
            d := m[2]
            d := RegExReplace(d, "[Oo]", "0")
            d := RegExReplace(d, "[TIl|i]", "1")
            d := RegExReplace(d, "[Ss]", "5")
            d := StrReplace(d, "B", "8", true)
            if RegExMatch(d, "^\d{1,9}$")
                return d
        }
        return t
    }

    __New(deps) {
        d := (deps is Map) ? deps : Map()
        if !(d.Has("cfg") && d.Has("safety") && d.Has("state"))
            throw ValueError("PotionsTask: cfg, safety and state are required")
        this.name := "potions"
        this.priority := 1
        this._cfg := d["cfg"]
        this._safety := d["safety"]
        this._state := d["state"]
        this._wh := d.Has("wh") ? d["wh"] : ""
        this._logFn := d.Has("log") ? d["log"] : ""
        this._io := d.Has("io") ? d["io"] : ""
        this._ocrFn := d.Has("ocr") ? d["ocr"] : ((r, scale := 1) => Ocr.Read(r.x, r.y, r.w, r.h, scale))
        this._amountFn := d.Has("amount") ? d["amount"] : ((r) => this._Ocr(r, 3))     ; amount box text
        this._cal := d.Has("cal") ? d["cal"] : Calibrate
        this._activeFn := d.Has("active") ? d["active"] : (() => WinActive("ahk_exe RobloxPlayerBeta.exe") ? true : false)
        this.pollFn := d.Has("poll") ? d["poll"] : ""
        this.timing := PotionsTask.DefaultTiming.Clone()
        this._pending := ""
        this._invOpen := false
        this._needClose := false     ; an interrupted run left the inventory open: close it first
        this._missing := ""
        this._lastCount := ""
        this._lastDesc := ""
        this._preDesc := ""
        ; A corrupt / unwritable usage file turns every potion off: say so
        ; at startup, not only as skips later (2026-10-27 review).
        st := ""
        try st := this._safety.Status()
        if (st != "")
            this._Error("Potions: " PotionsTask._Why(st) " (data\potion_usage.json). No potion is used until it is fixed and the macro restarted.")
    }

    static _Why(reason) => PotionsTask.ReasonText.Has(reason) ? PotionsTask.ReasonText[reason] : reason

    ; ---- scheduler contract -------------------------------------------------

    Queue(biome, ts) {
        if IsObject(this._pending)
            this._Report(this._pending.biome, "(all)", "skip", "superseded", "", "", "", this._IsDry())
        this._pending := {biome: String(biome), ts: String(ts)}
    }

    CanRun(state) => IsObject(this._pending)
    HasPending() => IsObject(this._pending)

    Run(ctx) {
        ev := this._pending
        this._pending := ""
        if !IsObject(ev)
            return
        ; the inventory scales evenly, centred (16:10): mode "C" around it,
        ; as BiomeItems / Merchant (review 2026-11-12: every potion missed
        ; the Items tab at 1920x1200)
        old := Screen.Mode
        Screen.Mode := "C"
        try {
            if this._needClose
                this._CloseLeftover(ctx)
            this._RunEvent(ev, ctx)
        } finally {
            Screen.Mode := old
        }
    }

    ; A run cut short by a pause / focus loss left the inventory open (no
    ; input may be sent while halted). Close it now, checked, before
    ; anything else -- even when the biome has ended meanwhile, so no other
    ; task runs with it open (2026-10-27 review). Runs on the ctx of the
    ; NEW run; the flag stays set while that is not possible.
    _CloseLeftover(ctx) {
        if this._Stopped(ctx)
            return
        cal := this._LoadCal()
        if !IsObject(cal)
            return
        if this._CloseInv(cal, ctx)
            this._needClose := false
        else if !this._Stopped(ctx)
            this._Error("Potions: the inventory left open by an interrupted potion run did not close")
    }

    ; ---- event --------------------------------------------------------------

    _RunEvent(ev, ctx) {
        biome := ev.biome
        list := Biomes.Find(this._cfg, biome)["potions"]
        dry := this._IsDry()
        if (list.Length = 0) {
            this._Log("Potions: no potion list for " biome "; nothing to use")
            return
        }
        if (SubStr(ev.ts, 1, 5) = "TEST-" && !dry) {
            ; a fake test event (Dashboard > Tools) never uses a potion
            this._SkipAll(biome, list, "test_event", dry)
            this._Error("Potions: test event while dry run is off; no potion used")
            return
        }
        if (Trim(ev.ts) = "") {
            this._SkipAll(biome, list, "bad_event", dry)
            this._Error("Potions: biome event for " biome " has no log timestamp; no potion used")
            return
        }
        if this._Stopped(ctx) {
            if !this._Requeue(ev, ctx)
                this._SkipAll(biome, list, "aborted", dry)
            return
        }
        if (!dry && !IsObject(this.pollFn)) {
            this._SkipAll(biome, list, "no_poll", dry)
            this._Error("Potions: no log poll wired into PotionsTask; the rare biome cannot be re-checked, so no potion is clicked")
            return
        }
        key := biome "|" ev.ts
        ; an event THIS task began and re-queued after a pause / focus loss
        ; (_Requeue sets resumes); any other already claimed event is refused
        resumed := ev.HasOwnProp("resumes") && this._safety.IsEventOpen(key)
        if !this._BiomeActive(ev) {
            this._SkipAll(biome, list, "biome_ended", dry)
            if resumed
                this._CloseEvent(key)
            return
        }
        ; A corrupt / unwritable usage file or an earlier halt refuses every
        ; potion: report THAT, loudly (2026-10-27 review: BeginEvent's false
        ; showed it as a quiet "event_claimed", even in dry run).
        if this._HaltedAll(biome, list, dry)
            return
        if (!resumed && !this._safety.BeginEvent(key)) {
            if !this._HaltedAll(biome, list, dry)      ; the claim's save failed
                this._SkipAll(biome, list, "event_claimed", dry)
            return
        }
        requeued := false
        try {
            cal := this._LoadCal()
            if !IsObject(cal) {
                this._Error("Potions: inventory calibration missing (" this._missing "). Run Calibrate. No potion was used.")
                this._SkipAll(biome, list, "uncalibrated", dry)
                return
            }
            stop := ""
            for entry in list {
                if (stop != "") {
                    this._Report(biome, PotionsTask._EntryName(entry), "skip", "stopped", "", "", "after " stop, dry)
                    continue
                }
                try {
                    stop := this._DoPotion(entry, ev, key, cal, ctx, dry)
                } catch Any as e {
                    this._Report(biome, PotionsTask._EntryName(entry), "skip", "input_failed", "", "", e is Error ? e.Message : "", dry)
                    this._Error("Potions: input error during " PotionsTask._EntryName(entry) "; all potion use stopped for this event")
                    stop := "input_failed"
                }
                ; cut short by a pause / focus loss / preempt (not F3): the
                ; event stays open and runs again before any other task
                ; (2026-10-27 review: it used to be marked done, so the rest
                ; of the list was lost)
                if (stop = "aborted" && this._Requeue(ev, ctx)) {
                    requeued := true
                    this._Log("Potions: " biome " event interrupted; it resumes when the macro does")
                    break
                }
            }
        } finally {
            if !requeued
                this._CloseEvent(key)
        }
    }

    _CloseEvent(key) {
        try {
            this._safety.MarkEventDone(key)
        } catch Any as e {
            this._Log("Potions: could not close event (" (e is Error ? e.Message : "error") ")")
        }
    }

    ; Safety halted (Status() not "") -> every potion skipped with that
    ; reason + errors webhook, true. Else false.
    _HaltedAll(biome, list, dry) {
        st := ""
        try st := this._safety.Status()
        if (st = "")
            return false
        this._SkipAll(biome, list, st, dry)
        this._Error("Potions: " PotionsTask._Why(st) " (data\potion_usage.json); no potion used for " biome)
        return true
    }

    ; Queue ev again after an interruption that is not F3 (pause, Roblox not
    ; in front, preempt). False -> the event ends: F3 (the user took over),
    ; MaxResumes reached, or a newer event is queued (then a duplicate of
    ; this same event counts as re-queued and keeps it open).
    _Requeue(ev, ctx) {
        if !(IsObject(ctx) && HasMethod(ctx, "IsStopped")) || ctx.IsStopped()
            return false
        n := ev.HasOwnProp("resumes") ? ev.resumes : 0
        if (n >= PotionsTask.MaxResumes)
            return false
        if IsObject(this._pending) {
            if ((this._pending.biome "|" this._pending.ts) !== (ev.biome "|" ev.ts))
                return false
            this._pending.resumes := n + 1      ; the duplicate resumes this event
            return true
        }
        this._pending := {biome: ev.biome, ts: ev.ts, resumes: n + 1}
        return true
    }

    ; -> "" to continue with the next potion, or a reason that stops ALL.
    _DoPotion(entry, ev, key, cal, ctx, dry) {
        biome := ev.biome
        id := PotionsTask._EntryName(entry)
        if (id = "(bad entry)") {
            this._Report(biome, id, "skip", "bad_entry", "", "", "", dry)
            this._Error("Potions: bad potion entry in biomes.json for " biome)
            return ""
        }
        want := entry.Has("qty") ? entry["qty"] : ""
        ; Rules that need no inventory (owned count not known yet).
        pre := this._safety.Plan(id, want, key, 999999)
        discover := (dry && pre.reason = "no_desc")
        if (pre.reason != "ok" && !discover)
            return this._PlanSkip(biome, id, pre.reason, "", dry)
        info := this._safety.Info(id)
        if !IsObject(info)
            return this._PlanSkip(biome, id, "unknown", "", dry)
        wantN := discover ? 0 : Integer(Trim(String(want), " `t`r`n"))
        ; a resumed event: uses already recorded for it count towards qty
        done := discover ? 0 : this._safety.UsedInEvent(id, key)
        if (!discover && done >= wantN) {
            this._Report(biome, id, "skip", "already_used", "", "", done " of " wantN " recorded", dry)
            return ""
        }
        wantN -= done
        if this._Stopped(ctx)
            return this._Stop(biome, id, "aborted", "", dry)
        if !this._BiomeActive(ev)
            return this._Stop(biome, id, "biome_ended", "", dry)
        this._invOpen := false
        PotionsTask.busy := true
        try {
            o := this._OpenAndSearch(info.name, cal, ctx)
            if (o = "aborted")
                return this._Stop(biome, id, "aborted", "", dry)
            if (o != "ok") {
                reason := (o = "not_open") ? "inv_not_open" : "inv_not_closed"
                this._Report(biome, id, "skip", reason, "", "", "", dry)
                this._Error("Potions: " id " not used: " PotionsTask._Why(reason))
                return reason
            }
            found := this._FindTile(info, cal, ctx)
            ; Roblox drops a typed letter now and then: not found -> type the
            ; exact name again (up to SearchTries searches in all)
            Loop PotionsTask.SearchTries - 1 {
                if (found.reason != "tile_not_found")
                    break
                if !(this._SetField(cal.inv_search.x, cal.inv_search.y, info.name, ctx) && this._Wait("afterType", ctx))
                    return this._Stop(biome, id, "aborted", "", dry)
                found := this._FindTile(info, cal, ctx)
            }
            if (found.reason = "aborted")
                return this._Stop(biome, id, "aborted", "", dry)
            if (found.reason = "select_unverified") {
                this._Report(biome, id, "skip", "select_unverified", "", "", found.extra, dry)
                this._Error("Potions: could not prove the tile click selected " id " (" found.extra "); all potion use stopped")
                return "select_unverified"
            }
            if (found.reason != "") {
                this._Report(biome, id, "skip", found.reason, "", "", found.extra, dry)
                this._Error("Potions: " id " not used: " found.reason " (" PotionsTask.ReasonText[found.reason] "). " found.extra)
                return ""
            }
            idx := found.idx
            if discover {
                d := this._Ocr(cal.inv_desc_rect)
                this._Report(biome, id, "skip", "no_desc", "", "", "tile " idx " found; description reads: '" PotionsTask._Flat(d) "'", dry)
                return ""
            }
            used := 0
            while (used < wantN) {
                if this._Stopped(ctx)
                    return this._Stop(biome, id, "aborted", "", dry)
                if !this._BiomeActive(ev)
                    return this._Stop(biome, id, "biome_ended", "", dry)
                ; Everything from the tile re-check to the Use click runs with
                ; Thread "NoTimers": no timer thread (Medal clip, scheduler
                ; tick) can interrupt and type into the focused box, but
                ; hotkeys (F3) and GUI buttons (Stop) still run, so the
                ; _Stopped check right before the click sees a stop at once.
                ; (Critical would buffer F3 until the click was done.)
                ; PotionsTask.busy (Clip defers) stays set as a second guard.
                Thread("NoTimers", true)
                try {
                    r := this._PrepareAndClick(info, idx, ev, key, cal, ctx, dry, wantN - used)
                } finally {
                    Thread("NoTimers", false)
                }
                if (r.status != "clicked")
                    return r.stop
                before := r.before
                waited := this._AfterUse(ctx)
                if (waited = "unverified") {
                    this._Report(biome, id, "used_unchecked", "use_unverified", before, "", "", dry)
                    return "aborted"
                }
                after := this._ReadCount(cal, idx, waited ? ctx : "")
                lastOne := false
                if !this._safety.VerifyConsumed(before, after) {
                    if !this._LastOneGone(info, cal, idx, before, after) {
                        this._Report(biome, id, "used_unverified", "verify_failed", before, after, "count reads " this._lastCount, dry)
                        this._Error("Potions: count for " id " went " before " -> " (after = "" ? "?" : after) " after one Use; all potion use stopped")
                        return "verify_failed"
                    }
                    after := "0", lastOne := true
                }
                used++
                this._Report(biome, id, "used", "used", before, after, "use " used " of " wantN, dry)
                if !waited
                    return "aborted"
                if lastOne
                    return ""                   ; none left of this potion
            }
            return ""
        } finally {
            ; Close CHECKED (2026-10-27 review: one blind click right after
            ; typing only took the focus off the box, so the inventory stayed
            ; open and the next potion's open click closed it and typed the
            ; name into the game). A preempt still closes (CleanupCtx); on a
            ; real halt nothing may be sent, so the next potion run closes
            ; it first (_needClose).
            if this._invOpen {
                closed := false
                if !CleanupCtx.Halted(ctx)
                    try closed := this._CloseInv(cal, CleanupCtx(ctx))
                if !closed {
                    this._needClose := true
                    if (!CleanupCtx.Halted(ctx) && this._Front())
                        this._Error("Potions: the inventory did not close after " id "; it is closed (checked) before the next potion")
                }
            }
            this._invOpen := false
            PotionsTask.busy := false
        }
    }

    ; Wait afterUse. A stop during it used to read the count at once, before
    ; the game updated it: a false "used (verify failed)" + errors webhook
    ; (2026-10-27 review). The click is done, so the rest of afterUse is
    ; waited out WITHOUT the stop check (nothing is sent, only waited), then
    ; the count is read if Roblox is still in front.
    ; -> true (waited normally) | false (stopped, waited out, verify) |
    ;    "unverified" (stopped and Roblox not in front: count not read)
    _AfterUse(ctx) {
        t0 := A_TickCount
        if this._Wait("afterUse", ctx)
            return true
        left := this._Ms("afterUse", 1200) - (A_TickCount - t0)
        if (left > 0)
            Input._Backend(this._io).Wait(left, "")
        return this._Front() ? false : "unverified"
    }

    ; 2026-10-27 review: Sol's RNG lists owned items only, so using the last
    ; potion of a kind removes its tile and the next result shifts into tile
    ; idx (its count reads, e.g. x9, or nothing). Count 1 -> gone counts as
    ; consumed only when the tile at idx no longer reads this name AND the
    ; selected-item description differs from the one read right before the
    ; click (an OCR hiccup on the tile alone is not enough). A wrong "yes"
    ; uses nothing more: the potion's loop ends here.
    _LastOneGone(info, cal, idx, before, after) {
        if (String(before) != "1" || String(after) = "1")
            return false
        this._Park(cal)
        if this._safety.NameMatches(this._Ocr(this._TileRect(cal, "inv_tile1_rect", idx)), info.name)
            return false
        return PotionSafety.Canon(this._Ocr(cal.inv_desc_rect)) !== PotionSafety.Canon(this._lastDesc)
    }

    ; Every check for ONE Use click, then the click (runs NoTimers).
    ; -> {status: "clicked", before} or {status: "done", stop: ""|reason}
    _PrepareAndClick(info, idx, ev, key, cal, ctx, dry, wantLeft) {
        biome := ev.biome
        id := info.id
        done := (stop) => ({status: "done", stop: stop, before: ""})
        ; 1. the chosen result tile still reads exactly this name
        seen := this._Ocr(this._TileRect(cal, "inv_tile1_rect", idx))
        if !this._safety.NameMatches(seen, info.name) {
            this._Report(biome, id, "skip", "name_mismatch", "", "", "tile " idx " OCR '" PotionsTask._Flat(seen) "'", dry)
            this._Error("Potions: tile " idx " OCR '" PotionsTask._Flat(seen) "' does not match " info.name "; " id " not used")
            return done("")
        }
        ; 2. the SELECTED item (the one Use acts on) has this potion's description
        if !this._DescOk(info, cal, biome, dry)
            return done("selected_mismatch")
        ; 3. amount box shows the calibrated "1"
        amt := this._SetAmountOne(cal, ctx)
        if (amt = "aborted")
            return done(this._Stop(biome, id, "aborted", "", dry))
        if (amt = "not_empty") {
            this._Report(biome, id, "skip", "amount_not_empty", "", "", "", dry)
            this._Error("Potions: amount box for " id " still shows a number after End + Backspace; not used")
            return done("")
        }
        if (amt != "ok") {
            this._Report(biome, id, "skip", "amount_not_one", "", "", "", dry)
            this._Error("Potions: amount box for " id " shows a number other than 1 after typing 1; not used")
            return done("")
        }
        ; 4. owned count (two agreeing reads), plan what is left
        before := this._ReadCount(cal, idx, ctx)
        if this._Stopped(ctx)
            return done(this._Stop(biome, id, "aborted", before, dry))
        plan := this._safety.Plan(id, wantLeft, key, before)
        if (plan.reason != "ok") {
            if (plan.reason = "unreadable")
                return done(this._PlanSkip(biome, id, plan.reason, before, dry, "count reads " this._lastCount))
            return done(this._PlanSkip(biome, id, plan.reason, before, dry))
        }
        if dry {
            this._Report(biome, id, "dry", "dry_run", before, "", "would use " plan.qty "; description reads: '" PotionsTask._Flat(this._lastDesc) "'", dry)
            return done("")
        }
        ; 5. last checks before reserving the use
        if this._Stopped(ctx)
            return done(this._Stop(biome, id, "aborted", before, dry))
        if !this._BiomeActive(ev)
            return done(this._Stop(biome, id, "biome_ended", before, dry))
        if this._IsDry() {
            this._Report(biome, id, "skip", "dry_now_on", before, "", "", dry)
            return done("dry_now_on")
        }
        ; 6. reserve + persist BEFORE the click
        try {
            this._safety.Record(id, key)
        } catch Any as e {
            this._Report(biome, id, "skip", "record_failed", before, "", e is Error ? e.Message : "", dry)
            this._Error("Potions: could not record a use of " id "; all potion use stopped")
            return done("record_failed")
        }
        ; 7. immediately before the click: description + amount again
        ;    (a reserved but unclicked use is the safe side)
        if !this._DescOk(info, cal, biome, dry)
            return done("selected_mismatch")
        sig2 := this._AmountOk(cal, ctx, "one")
        if (sig2 = "aborted")
            return done(this._Stop(biome, id, "aborted", before, dry))
        if (sig2 != "ok") {
            this._Report(biome, id, "skip", "amount_changed", before, "", "", dry)
            this._Error("Potions: amount box for " id " changed before Use; all potion use stopped")
            return done("amount_changed")
        }
        ; 8. ONE Use click (_ClickXY: stop + focus check right before it)
        if !this._ClickXY(cal.inv_use.x, cal.inv_use.y, ctx)
            return done(this._Stop(biome, id, "aborted", before, dry))
        return {status: "clicked", stop: "", before: before}
    }

    _DescOk(info, cal, biome, dry) {
        d := this._Ocr(cal.inv_desc_rect)
        this._lastDesc := d
        if this._safety.DescMatches(d, info.desc)
            return true
        this._Report(biome, info.id, "skip", "selected_mismatch", "", "", "description OCR '" PotionsTask._Flat(d) "' lacks '" info.desc "'", dry)
        this._Error("Potions: selected item's description reads '" PotionsTask._Flat(d) "', not '" info.desc "' (" info.id "); all potion use stopped")
        return false
    }

    ; ---- steps --------------------------------------------------------------

    ; -> "ok" | "aborted" | "not_open" | "not_closed" (see _OpenInv)
    _OpenAndSearch(name, cal, ctx) {
        o := this._OpenInv(cal, ctx)
        if (o != "ok")
            return o
        ; the inventory opens on the Gears tab: switch to Items first
        if !this._ClickXY(cal.inv_items_tab.x, cal.inv_items_tab.y, ctx)
            return "aborted"
        if !this._Wait("afterTab", ctx)
            return "aborted"
        if !this._SetField(cal.inv_search.x, cal.inv_search.y, name, ctx)
            return "aborted"
        return this._Wait("afterType", ctx) ? "ok" : "aborted"
    }

    ; Open the inventory, CHECKED (2026-10-27 review): inv_open is a toggle,
    ; and a click right after typing may only take the focus off a text box
    ; (TaskEnv.CloseInv). A blind click on an inventory left open closed it,
    ; and the search name was then typed into the game world (a/s/d walk,
    ; e interacts). So an inventory that already reads open is closed first
    ; (checked: a fresh one opens on Gears with no box focused), then it is
    ; opened and must read open (its Gears / Items tab labels).
    ; -> "ok" | "aborted" | "not_open" | "not_closed"
    _OpenInv(cal, ctx) {
        if this._InvShown(cal) {
            this._invOpen := true
            if !this._CloseInv(cal, ctx)
                return this._Stopped(ctx) ? "aborted" : "not_closed"
            this._invOpen := false
        }
        Loop 2 {
            if !this._ClickXY(cal.inv_open.x, cal.inv_open.y, ctx)
                return "aborted"
            this._invOpen := true        ; unknown from here on: the finally closes it (checked)
            if !this._Wait("afterOpen", ctx)
                return "aborted"
            if this._InvShown(cal)
                return "ok"
        }
        return "not_open"
    }

    ; The inventory is open: its tab labels (Gears / Items) read around the
    ; calibrated inv_items_tab point (same rect as TaskEnv.InvOpen).
    _InvShown(cal) {
        t := cal.inv_items_tab
        return RegExMatch(this._Ocr({x: t.x - 90, y: t.y - 25, w: 180, h: 50}, 1), "i)item|gear") > 0
    }

    ; Close the inventory: click inv_open while its tabs still read, up to
    ; CloseTries clicks (TaskEnv.CloseInv). Never a click on a closed one.
    ; -> true closed, false still open / stopped / Roblox not in front.
    _CloseInv(cal, ctx) {
        Loop PotionsTask.CloseTries {
            if !this._InvShown(cal)
                return true
            if !this._ClickXY(cal.inv_open.x, cal.inv_open.y, ctx)
                return false
            if !this._Wait("afterClose", ctx)
                return false
        }
        if this._InvShown(cal) {
            this._Log("Potions: the inventory is still open after " PotionsTask.CloseTries " clicks on its button")
            return false
        }
        return true
    }

    ; Tile scan (pointer is on the search box, off every tile).
    ; -> {idx, reason: "", extra} | {reason: "tile_not_found" | "tile_ambiguous"
    ;    | "select_unverified" | "aborted", extra}
    ; SELECT PROOF: sibling potions share descriptions ("Speed Potion L" and
    ; "Speed Potion": "[Quick Roll]"), so a dropped click that leaves an old
    ; selection would still pass the description check. Every select click
    ; is therefore made from a state whose description does NOT match desc
    ; (another tile is selected first if needed, see _Prime), and the click
    ; only counts when the description DOES match afterwards.
    _FindTile(info, cal, ctx) {
        n := this._CfgInt("Potions.tileScan", 6, 1, 12)
        hits := [], present := []
        seen := ""
        Loop n {
            t := this._Ocr(this._TileRect(cal, "inv_tile1_rect", A_Index))
            if (t != "") {
                present.Push(A_Index)
                seen .= (seen = "" ? "" : ", ") A_Index ":'" PotionsTask._Flat(t) "'"
            }
            if this._safety.NameMatches(t, info.name)
                hits.Push(A_Index)
        }
        if (hits.Length = 0)
            return {reason: "tile_not_found", extra: "searched '" info.name "'; tiles read: " (seen = "" ? "(none)" : seen)}
        if (info.desc = "") {
            ; dry-run discovery only (Plan refuses no_desc otherwise): nothing
            ; can be proven and nothing will be used
            if (hits.Length > 1)
                return {reason: "tile_ambiguous", extra: hits.Length " tiles read '" info.name "' and there is no desc to tell them apart"}
            if !this._SelectTile(cal, hits[1], ctx)
                return {reason: "aborted", extra: ""}
            return {idx: hits[1], reason: "", extra: ""}
        }
        match := []
        last := 0
        for k in hits {
            r := this._ClickFromOther(info, cal, k, present, ctx)
            if (r = "aborted" || r = "unverified")
                return {reason: r = "aborted" ? "aborted" : "select_unverified"
                    , extra: "no proven description without '" info.desc "' before the click (OCR error, unstable read, or no tile with another description could be selected first)"}
            last := k
            if (r = "match")
                match.Push(k)
        }
        if (match.Length > 1)
            return {reason: "tile_ambiguous", extra: hits.Length " tiles read '" info.name "'; " match.Length " have '" info.desc "' in the description"}
        if (match.Length = 0)
            return {reason: "select_unverified", extra: "after selecting " (hits.Length = 1 ? "the tile" : "each of the " hits.Length " tiles") " reading '" info.name "', no description had '" info.desc "' (dropped click or wrong desc)"}
        if (last != match[1]) {
            r := this._ClickFromOther(info, cal, match[1], present, ctx)
            if (r = "aborted")
                return {reason: "aborted", extra: ""}
            if (r != "match")
                return {reason: "select_unverified", extra: "re-selecting tile " match[1] " did not show '" info.desc "'"}
        }
        return {idx: match[1], reason: "", extra: ""}
    }

    ; Select tile k from a state whose description does not match desc.
    ; Fail closed: the "not matching" start state must hold on TWO reads
    ; descReread apart (one garbled read is not enough), an OCR exception is
    ; UNKNOWN (no select click at all, "unverified"), an EMPTY read is unknown too (Ocr.Read
    ; returns "" on failure): it is never taken as "not matching"; another
    ; tile with a readable, different description is selected first (_Prime)
    ; and the two reads repeated. After the click the description
    ; must match desc AND its canonical text must differ from the pre-click
    ; text.
    ; -> "match" | "nomatch" (description after the click) | "unverified"
    ;    (could not get a proven non-matching state first) | "aborted"
    _ClickFromOther(info, cal, k, present, ctx) {
        st := this._DescNotMatching(info, cal, ctx)
        ; "no" (matches) or "empty" (nothing readable, e.g. no item selected
        ; yet): select a tile whose description is READABLE and different
        if (st = "no" || st = "empty") {
            p := this._Prime(info, cal, k, present, ctx)
            if (p != "ok")
                return p
            st := this._DescNotMatching(info, cal, ctx)
        }
        if (st = "aborted")
            return "aborted"
        if (st != "yes")
            return "unverified"
        pre := this._preDesc
        if !this._SelectTile(cal, k, ctx)
            return "aborted"
        post := this._OcrStrict(cal.inv_desc_rect)
        if !post.ok
            return "nomatch"
        return (this._safety.DescMatches(post.text, info.desc)
            && PotionSafety.Canon(post.text) !== PotionSafety.Canon(pre)) ? "match" : "nomatch"
    }

    ; Two description reads descReread apart.
    ; -> "yes" (both read non-empty text and neither matches desc;
    ;    this._preDesc = 2nd text) | "no" (a read matches) | "empty" (a read
    ;    is empty/whitespace: Ocr.Read returns "" on failure, so empty is
    ;    UNKNOWN, never "not matching") | "unknown" (OCR exception) | "aborted"
    _DescNotMatching(info, cal, ctx) {
        Loop 2 {
            if (A_Index = 2 && !this._Wait("descReread", ctx))
                return "aborted"
            r := this._OcrStrict(cal.inv_desc_rect)
            if !r.ok
                return "unknown"
            if PotionsTask._Blank(r.text)
                return "empty"
            if this._safety.DescMatches(r.text, info.desc)
                return "no"
            this._preDesc := r.text
        }
        return "yes"
    }

    ; True only when the selected item's description reads NON-EMPTY text
    ; that does not contain desc. Empty / failed OCR -> false (unknown).
    _DescIsOther(info, cal) {
        t := this._Ocr(cal.inv_desc_rect)
        return !PotionsTask._Blank(t) && !this._safety.DescMatches(t, info.desc)
    }

    static _Blank(s) => Trim(String(s), " `t`r`n") = ""

    ; OCR that reports failure: {ok: false} on an exception, else {ok, text}.
    _OcrStrict(rect, scale := PotionsTask.OcrScale) {
        try {
            return {ok: true, text: String(this._ocrFn.Call(rect, scale))}
        } catch {
            return {ok: false, text: ""}
        }
    }

    ; Make the selected item's description readable and NOT matching desc
    ; (empty OCR never counts as "not matching"): select another
    ; result tile; if all of them match (shared descriptions), search
    ; PrimeSearch, select a tile there whose description differs, then search
    ; the potion again and check tile k still reads its name.
    ; -> "ok" | "unverified" | "aborted"
    _Prime(info, cal, k, present, ctx) {
        for j in present {
            if (j = k)
                continue
            if !this._SelectTile(cal, j, ctx)
                return "aborted"
            if this._DescIsOther(info, cal)
                return "ok"
        }
        if !(this._SetField(cal.inv_search.x, cal.inv_search.y, PotionsTask.PrimeSearch, ctx) && this._Wait("afterType", ctx))
            return "aborted"
        ok := false
        Loop this._CfgInt("Potions.tileScan", 6, 1, 12) {
            if (this._Ocr(this._TileRect(cal, "inv_tile1_rect", A_Index)) = "")
                continue
            if !this._SelectTile(cal, A_Index, ctx)
                return "aborted"
            if this._DescIsOther(info, cal) {
                ok := true
                break
            }
        }
        if !(this._SetField(cal.inv_search.x, cal.inv_search.y, info.name, ctx) && this._Wait("afterType", ctx))
            return "aborted"
        if !ok
            return "unverified"
        if !this._safety.NameMatches(this._Ocr(this._TileRect(cal, "inv_tile1_rect", k)), info.name)
            return "unverified"
        if !this._DescIsOther(info, cal)
            return "unverified"
        return "ok"
    }

    ; Click the middle of tile k's name, park the pointer, settle.
    _SelectTile(cal, k, ctx) {
        r := this._TileRect(cal, "inv_tile1_rect", k)
        if !this._ClickXY(r.x + r.w // 2, r.y + r.h // 2, ctx)
            return false
        this._Park(cal)
        return this._Wait("afterSelect", ctx)
    }

    ; Rect of tile k (1-based): the tile-1 rect `id` moved by (k-1) * the
    ; tile spacing (inv_tile2_rect - inv_tile1_rect).
    _TileRect(cal, id, k) {
        r := cal.%id%
        dx := cal.inv_tile2_rect.x - cal.inv_tile1_rect.x
        dy := cal.inv_tile2_rect.y - cal.inv_tile1_rect.y
        return {x: r.x + (k - 1) * dx, y: r.y + (k - 1) * dy, w: r.w, h: r.h}
    }

    ; Hover the search box so the pointer is not drawn over anything read.
    _Park(cal) {
        Input._Backend(this._io).MoveTo(cal.inv_search.x, cal.inv_search.y)
        this._Wait("afterPark", "")
    }

    ; Clear the amount box WITHOUT Ctrl+A (ONE click, End + Input.ClearKeys
    ; Backspaces), check no number is left, type "1" in the SAME focus, check
    ; no other number shows. -> "ok" | "aborted" | "not_empty" | "mismatch"
    ; 2026-10-27 review: a second click before typing opened a hole: with
    ; the first click swallowed the Backspaces went nowhere, a left-over "1"
    ; passed the empty check (a lone 1 never OCRs), the second click focused
    ; the box and typing made "11", which may OCR as nothing too. Without it
    ; a swallowed first click leaves the old content untouched.
    _SetAmountOne(cal, ctx) {
        ar := cal.inv_amount
        cx := ar.x + ar.w // 2, cy := ar.y + ar.h // 2
        if !(this._ClickXY(cx, cy, ctx) && this._Wait("afterClickField", ctx))
            return "aborted"
        if !this._ClearText(ctx)
            return "aborted"
        if !this._Wait("afterAmount", ctx)
            return "aborted"
        e := this._AmountOk(cal, ctx, "empty")
        if (e != "ok")
            return (e = "aborted") ? "aborted" : "not_empty"
        if !this._Type("1", ctx)
            return "aborted"
        if !this._Wait("afterAmount", ctx)
            return "aborted"
        return this._AmountOk(cal, ctx, "one")
    }

    ; What OCR reads in the amount box -> "blank" (nothing: empty, or a lone
    ; "1", which never OCRs) | "one" (a 1 read as 1 / l / I / |) | "other"
    ; (any other number or text).
    static AmountClass(text) {
        t := RegExReplace(String(text), "\s+")
        if (t = "")
            return "blank"
        if RegExMatch(t, "^[1lI|]$")
            return "one"
        return "other"
    }

    ; Amount box check (pointer parked, up to sigReads reads sigRetry apart:
    ; a blinking caret can spoil one). which = "empty": no number may be
    ; read ("blank"). which = "one": "blank" or "one", never another number.
    ; -> "ok" | "mismatch" | "aborted"
    _AmountOk(cal, ctx, which) {
        r := cal.inv_amount
        reads := this._CfgInt("Potions.sigReads", 3, 1, 5)
        this._Park(cal)
        Loop reads {
            t := ""
            try t := this._amountFn.Call({x: r.x, y: r.y, w: r.w, h: r.h})
            c := PotionsTask.AmountClass(t)
            if (c = "blank" || (which = "one" && c = "one"))
                return "ok"
            if (A_Index < reads && !this._Wait("sigRetry", ctx))
                return "aborted"
        }
        return "mismatch"
    }

    ; Count of tile idx: two reads must parse to the same digits, else "".
    ; this._lastCount = what the two reads said (for reports).
    _ReadCount(cal, idx, ctx) {
        r := this._TileRect(cal, "inv_count_rect", idx)
        a := this._Ocr(r)
        this._Wait("countReread", ctx)
        b := this._Ocr(r)
        pa := PotionsTask.ParseCount(a), pb := PotionsTask.ParseCount(b)
        this._lastCount := "'" PotionsTask._Flat(a) "' / '" PotionsTask._Flat(b) "'"
        return (RegExMatch(pa, "^\d{1,9}$") && pa == pb) ? pa : ""
    }

    ; Click a text box, empty it, type text (one char per gap).
    _SetField(x, y, text, ctx) {
        if !this._ClickXY(x, y, ctx)
            return false
        if !this._Wait("afterClickField", ctx)
            return false
        return this._ClearText(ctx) && this._Type(text, ctx)
    }

    ; Input.ClearText (End, then Input.ClearKeys Backspaces; Roblox ignores
    ; Ctrl+A) with the stop / focus check before EVERY key.
    _ClearText(ctx) {
        Loop Input.ClearKeys + 1 {
            if this._Stopped(ctx)
                return false
            if (A_Index = 1)
                Input.Key("End", 30, this._io)
            else
                Input.Key("Backspace", 20, this._io)
        }
        return true
    }

    ; Input.TypeText one character per call, typeGap apart, with the stop /
    ; focus check before EVERY character.
    _Type(text, ctx) {
        gap := this._Ms("typeGap", Input.TypeGapMs)
        s := String(text)
        Loop Parse s {
            if (A_Index > 1 && gap > 0)
                Input._Backend(this._io).Wait(gap)
            if this._Stopped(ctx)
                return false
            Input.TypeText(A_LoopField, this._io, 0)
        }
        return true
    }

    _ClickXY(x, y, ctx) {
        if this._Stopped(ctx)
            return false
        Input.Click(x, y, this._io)
        return true
    }

    _Wait(which, ctx) {
        return Input._Backend(this._io).Wait(this._Ms(which, 500), ctx) ? true : false
    }

    _Ms(which, def) => this.timing.Has(which) ? this.timing[which] : def

    _Ocr(rect, scale := PotionsTask.OcrScale) {
        try {
            return String(this._ocrFn.Call(rect, scale))
        } catch {
            return ""
        }
    }

    _CfgInt(path, def, lo, hi) {
        v := def
        try v := this._cfg.Get(path, def)
        if !IsInteger(v)
            return def
        v := Integer(v)
        return (v < lo || v > hi) ? def : v
    }

    ; -> object with the 9 calibrations, or "" (this._missing lists the gaps).
    _LoadCal() {
        c := {}
        missing := ""
        add := (s) => missing .= (missing = "" ? "" : ", ") s
        for id in PotionsTask.PointIds {
            p := ""
            try p := this._cal.Point(id)
            if (IsObject(p) && p.HasProp("x") && p.HasProp("y") && IsInteger(p.x) && IsInteger(p.y))
                c.%id% := p
            else
                add(id)
        }
        for id in PotionsTask.RectIds {
            r := ""
            try r := this._cal.Rect(id)
            if PotionsTask._GoodRect(r)
                c.%id% := r
            else
                add(id)
        }
        amt := ""
        try amt := this._cal.Rect(PotionsTask.AmountId)
        if !PotionsTask._GoodRect(amt) {
            e := ""
            try e := this._cal.Sig("inv_amount_empty")       ; an older recording of the same box
            if PotionsTask._GoodRect(e)
                amt := {x: e.x, y: e.y, w: e.w, h: e.h}
        }
        if PotionsTask._GoodRect(amt)
            c.inv_amount := amt
        else
            add(PotionsTask.AmountId)
        ; tile 2 must be the next tile: its rect does not overlap tile 1's
        ; (spacing >= tile width, or >= height for a column) and has the same
        ; size within 20%
        if (c.HasProp("inv_tile1_rect") && c.HasProp("inv_tile2_rect")) {
            t1 := c.inv_tile1_rect, t2 := c.inv_tile2_rect
            if !(Abs(t2.x - t1.x) >= t1.w || Abs(t2.y - t1.y) >= t1.h)
                add("inv_tile2_rect (tile spacing: overlaps tile 1)")
            else if (Abs(t2.w - t1.w) * 5 > t1.w || Abs(t2.h - t1.h) * 5 > t1.h)
                add("inv_tile2_rect (tile spacing: size differs from tile 1 by more than 20%)")
        }
        this._missing := missing
        return (missing = "") ? c : ""
    }

    static _GoodRect(r) => (IsObject(r) && r.HasProp("x") && r.HasProp("y") && r.HasProp("w") && r.HasProp("h")
        && IsInteger(r.x) && IsInteger(r.y) && IsInteger(r.w) && IsInteger(r.h) && r.w > 0 && r.h > 0)

    ; ---- checks -------------------------------------------------------------

    _IsDry() {
        return (this._cfg.Get("General.dryRun", 1) != 0) || (this._cfg.Get("Potions.dryRun", 0) != 0)
    }

    ; Stopped (ctx: F3 / pause / preempt) OR Roblox not in front. Checked
    ; before every click and key, also inside the NoTimers section where the
    ; App tick cannot notice focus loss (2026-10-27 review).
    _Stopped(ctx) => (IsObject(ctx) && ctx.ShouldStop()) || !this._Front()

    _Front() {
        try {
            return this._activeFn.Call() ? true : false
        } catch {
            return false
        }
    }

    ; Polls the log (pollFn), then: state.rareActive AND state.biome is this
    ; biome AND state.rareTs is this event's ts (a newer rare event of the
    ; same biome ends the old one). A failing poll or unreadable state counts
    ; as "ended".
    _BiomeActive(ev) {
        biome := ev.biome
        if IsObject(this.pollFn) {
            try {
                this.pollFn.Call()
            } catch Any as e {
                this._Log("Potions: biome poll failed (" (e is Error ? e.Message : "error") "); treating biome as ended")
                return false
            }
        }
        try {
            cur := this._state.biome
            ra := this._state.rareActive
            rts := this._state.rareTs
        } catch {
            return false
        }
        b := Biomes.Norm(biome)
        return (ra && b != "" && Biomes.Norm(cur) == b && String(rts) !== "" && String(rts) == String(ev.ts)) ? true : false
    }

    ; ---- reporting ----------------------------------------------------------

    _PlanSkip(biome, name, reason, before, dry, extra := "") {
        this._Report(biome, name, "skip", reason, before, "", extra, dry)
        if !PotionsTask.QuietReasons.Has(reason)
            this._Error("Potions: " name " skipped: " reason " (" (PotionsTask.ReasonText.Has(reason) ? PotionsTask.ReasonText[reason] : reason) ")")
        return PotionsTask.HaltReasons.Has(reason) ? reason : ""
    }

    _Stop(biome, name, reason, before, dry) {
        this._Report(biome, name, "skip", reason, before, "", "", dry)
        return reason
    }

    _SkipAll(biome, list, reason, dry) {
        for entry in list
            this._Report(biome, PotionsTask._EntryName(entry), "skip", reason, "", "", "", dry)
    }

    _Report(biome, potion, kind, reason, before, after, extra, dry) {
        txt := PotionsTask.ReasonText.Has(reason) ? PotionsTask.ReasonText[reason] : reason
        tag := dry ? "[DRY RUN] " : ""
        counts := (before != "" || after != "")
            ? "count " (before = "" ? "?" : before) " -> " (after = "" ? "?" : after) : ""
        verb := (kind = "used") ? "used" : (kind = "used_unverified") ? "used (verify failed)"
            : (kind = "used_unchecked") ? "used (count not verified)"
            : (kind = "dry") ? "would use" : "skipped"
        title := tag "Potion " verb ": " potion
        desc := "## " StrUpper(SubStr(verb, 1, 1)) SubStr(verb, 2) "`n**" potion "**"
        fields := [Webhook.Field(Emoji.Globe " Biome", biome), Webhook.Field("Reason", reason " (" txt ")")]
        if (counts != "")
            fields.Push(Webhook.Field("Count", StrReplace(counts, "count ", "")))
        if (extra != "")
            fields.Push(Webhook.Field("Detail", extra, false))
        color := (kind = "used") ? 0x2ECC71 : (kind = "used_unverified") ? 0xE74C3C
            : (kind = "dry" || kind = "used_unchecked") ? 0xF2A93B : 0x95A5A6
        this._Log("Potions: " tag verb " " potion " [" reason "]" (extra != "" ? " " extra : "") (counts != "" ? " " counts : ""))
        if IsObject(this._wh) {
            try this._wh.Send("potions", title, desc, color, {fields: fields})
        }
    }

    _Error(msg) {
        this._Log(msg)
        if IsObject(this._wh) {
            try this._wh.Send("errors", "Potion step problem", msg, 0xE74C3C)
        }
    }

    _Log(t) {
        if IsObject(this._logFn) {
            try this._logFn.Call(t)
        }
    }

    ; OCR text on one line, at most 160 chars (reports).
    static _Flat(s) {
        t := Trim(RegExReplace(String(s), "\s*[\r\n]+\s*", " / "))
        return (StrLen(t) > 160) ? SubStr(t, 1, 157) "..." : t
    }

    ; Biome list entry -> potion id ("id" key, else "name"), or "(bad entry)".
    static _EntryName(entry) {
        if !(entry is Map)
            return "(bad entry)"
        for k in ["id", "name"]
            if (entry.Has(k) && entry[k] is String && Trim(entry[k]) != "")
                return Trim(entry[k])
        return "(bad entry)"
    }
}
