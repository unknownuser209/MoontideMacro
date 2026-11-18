#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\LogWatch.ahk
#Include %A_LineFile%\..\tasks\TaskEnv.ahk
; ---------------------------------------------------------------------------
; ChatWatch: fallback merchant detection by OCR of the Roblox chat box
; (spec 4.5). Never types, never clicks: it only MOVES the mouse over the
; chat rect (so chat does not fade) and reads it.
;
;   cw := ChatWatch(deps)      deps as TaskEnv (cfg, log, io, cal, ocr, now,
;                              webhook) plus:
;                                onFound  callable onFound(name) per new hit
;   cw.Check()  -> Array of newly detected merchant names ("Mari"/"Jester")
;                  Call it as often as you like (e.g. every scheduler tick):
;                  it only reads the chat every merchant.chatPollSec seconds
;                  (cfg, default 5). After the hover it waits
;                  merchant.chatHoverMs (cfg, default 150) before the OCR so
;                  a faded chat has its background back (ChatWatch.NoHover,
;                  idle mode: no hover and no wait, the chat is read as it
;                  is). Nothing happens, and
;                  "" OCR is treated as
;                  unknown, if chat_rect is not calibrated (logged, errors
;                  webhook once).
;   ChatWatch.Detect(text) -> Array of merchant names found in OCR text.
;                  Same rule as the log: merchant name (case-sensitive whole
;                  word) plus an arrival word, on the same line
;                  (LogWatch.ParseMerchant), one hit per merchant per read.
;   Dedupe (sliding): a merchant is reported again only after it has
;                  been ABSENT from the chat reads for ChatWatch.DedupeSec
;                  (120 s) AND from at least ChatWatch.AbsentReads (2)
;                  reads in a row; each sighting, reported or not, restarts
;                  the window. Measured on the injected clock. (Live
;                  2026-11-10: the chat is not read during long tasks, so
;                  one old "Mari has arrived" line that never left the chat
;                  was re-reported after every hunt: 3 empty visits in 8 min.)
; The time source (deps.now) and OCR function (deps.ocr) are injectable.
; ---------------------------------------------------------------------------

class ChatWatch {
    static DedupeSec := 120
    static AbsentReads := 2
    static DefaultPollSec := 5
    static DefaultHoverMs := 150
    static NoHover := false      ; idle mode (App): never move the mouse, read the chat as it is

    __New(deps := "") {
        this._env := TaskEnv(deps)
        this._onFound := TaskEnv.Dep(deps, "onFound", "")
        this._onBoss := TaskEnv.Dep(deps, "onBoss", "")      ; onBoss("s" | "p")
        this._bossAt := Map()        ; "s" / "p" -> ms of the last report (or of the start)
        this._bossPrimed := false    ; the first read only notes lines already in the chat
        this._lastPoll := ""
        this._seen := Map()          ; name -> ms of last sighting
        this._absent := Map()        ; name -> reads in a row without it since
        ; startOld (the App): at Start every merchant counts as seen just
        ; now, so an arrival line already in the chat is not visited until it
        ; has left the chat (the usual dedupe: AbsentReads reads, DedupeSec)
        ; and shows again. Live 2026-11-11: an hour-old "Mari has arrived"
        ; sent the macro off with a Merchant Teleporter at every start (the
        ; first read alone was not enough: it missed the line, a later one
        ; read it). Fresh arrivals also come from the Roblox log (LogWatch).
        this._startOld := TaskEnv.Dep(deps, "startOld", false)
        this._noted := Map()
        if this._startOld
            this.Rebase()
    }

    ; BOSSES (Halloween 2026): "Sinister S." (GRAVEYARD) and "Sinister P."
    ; spawn in the server; the user saw one with hunting off and got no
    ; message (2026-11-15). Any chat line naming one counts (the game font
    ; draws i like l / 1). NOT SEEN YET: the exact wording of the game's line.
    ; The aura "Sinister" in a roll line ("... found Sinister, chance ...")
    ; has no S / P right after it: no match.
    static BossRe := "i)\bs[i1l!|]n[i1l!|]st[e3]r\s*[.,:]?\s*([sp]|5(?=\s*\.))(?![a-z0-9])"
    static BossGapSec := 900          ; one report per boss per 15 min

