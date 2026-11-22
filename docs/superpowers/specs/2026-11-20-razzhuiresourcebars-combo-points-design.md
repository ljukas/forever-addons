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
- **Look:** one status bar across the row, 0 to 5, so the fill's art runs on unbroken and stops at
  the last point (five bars repeated the art per slot, and looked cramped, in game 21 Nov). The
  plain player-frame fill (`…-Bar-Mana-Status`) tinted the gem red, sampled from the user's
  screenshot of `uf-roguecp-icon-red` (≈ 0.80, 0.20, 0.20); `PowerBarColor.COMBO_POINTS` is yellow,
  so it is not used. One cast-bar border across the row (the art isn't sliced, so a squeezed copy
  per slot thins its lines), split by separators cut from that art's left side, each with one
  screen pixel of the border's dark brown rim either side, so every slot ends and starts as the
  bar's ends do (`ns.PowerBar.CreateSeparator`, PowerBar.lua).
- **Other Powers row:** restyled the same way, one border with a divider between mana and energy
  instead of a border per bar, which read as two stacked boxes (user, 22 Nov). Confirmed in game
  22 Nov in Bear Form, with widths logged side by side (row 255, bars 129.5 and 130.5).
- **Settings:** in the power bar's Edit Mode dialog, for rogues and druids: a Combo Points checkbox
  (default on) and a Combo Points Height slider (3–20, default 10). Stored per layout next to the
  other fields in `RazzhUIResourceBarsDB.powerBar`; missing or invalid reads as the default, so no
  migration.

Deferred: a slide or fade when the row comes and goes (it just appears; a shared slide helper with
OffFormPower.lua would be a refactor of its own), more than five points.

## Secret values

`GetComboPoints` is `SecretWhenUnitPowerRestricted`. The count is never compared or logged: it goes
straight into the status bar's `SetValue`, which takes secret values. Readable in and out of combat
(in game 22 Nov, Cat Form, open world), but the design doesn't rely on it. Visibility depends only on class, `UnitPowerType` and
`UnitExists("target")`, none of them secret.

## Events

`PLAYER_TARGET_CHANGED` and `UNIT_DISPLAYPOWER` (player) re-decide visibility; `COMBO_TARGET_CHANGED`,
`UNIT_POWER_FREQUENT`, `UNIT_POWER_UPDATE` and `UNIT_MAXPOWER` (player) refill the bar while it shows; `PLAYER_ENTERING_WORLD` does both.
A target change fills at once, like Blizzard's (suppressTransitions); point changes fill smoothly when
the layout's Smooth Fill is on.
