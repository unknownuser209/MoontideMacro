#Requires AutoHotkey v2.0
; ---------------------------------------------------------------------------
; UiStuck: the general "the game's UI is wedged" escape (2026-11-20 audit).
; A Memory Match board left open locked every Aura Storage and inventory use
; out for 6 h 25 min (00:12-06:39, 2026-11-20: 160 hunts and 25 merchant
; visits lost) and an empty aura search failed the obby 15 times in a row
; (13:54-16:17); only a rejoin cleared either, and nothing asked for one.
;
; Tasks say when a game window they need did not work, and when it did:
;   UiStuck.Fail(kind [, n])  one failure of `kind` ("aura storage",
;                             "inventory", "aura search", "memory match
;                             board"); n counts as that many (a board known
;                             to be left open: UiStuck.TripAt, at once)
;   UiStuck.Ok(kind)          that kind worked: its failures are forgotten.
;                             Only its own: the storage opening fine says
;                             nothing about a search that lists nothing.
;   UiStuck.Due()             TripAt failures counted over all kinds
;   UiStuck.Text()            "4 in a row: aura storage 2, inventory 2"
;   UiStuck.Reset()           Start, and after the rejoin was asked
; The App asks the recovery task for a rejoin when Due (App._UiStuckCheck),
; at most once per App.UiRejoinGapMs. Static: one game, one count.
; ---------------------------------------------------------------------------

class UiStuck {
    static TripAt := 4
    static counts := Map()

    static Fail(kind, n := 1) {
        k := String(kind)
        UiStuck.counts[k] := (UiStuck.counts.Has(k) ? UiStuck.counts[k] : 0) + Max(1, Integer(n))
    }

    static Ok(kind) {
        if UiStuck.counts.Has(String(kind))
            UiStuck.counts.Delete(String(kind))
    }

    static Total() {
        n := 0
        for k, v in UiStuck.counts
            n += v
        return n
    }

    static Due() => UiStuck.Total() >= UiStuck.TripAt

    static Text() {
        s := ""
        for k, v in UiStuck.counts
            s .= (s = "" ? "" : ", ") k " " v
        return UiStuck.Total() " in a row: " s
    }

    static Reset() => UiStuck.counts := Map()
}
