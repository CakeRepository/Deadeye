# Deadeye

A hunter toolkit for **World of Warcraft: Forever** (interface 16001):

- **Auto Shot bar.** Shows the reload, where you can move freely, and the aim window at the end,
  where you must stand still. It turns red if you move or cast in the aim window, and can play a
  "stop moving" sound. It also shows where a cast-time shot such as Aimed Shot still fits before
  your next Auto Shot, and how much a cast will delay it.
- **Range indicator.** A color strip on top of the bar: melee, dead zone, Auto Shot range, or too
  far. It also warns you when you're not facing your target, have no line of sight, or your
  Hunter's Mark isn't on an enemy you can shoot.
- **Ammo and restocking.** An ammo counter beside the bar, with how many minutes of fighting your
  ammo lasts and warnings before you run out or leave town short. At vendors, Deadeye restocks you
  by itself: it fills your quiver, switches to better ammo you can use, and buys food your pet
  eats. When one kind of ammo runs out, the next best you carry goes in your ammo slot.
- **Aspect reminder.** Warns you in a fight while you're in Aspect of the Cheetah or the Pack
  (you get dazed when hit) or have no aspect at all.
- **Pet panel.** Happiness and the damage bonus or penalty that comes with it, plus health and
  loyalty. Hover it to see diet and training points. It alerts you when your pet needs feeding and
  warns you if you go into a fight without a pet, or leave town without food it eats. In dungeons
  and raids it reminds you to turn off Growl, which pulls enemies off your tank.
- **Feed button** beside the pet panel. Click it to feed your pet. It picks the food from your
  bags, lowest level first among food close to your pet's level, and leaves food that makes you
  well fed alone. Right-click it to skip a food.
- **Tranq Shot callout.** For hunters with Tranquilizing Shot: a big "Tranq Shot!" when a boss
  or your target enrages, and whether your shot removed it.
- **Delay report.** After a fight, shows how much Auto Shot time you lost to moving or casting.
- **Max camera distance**, if you want to zoom out further, and a button that zooms all the way out.
- **Options window** with a live preview, plus a chat command for every setting.
- **In your game's language:** English, Deutsch, Español, Français, Italiano, Português (Brasil),
  Русский, 한국어, 简体中文 and 繁體中文.

## Install

