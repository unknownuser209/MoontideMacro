#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\..\Scheduler.ahk
#Include %A_LineFile%\..\..\Input.ahk
#Include %A_LineFile%\..\..\Pixel.ahk
#Include %A_LineFile%\..\..\Roblox.ahk
; ---------------------------------------------------------------------------
; FishLogic: shared pieces for lib\tasks\Fishing.ahk and Sell.ahk.
;
;   - Data check: FishLogic.Missing(coords, routes) lists every key the tasks
;     read from data\coords.json / data\routes.json that is absent or the wrong
;     shape (paths like "coords.fishing.rod"). Tasks refuse to start on any.
;   - Pure minigame decision: FishLogic.ShouldClick(rows, stride, bar, tol,
;     advanced, thresholdPx, extendTol := 10). `rows` = Array of Arrays of
;     sampled colors (one Array per sampled y, samples `stride` px apart).
;       normal:   click when the bar color is in NO row (bar left the zone).
;       advanced: use rows[1] only; click when the bar is missing or its first
;                 contiguous run is narrower than thresholdPx.
;     No screen access: tests inject the samples.
;   - StripGrab.Rows: one BitBlt for the whole strip (the minigame needs
;     hundreds of samples per pass; PixelGetColor is ~5 ms per pixel).
;     Single points (bite pixel, shop-loaded) and the small sell-menu grids
;     use Pixel.Is / Pixel.Get so Pixel._getter fakes work.
;   - Deps: tasks take an optional deps object {io, roblox, now, wheel, grab,
;     log} so tests never touch the game. Defaults are the real ones.
;
; SETTINGS (settings.ini [General]; defaults live in Config.IniDefaults and are
; read ONLY through FishLogic.Settings / FishLogic.SellEvery)
;   sellEvery            15   fishing catches between sells (clamped to >= 1;
;                             not a whole number -> 15)
;   vip                  1    1 = the VIP sell walk, 0 = the slower non-VIP one
;   sellAll              1    1 = Sell All button (one round), 0 = sell selected
;   advancedFishing      0    1 = bar-width minigame detection (legacy only)
;   legacyReel           0    1 = FishSol's "click when the bar colour is
;                             gone" minigame; 0 = arrow controller (ReelScan)
;   advancedThreshold    20   px; click when the bar is narrower
;   fishingFailsafeSec   31   re-cast clicks after this long without a bite
;   pathingFailsafeSec   61   give up, reset and re-path (forces a sell run)
;   repathOnStart        1    App.Start sets state.needRepath so the first task
;                             is Sell (reset, walk to the fisher, sell, walk back)
;   (a key missing from an older settings.ini falls back to the same values;
;   the failsafe seconds fall back to data\coords.json.)
; ---------------------------------------------------------------------------

class StripGrab {
    ; One BitBlt of the bounding box of the rows `ys` over x1..x2, then the
    ; requested rows are read from the buffer. PixelGetColor per pixel costs
    ; milliseconds each (measured ~5.6 ms), a strip scan has to be one copy.
    ; -> Array (one entry per y in `ys`) of Arrays of 0xRRGGBB, x1, x1+stride...
    ; x1, x2, ys, stride are DESIGN px (2560x1440): off that size every
    ; sample is read at its Screen-mapped pixel (nearest), so callers keep
    ; their design geometry, counts and strides. At 2560x1440: unchanged.
    static Rows(x1, x2, ys, stride := 1) {
        if Screen.IsIdentity()
            return StripGrab._Blit(x1, x2, ys, stride)
        m := StripGrab.Map(x1, x2, ys, stride)
        return StripGrab._Blit(m.xs[1], m.xs[m.xs.Length], m.ys, 1, m.xs)
    }

    ; Design samples -> screen px: {xs: one per column, ys: one per row}.
    static Map(x1, x2, ys, stride := 1) {
        sx := [], sy := []
        x := x1
        while (x <= x2) {
            sx.Push(Screen.X(x))
            x += stride
        }
        for y in ys
            sy.Push(Screen.Y(y))
        return {xs: sx, ys: sy}
    }

