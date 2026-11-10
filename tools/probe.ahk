#Requires AutoHotkey v2.0
#SingleInstance Force
; ---------------------------------------------------------------------------
; Probe (manual use only, not part of the macro).
;   F8        tooltip: mouse x,y (screen), pixel color, Roblox 1440p check,
;             and OCR of a 400x80 box centered on the mouse
;   Shift+F8  copy the last probe text to the clipboard
;   Ctrl+F8   exit
; Use with Roblox open to confirm OCR reads chat text and to read coords.
; ---------------------------------------------------------------------------
#Include %A_ScriptDir%\..\lib\Roblox.ahk
#Include %A_ScriptDir%\..\lib\Pixel.ahk
#Include %A_ScriptDir%\..\lib\Ocr.ahk

CoordMode("Mouse", "Screen")
CoordMode("ToolTip", "Screen")
global ProbeLast := ""
global ProbeBoxW := 400, ProbeBoxH := 80

F8:: ProbeNow()
+F8:: ProbeCopy()
^F8:: ExitApp()

ProbeNow() {
    global ProbeLast
    ToolTip()               ; keep the old tooltip out of the capture
    Sleep(60)
    MouseGetPos(&mx, &my)
    color := Format("0x{:06X}", Pixel.Get(mx, my))
    bx := mx - ProbeBoxW // 2, by := my - ProbeBoxH // 2
    t0 := A_TickCount
    text := Ocr.Read(bx, by, ProbeBoxW, ProbeBoxH)
    ms := A_TickCount - t0
    ProbeLast := "pos " mx "," my "  color " color
        . "`nroblox " (Roblox.Hwnd() ? (Roblox.IsFullscreen1440() ? "1440 fullscreen" : "NOT 2560x1440 at 0,0") : "not running")
        . "`nocr box " bx "," by " " ProbeBoxW "x" ProbeBoxH " (" ms " ms):"
        . "`n" (text = "" ? "<nothing>" : text)
    ToolTip(ProbeLast, mx + 24, my + ProbeBoxH // 2 + 8)
}

ProbeCopy() {
    if (ProbeLast != "")
        A_Clipboard := ProbeLast
}
