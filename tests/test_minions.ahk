#Requires AutoHotkey v2.0
; Tests for lib\tasks\Minions.ahk. The aura storage fake (ObStore) and the
; helpers come from test_obby.ahk / test_questmatch.ahk. Bar colors are the
; live ones (2026-10-31, a Sand Storm orb read live).
#Include ..\lib\tasks\Minions.ahk

; QmIO whose waits move a fake clock (io.t, ms): the hunt's time limits.
; The keys stay down across the steps (_Go), so a walk is no w press:
; walks = full steps walked, by their jump (w alone down, not its first
; moment: _Escape's); HeldMs(k) = ms k was down so far; downAt[i] = the
; clock at log entry i.
class MnIO extends QmIO {
    t := 1000000
    walks := 0
    keysDown := Map()
    heldSum := Map()
    downAt := Map()
    Down(k) {
        if (k == "Space" && this.keysDown.Has("w") && this.t > this.keysDown["w"] && !this.keysDown.Has("a") && !this.keysDown.Has("d"))
            this.walks++
        this.keysDown[k] := this.t
        super.Down(k)
        this.downAt[this.log.Length] := this.t
    }
    Up(k) {
        if this.keysDown.Has(k) {
            this.heldSum[k] := this.HeldMs(k)
            this.keysDown.Delete(k)
        }
        super.Up(k)
    }
    HeldMs(k) => this.heldSum.Get(k, 0) + (this.keysDown.Has(k) ? this.t - this.keysDown[k] : 0)
    Wait(ms, ctx := "") {
        this.t += ms
        return super.Wait(ms, ctx)
    }
    Wheel(dir, n := 1, gapMs := 25) => this.log.Push("wheel " dir " " n)
}

; MnIO with the shift lock hooks (Input.ShiftLock): the cursor is pinned
; to the screen centre while lock is on, Left Shift's scan code released
; toggles it (works = false: it does nothing); locked = clicks sent while
; it was on (they miss the UI)
class MnLockIO extends MnIO {
    lock := false
    works := true
    locked := 0
    free := false                 ; a game screen frees the cursor: the lock reads off
    pos := {x: 0, y: 0}
    MouseAt(x, y) {
        this.log.Push("mouse " x "," y)
        this.pos := {x: x, y: y}
    }
    MousePos() => (this.lock && !this.free) ? {x: 1281, y: 719} : this.pos
    KeyEvent(keys) {
        this.log.Push("event " keys)
        if (keys = "{sc02A up}" && this.works)
            this.lock := !this.lock
    }
    ClickHere() {
        this.locked += this.lock ? 1 : 0
        return super.ClickHere()
    }
}

; -> {t, io, wh, logs, s, state}; frames = Array of bar lists, one per scan
; (the last one repeats). Now() is io.t. io: MnIO (no shift lock hooks).
MnTask(frames := "", gets := "", owned := "", io := "") {
    MinionsTask.LockX := MinionsTask.CenterX     ; fake bars sit at the centre and do not move when turned to
    io := IsObject(io) ? io : MnIO()
    wh := QmWh()
    logs := []
    s := ObStore(io, "Glock", IsObject(owned) ? owned : ["Eden", "Glock"])
    g := Map("Minions.enabled", 1, "Minions.patrol", 0, "Minions.spots", 0)
    if (gets is Map)
        for k, v in gets
            g[k] := v
    fr := IsObject(frames) ? frames : [[]]
    n := 0
    t := MinionsTask({
        cfg: QmCfg(g, Map()), io: io, webhook: wh, cal: QmObbyCal(false),
        ocr: (x, y, w, h, scale := 1) => s.Ocr(x, y, w, h),
        aura: () => s.Aura(), log: (m) => MnLog(logs, io, m), now: () => io.t, rect: (x, y, w, h) => s.Rect(x, y, w, h),
        scan: () => fr[Min(++n, fr.Length)], biome: () => st.biome, hud: () => MnNoPanel(), beacon: () => [],
        bossbar: () => false                         ; no boss bar UI at the top
    })
    st := SchedState()
    st.biome := "RAINY"
    return {t: t, io: io, wh: wh, logs: logs, s: s, state: st}
}

; the hud of a hunt test: Eden's panel unread (no row: no cooldown to
; read; the book keeps Eden's layout), 10 points (no Voidrush), no rank
MnNoPanel() => {rows: ["", "", "", "", "", ""], points: 10, rank: ""}

; logs gets m; io.backAt = io.log's length + 1 when the walk back to the
; fight starts (MnFight)
MnLog(logs, io, m) {
    logs.Push(m)
    if (!io.HasOwnProp("backAt") && InStr(m, "back to the fight"))
        io.backAt := io.log.Length + 1
}

; io.log index where the walk back to the fight starts, 0 = none (MnDowns'
; upTo: the fight only)
MnFight(io) => io.HasOwnProp("backAt") ? io.backAt : 0

; the biome in m ends ms into the fake clock
MnEndsBiome(m, ms) {
    t0 := m.io.t
    m.t._biomeFn := () => (m.io.t - t0 >= ms) ? "NORMAL" : "RAINY"
}

; rows like StripGrab.Rows: bg everywhere, a bar (yellow row, orange rows
; under it) from column c1 to c2 at row r
MnRows(nRows, nCols, bars, bg := 0xF1D7CD) {
    rows := []
    Loop nRows {
        row := []
        Loop nCols
            row.Push(bg)
        rows.Push(row)
    }
    for b in bars {
        Loop b.c2 - b.c1 + 1 {
            c := b.c1 + A_Index - 1
            rows[b.r][c] := 0xFFFF96              ; fog yellow (255,255,150)
            rows[b.r + 1][c] := 0xFFCF9D          ; (255,207,157)
            rows[b.r + 2][c] := 0xFFB89D          ; (255,184,157)
        }
        if b.HasOwnProp("text")                   ; "300 / 300" on it
            Loop 5
                rows[b.r][b.text + A_Index] := 0xFFFFFF
    }
    return rows
}

Test_Minions_Colors() {
    AssertTrue(MinionsTask.IsYellow(0xFFFF96) && MinionsTask.IsYellow(0xF9EF1C), "fog / clear yellow")
    AssertTrue(MinionsTask.IsOrange(0xFFB89D) && MinionsTask.IsOrange(0xF37B0D), "fog / clear orange")
    AssertTrue(!MinionsTask.IsYellow(0xF1D7CD) && !MinionsTask.IsOrange(0xF1D7CD), "sand storm fog is neither")
    AssertTrue(!MinionsTask.IsYellow(0xFFFFFF), "white text is not yellow")
}

Test_Minions_FindsBarsAcrossTheirText() {
    ys := [], rows := MnRows(20, 100, [{r: 5, c1: 20, c2: 59, text: 35}, {r: 12, c1: 70, c2: 84}])
    Loop 20
        ys.Push(100 + A_Index * 2)
    bars := MinionsTask.FindBars(rows, ys, 0, 2)
    AssertEq(bars.Length, 2, "orb bar (split by its text) and a minion bar")
    AssertEq(bars[1].w, 80, "the text gap is bridged: one 80 px bar")
    AssertEq(bars[1].y, ys[5], "its row")
}

Test_Minions_IgnoresThickYellowAndBareRuns() {
    ys := []
    Loop 20
        ys.Push(A_Index * 2)
    rows := MnRows(20, 100, [])
    Loop 6 {                                      ; a lamp: yellow rows stacked
        r := 4 + A_Index
        Loop 30
            rows[r][10 + A_Index] := 0xFFFF96
    }
    Loop 30                                       ; orange under it
        rows[11][10 + A_Index] := 0xFFB89D
    Loop 30                                       ; a yellow line with nothing under it
        rows[16][50 + A_Index] := 0xFFFF96
    AssertEq(MinionsTask.FindBars(rows, ys, 0, 2).Length, 0, "neither is a health bar")
}

Test_Minions_TurnFor() {
    AssertEq(MinionsTask.TurnFor(1300).ms, 0, "near the centre: aimed")
    t := MinionsTask.TurnFor(600)
    AssertEq(t.key, "Left", "left of centre -> Left")
    AssertEq(t.ms, 189, "680 px at 3.6 px/ms")
    AssertEq(MinionsTask.TurnFor(2500).ms, MinionsTask.TurnMaxMs, "capped")
}

Test_Minions_EligibleOncePerWeatherBiome() {
    m := MnTask()
    AssertEq(m.t.name "/" m.t.priority, "minions/6", "name / priority")
    AssertEq(m.t.CanRun(m.state), true, "RAINY, on, storage calibrated")
    m.state.biome := "PUMPKIN MOON"
    AssertEq(m.t.CanRun(m.state), false, "an event biome")
    m.state.biome := "GLITCHED"
    AssertEq(m.t.CanRun(m.state), false, "a rare biome")
    m.state.biome := "RAINY"
    m.t.CanRun(m.state)                           ; the scheduler asks first
    m.t.Run(SchedCtx())
    AssertEq(m.t.CanRun(m.state), false, "hunted this biome already")
    m.state.biome := "GRAVEYARD", m.t.CanRun(m.state), m.state.biome := "SNOWY"
    AssertEq(m.t.CanRun(m.state), true, "a new weather biome -> again")
    AssertEq(MnTask(, Map("Minions.enabled", 0)).t.CanRun(m.state), false, "off")
}

; L44-L51: 77 of 154 hunts were NORMAL, no orb on any frame. Eden on and the
; closing respawn fresh: nothing to do there. Minions.normal 1: hunted.
Test_Minions_NormalIsNotHuntedUnlessSet() {
    m := MnTask()
    m.s.logName := "Eden"
    MnShortHunt(m)
    m.state.biome := "NORMAL"
    AssertEq(m.t.CanRun(m.state), false, "NORMAL, all set: idle")
    m.io.t += MinionsTask.RehuntMs
    AssertEq(m.t.CanRun(m.state), false, "still idle a RehuntMs on")
    n := MnTask(, Map("Minions.normal", 1))
    n.state.biome := "NORMAL"
    AssertEq(n.t.CanRun(n.state), true, "Minions.normal 1: hunted")
    MnShortHunt(n)
    AssertTrue(InStr(MnStatsOf(n), "casts=2"), "a fight, not the set-up")
    AssertTrue(!MnLogged(n, "set-up"), "no set-up line")
}

; the aura off in NORMAL (L51 22:26:58, after a PUMPKIN MOON): the swap and
; the respawn there, once, no walk, no look. The orb biome then starts as
; after a hunt.
Test_Minions_NormalSetsUpOnceThenIdles() {
    m := MnTask()                                 ; Glock on, no respawn yet
    m.state.biome := "NORMAL"
    AssertEq(m.t.CanRun(m.state), true, "the set-up is due")
    AssertEq(m.t.Run(SchedCtx()), 0, "nothing hit")
    AssertEq(m.s.State().eq, "Eden", "the swap made")
    AssertEq(QmObbyDowns(m.io, "r"), 1, "one respawn")
    AssertEq(QmObbyDowns(m.io, "w") + QmObbyDowns(m.io, "Left") + QmObbyDowns(m.io, "Right"), 0, "no walk, no look")
    AssertEq(MnSkills(m.io), 0, "no skill")
    AssertTrue(!MnLogged(m, "minions: stats") && !MnLogged(m, "hunt over"), "no fight")
    AssertTrue(MnLogged(m, "minions: set-up in NORMAL") && MnLogged(m, "minions: set-up over"), "logged")
    AssertEq(m.t.CanRun(m.state), false, "idle now")
    m.io.t += MinionsTask.RehuntMs
    AssertEq(m.t.CanRun(m.state), false, "nothing is due a RehuntMs on")
    m.state.biome := "RAINY"
    AssertEq(m.t.CanRun(m.state), true, "an orb biome")
    esc := QmObbyDowns(m.io, "Esc")
    MnShortHunt(m)
    AssertTrue(MnLogged(m, "minions: still at spawn since the last hunt - no respawn"), "straight to the fight")
    AssertEq(QmObbyDowns(m.io, "Esc"), esc + 1, "only its closing respawn")
}

; the closing respawn nearly stale (SpawnKeepMs) or missing: made here, not
; at the orb biome's start. Eden on: no storage. L51 22:45: a NORMAL of 899 s.
Test_Minions_NormalRespawnsBeforeTheClosingOneGoesStale() {
    m := MnTask()
    m.s.logName := "Eden"
    MnShortHunt(m)
    AssertTrue(MinionsTask.PrepAfterMs < MinionsTask.SpawnKeepMs, "made before it goes stale")
    m.state.biome := "NORMAL"
    m.t.CanRun(m.state)
    m.io.t += MinionsTask.PrepAfterMs - 1000
    AssertEq(m.t.CanRun(m.state), false, "not yet")
    m.io.t += 1000
    AssertEq(m.t.CanRun(m.state), true, "old enough")
    r := QmObbyDowns(m.io, "r"), t0 := m.io.t
    m.t.Run(SchedCtx())
    AssertEq(QmObbyDowns(m.io, "r"), r + 1, "one respawn")
    AssertTrue(m.t._spawnAt >= t0, "recorded")
    AssertEq(QmObbyFirst(m.io, "type E"), 0, "no storage")
    AssertEq(m.t.CanRun(m.state), false, "idle again")
    m.t._spawnAt := 0, m.io.t += MinionsTask.RehuntMs
    AssertEq(m.t.CanRun(m.state), true, "no respawn to start from")
}

; no aura to put on: tried again a RehuntMs on, not every poll
Test_Minions_NormalSetUpThatFailsWaits() {
    m := MnTask(, , ["Glock"])
    m.state.biome := "NORMAL"
    AssertEq(m.t.CanRun(m.state), true, "due")
    AssertEq(m.t.Run(SchedCtx()), 0, "no Eden")
    AssertEq(m.t.CanRun(m.state), false, "not again at once")
    m.io.t += MinionsTask.RehuntMs
    AssertEq(m.t.CanRun(m.state), true, "again later")
}

; put back on: the user's aura stays on between hunts, _StillAtSpawn never
; holds, so there is nothing to ready. The log not knowing the aura: no reason.
Test_Minions_NormalSetUpNeedsAReason() {
    m := MnTask(, Map("Minions.putBack", 1))
    m.state.biome := "NORMAL"
    AssertEq(m.t.CanRun(m.state), false, "put back on")
    m := MnTask()
    m.s.logName := "Eden"
    MnShortHunt(m)
    m.s.known := false, m.s.logName := "Glock"
    m.state.biome := "NORMAL"
    AssertEq(m.t.CanRun(m.state), false, "aura unknown")
    m.s.known := true
    AssertEq(m.t.CanRun(m.state), true, "the log names another aura")
}

Test_Minions_WalksAttacksAndPutsTheAuraBack() {
    far := [{x: 1280, y: 600, w: 40}], near := [{x: 1290, y: 680, w: 200}]
    left := [{x: 400, y: 600, w: 40}]           ; a turn moves it to the centre
    m := MnTask([left, left, far, far, near], Map("Minions.putBack", 1))
    m.t._toastFn := () => (MnSkills(m.io) >= 3 ? "orb" : "")
    AssertEq(m.t.Run(SchedCtx()), 1, "the orb went down")
    AssertEq(m.s.State().eq, "Glock", "Glock back on")
    AssertTrue(QmObbyFirst(m.io, "type E") > 0, "Eden searched first")
    iLeft := QmObbyFirst(m.io, "down Left"), iW := QmObbyFirst(m.io, "down w"), iSkill := QmObbyFirst(m.io, "down e")
    AssertTrue(iLeft > 0 && iLeft < iW && iW < iSkill, "turned to it, walked up, then a skill")
    AssertTrue(iSkill < QmObbyFirst(m.io, "down f"), "Eden without its panel read: its layout, E first (then F)")
    AssertTrue(!MnLogged(m, "skill r"), "never Deadeye without a rank V")
    for k in ["1", "2", "3", "4", "5"]
        AssertEq(QmObbyDowns(m.io, k), 0, "never hotbar key " k)
}

Test_Minions_NothingFoundStillPutsTheAuraBack() {
    m := MnTask([[]], Map("Minions.putBack", 1))
    AssertEq(m.t.Run(SchedCtx()), 0, "no target")
    AssertEq(QmObbyDowns(m.io, "Left"), 2 * MinionsTask.ScanTurns + MinionsTask.SweepTurns - 1, "looked around, waited out a respawn, looked again, gave up, then the end sweep")
    AssertEq(m.s.State().eq, "Glock", "Glock back on")
}

; 2026-11-02 live: orbs and minions come ~35-40 s after the biome starts,
; and the hunt started at the change gave up after one respawn wait
Test_Minions_KeepsLookingUntilOrbsAreDue() {
    m := MnTask([[]])
    m.t.CanRun(m.state)                           ; the biome starts now
    t0 := m.io.t
    m.t.Run(SchedCtx())
    AssertTrue(QmObbyDowns(m.io, "Left") > 2 * MinionsTask.ScanTurns, "kept turning after the respawn wait")
    AssertTrue(m.io.t - t0 >= MinionsTask.OrbLateMs, "looked until OrbLateMs after the biome start")
    AssertTrue(MnLogged(m, "nothing in sight " MinionsTask.OrbLateMs // 1000 " s into the biome"), "the give up logged")
}

; the user, 2026-11-05: walk the map for orbs far from spawn
Test_Minions_PatrolWalksASpiralUntilTheHuntsTime() {
    AssertEq(MinionsTask.Spiral(1) " " MinionsTask.Spiral(2) " " MinionsTask.Spiral(3) " " MinionsTask.Spiral(4), "6 6 6 6", "a square, it stays on the island")
    m := MnTask([[]], Map("Minions.patrol", 1, "Minions.maxSec", 60))
    m.t.CanRun(m.state)
    t0 := m.io.t
    m.t.Run(SchedCtx())
    AssertTrue(MnLogged(m, "walking the map"), "started")
    AssertTrue(!MnLogged(m, "giving up"), "no give up")
    AssertTrue(!MnLogged(m, "waiting for a respawn"), "no respawn wait")
    AssertTrue(m.io.t - t0 >= 60000, "walked the hunt's time")
    AssertTrue(MnWalks(m.io) >= 12, "steps: " MnWalks(m.io))
    AssertTrue(QmObbyDowns(m.io, "Right") + QmObbyDowns(m.io, "Left") >= 2, "corners")
}

; the game under the map walk: the camera goes round in 3000 ms of arrow key
; whatever FullTurnMs says, w walks the way it faces; far: the furthest out
class MnGroundIO extends MnIO {
    cam := 0
    x := 0.0
    y := 0.0
    far := 0
    Wait(ms, ctx := "") {
        this.cam += (this.keysDown.Has("Right") ? ms : 0) - (this.keysDown.Has("Left") ? ms : 0)
        if this.keysDown.Has("w") {
            a := 2 * 3.141592653589793 * this.cam / 3000
            this.x += ms * Sin(a), this.y += ms * Cos(a)
            this.far := Max(this.far, Sqrt(this.x ** 2 + this.y ** 2))
        }
        return super.Wait(ms, ctx)
    }
}

; on the true circle the walk stays where PatrolHeading means it to, from any
; way the camera faced: with 1250 the model stayed under 9 s, the feet ran out
; to 33 s (the study's port of PatrolHeading, 57 falls in non-NORMAL hunts)
Test_Minions_PatrolStaysInItsRadiusFromAnyBearing() {
    ctx := SchedCtx(), c := MinionsTask.FullTurnMs
    Loop 48 {
        b := (A_Index - 1) * c // 48 - 3 * c         ; a few circles on, as after a look round
        io := MnGroundIO(), m := MnTask(, , , io), t := m.t
        t._bearing := b, io.cam := b
        f := {wallOff: "", pLeg: 0, pLeft: 0, shift: 0}
        Loop 200
            AssertTrue(t._PatrolStep(ctx, f), "on")
        t._Stop()
        AssertTrue(f.pLeg >= 20, "legs from bearing " b ": " f.pLeg)
        AssertTrue(io.far <= MinionsTask.PatrolRadiusMs, "from bearing " b ": " Round(io.far) " ms out")
        AssertTrue(MinionsTask.Gap(t._pos, io) < 50, "the reckoned place is the real one, from bearing " b)
    }
}

Test_Minions_PatrolStopsForATarget() {
    m := MnTask(, Map("Minions.patrol", 1))
    m.t.CanRun(m.state)
    due := m.io.t + MinionsTask.PatrolAfterMs + 15000
    near := [{x: 1280, y: 680, w: 200}]
    m.t._scanFn := () => (m.io.t < due) ? [] : near
    m.t._toastFn := () => (MnSkills(m.io) >= 3 ? "orb" : "")
    AssertEq(m.t.Run(SchedCtx()), 1, "the orb met on the walk went down")
    AssertTrue(MnLogged(m, "walking the map"), "it walked first")
}

; one circle at spawn, then the walk: not a fixed time into the biome (the 45 s
; of PatrolAfterMs stood at spawn in 19 of 35 biomes)
Test_Minions_WalksAfterOneCircle() {
    m := MnTask(, Map("Minions.patrol", 1))
    m.t.CanRun(m.state)
    t0 := m.io.t, st := {at: "", looks: 0, n: 0}
    near := [{x: 1280, y: 680, w: 200}]
    m.t._scanFn := () => MnWalkSeen(m, st, t0) ? near : []
    m.t._toastFn := () => (MnSkills(m.io) >= 3 ? "orb" : "")
    m.t.Run(SchedCtx())
    AssertTrue(st.at != "", "walked")
    AssertTrue(st.looks >= MinionsTask.SweepTurns - 1, "the circle first: " st.looks " turns")
    AssertTrue(st.looks <= MinionsTask.SweepTurns, "one circle, not more: " st.looks " turns")
    AssertTrue(st.at < 20000, "long before the old 45 s: " st.at " ms")
}

; the first scan after "walking the map": st.at, ms from t0, st.looks, the
; turns till then -> true
MnWalkSeen(m, st, t0) {
    if !MnLogged(m, "walking the map") {
        st.looks := QmObbyDowns(m.io, "Left")
        return false
    }
    if (st.at = "")
        st.at := m.io.t - t0
    return true
}

Test_Minions_OrbsAppearingLateAreHunted() {
    m := MnTask()
    m.t.CanRun(m.state)
    due := m.io.t + 40000, n := 0
    near := [{x: 1280, y: 680, w: 200}]
    m.t._scanFn := () => (m.io.t < due) ? [] : near
    m.t._toastFn := () => (MnSkills(m.io) >= 3 ? "orb" : "")
    AssertEq(m.t.Run(SchedCtx()), 1, "the orb that came 40 s in went down")
    AssertTrue(QmObbyDowns(m.io, "t") >= 1, "skills on it")
}

Test_Minions_GiveUp() {
    late := MinionsTask.OrbLateMs
    AssertEq(MinionsTask.GiveUp(false, 999999, 0), false, "the respawn wait first")
    AssertEq(MinionsTask.GiveUp(true, late - 1, 0), false, "orbs may still come")
    AssertEq(MinionsTask.GiveUp(true, late, 0), true, "OrbLateMs into the biome: done")
    AssertEq(MinionsTask.GiveUp(true, 5, ""), true, "biome start unknown: after the wait")
    q := MinionsTask.SeenQuietMs
    AssertEq(MinionsTask.GiveUp(true, late + 10, 0, late), false, "a bar seen just now: keep looking")
    AssertEq(MinionsTask.GiveUp(true, late + q, 0, late), true, "nothing seen for SeenQuietMs: done")
    AssertEq(MinionsTask.GiveUp(true, late, 0, ""), true, "nothing seen at all: done")
}

; 2026-11-02 live: SNOWY turned into PUMPKIN MOON mid-hunt and the hunt
; went on at orange lanterns. The biome changed: the hunt ends (respawn
; still), and the new biome is not counted as hunted.
Test_Minions_BiomeChangeEndsTheHunt() {
    m := MnTask()
    m.t.CanRun(m.state)
    near := [{x: 1280, y: 680, w: 200}], n := 0
    m.t._scanFn := () => (++n = 6 ? m.state.biome := "PUMPKIN MOON" : 0, near)
    m.t.Run(SchedCtx())
    AssertTrue(MnLogged(m, "biome changed (RAINY -> PUMPKIN MOON)"), "logged")
    AssertTrue(QmObbyDowns(m.io, "t") + QmObbyDowns(m.io, "f") <= 6, "no skills long after the change")
    AssertEq(QmObbyDowns(m.io, "r"), 2, "respawned before and after the hunt")
    m.state.biome := "SNOWY"
    AssertEq(m.t.CanRun(m.state), true, "a new normal biome: hunted")
}

Test_Minions_BiomeChangedToANormalOneIsNotHunted() {
    m := MnTask()
    m.t.CanRun(m.state)
    n := 0
    m.t._scanFn := () => (++n = 3 ? m.state.biome := "SNOWY" : 0, [])
    m.t.Run(SchedCtx())
    AssertTrue(MnLogged(m, "biome changed (RAINY -> SNOWY)"), "logged")
    AssertEq(m.t.CanRun(m.state), true, "SNOWY came during the hunt: not hunted yet")
}

; bars and casts do not keep a hunt past its biome: 0 of 11 "staying while
; its bars do" lines (L47-L51) had a bar within 3 s after, L51 23:02:37 then
; wandered 92 s. The new biome's orbs: its search starts empty (the branch
; sets _biome, so CanRun's own reset never fires).
Test_Minions_BiomeChangeEndsAFightGoingOn() {
    m := MnTask()
    m.t.CanRun(m.state)
    m.t._searched["1:1"] := 1, m.t._walls.Push({b: 300})
    near := [{x: 1280, y: 680, w: 200}]
    m.t._scanFn := () => (MnSkills(m.io) >= 2 ? m.state.biome := "WINDY" : 0, near)
    m.t.Run(SchedCtx())
    AssertTrue(MnLogged(m, "the biome changed (RAINY -> WINDY) - hunt over"), "over at the change")
    AssertTrue(!MnLogged(m, "staying while"), "no stay")
    AssertTrue(MnSkills(m.io) <= 3, "no skills after the change: " MnSkills(m.io))
    AssertEq(m.t._searched.Count, 0, "nowhere searched in WINDY")
    AssertEq(m.t._walls.Length, 0, "no wall met in WINDY")
    AssertEq(m.t.CanRun(m.state), true, "WINDY came during the hunt: not hunted yet")
}

; b0 is read after the set-up (~3 s): a hunt started at the very end of a
; biome would read the next one, see no change and hunt there to maxSec
Test_Minions_BiomeGoneDuringTheSetUpEndsTheHuntAtOnce() {
    near := [{x: 1280, y: 680, w: 200}]
    for b in ["NORMAL", "PUMPKIN MOON"] {
        m := MnTask([near])
        m.t.CanRun(m.state)
        m.state.biome := b                        ; CanRun saw RAINY
        m.t.Run(SchedCtx())
        AssertTrue(MnLogged(m, "the biome changed (RAINY -> " b ") - hunt over"), "logged: " b)
        AssertEq(MnSkills(m.io), 0, "no skill: " b)
        AssertEq(QmObbyDowns(m.io, "r"), 2, "respawned before and after: " b)
        AssertTrue(InStr(MnStatsOf(m), "seen=0"), "not one look: " b)
        AssertEq(m.t._biome, b, "the new biome taken: " b)
    }
    m := MnTask([near])                           ; another orb biome: on, its orbs are as good
    m.t.CanRun(m.state)
    m.state.biome := "WINDY"
    m.t._toastFn := () => (MnSkills(m.io) >= 2 ? "orb" : "")
    AssertEq(m.t.Run(SchedCtx()), 1, "WINDY is hunted")
    m := MnTask([near], Map("Minions.normal", 1))
    m.t.CanRun(m.state)
    m.state.biome := "NORMAL"
    m.t._toastFn := () => (MnSkills(m.io) >= 2 ? "orb" : "")
    AssertEq(m.t.Run(SchedCtx()), 1, "Minions.normal 1: so is NORMAL")
    m := MnBoss([near])
    m.s.logName := "Eden"
    m.state.biome := "WINDY"
    m.t.Run(SchedCtx())
    AssertTrue(MnLogged(m, "the biome changed (GRAVEYARD -> WINDY) - hunt over"), "the boss's biome over")
    AssertEq(MnSkills(m.io), 0, "no boss fight in WINDY")
}

Test_Minions_BiomeLeft() {
    AssertEq(MinionsTask.BiomeLeft("SNOWY", "PUMPKIN MOON"), true, "changed")
    AssertEq(MinionsTask.BiomeLeft("SNOWY", "SNOWY"), false, "the same")
    AssertEq(MinionsTask.BiomeLeft("", "SNOWY"), false, "unknown at the start: ignored")
    AssertEq(MinionsTask.BiomeLeft("SNOWY", ""), false, "unknown now: ignored")
}

Test_Minions_NoEdenNoHunt() {
    m := MnTask([[{x: 1280, y: 680, w: 200}]], , ["Glock"])
    AssertEq(m.t.Run(SchedCtx()), 0, "Eden not owned")
    AssertEq(QmObbyDowns(m.io, "e"), 0, "no skill pressed")
    AssertEq(m.wh.Count("errors"), 1, "reported")
}

; ---- real frames (tests\screens, cropped from 2560x1440, 2026-10-31) ------

; FindBars over a cropped frame: rows 2 px apart, every 2nd pixel
MnFrameBars(name, w, h) {
    ys := []
    y := 0
    while (y < h)
        ys.Push(y), y += 2
    rows := MatchFileGrab(A_ScriptDir "\screens\" name).Call(0, w - 1, ys, 2)
    return MinionsTask.FindBars(rows, ys, 0, 2)
}

; MinionsTask.Scan over a cropped frame (rows 2 px apart, then every row
; around the thin strips)
MnFrameScan(name, w, h) => MinionsTask.Scan(MatchFileGrab(A_ScriptDir "\screens\" name), {x1: 0, x2: w - 1, y1: 0, y2: h - 1})

; 2026-11-02 live (WINDY, far): an orb's bar 4 px high and four minions'
; one yellow row over one red-orange row, their text above them. Rows 2 px
; apart found none of them.
Test_Minions_RealFarWindyOrbAndMinions() {
    AssertEq(MnFrameBars("minions_windy_far.png", 264, 100).Length, 0, "rows 2 px apart alone: none")
    bars := MnFrameScan("minions_windy_far.png", 264, 100)
    AssertEq(bars.Length, 5, "the orb's bar and four minions'")
    AssertEq(bars[1].y " " bars[1].w, "33 44", "the orb's bar: 44 px, the highest")
}

; the far-bar pass adds no bar to the other real frames but two minions':
; one right of the Quest Board orb, one half hidden behind the snowy one
Test_Minions_RealScanAddsOnlyRealBars() {
    AssertEq(MnFrameScan("minions_gold_title.png", 700, 300).Length, 0, "gold aura title")
    AssertEq(MnFrameScan("minions_gold_sign.png", 240, 160).Length, 0, "gold leaderboard sign")
    AssertEq(MnFrameScan("minions_sand_orb.png", 260, 140).Length, 3, "sand storm orb + 2 minions")
    AssertEq(MnFrameScan("minions_snowy_close.png", 260, 150).Length, 3, "snowy close: orb, minion and a piece of its bar past the flare")
    bars := MnFrameScan("minions_snowy_far.png", 200, 130)
    AssertEq(bars.Length, 3, "snowy far: orb, minion and the minion half hidden behind it")
    AssertEq(bars[3].x " " bars[3].y " " bars[3].w, "32 98 28", "the half hidden one")
    bars := MnFrameScan("minions_questboard_orb.png", 200, 120)
    AssertEq(bars.Length, 2, "the Quest Board orb and now its far minion")
    AssertEq(bars[2].y " " bars[2].w, "77 38", "the minion's bar")
}

; 2026-11-02 live (SNOWY, near): the orb's bar 146 px wide is 11 px tall
; (yellow 6 over orange 5), a minion's 118 px 8 px (and a red line under
; it); rows 2 px apart saw yellow 2 px above every yellow row they hit, or
; no clear row 8 px under it: no bar found while the camera looked at them
Test_Minions_RealTallSnowyBars() {
    bars := MnFrameBars("minions_snowy_tall.png", 300, 160)
    AssertEq(bars.Length, 2, "the orb's bar and the front minion's")
    AssertEq(bars[1].x " " bars[1].y " " bars[1].w, "216 30 146", "the orb's bar")
    AssertEq(bars[2].x " " bars[2].y " " bars[2].w, "82 132 118", "the minion's bar")
    AssertEq(MnFrameScan("minions_snowy_tall.png", 300, 160).Length, 2, "Scan: the same two")
    ; yellow 5 px from an even row: the orange 6 px under the top yellow row
    bars := MnFrameScan("minions_snowy_tall_orb.png", 200, 80)
    AssertEq(bars.Length, 1, "the orb's bar")
    AssertEq(bars[1].y " " bars[1].w, "40 126", "the orb's bar, 126 px")
}

; 2026-11-02 live (NORMAL, spawn): the gold leaderboard sign's base, 256 px
; wide and ~20 px tall, yellow over a shade (r - g ~40) then grass: taken
; for a tall near bar ("target at ... (bar 160 px)" with no orb in sight)
; L23 RAINY / NORMAL: the leaderboards' lit strip, yellow straight into brick
; (r - g <= 86, a bar ends red): every hunt from spawn walked into the board
Test_Minions_RealBoardBaseIsNoBar() {
    AssertEq(MnFrameScan("minions_board_base_normal.png", 340, 60).Length, 0, "NORMAL: no bar")
    AssertEq(MnFrameScan("minions_board_base_rainy.png", 320, 60).Length, 0, "RAINY: no bar")
}

Test_Minions_RealGoldSignBaseIsNoBar() {
    AssertEq(MnFrameBars("minions_sign_base.png", 340, 160).Length, 0, "rows 2 px apart: no bar")
    AssertEq(MnFrameScan("minions_sign_base.png", 340, 160).Length, 0, "Scan: no bar")
    ; the same base under both signs in WINDY light, 352 px
    AssertEq(MnFrameScan("minions_sign_base_windy.png", 420, 120).Length, 0, "WINDY: no bar")
}

; 2026-11-03 live: a far bar is yellow over red-orange; a house's lit
; bookshelf (NORMAL night, 20 px: yellow over amber ffa031) and the Donate
; board's gold trim (22 px, over the navy) are yellow over amber, hue ~55
Test_Minions_RealAmberStripsAreNoFarBar() {
    AssertEq(MnFrameScan("minions_lit_shelf.png", 200, 100).Length, 0, "lit bookshelf")
    AssertEq(MnFrameScan("minions_donate_trim.png", 200, 120).Length, 0, "Donate board trim")
}

; 2026-11-03 live NORMAL: narrow (26..44 px) gold strips under the sky or
; over the leaderboard's navy are paler than the darker side round them
; (the gold sign base's top edge, the leaderboard's trim and base); a
; brick block's yellow lip has orange right over it
Test_Minions_RealGoldEdgesAndBrickLipAreNoBar() {
    AssertEq(MnFrameScan("minions_sign_base_top.png", 261, 161).Length, 0, "gold sign base's top edge")
    AssertEq(MnFrameScan("minions_trim_navy.png", 201, 141).Length, 0, "leaderboard trim over navy")
    AssertEq(MnFrameScan("minions_trim_base.png", 221, 131).Length, 0, "leaderboard base")
    AssertEq(MnFrameScan("minions_brick_lip.png", 221, 141).Length, 0, "brick block's lip")
}

; MnFrameScan's bars as "x,y w h"
MnBarsShow(bars) {
    s := ""
    for b in bars
        s .= (s = "" ? "" : " | ") b.x "," b.y " w" b.w " h" b.h
    return s
}

; clips L19 2026-11-03 (1280x720, upscaled 2x): minions in the player's
; face, their bars 320..1210 px wide and 16..92 px tall, yellow over an
; orange-to-red gradient the HP text crosses, blurred edges. MaxRun 420
; dropped them all ("target lost from sight (near)" with them right there)
Test_Minions_RealPointBlankBars() {
    AssertEq(MnBarsShow(MnFrameScan("minions_pointblank_snowy_two.png", 900, 400)), "300,40 w484 h26 | 632,340 w404 h22"
        , "SNOWY 053406: two Frozen Warriors close up")
    AssertEq(MnBarsShow(MnFrameScan("minions_pointblank_snowy_506.png", 600, 120)), "290,38 w506 h30"
        , "a part yellow row over its top (the HP text splits it)")
    AssertEq(MnBarsShow(MnFrameScan("minions_pointblank_snowy_top.png", 1300, 160)), "648,42 w1214 h92"
        , "right in the face: 1214 px at the top of the screen")
    AssertEq(MnBarsShow(MnFrameScan("minions_pointblank_snowy_322.png", 400, 80)), "198,32 w322 h16", "322 px")
    AssertEq(MnBarsShow(MnFrameScan("minions_pointblank_forest_394.png", 470, 80)), "234,30 w394 h22"
        , "LOST FOREST 053906 at night")
    AssertTrue(MinionsTask.Area.y1 <= 70 && MinionsTask.MaxRun >= 1214, "the scan reaches them")
}

; live shot L19 06:03:22 LOST FOREST: three far bars low on screen (42..56
; px, y ~700) were "near" (y 650 or lower) and skills went off from afar
Test_Minions_RealFarLowBarsAreNotNear() {
    AssertEq(MnBarsShow(MnFrameScan("minions_far_forest_060322.png", 400, 160)), "206,64 w56 h4 | 288,102 w44 h4 | 122,104 w36 h4"
        , "far, all of them")
}

; ---- the skill panel and Eden's points bar (2026-11-02 live, Eden) --------
; panel crops: screen x 2016.., y 1005..; bar crops: x 985.., y 1080..

MnPanel(name) => MinionsTask.Panel(MatchFileGrab(A_ScriptDir "\screens\" name), 2016, 1005)

; one panel as "T:0 F:0.55 ..." (rows top to bottom as Eden's keys, "-" = no row)
MnCds(p) {
    s := ""
    for r in p
        s .= SubStr("TFEQRV", A_Index, 1) ":" (IsObject(r) ? r.cd : "-") " "
    return RTrim(s)
}

Test_Minions_RealPanelCooldowns() {
    ; green floor: Darkmatter Barrage ~55% left, Cut Into Nothing ~94%; the V
    ; row cut off by the crop (black: no row)
    AssertEq(MnCds(MnPanel("eden_panel_cd_f_e.png")), "T:0 F:0.55 E:0.93 Q:0 R:0 V:-", "F and E cooling down")
    ; Taunt ~80% left; the toast over F / E (unreadable: ready)
    AssertEq(MnCds(MnPanel("eden_panel_cd_t.png")), "T:0.80 F:0 E:0 Q:0 R:0 V:0", "T cooling down, the toast ignored")
    ; another biome (blue-white behind the translucent rows) and the toast
    AssertEq(MnCds(MnPanel("eden_panel_cd_v_toast.png")), "T:0 F:0 E:0 Q:0 R:0 V:0.89", "Voidrush cooling down on a light background")
}

Test_Minions_PanelOfAnotherScreenHasNoRows() {
    p := MinionsTask.Panel(MatchFileGrab(A_ScriptDir "\screens\world_day.jpg"))
    AssertEq(MnCds(p), "T:- F:- E:- Q:- R:- V:-", "no skill panel in the world frame")
}

Test_Minions_RealPointsAndRank() {
    bar := (name) => MatchFileGrab(A_ScriptDir "\screens\" name)
    AssertEq(MinionsTask.Points(bar("eden_bar_70.png"), 985, 1080), 70, "70 points (404 px)")
    AssertEq(MinionsTask.Points(bar("eden_bar_90_rank_d.png"), 985, 1080), 90, "90 points, the rank's line above not counted")
    AssertEq(MinionsTask.Rank(bar("eden_bar_70.png"), 985, 1080), "", "no combo rank")
    AssertEq(MinionsTask.Rank(bar("eden_bar_90_rank_d.png"), 985, 1080), "?", "rank D: a letter, not V")
    AssertEq(MinionsTask.Points(bar("world_day.jpg")), -1, "no points bar in the world frame")
    AssertEq(MinionsTask.Rank(bar("world_day.jpg")), "", "nor a rank")
}

; loop L19 2026-11-03: most V presses logged no points, all at 0 (no fill,
; only the "0"): live screenshots (WINDY with Eden's ground swirl, SNOWY on
; light ground) and clip frames (WINDY 022508, half size scaled up 2x)
Test_Minions_RealZeroPointsAndRanks() {
    bar := (name) => MatchFileGrab(A_ScriptDir "\screens\" name)
    AssertEq(MinionsTask.Points(bar("eden_bar_0_swirl.png"), 985, 1080), 0, "live: the 0 alone, the swirl beside it")
    AssertEq(MinionsTask.Points(bar("eden_bar_0_snowy.png"), 985, 1080), 0, "live: the 0 on snow")
    AssertEq(MinionsTask.Points(bar("eden_bar_0_swirl_clip.png"), 985, 1080), 0, "clip: the 0 under the swirl")
    AssertEq(MinionsTask.Points(bar("eden_bar_30_rank_c_clip.png"), 985, 1080), 30, "clip: 30 (Voidrush's cost)")
    AssertEq(MinionsTask.Points(bar("eden_bar_5_rank_e_clip.png"), 985, 1080), 5, "clip: 5, the fill no wider than its digit")
    AssertEq(MinionsTask.Points(bar("eden_bar_37_rank_fading_clip.png"), 985, 1080), 37, "clip: 37")
    ; the rank: the swirl read "V" before (Deadeye would go); E / C read
    ; with their time line; the letter left after its line ran out: none
    AssertEq(MinionsTask.Rank(bar("eden_bar_0_swirl_clip.png"), 985, 1080), "", "the swirl is no rank V")
    AssertEq(MinionsTask.Rank(bar("eden_bar_0_swirl.png"), 985, 1080), "", "nor live")
    AssertEq(MinionsTask.Rank(bar("eden_bar_30_rank_c_clip.png"), 985, 1080), "?", "rank C")
    AssertEq(MinionsTask.Rank(bar("eden_bar_5_rank_e_clip.png"), 985, 1080), "?", "rank E, a short line left")
    AssertEq(MinionsTask.Rank(bar("eden_bar_37_rank_fading_clip.png"), 985, 1080), "", "C with its line run out: over")
}

; loop L19 06:03:36..06:04:02: "points 85" through three Voidrush presses.
; The read was right: the bar shows 85 in every frame of clip LOST FOREST
; 060426 (dark ground, "Player will automatically rejoin" under it); those
; V did nothing (no overlay, no cutscene). SNOWY 055335: a V that went
; (its dark cutscene) at 40 left the bar at 40 (its hits paid the cost
; back). Crops at screen x 984, y 1080, 720p scaled 2x.
Test_Minions_RealPointsAroundVoidrush() {
    bar := (name) => MatchFileGrab(A_ScriptDir "\screens\" name)
    AssertEq(MinionsTask.Points(bar("eden_bar_85_forest_clip.png"), 984, 1080), 85, "85 on the dark LOST FOREST ground")
    AssertEq(MinionsTask.Points(bar("eden_bar_before_voidrush_snowy_clip.png"), 984, 1080), 40, "40 before the V (rank E above)")
    AssertEq(MinionsTask.Points(bar("eden_bar_after_voidrush_snowy_clip.png"), 984, 1080), 40, "40 after it")
}

; a rank letter drawn into a fake grab (white rows = [x1, x2] spans)
MnRankGrab(spans) {
    return (x1, x2, ys, stride) => MnRankRows(spans, x1, x2, ys)
}
MnRankRows(spans, x1, x2, ys) {
    out := []
    for y in ys {
        row := []
        i := y - MinionsTask.RankY1 - 10 + 1             ; the letter from y 1090
        Loop x2 - x1 + 1 {
            x := x1 + A_Index - 1
            row.Push((i >= 1 && i <= spans.Length && MnInSpans(spans[i], x)) ? 0xFFFFFF : 0x103010)
        }
        out.Push(row)
    }
    return out
}

; x in one of the [x1, x2(, x3, x4)] spans
MnInSpans(sp, x) => (x >= sp[1] && x <= sp[2]) || (sp.Length >= 4 && x >= sp[3] && x <= sp[4])

Test_Minions_RankVIsAPoint() {
    v := [], d := []
    Loop 22 {
        h := (22 - A_Index) // 2                   ; 10 .. 0 px either side
        ; a V: two arms 6 px wide, apart at the top, one stroke at the point
        v.Push(h > 3 ? [1280 - h - 2, 1280 - h + 3, 1280 + h - 3, 1280 + h + 2] : [1280 - h - 2, 1280 + h + 2])
        d.Push([1268, 1292])
    }
    ; the rank's time line under the letter: 9 rows down, 5 thick, 200 wide
    lined := (spans) => MnRankLined(spans, 200)
    AssertEq(MinionsTask.Rank(MnRankGrab(lined(v))), "V", "wide on top, a point at the bottom")
    AssertEq(MinionsTask.Rank(MnRankGrab(lined(d))), "?", "as wide at the bottom: another letter")
    AssertEq(MinionsTask.Rank(MnRankGrab(v)), "", "no time line under it: no rank (a swirl, the bar's 0)")
    AssertEq(MinionsTask.Rank(MnRankGrab(MnRankLined(v, 10))), "", "a dot under it is no line")
    ; a V solid at the top (no arms apart): a point, but no V
    solid := []
    Loop 22
        h := (22 - A_Index) // 2, solid.Push([1280 - h - 2, 1280 + h + 2])
    AssertEq(MinionsTask.Rank(MnRankGrab(lined(solid))), "?", "no arms at the top: another letter")
    ; loop L19 03:07:42 / 03:52:37: Deadeye at C / D. Hair streaks off the
    ; centre, narrowing down, over the low-bobbing fill (its top read as
    ; the time line, its tall rows past the grab) read "V" before
    hair := []
    Loop 16
        hair.Push([1284 + A_Index, 1304 - (A_Index > 12 ? A_Index - 12 : 0)])
    Loop 4
        hair.Push([0, -1])
    Loop 70
        hair.Push([1180, 1380])                    ; the fill, to past RankY2
    AssertEq(MinionsTask.Rank(MnRankGrab(hair)), "", "hair over the fill: no letter")
    ; a centred V over the fill (no thin line): no rank either
    fill := v.Clone()
    Loop 4
        fill.Push([0, -1])
    Loop 70
        fill.Push([1180, 1380])
    AssertEq(MinionsTask.Rank(MnRankGrab(fill)), "", "the fill's top is no time line")
}

; every rank letter seen (real frames, crops at screen x 984, y 1080:
; full-res clip WINDY 030751 and the SNOWY 035319 clip at 720p scaled 2x)
; reads "?" (not V: Deadeye waits); the hair over the letter's place reads
; none (frame 22_hair read "?" before: a letter)
Test_Minions_RealRankLettersAndHair() {
    bar := (name) => MatchFileGrab(A_ScriptDir "\screens\" name)
    for f in ["eden_bar_46_rank_e.png", "eden_bar_38_rank_d.png", "eden_bar_44_rank_c.png", "eden_bar_15_rank_d_clip.png"]
        AssertEq(MinionsTask.Rank(bar(f), 984, 1080), "?", f ": a letter, not V")
    AssertEq(MinionsTask.Points(bar("eden_bar_44_rank_c.png"), 984, 1080), 44, "44 points under the C")
    AssertEq(MinionsTask.Points(bar("eden_bar_15_rank_d_clip.png"), 984, 1080), 15, "15 points under the D")
    AssertEq(MinionsTask.Rank(bar("eden_bar_22_hair.png"), 984, 1080), "", "hair streaks: no letter")
    AssertEq(MinionsTask.Rank(bar("eden_bar_44_hair.png"), 984, 1080), "", "a hair tip narrowing down: no V")
}

; spans, 8 empty rows, then 5 rows of a line w px wide centred on 1280
MnRankLined(spans, w) {
    out := spans.Clone()
    Loop 8
        out.Push([0, -1])
    Loop 5
        out.Push([1280 - w // 2, 1280 + w // 2])
    return out
}

; ---- MinionSkills: the next skill key from the panel --------------------

; Eden's six rows, ready unless cds (Map key -> overlay) says otherwise
MnHud(cds := "", points := -1, rank := "") {
    rows := []
    for k in ["t", "f", "e", "q", "r", "v"]
        rows.Push({cd: (cds is Map && cds.Has(k)) ? cds[k] : 0})
    return {rows: rows, points: points, rank: rank}
}

MnLogIndex(m, s) {
    for i, l in m.logs
        if InStr(l, s)
            return i
    return 0
}

; loop L19 05:32:07 "skills learn (e r t f q v)", 05:32:36 "skill r (points
; 49)": a "Potion Auto Added" toast over F / E / Q (live shots 05:32:09
; SNOWY and 05:47:06 NORMAL, crops at screen x 2016, y 1004) left rows
; unread, the book learnt every letter and pressed Deadeye with no rank
Test_Minions_RealToastOverPanelKeepsEdensLayout() {
    for f in ["eden_panel_toast_snowy.png", "eden_panel_toast_normal.png"]
        MnToastPanel(f)
}

MnToastPanel(f) {
    p := MinionsTask.Panel(MatchFileGrab(A_ScriptDir "\screens\" f), 2016, 1004)
    unread := 0
    for r in p
        unread += IsObject(r) ? 0 : 1
    AssertTrue(unread >= 1, f ": the toast hides rows (" MnCds(p) ")")
    AssertTrue(IsObject(p[1]) && IsObject(p[6]), f ": T and V clear of it (" MnCds(p) ")")
    learnt := Map()
    b := MinionSkills("Eden", p, learnt)
    AssertEq(b.how " " b.rowOf["r"] b.rowOf["v"] b.rowOf["f"], "panel 562", "Eden's layout, not learning")
    hud := {rows: p, points: 49, rank: ""}
    seen := ""
    t := 0
    Loop 60 {
        t += 400
        k := b.Next(hud, t)
        if (k != "")
            seen .= k, b.Pressed(k, hud, t)
    }
    AssertTrue(!InStr(seen, "r"), f ": no Deadeye at 49 points, no rank (" seen ")")
    AssertEq(SubStr(seen, 1, 2), "ef", f ": by priority: E, F (FirstOfFE), Voidrush after")
    AssertEq(b.Next({rows: p, points: 49, rank: "V"}, t + 100), "r", f ": rank V read: Deadeye")
}

; the hunt with Eden's panel read: T cooling down the whole hunt, 10 points
Test_Minions_HuntPressesOnlyReadySkills() {
    near := [{x: 1280, y: 680, w: 200}]
    m := MnTask([near, near, near, near, near, near, near, near, []])
    m.t._hudFn := () => MnHud(Map("t", 0.5), 10)
    m.t.Run(SchedCtx())
    AssertEq(QmObbyDowns(m.io, "t"), 0, "Taunt never (cooling down)")
    AssertEq(QmObbyDowns(m.io, "v"), 0, "Voidrush never (10 points)")
    AssertTrue(QmObbyDowns(m.io, "f") >= 1 && QmObbyDowns(m.io, "e") >= 1, "the others")
    AssertTrue(MnLogged(m, "minions: skills panel (r v f e t q)"), "the panel's skills logged")
}

Test_Minions_HuntDeadeyeAtRankV() {
    near := [{x: 1280, y: 680, w: 200}]
    m := MnTask([near, near, near, []])
    ; R's row cools down once Deadeye went (the respawn before the hunt is an r too)
    m.t._hudFn := () => MnHud(Map("r", QmObbyDowns(m.io, "r") >= 2 ? 0.9 : 0), 60, "V")
    m.t.Run(SchedCtx())
    AssertEq(QmObbyDowns(m.io, "r"), 3, "Deadeye once (and the two respawns)")
    r2 := 0, at := 0
    for i, e in m.io.log
        if (e = "down r" && ++r2 = 2)
            at := i
    v1 := QmObbyFirst(m.io, "down v")
    AssertTrue(at && (!v1 || v1 > at), "Deadeye before Voidrush")
    AssertTrue(MnLogged(m, "minions: skill r (points 60)"), "logged")
}

Test_Minions_ThinRowsMergeAndCap() {
    w := MinionsTask.ThinRows([{x: 100, y: 200, w: 30}, {x: 100, y: 204, w: 30}, {x: 500, y: 400, w: 30}], [])
    AssertEq(w.Length, 2, "seeds 4 px apart share rows")
    AssertEq(w[1][1] "-" w[1][w[1].Length] " " w[1].Length, "195-209 15", "every row 5 above to 5 below")
    AssertEq(MinionsTask.ThinRows([{x: 100, y: 200, w: 30}], [{x: 104, y: 202, w: 60}]).Length, 0, "a seed on a bar found")
    seeds := []
    Loop 50
        seeds.Push({x: 100, y: 120 + A_Index * 20, w: 30})
    n := 0
    for win in MinionsTask.ThinRows(seeds, [])
        n += win.Length
    AssertEq(n, MinionsTask.ThinCap, "a warm scene: ThinCap rows at most")
}

Test_Minions_RealSandStormOrbAndMinions() {
    bars := MnFrameBars("minions_sand_orb.png", 260, 140)
    AssertEq(bars.Length, 3, "the orb's bar and two minions' bars")
    AssertEq(bars[1].w, 76, "the orb's bar: 76 px")
}

Test_Minions_RealGoldAuraTitleIsNoBar() {
    AssertEq(MnFrameBars("minions_gold_title.png", 700, 300).Length, 0
        , "'Plushed : Pumpkinity' (gold gradient letters) and its pumpkin head")
}

; 2026-11-02 live frames: the gold leaderboard sign right of spawn passed
; as a bar (a pale yellow strip between dark blue panels); real bars stay
Test_Minions_RealGoldLeaderboardSignIsNoBar() {
    AssertEq(MnFrameBars("minions_gold_sign.png", 240, 160).Length, 0
        , "the sign's pale yellow edge (was a 136 px bar at 1994,554)")
}

Test_Minions_RealOrbBehindTheQuestBoard() {
    bars := MnFrameBars("minions_questboard_orb.png", 200, 120)
    AssertEq(bars.Length, 1, "WINDY: the orb's far bar above the Quest Board")
    AssertEq(bars[1].w, 42, "its 42 px")
}

Test_Minions_RealSnowyOrbAndMinionClose() {
    bars := MnFrameBars("minions_snowy_close.png", 260, 150)
    AssertEq(bars.Length, 2, "the orb's bar and a minion's")
    AssertEq(bars[1].w, 134, "the orb's bar: 134 px")
    AssertEq(bars[1].y, 30, "the orb's bar row")
}

Test_Minions_RealSnowyOrbAndMinionFarOnSnow() {
    bars := MnFrameBars("minions_snowy_far.png", 200, 130)
    AssertEq(bars.Length, 2, "the orb's bar and a minion's over bright snow")
    AssertEq(bars[1].w, 96, "the orb's bar: 96 px")
    AssertEq(bars[2].w, 66, "the minion's bar: 66 px")
}

Test_Minions_PaleStripOnDarkIsNoBar() {
    ys := []
    Loop 20
        ys.Push(A_Index * 2)
    sign := MnRows(20, 100, [{r: 5, c1: 20, c2: 59}], 0x29416A)
    Loop 40
        sign[5][19 + A_Index] := 0xFFFF7E         ; the sign's pale yellow
    AssertEq(MinionsTask.FindBars(sign, ys, 0, 2).Length, 0, "pale yellow on dark blue")
    pure := MnRows(20, 100, [{r: 5, c1: 20, c2: 59}], 0x29416A)
    Loop 40
        pure[5][19 + A_Index] := 0xFFFF00         ; a clear bar's pure yellow
    AssertEq(MinionsTask.FindBars(pure, ys, 0, 2).Length, 1, "pure yellow on dark blue is a bar")
}

Test_Minions_AutoRollSwapPutsTheCombatAuraBackOn() {
    old := MinionsTask.AuraCheckMs
    MinionsTask.AuraCheckMs := 0
    try {
        near := [{x: 1280, y: 680, w: 200}]
        m := MnTask([near, near, near, []])
        n := 0
        m.t._scanFn := () => (++n = 2 ? (m.s.logName := "Pumpkinity") : 0, n <= 3 ? near : [])
        m.t.Run(SchedCtx())
        swapped := false
        for l in m.logs
            swapped := swapped || InStr(l, "Pumpkinity got equipped")
        AssertTrue(swapped, "the log's new aura was noticed")
        types := 0
        for e in m.io.log
            types += (e == "type E") ? 1 : 0
        AssertEq(types, 2, "Eden searched again mid-hunt (once at the start)")
    } finally {
        MinionsTask.AuraCheckMs := old
    }
}

Test_Minions_FindsEdenUnderTheSpecialTab() {
    m := MnTask([[]], Map("Minions.putBack", 1))
    m.s.special := ["Eden"]
    m.t.Run(SchedCtx())
    AssertTrue(QmCountMoves(m.io, "move 567,-25") >= 1, "the Special tab was opened")
    AssertEq(m.wh.Count("errors"), 0, "Eden found and equipped")
    AssertEq(m.s.State().eq, "Glock", "Glock (Regular tab) back on after")
}

Test_Minions_EdenLogoNameStillEquips() {
    m := MnTask([[]])
    m.s.special := ["Eden"], m.s.logo := ["Eden"]
    m.t.Run(SchedCtx())
    AssertEq(m.wh.Count("errors"), 0, "the first result taken: its button reads Equip")
    AssertTrue(QmObbyFirst(m.io, "down Left") > 0, "the hunt ran")
}

Test_Obby_UnreadNameIsFoundThroughTheLog() {
    o := QmObbyTask("Glock", , , , ["Celestial", "Sailor", "Glock"])
    o.s.logo := ["Sailor", "Celestial"]
    o.s.owned := ["Sailor: Admiral", "Sailor", "Glock"]
    o.s.logo := ["Sailor: Admiral", "Sailor"]
    AssertEq(o.t.Run(SchedCtx()), 1, "names unread: equipped in turn until the log said Sailor")
    AssertEq(o.s.State().eq, "Glock", "Glock back after the run")
    found := false
    for l in o.logs
        found := found || InStr(l, "found by the log")
    AssertTrue(found, "logged how it was found")
}

; bars as on screen: moved by every Left turn (only ScanTurnMs ones here),
; none outside the scan area
MnTurning(m, bars) {
    out := []
    for b in bars {
        x := b.x + QmObbyDowns(m.io, "Left") * MinionsTask.Shift("Left", MinionsTask.ScanTurnMs)
        if (x >= MinionsTask.Area.x1 && x <= MinionsTask.Area.x2)
            out.Push({x: x, y: b.y, w: b.w})
    }
    return out
}

MnSkills(io, upTo := 0) {
    n := 0
    for i, e in io.log
        if (upTo && i >= upTo)
            break
        else if RegExMatch(e, "^down [tfeqv]$")
            n++
    return n
}

; a clip at night 2026-11-02: the player walked into a terrace wall for
; most of a 105 s hunt. Walks that get no closer -> a jump forward, a strafe
; left and one right (forward too), each checked by the next scan; still
; stuck -> that target is left alone and the hunt looks elsewhere (a bar
; about level with the player: no slide along the wall, WallHighY)
Test_Minions_StuckOnAWallTriesThenGivesUp() {
    m := MnTask()
    wall := [{x: 1280, y: 640, w: 60}]              ; not wide, not low: not near
    m.t._scanFn := () => MnTurning(m, wall)
    m.t.Run(SchedCtx())
    AssertEq(MnSkills(m.io), 0, "no skill at a target out of reach")
    for step in ["got no closer - jump forward (1/3)", "strafe left (2/3)", "strafe right (3/3)", "still stuck at 1280,640 - giving up on it"]
        AssertTrue(MnLogged(m, step), "logged: " step)
    sp := 0, iJump := 0
    for i, e in m.io.log
        if ((!MnFight(m.io) || i < MnFight(m.io)) && e == "down Space" && ++sp = MinionsTask.StuckWalks + 1)
            iJump := i
    AssertEq(sp, MinionsTask.StuckWalks + 1, "a jump in each walk, then the jump forward")
    AssertEq(m.io.log[iJump - 1], "down w", "the jump forward walks forward")
    iA := QmObbyFirst(m.io, "down a"), iD := QmObbyFirst(m.io, "down d")
    AssertTrue(iJump < iA && iA < iD, "jump, then left, then right")
    AssertEq(m.io.log[iA - 1] " " m.io.log[iD - 1], "down w down w", "strafing forward")
    AssertEq(QmObbyDowns(m.io, "a") + QmObbyDowns(m.io, "d"), 2, "one strafe each")
    AssertTrue(QmObbyFirst(m.io, "down Left") > iD, "then turned away to look elsewhere")
    AssertTrue(!MnLogged(m, "only the immune one left"), "not attacked as the last bar")
    AssertTrue(!MnLogged(m, "wall - sliding"), "level: no slide")
}

; L66 04:08 RAINY: each Escape moved the far "bar" (the Bossraid Portal's lit
; steps) on screen, which reset the Escapes: jump, strafe, again for 60 s, no
; cast. Moved but no nearer -> the next Escape, then given up.
Test_Minions_EscapeMovingTheBarAsideStillGivesUp() {
    m := MnTask()
    m.t._scanFn := () => MnTurning(m, [{x: 1280, y: 640, w: 60 - 12 * MnCount(m, "walking got no closer")}])   ; each Escape: a bit farther
    m.t.Run(SchedCtx())
    for step in ["jump forward (1/3)", "strafe left (2/3)", "strafe right (3/3)", "still stuck at"]
        AssertTrue(MnLogged(m, step), "logged: " step)
    AssertTrue(MnCount(m, "jump forward (1/3)") <= 2, "not the first Escape over and over")
}

Test_Minions_Nearer() {
    p := {x: 1280, y: 640, w: 60}
    AssertTrue(!MinionsTask.Nearer({x: 1450, y: 640, w: 60}, p), "aside: no nearer")
    AssertTrue(MinionsTask.Nearer({x: 1280, y: 640, w: 80}, p), "wider: nearer")
    AssertTrue(MinionsTask.Nearer({x: 1280, y: 670, w: 60}, p), "lower: nearer")
    AssertTrue(MinionsTask.Nearer(p, ""), "none before")
}

; ---- the wall slide (clips 2026-11-02: the orbs on a raised terrace next to
; spawn, too high to jump; the way up somewhere along its wall) -----------

; steps on key ("a" / "d") with w held: an Escape's strafe and the slide's
MnSlides(io, key) {
    n := 0, w := false
    for e in io.log {
        if (e == "down w")
            w := true
        else if (e == "up w")
            w := false
        else if (w && e == "down " key)
            n++
    }
    return n
}

MnUps(io, key) {
    n := 0
    for e in io.log
        n += (e = "up " key) ? 1 : 0
    return n
}

; io.log index of the n-th entry equal to e (0 = none)
MnNth(io, e, n) {
    for i, x in io.log
        if (x = e && --n = 0)
            return i
    return 0
}

; a high bar the Escapes got no closer to: a steps along the wall (hops,
; then w too), the bars scanned after each; nearer two looks running
; -> walking again, then the fight; the side kept for the biome
Test_Minions_WallSlideFindsAWayUp() {
    MinionsTask.WallSides := Map()
    m := MnTask()
    m.t.CanRun(m.state)
    high := [{x: 1280, y: 520, w: 60}], up := [{x: 1280, y: 560, w: 66}], near := [{x: 1280, y: 680, w: 200}]
    n := 0                                          ; the strafe left Escape is one "a"
    m.t._scanFn := () => QmObbyDowns(m.io, "a") < 3 ? high : ++n <= 2 ? up : n <= 8 ? near : []
    m.t.Run(SchedCtx())
    for step in ["strafe right (3/3)", "minions: wall - sliding left to find a way up", "wall - nearer, walking in (side a)", "minions: found a way up (side a)"]
        AssertTrue(MnLogged(m, step), "logged: " step)
    AssertTrue(QmObbyDowns(m.io, "a") >= 4 && QmObbyDowns(m.io, "d") >= 1, "the Escapes' strafes, three steps left, dodge steps at the stand: nearer once is no gain")
    iSl := MnNth(m.io, "down a", 2)
    AssertEq(m.io.log[iSl - 1] != "down w", true, "a alone")
    AssertEq(m.io.log[iSl + 1] " " m.io.log[iSl + 3] " " m.io.log[iSl + 5] " " m.io.log[iSl + 7], "down Space down Space down w up a", "two hops, then w too")
    AssertTrue(!MnLogged(m, "still stuck"), "not given up")
    AssertTrue(MnSkills(m.io) >= 1, "then skills on it")
    AssertEq(MinionsTask.WallSides.Get("RAINY", ""), "a", "the side kept for RAINY")
    MinionsTask.WallSides := Map()
}

; the side that worked in this biome before: tried first
Test_Minions_WallSlideTriesTheRememberedSideFirst() {
    MinionsTask.WallSides := Map("RAINY", "d")
    m := MnTask()
    m.t.CanRun(m.state)
    high := [{x: 1280, y: 520, w: 60}], near := [{x: 1280, y: 680, w: 200}]
    n := 0
    m.t._scanFn := () => QmObbyDowns(m.io, "d") < 2 ? high : ++n <= 6 ? near : []
    m.t.Run(SchedCtx())
    AssertTrue(MnLogged(m, "wall - sliding right to find a way up") && !MnLogged(m, "sliding left"), "right first")
    AssertTrue(MnLogged(m, "found a way up (side d)"), "found")
    MinionsTask.WallSides := Map()
}

; never nearer: WallSlideMaxMs one way, twice that the other, that much
; further round after a long step back, walks in, then the target is left
; for AvoidMs as before; every key released
Test_Minions_WallSlideBothWaysThenGivesUp() {
    MinionsTask.WallSides := Map()
    m := MnTask()
    m.t.CanRun(m.state)
    m.t._scanFn := () => MnTurning(m, [{x: 1280, y: 520, w: 60}])
    m.t.Run(SchedCtx())
    one := Ceil(MinionsTask.WallSlideMaxMs / MinionsTask.WallStepMs)
    two := Ceil(2 * MinionsTask.WallSlideMaxMs / MinionsTask.WallStepMs)
    for step in ["wall - sliding left to find a way up", "wall - sliding right to find a way up", "wall - backing off and round", "still stuck at 1280,520 - giving up on it", "no way up at this wall"]
        AssertTrue(MnLogged(m, step), "logged: " step)
    AssertEq(QmObbyDowns(m.io, "a") " " QmObbyDowns(m.io, "d"), (1 + one) " " (1 + two + one), "the Escapes' strafes, then the legs")
    AssertTrue(QmObbyLast(m.io, "down a") < MnNth(m.io, "down d", 2), "left first, then right")
    AssertTrue(QmObbyLast(m.io, "down d") < QmObbyFirst(m.io, "down Left"), "then looked elsewhere")
    AssertTrue(!MnLogged(m, "found a way up"), "none found")
    AssertEq(MinionsTask.WallSides.Count, 0, "no side kept")
    for key in ["w", "a", "d", "s", "Space"]
        AssertEq(QmObbyDowns(m.io, key), MnUps(m.io, key), "every " key " released")
}

; MnIO that stops ctx at the n-th "a" down
class MnStopIO extends MnIO {
    ctx := ""
    n := 0
    Down(k) {
        super.Down(k)
        if (k = "a" && --this.n = 0)
            this.ctx.Stop()
    }
}

; stopped mid-step: the side key is released
Test_Minions_WallSlideStoppedReleasesTheKeys() {
    MinionsTask.WallSides := Map()
    io := MnStopIO(), io.ctx := SchedCtx(), io.n := 3     ; the Escape's strafe, then the 2nd step
    m := MnTask(, , , io)
    m.t._scanFn := () => [{x: 1280, y: 520, w: 60}]
    m.t.Run(io.ctx)
    AssertTrue(MnLogged(m, "wall - sliding left"), "sliding")
    AssertTrue(!Input._held.Has("w") && !Input._held.Has("a"), "nothing held")
    for key in ["w", "a"]
        AssertEq(QmObbyDowns(m.io, key), MnUps(m.io, key), "every " key " released")
    AssertEq(QmObbyDowns(m.io, "a"), 3, "no step after the stop")
}

; a glow (OrbBeacon) behind a terrace wall: along it too, its glow growing
; is the way up
Test_Minions_WallSlideToAGlow() {
    MinionsTask.WallSides := Map()
    m := MnTask()
    m.t.CanRun(m.state)
    m.t._beaconFn := () => QmObbyDowns(m.io, "a") < 3 ? [{x: 1280, y: 500, r: 20}] : [{x: 1280, y: 500 + 2 * MnWalks(m.io), r: 30 + 5 * MnWalks(m.io)}]
    m.t.Run(SchedCtx())
    for step in ["strafe right (3/3)", "wall - sliding left to find a way up", "found a way up (side a)"]
        AssertTrue(MnLogged(m, step), "logged: " step)
    AssertTrue(!MnLogged(m, "still stuck at the glow"), "not given up")
    AssertEq(MinionsTask.WallSides.Get("RAINY", ""), "a", "the side kept")
    MinionsTask.WallSides := Map()
}

; ---- a terrace, simulated (the live failure: L25 22:21:39 WINDY, L23 18:10
; SNOWY): the wall along y = 0, the player on y < 0, the orb D behind it, the
; camera always on the orb (shift lock: w / s along that way, a / d across
; it), stairs through the wall from gapX on. Studs, 16 a second. --------------
class MnTerraceIO extends MnIO {
    px := 0
    py := -1.0
    D := 12.0
    gapX := 20.0                  ; "" = no way up
    gapW := 6.0
    way := -1                     ; left (-1) or right of the wall's foot
    overhead := 0                 ; ms a look at the screen takes
    cam := 0                      ; ms of turn off the orb
    left := false                 ; the wall given up on
    badWalks := 0                 ; walks into the wall's bearing after that
    held := Map()
    Down(k) {
        super.Down(k)
        this.held[StrLower(k)] := true
        if (k = "w" && this.left && Abs(MinionsTask.Wrap(this.cam)) <= MinionsTask.WallOffCone)
            this.badWalks++
    }
    Up(k) {
        super.Up(k)
        if this.held.Has(StrLower(k))
            this.held.Delete(StrLower(k))
    }
    Wait(ms, ctx := "") {
        left := ms
        while (left > 0) {
            d := Min(left, 20), left -= d
            this.Move(d)
        }
        return super.Wait(ms, ctx)
    }
    Move(ms) {
        this.cam += ms * (this.held.Has("right") - this.held.Has("left"))
        dx := -this.px, dy := this.D - this.py, n := Sqrt(dx * dx + dy * dy)
        if (n < 0.5 || MinionsTask.Wrap(this.cam))
            return
        fx := dx / n, fy := dy / n                  ; forward: to the orb
        rx := fy, ry := -fx                         ; right
        f := this.held.Has("w") - this.held.Has("s"), r := this.held.Has("d") - this.held.Has("a")
        if (!f && !r)
            return
        k := 16.0 * ms / 1000 / Sqrt(f * f + r * r)
        nx := this.px + k * (f * fx + r * rx), ny := this.py + k * (f * fy + r * ry)
        if (ny > 0 && this.py <= 2 && !this.InGap(nx))
            ny := Min(this.py, 0)                   ; slides along the wall; on top: free
        this.px := nx, this.py := ny
    }
    InGap(x) => this.gapX != "" && x * this.way >= this.gapX && x * this.way <= this.gapX + this.gapW
    Dist() => Sqrt(this.px ** 2 + (this.D - this.py) ** 2)
    ; the orb's bar from here (hand fights: 160 px beside it), lower as it nears
    Bars() {
        this.t += this.overhead
        d := this.Dist()
        x := 1280 - Round(MinionsTask.Wrap(this.cam) * MinionsTask.TurnPxPerMs)
        return (x < MinionsTask.Area.x1 || x > MinionsTask.Area.x2) ? [] : [{x: x, y: Round(600 - 8 * d), w: Round(800 / Max(d, 1))}]
    }
}

MnTerrace(io) {
    MinionsTask.WallSides := Map()
    m := MnTask(, , , io)
    m.t.CanRun(m.state)
    m.t._scanFn := () => io.Bars()
    return m
}

; stairs 20 studs along, the orb 12 behind the wall (w + a stood still 12
; along, past the way up's reach): found, the orb reached, skills on it
Test_Minions_TerraceStairsOnTheLeftAreClimbed() {
    MnTerraceClimb(-1)
}

; ... on the right: left first, back past the start
Test_Minions_TerraceStairsOnTheRightAreClimbed() {
    MnTerraceClimb(1)
}

MnTerraceClimb(way) {
    io := MnTerraceIO(), io.way := way
    m := MnTerrace(io)
    m.t.Run(SchedCtx())
    AssertTrue(MnLogged(m, "wall - sliding left"), "along the wall")
    AssertTrue(MnLogged(m, "wall - nearer, walking in"), "the way in seen")
    AssertTrue(MnLogged(m, "found a way up (side " (way < 0 ? "a" : "d") ")"), "the orb reached")
    AssertTrue(MnSkills(m.io) >= 1, "skills on it")
    AssertTrue(!MnLogged(m, "still stuck"), "not given up")
    MinionsTask.WallSides := Map()
}

; the old way along the same wall stands still at D (the reason for a / d
; alone): w + a held 12 s gets no further than D + a stud
Test_Minions_TerraceSimWPlusAStandsStillAtD() {
    io := MnTerraceIO()
    io.gapX := ""
    io.Down("w"), io.Down("a")
    io.Wait(12000)
    AssertTrue(Abs(io.px) <= io.D + 1, "w + a stalls at D: " io.px)
    io := MnTerraceIO()
    io.gapX := ""
    io.Down("a")
    io.Wait(7000)
    AssertTrue(Abs(io.px) >= 25, "a alone passes the stairs' 25 studs: " io.px)
}

; no way up, a look costing 250 ms: the wall gets WallMaxMs (the Escapes
; before it and a last walk in over that: 45 s here), then the patrol
; walks on, half a turn away, the wall's bearing left alone
Test_Minions_TerraceWithNoWayUpIsLeftForThePatrol() {
    io := MnTerraceIO(), io.gapX := "", io.overhead := 250
    m := MnTask(, Map("Minions.patrol", 1), , io)
    MinionsTask.WallSides := Map()
    m.t.CanRun(m.state)
    t0 := 0, t1 := 0
    look() {
        if (!t0 && MnLogged(m, "walking got no closer"))
            t0 := io.t
        if (!t1 && MnLogged(m, "no way up at this wall"))
            t1 := io.t, io.left := true
        return io.Bars()
    }
    m.t._scanFn := look
    m.t.Run(SchedCtx())
    AssertTrue(t1 > 0, "left")
    AssertTrue(t1 - t0 <= 46000, "about 40 s at the wall, a walk in that gets nearer not cut: " (t1 - t0))
    AssertTrue(MnLogged(m, "walking the map") || QmObbyDowns(m.io, "w") > 0, "walking on")
    AssertEq(io.badWalks, 0, "no walk back at the wall's bearing")
    AssertEq(MnCount(m, "still stuck"), 1, "not back at it")
    AssertTrue(MnLogged(m, "walking got no closer"), "the Escapes first")
    AssertEq(MnBelowLogs(m), 0, "out of reach: no stand")
    AssertEq(MnSkills(m.io), 0, "no cast at nothing")
    AssertEq(MnCount(m, "wall - sliding left"), 1, "the wall not started over")
}

MnBelowLogs(m) => MnCount(m, "in reach from below")

MnCount(m, s) {
    n := 0
    for l in m.logs
        n += InStr(l, s) ? 1 : 0
    return n
}

; a minion in reach above the wall (the Locked orb alone is no reason: review
; 0809 #8): a stand from below before the search, BelowStands at most with
; nothing hurt, then along the wall on
Test_Minions_BelowTheOrbStandsThenSearchesOn() {
    MinionsTask.WallSides := Map()
    m := MnTask()
    m.t.CanRun(m.state)
    m.t._scanFn := () => MnTurning(m, [{x: 1280, y: 520, w: 170}, {x: 1380, y: 560, w: 110}])
    m.t.Run(SchedCtx())
    AssertEq(MnBelowLogs(m), MinionsTask.BelowStands, "the stands")
    AssertTrue(MnSkills(m.io) >= MinionsTask.BelowStands, "cast from below: " MnSkills(m.io))
    AssertTrue(MnLogged(m, "wall - sliding right"), "then the search went on")
    AssertTrue(!MnLogged(m, "found a way up"), "a stand is no way up")
    AssertEq(MinionsTask.WallSides.Count, 0, "no side kept")
}

; ... a bar hurt: the casts land, standing on
Test_Minions_BelowTheOrbStandsOnWhileABarIsHurt() {
    MinionsTask.WallSides := Map()
    m := MnTask()
    m.t.CanRun(m.state)
    m.t._scanFn := () => [{x: 1280, y: 520, w: 170}, {x: 1380, y: 560, w: 110, fill: 0.7}]
    m.t.Run(SchedCtx())
    AssertTrue(MnBelowLogs(m) > MinionsTask.BelowStands, "stood on: " MnBelowLogs(m))
    AssertTrue(!MnLogged(m, "wall - sliding right"), "no search away from a fight that works")
}

; a minion come down beside the player mid-search: fought, no way up kept,
; and the search goes on where it was, not from the Escapes
Test_Minions_WallSearchGoesOnAfterAMinionStand() {
    MinionsTask.WallSides := Map()
    m := MnTask()
    m.t.CanRun(m.state)
    ; the minion in reach (AimMinionW) from its second read (the first is
    ; unconfirmed: the Locked orb alone, no stand for it, review 0809 #8)
    high := [{x: 1280, y: 520, w: 60}], mob := [{x: 1280, y: 520, w: 150}, {x: 1100, y: 640, w: 110}]
    n := 0
    m.t._scanFn := () => QmObbyDowns(m.io, "a") >= 4 && ++n <= 3 ? mob : high
    m.t.Run(SchedCtx())
    AssertTrue(MnSkills(m.io) >= 1, "a cast at the minion")
    AssertTrue(!MnLogged(m, "found a way up"), "no way up")
    jumps := 0, slides := 0
    for l in m.logs {
        if InStr(l, "still stuck")
            break
        jumps += InStr(l, "jump forward") ? 1 : 0, slides += InStr(l, "wall - sliding left") ? 1 : 0
    }
    AssertEq(jumps " " slides, "1 1", "no Escapes again, the search not started over")
    AssertEq(MinionsTask.WallSides.Count, 0, "no side kept")
}

; the target out of sight along the wall (overhead, a ledge): steps on, then
; dropped
Test_Minions_WallStepsOnWithTheBarLost() {
    MinionsTask.WallSides := Map()
    m := MnTask()
    m.t.CanRun(m.state)
    high := [{x: 1280, y: 520, w: 60}]
    n := 0
    m.t._scanFn := () => QmObbyDowns(m.io, "a") >= 3 ? [] : high
    m.t.Run(SchedCtx())
    n := 0
    for i, e in m.io.log
        if (i < QmObbyFirst(m.io, "down Left") && e == "down a")
            n++
    AssertEq(n, 3 + MinionsTask.WallBlindSteps, "a few steps blind, then none")
}

; a step with the view unchanged (a block in the way): the next is s + a
Test_Minions_WallStepPeelsOffABlock() {
    MinionsTask.WallSides := Map()
    m := MnTask()
    m.t.CanRun(m.state)
    m.t._scanFn := () => MnTurning(m, [{x: 1280, y: 520, w: 60}])
    m.t._viewFn := () => {edge: false, sig: [1, 2, 3, 4]}
    m.t.Run(SchedCtx())
    iA := MnNth(m.io, "down a", 3)                  ; after the Escape and the first step
    AssertEq(m.io.log[iA - 1], "down s", "s + a")
    AssertTrue(MnNth(m.io, "down a", 4) > iA, "then the next step")
    AssertEq(m.io.log[MnNth(m.io, "down a", 4) - 1] != "down s", true, "a alone again")
}

; the island's edge beside the wall: no half turn off the target, the next leg
Test_Minions_WallLegEndsAtTheIslandsEdge() {
    MinionsTask.WallSides := Map()
    m := MnTask()
    m.t.CanRun(m.state)
    m.t._scanFn := () => MnTurning(m, [{x: 1280, y: 520, w: 60}])
    sig := 0
    m.t._viewFn := () => {edge: QmObbyDowns(m.io, "a") = 3 && QmObbyDowns(m.io, "d") < 2, sig: [++sig]}
    m.t.Run(SchedCtx())
    AssertTrue(MnLogged(m, "wall - the island's edge"), "seen")
    AssertEq(QmObbyDowns(m.io, "a"), 3, "no further left")
    AssertTrue(MnLogged(m, "wall - sliding right"), "the other way")
}

; the wall left alone: its bearing, its bars, a near one kept
Test_Minions_OffWallDropsBarsAtThatBearing() {
    o := {b: 100}
    px := Round(50 * MinionsTask.TurnPxPerMs)
    AssertTrue(MinionsTask.OnWall(o, 100 + MinionsTask.WallOffCone) && !MinionsTask.OnWall(o, 101 + MinionsTask.WallOffCone), "the cone")
    AssertTrue(MinionsTask.OnWall({b: 0}, MinionsTask.FullTurnMs + 10), "whole circles count for nothing")
    bars := [{x: 1280 + px, y: 200, w: 60}, {x: 1280, y: 500, w: 130}, {x: 2200, y: 200, w: 60}]
    r := MinionsTask.OffWall(bars, o, 300)
    AssertEq(r.Length, 2, "the far one at that bearing gone")
    AssertEq(r[1].w " " r[2].x, "130 2200", "a near one and one off the cone kept")
    AssertEq(MinionsTask.OffWall([{x: 1280, y: 200, r: 30}], o, 100).Length, 0, "a glow as well")
}

; below a wall: the bars that are in reach, and those that show casts landing
Test_Minions_InReachAndHurt() {
    orb := {x: 1000, y: 300, w: 120}, far := {x: 900, y: 320, w: 40}
    AssertTrue(MinionsTask.InReach({orb: {x: 1000, y: 300, w: 150}, minions: [], anchor: orb}), "the orb alone, almost beside")
    AssertTrue(!MinionsTask.InReach({orb: {x: 1000, y: 300, w: 150}, minions: [far], anchor: orb}), "minions far: not yet")
    AssertTrue(!MinionsTask.InReach({orb: {x: 1, y: 2, w: 100}, minions: [far], anchor: far}), "the orb too far")
    AssertTrue(MinionsTask.InReach({orb: {x: 1, y: 2, w: 100}, minions: [{x: 1, y: 600, w: 110}], anchor: far}), "a minion faced first")
    AssertTrue(MinionsTask.Hurt({orb: "", minions: [{w: 80, fill: 0.8}]}), "a minion hurt")
    AssertTrue(!MinionsTask.Hurt({orb: {w: 150, fill: 0.3}, minions: [{w: 80, fill: 1}]}), "an orb's fill with minions up reads nothing")
    AssertTrue(MinionsTask.Hurt({orb: {w: 150, fill: 0.5}, minions: []}), "the orb, no minion left")
}

; the jump got it closer: walking again, no strafes
Test_Minions_StuckWalkFreedByAJump() {
    wall := [{x: 1280, y: 520, w: 60}], up := [{x: 1280, y: 590, w: 60}], near := [{x: 1280, y: 680, w: 200}]
    m := MnTask([wall, wall, wall, wall, wall, up, near, near, near, []])
    m.t.Run(SchedCtx())
    AssertTrue(MnLogged(m, "jump forward (1/3)") && !MnLogged(m, "strafe left"), "one jump was enough")
    AssertTrue(MnSkills(m.io) >= 1, "then skills on it")
}

; ---- the orb's glow (OrbBeacon; live 2026-11-02: orbs glow from spawn while
; their bars are too small to read, and the hunt turned in circles) ---------

; walks (MnIO: a w press goes on over many)
MnWalks(io) => io.walks

Test_Minions_WalksToAFarOrbGlow() {
    m := MnTask()
    near := [{x: 1280, y: 680, w: 200}]
    ; no bar until 3 walks; the glow right of centre, then centred and
    ; growing with every walk
    m.t._scanFn := () => MnWalks(m.io) >= 3 ? near : []
    m.t._beaconFn := () => QmObbyDowns(m.io, "Right") ? [{x: 1290, y: 700 + 10 * MnWalks(m.io), r: 20 + 6 * MnWalks(m.io)}] : [{x: 1700, y: 700, r: 20}]
    m.t.Run(SchedCtx())
    AssertTrue(MnLogged(m, "minions: orb glow at 1700,700 (20) - walking to it"), "the glow logged")
    iR := QmObbyFirst(m.io, "down Right"), iW := QmObbyFirst(m.io, "down w"), iT := QmObbyFirst(m.io, "down t")
    AssertTrue(iR > 0 && iR < iW && iW < iT, "turned to the glow, walked to it, then skills on the bar")
    AssertEq(MnDowns(m.io, "Left", iT), 0, "no look-around before the fight")
    AssertEq(QmObbyDowns(m.io, "Right"), 1, "one turn to centre it")
}

; a glow the walks get no closer to (a wall): the Escapes, then it is left
; for AvoidMs and the hunt looks elsewhere
Test_Minions_GlowBehindAWallIsLeftAlone() {
    m := MnTask()
    m.t._beaconFn := () => (g := MnTurning(m, [{x: 1280, y: 700, w: 20}])).Length ? [{x: g[1].x, y: g[1].y, r: g[1].w}] : []
    m.t.Run(SchedCtx())
    for step in ["got no closer - jump forward (1/3)", "strafe right (3/3)", "still stuck at the glow 1280,700 - giving up on it"]
        AssertTrue(MnLogged(m, step), "logged: " step)
    AssertTrue(QmObbyDowns(m.io, "Left") >= 1, "then looked elsewhere")
    AssertEq(MnSkills(m.io), 0, "nothing to hit")
}

; a glow counts as seen: no give up while one is in sight
Test_Minions_GlowKeepsTheHuntGoing() {
    m := MnTask()
    m.t.CanRun(m.state)
    ; a glow that comes closer with every walk, never a bar
    m.t._beaconFn := () => [{x: 1280, y: 600 + 2 * MnWalks(m.io), r: 10 + 5 * MnWalks(m.io)}]
    m.t.Run(SchedCtx())
    AssertTrue(!MnLogged(m, "giving up"), "never gave up")
    AssertTrue(MnWalks(m.io) >= 10, "kept walking to it")
}

; ---- the bearing (net turn ms since the last respawn; the camera faces one
; way after ResetToSpawn): players die near the orb and the hunt forgot
; where the fight was ---------------------------------------------------

; MnIO that also keeps every camera turn: turns = ["Left 250", ...]
class MnTurnIO extends MnIO {
    turns := []
    Wait(ms, ctx := "") {
        if (this.log.Length && RegExMatch(this.log[-1], "^down (Left|Right)$", &k))
            this.turns.Push(k[1] " " ms)
        return super.Wait(ms, ctx)
    }
}

MnHas(a, v) {
    for x in a
        if (x = v)
            return A_Index
    return 0
}

Test_Minions_BearingLoggedWhenATargetIsFirstSeen() {
    m := MnTask()
    near := [{x: 1280, y: 680, w: 200}]
    m.t._scanFn := () => QmObbyDowns(m.io, "Left") >= 2 ? near : []
    m.t.Run(SchedCtx())
    AssertTrue(MnLogged(m, "minions: target at 1280,680 (bar 200 px) - bearing " (-2 * MinionsTask.ScanTurnMs) " ms"), "two Left turns: the bearing")
    m := MnTask()
    m.t._beaconFn := () => QmObbyDowns(m.io, "Right") ? [] : [{x: 1700, y: 700, r: 20}]
    m.t.Run(SchedCtx())
    AssertTrue(MnLogged(m, "orb glow at 1700,700 (20) - walking to it (bearing 0 ms)"), "the glow's bearing")
}

Test_Minions_Wrap() {
    c := MinionsTask.FullTurnMs
    AssertEq(MinionsTask.Wrap(0), 0, "none")
    AssertEq(MinionsTask.Wrap(-500), -500, "under half a circle: kept")
    AssertEq(MinionsTask.Wrap(2 * c + 500), 500, "whole circles dropped")
    AssertEq(MinionsTask.Wrap(c - 100), -100, "over half a circle: the other way")
    AssertEq(MinionsTask.Wrap(-c + 100), 100, "over half a circle left: right")
    AssertEq(MinionsTask.Wrap(c // 2), c // 2, "half: right")
    AssertEq(MinionsTask.Wrap(-(c // 2)), c // 2, "half left: right")
}

; a long hunt's bearing is many circles: the turn back is the short way
; round, in TurnMaxMs steps with a stop check between (review 2026-11-02:
; one blocking Right hold of 3 s and more)
Test_Minions_TurnBackInShortSteps() {
    m := MnTask(, , , MnTurnIO())
    m.t._bearing := -7 * MinionsTask.FullTurnMs - 300
    m.t._TurnBy(SchedCtx(), 7 * MinionsTask.FullTurnMs + 300)
    AssertEq(m.t._bearing, -7 * MinionsTask.FullTurnMs, "300 ms right: the same way as the fight")
    AssertEq(m.io.turns.Length, 2, "300 ms: two steps")
    for t in m.io.turns
        AssertTrue(StrSplit(t, " ")[2] <= MinionsTask.TurnMaxMs, "a step no longer than TurnMaxMs: " t)
    m := MnTask(, , , MnTurnIO())
    m.t._TurnBy({ShouldStop: (*) => m.io.turns.Length >= 1}, 600)
    AssertEq(m.io.turns.Length, 1, "stopped between steps")
    ctx := SchedCtx()
    ctx.Stop()
    m.t._TurnBy(ctx, 600)
    AssertEq(m.io.turns.Length, 1, "stopped: no turn")
    ; 1400 ms is under half a true circle: all of it, that way (on a circle of
    ; 1250 it was 150 ms: a fight 168 degrees off stayed 150 off)
    for d in [1400, -1400] {
        m := MnTask(, , , MnTurnIO()), sum := 0
        m.t._TurnBy(SchedCtx(), d)
        AssertEq(m.t._bearing, d, "the whole turn")
        for x in m.io.turns {
            p := StrSplit(x, " "), sum += Integer(p[2])
            AssertEq(p[1], d > 0 ? "Right" : "Left", "one way")
        }
        AssertEq(sum, Abs(d), "held as long")
    }
    m := MnTask(, , , MnTurnIO())
    m.t._TurnBy(SchedCtx(), 1700)
    AssertEq(m.t._bearing, -1300, "over half a circle: the other way")
}

Test_Minions_GlowTurn() {
    c := MinionsTask.CenterX, t := MinionsTask.GlowAimTol
    ar := MinionsTask.GlowAim(1), al := MinionsTask.GlowAim(-1)
    pw := OrbBeacon.PlayerWhite, pl := OrbBeacon.Player
    AssertEq(ar " " al, (pw.x2 - c + MinionsTask.GlowClear) " " (c - pw.x1 + MinionsTask.GlowClear), "aimed GlowClear outside the character's white box, each side")
    AssertEq(MinionsTask.GlowTurn(c).ms, 0, "ahead (seen above the character): aimed")
    AssertEq(MinionsTask.GlowTurn(c + ar + t).ms, 0, "at the band's edge: aimed")
    AssertEq(MinionsTask.GlowTurn(c - al - t).ms, 0, "left too")
    g := MinionsTask.GlowTurn(1950)                     ; SAND STORM 20:49
    AssertEq(g.key, "Right", "right of centre: Right")
    AssertEq(g.ms, Round((1950 - c - ar) / MinionsTask.TurnPxPerMs), "to its side of the centre, not to it")
    x := 1950 + MinionsTask.Shift(g.key, g.ms)
    AssertTrue(x > pw.x2 + 100 && x > pl.x2, "lands clear right of the character's boxes (the turn may go ~130 px over)")
    g := MinionsTask.GlowTurn(560)
    AssertEq(g.key, "Left", "left of centre: Left")
    x := 560 + MinionsTask.Shift(g.key, g.ms)
    AssertTrue(x < pw.x1 - 100 && x < pl.x1, "lands clear left of the character's boxes")
    ; loop L19: aimed at 1020 / 1540 the glow was never seen again (1020
    ; inside PlayerWhite; the SNOWY orb at ~1410 after a turn to 1541)
    AssertTrue(MinionsTask.GlowTurn(1020).ms = 0 && MinionsTask.GlowTurn(1820).ms > 0, "1820 is turned to, not left at 1540")
    AssertEq(MinionsTask.GlowTurn(2500).ms, MinionsTask.TurnMaxMs, "capped")
    x := c + ar + t + 10, g := MinionsTask.GlowTurn(x)
    AssertTrue(g.ms > 0 && MinionsTask.GlowTurn(x + MinionsTask.Shift(g.key, g.ms)).ms = 0, "just outside: one nudge aims it")
}

Test_Minions_GlowLostAfterATurnGoesFurtherOut() {
    g := MinionsTask.GlowLost(1540)
    AssertEq(g.key, "Left", "lost right of centre: Left (the screen moves right, out from behind the character)")
    AssertTrue(MinionsTask.Shift(g.key, g.ms) >= MinionsTask.GlowClear - 5, "about GlowClear px out")
    AssertEq(MinionsTask.GlowLost(810).key, "Right", "left of centre: Right")
}

; live 2026-11-02 SAND STORM 20:49-20:51: a glow at ~1950,716 centred was
; behind the character (OrbBeacon.Player drops it), lost, a look-around
; turn found it at ~1950 again: 100 s of turns, never a walk. Now aimed to
; its side and walked to, the glow logged once.
Test_Minions_GlowRightOfCentreIsWalkedTo() {
    m := MnTask()
    near := [{x: 1280, y: 680, w: 200}]
    m.t._scanFn := () => MnWalks(m.io) >= 6 ? near : []
    ; the glow where the camera puts it (bearing: px per ms of turn),
    ; hidden in the character box, closer with every walk
    pl := OrbBeacon.Player
    m.t._beaconFn := () => ((x := 1950 - Round(m.t._bearing * MinionsTask.TurnPxPerMs)) >= pl.x1 && x <= pl.x2)
        ? [] : [{x: x, y: 716 + 2 * MnWalks(m.io), r: 70 + 6 * MnWalks(m.io)}]
    m.t.Run(SchedCtx())
    n := 0
    for l in m.logs
        n += InStr(l, "orb glow at") ? 1 : 0
    AssertEq(n, 1, "the glow logged once (live: ~25 times)")
    iT := QmObbyFirst(m.io, "down t")
    AssertTrue(iT > 0, "reached the fight")
    AssertEq(MnDowns(m.io, "Left", iT), 0, "no look-around on the way")
    AssertEq(MnDowns(m.io, "Right", iT), 1, "one turn to aim it")
}

; the glow gone from sight right after the turn to it (behind the
; character, fog): walked on at its last spot, no look-around
Test_Minions_GlowOutOfSightIsWalkedOn() {
    m := MnTask()
    near := [{x: 1280, y: 680, w: 200}]
    m.t._scanFn := () => MnWalks(m.io) >= MinionsTask.GlowLostLooks - 1 ? near : []
    m.t._beaconFn := () => QmObbyDowns(m.io, "Right") ? [] : [{x: 1950, y: 716, r: 70}]
    m.t.Run(SchedCtx())
    g := MinionsTask.GlowTurn(1950)
    ; lost right after the turn to it (loop L19: hidden by the character,
    ; the turn went too far): once a bit further out, then walked on
    AssertTrue(MnLogged(m, "glow out of sight at " (1950 + MinionsTask.Shift("Right", g.ms)) ",716 - turning a bit further out"), "logged")
    iT := QmObbyFirst(m.io, "down t")
    AssertTrue(iT > 0, "reached the fight")
    AssertEq(MnDowns(m.io, "Left", iT), 1, "one nudge out (Left: the glow was right), no look-around on the way")
    ; never found again: the nudge, GlowLostLooks - 1 walks, then the look-around
    m := MnTask()
    m.t._beaconFn := () => QmObbyDowns(m.io, "Right") ? [] : [{x: 1950, y: 716, r: 70}]
    m.t.Run(SchedCtx())
    i1 := QmObbyFirst(m.io, "down Left"), i2 := 0, n := 0
    for i, e in m.io.log
        if (e = "down Left" && ++n = 2) {
            i2 := i
            break
        }
    w := 0                                       ; a walk's jump: w stays down between walks
    for i, e in m.io.log
        w += (i > i1 && i < i2 && e == "down Space") ? 1 : 0
    AssertEq(w, MinionsTask.GlowLostLooks - 1, "the rest of GlowLostLooks walks on, then looked around")
}

; live 2026-11-02 WINDY 20:23:42 / SNOWY 20:55:02: a far bar seen ~2 s,
; lost on the walk, read as a death (4 quick scans) and the bearing thrown
; away. Now no death: the bearing kept for the walk back.
Test_Minions_FarBarLostIsNoDeath() {
    m := MnTask()
    far := [{x: 1280, y: 638, w: 28}]
    m.t._scanFn := () => (QmObbyDowns(m.io, "Left") >= 2 && MnWalks(m.io) < 1) ? far : []
    m.t.Run(SchedCtx())
    AssertTrue(MnLogged(m, "target at 1280,638 (bar 28 px) - bearing -1000 ms"), "seen")
    AssertTrue(!MnLogged(m, "died?"), "no death")
    AssertTrue(MnLogged(m, "back to the fight - turning to bearing -1000 ms"), "the bearing kept")
}

; the target's bar lost off its aimed spot (seen once more at 1460, then
; gone): looked for in place, then a turn back to that spot
Test_Minions_LostBarTurnsBackToItsSpot() {
    far := [{x: 1280, y: 600, w: 30}]
    m := MnTask([far, far, [], [{x: 1460, y: 600, w: 30}], []])
    m.t.Run(SchedCtx())
    AssertTrue(MnLogged(m, "target lost at 1460,600 - turning back to it"), "logged")
    iR := QmObbyFirst(m.io, "down Right"), iL := QmObbyFirst(m.io, "down Left")
    AssertTrue(iR > 0 && (!iL || iR < iL), "the turn back before any look-around")
    AssertTrue(!MnLogged(m, "died?"), "no death")
}

Test_Minions_GlowSame() {
    a := {x: 1280, y: 700, r: 20}
    AssertTrue(MinionsTask.GlowSame({x: 1300, y: 704, r: 22}, a), "about the same: no closer")
    AssertTrue(!MinionsTask.GlowSame({x: 1280, y: 716, r: 20}, a), "lower: closer")
    AssertTrue(!MinionsTask.GlowSame({x: 1280, y: 700, r: 28}, a), "bigger: closer")
    AssertTrue(!MinionsTask.GlowSame(a, ""), "no glow before")
}

; downs of key before log entry upTo (0 = all)
MnDowns(io, key, upTo := 0) {
    n := 0
    for i, e in io.log
        if (!upTo || i < upTo)
            n += (e = "down " key) ? 1 : 0
    return n
}

; live 2026-11-02: skills fire the way the CHARACTER faces, and it faces
; the camera only after moving forward (a kiting step turned it aside):
; without shift lock a short w tap right before every skill
Test_Minions_AimTapBeforeEverySkill() {
    near := [{x: 1280, y: 680, w: 200}]
    m := MnTask([near, near, near, near, near, []])
    m.t.Run(SchedCtx())
    n := 0, i0 := QmObbyFirst(m.io, "down r")    ; the hunt: after the respawn
    for i, e in m.io.log
        if (i > i0 && RegExMatch(e, "^down [tfeqv]$")) {
            n++
            AssertEq(m.io.log[i - 2] " / " m.io.log[i - 1], "down w / up w", "a w tap right before " e)
        }
    AssertTrue(n >= 3, "skills pressed")
    AssertTrue(MinionsTask.AimTapMs > 0 && MinionsTask.AimTapMs <= 120, "a tap, not a walk")
    m := MnTask([near, near, near, []])           ; Deadeye at rank V
    m.t._hudFn := () => MnHud(Map("r", QmObbyDowns(m.io, "r") >= 2 ? 0.9 : 0), 60, "V")
    m.t.Run(SchedCtx())
    r := 0
    for i, e in m.io.log
        if (e == "down r" && ++r = 2)
            AssertEq(m.io.log[i - 2] " / " m.io.log[i - 1], "down w / up w", "a w tap before Deadeye's hold")
    AssertEq(r, 3, "Deadeye once (and the two respawns)")
}

; loop L19 06:03:22: a 46 px bar at 1770,700 was attacked from afar (y 650
; or lower was near) -> turned to and walked to, no skill until it is wide
Test_Minions_FarLowBarIsWalkedToNotHit() {
    m := MnTask()
    m.t._scanFn := () => [{x: 1280, y: 700, w: 46}]
    m.t.Run(SchedCtx())
    AssertEq(MnSkills(m.io), 0, "no skill from afar")
    AssertTrue(MnWalks(m.io) >= 3, "walked to it")
}

Test_Minions_StoppedHuntDoesNotCount() {
    m := MnTask([[]])
    m.t.CanRun(m.state)
    ctx := SchedCtx()
    ctx.Stop()
    m.t.Run(ctx)
    AssertEq(m.t.CanRun(m.state), true, "F3 mid-hunt: the same biome is hunted again on the next Start")
}

Test_Minions_SameBiomeAgainAfterRehuntMs() {
    m := MnTask([[]])
    m.t.CanRun(m.state)
    m.t.Run(SchedCtx())
    AssertEq(m.t.CanRun(m.state), false, "just hunted")
    m.io.t += MinionsTask.RehuntMs
    AssertEq(m.t.CanRun(m.state), true, "the same long biome, RehuntMs later")
}

Test_Minions_WrongAuraOnMeansNoHunt() {
    m := MnTask([[{x: 1280, y: 680, w: 200}]], Map("Minions.putBack", 1))
    calls := 0
    m.t._swap._auraFn := () => {known: true, name: (calls++ = 0) ? "Glock" : "Luminosity"}
    AssertEq(m.t.Run(SchedCtx()), 0, "Luminosity went on, not Eden")
    AssertEq(QmObbyDowns(m.io, "t"), 0, "no skill pressed")
    AssertEq(m.wh.Count("errors"), 1, "reported")
    AssertEq(m.s.State().eq, "Glock", "Glock put back")
}

; put back off (the default, the user 2026-11-02: "you dont have to equip
; pumpkinity after the hunt"): the combat aura stays on, still a respawn after
Test_Minions_PutBackOffKeepsTheCombatAuraOn() {
    near := [{x: 1280, y: 680, w: 200}]
    m := MnTask([near, near, []])
    m.t.Run(SchedCtx())
    AssertEq(m.s.State().eq, "Eden", "Eden stays on")
    AssertEq(QmObbyDowns(m.io, "r"), 2, "respawned before and after the hunt")
    AssertTrue(QmObbyLast(m.io, "down r") > QmObbyLast(m.io, "down t"), "the respawn after the skills")
    AssertEq(m.wh.Count("errors"), 0, "no error")
}

; 2026-11-02 live: every hunt reopened the storage to check, ~15 s. The
; log naming the combat aura (put back off) skips the storage.
Test_Minions_CombatAuraAlreadyOnSkipsTheStorage() {
    m := MnTask([[]])
    m.s.logName := "Eden"
    m.t.Run(SchedCtx())
    AssertEq(QmObbyFirst(m.io, "type E"), 0, "no storage search")
    AssertEq(m.s.State().eq, "Glock", "the storage untouched")
    AssertTrue(MnLogged(m, "minions: Eden already on"), "logged")
    AssertTrue(QmObbyFirst(m.io, "down Left") > 0, "the hunt ran")
    m2 := MnTask([[]], Map("Minions.putBack", 1))
    m2.s.logName := "Eden"
    m2.t.Run(SchedCtx())
    AssertTrue(!MnLogged(m2, "already on"), "put back on: the checked swap as before")
}

; 2026-11-09 21:24: no aura on, Roblox's log still named Eden (it keeps the
; last one): the swap was skipped and the hunt had no skills. No skill
; panel on screen -> equipped after all
Test_Minions_LogSaysEdenButNoPanelEquips() {
    m := MnTask([[]])
    m.s.logName := "Eden"
    m.t._hudFn := ""                            ; the screen read: a world frame, no panel
    m.t._grab := MatchFileGrab(A_ScriptDir "\screens\world_day.jpg")
    AssertTrue(!m.t._PanelShows(), "no panel in the world frame")
    m.t.Run(SchedCtx())
    AssertTrue(MnLogged(m, "no skill panel is on screen"), "logged")
    AssertTrue(!MnLogged(m, "Eden already on"), "not taken as on")
    AssertTrue(QmObbyFirst(m.io, "type E") > 0, "the storage searched for Eden")
    ; Eden's real panel (crop at 2016,1005): on, skipped as before
    m2 := MnTask([[]])
    m2.s.logName := "Eden"
    m2.t._hudFn := ""
    m2.t._grab := MnShifted(MatchFileGrab(A_ScriptDir "\screens\eden_panel_cd_t.png"), 2016, 1005)
    AssertTrue(m2.t._PanelShows(), "Eden's panel read")
}

; grab of a crop that sits at ox, oy on the screen, read in screen coords
MnShifted(g, ox, oy) {
    return (x1, x2, ys, stride := 1) => g(x1 - ox, x2 - ox, MnShiftYs(ys, oy), stride)
}
MnShiftYs(ys, oy) {
    out := []
    for y in ys
        out.Push(y - oy)
    return out
}

Test_Minions_StorageLeftOpenIsClosedBeforeTheHunt() {
    ; live 2026-11-02 23:31: Eden already on, the storage still open from
    ; the swap before: the hunt ran blind under it
    m := MnTask([[]])
    m.s.logName := "Eden", m.s.openAtStart := true
    m.t.Run(SchedCtx())
    AssertTrue(MnLogged(m, "storage screen is over the game"), "seen")
    AssertTrue(!m.s.State().open, "closed")
    iClose := QmObbyFirst(m.io, "move 400,400")
    AssertTrue(iClose > 0 && iClose < QmObbyFirst(m.io, "down Left"), "closed before the hunt")
    AssertEq(QmClicksAt(m.io, "300,300"), 0, "nothing inside the storage clicked")
}

Test_Minions_StorageThatOpensMidHuntIsClosedWithShiftLockOff() {
    old := MinionsTask.ViewCheckMs
    MinionsTask.ViewCheckMs := 0
    try {
        near := [{x: 1280, y: 680, w: 200}]
        m := MnTask(, , , MnLockIO())
        m.s.logName := "Eden"
        n := 0
        m.t._scanFn := () => (++n = 2 ? (m.s.openAtStart := true) : 0, n <= 3 ? near : [])
        m.t.Run(SchedCtx())
        AssertTrue(MnLogged(m, "storage screen is over the game"), "seen mid-hunt")
        AssertTrue(!m.s.State().open, "closed")
        AssertEq(m.io.locked, 0, "no click while shift lock was on")
        AssertEq(MnEvents(m.io, "{sc02A up}"), 4, "on, off to close it, on, off")
        AssertTrue(!m.io.lock, "off at the end")
    } finally {
        MinionsTask.ViewCheckMs := old
    }
}

Test_Minions_DailyRewardsClosedWithShiftLockOffAndNeverClaimed() {
    old := MinionsTask.ViewCheckMs
    MinionsTask.ViewCheckMs := 0
    try {
        near := [{x: 1280, y: 680, w: 200}]
        m := MnTask(, , , MnLockIO())
        m.s.logName := "Eden"
        n := 0
        m.t._scanFn := () => (++n = 2 ? (m.s.daily := true) : 0, n <= 3 ? near : [])
        m.t.Run(SchedCtx())
        AssertTrue(MnLogged(m, "daily rewards screen is over the game"), "seen mid-hunt")
        AssertTrue(!m.s.State().daily, "closed")
        AssertEq(m.io.locked, 0, "no click while shift lock was on")
        AssertEq(QmClicksAt(m.io, "1280,895"), 0, "its Claim never pressed")
        AssertTrue(!m.io.lock, "off at the end")
    } finally {
        MinionsTask.ViewCheckMs := old
    }
}

Test_Minions_DailyRewardsXNotClickedWhileShiftLockIsOn() {
    ocr := (x, y, w, h) => (x = Input.DailyBox.x) ? "noily Rewords" : ""
    io := MnLockIO()
    io.lock := true, io.works := false
    AssertEq(Input.CloseDaily(SchedCtx(), io, ocr), 2, "stuck on: refused")
    AssertEq(io.Clicks(), 0, "no click")
    AssertTrue(!io.Moved(Input.DailyX[1], Input.DailyX[2]), "not even a move to the X")
    io.works := true
    AssertEq(Input.CloseDaily(SchedCtx(), io, ocr), 2, "turned off, title stays: given up")
    AssertTrue(!io.lock, "the guard turned it off")
    AssertEq(io.locked, 0, "no click while on")
    AssertEq(io.Clicks(), Input.DailyTries, "DailyTries clicks with the lock off")
}

; the Aura Storage X: the same guard
Test_Minions_StorageCloseTurnsShiftLockOffFirst() {
    m := MnTask([[]], , , MnLockIO())
    m.s.openAtStart := true
    m.io.lock := true
    AssertTrue(m.t._swap._ShutStorage(m.t._swap._AuraCal(), SchedCtx()), "closed")
    AssertEq(m.io.locked, 0, "no click while on")
    AssertTrue(!m.io.lock, "off")
    AssertTrue(MnLogged(m, "shift lock was on before the Aura Storage X - turned it off"), "logged")
    m := MnTask([[]], , , MnLockIO())
    m.s.openAtStart := true
    m.io.lock := true, m.io.works := false
    AssertTrue(!m.t._swap._ShutStorage(m.t._swap._AuraCal(), SchedCtx()), "stuck on: not closed")
    AssertEq(m.io.Clicks(), 0, "no click")
    AssertTrue(MnLogged(m, "shift lock would not turn off before the Aura Storage X - not clicked"), "reported")
}

; live 2026-11-03 18:29: the hunt after, shift lock on from before with no
; hunt's _lockTried to turn it off, Collections clicked at the centre 3 times
Test_Minions_CollectionsLeftUpWithShiftLockOnClosesBeforeTheHunt() {
    m := MnTask([[]], , , MnLockIO())
    m.s.logName := "Eden", m.s.coll := true
    m.io.lock := true
    m.t.Run(SchedCtx())
    AssertEq(m.io.locked, 0, "no click while on")
    AssertTrue(!m.s.State().coll, "closed")
    AssertTrue(MnLogged(m, "input: shift lock was on before"), "the guard's turn off logged")
    AssertTrue(!MnLogged(m, "would not close"), "no try spent")
}

; a game page frees the cursor until the respawn's Esc: the hunt's off check
; reads off with the lock on
class MnPageIO extends MnLockIO {
    Down(k) {
        if (k = "Esc")
            this.free := false
        return super.Down(k)
    }
}

Test_Minions_RespawnAfterTheHuntFailingIsLogged() {
    near := [{x: 1280, y: 680, w: 200}]
    m := MnTask(, , , MnPageIO())
    n := 0
    m.t._scanFn := () => (++n = 2 ? (m.io.works := false, m.io.free := true) : 0, n <= 2 ? near : [])
    m.t.Run(SchedCtx())
    AssertTrue(MnLogged(m, "minions: shift lock off"), "the off check fooled")
    AssertTrue(m.io.lock, "still on")
    AssertEq(m.io.locked, 0, "no click while on")
    AssertTrue(MnLogged(m, "the respawn after the hunt failed (shift lock would not turn off"), "says why")
}

Test_Minions_StorageThatWillNotCloseMeansNoHunt() {
    m := MnTask([[]])
    m.s.logName := "Eden", m.s.openAtStart := true, m.s.closeDrop := 99
    m.t.Run(SchedCtx())
    AssertTrue(MnLogged(m, "still over the game: no hunt"), "no hunt")
    AssertEq(QmObbyFirst(m.io, "down Left"), 0, "no fight")
}

Test_Minions_PutBackOffNeedsNoKnownAura() {
    m := MnTask()
    m.s.known := false
    AssertEq(m.t.CanRun(m.state), true, "put back off: the aura on now need not be known")
    m.t.Run(SchedCtx())
    AssertEq(m.s.State().eq, "Eden", "Eden on")
    AssertEq(m.wh.Count("errors"), 0, "no error")
    m2 := MnTask(, Map("Minions.putBack", 1))
    m2.s.known := false
    AssertEq(m2.t.CanRun(m2.state), false, "put back on: it must be known (to put it back)")
}

Test_Minions_ShiftAndMatch() {
    AssertEq(MinionsTask.Shift("Left", 100), 360, "Left moves things right")
    AssertEq(MinionsTask.Shift("Right", 100), -360, "Right moves them left")
    bars := [{x: 900, y: 600, w: 40}, {x: 1400, y: 610, w: 40}]
    AssertEq(MinionsTask.Match(bars, {x: 1000, y: 600}).x, 900, "nearest within reach")
    AssertEq(MinionsTask.Match(bars, {x: 1000, y: 600}, 360).x, 1400, "after a Left turn: moved right")
    AssertEq(MinionsTask.Match(bars, {x: 1000, y: 800}), "", "too far down: none")
    r := MinionsTask.Without(bars, {x: 1390, y: 600})
    AssertEq(r.bars.Length "/" r.bars[1].x "/" r.match.x, "1/900/1400", "the matched one taken out")
}

MnLogged(m, text) {
    for l in m.logs
        if InStr(l, text)
            return true
    return false
}

Test_Minions_Confirmed() {
    a := {x: 1000, y: 600, w: 40}, b := {x: 1600, y: 500, w: 40}
    AssertEq(MinionsTask.Confirmed([a, b], []).Length, 0, "the first scan: nothing yet")
    c := MinionsTask.Confirmed([a, b], [{x: 1020, y: 590, w: 40}])
    AssertEq(c.Length "/" c[1].x, "1/1000", "only the one seen before")
    AssertEq(MinionsTask.Confirmed([a], [{x: 640, y: 600, w: 40}], 360).Length, 1, "moved by a Left turn")
}

; a gold leaderboard sign near spawn read as a bar for one scan (the user)
Test_Minions_OneScanBarIsNoTarget() {
    m := MnTask([[{x: 1280, y: 680, w: 200}], []])
    m.t.Run(SchedCtx())
    AssertEq(QmObbyDowns(m.io, "t"), 0, "no skill at a one-scan bar")
    AssertTrue(!MnLogged(m, "target at"), "never a target")
}

; the stats line without " hunt_ms=... left=..." (asserted apart)
MnStatsHead(line) => RegExReplace(line, " hunt_ms=\d+ left=.*$")

Test_Minions_StatsHuntMs() {
    m := MnTask([[]])
    t0 := m.io.t
    m.t.Run(SchedCtx())
    ms := ""
    for l in m.logs
        if RegExMatch(l, "^minions: stats .* hunt_ms=(\d+) left=", &g)
            ms := Integer(g[1])
    AssertTrue(ms != "", "hunt_ms in the stats line")
    AssertTrue(ms >= MinionsTask.DeathWaitMs && ms <= m.io.t - t0, "the hunt's own time (the respawn wait in it)")
}

Test_Minions_OrbIndex() {
    b := (w, y := 600) => {x: 1000, y: y, w: w}
    AssertEq(MinionsTask.OrbIndex([]), 0, "no bars")
    AssertEq(MinionsTask.OrbIndex([b(90)]), 0, "a lone bar of 90 px is a minion")
    AssertEq(MinionsTask.OrbIndex([b(91)]), 1, "a lone bar over 90 px is the orb")
    AssertEq(MinionsTask.OrbIndex([b(40), b(100), b(45)]), 2, "the widest, 1.5x the median of the others")
    AssertEq(MinionsTask.OrbIndex([b(50, 600), b(40, 500), b(45, 400)]), 0, "under 1.5x and nothing below it")
    AssertEq(MinionsTask.OrbIndex([b(50, 600), b(40, 650), b(45, 700)]), 1, "under 1.5x but two bars below it")
    AssertEq(MinionsTask.OrbIndex([b(50, 600), b(40, 650), b(45, 500)]), 0, "only one bar below it")
    AssertEq(MinionsTask.OrbIndex([b(60), b(40)]), 1, "two bars: 60 is 1.5x 40")
}

; the sweep after the hunt gave up: bars only show from then on, moving
; right with every Left turn (Shift) as on screen
MnSweep(bars) {
    m := MnTask()
    m.t.CanRun(m.state)
    l0 := -1
    m.t._scanFn := () => MnSweepScan(m, bars, &l0)
    m.t.Run(SchedCtx())
    return m
}

MnSweepScan(m, bars, &l0) {
    if !MnLogged(m, "giving up")
        return []
    if (l0 < 0)
        l0 := QmObbyDowns(m.io, "Left")
    out := []
    for b in bars
        out.Push({x: b.x + (QmObbyDowns(m.io, "Left") - l0) * MinionsTask.Shift("Left", MinionsTask.ScanTurnMs), y: b.y, w: b.w})
    return out
}

; a bar on one look only, standing still on screen: a turn of ScanTurnMs is
; 1800 px by Shift, past the whole Area, no bar matches over it. Looked at
; again in place, as the look for the boss does
Test_Minions_EndSweepSeesABarAfterATurn() {
    m := MnTask(), t := m.t
    t._scanFn := () => QmObbyDowns(m.io, "Left") = 2 ? [{x: 1600, y: 660, w: 100}] : []
    r := t._Sweep(SchedCtx(), [], 0)
    AssertEq(r.left " " r.orb, "1 1", "the third look saw it")
    AssertEq(QmObbyDowns(m.io, "Left"), MinionsTask.SweepTurns - 1, "a circle of looks")
    n := 0, m := MnTask(), t := m.t
    t._scanFn := () => ++n = 3 ? [{x: 1600, y: 660, w: 100}] : []
    r := t._Sweep(SchedCtx(), [], 0)
    AssertEq(r.left, 0, "one scan alone is no bar")
}

Test_Minions_EndSweepCountsBarsAndTheOrb() {
    m := MnSweep([{x: 1280, y: 680, w: 100}, {x: 1500, y: 660, w: 40}])
    AssertTrue(MnLogged(m, " left=2 orb_left=1 orb_down=0"), "two bars, one an orb")
    m := MnSweep([{x: 1500, y: 660, w: 40}])
    AssertTrue(MnLogged(m, " left=1 orb_left=0 orb_down=0"), "a minion alone")
    AssertTrue(MnLogged(MnSweep([]), " left=0 orb_left=0 orb_down=0"), "nothing")
}

Test_Minions_BiomeChangeSkipsTheSweep() {
    m := MnTask()
    m.t.CanRun(m.state)
    orb := [{x: 1280, y: 680, w: 100}], n := 0
    m.t._scanFn := () => (++n = 6 ? m.state.biome := "PUMPKIN MOON" : 0, orb)
    m.t.Run(SchedCtx())
    AssertTrue(MnLogged(m, " left=0 orb_left=0 orb_down=0"), "no sweep after a biome change")
}

; ---- shift lock (live 2026-11-02, Roblox's Shift Lock Switch on) ----------

MnEvents(io, keys) {
    n := 0
    for e in io.log
        n += (e == "event " keys) ? 1 : 0
    return n
}

Test_Input_ShiftLockTogglesOnlyWhenNeeded() {
    io := MnLockIO()
    AssertEq(Input.ShiftLockOn(io), 0, "off: the cursor stays where it was moved")
    AssertTrue(io.Index("mouse " Input.ShiftProbe[1] "," Input.ShiftProbe[2]) > 0, "probed by a mouse move")
    AssertTrue(Input.ShiftLock(true, io), "turned on")
    AssertTrue(io.lock, "on")
    AssertEq(MnEvents(io, "{sc02A down}") " " MnEvents(io, "{sc02A up}"), "1 1", "one Left Shift tap (scan code)")
    AssertTrue(!Input._held.Has("sc02a"), "Left Shift not left held")
    AssertTrue(Input.ShiftLock(true, io), "already on")
    AssertEq(MnEvents(io, "{sc02A down}"), 1, "no tap when the state matches")
    AssertEq(Input.ShiftLockOn(io), 1, "on: the cursor is back at the centre")
    AssertTrue(Input.ShiftLock(false, io) && !io.lock, "turned off")
    AssertEq(io.Clicks(), 0, "never a click")
}

Test_Input_ShiftLockRetriesOnce() {
    io := MnLockIO()
    io.works := false
    AssertEq(Input.ShiftLock(true, io), false, "the toggle did nothing: not confirmed")
    AssertEq(MnEvents(io, "{sc02A down}"), 2, "one retry")
    io := MnLockIO()
    AssertEq(Input.ShiftLock(true, QmIO()), false, "an io without the hooks: nothing to do")
    ctx := SchedCtx()
    ctx.Stop()
    AssertEq(Input.ShiftLock(true, io, ctx), false, "stopped")
    AssertEq(Input.ShiftLockOn(io, ctx), -1, "stopped: unknown")
    AssertEq(io.log.Length, 0, "stopped: no input at all")
}

; with shift lock on the character faces the camera: no w aim taps; off
; again before the respawn after the hunt (its clicks need the mouse)
Test_Minions_ShiftLockOnForTheFight() {
    near := [{x: 1280, y: 680, w: 200}]
    m := MnTask([near, near, near, near, near, []], , , MnLockIO())
    m.t.Run(SchedCtx())
    AssertTrue(MnLogged(m, "minions: shift lock on") && MnLogged(m, "minions: shift lock off"), "logged")
    AssertTrue(MnSkills(m.io) >= 3, "skills pressed")
    AssertEq(MnDowns(m.io, "w", MnFight(m.io)), 0, "no w aim taps (until the walk back)")
    i0 := QmObbyFirst(m.io, "down r"), iOn := QmObbyFirst(m.io, "event {sc02A up}")
    AssertTrue(i0 > 0 && i0 < iOn && iOn < QmObbyFirst(m.io, "down t"), "on after the respawn, before the skills")
    AssertTrue(QmObbyLast(m.io, "event {sc02A up}") < QmObbyLast(m.io, "down r"), "off before the respawn after")
    AssertTrue(!m.io.lock && m.io.locked = 0, "off at the end, no click while on")
}

Test_Minions_ShiftLockUnconfirmedOrOffKeepsTheAimTap() {
    near := [{x: 1280, y: 680, w: 200}]
    io := MnLockIO()
    io.works := false
    m := MnTask([near, near, near, []], , , io)
    m.t.Run(SchedCtx())
    AssertTrue(MnLogged(m, "shift lock not confirmed"), "logged")
    AssertTrue(QmObbyDowns(m.io, "w") >= 1, "w aim taps")
    m := MnTask([near, near, near, []], Map("Minions.shiftLock", 0), , MnLockIO())
    m.t.Run(SchedCtx())
    AssertEq(MnEvents(m.io, "{sc02A down}"), 0, "setting off: shift lock never toggled (Input.ClickGuard only looks)")
    AssertTrue(QmObbyDowns(m.io, "w") >= 1, "w aim taps")
}

; auto roll mid-hunt: off for the storage swap, on again after
Test_Minions_ShiftLockOffForTheAuraSwap() {
    old := MinionsTask.AuraCheckMs
    MinionsTask.AuraCheckMs := 0
    try {
        near := [{x: 1280, y: 680, w: 200}]
        m := MnTask(, , , MnLockIO())
        n := 0
        m.t._scanFn := () => (++n = 2 ? (m.s.logName := "Pumpkinity") : 0, n <= 3 ? near : [])
        m.t.Run(SchedCtx())
        AssertTrue(MnLogged(m, "Pumpkinity got equipped"), "the swap ran")
        AssertEq(m.io.locked, 0, "no click while shift lock was on")
        AssertEq(MnEvents(m.io, "{sc02A up}"), 4, "on, off for the swap, on, off")
        AssertTrue(!m.io.lock, "off at the end")
    } finally {
        MinionsTask.AuraCheckMs := old
    }
}

; a scan that throws once shift lock is on
MnBoom(io, bars) {
    if io.lock
        throw Error("scan failed")
    return bars
}

Test_Minions_ShiftLockOffOnError() {
    near := [{x: 1280, y: 680, w: 200}]
    m := MnTask(, , , MnLockIO())
    m.t._scanFn := () => MnBoom(m.io, near)
    threw := false
    try m.t.Run(SchedCtx())
    catch
        threw := true
    AssertTrue(threw, "the error came through")
    AssertTrue(!m.io.lock, "off after an error")
    AssertEq(m.io.locked, 0, "no click while on")
}

; F3 mid-hunt: no input after a halt, so shift lock stays on; the next
; hunt turns it off before anything else
Test_Minions_ShiftLockLeftOnByAHaltIsTurnedOffNextTime() {
    near := [{x: 1280, y: 680, w: 200}]
    m := MnTask(, , , MnLockIO())
    ctx := SchedCtx(), n := 0
    m.t._scanFn := () => (++n = 3 ? ctx.Stop() : 0, near)
    m.t.Run(ctx)
    AssertTrue(m.io.lock, "halted: not turned off")
    AssertTrue(MnLogged(m, "shift lock may still be on"), "logged")
    m.t._scanFn := () => []
    m.io.log := []
    m.t.Run(SchedCtx())
    AssertEq(m.io.locked, 0, "off before the storage / the respawn")
    AssertTrue(!m.io.lock, "off at the end")
    AssertTrue(m.io.Index("event {sc02A up}") < m.io.Index("down Esc"), "off first")
}

; shift lock never confirmed off (review 2026-11-02): one more try, then
; every click step is skipped - with it on a click lands at the screen
; centre (live 2026-11-02: the Donation purchase prompt)
Test_Minions_ShiftLockStuckOnNeverClicks() {
    ; owed from before: no swap, no hunt
    io := MnLockIO()
    io.lock := true, io.works := false
    m := MnTask([[]], , , io)
    m.t._lockOwed := true
    AssertEq(m.t.Run(SchedCtx()), 0, "no hunt")
    AssertEq(io.Clicks(), 0, "the storage never clicked")
    ; two taps each, plus one after the first-person zoom out (still pinned)
    AssertEq(MnEvents(io, "{sc02A up}"), 6, "off tried once more (two taps + zoom out + tap each)")
    AssertTrue(MnLogged(m, "shift lock may still be on - the aura swap skipped (no click)"), "logged")
    ; stuck on after the hunt: no respawn menu, no put-back (owed)
    near := [{x: 1280, y: 680, w: 200}]
    io := MnLockIO()
    m := MnTask(, Map("Minions.putBack", 1), , io)
    n := 0
    m.t._scanFn := () => (++n = 3 ? (io.works := false) : 0, n <= 4 ? near : [])
    m.t.Run(SchedCtx())
    AssertTrue(io.lock, "still on")
    AssertEq(io.locked, 0, "no click while on")
    AssertTrue(MnLogged(m, "the respawn skipped (no click)") && MnLogged(m, "the aura put-back skipped (no click)"), "logged")
    AssertTrue(IsObject(m.t._swap._owed), "the put-back owed")
}

; auto roll mid-hunt with shift lock stuck on: no storage click, the hunt ends
Test_Minions_ShiftLockStuckOnSkipsTheAuraReequip() {
    old := MinionsTask.AuraCheckMs
    MinionsTask.AuraCheckMs := 0
    try {
        near := [{x: 1280, y: 680, w: 200}]
        io := MnLockIO()
        m := MnTask(, , , io)
        n := 0
        m.t._scanFn := () => (++n = 2 ? (m.s.logName := "Pumpkinity", io.works := false) : 0, n <= 3 ? near : [])
        m.t.Run(SchedCtx())
        AssertTrue(MnLogged(m, "Pumpkinity got equipped"), "the auto roll seen")
        AssertTrue(MnLogged(m, "the aura re-equip skipped (no click)"), "logged")
        AssertEq(io.locked, 0, "no click while on")
    } finally {
        MinionsTask.AuraCheckMs := old
    }
}

; ---- the HP text on the bars ("300 / 300" orb, "100 / 100" minion) -------
; 2026-11-02 clips: a bar gets shorter when the player walks away too, so
; "shorter, then gone" counted kills nobody made; the text is the truth

MnHpStr(r) => IsObject(r) ? r.hp "/" r.max : ""

MnH(hp, max) => {hp: hp, max: max}

MnStatsOf(m) {
    for l in m.logs
        if InStr(l, "minions: stats")
            return l
    return ""
}

; ---- the GRAVEYARD boss (2026 Halloween update: an Elite Minion, ~2000 HP,
; ~5% of GRAVEYARD starts, up to 10 min) -----------------------------------

; MnTask in GRAVEYARD, the biome start seen (CanRun)
MnBoss(frames := "", gets := "") {
    m := MnTask(frames, gets)
    m.state.biome := "GRAVEYARD"
    m.t.CanRun(m.state)
    return m
}

Test_Minions_GraveyardOncePerStart() {
    m := MnBoss([[]])
    AssertEq(m.t.CanRun(m.state), true, "GRAVEYARD: the boss check (Minions.boss default 1)")
    m.t.Run(SchedCtx())
    AssertEq(m.t.CanRun(m.state), false, "checked this GRAVEYARD already")
    m.io.t += MinionsTask.RehuntMs
    AssertEq(m.t.CanRun(m.state), false, "the boss spawns only when GRAVEYARD starts: no recheck")
    m.state.biome := "NORMAL", m.t.CanRun(m.state), m.state.biome := "GRAVEYARD"
    AssertEq(m.t.CanRun(m.state), true, "a new GRAVEYARD -> again")
    AssertEq(MnBoss(, Map("Minions.boss", 0)).t.CanRun(m.state), false, "boss off")
}

; nothing in sight: ends after BossLookMs, no storage (no aura swap), a
; closing respawn as after a hunt (L49 18:18:57: none, the next hunt paid one)
Test_Minions_NoBossEndsQuicklyWithoutASwap() {
    for gets in [Map(), Map("Minions.putBack", 1)] {
        m := MnBoss([[]], gets)
        t0 := m.io.t
        AssertEq(m.t.Run(SchedCtx()), 0, "no target")
        AssertTrue(MnLogged(m, "minions: no boss in GRAVEYARD"), "logged")
        AssertEq(QmObbyFirst(m.io, "type E"), 0, "no storage search")
        AssertEq(m.s.State().eq, "Glock", "the aura untouched")
        AssertEq(QmObbyDowns(m.io, "r"), 2, "respawns: before the look, the closing one")
        AssertTrue(QmObbyDowns(m.io, "Left") >= 2 * MinionsTask.SweepTurns, "full turns")
        AssertTrue(m.io.t - t0 >= MinionsTask.BossLookMs && m.io.t - t0 < MinionsTask.BossLookMs + 30000, "about BossLookMs")
        AssertTrue(!MnLogged(m, "minions: stats"), "no fight")
    }
    m := MnBoss([[]])                             ; the combat aura on already
    m.s.logName := "Eden"
    m.t.Run(SchedCtx())
    AssertTrue(MnLogged(m, "Eden already on") && MnLogged(m, "no boss in GRAVEYARD"), "looked with Eden on")
    AssertEq(QmObbyDowns(m.io, "r"), 2, "respawns: before the look, the closing one")
}

; a look, NORMAL, an orb biome: no respawn left to pay. Eden on: the look's
; closing respawn holds through NORMAL. Eden off: NORMAL's set-up pays it.
Test_Minions_NextHuntStartsFromTheBossLooksRespawn() {
    m := MnBoss([[]])
    m.s.logName := "Eden"
    m.t.Run(SchedCtx())
    m.state.biome := "NORMAL"
    AssertEq(m.t.CanRun(m.state), false, "Eden on, the respawn fresh: idle in NORMAL")
    m.state.biome := "RAINY"
    AssertEq(m.t.CanRun(m.state), true, "an orb biome")
    MnShortHunt(m)
    AssertTrue(MnLogged(m, "minions: still at spawn since the last hunt - no respawn"), "Eden on: from the look's respawn")
    m := MnBoss([[]])
    m.t.Run(SchedCtx())
    AssertTrue(m.t._spawnAt > 0, "the look before the swap closed too")
    m.state.biome := "NORMAL"
    AssertEq(m.t.CanRun(m.state), true, "Eden off: the set-up")
    m.t.Run(SchedCtx())
    m.state.biome := "RAINY"
    AssertEq(m.t.CanRun(m.state), true, "an orb biome")
    MnShortHunt(m)
    AssertTrue(MnLogged(m, "minions: still at spawn since the last hunt - no respawn"), "Eden off: from the set-up's respawn")
}

; the look sees a bar: the combat aura on, a respawn, the fight (BossMaxSec,
; a step back after every skill), boss=1 in the stats
Test_Minions_BossFoundIsFought() {
    boss := [{x: 1280, y: 680, w: 200}]
    m := MnBoss()
    m.t._scanFn := () => (MnSkills(m.io) < 6) ? boss : []
    m.t.Run(SchedCtx())
    AssertTrue(MnLogged(m, "minions: boss in sight"), "logged")
    iR1 := QmObbyFirst(m.io, "down r"), iE := QmObbyFirst(m.io, "type E"), iT := QmObbyFirst(m.io, "down t")
    AssertTrue(iR1 > 0 && iR1 < iE && iE < iT, "respawn, look, then the swap, then skills")
    AssertEq(QmObbyDowns(m.io, "r"), 3, "respawns: before the look, after the swap, after the fight")
    AssertEq(m.s.State().eq, "Eden", "Eden on")
    AssertEq(MnDowns(m.io, "s", MnFight(m.io)), 0, "the same fight: no step back")
    AssertTrue(InStr(MnStatsOf(m), " boss=1"), "boss=1 in the stats")
    AssertTrue(!MnLogged(m, "no boss in GRAVEYARD"), "not the no-boss end")
    AssertTrue(MnLogged(m, "no boss in sight for " MinionsTask.BossQuietMs // 1000 " s - fight over"), "gone: the fight ends")
}

; the boss fight may last up to BossMaxSec, not Minions.maxSec
Test_Minions_BossFightLastsUpToBossMaxSec() {
    boss := [{x: 1280, y: 680, w: 200}]
    m := MnBoss([boss])
    m.s.logName := "Eden"
    m.t.Run(SchedCtx())
    RegExMatch(MnStatsOf(m), "hunt_ms=(\d+)", &g)
    ms := Integer(g[1])
    AssertTrue(ms >= MinionsTask.BossMaxSec * 1000 && ms < MinionsTask.BossMaxSec * 1000 + 5000, "BossMaxSec (" ms ")")
    n := MnTask([boss])                           ; a normal biome: Minions.maxSec as before
    n.t.Run(SchedCtx())
    RegExMatch(MnStatsOf(n), "hunt_ms=(\d+)", &g)
    AssertTrue(Integer(g[1]) < MinionsTask.MaxSec * 1000 + 5000, "normal hunt unchanged")
    AssertTrue(!InStr(MnStatsOf(n), "boss="), "no boss field")
}

; the boss bar UI at the top (GUESSED) counts as the boss in sight
Test_Minions_BossBarUiStartsTheFight() {
    m := MnBoss([[]])
    m.s.logName := "Eden"
    m.t._bossFn := () => true
    m.t.Run(SchedCtx())
    AssertTrue(MnLogged(m, "boss in sight (the boss bar at the top)"), "logged")
    AssertTrue(InStr(MnStatsOf(m), " boss=1"), "fought")
}

; a grab painting f(x, y) (screen px)
MnPaint(f) => (x1, x2, ys, stride) => MnPaintRows(f, x1, x2, ys, stride)
MnPaintRows(f, x1, x2, ys, stride) {
    rows := []
    for y in ys {
        row := [], x := x1
        while (x <= x2)
            row.Push(f(x, y)), x += stride
        rows.Push(row)
    }
    return rows
}

Test_Minions_BossBarAtTheTop() {
    sky := 0x1A1A2A
    bar := (x, y) => (x >= 1000 && x <= 1560 && y >= 80 && y <= 92) ? (y < 86 ? 0xFF3030 : 0xC01818) : sky
    b := MinionsTask.BossBar(MnPaint(bar))
    AssertTrue(IsObject(b) && Abs(b.w - 560) <= 4 && Abs(b.x - 1280) <= 4, "a wide red bar at the top centre")
    text := (x, y) => (x >= 1250 && x <= 1300 && y >= 80 && y <= 92) ? 0xFFFFFF : bar(x, y)
    AssertTrue(IsObject(MinionsTask.BossBar(MnPaint(text))), "its HP text bridged")
    AssertEq(MinionsTask.BossBar(MnPaint((x, y) => sky)), "", "nothing")
    short := (x, y) => (x >= 1200 && x <= 1360 && y >= 80 && y <= 92) ? 0xFF3030 : sky
    AssertEq(MinionsTask.BossBar(MnPaint(short)), "", "too short: an orb's bar")
    warm := (x, y) => (x >= 900 && x <= 1700 && y >= 60) ? 0xF9B030 : sky
    AssertEq(MinionsTask.BossBar(MnPaint(warm)), "", "a big warm area (sunset, lava) is no bar")
    ; the UI bar is no target in the fight
    ui := {x: 1280, y: 100, w: 400}, foe := {x: 1280, y: 680, w: 200}
    r := MinionsTask.NotBossUi([ui, foe])
    AssertEq(r.Length "/" r[1].y, "1/680", "the boss bar UI dropped")
}

; ---- after a target out of reach, walls, the island's edge (loop L19
; 2026-11-03: "giving up" 38 s after the WINDY orb went behind a terrace
; ledge; 20 s facing a terrace wall; walked off the island to a glow) ----

Test_Minions_Pursue() {
    p := MinionsTask.PursueMs
    AssertEq(MinionsTask.Pursue(200000, ""), false, "nothing seen")
    AssertEq(MinionsTask.Pursue(200000, 200000 - p), true, "seen PursueMs ago: after it again")
    AssertEq(MinionsTask.Pursue(200000, 200000 - p - 1), false, "seen longer ago: give up")
}

; a far bar seen, then gone behind a ledge for good: the walk back to its
; bearing, then instead of the give up, after it again: sliding left,
; sliding right, backing off and round; then the give up
Test_Minions_TargetBehindALedgeIsPursued() {
    m := MnTask()
    m.t.CanRun(m.state)
    far := [{x: 1280, y: 520, w: 60}], n := 0
    m.t._scanFn := () => (++n <= 3) ? far : []
    m.t.Run(SchedCtx())
    k := MinionsTask.PursueStyles.Length
    i1 := MnLogAt(m, "back to the fight")
    i2 := MnLogAt(m, "after it again at bearing 0 ms, sliding left (1/" k ")")
    i3 := MnLogAt(m, "sliding right (2/" k ")")
    i4 := MnLogAt(m, "backing off and round (3/" k ")")
    iq := MnLogAt(m, "into the biome - giving up")
    AssertTrue(i1 && i1 < i2 && i2 < i3 && i3 < i4 && i4 < iq, "back, the three pursuits, then the give up: " i1 " " i2 " " i3 " " i4 " " iq)
    w := MinionsTask.ReturnWalks
    AssertTrue(MnSlides(m.io, "a") >= w && MnSlides(m.io, "d") >= w, "slid left and right: " MnSlides(m.io, "a") " " MnSlides(m.io, "d"))
    AssertTrue(QmObbyDowns(m.io, "s") >= 1, "backed off")
    for key in ["w", "a", "d", "s", "Space"]
        AssertEq(QmObbyDowns(m.io, key), MnUps(m.io, key), "every " key " released")
}

; a near target fought and gone (a kill): no pursuit, the give up as before
Test_Minions_NoPursuitAfterAFight() {
    near := [{x: 1280, y: 680, w: 200}]
    m := MnTask([near, near, near, near, []])
    m.t.CanRun(m.state)
    m.t.Run(SchedCtx())
    AssertTrue(MnSkills(m.io) >= 1, "fought")
    AssertTrue(!MnLogged(m, "after it again"), "not pursued")
}

; the island's edge ahead (the view's edge): no walk, a step back and a
; half turn first (a glow over the sea)
Test_Minions_EdgeAheadTurnsBack() {
    m := MnTask(, , , MnTurnIO())
    m.t.CanRun(m.state)
    k := 0
    m.t._viewFn := () => {edge: ++k = 1, sig: []}
    m.t._beaconFn := () => [{x: 1280, y: 600, r: 20}]
    m.t.Run(SchedCtx())
    AssertTrue(MnLogged(m, "the island's edge ahead - backing off and turning round"), "logged")
    iBk := QmObbyFirst(m.io, "down s"), iWk := QmObbyFirst(m.io, "down w")
    AssertTrue(iBk && iBk < iWk, "the step back before any walk")
    half := MinionsTask.FullTurnMs // 2, t := 0
    for x in m.io.turns
        if (A_Index <= half // MinionsTask.TurnMaxMs)
            t += Integer(StrSplit(x, " ")[2])
    AssertEq(t, half, "a half turn, in steps of TurnMaxMs")
    AssertTrue(MnWalks(m.io) >= 3, "then walked on")
}

; on a walk to a bar that edge is mostly a floor read as sea (L51 22:45:14-:27),
; a true half turn would face away from the target: the 75 degrees the logs were
; made with
Test_Minions_EdgeOnTheWayToABarTurnsLittle() {
    m := MnTask(, , , MnTurnIO()), t := m.t, ctx := SchedCtx()
    t._viewFn := () => {edge: true, sig: []}
    t._toBar := true
    AssertEq(t._EdgeGuard(ctx), -1, "no step")
    AssertEq(m.io.HeldMs("s"), MinionsTask.EdgeBackMs, "a step back")
    AssertEq(t._bearing, MinionsTask.EdgeBarTurnMs, "the short turn")
}

; patrols and blind walks: the true half turn
Test_Minions_EdgeOffTheWayToABarTurnsHalfACircle() {
    m := MnTask(, , , MnTurnIO()), t := m.t, ctx := SchedCtx()
    t._viewFn := () => {edge: true, sig: []}
    t._toBar := false
    AssertEq(t._EdgeGuard(ctx), -1, "no step")
    AssertEq(m.io.HeldMs("s"), MinionsTask.EdgeBackMs, "a step back")
    AssertEq(t._bearing, MinionsTask.FullTurnMs // 2, "the half turn")
}

; the patrol's quiet starts when the back-off and the turn are done: a 1500 ms
; turn would eat half of it (the L39 spin guard)
Test_Minions_EdgeQuietCountsFromTheEndOfTheTurn() {
    m := MnTask(, , , MnTurnIO()), t := m.t, ctx := SchedCtx()
    t._viewFn := () => {edge: true, sig: []}
    t._patrolling := true
    AssertEq(t._EdgeGuard(ctx), -1, "turned")
    AssertEq(t._edgeFree, m.io.t + MinionsTask.EdgeQuietMs, "quiet from now")
    AssertEq(t._EdgeGuard(ctx), 1, "walked on")
    m.io.t += MinionsTask.EdgeQuietMs
    AssertEq(t._EdgeGuard(ctx), -1, "a read again")
}

; a turn at the edge in the patrol ends the leg: the steps left of it would
; run back over what was searched
Test_Minions_PatrolLegEndsAtAnEdgeTurn() {
    m := MnTask(, , , MnTurnIO()), t := m.t, ctx := SchedCtx()
    f := {wallOff: "", pLeg: 1, pLeft: 5, shift: 0}
    t._viewFn := () => {edge: false, sig: []}
    t._PatrolStep(ctx, f)
    AssertEq(f.pLeft, 4, "a walk, the leg goes on")
    t._viewFn := () => {edge: true, sig: []}
    m.io.t += MinionsTask.EdgeQuietMs
    t._PatrolStep(ctx, f)
    AssertEq(f.pLeft, 0, "turned: the leg is over")
    t._Stop()
}

; a fall just after the guard turned went the way the player faced before the
; turn: the bearing at the death is the opposite one, FallAhead would hold the
; walk inland and let the walk to the cliff by for FallKeepMs
Test_Minions_FallAfterAnEdgeTurnKeepsTheWayBeforeIt() {
    m := MnTask(), t := m.t
    st := {b: "", x: 0, y: 0, dead: 0}
    t._beaconFn := () => [{x: 1280 + MinionsTask.GlowAim(1), y: 700, r: 20}]
    t._viewFn := () => MnFallEdge(m, st)
    t._deathFn := () => (!st.dead && m.io.HeldMs("s")) ? (st.dead := 1) : false
    t.Run(SchedCtx())
    AssertTrue(st.dead, "died")
    AssertTrue(t._falls.Length >= 1, "kept")
    w := t._falls[1]
    AssertEq(w.b " " w.x " " w.y, st.b " " st.x " " st.y, "the way before the turn")
    AssertTrue(MnLogged(m, "That way (bearing " st.b " ms"), "logged so")
}

MnFallEdge(m, st) {
    t := m.t, e := MnWalks(m.io) >= 6 && !m.io.HeldMs("s")
    if e
        st.b := t._bearing, st.x := t._pos.x, st.y := t._pos.y
    return {edge: e, sig: []}
}

; the guard's way counts FallGuardMs, then the bearing of the death again
Test_Minions_FallWayForgetsAnOldEdgeTurn() {
    m := MnTask(, , , MnTurnIO()), t := m.t, ctx := SchedCtx()
    t._viewFn := () => {edge: true, sig: []}
    t._pos := {x: 100, y: 200}
    t0 := m.io.t
    t._EdgeGuard(ctx)
    t._pos := {x: 300, y: 400}
    m.io.t := t0 + MinionsTask.FallGuardMs
    w := t._FallWay()
    AssertEq(w.b " " w.x " " w.y, "0 100 200", "fired at")
    m.io.t += 1
    w := t._FallWay()
    AssertEq(w.b " " w.x " " w.y, t._bearing " 300 400", "too long ago")
}

; the view the same after walks (a wall ahead): SlideSteps slides along it
; one way, then walking again; the next wall the other way
Test_Minions_WalkIntoAWallSlides() {
    m := MnTask()
    sig := [1, 2, 3]
    m.t._viewFn := () => {edge: false, sig: sig}
    ctx := SchedCtx()
    st := MinionsTask.SlideSteps, sw := MinionsTask.StillWalks
    Loop sw + 1 + st
        AssertTrue(m.t._WalkOrSlide(ctx), "stepped")
    AssertTrue(MnLogged(m, "walking into a wall - sliding left along it"), "logged")
    AssertEq(QmObbyDowns(m.io, "a") " " QmObbyDowns(m.io, "d"), st " 0", "SlideSteps slides left")
    AssertEq(MnWalks(m.io) " " QmObbyDowns(m.io, "a"), (sw + 1) " " st, "a walk or a slide each")
    m.t._WalkOrSlide(ctx)
    AssertEq(QmObbyDowns(m.io, "a") + QmObbyDowns(m.io, "d"), st, "then a walk")
    Loop sw + 1
        m.t._WalkOrSlide(ctx)
    AssertEq(QmObbyDowns(m.io, "d"), 1, "the next wall: right")
    ; the view changing: walks only
    m := MnTask(), n := 0
    m.t._viewFn := () => {edge: false, sig: [(++n * 40 * 0x010101) & 0xFFFFFF]}
    Loop 8
        m.t._WalkOrSlide(ctx)
    AssertEq(QmObbyDowns(m.io, "a") + QmObbyDowns(m.io, "d"), 0, "an open view: no slide")
}

; no view dep with a fake scan: no view, no edge, no wall
Test_Minions_NoViewWithAFakeScan() {
    m := MnTask()
    AssertEq(m.t._View(), "", "no view")
    AssertTrue(m.t._Walk(SchedCtx()) && QmObbyDowns(m.io, "w") = 1, "a plain walk")
}

Test_Minions_ViewSame() {
    a := [0x102030, 0x405060, 0x708090, 0xA0B0C0, 0, 0, 0, 0, 0, 0]
    b := a.Clone()
    AssertTrue(MinionsTask.ViewSame(a, b), "identical")
    b[1] := 0x102030 + 0x200000                ; red +32 on 1 of 10
    AssertTrue(!MinionsTask.ViewSame(a, b), "a tenth changed: not the same")
    b[1] := 0x102030 + 0x100000                ; +16: under SameDiff
    AssertTrue(MinionsTask.ViewSame(a, b), "small changes: the same")
    AssertTrue(!MinionsTask.ViewSame(a, [1, 2]) && !MinionsTask.ViewSame([], []) && !MinionsTask.ViewSame("", a), "lengths / none")
}

Test_Minions_IsSea() {
    AssertTrue(MinionsTask.IsSea(0x6EAAE6) && MinionsTask.IsSea(0x88C0F0), "day sea / sky blue")
    AssertTrue(!MinionsTask.IsSea(0x3CB43C) && !MinionsTask.IsSea(0x9090A0) && !MinionsTask.IsSea(0x101830) && !MinionsTask.IsSea(0xB4F0F0), "grass, grey stone, night, a cyan floor pad")
}

; rows of a half size file at screen coords (file px = (screen - o) / 2)
MnFileRows(name, ys, x1, x2, stride, ox, oy) {
    g := MatchFileGrab(A_ScriptDir "\screens\" name)
    rows := []
    for y in ys
        rows.Push(g.Call((x1 - ox) // 2, (x2 - ox) // 2, [(y - oy) // 2], stride // 2)[1])
    return rows
}

MnYs(y1, y2, step) {
    ys := [], y := y1
    while (y <= y2)
        ys.Push(y), y += step
    return ys
}

; real clip frames (2026-11-03, 1280x720 = half size; crops of screen
; x 520..2020, y 880..1152): walking off the island's edge (sea blue
; beside the legs, frames 15-17 before the fall) = edge; spawn, trees,
; the sky by day, a field, a terrace wall at night = none
Test_Minions_EdgeAheadOnRealFrames() {
    ys := MnYs(MinionsTask.EdgeY1, MinionsTask.ViewArea.y2, MinionsTask.ViewStep)
    st := MinionsTask.ViewStride, x1 := MinionsTask.ViewArea.x1 + 0
    for name in ["edge_a", "edge_b", "edge_c", "noedge_sky", "noedge_trees", "noedge_spawn", "noedge_field", "noedge_night_wall"] {
        rows := MnFileRows("minions_" name ".png", ys, 536, 2000, st, 520, 880)
        AssertEq(MinionsTask.EdgeAhead(rows, ys, 536, st), SubStr(name, 1, 5) = "edge_", name)
    }
}

; the floors that read as sea (L49 18:48:47, L46 15:46:38 SNOWY, L46 15:34:27
; STARFALL, L46 15:36:17 HEAVEN; every 2nd px of screen x 520..2020, y 880..1152):
; no edge in their biomes, no step back, no turn. The same read in WINDY: an edge
Test_Minions_RealSeaFloorsAreNoEdge() {
    a := MinionsTask.ViewArea, st := MinionsTask.ViewStride
    ys := MnYs(MinionsTask.EdgeY1, a.y2, MinionsTask.ViewStep)
    for name, biome in Map("snowy_a", "SNOWY", "snowy_b", "SNOWY", "starfall", "STARFALL", "heaven", "HEAVEN") {
        rows := MnFileRows("minions_floor_" name ".png", ys, 536, 2000, st, 520, 880)
        v := MinionsTask.ViewOf(rows, ys, 536, st)
        AssertTrue(v.edge, name ": the floor reads as sea")
        m := MnTask(, , , MnTurnIO()), t := m.t, ctx := SchedCtx()
        t._viewFn := () => v
        t._biome := biome
        AssertEq(t._EdgeGuard(ctx), 1, name ": walks on")
        AssertEq(m.io.HeldMs("s"), 0, name ": no step back")
        AssertEq(t._bearing, 0, name ": no turn")
        t._biome := "WINDY"
        AssertEq(t._EdgeGuard(ctx), -1, name ": an edge in WINDY")
    }
}

; only the view is ignored there: a remembered fall still turns the player
Test_Minions_SeaFloorKeepsRememberedFalls() {
    m := MnTask(, , , MnTurnIO()), t := m.t, ctx := SchedCtx()
    t._viewFn := () => {edge: false, sig: []}
    t._biome := "SNOWY"
    t._falls := [{x: 0, y: 0, b: 0, at: m.io.t}]
    AssertEq(MinionsTask.FallAhead(t._falls, t._pos, t._bearing, MinionsTask.WalkMs, m.io.t), true, "this fall lies ahead")
    AssertEq(t._EdgeGuard(ctx), -1, "turned")
    AssertTrue(MnLogged(m, "fell off the island this way before"), "the fall, not the view")
}

; real clip frames (crops of screen x 560..2000, y 400..968): a second
; apart facing a terrace wall at night (WINDY) = the same; walking at
; spawn by day = not
Test_Minions_ViewSameOnRealFrames() {
    a := MinionsTask.ViewArea
    ys := MnYs(a.y1, MinionsTask.ViewSigY, MinionsTask.ViewStep)
    v := (name) => MinionsTask.ViewOf(MnFileRows("minions_view_" name ".png", ys, a.x1, a.x2, MinionsTask.ViewStride, 560, 400), ys, a.x1, MinionsTask.ViewStride).sig
    AssertTrue(MinionsTask.ViewSame(v("wall_a"), v("wall_b")), "facing the wall: the same")
    AssertTrue(!MinionsTask.ViewSame(v("walk_a"), v("walk_b")), "walking: changed")
    AssertTrue(!MinionsTask.ViewSame(v("wall_a"), v("walk_a")), "another place: changed")
}

; m.logs index of the first line with text (0 = none)
MnLogAt(m, text) {
    for i, l in m.logs
        if InStr(l, text)
            return i
    return 0
}

; ---- combat study 2026-11-03 (clips L19): the player's HP, the orb's
; minions first, a near bar lost is fought on, staying by a locked orb ----

; real crops of the player list's header (screen x 2400.., y 20..):
; Roblox draws the player's HP over "Rolls" once hurt; full HP: no bar
MnPlayerHp(name) => MinionsTask.PlayerHp(MatchFileGrab(A_ScriptDir "\screens\" name), 2400, 20)

Test_Minions_RealPlayerHp() {
    for c in [["player_hp_rainy_yellow.png", 0.44, 0.52, "yellow, the red hurt vignette over the grey"]
        , ["player_hp_snowy_green.png", 0.70, 0.78, "green ~3/4"]
        , ["player_hp_hell_green.png", 0.66, 0.74, "HELL, green ~70%"]
        , ["player_hp_snowy_yellow.png", 0.54, 0.62, "yellow ~58%"]
        , ["player_hp_snowy_nearfull.png", 0.95, 1.0, "teal, nearly full"]] {
        v := MnPlayerHp(c[1])
        AssertTrue(v >= c[2] && v <= c[3], c[4] " (" v ")")
    }
    ; these read -1 by fill, grey and the bar's right end: the vignette, the
    ; grey under the night's floor (clip 224541920 at 45 and 50 s, grey 87)
    for c in [["player_hp_windy_hurt.png", "0.56", "L44 13:54:32, yellow under the vignette"]
        , ["player_hp_graveyard_hurt.png", "0.48", "L46 15:05:30, GRAVEYARD, the vignette"]
        , ["player_hp_heaven_green.png", "0.72", "L46 15:37:04, HEAVEN"]
        , ["player_hp_snowy_red.png", "0.03", "L46 15:47:33, red, nearly dead"]
        , ["player_hp_night_green.png", "0.87", "night, green"]
        , ["player_hp_night_low.png", "0.35", "night, yellow"]]
        AssertEq(MnPlayerHp(c[1]), c[2], c[3])
    for f in ["player_hp_full_hell.png", "player_hp_full_sky.png", "player_hp_full_grey.png"
        , "player_hp_full_heaven.png", "player_hp_full_sand.png"]
        AssertEq(MnPlayerHp(f), -1, "full HP: no bar (" f ")")
    AssertEq(MinionsTask.PlayerHp(MatchFileGrab(A_ScriptDir "\screens\world_day.jpg")), -1, "no player list in the world frame")
    bright := (x1, x2, ys, step) => MnRows(ys.Length, x2 - x1 + 1, [], 0xFFFF00)
    AssertEq(MinionsTask.PlayerHp(bright), -1, "the fill's colour left of the bar too: scenery")
}

; ---- deaths told on screen / by the HP; the step out after Voidrush -------
; (loop L19 2026-11-03: SNOWY 042511 and RAINY 041829 deaths never seen)

; real frames (clips at 720p scaled 2x; live HELL / GRAVEYARD screenshots)
Test_Minions_RealDeathScreen() {
    fr := (name) => MatchFileGrab(A_ScriptDir "\screens\" name ".jpg")
    for f in ["death_black_snowy_clip", "death_red_snowy_clip", "death_black_rainy_clip"]
        AssertTrue(MinionsTask.DeathScreen(fr(f)), f ": the death screen")
    for f in ["nodeath_voidrush_rainy_clip", "nodeath_barrage_snowy_clip", "nodeath_hell", "nodeath_hell_b"
        , "nodeath_graveyard_prompt", "world_day"]
        AssertTrue(!MinionsTask.DeathScreen(fr(f)), f ": no death screen")
}

Test_Minions_RespawnedByHp() {
    L := (a*) => MnHpLog(a)
    AssertEq(MinionsTask.Respawned(L(0, 0.6, 500, 0.41, 1500, 0.8)), "hp 41% -> 80%", "41% then 80% at spawn (SNOWY 042511)")
    AssertEq(MinionsTask.Respawned(L(0, 0.2, 500, -1, 1600, -1)), "hp 20% -> full", "20% then no bar (full) for a second (RAINY 041829)")
    AssertEq(MinionsTask.Respawned(L(0, 0.2, 500, -1)), "", "one read without the bar: not yet")
    AssertEq(MinionsTask.Respawned(L(0, 0.41, 500, 0.5, 900, 0.8)), "", "healing reads between: no jump")
    AssertEq(MinionsTask.Respawned(L(0, 0.6, 500, 0.9)), "", "never low: no death")
    AssertEq(MinionsTask.Respawned(L(0, 0.3, 11000, 0.8)), "", "low too long ago")
    AssertEq(MinionsTask.LastHp(L(0, 0.4, 500, -1), 1000), 0.4, "the last HP read")
    AssertEq(MinionsTask.LastHp(L(0, 0.4), 5000), -1, "too old")
    AssertEq(MinionsTask.WasHurt(L(0, 0.8, 500, MinionsTask.DeathLowHp, 900, -1)), true, "low at any read")
    AssertEq(MinionsTask.WasHurt(L(0, 0.46, 500, -1)), false, "never low")
    AssertEq(MinionsTask.WasHurt([]), false, "no read")
}

; [at, hp, at, hp, ...] -> Respawned's log
MnHpLog(a) {
    out := []
    Loop a.Length // 2
        out.Push({at: a[2 * A_Index - 1], hp: a[2 * A_Index]})
    return out
}

; the death screen mid-fight: logged, re-aimed, back the way the fight was
Test_Minions_DeathScreenTurnsBackToTheFight() {
    m := MnTask(, , , MnTurnIO())
    near := [{x: 1280, y: 680, w: 200}]
    dead := false
    m.t._scanFn := () => (dead ? [] : QmObbyDowns(m.io, "Left") >= 2 ? near : [])
    m.t._deathFn := () => (!dead && MnSkills(m.io) >= 3) ? (dead := true) : false
    m.t.Run(SchedCtx())
    AssertTrue(MnLogged(m, "minions: died (the death screen) - back at spawn, going straight back to the fight"), "the death logged")
    AssertTrue(MnLogged(m, "back to the fight - straight out, 0 ms, facing bearing -1000 ms"), "the fight was at spawn")
    AssertTrue(MnLogged(m, "where the fight was - looking round"), "a look from there")
    AssertTrue(!MnLogged(m, "replaying the trail"), "no moves, no trail")
    AssertTrue(!MnLogged(m, "turning to bearing"), "no walks by the bearing")
    AssertTrue(InStr(MnStatsOf(m), " deaths=1"), "counted")
}

; real lines of Roblox's log (2026-11-06 04:14:5x UTC, L25 SNOWY 22:14:56, the
; death the macro never saw): casts, then the respawn
global MnLogCast := "2026-11-06T04:14:56.400Z,5000.4,8788,6,Info [FLog::CreatorOutput] Taunt Enum.UserInputState.Begin InputObject`n"
    . "2026-11-06T04:14:56.429Z,5000.4,8788,6,Info [FLog::CreatorOutput] Taunt Enum.UserInputState.End InputObject`n"
    . "2026-11-06T04:14:57.632Z,5001.6,8788,6,Info [FLog::CreatorOutput] Voidrush Enum.UserInputState.Begin InputObject`n"
global MnLogRespawn := "2026-11-06T04:14:56.779Z,5000.7,8788,6,Info [FLog::CreatorOutput] Voidrush Enum.UserInputState.Cancel InputObject`n"
    . "2026-11-06T04:14:56.780Z,5000.7,8788,6,Info [FLog::CreatorOutput] Taunt function: 0x1af09b6a46722163 false Enum.KeyCode.T Enum.KeyCode.ButtonL1`n"

; a line into the log as Roblox writes it: RespawnTail keeps the file open
MnAppend(text, p) {
    f := FileOpen(p, "a", "UTF-8-RAW")
    f.Write(text)
    f.Close()
}

MnLogDir() {
    d := A_Temp "\vesper_respawn_test"
    try DirDelete(d, true)
    DirCreate(d)
    return d
}

; only a skill's binding is a respawn: never a cast, a Cancel (a menu opened)
Test_Minions_RespawnLine() {
    AssertTrue(RespawnTail.IsRespawn(MnLogRespawn), "a skill bound")
    AssertTrue(!RespawnTail.IsRespawn(MnLogCast), "casts, Voidrush")
    AssertTrue(!RespawnTail.IsRespawn("2026-11-06T04:14:56.779Z,5000.7,8788,6,Info [FLog::CreatorOutput] Taunt Enum.UserInputState.Cancel InputObject`n"), "a Cancel alone")
    AssertTrue(!RespawnTail.IsRespawn("2026-11-06T04:14:56.780Z,5000.7,8788,6,Warning [FLog::Output] Taunt function: 0x1 false Enum.KeyCode.T`n"), "not the game's output")
}

Test_Minions_RespawnTail() {
    d := MnLogDir(), p := d "\0.746_Player_ABCDE_last.log"
    t := RespawnTail(d)
    AssertTrue(!t.Poll(), "before a Sync")
    MnAppend(MnLogRespawn, p)
    t.Sync()
    AssertTrue(!t.Poll(), "lines from before the Sync: the hunt's own reset")
    MnAppend(MnLogCast, p)
    AssertTrue(!t.Poll(), "casts")
    MnAppend(SubStr(MnLogRespawn, 1, -20), p)
    AssertTrue(!t.Poll(), "a line not written whole yet")
    AssertEq(t.Seen, false, "no bind line read yet")
    MnAppend(SubStr(MnLogRespawn, -20), p)
    AssertTrue(t.Poll(), "the respawn")
    AssertEq(t.Seen, true, "this log tells respawns")
    AssertTrue(!t.Poll(), "told once")
    AssertEq(t.Seen, true, "and stays so")
    MnAppend(MnLogRespawn, p)
    t.Sync()
    AssertTrue(!t.Poll(), "Sync drops what came")
    AssertEq(t.Seen, true, "kept through a Sync")
    t := ""                                       ; the log is kept open
    DirDelete(d, true)
}

; L25 SNOWY: a respawn in the log with no black frame caught and no HP read:
; a death, counted once
Test_Minions_RespawnInTheLogIsADeath() {
    d := MnLogDir(), p := d "\0.746_Player_ABCDE_last.log"
    MnAppend(MnLogCast, p)
    m := MnTask(, , , MnTurnIO())
    near := [{x: 1280, y: 680, w: 200}]
    dead := false
    m.t._respawnLog := RespawnTail(d)
    m.t._scanFn := () => (dead ? [] : QmObbyDowns(m.io, "Left") >= 2 ? near : [])
    m.t._deathFn := () => ((!dead && MnSkills(m.io) >= 3) ? (dead := true, MnAppend(MnLogRespawn, p), false) : false)
    m.t.Run(SchedCtx())
    AssertTrue(MnLogged(m, "minions: died (a respawn in the log) - back at spawn, going straight back to the fight"), "the death logged")
    AssertTrue(InStr(MnStatsOf(m), " deaths=1"), "counted")
    m.t._respawnLog := ""
    DirDelete(d, true)
}

; the black frame caught first, the respawn's lines come while the death is
; handled (L22 17:33:48 the screen, 17:33:49.4 the lines): one death, not two
Test_Minions_DeathScreenThenItsLogLinesIsOneDeath() {
    d := MnLogDir(), p := d "\0.746_Player_ABCDE_last.log"
    MnAppend(MnLogCast, p)
    m := MnTask(, , , MnTurnIO())
    near := [{x: 1280, y: 680, w: 200}]
    dead := false
    m.t._respawnLog := RespawnTail(d)
    m.t._scanFn := () => (dead ? [] : QmObbyDowns(m.io, "Left") >= 2 ? near : [])
    m.t._deathFn := () => ((!dead && MnSkills(m.io) >= 3) ? (dead := true, MnAppend(MnLogRespawn, p), true) : false)
    m.t.Run(SchedCtx())
    AssertTrue(InStr(MnStatsOf(m), " deaths=1"), "one death: " MnStatsOf(m))
    m.t._respawnLog := ""
    DirDelete(d, true)
}

; the HP low in the fight, then back up (at spawn): a death
Test_Minions_HpJumpIsADeath() {
    m := MnTask(, , , MnTurnIO())
    near := [{x: 1280, y: 680, w: 200}]
    m.t._scanFn := () => (MnSkills(m.io) < 4 ? (QmObbyDowns(m.io, "Left") >= 2 ? near : []) : [])
    ; full (no bar) while it fights, 40% for two reads at the 4th skill,
    ; then 80% (at spawn)
    hp := {n: 0}
    m.t._hudFn := () => {rows: "", points: -1, rank: "", playerHp: MnSkills(m.io) < 4 ? -1 : (++hp.n <= 2 ? 0.4 : 0.8)}
    m.t.Run(SchedCtx())
    AssertTrue(MnLogged(m, "minions: died (hp 40% -> 80%)"), "the respawn told by the HP")
}

; a fight beside a bar with tail as the log: the HP 25%, 2 s unread (a hit's
; frames), 16%, then the orb's toast. With no respawn in the log: L48 17:32:06,
; :16, :25, HP 25, 6, 16, 24, no bind line from 17:31:12 to 17:34:11
MnHpGap(tail) {
    m := MnTask(, Map("Minions.maxSec", 60), , MnTurnIO())
    near := [{x: 1280, y: 400, w: 200}]
    m.t._swap.wear := "Eden"
    m.t._respawnLog := tail
    m.t._scanFn := () => near
    c := {t0: 0, hp: -1}
    m.t._hudFn := () => (h := MnNoPanel(), h.playerHp := c.hp, h)
    m.t._toastFn := () => (c.t0 := c.t0 ? c.t0 : m.io.t, d := m.io.t - c.t0
        , c.hp := d < 3000 ? 0.25 : d < 5000 ? -1 : 0.16, d >= 8000 ? "orb" : "")
    m.t._Fight(SchedCtx())
    return m
}

; a log that has shown it tells respawns: the HP tells none
Test_Minions_HpGapIsNoDeathOnceTheLogProvedItself() {
    tail := MnTail()
    tail.Seen := true
    m := MnHpGap(tail)
    AssertTrue(!MnLogged(m, "minions: died"), "no death: " MnStatsOf(m))
    AssertTrue(InStr(MnStatsOf(m), " deaths=0"), "none counted: " MnStatsOf(m))
    AssertTrue(MnSkills(m.io) >= 2, "the skills went on")
    AssertTrue(tail.stales > 0, "the log asked once the HP told one")
}

; a log with no bind line so far (an aura that prints none, no log at all
; there) or a newer one taking over: the HP route as ever
Test_Minions_HpRouteStaysForALogNotProved() {
    m := MnHpGap(MnTail())
    AssertTrue(MnLogged(m, "minions: died (hp 25% -> full)"), "never saw a line")
    tail := MnTail()
    tail.Seen := true, tail.newer := true
    m := MnHpGap(tail)
    AssertTrue(MnLogged(m, "minions: died (hp 25% -> full)"), "a rejoin: the log read is stale")
}

; Stale scans the log folder: not every tick
Test_Minions_StaleOnlyForARespawnTheHpTold() {
    m := MnTask()
    tail := MnTail()
    tail.Seen := true
    m.t._respawnLog := tail
    Loop 5 {
        AssertEq(m.t._DeathSeen(), "", "nothing told")
        m.io.t += 400
    }
    AssertEq(tail.stales, 0, "no scan")
}

; ---- loop L19 2026-11-03 06:48..07:38: survival, falls, HEAVEN ------------

; HEAVEN's gold floor trim (07:23 / 07:26 / 07:27, attacked as targets): a
; pale yellow row over one gold row on white -> no bar; a fogged SNOWY pair
; (04:26, its scanned orange row as gold, snow fog round it) still bars
Test_Minions_RealHeavenGoldTrimIsNoBar() {
    AssertEq(MnFrameScan("minions_heaven_trim_a.png", 160, 120).Length, 0, "trim a (07:23:58)")
    AssertEq(MnFrameScan("minions_heaven_trim_b.png", 160, 120).Length, 0, "trim b (07:27:05)")
    AssertEq(MnFrameScan("minions_heaven_trim_c.png", 180, 110).Length, 0, "trim c (07:27:26)")
    bars := MnFrameScan("minions_snowy_fog_pair.png", 220, 160)
    AssertEq(bars.Length, 2, "the fogged SNOWY minions' bars")
}

Test_Minions_FallAhead() {
    AssertTrue(Abs(MinionsTask.Way(0).y - 1) < 0.001, "bearing 0: ahead")
    AssertTrue(Abs(MinionsTask.Way(MinionsTask.FullTurnMs // 4).x - 1) < 0.001, "a quarter turn right: right")
    f := [{x: 0, y: 7000, b: 0, at: 0}]           ; fell 7 s of walking ahead
    p := (y) => {x: 0, y: y}
    AssertTrue(!MinionsTask.FallAhead(f, p(0), 0, 700, 1000), "near spawn: walk on")
    AssertTrue(MinionsTask.FallAhead(f, p(4300), 0, 700, 1000), "within FallMarginMs of it: the edge")
    AssertTrue(!MinionsTask.FallAhead(f, p(4300), MinionsTask.FullTurnMs // 2, 700, 1000), "walking away from it: on")
    AssertTrue(!MinionsTask.FallAhead(f, p(4300), MinionsTask.FullTurnMs // 4, 700, 1000), "across it: on")
    AssertTrue(!MinionsTask.FallAhead(f, p(4300), 0, 700, MinionsTask.FallKeepMs), "kept FallKeepMs")
    ; L69: the same edge at 17:54, 18:20, 18:31, 18:45, 10 min memory forgot each
    AssertTrue(MinionsTask.FallAhead(f, p(4300), 0, 700, 26 * 60000), "the next orb biome 26 min on: still the edge")
    AssertTrue(MinionsTask.Fell("", 5000, false), "no bar this hunt: a fall")
    AssertTrue(!MinionsTask.Fell(1000, 5000, false), "a bar 4 s ago: a fight")
    AssertTrue(!MinionsTask.Fell("", 5000, true), "hurt: the minions")
}

; L72 SAND STORM 04:39:21: seen dead 7 s out ahead of spawn (bearing 0)
; facing back to it (1500), kept so it held every walk home from out there
; (04:39:39 "fell off the island this way before (bearing 1500)", turned
; round to the cliff). Kept out from spawn instead: home is free, the walk
; out is the edge
Test_Minions_FallFacingSpawnIsKeptOutFromIt() {
    h := MinionsTask.FullTurnMs // 2
    w := MinionsTask.FallOut({x: 0, y: 7075, b: h})
    AssertEq(w.b " " w.faced, "0 " h, "the way out from spawn, the bearing it faced kept apart")
    AssertEq(MinionsTask.Along(w, w.b), 7075, "7 s out")
    f := [{x: w.x, y: w.y, b: w.b, at: 0}]
    AssertTrue(!MinionsTask.FallAhead(f, {x: 0, y: 7000}, h, 700, 1000), "out there: the walk home goes on")
    AssertTrue(!MinionsTask.FallAhead(f, {x: 0, y: 0}, h, 700, 1000), "at spawn: the walk behind it goes on")
    AssertTrue(MinionsTask.FallAhead(f, {x: 0, y: 4300}, 0, 700, 1000), "the walk out to it: the edge")
    old := [{x: 0, y: 7075, b: h, at: 0}]
    AssertTrue(MinionsTask.FallAhead(old, {x: 0, y: 7000}, h, 700, 1000), "kept as faced it held the walk home")
    ; 04:31:51: bearing -1875, -5665 ms out: out the other way
    w := MinionsTask.FallOut({x: 5665 * MinionsTask.Way(-1875 + h).x, y: 5665 * MinionsTask.Way(-1875 + h).y, b: -1875})
    AssertTrue(Abs(MinionsTask.Wrap(w.b - (-1875 + h))) <= 2 && Abs(MinionsTask.Along(w, w.b) - 5665) <= 2, "04:31:51: " w.b " " MinionsTask.Along(w, w.b))
    w0 := {x: 0, y: 4000, b: 0}
    AssertTrue(MinionsTask.FallOut(w0) == w0, "out along its way: as it was")
    w0 := {x: 300, y: -500, b: 0}
    AssertTrue(MinionsTask.FallOut(w0) == w0, "behind spawn within FallBehindMs (dead reckoning): as it was")
}

; the whole hunt: dead out there with the hunt turned home meanwhile ->
; the edge kept out from spawn, logged so
Test_Minions_FallSeenFacingHomeKeptOutward() {
    m := MnTask()
    glow := [{x: 1280 + MinionsTask.GlowAim(1), y: 700, r: 20}]
    st := {dead: 0}
    m.t._beaconFn := () => glow
    ; seen dead facing spawn from where it is
    m.t._deathFn := () => (st.dead = 0 && MnWalks(m.io) >= 10)
        ? (st.dead := 1, st.out := MinionsTask.PosBearing(m.t._pos), m.t._bearing := st.out + MinionsTask.FullTurnMs // 2, 1) : false
    m.t.Run(SchedCtx())
    AssertEq(m.t._falls.Length, 1, "kept")
    AssertEq(m.t._falls[1].b, st.out, "the way out to where it died")
    w := m.t._falls[1]
    AssertTrue(MinionsTask.Along(w, w.b) > 0, "out from spawn: " w.b " " MinionsTask.Along(w, w.b))
    s := ""
    for l in m.logs
        s .= InStr(l, "died") ? l " | " : ""
    AssertTrue(MnLogged(m, " ms faced back to it, "), "logged: " s)
}

; NORMAL at night 07:09 / 07:12 / 07:13: the death screen a few seconds into
; a walk by the same bearing, nothing in sight, then the walk back by it
; again. A death with no bar seen is a fall: no walk back by it, and that
; way is the edge from then on
Test_Minions_FallOffTheIslandIsAnEdge() {
    m := MnTask()
    glow := [{x: 1280 + MinionsTask.GlowAim(1), y: 700, r: 20}]
    st := {dead: 0}
    m.t._beaconFn := () => glow
    m.t._deathFn := () => (st.dead = 0 && MnWalks(m.io) >= 10) ? (st.dead := 1) : false
    m.t.Run(SchedCtx())
    AssertTrue(MnLogged(m, "minions: died (the death screen) with no bar in sight - fell off the island? That way (bearing ")
        && MnLogged(m, " ms out) is kept as the edge; no walk back by it"), "the fall logged")
    AssertTrue(!MnLogged(m, "back to the fight"), "no walk back by it")
    AssertTrue(MnLogged(m, "minions: fell off the island this way before (bearing "), "that way refused later")
    AssertEq(m.t._falls.Length, 1, "kept")
}

; the same death with the HP low: the minions, no fall. L46 15:11:03, HP 39%,
; bars 13 s old, a live fight on an open orb: no edge left at its spot
Test_Minions_HurtDeathIsNoFall() {
    m := MnTask(, Map("Minions.maxSec", 20))
    glow := [{x: 1280 + MinionsTask.GlowAim(1), y: 700, r: 20}]
    st := {dead: 0}
    m.t._beaconFn := () => glow
    m.t._hudFn := () => (h := MnNoPanel(), h.playerHp := 0.39, h)
    m.t._deathFn := () => (st.dead = 0 && MnWalks(m.io) >= 10) ? (st.dead := 1) : false
    m.t.Run(SchedCtx())
    AssertTrue(MnLogged(m, "minions: died (the death screen)"), "the death logged")
    AssertTrue(!MnLogged(m, "fell off the island"), "no fall")
    AssertEq(m.t._falls.Length, 0, "no edge kept")
}

; ---- the hand fights (clips 2026-11-03: 170608 Eden, 170827 Equinox, -------
; 171013 Luminosity, all three killed the orb) ------------------------------

MnShot(name) => MatchFileGrab(A_ScriptDir "\screens\" name)

; the bars of a crop as "w/full/fill ..."
MnFills(name, w, h) {
    s := ""
    for b in MnFrameScan(name, w, h)
        s .= (s = "" ? "" : " ") b.w "/" b.full "/" b.fill
    return s
}

; Night RAINY: the bars' yellow dims to d79c0a, FindBars read none of the
; hand fight; digits split a minion's bar with a 40 px gap; the fill read
; against the clip's digits while they showed (218, 79, 38, 12 of 300)
Test_Minions_RealHandFightBars() {
    AssertEq(MnFrameBars("minions_hand_eden_full.png", 440, 110).Length, 0, "FindBars alone: none")
    AssertEq(MnFills("minions_hand_eden_full.png", 440, 110), "128/128/1.00 230/234/0.98", "a minion through its digits and the full orb")
    AssertEq(MnFills("minions_hand_eden_three.png", 460, 140), "92/110/0.84 86/120/0.72 210/210/1.00", "two hurt minions and the orb")
    AssertEq(MnFills("minions_hand_eden_orb71.png", 280, 60), "118/164/0.72", "218 / 300")
    AssertEq(MnFills("minions_hand_eden_orb26.png", 360, 50), "50/190/0.26", "79 / 300")
    AssertEq(MnFills("minions_hand_eden_orb13.png", 380, 50), "24/188/0.13", "38 / 300")
    AssertEq(MnFills("minions_hand_eden_orb4.png", 380, 50), "8/192/0.04", "12 / 300: a stub on its plate")
    AssertEq(MnFrameScan("minions_hand_lum_orb.png", 220, 50).Length, 1, "STARFALL: the orb's far bar")
}

; the crops keep no screen y: put level with the player (Above; L71
; 04:05:52 had the level fight's minions at y 474-506)
Test_Minions_RealHandFightOrbIsTold() {
    v := MnScreenView("minions_hand_eden_three.png", 460, 140, 460)
    AssertEq(v.orb.w " " v.minions.Length, "210 2", "the widest bar, hurt minions beside it")
    AssertTrue(MinionsTask.Beside(v), "a hand fight's distance is beside it")
    v := MnScreenView("minions_hand_eden_orb4.png", 380, 50, 460)
    AssertEq(v.orb.full, 192, "nearly empty: the orb by its plate")
    AssertTrue(MinionsTask.Beside(v), "and still beside it")
}

; live 18:26 LOST FOREST (the first run of the hand-fight camera): the dark
; ground and a roof read as plate, the Locked 300 / 300 orb as 100/232, so
; 0.43 full and "beside it" from across the map
Test_Minions_RealForestBarsAreFull() {
    AssertEq(MnFills("minions_forest_orb_far.png", 360, 135), "100/100/1.00 68/68/1.00 74/74/1.00", "the orb and two minions, none hit")
    AssertEq(MnFills("minions_forest_three_far.png", 240, 70), "50/50/1.00 50/50/1.00 30/30/1.00", "far off: all full")
    AssertEq(MnFills("minions_far_forest_060322.png", 400, 160), "56/56/1.00 44/44/1.00 36/36/1.00", "the forest at dawn")
    ; the plate is opaque: read over bright ground too (46 / 100, 59 / 100)
    AssertEq(MnFills("minions_hurt_rainy_46.png", 520, 90), "110/110/1.00 140/152/0.92 120/264/0.45", "RAINY by day")
    AssertEq(MnFills("minions_hurt_snowy_59.png", 440, 110), "194/194/1.00 192/332/0.58", "SNOWY, over the sky")
    v := MinionsTask.View(MnFrameScan("minions_forest_orb_far.png", 360, 135))
    AssertEq(v.orb.w, 100, "the orb told")
    AssertEq(MinionsTask.Beside(v) MinionsTask.Beside(v, true) MinionsTask.Almost(v), "000", "far: walk on")
}

; L47 LOST FOREST: the plate shows through green, warm and light (2b1b00,
; 4f3521, 7b5941), unread it made a hurt orb as narrow as its HP: 1.00, and
; from 165532 on not even the orb. Fills against the plate's digits (164, 114,
; 83, 51 of 300; L48 SNOWY 180 of 300)
Test_Minions_RealPlateOverGreen() {
    AssertEq(MnFills("minions_plate_forest_55.png", 360, 100), "132/244/0.54", "164 / 300")
    AssertEq(MnFills("minions_plate_forest_38.png", 260, 100), "62/162/0.38", "114 / 300")
    AssertEq(MnFills("minions_plate_forest_28.png", 240, 100), "36/136/0.26", "83 / 300")
    AssertEq(MnFills("minions_plate_forest_17.png", 240, 110), "26/156/0.17", "51 / 300")
    AssertEq(MnFills("minions_plate_snowy_60.png", 340, 100), "142/240/0.59", "SNOWY as ever")
    AssertTrue(IsObject(MinionsTask.View(MnFrameScan("minions_plate_forest_17.png", 240, 110)).orb), "still the orb at 26 px of yellow")
}

; the loose read alone made false plates in the gold room (clip 22:45): as
; the strict read has them, no worse
Test_Minions_RealLoosePlateLeavesGoldAlone() {
    AssertEq(MnFills("minions_plate_gold_g084.png", 440, 240), "84/168/0.50 128/132/0.97 52/52/1.00 54/88/0.61", "no 52/180 stub by a minion")
    AssertEq(MnFills("minions_plate_gold_g096.png", 720, 230), "126/142/0.89 116/186/0.62", "no 126/182")
}

; a minion in the view: the orb is Locked, a low read of it is a misread
Test_Minions_NoOrbReadBesideAMinion() {
    two := [{x: 1280, y: 400, w: 10, full: 200, fill: "0.05"}, {x: 1100, y: 420, w: 120, full: 120, fill: 1}], n := 0
    m := MnTask()
    m.t._scanFn := () => (++n <= 3) ? two : []
    m.t.Run(SchedCtx())
    AssertTrue(!MnLogged(m, "the orb is down"), "no kill")
    AssertTrue(InStr(MnStatsOf(m), "orb_fill=-1 "), "no read: " MnStatsOf(m))
}

Test_Minions_StandingFacesTheMinionInReachFirst() {
    orb := {x: 1280, y: 100, w: 170, full: 170, fill: 1}
    far := {x: 1900, y: 500, w: 70}, near := {x: 700, y: 500, w: 90}, nearer := {x: 1800, y: 520, w: 110}
    a := MinionsTask.AimAt(MinionsTask.View([orb, near, nearer]))
    AssertEq(a.x, 1800, "the widest minion in reach")
    AssertEq(a.tol, MinionsTask.LockTol, "dead ahead")
    a := MinionsTask.AimAt(MinionsTask.View([orb, far]))
    AssertEq(a.x, 1900, "a far minion too: the orb takes nothing until they are dead")
    t := MinionsTask.TurnFor(1900, MinionsTask.LockTol, MinionsTask.LockPxPerMs)
    AssertEq(t.key " " t.ms, "Right 211", "a far side: 220 px short, the rest at the long turn's speed")
    t := MinionsTask.TurnFor(1500, MinionsTask.LockTol, MinionsTask.LockPxPerMs)
    AssertEq(t.ms, 100, "220 px at the short turn's real speed")
    t := MinionsTask.TurnFor(1400, MinionsTask.LockTol, MinionsTask.LockPxPerMs, 1195)
    AssertEq(t.key, "Right", "centred on screen is right of the character: turned on to the character's line")
    AssertEq(MinionsTask.TurnFor(1195, MinionsTask.LockTol, MinionsTask.LockPxPerMs, 1195).ms, 0, "on the character's line: aimed")
    a := MinionsTask.AimAt(MinionsTask.View([{x: 1000, y: 100, w: 170, full: 200, fill: 0.85}]))
    AssertEq(a.x, 1000, "minions dead: the orb")
}

; L72 SAND STORM 05:27-05:36: every minion read 1.00, so the lowest bar was
; faced, mostly one nearer the camera than the character (y 790-1014):
; behind its back, F and Q went the other way, 0 down in 244 s
Test_Minions_AimSkipsAMinionBehindTheCharacter() {
    ahead := {x: 1400, y: 640, w: 130}, behind := {x: 1100, y: 950, w: 278}
    AssertEq(MinionsTask.AimAt(MinionsTask.View([ahead, behind])).x, 1400, "the one ahead, not the lower one behind")
    AssertEq(MinionsTask.AimAt(MinionsTask.View([behind, ahead])).x, 1400, "whatever the order")
    hurt := {x: 900, y: 980, w: 200, full: 260, fill: 0.5}
    AssertEq(MinionsTask.AimAt(MinionsTask.View([ahead, hurt])).x, 1400, "ahead before a hurt one behind")
    AssertEq(MinionsTask.AimAt(MinionsTask.View([behind])).x, 1100, "only one behind: still that one")
    low := {x: 1300, y: 700, w: 120}
    AssertEq(MinionsTask.AimAt(MinionsTask.View([ahead, low, behind])).x, 1300, "ahead: the lowest as ever")
    AssertEq(MinionsTask.AimAt(MinionsTask.View([{x: 1500, y: 600, w: 100, full: 125, fill: 0.8}, low, ahead])).x, 1500, "ahead: the most hurt as ever")
    side := {x: 1700, y: 600, w: 130}             ; off the line: no F of its own
    AssertTrue(!MinionsTask.InFront(MinionsTask.View([{x: 1195, y: 900, w: 180}, side])), "dead on the line but behind: no F")
    AssertTrue(MinionsTask.InFront(MinionsTask.View([{x: 1195, y: 660, w: 140}, side])), "level with the character: F")
}

; the real frame (L72 bar_053528): the Golden Scarab at the player's side
; (97 / 100) reads level with the character, not behind it
Test_Minions_RealSandScarabBesideIsAhead() {
    bars := MnFrameScan("minions_sand_scarab_beside_x900_y440.png", 600, 260)
    low := ""
    for b in bars {
        b.x += 900, b.y += 440
        if (!IsObject(low) || b.y > low.y)
            low := b
    }
    AssertTrue(IsObject(low), "a bar")
    AssertEq(low.w, 136, "the scarab at the player's side")
    AssertTrue(low.y >= 640 && low.y <= 680, "level with the character: y " low.y)
    AssertTrue(!MinionsTask.Behind(low), "beside the character: not behind")
    a := MinionsTask.AimAt(MinionsTask.View([low, {x: 1180, y: 950, w: 278}]))
    AssertEq(a.x, low.x, "faced: the one beside, not one behind")
}

Test_Minions_BesideIsTheOrbsBar() {
    near := {x: 900, y: 500, w: 130}, near2 := {x: 1500, y: 520, w: 120}
    orb := {x: 1280, y: 100, w: 150, full: 150, fill: 1}
    AssertEq(MinionsTask.Beside(MinionsTask.View([orb, near, near2])), true, "a minion in reach counts, the orb far or not (the user, L52)")
    AssertEq(MinionsTask.Almost(MinionsTask.View([{x: 1280, y: 100, w: 100}, {x: 900, y: 500, w: 74}, {x: 1500, y: 520, w: 68}])), false, "not nearly either")
    AssertEq(MinionsTask.Beside(MinionsTask.View([near, near2])), true, "no orb in sight: a minion counts")
    v := MinionsTask.View([{x: 1280, y: 100, w: 100}, {x: 900, y: 500, w: 74}])
    AssertEq(v.orb.w, 100, "wider and higher: the orb, one minion by it")
}

Test_Minions_MinionsInReachStopTheWalk() {
    bars := [{x: 1280, y: 300, w: 200, full: 200, fill: 1}, {x: 1000, y: 700, w: 125}, {x: 1500, y: 700, w: 122}]
    v := MinionsTask.View(bars)
    AssertTrue(IsObject(v.orb), "the orb told")
    m := MnTask([bars])
    m.t.Run(SchedCtx())
    AssertTrue(MnSkills(m.io) >= 1, "cast where it stood")
    AssertTrue(MnLogged(m, "beside it (bar 125 px)"), "the first bars stop it: the w taps are the no-shift-lock aim")
}

Test_Minions_NoSkillBehindTheQuestPage() {
    m := MnTask()
    m.s.quest := true
    m.s.questDrop := 99
    r := m.t._Cast(SchedCtx(), {casts: 0, castEnd: 0, promptSaid: false}, MinionSkills("Eden", ""), "", false)
    AssertEq(r, 0, "no fight under it")
    AssertEq(QmObbyDowns(m.io, "f") + QmObbyDowns(m.io, "e") + QmObbyDowns(m.io, "t"), 0, "no skill")
}

Test_Minions_QuestPageClosedInTheFight() {
    old := MinionsTask.ViewCheckMs
    MinionsTask.ViewCheckMs := 0
    try {
        near := [{x: 1280, y: 680, w: 200}]
        m := MnTask(, , , MnLockIO())
        m.s.logName := "Eden"
        n := 0
        m.t._scanFn := () => (++n = 2 ? (m.s.quest := true) : 0, n <= 3 ? near : [])
        m.t.Run(SchedCtx())
        AssertTrue(MnLogged(m, "the quest screen is over the game"), "seen mid-hunt")
        AssertTrue(!m.s.State().quest, "closed")
    } finally {
        MinionsTask.ViewCheckMs := old
    }
}

Test_Minions_ALostPlateLooksForAMenuFirst() {
    old := MinionsTask.ViewCheckMs
    MinionsTask.ViewCheckMs := 999999
    try {
        near := [{x: 1280, y: 680, w: 200}]
        m := MnTask()
        m.s.logName := "Eden"
        n := 0
        m.t._scanFn := () => (++n = 4 ? (m.s.quest := true) : 0, n <= 3 ? near : [])
        m.t.Run(SchedCtx())
        AssertTrue(MnLogged(m, "the quest screen is over the game"), "seen, no 5 s wait")
        AssertTrue(!m.s.State().quest, "closed")
    } finally {
        MinionsTask.ViewCheckMs := old
    }
}

Test_Minions_NoEWhereTheBoardsPromptReads() {
    m := MnTask()
    b := MinionSkills("Eden", "")
    AssertEq(b.Next("", 0, false, "f"), "e", "F held back: E next")
    AssertEq(b.Next("", 0, false, "e"), "f", "E held back: F still")
    m.s.boardPrompt := true
    f := {casts: 0, castEnd: 0, promptSaid: false, standing: false, foes: []}
    book := {Next: (s, hud, now, close, no := "") => no = "e" ? "" : "e", CastMs: (s, k) => 0, Pressed: (s, k, hud, now) => 0}
    m.t._Cast(SchedCtx(), f, book, "", false)
    AssertTrue(MnLogged(m, "prompt is up - no E here"), "logged")
    AssertEq(QmObbyDowns(m.io, "e"), 0, "no E")
}

; a fill of 0.16 for a moment is no kill (live 18:26: 0.16, then 0.91)
Test_Minions_OneLowFillIsNoKill() {
    low := [{x: 1280, y: 400, w: 200, full: 200, fill: 1}], n := 0
    m := MnTask()
    m.t._scanFn := () => (++n, n = 3 ? [{x: 1280, y: 400, w: 200, full: 200, fill: "0.05"}] : n <= 3 ? low : [])
    m.t.Run(SchedCtx())
    AssertTrue(!MnLogged(m, "the orb is down"), "no kill by one read")
    AssertTrue(InStr(MnStatsOf(m), "orb_down=0 "), "orb_down=0")
}

; panels are bottom aligned, translucent: the key box's border was too
; dim for KeyIn at night and every row read "no skill"
Test_Minions_RealHandFightPanels() {
    p := MnPanel("hand_panel_eden_night.png")
    AssertEq(MnCds(p), "T:0 F:0.32 E:0 Q:0 R:0.93 V:0.81", "Eden at night, t=50: F, R, V cooling down")
    p := MnPanel("hand_panel_equinox.png")
    AssertEq(MnCds(p), "T:- F:- E:- Q:0.89 R:0.62 V:0.19", "Equinox: the three lowest rows")
    b := MinionSkills("Equinox", p)
    AssertEq(b.rowOf["e"] b.rowOf["t"] b.rowOf["r"], "456", "E T R")
    p := MnPanel("hand_panel_luminosity.png")
    AssertEq(MnCds(p), "T:- F:0.64 E:0.38 Q:0 R:0.56 V:0.34", "Luminosity: the five lowest rows")
    b := MinionSkills("Luminosity", p)
    AssertEq(b.rowOf["f"] b.rowOf["t"] b.rowOf["q"] b.rowOf["r"] b.rowOf["e"], "23456", "F T Q R E")
}

; a real V: hollow, its middle ~3 px left of the centre; an E cut off by
; the grab has its stem on top: no V. Deadeye rides on this
Test_Minions_RealRankVAtNight() {
    AssertEq(MinionsTask.Rank(MnShot("eden_bar_88_rank_v_night.png"), 985, 1080), "V", "V at 88")
    AssertEq(MinionsTask.Rank(MnShot("eden_bar_10_rank_v_night.png"), 985, 1080), "V", "V after Deadeye, 10 points")
    AssertEq(MinionsTask.Rank(MnShot("eden_bar_68_rank_e_cut.png"), 985, 1080), "?", "E, its top off the grab")
    AssertEq(MinionsTask.Rank(MnShot("eden_bar_27_rank_c_night.png"), 985, 1080), "?", "C")
    AssertEq(MinionsTask.Points(MnShot("eden_bar_88_rank_v_night.png"), 985, 1080), 88, "the Charge")
}

; the user's clip 20261108 123642 (day, snow): the ground behind the V as
; white as its outline (its top rows lost, then too narrow for a V: "?"), a
; hair streak at x 1251..1255 joining its top. B over Eden's swirl and A by
; day stay no V: Deadeye rides on this
Test_Minions_RealRankVByDay() {
    AssertEq(MinionsTask.Rank(MnShot("eden_bar_90_rank_v_day_snow.png"), 985, 1080), "V", "V, its outer edge in the snow")
    AssertEq(MinionsTask.Rank(MnShot("eden_bar_90_rank_v_day.png"), 985, 1080), "V", "V by day")
    AssertEq(MinionsTask.Rank(MnShot("eden_bar_0_rank_v_day.png"), 985, 1080), "V", "V after Deadeye, 0 points")
    AssertEq(MinionsTask.Rank(MnShot("eden_bar_75_rank_a_day.png"), 985, 1080), "?", "A by day")
    AssertEq(MinionsTask.Rank(MnShot("eden_bar_100_rank_b_swirl.png"), 985, 1080), "?", "B over the swirl")
    AssertEq(MinionsTask.Points(MnShot("eden_bar_90_rank_v_day_snow.png"), 985, 1080), 90, "the Charge")
}

Test_Minions_RealToasts() {
    for a in ["eden", "equinox", "luminosity"] {
        AssertEq(MinionsTask.Toast(MnShot("minions_toast_orb_" a ".png"), 2016, 1005), "orb", a ": Orb Awards")
        AssertEq(MinionsTask.Toast(MnShot("minions_toast_minion_" a ".png"), 2016, 1005), "minion", a ": Orb Minion Awards")
    }
    AssertEq(MinionsTask.Toast(MnShot("hand_panel_equinox.png"), 2016, 1005), "minion", "t=26: the Starfish toasts still up")
    for f in ["hand_panel_eden_night.png", "hand_panel_luminosity.png", "minions_toast_none_flash.png"]
        AssertEq(MinionsTask.Toast(MnShot(f), 2016, 1005), "", f ": none")
    AssertEq(MinionsTask.Toast(MnShot("eden_panel_toast_snowy.png"), 2016, 1004), "", "the potion toast is no award")
}

Test_Minions_ViewAndBeside() {
    orb := {x: 1280, y: 300, w: 60, full: 200, fill: 0.3}, mn := {x: 900, y: 500, w: 70, full: 110}
    v := MinionsTask.View([mn, orb])
    AssertTrue(v.orb == orb && v.anchor == mn, "the orb by its full width, hurt or not; at it, on to the minion")
    v := MinionsTask.View([{x: 900, y: 500, w: 70}, {x: 1500, y: 520, w: 80}])
    AssertEq(v.orb, "", "two like bars: no orb told")
    AssertEq(v.anchor.x, 1500, "the nearest minion ahead")
    far := MinionsTask.View([{x: 1280, y: 500, w: 100}])
    AssertEq(MinionsTask.Beside(far), false, "the orb far (a lone bar)")
    AssertEq(MinionsTask.Almost(MinionsTask.View([{x: 1280, y: 500, w: 150}])), true, "nearly")
    AssertEq(MinionsTask.Beside(MinionsTask.View([{x: 1280, y: 500, w: 165}])), false, "not yet")
    AssertEq(MinionsTask.Beside(MinionsTask.View([{x: 1280, y: 500, w: 165}]), true), true, "standing: it may drift")
    AssertEq(MinionsTask.Close(MinionsTask.View([{x: 1, y: 600, w: 200}, {x: 3, y: 600, w: MinionsTask.BesideMinionW}])), true, "a minion close")
    AssertEq(MinionsTask.FillOf({w: 5}), 1, "no plate read: full")
}

Test_Minions_StatsLine() {
    AssertEq(MinionsTask.Stats(4, 4, 1, 62000, 0, 0, 1, 21, "0.04", 1, "toast")
        , "minions: stats seen=4 down=4 waits=1 hunt_ms=62000 left=0 orb_left=0 orb_down=1 casts=21 orb_fill=0.04 deaths=1 how=toast", "a kill")
    AssertEq(MinionsTask.Stats(0, 0, 0, 5, 2, 1, 0, 0, "", 0, "", 1)
        , "minions: stats seen=0 down=0 waits=0 hunt_ms=5 left=2 orb_left=1 orb_down=0 casts=0 orb_fill=-1 deaths=0 boss=1", "none, the boss")
}

; ---- the skill book --------------------------------------------------------

; six panel rows from a key list ("" = no row) with cds
MnHudOf(keys, cds := "") {
    rows := []
    for k in keys
        rows.Push(k = "" ? "" : {cd: (cds is Map && cds.Has(k)) ? cds[k] : 0})
    return {rows: rows, points: -1, rank: ""}
}

; Next and Pressed at t; t moved past the cast
MnBookPress(b, hud, &t, close := false) {
    k := b.Next(hud, t, close)
    if (k != "") {
        b.Pressed(k, hud, t)
        t += b.CastMs(k)
    }
    return k
}

Test_Minions_BookEdenPriority() {
    t := 0, b := MinionSkills("Eden", "")
    AssertEq(b.how, "panel", "Eden's layout known")
    ; both ready: E, then F (FirstOfFE; was F, then E)
    AssertEq(MnBookPress(b, MnHud(, 0), &t), "e", "E before Taunt")
    AssertEq(MnBookPress(b, MnHud(, 0), &t), "f", "then F")
    AssertEq(MnBookPress(b, MnHud(, 0), &t), "t", "then T")
    AssertEq(b.Next(MnHud(, 0), t), "", "Q only with a minion in reach")
    AssertEq(b.Next(MnHud(, 0), t, true), "q", "Q then")
    t := 0, b := MinionSkills("Eden", "")
    AssertEq(b.Next(MnHud(, 29), t), "e", "29 Charge: no Voidrush")
    AssertEq(b.Next(MnHud(, 30), t), "e", "30 Charge: F and E before Voidrush")
    AssertEq(b.Next(MnHud(, 30, "V"), t), "r", "rank V: Deadeye first")
    AssertEq(b.Next(MnHud(, 100, "?"), t), "e", "no V read: never Deadeye")
    h := MnHud(, 100), h.air := true
    AssertEq(b.Next(h, t), "e", "off the ground: no Voidrush")
    ; T whatever the Charge, before Voidrush
    cds := Map("f", 0.5, "e", 0.5, "v", 0.5)
    AssertEq(b.Next(MnHud(cds, 90), t), "t", "T when nothing else is ready")
}

; c1: a cooldown starts when the cast ends, an empty row in a channel is
; not ready
Test_Minions_BookWaitsOutTheCast() {
    b := MinionSkills("Eden", ""), hud := MnHud(, 0)
    b.Pressed("f", hud, 1000)
    AssertEq(b.CastMs("f"), 2800, "F's channel")
    AssertEq(b.Next(hud, 3700), "", "mid-cast: nothing, every row empty")
    AssertTrue(b.Casting(3700), "casting")
    AssertEq(b.Next(hud, 3800), "e", "after it: the next")
    AssertEq(b.Rooted(1000), false, "F does not root")
    b.Pressed("r", MnHud(, 80, "V"), 4000)
    AssertTrue(b.Rooted(4000 + b.CastMs("r") - 1), "Deadeye: no movement")
    AssertEq(b.Rooted(4000 + b.CastMs("r")), false, "then free")
}

Test_Minions_BookCooldowns() {
    AssertEq(MinionSkills("Eden", "").CastMs("v"), 4800, "Voidrush")
    c := MinionsTask.Auras["eden"].cool
    AssertEq(c["t"] " " c["f"] " " c["e"] " " c["q"] " " c["v"] " " c["r"], "8000 10000 6000 3000 60000 40000", "clip 170608 section 3")
    b := MinionSkills("Equinox", ""), hud := MnHudOf(["", "", "", "e", "t", "r"])
    b.Pressed("r", hud, 0)
    ; the overlay late (a full row has no edge): the clock holds it
    AssertEq(b.Next(hud, 3000), "t", "R held by its clock, T next")
    AssertEq(b._Ready("r", hud, 19000), false, "not before cast + 20 s")
    AssertEq(b._Ready("r", hud, 23000), true, "then ready")
    ; the overlay read sets the time left
    b := MinionSkills("Equinox", ""), b.Pressed("t", hud, 0)
    b.Next(MnHudOf(["", "", "", "e", "t", "r"], Map("t", 0.5)), 10000)
    AssertEq(b._Ready("t", hud, 19999), false, "half of 20 s left at 10 s")
    AssertEq(b._Ready("t", hud, 20000), true, "gone at 20 s")
}

; a press that showed nothing (no overlay, no Charge moved): free again
Test_Minions_BookFailedPressIsFreeAgain() {
    b := MinionSkills("Eden", ""), hud := MnHud(, 40)
    b.Pressed("f", hud, 0)
    b.Next(hud, 2800 + MinionSkills.ConfirmMs)
    AssertEq(b._Ready("f", hud, 2800 + MinionSkills.ConfirmMs), false, "not at once")
    AssertEq(b._Ready("f", hud, 2800 + MinionSkills.ConfirmMs + MinionSkills.RetryMs), true, "after RetryMs")
    ; rows unread (a flash): the clock runs on
    b := MinionSkills("Eden", ""), b.Pressed("f", hud, 0)
    blind := {rows: "", points: -1, rank: ""}
    b.Next(blind, 9000)
    AssertEq(b._Ready("f", blind, 9000), false, "no row read: still its cooldown")
}

; the user, 2026-11-06: the walk kept going back to the leaderboard
Test_Minions_PatrolGoesWhereItHasNotSearched() {
    at := {x: 0, y: 0}, ms := MinionsTask.PatrolSteps * MinionsTask.WalkMs
    s := Map()
    first := MinionsTask.PatrolHeading(at, s, [], 0)
    u := MinionsTask.Way(first)
    s[MinionsTask.Cell({x: u.x * ms, y: u.y * ms})] := 3
    AssertTrue(MinionsTask.PatrolHeading(at, s, [], 0) != first, "searched: another way")
    far := {x: 8000, y: 0}
    u := MinionsTask.Way(MinionsTask.PatrolHeading(far, Map(), [], 0))
    AssertTrue(Sqrt((far.x + u.x * ms) ** 2 + (far.y + u.y * ms) ** 2) <= MinionsTask.PatrolRadiusMs, "stays near spawn")
    fall := [{x: 0, y: 2000, b: 0, at: 0}]
    AssertTrue(MinionsTask.PatrolHeading(at, Map(), fall, 0) != 0, "not at a remembered fall")
}

; L47 16:50:30: the orb at 0.05, its bar too short to read, a look round lost the kill
Test_Minions_OrbNearlyDeadIsStayedOn() {
    f := {casts: 3, orbFill: 0.05, orbAt: 1000, down: 3, boss: false}
    AssertTrue(MinionsTask.OrbNearlyDead(f, 1000 + MinionsTask.OrbLowMs - 1), "bars gone a while: stay")
    AssertTrue(!MinionsTask.OrbNearlyDead(f, 1000 + MinionsTask.OrbLowMs), "too long: look again")
    f.orbFill := 0.9
    AssertTrue(!MinionsTask.OrbNearlyDead(f, 1000), "a healthy orb: as before")
    f.orbFill := 0.05, f.casts := 0
    AssertTrue(!MinionsTask.OrbNearlyDead(f, 1000), "no skill on it yet: a far low bar is walked to")
    f.casts := 3, f.down := 2
    AssertTrue(!MinionsTask.OrbNearlyDead(f, 1000), "minions left: a false read forces no stand")
    ; L72 05:03:27-35: 0.15, 1.00, 0.06; the orb has no regen, one read jumps
    f.down := 3, f.orbReads := []
    for r in [0.15, 1.00]
        MinionsTask.OrbRead(f, r)
    f.orbFill := 1.00
    AssertTrue(MinionsTask.OrbNearlyDead(f, 1000), "0.15 then 1.00: still nearly dead")
    for r in [0.9, 0.95, 1.00]
        MinionsTask.OrbRead(f, r)
    AssertEq(MinionsTask.OrbHp(f), 0.9, "only the last OrbHpReads reads")
    AssertTrue(!MinionsTask.OrbNearlyDead(f, 1000), "a low misread long gone: as before")
}

; the user, L52: every skill from long range. Beside the orb with the minions
; still far is not in reach of them: walk on to them first
Test_Minions_WideOrbWithFarMinionsIsNotBeside() {
    orb := {x: 1200, y: 300, w: 230}, far := {x: 1500, y: 320, w: 60}, near := {x: 1500, y: 520, w: 130}
    v := MinionsTask.View([orb, far])
    AssertTrue(!MinionsTask.Beside(v), "minions far: not beside")
    AssertEq(v.anchor.x, far.x, "the walk goes to the minion")
    AssertTrue(MinionsTask.Beside(MinionsTask.View([orb, near])), "a minion in reach: beside")
    AssertTrue(MinionsTask.Beside(MinionsTask.View([orb])), "the orb alone, wide: beside")
    AssertTrue(!MinionsTask.Beside(MinionsTask.View([{x: 1200, y: 300, w: 165}])), "164-184 px was too far (L52 09:51)")
    AssertTrue(!MinionsTask.InReach(MinionsTask.View([{x: 1200, y: 300, w: 140}, {x: 900, y: 320, w: 90}])), "no skill at a 90 px minion")
}

; L71 crops (2560x1440 frames; the name keeps the crop's x, y): Scan's bars
; moved back to the screen's y, then View
MnScreenView(name, w, h, top) {
    bars := MnFrameScan(name, w, h)
    for b in bars
        b.y += top
    return MinionsTask.View(bars)
}

; Above on real frames: a SNOWY rooftop orb (02:47:14, ~10 casts at it, fill
; 1.00), the orb on a HEAVEN terrace over the player (03:04:24, then "beside"
; a 144 px bar at y 392 and no hurt), a level RAINY fight (04:05:52: the orb
; 168 px over minions of 108 / 120 px, beside one at y 486 right after)
Test_Minions_AboveOnRealFrames() {
    v := MnScreenView("minions_above_snowy_roof_orb_x1060_y60.png", 230, 100, 60)
    AssertEq(MnBarsShow(v.minions.Length ? v.minions : [v.orb]), "110,108 w144 h10", "the rooftop orb's bar")
    AssertTrue(MinionsTask.Above(v.orb, true), "the rooftop orb: above")
    AssertTrue(!MinionsTask.InReach(v) && !MinionsTask.Beside(v, true), "no casts at it, no stand")
    v := MnScreenView("minions_above_heaven_terrace_x1560_y280.png", 200, 90, 280)
    AssertTrue(MinionsTask.Above(v.anchor) && MinionsTask.Above({y: 392}), "the terrace's bars: above for a minion")
    ; the orb on that terrace, 03:01:36 (2 casts, fill 1.00): 150 px at y 322,
    ; too near the level orb's 358 for AboveOrbY; Locked: no casts on the walk
    v := MnScreenView("minions_above_heaven_orb_x1880_y280.png", 380, 160, 280)
    AssertEq(v.orb.y " " v.orb.w, "322 150", "the terrace orb's bar")
    AssertTrue(!MinionsTask.InReach(v, true) && !MinionsTask.Beside(v), "Locked: not in reach, not beside")
    v := MnScreenView("minions_level_rainy_fight_x520_y320.png", 580, 220, 320)
    AssertTrue(IsObject(v.orb) && !MinionsTask.Above(v.orb, true), "the level orb: not above")
    for b in v.minions
        if (b.w >= 100)
            AssertTrue(!MinionsTask.Above(b), "a level minion (" b.w " px at y " b.y "): not above")
    AssertTrue(MinionsTask.Beside(v) && MinionsTask.InReach(v) && MinionsTask.Close(v), "the 120 px minion level with the player: beside")
}

; Fakes: a bar above the player is neither beside, in reach nor close, the
; lone open bar and the nearly dead orb too; a Locked orb alone is not in
; reach for casts on the walk
Test_Minions_AboveIsNotBesideNorInReach() {
    terrace := {x: 1200, y: 424, w: 122, full: 122, h: 6}     ; RAINY 02:59:00
    level := {x: 1200, y: 600, w: 122, full: 122, h: 8}
    orb := {x: 1100, y: 250, w: 200}
    AssertTrue(!MinionsTask.Beside(MinionsTask.View([orb, terrace])), "the terrace minion: not beside")
    AssertTrue(!MinionsTask.Beside(MinionsTask.View([orb, terrace]), true), "... nor standing")
    AssertTrue(!MinionsTask.InReach(MinionsTask.View([orb, terrace])), "... nor in reach")
    AssertTrue(!MinionsTask.Close(MinionsTask.View([orb, terrace])), "... nor close")
    AssertTrue(MinionsTask.Beside(MinionsTask.View([orb, level])), "level: beside")
    roof := {x: 1170, y: 108, w: 144, full: 144}               ; SNOWY 02:47:14
    AssertTrue(!MinionsTask.InReach(MinionsTask.View([roof])), "the rooftop orb: not in reach")
    AssertTrue(!MinionsTask.Beside(MinionsTask.View([{x: 1170, y: 126, w: 6, full: 328}], true)), "the lone open bar up there: not beside")
    AssertTrue(MinionsTask.Beside(MinionsTask.View([{x: 1170, y: 520, w: 6, full: 328}], true)), "level: beside")
    near := {x: 1200, y: 360, w: 150, full: 150}
    AssertTrue(MinionsTask.InReach(MinionsTask.View([near])), "an orb alone almost beside: in reach")
    AssertTrue(!MinionsTask.InReach(MinionsTask.View([near]), true), "... Locked: no casts on the walk")
}

; the RAINY terrace (02:58:56-02:59:16): walking got no closer to a 122 px
; minion at y 424, then "beside it" and 5 casts at it. Now: no cast, the
; Escapes and the wall's slide
Test_Minions_TerraceMinionAboveGetsNoCasts() {
    m := MnTask([[{x: 1400, y: 250, w: 200}, {x: 1280, y: 424, w: 122, full: 122, h: 6}, {x: 1300, y: 410, w: 110}]])
    m.t.CanRun(m.state)
    m.t.Run(SchedCtx())
    AssertTrue(!MnLogged(m, "beside it") && !MnLogged(m, "a minion in the way"), "not beside, no stand")
    AssertEq(MnSkills(m.io), 0, "no skill at it")
    AssertTrue(MnLogged(m, "walking got no closer"), "the Escapes")
    AssertTrue(MnLogged(m, "wall - sliding"), "the wall's way up")
}

; by hand F, E, T, V, rank V, Deadeye: V last on the chain, T straight before it
Test_Minions_BookVoidrushAfterTheChain() {
    b := MinionSkills("Eden", "")
    AssertEq(b.Next(MnHud(, 40), 0), "e", "E first (then F), Voidrush or not")
    AssertEq(b.Next(MnHud(Map("e", 0.5), 40), 0), "f", "then F")
    AssertEq(b.Next(MnHud(Map("f", 0.5), 40), 0), "e", "E alone")
    AssertEq(b.Next(MnHud(Map("f", 0.5, "e", 0.5), 40), 0), "t", "then T, with Charge for V")
    gone := Map("f", 0.5, "e", 0.5, "t", 0.5)
    AssertEq(b.Next(MnHud(gone, 40), 0), "v", "then Voidrush")
    AssertEq(b.Next(MnHud(gone, 30), 0), "v", "30 Charge: enough")
    AssertEq(b.Next(MnHud(gone, 29), 0), "", "too little Charge: none")
    AssertEq(b.Next(MnHud(gone, 100), 0, false, "v"), "", "held back: none, whatever the Charge")
    AssertEq(b.Next(MnHud(gone, 100), 0, true, "v"), "q", "held back, a minion close: Q")
    h := MnHud(gone, 100), h.air := true
    AssertEq(b.Next(h, 0), "", "off the ground: no Voidrush")
    AssertEq(b.Next(MnHud(, 40, "V"), 0), "r", "rank V: Deadeye before all, minions or not")
}

; a book-only fight of ms: the panel's overlays from the presses (as
; MnArena's Hud), Charge 50, no rank. -> [{k, at, end}]
MnBookFight(b, ms, close, no := "") {
    cool := MinionsTask.Auras["eden"].cool, cdEnd := Map(), castEnd := 0, casts := [], t := 0
    while (t <= ms) {
        rows := []
        for k in ["t", "f", "e", "q", "r", "v"]
            left := cdEnd.Get(k, 0) - t, rows.Push({cd: (left > 0 && t >= castEnd) ? Round(left / cool[k], 2) : 0})
        hud := {rows: rows, points: 50, rank: ""}
        if ((k := b.Next(hud, t, close, no)) != "") {
            b.Pressed(k, hud, t)
            castEnd := t + b.CastMs(k), cdEnd[k] := castEnd + cool[k]
            casts.Push({k: k, at: t, end: castEnd})
        }
        t += 100
    }
    return casts
}

; the longest wait from a damaging cast's end to the next one's start
MnBookGap(casts) {
    gap := 0, last := ""
    for c in casts
        if InStr("feqrv", c.k) {
            if IsObject(last)
                gap := Max(gap, c.at - last.end)
            last := c
        }
    return gap
}

; L71-L77: the rank lapses 3.5-4 s after the last hit (a cast <= 3 s after
; a ranked one kept it 89 of 122, >= 5 s 10 of 107). A minion in reach:
; Impale fills the gaps F and E leave; the orb alone (Locked: no V): none
Test_Minions_BookImpaleFillsTheGap() {
    casts := MnBookFight(MinionSkills("Eden", ""), 60000, true, "v")
    s := ""
    for c in casts
        s .= c.k
    gap := MnBookGap(casts)
    AssertTrue(gap <= 3500, "a minion in reach: no gap over 3.5 s between damaging casts (" gap " ms): " s)
    AssertTrue(InStr(s, "q") && InStr(s, "f") && InStr(s, "e") && InStr(s, "t"), "Q fills, F, E and T still go: " s)
    AssertEq(SubStr(s, 1, 2), "ef", "E, then F")
    alone := MnBookFight(MinionSkills("Eden", ""), 60000, false, "v")
    s := ""
    for c in alone
        s .= c.k
    AssertTrue(!InStr(s, "q"), "no minion in reach: never Q: " s)
    ; T lands no hit: Q before it
    b := MinionSkills("Eden", "")
    AssertEq(b.Next(MnHud(Map("f", 0.5, "e", 0.5), 40), 0, true, "v"), "q", "F and E cooling, T ready: Q first")
    AssertEq(b.Next(MnHud(Map("f", 0.5, "e", 0.5, "q", 0.5), 40), 0, true, "v"), "t", "Q cooling too: T")
}

; F 2.8 s + 10 s, E 1 s + 6 s: F ready with E back soon waits for E, so
; E's cooldown runs under F's channel and not after it
Test_Minions_BookFWaitsForE() {
    hud := MnHud(, 40), eCd := (ms) => MnHud(Map("e", Round(ms / 6000, 2), "t", 0.5), 0)     ; T cooling: it may go in the wait
    b := MinionSkills("Eden", ""), b.Pressed("e", hud, 0)          ; E back at 7000
    AssertEq(b.Next(eCd(3000), 4000), "f", "E back in 3 s: F now")
    b := MinionSkills("Eden", ""), b.Pressed("e", hud, 0)
    AssertEq(b.Next(eCd(1000), 6000), "", "E back in 1 s: F waits")
    AssertEq(b.Next(eCd(1000), 6000, true), "q", "... Q meanwhile, a minion in reach")
    AssertEq(b.Next(hud, 7100), "e", "E, then F")
    b.Pressed("e", hud, 7100)
    AssertEq(b.Next(eCd(6000), 8100), "f", "F")
    ; an E overlay that never ends (a misread) holds F EWaitMs at most
    b := MinionSkills("Eden", ""), stuck := MnHud(Map("e", 0.1, "t", 0.5), 0)
    AssertEq(b.Next(stuck, 0), "", "E 600 ms off: F waits")
    AssertEq(b.Next(stuck, MinionSkills.EWaitMs), "f", "not longer than EWaitMs")
    AssertEq(MinionSkills("Eden", "").Next(stuck, 0, false, "e"), "f", "E held back: F at once")
}

; Impale's reach: a minion in reach (AimMinionW, not above), not behind
; the character; never the orb alone
Test_Minions_QReach() {
    orb := {x: 1280, y: 300, w: 200}, mk := (w, y) => {x: 1195, y: y, w: w, full: w}
    AssertTrue(MinionsTask.QReach(MinionsTask.View([orb, mk(MinionsTask.AimMinionW, 600)])), "a level minion in reach")
    AssertTrue(!MinionsTask.QReach(MinionsTask.View([orb, mk(MinionsTask.AimMinionW - 5, 600)])), "too far")
    AssertTrue(!MinionsTask.QReach(MinionsTask.View([orb, mk(130, 424)])), "above the player")
    AssertTrue(!MinionsTask.QReach(MinionsTask.View([orb, mk(130, MinionsTask.BehindY + 20)])), "behind the character")
    AssertTrue(!MinionsTask.QReach(MinionsTask.View([orb])), "the orb alone")
    AssertTrue(!MinionsTask.QReach(MinionsTask.View([{x: 1200, y: 360, w: 230}])), "the orb alone, beside")
}

; L44-L51: 6 of 11 V went into a Locked orb, 3 s after the last minion bar:
; no bar is no proof, the orb told open is (Open: f.down)
Test_Minions_VoidrushOnlyOnTheOpenOrb() {
    press := (down, boss := false) => (m := MnTask(), m.t._lock := true
        , f := {foes: [], down: down, boss: boss, casts: 0, castEnd: 0, promptSaid: false}
        , m.t._Press(SchedCtx(), f, MinionSkills("Eden", ""), MnHud(Map("f", 0.5, "e", 0.5, "t", 0.5), 100, "C"), false)
        , m)
    AssertEq(MnDowns(press(MinionsTask.OpenDown - 1).io, "v"), 0, "no minion in sight, the orb not open: no Voidrush")
    m := press(MinionsTask.OpenDown)
    AssertEq(MnDowns(m.io, "v"), 1, "open: Voidrush")
    AssertTrue(MnLogged(m, "minions: skill v (points 100) rank C"), "the rank on the skill's line")
    AssertEq(MnDowns(press(0, true).io, "v"), 1, "a boss is not Locked")
    ; L66 + L71: a V among minions, the HP at 45% or under 2-4 s on (04:48:28
    ; -> 37%, dead 04:48:46): no V with a minion in sight, ahead or not, the
    ; F held for one off to the side as before
    near := (isAhead, down := 0) => (m := MnTask(), m.t._lock := true
        , f := {foes: [{x: 1195, y: 600, w: 120, full: 120}], ahead: isAhead, down: down, boss: false, casts: 0, castEnd: 0, promptSaid: false}
        , m.t._Press(SchedCtx(), f, MinionSkills("Eden", ""), MnHud(Map("f", 0, "e", 0.5, "t", 0.5), 100, "C"), false)
        , m)
    m := near(true)
    AssertEq(MnDowns(m.io, "v"), 0, "a minion ahead: no Voidrush")
    AssertEq(MnDowns(m.io, "f"), 1, "a minion ahead: F")
    m := near(false)
    AssertEq(MnDowns(m.io, "v"), 0, "a minion off to the side: no Voidrush")
    AssertEq(MnDowns(m.io, "f"), 0, "a minion off to the side: F held")
    AssertEq(MnDowns(near(true, MinionsTask.OpenDown).io, "v"), 0, "toasts say open, a minion in sight: no Voidrush")
}

; points unread through a flash: the last read counts a while
Test_Minions_BookKeepsTheChargeThroughAFlash() {
    b := MinionSkills("Eden", "")
    t := 0
    MnBookPress(b, MnHud(, 50), &t), MnBookPress(b, MnHud(, 50), &t), MnBookPress(b, MnHud(, 50), &t)     ; F, E and T go first
    b.Next(MnHud(, 50), t)
    AssertEq(b.Next({rows: "", points: -1, rank: ""}, t + 1000), "v", "50 read a second ago")
    AssertTrue(b.Next({rows: "", points: -1, rank: ""}, t + 1000 + MinionSkills.PointsKeepMs) != "v", "too old: no Voidrush")
}

Test_Minions_BookEquinoxAndLuminosityOrder() {
    t := 0, b := MinionSkills("Equinox", "")
    hud := MnHudOf(["", "", "", "e", "t", "r"])
    s := ""
    Loop 3
        s .= MnBookPress(b, hud, &t)
    AssertEq(s, "rte", "Equinox: R T E")
    t := 0, b := MinionSkills("Luminosity", "")
    hud := MnHudOf(["", "f", "t", "q", "r", "e"])
    s := ""
    Loop 4
        s .= MnBookPress(b, hud, &t)
    AssertEq(s, "fetr", "Luminosity: F E T R")
    AssertEq(MnBookPress(b, hud, &t), "", "never Q (a dash, no damage)")
}

Test_Minions_KeysPerAura() {
    AssertEq(MinionsTask._Join(MinionsTask.KeysFor("Equinox")), "r t e", "Equinox")
    AssertEq(MinionsTask.KeysFor("Glock").Length, 6, "any other: every letter")
}

; an unknown aura's rows learnt: a key's row is the one whose cooldown
; starts after it, at the end of its cast; a key without a row dropped
Test_Minions_BookLearnsAnUnknownAura() {
    rows := ["", "", "", "", {cd: 0}, {cd: 0}], learnt := Map()
    b := MinionSkills("Glock", rows, learnt)
    AssertEq(b.how, "learn", "learning")
    cd := (a, c) => {rows: ["", "", "", "", {cd: a}, {cd: c}], points: -1, rank: ""}
    t := 0, k := b.Next(cd(0, 0), t)
    AssertEq(k, "e", "the first letter")
    b.Pressed(k, cd(0, 0), t)
    AssertEq(b.Next(cd(0, 0), t + 3000), "", "one at a time until its row shows")
    t := 3500, k := b.Next(cd(0.9, 0), t)
    AssertEq(b.rowOf["e"], 5, "E's row")
    AssertEq(k, "r", "the next letter")
    b.Pressed(k, cd(0.9, 0), t)
    b.Next(cd(0.9, 0), t + MinionSkills.LearnMs)
    t += MinionSkills.LearnMs + 4000, b.Next(cd(0.5, 0), t)
    b.Pressed("r", cd(0.5, 0), t)
    b.Next(cd(0.5, 0), t + MinionSkills.LearnMs)
    AssertTrue(b._dead.Has("r"), "R started nothing twice: dropped")
    b2 := MinionSkills("Glock", rows, learnt)
    AssertEq(b2.rowOf["e"], 5, "kept for the next hunt")
}

Test_Minions_BookWithoutAPanel() {
    b := MinionSkills("Glock", "")
    AssertEq(b.how, "keys", "no row read: every letter")
    t := 0, seen := ""
    Loop 6 {
        k := b.Next("", t)
        seen .= k
        b.Pressed(k, "", t)
        t += b.CastMs(k)
    }
    AssertEq(seen, "ertfqv", "in turn, a cast apart")
}

; ---- the fight -------------------------------------------------------------

; a look at a hunt that stands: m's io log has no step after index i
MnSteps(io, from := 1) {
    n := 0
    for i, e in io.log
        if (i >= from && RegExMatch(e, "^down [wasd]$"))
            n++
    return n
}

; the camera recipe (live 2026-11-03): pitch, zoom out, five notches in,
; pitch back, in that order, no click
Test_Minions_FightCameraRecipe() {
    io := MnLockIO()
    m := MnTask(, , , io)
    m.t._lock := true
    AssertTrue(m.t._FightCamera(SchedCtx()), "done")
    s := ""
    for e in io.log
        if RegExMatch(e, "^(look|wheel)")
            s .= (e = (s != "" ? SubStr(s, InStr(s, "`n", , -2) + 1, -1) : "") ? "" : e "`n")
    AssertEq(RTrim(s, "`n"), "look 0,80`nwheel down 1`nwheel up 1`nlook 0,-10", "the steps in order")
    n := Map()
    for e in io.log
        n[e] := n.Get(e, 0) + 1
    AssertEq(n["look 0,80"] " " n["wheel down 1"] " " n["wheel up 1"] " " n["look 0,-10"], "5 25 5 17", "the counts")
    AssertEq(io.Clicks(), 0, "no click")
    AssertEq(io.locked, 0, "none with the lock on")
}

Test_Minions_FightCameraNeedsShiftLock() {
    m := MnTask()
    m.t._lock := false
    AssertTrue(m.t._FightCamera(SchedCtx()), "goes on")
    AssertEq(m.io.Index("look 0,80"), 0, "mouse pitch does nothing without it: not sent")
    AssertTrue(MnLogged(m, "no shift lock - the camera left as it is"), "logged")
}

; at the hunt's start with the lock on, before any skill, and after a death
Test_Minions_FightCameraAtTheStartAndAfterADeath() {
    io := MnLockIO()
    m := MnTask(, , , io)
    near := [{x: 1280, y: 680, w: 200}], dead := false
    m.t._scanFn := () => dead ? [] : near
    m.t._deathFn := () => (!dead && MnSkills(io) >= 2) ? (dead := true) : false
    m.t.Run(SchedCtx())
    n := 0, first := 0
    for i, e in io.log
        if (e = "look 0,80" && (first := first ? first : i))
            n++
    AssertEq(n, 2 * MinionsTask.CamPitchSteps, "twice")
    AssertTrue(io.Index("event {sc02A up}") < first, "after shift lock went on")
    AssertTrue(first < QmObbyFirst(io, "down f"), "before the first skill")
}

; walk until beside, then no step at all while the fight goes on
Test_Minions_StandsBesideTheOrbNoStepBack() {
    far := [{x: 1280, y: 500, w: 60}], beside := [{x: 1280, y: 400, w: 200}]
    m := MnTask()
    m.t._scanFn := () => (MnWalks(m.io) >= 3 ? beside : far)
    m.t._toastFn := () => (MnSkills(m.io) >= 6 ? "orb" : "")
    m.t.Run(SchedCtx())
    AssertEq(MnStatsOf(m) != "", true, "ended")
    at := QmObbyFirst(m.io, "down e")                 ; the first skill (E, then F)
    AssertTrue(at > 0, "skills")
    AssertTrue(MnLogged(m, "minions: beside it (bar 200 px) - standing and casting"), "logged")
    AssertEq(QmObbyDowns(m.io, "s"), 0, "side steps through the casts, no step back")
    n := 0
    for i, e in m.io.log
        n += (i > at && e = "down w") ? 1 : 0
    AssertEq(n, MnSkills(m.io) - 1, "no walk after the first skill: only each skill's w tap (no shift lock)")
}

; hits land off centre: only a far-off orb is turned to
Test_Minions_OffCentreOrbIsLockedOn() {
    m := MnTask([[{x: 1500, y: 400, w: 200}]])
    m.t._toastFn := () => (MnSkills(m.io) >= 2 ? "orb" : "")
    m.t.Run(SchedCtx())
    AssertTrue(QmObbyDowns(m.io, "Left") + QmObbyDowns(m.io, "Right") > 0, "locked on in a fight: turned to it")
    m := MnTask([[{x: 700, y: 400, w: 200}]])
    m.t._toastFn := () => (MnSkills(m.io) >= 2 ? "orb" : "")
    m.t.Run(SchedCtx())
    AssertTrue(QmObbyDowns(m.io, "Left") >= 1, "far off: turned to it")
}

; the orb out of view, minions in it: the nearest one ahead, and the orb's
; bearing kept for when they are dead
Test_Minions_NoOrbInViewFacesTheNearestMinion() {
    two := [{x: 700, y: 500, w: 130}, {x: 2000, y: 480, w: 112}]
    m := MnTask([two])
    m.t._toastFn := () => (MnSkills(m.io) >= 1 ? "orb" : "")
    m.t.Run(SchedCtx())
    AssertTrue(QmObbyFirst(m.io, "down Left") > 0, "turned to the wider, nearer one")
    AssertEq(QmObbyDowns(m.io, "Right"), 0, "not the other")
}

; a flash hides every bar: no turn, no walk, skills on; the bars back: on
Test_Minions_FlashMeansNothing() {
    beside := [{x: 1280, y: 400, w: 200}], n := 0
    m := MnTask()
    m.t._scanFn := () => (++n <= 2 || n >= 14) ? beside : []
    m.t._toastFn := () => (n >= 18 ? "orb" : "")
    m.t.Run(SchedCtx())
    AssertEq(QmObbyDowns(m.io, "Left") + QmObbyDowns(m.io, "Right"), 0, "no look round")
    AssertEq(QmObbyDowns(m.io, "w"), QmObbyDowns(m.io, "f") + QmObbyDowns(m.io, "e") + QmObbyDowns(m.io, "t"), "no walk (a w tap per skill only)")
    AssertTrue(MnSkills(m.io) >= 3, "skills went on through it")
    AssertTrue(InStr(MnStatsOf(m), "orb_down=1 ") && InStr(MnStatsOf(m), "how=toast"), "the kill by its toast")
}

; L72 05:04:04: the plate gone at fill 0.06 after the blind casts was taken
; for a kill, the orb alive at 0.06 the next hunt. No toast: no kill at any
; fill, a look round on the spot for it, on until the biome ends
Test_Minions_PlateGoneAtLowFillIsNoKill() {
    low := [{x: 1280, y: 400, w: 10, full: 200, fill: "0.05"}], n := 0
    m := MnTask()
    m.t._biomeDown := MinionsTask.OpenDown
    m.t._scanFn := () => (++n <= 3) ? low : []
    MnEndsBiome(m, 120000)
    m.t.Run(SchedCtx())
    AssertTrue(MnLogged(m, "the orb's plate is gone at fill 0.05 - no Orb Awards toast, not down: looking round for it"), "logged")
    AssertTrue(!MnLogged(m, "the orb is down"), "no kill")
    s := MnStatsOf(m)
    AssertTrue(InStr(s, "orb_down=0 ") && !InStr(s, "how="), s)
    AssertTrue(MnLogged(m, "the biome changed"), "on until the biome ended")
    AssertTrue(QmObbyDowns(m.io, "Left") > 2, "looked round for it")
}

; the plate lost at low fill, found again on the look round: fought on, the
; kill by its toast, the hunt over at once
Test_Minions_PlateGoneAtLowFillFoundAgainKilledByToast() {
    low := [{x: 1280, y: 400, w: 10, full: 200, fill: "0.05"}], n := 0, at := 0
    m := MnTask()
    m.t._biomeDown := MinionsTask.OpenDown
    m.t._scanFn := () => (++n <= 3) ? low : (MnLogged(m, "plate is gone") ? MnTurning(m, [{x: 1280, y: 400, w: 10, full: 200, fill: "0.05"}]) : [])
    m.t._toastFn := () => (at := (!at && MnLogged(m, "plate is gone")) ? MnSkills(m.io) : at, (at && MnSkills(m.io) >= at + 2) ? "orb" : "")
    MnEndsBiome(m, 600000)
    m.t.Run(SchedCtx())
    s := MnStatsOf(m)
    AssertTrue(InStr(s, "orb_down=1 ") && InStr(s, "how=toast"), "the kill by its toast: " s)
    AssertTrue(!MnLogged(m, "the biome changed"), "over at the toast, not the biome")
    AssertTrue(MnSkills(m.io) >= at + 2, "skills on it again after the look")
}

Test_Minions_PlateGoneAtHighFillLooksAgain() {
    full := [{x: 1280, y: 400, w: 200, full: 200, fill: 1}], n := 0
    m := MnTask()
    m.t._scanFn := () => (++n <= 3) ? full : []
    m.t.Run(SchedCtx())
    AssertTrue(MnLogged(m, "no plate since the screen cleared - looking again"), "logged")
    AssertTrue(InStr(MnStatsOf(m), "orb_down=0 "), "no kill")
    AssertTrue(QmObbyDowns(m.io, "Left") > 2, "looked round")
    AssertTrue(!MnLogged(m, "back to the fight"), "no walk: a circle on the spot")
}

; the plate gone at low fill, the minions not proved down: no kill
Test_Minions_PlateGoneOnALockedOrbIsNoKill() {
    low := [{x: 1280, y: 400, w: 10, full: 200, fill: "0.05"}], n := 0
    m := MnTask()
    m.t._scanFn := () => (++n <= 3) ? low : []
    m.t.Run(SchedCtx())
    AssertTrue(!MnLogged(m, "plate is gone at fill"), "two low reads prove nothing: no orb HP")
    AssertTrue(!MnLogged(m, "the orb is down"), "no kill")
    AssertTrue(InStr(MnStatsOf(m), "orb_down=0 "), "orb_down=0")
}

; 3 toasts, then the bars go: no walk, no patrol, skills through OpenStayMs,
; a circle, skills again, until the biome ends, past Minions.maxSec
Test_Minions_OpenOrbIsStayedOn() {
    beside := [{x: 1280, y: 400, w: 200, full: 200, fill: 1}], n := 0
    m := MnTask(, Map("Minions.patrol", 1, "Minions.maxSec", 60))
    m.t._toastFn := () => (++n, (n = 2 || n = 4 || n = 6) ? "minion" : "")
    m.t._scanFn := () => n <= 6 ? beside : []
    m.t._beaconFn := () => [{x: 1500, y: 300, r: 40}]
    MnEndsBiome(m, 120000)
    m.t.Run(SchedCtx())
    AssertTrue(MnLogged(m, "3 minions down - the orb is open"), "logged")
    AssertTrue(MnLogged(m, "past the hunt's time - the orb is open"), "past maxSec")
    AssertTrue(MnLogged(m, "the orb is open - facing it, skills on"), "the circle, then back to it")
    AssertTrue(MnLogged(m, "hunt over"), "over with the biome")
    AssertTrue(!MnLogged(m, "walking the map") && !MnLogged(m, "orb glow") && !MnLogged(m, "back to the fight"), "no walk off it")
    AssertEq(QmObbyDowns(m.io, "w"), QmObbyDowns(m.io, "f") + QmObbyDowns(m.io, "e") + QmObbyDowns(m.io, "t"), "no walk (a w tap per skill only)")
}

; flat 1.00 bars do not keep a hunt past its time, hurt ones do for HurtKeepMs
Test_Minions_HuntOnNeedsAHurtBar() {
    f := {down: 0, hurtAt: ""}
    AssertTrue(!MinionsTask.HuntOn(f, 50000, 40000), "flat bars: over")
    f.hurtAt := 30000
    AssertTrue(MinionsTask.HuntOn(f, 50000, 40000), "hurt 20 s ago")
    AssertTrue(!MinionsTask.HuntOn(f, 60000, 40000), "30 s ago: over")
    f.down := 3
    AssertTrue(MinionsTask.HuntOn(f, 500000, 899999), "open: on")
    AssertTrue(!MinionsTask.HuntOn(f, 500000, 900000), "to the cap")
}

; the count lives as long as the biome; beside the fight is a thing of one life
Test_Minions_OpenCountKeptInTheBiome() {
    beside := [{x: 1280, y: 400, w: 200, full: 200, fill: 1}], n := 0
    m := MnTask(, Map("Minions.maxSec", 5))
    m.t._toastFn := () => (++n, n = 2 ? "minion" : "")
    m.t._scanFn := () => beside
    m.state.biome := "RAINY", m.t.CanRun(m.state)
    m.t.Run(SchedCtx())
    AssertEq(m.t._biomeDown, 1, "kept after the hunt")
    m.t._hunted := ""
    m.t.CanRun(m.state)
    AssertEq(m.t._biomeDown, 1, "the same biome")
    m.state.biome := "SNOWY"
    m.t.CanRun(m.state)
    AssertEq(m.t._biomeDown, 0, "a new biome")
}

; open: a lone bar under OrbLonePx is the orb and beside (L47 16:55:32 read
; 62 px at 114 / 300 with its plate unread, not the orb)
Test_Minions_OpenOrbLoneBarIsTheOrb() {
    bars := [{x: 1280, y: 400, w: 40, full: 40, fill: 1}]
    AssertTrue(!IsObject(MinionsTask.View(bars).orb), "locked: a minion")
    v := MinionsTask.View(bars, true)
    AssertTrue(IsObject(v.orb) && MinionsTask.Beside(v), "open: the orb, beside it")
    two := [{x: 1280, y: 400, w: 40, full: 40, fill: 1}, {x: 1000, y: 410, w: 40, full: 40, fill: 1}]
    AssertTrue(!MinionsTask.View(two, true).lone, "two bars: read as ever")
    f := {here: false, down: 3}
    AssertTrue(!MinionsTask.Stay(f), "open but not there yet: a re-hunt walks to it")
}

Test_Minions_ToastBeforeAnyCastIsNotOurs() {
    far := [{x: 1280, y: 500, w: 60}]
    m := MnTask([far])
    m.t._toastFn := () => "orb"
    m.t.Run(SchedCtx())
    AssertTrue(InStr(MnStatsOf(m), "orb_down=0 "), "an old toast")
}

Test_Minions_MinionToastsCount() {
    beside := [{x: 1280, y: 400, w: 200}], n := 0
    m := MnTask([beside])
    m.t._toastFn := () => (++n, (n = 3 || n = 4 || n = 6) ? "minion" : n >= 9 ? "orb" : "")
    AssertEq(m.t.Run(SchedCtx()), 3, "two toasts (one seen twice) and the orb")
}

; the supervisor's numbers
Test_Minions_FillLoggedEveryFewSeconds() {
    b := [{x: 1280, y: 400, w: 120, full: 200, fill: "0.6"}, {x: 900, y: 500, w: 52, full: 130, fill: "0.4"}]
    m := MnTask([b])
    t0 := m.io.t
    m.t._scanFn := () => (m.io.t - t0 > 30000 ? [] : b)
    m.t._toastFn := () => (m.io.t - t0 > 30000 ? "orb" : "")
    m.t.Run(SchedCtx())
    n := 0
    for l in m.logs
        n += InStr(l, "minions: fill orb=0.6 minions=0.4") ? 1 : 0
    AssertTrue(n >= 3 && n <= 10, "every FillEveryMs: " n)
}

; hits are -15: at low HP the fight goes on
Test_Minions_HurtStays() {
    MnStaysAt(0.45)
    MnStaysAt(0.2)
}

MnStaysAt(hp) {
    beside := [{x: 1280, y: 400, w: 200}]
    m := MnTask([beside])
    m.t._hudFn := () => (h := MnNoPanel(), h.playerHp := hp, h)
    m.t._toastFn := () => (MnSkills(m.io) >= 4 ? "orb" : "")
    m.t.Run(SchedCtx())
    AssertEq(QmObbyDowns(m.io, "s"), 0, "no step back at " hp)
    AssertTrue(MnSkills(m.io) >= 4, "skills on at " hp)
}

; hit hard: reads of the last BackDropMs, -1s left out, since a back-off
Test_Minions_HitHard() {
    L(a*) {
        log := []
        for i, hp in a
            log.Push({at: i * 500, hp: hp})
        return log
    }
    h := MinionsTask.HitHard(L(0.9, 0.8, 0.65), 1500)
    AssertTrue(IsObject(h) && h.top = 0.9 && h.hp = 0.65 && h.ms = 1000, "25% in 1 s")
    AssertEq(MinionsTask.HitHard(L(0.9, 0.8, 0.75), 1500), "", "15% at 75%: not yet")
    AssertTrue(IsObject(MinionsTask.HitHard(L(0.5, 0.4), 1000)), "10% at 40%: low")
    AssertEq(MinionsTask.HitHard(L(0.4, 0.4, 0.4), 1500), "", "low and flat: no hit")
    AssertEq(MinionsTask.HitHard(L(0.9, 0.6, -1), 1500), "", "the bar gone (full): no")
    AssertEq(MinionsTask.HitHard(L(-1, 0.5), 1000), "", "a -1 is no read, not full")
    AssertEq(MinionsTask.HitHard(L(0.9, 0.7, 0.7, 0.7, 0.7, 0.7, 0.7, 0.65), 4000), "", "the high read past BackDropMs")
    AssertEq(MinionsTask.HitHard(L(0.9, 0.8, 0.65), 1500, 1000), "", "since the last back-off: 15% at 65%")
}

; a fight beside an orb and a close minion, the HP from hp(ms into it), stopped
; at 12 s (bars: the scan's, the same each look)
MnHitFight(hp, bars := "") {
    m := MnTask(, Map("Minions.maxSec", 30), , MnTurnIO())
    near := IsObject(bars) ? bars : [{x: 1280, y: 400, w: 200}, {x: 1200, y: 500, w: 125}]
    m.t._swap.wear := "Eden"
    m.t._scanFn := () => near
    c := {t0: 0}, ctx := SchedCtx()
    m.t._hudFn := () => (h := MnNoPanel(), h.playerHp := hp(c.t0 ? m.io.t - c.t0 : 0), h)
    m.t._toastFn := () => (c.t0 := c.t0 ? c.t0 : m.io.t, m.io.t - c.t0 >= 12000 ? ctx.Stop() : 0, "")
    m.t._Fight(ctx)
    return m
}

; L72 SAND STORM: full -> dead in 8-17 s of stand and strafe among the
; minions. The HP down 30% in a tick: back out of reach once, skills on,
; then the stand again; the fight's HP logged
Test_Minions_BacksOffWhenHitHard() {
    m := MnHitFight((d) => d < 2000 ? 0.9 : 0.6)
    AssertEq(MnLogCount(m, "backing out of reach"), 1, "once: the HP flat after it")
    AssertTrue(MnLogged(m, "minions: hp 90% -> 60% in "), "the drop logged")
    AssertTrue(QmObbyDowns(m.io, "s") >= 1, "a step back")
    AssertEq(QmObbyDowns(m.io, "s"), MnUps(m.io, "s"), "s released")
    held := m.io.HeldMs("s")
    AssertTrue(held >= MinionsTask.BackOffMs - MinionsTask.FightTickMs && held <= MinionsTask.BackOffMs + 2 * MinionsTask.FightTickMs, "about BackOffMs back: " held)
    AssertTrue(MnSkills(m.io) >= 3, "skills on: " MnSkills(m.io))
    AssertTrue(MnLogged(m, "minions: hp 90% in the fight") && MnLogged(m, "minions: hp 60% in the fight"), "the fight's HP logged")
}

; hits that keep coming: a back-off each, BackOffMs apart at least
Test_Minions_BacksOffAgainWhileHit() {
    m := MnHitFight((d) => Max(0.05, Round(1 - d / 10000, 2)))
    n := MnLogCount(m, "backing out of reach")
    AssertTrue(n >= 2 && n <= 12000 // MinionsTask.BackOffMs + 1, "again while hit: " n)
}

; no back-off: the HP flat (low or not), or the orb open with no minion left
Test_Minions_NoBackOffWithoutHits() {
    m := MnHitFight((d) => 0.3)
    AssertEq(MnLogCount(m, "backing out of reach"), 0, "low and flat")
    AssertEq(QmObbyDowns(m.io, "s"), 0, "no step back")
    m := MnTask(, Map("Minions.maxSec", 30), , MnTurnIO())
    m.t._biomeDown := MinionsTask.OpenDown
    orb := [{x: 1280, y: 400, w: 200}]
    m.t._swap.wear := "Eden"
    m.t._scanFn := () => orb
    c := {t0: 0}
    m.t._hudFn := () => (h := MnNoPanel(), h.playerHp := (c.t0 && m.io.t - c.t0 >= 2000) ? 0.5 : 0.9, h)
    m.t._toastFn := () => (c.t0 := c.t0 ? c.t0 : m.io.t, m.io.t - c.t0 >= 8000 ? "orb" : "")
    m.t._Fight(SchedCtx())
    AssertEq(MnLogCount(m, "backing out of reach"), 0, "the open orb alone does not hit")
    AssertTrue(MnLogged(m, "minions: hp 50% in the fight"), "still logged")
}

; the fight's HP: a line per HpLogDrop down, else every HpLogMs at most
Test_Minions_FightHpLogRateLimited() {
    m := MnHitFight((d) => Round(0.95 - Mod(d // 300, 2) * 0.05, 2))
    n := MnLogCount(m, "in the fight")
    AssertTrue(n >= 2 && n <= 12000 // MinionsTask.HpLogMs + 2, "rate-limited: " n)
}

; m's _Idle ticks: n, worst: the longest run of them (ms)
MnWatchIdle(m) {
    w := {n: 0, from: 0, last: 0, worst: 0}
    idle := MinionsTask.Prototype._Idle
    watched(s, ctx) {
        w.from := (m.io.t - w.last > 2 * MinionsTask.FightTickMs) ? m.io.t : w.from
        ok := idle(s, ctx)
        w.n++, w.last := m.io.t, w.worst := Max(w.worst, w.last - w.from)
        return ok
    }
    m.t.DefineProp("_Idle", {Call: watched})
    return w
}

; HP low, no bar: the look goes on. Holding back stood idle here until 60%:
; L48 17:32:30-17:33:05, 35 s, no skill, 181 of 300 left on an open orb
Test_Minions_LowHpNoBarKeepsLooking() {
    m := MnTask([[]], Map("Minions.maxSec", 40))
    m.t._swap.wear := "Eden"
    m.t._hudFn := () => (h := MnNoPanel(), h.playerHp := 0.2, h)
    w := MnWatchIdle(m)
    m.t._Fight(SchedCtx())
    AssertEq(w.n, 0, "never standing: no idle tick")
    AssertTrue(QmObbyDowns(m.io, "Left") >= 3, "turning, looking: " QmObbyDowns(m.io, "Left"))
}

; beside the fight, the bars gone: ClearMs of quiet is all that is left of the
; idle (the screen clearing), then a look, none after it
Test_Minions_LowHpNoBarIdlesNoMoreThanClearMs() {
    m := MnTask(, Map("Minions.maxSec", 25), , MnTurnIO())
    near := [{x: 1280, y: 400, w: 200}, {x: 1200, y: 500, w: 125}]
    m.t._swap.wear := "Eden"
    m.t._scanFn := () => (MnSkills(m.io) < 2 ? near : [])
    m.t._hudFn := () => (h := MnNoPanel(), h.playerHp := 0.2, h)
    w := MnWatchIdle(m)
    c := {n: -1}
    m.t._toastFn := () => (c.n := (c.n < 0 && MnLogged(m, "no plate since the screen cleared")) ? w.n : c.n, "")
    m.t._Fight(SchedCtx())
    AssertTrue(c.n > 0, "the stand ended: " c.n)
    AssertTrue(w.worst <= MinionsTask.ClearMs + MinionsTask.FightTickMs, "no idle past ClearMs: " w.worst)
    AssertEq(w.n, c.n, "no idle after it")
}

; a walk in at low HP goes without side steps: logged, so that can be read
Test_Minions_LowHpWalkInLogged() {
    m := MnWalkInAt(0.2)
    AssertTrue(MnLogged(m, "minions: walking in at hp 20%"), "at 20%")
    m := MnWalkInAt(0.5)
    AssertTrue(!MnLogged(m, "minions: walking in"), "at 50%: not low")
}

MnWalkInAt(hp) {
    far := [{x: 1280, y: 400, w: 40}]
    m := MnTask([far])
    c := SchedCtx()
    m.t._swap.wear := "Eden"
    m.t._hudFn := () => (h := MnNoPanel(), h.playerHp := hp, h)
    m.t._toastFn := () => (MnWalks(m.io) >= 1 ? c.Stop() : 0, "")
    m.t._Fight(c)
    AssertTrue(MnWalks(m.io) >= 1, "walked in at " hp)
    return m
}

; Deadeye's windup: no turn, no step
Test_Minions_DeadeyeRootsThePlayer() {
    hp := {v: -1}
    off := [{x: 800, y: 400, w: 200}]
    m := MnTask()
    rPressed := () => MnLogged(m, "skill r")
    x := {at: 0, n: 0}
    m.t._scanFn := () => [{x: 800, y: 400, w: 200}]
    m.t._hudFn := () => (h := MnHud(, 80, "V"), h.playerHp := hp.v, h)
    m.t._toastFn := () => (rPressed() && ++x.n >= 3 ? "orb" : "")
    m.t.Run(SchedCtx())
    AssertTrue(rPressed(), "Deadeye at rank V")
    i := QmObbyFirst(m.io, "down r")
    ; the respawn's own r comes first: the skill's is the second
    r2 := 0, at := 0
    for j, e in m.io.log
        if (e = "down r" && ++r2 = 2)
            at := j
    n := 0
    for j, e in m.io.log
        n += (j > at && RegExMatch(e, "^down (Left|Right|w|a|s|d)$")) ? 1 : 0
    AssertEq(n, 0, "nothing moved while it winds up")
}

; ---- scripted fights: the clips' numbers in a small world ------------------

; a world for one fight: bars from the enemies' HP, HUD from the skills'
; own clocks (the overlay from the cast's end), flashes after casts.
; Pressed mid-cast or on cooldown = wasted. spec: {aura, panel (6 keys),
; skills: Map k -> {cast, cool, orb, min, charge, cost, needV}, minions}
class MnArena {
    __New(m, spec) {
        this.m := m, this.io := m.io, this.spec := spec
        this.n := 0                  ; io.log read so far
        this.orb := 300, this.min := [], this.wasted := 0, this.casts := ""
        Loop spec.minions
            this.min.Push(100)
        this.castEnd := 0, this.pend := "", this.cdEnd := Map()
        this.charge := 0, this.rankUntil := 0, this.walked := 0, this.wAfterBeside := 0, this.sides := 0, this.beside := false
        this.sideInCast := 0, this.sideRooted := 0, this.sideLate := 0, this.aloneAt := 0, this.keys := ""
        this.flashUntil := 0, this.killedAt := 0, this.stepsOf := Map("a", 0, "d", 0, "s", 0)
        this.toasts := 0, this.toasted := false
        m.t._scanFn := () => this.Scan()
        m.t._hudFn := () => this.Hud()
        m.t._toastFn := () => this.Toast()
    }
    ; the io log since the last look: presses at their times; steps by the time held
    Tick() {
        L := this.io.log, now := this.io.t
        while (this.n < L.Length) {
            e := L[++this.n]
            if RegExMatch(e, "^down (\w)$", &g)
                this.Key(g[1], this.io.downAt[this.n])
        }
        for k in ["a", "d", "s"]
            while (this.stepsOf[k] < this.io.HeldMs(k) // MinionsTask.DodgeStepMs)
                this.stepsOf[k]++, this.Step(k, now)
        if !this.beside
            this.walked := this.io.HeldMs("w") // MinionsTask.WalkMs
        if (IsObject(this.pend) && now >= this.castEnd) {
            this.Land(this.pend), this.pend := ""
        }
    }
    ; a step's worth of k held, read at the end of it
    Step(k, now) {
        at := now - MinionsTask.DodgeStepMs
        this.sides++, this.keys .= k
        this.sideInCast += at < this.castEnd
        this.sideLate += this.aloneAt && at >= this.aloneAt + MinionsTask.DodgeHoldMs + 2 * MinionsTask.FightTickMs
    }
    Key(k, now) {
        if (k = "w") {
            this.wAfterBeside += this.beside
            return
        }
        if !this.spec.skills.Has(k)
            return
        s := this.spec.skills[k]
        ; Hud's cd is in hundredths: 20 s cooldowns read up to 100 ms off
        ok := now >= this.castEnd && now + 100 >= this.cdEnd.Get(k, 0) && this.charge >= s.need
            && (!s.needV || now < this.rankUntil)
        if !ok {
            this.wasted++
            return
        }
        this.casts .= k
        this.castEnd := now + s.cast, this.cdEnd[k] := now + s.cast + s.cool
        this.pend := s
        this.flashUntil := this.castEnd + s.flash
    }
    Land(s) {
        alive := 0
        for i, hp in this.min {
            if (hp > 0) {
                this.min[i] := Max(0, hp - s.min)
                this.toasts += !this.min[i]
            }
            alive += this.min[i] > 0
        }
        if !alive
            this.orb := Max(0, this.orb - s.orb)
        this.charge := Min(100, Max(0, this.charge + s.charge))
        if s.rank
            this.rankUntil := this.io.t + 15000
        if s.spend
            this.charge := 0
        if (!this.orb && !this.killedAt)
            this.killedAt := this.io.t
    }
    Scan() {
        this.Tick()
        now := this.io.t
        if (now < this.flashUntil || !this.orb)
            return []
        w := Min(200, 70 + this.walked * 30)
        this.beside := w >= MinionsTask.BesideOrbW
        bars := []
        ; all within AimTol: these bars do not move on a turn, and one off
        ; centre was turned to for ever, unconfirmed (no minion ever in View)
        dy := this.HasOwnProp("jump") ? Mod(this.sides, 2) * this.jump : 0     ; a step moves the bars
        for i, hp in this.min
            if hp
                bars.Push({x: 1160 + i * 60, y: 560 + dy, w: Max(4, 130 * hp // 100 * w // 200), full: 130 * w // 200, fill: Round(hp / 100, 2)})
        if (!bars.Length && !this.aloneAt)
            this.aloneAt := now                  ; the orb alone in sight from here
        bars.Push({x: 1280, y: 300 + dy, w: Max(4, w * this.orb // 300), full: w, fill: Round(this.orb / 300, 2)})
        return bars
    }
    Hud() {
        now := this.io.t, rows := []
        for k in this.spec.panel {
            if (k = "") {
                rows.Push("")
                continue
            }
            left := this.cdEnd.Get(k, 0) - now
            s := this.spec.skills[k]
            rows.Push({cd: (left > 0 && now >= this.castEnd) ? Round(left / s.cool, 2) : 0})
        }
        eden := this.spec.aura = "Eden"
        return {rows: rows, points: eden ? this.charge : -1, rank: (eden && now < this.rankUntil) ? "V" : "", playerHp: -1}
    }
    ; the orb's, else one read of "minion" a minion down
    Toast() {
        if (this.killedAt && this.io.t >= this.killedAt + 300)
            return "orb"
        this.toasted := !this.toasted && this.toasts > 0
        this.toasts -= this.toasted
        return this.toasted ? "minion" : ""
    }
}

MnSkill(cast, cool, orb, min, flash := 0, charge := 0, need := 0, needV := false, rank := false, spend := false) => {cast: cast, cool: cool, orb: orb, min: min, flash: flash, charge: charge, need: need, needV: needV, rank: rank, spend: spend}

MnArenaFight(aura, panel, skills, minions, prep := "") {
    m := MnTask(, Map("Minions.maxSec", 300))
    a := MnArena(m, {aura: aura, panel: panel, skills: skills, minions: minions})
    m.t._swap.wear := aura
    if IsObject(prep)
        prep(m.t, a)
    t0 := m.io.t
    m.t._Fight(SchedCtx())
    return {m: m, a: a, ms: a.killedAt - t0}
}

MnArenaAsserts(f, what, maxMs) {
    AssertTrue(f.a.killedAt > 0, what ": the orb died (" f.a.casts ", orb " f.a.orb ")")
    AssertTrue(f.ms <= maxMs, what ": in " f.ms " ms")
    AssertEq(f.a.wasted, 0, what ": no press mid-cast or on cooldown (" f.a.casts ")")
    ; was 0 (no side step): the hits are darts, a player standing takes them all
    AssertTrue(f.a.sides > 0, what ": steps between casts")
    AssertTrue(f.a.sideInCast > 0, what ": strafing through casts (" f.a.casts ")")
    ; Voidrush goes right after the last minion now: its cast and flash (5.8 s
    ; here) hide the bars, and a flash hiding every bar says nothing
    AssertTrue(f.a.sideLate <= 20, what ": the minions dead, stood still (a flash can hide that for some ticks): " f.a.sideLate)
    s := MnStatsOf(f.m)
    AssertTrue(InStr(s, "orb_down=1 ") && InStr(s, "how=toast"), what ": " s)
}

; clip 170608: 62 s from first hit to the kill by hand
Test_Minions_ScriptedFightEden() {
    sk := Map("t", MnSkill(400, 8000, 0, 0, 0, 15)
        , "f", MnSkill(2800, 10000, 40, 40, 1500, 12)
        , "e", MnSkill(1000, 6000, 31, 31, 500, 10)
        , "q", MnSkill(1000, 3000, 0, 15, 0, 10)
        , "v", MnSkill(4800, 60000, 42, 42, 1000, -25, 30, false, true)
        , "r", MnSkill(3400, 40000, 102, 0, 2000, 0, 0, true, false, true))
    f := MnArenaFight("Eden", ["t", "f", "e", "q", "r", "v"], sk, 3)
    MnArenaAsserts(f, "Eden", 100000)
    AssertTrue(InStr(f.a.casts, "v"), "Voidrush at 30 Charge: " f.a.casts)
    AssertTrue(InStr(f.a.casts, "q"), "Impale fills the gaps among the minions: " f.a.casts)
    AssertTrue(InStr(f.a.casts, "r") > InStr(f.a.casts, "v"), "Deadeye after the rank it brings: " f.a.casts)
    AssertTrue(f.a.wAfterBeside <= QmObbyDowns(f.m.io, "t") + QmObbyDowns(f.m.io, "f") + QmObbyDowns(f.m.io, "e")
        + QmObbyDowns(f.m.io, "q") + QmObbyDowns(f.m.io, "v") + QmObbyDowns(f.m.io, "r"), "beside it only the w taps of no shift lock (some casts came on the walk in)")
}

; clip 170827: three skills R T E, 20 s each, 73 s by hand
Test_Minions_ScriptedFightEquinox() {
    sk := Map("r", MnSkill(3000, 20000, 45, 45, 3000)
        , "t", MnSkill(5000, 20000, 40, 40, 2000)
        , "e", MnSkill(2500, 20000, 50, 50, 2000))
    f := MnArenaFight("Equinox", ["", "", "", "e", "t", "r"], sk, 3)
    MnArenaAsserts(f, "Equinox", 180000)
    AssertEq(SubStr(f.a.casts, 1, 3), "rte", "R T E: " f.a.casts)
}

; clip 171013: F E T R, Q a dash: 123 s by hand (with a death)
Test_Minions_ScriptedFightLuminosity() {
    sk := Map("f", MnSkill(1000, 25000, 35, 35, 1500)
        , "t", MnSkill(1000, 23000, 40, 20, 500)
        , "q", MnSkill(500, 1900, 0, 0)
        , "r", MnSkill(2800, 50000, 75, 75, 2000)
        , "e", MnSkill(1000, 6900, 15, 15, 500))
    f := MnArenaFight("Luminosity", ["", "f", "t", "q", "r", "e"], sk, 4)
    MnArenaAsserts(f, "Luminosity", 180000)
    AssertEq(InStr(f.a.casts, "q"), 0, "never the dash: " f.a.casts)
    AssertEq(SubStr(f.a.casts, 1, 2), "fe", "F then E: " f.a.casts)
}

; the hits are darts: side steps two a way, no step back, a step never in a cast
Test_Minions_DodgeBetweenCasts() {
    f := MnSlowFight()
    MnArenaAsserts(f, "slow", 280000)
    AssertTrue(f.a.sides >= 20, "steps all through the gaps: " f.a.sides)
    AssertTrue(InStr(f.a.keys, "aadd"), "a side, then the other: " f.a.keys)
    AssertEq(InStr(f.a.keys, "s"), 0, "no step back: " f.a.keys)
    AssertTrue(MnLogged(f.m, "minions: dodging between casts"), "logged")
    AssertTrue(MnLogged(f.m, "minions: dodge run a") && MnLogged(f.m, "minions: dodge run d"), "each run's key logged")
    for key in ["a", "d"]
        AssertEq(QmObbyDowns(f.m.io, key), MnUps(f.m.io, key), "every " key " released")
}

; a step takes a tick's place: the same casts as standing, as fast
Test_Minions_DodgeKeepsTheCastRate() {
    still := MnSlowFight((t, a) => t.DefineProp("_Dodge", {Call: (s, ctx, f) => s._Idle(ctx)}))
    f := MnSlowFight()
    AssertEq(still.a.sides, 0, "off: no step")
    AssertTrue(f.a.sides > 0, "on: steps")
    AssertEq(f.a.casts, still.a.casts, "the same casts")
    AssertTrue(f.ms <= still.ms + MinionsTask.FightTickMs, "as fast: " f.ms " against " still.ms)
}

; sea on one side: the other; on both: no step, the casts go on
Test_Minions_DodgeNeverOffAnEdge() {
    f := MnSlowFight((t, a) => t._viewFn := () => {edge: a.beside, edgeL: false, edgeR: a.beside, sig: []})
    AssertEq(QmObbyDowns(f.m.io, "d"), 0, "never right, the sea there")
    AssertTrue(f.m.io.HeldMs("a") >= 20 * MinionsTask.DodgeStepMs, "left instead")
    f := MnSlowFight((t, a) => t._viewFn := () => {edge: a.beside, sig: []})
    AssertEq(f.a.sides, 0, "the sea on both sides: no step")
    AssertTrue(f.a.killedAt > 0, "the orb died all the same: " f.a.casts)
}

; a fall remembered to the right: that side refused
Test_Minions_DodgeAwayFromARememberedFall() {
    ; to the right of where the player first looks beside the orb
    f := MnSlowFight((t, a) => t._viewFn := () => (a.beside && !t._falls.Length && t._falls.Push({x: t._pos.x, y: t._pos.y, b: t._bearing + MinionsTask.FullTurnMs // 4, at: t._env.Now()}), ""))
    ; FallMarginMs away it is open again: 7 steps of DodgeStepMs
    AssertEq(SubStr(f.a.keys, 1, 6), "aaaaaa", "away from it, not towards: " f.a.keys)
}

; the orb alone, n ticks of 150 ms over bars(k); -> m
MnOrbStand(bars, n := 30, prep := "") {
    m := MnTask()
    ctx := SchedCtx(), k := 0
    m.t._lock := true
    m.t._scanFn := () => (m.io.t += 150, ++k >= n ? ctx.Stop() : 0, bars(k))
    if IsObject(prep)
        prep(m)
    MnWalkFight(m, ctx)
    return m
}

; L44 13:55: the orb drawn over the character, F's cloud past it, only E landed
Test_Minions_StepsBackFromAnOrbBehind() {
    orb := {x: 1195, y: 520, w: 236, full: 236, h: 14, fill: 1}
    m := MnOrbStand((k) => [orb])
    n := MnDowns(m.io, "s")
    AssertTrue(n >= 2, "steps back: " n)
    AssertEq(MnUps(m.io, "s"), n, "each let go")
    AssertTrue(MnLogged(m, "minions: the orb behind the player - a step back (full 236, h 14, y 520)"), "logged")
    AssertTrue(MnLogged(m, "minions: beside it (bar 236 px) - standing and casting (full 236, h 14, y 520)"), "the bar's numbers on the beside line")
    i := QmObbyFirst(m.io, "down s"), j := MnNth(m.io, "down s", 2)
    AssertTrue(m.io.downAt[j] - m.io.downAt[i] >= MinionsTask.OrbBehindGapMs, "no sooner than the gap")
    AssertTrue(QmObbyFirst(m.io, "up s") < j, "up before the next")
    ; not when the numbers fall short of it
    for bad in [{w: 209}, {y: 479}, {h: 13}] {
        o := {x: 1195, y: 520, w: 236, full: 236, h: 14, fill: 1}
        for key, val in bad.OwnProps()
            o.%key% := val
        o.full := o.w
        AssertTrue(MinionsTask.Beside(MinionsTask.View([o])), "beside all the same")
        AssertEq(MnDowns(MnOrbStand((k) => [o], 12).io, "s"), 0, "no step: " o.w " " o.y " " o.h)
    }
    AssertEq(MnDowns(MnOrbStand((k) => [{x: 1195, y: 520, w: 236, full: 236, fill: 1}], 12).io, "s"), 0, "no height read: no step")
}

; no minion in view is not none left: the strafe goes on for DodgeHoldMs, no
; back step into the darts
Test_Minions_NoStepBackWithMinionsAbout() {
    orb := {x: 1195, y: 520, w: 236, full: 236, h: 14, fill: 1}, mn := {x: 1195, y: 700, w: 130, full: 130, fill: 1}
    AssertEq(MnDowns(MnOrbStand((k) => [orb, mn], 20).io, "s"), 0, "a minion in view")
    at := {m: "", t: 0}
    m := MnOrbStand((k) => (k <= 3 ? (at.t := at.m.io.t, [orb, mn]) : [orb]), 40, (m) => at.m := m)
    i := QmObbyFirst(m.io, "down s")
    AssertTrue(i > 0, "none for that long: the step")
    AssertTrue(m.io.downAt[i] - at.t >= MinionsTask.DodgeHoldMs, "not before DodgeHoldMs: " m.io.downAt[i] - at.t)
}

; a fall remembered behind: no step; Deadeye's root: no key held into it
Test_Minions_NoStepBackAtAFallOrInTheRoot() {
    orb := {x: 1195, y: 520, w: 236, full: 236, h: 14, fill: 1}
    m := MnOrbStand((k) => [orb], 12, (m) => m.t._falls.Push({x: m.t._pos.x, y: m.t._pos.y, b: m.t._bearing + MinionsTask.FullTurnMs // 2, at: m.io.t}))
    AssertEq(MnDowns(m.io, "s"), 0, "the fall that way")
    m := MnOrbStand((k) => [orb], 30, (m) => m.t._hudFn := () => MnHud(, 80, "V"))
    r := QmObbyFirst(m.io, "down r")
    AssertTrue(r > 0, "Deadeye")
    root := MinionSkills("Eden", "").CastMs("r")
    for i, e in m.io.log
        if (e = "down s")
            AssertTrue(m.io.downAt[i] < m.io.downAt[r] || m.io.downAt[i] >= m.io.downAt[r] + root, "no step in the root")
}

; real frames, cropped: the step on the true bar, not on plates read past it.
; y put back from the crop's top
MnOrbBehindFrame(name, top) {
    bars := MnFrameScan(name, 800, 120)
    for b in bars
        b.y += top
    return MinionsTask.View(bars)
}

Test_Minions_RealOrbBehind() {
    ; L44 13:55 clip t=33: full plate, the orb over the character
    v := MnOrbBehindFrame("minions_orb_behind_clip.png", 500)
    AssertEq(v.orb.y " " v.orb.h, "556 14", "the bar")
    AssertTrue(MinionsTask.FullW(v.orb) >= MinionsTask.OrbBehindW, "wide: " MinionsTask.FullW(v.orb))
    AssertTrue(MinionsTask.OrbBehind(v), "the step")
    ; the same clip t=12, the character clear of the orb: dark ledge read as plate
    v := MnOrbBehindFrame("minions_orb_ahead_overread_clip.png", 440)
    AssertTrue(MinionsTask.FullW(v.orb) >= MinionsTask.OrbBehindW, "over-read: " MinionsTask.FullW(v.orb))
    AssertTrue(!MinionsTask.OrbBehind(v), "no step: h " v.orb.h)
    ; L51 22:45 clip t=36, night: a 144 px Locked orb read 260 wide, a minion on the player
    v := MnOrbBehindFrame("minions_orb_overread_night_clip.png", 460)
    AssertTrue(MinionsTask.FullW(v.orb) >= MinionsTask.OrbBehindW, "over-read: " MinionsTask.FullW(v.orb))
    AssertTrue(!MinionsTask.OrbBehind(v), "no step: h " v.orb.h)
}

; a step moves every bar past MatchY: still the same fight, no lost plate
Test_Minions_DodgeKeepsTheBars() {
    f := MnSlowFight((t, a) => a.jump := MinionsTask.MatchY + 40)
    AssertTrue(f.a.killedAt > 0, "the orb died: " f.a.casts)
    AssertTrue(f.a.sides >= 20, "steps all through: " f.a.sides)
    AssertTrue(!MnLogged(f.m, "no plate since the screen cleared"), "no plate lost")
}

; hp low: the fight as ever
Test_Minions_LowHpFightsOn() {
    m := MnTask(, Map("Minions.maxSec", 300))
    a := MnArena(m, {aura: "Eden", panel: ["t", "f", "e", "q", "r", "v"], skills: MnEdenSkills(), minions: 3})
    m.t._swap.wear := "Eden"
    hud := m.t._hudFn
    m.t._hudFn := () => (h := hud(), h.playerHp := 0.2, h)
    m.t._Fight(SchedCtx())
    AssertTrue(a.sides > 0, "dodging")
    AssertTrue(InStr(a.casts, "f") && InStr(a.casts, "e"), "skills on: " a.casts)
    AssertTrue(a.killedAt > 0, "the orb died: " a.casts)
}

Test_Minions_DodgeKey() {
    s := ""
    Loop 4 * MinionsTask.DodgeRun
        s .= MinionsTask.DodgeKey(A_Index - 1)
    AssertEq(s, "aaadddaaaddd", "3 steps a way, the pendulum and nothing else, never back")
}

; a strafe that leaves reach: the side key up, the walk in, then the strafe
; again. Under StandLoose of a minion's bar only (the user: skills from long
; range hit nothing)
Test_Minions_StrafeOutOfReachWalksBackIn() {
    wide := 200, narrow := 125     ; the orb drifts off with its minions
    bar := (w, o := wide) => [{x: 1195, y: 300, w: o, full: o, fill: 1}, {x: 1195, y: 600, w: w, full: w, fill: 1}]
    near := MinionsTask.BesideMinionW + 10
    out := Floor(MinionsTask.StandLoose * MinionsTask.BesideMinionW) - 1
    m := MnTask()
    ctx := SchedCtx(), k := 0, at := {out: 0}
    m.t._lock := true
    ; drifted off after a run's first steps, in again after a walk
    m.t._scanFn := () => (m.io.t += 150, ++k >= 60 ? ctx.Stop() : 0
        , at.out := (at.out = 0 && m.io.HeldMs("a") >= 800) ? 1 : (at.out = 1 && m.io.HeldMs("w") >= 300) ? 2 : at.out
        , at.out = 1 ? bar(out, narrow) : bar(near))
    MnWalkFight(m, ctx)
    AssertEq(at.out, 2, "it left reach and came back")
    iW := QmObbyFirst(m.io, "down w")
    AssertTrue(iW > 0, "the walk took over")
    AssertTrue(QmObbyFirst(m.io, "up a") < iW, "the strafe up first")
    n := 0
    for i, e in m.io.log
        n += (i > iW && (e == "down a" || e == "down d")) ? 1 : 0
    AssertTrue(n >= 1, "back in reach: the strafe again")
    AssertTrue(!MnKeyDown(m.io, "w"), "w up at the end")
    ; drifting inside StandLoose: no walk
    m := MnTask()
    ctx := SchedCtx(), k := 0
    loose := Ceil(MinionsTask.StandLoose * MinionsTask.BesideMinionW)
    m.t._lock := true
    m.t._scanFn := () => (m.io.t += 150, ++k >= 40 ? ctx.Stop() : 0, bar(k <= 2 ? near : loose))
    MnWalkFight(m, ctx)
    AssertTrue(MnDowns(m.io, "a") >= 1, "strafed")
    AssertEq(m.io.HeldMs("w"), 0, "a stand that may drift: no walk")
}

; Equinox's three skills, 20 s each, no flash, a minion's 100 HP takes 7: wide gaps
MnSlowFight(prep := "") {
    sk := Map("r", MnSkill(3000, 20000, 45, 15), "t", MnSkill(5000, 20000, 40, 15), "e", MnSkill(2500, 20000, 50, 15))
    return MnArenaFight("Equinox", ["", "", "", "e", "t", "r"], sk, 3, prep)
}

MnEdenSkills() => Map("t", MnSkill(400, 8000, 0, 0, 0, 15)
    , "f", MnSkill(2800, 10000, 40, 40, 1500, 12)
    , "e", MnSkill(1000, 6000, 31, 31, 500, 10)
    , "q", MnSkill(1000, 3000, 0, 15, 0, 10)
    , "v", MnSkill(4800, 60000, 42, 42, 1000, -25, 30, false, true)
    , "r", MnSkill(3400, 40000, 102, 0, 2000, 0, 0, true, false, true))

; ---- the trail: after a death the way to the fight replayed from spawn ------

; MnIO that keeps every key's hold by the fake clock: held = "key ms" in
; release order
class MnHeldIO extends MnIO {
    held := []
    Up(k) {
        this.held.Push(k " " (this.t - this.keysDown[k]))
        super.Up(k)
    }
}

; io.held from index i on, jumps left out, joined with ", "
MnHeld(io, i := 1) {
    out := ""
    for n, h in io.held
        if (n >= i && !InStr(h, "Space"))
            out .= (out = "" ? "" : ", ") h
    return out
}

; how many walks from walk number i on
MnHeldWalks(io, i := 1) => io.walks - i + 1

MnTrail(route) {
    out := ""
    for s in route
        out .= (out = "" ? "" : " ") s.k " " s.ms "@" s.b
    return out
}

; a far target that nears with every walk (no stuck walks), until gone()
MnNearing(m, gone) => () => gone() ? [] : [{x: 1280, y: 300 + 14 * MnHeldWalks(m.io), w: 40}]

; st.dead; st.walks := the replay's walks once it is over (st.at: its start)
MnReplayed(m, st) {
    if (!st.HasOwnProp("walks") && MnLogged(m, "trail replayed"))
        st.walks := MnHeldWalks(m.io, st.at)
    return st.dead
}

Test_Minions_TrailKeepsTheMovesNotTheDodges() {
    m := MnTask(, , , MnHeldIO()), t := m.t, ctx := SchedCtx()
    t._Walk(ctx), t._Stop()
    t._Turn("Left", 250), t._Turn("Right", 250)      ; a look round: nothing kept
    t._Walk(ctx), t._Stop()
    t._Turn("Right", 100)
    t._Hold("a", 300, ctx, false)                    ; a dodge
    t._Strafe(ctx, "a", 1000, false), t._Strafe(ctx, "d", 1000, false)   ; there and back
    t._Walk(ctx), t._Hold("s", MinionsTask.WalkMs, ctx)
    t._Slide(ctx, "a"), t._Escape(ctx, ""), t._Escape(ctx, "d"), t._Strafe(ctx, "d", 400, true)
    t._Hold("s", 600, ctx)
    AssertEq(MnTrail(t._trail), "w 700@0 w 700@0 la 700@100 e 600@100 ed 600@100 pd 400@100 s 600@100", "the moves at their bearings")
}

; a strafe's w push is no move of its own; a turn and back between two
; undoing moves still undoes them, a turn away does not
Test_Minions_TrailPairsAtOneBearingOnly() {
    m := MnTask(, , , MnHeldIO()), t := m.t, ctx := SchedCtx()
    t._Strafe(ctx, "a", 1000, false)
    AssertEq(MnTrail(t._trail), "a 1000@0", "one entry")
    t._Turn("Right", 50)
    t._Strafe(ctx, "d", 1000, false)
    AssertEq(MnTrail(t._trail), "a 1000@0 d 1000@50", "another way: both kept")
    t._trailTo := 2
    t._Turn("Left", 3000)                            ; a full circle: the same way
    t._Strafe(ctx, "a", 1000, false)
    AssertEq(MnTrail(t._trail), "a 1000@0", "undone")
    AssertEq(t._trailTo, 1, "the sighting's count follows")
}

Test_Minions_ReplayOrderAndDurations() {
    m := MnTask(, , , MnHeldIO()), t := m.t, ctx := SchedCtx()
    f := {shift: 0, replay: 1, route: [{k: "w", ms: 700, b: 0}, {k: "w", ms: 700, b: 100}, {k: "s", ms: 600, b: 100}
        , {k: "w", ms: 300, b: 400}, {k: "la", ms: 700, b: 400}, {k: "ed", ms: 600, b: 400}, {k: "pa", ms: 400, b: 400}
        , {k: "t", ms: 0, b: 300}]}
    calls := 0
    while (f.replay && calls < 20)
        AssertTrue(t._Replay(ctx, f), "on"), calls++
    ; a small turn inside the walk, w down through both steps; a long one stands
    AssertEq(MnHeld(m.io), "Right 100, w 1400, s 600, Right 250, Right 50, w 300, a 700, w 700, d 600, w 600, a 400, s 400, Left 100"
        , "the moves in order, each turned to first")
    AssertEq(t._bearing, 300, "on the sighting's bearing")
    AssertEq(calls, 8, "two walks a look, a look after the long turn, one after each other move")
    AssertTrue(MnLogged(m, "trail replayed, nothing in sight"), "logged")
    AssertEq(MnTrail(t._trail), "w 700@0 w 700@100 s 600@100 w 300@400 la 700@400 ed 600@400 pa 400@400", "the replay is the trail")
}

Test_Minions_DeathReplaysTheTrail() {
    m := MnTask(, , , MnHeldIO())
    st := {dead: false, at: 0}
    m.t._scanFn := MnNearing(m, () => MnReplayed(m, st))
    m.t._deathFn := () => (!st.dead && MnHeldWalks(m.io) >= 6) ? (st.at := m.io.walks + 1, st.dead := true) : false
    m.t.Run(SchedCtx())
    AssertTrue(MnLogged(m, "died (the death screen) - back at spawn, replaying the trail"), "the death logged")
    AssertEq(MnLines(m, "replaying the trail, "), "minions: back to the fight - replaying the trail, 6 steps, 3500 ms", "the five walks to the last sighting and its bearing")
    AssertTrue(MnLogged(m, "trail replayed, nothing in sight"), "to its end")
    AssertEq(st.walks, 5, "the same walks, no more")
    AssertTrue(!MnLogged(m, "turning to bearing"), "not the old walk")
}

Test_Minions_ReplayStopsOnABar() {
    m := MnTask(, , , MnHeldIO())
    st := {dead: false, at: 0}
    seen := () => !st.dead || MnHeldWalks(m.io, st.at) >= 2
    m.t._scanFn := () => seen() ? [{x: 1280, y: 300 + 14 * MnHeldWalks(m.io), w: 40}] : []
    m.t._deathFn := () => (!st.dead && MnHeldWalks(m.io) >= 6) ? (st.at := m.io.walks + 1, st.dead := true) : false
    m.t.Run(SchedCtx())
    AssertEq(MnLines(m, "trail left"), "minions: a target in sight - trail left at step 3/6", "two walks, then the bar")
    AssertTrue(!MnLogged(m, "trail replayed"), "not walked to its end")
}

; the second life never reached the fight: the same route again
Test_Minions_TrailLastsThroughDeaths() {
    m := MnTask(, , , MnHeldIO())
    st := {dead: 0, at: 0}
    m.t._scanFn := MnNearing(m, () => MnReplayed(m, st))
    m.t._deathFn := () => ((st.dead = 0 && MnHeldWalks(m.io) >= 6) || (st.dead = 1 && MnHeldWalks(m.io, st.at) >= 3))
        ? (st.at := m.io.walks + 1, ++st.dead) : false
    m.t.Run(SchedCtx())
    AssertEq(MnLines(m, "replaying the trail, "), "minions: back to the fight - replaying the trail, 6 steps, 3500 ms|minions: back to the fight - replaying the trail, 6 steps, 3500 ms", "both deaths")
    AssertEq(st.walks, 5, "the whole way again")
    AssertTrue(InStr(MnStatsOf(m), " deaths=2"), "counted")
}

; a replay that reached the fight is the next death's route, what followed added
Test_Minions_TheReplayIsTheNextTrail() {
    m := MnTask(, , , MnHeldIO())
    st := {dead: 0, at: 0}
    m.t._scanFn := () => (st.dead = 1 && MnHeldWalks(m.io, st.at) < 2) || st.dead > 1 ? [] : [{x: 1280, y: 300 + 14 * MnHeldWalks(m.io), w: 40}]
    m.t._deathFn := () => ((st.dead = 0 && MnHeldWalks(m.io) >= 6) || (st.dead = 1 && MnHeldWalks(m.io, st.at) >= 5))
        ? (st.at := m.io.walks + 1, ++st.dead) : false
    m.t.Run(SchedCtx())
    AssertEq(MnLines(m, "trail left"), "minions: a target in sight - trail left at step 3/6", "left the first route")
    AssertEq(MnLines(m, "replaying the trail, "), "minions: back to the fight - replaying the trail, 6 steps, 3500 ms|minions: back to the fight - replaying the trail, 5 steps, 2800 ms"
        , "then two walks of it and two after it")
}

; the far glow L31 went after instead: after the replay, not during it
Test_Minions_ReplayGoesBeforeAGlow() {
    m := MnTask(, , , MnHeldIO())
    st := {dead: false}
    m.t._scanFn := MnNearing(m, () => st.dead)
    m.t._beaconFn := () => st.dead ? [{x: 1280 + MinionsTask.GlowAim(1), y: 700, r: 20}] : []
    m.t._deathFn := () => (!st.dead && MnHeldWalks(m.io) >= 6) ? (st.dead := true) : false
    m.t.Run(SchedCtx())
    i1 := MnLogAt(m, "trail replayed"), i2 := MnLogAt(m, "orb glow at")
    AssertTrue(i1 && i1 < i2, "the replay, then the glow: " i1 " " i2)
}

; the target of a fall's test: gone for good after n walks (st.gone: when)
MnFading(m, st, n) {
    if (st.dead || MnHeldWalks(m.io) >= n) {
        st.gone := st.gone ? st.gone : m.io.t
        return []
    }
    return [{x: 1280, y: 300 + 14 * MnHeldWalks(m.io), w: 40}]
}

; a fall: the last moves are the way off the island. Bars for 8 walks, then
; a walk off unseen: back to the sighting less the tail
Test_Minions_FallDropsTheTrailsTail() {
    m := MnTask(, , , MnHeldIO())
    st := {dead: false, at: 0, gone: 0}
    m.t._scanFn := () => MnFading(m, st, 8)
    m.t._deathFn := () => (!st.dead && st.gone && m.io.t - st.gone > MinionsTask.FallQuietMs + 1000) ? (st.at := m.io.walks + 1, st.dead := true) : false
    m.t.Run(SchedCtx())
    AssertTrue(MnLogged(m, "kept as the edge"), "a fall")
    AssertEq(MnLines(m, "replaying the trail, "), "minions: back to the fight - replaying the trail, 3 steps, 2100 ms", "seven walks to the last sighting less FallMarginMs and a walk")
    AssertTrue(MnLogged(m, "trail replayed, nothing in sight"), "the rest walked, the fall's own guard quiet")
    AssertEq(MnHeldWalks(m.io, st.at), 3, "stops short of the edge")
}

; a trail shorter than the tail: nothing left, no replay, no walk back
Test_Minions_NoReplayAfterAFallPastTheTail() {
    m := MnTask(, , , MnHeldIO())
    st := {dead: false, at: 0, gone: 0}
    m.t._scanFn := () => MnFading(m, st, 3)
    m.t._deathFn := () => (!st.dead && st.gone && m.io.t - st.gone > MinionsTask.FallQuietMs + 1000) ? (st.at := m.io.walks + 1, st.dead := true) : false
    m.t.Run(SchedCtx())
    AssertTrue(MnLogged(m, "kept as the edge"), "a fall")
    AssertTrue(!MnLogged(m, "replaying the trail"), "no replay")
    fell := MnLogAt(m, "kept as the edge")           ; the bar lost before it: walked back then
    for i, l in m.logs
        AssertTrue(i <= fell || !InStr(l, "back to the fight"), "no walk back after the fall: " l)
}

; a fall on the way, no bar since the respawn: not past the step that fell
Test_Minions_TrailRouteCutsAFallOnTheReplay() {
    m := MnTask(), t := m.t, r := []
    Loop 10
        r.Push({k: "w", ms: 700, b: 0})
    f := {route: r, replay: 9}                       ; step 8 was the last walked
    t._TrailRoute(f, true)
    AssertEq(f.route.Length, 4, "eight walks less the tail")
    AssertEq(f.replay, 0, "over")
    f := {route: [{k: "w", ms: 700, b: 0}], replay: 1}
    t._TrailRoute(f, false)
    AssertEq(f.route.Length, 1, "no fall: the route as it was")
}

; the bearings of a life without a re-aim are guesses: not a route
Test_Minions_NoRouteFromALifeNotReAimed() {
    m := MnTask(), t := m.t
    old := [{k: "w", ms: 700, b: 0}]
    f := {route: old, replay: 0}
    t._Note("w", 700), t._aimed := false
    t._TrailSeen(f)
    t._bearing := 300, t._Note("w", 300), t._TrailSeen(f)
    t._TrailRoute(f, false)
    AssertEq(MnTrail(f.route), "w 700@0", "the route before it")
    t._aimed := true
    t._Note("w", 700), t._bearing := 500, t._TrailSeen(f)
    t._TrailRoute(f, false)
    AssertEq(MnTrail(f.route), "w 700@300 t 0@500", "a re-aimed life's own, ending on the sighting's bearing")
}

; the walk turned round at an edge in view: the replay ends there
Test_Minions_ReplayEndsAtAnEdge() {
    m := MnTask(, , , MnHeldIO()), t := m.t, ctx := SchedCtx()
    t._viewFn := () => {edge: MnHeldWalks(m.io) >= 1, sig: []}
    f := {shift: 0, replay: 1, route: [{k: "w", ms: 700, b: 0}, {k: "w", ms: 700, b: 0}, {k: "w", ms: 700, b: 0}]}
    calls := 0
    while (f.replay && calls < 10)
        t._Replay(ctx, f), calls++
    AssertTrue(MnLogged(m, "an edge on the trail at step 2/3 - replay over"), "stopped there")
    AssertEq(MnHeldWalks(m.io), 1, "no walk past it")
}

; L36 09:02:08, L41 11:47:21: a remembered fall turned the plain trail round.
; It led to a bar: on it goes
Test_Minions_RememberedFallLeavesTheReplayOn() {
    m := MnTask(, , , MnHeldIO()), t := m.t, ctx := SchedCtx()
    t._falls := [{x: 0, y: 3000, b: 0, at: m.io.t}]
    f := {shift: 0, replay: 1, route: [{k: "w", ms: 700, b: 0}, {k: "w", ms: 700, b: 0}, {k: "w", ms: 700, b: 0}]}
    calls := 0
    while (f.replay && calls < 10)
        t._Replay(ctx, f), calls++
    AssertTrue(!MnLogged(m, "fell off the island this way"), "no turn")
    AssertTrue(MnLogged(m, "trail replayed"), "to its end")
    AssertEq(MnHeldWalks(m.io), 3, "every walk")
    AssertEq(t._toBar, false, "only for the replay")
}

; the fight's place, for the tests of the way back to it
MnHomeF(x, y, face := 0, at := "") => {shift: 0, home: 1, homeTo: {x: x, y: y}, homeWalks: "", ring: 0, ringAt: 0, ringFor: ""
    , fightPos: {x: x, y: y}, fightFace: face, fightAt: at}

; L39 11:08:21, L41 11:47:09: straight to where the fight was, not the 13 s
; and 40 s of trail; a remembered fall on the way does not turn it (L41 12:26:57)
Test_Minions_HomeStepWalksStraightToTheSpot() {
    m := MnTask(, , , MnHeldIO()), t := m.t, ctx := SchedCtx()
    t._falls := [{x: 3000, y: 0, b: 750, at: m.io.t}]
    f := MnHomeF(2100, 0), calls := 0
    while (f.home && calls < 20)
        AssertTrue(t._HomeStep(ctx, f), "on"), calls++
    AssertEq(MinionsTask.Wrap(t._bearing), 750, "a quarter turn right: the way from spawn")
    AssertEq(MnHeldWalks(m.io), 3, "the way's length in walks")
    AssertTrue(MinionsTask.Gap(t._pos, f.homeTo) <= MinionsTask.HomeNearMs, "there")
    AssertTrue(!MnLogged(m, "fell off the island this way"), "no turn at the remembered fall")
    AssertTrue(MnLogged(m, "where the fight was - looking round"), "logged")
    AssertEq(f.ring, MinionsTask.FullTurnMs // MinionsTask.ScanTurnMs, "a circle of looks next")
    AssertEq(t._toBar, false, "only for the way back")
}

; a wall: the walks run out, the look is from there
Test_Minions_HomeStepEndsWhenTheWalksRunOut() {
    m := MnTask(, , , MnHeldIO()), t := m.t, ctx := SchedCtx()
    f := MnHomeF(0, 7000), f.homeWalks := 2, calls := 0
    while (f.home && calls < 20)
        t._HomeStep(ctx, f), calls++
    AssertEq(MnHeldWalks(m.io), 2, "no more")
    AssertTrue(MnLogged(m, "ms short of the spot - looking round"), "logged")
}

; an edge in view is real: the look from here, no second go at it
Test_Minions_HomeStepStopsAtAnEdge() {
    m := MnTask(, , , MnHeldIO()), t := m.t, ctx := SchedCtx()
    t._viewFn := () => {edge: MnHeldWalks(m.io) >= 1, sig: []}
    f := MnHomeF(0, 7000), calls := 0
    while (f.home && calls < 20)
        t._HomeStep(ctx, f), calls++
    AssertEq(MnHeldWalks(m.io), 1, "no walk past it")
    AssertTrue(MnLogged(m, "an edge on the way back - looking round here"), "logged")
    AssertTrue(MnLogged(m, "as far as the way goes - looking round"), "then the look")
}

; a circle, the first look the way the target was; then a leg to the next
; point round the spot, a quarter turn on each time; all done: no more
Test_Minions_RingLooksRoundTheSpot() {
    m := MnTask(, , , MnHeldIO()), t := m.t, ctx := SchedCtx()
    f := MnHomeF(1000, 2000, 300, m.io.t), f.home := 0, n := MinionsTask.FullTurnMs // MinionsTask.ScanTurnMs
    f.ring := n
    t._RingStep(ctx, f)
    AssertEq(MinionsTask.Wrap(t._bearing), 300, "faces the target's way first")
    Loop n - 1
        t._RingStep(ctx, f)
    AssertEq(f.ring, 0, "a circle")
    AssertEq(f.home, 1, "on to the first point")
    u := MinionsTask.Way(300)
    AssertTrue(Abs(f.homeTo.x - (1000 + MinionsTask.RingMs * u.x)) < 1 && Abs(f.homeTo.y - (2000 + MinionsTask.RingMs * u.y)) < 1, "that way off the spot")
    f.ringAt := MinionsTask.RingPoints, f.home := 0, f.ring := 1
    t._RingStep(ctx, f)
    AssertEq(f.home, 0, "no more points")
    AssertEq(f.fightAt, "", "not looked for any more")
    AssertTrue(MnLogged(m, "no sign of the fight round where it was"), "logged")
    f := MnHomeF(0, 0, 0, m.io.t - MinionsTask.FightOpenMs - 1), f.home := 0, f.ring := 1
    t._RingStep(ctx, f)
    AssertEq(f.home, 0, "the fight old by now: no leg")
}

; a bar ends the way back and marks the place; a life not re-aimed only the time
Test_Minions_FightSeenMarksThePlace() {
    m := MnTask(), t := m.t
    f := MnHomeF(0, 0), f.ring := 3, f.ringAt := 2
    t._pos := {x: 100, y: 200}, t._bearing := 300, t._aimed := true
    t._FightSeen(f, {x: MinionsTask.CenterX + 360, w: 130})
    AssertEq(f.fightPos.x " " f.fightPos.y, "100 200", "beside it: the player's place")
    AssertEq(f.fightFace, 461, "the bar's way: 360 px right of the camera, 19 degrees")
    AssertEq(f.home " " f.ring " " f.ringAt, "0 0 0", "nothing to walk back to")
    AssertEq(f.fightAt, m.io.t, "when")
    t._pos.x := 9, m.io.t += 5, t._aimed := false
    t._FightSeen(f, {x: MinionsTask.CenterX, w: 130})
    AssertEq(f.fightPos.x, 100, "the guess of a life not re-aimed is no place")
    AssertEq(f.fightAt, m.io.t, "the fight is on all the same")
}

; L66 03:49:15 (bar 24 px), L69 17:51:29: a far bar lost, the looks went
; round the player's own spot. The place is out there along the bar's way
Test_Minions_FarBarMarksThePlaceOutThere() {
    m := MnTask(), t := m.t
    f := MnHomeF(0, 0)
    t._pos := {x: 100, y: 200}, t._bearing := 300, t._aimed := true
    t._FightSeen(f, {x: MinionsTask.CenterX, w: 30})
    AssertEq(f.fightFar, 3000, "a 30 px minion: 3 s out")
    AssertEq(Round(f.fightPos.x) " " Round(f.fightPos.y), "1863 2627", "3000 ms along bearing 300")
    AssertEq(MinionsTask.FarOf({w: 95, full: 190}, true), 0, "an orb's plate full width: beside")
    AssertEq(MinionsTask.FarOf({w: 95}, true), 1000, "an orb's plate half as wide: 1 s")
    AssertEq(MinionsTask.FarOf({w: 2}), MinionsTask.FarMaxMs, "capped")
}

; L66 04:17:51 / 06:39:31: far minions at 1748 and 2094 turned 250 ms at the
; short turn's speed, flew 900-1147 px to 848 / 947, back and forth, never a
; walk, lost. Now one turn lands within the lock
Test_Minions_FarMinionTurnLandsOnTheLock() {
    t := MinionsTask.TurnFor(1748, MinionsTask.LockTol, MinionsTask.LockPxPerMs, 1195)
    AssertEq(t.key " " t.ms, "Right 193", "220 px short, 333 px long")
    AssertTrue(Abs(1748 - Round(t.ms * MinionsTask.TurnPxPerMs) - 1195) <= MinionsTask.LockTol, "lands on the lock at the measured speed")
    AssertEq(MinionsTask.TurnFor(1400, MinionsTask.LockTol, MinionsTask.LockPxPerMs, 1195).ms, 93, "a short one as before")
}

; a far bar lost and not found where it was on screen: walked to, then the
; looks there (not a circle first)
Test_Minions_FarBarLostIsWalkedTo() {
    far := [{x: 1280, y: 600, w: 30}]
    m := MnTask([far, far, []])
    m.t.Run(SchedCtx())
    AssertTrue(MnLogged(m, "a far target lost - walking to it, 3000 ms"), "logged")
    i1 := MnLogAt(m, "a far target lost"), i2 := MnLogAt(m, "where the fight was - looking round")
    AssertTrue(i1 && i1 < i2, "the looks after the walk: " i1 " " i2)
    iW := QmObbyFirst(m.io, "down w"), iL := QmObbyFirst(m.io, "down Left")
    AssertTrue(iW > 0 && (!iL || iW < iL), "a walk before any look round: " iW " " iL)
}

Test_Minions_FightOpenAndLineBeats() {
    AssertTrue(MinionsTask.FightOpen(70000, 10000), "60 s ago")
    AssertTrue(!MinionsTask.FightOpen(70001, 10000), "longer")
    AssertTrue(!MinionsTask.FightOpen(70000, ""), "never seen")
    w := (n) => (r := [], MnPush(r, n), r)
    AssertTrue(MinionsTask.LineBeats([], {x: 0, y: 0}), "no trail")
    AssertTrue(!MinionsTask.LineBeats(w(4), {x: 0, y: 2800}), "a straight trail: it is known to be walkable")
    AssertTrue(!MinionsTask.LineBeats(w(2), {x: 0, y: 0}), "a short one")
    AssertTrue(MinionsTask.LineBeats(w(20), {x: 0, y: 2800}), "a wander")
}

MnPush(r, n) {
    Loop n
        r.Push({k: "w", ms: 700, b: 0})
}

; L37 09:44:45, L41 12:26:29: a life that saw the fight sooner, or from spawn
; (no trail at all), leaves the shorter way; one that wandered does not
Test_Minions_TrailRouteKeepsTheShortest() {
    m := MnTask(), t := m.t
    f := {route: [{k: "w", ms: 1400, b: 0}], replay: 0}
    t._Note("w", 700), t._Note("w", 700), t._bearing := 300, t._Note("w", 700), t._TrailSeen(f)
    t._TrailRoute(f, false)
    AssertEq(MnTrail(f.route), "w 1400@0", "the longer trail left")
    t._Note("w", 700), t._TrailSeen(f)
    t._TrailRoute(f, false)
    AssertEq(MnTrail(f.route), "w 700@300 t 0@300", "a shorter one taken")
    t._TrailSeen(f)
    t._TrailRoute(f, false)
    AssertEq(f.route.Length, 0, "seen from spawn: nothing to walk")
}

; L41 12:26:41 as it went: the bars seen from spawn off to the side, no
; trail. Before: 8 walks away. Now no walk, turned to where the bars were
Test_Minions_BarFromSpawnNoWalkAway() {
    m := MnTask(, , , MnTurnIO()), t := m.t
    st := {dead: false, again: false}
    near := [{x: 1280, y: 680, w: 200}]
    t._scanFn := () => (!st.dead ? (QmObbyDowns(m.io, "Left") >= 2 ? near : [])
        : MinionsTask.Wrap(t._bearing + 500) = 0 ? (st.again := true, near) : [])
    t._deathFn := () => (!st.dead && MnSkills(m.io) >= 3) ? (st.walks := MnWalks(m.io), st.dead := true) : false
    t._toastFn := () => st.again ? "orb" : ""
    t.Run(SchedCtx())
    AssertTrue(st.again, "seen again from spawn")
    AssertEq(MnWalks(m.io), st.walks, "not a walk after the death")
}

; L41 12:05:11, L37 10:01:28: the replay ends, nothing in sight, the patrol
; took over and the fight was never seen again. Now: a look there and round
; there first, the map after it
Test_Minions_PatrolWaitsForTheLookRound() {
    m := MnTask(, Map("Minions.patrol", 1), , MnHeldIO()), t := m.t
    st := {dead: false, at: 0}
    t._scanFn := MnNearing(m, () => MnReplayed(m, st))
    t._deathFn := () => (!st.dead && MnHeldWalks(m.io) >= 6) ? (st.at := m.io.walks + 1, st.dead := true) : false
    t.Run(SchedCtx())
    i1 := MnLogAt(m, "trail replayed"), i2 := MnLogAt(m, "where the fight was - looking round")
    i3 := MnLogAt(m, "round where the fight was (" MinionsTask.RingPoints "/"), i4 := MnLogAt(m, "no sign of the fight"), i5 := MnLogAt(m, "walking the map")
    AssertTrue(i1 && i1 < i2 && i2 < i3 && i3 < i4 && i4 < i5, "in that order: " i1 " " i2 " " i3 " " i4 " " i5)
    AssertEq(MnCount(m, "walking the map"), 1, "the map once, at the end")
}

; a patrol under way when the fight began goes on only after the look too
Test_Minions_APatrolOnStopsForAFightLost() {
    m := MnTask(, Map("Minions.patrol", 1), , MnHeldIO()), t := m.t
    st := {gone: false}
    t._scanFn := () => (MnLogged(m, "walking the map") && !st.gone && MnHeldWalks(m.io) < 4
        ? [{x: 1280, y: 300 + 14 * MnHeldWalks(m.io), w: 40}] : (MnHeldWalks(m.io) >= 4 ? (st.gone := true, []) : []))
    t.Run(SchedCtx())
    i1 := MnLogAt(m, "target at"), i2 := MnLogAt(m, "where the fight was - looking round"), i3 := MnLogAt(m, "no sign of the fight")
    AssertTrue(i1 && i1 < i2 && i2 < i3, "in that order: " i1 " " i2 " " i3)
}

; a fight over a minute old: the old ways, the map may start
Test_Minions_NoLookRoundForAnOldFight() {
    m := MnTask(), t := m.t
    f := MnHomeF(0, 0, 0, m.io.t - MinionsTask.FightOpenMs - 1)
    AssertTrue(!t._FightLost(f), "too old")
    f.fightAt := m.io.t
    AssertTrue(t._FightLost(f), "fresh")
    f.ringFor := f.fightAt
    AssertTrue(!t._FightLost(f), "once per sighting")
    f.ringFor := "", t._aimed := false
    AssertTrue(!t._FightLost(f), "no re-aim: no place to go to")
    t._aimed := true, f.fightPos := ""
    AssertTrue(!t._FightLost(f), "no place")
}

; the log lines with text, joined with "|"
MnLines(m, text) {
    out := ""
    for l in m.logs
        if InStr(l, text)
            out .= (out = "" ? "" : "|") l
    return out
}

MnLogCount(m, text) {
    n := 0
    for l in m.logs
        n += InStr(l, text) ? 1 : 0
    return n
}

; ---- the spots and the routes learned to them -------------------------------

; MnTask with the spots on (MnHeldIO: the holds kept)
MnSpotTask() => MnTask(, Map("Minions.spots", 1), , MnHeldIO())

; the orb's bar at bearing b as t sees it: in the scan area, wider the
; further the player has come along that way
MnOrbBar(t, b) {
    d := MinionsTask.Wrap(b - t._bearing), c := MinionsTask.FullTurnMs
    if (Abs(d) >= c // 4)                        ; behind the camera
        return []
    x := 1280 + Round(MinionsTask.FocalPx * Tan(2 * 3.141592653589793 * d / c))
    if (x < 560 || x > 2240)
        return []
    return [{x: x, y: 300, w: Max(30, 50 + MinionsTask.Along(t._pos, b) * 20 // 700)}]
}

; a route of n walks at bearing b, its last bearing as _RouteLearn leaves it
MnRoute(n, b := 0, fails := 0) {
    steps := []
    Loop n
        steps.Push({k: "w", ms: MinionsTask.WalkMs, b: b})
    steps.Push({k: "t", ms: 0, b: b})
    return {ms: n * MinionsTask.WalkMs, fails: fails, steps: steps}
}

; what _RouteStep and _RouteLearn read of the fight
MnRouteFight(spot, why := "", route := "") => {spot: spot, spotAt: 0, rWhy: why, rEdge: false, rUsed: false, rTried: false
    , route: IsObject(route) ? route : [], replay: IsObject(route) ? 1 : 0, shift: 0}

; a whole route of f stepped through
MnRouteOut(t, f) {
    ctx := SchedCtx()
    while f.replay
        t._RouteStep(ctx, f, false)
}

; lines of the real runs (L31, L22, L27, L32, L23, L34) and their bearings on
; the true circle: atan of the px off the centre, 8.33 ms a degree, mod 3000.
; On the old circle of 1250 the first two were one spot at 849 and 847
Test_Minions_AbsBearingOfRealLogLines() {
    lines := [["07:07:15 minions: target at 736,52 (bar 54 px) - bearing -1500 ms", 1268]
        , ["17:17:29 minions: target at 730,148 (bar 44 px) - bearing -250 ms", 2515]
        , ["23:14:58 minions: target at 2220,234 (bar 40 px) - bearing 0 ms", 354]
        , ["07:23:32 minions: target at 1442,120 (bar 56 px) - bearing -2250 ms", 825]
        , ["18:04:57 minions: target at 884,90 (bar 50 px) - bearing -2000 ms", 824]
        , ["08:06:48 minions: target at 820,90 (bar 40 px) - bearing -1000 ms", 1799]]
    for l in lines {
        AssertTrue(RegExMatch(l[1], "target at (\d+),\d+ .* bearing (-?\d+) ms", &m), "the line reads")
        AssertEq(MinionsTask.AbsBearing(Integer(m[2]), Integer(m[1])), l[2], l[1])
    }
    AssertEq(MinionsTask.AbsBearing(0, 1280), 0, "ahead")
    AssertEq(MinionsTask.AbsBearing(0, 1100), 2917, "left of ahead wraps")
    AssertEq(MinionsTask.AbsBearing(0, 2240), 359, "the Area's right edge: 43 degrees, not 960 / 3.6")
    AssertEq(MinionsTask.AbsBearing(0, 560), 2708, "its left edge: 35 degrees")
    AssertTrue(!IsObject(MinionsTask.SpotOf(700)), "no spot there")
}

; whole circles count for nothing, whatever the turns of a long hunt
Test_Minions_AbsBearingSameAWholeCircleOn() {
    for x in [560, 1100, 1280, 1500, 2240] {
        a := MinionsTask.AbsBearing(0, x)
        AssertEq(MinionsTask.AbsBearing(-3000, x), a, "a circle left at " x)
        AssertEq(MinionsTask.AbsBearing(3000, x), a, "a circle right at " x)
        AssertEq(MinionsTask.AbsBearing(-21000, x), a, "seven circles at " x)
        AssertTrue(a >= 0 && a < MinionsTask.FullTurnMs, "in the circle: " a)
    }
    AssertTrue(MinionsTask.AbsBearing(-1250, 1280) != MinionsTask.AbsBearing(0, 1280), "1250 is no circle")
}

; a circle of looks is a circle: 6 looks, the view of each overlapping the next
Test_Minions_LooksMakeTrueCircles() {
    c := MinionsTask.FullTurnMs
    AssertEq(c, 3000, "120 degrees a second")
    AssertEq(MinionsTask.SweepTurns * MinionsTask.ScanTurnMs, c, "the sweep, the look before the map walk: one circle")
    AssertEq(MinionsTask.ScanTurns * MinionsTask.ScanTurnMs, c, "before a respawn wait: one")
    a := MinionsTask.Area
    AssertTrue(MinionsTask.AbsBearing(0, a.x2) + c - MinionsTask.AbsBearing(0, a.x1) > MinionsTask.ScanTurnMs, "the Area wider than a step")
    AssertEq(MinionsTask.RouteCone, c // 4, "90 degrees")
    AssertEq(MinionsTask.WallOffCone, c // 8, "45 degrees")
}

Test_Minions_PosBearingIsTheWayOut() {
    for b in [0, 120, 265, 625, 850, 1198] {
        u := MinionsTask.Way(b)
        AssertEq(MinionsTask.PosBearing({x: 5000 * u.x, y: 5000 * u.y}), b, "out along " b)
    }
    AssertEq(MinionsTask.PosBearing({x: 0, y: 0}), "", "at spawn")
}

; Spots' b are false on the true circle (the shipped macro has no Minions.spots
; key, only hunt_loop set it): off unless asked for, the plain look from spawn
Test_Minions_SpotsOffByDefault() {
    m := MnTask(), t := m.t
    t._env.cfg.g.Delete("Minions.spots")
    AssertTrue(!t._SpotsOn(), "no key: off")
    t._SpotLook(SchedCtx(), MnRouteFight(""))
    AssertEq(t._bearing, -MinionsTask.ScanTurnMs, "a plain look")
    AssertTrue(!MnLogged(m, "looking at the spots"), "not the spots")
    AssertTrue(MnSpotTask().t._SpotsOn(), "asked for: on")
}

Test_Minions_SpotsAreLookedAtInOrder() {
    m := MnSpotTask(), t := m.t, ctx := SchedCtx(), f := MnRouteFight("")
    got := ""
    Loop MinionsTask.Spots.Length + 1 {
        t._SpotLook(ctx, f)
        got .= (got = "" ? "" : " ") Mod(t._bearing + 10 * MinionsTask.FullTurnMs, MinionsTask.FullTurnMs)
    }
    AssertEq(got, "850 265 385 120 1198 574 850", "the likeliest first, then round again")
    t._Note("w", 700), b := t._bearing
    t._SpotLook(ctx, f)
    AssertEq(t._bearing, b - MinionsTask.ScanTurnMs, "walked off: the plain look")
}

Test_Minions_HuntLooksAtTheSpotsFirst() {
    m := MnSpotTask(), t := m.t, seen := []
    t._biomeAt := m.io.t                         ; the orbs not due yet
    t._scanFn := () => (seen.Push(Mod(t._bearing + 10 * MinionsTask.FullTurnMs, MinionsTask.FullTurnMs)), [])
    t.Run(SchedCtx())
    AssertEq(seen[2] " " seen[3] " " seen[4] " " seen[5], "850 265 385 120", "no blind circle")
    AssertTrue(MnLogged(m, "looking at the spots"), "logged")
}

Test_Minions_RouteStoredOnBeside() {
    m := MnSpotTask(), t := m.t
    t._scanFn := () => MnOrbBar(t, 850)
    t._toastFn := () => MnLogged(m, "learned") ? "orb" : ""
    t.Run(SchedCtx())
    AssertTrue(MnLogged(m, "route to spot 850 learned"), "learned")
    r := t._routes["850"]
    AssertEq(r.steps[-1].k, "t", "ends on the fight's bearing")
    AssertEq(r.ms, MinionsTask.TrailMs(r.steps), "its length")
    AssertTrue(r.steps.Length > 3, "the walks in")
}

Test_Minions_ShortestRouteKept() {
    m := MnSpotTask(), t := m.t, f := MnRouteFight("850")
    t._routes["850"] := MnRoute(5)
    t._trail := MnRoute(7).steps
    t._RouteLearn(f)
    AssertEq(t._routes["850"].ms, 5 * MinionsTask.WalkMs, "a longer one left")
    t._trail := MnRoute(3).steps
    t._RouteLearn(f)
    AssertEq(t._routes["850"].ms, 3 * MinionsTask.WalkMs, "a shorter one taken")
}

Test_Minions_RouteLearnedByWhereThePlayerStands() {
    m := MnSpotTask(), t := m.t, f := MnRouteFight("")
    u := MinionsTask.Way(280)
    t._trail := MnRoute(3, 280).steps, t._pos := {x: 3000 * u.x, y: 3000 * u.y}
    t._RouteLearn(f)
    AssertTrue(t._routes.Has("265"), "no spot seen from spawn: the way the player went")
    f := MnRouteFight(""), u := MinionsTask.Way(2000)
    t._pos := {x: 3000 * u.x, y: 3000 * u.y}
    t._RouteLearn(f)
    AssertEq(t._routes.Count, 1, "no spot that way: nothing stored")
}

Test_Minions_FailedRouteDropped() {
    m := MnSpotTask(), t := m.t
    t._routes["850"] := MnRoute(1)
    MnRouteOut(t, MnRouteFight("850", "glow", MnRoute(1).steps))
    AssertEq(t._routes["850"].fails, 1, "one fail, kept")
    MnRouteOut(t, MnRouteFight("850", "bar", MnRoute(1).steps))
    AssertTrue(!t._routes.Has("850"), "two: dropped")
    AssertTrue(MnLogged(m, "failed 2 times - dropped"), "logged")
}

Test_Minions_BlindRouteWithNoOrbIsNoFail() {
    m := MnSpotTask(), t := m.t
    t._routes["850"] := MnRoute(1)
    MnRouteOut(t, MnRouteFight("850", "due", MnRoute(1).steps))
    AssertEq(t._routes["850"].fails, 0, "no orb there today: the route is not to blame")
}

Test_Minions_EdgeFailsABlindRoute() {
    m := MnSpotTask(), t := m.t
    t._routes["850"] := MnRoute(2)
    t._viewFn := () => {edge: true, sig: []}
    MnRouteOut(t, MnRouteFight("850", "due", MnRoute(2).steps))
    AssertEq(t._routes["850"].fails, 1, "the way itself went wrong")
}

Test_Minions_ArrivingClearsAFail() {
    m := MnSpotTask(), t := m.t, f := MnRouteFight("850")
    t._routes["850"] := MnRoute(2, 0, 1), f.rUsed := true
    t._trail := MnRoute(4).steps
    t._RouteLearn(f)
    AssertEq(t._routes["850"].fails, 0, "it led here")
}

Test_Minions_NextHuntReplaysTheRoute() {
    m := MnSpotTask(), t := m.t, st := {n: 0}
    t._scanFn := () => MnOrbBar(t, 850)
    t._toastFn := () => MnLogCount(m, "beside it") > st.n ? "orb" : ""
    t.Run(SchedCtx())
    AssertEq(MnLogCount(m, "replaying the stored route"), 0, "the first hunt walks")
    ms := t._routes["850"].ms
    st.n := MnLogCount(m, "beside it"), t._biomeAt := m.io.t      ; the orbs not due: the bar starts it
    t.Run(SchedCtx())
    AssertEq(MnLogCount(m, "spot 850 (bar) - replaying the stored route"), 1, "the second replays it at once")
    AssertTrue(MnLogged(m, "trail left at step"), "a bar near ends it")
    AssertEq(t._routes["850"].ms, ms, "the same way, not stored again")
}

Test_Minions_FarBarDoesNotEndAStoredRoute() {
    m := MnSpotTask(), t := m.t, f := MnRouteFight("850", "bar", MnRoute(4).steps)
    t._trail.Push({k: "w", ms: 700, b: 0})
    far := {x: 1280, y: 300, w: 40}, near := {x: 1280, y: 600, w: 110}
    AssertTrue(t._RouteBar(f, {orb: "", minions: [far], anchor: far}, far), "far: on")
    AssertTrue(!t._RouteBar(f, {orb: "", minions: [near], anchor: near}, near), "near: over")
}

Test_Minions_BlindRouteLeftForABarElsewhere() {
    m := MnSpotTask(), t := m.t, f := MnRouteFight("850", "due", MnRoute(4, 0).steps)
    t._trail.Push({k: "w", ms: 700, b: 0})
    b := {x: 1280, y: 300, w: 40}, v := {orb: "", minions: [b], anchor: b}
    t._bearing := MinionsTask.FullTurnMs // 2
    AssertTrue(!t._RouteBar(f, v, b), "behind the way it goes: left")
    t._bearing := 100
    AssertTrue(t._RouteBar(f, v, b), "about ahead: on")
}

Test_Minions_GlowAtASpotStartsItsRoute() {
    m := MnSpotTask(), t := m.t, f := MnRouteFight("")
    t._routes["850"] := MnRoute(2)
    AssertTrue(!t._RouteGlow(f, {x: 1280, r: 80}), "no spot ahead at bearing 0")
    t._bearing := 850
    AssertTrue(t._RouteGlow(f, {x: 1300, r: 80}), "the spot's glow")
    AssertEq(f.rWhy, "glow", "why")
    AssertEq(f.replay, 1, "from its start")
}

Test_Minions_DueRouteOnceAHunt() {
    m := MnSpotTask(), t := m.t
    t._routes["265"] := MnRoute(2, 265)
    t._routes["120"] := MnRoute(2, 120)
    t._scanFn := () => []
    t.Run(SchedCtx())
    AssertEq(MnLogCount(m, "(due) - replaying the stored route"), 1, "one blind route")
    AssertTrue(MnLogged(m, "spot 265 (due)"), "the likeliest spot with one")
    AssertTrue(t._routes.Has("265"), "kept")
}

; a stored route waits for the circle too: 12 of 15 early sightings need it
Test_Minions_DueRouteAfterTheCircle() {
    m := MnSpotTask(), t := m.t, st := {scans: 0, at: 0}
    t.CanRun(m.state)
    t._routes["265"] := MnRoute(2, 265)
    t._scanFn := () => (st.scans++, !st.at && MnLogged(m, "(due)") ? st.at := st.scans : 0, [])
    t.Run(SchedCtx())
    AssertTrue(st.at > MinionsTask.SweepTurns, "after the circle: scan " st.at)
    AssertEq(MnLogCount(m, "(due) - replaying the stored route"), 1, "then the route")
}

Test_Minions_DeathTakesTheStoredRoute() {
    m := MnSpotTask(), t := m.t, st := {dead: false}
    t._routes["850"] := MnRoute(2, 850)
    t._scanFn := () => MnOrbBar(t, 850)
    t._deathFn := () => (!st.dead && MnLogged(m, "beside it")) ? (st.dead := true) : false
    t._toastFn := () => MnLogged(m, "back to the fight") ? "orb" : ""
    t.Run(SchedCtx())
    AssertTrue(MnLogged(m, "back to the fight - replaying the stored route"), "not the trail")
}

Test_Minions_UnknownSpotFallsBack() {
    m := MnSpotTask(), t := m.t
    t._routes["850"] := MnRoute(2, 850)
    t._biomeAt := m.io.t
    t._scanFn := () => MnOrbBar(t, 1500)
    t._toastFn := () => MnLogged(m, "beside it") ? "orb" : ""
    t.Run(SchedCtx())
    AssertTrue(MnLogged(m, "beside it"), "walked straight to it")
    AssertTrue(!MnLogged(m, "replaying the stored route"), "no route used")
    AssertEq(t._routes.Count, 1, "none learned: no spot there")
}

Test_Minions_SpotWithNoRouteWalksAndLearns() {
    m := MnSpotTask(), t := m.t
    t._routes["265"] := MnRoute(2, 265)
    t._biomeAt := m.io.t
    t._scanFn := () => MnOrbBar(t, 850)
    t._toastFn := () => MnLogged(m, "learned") ? "orb" : ""
    t.Run(SchedCtx())
    AssertTrue(!MnLogged(m, "replaying the stored route"), "as before")
    AssertTrue(t._routes.Has("850"), "and learned")
}

Test_Minions_RoutesFileRoundTrip() {
    path := A_Temp "\vesper_routes_test_" A_TickCount ".json"
    try {
        m := MnSpotTask(), t := m.t, f := MnRouteFight("850")
        t._routesFile := path
        t._trail := MnRoute(3, 850).steps
        t._RouteLearn(f)
        n := MnSpotTask(), n.t._routesFile := path
        n.t._RoutesRead()
        AssertEq(MnTrail(n.t._routes["850"].steps), MnTrail(t._routes["850"].steps), "the same steps")
        AssertEq(n.t._routes["850"].ms, 3 * MinionsTask.WalkMs, "its length")
        FileDelete(path)
        FileAppend("not json", path)
        b := MnSpotTask(), b.t._routesFile := path
        b.t._RoutesRead()
        AssertEq(b.t._routes.Count, 0, "a bad file: none")
        AssertTrue(MnLogged(b, "unreadable"), "logged")
    } finally {
        try FileDelete(path)
    }
}

; ---- moves held across the scans (the user: "instead of move stop move stop") --

; a fake scan that takes ms of the clock, as the real grabs do
MnSlow(m, ms, frames) {
    n := 0
    return () => (m.io.t += ms, frames[Min(++n, frames.Length)])
}

; a far target that nears with every walk, a scan taking ms
MnNearingSlow(m, ms) => () => (m.io.t += ms, [{x: 1280, y: 300 + 14 * MnWalks(m.io), w: 40}])

; k down right now
MnKeyDown(io, k) => io.keysDown.Has(k)

Test_Minions_WalkKeepsWDownBetweenSteps() {
    m := MnTask(, , , MnHeldIO()), t := m.t, ctx := SchedCtx()
    t._Walk(ctx), t._Walk(ctx), t._Walk(ctx)
    AssertEq(MnDowns(m.io, "w") " " MnUps(m.io, "w"), "1 0", "one press, no release")
    AssertEq(m.io.walks, 3, "each step its jump")
    t._Stop()
    AssertEq(MnHeld(m.io), "w 2100", "up on the stop, held all along")
    AssertTrue(!IsObject(t._held) && !Input._held.Has("w"), "nothing left held")
    t._Stop()
    AssertEq(MnUps(m.io, "w"), 1, "a second stop sends nothing")
}

; the scan's time is in the step, no time is lost or counted twice
Test_Minions_StepsCountTheScansBetweenThem() {
    m := MnTask(), t := m.t, ctx := SchedCtx(), t0 := m.io.t
    t._Walk(ctx)
    m.io.t += 200                                    ; a scan, w down
    t._Walk(ctx)
    AssertEq(m.io.t - t0, 2 * MinionsTask.WalkMs, "the step is shorter by the scan")
    AssertEq(MnTrail(t._trail), "w 700@0 w 700@0", "whole steps on the trail")
    AssertEq(Round(t._pos.y), 1400, "and in the position")
    m.io.t += 900                                    ; a scan longer than a step
    t._Walk(ctx)
    AssertEq(m.io.t - t0, 2360, "no wait left but the jump's tap")
    AssertEq(MnTrail(t._trail), "w 700@0 w 700@0 w 960@0", "its time as it was")
    AssertEq(Round(t._pos.y), 2360, "the position sums the time held")
    t._Stop()
    AssertEq(MinionsTask.TrailMs(t._trail), 2360, "the trail too")
}

; an aim tap with w down: no release; the way so far on the old bearing
Test_Minions_TurnsWhileWalking() {
    m := MnTask(), t := m.t, ctx := SchedCtx()
    t._Walk(ctx)
    m.io.t += 100
    q := 312                                     ; shorter than the walk: its time runs on through the taps
    t._Turn("Right", 200), t._Turn("Right", q - 200)
    AssertEq(MnUps(m.io, "w"), 0, "w down through the turns")
    t._Walk(ctx)
    AssertEq(MnDowns(m.io, "w"), 1, "the same press")
    t._Stop()
    AssertEq(MnTrail(t._trail), "w 700@0 w 700@" q, "a step each, at the bearing it ended on")
    ; 800 ms ahead, the first tap's 200 at its bearing, the rest of the step at the last
    a := MinionsTask.Way(200), b := MinionsTask.Way(q)
    AssertEq(Round(t._pos.x) " " Round(t._pos.y), Round(200 * a.x + 400 * b.x) " " Round(800 + 200 * a.y + 400 * b.y), "the way bent with the bearing")
}

; a look's worth of turn: not walked through. 250 ms, 30 degrees, whatever the
; step of a look round: at 500 a turn of 60 degrees would keep w down, no look
Test_Minions_LongTurnStopsTheWalk() {
    m := MnTask(), t := m.t, ctx := SchedCtx()
    AssertEq(MinionsTask.BigTurnMs, 250, "30 degrees")
    t._Walk(ctx)
    t._TurnBy(ctx, MinionsTask.BigTurnMs - 1)
    AssertEq(MnUps(m.io, "w"), 0, "a small one on the move")
    t._TurnBy(ctx, MinionsTask.BigTurnMs)
    i := m.io.Index("up w")
    AssertTrue(i > 0 && i < MnNth(m.io, "down Right", 2), "up before a long one")
}

; the same line in a replay and on the way home: a turn of BigTurnMs and up
; stands for a look, under ScanTurnMs too
Test_Minions_ReplayAndHomeLookAfterABigTurn() {
    m := MnTask(, , , MnHeldIO()), t := m.t, ctx := SchedCtx()
    f := {shift: 0, replay: 1, route: [{k: "w", ms: 700, b: 300}, {k: "w", ms: 700, b: 300}]}
    t._Replay(ctx, f)
    AssertEq(t._bearing " " f.replay " " MnHeldWalks(m.io), "300 1 0", "a replay: turned, no walk yet")
    m := MnTask(, , , MnHeldIO()), t := m.t
    u := MinionsTask.Way(300), f := MnHomeF(5000 * u.x, 5000 * u.y)
    t._HomeStep(ctx, f)
    AssertEq(t._bearing " " MnHeldWalks(m.io), "300 0", "home: turned, no walk yet")
}

Test_Minions_HuntWalksWithoutARelease() {
    m := MnTask()
    ctx := SchedCtx(), ups := -1
    scan := MnNearingSlow(m, 150)
    m.t._scanFn := () => (MnWalks(m.io) >= 8 ? (ups := MnUps(m.io, "w"), ctx.Stop(), scan()) : scan())
    MnWalkFight(m, ctx)
    AssertTrue(MnWalks(m.io) >= 8, "walked: " MnWalks(m.io))
    AssertEq(ups, 0, "eight walks with their scans, w never up")
    AssertEq(MnDowns(m.io, "w"), 1, "one press")
    AssertTrue(MnUps(m.io, "w") = 1 && !MnKeyDown(m.io, "w"), "up when the hunt stopped")
}

; off centre with w down: the turn, a look, the walk on: one press
Test_Minions_AimTurnKeepsTheWalk() {
    m := MnTask()
    ctx := SchedCtx(), n := 0
    m.t._scanFn := () => (++n >= 16 ? (ctx.Stop(), []) : [{x: Mod(n // 2, 2) ? 1000 : 1280, y: 300 + 14 * n, w: 40}])
    m.t._lock := true
    f := MnWalkFight(m, ctx)
    AssertTrue(MnDowns(m.io, "Left") >= 2, "turned on the way: " MnDowns(m.io, "Left"))
    AssertEq(MnDowns(m.io, "w"), 1, "one press through the turns")
}

; _Fight alone: no respawn, no aura
MnWalkFight(m, ctx) {
    m.t._swap.wear := "Eden"
    return m.t._Fight(ctx)
}

Test_Minions_StopMidWalkReleases() {
    m := MnTask(), t := m.t, ctx := SchedCtx()
    t0 := m.io.t
    t._Walk(ctx)
    ctx.Stop()
    AssertEq(t._Walk(ctx), false, "stopped")
    AssertEq(MnUps(m.io, "w"), 1, "w up at once")
    AssertTrue(!IsObject(t._held), "nothing held")
    held := m.io.t - t0
    AssertTrue(held < 2 * MinionsTask.WalkMs, "the step cut short: " held)
    AssertEq(Round(t._pos.y), held, "the position: only the time held")
    AssertEq(MinionsTask.TrailMs(t._trail), held, "the trail too")
}

Test_Minions_ErrorInTheFightReleases() {
    m := MnTask()
    n := 0
    m.t._scanFn := () => (++n = 4 ? MnThrow("the grab broke") : [{x: 1280, y: 300 + 14 * n, w: 40}])
    err := ""
    try
        MnWalkFight(m, SchedCtx())
    catch as e
        err := e.Message
    AssertEq(err, "the grab broke", "the error goes on up")
    AssertEq(MnDowns(m.io, "w") " " MnUps(m.io, "w"), "1 1", "w was down and came up")
    AssertTrue(!Input._held.Has("w"), "no key in the registry")
}

MnThrow(msg) {
    throw Error(msg)
}

Test_Minions_DeathReleasesFirst() {
    m := MnTask()
    st := {dead: false, w: ""}
    m.t._scanFn := () => st.dead ? [] : [{x: 1280, y: 300 + 14 * MnWalks(m.io), w: 40}]
    m.t._deathFn := () => (!st.dead && MnWalks(m.io) >= 4) ? (st.dead := true) : false
    m.t.DefineProp("_TrailRoute", {Call: (s, f, fell) => (st.w := MnKeyDown(m.io, "w"), 0)})
    m.t.Run(SchedCtx())
    AssertEq(st.w, false, "w up before the death is handled")
    AssertTrue(MnWalks(m.io) >= 4, "it had walked")
}

Test_Minions_MenuReleasesFirst() {
    m := MnTask()
    ctx := SchedCtx(), n := 0
    m.t._scanFn := () => (++n >= 40 ? (ctx.Stop(), []) : [{x: 1280, y: 300 + 14 * n, w: 40}])
    at := {up: -1}
    m.t._swap.DefineProp("Covered", {Call: (s) => (MnWalks(m.io) >= 9 && at.up < 0) ? (at.up := 0, "storage") : ""})
    m.t._swap.DefineProp("ClearView", {Call: (s, c) => (at.up := MnKeyDown(m.io, "w") ? 2 : 1, "")})
    MnWalkFight(m, ctx)
    AssertEq(at.up, 1, "w up before the menu's clicks")
}

Test_Minions_EndOfTheHuntReleases() {
    m := MnTask(, Map("Minions.maxSec", 3))
    m.t._scanFn := () => [{x: 1280, y: 300 + 14 * MnWalks(m.io), w: 40}]
    sweep := {w: -1}
    m.t.DefineProp("_Sweep", {Call: (s, c, l, sh) => (sweep.w := MnKeyDown(m.io, "w"), {left: 0, orb: 0})})
    MnWalkFight(m, SchedCtx())
    AssertTrue(MnWalks(m.io) >= 2, "it walked")
    AssertEq(sweep.w, false, "up before the sweep")
}

; no step asked for in a tick: the move ends with it
Test_Minions_TickWithNoStepEndsTheMove() {
    m := MnTask(), t := m.t, ctx := SchedCtx()
    f := {look: 0, atBars: false, tickEnd: m.io.t, ticks: {fight: {n: 0, ms: 0, look: 0, parts: MinionsTask._NoParts()}, seek: {n: 0, ms: 0, look: 0, parts: MinionsTask._NoParts()}}}
    t.DefineProp("_FightStep", {Call: (s, c, f, b) => s._Walk(c)})
    t._Timed(ctx, f, "")
    AssertTrue(MnKeyDown(m.io, "w"), "a walk: down")
    t.DefineProp("_FightStep", {Call: (s, c, f, b) => s._Keep()})
    t._Timed(ctx, f, "")
    AssertTrue(MnKeyDown(m.io, "w"), "a look again: down")
    m.io.t += MinionsTask.WalkMs
    t._Timed(ctx, f, "")
    AssertTrue(!MnKeyDown(m.io, "w"), "a step overdue: up, the edge not looked at")
    t.DefineProp("_FightStep", {Call: (s, c, f, b) => s._Walk(c)})
    t._Timed(ctx, f, "")
    t.DefineProp("_FightStep", {Call: (s, c, f, b) => true})
    t._Timed(ctx, f, "")
    AssertTrue(!MnKeyDown(m.io, "w"), "nothing asked for: up")
}

; something else let go (F2's ReleaseAll): pressed again, not counted as down
Test_Minions_ReleaseAllLiftsTheMoveAndWalkPressesAgain() {
    m := MnTask(), t := m.t, ctx := SchedCtx()
    t._Walk(ctx)
    AssertTrue(Input._held.Has("w"), "in Input's registry")
    Input.ReleaseAll()
    AssertTrue(!MnKeyDown(m.io, "w"), "ReleaseAll lifts it")
    t._Walk(ctx)
    AssertTrue(MnKeyDown(m.io, "w"), "the next step presses it again")
    t._Stop()
    AssertTrue(!Input._held.Has("w"), "gone")
}

; the wall check by time: near steps do not compare a view with a moment ago
Test_Minions_WallCheckComparesOverTime() {
    m := MnTask(), t := m.t, ctx := SchedCtx(), n := 0
    t._viewFn := () => (n++, {edge: false, sig: [1, 2, 3]})
    t._Walk(ctx, MinionsTask.NearStepMs)
    AssertEq(t._stills, 0, "no view to compare yet")
    t._Walk(ctx, MinionsTask.NearStepMs)
    AssertEq(t._stills, 0, "300 ms on: too soon")
    t._Walk(ctx, MinionsTask.NearStepMs)
    AssertEq(t._stills, 1, "600 ms on: the same view")
    t._Walk(ctx)
    AssertEq(t._stills, 2, "a whole step on")
    t := MnTask().t, n := 0
    t._viewFn := () => {edge: false, sig: [(++n * 40 * 0x010101) & 0xFFFFFF]}
    t._Walk(ctx), t._Walk(ctx), t._Walk(ctx)
    AssertEq(t._stills, 0, "the view changing over time")
}

; ---- the fight: the strafe held through the ticks ---------------------------

; a fight of ticks: three minions and the orb beside the player, n scans of ms each
MnStrafeFight(ms, n, prep := "") {
    m := MnTask()
    ctx := SchedCtx(), k := 0
    bars := [{x: 1280, y: 300, w: 200, full: 200, fill: 1}, {x: 1100, y: 600, w: 130, full: 130, fill: 1}, {x: 1400, y: 600, w: 130, full: 130, fill: 1}]
    m.t._scanFn := () => (m.io.t += ms, ++k >= n ? (ctx.Stop(), bars) : bars)
    m.t._lock := true
    if IsObject(prep)
        prep(m)
    MnWalkFight(m, ctx)
    return m
}

Test_Minions_StrafeHeldThroughTheCasts() {
    m := MnStrafeFight(150, 6)
    iA := QmObbyFirst(m.io, "down a"), iUp := QmObbyFirst(m.io, "up a")
    AssertTrue(iA > 0 && iUp > iA, "a down, then up: " iA " " iUp)
    AssertEq(MnDowns(m.io, "a"), 1, "one press for the run")
    AssertTrue(!MnKeyDown(m.io, "a") && !MnKeyDown(m.io, "d"), "all up at the end")
    m := MnStrafeFight(150, 40)
    n := 0, side := 0
    for e in m.io.log {
        side += (e == "down a" || e == "down d") ? 1 : (e == "up a" || e == "up d") ? -1 : 0
        n += (side && RegExMatch(e, "^down [tfeqvr]$")) ? 1 : 0
    }
    AssertTrue(n >= 3, "skills sent with a side key down: " n)
    AssertEq(MnSkills(m.io), n + 1, "all but the first, before the first step")
}

; flips by time: DodgeRun steps' worth a side, scans or no scans
Test_Minions_StrafeFlipsByTime() {
    runMs := MinionsTask.DodgeRun * MinionsTask.DodgeStepMs
    m := MnStrafeFight(150, 3 * runMs // MinionsTask.FightTickMs)
    AssertEq(MnDowns(m.io, "a") " " MnDowns(m.io, "d"), "2 1", "a, d, a")
    aOff := MnNth(m.io, "down d", 1), aOn := QmObbyFirst(m.io, "down a")
    AssertTrue(MnUps(m.io, "a") >= 1 && QmObbyFirst(m.io, "up a") < aOff, "one side up before the other goes down")
    held := m.io.downAt[aOff] - m.io.downAt[aOn]
    AssertTrue(held >= runMs && held <= runMs + MinionsTask.DodgeStepMs, "a run's time, whatever a tick takes: " held)
    ; slow scans: a step per scan, the same time a side
    m := MnStrafeFight(700, 8)
    aOff := MnNth(m.io, "down d", 1), aOn := QmObbyFirst(m.io, "down a")
    held := m.io.downAt[aOff] - m.io.downAt[aOn]
    ; a tick here ~790 ms; the key goes down at a slow tick's end, the flip comes at a tick's start
    AssertTrue(held >= runMs && held <= runMs + 2 * 800, "with 700 ms ticks too, to two ticks: " held)
}

; the sea comes into view on the side held: up at once
Test_Minions_StrafeUpAtAnEdge() {
    sea := {on: false, at: 0}
    m := MnStrafeFight(150, 12, (m) => m.t._viewFn := () => (sea.on := m.io.HeldMs("a") >= 800 && MnKeyDown(m.io, "a") || sea.on
        , {edge: sea.on, sig: []}))
    AssertTrue(sea.on, "the edge came")
    AssertEq(MnDowns(m.io, "a") " " MnUps(m.io, "a"), "1 1", "a let go")
    AssertEq(MnDowns(m.io, "d"), 0, "the sea on both sides: no other way")
    ; on its side only: over to the other side
    m := MnStrafeFight(150, 12, (m) => m.t._viewFn := () => {edge: MnKeyDown(m.io, "a"), edgeL: MnKeyDown(m.io, "a"), edgeR: false, sig: []})
    AssertTrue(QmObbyFirst(m.io, "up a") < QmObbyFirst(m.io, "down d"), "a up, then d")
    AssertTrue(MnDowns(m.io, "d") >= 1, "d")
}

; a fall remembered that way, checked with the key down
Test_Minions_StrafeUpAtAFall() {
    m := MnStrafeFight(150, 12, (m) => m.t._viewFn := () => (MnKeyDown(m.io, "a") && !m.t._falls.Length
        && m.t._falls.Push({x: m.t._pos.x, y: m.t._pos.y, b: m.t._bearing - MinionsTask.FullTurnMs // 4, at: m.io.t}), ""))
    AssertTrue(m.t._falls.Length, "the fall")
    iD := QmObbyFirst(m.io, "down d")
    AssertTrue(iD > 0 && QmObbyFirst(m.io, "up a") < iD, "up, then the other way")
    held := m.io.downAt[iD] - m.io.downAt[QmObbyFirst(m.io, "down a")]
    AssertTrue(held <= 2 * MinionsTask.DodgeStepMs, "at the next tick, not at the run's end: " held)
}

; the position follows the time held, the dodge stays off the trail
Test_Minions_StrafeOnThePositionNotTheTrail() {
    m := MnTask(), t := m.t, ctx := SchedCtx()
    t._Step("a", 400, ctx, false)
    m.io.t += 100
    t._Step("a", 400, ctx, false)
    AssertEq(Round(t._pos.x), -800, "left, the time held")
    AssertTrue(Abs(t._pos.y) < 5, "not forward: " t._pos.y)
    t._Step("d", 400, ctx, false)
    AssertEq(Round(t._pos.x), -400, "and back")
    t._Stop()
    AssertEq(t._trail.Length, 0, "no dodge on the trail")
}

; nothing to dodge: the stand has no key down
Test_Minions_StandWithNoDodgeReleases() {
    m := MnTask(), t := m.t, ctx := SchedCtx()
    t._Step("a", 400, ctx, false)
    t._Idle(ctx)
    AssertTrue(!MnKeyDown(m.io, "a"), "up for the wait")
}

; Deadeye roots: the strafe up before the press
Test_Minions_DeadeyeStopsTheStrafe() {
    m := MnTask()
    ctx := SchedCtx(), k := 0, at := {down: -1}
    bars := [{x: 1280, y: 300, w: 200, full: 200, fill: 1}, {x: 1100, y: 600, w: 130, full: 130, fill: 1}]
    m.t._scanFn := () => (++k >= 30 ? (ctx.Stop(), bars) : bars)
    m.t._hudFn := () => MnHud(, 80, k >= 6 ? "V" : "")
    m.t._lock := true
    MnWalkFight(m, ctx)
    i := QmObbyFirst(m.io, "down r")
    AssertTrue(i > 0, "Deadeye pressed")
    AssertTrue(QmObbyFirst(m.io, "down a") < i, "strafing before it")
    side := 0
    for j, e in m.io.log
        if (j < i)
            side += (e == "down a" || e == "down d") ? 1 : (e == "up a" || e == "up d") ? -1 : 0
    AssertEq(side, 0, "no side key down at the press")
    n := 0
    for j, e in m.io.log
        n += (j > i && j < i + 6 && (e = "down a" || e = "down d" || e = "down w")) ? 1 : 0
    AssertEq(n, 0, "no key right after it")
}

; beside it: w up at once, not on past it through the turn to it
Test_Minions_ArrivingStopsTheWalkBeforeTheTurn() {
    m := MnTask()
    ctx := SchedCtx(), n := 0
    far := [{x: 1280, y: 300, w: 60}]
    m.t._scanFn := () => (MnWalks(m.io) < 3 ? (far[1].y += 14, far)
        : ++n >= 8 ? (ctx.Stop(), []) : [{x: 2300, y: 400, w: 200}])
    m.t._lock := true
    MnWalkFight(m, ctx)
    i := QmObbyFirst(m.io, "down Right")
    AssertTrue(i > 0, "turned to it")
    AssertTrue(MnUps(m.io, "w") >= 1 && QmObbyFirst(m.io, "up w") < i, "w up first")
}

; a walk held: no aim tap would let go of it
Test_Minions_NoAimTapWhileWalking() {
    m := MnTask(), t := m.t, ctx := SchedCtx()
    t._Walk(ctx)
    f := {casts: 0, castEnd: 0, promptSaid: false}
    book := MinionSkills("Eden", "")
    AssertTrue(t._Press(ctx, f, book, "", false), "pressed")
    AssertEq(f.casts, 1, "a skill went out")
    AssertEq(MnDowns(m.io, "w") " " MnUps(m.io, "w"), "1 0", "w stayed down")
}

Test_Minions_TickLoggedOnceAHunt() {
    m := MnTask(, Map("Minions.maxSec", 5))
    m.t._scanFn := MnNearingSlow(m, 100)
    MnWalkFight(m, SchedCtx())
    AssertTrue(RegExMatch(MnLines(m, "minions: tick "), "^minions: tick \d+ ms fighting \(\d+ ticks, looks 100 ms\), \d+ ms seeking \(\d+ steps, looks \d+ ms\); per tick fighting chk \d+ cap \d+ death \d+ scan \d+ toast \d+ hud \d+ ocr \d+ rest \d+, seeking chk \d+ cap \d+ death \d+ scan \d+ toast \d+ hud \d+ ocr \d+ rest \d+$"), MnLines(m, "minions: tick "))
    AssertEq(MnCount(m, "minions: tick "), 1, "once")
    AssertTrue(InStr(MnLines(m, "minions: tick "), "tick 7"), "a walk tick is a step long, the scan in it: " MnLines(m, "minions: tick "))
}

; seeking: no skill to press, the panel not read (the death check reads the hud dep each tick)
Test_Minions_NoHudWhileSeeking() {
    m := MnTask(, Map("Minions.maxSec", 3))
    ctx := SchedCtx(), hud := 0, scans := 0
    m.t._scanFn := () => (++scans, m.io.t += 300, [])
    m.t._hudFn := () => (++hud, MnNoPanel())
    MnWalkFight(m, ctx)
    AssertTrue(scans >= 3, "ticks: " scans)
    ; once a hunt's start, once a tick for the death; none for the panel
    AssertTrue(hud <= scans + 2, "hud " hud ", scans " scans)
}

; --- the set-up's time (biomes last ~120 s) ---

; RsLockIO with a clock; enterLost: Enter presses the prompt ignores
class MnQuickIO extends RsLockIO {
    t := 0
    lock := false
    enterLost := 0
    enterAt := []
    clickAt := []
    Wait(ms, ctx := "") {
        this.t += ms
        return super.Wait(ms, ctx)
    }
    Down(k) {
        if (k = "Enter") {
            this.enterAt.Push(this.t)
            if (this.enterLost-- > 0) {
                this.log.Push("down Enter")
                return
            }
        }
        super.Down(k)
    }
    ClickHere() {
        this.clickAt.Push(this.t)
        super.ClickHere()
    }
}

; Roblox's log for a test: lines: the Poll that finds the respawn's lines (0 = never)
class MnTail {
    n := 0
    newer := false
    Seen := false
    stales := 0                   ; Stale calls
    __New(lines := 0) {
        this.lines := lines
    }
    Sync() {
    }
    Poll() {
        found := this.lines && ++this.n = this.lines
        this.Seen := this.Seen || found
        return found
    }
    Stale() {
        this.stales++
        return this.newer
    }
}

; a ctx stopped from the start
MnStopped() {
    c := SchedCtx()
    c.Stop()
    return c
}

; one hunt, a fight of two skills: a bar at hand, then the orb's toast
MnShortHunt(m, near := "") {
    from := MnSkills(m.io)
    m.t._scanFn := IsObject(near) ? near : () => [{x: 1280, y: 680, w: 200}]
    m.t._toastFn := () => (MnSkills(m.io) - from >= 2 ? "orb" : "")
    m.t.Run(SchedCtx())
}

; the waits of the plain reset stay as they were for the other tasks; the
; hunt's: Enter sooner, the clicks at the log's lines, every check still there
Test_Minions_QuickResetWaitsForTheLogNotTheClock() {
    plain := MnQuickIO()
    AssertEq(Input.ResetToSpawn(SchedCtx(), plain), true, "plain")
    AssertEq(plain.enterAt[1], 1400, "Esc + R as ever")
    io := MnQuickIO()
    r := Input.QuickReset(SchedCtx(), io, () => io.enterAt.Length && io.t - io.enterAt[1] >= 1700)
    AssertEq(r, true, "quick")
    AssertEq(io.enterAt[1], 700, "Enter 0.7 s sooner")
    AssertEq(io.clickAt[1] - io.enterAt[1], 1700 + Input.ResetQuick["afterLine"] + Input.ShiftSettleMs + Input.ResetQuick["aroundClick"], "the first click from the lines, not 2.6 s on")
    AssertTrue(plain.t - io.t >= 1500, "over 1.5 s saved: " plain.t " -> " io.t)
    AssertEq(io.Count("click@52,621") " " io.Count("click@525,158") " " io.collUp " " io.promptUp, "1 1 0 0", "opened, closed, nothing left up")
    AssertEq(Input._quick, false, "the next task's waits are the plain ones")
    AssertEq(Input._settled, "", "and no fn left")
}

; Enter too soon for the prompt: no lines come, the prompt is read, Enter
; again: no prompt left over the game
Test_Minions_QuickResetEnterLostIsPressedAgain() {
    io := MnQuickIO()
    io.enterLost := 1
    AssertEq(Input.QuickReset(SchedCtx(), io, () => false), true, "done")
    AssertEq(io.enterAt.Length, 2, "Enter twice")
    AssertTrue(io.enterAt[2] - io.enterAt[1] >= Input.ResetQuick["afterEnter"], "after the full wait")
    AssertEq(io.promptUp, false, "not left up")
    ok := MnQuickIO()
    Input.QuickReset(SchedCtx(), ok, () => false)
    AssertEq(ok.enterAt.Length, 1, "no lines but no prompt either (the log unread): once")
    AssertEq(ok.clickAt[1] - ok.enterAt[1], Input.TapHoldMs + Input.ResetQuick["afterEnter"] + Input.ShiftSettleMs + Input.ResetQuick["aroundClick"], "the full wait")
}

; R before the menu took it: the plain retry, the menu not toggled shut
Test_Minions_QuickResetRIgnoredIsRetried() {
    io := MnQuickIO(1)
    io.menuTrack := true
    AssertEq(Input.QuickReset(SchedCtx(), io, () => io.enterAt.Length > 0), true, "done")
    AssertEq(io.Count("down Esc"), 1, "one Esc: a second would shut the menu")
    AssertEq(io.Count("down r"), 2, "R again")
}

; the guard on every click holds in the quick waits (commit 9c0b2a3)
Test_Minions_QuickResetKeepsTheClickGuard() {
    io := MnQuickIO()
    io.lock := true
    AssertEq(Input.QuickReset(SchedCtx(), io, () => true), true, "done")
    AssertEq(io.pinned, 0, "no click with shift lock on")
    AssertEq(io.lock, false, "turned off first")
    AssertEq(Input.QuickAim(SchedCtx(), io), true, "the re-aim too")
    AssertEq(io.pinned, 0, "none")
    AssertEq(Input._quick, false, "over")
}

; a stop in the quick wait: stopped, the quick waits over
Test_Minions_QuickResetStopped() {
    io := MnQuickIO(, , , 4)
    AssertEq(Input.QuickReset(SchedCtx(), io, () => false), false, "stopped")
    AssertEq(Input._quick, false, "over")
}

; the closing respawn of a hunt serves the next one: no Esc, no click, the
; bearing 0, shift lock on and the camera recipe as after a respawn
Test_Minions_NextHuntStartsFromTheClosingRespawn() {
    m := MnTask(, , , MnLockIO())
    MnShortHunt(m)
    AssertEq(QmObbyDowns(m.io, "Esc"), 2, "the first hunt: its respawn, the closing one")
    m.t._bearing := 900, m.t._pos := {x: 5, y: 5}
    at := m.io.log.Length, seen := ""
    MnShortHunt(m, () => (seen := (seen = "" ? m.t._bearing : seen), [{x: 1280, y: 680, w: 200}]))
    AssertEq(QmObbyDowns(m.io, "Esc"), 3, "only the closing one")
    AssertTrue(MnLogged(m, "minions: still at spawn since the last hunt - no respawn"), "logged")
    AssertEq(seen, 0, "the first look at bearing 0")
    AssertEq(m.io.locked, 0, "no click with the lock on")
    on := 0, look := 0, down := 0, esc := 0
    for i, e in m.io.log {
        if (i <= at)
            continue
        on := (!on && e = "event {sc02A up}") ? i : on
        look := (!look && e = "look 0,80") ? i : look
        down := (!down && e = "wheel down 1") ? i : down
        esc := (!esc && e = "down Esc") ? i : esc
    }
    AssertTrue(on && on < look && look < down && down < esc, "lock, pitch, zoom, the closing respawn: " on " " look " " down " " esc)
}

; every doubt is a respawn
Test_Minions_StillAtSpawnOnlyWithNoDoubt() {
    m := MnTask()
    fresh := () => (m.t._spawnAt := m.io.t, m.t._spawnSent := Input.Sent)
    fresh()
    AssertEq(m.t._StillAtSpawn(true), true, "all clear")
    AssertEq(m.t._StillAtSpawn(true), false, "good for one hunt")
    fresh()
    AssertEq(m.t._StillAtSpawn(false), false, "the aura swapped: its clicks")
    fresh()
    Input.Key("w", 50, m.io)
    AssertEq(m.t._StillAtSpawn(true), false, "a key since: another task may have walked")
    fresh()
    Input.Click(10, 10, m.io)
    AssertEq(m.t._StillAtSpawn(true), false, "a click since")
    fresh()
    m.io.t += MinionsTask.SpawnKeepMs
    AssertEq(m.t._StillAtSpawn(true), false, "too old")
    m.t._respawnLog := MnTail(1)
    fresh()
    AssertEq(m.t._StillAtSpawn(true), false, "a respawn in the log")
    m.t._respawnLog := MnTail()
    m.t._respawnLog.newer := true
    fresh()
    AssertEq(m.t._StillAtSpawn(true), false, "a newer log: a rejoin")
}

; the first hunt: none yet; a hunt's own respawn does not serve the next
Test_Minions_OnlyTheClosingRespawnCounts() {
    m := MnTask(, , , MnLockIO())
    AssertEq(m.t._StillAtSpawn(true), false, "none yet")
    m.t._spawnAt := m.io.t, m.t._spawnSent := Input.Sent
    m.t._Hunt(MnStopped())
    AssertEq(m.t._spawnAt, 0, "gone once a fight began")
}

; what the log showed goes with the aura: a swap, and it is to show it again.
; The combat aura on already: kept (the closing respawn proved it)
Test_Minions_ASwapDoubtsTheLog() {
    m := MnTask(, , , MnLockIO())
    tail := MnTail()
    tail.Seen := true
    m.t._respawnLog := tail
    MnShortHunt(m)
    AssertEq(tail.Seen, false, "Glock to Eden")
    tail.Seen := true
    MnShortHunt(m)
    AssertEq(tail.Seen, true, "Eden on already")
}

; the hunt's own reset proves the log before the fight (Input.QuickReset polls)
Test_Minions_TheHuntsResetProvesTheLog() {
    m := MnTask(, , , MnQuickIO())
    tail := MnTail(1)
    m.t._respawnLog := tail
    AssertEq(m.t._Respawn(SchedCtx()), true, "reset")
    AssertEq(tail.Seen, true, "its lines")
}

; an auto roll mid-hunt: doubted too, and the lines of the aura put back
; prove it again. An aura that prints none: the HP route is back
Test_Minions_AutoRollDoubtsTheLog() {
    old := MinionsTask.AuraCheckMs
    MinionsTask.AuraCheckMs := 0
    try {
        AssertEq(MnAutoRollSeen(false), false, "no line from the aura put back")
        AssertEq(MnAutoRollSeen(true), true, "its own lines")
    } finally {
        MinionsTask.AuraCheckMs := old
    }
}

; a hunt with the log proved, an auto roll in it, lines: the aura put back
; prints its bind lines -> Seen after it
MnAutoRollSeen(lines) {
    near := [{x: 1280, y: 680, w: 200}]
    m := MnTask([near, near, near, []])
    tail := MnTail()
    m.t._respawnLog := tail
    n := 0
    m.t._scanFn := () => (++n = 2 ? (tail.Seen := true, tail.lines := lines ? tail.n + 1 : 0, m.s.logName := "Pumpkinity") : 0, near)
    m.t._toastFn := () => (MnLogged(m, "Pumpkinity got equipped") ? "orb" : "")
    m.t.Run(SchedCtx())
    AssertTrue(MnLogged(m, "Pumpkinity got equipped"), "the swap ran")
    return tail.Seen
}

; a menu closed over the game: its clicks, a respawn
Test_Minions_MenuClosedMeansARespawn() {
    m := MnTask()
    m.t._spawnAt := m.io.t, m.t._spawnSent := Input.Sent
    m.t._swap.DefineProp("Covered", {call: (*) => "collections"})
    m.t._swap.DefineProp("ClearView", {call: (*) => ""})
    AssertEq(m.t._ClearView(SchedCtx()), true, "closed")
    AssertEq(m.t._StillAtSpawn(true), false, "no shortcut")
}

; a death told by the log: shift lock off first, the clicks right after,
; not 1.5 s on; the camera set again with the lock on, the bearing 0
Test_Minions_AfterDeathByTheLogHasNoFixedWait() {
    io := MnLockIO()
    m := MnTask(, , , io)
    m.t._respawnLog := MnTail()
    m.t._lockTried := true, m.t._lock := true, io.lock := true, m.t._bearing := 700
    t0 := io.t, hi := Input._hiRes
    AssertEq(m.t._AfterDeath(SchedCtx(), "a respawn in the log"), true, "done")
    off := io.Index("event {sc02A up}"), click := io.Index("click"), look := io.Index("look 0,80")
    AssertTrue(off && off < click && click < look, "off, re-aim, camera: " off " " click " " look)
    AssertEq(io.locked, 0, "no click with the lock on")
    AssertEq(m.t._bearing, 0, "bearing 0")
    AssertEq(m.t._aimed, true, "aimed")
    AssertEq(io.lock, true, "shift lock on again")
    AssertEq(m.t._lock, true, "known")
    AssertTrue(MnLogged(m, "minions: fight camera set"), "the camera right")
    AssertEq(Input._hiRes, hi, "the 1 ms timer off again")
    AssertTrue(io.t - t0 < 4000, "under 4 s on the fake's waits: " io.t - t0)
}

; the death screen comes before the respawn: the clicks wait for its lines
; (L36 08:35:55: three clicks at a dead player, Collections never opened)
Test_Minions_AfterDeathScreenWaitsForTheLines() {
    io := MnLockIO()
    m := MnTask(, , , io)
    tail := MnTail(5)
    m.t._respawnLog := tail
    m.t._lockTried := true, m.t._lock := true, io.lock := true
    AssertEq(m.t._AfterDeath(SchedCtx(), MinionsTask.DeathScreenSeen), true, "done")
    AssertEq(tail.n, 5, "looked until the lines came")
    AssertEq(m.t._aimed, true, "aimed")
    AssertEq(io.locked, 0, "no click with the lock on")
}

; no lines at all: on after DeathLineMs
Test_Minions_AfterDeathScreenNoLinesGoesOn() {
    m := MnTask(, , , MnLockIO())
    m.t._respawnLog := MnTail()
    t0 := m.io.t
    AssertEq(m.t._RespawnSettle(SchedCtx(), MinionsTask.DeathScreenSeen, t0), true, "goes on")
    AssertEq(m.io.t - t0, MinionsTask.DeathLineMs + MinionsTask.DeathAfterLineMs, "looked, then the rest")
}

; no log to read: the fixed wait of old, what the lock took counted
Test_Minions_AfterDeathNoLogKeepsTheFixedWait() {
    m := MnTask()
    t0 := m.io.t
    m.io.t += 400
    AssertEq(m.t._RespawnSettle(SchedCtx(), "a respawn in the log", t0), true, "goes on")
    AssertEq(m.io.t - t0, MinionsTask.DeathSettleMs, "the whole wait")
}

; a stop in the wait for the lines: stopped, nothing clicked
Test_Minions_AfterDeathStoppedInTheWait() {
    m := MnTask(, , , MnLockIO())
    m.t._respawnLog := MnTail()
    AssertEq(m.t._AfterDeath(MnStopped(), MinionsTask.DeathScreenSeen), false, "stopped")
    AssertEq(m.io.Clicks(), 0, "no click")
}

; a stop in the camera: the 1 ms timer off all the same
Test_Minions_FightCameraStoppedLeavesTheTimerOff() {
    m := MnTask(, , , MnLockIO())
    m.t._lock := true
    hi := Input._hiRes
    AssertEq(m.t._FightCamera(MnStopped()), false, "stopped")
    AssertEq(Input._hiRes, hi, "off")
}

; a known aura's layout needs no panel read before the first look
Test_Minions_KnownAuraSkipsThePanelRead() {
    m := MnTask()
    m.t._hudFn := () => (m.logs.Push("hud read"), MnNoPanel())
    MnShortHunt(m)
    skills := 0, hud := 0
    for i, e in m.logs {
        skills := (!skills && InStr(e, "minions: skills panel")) ? i : skills
        hud := (!hud && e = "hud read") ? i : hud
    }
    AssertTrue(skills && skills < hud, "the book first: " skills " " hud)
}

; ---- a tick's speed (2026-11-06: 957 ms a fight tick) ---------------------

; Scan reads boxes round what is warm: the same bars as ScanFull on real
; frames (bars near, far, point-blank, gold signs that are none)
Test_Minions_ScanSameAsScanFull() {
    for f in [["minions_hand_eden_three.png", 460, 140], ["minions_windy_far.png", 264, 100], ["minions_forest_orb_far.png", 360, 135]
        , ["minions_pointblank_snowy_two.png", 900, 400], ["minions_snowy_fog_pair.png", 220, 160], ["minions_sand_orb.png", 260, 140]
        , ["minions_gold_title.png", 700, 300], ["minions_sign_base.png", 340, 160], ["minions_heaven_trim_a.png", 160, 120]] {
        g := MatchFileGrab(A_ScriptDir "\screens\" f[1]), a := {x1: 0, x2: f[2] - 1, y1: 0, y2: f[3] - 1}
        AssertEq(MnBarsFull(MinionsTask.Scan(g, a)), MnBarsFull(MinionsTask.ScanFull(g, a)), f[1])
    }
}

MnBarsFull(bars) {
    s := ""
    for b in bars
        s .= b.x "," b.y "," b.w "," b.h "," b.fill ";"
    return s
}

; nothing warm: no box, so no pixel of the area read but the sparse look
Test_Minions_ScanColdSceneHasNoBoxes() {
    px := 0
    grab := (x1, x2, ys, st) => MnColdRows(x1, x2, ys, st, &px)
    a := {x1: 0, x2: 799, y1: 0, y2: 399}
    AssertEq(MinionsTask.Scan(grab, a).Length, 0, "no bars")
    AssertTrue(px <= 800 * 200 // MinionsTask.GateEvery + 200, "the sparse look only: " px)
}

MnColdRows(x1, x2, ys, st, &px) {
    out := []
    for y in ys {
        row := []
        x := x1
        while (x <= x2)
            row.Push(0x304050), x += st, px++
        out.Push(row)
    }
    return out
}

; MnFrameScan as a RAINY hunt reads it
MnRainScan(name, w, h) {
    MinionsTask._GradLook(true)
    try return MnFrameScan(name, w, h)
    finally MinionsTask._GradLook(false)
}

; Rain mutes the bars under FindGrad's usual warm test: an orb and its minions
; in plain view read as none (real frames, L47 16:05:52, L45 14:18:32).
Test_Minions_RainReadsMutedBars() {
    AssertEq(MnFrameScan("minions_rain_160552.png", 360, 104).Length, 0, "usual look: none")
    bars := MnRainScan("minions_rain_160552.png", 360, 104)
    AssertEq(bars.Length, 2, "the orb's bar and a minion's")
    AssertEq(bars[1].x " " bars[1].y " " bars[1].w, "250 32 60", "the orb's bar")
    AssertEq(MnFrameScan("minions_rain_141832.png", 320, 120).Length, 0, "usual look: none")
    AssertEq(MnRainScan("minions_rain_141832.png", 320, 120).Length, 1, "the orb's bar")
}

; what the usual look reads stands in rain: the loose warm cuts a bright bar
; or joins it to its neighbour (L53 11:16:00: the w76 bar was lost; clip: two
; minions read as one)
Test_Minions_RainKeepsTheUsualRead() {
    for f in [["minions_rain_141848.png", 320, 100, 1], ["minions_rain_185257.png", 320, 100, 2]
        , ["minions_rain_bright_111600.png", 320, 108, 2], ["nodeath_voidrush_rainy_clip.jpg", 2560, 1440, 3]] {
        bars := MnFrameScan(f[1], f[2], f[3])
        AssertEq(bars.Length, f[4], f[1])
        AssertEq(MnBarsFull(MnRainScan(f[1], f[2], f[3])), MnBarsFull(bars), f[1])
    }
}

; warm boards and scenery in rain are no bars (the gold boards' lit base, a
; hunt from spawn; L47 16:01:23, L48 17:38:18, L56 12:26:51)
Test_Minions_RainReadsNoBoards() {
    for f in [["minions_rain_none_160123.png", 624, 132], ["minions_rain_none_173818.png", 848, 144]
        , ["minions_rain_none_boards.png", 864, 444], ["minions_board_base_rainy.png", 320, 60]
        , ["glow_noorb_rainy_board.png", 305, 325]]
        AssertEq(MnRainScan(f[1], f[2], f[3]).Length, 0, f[1])
}

; Scan and ScanFull read the same in rain too
Test_Minions_RainScanSameAsScanFull() {
    g := MatchFileGrab(A_ScriptDir "\screens\minions_rain_160552.png"), a := {x1: 0, x2: 359, y1: 0, y2: 103}
    MinionsTask._GradLook(true)
    try {
        full := MnBarsFull(MinionsTask.ScanFull(g, a))
        AssertEq(MnBarsFull(MinionsTask.Scan(g, a)), full, "same bars")
    } finally
        MinionsTask._GradLook(false)
}

; the rain's thresholds in RAINY alone, and only for the scan
Test_Minions_RainLookOnlyInRain() {
    for b in ["RAINY", "WINDY", "SAND STORM", ""] {
        t := MnTask().t, seen := []
        t._scanFn := "", t._biome := b
        t._grab := (x1, x2, ys, st) => MnLookRows(seen, ys)
        t._Scan()
        AssertEq(seen[1], b = "RAINY" ? MinionsTask.RainRed : 0x960000, "while scanning in " b)
        AssertEq(MinionsTask.GradRed " " MinionsTask.GradRB " " MinionsTask.GradBlue " " MinionsTask.GradBottom " " MinionsTask.GradRain
            , 0x960000 " 100 90 42 0", "after it")
    }
}

MnLookRows(seen, ys) {
    seen.Push(MinionsTask.GradRed)
    out := []
    for y in ys
        out.Push([0x304050])
    return out
}

; warm px near each other are one box, far ones two, opened for the finders
Test_Minions_HotBoxesJoinNearOnes() {
    bx := []
    MinionsTask._BoxAdd(bx, 10, 100, 200)
    MinionsTask._BoxAdd(bx, 11, 120, 210)
    MinionsTask._BoxAdd(bx, 12, 900, 950)
    AssertEq(bx.Length, 2, "one under the other joined, one far apart")
    AssertEq(bx[1].b " " bx[1].i2, "210 11", "grown")
    m := MinionsTask._BoxMerge([{x1: 0, x2: 100, i1: 1, i2: 10}, {x1: 50, x2: 200, i1: 5, i2: 20}, {x1: 500, x2: 600, i1: 1, i2: 5}])
    AssertEq(m.Length, 2, "overlapping boxes are one: no run read twice")
    AssertEq(m[1].x2 " " m[1].i2, "200 20", "their union")
}

; one copy of the screen for all readers while held, alpha off, by stride
Test_ScreenFrame_ReadsOneCopy() {
    fr := ScreenFrame()
    fr.Hold()
    at := 5 * fr._w * 4 + 10 * 4
    NumPut("UInt", 0xFF112233, fr._bits, at)
    NumPut("UInt", 0xFF445566, fr._bits, at + 8)
    rows := fr(10, 13, [5], 2)
    AssertEq(rows[1].Length, 2, "every 2nd px of 4")
    AssertEq(Format("{:06x} {:06x}", rows[1][1], rows[1][2]), "112233 445566", "the copy, no alpha")
    AssertEq(fr(10, 10, [5])[1][1], 0x112233, "held: still that copy")
    fr.Let()
    AssertTrue(!fr.Held, "let go")
}

; a tick's wait is what its looks left of FightTickMs
Test_Minions_IdleWaitsWhatTheLooksLeft() {
    m := MnTask(), t := m.t, ctx := SchedCtx()
    t._TickStart(m.io.t - 200)
    t0 := m.io.t
    t._Idle(ctx)
    AssertEq(m.io.t - t0, MinionsTask.FightTickMs - 200, "the look was in the tick")
    t._TickStart(m.io.t - 900)
    t0 := m.io.t
    t._Idle(ctx)
    AssertEq(m.io.t - t0, 0, "a slow look: no wait on top")
}

; a dodge goes on through the ticks: a tick long, the key held between them
Test_Minions_DodgeIsATickLong() {
    m := MnTask(), t := m.t, ctx := SchedCtx()
    f := {dodges: 0, dodgeMs: 0, dodgeKey: "", foes: [], stepped: false}
    t._tick := 1, t._TickStart(m.io.t - 100)
    t0 := m.io.t
    AssertTrue(t._Dodge(ctx, f), "stepped")
    AssertEq(m.io.t - t0, MinionsTask.FightTickMs - 100, "a new key: what the look left")
    k := t._held.key
    t._tick := 2, t._TickStart(m.io.t)
    t0 := m.io.t
    t._Dodge(ctx, f)
    AssertEq(t._held.key, k, "the same side")
    AssertEq(m.io.t - t0, MinionsTask.FightTickMs, "held on: a tick")
    AssertEq(MnDowns(m.io, k), 1, "one key press through both")
    AssertEq(f.dodgeMs, 2 * MinionsTask.FightTickMs - 100, "the time on that side")
}

; the Quest Board's page: one OCR per QuestEveryMs, not one a cast
Test_Minions_QuestReadByTime() {
    m := MnTask(), t := m.t, n := 0
    t._swap := {QuestUp: (*) => (n++, false)}
    t._QuestSeen(), t._QuestSeen(), t._QuestSeen()
    AssertEq(n, 1, "one read")
    m.io.t += MinionsTask.QuestEveryMs
    t._QuestSeen()
    AssertEq(n, 2, "time up: read again")
}

; L63 01:17:39: the UGC Shop over the fight is seen with the Quest page's read
Test_Minions_ShopSeenInTheFight() {
    m := MnTask(), t := m.t
    t._swap := {QuestUp: (*) => false, ShopUp: (*) => true}
    AssertTrue(t._QuestSeen(), "the shop up: the view is cleared")
}

; L64 02:24:47-02:25:37: the orb's bar went 0.90 -> 0.29 with 2 minion toasts:
; it can be hurt, so it is open (Voidrush, Deadeye), a flat misread is not
Test_Minions_OrbBarGoingDownUnlocks() {
    f := {boss: false, down: 2, foes: [], orbHurt: false, hurtFirst: "", hurtFirstAt: 0}
    AssertTrue(!MinionsTask.Unlocked(f), "2 toasts: locked")
    AssertTrue(!MinionsTask.OrbHurtStep(f, 1.00, 1000), "whole: nothing")
    AssertTrue(!MinionsTask.OrbHurtStep(f, 0.90, 2000), "first low read")
    AssertTrue(!MinionsTask.OrbHurtStep(f, 0.91, 5000), "not lower")
    AssertTrue(MinionsTask.OrbHurtStep(f, 0.79, 9000), "lower: hurt")
    AssertTrue(MinionsTask.Unlocked(f), "open")
    f.foes := [{w: 60}]
    AssertTrue(!MinionsTask.Unlocked(f), "a minion bar in view: not now")
    g := {boss: false, down: 0, foes: [], orbHurt: false, hurtFirst: "", hurtFirstAt: 0}
    for t in [1000, 4000, 13000, 17000]
        AssertTrue(!MinionsTask.OrbHurtStep(g, 0.38, t), "a flat 0.38: no")
    h := {boss: false, down: 0, foes: [], orbHurt: false, hurtFirst: "", hurtFirstAt: 0}
    MinionsTask.OrbHurtStep(h, 0.80, 1000)
    AssertTrue(!MinionsTask.OrbHurtStep(h, 0.70, 1000 + MinionsTask.HurtOpenMs + 1), "too long apart")
    AssertTrue(!h.orbHurt, "still locked")
}

; L71 02:47:05 / 03:28:44: a lone bar going down with minions seen a moment
; before is a near minion read as the orb: the orb stays Locked; a whole read
; between two low ones is no drop either (the orb has no regen)
Test_Minions_OrbHurtNotWithMinionsAbout() {
    f := {boss: false, down: 0, foes: [{w: 120}], orbHurt: false, hurtFirst: "", hurtFirstAt: 0}
    AssertTrue(!MinionsTask.OrbHurtStep(f, 0.59, 1000), "minions about: first")
    AssertTrue(!MinionsTask.OrbHurtStep(f, 0.51, 2000), "minions about: no drop")
    AssertTrue(!f.orbHurt && !MinionsTask.Unlocked(f), "locked")
    f.foes := []
    AssertTrue(!MinionsTask.OrbHurtStep(f, 0.50, 6000), "none about: a first read")
    AssertTrue(MinionsTask.OrbHurtStep(f, 0.40, 7000), "then lower: hurt")
    g := {boss: false, down: 0, foes: [], orbHurt: false, hurtFirst: "", hurtFirstAt: 0}
    MinionsTask.OrbHurtStep(g, 0.60, 1000)
    MinionsTask.OrbHurtStep(g, 1.00, 2000)
    AssertTrue(!MinionsTask.OrbHurtStep(g, 0.50, 3000), "a whole read between: from the start")
    AssertTrue(MinionsTask.OrbHurtStep(g, 0.45, 4000), "two low in a row: hurt")
}

; L72 04:32..04:55: Jock's dialog over the fight is seen with the Quest page's read
Test_Minions_JockSeenInTheFight() {
    m := MnTask(), t := m.t
    t._swap := {QuestUp: (*) => false, ShopUp: (*) => false, JockUp: (*) => true}
    AssertTrue(t._QuestSeen(), "his dialog up: the view is cleared")
}

; L72: Jock's dialog closed in the fight: shift lock off for the Leave click,
; on again after, logged
Test_Minions_JockDialogClosedShiftOff() {
    m := MnTask(), t := m.t, ev := []
    t._lockTried := true
    t.DefineProp("_ShiftOff", {call: (*) => ev.Push("off")})
    t.DefineProp("_ShiftOn", {call: (*) => (ev.Push("on"), true)})
    t._swap.DefineProp("Covered", {call: (*) => "jock dialog"})
    t._swap.DefineProp("ClearView", {call: (*) => (ev.Push("leave"), "")})
    AssertTrue(t._ClearView(SchedCtx()), "closed")
    AssertTrue(MnLogged(m, "the jock dialog screen is over the game - closing it"), "logged")
    AssertEq(ev.Length, 3, "three steps")
    AssertEq(ev[1] "," ev[2] "," ev[3], "off,leave,on", "shift lock off around the click")
}

; L79 21:14:04: Leave clicked, Jock's dialog stayed, the fight ended with
; the minions at 5-15%: the skills still go under it - fight on, no new
; try for JockRetryMs
Test_Minions_JockDialogLeftUpFightsOn() {
    m := MnTask(), t := m.t, reads := 0
    t._swap.DefineProp("Covered", {call: (*) => "jock dialog"})
    t._swap.DefineProp("ClearView", {call: (*) => "jock dialog"})
    t._swap.DefineProp("QuestUp", {call: (*) => false})
    t._swap.DefineProp("JockUp", {call: (*) => (reads++, true)})
    AssertTrue(t._ClearView(SchedCtx()), "not closed, yet clear to fight")
    AssertTrue(MnLogged(m, "Jock's dialog stays up - fighting on under it"), "logged")
    m.io.t += MinionsTask.QuestEveryMs
    AssertTrue(!t._QuestSeen(), "right after: not looked for again")
    AssertEq(reads, 0, "no read")
    m.io.t += MinionsTask.JockRetryMs
    AssertTrue(t._QuestSeen(), "JockRetryMs on: tried again")
}

; L54 12:03:51: toasts said three down with two minions up: the orb stays Locked
Test_Minions_OpenNeedsNoMinionBars() {
    AssertTrue(MinionsTask.Open({down: 3, foes: []}), "three down, no bars")
    AssertTrue(!MinionsTask.Open({down: 3, foes: [{w: 60}]}), "a minion bar: not open")
    AssertTrue(!MinionsTask.Open({down: 2, foes: []}), "two down")
}

; L57 12:44:53: stacked minion toasts read as Orb Awards, three minions alive
Test_Minions_NoOrbToastWithMinionBars() {
    bars := [{x: 1280, y: 300, w: 200}, {x: 1200, y: 500, w: 130}, {x: 1400, y: 500, w: 125}]
    m := MnTask([bars])
    m.t._toastFn := () => (MnSkills(m.io) >= 1 ? "orb" : "")
    AssertEq(m.t.Run(SchedCtx()), 0, "no kill with minions up")
    AssertTrue(!MnLogged(m, "the orb is down"), "not logged")
}

Test_Minions_OrbAloneIsAimedTight() {
    a := MinionsTask.AimAt(MinionsTask.View([{x: 1280, y: 300, w: 200}]))
    AssertEq(a.tol, MinionsTask.OrbTol, "the orb alone: tight")
    a := MinionsTask.AimAt(MinionsTask.View([{x: 1280, y: 300, w: 200}, {x: 1000, y: 500, w: 130}]))
    AssertEq(a.tol, MinionsTask.LockTol, "a minion: looser")
}

; L70: 5 deaths in 4 hunts, the HP ~27-39% after each respawn; L66: deaths
; ~25 s apart, 5-15 s into the fight again. At spawn the HP is waited for:
; 30% up 1.5% a second, a 4 s walk back regains 6%: on at 54%
Test_Minions_DeathWaitsAtSpawnForTheHp() {
    m := MnTask()
    t0 := m.io.t
    m.t._hudFn := () => (h := MnNoPanel(), h.playerHp := Round(0.3 + (m.io.t - t0) * MinionsTask.RegenPerMs, 2), h)
    f := {casts: 0, orbFill: "", orbAt: 0, down: 0, boss: false, b0: "RAINY"}
    AssertEq(m.t._Regen(SchedCtx(), f, 4000), true, "done")
    AssertTrue(MnLogged(m, "minions: hp 30% at spawn - waiting for 54% before going back"), "the wait logged")
    AssertTrue(MnLogged(m, "minions: going back at hp 54% after "), "on at 54%")
    w := m.io.t - t0
    AssertTrue(w >= 16000 && w < 16000 + 2 * MinionsTask.RegenLookMs, "~16 s: " w)
}

; the HP never comes up: RegenMaxMs at most (no walk known: all of ReturnHp);
; the biome over: no more wait, the fight loop ends the hunt
Test_Minions_HpWaitAtSpawnEnds() {
    m := MnTask()
    t0 := m.io.t
    m.t._hudFn := () => (h := MnNoPanel(), h.playerHp := 0.3, h)
    f := {casts: 0, orbFill: "", orbAt: 0, down: 0, boss: false, b0: "RAINY"}
    AssertEq(m.t._Regen(SchedCtx(), f, ""), true, "done")
    w := m.io.t - t0
    AssertTrue(w >= MinionsTask.RegenMaxMs && w < MinionsTask.RegenMaxMs + 2 * MinionsTask.RegenLookMs, "capped: " w)
    AssertTrue(MnLogged(m, "waiting for 60% before going back"), "all of ReturnHp")
    AssertTrue(MnLogged(m, "minions: going back at hp 30% after "), "on all the same")
    m := MnTask()
    m.t._hudFn := () => (h := MnNoPanel(), h.playerHp := 0.3, h)
    MnEndsBiome(m, 3000)
    t0 := m.io.t
    AssertEq(m.t._Regen(SchedCtx(), f, ""), true, "done")
    w := m.io.t - t0
    AssertTrue(w >= 3000 && w < 3000 + 2 * MinionsTask.RegenLookMs, "the biome's end: " w)
}

; no wait: full HP (no bar), the HP enough (less the walk's regen), the fight
; beside spawn (its minions reach it), the orb nearly dead
Test_Minions_NoHpWaitWhenItCannotHelp() {
    m := MnTask()
    hp := {v: -1}
    m.t._hudFn := () => (h := MnNoPanel(), h.playerHp := hp.v, h)
    f := {casts: 3, orbFill: "", orbAt: 0, down: 0, boss: false, b0: "RAINY"}
    for c in [[-1, 8000, "no bar: full"], [0.7, "", "enough"], [0.5, 8000, "0.6 less 8 s of regen"]
        , [0.3, MinionsTask.RegenFarMs, "the fight beside spawn"]] {
        hp.v := c[1], t0 := m.io.t
        AssertEq(m.t._Regen(SchedCtx(), f, c[2]), true, c[3])
        AssertEq(m.io.t - t0, 0, c[3] ": no wait")
    }
    hp.v := 0.3, f.orbFill := 0.05, f.orbAt := Max(1, m.io.t), f.down := MinionsTask.OpenDown, t0 := m.io.t
    AssertEq(m.t._Regen(SchedCtx(), f, 8000), true, "the orb nearly dead")
    AssertEq(m.io.t - t0, 0, "the orb nearly dead: no wait")
    AssertTrue(!MnLogged(m, "at spawn - waiting"), "never logged")
}

; a death in a hunt: the HP 30% at spawn, the trail back 3500 ms (5% of regen):
; stood till 55%, then the same walks back
Test_Minions_DeathRegensBeforeTheTrail() {
    m := MnTask(, , , MnHeldIO())
    st := {dead: false, at: 0, t: 0}
    m.t._scanFn := MnNearing(m, () => MnReplayed(m, st))
    m.t._deathFn := () => (!st.dead && MnHeldWalks(m.io) >= 6) ? (st.at := m.io.walks + 1, st.t := m.io.t, st.dead := true) : false
    m.t._hudFn := () => (h := MnNoPanel(), h.playerHp := st.dead ? Round(0.3 + (m.io.t - st.t) * MinionsTask.RegenPerMs, 2) : -1, h)
    m.t.Run(SchedCtx())
    AssertTrue(MnLogged(m, "replaying the trail, 6 steps, 3500 ms"), "the trail")
    AssertTrue(MnLogged(m, "at spawn - waiting for 55% before going back"), "the wait")
    AssertTrue(MnLogged(m, "minions: going back at hp 55% after "), "on at 55%")
    AssertEq(st.walks, 5, "the same walks, no more")
    AssertTrue(InStr(MnStatsOf(m), " deaths=1"), "one death, no HP-told one: " MnStatsOf(m))
}

; ---- review 0809 ------------------------------------------------------------

; #1: two minions behind (y 790-820), one ahead, HP 60% -> 38%: no back-off,
; s walks into the two behind
Test_Minions_NoBackOffIntoMinionsBehind() {
    bars := [{x: 1280, y: 400, w: 200}, {x: 1300, y: 480, w: 125}, {x: 1100, y: 790, w: 130}, {x: 1450, y: 820, w: 135}]
    m := MnHitFight((d) => d < 2000 ? 0.6 : 0.38, bars)
    AssertEq(MnLogCount(m, "backing out of reach"), 0, "minions behind: no back-off")
}

; #2: minions, then one near minion's lone bar (over OrbLonePx: read as the
; orb) going down under the casts past DodgeHoldMs: the orb stays Locked
Test_Minions_LoneNearMinionAfterMinionsIsNoHurtOrb() {
    m := MnTask(, Map("Minions.maxSec", 30), , MnTurnIO())
    m.t._swap.wear := "Eden"
    two := [{x: 1280, y: 300, w: 160}, {x: 1300, y: 520, w: 125}]
    c := {t0: 0}, ctx := SchedCtx()
    lone(d) {
        fill := Max(0.1, Round(0.8 - d / 10000, 2))
        return [{x: 1300, y: 520, w: Round(150 * fill), full: 150, fill: fill}]
    }
    m.t._scanFn := () => (c.t0 && m.io.t - c.t0 >= 1500) ? lone(m.io.t - c.t0) : two
    m.t._toastFn := () => (c.t0 := c.t0 ? c.t0 : m.io.t, m.io.t - c.t0 >= 10000 ? ctx.Stop() : 0, "")
    m.t._Fight(ctx)
    AssertTrue(!MnLogged(m, "it can be hurt: open"), "no hurt-open from the near minion")
}

; #3: in reach before ahead, never one above the player
Test_Minions_AimInReachFirstNeverAbove() {
    orb := {x: 1280, y: 100, w: 170, full: 170, fill: 1}
    behind := {x: 1000, y: 800, w: 150}, far := {x: 1400, y: 480, w: 40}
    AssertEq(MinionsTask.AimAt(MinionsTask.View([orb, far, behind])).x, 1000, "the one in reach behind, not the far one ahead")
    level := {x: 1000, y: 600, w: 130}, roof := {x: 1400, y: 420, w: 72, full: 120, fill: 0.6}
    AssertEq(MinionsTask.AimAt(MinionsTask.View([orb, roof, level])).x, 1000, "the level one, not the hurt one on the roof")
}

; #4: the last minion gone, its hit still in the window: no back-off from the
; Locked orb alone
Test_Minions_NoBackOffFromTheLockedOrbAlone() {
    m := MnTask(, Map("Minions.maxSec", 30), , MnTurnIO())
    m.t._swap.wear := "Eden"
    two := [{x: 1280, y: 400, w: 200}, {x: 1200, y: 500, w: 125}], orb := [{x: 1280, y: 400, w: 200}]
    c := {t0: 0}, ctx := SchedCtx()
    m.t._scanFn := () => (c.t0 && m.io.t - c.t0 >= 1500) ? orb : two
    m.t._hudFn := () => (h := MnNoPanel(), h.playerHp := (c.t0 && m.io.t - c.t0 >= 2000) ? 0.6 : 0.9, h)
    m.t._toastFn := () => (c.t0 := c.t0 ? c.t0 : m.io.t, m.io.t - c.t0 >= 8000 ? ctx.Stop() : 0, "")
    m.t._Fight(ctx)
    AssertEq(MnLogCount(m, "backing out of reach"), 0, "the orb alone: no back-off")
}

; #5: melee hits ~-10% every 1.2 s at 45% and under: back-offs no closer than
; BackOffMs + BackHoldMs, not one per BackOffMs
Test_Minions_BackOffsWaitForTheHold() {
    m := MnHitFight((d) => d < 5000 ? Round(0.45 - 0.1 * (d // 1200), 2) : 0.05)
    n := MnLogCount(m, "backing out of reach")
    AssertTrue(n >= 1 && n <= 12000 // (MinionsTask.BackOffMs + MinionsTask.BackHoldMs), "spaced by the hold: " n)
}

; #6: walked off the island while seeking, back at 30%: no fight to go back
; to, no wait for the HP
Test_Minions_NoHpWaitAfterAFallWithNoWayBack() {
    m := MnTask()
    glow := [{x: 1280 + MinionsTask.GlowAim(1), y: 700, r: 20}]
    st := {dead: 0}
    m.t._beaconFn := () => glow
    m.t._deathFn := () => (st.dead = 0 && MnWalks(m.io) >= 10) ? (st.dead := 1) : false
    m.t._hudFn := () => (h := MnNoPanel(), h.playerHp := st.dead ? 0.3 : -1, h)
    m.t.Run(SchedCtx())
    AssertTrue(MnLogged(m, "with no bar in sight - fell off the island?"), "the fall")
    AssertTrue(!MnLogged(m, "at spawn - waiting"), "no wait")
}

; #7: full HP (no bar, two reads) -> 55% in one combo counts
Test_Minions_HitHardFromFullHp() {
    L(a*) {
        log := []
        for i, hp in a
            log.Push({at: i * 500, hp: hp})
        return log
    }
    h := MinionsTask.HitHard(L(-1, -1, 0.55, 0.5), 2000)
    AssertTrue(IsObject(h) && h.top = 1.0 && h.hp = 0.5, "from full")
    AssertEq(MinionsTask.HitHard(L(0.9, -1, 0.85), 1500), "", "a lone -1: no read")
}

; #8: at a wall, the Locked orb alone in reach above it: no stand, no cast
Test_Minions_NoStandBelowALockedOrbAlone() {
    MinionsTask.WallSides := Map()
    m := MnTask()
    m.t.CanRun(m.state)
    m.t._scanFn := () => MnTurning(m, [{x: 1280, y: 520, w: 150}])
    m.t.Run(SchedCtx())
    AssertEq(MnBelowLogs(m), 0, "Locked: no stand from below")
    AssertEq(MnSkills(m.io), 0, "no cast at it")
}

; #9: the orb hurt (0.5 -> 0.3: Unlocked), last read on a rooftop (Above),
; the bar lost: no blind OrbNearlyDead stand under it
Test_Minions_NoBlindStandUnderARooftopOrb() {
    m := MnTask(, Map("Minions.maxSec", 30), , MnTurnIO())
    m.t._swap.wear := "Eden"
    level :=[{x: 1280, y: 520, w: 100, full: 200, fill: 0.5}], roof := [{x: 1280, y: 250, w: 45, full: 150, fill: 0.3}]
    st := {n: 0, k: ""}, ctx := SchedCtx()
    m.t._scanFn := () => (++st.n <= 6 ? level : st.n <= 9 ? roof : (st.k := st.k = "" ? MnSkills(m.io) : st.k, []))
    m.t._toastFn := () => (st.n >= 40 ? ctx.Stop() : 0, "")
    m.t._Fight(ctx)
    AssertTrue(st.k != "" && st.k > 0, "cast at it level: " st.k)
    AssertEq(MnSkills(m.io) - st.k, 0, "no blind casts under the roof")
}


; low: a death mid back-off ends it: a quick respawn walks no s from the
; old back-off
Test_Minions_DeathEndsTheBackOff() {
    m := MnTask(, Map("Minions.maxSec", 30), , MnTurnIO())
    near := [{x: 1280, y: 400, w: 200}, {x: 1200, y: 500, w: 125}]
    m.t._swap.wear := "Eden"
    m.t._scanFn := () => near
    st := {dead: 0, at: 0, t0: 0}, ctx := SchedCtx()
    m.t._deathFn := () => (!st.dead && MnLogged(m, "backing out of reach")) ? (st.dead := 1, st.at := m.io.log.Length) : false
    m.t.DefineProp("_AfterDeath", {Call: (*) => true})     ; a quick respawn: the old back-off's times not yet past
    m.t._hudFn := () => (h := MnNoPanel(), h.playerHp := (!st.dead && st.t0 && m.io.t - st.t0 >= 2000) ? 0.6 : 0.9, h)
    m.t._toastFn := () => (st.t0 := st.t0 ? st.t0 : m.io.t, m.io.t - st.t0 >= 8000 ? ctx.Stop() : 0, "")
    m.t._Fight(ctx)
    AssertTrue(st.dead, "died backing off")
    n := 0
    for i, e in m.io.log
        n += (i > st.at && e = "down s") ? 1 : 0
    AssertEq(n, 0, "no s after the respawn")
}
