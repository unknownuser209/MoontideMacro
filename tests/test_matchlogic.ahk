#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\..\lib\MatchLogic.ahk

Test_MatchTier_Order() {
    AssertEq(GameLists.MatchTier("Godlike Potion"), 1, "godlike")
    AssertEq(GameLists.MatchTier("Heovenly Potion"), 2, "heavenly misread")
    AssertEq(GameLists.MatchTier("Godly Potion (Zeus)"), 3, "godly")
    AssertEq(GameLists.MatchTier("Fortune Potion III"), 7, "fortune III")
    AssertEq(GameLists.MatchTier("Haste Potion I"), 9, "haste I")
    AssertEq(GameLists.MatchTier("Void Coin"), 5, "void coin beats coin")
    AssertEq(GameLists.MatchTier("Coins"), 11, "coins")
    AssertEq(GameLists.MatchTier("Banana"), 12, "unknown")
}

Test_MatchKey_Parses() {
    AssertEq(MatchLogic.Key("Lucky Potion`nx100"), "Lucky Potion|100", "x100")
    AssertEq(MatchLogic.Key("Coins 10,000"), "Coins|10000", "commas")
    AssertEq(MatchLogic.Key("Heavenly Potion"), "Heavenly Potion|1", "no number")
    AssertEq(MatchLogic.Key("Lucky Potion x1O"), "Lucky Potion|10", "O is zero")
    AssertEq(MatchLogic.Key(""), "", "empty")
    AssertEq(MatchLogic.Key("  12 "), "", "no letters")
}

Test_MatchValue_Order() {
    AssertTrue(MatchLogic.Value("Godlike Potion|1") < MatchLogic.Value("Heavenly Potion|1"), "godlike first")
    AssertTrue(MatchLogic.Value("Heavenly Potion|1") < MatchLogic.Value("Coins|10000"), "potion over coins")
    AssertTrue(MatchLogic.Value("Lucky Potion|200") < MatchLogic.Value("Lucky Potion|10"), "more is better")
    AssertTrue(MatchLogic.Value("Coins|1000") < MatchLogic.Value("banana|1"), "unknown last")
}

Test_MatchLogic_PicksBestKnownPair() {
    b := MatchLogic.NewBoard()
    for i in [1, 7]
        MatchLogic.Record(b, i, "Coins|1000")
    for i in [3, 9]
        MatchLogic.Record(b, i, "Godlike Potion|1")
    for i in [4, 5]
        MatchLogic.Record(b, i, "Heavenly Potion|1")
    AssertEq(MatchLogic.First(b, 5), 3, "first")
    AssertEq(MatchLogic.Second(b, 3, 5), 9, "second")
}

Test_MatchLogic_NewTileThenItsPartner() {
    b := MatchLogic.NewBoard()
    MatchLogic.Record(b, 2, "Void Coin|1")
    AssertEq(MatchLogic.First(b, 9), 1, "first hidden")
    MatchLogic.Record(b, 1, "Void Coin|1")
    AssertEq(MatchLogic.Second(b, 1, 9), 2, "partner")
}

Test_MatchLogic_LearnsWhenNoPartner() {
    b := MatchLogic.NewBoard()
    AssertEq(MatchLogic.First(b, 10), 1, "first")
    MatchLogic.Record(b, 1, "Lucky Potion|10")
    AssertEq(MatchLogic.Second(b, 1, 10), 2, "next hidden")
}

Test_MatchLogic_LastTurnGuess() {
    b := MatchLogic.NewBoard()
    MatchLogic.Record(b, 1, "Heavenly Potion|1")
    MatchLogic.Record(b, 2, "Coins|1000")
    AssertEq(MatchLogic.First(b, 1), 1, "best single")
    AssertEq(MatchLogic.Second(b, 1, 1), 3, "hidden")
}

Test_MatchLogic_NeverPairsUnreadable() {
    b := MatchLogic.NewBoard()
    MatchLogic.Record(b, 1, "")
    MatchLogic.Record(b, 2, "")
    AssertEq(b[1]["state"], "unreadable", "state")
    AssertEq(MatchLogic.First(b, 5), 3, "skips unreadable pair")
}

Test_MatchLogic_PlaysAFullBoard() {
    content := ["Coins|1000", "Lucky Potion|10", "Godlike Potion|1", "Heavenly Potion|1", "Void Coin|1"
        , "Rune|1", "Speed Potion|50", "Fortune Potion I|1", "Haste Potion II|1", "Coins|50"]
    b := MatchLogic.NewBoard()
    pairs := 0, godlike := false
    Loop 10 {
        turnsLeft := 11 - A_Index
        a := MatchLogic.First(b, turnsLeft)
        AssertTrue(a > 0 && b[a]["state"] != "matched", "first not matched, turn " A_Index)
        MatchLogic.Record(b, a, content[Mod(a - 1, 10) + 1])
        c := MatchLogic.Second(b, a, turnsLeft)
        AssertTrue(c > 0 && c != a && b[c]["state"] != "matched", "second not matched, turn " A_Index)
        MatchLogic.Record(b, c, content[Mod(c - 1, 10) + 1])
        if (b[a]["key"] != "" && b[a]["key"] == b[c]["key"]) {
            MatchLogic.Matched(b, a, c)
            pairs++
            if (b[a]["key"] = "Godlike Potion|1")
                godlike := true
        }
    }
    AssertEq(pairs, 5, "pairs")
    AssertTrue(godlike, "godlike pair matched")
}
