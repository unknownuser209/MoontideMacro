#Requires AutoHotkey v2.0
; ---------------------------------------------------------------------------
; HelpTexts: one plain sentence or two per dashboard setting, keyed by its
; settings.ini key ("Section.key", any case). The dashboard's field helpers
; (_BoolField / _IntField / _StrField) put a "?" after a setting's label when
; it has an entry here; hovering or clicking the "?" shows the text.
;   HelpTexts.For(key) -> the text, or ""
; ---------------------------------------------------------------------------

class HelpTexts {
    static For(key) {
        k := StrLower(String(key))
        return HelpTexts.Map.Has(k) ? HelpTexts.Map[k] : ""
    }

    static Map := HelpTexts._Build()

    static _Build() {
        m := Map()
        add := (k, t) => m[StrLower(k)] := t
        ; fishing / selling
        add("General.fishing", "Fishing is what the macro does whenever no other task is due. Turn it off if you only want hunting, quests or alerts.")
        add("General.sellAll", "On: sells every fish. Off: sells only the fish you ticked in the Fishing Shop.")
        add("General.sellEvery", "How many catches before walking to the Fisher to sell. Lower = more trips, never a full bag.")
        add("General.vip", "Tick this if you own the VIP gamepass: the walks to the Fisher are faster and use the VIP routes.")
        add("General.advancedFishing", "Uses the width of the reel bar to time clicks. Only turn on if normal fishing misses a lot.")
        add("General.advancedThreshold", "How close the fish must be to the bar's centre before a click (advanced mode only). Leave the default unless told otherwise.")
        add("General.fishingFailsafeSec", "If a cast takes longer than this, the macro gives up on it and casts again.")
        add("General.pathingFailsafeSec", "If a walk takes longer than this, the macro respawns and tries again.")
        add("Limbo.enabled", "Uses the Portable Crack and waits in Limbo for Eden instead of fishing. Fishing, selling, crafting, quests and merchants are paused while it is on.")
        ; crafting
        add("Craft.enabled", "Crafts the potion set on this page whenever the materials allow.")
        add("Craft.cauldron", "Also uses Stella's cauldron. Needs the cauldron walk recorded (Setup > Routes).")
        ; quests / merchants
        add("quests.enabled", "Accepts, tracks and turns in quests at the quest board.")
        add("General.questIntervalMin", "How often to visit the quest board, in minutes.")
        add("quests.dismissDisabled", "Dismisses quests you did not tick in the list, so new ones can appear.")
        add("merchant.enabled", "Buys from Mari and the Jester when the chat says they arrived (your want-list is on this page).")
        add("merchant.chatPollSec", "How often the chat is read for a merchant arriving, in seconds.")
        ; biome items / obby / memory match
        add("BiomeItems.enabled", "Uses your biome items (Randomizer, Strange Controller, Selector) whenever their cooldown allows.")
        add("BiomeItems.biomeRandomizer", "The crafted Biome Randomizer (35 min cooldown). The one-time Season Pass randomizer is never used.")
        add("BiomeItems.strangeController", "The Strange Controller (20 min cooldown).")
        add("BiomeItems.biomeSelector", "The Biome Selector (60 min cooldown). Each use spends one Drive.")
        add("Obby.enabled", "Runs the obby for its reward on a timer, with the aura it needs.")
        add("Obby.intervalMin", "Minutes between obby runs.")
        add("Obby.retries", "How many times a failed obby run is tried again before waiting for the next one.")
        add("MemoryMatch.enabled", "Plays Memory Match every 12 hours and keeps the best pairs. Needs the memory_match walk recorded.")
        add("Auras.equipFirst", "Swaps auras by searching the name and equipping the first result, without reading it. Faster, but only use it if your aura names are unique.")
        ; hunting
        add("Minions.enabled", "Hunts orbs and minions in rare biomes (this event ends later in November).")
        add("Minions.aura", "The aura worn for fights. Small auras like Eden work best: big ones hide the targets.")
        add("Minions.boss", "Also fights the GRAVEYARD boss when it spawns.")
        add("Minions.normal", "Also hunts in the NORMAL biome, not only in rare ones.")
        add("Minions.maxSec", "The longest one hunt may take before the macro goes back to fishing.")
        add("Minions.putBack", "Puts your previous aura back on after the hunt.")
        add("Minions.shiftLock", "Uses Roblox shift lock while fighting (turn on Shift Lock Switch in Roblox settings first).")
        ; alerts
        add("General.sound", "Plays a sound on this PC when a rare biome starts.")
        add("General.everyonePing", "Pings @everyone on your Discord for the biomes listed below.")
        add("General.everyoneBiomes", "The biomes that ping @everyone, separated by commas (for example GLITCHED, DREAMSPACE).")
        add("Medal.enabled", "Saves a clip with Medal (or another clip app) by pressing its clip hotkey.")
        add("Medal.clipHotkey", "The same hotkey your clip app uses to save a clip, for example F8 or Alt+9.")
        add("Medal.onRareBiome", "Clips when a rare biome starts.")
        add("Medal.onRareAura", "Clips when you roll a rare aura.")
        add("Medal.auraMinRarity", "Only auras rarer than this (1 in N) are clipped.")
        add("Medal.auras", "Aura names that are always clipped, whatever their rarity, separated by commas.")
        add("Medal.auraAlwaysCategories", "Aura classes that are always clipped.")
        add("Medal.delaySec", "Seconds to wait before pressing the clip hotkey, so the moment is inside the clip.")
        add("Medal.cooldownSec", "The shortest time between two clips.")
        add("Summary.enabled", "Sends one message a day with what the macro did, to the webhooks that have Stop ticked.")
        add("Summary.time", "When the daily summary is sent (24 hour clock, for example 23:55).")
        add("Remote.enabled", "Lets you control the macro from Discord with commands like !status, !start and !stop. Needs a Discord bot.")
        add("Remote.channel", "The id of the Discord channel the bot listens in (Developer Mode on, right-click the channel, Copy Channel ID).")
        add("Remote.users", "The Discord user ids allowed to send commands, separated by commas. Everyone else is ignored.")
        add("Remote.prefix", "What commands start with, for example ! for !status.")
        ; schedule
        add("Schedule.enabled", "Starts and stops the macro by itself at the times below.")
        add("Schedule.start", "When to start (24 hour clock, for example 22:00).")
        add("Schedule.end", "When to stop (24 hour clock). An end before the start means overnight.")
        add("Schedule.maxHours", "Stops after this many hours even inside the window. 0 = no limit.")
        ; recovery
        add("recovery.enabled", "Rejoins your private server after a disconnect and stops Roblox kicking you for being idle.")
        add("recovery.antiGhost", "If the game moves you into a server your friends cannot join, rejoins your private server.")
        add("recovery.afkMin", "How often to move a little so Roblox does not kick you for being idle.")
        add("recovery.loadSec", "How long to wait for Roblox to load after a rejoin before checking the screen.")
        add("recovery.stuckMin", "If nothing has worked for this long, the macro respawns and starts over.")
        ; look
        add("UI.animations", "Fades, moving stars and the running pulse. They only move while this window is in front.")
        add("UI.simple", "Simple mode shows only the main pages. Turn it off to see every page and option.")
        return m
    }
}
