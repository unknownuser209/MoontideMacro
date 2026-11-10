# Vesper Macro — Design Spec

Date: 2026-10-24
Status: Draft, awaiting user review

## 1. Purpose

An unattended AutoHotkey v2 macro for Roblox **Sol's RNG**, for personal use. It fishes, sells, auto-crafts, runs the quest board, buys from merchants, reports biomes to Discord, and drinks potions in rare biomes. The UI uses the "Vesper" theme and memory use is kept as low as possible.

FishSol v2.1 (`a local copy of FishSol v2.1`) is a **reference only**. No code is copied. We take its proven 1440p coordinates and timed routes and learn from its failures:
- Biomes never worked because it picks the newest `.log`, which can be a Studio or crash log.
- Auto-craft never bought anything, and its plugin is a 0-byte file.
- Its loops are copy-pasted once per resolution.
- It runs a WMI process query every second.

## 2. Environment and constraints

| Item | Value |
|---|---|
| Language | AutoHotkey **v2**, delivered as `.ahk` only (user installs AHK v2) |
| Display | 2560x1440, Roblox fullscreen |
| Roblox | Standard launcher, **no Bloxstrap** |
| Input method | Screen pixels plus keyboard and mouse only. No memory reading or injection. |
| Hotkeys | F1 start, F2 pause/resume, F3 stop |
| Memory target | Under 30 MB idle (art included) |

Verified on the user's machine: `%LOCALAPPDATA%\Roblox\logs\*_Player_*.log` contains `[BloxstrapRPC]` `SetRichPresence` lines even without Bloxstrap. The biome is `data.largeImage.hoverText` (for example `SAND STORM`).

## 3. Architecture

A single process with one scheduler tick (`SetTimer`). Only one task runs at a time. Each task is a module with `CanRun()` and `Run()`, and every step checks the stop/pause flag.

```
VesperMacro/
  Vesper.ahk            entry, hotkeys, scheduler
  lib/
    Config.ahk          load/save settings.ini + data/*.json
    Json.ahk            minimal JSON parse/stringify
    Roblox.ahk          find window (RobloxPlayerBeta.exe via WinExist), focus, fullscreen check
    Input.ahk           click/move/key helpers, timed route player
    Pixel.ahk           PixelGetColor/PixelSearch wrappers with tolerance
    LogWatch.ahk        tail newest *_Player_*.log by byte offset; emits biome/aura/merchant events
    Ocr.ahk             Windows.Media.Ocr on a small region (chat fallback)
    Webhook.ahk         multi-webhook router, embeds, screenshot upload
    Calibrate.ahk       click-once wizard -> data/calibration.json
    tasks/
      Fishing.ahk       cast, bite wait, bar-tracking minigame, failsafes
      Sell.ahk          walk to fisher, sell all/selected
      Craft.ahk         fisher potion buying + Stella cauldron
      Quests.ahk        quest board accept/track/turn-in with filter
      Merchant.ahk      Mari/Jester detection + want-list buying
      Potions.ahk       rare-biome potion use from inventory (safety checks, see 4.6a)
      Clip.ahk          Medal.tv clip hotkey triggers
      Recovery.ahk      rejoin private server, anti-AFK, stuck reset
    ui/
      Theme.ahk         palette, fonts, styled controls
      Dashboard.ahk     tabbed main window
      Overlay.ahk       mini always-on-top status window
  data/
    routes.json         timed walking routes (VIP and non-VIP), ported from FishSol 1440p
    coords.json         fishing/sell coords + pixel colors from FishSol 1440p
    calibration.json    wizard-recorded coords for new features
    quests.json         every quest type and quest, with enabled flags
    merchants.json      Mari and Jester want-lists with quantities
    biomes.json         biome list, rare flags, per-biome potion lists
    potions.json        potion names, locked flags, per-biome/day/run caps
    potion_usage.json   persisted usage counters + processed biome-event keys
  assets/
    vesper_bg.png       darkened, downscaled full-body row over the ocean
    vesper_ref.webp     original reference sheet
  settings.ini          user settings, webhooks, private server link (local only, never logged)
```

### Scheduler priority (highest first)
1. **Rare-biome potions**, triggered by a LogWatch event.
2. **Recovery**, when disconnected or stuck.
3. **Merchant**, when detected.
4. **Craft**, when the "Potion Crafted" notification appears (pixel).
5. **Quests**, on an interval (default 30 min).
6. **Sell**, every N fishing loops (FishSol behavior).
7. **Fishing** is the default task.

A higher-priority event interrupts the current task at its next safe checkpoint. After any task, the macro resets to spawn (Esc, R, Enter) and walks back to fishing.

## 4. Features

### 4.1 Fishing
- Coordinates and colors come from FishSol 1440p: click the rod, wait for the white pixel at the bite indicator, then sample the bar color.
- Minigame: watch the bar strip and click when the bar color leaves the target zone. Optional "advanced" mode uses bar width.
- Fishing failsafe (N s) and pathing failsafe (M s) trigger a reset and re-path.

