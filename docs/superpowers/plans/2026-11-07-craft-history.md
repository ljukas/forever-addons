# Craft History Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** ForeverProfessions records every craft per character, per recipe and per skill level (attempts, skill-ups, colour, capped casts), plus items made and the recipe's gray level.

**Architecture:** A dev-only probe first reports the facts the recorder depends on (event order, secrecy, IDs). The recorder (`Sources/CraftRecorder.lua`) then follows `Sources/GatherRecorder.lua`'s pattern: per-cast snapshots keyed by `castGUID`, written through `ns.DB` (migration 2). No UI in this step.

**Tech Stack:** Lua 5.1, Forever's modern addon API (`C_TradeSkillUI`, `UNIT_SPELLCAST_*`), ForeverDev logging (`scripts/devlog.sh`).

**Spec:** `docs/superpowers/specs/2026-11-07-craft-history-design.md`

## Global Constraints

- Interface 16001; every new Lua file listed in `ForeverProfessions.toc`.
- `local ADDON_NAME, ns = ...`; no new globals.
- Never compare, do arithmetic on or branch on a secret value: `issecretvalue` first.
- Dev-only code in `Dev/`, starts with `if not ns.dev.enabled then return end`, listed in the TOC between `#@do-not-package@` lines (`.pkgmeta` already ignores `Dev`).
- `ns.log(TAG, ...)`, never `print`; tags listed in `Core.lua`'s shim comment.
- `scripts/lint.sh` clean after every task; one conventional commit per task.
- There is no automated test suite for addon code: verification is lint plus the in-game devlog. Keep pure logic (rank correction, cap rule) in plain functions a reviewer can check by reading.

## Review Focus

1. **Create All queue:** N queued crafts → exactly N attempts, each at its own start-of-cast rank and colour; a skill-up lands on the craft that finished, never the one starting.
2. **Interrupted craft** (moving, `/stopcasting`, closing the window mid-queue) → no attempt counted, no snapshot left behind that later absorbs a skill-up.
3. **Craft at the skill cap** (rank == max rank) → counted in `capped`, not `attempts`.
4. **Non-recipe casts** (gathering, Hearthstone, spells, enchanting an item with no window) → nothing recorded, no Lua error when `GetRecipeInfo` returns nil.
5. **Existing players' saved data:** migration 2 leaves `settings` and `nodes` untouched and works on a fresh DB and on a version-1 DB.

---

### Task 1: Craft probe (dev-only)

Answers the spec's in-game checks 1–6. Ships nothing to players.

**Files:**
- Create: `addons/ForeverProfessions/Dev/CraftProbe.lua`
- Modify: `addons/ForeverProfessions/ForeverProfessions.toc` (append a `#@do-not-package@` block with `Dev/CraftProbe.lua` after `UI/MinimapPins.lua`)
- Modify: `addons/ForeverProfessions/Core.lua` (shim comment: `CRAFT  Dev/CraftProbe.lua`)

**Interfaces:**
- Consumes: `ns.dev`, `ns.log` (Core.lua).
- Produces: nothing for later tasks except devlog lines tagged `CRAFT`.

- [ ] **Step 1: Write `Dev/CraftProbe.lua`.** Each log line starts with a per-session sequence number and `GetTime()` to 3 decimals, so the event order is readable. Log only while a recipe cast is live, or within 5 s of the last one, except where stated:
  - `UNIT_SPELLCAST_START` (player): `start castGUID spellID`, then `C_TradeSkillUI.GetRecipeInfo(spellID)` → `isRecipe`, `relativeDifficulty`, `maxTrivialLevel`, `numSkillUps`, `canSkillUp`; and `C_TradeSkillUI.GetProfessionInfoByRecipeID(spellID)` → `professionID`, `professionName`, `skillLevel`, `skillModifier`, `maxSkillLevel`. Skip non-recipes (no recipe info) after one `LogOnce` per spellID. Guard `spellID` with `issecretvalue` before calling.
  - `UNIT_SPELLCAST_SUCCEEDED / FAILED / INTERRUPTED / STOP` (player), for live recipe casts: event name and `castGUID`.
  - `TRADE_SKILL_CRAFT_BEGIN`: `recipeSpellID`. `TRADE_SKILL_ITEM_CRAFTED_RESULT`: `data.itemID`, `data.quantity`.
  - `SKILL_LINES_CHANGED` (always): re-read the last recipe's profession info and log `skillLevel` with `ns.dev:LogChanged(professionName, skillLevel, ...)`.
  - `CHAT_MSG_SKILL` (always): `text`.
