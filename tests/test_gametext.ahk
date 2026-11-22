#Requires AutoHotkey v2.0
; ---------------------------------------------------------------------------
; GameText: the shared game-font normaliser, and every check that now uses
; it (deep bug hunt, 2026-11-20). Real frames in tests\screens where one
; exists (RED with the old match, GREEN with the new); otherwise the real
; live misreads from macro.log.
; ---------------------------------------------------------------------------
#Include ..\lib\GameText.ahk
#Include ..\lib\Ocr.ahk
#Include ..\lib\PotionSafety.ahk
#Include ..\lib\tasks\Quests.ahk
#Include ..\lib\tasks\Merchant.ahk
#Include ..\lib\tasks\Fishing.ahk
#Include ..\lib\tasks\Obby.ahk
#Include ..\lib\tasks\Craft.ahk
#Include ..\lib\tasks\BiomeItems.ahk
#Include ..\lib\tasks\Potions.ahk

GtFrame(name) {
    for ext in [".jpg", ".png"]
        if FileExist(p := A_ScriptDir "\screens\" name ext)
            return p
    throw Error("frame " name " missing")
}

Test_GameText_FoldsTheFontQuirks() {
    eq := (a, b, why) => AssertEq(GameText.Fold(a), GameText.Fold(b), why)
    eq("ECluip", "Equip", "q read as Cl")
    eq("ECIuip", "Equip", "q read as CI")
    eq("EX it", "Exit", "a space inside the word")
    eq("Worl<shop", "Workshop", "k read as l<")
    eq("Lucl" Chr(0xAB) "y", "Lucky", "k read as l + guillemet")
    eq("LucI" Chr(0x2039) "y", "Lucky", "k read as I + single guillemet")
    eq("Portoble Crock", "Portable Crack", "a read as o")
    eq("Gpeed Votion L", "Speed Potion L", "S as G, P as V")
    eq("F0rtune 5poid", "Fortune Spoid", "0 for o, 5 for s")
    eq("Strange Potion Il", "Strange Potion II", "Il = II")
    eq("Hoste`nPotion", "Haste Potion", "a line break inside a tile name")
    AssertTrue(GameText.Has("orkrnotl", "rkmat"), "m read as rn ('orkrnotl' = Darkmatter)")
    AssertEq(GameText.Norm("her name"), "her nome", "no pair fold across two words")
    AssertTrue(GameText.Has("Magic item", "item"), "cl / ci only folded inside a word")
    AssertTrue(!GameText.Has("", "exit") && !GameText.Has("exit", "") && !GameText.HasAny("", ["exit"]), "empty is never a match")
    AssertTrue(GameText.StartsWord("Gtella's Workshop", "stel") && !GameText.StartsWord("pastel", "stel"), "a word start")
    AssertEq(GameText.DropJunk("Lucky`n" Chr(0xFFFD) "Potion L"), "Lucky`nPotion L", "U+FFFD glued to a word")
    AssertEq(GameText.DropJunk("Lucky -Potion L"), "Lucky Potion L", "a dash glued to a word")
    AssertEq(GameText.DropJunk("Heavenly Potion " Chr(0xFFFD)), "Heavenly Potion " Chr(0xFFFD), "a lone trailing mark is kept")
    ; the old QuestMatch k rule is the shared one
    AssertEq(QuestMatch.FixK("Hell Breol<through LucI<y"), "Hell Breokthrough Lucky", "QuestMatch.FixK")
}

; --- C1 Quests: Eden's skill list over the Accept / Claim button ----------
; real frame quest_button_accept_skills_toast_1440 (crop x 2000, y 1000),
; the button box at quest_accept 2169,1081 reads 'orkrnotl': SkillRe missed
; it live 5x (11-19 / 11-20), so the green-ink fallback never ran
Test_GameText_QuestSkillListRealFrame() {
    pt := {x: 2169, y: 1081}, b := QuestsTask.Button
    t := Ocr.ReadFile(GtFrame("quest_button_accept_skills_toast_1440"), pt.x + b.dx - 2000, pt.y + b.dy - 1000, b.w, b.h)
    AssertTrue(!RegExMatch(t, QuestsTask.SkillRe), "RED: the old SkillRe misses '" t "'")
    AssertTrue(QuestsTask.SkillHit(t), "GREEN: the skill list is seen in '" t "'")
    for f in ["quest_button_accept_1440", "quest_button_claim_1440", "quest_button_claim_toast_1440"] {
        r := Ocr.ReadFile(GtFrame(f), pt.x + b.dx - 2000, pt.y + b.dy - 1000, b.w, b.h)
        AssertTrue(!QuestsTask.SkillHit(r), f ": a plain button is no skill list ('" r "')")
    }
}

Test_GameText_QuestSkillListLiveReads() {
    for t in ["orkrnotl", "Oorkrnotl", "Oorkmo", "Oarkmn", "rkmot", "vugrkmot Re", "Taunt", "Darkmatter Barrage", "Cut Into Nothing Impole"]
        AssertTrue(QuestsTask.SkillHit(t), "'" t "' is the skill list")
    for t in ["", "Accept", "Accep t", "Accevi", "Claim Rewards", "Cloim Rewords", "Dismiss", "Tracking"]
        AssertTrue(!QuestsTask.SkillHit(t), "'" t "' is not")
}

; --- C2 Fishing: the Fish / Exit button ------------------------------------
; no real frame (Eden's combo bar covers the button on every 1440p frame);
; live 2026-11-20 reads 'EX it' and 'Exim'
Test_GameText_FishingExitLiveReads() {
    for t in ["EX it", "Exim"]
        AssertTrue(!InStr(StrLower(t), "exit"), "RED: the old check missed '" t "'")
    for t in ["Exit", "EX it", "Exim", "[ Exit ]", "EXIT", "Ex1t"]
        AssertTrue(FishingTask.IsExit(t), "'" t "' reads Exit")
    for t in ["", "Fish", "Fishing", "It's quiet... too quiet.", "Ex"]
        AssertTrue(!FishingTask.IsExit(t), "'" t "' is not Exit")
    AssertTrue(FishingTask.IsFish("Fish") && FishingTask.IsFish("[ Fi sh ]") && !FishingTask.IsFish("Exit") && !FishingTask.IsFish(""), "Fish")
}

; --- C3 Obby: the Aura Storage's Equip button -----------------------------
Test_GameText_ObbyEquipButton() {
    ; live 2026-11-20 08:58: 'ECluip' -> "not Equip: not clicked", no Sailor
    AssertTrue(!RegExMatch("ECluip", "i)equip"), "RED: the old regex missed 'ECluip'")
    AssertEq(ObbyTask.ButtonState("ECluip"), "off", "GREEN: 'ECluip' is Equip")
    AssertEq(ObbyTask.ButtonState("Equip"), "off", "Equip")
    AssertEq(ObbyTask.ButtonState("Unequip"), "on", "Unequip")
    AssertEq(ObbyTask.ButtonState("nequip"), "on", "the U lost")
    AssertEq(ObbyTask.ButtonState("UnECluip"), "on", "Unequip with q as Cl")
    for t in ["Delete", "Lock", "Locl<", "Sell", "SeII", "Remove", "Discard", "Equip Lock"]
        AssertEq(ObbyTask.ButtonState(t), "never", "'" t "' is never clicked")
    AssertEq(ObbyTask.ButtonState(""), "", "nothing read")
    AssertEq(ObbyTask.ButtonState("Rolled at"), "", "another text")
    ; real frame: Sailor selected, the button reads Equip (1x, as the task)
    b := ObbyTask.ButtonBox
    t := Ocr.ReadFile(GtFrame("aura_selected_sailor"), 840 + b.dx, 843 + b.dy, b.w, b.h)
    AssertEq(ObbyTask.ButtonState(t), "off", "aura_selected_sailor reads Equip ('" t "')")
}

; --- C4 / C5 Merchant: Mari's shop title, her tabs and item title ----------
Test_GameText_MerchantShopTitle() {
    ; live 11-19 21:45 and 11-20 09:22 'Mori's Gno': X not clicked
    AssertTrue(!RegExMatch("Mori's Gno", "i)h[ao0]p|sh[ao0]|(?:'|\b)s\s*s[a-z]"), "RED: the old ShopRe missed 'Mori's Gno'")
    for t in ["Mori's Gno", "Mori's Shop", "Mori's sho", "Mori's stin", "Morl s stib", "Mori" Chr(0x2022) "s$hop", "Jester's Shop", "Mari s Gno"]
        AssertTrue(RegExMatch(t, MerchantTask.ShopRe) > 0, "'" t "' is her shop")
    for t in ["", "Mori", "Mari", "Who are you?", "Click to skip", "Leave", "Open"]
        AssertTrue(!RegExMatch(t, MerchantTask.ShopRe), "'" t "' is no shop title")
    ; the real jester_shop title still reads
    L := MerchantTask.Layout
    t := Ocr.ReadFile(GtFrame("jester_shop"), L.title.x, L.title.y, L.title.w, L.title.h, MerchantTask.SmallScale)
    AssertTrue(RegExMatch(t, MerchantTask.ShopRe) > 0, "jester_shop title '" t "'")
}

Test_GameText_MerchantTabsAndTitles() {
    ; S as G, P as V: two misread letters were past the one-letter slack
    tabs := ["Gpeed Votion L", "Lucky Votion XL", "Lucky Venny", "Hoste Votion III", "Void Coin"]
    old := (t) => GameLists.Distance(GameLists.Fold(t), GameLists.Fold("Speed Potion L"))
    AssertTrue(old("Gpeed Votion L") > MerchantTask.Slack(GameLists.Fold("Speed Potion L")), "RED: the old fold was 2 letters off")
    AssertEq(MerchantTask.FindTab(tabs, "Speed Potion L"), 1, "Gpeed Votion L")
    AssertEq(MerchantTask.FindTab(tabs, "Lucky Potion XL"), 2, "Lucky Votion XL")
    AssertEq(MerchantTask.FindTab(tabs, "Lucky Penny"), 3, "Lucky Venny")
    AssertEq(MerchantTask.FindTab(tabs, "Haste Potion III"), 4, "Hoste Votion III")
    AssertEq(MerchantTask.FindTab(tabs, "Void Coin"), 5, "Void Coin")
    ; never a near name or another tier
    AssertEq(MerchantTask.FindTab(tabs, "Speed Potion XL"), 0, "Speed L is not XL")
    AssertEq(MerchantTask.FindTab(tabs, "Speed Potion"), 0, "Speed L is not Speed")
    AssertEq(MerchantTask.FindTab(tabs, "Lucky Potion L"), 0, "Lucky XL is not L")
    AssertEq(MerchantTask.FindTab(tabs, "Haste Potion II"), 0, "III is not II")
    AssertEq(MerchantTask.FindTab(["Gear A", "Gear B"], "Gear B"), 2, "Gear B is not Gear A")
    AssertEq(MerchantTask.FindTab(["Gear A"], "Gear B"), 0, "only Gear A sold")
    ; the cut titles read live on Mari's shop are NO proof (nothing bought)
    AssertTrue(!MerchantTask.TitleNames("I Epic", "Gear A") && !MerchantTask.TitleNames("I Enic", "Gear B"), "'I Epic' names no gear")
    AssertTrue(!MerchantTask.TitleNames("Lucky", "Lucky Potion XL"), "'Lucky' is not Lucky Potion XL")
    AssertTrue(!MerchantTask.TitleNames("Void" Chr(0xFFFD) "0i", "Void Coin"), "'Void?0i' is not Void Coin")
    AssertTrue(MerchantTask.TitleNames("Gpeed Votion L | Rare", "Speed Potion L"), "a whole title with G / V names it")
    AssertTrue(!MerchantTask.TitleNames("Gpeed Votion L | Rare", "Speed Potion XL"), "...and not XL")
}

; Mari's 1x title read cut: the 2x read names it, the purchase is logged;
; two cut reads joined never name it (nothing bought)
Test_GameText_MerchantTitleAgainAt2xAndBuyLogged() {
    wants := Map("Mari", [Map("name", "Void Coin", "qty", 2)], "Jester", [])
    io := QmIO(), wh := QmWh(), logs := []
    shop := GtCutShop(io, ["Void Coin", "", "", "", ""], "Void" Chr(0xFFFD) "0i", "Void Coin | Epic")
    t := MerchantTask({cfg: QmCfg("", Map("merchants", wants)), io: io, webhook: wh, cal: QmMerchCal(), log: (m) => logs.Push(m)
        , ocr: (x, y, w, h, scale := 1) => shop.Ocr(x, y, w, h, scale)})
    t.Notify("Mari")
    t.Run(SchedCtx())
    L := MerchantTask.Layout
    AssertTrue(io.Index("move " L.buy.x "," L.buy.y) > 0, "bought after the 2x title read named it")
    AssertTrue(GtLogHas(logs, "merchant: bought 2 Void Coin from Mari"), "the purchase is in macro.log")
    ; 1x 'Void' + 2x 'Coin | Epic': each alone is no proof
    io2 := QmIO(), wh2 := QmWh(), logs2 := []
    shop2 := GtCutShop(io2, ["Void Coin", "", "", "", ""], "Void", "Coin | Epic")
    t2 := MerchantTask({cfg: QmCfg("", Map("merchants", wants)), io: io2, webhook: wh2, cal: QmMerchCal(), log: (m) => logs2.Push(m)
        , ocr: (x, y, w, h, scale := 1) => shop2.Ocr(x, y, w, h, scale)})
    t2.Notify("Mari")
    t2.Run(SchedCtx())
    AssertEq(io2.Index("move " L.buy.x "," L.buy.y), 0, "Purchase never clicked")
    AssertTrue(GtLogHas(logs2, "shows 'Void / Coin | Epic': skipped"), "both reads logged")
    ; no notice: the click is logged as unconfirmed
    io3 := QmIO(), logs3 := []
    shop3 := QmShop(io3, ["Lucky Potion", "", "", "", ""])
    shop3.confirm := false
    t3 := MerchantTask({cfg: QmCfg("", Map("merchants", Map("Mari", [Map("name", "Lucky Potion", "qty", 1)], "Jester", []))), io: io3, webhook: QmWh()
        , cal: QmMerchCal(), log: (m) => logs3.Push(m), ocr: (x, y, w, h, scale := 1) => shop3.Ocr(x, y, w, h, scale)})
    t3.Notify("Mari")
    t3.Run(SchedCtx())
    AssertTrue(GtLogHas(logs3, "merchant: Purchase clicked for 1 Lucky Potion at Mari (no 'You purchased' notice seen)"), "unconfirmed click logged")
    ; an item not found: the tab reads are logged
    io4 := QmIO(), logs4 := []
    shop4 := QmShop(io4, ["Mixed Potion", "Lucky Potion", "", "", ""])
    t4 := MerchantTask({cfg: QmCfg("", Map("merchants", Map("Mari", ["Void Coin"], "Jester", []))), io: io4, webhook: QmWh()
        , cal: QmMerchCal(), log: (m) => logs4.Push(m), ocr: (x, y, w, h, scale := 1) => shop4.Ocr(x, y, w, h, scale)})
    t4.Notify("Mari")
    t4.Run(SchedCtx())
    AssertTrue(GtLogHas(logs4, "Void Coin is not in Mari's shop this visit (tabs read: Mixed Potion | Lucky Potion | "), "tab reads logged")
}

GtLogHas(logs, s) {
    for l in logs
        if InStr(l, s)
            return true
    return false
}

; QmShop whose item title reads `t1` at 1x and `t2` at 2x
class GtCutShop extends QmShop {
    __New(io, tabs, t1, t2) {
        super.__New(io, tabs)
        this.t1 := t1, this.t2 := t2
    }
    Ocr(x, y, w, h, scale := 1) {
        L := MerchantTask.Layout
        if (x = L.item.x && y = L.item.y && this.io.Index("move " L.open.x "," L.open.y))
            return scale = 1 ? this.t1 : this.t2
        return super.Ocr(x, y, w, h, scale)
    }
}

; --- L1 Craft: Stella's Workshop title and her name -----------------------
Test_GameText_CraftWorkshopAndStella() {
    AssertTrue(!RegExMatch("Stella's Worl<shop", CraftTask.GuiRe), "RED: 'Worl<shop' missed")
    for t in ["Stella's Worl<shop", "Stella's WorI<shop", "Stella's Workshop", "W0rkshop", "Work shop"]
        AssertTrue(CraftTask.WorkshopUp(t), "'" t "' is her workshop")
    for t in ["", "Fishing Shop", "Shop", "Work", "Stella"]
        AssertTrue(!CraftTask.WorkshopUp(t), "'" t "' is not")
    AssertTrue(!RegExMatch("Gtella", CraftTask.StellaRe), "RED: 'Gtella' missed")
    for t in ["Gtella", "Stella", "Stello", "STELLA`nHello"]
        AssertTrue(CraftTask.StellaSeen(t), "'" t "' is Stella")
    for t in ["", "pastel", "Captain Florg", "Steady"]
        AssertTrue(!CraftTask.StellaSeen(t), "'" t "' is not Stella")
    AssertTrue(CraftTask.IsRecipe("Lucl" Chr(0xAB) "y Potion", "Lucky Potion"), "IsRecipe: l + guillemet = k")
    AssertTrue(!CraftTask.IsRecipe("Lucky Potion", "Lucky Potion L"), "IsRecipe still exact")
}

; --- L2 BiomeItems: the Biome Selector's Drives ----------------------------
Test_GameText_SelectorDrives() {
    AssertTrue(!InStr(StrLower("Obyss Curse Drive"), "abyss"), "RED: 'Obyss' missed")
    reads := Map("Radiant Star Drive", "Rodiont Stor Drive", "Infernal Flame Drive", "Infemol Flome Drive"
        , "Unknown Void Drive", "Unknown Void Drive", "Corrupt Ruin Drive", "Corrupt Ruin Drive"
        , "Golden Dune Drive", "Golden Dune Drive", "Chilling Frost Drive", "ChiIIing Frost Drive"
        , "Abyss Curse Drive", "Obyss Curse Drive", "Raging Gale Drive", "Roging Gole Drive", "Angelic Hymn Drive", "Ongelic Hymn Drive")
    for d in BiomeItemsTask.Drives {
        AssertTrue(reads.Has(d), d " has a read")
        for e in BiomeItemsTask.Drives {
            k := BiomeItemsTask.DriveKey(e)
            AssertEq(BiomeItemsTask.DriveIn(reads[d], k) ? 1 : 0, (d = e) ? 1 : 0, "'" reads[d] "' vs key " k)
        }
    }
}

; --- L6 PotionSafety: tile names and descriptions --------------------------
Test_GameText_PotionNamesFold() {
    d := SafetyTempDir()
    try {
        cfg := SafetyCfg(SafetyEntry("Lucky Potion", 0, 1, 3, 3), SafetyEntry("Lucky Potion L", 0, 1, 3, 3), SafetyEntry("Heavenly Potion", 0, 1, 3, 3))
        s := SafetyNew(cfg, d "\potion_usage.json")
        AssertTrue(s.NameMatches("Lucl<y Potion", "Lucky Potion"), "l< = k")
        AssertTrue(s.NameMatches("LucI" Chr(0xAB) "y`nPotion", "Lucky Potion"), "I + guillemet = k")
        AssertTrue(s.NameMatches("Lucky`n" Chr(0xFFFD) "Potion L", "Lucky Potion L"), "U+FFFD glued to Potion")
        AssertTrue(s.NameMatches("Lucky -Potion L", "Lucky Potion L"), "a dash glued to Potion")
        ; still exact: no letter guessed, no tier lost or added
        AssertTrue(!s.NameMatches("Lucky Potion", "Lucky Potion L"), "L is never dropped")
        AssertTrue(!s.NameMatches("Lucky Potion L", "Lucky Potion"), "L is never added")
        AssertTrue(!s.NameMatches("Lucky`nL", "Lucky Potion L"), "a lost word stays a mismatch")
        AssertTrue(!s.NameMatches("Lucky`nT'otion L", "Lucky Potion L"), "T' is not P")
        AssertTrue(!s.NameMatches("Heavenly Potion -I", "Heavenly Potion"), "a glued I is a never-use name, not plain")
        AssertTrue(s.DescMatches("Gives you 1 rninute of luck", "Gives you 1 minute of"), "rn = m in a description")
    } finally SafetyCleanup(d)
}

; real frame inv_lucky_tiles_6digit (screen x 1050, y 560): Lucky Potion L /
; Lucky Potion / Lucky Potion XL. Each name box (the tile cut above its
; count) at the task's scale reads its own name and never a neighbour's
; (a regression check: the AHK pipeline reads these whole; the audit's
; Python OCR read 'Lucky / -Potion L', which the fold now accepts too).
Test_GameText_PotionTileRealFrame() {
    d := SafetyTempDir()
    try {
        cfg := SafetyCfg(SafetyEntry("Lucky Potion", 0, 1, 3, 3), SafetyEntry("Lucky Potion L", 0, 1, 3, 3), SafetyEntry("Lucky Potion XL", 0, 1, 3, 3))
        s := SafetyNew(cfg, d "\potion_usage.json")
        f := GtFrame("inv_lucky_tiles_6digit")
        names := ["Lucky Potion L", "Lucky Potion", "Lucky Potion XL"]
        xs := [1076, 1209, 1342]
        for i, want in names {
            t := Ocr.ReadFile(f, xs[i] - 1050, 578 - 560, 112, 82, PotionsTask.OcrScale)
            for j, other in names
                if (j != i)
                    AssertTrue(!s.NameMatches(t, other), "tile " i " ('" t "') is never " other)
            AssertTrue(s.NameMatches(t, want), "tile " i " reads " want " ('" t "')")
        }
    } finally SafetyCleanup(d)
}
