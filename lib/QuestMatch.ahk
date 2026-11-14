#Requires AutoHotkey v2.0
; ---------------------------------------------------------------------------
; QuestMatch: match OCR text from the quest board against data\quests.json.
; Pure logic, no I/O.
;
;   QuestMatch.Match(ocrText, questsCfg) -> {name, enabled} | ""
;     questsCfg = cfg.Data("quests"): {types: [{name, enabled, quests:
;     [{name, enabled}]}]}. A quest is enabled only if its type AND itself
;     are enabled (enabled may be 1/0 or true/false).
;     Matching is on normalised text (lower case, every run of non-alphanumeric
;     characters -> one space, so "Deep-Sea Hunter" == "deep sea hunter").
;       1. exact: the normalised name appears as whole words in the text.
;          Best = longest name ("Delivery II" beats "Delivery I").
;       2. fuzzy (only if no exact hit): Levenshtein similarity of the name
;          against every same-length word window of each OCR line, must reach
;          QuestMatch.FuzzyMin. If two DIFFERENT names tie for best, the read is
;          ambiguous and "" is returned. A trailing roman numeral in the name
;          must match exactly (never guess between "Delivery I"/"II").
;     "" (no/empty text, no match) means UNKNOWN: callers must take no action.
;     An aura hunt ("Unique Aura Hunt") also goes by the board's title
;     without "Aura" ("Unique Hunt", live 2026-11-13): Alt().
;   QuestMatch.IsComplete(ocrText) -> bool  (turn-in wording; edit CompleteRe)
;   QuestMatch.Norm(text)
; ---------------------------------------------------------------------------

class QuestMatch {
    static FuzzyMin := 0.80
    static MinFuzzyLen := 5
    ; The game font reads "a" as "o" and l as I ("Cloim Rewords", "Reody to
    ; turn in": 2026-10-27 review).
    static CompleteRe := "i)\b(?:completed|turn[ \-]?in|re[ao]dy to turn|c[lI1|][ao]im(?: rew[ao]rds?)?)\b"

    static Norm(text) {
        s := RegExReplace(StrLower(String(text)), "[^a-z0-9]+", " ")
        return Trim(s)
    }

    ; The board's other name for a list entry ("" = none): "<rarity> aura
    ; hunt" -> "<rarity> hunt".
    static Alt(norm) {
        a := RegExReplace(norm, "^(\w+) aura hunt$", "$1 hunt")
        return (a != norm) ? a : ""
    }

    static IsComplete(ocrText) => RegExMatch(String(ocrText), QuestMatch.CompleteRe) ? true : false

    ; -> Array of {name, norm, enabled}
    static Flatten(questsCfg) {
        out := []
        if !(questsCfg is Map && questsCfg.Has("types") && questsCfg["types"] is Array)
            return out
        for t in questsCfg["types"] {
            if !(t is Map)
                continue
            typeOn := QuestMatch._On(t, "enabled")
            if !(t.Has("quests") && t["quests"] is Array)
                continue
            for q in t["quests"] {
                if !(q is Map && q.Has("name"))
                    continue
                n := QuestMatch.Norm(q["name"])
                if (n = "")
                    continue
                out.Push({name: String(q["name"]), norm: n, alt: QuestMatch.Alt(n), enabled: typeOn && QuestMatch._On(q, "enabled")})
            }
        }
        return out
    }

    static Match(ocrText, questsCfg) {
        text := QuestMatch.Norm(ocrText)
        if (text = "")
            return ""
        list := QuestMatch.Flatten(questsCfg)
        if (list.Length = 0)
            return ""
        ; 1. exact, whole words, longest name wins
        padded := " " text " "
        best := "", bestLen := 0
        for q in list {
            for n in [q.norm, q.alt] {
                if (n != "" && InStr(padded, " " n " ") && StrLen(n) > bestLen)
                    best := q, bestLen := StrLen(n)
            }
        }
        if (best != "")
            return {name: best.name, enabled: best.enabled}
        ; 2. fuzzy
        lines := []
        for raw in StrSplit(String(ocrText), "`n", "`r") {
            n := QuestMatch.Norm(raw)
            if (n != "")
                lines.Push(StrSplit(n, " "))
        }
        bestScore := 0
        bestQ := ""
        tied := false
        for q in list {
            score := 0
            for qn in [q.norm, q.alt] {
                if (qn = "" || StrLen(qn) < QuestMatch.MinFuzzyLen)
                    continue
                qWords := StrSplit(qn, " ")
                nWords := qWords.Length
                ; A trailing roman numeral (Delivery II) must be read exactly:
                ; one OCR edit turns I into II or IV, which is a different quest.
                numeral := (nWords > 1 && RegExMatch(qWords[nWords], "^[ivx]+$")) ? qWords[nWords] : ""
                for words in lines {
                    for cand in QuestMatch._Windows(words, nWords) {
                        if (numeral != "" && !RegExMatch(cand, " " numeral "$"))
                            continue
                        score := Max(score, QuestMatch.Similarity(cand, qn))
                    }
                }
            }
            if (score < QuestMatch.FuzzyMin)
                continue
            if (score > bestScore + 0.0000001) {
                bestScore := score, bestQ := q, tied := false
            } else if (Abs(score - bestScore) <= 0.0000001) {
                tied := true
            }
        }
        if (bestQ == "" || tied)
            return ""
        return {name: bestQ.name, enabled: bestQ.enabled}
    }

    ; All runs of n consecutive words (or the whole line if it is shorter).
    static _Windows(words, n) {
        out := []
        if (words.Length <= n) {
            out.Push(QuestMatch._Join(words, 1, words.Length))
            return out
        }
        Loop words.Length - n + 1
            out.Push(QuestMatch._Join(words, A_Index, A_Index + n - 1))
        return out
    }

    static _Join(words, from, to) {
        s := ""
        i := from
        while (i <= to) {
            s .= (i = from ? "" : " ") words[i]
            i++
        }
        return s
    }

    ; 1 - levenshtein / max length, 0..1.
    static Similarity(a, b) {
        la := StrLen(a), lb := StrLen(b)
        if (la = 0 && lb = 0)
            return 1.0
        prev := []
        Loop lb + 1
            prev.Push(A_Index - 1)
        Loop la {
            i := A_Index
            cur := [i]
            ca := SubStr(a, i, 1)
            Loop lb {
                j := A_Index
                cost := (ca = SubStr(b, j, 1)) ? 0 : 1      ; "=" is case-insensitive, text is normalised anyway
                cur.Push(Min(prev[j + 1] + 1, cur[j] + 1, prev[j] + cost))
            }
            prev := cur
        }
        return 1.0 - prev[lb + 1] / Max(la, lb)
    }

    static _On(m, key) {
        if !m.Has(key)
            return true
        v := m[key]
        return !(v = 0 || v = "0" || v = "false" || v = "")
    }
}