    ; Screen px. cols (optional): the absolute screen xs to read in each row
    ; instead of x1, x1+stride...
    static _Blit(x1, x2, ys, stride := 1, cols := "") {
        y1 := ys[1], y2 := ys[1]
        for y in ys {
            y1 := Min(y1, y)
            y2 := Max(y2, y)
        }
        w := x2 - x1 + 1
        h := y2 - y1 + 1
        hdc := DllCall("GetDC", "Ptr", 0, "Ptr")
        if !hdc
            throw OSError("StripGrab: GetDC failed")
        mdc := 0, hbm := 0, old := 0
        try {
            mdc := DllCall("CreateCompatibleDC", "Ptr", hdc, "Ptr")
            bi := Buffer(40, 0)
            NumPut("UInt", 40, bi, 0)
            NumPut("Int", w, bi, 4)
            NumPut("Int", -h, bi, 8)            ; negative = top-down rows
            NumPut("UShort", 1, bi, 12)
            NumPut("UShort", 32, bi, 14)
            pBits := 0
            hbm := DllCall("CreateDIBSection", "Ptr", hdc, "Ptr", bi, "UInt", 0, "Ptr*", &pBits, "Ptr", 0, "UInt", 0, "Ptr")
            if (!mdc || !hbm || !pBits)
                throw OSError("StripGrab: could not create the capture buffer")
            old := DllCall("SelectObject", "Ptr", mdc, "Ptr", hbm, "Ptr")
            if !DllCall("BitBlt", "Ptr", mdc, "Int", 0, "Int", 0, "Int", w, "Int", h
                , "Ptr", hdc, "Int", x1, "Int", y1, "UInt", 0x00CC0020)
                throw OSError("StripGrab: BitBlt failed")
            out := []
            for y in ys {
                row := []
                off := (y - y1) * w * 4
                if IsObject(cols) {
                    for cx in cols
                        row.Push(NumGet(pBits, off + (cx - x1) * 4, "UInt") & 0xFFFFFF)
                } else {
                    x := 0
                    while (x < w) {
                        row.Push(NumGet(pBits, off + x * 4, "UInt") & 0xFFFFFF)
                        x += stride
                    }
                }
                out.Push(row)
            }
            return out
        } finally {
            if (mdc && old)
                DllCall("SelectObject", "Ptr", mdc, "Ptr", old)
            if hbm
                DllCall("DeleteObject", "Ptr", hbm)
            if mdc
                DllCall("DeleteDC", "Ptr", mdc)
            DllCall("ReleaseDC", "Ptr", 0, "Ptr", hdc)
        }
    }
}

; One copy of the screen, read as often as wanted. A BitBlt of the desktop
; costs ~16 ms whatever its size (2 x 2 px as much as 2560 x 1440, measured
; live 2026-11-06: it waits for the compositor), so a tick of many readers
; takes one (Hold) and they all read it; Let ends that. Not held, each Call
; copies the screen anew. Call as StripGrab.Rows.
class ScreenFrame {
    _w := 0, _h := 0, _bits := 0, _mdc := 0, _hbm := 0, _old := 0
    Held := false

    __Delete() => this._Free()

    Hold() {
        this._Take()
        this.Held := true
    }

    Let() => this.Held := false

    Call(x1, x2, ys, stride := 1) {
        if !this.Held
            this._Take()
        if !Screen.IsIdentity()
            return this._Mapped(x1, x2, ys, stride)
        for y in ys
            if (y < 0 || y >= this._h || x1 < 0 || x2 >= this._w)
                return StripGrab.Rows(x1, x2, ys, stride)
        out := [], p := this._bits, line := this._w * 4, step := stride * 4
        n := (x2 - x1) // stride + 1
        for y in ys {
            row := []
            row.Capacity := n
            off := y * line + x1 * 4
            Loop n {
                row.Push(NumGet(p, off, "UInt") & 0xFFFFFF)
                off += step
            }
            out.Push(row)
        }
        return out
    }