Get it from [CurseForge](https://www.curseforge.com/wow/addons/deadeye-hunter-auto-shot-timer-range-feed-pet), or download `Deadeye-<version>.zip` from the
[GitHub releases](https://github.com/CakeRepository/Deadeye/releases) and unzip it into the
Forever client's `Interface\AddOns` folder. To find that folder, select WoW: Forever in the
Battle.net app, open the gear menu and choose **Show in Explorer**. Then type `/deadeye` (or the
shortcut `/deye`) on a hunter.

Deadeye was called ForeverHunter up to 0.2.0-beta. If you have that version, delete its
`ForeverHunter` folder from `Interface\AddOns`.

## Setting it up

`/deadeye` opens the options window. While it's open, a fake Auto Shot loops so you can see each
change immediately.

| Page | What you can change |
|---|---|
| Position & Size | Drag to move or type exact X/Y offsets, width, height, scale, horizontal or vertical, fill direction |
| Bar | Texture (LibSharedMedia ones too), background, border, Auto Shot icon, spark, aim-window line and shading, casting between shots |
| Colors | Reload, aim window, moving or casting, idle, out-of-range opacity, text and warning colors |
| Text, Wording | Font, size, outline, where the label and timer go, decimals, and the wording for each phase and warning |
| Timing & Alerts | When the bar shows, aim window length, latency compensation, range dimming, stop-moving sound, delay report |
| Range (3 pages) | On or off, when it shows, on the bar or anywhere, strip or text, size, Hunter's Mark reminder, colors, wording and font |
| Ammo | Counter on or off, always or only when low, beside the bar or anywhere, the low mark, warnings, swapping ammo, the restock button, restocking by itself and its spending limit, better ammo, stacks to carry without a quiver |
| Aspect | The aspect reminder and each of its warnings, the alert at the start of a fight, sound and color |
| Pet (3 pages) | On or off, always or only when the pet needs attention, position, width, health and loyalty lines, feed button, skipped food, buying pet food, alerts, Growl reminders, sound, font |
| Tranq Shot | (once you know Tranquilizing Shot) the callout, nameplates, announcing in group chat, position, text, sound |
| Camera | Max camera distance, and a button that zooms all the way out |

To move frames, use `/deadeye move`, the **Unlock frames** box, or Blizzard's Edit Mode. Each one shows
the bar, range strip and pet panel as blue boxes you can drag. The range strip follows the bar
until you drag it somewhere else. The feed button follows the pet panel, on the side away from the
middle of the screen.

### Ammo and restocking

- **The counter** shows how much of the ammo in your ammo slot you carry. It turns yellow below
  the low mark (200 by default) and red when you're out. Hover it to see how many minutes of
  fighting that lasts at the rate you shoot.
- **Warnings** come as you drop below the mark, when you run out, when a fight starts short of
  ammo or with an empty ammo slot, and when you leave an inn or a city short.
- **Restocking at vendors.** When you open a vendor that sells ammo for your weapon or food your
  pet eats, Deadeye restocks you by itself, spending at most half your money (change that on the
  **Ammo** page). It says so the first time.
  - It fills your quiver or ammo pouch with the ammo in your ammo slot. If the vendor has better
    ammo that you can use, Sharp Arrows instead of Rough Arrows say, it buys that and puts it in
    your ammo slot.
  - It buys a stack of the food your pet gets the most happiness from (close to its level).
  - Without a quiver or ammo pouch, it buys up to 4 stacks of ammo in all.
- **The button** below the vendor window does the same with a click: **Restock**, **Fill quiver**,
  **Upgrade ammo**, **Buy pet food** and so on. Hover it to see what it will buy, what that costs,
  and why it can't buy more. Shift-click buys your own ammo instead of better ammo.
  **Right-click** turns restocking by itself on or off.
- **Out of ammo:** after the fight, the best other ammo you carry goes in your ammo slot.
- A vendor's quiver gets a tip when you have none: quivers and ammo pouches make you shoot faster.

### Casting between shots

Cast-time shots like Aimed Shot hold back your Auto Shot if they run into the aim window. The bar
shows a stretch after each shot where you can start the cast and still finish in time. If it
can't fit, a line marks the start of the bar and a number shows the least the cast will cost.
While you cast, a line shows where the cast ends. Any part that runs into the aim window turns
red, with "+0.4" for the delay. The delay report says how much of the lost time came from casting.
Turn each part on or off on the **Bar** page.

### Tranq Shot

For hunters who know Tranquilizing Shot. When a boss, your target or your focus gets an enrage, a
big "Tranq Shot!" appears near the top of the screen, with a sound. Your shot clears it. Then it
tells you if the enrage came off ("Enrage removed!") or stayed ("Still enraged!"). You can also
watch enemy nameplates. It can tell your party or raid how your shot went: that's off by default,
and the game blocks it in boss fights. In combat the game hides what kind of buff an enemy gains,
so a magic buff a priest could purge can set it off too. The buff's name and icon under the
callout show which it is.

### Feed button

- **Click** feeds your pet the food the button shows. It casts Feed Pet and then uses that food.
- **Which food:** food your pet eats that is close to its level (Feed Pet gives the most happiness
  for that), lowest level first so your better food lasts, then the smallest stack. Food that makes
  you *well fed* is saved for you. Hover the button to see the food, how many you have, and
  anything it is leaving alone.
- **Right-click** skips the shown food from now on. `/deadeye pet unskip`, or the button on the
  **Pet: feeding** page, lets it use skipped food again.
- With no food your pet eats, a click casts Feed Pet so you can pick a food in your bags yourself.
- It lights up yellow while your pet isn't happy.
- Blizzard doesn't let addons move, show or change a button that casts spells during a fight, so
  the button catches up when the fight ends.

## Chat commands

Every setting in the window also works from chat:

```text
/deadeye <setting> <value>           Auto Shot bar, e.g. /deadeye width 260 or /deadeye label above
/deadeye range <setting> <value>     range indicator, e.g. /deadeye range show problems
/deadeye pet <setting> <value>       pet panel, e.g. /deadeye pet feedbutton off
/deadeye ammo <setting> <value>      ammo counter and restocking, e.g. /deadeye ammo autobuy off
/deadeye aspect <setting> <value>    aspect reminder, e.g. /deadeye aspect none off
/deadeye tranq <setting> <value>     Tranq Shot callout, e.g. /deadeye tranq announce on
/deadeye camera <setting> <value>    camera, e.g. /deadeye camera zoom 2.6
/deadeye <setting>                   shows the current value and what it accepts
/deadeye settings [range|pet|camera] lists every setting with its value
```

`/deye` is a shortcut for `/deadeye`: `/deye width 260` does the same thing.

Values can be `on`, `off` or `toggle`, numbers, a choice name (the start of a word is enough,
such as `/deadeye outline thick`), or colors such as `ff8800`, `#ff8800cc` or `255 136 0`.

Other commands:

- `/deadeye move` unlocks or locks all frames.
- `/deadeye test` loops a fake Auto Shot.
- `/deadeye stats` shows the last fight's Auto Shot delays.
- `/deadeye pet unskip` lets the feed button use food you skipped again.
- `/deadeye camera zoomout` sets the max camera distance and zooms all the way out.
- `/deadeye debug` logs every shot.
- `/deadeye reset` resets all settings.
- `/deadeye help` lists all commands.

You can also use the minimap addon button. Left-click opens the options; right-click unlocks or
locks the frames.

## How it works

Forever runs Classic hunter rules on the modern client, with Midnight's addon restrictions. The
combat log is closed to addons. In combat, weapon speed, health and target debuffs come back as
"secret" values that addons can't read. So Deadeye uses only what stays readable:

- **`PLAYER_SWING`** fires on every Auto Shot with your current hasted speed. It drives the bar.
- **`UNIT_SPELLCAST_FAILED_QUIET`** for Auto Shot means the shot was due but you were moving.
- **`UI_ERROR_MESSAGE`** gives the reason behind failed attacks: wrong facing, no line of sight,
  too close or too far.
- **`C_Spell.IsSpellInRange`** with Auto Shot and your melee abilities gives the range bands. Auto
  Shot's own check wins: anything it can reach is past melee range. Melee range comes from the
  game's swing timer (`C_SwingTimer.IsTargetWithinSwingRange`, which answered nothing on the betas
  tested), then Wing Clip, Mongoose Bite, Auto Attack and Raptor Strike. A melee ability whose
  check calls a far target "in range" (Raptor Strike does on Forever) is ignored from then on. In
  combat, a melee swing that just landed (`PLAYER_SWING`) also proves melee range. When nothing can
  tell melee range from the dead zone, the strip says **Too close** and lights both bands. Out of
  combat, `CheckInteractDistance` tells the dead zone from too far. Addons can't get the exact
  distance to an enemy.
- **Hunter's Mark.** You can only have one out, so the reminder asks whether your mark is on an
  enemy you can shoot, not whether your target is marked. Out of combat the mark is read on the
  target. In combat aura details are hidden, but aura instance IDs aren't: the addon notes the ID
  your mark gets when you cast it (the one new debuff of yours on the target) and looks for it on
  your target and on enemy nameplates. That shows whether the marked enemy is alive and in Auto
  Shot range. With enemy nameplates hidden, a cast mark is trusted for its two minutes. If the
  client lets addons read Hunter's Mark in combat (`C_Secrets.ShouldSpellAuraBeSecret`), it's read
  directly.
- **Ammo.** `GetInventoryItemCount` on the ammo slot counts that ammo in all your bags. A bag's
  family from `C_Container.GetContainerNumFreeSlots` says whether it's a quiver (arrows) or an ammo
  pouch (bullets). Vendors sell ammo in batches of 200: restocking calls `BuyMerchantItem` with one
  stack at a time, a moment apart, like buying several stacks in the game's own vendor window.
  `C_Item.EquipItemByName` puts new ammo in the ammo slot, out of combat only. Pet food follows the
  feed button's rules (`C_PetInfo.CanPetEatItem` and the pet's level).
