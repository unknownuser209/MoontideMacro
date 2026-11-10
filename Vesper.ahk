#Requires AutoHotkey v2.0
#SingleInstance Force
; Vesper Macro entry point. All wiring lives in lib\App.ahk (testable).
; #SingleInstance Force: a second copy replaces the first, so two instances
; never share data\potion_usage.json (PotionSafety).
; Paths are absolute from A_ScriptDir (settings.ini, data\, potion usage).
#Include %A_ScriptDir%\lib\App.ahk

Persistent
VesperApp := App.Main(A_ScriptDir, A_Args)
