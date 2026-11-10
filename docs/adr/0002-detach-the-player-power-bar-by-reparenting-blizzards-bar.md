# 0002: Detach the player power bar by re-parenting Blizzard's bar, placed with LibEditMode

Date: 2026-11-10. Status: accepted.

## Context

ForeverUnitFrames moves the player frame's power bar out of the player frame into a frame the
player places and sizes, and lets the health bar fill the space it leaves
(`docs/superpowers/specs/2026-11-10-foreverunitframes-detached-power-bar-design.md`). On Forever,
player power is a secret value (CLAUDE.md), and the player frame's health and mana bars are
protected frames: they inherit `SecureFrameParentPropagationTemplate`, so addon code can't move
or resize them in combat. Forever's player frame lays the bars out in two global functions,
`PlayerFrame_UpdateHealthBarVisuals` and `PlayerFrame_UpdateManaBarVisuals`
(`Blizzard_UnitFrame/Camelot/PlayerFrame.lua`), which run again on every art change (vehicle,
alternate power bar, Edit Mode).

Edit Mode has no API for addons to add their own systems.

## Decision

1. **Re-parent Blizzard's own mana bar** (`PlayerFrame_GetManaBar()`) into a holder frame of ours,
   and re-apply our layout after Blizzard's with `hooksecurefunc` on both layout functions. Blizzard
   keeps updating the bar (value, colour, text, full-power pulse, spend feedback), and secret
   values never reach our code.
2. **Every layout change goes through one gate:** apply now out of combat, or once
   `PLAYER_REGEN_ENABLED` fires if Blizzard re-laid out the frame in combat.
3. **Place and size the holder with LibEditMode** (p3lim-wow, MINOR 19, which lists Forever's
   interface and game type), loaded in its namespaced mode so it needs no LibStub. Position and
   size are kept per Edit Mode layout, like Blizzard's own systems.

## Alternatives considered

- **Draw our own power bar and hide Blizzard's:** our code would have to feed `UnitPower`, a
  secret value, to a bar and its text, and rebuild colour, text, pulse and cost prediction that
  Blizzard's bar already does.
- **Hand-rolled Edit Mode support** (drag on `EditMode.Enter`, sliders in the Settings panel): no
  library, but no dialog in Edit Mode, one position for all layouts, and more code of our own. The
  user picked LibEditMode.
- **LibStub-registered LibEditMode:** shares one copy between addons, but needs LibStub, which is
  only published on CurseForge's SVN. The namespaced copy is ours alone.

## Consequences

- The repo's first library. `scripts/libs.sh` fetches `.pkgmeta` externals into `Libs/` for
  development; the packager bundles it unmodified, as its licence requires.
- If Blizzard re-lays out the player frame in combat (a vehicle), our layout returns when combat
  ends, not immediately.
