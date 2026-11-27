#Requires AutoHotkey v2.0
; ---------------------------------------------------------------------------
; ReelTrace: every pass of the last reels, for the support zip
; (logs\reel_trace.log). A tester lost 56 of 84 fish (2026-11-26): his video
; showed the arrow held just past the fish, while the reel line in macro.log
; only has totals. One line per pass:
;
;   t m p1-p2 fill empty target w dc
;     t       ms since the reel started
;     m       the arrow's x (0 = not found); p1-p2 the fish (0-0 = none)
;     fill    the click bar's colour (- = none); empty the empty level
;     target  ReelDecide's aim point (- = no decision); w its fish width
;     d c     decided to click (0/1), clicked (0/1: the click gap allows it)
;   x values are the reel's own (2560x1440 design) px; the header's x1 / x2
;   are where the strip's ends land on the client.
;
; Passes are kept in memory during the reel (no file work inside it); the
; file is written when the reel ends and again with the card's result.
; Only the last MaxReels reels are kept. Numbers only: nothing to scrub.
; Never throws (a file that cannot be written keeps the text in memory).
; ---------------------------------------------------------------------------

class ReelTrace {
    static MaxReels := 12
    ; a reel that never ends (the 9 s cap at ~10 ms a pass is ~900)
    static MaxPasses := 3000
    static Columns := "t m p1-p2 fill empty target w dc"

    __New(path, maxReels := 0) {
        this.path := path
        this.max := maxReels > 0 ? maxReels : ReelTrace.MaxReels
        this.reels := []            ; [{head, body}], oldest first
        this.cur := ""              ; the running reel's header ("" = none)
        this.lines := []
    }

    Begin(head) {
        this.cur := "=== reel " FormatTime(, "yyyy-MM-dd HH:mm:ss") " | " head
        this.lines := []
    }

    ; s: a FishLogic.ReelScan result; st: ReelDecide's state (tg, w)
    Add(t, s, st, decided, clicked) {
        if (this.cur = "" || this.lines.Length >= ReelTrace.MaxPasses)
            return
        fill := (s.fill = "") ? "-" : Format("{:06X}", s.fill)
        tg := st.HasProp("tg") ? Round(st.tg) : "-"
        w := st.HasProp("w") ? st.w : 0
        this.lines.Push(Round(t) " " s.m " " s.p1 "-" s.p2 " " fill " " s.empty " " tg " " w " " (decided ? 1 : 0) (clicked ? 1 : 0))
    }

    End(how) {
        if (this.cur = "")
            return
        body := ""
        for l in this.lines
            body .= l "`n"
        this.reels.Push({head: this.cur " | end " how, body: body})
        while (this.reels.Length > this.max)
            this.reels.RemoveAt(1)
        this.cur := "", this.lines := []
        this._Write()
    }

    ; The catch card's result for the last reel ("caught", "got away", ...)
    Outcome(text) {
        if !this.reels.Length
            return
        this.reels[this.reels.Length].head .= " | " text
        this._Write()
    }

    Text() {
        out := ""
        for r in this.reels
            out .= r.head "`n" ReelTrace.Columns "`n" r.body
        return out
    }

    _Write() {
        try {
            dir := RegExReplace(this.path, "\\[^\\]+$")
            if (dir != this.path && !DirExist(dir))
                DirCreate(dir)
            f := FileOpen(this.path, "w", "UTF-8")
            f.Write(this.Text())
            f.Close()
        }
    }
}
