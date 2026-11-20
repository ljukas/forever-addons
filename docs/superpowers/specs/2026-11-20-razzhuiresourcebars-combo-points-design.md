# RazzhUIResourceBars: combo points row

## Goal

Rogues, and druids in Cat Form, see their combo points as a row of five slots on top of the
resource bar frame, filling left to right as points build, in the red of Blizzard's combo point
gems around the target portrait.

## Scope

- **Who:** rogues always; druids while their power is energy (Cat Form), Blizzard's own rule
  (`DruidComboPointBarMixin:ShouldShowComboPointBar`, Mainline/DruidComboPointBar.lua).
- **When:** only while the player has a target (user, 20 Nov 2026). Combo points live on the target
  in Forever (`GetComboPoints("player", "target")`, Camelot/ComboFrame.lua), so "has points" never
  happens without one; with a target and no points the row shows five empty slots.
- **Where:** the top of the frame: on the druid's Other Powers row when it is in, else straight on
  the power bar. Same cast-bar border cells and background as the Other Powers row, sharing lines.
- **Look:** five slots, each the plain player-frame fill (`…-Bar-Mana-Status`) tinted the gem red,
  sampled from the user's screenshot of `uf-roguecp-icon-red` (≈ 0.80, 0.20, 0.20).
  `PowerBarColor.COMBO_POINTS` is yellow, so it is not used.
- **Settings:** in the power bar's Edit Mode dialog, for rogues and druids: a Combo Points checkbox
  (default on) and a Combo Points Height slider (3–20, default 10). Stored per layout next to the
  other fields in `RazzhUIResourceBarsDB.powerBar`; missing or invalid reads as the default, so no
  migration.

Deferred: a slide or fade when the row comes and goes (it just appears; a shared slide helper with
OffFormPower.lua would be a refactor of its own), more than five points.

## Secret values

`GetComboPoints` is `SecretWhenUnitPowerRestricted`. The count is never compared or logged: slot
*i* is a status bar with range *i−1 … i* that gets the count as its value, so the client's own
clamping fills it or leaves it empty. Visibility depends only on class, `UnitPowerType` and
`UnitExists("target")`, none of them secret.

## Events

`PLAYER_TARGET_CHANGED` and `UNIT_DISPLAYPOWER` (player) re-decide visibility; `COMBO_TARGET_CHANGED`,
`UNIT_POWER_FREQUENT` and `UNIT_MAXPOWER` (player) refill the slots; `PLAYER_ENTERING_WORLD` does both.
A target change fills at once, like Blizzard's (suppressTransitions); point changes fill smoothly when
the layout's Smooth Fill is on.
