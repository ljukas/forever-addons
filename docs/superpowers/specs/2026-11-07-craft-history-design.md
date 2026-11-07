# Craft history — design

**Addon:** ForeverProfessions · **Step 1 of 2** (record; the professions-window text is step 2)

## Why

The player wants a history of everything their characters craft, in every profession, and above
all wants to work out **their own skill-up chance per craft** from it: how likely a recipe is to
give a point at a given skill level, and how that varies with its colour (orange, yellow, green,
gray). Nothing about crafting is recorded today; ForeverProfessions only records gathering nodes.

Success: after some crafting, the saved data answers "Rough Copper Bomb at skill 63, yellow:
6 attempts, 2 skill-ups", for every recipe and skill level crafted, per character.

## Goals

- Record every completed craft of every profession, on every character, from the release on.
- Per craft, at the **start of that cast**: the recipe, the character's skill in that
  profession, and the recipe's colour at that moment.
- Per craft, at its end: whether it gave skill points, and how many.
- Items made per recipe.
- A layout that supports estimating P(skill-up | recipe, skill level), and pooling it across
  characters.

## Non-goals (this step)

- Any UI: the text below Reagents in the professions window is step 2, built on this data.
- Reagent cost or prices.
- Backfilling crafts made before the release (impossible).
- A per-craft timeline with dates. The player's aim is the skill-up estimate, and the
  per-skill-level aggregate answers it with bounded size (at most one row per skill level).

## Anti-goals

- **Skill-ups credited to the wrong craft.** In a "Create All" queue the next cast can start
  before the skill-up from the previous one is reported. Crediting "the current cast" would
  shift every queued skill-up one craft late, to a higher skill and maybe a lighter colour, and
  silently corrupt the estimates. Wrong data is worse than no data.
- Sampling once per button press. A queue of 10 is 10 samples, each with its own skill and
  colour.
- Counting interrupted or failed casts as attempts.
- Touching Blizzard's professions frames or tainting them.

## Decided with the player

- **All professions**, including Cooking, First Aid, Smelting and Enchanting.
- **Per character**, so each character has its own history.
- **Snapshot at the start of each cast**, never once per Create press (the player's words:
  "check at start of EACH craft").
- Aim: the player's own inference of skill-up % per craft.

## Design

### Where it lives

ForeverProfessions, in a new `Sources/CraftRecorder.lua`, alongside `Sources/GatherRecorder.lua`
and built the same way (a `handlers` table keyed by `UNIT_SPELLCAST_*` events, registered for
`"player"`, casts matched by `castGUID`, `issecretvalue` guards on every payload value).

### Saved layout (account-wide `ForeverProfessionsDB`, `DB_VERSION` 1 → 2)

```
crafts = {
  [characterKey] = {                 -- "Name-Realm"
    [recipeID] = {
      made   = <items produced, all crafts>,
      gray   = <recipeInfo.maxTrivialLevel, latest seen>,
      levels = {
        [skillRank] = { attempts, skillUps, difficulty, capped },
      },
    },
  },
}
```

- `skillRank`: the character's skill in the recipe's profession at the start of the cast.
- `attempts`: completed casts at that rank. `skillUps`: skill points they gave (normally 0 or 1
  per cast; a sum, so multi-point gains are kept).
- `difficulty`: the `Enum.TradeskillRelativeDifficulty` value seen at that rank (Optimal =
  orange, Medium = yellow, Easy = green, Trivial = gray). A recipe has one colour per rank, so
  the latest sample is kept.
- `gray`: the recipe's gray threshold, for step 2's wiki baseline (below). Stored per recipe
  rather than per character because it's a property of the recipe.
- Account-wide rather than `SavedVariablesPerCharacter`, so step 2 (and the estimate) can pool
  characters: the odds don't depend on who crafts. Only `Database.lua` knows this layout, as
  today.
- Migration 2 adds `db.crafts = db.crafts or {}`. Existing `settings` and `nodes` are untouched.

### Recording a craft

1. **Cast starts** (`UNIT_SPELLCAST_START` for the player): if `spellID` is a recipe the client
   knows (`C_TradeSkillUI.GetRecipeInfo(spellID)` returns info), snapshot
   `{ castGUID, recipeID, profession, skillRank, difficulty }` from that recipe info and the
   profession's current rank. Each queued cast gets its own snapshot.
