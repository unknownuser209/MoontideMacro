#Requires AutoHotkey v2.0
; ---------------------------------------------------------------------------
; The public build's stand-in for lib\plugins\sniper\Sniper.ahk: the biome
; sniper is not released (the owner, 2026-11-27). tools\strip_private.py
; puts this file in its place when publishing. Available = false keeps it
; out of the built-in plugins (App.BuiltinPlugins) and drops the Sniper page
; (Dashboard.__New); the other members only let the code that names them
; load, and do nothing.
; ---------------------------------------------------------------------------
class SniperPlugin {
    static Available := false
    static Id := "sniper"
    static DefBiomes := ""
    static DefBlocked := ""
    static Manifest := Map("id", "sniper", "name", "Biome sniper", "def", 0, "settings", [])
    static BadChannels(text) => ""
    static CleanToken(t) => ""
    static TokenLooksOk(t) => false
}

class SniperVault {
    static Protect(s) => ""
    static Unprotect(s) => ""
}
