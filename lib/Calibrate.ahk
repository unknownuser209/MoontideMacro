#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\Brand.ahk
#Include %A_LineFile%\..\Json.ahk
#Include %A_LineFile%\..\Pixel.ahk
#Include %A_LineFile%\..\GameLists.ahk
#Include %A_LineFile%\..\Roblox.ahk
; ---------------------------------------------------------------------------
; Calibrate: guided click-recording wizard + the store tasks read from.
;
; Store: data\calibration.json (via Json.ahk), written atomically (tmp +
; FileMove, with a guard against the target being a directory).
;
;   Calibrate.Point(id)  -> {x, y, color}   DESIGN coords (2560x1440; the
;                           capture stores Screen.Inv of the pointer); color = Integer
;                           0xRRGGBB sampled at the click. "" when the id is
;                           missing, malformed, or is a rect step.
;   Calibrate.Rect(id)   -> {x, y, w, h}    normalised (x,y = top-left, w,h>0)
;                           "" when missing / not a rect step.
;   Calibrate.Sig(id)    -> {x, y, w, h, sig}  kind "sig": a rect plus the
;                           Pixel.Signature taken of it at calibration (e.g.
;                           the amount box while it shows "1"). "" when
;                           missing / not a sig step / malformed.
;   CALLERS MUST treat "" as "uncalibrated": skip the action and log it.
;   Coordinates are never invented or defaulted.
;
;   Calibrate.Run(stepIds := "all")  show the wizard; stepIds = "all", an
;                           Array of ids or a comma list. Re-record a single
;                           step with Run("inv_open"). Blocks (pumping GUI
;                           events) until finished/cancelled. -> count recorded.
;                           Each recorded step is saved immediately, so Cancel
;                           keeps earlier results. Unknown id -> ValueError
;                           before any UI is shown.
;   Calibrate.Steps()    -> Array of Map {id, kind "point"|"rect"|"sig", prompt}
;   Calibrate.Use(path := "", cfg := "")  choose the store file (default
;                           <repo>\data\calibration.json) and the Config used
;                           for the potion list; reloads from disk.
;
; Fisher buy steps: one per potion in the config key  [Craft] potions  (comma
; list of full in-game names, default "Lucky Potion"; blank ->
; default). Every entry must match a name in data\potions.json (the single
; source of potion identity; match is case/space-insensitive and the
; canonical spelling from potions.json is used). Entries not found there are
; skipped and reported through Calibrate.Logger (callable taking one string,
; default none) and Calibrate.Skipped(), when Use starts. Step id =
; Calibrate.PotionPrefix ("fisher_item_") + lower-cased name with every run of
; non-alphanumerics turned into "_"  ("Lucky Potion" -> fisher_item_lucky_potion;
; see Calibrate.PotionId): the potion's TILE in the Fisher shop (picks it).
; The Buy button is the same for every potion: one step, fisher_buy_button.
; Callers look the id up with Calibrate.PotionId(name).
;
; Capture (NOTHING IS CLICKED): the user HOVERS the target and presses the
; capture key (default F4; override with [Calibrate] captureKey). Rect steps
; and sig steps take two presses at opposite corners; on the second press of
; a sig step the pointer is moved briefly below the rect (so it is not in
; the picture), the rect is grabbed (Calibrate.SigFn, default
; Pixel.Signature) and the pointer moved back. Calibrate.SigProblem judges
; the grab (inv_amount_empty: any; inv_amount_one: bright content, same
; rect as the empty one and some cell more than 2 x sigTol away from it);
; a refused grab asks again. Esc
; cancels the wizard. The keys are
; polled with GetKeyState inside Run's own loop: no Hotkey / hook is ever
; installed, so nothing can be left behind. Pointer position and pixel color
; are sampled in the same pass that sees the key press. Presses while the
; pointer is over the wizard window are ignored. Hover so the target is in
; its normal, non-highlighted state if possible (the color sampled is
; whatever is under the pointer).
; ---------------------------------------------------------------------------