    ; Design samples read at their Screen-mapped pixels of the held copy
    ; (the copy is the primary monitor; a client off it -> StripGrab.Rows).
    _Mapped(x1, x2, ys, stride) {
        m := StripGrab.Map(x1, x2, ys, stride)
        if (m.xs[1] < 0 || m.xs[m.xs.Length] >= this._w)
            return StripGrab.Rows(x1, x2, ys, stride)
        for sy in m.ys
            if (sy < 0 || sy >= this._h)
                return StripGrab.Rows(x1, x2, ys, stride)
        out := [], p := this._bits, line := this._w * 4
        for sy in m.ys {
            row := []
            row.Capacity := m.xs.Length
            base := sy * line
            for sx in m.xs
                row.Push(NumGet(p, base + sx * 4, "UInt") & 0xFFFFFF)
            out.Push(row)
        }
        return out
    }

    _Take() {
        w := DllCall("GetSystemMetrics", "Int", 0, "Int"), h := DllCall("GetSystemMetrics", "Int", 1, "Int")
        hdc := DllCall("GetDC", "Ptr", 0, "Ptr")
        if !hdc
            throw OSError("ScreenFrame: GetDC failed")
        try {
            if (w != this._w || h != this._h || !this._bits)
                this._Alloc(hdc, w, h)
            if !DllCall("BitBlt", "Ptr", this._mdc, "Int", 0, "Int", 0, "Int", w, "Int", h
                , "Ptr", hdc, "Int", 0, "Int", 0, "UInt", 0x00CC0020)
                throw OSError("ScreenFrame: BitBlt failed")
        } finally
            DllCall("ReleaseDC", "Ptr", 0, "Ptr", hdc)
    }

    _Alloc(hdc, w, h) {
        this._Free()
        this._mdc := DllCall("CreateCompatibleDC", "Ptr", hdc, "Ptr")
        bi := Buffer(40, 0)
        NumPut("UInt", 40, bi, 0)
        NumPut("Int", w, bi, 4)
        NumPut("Int", -h, bi, 8)                ; negative = top-down rows
        NumPut("UShort", 1, bi, 12)
        NumPut("UShort", 32, bi, 14)
        pBits := 0
        this._hbm := DllCall("CreateDIBSection", "Ptr", hdc, "Ptr", bi, "UInt", 0, "Ptr*", &pBits, "Ptr", 0, "UInt", 0, "Ptr")
        if (!this._mdc || !this._hbm || !pBits) {
            this._Free()
            throw OSError("ScreenFrame: could not create the capture buffer")
        }
        this._old := DllCall("SelectObject", "Ptr", this._mdc, "Ptr", this._hbm, "Ptr")
        this._bits := pBits, this._w := w, this._h := h
    }

    _Free() {
        if (this._mdc && this._old)
            DllCall("SelectObject", "Ptr", this._mdc, "Ptr", this._old)
        if this._hbm
            DllCall("DeleteObject", "Ptr", this._hbm)
        if this._mdc
            DllCall("DeleteDC", "Ptr", this._mdc)
        this._mdc := 0, this._hbm := 0, this._old := 0, this._bits := 0, this._w := 0, this._h := 0
    }
}