- **Casting between shots.** Your own casts stay readable in combat: `UnitCastingInfo` gives where
  a cast ends, and `C_Spell.GetSpellInfo` a spell's cast time.
- **Tranq Shot.** Enemy buffs' details are secret in combat, but their aura instance IDs aren't.
  A new buff that `HELPFUL|RAID_PLAYER_DISPELLABLE` lists on an enemy you're fighting sets off the
  callout. Known frenzies the game flags as readable are found by spell ID. Boss emotes can't be
  read in instances, so they aren't used.
- **Aspects.** Out of combat your buffs are read directly. In combat aura details can be hidden,
  so the aspect is followed through your own casts and through its aura instance ID, which stays a
  plain number in combat: when that ID leaves your buffs, the aspect is gone.
- **`C_PetInfo`** feeds the pet panel. Pet health is passed straight to the bar without being read.
- **The feed button** is Blizzard's `SecureActionButtonTemplate`, set to cast Feed Pet and then use
  the food at its `target-bag` and `target-slot`. `C_PetInfo.CanPetEatItem` says what your pet
  eats, and the item's tooltip says whether a food makes you well fed. The button is anchored to
  the screen rather than to the pet panel, so the panel stays free to change in combat.

## Please check in game

- **Auto Shot timing.** `/deadeye debug` prints each shot's speed and the gap since the last shot.
- **Range strip and warnings.** Facing, line of sight, dead zone or too far in combat, and the
  Hunter's Mark reminder. Melee range below level 12, where Raptor Strike is your only melee
  ability: `/deadeye debug` says when a melee check is ignored.
