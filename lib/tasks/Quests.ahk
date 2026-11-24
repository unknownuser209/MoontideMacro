#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\TaskEnv.ahk
#Include %A_LineFile%\..\..\QuestMatch.ahk
; ---------------------------------------------------------------------------
; QuestsTask: one pass over the quest board (spec 4.4).
;
;   t := QuestsTask(deps)     deps as TaskEnv (cfg, webhook, log, io, cal, ocr, now)
;   t.name = "quests", t.priority = 5   (Scheduler task contract)
;   t.CanRun(state)  -> cfg quests.enabled (default 1) AND the route exists.
;                       Without it the task is not eligible, so it never
;                       interrupts sell/fishing just to skip (the missing
;                       piece is logged once).
;   THE BOARD'S STEPS NEED NO CALIBRATION (quest_board_rect, quest_accept,
;   quest_dismiss, quest_close, quest_next): a step that is not recorded is
;   found on screen once the board is open (_FindBoard, lib\AutoCal.ahk:
;   "Objects" and the buttons under it place the panel, "Exit" the Exit
;   button, the > arrow sits from Exit and is checked by its pixels). A
;   recorded panel that reads is used as before and nothing is searched;
;   recorded but nothing reads in it after E: one look, and when the board
;   is found on screen the steps found are used for that visit (logged).
;                       The interval is enforced by Scheduler (QuestDue); the
;                       caller calls Scheduler.MarkRun. Not duplicated here.
;   t.Run(ctx)       -> number of board actions taken.
;
; THE BOARD (2026 UI, seen 2026-10-26): a carousel. One quest shows at a
; time: its title, stars and "Objects" text in a panel on the right, with
; Accept and Dismiss under it, < > arrows beside the board and Exit at the
; bottom. Dismiss moves to the next quest by itself; Accept stays on the
; quest (only > moves on). Claim Rewards shows on the Accept spot.
;
; PASS
;   Preflight (nothing is pressed or clicked unless all pass):
;     calibration quest_board_rect + quest_close, and the route named by cfg
;     quests.route (default "quest_board", from data\routes.json; the user
;     records it, until then the task logs + skips).
;   ResetToSpawn -> walk route -> press E (open board) -> wait up to
;   OpenWaitMs for text in the panel. No text = the board did not open: an
;   EMPTY board shows an in-game notification instead ("no quests"), read in
;   notify_rect when calibrated -> logged as "no quests right now";
;   otherwise "board did not open" (check the route with Test). Nothing is
;   clicked in either case.
;   The panel is read from quest_board_rect grown TitleUp px upwards, so
;   the quest title above the "Objects" box is included.
;   Loop (max QuestsTask.MaxSteps reads), each read looks at the quest shown.
;   A quest is identified by its TITLE only (first OCR line, letters only):
;   the stars and objective text read differently from one OCR to the next
;   (a run that keyed on the whole panel accepted one quest 12 times).
;     a title already handled    -> > did not move, or went all the way
;                                   round: done (nothing is ever done twice)
;     OCR "" / no title          -> done
;     button reads "accepted" /  -> already taken: left alone
;       "in progress"
;     button reads "claim" (or   -> click quest_accept: Accept and Claim
;     the text says completed)      Rewards are the SAME button spot; the
;                                   word on it (OCR around quest_accept)
;                                   tells which one is showing.
;                                   Claim Rewards shows (lit) on EVERY
;                                   accepted quest, finished or not (real
;                                   frame quest_button_claim_toast_1440:
;                                   right under "Quest Accepted"): the
;                                   click only claims a finished one. The
;                                   quest still shown after it = not
;                                   finished: its Claim Rewards is left
;                                   alone for ClaimBackoffMin (60, 120,
;                                   240 min), not pressed every visit.
;                                   The same wait holds an unread button
;                                   pressed blind that changed nothing.
;     no quest name matches      -> left alone (logged with its title)
;     enabled in the filter      -> click quest_accept
;     disabled in the filter     -> quests.dismissDisabled = 1: click
;                                   quest_dismiss (ABANDONS the quest), but
;                                   only when the button word was read (an
;                                   unread word may be Claim Rewards);
;                                   0 (default): left alone. Quests are
;                                   never abandoned unless the user opts in.
;   After the action: Dismiss moves the board on by itself. Otherwise the
;   title is read again; still the same quest -> click quest_next (>).
;   Without quest_next only the first quest(s) shown are handled. Every
;   quest seen is logged with its title and the button word.
;   A missing quest_accept/quest_dismiss skips only that action (logged,
;   errors webhook once); without quest_accept no button word can be read,
;   so nothing is dismissed either. Then click quest_close (exit the
;   board; only while its text or the Exit word reads and no Roblox
;   purchase prompt is up, the prompt guard after it), then ResetToSpawn. One `quests` webhook summarises the actions.
;   Preempted (a higher task due; not F3 / pause): the board is still
;   closed and the player respawned before the next task starts.
; ---------------------------------------------------------------------------

