# Deadeye

A hunter toolkit for **World of Warcraft: Forever** (interface 16001):

- **Auto Shot bar.** Shows the reload, where you can move freely, and the aim window at the end,
  where you must stand still. It turns red if you move or cast in the aim window, and can play a
  "stop moving" sound.
- **Range indicator.** A color strip on top of the bar: melee, dead zone, Auto Shot range, or too
  far. It also warns you when you're not facing your target, have no line of sight, or haven't
  used Hunter's Mark in combat.
- **Pet panel.** Happiness and the damage bonus or penalty that comes with it, plus health and
  loyalty. Hover it to see diet and training points. It alerts you when your pet needs feeding and
  warns you if you go into a fight without a pet.
- **Feed button** beside the pet panel. Click it to feed your pet. It picks the food from your
  bags, lowest level first among food close to your pet's level, and leaves food that makes you
  well fed alone. Right-click it to skip a food.
- **Delay report.** After a fight, shows how much Auto Shot time you lost to moving or casting.
- **Max camera distance**, if you want to zoom out further.
- **Options window** with a live preview, plus a chat command for every setting.

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
| Bar | Texture (LibSharedMedia ones too), background, border, Auto Shot icon, spark, aim-window line and shading |
| Colors | Reload, aim window, moving or casting, idle, out-of-range opacity, text and warning colors |
| Text, Wording | Font, size, outline, where the label and timer go, decimals, and the wording for each phase and warning |
| Timing & Alerts | When the bar shows, aim window length, latency compensation, range dimming, stop-moving sound, delay report |
| Range (3 pages) | On or off, when it shows, on the bar or anywhere, strip or text, size, Hunter's Mark reminder, colors, wording |
| Pet (3 pages) | On or off, always or only when the pet needs attention, position, width, health and loyalty lines, feed button, skipped food, alerts, sound, font |
| Camera | Max camera distance |

To move frames, use `/deadeye move`, the **Unlock frames** box, or Blizzard's Edit Mode. Each one shows
the bar, range strip and pet panel as blue boxes you can drag. The range strip follows the bar
until you drag it somewhere else. The feed button follows the pet panel, on the side away from the
middle of the screen.

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
- **`C_Spell.IsSpellInRange`** with Auto Shot and your melee abilities gives the range bands. Out
  of combat, `CheckInteractDistance` tells the dead zone from too far. Addons can't get the exact
  distance to an enemy.
- **Hunter's Mark** can be read on the target out of combat. In combat the addon goes by the marks
  you cast, since debuffs are hidden then. If you switch targets mid-fight it can't tell whether the
  old target is still marked, so it reminds you again.
- **`C_PetInfo`** feeds the pet panel. Pet health is passed straight to the bar without being read.
- **The feed button** is Blizzard's `SecureActionButtonTemplate`, set to cast Feed Pet and then use
  the food at its `target-bag` and `target-slot`. `C_PetInfo.CanPetEatItem` says what your pet
  eats, and the item's tooltip says whether a food makes you well fed. The button is anchored to
  the screen rather than to the pet panel, so the panel stays free to change in combat.

## Please check in game

- **Auto Shot timing.** `/deadeye debug` prints each shot's speed and the gap since the last shot.
- **Range strip and warnings.** Facing, line of sight, dead zone or too far in combat, and the
  Hunter's Mark reminder.
- **Pet panel.** Happiness icons, the feed alert, and the "no pet" warning.
- **Feed button.** That a click feeds the food shown, which food it picks, and that a right-click
  skips it.
- **Haste.** If Rapid Fire lands mid-reload, the bar corrects itself on the next shot.

Report problems at the [issue tracker](https://github.com/CakeRepository/Deadeye/issues).
Output from `/deadeye debug` helps.

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
Core.lua                saved variables, module registry, /deadeye commands, secret-value helpers
Media.lua               bar textures, fonts, sounds (+ LibSharedMedia)
Frames.lua              shared drag/lock/Edit Mode handling and positions
Options/Widgets.lua     checkbox, slider, dropdown, color, text box, button
Options/Window.lua      the options window
Options/Slash.lua       /deadeye <setting> <value>, built from the same option lists
Modules/AutoShot.lua    Auto Shot bar, delay report, facing and range warnings
Modules/Range.lua       range strip and Hunter's Mark reminder
Modules/Pet.lua         pet panel and feed button
Modules/Camera.lua      max camera distance
tests/                  mock client and scenario tests
docs/curseforge.md      text for the CurseForge project page
```

A module calls `ns:NewModule(name, defaults)` and returns its option pages from
`GetOptionSections()`. The window and the chat commands are both built from those pages, so a new
setting shows up in both places.

## License

MIT. See [LICENSE](LICENSE).
