#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\Json.ahk
#Include %A_LineFile%\..\Screen.ahk
#Include %A_LineFile%\..\Roblox.ahk
#Include %A_LineFile%\..\Calibrate.ahk
#Include %A_LineFile%\..\AutoCal.ahk
#Include %A_LineFile%\..\Ocr.ahk
#Include %A_LineFile%\..\Pixel.ahk
#Include %A_LineFile%\..\Input.ahk
#Include %A_LineFile%\..\CalHealth.ahk
; ---------------------------------------------------------------------------
; CalTest: the "Test my calibration" button. Every RECORDED calibration step
; gets a verdict: OK, REDO (with why) or NOT TESTED (with why). Steps that
; are not recorded are left to "Check my setup" (lib\SetupCheck.ahk).
;
;   CalTest.Run(cfg, probes := "") -> Array of rows
;       {id, name, level: "ok"|"fail"|"info", verdict: "OK"|"REDO"|
;        "NOT TESTED"|"" (a note), detail, fix}
;     Notes first (ids starting "_": the calibration in use, the live
;     test's own result), then the steps: REDO, OK, NOT TESTED, each in the
;     Calibrate page's order. level is what the Check page's tags use.
;   CalTest.Summary(rows) -> "1 to redo, 12 ok, 25 not tested"
;   CalTest.Report(rows)  -> plain text block
;
; THREE KINDS OF EVIDENCE, the strongest first:
;  (a) STATIC, every recorded step, no input: it lies on the game screen
;      (2560x1440 design space) and, mapped the way its window scales
;      (Screen.Mode, ModeOf), inside the Roblox window now; a box is big
;      enough to read; where it was recorded: the client size kept with it
;      (Calibrate.RecordedAt), else the shipped preset whose spot it is.
;      Every spot is design space mapped the way its window scales, so
;      another size is fine and another shape is only named (if it misses,
;      record it again); the chat box recorded at another size (it keeps
;      its size in pixels) -> REDO.
;  (b) LIVE, only with the macro stopped, Roblox open and brought to the
;      front; Roblox must be in front before EVERY click (else the test
;      stops: nothing more is sent). Only clicks the tasks make anyway:
;        inventory: inv_open (not when it is open already), its Items tab,
;          reads of the tabs, the search box, the tiles, Use and the
;          description (AutoCal.Inventory: where they are on screen), then
;          inv_open again while its tabs still read (as TaskEnv.CloseInv).
;        Aura Storage: aura_open, its title over aura_search, the
;          [Information] header over aura_equip, then its X (aura_close)
;          only while its title reads and no "delete / lock / sell" word
;          reads on it; else its sidebar button toggles it shut.
;        reads only: buff_expand's colour, text in chat_rect.
;      Nothing is ever bought, used, equipped or confirmed; never Esc. A
;      Roblox purchase prompt on screen stops the live test (no click).
;      What this test opened it closes; what was open it leaves open.
;  (c) HISTORY (lib\CalHealth.ahk) for the spots that need walking: how
;      the step did each time a task used it. FailRun misses in a row ->
;      REDO; the last use worked -> OK.
;
; PROBES (every system call; tests run offline), all optional:
;   steps ()            Array of {id, kind, v: {x, y[, w, h]}, at}
;   client ()           {w, h} of the Roblox client, "" = not open
;   presets ()          Array of {w, h, label, steps: Map id -> Map}
;   health (id)         CalHealth.Get(id)
;   running ()          the macro is running (App: started)
;   hwnd ()             Roblox window id or 0
;   focus ()            bring Roblox to the front -> true when it is
;   front ()            Roblox is the foreground window (before each click)
;   click (pt, mode)    one click at a design point in that Screen mode ->
;                       1 sent | 0 refused (Input.ClickGuard + Input.Click)
;   wait (ms)
;   ocr (x, y, w, h, scale)    text (design px, the current Screen.Mode)
;   lines (x, y, w, h, scale)  Array of {text, x, y, l, t, r, b}
;   pixel (x, y, color, tol)   bool
;   purchaseUp ()       a Roblox purchase prompt reads
;   now ()              A_Now (the "today 13:05" in the history lines)
; A probe that throws counts as "could not" (never an error).
; ---------------------------------------------------------------------------

class CalTest {
    static FailRun := 2            ; misses in a row (history) -> REDO
    static MinBox := 8             ; a box narrower / lower than this cannot be read
    static ChatSizeTol := 0.1      ; chat_rect recorded this far from the size now (log of the scale) -> REDO
    static OpenMs := 900           ; after a click that opens a window
    static PollMs := 500
    static TabMs := 500            ; after the Items tab click
    static CloseMs := 700
    static CloseTries := 3
    static SearchTolX := 220       ; the search box is wide: anywhere on it
    static SearchTolY := 22
    static UseTol := 36
    static DescTol := 30
    ; the Aura Storage's own reads (ObbyTask: StorageBox / StorageRe /
    ; StorageScale / PanelBox / PanelRe / NeverRe; tested equal)
    static StorageBox := {dx: -200, dy: -135, w: 650, h: 85}
    static StorageRe := "i)st[o0]r[ao][go][e3]"
    static StorageScale := 2
    static PanelBox := {dx: -210, dy: -262, w: 260, h: 66}
    static PanelRe := "i)nf[o0]rmati[o0]n"
    static NeverRe := "i)delete|lock|sell|remove|discard"
    static CloseBox := {dx: -110, dy: -35, w: 220, h: 70}
    ; the storage's title found anywhere in the middle of the screen
    static TitleRe := "i)aur[ao]\s*st[o0]r[ao]g"
    static TitleArea := {l: 600, t: 150, r: 2000, b: 800}
    static TabsRe := "i)item|gear"

    ; the Screen mode each step's window maps in
    static ModeOf(id) => Calibrate.ModeOf(id)

    ; why a step without live test or history is not tested
    static Needs := [["fisher_", "needs you at Captain Flarg (the Fisher)"], ["cauldron_", "needs you at Stella's cauldron"]
        , ["stella_", "needs you at Stella"], ["quest_", "needs you at the quest board"], ["selector_", "needs the Biome Selector open"]
        , ["obby_", "needs the obby's blessing"], ["daily_", "needs the Daily Rewards popup"], ["notify_rect", "needs an in-game notification"]
        , ["inv_", "needs a potion picked in the inventory"], ["aura_", "needs a search in the Aura Storage"]
        , ["chat_rect", "needs chat text on screen"], ["buff_expand", "needs the buff list closed"]]
    ; steps the live part can test (when it cannot run, they say why)
    ; (inv_use / inv_desc_rect only when an item happens to be picked)
    static LiveIds := ["inv_open", "inv_items_tab", "inv_search", "inv_tile1_rect", "inv_tile2_rect", "inv_count_rect"
        , "aura_open", "aura_search", "aura_equip", "aura_close", "buff_expand", "chat_rect"]

    static Run(cfg, probes := "") {
        P := (key) => (probes is Map && probes.Has(key)) ? probes[key] : ""
        call := (key, def, args*) => CalTest._Call(P(key), def, args*)

        st := call("steps", () => CalTest._Steps())
        steps := (st.ok && st.v is Array) ? st.v : []
        cl := call("client", () => CalTest._Client())
        client := (cl.ok && IsObject(cl.v) && cl.v.HasProp("w")) ? cl.v : ""
        pr := call("presets", () => CalTest._Presets())
        presets := (pr.ok && pr.v is Array) ? pr.v : []
        nw := call("now", () => A_Now)
        now := nw.ok ? nw.v : A_Now

        notes := []
        note := (id, name, detail, fix := "") => notes.Push({id: id, name: name, level: "info", verdict: "", detail: detail, fix: fix})
        if !st.ok
            note("_source", "Calibration", "could not read the calibration")
        else
            note("_source", "Calibration", CalTest._SourceText(steps, client, presets))

        ; (a) static
        res := Map(), origin := Map(), byId := Map()
        for s in steps {
            byId[s.id] := s
            r := CalTest.Static(s, client, presets)
            origin[s.id] := r.origin
            if (r.v = "redo")
                res[s.id] := r
        }

        ; (b) live
        live := CalTest._LiveRun(byId, res, call, &why)
        if (why != "")
            note("_live", "Live test", why)
        else
            note("_live", "Live test", live.Summary())

        ; (c) history, and the rows
        out := Map("redo", [], "ok", [], "untested", [])
        for s in steps {
            id := s.id
            if res.Has(id)
                r := res[id]
            else if live.out.Has(id) && live.out[id].v != "untested"
                r := live.out[id]
            else {
                h := call("health", (i) => CalHealth.Get(i), id)
                r := CalTest.FromHistory(h.ok ? h.v : "", now)
                if (r.v = "untested" && r.why = "") {
                    if live.out.Has(id)
                        r := live.out[id]
                    else if (why != "" && CalTest._Has(CalTest.LiveIds, id))
                        r := {v: "untested", why: "not tested: " RegExReplace(why, "^\w+: ")}
                    else if (live.ran && CalTest._Has(CalTest.LiveIds, id))
                        r := {v: "untested", why: "not tested: the live test did not get to it (see the Live test line)"}
                    else
                        r := {v: "untested", why: "not tested: " CalTest.NeedText(id) "; no use noted yet (the tasks note each use)"}
                }
            }
            det := r.why
            if (origin[id] != "")
                det .= " [" origin[id] "]"
            fix := (r.v = "redo") ? "Record " id " again on the Calibrate page" (InStr(origin[id], "preset") ? ", or apply the preset for your screen" : "") : ""
            out[r.v].Push({id: id, name: id, level: r.v = "redo" ? "fail" : r.v = "ok" ? "ok" : "info"
                , verdict: r.v = "redo" ? "REDO" : r.v = "ok" ? "OK" : "NOT TESTED", detail: det, fix: fix})
        }
        rows := []
        for n in notes
            rows.Push(n)
        for k in ["redo", "ok", "untested"]
            for r in out[k]
                rows.Push(r)
        return rows
    }

    static Summary(rows) {
        n := Map("REDO", 0, "OK", 0, "NOT TESTED", 0)
        for r in rows
            if n.Has(r.verdict)
                n[r.verdict] += 1
        return n["REDO"] " to redo, " n["OK"] " ok, " n["NOT TESTED"] " not tested"
    }

    static Report(rows) {
        s := "Calibration test: " CalTest.Summary(rows) "`r`n`r`n"
        for r in rows {
            tag := r.verdict = "" ? "[INFO]" : r.verdict = "NOT TESTED" ? "[ -- ]" : r.verdict = "OK" ? "[ OK ]" : "[REDO]"
            s .= tag " " r.name ": " r.detail "`r`n"
            if (r.fix != "")
                s .= "        What to do: " r.fix "`r`n"
        }
        return s
    }

    ; ---- (a) static ---------------------------------------------------------

    ; s {id, v, at}, client {w, h} or "", presets -> {v: "redo"|"", why, origin}
    static Static(s, client, presets) {
        v := s.v, id := s.id
        isRect := v.HasProp("w")
        org := CalTest.Origin(s, client, presets)
        redo := (why) => {v: "redo", why: why, origin: org.text}
        if (v.x < 0 || v.y < 0 || v.x > Screen.DesignW || v.y > Screen.DesignH
            || (isRect && (v.x + v.w > Screen.DesignW || v.y + v.h > Screen.DesignH)))
            return redo("it lies off the game screen (" CalTest._Pos(v) ")")
        if (isRect && (v.w < CalTest.MinBox || v.h < CalTest.MinBox))
            return redo("its box is only " v.w "x" v.h ": too small to read anything")
        if IsObject(client) && !CalTest.MapsInside(v, CalTest.ModeOf(id), client)
            return redo("it falls outside your Roblox window (" client.w "x" client.h ")")
        ; every spot is kept in 2560x1440 design space and mapped the way its
        ; window scales, so another size or shape is fine, except the chat:
        ; it keeps its size in pixels (the presets differ only in chat_rect)
        if (IsObject(client) && IsObject(org.size)) {
            sz := org.size
            if (id = "chat_rect" && Abs(Ln(Sqrt((sz.w * sz.h) / (client.w * client.h)))) > CalTest.ChatSizeTol)
                return redo(org.text " but your Roblox is " client.w "x" client.h ": the chat keeps its size in pixels, so it needs a recording at your size")
            if !CalTest.SameShape(sz, client)
                return {v: "", why: "", origin: org.text ", another shape than your Roblox now: if it misses, record it again"}
        }
        return {v: "", why: "", origin: org.text}
    }

    ; Where the step comes from: {text, size ({w, h} or "")}
    static Origin(s, client, presets) {
        if (s.HasProp("at") && RegExMatch(s.at, "^(\d+)x(\d+)$", &m))
            return {text: "recorded at " s.at, size: {w: Integer(m[1]), h: Integer(m[2])}}
        same := []
        for p in presets
            if (p.steps is Map && p.steps.Has(s.id) && CalTest._Equal(p.steps[s.id], s.v))
                same.Push(p)
        if !same.Length
            return {text: "", size: ""}
        pick := same[1]
        if IsObject(client) {
            for p in same
                if (p.w = client.w && p.h = client.h)
                    return {text: "the " p.label " preset's spot", size: {w: p.w, h: p.h}}
            for p in same
                if CalTest.SameShape(p, client) {
                    pick := p
                    break
                }
        }
        return {text: "the " pick.label " preset's spot", size: {w: pick.w, h: pick.h}}
    }

    static SameShape(a, b) => (a.w > 0 && a.h > 0 && b.w > 0 && b.h > 0) && Abs(Ln((a.w / a.h) / (b.w / b.h))) <= Calibrate.AspectTol

    ; the point (both corners of a rect) maps inside a w x h client in `mode`
    static MapsInside(v, mode, client) {
        old := [Screen.cx, Screen.cy, Screen.cw, Screen.ch], oldMode := Screen.Mode
        try {
            Screen.SetClient(0, 0, client.w, client.h)
            Screen.Mode := mode
            pts := v.HasProp("w") ? [[v.x, v.y], [v.x + v.w, v.y + v.h]] : [[v.x, v.y]]
            for p in pts {
                X := Screen.X(p[1]), Y := Screen.Y(p[2])
                if (X < 0 || Y < 0 || X > client.w || Y > client.h)
                    return false
            }
            return true
        } finally {
            Screen.SetClient(old*)
            Screen.Mode := oldMode
        }
    }

    ; ---- (c) history ----------------------------------------------------------

    ; h: CalHealth.Get's record or "" -> {v: "redo"|"ok"|"untested", why}
    static FromHistory(h, now := "") {
        if !IsObject(h) || (h.ok + h.fail = 0)
            return {v: "untested", why: ""}
        why := (h.why != "" ? ": " h.why : "")
        if (h.run >= CalTest.FailRun)
            return {v: "redo", why: "did not work the last " h.run " times it was used (last " CalTest.When(h.lastFail, now) why ")"}
        if (h.run = 1)
            return {v: "untested", why: "not sure: it missed the last time (" CalTest.When(h.lastFail, now) why ")"
                . (h.ok ? " after working " CalTest._Times(h.ok) : "") "; one more miss and it needs redoing"}
        return {v: "ok", why: "worked " CalTest._Times(h.ok) ", last " CalTest.When(h.lastOk, now)
            . (h.fail ? " (missed " CalTest._Times(h.fail) " before)" : "")}
    }

    ; "today 13:05" / "yesterday 13:05" / "2026-11-20 13:05"
    static When(stamp, now := "") {
        if !RegExMatch(stamp, "^\d{14}$")
            return "at an unknown time"
        now := RegExMatch(now, "^\d{14}$") ? now : A_Now
        t := FormatTime(stamp, "HH:mm")
        d := SubStr(stamp, 1, 8), today := SubStr(now, 1, 8)
        if (d = today)
            return "today " t
        y := DateAdd(today, -1, "Days")
        if (d = SubStr(y, 1, 8))
            return "yesterday " t
        return FormatTime(stamp, "yyyy-MM-dd") " " t
    }

    static NeedText(id) {
        for n in CalTest.Needs
            if (SubStr(id, 1, StrLen(n[1])) = n[1])
                return n[2]
        return "it is only used while a task runs"
    }

    ; ---- (b) live --------------------------------------------------------------

    ; -> the CalLive (its out Map: id -> {v, why}); why = why it did not run
    static _LiveRun(byId, res, call, &why) {
        L := CalLive(call, byId)
        why := ""
        ru := call("running", () => false)
        if (ru.ok && ru.v) {
            why := "skipped: the macro is running (stop it with F3, then test again)"
            return L
        }
        h := call("hwnd", () => Roblox.Hwnd())
        if !(h.ok && h.v) {
            why := "skipped: Roblox is not open"
            return L
        }
        fo := call("focus", () => Roblox.Focus(2))
        if !(fo.ok && fo.v) {
            why := "skipped: Roblox could not be brought to the front"
            return L
        }
        L.bad := res
        if L.PurchaseUp() {
            why := "stopped: a Roblox purchase prompt is open (close it yourself, never press Buy), then test again"
            return L
        }
        L.ran := true
        CalTest._Inventory(L)
        CalTest._Aura(L)
        CalTest._Reads(L)
        return L
    }

    static _Inventory(L) {
        if !(L.Can("inv_open") && L.Can("inv_items_tab"))
            return
        if L.aborted
            return
        tab := L.V("inv_items_tab"), openPt := L.V("inv_open")
        ; open already: its tabs read where recorded, or the window is found
        ; on screen. bug hunt 2026-11-27: with inv_items_tab off, an open
        ; inventory was taken for closed, inv_open's click shut it, then
        ; inv_open got REDO and the tab (the wrong step) NOT TESTED.
        was := L.TabsRead(tab)
        if !was {
            pre := AutoCal.Inventory(L.Lines("C"))
            was := IsObject(pre) && L.TabsRead(pre.tab)
        }
        clicked := false
        if was
            L.Set("inv_open", "untested", "not tested: the inventory was open already (left as it was)")
        else {
            if !L.Click(openPt, "C")
                return
            clicked := true
            L.leftOpen := "the inventory (its button on the left closes it)"
            L.Wait(CalTest.OpenMs)
            if !L.Front()
                return
        }
        tabAt := ""
        if L.TabsRead(tab) || (clicked && L.Wait(CalTest.PollMs) && L.Front() && L.TabsRead(tab)) {
            tabAt := tab
            if clicked
                L.Set("inv_open", "ok", "a click on it opened the inventory")
            L.Set("inv_items_tab", "ok", "the inventory's Gears / Items tabs read there")
        } else {
            if L.aborted
                return
            inv := AutoCal.Inventory(L.Lines("C"))
            if (IsObject(inv) && L.TabsRead(inv.tab)) {
                tabAt := inv.tab
                if clicked
                    L.Set("inv_open", "ok", "a click on it opened the inventory")
                L.Set("inv_items_tab", "redo", "the inventory's tabs do not read there; on your screen its Items tab is at " CalTest._Pos(inv.tab))
            } else {
                if clicked {
                    L.Set("inv_open", "redo", "a click on it did not open the inventory (no inventory title or tabs read after it)")
                    L.leftOpen := ""
                    L.notes.Push("if the inventory did open, close it yourself")
                }
                return
            }
        }
        ; the Items tab (where it reads), then a look at the window
        if !L.Click(tabAt, "C")
            return
        L.Wait(CalTest.TabMs)
        if !L.Front()
            return
        inv := AutoCal.Inventory(L.Lines("C"))
        if (IsObject(inv) && !(IsObject(inv.search) && IsObject(inv.tile1) && IsObject(inv.use)))
            inv := AutoCal.InvMerge(inv, AutoCal.Inventory(L.Lines("C", inv.box, 2), inv.title))
        CalTest._InvParts(L, inv)
        if clicked
            CalTest._InvClose(L, openPt, tabAt)
    }

    static _InvParts(L, inv) {
        has := (k) => IsObject(inv) && IsObject(inv.%k%)
        if L.Can("inv_search") {
            r := L.V("inv_search")
            if has("search") {
                s := inv.search
                if (Abs(r.x - s.x) <= CalTest.SearchTolX && Abs(r.y - s.y) <= CalTest.SearchTolY)
                    L.Set("inv_search", "ok", "it is on the search box (the box's text reads at " CalTest._Pos(s) ")")
                else
                    L.Set("inv_search", "redo", "the search box is at " CalTest._Pos(s) " on your screen")
            } else
                L.Set("inv_search", "untested", "not tested: the search box's text did not read")
        }
        if L.Can("inv_tile1_rect") {
            r := L.V("inv_tile1_rect")
            t := L.Ocr("C", r.x, r.y, r.w, r.h, 2)
            if (CalTest._Letters(t) >= 3)
                L.Set("inv_tile1_rect", "ok", "an item name reads in it ('" CalTest._Short(t) "')")
            else if has("tile1")
                L.Set("inv_tile1_rect", "redo", "no item name reads in it; the first tile's name is at " CalTest._Pos(inv.tile1))
            else
                L.Set("inv_tile1_rect", "untested", "not tested: no item name read in the first tile (is your Items tab empty?)")
        }
        if L.Can("inv_tile2_rect") {
            r := L.V("inv_tile2_rect")
            t := L.Ocr("C", r.x, r.y, r.w, r.h, 2)
            if (CalTest._Letters(t) >= 3)
                L.Set("inv_tile2_rect", "ok", "an item name reads in it ('" CalTest._Short(t) "')")
            else
                L.Set("inv_tile2_rect", "untested", "not tested: nothing reads in it (fewer than two items?)")
        }
        if L.Can("inv_count_rect") {
            r := L.V("inv_count_rect")
            t := L.Ocr("C", r.x, r.y, r.w, r.h, 2)
            if RegExMatch(t, "\d")
                L.Set("inv_count_rect", "ok", "a count reads in it ('" CalTest._Short(t) "')")
            else
                L.Set("inv_count_rect", "untested", "not tested: no count reads in it")
        }
        ; Use and the description show only with an item picked: judged when
        ; one happens to be
        if L.Can("inv_use") && has("use") {
            r := L.V("inv_use"), u := inv.use
            if (Abs(r.x - u.x) <= CalTest.UseTol && Abs(r.y - u.y) <= CalTest.UseTol)
                L.Set("inv_use", "ok", "it is on the Use button (Use reads at " CalTest._Pos(u) ")")
            else
                L.Set("inv_use", "redo", "the Use button is at " CalTest._Pos(u) " on your screen")
        }
        if L.Can("inv_desc_rect") && has("desc") {
            r := L.V("inv_desc_rect"), d := inv.desc
            if (Abs(r.x - d.x) <= CalTest.DescTol && Abs(r.y - d.y) <= CalTest.DescTol)
                L.Set("inv_desc_rect", "ok", "it is on the description under Use")
            else
                L.Set("inv_desc_rect", "redo", "the description under Use is at " CalTest._Pos(d) " on your screen")
        }
    }

    ; inv_open again while the tabs still read (TaskEnv.CloseInv)
    static _InvClose(L, openPt, tabAt) {
        Loop CalTest.CloseTries {
            if !L.TabsRead(tabAt) {
                L.leftOpen := ""
                return true
            }
            if !L.Click(openPt, "C")
                return false
            L.Wait(CalTest.CloseMs)
            if !L.Front()
                return false
        }
        if !L.TabsRead(tabAt) {
            L.leftOpen := ""
            return true
        }
        L.notes.Push("the inventory is still open after " CalTest.CloseTries " clicks on inv_open: close it yourself")
        L.leftOpen := ""
        return false
    }

    static _Aura(L) {
        if !(L.Can("aura_open") && L.Can("aura_search")) || L.aborted
            return
        op := L.V("aura_open"), srch := L.V("aura_search")
        eq := L.Can("aura_equip") ? L.V("aura_equip") : ""
        clicked := false
        ; open already: as _AuraClose's check (its title over aura_search,
        ; the [Information] header over aura_equip, or the title found on
        ; screen). bug hunt 2026-11-27: with aura_search off, the open
        ; storage was shut by aura_open's click, aura_open got REDO and
        ; aura_search NOT TESTED. The header read on no other of the 397
        ; tests\screens frames.
        if (L.TitleRead(srch) || (IsObject(eq) && L.PanelRead(eq)) || IsObject(CalTest.StorageLine(L.Lines("C")))) {
            L.Set("aura_open", "untested", "not tested: the Aura Storage was open already (left as it was)")
            if L.Can("aura_close")
                L.Set("aura_close", "untested", "not tested: the Aura Storage was open already (left as it was)")
        } else {
            if !L.Click(op, "C")
                return
            clicked := true
            L.leftOpen := "the Aura Storage (its X, top right)"
            L.Wait(CalTest.OpenMs)
            Loop 3 {
                if !L.Front()
                    return
                if L.TitleRead(srch)
                    break
                if (A_Index < 3)
                    L.Wait(CalTest.PollMs)
            }
        }
        found := ""
        up := L.TitleRead(srch) ? "title" : (IsObject(eq) && L.PanelRead(eq)) ? "panel"
            : IsObject(found := CalTest.StorageLine(L.Lines("C"))) ? "found" : ""
        if clicked
            L.Set("aura_open", up != "" ? "ok" : "redo", up != "" ? "a click on it opened the Aura Storage"
                : "a click on it did not open the Aura Storage (its title did not read)")
        if (up = "") {
            if clicked {
                L.leftOpen := ""
                L.notes.Push("if the Aura Storage did open, close it yourself (its X, top right)")
            }
            return
        }
        if (up = "title")
            L.Set("aura_search", "ok", "the Aura Storage's title reads right above it")
        else
            L.Set("aura_search", "redo", "the Aura Storage's title does not read where it should above it" (IsObject(found) ? "; the title is at " CalTest._Pos(found) : ""))
        if IsObject(eq) {
            if (up = "panel" || L.PanelRead(eq))
                L.Set("aura_equip", "ok", "the storage's [Information] header reads above it, as over Equip")
            else if (up = "title")
                L.Set("aura_equip", "redo", "the storage's [Information] header does not read where it should above it")
        }
        if clicked
            CalTest._AuraClose(L, op, srch, eq, up)
    }

    ; its X only while its title reads and no "delete / lock / sell" word
    ; reads on it; else (or when the X did not close it) its sidebar button
    static _AuraClose(L, op, srch, eq, up) {
        storageUp := () => L.TitleRead(srch) || (IsObject(eq) && L.PanelRead(eq)) || IsObject(CalTest.StorageLine(L.Lines("C")))
        if (up = "title" && L.Can("aura_close")) {
            c := L.V("aura_close"), b := CalTest.CloseBox
            t := L.Ocr("C", c.x + b.dx, c.y + b.dy, b.w, b.h)
            if RegExMatch(t, CalTest.NeverRe) {
                L.Set("aura_close", "redo", "it sits on a button that reads '" CalTest._Short(t) "': not clicked")
            } else {
                if !L.Click(c, "C")
                    return
                L.Wait(CalTest.CloseMs)
                if !L.Front()
                    return
                if !storageUp() {
                    L.Set("aura_close", "ok", "a click on it closed the Aura Storage")
                    L.leftOpen := ""
                    return
                }
                L.Set("aura_close", "redo", "a click on it did not close the Aura Storage")
            }
        }
        if !L.Click(op, "C")
            return
        L.Wait(CalTest.CloseMs)
        if !L.Front()
            return
        L.leftOpen := ""
        if storageUp()
            L.notes.Push("the Aura Storage is still open: close it yourself (its X, top right)")
    }

    ; reads only
    static _Reads(L) {
        if L.aborted
            return
        if L.Can("buff_expand") {
            b := L.V("buff_expand")
            if L.PixelIs(b.x, b.y, b.HasProp("color") ? b.color : "", 20)
                L.Set("buff_expand", "ok", "it shows its recorded colour (the buff list button)")
            else
                L.Set("buff_expand", "untested", "not tested: it does not show its recorded colour right now (the buff list may be open, or something covers it)")
        }
        if L.Can("chat_rect") {
            r := L.V("chat_rect")
            n := 0
            for ln in L.Lines("S", r)
                n += CalTest._Letters(ln.text)
            if (n >= 6)
                L.Set("chat_rect", "ok", "chat text reads in it")
            else
                L.Set("chat_rect", "untested", "not tested: nothing reads in it right now (chat closed or empty)")
        }
    }

    ; the Aura Storage's title line in the middle of the screen, or ""
    static StorageLine(lines) {
        a := CalTest.TitleArea
        if !(lines is Array)
            return ""
        for ln in lines
            if (RegExMatch(ln.text, CalTest.TitleRe) && ln.x >= a.l && ln.x <= a.r && ln.y >= a.t && ln.y <= a.b)
                return ln
        return ""
    }

    ; ---- defaults and helpers ---------------------------------------------------

    static _Steps() {
        out := []
        for s in Calibrate.Steps() {
            id := s["id"]
            k := Calibrate.StoredKey(id)
            if (k = "")
                continue
            p := StrSplit(k, ",")
            v := (p.Length >= 4) ? {x: Integer(p[1]), y: Integer(p[2]), w: Integer(p[3]), h: Integer(p[4])} : {x: Integer(p[1]), y: Integer(p[2])}
            if (p.Length < 4) {
                pt := ""
                try pt := Calibrate.Point(id)
                v.color := (IsObject(pt) && pt.x = v.x && pt.y = v.y) ? pt.color : ""
            }
            out.Push({id: id, kind: s["kind"], v: v, at: Calibrate.RecordedAt(id)})
        }
        return out
    }

    static _Client() {
        if (Roblox.ClientOk() != "ok")
            return ""
        return {x: Screen.cx, y: Screen.cy, w: Screen.cw, h: Screen.ch}
    }

    static _Presets() {
        out := []
        for p in Calibrate.Presets() {
            root := ""
            try root := Json.Parse(FileRead(p.path, "UTF-8"))
            if (root is Map && root.Has("steps") && root["steps"] is Map)
                out.Push({w: p.w, h: p.h, label: p.label, steps: root["steps"]})
        }
        return out
    }

    static _SourceText(steps, client, presets) {
        n := steps.Length
        if !n
            return "no step is recorded yet (Check my setup lists the ones your features need)"
        cur := 0, other := Map(), at := 0, shape := 0
        for s in steps {
            o := CalTest.Origin(s, client, presets)
            if (IsObject(o.size) && IsObject(client) && !CalTest.SameShape(o.size, client))
                shape++
            if (s.HasProp("at") && s.at != "")
                at++
            else if (IsObject(o.size) && IsObject(client) && o.size.w = client.w && o.size.h = client.h)
                cur++
            else if IsObject(o.size)
                other[o.size.w "x" o.size.h] := (other.Has(o.size.w "x" o.size.h) ? other[o.size.w "x" o.size.h] : 0) + 1
        }
        t := n " step" (n = 1 ? "" : "s") " recorded"
        t .= IsObject(client) ? "; your Roblox is " client.w "x" client.h : "; Roblox is not open, so the size checks were skipped"
        if cur
            t .= "; " cur " match the preset for your size"
        for k, c in other
            t .= "; " c " match the " k " preset"
        if at
            t .= "; " at " recorded by you"
        hand := n - cur - at
        for k, c in other
            hand -= c
        if (hand > 0)
            t .= "; " hand " recorded by hand before sizes were kept"
        if shape
            t .= "; " shape " come from another screen shape (fine while they work)"
        return t
    }

    ; the real click: shift lock off first (Input.ClickGuard), then the
    ; macro's own click (ChatGuard moves the chat off it). -> 1 | 0
    static _RealClick(pt, mode) {
        return Screen.WithMode(mode, () => (Input.ClickGuard("", "", "the calibration test") > 0) ? (Input.Click(pt.x, pt.y), 1) : 0)
    }

    static _Call(fn, def, args*) {
        try {
            return {ok: true, v: IsObject(fn) ? fn(args*) : def(args*)}
        } catch Any {
            return {ok: false, v: ""}
        }
    }

    static _Equal(e, v) {
        if !(e is Map && e.Has("x") && e.Has("y"))
            return false
        if (e["x"] != v.x || e["y"] != v.y)
            return false
        if v.HasProp("w")
            return e.Has("w") && e.Has("h") && e["w"] = v.w && e["h"] = v.h
        return !e.Has("w")
    }

    static _Has(list, id) {
        for x in list
            if (x = id)
                return true
        return false
    }

    static _Pos(v) => v.x "," v.y
    static _Letters(t) => StrLen(RegExReplace(String(t), "[^A-Za-z]"))
    static _Short(t) => SubStr(Trim(RegExReplace(String(t), "\s+", " ")), 1, 30)
    static _Times(n) => n = 1 ? "once" : n = 2 ? "twice" : n " times"
}

