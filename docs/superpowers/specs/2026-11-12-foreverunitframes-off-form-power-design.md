# ForeverUnitFrames: a druid's other powers on the power bar

Date: 2026-11-12. Builds on `2026-11-10-foreverunitframes-detached-power-bar-design.md`.

## Intent

The user plays a druid. In bear or cat form they want to see their mana (is there enough to shift
out, heal and shift back?) and the other form's power (is cat energy full yet? it keeps filling
outside cat form). Display only: "All I want is it to draw correctly. We don't need any logic on
it."

## What it does

- A row above the detached power bar holds a thin bar for each power of mana, energy and rage
  that the druid has and the current form does **not** use, in that order.
- A power only gets a bar once the druid knows its form (the user: "we should only activate
  extra bars when we know the spells"). Mana always counts; rage counts once a bear form is on
  the stance bar (spells 5487, 9634), energy once Cat Form is (768).

  | Forms known | In caster form | In bear | In cat |
  |---|---|---|---|
  | none (before level 10) | no row | | |
  | bear | rage, full width | mana, full width | |
  | bear and cat | energy, rage | mana, energy | mana, rage |

  One bar spans the row, so with the main bar it is two bars of equal width; two bars split the
  row in half.
- **One frame** (the user's words): the row and the main bar share the cast bar's background and
  border, which grow upward over the row. A thin divider line separates the row from the main bar
  and the two halves from each other. No gaps, no second border.
- The bars use Blizzard's player-frame bar art per power
  (`UI-HUD-UnitFrame-Player-PortraitOn-Bar-<Mana|Energy|Rage>`, from `PowerBarColor`), with no
  text, pulse or spend flash. They slide to new values when the bar's Smooth Fill is on.
- The row follows the main bar's position and width. The Edit Mode box stays the main bar; the row
  grows upward from it.
- Druids only. Other classes see no row and no settings for it.
- Two settings in the bar's Edit Mode dialog, per layout like the others, shown only to druids:
  **Other Powers** (checkbox, on by default) and **Other Powers Height** (slider, 3–20, default 6).

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

- The order mana, energy, rage, and showing energy + rage in caster form.
- Reading known forms from the stance bar (`GetShapeshiftFormInfo`) by spell ID.
- The divider: a 1 px grey line with a 1 px black line on each side, to echo the border. To be
  tuned from a screenshot.
- The height slider, since pixel tuning goes in options sliders.

## In-game checks

| Check | How it shows |
|---|---|
| Row shows the right powers in bear, cat and caster form | screenshot; `OFFFORM powers` |
| The stance bar's form spell IDs are the ones the code expects | `OFFFORM form <index> <spellID>` |
| A druid without cat form gets one full-width bar; without bear form, no row | user on a low-level druid |
| Row and main bar read as one framed bar; dividers look right | screenshot |
| Fills reach the border's left and right ends | screenshot at full mana |
| Energy fills while in bear; what rage reads in cat | user's eyes (values are secret); `OFFFORM event <event> <power> in <current>` shows which powers get updates |
| The energy and rage bar art exists; the border stretches without thickening | `OFFFORM art`; screenshot |
| Bars update in combat, no blocked actions or errors | `devlog.sh --errors` |
| Checkbox hides the row and the border shrinks back; slider resizes it | user; `OFFFORM layout` |
| A non-druid sees no row and no settings | user on another character |