### 4.2 Selling
- Every N fishing loops it walks the timed route to the fisher, sells all or selected fish, then returns.
- Routes come in VIP and non-VIP versions (setting).

### 4.3 Auto-craft
1. **Start:** walk to the fisher and buy the user-configured potions and quantities (for example Lucky and Speed).
2. **Fish** until the **"Potion Crafted" notification** appears (pixel check, calibrated).
3. **On notification:** stop fishing, walk to the fisher, buy the same amounts again, and return. This repeats because Sol's RNG auto-adds auras but not potions.
4. **Optional Stella cauldron step** (toggle):
   - Walk the route to **Stella's cauldron**. The route ends out of Stella's interaction range so her prompt doesn't capture the key.
   - Press **F** to open the cauldron and pixel-check that the cauldron GUI opened. If Stella's dialog opens instead, close it, step away and retry up to 3 times.
   - Click the **search box**, type the configured potion name, and click the first result.
   - Click **Open Recipe**, then click **Add all ingredients** (a single button).
   - Close the GUI and resume.
- A purchase is verified by a pixel check of the shop UI. If it fails, retry once, then report an error and keep fishing.

### 4.4 Quest board
- The quest board runs every 30 minutes (configurable). The board shows 5 quests, 3 can be active, and a new one arrives every hour.
- Turn in completed quests, accept allowed quests, and skip denied ones. Denied quests are only dismissed (abandoned) when the user opts in (`quests.dismissDisabled = 1`, default 0).
- **Filter:** a checklist of every quest type and every individual quest from `quests.json`, pre-filled from current guides:
  - Player Hunt I–III
  - Aura hunts: Basic, Epic, Unique, Legendary, Mythic
  - Breakthroughs
  - Resonance
  - Delivery I–V
  - Fishing: River Angler, Minnow Rookie, Deep-Sea Hunter, Legendary Fisher
  - Finding a Person
  - Lucky Clover
  - Time of Patience

  The user can edit the list.
- Quest names on the board are read with **OCR** on the board region and matched against the list.

### 4.5 Merchants (Mari and Jester)
- **Detection:**
  1. LogWatch scans for merchant keywords. This is unconfirmed, since the user's log had no merchant lines.
  2. Fallback: OCR a small chat region every few seconds and look for the merchant name or arrival text.
- To keep chat from fading, the mouse hovers over the chat box before each OCR read. It never types or sends anything.
- **Buying:** walk to the merchant and buy items from the per-merchant want-list with quantities, then return.
- Webhook report includes the merchant and what was bought.

### 4.6 Biomes and rare biomes
- LogWatch reads only the newest `*_Player_*.log` from its last byte offset, then parses `largeImage.hoverText`.
- Every biome change goes to the webhook and the in-app log.
- **Rare biomes** (selectable; defaults: Glitched, Dreamspace, Cyberspace, Radiant Forest, Singularity) trigger:
  - A webhook @mention with a screenshot of the Roblox window.
  - A local sound alert.
  - A **per-biome potion list with quantities**. The inventory is opened, each potion is searched and used, and then the inventory is closed.
  - Quests, merchant and crafting pause for the rest of the biome.

### 4.6a Potion safety (never waste potions)
Every potion use passes **all** of these checks. Any failure skips that potion, logs it and sends an Errors webhook, and the run continues without retrying blindly.
1. **Locked tier:** top-tier potions (Transcendent, Heavenly, Oblivion, Godlike, Zeus, Poseidon, Hades, Warp, and any potion added to the locked list) are **locked by default**. Each one must be unlocked individually in the UI, and the unlock dialog states the potion name and caps.
2. **Caps:** each potion has a per-biome max, a per-day max and a lifetime-of-run max. The counters persist in `data/potion_usage.json` across restarts. The per-biome cap is hard: one biome event can never exceed it.
3. **One trigger per biome event:** a biome event is keyed by biome name plus log timestamp. Duplicate RPC lines, restarts or a re-read log can't trigger the same event twice.
4. **Biome re-check:** right before each click, LogWatch must confirm that the rare biome is still the current biome. If it ended or changed, stop immediately.
5. **Identity check (description box, tile scan, amount signature):** the game's selected-item panel shows **no item name** (recon 2026-10-25), so identity comes from the description box:
   - After opening the inventory (Items tab) and searching, OCR reads the names of the first result tiles (tile scan, `Potions.tileScan`, default 6) and keeps only tiles whose name matches exactly (confusable-aware: the game font draws `a` like `o`).
   - Each matching tile is selected with **proof**: before the click the selected item's description must NOT contain the potion's `desc` on two reads (an empty or failed OCR read is UNKNOWN, never "not matching"), and after the click it MUST contain it. More than one proven tile, or none, means no click.
   - Right before each Use click the description box is read again and must contain `desc`. `desc` (data/potions.json) must be unique among ALL in-game potions (e.g. "1 minute of [Quick Roll]"; sibling potions share text).
   - The amount box is checked with a **pixel signature** (calibrated empty box and "1"), because OCR cannot read a lone "1".
   - Any doubt means no click.
