# Skill-up odds in the professions window — design

**Addon:** ForeverProfessions · **Step 2 of 2** of recipe statistics (step 1, the craft history,
is `2026-11-07-craft-history-design.md`, merged in ljukas/forever-addons#36)

## Why

Step 1 records every craft: per character, recipe and skill rank, the attempts, the skill
points they gave and the recipe's colour. The player wants that turned into something they can
use while levelling a profession: **their own chance to skill up** from a recipe at their
current skill, next to the commonly cited wiki formula as a baseline, and how often they've
crafted the recipe and how many points it gave them.

Success: in the Forever professions window, a recipe they've levelled with shows, under its
Reagents, how many times this character made it, the points it gave, and "chance at 86: 62%
(yours, 13 crafts) · 70% (wiki)"; and the recipe list shows a % at the end of every recipe row,
so recipes can be compared at a glance.

## Goals

1. **Text under Reagents** in the recipe schematic (the crafting page's right side):
   - this character's crafts of the recipe and the skill points they gave;
   - the player's own skill-up chance at their current skill, with how many crafts it rests on;
   - the wiki baseline chance at the current skill.
2. **A % at the right end of each recipe row** in the recipe list (the player's addition after
   seeing the skill-up arrows): the player's own estimate when it rests on enough crafts,
   otherwise the wiki %, in a dimmer colour.
3. Both update when a craft is recorded, without reopening the window.

## Non-goals

- A settings toggle for either display (can come later through `Options.lua`).
- Tooltips or breakdowns per rank.
- A static recipe-threshold table, or any data not learned in game.
- Other characters' craft counts (the counts are this character's own).
- Inspected / linked professions of other players, and crafting orders: only our own crafting
  page (`ProfessionsFrame.CraftingPage`) is extended.
- Localisation beyond enUS (as the rest of the addon, strings go in `ns.L`).

## Anti-goals

- **Tainting the professions window.** Crafting goes through it. Extend only with
  `hooksecurefunc`, `ScrollUtil.AddInitializedFrameCallback` and our own child font strings;
  never replace a Blizzard method, never write a field on a Blizzard frame or table, never
  re-anchor Blizzard's widgets.
- **A precise-looking number from no data.** Every estimate of ours shows how many crafts it
  rests on, and the wiki % shows a range or "?" rather than a guessed yellow level.
- **Pretending a capped craft could skill up.** At the trainer cap the text says so instead of a
  chance.

## Decided with the player

- **Yellow threshold: learned from crafts.** The client exposes the gray level
  (`recipeInfo.maxTrivialLevel`) but not the yellow one. It's taken from the recorded rows,
  pooled over all characters: the lowest rank seen yellow, with the highest rank seen orange
  below it. Exact when they're adjacent; a range when there's a gap; "?" when nothing orange was
  ever seen below a yellow sample (or no yellow sample exists). No static table, no guess from
  the gray level.
- **Our estimate pools nearby ranks of the same colour:** rows within **±5 ranks** of the
  current skill whose recorded colour equals the recipe's current colour, summed:
  `skillUps / attempts`, shown with the number of attempts. Capped crafts are already excluded
  from `attempts` by step 1.
- **Characters:** the odds (our estimate and the yellow level) pool every character on the
  account, since they don't depend on who crafts. "Crafted X times, Y skill-ups" is the current
  character's own.
- **Recipe list %:** at the **right end of the row**, right-aligned (Blizzard's layout left
  alone: the arrows sit 9 px outside the row's left edge, too little room for "100%"). It shows
  **ours if it rests on at least 5 crafts, else the wiki %** dimmed, else nothing.

## Design

### The numbers

Inputs: `recipeID`, the character's current base skill in the recipe's profession
(`C_TradeSkillUI.GetProfessionInfoByRecipeID(recipeID).skillLevel`, the same rank step 1 files
crafts under), its `maxSkillLevel`, and the live `recipeInfo.relativeDifficulty` and
`maxTrivialLevel` (gray). Any of them secret or missing → nothing is shown (logged once).

**Wiki baseline** at skill `s` with gray `g` and yellow `y`:

| Current colour | Baseline |
|---|---|
| Orange (Optimal) | 100% |
| Gray (Trivial) | 0% |
| Yellow / green, `y` known | `(g − s) / (g − y)`, clamped to 0–100% |
| Yellow / green, `y` in `[lo, hi]` | the range `(g − s)/(g − lo)` … `(g − s)/(g − hi)`, e.g. "60–75%" |
| Yellow / green, no lower bound | "?" |

Yellow learning, over every character's rows of the recipe: `Y` = lowest rank recorded yellow
(Medium); `O` = highest rank recorded orange (Optimal) **below `Y`**. With both, `y ∈ [O + 1, Y]`
(exact when `Y = O + 1`). Rows above `Y` that are orange (impossible unless the data is junk)
are ignored rather than trusted.

**Our estimate:** rows of every character with `|rank − s| ≤ 5` and recorded difficulty equal to
the current colour: `p = Σ skillUps / Σ attempts`, shown with `n = Σ attempts`. No rows (or
`n = 0`) → no estimate. A sum of skill-ups can exceed the attempts when a craft gives several
points; the shown % is clamped to 100%.

**At the skill cap** (`skill ≥ maxSkillLevel`): no chance is shown, only "at skill cap" in the
schematic, and **nothing** in the recipe list *(builder's call: the list must not say 100% next
to a schematic that says no chance)*.

**Base skill, not effective** *(builder's call)*. Step 1 files rows under the base
`skillLevel` and ignores `skillModifier` (its probe check 5 is still unanswered: the test
character had modifier 0). Step 2 uses the same base rank so the current skill and the rows are
on one scale. If a character with a racial or item bonus turns up, both steps would need the
effective rank, which is a recorder change and a follow-up of its own. Until then the dev log
line includes `skillModifier`, so in-game check 3 shows whether any displayed character has one.

### Schematic text

A font string of our own, a child of `ProfessionsFrame.CraftingPage.SchematicForm`, anchored
below the form's `Reagents` container (below `OptionalReagents` instead when that is shown),
left-aligned, wrapping within the reagent columns' width. Hidden when `Reagents` is hidden or
the recipe isn't learned. Blizzard's colours: labels in `NORMAL_FONT_COLOR` (the gold of the
"Reagents:" header), values in `HIGHLIGHT_FONT_COLOR`. Two lines, e.g.:

```
Crafted 23 times, 9 skill-ups
Chance at 86: 62% (yours, 13 crafts) · 70% (wiki)
```

Variants: "Not crafted yet" for the first line; "?" or a range for the wiki part; no "yours"
part when there's no estimate; "At skill cap" instead of the second line.

Refreshed by `hooksecurefunc` on that form instance's `Init` (Blizzard calls it on recipe
selection, `OnShow` and `Refresh`), and when a craft is recorded (below).

### Recipe list %

A right-aligned font string of our own on each recipe row of
`ProfessionsFrame.CraftingPage.RecipeList.ScrollBox`, created on first sight of the row and
kept in an addon-side table keyed by the row frame. Set from
`ScrollUtil.AddInitializedFrameCallback(scrollBox, ..., owner, true)` after Blizzard's own row
`Init`. Category rows (no `recipeInfo` in the element data) get nothing. Shown only for recipes
where Blizzard shows skill-up arrows (`recipeInfo.canSkillUp` and a non-gray colour). Our
estimate in the recipe's difficulty colour (`DIFFICULT_DIFFICULTY_COLOR` etc., as Blizzard's
arrow text), the wiki % in `DISABLED_FONT_COLOR`. How a wiki range fits the narrow column is
left to the builder.

The row label's width is computed by Blizzard from the row width; a long name could run under
our %. Whether that happens with real names is an in-game check.

### When a craft is recorded

`Database.lua`'s write functions (`RecordAttempt`, `RecordSkillUp`) announce the change through
`ns.callbacks:TriggerEvent("CraftsChanged", recipeID)`, as `Add` already announces
`NodesChanged`. The UI refreshes the schematic text if it shows that recipe, and every visible
list row (`ScrollBox:ForEachFrame`).

### Where the code goes

- `Database.lua`: read functions; the only code that indexes `ns.db.crafts`. One for this
  character's totals of a recipe (crafts = attempts + capped, skill-ups), and one that calls back
  per row of a recipe across all characters (rank, attempts, skill-ups, difficulty).
- `Odds.lua` (new): the pure math above (yellow learning, wiki baseline, our pooled estimate),
  with no frame or event code, so a reviewer can check it by reading.
- `UI/RecipeOdds.lua` (new): the two hooks and the formatting, loaded through
  `EventUtil.ContinueOnAddOnLoaded("Blizzard_Professions", ...)` (the window is load-on-demand).
- `Core.lua`'s shim comment lists any new `ns.log` tags; `ns.L` gets the strings.
- `CHANGELOG.md`: a players' line under `## Unreleased`.

No SavedVariables change.

## In-game checks

1. The schematic text sits under Reagents without overlapping the Details panel or the Create
   buttons, for a recipe with 1, 2 and 4+ reagents.
2. The list % lines up at the row ends and doesn't collide with long names or `[count]`.
3. The numbers match the saved rows: a dev-only log line per displayed recipe (inputs and
   results) lets them be checked against `ForeverProfessionsDB`; e.g. recipe 3929 (orange
   79–84, yellow at 85, gray 95) must learn yellow = 85.
4. After a craft, both displays update without reselecting the recipe.
5. `scripts/devlog.sh --errors` stays clean, with no `ADDON_ACTION_BLOCKED` while crafting
   (taint check).

## Left to the builder

- Exact wording and number formatting (whole percent), within the examples above.
- How a wiki **range** is shown in the narrow list column (midpoint with a "~", the lower bound,
  or nothing).
- Function names, the dev log tag and its `LogChanged` key.
- The reagent-column width the text wraps at (read from the form or a constant from Blizzard's
  Camelot override: two 160 px reagent slots).
