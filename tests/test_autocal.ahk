#Requires AutoHotkey v2.0
; ---------------------------------------------------------------------------
; Tests for lib\AutoCal.ahk: the windows whose parts are found on screen by
; their text, so their calibration steps need no hovering.
;
; REAL FRAMES (tests\screens, 2560x1440; the real Windows OCR, as
; test_screens.ahk): fishshop_hell_sell / sellconfirm_hell (the Fishing
; Shop), workshop_open / workshop_search_typed (Stella's Workshop, live
; 2026-11-20 / 11-21), selector_list_night / _booting / _bobbed and
; selector_prompt_over_storage (the Biome Selector, live 2026-11-21; only the
; Selector's window is kept, the leaderboards behind it are blacked out).
; The places found are checked against what was calibrated by hand on that
; screen, and the tasks' own reads are made at the places found.
; ---------------------------------------------------------------------------
#Include ..\lib\AutoCal.ahk
#Include ..\lib\Ocr.ahk
#Include ..\lib\tasks\Craft.ahk
#Include ..\lib\tasks\BiomeItems.ahk

AcPath(name) => A_ScriptDir "\screens\" name ".jpg"

; every line of frame `name` with its place (the whole frame, or rect r)
AcLines(name, r := "", scale := 1) {
    AssertTrue(FileExist(AcPath(name)), "frame " name " exists")
    return IsObject(r) ? Ocr.LinesFile(AcPath(name), r.x, r.y, r.w, r.h, scale) : Ocr.LinesFile(AcPath(name), 0, 0, 2560, 1440, scale)
}

AcNear(p, x, y, tol, what) {
    AssertTrue(IsObject(p), what ": found")
    AssertTrue(Abs(p.x - x) <= tol && Abs(p.y - y) <= tol, what ": " p.x "," p.y " is within " tol " of " x "," y)
}

AcLine(text, l, t, r, b) => {text: text, x: (l + r) // 2, y: (t + b) // 2, l: l, t: t, r: r, b: b}

; ---- which steps are automatic ------------------------------------------------

Test_AutoCal_IsAuto() {
    for id in ["fisher_item_lucky_potion", "fisher_item_potion_of_bound", "cauldron_gui", "cauldron_search", "cauldron_result"
        , "cauldron_result_2", "cauldron_open_recipe", "cauldron_close", "selector_list_rect", "selector_confirm"]
        AssertTrue(AutoCal.IsAuto(id), id " is found on screen")
    ; no text to find these by (a picture, a spot in the world, a box)
    for id in ["cauldron_add_all", "fisher_buy_button", "fisher_picked_name", "inv_open", "inv_tile2_rect", "inv_count_rect", "inv_amount_box", "notify_rect", "aura_open", "chat_rect", ""]
        AssertTrue(!AutoCal.IsAuto(id), "'" id "' still asks the user (or the preset)")
    AssertEq(AutoCal.TilePrefix, Calibrate.PotionPrefix, "the tile steps are Calibrate's fisher_item_ ones")
    AssertEq(AutoCal.Shop.pitch, CraftTask.TilePitch, "one tile spacing")
    AssertEq(AutoCal.Shop.cols, CraftTask.GridCols, "one column count")
}

; ---- Fisher shop -----------------------------------------------------------------

Test_AutoCal_ShopTilesFromTheTitle() {
    ; live 2026-11-21 03:17: the Buy tab, 4 columns of tall tiles, two rows
    ; in sight (the Sell tab's 5 columns 190 apart were taken for it before)
    lines := AcLines("fishshop_buy_tab", , 2)
    title := AutoCal.ShopTitle(lines)
    AssertTrue(IsObject(title), "the Fishing Shop's title is found")
    AcNear(AutoCal.ShopTile(title, 1), 1125, 596, 4, "tile 1 (Lucky Potion)")
    AcNear(AutoCal.ShopTile(title, 8), 1854, 900, 4, "tile 8 (Gladiator Potion: column 4, row 2)")
    AssertEq(AutoCal.ShopTile(title, 9), "", "tile 9 is under the wheel: no place")
    AssertEq(AutoCal.ShopTile(title, 13), "", "nor tile 13 (Potion of Bound)")
    ; each tile worked out sits on the tile whose name reads under it
    for i, n in ["Lucky Potion", "Speed Potion", "Wind essence", "Icicle", "Rainy Bottle", "Haste Potion III", "Fortune Potion III", "Gladiator Potion"] {
        lab := ""
        for L in lines
            if (!IsObject(lab) && L.x > 1000 && CraftTask.IsItem(L.text, n))
                lab := L
        AssertTrue(IsObject(lab), n "'s name reads under its picture")
        p := AutoCal.ShopTile(title, i)
        AssertTrue(Abs(p.x - lab.x) <= 20 && lab.y - p.y >= 30 && lab.y - p.y <= 70, "tile " i " is on " n "'s tile (" p.x "," p.y " / name " lab.x "," lab.y ")")
    }
    ; the same grid CraftTask.GridTiles walks
    g := CraftTask.GridTiles(AutoCal.ShopTile(title, 1), 1)
    AssertEq(g.Length, AutoCal.Shop.cols * AutoCal.Shop.rows, "the tiles in sight")
    AssertEq(g[8].x "," g[8].y, AutoCal.ShopTile(title, 8).x "," AutoCal.ShopTile(title, 8).y, "one grid")
    AssertEq(AutoCal.Shop.pitchY, CraftTask.TilePitchY, "one row spacing")
    ; the shop's title sits in the same place on the Sell tab and under the
    ; Sell Confirm popup
    for f in ["fishshop_hell_sell", "sellconfirm_hell"]
        AcNear(AutoCal.ShopTile(AutoCal.ShopTitle(AcLines(f)), 1), 1125, 596, 4, f ": tile 1 from the title")
    ; no title read: the shop's usual place
    AssertEq(AutoCal.ShopTile("", 1).x "," AutoCal.ShopTile("", 1).y, "1125,596", "no title: the usual place")
    AssertEq(AutoCal.ShopTile(title, 0), "", "no tile 0")
}

Test_AutoCal_ShopLabelFindsATileByItsName() {
    lines := AcLines("fishshop_buy_tab", , 2)
    title := AutoCal.ShopTitle(lines)
    AcNear(AutoCal.ShopLabel(lines, title, (t) => CraftTask.IsItem(t, "Lucky Potion")), 1125, 596, 6, "Lucky Potion's tile by its name")
    AcNear(AutoCal.ShopLabel(lines, title, (t) => CraftTask.IsItem(t, "Gladiator Potion")), 1854, 900, 8, "Gladiator Potion's tile (row 2) by its name")
    AssertEq(AutoCal.ShopLabel(lines, title, (t) => CraftTask.IsItem(t, "Potion of Bound")), "", "a name not in sight: none")
    ; the shop's own words outside the grid are never a tile (the title, the
    ; picked item's big name left of the grid, Purchase)
    AssertEq(AutoCal.ShopLabel(lines, title, (t) => RegExMatch(t, "i)fishing|purch")), "", "nothing left of / above the grid")
    for L in lines
        if (L.x < 1000 && CraftTask.IsItem(L.text, "Lucky Potion"))
            AssertTrue(L.x < title.l + AutoCal.Shop.labels.l, "the picked item's name (left panel) is outside the label area")
    ; row 1's names read at 1x too; row 2's smaller ones need 2x
    one := AcLines("fishshop_buy_tab")
    AcNear(AutoCal.ShopLabel(one, AutoCal.ShopTitle(one), (t) => CraftTask.IsItem(t, "Icicle")), 1854, 596, 8, "Icicle at 1x")
    ; the Sell tab shows fish: no potion's name there
    sell := AcLines("fishshop_hell_sell")
    AssertEq(AutoCal.ShopLabel(sell, AutoCal.ShopTitle(sell), (t) => RegExMatch(t, "i)lucky")), "", "the Sell tab: no potion name")
    ; a name broken into two lines under its picture
    T := AcLine("Fishing Shop", 592, 342, 892, 378)
    two := [T, AcLine("Fortune Potion", 1240, 590, 1350, 606), AcLine("III", 1285, 612, 1305, 626), AcLine("Haste Potion", 1050, 590, 1160, 606), AcLine("III", 1095, 612, 1115, 626)]
    p2 := AutoCal.ShopLabel(two, T, (t) => CraftTask.IsItem(t, "Fortune Potion III"))
    AcNear(p2, 1295, 598 - AutoCal.Shop.labelUp, 2, "Fortune Potion III by its two-line name")
}

Test_AutoCal_NothingFoundOnOtherScreens() {
    for f in ["world_day", "inventory_open_day", "mari_day_buttons", "jester_shop"] {
        lines := AcLines(f)
        AssertEq(AutoCal.ShopTitle(lines), "", f ": no Fishing Shop")
        AssertEq(AutoCal.Workshop(lines), "", f ": no Workshop")
        AssertEq(AutoCal.Selector(lines, BiomeItemsTask.Drives), "", f ": no Biome Selector")
    }
    AssertEq(AutoCal.Workshop(AcLines("fishshop_hell_sell")), "", "the Fishing Shop is not the Workshop")
    AssertEq(AutoCal.Selector(AcLines("workshop_open"), BiomeItemsTask.Drives), "", "the Workshop is not the Selector")
    AssertEq(AutoCal.Workshop(""), "", "no read")
    AssertEq(AutoCal.Selector([], BiomeItemsTask.Drives), "", "nothing read")
}

; ---- Stella's Workshop --------------------------------------------------------------

; the title read as the craft task reads cauldron_gui (GuiPad, 1x then 2x)
AcGuiRead(name, gui) {
    pd := CraftTask.GuiPad
    for sc in [1, 2] {
        t := Ocr.ReadFile(AcPath(name), gui.x, Max(0, gui.y - pd.top), gui.w, gui.h + pd.top + pd.bottom, sc)
        if CraftTask.WorkshopUp(t)
            return t
    }
    return ""
}

Test_AutoCal_WorkshopFoundByItsTitle() {
    for f in ["workshop_open", "workshop_search_typed"] {
        lines := AcLines(f)
        ws := AutoCal.Workshop(lines)
        AssertTrue(IsObject(ws), f ": Stella's Workshop is found")
        AssertEq(ws.kx, 1, f ": its usual size")
        ; the title reads again at the place found (what the task checks before each click)
        AssertTrue(AcGuiRead(f, ws.gui) != "", f ": the title reads in the rect found")
        ; where the user calibrated them on this screen (2026-11-21)
        AcNear(ws.close, 2468, 232, 12, f ": close")
        AcNear(ws.search, 2140, 359, 6, f ": search")
        AcNear(ws.open, 311, 1107, 30, f ": Open Recipe")
        ; the X really is there: it reads at 2x around the place found
        x := Ocr.LinesFile(AcPath(f), 1800, 180, 760, 1100, 1, "i)^x$")
        AssertTrue(x.Length = 1 && Abs(x[1].x - ws.close.x) <= 6 && Abs(x[1].y - ws.close.y) <= 6, f ": the X reads at the place found")
        ; the search point is inside the search box: its text reads around it
        st := Ocr.ReadFile(AcPath(f), ws.search.x - 270, ws.search.y - 22, 540, 44)
        AssertTrue(RegExMatch(st, f = "workshop_open" ? "i)se[ao]rch" : "i)he[ao]venly"), f ": the search box is at the place found ('" st "')")
        ; Open Recipe reads at the place found
        AssertTrue(RegExMatch(Ocr.ReadFile(AcPath(f), ws.open.x - 150, ws.open.y - 30, 300, 60), "i)open\s*rec"), f ": Open Recipe reads there")
    }
}

Test_AutoCal_WorkshopCardsByTheirTitles() {
    f := "workshop_open"
    ws := AutoCal.Workshop(AcLines(f))
    lines := AcLines(f, ws.list)
    isR := (name) => ((t) => CraftTask.IsRecipe(t, name))
    c1 := AutoCal.Card(lines, isR("Fortune Potion I"), "", ws)
    ; the user's own cauldron_result on this screen: 1890,402,572,138
    AssertTrue(IsObject(c1) && Abs(c1.x - 1890) <= 8 && Abs(c1.y - 402) <= 8 && c1.w = 572 && c1.h = 138, "card 1 = the calibrated cauldron_result")
    c2 := AutoCal.Card(lines, isR("Fortune Potion II"), "", ws)
    ; ... and cauldron_result_2: 1885,580,576,141
    AssertTrue(IsObject(c2) && Abs(c2.x - 1885) <= 8 && Abs(c2.y - 580) <= 8, "card 2 = the calibrated cauldron_result_2")
    c3 := AutoCal.Card(lines, isR("Fortune Potion III"), "", ws)
    AssertTrue(IsObject(c3) && c3.y > c2.y + 150, "card 3 below card 2")
    ; the card found reads as that recipe (the task's check before the click)
    for pair in [[c1, "Fortune Potion I"], [c2, "Fortune Potion II"], [c3, "Fortune Potion III"]] {
        t := Ocr.ReadFile(AcPath(f), pair[1].x, pair[1].y, pair[1].w, pair[1].h)
        AssertTrue(CraftTask.IsRecipe(t, pair[2]), pair[2] ": its card reads its title first ('" t "')")
        for other in ["Fortune Potion I", "Fortune Potion II", "Fortune Potion III"]
            if (other != pair[2])
                AssertTrue(!CraftTask.IsRecipe(t, other), pair[2] "'s card is never " other)
    }
    AssertEq(AutoCal.Card(lines, isR("Heavenly Potion"), "", ws), "", "a recipe not in the list: no card")
    ; a description picks between cards (the Godly Potions): the lines under the title
    AssertTrue(IsObject(AutoCal.Card(lines, isR("Haste Potion I"), "Power of the Wind", ws)), "Haste Potion I's card says Power of the Wind")
    AssertEq(AutoCal.Card(lines, isR("Haste Potion I"), "Lord of Hell", ws), "", "... and not Lord of Hell")
    AssertEq(AutoCal.Card(lines, isR("Fortune Potion I"), "Power of the Wind", ws), "", "the next card's text is not this card's")
}

Test_AutoCal_WorkshopNeedsItsWholeTitle() {
    T := AcLine("Stello's Worl<shop", 2005, 229, 2348, 259)
    ws := AutoCal.Workshop([T])
    AssertTrue(IsObject(ws), "'Stello's Worl<shop' (the game font) is the title")
    AssertEq(ws.open, "", "Open Recipe not read: none (the task then uses the calibrated one)")
    AssertEq(ws.close.x "," ws.close.y, "2467,242", "the X from the title's right end")
    ; half a title has another middle: nothing is placed from it
    AssertEq(AutoCal.Workshop([AcLine("Workshop", 2180, 229, 2348, 259)]), "", "'Workshop' alone: not placed")
    AssertEq(AutoCal.Workshop([AcLine("Stella", 2005, 229, 2120, 259)]), "", "'Stella' alone: not placed")
    ; a Workshop that scales evenly on another shape: measured by its title
    big := AutoCal.Workshop([AcLine("Stella's Workshop", 1000, 200, 1000 + 412, 236)], 1)      ; 1.2x
    AssertTrue(Abs(big.kx - 1.2) < 0.01, "the title's width gives the scale")
    AssertEq(big.close.x, 1412 + Round(119 * big.kx), "the X scaled")
    AssertEq(big.search.y, 218 + Round(113 * big.ky), "the search box scaled")
}

; ---- Biome Selector ----------------------------------------------------------------

Test_AutoCal_SelectorListFoundByItsDrives() {
    ; the user's selector_list_rect on this screen: 822,515,672,416 (the
    ; window bobs ~32 px, so y follows the rows of each frame: the first
    ; row's middle is 30 below the rect's top)
    for f, row1 in Map("selector_list_night", 545, "selector_list_booting", 549, "selector_list_bobbed", 536) {
        r := AutoCal.Selector(AcLines(f), BiomeItemsTask.Drives)
        AssertTrue(IsObject(r), f ": the Drive list is found")
        AssertTrue(Abs(r.x - 822) <= 12 && r.w = 672 && r.h = 416, f ": x " r.x " w " r.w " h " r.h " = the calibrated rect")
        AssertTrue(Abs(r.y - (row1 - 30)) <= 8, f ": y " r.y " follows its rows (first row at " row1 ")")
        AssertTrue(Abs(AutoCal.SelectorConfirmX(r) - 1034) <= 12, f ": Confirm's x = the calibrated selector_confirm")
        ; the task's own check of the rect found: a Drive reads in it
        t := Ocr.ReadFile(AcPath(f), r.x, r.y, r.w, r.h)
        up := false
        for d in BiomeItemsTask.Drives
            up := up || BiomeItemsTask.RowIs(t, A_Index)
        AssertTrue(up, f ": a Drive reads in the rect found")
    }
    ; the prompt hides the rows, 'Auro Storage' behind it reads as "Star":
    ; one row is no list
    AssertEq(AutoCal.Selector(AcLines("selector_prompt_over_storage"), BiomeItemsTask.Drives), "", "the prompt over the Aura Storage: no list placed")
}

Test_AutoCal_SelectorRowsMustAgree() {
    D := BiomeItemsTask.Drives
    ; a row's name as it reads: centred on x 1156, 19.8 px a letter (k: a bigger window)
    row := (i, y, text := "", k := 1) => AcSelRow(text != "" ? text : D[i], y, k)
    ; three rows 50 apart: found, centred on the names
    r := AutoCal.Selector([row(1, 549), row(3, 649), row(4, 699)], D, 1)
    AssertEq(r.x "," r.y "," r.w "," r.h, "820,519,672,416", "three rows place the list")
    ; two rows are not enough, rows that do not fit one spacing neither
    AssertEq(AutoCal.Selector([row(1, 549), row(3, 649)], D, 1), "", "two rows: not placed")
    AssertEq(AutoCal.Selector([row(1, 549), row(3, 700), row(4, 1100)], D, 1), "", "rows off the spacing: not placed")
    ; a stray "Star" far above joins no row
    r2 := AutoCal.Selector([AcLine("Auro Storage", 1143, 386, 1416, 418), row(3, 649), row(4, 699), row(7, 849)], D, 1)
    AssertEq(r2.y, 519, "the stray line is left out")
    ; cut names give no middle: not placed
    AssertEq(AutoCal.Selector([row(1, 549, "Radiant"), row(3, 649, "Unknown"), row(4, 699, "Corrupt")], D, 1), "", "no whole name: no x, not placed")
    ; a Selector drawn 1.2x bigger: the row spacing gives the size
    r3 := AutoCal.Selector([row(1, 500, "", 1.2), row(3, 620, "", 1.2), row(4, 680, "", 1.2)], D, 1)
    AssertEq(r3.h, Round(416 * 1.2), "rows 60 apart: 1.2x")
    AssertEq(r3.w, Round(672 * 1.2), "... wide too")
    ; junk glued to a name, or a name cut short, has the wrong width: its
    ; middle is not used (live at 1080p: '*Unknown' + 'Void>Drive' put the
    ; list 28 px left)
    junk := AcLine("*Unknown Void>Drive", 924, 636, 1335, 662)
    r4 := AutoCal.Selector([row(1, 549), junk, row(4, 699)], D, 1)
    AssertEq(r4.x, 820, "the row with junk on it does not move the list")
    AssertEq(AutoCal.Selector([row(1, 549, "Radiant Star Dri"), junk, row(4, 699, "Corrupt Ruin Dr")], D, 1), "", "no row of the right width: not placed")
    ; a first or last letter lost still names its row
    r5 := AutoCal.Selector([row(1, 549), AcLine("nfernal", 979, 586, 1115, 612), AcLine("Chillin", 957, 786, 1095, 812)], D, 1)
    AssertEq(r5.y, 519, "'nfernal' and 'Chillin' are rows 2 and 6")
}

AcSelRow(text, y, k := 1) {
    wd := StrLen(text) * 19.8 * k
    return AcLine(text, Round(1156 - wd / 2), y - 13, Round(1156 + wd / 2), y + 13)
}

; ---- the craft task: Fisher shop tiles with no calibration ---------------------------

; a move within tol of x,y that was followed by a click
AcClickedNear(io, x, y, tol := 3) {
    for i, e in io.log
        if (RegExMatch(e, "^move (-?\d+),(-?\d+)$", &m) && Abs(m[1] - x) <= tol && Abs(m[2] - y) <= tol
            && i < io.log.Length && io.log[i + 1] = "click")
            return i
    return 0
}

Test_AutoCal_CraftBuysAPotionWithNoTileStep() {
    ; tester 2026-11-21: the Potion of Bound tile was calibrated onto Rainy
    ; Bottle and nothing was bought. No tile step now. It is in the shop's
    ; row 4, under the wheel: scrolled to and found by its name.
    m := CrMake(Map("pots", ["Potion of Bound"]))          ; no fisher_item_potion_of_bound
    io := m.io
    m.ocr.dyn["2000,200,400,60"] := () => CrGridName(io)
    m.t._env.linesFn := CrGridLinesFn(io)
    logs := CrLogs(m)
    AssertEq(m.t.BuyHere(SchedCtx()), 1, "bought")
    iTile := io.Idx("move 1127,900")
    AssertTrue(iTile > 0 && io.Idx("move 1400,100") > iTile, "its tile clicked where its name read, then Buy")
    AssertEq(io.Count("wheel down 1"), 2, "two rows down the list")
    AssertEq(CrClicksAt(io, "move 1125,596"), 0, "no other tile tried")
    AssertEq(m.wh.Count("errors"), 0, "no error")
    AssertTrue(CrSaid(logs, "Potion of Bound: tile found on screen at 1127,900"), "logged where")
    ; a potion in the two rows in sight: by its name, no scrolling
    m1 := CrMake(Map("pots", ["Gladiator Potion"]))
    io1 := m1.io
    m1.ocr.dyn["2000,200,400,60"] := () => CrGridName(io1)
    m1.t._env.linesFn := CrGridLinesFn(io1)
    AssertEq(m1.t.BuyHere(SchedCtx()), 1, "Gladiator Potion bought")
    AssertTrue(CrClicksAt(io1, "move 1856,900") > 0 && io1.Count("wheel down 1") = 0, "tile 8 by its name, no scrolling")
    ; no line reads at all: its place in the two rows in sight
    m4 := CrMake(Map("pots", ["Gladiator Potion"]))
    io4 := m4.io
    m4.ocr.dyn["2000,200,400,60"] := () => CrGridName(io4)
    AssertEq(m4.t.BuyHere(SchedCtx()), 1, "bought on the usual grid")
    AssertTrue(CrClicksAt(io4, "move 1854,900") > 0, "tile 8 of the grid")
    ; the shop lists it somewhere else: the name finds it, whatever the order
    stock := ["Lucky Potion", "Speed Potion", "Wind essence", "Icicle", "Rainy Bottle", "Potion of Bound"]
    m2 := CrMake(Map("pots", ["Potion of Bound"]))
    io2 := m2.io
    m2.ocr.dyn["2000,200,400,60"] := () => CrGridName(io2, stock)
    m2.t._env.linesFn := CrGridLinesFn(io2, stock)
    AssertEq(m2.t.BuyHere(SchedCtx()), 1, "found on the tile the shop really lists it on")
    AssertTrue(CrClicksAt(io2, "move 1370,900") > 0, "tile 6")
    AssertEq(io2.Count("wheel down 1"), 0, "found by its name, no scrolling")
    ; a name the shop does not sell is never placed (Calibrate.Potions drops
    ; it; a fake list here): nothing clicked in the grid
    m3 := CrMake(Map("pots", ["Mystery Brew"]))
    io3 := m3.io
    m3.t._env.linesFn := CrGridLinesFn(io3)
    AssertEq(m3.t.BuyHere(SchedCtx()), 0, "nothing bought")
    AssertEq(m3.io.Count("move 1400,100"), 0, "Buy never pressed")
    AssertEq(m3.io.Count("click", m3.io.Idx("wheel up " CraftTask.ScrollTopNotches)), 1, "no tile clicked (only the shop's X)")
    AssertEq(m3.wh.Count("errors"), 1, "reported")
}

Test_AutoCal_CraftTileFollowsTheTitleAndTheNames() {
    ; the shop's title read 10 px right and down: the grid moves with it
    m := CrMake(Map("pots", ["Gladiator Potion"], "lines", (x, y, w, h, scale := 1) => [AcLine("Fishing Shop", 602, 352, 902, 388)]))
    io := m.io
    m.ocr.dyn["2000,200,400,60"] := () => (CrLast(io, ["move 1864,910"]) && !CrShopShut(io)) ? "Gladiator Potion" : ""
    AssertEq(m.t.BuyHere(SchedCtx()), 1, "bought")
    AssertTrue(io.Idx("move 1864,910") > 0, "tile 8 from the title read")
    ; the potion's name reads under a picture somewhere else in the grid:
    ; that tile, whatever the order
    m2 := CrMake(Map("pots", ["Potion of Bound"], "lines", (x, y, w, h, scale := 1) => [AcLine("Fishing Shop", 592, 342, 892, 378)
        , AcLine("Lucky Potion", 1050, 590, 1170, 606), AcLine("Potion of Bound", 1620, 790, 1780, 806)]))
    io2 := m2.io
    m2.ocr.dyn["2000,200,400,60"] := () => (CrLast(io2, ["move 1700,749"]) && !CrShopShut(io2)) ? "Potion of Bound" : ""
    logs := CrLogs(m2)
    AssertEq(m2.t.BuyHere(SchedCtx()), 1, "bought")
    AssertTrue(io2.Idx("move 1700,749") > 0, "the tile its name is on (its centre, above the name)")
    AssertTrue(CrSaid(logs, "its name read in the grid"), "logged how")
    ; the lines read covers the title and the whole grid
    seen := []
    m3 := CrMake(Map("pots", ["Lucky Potion"], "drop", ["fisher_item_lucky_potion"], "lines", (x, y, w, h, scale := 1) => (seen.Push(x "," y "," w "," h), [])))
    io3 := m3.io
    m3.ocr.dyn["2000,200,400,60"] := () => CrGridName(io3)
    AssertEq(m3.t.BuyHere(SchedCtx()), 1, "bought on the usual grid when no line reads")
    AssertTrue(seen.Length >= 1, "the screen was read for the title")
    r := StrSplit(seen[1], ",")
    T := CraftTask.ShopTitle, B := CraftTask.GridBox
    AssertTrue(r[1] <= T.x && r[2] <= T.y && r[1] + r[3] >= B.x + B.w && r[2] + r[4] >= B.y + B.h, "one read: title and grid")
    ; a recorded tile is used first and nothing is read for it
    seen4 := []
    m4 := CrMake(Map("pots", ["Lucky Potion"], "lines", (x, y, w, h, scale := 1) => (seen4.Push(1), [])))
    AssertEq(m4.t.BuyHere(SchedCtx()), 1, "bought on its recorded tile")
    AssertTrue(m4.io.Idx("move 100,100") > 0 && seen4.Length = 0, "the recorded tile, no screen read")
}

; ---- the craft task: Stella's Workshop with no calibration ------------------------------

AcWsDrop() => ["cauldron_gui", "cauldron_search", "cauldron_result", "cauldron_open_recipe", "cauldron_close"]

; the Workshop's lines as read on the live frame (tests\screens\workshop_open)
AcWsLines(cards) {
    out := [AcLine("Stello's Worl<shop", 2005, 229, 2348, 259), AcLine("Item", 1986, 290, 2047, 308), AcLine("Lontern", 2282, 290, 2391, 308)
        , AcLine("Search...", 1921, 348, 2006, 362), AcLine("Open Recipe", 176, 1083, 392, 1111), AcLine("Auto", 543, 1088, 608, 1105)]
    for i, c in cards {
        y := 409 + (i - 1) * 181
        out.Push(AcLine(c[1], 2033, y, 2321, y + 25))
        out.Push(AcLine(c[2], 1895, y + 62, 2456, y + 80))
    }
    return out
}

Test_AutoCal_CraftCauldronWithNoCalibration() {
    ; only Add All is recorded: the title, the search box, the result card,
    ; Open Recipe and the X are found on screen
    lines := AcWsLines([["Heavenly Potion", "Those who toke this Potion will be Blessed."]])
    m := CrMake(Map("cauldron", true, "drop", AcWsDrop(), "lines", (x, y, w, h, scale := 1) => lines
        , "ocr", Map("1975,217,403,59", "Stello's Worl<shop", "1891,402,572,138", "Heavenly Potion`nThose who toke this Potion will be Blessed.")))
    logs := CrLogs(m)
    AssertEq(m.t.Run(SchedCtx()), 2, "buys done")
    io := m.io
    iFk := io.Idx("down f")
    AssertEq(io.Count("down f"), 1, "F once: the Workshop was seen")
    iSearch := io.Idx("move 2139,357", iFk)
    iType := io.Idx("type Heavenly Potion", iSearch)
    iCard := io.Idx("move 2177,471", iType)
    iOpen := io.Idx("move 284,1097", iCard)
    iAdd := io.Idx("move 1000,100", iOpen)
    iClose := io.Idx("move 2467,242", iAdd)
    AssertTrue(iSearch > 0 && iType > iSearch && iCard > iType && iOpen > iCard && iAdd > iOpen && iClose > iAdd
        , "search, type, the card, Open Recipe, Add All (recorded), the X: all at the places found")
    AssertEq(m.wh.Count("errors"), 0, "no error, no missing-step report")
    AssertTrue(CrSaid(logs, "Stella's Workshop found on screen"), "logged")
    ; between tasks the Workshop found this run can still be closed
    lo := m.t.Leftovers()
    AssertEq(lo.Length, 1, "the Workshop found this run is a leftover the tidy can close")
    ; Add All has no text to find: without it the cauldron is skipped, no F
    m2 := CrMake(Map("cauldron", true, "drop", ["cauldron_add_all"], "lines", (x, y, w, h, scale := 1) => lines))
    m2.t.Run(SchedCtx())
    AssertEq(m2.io.Count("down f"), 0, "no Add All step: no F")
}

Test_AutoCal_CraftCauldronCardsAndChecks() {
    ; another recipe first in the list: nothing is added
    lines := AcWsLines([["Fortune Potion II", "Those who toke this Potion will be Blessed."]])
    m := CrMake(Map("cauldron", true, "drop", AcWsDrop(), "gets", Map("Craft.craftTarget", "Fortune Potion I"), "lines", (x, y, w, h, scale := 1) => lines
        , "ocr", Map("1975,217,403,59", "Stella's Workshop", "1891,402,572,138", "Fortune Potion II`nThose who toke this Potion will be Blessed.")))
    m.t.Run(SchedCtx())
    AssertEq(m.io.Count("move 2177,471") + m.io.Count("move 284,1097") + m.io.Count("move 1000,100"), 0, "Fortune Potion II is never taken for Fortune Potion I")
    AssertTrue(m.io.Idx("move 2467,242") > 0, "the Workshop is closed with its X")
    AssertEq(m.wh.Count("errors"), 1, "reported")
    ; the title line says the recipe but the card read does not (a read of
    ; the screen between two frames): the card is not clicked
    lines2 := AcWsLines([["Heavenly Potion", "x"]])
    m2 := CrMake(Map("cauldron", true, "drop", AcWsDrop(), "lines", (x, y, w, h, scale := 1) => lines2
        , "ocr", Map("1975,217,403,59", "Stella's Workshop", "1891,402,572,138", "Fortune Potion I`nx")))
    m2.t.Run(SchedCtx())
    AssertEq(m2.io.Count("move 2177,471"), 0, "the card is read again before the click")
    ; a Godly Potion: the card whose lines name its Lord (no cauldron_result_2 needed)
    godly := AcWsLines([["Godly Potion", "Gives you 4 hours of [Lord of the Sky]"], ["Godly Potion", "Gives you 4 hours of [Lord of the Seo]"], ["Godly Potion", "Gives you 4 hours of [Lord of HeII]"]])
    for t in [["Godly Potion (Zeus)", 471, "the Sky"], ["Godly Potion (Poseidon)", 652, "the Seo"], ["Godly Potion (Hades)", 833, "HeII"]] {
        m3 := CrMake(Map("cauldron", true, "drop", AcWsDrop(), "gets", Map("Craft.craftTarget", t[1]), "lines", (x, y, w, h, scale := 1) => godly
            , "ocr", Map("1975,217,403,59", "Stella's Workshop", "1891," (t[2] - 69) ",572,138", "Godly Potion`nGives you 4 hours of [Lord of " t[3] "]")))
        m3.t.Run(SchedCtx())
        AssertTrue(m3.io.Idx("move 2177," t[2]) > 0, t[1] ": its own card (y " t[2] ")")
        AssertTrue(m3.io.Idx("move 1000,100") > 0, t[1] ": Add All")
        AssertEq(m3.wh.Count("errors"), 0, t[1] ": no error")
    }
    ; the title not read again at the place found: not open, nothing clicked
    m4 := CrMake(Map("cauldron", true, "drop", AcWsDrop(), "lines", (x, y, w, h, scale := 1) => lines2))
    m4.t.Run(SchedCtx())
    AssertEq(m4.io.Count("move 2139,357") + m4.io.Count("move 2467,242"), 0, "found by one read only: never clicked")
    AssertEq(m4.io.Count("down f"), CraftTask.GuiTries, "F tried again, as when it does not open")
}

Test_AutoCal_CraftCauldronCalibrationStillWins() {
    ; a full calibration whose title box reads: used as before, the screen
    ; is never searched
    n := 0
    m := CrMake(Map("cauldron", true, "lines", (x, y, w, h, scale := 1) => (n += 1, AcWsLines([["Heavenly Potion", "x"]]))))
    m.t.Run(SchedCtx())
    AssertTrue(m.io.Idx("move 700,100") > 0 && m.io.Idx("move 950,140") > 0 && m.io.Idx("move 1100,100") > 0, "the recorded search box, card and close")
    AssertEq(m.io.Count("move 2139,357") + m.io.Count("move 2467,242"), 0, "nothing at the places a screen read would give")
    AssertEq(n, 0, "no screen read for a calibration that reads")
    ; recorded in the wrong place (the title box reads nothing there): the
    ; Workshop found on screen is used instead
    lines := AcWsLines([["Heavenly Potion", "Those who toke this Potion will be Blessed."]])
    m2 := CrMake(Map("cauldron", true, "lines", (x, y, w, h, scale := 1) => lines
        , "ocr", Map("600,90,200,65", "", "1975,217,403,59", "Stella's Workshop", "1891,402,572,138", "Heavenly Potion`nx")))
    logs := CrLogs(m2)
    m2.t.Run(SchedCtx())
    AssertTrue(m2.io.Idx("move 2139,357") > 0 && m2.io.Idx("move 2177,471") > 0 && m2.io.Idx("move 2467,242") > 0, "the places found on screen")
    AssertEq(m2.io.Count("move 700,100") + m2.io.Count("move 950,140") + m2.io.Count("move 1100,100"), 0, "the wrong recorded places are not clicked")
    AssertTrue(CrSaid(logs, "the calibrated title box did not read it"), "logged why")
    AssertEq(m2.wh.Count("errors"), 0, "no error")
}

Test_AutoCal_CraftCauldronOnTheRealFrame() {
    ; the whole cauldron step against the live frame (search typed, the list
    ; not filtered yet: Fortune Potion I is the first card): the real OCR
    ; finds the Workshop and every click lands where the user calibrated it
    f := AcPath("workshop_search_typed")
    AssertTrue(FileExist(f), "frame exists")
    m := CrMake(Map("cauldron", true, "drop", AcWsDrop(), "gets", Map("Craft.enabled", 0, "Craft.craftTarget", "Fortune Potion I")
        , "ocrFn", (x, y, w, h, scale := 1) => Ocr.ReadFile(f, x, y, w, h, scale)
        , "lines", (x, y, w, h, scale := 1) => Ocr.LinesFile(f, x, y, w, h, scale)))
    m.t.Run(SchedCtx())
    io := m.io
    iSearch := AcClickedNear(io, 2140, 359, 6)                     ; cauldron_search
    iCard := AcClickedNear(io, 1890 + 286, 402 + 69, 10)           ; the middle of cauldron_result
    iOpen := AcClickedNear(io, 311, 1107, 30)                      ; cauldron_open_recipe
    iAdd := AcClickedNear(io, 1000, 100, 0)                        ; cauldron_add_all (recorded)
    iClose := AcClickedNear(io, 2468, 232, 12)                     ; cauldron_close
    AssertTrue(iSearch > 0, "the search box clicked where it is")
    AssertTrue(io.Idx("type Fortune Potion I") > iSearch, "the recipe typed")
    AssertTrue(iCard > iSearch && iOpen > iCard && iAdd > iOpen && iClose > iAdd, "the card, Open Recipe, Add All, the X: in order, at their places")
    AssertEq(m.wh.Count("errors"), 0, "no error")
    ; a recipe that is not the first card on this frame: nothing added
    m2 := CrMake(Map("cauldron", true, "drop", AcWsDrop(), "gets", Map("Craft.enabled", 0, "Craft.craftTarget", "Heavenly Potion")
        , "ocrFn", (x, y, w, h, scale := 1) => Ocr.ReadFile(f, x, y, w, h, scale)
        , "lines", (x, y, w, h, scale := 1) => Ocr.LinesFile(f, x, y, w, h, scale)))
    m2.t.Run(SchedCtx())
    AssertEq(AcClickedNear(m2.io, 311, 1107, 30) + AcClickedNear(m2.io, 1000, 100, 0), 0, "Heavenly Potion is not in the list: no Open Recipe, no Add All")
    AssertTrue(AcClickedNear(m2.io, 2468, 232, 12) > 0, "closed with its X")
}

; ---- the biome items task: the Selector's list with no calibration ------------------------

; AutoCal's Selector numbers for the test fake's window (list rect
; 500,400,600,800: rows 100 apart, Confirm at x 600), restored after fn.
AcWithFakeSelector(fn) {
    keep := AutoCal.Sel
    AutoCal.Sel := {w: 600, h: 800, pitch: 100, pitchMin: 70, pitchMax: 140, row1: 0.072
        , confirmDx: 100 / 600, minRows: 3, scaleTol: 0.06, rowTol: 0.25, sideTol: 320, charW: 300 / 18, widthTol: 0.08}
    try
        fn()
    finally
        AutoCal.Sel := keep
}

; rows 1, 3 and 4 of the fake's list as lines (names centred on x 800)
AcSelLines() {
    out := []
    for i in [1, 3, 4]
        out.Push(AcLine(BiomeItemsTask.Drives[i], 650, 445 + (i - 1) * 100, 950, 471 + (i - 1) * 100))
    return out
}

AcBiSaid(m, text) {
    for l in m.logs
        if InStr(l, text)
            return true
    return false
}

Test_AutoCal_SelectorWithNoCalibration() {
    AcWithFakeSelector(() => AcSelNoCal())
}
AcSelNoCal() {
    m := BiMake(Map("BiomeItems.biomeSelector", 1, "BiomeItems.selectorDrive", "Unknown Void Drive"), ["Biome Selector"], ["Select a biome using a Drive"]
        , Map("selector_list_rect", "DEL", "selector_confirm", "DEL"))
    m.t._env.linesFn := (x, y, w, h, scale := 1) => m.ocr.selector ? AcSelLines() : []
    AssertEq(m.t.CanRun(BiState()), true, "eligible with neither Selector step recorded")
    AssertEq(m.t.Run(SchedCtx()), 1, "used")
    AssertEq(m.ocr.confirmed, "Unknown Void Drive", "the Drive in settings confirmed")
    AssertTrue(m.io.Moved(600, 974), "Confirm at the x worked out from the list found")
    AssertTrue(AcBiSaid(m, "Drive list found on screen at 500,400"), "logged where")
    AssertEq(m.wh.Count("errors"), 0, "no error")
    ; nothing found on screen: nothing confirmed, and the report does not
    ; claim the Selector was closed
    m2 := BiMake(Map("BiomeItems.biomeSelector", 1, "BiomeItems.selectorDrive", "Unknown Void Drive"), ["Biome Selector"], ["x"]
        , Map("selector_list_rect", "DEL", "selector_confirm", "DEL"))
    AssertEq(m2.t.Run(SchedCtx()), 0, "nothing used")
    AssertEq(m2.ocr.confirmed, "", "Confirm never used")
    AssertEq(m2.wh.Count("errors"), 1, "reported")
    AssertTrue(InStr(m2.wh.sent[1].desc, "not found on screen") && !InStr(m2.wh.sent[1].desc, "were closed"), "says it could not be placed")
}

Test_AutoCal_SelectorCalibrationStillWins() {
    AcWithFakeSelector(() => AcSelCal())
}
AcSelCal() {
    ; both steps recorded and a Drive reads in the rect: never searched
    n := 0
    m := BiMake(Map("BiomeItems.biomeSelector", 1, "BiomeItems.selectorDrive", "Unknown Void Drive"), ["Biome Selector"], ["x"])
    m.t._env.linesFn := (x, y, w, h, scale := 1) => (n += 1, AcSelLines())
    AssertEq(m.t.Run(SchedCtx()), 1, "used")
    AssertEq(n, 0, "no screen read for a calibration that reads")
    AssertTrue(!AcBiSaid(m, "found on screen"), "nothing found on screen")
    ; recorded in the wrong place (no Drive reads there): the list found on
    ; screen is used, and Confirm's x comes from it too
    m2 := BiMake(Map("BiomeItems.biomeSelector", 1, "BiomeItems.selectorDrive", "Unknown Void Drive"), ["Biome Selector"], ["x"])
    m2.t._env.cal.r["selector_list_rect"] := {x: 1400, y: 300, w: 600, h: 800}
    m2.t._env.cal.p["selector_confirm"] := {x: 1500, y: 600, color: 0}
    m2.t._env.linesFn := (x, y, w, h, scale := 1) => m2.ocr.selector ? AcSelLines() : []
    AssertEq(m2.t.Run(SchedCtx()), 1, "used")
    AssertEq(m2.ocr.confirmed, "Unknown Void Drive", "confirmed")
    AssertTrue(m2.io.Moved(600, 974) && !m2.io.Moved(1500, 974), "Confirm where the list really is")
    AssertTrue(AcBiSaid(m2, "no Drive read in the calibrated selector_list_rect"), "logged why")
}

; ---- Calibrate / Check my setup / the Calibrate page ------------------------------------

AcTmpCal() {
    d := A_Temp "\vesper_autocal_" A_TickCount "_" Random(100000, 999999)
    DirCreate(d)
    return d
}

Test_AutoCal_CalibrateStepsFoundOnScreen() {
    d := AcTmpCal()
    try {
        Calibrate.Use(d "\cal.json")
        auto := Map()
        for s in Calibrate.Steps()
            auto[s["id"]] := s["auto"]
        for id in ["fisher_item_lucky_potion", "cauldron_gui", "cauldron_search", "cauldron_result", "cauldron_result_2", "cauldron_open_recipe", "cauldron_close"
            , "selector_list_rect", "selector_confirm"]
            AssertEq(auto[id], true, id " is marked found on screen")
        for id in ["cauldron_add_all", "fisher_buy_button", "fisher_picked_name", "fisher_open_shop", "inv_open", "inv_tile2_rect", "aura_equip", "notify_rect", "chat_rect"]
            AssertEq(auto[id], false, id " still needs recording")
        ; Run all = the steps that need hovering
        hand := Calibrate.ResolveIds("hand")
        for s in hand
            AssertTrue(!s["auto"], s["id"] ": a step found on screen is not in the hand list")
        AssertEq(hand.Length, Calibrate.ResolveIds("all").Length - 19, "19 steps fewer to hover (one potion, the Workshop, the Selector, the inventory, the quest board)")
        ; by hand: an automatic step can still be asked for by its id
        AssertEq(Calibrate.ResolveIds("cauldron_gui,selector_confirm").Length, 2, "an automatic step is still recordable by id")
        ; ready without a recording; a recording is kept and read as before
        AssertEq(Calibrate.Ready("cauldron_gui"), true, "found on screen: ready unrecorded")
        AssertEq(Calibrate.Ready("cauldron_add_all"), false, "Add All: not ready until recorded")
        AssertEq(Calibrate.Rect("cauldron_gui"), "", "not recorded: no rect is invented")
        Calibrate.SetRect("cauldron_gui", 1861, 222, 2447, 257)
        Calibrate.SetPoint("cauldron_add_all", 1104, 911, 0x100E03)
        AssertEq(Calibrate.Rect("cauldron_gui").x, 1861, "a recording by hand is stored")
        AssertEq(Calibrate.Ready("cauldron_add_all"), true, "recorded: ready")
        ; "Check my setup": no step found on screen is ever reported missing
        miss := SetupCheck._CalMissing()
        for id in miss
            AssertTrue(!AutoCal.IsAuto(id), id ": a step found on screen is never missing")
        AssertTrue(AcHas(miss, "fisher_buy_button") && AcHas(miss, "inv_open"), "steps that need hovering are still listed")
        AssertTrue(!AcHas(miss, "cauldron_add_all"), "a recorded step is not missing")
    } finally {
        Calibrate.Use(A_Temp "\vesper_cal_unused.json")
        try DirDelete(d, true)
    }
}

AcHas(arr, want) {
    for v in arr
        if (v = want)
            return true
    return false
}

Test_AutoCal_CheckMySetupWithAFreshInstall() {
    ; the cauldron and the Fish shop switched on, nothing recorded for the
    ; steps found on screen: the calibration row does not ask for them
    d := AcTmpCal()
    try {
        Calibrate.Use(d "\cal.json")
        for s in Calibrate.Steps()
            if (!s["auto"] && s["kind"] = "point")
                Calibrate.SetPoint(s["id"], 100, 100, 0)
            else if !s["auto"]
                Calibrate.SetRect(s["id"], 100, 100, 200, 200)
        cfg := {Get: (self, k, dflt := "") => (k = "Craft.cauldron" || k = "Craft.enabled" || k = "BiomeItems.enabled") ? 1 : dflt, Webhooks: (self) => []}
        rows := SetupCheck.Run(cfg, Map("hwnd", () => 0, "logAge", () => 30, "procs", (n) => false, "ahkVersion", () => "2.0.19"
            , "scale", () => 100, "hdr", () => 0, "front", () => 0))
        cal := ""
        for r in rows
            if (r.id = "calibration")
                cal := r
        AssertTrue(IsObject(cal), "the calibration row is there")
        AssertEq(cal.level, "ok", "every step that needs recording is recorded: ok (" cal.detail ")")
    } finally {
        Calibrate.Use(A_Temp "\vesper_cal_unused.json")
        try DirDelete(d, true)
    }
}

Test_AutoCal_CalibratePageRunAllSkipsAutomaticSteps() {
    dir := UiDashTmp()
    d := ""
    try {
        cfg := Config.Load(dir)
        Calibrate.Use(dir "\cal.json", cfg)
        asked := []
        d := Dashboard(cfg, Map("calibrate", (ids) => (asked.Push(ids), 0)))
        d._CalRun("all")
        AssertEq(asked.Length, 1, "the wizard was asked once")
        AssertEq(asked[1], "hand", "Run all = the steps that need hovering")
        ; Record selected on an automatic row: calibrating it by hand stays possible
        lv := d.Ctrl("calibrate")
        row := UiDashRow(lv, "cauldron_gui")
        AssertTrue(row > 0, "cauldron_gui is listed")
        lv.Modify(0, "-Select")
        lv.Modify(row, "Select")
        d._CalRun("selected")
        AssertTrue(asked.Length = 2 && asked[2] is Array && asked[2].Length = 1 && asked[2][1] = "cauldron_gui", "Record selected records the automatic step by hand")
    } finally {
        UiDashClose(d)
        Calibrate.Use(A_Temp "\vesper_cal_unused.json")
        try DirDelete(dir, true)
    }
}

; ---- the tasks' own finds on the real frames ------------------------------------------------

Test_AutoCal_CraftTileOnTheRealShopFrame() {
    ; the craft task's own read of the open shop (title + grid) on the live
    ; Buy tab frame (2026-11-21 03:17; live it found Lucky Potion by its
    ; name and bought it)
    f := AcPath("fishshop_buy_tab")
    m := CrMake(Map("pots", ["Lucky Potion"], "drop", ["fisher_item_lucky_potion"]
        , "lines", (x, y, w, h, scale := 1) => Ocr.LinesFile(f, x, y, w, h, scale)))
    centres := [[1125, 596], [1368, 596], [1611, 596], [1854, 596], [1125, 900], [1368, 900], [1611, 900], [1854, 900]]
    for i, c in centres {
        n := GameLists.Shop[i]
        at := m.t._AutoTile(n)
        AssertTrue(IsObject(at), n ": found")
        if !IsObject(at)
            continue
        ; a click there is well inside the tile (229 x 293)
        AssertTrue(Abs(at.x - c[1]) <= 12 && Abs(at.y - c[2]) <= 12, n ": " at.x "," at.y " is on its tile's centre " c[1] "," c[2])
        AssertTrue(InStr(at.how, "name read"), n ": by its name under its picture (" at.how ")")
        ; and the name box reads it once picked? (only Lucky Potion is picked on this frame)
    }
    AssertTrue(CraftTask.IsItem(Ocr.ReadFile(f, 600, 830, 380, 80), "Lucky Potion"), "the picked item's name reads on the frame")
    ; the rows under the wheel: no place worked out, the wheel search looks for the name
    for n in ["Eternal Flame", "Potion of Bound", "Heavenly Potion"]
        AssertEq(m.t._AutoTile(n), "", n ": not in sight, no tile")
    AssertEq(m.t._AutoTile("Not In The Shop"), "", "not a shop item: no tile")
    ; the Sell tab shows fish: a fish's name is never taken for a potion
    fs := AcPath("fishshop_hell_sell")
    m2 := CrMake(Map("pots", ["Lucky Potion"], "drop", ["fisher_item_lucky_potion"]
        , "lines", (x, y, w, h, scale := 1) => Ocr.LinesFile(fs, x, y, w, h, scale)))
    for n in GameLists.Shop {
        at := m2.t._AutoTile(n)
        AssertTrue(!IsObject(at) || !InStr(at.how, "name read"), n ": no fish name passes for it")
    }
}

Test_AutoCal_SelectorOnTheRealFrames() {
    ; the biome items task with neither Selector step recorded, the real OCR
    ; on the live frames: the list is found and the click lands on the
    ; Drive's own row
    state := A_Temp "\vesper_bi_autocal_test.json"
    for f, want in Map("selector_list_night", ["Raging Gale Drive", 899], "selector_list_bobbed", ["Unknown Void Drive", 639]) {
        path := AcPath(f)
        for p in [state, state ".tmp"]
            try FileDelete(p)
        io := BiIO(BiOcr([], []))
        logs := []
        t := BiomeItemsTask({cfg: BiCfg(Map("BiomeItems.biomeSelector", 1)), io: io, webhook: BiWh()
            , cal: BiCal(Map("selector_list_rect", "DEL", "selector_confirm", "DEL")), log: (s) => logs.Push(s)
            , ocr: AcFileOcr(path), lines: AcFileLines(path), now: () => 1000, statePath: state})
        AssertEq(t._FindSelector(), 1, f ": the list is found on screen")
        r := t._SelRect()
        AssertTrue(IsObject(r) && Abs(r.x - 822) <= 12 && r.w = 672, f ": at the calibrated x (" (IsObject(r) ? r.x : "none") ")")
        AssertEq(t._SelectorUp(), true, f ": the Selector reads as up in the rect found")
        AssertEq(t._PickDrive(want[1], SchedCtx()), 1, f ": " want[1] " clicked")
        cx := 0, cy := 0
        for e in io.log
            if RegExMatch(e, "^move (\d+),(\d+)$", &mm)
                cx := Integer(mm[1]), cy := Integer(mm[2])
        AssertTrue(Abs(cx - 1158) <= 15 && Abs(cy - want[2]) <= 16, f ": the click " cx "," cy " is on " want[1] "'s row (y " want[2] ")")
        AssertTrue(Abs(t._ConfirmX(r) - 1034) <= 12, f ": Confirm's x")
    }
    for p in [state, state ".tmp"]
        try FileDelete(p)
}

AcFileOcr(path) => (x, y, w, h, scale := 1) => Ocr.ReadFile(path, x, y, w, h, scale)
AcFileLines(path) => (x, y, w, h, scale := 1) => Ocr.LinesFile(path, x, y, w, h, scale)

; ---- other resolutions (the real frames scaled, as test_resample.ahk) -------------------------

; The windows are found, in DESIGN px, when the game runs at 1920x1080 and
; at 1366x768 (frames scaled by GDI+, a stand-in for the game drawn at that
; size): Ocr.Lines gives design px at any client size.
Test_AutoCal_FoundAtOtherResolutions() {
    bad := ""
    try {
        for size in [[1920, 1080], [1366, 768]] {
            cw := size[1], ch := size[2], f := cw / 2560, tag := cw "x" ch
            RsAt(cw, ch)
            ; Fisher shop: the title places tile 1
            title := AutoCal.ShopTitle(Ocr.LinesFile(RsFrame("fishshop_hell_sell", f), 0, 0, 2560, 1440))
            t1 := AutoCal.ShopTile(title, 1)
            if !(IsObject(title) && Abs(t1.x - 1125) <= 10 && Abs(t1.y - 596) <= 10)
                bad .= " | " tag " shop tile 1 " (IsObject(title) ? t1.x "," t1.y : "(no title)")
            ; Stella's Workshop
            p := RsFrame("workshop_open", f)
            ws := AutoCal.Workshop(Ocr.LinesFile(p, 0, 0, 2560, 1440))
            if !IsObject(ws)
                bad .= " | " tag " workshop not found"
            else {
                if !(Abs(ws.close.x - 2468) <= 14 && Abs(ws.close.y - 232) <= 16)
                    bad .= " | " tag " workshop close " ws.close.x "," ws.close.y
                if !(Abs(ws.search.x - 2140) <= 14 && Abs(ws.search.y - 359) <= 10)
                    bad .= " | " tag " workshop search " ws.search.x "," ws.search.y
                if !(IsObject(ws.open) && Abs(ws.open.x - 311) <= 34 && Abs(ws.open.y - 1107) <= 16)
                    bad .= " | " tag " workshop Open Recipe"
                c1 := AutoCal.Card(Ocr.LinesFile(p, ws.list.x, ws.list.y, ws.list.w, ws.list.h), (t) => CraftTask.IsRecipe(t, "Fortune Potion II"), "", ws)
                if !(IsObject(c1) && Abs(c1.x - 1885) <= 14 && Abs(c1.y - 580) <= 12)
                    bad .= " | " tag " workshop card 2 " (IsObject(c1) ? c1.x "," c1.y : "(none)")
                else if !CraftTask.IsRecipe(Ocr.ReadFile(p, c1.x, c1.y, c1.w, c1.h), "Fortune Potion II")
                    bad .= " | " tag " workshop card 2 does not read as Fortune Potion II"
            }
            ; nothing found on a plain game screen
            if (IsObject(AutoCal.Workshop(Ocr.LinesFile(RsFrame("world_day", f), 0, 0, 2560, 1440)))
                || IsObject(AutoCal.ShopTitle(Ocr.LinesFile(RsFrame("world_day", f), 0, 0, 2560, 1440))))
                bad .= " | " tag " something found on world_day"
        }
    } finally {
        Screen.Reset()
    }
    AssertEq(bad, "", "found at 1080p and 768p")
}

; The Biome Selector's list at 1920x1080 (its thin coloured names over the
; world read worse when small: found on at least two of the three frames,
; never in a wrong place).
Test_AutoCal_SelectorFoundAt1080p() {
    found := 0, bad := ""
    try {
        RsAt(1920, 1080)
        for f, row1 in Map("selector_list_night", 545, "selector_list_booting", 549, "selector_list_bobbed", 536) {
            p := RsFrame(f, 0.75)
            r := AutoCal.Selector(Ocr.LinesFile(p, 0, 0, 2560, 1440), BiomeItemsTask.Drives)
            if !IsObject(r)
                r := AutoCal.Selector(Ocr.LinesFile(p, 640, 300, 1280, 840, 2), BiomeItemsTask.Drives)     ; the task's second look
            if !IsObject(r)
                continue
            found++
            if !(Abs(r.x - 822) <= 16 && Abs(r.y - (row1 - 30)) <= 12 && r.w = 672 && r.h = 416)
                bad .= " | " f ": " r.x "," r.y "," r.w "," r.h
        }
    } finally {
        Screen.Reset()
    }
    AssertEq(bad, "", "never placed wrong at 1080p")
    AssertTrue(found >= 2, "found on " found " of 3 frames at 1080p")
}

; ===========================================================================
; The inventory and the quest board (2026-11-21, second part)
;
; REAL FRAMES: inventory_open_day / _rainy / _sand (already here),
; inv_randomizer_selected_sand (the overnight watcher, 03:44: Biome
; Randomizer searched and selected), quest_page_full_claim_day and
; quest_page_full_claim_night (01:14 / 01:27: the board with Claim Rewards up;
; the night one makes the recognizer turn the picture by the poster's slant,
; so its boxes come back turned: Ocr turns them back). Only the window is
; kept in the new frames, the rest is black (chat, player list, boards).
; The places found are checked against the 2560x1440 preset's recordings.
; ===========================================================================
#Include ..\lib\tasks\InvFind.ahk
#Include ..\lib\tasks\Quests.ahk
#Include ..\lib\MatchVision.ahk

; pixels of a frame's box, as TaskEnv's rect dep gives them (row by row)
AcFileRect(path) {
    g := MatchFileGrab(path)
    return (x, y, w, h) => AcGrabFlat(g, x, y, w, h)
}
AcGrabFlat(g, x, y, w, h) {
    ys := []
    Loop h
        ys.Push(y + A_Index - 1)
    out := []
    for row in g.Call(x, x + w - 1, ys)
        for c in row
            out.Push(c)
    return out
}

; ---- Ocr: a picture the recognizer turns ----------------------------------------------

Test_AutoCal_OcrBoxesTurnedBack() {
    ; the same board by day and by night: at night the recognizer finds the
    ; poster's slanted text and gives every box in a picture turned by
    ; -4.8 degrees ("Exit" 45 px right, "Objects" 80 px up). Turned back,
    ; both frames give the same places.
    for f in ["quest_page_full_claim_day", "quest_page_full_claim_night"] {
        lines := AcLines(f)
        AcNear(AutoCal.Find(lines, "i)^exit$"), 1282, 1254, 4, f ": Exit")
        AcNear(AutoCal.Find(lines, "i)^objects$"), 2254, 535, 4, f ": Objects")
        AcNear(AutoCal.Find(lines, "i)^dismiss$"), 2374, 1087, 4, f ": Dismiss")
    }
    p := Ocr.Turn(100, 0, 0, 0, 90)
    AssertTrue(Abs(p.x) < 0.001 && Abs(p.y - 100) < 0.001, "Turn: a quarter turn about the middle")
    q := Ocr.Turn(7, 9, 7, 9, 33)
    AssertTrue(Abs(q.x - 7) < 0.001 && Abs(q.y - 9) < 0.001, "Turn: the middle stays")
}

; ---- inventory: found by its title and tabs ------------------------------------------

Test_AutoCal_InventoryFoundByItsTitle() {
    ; the 2560x1440 preset: inv_items_tab 1684,445  inv_search 1434,487
    ; inv_use 913,770  inv_tile1_rect 1076,578,110,112  inv_desc_rect 648,812,367,243
    for f in ["inventory_open_day", "inventory_open_rainy", "inventory_open_sand", "inv_randomizer_selected_sand"] {
        inv := AutoCal.Inventory(AcLines(f))
        AssertTrue(IsObject(inv), f ": the inventory is found")
        AcNear(inv.tab, 1684, 445, 14, f ": the Items tab")
        AcNear(inv.search, 1434, 487, 6, f ": the search box")
        AcNear(inv.use, 913, 770, 6, f ": Use")
        AssertTrue(IsObject(inv.desc) && Abs(inv.desc.x - 648) <= 6 && Abs(inv.desc.y - 812) <= 6 && inv.desc.w = 367 && inv.desc.h = 243, f ": the description box")
        AssertTrue(IsObject(inv.tile1) && Abs(inv.tile1.x - 1076) <= 4 && Abs(inv.tile1.y - 578) <= 4 && inv.tile1.w = 110 && inv.tile1.h = 112, f ": the first tile's name box")
        ; the tasks' own reads at the places found
        env := TaskEnv({ocr: AcFileOcr(AcPath(f))})
        AssertTrue(env.InvOpen(inv.tab), f ": the tabs read around the tab found (TaskEnv.InvOpen)")
        AssertTrue(StrLen(Trim(Ocr.ReadFile(AcPath(f), inv.desc.x, inv.desc.y, inv.desc.w, inv.desc.h))) >= 5, f ": the description reads in the box found")
    }
    UiStuck.Reset()
    ; the item searched for reads in the first tile's box (what the tasks check)
    f := "inv_randomizer_selected_sand"
    inv := AutoCal.Inventory(AcLines(f))
    t := Ocr.ReadFile(AcPath(f), inv.tile1.x, inv.tile1.y, inv.tile1.w, inv.tile1.h)
    AssertTrue(GameText.Has(t, "randomizer"), "Biome Randomizer reads in the tile box ('" t "')")
    AssertTrue(RegExMatch(Ocr.ReadFile(AcPath(f), inv.desc.x, inv.desc.y, inv.desc.w, inv.desc.h), "i)dimension|biome"), "its description reads in the box")
    ; no inventory on other screens, and the word alone is no window
    for g in ["world_day", "fishshop_hell_sell", "workshop_open", "quest_page_full_claim_day", "mari_day_buttons"]
        AssertEq(AutoCal.Inventory(AcLines(g)), "", g ": no inventory")
    ; the title alone gives the tab's place only: the caller reads the tabs
    ; there (TaskEnv.InvOpen) before it believes it
    bare := AutoCal.Inventory([AcLine("Inventory", 1182, 386, 1382, 418)])
    AssertTrue(IsObject(bare) && bare.tab.x = 1282 + 414 && bare.tab.y = 402 + 47, "the title places the Items tab")
    half := AutoCal.Inventory([AcLine("Inventory", 1182, 386, 1382, 418), AcLine("Geors", 1218, 442, 1281, 456)])
    AssertTrue(IsObject(half) && half.tab.x = 1282 + 414 && half.tab.y = 449, "Gears places the Items tab beside it")
    AssertTrue(half.use = "" && half.search = "" && half.tile1 = "" && half.desc = "", "nothing read where they would be: Use, search, tile and description are not placed")
    full := AutoCal.Inventory(AcLines("inventory_open_day"))
    mg := AutoCal.InvMerge(half, full)
    AssertTrue(IsObject(mg.use) && IsObject(mg.search) && IsObject(mg.tile1) && mg.tab.y = 449, "a closer read fills the parts the first one missed")
}

; ---- quest board: found by "Objects", its buttons and Exit ------------------------------

Test_AutoCal_QuestBoardFoundByItsWords() {
    ; the 2560x1440 preset: quest_board_rect 2024,489,458,326  quest_accept
    ; 2169,1081  quest_dismiss 2371,1086  quest_close 1278,1263  quest_next 1815,721
    for f in ["quest_page_full_claim_day", "quest_page_full_claim_night"] {
        path := AcPath(f)
        lines := AcLines(f)
        p := AutoCal.QuestPanel(lines)
        AssertTrue(IsObject(p), f ": the panel is found")
        AssertTrue(Abs(p.rect.x - 2024) <= 6 && Abs(p.rect.y - 489) <= 6 && p.rect.w = 458 && p.rect.h = 326, f ": quest_board_rect (" p.rect.x "," p.rect.y ")")
        AcNear(p.dismiss, 2371, 1086, 8, f ": Dismiss")
        AssertTrue(Abs(p.accept.x - 2169) <= 40 && Abs(p.accept.y - 1081) <= 8, f ": the Accept / Claim Rewards button")
        ; the task's own reads: the quest's title in the panel, the word on the button
        a := QuestsTask.Panel(p.rect)
        t := Ocr.ReadFile(path, a.x, a.y, a.w, a.h)
        AssertTrue(QuestsTask.PanelUp(t) && InStr(QuestsTask.Key(t), "nullbreokthrough") = 1, f ": the panel reads its quest ('" QuestsTask.Title(t) "')")
        b := QuestsTask.Button
        AssertEq(QuestsTask.WordOf(Ocr.ReadFile(path, p.accept.x + b.dx, p.accept.y + b.dy, b.w, b.h)), "claim", f ": Claim Rewards reads around the button found")
        AssertTrue(RegExMatch(Ocr.ReadFile(path, p.dismiss.x + b.dx, p.dismiss.y + b.dy, b.w, b.h), "i)d[il1]sm"), f ": Dismiss reads around its place")
        ex := AutoCal.QuestExit(lines)
        AcNear(ex.close, 1278, 1263, 12, f ": Exit")
        AcNear(ex.next, 1815, 721, 6, f ": the > arrow")
        e := QuestsTask.ExitBox
        AssertTrue(RegExMatch(Ocr.ReadFile(path, ex.close.x + e.dx, ex.close.y + e.dy, e.w, e.h), QuestsTask.ExitRe), f ": Exit reads where the task checks it")
        ; the arrow has no word: its pixels (a dark button, a white glyph)
        rect := AcFileRect(path)
        n := AutoCal.Quest.arrowBox
        AssertTrue(AutoCal.IsArrow(rect(ex.next.x - n // 2, ex.next.y - n // 2, n, n)), f ": the > arrow's pixels")
        AssertTrue(AutoCal.IsArrow(rect(745 - n // 2, 720 - n // 2, n, n)), f ": the < arrow looks the same")
        ; (a dark button with white on it: the poster, the wall and the
        ; panel's text are none; the Exit button would pass, it is one)
        for spot in [[1600, 720], [1815, 900], [1280, 500], [2254, 535], [1815, 600]]
            AssertTrue(!AutoCal.IsArrow(rect(spot[1] - n // 2, spot[2] - n // 2, n, n)), f ": no arrow at " spot[1] "," spot[2])
    }
    ; (named quest_page_*: the other tasks' "is the Quest Board up" checks
    ; read true on them, as on the cropped quest_page_a..c)
    for f in ["quest_page_full_claim_day", "quest_page_full_claim_night"] {
        b := ObbyTask.QuestBox
        AssertTrue(RegExMatch(Ocr.ReadFile(AcPath(f), b.x, b.y, b.w, b.h), ObbyTask.QuestRe), f ": the obby task's Quest Board check reads it too")
    }
    for g in ["world_day", "inventory_open_day", "workshop_open", "fishshop_hell_sell", "selector_list_night"] {
        AssertEq(AutoCal.QuestPanel(AcLines(g)), "", g ": no quest panel")
        AssertEq(AutoCal.QuestExit(AcLines(g)), "", g ": no Exit")
    }
    AssertTrue(!AutoCal.IsArrow("") && !AutoCal.IsArrow([]), "no pixels: no arrow")
    ; "Objects" without a button in its row under it (the panel moving, or
    ; another window's word): not placed
    O := AcLine("Objects", 2147, 512, 2360, 557)
    AssertEq(AutoCal.QuestPanel([O]), "", "Objects alone")
    AssertEq(AutoCal.QuestPanel([O, AcLine("Dismiss", 2360, 1000, 2480, 1020)]), "", "a button that is not in its row")
    ok := AutoCal.QuestPanel([O, AcLine("Accept", 2090, 1078, 2176, 1096)])
    AssertTrue(IsObject(ok) && ok.dismiss.x = 2253 + 120 && ok.accept.x = 2253 - 121, "Accept alone places both buttons")
}

; ---- the quest task with no board step recorded, on the real frame ----------------------

AcQuestOnFrame(f, cal) {
    path := AcPath(f)
    io := QmIO()
    wh := QmWh()
    logs := []
    t := QuestsTask({cfg: QmCfg(, Map("quests", QmQuestsCfg(), "routes", QmRoutesData())), io: io, webhook: wh, cal: cal
        , log: (s) => logs.Push(s), ocr: AcFileOcr(path), lines: AcFileLines(path), rect: AcFileRect(path)})
    return {t: t, io: io, wh: wh, logs: logs}
}

; the last move before each click, as "x,y" strings
AcClicks(io) {
    out := [], last := ""
    for e in io.log {
        if RegExMatch(e, "^move (-?\d+),(-?\d+)$", &m)
            last := {x: Integer(m[1]), y: Integer(m[2])}
        else if (e = "click" && IsObject(last))
            out.Push(last)
    }
    return out
}
AcClickNear(clicks, x, y, tol) {
    n := 0
    for c in clicks
        n += (Abs(c.x - x) <= tol && Abs(c.y - y) <= tol) ? 1 : 0
    return n
}

Test_AutoCal_QuestsOnTheRealBoardWithNoCalibration() {
    for f in ["quest_page_full_claim_day", "quest_page_full_claim_night"] {
        m := AcQuestOnFrame(f, QmCal())                 ; nothing recorded
        AssertEq(m.t.CanRun(SchedState()), true, f ": eligible with no board step recorded")
        m.t.Run(SchedCtx())
        c := AcClicks(m.io)
        ; the frame shows one quest with Claim Rewards up: pressed once (it
        ; stays: not finished), then >, then Exit
        AssertEq(AcClickNear(c, 2133, 1087, 6), 1, f ": Claim Rewards pressed once, on the button")
        AssertTrue(AcClickNear(c, 2169, 1081, 40) = 1, f ": ... where quest_accept is recorded in the preset")
        AssertEq(AcClickNear(c, 1815, 721, 6), 1, f ": > clicked where quest_next is recorded")
        AssertEq(AcClickNear(c, 1278, 1263, 12), 1, f ": Exit clicked where quest_close is recorded")
        AssertEq(AcClickNear(c, 2371, 1086, 60), 0, f ": Dismiss never clicked")
        AssertTrue(QmSaid(m.logs, "the board found on screen (panel at 202"), f ": logged")
        AssertTrue(QmSaid(m.logs, "closed the board"), f ": closed")
        AssertEq(m.wh.Count("errors"), 0, f ": no error")
    }
}

Test_AutoCal_QuestsRecordedInTheWrongPlace() {
    ; recorded for another screen: nothing reads in the recorded panel after
    ; E. One look finds the board; the steps found are used for the visit.
    wrong := QmCal(Map("quest_accept", {x: 300, y: 300, color: 0}, "quest_dismiss", {x: 500, y: 300, color: 0}
        , "quest_close", {x: 300, y: 1300, color: 0}, "quest_next", {x: 400, y: 100, color: 0})
        , Map("quest_board_rect", {x: 100, y: 500, w: 400, h: 300}))
    m := AcQuestOnFrame("quest_page_full_claim_day", wrong)
    m.t.Run(SchedCtx())
    c := AcClicks(m.io)
    AssertEq(AcClickNear(c, 2133, 1087, 6), 1, "Claim Rewards on the button found")
    AssertEq(AcClickNear(c, 1282, 1254, 6), 1, "Exit where it reads")
    AssertEq(AcClickNear(c, 1815, 720, 6), 1, "> where it is")
    for p in [[300, 300], [500, 300], [300, 1300], [400, 100]]
        AssertEq(AcClickNear(c, p[1], p[2], 3), 0, "the wrong recorded spot " p[1] "," p[2] " is never clicked")
    AssertTrue(QmSaid(m.logs, "nothing read in the calibrated quest_board_rect"), "logged why")
    ; the board is not there at all (a plain game screen): nothing clicked
    m2 := AcQuestOnFrame("world_day", QmCal())
    m2.t.Run(SchedCtx())
    for cl in AcClicks(m2.io)
        AssertTrue(!(cl.x > 1700 && cl.y > 300) && !(Abs(cl.x - 1282) < 60 && Abs(cl.y - 1254) < 60), "no board button clicked on a plain screen (" cl.x "," cl.y ")")
    AssertTrue(QmSaid(m2.logs, "did not open"), "said the board did not open")
}

Test_AutoCal_QuestsCalibratedBoardIsNeverSearched() {
    ; a recorded board that reads: as before, the screen is never searched
    n := 0
    board := QmBoard([["Resonance`n***`nObjects`nReach resonance"], ["Mythic Aura Hunt`n***`nRoll a Mythic aura"]])
    m := QmBoardTask(board)
    m.t._env.linesFn := (x, y, w, h, scale := 1) => (n += 1, [AcLine("Objects", 2147, 512, 2360, 557), AcLine("Dismiss", 2311, 1076, 2437, 1097), AcLine("Exit", 1246, 1241, 1318, 1267)])
    m.t.Run(SchedCtx())
    AssertEq(n, 0, "no screen read for a calibration that reads")
    AssertTrue(m.io.Moved(100, 200) && m.io.Moved(700, 800), "the recorded Accept and Exit")
    for e in m.io.log
        AssertTrue(!RegExMatch(e, "^move (2133|2374|1282|1815),"), "nothing at a place a screen read would give (" e ")")
    ; one step missing (quest_next), the rest recorded and reading: the
    ; recorded ones are used; > is not looked for while the panel reads
    cal := QmBoardCal()
    cal.p.Delete("quest_next")
    board2 := QmBoard([["Resonance`n***`nObjects`nReach resonance"]])
    m2 := QmBoardTask(board2, , cal)
    m2.t.Run(SchedCtx())
    AssertTrue(m2.io.Moved(100, 200) && m2.io.Moved(700, 800), "Accept and Exit as recorded")
}

; ---- Calibrate: places found this run ----------------------------------------------------

Test_AutoCal_CalibrateFoundThisRun() {
    d := AcTmpCal()
    try {
        Calibrate.Use(d "\cal.json")
        Calibrate.SetPoint("inv_open", 45, 674, 0xFFFFFF)
        AssertEq(Calibrate.Point("inv_use"), "", "not recorded, not found: nothing")
        Calibrate.SetFound("inv_use", {x: 910, y: 772})
        Calibrate.SetFound("inv_desc_rect", {x: 648, y: 812, w: 367, h: 243})
        AssertEq(Calibrate.Point("inv_use").x "," Calibrate.Point("inv_use").y, "910,772", "a point found this run")
        AssertEq(Calibrate.Rect("inv_desc_rect").w, 367, "a rect found this run")
        AssertEq(Calibrate.Rect("inv_use"), "", "a found point is no rect")
        AssertEq(Calibrate.Point("inv_desc_rect"), "", "a found rect is no point")
        AssertEq(Calibrate.Stored("inv_use"), false, "found is not recorded")
        AssertEq(Calibrate.Stored("inv_open"), true, "recorded")
        ; never written to the file
        Calibrate.SetPoint("inv_search", 1434, 487, 0)
        saved := AcSavedSteps(d "\cal.json")
        AssertTrue(saved.Has("inv_search") && !saved.Has("inv_use") && !saved.Has("inv_desc_rect"), "the found places are not saved")
        ; a recording is kept as it is: a found place does not replace it ...
        Calibrate.SetFound("inv_search", {x: 1, y: 2})
        AssertEq(Calibrate.Point("inv_search").x, 1434, "a recording wins over a found place")
        ; ... unless it failed its own read on screen
        Calibrate.SetFound("inv_search", {x: 1500, y: 490}, true)
        AssertEq(Calibrate.Point("inv_search").x, 1500, "a recording that failed its read: the found place is used")
        AssertEq(Calibrate.Stored("inv_search"), true, "the recording itself is untouched")
        ; recording the step by hand drops what was found
        Calibrate.SetPoint("inv_use", 913, 770, 0)
        AssertEq(Calibrate.Point("inv_use").x, 913, "recorded by hand: the recording")
        Calibrate.SetPoint("inv_search", 1434, 487, 0)
        AssertEq(Calibrate.Point("inv_search").x, 1434, "recorded again: the found place is dropped")
        ; a load (every Start) starts over
        Calibrate.SetFound("inv_tile1_rect", {x: 1076, y: 578, w: 110, h: 112})
        Calibrate.Use(d "\cal.json")
        AssertEq(Calibrate.Rect("inv_tile1_rect"), "", "found places are per run")
        AssertEq(Calibrate.Point("inv_use").x, 913, "recordings stay")
    } finally {
        Calibrate.Use(A_Temp "\vesper_cal_unused.json")
        try DirDelete(d, true)
    }
}

; the recorded steps in a calibration file (Map id -> Map)
AcSavedSteps(path) => Json.Parse(FileRead(path, "UTF-8"))["steps"]

; ---- InvFindTask: one look at the inventory ---------------------------------------------

; A world whose inventory button (45,674) opens and closes the inventory of
; frame `f`: the OCR and the lines read the frame while it is open, nothing
; while it is closed.
class AcInvWorld {
    __New(f) {
        this.path := AcPath(f)
        this.open := false
        this.stuck := false         ; the button does nothing
        this.clicks := 0
    }
    Clicked(x, y) {
        if (x = 45 && y = 674) {
            this.clicks++
            if !this.stuck
                this.open := !this.open
        }
    }
    Key(k) => 0
    Scroll(n) => 0
    Ocr(x, y, w, h, scale := 1) => this.open ? Ocr.ReadFile(this.path, x, y, w, h, scale) : ""
    Lines(x, y, w, h, scale := 1) => this.open ? Ocr.LinesFile(this.path, x, y, w, h, scale) : []
}

; -> {t, w (the world), io, wh, logs, clk, dir}; the real Calibrate on a temp
; file with `recorded` (Map id -> [x, y] or [x, y, w, h]) in it
AcInvMake(f, recorded, gets := "") {
    d := AcTmpCal()
    Calibrate.Use(d "\cal.json")
    for id, v in recorded {
        if (v.Length = 2)
            Calibrate.SetPoint(id, v[1], v[2], 0)
        else
            Calibrate.SetRect(id, v[1], v[2], v[1] + v[3], v[2] + v[4])
    }
    w := AcInvWorld(f)
    io := BiIO(w)
    wh := BiWh()
    logs := []
    clk := {t: 1000000}
    g := Map("BiomeItems.enabled", 1, "merchant.enabled", 0)
    if (gets is Map)
        for k, v in gets
            g[k] := v
    t := InvFindTask({cfg: BiCfg(g), io: io, webhook: wh, log: (s) => logs.Push(s), now: () => clk.t
        , ocr: (x, y, w2, h, scale := 1) => w.Ocr(x, y, w2, h, scale), lines: (x, y, w2, h, scale := 1) => w.Lines(x, y, w2, h, scale)})
    return {t: t, w: w, io: io, wh: wh, logs: logs, clk: clk, dir: d}
}
AcInvDone(m) {
    UiStuck.Reset()
    Calibrate.Use(A_Temp "\vesper_cal_unused.json")
    try DirDelete(m.dir, true)
}
; the 2560x1440 preset's inventory steps
AcInvPreset() => Map("inv_open", [45, 674], "inv_items_tab", [1684, 445], "inv_search", [1434, 487], "inv_use", [913, 770]
    , "inv_tile1_rect", [1076, 578, 110, 112], "inv_desc_rect", [648, 812, 367, 243])

Test_AutoCal_InvFindPlacesTheMissingSteps() {
    m := AcInvMake("inv_randomizer_selected_sand", Map("inv_open", [45, 674]))
    try {
        UiStuck.Reset()
        AssertEq(m.t.name, "autocal", "name")
        AssertEq(m.t.CanRun(SchedState()), true, "inventory steps missing, a feature that uses it on: one look")
        AssertEq(m.t.Run(SchedCtx()), 5, "five steps placed")
        AssertEq(m.w.clicks, 2, "the inventory button clicked twice: open, close")
        AssertEq(m.w.open, false, "the inventory is closed again")
        clicks := AcClicks(m.io)
        for c in clicks
            AssertTrue(c.x = 45 && c.y = 674, "only the inventory button was clicked (" c.x "," c.y ")")
        ; what the tasks now get, against the preset's recordings
        AcNear(Calibrate.Point("inv_items_tab"), 1684, 445, 14, "inv_items_tab")
        AcNear(Calibrate.Point("inv_search"), 1434, 487, 6, "inv_search")
        AcNear(Calibrate.Point("inv_use"), 913, 770, 6, "inv_use")
        r := Calibrate.Rect("inv_tile1_rect")
        AssertTrue(IsObject(r) && Abs(r.x - 1076) <= 4 && Abs(r.y - 578) <= 4 && r.w = 110 && r.h = 112, "inv_tile1_rect")
        r := Calibrate.Rect("inv_desc_rect")
        AssertTrue(IsObject(r) && Abs(r.x - 648) <= 6 && Abs(r.y - 812) <= 6, "inv_desc_rect")
        for id in AutoCal.InvIds
            AssertEq(Calibrate.Stored(id), false, id " is not written as a recording")
        AssertEq(AcSavedSteps(m.dir "\cal.json").Count, 1, "the file still holds inv_open alone")
        AssertTrue(AcBiSaid(m, "inventory steps found on screen"), "logged")
        AssertEq(m.wh.Count("errors"), 0, "no error")
        AssertEq(m.t.CanRun(SchedState()), false, "nothing missing any more: never again")
        ; a task's own preflight now passes (the biome items task)
        t2 := BiomeItemsTask({cfg: BiCfg(Map("BiomeItems.strangeController", 1)), io: m.io, webhook: m.wh, now: () => m.clk.t
            , ocr: (*) => "", statePath: m.dir "\bi.json"})
        AssertTrue(IsObject(t2._InvCal()), "the biome items task has every inventory step")
        ; the next Start loads the file again: found places are per run
        Calibrate.Use(m.dir "\cal.json")
        AssertEq(m.t.CanRun(SchedState()), true, "after a new Start: looked at once more")
    } finally
        AcInvDone(m)
}

Test_AutoCal_InvFindNeverRunsForAFullCalibration() {
    m := AcInvMake("inventory_open_day", AcInvPreset())
    try {
        UiStuck.Reset()
        Loop 3
            AssertEq(m.t.CanRun(SchedState()), false, "every step recorded, the inventory works: never (" A_Index ")")
        AssertEq(m.io.log.Length, 0, "no input")
        ; one failure is no reason either
        UiStuck.Fail("inventory")
        AssertEq(m.t.CanRun(SchedState()), false, "one failure: not yet")
        ; it failed twice in a row, yet it reads where it is recorded: looked
        ; at once, nothing replaced
        UiStuck.Fail("inventory")
        AssertEq(m.t.CanRun(SchedState()), true, "the inventory failed its own read twice: one look")
        AssertEq(m.t.Run(SchedCtx()), 0, "it reads where it is recorded: nothing placed")
        AssertEq(Calibrate.Point("inv_items_tab").x, 1684, "the recording is used")
        AssertEq(m.w.open, false, "closed again")
        AssertEq(m.wh.Count("errors"), 0, "no error")
        UiStuck.Fail("inventory", 2)
        m.clk.t += InvFindTask.RetryMs + 1
        AssertEq(m.t.CanRun(SchedState()), false, "one look per run for a failing inventory")
        ; no feature that uses the inventory: never, whatever is missing
        m2 := AcInvMake("inventory_open_day", Map("inv_open", [45, 674]), Map("BiomeItems.enabled", 0))
        AssertEq(m2.t.CanRun(SchedState()), false, "no inventory feature on: not looked at")
        try DirDelete(m2.dir, true)
        ; no inventory button recorded (a picture: nothing to find it by)
        m3 := AcInvMake("inventory_open_day", Map())
        AssertEq(m3.t.CanRun(SchedState()), false, "inv_open not recorded: not looked at")
        try DirDelete(m3.dir, true)
        for i, kv in InvFindTask.Needs
            AssertEq(kv[1] "=" kv[2], SetupCheck.InvNeeds[i][1] "=" SetupCheck.InvNeeds[i][2], "the features that use the inventory: one list")
        AssertEq(InvFindTask.Needs.Length, SetupCheck.InvNeeds.Length, "the same length")
    } finally
        AcInvDone(m)
}

Test_AutoCal_InvFindRecordedInTheWrongPlace() {
    ; recorded for another screen: the tabs never read around inv_items_tab,
    ; so every task says the inventory did not open
    rec := AcInvPreset()
    rec["inv_items_tab"] := [1400, 300], rec["inv_search"] := [1200, 340], rec["inv_use"] := [700, 600]
    rec["inv_tile1_rect"] := [900, 420, 110, 112], rec["inv_desc_rect"] := [500, 650, 367, 243]
    m := AcInvMake("inv_randomizer_selected_sand", rec)
    try {
        UiStuck.Reset()
        AssertEq(m.t.CanRun(SchedState()), false, "recorded: not looked at until it fails")
        UiStuck.Fail("inventory", 2)
        AssertEq(m.t.CanRun(SchedState()), true, "failed twice: one look")
        AssertEq(m.t.Run(SchedCtx()), 5, "the five steps found replace their recordings")
        AcNear(Calibrate.Point("inv_items_tab"), 1684, 445, 14, "inv_items_tab now")
        AcNear(Calibrate.Point("inv_use"), 913, 770, 6, "inv_use now")
        AssertEq(Calibrate.Stored("inv_items_tab"), true, "the recordings are still in the file")
        AssertEq(AcSavedSteps(m.dir "\cal.json")["inv_items_tab"]["x"], 1400, "... unchanged")
        AssertEq(m.wh.Count("errors"), 1, "told once (errors webhook)")
        AssertTrue(AcBiSaid(m, "not where it is calibrated"), "logged")
        AssertEq(m.w.open, false, "closed again")
        AssertTrue(!UiStuck.counts.Has("inventory"), "the inventory reads again: its failures are forgotten")
        ; the next Start: the recordings again (the user was told to fix them)
        Calibrate.Use(m.dir "\cal.json")
        AssertEq(Calibrate.Point("inv_items_tab").x, 1400, "after a new Start: the recording, until it fails again")
    } finally
        AcInvDone(m)
}

Test_AutoCal_InvFindWhenTheInventoryDoesNotShow() {
    m := AcInvMake("inventory_open_day", Map("inv_open", [45, 674]))
    try {
        UiStuck.Reset()
        m.w.stuck := true                           ; the button does nothing
        Loop InvFindTask.MaxTries {
            AssertEq(m.t.CanRun(SchedState()), true, "look " A_Index)
            AssertEq(m.t.Run(SchedCtx()), 0, "nothing placed")
            AssertEq(m.t.CanRun(SchedState()), false, "not again at once")
            m.clk.t += InvFindTask.RetryMs + 1
        }
        AssertEq(m.t.CanRun(SchedState()), false, "MaxTries looks, then no more")
        AssertEq(m.w.clicks, InvFindTask.MaxTries, "one click on the button a look, never a second one on a closed inventory")
        AssertEq(m.wh.Count("errors"), 1, "the steps still missing are told once")
        AssertEq(Calibrate.Point("inv_use"), "", "nothing invented")
        ; already open (left by a stop): not clicked to open, closed after
        m2 := AcInvMake("inventory_open_day", Map("inv_open", [45, 674]))
        m2.w.open := true
        AssertEq(m2.t.Run(SchedCtx()), 5, "an inventory left open is read as it is")
        AssertEq(m2.w.clicks, 1, "one click: the close")
        AssertEq(m2.w.open, false, "closed")
        try DirDelete(m2.dir, true)
    } finally
        AcInvDone(m)
}

Test_AutoCal_InvFindIsATaskOfTheApp() {
    AssertEq(Sched.Priority["autocal"], 5, "priority 5, with the other island tasks")
    AssertTrue(Sched.RareBlocked.Has("autocal"), "not in a rare biome")
    AssertTrue(Sched.LimboModeOk.Has("autocal") && !Sched.InLimboOk.Has("autocal"), "with Limbo on (the crack is in the inventory), not inside Limbo")
    a := 0, b := 0, mm := 0
    for i, n in App.Order {
        if (n = "autocal")
            a := i
        if (n = "biomeitems")
            b := i
        if (n = "merchant")
            mm := i
    }
    AssertTrue(a > 0 && a < b, "before the biome items task")
    ; a scheduler pick: only when it says so
    st := SchedState()
    AssertEq(Scheduler.Next([SchedFakeTask("autocal", 5, false), SchedFakeTask("fishing", 99)], st, 0).name, "fishing", "nothing missing: fishing")
    AssertEq(Scheduler.Next([SchedFakeTask("autocal", 5, true), SchedFakeTask("fishing", 99)], st, 0).name, "autocal", "a step missing: the look first")
}

; The inventory and the quest board at 1920x1080 and 1366x768 (frames scaled
; as test_resample.ahk does): found, in design px, where the preset has them.
Test_AutoCal_InventoryAndBoardAtOtherResolutions() {
    bad := ""
    try {
        for size in [[1920, 1080], [1366, 768]] {
            cw := size[1], ch := size[2], f := cw / 2560, tag := cw "x" ch
            RsAt(cw, ch)
            ; as InvFindTask reads it: the whole screen, the tabs checked at
            ; the tab found, then the window alone at 2x for what is missing
            pth := RsFrame("inv_randomizer_selected_sand", f)
            inv := AutoCal.Inventory(Ocr.LinesFile(pth, 0, 0, 2560, 1440))
            if (IsObject(inv) && !TaskEnv({ocr: RsOcrFn(pth)}).InvOpen(inv.tab))
                bad .= " | " tag " tabs do not read at the tab found"
            if IsObject(inv) {
                inv := AutoCal.InvMerge(inv, AutoCal.Inventory(Ocr.LinesFile(pth, inv.box.x, inv.box.y, inv.box.w, inv.box.h, 2), inv.title))
                inv := AutoCal.InvMerge(inv, AutoCal.Inventory(Ocr.LinesFile(pth, inv.useBox.x, inv.useBox.y, inv.useBox.w, inv.useBox.h, 2), inv.title))
            }
            if !IsObject(inv)
                bad .= " | " tag " inventory not found"
            else {
                if !(Abs(inv.tab.x - 1684) <= 18 && Abs(inv.tab.y - 445) <= 10)
                    bad .= " | " tag " tab " inv.tab.x "," inv.tab.y
                if !(IsObject(inv.use) && Abs(inv.use.x - 913) <= 10 && Abs(inv.use.y - 770) <= 10)
                    bad .= " | " tag " use"
                if !(IsObject(inv.search) && Abs(inv.search.x - 1434) <= 10 && Abs(inv.search.y - 487) <= 10)
                    bad .= " | " tag " search"
                if !(IsObject(inv.tile1) && Abs(inv.tile1.x - 1076) <= 8 && Abs(inv.tile1.y - 578) <= 8)
                    bad .= " | " tag " tile1"
            }
            for name in ["quest_page_full_claim_day", "quest_page_full_claim_night"] {
                lines := Ocr.LinesFile(RsFrame(name, f), 0, 0, 2560, 1440)
                p := AutoCal.QuestPanel(lines), ex := AutoCal.QuestExit(lines)
                if !(IsObject(p) && Abs(p.rect.x - 2024) <= 10 && Abs(p.rect.y - 489) <= 10 && Abs(p.dismiss.x - 2371) <= 12 && Abs(p.dismiss.y - 1086) <= 10)
                    bad .= " | " tag " " name " panel" (IsObject(p) ? " " p.rect.x "," p.rect.y : " not found")
                if !(IsObject(ex) && Abs(ex.close.x - 1278) <= 12 && Abs(ex.close.y - 1263) <= 14 && Abs(ex.next.x - 1815) <= 10 && Abs(ex.next.y - 721) <= 10)
                    bad .= " | " tag " " name " exit" (IsObject(ex) ? " " ex.close.x "," ex.close.y : " not found")
            }
        }
    } finally {
        Screen.Reset()
    }
    AssertEq(bad, "", "found at 1080p and 768p")
}