class FishLogic {
    ; Dotted paths read by the tasks. P = [x, y] point, R = [x1, y1, x2, y2].
    static CoordsScalar := [
        "fishing.rodPreMs", "fishing.rodSettleMs", "fishing.bite.color", "fishing.bite.tol",
        "fishing.bite.pollMs", "fishing.parkSettleMs",
        "fishing.strip.x1", "fishing.strip.x2", "fishing.strip.stride", "fishing.strip.tol",
        "fishing.advanced.y", "fishing.advanced.x1", "fishing.advanced.x2", "fishing.advanced.stride",
        "fishing.advanced.tol", "fishing.advanced.extendTol", "fishing.advanced.thresholdPx",
        "fishing.advanced.afterClickMs",
        "fishing.minigameCapMs", "fishing.minigamePollMs", "fishing.afterMinigameMs",
        "fishing.closePreMs", "fishing.afterCloseMs",
        "fishing.failsafe.fishingSec", "fishing.failsafe.pathingSec", "fishing.failsafe.gapMs",
        "sell.dailyReward.stride", "sell.dailyReward.color", "sell.dailyReward.tol",
        "sell.dailyReward.maxTries", "sell.dailyReward.gapMs",
        "sell.camera.wheelUp", "sell.camera.wheelDown", "sell.camera.wheelGapMs",
        "sell.camera.pauseMs", "sell.camera.afterMs",
        "sell.dialog.aClicks", "sell.dialog.aGapMs", "sell.dialog.aAfterMs",
        "sell.dialog.bPreMs", "sell.dialog.bAfterMs",
        "sell.loop.maxRounds", "sell.loop.startDelayMs", "sell.loop.itemPreMs", "sell.loop.itemPostMs",
        "sell.loop.optionPreMs", "sell.loop.optionPostMs",
        "sell.loop.loaded.color", "sell.loop.loaded.tol", "sell.loop.loaded.timeoutMs",
        "sell.loop.loaded.pollMs", "sell.loop.loaded.closePreMs",
        "sell.loop.afterLoadMs", "sell.loop.confirmPreMs", "sell.loop.confirmPostMs",
        "sell.loop.more.stride", "sell.loop.more.color", "sell.loop.more.tol",
        "sell.closePreMs", "sell.closePostMs",
        "fishing.reel.x1", "fishing.reel.x2", "fishing.reel.stride", "fishing.reel.pollMs",
        "fishing.reel.leadMs", "fishing.reel.aim", "fishing.reel.clickGapMs",
        "fishing.reel.arrowY", "fishing.reel.barY", "fishing.fishButton.waitMs",
        "fishing.fishButton.pollMs", "fishing.fishButton.settleMs", "fishing.panelTitle.word",
        "fishing.reel.endMs", "fishing.result.waitMs", "fishing.result.pollMs"
    ]
    static CoordsPoint := [
        "fishing.rod", "fishing.bite.pixel", "fishing.parkMouse", "fishing.barSample", "fishing.close",
        "sell.dailyReward.claim", "sell.dailyReward.close",
        "sell.dialog.a", "sell.dialog.b",
        "sell.loop.item", "sell.loop.sellAll", "sell.loop.sellSelected",
        "sell.loop.loaded.pixel", "sell.loop.loaded.closeClick", "sell.loop.confirm",
        "sell.close"
    ]
    static CoordsRect := ["sell.dailyReward.rect", "sell.loop.more.rect", "fishing.fishButton.rect", "fishing.panelTitle.rect", "fishing.result.rect"]
    static CoordsList := ["fishing.result.failWords", "fishing.reel.borderYs", "fishing.strip.rows", "fishing.failsafe.clicks", "sell.dailyReward.rows", "sell.loop.more.rows"]
    static RoutePaths := ["vip.toShop", "vip.back", "nonvip.toShop", "nonvip.back"]

    ; -> Array of missing/malformed key paths ("coords.x.y" / "routes.x.y").
    static Missing(coords, routes) {
        out := []
        for p in FishLogic.CoordsScalar {
            v := FishLogic._Dig(coords, p)
            if !(v is Integer || v is Float || (v is String && v != ""))
                out.Push("coords." p)
        }
        for p in FishLogic.CoordsPoint
            if !FishLogic._IsNums(FishLogic._Dig(coords, p), 2)
                out.Push("coords." p)
        for p in FishLogic.CoordsRect
            if !FishLogic._IsNums(FishLogic._Dig(coords, p), 4)
                out.Push("coords." p)
        for p in FishLogic.CoordsList {
            v := FishLogic._Dig(coords, p)
            if !(v is Array) || v.Length = 0
                out.Push("coords." p)
        }
        for p in FishLogic.RoutePaths {
            v := FishLogic._Dig(routes, p)
            if !(v is Array) || v.Length = 0
                out.Push("routes." p)
        }
        return out
    }

    static _Dig(root, path) {
        v := root
        for part in StrSplit(path, ".") {
            if !(v is Map) || !v.Has(part)
                return ""
            v := v[part]
        }
        return v
    }

    static _IsNums(v, n) {
        if !(v is Array) || v.Length != n
            return false
        for item in v
            if !(item is Integer)
                return false
        return true
    }

