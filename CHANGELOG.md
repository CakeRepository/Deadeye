# Changelog

## v0.5.1-beta

- **Pet commands:** your pet panel works as a remote for the calls you make in a hurry.
  - **Click** it to send your pet in, opening with Charge for a boar (Dash or Dive for other
    pets). Click again to call it back, on passive so it stays out, even while it's still running
    in. Sent in again, it gets its stance back.
  - **Right-click** parks it where it stands. **Shift-right-click** uses the game's Move To:
    click the ground where it should wait.
  - **Shift-click** changes its stance, shown at the panel's top right.
  - With no pet out a click casts Call Pet, and with a dead one Revive Pet.
  - The panel lights up when Charge would land.
  - Every command has a key binding (Key Bindings > AddOns > Deadeye), and **Make pet macros**
    on the **Pet: commands** page puts them in your macros, to drag onto your bars. The macros
    hold the commands themselves; the stance macro is passive, shift for defensive, ctrl for
    aggressive.
  - **Duels:** when a duel is asked for, by you or of you, a button above the panel holds your
    pet back, so it doesn't run in when the duel starts.
- **Revive button:** while your pet is dead, a Revive Pet button takes the feed button's place.
  It comes up the moment your pet dies, even in combat. Turn it off on the **Pet: feeding** page.
- **Sound when a fight starts:** a new checkbox on the Aspect, Ammo and Pet alert pages turns off
  just the sound of the alerts a fight can start with (no aspect, low ammo, no pet). At low levels
  the no-aspect one could sound at almost every pull. The chat messages and every other sound
  stay. Thanks to the player who asked.

## v0.5.0-beta

- **Ammo counter** beside the Auto Shot bar: the ammo you have left, yellow when you're running
  low (below 200 by default) and red when you're out. Hover it to see how many minutes of fighting
  it lasts at the rate you shoot. You're warned as you drop below the mark, when you run out, when
  a fight starts short, and when you leave an inn or a city short.
- **Restocking at vendors.** Open a vendor that sells ammo for your weapon or food your pet eats,
  and Deadeye restocks you by itself. It fills your quiver or ammo pouch, and if the vendor has
  better ammo that you can use, it buys that and puts it in your ammo slot. It buys a stack of food
  your pet gets the most happiness from. It spends at most half your money on its own.
- **The restock button** below the vendor window does the same with a click, and its tooltip says
  what it buys and what that costs. Shift-click buys your own ammo instead of better ammo.
  Right-click turns restocking by itself on or off.
- **Out of ammo?** After the fight, the best other ammo you carry goes in your ammo slot.
- **Aspect reminder.** In a fight, the text above the bar warns you while you're in Aspect of the
  Cheetah or the Pack (you get dazed when hit) or have no aspect, and a fight that starts that way
  gets an alert.
- **Casting between shots.** The Auto Shot bar shows where a cast-time shot such as Aimed Shot
  still fits before your next Auto Shot. While you cast, it shows where the cast ends and how much
  it will delay the shot. The delay report says how much of the lost time came from casting.
- **Tranq Shot callout** for hunters who know Tranquilizing Shot: a big "Tranq Shot!" when a boss,
  your target or your focus enrages, and whether your shot removed it. It can tell your group,
  off by default.
- **Growl reminder.** In dungeons and raids, Deadeye reminds you to turn off your pet's Growl,
  which pulls enemies off your tank, and to turn it back on when you're out.
- **Pet food warning** when you leave an inn or a city without food your pet eats.
- **Zoom all the way out:** a button on the Camera page (or `/deadeye camera zoomout`) sets the
  max camera distance and zooms your camera out to it.
- **Fixed:** standing in melee range read as "Dead zone" for hunters whose only melee ability is
  Raptor Strike. Melee range now also comes from Auto Attack's range, the game's own melee range
  check and your melee swings. When none of them can tell, the strip says **Too close** instead of
  guessing.
- The page list in the options window is tighter, to fit the new pages.

## v0.4.0-beta

- **Deadeye speaks your language:** German, Spanish (Spain and Latin America), French, Italian,
  Brazilian Portuguese, Russian, Korean, Simplified and Traditional Chinese, besides English. The
  translations are machine-made first drafts; corrections are very welcome on GitHub.
- Chat commands and setting names stay in English in every language, so `/deadeye width 250`
  works everywhere.
- On Korean and Chinese clients the bar and panels use the game's font, the one that has those
  characters; Russian clients get the Cyrillic versions of the other fonts.
- **Fixed:** the range indicator said "Melee" for targets well inside Auto Shot range. Raptor
  Strike's range check calls far targets in range on Forever; Auto Shot's own range check now
  wins, and a melee ability caught doing that is ignored.
- **Smarter Hunter's Mark reminder:** one mark is enough. Switching targets in a fight no longer
  nags while your mark is on a living enemy in Auto Shot range. The addon follows your mark by its
  aura ID on your target and enemy nameplates, and reminds you when the marked enemy dies, runs out
  of range or the mark runs out.
- The range indicator's font settings moved to its text page, which leaves room for longer text.
- Notes in the options window grow to fit their text.

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
