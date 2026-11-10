#Requires AutoHotkey v2.0
; ---------------------------------------------------------------------------
; Biomes: lookup in cfg.Data("biomes") (data\biomes.json).
;
;   Biomes.Norm(name)       trim, collapse whitespace, uppercase
;   Biomes.Find(cfg, name)  -> Map{name, rare 0|1, potions Array, known bool}
;     Unknown names (e.g. a new game biome) -> rare 0, potions [], known false.
;     rare is 1 ONLY for JSON true / 1 (anything else = not rare).
;     potions entries are expected as {"name": "<potion id>", "qty": N} (or
;     "id" instead of "name"); the id is the data\potions.json entry id (=
;     the in-game name, except "Godly Potion (Sky)" / "(Sea)" / "(Hell)").
;     They are validated by the potions task, not here.
;   Biomes.IsNormal(name)   true for the game's everyday biomes (Normal):
;     an event biome (PUMPKIN MOON, GRAVEYARD, BLOOD RAIN ...), a rare one or
;     a name not listed (a new game biome) is not. Biome items only change a
;     normal biome away.
; ---------------------------------------------------------------------------

class Biomes {
    static Normal := ["NORMAL", "WINDY", "RAINY", "SNOWY", "SAND STORM", "HELL", "STARFALL", "CORRUPTION", "LOST FOREST", "HEAVEN"]

    static Norm(n) => StrUpper(Trim(RegExReplace(String(n), "[\s\x{00A0}]+", " "), " "))

    static IsNormal(name) {
        n := Biomes.Norm(name)
        for b in Biomes.Normal
            if (n == b)
                return true
        return false
    }

    static Find(cfg, name) {
        n := Biomes.Norm(name)
        list := []
        try {
            d := cfg.Data("biomes")
            if (d is Map && d.Has("biomes") && d["biomes"] is Array)
                list := d["biomes"]
        }
        if (n != "") {
            for b in list {
                if !(b is Map && b.Has("name") && b["name"] is String && Biomes.Norm(b["name"]) == n)
                    continue
                rare := (b.Has("rare") && b["rare"] is Integer && b["rare"] = 1) ? 1 : 0
                pots := (b.Has("potions") && b["potions"] is Array) ? b["potions"] : []
                return Map("name", name, "rare", rare, "potions", pots, "known", true)
            }
        }
        return Map("name", name, "rare", 0, "potions", [], "known", false)
    }
}