    ; ---- pure decision ------------------------------------------------------

    ; x positions x1, x1+stride, ... <= x2.
    static Xs(x1, x2, stride) {
        out := []
        x := x1
        while (x <= x2) {
            out.Push(x)
            x += stride
        }
        return out
    }

    static RowHasColor(colors, bar, tol) {
        for c in colors
            if Pixel.Match(c, bar, tol)
                return true
        return false
    }

    ; Width in px of the first run of bar-colored samples: first sample within
    ; `tol`, extended right while within `extendTol`. -1 when no sample matches.
    ; Resolution is `stride` px.
    static BarWidth(colors, stride, bar, tol, extendTol) {
        i := 0
        for idx, c in colors {
            if Pixel.Match(c, bar, tol) {
                i := idx
                break
            }
        }
        if !i
            return -1
        j := i
        while (j < colors.Length && Pixel.Match(colors[j + 1], bar, extendTol))
            j++
        return (j - i) * stride
    }

    static ShouldClick(rows, stride, bar, tol, advanced, thresholdPx, extendTol := 10) {
        if advanced {
            if (rows.Length = 0)
                return true
            w := FishLogic.BarWidth(rows[1], stride, bar, tol, extendTol)
            return w < 0 || w < thresholdPx
        }
        for row in rows
            if FishLogic.RowHasColor(row, bar, tol)
                return false
        return true
    }

    ; ---- screen sampling (Pixel.Is) ------------------------------------------

    ; True when any grid sample (xs x rows) is within tol of color.
    static GridHas(xs, rows, color, tol) {
        for y in rows
            for x in xs
                if Pixel.Is(x, y, color, tol)
                    return true
        return false
    }

    ; Camera zoom (FishSol wheel sequence): wheel up, pause, wheel down, settle.
    ; `cam` = coords sell.camera {wheelUp, wheelDown, wheelGapMs, pauseMs,
    ; afterMs}. Wheel notches go out in chunks of 10 so ctx.ShouldStop() is
    ; honoured. -> false when stopped. Shared by Sell and Craft.
    ; It runs on a CleanupCtx: a preempt between the wheel up (all the way
    ; in = first person) and the wheel down left the camera in first person,
    ; where Roblox pins the cursor like shift lock and every task after it
    ; was skipped (live 2026-11-10 04:09, sell preempted by the obby). A
    ; halt (F3, pause) still stops at once.
    static Zoom(io, ctx, cam) {
        ctx := CleanupCtx(ctx)
        if !FishLogic._Wheel(io, ctx, "up", cam["wheelUp"], cam["wheelGapMs"])
            return false
        if !io.Wait(cam["pauseMs"], ctx)
            return false
        if !FishLogic._Wheel(io, ctx, "down", cam["wheelDown"], cam["wheelGapMs"])
            return false
        return io.Wait(cam["afterMs"], ctx)
    }

    static _Wheel(io, ctx, dir, total, gapMs) {
        left := total
        while (left > 0) {
            if ctx.ShouldStop()
                return false
            n := Min(10, left)
            io.Wheel(dir, n, gapMs)
            left -= n
        }
        return true
    }

    ; ---- input helpers ---------------------------------------------------------

    ; Move, wait pre, click, wait post. -> false when stopped.
    static ClickAt(io, ctx, pt, preMs, postMs) {
        if (IsObject(ctx) && ctx.ShouldStop())
            return false
        io.MoveTo(pt[1], pt[2])
        if !io.Wait(preMs, ctx)
            return false
        io.ClickHere()
        return io.Wait(postMs, ctx)
    }

    ; Fills any missing deps member with the real implementation.
    static Deps(d) {
        if !IsObject(d)
            d := Object()
        defaults := Map(
            "io", Input._io,
            "roblox", Roblox,
            "now", () => A_TickCount,
            "grab", (x1, x2, ys, stride) => StripGrab.Rows(x1, x2, ys, stride),
            "log", (msg) => 0
        )
        for name, val in defaults
            if !d.HasOwnProp(name)
                d.DefineProp(name, {value: val})
        return d
    }

