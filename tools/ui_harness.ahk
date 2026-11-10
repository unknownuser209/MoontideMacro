#Requires AutoHotkey v2.0
#SingleInstance Off
; ---------------------------------------------------------------------------
; UI harness (dev only): builds the dashboard + overlay on a SCRATCH config
; (A_Temp\vesper_ui_harness, copy of data\*.json, fake webhook), shows them
; OFF-SCREEN without activating them, captures every page and the overlay
; with PrintWindow, measures this process's memory, then exits.
;
;   AutoHotkey64.exe tools\ui_harness.ahk <outDir> [holdSec]
;
; Prints "MEM ..." lines and the PNG paths to stdout. Never reads or writes
; the repo's settings.ini, never takes focus from the foreground app (e.g. a
; running Roblox), never changes dry-run: the "dry run OFF" banner is a
; render-only preview.
; ---------------------------------------------------------------------------
#Include ..\lib\ui\Dashboard.ahk
#Include ..\lib\ui\Overlay.ahk

Out(s) => FileAppend(s "`n", "*")
OnError((e, *) => (Out("ERROR " e.Message " | " e.Extra " | line " e.Line " | " e.File), ExitApp(3)))

MemMB() {
    pmc := Buffer(A_PtrSize = 8 ? 72 : 40, 0)
    NumPut("UInt", pmc.Size, pmc, 0)
    DllCall("psapi\GetProcessMemoryInfo", "Ptr", DllCall("GetCurrentProcess", "Ptr"), "Ptr", pmc, "UInt", pmc.Size)
    ws := NumGet(pmc, A_PtrSize = 8 ? 16 : 12, "UPtr")
    priv := NumGet(pmc, A_PtrSize = 8 ? 56 : 32, "UPtr")
    return Format("ws={:.1f}MB private={:.1f}MB", ws / 1048576, priv / 1048576)
}

