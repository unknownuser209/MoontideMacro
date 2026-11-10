#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\TaskEnv.ahk
#Include %A_LineFile%\..\FishLogic.ahk
#Include %A_LineFile%\..\Obby.ahk
#Include %A_LineFile%\..\OrbBeacon.ahk
#Include %A_LineFile%\..\Sinister.ahk
#Include %A_LineFile%\..\..\LogWatch.ahk
; ---------------------------------------------------------------------------
; MinionsTask: fights the Biome Orbs and Minions of a weather biome
; (2026 Halloween update) with a combat aura (and puts the user's aura back
; after when Minions.putBack is 1).
;
;   t := MinionsTask(deps)  deps as TaskEnv plus:
;     aura   callable aura() -> {known, name} (as ObbyTask; App: LogWatch)
;     grab   callable grab(x1, x2, ys, stride) -> rows (StripGrab.Rows shape)
;     scan   callable scan() -> bars, in place of grab + FindBars (tests)
;     beacon callable beacon() -> glows, in place of OrbBeacon.Scan(grab)
;            (tests)
;     biome  callable biome() -> the biome name now (App: state.biome after
;            a log poll); "" / no dep = unknown, never ends a hunt
;     toast  callable toast() -> "orb" / "minion" / "", in place of
;            Toast(grab) (tests)
;     bossbar callable bossbar() -> true when the boss bar UI is up, in
;            place of BossBar(grab) (tests)
;     ghost  callable ghost() -> true in a ghost server (App: state.ghost or
;            the last join "other"); none = unknown = no boss message
;     sinister  SinisterReport-like (tests), in place of the one made from
;            webhook (PostText / EditText), cfg, ghost and log
;   t.name = "minions", t.priority = 6
;   t.CanRun(state) -> cfg Minions.enabled (default 0) AND state.biome is a
;                      normal biome (Biomes: not rare, not event) AND this biome was not hunted
;                      yet AND the aura storage is calibrated AND (put back
;                      on only) the aura on now is known (to put it back).
;                      GRAVEYARD (BossBiome) too when Minions.boss (default
;                      1), once per GRAVEYARD start (no RehuntMs): boss mode.
;                      NORMAL (IdleBiome) only when Minions.normal (default
;                      0), else only when the set-up is due (_PrepDue).
;   t.Run(ctx)      -> enemies down (minion toasts seen, and the orb).
;
; NORMAL (L44-L51: 77 of 154 hunts, no orb on any frame, more than half of
; the falls): not hunted. The macro idles there at spawn, the combat aura on,
; so an orb biome starts with no swap and no respawn ("still at spawn"). That
; needs a set-up now and then, always in NORMAL, never at an orb biome's
; start: the aura off (the log names another), no closing respawn to start
; from, or one PrepAfterMs old (it goes stale at SpawnKeepMs) -> Run does the
; aura swap, the menus, the closing respawn, and nothing else: no walk, no
; look. Tried at most once per RehuntMs. No set-up with Minions.putBack.
;
; BOSS MODE (2026 Halloween update, the user): when GRAVEYARD starts an
; Elite Minion boss ("Sinister S.", ~2000 HP, many special attacks) spawns
; ~5% of the time and stays up to 10 min (the biome timer paused meanwhile);
; everyone in the fight gets its rewards. NOT SEEN YET: its bar is GUESSED to
; look like the orbs' (wider; the same Scan finds it) and / or a big boss bar
; UI at the top centre (BossBar). Run: a respawn, then BossLook (BossLookMs
; of full turns) for any confirmed bar or that UI BEFORE the aura swap (the
; storage is ~15 s of clicks; the combat aura already on: no swap at all);
; nothing -> "minions: no boss in GRAVEYARD", a closing respawn as after a
; hunt (L49 18:18:57: none, the next hunt paid one), done.
; Seen -> the swap, a respawn and the fight below, with
; BossMaxSec in place of Minions.maxSec, BossQuietMs without a bar before it
; gives up (the boss bar UI up keeps it going), the UI bar never a target
; (NotBossUi) and boss=1 in the stats line.
; Discord (SinisterReport, lib\tasks\Sinister.ahk): boss in sight -> ONE
; "<private server link> sinister s natrual spawn" on the "sinister" event
; per GRAVEYARD start (never in a ghost server, never a ping); the fight's
; ticks feed it the plate's fill and sight, deaths and the toast; killed
; (GUESSED, see there) -> that message edited to "<link> dead". The biome
; changing first = a despawn: no edit.
;
; LIVE FACTS (2026-10-31, Eden): orbs and minions stand near spawn in every
; normal biome (seen: RAINY, WINDY, SNOWY, SAND STORM) and despawn when the
; biome changes. 2026-11-02: they come ~35-40 s after the biome starts (or
; not at all), and a normal biome lasts only ~1-3 min.
; A plain click does nothing to them: only an aura's skills hurt them. Eden's
; skills: T Taunt, F Darkmatter Barrage, E Cut Into Nothing, Q Impale,
; R Deadeye, V Voidrush. Each orb / minion has a thin health bar above it:
; ~5 px, a vertical gradient from yellow (255,255,150 in fog; 249,239,28
; clear) to orange (255,184,157 / 243,123,13), "300 / 300" written on it.
; Left / Right arrows turn the camera (~3.6 px per ms at 2560 wide), a full
; circle in 3000 ms (FullTurnMs).
;
; PASS
;   1. Minions.aura (default Eden) on, through ObbyTask's checked swap (never
;      anything but Equip / Unequip).
;   2. ResetToSpawn, shift lock on (Minions.shiftLock; off again whenever the
;      hunt ends and around a storage swap, else a w tap of AimTapMs before
;      each skill), the fight camera (_FightCamera). Then the fight, built
;      from three hand fights that all killed the orb (clips 2026-11-03, Eden
;      578 HP/min; the macro's kiting and aiming before it: 30-45 HP/min):
;      FIND. Scan for bars (Scan: a bar counts once in two scans in a row
;      about in one place, Confirmed). None -> the orb's glow (OrbBeacon: a
;      far orb glows from spawn while its bar is too small to read) turned
;      to and walked to; after a death the moves since the respawn replayed
;      from spawn (_Note, _Replay); a walk back to the bearing the fight was
;      at (ReturnWalks; no trail, or a look around that found nothing); a target
;      seen PursueMs ago or less and never reached: after it again
;      (PursueStyles); else a look around, ScanTurnMs at a time: 6 looks a
;      circle. Minions.spots on (default off, their bearings are false, see
;      Spots): from spawn straight at the fixed Spots, and a bar, a glow or the
;      orbs due with a route learned to that spot (_RouteLearn, data\
;      minions_routes.json): the route replayed until a bar is near. Nothing for
;      ScanTurns turns: one respawn wait, then GiveUp (not before OrbLateMs
;      after the biome started). Every walk: not at the island's edge
;      (_EdgeGuard; on the way to a bar: EdgeBarTurnMs, no half turn away from
;      it), the view unchanged = a wall (_WalkOrSlide); no closer to a target:
;      the Escapes, the wall slide, then it is left for AvoidMs.
;      APPROACH. Bars far: the orb (else the nearest minion, View) turned to
;      and walked to until the orb's bar is BesideOrbW wide (Beside; no orb
;      in sight: a minion's BesideMinionW), short steps at the end. Minions
;      near do not stop the walk unless they block it (BlockedMs).
;      STAND. Beside it: no more steps, no side steps. The orb (else the
;      nearest minion) kept ahead within FaceTol; Locked or not, the same.
;      Minions come to the player or stand round the orb, AoE reaches them.
;      CAST. One skill at a time (MinionSkills), never mid-cast, never under
;      the Quest Board page, no E where the board's prompt reads (E is its
;      interact key). No bar: a menu looked for first (_ClearView), else a
;      flash, which means nothing: skills on BlindCastMs, then none for
;      ClearMs so the screen clears.
;      SURVIVE. Minions throw darts from beside the orb: between casts, a
;      minion seen, side steps (_Dodge), at any HP. A death (a respawn in
;      the log, the death screen; the HP low, then back up, only while the
;      log has not shown it tells respawns: _DeathSeen) ->
;      the camera again, the HP waited for at spawn (_Regen), the walk back
;      by the bearing.
;      END. The biome changing (BiomeLeft; whatever is in sight: the orb goes
;      with it; the set-up run past it, into a biome not hunted: at once), the
;      "Orb Awards" toast (Toast: behind the skill rows). No plate once the
;      screen cleared is no kill at any fill: the look goes on.
;      Bearing (_Turn): the net turn ms since the last respawn (Left -,
;      Right +; after ResetToSpawn the camera faces one way), 0 again at a
;      death; logged "bearing N ms" when a target is first seen.
;      Every FillEveryMs one "minions: fill orb=0.42 minions=0.80,0.35" (the
;      bars' fill, _Fill: digits go at low fill) for damage per minute, and
;      at the end one "minions: stats" line (Stats). A hunt that ended
;      without a toast or a biome change: first one sweep (_Sweep) round a
;      full circle -> left= / orb_left=; an orb in it is not down.
;   3. ResetToSpawn (CleanupCtx: also after a preempt). Minions.putBack 1
;      (default 0): the aura from before back too (a real halt owes it to
;      the next run, as the obby).
; ---------------------------------------------------------------------------

class MinionsTask {
    ; Orbs spawn in every biome but the rare and event ones (the user,
    ; 2026-10-31). Listed, not "anything else": a new biome may be an event.
    ; NORMAL: on the list, hunted only with Minions.normal (_NoHunt).
    static Biomes := Map("NORMAL", true, "WINDY", true, "RAINY", true, "SNOWY", true, "SAND STORM", true
        , "HELL", true, "STARFALL", true, "CORRUPTION", true, "LOST FOREST", true, "HEAVEN", true)
    static IdleBiome := "NORMAL"
    static Aura := "Eden"
    ; The skills of the auras fought by hand (clips 2026-11-03, MedalTV
    ; 170608 Eden, 170827 Equinox, 171013 Luminosity): panel: the rows top to
    ; bottom (the last row at the bottom); order: damage first (Luminosity's
    ; Q is a dash, no damage: not cast); cool: the overlay's ms; cast: press
    ; to the overlay's start, nothing else then. Eden: T Taunt +15 Charge, no
    ; damage; F Barrage ~40 to all inside, on the orb; E Cut -31 to several,
    ; mid range (the -31 once credited to Impale); Q Impale -15 to one, it
    ; mostly misses; V Voidrush needs 30 Charge, costs 25; R Deadeye -102 at
    ; rank V only (it "came during" V). Any other aura: every letter (one an
    ; aura lacks does nothing), cooldowns from its panel.
    static Keys := ["e", "r", "t", "f", "q", "v"]
    static Auras := Map(
        "eden", {panel: ["t", "f", "e", "q", "r", "v"], order: ["r", "v", "f", "e", "t", "q"]
            , cool: Map("t", 8000, "f", 10000, "e", 6000, "q", 3000, "v", 60000, "r", 40000)
            , cast: Map("t", 400, "f", 2800, "e", 1000, "q", 1000, "v", 4800, "r", 3400)},
        "equinox", {panel: ["e", "t", "r"], order: ["r", "t", "e"]
            , cool: Map("r", 20000, "t", 20000, "e", 20000)
            , cast: Map("r", 3000, "t", 5000, "e", 2500)},
        "luminosity", {panel: ["f", "t", "q", "r", "e"], order: ["f", "e", "t", "r"]
            , cool: Map("f", 25000, "t", 23000, "r", 50000, "e", 6900, "q", 1900)
            , cast: Map("f", 1000, "t", 1000, "r", 2800, "e", 1000, "q", 500)})
    static KeysFor(aura) {
        k := StrLower(Trim(String(aura)))
        return MinionsTask.Auras.Has(k) ? MinionsTask.Auras[k].order : MinionsTask.Keys
    }
    ; Points a skill needs (Eden: Voidrush 30, "You need 30 Charge to use
    ; this" at 27, clip 170608 t=12.6)
    static Costs := Map("eden", Map("v", 30))
    ; The aura's skill panel (live 2026-11-02, Eden; the layout is every
    ; aura's): one row per skill at the bottom right, SkillTops = the six
    ; row tops (fewer skills fill the lowest rows: clips 2026-11-03, Equinox
    ; 3, Luminosity 5). A row: a key box (x 2021..2060,
    ; white border, a white letter) and a name box (x 2073..2534). A skill
    ; cooling down: a lighter overlay over the name box from the left, its
    ; right edge moving left until it is gone (no timer text).
    static SkillTops := [1010, 1059, 1109, 1158, 1208, 1257]
    static PanelX1 := 2020       ; panel grab, every 2nd px from here
    static PanelX2 := 2530
    static KeyX2 := 2060         ; the key box's right border
    static NameX1 := 2073        ; the name box: the overlay's 0..1
    static NameW := 461
    static BorderStep := 40      ; the key box's right border over the world beside it (night 80)
    static LetterMin := 0.06     ; share of the key box white: a letter (live 0.15..0.28)
    static LetterMax := 0.6
    static CdStep := 35          ; overlay over the rest of its row (live +75..+90)
    ; Eden's points: a pure white fill centred on x 1280, PxPerPoint a
    ; point, bobbing (fill top y 1141..1168); the combo rank letter above it
    ; (x 1268..1292), a thin white line between (the rank's time left)
    static BarX1 := 985
    static BarX2 := 1573
    static BarY1 := 1120
    static BarY2 := 1216
    static PxPerPoint := 5.75
    static RankX1 := 1240
    static RankX2 := 1320
    static RankY1 := 1080
    static RankY2 := 1175        ; the letter (to ~1140) and its time line under it
    ; Scan area (2560x1440): above the bottom bar, right of the chat, left of
    ; the skill list. Rows RowStep apart, every Stride-th pixel (Scan: plus
    ; every row around thin strips, for far bars).
    ; y1 was 120: a point-blank minion's bar sits at the top (clip L19
    ; SNOWY 053406: 1210 px wide at y ~70)
    static Area := {x1: 560, x2: 2240, y1: 40, y2: 1100}
    static RowStep := 2
    static Stride := 2
    static MinRun := 24          ; px: shortest bar (a far minion)
    static GapPx := 16           ; px of text on the bar bridged inside one run
    static RunCover := 0.7
    static BelowCover := 0.6
    static EdgeCover := 0.2
    static PaleOver := 32        ; bar blue over the background's darkest channel: a sign (real: <= 0, sign 65)
    static AboveWarm := 0.7      ; yellow / orange 2 px over a bar's yellow at most this share (real
                                 ; <= 0.47; a brick block's bevel: orange 1.0 over its yellow lip)
    ; px: longer is not a health bar. Was 420: point-blank bars are wider
    ; (clips L19 2026-11-03: minions 290..1210 px, the orb ~610; "target
    ; lost from sight (near)" with them in the player's face)
    static MaxRun := 1500
    static BarAspect := 10       ; a bar is at least this many times wider than tall (real ~13)
    static TallLoose := 0.35     ; least warm in a tall bar's row the HP text crosses (real >= 0.40)
    static DeepOrange := 92      ; r - g of a bar's red-orange lower row (real >= 98, sand fog 104; boards' lit base brick <= 86, gold sign <= 55)
    ; Far bars (FindThin): 2..5 px high, rows 1 px apart around seeds
    static ThinMin := 20         ; px (live 2026-11-02 WINDY: minions 24..30, one half hidden 20)
    static ThinMax := 120        ; px: a far orb ~45..100
    static ThinAlone := 0.5      ; most yellow / orange 4 px above and below a seed
    static ThinPad := 5          ; rows grabbed above and below a seed
    static ThinCap := 120        ; most rows grabbed for far bars per scan
    static FlatAspect := 22      ; a bar at most this many times wider than tall (real ~13; the boards' lit base 106 x 4)
    static ThinHue := 47         ; most _OrangeHue of a far bar's orange row (real <= 44; lit shelf, sign trim ~55)
    ; HEAVEN's gold floor trim (loop L19 2026-11-03 07:23 / 07:26 / 07:27,
    ; attacked as targets: 30..62 px, a pale yellow row 255,255,~165 over
    ; one gold row ~f8bc63, white over and under it): a narrow bar (not
    ; tall) whose reddest orange row scanned is over GoldHue (trim 55..68)
    ; with GoldWhite or more (the darkest channel's median) in the scanned
    ; rows over it and under it (trim 224..255). Real bars' scanned orange
    ; row can read 48..76 too (fogged SNOWY 042646: ffd190 over a pink red
    ; row), but none sat on white both ways (snow fog: 205 / 203 at most
    ; over, tests\screens minions_snowy_far, bar 042646)
    static GoldHue := 52
    static GoldWhite := 215
    static CenterX := 1280
    static AimTol := 140         ; px off centre still counted as aimed
    ; A glow is aimed GlowAimDx px to its own side of the centre, never at
    ; it: centred it sits behind the character, OrbBeacon drops it (Player)
    ; and the hunt turned back and forth for 100 s, never walking (live
    ; 2026-11-02 SAND STORM: a glow at ~1950,716). Within GlowAimTol of
    ; that (or nearer the centre: seen above the character) = aimed (GlowTurn)
    ; GlowAimDx: the old fixed aim, 260 px each way. Loop L19 2026-11-03:
    ; every glow turned to was "out of sight" at once at ~1540 / ~1020 and
    ; never found again (NORMAL 02:15, a real far orb; clip SNOWY 001850:
    ; the orb at ~1410 after the turn). OrbBeacon drops a mostly white glow
    ; over the character's body (PlayerWhite x 940..1440: 1020 inside it)
    ; and short turns move more than TurnPxPerMs (~130 px over). So the aim
    ; is GlowClear px outside OrbBeacon's PlayerWhite box on the glow's side
    ; (right ~1570, left ~810), and a glow lost right after a turn to it is
    ; turned GlowClear px further out once (GlowLost) before the walk on.
    static GlowAimDx := 260
    static GlowClear := 130
    static GlowMaxY := 560
    static GlowAimTol := 100
    static GlowLostLooks := 3    ; steps for a glow gone from sight (a walk on / a turn back), then forgotten
    static TurnPxPerMs := 3.6    ; a 322 ms Left moved a bar 1168 px; short turns move ~2.2 px/ms (L34): they undershoot, the next look corrects
    static TurnMinMs := 25
    static TurnMaxMs := 250
    static ScanTurnMs := 500     ; one look-around step: 60 degrees, the Area's 78 overlap by 18 (at 600 ms by 6, about a bearing's error)
    static ScanTurns := 6        ; looks before a respawn wait or a give up: one circle
    static SweepTurns := 6       ; looks of a circle: the end-of-hunt sweep, the look before the map walk
    static BigTurnMs := 250      ; a look's worth of turn, 30 degrees: no walk through it, a look after it (_TurnBy, _Replay, _HomeStep)
    static PatrolAfterMs := 0    ; into the biome. The look round spawn is SweepTurns, then the walk: the 45 s here stood 33 s at spawn in 19 of 35 biomes, circles 2-7 found 2-3 of 35 orbs
    static PatrolCell := 2500    ; ms of walking a side
    static PatrolRadiusMs := 9000 ; from spawn: half the falls came 2-7 s out, the fixed spots are nearer
    static PatrolSteps := 6      ; walks in the patrol's first leg (WalkMs each); two legs per size
    ; ms of arrow key for a full circle (Wrap, Way), 120 degrees a second: spawn
    ; frames at bearing 0, -3000, -6000 show one view (L46 15:15:16, 15:46:38,
    ; 14:56:51), -1250 another (L47 15:55:29), and 12 turns of 250 ms brought the
    ; red cube back (L51 clip 222422054). It was 1250: a half turn was 75
    ; degrees, a turn back to a fight off the camera's way went wrong, _pos too.
    static FullTurnMs := 3000
    static FocalPx := 1028       ; px from the camera to the screen at 2560x1440: 720 / tan 35, the 70 degree view (AbsBearing)
    static OrbAboveY := 60       ; px a whole bar sits above every other to be the orb
    static OrbRatio := 1.5       ; the orb: its bar at least this times the median of the others'
    static OrbHighRatio := 1.25  ; ... or this, above all of them (live 18:26: 100 over 74 near a far orb)
    static OrbLonePx := 90       ; a lone bar wider than this is the orb
    ; The fight (the 3 hand fights, clips 2026-11-03): beside the orb the
    ; player stands, the orb ahead, and casts; minions come or stand round
    ; it and AoE reaches them; orb 144..230 px, minions 91..135 px wide
    ; there, from a camera zoomed far out and pitched down (_FightCamera).
    ; E whiffed with the orb's bar under ~110 px, the player settled at
    ; 166..220. GUESSED in that range until it runs live: BesideOrbW,
    ; BesideMinionW.
    static CamPitchSteps := 5
    static CamPitchPx := 80
    static CamBackSteps := 17    ; 12: far bars at y 40, off the scan's top (L39); 22: level with the ground, a target ahead hid behind the player, aim and look round fought (L42)
    static CamBackPx := 10
    static CamLookGapMs := 16
    static CamZoomOut := 25
    static CamZoomIn := 5
    ; The user, L52: orbs found, every skill from long range, nothing hit. L52
    ; 09:51:30-09:52:05: 14 casts "beside" a 160-184 px orb, the minions at 1.00;
    ; the frame where E landed has the orb bar near 230 px, minions either side
    static BesideOrbW := 190
    static BesideMinionW := 120
    ; A minion's bar higher on screen than AboveY (its y), the orb's than
    ; AboveOrbY, stands above the player: a rooftop, a terrace. However wide,
    ; not beside nor in reach, no casts at it (the wall's way up, WallHighY, or
    ; another target). L71 (2560x1440): stands that hurt something read a
    ; 108-146 px minion at y 474.. (level with the player: 474-506 on frame
    ; 04:05:52, then beside at 486), casts that hurt nothing at 446 (128 px),
    ; 416-424 (122 px on a terrace, RAINY 02:59), 410, 400, 392 (a HEAVEN
    ; terrace, 03:04:26), 264. The orb floats over its minions: level, its bar
    ; sits ~120 px higher (168 px at 358 over minions at 474-506, 04:05:52),
    ; beside at 474..; on a SNOWY rooftop a 144-328 px orb read 44-126
    ; (02:46-02:47, ~10 casts, fill 1.00). On a HEAVEN terrace 132-150 px at
    ; 322-324: too near 358 to tell, Locked (InReach) keeps casts off it.
    ; Real frames: tests\screens\minions_above_*, minions_level_rainy_fight_*
    static AboveY := 460
    static AboveOrbY := 300
    ; A minion's bar under this y stands nearer the camera than the character:
    ; behind its back (shift lock faces it the camera's way), out of F's cloud
    ; and Q's line. Level with it a bar sits at 648-688 (L72 053528 Golden
    ; Scarab beside the player at 662, CORRUPTION stands 648-688). L72 SAND
    ; STORM 05:27-05:36: 13 of 50 stands at such a bar (good fights 6-15%),
    ; the minions all 1.00, so AimAt's "lowest" took one behind, 0 down in 244 s
    static BehindY := 760
    static StandLoose := 0.8    ; standing: no step until a bar falls under this share of those
    static AlmostShare := 0.75   ; from this share of those: NearStepMs steps, no overshoot
    static NearStepMs := 300
    static BlockedMs := 4000     ; walking no closer with a minion close: stand and cast this long
    static FaceTol := 300        ; px off centre let be (hits landed at x 727..1516)
    static OrbTol := 60          ; the orb alone stands still: straight at it, F lands ahead (L60 13:57: off to the side)
    static LockTol := 150        ; px off the character let be in a fight
    ; Shift lock keeps the character left of the screen's centre and skills go
    ; straight out of it: a target centred on screen is passed on the right
    ; close up (the user, L44 13:55: "hitting in front of it", the orb untouched)
    static LockX := 1195         ; the character's x on 4 frames: 1157..1215
    static LockPxPerMs := 2.2    ; short turns (L23, L34: 1.75-2.2): one correction lands on the target
    static ShortTurnPx := 220    ; ... only this far, the rest at TurnPxPerMs (L66: 190-250 ms moved 593-1178 px, 3.1-4.7 px/ms;
                                 ; all at 2.2 a far minion flew past the centre, back and forth, no walk, lost: 04:17:51, 06:39:31)
    static ReachDx := 230
    static VCheckMs := 500       ; Charge read this long after V's cast: spent or refused
    static VOffMs := 20000
    static AimMinionW := 105     ; a minion's bar this wide: in reach, faced first
    static FightTickMs := 300    ; a look at the fight between casts (the look in it: _TickLeft)
    static QuestEveryMs := 2000  ; how often a cast looks for the Quest Board's page (_QuestSeen)
    static JockRetryMs := 20000  ; after a failed Leave on Jock's dialog: fight on this long before another try
    static PanelMinRows := 3     ; skill panel rows that prove an aura is on (_PanelShows; Eden has 6)
    ; Flashes wash the bars out for seconds (t=46-50, 64 of 170827; 70-73 of
    ; 171013). No bar beside the fight: skills on BlindCastMs, then none for
    ; ClearMs so the screen clears; still no plate: a look round for it, at
    ; any fill. Only the Orb Awards toast is a kill (L72 05:04:04: the plate
    ; gone at 0.06 taken for one, the orb alive at 0.06 the next hunt).
    ; The orb has no regen and single reads jump (0.15 -> 1.00 -> 0.06): its
    ; HP is the lowest of its last OrbHpReads orb-alone reads (OrbHp)
    static BlindCastMs := 4000
    static ClearMs := 2500
    static OrbHpReads := 3
    static OrbLowFill := 0.4
    static OrbLowMs := 15000
    ; The orb is open (Open) once OpenDown minions' toasts came in this biome:
    ; nothing else proves it, a lone hurt bar is mostly a minion (8 of the 10
    ; first lone reads under 0.9 in L44-L51). Beside it then (Stay) no step
    ; away: OpenStayMs of skills with no bar, a look round on the spot, again.
    ; The hunt runs past Minions.maxSec, to HuntCapMs, while it is open or a
    ; bar read hurt or the fill fell HurtKeepMs ago at most (flat 1.00 bars:
    ; no, the gold room's; L47 16:53 ran out of time with 4 minutes of biome
    ; left and the orb at 51 / 300)
    static OpenDown := 3
    ; The orb's bar seen going down, no minion in view: it can be hurt, so it
    ; is open whatever the toasts counted (L64 02:24:47-02:25:37: 0.90 -> 0.29
    ; with 2 minion toasts, Charge 100 the whole time, no Voidrush, no
    ; Deadeye). Two orb-alone reads at HurtOpenFill or less, the later one
    ; HurtOpenDrop lower, within HurtOpenMs (a flat misread like 0.38, 0.38
    ; of L60 14:11:59-14:12:16 does not count)
    static HurtOpenFill := 0.92
    static HurtOpenDrop := 0.03
    static HurtOpenMs := 15000
    static OpenStayMs := 15000
    static HurtKeepMs := 30000
    static HuntCapMs := 900000
    ; The Quest Board's interact prompt (real crop minions_prompt_board): up
    ; wherever the board is, inside this box; an E here opens the page
    static PromptBox := {x: 640, y: 300, w: 1280, h: 700}
    static PromptRe := "i)see\s*q\s*uests|quest\s*bo[ao]rd"
    static FillEveryMs := 3000
    ; Survival (normal hits -15, regen ~1.5% a second): no holding back at
    ; low HP. The hand fights have none; 24-26 of 34 such stretches (L44..L51)
    ; ended in a real death all the same, and with no bar in view one stood
    ; idle until the HP read 60% (L48 17:32:30-17:33:05, the orb at 181/300).
    ; The dodge. Clip 170608 (10 fps): the hits (-15 at 9.1, 14.1, 17.8 s)
    ; came from blue darts thrown by minions hovering round the orb, ~500 px
    ; off, ~1500 px/s on screen; the darts of 17.0, 21, 26.3, 26.9, 31.3 s
    ; flew past the moving player. A step back keeps in the line of fire: to
    ; the side, DodgeRun steps a way so the player is off the spot aimed at
    ; when the dart lands. A step takes the tick's place, a ready skill waits
    ; no longer. Bars in sight, none a minion's, for DodgeHoldMs: none left,
    ; no dodge (0:33 on, the orb alone: stood still, no hit); a flash hiding
    ; every bar says nothing. Never a step back, however near a minion: the
    ; aim has just put it dead ahead, so back is along the dart's line. A side
    ; only, and a stand that drifts out of reach (Beside) walks back in.
    ; Step length GUESSED.
    static DodgeStepMs := 400
    ; steps one way: shift lock turns a long strafe into an orbit that leaves
    ; small slabs (L51 22:45: two walks into the sea on 2.4 s runs). 3 is a
    ; GUESS, no live test of 1.2 s runs: back towards 6 if hits a minute rise
    static DodgeRun := 3
    static DodgeHoldMs := 3000
    ; Out of reach when hit hard. L72 SAND STORM 05:27:27 and 05:31:39: 15
    ; deaths in 2 fights of 39 casts each, every life from full HP dead 8-17 s
    ; after its stand began, the strafe on all the while (45% -> 17% 05:33:24-27,
    ; 33% -> 16% 05:33:49-52, 45% -> 14% 05:35:35-40; full -> 2% 05:28:29-37),
    ; the minion bars at 1.00: they hit, the casts did not. The strafe keeps the
    ; player in melee reach (SNOWY, WINDY: melee minions). The HP read down
    ; BackDrop within BackDropMs (BackLowDrop at BackHp or under), minions
    ; alive (HitHard): back (s: away from what the aim faces) BackOffMs, skills
    ; on, then no walk in for BackHoldMs (strafe and cast from there; a bar
    ; beside still stands). Short: a step back is checked by the falls alone.
    ; Numbers GUESSED; the fight's HP is logged (_HpNote: each HpLogDrop down,
    ; else every HpLogMs while it moves) to measure them.
    static BackDrop := 0.2
    static BackLowDrop := 0.1
    static BackHp := 0.45
    static BackDropMs := 3000
    static BackOffMs := 1200
    static BackHoldMs := 2500
    static HpLogDrop := 0.15
    static HpLogMs := 3000
    static HpLogBarMs := 5000
    ; The orb nearer the camera than the character: F's cloud rides with the
    ; character and misses it (L44 13:55 clip t=24-47: the orb drawn over the
    ; character, F 0 of 2, only E moved the plate). One short step back, no
    ; minion left, no key into Deadeye's root. Width and y GUESSED from that one
    ; clip, between 182 px ahead and 236 behind. OrbBehindH keeps out plates
    ; read past the bar over dark scenery: L51 22:45 a 144 px bar read full
    ; 260, h 10; full orb bars of 180-282 px measured h 14-18
    static OrbBehindW := 210
    static OrbBehindY := 480
    static OrbBehindH := 14
    static OrbBehindGapMs := 700
    static LostLooks := 2        ; scans without a turn after a bar went missing
    static StuckWalks := 3       ; walks with the bar unchanged -> Escapes
    ; Walking into a wall (a clip at night 2026-11-02: the player against a
    ; terrace wall for most of a 105 s hunt, nothing killed): these in turn,
    ; EscapeMs each, forward with a jump ("") or strafing; then that target
    ; is left for AvoidMs
    static Escapes := [{name: "jump forward", side: ""}, {name: "strafe left", side: "a"}, {name: "strafe right", side: "d"}]
    static EscapeMs := 600
    ; The orbs on a raised terrace next to spawn, 2-4 blocks up, too high to
    ; jump (many clips 2026-11-02): the Escapes fail and the minions on top
    ; hit the player. A target still above (a bar at WallHighY or higher on
    ; screen; GUESSED, a level bar ~650) -> along the wall to the way up
    ; (stairs / a ramp, ~10-25 studs, either way), the camera kept on the
    ; target (TurnFor; shift lock keeps the body facing it). Not w + a: with
    ; the camera on a target D behind the wall that way has no pull along
    ; the wall left at D from its foot (45 degrees), the slide stood still
    ; there (L25 22:22:38, L23 18:10:59), short of the stairs. A / d alone
    ; keeps going (slower the further out) but never nears the target, so
    ; nothing would show a way in: steps of WallStepMs, a / d with two hops,
    ; w added for its last WallPushMs (the sum stalls at 3.6 D). Up to
    ; WallSlideMaxMs one way, twice that the other (back past the start),
    ; then round: well back (WallRoundMs), WallSlideMaxMs further on the
    ; same way and WallInWalks walks in. A step that left the view the same
    ; (a block in the way): the next is s + a / d (WallPeelMs), off it. The
    ; island's edge: the next leg. The bar WallGainPx wider or lower than at
    ; its worst this leg WallLooks looks running = a way in: walks; stuck
    ; again, on along the wall from there. No gain counted on the way back
    ; past the start (the bar grows, nothing found), nor just after a peel.
    ; The orb beside the player = the way up: the side kept per biome
    ; (WallSides), tried first next time.
    ; No picture rule for the stairs: the real frames (L22..L26) have none.
    ; The dark soil of the faces is 0.2-0.3% of a day frame and drowned by
    ; trees, boards and shadows at night (12-26%), the steps are the grass
    ; or snow around them.
    static WallHighY := 620
    static WallSlideMs := 700    ; a slide (_Slide) with no target to keep the camera on
    static WallStepMs := 1000
    static WallHopMs := 520      ; between two hops of a step (a jump lasts ~540: down for the next look)
    static WallPushMs := 350
    static WallRoundMs := 1500
    static WallInWalks := 3
    static WallPeelMs := 500
    static WallSlideMaxMs := 7000
    static WallGainPx := 12      ; px: over Same's tolerance
    static WallLooks := 2        ; a hop lifts the camera: one look is no gain
    static WallBlindSteps := 4   ; steps on with the target out of sight (overhead, behind a ledge)
    static WallSides := Map()    ; biome -> "a" / "d", kept between hunts
    ; One wall gets WallMaxMs, about 40 s with the walks and Escapes before
    ; (L25 WINDY: 100 s, 2 casts, all of it at one wall): then that target is
    ; left, the patrol walks on, half a turn away, and bars within WallOffCone
    ; of the wall's bearing (narrower than BesideMinionW) count for nothing
    ; for WallOffMs: from another side the bearing is another. Time away
    ; from the wall (standing, casting) counts WallGapMs at most a stretch.
    static WallMaxMs := 35000
    static WallGapMs := 4000
    static WallOffMs := 60000
    static WallOffCone := 375    ; ms of turn: 45 degrees either way
    ; The target in reach from below (InReach; the hand fights' smallest
    ; bars, GUESSED enough for the wall too): BelowStands stands of BlockedMs
    ; there, casting, before the search goes on; more while a bar is hurt
    ; (HurtFill or less: the casts land; the minions come down to the player)
    static BelowStands := 3
    static HurtFill := 0.9
    ; The player's HP: Roblox's player list draws it over the "Rolls" header
    ; (x 2422..2540, rows ~27..40) once hurt, a green / yellow / red fill and
    ; grey for the HP lost; full HP: no bar (PlayerHp -1).
    static PlayerHpX1 := 2422
    static PlayerHpX2 := 2540
    static PlayerHpYs := [30, 32, 34]
    ; No Voidrush VoidGroundMs after a jump of the hunt's own (a walk, a
    ; slide, an escape): the game refuses it in the air ("You need to be on
    ; ground to use this", clip RAINY 041829)
    static VoidGroundMs := 1500
    ; Skills fire the way the CHARACTER faces (live 2026-11-02), and it
    ; turns to the camera only once it moves forward: a kiting step left it
    ; facing aside. With shift lock on (Minions.shiftLock, default 1; live
    ; 2026-11-02 with Roblox's Shift Lock Switch setting on) it always faces
    ; the camera; it is turned on after the respawn (Input.ShiftLock) and
    ; off whenever _Hunt ends and before a storage swap (the mouse cannot
    ; click any UI while it is on). Not confirmed on (or the setting off): a
    ; w tap of AimTapMs right before every skill (Deadeye's hold too).
    static AimTapMs := 70
    static AvoidMs := 30000      ; an out of reach target is left this long
    static MatchX := 200         ; px: one bar in two scans (after the turn's shift)
    static MatchY := 80
    static PeekLooks := 2        ; scans in place for bars seen once (not yet confirmed)
    static DeathWaitMs := 7000   ; nothing in sight: once, wait out a respawn and look again
    static ReturnWalks := 8      ; walks back towards the fight's bearing (GUESSED: ~6 s from spawn)
    ; After a death the fight is at a place, not a bearing: where the player
    ; last saw a target (_FightSeen: _pos, dead reckoned from spawn). L36..L41:
    ; 18 deaths in a fight, a replay past its first steps never got back (0 of
    ; 8), a bar seen from spawn left no trail and 8 walks led away from it.
    static FightOpenMs := 60000  ; a target seen this long ago and not down: the fight is on (the brief's 60 s)
    static HomeNearMs := 500     ; this near the spot: there (a walk's length less a bit, GUESSED)
    static HomeAimMs := 40       ; a turn of less on the way: not worth a key press (GUESSED)
    static HomeSpareWalks := 4   ; walks on top of the way's length: walls, slides (GUESSED)
    static LineBend := 1.5       ; a trail longer than this x the straight way ...
    static LineSlackMs := 1500   ; ... and this: wandered, the straight way instead (GUESSED: _pos is not in the logs)
    static RingPoints := 4       ; looks round the spot after the one on it ...
    static RingMs := 2800        ; ... this far off it, a quarter turn apart (4 walks, GUESSED)
    ; A far bar: the fight is out there, not where the player stood (L66
    ; 03:49:15 bar 24 px lost, 27 s of looks round the player's own spot; L69
    ; WINDY 17:51:29 first bar, first cast 47 s later). L65/L66: bars under
    ; 40 px were reached in 1-12 s of walking, mostly 2-5 s
    static FarWalkMs := 1000     ; ms out per (beside width / bar width - 1): 30 px minion 3000 ms (GUESSED from that)
    static FarMaxMs := 6000      ; never further (GUESSED)
    static ReplayWalks := 2      ; walks of a replay (_Replay) between two looks (GUESSED: L31 a walk and its look take ~1.8 s)
    ; Orbs spawn at a few fixed spots. b: ms of bearing from spawn, most
    ; sightings first; tol: their spread and a little. THESE b ARE FALSE: they
    ; are first sightings in L22..L34 from spawn wrapped to the old 1250 ms
    ; circle at 3.6 px a ms, on a circle of 3000 they mean nothing (two of
    ; "850" are 1268 and 2515; L44..L51 sightings mod 3000 group near 340, 1065,
    ; 1250, 1470, 1850, 2030, 2490). Minions.spots is off by default until they
    ; are rebuilt from those (_SpotsOn).
    static Spots := [{b: 850, tol: 30}, {b: 265, tol: 40}, {b: 385, tol: 30}, {b: 120, tol: 30}, {b: 1198, tol: 30}, {b: 574, tol: 30}]
    static SpotLooseMs := 190    ; more tol for the dead reckoned way to a fight (GUESSED)
    static RouteFails := 2       ; replays that failed in a row: the stored route dropped
    static RouteCone := 750      ; ms: a bar this near the way a blind route goes next keeps it on (90 degrees, GUESSED)
    ; Orbs and minions come ~35-40 s after a normal biome starts (live
    ; 2026-11-02; ~3 of 13 biomes had none): nothing in sight -> keep
    ; looking until this long after the start (GiveUp)
    static OrbLateMs := 55000
    static SeenQuietMs := 25000  ; ... and no bar seen this long (GiveUp)
    ; ... but a target seen (a bar or a glow) at most PursueMs ago is not
    ; given up on (loop L19 2026-11-03, WINDY: "giving up" 38 s after the
    ; orb went behind a terrace ledge): the walk back to its bearing again
    ; (ReturnWalks steps) once per PursueStyles entry, sliding along the
    ; wall (w + a / d, a jump each) or backing off and walking round it
    static PursueMs := 90000
    static PursueStyles := [{name: "sliding left", side: "a"}, {name: "sliding right", side: "d"}, {name: "backing off and round", side: "s"}]
    static RoundBackMs := 900    ; "round": a step back this long, then a quarter turn left, walks, a quarter turn back
    ; Walking with nothing new in view (the walk back, a pursuit, a glow
    ; out of sight): the view (_View: a coarse grab, ViewArea rows ViewStep
    ; apart, every ViewStride-th px, the character's column ViewSkip left
    ; out) the same after StillWalks walks in a row (ViewSame: under
    ; SameShare of its px changed by over SameDiff) = walking into a wall
    ; (the WINDY clip: 20 s facing a terrace wall) -> SlideSteps slides
    ; along it one way (the other way next time), then walks again
    static ViewArea := {x1: 560, x2: 2000, y1: 400, y2: 1144}
    static ViewStep := 32
    static ViewStride := 16
    static ViewSkip := {x1: 1040, x2: 1520}
    static ViewSigY := 968       ; rows to here make the view's signature (lower: the aura's swirl at the feet)
    static SameDiff := 24
    static SameShare := 0.1
    static StillWalks := 2
    static SlideSteps := 4
    ; The island's edge (loop L19 2026-11-03, NORMAL by day: walked off it
    ; to a glow): the ground beside the character's legs (EdgeL / EdgeR,
    ; the view's rows from EdgeY1 down) turns sea / sky blue (blue >= 170, 50
    ; over red, 20 over green): EdgeShare or more of a side = the edge ->
    ; no step forward, a step back (EdgeBackMs) and a half turn. Clip
    ; frames: 0.48..0.88 at the edge, under 0.04 walking on the island.
    ; Daytime only (the void at night, in fog: never seen).
    ; On a walk to a bar or a way back (_toBar): EdgeBarTurnMs, no half turn.
    ; L44..L51: 16 edge lines that near a bar, in SNOWY, HEAVEN and WINDY, bars
    ; back in 2-5 s after 15. Floors read as sea: frames near 6 of them have
    ; blue snow or HEAVEN's blue tiles underfoot, no sea (L46 15:36:17, L51
    ; 22:45:20). The 625 ms all those lines were made with, 75 degrees, left the
    ; target on screen, a true half turn faces away from it.
    static EdgeL := {x1: 536, x2: 1064}
    static EdgeR := {x1: 1496, x2: 2000}
    static EdgeY1 := 888
    static EdgeShare := 0.35
    static EdgeBackMs := 600
    static EdgeBarTurnMs := 625
    ; Biomes whose floor reads as sea: the view's edge means nothing there, a
    ; remembered fall still counts (_EdgeGuard). Blue snow .98 and .90 of a side
    ; (L49 18:48:47, L46 15:46:38), STARFALL's and HEAVEN's blue floor (L46
    ; 15:34:27, 15:36:17). Edge lines followed by a death in 8 s: 3 of 25, 4 of
    ; 43, 0 of 11; NORMAL 18 of 36, WINDY 4 of 12 stay guarded.
    static SeaFloors := Map("SNOWY", 1, "STARFALL", 1, "HEAVEN", 1)
    static BiomeCheckMs := 1000  ; how often the hunt asks the biome dep
    static WalkMs := 700
    static TrailGrainMs := 32    ; two ticks of A_TickCount
    static StillMs := 600        ; two views this far apart at least tell a wall (_Still): steps run into each other now
    static MaxSec := 120
    static ConfirmMs := 5000     ; the log has this long to name the combat aura
    static RehuntMs := 180000    ; a biome may be hunted again this long after a hunt
    static MinSec := 60
    static AuraCheckMs := 10000  ; how often the log's aura is compared with the combat aura
    static ViewCheckMs := 5000   ; how often the fight looks for a menu over the game (_ClearView)
    ; Boss mode (see the top)
    static BossBiome := "GRAVEYARD"
    static BossLookMs := 20000   ; the look for the boss before the swap (~6 circles of 6 steps)
    static BossMaxSec := 600     ; its despawn timer: 10 min
    static BossQuietMs := 45000  ; no bar this long -> the fight is over (deaths walk back from spawn)
    ; The boss bar UI (GUESSED, not seen): a warm (yellow / orange / red)
    ; strip at least BossBarMin px wide across the top centre, its HP text
    ; bridged (gaps up to BossGap px), at most BossThick px tall
    static BossArea := {x1: 760, x2: 1800, y1: 30, y2: 220}
    static BossBarMin := 360
    static BossGap := 80
    static BossThick := 40

    name := "minions"
    priority := 6

    __New(deps := "") {
        this._env := TaskEnv(deps)
        this._grab := TaskEnv.Dep(deps, "grab", "")
        if !IsObject(this._grab)
            this._grab := ScreenFrame()
        this._scanFn := TaskEnv.Dep(deps, "scan", "")
        this._beaconFn := TaskEnv.Dep(deps, "beacon", "")
        this._viewFn := TaskEnv.Dep(deps, "view", "")    ; -> {edge, sig} or "" (_View)
        this._stills := 0             ; walks in a row that left the view the same (_Walk), then slides
        this._wallSide := 0          ; _WalkOrSlide: the slide way, a / d in turn
        this._lastView := ""             ; the view after the last walk
        this._viewAt := 0            ; Now() of that view
        ; the move held across scans (_Go, _Stop; "" = none) and the tick it
        ; was last asked for by (_Timed: not this tick, it goes up)
        this._held := "", this._tick := 0
        ; when this tick began, where _Mark is in it, its ms per part, when
        ; the Quest Board page was read last (_QuestSeen)
        this._tickAt := "", this._partAt := 0, this._parts := MinionsTask._NoParts(), this._questAt := 0
        this._jockAt := ""           ; Now() of the last failed Leave on Jock's dialog ("" = none)
        this._biomeFn := TaskEnv.Dep(deps, "biome", "")
        this._hudFn := TaskEnv.Dep(deps, "hud", "")
        this._toastFn := TaskEnv.Dep(deps, "toast", "")
        this._bossFn := TaskEnv.Dep(deps, "bossbar", "")
        ; the boss's Discord message (SinisterReport): one per spawn, edited at its death
        this._sin := TaskEnv.Dep(deps, "sinister", "")
        if !IsObject(this._sin)
            this._sin := SinisterReport({webhook: this._env.wh, cfg: this._env.cfg, ghost: TaskEnv.Dep(deps, "ghost", "")
                , log: this._env._logFn, now: this._env.nowFn})
        this._boss := false          ; this Run is boss mode (GRAVEYARD)
        this._learnt := Map()        ; aura -> Map key -> panel row (MinionSkills), kept between hunts
        this._eden := false
        this._swap := ObbyTask(deps)
        this._swap.logoOk := true    ; Eden's name panel is a logo (live 2026-10-31)
        this._biome := ""            ; the biome seen last by CanRun
        this._biomeAt := ""          ; Now() when CanRun saw it start ("" = unknown)
        this._hunted := ""           ; Now() of the last finished hunt in this biome ("" = none)
        this._biomeDown := 0         ; minion toasts since this biome began or its orb fell (f.down)
        this._lock := false          ; shift lock confirmed on (no w aim taps)
        this._lockTried := false     ; this hunt uses shift lock (Minions.shiftLock)
        this._lockOwed := false      ; shift lock maybe left on (a halt): off first next Run
        this._spawnAt := 0, this._spawnSent := 0   ; the closing respawn (_StillAtSpawn)
        this._bearing := 0           ; net turn ms since the last respawn (Left -, Right +)
        this._turns := 0             ; camera turns made (_Turn): a death needs none since the bars went
        ; where the player is from the last respawn (dead reckoning: forward
        ; ms walked along the bearing, _Moved; x right, y ahead of the
        ; respawn way) and the falls off the island seen (Falls, FallAhead)
        this._pos := {x: 0, y: 0}
        this._falls := [], this._patrols := 0, this._toBar := false, this._fallFree := 0, this._edgeFree := 0, this._patrolling := false, this._searched := Map(), this._walls := []
        this._edgeWay := ""          ; where the last _EdgeGuard fired, {x, y, b, at} (_FallWay)
        ; the moves since the last respawn ({k, ms, b}: _Note), how many of
        ; them led to the last sighting and its bearing ("" = none yet);
        ; the camera re-aimed at that respawn (no: bearings are guesses)
        this._trail := [], this._trailTo := 0, this._trailB := "", this._aimed := true
        ; spot (String of its b) -> {ms, fails, steps}: the learned ways there
        ; (_RouteLearn), kept in routesFile (default data\minions_routes.json)
        this._routes := Map(), this._routesLoaded := false
        this._routesFile := TaskEnv.Dep(deps, "routesFile", "")
        this._jumpAt := ""           ; Now() of the last jump (no Voidrush in the air: VoidGroundMs)
        this._hpLog := []            ; the player's HP reads lately: {at, hp} (Respawned)
        this._deathFn := TaskEnv.Dep(deps, "death", "")   ; -> true when the death screen shows (tests)
        this._respawnLog := TaskEnv.Dep(deps, "respawnLog", "")   ; RespawnTail (Sync, Poll); made in _Fight
    }

    CanRun(state) {
        env := this._env
        if (!IsObject(env.cfg) || !env.cfg.Get("Minions.enabled", 0))
            return false
        b := state.HasProp("biome") ? state.biome : ""
        if (b != this._biome)
            this._BiomeStart(b)
        ; once per RehuntMs in one biome: orbs come back, and a hunt that
        ; found nothing may find them later (2026-11-01: a long Sand Storm
        ; was never hunted again)
        ; GRAVEYARD: the boss spawns only when it starts, checked once
        if (b = MinionsTask.BossBiome) {
            if (!env.cfg.Get("Minions.boss", 1) || this._hunted != "")
                return false
        } else if (!MinionsTask.Biomes.Has(b) || (this._hunted != "" && this._env.Now() - this._hunted < MinionsTask.RehuntMs))
            return false
        else if (this._NoHunt(b) && !this._PrepDue())
            return false
        return IsObject(this._swap._AuraCal()) && (!env.cfg.Get("Minions.putBack", 0) || this._swap._Aura().known)
    }

    ; A new biome: new orbs, not hunted yet.
    _BiomeStart(b) {
        this._sin.Gone()                     ; a boss not seen dead by now despawned
        this._searched := Map(), this._walls := []
        this._biome := b
        this._biomeAt := this._env.Now()
        this._hunted := ""
        this._biomeDown := 0
    }

    ; NORMAL and not to be hunted (Minions.normal 0): only the set-up runs here.
    _NoHunt(b) => b = MinionsTask.IdleBiome && !this._env.cfg.Get("Minions.normal", 0)

    ; A hunt can go on in b.
    _Huntable(b) => MinionsTask.Biomes.Has(b) && !this._NoHunt(b)

    ; The next orb biome would have to swap or respawn at its start: done in
    ; NORMAL instead (the header). Modelled on the 40 orb biomes of L44-L51
    ; that began with a hunt running: with no set-up 5 would swap there
    ; (16-17 s) and 10 respawn (6 s). The aura not known is no reason. Put
    ; back on: the user's aura is on between hunts and _StillAtSpawn never
    ; holds, nothing to keep ready.
    _PrepDue() {
        env := this._env
        if env.cfg.Get("Minions.putBack", 0)
            return false
        if (!this._spawnAt || env.Now() - this._spawnAt >= MinionsTask.PrepAfterMs)
            return true
        a := this._swap._Aura()
        return a.known && !ObbyTask.SameAura(a.name, env.cfg.Get("Minions.aura", MinionsTask.Aura))
    }

    Run(ctx) {
        env := this._env
        io := env.io
        this._hunted := env.Now()
        this._boss := (this._biome = MinionsTask.BossBiome)   ; CanRun let GRAVEYARD in for the boss
        prep := this._NoHunt(this._biome)    ; CanRun let NORMAL in for the set-up
        if this._lockOwed                    ; before any click (the storage, the respawn)
            this._ShiftOff(ctx)
        if !this._ClickOk(ctx, "the aura swap")
            return 0
        this._swap.wear := env.cfg.Get("Minions.aura", MinionsTask.Aura)
        this._back := env.cfg.Get("Minions.putBack", 0) ? true : false
        sw := this._back ? "" : this._AlreadyOn()
        already := IsObject(sw)
        ; a swap: the log has to show it tells this aura's respawns too (_Respawn's reset does)
        if (!already && IsObject(this._respawnLog))
            this._respawnLog.Seen := false
        ; boss mode with a swap to make: the boss is up ~5% of the time,
        ; the swap is ~15 s of storage clicks -> look first
        looked := false
        if (this._boss && !IsObject(sw)) {
            if !this._BossFirst(ctx)
                return 0
            looked := true
        }
        if (!IsObject(sw) && this._back)
            sw := this._swap.PutOnSailor(ctx)
        if !IsObject(sw)
            sw := this._WearOnly(ctx)
        ; swapped or not: no storage / Collections / prompt left over the game
        clear := this._ClearView(ctx)
        if !sw.ok {
            if (sw.why = "stopped")
                this._hunted := ""
            else {
                msg := "could not equip " this._swap.wear " (" sw.why "): no hunt"
                env.Log("minions: " msg)
                env.Report("errors", "Minions failed", msg, 0xE74C3C)
            }
            return 0
        }
        if !clear {
            if CleanupCtx.Halted(ctx)
                this._hunted := ""
            else
                env.Log("minions: a menu is still over the game: no hunt")
            return 0
        }
        hits := 0
        try {
            if !this._Confirm(ctx, sw)
                return 0
            if prep
                env.Log("minions: set-up in " this._biome " - no hunt, the respawn and idle")
            else if (this._StillAtSpawn(already) || this._Respawn(ctx)) {
                this._bearing := 0, this._pos := {x: 0, y: 0}   ; the camera faces the respawn way
                ; boss mode, the combat aura on already: the look here
                if (this._boss && !looked && !this._BossLook(ctx)) {
                    if !ctx.ShouldStop()
                        env.Log("minions: no boss in " MinionsTask.BossBiome)
                } else
                    hits := this._Hunt(ctx)
            }
            else if !ctx.ShouldStop()
                env.Log("minions: respawn failed (" Input.LastResetError "): no hunt")
        } finally {
            if !CleanupCtx.Halted(ctx) {
                cctx := CleanupCtx(ctx)
                this._CloseRespawn(cctx)
                if (this._back && this._ClickOk(cctx, "the aura put-back"))
                    this._swap.PutBack(cctx, sw)
                else if this._back
                    this._swap.Owe(sw)
            } else if this._back {
                this._swap.Owe(sw)
            }
        }
        ; F3 / pause / Roblox not in front: that hunt does not count, the
        ; next Start hunts this biome again (2026-11-01: after an F3 the
        ; restarted macro sat in the same Sand Storm doing nothing)
        if CleanupCtx.Halted(ctx)
            this._hunted := ""
        env.Log(prep ? "minions: set-up over" : "minions: hunt over, " hits " target(s) went down")
        return hits
    }

    ; The respawn that closes a hunt, a look or a set-up: the next hunt starts
    ; from it (_StillAtSpawn). A failure here left Collections up unsaid (live
    ; 2026-11-03 18:28).
    _CloseRespawn(ctx) {
        if (this._ClickOk(ctx, "the respawn") && !this._Respawn(ctx) && !CleanupCtx.Halted(ctx))
            this._env.Log("minions: the respawn after the hunt failed (" Input.LastResetError ")")
    }

    ; A hunt's respawn: Input.QuickReset, over at the respawn's lines in
    ; Roblox's log. Done: remembered for _StillAtSpawn. -> as ResetToSpawn.
    _Respawn(ctx) {
        env := this._env
        this._spawnAt := 0
        if (!IsObject(this._respawnLog) && !IsObject(this._scanFn))
            this._respawnLog := RespawnTail()
        this._RespawnSync()
        log := this._respawnLog
        if !Input.QuickReset(ctx, env.io, IsObject(log) ? () => log.Poll() : "")
            return false
        this._RespawnSync()
        this._spawnAt := env.Now(), this._spawnSent := Input.Sent
        return true
    }

    ; The last hunt's closing respawn still holds, so this hunt needs none
    ; (~5 s of a ~120 s biome): the combat aura was on already (no storage
    ; clicks: already), no key or click through Input since (another task),
    ; no menu closed (_ClearView), no respawn in the log (a death, a new
    ; aura), no newer log (a rejoin), not older than SpawnKeepMs (the user
    ; may have moved by hand). The camera is as the re-aim left it, at
    ; bearing 0: _FightCamera goes on from there as after a respawn. Any
    ; doubt: a respawn. Good for one hunt.
    _StillAtSpawn(already) {
        env := this._env, at := this._spawnAt
        this._spawnAt := 0
        if (!already || !at || env.Now() - at >= MinionsTask.SpawnKeepMs || Input.Sent != this._spawnSent)
            return false
        log := this._respawnLog
        if (IsObject(log) && (log.Poll() || log.Stale()))
            return false
        env.Log("minions: still at spawn since the last hunt - no respawn")
        return true
    }

    ; The fight with shift lock on (Minions.shiftLock), and off again
    ; however it ends (stop, biome change, give up, an error).
    _Hunt(ctx) {
        this._spawnAt := 0                       ; only the closing respawn counts
        this._lockTried := this._env.cfg.Get("Minions.shiftLock", 1) ? true : false
        this._lock := this._lockTried && this._ShiftOn(ctx)
        try {
            if !this._FightCamera(ctx)
                return 0
            return this._Fight(ctx)
        } finally {
            if this._lockTried
                this._ShiftOff(ctx)
            this._lockTried := false
        }
    }

    ; Boss mode before the swap: a respawn, then BossLook. -> true = the boss
    ; is in sight (swap and fight); false = none (logged, the closing
    ; respawn made), the respawn failed, or stopped (a stop / halt: this
    ; GRAVEYARD is checked again).
    _BossFirst(ctx) {
        env := this._env
        if !Input.ResetToSpawn(ctx, env.io) {
            if !ctx.ShouldStop()
                env.Log("minions: respawn failed (" Input.LastResetError "): no boss check")
        } else {
            this._bearing := 0, this._pos := {x: 0, y: 0}
            if this._BossLook(ctx)
                return true
            if !ctx.ShouldStop() {
                env.Log("minions: no boss in " MinionsTask.BossBiome)
                this._CloseRespawn(CleanupCtx(ctx))
            }
        }
        if (ctx.ShouldStop() || CleanupCtx.Halted(ctx))
            this._hunted := ""
        return false
    }

    ; The look for the boss: BossLookMs of ScanTurnMs turns (full circles),
    ; a bar confirmed in two scans (Confirmed; one seen once: a scan again
    ; in place first) or the boss bar UI (BossBar) -> true (logged).
    _BossLook(ctx) {
        env := this._env
        t0 := env.Now(), last := [], shift := 0, peeked := false
        while (env.Now() - t0 < MinionsTask.BossLookMs) {
            if ctx.ShouldStop()
                return false
            raw := this._Scan()
            bars := MinionsTask.Confirmed(raw, last, shift), last := raw, shift := 0
            ui := !bars.Length && this._BossUi()
            if (bars.Length || ui) {
                env.Log("minions: boss in sight (" (ui ? "the boss bar at the top" : "a bar at " bars[1].x "," bars[1].y ", " bars[1].w " px")
                    . ") - bearing " this._bearing " ms")
                this._sin.Spawn(this._biome "@" this._biomeAt)   ; one Discord message per GRAVEYARD start
                return true
            }
            if (raw.Length && !peeked) {
                peeked := true
                continue
            }
            peeked := false
            shift := this._Turn("Left", MinionsTask.ScanTurnMs)
        }
        return false
    }

    ; One boss fight tick for SinisterReport: the widest confirmed bar's fill
    ; (the boss's plate), and its plate in sight (any bar, else the boss bar
    ; UI; read from this tick's snapshot).
    _SinNote(raw, bars, now) {
        top := ""
        for b in bars
            if (!IsObject(top) || MinionsTask.FullW(b) > MinionsTask.FullW(top))
                top := b
        seen := raw.Length > 0 || this._BossUi()
        this._sin.Note(IsObject(top) ? MinionsTask.FillOf(top) : "", seen, now)
    }

    ; The boss bar UI is up now (BossBar; the bossbar dep in tests).
    _BossUi() {
        if IsObject(this._bossFn)
            return (this._bossFn)() ? true : false
        try return IsObject(MinionsTask.BossBar(this._grab))
        return false
    }

    ; Shift lock on for the fight -> true when confirmed (logged either way).
    _ShiftOn(ctx) {
        if Input.ShiftLock(true, this._env.io, ctx) {
            this._env.Log("minions: shift lock on")
            return true
        }
        if !ctx.ShouldStop()
            this._env.Log("minions: shift lock not confirmed - aiming with w taps")
        return false
    }

    ; Shift lock off (CleanupCtx: after a preempt too). Not confirmed off (a
    ; halt sends nothing) -> owed: the next Run turns it off first.
    _ShiftOff(ctx) {
        env := this._env
        this._lock := false
        if !Input.CanShiftLock(env.io)
            return
        if Input.ShiftLock(false, env.io, CleanupCtx(ctx)) {
            if this._lockOwed || this._lockTried
                env.Log("minions: shift lock off")
            this._lockOwed := false
            return
        }
        this._lockOwed := true
        env.Log("minions: shift lock may still be on (" (CleanupCtx.Halted(ctx) ? "halted" : "not confirmed off") ") - turned off before the next hunt")
    }

    ; Before a step that clicks (what: the storage, the respawn menu): with
    ; shift lock on every click lands at the screen centre (live 2026-11-02:
    ; the Donation purchase prompt). Owed (_ShiftOff not confirmed) -> one
    ; more try; still owed -> false, logged: the step is skipped, not
    ; clicked.
    _ClickOk(ctx, what) {
        if this._lockOwed
            this._ShiftOff(ctx)
        if !this._lockOwed
            return true
        this._env.Log("minions: shift lock may still be on - " what " skipped (no click)")
        return false
    }

    ; The camera of the hand fights (zoomed far out, pitched down: BesideOrbW
    ; assumes it), once a hunt and again after a death: pitched to its limit
    ; first, then zoomed out to the end, in five notches, and pitched back
    ; a little (live 2026-11-03, the same view from 5 scrambled starts; zoom
    ; before pitch gave a closer view from 2 of 4). Mouse pitch needs shift
    ; lock on, so not without it; no click in it. ~1.6 s (was ~3.5 s: the
    ; pitch down overshoots, so big steps; the zoom out has notches to spare,
    ; so a short gap; the settles cut, GUESSED; the notches in and the steps
    ; back set the view: as many, as big as live, the notches as far apart).
    ; The 1 ms timer on: a Sleep of 16 ms is ~31 ms else. -> false = stopped.
    _FightCamera(ctx) {
        env := this._env
        if !this._lock {
            if !ctx.ShouldStop()
                env.Log("minions: no shift lock - the camera left as it is")
            return !ctx.ShouldStop()
        }
        Input.HiRes(true)
        try
            return this._CameraSteps(ctx)
        finally
            Input.HiRes(false)
    }

    _CameraSteps(ctx) {
        env := this._env, io := Input._Backend(env.io)
        Loop MinionsTask.CamPitchSteps {
            io.Look(0, MinionsTask.CamPitchPx)
            if !env.Wait(MinionsTask.CamLookGapMs, ctx)
                return false
        }
        if !env.Wait(100, ctx)
            return false
        Loop MinionsTask.CamZoomOut {
            io.Wheel("down", 1, 0)
            if !env.Wait(25, ctx)
                return false
        }
        if !env.Wait(200, ctx)
            return false
        Loop MinionsTask.CamZoomIn {
            io.Wheel("up", 1, 0)
            if !env.Wait(60, ctx)
                return false
        }
        if !env.Wait(100, ctx)
            return false
        Loop MinionsTask.CamBackSteps {
            io.Look(0, -MinionsTask.CamBackPx)
            if !env.Wait(MinionsTask.CamLookGapMs, ctx)
                return false
        }
        env.Log("minions: fight camera set")
        return true
    }

    ; The fight: however it ends (an error too) no move stays held.
    _Fight(ctx) {
        try
            return this._FightRun(ctx)
        finally
            this._Stop()
    }

    _FightRun(ctx) {
        env := this._env
        maxMs := (this._boss ? MinionsTask.BossMaxSec : MinionsTask.Secs(env.cfg.Get("Minions.maxSec", MinionsTask.MaxSec))) * 1000
        start := env.Now()
        f := {maxSeen: 0, down: 0, waits: 0, deaths: 0, casts: 0, orbDown: 0, how: "", biomeGone: false
            , last: [], shift: 0, barAt: "", lastSeen: this._boss ? start : "", seen: false   ; BossLook just saw it
            , standing: false, foes: [], foeAt: 0, dodges: 0, stepped: false, lowAt: 0, castEnd: 0, fillAt: "", orbFill: "", orbAt: 0, orbReads: [], orbBearing: "", toast: ""
            , blockedTo: 0, vTry: 0, vPts: 0, vOff: 0, orbHurt: false, hurtFirst: "", hurtFirstAt: 0, loneFoe: false, orbHigh: false, menuLooked: false, promptSaid: false, patrol: false, pLeg: 0, pLeft: 0
            , prev: "", stuck: 0, esc: 0, wall: "", wallOff: "", avoid: "", tLast: "", lookedBack: false, lost: MinionsTask.LostLooks, peek: 0
            , empty: 0, rewaited: false, gAvoid: "", gAt: "", gStuck: 0, gEsc: 0, gWall: "", glowing: false
            , gLast: "", gMiss: 0, gTurned: false, gNudged: false
            ; the bearing (this._bearing) a bar or glow was seen at last, and
            ; the walk back to it (ReturnWalks; backed: done since that
            ; sighting); given up on too soon (Pursue): walks back to the
            ; bearing again in a PursueStyles way (pursued: rounds since the
            ; sighting at pSeen; pWalks left, pTurn: turn first); not after
            ; a fight at hand (nearAt: when one was seen last)
            , fightBearing: "", back: 0, backTurn: false, backed: false
            , pursued: 0, pSeen: -1, pWalks: 0, pTurn: false, pStyle: "", nearAt: ""
            ; out of reach (_BackOff): since, the walk back's end, no walk in till; HP logged (_HpNote)
            , offAt: 0, offEnd: 0, offHold: 0, hpSaid: -1, hpSaidAt: 0}
        this._hpLog := [], this._held := ""
        ; down: minion toasts in this biome, a hunt before this one's too
        ; (Open); kills: this hunt's. here: beside the fight in this life
        ; (Stay); stayAt: the last look round for it ended; hurtAt: a bar
        ; last read hurt or the fill fell (HuntOn); past: the time ran out
        f.down := this._biomeDown, f.kills := 0, f.boss := this._boss, f.here := false, f.stayAt := 0, f.hurtAt := "", f.past := false
        ; time on one side of the dodge (DodgeKey); a tick's end, what it took (_Timed)
        f.dodgeMs := 0, f.dodgeKey := "", f.backAt := 0, f.tickEnd := start, f.look := 0, f.atBars := false
        f.ticks := {fight: {n: 0, ms: 0, look: 0, parts: MinionsTask._NoParts()}, seek: {n: 0, ms: 0, look: 0, parts: MinionsTask._NoParts()}}
        this._TickStart(start)
        ; the way to the fight (_TrailRoute) and its next step (0: no replay on)
        f.route := [], f.replay := 0
        ; where the fight is (_FightSeen) and the way back to it (_HomeStart)
        f.fightPos := "", f.fightFace := 0, f.fightFar := 0, f.fightAt := "", f.home := 0, f.homeTo := "", f.homeWalks := ""
        f.ring := 0, f.ringAt := 0, f.ringFor := ""
        ; the fight's spot ("" = none yet), the last one looked at, why a
        ; stored route is on ("" = none: bar, glow, due, death), it met an
        ; edge, it led here, the blind one of this hunt spent
        f.spot := "", f.spotAt := 0, f.rWhy := "", f.rEdge := false, f.rUsed := false, f.rTried := false
        this._RoutesRead()
        this._trail := [], this._trailTo := 0, this._trailB := "", this._aimed := true
        if (!IsObject(this._respawnLog) && !IsObject(this._scanFn))
            this._respawnLog := RespawnTail()
        this._RespawnSync()                      ; the hunt's own reset is no death
        ; the equipped aura's skills from its panel (MinionSkills; a known
        ; aura has its layout whatever the panel reads: no read)
        this._eden := ObbyTask.SameAura(this._swap.wear, "Eden")
        hud := MinionsTask.Auras.Has(StrLower(Trim(this._swap.wear))) ? "" : this._Hud()
        book := MinionSkills(this._swap.wear, IsObject(hud) ? hud.rows : "", this._learnt)
        env.Log("minions: skills " book.how " (" MinionsTask._Join(book.keys) ")")
        checked := start, viewed := start
        b0 := this._BiomeNow(), bChecked := start, f.b0 := b0
        ; read after the set-up (~3 s): a hunt started at a biome's very end
        ; has the next one here, no change would ever show and it would walk
        ; there for maxSec. Unknown: as ever, nothing ends on it.
        if (b0 != "" && !(this._boss ? b0 = MinionsTask.BossBiome : this._Huntable(b0)))
            this._BiomeGone(f, this._biome, b0)
        a := ""
        try a := (this._swap._auraFn)()
        this._logAura := IsObject(a) ? a.name : ""
        while (!f.biomeGone && (env.Now() - start < maxMs || (!this._boss && MinionsTask.HuntOn(f, env.Now(), env.Now() - start)))) {
            if ctx.ShouldStop()
                break
            if (!f.past && env.Now() - start >= maxMs) {
                f.past := true
                env.Log("minions: past the hunt's time - " (MinionsTask.Open(f) ? "the orb is open" : "a bar was hurt lately") ", staying on")
            }
            ; orbs despawn with the biome, and an event biome's lanterns
            ; read as bars (2026-11-02: SNOWY -> PUMPKIN MOON mid-hunt).
            ; Bars or casts do not keep it going: 0 of 11 stays on a fight's
            ; bars (L47-L51, BiomeOnMs, gone) had a bar within 3 s after, and
            ; L51 23:02:37 then wandered 92 s. Clips: the orb left at the
            ; log's change within about 1 s (13:55:48, 12:40:32).
            if (env.Now() - bChecked >= MinionsTask.BiomeCheckMs) {
                bChecked := env.Now()
                b := this._BiomeNow()
                if MinionsTask.BiomeLeft(b0, b) {
                    this._BiomeGone(f, b0, b)
                    break
                }
            }
            if (env.Now() - checked >= MinionsTask.AuraCheckMs) {
                checked := env.Now()
                if !this._KeepAura(ctx)
                    break
            }
            if (env.Now() - viewed >= MinionsTask.ViewCheckMs) {
                viewed := env.Now()
                if !this._ClearView(ctx)
                    break
            }
            ; a death (_DeathSeen: the log, the death screen, or the HP: low,
            ; then back up at spawn): the old spots mean nothing; re-aimed, back
            ; the way the fight was (clips L19 SNOWY 042511, RAINY 041829: deaths
            ; never noticed, 10 s of skills at spawn)
            this._Mark("chk")
            this._Snap()                         ; one copy of the screen for this tick's readers
            this._Mark("cap")
            why := this._DeathSeen()
            this._Mark("death")
            if (why != "") {
                this._SnapEnd()
                if !this._Died(ctx, f, why)
                    break
                continue
            }
            this._HpNote(f, env.Now())
            if !this._Timed(ctx, f, book)
                break
        }
        this._Stop()
        this._TickLog(f)
        sweep := {left: 0, orb: 0}
        if (!f.biomeGone && !ctx.ShouldStop() && f.how != "toast")
            sweep := this._Sweep(ctx, f.last, f.shift)
        orbDown := (f.orbDown && !sweep.orb) ? 1 : 0     ; an orb in the sweep is not down
        down := orbDown ? f.kills + 1 : f.kills
        if orbDown
            this._biomeDown := 0                 ; the next orb has its own minions
        env.Log(MinionsTask.Stats(f.maxSeen, down, f.waits, env.Now() - start, sweep.left, sweep.orb, orbDown
            , f.casts, f.orbFill, f.deaths, orbDown ? f.how : "", this._boss ? 1 : 0))
        return down
    }

    ; The hunt's biome ended (b0 -> b): so does the hunt. The new biome is
    ; fresh: not counted as hunted, its search empty (CanRun will not see it
    ; change: _biome is set here).
    _BiomeGone(f, b0, b) {
        this._env.Log("minions: the biome changed (" b0 " -> " b ") - hunt over")
        this._BiomeStart(b)
        f.biomeGone := true
    }

    ; A death seen (why): back at spawn. No bar in sight lately and the HP
    ; never low: walked off the island (Fell) -> that way kept as its edge
    ; (FallAhead, FallOut), no walk back by it. The way the fight was: replayed from
    ; spawn (_TrailRoute, _Replay; a fall's tail dropped); no trail, or a
    ; wandering one (LineBeats): straight to where it was; a fight long over
    ; or no position: by its bearing. A fight on: then a look from where it
    ; was and round it (_HomeStep, _RingStep). -> false = stopped.
    _Died(ctx, f, why) {
        env := this._env
        this._Stop()
        f.deaths++
        if f.boss
            this._sin.Died()
        fell := MinionsTask.Fell(f.barAt, env.Now(), MinionsTask.WasHurt(this._hpLog))   ; _AfterDeath clears that log
        if (fell && f.replay && f.rWhy != "")
            this._RouteFailed(f)
        this._TrailRoute(f, fell)
        stored := this._RouteBack(f, fell)
        open := IsObject(f.fightPos) && MinionsTask.FightOpen(env.Now(), f.fightAt)
        line := open && !fell && !stored && MinionsTask.LineBeats(f.route, f.fightPos)
        if fell {
            w := MinionsTask.FallOut(this._FallWay())
            this._falls.Push({x: w.x, y: w.y, b: w.b, at: env.Now()})
            env.Log("minions: died (" why ") with no bar in sight - fell off the island? That way (bearing " w.b " ms"
                . (w.HasOwnProp("faced") ? " out from spawn, not the " w.faced " ms faced back to it" : "")
                . ", " MinionsTask.Along(w, w.b) " ms out) is kept as the edge; no walk back by it")
        } else
            env.Log("minions: died (" why ") - back at spawn, " (line ? "going straight back to the fight" : f.route.Length ? "replaying the trail"
                : "walking back by bearing " (f.fightBearing = "" ? "none" : f.fightBearing " ms")))
        if !this._AfterDeath(ctx, why)
            return false
        this._RespawnSync()                      ; this death's own lines (a black frame comes first)
        f.home := 0, f.ring := 0, f.ringAt := 0, f.ringFor := fell ? f.fightAt : f.ringFor
        walk := ""                               ; ms of walk back to the fight ("" = not known)
        if (f.route.Length && this._aimed && !line) {
            f.replay := 1, f.back := 0, f.backed := true, f.rWhy := stored ? "death" : "", f.rUsed := stored
            walk := MinionsTask.TrailMs(f.route)
            env.Log("minions: back to the fight - replaying the " (stored ? "stored route" : "trail") ", " f.route.Length " steps, " walk " ms")
        } else if (line && this._aimed) {
            f.back := 0, f.backed := true
            walk := MinionsTask.Gap({x: 0, y: 0}, f.fightPos)
            env.Log("minions: back to the fight - straight out, " Round(walk) " ms, facing bearing " Round(MinionsTask.Wrap(f.fightFace)) " ms")
        } else if (f.fightBearing != "" && !fell)
            f.back := MinionsTask.ReturnWalks, f.backTurn := true, f.backed := true
        if (open && this._aimed && (line || f.replay))
            this._HomeStart(f, fell)
        if fell
            f.fightBearing := ""
        ; no fight to go back to (a fall with no trail, nothing known): the
        ; search starts from spawn, no wait for the HP
        nowhere := walk = "" && (fell || (!IsObject(f.fightPos) && f.fightBearing = ""))
        if (!nowhere && !this._Regen(ctx, f, walk))
            return false
        f.standing := false, f.prev := "", f.stuck := 0, f.esc := 0, f.wall := "", f.tLast := "", f.lookedBack := false
        f.avoid := "", f.wallOff := "", f.lost := MinionsTask.LostLooks, f.empty := 0, f.last := [], f.shift := 0, f.glowing := false
        f.gLast := "", f.gWall := "", f.orbBearing := "", f.pLeg := 0, f.pLeft := 0, f.offAt := 0, f.offEnd := 0, f.offHold := 0
        f.here := false                          ; far from it now: the way back is walked
        f.tickEnd := env.Now()
        this._TickStart(f.tickEnd)
        return true
    }

    ; One _FightStep, timed from the last tick's end (the checks before it
    ; and its looks are in it: _TickLog). A move held that no step of this
    ; tick asked for goes up. -> false = over.
    _Timed(ctx, f, book) {
        env := this._env
        this._tick++, f.look := 0, f.atBars := false
        try ok := this._FightStep(ctx, f, book)
        finally
            this._SnapEnd()
        if (IsObject(this._held) && this._held.tick != this._tick)
            this._Stop()
        this._Mark("rest")
        s := f.atBars ? f.ticks.fight : f.ticks.seek, now := env.Now()
        s.n++, s.ms += now - f.tickEnd, s.look += f.look, f.tickEnd := now
        for k, v in this._parts.OwnProps()
            s.parts.%k% += v
        this._TickStart(now)
        return ok
    }

    ; ms of a tick by part: checks (biome, aura, menus), the screen copy, the
    ; death readers, bars, toast, skill panel, OCR, the rest (keys, waits).
    static _NoParts() => {chk: 0, cap: 0, death: 0, scan: 0, toast: 0, hud: 0, ocr: 0, rest: 0}

    _TickStart(now) {
        this._tickAt := now, this._partAt := now, this._parts := MinionsTask._NoParts()
    }

    ; The time since the last _Mark goes to part.
    _Mark(part) {
        now := this._env.Now()
        this._parts.%part% += now - this._partAt
        this._partAt := now
    }

    ; What is left of a tick of FightTickMs, the looks in it.
    _TickLeft() => this._tickAt = "" ? MinionsTask.FightTickMs : Max(0, MinionsTask.FightTickMs - (this._env.Now() - this._tickAt))

    ; The readers from here on share one copy of the screen (ScreenFrame; a
    ; grab dep has none). -> true = taken here, already held or none: false.
    _Snap() {
        g := this._grab
        if (!HasMethod(g, "Hold") || g.Held)
            return false
        try g.Hold()
        catch
            return false
        return true
    }

    _SnapEnd() {
        if HasMethod(this._grab, "Let")
            this._grab.Let()
    }

    ; Once a hunt: what a fight tick and a seek step take, and how much of
    ; that goes to the screen grabs (the keys stay held through them).
    _TickLog(f) {
        a := f.ticks.fight, b := f.ticks.seek
        this._env.Log("minions: tick " (a.n ? a.ms // a.n : 0) " ms fighting (" a.n " ticks, looks " (a.n ? a.look // a.n : 0) " ms), "
            . (b.n ? b.ms // b.n : 0) " ms seeking (" b.n " steps, looks " (b.n ? b.look // b.n : 0) " ms); per tick fighting "
            . MinionsTask._PartsText(a) ", seeking " MinionsTask._PartsText(b))
    }

    static _PartsText(s) {
        t := "", p := s.parts
        for k in ["chk", "cap", "death", "scan", "toast", "hud", "ocr", "rest"]
            t .= (A_Index > 1 ? " " : "") k " " (s.n ? p.%k% // s.n : 0)
        return t
    }

    ; One look at the fight: the bars, the toasts, then one step: a cast
    ; beside the orb, a walk to it, or the look for it. -> false = over.
    _FightStep(ctx, f, book) {
        env := this._env, now := env.Now()
        raw := this._Scan()
        this._Mark("scan")
        if raw.Length
            f.barAt := now
        sh := f.shift, f.shift := 0              ; px the last turn moved the screen
        if IsObject(f.gAvoid)
            f.gAvoid.x += sh
        if IsObject(f.tLast) {
            f.tLast.x += sh
            if IsObject(tm := MinionsTask.Match(raw, f.tLast))   ; seen once (unconfirmed) still moves it
                f.tLast.x := tm.x, f.tLast.y := tm.y
        }
        if IsObject(f.gLast)
            f.gLast.x += sh
        ; a dodge step or a turn moves every bar by px not known well: the scan
        ; after it stands alone (L34 08:03:47-08:04:11: a real orb 30 s in sight,
        ; each turn to it unconfirmed the bar, the look round turned it away again)
        bars := (f.stepped || sh) ? raw : MinionsTask.Confirmed(raw, f.last, sh), f.last := raw, f.stepped := false
        f.maxSeen := Max(f.maxSeen, bars.Length)
        hidden := false                          ; only the target given up on is in sight
        if IsObject(f.avoid) {
            if (now >= f.avoid.until)
                f.avoid := ""
            else {
                r := MinionsTask.Without(bars, f.avoid, sh)
                if IsObject(r.match)
                    f.avoid.x := r.match.x, f.avoid.y := r.match.y
                else
                    f.avoid.x += sh
                hidden := IsObject(r.match) && !r.bars.Length
                bars := r.bars
            }
        }
        if IsObject(f.wallOff) {
            if (now >= f.wallOff.until)
                f.wallOff := ""
            else if bars.Length {
                bars := MinionsTask.OffWall(bars, f.wallOff, this._bearing)
                hidden := hidden || (!bars.Length && !f.patrol)
            }
        }
        ; a kill by the toast behind the skill rows, whatever the bars read
        t := this._Toast()
        this._Mark("toast")
        ; never with minion bars up: stacked Orb Minion Awards read as Orb Awards (L57 12:44:53)
        if (t = "orb" && f.casts && raw.Length <= 1) {
            env.Log("minions: Orb Awards toast - the orb is down")
            f.orbDown := 1, f.how := "toast"
            if f.boss
                this._sin.Killed("an award toast")
            return false
        }
        if (t = "minion" && f.toast != "minion") {
            f.kills++, this._biomeDown := ++f.down, f.loneFoe := false
            if (f.down = MinionsTask.OpenDown)
                env.Log("minions: " f.down " minions down - the orb is open")
        }
        f.toast := t
        if f.boss
            this._SinNote(raw, bars, now)
        v := MinionsTask.View(bars, MinionsTask.Stay(f))
        was := f.orbFill
        if IsObject(v.orb)
            f.orbBearing := this._bearing
        ; minions seen: a lone bar may be the last near one read as the orb
        ; (OrbLonePx) till a minion toast or a whole orb read (OrbHurtStep)
        if v.minions.Length
            f.loneFoe := true
        ; a minion in the same view: the orb is Locked and cannot be hurt, a
        ; low read is a misread plate or a minion (L51 22:19:26 orb=0.05
        ; minions=1.00,1.00,0.39)
        if (IsObject(v.orb) && !v.minions.Length) {
            f.orbAt := now, f.orbFill := MinionsTask.FillOf(v.orb), f.orbHigh := MinionsTask.Above(v.orb, true)
            if (f.orbFill > MinionsTask.HurtOpenFill)
                f.loneFoe := false
            if (!f.foes.Length && !f.loneFoe)
                MinionsTask.OrbRead(f, f.orbFill)
            if (!f.orbHurt && MinionsTask.OrbHurtStep(f, f.orbFill, now))
                env.Log("minions: the orb's bar went down to " f.orbFill " - it can be hurt: open")
        }
        if (MinionsTask.Hurt(v) || (was != "" && f.orbFill < was))
            f.hurtAt := now
        this._LogFill(f, v, now)
        f.ahead := !v.minions.Length || MinionsTask.InFront(v)
        f.atBars := IsObject(v.anchor)
        hud := (f.atBars || f.standing) ? this._Hud() : ""   ; no skill while seeking: no panel to read
        this._Mark("hud")
        this._SnapEnd()                              ; keys and turns from here: what is read next is new
        f.look := env.Now() - f.tickEnd
        if IsObject(v.anchor)
            return this._AtBars(ctx, f, book, v, hud)
        if hidden {
            ; out of reach: look elsewhere (not a scan with nothing: no
            ; respawn wait, no give up)
            this._Stop()
            f.shift := this._Turn("Left", MinionsTask.ScanTurnMs)
            return true
        }
        ; the orb nearly dead: its bar's yellow gets too short to read (L47 16:50:30,
        ; fill 0.05, then bars gone, a look round, the kill lost). Stay and cast
        if (MinionsTask.OrbNearlyDead(f, now) && !f.orbHigh)     ; not under a rooftop orb (Above)
            f.standing := true
        if !f.standing {
            if MinionsTask.Stay(f)
                return this._OpenLook(ctx, f, raw)
            return this._Seek(ctx, f, raw)
        }
        ; beside the fight and no bar: a menu first (it washes the plates
        ; out as a flash does), looked for once per stretch without bars.
        if !f.menuLooked {
            f.menuLooked := true
            if !this._ClearView(ctx)
                return false
        }
        ; Else a flash, a low bar, the camera swung. Skills on at the same
        ; aim, then none for ClearMs so the screen clears: still nothing =
        ; the plate is gone. No kill without the toast, however low the orb
        ; read: a look round for it (the toast, read every tick, ends it)
        stay := MinionsTask.Stay(f)
        low := MinionsTask.OrbNearlyDead(f, now)
        blind := stay ? MinionsTask.OpenStayMs : low ? MinionsTask.OrbLowMs : MinionsTask.BlindCastMs
        last := stay ? Max(f.barAt, f.stayAt) : f.barAt
        if (now - last < blind)
            return this._Cast(ctx, f, book, hud, false)
        if (now < Max(last + blind, f.castEnd) + MinionsTask.ClearMs)
            return this._Idle(ctx)
        f.standing := false
        hp := MinionsTask.OrbHp(f)
        if (hp != "" && hp <= MinionsTask.OrbLowFill && MinionsTask.Unlocked(f))
            env.Log("minions: the orb's plate is gone at fill " hp " - no Orb Awards toast, not down: looking round for it")
        else
            env.Log("minions: no plate since the screen cleared - looking again")
        ; a circle from here, no walk: the walk back left a hurt orb behind and
        ; ran off the edge (9 uses, 2 falls, L44-L51)
        f.backed := true
        return this._HomeStart(f, true)
    }

    ; The orb open, beside it (Stay), no bar and no stand on: a circle where
    ; it stands, no patrol, no glow, no step (L47 16:54:36: the look round
    ; walked off a hurt orb), then the way it was and skills on: the stand of
    ; _FightStep, OpenStayMs from here. -> false = stopped.
    _OpenLook(ctx, f, raw) {
        if (raw.Length && ++f.peek <= MinionsTask.PeekLooks)
            return this._Keep()
        if (++f.lost <= MinionsTask.LostLooks)
            return this._Keep()
        if ((!f.home && !f.ring) || (f.home && IsObject(f.homeTo)))
            this._HomeStart(f, true)
        if f.home
            return this._HomeStep(ctx, f)
        at := f.fightAt, f.ringAt := MinionsTask.RingPoints
        ok := this._RingStep(ctx, f)
        if f.ring
            return ok
        f.fightAt := at, f.patrol := false       ; the fight is here still
        face := IsObject(f.fightPos) ? f.fightFace : f.orbBearing
        if (face != "" && MinionsTask.Wrap(face - this._bearing))
            f.shift := this._TurnBy(ctx, face - this._bearing)
        f.standing := true, f.stayAt := this._env.Now(), f.menuLooked := false, f.peek := 0, f.lost := 0
        this._env.Log("minions: the orb is open - facing it, skills on")
        return !ctx.ShouldStop()
    }

    ; Bars in sight (v: View's): the orb (else the nearest minion) kept
    ; ahead; any of them beside the player -> stand there and cast, else
    ; a step to it.
    _AtBars(ctx, f, book, v, hud) {
        env := this._env, now := env.Now(), bar := v.anchor
        if (f.empty > 0 || !f.seen)
            env.Log("minions: target at " bar.x "," bar.y " (bar " bar.w " px) - bearing " this._bearing " ms")
        f.empty := 0, f.lost := 0, f.seen := true, f.peek := 0, f.lastSeen := now, f.glowing := false, f.gWall := ""
        f.tLast := {x: bar.x, y: bar.y}, f.lookedBack := false, f.gLast := "", f.gMiss := 0
        f.fightBearing := this._bearing, f.back := 0, f.backed := false, f.menuLooked := false
        this._FightSeen(f, bar, IsObject(v.orb) && bar = v.orb)
        if this._RouteBar(f, v, bar)
            return this._RouteStep(ctx, f, true)
        this._TrailSeen(f)
        close := MinionsTask.Close(v)
        qin := MinionsTask.QReach(v)             ; Impale's gap fill: a minion in reach, never the orb alone
        if v.minions.Length
            f.foes := v.minions, f.foeAt := now
        else if (now - f.foeAt >= MinionsTask.DodgeHoldMs)
            f.foes := []
        if (close && f.stuck >= MinionsTask.StuckWalks && now >= f.blockedTo) {
            env.Log("minions: a minion in the way - standing and casting")
            f.blockedTo := now + MinionsTask.BlockedMs
        }
        ; at a wall a stand ends: no looser Beside, _Below counts them
        beside := (MinionsTask.OrbNearlyDead(f, now) && !MinionsTask.Above(v.orb, true)) || MinionsTask.Beside(v, f.standing && !IsObject(f.wall)) || (close && now < f.blockedTo) || this._Below(f.wall, v, now, !MinionsTask.Unlocked(f))
        if (beside && IsObject(this._held) && this._held.key = "w")
            this._Stop()                         ; arrived: not on past it through the turn and the cast
        if !book.Rooted(now) {
            lock := beside || v.minions.Length
            aim := lock ? MinionsTask.AimAt(v) : {x: bar.x, tol: MinionsTask.AimTol}
            ; beside it the skills leave the character, not the screen's centre
            turn := MinionsTask.TurnFor(aim.x, aim.tol, lock ? MinionsTask.LockPxPerMs : "", lock ? MinionsTask.LockX : "")
            if (turn.ms > 0)
                f.shift := this._Turn(turn.key, turn.ms)
        }
        ; hit hard: out of reach first (the aim above faces what it backs from)
        if ((off := this._BackOff(ctx, f, book, hud, v, qin, beside)) != "")
            return off
        if beside {
            if !f.standing {
                env.Log("minions: beside it (bar " bar.w " px) - standing and casting" MinionsTask.BarNote(bar))
                this._Flush()                    ; the walk here, on the trail
                this._RouteLearn(f)
            }
            if (IsObject(f.wall) && IsObject(v.orb) && MinionsTask.Beside(v))    ; the way up (a minion that came down: none)
                this._WallFound(f.wall), f.wall := ""
            f.standing := true, f.nearAt := now, f.stuck := 0, f.esc := 0, f.prev := ""
            f.here := true
            if (!f.foes.Length && !book.Rooted(now) && now >= f.backAt && MinionsTask.OrbBehind(v)
                && this._DodgeOpen("s", "", MinionsTask.NearStepMs, now))
                return this._StepBack(ctx, f, v, now)
            return this._Cast(ctx, f, book, hud, qin)
        }
        f.standing := false
        this._HurtWalk(f, now)
        ; in reach but not beside: skills while walking (L32: 7 casts in 64 s, the
        ; cast waited for the stand; by hand: buttons all the way in)
        if (MinionsTask.InReach(v, !MinionsTask.Unlocked(f)) && !this._Press(ctx, f, book, hud, qin))
            return false
        if book.Rooted(now)
            return this._Idle(ctx)
        if (f.shift && !IsObject(f.wall))        ; turned: a look before the step (along a wall: kept on it)
            return this._Keep()
        ; along a wall: the bar shifts as the player moves, only nearer
        ; (WallGained) counts, as a way in
        if (IsObject(f.wall) && !f.wall.up) {
            f.wall.blind := 0
            if MinionsTask.WallGained(f.wall, bar) {
                env.Log("minions: wall - nearer, walking in (side " f.wall.side ")")
                f.wall.up := true, f.stuck := 0, f.esc := 0
            }
        } else if MinionsTask.Same(bar, f.prev)
            f.stuck++
        else if MinionsTask.Nearer(bar, f.prev)  ; only nearer is progress: an Escape's strafe moves the bar aside
            f.stuck := 0, f.esc := 0             ; (L66 04:08 RAINY: jump, strafe, from the start again for 60 s)
        f.prev := bar
        ; walking stopped making progress (a terrace wall: live 2026-10-31
        ; and a night clip 2026-11-02) -> the Escapes, each checked by the
        ; next scan, then (the target above) the wall slide; then that
        ; target is left for AvoidMs
        esc := f.esc, wall := f.wall
        this._toBar := true
        ok := this._Approach(ctx, f.stuck, &esc, &wall, bar, MinionsTask.Almost(v) ? MinionsTask.NearStepMs : "")
        this._toBar := false
        walled := IsObject(f.wall) && !IsObject(wall)
        f.esc := esc, f.wall := wall
        if (ok < 0) {
            env.Log("minions: still stuck at " bar.x "," bar.y " - giving up on it for " MinionsTask.AvoidMs // 1000 " s")
            f.avoid := {x: bar.x, y: bar.y, until: env.Now() + MinionsTask.AvoidMs}
            f.stuck := 0, f.esc := 0, f.prev := "", f.tLast := "", f.ringFor := f.fightAt
            if walled
                this._LeaveWall(ctx, f, bar.x)
            return true
        }
        return ok != 0
    }

    ; The map on foot: a square spiral out, Spiral's steps a leg, a quarter
    ; turn at each corner; bars and glows are looked for before every step,
    ; so any sighting ends it. A step that turned the player (_EdgeGuard) ends
    ; the leg: the rest of it would run back over cells just searched, the
    ; next way comes from PatrolHeading. It ends with the biome or the hunt's
    ; time.
    _PatrolStep(ctx, f) {
        if (IsObject(f.wallOff) && MinionsTask.OnWall(f.wallOff, this._bearing)) {
            f.shift := this._TurnBy(ctx, MinionsTask.FullTurnMs // 4)
            return true
        }
        k := MinionsTask.Cell(this._pos)
        this._searched[k] := (this._searched.Has(k) ? this._searched[k] : 0) + 1
        if (f.pLeft <= 0) {
            ; the least searched way next (the user, 2026-11-06: it kept going
            ; to the leaderboard, a place already searched)
            f.pLeg++, f.pLeft := MinionsTask.Spiral(f.pLeg)
            way := MinionsTask.PatrolHeading(this._pos, this._searched, this._falls, this._env.Now(), this._walls)
            if MinionsTask.Wrap(way - this._bearing) {
                f.shift := this._TurnBy(ctx, way - this._bearing)
                return true
            }
        }
        f.pLeft--, b := this._bearing
        this._patrolling := true
        try {
            return this._WalkOrSlide(ctx)
        } finally {
            this._patrolling := false
            if (this._bearing != b)
                f.pLeft := 0
        }
    }

    ; The next ready skill (book.Next; close: a minion in Impale's reach, QReach), or
    ; a tick of waiting: a cast runs out here, nothing else is pressed
    ; meanwhile. The Quest Board page up: closed, no skill behind it. The
    ; board's prompt up: not E. Nothing to press and no cast on: the tick is
    ; a dodge step (_Dodge). -> false = stopped.
    _Cast(ctx, f, book, hud, close) {
        env := this._env
        if !this._Press(ctx, f, book, hud, close)
            return false
        now := env.Now()
        ; moving through casts too (L31: standing for them, HP 100 -> 18% in 7 s;
        ; by hand 3 hits in 25 s on the move). Only Deadeye roots the player
        if (f.standing && f.foes.Length && !book.Rooted(now))
            return this._Dodge(ctx, f)
        return this._Idle(ctx)
    }

    ; The orb behind the player (OrbBehind): one short step back, the key up
    ; before the next cast, the next no sooner than OrbBehindGapMs. Off the
    ; trail, as a dodge is. -> false = stopped.
    _StepBack(ctx, f, v, now) {
        f.backAt := now + MinionsTask.OrbBehindGapMs, f.stepped := true
        this._env.Log("minions: the orb behind the player - a step back" MinionsTask.BarNote(v.orb))
        ok := this._Step("s", MinionsTask.NearStepMs, ctx, false)
        this._Stop()
        return ok
    }

    ; Hit hard with minions alive (HitHard over the HP reads since the last
    ; one): back out of their reach BackOffMs, the s key held tick to tick
    ; and skills on, then BackHoldMs of no walk in: casts and the strafe
    ; where it stands, unless a bar is beside (the stand goes on as ever). No
    ; step back where a fall is remembered, none into Deadeye's root.
    ; -> "" = not now (the tick goes on as before), else as a step: false = stopped.
    _BackOff(ctx, f, book, hud, v, close, beside) {
        env := this._env, now := env.Now()
        if (!v.minions.Length && !f.loneFoe)
            return ""                            ; the orb alone never hit anyone (a lone bar after minions: maybe the last one, near)
        ; one at a time, the hold over first; none with a minion behind: s walks into it
        if (now >= f.offHold && !book.Rooted(now) && !MinionsTask.AnyBehind(v) && IsObject(h := MinionsTask.HitHard(this._hpLog, now, f.offAt))
            && this._DodgeOpen("s", "", MinionsTask.BackOffMs, now)) {
            f.offAt := now, f.offEnd := now + MinionsTask.BackOffMs, f.offHold := f.offEnd + MinionsTask.BackHoldMs
            f.standing := false
            env.Log("minions: hp " Round(h.top * 100) "% -> " Round(h.hp * 100) "% in " Round(h.ms / 1000, 1) " s - backing out of reach ("
                . v.minions.Length " minion bar" (v.minions.Length = 1 ? "" : "s") " in sight)")
        }
        if (now < f.offEnd) {
            if !this._Press(ctx, f, book, hud, close)
                return false
            if book.Rooted(env.Now())
                return this._Idle(ctx)
            h := this._held, on := IsObject(h) && h.key = "s"
            f.stepped := true
            return this._Step("s", on ? MinionsTask.FightTickMs : this._TickLeft(), ctx, false)
        }
        if (now < f.offHold && !beside) {
            if (MinionsTask.InReach(v, !MinionsTask.Unlocked(f)) && !this._Press(ctx, f, book, hud, close))
                return false
            if (f.foes.Length && !book.Rooted(env.Now()))
                return this._Dodge(ctx, f)
            return this._Idle(ctx)
        }
        return ""
    }

    ; The player's HP in a fight (bars seen HpLogBarMs ago at most, or a
    ; stand on): logged at each HpLogDrop down, else every HpLogMs at most
    ; while it changes; no line at full HP (no bar). Deaths can be read
    ; against it.
    _HpNote(f, now) {
        n := this._hpLog.Length
        if (!n || (hp := this._hpLog[n].hp) < 0)
            return
        if !(f.standing || (f.barAt != "" && now - f.barAt <= MinionsTask.HpLogBarMs))
            return
        if (f.hpSaid >= 0 && hp > f.hpSaid - MinionsTask.HpLogDrop
            && (now - f.hpSaidAt < MinionsTask.HpLogMs || Abs(hp - f.hpSaid) < 0.03))
            return
        f.hpSaid := hp, f.hpSaidAt := now
        this._env.Log("minions: hp " Round(hp * 100) "% in the fight")
    }

    ; A tick of waiting, the player standing. -> false = stopped.
    _Idle(ctx) {
        this._Stop()
        return this._env.Wait(this._TickLeft(), ctx)
    }

    ; The next ready skill pressed, if any. -> false = stopped.
    _Press(ctx, f, book, hud, close) {
        env := this._env, io := env.io
        ; Voidrush for the open orb alone: deaths came 2-10 s after it among
        ; minions (L22, L32, L36), and spent early its 60 s kept Deadeye from the
        ; orb (L44 13:54:21, minions dead 13:55:07, no rank V, the biome won); 3 s
        ; after the last minion bar is no proof either, 6 of 11 V went into a
        ; Locked orb. By hand: V, rank V, Deadeye -102. A boss is never Locked
        eden := book.HasProp("eden") && book.eden && f.HasProp("foes")
        ; Not for a minion ahead either (tried for Deadeye's rank V): L66 + L71,
        ; 19 V that went among minions put the HP at 45% or under within 6 s
        ; 11 times (04:48:28 -> 37% 04:48:32, dead 04:48:46; 03:54:53 -> 8%,
        ; 04:00:13 -> 45%), the V the game refused at the same point of a fight
        ; 1-2 of 10; one Deadeye came of 69 V, its player dead 4 s later (05:42:07)
        no := (eden && !MinionsTask.Unlocked(f)) ? "v" : ""
        ; F is a cloud ahead, held till a minion is there (L58 13:02: 2 of 4 F on bare
        ; ground); E is a ring round the player, facing or not (L59: holding it cut the casts)
        if (eden && no != "" && f.HasOwnProp("ahead") && !f.ahead)
            no .= "f"
        ; a Voidrush the game refused: Charge stays, nothing cast, and its 5 s cast
        ; window blocked every other skill (L60 13:56:30-13:57:27, 5 presses, 100 points)
        if (eden && f.HasOwnProp("vTry")) {
            now := env.Now()
            pts := (IsObject(hud) && hud.HasOwnProp("points")) ? hud.points : -1
            ; read once its cast is over: Charge may drop only as it lands
            if (f.vTry && now >= f.castEnd + MinionsTask.VCheckMs && pts >= 0) {
                if (pts >= f.vPts) {
                    env.Log("minions: Voidrush did not go - no retry for " MinionsTask.VOffMs // 1000 " s")
                    f.vOff := now + MinionsTask.VOffMs
                }
                f.vTry := 0
            }
            if (now < f.vOff)
                no .= "v"
        }
        k := book.Next(hud, env.Now(), close, no)
        if (k != "" && this._QuestSeen())
            return this._ClearView(ctx)
        if (k = "e" && this._Prompt()) {
            if !f.promptSaid
                env.Log("minions: the Quest Board's prompt is up - no E here")
            f.promptSaid := true
            k := book.Next(hud, env.Now(), close, no "e")
        }
        if (k != "") {
            if book.Roots(k)                     ; no key held into the root
                this._Stop()
            ; face the way the camera does (shift lock does it; so does a walk held)
            if (!this._lock && !(IsObject(this._held) && this._held.key = "w"))
                Input.Key("w", MinionsTask.AimTapMs, io)
            Input.Key(k, 40, io)
            book.Pressed(k, hud, env.Now())
            f.casts++, f.castEnd := env.Now() + book.CastMs(k)
            if (k = "v" && eden && f.HasOwnProp("vTry"))
                f.vTry := env.Now(), f.vPts := (IsObject(hud) && hud.HasOwnProp("points")) ? hud.points : 0
            pts := (IsObject(hud) && hud.HasOwnProp("points")) ? hud.points : -1
            rank := (IsObject(hud) && hud.HasOwnProp("rank") && hud.rank != "") ? " rank " hud.rank : ""
            env.Log("minions: skill " k (pts >= 0 ? " (points " pts ")" : "") rank)
        }
        return true
    }

    ; One step out of the line of fire (DodgeKey: the side by the time spent
    ; on it, f.dodgeMs), else to the other side, else none and the key up: no
    ; step where the sea shows on that side or a fall is remembered
    ; (_DodgeOpen). The key stays held to the next tick, through its casts
    ; and turns. -> false = stopped.
    _Dodge(ctx, f) {
        env := this._env, now := env.Now()
        this._Settle()
        key := MinionsTask.DodgeKey(f.dodgeMs // MinionsTask.DodgeStepMs), f.dodges++
        view := this._View()
        for k in [key, key = "a" ? "d" : "a"]
            if this._DodgeOpen(k, view, MinionsTask.DodgeStepMs, now) {
                if (f.dodges = 1)
                    env.Log("minions: dodging between casts")
                if (k != f.dodgeKey)
                    env.Log("minions: dodge run " k)
                f.dodgeKey := k, f.stepped := true
                ; a tick long, not a whole step: the key stays down to the next tick
                ; and its look comes inside the move (DodgeKey goes by the time held)
                h := this._held, on := IsObject(h) && h.key = k, from := on ? h.at : now
                ok := this._Step(k, on ? MinionsTask.FightTickMs : this._TickLeft(), ctx, false)
                f.dodgeMs += env.Now() - from
                return ok
            }
        return this._Idle(ctx)
    }

    ; key ("a" / "d" / "s") is safe for ms from here. The view sees the sea
    ; at the legs' sides only: a step back is checked by the falls alone.
    _DodgeOpen(key, view, ms, now) {
        if MinionsTask.FallAhead(this._falls, this._pos, this._bearing + MinionsTask.DodgeOff(key), ms, now)
            return false
        if (key = "s" || !IsObject(view))
            return true
        side := key = "a" ? "edgeL" : "edgeR"
        return view.HasOwnProp(side) ? !view.%side% : !view.edge
    }

    ; The board's prompt reads now (one read; nothing to read with: no).
    _Prompt() {
        env := this._env
        if (!IsObject(env.ocrFn) && !HasMethod(env.io, "Ocr"))
            return false
        this._Mark("rest")
        up := RegExMatch(Input._Read(env.io, MinionsTask.PromptBox, env.ocrFn), MinionsTask.PromptRe) > 0
        this._Mark("ocr")
        return up
    }

    ; The Quest Board's page is up: one OCR every QuestEveryMs at most, not
    ; before each cast (_ClearView reads it too).
    _QuestSeen() {
        now := this._env.Now()
        if (now - this._questAt < MinionsTask.QuestEveryMs)
            return false
        this._questAt := now
        this._Mark("rest")
        ; the UGC Shop too: E opens it (L63 01:17:39, the orb behind it)
        ; and Jock's dialog: E opens it too (L72 04:32..04:55, over hunt after hunt)
        jock := this._jockAt = "" || now - this._jockAt >= MinionsTask.JockRetryMs   ; not right after a failed Leave
        up := this._swap.QuestUp() || (HasMethod(this._swap, "ShopUp") && this._swap.ShopUp())
            || (jock && HasMethod(this._swap, "JockUp") && this._swap.JockUp())
        this._Mark("ocr")
        return up
    }

    ; A step in with the HP at DeathLowHp or under: no side steps on the way
    ; (_Cast's are the stand's). Logged every FillEveryMs at most, so what that
    ; costs can be read off the deaths after it (it used to stop here under
    ; 30% and cast from there: L48 17:16:24-42, 18 s, 6 casts).
    _HurtWalk(f, now) {
        hp := MinionsTask.LastHp(this._hpLog, now)
        if (hp < 0 || hp > MinionsTask.DeathLowHp || now - f.lowAt < MinionsTask.FillEveryMs)
            return
        f.lowAt := now
        this._env.Log("minions: walking in at hp " Round(hp * 100) "%")
    }

    ; The orb's and the minions' bar fill, every FillEveryMs at most while
    ; any is in sight: damage per minute for whoever reads the log.
    _LogFill(f, v, now) {
        if (!IsObject(v.anchor) || (f.fillAt != "" && now - f.fillAt < MinionsTask.FillEveryMs))
            return
        f.fillAt := now
        s := ""
        for b in v.minions
            s .= (A_Index > 1 ? "," : "") MinionsTask.FillOf(b)
        this._env.Log("minions: fill orb=" (IsObject(v.orb) ? MinionsTask.FillOf(v.orb) : "-") " minions=" (s = "" ? "-" : s))
    }

    ; "orb" / "minion" / "" (Toast; the toast dep in tests; none with a fake
    ; scan and no dep: not the game's screen).
    _Toast() {
        if IsObject(this._toastFn)
            return (this._toastFn)()
        if IsObject(this._scanFn)
            return ""
        try return MinionsTask.Toast(this._grab)
        return ""
    }

    ; No bar in sight and not beside the fight: bars seen once looked at
    ; again, the target's last spot turned back to, then a far orb's glow,
    ; the way back to the fight, a look around. -> false = over.
    _Seek(ctx, f, raw) {
        env := this._env
        if (f.replay && f.rWhy != "")            ; a stored route: no bar near, on it goes
            return this._RouteStep(ctx, f, false)
        ; bars seen once: look again in place before anything else
        if (raw.Length && ++f.peek <= MinionsTask.PeekLooks)
            return this._Keep()
        ; a far bar flickers between scans: look again before turning away
        ; from where one was
        if (++f.lost <= MinionsTask.LostLooks)
            return this._Keep()
        ; the target's bar lost: once, a turn back to its last spot on
        ; screen, then looked for there in place
        if (IsObject(f.tLast) && !f.lookedBack) {
            f.lookedBack := true
            turn := MinionsTask.TurnFor(f.tLast.x)
            if (turn.ms > 0) {
                env.Log("minions: target lost at " f.tLast.x "," f.tLast.y " - turning back to it")
                f.shift := this._Turn(turn.key, turn.ms), f.lost := 0
                return true
            }
        }
        ; its bar lost along a wall: overhead, behind a ledge. A few steps
        ; on all the same, then no slide to it
        if (IsObject(f.wall) && !f.wall.up && ++f.wall.blind <= MinionsTask.WallBlindSteps) {
            wall := f.wall
            ok := this._WallStep(ctx, &wall)
            f.wall := wall
            return ok != 0
        }
        f.wall := ""
        ; a far target lost and looked for where it was on screen: walked to
        ; where it is (_FightSeen), the looks there, not a circle here first
        ; (L66 06:39:31: lost, a circle, then one more where the player stood)
        if (!f.replay && !f.home && f.fightFar > MinionsTask.HomeNearMs && this._FightLost(f)) {
            env.Log("minions: a far target lost - walking to it, " f.fightFar " ms")
            return this._HomeStart(f)
        }
        ; after a death: the way that led to the fight beats a far glow
        ; (L31 07:08:08: 30 s after one, then off the island)
        if f.replay
            return this._Replay(ctx, f)
        if f.home
            return this._HomeStep(ctx, f)
        ; no bar to read: a far orb's glow (OrbBeacon) -> turned to and
        ; walked to, the bars scanned again each step; walks that get no
        ; closer (GlowSame since gAt) -> the Escapes, then that glow is left
        ; for AvoidMs
        glows := this._Beacon()
        if IsObject(f.gAvoid) {
            if (env.Now() >= f.gAvoid.until)
                f.gAvoid := ""
            else {
                r := MinionsTask.Without(glows, f.gAvoid)
                if IsObject(r.match)
                    f.gAvoid.x := r.match.x, f.gAvoid.y := r.match.y
                glows := r.bars
            }
        }
        if IsObject(f.wallOff)
            glows := MinionsTask.OffWall(glows, f.wallOff, this._bearing)
        g := OrbBeacon.Pick(glows)
        if IsObject(g) {
            if this._RouteGlow(f, g)
                return this._RouteStep(ctx, f, false)
            if !f.glowing
                env.Log("minions: orb glow at " g.x "," g.y " (" g.r ") - walking to it (bearing " this._bearing " ms)")
            f.glowing := true, f.empty := 0, f.lastSeen := env.Now()
            f.fightBearing := this._bearing, f.back := 0, f.backed := false
            f.gLast := {x: g.x, y: g.y, r: g.r}, f.gMiss := 0, f.gTurned := false, f.gNudged := false
            turn := MinionsTask.GlowTurn(g.x)    ; to its side of the centre (not behind the character)
            if (turn.ms > 0) {
                f.shift := this._Turn(turn.key, turn.ms), f.gTurned := true
                return this._Keep()
            }
            ; along a wall: the glow lower or bigger = a way up
            gt := {y: g.y, w: 2 * g.r}
            if (IsObject(f.gWall) && !f.gWall.up) {
                if MinionsTask.WallGained(f.gWall, gt)
                    this._WallFound(f.gWall), f.gWall.up := true, f.gAt := g, f.gStuck := 0, f.gEsc := 0
            } else if MinionsTask.GlowSame(g, f.gAt)
                f.gStuck++
            else
                f.gAt := g, f.gStuck := 0, f.gEsc := 0
            esc := f.gEsc, wall := f.gWall
            ok := this._Approach(ctx, f.gStuck, &esc, &wall, gt)
            walled := IsObject(f.gWall) && !IsObject(wall)
            f.gEsc := esc, f.gWall := wall
            if (ok < 0) {
                env.Log("minions: still stuck at the glow " g.x "," g.y " - giving up on it for " MinionsTask.AvoidMs // 1000 " s")
                f.gAvoid := {x: g.x, y: g.y, until: env.Now() + MinionsTask.AvoidMs}
                f.gAt := "", f.gStuck := 0, f.gEsc := 0, f.glowing := false, f.gLast := ""
                if walled
                    this._LeaveWall(ctx, f, g.x)
                return true
            }
            return ok != 0
        }
        ; the glow gone from sight after a turn or a walk (behind the
        ; character, fog, a flicker): GlowLostLooks steps at its last spot
        ; (GlowTurn: a turn back to it, or aimed: a walk on) before it is
        ; forgotten and the hunt looks around
        if (IsObject(f.gLast) && ++f.gMiss <= MinionsTask.GlowLostLooks) {
            turn := MinionsTask.GlowTurn(f.gLast.x)
            ; lost right after the turn to it: the turn overshot, it hides
            ; behind the character -> a bit further out (GlowLost), then
            ; walked on (its last spot is a guess now: no turn back)
            nudge := (f.gMiss = 1 && f.gTurned && !turn.ms)
            if nudge
                turn := MinionsTask.GlowLost(f.gLast.x), f.gNudged := true
            else if f.gNudged
                turn := {key: "", ms: 0}
            f.gTurned := false
            if (f.gMiss = 1)
                env.Log("minions: glow out of sight at " f.gLast.x "," f.gLast.y " - " (nudge ? "turning a bit further out" : turn.ms ? "turning back to it" : "walking on"))
            if (turn.ms > 0) {
                f.shift := this._Turn(turn.key, turn.ms)
                return this._Keep()
            }
            return this._Walk(ctx)
        }
        f.gLast := "", f.gMiss := 0
        f.glowing := false, f.gWall := ""
        if f.ring
            return this._RingStep(ctx, f)
        ; a look around found nothing after a fight: turned to its bearing
        ; (the net turn since the respawn; the short way round, _TurnBy)
        ; and walked that way, the bars and glows scanned each step
        if (f.back > 0) {
            if f.backTurn {
                f.backTurn := false
                env.Log("minions: back to the fight - turning to bearing " f.fightBearing " ms")
                if MinionsTask.Wrap(f.fightBearing - this._bearing) {
                    f.shift := this._TurnBy(ctx, f.fightBearing - this._bearing)
                    return true
                }
            }
            f.back--
            return this._WayStep(ctx)
        }
        ; the walk back again, another way (Pursue)
        if (f.pWalks > 0 && f.lastSeen = f.pSeen) {
            if f.pTurn {
                f.pTurn := false
                if MinionsTask.Wrap(f.fightBearing - this._bearing) {
                    f.shift := this._TurnBy(ctx, f.fightBearing - this._bearing)
                    return true
                }
            }
            f.pWalks--
            return this._PursueStep(ctx, f.pStyle.side, MinionsTask.ReturnWalks - f.pWalks)
        }
        f.pWalks := 0
        if f.patrol {
            if this._FightLost(f)
                return this._HomeStart(f)
            return this._PatrolStep(ctx, f)
        }
        ; one circle from where it stands, then the map on foot (the user,
        ; 2026-11-05: orbs far from spawn were never seen)
        ; The circle first, a stored route too: 12 of 15 early sightings need it
        ; (L28: 1 fight in 14 hunts walking off at once, 3 of 11 looking from spawn)
        patrol := !this._boss && env.cfg.Get("Minions.patrol", 1)
        due := this._biomeAt = "" || env.Now() - this._biomeAt >= MinionsTask.PatrolAfterMs
        if (due && f.empty >= MinionsTask.SweepTurns && this._RouteDue(f))
            return this._RouteStep(ctx, f, false)
        if (patrol && due && f.empty >= MinionsTask.SweepTurns) {
            if this._FightLost(f)
                return this._HomeStart(f)
            env.Log("minions: nothing in sight - walking the map")
            f.patrol := true, f.pLeg := 0, f.pLeft := 0, f.empty := 0
            return true
        }
        if (++f.empty > MinionsTask.ScanTurns) {
            ; orbs come ~35-40 s into a biome: keep turning until OrbLateMs
            ; in (GiveUp). The boss is up from the start: BossQuietMs
            ; without a bar, the boss bar UI keeping it going (GUESSED: the
            ; boss is still up)
            if (this._boss && this._BossUi())
                f.lastSeen := env.Now()
            quit := this._boss ? MinionsTask.GiveUp(f.rewaited, env.Now(), "", f.lastSeen, MinionsTask.BossQuietMs)
                : MinionsTask.GiveUp(f.rewaited, env.Now(), this._biomeAt, f.lastSeen)
            ; a target seen not long ago (behind a ledge, a wall) and never
            ; reached (not beside, not left as stuck): after it again before
            ; giving up (Pursue)
            if (f.lastSeen != f.pSeen)
                f.pursued := 0
            left := (IsObject(f.avoid) && env.Now() < f.avoid.until) || (IsObject(f.gAvoid) && env.Now() < f.gAvoid.until)
            if (quit && !this._boss && f.fightBearing != "" && !left && f.lastSeen != f.nearAt
                && f.pursued < MinionsTask.PursueStyles.Length && MinionsTask.Pursue(env.Now(), f.lastSeen)) {
                f.pStyle := MinionsTask.PursueStyles[++f.pursued], f.pSeen := f.lastSeen
                f.pWalks := MinionsTask.ReturnWalks, f.pTurn := true, f.empty := 0
                env.Log("minions: a target seen " (env.Now() - f.lastSeen) // 1000 " s ago - after it again at bearing "
                    . f.fightBearing " ms, " f.pStyle.name " (" f.pursued "/" MinionsTask.PursueStyles.Length ")")
                return true
            }
            if quit {
                if this._boss
                    env.Log("minions: no boss in sight for " MinionsTask.BossQuietMs // 1000 " s - fight over")
                else if (this._biomeAt != "")
                    env.Log("minions: nothing in sight " MinionsTask.OrbLateMs // 1000 " s into the biome - giving up")
                return false
            }
            f.empty := 0, waited := false
            if (!f.rewaited && !patrol) {
                ; the minions hit back: a death respawns the player at spawn
                ; and every bar is gone meanwhile. Wait once for the respawn
                ; and look again (the user, 2026-11-01)
                f.rewaited := true, f.prev := "", f.stuck := 0, f.wall := "", f.waits++
                env.Log("minions: nothing in sight - waiting for a respawn, then looking again")
                ; the bearing stays: a respawn unseen is only a guess
                if !env.Wait(MinionsTask.DeathWaitMs, ctx)
                    return false
                waited := true
            }
            ; once per sighting: back the way the fight was
            if (f.fightBearing != "" && !f.backed)
                f.back := MinionsTask.ReturnWalks, f.backTurn := true, f.backed := true
            if (waited || f.back)
                return true
        }
        f.shift := this._SpotLook(ctx, f)
        return true
    }

    ; Put back off and the log already names the combat aura: no storage
    ; at all (live 2026-11-02: every hunt reopened it to check, ~15 s and
    ; its clicks). -> a swap result as _WearOnly, "" = swap (another aura
    ; or the log unknown).
    _AlreadyOn() {
        a := ""
        try a := (this._swap._auraFn)()
        if !(IsObject(a) && a.known && ObbyTask.SameAura(a.name, this._swap.wear))
            return ""
        ; ...and its skill panel on screen: 2026-11-09 21:24 no aura was on,
        ; Roblox's log still named Eden (it keeps the last one), the swap was
        ; skipped and the hunt fought with no skills
        if !this._PanelShows() {
            this._env.Log("minions: the log names " a.name " but no skill panel is on screen (no aura on?) - equipping " this._swap.wear)
            return ""
        }
        this._swap._owed := ""
        this._env.Log("minions: " this._swap.wear " already on")
        return {ok: true, had: true, prev: a.name, why: ""}
    }

    ; The equipped aura's skill panel is on screen (the screen itself, as
    ; Panel reads it): PanelMinRows rows or more (a toast can hide some). A
    ; scripted hud (tests: its empty rows mean "unread") or a read that
    ; fails is no proof against the log: true.
    _PanelShows() {
        if IsObject(this._hudFn)
            return true
        rows := "", took := this._Snap()
        try rows := MinionsTask.Panel(this._grab)
        if took
            this._SnapEnd()
        if !IsObject(rows)
            return true
        n := 0
        for r in rows
            n += IsObject(r) ? 1 : 0
        return n >= MinionsTask.PanelMinRows
    }

    ; Put back off: only the combat aura on (as PutOnSailor, without the
    ; aura from before having to be known; nothing is owed). prev = what the
    ; log said before, for _Confirm.
    _WearOnly(ctx) {
        sw := this._swap
        sw._owed := ""
        c := sw._AuraCal()
        if !IsObject(c)
            return {ok: false, had: false, prev: "", why: "the aura storage is not calibrated (Setup > Calibrate)"}
        cur := sw._Aura()
        r := sw._SetAura(c, sw.wear, true, CleanupCtx(ctx), &was)
        return {ok: r > 0, had: (was = "on"), prev: cur.known ? cur.name : "", why: (r < 0) ? "stopped" : sw._why}
    }

    ; The log must not name some third aura after the swap (2026-11-01:
    ; Luminosity went on for Eden). The log still naming the aura from
    ; before is a lag, not a failure. -> false = wrong aura (reported).
    _Confirm(ctx, sw) {
        env := this._env
        waited := 0
        Loop {
            a := ""
            try a := (this._swap._auraFn)()
            if (IsObject(a) && a.known) {
                if ObbyTask.SameAura(a.name, this._swap.wear)
                    return true
                if (a.name != "" && !ObbyTask.SameAura(a.name, sw.prev)) {
                    msg := a.name " went on instead of " this._swap.wear ": no hunt" (this._back ? " (put back)" : "")
                    env.Log("minions: " msg)
                    env.Report("errors", "Minions failed", msg, 0xE74C3C)
                    return false
                }
            }
            if (waited >= MinionsTask.ConfirmMs)
                return true
            if !env.Wait(250, ctx)
                return false
            waited += 250
        }
    }

    ; Auto roll equips a new aura (live 2026-10-31: "Plushed : Pumpkinity"
    ; replaced Eden), and then the skills do nothing. The log names the
    ; equipped aura: not the combat aura -> equipped again. -> false when
    ; that failed (the hunt ends; the aura from before still goes back).
    ; The log itself (not the swap's 150 s cache), and only a CHANGE counts:
    ; right after the swap it can still name the aura from before.
    _KeepAura(ctx) {
        cur := ""
        try cur := (this._swap._auraFn)()
        if (!IsObject(cur) || !cur.known)
            return true
        last := this._logAura, this._logAura := cur.name
        if (cur.name == last || ObbyTask.SameAura(cur.name, this._swap.wear))
            return true
        this._env.Log("minions: " cur.name " got equipped (auto roll?) - " this._swap.wear " on again")
        this._Stop()
        ; the storage is clicked: shift lock off around it, on again after
        if this._lockTried
            this._ShiftOff(ctx)
        if !this._ClickOk(ctx, "the aura re-equip")
            return false
        c := this._swap._AuraCal()
        ok := IsObject(c) && this._swap._SetAura(c, this._swap.wear, true, ctx) > 0
        if (ok && this._lockTried)
            this._lock := this._ShiftOn(ctx)
        log := this._respawnLog
        if IsObject(log)
            log.Seen := false, log.Poll()        ; what the log showed was for the aura before; these lines prove it again
        this._RespawnSync()                      ; a new aura binds its skills too
        return ok
    }

    ; A menu over the game (Aura Storage / Aura Collections / the Daily
    ; Rewards popup / the Quest Board page / Jock's dialog / a Roblox purchase prompt; live 2026-11-02 23:29: the storage stayed open over a
    ; whole hunt, which then ran blind): closed (ObbyTask.ClearView). A
    ; prompt goes with Esc; the others take a click, and one menu can hide
    ; another, so shift lock goes off first (it pins every click to the
    ; screen centre) and on again after. -> false = still up or not closed
    ; (logged): no fight
    _ClearView(ctx) {
        if CleanupCtx.Halted(ctx)                ; nothing sent (Roblox may not be in front)
            return false
        what := this._swap.Covered()
        if (what = "")
            return true
        this._spawnAt := 0
        this._env.Log("minions: the " what " screen is over the game - closing it")
        this._Stop()
        if this._lockTried
            this._ShiftOff(ctx)
        if !this._ClickOk(ctx, "closing the " what " screen")
            return false
        left := this._swap.ClearView(CleanupCtx(ctx))
        if (this._lockTried && !ctx.ShouldStop())
            this._lock := this._ShiftOn(ctx)
        ; Jock's dialog left up: the skills still go (L72: whole fights under
        ; it). L79 21:14:04 a failed Leave ended a fight with the minions at
        ; 5-15%: fight on, the next try JockRetryMs on (_QuestSeen)
        if (left = "jock dialog" && !ctx.ShouldStop()) {
            this._jockAt := this._env.Now()
            this._env.Log("minions: Jock's dialog stays up - fighting on under it")
            return true
        }
        return left = ""
    }

    ; From now on only new respawn lines count (RespawnTail)
    _RespawnSync() {
        if IsObject(this._respawnLog)
            this._respawnLog.Sync()
    }

    ; A death since the last look: a respawn in Roblox's log (RespawnTail: the
    ; black frame lasts ~0.5 s, a cast's wait passes it: L25 SNOWY 22:14:56,
    ; L26 22:41:59), the death screen now (DeathScreen; the death dep in
    ; tests), or a respawn told by the player's HP (Respawned over _hpLog, one
    ; read added here). The HP only while no log has shown it tells respawns
    ; (RespawnTail.Seen) or a newer log took over (a rejoin): a low read, then
    ; hurt frames unread, looks like one. L44..L51: 192 of 192 deaths by the
    ; log or the screen have a respawn line, about half of the 24 by the HP
    ; none (L48 17:32:06, :16, :25, no bind line 17:31:12-17:34:11), each
    ; 3.5-5 s stood still, Collections clicked, bearing and position gone.
    ; A real one the HP saw first comes through the log, 1-5 s on. Stale is a
    ; scan of the log folder: only for a respawn the HP told.
    ; -> "" or the evidence (logged). A fake scan with no death / hud /
    ; respawnLog dep: nothing read (not the game's screen).
    _DeathSeen() {
        env := this._env, now := env.Now(), log := this._respawnLog
        if (IsObject(log) && log.Poll())
            return "a respawn in the log"
        if IsObject(this._deathFn) {
            if (this._deathFn)()
                return MinionsTask.DeathScreenSeen
        } else if !IsObject(this._scanFn) {
            try {
                if MinionsTask.DeathScreen(this._grab)
                    return MinionsTask.DeathScreenSeen
            }
        }
        hp := this._PlayerHp()
        this._hpLog.Push({at: now, hp: hp})
        while (this._hpLog.Length > 1 && now - this._hpLog[1].at > MinionsTask.DeathHpMs)
            this._hpLog.RemoveAt(1)
        why := MinionsTask.Respawned(this._hpLog)
        if (why != "" && IsObject(log) && log.Seen && !log.Stale())
            return ""
        return why
    }

    ; The player's HP now (PlayerHp; the hud dep's playerHp in tests; a fake
    ; scan and no hud dep: -1, not the game's screen). 0..1, -1 = no bar.
    _PlayerHp() {
        if IsObject(this._hudFn) {
            h := (this._hudFn)()
            return (IsObject(h) && h.HasOwnProp("playerHp")) ? h.playerHp : -1
        }
        if IsObject(this._scanFn)
            return -1
        try return MinionsTask.PlayerHp(this._grab)
        return -1
    }

    ; After a death the player is back with the HP low (L70: ~27-39% at
    ; spawn, 5 deaths in 4 hunts) and walked straight back in: 2 hits from
    ; the next death. L66: 33 of ~60 deaths in fights came 15-57 s after the
    ; last one, 5-15 s into the fight again (03:20:40-03:28:20 nine in a row
    ; ~25 s apart, 03:33:45 -> 03:34:08 six seconds in; HP 25-37% walking in).
    ; So at spawn, out of the minions' reach, a wait till the HP reads
    ; ReturnHp less what the walk back (walk: ms, "" = not known) regains
    ; (RegenPerMs), RegenMaxMs at most; no wait with no bar (full HP), a fight
    ; RegenFarMs from spawn or nearer (the minions reach spawn), the orb
    ; nearly dead, or the biome gone (the fight loop ends the hunt).
    ; -> false = stopped.
    _Regen(ctx, f, walk) {
        env := this._env, t0 := env.Now()
        need := MinionsTask.ReturnHp - (walk = "" ? 0 : walk * MinionsTask.RegenPerMs)
        hp := this._PlayerHp()
        if (hp < 0 || hp >= need || (walk != "" && walk <= MinionsTask.RegenFarMs) || MinionsTask.OrbNearlyDead(f, t0))
            return true
        env.Log("minions: hp " Round(hp * 100) "% at spawn - waiting for " Round(need * 100) "% before going back")
        while (env.Now() - t0 < MinionsTask.RegenMaxMs) {
            if !env.Wait(MinionsTask.RegenLookMs, ctx)
                return false
            if (f.HasOwnProp("b0") && MinionsTask.BiomeLeft(f.b0, this._BiomeNow()))
                break
            hp := this._PlayerHp()
            if (hp < 0 || hp >= need)
                break
        }
        env.Log("minions: going back at hp " (hp < 0 ? "full" : Round(hp * 100) "%") " after " (env.Now() - t0) " ms")
        return true
    }

    ; After a death: the player is at spawn, the camera re-aimed as after
    ; ResetToSpawn (Aura Collections open + close: the respawn's own camera
    ; is not known to face the same way; shift lock off for the clicks, on
    ; again), the bearing 0. Shift lock goes off first, inside the wait for
    ; the respawn (_RespawnSettle). why: _DeathSeen's. -> false = stopped.
    _AfterDeath(ctx, why := "") {
        env := this._env, t0 := env.Now()
        this._hpLog := [], this._bearing := 0, this._pos := {x: 0, y: 0}, this._aimed := false
        if this._lockTried
            this._ShiftOff(ctx)
        if !this._RespawnSettle(ctx, why, t0)
            return false
        if !this._ClickOk(ctx, "the camera re-aim after the death")
            return !ctx.ShouldStop()
        if Input.QuickAim(ctx, env.io)
            this._aimed := true
        else
            env.Log("minions: camera not re-aimed after the death (" Input.LastResetError ") - the bearing is a guess")
        if (this._lockTried && !ctx.ShouldStop())
            this._lock := this._ShiftOn(ctx)
        return this._FightCamera(ctx)            ; the respawn may have reset it
    }

    ; The wait before the re-aim's clicks. The log read: from the respawn's
    ; lines (t0: seen then; the death screen comes before them, 0.2..2.2 s,
    ; L34..L37: looked for up to DeathLineMs) DeathAfterLineMs, what the
    ; shift lock took counted. No log: DeathSettleMs. -> false = stopped.
    _RespawnSettle(ctx, why, t0) {
        env := this._env, log := this._respawnLog
        if !IsObject(log)
            return env.Wait(Max(0, MinionsTask.DeathSettleMs - (env.Now() - t0)), ctx)
        if (why = MinionsTask.DeathScreenSeen) {
            left := MinionsTask.DeathLineMs
            Loop {
                if (log.Poll() || left <= 0)
                    break
                if !env.Wait(50, ctx)
                    return false
                left -= 50
            }
            t0 := env.Now()
        }
        return env.Wait(Max(0, MinionsTask.DeathAfterLineMs - (env.Now() - t0)), ctx)
    }

    ; A camera turn (key Left / Right, ms) -> px it moves the screen
    ; (Shift); the bearing follows it (Left -, Right +).
    _Turn(key, ms) {
        this._turns++
        this._Settle()                           ; a move held went the old way so far
        Input.Key(key, ms, this._env.io)
        this._bearing += (key = "Left") ? -ms : (key = "Right") ? ms : 0
        this._Settle()
        return MinionsTask.Shift(key, ms)
    }

    ; A turn of d ms net (Right +) the short way round (Wrap), in steps of
    ; TurnMaxMs at most with a stop check before each: a bearing after a
    ; long hunt is many circles, one hold would block F3 for seconds. A
    ; look's worth or more (BigTurnMs): no walk through it, what it turns to
    ; is not checked for an edge. -> px the steps moved the screen (Shift).
    _TurnBy(ctx, d) {
        d := MinionsTask.Wrap(d), px := 0
        if (Abs(d) >= MinionsTask.BigTurnMs)
            this._Stop()
        while (d && !ctx.ShouldStop()) {
            ms := Min(Abs(d), MinionsTask.TurnMaxMs)
            px += this._Turn(d < 0 ? "Left" : "Right", ms)
            d -= (d < 0) ? -ms : ms
        }
        return px
    }

    ; One step towards a far target (a bar or a glow) that stuck walks got
    ; no closer to: a walk, then the Escapes in turn (esc: the ones done),
    ; each checked by the next scan, then along the wall (wall: "" = none,
    ; started here when t, the target now {y, w}, is above: WallHighY; up:
    ; walking in, stuck again = on along it from here).
    ; -> 1 stepped, 0 stopped, -1 still stuck after every Escape and the
    ; wall (the caller leaves that target). ms: the walk's length ("" = WalkMs).
    _Approach(ctx, stuck, &esc, &wall := "", t := "", ms := "") {
        if (IsObject(wall) && !wall.up)
            return this._WallStep(ctx, &wall)
        if (stuck < MinionsTask.StuckWalks)
            return this._Walk(ctx, ms) ? 1 : 0
        if IsObject(wall) {
            wall.up := false, wall.gain := 0, wall.y := t.y, wall.w := t.w
            return this._WallStep(ctx, &wall)
        }
        if (esc < MinionsTask.Escapes.Length) {
            e := MinionsTask.Escapes[++esc]
            this._env.Log("minions: walking got no closer - " e.name " (" esc "/" MinionsTask.Escapes.Length ")")
            return this._Escape(ctx, e.side) ? 1 : 0
        }
        if !(IsObject(t) && t.y <= MinionsTask.WallHighY)
            return -1
        ; the side that found a way up in this biome before first
        side := MinionsTask.WallSides.Get(this._biome, "a")
        wall := {side: side, leg: 1, ms: 0, y: t.y, w: t.w, up: false, gain: 0, quiet: 0, blind: 0, spent: 0, tick: this._env.Now()
            , back: 0, stuck: false, below: 0, belowTo: 0}
        this._WallLog(side)
        return this._WallStep(ctx, &wall)
    }

    ; One step along the wall: the legs (WallLeg) in turn, each up to its
    ; length or the island's edge. -> as _Approach (-1: the legs or WallMaxMs
    ; done, wall "").
    _WallStep(ctx, &wall) {
        now := this._env.Now()
        wall.spent += Min(now - wall.tick, MinionsTask.WallGapMs), wall.tick := now
        if (wall.spent >= MinionsTask.WallMaxMs) {
            wall := ""
            return -1
        }
        if wall.back {
            ms := wall.back, wall.back := 0
            return this._Hold("s", ms, ctx) ? 1 : 0
        }
        v := this._View()
        edge := IsObject(v) && v.edge
        if (edge || wall.ms >= MinionsTask.WallLeg(wall.leg)) {
            if edge
                this._env.Log("minions: wall - the island's edge, no further this way")
            done := wall.ms
            wall.leg++, wall.ms := 0, wall.quiet := 0
            if (wall.leg > 4) {
                wall := ""
                return -1
            }
            if (wall.leg = 2) {
                wall.side := (wall.side = "a") ? "d" : "a", wall.quiet := done * 3 // 4
                this._WallLog(wall.side)
            } else if (wall.leg = 3) {
                wall.back := MinionsTask.WallRoundMs
                this._env.Log("minions: wall - backing off and round")
            }
            if edge
                return this._Hold("s", MinionsTask.EdgeBackMs, ctx) ? 1 : 0
            if wall.back
                return this._WallStep(ctx, &wall)
        }
        if (wall.leg = 4) {
            wall.ms += MinionsTask.WalkMs
            return this._Walk(ctx) ? 1 : 0
        }
        ms := wall.stuck ? MinionsTask.WallPeelMs : MinionsTask.WallStepMs
        wall.ms += ms
        if !this._Strafe(ctx, wall.side, ms, wall.stuck)
            return 0
        if wall.stuck
            wall.quiet := Max(wall.quiet, wall.ms + 2 * MinionsTask.WallStepMs)
        v2 := this._View()
        wall.stuck := IsObject(v) && IsObject(v2) && !wall.stuck && MinionsTask.ViewSame(v.sig, v2.sig)
        return 1
    }

    ; The legs' lengths: one way, twice that the other, round, walks in
    static WallLeg(leg) => leg = 2 ? 2 * MinionsTask.WallSlideMaxMs
        : leg = 4 ? MinionsTask.WallInWalks * MinionsTask.WalkMs : MinionsTask.WallSlideMaxMs

    ; Sideways (side "a" / "d") ms, two hops, w added for its last
    ; WallPushMs, the bearing kept; off: with s and no hop, off what blocks
    ; the way.
    _Strafe(ctx, side, ms, off) {
        this._Stop()
        io := this._env.io
        u := MinionsTask.Way(this._bearing + (side = "a" ? -1 : 1) * MinionsTask.FullTurnMs // 4)
        this._pos.x += ms * u.x, this._pos.y += ms * u.y
        this._Note((off ? "p" : "") side, ms)
        if off {
            Input._Press("s", io), this._Moved(-ms)
            try {
                Input._Press(side, io)
                try {
                    return this._env.Wait(ms, ctx)
                } finally {
                    Input._Release(side, io)
                }
            } finally {
                Input._Release("s", io)
            }
        }
        Input._Press(side, io)
        try {
            Input.Key("Space", 60, io), this._jumpAt := this._env.Now()
            if !this._env.Wait(MinionsTask.WallHopMs - 60, ctx)
                return false
            Input.Key("Space", 60, io), this._jumpAt := this._env.Now()
            if !this._env.Wait(ms - MinionsTask.WallHopMs - 60 - MinionsTask.WallPushMs, ctx)
                return false
            return this._Hold("w", MinionsTask.WallPushMs, ctx, false)
        } finally {
            Input._Release(side, io)
        }
    }

    ; Along a wall, the target in reach (InReach): stands of BlockedMs, at
    ; most BelowStands unless a bar is hurt. Not while walking in.
    _Below(w, v, now, locked := false) {
        if (!IsObject(w) || w.up || !MinionsTask.InReach(v, locked))
            return false
        if (now < w.belowTo)
            return true
        if (w.below >= MinionsTask.BelowStands && !MinionsTask.Hurt(v))
            return false
        w.below++, w.belowTo := now + MinionsTask.BlockedMs
        this._env.Log("minions: in reach from below the wall - standing and casting (" w.below ")")
        return true
    }

    ; No way up found (x: the target on screen): the wall's bearing left
    ; alone (WallOff), the patrol on from here, half a turn away.
    _LeaveWall(ctx, f, x) {
        env := this._env
        b := this._bearing + Round((x - MinionsTask.CenterX) / MinionsTask.TurnPxPerMs)
        f.wallOff := {b: b, until: env.Now() + MinionsTask.WallOffMs}
        this._walls.Push({b: b})
        env.Log("minions: no way up at this wall - bearing " b " ms left alone for " MinionsTask.WallOffMs // 1000 " s")
        if (this._boss || !env.cfg.Get("Minions.patrol", 1))
            return
        f.patrol := true, f.pLeg := 0, f.pLeft := 0, f.empty := 0, f.fightBearing := ""
        f.shift := this._TurnBy(ctx, MinionsTask.FullTurnMs // 2)
    }

    _WallLog(side) => this._env.Log("minions: wall - sliding " (side = "a" ? "left" : "right") " to find a way up")

    ; The way along the wall w reached the target: logged, its side kept
    ; for this biome.
    _WallFound(w) {
        this._env.Log("minions: found a way up (side " w.side ")")
        if (this._biome != "")
            MinionsTask.WallSides[this._biome] := w.side
    }

    ; Forward and sideways (side "a" / "d") WallSlideMs with one jump; not
    ; at the island's edge (_EdgeGuard).
    _Slide(ctx, side) {
        e := this._EdgeGuard(ctx)
        if (e <= 0)
            return e < 0
        this._Stop()
        io := this._env.io
        Input._Press("w", io), this._Moved(MinionsTask.WallSlideMs), this._Note("l" side, MinionsTask.WallSlideMs)
        try {
            Input._Press(side, io)
            try {
                if !this._env.Wait(150, ctx)
                    return false
                Input.Key("Space", 60, io), this._jumpAt := this._env.Now()
                return this._env.Wait(MinionsTask.WallSlideMs - 210, ctx)
            } finally {
                Input._Release(side, io)
            }
        } finally {
            Input._Release("w", io)
        }
    }

    ; Forward EscapeMs, with a jump (side "") or strafing (side "a" / "d").
    _Escape(ctx, side) {
        this._Stop()
        io := this._env.io
        Input._Press("w", io), this._Moved(MinionsTask.EscapeMs), this._Note("e" side, MinionsTask.EscapeMs)
        try {
            if (side = "") {
                Input.Key("Space", 60, io), this._jumpAt := this._env.Now()
                return this._env.Wait(MinionsTask.EscapeMs - 60, ctx)
            }
            Input._Press(side, io)
            try {
                return this._env.Wait(MinionsTask.EscapeMs, ctx)
            } finally {
                Input._Release(side, io)
            }
        } finally {
            Input._Release("w", io)
        }
    }

    ; key held ms; note: kept on the trail (a dodge, part of a strafe: not)
    _Hold(key, ms, ctx, note := true) {
        this._Stop()
        io := this._env.io
        if note
            this._Note(key, ms)
        if (key = "w" || key = "s")
            this._Moved(key = "w" ? ms : -ms)
        Input._Press(key, io)
        try {
            return this._env.Wait(ms, ctx)
        } finally {
            Input._Release(key, io)
        }
    }

    ; A move on the trail: k "w" a walk, "s" back, "a" / "d" a strafe, "pa" /
    ; "pd" one off a wall, "la" / "ld" a slide, "e" / "ea" / "ed" an escape;
    ; b the bearing it went at, so turns need no entry and a look round
    ; leaves none. A move undoing the one before (Undoes): both gone.
    _Note(k, ms) {
        t := this._trail
        ; a held step is its time on the clock: a few ms either way (TrailGrainMs)
        if (t.Length && Abs(t[-1].ms - ms) <= MinionsTask.TrailGrainMs && !MinionsTask.Wrap(t[-1].b - this._bearing) && MinionsTask.Undoes(t[-1].k, k)) {
            t.Pop()
            this._trailTo := Min(this._trailTo, t.Length)
        } else
            t.Push({k: k, ms: ms, b: this._bearing})
    }

    static Undoes(a, b) => (a = "w" && b = "s") || (a = "s" && b = "w") || (a = "a" && b = "d") || (a = "d" && b = "a")

    ; A bar in sight: the trail so far leads to the fight; a replay ends here
    ; (what it walked is on the trail by now: the replay is the trail).
    _TrailSeen(f) {
        if f.replay
            this._env.Log("minions: a target in sight - trail left at step " f.replay "/" f.route.Length)
        f.replay := 0, f.rWhy := "", this._trailTo := this._trail.Length, this._trailB := this._bearing
    }

    ; At a death, f.route := the way to the fight: the trail up to the last
    ; sighting, ending on that bearing, unless the one so far is shorter (a
    ; life that wandered to the same fight); no sighting since the respawn (or
    ; no re-aim then): the route as it was, so it lasts through deaths
    ; on the way. A fall: not past the step that fell, less the tail (TrailCut).
    _TrailRoute(f, fell) {
        if (this._trailB != "" && this._aimed) {
            r := []
            Loop this._trailTo
                r.Push(this._trail[A_Index])
            if r.Length
                r.Push({k: "t", ms: 0, b: this._trailB})
            if (!f.route.Length || MinionsTask.TrailMs(r) <= MinionsTask.TrailMs(f.route))
                f.route := r
        } else if (fell && f.replay)
            f.route.Length := f.replay - 1
        if fell
            f.route := MinionsTask.TrailCut(f.route, MinionsTask.FallMarginMs + MinionsTask.WalkMs)
        f.replay := 0, this._trail := [], this._trailTo := 0, this._trailB := ""
    }

    ; route without its last moves of ms or more: FallMarginMs + a walk, so
    ; its last step stays clear of the fall (FallAhead)
    static TrailCut(route, ms) {
        out := route.Clone()
        while (out.Length && ms > 0)
            ms -= out.Pop().ms
        return out
    }

    static TrailMs(route) {
        ms := 0
        for s in route
            ms += s.ms
        return ms
    }

    ; One step of the replay, f.replay on: the turn to the move's bearing
    ; (BigTurnMs or more: a look after it), the move, up to ReplayWalks
    ; walks in a row. Bars end it in _TrailSeen; an edge in view (the walk
    ; turned round, _EdgeGuard) here, a remembered fall not: this way led to
    ; a bar (L36 09:02:08, L41 11:47:21: turned round at step 2/11 and 7/61,
    ; both fights never found again). -> false = stopped.
    _Replay(ctx, f) {
        env := this._env
        Loop MinionsTask.ReplayWalks {
            s := f.route[f.replay], d := MinionsTask.Wrap(s.b - this._bearing)
            big := Abs(d) >= MinionsTask.BigTurnMs
            if (A_Index > 1 && (big || s.k != "w"))
                return true
            if d
                f.shift := this._TurnBy(ctx, d)
            if big
                return true
            f.replay++, b := this._bearing
            if !this._WayStep(ctx, s)
                return false
            if (this._bearing != b) {
                env.Log("minions: an edge on the trail at step " f.replay - 1 "/" f.route.Length " - replay over")
                f.replay := 0, f.rEdge := true
                return true
            }
            if (f.replay > f.route.Length) {
                env.Log("minions: trail replayed, nothing in sight")
                f.replay := 0
                return true
            }
        }
        return true
    }

    ; A step of a way that led to a target: the move s of a route, "" a walk
    ; (or slide). A remembered fall does not turn it round (_EdgeGuard, as
    ; for a bar ahead). -> false = stopped.
    _WayStep(ctx, s := "") {
        was := this._toBar
        this._toBar := true
        try
            return IsObject(s) ? this._ReplayMove(ctx, s) : this._WalkOrSlide(ctx)
        finally
            this._toBar := was
    }

    ; Bars in sight (bar: the one aimed at): the fight is here, that way from
    ; here; any way back to it is over. A life not re-aimed: when it is only
    ; (its position and bearings are guesses), the place stays the last one.
    ; A far bar (orb: its plate, wider): the place is out there, FarOf ms
    ; along the way it was seen.
    _FightSeen(f, bar, orb := false) {
        f.fightAt := this._env.Now(), f.home := 0, f.ring := 0, f.ringAt := 0
        f.fightFar := MinionsTask.FarOf(bar, orb)
        if !this._aimed
            return
        this._Settle()
        f.fightFace := MinionsTask.AbsBearing(this._bearing, bar.x), u := MinionsTask.Way(f.fightFace)
        f.fightPos := f.fightFar ? {x: this._pos.x + f.fightFar * u.x, y: this._pos.y + f.fightFar * u.y} : {x: this._pos.x, y: this._pos.y}
    }

    ; ms of walking to a bar this wide (FarWalkMs, FarMaxMs), 0 = beside
    static FarOf(bar, orb := false) {
        k := orb ? MinionsTask.BesideOrbW : MinionsTask.BesideMinionW, w := MinionsTask.FullW(bar)
        return w >= k ? 0 : Round(Min(MinionsTask.FarMaxMs, MinionsTask.FarWalkMs * (k / Max(w, 1) - 1)))
    }

    ; The target seen not FightOpenMs ago (a down one ends the hunt)
    static FightOpen(now, at) => at != "" && now - at <= MinionsTask.FightOpenMs

    static Gap(a, b) => Sqrt((b.x - a.x) ** 2 + (b.y - a.y) ** 2)

    ; No route to pos from spawn, or one that wanders: L39 11:08:21 13.5 s of
    ; trail still on its way 32 s later, L41 11:47:09 61 steps, 40 s of it
    static LineBeats(route, pos) => !route.Length || MinionsTask.TrailMs(route) > MinionsTask.LineBend * MinionsTask.Gap({x: 0, y: 0}, pos) + MinionsTask.LineSlackMs

    ; A fight lost from sight and not looked for yet: no map walk before
    ; that (L41 12:26:56, L37 10:01:54: the patrol took over, fights at 0.11
    ; and 1.00 of the orb never met again). A target left as stuck counts as
    ; looked for (f.ringFor, _AtBars).
    _FightLost(f) => !this._boss && this._aimed && IsObject(f.fightPos) && f.ringFor != f.fightAt
        && MinionsTask.FightOpen(this._env.Now(), f.fightAt)

    ; On to where the fight was and the looks from there and round it (here:
    ; one look where it stands, after a fall the rest of the way is what
    ; fell). -> true
    _HomeStart(f, here := false) {
        f.home := 1, f.homeTo := here ? "" : f.fightPos, f.homeWalks := "", f.ring := 0
        f.ringAt := here ? MinionsTask.RingPoints : 0, f.ringFor := f.fightAt
        return true
    }

    ; A step to f.homeTo, the way worked out anew from where the walk got to
    ; (a slide, a wall), its walks counted; there, or no walks left, or an
    ; edge in view: the looks from here on (f.ring). -> false = stopped.
    _HomeStep(ctx, f) {
        env := this._env
        this._Settle()
        left := IsObject(f.homeTo) ? MinionsTask.Gap(this._pos, f.homeTo) : 0
        if (f.homeWalks = "")
            f.homeWalks := Ceil(left / MinionsTask.WalkMs) + MinionsTask.HomeSpareWalks
        if (left <= MinionsTask.HomeNearMs || f.homeWalks <= 0) {
            this._Stop()
            f.home := 0, f.ring := MinionsTask.FullTurnMs // MinionsTask.ScanTurnMs
            env.Log("minions: " (!IsObject(f.homeTo) ? "as far as the way goes" : left > MinionsTask.HomeNearMs ? Round(left) " ms short of the spot"
                : f.ringAt ? "round where the fight was (" f.ringAt "/" MinionsTask.RingPoints ")" : "where the fight was") " - looking round")
            return true
        }
        d := MinionsTask.Wrap(MinionsTask.PosBearing({x: f.homeTo.x - this._pos.x, y: f.homeTo.y - this._pos.y}) - this._bearing)
        if (Abs(d) >= MinionsTask.HomeAimMs)
            f.shift := this._TurnBy(ctx, d)
        if (Abs(d) >= MinionsTask.BigTurnMs)
            return true
        f.homeWalks--, b := this._bearing
        if !this._WayStep(ctx)
            return false
        if (this._bearing != b) {
            env.Log("minions: an edge on the way back - looking round here")
            f.homeWalks := 0, f.homeTo := ""
        }
        return true
    }

    ; A look of a circle from where the fight was, the first one the way the
    ; target was. Done: on to the next of RingPoints round the spot; all done,
    ; or the fight old by now: it is not looked for any more. -> false = stopped.
    _RingStep(ctx, f) {
        env := this._env, c := MinionsTask.FullTurnMs
        this._Stop()
        if (f.ring = c // MinionsTask.ScanTurnMs)
            f.shift := this._TurnBy(ctx, f.fightFace - this._bearing)
        else
            f.shift := this._Turn("Left", MinionsTask.ScanTurnMs)
        if (--f.ring > 0)
            return !ctx.ShouldStop()
        if (f.ringAt < MinionsTask.RingPoints && MinionsTask.FightOpen(env.Now(), f.fightAt)) {
            u := MinionsTask.Way(f.fightFace + f.ringAt++ * c // 4)
            f.home := 1, f.homeWalks := ""
            f.homeTo := {x: f.fightPos.x + MinionsTask.RingMs * u.x, y: f.fightPos.y + MinionsTask.RingMs * u.y}
            return !ctx.ShouldStop()
        }
        env.Log("minions: no sign of the fight round where it was")
        f.ringAt := 0, f.fightAt := ""
        return !ctx.ShouldStop()
    }

    ; The move s of a route (_Note's k; "t" only a bearing). It goes on the
    ; new trail as it did on the old one. -> false = stopped.
    _ReplayMove(ctx, s) {
        side := SubStr(s.k, 2)
        switch SubStr(s.k, 1, 1) {
            case "w": return this._Walk(ctx, s.ms)
            case "s": return this._Hold("s", s.ms, ctx)
            case "a", "d": return this._Strafe(ctx, s.k, s.ms, false)
            case "p": return this._Strafe(ctx, side, s.ms, true)
            case "l": return this._Slide(ctx, side)
            case "e": return this._Escape(ctx, side)
        }
        return true
    }

    ; ---- the spots and the routes learned to them ---------------------------

    ; The bearing from spawn of a thing at screen x, the camera at bearing b:
    ; 0 <= ms < FullTurnMs (right of the respawn way: more). Off the centre by
    ; the camera's angle (FocalPx), not px / TurnPxPerMs: the Area's edges are 35
    ; and 43 degrees out, 292 and 358 ms, where px / 3.6 says 200 and 267.
    static AbsBearing(b, x) {
        c := MinionsTask.FullTurnMs
        d := Mod(b + Round(ATan((x - MinionsTask.CenterX) / MinionsTask.FocalPx) * c / (2 * 3.141592653589793)), c)
        return d < 0 ? d + c : d
    }

    ; The way from spawn to pos as a bearing (AbsBearing's), "" = at spawn.
    static PosBearing(pos) {
        if !(pos.x || pos.y)
            return ""
        pi := 3.141592653589793, c := MinionsTask.FullTurnMs
        a := pos.y ? ATan(pos.x / pos.y) : (pos.x > 0 ? pi / 2 : -pi / 2)
        return Mod(Round((pos.y < 0 ? a + pi : a) * c / (2 * pi)) + c, c)
    }

    ; The spot nearest bearing a within its tol + loose, "" = none.
    static SpotOf(a, loose := 0) {
        best := "", least := 0
        for s in MinionsTask.Spots {
            d := Abs(MinionsTask.Wrap(a - s.b))
            if (d <= s.tol + loose && (!IsObject(best) || d < least))
                best := s, least := d
        }
        return best
    }

    ; Off unless asked for: Spots' b are false on the true circle, a later fix
    ; rebuilds them. Off, the routes learned to them are off too.
    _SpotsOn() => !this._boss && this._env.cfg.Get("Minions.spots", 0)

    ; Bearings mean something: nothing walked since the camera was aimed.
    _AtSpawn() => this._aimed && !this._trail.Length

    ; A look round: from spawn straight to the next spot, in Spots' order
    ; round and round; elsewhere ScanTurnMs left. -> px it moved the screen.
    _SpotLook(ctx, f) {
        this._Stop()
        if !(this._SpotsOn() && this._AtSpawn())
            return this._Turn("Left", MinionsTask.ScanTurnMs)
        if !f.spotAt
            this._env.Log("minions: looking at the spots")
        f.spotAt := Mod(f.spotAt, MinionsTask.Spots.Length) + 1
        return this._TurnBy(ctx, MinionsTask.Spots[f.spotAt].b - this._bearing)
    }

    ; f.spot's stored route on from its first step (why: see _Fight); no
    ; route: false, the hunt goes on as it would.
    _RouteStart(f, why) {
        if !this._routes.Has(f.spot)
            return false
        r := this._routes[f.spot]
        f.route := r.steps.Clone(), f.replay := 1, f.rWhy := why, f.rUsed := true, f.rEdge := false, f.back := 0
        this._env.Log("minions: spot " f.spot " (" why ") - replaying the stored route, " r.steps.Length " steps, " r.ms " ms")
        return true
    }

    ; Bars in sight (v, bar: _AtBars's). From spawn: their spot kept, its
    ; route started. -> true = a stored route goes on: no bar near, and a
    ; blind one (due) only for a bar about the way it goes next.
    _RouteBar(f, v, bar) {
        if !this._SpotsOn()
            return false
        near := MinionsTask.InReach(v)
        a := MinionsTask.AbsBearing(this._bearing, bar.x)
        if (!f.replay && !near && this._AtSpawn() && IsObject(s := MinionsTask.SpotOf(a))) {
            f.spot := String(s.b)
            this._RouteStart(f, "bar")
        }
        if (near || !f.replay || f.rWhy = "")
            return false
        return f.rWhy != "due" || Abs(MinionsTask.Wrap(a - f.route[f.replay].b)) <= MinionsTask.RouteCone
    }

    ; A glow g from spawn: its spot kept. -> true = its route started.
    _RouteGlow(f, g) {
        if !(this._SpotsOn() && this._AtSpawn() && IsObject(s := MinionsTask.SpotOf(MinionsTask.AbsBearing(this._bearing, g.x))))
            return false
        f.spot := String(s.b)
        return this._RouteStart(f, "glow")
    }

    ; The orbs due, nothing seen: once a hunt the route of the likeliest spot
    ; that has one. -> true = started.
    _RouteDue(f) {
        if (f.rTried || !this._SpotsOn() || !this._AtSpawn())
            return false
        for s in MinionsTask.Spots
            if this._routes.Has(String(s.b)) {
                f.rTried := true, f.spot := String(s.b)
                return this._RouteStart(f, "due")
            }
        return false
    }

    ; After a death: f.route := the fight's stored route. -> true = it did.
    ; A fall: no (_TrailRoute's cut trail, or nothing).
    _RouteBack(f, fell) {
        f.rWhy := "", f.rUsed := false
        if (fell || !this._SpotsOn() || !this._routes.Has(f.spot))
            return false
        f.route := this._routes[f.spot].steps.Clone()
        return true
    }

    ; One step of a stored route (_Replay; a remembered fall does not turn
    ; it round, an edge in view does). Over with no bar seen, or at an edge:
    ; failed; a blind one with no bar at its end only found no orb there.
    ; -> false = stopped.
    _RouteStep(ctx, f, seen) {
        this._toBar := true
        try
            ok := this._Replay(ctx, f)
        finally
            this._toBar := false
        if !f.replay {
            if (f.rEdge || (!seen && f.rWhy != "due"))
                this._RouteFailed(f)
            f.rWhy := "", f.rEdge := false
        }
        return ok
    }

    _RouteFailed(f) {
        if !this._routes.Has(f.spot)
            return
        r := this._routes[f.spot]
        if (++r.fails >= MinionsTask.RouteFails) {
            this._routes.Delete(f.spot)
            this._env.Log("minions: the route to spot " f.spot " failed " r.fails " times - dropped")
        } else
            this._env.Log("minions: the route to spot " f.spot " failed (" r.fails "/" MinionsTask.RouteFails ")")
        this._RoutesSave()
    }

    ; Beside the fight: the trail from spawn is a way to its spot (f.spot, else
    ; the spot the player stands towards). The shortest one kept; a stored
    ; one that led here counts its fails from 0 again.
    _RouteLearn(f) {
        if !(this._SpotsOn() && this._aimed && this._trail.Length)
            return
        if (f.spot = "") {
            a := MinionsTask.PosBearing(this._pos)
            if (a = "" || !IsObject(s := MinionsTask.SpotOf(a, MinionsTask.SpotLooseMs)))
                return
            f.spot := String(s.b)
        }
        steps := this._trail.Clone()
        steps.Push({k: "t", ms: 0, b: this._bearing})
        ms := MinionsTask.TrailMs(steps), old := this._routes.Has(f.spot) ? this._routes[f.spot] : ""
        if (IsObject(old) && ms >= old.ms) {
            if (f.rUsed && old.fails) {
                old.fails := 0
                this._RoutesSave()
            }
            return
        }
        this._routes[f.spot] := {ms: ms, fails: 0, steps: steps}
        this._env.Log("minions: route to spot " f.spot " learned, " steps.Length " steps, " ms " ms")
        this._RoutesSave()
    }

    ; The routes file read, once a run of the macro (none, or unreadable: no routes).
    _RoutesRead() {
        if this._routesLoaded
            return
        this._routesLoaded := true
        cfg := this._env.cfg
        if (this._routesFile = "" && cfg.HasProp("dataDir"))
            this._routesFile := cfg.dataDir "\minions_routes.json"
        if (this._routesFile = "" || !FileExist(this._routesFile))
            return
        try {
            for key, r in Json.Parse(FileRead(this._routesFile, "UTF-8")) {
                steps := []
                for s in r["steps"]
                    steps.Push({k: s["k"], ms: s["ms"], b: s["b"]})
                this._routes[key] := {ms: r["ms"], fails: r["fails"], steps: steps}
            }
            this._env.Log("minions: " this._routes.Count " stored route(s) read")
        } catch as e {
            this._routes := Map()
            this._env.Log("minions: the routes file is unreadable (" e.Message ") - no routes")
        }
    }

    _RoutesSave() {
        if (this._routesFile = "")
            return
        root := Map()
        for key, r in this._routes {
            steps := []
            for s in r.steps
                steps.Push(Map("k", s.k, "ms", s.ms, "b", s.b))
            root[key] := Map("ms", r.ms, "fails", r.fails, "steps", steps)
        }
        try
            Calibrate._AtomicWrite(this._routesFile, Json.Stringify(root) "`n")
        catch as e
            this._env.Log("minions: the routes file not written (" e.Message ")")
    }

    ; ms walked forward (back: -) along the bearing: the position (_pos)
    _Moved(ms) {
        u := MinionsTask.Way(this._bearing)
        this._pos.x += ms * u.x, this._pos.y += ms * u.y
    }

    ; ---- moves held across the scans ---------------------------------------
    ; A step of a move is ms from the end of the last one: the scan, the casts
    ; and the turns between two steps are in it, the key is down all along.
    ; The screen grabs take as long as they did, the player does not stand
    ; for them. this._held: {key, note (on the trail), at: the last step's
    ; end, t: the time _Settle got to, ms: settled, not on the trail yet,
    ; tick}. One key at a time. Up: _Stop, here or at the end of a tick that
    ; asked for no step (_Timed), and at the end of the fight whatever happens.

    ; key down; another one held goes up first; pressed again if something
    ; let go of it (Input.ReleaseAll). -> the held move
    _Go(key, note := true) {
        h := this._held
        if (IsObject(h) && h.key = key && Input._held.Has(StrLower(key))) {
            h.tick := this._tick
            return h
        }
        this._Stop()
        now := this._env.Now()
        Input._Press(key, this._env.io)
        return this._held := {key: key, note: note, at: now, t: now, ms: 0, tick: this._tick}
    }

    ; The move up, its time on the position and the trail.
    _Stop() {
        h := this._held
        if !IsObject(h)
            return
        this._Flush()
        this._held := ""
        Input._Release(h.key, this._env.io)
    }

    ; The time held since the last call along the bearing now: the position.
    _Settle() {
        h := this._held
        if !IsObject(h)
            return
        now := this._env.Now(), ms := now - h.t, h.t := now
        if (ms <= 0)
            return
        u := MinionsTask.Way(this._bearing + (h.key = "w" ? 0 : MinionsTask.DodgeOff(h.key)))
        this._pos.x += ms * u.x, this._pos.y += ms * u.y, h.ms += ms
    }

    ; What was settled, on the trail: one entry a step, at the bearing it
    ; ended on (a turn inside a step is an aim correction: a replay of
    ; pieces of a scan's length would last a scan each).
    _Flush() {
        this._Settle()
        h := this._held
        if !IsObject(h)
            return
        if (h.note && h.ms > 0)
            this._Note(h.key, h.ms)
        h.ms := 0
    }

    ; The step ends here; the key stays down.
    _StepDone() {
        this._Flush()
        this._held.at := this._env.Now()
    }

    ; Up to time t with the key down; stopped: it goes up. -> false = stopped.
    _Until(t, ctx) {
        left := t - this._env.Now()
        if (left > 0 ? this._env.Wait(left, ctx) : !ctx.ShouldStop())
            return true
        this._Stop()
        return false
    }

    ; key held for a step of ms. -> false = stopped.
    _Step(key, ms, ctx, note := true) {
        h := this._Go(key, note)
        if !this._Until(h.at + ms, ctx)
            return false
        this._StepDone()
        return true
    }

    ; A tick with no step of its own (a look again, an aim turn) that does
    ; not end the move, unless a step is overdue: the checks for an edge come
    ; with the steps. -> true
    _Keep() {
        h := this._held
        if (IsObject(h) && this._env.Now() - h.at < MinionsTask.WalkMs)
            h.tick := this._tick
        return true
    }

    ; Forward WalkMs with one jump (spawn has ledges; ms: a shorter step,
    ; none); not at the island's edge (_EdgeGuard). w stays down for the next
    ; step. The view after it kept (_Still).
    _Walk(ctx, ms := "") {
        e := this._EdgeGuard(ctx)
        if (e <= 0)
            return e < 0
        ms := (ms = "") ? MinionsTask.WalkMs : ms
        h := this._Go("w")
        if (ms > MinionsTask.NearStepMs) {       ; a short step beside the orb: no jump
            if !this._Until(h.at + 150, ctx)
                return false
            Input.Key("Space", 60, this._env.io), this._jumpAt := this._env.Now()
        }
        if !this._Until(h.at + ms, ctx)
            return false
        this._StepDone()
        this._Still()
        return true
    }

    ; A walk, or after StillWalks walks that left the view the same (a
    ; wall), SlideSteps slides along it one way (a / d in turn per wall),
    ; then walks again. -> false = stopped.
    _WalkOrSlide(ctx) {
        if (this._stills >= MinionsTask.StillWalks + MinionsTask.SlideSteps)
            this._stills := 0, this._lastView := ""
        if (this._stills < MinionsTask.StillWalks)
            return this._Walk(ctx)
        if (this._stills = MinionsTask.StillWalks) {
            this._wallSide++
            this._env.Log("minions: walking into a wall - sliding " (Mod(this._wallSide, 2) ? "left" : "right") " along it")
        }
        this._stills++
        return this._Slide(ctx, Mod(this._wallSide, 2) ? "a" : "d")
    }

    ; Step k (1..ReturnWalks) of a pursuit walk (Pursue) in style side:
    ; "a" / "d" a slide that way; "s" (round) a step back, a quarter turn
    ; left, walks, at the middle a quarter turn back; "" a walk (or slide).
    ; -> false = stopped.
    _PursueStep(ctx, side, k) {
        if (side = "a" || side = "d")
            return this._Slide(ctx, side)
        if (side = "s") {
            q := MinionsTask.FullTurnMs // 4, mid := MinionsTask.ReturnWalks // 2
            if (k = 1)
                return this._Hold("s", MinionsTask.RoundBackMs, ctx)
            if (k = 2 || k = mid + 1) {
                this._TurnBy(ctx, k = 2 ? -q : q)
                return !ctx.ShouldStop()
            }
        }
        return this._WalkOrSlide(ctx)
    }

    ; The island's edge ahead (EdgeAhead on the view, not in SeaFloors): no
    ; step, a step back and a half turn instead; on the way to a bar EdgeBarTurnMs, the bar
    ; stays in reach. The patrol's quiet (EdgeQuietMs) counts from the end of
    ; the turn, or the turn would eat it. -> 1 go on, -1 turned back, 0 stopped.
    _EdgeGuard(ctx) {
        this._Settle()
        ; a bar ahead beats a remembered fall: the position is dead reckoning
        ; (L25 WINDY: four walks to the orb turned round, the last 30 s of the hunt)
        ; once per FallQuietTurnMs: dead reckoning drifts, L38 spun on the spot
        ; for 30 s with a remembered fall on every side
        now := this._env.Now()
        fall := !this._toBar && now >= this._fallFree && MinionsTask.FallAhead(this._falls, this._pos, this._bearing, MinionsTask.WalkMs, now)
        if fall
            this._fallFree := now + MinionsTask.FallQuietTurnMs
        v := (fall || MinionsTask.SeaFloors.Has(this._biome)) ? "" : this._View()
        ; once turned, walked on: a floor read as sea spun the player (L39 SNOWY)
        if !(fall || IsObject(v) && v.edge && (!this._patrolling || now >= this._edgeFree))
            return 1
        this._env.Log(fall ? "minions: fell off the island this way before (bearing " this._bearing " ms) - backing off and turning round"
            : "minions: the island's edge ahead - backing off and turning round")
        this._edgeWay := {x: this._pos.x, y: this._pos.y, b: this._bearing, at: now}
        this._stills := 0, this._lastView := ""
        if !this._Hold("s", MinionsTask.EdgeBackMs, ctx)
            return 0
        this._TurnBy(ctx, this._toBar ? MinionsTask.EdgeBarTurnMs : MinionsTask.FullTurnMs // 2)
        if !fall
            this._edgeFree := this._env.Now() + MinionsTask.EdgeQuietMs
        return ctx.ShouldStop() ? 0 : -1
    }

    ; The way a fall went: where the player stands and faces, or, _EdgeGuard
    ; having fired FallGuardMs ago or less, what it fired at: a fall after its
    ; turn went the way the player faced before it, the bearing now is the
    ; opposite (L44..L51: 25 of 142 falls came 3 s or less after a turn).
    _FallWay() {
        e := this._edgeWay
        if (IsObject(e) && this._env.Now() - e.at <= MinionsTask.FallGuardMs)
            return e
        return {x: this._pos.x, y: this._pos.y, b: this._bearing}
    }

    ; The view after a walk compared with the last one, StillMs ago or more
    ; (sooner: not yet, a short step shows no change): the same (ViewSame)
    ; -> _still + 1, else 0 (no view: 0).
    _Still() {
        if (IsObject(this._lastView) && this._env.Now() - this._viewAt < MinionsTask.StillMs)
            return
        v := this._View()
        this._stills := (IsObject(v) && IsObject(this._lastView) && MinionsTask.ViewSame(v.sig, this._lastView.sig)) ? this._stills + 1 : 0
        this._lastView := v, this._viewAt := this._env.Now()
    }

    ; The view now: {edge, sig} (ViewOf over one grab), "" = none (the
    ; view dep's ""; with a fake scan dep and no view dep: none, the
    ; screen is not the game's).
    _View() {
        if IsObject(this._viewFn)
            return (this._viewFn)()
        if IsObject(this._scanFn)
            return ""
        a := MinionsTask.ViewArea, ys := []
        y := a.y1
        while (y <= a.y2)
            ys.Push(y), y += MinionsTask.ViewStep
        try return MinionsTask.ViewOf(this._grab.Call(a.x1, a.x2, ys, MinionsTask.ViewStride), ys, a.x1, MinionsTask.ViewStride)
        return ""
    }

    ; The end-of-hunt look around (a full circle: SweepTurns scans, ScanTurnMs
    ; between): the most confirmed bars in one scan, and whether an orb was
    ; among them. last / shift = the hunt's last scan and the turn since.
    ; A bar with no match: scanned again in place (as _BossLook), Shift says
    ; 1800 px for a turn of ScanTurnMs, past the whole Area, no bar could match.
    _Sweep(ctx, last, shift) {
        io := this._env.io
        left := 0, orb := 0
        Loop MinionsTask.SweepTurns {
            if ctx.ShouldStop()
                break
            raw := this._Scan()
            if (raw.Length && MinionsTask.Confirmed(raw, last, shift).Length < raw.Length)
                last := raw, shift := 0, raw := this._Scan()
            bars := MinionsTask.Confirmed(raw, last, shift), last := raw, shift := 0
            left := Max(left, bars.Length)
            if MinionsTask.OrbIndex(bars)
                orb := 1
            if (A_Index < MinionsTask.SweepTurns) {
                shift := this._Turn("Left", MinionsTask.ScanTurnMs)
            }
        }
        return {left: left, orb: orb}
    }

    ; The biome now from the biome dep ("" = no dep / unknown).
    _BiomeNow() {
        if !IsObject(this._biomeFn)
            return ""
        try return String((this._biomeFn)())
        return ""
    }

    ; The skill panel (and Eden's points and combo rank) now: {rows, points,
    ; rank} for MinionSkills, "" = unknown (a failed grab; the hud dep's "").
    _Hud() {
        air := this._jumpAt != "" && this._env.Now() - this._jumpAt < MinionsTask.VoidGroundMs
        if IsObject(this._hudFn) {
            h := (this._hudFn)()
            if IsObject(h)
                h.air := air
            return h
        }
        try {
            h := {rows: MinionsTask.Panel(this._grab), points: -1, rank: "", air: air}   ; the HP: _DeathSeen reads it each tick
            if this._eden
                h.points := MinionsTask.Points(this._grab), h.rank := MinionsTask.Rank(this._grab)
            return h
        }
        return ""
    }

    _Scan() {
        if IsObject(this._scanFn)
            bars := (this._scanFn)()
        else {
            took := this._Snap()                 ; its grabs: one copy of the screen
            MinionsTask._GradLook(this._biome = "RAINY")
            try bars := MinionsTask.Scan(this._grab, MinionsTask.Area)
            finally {
                MinionsTask._GradLook(false)
                if took
                    this._SnapEnd()
            }
        }
        return this._boss ? MinionsTask.NotBossUi(bars) : bars
    }

    ; The orbs' glows now (OrbBeacon.Scan: one grab, only while no bar is
    ; in sight).
    _Beacon() {
        if IsObject(this._beaconFn)
            return (this._beaconFn)()
        ; the sky line only where bars wash out: fog, rain. Elsewhere bars read far off
        ; and the day sky over the sea is cyan (L28 NORMAL: walks to it, off the island)
        ; ... and glows only there: bars read far off elsewhere, and what glowed
        ; in NORMAL / WINDY was the gold boards, the hunt walked to them (L48)
        if !(this._biome = "SAND STORM" || this._biome = "RAINY" || this._biome = "HELL")
            return []
        top := (this._biome = "SAND STORM" || this._biome = "RAINY") ? OrbBeacon.FightTop : ""
        ; low on screen an orb has bars by then: what glows there is the floor (L38 SAND STORM)
        far := []
        for g in OrbBeacon.Scan(this._grab, this._biome, top)    ; the biome: its orb colours
            if (g.y <= MinionsTask.GlowMaxY)
                far.Push(g)
        return far
    }

    ; One scan of area a (x1, x2, y1, y2) with grab(x1, x2, ys, stride):
    ; ScanFull's bars, its pixel work only where something warm is. A sparse
    ; look (_HotBoxes) gives the boxes; FindBars and FindGrad read those, at
    ; full detail, and every row is still looked at for far bars. A scene
    ; warm all over: ScanFull. -> bars as FindBars.
    static Scan(grab, a) {
        st := MinionsTask.Stride
        ys := MinionsTask._AreaYs(a)
        boxes := MinionsTask._HotBoxes(grab, a, ys)
        if !IsObject(boxes)
            return MinionsTask.ScanFull(grab, a)
        found := [], seeds := [], grads := []
        for bx in boxes {
            part := []
            Loop bx.i2 - bx.i1 + 1
                part.Push(ys[bx.i1 + A_Index - 1])
            rows := grab(bx.x1, bx.x2, part, st)
            found.Push(MinionsTask.FindBars(rows, part, bx.x1, st, seeds)*)
            grads.Push(MinionsTask._GradPass(rows, part, bx.x1, st)*)
        }
        bars := []                               ; as one pass: top to bottom
        for b in MinionsTask._TopDown(found)
            MinionsTask._Add(bars, b)
        tys := [], trows := []
        for win in MinionsTask.ThinRows(MinionsTask._TopDown(seeds), bars)
            for r in grab(a.x1, a.x2, win, st)
                tys.Push(win[A_Index]), trows.Push(r)
        for b in MinionsTask.FindThin(trows, tys, a.x1, st)
            MinionsTask._Add(bars, b)
        for b in MinionsTask._TopDown(grads)
            MinionsTask._GradAdd(bars, b)
        real := []
        for b in bars
            if (b.w <= MinionsTask.FlatAspect * b.h) {
                MinionsTask._FillGrab(b, grab, a, ys)
                real.Push(b)
            }
        return real
    }

    ; Every row of area a a scan reads.
    static _AreaYs(a) {
        ys := []
        y := a.y1
        while (y <= a.y2) {
            ys.Push(y)
            y += MinionsTask.RowStep
        }
        return ys
    }

    ; list by y, then x (few items).
    static _TopDown(list) {
        out := []
        for b in list {
            i := out.Length + 1
            while (i > 1 && (out[i - 1].y > b.y || (out[i - 1].y = b.y && out[i - 1].x > b.x)))
                i--
            out.InsertAt(i, b)
        }
        return out
    }

    ; _Fill with only its three rows grabbed, whole (the plate runs on past
    ; any box).
    static _FillGrab(b, grab, a, ys) {
        at := MinionsTask._FillRows(b, ys, ys.Length)
        r := grab(a.x1, a.x2, [ys[at.mid], ys[at.up], ys[at.down]], MinionsTask.Stride)
        MinionsTask._FillFrom(b, r[1], r[2], r[3], a.x1, MinionsTask.Stride)
    }

    ; Where something a bar is made of may be: a look at every GateEvery-th
    ; px of every row, the next row half a step along (a bar has two rows at
    ; least: a stub 6 px long is seen). A warm px: yellow, orange (FindBars)
    ; or FindGrad's top rows (GateHue: the dim red of HELL's rock is not, a
    ; strip's top reads GradTop). Warm px near each other make a box, opened by
    ; GateRows rows and GateLeft / GateRight px: what the finders read round
    ; a run (the rows over and under it, the gaps they bridge, a stub's
    ; plate). -> boxes {x1, x2, i1, i2 (rows of ys)}, "" = most of the area.
    static GateEvery := 8        ; px; shortest bar 20 px
    static GateRows := 6
    static GateLeft := 48
    static GateRight := 96
    static GateShare := 0.6
    static GateHue := 45         ; least 100 * g / r (GradTop 55, its median)
    static _HotBoxes(grab, a, ys) {
        k := MinionsTask.GateEvery, n := ys.Length
        red := MinionsTask.GradRed, over := MinionsTask.GradRB
        odd := [], even := []
        for y in ys
            (A_Index & 1 ? odd : even).Push(y)
        ra := grab(a.x1, a.x2, odd, k)
        rb := even.Length ? grab(a.x1 + k // 2, a.x2, even, k) : []
        join := (MinionsTask.GateLeft + MinionsTask.GateRight) // k
        boxes := []
        Loop n {
            i := A_Index
            row := (i & 1) ? ra[(i + 1) // 2] : rb[i // 2]
            x0 := (i & 1) ? a.x1 : a.x1 + k // 2
            lo := 0, hi := 0
            for c in row {
                if (c < red)
                    continue
                r := c >> 16, g := (c >> 8) & 0xFF, b := c & 0xFF
                if (r - b < over || 100 * g < MinionsTask.GateHue * r) {
                    if (r < 225 || !((g >= 205 && g - b >= 60) || (r - g >= 35 && r - b >= 70)))
                        continue
                }
                if (lo && A_Index - hi <= join)
                    hi := A_Index
                else {
                    if lo
                        MinionsTask._BoxAdd(boxes, i, x0 + (lo - 1) * k, x0 + (hi - 1) * k)
                    lo := A_Index, hi := A_Index
                }
            }
            if lo
                MinionsTask._BoxAdd(boxes, i, x0 + (lo - 1) * k, x0 + (hi - 1) * k)
        }
        st := MinionsTask.Stride, out := []
        for bx in boxes {
            x1 := Max(a.x1, bx.a - MinionsTask.GateLeft)
            out.Push({x1: a.x1 + ((x1 - a.x1) // st) * st, x2: Min(a.x2, bx.b + MinionsTask.GateRight)
                , i1: Max(1, bx.i1 - MinionsTask.GateRows), i2: Min(n, bx.i2 + MinionsTask.GateRows)})
        }
        out := MinionsTask._BoxMerge(out)
        area := 0
        for bx in out
            area += (bx.x2 - bx.x1 + 1) * (bx.i2 - bx.i1 + 1)
        return area > MinionsTask.GateShare * (a.x2 - a.x1 + 1) * n ? "" : out
    }

    ; The warm span xa..xb of row i into the box it touches, else a new one.
    static _BoxAdd(boxes, i, xa, xb) {
        reach := MinionsTask.GateLeft + MinionsTask.GateRight, down := 2 * MinionsTask.GateRows + 1
        Loop boxes.Length {
            bx := boxes[boxes.Length - A_Index + 1]  ; the last ones are the open ones
            if (i - bx.i2 > down)
                continue
            if (xa <= bx.b + reach && xb >= bx.a - reach) {
                bx.a := Min(bx.a, xa), bx.b := Max(bx.b, xb), bx.i2 := i
                return
            }
        }
        boxes.Push({a: xa, b: xb, i1: i, i2: i})
    }

    ; boxes with no two overlapping: a run read twice would count twice.
    static _BoxMerge(boxes) {
        Loop {
            joined := false
            i := 1
            while (i <= boxes.Length) {
                p := boxes[i], j := i + 1
                while (j <= boxes.Length) {
                    q := boxes[j]
                    if (p.x1 <= q.x2 && q.x1 <= p.x2 && p.i1 <= q.i2 && q.i1 <= p.i2) {
                        p.x1 := Min(p.x1, q.x1), p.x2 := Max(p.x2, q.x2)
                        p.i1 := Min(p.i1, q.i1), p.i2 := Max(p.i2, q.i2)
                        boxes.RemoveAt(j)
                        joined := true
                    } else
                        j++
                }
                i++
            }
            if !joined
                return boxes
        }
    }

    ; One scan of all of area a: rows RowStep apart (FindBars), then every
    ; row around the thin strips FindBars left unexplained (ThinRows, a few
    ; grabs of ~11 rows) for far bars (FindThin). -> bars as FindBars.
    static ScanFull(grab, a) {
        st := MinionsTask.Stride
        ys := MinionsTask._AreaYs(a)
        seeds := []
        rows := grab(a.x1, a.x2, ys, st)
        bars := MinionsTask.FindBars(rows, ys, a.x1, st, seeds)
        tys := [], trows := []
        for win in MinionsTask.ThinRows(seeds, bars)
            for r in grab(a.x1, a.x2, win, st)
                tys.Push(win[A_Index]), trows.Push(r)
        for b in MinionsTask.FindThin(trows, tys, a.x1, st)
            MinionsTask._Add(bars, b)
        for b in MinionsTask._GradPass(rows, ys, a.x1, st)
            MinionsTask._GradAdd(bars, b)
        real := []                               ; L23: every RAINY / NORMAL hunt from spawn walked into the boards' lit base
        for b in bars
            if (b.w <= MinionsTask.FlatAspect * b.h) {
                MinionsTask._Fill(b, rows, ys, a.x1, st)
                real.Push(b)
            }
        return real
    }

    ; ---- pure helpers (tested) -------------------------------------------

    ; at least MinSec: 10 s ended a hunt before the first walk (2026-10-31)
    static Secs(v) => IsNumber(v) ? Max(MinionsTask.MinSec, Min(Integer(v), 900)) : MinionsTask.MaxSec

    ; The bar's top rows (yellow) and lower rows (orange). Fog washes both
    ; out but keeps blue well under green / red; the fog itself is pinkish
    ; grey (241,215,205), sand beige.
    static IsYellow(c) {
        r := (c >> 16) & 0xFF, g := (c >> 8) & 0xFF, b := c & 0xFF
        return r >= 225 && g >= 205 && g - b >= 60
    }
    static IsOrange(c) {
        r := (c >> 16) & 0xFF, g := (c >> 8) & 0xFF, b := c & 0xFF
        return r >= 225 && r - g >= 35 && r - b >= 70
    }

    ; rows (one Array per y in ys, every stride-th pixel from x1) -> Array of
    ; {x, y, w} health bars (rows RowStep = 2 px apart). A bar is a solid
    ; strip: a yellow run MinRun..MaxRun px long (text gaps bridged), at least
    ; RunCover of it yellow, orange under BelowCover of it 2 or 4 px lower,
    ; and clear just around it: at most EdgeCover yellow 2 px above, yellow /
    ; orange 8 px below; and no paler than its background (_Pale: the gold
    ; leaderboard sign near spawn). An aura's gold title (the same yellow-to-orange
    ; gradient, 2026-10-31 "Plushed : Pumpkinity") is letters over ~40 px:
    ; thin in a row, coloured above and below; a pumpkin head is a blob.
    ; seeds (an Array): gets the thin strips that are no bar here (_Seed),
    ; for ThinRows / FindThin.
    static FindBars(rows, ys, x1, stride, seeds := "") {
        bars := []
        n := rows.Length
        ; the "300 / 300" written on the bar splits the run: gaps up to
        ; GapPx are bridged
        gap := MinionsTask.GapPx // stride
        Loop n {
            i := A_Index
            row := rows[i]
            j := 1
            while (j <= row.Length) {
                ; IsYellow / IsOrange inline (the hot loop: every pixel)
                c := row[j]
                if (c < 0xE10000) {                  ; red under 225: neither colour
                    j++
                    continue
                }
                g := (c >> 8) & 0xFF, b := c & 0xFF
                if (g < 205 || g - b < 60) {
                    ; a far bar's orange bottom row (its yellow row between
                    ; two scanned rows): a seed too
                    r := c >> 16
                    if (IsObject(seeds) && r - g >= 35 && r - b >= 70) {
                        s := j++
                        while (j <= row.Length) {
                            c := row[j], r := c >> 16, g := (c >> 8) & 0xFF, b := c & 0xFF
                            if (r < 225 || r - g < 35 || r - b < 70 || (g >= 205 && g - b >= 60))
                                break
                            j++
                        }
                        MinionsTask._Seed(seeds, rows, i, s, j - 1, ys, x1, stride)
                    } else
                        j++
                    continue
                }
                s := j
                e := MinionsTask._YRun(row, &j, gap)
                len := (e - s + 1) * stride
                if (h := MinionsTask._IsBar(rows, i, s, e, len))
                    MinionsTask._Add(bars, {x: x1 + ((s + e) // 2) * stride - stride, y: ys[i], w: len, h: h})
                else if IsObject(seeds)
                    MinionsTask._Seed(seeds, rows, i, s, e, ys, x1, stride)
            }
        }
        return bars
    }

    ; From j (a yellow pixel): the end of its yellow run, gaps up to gap
    ; bridged; j is left just after it.
    static _YRun(row, &j, gap) {
        n := row.Length                          ; IsYellow inline (a sand or gold scene: long runs)
        while (j <= n) {
            c := row[j]
            if (c < 0xE10000 || ((c >> 8) & 0xFF) < 205 || ((c >> 8) & 0xFF) - (c & 0xFF) < 60)
                break
            j++
        }
        Loop {
            k := j
            while (k <= n && k - j <= gap) {
                c := row[k]
                if (c >= 0xE10000 && ((c >> 8) & 0xFF) >= 205 && ((c >> 8) & 0xFF) - (c & 0xFF) >= 60)
                    break
                k++
            }
            if (k > n || k - j > gap)
                break
            j := k
            while (j <= n) {
                c := row[j]
                if (c < 0xE10000 || ((c >> 8) & 0xFF) < 205 || ((c >> 8) & 0xFF) - (c & 0xFF) < 60)
                    break
                j++
            }
        }
        return j - 1
    }

    ; FindBars' bar test for the yellow run rows[i][s..e] (len px). A near
    ; bar is taller (live 2026-11-02 SNOWY: an orb's bar 146 px wide, yellow
    ; 6 px over orange 5 px; a minion's 118 px, 5 over 3 and a red line
    ; under it): a bar wider than 8 * BarAspect px may be up to len /
    ; BarAspect px tall, its orange starting lower and its clear row (the
    ; first after the orange) farther down; a narrower one is tested as
    ; ever (orange 2 or 4 px lower, clear 8 px lower). A wider bar's orange
    ; ends red: one of its orange rows DeepOrange red ("d"); the gold
    ; leaderboard sign's base and roof edge (live 2026-11-02 NORMAL, 256 and
    ; 160 px, ~20 px tall) and the Donate board's trim (100 px) are yellow
    ; over a shade no redder than r - g 55. A narrower one is no paler than
    ; the darker of the rows over and under it (_Pale darker): the gold sign
    ; base's top edge under the sky and the leaderboard's gold trim over its
    ; navy (live 2026-11-03 NORMAL, 26..44 px: blue over the darker side
    ; 34..67; real narrow bars <= 23, fog washes both sides). Not under
    ; orange either (AboveWarm: a brick block's yellow lip, 2026-11-03).
    ;
    ; Point-blank bars (clips L19 2026-11-03 SNOWY 053406 / LOST FOREST
    ; 053906, minions in the player's face: 290..1210 px, the orb's ~610)
    ; are 16..92 px tall: yellow 4..18 px over an orange-to-red gradient with
    ; the HP text dark across its middle (a row only 0.40 orange) and a
    ; blurred top / bottom edge row. So a tall bar (wider than 8 *
    ; BarAspect) may have a yellow row over its top row (its blurred edge:
    ; the row over that clear), keeps going through rows at least TallLoose
    ; warm (the text) and has its clear row 2 px lower when the first one
    ; is its blurred edge. -> its height in px (yellow + orange rows; 0 =
    ; no bar).
    static _IsBar(rows, i, s, e, len) {
        n := rows.Length
        if (len < MinionsTask.MinRun || len > MinionsTask.MaxRun)
            return 0
        if (MinionsTask._Cover(rows[i], s, e, "y") < MinionsTask.RunCover)
            return 0
        tall := len > 8 * MinionsTask.BarAspect
        if (i - 1 >= 1) {
            up := MinionsTask._Cover(rows[i - 1], s, e, "y")
            ; a tall bar's blurred top row over this one: clear over it
            top := tall && up > MinionsTask.EdgeCover
                && (i - 2 < 1 || MinionsTask._Cover(rows[i - 2], s, e, "yo") <= MinionsTask.EdgeCover)
            if (!top && (up > MinionsTask.EdgeCover || MinionsTask._Cover(rows[i - 1], s, e, "yo") > MinionsTask.AboveWarm))
                return 0
        }
        last := i + Max(4, len // (MinionsTask.BarAspect * MinionsTask.RowStep))
        first := last - 2                        ; the latest row orange may start
        d := i + 1, orange := false
        deep := !tall
        hue := 100                               ; the reddest orange row's (narrow bars: GoldHue)
        while (d <= n && d <= last) {
            if (MinionsTask._Cover(rows[d], s, e, "o") >= MinionsTask.BelowCover) {
                if !tall
                    hue := Min(hue, MinionsTask._OrangeHue(rows[d], s, e))
                orange := true
                deep := deep || MinionsTask._Cover(rows[d], s, e, "d") >= MinionsTask.BelowCover
            } else if (orange && tall && MinionsTask._Cover(rows[d], s, e, "yo") >= MinionsTask.TallLoose
                && d + 1 <= n && MinionsTask._Cover(rows[d + 1], s, e, "o") >= MinionsTask.BelowCover) {
                ; the HP text across a tall bar's orange: orange again under it
            } else if orange
                break
            else if (d >= first)
                return 0
            else if (d > i + 2 && MinionsTask._Cover(rows[d], s, e, "yo") < (tall ? MinionsTask.TallLoose : MinionsTask.RunCover))
                return 0                         ; a tall bar's yellow is solid (but its HP text)
            d++
        }
        if (!orange || !deep || d > last)        ; d > last: still orange there
            return 0
        h := (d - i) * MinionsTask.RowStep
        c := Max(d, i + 4)
        if (c <= n && MinionsTask._Cover(rows[c], s, e, "yo") > MinionsTask.EdgeCover) {
            ; a tall bar's blurred lower edge: clear one row lower
            if (!tall || c + 1 > n || MinionsTask._Cover(rows[c + 1], s, e, "yo") > MinionsTask.EdgeCover)
                return 0
            c++
        }
        ; gold on white, not a red-orange bar: HEAVEN's floor trim (GoldHue)
        if (!tall && hue > MinionsTask.GoldHue && i > 1 && c <= n
            && MinionsTask._DarkOf(rows[i - 1], s, e) >= MinionsTask.GoldWhite
            && MinionsTask._DarkOf(rows[c], s, e) >= MinionsTask.GoldWhite)
            return 0
        return MinionsTask._Pale(rows, i, s, e, c, !tall) ? 0 : h
    }

    ; the median of the darkest channel over row[s..e]
    static _DarkOf(row, s, e) {
        dark := []
        Loop e - s + 1 {
            c := row[s + A_Index - 1]
            dark.Push(Min((c >> 16) & 0xFF, (c >> 8) & 0xFF, c & 0xFF))
        }
        return MinionsTask._Median(dark)
    }

    ; A far bar is only 2..5 px (live 2026-11-02 WINDY: a minion's bar one
    ; yellow row over one red-orange row, "100 / 100" written ABOVE it), so
    ; rows 2 px apart see one row of it or two, never the orange under the
    ; yellow. A seed: a run ThinMin..ThinMax px, at least RunCover yellow /
    ; orange, with at most ThinAlone yellow / orange 4 px above and below
    ; (a far bar is thin; lava, sand, a roof or a pumpkin is not).
    static _Seed(seeds, rows, i, s, e, ys, x1, stride) {
        len := (e - s + 1) * stride
        if (len < MinionsTask.ThinMin || len > MinionsTask.ThinMax || i < 3 || i + 2 > rows.Length)
            return
        if (MinionsTask._Warm(rows[i - 2], s, e, MinionsTask.ThinAlone)
            || MinionsTask._Warm(rows[i + 2], s, e, MinionsTask.ThinAlone)
            || MinionsTask._Cover(rows[i], s, e, "yo") < MinionsTask.RunCover)
            return
        seeds.Push({x: x1 + ((s + e) // 2) * stride - stride, y: ys[i], w: len})
    }

    ; seeds (FindBars, top to bottom) not on a bar found -> Array of row
    ; lists (every row ThinPad above to ThinPad below a seed, overlaps
    ; merged), ThinCap rows at most (a warm scene: 2026-11-02 frames had
    ; up to 174).
    static ThinRows(seeds, bars) {
        wins := []
        pad := MinionsTask.ThinPad
        for sd in seeds {
            on := false
            for o in bars
                if (Abs(o.y - sd.y) <= 8 && Abs(o.x - sd.x) <= Max(o.w, sd.w) // 2) {
                    on := true
                    break
                }
            if on
                continue
            lo := Max(0, sd.y - pad)
            if (wins.Length && lo <= wins[-1][2] + 1)
                wins[-1][2] := Max(wins[-1][2], sd.y + pad)
            else
                wins.Push([lo, sd.y + pad])
        }
        out := [], left := MinionsTask.ThinCap
        for w in wins {
            ys := []
            y := w[1]
            while (y <= w[2] && left > 0)
                ys.Push(y++), left--
            if ys.Length
                out.Push(ys)
            if (left <= 0)
                break
        }
        return out
    }

    ; Far bars in rows 1 px apart (ys, the ThinRows): a yellow run
    ; ThinMin..ThinMax px, at least RunCover yellow, orange under BelowCover
    ; of it 1 or 2 px lower, then clear (EdgeCover) 1 and 2 px under that
    ; orange and 4 px above the yellow (the text above it is nearer), and
    ; not pale (_PaleOn). A shop button's yellow-to-orange top edge has its
    ; yellow face 2 px under (live 2026-11-02 "Donate" sign). The orange
    ; row is red-orange (_OrangeHue at most ThinHue, real <= 44 even
    ; washed): a lit bookshelf or the Donate board's trim is yellow over
    ; amber (~55, live 2026-11-03). -> bars as FindBars.
    static FindThin(rows, ys, x1, stride) {
        bars := []
        at := Map()
        for y in ys
            at[y] := A_Index
        gap := MinionsTask.GapPx // stride
        Loop ys.Length {
            y := ys[A_Index]
            row := rows[A_Index]
            j := 1
            while (j <= row.Length) {
                c := row[j]                          ; IsYellow inline
                if (c < 0xE10000 || ((c >> 8) & 0xFF) < 205 || ((c >> 8) & 0xFF) - (c & 0xFF) < 60) {
                    j++
                    continue
                }
                s := j
                e := MinionsTask._YRun(row, &j, gap)
                len := (e - s + 1) * stride
                if (len < MinionsTask.ThinMin || len > MinionsTask.ThinMax
                    || MinionsTask._Cover(row, s, e, "y") < MinionsTask.RunCover)
                    continue
                k := 0
                for d in [1, 2]
                    if (at.Has(y + d) && MinionsTask._Cover(rows[at[y + d]], s, e, "o") >= MinionsTask.BelowCover) {
                        k := d
                        break
                    }
                if !k
                    continue
                clear := true
                for d in [-4, k + 1, k + 2]
                    if (!at.Has(y + d) || MinionsTask._Cover(rows[at[y + d]], s, e, "yo") > MinionsTask.EdgeCover) {
                        clear := false
                        break
                    }
                if (!clear || MinionsTask._PaleOn(row, s, e, [rows[at[y - 4]], rows[at[y + k + 2]]]))
                    continue
                if (MinionsTask._OrangeHue(rows[at[y + k]], s, e) > MinionsTask.ThinHue)
                    continue
                MinionsTask._Add(bars, {x: x1 + ((s + e) // 2) * stride - stride, y: y, w: len, h: k + 1})
            }
        }
        return bars
    }

    ; Bars in the hand fights' light and view (clips 2026-11-03: none of
    ; them read by FindBars, the RAINY night dims the yellow to d79c0a, so
    ; IsYellow fails): the fill is a vertical gradient, yellow-orange
    ; (g / r ~0.7) over red (g / r ~0.15), low blue, 7..17 px tall; digits
    ; dark across it split a 128 px minion bar with a 40 px gap. A strip: a
    ; warm run (_GradWarm, gaps up to GradGap px bridged) topped by a clear
    ; row, GradTop or more green / red in its top row, GradBottom or less in
    ; its last, about one hue along its length (GradSpread), clear under it.
    ; Shorter than GradMin px: a nearly empty bar, only with GradPlate px
    ; or more of its dark plate right of it (_Plate). -> bars as FindBars.
    static GradMin := 24
    static GradStub := 6
    static GradPlate := 60
    static GradGap := 44
    static GradTop := 55         ; 100 * g / r of the strip's top (real 62..81; gold signs too)
    static GradBottom := 42      ; ... of its last row (real 5..33; gold signs over 50)
    static GradSpread := 20
    static GradCover := 0.45     ; of the run warm: still the strip
    static GradClear := 0.3      ; warm over / under the strip at most
    static GradBlue := 90
    static GradRed := 0x960000   ; a warm px: this red or more (as one number: r first)
    static GradRB := 100         ; ... and red over blue by this much
    static GradSolid := 0.6
    static GradNear := 16
    ; The thresholds FindGrad and _HotBoxes read with: the rain's, or the usual
    ; (_Scan: RAINY only). Rain mutes a far bar to about (155,138,96) over
    ; (159,66,99): red under 150, red over blue near 60, blue over 90, and the
    ; last row read can be a little over GradBottom, so orbs on screen read as
    ; no bars (L47 16:05:52, L45 14:18:32). 48 RAINY frames: 41 bars -> 65, all
    ; 24 new ones real, none lost. RainBottom 58 read 3 bars more, and the gold
    ; frame of a reward window as two bars (L45 14:19:29).
    static _GradLook(rain) {
        MinionsTask.GradRain := rain
        MinionsTask.GradRed := rain ? MinionsTask.RainRed : 0x960000
        MinionsTask.GradRB := rain ? MinionsTask.RainRB : 100
        MinionsTask.GradBlue := rain ? MinionsTask.RainBlue : 90
        MinionsTask.GradBottom := rain ? MinionsTask.RainBottom : 42
    }
    static GradRain := false
    static RainRed := 0x780000
    static RainRB := 45
    static RainBlue := 125
    static RainBottom := 50
    ; FindGrad; in rain the usual read stands and the rain's only adds what
    ; lies beside no bar of it: its loose warm takes a bright bar's name for
    ; bar and cuts its start (L46 15:49:57), or runs it into what is next to
    ; it, too flat to stay a bar (L53 11:16:00) or two bars as one (clip
    ; nodeath_voidrush_rainy).
    static _GradPass(rows, ys, x1, stride) {
        bars := MinionsTask.FindGrad(rows, ys, x1, stride)
        if !MinionsTask.GradRain
            return bars
        MinionsTask._GradLook(false)
        try out := MinionsTask.FindGrad(rows, ys, x1, stride)
        finally MinionsTask._GradLook(true)
        for b in bars {
            near := b.w > MinionsTask.FlatAspect * b.h
            for o in out
                near := near || MinionsTask._GradBeside(o, b)
            if !near
                out.Push(b)
        }
        return out
    }

    static FindGrad(rows, ys, x1, stride) {
        bars := []
        gap := MinionsTask.GradGap // stride
        red := MinionsTask.GradRed, rb := MinionsTask.GradRB
        n := rows.Length
        Loop n - 2 {
            i := A_Index + 1
            row := rows[i], up := rows[i - 1]
            j := 1, m := row.Length
            while (j <= m) {
                c := row[j]                          ; _GradWarm inline (the hot loop)
                if (c < red || (c >> 16) - (c & 0xFF) < rb) {
                    j++
                    continue
                }
                c := up[j]
                if (c >= red && (c >> 16) - (c & 0xFF) >= rb) {
                    j++
                    continue
                }
                s := j, e := j, k := j + 1, hit := 1, big := 0
                while (k <= m && k - e <= gap) {
                    c := row[k]
                    if (c >= red && (c >> 16) - (c & 0xFF) >= rb) {
                        if (k - e - 1 > big)
                            big := k - e - 1
                        e := k, hit++
                    }
                    k++
                }
                j := e + 1
                ; solid but for one gap (the digits); a name's letters are not
                if (hit >= MinionsTask.GradSolid * (e - s + 1 - big)
                    && (b := MinionsTask._GradBar(rows, i, s, e, ys, x1, stride)))
                    MinionsTask._GradAdd(bars, b)
            }
        }
        return bars
    }

    ; b into bars: one bar with what lies just over or under it (its name,
    ; the red line under a minion's), the wider one kept
    static _GradAdd(bars, b) {
        for o in bars
            if MinionsTask._GradBeside(o, b) {
                if (b.w > o.w)
                    o.x := b.x, o.y := b.y, o.w := b.w, o.h := b.h
                return
            }
        bars.Push(b)
    }

    static _GradBeside(o, b) => Abs(o.y - b.y) <= MinionsTask.GradNear && Abs(o.x - b.x) <= (o.w + b.w) // 2

    static _GradWarm(c) => c >= MinionsTask.GradRed && (c >> 16) - (c & 0xFF) >= MinionsTask.GradRB

    ; FindGrad's strip test for rows[i][s..e] -> a bar or 0.
    static _GradBar(rows, i, s, e, ys, x1, stride) {
        len := (e - s + 1) * stride
        if (len < MinionsTask.GradStub || len > MinionsTask.MaxRun)
            return 0
        if (MinionsTask._GradCover(rows[i], s, e) < MinionsTask.GradCover
            || MinionsTask._GradCover(rows[i - 1], s, e) > MinionsTask.GradClear)
            return 0
        d := i + 1
        while (d <= rows.Length && MinionsTask._GradCover(rows[d], s, e) >= MinionsTask.GradCover)
            d++
        h := (d - i) * MinionsTask.RowStep
        if (h < 4 || d > rows.Length || (len >= MinionsTask.GradMin && h > Max(10, len // 4 + 6)) || h > 24)
            return 0
        t := MinionsTask._GradHue(rows[i + (h > 6 ? 1 : 0)], s, e)
        last := MinionsTask._GradHue(rows[d - 1], s, e)
        if (t.hue < MinionsTask.GradTop || last.hue > MinionsTask.GradBottom || t.blue > MinionsTask.GradBlue
            || t.spread > MinionsTask.GradSpread)
            return 0
        if (d + 1 <= rows.Length && MinionsTask._GradCover(rows[d + 1], s, e) > MinionsTask.GradClear)
            return 0
        if (len < MinionsTask.GradMin && MinionsTask._Plate(rows[i + (d - i) // 2], rows[Max(1, i - 2)], rows[Min(d + 2, rows.Length)], e, stride) < MinionsTask.GradPlate)
            return 0
        return {x: x1 + ((s + e) // 2) * stride - stride, y: ys[i], w: len, h: h}
    }

    static _GradCover(row, s, e) {
        hit := 0, i := s, red := MinionsTask.GradRed, rb := MinionsTask.GradRB
        Loop e - s + 1 {
            c := row[i++]
            if (c >= red && (c >> 16) - (c & 0xFF) >= rb)
                hit++
        }
        return hit / (e - s + 1)
    }

    ; The warm px of row[s..e]: {hue: median 100 * g / r, blue: median, spread:
    ; the hues of its two halves apart}
    static _GradHue(row, s, e) {
        a := [], b := [], blue := [], mid := (s + e) // 2
        Loop e - s + 1 {
            j := s + A_Index - 1, c := row[j]
            if !MinionsTask._GradWarm(c)
                continue
            r := (c >> 16) & 0xFF, h := 100 * ((c >> 8) & 0xFF) // r
            (j <= mid ? a : b).Push(h)
            blue.Push(c & 0xFF)
        }
        if !blue.Length
            return {hue: 100, blue: 255, spread: 100}
        all := a.Clone()
        all.Push(b*)
        ma := a.Length ? MinionsTask._Median(a) : MinionsTask._Median(b)
        mb := b.Length ? MinionsTask._Median(b) : ma
        return {hue: MinionsTask._Median(all), blue: MinionsTask._Median(blue), spread: Abs(ma - mb)}
    }

    ; px of a bar's dark plate (the HP lost) right of column e of row: dark
    ; (PlateDark) and PlateDiff or more apart (three channels added) from
    ; both refs, rows of the world just over and under the bar (night ground
    ; 112025 and the plate 1a1218 differ by 30; the ground beyond the plate
    ; is like one of them at least), up to PlateMiss px of anything else
    ; bridged (digits on it). 0 = none: a full bar.
    ; The plate is a dark maroon (1a1218, 0d0d15 at its bluest, 2e110d over
    ; fire): green over red by PlateGreen at most, blue over red PlateBlue,
    ; green over blue PlateWarm. Any dark world px counted before: LOST
    ; FOREST's ground (132224, 00301b, 213313) and a roof read as plate, a
    ; full 300 / 300 orb as 100/232 (live 18:26), "beside it" 40 m away. At
    ; least PlateCover of its length must be plate (the rest digits).
    ; Over bright green the plate shows through warmer and lighter (L47
    ; 16:55:10 2b1b00, 4f3521, 7b5941: 164 / 300 read as 1.00, a hurt orb as
    ; narrow as its HP): a loose read too (PlateDarkLoose, PlateWarmLoose,
    ; red over green PlateRedLoose at most), taken only from PlateLooseMin px
    ; (shorter it is scenery as often as plate), else the strict one as ever.
    static PlateDark := 100
    static PlateDiff := 12
    static PlateMiss := 24
    static PlateGreen := 4
    static PlateBlue := 10
    static PlateWarm := 12
    static PlateCover := 0.5
    static PlateDarkLoose := 130
    static PlateWarmLoose := 45
    static PlateRedLoose := 45
    static PlateLooseMin := 20
    static _Plate(row, up, down, e, stride) {
        p := MinionsTask._PlateRun(row, up, down, e, stride, true)
        return p >= MinionsTask.PlateLooseMin ? p : MinionsTask._PlateRun(row, up, down, e, stride, false)
    }

    static _PlateRun(row, up, down, e, stride, loose) {
        miss := MinionsTask.PlateMiss // stride, k := e + 2, last := e, hits := 0
        while (k <= row.Length && k - last <= miss) {
            c := row[k]
            if ((loose ? MinionsTask._PlateDim(c) : MinionsTask._PlateDark(c)) && MinionsTask._Apart(c, up[k]) && MinionsTask._Apart(c, down[k]))
                last := k, hits++
            k++
        }
        return (hits >= MinionsTask.PlateCover * (last - e - 1)) ? (last - e) * stride : 0
    }

    static _PlateDark(c) {
        r := (c >> 16) & 0xFF, g := (c >> 8) & 0xFF, b := c & 0xFF
        return Max(r, g, b) <= MinionsTask.PlateDark && g - r <= MinionsTask.PlateGreen
            && b - r <= MinionsTask.PlateBlue && g - b <= MinionsTask.PlateWarm
    }

    static _PlateDim(c) {
        r := (c >> 16) & 0xFF, g := (c >> 8) & 0xFF, b := c & 0xFF
        return Max(r, g, b) <= MinionsTask.PlateDarkLoose && g - r <= MinionsTask.PlateGreen
            && b - r <= MinionsTask.PlateBlue && g - b <= MinionsTask.PlateWarmLoose
            && r - g <= MinionsTask.PlateRedLoose
    }

    static _Apart(c, d) => Abs(((c >> 16) & 0xFF) - ((d >> 16) & 0xFF)) + Abs(((c >> 8) & 0xFF) - ((d >> 8) & 0xFF))
        + Abs((c & 0xFF) - (d & 0xFF)) >= MinionsTask.PlateDiff

    ; b gets full (px, its plate with it) and fill (0..1): the HP left, from
    ; the row through its middle in rows (Scan's: ys, from x1 every stride-th).
    static _Fill(b, rows, ys, x1, stride) {
        at := MinionsTask._FillRows(b, ys, rows.Length)
        MinionsTask._FillFrom(b, rows[at.mid], rows[at.up], rows[at.down], x1, stride)
    }

    ; The rows _Fill reads, as indexes of ys (n rows).
    static _FillRows(b, ys, n) {
        h := b.HasOwnProp("h") ? b.h : 4
        at := (y) => Min(n, Max(1, (y - ys[1]) // MinionsTask.RowStep + 1))
        return {mid: at(b.y + h // 2), up: at(b.y - 4), down: at(b.y + h + 4)}
    }

    static _FillFrom(b, row, up, down, x1, stride) {
        e := (b.x + b.w // 2 - x1) // stride + 1
        p := (e >= 1 && e <= row.Length) ? MinionsTask._Plate(row, up, down, e, stride) : 0
        b.full := b.w + p
        b.fill := Round(b.w / b.full, 2)
    }

    ; _Cover(row, s, e, "yo") > limit, stopping as soon as that is decided
    ; (IsYellow / IsOrange inline: many seeds in a warm scene).
    static _Warm(row, s, e, limit) {
        n := e - s + 1
        need := Floor(limit * n) + 1             ; hits for a share over limit
        miss := n - need + 1                     ; misses that rule it out
        hit := 0
        Loop n {
            c := row[s + A_Index - 1]
            if (c >= 0xE10000) {
                r := c >> 16, g := (c >> 8) & 0xFF, b := c & 0xFF
                if ((g >= 205 && g - b >= 60) || (r - g >= 35 && r - b >= 70)) {
                    if (++hit >= need)
                        return true
                    continue
                }
            }
            if (--miss <= 0)
                return false
        }
        return false
    }

    ; Share of row[s..e] that is yellow ("y"), orange ("o"), either ("yo")
    ; or orange at least DeepOrange red ("d").
    static _Cover(row, s, e, kind) {
        hit := 0, i := s, wy := kind = "y" || kind = "yo", wo := kind != "y"
        deep := kind = "d" ? MinionsTask.DeepOrange : 0
        Loop e - s + 1 {                         ; IsYellow / IsOrange inline
            c := row[i++]
            if (c < 0xE10000)
                continue
            r := (c >> 16) & 0xFF, g := (c >> 8) & 0xFF, b := c & 0xFF
            if (wy && g >= 205 && g - b >= 60)
                hit++
            else if (wo && r - g >= 35 && r - b >= 70 && r - g >= deep)
                hit++
        }
        return hit / (e - s + 1)
    }

    ; A pale yellow strip on a dark background: the gold leaderboard sign
    ; near spawn (2026-11-02, its yellow 255,255,126..182 between dark blue
    ; panels) or the like. A real bar's yellow is pure (blue ~0) unless fog
    ; washes it, and fog washes the background around it as much or more
    ; (sand storm: bar blue ~150, fog around it 160..200). -> true when the
    ; median blue of the yellow in row i is more than PaleOver above the
    ; median darkest channel 2 px above and in row below (default 8 px
    ; below: the bar's clear row; the brighter side; darker: the darker
    ; side when it has both rows).
    static _Pale(rows, i, s, e, below := 0, darker := false) {
        bg := []
        for r in [i - 1, below ? below : i + 4]
            if (r >= 1 && r <= rows.Length)
                bg.Push(rows[r])
        return MinionsTask._PaleOn(rows[i], s, e, bg, darker && bg.Length = 2)
    }

    ; _Pale for the yellow in row[s..e] against the rows bgRows (the
    ; brightest of their medians; darker: the darkest).
    static _PaleOn(row, s, e, bgRows, darker := false) {
        blue := []
        Loop e - s + 1 {
            c := row[s + A_Index - 1]
            if MinionsTask.IsYellow(c)
                blue.Push(c & 0xFF)
        }
        bg := -1
        for r in bgRows {
            dark := []
            Loop e - s + 1 {
                c := r[s + A_Index - 1]
                dark.Push(Min((c >> 16) & 0xFF, (c >> 8) & 0xFF, c & 0xFF))
            }
            v := MinionsTask._Median(dark)
            bg := bg < 0 ? v : darker ? Min(bg, v) : Max(bg, v)
        }
        return bg >= 0 && blue.Length && MinionsTask._Median(blue) - bg > MinionsTask.PaleOver
    }

    ; The median of a, the upper middle one of an even count.
    static _MedianHi(a) {
        s := ""
        for v in a
            s .= v "`n"
        a := StrSplit(Sort(RTrim(s, "`n"), "N"), "`n")
        return Integer(a[a.Length // 2 + 1])
    }

    ; Median hue of the orange pixels in row[s..e]: 100 * (g - b) / (r - b),
    ; 0 red .. 100 yellow (none orange: 100).
    static _OrangeHue(row, s, e) {
        h := []
        Loop e - s + 1 {
            c := row[s + A_Index - 1]
            if MinionsTask.IsOrange(c) {
                r := (c >> 16) & 0xFF, g := (c >> 8) & 0xFF, b := c & 0xFF
                h.Push(Max(0, 100 * (g - b) // (r - b)))
            }
        }
        return h.Length ? MinionsTask._Median(h) : 100
    }

    static _Median(a) {
        s := ""
        for v in a
            s .= v "`n"
        a := StrSplit(Sort(RTrim(s, "`n"), "N"), "`n")
        return Integer(a[(a.Length + 1) // 2])
    }

    ; Two runs of one bar (its two yellow rows) count once: the wider kept.
    static _Add(bars, b) {
        for o in bars
            if (Abs(o.y - b.y) <= 6 && Abs(o.x - b.x) <= Max(o.w, b.w) // 2) {
                if (b.w > o.w)
                    o.x := b.x, o.y := b.y, o.w := b.w
                if (b.HasOwnProp("h") && (!o.HasOwnProp("h") || b.h > o.h))
                    o.h := b.h
                return
            }
        bars.Push(b)
    }

    ; Nothing in sight after a full look around: give up once the respawn
    ; wait is done (rewaited) and OrbLateMs have passed since the biome
    ; started (biomeAt, Now() ms; "" = unknown: right after the wait), and
    ; no bar was seen for SeenQuietMs (lastSeen, Now() ms; "" = none yet):
    ; live 2026-11-02 a fog orb went out of sight for 8 s and the hunt gave
    ; up with the orb still there. quiet: SeenQuietMs (boss mode: BossQuietMs).
    static GiveUp(rewaited, now, biomeAt, lastSeen := "", quiet := "") => rewaited
        && (biomeAt = "" || now - biomeAt >= MinionsTask.OrbLateMs)
        && (lastSeen = "" || now - lastSeen >= (quiet = "" ? MinionsTask.SeenQuietMs : quiet))

    ; The biome now (b) is another than at the hunt's start (b0); "" on
    ; either side = unknown, ignored.
    static BiomeLeft(b0, b) => b0 != "" && b != "" && b != b0

    ; Give up later: a target (a bar, a glow) seen at most PursueMs ago
    ; (lastSeen: Now() ms, "" = none) -> after it again (PursueStyles).
    static Pursue(now, lastSeen) => lastSeen != "" && now - lastSeen <= MinionsTask.PursueMs

    ; The view from rows (grab shape: one Array per y in ys, every
    ; stride-th px from x1): {edge, sig}. edge: EdgeAhead; sig: the px of
    ; the rows to ViewSigY out of the ViewSkip column (for ViewSame).
    static ViewOf(rows, ys, x1, stride) {
        sig := []
        sk := MinionsTask.ViewSkip
        for i, row in rows {
            if (ys[i] > MinionsTask.ViewSigY)
                break
            for j, c in row {
                x := x1 + (j - 1) * stride
                if (x < sk.x1 || x > sk.x2)
                    sig.Push(c)
            }
        }
        l := MinionsTask.EdgeOn(rows, ys, x1, stride, MinionsTask.EdgeL)
        r := MinionsTask.EdgeOn(rows, ys, x1, stride, MinionsTask.EdgeR)
        return {edge: l || r, edgeL: l, edgeR: r, sig: sig}
    }

    ; The island's edge beside the character's legs: of the px in rows
    ; EdgeY1 or lower, in EdgeL or in EdgeR, EdgeShare or more sea / sky
    ; blue (IsSea).
    static EdgeAhead(rows, ys, x1, stride) => MinionsTask.EdgeOn(rows, ys, x1, stride, MinionsTask.EdgeL)
        || MinionsTask.EdgeOn(rows, ys, x1, stride, MinionsTask.EdgeR)

    ; ... on that side alone
    static EdgeOn(rows, ys, x1, stride, side) {
        n := 0, nb := 0
        for i, row in rows {
            if (ys[i] < MinionsTask.EdgeY1)
                continue
            for j, c in row {
                x := x1 + (j - 1) * stride
                if (x < side.x1 || x > side.x2)
                    continue
                n++
                nb += MinionsTask.IsSea(c)
            }
        }
        return n && nb >= MinionsTask.EdgeShare * n
    }

    ; The daytime sea / sky blue past the island's edge (clip 2026-11-03
    ; ~(110, 170, 230)): blue >= 170, 50 over red, 20 over green, green over
    ; red (a cyan floor pad, blue = green: none).
    static IsSea(c) {
        r := (c >> 16) & 0xFF, g := (c >> 8) & 0xFF, b := c & 0xFF
        return b >= 170 && b - r >= 80 && b - g >= 20 && g >= r      ; snow floor b - r <= 56 (L23 SNOWY), sea >= 104
    }

    ; Two view signatures (ViewOf) about the same: under SameShare of the
    ; px changed (a channel by over SameDiff). Different lengths: not.
    static ViewSame(a, b) {
        if (!IsObject(a) || !IsObject(b) || a.Length != b.Length || !a.Length)
            return false
        d := MinionsTask.SameDiff, ch := 0
        for i, c in a {
            e := b[i]
            if (Abs(((c >> 16) & 0xFF) - ((e >> 16) & 0xFF)) > d || Abs(((c >> 8) & 0xFF) - ((e >> 8) & 0xFF)) > d
                || Abs((c & 0xFF) - (e & 0xFF)) > d)
                ch++
        }
        return ch < MinionsTask.SameShare * a.Length
    }

    ; The same bar as before, about where it was: the walk got nowhere.
    ; a square round the start: the spiral walked off the island (66 of 84 deaths were falls, half 2-7 s of walking out)
    static Spiral(leg) => MinionsTask.PatrolSteps

    ; Where the player is, to the PatrolCell: the map's squares it has searched
    static Cell(pos) => Round(pos.x / MinionsTask.PatrolCell) "," Round(pos.y / MinionsTask.PatrolCell)

    ; The bearing of the next leg: of the 8 ways, the one ending in the square
    ; searched least; off PatrolRadiusMs or towards a remembered fall counts as searched
    static PatrolHeading(pos, searched, falls, now, walls := "") {
        best := 0, bs := "", ms := MinionsTask.PatrolSteps * MinionsTask.WalkMs
        Loop 8 {
            b := (A_Index - 1) * MinionsTask.FullTurnMs // 8
            u := MinionsTask.Way(b), p := {x: pos.x + u.x * ms, y: pos.y + u.y * ms}
            k := MinionsTask.Cell(p)
            sc := searched.Has(k) ? searched[k] : 0
            if (Sqrt(p.x * p.x + p.y * p.y) > MinionsTask.PatrolRadiusMs)
                sc += 50
            if MinionsTask.FallAhead(falls, pos, b, ms, now)
                sc += 20
            if IsObject(walls)                   ; walls given up on in this biome
                for w in walls
                    if MinionsTask.OnWall(w, b)
                        sc += 100
            if (bs = "" || sc < bs)
                bs := sc, best := b
        }
        return best
    }

    ; The orb's HP (OrbHp) under OrbLowFill, read in the last OrbLowMs,
    ; skills cast on it once the orb can be hurt at all: a false low read
    ; beside live minions forces no stand
    static OrbNearlyDead(f, now) => MinionsTask.Unlocked(f) && f.casts && (hp := MinionsTask.OrbHp(f)) != "" && hp <= MinionsTask.OrbLowFill && f.orbAt && now - f.orbAt < MinionsTask.OrbLowMs

    ; An orb-alone read of fill kept: the last OrbHpReads of them
    static OrbRead(f, fill) {
        f.orbReads.Push(fill)
        while (f.orbReads.Length > MinionsTask.OrbHpReads)
            f.orbReads.RemoveAt(1)
    }

    ; The orb's HP: it has no regen and one read jumps (L72 05:03:27-35:
    ; 0.15, 1.00, 0.06), so the lowest of its last reads ("" = none; no
    ; reads kept: the last fill)
    static OrbHp(f) {
        if !(f.HasOwnProp("orbReads") && f.orbReads.Length)
            return f.HasOwnProp("orbFill") ? f.orbFill : ""
        hp := ""
        for r in f.orbReads
            hp := (hp = "" || r < hp) ? r : hp
        return hp
    }

    ; The orb's minions are down (OpenDown), beside it in this life too. Not
    ; on the way there: a re-hunt keeps the count and starts at spawn.
    ; no minion bar lately too: toasts overcount (L54 12:03:51 "open", minions 0.79, 0.13 at 12:04:05)
    static Open(f) => f.down >= MinionsTask.OpenDown && !(f.HasOwnProp("foes") && f.foes.Length)
    static Stay(f) => f.here && MinionsTask.Open(f)

    ; Its fill counts: the orb is open, a boss has no minions
    static Unlocked(f) => f.boss || MinionsTask.Open(f)
        || (f.HasOwnProp("orbHurt") && f.orbHurt && !(f.HasOwnProp("foes") && f.foes.Length))

    ; An orb-alone read of fill at now (HurtOpenFill): -> true once the bar
    ; has gone down (sets f.orbHurt). f.hurtFirst / hurtFirstAt: the read to
    ; beat, the highest low one lately. A minion's bar in view lately (f.foes,
    ; DodgeHoldMs): the lone bar is mostly a near minion read as the orb (it
    ; is over OrbLonePx up close), its fill going down under the casts: no
    ; read (L71 02:47:05 "0.02" and 03:28:44 "0.51", the minions at 1.00 and
    ; 0.65 the next read: the Locked orb then stood for and cast at). A whole
    ; read starts it again: the orb has no regen.
    static OrbHurtStep(f, fill, now) {
        if ((f.HasOwnProp("foes") && f.foes.Length) || (f.HasOwnProp("loneFoe") && f.loneFoe))
            return false
        if (fill > MinionsTask.HurtOpenFill)
            f.hurtFirst := ""
        if (fill > MinionsTask.HurtOpenFill || fill < 0)
            return false
        if (f.hurtFirst != "" && now - f.hurtFirstAt <= MinionsTask.HurtOpenMs && fill <= f.hurtFirst - MinionsTask.HurtOpenDrop)
            return f.orbHurt := true
        if (f.hurtFirst = "" || now - f.hurtFirstAt > MinionsTask.HurtOpenMs || fill > f.hurtFirst)
            f.hurtFirst := fill, f.hurtFirstAt := now
        return false
    }

    ; The hunt goes on past its time (ran: ms so far)
    static HuntOn(f, now, ran) => ran < MinionsTask.HuntCapMs
        && (MinionsTask.Open(f) || (f.hurtAt != "" && now - f.hurtAt < MinionsTask.HurtKeepMs))

    static Same(b, prev) => IsObject(prev) && Abs(b.y - prev.y) <= 12 && Abs(b.w - prev.w) <= 10 && Abs(b.x - prev.x) <= 160
    ; b wider or lower than prev (none before: a new target)
    static Nearer(b, prev) => !IsObject(prev) || b.w - prev.w > 10 || b.y - prev.y > 12

    ; The glow g (OrbBeacon) about as at a, an earlier walk's (a glow is
    ; measured RowStep / Stride coarse): the walks since got it no lower and
    ; no bigger. Compared with where the stuck count started, not the last
    ; walk: a far orb grows only a few px a walk.
    static GlowSame(g, a) => IsObject(a) && Abs(g.y - a.y) <= 8 && Abs(g.r - a.r) <= 4

    ; The target t ({y, w}; a glow: w = 2 r) nearer than at the wall slide's
    ; start (ref): WallGainPx wider or lower on screen (level with the
    ; player, up on the terrace).
    static WallCloser(t, ref) => t.w >= ref.w + MinionsTask.WallGainPx || t.y >= ref.y + MinionsTask.WallGainPx

    ; ... WallLooks looks running (w: the wall's state, gain its count, y / w
    ; the bar at its worst this leg; quiet: ms of the leg with no gain)
    static WallGained(w, t) {
        if (w.ms < w.quiet) {
            w.gain := 0, w.y := t.y, w.w := t.w
            return false
        }
        if MinionsTask.WallCloser(t, w) {
            w.gain++
            return w.gain >= MinionsTask.WallLooks
        }
        w.gain := 0, w.y := Min(w.y, t.y), w.w := Min(w.w, t.w)
        return false
    }

    ; bearing b (ms) within WallOffCone of the wall left alone (o: {b})
    static OnWall(o, b) => Abs(MinionsTask.Wrap(b - o.b)) <= MinionsTask.WallOffCone

    ; bars (or glows) without those at that wall as seen from bearing b,
    ; a near bar kept: it came to the player
    static OffWall(bars, o, b) {
        out := []
        for t in bars
            if ((t.HasOwnProp("w") && MinionsTask.FullW(t) >= MinionsTask.BesideMinionW)
                || !MinionsTask.OnWall(o, b + Round((t.x - MinionsTask.CenterX) / MinionsTask.TurnPxPerMs)))
                out.Push(t)
        return out
    }

    ; The player's HP through grab (screen = its coords + ox, oy; real
    ; crops: tests\screens\player_hp_*): per PlayerHpYs row, the run of fill
    ; from PlayerHpX1 on, over the 119 px to PlayerHpX2 -> run / 119; the
    ; median of the rows read. The fill alone: the grey of the HP lost was
    ; too dark at night (clip 224541920 22:45: 87, a floor of 110) and the
    ; vignette tints it, a read of fill and grey and the bar's right end gave
    ; -1 on L44 13:54:32, L46 15:05:30, 15:37:04, 15:47:33 and that whole clip.
    ; -> 0..1, -1 = no bar (full HP, or not the player list).
    static PlayerHp(grab, ox := 0, oy := 0) {
        ys := []
        for y in MinionsTask.PlayerHpYs
            ys.Push(y - oy)
        x1 := MinionsTask.PlayerHpX1, x2 := MinionsTask.PlayerHpX2
        n := x2 - x1 + 1
        fr := []
        for row in grab(x1 - 6 - ox, x2 - ox, ys, 1) {
            if (MinionsTask._HpFill(row[1]) && MinionsTask._HpFill(row[2]))   ; the same left of x1: scenery
                continue
            px := 0
            while (px < n && MinionsTask._HpFill(row[7 + px]))
                px++
            if px
                fr.Push(px / n)
        }
        if !fr.Length
            return -1
        if (fr.Length = 3)                       ; the median (_Median is integers only)
            return Round(fr[1] + fr[2] + fr[3] - Max(fr*) - Min(fr*), 2)
        return Round(fr[1], 2)                   ; 1 or 2 rows: the first (top) one
    }

    ; the HP fill: green to teal (00ff9a, 50ff4e), yellow (ffff00), red
    static _HpFill(c) {
        r := (c >> 16) & 0xFF, g := (c >> 8) & 0xFF, b := c & 0xFF
        return (b <= 100 && Max(r, g) >= 200) || (g >= 200 && r <= 120 && b <= 200)
    }

    ; The hunt's one stats line: most bars in sight at once, enemies down
    ; (Orb Minion Awards toasts seen, and the orb), respawn waits, the hunt's
    ; ms; bars left in the end sweep, an orb among them (0|1), the orb killed
    ; (0|1; its Orb Awards toast and no orb in the sweep); skills cast, the
    ; orb's last fill read (-1 none), deaths; " how=toast" with a kill;
    ; " boss=1" in boss mode only.
    static Stats(seen, down, waits, ms, left, orbLeft, orbDown, casts, orbFill, deaths, how := "", boss := 0) => "minions: stats seen=" seen " down=" down " waits=" waits " hunt_ms=" ms " left=" left " orb_left=" orbLeft " orb_down=" orbDown " casts=" casts " orb_fill=" (orbFill = "" ? -1 : orbFill) " deaths=" deaths (how != "" ? " how=" how : "") (boss ? " boss=1" : "")

    ; a bar's width with its dark plate (a hurt bar's yellow is only the HP
    ; left), and its fill (Scan's _Fill; bars without them: full)
    static FullW(b) => b.HasOwnProp("full") ? b.full : b.w
    static FillOf(b) => b.HasOwnProp("fill") ? b.fill : 1

    ; One scan's bars -> {orb, minions, anchor}: the orb ("" = none told
    ; apart, OrbIndex) and the others; anchor: what the camera keeps ahead,
    ; the orb, else the nearest minion (the widest bar). Locked or not: the
    ; same fight.
    ; open (Stay): a lone bar is the orb whatever its width, the hurt orb's
    ; yellow shrinks to a minion's and under (L47 16:55:32 62 px at 114 / 300).
    static View(bars, open := false) {
        if (open && bars.Length = 1)
            return {orb: bars[1], minions: [], anchor: bars[1], lone: true}
        oi := MinionsTask.OrbIndex(bars), mins := [], near := ""
        for i, b in bars
            if (i != oi) {
                mins.Push(b)
                if (!IsObject(near) || MinionsTask.FullW(b) > MinionsTask.FullW(near))
                    near := b
            }
        ; minions up: to them, never the orb, Locked till they die (L58 13:02:15-:31:
        ; the aim swung between both, the character faced the gap, skills hit nothing)
        return {orb: oi ? bars[oi] : "", minions: mins, anchor: IsObject(near) ? near : oi ? bars[oi] : "", lone: false}
    }

    ; v (View's) is beside the fight: a minion's bar BesideMinionW wide, or with
    ; no minion in sight the orb's BesideOrbW (standing already: StandLoose of
    ; those). A wide orb with minions still far is not there yet (the user, L52)
    ; A bar above the player (Above) is neither.
    static Beside(v, standing := false) => (v.HasOwnProp("lone") && v.lone && !MinionsTask.Above(v.anchor, true)) || MinionsTask._Wide(v, standing ? MinionsTask.StandLoose : 1)

    ; the bar b stands above the player (AboveY; orb: the orb's, AboveOrbY)
    static Above(b, orb := false) => IsObject(b) && b.HasOwnProp("y") && b.y < (orb ? MinionsTask.AboveOrbY : MinionsTask.AboveY)

    ; Standing: where the casts go. Locked on, strafing or not (the user,
    ; 2026-11-06: dodging, the attacks went away from the enemy): the widest
    ; minion dead ahead, it must die before the orb can be hurt (L22
    ; 17:31:47-17:32:10: 6 casts, 0 damage, the minions 600 px off centre).
    ; None: the orb (else the anchor), as tight. One ahead of the character
    ; before any behind it (Behind): facing those lands nothing but E, and
    ; with every bar whole the lowest was mostly one behind (L72 SAND STORM).
    static AimAt(v) {
        near := ""                               ; the most hurt, then the lowest: one dead soonest, and never an orb read as a minion
        for b in v.minions
            if (!IsObject(near) || MinionsTask._AimBefore(b, near))
                near := b
        return IsObject(near) ? {x: near.x, tol: MinionsTask.LockTol} : {x: v.anchor.x, tol: MinionsTask.OrbTol}
    }

    ; minion bar b a better aim than c: not above the player (Above), then in
    ; reach (AimMinionW), then ahead of the character, then more hurt, then lower
    static _AimBefore(b, c) {
        ba := MinionsTask.Above(b), ca := MinionsTask.Above(c)
        if (ba != ca)
            return ca
        br := MinionsTask.FullW(b) >= MinionsTask.AimMinionW, cr := MinionsTask.FullW(c) >= MinionsTask.AimMinionW
        if (br != cr)
            return br
        bb := MinionsTask.Behind(b), cb := MinionsTask.Behind(c)
        if (bb != cb)
            return cb
        fb := MinionsTask.FillOf(b), fc := MinionsTask.FillOf(c)
        return fb < fc || (fb = fc && b.y > c.y)
    }

    ; the bar b stands behind the character (BehindY)
    static Behind(b) => IsObject(b) && b.HasOwnProp("y") && b.y > MinionsTask.BehindY

    ; a minion bar of v behind the character (Behind)
    static AnyBehind(v) {
        for b in v.minions
            if MinionsTask.Behind(b)
                return true
        return false
    }

    ; The orb's bar says it stands nearer the camera than the player (see
    ; OrbBehindW): full width, height and height on screen together
    static OrbBehind(v) => IsObject(v.orb) && v.orb.HasOwnProp("h") && v.orb.h >= MinionsTask.OrbBehindH
        && v.orb.y >= MinionsTask.OrbBehindY && MinionsTask.FullW(v.orb) >= MinionsTask.OrbBehindW

    ; a bar's numbers for a log line
    static BarNote(b) => " (full " MinionsTask.FullW(b) ", h " (b.HasOwnProp("h") ? b.h : "?") ", y " b.y ")"

    ; A minion near enough and straight out of the character: F's cloud is about
    ; +-230 px wide (L58 clip); not one behind the character (Behind)
    static InFront(v) {
        for b in v.minions
            if (Abs(b.x - MinionsTask.LockX) <= MinionsTask.ReachDx && MinionsTask.FullW(b) >= MinionsTask.AimMinionW && !MinionsTask.Behind(b))
                return true
        return false
    }

    ; ... nearly: short steps from here
    static Almost(v) => MinionsTask._Wide(v, MinionsTask.AlmostShare)

    static _Wide(v, k) {
        for b in v.minions
            if (MinionsTask.FullW(b) >= k * MinionsTask.BesideMinionW && !MinionsTask.Above(b))
                return true
        ; minions in sight, none near: not there yet, however wide the orb
        return !v.minions.Length && IsObject(v.orb) && MinionsTask.FullW(v.orb) >= k * MinionsTask.BesideOrbW && !MinionsTask.Above(v.orb, true)
    }

    ; ... near enough to cast at from where it stands, a wall between: the
    ; orb almost beside, or a minion faced first (AimMinionW); none above
    ; the player (Above). locked: the orb cannot be hurt, alone it is not
    ; worth a cast (L71 SNOWY 02:46-02:48: ~10 casts at a Locked 144-160 px
    ; orb on a rooftop, its fill 1.00 throughout)
    static InReach(v, locked := false) {
        if (!locked && !v.minions.Length && MinionsTask.Almost(v))
            return true
        for b in v.minions
            if (MinionsTask.FullW(b) >= MinionsTask.AimMinionW && !MinionsTask.Above(b))
                return true
        return false
    }

    ; The casts land: a minion hurt, none left: the orb (its fill reads
    ; wrong in flashes, the minions must die first anyway)
    static Hurt(v) {
        for b in v.minions
            if (MinionsTask.FillOf(b) <= MinionsTask.HurtFill)
                return true
        return !v.minions.Length && IsObject(v.orb) && MinionsTask.FillOf(v.orb) <= MinionsTask.HurtFill
    }

    ; The step's key: DodgeRun steps a side, then the other (n: steps so far).
    static DodgeKey(n) => Mod(n // MinionsTask.DodgeRun, 2) ? "d" : "a"

    ; a step's way off the bearing, in turn ms
    static DodgeOff(key) => key = "a" ? -MinionsTask.FullTurnMs // 4 : key = "d" ? MinionsTask.FullTurnMs // 4 : MinionsTask.FullTurnMs // 2

    ; a minion within Impale's reach (not above the player)
    static Close(v) {
        for b in v.minions
            if (MinionsTask.FullW(b) >= MinionsTask.BesideMinionW && !MinionsTask.Above(b))
                return true
        return false
    }

    ; a minion in Impale's reach: in reach (InReach's AimMinionW, not Above)
    ; and not behind the character (Behind: out of Q's line). Minions only:
    ; Q does 0 to the orb (hand clip 170608)
    static QReach(v) {
        for b in v.minions
            if (MinionsTask.FullW(b) >= MinionsTask.AimMinionW && !MinionsTask.Above(b) && !MinionsTask.Behind(b))
                return true
        return false
    }

    ; The award toast through grab (screen = its coords + ox, oy; real crops:
    ; tests\screens\minions_toast_*): it slides in behind the skill rows, so
    ; OCR rarely reads it, but the top of its title shows between two rows
    ; (ToastYs), always at one spot: its blue px (_ToastBlue) in one run
    ; (gaps up to ToastGap px) across ToastOrb -> "orb" ("Orb Awards"),
    ; ToastMinion -> "minion" ("Orb Minion Awards"), else "".
    static ToastYs := [1100, 1102, 1104, 1106, 1108]
    static ToastX1 := 2040
    static ToastX2 := 2540
    static ToastGap := 24
    static ToastTol := 10
    static ToastOrb := [2198, 2381]
    static ToastMinion := [2140, 2440]
    static Toast(grab, ox := 0, oy := 0) {
        ys := []
        for y in MinionsTask.ToastYs
            ys.Push(y - oy)
        rows := grab(MinionsTask.ToastX1 - ox, MinionsTask.ToastX2 - ox, ys, 2)
        a := 0, b := 0, s := 0, e := 0
        Loop rows[1].Length {
            j := A_Index, hit := false
            for row in rows
                hit := hit || MinionsTask._ToastBlue(row[j])
            if !hit
                continue
            x := MinionsTask.ToastX1 + (j - 1) * 2
            if (!s || x - e > MinionsTask.ToastGap) {
                if (e - s > b - a)
                    a := s, b := e
                s := x
            }
            e := x
        }
        if (e - s > b - a)
            a := s, b := e
        for what, span in Map("orb", MinionsTask.ToastOrb, "minion", MinionsTask.ToastMinion)
            if (Abs(a - span[1]) <= MinionsTask.ToastTol && Abs(b - span[2]) <= MinionsTask.ToastTol)
                return what
        return ""
    }

    static _ToastBlue(c) {
        r := (c >> 16) & 0xFF, g := (c >> 8) & 0xFF, b := c & 0xFF
        return b >= 80 && b - r >= 35 && g - r >= 15 && b >= g
    }

    ; Which bar of one scan is the orb: its index, 0 for none. The orb's bar
    ; is the widest, at least OrbRatio times the median of the others' (the
    ; upper one of an even count: a hurt minion's short bar made a full
    ; minion beside it "the orb", live 2026-11-03 84/100 beside 3/100); when
    ; it is no wider than that, the widest still counts if 2 bars sit below
    ; it on screen (nearer), or all of them and it is OrbHighRatio times
    ; theirs (wider though farther). A lone bar counts only if wider than
    ; OrbLonePx.
    static OrbIndex(bars) {
        if !bars.Length
            return 0
        wide := 1
        for i, b in bars
            if (MinionsTask.FullW(b) > MinionsTask.FullW(bars[wide]))
                wide := i
        ww := MinionsTask.FullW(bars[wide])
        if (bars.Length = 1)
            return ww > MinionsTask.OrbLonePx ? wide : 0
        ; a whole bar well above all others, near the widest: the orb, whatever
        ; the ratio (L58 13:02:31: orb 104-126 px, minions 122-134, y 500 / 620)
        top := 0
        for i, b in bars
            if (!top || b.y < bars[top].y)
                top := i
        high := MinionsTask.FillOf(bars[top]) >= 0.97 && MinionsTask.FullW(bars[top]) >= Max(100, 0.75 * ww)
        for i, b in bars
            if (i != top && b.y - bars[top].y < MinionsTask.OrbAboveY)
                high := false
        if high
            return top
        ws := []
        for i, b in bars
            if (i != wide)
                ws.Push(MinionsTask.FullW(b))
        med := MinionsTask._MedianHi(ws)
        if (ww >= MinionsTask.OrbRatio * med)
            return wide
        below := 0
        for b in bars
            if (b.y > bars[wide].y)
                below++
        return (below >= 2 || (below = bars.Length - 1 && ww >= MinionsTask.OrbHighRatio * med)) ? wide : 0
    }

    ; ---- the skill panel and Eden's points bar (real crops: tests\screens) --

    ; The skill panel through grab (as StripGrab.Rows; screen = its coords +
    ; ox, oy) -> Array, one per SkillTops: "" = no skill in that row, else
    ; {cd: 0 ready, else the overlay's width 0..1}. A row read neither way
    ; (a "Potion Auto Added" toast over it) reads ready.
    static Panel(grab, ox := 0, oy := 0) {
        ys := []
        for top in MinionsTask.SkillTops {
            ys.Push(top + 4 - oy)                ; above the name: the overlay's edge
            y := top + 10
            while (y <= top + 30)                ; the key letter
                ys.Push(y - oy), y += 2
        }
        rows := grab(MinionsTask.PanelX1 - ox, MinionsTask.PanelX2 - ox, ys, 2)
        per := ys.Length // MinionsTask.SkillTops.Length
        out := []
        Loop MinionsTask.SkillTops.Length {
            i := (A_Index - 1) * per + 1
            box := []
            Loop per - 1
                box.Push(rows[i + A_Index])
            out.Push(MinionsTask.KeyIn(box, MinionsTask.PanelX1, 2) ? {cd: MinionsTask.CdFrac(rows[i], MinionsTask.PanelX1, 2)} : "")
        }
        return out
    }

    ; A key box's rows (pixels from screen x x0, every stride-th) hold a
    ; letter: its right border lit in half of them or more, LetterMin..
    ; LetterMax of the inside (x 2026..2054) white. An empty row is the
    ; world behind (no border).
    static KeyIn(rows, x0, stride) {
        rb := (MinionsTask.KeyX2 - x0) // stride + 1
        lit := 0, white := 0, n := 0
        for row in rows {
            ; translucent: 9bb29b over grass, only 5c635e in the night clips
            if (MinionsTask._Low(row[rb]) >= 150 || MinionsTask._Low(row[rb - 1]) >= 150
                || MinionsTask._Low(row[rb]) - MinionsTask._Low(row[rb + 2]) >= MinionsTask.BorderStep)
                lit++
            x := 2026
            while (x <= 2054) {
                n++
                white += MinionsTask._Low(row[(x - x0) // stride + 1]) >= 220 ? 1 : 0
                x += stride
            }
        }
        return rows.Length && lit * 2 >= rows.Length && white >= MinionsTask.LetterMin * n && white <= MinionsTask.LetterMax * n
    }

    ; One row across the name box (pixels from screen x x0, every stride-th),
    ; above its text -> the cooldown overlay's width 0..1, 0 = none. The
    ; overlay is translucent (its colour follows the world behind): its left
    ; end at least CdStep brighter than the right end, one edge between, and
    ; most of each side on its side of the middle. An overlay over the whole
    ; row (a skill just pressed) is no edge: 0.
    static CdFrac(row, x0, stride) {
        L := []
        x := MinionsTask.NameX1 + 3              ; inside the left border
        while (x <= MinionsTask.PanelX2) {
            c := row[(x - x0) // stride + 1]
            L.Push((((c >> 16) & 0xFF) + ((c >> 8) & 0xFF) + (c & 0xFF)) // 3)
            x += stride
        }
        n := L.Length
        hi := [], lo := []
        Loop 8
            hi.Push(L[3 + A_Index]), lo.Push(L[n - 8 + A_Index])
        hi := MinionsTask._Median(hi), lo := MinionsTask._Median(lo)
        if (hi - lo < MinionsTask.CdStep)
            return 0
        mid := (hi + lo) / 2
        e := 0
        j := 4
        while (j <= n - 2) {
            if (L[j] < mid && L[j + 1] < mid && L[j + 2] < mid) {
                e := j
                break
            }
            j++
        }
        if !e
            return 0
        up := 0, down := 0
        Loop e - 4
            up += L[3 + A_Index] >= mid ? 1 : 0
        Loop n - e + 1
            down += L[e + A_Index - 1] < mid ? 1 : 0
        if (up < 0.85 * (e - 4) || down < 0.85 * (n - e + 1))
            return 0
        return Round((MinionsTask.NameX1 + 3 + (e - 1) * stride - MinionsTask.NameX1) / MinionsTask.NameW, 2)
    }

    ; Eden's points through grab (screen = its coords + ox, oy): per row the
    ; pure white across the centre (gaps up to 120 px bridged: the number on
    ; it, the frame's notch), the widest in a run of 6 rows or more (12 px:
    ; the fill, not the rank's thin line) / PxPerPoint. -> 0..100, -1 = no
    ; fill seen (not Eden's bar). No fill but the number's glyph alone at
    ; the centre (ZeroGlyph: "0", a white ring on black; loop L19
    ; 2026-11-03, most V presses logged no points: they were all at 0) -> 0.
    static Points(grab, ox := 0, oy := 0) {
        ys := []
        y := MinionsTask.BarY1
        while (y <= MinionsTask.BarY2)
            ys.Push(y - oy), y += 2
        best := 0, run := 0, wide := 0
        rows := grab(MinionsTask.BarX1 - ox, MinionsTask.BarX2 - ox, ys, 2)
        for row in rows {
            a := 0, b := 0, ext := 0
            for c in row {
                if (MinionsTask._Low(c) < 245)
                    continue
                x := MinionsTask.BarX1 + (A_Index - 1) * 2
                if (a && x - b > 120) {
                    if (a <= 1300 && b >= 1260)
                        break
                    a := 0
                }
                if !a
                    a := x
                b := x
            }
            if (a && a <= 1300 && b >= 1260)
                ext := b - a + 2
            if (ext >= 20)
                run++, wide := Max(wide, ext)
            else
                run := 0, wide := 0
            if (run >= 6)
                best := Max(best, wide)
        }
        if best
            return Min(100, Round(best / MinionsTask.PxPerPoint))
        return MinionsTask.ZeroGlyph(rows, MinionsTask.BarX1, 2) ? 0 : -1
    }

    ; The bar's "0" with no fill (live 2026-11-03: a white ring x 1273..1287,
    ; y 1161..1182 over the black glyph): in rows (x1, stride px apart, 2
    ; px apart) a run of ZeroRows rows whose white (Low >= 245) over x
    ; 1200..1360 is only in ZeroX1..ZeroX2, centred on CenterX within
    ; ZeroOff, with black inside its middle row (a ring, not a stroke).
    static ZeroX1 := 1262
    static ZeroX2 := 1298
    static ZeroOff := 8
    static ZeroRows := [6, 14]   ; 12..28 px
    static ZeroGlyph(rows, x1, stride) {
        run := []
        for row in rows {
            a := 0, b := 0, out := false
            for c in row {
                x := x1 + (A_Index - 1) * stride
                if (x < 1200 || x > 1360 || MinionsTask._Low(c) < 245)
                    continue
                if (x < MinionsTask.ZeroX1 || x > MinionsTask.ZeroX2)
                    out := true
                a := a ? a : x, b := x
            }
            if (a && !out && Abs((a + b) / 2 - MinionsTask.CenterX) <= MinionsTask.ZeroOff) {
                run.Push({row: row, a: a, b: b})
                continue
            }
            if MinionsTask._ZeroRun(run, x1, stride)
                return true
            run := []
        }
        return MinionsTask._ZeroRun(run, x1, stride)
    }

    static _ZeroRun(run, x1, stride) {
        if (run.Length < MinionsTask.ZeroRows[1] || run.Length > MinionsTask.ZeroRows[2])
            return false
        m := run[(run.Length + 1) // 2]
        x := m.a + stride
        while (x < m.b) {
            c := m.row[(x - x1) // stride + 1]
            if (Max((c >> 16) & 0xFF, (c >> 8) & 0xFF, c & 0xFF) < 100)
                return true
            x += stride
        }
        return false
    }

    ; Eden's combo rank letter through grab: the white rows over x 1250..1310
    ; only (the rank's line and the fill are wider), the longest run of
    ; them 14..48 rows -> "V" when its bottom quarter is at most half as
    ; wide as its top quarter (a V's point) and its top quarter is split
    ; in two at the centre (a V's arms; GUESSED: no V seen yet), "?" another
    ; letter, "" none.
    ; A letter only with the rank's time line under it (RankLineDy px below
    ; its last row: white through x 1280, RankLineMin wide or more, thin):
    ; clip L19 WINDY 022508, Eden's white ground swirl read "V" (Deadeye
    ; would go) and the bar's "0" a letter. Real frames: E, D, C read "?".
    ; Loop L19 2026-11-03: Deadeye went twice at ranks under V ("You need V
    ; Combo Rank", SNOWY 035319 at a D, WINDY 03:07:42 at a C): the camera
    ; close, the character's white hair streaks over the letter's place
    ; (full-res clip 030751: diagonal strokes x 1284..1304, narrowing down)
    ; and the fill bobbing low (its top RankLineDy under them, read as the
    ; time line, its tall rows past RankY2 unseen). So a letter is also
    ; (_Glyph): centred (its box within RankCentreTol of CenterX, RankBoxW
    ; wide), outlined (the game draws every rank letter white with a black
    ; edge: dark within RankEdgePx beside RankEdgeShare of its rows; hair
    ; and snow are not), and its time line is thin (a row without it within
    ; RankLineMax under it, not past the grab: the fill is taller).
    static RankLineX1 := 1130
    static RankLineX2 := 1430
    static RankLineDy := [3, 20]
    static RankLineMin := 20
    static RankLineMax := 10
    static RankCentreTol := 8
    static RankBoxW := [16, 44]
    static RankEdgePx := 4
    static RankEdgeShare := 0.7
    static Rank(grab, ox := 0, oy := 0) {
        ys := []
        y := MinionsTask.RankY1
        while (y <= MinionsTask.RankY2)
            ys.Push(y - oy), y++
        rows := grab(MinionsTask.RankLineX1 - ox, MinionsTask.RankLineX2 - ox, ys, 1)
        i0 := MinionsTask.RankX1 - MinionsTask.RankLineX1
        cur := [], first := 0
        for i, row in rows {
            a := 0, b := 0
            Loop MinionsTask.RankX2 - MinionsTask.RankX1 + 1
                if (MinionsTask._Low(row[i0 + A_Index]) >= 200)
                    b := MinionsTask.RankX1 + A_Index - 1, a := a ? a : b
            if !(a > 1250 && b < 1310)
                s := MinionsTask._RankLit(row), a := s.a, b := s.b
            ; through the letter's middle (a hair streak at x 1251..1255 over
            ; a V's top rows, clip 20261108: one run of 46 rows, no letter)
            if (a > 1250 && b < 1310 && a <= MinionsTask.CenterX + MinionsTask.RankMidTol && b >= MinionsTask.CenterX - MinionsTask.RankMidTol) {
                first := cur.Length ? first : i
                cur.Push({a: a, b: b, row: row})
                continue
            }
            if ((r := MinionsTask._RankLetter(cur, rows, first + cur.Length - 1)) != "")
                return r
            cur := []
        }
        return MinionsTask._RankLetter(cur, rows, first + cur.Length - 1)
    }

    ; a row with white past x 1250 / 1310 (clip 20261108 123642, a V by day:
    ; the snow behind the letter as white as its outline, its top rows lost,
    ; the rest too narrow for a V, "?"): the white between the first dark
    ; from x 1250 and from x 1310 (the letter's black edge; a speck of snow
    ; beyond it is not the letter) -> {a, b} when it has dark beside both
    ; ends, else {a: 0, b: 0}
    static RankMidTol := 14
    static _RankLit(row) {
        static none := {a: 0, b: 0}
        lo := 1250, hi := 1310
        while (lo < hi && !MinionsTask._Dark(row[lo - MinionsTask.RankLineX1 + 1]))
            lo++
        while (hi > lo && !MinionsTask._Dark(row[hi - MinionsTask.RankLineX1 + 1]))
            hi--
        a := 0, b := 0, x := lo
        while (++x < hi)
            if (MinionsTask._Low(row[x - MinionsTask.RankLineX1 + 1]) >= 200)
                b := x, a := a ? a : x
        if (!a || !MinionsTask._DarkNear(row, a, -1) || !MinionsTask._DarkNear(row, b, 1))
            return none
        return {a: a, b: b}
    }

    ; run ({a, b, row} per row: its white's ends, the row from RankLineX1) a
    ; letter, last its last row in rows: "V" / "?" when it is a glyph
    ; (_Glyph) with the thin time line under it, else ""
    static _RankLetter(run, rows, last) {
        n := run.Length
        if (n < 14 || n > 48 || !MinionsTask._Glyph(run))   ; an E by day 45 rows (its top in the snow, now read)
            return ""
        line := 0
        Loop MinionsTask.RankLineDy[2] - MinionsTask.RankLineDy[1] + 1 {
            j := last + MinionsTask.RankLineDy[1] + A_Index - 1
            if (j <= rows.Length && MinionsTask._RankLine(rows[j])) {
                line := j
                break
            }
        }
        if !line
            return ""
        thin := false                            ; a row without it soon under it (the fill: tall)
        Loop MinionsTask.RankLineMax {
            j := line + A_Index
            if (j > rows.Length)
                break
            if !MinionsTask._RankLine(rows[j]) {
                thin := true
                break
            }
        }
        if !thin
            return ""
        ; a real V (clip 170608 t=38..53, hollow, ~40 px on top, 15 at its
        ; flat foot, ~3 px left of CenterX): its arms apart about its own
        ; middle, its last rows narrow (an E cut off by the grab: a stem on
        ; top and a wide foot)
        ; by day the V's outer edge can melt into the snow on its first rows
        ; (only its inner strokes left): its width from its top half
        q := Max(1, n // 4), f := Max(1, n // 10), top := 0, bot := 0, split := 0, a := 9999, b := 0
        for r in run
            a := Min(a, r.a), b := Max(b, r.b)
        Loop n // 2
            top := Max(top, run[A_Index].b - run[A_Index].a + 1)
        Loop q
            split += MinionsTask._Split(run[A_Index].row, (a + b) // 2) ? 1 : 0
        Loop f
            bot := Max(bot, run[n - f + A_Index].b - run[n - f + A_Index].a + 1)
        return (bot * 2 <= top && split * 2 >= q) ? "V" : "?"
    }

    ; the run's rows look like a rank letter: centred, as wide as one,
    ; outlined in black
    static _Glyph(run) {
        a := 9999, b := 0, edged := 0
        for r in run {
            a := Min(a, r.a), b := Max(b, r.b)
            edged += (MinionsTask._DarkNear(r.row, r.a, -1) && MinionsTask._DarkNear(r.row, r.b, 1)) ? 1 : 0
        }
        w := b - a + 1
        return Abs((a + b) / 2 - MinionsTask.CenterX) <= MinionsTask.RankCentreTol
            && w >= MinionsTask.RankBoxW[1] && w <= MinionsTask.RankBoxW[2]
            && edged >= MinionsTask.RankEdgeShare * run.Length
    }

    static _Dark(c) => Max((c >> 16) & 0xFF, (c >> 8) & 0xFF, c & 0xFF) <= 90

    ; row (x RankLineX1..) dark (no channel over 90) within RankEdgePx of
    ; screen x, on side dir (-1 left, 1 right)
    static _DarkNear(row, x, dir) {
        Loop MinionsTask.RankEdgePx {
            i := x + dir * A_Index - MinionsTask.RankLineX1 + 1
            if (i < 1 || i > row.Length)
                return false
            c := row[i]
            if (Max((c >> 16) & 0xFF, (c >> 8) & 0xFF, c & 0xFF) <= 90)
                return true
        }
        return false
    }

    ; row (x RankLineX1..) not white at the letter's middle (cx +- 2): a V's
    ; arms apart
    static _Split(row, cx) {
        Loop 5 {
            i := cx - 3 + A_Index - MinionsTask.RankLineX1 + 1
            if (MinionsTask._Low(row[i]) >= 200)
                return false
        }
        return true
    }
    ; row (x RankLineX1.., 1 px apart): white through the centre, gaps of 2
    ; px bridged, at least RankLineMin wide
    static _RankLine(row) {
        c0 := MinionsTask.CenterX - MinionsTask.RankLineX1 + 1
        w := 0
        for dir in [-1, 1] {
            i := dir < 0 ? c0 : c0 + 1, gap := 0
            while (i >= 1 && i <= row.Length) {
                if (MinionsTask._Low(row[i]) >= 200)
                    w += (gap + 1), gap := 0
                else if (++gap > 2)
                    break
                i += dir
            }
        }
        return w >= MinionsTask.RankLineMin
    }

    static _Join(a) {
        s := ""
        for v in a
            s .= (A_Index > 1 ? " " : "") v
        return s
    }

    static _Low(c) =>Min((c >> 16) & 0xFF, (c >> 8) & 0xFF, c & 0xFF)

    ; px the screen moves for a camera turn (Left moves things right).
    static Shift(key, ms) => (key = "Left" ? 1 : key = "Right" ? -1 : 0) * Round(ms * MinionsTask.TurnPxPerMs)

    ; A turn of d ms (Right +) as the short way round: whole circles
    ; (FullTurnMs) dropped -> -C/2 < d <= C/2.
    static Wrap(d) {
        c := MinionsTask.FullTurnMs
        d := Mod(d, c)
        return (d > c / 2) ? d - c : (d <= -c / 2) ? d + c : d
    }

    ; The bar in bars nearest to where o was (moved shift px by a turn), ""
    ; when none is within MatchX / MatchY.
    static Match(bars, o, shift := 0) {
        best := "", bd := 0
        for b in bars {
            dx := Abs(b.x - o.x - shift), dy := Abs(b.y - o.y)
            if (dx > MinionsTask.MatchX || dy > MinionsTask.MatchY)
                continue
            if (!IsObject(best) || dx + dy < bd)
                best := b, bd := dx + dy
        }
        return best
    }

    ; The bars that were in the scan before too (prev, moved shift px by a
    ; turn since): one scan alone is no bar.
    static Confirmed(bars, prev, shift := 0) {
        out := []
        for b in bars
            if IsObject(MinionsTask.Match(prev, {x: b.x - shift, y: b.y}))
                out.Push(b)
        return out
    }

    ; -> {bars: bars but the one matching o, match: that one or ""}.
    static Without(bars, o, shift := 0) {
        m := MinionsTask.Match(bars, o, shift)
        rest := []
        for b in bars
            if (b !== m)
                rest.Push(b)
        return {bars: rest, match: m}
    }

    ; bars without the boss bar UI (BossBar's: BossBarMin wide or more,
    ; inside BossArea): never a target.
    static NotBossUi(bars) {
        out := []
        for b in bars
            if !(b.w >= MinionsTask.BossBarMin && b.y <= MinionsTask.BossArea.y2
                && b.x >= MinionsTask.BossArea.x1 && b.x <= MinionsTask.BossArea.x2)
                out.Push(b)
        return out
    }

    ; The boss bar UI through grab (as StripGrab.Rows; GUESSED, not seen:
    ; a big boss bar across the top centre): in BossArea (rows 2 px apart,
    ; every 2nd px) a run of warm pixels (_Hot), gaps up to BossGap bridged
    ; (its HP text), at least BossBarMin px, RunCover of it warm, warm under
    ; BelowCover of it 2 px lower, and not warm (EdgeCover) BossThick px
    ; lower (a sunset or lava is no bar). -> {x, y, w} or "".
    static BossBar(grab) {
        a := MinionsTask.BossArea, st := 2
        ys := [], y := a.y1
        while (y <= a.y2)
            ys.Push(y), y += 2
        rows := grab(a.x1, a.x2, ys, st)
        gap := MinionsTask.BossGap // st, thick := MinionsTask.BossThick // 2
        Loop rows.Length - thick {               ; a bar's lower rows checked: the top of the area
            i := A_Index, row := rows[i], j := 1
            while (j <= row.Length) {
                if !MinionsTask._Hot(row[j]) {
                    j++
                    continue
                }
                s := j, e := j, hit := 0
                while (j <= row.Length && j - e <= gap) {
                    if MinionsTask._Hot(row[j])
                        e := j, hit++
                    j++
                }
                j := e + 1
                n := e - s + 1
                if (n * st < MinionsTask.BossBarMin || hit < MinionsTask.RunCover * n)
                    continue
                if (MinionsTask._HotShare(rows[i + 1], s, e) < MinionsTask.BelowCover)
                    continue
                if (MinionsTask._HotShare(rows[i + thick], s, e) > MinionsTask.EdgeCover)
                    continue
                return {x: a.x1 + (s + e - 2) * st // 2, y: ys[i], w: n * st}
            }
        }
        return ""
    }

    ; A boss bar pixel: yellow, orange or red.
    static _Hot(c) {
        r := (c >> 16) & 0xFF, g := (c >> 8) & 0xFF, b := c & 0xFF
        return MinionsTask.IsYellow(c) || MinionsTask.IsOrange(c) || (r >= 180 && r - g >= 90 && r - b >= 90)
    }

    static _HotShare(row, s, e) {
        hit := 0
        Loop e - s + 1
            hit += MinionsTask._Hot(row[s + A_Index - 1]) ? 1 : 0
        return hit / (e - s + 1)
    }

    ; A death seen on screen (clips L19 2026-11-03 SNOWY 042511, RAINY
    ; 041829: HP falling to red, then ~0.5 s of a black screen and ~0.5 s of
    ; Eden's dark red respawn screen, only the points bar on it, the skill
    ; panel gone; then the player at spawn): a grid (DeathGrid, the points
    ; bar's box DeathSkip left out) DeathShare or more dark (green and blue
    ; DeathDark or less, red DeathRed or less) and no skill panel row.
    ; Real frames: tests\screens\death_*; never over a V / F cutscene,
    ; night, HELL, the respawn prompt.
    static DeathGrid := {x1: 40, x2: 2520, y1: 60, y2: 1380, dx: 40, dy: 120}
    static DeathSkip := {x1: 880, x2: 1680, y1: 1040, y2: 1250}
    static DeathDark := 40
    static DeathRed := 200
    static DeathShare := 0.98    ; real: 1.00 (black, red); HELL 0.87..0.93, GRAVEYARD night + prompt 0.94
    static DeathScreen(grab, ox := 0, oy := 0) {
        g := MinionsTask.DeathGrid, sk := MinionsTask.DeathSkip
        ys := []
        y := g.y1
        while (y <= g.y2)
            ys.Push(y - oy), y += g.dy
        n := 0, dark := 0
        for i, row in grab(g.x1 - ox, g.x2 - ox, ys, g.dx) {
            y := ys[i] + oy
            for j, c in row {
                x := g.x1 + (j - 1) * g.dx
                if (x >= sk.x1 && x <= sk.x2 && y >= sk.y1 && y <= sk.y2)
                    continue
                n++
                r := (c >> 16) & 0xFF, gr := (c >> 8) & 0xFF, b := c & 0xFF
                dark += (Max(gr, b) <= MinionsTask.DeathDark && r <= MinionsTask.DeathRed) ? 1 : 0
            }
        }
        if (!n || dark < MinionsTask.DeathShare * n)
            return false
        for r in MinionsTask.Panel(grab, ox, oy)
            if IsObject(r)
                return false
        return true
    }

    ; A respawn told by the player's HP (log: its reads, oldest first,
    ; {at, hp}, hp -1 = no bar: full HP or not read): a read at DeathLowHp
    ; or under, within DeathHpMs, then only reads DeathHpJump higher or none
    ; (-1): the last one DeathHpJump higher (SNOWY 042511: 41% -> 80% at
    ; spawn), or none for DeathFullMs and two reads (RAINY 041829: ~20% ->
    ; full at spawn, the bar hidden). HP comes back ~1% a second: no heal.
    ; -> "" or the evidence ("hp 41% -> 80%").
    static DeathSettleMs := 1500 ; after a death seen, no log to read: the respawn screens over before the re-aim clicks
    static DeathLineMs := 3000   ; the death screen seen: the respawn's log lines looked for this long
    static DeathAfterLineMs := 300 ; from those lines to the re-aim's first click (as Input.ResetQuick's afterLine)
    static DeathScreenSeen := "the death screen"
    static SpawnKeepMs := 600000 ; a closing respawn holds for the next hunt this long (GUESSED: only a player's own moves age it)
    static PrepAfterMs := 480000 ; a closing respawn this old is made again in NORMAL, before SpawnKeepMs (L51 22:45: a NORMAL of 899 s)
    static DeathLowHp := 0.45
    ; _Regen: the HP to go back to a fight at (GUESSED: 4 dart hits of -15;
    ; 25-37% held 5-25 s in L66), regen ~1.5% a second (the Eden hand clip),
    ; the longest wait (a biome lasts ~110 s), a read every RegenLookMs, a
    ; fight this near spawn: no wait (GUESSED; L66 walks back were 4.5-19 s)
    static ReturnHp := 0.6
    static RegenPerMs := 0.000015
    static RegenMaxMs := 25000
    static RegenLookMs := 500
    static RegenFarMs := 2500
    static DeathHpJump := 0.3
    static DeathHpMs := 10000
    static DeathFullMs := 1000
    static Respawned(log) {
        n := log.Length, L := 0
        Loop n - 1 {
            e := log[A_Index]
            if (e.hp >= 0 && e.hp <= MinionsTask.DeathLowHp)
                L := A_Index
        }
        if (!L || log[n].at - log[L].at > MinionsTask.DeathHpMs)
            return ""
        lo := log[L].hp, hi := lo + MinionsTask.DeathHpJump
        Loop n - L {
            h := log[L + A_Index].hp
            if (h >= 0 && h < hi)
                return ""
        }
        if (log[n].hp >= hi)
            return "hp " Round(lo * 100) "% -> " Round(log[n].hp * 100) "%"
        if (n - L >= 2 && log[n].at - log[L + 1].at >= MinionsTask.DeathFullMs)
            return "hp " Round(lo * 100) "% -> full"
        return ""
    }

    ; Any read in log (as Respawned, DeathHpMs of them) at DeathLowHp or under:
    ; a death with the player hurt, no fall (Fell). Not 0.3: L46 15:11:03,
    ; HP 39% by the end, a live fight on an open orb, bars 13 s old.
    static WasHurt(log) {
        for e in log
            if (e.hp >= 0 && e.hp <= MinionsTask.DeathLowHp)
                return true
        return false
    }

    ; Hit hard now (see BackDrop): in log (as Respawned), the reads of the
    ; last BackDropMs and since (ms), a lone -1 (not read) left out, two in a
    ; row full (1.0: the first drop from full HP counts), the last one a bar:
    ; it BackDrop under the highest of them, or BackLowDrop at BackHp or
    ; under -> {hp, top, ms} or "".
    static HitHard(log, now, since := 0) {
        n := log.Length
        if (!n || log[n].hp < 0)
            return ""
        hp := log[n].hp, top := -1, at := 0
        for i, e in log {
            r := (e.hp < 0 && ((i > 1 && log[i - 1].hp < 0) || log[i + 1].hp < 0)) ? 1.0 : e.hp
            if (e.at >= Max(since, now - MinionsTask.BackDropMs) && r > top)
                top := r, at := e.at
        }
        d := top - hp
        if (d >= MinionsTask.BackDrop - 0.001 || (hp <= MinionsTask.BackHp && d >= MinionsTask.BackLowDrop - 0.001))
            return {hp: hp, top: top, ms: log[n].at - at}
        return ""
    }

    ; The player's HP read last (log as Respawned) if within HpFreshMs of
    ; now, else -1.
    static HpFreshMs := 3000
    static LastHp(log, now) {
        i := log.Length
        while (i >= 1) {
            e := log[i--]
            if (now - e.at > MinionsTask.HpFreshMs)
                break
            if (e.hp >= 0)
                return e.hp
        }
        return -1
    }

    ; Falls off the island (loop L19 2026-11-03 NORMAL at night: died
    ; (the death screen) 07:01:30, 07:09:26, 07:12:24, 07:13:04, each a few
    ; seconds into a walk by bearing -4329..-4429 ms from the respawn, no
    ; bar in sight; RAINY 07:17:18 right after two "island's edge ahead".
    ; Night frames read 0.65..0.85 dark (DeathScreen needs 0.98 and no
    ; skill panel): real deaths, the edge guard knows only the day sea, and
    ; the night void is as dark as the night grass and stone round spawn
    ; (no colour tells it). A death with no bar seen for FallQuietMs and
    ; the HP never low (hurt) = a fall: the spot (_pos, dead reckoning in
    ; walked ms) and the way (bearing) kept FallKeepMs; a walk that way
    ; (within FallCos of it) that would get within FallMarginMs of that
    ; spot along it = the edge (FallAhead).
    static FallQuietMs := 10000
    static FallMarginMs := 2100  ; 3 walks short of where the fall began
    static FallKeepMs := 10800000 ; L69 2026-11-08: 4 falls at bearing -1875, ~5.2 s out, 11-26 min apart: 10 min forgot each
    static FallQuietTurnMs := 20000
    static FallGuardMs := 4000   ; a fall this soon after _EdgeGuard fired went the way it fired at (_FallWay)
    static EdgeQuietMs := 3000
    static FallCos := 0.5        ; within 60 degrees of the way it fell
    static FallBehindMs := 700   ; a fall behind spawn along its way by more: kept out from spawn (FallOut)
    static Fell(barAt, now, hurt) => !hurt && (barAt = "" || now - barAt >= MinionsTask.FallQuietMs)

    ; the unit step for bearing b (ms, Right +; FullTurnMs a circle): x right,
    ; y ahead of the respawn way
    static Way(b) {
        a := 2 * 3.141592653589793 * b / MinionsTask.FullTurnMs
        return {x: Sin(a), y: Cos(a)}
    }

    ; ms walked out along bearing b to pos (rounded)
    static Along(pos, b) {
        u := MinionsTask.Way(b)
        return Round(pos.x * u.x + pos.y * u.y)
    }

    ; The way a fall went (w {x, y, b}: _FallWay) as an edge out from spawn.
    ; Spawn stands on the island, so a fall never lies behind it along its
    ; own way. Seen late (the respawn's line comes seconds on, the hunt walks
    ; and turns meanwhile: a new leg home, a guard's half turn), the bearing
    ; then can face back to spawn: kept so, FallAhead held every walk home
    ; from anywhere out there and turned the player round to the cliff (L72
    ; SAND STORM 04:31-04:42: 9 of 11 falls -1858..-9253 ms out, 15 of 17
    ; "fell off this way before" turns at those ways, 4 deaths 2-4 s after
    ; one; all logs: 27 of 51 falls). Out along its way, or behind spawn by
    ; FallBehindMs at most (dead reckoning's slack): w; else the way from
    ; spawn to the spot (PosBearing), faced: the bearing it had.
    static FallOut(w) {
        if (MinionsTask.Along(w, w.b) >= -MinionsTask.FallBehindMs)
            return w
        return {x: w.x, y: w.y, b: MinionsTask.PosBearing(w), faced: w.b}
    }

    ; A walk of ms at bearing from pos would come within FallMarginMs of a
    ; fall in falls ({x, y, b, at}) along its way, kept FallKeepMs
    static FallAhead(falls, pos, bearing, ms, now) {
        v := MinionsTask.Way(bearing)
        for f in falls {
            if (now - f.at >= MinionsTask.FallKeepMs)
                continue
            u := MinionsTask.Way(f.b)
            c := u.x * v.x + u.y * v.y
            if (c < MinionsTask.FallCos)
                continue
            if (pos.x * u.x + pos.y * u.y + ms * c >= f.x * u.x + f.y * u.y - MinionsTask.FallMarginMs)
                return true
        }
        return false
    }

    ; -> {key, ms} to aim a glow at x: GlowAimDx px to its side of the
    ; centre (centred it hides behind the character); ms 0 = aimed (within
    ; GlowAimDx + GlowAimTol of the centre).
    static GlowTurn(x) {
        dx := x - MinionsTask.CenterX
        aim := MinionsTask.GlowAim(dx < 0 ? -1 : 1)
        if (Abs(dx) <= aim + MinionsTask.GlowAimTol)
            return {key: "", ms: 0}
        ms := Round((Abs(dx) - aim) / MinionsTask.TurnPxPerMs)
        ms := Max(MinionsTask.TurnMinMs, Min(MinionsTask.TurnMaxMs, ms))
        return {key: dx < 0 ? "Left" : "Right", ms: ms}
    }

    ; px off the centre a glow is aimed on side (-1 left, 1 right): GlowClear
    ; outside OrbBeacon's boxes over the character (PlayerWhite, Player)
    static GlowAim(side) {
        pw := OrbBeacon.PlayerWhite, pl := OrbBeacon.Player
        edge := side < 0 ? MinionsTask.CenterX - Min(pw.x1, pl.x1) : Max(pw.x2, pl.x2) - MinionsTask.CenterX
        return Max(MinionsTask.GlowAimDx, edge + MinionsTask.GlowClear)
    }

    ; -> {key, ms}: a glow lost at x right after a turn to it (hidden by the
    ; character: the turn went too far) turned GlowClear px further out
    static GlowLost(x) {
        ms := Max(MinionsTask.TurnMinMs, Round(MinionsTask.GlowClear / MinionsTask.TurnPxPerMs))
        return {key: x >= MinionsTask.CenterX ? "Left" : "Right", ms: ms}
    }

    ; -> {key: "Left" | "Right", ms} to face x within tol (ms 0 = aimed).
    static TurnFor(x, tol := "", rate := "", center := "") {
        dx := x - (center = "" ? MinionsTask.CenterX : center)
        if (Abs(dx) <= (tol = "" ? MinionsTask.AimTol : tol))
            return {key: "", ms: 0}
        px := Abs(dx), short := (rate = "") ? 0 : Min(px, MinionsTask.ShortTurnPx)
        ms := Round(short / (rate = "" ? 1 : rate) + (px - short) / MinionsTask.TurnPxPerMs)
        ms := Max(MinionsTask.TurnMinMs, Min(MinionsTask.TurnMaxMs, ms))
        return {key: dx < 0 ? "Left" : "Right", ms: ms}
    }
}

; ---------------------------------------------------------------------------
; MinionSkills: which skill key to press next in one hunt (pure: the HUD
; reads and the clock come in, a key goes out; tested with fakes).
;
;   b := MinionSkills(aura, rows, learnt := "")
;     rows   MinionsTask.Panel() at the hunt's start ("" / no row = the
;            panel unknown)
;     learnt Map aura -> Map key -> row, rows learnt in earlier hunts (kept
;            up to date by the book)
;   b.Next(hud, now, close := false) -> the key to press, "" = none now
;     hud {rows (Panel), points (Points, -1 unknown), rank (Rank), air} or ""
;     close: a minion in Impale's reach (QReach; Eden: Impale only then)
;   b.Pressed(k, hud, now)
;   b.CastMs(k), b.Casting(now), b.Rooted(now) (no movement: Deadeye's windup)
;   b.keys, b.rowOf (key -> row index), b.how ("panel" / "learn" / "keys")
;
; One cast at a time: a cooldown overlay starts when the cast ENDS, so after
; a press nothing goes until CastMs is out, and an empty row during a
; channel is not "ready". A pressed key waits its cast plus its cooldown,
; made exact by its overlay once read (cd x cooldown left); a press that
; showed nothing (no overlay, no points moved) ConfirmMs after its cast
; failed: free again after RetryMs. A row whose overlay reads is never ready.
;
; MinionsTask.Auras (panel top to bottom, the last row at the bottom, order
; to cast in, cooldowns, casts): Eden, Equinox, Luminosity. Eden goes by
; rule: R at rank V; E, then F (FirstOfFE); Q with a minion in reach (close);
; T; V at Charge 30 or more, unless held back (no: the orb still Locked).
; Others:
; the first ready in their order. Unknown aura: every letter (Keys) in
; turn, one at a time, the row whose cooldown starts after it is that key's
; (learnt); a key that started none twice is dropped.
; ---------------------------------------------------------------------------

class MinionSkills {
    static GenericCastMs := 3000     ; an unknown skill's cast
    static LearnMs := 8000           ; ... and its cooldown looked for this long (it starts at the cast's end)
    static UnknownHoldMs := 4000     ; an unknown cooldown: no overlay seen yet, not again this long after the cast
    static ConfirmMs := 1500         ; after the cast, or a tenth of the cooldown (a full row has no edge to read)
    static RetryMs := 2000           ; a press that failed: again after this
    static PointsKeepMs := 5000      ; the Charge read last, through a flash
    static EWaitMs := 1500           ; Eden: F ready, E back within this: F waits for E (at most this long)

    __New(aura, rows, learnt := "") {
        a := StrLower(Trim(String(aura)))
        this.aura := a
        this.eden := (a = "eden")
        this.spec := MinionsTask.Auras.Has(a) ? MinionsTask.Auras[a] : ""
        this.rowOf := Map()
        this.keys := MinionsTask.KeysFor(a)
        this.how := "keys"
        this._i := 0
        this._castUntil := 0
        this._rootUntil := 0
        this._pts := -1, this._ptsAt := 0
        this._fWait := ""            ; Eden: since when a ready F waits for E ("" = not)
        this._state := Map()         ; key -> {at, est, seen, pts, cds} since its press
        this._miss := Map()          ; key -> presses that started no cooldown (learning)
        this._dead := Map()
        this._learnt := (learnt is Map) ? learnt : Map()
        slots := []
        if IsObject(rows)
            for i, r in rows
                if IsObject(r)
                    slots.Push(i)
        this._slots := slots
        ; known auras: always their layout, read or not (loop L19 05:32: a
        ; toast over three rows sent Eden to learning every letter); the
        ; panel fills the rows from the bottom (clips 2026-11-03)
        if IsObject(this.spec) {
            n := this.spec.panel.Length, top := MinionsTask.SkillTops.Length - n
            for j, k in this.spec.panel
                this.rowOf[k] := top + j
            this.how := "panel"
            return
        }
        if !slots.Length
            return
        this.how := "learn"
        if this._learnt.Has(a)
            for k, i in this._learnt[a]
                if IsObject(rows[i])
                    this.rowOf[k] := i
        this._learnt[a] := this.rowOf
        this._Narrow()
    }

    ; no: a key not to pick now (the board's prompt: E)
    Next(hud, now, close := false, no := "") {
        this._See(hud, now)
        if this.Casting(now)
            return ""
        if this.eden {
            pts := this._Points(hud, now)
            if (IsObject(hud) && hud.HasOwnProp("rank") && hud.rank = "V" && this._Ready("r", hud, now))
                return "r"
            ; F and E first: V at first contact threw the player off the target (L23 18:05:18, 18:09:50)
            if ((k := this._FirstOfFE(hud, now, no)) != "")
                return k
            ; the rank lapses 3.5-4 s after the last hit (L71-L77: a cast <= 3 s
            ; after a ranked one kept it 89 of 122, >= 5 s 10 of 107; 73 of 140
            ; lapses stood beside it with nothing ready): F and E both cooling,
            ; Impale (1 s cast, 3 s cooldown) fills the gap, before T (no hit).
            ; Minions only (close: QReach), it does 0 to the orb
            if (close && !InStr(no, "q") && this._Ready("q", hud, now))
                return "q"
            ; T straight before V: by hand F, E, T, V, rank V 3.5 s on; the rank
            ; lapses 3.5-4 s after the last hit, so V comes on a live chain
            if (!InStr(no, "t") && (pts < 100 || !InStr(no, "v")) && this._Ready("t", hud, now))
                return "t"
            if (!InStr(no, "v") && pts >= this._Cost("v") && !(IsObject(hud) && hud.HasOwnProp("air") && hud.air) && this._Ready("v", hud, now))
                return "v"
            return ""
        }
        if IsObject(this.spec) {
            for k in this.keys
                if (!InStr(no, k) && this._Ready(k, hud, now))
                    return k
            return ""
        }
        Loop this.keys.Length {
            i := Mod(this._i + A_Index - 1, this.keys.Length)
            if (!InStr(no, this.keys[i + 1]) && this._Ready(this.keys[i + 1], hud, now)) {
                this._i := i + 1
                return this.keys[i + 1]
            }
        }
        return ""
    }

    Pressed(k, hud, now) {
        cds := []
        for r in this._Rows(hud)
            cds.Push(IsObject(r) ? r.cd : 0)
        cast := this.CastMs(k)
        if (k = "f" || k = "e")
            this._fWait := ""
        this._castUntil := now + cast
        if this.Roots(k)
            this._rootUntil := now + cast
        this._state[k] := {at: now, est: now + cast + this._CoolMs(k), seen: false, cds: cds
            , pts: this._Points(hud, now)}
    }

    CastMs(k) => (IsObject(this.spec) && this.spec.cast.Has(k)) ? this.spec.cast[k] : MinionSkills.GenericCastMs
    Casting(now) => now < this._castUntil
    Rooted(now) => now < this._rootUntil
    Roots(k) => this.eden && k = "r"

    _Cost(k) => (MinionsTask.Costs.Has(this.aura) && MinionsTask.Costs[this.aura].Has(k)) ? MinionsTask.Costs[this.aura][k] : 0
    _CoolMs(k) => (IsObject(this.spec) && this.spec.cool.Has(k)) ? this.spec.cool[k] : 0
    _Rows(hud) => (IsObject(hud) && IsObject(hud.rows)) ? hud.rows : []

    ; k's row as read now, "" = none (unknown key, a row unread)
    _Row(k, hud) {
        rows := this._Rows(hud)
        if (this.rowOf.Has(k) && this.rowOf[k] <= rows.Length && IsObject(rows[this.rowOf[k]]))
            return rows[this.rowOf[k]]
        return ""
    }

    ; the Charge now: the read, else the last one within PointsKeepMs, else -1
    _Points(hud, now) {
        if (IsObject(hud) && hud.HasOwnProp("points") && hud.points >= 0) {
            this._pts := hud.points, this._ptsAt := now
            return hud.points
        }
        return (this._pts >= 0 && now - this._ptsAt < MinionSkills.PointsKeepMs) ? this._pts : -1
    }

    ; Eden's F or E to press now, "" = neither. Staggered so their cooldowns
    ; do not run out together with nothing between (E 1 s cast + 6 s, F 2.8 s
    ; + 10 s): both ready -> E, then F, whose channel covers most of E's
    ; cooldown (the last hit to E's return 3.2 s; F, then E: 6 s). F ready, E
    ; back within EWaitMs -> F waits for it, at most EWaitMs (Q or T may go
    ; meanwhile): F now would leave both down for ~6 s after E
    _FirstOfFE(hud, now, no) {
        eOk := !InStr(no, "e"), fOk := !InStr(no, "f")
        if (eOk && this._Ready("e", hud, now))
            return "e"
        if !(fOk && this._Ready("f", hud, now)) {
            this._fWait := ""
            return ""
        }
        if (!eOk || this._LeftMs("e", hud, now) > MinionSkills.EWaitMs) {
            this._fWait := ""
            return "f"
        }
        if (this._fWait = "")
            this._fWait := now
        return (now - this._fWait < MinionSkills.EWaitMs) ? "" : "f"
    }

    ; ms till k's cooldown is over: 0 ready, a large number unknown / never
    _LeftMs(k, hud, now) {
        if this._Ready(k, hud, now)
            return 0
        c := this._CoolMs(k), row := this._Row(k, hud)
        if (this._dead.Has(k) || !c)
            return 99999999
        if (IsObject(row) && row.cd > 0)
            return Round(row.cd * c)
        return this._state.Has(k) ? Max(0, this._state[k].est - now) : 99999999
    }

    ; k's cooldown is over (the cast aside)
    _Ready(k, hud, now) {
        if this._dead.Has(k)
            return false
        row := this._Row(k, hud)
        if (IsObject(row) && row.cd > 0)
            return false
        if this._state.Has(k) {
            st := this._state[k]
            if this._CoolMs(k)
                return now >= st.est
            return st.seen || now >= st.at + this.CastMs(k) + MinionSkills.UnknownHoldMs
        }
        ; one unknown key at a time: its row must be told apart
        if (this.how = "learn" && !this.rowOf.Has(k))
            for pk, p in this._state
                if (!this.rowOf.Has(pk) && now - p.at < MinionSkills.LearnMs)
                    return false
        return true
    }

    ; what the presses did: an overlay read (its time left; learning: whose
    ; row), the points moved, or nothing by ConfirmMs after the cast
    _See(hud, now) {
        rows := this._Rows(hud)
        for k, st in this._state {
            row := this._Row(k, hud)
            if (IsObject(row) && row.cd > 0) {
                st.seen := true
                if this._CoolMs(k)
                    st.est := now + Round(row.cd * this._CoolMs(k))
            } else if (!this.rowOf.Has(k) && this.how = "learn") {
                for i in this._slots
                    if (!this._Taken(i) && i <= rows.Length && IsObject(rows[i]) && rows[i].cd > 0 && st.cds.Length >= i && st.cds[i] = 0) {
                        this.rowOf[k] := i, st.seen := true
                        this._Narrow()
                        break
                    }
                if (!this.rowOf.Has(k) && !this._dead.Has(k) && rows.Length && !st.seen && now - st.at >= MinionSkills.LearnMs) {
                    st.seen := true          ; counted once a press
                    this._miss[k] := (this._miss.Has(k) ? this._miss[k] : 0) + 1
                    if (this._miss[k] >= 2)
                        this._dead[k] := true
                }
            }
            pts := this._Points(hud, now)
            if (pts >= 0 && st.pts >= 0 && pts != st.pts)
                st.seen := true
            if (!st.seen && IsObject(row) && this._CoolMs(k)
                && now >= st.at + this.CastMs(k) + Max(MinionSkills.ConfirmMs, this._CoolMs(k) // 10)) {
                st.seen := true, st.est := now + MinionSkills.RetryMs
            }
        }
    }

    _Taken(i) {
        for k, r in this.rowOf
            if (r = i)
                return true
        return false
    }

    ; every row has its key: only those keys, in row order
    _Narrow() {
        if (this.rowOf.Count < this._slots.Length)
            return
        ks := []
        for i in this._slots
            for k, r in this.rowOf
                if (r = i)
                    ks.Push(k)
        this.keys := ks
    }
}