    ; >= 1 always: 0 or a negative value would make a sell due before every
    ; catch (sell/fish loop without fishing).
    static SellEvery(cfg) {
        v := cfg.Get("General.sellEvery", 15)
        if !IsInteger(v)
            return 15
        return Max(1, Integer(v))
    }

    ; Sell (= re-path) due: enough catches, or a re-path was requested
    ; (state.needRepath: App.Start, fishing failsafe / false bite).
    ; A trip to the fisher is for selling fish or buying craft potions there:
    ; with fishing and crafting off it only walked there and idled
    ; (hunting only, 2026-10-31).
    static TripWanted(cfg) => (cfg.Get("General.fishing", 1) || cfg.Get("Craft.enabled", 1)) ? true : false

    static SellDue(state, cfg) {
        if !FishLogic.TripWanted(cfg)
            return false
        if (state.HasProp("needRepath") && state.needRepath)
            return true
        return state.fishLoops >= FishLogic.SellEvery(cfg)
    }

    ; The sampled bar colour must show up in the strip within this long after
    ; the minigame starts, else it was not a real bite (no clicks are sent).
    static BarSeenMs := 1000

    ; Arrow reel: the reel opens with ~1.5 s of "Ready!" where the click bar
    ; covers the fish (no purple yet), so the cyan click bar alone also
    ; counts as "reel is up", and it gets longer to show.
    static ReelSeenMs := 2500
    ; Window for the arrow's speed estimate (ReelDecide).
    static ReelSpeedMs := 80

    ; Right after the cast the bite pixel must stay white this long to count
    ; as white scenery (a moment of white is the panel animating).
    static BaselineMs := 1200

    ; Consecutive bite polls that must read the bite colour (one-poll
    ; flickers are ignored).
    static BitePolls := 2

    ; Consecutive non-bites (no reel bar) before giving up and re-pathing.
    static NonBiteRepath := 2

    ; All task settings in one place. -> {sellEvery, vip, sellAll, advanced,
    ; threshold, fishingSec, pathingSec}
    static Settings(cfg, coords) {
        fs := coords["fishing"]["failsafe"]
        return {
            sellEvery: FishLogic.SellEvery(cfg),
            vip: cfg.Get("General.vip", 1) ? true : false,
            sellAll: cfg.Get("General.sellAll", 1) ? true : false,
            advanced: cfg.Get("General.advancedFishing", 0) ? true : false,
            legacyReel: cfg.Get("General.legacyReel", 0) ? true : false,
            threshold: cfg.Get("General.advancedThreshold", coords["fishing"]["advanced"]["thresholdPx"]),
            fishingSec: FishLogic._Secs(cfg, "General.fishingFailsafeSec", fs["fishingSec"], FishLogic.MinFishingSec),
            pathingSec: FishLogic._Secs(cfg, "General.pathingFailsafeSec", fs["pathingSec"], FishLogic.MinPathingSec)
        }
    }

    ; The Dashboard's minimums. A hand-edited settings.ini could still say 0
    ; (every cast gives up at once and walks to the shop) or text (review).
    static MinFishingSec := 5
    static MinPathingSec := 10

    ; Whole seconds from key, at least lo; not a number -> def.
    static _Secs(cfg, key, def, lo) {
        v := cfg.Get(key, def)
        if !IsNumber(v)
            v := def
        return Max(lo, Integer(v))
    }

