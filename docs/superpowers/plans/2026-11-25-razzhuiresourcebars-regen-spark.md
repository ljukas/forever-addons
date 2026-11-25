# Plan: RazzhUIResourceBars mana regen spark

Spec: `docs/superpowers/specs/2026-11-25-razzhuiresourcebars-regen-spark-design.md`. One step, one PR.

## Tasks

1. **Shared cost lookup (refactor).** CostPrediction.lua's `CostOf` moves to PowerBar.lua as
   `ns.PowerBar.SpellCost(spellID, powerType)`; CostPrediction.lua calls it. No behaviour change.
2. **Settings layout.** `PowerBar.DEFAULTS` gains `regenSpark = true`; Database.lua's layout comment
   lists it; EditMode.lua validates, saves (and logs) it. SavedVariables gate:
   `savedvariables-guard` after this task.
3. **Other Powers row seam.** OffFormPower.lua exposes `BarFor(powerType)`: the row's bar for that
   power while the row is in, else nil; a stub for non-druids.
4. **RegenSpark.lua.** The spark, its clock and events, `REGEN` tag, `SetEnabled`. Listed in the TOC
   after OffFormPower.lua. Edit Mode checkbox for classes with mana; strings in Core.lua.
5. **CHANGELOG** line under Unreleased.

## Step reviewers

Core four, plus `savedvariables-guard` (settings key) and a UI reviewer (frames, atlas, layering).

## Review Focus

- Nothing secret is compared or calculated with: the spark's place comes from `GetTime()` only, and
  a secret `spellID` or cost starts nothing.
- The spark changes bars on a form change without getting stuck on a hidden parent: the clock runs
  on a frame that is never hidden.
- Turning the setting off, a loading screen and death each stop a running spark.
- Layering: above the border on both bars; the Other Powers row's clip.

## In-game checks

| Check | How it shows |
| --- | --- |
| A mana spell starts the spark; a free or non-mana one doesn't | `REGEN start <spellID> <cost>`, by eye |
| The spark reaches the right edge as regen resumes | by eye against the mana bar; `REGEN regen start/done <base> <casting>` (or `secret`) |
| Forever has a five-second rule at all | the same `REGEN regen` lines: base regen at `done` above the one at `start` |
| A second cast restarts the spark from the left | by eye; two `REGEN start` lines without a `REGEN stop done` between |
| Cast-time spell: the spark starts at the end of the cast | by eye |
| Channel: starts at the channel's start | `REGEN start` time against the channel, by eye |
| Druid: shifting starts the spark; it shows on the Other Powers mana bar in a form and moves back | `REGEN host bar/offform/none` (at each spark's start and on each change), by eye |
| Look: size and layering on both bars, not cut off on the Other Powers row | by eye |
| Checkbox off stops and hides it; survives `/rl` | `SAVE` line's last field, by eye |
| Clearcasting cast starts no spark | `REGEN start` absent for the free cast |
| A secret spell or cost starts nothing | `REGEN secret spell/cost` (LogOnce) |
| The spark stops on death, a loading screen and the setting going off | `REGEN stop PLAYER_DEAD/PLAYER_ENTERING_WORLD/off` |
