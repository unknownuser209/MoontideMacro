#Requires AutoHotkey v2.0
; Tests for lib\QuestMatch.ahk, lib\ChatWatch.ahk, lib\tasks\Quests.ahk and
; lib\tasks\Merchant.ahk. Offline: fake IO, calibration, OCR, clock, webhook.
#Include ..\lib\Json.ahk
#Include ..\lib\QuestMatch.ahk
#Include ..\lib\ChatWatch.ahk
#Include ..\lib\tasks\Quests.ahk
#Include ..\lib\tasks\Merchant.ahk

; ---- helpers (names must not start with Test_) -----------------------------

; Recording IO: never sleeps, never touches the screen.
class QmIO {
    __New() {
        this.log := []
    }
    Down(k) => this.log.Push("down " k)
    Up(k) => this.log.Push("up " k)
    MoveTo(x, y) => this.log.Push("move " x "," y)
    Look(dx, dy) => this.log.Push("look " dx "," dy)
    ClickHere() => this.log.Push("click")
    Type(t) => this.log.Push("type " t)
    Wait(ms, ctx := "") => !(IsObject(ctx) && ctx.ShouldStop())
    Index(entry) {
        for i, e in this.log
            if (e = entry)
                return i
        return 0
    }
    Clicks() {
        n := 0
        for e in this.log
            n += (e = "click") ? 1 : 0
        return n
    }
    Moved(x, y) {
        for e in this.log
            if (e = "move " x "," y)
                return true
        return false
    }
    ; The merchant fakes' inventory: open after an odd number of clicks on
    ; inv_open (QmMerchCal: 100,100).
    InvOpen() => Mod(QmCountMoves(this, "move 100,100"), 2) = 1
}

; Calibration fake: points Map id -> {x,y,color}, rects Map id -> {x,y,w,h}.
class QmCal {
    __New(points := "", rects := "") {
        this.p := points is Map ? points : Map()
        this.r := rects is Map ? rects : Map()
    }
    Point(id) => this.p.Has(id) ? this.p[id] : ""
    Rect(id) => this.r.Has(id) ? this.r[id] : ""
}

class QmWh {
    __New() {
        this.sent := []
    }
    Send(event, title, desc, color, opts := "") {
        this.sent.Push({event: event, title: title, desc: desc})
    }
    Count(event) {
        n := 0
        for s in this.sent
            n += (s.event = event) ? 1 : 0
        return n
    }
}

class QmCfg {
    __New(gets := "", data := "") {
        this.g := gets is Map ? gets : Map()
        this.d := data is Map ? data : Map()
    }
    Get(path, default := "") => this.g.Has(path) ? this.g[path] : default
    Data(name) => this.d.Has(name) ? this.d[name] : Map()
}

class QmClock {
    __New(t := 0) {
        this.t := t
    }
    Now() => this.t
}

; OCR fake: returns texts in order, repeating the last one.
; Board OCR fake. Reads of the board rect (QmBoardCal: 1000,300,400,500)
; walk `texts`; the first one (the "did the board open" check after E)
; does not advance. Any other rect returns other["x,y,w,h"] or "" (e.g. the
; Accept/Claim button box or notify_rect).
class QmOcr {
    __New(texts, other := "", board := "") {
        this.texts := texts
        this.i := 0
        this.rects := []
        this.other := (other is Map) ? other : Map()
        this.opened := (board = "")         ; no board rect: every read walks texts
        this.board := board
    }
    Read(x, y, w, h) {
        r := x "," y "," w "," h
        this.rects.Push(r)
        if (this.board != "" && r != this.board)
            return this.other.Has(r) ? this.other[r] : ""
        if !this.opened {
            this.opened := true
            return this.texts.Length ? this.texts[1] : ""
        }
        this.i := Min(this.i + 1, this.texts.Length)
        return this.texts[this.i]
    }
}

QmBoardOcr(texts, other := "") => QmOcr(texts, other, "1000,300,400,500")

QmQuestsCfg() {
    q := (n, on := 1) => Map("name", n, "enabled", on)
    return Map("types", [
        Map("name", "Delivery", "enabled", 1, "quests", [q("Delivery I"), q("Delivery II"), q("Delivery IV")]),
        Map("name", "Aura Hunt", "enabled", 1, "quests", [q("Basic Aura Hunt"), q("Mythic Aura Hunt", 0)]),
        Map("name", "Fishing", "enabled", 0, "quests", [q("Deep-Sea Hunter"), q("River Angler")]),
        Map("name", "Resonance", "enabled", 1, "quests", [q("Resonance")])
    ])
}

QmBoardCal() {
    return QmCal(Map(
        "quest_accept", {x: 100, y: 200, color: 0x00FF00},
        "quest_dismiss", {x: 300, y: 400, color: 0xFF0000},
        "quest_close", {x: 700, y: 800, color: 0x0000FF},
        "quest_next", {x: 900, y: 950, color: 0x000000}
    ), Map("quest_board_rect", {x: 1000, y: 300, w: 400, h: 500}, "notify_rect", {x: 1, y: 2, w: 30, h: 40}))
}

QmRoutesData() {
    return Map("routes", Map(
        "quest_board", [["w", "down", 100], ["w", "up", 0]],
        "mari", [["w", "down", 100], ["w", "up", 0]],
        "jester", [["a", "down", 100], ["a", "up", 0]]
    ))
}

; ---- QuestMatch ------------------------------------------------------------

Test_QuestMatch_ExactAndFuzzy() {
    cfg := QmQuestsCfg()
    m := QuestMatch.Match("Quest: Basic Aura Hunt`nRoll 5 auras", cfg)
    AssertEq(m.name, "Basic Aura Hunt", "exact name found in noisy text")
    AssertEq(m.enabled, true, "enabled")
    ; case and punctuation do not matter
    AssertEq(QuestMatch.Match("RESONANCE!!", cfg).name, "Resonance", "case/punct")
    ; longest name wins: "Delivery II" text also contains the words of "Delivery I"
    AssertEq(QuestMatch.Match("Delivery II", cfg).name, "Delivery II", "longest wins II")
    AssertEq(QuestMatch.Match("Delivery I", cfg).name, "Delivery I", "I alone")
    AssertEq(QuestMatch.Match("Delivery IV", cfg).name, "Delivery IV", "IV")
    ; whole words: a longer token does not match the shorter name
    AssertEq(QuestMatch.Match("Delivery IIII", cfg), "", "IIII is not II")
    ; fuzzy: OCR typos
    AssertEq(QuestMatch.Match("Basic Aura Hnnt", cfg).name, "Basic Aura Hunt", "fuzzy typo")
    AssertEq(QuestMatch.Match("Reson4nce", cfg).name, "Resonance", "fuzzy digit")
    AssertEq(QuestMatch.Match("Deep Sea Hunter", cfg).name, "Deep-Sea Hunter", "hyphen normalised")
    ; ambiguous fuzzy ("Delivery Il" is one edit from both I and II) -> unknown
    AssertEq(QuestMatch.Match("Delivery Il", cfg), "", "ambiguous fuzzy is unknown")
    ; no match / empty
    AssertEq(QuestMatch.Match("Collect seven sticks", cfg), "", "no match")
    AssertEq(QuestMatch.Match("", cfg), "", "empty text")
    AssertEq(QuestMatch.Match("Resonance", Map()), "", "empty config")
    AssertEq(QuestMatch.IsComplete("Resonance - Completed"), true, "completed words")
    AssertEq(QuestMatch.IsComplete("Resonance - Roll 5 auras"), false, "not completed")
}

Test_QuestMatch_DisabledIsDenied() {
    cfg := QmQuestsCfg()
    m := QuestMatch.Match("Mythic Aura Hunt", cfg)
    AssertEq(m.name, "Mythic Aura Hunt", "disabled quest still matched")
    AssertEq(m.enabled, false, "quest disabled -> denied")
    ; whole type disabled -> every quest in it denied even if the quest is on
    m := QuestMatch.Match("River Angler", cfg)
    AssertEq(m.enabled, false, "type disabled -> denied")
    ; fuzzy match of a disabled quest is also denied
    AssertEq(QuestMatch.Match("Mythic Aurq Hunt", cfg).enabled, false, "fuzzy disabled denied")
    ; true/false forms from JSON-ish data
    cfg2 := Map("types", [Map("name", "T", "enabled", true, "quests", [Map("name", "Lucky Clover", "enabled", false)])])
    AssertEq(QuestMatch.Match("Lucky Clover", cfg2).enabled, false, "false bool denied")
}

; ---- ChatWatch -------------------------------------------------------------

Test_ChatWatch_DetectsMariAndJester() {
    AssertEq(ChatWatch.Detect("[Server]: Mari has arrived!").Length, 1, "mari one")
    AssertEq(ChatWatch.Detect("[Server]: Mari has arrived!")[1], "Mari", "mari name")
    AssertEq(ChatWatch.Detect("The Jester appeared nearby")[1], "Jester", "jester name")
    both := ChatWatch.Detect("Mari has arrived`nJester has arrived")
    AssertEq(both.Length, 2, "both on separate lines")
    AssertEq(ChatWatch.Detect("hello world").Length, 0, "no merchant")
    AssertEq(ChatWatch.Detect("Mari is my cat").Length, 0, "name without arrival word")
    AssertEq(ChatWatch.Detect("mari has arrived").Length, 0, "case-sensitive name")
    AssertEq(ChatWatch.Detect("").Length, 0, "empty")

    clock := QmClock(1000)
    io := QmIO()
    ocr := QmOcr(["Mari has arrived", "Mari has arrived", "Jester has arrived", "just chatting", "Mari has arrived", ""])
    found := []
    cw := ChatWatch({
        cfg: QmCfg(Map("merchant.chatPollSec", 5)),
        io: io,
        cal: QmCal(, Map("chat_rect", {x: 10, y: 20, w: 400, h: 200})),
        ocr: (x, y, w, h, scale := 1) => ocr.Read(x, y, w, h),
        now: () => clock.Now(),
        onFound: (n) => found.Push(n)
    })
    hits := cw.Check()
    AssertEq(hits.Length, 1, "first read finds Mari")
    AssertEq(hits[1], "Mari", "Mari")
    AssertTrue(io.Moved(210, 120), "hovered rect center")
    AssertEq(io.Clicks(), 0, "hover only: never clicks")
    AssertEq(ocr.rects[1], "10,20,400,200", "ocr on the chat rect")
    ; polled again too soon: no read at all
    clock.t := 3000
    AssertEq(cw.Check().Length, 0, "inside poll interval")
    AssertEq(ocr.i, 1, "no OCR inside poll interval")
    ; after 5 s: Mari again, within 120 s -> deduped
    clock.t := 7000
    AssertEq(cw.Check().Length, 0, "same merchant deduped")
    AssertEq(ocr.i, 2, "but chat was read")
    ; Jester is a different merchant
    clock.t := 13000
    h := cw.Check()
    AssertEq(h.Length, 1, "jester new")
    AssertEq(h[1], "Jester", "jester")
    ; a second read without Mari (absent from 2 reads in a row now)
    clock.t := 20000
    AssertEq(cw.Check().Length, 0, "chat without a merchant")
    ; Mari again, last sighting was at 7000 -> must be absent >= 120 s
    clock.t := 128000
    h := cw.Check()
    AssertEq(h.Length, 1, "mari re-reported after dedupe window")
    ; OCR failure ("") = unknown
    clock.t := 140000
    AssertEq(cw.Check().Length, 0, "empty OCR is unknown")
    AssertEq(found.Length, 3, "onFound called per hit")
    AssertEq(io.Clicks(), 0, "still no clicks")
    for e in io.log
        AssertTrue(!InStr(e, "down") && !InStr(e, "up"), "never types or presses keys")
}

