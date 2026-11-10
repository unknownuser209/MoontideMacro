#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\GameLists.ahk
; ---------------------------------------------------------------------------
; MatchLogic: the thinking half of the Memory Match task. Pure functions over
; a board; no screen, no clicks (the task reads tiles and flips them).
;
;   MatchLogic.Key(text)       "item|amount" off a tile's OCR text, or "" when
;                              the text has no letters. item = the first name
;                              of the reward tier it matches (GameLists.
;                              MatchTier), else its folded letters. amount =
;                              the last number (commas dropped, the font's
;                              O/o = 0 and I/l/| = 1 inside digits), else 1.
;   MatchLogic.Value(key)      lower is better: tier * 1000000 - Min(amount,
;                              999999). Tiers: GameLists.MatchRewards. The
;                              task's picture keys "w<width>#<n>" (MatchVision)
;                              -> the amount text width (narrow = rare).
;   MatchLogic.NewBoard(n)     n tiles (default 20), each a Map with "state"
;                              (hidden | seen | matched | unreadable) and "key".
;   MatchLogic.First(board, turnsLeft)         tile to flip first this turn.
;   MatchLogic.Second(board, first, turnsLeft) tile to flip second; call it
;                              after Record() wrote the first tile.
;   MatchLogic.Record(board, i, key)           seen + key, or unreadable
;                              when key is "".
;   MatchLogic.Matched(board, a [, b])         both tiles matched (b = 0: only
;                              a, a tile found green when flipped).
;
; CHOOSING FLIPS
;   First:  the most valuable pair of two seen tiles with equal keys (the
;           lower index of the two); else on the last turn the most valuable
;           seen single; else the first hidden tile; else the first seen
;           tile; else 0.
;   Second: the seen partner of `first` (same key); else the first hidden
;           tile other than `first`; else the first seen, then the first
;           unreadable one other than `first`; else 0.
;   Unreadable tiles never count toward a pair. All indices are 1-based; 0
;   means "no tile to flip".
; ---------------------------------------------------------------------------

class MatchLogic {
    static Key(text) {
        text := String(text)
        if (GameLists.Fold(text) = "")
            return ""
        amount := 1
        pos := 1, last := ""
        while (pos := RegExMatch(text, "\d[\d,OoIl|]*", &m, pos)) {
            last := m[0]
            pos += m.Len
        }
        if (last != "") {
            d := StrReplace(last, ",")
            d := RegExReplace(RegExReplace(d, "[Oo]", "0"), "[Il|]", "1")
            amount := Integer(SubStr(d, 1, 15))
        }
        tier := GameLists.MatchTier(text)
        if (tier <= GameLists.MatchRewards.Length)
            return GameLists.MatchRewards[tier][1] "|" amount
        rest := RegExReplace(text, "[xX]?\d[\d,OoIl|]*")
        rest := RegExReplace(rest, "(?<![A-Za-z])[xX](?![A-Za-z])")
        item := GameLists.Fold(rest)
        return item = "" ? "" : item "|" amount
    }

    static Value(key) {
        key := String(key)
        ; the task's picture keys "w<amount width>#<n>": a narrower amount is rarer
        if RegExMatch(key, "^w(\d+)#", &m)
            return Integer(m[1])
        pos := InStr(key, "|", , -1)
        item := pos ? SubStr(key, 1, pos - 1) : key
        amount := 1
        if (pos && RegExMatch(SubStr(key, pos + 1), "^\d+$"))
            amount := Integer(SubStr(key, pos + 1, 15))
        return GameLists.MatchTier(item) * 1000000 - Min(amount, 999999)
    }

    static NewBoard(n := 20) {
        board := []
        Loop n
            board.Push(Map("state", "hidden", "key", ""))
        return board
    }

    static Record(board, i, key) {
        board[i]["key"] := key
        board[i]["state"] := (key = "") ? "unreadable" : "seen"
    }

    static Matched(board, a, b := 0) {
        board[a]["state"] := "matched"
        if b
            board[b]["state"] := "matched"
    }

    static First(board, turnsLeft) {
        ; rule 1: the most valuable known pair.
        bestI := 0, bestV := 0
        for i, t in board {
            if (t["state"] != "seen" || t["key"] = "")
                continue
            for j, u in board {
                if (j <= i)
                    continue
                if (u["state"] = "seen" && u["key"] == t["key"]) {
                    v := MatchLogic.Value(t["key"])
                    if (bestI = 0 || v < bestV)
                        bestI := i, bestV := v
                    break
                }
            }
        }
        if bestI
            return bestI
        ; last turn: the best single is the only thing worth a guess.
        if (turnsLeft <= 1) {
            for i, t in board {
                if (t["state"] != "seen")
                    continue
                v := MatchLogic.Value(t["key"])
                if (bestI = 0 || v < bestV)
                    bestI := i, bestV := v
            }
            if bestI
                return bestI
        }
        for state in ["hidden", "seen"] {
            for i, t in board {
                if (t["state"] = state)
                    return i
            }
        }
        return 0
    }

    static Second(board, first, turnsLeft) {
        key := board[first]["key"]
        if (key != "") {
            for i, t in board {
                if (i != first && t["state"] = "seen" && t["key"] == key)
                    return i
            }
        }
        for state in ["hidden", "seen", "unreadable"] {
            for i, t in board {
                if (i != first && t["state"] = state)
                    return i
            }
        }
        return 0
    }
}