- [ ] **Step 2: TOC and Core.lua shim comment** as listed under Files.
- [ ] **Step 3: Lint.** Run `scripts/lint.sh`. Expected: clean.
- [ ] **Step 4: Commit.** `git add addons/ForeverProfessions/Dev/CraftProbe.lua addons/ForeverProfessions/ForeverProfessions.toc addons/ForeverProfessions/Core.lua && git branch --show-current && git commit -m "chore(foreverprofessions): probe crafting events and skill-ups"`
- [ ] **Step 5: In-game run (the player).** `scripts/worktree.sh game`; the player `/rl`s, crafts one recipe singly, then a Create All of 5+ of an orange or yellow recipe (ideally one that gives several skill-ups), interrupts one craft by moving, then `/rl`. Read with `scripts/devlog.sh --addon ForeverProfessions --tag CRAFT` and `scripts/devlog.sh --errors`.
- [ ] **Step 6: Record the answers** to checks 1–6 in the spec under a new "Probe results" section, and revise Tasks 2–4 below if any answer contradicts them. **Gate: Tasks 2–4 start only after this step.**

### Task 2: Saved layout, migration 2

**Files:** Modify `addons/ForeverProfessions/Database.lua` (layout comment, `DB_VERSION = 2`, `migrations[2]`, and the write functions below).

**Interfaces:**
- Produces: `ns.DB.RecordAttempt(characterKey, recipeID, skillRank, difficulty, gray, capped)` (adds 1 to `attempts`, or to `capped` when `capped`; sets `difficulty` and `gray`), `ns.DB.AddMade(characterKey, recipeID, quantity)`, and `ns.DB.RecordSkillUp(characterKey, recipeID, skillRank, points)`.
- Layout exactly as the spec's "Saved layout", with rows `{ attempts, skillUps, difficulty, capped }`.

- [ ] Implement; lint; commit `feat(foreverprofessions): store craft history`.
- [ ] **SavedVariables gate:** dispatch `savedvariables-guard` on this commit; fix or rule on every finding before Task 3.

### Task 3: Craft recorder

**Files:** Create `addons/ForeverProfessions/Sources/CraftRecorder.lua` (TOC: after `Sources/GatherRecorder.lua`); Core.lua shim comment gets the recorder's tags.

**Interfaces:**
- Consumes: Task 2's `ns.DB.RecordAttempt`, `ns.DB.RecordSkillUp`.
- Behaviour, fixed by the spec's "Probe results":
  - Snapshot on `UNIT_SPELLCAST_START` (player) when `C_TradeSkillUI.GetRecipeInfo(spellID)` returns info: `{ recipeID, professionID, skillRank = info.skillLevel, maxRank = info.maxSkillLevel, difficulty = recipe.relativeDifficulty, gray = recipe.maxTrivialLevel }` from `GetProfessionInfoByRecipeID`. Any of those secret → don't snapshot, `ns.log("SECRET", ...)`.
  - `UNIT_SPELLCAST_SUCCEEDED` with the snapshot's `castGUID` → `ns.DB.RecordAttempt(...)` with `made = 0`, `capped = skillRank >= maxRank`; the snapshot becomes `lastFinished[professionID]`, and `lastKnownRank[professionID] = skillRank`.
  - `UNIT_SPELLCAST_FAILED` / `INTERRUPTED` → drop the snapshot.
  - `TRADE_SKILL_ITEM_CRAFTED_RESULT` → add `data.quantity` to the most recently finished craft's `made` (new `ns.DB.AddMade(characterKey, recipeID, quantity)` in Task 2).
  - `SKILL_LINES_CHANGED` → for each `lastFinished` profession, re-read `skillLevel` by its recipe; if higher than `lastKnownRank`, `ns.DB.RecordSkillUp` the difference on that craft's row, then update `lastKnownRank`. If a snapshot of that profession is in flight at that moment, `ns.dev:LogOnce("late", "LATE", ...)`; no correction.
  - Character key: `UnitName("player") .. "-" .. GetNormalizedRealmName()`; verify both in the Forever source first.
  - Tags: `CRAFTED`, `SKILLUP`, `SECRET`, `LATE`.

- [ ] Implement; lint; commit `feat(foreverprofessions): record every craft and its skill-ups`.

### Task 4: Changelog

- [ ] Add under `## Unreleased` in `addons/ForeverProfessions/CHANGELOG.md` a player-facing line: crafts and skill-ups are now remembered per character, for the upcoming recipe statistics. Commit `docs(foreverprofessions): note craft history in changelog`.

Then Phase 5 review (core reviewers + `savedvariables-guard`) and Phase 6 in-game verification with the same steps as Task 1 Step 5, checking `scripts/observed.sh`/the saved `crafts` table.
