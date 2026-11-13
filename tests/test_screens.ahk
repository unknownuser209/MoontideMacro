#Requires AutoHotkey v2.0
; ---------------------------------------------------------------------------
; Screen regression tests: the REAL Windows OCR on real 2560x1440 frames from
; the user's clips (tests\screens\*.jpg), read with the tasks' own boxes and
; scales. The other tests feed the tasks made-up OCR text, so a box in the
; wrong place or a scale too small for some lighting passed them all and
; only broke in the game (2026-10-26: Mari's name never read at 1x, the
; Fishing Shop title box read nothing, Mari's Leave did not read at night).
;
; RULE: when a clip shows a screen the macro misread, save that frame here
; (ffmpeg -ss <t> -i clip -frames:v 1 -q:v 2 tests\screens\<what>.jpg) and
; add it to a test below, so the fix can never quietly break again.
;
; Frames: mari_* (clip 2026-10-26 21:05 night, 23:32 day), jester_* (21:50),
; fishshop_hell_sell / sellconfirm_hell (22:42, red Hell lighting),
; world_day / inventory_day (23:32, no merchant dialog).
; ---------------------------------------------------------------------------

ScrPath(name) => A_ScriptDir "\screens\" name ".jpg"

; OCR of rect r on frame `name` at `scale` (the tasks' Ocr pipeline).
ScrRead(name, r, scale := 1) {
    AssertTrue(FileExist(ScrPath(name)), "frame " name " exists")
    return Ocr.ReadFile(ScrPath(name), r.x, r.y, r.w, r.h, scale)
}

; The box the merchant reads around a button point.
ScrButton(pt) {
    b := MerchantTask.ButtonBox
    return {x: pt.x + b.dx, y: pt.y + b.dy, w: b.w, h: b.h}
}

Test_Screens_MerchantNameReadsInEveryLight() {
    L := MerchantTask.Layout
    for f in ["mari_night_dialog", "mari_day_dialog", "mari_day_buttons", "mari_black_buttons"]
        AssertTrue(RegExMatch(ScrRead(f, L.dialogName, MerchantTask.NameScale), MerchantTask.NameRe["Mari"]), f ": Mari's name reads")
    for f in ["jester_dialog", "jester_buttons"]
        AssertTrue(RegExMatch(ScrRead(f, L.dialogName, MerchantTask.NameScale), MerchantTask.NameRe["Jester"]), f ": Jester's name reads")
}

Test_Screens_MerchantDialogUpNeverMissed() {
    ; "is her dialog still up?" decides whether the macro may respawn: it
    ; must be true on every frame with her dialog, whatever the light
    L := MerchantTask.Layout
    for f in ["mari_night_dialog", "mari_day_dialog", "mari_night_buttons", "mari_day_buttons", "mari_black_buttons"]
        AssertTrue(MerchantTask.DialogUp(ScrRead(f, L.dialogArea), "Mari"), f ": Mari's dialog seen")
    for f in ["jester_dialog", "jester_buttons"]
        AssertTrue(MerchantTask.DialogUp(ScrRead(f, L.dialogArea), "Jester"), f ": Jester's dialog seen")
    for f in ["world_day", "inventory_day"]
        AssertTrue(!MerchantTask.DialogUp(ScrRead(f, L.dialogArea), "Mari"), f ": no dialog")
}

Test_Screens_MerchantOpenOnlyWithButtons() {
    L := MerchantTask.Layout
    for f in ["mari_night_buttons", "mari_day_buttons", "mari_black_buttons", "jester_buttons"]
        AssertTrue(RegExMatch(ScrRead(f, ScrButton(L.open)), MerchantTask.OpenRe), f ": Open reads")
    ; while her line types out there is no Open yet: clicking it then does nothing
    for f in ["mari_night_dialog", "mari_day_dialog", "jester_dialog", "world_day"]
        AssertTrue(!RegExMatch(ScrRead(f, ScrButton(L.open)), MerchantTask.OpenRe), f ": no Open yet")
}

Test_Screens_MerchantLeave() {
    L := MerchantTask.Layout
    for f in ["mari_day_buttons", "mari_black_buttons", "jester_buttons"]
        AssertTrue(RegExMatch(ScrRead(f, ScrButton(L.leave), MerchantTask.LeaveScale), MerchantTask.LeaveRe), f ": Leave reads")
    ; mari_night_buttons: red Leave on green grass does not read at all; the
    ; dialog check above covers it (never "gone" while "Click to skip" reads)
}

Test_Screens_JesterShop() {
    L := MerchantTask.Layout
    AssertTrue(RegExMatch(ScrRead("jester_shop", L.title, MerchantTask.SmallScale), "i)sh[ao]p"), "shop title")
    texts := []
    for r in L.tabs
        texts.Push(ScrRead("jester_shop", r))
    AssertEq(MerchantTask.FindTab(texts, "Strange Potion I"), 1, "tab 1")
    AssertEq(MerchantTask.FindTab(texts, "Rune of Everything"), 4, "tab 4 (Everythino)")
    AssertTrue(MerchantTask.TitleNames(ScrRead("jester_shop", L.item), "Strange Potion I"), "item title")
    AssertEq(MerchantTask.Stock(ScrRead("jester_shop", L.stock, MerchantTask.SmallScale)), 20, "stock")
    AssertTrue(RegExMatch(ScrRead("jester_purchased", L.notice), "i)purch[ao]sed"), "purchased notice")
}

Test_Screens_FishingShopTitle() {
    ; the craft buy step must see the shop the sell left open (else E brings
    ; Captain Flarg's dialog over it), in Hell's red light too
    t := CraftTask.ShopTitle
    for f in ["fishshop_hell_sell", "sellconfirm_hell"]
        AssertTrue(RegExMatch(ScrRead(f, t), t.re), f ": craft sees the Fishing Shop")
    c := SellTask.ShopChecks.title
    AssertTrue(InStr(StrLower(ScrRead("fishshop_hell_sell", c)), "fishing"), "sell sees the Fishing Shop")
    AssertTrue(!RegExMatch(ScrRead("world_day", t), t.re), "no shop in the open world")
}

Test_Screens_SellConfirmPopup() {
    sc := SellTask.ShopChecks
    AssertTrue(SellTask.Seen(sc.popup, ScrRead("sellconfirm_hell", sc.popup)), "the Sell Confirm popup is seen")
    for f in ["fishshop_hell_sell", "world_day", "jester_shop"]
        AssertTrue(!SellTask.Seen(sc.popup, ScrRead(f, sc.popup)), f ": no popup")
    ; live 2026-10-27 the same popup read like this: the old word list missed
    ; it and the macro walked off with it open (clip 19:43)
    AssertTrue(SellTask.Seen(sc.popup, "you reo y wont to sell oll your Pironho?`""), "the game font's misread is seen")
    for t in ["Pironho Pironho Silverfin", "Captain narg Talk", "Fishing Shop", "Sell All", ""]
        AssertTrue(!SellTask.Seen(sc.popup, t), "'" t "' is not the popup")
    ; its two buttons sit where the sell presses them
    coords := Json.Parse(FileRead(A_ScriptDir "\..\data\coords.json", "UTF-8"))
    cf := coords["sell"]["loop"]["confirm"]
    AssertTrue(RegExMatch(ScrRead("sellconfirm_hell", {x: cf[1] - 150, y: cf[2] - 35, w: 300, h: 70}), "i)\bsell\b"), "confirm point is on Sell")
    cn := sc.cancel
    AssertTrue(RegExMatch(ScrRead("sellconfirm_hell", {x: cn[1] - 150, y: cn[2] - 35, w: 300, h: 70}), "i)c[ao]nc[ae]l"), "cancel point is on Cancel (the font draws Concel)")
}

Test_Screens_SellConfirmSecondLook() {
    ; 2026-10-27 review: when the 1x read misses the popup, the sell looks
    ; again at 2x and at its Cancel label before walking off. Both must see
    ; the real popup, and neither may see one on the other frames.
    sc := SellTask.ShopChecks, b := sc.cancelBox
    cb := {x: sc.cancel[1] + b.dx, y: sc.cancel[2] + b.dy, w: b.w, h: b.h}
    AssertTrue(SellTask.Seen(sc.popup, ScrRead("sellconfirm_hell", sc.popup, 2)), "the popup text reads at 2x")
    AssertTrue(RegExMatch(ScrRead("sellconfirm_hell", cb), SellTask.CancelRe), "its Cancel label reads (Concel)")
    AssertTrue(SellTask.PopupSecond(ScrRead("sellconfirm_hell", sc.popup, 2), ScrRead("sellconfirm_hell", cb)), "the second look sees it")
    for f in ["fishshop_hell_sell", "world_day", "jester_shop", "mm_prompt_ready", "inventory_day"]
        AssertTrue(!SellTask.PopupSecond(ScrRead(f, sc.popup, 2), ScrRead(f, cb)), f ": no popup on a second look")
}

; ---- Aura storage (live 2026-10-27 20:50) ---------------------------------
; "Sailor" searched: six Sailor: Admiral and a Sailor: Flying Dutchman come
; before plain Sailor (8th). The tiles are logos OCR cannot read live, so a
; tile is clicked and the name above [ Information ] read.
; aura_selected_sailor / aura_selected_dutchman: tile 8 / 7 selected;
; aura_search_sailor (clip 20:17): nothing selected. aura_equip is the
; user's calibrated point.

ScrAuraName(name) {
    n := ObbyTask.NameBox
    return ScrRead(name, {x: 840 + n.dx, y: 843 + n.dy, w: n.w, h: n.h}, ObbyTask.NameScale)
}

Test_Screens_AuraNameOfTheSelectedTile() {
    AssertTrue(ObbyTask.NameIs(ScrAuraName("aura_selected_sailor"), "Sailor"), "plain Sailor selected")
    AssertTrue(!ObbyTask.NameIs(ScrAuraName("aura_selected_dutchman"), "Sailor"), "Sailor: Flying Dutchman is not Sailor")
    AssertTrue(!ObbyTask.NameIs(ScrAuraName("aura_search_sailor"), "Sailor"), "nothing selected")
    b := ObbyTask.ButtonBox
    AssertTrue(RegExMatch(ScrRead("aura_selected_sailor", {x: 840 + b.dx, y: 843 + b.dy, w: b.w, h: b.h}), "i)^\W*equip\W*$"), "the button reads Equip (not Remove / Unlock)")
}

; the panel at every scale the swap reads it (ObbyTask._ReadName)
ScrAuraNames(name) {
    n := ObbyTask.NameBox, out := []
    for s in ObbyTask.NameScales
        out.Push(ScrRead(name, {x: 840 + n.dx, y: 843 + n.dy, w: n.w, h: n.h}, s))
    return out
}

; live 2026-11-10 12:34: "Sailor" equipped Sailor: Admiral first. Exact
; names on the real frames: Sailor is Sailor, never Sailor: Admiral /
; Flying Dutchman, and the log's "Sailor_Flying_Dutchman" is the 7th tile
Test_Screens_AuraNameVerdictIsExact() {
    sailor := ScrAuraNames("aura_selected_sailor"), dutch := ScrAuraNames("aura_selected_dutchman")
    AssertEq(ObbyTask.NameVerdict(sailor, "Sailor"), "same", "plain Sailor selected")
    AssertTrue(ObbyTask.NameVerdict(sailor, "Sailor_Admiral") != "same", "plain Sailor is not Sailor: Admiral")
    AssertTrue(ObbyTask.NameVerdict(sailor, "Sailor_Flying_Dutchman") != "same", "plain Sailor is not Flying Dutchman")
    AssertEq(ObbyTask.NameVerdict(dutch, "Sailor"), "other", "Flying Dutchman read as another aura than Sailor")
    AssertEq(ObbyTask.NameVerdict(dutch, "Sailor_Admiral"), "other", "Flying Dutchman is not Admiral")
    AssertEq(ObbyTask.NameVerdict(dutch, "Sailor_Flying_Dutchman"), "same", "the log's name of the 7th tile")
    AssertEq(ObbyTask.NameVerdict(ScrAuraNames("aura_search_sailor"), "Sailor"), "unread", "nothing selected")
}

; ---- Memory Match (clip 2026-10-27 18:50) ----------------------------------
; mm_prompt_ready / mm_prompt_cooldown: the notification before / after Start
; (mm_prompt_cooldown_title: clip 19:43, the title misreads);
; mm_board_start: 20 tiles face down; mm_flip_anim: tile 11 mid-flip, tile 16
; face up; mm_matched: one green pair; mm_end: every tile shown, Close.

ScrVision(name) => MatchVision(MatchFileGrab(ScrPath(name)))

Test_Screens_MemoryMatchPrompt() {
    L := MemoryMatchTask.Layout
    AssertTrue(RegExMatch(ScrRead("mm_prompt_ready", L.notify), MemoryMatchTask.NotifyRe), "notification seen")
    btn := ScrRead("mm_prompt_ready", L.startBox)
    AssertTrue(RegExMatch(btn, MemoryMatchTask.StartRe) && !RegExMatch(btn, MemoryMatchTask.CooldownRe), "ready: Start")
    cd := ScrRead("mm_prompt_cooldown", L.startBox)
    AssertTrue(RegExMatch(cd, MemoryMatchTask.CooldownRe), "cooldown: Available after ... Left")
    AssertEq(MemoryMatchTask.ParseCooldown(cd), 43140, "11h 59m read off the button")
    AssertTrue(!RegExMatch(ScrRead("world_day", L.notify), MemoryMatchTask.NotifyRe), "no notification in the world")
    for f in ["mm_prompt_ready", "mm_prompt_cooldown", "mm_prompt_cooldown_title"]
        AssertTrue(MemoryMatchTask.NotifyUp(ScrRead(f, L.notify), ScrRead(f, L.startBox)), f ": notification seen")
    AssertTrue(!MemoryMatchTask.NotifyUp(ScrRead("world_day", L.notify), ScrRead("world_day", L.startBox)), "no notification in the world (title or button)")
    ; clip 2026-10-27 19:43: the title read "Stort Memor Moach?" and the
    ; macro reset with the notification open
    cd := ScrRead("mm_prompt_cooldown_title", L.startBox)
    AssertEq(MemoryMatchTask.ParseCooldown(cd), 40020, "11h 07m read off the button")
}

Test_Screens_MemoryMatchBoard() {
    L := MemoryMatchTask.Layout
    for f in ["mm_board_start", "mm_matched", "mm_end"]
        AssertTrue(RegExMatch(ScrRead(f, L.title), MemoryMatchTask.TitleRe), f ": board title")
    AssertTrue(RegExMatch(ScrRead("mm_end", L.closeBox), MemoryMatchTask.CloseRe), "Close at the end")
    for f in ["mm_board_start", "mm_matched"]
        AssertTrue(!RegExMatch(ScrRead(f, L.closeBox), MemoryMatchTask.CloseRe), f ": no Close mid-round")
    v := ScrVision("mm_board_start")
    Loop 20
        AssertEq(v.State(A_Index), "hidden", "start: tile " A_Index " face down")
    v := ScrVision("mm_matched")
    AssertEq(v.State(9), "matched", "green pair 9")
    AssertEq(v.State(15), "matched", "green pair 15")
    AssertEq(v.State(1), "hidden", "others face down")
    v := ScrVision("mm_flip_anim")
    AssertEq(v.State(16), "open", "flip_anim: tile 16 face up")
    AssertTrue(v.State(11) != "hidden", "flip_anim: tile 11 mid-flip is not face down")
    AssertEq(v.State(1), "hidden", "flip_anim: tile 1 face down")
}

Test_Screens_MemoryMatchPairsByPicture() {
    ; every tile shown: exactly the 9 real pairs look the same (9-15 is the
    ; green one); x100 / x200 and x3,000 / x5,000 never do
    v := ScrVision("mm_end")
    sigs := []
    Loop 20
        sigs.Push(v.Sig(A_Index))
    found := ""
    Loop 20 {
        i := A_Index
        if (v.State(i) != "open")
            continue
        Loop 20 {
            j := A_Index
            if (j > i && v.State(j) = "open" && MatchVision.Same(sigs[i], sigs[j]))
                found .= i "-" j " "
        }
    }
    AssertEq(found, "1-19 2-12 3-11 4-17 5-16 6-18 7-10 8-14 13-20 ", "the 9 pairs")
    ; value by the amount's width: x1 < x5 < x20 < x100 < x200 < x1,000 < x3,000
    order := [3, 2, 8, 1, 5, 4, 7]
    Loop order.Length - 1
        AssertTrue(sigs[order[A_Index]].width < sigs[order[A_Index + 1]].width, "width " order[A_Index] " < " order[A_Index + 1])
    AssertTrue(InStr(MemoryMatchTask.Label("w" sigs[3].width "#1"), "rare"), "x1 labelled rare")
    AssertTrue(InStr(MemoryMatchTask.Label("w" sigs[4].width "#1"), "Coins"), "x1,000 labelled coins")
}

Test_Screens_MemoryMatchFlipNotSettled() {
    ; tile 11 mid-flip is not its finished picture: the task waits for a
    ; still picture; tile 16 (face up) already is
    mid := ScrVision("mm_flip_anim"), fin := ScrVision("mm_end")
    AssertTrue(!MatchVision.Same(mid.Sig(11), fin.Sig(11)), "mid-flip picture differs")
    AssertEq(mid.State(16), "open", "tile 16 face up")
    AssertTrue(MatchVision.Same(mid.Sig(16), fin.Sig(16)), "tile 16 already its final picture")
}

; ---- no blind clicks in the aura storage (live 2026-11-02 09:20) ------------
; A click on an empty result slot went through the storage into the world and
; opened Roblox's purchase prompt. On the three storage frames (Hell, two
; lightings of the same session) the 8 Sailor results must show as tiles and
; the 8 empty slots under them (the dim world behind the panel) must not.
; Tile 1's name rect as the user calibrates it (aura_tile_rect).

ScrTilePixels(g, r) {
    ys := []
    Loop r.h
        ys.Push(r.y + A_Index - 1)
    px := []
    for row in g(r.x, r.x + r.w - 1, ys)
        for c in row
            px.Push(c)
    return px
}

Test_Screens_AuraTilesShowEmptySlotsDoNot() {
    first := {x: 1056, y: 548, w: 78, h: 66}
    for f in ["aura_search_sailor", "aura_selected_sailor", "aura_selected_dutchman"] {
        g := MatchFileGrab(ScrPath(f))
        Loop 16 {
            r := ObbyTask.TileRect(first, A_Index)
            AssertEq(ObbyTask.TileShown(ScrTilePixels(g, r), r.w, r.h), A_Index <= 8, f ": slot " A_Index (A_Index <= 8 ? " shows a tile" : " is empty"))
        }
    }
}

Test_Screens_AuraStorageTitleReads() {
    ; aura_search 1146,490 (the user's calibration, ObbyTask.Tabs)
    b := ObbyTask.StorageBox
    box := {x: 1146 + b.dx, y: 490 + b.dy, w: b.w, h: b.h}
    for f in ["aura_search_sailor", "aura_selected_sailor", "aura_selected_dutchman"]
        AssertTrue(RegExMatch(ScrRead(f, box), ObbyTask.StorageRe), f ": the storage title reads")
    for f in ["world_day", "inventory_day", "mm_board_start", "jester_shop", "fishshop_hell_sell"]
        AssertTrue(!RegExMatch(ScrRead(f, box), ObbyTask.StorageRe), f ": no storage title")
}

; OCR of box b (2560x1440 screen px) on a crop of the screen whose top
; left is ox,oy (tests\screens\storage_crop_*.jpg: x 620..1600, y 340..660)
ScrCropRead(name, b, ox, oy, scale := 1) {
    p := A_ScriptDir "\screens\" name ".jpg"
    AssertTrue(FileExist(p), "crop " name " exists")
    return Ocr.ReadFile(p, b.x - ox, b.y - oy, b.w, b.h, scale)
}

Test_Screens_AuraStorageSeenOverTheHunt() {
    ; live 2026-11-02 (L19): pumpkin_banner = 23:27:50, the PUMPKIN MOON
    ; banner's flames over the title (the swap read "not open"); snowy_* =
    ; the 23:30 hunt clip (720p, upscaled), the storage open over the whole
    ; fight. none_* = no storage (the chat + the Auras tooltip; the respawn
    ; prompt over Eden). aura_search 1146,490 / aura_equip 840,843.
    t := ObbyTask.StorageBox, p := ObbyTask.PanelBox
    title := {x: 1146 + t.dx, y: 490 + t.dy, w: t.w, h: t.h}
    panel := {x: 840 + p.dx, y: 843 + p.dy, w: p.w, h: p.h}
    for f in ["storage_crop_pumpkin_banner", "storage_crop_snowy_hunt", "storage_crop_snowy_day"] {
        AssertTrue(RegExMatch(ScrCropRead(f, panel, 620, 340), ObbyTask.PanelRe), f ": the [ Information ] panel reads")
        AssertTrue(RegExMatch(ScrCropRead(f, title, 620, 340, ObbyTask.StorageScale), ObbyTask.StorageRe), f ": the title reads at StorageScale")
    }
    for f in ["storage_crop_none_chat", "storage_crop_none_respawn"] {
        AssertTrue(!RegExMatch(ScrCropRead(f, panel, 620, 340), ObbyTask.PanelRe), f ": no panel")
        AssertTrue(!RegExMatch(ScrCropRead(f, title, 620, 340), ObbyTask.StorageRe), f ": no title")
        AssertTrue(!RegExMatch(ScrCropRead(f, title, 620, 340, ObbyTask.StorageScale), ObbyTask.StorageRe), f ": no title at StorageScale")
    }
    ; full frames: the panel on every storage frame, never on a game screen
    for f in ["aura_search_sailor", "aura_selected_sailor", "aura_selected_dutchman"]
        AssertTrue(RegExMatch(ScrRead(f, panel), ObbyTask.PanelRe), f ": the panel reads")
    for f in ["world_day", "inventory_day", "mm_board_start", "jester_shop", "fishshop_hell_sell", "mari_night_buttons", "mari_night_dialog", "sellconfirm_hell"]
        AssertTrue(!RegExMatch(ScrRead(f, panel), ObbyTask.PanelRe), f ": no panel")
}

Test_Screens_DailyRewardsTitleReads() {
    ; live 2026-11-03 18:17 / 18:19 (L20; crops x 620.., y 480..): the title
    ; reads as "noily Rewords", the X and Claim stay out of its box
    for f in ["daily_rewards_crop_a", "daily_rewards_crop_b"] {
        rd := ((f) => (x, y, w, h) => ScrCropRead(f, {x: x, y: y, w: w, h: h}, 620, 480))(f)
        AssertTrue(Input.DailyUp("", rd), f ": the title reads")
        AssertTrue(!Input.PurchaseUp("", rd), f ": no purchase prompt")
    }
    ; every other frame, game screens and menus: never the popup
    Loop Files A_ScriptDir "\screens\*.*" {
        if InStr(A_LoopFileName, "daily_rewards")
            continue
        b := Input.DailyBox
        AssertTrue(!RegExMatch(Ocr.ReadFile(A_LoopFileFullPath, b.x, b.y, b.w, b.h), Input.DailyRe), A_LoopFileName ": no Daily Rewards popup")
    }
}

Test_Screens_QuestPageReads() {
    ; live 18:27-18:33 (L20 clips, 720p upscaled; crops x 1160.., y 480..):
    ; "Snowy Breakthrough" under the Eden banner too (b); the Exit word
    ; through the "Player will automatically rejoin" line
    for f in ["quest_page_a", "quest_page_b", "quest_page_c"] {
        AssertTrue(RegExMatch(ScrCropRead(f, ObbyTask.QuestBox, 1160, 480), ObbyTask.QuestRe), f ": Objects reads")
        AssertTrue(RegExMatch(ScrCropRead(f, ObbyTask.QuestExitBox, 1160, 480), ObbyTask.QuestExitRe), f ": Exit reads")
    }
    ; every other frame, game screens and menus: never the page
    Loop Files A_ScriptDir "\screens\*.*" {
        if InStr(A_LoopFileName, "quest_page")
            continue
        b := ObbyTask.QuestBox
        AssertTrue(!RegExMatch(Ocr.ReadFile(A_LoopFileFullPath, b.x, b.y, b.w, b.h), ObbyTask.QuestRe), A_LoopFileName ": no Quest Board page")
    }
}

Test_Screens_BoardPromptReads() {
    ; live 18:26:58: the board's prompt beside the player; the crop is x
    ; 960.., y 700.. of PromptBox
    AssertTrue(RegExMatch(Ocr.ReadFile(A_ScriptDir "\screens\minions_prompt_board.png", 0, 0, 260, 110), MinionsTask.PromptRe), "See Quests reads")
    b := MinionsTask.PromptBox
    for f in ["world_day", "inventory_day"]
        AssertTrue(!RegExMatch(ScrRead(f, b), MinionsTask.PromptRe), f ": no prompt")
}

; L45 14:15: the Bossraid Portal's window over a fight, E opened it
Test_Screens_RaidWindowReads() {
    AssertTrue(RegExMatch(ScrRead("raid_open_night", ObbyTask.RaidBox), ObbyTask.RaidRe), "its difficulty line reads")
    for f in ["world_day", "mari_day_dialog", "mm_board_start", "fishshop_hell_sell", "jester_shop", "inventory_open_day"]
        AssertTrue(!RegExMatch(ScrRead(f, ObbyTask.RaidBox), ObbyTask.RaidRe), f ": no window")
}

; the loops' biome items: "the inventory is not open" over an open inventory,
; left open through the hunts (1x reads "'terns")
Test_Screens_InventoryOpenReads() {
    env := (f) => TaskEnv({ocr: (x, y, w, h, scale := 1) => Ocr.ReadFile(ScrPath(f), x, y, w, h, scale)})
    tab := {x: 1684, y: 445}
    for f in ["inventory_open_sand", "inventory_open_rainy", "inventory_open_day"] {
        AssertTrue(env(f).InvOpen(tab), f ": its tabs read")
        AssertTrue(RegExMatch(ScrRead(f, ObbyTask.InvBox), ObbyTask.InvRe), f ": its title reads")
    }
    for f in ["world_day", "mari_day_dialog", "mm_board_start", "fishshop_hell_sell", "jester_shop"] {
        AssertTrue(!env(f).InvOpen(tab), f ": no tabs")
        AssertTrue(!RegExMatch(ScrRead(f, ObbyTask.InvBox), ObbyTask.InvRe), f ": no title")
    }
}

; L63 01:17:39: the UGC Shop in the Inventory's frame, told apart from it
Test_Screens_UgcShopReads() {
    AssertTrue(RegExMatch(ScrRead("ugc_shop_windy", ObbyTask.InvBox), ObbyTask.ShopRe), "its title reads")
    AssertTrue(!RegExMatch(ScrRead("ugc_shop_windy", ObbyTask.InvBox), ObbyTask.InvRe), "not the Inventory")
    for f in ["world_day", "mari_day_dialog", "mm_board_start", "fishshop_hell_sell", "jester_shop", "inventory_open_day", "inventory_open_rainy", "raid_open_night"]
        AssertTrue(!RegExMatch(ScrRead(f, ObbyTask.InvBox), ObbyTask.ShopRe), f ": no shop")
}

; L72 04:32..04:55: Jock's dialog (E near him) read by his name, in four
; biomes' light (crops at x680 y890 of the 2560x1440 frame); no other
; screen reads as it (Mari's and Jester's dialogs in the same panel)
Test_Screens_JockDialogReads() {
    b := ObbyTask.JockBox, r := {x: b.x - 680, y: b.y - 890, w: b.w, h: b.h}
    for f in ["jock_dialog_sand_x680_y890", "jock_dialog_snowy_x680_y890", "jock_dialog_windy_x680_y890", "jock_dialog_rainy_x680_y890"] {
        p := A_ScriptDir "\screens\" f ".png"
        AssertTrue(FileExist(p), "frame " f " exists")
        AssertTrue(RegExMatch(Ocr.ReadFile(p, r.x, r.y, r.w, r.h), ObbyTask.JockRe), f ": his name reads")
    }
    for f in ["world_day", "mari_day_dialog", "mari_day_buttons", "mari_night_dialog", "jester_dialog", "jester_buttons", "jester_shop", "ugc_shop_windy", "inventory_open_day", "raid_open_night", "fishshop_hell_sell", "nodeath_hell"]
        AssertTrue(!RegExMatch(ScrRead(f, b), ObbyTask.JockRe), f ": no Jock")
}

Test_Screens_NoPurchasePromptOnGameScreens() {
    ; the shops' own "Purchase" / "Buy" (coins) must never read as Roblox's
    ; prompt (an Esc there would open the Roblox menu)
    b := Input.PurchaseBox
    Loop Files A_ScriptDir "\screens\*.*"
        AssertTrue(!RegExMatch(Ocr.ReadFile(A_LoopFileFullPath, b.x, b.y, b.w, b.h), Input.PurchaseRe), A_LoopFileName ": no purchase prompt")
    for t in ["Buy Robux and item`nR$1,000 Donation`nBuy $4.99", "Your payment method will be charged", "Buy Robux", "Would you like to buy Donation for R$ 1000?"]
        AssertTrue(RegExMatch(t, Input.PurchaseRe), "'" t "' is a purchase prompt")
}
; live 2026-11-10: Eden's combo bar covers the fishing panel's Fish / Exit
; button, so it never read and every cast waited 4 s. The panel's status
; line is never covered: "Location ..." idle, a waiting phrase with the line out.
Test_Screens_FishingStatusLineReadsUnderEden() {
    s := FishingTask.StatusRect
    r := {x: s[1], y: s[2], w: s[3], h: s[4]}
    AssertTrue(RegExMatch(ScrRead("fish_status_ready_eden", r), FishingTask.ReadyRe) > 0, "idle panel reads Location")
    for f in ["fish_status_waiting_eden", "fish_status_anyminute_eden"]
        AssertEq(RegExMatch(ScrRead(f, r), FishingTask.ReadyRe), 0, f ": line out, not ready")
}

; ---- fishing at 1920x1080 (live 2026-11-10) ------------------------------
; Native 1080p frames, cropped (fish1080_<what>_x<ox>_y<oy>.png = the crop's
; top left on the 1920x1080 screen): the panel idle, the reel, the catch
; card. The fishing panel / reel / card scale x0.84, not x0.75, and their
; text keeps its pixel size (FishingTask.MapFishing). Every read goes
; through the task's own mapping, as in the game.

; Screen at 1920x1080 for a crop taken at ox, oy (callers Reset in finally)
ScrAt1080(ox, oy) => Screen.SetClient(-ox, -oy, 1920, 1080)

ScrFish1080(name) => A_ScriptDir "\screens\fish1080_" name ".png"

ScrFishMapped() {
    c := Json.Parse(FileRead(A_ScriptDir "\..\data\coords.json", "UTF-8"))
    return FishingTask.MapFishing(c["fishing"])
}

Test_Screens_Fishing1080PanelReads() {
    p := ScrFish1080("idle_x700_y600")
    AssertTrue(FileExist(p), "frame exists")
    try {
        ScrAt1080(700, 600)
        fc := ScrFishMapped()
        s := FishingTask.MapRect(FishingTask.StatusRect)
        AssertTrue(RegExMatch(Ocr.ReadFile(p, s*), FishingTask.ReadyRe) > 0, "status line reads Location")
        old := FishingTask.StatusRect     ; the x0.75 box cut the L off
        AssertEq(RegExMatch(Ocr.ReadFile(p, old*), FishingTask.ReadyRe), 0, "x0.75 status box misses it (why the mapping)")
        t := fc["panelTitle"]
        AssertTrue(InStr(StrLower(Ocr.ReadFile(p, t["rect"]*)), t["word"]), "panel title reads Fishing")
        b := fc["fishButton"]
        AssertTrue(InStr(StrLower(Ocr.ReadFile(p, b["rect"]*)), b["word"]), "button reads Fish")
        ; the rod click lands on the Fish button (crop 65..235, 222..247;
        ; Screen maps to the crop's px here)
        r := Screen.Pt(fc["rod"][1], fc["rod"][2])
        AssertTrue(r.x >= 70 && r.x <= 230 && r.y >= 224 && r.y <= 245, "rod click on the button (" r.x "," r.y ")")
    } finally
        Screen.Reset()
}

Test_Screens_Fishing1080ReelSeen() {
    p := ScrFish1080("reel_x700_y600")
    AssertTrue(FileExist(p), "frame exists")
    try {
        ScrAt1080(700, 600)
        rc := ScrFishMapped()["reel"]
        g := MatchFileGrab(p)
        grab := (x1, x2, ys, stride) => ScrStripRows(g, x1, x2, ys, stride)
        ys := [rc["arrowY"], rc["barY"]]
        for y in rc["borderYs"]
            ys.Push(y)
        rows := grab(rc["x1"], rc["x2"], ys, rc["stride"])
        s := FishLogic.ReelScan(rows[1], rows[2], rc["x1"], rc["stride"])
        AssertTrue(s.m > 0, "arrow found")
        AssertTrue(s.fill != "", "bar colour found")
        ; the arrow sits over the cyan bar's end (screen ~910 = crop 210)
        ax := Screen.X(s.m)
        AssertTrue(ax >= 195 && ax <= 225, "arrow at crop x " ax)
        ; a border row is the bar's white frame (_ReelUp's 90 %). This frame
        ; is a JPEG capture: over the cyan fill its chroma tints the line
        ; (193,244,245), so only the part past the fill (crop x > 270, where
        ; the line is 228,228,228) is counted here.
        white := false
        Loop rows.Length - 2 {
            n := 0, all := 0
            for c in rows[A_Index + 2] {
                if (Screen.X(rc["x1"] + (A_Index - 1) * rc["stride"]) <= 270)
                    continue
                all++, n += FishLogic.ReelWhite(c) ? 1 : 0
            }
            white := white || (all > 50 && n * 10 >= all * 9)
        }
        AssertTrue(white, "a border row is the bar's white frame (_ReelUp)")
    } finally
        Screen.Reset()
}

; FishingTask._ReelUnseen on the real 1080p reel: the bar's two borders are
; found where they are, and 9 screen px lower (another Roblox top bar) the
; reel rows follow by ~12 design px.
Test_Screens_Fishing1080ReelSearchFindsTheBar() {
    p := ScrFish1080("reel_x700_y600")
    g := MatchFileGrab(p)
    for shift in [0, 9] {
        t := FsMakeCfg()
        try {
            ScrAt1080(700, 600 + shift)
            logs := []
            task := FishingTask(t.cfg, SchedState(), FsDeps(FsIO(), "", true, logs))
            task.deps.grab := (x1, x2, ys, stride) => ScrStripRows(g, x1, x2, ys, stride)
            task._ReelUnseen()
            want := Round(shift / Screen.s)
            AssertTrue(Abs(FishingTask.ReelDy - want) <= 2, "shift " shift ": rows moved " FishingTask.ReelDy ", want ~" want " (" FsJoin(logs) ")")
            AssertTrue(FsHasLog(logs, "borders found"), "shift " shift ": borders found")
        } finally {
            FishLogic.WhiteMin := 220
            FishingTask.ReelDy := 0
            Screen.Reset()
            FsClean(t.dir)
        }
    }
}

Test_Screens_Fishing1080CatchCard() {
    p := ScrFish1080("card_x600_y180")
    AssertTrue(FileExist(p), "frame exists")
    try {
        ScrAt1080(600, 180)
        fc := ScrFishMapped()
        r := fc["result"]["rect"]
        t := Ocr.ReadFile(p, r[1], r[2], r[3], r[4], FishingTask.CardScale)
        AssertTrue(RegExMatch(t, FishingTask.CardRe) > 0, "card reads Fish Caught (" t ")")
        AssertEq(RegExMatch(t, FishingTask.FailRe), 0, "not a miss")
        ; the close click on the card's X (crop 503..521, 153..171)
        c := Screen.Pt(fc["close"][1], fc["close"][2])
        AssertTrue(Abs(c.x - 512) <= 10 && Abs(c.y - 162) <= 10, "close click on the X (" c.x "," c.y ")")
    } finally
        Screen.Reset()
}

Test_Screens_FishingMappingOnlyOff1440() {
    c := Json.Parse(FileRead(A_ScriptDir "\..\data\coords.json", "UTF-8"))["fishing"]
    m := FishingTask.MapFishing(c)
    AssertEq(Json.Stringify(m), Json.Stringify(c), "identity at 2560x1440")
    AssertEq(Json.Stringify(FishingTask.MapRect(FishingTask.StatusRect)), Json.Stringify(FishingTask.StatusRect), "status box unchanged at 2560x1440")
}

; grab(x1, x2, ys, stride) over a frame in design px, each sample at its
; Screen-mapped pixel (nearest), like StripGrab.Rows
ScrStripRows(g, x1, x2, ys, stride) {
    out := []
    for y in ys {
        sy := Screen.Y(y), row := []
        x := x1
        while (x <= x2) {
            DllCall("gdiplus\GdipBitmapGetPixel", "Ptr", g._bmp, "Int", Screen.X(x), "Int", sy, "UInt*", &col := 0)
            row.Push(col & 0xFFFFFF)
            x += stride
        }
        out.Push(row)
    }
    return out
}

; the fishing panel / card scale, measured per size (live windowed, 2026-11-11)
Test_Screens_FishingUiScaleMeasured() {
    AssertTrue(Abs(FishingTask.UiK(1.0) - 1.0) < 0.001, "2560x1440")
    AssertTrue(Abs(FishingTask.UiK(0.75) - 0.84) < 0.001, "1920x1080")
    AssertTrue(Abs(FishingTask.UiK(0.5333) - 0.726) < 0.001, "1366x768")
    k := FishingTask.UiK(0.625)
    AssertTrue(k > 0.726 && k < 0.84, "1600x900 between 768p and 1080p: " k)
    AssertTrue(FishingTask.UiK(0.5) < 0.726, "1280x720 below 768p")
    AssertTrue(FishingTask.UiK(1.5) > 1, "4K above 1")
    ; 1366x768: the reel bar lands where it was measured (client 510..855)
    try {
        Screen.SetClient(0, 0, 1366, 768)
        a := FishingTask.PanelPt(1042, 1044), b := FishingTask.PanelPt(1517, 1044)
        AssertTrue(Abs(Screen.X(a.x) - 510) <= 3 && Abs(Screen.X(b.x) - 855) <= 3, "reel bar x " Screen.X(a.x) ".." Screen.X(b.x))
    } finally Screen.Reset()
}

; 1366x768 (live, 2026-11-11): Mari's name in her dialog is small text that
; reads only at the x2 variant; the name check read '' and nothing was bought
Test_Screens_MariName768() {
    try {
        Screen.SetClient(0, 0, 1366, 768)
        b := MerchantTask.Layout.dialogName
        t := Ocr.ReadFile(A_ScriptDir "\screens\mari_dialog_768.jpg", b.x, b.y, b.w, b.h, MerchantTask.NameScale)
        AssertTrue(RegExMatch(t, MerchantTask.NameRe["Mari"]) > 0, "her name reads at 768: '" t "'")
    } finally Screen.Reset()
}
