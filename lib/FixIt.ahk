#Requires AutoHotkey v2.0
; ---------------------------------------------------------------------------
; FixIt (idea 10, 2026-11-13): watches the log for problems that keep coming
; back and turns them into a plain "how to fix it" card.
;
;   f := FixIt()
;   card := f.Seen(line)   -> the rule (a card to show) the FIRST time a rule
;                             reaches its count, else "" (once per rule until
;                             Reset / Dismiss)
;   f.Dismiss(key)         -> that card is not shown again this session
;   f.Reset()              -> counts cleared (App.Start)
;   f.QuietFor(key, now)   -> ms since the rule's line was last seen (Seen's
;                             `now`); -1 never seen. App closes a card whose
;                             line stopped coming (the problem is gone).
;   f.Forget(key)          -> the card may show again (it was closed because
;                             the problem went away, not dismissed)
;
; A rule: {key, re (log line regex), n (lines before the card), title, fix
; (what to do, plain words), page (a dashboard page to open, or ""), act
; (a "Fix it for me" action App knows, or "")}.
; Pure logic: no UI, no input.
; ---------------------------------------------------------------------------

class FixIt {
    static Rules := [
        {key: "notfs", re: "i)Paused: (Roblox not fullscreen|Moontide needs Roblox fullscreen|The Roblox window can't be used)", n: 1
            , title: "The Roblox window can't be used"
            , fix: "Roblox is minimized, too small or partly off the screen. Restore the window and keep it on the screen, or press F11 for fullscreen, then press F2 (or F1).", page: "", act: "fullscreen"},
        {key: "focus", re: "i)Paused: Roblox is not the active window", n: 2
            , title: "Another window keeps taking focus"
            , fix: "Something pulled Roblox to the back (the log line says what was in front). Close that app or turn off its overlay or toolbar, then press F2.", page: "Check", act: ""},
        {key: "nolink", re: "i)no (usable )?private server link", n: 1
            , title: "No private server link"
            , fix: "Without your private server link the macro cannot rejoin after a disconnect. Paste it in Settings > General (Private server).", page: "Settings", act: ""},
        {key: "badlink", re: "i)private server link refused", n: 1
            , title: "The private server link is not right"
            , fix: "Copy the link again from your private server's Share / Copy Link button. It starts with https://www.roblox.com/.", page: "Settings", act: ""},
        {key: "shift", re: "i)shift lock (may still be on|would not turn off)", n: 2
            , title: "The mouse is stuck in the middle"
            , fix: "The mouse is stuck in the middle of the screen. If a game window is open (a shop or Captain Flarg's dialog), close it: the macro rejoins by itself after 3 tries. Otherwise press Shift once in Roblox to turn shift lock off.", page: "", act: ""},
        {key: "rejoins", re: "i)rejoin limit reached", n: 1
            , title: "Roblox keeps disconnecting"
            , fix: "Check your internet and Roblox's status page. The macro tries again by itself in a few minutes.", page: "", act: ""},
        {key: "inventory", re: "i)the inventory did not open", n: 2
            , title: "The inventory did not open"
            , fix: "The inventory buttons are not where the macro expects. Open Help > Calibrate and press Apply preset, or record the inventory steps.", page: "Calibrate", act: ""},
        {key: "calib", re: "i)not calibrated", n: 2
            , title: "A click spot is not set up"
            , fix: "A step the macro needs has no calibration. Open Help > Calibrate and press Apply preset (or record the step named in the log).", page: "Calibrate", act: ""},
        {key: "webhook", re: "i)Webhook .*send failed .*giving up", n: 1
            , title: "A Discord webhook does not work"
            , fix: "Discord refused a message. Copy the webhook link again in Discord (channel settings > Integrations > Webhooks) and paste it in Discord & Clips > Discord.", page: "Webhooks", act: ""},
        {key: "update", re: "i)Update check failed", n: 2
            , title: "Updates cannot be checked"
            , fix: "The macro could not reach GitHub. Check your internet, or download the newest zip from the releases page by hand.", page: "", act: ""},
        ; lib\tasks\ReelPause.ahk (FishingTask._PauseCheck): at most once an hour
        {key: "reelpause", re: "i)fishing: slow PC: ", n: 1
            , title: "Reels keep pausing on this PC"
            , fix: "Your PC froze for a moment during several fishing reels, which loses fish. Lower Roblox graphics (Esc > Settings > Graphics Quality), close browsers and other games, turn off recording apps, plug in a laptop.", page: "Check", act: ""}
    ]

    __New() {
        this.counts := Map()
        this.shown := Map()
        this.last := Map()
    }

    Seen(line, now := "") {
        for r in FixIt.Rules {
            if !RegExMatch(String(line), r.re)
                continue
            this.last[r.key] := (now = "") ? A_TickCount : now
            n := (this.counts.Has(r.key) ? this.counts[r.key] : 0) + 1
            this.counts[r.key] := n
            if (n >= r.n && !this.shown.Has(r.key)) {
                this.shown[r.key] := true
                return r
            }
            return ""
        }
        return ""
    }

    Dismiss(key) {
        this.shown[key] := true
    }

    ; counts start over (a new run); a dismissed / shown card may come back
    Reset() {
        this.counts := Map()
        this.shown := Map()
        this.last := Map()
    }

    QuietFor(key, now) => this.last.Has(key) ? now - this.last[key] : -1

    Forget(key) {
        for m in [this.counts, this.shown, this.last]
            if m.Has(key)
                m.Delete(key)
    }

    static Rule(key) {
        for r in FixIt.Rules
            if (r.key = key)
                return r
        return ""
    }
}
