#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\..\Brand.ahk
#Include %A_LineFile%\..\Theme.ahk
#Include %A_LineFile%\..\Anim.ahk
; ---------------------------------------------------------------------------
; Splash: the startup screen (moon, product name, "made by <creator>").
;   Splash.Show(opts := "")  BLOCKS until it is over. opts is a Map; key
;                            "animations" = 0 shows it 600 ms with no fades.
;                            Tests only: "noshow" = 1 never shows the window,
;                            "holdMs" overrides the 1000 ms hold, "hook" is
;                            called (g, clickControl) once built, before showing.
;                            Otherwise: fade in 300 ms, hold 1000 ms, fade out
;                            300 ms. A click skips it. App.Boot calls it before
;                            the Dashboard exists, only in "normal" mode.
;   Splash.Text()            "<product> <dot> made by <creator>".
; The fades are UNGATED Anim tweens: the Dashboard (and its gate) does not
; exist yet, and a gated tween behind a closed gate would jump to its end.
; The class also holds the second stored check value that lib\Credits.ahk
; compares against (rewritten by tools\update_credits.ahk, one line, do not
; reformat).
; ---------------------------------------------------------------------------
class Splash {
    static _ck := [17, 115, 85, 180, 196, 244, 212, 156, 127, 12, 57, 26, 168, 129, 232, 206, 36, 84, 49, 66, 247, 134, 229, 222, 58, 76, 47, 89, 186, 152, 171, 131, 53, 68, 39, 87, 180, 153, 246, 238, 207, 121, 93, 61, 25, 161, 221, 230, 194, 116, 81, 54, 66, 247, 132, 251, 214, 57, 24, 127, 94, 236, 206, 243]
    static W := 420
    static H := 250

    static Text() => Brand.Name " " Chr(0xB7) " " Credits.MadeBy()

    static Show(opts := "") {
        o := (opts is Map) ? opts : Map()
        fade := !(o.Has("animations") && o["animations"] = 0)
        hold := o.Has("holdMs") ? o["holdMs"] : 1000
        st := {skip: false, phase: false, click: ""}
        g := Splash._Build(st)
        try {
            ; A layered window is not drawn until SetLayeredWindowAttributes has run:
            ; always set the opacity (0 to fade in, 255 when there are no fades).
            Splash._Alpha(g, fade ? 0 : 255)
            if o.Has("hook")
                o["hook"].Call(g, st.click)
            if !o.Has("noshow")
                g.Show("w" Splash.W " h" Splash.H " Center NoActivate")      ; never steals focus from Roblox
            if fade {
                Splash._Fade(st, g, "splash.in", false)
                Splash._Wait(st, hold)
                Splash._Fade(st, g, "splash.out", true)
            } else
                Splash._Wait(st, 600)
        } finally {
            Anim.Stop("splash.in")
            Anim.Stop("splash.out")
            try g.Destroy()
        }
    }

    static _Build(st) {
        g := Theme.Window("", "-Caption +AlwaysOnTop +ToolWindow +E0x80000")      ; E0x80000: layered, for the fades
        w := Splash.W, h := Splash.H
        Theme.Rect(g, 0, 0, w, 1, Theme.PanelC)
        Theme.Rect(g, 0, h - 1, w, 1, Theme.PanelC)
        Theme.Rect(g, 0, 0, 1, h, Theme.PanelC)
        Theme.Rect(g, w - 1, 0, 1, h, Theme.PanelC)
        Theme.Moon(g, (w - 96) // 2, 34, 96)
        Theme.Label(g, "x0 y146 w" w " h40 Center", Brand.Name, "title", Theme.Bg)
        Theme.Label(g, "x0 y194 w" w " h24 Center", Credits.MadeBy(), "head", Theme.Bg)
        c := g.Add("Text", "x0 y0 w" w " h" h " +0x100 BackgroundTrans")      ; on top: a click anywhere skips
        c.OnEvent("Click", (*) => st.skip := true)
        st.click := c
        return g
    }

    static _Fade(st, g, key, out) {
        if st.skip
            return
        st.phase := false
        Anim.Tween(key, 300, (p) => Splash._Alpha(g, Round(255 * (out ? 1 - p : p))), () => st.phase := true, false)
        t0 := A_TickCount
        while (!st.phase && !st.skip && A_TickCount - t0 < 600)      ; deadline: startup can never hang here
            Sleep(10)
        Anim.Stop(key)
    }

    ; Window opacity 0..255 (the window is hidden at first, so no WinSetTransparent).
    static _Alpha(g, a) {
        DllCall("SetLayeredWindowAttributes", "Ptr", g.Hwnd, "UInt", 0, "UChar", a, "UInt", 2)
    }

    static _Wait(st, ms) {
        t0 := A_TickCount
        while (!st.skip && A_TickCount - t0 < ms)
            Sleep(10)
    }
}