2. **Cast succeeds** (`UNIT_SPELLCAST_SUCCEEDED`, same `castGUID`): add one attempt to the
   snapshot's `levels[skillRank]`, add the items made to `made`, and remember this craft as
   **the last finished craft** of its profession.
3. **Cast fails or is interrupted**: drop the snapshot; nothing is counted.
4. **Skill rises** (the profession's rank, re-read when the client reports skill lines changed,
   is higher than the last rank seen): credit the difference to that profession's **last
   finished craft**, in the `levels` row it was counted in. Never to a cast that has only
   started.

### Crafts at the skill cap *(builder's call)*

A character at the trainer cap (e.g. 75/75) can't gain a point whatever the colour, so such a
cast says nothing about the odds and would drag every estimate at a tier boundary toward 0%.
Capped casts are **not** counted in `attempts`. They are counted in a separate per-row
`capped` field so no craft goes unrecorded (`levels[skillRank] = { attempts, skillUps,
difficulty, capped }`). They still add to `made`.

### Late skill-ups and the next cast's rank *(builder's call)*

If the skill rise from cast N arrives after cast N+1 has started, N+1's start snapshot holds
the old rank (and maybe the old colour), but the server rolled N+1 at the new rank. The goal is
accurate per-craft odds, so **in-flight snapshots are corrected**: when a skill rise is credited
to the last finished craft, every snapshot of that profession still in progress gets its
`skillRank` raised by the same amount and its colour re-read. Whether this case happens at all is
in-game check 3. If it never does, the correction is dead code and can be dropped.

### Secret values

Each value read (cast payload, recipe info, rank) is checked with `issecretvalue`. If any value
the snapshot needs is secret, that cast isn't recorded (`ns.log` says so). Partial rows are never
written.

## Step 2 preview: the wiki baseline (the player's request)

Step 2 shows our observed estimate **next to** the widely cited Vanilla formula as a baseline:
`chance = (gray − skill) / (gray − yellow)`, 100% while orange, 0% once gray. Step 1 stores what
that needs from the client:

- `gray` comes from `recipeInfo.maxTrivialLevel` (in-game check 6).
- `yellow` is **not exposed by the client**. Step 2 needs either a static per-recipe threshold
  table, or a value reconstructed from our own data (the lowest rank at which a recipe was seen
  yellow, where an orange sample exists below it). Step 1's per-rank `difficulty` already makes
  reconstruction possible. Which source to use is an open decision for step 2.

## In-game checks (only the client can answer these)

The design rests on runtime behaviour the source can't show. A dev-only probe
(`addons/ForeverProfessions/Dev/`, do-not-package) checks them in game **before the recorder is
built** *(builder's call)*: the probe is the branch's first commit, the player runs it, and the
recorder is written against the facts it reports, in the same PR. Nothing reaches players until
the checks pass, and no row is ever written from a guessed event order. If check 1 or 2 fails,
the design comes back for revision.

1. A craft's `UNIT_SPELLCAST_*` `spellID` equals the recipe ID that `GetRecipeInfo` accepts.
2. `relativeDifficulty`, the profession rank and the cast payloads are readable (not secret).
3. **Event order during a Create All of several crafts:** where the skill-change signal lands
   relative to the previous cast's SUCCEEDED and the next cast's START.
4. Whether `TRADE_SKILL_ITEM_CRAFTED_RESULT` fires on Forever, with the item quantity, for
   items made.
5. Which rank feeds the colour: base rank, or rank plus racial/item modifier.
6. `maxTrivialLevel` is the rank at which the recipe turns gray (compare it with the colour the
   window shows at that rank).

## Left to the builder

- Which signal detects a skill rise (`SKILL_LINES_CHANGED`, a re-read of the profession info, or
  `CHAT_MSG_SKILL`), and how long a finished craft stays creditable. Choose from check 3's
  results.
- How `made` is measured: the crafted-result event's quantity if check 4 confirms it fires,
  otherwise the recipe's output quantity.
- The character key's exact form and the API that builds it, verified in the Forever source.
- Whether `skillRank` is the base or effective rank (check 5); record whichever matches the
  colour, and say which in the layout comment.
- `ns.log` tags for the recorder, listed in `Core.lua`'s shim comment.