class QuestsTask {
    static MaxSteps := 16          ; reads per pass (5 quests need ~10)
    static OpenKey := "e"
    static SettleMs := 700
    ; Speed (2026-11-13): an unread button cost 8 x 500 ms on 4 of 5 slots
    ; (106 times in the logs). 3 x 300 ms now: still unread = left alone
    ; (never dismissed blind), a claim under a toast waits for the next visit.
    static ButtonTries := 3       ; button reads again while it reads nothing (a toast over it)
    static ButtonRetryMs := 300
    ; Claim Rewards pressed and the quest stayed (not finished): minutes
    ; until its next try, by the number of tries in a row (the last one
    ; repeats). A tester's log (v1.6.1) and 24 h live (2026-11-20): 10
    ; "claimed" lines for quests not finished, one every visit.
    static ClaimBackoffMin := [60, 120, 240]
    static NextMaxMs := 1400      ; after >: the next quest's text shows (read twice the same) within this
    static SkillRe := "i)t[ao]unt|b[ao]rr[ao]ge|nothing|imp[ao][lI1]e|de[ao]deye|voidrush|rkm[ao]t"   ; Eden's skill list
    ; the same names through the game-font fold (GameText): its "m" reads
    ; "rn" ('orkrnotl' = Darkmatter, real frame
    ; quest_button_accept_skills_toast_1440; live 'Oorkmo', 'Oarkmn' 11-19)
    static SkillWords := ["taunt", "barrage", "nothing", "impale", "deadeye", "voidrush", "rkmat", "arkm"]
    static SkillHit(t) => RegExMatch(String(t), QuestsTask.SkillRe) > 0 || GameText.HasAny(t, QuestsTask.SkillWords)
    static AfterCardMs := 1200     ; after a catch card closed, before E
    static WalkTries := 2          ; respawn + walk + E when the board did not open
    static OpenWaitMs := 2000      ; board text must appear within this after E
    static PollMs := 250
    static TitleUp := 130          ; px above quest_board_rect that hold the quest title
    ; the game font's Q reads as O ("No Ouests to ...", live 2026-11-18 06:07)
    ; Its small line "There's no quest to see. (Quests are created in every
    ; 1 hour)" read through Eden's skill list (NoticeInk): 'no queguuo gee.
    ; ... rn every I nour' (real frame quest_notify_noquests_skills_1440)
    static NoQuestRe := "i)\bno\b.{0,20}\b[qo0]uests?\b|\b[qo0]uests?\b.{0,30}\b(?:empty|come back|none)\b|\bno\s+q[uo]e|\bev[ae]ry\s+\S{1,2}\s+[nh]?[o0]ur\b"
    ; the notification lies UNDER Eden's skill list (live 2026-11-18 09:51 -
    ; 09:57: the board was empty, the read was 'Cut Into Nothing Impole' and
    ; the board walked to twice): its white words alone, at 2x
    static NoticeInk := 230
    static Button := {dx: -120, dy: -30, w: 240, h: 60}   ; OCR box around quest_accept
    static ExitBox := {dx: -120, dy: -30, w: 240, h: 60}  ; OCR box around quest_close
    static ExitRe := "i)ex[il1|]t"

    name := "quests"
    priority := 5

    __New(deps := "") {
        this._env := TaskEnv(deps)
        this._notice := ""      ; last notification text seen while waiting for the board
        this._btnRaw := ""      ; the last button read (the words, not the verdict)
        this._held := Map()     ; quest key -> {until: env.Now() ms, n: tries} (ClaimBackoffMin)
        this._found := ""       ; the board's steps found on screen this visit (_FindBoard)
        this._foundWins := false    ; ... used instead of the recorded ones (they read nothing)
        ; deps "cards": (ctx) => true when it closed a fishing catch card (App:
        ; the fishing task's leftovers); "" = none
        this._cards := (IsObject(deps) && deps.HasOwnProp("cards")) ? deps.cards : ""
        ; the button's colour (ButtonColour): read from the screen in the
        ; real task, from deps "rect" in tests; a faked ocr without one: none
        this._colourOn := !(IsObject(deps) && deps.HasOwnProp("ocr")) || (IsObject(deps) && deps.HasOwnProp("rect"))
    }

    CanRun(state) {
        env := this._env
        if (IsObject(env.cfg) && !env.cfg.Get("quests.enabled", 1))
            return false
        return env.Route(IsObject(env.cfg) ? env.cfg.Get("quests.route", "quest_board") : "") != ""
    }

    Run(ctx) {
        env := this._env
        steps := env.Route(IsObject(env.cfg) ? env.cfg.Get("quests.route", "quest_board") : "")
        if (steps == "")
            return 0
        ; not recorded: "" until the board is found on screen (_FindBoard)
        this._found := "", this._foundWins := false
        rect := env.cal.Rect("quest_board_rect")
        area := IsObject(rect) ? QuestsTask.Panel(rect) : ""

        done := []
        io := env.io
        ; A preempt (a higher task is due) also makes ctx.ShouldStop() true,
        ; yet the board must still be closed and the player respawned: the
        ; next task would start with the board open (2026-10-27 review).
        ; Those steps use CleanupCtx and are skipped only on a real halt
        ; (F3 / pause / Roblox not in front): then nothing is sent.
        cc := CleanupCtx(ctx)
        away := false                       ; left spawn: respawn at the end
        try {
            ; a walk that missed the board (another player's boat in the way,
            ; a card over the screen after a stop mid-cast: live 2026-11-11)
            ; gets one more respawn + walk before the run gives up
            oldMode := Screen.Mode
            opened := 0
            Loop QuestsTask.WalkTries {
                if (A_Index > 1)
                    env.Log(this._NoBoardReason() " - walking there once more")
                if !Input.ResetToSpawn(ctx, io) {
                    ; said why (a silent quests run at 1366x768, 2026-11-11)
                    if !ctx.ShouldStop()
                        env.Log("quests: the respawn failed (" (Input.LastResetError != "" ? Input.LastResetError : "no reason given") "): board not tried")
                    return 0
                }
                away := true
                if !Input.PlayRoute(steps, ctx, io) {
                    if !ctx.ShouldStop()
                        env.Log("quests: the walk to the board did not finish: board not tried")
                    return 0
                }
                ; a catch card over the screen (a line left out when the macro was
                ; stopped, live 1920x1080 2026-11-11): E did nothing under it, and
                ; an E after it closed cast Eden's dash: close it before E
                ; (E right after the close still did nothing, three times live: the
                ; board's prompt comes back a moment later)
                if (this._ClearCard(cc, Screen.Mode) && !env.Wait(QuestsTask.AfterCardMs, ctx))
                    return 0
                Input.Key(QuestsTask.OpenKey, 80, io)
                ; the quest panel scales by height and hugs the right edge where
                ; the rest stretches (16:10, live 1440x900): the board phase maps
                ; in Screen mode "RH"; its Exit and > buttons stretch (converted)
                Screen.Mode := "RH"
                try {
                    opened := this._WaitOpen(ctx, area)
                    if (opened = 1 && IsObject(area) && !this._foundWins)
                        CalHealth.Ok("quest_board_rect", area)
                    ; recorded, but nothing read in it: is the board on
                    ; screen somewhere else? (one look; the game's "no
                    ; quests" notification already answered it)
                    if (opened = 0 && IsObject(area) && !RegExMatch(this._notice, QuestsTask.NoQuestRe) && this._FindBoard(true)) {
                        CalHealth.Fail("quest_board_rect", "no quest text read in it; the board was found elsewhere on screen", area)
                        opened := 1
                    }
                    if (opened = 1 && IsObject(this._found) && (this._foundWins || !IsObject(area)))
                        area := QuestsTask.Panel(this._found["quest_board_rect"])
                } finally
                    Screen.Mode := oldMode
                if (opened != 0 || RegExMatch(this._notice, QuestsTask.NoQuestRe))
                    break                           ; open, stopped, or the game says empty
            }
            Screen.Mode := "RH"
            try {
                if (opened < 0) {
                    ; told to stop while the board was opening: close it if it is up
                    if !CleanupCtx.Halted(ctx)
                        this._CloseBoard(cc, this._CloseRH(), area)
                    return 0
                }
                if !opened {
                    env.Log(this._NoBoardReason())
                    return 0
                }
                done := this._Pass(ctx, area)
                if !CleanupCtx.Halted(ctx)
                    this._CloseBoard(cc, this._CloseRH(), area)
            } finally
                Screen.Mode := oldMode
        } finally {
            if (away && !CleanupCtx.Halted(ctx) && env.RespawnAfter())
                Input.ResetToSpawn(cc, io)
        }
        if (done.Length > 0) {
            desc := ""
            for line in done
                desc .= (desc = "" ? "" : "`n") "- " line
            env.Report("quests", "Quest board", desc)
        }
        return done.Length
    }

    ; Exit only while the board is up (panel text or the Exit word reads):
    ; a click on an empty spot can go through into the world and open a
    ; Roblox purchase prompt (live 2026-11-02), closed with Esc after it.
    _CloseBoard(ctx, closePt, area) {
        env := this._env
        if (!IsObject(closePt) || !IsObject(area)) {
            ; a step that is not recorded and was not found yet: looked for
            ; now (the board may have been seen while it was still opening,
            ; or the run was told to stop before it was)
            if this._FindBoard(this._foundWins) {
                if !IsObject(area)
                    area := QuestsTask.Panel(this._found["quest_board_rect"])
                if !IsObject(closePt)
                    closePt := this._CloseRH()
            }
            if !IsObject(area)
                return env.Log("quests: the board is not on screen (not calibrated, not found): Exit not clicked")
            if !IsObject(closePt)
                return env.Log("quests: Exit not clicked: quest_close is not calibrated and the Exit button was not found on screen")
        }
        if ((why := env.Unsafe("quests")) != "")
            return env.Log("quests: Exit not clicked: " why)
        e := QuestsTask.ExitBox
        if (Trim((env.ocrFn)(area.x, area.y, area.w, area.h)) = ""
            && !RegExMatch((env.ocrFn)(closePt.x + e.dx, closePt.y + e.dy, e.w, e.h), QuestsTask.ExitRe))
            return env.Log("quests: the board is not open (no quest text, no Exit button): Exit not clicked")
        env.Click(closePt)
        env.Log("quests: closed the board")
        env.Wait(QuestsTask.SettleMs, ctx)
        env.BuyPrompt("quests")
    }

    ; A board step: the recorded one, else the one found on screen this
    ; visit; the found one first when the recorded panel read nothing
    ; (_foundWins). "" = neither.
    _Step(id) {
        f := (IsObject(this._found) && this._found.Has(id)) ? this._found[id] : ""
        if (this._foundWins && IsObject(f))
            return f
        v := ""
        try v := (id = "quest_board_rect") ? this._env.cal.Rect(id) : this._env.cal.Point(id)
        return IsObject(v) ? v : f
    }

    ; quest_close as the board phase clicks it (Exit stretches: "S" -> "RH")
    _CloseRH() {
        pt := this._Step("quest_close")
        return IsObject(pt) ? Screen.Convert(pt, "S", "RH") : ""
    }

    ; The board found on screen (AutoCal; called in the board phase, Screen
    ; mode "RH"): the panel from "Objects" and its buttons, checked by the
    ; task's own read of the panel found; Exit and the > arrow read in mode
    ; "S" (they stretch), the arrow only when its pixels are an arrow
    ; button's. wins: the recorded steps read nothing, the found ones are
    ; used instead. -> true when the panel was found (this._found set)
    _FindBoard(wins := false) {
        env := this._env
        panel := AutoCal.QuestPanel(env.Lines())
        if !IsObject(panel)
            return false
        a := QuestsTask.Panel(panel.rect)
        if !QuestsTask.PanelUp((env.ocrFn)(a.x, a.y, a.w, a.h))
            return false
        f := Map("quest_board_rect", panel.rect, "quest_accept", panel.accept, "quest_dismiss", panel.dismiss)
        ex := AutoCal.QuestExit(Screen.WithMode("S", () => env.Lines()))
        if IsObject(ex) {
            f["quest_close"] := ex.close
            if this._colourOn {
                b := AutoCal.Quest.arrowBox, px := ""
                try px := Screen.WithMode("S", () => (env.rectFn)(ex.next.x - b // 2, ex.next.y - b // 2, b, b))
                if AutoCal.IsArrow(px)
                    f["quest_next"] := ex.next
            }
        }
        first := !IsObject(this._found)
        this._found := f
        this._foundWins := wins ? true : false
        if first
            env.Log("quests: the board found on screen (panel at " panel.rect.x "," panel.rect.y
                . (f.Has("quest_close") ? ", Exit at " f["quest_close"].x "," f["quest_close"].y : ", Exit not read")
                . (f.Has("quest_next") ? ", > at " f["quest_next"].x "," f["quest_next"].y : ", > not seen") ")"
                . (wins ? ": nothing read in the calibrated quest_board_rect, the steps found are used for this visit" : ": its steps that are not calibrated are placed from it"))
        return true
    }

    ; quest_board_rect grown upwards by TitleUp (the title sits above the
    ; "Objects" box the user usually marks).
    static Panel(rect) {
        y := Max(0, rect.y - QuestsTask.TitleUp)
        return {x: rect.x, y: y, w: rect.w, h: rect.h + (rect.y - y)}
    }

    ; Identity of the quest on screen: the letters of its title (first
    ; non-empty OCR line). Stars and objective text are left out: they OCR
    ; differently from read to read.
    ; The game font's k reads "l<" on one read and k on the next, its a
    ; reads o: 'Minnow Rookie' then 'Minnow Rool<ie' was one quest claimed
    ; twice on one board (live 2026-11-20). Both are folded.
    static Key(text) => StrReplace(RegExReplace(StrLower(GameText.FixK(QuestsTask.Title(text))), "[^a-z]+"), "a", "o")

    ; Minutes left before the quest's Claim Rewards is tried again (0 = now)
    _HeldMin(key) {
        if !this._held.Has(key)
            return 0
        left := this._held[key].until - this._env.Now()
        return (left > 0) ? Ceil(left / 60000) : 0
    }

    ; Claim Rewards (or an unread button) changed nothing: wait longer each
    ; time -> the minutes
    _Hold(key) {
        n := this._held.Has(key) ? this._held[key].n + 1 : 1
        steps := QuestsTask.ClaimBackoffMin
        mins := steps[Min(n, steps.Length)]
        this._held[key] := {until: this._env.Now() + mins * 60000, n: n}
        return mins
    }

    ; What the game says after a click that changed nothing (notify_rect;
    ; "" = nothing read, or Eden's skill list): only for the log
    _Said() {
        env := this._env
        n := env.cal.Rect("notify_rect")
        if !IsObject(n)
            return ""
        t := ""
        try t := Trim(RegExReplace(String((env.ocrFn)(n.x, n.y, n.w, n.h)), "\s+", " "))
        if (t = "" || QuestsTask.SkillHit(t))
            return ""
        return "; the game says '" SubStr(t, 1, 60) "'"
    }

    ; First non-empty line (the title) for the log.
    static Title(text) {
        for line in StrSplit(String(text), "`n", "`r")
            if (Trim(line) != "")
                return SubStr(Trim(line), 1, 40)
        return ""
    }

    ; The quest panel's text: "Objects", or a title's worth of letters. A
    ; scrap the world gives ('lil' off a house sign, live 2026-11-18 10:07)
    ; is no board: it was taken as open and the "No Quests" notification
    ; under it was never read.
    static PanelUp(t) => RegExMatch(String(t), "i)[o0]bjects") || StrLen(RegExReplace(String(t), "[^A-Za-z]")) >= 6

    ; -> 1 board text seen, 0 not within OpenWaitMs, -1 stopped.
    _WaitOpen(ctx, area) {
        env := this._env
        if !env.Wait(QuestsTask.SettleMs, ctx)
            return -1
        this._notice := ""
        n := env.cal.Rect("notify_rect")
        waited := 0
        Loop {
            ; no recorded panel: looked for on screen (_FindBoard)
            if (IsObject(area) ? QuestsTask.PanelUp((env.ocrFn)(area.x, area.y, area.w, area.h)) : this._FindBoard())
                return 1
            if IsObject(n) {
                t := (env.ocrFn)(n.x, n.y, n.w, n.h)
                if (Trim(t) != "")
                    this._notice := t
                if RegExMatch(t, QuestsTask.NoQuestRe)
                    return 0                        ; the game says the board is empty
                if (Trim(t) != "") {                ; something there (the skill list?): its white words alone
                    k := ""
                    try k := String((env.inkFn)(n.x, n.y, n.w, n.h, 2, QuestsTask.NoticeInk))
                    if RegExMatch(k, QuestsTask.NoQuestRe) {
                        this._notice := k
                        return 0
                    }
                }
            }
            if (waited >= QuestsTask.OpenWaitMs)
                return 0
            if !env.Wait(QuestsTask.PollMs, ctx)
                return -1
            waited += QuestsTask.PollMs
        }
    }

    ; deps "cards" in the screen mode the rest of the game maps in -> true
    ; when a catch card was closed
    _ClearCard(ctx, mode) {
        f := this._cards
        if !IsObject(f)
            return false
        try
            return Screen.WithMode(mode, () => f.Call(ctx)) ? true : false
        return false
    }

    ; Why the board is not open: the game's "no quests" notification, or not there.
    _NoBoardReason() {
        env := this._env
        t := this._notice
        if (t != "") {
            if RegExMatch(t, QuestsTask.NoQuestRe)
                return "quests: the board has no quests right now (game notification); nothing clicked"
            if (Trim(t) != "")
                return "quests: the board did not open (notification reads: '" SubStr(Trim(RegExReplace(t, "\s+", " ")), 1, 80) "'); nothing clicked"
        }
        return "quests: the board did not open after E (no quests, or the route missed it: try Test on Help > Routes); nothing clicked"
    }

    ; Word on the Accept / Claim Rewards button:
    ; "claim" | "active" (accepted / in progress) | "accept" | "".
    ; The game font draws "a" like "o" and l like I: "Claim Rewards" reads
    ; "Cloim Rewords" / "CIoim" (2026-10-27 review).
    ; Claim Rewards cut at the box's left edge reads 'aim Rewords' / 'loim
    ; Re%ords' / 'aim Revvrds' (real frames day1118, 2560x1440)
    static ClaimRe := "i)c[lI1|][ao]im|rew[ao]rd|[lI1|]?[ao]im\s*re|\bre\S{1,3}[ao]?rds?\b"
    static ActiveRe := "i)accepted|in progress|[ao]ctive|tr[ao]cking"
    ; 'Accep t' (split by the skill list), and the halves the night of
    ; 2026-11-18 read: 'ccep', 'cc:eap', 'AcceOVrl<', 'AccegL', '-xcceel'.
    ; No other word on that spot (Claim Rewards, Dismiss, Eden's skills)
    ; holds "cce".
    static AcceptRe := "i)a\s?c\s?c\s?e\s?p\s?t|cc\W?e"

    ; The verdict of one button read -> "claim" | "active" | "accept" | ""
    static WordOf(t) {
        t := String(t)
        if RegExMatch(t, QuestsTask.ClaimRe)
            return "claim"
        if RegExMatch(t, QuestsTask.ActiveRe)
            return "active"
        if RegExMatch(t, QuestsTask.AcceptRe)
            return "accept"
        return ""
    }

    _ButtonWord(pt) {
        env := this._env
        b := QuestsTask.Button
        t := (env.ocrFn)(pt.x + b.dx, pt.y + b.dy, b.w, b.h)
        this._btnRaw := String(t)
        w := QuestsTask.WordOf(t)
        ; the skill list's white names over it ('rkmot'): its green word
        ; alone (Accept is green; 'Accevi' at 2560x1440)
        if (w = "" && QuestsTask.SkillHit(t)) {
            g := String((env.inkFn)(pt.x + b.dx, pt.y + b.dy, b.w, b.h, 2, "g"))
            this._btnRaw .= " / green '" g "'"
            w := QuestsTask.WordOf(g)
            if (w = "active")
                w := ""
        }
        if (w = "active")
            return w
        ; the button's own colour (Accept green, Claim Rewards yellow): reads
        ; under a toast or the skill list, where the words do not. Claim's
        ; yellow also overrules a misread "accept": Dismiss never follows a
        ; yellow button (it would abandon a finished quest).
        c := this._ButtonColour(pt)
        if (c != "") {
            this._btnRaw .= " / " (c = "accept" ? "green" : "yellow") " button"
            if (w = "" || (w = "accept" && c = "claim"))
                w := c
        }
        return w
    }

    ; The Accept spot's pixels -> "accept" (green words, the Dismiss button's
    ; red beside them), "claim" (yellow) or "" (unknown / not checked).
    _ButtonColour(pt) {
        if !this._colourOn
            return ""
        b := QuestsTask.Button
        arr := "", dis := ""
        try arr := (this._env.rectFn)(pt.x + b.dx, pt.y + b.dy, b.w, b.h)
        if !(arr is Array && arr.Length = b.w * b.h)
            return ""
        dp := this._Step("quest_dismiss")
        if IsObject(dp)                     ; read like quest_accept (the panel's mode)
            try dis := (this._env.rectFn)(dp.x + b.dx, dp.y + b.dy, b.w, b.h)
        return QuestsTask.ButtonColour(arr, dis)
    }

    ; Pure: pixels (0xRRGGBB) of the button box (and of the Dismiss button's
    ; box, dis) -> "accept" | "claim" | "".
    ; Accept's word and frame are green (0,240,96; under Eden's skill list
    ; 48,160,48), Claim Rewards' yellow (245,226,58; under the skill list
    ; 110,95,30), on the panel's dark fill (real frames: ~7-14% text pixels
    ; of one colour, none of the other, 70%+ dark). Grass seen through the
    ; skill list is bluer (80,208,128) and has no dark fill. "accept" lets an
    ; unticked quest be dismissed, so it also needs the board's own Dismiss
    ; red beside it (a bright green wall behind the skill list, no board,
    ; read as green: live 2026-11-18 10:07). Under a toast AND the skill
    ; list the green is too faint to tell: "" (left alone).
    static ButtonColour(arr, dis := "") {
        n := arr.Length, g := 0, y := 0, d := 0
        if (n < 100)
            return ""
        for c in arr {
            r := (c >> 16) & 255, gr := (c >> 8) & 255, bl := c & 255
            if (gr >= 120 && gr - r >= 70 && bl * 2 <= gr)
                g++
            else if ((r >= 190 && gr >= 170 && bl <= 110 && Abs(r - gr) <= 70)
                || (r >= 80 && gr * 10 >= r * 7 && gr * 100 <= r * 105 && bl * 2 <= gr))
                y++
            if (Max(r, gr, bl) < 90)
                d++
        }
        if (d < n * 0.2)
            return ""
        lo := n * 0.02, hi := n * 0.3, other := n * 0.003
        if (y >= lo && y <= hi && g <= other)
            return "claim"
        if !(g >= lo && g <= hi && y <= other && dis is Array && dis.Length >= 100)
            return ""
        red := 0
        for c in dis {
            r := (c >> 16) & 255, gr := (c >> 8) & 255, bl := c & 255
            if (r >= 100 && r * 10 >= gr * 22 && r * 10 >= bl * 22)
                red++
        }
        return (red >= dis.Length * 0.02) ? "accept" : ""
    }

    ; -> Array of "accepted X" / "dismissed X" / "claimed rewards for X" strings.
    _Pass(ctx, area) {
        env := this._env
        quests := IsObject(env.cfg) ? env.cfg.Data("quests") : Map()
        dismissOn := IsObject(env.cfg) && env.cfg.Get("quests.dismissDisabled", 0)
        acceptPt := this._Step("quest_accept")
        nextPt := this._Step("quest_next")
        if IsObject(nextPt)                 ; > stretches (the board's own panel maps "RH")
            nextPt := Screen.Convert(nextPt, "S", Screen.Mode)
        done := []
        seen := Map()
        lastKey := ""
        pushed := false                     ; > already pressed while lastKey was shown
        Loop QuestsTask.MaxSteps {
            if ctx.ShouldStop()
                break
            text := (env.ocrFn)(area.x, area.y, area.w, area.h)
            key := QuestsTask.Key(text)
            if (key = "")
                break
            if seen.Has(key) {
                ; still on the quest just handled (a re-read glitched before >): press > once
                if (key = lastKey && !pushed && IsObject(nextPt)) {
                    env.Click(nextPt)
                    pushed := true
                    if !env.Wait(QuestsTask.SettleMs, ctx)
                        break
                    continue
                }
                break                       ; > did not move / went all the way round
            }
            seen[key] := true
            lastKey := key, pushed := false
            title := QuestsTask.Title(text)
            m := QuestMatch.Match(text, quests)
            word := IsObject(acceptPt) ? this._ButtonWord(acceptPt) : ""
            ; the game's "Potion Auto Added" toast (fixed px, bottom right)
            ; covers the button for a few seconds below 1440p (1366x768,
            ; 2026-11-11): read it again until it goes
            tries := 0
            ; An aura's skill list (Eden: Taunt, Darkmatter Barrage...) sits
            ; there for good: no wait for that (4 s a quest, live 2560x1440)
            while (word = "" && IsObject(acceptPt) && !QuestsTask.SkillHit(this._btnRaw)
                && tries++ < QuestsTask.ButtonTries) {
                if !env.Wait(QuestsTask.ButtonRetryMs, ctx)
                    break
                word := this._ButtonWord(acceptPt)
            }
            env.Log("quests: [" seen.Count "] '" title "' -> " ((m != "") ? m.name (m.enabled ? " (ticked)" : " (not ticked)") : "no match") ", button: " ((word != "") ? word : "? ('" SubStr(Trim(RegExReplace(this._btnRaw, "\s+", " ")), 1, 30) "')"))
            action := ""
            name := (m != "") ? m.name : title
            if (word = "accept")
                try this._held.Delete(key)      ; a new quest under that title
            held := this._HeldMin(key)
            claimable := (word = "claim" || (word = "" && m != "" && QuestMatch.IsComplete(text)))
            if (held && (claimable || (word = "" && m != "" && m.enabled)))
                ; Claim Rewards did nothing on it a while ago: not every visit
                env.Log("quests: left " name " alone (accepted, not finished at the last try: Claim Rewards again in " held " min)")
            else if claimable
                action := "turnin"
            else if (word = "active")
                env.Log("quests: " title " is already accepted")
            else if (m == "")
                env.Log("quests: left '" title "' alone (no quest in the list matches it)")
            else if m.enabled
                action := "accept"
            else if (dismissOn && word = "")
                ; the button word was not read: it may be Claim Rewards in a
                ; misread, and Dismiss would abandon a finished quest
                ; (2026-10-27 review). Never dismissed blind.
                env.Log("quests: left " m.name " alone (its button did not read: never dismissed blind)")
            else if dismissOn
                action := "dismiss"
            else
                env.Log("quests: left " m.name " alone (not ticked; never dismissed while quests.dismissDisabled = 0)")
            if (action != "") {
                id := (action = "dismiss") ? "quest_dismiss" : "quest_accept"   ; Claim Rewards = the Accept spot
                pt := this._Step(id)
                if (pt != "") {
                    ; an unread button is clicked only on the Accept spot (a
                    ; ticked quest): that spot holds Accept or Claim Rewards,
                    ; either is safe; Dismiss needs the word or the colour
                    env.Click(pt)
                    verb := (action = "turnin") ? "claimed rewards for" : (action = "accept") ? "accepted" : "dismissed"
                    done.Push(verb " " name)
                    ; a claim is only known after the click (the quest leaves)
                    env.Log("quests: " ((action = "turnin") ? "pressed Claim Rewards for" : verb) " " name (word = "" ? " (button unread: pressed the Accept / Claim Rewards spot)" : ""))
                } else {
                    env.Log("quests: skipped " action " for " name)
                }
                if !env.Wait(QuestsTask.SettleMs, ctx)
                    break
                if (action = "dismiss" && pt != "")
                    continue                    ; the board shows the next quest by itself
                ; a claim may remove the quest: move on only if it is still shown
                if (QuestsTask.Key((env.ocrFn)(area.x, area.y, area.w, area.h)) != key) {
                    if (pt != "" && (action = "turnin" || word = "")) {
                        ; gone: claimed (Accept keeps the quest on screen, so
                        ; an unread button that removed it was Claim Rewards)
                        try this._held.Delete(key)
                        done[done.Length] := "claimed rewards for " name
                        env.Log("quests: claimed rewards for " name)
                    }
                    continue
                }
                ; still shown after Claim Rewards: not finished yet (live
                ; 09:09 / 09:25: the same quest "claimed" visit after visit)
                if (action = "turnin" && pt != "") {
                    done.Pop()
                    env.Log("quests: " name " is not finished yet (it stayed on the board after Claim Rewards" this._Said() "): next try in " this._Hold(key) " min")
                } else if (action = "accept" && pt != "" && word = "") {
                    ; the unread button changed nothing to see: accepted now,
                    ; or an unfinished quest's Claim Rewards. Not pressed
                    ; blind again every visit.
                    this._Hold(key)
                }
            }
            if !IsObject(nextPt)
                break
            env.Click(nextPt)                   ; Accept / leave alone keep the quest on screen
            pushed := true
            if (this._WaitNext(area, key, ctx) < 0)
                break
        }
        return done
    }

    ; After >: the board shows another quest, the same key on two reads in a
    ; row (no half-drawn text), at most NextMaxMs; was a fixed SettleMs.
    ; -> 1 | 0 not within NextMaxMs (the loop's own read decides) | -1 stopped
    _WaitNext(area, oldKey, ctx) {
        env := this._env
        waited := 0, prev := ""
        Loop {
            if !env.Wait(QuestsTask.PollMs, ctx)
                return -1
            waited += QuestsTask.PollMs
            k := QuestsTask.Key((env.ocrFn)(area.x, area.y, area.w, area.h))
            ; 500 ms at least: the button can be drawn a frame after the title
            if (k != "" && k != oldKey && k = prev && waited >= 500)
                return 1
            prev := k
            if (waited >= QuestsTask.NextMaxMs)
                return 0
        }
    }
}
