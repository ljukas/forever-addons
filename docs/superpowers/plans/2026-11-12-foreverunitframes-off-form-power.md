# Plan: a druid's other powers on the power bar

Spec: `docs/superpowers/specs/2026-11-12-foreverunitframes-off-form-power-design.md`.
One step, one PR: `feat(foreverunitframes): show a druid's other powers above the power bar`.
Stacked on `build/scripts-pkgmeta-libs` (PR #41), where ForeverUnitFrames lives until it merges.

## Tasks

1. **PowerBar.lua seams.** Defaults `offForm = true`, `offFormHeight = 6`. Expose
   `ns.PowerBar.border` (the row's parent, so it hides with the backdrop),
   `ns.PowerBar.SetHeadroom(pixels)` (grows the background and border upward) and
   `ns.PowerBar.Interpolation()` (the current smooth/immediate mode).
2. **OffFormPower.lua** (new, in the TOC after PowerBar.lua). The row, its two status bars and the
   dividers; which powers to show (pure function `OtherPowers(current, known)`; `KnownPowers` reads the stance bar); events
   `UNIT_DISPLAYPOWER`, `UNIT_POWER_FREQUENT`, `UNIT_MAXPOWER` for the player, `UPDATE_SHAPESHIFT_FORMS`, `SPELLS_CHANGED`, registered only
   while the row shows; `ns.OffFormPower.SetLayout(shown, height)`; `ns.OffFormPower.available`
   (player is a druid). Log tag `OFFFORM`.
3. **EditMode.lua + Core.lua + Database.lua.** `VALID` entries, `Apply` passes the two settings on,
   a checkbox and a slider added only when `ns.OffFormPower.available`; strings in `ns.L`; the DB
   layout comment and the tag list in Core.lua.
4. **CHANGELOG.md** line under Unreleased.

## Step reviewers

Core (`addon-reviewer`, `api-verifier`, correctness, spec) plus `savedvariables-guard` (new saved
fields) and a UI reviewer (new frames on Blizzard's bar).

## Review Focus

- Secret values: `UnitPower` / `UnitPowerMax` results must go only into `SetValue` /
  `SetMinMaxValues`, never into a comparison, arithmetic, a log line or a table key.
- Switching a bar to another power must not slide from the old power's value.
- Nothing here may touch Blizzard's protected mana bar or re-anchor the holder; in combat only
  our own unprotected frames and textures change.
- A saved layout without the new fields, and a non-druid, must behave exactly as before.

## In-game checks

The spec's table. Tags: `OFFFORM powers <current> <left> <right>` on every change of bars, `OFFFORM form <index> <spellID>` per stance-bar form,
`OFFFORM layout <shown> <height>` on every layout apply.
