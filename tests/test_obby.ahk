#Requires AutoHotkey v2.0
; Tests for lib\tasks\Obby.ahk. Offline: fake IO, calibration, OCR, pixel,
; webhook and a fake aura storage that replays the clicks / typing in the
; IO log. Helpers (QmIO, QmCal, QmWh, QmCfg) come from test_questmatch.ahk.
#Include ..\lib\tasks\Obby.ahk

; ---- helpers (names must not start with Test_) -----------------------------

QmObbyRoutes() {
    return Map("routes", Map("obby", [["w", "down", 100], ["w", "up", 0]]))
}

; The aura storage, rebuilt from the IO log each time it is asked:
;   aura_open 10,10 / search 20,20 / result tile k at 100,100 200x50 plus
;   ObbyTask.TileStep per column / row (tile 1 centre 200,125) / equip
;   300,300 (the selected aura's name panel at ObbyTask.NameBox from it) /
;   close 400,400 / buff_expand 500,500 / blessing 600,600.
; Like the game: the search keeps its old text (leftover), Backspace takes
; one letter, Ctrl+A does nothing; results list every owned aura whose name
; contains the search, in `owned` order.
class ObStore {
    __New(io, initial, owned) {
        this.io := io
        this.initial := initial
        this.owned := owned
        this.known := true
        this.blessing := true        ; the blessing shows (when the list is expanded)
        this.button := ""            ; forced button text ("" = Equip / Unequip)
        this.leftover := ""          ; the search text from before
        this.logName := "-"          ; "-" = the log follows the game; else what the log still says
        this.special := []           ; auras under the Special tab (the rest: Regular)
        this.logo := []              ; auras whose name panel is a logo (OCR reads nothing)
        this.drop := 0               ; Equip / Unequip clicks the game drops (the first n)
        this.coll := false           ; the Aura Collections screen is up (covers the storage)
        this.collMiss := 0           ; reads of it that miss it (the chat overlaps the title)
        this.prompt := false         ; a Roblox purchase prompt is up (Esc closes it)
        this.promptStuck := false    ; ... and Esc does not close it
        this.closed := false         ; the storage never opens (its button does nothing)
        this.buffShown := true       ; the buff list button shows its calibrated colour (both states)
        this.promptOnExpand := false ; a click on buff_expand opens a Roblox purchase prompt
        this.openAtStart := false    ; the storage is open already (left open)
        this.closeDrop := 0          ; clicks on its X the game drops (the first n)
        this.titleMiss := 0          ; reads of its open title that miss (a banner over it)
        this.daily := false          ; the Daily Rewards popup is up
        this.dailyDrop := 0          ; clicks on its X the game drops (the first n)
        this.dailyOnType := false    ; it comes up at the first typed search (mid-swap)
        this.quest := false          ; the Quest Board page is up
        this.questDrop := 0          ; clicks on its Exit the game drops (the first n)
        this.questExit := "Exit"     ; what its Exit box reads
        this._px := Map()            ; "w,h,lit" -> pixel Array (Rect)
        this.names := Map()          ; aura -> what its name panel reads (a misread; default its name)
        this.lag := 0                ; name panel reads after each click that still show the aura selected before
        this._lagAt := -1, this._lagN := 0
    }
    Results(search, tab := "regular") {
        out := []
        if (search = "")
            return out
        for a in this.owned {
            sp := false
            for x in this.special
                sp := sp || (x == a)
            if ((tab = "special") = sp && InStr(GameLists.Fold(a), GameLists.Fold(search)))
                out.Push(a)
        }
        return out
    }
    ; result tile number at a tile rect's top left (0 = not a tile)
    TileAt(x, y) {
        st := ObbyTask.TileStep
        if (x < 100 || y < 100 || Mod(x - 100, st.dx) || Mod(y - 100, st.dy))
            return 0
        col := (x - 100) // st.dx
        return (col < ObbyTask.TileCols) ? ((y - 100) // st.dy) * ObbyTask.TileCols + col + 1 : 0
    }
    State() {
        search := this.leftover, selected := "", eq := this.initial, open := this.openAtStart, last := "", expanded := false, tab := "regular", dropped := 0, closes := 0
        coll := this.coll, prompt := this.prompt
        daily := this.daily, dailyCloses := 0, typed := false
        quest := this.quest, questCloses := 0
        hist := [], before := ""
        for e in this.io.log {
            if (e = "down Esc")
                prompt := prompt && this.promptStuck
            else if (e = "down Backspace")
                search := SubStr(search, 1, StrLen(search) - 1)
            else if (SubStr(e, 1, 5) = "type ") {
                search .= SubStr(e, 6)
                daily := daily || (this.dailyOnType && !typed)
                typed := true
            } else if (SubStr(e, 1, 5) = "move ")
                last := SubStr(e, 6)
            else if (e = "click") {
                xy := StrSplit(last, ",")
                k := (xy.Length = 2) ? this.TileAt(xy[1] - 100, xy[2] - 25) : 0
                if k {
                    r := this.Results(search, tab)
                    before := selected
                    selected := (open && k <= r.Length) ? r[k] : ""
                    ; like live 2026-11-02: an empty slot lets the click
                    ; through into the world (a Donation board's prompt)
                    if (open && k > r.Length)
                        prompt := true
                }
                switch last {
                    ; its sidebar button toggles it; the Collections screen covers the button
                    case "10,10": open := open ? false : (!coll && !this.closed), selected := open ? selected : ""
                    case "525,158": coll := false         ; Input.ResetCoords menuClose
                    case "1890,527":                      ; Input.DailyX
                        if (dailyCloses++ >= this.dailyDrop)
                            daily := false
                    case ObbyTask.QuestExit[1] "," ObbyTask.QuestExit[2]:
                        if (questCloses++ >= this.questDrop)
                            quest := false
                    case "122,-25": tab := "regular"       ; the tabs, from aura_search 20,20
                    case "567,-25": tab := "special"
                    case "300,300":
                        if (open && selected != "" && this.button = "" && dropped++ >= this.drop)
                            eq := (eq == selected) ? "" : selected, hist.Push(eq)
                    case "400,400":
                        if (open && closes++ >= this.closeDrop)
                            open := false, selected := ""
                    case "500,500": expanded := !expanded, prompt := prompt || this.promptOnExpand
                }
            }
        }
        return {search: search, selected: selected, eq: eq, open: open, expanded: expanded, coll: coll, tab: tab, prompt: prompt, daily: daily, quest: quest, hist: hist, before: before}
    }
    ; pixels of a tile rect: an aura's bright name where the results have
    ; one, the dim world behind the panel elsewhere
    Rect(x, y, w, h) {
        s := this.State()
        k := this.TileAt(x, y)
        lit := (s.open && k && k <= this.Results(s.search, s.tab).Length) ? 1 : 0
        key := w "," h "," lit
        if !this._px.Has(key) {
            px := []
            px.Capacity := w * h
            Loop w * h
                px.Push((lit && Mod(A_Index, 7) = 0) ? 0xF0F0F0 : 0x202428)
            this._px[key] := px
        }
        return this._px[key]
    }
    Ocr(x, y, w, h) {
        s := this.State()
        pb := Input.PurchaseBox
        if (x = pb.x && y = pb.y)
            return s.prompt ? "Buy Robux and item`nR$1,000 Donation`nYour payment method will be charged`nBuy $4.99" : ""
        db := Input.DailyBox
        if (x = db.x && y = db.y)
            return s.daily ? "noily Rewords" : ""
        if (this.HasOwnProp("boardPrompt") && x = MinionsTask.PromptBox.x && y = MinionsTask.PromptBox.y)
            return "Quest Board`nSee Q uests"
        if (x = ObbyTask.QuestBox.x && y = ObbyTask.QuestBox.y)
            return s.quest ? "Objects" : ""
        if (x = ObbyTask.QuestExitBox.x && y = ObbyTask.QuestExitBox.y)
            return s.quest ? this.questExit : ""
        sb := ObbyTask.StorageBox
        if (x = 20 + sb.dx && y = 20 + sb.dy)
            return (s.open && !s.prompt && this.titleMiss-- <= 0) ? "Auro Storage" : ""
        pn := ObbyTask.PanelBox
        if (x = 300 + pn.dx && y = 300 + pn.dy)
            return (s.open && !s.prompt) ? "[ Information ]" : ""
        cb := Input.ResetChecks["collection"]
        if (x = cb.x && y = cb.y)
            return (s.coll && this.collMiss-- <= 0) ? "Aura Collections [Exit]" : ""
        n := ObbyTask.NameBox
        if (x = 300 + n.dx && y = 300 + n.dy) {
            if (s.open && s.selected != "")
                for lg in this.logo
                    if (lg == s.selected)
                        return ""
            sel := s.selected
            if this.lag {                            ; the panel still shows the aura selected before
                if (this._lagAt != this.io.log.Length)
                    this._lagAt := this.io.log.Length, this._lagN := 0
                if (++this._lagN <= this.lag)
                    sel := s.before
            }
            if (s.open && sel != "" && this.names.Has(sel))
                return this.names[sel]
            return (s.open && sel != "") ? sel "`n1 in 3,000" : ""
        }
        i := ObbyTask.InfoBox
        if (x = 300 + i.dx && y = 300 + i.dy)
            return (s.open && s.selected != "") ? "Rolled at: [ Unknown ]`nWith luck of [ Unknown ]" : ""
        if (x = 150 && y = 265) {
            if s.daily                               ; live 18:18: the popup's tiles under the box
                return "x 10 x 2,000"
            if (this.button != "")
                return this.button
            ; like the game: the open storage shows Equip with nothing selected
            return !s.open ? "" : (s.selected = "") ? "Equip" : (s.selected == s.eq ? "Unequip" : "Equip")
        }
        return ""
    }
    Pixel(x, y, c, tol) => (x = 600 && y = 600 && this.blessing && this.State().expanded) || (x = 500 && y = 500 && this.buffShown)
    Aura() => {known: this.known, name: (this.logName != "-") ? this.logName : this.State().eq}
}

QmObbyCal(check := true) {
    p := Map("aura_open", {x: 10, y: 10, color: 0}, "aura_search", {x: 20, y: 20, color: 0}
        , "aura_equip", {x: 300, y: 300, color: 0}, "aura_close", {x: 400, y: 400, color: 0})
    if check {
        p["buff_expand"] := {x: 500, y: 500, color: 0}
        p["obby_blessing"] := {x: 600, y: 600, color: 0xABCDEF}
    }
    return QmCal(p, Map("aura_tile_rect", {x: 100, y: 100, w: 200, h: 50}))
}

; -> {t, io, wh, logs, s (the store)}
QmObbyTask(initial := "Glock", gets := "", check := true, routes := "", owned := "", cal := "") {
    io := QmIO()
    wh := QmWh()
    logs := []
    s := ObStore(io, initial, IsObject(owned) ? owned : ["Sailor", "Glock", "Celestial"])
    g := Map("Obby.enabled", 1)
    if (gets is Map)
        for k, v in gets
            g[k] := v
    t := ObbyTask({
        cfg: QmCfg(g, IsObject(routes) ? routes : QmObbyRoutes()),
        io: io, webhook: wh, cal: IsObject(cal) ? cal : QmObbyCal(check),
        ocr: (x, y, w, h, scale := 1) => s.Ocr(x, y, w, h),
        pixel: (x, y, c, tol) => s.Pixel(x, y, c, tol), rect: (x, y, w, h) => s.Rect(x, y, w, h),
        aura: () => s.Aura(),
        log: (m) => logs.Push(m)
    })
    return {t: t, io: io, wh: wh, logs: logs, s: s}
}

QmObbyDowns(io, key) {
    n := 0
    for e in io.log
        n += (e = "down " key) ? 1 : 0
    return n
}

; a task log line containing text
QmObbyLogHas(logs, text) {
    for m in logs
        if InStr(m, text)
            return true
    return false
}

; index of the first / last log entry equal to e (0 = none)
QmObbyFirst(io, e) {
    for i, x in io.log
        if (x = e)
            return i
    return 0
}
QmObbyLast(io, e) {
    i := io.log.Length
    while (i > 0) {
        if (io.log[i] = e)
            return i
        i--
    }
    return 0
}

; ---- eligibility ------------------------------------------------------------

Test_Obby_Eligibility() {
    o := QmObbyTask(, , , Map())
    AssertEq(o.t.name, "obby", "name")
    AssertEq(o.t.priority, 5, "priority")
    AssertEq(o.t.CanRun(SchedState()), false, "no route -> not eligible")
    AssertEq(QmObbyTask(, Map("Obby.enabled", 0)).t.CanRun(SchedState()), false, "off -> not eligible")
    AssertEq(QmObbyTask().t.CanRun(SchedState()), true, "on, route, aura storage calibrated -> eligible")
    AssertEq(QmObbyTask(, , , , , QmCal()).t.CanRun(SchedState()), false, "aura storage not calibrated -> not eligible")
}

; ---- the Sailor swap ----------------------------------------------------------

Test_Obby_EquipsSailorAndPutsTheOldAuraBack() {
    o := QmObbyTask("Glock")
    AssertEq(o.t.Run(SchedCtx()), 1, "blessing seen")
    AssertEq(o.s.State().eq, "Glock", "Glock equipped again")
    iRoute := QmObbyFirst(o.io, "down w")
    AssertTrue(QmObbyFirst(o.io, "type S") > 0 && QmObbyFirst(o.io, "type S") < iRoute, "Sailor searched before the route")
    AssertTrue(QmObbyLast(o.io, "type G") > iRoute, "Glock searched after the route")
    AssertEq(QmObbyDowns(o.io, "w"), 1, "route played once")
    AssertEq(o.wh.Count("obby"), 1, "obby webhook")
    AssertEq(o.wh.Count("errors"), 0, "no error")
    AssertEq(QmCountMoves(o.io, "move 500,500"), 2, "buff list expanded, then collapsed again")
    AssertTrue(!o.s.State().expanded, "left collapsed")
}

Test_Obby_NoAuraBeforeUnequipsSailor() {
    o := QmObbyTask("")
    AssertEq(o.t.Run(SchedCtx()), 1, "blessing seen")
    AssertEq(o.s.State().eq, "", "Sailor unequipped: no aura again")
    AssertEq(o.wh.Count("errors"), 0, "no error")
}

Test_Obby_AlreadySailorIsKept() {
    o := QmObbyTask("Sailor")
    AssertEq(o.t.Run(SchedCtx()), 1, "blessing seen")
    AssertEq(QmCountMoves(o.io, "move 300,300"), 0, "Equip / Unequip never clicked")
    AssertEq(QmCountMoves(o.io, "move 10,10"), 1, "the storage opened once to check (not again to put back)")
    AssertEq(o.s.State().eq, "Sailor", "Sailor kept")
}

; a fresh start while the log still says Sailor after an unequip: the
; button says Equip, so Sailor goes on and comes off again
Test_Obby_StaleSailorInTheLogMeansNoAura() {
    o := QmObbyTask("")
    o.s.logName := "Sailor"
    AssertEq(o.t.Run(SchedCtx()), 1, "ran")
    AssertTrue(QmObbyFirst(o.io, "move 300,300") < QmObbyFirst(o.io, "down w"), "Sailor equipped before the route")
    AssertEq(o.s.State().eq, "", "Sailor off again after")
    AssertEq(o.wh.Count("errors"), 0, "no error")
}

Test_Obby_NoSailorTileNothingEquipped() {
    o := QmObbyTask("Glock", , , , ["Glock"])
    AssertEq(o.t.Run(SchedCtx()), 0, "not run")
    AssertEq(QmCountMoves(o.io, "move 300,300"), 0, "the button never clicked")
    AssertEq(QmObbyDowns(o.io, "w"), 0, "route never played")
    AssertEq(o.wh.Count("errors"), 1, "reported")
    AssertEq(o.s.State().eq, "Glock", "aura unchanged")
    AssertTrue(!o.s.State().open, "storage closed")
}

Test_Obby_ClosesAuraCollectionsLeftOpen() {
    ; a run killed mid camera-reset left Aura Collections open (live 2026-11-02)
    o := QmObbyTask("Glock")
    o.s.coll := true
    AssertEq(o.t.Run(SchedCtx()), 1, "blessing seen")
    AssertEq(o.s.State().eq, "Glock", "Glock equipped again")
    iClose := QmObbyFirst(o.io, "move 525,158")
    AssertTrue(iClose > 0 && iClose < QmObbyFirst(o.io, "type S"), "closed before the Sailor search")
    AssertTrue(QmObbyLogHas(o.logs, "Aura Collections"), "logged")
    AssertEq(o.wh.Count("errors"), 0, "no error")
}

Test_Obby_EmptyTileChecksAuraCollectionsAndRetries() {
    ; the first check misses the screen: the search reads an empty first tile,
    ; then the screen is looked for once more, closed, and the swap retried
    o := QmObbyTask("Glock")
    o.s.coll := true, o.s.collMiss := 1
    sw := o.t.PutOnSailor(SchedCtx())
    AssertTrue(sw.ok, "Sailor on after the retry")
    AssertEq(o.s.State().eq, "Sailor", "Sailor worn")
    AssertEq(QmCountMoves(o.io, "move 525,158"), 1, "closed once")
    AssertTrue(QmObbyLogHas(o.logs, "Aura Collections"), "logged")
    ; nothing covers it: no retry
    o2 := QmObbyTask("Glock", , , , ["Glock"])
    AssertTrue(!o2.t.PutOnSailor(SchedCtx()).ok, "no Sailor owned")
    AssertEq(QmCountMoves(o2.io, "move 10,10"), 1, "storage opened once")
}

Test_Obby_ButtonNotEquipIsNeverClicked() {
    o := QmObbyTask("Glock")
    o.s.button := "Delete"
    AssertEq(o.t.Run(SchedCtx()), 0, "not run")
    AssertEq(QmCountMoves(o.io, "move 300,300"), 0, "Delete never clicked")
    AssertEq(o.wh.Count("errors"), 1, "reported")
    AssertTrue(InStr(o.wh.sent[1].desc, "Delete"), "says what the button read")
}

Test_Obby_UnknownAuraDoesNothing() {
    o := QmObbyTask("Glock")
    o.s.known := false
    AssertEq(o.t.Run(SchedCtx()), 0, "not run")
    AssertEq(o.io.log.Length, 0, "nothing pressed or clicked")
    AssertEq(o.wh.Count("errors"), 1, "reported once")
    ; 2026-10-27: unknown after a restart, the obby was still eligible and
    ; interrupted the sell every minute only to skip itself
    AssertEq(o.t.CanRun(SchedState()), false, "not eligible while the aura is unknown")
    o.s.known := true
    AssertEq(o.t.CanRun(SchedState()), true, "eligible once it is known")
}

Test_Obby_RestoreFailureIsReported() {
    ; the old aura's tile is not found after the run: Sailor stays, the user is told
    o := QmObbyTask("Glock", , , , ["Sailor"])
    o.s.initial := "Glock"
    AssertEq(o.t.Run(SchedCtx()), 1, "blessing seen")
    found := false
    for m in o.wh.sent
        found := found || (m.event = "errors" && InStr(m.desc, "Glock") && InStr(m.desc, "by hand"))
    AssertTrue(found, "errors webhook names the aura to put back by hand")
}

; ---- the blessing check ---------------------------------------------------------

Test_Obby_RetryThenError() {
    o := QmObbyTask("Glock", Map("Obby.retries", 1))
    o.s.blessing := false
    AssertEq(o.t.Run(SchedCtx()), 0, "never seen")
    AssertEq(QmObbyDowns(o.io, "w"), 2, "route played twice (1 retry)")
    AssertEq(o.wh.Count("obby"), 0, "no success webhook")
    AssertEq(o.s.State().eq, "Glock", "aura still restored")
    AssertTrue(InStr(o.wh.sent[o.wh.sent.Length].desc, "never showed"), "errors webhook says why")
}

Test_Obby_RetriesAreClamped() {
    o := QmObbyTask("Glock", Map("Obby.retries", 99))
    o.s.blessing := false
    o.t.Run(SchedCtx())
    AssertEq(QmObbyDowns(o.io, "w"), 4, "retries clamp to 3 -> 4 plays")
    AssertEq(ObbyTask.Retries(-2), 0, "negative -> 0")
    AssertEq(ObbyTask.Retries("x"), 1, "junk -> 1")
}

Test_Obby_UncheckedWithoutBuffPoints() {
    o := QmObbyTask("Glock", , false)
    AssertEq(o.t.Run(SchedCtx()), 0, "unchecked -> 0")
    AssertEq(QmObbyDowns(o.io, "w"), 1, "route played once")
    AssertEq(QmCountMoves(o.io, "move 500,500"), 0, "no expand click")
    found := false
    for m in o.wh.sent
        found := found || (m.event = "obby" && InStr(m.desc, "unchecked"))
    AssertTrue(found, "says unchecked")
    AssertEq(o.s.State().eq, "Glock", "aura restored")
}

Test_Obby_NameMatchesTheGameFont() {
    AssertTrue(ObbyTask.NameIs("Sailor`n1 in 3,000", "Sailor"), "the rarity line is left out")
    AssertTrue(ObbyTask.NameIs("Sailor`n'2.0O,OOO", "Sailor"), "a misread rarity line (live 2026-10-27, 1x)")
    AssertTrue(ObbyTask.NameIs("Celestiol", "Celestial"), "a = o in the game font")
    AssertTrue(!ObbyTask.NameIs("Sailor: Flying Dutchman", "Sailor"), "another aura is not Sailor")
    AssertTrue(!ObbyTask.NameIs("Sailor:`nFlying Dutchman", "Sailor"), "split over two lines it is still not Sailor")
    AssertTrue(!ObbyTask.NameIs("Sailor: tchman`ni 80.000 OOO", "Sailor"), "the live misread of Flying Dutchman")
    AssertTrue(!ObbyTask.NameIs("", "Sailor"), "empty")
}

; live 2026-11-10 12:34: "Sailor" equipped Sailor: Admiral first; the names
; must match exactly after folding, a partial read is never a match
Test_Obby_NameReadIsExactAfterNormalising() {
    AssertEq(ObbyTask.NameRead("Sailor", "Sailor"), "same", "plain")
    AssertEq(ObbyTask.NameRead("SAILOR`n1 in 12,000,000", "sailor"), "same", "case, rarity line")
    AssertEq(ObbyTask.NameRead("Sailor : Admiral`n1 in 2,500,000", "Sailor_Admiral"), "same", "the log's _ form")
    AssertEq(ObbyTask.NameRead("Sailor: Admiral", "Sailor"), "other", "Sailor: Admiral is not Sailor")
    AssertEq(ObbyTask.NameRead("Sailor:", "Sailor"), "other", "'Sailor:' goes on past Sailor")
    AssertEq(ObbyTask.NameRead("Sailor:", "Sailor_Admiral"), "unread", "'Sailor:' may be Admiral cut short")
    AssertEq(ObbyTask.NameRead("Sailor", "Sailor_Admiral"), "unread", "Sailor is never Sailor: Admiral")
    AssertEq(ObbyTask.NameRead("Saibr", "Sailor"), "same", "two letters off plain Sailor (no colon: not a Sailor: variant)")
    AssertEq(ObbyTask.NameRead("Glock", "Sailor"), "other", "another name")
    AssertEq(ObbyTask.NameRead("Sailor Flying Dutchman`ni in", "Sailor_Flying_Dutchman"), "same", "3x's 'i in' rarity line left out")
    AssertEq(ObbyTask.NameRead("", "Sailor"), "unread", "nothing")
}

; live 2026-11-10: Luminosity's logo name read 'LVIßTOSITY' / 'xvnmrosrrr';
; as "another aura" no tile was ever tried and the put-back scanned for
; minutes. A read that is no known aura name is noise (unread); a real
; lookalike stays "other".
Test_Obby_NoiseReadIsNotAnotherAura() {
    old := ObbyTask.Known
    try {
        m := Map()
        for n in ["Sailor", "Sailor: Admiral", "Luminosity", "Pumpkinity", "Eden"]
            m[GameLists.Fold(n)] := true
        ObbyTask.Known := m
        AssertEq(ObbyTask.NameRead("LVIßTOSITY", "Luminosity"), "unread", "garbled logo name")
        AssertEq(ObbyTask.NameRead("xvnmrosrrr", "Luminosity"), "unread", "noise")
        AssertEq(ObbyTask.NameRead("Sailor Admiral", "Sailor"), "other", "a real lookalike stays other")
        AssertEq(ObbyTask.NameRead("Pumpkinity", "Luminosity"), "other", "another real aura")
        AssertEq(ObbyTask.NameRead("Sailor", "Sailor"), "same", "exact")
    } finally {
        ObbyTask.Known := old
    }
}

Test_Obby_NameVerdictAcrossScales() {
    AssertEq(ObbyTask.NameVerdict(["Sailor", "Sailor", "Sailor`n'2.0O,OOO"], "Sailor"), "same", "every scale agrees")
    AssertEq(ObbyTask.NameVerdict(["Sailor", "Sailor:", "Sailor"], "Sailor"), "unread", "one scale saw the colon: Admiral cut short")
    AssertEq(ObbyTask.NameVerdict(["Sailor", "Sailor Admiral", ""], "Sailor"), "unread", "a longer name at one scale")
    dutch := ["Sailor: tchman`ni 80.000 OOO", "Sailor Flying Dutchman`ni in", "Sa Flying Du tchma n"]
    AssertEq(ObbyTask.NameVerdict(dutch, "Sailor_Flying_Dutchman"), "same", "partial reads agree with the whole one")
    AssertEq(ObbyTask.NameVerdict(dutch, "Sailor"), "other", "Flying Dutchman is not Sailor")
    AssertEq(ObbyTask.NameVerdict(["", "", ""], "Luminosity"), "unread", "a logo")
}

; put-back: the previous aura's tile is picked by its name, the lookalikes
; in front of it never equipped
Test_Obby_PutBackPicksTheRightTileFirst() {
    owned := ["Sailor: Admiral", "Sailor: Admiral", "Sailor: Admiral", "Sailor: Flying Dutchman", "Sailor", "Eden"]
    o := QmObbyTask("Sailor", , , , owned)
    o.s.special := ["Eden"]
    o.s.names["Sailor: Admiral"] := "Sailor:`n1 in 2,500,000"     ; read cut short
    o.t.wear := "Eden"
    sw := o.t.PutOnSailor(SchedCtx())
    AssertTrue(sw.ok, "Eden on")
    AssertEq(sw.prev, "Sailor", "Sailor before")
    AssertTrue(o.t.PutBack(SchedCtx(), sw), "put back")
    h := o.s.State().hist
    AssertEq(h.Length, 2, "two equips: Eden, then Sailor")
    AssertEq(h[2], "Sailor", "Sailor equipped again")
    AssertTrue(QmObbyLogHas(o.logs, "Sailor is result 5"), "found by its name, result 5")
    AssertTrue(!QmObbyLogHas(o.logs, "found by the log"), "no equip-and-check")
}

; no name reads for some results: only those are equipped in turn, never
; one whose name read as another aura, and the first exact log match stops it
Test_Obby_LogPickSkipsReadOthersAndStopsAtTheFirstMatch() {
    owned := ["Sailor: Admiral", "Sailor: Flying Dutchman", "Sailor", "Sailor Moon", "Glock"]
    o := QmObbyTask("Glock", , , , owned)
    o.s.logo := ["Sailor: Flying Dutchman", "Sailor", "Sailor Moon"]
    AssertEq(o.t.Run(SchedCtx()), 1, "blessing seen")
    h := o.s.State().hist
    AssertEq(h.Length, 3, "Dutchman (unread), Sailor (the log said so), Glock back")
    AssertEq(h[1], "Sailor: Flying Dutchman", "the unread tile tried")
    AssertEq(h[2], "Sailor", "stopped at Sailor")
    AssertEq(h[3], "Glock", "Glock back by its name")
    for a in h
        AssertTrue(a != "Sailor: Admiral" && a != "Sailor Moon", "never equipped: " a)
    AssertEq(o.wh.Count("errors"), 0, "no error")
}

; the name panel still shows the tile before for a moment after a click: a
; stale read is read again, so the wanted tile is not marked as another aura
Test_Obby_StaleNameReadIsReadAgain() {
    o := QmObbyTask("Glock", , , , ["Sailor: Flying Dutchman", "Sailor", "Glock"])
    o.s.lag := ObbyTask.NameScales.Length
    AssertEq(o.t.Run(SchedCtx()), 1, "blessing seen")
    h := o.s.State().hist
    AssertEq(h.Length, 2, "Sailor, then Glock back")
    AssertEq(h[1], "Sailor", "Sailor found by its name")
    AssertTrue(!QmObbyLogHas(o.logs, "found by the log"), "no equip-and-check")
}

; clip 2026-10-27 20:17: "Sailor" lists six Sailor: Admiral and a Sailor:
; Flying Dutchman before plain Sailor; only the first tile was read
Test_Obby_FindsSailorBehindItsLookalikes() {
    owned := []
    Loop 6
        owned.Push("Sailor: Admiral")
    owned.Push("Sailor: Flying Dutchman", "Sailor", "Glock")
    o := QmObbyTask("Glock", , , , owned)
    AssertEq(o.t.Run(SchedCtx()), 1, "blessing seen")
    st := ObbyTask.TileStep
    i8 := QmObbyFirst(o.io, "move " (200 + 7 * st.dx) ",125")
    AssertTrue(i8 > 0 && i8 < QmObbyFirst(o.io, "down w"), "the 8th tile (Sailor) selected before the route")
    AssertEq(QmObbyFirst(o.io, "move " (200 + 8 * st.dx) ",125"), 0, "the scan stopped at Sailor")
    AssertEq(o.s.State().eq, "Glock", "Glock back after (Sailor: Admiral never equipped)")
    AssertEq(o.wh.Count("errors"), 0, "no error")
    AssertEq(o.s.State().eq, "Glock", "Glock back after")
}

; the same clip: Ctrl+A does nothing in the search, so typing again made
; "SailoSailor" and nothing was found
Test_Obby_ClearsTheOldSearchWithoutCtrlA() {
    o := QmObbyTask("Glock")
    o.s.leftover := "SailoSailoSailSoilor"
    AssertEq(o.t.Run(SchedCtx()), 1, "blessing seen")
    AssertEq(QmObbyDowns(o.io, "Ctrl"), 0, "no Ctrl+A")
    AssertTrue(QmObbyFirst(o.io, "down End") > 0, "End before the Backspaces")
    AssertEq(o.wh.Count("errors"), 0, "no error")
}

; live 2026-10-27: Unequip worked (the button turned back to Equip), but
; the log's "Equipped" line still said Sailor ~2 min later, so the put-back
; was reported as failed
Test_Obby_UnequipConfirmedByTheButtonWhenTheLogLags() {
    o := QmObbyTask("")
    o.s.logName := ""                ; the log saw no aura before
    sw := o.t.PutOnSailor(SchedCtx())
    AssertTrue(sw.ok, "Sailor equipped (button turned to Unequip)")
    o.s.logName := "Sailor"          ; ...and keeps saying Sailor after the unequip
    AssertTrue(o.t.PutBack(SchedCtx(), sw), "put back: the button turned to Equip")
    AssertEq(o.s.State().eq, "", "Sailor off")
    AssertEq(o.wh.Count("errors"), 0, "no false 'put it back by hand'")
}

; the next obby run (every minute) while the log still says Sailor: Sailor
; is equipped again and taken off again, not taken as "already on"
Test_Obby_StaleLogIsNotTrustedAfterItsOwnChange() {
    o := QmObbyTask("")
    o.s.logName := ""
    AssertEq(o.t.Run(SchedCtx()), 1, "first run")
    o.s.logName := "Sailor"          ; stale
    AssertEq(o.t.Run(SchedCtx()), 1, "second run")
    AssertEq(QmObbyDowns(o.io, "w"), 2, "both runs played the route")
    AssertEq(o.s.State().eq, "", "Sailor off after both")
    AssertEq(o.wh.Count("errors"), 0, "no error")
}

; review 2026-10-27: a merchant / potion preempt during the route skipped
; the put-back, and the next run took Sailor for the user's own aura
Test_Obby_PreemptStillPutsTheAuraBack() {
    o := QmObbyTask("Glock")
    ctx := SchedCtx()
    io := o.io
    io.DefineProp("Down", {Call: (self, k) => (self.log.Push("down " k), (k = "w") ? ctx.RequestPreempt() : 0)})
    o.t.Run(ctx)
    AssertEq(o.s.State().eq, "Glock", "Glock back on although the obby was preempted")
    AssertEq(o.t.Owed(), "", "nothing owed")
    AssertTrue(!o.s.State().open, "storage closed")
}

; F3 / pause / Roblox losing focus: no input may be sent, so the aura is
; owed, and the next run puts THAT aura back (not Sailor)
Test_Obby_HaltOwesTheAuraToTheNextRun() {
    o := QmObbyTask("Glock")
    ctx := SchedCtx()
    io := o.io
    io.DefineProp("Down", {Call: (self, k) => (self.log.Push("down " k), (k = "w") ? ctx.Pause() : 0)})
    o.t.Run(ctx)
    AssertEq(o.s.State().eq, "Sailor", "halted: Sailor stays on (nothing sent)")
    AssertEq(o.t.Owed(), "Glock", "Glock is owed")
    io.DefineProp("Down", {Call: (self, k) => self.log.Push("down " k)})
    AssertEq(o.t.Run(SchedCtx()), 1, "next run")
    AssertEq(o.s.State().eq, "Glock", "Glock back after the next run")
    AssertEq(o.t.Owed(), "", "paid")
}

; a preempt during the Sailor swap itself: the swap finishes
Test_Obby_PreemptDuringTheSwapFinishesIt() {
    o := QmObbyTask("Glock")
    ctx := SchedCtx()
    io := o.io
    io.DefineProp("Type", {Call: (self, t) => (self.log.Push("type " t), ctx.RequestPreempt())})
    sw := o.t.PutOnSailor(ctx)
    AssertTrue(sw.ok, "Sailor on")
    AssertEq(sw.prev, "Glock", "prev kept")
    AssertTrue(!o.s.State().open, "storage closed")
}

; "Unequip" read without its U: still worn, never clicked
Test_Obby_NequipReadsAsWorn() {
    o := QmObbyTask("Sailor")
    o.s.button := "nequip"
    o.t.Run(SchedCtx())
    AssertEq(QmCountMoves(o.io, "move 300,300"), 0, "the button is never clicked")
}

Test_Input_ClearTextEndThenBackspaces() {
    io := QmIO()
    Input.ClearText(io)
    AssertEq(io.log[1], "down End", "End first")
    AssertEq(QmObbyDowns(io, "Backspace"), Input.ClearKeys, "ClearKeys Backspaces")
    AssertEq(QmObbyDowns(io, "Ctrl"), 0, "no Ctrl+A (Roblox ignores it)")
    io2 := QmIO()
    Input.ClearText(io2, 6)
    AssertEq(QmObbyDowns(io2, "Backspace"), 6, "a custom count")
}

Test_Obby_StopMidRunReleasesKeys() {
    o := QmObbyTask("Sailor")
    ctx := SchedCtx()
    ctx.Stop()
    o.t.Run(ctx)
    held := Map()
    for e in o.io.log {
        if (SubStr(e, 1, 5) = "down ")
            held[SubStr(e, 6)] := (held.Has(SubStr(e, 6)) ? held[SubStr(e, 6)] : 0) + 1
        else if (SubStr(e, 1, 3) = "up ")
            held[SubStr(e, 4)] := (held.Has(SubStr(e, 4)) ? held[SubStr(e, 4)] : 0) - 1
    }
    for k, v in held
        AssertEq(v <= 0, true, "key " k " released")
    AssertEq(o.wh.Count("errors"), 0, "a stop is not a failure")
}

Test_Obby_DroppedEquipClickIsClickedAgain() {
    o := QmObbyTask("Glock")
    o.s.drop := 1
    AssertEq(o.t.Run(SchedCtx()), 1, "blessing seen")
    AssertEq(o.wh.Count("errors"), 0, "Sailor on after the second click")
    AssertEq(o.s.State().eq, "Glock", "Glock back")
}

; a join quiet (60 s+) is running: our own swap's 20 s must not cut it short
Test_Obby_SwapKeepsALongerJoinQuiet() {
    try {
        long := A_TickCount + 600000
        Auras.QuietUntil := long
        o := QmObbyTask("Glock")
        AssertEq(o.t.Run(SchedCtx()), 1, "blessing seen")
        AssertTrue(Auras.QuietUntil >= long, "the swap kept the longer join quiet")
        Auras.QuietUntil := long
        o := QmObbyTask("Glock", , , , ["Celestial", "Sailor", "Glock"])
        o.s.owned := ["Sailor: Admiral", "Sailor", "Glock"]
        o.s.logo := ["Sailor: Admiral", "Sailor"]
        AssertEq(o.t.Run(SchedCtx()), 1, "names unread: found through the log")
        AssertTrue(Auras.QuietUntil >= long, "the log pick kept the longer join quiet")
        Auras.QuietUntil := 0
        o := QmObbyTask("Glock")
        o.t.Run(SchedCtx())
        AssertTrue(Auras.QuietUntil > A_TickCount, "no quiet before: the swap still sets one")
    } finally
        Auras.QuietUntil := 0
}

Test_Obby_SearchTextFromLogNames() {
    AssertEq(ObbyTask.SearchText(":Flushed:_Pumpkinity"), "Pumpkinity", "emoji code and _ dropped")
    AssertEq(ObbyTask.SearchText("Kyawthuite_Remembrance"), "Remembrance", "longest word")
    AssertEq(ObbyTask.SearchText("Sailor"), "Sailor", "plain name")
    AssertTrue(ObbyTask.NameIs("Flushed : Pumpkinity`n1 in 2,000", ":Flushed:_Pumpkinity"), "the tile's name still matches the log name")
}

; ---- no blind clicks (live 2026-11-02 09:20) ---------------------------------
; "Eden" searched on the Regular tab showed an empty grid (Eden is under
; Special); the click on the empty slot went through the storage into the
; world and opened Roblox's "Buy Robux and item" prompt for a Donation board.

; a click on result slot k (any tab) in the IO log
QmObbyTileClicks(io, k) {
    st := ObbyTask.TileStep
    pt := "move " (200 + Mod(k - 1, ObbyTask.TileCols) * st.dx) "," (125 + ((k - 1) // ObbyTask.TileCols) * st.dy)
    n := 0, last := ""
    for e in io.log {
        if (e = "click" && last = pt)
            n++
        if (SubStr(e, 1, 5) = "move ")
            last := e
    }
    return n
}

Test_Obby_TileShownIsPure() {
    dark := [], lit := []
    Loop 100
        dark.Push(0x101418), lit.Push(Mod(A_Index, 5) = 0 ? 0xFFFFFF : 0x101418)
    AssertTrue(!ObbyTask.TileShown(dark, 10, 10), "an empty slot: no bright pixels")
    AssertTrue(ObbyTask.TileShown(lit, 10, 10), "a tile: a bright name")
    few := dark.Clone()
    Loop ObbyTask.TileInk - 1
        few[A_Index] := 0xFFFFFF
    AssertTrue(!ObbyTask.TileShown(few, 10, 10), "a few bright pixels are not a tile")
    AssertTrue(!ObbyTask.TileShown(lit, 10, 9), "wrong size -> not shown")
    AssertTrue(!ObbyTask.TileShown("", 10, 10), "no pixels -> not shown")
}

Test_Obby_EmptyGridIsNeverClicked() {
    ; Eden under Special, its name a logo: Regular lists nothing
    o := QmObbyTask("Glock", , , , ["Glock", "Eden"])
    o.s.special := ["Eden"], o.s.logo := ["Eden"]
    o.t.wear := "Eden"
    sw := o.t.PutOnSailor(SchedCtx())
    AssertTrue(sw.ok, "Eden on from the Special tab")
    AssertEq(o.s.State().eq, "Eden", "Eden worn")
    AssertTrue(!o.s.State().prompt, "no purchase prompt (no click went through)")
    AssertEq(QmObbyDowns(o.io, "Esc"), 0, "no Esc needed")
    AssertEq(QmObbyTileClicks(o.io, 2), 0, "slot 2 (empty on both tabs) never clicked")
    AssertTrue(QmObbyLogHas(o.logs, "Regular tab is empty"), "the empty Regular grid is logged")
    ; Regular's slot 1 was never clicked: every slot-1 click came after the Special tab
    iSpecial := QmObbyFirst(o.io, "move 567,-25")
    AssertTrue(iSpecial > 0, "the Special tab was opened")
    AssertTrue(QmObbyFirst(o.io, "move 200,125") > iSpecial, "no tile clicked before the Special tab")
}

Test_Obby_NothingOwnedClicksNoTile() {
    o := QmObbyTask("Glock", , , , ["Glock"])
    AssertTrue(!o.t.PutOnSailor(SchedCtx()).ok, "no Sailor owned")
    AssertEq(QmObbyTileClicks(o.io, 1), 0, "no tile clicked: the grid was empty")
    AssertTrue(!o.s.State().prompt, "no purchase prompt")
}

Test_Obby_PurchasePromptClosedWithEscNeverClicked() {
    o := QmObbyTask("Glock")
    o.s.prompt := true
    sw := o.t.PutOnSailor(SchedCtx())
    AssertTrue(!sw.ok, "the swap stops")
    AssertEq(o.io.Clicks(), 0, "nothing clicked")
    AssertEq(QmObbyDowns(o.io, "Esc"), 1, "closed with Esc")
    AssertTrue(!o.s.State().prompt, "the prompt is gone")
    AssertTrue(QmObbyLogHas(o.logs, "purchase prompt closed"), "logged")
    found := false
    for m in o.wh.sent
        found := found || (m.event = "errors" && InStr(m.title, "Purchase prompt"))
    AssertTrue(found, "errors webhook")
    AssertEq(o.s.State().eq, "Glock", "aura unchanged")
}

Test_Obby_StuckPurchasePromptIsReportedNeverClicked() {
    o := QmObbyTask("Glock")
    o.s.prompt := true, o.s.promptStuck := true
    AssertTrue(!o.t.PutOnSailor(SchedCtx()).ok, "the swap stops")
    AssertEq(o.io.Clicks(), 0, "nothing clicked")
    AssertEq(QmObbyDowns(o.io, "Esc"), Input.PurchaseTries, "Esc tried PurchaseTries times")
    found := false
    for m in o.wh.sent
        found := found || (m.event = "errors" && InStr(m.desc, "close it yourself"))
    AssertTrue(found, "the user is told to close it (never Buy)")
}

Test_Obby_PromptMidSwapStopsIt() {
    ; a prompt comes up after the tab click: the next click is refused
    o := QmObbyTask("Glock")
    io := o.io, s := o.s
    io.DefineProp("ClickHere", {Call: (self) => (self.log.Push("click"), (QmObbyLastMove(self) = "move 122,-25") ? (s.prompt := true) : 0)})
    AssertTrue(!o.t.PutOnSailor(SchedCtx()).ok, "the swap stops")
    AssertEq(QmObbyDowns(io, "Esc"), 1, "closed with Esc")
    AssertEq(QmObbyTileClicks(io, 1), 0, "no tile clicked after it")
    AssertEq(QmCountMoves(io, "move 300,300"), 0, "Equip never clicked")
    AssertTrue(InStr(o.t._why, "purchase prompt"), "why says it")
}

QmObbyLastMove(io) {
    i := io.log.Length
    while (i > 0) {
        if (SubStr(io.log[i], 1, 5) = "move ")
            return io.log[i]
        i--
    }
    return ""
}

Test_Obby_StorageNotOpenNothingClicked() {
    o := QmObbyTask("Glock")
    o.s.closed := true
    sw := o.t.PutOnSailor(SchedCtx())
    AssertTrue(!sw.ok, "no swap")
    AssertEq(o.io.Clicks(), 1, "only its button clicked")
    AssertEq(QmCountMoves(o.io, "move 122,-25"), 0, "no tab clicked")
    AssertEq(QmCountMoves(o.io, "move 400,400"), 0, "no close clicked (it is not open)")
    AssertTrue(InStr(sw.why, "did not open"), "why says it")
}

Test_Obby_EquipNeedsTheStorageTitle() {
    ; the title stops reading after the tile was picked: Equip is not clicked
    o := QmObbyTask("Glock")
    s := o.s
    base := s.Ocr.Bind(s)
    sb := ObbyTask.StorageBox
    s.DefineProp("Ocr", {Call: (self, x, y, w, h) => (x = 20 + sb.dx && y = 20 + sb.dy && self.State().selected != "") ? "" : base(x, y, w, h)})
    AssertTrue(!o.t.PutOnSailor(SchedCtx()).ok, "no swap")
    AssertEq(o.s.State().eq, "Glock", "Equip never clicked (the mouse may rest on it)")
    AssertTrue(InStr(o.t._why, "not open"), "why says it")
}

Test_Obby_BuffButtonOnlyWhereItShows() {
    ; live 2026-11-02: a click on an empty spot went through into the world.
    ; The buff list button is not where it was calibrated: never clicked,
    ; the run is reported as not checked (no replay)
    o := QmObbyTask("Glock", Map("Obby.retries", 1))
    o.s.buffShown := false
    AssertEq(o.t.Run(SchedCtx()), 0, "not checked")
    AssertEq(QmCountMoves(o.io, "move 500,500"), 0, "buff_expand never clicked")
    AssertEq(QmObbyDowns(o.io, "w"), 1, "route played once")
    AssertTrue(QmObbyLogHas(o.logs, "buff_expand"), "logged why")
    found := false
    for m in o.wh.sent
        found := found || (m.event = "errors" && InStr(m.desc, "not checked"))
    AssertTrue(found, "reported")
    AssertEq(o.s.State().eq, "Glock", "aura restored")
    ; it shows: expanded, checked, collapsed again
    o2 := QmObbyTask("Glock")
    AssertEq(o2.t.Run(SchedCtx()), 1, "claimed")
    AssertEq(QmCountMoves(o2.io, "move 500,500"), 2, "expanded and collapsed")
    AssertTrue(!o2.s.State().expanded, "left collapsed")
}

Test_Obby_PromptAfterBuffButtonStopsTheCheck() {
    o := QmObbyTask("Glock", Map("Obby.retries", 1))
    o.s.promptOnExpand := true
    AssertEq(o.t.Run(SchedCtx()), 0, "not claimed")
    AssertEq(QmCountMoves(o.io, "move 500,500"), 1, "no second click on buff_expand")
    AssertTrue(QmObbyFirst(o.io, "down Esc") > 0 && !o.s.State().prompt, "closed with Esc")
    AssertEq(QmObbyDowns(o.io, "w"), 1, "no replay after a prompt")
    found := false
    for m in o.wh.sent
        found := found || (m.event = "errors" && InStr(m.title, "Purchase prompt"))
    AssertTrue(found, "reported")
}

; clicks sent while the mouse was last moved to xy ("400,400")
QmClicksAt(io, xy) {
    n := 0, last := ""
    for e in io.log {
        if (SubStr(e, 1, 5) = "move ")
            last := SubStr(e, 6)
        else if (e = "click" && last = xy)
            n++
    }
    return n
}

Test_Obby_DroppedCloseClickIsRetriedUntilClosed() {
    ; live 2026-11-02 23:29: one unchecked click on the X, and the storage
    ; stayed open over the whole hunt
    o := QmObbyTask("Glock")
    o.s.closeDrop := 1
    sw := o.t.PutOnSailor(SchedCtx())
    AssertTrue(sw.ok, "Sailor on")
    AssertTrue(!o.s.State().open, "the storage is closed")
    AssertEq(QmClicksAt(o.io, "400,400"), 2, "the X clicked again after the dropped click")
    AssertEq(o.wh.Count("errors"), 0, "no error")
}

Test_Obby_StorageLeftOpenWithTheAuraOnIsClosed() {
    ; 23:27 left it open; 23:29 found Eden on already (Unequip) and the
    ; close did not take: the hunt ran under it
    o := QmObbyTask("Sailor")
    o.s.openAtStart := true, o.s.closeDrop := 1
    sw := o.t.PutOnSailor(SchedCtx())
    AssertTrue(sw.ok && sw.had, "Sailor was on already")
    AssertEq(QmClicksAt(o.io, "10,10"), 0, "its sidebar button never clicked (it would close it)")
    AssertEq(QmClicksAt(o.io, "300,300"), 0, "Equip / Unequip never clicked")
    AssertTrue(!o.s.State().open, "closed")
}

Test_Obby_BannerOverTheTitleIsWaitedOut() {
    ; 23:27: the PUMPKIN MOON banner over the title: "not open (its title
    ; did not read)", no swap. The panel shows: the title is read again
    o := QmObbyTask("Glock")
    o.s.titleMiss := 6
    sw := o.t.PutOnSailor(SchedCtx())
    AssertTrue(sw.ok, "Sailor on")
    AssertEq(o.s.State().eq, "Sailor", "Sailor worn")
    AssertTrue(!QmObbyLogHas(o.logs, "title did not read"), "no title failure")
    AssertTrue(!o.s.State().open, "closed")
}

Test_Obby_TitleNeverReadsSidebarButtonClosesIt() {
    ; panel up, title never reads: the X is never clicked blind; the
    ; storage's own sidebar button toggles it shut
    o := QmObbyTask("Glock")
    o.s.openAtStart := true, o.s.titleMiss := 100000
    AssertEq(o.t.Covered(), "storage", "seen by its panel")
    AssertEq(o.t.ClearView(SchedCtx()), "", "clear")
    AssertTrue(!o.s.State().open, "closed")
    AssertEq(QmClicksAt(o.io, "400,400"), 0, "the X never clicked without its title")
    AssertEq(QmClicksAt(o.io, "10,10"), 1, "its sidebar button once")
    AssertTrue(QmObbyLogHas(o.logs, "sidebar button"), "logged")
}

Test_Obby_ClearViewClosesPromptCollectionsAndStorage() {
    o := QmObbyTask("Glock")
    AssertEq(o.t.Covered(), "", "nothing up")
    AssertEq(o.t.ClearView(SchedCtx()), "", "nothing to do")
    AssertEq(o.io.Clicks(), 0, "no click")
    o.s.prompt := true, o.s.coll := true, o.s.openAtStart := true
    AssertEq(o.t.Covered(), "purchase", "the prompt first")
    AssertEq(o.t.ClearView(SchedCtx()), "", "all closed")
    s := o.s.State()
    AssertTrue(!s.prompt && !s.coll && !s.open, "prompt, Collections and storage gone")
    AssertEq(QmObbyDowns(o.io, "Esc"), 1, "the prompt with Esc")
    AssertTrue(QmObbyFirst(o.io, "down Esc") < QmObbyFirst(o.io, "click"), "no click before the prompt went")
    AssertEq(QmClicksAt(o.io, "300,300"), 0, "nothing inside the storage clicked")
    AssertTrue(QmObbyLogHas(o.logs, "Aura Storage window was open"), "logged")
}

Test_Obby_DailyRewardsClosedBeforeTheSwap() {
    ; live 2026-11-03 18:18: the popup over the storage, the swap read its
    ; tiles as the Equip button
    o := QmObbyTask("Glock")
    o.s.daily := true
    AssertTrue(o.t.PutOnSailor(SchedCtx()).ok, "the swap went through")
    AssertEq(o.s.State().eq, "Sailor", "Sailor on")
    AssertTrue(!o.s.State().daily, "the popup gone")
    AssertEq(QmClicksAt(o.io, "1890,527"), 1, "its X once")
    AssertTrue(QmObbyFirst(o.io, "move 1890,527") < QmObbyFirst(o.io, "move 10,10"), "before the storage opened")
    AssertEq(QmClicksAt(o.io, "1280,895"), 0, "its Claim never pressed")
    AssertTrue(QmObbyLogHas(o.logs, "Daily Rewards popup was over the game"), "logged")
}

Test_Obby_DailyRewardsMidSwapIsClosedAndTheSwapRetried() {
    o := QmObbyTask("Glock")
    o.s.dailyOnType := true
    AssertTrue(o.t.PutOnSailor(SchedCtx()).ok, "the second pass went through")
    AssertEq(o.s.State().eq, "Sailor", "Sailor on")
    AssertEq(QmClicksAt(o.io, "1890,527"), 1, "its X once")
}

Test_Obby_ClearViewClosesDailyRewards() {
    o := QmObbyTask("Glock")
    o.s.daily := true, o.s.prompt := true, o.s.coll := true, o.s.openAtStart := true
    AssertEq(o.t.Covered(), "purchase", "the prompt first")
    AssertEq(o.t.ClearView(SchedCtx()), "", "all four closed")
    s := o.s.State()
    AssertTrue(!s.daily && !s.prompt && !s.coll && !s.open, "nothing left")
    AssertTrue(QmObbyFirst(o.io, "down Esc") < QmObbyFirst(o.io, "click"), "no click before the prompt went")
    AssertEq(QmClicksAt(o.io, "1890,527"), 1, "its X once")
    o2 := QmObbyTask("Glock")
    o2.s.daily := true
    AssertEq(o2.t.Covered(), "daily rewards", "seen by its title")
}

; real frames: the Inventory left over the game closes by its X, read on the
; frame with the real OCR until the click, the plain world after it
Test_Obby_InventoryClosedByItsX() {
    for f in ["inventory_open_sand", "inventory_open_rainy", "inventory_open_day"] {
        o := QmObbyTask("Glock")
        path := A_ScriptDir "\screens\" f ".jpg", world := A_ScriptDir "\screens\world_day.jpg"
        o.t._env.ocrFn := (x, y, w, h, scale := 1) => Ocr.ReadFile(o.io.Clicks() ? world : path, x, y, w, h, scale)
        AssertEq(o.t.Covered(), "inventory", f ": seen by its title")
        AssertEq(o.t.ClearView(SchedCtx()), "", f ": clear")
        AssertEq(o.io.Clicks(), 1, f ": one click")
        AssertEq(QmObbyLastMove(o.io), "move " ObbyTask.InvX[1] "," ObbyTask.InvX[2], f ": on its X")
    }
}

; L63 01:17:39: the UGC Shop over a fight (E opened it): closed by its X,
; read on the real frame until the click, never Purchase
Test_Obby_UgcShopClosedByItsX() {
    o := QmObbyTask("Glock")
    path := A_ScriptDir "\screens\ugc_shop_windy.jpg", world := A_ScriptDir "\screens\world_day.jpg"
    o.t._env.ocrFn := (x, y, w, h, scale := 1) => Ocr.ReadFile(o.io.Clicks() ? world : path, x, y, w, h, scale)
    AssertEq(o.t.Covered(), "ugc shop", "seen by its title")
    AssertEq(o.t.ClearView(SchedCtx()), "", "clear")
    AssertEq(o.io.Clicks(), 1, "one click")
    AssertEq(QmObbyLastMove(o.io), "move " ObbyTask.InvX[1] "," ObbyTask.InvX[2], "on its X")
}

; L72 04:32..04:55: Jock's dialog over hunt after hunt (E opened it): one
; click on his Leave, read on the real crop until the click (boxes off the
; crop read nothing), nothing else clicked
Test_Obby_JockDialogLeft() {
    o := QmObbyTask("Glock")
    path := A_ScriptDir "\screens\jock_dialog_snowy_x680_y890.png", world := A_ScriptDir "\screens\world_day.jpg"
    o.t._env.ocrFn := (x, y, w, h, scale := 1) => o.io.Clicks() ? Ocr.ReadFile(world, x, y, w, h, scale)
        : (x >= 680 && y >= 890 && x + w <= 1880 && y + h <= 1350) ? Ocr.ReadFile(path, x - 680, y - 890, w, h, scale) : ""
    AssertEq(o.t.Covered(), "jock dialog", "seen by his name")
    AssertEq(o.t.ClearView(SchedCtx()), "", "clear")
    AssertEq(o.io.Clicks(), 1, "one click")
    AssertEq(QmObbyLastMove(o.io), "move " ObbyTask.JockLeave[1] "," ObbyTask.JockLeave[2], "on Leave")
    AssertEq(ObbyTask.JockLeave[1] >= 1610 && ObbyTask.JockLeave[1] <= 1850 && ObbyTask.JockLeave[2] >= 1230 && ObbyTask.JockLeave[2] <= 1282, true, "inside the Leave button (x 1602-1856, y 1223-1288)")
}

; still up after every click: given up, reported
Test_Obby_JockDialogStuckIsReported() {
    o := QmObbyTask("Glock")
    path := A_ScriptDir "\screens\jock_dialog_sand_x680_y890.png"
    o.t._env.ocrFn := (x, y, w, h, scale := 1) => (x >= 680 && y >= 890 && x + w <= 1880 && y + h <= 1350) ? Ocr.ReadFile(path, x - 680, y - 890, w, h, scale) : ""
    AssertEq(o.t.ClearView(SchedCtx()), "jock dialog", "still up")
    AssertEq(o.io.Clicks(), ObbyTask.QuestTries, "its tries, no more")
}

Test_Obby_InventoryStuckIsReported() {
    o := QmObbyTask("Glock")
    path := A_ScriptDir "\screens\inventory_open_rainy.jpg"
    o.t._env.ocrFn := (x, y, w, h, scale := 1) => Ocr.ReadFile(path, x, y, w, h, scale)
    AssertEq(o.t.ClearView(SchedCtx()), "inventory", "still up")
    AssertEq(o.io.Clicks(), ObbyTask.QuestTries, "its tries, no more")
}

; live 18:27 / 18:32: Esc only opens the Roblox menu over the page
Test_Obby_QuestPageClosedByItsExit() {
    o := QmObbyTask("Glock")
    o.s.quest := true, o.s.questDrop := 1
    AssertEq(o.t.Covered(), "quest", "seen by its Objects")
    AssertEq(o.t.ClearView(SchedCtx()), "", "clear")
    AssertTrue(!o.s.State().quest, "gone")
    AssertEq(QmObbyFirst(o.io, "down Esc"), 0, "no Esc")
}

Test_Obby_QuestPageExitClickedOnlyWhenItReads() {
    o := QmObbyTask("Glock")
    o.s.quest := true, o.s.questExit := ""
    AssertEq(o.t.ClearView(SchedCtx()), "quest", "still up")
    AssertEq(o.io.Clicks(), 0, "no click on an unread Exit")
    o2 := QmObbyTask("Glock")
    o2.s.quest := true, o2.s.questDrop := 99
    AssertEq(o2.t.ClearView(SchedCtx()), "quest", "still up")
    AssertEq(o2.io.Clicks(), ObbyTask.QuestTries, "QuestTries clicks")
    o3 := QmObbyTask("Glock")
    o3.s.quest := true, o3.s.prompt := true, o3.s.promptStuck := true
    o3.t.ClearView(SchedCtx())
    AssertEq(o3.io.Clicks(), 0, "never clicked under a purchase prompt")
}

Test_Obby_DailyRewardsThatWillNotCloseStopsTheSwap() {
    o := QmObbyTask("Glock")
    o.s.daily := true, o.s.dailyDrop := 99
    sw := o.t.PutOnSailor(SchedCtx())
    AssertTrue(!sw.ok && InStr(sw.why, "Daily Rewards"), "refused, says why")
    AssertEq(QmClicksAt(o.io, "1890,527"), Input.DailyTries, "its X DailyTries times")
    AssertEq(QmClicksAt(o.io, "10,10"), 0, "the storage never opened under it")
    o2 := QmObbyTask("Glock")
    o2.s.daily := true, o2.s.dailyDrop := 99
    AssertEq(o2.t.ClearView(SchedCtx()), "daily rewards", "still up")
    AssertEq(QmClicksAt(o2.io, "1890,527"), Input.DailyTries, "no more than DailyTries clicks")
}

Test_Obby_DailyRewardsNeverClickedUnderAPrompt() {
    o := QmObbyTask("Glock")
    o.s.daily := true, o.s.prompt := true, o.s.promptStuck := true
    AssertEq(Input.CloseDaily(SchedCtx(), o.io, (x, y, w, h) => o.s.Ocr(x, y, w, h)), 2, "refused")
    AssertEq(o.io.Clicks(), 0, "no click")
}

Test_Obby_StorageThatWillNotCloseIsReported() {
    o := QmObbyTask("Glock")
    o.s.openAtStart := true, o.s.closeDrop := 99
    AssertEq(o.t.ClearView(SchedCtx()), "storage", "still up")
    AssertEq(QmClicksAt(o.io, "400,400"), ObbyTask.CloseTries, "the X CloseTries times")
    AssertEq(QmClicksAt(o.io, "10,10"), 0, "no sidebar click while the title reads")
    AssertEq(o.wh.Count("errors"), 1, "reported")
}

; ---- [Auras] equipFirst: the first search result, no name / button reads ----

; QmObbyTask with Auras.equipFirst = on (1) / off (0); every OCR box read
; lands in o.reads ("x,y")
QmObbyEqFirst(initial := "Glock", owned := "", on := 1) {
    o := QmObbyTask(initial, Map("Auras.equipFirst", on), , , owned)
    reads := [], s := o.s
    o.t._env.ocrFn := (x, y, w, h, scale := 1) => (reads.Push(x "," y), s.Ocr(x, y, w, h))
    o.reads := reads
    return o
}

; reads of the name panel / the button / the info lines (from aura_equip 300,300)
QmObbyAuraReads(reads) {
    n := ObbyTask.NameBox, b := ObbyTask.ButtonBox, i := ObbyTask.InfoBox
    boxes := Map((300 + n.dx) "," (300 + n.dy), 1, (300 + b.dx) "," (300 + b.dy), 1, (300 + i.dx) "," (300 + i.dy), 1)
    k := 0
    for r in reads
        k += boxes.Has(r) ? 1 : 0
    return k
}

Test_Obby_EquipFirstClicksTheFirstTileThenEquipWithoutReads() {
    o := QmObbyEqFirst("Glock")
    o.s.logo := ["Sailor", "Glock"]              ; names unreadable: no matter
    sw := o.t.PutOnSailor(SchedCtx())
    AssertTrue(sw.ok, "Sailor on")
    AssertTrue(!sw.had, "was not on")
    AssertEq(sw.prev, "Glock", "Glock to put back")
    AssertEq(o.s.State().eq, "Sailor", "Sailor worn")
    iTile := QmObbyFirst(o.io, "move 200,125"), iEq := QmObbyFirst(o.io, "move 300,300")
    AssertTrue(iTile > 0 && iTile < iEq, "the first result tile clicked, then Equip")
    AssertEq(QmClicksAt(o.io, "300,300"), 1, "Equip clicked once")
    AssertTrue(QmObbyLast(o.io, "move 400,400") > iEq, "then the X")
    AssertTrue(!o.s.State().open, "storage closed")
    AssertEq(QmObbyAuraReads(o.reads), 0, "no name / button read")
    ; the put back: the same mode
    AssertTrue(o.t.PutBack(SchedCtx(), sw), "put back")
    AssertEq(o.s.State().eq, "Glock", "Glock equipped again")
    AssertTrue(!o.s.State().open, "storage closed again")
    AssertEq(QmObbyAuraReads(o.reads), 0, "still no name / button read")
    AssertEq(o.wh.Count("errors"), 0, "no error")
}

Test_Obby_EquipFirstRunsTheObbyAndUnequipsAfter() {
    o := QmObbyEqFirst("")
    AssertEq(o.t.Run(SchedCtx()), 1, "blessing seen")
    AssertTrue(QmObbyFirst(o.io, "move 300,300") < QmObbyFirst(o.io, "down w"), "Sailor equipped before the route")
    AssertEq(QmClicksAt(o.io, "300,300"), 2, "Equip, then Unequip after (the same spot)")
    AssertEq(o.s.State().eq, "", "Sailor off again: no aura, as before")
    AssertEq(QmObbyAuraReads(o.reads), 0, "no name / button read")
    AssertEq(o.wh.Count("errors"), 0, "no error")
}

Test_Obby_EquipFirstTakesWhatTheSearchListsFirst() {
    ; on: whatever the search lists first goes on (the user's choice);
    ; off: unchanged, the names are read and plain Sailor is found
    owned := ["Sailor: Admiral", "Sailor", "Glock"]
    o := QmObbyEqFirst("Glock", owned)
    AssertTrue(o.t.PutOnSailor(SchedCtx()).ok, "on: swapped")
    AssertEq(o.s.State().eq, "Sailor: Admiral", "on: the first result equipped")
    AssertEq(QmObbyAuraReads(o.reads), 0, "on: no name / button read")
    off := QmObbyEqFirst("Glock", owned, 0)
    AssertTrue(off.t.PutOnSailor(SchedCtx()).ok, "off: swapped")
    AssertEq(off.s.State().eq, "Sailor", "off: plain Sailor, found by its name")
    AssertTrue(QmObbyAuraReads(off.reads) > 0, "off: the name and button are read as before")
    AssertTrue(!off.s.State().open, "off: storage closed")
}

Test_Obby_EquipFirstAuraOnAlreadyOpensNothing() {
    ; an Equip click would take it off: the log says it is on, nothing done
    o := QmObbyEqFirst("Sailor")
    sw := o.t.PutOnSailor(SchedCtx())
    AssertTrue(sw.ok && sw.had, "already on")
    AssertEq(o.io.Clicks(), 0, "nothing clicked")
    AssertEq(o.s.State().eq, "Sailor", "Sailor kept")
    AssertTrue(o.t.PutBack(SchedCtx(), sw), "nothing to put back")
    AssertEq(o.io.Clicks(), 0, "still nothing clicked")
}

Test_Obby_EquipFirstNoResultClicksNoTileNorEquip() {
    o := QmObbyEqFirst("Glock", ["Glock"])
    sw := o.t.PutOnSailor(SchedCtx())
    AssertTrue(!sw.ok, "no Sailor owned")
    AssertTrue(InStr(sw.why, "no result tile"), "says why")
    AssertEq(QmClicksAt(o.io, "300,300"), 0, "Equip never clicked")
    AssertEq(QmClicksAt(o.io, "200,125"), 0, "the empty first slot never clicked")
    AssertTrue(!o.s.State().prompt, "no click through into the world")
    AssertEq(QmCountMoves(o.io, "move 567,-25"), ObbyTask.SearchTries // 2, "the Special tab tried too")
    AssertTrue(!o.s.State().open, "storage closed")
    AssertEq(o.s.State().eq, "Glock", "aura unchanged")
}

Test_Obby_EquipFirstStorageNotOpenNothingClicked() {
    o := QmObbyEqFirst("Glock")
    o.s.closed := true
    AssertTrue(!o.t.PutOnSailor(SchedCtx()).ok, "not swapped")
    AssertEq(QmClicksAt(o.io, "200,125"), 0, "no tile clicked")
    AssertEq(QmClicksAt(o.io, "300,300"), 0, "Equip never clicked")
    AssertEq(QmObbyFirst(o.io, "type S"), 0, "nothing typed")
}

; 16:10 at 1440x900 (live 2026-11-11): plain Sailor read 'Sanor'
Test_Obby_NameReadTwoLettersOffAShortName() {
    AssertEq(ObbyTask.NameRead("Sanor", "Sailor"), "same", "Sanor = Sailor (2 letters off)")
    AssertEq(ObbyTask.NameRead("Sailor: Admiral", "Sailor"), "other", "the colon still means another aura")
    AssertEq(ObbyTask.NameRead("Sa", "Sailor"), "unread", "too short to tell")
    AssertTrue(ObbyTask.NameRead("Eden", "Sailor") != "same", "another name is never Sailor")
}

; 1366x768 (live 2026-11-11): 'Sanor' is one letter off Solar too, so the
; known-name guard refused it; a Sailor search lists only names holding
; "Sailor", so only those can be the other aura on screen
Test_Obby_NameReadSanorWithSolarKnown() {
    old := ObbyTask.Known
    try {
        m := Map()
        for n in ["Sailor", "Solar", "Sailor: Admiral", "Sailor: Flying Dutchman", "Eden"]
            m[GameLists.Fold(n)] := true
        ObbyTask.Known := m
        AssertEq(ObbyTask.NameRead("Sanor", "Sailor"), "same", "Solar cannot be in a Sailor search")
        AssertEq(ObbyTask.NameRead("Sailor: Admiral", "Sailor"), "other", "the Admiral is still another aura")
        AssertTrue(ObbyTask.NameRead("Solar", "Sailor") != "same", "a clean Solar read is not Sailor")
    } finally ObbyTask.Known := old
}

; 1600x900 (live 2026-11-11): the rarity "1 in 100,000" on the name's line
; read 'npoo,ooo' and Sailor was taken for another aura
Test_Obby_NameReadRarityOnTheSameLine() {
    AssertEq(ObbyTask.NameRead("Sailor npoo,ooo", "Sailor"), "same", "rarity cut off")
    AssertEq(ObbyTask.NameRead("Sailor`nnpoo,ooo", "Sailor"), "same", "rarity on its own line (live, two lines)")
    AssertEq(ObbyTask.NameRead("Sailor`nupoo,ooo", "Sailor"), "same", "and upoo")
    AssertEq(ObbyTask.NameRead("Sailor 12poopoo", "Sailor"), "same", "digits, no comma (live 2560x1440)")
    AssertEq(ObbyTask.NameRead("Sailor npoopoo", "Sailor"), "same", "no digit, no comma (live 2560x1440)")
    AssertEq(ObbyTask.NameVerdict(["Sailor", "Sailor in", "Sailor in '2,000`""], "Sailor"), "same", "a bare 'in' left of the rarity (live 2560x1440)")
    AssertEq(ObbyTask.NameVerdict(["Sailor 12poopoo", "Sailor in 12,ooopoa", "Sailor"], "Sailor"), "same", "live 11:48:57 triple")
    AssertEq(ObbyTask.NameVerdict(["Sailor", "Sailor npoopoo", "Sailor"], "Sailor"), "same", "one scale with the rarity no longer vetoes")
    AssertEq(ObbyTask.NameRead("Poseidon", "Poseidon"), "same", "a real name with po is kept")
    AssertTrue(ObbyTask.NameRead("Sailor: Admiral 12poopoo", "Sailor") = "other", "the Admiral with its rarity")
    AssertEq(ObbyTask.NameRead("Sailor 1 in 100,000", "Sailor"), "same", "rarity with digits")
    AssertEq(ObbyTask.NameRead("Sailor : Flying Putchman", "Sailor"), "other", "the Dutchman is still another aura")
    AssertEq(ObbyTask.NameRead("Sailor: Admiral npoo,ooo", "Sailor"), "other", "the Admiral too")
}

; 2560x1440 (live 2026-11-11 11:10): no tile read as Sailor, the log pick put
; on Sailor: Admiral, the swap failed and the obby skipped with the Admiral
; still on (the player's Eden lost until the next hunt). A failed swap that
; left another aura on puts the one from before back.
Test_Obby_FailedSwapPutsTheAuraBack() {
    o := QmObbyTask("Glock")
    calls := []
    o.t.DefineProp("PutOnSailor", {Call: (this, ctx) => (o.s.logName := "Celestial", {ok: false, had: false, prev: "Glock", unknown: false, why: "no Sailor"})})
    o.t.DefineProp("PutBack", {Call: (this, ctx, info) => (calls.Push(info.prev), true)})
    o.t.Run(SchedCtx())
    AssertEq(calls.Length, 1, "put back once")
    AssertEq(calls.Length ? calls[1] : "", "Glock", "the aura from before")
    AssertTrue(QmObbyLogHas(o.logs, "put back"), "logged")
    ; nothing changed: no put-back
    o2 := QmObbyTask("Glock")
    calls2 := []
    o2.t.DefineProp("PutOnSailor", {Call: (this, ctx) => {ok: false, had: false, prev: "Glock", unknown: false, why: "no Sailor"}})
    o2.t.DefineProp("PutBack", {Call: (this, ctx, info) => (calls2.Push(info.prev), true)})
    o2.t.Run(SchedCtx())
    AssertEq(calls2.Length, 0, "Glock still on: nothing to put back")
}
