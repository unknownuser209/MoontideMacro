#Requires AutoHotkey v2.0
; ---------------------------------------------------------------------------
; GameLists: what the game sells and crafts (read off the creator's screenshots,
; 2026-10-26). Update these when the game changes.
;
;   GameLists.Shop      Captain Flarg's Fisher shop, in its grid order (the
;                       [Craft] potions list may only name these).
;   GameLists.Recipes   Stella's cauldron recipes, in her list order. The three
;                       Godly Potions share the title "Godly Potion"; they are
;                       told apart by their description: Zeus = [Lord of the
;                       Sky], Poseidon = [Lord of the Sea], Hades = [Lord of Hell].
;   GameLists.SearchName(recipe)   the text typed into the cauldron search and
;                       matched against a result's title ("Godly Potion (Hades)"
;                       -> "Godly Potion").
;   GameLists.DescHint(recipe)     description text the result card must also
;                       show ("Lord of Hell"), or "" when the title is enough.
;   GameLists.Fold(s)   letters only, lower case, the game font's look-alikes
;                       folded ("I<" / l + guillemet k, l/1/| i, o a), for comparing OCR text.
;   GameLists.Distance(a, b)   edit distance (insert / delete / change one letter).
;   GameLists.ShopName(name)       canonical shop spelling, or "" if not sold.
;   GameLists.MatchRewards   Memory Match prizes, best tier first (each tier an
;                       Array of names that rank the same).
;   GameLists.MatchTier(text)  1-based tier of a tile's text, or MatchRewards.Length
;                       + 1 when none: a folded name equals the text; else the
;                       longest name the text contains ("Fortune Potion III" is
;                       not II; "Void Coin" is not Coin); else the one name
;                       within Slack letters (2 from 14 letters, 1 from 8, else 0).
; ---------------------------------------------------------------------------

class GameLists {
    static Shop := ["Lucky Potion", "Speed Potion", "Wind essence", "Icicle"
        , "Rainy Bottle", "Haste Potion III", "Fortune Potion III", "Gladiator Potion"
        , "Eternal Flame", "Curruptaine", "Hour Glass", "NULL?"
        , "Potion of Bound", "Warp Potion", "Heavenly Potion"]

    static Recipes := ["Fortune Potion I", "Fortune Potion II", "Fortune Potion III"
        , "Haste Potion I", "Haste Potion II", "Haste Potion III"
        , "Jewelry Potion", "Zombie Potion", "Rage Potion", "Diver Potion"
        , "Potion of Bound", "Heavenly Potion"
        , "Godly Potion (Zeus)", "Godly Potion (Poseidon)", "Godly Potion (Hades)"
        , "Warp Potion", "Godlike Potion"
        , "Forbidden Potion I", "Forbidden Potion II", "Forbidden Potion III"
        , "Void Heart"]

    static MatchRewards := [["Godlike Potion"], ["Heavenly Potion"], ["Godly Potion"], ["Potion of Bound"]
        , ["Void Coin"], ["Rune"], ["Fortune Potion III", "Haste Potion III"]
        , ["Fortune Potion II", "Haste Potion II"], ["Fortune Potion I", "Haste Potion I"]
        , ["Lucky Potion", "Speed Potion"], ["Coins", "Coin"]]

    static MatchTier(text) {
        f := GameLists.Fold(text)
        none := GameLists.MatchRewards.Length + 1
        if (f = "")
            return none
        bestTier := 0, bestLen := 0
        for tier, names in GameLists.MatchRewards {
            for name in names {
                n := GameLists.Fold(name)
                if (n == f)
                    return tier
                if (InStr(f, n) && StrLen(n) > bestLen)
                    bestTier := tier, bestLen := StrLen(n)
            }
        }
        if bestTier
            return bestTier
        bestTier := 0, bestD := 99, ties := 0
        for tier, names in GameLists.MatchRewards {
            for name in names {
                n := GameLists.Fold(name)
                slack := StrLen(n) >= 14 ? 2 : StrLen(n) >= 8 ? 1 : 0
                d := GameLists.Distance(f, n)
                if (d > slack)
                    continue
                if (d < bestD)
                    bestTier := tier, bestD := d, ties := 0
                else if (d = bestD && tier != bestTier)
                    ties++
            }
        }
        return (bestTier && !ties) ? bestTier : none
    }

    static Godly := Map("zeus", "Lord of the Sky", "poseidon", "Lord of the Sea", "hades", "Lord of Hell")

    static SearchName(recipe) => Trim(RegExReplace(String(recipe), "\s*\([^)]*\)\s*$"))

    static DescHint(recipe) {
        if RegExMatch(String(recipe), "i)\((\w+)\)\s*$", &m) && GameLists.Godly.Has(StrLower(m[1]))
            return GameLists.Godly[StrLower(m[1])]
        return ""
    }

    static Fold(s) {
        s := StrLower(String(s))
        s := RegExReplace(s, "[il1|][<\x{AB}\x{2039}]", "k")       ; I< and l followed by a guillemet (U+00AB / U+2039) = k
        s := RegExReplace(s, "[l1|!]", "i")
        s := StrReplace(s, "o", "a")
        return RegExReplace(s, "[^a-z]")
    }

    static Distance(a, b) {
        a := String(a), b := String(b)
        la := StrLen(a), lb := StrLen(b)
        if (la = 0)
            return lb
        if (lb = 0)
            return la
        prev := []
        Loop lb + 1
            prev.Push(A_Index - 1)
        Loop la {
            i := A_Index
            cur := [i]
            ca := SubStr(a, i, 1)
            Loop lb {
                j := A_Index
                cost := (ca == SubStr(b, j, 1)) ? 0 : 1
                cur.Push(Min(prev[j + 1] + 1, cur[j] + 1, prev[j] + cost))
            }
            prev := cur
        }
        return prev[lb + 1]
    }

    static ShopName(name) {
        k := StrLower(Trim(RegExReplace(String(name), "\s+", " ")))
        for n in GameLists.Shop {
            if (StrLower(n) = k)
                return n
        }
        return ""
    }
}