class Calibrate {
    static DefaultPotions := "Lucky Potion"
    ; F4: F9 opens Roblox's developer console (it closed the game window
    ; being calibrated), F7 is the route recorder, F6 / F8 are left for Medal.
    static DefaultCaptureKey := "F4"
    static Logger := ""
    static _skipped := []
    ; (rect {x,y,w,h}) -> signature string. Tests swap it.
    static SigFn := (r) => Calibrate._LiveSig(r)

    static _path := ""
    static _cfg := ""
    static _store := Map()
    static _loaded := false
    static _status := "missing"
    static _running := false

    ; ---- public: store -----------------------------------------------------

    static Use(path := "", cfg := "") {
        Calibrate._path := (path != "") ? path : Calibrate._DefaultPath()
        Calibrate._cfg := cfg
        Calibrate._Load()
        Calibrate._LogSkips()
    }

    static Point(id) {
        Calibrate._Ensure()
        e := Calibrate._store.Has(id) ? Calibrate._store[id] : ""
        if (!IsObject(e) || e.Has("w"))
            return ""
        return {x: e["x"], y: e["y"], color: e["color"]}
    }

    static Rect(id) {
        Calibrate._Ensure()
        e := Calibrate._store.Has(id) ? Calibrate._store[id] : ""
        if (!IsObject(e) || !e.Has("w") || e.Has("sig"))
            return ""
        return {x: e["x"], y: e["y"], w: e["w"], h: e["h"]}
    }

    static Sig(id) {
        Calibrate._Ensure()
        e := Calibrate._store.Has(id) ? Calibrate._store[id] : ""
        if (!IsObject(e) || !e.Has("sig"))
            return ""
        return {x: e["x"], y: e["y"], w: e["w"], h: e["h"], sig: e["sig"]}
    }

    ; Two corners in any order + a well-formed signature (Pixel.SigParse),
    ; else ValueError (nothing stored).
    static SetSig(id, x1, y1, x2, y2, sig) {
        Calibrate._Ensure()
        x1 := Integer(x1), y1 := Integer(y1), x2 := Integer(x2), y2 := Integer(y2)
        w := Abs(x2 - x1), h := Abs(y2 - y1)
        if (w < 1 || h < 1)
            throw ValueError("Calibrate: rectangle needs non-zero width and height")
        if !IsObject(Pixel.SigParse(sig))
            throw ValueError("Calibrate: bad signature")
        Calibrate._store[id] := Map("x", Min(x1, x2), "y", Min(y1, y2), "w", w, "h", h, "sig", sig)
        Calibrate._Save()
    }

    ; Signature tolerance used to judge "clearly differs" (cfg Potions.sigTol,
    ; default 2; the same value the potions task compares with).
    static SigTol() {
        t := 2
        if IsObject(Calibrate._cfg)
            try t := Calibrate._cfg.Get("Potions.sigTol", 2)
        return (IsInteger(t) && t >= 0 && t <= 9) ? Integer(t) : 2
    }

    ; "" when sig may be stored for step id, else the reason (shown in the
    ; wizard). inv_amount_empty: well-formed. inv_amount_one: has bright
    ; content, the empty signature is recorded with the same rect, and some
    ; cell differs from it by more than 2 x SigTol(). Other sig steps:
    ; well-formed with bright content.
    static EmptyMaxInk := 6     ; default cap on the empty box's ink (sum of cells)
    static InkGap := 4          ; default: "1" must add at least this much ink

    ; Ink rule for the amount box pair (catches "empty" recorded while the
    ; box showed 1, and "1" recorded on an empty box): ink(empty) <=
    ; Potions.sigEmptyMaxInk (6) and ink(one) - ink(empty) >= Potions.sigInkGap
    ; (4). one = "" checks the empty cap only. -> "" or the problem.
    static AmountInkProblem(emptySig, oneSig := "", cfg := "") {
        cap := Calibrate.EmptyMaxInk, gap := Calibrate.InkGap
        c := IsObject(cfg) ? cfg : Calibrate._cfg
        if IsObject(c) {
            try v := c.Get("Potions.sigEmptyMaxInk", cap), cap := (IsInteger(v) && v >= 0) ? Integer(v) : cap
            try v := c.Get("Potions.sigInkGap", gap), gap := (IsInteger(v) && v >= 1) ? Integer(v) : gap
        }
        ie := Pixel.SigInk(emptySig)
        if (ie < 0)
            return "empty signature unreadable"
        if (ie > cap)
            return "the empty box has too much bright content (" ie " > " cap "): was a number still in it?"
        if (oneSig = "")
            return ""
        io := Pixel.SigInk(oneSig)
        if (io < 0 || io - ie < gap)
            return "the '1' adds too little bright content over the empty box (" (io < 0 ? "?" : io - ie) " < " gap "): did the box show 1?"
        return ""
    }

    static SigProblem(id, sig, r) {
        if !IsObject(Pixel.SigParse(sig))
            return "Could not read that box. Hover the two corners again."
        if (id = "inv_amount_empty") {
            ink := Calibrate.AmountInkProblem(sig)
            return (ink = "") ? "" : "Not recorded: " ink " Delete the number from the box, then hover the two corners again."
        }
        if !Pixel.SigValid(sig)
            return "No bright digit seen in that box. Make it show exactly 1, then hover the two corners again."
        if (id = "inv_amount_one") {
            e := Calibrate.Sig("inv_amount_empty")
            if !IsObject(e)
                return "Record the EMPTY amount box (step inv_amount_empty) first."
            if (e.x != r.x || e.y != r.y || e.w != r.w || e.h != r.h)
                return "Use the same two corners as for the empty box (it was " e.x "," e.y " " e.w "x" e.h ")."
            if (Pixel.SigMaxDiff(sig, e.sig) <= 2 * Calibrate.SigTol())
                return "The '1' looks too much like the empty box. Make sure it shows exactly 1 and hover the corners tight around the inside of the box."
            ink := Calibrate.AmountInkProblem(e.sig, sig)
            if (ink != "")
                return "Not recorded: " ink " Re-record the empty box if it was not empty."
        }
        return ""
    }

    ; Live grab for a sig step: pointer moved below the rect, grabbed, moved
    ; back (hover only, nothing clicked).
    static _LiveSig(r) {
        CoordMode("Mouse", "Screen")
        MouseGetPos(&mx, &my)
        try {
            p := Screen.Pt(r.x + r.w // 2, r.y + r.h + 60)
            MouseMove(p.x, p.y, 0)
            Sleep(150)
            return Pixel.Signature(r.x, r.y, r.w, r.h)
        } finally {
            MouseMove(mx, my, 0)
        }
    }

    ; Screen px of the pointer -> the DESIGN-space point stored (2560x1440):
    ; a point recorded at 1920x1080 is stored / 0.75, so the file is the same
    ; at every size and version-1 files (taken at 2560x1440) stay valid.
    static ToDesign(sx, sy) => Screen.Inv(sx, sy)

    ; ok | missing | bad  (state of the file at last load)
    static LoadStatus() {
        Calibrate._Ensure()
        return Calibrate._status
    }

    ; Store a point and save. The value stays in memory even if saving throws.
    static SetPoint(id, x, y, color) {
        Calibrate._Ensure()
        Calibrate._store[id] := Map("x", Integer(x), "y", Integer(y), "color", Pixel.ToRgb(color))
        Calibrate._Save()
    }

    ; Two corners in any order. Zero width or height -> ValueError (nothing stored).
    static SetRect(id, x1, y1, x2, y2) {
        Calibrate._Ensure()
        x1 := Integer(x1), y1 := Integer(y1), x2 := Integer(x2), y2 := Integer(y2)
        w := Abs(x2 - x1), h := Abs(y2 - y1)
        if (w < 1 || h < 1)
            throw ValueError("Calibrate: rectangle needs non-zero width and height")
        Calibrate._store[id] := Map("x", Min(x1, x2), "y", Min(y1, y2), "w", w, "h", h)
        Calibrate._Save()
    }

    ; ---- public: step list -------------------------------------------------

    static PotionPrefix := "fisher_item_"

    static PotionId(name) {
        s := StrLower(Trim(String(name)))
        s := Trim(RegExReplace(s, "[^a-z0-9]+", "_"), "_")
        return Calibrate.PotionPrefix s
    }

    ; Potion names from [Craft] potions, validated against the Fisher shop
    ; (GameLists.Shop) when a Config is bound: trimmed, de-duplicated, order
    ; kept, canonical spelling. Names the shop does not sell are left out
    ; (Skipped()).
    static Potions() {
        csv := Calibrate.DefaultPotions
        known := ""
        if IsObject(Calibrate._cfg) {
            csv := Calibrate._cfg.Get("Craft.potions", csv)
            known := true
        }
        if (Trim(csv) = "")
            csv := Calibrate.DefaultPotions
        out := []
        skipped := []
        seen := Map()
        for part in StrSplit(csv, ",") {
            n := Trim(RegExReplace(part, "\s+", " "))
            k := StrLower(n)
            if (n = "" || seen.Has(k))
                continue
            seen[k] := true
            if known {
                s := GameLists.ShopName(n)
                if (s = "") {
                    skipped.Push(n)
                    continue
                }
                n := s
            }
            out.Push(n)
        }
        Calibrate._skipped := skipped
        return out
    }

    ; Names dropped from [Craft] potions as of the current config.
    static Skipped() {
        Calibrate.Potions()
        return Calibrate._skipped
    }

    static _LogSkips() {
        if !IsObject(Calibrate.Logger)
            return
        for n in Calibrate.Skipped()
            Calibrate.Logger.Call("Calibrate: ignoring '" n "' in [Craft] potions (not in potions.json)")
    }

    ; Capture key name (GetKeyState syntax).
    static CaptureKey() {
        k := Calibrate.DefaultCaptureKey
        if IsObject(Calibrate._cfg)
            k := Trim(Calibrate._cfg.Get("Calibrate.captureKey", k))
        ; an old settings.ini may still say F9 (Roblox's developer console)
        return (k = "" || StrUpper(k) = "F9") ? Calibrate.DefaultCaptureKey : k
    }

    static Steps() {
        out := []
        add := (id, kind, prompt) => out.Push(Map("id", id, "kind", kind, "prompt", prompt))
        add("notify_rect", "rect", "Wait for an in-game notification (let auto craft make something, or press E at an EMPTY quest board). Hover the TOP-LEFT then the BOTTOM-RIGHT corner of the area where notification text shows (make it a bit bigger than one notification).")
        add("fisher_open_shop", "point", "Talk to Captain Flarg so his two buttons show. Hover the Open Shop button (not Sell Fish).")
        for name in Calibrate.Potions()
            add(Calibrate.PotionId(name), "point", "Fisher shop open (Open Shop). Hover the " name " tile in the shop list (the tile that picks it).")
        add("fisher_buy_button", "point", "Fisher shop open, a potion picked. Hover the Buy button (the same spot for every potion).")
        add("fisher_picked_name", "rect", "Fisher shop open, a potion picked. Hover the TOP-LEFT then the BOTTOM-RIGHT corner of the picked item's big NAME in the left panel (make it wide enough for the longest name, e.g. 'Fortune Potion III'). The macro reads it so it never buys the wrong item.")
        add("fisher_qty", "point", "Stand at the Fisher shop with a potion selected. Hover the quantity box.")
        add("fisher_confirm", "point", "Stand at the Fisher shop. Hover the final Confirm / Purchase button.")
        add("fisher_purchase_close", "point", "Fisher shop, the purchase window still open after buying. Hover the button that closes the purchase window (its X).")
        add("fisher_shop_close", "point", "Fisher shop open (purchase window closed). Hover the X that closes the whole shop.")
        add("fisher_leave", "point", "Talk to Captain Flarg so his three buttons show (Open Shop, Sell Fish, Leave). Hover the Leave button.")
        add("cauldron_gui", "rect", "Open Stella's cauldron (Stella's Workshop). Hover the TOP-LEFT then the BOTTOM-RIGHT corner of its title text 'Stella's Workshop'.")
        add("cauldron_search", "point", "Stella's cauldron open. Hover the recipe search box.")
        add("cauldron_result", "rect", "Type a recipe name in the search box. Hover the TOP-LEFT then the BOTTOM-RIGHT corner of the FIRST result card (its name and the line under it).")
        add("cauldron_result_2", "rect", "Type Godly Potion in the search box (three results). Hover the TOP-LEFT then the BOTTOM-RIGHT corner of the SECOND result card, the same parts as the first. Only needed for the Godly Potions.")
        add("cauldron_open_recipe", "point", "Recipe selected. Hover the Open Recipe button.")
        add("cauldron_add_all", "point", "Recipe open. Hover the Add All button.")
        add("cauldron_close", "point", "Hover the button that closes the cauldron window.")
        add("stella_dialog", "rect", "Walk into Stella so her dialog shows. Hover the TOP-LEFT then the BOTTOM-RIGHT corner of her NAME ('Stella') at the top of the dialog.")
        add("inv_open", "point", "Stand anywhere with the inventory closed. Hover the inventory button.")
        add("inv_items_tab", "point", "Open the inventory (it opens on the Gears tab). Hover the Items tab button (do not press it).")
        add("inv_search", "point", "Inventory open on the Items tab. Hover the item search box.")
        add("inv_tile1_rect", "rect", "Search 'Potion' so a full row of results shows. Hover the TOP-LEFT then the BOTTOM-RIGHT corner of the FIRST result tile's NAME text (both lines of it).")
        add("inv_tile2_rect", "rect", "Same results. Hover the TOP-LEFT then the BOTTOM-RIGHT corner of the SECOND result tile's NAME text, the same way as the first (this sets the tile spacing).")
        add("inv_count_rect", "rect", "Same results. Hover the TOP-LEFT then the BOTTOM-RIGHT corner of the FIRST result tile's count text (e.g. x12).")
        add("inv_use", "point", "Select a potion tile yourself. Hover the Use button (do not press it).")
        add("inv_desc_rect", "rect", "Potion selected. Hover the TOP-LEFT then the BOTTOM-RIGHT corner of the description text under Use (the first two lines, e.g. 'Gives you ... of [Lucky]').")
        add("inv_amount_box", "rect", "Potion selected. Hover the TOP-LEFT then the BOTTOM-RIGHT corner of the INSIDE of the amount box next to Use (where the number goes).")
        add("quest_board_rect", "rect", "Stand at the quest board with it open. Hover the TOP-LEFT then the BOTTOM-RIGHT corner of the quest text area.")
        add("quest_accept", "point", "Quest board open. Hover the Accept button (Claim Rewards shows in the same spot).")
        add("quest_dismiss", "point", "Quest board open. Hover the Dismiss / Abandon button.")
        add("quest_close", "point", "Quest board open. Hover the button that exits / closes the board.")
        add("quest_next", "point", "Quest board open. Hover the > arrow to the right of the board (next quest).")
        add("aura_open", "point", "Stand anywhere with every menu closed. Hover the Aura Storage button (the one that opens your auras).")
        add("aura_search", "point", "Aura Storage open. Hover its search box.")
        add("aura_tile_rect", "rect", "Aura Storage open, type Sailor in the search box. Hover the TOP-LEFT then the BOTTOM-RIGHT corner of the FIRST result's NAME text.")
        add("aura_equip", "point", "Aura Storage open, select the Sailor tile yourself. Hover the Equip button (do NOT press it; never a Delete button). The macro reads Equip / Unequip on it before it ever presses it.")
        add("aura_close", "point", "Aura Storage open. Hover the X that closes it.")
        add("buff_expand", "point", "Hover the arrow / button that expands your buff list so every buff shows (the same button collapses it).")
        add("obby_blessing", "point", "Touch the obby's star so the Basic Blessing shows, expand the buff list, then hover the Basic Blessing icon (the macro checks its colour after each obby run).")
        add("selector_list_rect", "rect", "Use the Biome Selector so its list of Drives shows. Hover the TOP-LEFT corner of the first Drive (Radiant Star), then the BOTTOM-RIGHT corner of the last one you can see. The macro reads the list, so the slow bobbing does not matter.")
        add("selector_confirm", "point", "Biome Selector open, a Drive selected. Hover the button that confirms / uses it (do not press it).")
        add("chat_rect", "rect", "Open the chat. Hover the TOP-LEFT then the BOTTOM-RIGHT corner of the chat message area.")
        return out
    }

    ; "all" | Array of ids | comma list -> Array of step Maps (list order kept
    ; for "all", requested order otherwise). Unknown id -> ValueError.
    static ResolveIds(stepIds := "all") {
        steps := Calibrate.Steps()
        if (!IsObject(stepIds) && StrLower(Trim(String(stepIds))) = "all")
            return steps
        want := []
        if IsObject(stepIds) {
            for id in stepIds
                want.Push(Trim(String(id)))
        } else {
            for id in StrSplit(String(stepIds), ",")
                want.Push(Trim(id))
        }
        byId := Map()
        for s in steps
            byId[s["id"]] := s
        out := []
        for id in want {
            if (id = "")
                continue
            if !byId.Has(id)
                throw ValueError("Calibrate: unknown step id '" id "'")
            out.Push(byId[id])
        }
        return out
    }

    ; ---- public: wizard ----------------------------------------------------

    static NewSession(steps) {
        return Calibrate._Session(steps)
    }

    static Run(stepIds := "all") {
        steps := Calibrate.ResolveIds(stepIds)
        if (steps.Length = 0 || Calibrate._running)
            return 0
        Calibrate._running := true
        sess := Calibrate._Session(steps)
        g := ""
        try {
            try Roblox.ClientOk()          ; Screen maps to Roblox's client now (macro may be stopped)
            CoordMode("Mouse", "Screen")
            g := Calibrate._BuildGui(sess)
            lastRev := -1
            key := Calibrate.CaptureKey()
            ; A key already held when we start is not a capture.
            prev := GetKeyState(key, "P")
            prevEsc := GetKeyState("Escape", "P")
            while !sess.IsDone() {
                if (sess.Revision() != lastRev) {
                    lastRev := sess.Revision()
                    g.Refresh()
                }
                down := GetKeyState(key, "P")
                if (down && !prev) {
                    MouseGetPos(&mx, &my, &win)
                    if (win = g.Hwnd())
                        sess.Notice("Move the pointer onto the target (off this window), then press " key ".")
                    else {
                        d := Calibrate.ToDesign(mx, my)        ; stored in design space
                        sess.Capture(d.x, d.y)
                    }
                }
                prev := down
                esc := GetKeyState("Escape", "P")
                if (esc && !prevEsc)
                    sess.Cancel()
                prevEsc := esc
                Sleep(15)
            }
        } finally {
            if IsObject(g)
                g.Close()
            Calibrate._running := false
        }
        return sess.Count()
    }

    ; ---- wizard window -----------------------------------------------------

    static _BuildGui(sess) {
        bg := "0D1117", panel := "0B2A5B", text := "F7F1E8", accent := "F2A93B"
        wnd := Gui("+AlwaysOnTop +ToolWindow -MinimizeBox -MaximizeBox", Brand.Name " Calibration")
        wnd.MarginX := 14
        wnd.MarginY := 12
        wnd.BackColor := bg
        wnd.SetFont("s9 c" accent, "Segoe UI")
        head := wnd.Add("Text", "w460", "")
        wnd.SetFont("s11 c" text)
        body := wnd.Add("Text", "w460 h120 Background" panel, "")
        wnd.SetFont("s9 c" accent)
        note := wnd.Add("Text", "w460 h34", "")
        wnd.SetFont("s9 c" text)
        bSkip := wnd.Add("Button", "w100 Section", "Skip")
        bRedo := wnd.Add("Button", "x+10 ys w100", "Redo")
        bCancel := wnd.Add("Button", "x+10 ys w100", "Cancel")
        bSkip.OnEvent("Click", (*) => sess.Skip())
        bRedo.OnEvent("Click", (*) => sess.Redo())
        bCancel.OnEvent("Click", (*) => sess.Cancel())
        wnd.OnEvent("Close", (*) => sess.Cancel())
        wnd.Show("x20 y20 AutoSize NoActivate")
        return Calibrate._Window(wnd, sess, head, body, note)
    }

    class _Window {
        __New(wnd, sess, head, body, note) {
            this._gui := wnd
            this._sess := sess
            this._head := head
            this._body := body
            this._note := note
        }
        Hwnd() => this._gui.Hwnd
        Refresh() {
            s := this._sess
            this._head.Text := s.HeadText()
            this._body.Text := s.PromptText()
            this._note.Text := s.LastError()
        }
        Close() {
            try this._gui.Destroy()
        }
    }

    ; ---- session (wizard logic, no UI) -------------------------------------

    class _Session {
        __New(steps) {
            this._steps := steps
            this._idx := 1
            this._corner := ""
            this._count := 0
            this._cancelled := false
            this._err := ""
            this._rev := 0
        }

        Current() => this.IsDone() ? "" : this._steps[this._idx]
        IsDone() => this._cancelled || this._idx > this._steps.Length
        WasCancelled() => this._cancelled
        Count() => this._count
        LastError() => this._err
        Revision() => this._rev

        HeadText() {
            if this.IsDone()
                return "Done"
            return "Step " this._idx " of " this._steps.Length "   [" this.Current()["id"] "]"
        }

        PromptText() {
            s := this.Current()
            if !IsObject(s)
                return ""
            t := s["prompt"]
            key := Calibrate.CaptureKey()
            if (s["kind"] = "rect" || s["kind"] = "sig")
                t .= "`n" (IsObject(this._corner) ? "Now hover the BOTTOM-RIGHT corner and press " key "." : "Hover the TOP-LEFT corner and press " key " first.")
            else
                t .= "`nHover it (normal, not highlighted, if possible) and press " key "."
            return t "`nNothing is clicked. Esc cancels."
        }

        ; Show a message in the window without changing state.
        Notice(msg) {
            this._err := msg
            this._rev++
        }

        ; Hover-and-key capture at screen x,y (nothing is clicked).
        Capture(x, y) {
            s := this.Current()
            if !IsObject(s)
                return
            this._err := ""
            try {
                if (s["kind"] = "point") {
                    color := Pixel.Get(x, y)
                    this._Advance()
                    Calibrate.SetPoint(s["id"], x, y, color)
                } else if !IsObject(this._corner) {
                    this._corner := [x, y]
                } else {
                    cx := this._corner[1], cy := this._corner[2]
                    if (Abs(x - cx) < 1 || Abs(y - cy) < 1) {
                        this._err := "Corners must differ in both X and Y. Hover the opposite corner."
                    } else if (s["kind"] = "sig") {
                        r := {x: Min(x, cx), y: Min(y, cy), w: Abs(x - cx), h: Abs(y - cy)}
                        sig := ""
                        try sig := Calibrate.SigFn.Call(r)
                        why := Calibrate.SigProblem(s["id"], sig, r)
                        if (why != "") {
                            this._corner := ""
                            this._err := why
                        } else {
                            this._Advance()
                            Calibrate.SetSig(s["id"], cx, cy, x, y, sig)
                        }
                    } else {
                        this._Advance()
                        Calibrate.SetRect(s["id"], cx, cy, x, y)
                    }
                }
            } catch Any as e {
                ; Value (if computed) stays in memory; surface the problem in the window.
                this._err := "Not saved to disk: " e.Message
            }
            this._rev++
        }

        Skip() {
            if this.IsDone()
                return
            this._err := ""
            this._Advance(false)
            this._rev++
        }

        ; Pending first corner -> drop it. Otherwise go back one step.
        Redo() {
            if this.IsDone()
                return
            this._err := ""
            if IsObject(this._corner)
                this._corner := ""
            else if (this._idx > 1)
                this._idx--
            this._rev++
        }

        Cancel() {
            this._cancelled := true
            this._rev++
        }

        _Advance(recorded := true) {
            this._corner := ""
            this._idx++
            if recorded
                this._count++
        }
    }

    ; ---- load / save -------------------------------------------------------

    static _DefaultPath() {
        return RegExReplace(A_LineFile, "\\[^\\]*\\[^\\]*$") "\data\calibration.json"
    }

    static _Ensure() {
        if !Calibrate._loaded
            Calibrate._Load()
    }

    static _Load() {
        if (Calibrate._path = "")
            Calibrate._path := Calibrate._DefaultPath()
        Calibrate._loaded := true
        Calibrate._store := Map()
        path := Calibrate._path
        ; no calibration yet (no file, or the shipped one with no steps): start
        ; from the preset made at THIS system's display (resolution + Windows
        ; scale), if one ships; otherwise stay empty (the Calibrate page says
        ; so). Read only: the user's file is not written until a step is
        ; recorded (then it holds the preset + the new step)
        src := path
        Calibrate.AutoNote := ""
        if Calibrate._NoSteps(path) {
            pp := Calibrate.PresetPath(path)
            if (pp != "" && FileExist(pp))
                src := pp
        } else {
            alt := Calibrate._PresetSwap(path)
            if (alt != "")
                src := alt
        }
        if !FileExist(src) {
            Calibrate._status := "missing"
            return
        }
        root := ""
        try root := Json.Parse(FileRead(src, "UTF-8"))
        if !(root is Map && root.Has("steps") && root["steps"] is Map) {
            Calibrate._status := "bad"
            return
        }
        Calibrate._status := "ok"
        for id, e in root["steps"] {
            c := Calibrate._ParseEntry(e)
            if IsObject(c)
                Calibrate._store[String(id)] := c
        }
    }

    ; ---- presets: data\presets\calibration_<W>x<H>_<scale>.json -------------
    ; A preset is a calibration file recorded fullscreen at W x H with Windows
    ; display scale <scale> %. Only a preset made at the user's own display is
    ; applied automatically (first run); the Calibrate page lists them all.

    static PresetPrefix := "calibration_"

    ; (cal path) -> the presets folder next to it
    static PresetDir(path := "") {
        SplitPath((path != "") ? path : (Calibrate._path != "" ? Calibrate._path : Calibrate._DefaultPath()), , &dir)
        return dir "\presets"
    }

    ; "calibration_2560x1440_100.json" -> {w, h, scale} or "" (any other name)
    static ParsePresetName(file) {
        SplitPath(file, &name)
        if !RegExMatch(name, "i)^calibration_(\d{3,5})x(\d{3,5})_(\d{2,3})\.json$", &m)
            return ""
        return {w: Integer(m[1]), h: Integer(m[2]), scale: Integer(m[3])}
    }

    static PresetLabel(p) => p.w "x" p.h " " Chr(0xB7) " " p.scale "%"

    ; -> Array of {w, h, scale, label, path}, biggest resolution first, then
    ; by scale. Files that do not follow the name pattern are left out.
    static Presets(path := "") {
        list := []
        try {
            Loop Files Calibrate.PresetDir(path) "\calibration_*.json" {
                p := Calibrate.ParsePresetName(A_LoopFileName)
                if !IsObject(p)
                    continue
                p.label := Calibrate.PresetLabel(p), p.path := A_LoopFileFullPath
                i := 1
                while (i <= list.Length && Calibrate._PresetBefore(list[i], p))
                    i++
                list.InsertAt(i, p)
            }
        }
        return list
    }

    static _PresetBefore(a, b) => (a.w * a.h != b.w * b.h) ? (a.w * a.h > b.w * b.h) : (a.w != b.w) ? (a.w > b.w) : (a.scale <= b.scale)

    ; the preset made at display sys {w, h, scale}, or ""
    static MatchPreset(list, sys) {
        if !IsObject(sys)
            return ""
        for p in list
            if (p.w = sys.w && p.h = sys.h && p.scale = sys.scale)
                return p
        return ""
    }

    ; () -> {w, h, scale}: this system's display. Tests swap it.
    static SystemFn := () => Calibrate.SystemDisplay()

    ; The monitor Roblox is on (the primary one when Roblox is not open):
    ; its resolution in physical px and its Windows display scale in %.
    static SystemDisplay() {
        m := ""
        try {
            hwnd := Roblox.Hwnd()
            if hwnd
                m := Roblox._Monitor(hwnd)
        }
        if !IsObject(m)
            m := {x: 0, y: 0, w: A_ScreenWidth, h: A_ScreenHeight}
        sc := Screen.ScaleAt(m.x + 1, m.y + 1)
        if Roblox.AllowWindowed                 ; testing: the window's client size is "the display"
            try {
                WinGetClientPos(, , &cw, &ch, "ahk_id " Roblox.Hwnd())
                if (cw > 0 && ch > 0)
                    m := {x: m.x, y: m.y, w: cw, h: ch}
            }
        return {w: m.w, h: m.h, scale: sc}
    }

    ; What _Load did on its own (App logs it), "" when nothing.
    static AutoNote := ""

    ; Auto screen setup (idea 2, 2026-11-13): the calibration is exactly one
    ; of the shipped presets (never hand-edited) but the screen now matches
    ; ANOTHER preset (the player changed resolution): -> that preset's path
    ; (used read-only, like the first run; the file on disk is untouched).
    ; A hand-made or edited calibration -> "" (always kept).
    static _PresetSwap(path) {
        pp := Calibrate.PresetPath(path)
        if (pp = "" || !FileExist(pp))
            return ""
        mine := Calibrate._StepsKey(path)
        if (mine = "" || mine == Calibrate._StepsKey(pp))
            return ""
        for p in Calibrate.Presets(path) {
            if (p.path = pp)
                continue
            if (Calibrate._StepsKey(p.path) == mine) {
                sys := ""
                try sys := Calibrate.SystemFn.Call()
                Calibrate.AutoNote := "your calibration is the " p.label " preset but your screen is " (IsObject(sys) ? Calibrate.PresetLabel(sys) : "another size")
                    . ": using the matching preset (your file is unchanged; Calibrate > Apply preset makes it permanent)"
                return pp
            }
        }
        return ""
    }

    ; a calibration file's steps as one comparable string ("" = none / broken)
    static _StepsKey(file) {
        try {
            root := Json.Parse(FileRead(file, "UTF-8"))
            if (root is Map && root.Has("steps") && root["steps"] is Map && root["steps"].Count)
                return Json.Stringify(root["steps"])
        }
        return ""
    }

    ; Path of the preset matching this system's display, or "".
    static PresetPath(path := "") {
        p := ""
        try p := Calibrate.MatchPreset(Calibrate.Presets(path), Calibrate.SystemFn.Call())
        return IsObject(p) ? p.path : ""
    }

    ; No calibration file, or one that parses with an empty "steps" map.
    ; A broken file is NOT replaced (the user may want to fix it).
    static _NoSteps(path) {
        if !FileExist(path)
            return true
        root := ""
        try root := Json.Parse(FileRead(path, "UTF-8"))
        return (root is Map && root.Has("steps") && root["steps"] is Map && root["steps"].Count = 0)
    }

    ; Dashboard "Apply preset": the current calibration is copied to
    ; <file>.bak (when there is one), the preset copied over it and reloaded.
    ; -> "" on success, else what went wrong (nothing changed).
    static ApplyPreset(presetPath) {
        Calibrate._Ensure()
        root := ""
        try root := Json.Parse(FileRead(presetPath, "UTF-8"))
        if !(root is Map && root.Has("steps") && root["steps"] is Map)
            return "the preset file is missing or broken"
        path := Calibrate._path
        try {
            if FileExist(path)
                FileCopy(path, path ".bak", 1)
            FileCopy(presetPath, path, 1)
        } catch Any as e
            return "could not copy the preset (" e.Message ")"
        Calibrate._Load()
        return ""
    }

    ; -> normalised Map or "" if malformed.
    static _ParseEntry(e) {
        if !(e is Map && e.Has("x") && e.Has("y") && e["x"] is Integer && e["y"] is Integer)
            return ""
        if e.Has("w") {
            if !(e.Has("h") && e["w"] is Integer && e["h"] is Integer && e["w"] > 0 && e["h"] > 0)
                return ""
            if e.Has("sig") {
                if !IsObject(Pixel.SigParse(e["sig"]))
                    return ""
                return Map("x", e["x"], "y", e["y"], "w", e["w"], "h", e["h"], "sig", e["sig"])
            }
            return Map("x", e["x"], "y", e["y"], "w", e["w"], "h", e["h"])
        }
        if !e.Has("color")
            return ""
        try color := Pixel.ToRgb(e["color"])
        catch
            return ""
        return Map("x", e["x"], "y", e["y"], "color", color)
    }

    static _Save() {
        steps := Map()
        for id, e in Calibrate._store {
            if e.Has("sig")
                steps[id] := Map("x", e["x"], "y", e["y"], "w", e["w"], "h", e["h"], "sig", e["sig"])
            else if e.Has("w")
                steps[id] := Map("x", e["x"], "y", e["y"], "w", e["w"], "h", e["h"])
            else
                steps[id] := Map("x", e["x"], "y", e["y"], "color", Format("0x{:06X}", e["color"]))
        }
        list := []
        for s in Calibrate.Steps()
            list.Push(Map("id", s["id"], "kind", s["kind"], "prompt", s["prompt"]))
        ; version 2: coordinates are design space (2560x1440) at any client size
        root := Map("version", 2, "space", "design 2560x1440", "steps", steps, "stepList", list)
        path := Calibrate._path
        ; A corrupt file is kept as <path>.bad instead of being lost silently.
        if (Calibrate._status = "bad" && FileExist(path) && !InStr(FileExist(path), "D"))
            try FileCopy(path, path ".bad", 1)
        Calibrate._AtomicWrite(path, Json.Stringify(root) "`n")
        Calibrate._status := "ok"
    }

    static _AtomicWrite(path, text) {
        SplitPath(path, , &dir)
        if (dir != "" && !DirExist(dir))
            DirCreate(dir)
        tmp := path ".tmp"
        f := ""
        try {
            ; FileMove onto an existing directory silently moves the file INTO
            ; it and "succeeds": refuse instead.
            if InStr(FileExist(path), "D")
                throw OSError("Calibrate: calibration path is a directory")
            f := FileOpen(tmp, "w", "UTF-8-RAW")
            f.Write(text)
            f.Close()
            f := ""
            FileMove(tmp, path, 1)
            if (InStr(FileExist(path), "D") || FileRead(path, "UTF-8-RAW") !== text)
                throw OSError("Calibrate: calibration file read-back mismatch")
        } catch Any as err {
            f := ""
            try FileDelete(tmp)
            throw err
        }
    }
}
