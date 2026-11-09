# Skill-up odds Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show the player's own skill-up chance, the wiki baseline and their craft counts under
Reagents in the Forever professions window, and a % at the end of each recipe row.

**Architecture:** `Database.lua` gains read functions over `crafts` and announces writes with a
`CraftsChanged` callback. A new pure `Odds.lua` does the math (learn the yellow level, wiki
baseline, pooled estimate). A new `UI/RecipeOdds.lua` hooks the crafting page's schematic form
(`hooksecurefunc` on the instance's `Init`) and recipe list (`ScrollUtil.AddInitializedFrameCallback`)
and owns its font strings.

**Tech Stack:** Lua 5.1, the Forever (Midnight 12.x) addon API. No test suite in the repo; the
pure math is checked with a throwaway LuaJIT script in the scratchpad (not committed).

**Spec:** `docs/superpowers/specs/2026-11-09-skillup-odds-design.md`

## Global Constraints

- No SavedVariables change; only `Database.lua` indexes `ns.db.crafts`.
- No writes to Blizzard frames or tables, no replaced methods, no re-anchoring Blizzard widgets.
- Pool window ±5 ranks (`ns.Odds.WINDOW = 5`); list shows ours at ≥ 5 crafts (`ns.Odds.LIST_MIN_CRAFTS = 5`).
- Skill = base `skillLevel` from `C_TradeSkillUI.GetProfessionInfoByRecipeID`; every value read is `issecretvalue`-checked.
- Strings in `ns.L`; new log tag `ODDS` listed in `Core.lua`'s shim comment.
- `scripts/lint.sh` clean after every task.

## Review Focus

1. Recipes with no rows at all, or rows only of another colour: no estimate, wiki from colour alone (100% orange / "?" yellow-green).
2. Junk rows (orange recorded above the first yellow; recipe IDs of profession spells): ignored, never crash.
3. At the skill cap: "At skill cap" in the schematic, nothing in the list.
4. A craft recorded while the window is open: both displays refresh; the list refresh must cope with category rows and recycled frames.
5. Gray recipe or `canSkillUp == false`: no list %, schematic says 0% (wiki).

---

### Task 1: Database reads and the CraftsChanged event

**Files:**
- Modify: `addons/ForeverProfessions/Core.lua` (events list, `ns.GetCharacterKey`)
- Modify: `addons/ForeverProfessions/Database.lua`
- Modify: `addons/ForeverProfessions/Sources/CraftRecorder.lua` (use `ns.GetCharacterKey`)

**Interfaces — Produces:**
- `ns.GetCharacterKey() -> string|nil` (moved verbatim from CraftRecorder, behaviour unchanged).
- `ns.DB.GetCraftTotals(characterKey, recipeID) -> crafts, skillUps` (crafts = Σ attempts + Σ capped; 0, 0 when none).
- `ns.DB.GetCraftRows(recipeID) -> { { rank, attempts, skillUps, difficulty }, ... }` across all characters (named fields `rank`, `attempts`, `skillUps`, `difficulty`).
- `ns.callbacks` event `CraftsChanged(recipeID)`, fired by `RecordAttempt` and by a successful `RecordSkillUp`.

- [ ] Implement; lint; commit `feat(foreverprofessions): read craft history for skill-up odds`.

Step reviewers (Phase 5): the four core reviewers plus a **UI reviewer** (hooks into Blizzard's
professions window). No SavedVariables change, so no `savedvariables-guard` unless the diff
touches the layout.

### Task 2: Odds math

**Files:** Create `addons/ForeverProfessions/Odds.lua`; add to TOC after `Database.lua`.

**Interfaces — Produces** (`D` = `Enum.TradeskillRelativeDifficulty`; chances are fractions 0–1):
- `ns.Odds.LearnYellow(rows, skill, difficulty) -> lo, hi | nil` — the live (skill, difficulty) counts as one more sample. `Y` = lowest Medium rank; `O` = highest Optimal rank below `Y`; returns `O + 1, Y`, or nil without both.
- `ns.Odds.Wiki(skill, difficulty, gray, lo, hi) -> low, high | nil` — Optimal → 1, 1; Trivial → 0, 0; else nil without `lo` or when `gray <= hi`; else `(g−s)/(g−lo)`, `(g−s)/(g−hi)` each clamped to 0–1.
- `ns.Odds.Ours(rows, skill, difficulty) -> p, n | nil` — rows with `|rank − skill| ≤ WINDOW` and same difficulty; nil when `n == 0`; `p` clamped to ≤ 1.

- [ ] **Step 1: scratch test** (`<scratchpad>/odds_test.lua`, loads `Odds.lua` with a stub `ns` and `Enum`), asserting:
  - recipe 3929 rows (Optimal 79–84, Medium 85) → `LearnYellow` = 85, 85; `Wiki(85, Medium, 95, 85, 85)` = 1, 1; `Wiki(90, …)` = 0.5, 0.5.
  - gap: Optimal 80, Medium 84 → 81, 84; `Wiki(86, Medium, 95, 81, 84)` ≈ 9/14, 9/11.
  - no Optimal below → nil; Optimal at 90 above Medium 85 is ignored (still needs one below).
  - live sample: rows Optimal ≤ 84, no Medium, `LearnYellow(rows, 85, Medium)` = 85, 85.
  - `Ours`: rows {84 Medium 2/1, 86 Medium 3/1, 92 Medium 5/5, 85 Optimal 1/1} at 86 Medium → 2/5, 5; skillUps 3 of 2 attempts → p = 1; no matching rows → nil.
  - Optimal → 1,1 and Trivial → 0,0 regardless of `lo`.
- [ ] **Step 2:** run `luajit <scratchpad>/odds_test.lua` → fails (no file).
- [ ] **Step 3:** implement `Odds.lua`.
- [ ] **Step 4:** run → prints `ok`.
- [ ] **Step 5:** lint; commit `feat(foreverprofessions): estimate skill-up odds from craft history`.

### Task 3: The professions window

**Files:** Create `addons/ForeverProfessions/UI/RecipeOdds.lua`; add to TOC after `UI/MinimapPins.lua`; `Core.lua` (`ns.L` strings, `ODDS` tag).

**Interfaces — Consumes:** Tasks 1–2. Frames: `ProfessionsFrame.CraftingPage.SchematicForm` (`Init(recipeInfo)`, `Reagents`, `OptionalReagents`, `GetRecipeInfo()`), `ProfessionsFrame.CraftingPage.RecipeList.ScrollBox` (row element data is a tree node; `node:GetData().recipeInfo`, absent on category rows).

- [ ] Load inside `EventUtil.ContinueOnAddOnLoaded("Blizzard_Professions", …)`, registered from `ns.OnInitialize`.
- [ ] Shared `Read(recipeID)` returns the inputs (fresh `C_TradeSkillUI.GetRecipeInfo`, profession info) or nil when missing/secret/not learned; logs `ODDS` via `ns.dev:LogChanged("odds " .. recipeID, …)` with skill, `skillModifier`, difficulty, gray, yellow lo/hi, ours, wiki (built only when `ns.dev.enabled`).
- [ ] Schematic: one `GameFontHighlightSmall` font string on the form, wrapped at 325 px, `TOPLEFT` under `OptionalReagents` if shown else `Reagents` (y −10), hidden when `Reagents` is hidden. Text per spec: "Crafted %d times, %d skill-ups" (singulars) / "Not crafted yet"; "Chance at %d: " + "62% (yours, 13 crafts)" · "70% (wiki)" / "60–75% (wiki)" / "? (wiki)"; "At skill cap". Labels in `NORMAL_FONT_COLOR`.
- [ ] List: per row (addon-side table keyed by frame) a right-aligned `GameFontHighlightSmall` at `RIGHT -4, 0`; shown only when `canSkillUp`, not Trivial, not capped. Ours (n ≥ 5) in the difficulty colour (`DIFFICULT/FAIR/EASY_DIFFICULTY_COLOR`), else wiki in `DISABLED_FONT_COLOR`; a wiki range shows `~` + rounded midpoint *(builder's call)*.
- [ ] `CraftsChanged`: refresh the schematic when shown, and `ScrollBox:ForEachFrame` rows.
- [ ] Lint; commit `feat(foreverprofessions): show skill-up odds in the professions window`.

### Task 4: Changelog

- [ ] Players' line under `## Unreleased`; commit `docs(foreverprofessions): note skill-up odds in changelog`.

## In-game checks (Phase 6)

From the spec: layout under Reagents (1, 2, 4+ reagents), list column vs long names and `[count]`,
`ODDS` lines vs saved rows (recipe 3929 → yellow 85), refresh after a craft, `devlog.sh --errors`
clean with no `ADDON_ACTION_BLOCKED` while crafting, and `skillModifier` 0 in every `ODDS` line.
