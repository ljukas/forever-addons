# ForeverUnitFrames: a druid's other powers on the power bar

Date: 2026-11-12. Builds on `2026-11-10-foreverunitframes-detached-power-bar-design.md`.

## Intent

The user plays a druid. In bear or cat form they want to see their mana (is there enough to shift
out, heal and shift back?) and the other form's power (is cat energy full yet? it keeps filling
outside cat form). Display only: "All I want is it to draw correctly. We don't need any logic on
it."

## What it does

- A row above the detached power bar holds a thin bar for mana and for energy when the current
  form does **not** use them, in that order.
- Energy only gets its bar once the druid knows Cat Form (the user: "we should only activate
  extra bars when we know the spells"): spell 768 on the stance bar.
- Rage never gets a bar: in game it was gone whenever the user went back into bear form, so
  there is nothing to watch (2026-11-12). Energy does build up outside cat form (the Furor talent).

  | Forms known | In caster form | In bear | In cat |
  |---|---|---|---|
  | none or bear only | no row | mana, full width | |
  | cat (with or without bear) | energy, full width | mana, energy | mana, full width |

  One bar spans the row, so with the main bar it is two bars of equal width; two bars split the
  row in half.
- **One frame** (the user's words), with borders that fit the bar's look: each bar in the row
  wears the cast bar's border, like the main bar, and neighbouring borders overlap by their line,
  so the bars share one thin line between them. The main bar's border is left as it is: the art
  isn't sliced, and stretched over the row its top and bottom lines grew thicker and crowded the
  bar's text (in game, 2026-11-12). The background grows upward behind the row.
- The bars use Blizzard's player-frame bar art per power
  (`UI-HUD-UnitFrame-Player-PortraitOn-Bar-<Mana|Energy>`, from `PowerBarColor`), with no
  text, pulse or spend flash. They slide to new values when the bar's Smooth Fill is on.
- The row follows the main bar's position and width. The Edit Mode box stays the main bar; the row
  grows upward from it.
- Druids only. Other classes see no row and no settings for it.
- Two settings in the bar's Edit Mode dialog, per layout like the others, shown only to druids:
  **Other Powers** (checkbox, on by default) and **Other Powers Height** (slider, 3–20, default 10).

## Constraints

- Power values are secret on Forever, even out of combat. The code passes `UnitPower` /
  `UnitPowerMax` straight into `StatusBar:SetValue` / `SetMinMaxValues` and never compares, logs
  or does arithmetic on them. `UnitPowerType("player")` (which power the form uses) is not flagged
  secret and is branched on.
- The row's frames are ours and unprotected, so they update in combat. Nothing about Blizzard's
  bar or the holder changes in combat because of this feature.
- The row hides with the main bar's backdrop (a `/reload` in combat leaves the bar in the player
  frame until combat ends).
- Saved data: two new fields in each `ForeverUnitFramesDB.powerBar` entry (`offForm`,
  `offFormHeight`). A missing field reads as its default, so no migration and no version bump.

## Non-goals

- Thresholds, markers, glows, sounds, numbers on the row; other classes; dead/ghost desaturation
  of the row; a rage bar that hides itself when empty.

## Calls made by the builder (not the user's)

- Mana left of energy, and showing energy in caster form.
- Reading known forms from the stance bar (`GetShapeshiftFormInfo`) by spell ID.
- The height slider, since pixel tuning goes in options sliders.

## In-game checks

| Check | How it shows |
|---|---|
| Row shows the right powers in bear, cat and caster form | screenshot; `OFFFORM powers` |
| The stance bar's form spell IDs are the ones the code expects | `OFFFORM form <index> <spellID>` |
| A druid without cat form gets no row in caster form and mana in bear | user on a low-level druid |
| Row and main bar read as one framed bar; dividers look right | screenshot |
| Fills reach the border's left and right ends | screenshot at full mana |
| Energy fills while in bear and in caster form | user's eyes (values are secret); `OFFFORM event <event> <power> in <current>` shows which powers get updates |
| The energy bar art exists; the border stretches without thickening | `OFFFORM art`; screenshot |
| Bars update in combat, no blocked actions or errors | `devlog.sh --errors` |
| Checkbox hides the row and the border shrinks back; slider resizes it | user; `OFFFORM layout` |
| A non-druid sees no row and no settings | user on another character |
