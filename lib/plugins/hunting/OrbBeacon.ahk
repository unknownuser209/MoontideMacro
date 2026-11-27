#Requires AutoHotkey v2.0
; ---------------------------------------------------------------------------
; OrbBeacon: finds the glow of a far Biome Orb (2026 Halloween update), for
; the Minions hunt to walk to while the orb's thin health bar is still too
; small for MinionsTask.FindBars (MinionsTask: only while no bar is in sight).
;
;   glows := OrbBeacon.Scan(grab, biome := "")
;                                   grab(x1, x2, ys, stride) -> rows
;                                   (StripGrab.Rows shape) over Area; biome
;                                   (state.biome) picks the orb colours
;   glows := OrbBeacon.Find(rows, ys, x1, stride, biome := "")
;            rows: one Array per y in ys (rows evenly spaced), every
;            stride-th pixel from x1 (as MinionsTask.FindBars) ->
;            Array of {x, y, r}: centre and radius in screen px (2560x1440)
;   g := OrbBeacon.Pick(glows)      the nearest: the biggest (then the
;                                   lowest); "" when none
;
; WHAT A GLOW IS: an orb is a sphere glowing so bright that the game clips a
; channel: cyan (WINDY / NORMAL: g and b at 255, r low), white with a cyan
; rim (SNOWY), orange (SAND STORM: r at 255, a ring with a darker inside in
; fog), pure red (HELL: the Flame Orb, (255, 0, 0) with a dark pentagram),
; sky blue with some cyan (RAINY: the Raincloud Orb, only its rim clipped).
; A glow pixel has its brightest channel >= MinBright and is either near
; white (all >= WhiteMin) or coloured (max - min >= MinSat), but never red
; alone (green under RedG when red is the top: red light), save in HELL
; (red clipped, green and blue <= RedOrbGB: its orb's red).
; Glow pixels form runs per row (GapPx bridged); a run longer than 2 * RMax
; (a floor edge) is dropped, and a run 3 rows long or more must have a run
; under or over it covering StripCover of it (else it is a health bar or a
; neon strip). Runs touching from row to row (SlackPx) make one blob; blobs
; MergePx apart merge (a ring split in two, an orb and its glowing minions)
; while the merge stays round. A blob is a glow when it has coloured pixels,
; spans MinRows rows or more, is RMin..RMax in radius, MinAspect..MaxAspect
; wide for its height (FlatAspect while under FlatRows rows: a flat strip),
; is in the biome's colours (Kind sorts each glow pixel by colour, Palette):
;   - NORMAL / WINDY: cyan or mint (mint: g clipped, b high, r low: the cyan
;     orb by day; sunlit leaves have more red, a lit field less blue) are
;     PalShare of its pixels, and deep ones (red under DeepR) DeepShare of
;     its coloured pixels (the day sky between leaves or branches, mint tree
;     tops in the fog and palm leaves clip pale: red 120..200) and clipped
;     cyan CyanShare of them (a mint tree top has none); a pale mint blob
;     never merges with a white one. Far by day in the fog an orb is only a
;     small white core in a sky blue rim (FarWhite: 3 rows or more, rim on
;     both sides of the white, so not a cloud in the sky between branches);
;     NORMAL / WINDY never have orange / yellow over CyanWarm of the
;     coloured (the day sky under an orange roof edge or a sign);
;   - SAND STORM: orange or yellow PalShare (not salmon: the Bossraid
;     Portal's light in the fog), deep orange (hue under DeepHue) OrangeDeep
;     of it (lit boards, windows and "Your stats" text are yellower: hue
;     38..53, the orb 21..43);
;   - LOST FOREST: green / mint PalShare of the coloured round a white core
;     (GreenWhite px or more, FarCore of all, a filled disc), white and rim
;     side by side in MixRows of its rows (its fog-lit foliage clips deep
;     green / mint with no white; no orb of LOST FOREST seen yet);
;   - HELL: red PalShare, orange / yellow under RedWarm (a red lamp's
;     orange core), glow px at most RedFill of its box (a red lit block or
;     window is solid; the orb's pentagram is dark);
;   - RAINY: sky blue / blue / cyan PalShare with clipped cyan RainCyan of
;     the coloured (the rain's blue sky and fog have none);
;   - SNOWY: a white core (SnowWhite of it) with a blue / cyan rim (SnowRim
;     of the coloured, SnowRimAll of all) filling SnowFill of its box (not a
;     beam, not a line of text), white and rim side by side in MixRows of
;     its rows (a lit shop's white sign over its sky blue inside, the sky
;     over branches, a board's lit edge: white rows and rim rows apart);
;   - any other biome (STARFALL, ..., "" unknown): little pink and the
;     colours of NORMAL, SNOWY, SAND STORM or LOST FOREST;
; has a row spanning RowSpan of its width (a thin slanted skill beam: each
; row only a bit), stands out (little glow SidePx beside it in its rows,
; SideMaxSand in SAND STORM: its glowing minions stand close; little clipped
; at all beside it, LitMax: a pale lit wall round lit window frames; and 2
; rows over / under it: a lit field, daylight snow or a lit board glow all
; round), and is none of:
;   - in the sky: its top row above SkyY + SkyRows rows (the top 25% of the
;     screen; the sun sits high and the daytime sky around it clips too;
;     the sky under a roof at the area's top);
;   - daytime sky blue (not RAINY): most of its coloured pixels blue at the
;     top with green under 243 and red well under green, and little white
;     (sky between trees near the horizon; an orb's cyan clips green too);
;   - centred on the character's head (Player: x 1120..1300, with or
;     without shift lock; an aura's own glow, e.g. Pumpkinity's head), or
;     mostly white (PlayerWhite) centred on its body (x 940..1440: the
;     character sits left of centre in shift lock; its white hair, its pet);
;   - touching the first / last pixel of the rows (cut by the area edge).
;
; HOLLOW (SAND STORM): the sand orb is a glowing ring, darker inside, in fog
; and at night, near or far (the test crops, L72). What else glows orange in
; the fog is lit from the front or lit through: Bob's UGC Shop lamp, lit house
; doors / windows, leaderboard and "Your stats" boards, studded blocks close
; by, the Memory Match board (L72 04:32..04:41, 10 glows, none an orb, the hunt
; walked off the island after them). A glow's core (middle half of its width
; and height) glows at most HollowCore (a lamp, a lit stud, a board: solid)
; and HollowDark of it is dark (a lit door frame, an L of a board's edge: bright
; fog inside). The near orbs of L72 are discs (not glows): unchanged.
;
; A DISC (SAND STORM, RAINY only, on top of the glows): fog washes the sand
; orb (rim (251, 222, 210): under MinSat) and the Raincloud Orb far off or at
; night never clips (rim (58, 135, 234)), so neither is a glow. Each is still
; a round blob of its tint against what is around it, whatever the light:
; tint = red over blue (SAND STORM, orange hue SalmonHue..DiscHue, red
; DiscRed or more) or blue over red and green (RAINY). Tinted px form runs and
; blobs as glows do; a blob is a disc when it is DiscAspect round, DiscFill of
; the circle in it is tinted, under DiscOut of the ring round it and DiscCorner
; of its box's corners (a block), and its mean tint is DiscContrast over the
; ring's. SAND STORM: its rim no darker than its core by DiscRim (the orb is
; darker inside; a lit icon, a board: bright inside). The sky, Player and edge
; tests of a glow hold.
;
; REAL FRAMES (tests\test_orbbeacon.ahk, 2026-11-02 clip frames at half
; size): the NORMAL day orb (cyan, with its ghost minions) and the SAND
; STORM orb (orange ring, close) found, the SNOWY orbs of the Minions
; crops found; the day sun, the HELL sun, the WINDY moon (pale, never
; clipped) and two HELL frames without an orb give nothing. Live hunt
; frames (glow_orb_* / glow_noorb_*): SNOWY orbs far and mid, WINDY orbs at
; night, by day half behind a wall and over the Quest Board found; the pink
; blocks by the Bossraid Portal (SNOWY) and its light in SAND STORM fog,
; lit windows at night, sunlit leaves, daylight snow, a violet beam,
; leaderboards and signs (SNOWY, WINDY, RAINY), a clipped field give
; nothing. Over 203 saved hunt screenshots (17 runs, 2026-11-02): frames
; with a false glow 152 -> 9, the 15 orbs in view all still found. Loop L19
; (2026-11-03, 77 hunt screenshots): NORMAL frames with a false glow (mint
; tree tops in fog, palm leaves, day sky between leaves) 23 -> 3 (a cyan
; skill beam, sky under a roof), far NORMAL / WINDY orbs 1 -> 5 found.
; Loop L19 + L18 all biomes (2026-11-03, 210 hunt screenshots, judged by
; eye): false glows 45 in 31 frames -> 4 in 4 (SNOWY: a lit shop, sky
; between branches, a board edge; a cyan beam in RAINY), orb frames found
; 25 -> 33 (HELL's red Flame Orb 0 -> 3, RAINY's orb 0 -> 3, a SAND STORM
; orb in fog, a far cyan orb right of the character), none lost.
; Loop L19 02:06-02:47 (LOST FOREST, SNOWY): false glows 9 in 8 frames -> 0
; (LOST FOREST foliage / a sparkle 5 in 4 frames, the 60 s LOST FOREST clip
; 116 in 60 frames -> 0; SNOWY lit shop x2, sky over branches, board edge),
; every SNOWY orb still found.
;
; Discs (2026-11-05): 60 s of the user's RAINY night clip 170608 (1 frame a
; second, the orb in most): frames with a glow 6 -> 38, the far ones at y
; 180..350 all found; L22 SAND STORM's washed orb found; forced over the 37
; L22..L26 frames, SAND STORM adds only that orb, and no RAINY frame adds one.
;
; LIMITS (honest):
;   - Only clipped glows: an orb far in thick fog, at night behind
;     something, or dimmed by distance may never reach MinBright. No frame
;     of a far HELL orb (under ~50 px) was seen, nor of a LOST FOREST
;     (green) orb: a LOST FOREST orb without a white core is never found
;     (its bar still is); a far HELL orb whose dark pentagram blurs may read solid
;     (RedFill: orbs 0.37..0.57 of their box, lit blocks 0.62..0.81).
;   - Rows RowStep apart: r is the blob's half size, often merged with its
;     minions or bars (x off by up to ~30 px).
;   - Any other clipped, roundish thing in the biome's colours that stands
;     out reads as an orb: a cyan aura or skill of another player, sky
;     between two trees by day, an aura's glow on the floor by the character,
;     a red lamp without an orange core in HELL.
;   - Orb colours of STARFALL, CORRUPTION, HEAVEN and LOST FOREST were never
;     seen (guessed; STARFALL frames had no orb in view); an orb in colours
;     off its biome's palette is dropped. HELL (red) and RAINY (sky blue)
;     are from 3 frames each.
;   - A disc needs the whole orb in view: one half behind a wall or a tower
;     (L25 RAINY 22:24:52) is only found by its bars. Only one washed SAND
;     STORM orb was ever saved: the Disc numbers for SAND STORM come from
;     that frame and two clearer ones; no frame of SAND STORM at night.
;   - A lit sand block close by (L22 17:18:39, its stud highlights clip
;     orange as the orb's ring does; no disc) read as a glow till HOLLOW:
;     solid studs. HOLLOW is from 3 orb glows (fog, night, with minions)
;     and 10 fakes; a lit frame dark inside (a window at night, its glass
;     dark) would pass it.
;   - Under MinRows rows (~32 px high, an orb of r < 16, its bar then ~20 px
;     wide) is no glow.
;   - An orb straight ahead behind the character's head (Player box) is
;     dropped, a mostly white one (SNOWY) by its body too (PlayerWhite);
;     an orb with glowing minions touching it on both sides can merge too
;     wide (MaxAspect) and be dropped (minions_windy_far).
;   - Daytime sky test is by colour: a blue-white orb with no white core
;     against the sky would be dropped too.
; COST: one grab of Area rows RowStep apart, every Stride-th pixel (93 rows
; x 421 px = ~39k pixels), one pass with a cheap reject per pixel.
; ---------------------------------------------------------------------------

class OrbBeacon {
    ; scan area (2560x1440): below the top 25% (sky, sun), above the points
    ; bar, right of the chat / HUD buttons, left of the skill list (as
    ; MinionsTask.Area)
    static Area := {x1: 560, x2: 2240, y1: 360, y2: 1096}
    static SkyY := 360
    static FightTop := 96        ; the fight camera's top row, see Scan
    static SkyRows := 3          ; a glow's top row this many rows under SkyY or lower (the sky
                                 ; seen under a roof or between leaves at the area's top)
    static RowStep := 8
    static Stride := 4
    static MinBright := 240      ; brightest channel (clipped glow; sand orb rim 246..255 in fog)
    static WhiteMin := 235       ; all channels: a white core
    static MinSat := 60          ; max - min: coloured
    static RedG := 128           ; red the top and green under this: red light, not a glow
    static RedOrbGB := 40        ; HELL: red clipped, green and blue at most this: the Flame Orb
    static CyanWarm := 0.1       ; NORMAL / WINDY: orange / yellow at most this share (sky under an
                                 ; orange roof edge or sign; an orb's cyan has none)
    static DeepHue := 36         ; SAND STORM: orange hue under this (deg; its orb 21..43, median 30;
    static OrangeDeep := 0.4     ; this share of its orange / yellow px; lit boards, windows, text 38..53)
    static RainCyan := 0.04      ; RAINY: clipped cyan at least this share (its orb 0.07..0.23)
    static RowSpan := 0.5        ; the widest row spans this share of the glow (a slanted beam: less)
    static LitMax := 0.3         ; beside it at most this share clipped at all (a pale lit wall, snow)
    static RedWarm := 0.1        ; HELL: orange / yellow at most this share (a red lamp's core)
    static RedFill := 0.6        ; HELL: glow px at most this share of the box (the orb's dark
                                 ; pentagram; a red lit block is solid)
    static SkyG := 242           ; sky blue: blue clipped, green at most this
    static GapPx := 8            ; dark px bridged inside one run
    static SlackPx := 12         ; runs in consecutive rows this close are one blob
    static MergePx := 24
    static StripCover := 0.4
    static RMin := 6
    static RMax := 120
    static MinAspect := 0.4
    static MaxAspect := 2.5
    static FlatAspect := 2.1     ; wider than this for its height and under FlatRows rows: a flat strip
    static FlatRows := 8
    static MinRows := 4          ; rows a glow spans (RowStep apart: ~32 px high)
    static MintB := 195
    static MintBR := 70
    static SalmonHue := 18       ; red-clipped under this hue (deg): portal / lamp light
    static PalShare := 0.5       ; the biome's colours: this share of all glow px
    static DeepR := 120          ; NORMAL / WINDY: a deep cyan / mint px has red under this ...
    static DeepShare := 0.25     ; ... and they are this share of the coloured px (an orb's glow
                                 ; fades to deep cyan; sky between leaves, fog-tinted mint tree
                                 ; tops and palm leaves stay pale: red 120..200)
    static CyanShare := 0.12     ; NORMAL / WINDY: clipped cyan (g and b) this share of the
                                 ; coloured px (fog-tinted mint tree tops have none)
    ; NORMAL / WINDY far orb by day in the fog: a small white core (FarWhite px
    ; or more, FarCore..1 of the coloured) in a blue / sky blue rim (FarBlue
    ; of the coloured; FarRim blue or cyan, some cyan) on both sides of the
    ; white in its widest white row, FarRows..FarRowsMax rows (white text,
    ; walls: mostly white; a cloud in the sky between branches: white at an
    ; edge; sky through a dark tree: little white)
    static FarWhite := 2
    static FarCore := 0.15
    static FarBlue := 0.4
    static FarRim := 0.8
    static FarRows := 3
    static FarRowsMax := 6
    static PinkShare := 0.3      ; no biome: pink at most this share of the coloured px
    static SnowWhite := 0.4      ; SNOWY: white core >= this share
    static SnowRim := 0.7        ; SNOWY: blue / cyan >= this share of the coloured px
    static SnowRimAll := 0.08    ;        and of all glow px
    static SnowFill := 0.3       ; SNOWY: glow px >= this share of the box (a disc, not a beam / text)
    static MixRows := 0.5        ; SNOWY / LOST FOREST: rows with white and rim side by side, this
                                 ; share of its rows (an orb's core sits in its rim; a lit shop sign
                                 ; over its blue inside, sky over branches: white rows, rim rows apart)
    static GreenWhite := 3       ; LOST FOREST: white core px at least (its fog-lit foliage clips
                                 ; deep green / mint with no white)
    static SidePx := [8, 32]     ; beside the glow, this far out of its box ...
    static SideMax := 0.06       ; ... at most this share is glow (a glow stands out)
    static SideMaxSand := 0.1    ; SAND STORM: its glowing yellow minions stand close beside it
    static Ring2Max := 0.4       ; 2 rows over / under it: at most this share glow
    ; a disc (see A DISC)
    static DiscSand := 60        ; SAND STORM tint: red over blue at least (fog 30..45, the orb 70..105)
    static DiscRain := 45        ; RAINY tint: blue over red at least (night fog 15..30, the orb 55..200)
    static DiscBlue := 20        ; RAINY: blue over green at least (its teal floor: none)
    static DiscB := 80           ; RAINY: blue at least
    static DiscRed := 190        ; SAND STORM: red at least (wood, dark blocks)
    static DiscHue := 40         ; SAND STORM: hue under this (deg; the yellow minions 57)
    static DiscAspect := 1.38    ; wide for its height, and the other way round
    static DiscFill := 0.7       ; the orbs 0.73..0.99 (washed sand 0.85), all else under
    static DiscOut := 0.15       ; the ring (1.2 .. 1.5 radii) tinted at most (the orbs <= 0.07)
    static DiscCorner := 0.3     ; its box out of the circle tinted at most (a block: most)
    static DiscContrast := 25    ; mean tint over the ring's (washed sand 35, far RAINY 43)
    static DiscRim := 8          ; SAND STORM: rim at most this darker than its core
    ; SAND STORM: a glow is hollow (see HOLLOW)
    static HollowCore := 0.55    ; its core glows at most this share (orbs 0.00..0.48; lamps, lit
                                 ; doors, studs, boards 0.61..1.00)
    static HollowDark := 0.12    ; and this share of its core is dark (orbs 0.17..1.00; a lit door
    static HollowDarkMax := 225  ; frame, a board's edge 0.00..0.04): brightest channel under this
    static Player := {x1: 1120, x2: 1300, y1: 560, y2: 1100}
    ; the character's white (hair, pet): centred x 1120..1440 or, in shift
    ; lock, 960..1300 (live 2026-11-03); a mostly white glow there is it
    static PlayerWhite := {x1: 940, x2: 1440, share: 0.6}

    ; top: the first row to scan and the sky's line (the fight camera looks
    ; down: the horizon sits near FightTop, a far orb at y ~150, never in
    ; Area, L22 SAND STORM 17:11:25)
    static Scan(grab, biome := "", top := "") {
        a := OrbBeacon.Area, st := OrbBeacon.Stride
        ys := []
        y := top != "" ? top : a.y1
        while (y <= a.y2)
            ys.Push(y), y += OrbBeacon.RowStep
        return OrbBeacon.Find(grab(a.x1, a.x2, ys, st), ys, a.x1, st, biome, top != "" ? top : OrbBeacon.SkyY)
    }

    ; c -> 0 no glow, 1 white, else its colour (a coloured glow pixel):
    ;   2 C cyan (g and b clipped)    3 B blue (b clipped over g, r <= g)
    ;   4 M mint (g clipped, b >= MintB, b - r >= MintBR: a cyan orb by day)
    ;   5 G green (g clipped, else)   6 Y yellow (r and g clipped)
    ;   7 O orange (r clipped, hue SalmonHue..)
    ;   8 P pink / violet / salmon (r clipped, b over g or hue under
    ;     SalmonHue; b clipped with r over g): portal light, beams, never an orb
    ;   9 B and sky blue (blue at the top, green <= SkyG, red well under green)
    ;  11 R pure red (red: HELL only; r clipped, g and b <= RedOrbGB)
    ; (blob counts: 10 deep cyan / mint, 12 deep orange: _DeepOrange)
    static Kind(c, red := false) {
        r := (c >> 16) & 0xFF, g := (c >> 8) & 0xFF, b := c & 0xFF
        mx := Max(r, g, b), mn := Min(r, g, b)
        if (mx < OrbBeacon.MinBright)
            return 0
        if (mn >= OrbBeacon.WhiteMin)
            return 1
        if (r = mx && g < OrbBeacon.RedG)
            return (red && g <= OrbBeacon.RedOrbGB && b <= OrbBeacon.RedOrbGB) ? 11 : 0
        if (mx - mn < OrbBeacon.MinSat)
            return 0
        if (b = mx && g <= OrbBeacon.SkyG && b - g >= 8 && r < g - 40)
            return 9
        lo := OrbBeacon.MinBright
        if (g >= lo && b >= lo)
            return 2
        if (b >= lo && b > g)
            return r > g ? 8 : 3
        if (r >= lo && g >= lo)
            return 6
        if (g >= lo)
            return (b >= OrbBeacon.MintB && b - r >= OrbBeacon.MintBR) ? 4 : 5
        ; red at the top: hue 60 * (g - b) / (r - b)
        return (b > g || (g - b) * 60 < OrbBeacon.SalmonHue * (r - b)) ? 8 : 7
    }

    ; the biome's orb colours (Kind codes): the share of a glow's pixels
    ; they must make up
    static Palette(biome) {
        switch biome {
            case "NORMAL", "WINDY":
                return [2, 4]                 ; cyan, mint by day
            case "SAND STORM":
                return [6, 7]                 ; orange, yellow
            case "HELL":
                return [11]                   ; pure red (the Flame Orb)
            case "LOST FOREST":
                return [4, 5]                 ; green
            case "SNOWY":
                return [2, 3, 9]              ; white core, blue / cyan rim
            case "RAINY":
                return [3, 9, 2]              ; sky blue / blue rim (the Raincloud Orb)
        }
        return ""
    }

    static Find(rows, ys, x1, stride, biome := "", skyY := 360) {
        n := rows.Length
        if (n = 0)
            return []
        step := n > 1 ? ys[2] - ys[1] : OrbBeacon.RowStep
        red := biome = "HELL"   ; HELL's orb is clipped red (its red light is no glow elsewhere)
        lo := OrbBeacon.MinBright
        gap := OrbBeacon.GapPx // stride
        maxLen := 2 * OrbBeacon.RMax
        ; 1. runs of glow pixels per row
        runs := [], first := [], last := []
        Loop n {
            i := A_Index
            row := rows[i]
            first.Push(runs.Length + 1)
            len := row.Length
            j := 1
            while (j <= len) {
                c := row[j]
                ; cheap reject: no channel >= MinBright
                if ((c >> 16) < lo && ((c >> 8) & 0xFF) < lo && (c & 0xFF) < lo) {
                    j++
                    continue
                }
                k := OrbBeacon.Kind(c, red)
                if !k {
                    j++
                    continue
                }
                s := j, e := j, cnt := [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
                while (j <= len) {
                    k := OrbBeacon.Kind(row[j], red)
                    if k {
                        e := j
                        cnt[k]++
                        if ((k = 2 || k = 4) && (row[j] >> 16) < OrbBeacon.DeepR)
                            cnt[10]++
                        else if (k = 7 && OrbBeacon._DeepOrange(row[j]))
                            cnt[12]++
                    } else if (j - e > gap)
                        break
                    j++
                }
                if ((e - s + 1) * stride <= maxLen)
                    runs.Push({i: i, a: x1 + (s - 1) * stride, b: x1 + (e - 1) * stride, cnt: cnt, p: runs.Length + 1, drop: false})
            }
            last.Push(runs.Length)
        }
        ; 2. long runs with nothing under / over them: bars, strips
        for r in runs {
            L := r.b - r.a
            if (L < 3 * step)
                continue
            cov := 0
            for d in [-1, 1] {
                ii := r.i + d
                if (ii < 1 || ii > n)
                    continue
                Loop last[ii] - first[ii] + 1 {
                    q := runs[first[ii] + A_Index - 1]
                    cov := Max(cov, Min(r.b, q.b) - Max(r.a, q.a))
                }
            }
            if (cov < OrbBeacon.StripCover * L)
                r.drop := true
        }
        ; 3. blobs: runs touching from row to row
        sl := OrbBeacon.SlackPx
        for idx, r in runs {
            if (r.drop || r.i = 1)
                continue
            Loop last[r.i - 1] - first[r.i - 1] + 1 {
                q := runs[first[r.i - 1] + A_Index - 1]
                if (!q.drop && q.a - sl <= r.b && r.a <= q.b + sl)
                    OrbBeacon._Union(runs, idx, first[r.i - 1] + A_Index - 1)
            }
        }
        byRoot := Map(), blobs := []
        for idx, r in runs {
            if r.drop
                continue
            root := OrbBeacon._Root(runs, idx)
            if !byRoot.Has(root) {
                byRoot[root] := {a: r.a, b: r.b, i1: r.i, i2: r.i, cnt: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]}
                blobs.Push(byRoot[root])
            }
            m := byRoot[root]
            m.a := Min(m.a, r.a), m.b := Max(m.b, r.b)
            m.i1 := Min(m.i1, r.i), m.i2 := Max(m.i2, r.i)
            Loop 12
                m.cnt[A_Index] += r.cnt[A_Index]
        }
        ; 4. close blobs merge while round (NORMAL / WINDY: never a pale mint
        ; blob, a tree top in the fog, with a white one, a far orb beside it)
        mp := OrbBeacon.MergePx
        cyanPal := !IsObject(OrbBeacon.Palette(biome)) || OrbBeacon.Palette(biome)[1] = 2 && biome != "SNOWY"
        merged := true
        while merged {
            merged := false
            for p, u in blobs {
                for q, v in blobs {
                    if (q <= p)
                        continue
                    if (u.a - mp > v.b || v.a > u.b + mp || u.i1 - 1 > v.i2 || v.i1 > u.i2 + 1)
                        continue
                    if (cyanPal && (OrbBeacon._PaleMint(u) && v.cnt[1] || OrbBeacon._PaleMint(v) && u.cnt[1]))
                        continue
                    xa := Min(u.a, v.a), xb := Max(u.b, v.b), i1 := Min(u.i1, v.i1), i2 := Max(u.i2, v.i2)
                    w := xb - xa + stride, h := (i2 - i1 + 1) * step
                    if (w > maxLen || h > maxLen || w < 0.5 * h || w > 2 * h)
                        continue
                    cnt := []
                    Loop 12
                        cnt.Push(u.cnt[A_Index] + v.cnt[A_Index])
                    blobs[p] := {a: xa, b: xb, i1: i1, i2: i2, cnt: cnt}
                    blobs.RemoveAt(q)
                    merged := true
                    break 2
                }
            }
        }
        ; 5. the glow tests
        out := []
        xEnd := x1 + (rows[1].Length - 1) * stride
        pl := OrbBeacon.Player, pw := OrbBeacon.PlayerWhite
        pal := OrbBeacon.Palette(biome)
        sky := biome != "RAINY"   ; no clear blue sky in the rain (its orb is sky blue)
        for m in blobs {
            w := m.b - m.a + stride
            nr := m.i2 - m.i1 + 1
            h := nr * step
            cx := (m.a + m.b) // 2
            cy := (ys[m.i1] + ys[m.i2]) // 2
            m.nw := m.cnt[1], m.ns := m.cnt[9], m.nc := 0
            Loop 8
                m.nc += m.cnt[A_Index + 1]
            m.nc += m.cnt[11]
            far := cyanPal && OrbBeacon._FarOrb(m, rows, x1, stride, w, nr)
            if (m.nc < 2 || nr < (far ? OrbBeacon.FarRows : OrbBeacon.MinRows))
                continue
            if (w < 2 * OrbBeacon.RMin || w > maxLen || h > maxLen + step)
                continue
            if (w < OrbBeacon.MinAspect * h || w > OrbBeacon.MaxAspect * h)
                continue
            if (ys[m.i1] < skyY + OrbBeacon.SkyRows * step)
                continue
            if (sky && !far && m.ns * 2 > m.nc && m.nw * 4 < m.nc)
                continue
            if (cy >= pl.y1 && cy <= pl.y2 && (cx >= pl.x1 && cx <= pl.x2
                || cx >= pw.x1 && cx <= pw.x2 && m.nw >= pw.share * (m.nw + m.nc)))
                continue
            if (m.a <= x1 || m.b >= xEnd)
                continue
            if (w > OrbBeacon.FlatAspect * h && nr < OrbBeacon.FlatRows)
                continue
            if (!far && !OrbBeacon._Colours(m, pal, biome = "SNOWY", w, nr, stride))
                continue
            if ((biome = "SNOWY" || biome = "LOST FOREST")
                && OrbBeacon._MixRows(m, rows, x1, stride, pal) < OrbBeacon.MixRows * nr)
                continue
            if (OrbBeacon._RowSpan(m, rows, x1, stride, red) < OrbBeacon.RowSpan * w)
                continue
            if !OrbBeacon._StandsOut(m, rows, x1, stride, red, biome = "SAND STORM" ? OrbBeacon.SideMaxSand : OrbBeacon.SideMax)
                continue
            if (biome = "SAND STORM" && !OrbBeacon._Hollow(m, rows, ys, x1, stride))
                continue
            out.Push({x: cx, y: cy, r: Max(w, h) // 2})
        }
        if (biome = "SAND STORM" || biome = "RAINY")
            for d in OrbBeacon._Discs(rows, ys, x1, stride, step, skyY, biome = "SAND STORM") {
                for g in out
                    if (Abs(g.x - d.x) <= g.r + d.r && Abs(g.y - d.y) <= g.r + d.r)
                        continue 2
                out.Push(d)
            }
        return out
    }

    ; c's tint (see A DISC): red over blue, or blue over red
    static _Tint(c, sand) => sand ? ((c >> 16) & 0xFF) - (c & 0xFF) : (c & 0xFF) - ((c >> 16) & 0xFF)

    ; c is the orb's colour in the fog / the rain
    static _Tinted(c, sand) {
        r := (c >> 16) & 0xFF, g := (c >> 8) & 0xFF, b := c & 0xFF
        if sand
            return r - b >= OrbBeacon.DiscSand && r >= OrbBeacon.DiscRed
                && (g - b) * 60 < OrbBeacon.DiscHue * (r - b) && (g - b) * 60 >= OrbBeacon.SalmonHue * (r - b)
        return b - r >= OrbBeacon.DiscRain && b - g >= OrbBeacon.DiscBlue && b >= OrbBeacon.DiscB
    }

    ; The discs in rows (see A DISC) -> Array of {x, y, r}
    static _Discs(rows, ys, x1, stride, step, skyY, sand) {
        lo := sand ? OrbBeacon.DiscSand : OrbBeacon.DiscRain
        gap := OrbBeacon.GapPx // stride, sl := OrbBeacon.SlackPx
        runs := [], first := [], last := []
        Loop rows.Length {
            i := A_Index
            row := rows[i]
            first.Push(runs.Length + 1)
            len := row.Length
            j := 1
            while (j <= len) {
                ; cheap reject: the tint under its least
                if (OrbBeacon._Tint(row[j], sand) < lo || !OrbBeacon._Tinted(row[j], sand)) {
                    j++
                    continue
                }
                s := j, e := j
                while (j <= len) {
                    if OrbBeacon._Tinted(row[j], sand)
                        e := j
                    else if (j - e > gap)
                        break
                    j++
                }
                runs.Push({i: i, a: x1 + (s - 1) * stride, b: x1 + (e - 1) * stride, p: runs.Length + 1})
            }
            last.Push(runs.Length)
            if (i = 1)
                continue
            Loop last[i] - first[i] + 1 {
                k := first[i] + A_Index - 1
                r := runs[k]
                Loop last[i - 1] - first[i - 1] + 1 {
                    q := runs[first[i - 1] + A_Index - 1]
                    if (q.a - sl <= r.b && r.a <= q.b + sl)
                        OrbBeacon._Union(runs, k, first[i - 1] + A_Index - 1)
                }
            }
        }
        byRoot := Map()
        for idx, r in runs {
            root := OrbBeacon._Root(runs, idx)
            if !byRoot.Has(root)
                byRoot[root] := {a: r.a, b: r.b, i1: r.i, i2: r.i}
            m := byRoot[root]
            m.a := Min(m.a, r.a), m.b := Max(m.b, r.b), m.i1 := Min(m.i1, r.i), m.i2 := Max(m.i2, r.i)
        }
        out := []
        xEnd := x1 + (rows[1].Length - 1) * stride
        pl := OrbBeacon.Player
        for root, m in byRoot {
            w := m.b - m.a + stride, nr := m.i2 - m.i1 + 1, h := nr * step
            rad := Max(w, h) / 2
            if (nr < OrbBeacon.MinRows || rad > OrbBeacon.RMax + 2 * step || rad < 2 * step)
                continue
            if (w > OrbBeacon.DiscAspect * h || h > OrbBeacon.DiscAspect * w)
                continue
            if (ys[m.i1] < skyY + OrbBeacon.SkyRows * step || m.a <= x1 || m.b >= xEnd)
                continue
            cx := (m.a + m.b) // 2, cy := (ys[m.i1] + ys[m.i2]) // 2
            if (cy >= pl.y1 && cy <= pl.y2 && cx >= pl.x1 && cx <= pl.x2)
                continue
            if OrbBeacon._IsDisc(rows, ys, x1, stride, m, cx, cy, rad, sand)
                out.Push({x: cx, y: cy, r: Round(rad)})
        }
        return out
    }

    ; the blob round (cx, cy) of radius rad is tinted as a disc is (see A DISC)
    static _IsDisc(rows, ys, x1, stride, m, cx, cy, rad, sand) {
        nIn := 0, tIn := 0, sumIn := 0        ; the circle (0.9 radii)
        nOut := 0, tOut := 0, sumOut := 0     ; the ring (1.2 .. 1.5)
        nBox := 0, tBox := 0                  ; the box's corners (over 1.1)
        nRim := 0, sumRim := 0                ; the rim (1 .. 1.25), by brightness
        nCore := 0, sumCore := 0              ; the core (0.7)
        for i, y in ys {
            dy := y - cy
            if (Abs(dy) > 1.5 * rad)
                continue
            row := rows[i]
            j := Max(1, Ceil((cx - 1.5 * rad - x1) / stride) + 1)
            jEnd := Min(row.Length, Floor((cx + 1.5 * rad - x1) / stride) + 1)
            while (j <= jEnd) {
                c := row[j]
                x := x1 + (j - 1) * stride
                d := Sqrt((x - cx) ** 2 + dy ** 2) / rad
                j++
                if (d > 1.5)
                    continue
                t := OrbBeacon._Tinted(c, sand) ? 1 : 0
                if (d <= 0.9)
                    nIn++, tIn += t, sumIn += OrbBeacon._Tint(c, sand)
                else if (d >= 1.2)
                    nOut++, tOut += t, sumOut += OrbBeacon._Tint(c, sand)
                if (d > 1.1 && x >= m.a && x <= m.b && y >= ys[m.i1] && y <= ys[m.i2])
                    nBox++, tBox += t
                if (sand) {
                    br := Max((c >> 16) & 0xFF, (c >> 8) & 0xFF, c & 0xFF)
                    if (d <= 0.7)
                        nCore++, sumCore += br
                    else if (d >= 1 && d <= 1.25)
                        nRim++, sumRim += br
                }
            }
        }
        if (!nIn || !nOut || tIn < OrbBeacon.DiscFill * nIn || tOut > OrbBeacon.DiscOut * nOut)
            return false
        if (tBox > OrbBeacon.DiscCorner * nBox)
            return false
        if (sumIn / nIn - sumOut / nOut < OrbBeacon.DiscContrast)
            return false
        return !sand || (nRim && nCore && sumRim / nRim - sumCore / nCore >= -OrbBeacon.DiscRim)
    }

    ; blob m in the biome's colours (pal: Palette; "" = a biome without one:
    ; little pink and the colours of any biome that has one)
    static _Colours(m, pal, snowy, w, nr, stride) {
        n := m.nw + m.nc
        if !IsObject(pal) {
            if (m.cnt[8] > OrbBeacon.PinkShare * m.nc)
                return false
            for b in ["NORMAL", "SNOWY", "SAND STORM", "LOST FOREST"]
                if OrbBeacon._Colours(m, OrbBeacon.Palette(b), b = "SNOWY", w, nr, stride)
                    return true
            return false
        }
        p := 0
        for k in pal
            p += m.cnt[k]
        if snowy  ; a white core with a blue / cyan rim, a filled disc
            return m.nw >= OrbBeacon.SnowWhite * n && p >= OrbBeacon.SnowRim * m.nc
                && p >= OrbBeacon.SnowRimAll * n && n >= OrbBeacon.SnowFill * (w / stride) * nr
        if (pal[1] = 3)   ; RAINY: sky blue with some clipped cyan (rain sky, fog: none)
            return p >= OrbBeacon.PalShare * n && m.cnt[2] >= OrbBeacon.RainCyan * m.nc
        if (pal[1] = 6)   ; SAND STORM: deep orange (a lit board, window or text: yellower)
            return p >= OrbBeacon.PalShare * n && m.cnt[12] >= OrbBeacon.OrangeDeep * (m.cnt[6] + m.cnt[7])
        if (pal[1] = 4)   ; LOST FOREST: green / mint round a white core (foliage: no white)
            return p >= OrbBeacon.PalShare * m.nc && m.nw >= OrbBeacon.GreenWhite
                && m.nw >= OrbBeacon.FarCore * n && n >= OrbBeacon.SnowFill * (w / stride) * nr
        if (pal[1] = 11)  ; HELL: red, no lamp's orange core, hollow (a lit block is solid)
            return p >= OrbBeacon.PalShare * n && m.cnt[6] + m.cnt[7] <= OrbBeacon.RedWarm * m.nc
                && n <= OrbBeacon.RedFill * (w / stride) * nr
        ; NORMAL / WINDY: cyan / mint fading to deep cyan, with clipped cyan
        return p >= OrbBeacon.PalShare * n && (pal[1] != 2
            || m.cnt[2] >= OrbBeacon.CyanShare * m.nc && m.cnt[10] >= OrbBeacon.DeepShare * m.nc
            && m.cnt[6] + m.cnt[7] <= OrbBeacon.CyanWarm * m.nc)
    }

    ; r clipped, hue under DeepHue (deg): the orange of the SAND STORM orb
    static _DeepOrange(c) {
        r := (c >> 16) & 0xFF, g := (c >> 8) & 0xFF, b := c & 0xFF
        return (g - b) * 60 < OrbBeacon.DeepHue * (r - b)
    }

    ; blob m's widest row (first to last glow px in its box) in px: an orb's
    ; middle row spans most of it; a thin slanted beam's rows only a bit
    static _RowSpan(m, rows, x1, stride, red) {
        j1 := (m.a - x1) // stride + 1, j2 := (m.b - x1) // stride + 1
        best := 0
        Loop m.i2 - m.i1 + 1 {
            row := rows[m.i1 + A_Index - 1]
            fa := 0, fb := 0
            j := j1
            while (j <= j2) {
                if OrbBeacon.Kind(row[j], red)
                    fa := fa ? fa : j, fb := j
                j++
            }
            if fa
                best := Max(best, (fb - fa + 1) * stride)
        }
        return best
    }

    ; NORMAL / WINDY far orb by day (see FarWhite): a small white core in a
    ; blue rim, a filled disc
    static _FarOrb(m, rows, x1, stride, w, nr) {
        nw := m.nw, nc := m.nc
        blue := m.cnt[3] + m.cnt[9]
        if !(nr >= OrbBeacon.FarRows && nr <= OrbBeacon.FarRowsMax && nw >= OrbBeacon.FarWhite
            && nw >= OrbBeacon.FarCore * nc && nw <= nc && m.cnt[2] > 0
            && blue >= OrbBeacon.FarBlue * nc && blue + m.cnt[2] >= OrbBeacon.FarRim * nc
            && nw + nc >= OrbBeacon.SnowFill * (w / stride) * nr)
            return false
        ; the widest white row: rim (blue / cyan) left and right of its white
        j1 := (m.a - x1) // stride + 1, j2 := (m.b - x1) // stride + 1
        best := 0, ok := false
        Loop nr {
            row := rows[m.i1 + A_Index - 1]
            wa := 0, wb := 0, nwr := 0
            j := j1
            while (j <= j2) {
                if (OrbBeacon.Kind(row[j]) = 1)
                    wa := wa ? wa : j, wb := j, nwr++
                j++
            }
            if (nwr <= best)
                continue
            best := nwr, l := false, r := false
            j := j1
            while (j <= j2) {
                k := OrbBeacon.Kind(row[j])
                if (k = 2 || k = 3 || k = 9) {
                    if (j < wa)
                        l := true
                    else if (j > wb)
                        r := true
                }
                j++
            }
            ok := l && r
        }
        return ok
    }

    ; rows of blob m with a white px and a rim px (pal's colours) both in
    ; its box: an orb's white core sits inside its rim in most of its rows
    static _MixRows(m, rows, x1, stride, pal) {
        j1 := (m.a - x1) // stride + 1, j2 := (m.b - x1) // stride + 1
        mix := 0
        Loop m.i2 - m.i1 + 1 {
            row := rows[m.i1 + A_Index - 1]
            w := false, rim := false
            j := j1
            while (j <= j2 && !(w && rim)) {
                k := OrbBeacon.Kind(row[j])
                if (k = 1)
                    w := true
                else if k
                    for q in pal
                        if (k = q) {
                            rim := true
                            break
                        }
                j++
            }
            mix += (w && rim) ? 1 : 0
        }
        return mix
    }

    ; SAND STORM: blob m is hollow (see HOLLOW): its core (the middle half
    ; of its width, the rows in the middle half of its height) glows at most
    ; HollowCore and HollowDark of it is dark (brightest channel under
    ; HollowDarkMax)
    static _Hollow(m, rows, ys, x1, stride) {
        cx := (m.a + m.b) / 2, cy := (ys[m.i1] + ys[m.i2]) / 2
        w := m.b - m.a + stride, h := ys[m.i2] - ys[m.i1]
        n := 0, hit := 0, dark := 0
        Loop m.i2 - m.i1 + 1 {
            i := m.i1 + A_Index - 1
            if (Abs(ys[i] - cy) > h / 4 + 0.5)
                continue
            row := rows[i]
            j := Ceil((cx - w / 4 - x1) / stride) + 1, jEnd := Floor((cx + w / 4 - x1) / stride) + 1
            while (j <= jEnd) {
                c := row[j++]
                n++
                if OrbBeacon.Kind(c)
                    hit++
                else if (Max((c >> 16) & 0xFF, (c >> 8) & 0xFF, c & 0xFF) < OrbBeacon.HollowDarkMax)
                    dark++
            }
        }
        return n && hit <= OrbBeacon.HollowCore * n && dark >= OrbBeacon.HollowDark * n
    }

    ; a pale mint / green blob: no white, no clipped cyan (a tree top in fog)
    static _PaleMint(m) => !m.cnt[1] && !m.cnt[2] && m.cnt[4] + m.cnt[5] > 0

    ; blob m stands out of its surroundings: little glow beside it (SidePx
    ; out, its rows) and 2 rows over / under it (a lit sky, snow, a field
    ; or a wall of text glows all round)
    static _StandsOut(m, rows, x1, stride, red := false, sideMax := 0.06) {
        g := (i, x) => (i >= 1 && i <= rows.Length && x >= x1 && (j := (x - x1) // stride + 1) <= rows[i].Length
            && OrbBeacon.Kind(rows[i][j], red)) ? 1 : 0
        ; lit: any clipped channel (a pale lit wall, snow in daylight)
        lo := OrbBeacon.MinBright
        lit := (i, x) => (i >= 1 && i <= rows.Length && x >= x1 && (j := (x - x1) // stride + 1) <= rows[i].Length
            && ((c := rows[i][j]) >> 16 >= lo || ((c >> 8) & 0xFF) >= lo || (c & 0xFF) >= lo)) ? 1 : 0
        d1 := OrbBeacon.SidePx[1], d2 := OrbBeacon.SidePx[2]
        hit := 0, all := 0, nlit := 0
        Loop m.i2 - m.i1 + 1 {
            i := m.i1 + A_Index - 1
            x := m.a - d2
            while (x <= m.a - d1)
                hit += g(i, x), nlit += lit(i, x), all++, x += stride
            x := m.b + d1
            while (x <= m.b + d2)
                hit += g(i, x), nlit += lit(i, x), all++, x += stride
        }
        if (hit > sideMax * all || nlit > OrbBeacon.LitMax * all)
            return false
        hit := 0, all := 0
        x := m.a
        while (x <= m.b) {
            hit += g(m.i1 - 2, x) + g(m.i2 + 2, x), all += 2
            x += stride
        }
        return hit <= OrbBeacon.Ring2Max * all
    }

    static Pick(glows) {
        best := ""
        for g in glows
            if (!IsObject(best) || g.r > best.r || (g.r = best.r && g.y > best.y))
                best := g
        return best
    }

    static _Root(runs, i) {
        while (runs[i].p != i) {
            runs[i].p := runs[runs[i].p].p
            i := runs[i].p
        }
        return i
    }

    static _Union(runs, i, j) {
        a := OrbBeacon._Root(runs, i), b := OrbBeacon._Root(runs, j)
        if (a != b)
            runs[Max(a, b)].p := Min(a, b)
    }
}
