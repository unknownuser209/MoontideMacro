#Requires AutoHotkey v2.0
; Tests for lib\tasks\OrbBeacon.ahk: real frames (tests\screens\glow_*.png,
; 2026-11-02 clip frames at HALF size, 1280x720 of 2560x1440: one file px =
; 2 screen px) and the Minions crops (minions_*.png, full size).
;
; GROUND TRUTH (looked at by eye, screen coords 2560x1440):
;   day_sun    NORMAL day: the real sun top left (~x 120..560, y 0..250) =
;              NO orb; a cyan Biome Orb with ghost minions at the house right
;              of centre, centre ~(1874, 700) r ~55 = ORB.
;   sand_close SAND STORM: an orange ring orb right of the player, centre
;              ~(1732, 786) r ~46 = ORB (yellow minions left of it).
;   hell_a     HELL: no orb glow in view (a dull lit ledge ~(1566, 760), red
;              light columns) = NONE.
;   hell_b     HELL: as hell_a, no orb in view = NONE (not cropped).
;   hell_none  HELL: the white sun high in the sky ~(1510, 196) r ~90 and
;              the leaderboards = NONE.
;   windy_far  WINDY night: the pale moon setting behind trees left
;              ~(160, 560), never clipped, not cyan = NONE (no cyan orb).
; Crops: glow_day_area / glow_hell_a / glow_hell_none = OrbBeacon.Area
; (screen 560.., 360..); glow_day_sun screen 80.., 0..; glow_hell_sun
; 1360.., 40..; glow_sand_close 1520.., 640..; glow_windy_moon 80.., 460..
; MatchFileGrab: lib\MatchVision.ahk (included by MemoryMatch, as test_screens)
#Include ..\lib\tasks\OrbBeacon.ahk

; OrbBeacon.Find over a file at screen coords: file px = (screen - o) / scale
; (x1 - ox a multiple of scale, stride a multiple of scale); rows RowStep
; apart from y1 to y2; outside the file reads black.
OrbFileFind(name, scale, ox, oy, x1, x2, y1, y2, biome := "", skyY := 360) {
    f := OrbFileRows(name, scale, ox, oy, x1, x2, y1, y2)
    return OrbBeacon.Find(f.rows, f.ys, x1, OrbBeacon.Stride, biome, skyY)
}

