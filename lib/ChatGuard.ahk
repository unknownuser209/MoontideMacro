#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\Screen.ahk
; ---------------------------------------------------------------------------
; ChatGuard: Roblox's chat window out of the way of a click, and back after.
;
; Sol's RNG's UI scales with the client (Screen), Roblox's chat window and
; top bar do NOT: they keep the same pixel size at every resolution
; (measured, client px from the client's top-left): the chat window x 8..483,
; y 64..420 (tab bar 64..100, messages 102.., input box at the bottom), the
; chat on / off button (speech bubble) in the top bar at 138, 32. At
; 2560x1440 nothing the macro clicks lies under it; at 1920x1080 and below
; the open chat covers the Aura Collections close (design 525, 158 ->
; 394, 119 at 1080p, every respawn's camera re-aim), the Aura Storage
; button (design 35, 534 -> 26, 400) and more: merchants and aura swaps
; broke there. ChatWatch needs the chat VISIBLE between tasks (merchant
; lines), so it is hidden only right before a click it would cover and
; shown again after the task (App._Tidy).
;
; Open or not is read on the button itself (real frames, tests\screens):
; open = a FILLED white bubble, closed = an OUTLINE bubble (dark inside);
; the unread badge sits top right, so only its left inside is read
; (Icon.inner), with the bubble's left edge (closed: still white), a band
; left of it (dark either way) and the tail under it (white either way).
; Anything else (the title screen has no chat button: its mic sits there)
; is unknown and nothing is clicked. Read through io.GrabScreen (SCREEN px:
; the real io has it; test ios without it never hide anything).
;
;   ChatGuard.Covers(x, y [, anchor]) / Covers([x, y]) / Covers({x, y [, w, h]})
;       a DESIGN point / rect lands inside the chat window at the current
;       Screen mapping (through the client origin Screen.cx / cy, so a
;       windowed client works too)
;   ChatGuard.State(io) -> 1 open | 0 closed | -1 unknown (no GrabScreen,
;       no chat button there)
;   ChatGuard.IsOpen(io) -> State = 1
;   ChatGuard.ClearFor(io, ctx, targets*) -> Hide when any target is
;       covered, else 0 with nothing read or sent
;   ChatGuard.Hide(io, ctx) -> 1 hidden | 0 not open (or unknown): nothing
;       sent | 2 still open (or shift lock refused the click) | -1 stopped
;   ChatGuard.Restore(ctx, io, log) -> 1 shown again | 0 nothing to do (we
;       did not hide it, or it is open already) | 2 would not reopen
;       (logged, given up) | -1 stopped (tried again next time). Only
;       reopens a chat ChatGuard hid; io defaults to the one that hid it.
;   ChatGuard.Hidden() -> ChatGuard hid it and has not shown it again
;   ChatGuard.Reset()  forget (tests)
; Clicks on the button go through Input.ClickGuard (shift lock pins the
; cursor to the screen centre: the click would land in the world) and do
; not count in Input.Sent (they never move the player).
; ---------------------------------------------------------------------------

class ChatGuard {
    static Win := {x1: 8, y1: 64, x2: 483, y2: 420}       ; client px
    static Toggle := [138, 32]                             ; client px
    ; client px: one grab x 121..141, y 27..42; samples inside it
    static Grab := {x: 121, y: 27, w: 21, h: 16}
    static Icon := {inner: [130, 133, 27, 37], edge: [128, 129, 27, 37]
        , outside: [121, 124, 27, 37], tail: [137, 139, 41, 42]}
    static BrightLum := 170
    static HoverMs := 150         ; on the button before the click
    static SeeMs := 600           ; for the new state after a click
    static PollMs := 150
    static Tries := 2             ; clicks on the button before giving up
    static AfterHideMs := 400     ; after it reads closed, before the click it was in the way of
    static _hidden := false
    static _io := ""
    ; A chat hidden by a run that was then stopped (F3 sends nothing) or
    ; closed stayed hidden for good: the next run did not know it hid it and
    ; merchants never showed (live 2026-11-11). FlagPath (the App sets it,
    ; "" = off, tests) marks "we hid it" across runs; Restore reads it.
    static FlagPath := ""

    static Reset() {
        ChatGuard._hidden := false
        ChatGuard._io := ""
        ChatGuard._Mark(false)
    }

    static _Mark(on) {
        f := ChatGuard.FlagPath
        if (f = "")
            return
        try {
            if on {
                if !FileExist(f)
                    FileAppend("1", f)
            } else if FileExist(f)
                FileDelete(f)
        }
    }

    static Hidden() => ChatGuard._hidden

    static Covers(a, b := "", anchor := "C") {
        w := 0, h := 0
        if IsObject(a) {
            if (b != "")
                anchor := b
            if (a is Array) {
                x := a[1], y := a[2]
            } else {
                x := a.x, y := a.y
                if (HasProp(a, "w") && HasProp(a, "h"))
                    w := a.w, h := a.h
            }
        } else
            x := a, y := b
        p := Screen.Pt(x, y, anchor)
        q := (w || h) ? Screen.Pt(x + w, y + h, anchor) : p
        c := ChatGuard.Win
        x1 := p.x - Screen.cx, y1 := p.y - Screen.cy
        x2 := q.x - Screen.cx, y2 := q.y - Screen.cy
        return x2 >= c.x1 && x1 <= c.x2 && y2 >= c.y1 && y1 <= c.y2
    }

    static State(io) {
        if !(IsObject(io) && HasMethod(io, "GrabScreen"))
            return -1
        g := ChatGuard.Grab
        px := ""
        try px := io.GrabScreen(Screen.cx + g.x, Screen.cy + g.y, g.w, g.h)
        if !(px is Array && px.Length >= g.w * g.h)
            return -1
        i := ChatGuard.Icon
        inner := ChatGuard._Bright(px, i.inner), edge := ChatGuard._Bright(px, i.edge)
        out := ChatGuard._Bright(px, i.outside), tail := ChatGuard._Bright(px, i.tail)
        if (out > 0.25 || tail < 0.5)
            return -1
        if (inner >= 0.75)
            return 1
        if (inner <= 0.25 && edge >= 0.5)
            return 0
        return -1
    }

    static IsOpen(io) => ChatGuard.State(io) = 1

    ; share of bright px in client box [x1, x2, y1, y2] of a Grab
    static _Bright(px, box) {
        g := ChatGuard.Grab
        n := 0, lit := 0
        y := box[3]
        while (y <= box[4]) {
            x := box[1]
            while (x <= box[2]) {
                c := px[(y - g.y) * g.w + (x - g.x) + 1]
                lit += (0.299 * ((c >> 16) & 0xFF) + 0.587 * ((c >> 8) & 0xFF) + 0.114 * (c & 0xFF)) >= ChatGuard.BrightLum
                n++
                x++
            }
            y++
        }
        return n ? lit / n : 0
    }

    static ClearFor(io, ctx, targets*) {
        for t in targets
            if (IsObject(t) && ChatGuard.Covers(t))
                return ChatGuard.Hide(io, ctx)
        return 0
    }

    static Hide(io, ctx := "") {
        io := Input._Backend(io)
        if (ChatGuard.State(io) != 1)
            return 0
        Loop ChatGuard.Tries {
            r := ChatGuard._Click(io, ctx)
            if (r <= 0)
                return r ? -1 : 2
            ChatGuard._hidden := true, ChatGuard._io := io
            ChatGuard._Mark(true)
            r := ChatGuard._See(io, ctx, 0)
            if (r < 0)
                return -1
            if r {
                Input._Log("chat: hidden (it covers a button at " Screen.cw "x" Screen.ch "); shown again after the task")
                ; the window fades out after its button flips: a click right
                ; away still hit it (Aura Storage "did not open", 1366x768)
                return io.Wait(ChatGuard.AfterHideMs, ctx) ? 1 : -1
            }
        }
        Input._Log("chat: still open after " ChatGuard.Tries " clicks on its button")
        return 2
    }

    static Restore(ctx := "", io := "", log := "") {
        if (!ChatGuard._hidden && ChatGuard.FlagPath != "" && FileExist(ChatGuard.FlagPath))
            ChatGuard._hidden := true           ; an earlier run hid it
        if !ChatGuard._hidden
            return 0
        if !IsObject(io)
            io := ChatGuard._io
        if !IsObject(io)
            try io := Input._Backend("")
        if !IsObject(io) {
            ChatGuard.Reset()
            return 0
        }
        s := ChatGuard.State(io)
        if (s = 1) {                    ; open already (the user, or a toggle that came late)
            ChatGuard.Reset()
            return 0
        }
        if (s < 0)
            return 0                    ; nothing readable there now: next time
        Loop ChatGuard.Tries {
            r := ChatGuard._Click(io, ctx)
            if (r < 0)
                return -1
            if (r = 0)
                break
            r := ChatGuard._See(io, ctx, 1)
            if (r < 0)
                return -1
            if r {
                ChatGuard.Reset()
                ChatGuard._Log(log, "chat: shown again")
                return 1
            }
        }
        ChatGuard.Reset()
        ChatGuard._Log(log, "chat: would not open again: open it yourself (the merchant chat watch reads it)")
        return 2
    }

    static _Log(log, text) {
        if !IsObject(log)
            return Input._Log(text)
        try log(text)
    }

    ; One click on the chat button (fixed client px, as a design point for
    ; the io). -> 1 clicked | 0 refused (shift lock) | -1 stopped
    static _Click(io, ctx) {
        if (IsObject(ctx) && ctx.ShouldStop())
            return -1
        g := Input.ClickGuard(io, ctx, "the chat button")
        if (g <= 0)
            return g
        t := ChatGuard.Toggle
        p := Screen.Inv(Screen.cx + t[1], Screen.cy + t[2])
        io.MoveTo(p.x, p.y)
        if !io.Wait(ChatGuard.HoverMs, ctx)
            return -1
        io.ClickHere()
        return 1
    }

    ; Polls State until it is `want`, up to SeeMs. -> 1 | 0 | -1 stopped
    static _See(io, ctx, want) {
        waited := 0
        Loop {
            if !io.Wait(ChatGuard.PollMs, ctx)
                return -1
            waited += ChatGuard.PollMs
            if (ChatGuard.State(io) = want)
                return 1
            if (waited >= ChatGuard.SeeMs)
                return 0
        }
    }
}
