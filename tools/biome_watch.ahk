#Requires AutoHotkey v2.0
#SingleInstance Force
#Include %A_ScriptDir%\..\lib\Config.ahk
#Include %A_ScriptDir%\..\lib\Scheduler.ahk
#Include %A_ScriptDir%\..\lib\LogWatch.ahk
#Include %A_ScriptDir%\..\lib\Webhook.ahk
#Include %A_ScriptDir%\..\lib\BiomeEvents.ahk
#Include %A_ScriptDir%\..\lib\Clip.ahk
; ---------------------------------------------------------------------------
; biome_watch.ahk [hours]: biome / aura detection and the webhook reports
; only, from the Roblox log, while the macro itself is stopped or busy being
; worked on (the user, 2026-11-02: "let biome detection and webhook reports
; stay running the entire time").
;
; Uses settings.ini as the macro does (webhooks, @everyone biomes, Medal
; clips on rare biomes / auras). Runs NO task and never uses potions: the
; potions queue BiomeEvents feeds is a no-op here. Default 24 h, then exits.
; Do not run it together with a started macro (both would report).
; ---------------------------------------------------------------------------
class NoPotions {
    Queue(*) => 0
}

hours := A_Args.Length >= 1 && IsNumber(A_Args[1]) ? A_Args[1] : 24
root := A_ScriptDir "\.."
cfg := Config(root)
logFile := root "\logs\biome_watch.log"
WatchLog(m) {
    global logFile
    try FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") "  " m "`n", logFile)
}
wh := Webhook(cfg, WatchLog)
Clip.Setup(cfg, wh, WatchLog)
state := SchedState()
be := BiomeEvents(Map("cfg", cfg, "state", state, "wh", wh, "potions", NoPotions()
    , "log", WatchLog, "clip", Clip, "lastFile", cfg.dataDir "\last_biome.txt"
    , "hadFile", cfg.dataDir "\auras_had.txt"))
lw := LogWatch()
WatchLog("biome watch started (" hours " h, reports only, no potions)")
A_IconTip := "Moontide biome watch (reports only)"
deadline := A_TickCount + hours * 3600000
while (A_TickCount < deadline) {
    try {
        for ev in lw.Poll() {
            t := ev["type"]
            if (t = "biome" || t = "aura")
                be.Handle(ev)
        }
    } catch Any as e {
        WatchLog("poll error: " e.Message)
    }
    try wh.Flush()
    Sleep 1000
}
wh.Drain(5000)
WatchLog("biome watch ended")
