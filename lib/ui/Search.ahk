#Requires AutoHotkey v2.0
; Search: the pure index and ranking behind the dashboard's search box
; (2026-11-18 themes + layout design, spec 6). Nothing here touches a
; control, and nothing throws on a bad query or index.
;
;   Search.Add(index, text, kind, page, card, shown := "")
;       index is an Array; kind is "title" | "label" | "info" | "help"; page is the
;       page name and card the card id ("" for none). shown is the text a
;       result lists (default text): the English and the translated entry
;       of one label both list the translated text.
;   Search.Find(index, query, max := 8)
;       an Array (at most max) of {text, page, card, score}. Every word of
;       the query must start a word of the entry, case-insensitive and
;       accent-folded. Title 3 > label 2 > info 1.5 > help 1 (info is a
;       read-only label: a stat tile, a note); a shorter entry wins a
;       tie. A shown text on one card is listed once. text is the shown text.
;   Search.Words(s)   the folded words of s (an Array)
;   Search.Fold(s)    s lower-cased with the accents taken off
class Search {
    static MaxWords := 8
    static MaxQuery := 200

    static Add(index, text, kind, page, card, shown := "") {
        try {
            text := String(text)
            if (!(index is Array) || Trim(text) = "")
                return
            w := (kind = "title") ? 3 : (kind = "label") ? 2 : (kind = "info") ? 1.5 : 1
            index.Push({text: text, shown: (shown = "" ? text : String(shown)), w: w, page: String(page), card: String(card)
                , words: Search.Words(text), len: StrLen(text)})
        }
    }

    static Find(index, query, limit := 8) {
        out := []
        try {
            if !(index is Array)
                return out
            q := Search.Words(SubStr(String(query), 1, Search.MaxQuery))
            if (!q.Length || !IsInteger(limit) || limit < 1)
                return out
            if (q.Length > Search.MaxWords)
                q.Length := Search.MaxWords
            hits := []
            for n, e in index {
                if Search._Matches(e.words, q)
                    hits.Push({text: e.shown, page: e.page, card: e.card, score: e.w * 10000 + Max(0, 999 - e.len), n: n})
            }
            ; best first; the entry added first wins an exact tie (insertion sort, stable)
            Loop hits.Length - 1 {
                i := A_Index + 1
                h := hits[i]
                j := i - 1
                while (j >= 1 && hits[j].score < h.score) {
                    hits[j + 1] := hits[j]
                    j--
                }
                hits[j + 1] := h
            }
            seen := Map()
            for h in hits {
                key := h.page "|" h.card "|" h.text
                if seen.Has(key)
                    continue
                seen[key] := true
                out.Push({text: h.text, page: h.page, card: h.card, score: h.score})
                if (out.Length >= limit)
                    break
            }
        }
        return out
    }

    ; every query word starts some word of the entry
    static _Matches(words, q) {
        for qw in q {
            ok := false
            for w in words {
                if (SubStr(w, 1, StrLen(qw)) = qw) {
                    ok := true
                    break
                }
            }
            if !ok
                return false
        }
        return true
    }

    static Words(s) {
        out := []
        try {
            s := RegExReplace(Search.Fold(s), "[^\p{L}\p{N}]+", " ")
            for w in StrSplit(Trim(s), " ") {
                if (w != "")
                    out.Push(w)
            }
        }
        return out
    }

    static Fold(s) {
        s := StrLower(String(s))
        try {
            ; canonical decomposition, then the combining marks go
            n := DllCall("Normaliz\NormalizeString", "Int", 2, "WStr", s, "Int", -1, "Ptr", 0, "Int", 0, "Int")
            if (n > 0) {
                buf := Buffer(n * 2 + 2, 0)
                n := DllCall("Normaliz\NormalizeString", "Int", 2, "WStr", s, "Int", -1, "Ptr", buf, "Int", n, "Int")
                if (n > 0)
                    s := RegExReplace(StrGet(buf, "UTF-16"), "\p{Mn}+")
            }
        }
        return s
    }
}
