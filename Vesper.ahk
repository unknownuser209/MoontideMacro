#Requires AutoHotkey v2.0
#SingleInstance Force
; Vesper Macro entry point. All wiring lives in lib\App.ahk (testable).
; #SingleInstance Force: a second copy replaces the first, so two instances
; never share data\potion_usage.json (PotionSafety).
; Paths are absolute from A_ScriptDir (settings.ini, data\, potion usage).
#Include %A_ScriptDir%\lib\App.ahk
; Plugins switched on in plugins\ (lib\Plugins.ahk writes this file, only
; with plugins that passed a separate /Validate check; *i: none = fine)
#Include *i %A_ScriptDir%\plugins\.loaded\_enabled.ahk

Persistent
; Per-monitor DPI awareness before ANY coordinate or capture call: at 125 /
; 150 % Windows would otherwise hand the macro scaled-down coordinates.
Screen.InitDpi()
VesperApp := App.Main(A_ScriptDir, A_Args)
