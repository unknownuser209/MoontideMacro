#Requires AutoHotkey v2.0
; ---------------------------------------------------------------------------
; ReelPause: the slow-PC warning (2026-11-23). A tester caught 63 %: their PC
; stalled 0.6-1.6 s at a time in the reel minigame and every lost fish had a
; ~1 s pause in it. The macro's own mid-reel work is gone (Input.InReel), but
; a slow PC still stalls; this tells the user so, with what to try.
;
;   rp := ReelPause()
;   w := rp.Add({gap, grab, work, wait, lost}, now)
;       fed ONCE per reel, after it ended (never inside the reel loop):
;       gap   the reel's longest gap between two screen reads, ms ("max gap"
;             in the "fishing: reel ..." line)
;       grab / work / wait   the slowest screen capture / scan / sleep of
;             one pass ("slowest grab / work / wait")
;       lost  true when the fish got away
;     -> "" or a warning {n, of, longest, lost, part, text, advice}
;   rp.Reset()      a new session (App.Start): reels, the hour and Last cleared
;   ReelPause.Last  "" or the last warning this session (SetupCheck's row)
;   ReelPause.Part(grab, work, wait, gap) -> "grab" | "work" | "wait" | ""
;   ReelPause.Advice(part) -> what to try, plain words
;
; The rule: within the last Window (10) reels, at least NeedSlow (3) had a
; gap >= SlowMs (300 ms) or at least NeedBad (2) had >= BadMs (800 ms).
; Healthy PCs measure 47-94 ms max gaps; the tester's bad reels 600-1600 ms,
; and FishLogic already drops speed samples older than 250 ms as stale, so
; 300 ms is past what the reel controller rides out. Not before MinReels (5)
; reels this session (one bad start is not a slow PC), and at most once per
; GapMs (60 min).
; The part named: per slow reel, the biggest of grab / work / wait when it
; is at least half that reel's gap; named when it is that in more than half
; of the slow reels (else "" and the general advice).
; Pure logic: no UI, no input, no webhook.
; ---------------------------------------------------------------------------

class ReelPause {
    static Window := 10
    static SlowMs := 300
    static BadMs := 800
    static NeedSlow := 3
    static NeedBad := 2
    static MinReels := 5
    static GapMs := 60 * 60000
    static Last := ""

    __New() => this.Reset()

    Reset() {
        this.reels := []
        this.count := 0
        this.warnedAt := ""
        ReelPause.Last := ""
    }

    Add(r, now) {
        g := (k) => (IsObject(r) && r.HasProp(k) && IsNumber(r.%k%)) ? r.%k% : 0
        this.reels.Push({gap: g("gap"), grab: g("grab"), work: g("work"), wait: g("wait")
            , lost: (IsObject(r) && r.HasProp("lost") && r.lost) ? true : false})
        while (this.reels.Length > ReelPause.Window)
            this.reels.RemoveAt(1)
        this.count++
        if (this.count < ReelPause.MinReels)
            return ""
        if (this.warnedAt != "" && now - this.warnedAt < ReelPause.GapMs)
            return ""
        slow := [], bad := 0, longest := 0, lost := 0
        for x in this.reels {
            if (x.gap >= ReelPause.SlowMs) {
                slow.Push(x)
                lost += x.lost ? 1 : 0
                longest := Max(longest, x.gap)
            }
            if (x.gap >= ReelPause.BadMs)
                bad++
        }
        if (slow.Length < ReelPause.NeedSlow && bad < ReelPause.NeedBad)
            return ""
        this.warnedAt := now
        votes := Map()
        for x in slow {
            p := ReelPause.Part(x.grab, x.work, x.wait, x.gap)
            if (p != "")
                votes[p] := (votes.Has(p) ? votes[p] : 0) + 1
        }
        part := ""
        for p, n in votes
            if (n * 2 > slow.Length)
                part := p
        w := {n: slow.Length, of: this.reels.Length, longest: Round(longest), lost: lost, part: part, advice: ReelPause.Advice(part)}
        w.text := ReelPause.Text(w)
        ReelPause.Last := w
        return w
    }

    static Part(grab, work, wait, gap) {
        best := "", v := 0
        for p, ms in Map("grab", grab, "work", work, "wait", wait)
            if (IsNumber(ms) && ms > v)
                best := p, v := ms
        return (best != "" && v * 2 >= gap) ? best : ""
    }

    static Why := Map(
        "grab", "The screen capture was slow (the graphics card or a recording app was busy). ",
        "work", "The processor was busy. ",
        "wait", "Windows woke the macro late (the PC was busy or saving power). ")

    static Advice(part) {
        g := "lower Roblox graphics (Esc > Settings > Graphics Quality)"
        switch part {
            case "grab": return g ", turn off recording apps (OBS, Medal, Xbox Game Bar), close browsers and other games."
            case "work": return "close browsers, other games and heavy apps, " g ", plug in a laptop."
            case "wait": return "close other apps, plug in a laptop and set Windows' power mode to Best performance, " g "."
        }
        return g ", close browsers and other games, turn off recording apps, plug in a laptop."
    }

    ; "Your PC paused during 3 of the last 10 reels (longest 1200 ms), which
    ; can lose fish (2 got away). The processor was busy. Try: ..."
    static Text(w) {
        s := "Your PC paused during " w.n " of the last " w.of " reels (longest " w.longest " ms), which can lose fish"
        s .= w.lost ? " (" w.lost " got away). " : ". "
        if ReelPause.Why.Has(w.part)
            s .= ReelPause.Why[w.part]
        return s "Try: " w.advice
    }
}
