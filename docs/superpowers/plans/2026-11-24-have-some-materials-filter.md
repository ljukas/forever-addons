# "Have Some Materials" Filter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a "Have Some Materials" checkbox to the professions window's Filter menu that keeps
only recipes where the player owns at least one required reagent.

**Architecture:** One new file, `addons/ForeverProfessions/UI/RecipeFilter.lua`, set up on
`Blizzard_Professions` load like `UI/RecipeOdds.lua`: `Menu.ModifyMenu` adds the checkbox,
`hooksecurefunc(page, "Init")` prunes the list, `hooksecurefunc(Professions, "SetDefaultFilters")`
clears the flag, `hooksecurefunc(dropdown, "ValidateResetState")` shows the reset ✕.

**Tech Stack:** Lua 5.1, Blizzard Menu / TreeDataProvider / ProfessionsUtil.

**Spec:** `docs/superpowers/specs/2026-11-24-have-some-materials-filter-design.md`

## Global Constraints

- No Blizzard function or field overwritten; hooks only. No globals. `ns.log`, never `print`.
- Label "Have Some Materials", in `ns.L` (`HAVE_SOME_MATERIALS`).
- Reagent count: `ProfessionsUtil.GetReagentQuantityInPossession(reagent, true)`.

## Review Focus

- A recipe with only non-Basic slots, or a reagent with a currencyID and no itemID.
- Nested categories: a parent left empty after its children are removed must go too.
- The favorites group holds copies of recipes (`favoritesInstance`); they are pruned like others.
- The orders page shares `MENU_PROFESSIONS_FILTER`: no checkbox there.
- Taint: calling `page:Init` from addon code; the Create button must still work (no
  `ADDON_ACTION_BLOCKED` in the devlog).

## Task 1: The filter

**Files:** Create `addons/ForeverProfessions/UI/RecipeFilter.lua`; modify
`ForeverProfessions.toc` (after `UI/RecipeOdds.lua`), `Core.lua` (`ns.L.HAVE_SOME_MATERIALS`, tag
`FILTER` in the shim comment), `CHANGELOG.md` (Unreleased line).

- [ ] `HasSomeMaterials(recipeID) -> boolean` (pure: schematic → any Basic slot with an owned
      reagent; true when no Basic slot).
- [ ] `Prune(node) -> boolean` (removes failing recipe nodes and childless categories with
      `node:Remove(child, true)`, returns whether `node` still has children); the hook calls it on
      the provider's root, then `provider:Invalidate()` and `NoResultsText:SetShown(provider:IsEmpty())`.
- [ ] Menu checkbox, reset hook, ✕ hook, toggle → `page:Init(page.professionInfo)`.
- [ ] `ns.log("FILTER", ...)`: kept/removed counts per prune.
- [ ] `scripts/lint.sh` clean; commit `feat(foreverprofessions): add a have some materials filter`.

## In-game checks

1. Box appears under "Have Materials"; ticking it hides recipes with 0 of every reagent
   (`FILTER` line: kept/removed).
2. Loot a reagent with the window open: does the list update by itself? (`FILTER` "bags
   changed" followed by a "pruned" line and a "recipe … has some true" flip).
3. The red ✕ (always shown on Forever) clears our box too; does reopening the window clear it?
4. Create still crafts after toggling; `devlog.sh --errors` clean.