6. **Quantity guard:** OCR reads the owned count before using a potion. The macro uses min(configured qty, remaining caps, owned), then re-reads the count after each use to confirm exactly one was consumed. An unexpected drop aborts the potion step.
7. **Single-click use:** one Use click per potion, with a delay and verification between clicks. Never batch-click or hold.
8. **Global kill switch:** F3 and an overlay button stop potion use instantly. A "Dry run" toggle performs every check and logs what *would* be used without clicking.
9. **Audit trail:** every use, and every skip with its reason, goes to the in-app log and the Potions webhook event, with counts before and after.

### 4.6b Clipping (Medal.tv)
- Checks that Medal is running (`medal.exe` via `ProcessExist`) and sends the user-configured Medal **clip hotkey** (set in Settings to match Medal).
- **Triggers** (each toggleable):
  - Rare biome start
  - Rare aura equipped/rolled, from the log's RPC `state` (aura name). The user selects auras in a list, and a rarity threshold is configurable.
    (2026-10-25, user request) Rarity data in `data/auras.json` (name, rarity = 1-in-N, category; file only, no built-in table). Clip when the aura is listed (`[Medal] auras`), its category is in `[Medal] auraAlwaysCategories` (default `Challenged,Challenged+`) or its rarity >= `[Medal] auraMinRarity` (default 100000000). Unknown aura: no clip, logged once. The `clips` webhook states the aura, 1-in-N and why. The calibration capture key default moved F6 -> F9 so F6 is free for the Medal hotkey.
- A clip is sent a few seconds after the event (configurable) so the moment is inside Medal's buffer. A cooldown prevents duplicate clips.
- The webhook message notes that a clip was saved. The clip file itself isn't uploaded.
- If Medal isn't running, log a warning once and skip.

### 4.7 Webhooks
- Multiple webhooks, each with a name, URL, mention ID, an **on/off toggle** and event checkboxes:
  - All biomes
  - Rare biomes
  - Merchant
  - Quests
  - Crafting
  - Errors and recovery
  - Start and stop
  - Potions (use and skip audit)
  - Clips
- Sends are queued so they never block a task. A failed send is retried once.
- URLs are never written to the in-app log or webhook bodies, except the private-server link as a join button if enabled.

### 4.8 Recovery
- **Disconnect:** reopen the private server link if the window is gone or the reconnect screen is shown.
- **Anti-AFK:** a small input every ~15 minutes while otherwise idle.
- **Stuck:** if there's no fishing progress for N minutes, reset to spawn and re-path.

### 4.9 Calibration wizard
- A guided step list: stand at the location, then click the target.
  - Targets: quest board UI, merchant UI, fisher shop buy buttons, Stella cauldron (search, result, Open Recipe, Add all), inventory and potion search, chat region, "Potion Crafted" notification.
- Each step stores a click point plus a sample color.
- Each step can be re-recorded on its own.

## 5. UI

- **Palette:**

  | Role | Color | Hex |
  |---|---|---|
  | Background | Black | `#0D1117` |
  | Panels and borders | Deep navy | `#0B2A5B` |
  | Text | Warm white | `#F7F1E8` |
  | Accents and active | Gold | `#F2A93B` |

  A crescent-moon motif is used.
- **Dashboard tabs:** Run, Fishing, Craft, Quests, Merchants, Biomes & Potions, Webhooks, Calibrate, Settings, Tools, Log.
  - Tools: record walking routes (F7 start/stop, keys are only watched) and dev-only test events (fake rare biome / merchant arrival, refused unless dry run is on, webhooks marked [TEST]).
  - The background is the full-body row over the moonlit ocean, darkened and downscaled.
- **Overlay:** a small always-on-top window showing state, current task, biome, uptime and loop count, with buttons for start, pause and stop.
- **Log panel:** capped at 200 lines.

## 6. Memory and CPU
- One timer and no per-module processes. FishSol's separate biome process and WMI query are removed.
- The log is read incrementally (only new bytes).
- OCR runs only in small regions, and only for the chat fallback and the quest board.
- Pixel checks are single-point where possible.
- The image is loaded once at display size.

## 7. Error handling
- Every task step has a timeout. On timeout: log, send a webhook (errors event), reset to spawn and continue fishing.
- If Roblox isn't found or isn't fullscreen 2560x1440, the macro pauses and shows a clear status.

## 8. Testing
- **Offline:**
  - LogWatch parser against real log lines (biome change, Studio log ignored).
  - JSON and config round-trip.
  - Webhook router event filtering, with a dry-run mode.
- **In game:**
  - Calibrate.
  - Run each task alone: fishing 10 loops, sell, craft cycle, cauldron, quests, merchant with a manual trigger, potions with a forced biome event.
  - Full loop for 30+ minutes.
  - Check RAM in Task Manager.

## 9. Risks
- Game UI, quest names and routes change with updates, so they live in data files and calibration.
- The merchant log signal is unconfirmed, so OCR may be the main path.
- The ported FishSol coordinates and timed routes may be off for the current game version.
- The developers dislike fishing macros, though they aren't reported as bannable. The user accepts the risk.