OrbFileRows(name, scale, ox, oy, x1, x2, y1, y2) {
    g := MatchFileGrab(A_ScriptDir "\screens\" name)
    st := OrbBeacon.Stride
    ys := [], rows := []
    y := y1
    while (y <= y2) {
        ys.Push(y)
        rows.Push(g.Call((x1 - ox) // scale, (x2 - ox) // scale, [(y - oy) // scale], st // scale)[1])
        y += OrbBeacon.RowStep
    }
    return {rows: rows, ys: ys}
}

; the Area over a half size crop of it
OrbAreaFind(name, biome := "") {
    a := OrbBeacon.Area
    return OrbFileFind(name, 2, a.x1, a.y1, a.x1, a.x2, a.y1, a.y2, biome)
}

OrbNear(g, x, y, tol) => IsObject(g) && Abs(g.x - x) <= tol && Abs(g.y - y) <= tol

OrbShow(gs) {
    s := ""
    for g in gs
        s .= g.x "," g.y "," g.r " "
    return RTrim(s)
}

; ---- real frames -----------------------------------------------------------

Test_OrbBeacon_RealDayOrbFoundNotSky() {
    for biome in ["", "NORMAL"] {
    gs := OrbAreaFind("glow_day_area.png", biome)
    t := OrbBeacon.Pick(gs)
    AssertTrue(OrbNear(t, 1874, 700, 50), "the cyan orb picked: " OrbShow(gs))
    AssertTrue(t.r >= 30 && t.r <= 90, "its size: " t.r)
    ; the clipped day sky between the trees near the horizon is no glow; a
    ; ghost minion beside the orb may be
    for g in gs
        AssertTrue(OrbNear(g, 1874, 700, 140), "only the orb and its minions: " OrbShow(gs))
    }
}

Test_OrbBeacon_RealDaySunIgnored() {
    gs := OrbFileFind("glow_day_sun.png", 2, 80, 0, 80, 636, 0, 416)
    AssertEq(OrbShow(gs), "", "the sun and the sky round it")
}

Test_OrbBeacon_RealHellSunIgnored() {
    gs := OrbFileFind("glow_hell_sun.png", 2, 1360, 40, 1360, 1676, 40, 436)
    AssertEq(OrbShow(gs), "", "HELL's white sun high in the sky")
}

Test_OrbBeacon_RealHellNoOrb() {
    for biome in ["", "HELL"] {
        AssertEq(OrbShow(OrbAreaFind("glow_hell_a.png", biome)), "", "hell_a: red light, a lit ledge, no orb")
        AssertEq(OrbShow(OrbAreaFind("glow_hell_none.png", biome)), "", "hell_none: the leaderboards, the sun's lower glow")
    }
}

Test_OrbBeacon_RealSandStormCloseOrb() {
    for biome in ["", "SAND STORM"] {
        gs := OrbFileFind("glow_sand_close.png", 2, 1520, 640, 1520, 1916, 640, 916, biome)
        AssertEq(gs.Length, 1, "one glow: " OrbShow(gs))
        t := OrbBeacon.Pick(gs)
        AssertTrue(OrbNear(t, 1732, 786, 30), "the orange ring orb: " OrbShow(gs))
        AssertTrue(t.r >= 30 && t.r <= 70, "its size: " t.r)
    }
}

Test_OrbBeacon_RealWindyMoonIgnored() {
    gs := OrbFileFind("glow_windy_moon.png", 2, 80, 460, 80, 316, 460, 656)
    AssertEq(OrbShow(gs), "", "the pale moon")
}

; the Minions crops (full size) placed at screen (1600, 600)
Test_OrbBeacon_RealSnowyAndSandCrops() {
    f := (name, w, h, biome) => OrbBeacon.Pick(OrbFileFind(name, 1, 1600, 600, 1536, 1600 + w + 60, 536, 600 + h + 60, biome))
    for biome in ["", "SNOWY"] {
        t := f("minions_snowy_close.png", 260, 150, biome)
        AssertTrue(OrbNear(t, 1750, 710, 30), "SNOWY close: white core, cyan rim")
        t := f("minions_snowy_far.png", 200, 130, biome)
        AssertTrue(OrbNear(t, 1695, 700, 30), "SNOWY far")
    }
    for biome in ["", "SAND STORM"] {
        t := f("minions_sand_orb.png", 260, 140, biome)
        AssertTrue(OrbNear(t, 1780, 696, 30), "SAND STORM orb (its bars above it)")
    }
    ; a SNOWY orb in another biome's colours is none
    AssertEq(f("minions_snowy_close.png", 260, 150, "SAND STORM"), "", "SNOWY orb under SAND STORM colours")
}

; live 2026-11-02 frames (tests\screens\glow_orb_* / glow_noorb_*: full
; size crops of 2560x1440 screenshots; file name, its screen x1 y1 x2 y2
; (x1 a multiple of 4, y1 of 8: the scan grid), the biome, the orb's
; centre or ""):
; orb_*: the hunt's frames with an orb in view (SNOWY night far / mid, WINDY
; night, WINDY by day half behind a wall, WINDY peeking over the Quest
; Board). noorb_*: glows the old OrbBeacon walked to (Minions "orb glow at
; ..." then no bar for 10 s, or a hunt without orbs): the pink lit blocks by
; the red Bossraid Portal (SNOWY) and its light in SAND STORM fog, lit house
; windows at night, sunlit tree leaves (NORMAL), SNOWY daylight snow and
; leaderboards, a violet beam (another player's skill), white leaderboard
; text and a green sign at night, a clipped green field (WINDY by day), the
; MOST ROLLED / COLLECTED STAT boards by day (WINDY), the leaderboard in
; the rain (RAINY: no orb colours known, so any biome's colours).
; 2026-11-03 (loop L19): orb_normal_far_*: NORMAL by day in the fog a far
; orb is a small white core in a sky blue rim (3..4 rows), often beside a
; tree (far_tree: two fog-tinted mint tree tops left of it, the old
; OrbBeacon walked to those), orb_windy_far_night the same at night;
; noorb_normal_*: what the old OrbBeacon walked to for 2 min in NORMAL:
; fog-tinted mint tree tops, palm leaves, the clipped day sky between
; leaves / by a trunk / with a cloud, a sign.
; 2026-11-03 later (loop L19 HELL / RAINY / SAND STORM / STARFALL / SNOWY):
; orb_hell_*: the Flame Orb is clipped pure red (255, 0, 0) with a dark
; pentagram, its Molten minions in front; orb_rainy_*: the Raincloud Orb a
; sky blue sphere (only its rim clipped, some cyan); orb_sand_fog: the orange
; ring far in the fog beside a "Your stats" board (the old OrbBeacon took
; the board's yellow text); orb_normal_far_house: a far cyan orb right of
; the shift-locked character. noorb_*: red lamps (orange core), red lit
; blocks / a window (solid), HELL's yellow walls, STARFALL's lit house
; windows, SNOWY lit window frames on a pale lit wall, the character's
; white hair / pet left of centre (shift lock), a cyan skill beam, the day
; sky under a roof, RAINY's stats text, fog, floor, blue sky and a yellow
; glare, SAND STORM's lit board edges.
; 2026-11-03 02:06-02:47 (loop L19): noorb_snowy_*: a lit shop (its white
; sign over its sky blue inside: white rows and rim rows apart), the sky
; over two branches, a board's lit edge; noorb_lost_*: LOST FOREST's fog-lit
; foliage clips deep green / mint (no white: tree tops, leaves, the floor)
; and a small sparkle under a ledge (no orb of LOST FOREST seen in its 2
; hunts and their 60 s clip).
global OrbLiveCrops := [
    ["orb_snowy_far_a", 1368, 680, 1552, 828, "SNOWY", [1460, 756]],
    ["orb_snowy_far_b", 1644, 640, 1830, 784, "SNOWY", [1738, 712]],
    ["orb_snowy_mid", 1472, 600, 1706, 796, "SNOWY", [1590, 700]],
    ["orb_windy_night", 1952, 552, 2138, 700, "WINDY", [2046, 628]],
    ["orb_windy_day_wall", 1756, 520, 1998, 720, "WINDY", [1878, 620]],
    ["orb_windy_board", 1380, 584, 1550, 716, "WINDY", [1466, 652]],
    ["noorb_snowy_portal", 1500, 368, 2140, 972, "SNOWY", ""],
    ["noorb_windy_windows", 1536, 576, 1736, 740, "WINDY", ""],
    ["noorb_normal_leaves", 1680, 600, 1860, 780, "NORMAL", ""],
    ["noorb_snowy_daylight", 1616, 632, 1858, 832, "SNOWY", ""],
    ["noorb_snowy_beam", 1492, 608, 1754, 834, "SNOWY", ""],
    ["noorb_snowy_board", 864, 368, 1104, 552, "SNOWY", ""],
    ["noorb_snowy_sign", 1948, 640, 2170, 820, "SNOWY", ""],
    ["noorb_sand_portal", 1568, 408, 2208, 1008, "SAND STORM", ""],
    ["noorb_windy_field", 1436, 728, 1818, 1070, "WINDY", ""],
    ["noorb_snowy_day", 1452, 488, 1794, 790, "SNOWY", ""],
    ["noorb_windy_boards", 1496, 480, 1858, 800, "WINDY", ""],
    ["noorb_rainy_board", 1936, 488, 2240, 812, "RAINY", ""],
    ["orb_normal_far_tree", 1480, 568, 1800, 736, "NORMAL", [1728, 660]],
    ["orb_normal_far_a", 1560, 584, 1740, 736, "NORMAL", [1650, 660]],
    ["orb_normal_far_b", 1880, 568, 2072, 720, "NORMAL", [1976, 644]],
    ["orb_normal_far_c", 1968, 560, 2156, 712, "NORMAL", [2062, 636]],
    ["orb_windy_far_night", 1720, 584, 1900, 728, "WINDY", [1810, 656]],
    ["noorb_normal_fogtree", 1520, 560, 1740, 736, "NORMAL", ""],
    ["noorb_normal_skyleaves", 864, 512, 1052, 672, "NORMAL", ""],
    ["noorb_normal_skytrunk", 1640, 592, 1840, 752, "NORMAL", ""],
    ["noorb_normal_palm", 1720, 400, 2128, 640, "NORMAL", ""],
    ["noorb_normal_fogtree_b", 1900, 424, 2088, 576, "NORMAL", ""],
    ["noorb_normal_fogtree_c", 1940, 480, 2148, 688, "NORMAL", ""],
    ["noorb_normal_mint", 560, 552, 720, 704, "NORMAL", ""],
    ["noorb_normal_mint_b", 1540, 376, 1732, 520, "NORMAL", ""],
    ["noorb_normal_skycloud", 872, 520, 1064, 672, "NORMAL", ""],
    ["noorb_normal_skytree", 1680, 584, 1880, 752, "NORMAL", ""],
    ["noorb_normal_sign", 2040, 680, 2236, 832, "NORMAL", ""],
    ["orb_hell_minions", 1856, 608, 2120, 816, "HELL", [1988, 712]],
    ["orb_hell_close", 1836, 528, 2096, 752, "HELL", [1966, 640]],
    ["orb_hell_behind", 820, 592, 1048, 792, "HELL", [934, 692]],
    ["orb_rainy_near", 1756, 520, 2060, 792, "RAINY", [1908, 656]],
    ["orb_rainy_bars", 1512, 600, 1816, 864, "RAINY", [1664, 732]],
    ["orb_sand_fog", 1280, 560, 1640, 800, "SAND STORM", [1406, 656]],
    ["orb_normal_far_house", 1312, 544, 1536, 728, "NORMAL", [1424, 636]],
    ["noorb_hell_lamp", 1708, 408, 1908, 592, "HELL", ""],
    ["noorb_hell_lamp_b", 1896, 504, 2098, 688, "HELL", ""],
    ["noorb_hell_block", 1872, 648, 2076, 832, "HELL", ""],
    ["noorb_hell_window", 768, 592, 972, 776, "HELL", ""],
    ["noorb_hell_block_b", 1192, 360, 1396, 520, "HELL", ""],
    ["noorb_hell_walls", 744, 912, 1052, 1096, "HELL", ""],
    ["noorb_hell_tower", 588, 368, 796, 584, "HELL", ""],
    ["noorb_starfall_windows", 1440, 560, 2160, 800, "STARFALL", ""],
    ["noorb_snowy_windows", 1300, 368, 1640, 560, "SNOWY", ""],
    ["noorb_snowy_windows_b", 560, 760, 760, 960, "SNOWY", ""],
    ["noorb_snowy_windows_c", 560, 600, 880, 784, "SNOWY", ""],
    ["noorb_snowy_player", 940, 840, 1300, 1096, "SNOWY", ""],
    ["noorb_snowy_player_b", 860, 640, 1100, 832, "SNOWY", ""],
    ["noorb_normal_beam", 640, 600, 1000, 1000, "NORMAL", ""],
    ["noorb_normal_roofsky", 960, 360, 1180, 520, "NORMAL", ""],
    ["noorb_normal_roofsky_b", 1520, 360, 1740, 520, "NORMAL", ""],
    ["noorb_rainy_text", 756, 624, 980, 784, "RAINY", ""],
    ["noorb_rainy_floor", 560, 800, 860, 1040, "RAINY", ""],
    ["noorb_rainy_fog", 1640, 520, 1940, 800, "RAINY", ""],
    ["noorb_rainy_sky", 920, 360, 1180, 520, "RAINY", ""],
    ["noorb_rainy_glare", 816, 800, 1056, 984, "RAINY", ""],
    ["noorb_sand_board", 1908, 528, 2132, 696, "SAND STORM", ""],
    ["noorb_sand_board_b", 936, 384, 1156, 568, "SAND STORM", ""],
    ["noorb_snowy_shop", 1860, 560, 2240, 880, "SNOWY", ""],
    ["noorb_snowy_shop_b", 1280, 600, 1760, 900, "SNOWY", ""],
    ["noorb_snowy_branches", 660, 584, 880, 760, "SNOWY", ""],
    ["noorb_snowy_boardedge", 1640, 560, 1800, 696, "SNOWY", ""],
    ["noorb_lost_tree", 1580, 504, 1812, 680, "LOST FOREST", ""],
    ["noorb_lost_tree_b", 660, 560, 860, 720, "LOST FOREST", ""],
    ["noorb_lost_sparkle", 2000, 368, 2200, 496, "LOST FOREST", ""],
    ["noorb_lost_leaves", 1960, 488, 2164, 640, "LOST FOREST", ""],
    ["noorb_lost_floor", 1980, 784, 2200, 936, "LOST FOREST", ""]]

; the fight camera (Scan from FightTop, as OrbLiveCrops): orb_sand_washed: L22
; 17:17:29, the orb the fog washes under MinSat, a darker orange disc between
; its yellow minions; orb_rainy_far_*: the user's RAINY night clip 170608 (t 0,
; 2, 3 s), the Raincloud Orb far at y 150..420, its rim never clipped; noorb:
; a lit yellow block and the red Bossraid Portal in the fog, the player's blue
; floor mark, a portal, the character's hair, bars with no orb at night.
; L72 SAND STORM (2026-11-09, the hunt's frames; OrbBeacon HOLLOW): noorb_sand_*:
; the 10 glows it walked to, none an orb, the fog tints them orange: Bob's UGC
; Shop lamp (04:32:23, 04:32:45, 04:33:15), lit house doors (04:35:30,
; 04:36:06), the leaderboard (04:36:35), a studded block close by (04:40:18,
; 05:36:03), the Memory Match board (04:40:51); orb_sand_l72_*: the orange orb
; near, its minions and bars round it (05:31:42, 05:31:45, 05:37:22).
global OrbFightCrops := [
    ["orb_sand_washed", 640, 96, 880, 240, "SAND STORM", [757, 150]],
    ["orb_rainy_far_a", 1040, 96, 1248, 320, "RAINY", [1146, 200]],
    ["orb_rainy_far_b", 544, 104, 784, 328, "RAINY", [656, 216]],
    ["orb_rainy_far_c", 860, 216, 1116, 472, "RAINY", [988, 344]],
    ["noorb_sand_redportal", 560, 240, 860, 500, "SAND STORM", ""],
    ["noorb_rainy_decal", 1000, 600, 1500, 1000, "RAINY", ""],
    ["noorb_rainy_portal", 760, 200, 1100, 440, "RAINY", ""],
    ["noorb_rainy_hair", 760, 880, 1140, 1096, "RAINY", ""],
    ["noorb_rainy_clipbars", 900, 96, 1500, 500, "RAINY", ""],
    ["noorb_sand_shoplamp", 1400, 400, 1648, 576, "SAND STORM", ""],
    ["noorb_sand_shoplamp_b", 1000, 400, 1240, 576, "SAND STORM", ""],
    ["noorb_sand_shoplamp_c", 1740, 400, 1980, 584, "SAND STORM", ""],
    ["noorb_sand_door", 1764, 384, 2008, 560, "SAND STORM", ""],
    ["noorb_sand_door_b", 1976, 384, 2232, 568, "SAND STORM", ""],
    ["noorb_sand_leaderboard", 1420, 400, 1748, 680, "SAND STORM", ""],
    ["noorb_sand_studs", 1340, 96, 1800, 380, "SAND STORM", ""],
    ["noorb_sand_mmboard", 1160, 424, 1420, 616, "SAND STORM", ""],
    ["noorb_sand_studs_b", 1160, 256, 1440, 488, "SAND STORM", ""],
    ["orb_sand_l72_a", 2016, 440, 2236, 656, "SAND STORM", [2142, 544]],
    ["orb_sand_l72_b", 1560, 432, 1820, 640, "SAND STORM", [1690, 536]],
    ["orb_sand_l72_c", 1700, 440, 1964, 672, "SAND STORM", [1832, 556]]]

OrbFightFind(c, biome := "") {
    return OrbFileFind("glow_" c[1] ".png", 1, c[2], c[3], c[2], c[4], c[3], c[5], biome != "" ? biome : c[6], OrbBeacon.FightTop)
}

Test_OrbBeacon_RealFightOrbsFound() {
    for c in OrbFightCrops {
        if !IsObject(c[7])
            continue
        gs := OrbFightFind(c)
        AssertTrue(OrbNear(OrbBeacon.Pick(gs), c[7][1], c[7][2], 30), c[1] ": the orb: " OrbShow(gs))
    }
}

Test_OrbBeacon_RealFightNoOrb() {
    for c in OrbFightCrops
        if !IsObject(c[7])
            AssertEq(OrbShow(OrbFightFind(c)), "", c[1] " (" c[6] ")")
}

; the L72 SAND STORM fakes are glows but not hollow: each one glows without
; the HOLLOW test (so it is that test that drops it), the sand orbs of the
; glow crops are hollow
Test_OrbBeacon_RealSandLitNotHollow() {
    core := OrbBeacon.HollowCore, dark := OrbBeacon.HollowDark
    OrbBeacon.HollowCore := 1, OrbBeacon.HollowDark := 0
    try {
        for c in OrbFightCrops
            if (InStr(c[1], "noorb_sand_") = 1 && c[1] != "noorb_sand_redportal")
                AssertTrue(OrbFightFind(c).Length >= 1, c[1] ": a glow without HOLLOW")
    } finally
        OrbBeacon.HollowCore := core, OrbBeacon.HollowDark := dark
    gs := OrbFileFind("glow_orb_sand_fog.png", 1, 1280, 560, 1280, 1640, 560, 800, "SAND STORM")
    AssertTrue(OrbNear(OrbBeacon.Pick(gs), 1406, 656, 30), "the far ring in the fog: " OrbShow(gs))
}

; a lit sand block close by: no disc, and its solid lit studs no glow (HOLLOW)
Test_OrbBeacon_RealSandBlockNoDisc() {
    f := OrbFileRows("glow_noorb_sand_block.png", 1, 560, 320, 560, 860, 320, 520)
    AssertEq(OrbShow(OrbBeacon._Discs(f.rows, f.ys, 560, OrbBeacon.Stride, OrbBeacon.RowStep, OrbBeacon.FightTop, true)), "", "the block")
    AssertEq(OrbShow(OrbBeacon.Find(f.rows, f.ys, 560, OrbBeacon.Stride, "SAND STORM", OrbBeacon.FightTop)), "", "its studs")
}

; a disc is the biome's own: the washed sand orb is no RAINY orb, a far RAINY
; orb no SAND STORM one, and no other biome looks for discs
Test_OrbBeacon_RealDiscOnlyInItsBiome() {
    AssertEq(OrbShow(OrbFightFind(OrbFightCrops[1], "RAINY")), "", "sand orb under RAINY")
    AssertEq(OrbShow(OrbFightFind(OrbFightCrops[2], "SAND STORM")), "", "RAINY orb under SAND STORM")
    AssertEq(OrbShow(OrbFightFind(OrbFightCrops[2], "NORMAL")), "", "RAINY orb under NORMAL")
}

; every glow_noorb_ crop of SAND STORM and RAINY stays clean with the fight
; camera's sky line too (far orbs are looked for up to FightTop)
Test_OrbBeacon_RealNoOrbFromFightTop() {
    for c in OrbLiveCrops
        if (!IsObject(c[7]) && (c[6] = "SAND STORM" || c[6] = "RAINY"))
            AssertEq(OrbShow(OrbFileFind("glow_" c[1] ".png", 1, c[2], c[3], c[2], c[4], c[3], c[5], c[6], OrbBeacon.FightTop)), "", c[1])
}

OrbLiveFind(c) {
    return OrbFileFind("glow_" c[1] ".png", 1, c[2], c[3], c[2], c[4], c[3], c[5], c[6])
}

Test_OrbBeacon_RealLiveOrbsFound() {
    for c in OrbLiveCrops {
        if !IsObject(c[7])
            continue
        gs := OrbLiveFind(c)
        AssertTrue(OrbNear(OrbBeacon.Pick(gs), c[7][1], c[7][2], 30), c[1] ": the orb: " OrbShow(gs))
    }
}

; the far orb beside the trees: the fog-tinted mint tree tops left of it
; (~(1556, 660), ~(1660, 624)) give nothing (NORMAL / WINDY; with no biome
; known they are LOST FOREST's green)
Test_OrbBeacon_RealNormalFarOrbNotTreeTops() {
    for biome in ["NORMAL", "WINDY"] {
        gs := OrbFileFind("glow_orb_normal_far_tree.png", 1, 1480, 568, 1480, 1800, 568, 736, biome)
        AssertTrue(gs.Length >= 1, biome ": the orb: " OrbShow(gs))
        for g in gs
            AssertTrue(OrbNear(g, 1728, 660, 30), biome ": only the orb, no tree top: " OrbShow(gs))
    }
}

Test_OrbBeacon_RealLiveFalseGlowsIgnored() {
    for c in OrbLiveCrops
        if !IsObject(c[7])
            AssertEq(OrbShow(OrbLiveFind(c)), "", c[1] " (" c[6] ")")
}

; ---- synthetic -------------------------------------------------------------

; rows over x 1000.., ys from y0 RowStep apart, background bg, with discs
; {x, y, r, c} (c inside, white core out to r * 0.7 when core = 1)
OrbSynth(discs, y0 := 600, h := 400, bg := 0x203040) {
    st := OrbBeacon.Stride
    ys := [], rows := []
    y := y0
    while (y < y0 + h) {
        ys.Push(y)
        row := []
        x := 1000
        while (x <= 1800) {
            c := bg
            for d in discs {
                dx := x - d.x, dy := y - d.y
                if (dx * dx + dy * dy <= d.r * d.r)
                    c := (d.HasOwnProp("core") && dx * dx + dy * dy <= d.r * d.r / 2) ? 0xFFFFFF : d.c
            }
            row.Push(c)
            x += st
        }
        rows.Push(row)
        y += OrbBeacon.RowStep
    }
    return OrbBeacon.Find(rows, ys, 1000, st)
}

Test_OrbBeacon_SynthDiscs() {
    gs := OrbSynth([{x: 1600, y: 800, r: 40, c: 0x40FFFF}])
    AssertEq(gs.Length, 1, "a cyan disc")
    AssertTrue(OrbNear(gs[1], 1600, 800, 8) && Abs(gs[1].r - 40) <= 8, "where it is: " OrbShow(gs))
    AssertEq(OrbSynth([{x: 1600, y: 800, r: 40, c: 0xFFB050}]).Length, 1, "orange")
    AssertEq(OrbSynth([{x: 1600, y: 800, r: 40, c: 0x60C8FF, core: 1}]).Length, 1, "white core, blue rim")
    AssertEq(OrbSynth([{x: 1600, y: 800, r: 40, c: 0xFF2010}]).Length, 0, "red light")
    AssertEq(OrbSynth([{x: 1600, y: 800, r: 40, c: 0xFFFFFF}]).Length, 0, "white only (a white body, text)")
    AssertEq(OrbSynth([{x: 1600, y: 800, r: 40, c: 0xC0D0F0}]).Length, 0, "pale (the moon)")
    AssertEq(OrbSynth([{x: 1600, y: 800, r: 40, c: 0x90E0FF}]).Length, 0, "day sky blue")
    AssertEq(OrbSynth([{x: 1600, y: 800, r: 3, c: 0x40FFFF}]).Length, 0, "too small")
    AssertEq(OrbSynth([{x: 1280, y: 800, r: 40, c: 0xFFB050}]).Length, 0, "on the player (an aura's glow)")
    AssertEq(OrbSynth([{x: 1600, y: 380, r: 40, c: 0x40FFFF}], 360).Length, 0, "cut by the sky line")
    AssertEq(OrbSynth([{x: 1600, y: 450, r: 40, c: 0x40FFFF}], 360).Length, 1, "below the sky line")
    AssertEq(OrbSynth([{x: 1600, y: 800, r: 40, c: 0xFF90B0}]).Length, 0, "pink (portal light)")
    AssertEq(OrbSynth([{x: 1600, y: 800, r: 12, c: 0x40FFFF}]).Length, 0, "under MinRows rows")
}

; NORMAL / WINDY: a fog-tinted mint tree top (pale mint, no clipped cyan) and
; the pale day sky (cyan, red ~180) are none; the orb's deep cyan / mint is
Test_OrbBeacon_SynthNormalPaleMintAndSkyAreNone() {
    for biome in ["NORMAL", "WINDY", ""] {
        ; (no biome: any biome's colours, LOST FOREST's mint too)
        if (biome != "")
            AssertEq(OrbSynthB([{x: 1600, y: 800, r: 40, c: 0x88F8D0}], biome).Length, 0, biome ": pale mint (tree top)")
        AssertEq(OrbSynthB([{x: 1600, y: 800, r: 40, c: 0xB8FFFF}], biome).Length, 0, biome ": pale cyan (day sky)")
        AssertEq(OrbSynthB([{x: 1600, y: 800, r: 40, c: 0x30FFFF}], biome).Length, 1, biome ": deep cyan (an orb)")
        ; a ring: deep cyan outside, deep mint inside (the day orb)
        AssertEq(OrbSynthB([{x: 1600, y: 800, r: 40, c: 0x30FFFF}, {x: 1600, y: 800, r: 28, c: 0x40F8D8}], biome).Length, 1, biome ": cyan / mint ring")
    }
    ; LOST FOREST: green / mint round a white core; its foliage's deep green
    ; / mint alone is none
    core := [{x: 1600, y: 800, r: 40, c: 0x30FFB0}, {x: 1600, y: 800, r: 28, c: 0xFFFFFF}]
    AssertEq(OrbSynthB(core, "LOST FOREST").Length, 1, "LOST FOREST: mint round a white core")
    AssertEq(OrbSynthB([{x: 1600, y: 800, r: 40, c: 0x30FFB0}], "LOST FOREST").Length, 0, "LOST FOREST: deep mint alone")
    AssertEq(OrbSynthB([{x: 1600, y: 800, r: 40, c: 0x88F8D0}], "LOST FOREST").Length, 0, "LOST FOREST: pale mint alone")
    ; white over the rim, not inside it (a lit sign over its inside)
    split := [{x: 1600, y: 800, r: 40, c: 0x30FFB0}, {x: 1600, y: 770, r: 22, c: 0xFFFFFF}]
    AssertEq(OrbSynthB(split, "LOST FOREST").Length, 0, "LOST FOREST: white rows over mint rows")
}

; SNOWY: the white core sits inside its blue rim in most rows; a lit shop's
; white sign over its sky blue inside (white rows, then blue rows) is none
Test_OrbBeacon_SynthSnowyCoreInRim() {
    AssertEq(OrbSynthB([{x: 1600, y: 800, r: 40, c: 0x60C8FF}, {x: 1600, y: 800, r: 30, c: 0xFFFFFF}], "SNOWY").Length, 1, "white in a blue rim")
    shop := [{x: 1600, y: 784, r: 40, c: 0xFFFFFF}, {x: 1600, y: 824, r: 34, c: 0x60C8FF}]
    AssertEq(OrbSynthB(shop, "SNOWY").Length, 0, "white over blue")
}

; NORMAL / WINDY far orb by day: a small white core in a sky blue rim, 3 rows
Test_OrbBeacon_SynthNormalFarOrb() {
    far := [{x: 1600, y: 804, r: 14, c: 0x88C8F8}, {x: 1600, y: 804, r: 13, c: 0x60FFFF}, {x: 1600, y: 804, r: 8, c: 0xFFFFFF}]
    for biome in ["NORMAL", "WINDY", ""]
        AssertEq(OrbSynthB(far, biome).Length, 1, biome ": white core, blue rim")
    AssertEq(OrbSynthB(far, "SAND STORM").Length, 0, "SAND STORM: not its colours")
    ; white only (text, a white wall) and white with no rim on one side
    AssertEq(OrbSynthB([{x: 1600, y: 804, r: 14, c: 0xFFFFFF}], "NORMAL").Length, 0, "white only")
    AssertEq(OrbSynthB([{x: 1600, y: 804, r: 14, c: 0x88C8F8}, {x: 1610, y: 804, r: 8, c: 0xFFFFFF}], "NORMAL").Length, 0, "white at the rim's edge")
}

; OrbSynth with a biome; discs later in the list paint over earlier ones
OrbSynthB(discs, biome, y0 := 600, h := 400, bg := 0x203040) {
    st := OrbBeacon.Stride
    ys := [], rows := []
    y := y0
    while (y < y0 + h) {
        ys.Push(y)
        row := []
        x := 1000
        while (x <= 1800) {
            c := bg
            for d in discs {
                dx := x - d.x, dy := y - d.y
                if (dx * dx + dy * dy <= d.r * d.r)
                    c := d.c
            }
            row.Push(c)
            x += st
        }
        rows.Push(row)
        y += OrbBeacon.RowStep
    }
    return OrbBeacon.Find(rows, ys, 1000, st, biome)
}

Test_OrbBeacon_SynthStripsAreNoGlow() {
    ; a health bar: 5 px high, one row
    st := OrbBeacon.Stride
    rows := [], ys := []
    Loop 6 {
        i := A_Index
        ys.Push(600 + (i - 1) * 8)
        row := []
        Loop 201
            row.Push(i = 3 && A_Index > 50 && A_Index < 80 ? 0xFFFF60 : 0)
        rows.Push(row)
    }
    AssertEq(OrbBeacon.Find(rows, ys, 1000, st).Length, 0, "a bar")
    ; a long neon floor edge over 3 rows
    rows := []
    Loop 6 {
        row := []
        i := A_Index
        Loop 201
            row.Push(i >= 2 && i <= 4 && A_Index > 10 && A_Index < 190 ? 0x60FFB0 : 0)
        rows.Push(row)
    }
    AssertEq(OrbBeacon.Find(rows, ys, 1000, st).Length, 0, "a floor strip")
}

Test_OrbBeacon_Pick() {
    AssertEq(OrbBeacon.Pick([]), "", "none")
    t := OrbBeacon.Pick([{x: 1, y: 500, r: 20}, {x: 2, y: 600, r: 40}, {x: 3, y: 700, r: 40}, {x: 4, y: 800, r: 10}])
    AssertEq(t.x, 3, "the biggest, then the lowest")
}

; HELL: the Flame Orb is clipped pure red with a dark pentagram (a ring
; here); red is no glow in other biomes, a red lamp has an orange core, a red
; lit block is solid
Test_OrbBeacon_SynthHellRed() {
    ring := [{x: 1600, y: 800, r: 40, c: 0xFF0000}, {x: 1600, y: 800, r: 24, c: 0x300000}]
    AssertEq(OrbSynthB(ring, "HELL").Length, 1, "HELL: red ring")
    for biome in ["", "NORMAL", "SAND STORM", "RAINY"]
        AssertEq(OrbSynthB(ring, biome).Length, 0, biome ": red is no glow")
    lamp := [{x: 1600, y: 800, r: 40, c: 0xFF0000}, {x: 1600, y: 800, r: 24, c: 0xFFA020}]
    AssertEq(OrbSynthB(lamp, "HELL").Length, 0, "HELL: red lamp, orange core")
    AssertEq(OrbSynthB([{x: 1600, y: 800, r: 40, c: 0xFF0000}], "HELL").Length, 0, "HELL: solid red")
    AssertEq(OrbSynthB([{x: 1600, y: 800, r: 40, c: 0xFFB050}], "HELL").Length, 0, "HELL: orange (not its orb)")
}

; RAINY: the Raincloud Orb is sky blue with some clipped cyan, or a round
; blue disc (OrbFightCrops); sky blue that is not round (blue sky, fog) and
; yellow (text, glare) are none
Test_OrbBeacon_SynthRainyBlue() {
    orb := [{x: 1600, y: 800, r: 40, c: 0x60A0FF}, {x: 1600, y: 800, r: 36, c: 0x203060}, {x: 1600, y: 770, r: 8, c: 0x60FFFF}]
    AssertEq(OrbSynthB(orb, "RAINY").Length, 1, "RAINY: sky blue rim, some cyan")
    AssertEq(OrbSynthB([{x: 1560, y: 800, r: 40, c: 0x60A0FF}, {x: 1640, y: 800, r: 40, c: 0x60A0FF}], "RAINY").Length, 0, "RAINY: sky blue only, not round")
    AssertEq(OrbSynthB([{x: 1600, y: 800, r: 40, c: 0xFFE040}], "RAINY").Length, 0, "RAINY: yellow")
}

; the character's white left of centre (shift lock) or at it is none; the
; same orb further right is one; a coloured glow is dropped only at the
; character's head (x 1120..1300)
Test_OrbBeacon_SynthPlayerWhite() {
    orb := (x) => [{x: x, y: 800, r: 40, c: 0x60C8FF}, {x: x, y: 800, r: 34, c: 0xFFFFFF}]
    AssertEq(OrbSynthB(orb(1060), "SNOWY").Length, 0, "white at the shift-locked character")
    AssertEq(OrbSynthB(orb(1600), "SNOWY").Length, 1, "white further right")
    AssertEq(OrbSynthB([{x: 1380, y: 800, r: 40, c: 0x30FFFF}], "NORMAL").Length, 1, "cyan right of the head")
    AssertEq(OrbSynthB([{x: 1200, y: 800, r: 40, c: 0x30FFFF}], "NORMAL").Length, 0, "cyan at the head")
}

; a thin slanted cyan beam (a skill) is none: its rows span little of it
Test_OrbBeacon_SynthBeamIsNone() {
    beam := []
    Loop 12
        beam.Push({x: 1500 + A_Index * 8, y: 740 + A_Index * 8, r: 5, c: 0x30FFFF})
    AssertEq(OrbSynthB(beam, "NORMAL").Length, 0, "a slanted beam")
}
