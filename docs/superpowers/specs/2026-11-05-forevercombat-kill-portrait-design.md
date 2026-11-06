# ForeverCombat: red portrait when your DoTs will kill

Date: 2026-11-05 · Status: approved · Addon: ForeverCombat

## Intent

The DoT meter draws the damage your DoTs still have to deal as segments on the target's and
focus's health bar. Once they cover all of the remaining health, a small glow lights at the
bar's left end (`UI/Cue.lua`). On a low-health target that is too subtle: you can't tell at a
glance that the target is already dead, so you keep casting on it instead of switching. This
adds an unmistakable signal: **the unit frame's round portrait turns red while your DoTs will
finish the target off**, so you can move on to the next one.

## Goals

1. **Red portrait.** While the DoT meter's total for the unit covers its current health, the
   portrait on the target frame (and on the focus frame) is washed red. No icon. Picked by the
   user from three mockups (red X, skull, red portrait).
2. **Same condition as the existing glow.** It shows exactly when the DoT meter's cue glow
   shows: the total of the player's tracked DoTs' remaining damage on the unit (`ns.Tracker`,
   the same total the segments draw) is at least `UnitHealth(unit)`. One source of truth: it
   must never disagree with the meter.
3. **Own checkbox** in Options → AddOns → ForeverCombat, on by default, under the DoT Meter
   checkbox. Off hides it. When the DoT Meter itself is off, the portrait stays normal too:
   it has no effects to go by.
4. **Target and focus frames**, the two hosts the meter already draws on (`UI/Hosts.lua`).

## Non-goals

- No sound, no nameplates, no party/raid frames, no change to the bar glow (it stays).
- Nobody else's damage counts, only the player's tracked DoTs (as for the meter).
- No "probably dies" threshold or earlier warning: see the constraint below.

## Constraints

- **Health is secret in combat** (Midnight restrictions). Addon code can't compare the DoT
  total against `UnitHealth`. `UI/Cue.lua` gets around it with a very long invisible
  StatusBar (`max = health`, `value = total`), a texture riding the end of its fill, and a
  clipping window as wide as that texture: the texture is only on screen when the fill reaches
  the end, i.e. at 100%. The red portrait has to use the same trick, so it is on/off
  (with a short wipe across the portrait as the total crosses the last fraction of a percent
  of health) and can't fire earlier than "the DoTs cover it".
- **Native look.** Blizzard's own pieces: the portrait is `TargetFrame.TargetFrameContainer.Portrait`
  (58×58, `BACKGROUND` sublevel 1), shaped round by `TargetFrameContainer.PortraitMask`
  (`CircleMask`); the gold ring is `FrameTexture` (`BACKGROUND` sublevel 2). FocusFrame uses
  the same template. The red follows the same circle mask. The red is Blizzard's
  `RED_FONT_COLOR` (no custom art).
- **No taint.** Hooks and child frames only; never set fields on Blizzard's frames or touch them
  in combat beyond parenting our own non-secure frames to them (as the bar segments already do).

## Decided by Claude (builder may revisit)

- **"Washed red" keeps the face readable**: a multiplicative tint (`MOD` blend, a texture in
  `RED_FONT_COLOR`) rather than an opaque red disc, so you still see who it is; Blizzard
  reddens low-health player portraits the same way. *Amended in review:* a multiply alone mostly
  darkens dark portraits, so the same red at 0.35 alpha (`BLEND`) goes over it. Tune in game.
- **Same start as the glow.** Each cue's long bar is its rider's width / 0.0016, so the 58px
  portrait rider starts wiping in at the same total as the 16px glow (*amended in review*).
- **Generalise the cue rather than duplicate it.** `ns.Cue` already does "show this texture
  only when total ≥ max"; the portrait is a second cue shape (window over the portrait,
  red texture as wide as the portrait, masked by the portrait mask). The DoT module declares
  it next to its bar cue, so the hosts render it in the same pass with the same total.
- **Setting key** `dotKillPortrait` in `ForeverCombatDB.settings`, registered like the module
  checkboxes (default true). Adding a key needs no DB migration (registering fills the default).
- **Layering**: under the gold ring is impossible (portrait and ring are adjacent `BACKGROUND`
  sublevels 1 and 2), so the red draws over the ring. *Amended in review:* the frame's own
  `PortraitMask` is only 1px inside the ring, so the red gets its own `CircleMask` 3px further
  in to stay off the ring's inner edge. Tune in game.
- **Combo points stay visible.** On Forever, Blizzard's `ComboFrame` is centred on the target
  portrait (`Blizzard_UnitFrame/Camelot/ComboFrame.lua`) at MEDIUM strata and a 66px radius, so
  by source they're above our LOW-strata red and outside its circle. Launch check.
- **The checkbox is a child of DoT Meter** in the options panel, indented and greyed out while
  DoT Meter is off (Blizzard's `SetParentInitializer`), since it has nothing to show then.

## Left to the builder

File layout, names, how the second cue is declared on the module, the exact wipe width.

## Launch checks (after launch, in game; the user's main checkout is busy, so later)

- The portrait turns red at the same moment as the bar's left-end glow, and back when the
  target heals or a DoT ends (`DISPLAY` log line extended with the kill state is not possible:
  it's secret. Check by eye).
- The red is round, lines up with the portrait, and looks right with the gold ring and the boss
  (gold dragon) frame.
- The red is clearly visible but the face is still recognisable, also on dark, blue or grey
  models and tap-denied (greyed) mobs.
- The ring's inner edge, the boss gold dragon and the red threat flash stay un-tinted.
- `HOST` lines: portrait 58×58, its layer `BACKGROUND 1`, ring `BACKGROUND 2`, combo frame
  `MEDIUM`. `DISPLAY` shows `portrait=on/off` follow the checkbox.
- Combo points (rogue, druid in cat form) still show on top of the red.
- Unticking the checkbox (and the DoT Meter checkbox) clears it at once.
- No Lua errors or blocked actions (`scripts/devlog.sh --errors`).