Test_ChatWatch_SlidingDedupe() {
    clock := QmClock(0)
    io := QmIO()
    text := "Mari has arrived"
    cw := ChatWatch({
        io: io,
        cal: QmCal(, Map("chat_rect", {x: 10, y: 20, w: 400, h: 200})),
        ocr: (*) => text,
        now: () => clock.Now()
    })
    triggers := 0
    ; line stays visible (hover keeps chat from fading) for 300 s of 5 s polls
    Loop 61 {
        clock.t := (A_Index - 1) * 5000
        triggers += cw.Check().Length
    }
    AssertEq(triggers, 1, "visible > 120 s: still one trigger")
    ; line gone for 121 s (last sighting at 300000)
    text := "just chatting"
    t := 300000
    while (t < 300000 + 121000) {
        t += 5000
        clock.t := t
        triggers += cw.Check().Length
    }
    AssertEq(triggers, 1, "absent: no trigger")
    text := "Mari has arrived"
    clock.t := t + 5000
    triggers += cw.Check().Length
    AssertEq(triggers, 2, "back after >= 120 s absence: second trigger")
    ; reappearing sooner than 120 s after the last sighting stays suppressed
    text := "x"
    clock.t += 5000
    cw.Check()
    text := "Mari has arrived"
    clock.t += 5000
    AssertEq(cw.Check().Length, 0, "short absence: suppressed")
    AssertEq(io.Clicks(), 0, "never clicks")
}

; IO that logs waits too (shared log with the OCR fake).
class QmWaitIO extends QmIO {
    Wait(ms, ctx := "") => (this.log.Push("wait " ms), true)
}

Test_ChatWatch_WaitsAfterHoverBeforeOcr() {
    io := QmWaitIO()
    cw := ChatWatch({
        io: io,
        cal: QmCal(, Map("chat_rect", {x: 10, y: 20, w: 400, h: 200})),
        ocr: (*) => (io.log.Push("ocr"), "Mari has arrived"),
        now: () => 0
    })
    cw.Check()
    AssertEq(io.log.Length, 3, "move, wait, ocr")
    AssertEq(io.log[1], "move 210,120", "hover first")
    AssertEq(io.log[2], "wait 150", "default 150 ms so the chat background is back")
    AssertEq(io.log[3], "ocr", "OCR after the wait")
    ; configurable
    io2 := QmWaitIO()
    cw2 := ChatWatch({
        io: io2, cfg: QmCfg(Map("merchant.chatHoverMs", 300)),
        cal: QmCal(, Map("chat_rect", {x: 10, y: 20, w: 400, h: 200})),
        ocr: (*) => (io2.log.Push("ocr"), ""),
        now: () => 0
    })
    cw2.Check()
    AssertEq(io2.log[2], "wait 300", "merchant.chatHoverMs")
}

Test_ChatWatch_MissingCalibrationDoesNothing() {
    io := QmIO()
    wh := QmWh()
    called := 0
    cw := ChatWatch({
        io: io, webhook: wh, cal: QmCal(),
        ocr: (*) => (called++, "Mari has arrived"),
        now: () => 1000
    })
    AssertEq(cw.Check().Length, 0, "no chat_rect -> nothing")
    AssertEq(called, 0, "no OCR without a rect")
    AssertEq(io.log.Length, 0, "no mouse movement")
    AssertEq(wh.Count("errors"), 1, "one errors webhook")
    ; polling many times: logged once, webhook once
    logs := []
    cw2 := ChatWatch({io: io, webhook: wh, cal: QmCal(), log: (s) => logs.Push(s), now: () => 0})
    cw2.Check()
    AssertEq(logs.Length, 1, "first poll logs the missing rect")
    t := 0
    cw3 := ChatWatch({io: io, webhook: wh, cal: QmCal(), log: (s) => logs.Push(s), now: () => (t += 6000)})
    Loop 10
        cw3.Check()
    AssertEq(logs.Length, 2, "ten polls log once, not ten times")
}

Test_QuestMatch_DefaultsKnowTheBoardQuests() {
    ; quests seen on the 2026-10-26 board must match an entry in the default list
    q := Config._DefQuests()
    for pair in [["Meditation I`n*`nPlay the game for 10 minutes", "Meditation I"]
            , ["Meditation II`nPlay for 30 minutes", "Meditation II"]
            , ["Windy Breakthrough`n***", "Breakthroughs"]
            , ["Resonance of Flome", "Resonance"]] {
        m := QuestMatch.Match(pair[1], q)
        AssertTrue(IsObject(m), pair[2] " matched")
        AssertEq(IsObject(m) ? m.name : "", pair[2], "right entry for " pair[2])
    }
}

; ---- QuestsTask ------------------------------------------------------------

