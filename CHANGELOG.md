# Changelog

## v0.3.0-beta

- **Renamed to Deadeye.** Another addon already uses the name ForeverHunter. The chat command is
  now `/deadeye`, with `/deye` as a shortcut. If you have 0.2.0-beta, delete the old
  `ForeverHunter` folder from `Interface\AddOns`. Its settings don't carry over.
- **Feed button** beside the pet panel: click it to feed your pet. It picks food close to your
  pet's level from your bags, lowest level first so your better food lasts, and saves food that
  makes you well fed for you. Right-click it to skip a food (`/fh pet unskip` to undo). With no
  food your pet eats, a click casts Feed Pet so you can pick one yourself. It lights up while your
  pet isn't happy, and catches up after a fight, since Blizzard locks such buttons in combat.
- New **Pet: feeding** options page with the feed button, the feed alert and skipped food.

## v0.2.0-beta

First public beta for WoW: Forever (1.60.1).

- **Options window** (`/fh`) with a live preview: position, size, vertical or reversed bars,
  textures (including LibSharedMedia), background, border, icon, colors, fonts, text placement and
  the wording of every phase.
- **Every setting from chat**: `/fh <setting> <value>`, `/fh range ...`, `/fh pet ...`,
  `/fh camera ...`, and `/fh settings` to list them.
- **Moving frames**: `/fh move`, the Unlock frames box, or Blizzard's Edit Mode.
- **Range indicator**: a color strip showing melee, dead zone, Auto Shot range or too far. It sits
  on top of the Auto Shot bar by default. In combat, Auto Shot's own "too close" and "out of range"
  errors tell the dead zone from too far.
- **Facing and line of sight warnings**: shown as soon as an attack fails for either reason.
- **Hunter's Mark reminder**: "Mark your target" in combat until your target is marked.
- **Pet panel**: happiness and its damage effect, health, loyalty, diet and training points, with a
  feed alert and a warning when a fight starts without your pet.
- **Delay report**: Auto Shot time lost to moving or casting (`/fh stats`, or after each fight).
- **Stop-moving sound** as the aim window starts.
- **Max camera distance** setting (off unless you turn it on).
- The bar and pet panel now start below your character (their earlier spot is moved
  automatically unless you had moved it yourself).

## v0.1.0

- Auto Shot reload and aim-window bar, driven by Forever's `PLAYER_SWING` event.