; The live part's state: every probe call, the focus check before each
; click, what was found per step and what is still open.
class CalLive {
    __New(call, byId) {
        this.call := call
        this.st := byId
        this.bad := Map()           ; steps the static checks already failed
        this.out := Map()
        this.notes := []
        this.aborted := false
        this.lostFocus := false
        this.ran := false
        this.clicks := 0
        this.leftOpen := ""
    }

    ; recorded, and not already failed by the static checks
    Can(id) => this.st.Has(id) && !this.bad.Has(id)
    V(id) => this.st[id].v
    Set(id, v, why) => this.out[id] := {v: v, why: why}

    Front() {
        if this.aborted
            return false
        r := this.call.Call("front", () => WinActive("ahk_exe " Roblox.Exe) ? 1 : 0)
        if (r.ok && r.v)
            return true
        this.aborted := true
        this.lostFocus := true
        return false
    }

    Click(pt, mode) {
        if !this.Front()
            return false
        r := this.call.Call("click", (p, m) => CalTest._RealClick(p, m), pt, mode)
        this.clicks++
        if !(r.ok && r.v) {
            this.aborted := true
            this.notes.Push("a click was refused (shift lock would not turn off?): the test stopped there")
            return false
        }
        return true
    }

    Wait(ms) {
        this.call.Call("wait", (t) => Sleep(t), ms)
        return true
    }