; Fake quest board, like the 2026 UI: a carousel showing one quest. Accept
; (100,200) turns the button into "Accepted" and stays; on a "Claim Rewards"
; button it claims and removes the quest. Dismiss (300,400) removes the quest
; and shows the next one. > (900,950) moves on (wraps when wrap = true).
; OCR: the panel (QmBoardCal rect grown by QuestsTask.TitleUp) shows the
; current quest's text, the box around Accept its button word.
class QmBoard {
    __New(quests, wrap := true) {
        this.q := []
        for e in quests
            this.q.Push({text: e[1], button: e.Length > 1 ? e[2] : "Accept"})
        this.wrap := wrap
        this.i := 1
        this.notify := ""
        this.panel := "1000,170,400,630"
        this.btn := "-20,170,240,60"
        this.nexts := 0
        this.noise := false      ; true: every panel read ends in different junk (stars / objectives OCR)
        this.keepAccept := false ; true: the button still says "Accept" after accepting
        this.reads := 0
        this.accepts := Map()    ; title -> times Accept was clicked on it
        this.onClick := ""       ; (x, y) => ..., called on every click
        this.exit := "580,770,240,60"   ; the Exit button's word, around quest_close 700,800
        this.closed := false     ; Exit clicked (or the board went away): nothing reads
        this.promptOnExit := false   ; the Exit click opens a Roblox purchase prompt
        this.prompt := false     ; that prompt is up (Esc closes it)
        this.toast := 0          ; button reads left covered (the game's "Potion Auto Added" toast)
        this.cards := ""         ; QuestsTask dep "cards": closes a catch card, -> true closed
    }
    Cur() => (this.q.Length ? this.q[this.i] : "")
    Click(x, y) {
        if IsObject(this.onClick)
            this.onClick.Call(x, y)
        if (x = 700 && y = 800) {
            this.closed := true
            this.prompt := this.promptOnExit
            return
        }
        c := this.Cur()
        if !IsObject(c)
            return
        if (x = 100 && y = 200) {
            if RegExMatch(c.button, "i)c[lI][ao]im") {      ; also the game font's "Cloim Rewords"
                this.q.RemoveAt(this.i)
                this._Clamp()
            } else {
                t := StrSplit(c.text, "`n")[1]
                this.accepts[t] := (this.accepts.Has(t) ? this.accepts[t] : 0) + 1
                if !this.keepAccept
                    c.button := "Accepted"
            }
        } else if (x = 300 && y = 400) {
            this.q.RemoveAt(this.i)
            this._Clamp()
        } else if (x = 900 && y = 950) {
            this.nexts++
            if (this.i < this.q.Length)
                this.i++
            else if this.wrap
                this.i := 1
        }
    }
    _Clamp() {
        if (this.i > this.q.Length)
            this.i := this.wrap ? 1 : Max(1, this.q.Length)
    }
    Read(x, y, w, h) {
        r := x "," y "," w "," h
        pb := Input.PurchaseBox
        if (x = pb.x && y = pb.y)
            return this.prompt ? "Buy Robux and item`nR$1,000 Donation`nBuy $4.99" : ""
        if this.closed
            return ""
        if (r = this.exit)
            return "Exit"
        c := this.Cur()
        if (r = this.panel) {
            this.reads++
            return IsObject(c) ? c.text (this.noise ? "`n" Chr(65 + Mod(this.reads, 26)) "x*" this.reads : "") : ""
        }
        if (r = this.btn) {
            this.btnReads := (this.HasOwnProp("btnReads") ? this.btnReads : 0) + 1
            if (this.toast > 0) {
                this.toast--
                return ""
            }
            return IsObject(c) ? c.button : ""
        }
        if (r = "1,2,30,40")
            return this.notify
        return ""
    }
}

class QmBoardIO extends QmIO {
    __New(board) {
        super.__New()
        this.board := board
        this.x := 0, this.y := 0
    }
    MoveTo(x, y) {
        this.x := x, this.y := y
        super.MoveTo(x, y)
    }
    ClickHere() {
        super.ClickHere()
        this.board.Click(this.x, this.y)
    }
    Down(k) {
        super.Down(k)
        if (k = "Esc")
            this.board.prompt := false
        if (k = "e" && this.board.HasOwnProp("opensOnE") && --this.board.opensOnE = 0)
            this.board.closed := false      ; the board opens on this E (an earlier walk missed it)
    }
}

QmBoardTask(board, gets := "", cal := "", logs := "") {
    io := QmBoardIO(board)
    wh := QmWh()
    lg := (logs is Array) ? logs : []
    t := QuestsTask({
        cfg: QmCfg(gets, Map("quests", QmQuestsCfg(), "routes", QmRoutesData())),
        io: io, webhook: wh, cal: IsObject(cal) ? cal : QmBoardCal(), log: (s) => lg.Push(s),
        ocr: (x, y, w, h, scale := 1) => board.Read(x, y, w, h),
        cards: IsObject(board.cards) ? board.cards : "",
        ink: (x, y, w, h, scale := 1, ink := 0) => (board.HasOwnProp("green") ? board.green : "")
    })
    return {t: t, io: io, wh: wh, logs: lg, board: board}
}

Test_Quests_MissingCalibrationSkipsWithoutClicking() {
    io := QmIO()
    wh := QmWh()
    logs := []
    t := QuestsTask({
        cfg: QmCfg(, Map("quests", QmQuestsCfg(), "routes", QmRoutesData())),
        io: io, webhook: wh, cal: QmCal(), log: (s) => logs.Push(s),
        ocr: (*) => "Resonance"
    })
    AssertEq(t.name, "quests", "name")
    AssertEq(t.priority, 5, "priority")
    AssertEq(t.CanRun(SchedState()), false, "board not calibrated -> not eligible (never interrupts sell/fishing)")
    AssertEq(t.Run(SchedCtx()), 0, "no actions")
    AssertEq(io.log.Length, 0, "no key, move or click at all")
    AssertEq(wh.Count("errors"), 1, "errors webhook once")
    t.Run(SchedCtx())
    AssertEq(wh.Count("errors"), 1, "errors webhook not repeated")
    AssertEq(logs.Length, 1, "missing step logged once, not on every run")
    ; board rect present but route missing: still no input
    wh2 := QmWh()
    io2 := QmIO()
    t2 := QuestsTask({
        cfg: QmCfg(, Map("quests", QmQuestsCfg())),
        io: io2, webhook: wh2, cal: QmBoardCal(), ocr: (*) => "Resonance"
    })
    AssertEq(t2.CanRun(SchedState()), false, "route missing -> not eligible")
    AssertEq(t2.Run(SchedCtx()), 0, "route missing -> skip")
    AssertEq(io2.log.Length, 0, "no input without route")
    AssertEq(wh2.Count("errors"), 1, "route missing reported")
}

Test_Quests_CarouselHandlesEveryQuest() {
    ; the user's board: 5 quests; Dismiss moves on by itself, Accept stays (> moves on)
    board := QmBoard([
        ["Resonance`n***`nObjects`nReach resonance"],             ; ticked -> accept, then >
        ["Mythic Aura Hunt`n***`nRoll a Mythic aura"],            ; unticked -> dismiss (moves on)
        ["Delivery II`n**`nBring 3 crates"],                       ; ticked -> accept, then >
        ["Deep-Sea Hunter`n*`nCatch 5 fish"],                      ; unticked -> dismiss
        ["Basic Aura Hunt`n*`nRoll 10 auras", "Claim Rewards"]    ; finished -> claim
    ])
    m := QmBoardTask(board, Map("quests.dismissDisabled", 1))
    AssertEq(m.t.CanRun(SchedState()), true, "eligible")
    n := m.t.Run(SchedCtx())
    AssertEq(n, 5, "every quest on the board handled")
    d := m.wh.sent[1].desc
    for want in ["accepted Resonance", "dismissed Mythic Aura Hunt", "accepted Delivery II", "dismissed Deep-Sea Hunter", "claimed rewards for Basic Aura Hunt"]
        AssertTrue(InStr(d, want), "summary: " want)
    AssertEq(board.q.Length, 2, "the two accepted quests stay on the board")
    AssertEq(board.q[1].button, "Accepted", "Resonance accepted")
    AssertTrue(board.nexts >= 2, "> pressed after each Accept")
    AssertTrue(m.io.Moved(700, 800), "board exited at the end")
    AssertEq(m.wh.Count("quests"), 1, "one quests webhook")
    AssertEq(m.wh.Count("errors"), 0, "no errors")
}

Test_Quests_NoisyOcrNeverRepeatsAnAccept() {
    ; the 2026-10-26 in-game run: the stars / objective text OCR differently
    ; on every read and the button may still read "Accept" -> the old pass
    ; accepted the same quest 12 times. A quest is now known by its title.
    board := QmBoard([["Delivery I`n***`nObjects"], ["Basic Aura Hunt`n*`nObjects"], ["Resonance`n**`nObjects"]], true)
    board.noise := true
    board.keepAccept := true
    m := QmBoardTask(board)
    AssertEq(m.t.Run(SchedCtx()), 3, "three quests, three accepts")
    for title, n in board.accepts
        AssertEq(n, 1, title " accepted exactly once")
    AssertEq(board.accepts.Count, 3, "every quest reached")
    AssertTrue(board.nexts <= 4, "> pressed about once per quest, not in a loop")
    ; the log names every quest it saw
    seenLines := 0
    for l in m.logs
        seenLines += InStr(l, "quests: [") ? 1 : 0
    AssertEq(seenLines, 3, "one 'seen' line per quest")
}

Test_Quests_DisabledLeftAloneByDefault() {
    ; default (quests.dismissDisabled missing / 0): an unticked quest is
    ; left alone, never dismissed (abandoned); the pass still goes on with >
    board := QmBoard([["Mythic Aura Hunt`nRoll a Mythic aura"], ["Delivery II`nBring 3 crates"], ["River Angler`nCatch fish"]])
    m := QmBoardTask(board)
    AssertEq(m.t.Run(SchedCtx()), 1, "only the ticked quest accepted")
    AssertTrue(!m.io.Moved(300, 400), "dismiss NEVER clicked by default")
    AssertTrue(InStr(m.wh.sent[1].desc, "accepted Delivery II"), "Delivery II accepted after paging past Mythic")
    AssertEq(board.q.Length, 3, "nothing removed")
    AssertTrue(InStr(m.logs[1] m.logs[2], "left Mythic Aura Hunt alone"), "skip logged")
    AssertEq(Config.IniDefaults()["Quests"]["dismissDisabled"], "0", "registered in IniDefaults, default 0")
}

Test_Quests_StopsAtTheEndOrAfterGoingRound() {
    ; > does nothing on the last quest (no wrap): the pass ends there
    board := QmBoard([["Delivery I`nBring crates"], ["Delivery II`nBring crates"]], false)
    m := QmBoardTask(board)
    AssertEq(m.t.Run(SchedCtx()), 2, "both accepted")
    AssertTrue(board.nexts <= 2, "no endless > presses at the end")
    ; wrap: back at the first quest = done; nothing handled twice
    board2 := QmBoard([["Delivery I`nBring crates"], ["Mythic Aura Hunt`nRoll"]], true)
    m2 := QmBoardTask(board2)
    AssertEq(m2.t.Run(SchedCtx()), 1, "accepted once, Mythic left alone")
    AssertEq(board2.q[1].button, "Accepted", "accepted")
    AssertTrue(board2.nexts <= 3, "stopped after going round")
    ; already accepted quests (button "Accepted") are left alone
    board3 := QmBoard([["Delivery I`nBring crates", "Accepted"], ["Delivery IV`nBring crates", "Accepted"]])
    m3 := QmBoardTask(board3)
    AssertEq(m3.t.Run(SchedCtx()), 0, "nothing to do")
    AssertTrue(!m3.io.Moved(100, 200), "accept not clicked again")
    ; a quest no name matches: left alone, the rest still handled
    board4 := QmBoard([["Strange Quest`nDo a thing"], ["Delivery I`nBring crates"]])
    m4 := QmBoardTask(board4)
    AssertEq(m4.t.Run(SchedCtx()), 1, "the known quest still accepted")
    AssertTrue(InStr(m4.wh.sent[1].desc, "accepted Delivery I"), "Delivery I")
}

Test_Quests_WithoutNextArrowOnlyTheFirst() {
    cal := QmCal(Map(
        "quest_accept", {x: 100, y: 200, color: 0},
        "quest_dismiss", {x: 300, y: 400, color: 0},
        "quest_close", {x: 700, y: 800, color: 0}
    ), Map("quest_board_rect", {x: 1000, y: 300, w: 400, h: 500}))
    board := QmBoard([["Delivery I`nBring crates"], ["Delivery II`nBring crates"]])
    m := QmBoardTask(board, , cal)
    AssertEq(m.t.Run(SchedCtx()), 1, "first quest only")
    AssertEq(board.nexts, 0, "no arrow to press")
}

Test_Quests_MissingAcceptSkipsOnlyThatAction() {
    ; without quest_accept the button word (read around it) is unknown: it
    ; may be Claim Rewards, so nothing is dismissed blind (2026-10-27 review)
    cal := QmCal(Map("quest_dismiss", {x: 300, y: 400, color: 0xFF0000}, "quest_close", {x: 700, y: 800, color: 0}
        , "quest_next", {x: 900, y: 950, color: 0}), Map("quest_board_rect", {x: 1000, y: 300, w: 400, h: 500}))
    board := QmBoard([["Resonance`nReach it"], ["Mythic Aura Hunt`nRoll"]])
    m := QmBoardTask(board, Map("quests.dismissDisabled", 1), cal)
    AssertEq(m.t.Run(SchedCtx()), 0, "no action without the accept point")
    AssertTrue(!m.io.Moved(300, 400), "dismiss not clicked blind")
    AssertEq(m.wh.Count("errors"), 1, "accept missing reported once")
    AssertEq(board.q.Length, 2, "nothing abandoned")
    AssertTrue(m.io.Moved(700, 800), "board still exited")
}

Test_QuestMatch_CompleteInTheGameFont() {
    ; the game font reads "a" as "o" and l as I (2026-10-27 review)
    for t in ["Cloim Rewords", "CIoim Rewords", "Claim Rewards", "Reody to turn in", "Completed"]
        AssertEq(QuestMatch.IsComplete(t), true, "'" t "' is the turn-in wording")
    for t in ["Roll 5 auras", "Accept", "Dismiss", ""]
        AssertEq(QuestMatch.IsComplete(t), false, "'" t "' is not")
}

Test_Quests_ClaimButtonInTheGameFont() {
    ; "Claim Rewards" reads "Cloim Rewords": before, the word was "" and an
    ; unticked finished quest was DISMISSED (rewards lost; 2026-10-27 review)
    board := QmBoard([["Mythic Aura Hunt`nRoll 1 Mythic aura", "Cloim Rewords"], ["Resonance`nReach it", "CIoim Rewords"]])
    m := QmBoardTask(board, Map("quests.dismissDisabled", 1))
    AssertEq(m.t.Run(SchedCtx()), 2, "two claims")
    d := m.wh.sent[1].desc
    AssertTrue(InStr(d, "claimed rewards for Mythic Aura Hunt"), "the unticked quest claimed, not dismissed")
    AssertTrue(InStr(d, "claimed rewards for Resonance"), "the ticked one reported as claimed, not accepted")
    AssertTrue(!m.io.Moved(300, 400), "dismiss never clicked")
    AssertEq(board.q.Length, 0, "both claimed off the board")
}

Test_Quests_UnreadButtonNeverDismisses() {
    ; the button word did not read at all: never Dismiss (it may be Claim)
    board := QmBoard([["Mythic Aura Hunt`nRoll 1 Mythic aura", ""], ["River Angler`nCatch fish", "Accept"]])
    m := QmBoardTask(board, Map("quests.dismissDisabled", 1))
    AssertEq(m.t.Run(SchedCtx()), 1, "only the readable one dismissed")
    AssertEq(board.q.Length, 1, "the unread quest stays")
    AssertTrue(InStr(board.q[1].text, "Mythic"), "it is Mythic Aura Hunt")
    found := false
    for l in m.logs
        found := found || InStr(l, "never dismissed blind")
    AssertTrue(found, "logged why")
}

; Index of the last io log entry equal to `entry` (0 if none).
QmLast(io, entry) {
    i := io.log.Length
    while (i >= 1) {
        if (io.log[i] = entry)
            return i
        i--
    }
    return 0
}

Test_Quests_PreemptStillClosesTheBoard() {
    ; a higher task becomes due right after an Accept: the board is closed
    ; and the player respawned before it starts (2026-10-27 review)
    board := QmBoard([["Resonance`nReach it"], ["Delivery II`nBring 3 crates"]])
    ctx := SchedCtx()
    board.onClick := (x, y) => (x = 100 && y = 200) ? ctx.RequestPreempt() : 0
    m := QmBoardTask(board)
    AssertEq(m.t.Run(ctx), 1, "the accept before the preempt is reported")
    iClose := QmLast(m.io, "move 700,800")
    AssertTrue(iClose > 0, "board closed")
    AssertTrue(QmLast(m.io, "down Esc") > iClose, "then respawned")
    AssertEq(board.accepts.Has("Delivery II"), false, "no more quests handled after the preempt")
    ; F3 / pause at the same moment: nothing more is sent
    board2 := QmBoard([["Resonance`nReach it"], ["Delivery II`nBring 3 crates"]])
    ctx2 := SchedCtx()
    board2.onClick := (x, y) => (x = 100 && y = 200) ? ctx2.Stop() : 0
    m2 := QmBoardTask(board2)
    m2.t.Run(ctx2)
    iAcc := QmLast(m2.io, "move 100,200")
    AssertEq(QmLast(m2.io, "move 700,800"), 0, "halted: board not touched")
    AssertTrue(QmLast(m2.io, "down Esc") < iAcc, "halted: no respawn")
}

Test_Quests_ClaimButtonWordDecides() {
    ; the Accept and Claim Rewards buttons share one spot: the word on it decides
    board := QmBoard([["Mythic Aura Hunt`nRoll 1 Mythic aura", "Claim Rewards"]])
    m := QmBoardTask(board)
    AssertEq(m.t.Run(SchedCtx()), 1, "one claim")
    AssertTrue(InStr(m.wh.sent[1].desc, "claimed rewards for Mythic Aura Hunt"), "claimed, even though Mythic is unticked")
    AssertTrue(m.io.Moved(100, 200) && !m.io.Moved(300, 400), "claim clicked on the accept spot, dismiss never")
    AssertTrue(m.io.Moved(700, 800), "board exited")
}

Test_Quests_EmptyBoardNotificationClicksNothing() {
    board := QmBoard([])
    board.notify := "There are no quests available right now"
    m := QmBoardTask(board)
    AssertEq(m.t.CanRun(SchedState()), true, "eligible")
    AssertEq(m.t.Run(SchedCtx()), 0, "no actions")
    AssertTrue(!m.io.Moved(100, 200) && !m.io.Moved(300, 400) && !m.io.Moved(700, 800), "no board button clicked (not even exit: the board never opened)")
    AssertTrue(InStr(m.logs[m.logs.Length], "no quests right now"), "logged as an empty board")
    ; board never opens and no notification: says so, still no clicks
    m2 := QmBoardTask(QmBoard([]))
    AssertEq(m2.t.Run(SchedCtx()), 0, "no actions")
    AssertTrue(!m2.io.Moved(100, 200) && !m2.io.Moved(300, 400) && !m2.io.Moved(700, 800), "no board button clicked")
    AssertTrue(InStr(m2.logs[m2.logs.Length], "did not open"), "says the board did not open")
    ; exit button not calibrated: not eligible
    cal := QmCal(Map("quest_accept", {x: 100, y: 200, color: 0}), Map("quest_board_rect", {x: 1000, y: 300, w: 400, h: 500}))
    t3 := QuestsTask({cfg: QmCfg(, Map("quests", QmQuestsCfg(), "routes", QmRoutesData())), io: QmIO(), webhook: QmWh(), cal: cal, ocr: (*) => ""})
    AssertEq(t3.CanRun(SchedState()), false, "no exit button -> not eligible")
}

Test_Quests_PanelIncludesTheTitle() {
    p := QuestsTask.Panel({x: 2024, y: 489, w: 458, h: 326})
    AssertEq(p.y, 489 - QuestsTask.TitleUp, "grown upwards to the title")
    AssertEq(p.y + p.h, 489 + 326, "same bottom")
    AssertEq(QuestsTask.Panel({x: 0, y: 50, w: 10, h: 10}).y, 0, "never above the screen")
    AssertEq(QuestsTask.Key("Delivery II`nProgress 0/3"), QuestsTask.Key("Delivery II`nProgress 1/3"), "progress digits do not change the quest identity")
}

Test_Quests_ExitOnlyWhileTheBoardIsUp() {
    ; live 2026-11-02: a click on an empty spot went through into the world.
    ; The board went away after the claim: Exit is never clicked blind.
    board := QmBoard([["Mythic Aura Hunt`nRoll 1 Mythic aura", "Claim Rewards"]])
    board.onClick := (x, y) => (x = 100 && y = 200) ? board.closed := true : 0
    m := QmBoardTask(board)
    AssertEq(m.t.Run(SchedCtx()), 1, "claimed")
    AssertTrue(!m.io.Moved(700, 800), "Exit never clicked without the board")
    found := false
    for l in m.logs
        found := found || InStr(l, "board is not open")
    AssertTrue(found, "logged why")
    ; every quest claimed (empty panel) but the Exit button still reads: closed
    board2 := QmBoard([["Mythic Aura Hunt`nRoll 1 Mythic aura", "Claim Rewards"]])
    m2 := QmBoardTask(board2)
    m2.t.Run(SchedCtx())
    AssertEq(board2.q.Length, 0, "claimed off the board")
    AssertTrue(m2.io.Moved(700, 800), "Exit clicked while its word reads")
    ; the Exit click opens a purchase prompt: closed with Esc and reported
    board3 := QmBoard([["Resonance`nReach it"]])
    board3.promptOnExit := true
    m3 := QmBoardTask(board3)
    m3.t.Run(SchedCtx())
    iExit := QmLast(m3.io, "move 700,800")
    AssertTrue(iExit > 0 && QmLast(m3.io, "down Esc") > iExit, "Esc after Exit")
    AssertEq(board3.prompt, false, "prompt closed")
    found := false
    for x in m3.wh.sent
        found := found || (x.event = "errors" && InStr(x.title, "Purchase prompt"))
    AssertTrue(found, "reported")
}

; ---- MerchantTask ----------------------------------------------------------

Test_Merchant_NotifyDedupeAndLogEvents() {
    clock := QmClock(0)
    t := MerchantTask({now: () => clock.Now()})
    AssertEq(t.name, "merchant", "name")
    AssertEq(t.priority, 3, "priority")
    AssertEq(t.CanRun(SchedState()), false, "nothing pending")
    ev := Map("type", "merchant", "name", "Mari", "ts", "x", "live", false)
    t.OnLogEvent(ev)
    AssertEq(t.CanRun(SchedState()), false, "live=false ignored")
    ev["live"] := true
    t.OnLogEvent(ev)
    AssertEq(t.CanRun(SchedState()), true, "live merchant event queues a visit")
    AssertEq(t.Notify("Mari"), false, "already pending")
    AssertEq(t.Notify("Bob"), false, "unknown merchant ignored")
    AssertEq(t.Notify("Jester"), true, "other merchant queues")
    AssertEq(t.Pending(), 2, "two pending")
    t.OnLogEvent(Map("type", "biome", "name", "Mari", "live", true))
    AssertEq(t.Pending(), 2, "non-merchant event ignored")
}

Test_Merchant_Dedupe120sSliding() {
    clock := QmClock(0)
    t := MerchantTask({now: () => clock.Now()})
    AssertEq(t.Notify("Mari"), true, "first notice queues")
    AssertEq(t.Run(SchedCtx()), 0, "visit (empty want-list) clears pending")
    clock.t := 60000
    AssertEq(t.Notify("Mari"), false, "within 120 s suppressed")
    clock.t := 150000
    AssertEq(t.Notify("Mari"), false, "still suppressed: 90 s since last notice (window slides)")
    clock.t := 269999
    AssertEq(t.Notify("Mari"), false, "119.999 s since last notice: suppressed")
    clock.t := 389999
    AssertEq(t.Notify("Mari"), true, "120 s after the last notice: queues again")
    AssertEq(t.CanRun(SchedState()), true, "second trip pending")
}

; Merchant calibration with the inventory steps the teleporter needs.
QmMerchCal(extra := "") {
    p := Map("inv_open", {x: 100, y: 100}, "inv_items_tab", {x: 110, y: 110}
        , "inv_search", {x: 120, y: 120}, "inv_use", {x: 130, y: 130})
    r := Map("inv_tile1_rect", {x: 200, y: 200, w: 100, h: 30}, "inv_desc_rect", {x: 300, y: 300, w: 200, h: 40})
    if (extra is Map)
        for k, v in extra
            p[k] := v
    return QmCal(p, r)
}

; OCR fake for the inventory: tile text, description text and the tabs
; (read around inv_items_tab 110,110 by TaskEnv.InvOpen), only while it is
; open (io.InvOpen).
QmTeleOcr(io, tile := "Merchant`nTeleporter", desc := "Teleports you to the current merchant") {
    return (x, y, w, h, scale := 1) => !io.InvOpen() ? "" : (x = 200) ? tile : (x = 300) ? desc : (x = 20 && y = 85) ? "Gears   Items" : ""
}

; A merchant shop as the clip shows it, driven by what the task clicked
; (io.log): the dialog after E, the shop after Open, 5 tabs, the selected
; item's title and stock, and the "You purchased" notice right after a
; Purchase click. Text uses the game font's "o" for "a" where OCR does.
class QmShop {
    __New(io, tabs, stock := "") {
        this.io := io
        this.tabs := tabs
        this.stock := stock is Map ? stock : Map()
        this.dialog := true
        this.shop := true
        this.confirm := true
        this.scales := Map()     ; "x,y" -> last OCR scale asked for
        this.noMerchant := false ; Use shows "There's no merchant spawned"
        this.promptAfter := ""   ; a Roblox purchase prompt shows after this log entry (Esc closes it)
    }
    _Pt(p) => "move " p.x "," p.y
    _LastMove() {
        i := this.io.log.Length
        while (i > 0) {
            if (SubStr(this.io.log[i], 1, 5) = "move ")
                return this.io.log[i]
            i--
        }
        return ""
    }
    _After(a, b) {          ; a logged after the first b
        ib := this.io.Index(b)
        if !ib
            return false
        Loop this.io.log.Length - ib
            if (this.io.log[ib + A_Index] = a)
                return true
        return false
    }
    Sel() {
        L := MerchantTask.Layout
        i := this.io.log.Length
        while (i > 0) {
            for k, r in L.tabs
                if (this.io.log[i] = "move " (r.x + r.w // 2) "," (r.y + r.h // 2))
                    return this.tabs[k]
            i--
        }
        return this.tabs[1]
    }
    Ocr(x, y, w, h, scale := 1) {
        L := MerchantTask.Layout
        this.scales[x "," y] := scale
        pb := Input.PurchaseBox
        if (x = pb.x && y = pb.y)
            return (this.promptAfter != "" && this.io.Index(this.promptAfter) && !this._After("down Esc", this.promptAfter))
                ? "Buy Robux and item`nR$1,000 Donation`nBuy $4.99" : ""
        inv := this.io.InvOpen()
        if (x = 200)
            return inv ? "Merchant`nTeleporter" : ""
        if (x = 300)
            return inv ? "Teleports you to the current merchant" : ""
        if (x = 20 && y = 85)
            return inv ? "Gears   Items" : ""
        nb := MerchantTask.NoMerchantBox
        if (x = nb.x && y = nb.y)
            return (this.noMerchant && this.io.Index("move 130,130")) ? "Warning`nThere' G no merchant gpowned_ (Event merchant iG not counted)" : ""
        talked := this.io.Index("down e") > 0
        opened := talked && this._After(this._Pt(L.open), "down e")
        left := talked && this._After(this._Pt(L.leave), "down e")
        b := MerchantTask.ButtonBox
        up := talked && this.dialog && !left
        if (x = L.dialogName.x && y = L.dialogName.y)
            return (up && !opened) ? "Mori`nI hope I have something... that catches your attention.." : ""
        ; her buttons show once her line is done (here: after the skip click)
        if (x = L.open.x + b.dx && y = L.open.y + b.dy)
            return (up && !opened && this._After(this._Pt(L.skip), "down e")) ? "[ Open ]" : ""
        if (x = L.leave.x + b.dx && y = L.leave.y + b.dy)
            return (up && (!opened || this._After(this._Pt(L.close), "down e"))) ? "[ Leave ]" : ""
        if (x = L.title.x && y = L.title.y)
            return (opened && this.shop) ? "Mori's Shop" : ""
        if !(opened && this.shop)
            return ""
        for k, r in L.tabs
            if (x = r.x && y = r.y)
                return this.tabs[k]
        sel := this.Sel()
        if (x = L.item.x && y = L.item.y)
            return StrReplace(sel, "k", "I<") " | Common"
        if (x = L.stock.x && y = L.stock.y)
            return "Stock Left: " StrReplace(StrReplace(String(this.stock.Has(sel) ? this.stock[sel] : 10), "1", "I"), "0", "O")
        if (x = L.notice.x && y = L.notice.y)
            return (this.confirm && this._LastMove() = this._Pt(L.buy)) ? "You purchosed some " sel "s" : ""
        return ""
    }
}

QmMerchTask(wants, shop, io, wh, gets := "") {
    return MerchantTask({cfg: QmCfg(gets, Map("merchants", wants)), io: io, webhook: wh, cal: QmMerchCal()
        , ocr: (x, y, w, h, scale := 1) => shop.Ocr(x, y, w, h, scale)})
}

QmTyped(io, from := 0) {
    s := ""
    for i, e in io.log
        if (i > from && SubStr(e, 1, 5) = "type ")
            s .= SubStr(e, 6)
    return s
}

Test_Merchant_MissingCalibrationOrRouteSkipsWithoutClicking() {
    wants := Map("Mari", [Map("name", "Lucky Potion", "qty", 2)], "Jester", [])
    ; no inventory calibration (the teleporter needs it)
    io := QmIO()
    wh := QmWh()
    t := MerchantTask({cfg: QmCfg(, Map("merchants", wants)), io: io, webhook: wh, cal: QmCal(), ocr: QmTeleOcr(io)})
    t.Notify("Mari")
    AssertEq(t.Run(SchedCtx()), 0, "no visit")
    AssertEq(io.log.Length, 0, "no input without calibration")
    AssertTrue(wh.Count("errors") >= 1, "missing steps reported")
    AssertEq(t.CanRun(SchedState()), false, "pending cleared (no retry loop)")
    ; teleporter switched off: not visited, nothing pressed, no error
    io3 := QmIO()
    wh3 := QmWh()
    t3 := MerchantTask({
        cfg: QmCfg(Map("merchant.teleporter", 0), Map("merchants", wants)),
        io: io3, webhook: wh3, cal: QmMerchCal(), ocr: QmTeleOcr(io3)
    })
    t3.Notify("Mari")
    AssertEq(t3.Run(SchedCtx()), 0, "teleporter off -> no visit")
    AssertEq(io3.log.Length, 0, "no input")
    AssertEq(wh3.Count("errors"), 0, "not an error")
}

Test_Merchant_ShopTextHelpers() {
    tabs := ["Lucky Potion", "Speed Potion", "Fortune Spoid I", "Fortune Spoid II", "Mixed Potion"]
    AssertEq(MerchantTask.FindTab(tabs, "Fortune Spoid I"), 3, "I is not II")
    AssertEq(MerchantTask.FindTab(tabs, "Fortune Spoid II"), 4, "II")
    AssertEq(MerchantTask.FindTab(["Lucky Potian", "Speed Pation"], "Lucky Potion"), 1, "o/a look-alikes")
    AssertEq(MerchantTask.FindTab(["Lucky Potion", "Fortune Spoid ll"], "Fortune Spoid II"), 2, "l for I")
    AssertEq(MerchantTask.FindTab(tabs, "Heavenly Potion"), 0, "not sold")
    AssertEq(MerchantTask.FindTab(["", "", "", "", ""], "Lucky Potion"), 0, "unreadable row")
    AssertEq(MerchantTask.Stock("Stock Left: 10"), 10, "stock")
    AssertEq(MerchantTask.Stock("Stack Left: O"), 0, "font o for 0")
    ; what Windows OCR read off the clip's frames (2026-10-26)
    AssertEq(MerchantTask.Stock("Stock Left: IO"), 10, "I and O for 1 and 0")
    AssertEq(MerchantTask.Stock("Stocl< Left: O"), 0, "sold out, k misread")
    AssertTrue(InStr(MerchantTask.Norm("LucI<Y Potion I Common"), MerchantTask.Norm("Lucky Potion")), "item title with k as I<")
    AssertTrue(RegExMatch("YOU purchased IO Lucky Potions", "i)purch[ao]sed"), "notice")
    AssertEq(MerchantTask.Stock(""), "", "unreadable stock")
    AssertTrue(RegExMatch("Mori", MerchantTask.NameRe["Mari"]), "Mari in the game font")
    AssertEq(MerchantTask.ParseItem(Map("name", "Lucky Potion", "qty", 3, "x", 1, "y", 2)).qty, 3, "old x/y entries still load")
}

Test_Merchant_OnlyTheWantedTier() {
    ; 2026-10-27 review: a shop that carries ONE tier sold the wrong one:
    ; "fartunespaidii" contains "fartunespaidi", III is one letter from II,
    ; and the title's "|" folds to "i" ("Fortune Spoid I | Common" contains
    ; "fartunespaidii"). The roman numeral must match exactly.
    AssertEq(MerchantTask.FindTab(["Lucky Potion", "Fortune Spoid II"], "Fortune Spoid I"), 0, "want I, only II sold")
    AssertEq(MerchantTask.FindTab(["Fortune Spoid I", "Fortune Spoid II"], "Fortune Spoid III"), 0, "want III, only I and II sold")
    AssertEq(MerchantTask.FindTab(["Lucky Potion", "Fortune Spoid I"], "Fortune Spoid II"), 0, "want II, only I sold")
    AssertEq(MerchantTask.FindTab(["Stronge Potion II"], "Strange Potion I"), 0, "Jester: want I, only II sold")
    AssertEq(MerchantTask.FindTab(["Stronge Potion I"], "Strange Potion II"), 0, "Jester: want II, only I sold")
    AssertEq(MerchantTask.FindTab(["Fortune Spoid ll", "Fortune Spoid lll"], "Fortune Spoid III"), 2, "III read as lll")
    AssertEq(MerchantTask.FindTab(["Lucky Potion", "Fortvne Spoid I"], "Fortune Spoid I"), 2, "slack on the base name only")
    AssertTrue(!MerchantTask.TitleNames("Fortune Spoid II | Rare", "Fortune Spoid I"), "title II is not I")
    AssertTrue(!MerchantTask.TitleNames("Fortune Spoid II | Rare", "Fortune Spoid III"), "title II is not III")
    AssertTrue(!MerchantTask.TitleNames("Fortune Spoid I | Common", "Fortune Spoid II"), "title I is not II ('|' folds to i)")
    AssertTrue(MerchantTask.TitleNames("Fortune Spoid II | Rare", "Fortune Spoid II"), "title II is II")
    AssertTrue(MerchantTask.TitleNames("Fortune Spoid II I Rare", "Fortune Spoid II"), "title II, separator read as I")
    AssertTrue(MerchantTask.TitleNames("LucI<Y Potion | Common", "Lucky Potion"), "no tier")
    AssertTrue(!MerchantTask.TitleNames("Lucky Potion I Common", "Lucky Potion L"), "no tier is not L (folds to I)")
    ; the whole visit: only II in the shop, I wanted -> nothing bought
    io := QmIO()
    wh := QmWh()
    shop := QmShop(io, ["Lucky Potion", "Speed Potion", "Fortune Spoid II", "Mixed Potion", "Gear B"])
    t := QmMerchTask(Map("Mari", [Map("name", "Fortune Spoid I", "qty", 2)], "Jester", []), shop, io, wh)
    t.Notify("Mari")
    AssertEq(t.Run(SchedCtx()), 1, "visited")
    L := MerchantTask.Layout
    AssertEq(io.Index("move " (L.tabs[3].x + L.tabs[3].w // 2) "," (L.tabs[3].y + L.tabs[3].h // 2)), 0, "the II tab never clicked")
    AssertEq(io.Index("move " L.buy.x "," L.buy.y), 0, "nothing bought")
    AssertTrue(InStr(wh.sent[wh.sent.Length].desc, "Fortune Spoid I: not sold this visit"), "reported as not sold")
}

Test_Merchant_BuysByNameFromTheShopTabs() {
    wants := Map("Mari", [
        Map("name", "Lucky Potion", "qty", 25),          ; stock 10 -> 10
        Map("name", "Fortune Spoid I", "qty", 2),        ; tab 4 (II is tab 3)
        "Heavenly Potion",                               ; not sold this visit
        Map("name", "Speed Potion", "qty", 3)            ; sold out
    ], "Jester", [])
    io := QmIO()
    wh := QmWh()
    shop := QmShop(io, ["Lucky Potion", "Speed Potion", "Fortune Spoid II", "Fortune Spoid I", "Mixed Potion"]
        , Map("Speed Potion", 0))
    t := QmMerchTask(wants, shop, io, wh)
    t.Notify("Mari")
    AssertEq(t.Run(SchedCtx()), 1, "one visit")
    L := MerchantTask.Layout
    iUse := io.Index("move 130,130")
    iE := io.Index("down e")
    iOpen := io.Index("move " L.open.x "," L.open.y)
    AssertTrue(iUse > 0 && iE > iUse, "teleported, then E")
    AssertTrue(iOpen > iE, "Open clicked after the dialog showed")
    tab := (k) => "move " (L.tabs[k].x + L.tabs[k].w // 2) "," (L.tabs[k].y + L.tabs[k].h // 2)
    AssertTrue(io.Index(tab(1)) > iOpen, "Lucky Potion tab")
    AssertTrue(io.Index(tab(4)) > io.Index(tab(1)), "Fortune Spoid I tab, not II")
    AssertEq(io.Index(tab(3)), 0, "Fortune Spoid II never clicked")
    AssertEq(QmTyped(io, iOpen), "102", "typed 10 (capped at the stock) then 2")
    buys := 0
    for e in io.log
        buys += (e = "move " L.buy.x "," L.buy.y) ? 1 : 0
    AssertEq(buys, 2, "Purchase clicked once per item bought")
    AssertTrue(io.Index("move " L.close.x "," L.close.y) > 0, "shop closed with X")
    d := wh.sent[wh.sent.Length].desc
    AssertEq(wh.Count("merchant"), 1, "one merchant webhook")
    AssertTrue(InStr(d, "bought 10 Lucky Potion"), "lucky confirmed")
    AssertTrue(InStr(d, "bought 2 Fortune Spoid I"), "spoid confirmed")
    AssertTrue(InStr(d, "Heavenly Potion: not sold this visit"), "not sold")
    AssertTrue(InStr(d, "Speed Potion: sold out"), "sold out")
    AssertEq(wh.Count("errors"), 0, "no errors")
    AssertEq(shop.scales[L.title.x "," L.title.y], 2, "title read at scale 2")
    AssertEq(shop.scales[L.stock.x "," L.stock.y], 2, "stock read at scale 2")
    ; no notice after Purchase: reported as not confirmed
    io2 := QmIO()
    wh2 := QmWh()
    shop2 := QmShop(io2, ["Lucky Potion", "", "", "", ""])
    shop2.confirm := false
    t2 := QmMerchTask(Map("Mari", [Map("name", "Lucky Potion", "qty", 1)], "Jester", []), shop2, io2, wh2)
    t2.Notify("Mari")
    t2.Run(SchedCtx())
    AssertTrue(InStr(wh2.sent[wh2.sent.Length].desc, "no 'You purchased' notice seen"), "unconfirmed purchase says so")
}

Test_Merchant_ShopNotOpenNothingBought() {
    L := MerchantTask.Layout
    wants := Map("Mari", [Map("name", "Lucky Potion", "qty", 1)], "Jester", [])
    ; the dialog never shows: Open is never clicked
    io := QmIO()
    wh := QmWh()
    shop := QmShop(io, ["Lucky Potion", "", "", "", ""])
    shop.dialog := false
    t := QmMerchTask(wants, shop, io, wh)
    t.Notify("Mari")
    t.Run(SchedCtx())
    AssertEq(io.Index("move " L.open.x "," L.open.y), 0, "no Open click without the dialog")
    AssertEq(io.Index("move " L.buy.x "," L.buy.y), 0, "nothing bought")
    AssertEq(wh.Count("errors"), 1, "reported")
    ; the dialog shows but the shop does not open
    io2 := QmIO()
    wh2 := QmWh()
    shop2 := QmShop(io2, ["Lucky Potion", "", "", "", ""])
    shop2.shop := false
    t2 := QmMerchTask(wants, shop2, io2, wh2)
    t2.Notify("Mari")
    t2.Run(SchedCtx())
    AssertTrue(io2.Index("move " L.open.x "," L.open.y) > 0, "Open clicked")
    AssertEq(io2.Index("move " L.buy.x "," L.buy.y), 0, "nothing bought")
    AssertEq(wh2.Count("errors"), 1, "reported")
    ; empty want-list: no trip at all
    io3 := QmIO()
    wh3 := QmWh()
    t3 := MerchantTask({cfg: QmCfg(, Map("merchants", Map("Mari", [], "Jester", []))), io: io3, webhook: wh3, cal: QmMerchCal()})
    t3.Notify("Mari")
    AssertEq(t3.Run(SchedCtx()), 0, "empty want-list: no visit")
    AssertEq(io3.log.Length, 0, "no input")
    AssertEq(wh3.Count("merchant"), 1, "still reports the arrival")
}


Test_Merchant_TeleporterSearchRetypedWhenALetterDrops() {
    ; the first search shows nothing (a dropped letter), the second the teleporter
    wants := Map("Mari", [], "Jester", [])
    io := QmIO()
    wh := QmWh()
    reads := [0]
    ocr := (x, y, w, h, scale := 1) => (x = 200) ? (++reads[1] = 1 ? "" : "Merchant`nTeleporter") : (x = 300) ? "Teleports you to the current merchant"
        : (x = 20 && y = 85 && io.InvOpen()) ? "Gears   Items" : ""
    t :=MerchantTask({cfg: QmCfg(, Map("merchants", wants)), io: io, webhook: wh, cal: QmMerchCal(), ocr: ocr, pixel: (*) => true})
    c := t._InvCal()
    AssertEq(t._Teleport(c, SchedCtx()), true, "used after typing the search again")
    n := 0
    for e in io.log
        n += (e = "move 120,120") ? 1 : 0
    AssertEq(n, 2, "search box clicked twice (typed twice)")
    AssertTrue(io.Index("move 130,130") > 0, "Use clicked")
    AssertEq(wh.Count("errors"), 0, "no error")
}

; clip 2026-10-27 20:36: "Mari has arrived" in chat, but Use answered
; "There's no merchant spawned. (Event merchant is not counted)"; the macro
; pressed E for a dialog that never came, reported an error and respawned
Test_Merchant_NoMerchantSpawnedStopsQuietly() {
    io := QmIO()
    wh := QmWh()
    shop := QmShop(io, ["Lucky Potion", "Speed Potion", "Fortune Spoid II", "Fortune Spoid I", "Mixed Potion"])
    shop.noMerchant := true
    t := QmMerchTask(Map("Mari", [Map("name", "Lucky Potion", "qty", 1)], "Jester", []), shop, io, wh)
    t.Notify("Mari")
    AssertEq(t.Run(SchedCtx()), 0, "no visit")
    AssertTrue(io.Index("move 130,130") > 0, "Use clicked")
    AssertEq(io.Index("down e"), 0, "no E for a merchant who is not there")
    AssertEq(io.Index("down Esc"), 0, "no respawn: nothing moved")
    AssertEq(wh.Count("errors"), 0, "not an error")
    AssertEq(wh.Count("merchant"), 1, "one merchant webhook says why")
    AssertTrue(InStr(wh.sent[wh.sent.Length].desc, "no merchant has spawned"), "says the teleporter found none")
    AssertEq(t.Pending(), 0, "the visit is dropped, not retried")
}

Test_Merchant_InventoryClosedAndChecked() {
    ; nothing found: the inventory's tabs still read after the first close click -> clicked again
    wants := Map("Mari", [], "Jester", [])
    io := QmIO()
    wh := QmWh()
    ocr := (x, y, w, h, scale := 1) => (x = 20 && y = 85) ? (QmCountMoves(io, "move 100,100") = 1 || QmCountMoves(io, "move 100,100") = 2 ? "Gears   Items" : "") : ""
    t := MerchantTask({cfg: QmCfg(, Map("merchants", wants)), io: io, webhook: wh, cal: QmMerchCal(), ocr: ocr, pixel: (*) => true})
    c := t._InvCal()
    AssertEq(t._Teleport(c, SchedCtx()), false, "not used")
    AssertEq(QmCountMoves(io, "move 100,100"), 3, "opened once, then closed with a second click after the check")
    AssertEq(wh.Count("errors"), 1, "reported")
}

QmCountMoves(io, text) {
    n := 0
    for e in io.log
        n += (e = text) ? 1 : 0
    return n
}

Test_Merchant_EPressedAgainUntilHerDialogShows() {
    ; the first E lands before her prompt: her name shows only after the second
    io := QmIO()
    ocr := (x, y, w, h, scale := 1) => (x = MerchantTask.Layout.dialogName.x && y = MerchantTask.Layout.dialogName.y) ? (QmCountMoves(io, "down e") >= 2 ? "Mori" : "") : ""
    t := MerchantTask({cfg: QmCfg(), io: io, webhook: QmWh(), cal: QmMerchCal(), ocr: ocr, pixel: (*) => true})
    AssertEq(t._OpenDialog("Mari", SchedCtx()), 1, "dialog seen after E again")
    AssertEq(QmCountMoves(io, "down e"), 2, "E pressed twice")
    ; never: DialogTries presses, then 0
    io2 := QmIO()
    t2 := MerchantTask({cfg: QmCfg(), io: io2, webhook: QmWh(), cal: QmMerchCal(), ocr: (x, y, w, h, scale := 1) => "", pixel: (*) => true})
    AssertEq(t2._OpenDialog("Mari", SchedCtx()), 0, "not seen")
    AssertEq(QmCountMoves(io2, "down e"), MerchantTask.DialogTries, "E pressed DialogTries times")
}

Test_Merchant_WaitsForHerButtonsAndLeavesBeforeTheReset() {
    ; clip 2026-10-26: Open was clicked ~5 s before her buttons existed, the
    ; visit gave up and respawned with her dialog open (it stayed on screen)
    wants := Map("Mari", [Map("name", "Lucky Potion", "qty", 1)], "Jester", [])
    io := QmIO()
    wh := QmWh()
    shop := QmShop(io, ["Lucky Potion", "Speed Potion", "Mixed Potion", "Fortune Spoid I", "Gear B"])
    t := QmMerchTask(wants, shop, io, wh)
    t.Notify("Mari")
    AssertEq(t.Run(SchedCtx()), 1, "visited")
    L := MerchantTask.Layout
    iSkip := io.Index("move " L.skip.x "," L.skip.y)
    iOpen := io.Index("move " L.open.x "," L.open.y)
    AssertTrue(iSkip > 0 && iOpen > iSkip, "skip her line first, Open only once its button reads")
    iLeave := io.Index("move " L.leave.x "," L.leave.y)
    iEsc := io.Index("down Esc")
    AssertTrue(iLeave > iOpen, "her dialog is left after shopping")
    AssertTrue(iEsc = 0 || iEsc > iLeave, "never a reset before Leave")
    ; her buttons never show: nothing opened, she is left, then the reset
    io2 := QmIO()
    wh2 := QmWh()
    shop2 := QmShop(io2, ["Lucky Potion", "Speed Potion", "Mixed Potion", "Fortune Spoid I", "Gear B"])
    t2 := MerchantTask({cfg: QmCfg(, Map("merchants", wants)), io: io2, webhook: wh2, cal: QmMerchCal()
        , ocr: (x, y, w, h, scale := 1) => (x = L.open.x + MerchantTask.ButtonBox.dx) ? "" : shop2.Ocr(x, y, w, h, scale)})
    t2.Notify("Mari")
    AssertEq(t2.Run(SchedCtx()), 0, "not visited")
    AssertEq(io2.Index("move " L.open.x "," L.open.y), 0, "Open never clicked blind")
    AssertTrue(io2.Index("move " L.leave.x "," L.leave.y) > 0, "Leave clicked")
    AssertTrue(wh2.Count("errors") >= 1, "reported")
}

Test_Merchant_JesterClipReads() {
    ; OCR of Jester's shop (clip 2026-10-26): the game font reads "g" as "o"
    tabs := ["Stronge Potion I", "Speed Potion", "LucI<Y Potion", "Rune of Everythino", "Heavenly Potion"]
    AssertEq(MerchantTask.FindTab(tabs, "Rune of Everything"), 4, "Everythino = Everything")
    AssertEq(MerchantTask.FindTab(tabs, "Strange Potion I"), 1, "Stronge = Strange")
    AssertEq(MerchantTask.FindTab(tabs, "Lucky Potion"), 3, "LucI<Y = Lucky")
    AssertEq(MerchantTask.FindTab(tabs, "Oblivion Potion"), 0, "not sold: no near match")
    AssertEq(MerchantTask.FindTab(["Speed Potion", "Seed Potion"], "Steed Potion"), 0, "two tabs as close: none")
    AssertTrue(MerchantTask.TitleNames("Rune of Everythino I Mythic", "Rune of Everything"), "title with a misread letter")
    AssertTrue(!MerchantTask.TitleNames("Heavenly Potion I Legendary", "Rune of Everything"), "another title")
    ; the real read of jester_shop's title: the "|" separator reads as "I"
    AssertTrue(MerchantTask.TitleNames("Stronge Potion I I Uncommon", "Strange Potion I"), "tier I title, separator read as I")
    AssertTrue(!MerchantTask.TitleNames("Stronge Potion I I Uncommon", "Strange Potion II"), "tier I title is not II")
    AssertTrue(RegExMatch("Leuve", MerchantTask.LeaveRe) > 0, "Jester's Leave reads 'Leuve'")
    AssertEq(MerchantTask.Stock("Stocl< Left: 20"), 20, "stock")
}

Test_Merchant_TeleporterNeverUsesAnotherItem() {
    wants := Map("Mari", [Map("name", "Lucky Potion", "qty", 1, "x", 700, "y", 800)], "Jester", [])
    ; the search shows a potion first (no teleporter owned): Use never clicked
    io := QmIO()
    wh := QmWh()
    t := MerchantTask({cfg: QmCfg(, Map("merchants", wants)), io: io, webhook: wh, cal: QmMerchCal()
        , ocr: QmTeleOcr(io, "Lucky`nPotion", "Gives you [Lucky]"), pixel: (*) => true})
    t.Notify("Mari")
    AssertEq(t.Run(SchedCtx()), 0, "no visit")
    AssertEq(io.Index("move 130,130"), 0, "Use never clicked")
    AssertEq(io.Index("down e"), 0, "no merchant talk")
    AssertEq(wh.Count("errors"), 1, "reported")
    AssertTrue(io.log[io.log.Length - 1] = "move 100,100" || io.Index("move 100,100") > 0, "inventory closed again")
    ; the tile says teleporter but the selected item's description does not (stale selection)
    io2 := QmIO()
    wh2 := QmWh()
    t2 := MerchantTask({cfg: QmCfg(, Map("merchants", wants)), io: io2, webhook: wh2, cal: QmMerchCal()
        , ocr: QmTeleOcr(io2, "Merchant`nTeleporter", "Gives you [Heavenly] for 1 roll"), pixel: (*) => true})
    t2.Notify("Mari")
    t2.Run(SchedCtx())
    AssertEq(io2.Index("move 130,130"), 0, "Use never clicked without the teleporter description")
    AssertEq(wh2.Count("errors"), 1, "reported")
}

; ---- no blind clicks (live 2026-11-02: a click went through a panel into
; the world and opened Roblox's "Buy Robux and item" prompt) ---------------

QmSaid(logs, text) {
    for l in logs
        if InStr(l, text)
            return true
    return false
}

QmPromptReported(wh) {
    for x in wh.sent
        if (x.event = "errors" && InStr(x.title, "Purchase prompt"))
            return true
    return false
}

Test_Merchant_InventoryNotOpenNothingClicked() {
    ; the inventory button does nothing: its tabs never read, so the Items
    ; tab, the search box, a tile and Use are never clicked blind
    io := QmIO()
    wh := QmWh()
    logs := []
    t := MerchantTask({cfg: QmCfg(, Map("merchants", Map("Mari", [Map("name", "Lucky Potion")], "Jester", []))), io: io
        , webhook: wh, cal: QmMerchCal(), log: (s) => logs.Push(s)
        , ocr: (x, y, w, h, scale := 1) => (x = 200) ? "Merchant`nTeleporter" : (x = 300) ? "Teleports you" : ""})
    t.Notify("Mari")
    AssertEq(t.Run(SchedCtx()), 0, "no visit")
    AssertEq(QmCountMoves(io, "move 100,100"), 1, "inventory button clicked once")
    for p in ["110,110", "120,120", "250,215", "130,130"]
        AssertEq(io.Index("move " p), 0, p " never clicked with the inventory shut")
    AssertEq(io.Index("down e"), 0, "no merchant talk")
    AssertEq(wh.Count("errors"), 1, "reported")
    AssertTrue(QmSaid(logs, "inventory is not open"), "logged why")
}

Test_Merchant_PurchasePromptStopsTheTeleport() {
    wants := Map("Mari", [Map("name", "Lucky Potion", "qty", 1)], "Jester", [])
    ; a prompt shows after the tile click: Use is never clicked, Esc closes it
    io := QmIO()
    wh := QmWh()
    shop := QmShop(io, ["Lucky Potion", "", "", "", ""])
    shop.promptAfter := "move 250,215"
    t := QmMerchTask(wants, shop, io, wh)
    t.Notify("Mari")
    AssertEq(t.Run(SchedCtx()), 0, "no visit")
    AssertEq(io.Index("move 130,130"), 0, "Use never clicked")
    AssertTrue(io.Index("down Esc") > io.Index("move 250,215"), "closed with Esc")
    AssertEq(io.Index("down e"), 0, "no merchant talk")
    AssertTrue(QmPromptReported(wh), "reported")
    ; a prompt right after Use: closed, no merchant talk
    io2 := QmIO()
    wh2 := QmWh()
    shop2 := QmShop(io2, ["Lucky Potion", "", "", "", ""])
    shop2.promptAfter := "move 130,130"
    t2 := QmMerchTask(wants, shop2, io2, wh2)
    t2.Notify("Mari")
    AssertEq(t2.Run(SchedCtx()), 0, "no visit")
    AssertTrue(io2.Index("down Esc") > io2.Index("move 130,130"), "closed with Esc after Use")
    AssertEq(io2.Index("down e"), 0, "no merchant talk after a prompt")
    AssertTrue(QmPromptReported(wh2), "reported")
}

Test_Merchant_ShopClosedOnlyWhileItsTitleReads() {
    L := MerchantTask.Layout
    wants := Map("Mari", [Map("name", "Lucky Potion", "qty", 1)], "Jester", [])
    ; the shop is gone after Purchase (its title no longer reads): X never clicked
    io := QmIO()
    wh := QmWh()
    shop := QmShop(io, ["Lucky Potion", "", "", "", ""])
    logs := []
    t := MerchantTask({cfg: QmCfg(, Map("merchants", wants)), io: io, webhook: wh, cal: QmMerchCal(), log: (s) => logs.Push(s)
        , ocr: (x, y, w, h, scale := 1) => (x = L.title.x && y = L.title.y && io.Index("move " L.buy.x "," L.buy.y)) ? "" : shop.Ocr(x, y, w, h, scale)})
    t.Notify("Mari")
    t.Run(SchedCtx())
    AssertTrue(io.Index("move " L.buy.x "," L.buy.y) > 0, "bought")
    AssertEq(io.Index("move " L.close.x "," L.close.y), 0, "X never clicked without the shop")
    AssertTrue(QmSaid(logs, "shop is not open"), "logged why")
    ; a prompt after X: closed with Esc and reported
    io2 := QmIO()
    wh2 := QmWh()
    shop2 := QmShop(io2, ["Lucky Potion", "", "", "", ""])
    shop2.promptAfter := "move " L.close.x "," L.close.y
    t2 := QmMerchTask(wants, shop2, io2, wh2)
    t2.Notify("Mari")
    t2.Run(SchedCtx())
    AssertTrue(io2.Index("down Esc") > io2.Index("move " L.close.x "," L.close.y), "closed with Esc after X")
    AssertTrue(QmPromptReported(wh2), "reported")
}

; live 2026-11-10: the title read 'Mori's sho' and her shop was left open
Test_Merchant_ShopTitleReadsWhenCut() {
    AssertTrue(RegExMatch("Mari's Shop", MerchantTask.ShopRe) > 0, "full title")
    AssertTrue(RegExMatch("Mori's sho", MerchantTask.ShopRe) > 0, "cut and misread")
    AssertTrue(RegExMatch("Jester's Shap", MerchantTask.ShopRe) > 0, "a for o")
    AssertTrue(RegExMatch("Mori's stin", MerchantTask.ShopRe) > 0, "h read as t")
    AssertTrue(RegExMatch("Mori•s$hop", MerchantTask.ShopRe) > 0, "S read as $")
    AssertTrue(RegExMatch("Morl s stib", MerchantTask.ShopRe) > 0, "apostrophe lost (live 2026-11-10 18:33)")
    AssertEq(RegExMatch("Open", MerchantTask.ShopRe), 0, "dialog Open button")
    AssertEq(RegExMatch("Mari", MerchantTask.ShopRe), 0, "no shop word")
    AssertEq(RegExMatch("Leave", MerchantTask.ShopRe), 0, "dialog button")
}

; live 2026-11-10: no chat reads during a hunt (minutes), the old line was
; still in the chat each time and Mari was re-queued after every hunt
Test_ChatWatch_LongGapWithoutReadsIsNoAbsence() {
    clock := QmClock(0)
    text := "Mari has arrived"
    cw := ChatWatch({io: QmIO(), cal: QmCal(, Map("chat_rect", {x: 10, y: 20, w: 400, h: 200})), ocr: (*) => text, now: () => clock.Now()})
    AssertEq(cw.Check().Length, 1, "first sighting")
    for t in [200000, 500000, 900000] {
        clock.t := t
        AssertEq(cw.Check().Length, 0, "same line, reads " t " ms apart: no re-report")
    }
    ; one bad read is not enough either
    text := "", clock.t += 5000, cw.Check()
    text := "chat", clock.t += 200000, cw.Check()
    text := "Mari has arrived", clock.t += 5000
    AssertEq(cw.Check().Length, 0, "absent from 1 read only")
    ; gone from 2 reads and > 120 s, then back: a new arrival
    text := "chat", clock.t += 5000, cw.Check()
    clock.t += 5000, cw.Check()
    text := "Mari has arrived", clock.t += 130000
    AssertEq(cw.Check().Length, 1, "really gone, then back: reported")
}

; live 2026-11-11: an hour-old "Mari has arrived" in the chat sent the macro
; to Mari (a Merchant Teleporter used) at every start
Test_ChatWatch_OldLineAtStartIsNotVisited() {
    clock := QmClock(0)
    text := "Mari has arrived"
    cw := ChatWatch({io: QmIO(), cal: QmCal(, Map("chat_rect", {x: 10, y: 20, w: 400, h: 200})), ocr: (*) => text, now: () => clock.Now(), startOld: true})
    text := "[Tip]: nothing yet"
    AssertEq(cw.Check().Length, 0, "the first read misses the line")
    text := "Mari has arrived"
    clock.t += 10000
    AssertEq(cw.Check().Length, 0, "a later read sees the old line: still not visited")
    clock.t += 10000
    AssertEq(cw.Check().Length, 0, "still the same line")
    ; she leaves the chat, then really arrives again
    text := "[Tip]: something else"
    Loop 3 {
        clock.t += 60000
        cw.Check()
    }
    text := "Mari has arrived"
    clock.t += 10000
    AssertEq(cw.Check().Length, 1, "a new arrival after it: visited")
    ; Rebase (a new Start): the line on screen now is old again
    cw.Rebase()
    clock.t += 300000
    AssertEq(cw.Check().Length, 0, "after a restart: old again")
}

; 1366x768 (live 2026-11-11): the game's "Potion Auto Added" toast (fixed
; px, bottom right) sat over the Accept button for a few seconds: every
; button read "", so unticked quests were never dismissed. The button is
; read again until the toast goes.
Test_Quests_ButtonCoveredByAToastIsReadAgain() {
    board := QmBoard([["River Angler`nCatch fish", "Accept"]])
    board.toast := 3
    m := QmBoardTask(board, Map("quests.dismissDisabled", 1))
    AssertEq(m.t.Run(SchedCtx()), 1, "dismissed once the toast went")
    AssertEq(board.q.Length, 0, "off the board")
    found := false
    for l in m.logs
        found := found || InStr(l, "button: accept")
    AssertTrue(found, "the button read in the end")
}

; 2026-11-11 06:58 (1920x1080): a fishing line left out when the macro was
; stopped and started again: its Fishing Failed card came up during the walk,
; E did nothing under it, and an E after it closed cast Eden's dash. The card
; is closed before E.
Test_Quests_CardOverTheBoardIsClosedBeforeE() {
    board := QmBoard([["River Angler`nCatch fish", "Accept"]])
    board.closed := true
    cleared := 0
    m := ""
    board.cards := (ctx) => (board.closed ? (cleared++, board.closed := false, true) : false)
    m := QmBoardTask(board, Map("quests.dismissDisabled", 1))
    AssertEq(m.t.Run(SchedCtx()), 1, "the board read")
    AssertEq(cleared, 1, "the card closed once")
    AssertEq(QmCountLog(m.io, "down e"), 1, "E once")
    AssertTrue(m.io.Index("down e") > 0, "E pressed")
}

QmCountLog(io, entry) {
    n := 0
    for e in io.log
        n += (e = entry)
    return n
}

; 2560x1440 (live 2026-11-11): Eden's skill list lies over the buttons for
; good; the toast re-read waited 4 s on every quest. A read of the skill
; names stops the re-reads.
Test_Quests_SkillListOverTheButtonIsNotReadAgain() {
    board := QmBoard([["River Angler`nCatch fish", "Taunt Darkmatter Barrage"]])
    m := QmBoardTask(board, Map("quests.dismissDisabled", 1))
    m.t.Run(SchedCtx())
    AssertEq(board.btnReads, 1, "the button read once")
    AssertEq(board.q.Length, 1, "never dismissed blind")
}

Test_Quests_EmptyButtonIsStillReadAgain() {
    board := QmBoard([["River Angler`nCatch fish", ""]])
    m := QmBoardTask(board, Map("quests.dismissDisabled", 1))
    m.t.Run(SchedCtx())
    AssertEq(board.btnReads, 1 + QuestsTask.ButtonTries, "nothing read: read again (a toast)")
}

; 2560x1440 (live 2026-11-11): under Eden's skill list the button read
; 'Accep t': an unticked quest was never dismissed
Test_Quests_AcceptSplitByTheSkillList() {
    board := QmBoard([["River Angler`nCatch fish", "Accep t"]])
    m := QmBoardTask(board, Map("quests.dismissDisabled", 1))
    AssertEq(m.t.Run(SchedCtx()), 1, "read as Accept: dismissed")
    AssertEq(board.q.Length, 0, "off the board")
}

; 2026-11-11 (live, several sizes): a walk missed the board (another
; player's boat, a card after a stop mid-cast) and quests waited 30 minutes.
; The board not open gets one more respawn + walk + E.
Test_Quests_MissedBoardIsWalkedToOnceMore() {
    board := QmBoard([["River Angler`nCatch fish", "Accept"]])
    board.closed := true
    board.opensOnE := 2
    logs := []
    m := QmBoardTask(board, Map("quests.dismissDisabled", 1), , logs)
    AssertEq(m.t.Run(SchedCtx()), 1, "the board read on the second walk")
    AssertEq(QmCountLog(m.io, "down e"), 2, "E twice")
    found := false
    for l in logs
        found := found || InStr(l, "walking there once more")
    AssertTrue(found, "logged")
    ; never opens: two walks, then it gives up
    board2 := QmBoard([["River Angler`nCatch fish", "Accept"]])
    board2.closed := true
    m2 := QmBoardTask(board2, Map("quests.dismissDisabled", 1))
    AssertEq(m2.t.Run(SchedCtx()), 0, "nothing done")
    AssertEq(QmCountLog(m2.io, "down e"), 2, "two tries only")
}

Test_Quests_SkillListFragmentsStopTheReReads() {
    for t in ["rkmot", "vugrkmot Re", "Taunt", "Darkmatter Barrage"]
        AssertTrue(RegExMatch(t, QuestsTask.SkillRe) > 0, "'" t "' is the skill list (live 2560x1440)")
    for t in ["", "Accep t", "Claim Rewards"]
        AssertTrue(!RegExMatch(t, QuestsTask.SkillRe), "'" t "' is not")
}

; 2560x1440 (live 2026-11-11): Eden's skill list over the button read
; 'rkmot'; its green word alone read 'Accevi'
Test_Quests_GreenWordUnderTheSkillList() {
    board := QmBoard([["River Angler`nCatch fish", "rkmot"]])
    board.green := "Accevi"
    m := QmBoardTask(board, Map("quests.dismissDisabled", 1))
    AssertEq(m.t.Run(SchedCtx()), 1, "read as Accept: dismissed")
    board2 := QmBoard([["Mythic Aura Hunt`nRoll 1 Mythic aura", "rkmot"]])
    board2.green := "Cloim Re"
    m2 := QmBoardTask(board2, Map("quests.dismissDisabled", 1))
    m2.t.Run(SchedCtx())
    AssertTrue(InStr(m2.wh.sent.Length ? m2.wh.sent[1].desc : "", "claimed"), "read as Claim: claimed, never dismissed")
    board3 := QmBoard([["River Angler`nCatch fish", "rkmot"]])
    m3 := QmBoardTask(board3, Map("quests.dismissDisabled", 1))
    AssertEq(m3.t.Run(SchedCtx()), 0, "no green word: never dismissed blind")
}
