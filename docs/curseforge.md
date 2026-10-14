# CurseForge project page

Paste these into the CurseForge project form.

**Name:** ForeverHunter

**Summary:**
Auto Shot reload and aim-window bar, range strip with facing and Hunter's Mark warnings, and pet happiness panel for WoW: Forever hunters.

**Category:** Class: Hunter (add Combat and Buffs & Debuffs as other categories if you like)

**License:** MIT License

**Source:** https://github.com/CakeRepository/ForeverHunter

**Game version for the file:** WoW: Forever 1.60.1 &nbsp;·&nbsp; **Release type:** Beta

---

**Description:**

# ForeverHunter

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
Hover it to see what your pet eats and its training points. ForeverHunter tells you when your pet
needs feeding and warns you when a fight starts without it.

## Delay report
After each fight, see how much Auto Shot time you lost to moving or casting (`/fh stats`).

## Camera
Optionally raise the max camera distance (up to 39 yards) to keep an eye on your pet and the pull.

## Make it yours
Type **/fh** for the options window. A live preview runs while it's open. You can change
position, size, vertical or reversed bars, textures (LibSharedMedia supported), borders, the
Auto Shot icon, colors, fonts, text placement, and the wording of every phase.

Every option also works from chat, for example `/fh width 260`, `/fh texture flat`,
`/fh label above` or `/fh range show problems`. `/fh settings` lists them all.

To move frames, use `/fh move`, the **Unlock frames** box, or Blizzard's **Edit Mode**.

## Notes
- Hunters only.
- Built for Forever's addon rules. It uses the game's own swing event, and secret combat values
  are only shown, never computed with.
- This is a **beta**. Please report anything that looks off at
  https://github.com/CakeRepository/ForeverHunter/issues. Output from `/fh debug` helps a lot.