    Ocr(mode, x, y, w, h, scale := 1) {
        r := Screen.WithMode(mode, () => this.call.Call("ocr", (a, b, c, d, e) => Ocr.Read(a, b, c, d, e), x, y, w, h, scale))
        return r.ok ? String(r.v) : ""
    }

    Lines(mode, box := "", scale := 1) {
        b := IsObject(box) ? box : {x: 0, y: 0, w: Screen.DesignW, h: Screen.DesignH}
        r := Screen.WithMode(mode, () => this.call.Call("lines", (a, bb, c, d, e) => Ocr.Lines(a, bb, c, d, e), b.x, b.y, b.w, b.h, scale))
        return (r.ok && r.v is Array) ? r.v : []
    }

    PixelIs(x, y, color, tol) {
        if (color = "")
            return false
        r := this.call.Call("pixel", (a, b, c, d) => Pixel.Is(a, b, c, d), x, y, color, tol)
        return r.ok && r.v
    }

    PurchaseUp() {
        r := this.call.Call("purchaseUp", () => Input.PurchaseUp("", (x, y, w, h) => Ocr.Read(x, y, w, h)))
        return r.ok && r.v
    }

    ; the inventory's tab labels around a tab point, at 2x (TaskEnv.InvOpen)
    TabsRead(tab) => RegExMatch(this.Ocr("C", tab.x - 90, tab.y - 25, 180, 50, 2), CalTest.TabsRe) > 0

    ; the Aura Storage's title over aura_search (ObbyTask._Open)
    TitleRead(srch) {
        b := CalTest.StorageBox
        x := srch.x + b.dx, y := srch.y + b.dy
        return RegExMatch(this.Ocr("C", x, y, b.w, b.h), CalTest.StorageRe)
            || RegExMatch(this.Ocr("C", x, y, b.w, b.h, CalTest.StorageScale), CalTest.StorageRe)
    }

    ; the storage's [Information] header over aura_equip (ObbyTask._Panel)
    PanelRead(eq) {
        b := CalTest.PanelBox
        return RegExMatch(this.Ocr("C", eq.x + b.dx, eq.y + b.dy, b.w, b.h), CalTest.PanelRe) > 0
    }

    Summary() {
        if this.lostFocus
            this.notes.Push("Roblox lost focus mid-test: nothing more was clicked")
        if (this.leftOpen != "")
            this.notes.Push("left open: " this.leftOpen ": close it yourself")
        n := 0
        for id, r in this.out
            n++
        t := "tested " n " step" (n = 1 ? "" : "s") " on screen (" this.clicks " click" (this.clicks = 1 ? "" : "s") ")"
        for s in this.notes
            t .= "; " s
        return t
    }
}