- **Ammo.** The count, the low and out-of-ammo warnings, and the vendor button: what it buys, that
  a full quiver stops it, and refilling by itself.
- **Aspect reminder.** Switching or cancelling an aspect in combat.
- **Restocking.** Better ammo going into your ammo slot, pet food, and the spending limit.
- **Casting between shots.** `/deadeye debug` prints each cast's real and listed time. Check
  whether a cast resets the Auto Shot timer and whether haste changes Aimed Shot's cast time.
- **Tranq Shot.** Whether a frenzy in combat sets off the callout, and with which name and icon.
- **Growl reminder.** Going into a dungeon with Growl's autocast on.
- **Pet panel.** Happiness icons, the feed alert, and the "no pet" warning.
- **Feed button.** That a click feeds the food shown, which food it picks, and that a right-click
  skips it.
- **Haste.** If Rapid Fire lands mid-reload, the bar corrects itself on the next shot.

Report problems at the [issue tracker](https://github.com/CakeRepository/Deadeye/issues).
Output from `/deadeye debug` helps.

## Languages

Deadeye follows your game client's language. The translations are machine-made first drafts, so
native speakers will find things to improve: please open an issue, or edit
`Locales/<language>.lua` and check it with `python tests/check_locale.py deDE` (or your locale's
code). Each line there is `L["English text"] = "translation"`. Keep the `%s` and `%d` placeholders
in the same order, and keep chat commands such as `/deadeye pet unskip` in English.

Chat commands and setting names stay in English in every language, so `/deadeye width 250` works
everywhere. On Korean and Chinese clients the bar uses the game's own font, the one that has those
characters. Russian clients get the Cyrillic versions of the other fonts.

## Development

The addon files sit at the repository root. `tests/` holds a mock Forever client and scenario
tests; they aren't part of the release zip. The tests need Lua 5.1, the version WoW uses:

```bash
pip install lupa
python tests/run_tests.py
```

`lua5.1 tests/run.lua` also works if you have a standalone Lua 5.1.

Releases: push a tag such as `v0.3.1-beta` and the
[BigWigs packager](https://github.com/BigWigsMods/packager) workflow builds the zip and creates a
GitHub release. A tag with "beta" or "alpha" in it is marked that way. It also uploads the zip to
the CurseForge project (ID 1745019, set in `Deadeye.toc` as `## X-Curse-Project-ID`) when the
repository has a CurseForge API token as the secret `CF_API_TOKEN`.

```text
Deadeye.toc             load order, saved variables, addon-menu hooks
Core.lua                saved variables, module registry, /deadeye commands, translations (L)
Locales/*.lua           one translation per language (esES also covers esMX)
Media.lua               bar textures, fonts, sounds (+ LibSharedMedia)
Frames.lua              shared drag/lock/Edit Mode handling and positions
Options/Widgets.lua     checkbox, slider, dropdown, color, text box, button
Options/Window.lua      the options window
Options/Slash.lua       /deadeye <setting> <value>, built from the same option lists
Modules/AutoShot.lua    Auto Shot bar, delay report, facing and range warnings
Modules/Range.lua       range strip and Hunter's Mark reminder
Modules/Ammo.lua        ammo counter, warnings and forecast, restocking at vendors
Modules/Aspect.lua      aspect reminder
Modules/Pet.lua         pet panel, feed button, pet food and Growl reminders
Modules/Tranq.lua       Tranq Shot callout
Modules/Camera.lua      max camera distance
tests/                  mock client and scenario tests (tests/mocks/: mocks for newer features)
docs/screenshots/       screenshots for the CurseForge page
docs/curseforge.md      text for the CurseForge project page
```

A module calls `ns:NewModule(name, defaults)` and returns its option pages from
`GetOptionSections()`. The window and the chat commands are both built from those pages, so a new
setting shows up in both places.

Text the player sees goes through `L["English text"]`, written as a whole sentence with `%s`
placeholders, never glued together from pieces. The tests fail until every language file
translates every such text, keeping its placeholders and commands.

## License

MIT. See [LICENSE](LICENSE).