; Client-area capture: PrintWindow(PW_CLIENTONLY | PW_RENDERFULLCONTENT).
; Works off-screen and never activates the window.
; Repaint everything, take a throwaway capture (an off-screen window's first
; PrintWindow can come back half painted), then the real one.
Shot(hwnd, outDir, name) {
    DllCall("RedrawWindow", "Ptr", hwnd, "Ptr", 0, "Ptr", 0, "UInt", 0x0185)
    Sleep(250)
    Grab(hwnd, A_Temp "\vesper_harness_throwaway.png")
    Sleep(250)
    ok := Grab(hwnd, outDir "\" name ".png")
    try FileDelete(A_Temp "\vesper_harness_throwaway.png")
    Out(ok ? "SHOT " outDir "\" name ".png" : "SHOT FAILED " name)
}

Grab(hwnd, dest) {
    rc := Buffer(16, 0)
    DllCall("GetClientRect", "Ptr", hwnd, "Ptr", rc)
    w := NumGet(rc, 8, "Int"), h := NumGet(rc, 12, "Int")
    DllCall("LoadLibrary", "Str", "gdiplus", "Ptr")
    si := Buffer(3 * A_PtrSize, 0)
    NumPut("UInt", 1, si, 0)
    token := 0, pBmp := 0
    DllCall("gdiplus\GdiplusStartup", "Ptr*", &token, "Ptr", si, "Ptr", 0)
    hdcS := DllCall("GetDC", "Ptr", 0, "Ptr")
    hdc := DllCall("CreateCompatibleDC", "Ptr", hdcS, "Ptr")
    hbm := DllCall("CreateCompatibleBitmap", "Ptr", hdcS, "Int", w, "Int", h, "Ptr")
    old := DllCall("SelectObject", "Ptr", hdc, "Ptr", hbm, "Ptr")
    ok := DllCall("PrintWindow", "Ptr", hwnd, "Ptr", hdc, "UInt", 3)
    DllCall("SelectObject", "Ptr", hdc, "Ptr", old, "Ptr")
    DllCall("gdiplus\GdipCreateBitmapFromHBITMAP", "Ptr", hbm, "Ptr", 0, "Ptr*", &pBmp)
    clsid := Buffer(16, 0)
    DllCall("ole32\CLSIDFromString", "WStr", "{557CF406-1A04-11D3-9A73-0000F81EF32E}", "Ptr", clsid)
    r := DllCall("gdiplus\GdipSaveImageToFile", "Ptr", pBmp, "WStr", dest, "Ptr", clsid, "Ptr", 0)
    DllCall("gdiplus\GdipDisposeImage", "Ptr", pBmp)
    DllCall("DeleteObject", "Ptr", hbm)
    DllCall("DeleteDC", "Ptr", hdc)
    DllCall("ReleaseDC", "Ptr", 0, "Ptr", hdcS)
    DllCall("gdiplus\GdiplusShutdown", "Ptr", token)
    return ok && !r
}

outDir := A_Args.Length ? A_Args[1] : A_ScriptDir "\..\.superpowers\screens"
holdSec := A_Args.Length > 1 ? Integer(A_Args[2]) : 0
DirCreate(outDir)
Out("MEM baseline " MemMB())

root := RegExReplace(A_LineFile, "\\tools\\[^\\]+$", "")
cfgDir := A_Temp "\vesper_ui_harness"
try DirDelete(cfgDir, true)
DirCreate(cfgDir "\data")
Loop Files, root "\data\*.json"
    FileCopy(A_LoopFilePath, cfgDir "\data\" A_LoopFileName, 1)
cfg := Config.Load(cfgDir)
fake := "https://discord.com/api/webhooks/000000000000000000/FAKE_SCREENSHOT_TOKEN_9d1c"
cfg.SetWebhooks([Map("name", "Main", "url", fake, "mention", "123456789", "enabled", 1
    , "events", ["biome", "rare", "errors", "startstop", "potions"])
    , Map("name", "Rare only", "url", "", "mention", "", "enabled", 0, "events", ["rare"])])
cfg.Set("General.privateServer", "https://www.roblox.com/share?code=FAKEFAKEFAKE1234&type=Server")
cfg.Save()

cb := Map("start", () => d.Log("Start pressed"), "pause", () => d.Log("Pause pressed"), "stop", () => d.Log("Stop pressed"))
d := Dashboard(cfg, cb)
o := Overlay(cfg, cb)
offX := SysGet(76) + SysGet(78) + 200          ; right of the whole virtual desktop
d._gui.Show("x" offX " y0 w" Dashboard.W " h" Dashboard.H " NoActivate")
d._shown := true
o._gui.Show("x" offX + 1100 " y0 w" Overlay.W " h" Overlay.H " NoActivate")
o._shown := true
d.SetStatus("Running", "Fishing", "GLITCHED", true, 5025000, 37)
o.SetStatus("Running", "Fishing", "GLITCHED", true, 5025000, 37)
for line in [Brand.Name " started (dry run)", "LogWatch: biome NORMAL", "Fishing: loop 36 done", "Sell: sold all fish"
        , "Webhook: posted to " fake, "Recovery: link " cfg.Get("General.privateServer", "") " ready"
        , "LogWatch: biome GLITCHED (rare)", "Potions: DRY RUN would use Lucky Potion x1 (caps ok)", "Fishing: loop 37 done"]
    d.Log(line)
Sleep(1500)
Out("MEM idle " MemMB())

for i, name in Dashboard.Pages {
    d.SelectPage(i)
    if (name = "Biomes & Potions") {
        d.SelectBiome("GLITCHED")
        d.SelectPotion("Heavenly Potion")
    }
    Shot(d.Hwnd, outDir, "dash_" Format("{:02}", i) "_" RegExReplace(name, "[^A-Za-z]+", ""))
}
d.SelectPage(6)
d._RefreshDry(0)        ; render-only preview of the banner; cfg untouched
Shot(d.Hwnd, outDir, "dash_06b_dryrun_off_preview")
d._RefreshDry()
d.SelectPage(1)
Shot(o.Hwnd, outDir, "overlay_running")
o.SetStatus("Paused", "Sell", "WINDY", false, 61000, 4)
Shot(o.Hwnd, outDir, "overlay_paused")
Out("MEM after pages " MemMB())
Out("DRYRUN cfg=" cfg.Get("General.dryRun", 1))
Out("LOGLEAK " ((InStr(d.LogText(), "FAKE_SCREENSHOT_TOKEN") || InStr(d.LogText(), "FAKEFAKEFAKE")) ? "YES" : "no"))
if holdSec
    Sleep(holdSec * 1000)
try DirDelete(cfgDir, true)
ExitApp(0)
