# RazzhUIPowershift Implementation Plan

> **Superseded on 20 November 2026.** The page hold below was built and tested in game: the bar held, but the client still refused the form abilities. The module now does the powershift itself in two steps from one key (the spec has the design; `Shift.lua` and `Bindings.xml` replace `Hold.lua`). Kept for the record.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep EllesmereUI's action bar 1 on the form's page for the three seconds after a powershift in which the client reports no form.

**Architecture:** A hidden secure click button arms a hold (an attribute on EllesmereUI's bar frame) from the player's macro. A secure wrap on that frame's `OnAttributeChanged` cancels the bar's page handler while the hold is set and the client reports no form. Insecure code only watches, logs and releases stale holds out of combat.

**Tech Stack:** Lua 5.1, `SecureHandlerClickTemplate`, `SecureHandlerWrapScript`, `Settings` through `RazzhUI.RegisterOptions`.

**Spec:** `docs/superpowers/specs/2026-11-20-razzhuipowershift-design.md`

**Execution:** inline in this session (two small files that share one attribute name).

## Global Constraints

- Interface 16001; a RazzhUI module (`## Dependencies: RazzhUI`, `## Group: RazzhUI`, title `|cffd6b380RazzhUI|r Powershift`).
- No SavedVariables, no slash command, no globals except the frame name `RazzhUIPowershiftHold`.
- No protected call in combat: setup and release check `InCombatLockdown()`.
- Names fixed by the spec: button `RazzhUIPowershiftHold`, bar `EABBar_MainBar`, attribute `razzhuipowershift-hold`, EllesmereUI's frame ref `blizzmainbar`, state attribute `state-page`.

## Review Focus

1. A hold that outlives the powershift (failed recast in combat): the bar must come right on the next form change and on leaving combat.
2. Vehicle, override, possess and temporary shapeshift bars must never be blocked by a hold.
3. `/reload` in combat: setup must wait for `PLAYER_REGEN_ENABLED`, and run once.
4. EllesmereUI absent or its bar frame unprotected: the module does nothing and says so on its options page.
5. Taint: the wrap and the frame ref are set out of combat only; nothing calls into insecure code from a snippet.

## Tasks

### Task 1: Scaffold and the hold

**Files:** `addons/RazzhUIPowershift/RazzhUIPowershift.toc`, `Core.lua` (dev shim only), `Hold.lua`, `.pkgmeta`.

**Produces:** `ns.Hold.status` (`"waiting"`, `"ready"` or `"nobar"`), and the `HOLD` log tag: `setup <status>`, `set <page>`, `cleared`, `released <reason>`.

- [ ] `scripts/new-addon.sh RazzhUIPowershift`; drop the SavedVariables line and the DB code; notes and icon in the TOC.
- [ ] `Hold.lua`: the button with its `_onclick` snippet, the wrap's pre-body, setup on `PLAYER_ENTERING_WORLD` / `PLAYER_REGEN_ENABLED`, and the release on `UNIT_DISPLAYPOWER` / `PLAYER_REGEN_ENABLED` when the power type is mana. Snippet logic is the spec's "Design" section, line for line.
- [ ] `scripts/lint.sh` clean; commit `feat(razzhuipowershift): hold bar 1's page through a powershift`.

### Task 2: Options page and changelog

**Files:** `addons/RazzhUIPowershift/Options.lua`, `CHANGELOG.md`, TOC.

**Consumes:** `ns.Hold.status`.

- [ ] `Options.lua`: on the first `PLAYER_ENTERING_WORLD`, after the hold's setup attempt, a page with section headers: how to use it, the macro line `/click RazzhUIPowershiftHold`, and whether EllesmereUI's bar was found.
- [ ] `CHANGELOG.md`: a players' line under `## Unreleased`.
- [ ] `scripts/lint.sh` clean; commit.

### Task 3: Review and verify

- [ ] Step review per `docs/feature-workflow.md` Phase 5 (`addon-reviewer`, `api-verifier`, correctness and spec reviewers).
- [ ] In-game checks 1 to 6 from the spec, with `scripts/devlog.sh --tag FORM` and `--tag HOLD`.