    ; True when every sampled color is pure black (bad capture, e.g. exclusive
    ; fullscreen): the strip must never be trusted then. Empty = black.
    ; ---- reel minigame, 2026 UI (lossless bar captures 2026-10-25) --------
    ; Bar frame y 1030/1055, inside x 1042..1517. The fish is a coloured box
    ; (purple, yellow, ... it changes per fish) that moves on its own; where
    ; the player's click bar covers it, it shows a lighter tint. The click
    ; bar fills from the left in one colour (blue/cyan, it changes with the
    ; light); the white arrow above (solid base line at y 1025, ~27 px wide)
    ; marks its right end. Clicking pushes the arrow right, it drifts left
    ; otherwise. Colours are never hard-coded: the arrow is read from its
    ; white base line, the click bar colour from the bar's left end, and the
    ; fish is the biggest block of colour that is not the click bar's.
    ; The bar's empty part is see-through: black in the dark, a dim grey
    ; over a bright scene (live 1080p SNOWY 2026-11-10: 0x3E4750, brightest
    ; channel 80). Counted as fish, that grey was the biggest block and the
    ; arrow chased it to the bar's end while the fish got away. So a dim,
    ; unsaturated grey (max < 100, channels within 24) is empty too.
    static ReelDark(c) {
        r := (c >> 16) & 0xFF, g := (c >> 8) & 0xFF, b := c & 0xFF
        mx := Max(r, g, b)
        return mx < 70 || (mx < 100 && mx - Min(r, g, b) <= 24)
    }
    static ReelWhite(c) => Min((c >> 16) & 0xFF, (c >> 8) & 0xFF, c & 0xFF) > 220
    ; Largest single-channel difference. The fish under the click bar can be
    ; very close to the bar's colour: (0,255,255) on (47,255,255) by day,
    ; (75,156,255) on (71,173,255) at night, while the bar itself varies by
    ; at most ~6 per channel along its length.
    static ReelDist(a, b) => Max(Abs(((a >> 16) & 0xFF) - ((b >> 16) & 0xFF)), Abs(((a >> 8) & 0xFF) - ((b >> 8) & 0xFF)), Abs((a & 0xFF) - (b & 0xFF)))
    static ReelFishDiff := 12
    ; The arrow's white base line is ~27 px wide (captures 2026-10-26: 1028..1055
    ; at rest on the far left). Longer white runs on its row are scenery seen
    ; above the bar (snow in SNOWY), never the arrow; at the far left the
    ; arrow sticks out of the strip, so a shorter run touching an end of the
    ; strip is the arrow resting there.
    static ArrowW := 28
    static ArrowMinW := 15
    static ArrowMaxW := 44
    static ArrowEdgeMinW := 8

    ; arrowRow: y 1025 (the arrow's base line); barRow: a row inside the bar.
    ; -> {m: arrow x (0 = no arrow), p1, p2: fish extent (0 = no fish)}
    static ReelScan(arrowRow, barRow, x1, stride) {
        m := FishLogic.ReelArrow(arrowRow, x1, stride)
        ; click bar colour near the bar's left end ("" when it is empty): the
        ; most typical of a few samples a little way in (the edge pixels are
        ; anti-aliased)
        fill := "", cand := []
        i := 1 + Ceil(4 / stride)
        while (i <= barRow.Length && i <= 1 + Ceil(20 / stride)) {
            c := barRow[i]
            if !FishLogic.ReelDark(c) && !FishLogic.ReelWhite(c)
                cand.Push(c)
            i++
        }
        if (cand.Length * 2 >= Ceil(16 / stride)) {
            bestSum := ""
            for a in cand {
                sum := 0
                for b in cand
                    sum += FishLogic.ReelDist(a, b)
                if (bestSum = "" || sum < bestSum)
                    bestSum := sum, fill := a
            }
        }
        ; fish: clusters of non-dark, non-white, non-fill pixels (gaps of up
        ; to ~14 px, e.g. the timer digits, join a cluster); keep the biggest
        maxGap := Max(1, 14 // stride)
        p1 := 0, p2 := 0, bestN := 0
        c1 := 0, c2 := 0, cn := 0, gap := 0
        for c in barRow {
            x := x1 + (A_Index - 1) * stride
            isFish := !FishLogic.ReelDark(c) && !FishLogic.ReelWhite(c)
                && (fill = "" || FishLogic.ReelDist(c, fill) > FishLogic.ReelFishDiff)
            if isFish {
                if (cn && gap <= maxGap) {
                    c2 := x, cn++
                } else {
                    if (cn > bestN)
                        bestN := cn, p1 := c1, p2 := c2
                    c1 := x, c2 := x, cn := 1
                }
                gap := 0
            } else if cn {
                gap++
            }
        }
        if (cn > bestN)
            bestN := cn, p1 := c1, p2 := c2
        if (bestN * stride < 20)
            p1 := 0, p2 := 0
        return {m: m, p1: p1, p2: p2, fill: fill}
    }

    ; The arrow's x on its row, 0 = none: the white run whose width is closest
    ; to ArrowW among runs ArrowMinW..ArrowMaxW px wide; a run touching an end
    ; of the strip (ArrowEdgeMinW+ px, not wider than ArrowMaxW) is the arrow
    ; resting at that end (m = that end). Wider runs are scenery: ignored.
    static ReelArrow(row, x1, stride) {
        runs := [], run := 0, runA := 0
        for c in row {
            if FishLogic.ReelWhite(c) {
                if (!run)
                    runA := A_Index
                run++
            } else if run {
                runs.Push([runA, run])
                run := 0
            }
        }
        if run
            runs.Push([runA, run])
        n := row.Length
        m := 0, bestD := ""
        for r in runs {
            w := r[2] * stride
            if (w > FishLogic.ArrowMaxW)
                continue
            edge := (r[1] = 1) || (r[1] + r[2] - 1 = n)
            if (w < FishLogic.ArrowMinW && !(edge && w >= FishLogic.ArrowEdgeMinW))
                continue
            d := Abs(w - FishLogic.ArrowW)
            if (bestD != "" && d >= bestD)
                continue
            bestD := d
            if (edge && w < FishLogic.ArrowMinW)
                m := (r[1] = 1) ? x1 : x1 + (n - 1) * stride
            else
                m := x1 + Round((r[1] - 1 + (r[2] - 1) / 2) * stride)
        }
        return m
    }

    ; Click now? st keeps the fish width and the last arrow sample between
    ; calls (start with {}). leadMs: aim with the arrow's predicted position.
    static ReelDecide(scan, st, nowMs, leadMs, aim := 0.4) {
        if (!scan.p2 || !scan.m)
            return false
        w := st.HasProp("w") ? st.w : 0
        if (scan.p1 > scan.m + 6)                       ; fish fully visible
            w := Max(w, scan.p2 - scan.p1)
        st.w := w
        left := (scan.p1 <= scan.m + 6 && w > 0) ? scan.p2 - w : scan.p1
        target := left + (scan.p2 - left) * aim
        ; arrow speed over the last ~80 ms (positions come in 2 px steps, so
        ; one 10 ms sample alone is far too noisy)
        if !st.HasProp("hist")
            st.hist := []
        st.hist.Push([nowMs, scan.m])
        while (st.hist.Length > 2 && nowMs - st.hist[2][1] >= FishLogic.ReelSpeedMs)
            st.hist.RemoveAt(1)
        old := st.hist[1]
        v := (nowMs - old[1] >= 20) ? (scan.m - old[2]) / (nowMs - old[1]) : 0
        return scan.m + v * leadMs < target
    }

    ; state.stats[key] += n when the state keeps stats (SchedState.Bump).
    static Bump(state, key, n := 1) {
        if IsObject(state) && HasMethod(state, "Bump")
            state.Bump(key, n)
    }

    static AllBlack(rows) {
        for row in rows
            for c in row
                if (c != 0)
                    return false
        return true
    }

    static FocusRetryMs := 2000

    ; Focuses Roblox. On failure: log once, wait FocusRetryMs (ctx-aware) so a
    ; caller that returns right after cannot spin the scheduler hot. -> bool.
    static FocusOrWait(deps, ctx, who) {
        if deps.roblox.Focus()
            return true
        deps.log.Call(who ": Roblox window not focused")
        deps.io.Wait(FishLogic.FocusRetryMs, ctx)
        return false
    }

    ; Throws ValueError naming the first few bad keys. Never prints values.
    static Require(who, cfg) {
        coords := cfg.Data("coords")
        routes := cfg.Data("routes")
        bad := FishLogic.Missing(coords, routes)
        if (bad.Length) {
            names := ""
            for p in bad {
                if (A_Index > 5) {
                    names .= ", ..."
                    break
                }
                names .= (A_Index > 1 ? ", " : "") p
            }
            throw ValueError(who ": data\coords.json / routes.json incomplete: " names)
        }
        return coords
    }
}
