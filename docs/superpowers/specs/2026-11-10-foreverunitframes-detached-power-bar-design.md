# ForeverUnitFrames: detached player power bar

Date: 2026-11-10. Decision record: `docs/adr/0002-detach-the-player-power-bar-by-reparenting-blizzards-bar.md`.

## Intent

The user wants their power (rage, mana, energy) where their eyes are in a fight: just above the
action bars in the middle of the screen, not in the player frame in the corner. The player frame
keeps the portrait, name and health. The health bar grows into the space the power bar leaves, so
the frame doesn't show an empty slot or the divider between the two.

## What it does

- **Health bar:** in the player frame, the health bar covers both the health row and the power
  row below it (Forever's layout: health 124×15 at (87, −46), power 124×10 at (87, −61)). The frame
  art draws the power row's well and the divider between the rows, so the grown bar needs frame art
  without them: which art, and the exact mask, are settled in game with the `/fufart` probe
  (`Dev/ArtProbe.lua`). First build: container, bar and mask grown by 10 px (the user's first
  screenshot showed the divider and the old well still there).
- **Power bar:** Blizzard's own player mana bar (`PlayerFrame_GetManaBar()`), with its colour,
  text, full-power pulse and spend feedback, moves into a holder frame of ours on `UIParent`. It
  fills the holder and wears the cast bar's background and border (`ui-castingbar-background`,
  `ui-castingbar-frame`, the cast bar's offsets), so it matches the other free-standing bars. Its
  mask becomes the plain `Unit_BarMask`, 2 px past the bar like Blizzard's; the full-power pulse is
  centred on its right end, as on the Personal Resource Display.
- **Edit Mode:** the holder is an Edit Mode box named "Player Power Bar" (LibEditMode). Players
  drag it, and its dialog has **Width** (60–600, default 270) and **Height** (8–40, default 12)
  sliders plus Reset Position. Default position: bottom centre, 150 px up. When Edit Mode's
  snapping is on, a dropped box snaps like Blizzard's (`Snap.lua`): within 8 screen pixels of the
  screen's edges and centre, the grid lines, and the edges and centres of the other boxes.
- Position and size are kept per Edit Mode layout, account-wide, in `ForeverUnitFramesDB`.
  Character-specific layouts are keyed by the character too (characters can each have a layout of
  the same name); the preset layouts are shared, as in Edit Mode.

## Constraints

- The bars are protected frames: layout changes only out of combat. If Blizzard re-lays out the
  frame in combat (loading screen, vehicle), the power bar stays put: it lives in a slot frame
  offset so Blizzard's own `SetPoint("TOPLEFT", 87, -61)` lands where ours is. The health bar shows
  Blizzard's sizes until combat ends. A `/reload` in combat leaves the bar in the player frame until
  combat ends, and the holder's backdrop hidden.
- Never replace Blizzard functions or fields: `hooksecurefunc` on the two layout functions, and
  `HookScript` on the bar's OnShow/OnHide (to show the backdrop with the bar).
- Power values are secret; our code never reads them.
- The detached bar no longer hides with `PlayerFrame` (it lives on `UIParent`); nothing in
  Forever hides `PlayerFrame` on its own.

## Non-goals (first slice)

- Target, party or pet frames; a separate class-resource or alternate power bar; hiding the
  power bar; a Settings-panel copy of the sliders; text format options; snap preview lines while
  dragging (Blizzard draws them; the box snaps on drop).

## In-game checks

| Check | How it shows |
|---|---|
| Health bar fills both rows, no divider or old well showing | screenshot; `LAYOUT` (measured sizes), `ART` (atlas sizes) |
| Power bar sits in the holder with the cast bar's border, updates, text shows | screenshot; `POWER` (size, shown) |
| Full-power pulse sits at the bar's right end | screenshot at full energy/rage/mana |
| No blocked actions on login, `/reload`, combat, Edit Mode drag | `devlog.sh --errors` |
| A re-layout in combat is deferred and applied after | `DEFER` / `APPLY` |
| The layout name resolves at login, and drags and sliders save | `EDITMODE layout <name>` with a name, then `SAVE` |
| Drops snap to the action bars, screen centre and grid | user; `EDITMODE snap` |
| Position dialog arrows have art (LibEditMode 19 predates its atlas fix) | screenshot |
