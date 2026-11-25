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
;                                onBoss   callable onBoss("s" | "p") per boss line
;                                onOrb    callable onOrb(name) per orb line
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
;                  And one report per merchant per ReportGapSec (15 min):
;                  an old line that misses a few OCR reads came back as an
;                  arrival every ~5 min (live 2026-11-24 15:06, 15:11 after a
;                  real Jester at 15:00: the teleporter said no merchant).
; The time source (deps.now) and OCR function (deps.ocr) are injectable.
; ---------------------------------------------------------------------------

class ChatWatch {
    static DedupeSec := 120
    ; a merchant came back no sooner than 19.6 min in 3 days of live logs
    ; (2026-11-22..24); stale lines came back 3.5..11.7 min after a report
    static ReportGapSec := 900
    static AbsentReads := 2
    static DefaultPollSec := 5
    static DefaultHoverMs := 150
    static NoHover := false      ; idle mode (App): never move the mouse, read the chat as it is

    __New(deps := "") {
        this._env := TaskEnv(deps)
        this._onFound := TaskEnv.Dep(deps, "onFound", "")
        this._onBoss := TaskEnv.Dep(deps, "onBoss", "")      ; onBoss("s" | "p")
        this._onOrb := TaskEnv.Dep(deps, "onOrb", "")        ; onOrb("Typhoon")
        this._bossAt := Map()        ; "s" / "p" -> ms of the last report (or of the start)
        this._bossLines := Map()     ; "s" / "p" -> boss lines the chat has shown (_CheckBoss)
        this._bossLinesAt := Map()   ; ... ms they were last read
        this._bossLow := Map()       ; ... reads in a row with fewer
        this._orbSeen := Map()       ; orb name -> ms of its last sighting
        this._orbAbsent := Map()     ; orb name -> reads in a row without it since
        this._bossPrimed := false    ; the first read only notes lines already in the chat
        this._lastPoll := ""
        this._hoverAt := ""          ; HoverAhead: ms the mouse went over the chat ("" = not hovered ahead)
        this._hoverPt := ""
        this._seen := Map()          ; name -> ms of last sighting
        this._reportAt := Map()      ; name -> ms of its last report (ReportGapSec)
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

    ; -> Map "s" / "p" -> how many lines of the OCR text name that boss
    static CountBoss(text) {
        n := Map()
        for line in StrSplit(String(text), "`n", "`r") {
            seen := Map()
            pos := 1
            while (pos := RegExMatch(line, ChatWatch.BossRe, &m, pos)) {
                b := (StrLower(m[1]) = "p") ? "p" : "s"
                if !seen.Has(b)
                    seen[b] := true, n[b] := n.Get(b, 0) + 1
                pos += m.Len
            }
        }
        return n
    }

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

    ; ORBS (2026-11-22, a tester: "Typhoon orb has spawned"): the Biome Orb
    ; of a weather biome, named in the chat. NOT SEEN YET: the game's line
    ; (no clip, wiki or guide quotes it). Guessed: "<Name> Orb" on one line
    ; with a spawn word after it (spawned / appeared / arrived / emerged),
    ; e.g. "A Typhoon Orb has spawned!". The game font reads o as 0 and a as
    ; o. A player typing "typhoon orb spawned" matches too (as for the
    ; bosses). Names known: Typhoon (the tester), Flame (HELL), Raincloud
    ; (RAINY); any other word before "Orb" is kept as read.
    static OrbRe := "i)\b([a-z][a-z0-9]{2,15})\s+[o0]rbs?\b[^\r\n]{0,40}?\b(?:sp[a@o]wn|[a@o]pp[e3][a@o]r|[a@o]rr[i1l!|]v|[e3]m[e3]rg)"
    static OrbKnown := [["Typhoon", "i)^typh[o0a][o0a]n$"], ["Flame", "i)^f[l1i|][a@o]m[e3]$"], ["Raincloud", "i)^r[a@o][i1l!|]ncl[o0a]ud$"]]
    ; a word before "orb" that names no orb ("the orb has spawned")
    static OrbNot := "i)^(?:the|biome|new|this|that|one|rare|another|any|some|your|our|their|his|her|its|and)$"
    static OrbGapSec := 120           ; gone from the chat this long (and AbsentReads reads) before the same orb again

    ; -> Array of orb names ("Typhoon", ...), one per orb named in the OCR text
    static DetectOrb(text) {
        found := []
        seen := Map()
        for line in StrSplit(String(text), "`n", "`r") {
            pos := 1
            while (pos := RegExMatch(line, ChatWatch.OrbRe, &m, pos)) {
                pos += m.Len
                name := ChatWatch.OrbName(m[1])
                if (name != "" && !seen.Has(name))
                    seen[name] := true, found.Push(name)
            }
        }
        return found
    }

    ; the word read before "orb" -> its name ("typhaon" -> "Typhoon"), "" = no orb's
    static OrbName(word) {
        word := String(word)
        if RegExMatch(word, ChatWatch.OrbNot)
            return "Biome"
        for k in ChatWatch.OrbKnown
            if RegExMatch(word, k[2])
                return k[1]
        if !RegExMatch(word, "i)^[a-z][a-z0-9]*$")
            return ""
        return StrUpper(SubStr(word, 1, 1)) StrLower(SubStr(word, 2))
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

    _PollMs() {
        env := this._env
        pollSec := ChatWatch.DefaultPollSec
        if IsObject(env.cfg)
            pollSec := env.cfg.Get("merchant.chatPollSec", ChatWatch.DefaultPollSec)
        if (!IsNumber(pollSec) || pollSec < 1)
            pollSec := ChatWatch.DefaultPollSec
        return pollSec * 1000
    }

    _Due(now) => (this._lastPoll == "" || now - this._lastPoll >= this._PollMs())

    ; HoverAhead(): the App, a moment before Check (fishing came back for
    ; the chat): the mouse goes over the chat now, so Check waits only what
    ; is left of merchant.chatHoverMs (the App's tidy reads fill the rest).
    ; Only when a read is due; never in idle mode (NoHover).
    HoverAhead() {
        env := this._env
        if (ChatWatch.NoHover || !this._Due(env.Now()))
            return false
        rect := env.cal.Rect("chat_rect")
        if !IsObject(rect)
            return false
        c := TaskEnv.Center(rect)
        env.io.MoveTo(c[1], c[2])                   ; hover only: no click, no typing
        this._hoverAt := env.Now(), this._hoverPt := c
        return true
    }

    ; The mouse still on the chat since HoverAhead (io.MousePos; an io
    ; without it: not known, so no)
    _StillHovered(c) {
        io := this._env.io
        if (this._hoverAt == "" || !HasMethod(io, "MousePos") || !IsObject(this._hoverPt))
            return false
        if (this._hoverPt[1] != c[1] || this._hoverPt[2] != c[2])
            return false
        p := ""
        try p := io.MousePos()
        return IsObject(p) && Abs(p.x - c[1]) <= 3 && Abs(p.y - c[2]) <= 3
    }

    Check() {
        env := this._env
        now := env.Now()
        if !this._Due(now)
            return []
        this._lastPoll := now

        rect := env.Rect("chat_rect")
        if (rect == "")
            return []
        ; idle mode (NoHover): the mouse is never moved; a faded chat is
        ; read as it is (its text stays, only its dark background fades)
        if !ChatWatch.NoHover {
            c := TaskEnv.Center(rect)
            ; Faded chat gets its dark background back < 150 ms after a hover
            ; (recon 2026-10-25); OCR over the bright sky degrades without it.
            hoverMs := ChatWatch.DefaultHoverMs
            if IsObject(env.cfg)
                hoverMs := env.cfg.Get("merchant.chatHoverMs", ChatWatch.DefaultHoverMs)
            if (!IsInteger(hoverMs) || hoverMs < 0)
                hoverMs := ChatWatch.DefaultHoverMs
            left := Integer(hoverMs)
            if this._StillHovered(c)                 ; HoverAhead: only the rest of the wait
                left := Max(0, left - (now - this._hoverAt))
            else
                env.io.MoveTo(c[1], c[2])           ; hover only: no click, no typing
            this._hoverAt := ""
            if (left > 0)
                env.io.Wait(left)
        }
        text := (env.ocrFn)(rect.x, rect.y, rect.w, rect.h)
        if (text == "")
            return []                           ; unknown: no action

        first := !this._bossPrimed
        this._bossPrimed := true
        this._CheckBoss(text, now, first)
        this._CheckOrb(text, now, first)
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
            if (this._reportAt.Has(name) && now - this._reportAt[name] < ChatWatch.ReportGapSec * 1000) {
                env.Log("chat: " name "'s arrival line again " Round((now - this._reportAt[name]) / 60000, 1) " min after it was reported: not visited (one visit per " Round(ChatWatch.ReportGapSec / 60) " min)")
                continue
            }
            this._reportAt[name] := now
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
    ; A spawn is a NEW line: more lines naming the boss than the chat has
    ; shown. The line of an old spawn stays in a quiet chat for hours, and
    ; with only the 15 min gap it was announced again, the boss dead and its
    ; biome over (live 2026-11-23 00:33:39 Sinister S. in HELL, 11-24
    ; 07:57:39 and 10:37:21 Sinister P. in SNOWY / RAINY). The lines shown
    ; drop to fewer only after AbsentReads reads and BossGapSec without them
    ; (an OCR miss now and then is no absence).
    _CheckBoss(text, now, first) {
        env := this._env
        counts := ChatWatch.CountBoss(text)
        bosses := []
        for b in ["s", "p"] {
            c := counts.Get(b, 0), had := this._bossLines.Get(b, 0)
            if (c > had) {
                this._bossLines[b] := c, this._bossLinesAt[b] := now, this._bossLow[b] := 0
                bosses.Push(b)
            } else if (c = had) {
                this._bossLinesAt[b] := now, this._bossLow[b] := 0
            } else {
                this._bossLow[b] := this._bossLow.Get(b, 0) + 1
                if (this._bossLow[b] >= ChatWatch.AbsentReads && now - this._bossLinesAt.Get(b, 0) >= ChatWatch.BossGapSec * 1000)
                    this._bossLines[b] := c, this._bossLinesAt[b] := now, this._bossLow[b] := 0
            }
        }
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

    ; An orb named in the chat -> onOrb, with the merchants' sliding dedupe
    ; (2026-11-22): orbs come every few biomes and their line stays in the
    ; chat, so a fixed gap would re-send a line still there. The same orb
    ; again only after it was gone OrbGapSec and AbsentReads reads.
    _CheckOrb(text, now, first) {
        env := this._env
        orbs := ChatWatch.DetectOrb(text)
        here := Map()
        for name in orbs
            here[name] := true
        for name, _ in this._orbSeen
            if !here.Has(name)
                this._orbAbsent[name] := (this._orbAbsent.Has(name) ? this._orbAbsent[name] : 0) + 1
        for name in orbs {
            suppressed := this._orbSeen.Has(name) && (now - this._orbSeen[name] < ChatWatch.OrbGapSec * 1000
                || (this._orbAbsent.Has(name) ? this._orbAbsent[name] : 0) < ChatWatch.AbsentReads)
            this._orbSeen[name] := now, this._orbAbsent[name] := 0
            if suppressed
                continue
            if (first && this._startOld) {
                env.Log("chat: a " name " orb line was already in the chat at the start: not announced")
                continue
            }
            env.Log("chat: " name " orb spawned (read in the chat)")
            if IsObject(this._onOrb)
                try (this._onOrb)(name)
        }
    }
}