    ; -> Array of "s" / "p", one per boss named in the OCR text
    static DetectBoss(text) {
        found := []
        seen := Map()
        pos := 1
        while (pos := RegExMatch(String(text), ChatWatch.BossRe, &m, pos)) {
            b := (StrLower(m[1]) = "p") ? "p" : "s"
            if !seen.Has(b)
                seen[b] := true, found.Push(b)
            pos += m.Len
        }
        return found
    }

    static Names := ["Mari", "Jester"]
    Rebase() {
        now := this._env.Now()
        for name in ChatWatch.Names
            this._seen[name] := now, this._absent[name] := 0
        this._noted := Map()
        this._bossPrimed := false
    }

    static Detect(text) {
        found := []
        seen := Map()
        for line in StrSplit(String(text), "`n", "`r") {
            who := LogWatch.ParseMerchant(line)
            if (who != "" && !seen.Has(who)) {
                seen[who] := true
                found.Push(who)
            }
        }
        return found
    }

    Check() {
        env := this._env
        now := env.Now()
        pollSec := ChatWatch.DefaultPollSec
        if IsObject(env.cfg)
            pollSec := env.cfg.Get("merchant.chatPollSec", ChatWatch.DefaultPollSec)
        if (!IsNumber(pollSec) || pollSec < 1)
            pollSec := ChatWatch.DefaultPollSec
        if (this._lastPoll !== "" && now - this._lastPoll < pollSec * 1000)
            return []
        this._lastPoll := now

        rect := env.Rect("chat_rect")
        if (rect == "")
            return []
        ; idle mode (NoHover): the mouse is never moved; a faded chat is
        ; read as it is (its text stays, only its dark background fades)
        if !ChatWatch.NoHover {
            c := TaskEnv.Center(rect)
            env.io.MoveTo(c[1], c[2])               ; hover only: no click, no typing
            ; Faded chat gets its dark background back < 150 ms after a hover
            ; (recon 2026-10-25); OCR over the bright sky degrades without it.
            hoverMs := ChatWatch.DefaultHoverMs
            if IsObject(env.cfg)
                hoverMs := env.cfg.Get("merchant.chatHoverMs", ChatWatch.DefaultHoverMs)
            if (!IsInteger(hoverMs) || hoverMs < 0)
                hoverMs := ChatWatch.DefaultHoverMs
            env.io.Wait(Integer(hoverMs))
        }
        text := (env.ocrFn)(rect.x, rect.y, rect.w, rect.h)
        if (text == "")
            return []                           ; unknown: no action

        this._CheckBoss(text, now)
        hits := []
        names := ChatWatch.Detect(text)
        here := Map()
        for name in names
            here[name] := true
        for name, _ in this._seen {
            if !here.Has(name)
                this._absent[name] := (this._absent.Has(name) ? this._absent[name] : 0) + 1
        }
        for name in names {
            ; Sliding window: every sighting refreshes the stamp, so a line
            ; that stays visible (the hover keeps chat from fading) never
            ; re-fires; it fires again only after >= DedupeSec without it.
            ; a long gap without reads is not an absence: it must also be
            ; missing from AbsentReads reads in a row
            suppressed := this._seen.Has(name) && (now - this._seen[name] < ChatWatch.DedupeSec * 1000
                || (this._absent.Has(name) ? this._absent[name] : 0) < ChatWatch.AbsentReads)
            this._seen[name] := now, this._absent[name] := 0
            if suppressed {
                if (this._startOld && !this._noted.Has(name)) {
                    this._noted[name] := true
                    env.Log("chat: " name "'s arrival line is an old one (in the chat since the start): not visited")
                }
                continue
            }
            hits.Push(name)
            env.Log("chat: " name " detected")
            if IsObject(this._onFound)
                (this._onFound)(name)
        }
        return hits
    }

    ; A boss named in the chat -> onBoss, once per boss per BossGapSec. With
    ; startOld, a line already there at the first read is only noted (an old
    ; spawn is not announced at every start).
    _CheckBoss(text, now) {
        env := this._env
        bosses := ChatWatch.DetectBoss(text)
        first := !this._bossPrimed
        this._bossPrimed := true
        for b in bosses {
            if (this._bossAt.Has(b) && now - this._bossAt[b] < ChatWatch.BossGapSec * 1000)
                continue
            this._bossAt[b] := now
            if (first && this._startOld) {
                env.Log("chat: a Sinister " StrUpper(b) ". line was already in the chat at the start: not announced")
                continue
            }
            env.Log("chat: Sinister " StrUpper(b) ". spawned (read in the chat)")
            if IsObject(this._onBoss)
                try (this._onBoss)(b)
        }
    }
}
