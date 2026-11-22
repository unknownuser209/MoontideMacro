#Requires AutoHotkey v2.0
; ---------------------------------------------------------------------------
; GameText: one normaliser for OCR reads of the game's font. Pure logic.
;
; Windows OCR misreads Sol's RNG's font the same way every time (real frames
; in tests\screens and live logs, 2026-11-10 .. 11-20):
;   a drawn like o        'Portoble Crock', 'Mori', 'Auro Storage'
;   k as l< / I< / l«      'Worl<shop', 'LucI<y', 'Lucl«y'
;   m as rn               'orkrnotl' (Darkmatter), 'rninutes'
;   q as Cl               'ECluip' (Equip)
;   S as G, P as V        'Gol's World', 'Mori's Gno', 'Votion L'
;   l / I / 1 / | / !     one shape ('Il' = II)
;   0 for o, 5 for s      'F0rtune'
;   spaces inside a word  'EX it'; and line breaks inside tile names
; Both sides of a compare go through the same fold, so a word written
; normally ("Equip") meets its misread ('ECluip' -> "equip").
;
;   GameText.FixK(text)        l< / I< / i< / l« / l‹ -> k, the rest kept
;   GameText.Norm(text)        each word folded (see Fold), words joined by
;                              one space: for "starts a word" checks
;   GameText.Fold(text)        letters only, every look-alike folded, spaces
;                              and line breaks dropped:
;                                k fix, lower case, l 1 | ! -> i, 0 -> o,
;                                5 -> s, then per word: rn -> m, ci -> q
;                                (cl after the i fold), g -> s, v -> p, a -> o
;   GameText.Has(read, word)   the folded word is inside the folded read
;   GameText.HasAny(read, words)   any of an Array of words
;   GameText.StartsWord(read, word)   a word of the read starts with it
;   GameText.DropJunk(text)    a stray U+FFFD / "-" glued to the front of a
;                              word dropped ('Lucky -Potion L')
;
; A pair fold (rn, cl) is only done inside one word, so two words never run
; into a false letter ("her name" stays "her nome"). Folding only merges
; look-alikes; a check that must not pass by accident (a purchase prompt,
; a never-use name) keeps its own strict rule on top.
; ---------------------------------------------------------------------------

class GameText {
    static KRe := "[lIi1|][<\x{AB}\x{2039}]"

    static FixK(text) => RegExReplace(String(text), GameText.KRe, "k")

    static Norm(text) {
        out := ""
        for w in StrSplit(StrLower(GameText.FixK(text)), [" ", "`t", "`r", "`n"]) {
            f := GameText._Word(w)
            if (f != "")
                out .= (out = "" ? "" : " ") f
        }
        return out
    }

    static Fold(text) => StrReplace(GameText.Norm(text), " ")

    ; one lower-case word (k already fixed)
    static _Word(w) {
        w := RegExReplace(w, "[l1|!]", "i")
        w := StrReplace(StrReplace(w, "0", "o"), "5", "s")
        w := RegExReplace(w, "[^a-z]")
        w := StrReplace(w, "rn", "m")
        w := StrReplace(w, "ci", "q")
        w := StrReplace(StrReplace(w, "g", "s"), "v", "p")
        return StrReplace(w, "a", "o")
    }

    static Has(read, word) {
        f := GameText.Fold(word)
        return f != "" && InStr(GameText.Fold(read), f) > 0
    }

    static HasAny(read, words) {
        r := GameText.Fold(read)
        if (r = "")
            return false
        for w in words {
            f := GameText.Fold(w)
            if (f != "" && InStr(r, f))
                return true
        }
        return false
    }

    static StartsWord(read, word) {
        f := GameText.Fold(word)
        return f != "" && InStr(" " GameText.Norm(read), " " f) > 0
    }

    static DropJunk(text) => RegExReplace(String(text), "(^|\s)[\x{FFFD}\-]+(?=\p{L})", "$1")
}
