# CurseForge project page

Created on CurseForge as project **1745019**:
https://www.curseforge.com/wow/addons/deadeye-hunter-auto-shot-timer-range-feed-pet
(visible once a moderator approves the first file). The text below is what was entered, kept here
so the page can be edited later.

**Name:** Deadeye - Hunter Auto Shot Timer, Range & Feed Pet (Forever)

CurseForge search matches words in project titles, so the title carries the words players search
for: hunter, auto shot, timer, range, feed pet, forever.

**Summary:**
Auto Shot reload and aim-window bar, range strip with facing and Hunter's Mark warnings, pet happiness panel and a click-to-feed button for WoW: Forever hunters.

**Category:** Class: Hunter (add Combat and Buffs & Debuffs as other categories if you like)

**License:** MIT License

**Source:** https://github.com/CakeRepository/Deadeye

**Game version for the file:** WoW: Forever 1.60.1 &nbsp;·&nbsp; **Release type:** Beta

---

**Description:**

# Deadeye

A hunter toolkit built for **World of Warcraft: Forever**.

## Auto Shot bar
See exactly when you can move and when you have to stand still.

- **Reload** (orange): move freely.
- **Aim window** (green): the last half second before each shot. Stand still and don't cast.
- **Red**: you're moving or casting in the aim window, so your shot is being held back.
- Optional "stop moving" sound as the aim window starts, or only if you're moving in it.
- Latency compensation, and an out-of-range dim.

## Range strip
A color-coded strip on top of the bar shows which band your target is in: **melee**, **dead zone**,
**Auto Shot range** or **too far**.

The text above it warns you in combat:
- **Face your target**
- **No line of sight**
- **Mark your target**, if your target has no Hunter's Mark

## Pet panel
Happiness, along with the damage bonus or penalty that comes with it, plus health and loyalty.
Hover it to see what your pet eats and its training points. Deadeye tells you when your pet
needs feeding and warns you when a fight starts without it.

## Feed button
Click the button beside the pet panel to feed your pet. It picks the food for you: food close to
your pet's level, lowest level first so your better food lasts. Food that makes you **well fed** is
saved for you. Right-click to skip a food, and hover to see what it will use. It lights up while
your pet isn't happy.

## Delay report
After each fight, see how much Auto Shot time you lost to moving or casting (`/deadeye stats`).

## Camera
Optionally raise the max camera distance (up to 39 yards) to keep an eye on your pet and the pull.

## Make it yours
Type **/deadeye** (or the shortcut **/deye**) for the options window. A live preview runs while it's open. You can change
position, size, vertical or reversed bars, textures (LibSharedMedia supported), borders, the
Auto Shot icon, colors, fonts, text placement, and the wording of every phase.

Every option also works from chat, for example `/deadeye width 260`, `/deadeye texture flat`,
`/deadeye label above` or `/deadeye range show problems`. `/deadeye settings` lists them all.

To move frames, use `/deadeye move`, the **Unlock frames** box, or Blizzard's **Edit Mode**.

## Notes
- Hunters only.
- Built for Forever's addon rules. It uses the game's own swing event, and secret combat values
  are only shown, never computed with.
- This is a **beta**. Please report anything that looks off at
  https://github.com/CakeRepository/Deadeye/issues. Output from `/deadeye debug` helps a lot.
