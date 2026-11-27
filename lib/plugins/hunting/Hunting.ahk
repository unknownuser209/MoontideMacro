#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\..\..\Plugins.ahk
#Include %A_LineFile%\..\Minions.ahk
#Include %A_LineFile%\..\ClockWatch.ahk
; ---------------------------------------------------------------------------
; HuntingPlugin: the built-in plugin "Orb & boss hunting" (2026-11-26). It is
; what the Limited tab was: the Halloween orb / minion hunt (MinionsTask,
; Minions.*), the Sinister S. / P. and orb messages (SinisterReport,
; ClockWatch, ChatWatch's boss / orb lines, Hunting.bossAlert /
; Hunting.orbAlert) and the Cursed Rune Fragment (Hunting.cursedRune,
; BiomeItemsTask). Its settings page is the Hunting page (Plugins > Settings).
;
; Switched off on the Plugins tab (Plugins.hunting = 0) none of it runs: no
; hunt, no boss or orb message, no chat read for them, no rune. On (the
; default) everything works exactly as the Limited tab did, each part by its
; own switch. The old [Limited] keys move to [Hunting] (Config.RenamedKeys).
;
;   HuntingPlugin.Active(cfg)      the plugin is on
;   HuntingPlugin.BossOn(cfg)      boss messages wanted (on + bossAlert)
;   HuntingPlugin.OrbOn(cfg)       orb messages wanted (on + orbAlert)
;   HuntingPlugin.RuneOn(cfg)      the Cursed Rune Fragment (on + cursedRune)
;   HuntingPlugin.ChatWanted(cfg)  the chat must be read for it
; ---------------------------------------------------------------------------
class HuntingPlugin extends MoontidePlugin {
    static Id := "hunting"
    static Manifest := Map("id", "hunting", "name", "Orb & boss hunting", "version", "1.0.0", "author", "Moontide"
        , "description", "Hunts biome orbs and minions with a combat aura, sends the Sinister S. / P. and orb messages, uses one Cursed Rune Fragment per Graveyard / Pumpkin Moon night. (The Limited tab before.)"
        , "page", "Hunting", "section", "Hunting", "def", 1, "settings", [])

    static Active(cfg) => Plugins.On(cfg, HuntingPlugin.Id, 1)
    static _Get(cfg, key, def) {
        try return cfg.Get(key, def)
        return def
    }
    static BossOn(cfg) => HuntingPlugin.Active(cfg) && HuntingPlugin._Get(cfg, "Hunting.bossAlert", 1) ? true : false
    static OrbOn(cfg) => HuntingPlugin.Active(cfg) && HuntingPlugin._Get(cfg, "Hunting.orbAlert", 0) ? true : false
    static RuneOn(cfg) => HuntingPlugin.Active(cfg) && HuntingPlugin._Get(cfg, "Hunting.cursedRune", 0) ? true : false
    static HuntOn(cfg) => HuntingPlugin.Active(cfg) && HuntingPlugin._Get(cfg, "Minions.enabled", 0) ? true : false
    static ChatWanted(cfg) => HuntingPlugin.BossOn(cfg) || HuntingPlugin.OrbOn(cfg)
}
