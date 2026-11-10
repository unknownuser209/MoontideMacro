#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\lib\RouteRecorder.ahk
#Include ..\lib\Brand.ahk
; ---------------------------------------------------------------------------
; Route recorder (standalone). Records a walking route into data\routes.json.
;
;   AutoHotkey64.exe tools\record_route.ahk [name]
;     name: quest_board | cauldron (or any
;     lower-case name your settings point to). Without a name a small list
;     asks for one.
;
; It only WATCHES the keyboard (GetKeyState); it never presses, clicks or
; moves anything. Stand at the start spot in Roblox (after a reset to spawn),
; press F7, walk with
; W A S D / Space, press F7 again to stop and save. Esc cancels.
; Recording from the dashboard (Setup > Routes) is the same, and the running
; macro sees the new route at once; after using this tool, restart the macro.
; ---------------------------------------------------------------------------

RecordRouteMain(A_Args)

RecordRouteMain(args) {
    path := A_ScriptDir "\..\data\routes.json"
    name := (args.Length >= 1) ? Trim(args[1]) : RecordRouteAsk()
    if (name = "")
        ExitApp(0)
    if !RouteRecorder.ValidName(name) {
        MsgBox("Route name '" name "' is not allowed (lower-case letters, digits, _; not vip / nonvip).", Brand.Name " route recorder", "Icon!")
        ExitApp(2)
    }
    r := RouteRecorder.Run(name, path)
    MsgBox("Route '" name "': " r.msg, Brand.Name " route recorder", r.ok ? "Iconi" : "Icon!")
    ExitApp(r.ok ? 0 : 1)
}

; Small chooser. -> route name or "" (closed).
RecordRouteAsk() {
    pick := [""]
    g := Gui("+AlwaysOnTop", Brand.Name " route recorder")
    g.BackColor := "0D1117"
    g.SetFont("s10 cF7F1E8", "Segoe UI")
    g.Add("Text", "w300", "Which route do you want to record?")
    lb := g.Add("ListBox", "w300 r5 Background0B2A5B cF7F1E8", RouteRecorder.Names)
    lb.Choose(1)
    ok := g.Add("Button", "w300 Default", "Record")
    done := false
    ok.OnEvent("Click", (*) => (pick[1] := lb.Text, done := true))
    g.OnEvent("Close", (*) => (done := true))
    g.Show()
    while !done
        Sleep(50)
    try g.Destroy()
    return pick[1]
}
