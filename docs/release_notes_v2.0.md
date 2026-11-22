Moontide Macro v2.0: the big one

**Make the dashboard yours**
- **Themes.** Settings > Look is now a full page. Save as many themes as you like:
  - colours, with every shade if you want;
  - fonts for each kind of text;
  - window size (100, 115 or 130 %);
  - a background picture (fill, fit, centre or tile, and how dark);
  - which side the sidebar is on.
- **Edit layout.** Drag cards by their title, resize them from the corner, and hide the ones you don't use.
- **Share a theme.** Export makes one .moontheme file with the picture inside. Send it to a friend; they import it, or drop it on the window, and see a preview first.
- **New page groups and search.** Pages are grouped into Farming, Quests & events, Biomes & Potions, Discord & Clips, Settings and Help. Press Ctrl+F and type, and it opens the page and shows the card.
- **Languages.** Vietnamese is added, every translation was reviewed, and the language is the first thing setup asks.

**Setup that calibrates itself**
- The macro finds these on screen by their text, so there's nothing to hover for them:
  - the Fisher shop tiles;
  - Stella's Workshop;
  - the Biome Selector;
  - the quest board;
  - most of the inventory.
- Screen sizes without a preset get the nearest one.

**Fishing, shop and crafting**
- **Fish shop** replaces the Craft cycle. It buys your potions at the Fisher in the same visit as the sell, and buys again every 30 minutes (Craft.buyEveryMin) as well as after each "auto crafted" message. Before, a missed message could leave the auto craft without potions for hours.
- **Fisher shop.** It now uses the shop's real Buy layout, finds a potion by its name when a tile shows another item, and logs every purchase.
- **Stella's cauldron.** The cauldron step now:
  - waits for the Workshop to open;
  - presses Enter in the search;
  - waits for the portal teleport into Stella's Sanctuary, and walks again if it missed.
- **The walk to the Fisher** tries up to 3 times. After a craft trip, the macro goes straight back to the fishing spot.

**Quests, merchants, minigames**
- **Quests.** Claim Rewards shows on every accepted quest, finished or not, so a claim that does nothing now waits 60, 120, then 240 minutes. It no longer presses the button every visit.
- **Mari and Jester.** Item names in the game font read much better, so the macro actually buys your list now. It also closes the inventory after the teleporter.
- **Memory Match.** It recognises the game's new green for matched pairs, and closes its board by every known way.
- **Biome Selector.** It confirms only when the prompt names your Drive, closes the window with its X, and uses the Drive you picked even when its row is hard to read.

**Recovery and safety**
- **Stuck screens.** When the same screen keeps failing, the macro rejoins your private server (at most once every 20 minutes).
- **Portable Crack (Limbo).** Limbo now uses the Portable Crack, closes the inventory after it, and can tell a restart inside THE LIMBO.
- **Alerts.** The aura alert threshold and the clip threshold are shown side by side, so it's clear which one pings.
- **Shift lock and focus.** Any game window left open is closed between tasks, and the macro explains a shift-lock or focus pause instead of looking idle.

If something misbehaves, send `logs\macro.log` (or the fix card's Support zip) in the Discord.
