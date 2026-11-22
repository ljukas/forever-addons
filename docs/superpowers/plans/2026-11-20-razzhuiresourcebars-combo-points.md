# Plan: RazzhUIResourceBars combo points row

Spec: `docs/superpowers/specs/2026-11-20-razzhuiresourcebars-combo-points-design.md`. One step, one PR.

## Tasks

1. **Settings layout.** `PowerBar.DEFAULTS` gains `comboPoints = true`, `comboPointsHeight = 10`;
   Database.lua's layout comment lists them; EditMode.lua validates, saves (and logs) them.
   SavedVariables gate: `savedvariables-guard` after this task.
2. **Other Powers row seam.** OffFormPower.lua exposes `Row()` (its row while it is in, else nil)
   and `OnRowChanged(func)`; stubs for non-druids.
3. **ComboPoints.lua.** Row of five slots on top of the frame, events, secret-safe fill, `COMBO`
   tag. Listed in the TOC after OffFormPower.lua. Edit Mode checkbox and slider for rogues and
   druids; strings in Core.lua.
4. **CHANGELOG** line under Unreleased.

## Step reviewers

Core four, plus `savedvariables-guard` (settings keys) and a UI reviewer (frames, atlases).

## Review Focus

- The fill never compares or does arithmetic on the combo point count.
- The row sits flush on the Other Powers row when that is in and on the power bar otherwise, and
  moves when the Other Powers setting is toggled.
- Cell and fill offsets: five cells share one line between slots, end cells line up with the
  frame's border below.

## In-game checks

| Check | How it shows |
| --- | --- |
| `GetComboPoints` secret in/out of combat | `COMBO secret <bool> combat <bool>` (LogOnce per pair) |
| Row shows only with a target, as rogue or in Cat Form | `COMBO shown <bool>` (LogChanged), by eye |
| Slots fill one per point, smoothly | by eye |
| Red matches the target portrait's gems | by eye, side by side |
| Druid: row sits on the Other Powers row; rogue: on the power bar | by eye; `COMBO anchor offform/bar` |
| Moving points to a new target updates | `COMBO_TARGET_CHANGED`, by eye |
| Separators cut from the border art, one line wide, sharp at odd widths | `COMBO separator art true`, by eye at Width 271 |
| A point gained without an energy change shows at once | by eye (`UNIT_POWER_UPDATE`) |
