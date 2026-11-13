# Moontide Macro

An AutoHotkey v2 macro for **Sol's RNG** on Roblox. It fishes, sells, buys
potions at the Fisher (and can use Stella's cauldron), works the quest board,
visits Mari and the Jester, and watches the biome. In a rare biome it alerts
you on Discord and can use potions from your inventory, with strict safety
checks.

It only reads screen pixels and the Roblox log, and presses keys and clicks
the mouse like a player. It never reads or changes game memory.

(Originally built around the Vesper theme, so the entry script is still
`Vesper.ahk`. `MoontideMacro.exe` is AutoHotkey v2 itself, renamed: it runs
`MoontideMacro.ahk`, which starts the same macro. Its license is in
`AutoHotkey license.txt`. Some antivirus apps are wary of any AutoHotkey
program; it reads no game memory and sends nothing anywhere you did not set up.)

## Requirements

- Windows, Roblox (standard launcher, no Bloxstrap) **fullscreen**. Tested sizes:
  2560x1440, 1920x1080, 1920x1200, 1680x1050, 1600x900, 1536x864, 1440x900,
  1366x768, 1280x800 and 1280x720. Other 16:9 / 16:10 sizes may work; 5:4
  (1280x1024) and ultrawide (2560x1080, 3440x1440) do not yet.
- **Be careful:** Memory Match works better at some screen sizes than others,
  and minion hunting is still very buggy at every size. Keep an eye on both.
- Nothing to install: the release zip includes `MoontideMacro.exe`. If you
  already have [AutoHotkey v2](https://www.autohotkey.com/), you can run
  `Vesper.ahk` instead.

## Start

1. Download the zip from the latest release and unzip it into its own folder.
2. Double-click `MoontideMacro.exe` (or `Vesper.ahk` with AutoHotkey v2
   installed; use one or the other, not both). The dashboard and a small
   overlay open. The first time, the setup wizard walks you through the basics.
3. Open Roblox fullscreen, join your server, stand at the fishing spot.
4. Press **F1**.

## Updating

The macro can fetch new versions from GitHub Releases. In `settings.ini`:

```
[Update]
repo=owner/name
check=1
auto=0
```

- `repo` is the GitHub repository to follow. **Empty (the default) turns the
  updater off completely.**
- `check=1` looks for a newer release once per start; `auto=0` asks first
  (Home page: "Update available: vX.Y.Z", **Install** or **Later**), `auto=1`
  installs without asking. **Check for updates** on Home checks on demand.
- Installing only happens while the macro is stopped. Your `settings.ini`,
  calibration, routes, quests, merchants, potions, biomes, state files, logs
  and `backup\` are never overwritten. The replaced program files are copied
  to `backup\<old version>\` first; if anything fails they are restored and the
  old version keeps running. Then the macro restarts itself.

Releasing (owner): bump `Brand.Version` in `lib\Brand.ahk`, run
`powershell -NoProfile -File tools\make_release.ps1`, then create a GitHub
release tagged `v<version>` and attach `dist\MoontideMacro-v<version>.zip`.
The script publishes nothing.

## Keys

| Key | What it does |
|---|---|
| **F1** | Start |
| **F2** | Pause / resume |
| **F3** | Stop. Also the potion kill switch: potion use stops before its next click. |
| **F9** | Calibration: capture the point under the mouse (nothing is clicked) |
| **F7** | Route recorder: start / stop recording |

Start, pause and stop can be changed in `settings.ini` `[Hotkeys]` (F1-F24
only). The Medal clip hotkey (Alerts > Clips) must be F4-F24 and must not be any
of the keys above. **F6 is free for Medal.**

The capture key was F6 in older versions. If your `settings.ini` still has
`captureKey=F6` under `[Calibrate]`, F6 stays the capture key and the Medal
hotkey cannot be F6: close Vesper, change that line to `captureKey=F9` (or
delete it), start Vesper again.

## The dashboard, credits and switches

Moontide Macro is made by **Vesper**; the Discord server link is on the
**About** page and in every start message. A short splash shows the moon
and "made by Vesper" at startup (click to skip it), and the window title,
tray tip, first log line and the start message carry the credit too. If the
credits files were edited, a gold "Modified copy" banner shows in the header;
it is only a notice and never stops the macro.

The dashboard groups its pages into hubs in the sidebar, and a hub with
several pages shows them as tabs. The **Animations** switch (Setup > Settings) turns
all fades and motion off (the splash then just shows for a moment).

**Themes** (Setup > Settings > Look): Moontide (navy and gold), Overdrive
(red), Galaxy (blue-violet), Boss (green and gold), Equinox (black and white),
Matrix (orange), Radiant (purple) and Illusionary (electric blue). Each changes
every colour and the background picture (Sol's RNG art). Press **Apply now** while the macro
is stopped, or it shows at the next start.

The sidebar hubs:

- **Home**: Run (status, Start / Pause / Stop, potion dry run, updates) and
  **Stats** (today, this run and the last 7 days).
- **Automate**: Fishing, Crafting, Quests, Merchants, Biome items, Obby &
  Memory, Limbo.
- **Limited**: features that only exist during a game event. **Hunting**
  (Halloween orbs, minions and the Graveyard boss) is here; Sol's RNG removes
  it later in November and this tab goes with it.
- **Alerts**: Biomes, Discord, Clips, **Daily summary**, **Remote**.
- **Setup**: **Check & help**, Calibrate, Routes, **Schedule**, Settings,
  Dev tools.

## Setup wizard

The first time you start the macro a short wizard opens: a check of your PC,
your private server link, a Discord webhook and what to run. Every step can be
skipped (Next with an empty box keeps what you had) and **Skip setup** closes
it for good. Run it again any time from **Setup > Check & help**.

## Check & help

**Check now** looks at Roblox (open, size, fullscreen), Windows display scale
and HDR, the Roblox logs, your private server link, your Discord webhooks,
calibration and apps known to pull focus away from Roblox (Microsoft PC
Manager's floating toolbar does this). It sends no input. `[!]` may cause
trouble, `[X]` will not work, each with what to do.

**Make support zip** writes `logs\support_<date>.zip`: your log, a few recent
screenshots, this check and your settings with webhook links, server links,
the bot token and your Windows user name taken out. Send that zip to whoever
helps you.

## Stats and the daily summary

**Home > Stats** counts fish caught and missed, reel success, fish per hour,
sell trips, biomes and rare biomes, rare auras rolled, rejoins and run time,
for today, for this run and for the last 7 days (kept in `data\stats.json`).

**Alerts > Daily summary**: once a day at the time you pick, one Discord
message with that day's numbers. It goes to the webhooks that have **Stop**
(start / stop messages) ticked. **Send one now** sends today's so far.

## Run schedule

**Setup > Schedule**: the macro starts by itself at the start time (it brings
Roblox to the front first, like pressing F1) and stops at the stop time.
Overnight windows such as 22:00 to 08:00 work; the same start and stop time
means all day. If you stop it yourself inside the window it stays stopped until
the next one. **Stop after** ends any run after that many hours (0 = no
limit).

## Discord remote control

Control the macro from your phone with your own Discord bot (**Alerts >
Remote**):

1. https://discord.com/developers: **New Application**, then **Bot**: **Reset
   Token** and paste the token into the macro. It is stored only in
   `settings.ini`, never shown or logged.
2. On the Bot page turn on **MESSAGE CONTENT INTENT**.
3. **OAuth2 > URL Generator**: tick `bot`, then View Channels, Send Messages,
   Attach Files and Read Message History. Open the link and add the bot to your
   server.
4. Discord **Settings > Advanced > Developer Mode** on. Right-click your channel:
   **Copy Channel ID**. Right-click yourself: **Copy User ID**. Paste both.
5. Save, then **Test connection**.

Commands (only from the user ids you listed): `!status`, `!stats`,
`!screenshot`, `!log`, `!start`, `!stop`, `!pause`, `!resume`, `!help`.

## Roblox updates

When Roblox updates while the macro runs, auto-rejoin waits for the Roblox
launcher (or Bloxstrap / Fishstrap) to finish installing before it counts a
failed join, and logs that Roblox is updating.

## First run checklist (in this order)

### 1. Settings

- **Alerts > Discord** page: add your Discord webhook(s) and tick the events each one
  gets. URLs are stored only in `settings.ini` and never shown or logged.
  Each row has a **Test** button (sends one message to that saved webhook
  only, no pings; the result shows in the page status). Every Start sends one
  "Moontide Macro" embed (a status card: fishing, selling, craft, quests, merchants, potions,
  @everyone, clips, rejoin, route, plus the Discord invite) to every **enabled** webhook, no pings.
- **Setup > Settings** page: **Ping @everyone** on Dreamspace / Glitched / Cyberspace
  (`General.everyonePing`, list in `General.everyoneBiomes`). Only the live
  rare-biome message pings; Dashboard test events never ping.
- **Setup > Settings** page: paste your **private server link** (used to rejoin after
  a disconnect, and as the **Join Server** button under every "Biome
  Started" Discord message; never shown in the log).
- Every biome gets a Discord card when it starts and when it ends (NORMAL
  too); a rare biome's start is the big rare alert only. Tick **biome** on the
  webhook that should get them. "Biome Started" cards (and the rare alert)
  show a square picture of the biome from `assets\biomes\NAME.png` (spaces as
  `_`); put your own PNG there to replace one. If the biome changed while the
  macro was stopped or closed, the next Start sends "Biome Ended" for the old
  one and "Biome Started" for the current one (`data\last_biome.txt` keeps the
  last biome seen). While paused the log is still read, so those changes are
  sent as they happen.
- **Setup > Settings** page: **VIP gamepass routes**. Check it matches whether you
  own VIP. An existing `settings.ini` keeps its old value, so look even if
  you used it before.
- **Automate > Fishing** page: sell every N catches (at least 1), sell all or selected.

`settings.ini` holds your secrets. Do not share it.

### 2. Calibrate

**Playing fullscreen at one of the tested sizes with Windows scale 100%?** A
ready-made calibration for it (`data\presets\calibration_<size>_100.json`) is
loaded on the first start, so you can skip this step and only re-record a step
that misses (Setup > Calibrate > Preset lists them all). Other sizes or scales:
calibrate every step as below.

**Setup > Calibrate** page: pick steps and press **Record selected** (or **Run
all**). For each step, stand where the prompt says, **hover** the target and
press **F9**. Nothing is clicked. Esc cancels. Do the steps by location:

1. **Notifications** (`notify_rect`): the area where in-game notification
   text shows. Easiest: press E at an empty quest board, or let auto craft
   make something. It is read for "no quests" (quest board) and "crafted"
   (auto craft re-buys from the Fisher).
2. **Fisher shop** (where you sell): talk to Captain Flarg, then
   `fisher_open_shop` (his two buttons are Sell Fish and Open Shop: hover
   **Open Shop**; the macro only clicks it after reading "shop" on it),
   `fisher_item_<potion>` (the potion's tile in the shop) for each potion you
   buy, `fisher_buy_button` (the Buy button, the same for every potion),
   `fisher_qty`, `fisher_confirm`, `fisher_purchase_close` (closes the
   purchase window, which stays open after buying), `fisher_shop_close` (the
   shop's X).
3. **Inventory** (anywhere), exactly in this order:
   `inv_open`, `inv_items_tab` (the inventory opens on Gears; hover the
   Items tab), `inv_search`, `inv_tile1_rect`, `inv_tile2_rect`,
   `inv_count_rect`, `inv_use` (hover only, never press it),
   `inv_desc_rect`, then **`inv_amount_empty` BEFORE `inv_amount_one`**
   (empty the amount box yourself and mark its inside; then type 1 into it
   and just press F9: the same box is reused).
4. **Stella's cauldron** (only if you use it): `cauldron_gui` (a box around
   the "Stella's Workshop" title), `cauldron_search`, `cauldron_result` (a
   box around the FIRST result card: its name must be your recipe before it
   is clicked), `cauldron_open_recipe`, `cauldron_add_all`, `cauldron_close`,
   `stella_dialog` (a box around her name "Stella" in the dialog that shows
   when you walk into her; Esc is only pressed when that name is read).
5. **Quest board** (open it): `quest_board_rect` (the quest text),
   `quest_accept` (Claim Rewards shows in the same spot; the macro reads
   the word on the button), `quest_dismiss`, `quest_close` (the exit
   button), `quest_next` (the > arrow beside the board). Quests do not run
   until the text area and the exit button are recorded. The board shows
   one quest at a time: the macro reads each one (title + objectives),
   accepts / claims / dismisses it, presses > after an Accept or a skip
   (Dismiss moves on by itself) and stops when it is back at a quest it
   already handled.
6. **Chat**: `chat_rect` (merchant detection).

**Limbo (Eden)**: Automate > Limbo > "Wait in Limbo for Eden instead of
fishing". With it on, fishing, selling, crafting, quests, merchants and biome
items stop; biome webhooks, clips and rare-biome potions stay on. The macro
uses your **Portable Crack** (inventory steps), turns the camera top-down
(right mouse held, mouse moved down, keeping the respawn's camera angle),
walks the `limbo_eden` route, then presses E every few seconds and clicks
**Contract with it** where it reads that text (no calibration; you need a
Void Heart plus a Darklight Core, Orb and Shard). Eden spawns 1 in 50,000
every 2 minutes. When a rare biome starts it rejoins your private server
(back to Sol's Island) so the potions run, and uses the crack again once the
rare biome is over. In Limbo nothing else runs (buffs and the island are out
of reach); start the macro on Sol's Island. THE LIMBO has no working reset:
to record `limbo_eden` (Setup > Routes), stand where the Portable Crack puts you and
press Record: the camera is re-aimed (Aura Collections) and turned top-down,
then walk to Eden's spot on the last island. The route is walked once, right
after the crack.

The capture key is **F4** (F9 opens Roblox's developer console). The two
routes (`quest_board`, `cauldron`) come recorded by the creator; **Setup > Routes >
Reset** puts that recording back if yours stops working. The **About** page
has the creator, a message and the Discord server.

Merchants need no calibration: the macro uses the Merchant Teleporter, talks
(E), clicks **Open**, finds each item on the **Automate > Merchants** page by its name
in the shop's tab row, types the amount (at most the "Stock Left"), clicks
**Purchase** and checks the "You purchased ..." notice. The positions come
from a recording of Mari's shop at 2560x1440.

There is no Reconnect button in game: when Roblox shows its disconnect
screen ("Disconnected", "Error Code", "kicked"), the macro closes Roblox and
opens your private server link again (needs the link in Setup > Settings).

A step that is not calibrated is skipped (logged once, errors webhook).
Coordinates are never guessed.

### 3. Record routes

**VIP note:** every walk that comes with the macro (sell, quest board, obby,
Memory Match and the others) was recorded with Sol's RNG **VIP gamepass**,
which walks faster. Without VIP your character is slower and those walks fall
short: turn off **VIP gamepass routes** (Setup > Settings) and record your own
walks here.

**Your own sell walks:** record `sell_to_fisher` (respawn, walk to Captain
Flarg, stop before pressing E) and `fisher_to_fishing` (stand at Captain
Flarg with his dialog closed, walk to the fishing spot). Once recorded, the
sell trip uses them instead of the shipped walk.

The quest board and the cauldron need walking routes. Record them on the
**Setup > Routes** page (Record stops a running macro first):

1. Press **Record** next to the route. With Roblox open and fullscreen, the
   macro respawns you itself, the same way it does before playing a route
   (this also resets the camera), so recording and playback start
   identically. A small box at the top left shows what the recorder is
   doing.
2. Click back into Roblox if needed.
3. Press **F7**, walk with **W A S D** / **Space**, turn the camera by
   holding the **right mouse button** and dragging (or the arrow keys),
   zoom with the **mouse wheel** (or I / O), press **F7** again to save.
   **Esc** cancels. Max 3 minutes. Every route starts with a respawn, which
   resets the camera, so recorded camera turns replay the same way.
4. Press **Test** next to the route: the macro respawns you, walks it and
   presses E / F. If the board / cauldron opens, the route works.

| Route | From | To |
|---|---|---|
| `quest_board` | spawn | in front of the board (the macro presses E) |
| `cauldron` | spawn | near the cauldron but OUT of Stella's range (the macro presses F) |

No other routes: after the cauldron the macro clicks out of it and respawns
(fishing then walks back by itself), and merchants are reached with the
**Merchant Teleporter** item from your inventory (it needs the inventory
calibration steps; it only clicks Use after reading "teleporter" on the tile
and "teleport"/"merchant" in the description).

You can press the interaction key at the end out of habit: a final E / F
is dropped on save, because the macro presses it. The recorder only
watches your keys; it never presses anything. You can also run
`tools\record_route.ahk` (restart the macro afterwards).

### 4. Potions

Potion use is the risky part, so it is off until you set it up.

1. **Dry run stays ON** (Home or Alerts > Biomes) until
   everything below is verified. In dry run every check runs, but **Use is
   never clicked**. Webhooks say `[DRY RUN] Potion would use ...`.
2. **Add potions to rare biomes** on the **Alerts > Biomes** page: pick the
   biome (GLITCHED is the one the test event fakes), pick the potion, set
   qty, Add, Save.
3. **Unlock** a potion (Alerts > Biomes) only while the macro is
   **stopped**. Top-tier potions are locked by default; each unlock shows
   the potion and its caps. Lucky, Speed, Fortune I and Haste I ship
   unlocked.
4. **Fill in `desc`** for each potion in `data\potions.json`. The game shows
   no potion name next to Use, so it identifies the selected potion by
   its **description text**. To find it: with dry run on and the macro
   running, send a fake rare biome (Setup > Dev tools, step 5). For a potion
   without `desc` the log shows
   `... no_desc ... description reads: '...'`. Copy a part that is **unique
   among ALL in-game potions**, e.g. `1 minute of [Quick Roll]` for Speed
   Potion (Speed Potion L also says `[Quick Roll]`). Restart the macro after
   editing the file.
5. **Test events** (Setup > Dev tools, needs dry run ON and the macro running):
   "Fake GLITCHED biome" runs the full potion dry run; "Fake Mari arrival"
   runs a merchant visit. Their webhooks are marked `[TEST]`.
6. Only when the dry-run reports pick the right potion every time, turn dry
   run off.

## Biome items

**Automate > Biome items** page: tick **Use biome items** and the items you own.

| Item | Cooldown | Notes |
|---|---|---|
| Biome Randomizer | 35 min | the crafted, reusable one |
| Strange Controller | 20 min | |
| Biome Selector | 60 min | spends one **Drive** per use; record `selector_drive` (the Drive to pick) and `selector_confirm` |

- Used only in a normal biome (Normal, Windy, Rainy, Snowy, Sand Storm, Hell,
  Starfall, Corruption, Lost Forest, Heaven) that you have **not** marked rare
  (Alerts > Biomes page). Event biomes (Pumpkin Moon, Graveyard, Blood Rain...)
  and biomes not in `data\biomes.json` are never changed away.
- One item per 20 minutes (the game's server cooldown).
- The **One-time Biome Randomizer is never used**: a tile or description that
  says one-time / single use / "used once" is refused, and when it is the first
  search result the second tile is checked instead. The Randomizer is only used
  when its description names the reusable one (its cooldown wording) and reads
  the same twice; an empty or cut-off description is refused.
- Last-use times are kept in `data\biome_items_state.json`, so a restart keeps
  the cooldowns.
- Needs the inventory calibration steps.

## Obby and Memory Match

**Automate > Obby & Memory** page, two panels.

**Obby** (the Basic Blessing): tick **Run the obby**, set **Every** (1 to 120
minutes, default 10) and **Retries** (0 to 3 extra tries after a failed run,
default 1).

Each run equips the **Sailor** aura first (Sailor walks on water, so the
route skips the jumps), and afterwards equips the aura you had on again (or
unequips Sailor if you had none). It only ever clicks a button that reads
Equip / Unequip, never Delete.

1. Setup > Calibrate: the aura storage steps `aura_open`, `aura_search`,
   `aura_tile_rect`, `aura_equip`, `aura_close` (the obby does not run
   without them).
2. Setup > Routes: equip Sailor yourself, then record the `obby` route, from a
   respawn to the star at the end of the obby.
3. Setup > Calibrate: `buff_expand` (the button that expands the buff list) and
   `obby_blessing` (touch the star, expand the buffs, hover the Basic Blessing
   icon). Without them the obby still runs, but the blessing is not checked.
4. Reports: the `obby` event (Discord > events) says the blessing was claimed,
   or that the run was unchecked. A failed run goes to the `errors` event.

**Memory Match** (20 tiles, 10 turns, every 12 hours): plays the board and
keeps the best pairs.

1. Setup > Routes: record the `memory_match` route, from a respawn to the
   board.
2. Tick **Play Memory Match**. It presses E at the board, and clicks Start
   only when the button says Start Memory Match. When it says "Available
   after 11h 59m Left" it waits exactly that long (the page shows the next try).
3. Tiles show an icon and an amount but no name, so pairs are found by
   comparing the tiles' pictures; the narrowest amounts (x1: Godlike,
   Heavenly, Godly, Bound, Void Coin, Rune) are claimed first, coins last. It
   waits for every flip, flip-back and match animation before the next click,
   and clicks Close after the last chance.
4. Reports: the `memorymatch` event lists the pairs won, best first, or says
   no pairs matched. A board that will not open goes to the `errors` event.

## Medal clips

Alerts > Clips, **Medal clips** (needs Medal running). Vesper taps your Medal
clip hotkey a few seconds after a rare biome or a rare aura. Set the same
key in Medal; **F6** works (it is no longer the capture key).

With **Clip on rare aura** ticked, an aura you roll is clipped when any of
these is true:

- it is in **Always clip auras** (comma list of names),
- its class is in **Always clip classes** (default `Challenged,Challenged+`),
- its odds are at least **1 in** the number you set (default `100,000,000`;
  type `100m`, `1b` or `1,000,000,000`; `0` turns this rule off).

Odds and classes come from `data\auras.json` (sourced from the Sol's RNG
wiki, see its `_source`). An aura that is not in that file is never clipped
by rarity; the log says `unknown aura <name>` once. Add it to the file (name
exactly as the game shows it, `rarity` = the N in 1 in N, `category`), or
add an `aliases` list to an entry if the game spells it differently. Restart
Vesper after editing. The `clips` webhook names the aura, its odds and why
it was clipped.

## Safety

- **F3** stops everything, including potion use, at once.
- A potion is **never** used when it is locked, when a cap is reached
  (per biome, per day, per run; counted in `data\potion_usage.json`), when
  the same biome event was already handled, when the rare biome ended, when
  its tile name or description does not match, when the amount box does not
  show exactly 1, or when the count cannot be read twice the same. Any doubt
  means no click. Every use and skip goes to the log and the Potions webhook.
- One Use click at a time; the count must drop by exactly 1 or all potion
  use stops.
- Dry run is on by default. Test events are refused unless dry run is on.
- Quests are never abandoned unless you tick "Dismiss unticked quests"
  (Automate > Quests page).
- Fisher purchases are capped at 999 per potion per visit.

## Troubleshooting

| You see | Do this |
|---|---|
| Paused: **Not fullscreen** | Make Roblox fullscreen (F11), press **F2**. |
| Paused: **Roblox lost focus** | You alt-tabbed. Click into Roblox, press **F2**. The log says which app was in front; Microsoft PC Manager's toolbar takes focus by itself: close PC Manager or turn its toolbar off. |
| Something does not work and you need help | **Setup > Check & help**: **Check now**, then **Make support zip** and send the zip. |
| Paused: **Roblox not found** | Open Roblox. With a private server link set, it rejoins by itself. |
| Paused: **Scheduler error** | Read the log line, fix the cause, press **F2**. |
| Log: `quests: the board did not open` | Press **Test** next to quest_board (Setup > Routes). If it walks wrong, record the route again. |
| Log: `the board has no quests right now` | Normal: the game said the board is empty. |
| Potions skipped: `uncalibrated` | Record the inventory calibration steps (all 10). |
| Potions skipped: `no_desc` / `select_unverified` | Fill in / fix `desc` in `data\potions.json` (unique text). |
| "route 'x' not found" | Record that route on the Setup > Routes page. |
| Clip hotkey not saved | Pick an F4-F24 key that is not F1-F3, F7 or the capture key (F9). F6 refused? See "Keys": your `settings.ini` still has `captureKey=F6`. |
| Log: `unknown aura <name>` | That aura is not in `data\auras.json`, so it is never clipped by rarity. Add it (name, rarity, category) or list it in **Always clip auras**. |

The **Log** page shows the newest 200 lines; links and webhook URLs are
always hidden.
