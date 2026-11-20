# RazzhUIQuestXP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A new RazzhUI module that shows the XP of all completed quests, and its share of the current level, as one line of text placed and sized in Edit Mode, with a wordy tooltip.

**Architecture:** The quest and XP-buff logic of the removed ForeverQuests comes back from git history (`git show 060566a^:addons/ForeverQuests/<file>`), feeding a pure function that builds the line and tooltip. A frame with one font string shows it; LibEditMode makes that frame an Edit Mode box with a per-layout store copied from `addons/ForeverCombatText/EditMode.lua`.

**Tech Stack:** Lua 5.1, Forever client API (interface 16001), LibEditMode tag 19 (namespaced, `.pkgmeta` external), RazzhUI core (`RazzhUI.RegisterOptions`).

**Spec:** `docs/superpowers/specs/2026-11-20-razzhuiquestxp-design.md` (and, for the quest rules, `docs/superpowers/specs/2026-11-09-foreverquests-turn-in-xp-design.md`).

## Global Constraints

- One PR: `feat(razzhuiquestxp): show turn-in XP as a line of text`.
- No test suite exists for addon code: every task's check is `scripts/lint.sh` clean, and pure logic stays in functions apart from event and frame code.
- Verify each API in `.cache/wow-ui-source` before first use. Never compare, add or branch on a value before `issecretvalue` has cleared it.
- No globals except `RazzhUIQuestXPDB`. `ns.log`, never `print`. Strings are plain ASCII, in `ns.L`.
- Commit per task: `git add <paths>` (never `-A`) with `git branch --show-current` in the same command.
- Exact copy: line `Quests: +%s XP (%d%%)`; sample `Quests: +4,250 XP (31%)`; defaults `CENTER, 0, -250`, font size 14, slider 8 to 32 step 1; reward wait 5 seconds.

## Review Focus

1. **Text width changes while anchored.** The box is sized to the text; with a saved `RIGHT` or `TOPLEFT` point it must grow from that point and never drift across `/rl`.
2. **Edit Mode with nothing to show.** The sample must appear on entering Edit Mode and the real state must come back on leaving it, including when a quest completes while Edit Mode is open.
3. **Percent over 100 and level-up.** `xp >= max - cur` turns the line green; the percent is of the whole level and may be 100 or more without the line levelling (it can't: gain >= max implies level-up; check the reverse case, a small gain that levels).
4. **Hidden states.** Max level, XP gain disabled, pending reward data, a secret value, zero XP: no line, and the mouse must not be caught by an invisible frame.
5. **A DB from a newer version, or a corrupt entry.** A non-table `text`, an out-of-range `fontSize` or an unknown `point` reads as the default and is never written through.

## Reviewers (Phase 5)

Core (`addon-reviewer`, `api-verifier`, correctness, spec) plus `savedvariables-guard` (new SavedVariables), a UI reviewer (new frame, tooltip, Edit Mode box) and a release reviewer (new `.pkgmeta` external and TOC).

## In-game checks

| # | Check | Shown by |
|---|---|---|
| 1 | Predicted XP equals the XP paid on turn-in | `TURNIN quest <id> xpReward <n> predicted <n>` |
| 2 | The line updates when a quest completes, is turned in or abandoned, without `/rl` | `LINE` (logged on change) |
| 3 | Position and font size survive `/rl`, per layout | `SAVE`, `EDITMODE apply` |
| 4 | Sample in Edit Mode with no completed quests; gone on leaving | by eye, `EDITMODE enter/exit` |
| 5 | Tooltip wording, including level-up | by eye |
| 6 | No errors or blocked actions with the line shown in combat | `scripts/devlog.sh --errors` |

## File structure

```
addons/RazzhUIQuestXP/
  RazzhUIQuestXP.toc   metadata, SavedVariables, load order
  .pkgmeta             LibEditMode external
  CHANGELOG.md
  Core.lua             dev shim, ns.L, ns.OnInitialize, DB load
  Database.lua         layout comment, DB_VERSION, migrations
  XPBonus.lua          known XP buffs (from ForeverQuests, unchanged)
  Quests.lua           completed quests and their XP, events (from ForeverQuests)
  Summary.lua          pure: the line, its colour and the tooltip lines from numbers
  Text.lua             the box, its font string, the tooltip, refresh
  EditMode.lua         LibEditMode box, per-layout store, Font Size slider, sample
  Options.lua          RazzhUI options page with the Edit Mode button
```

---

### Task 1: Scaffold the module and its database

**Files:**
- Create: `addons/RazzhUIQuestXP/{RazzhUIQuestXP.toc,.pkgmeta,CHANGELOG.md,Core.lua,Database.lua}` (start from `scripts/new-addon.sh RazzhUIQuestXP`)
- Modify: `.luacheckrc` (add `files["addons/RazzhUIQuestXP/**"].globals = { "RazzhUIQuestXPDB" }`)

**Interfaces:**
- Produces: `ns.L` (table of strings), `ns.OnInitialize(func)`, `ns.db` (= `RazzhUIQuestXPDB`), `ns.DB.Migrate(db)`, `ns.log`, `ns.dev`, `ns.LibEditMode`.

- [ ] **Step 1:** Run `scripts/new-addon.sh RazzhUIQuestXP`. TOC: `## Title: |cffd6b380RazzhUI|r Quest XP`, `## Notes: Shows how much experience turning in all your completed quests gives, as a line of text you place in Edit Mode.`, `## IconTexture: Interface\Icons\INV_Misc_Book_08`, `## X-Category: Quests`, the two `Libs\LibEditMode\` lines and the file list in the order of "File structure". `.pkgmeta` as ForeverCombatText's with `package-as: RazzhUIQuestXP`. Run `scripts/libs.sh`.
- [ ] **Step 2:** `Core.lua` as ForeverCombatText's (shim, tag list `LOADED / BONUS / XP TURNIN / LINE / SAVE EDITMODE / OPTIONS`, `ns.L`, `ns.OnInitialize`, DB load). `Database.lua`: `DB_VERSION = 1`, migration 1 makes `db.text` a table; layout comment `text = { [key] = { point, x, y, fontSize } }` with ForeverCombatText's key rules.
- [ ] **Step 3:** Create the remaining files empty but valid (`local ADDON_NAME, ns = ...`) so the TOC check passes; `scripts/lint.sh` clean.
- [ ] **Step 4:** Commit `feat(razzhuiquestxp): scaffold the module`.
- [ ] **Step 5 (SavedVariables gate):** dispatch `savedvariables-guard` on the commit; fix or rule on every finding before Task 2.

### Task 2: Quest XP engine

**Files:**
- Create: `addons/RazzhUIQuestXP/XPBonus.lua`, `Quests.lua`, `Summary.lua`

**Interfaces:**
- Produces:
  - `ns.XPBonus.Update() -> boolean`, `ns.XPBonus.Apply(reward) -> number`, `ns.XPBonus.Get() -> percent, names`
  - `ns.Quests.Collect() -> { count, xp, pending, secret }`, `ns.Quests.Invalidate()`; calls `ns.OnQuestsChanged()` (set in Task 3) on the next frame after any relevant event
  - `ns.Summary.Build(count, xp, cur, max, level, bonusPercent, bonusNames) -> { text, levelsUp, lines } | nil`, where `lines` is a list of `{ text, color }`. Returns nil when `count == 0`, `xp <= 0` or `max <= 0`. Pure: its only client calls are `BreakUpLargeNumbers` and the colour constants.

- [ ] **Step 1:** Restore `XPBonus.lua` and `Quests.lua` from `060566a^` unchanged apart from header comments (ExpBar.lua is gone: "set by Text.lua"). Re-verify every API they call in `.cache/wow-ui-source`.
- [ ] **Step 2:** `Summary.Build`. Line percent is `floor(xp * 100 / max)`. `levelsUp` is `cur + xp >= max`. Tooltip lines, in order: `Completed quests: %d (+%s XP)`; `That is %d%% of level %d (%s XP).` (highlight colour; `%s` is `max`); grey `Includes +%d%% from %s` when `bonusPercent > 0`; then `Ends at %d%% of level %d` (`floor((cur + xp) * 100 / max)`, highlight) or green `Level up!` and, when the overflow is positive, green `+%s XP past level %d` (`level + 1`).
- [ ] **Step 3:** Check `Build` by reading against: (2, 4250, 1000, 13700, 23, 0, {}) -> `Quests: +4,250 XP (31%)`, not levelling, `Ends at 38% of level 23`; (1, 500, 13500, 13700, 23, 3, {"Well-Rested"}) -> `(3%)`, levels, `+300 XP past level 24`; (0, ...) -> nil.
- [ ] **Step 4:** `scripts/lint.sh` clean; commit `feat(razzhuiquestxp): collect completed quests' XP`.

### Task 3: The text box and tooltip

**Files:**
- Create: `addons/RazzhUIQuestXP/Text.lua`

**Interfaces:**
- Consumes: Task 2's `Collect`, `XPBonus.Get`, `Summary.Build`.
- Produces: `ns.Text.holder` (Frame), `ns.Text.DEFAULTS = { point = "CENTER", x = 0, y = -250, fontSize = 14 }`, `ns.Text.SetLayout({ point, x, y, fontSize })`, `ns.Text.SetSample(boolean)`, `ns.Text.Refresh()`; sets `ns.OnQuestsChanged = ns.Text.Refresh`.

- [ ] **Step 1:** `holder` on `UIParent` with one `GameFontNormal` font string anchored `CENTER`; `SetLayout` re-anchors the holder and sets the font size (face and flags from `GameFontNormal:GetFont()`), then resizes the holder to the string.
- [ ] **Step 2:** `Refresh`: no summary when `IsXPUserDisabled()`, `IsPlayerAtEffectiveMaxLevel()`, `pending`, `secret`, or `UnitXP`/`UnitXPMax` secret. With a summary: text, gold or green, shown. Without: the sample (gold, no tooltip lines but one explaining line `Shown here while Edit Mode is open.`) when sampling, else hidden. `ns.dev:LogChanged("line", ..., "LINE", ...)`.
- [ ] **Step 3:** `OnEnter` shows `GameTooltip` (`SetOwner(holder, "ANCHOR_TOP")`, title `Quest turn-ins`, the summary's lines); `OnLeave` hides it. A hidden holder takes no mouse.
- [ ] **Step 4:** `scripts/lint.sh` clean; commit `feat(razzhuiquestxp): show the turn-in XP line and its tooltip`.

### Task 4: Edit Mode box, font size and options page

**Files:**
- Create: `addons/RazzhUIQuestXP/EditMode.lua`, `Options.lua`

**Interfaces:**
- Consumes: `ns.Text.holder`, `DEFAULTS`, `SetLayout`, `SetSample`; `ns.db.text`.

- [ ] **Step 1:** `EditMode.lua` from ForeverCombatText's: same `Key`/`Store`/`Get`/`Save`/`Apply`, layout callbacks (`layout`, `create`, `rename`, `delete`) and validation, with fields `point, x, y, fontSize` and one slider (`Font Size`, 8 to 32, step 1). Box name `Quest XP`. `enter` -> `ns.Text.SetSample(true)`, `exit` -> `SetSample(false)`. If `LEM:IsInEditMode()` at init, sample at once.
- [ ] **Step 2:** `Options.lua` as ForeverCombatText's, with this module's strings.
- [ ] **Step 3:** `scripts/lint.sh` clean; commit `feat(razzhuiquestxp): place and size the line in Edit Mode`.

### Task 5: Changelog and docs

**Files:**
- Modify: `addons/RazzhUIQuestXP/CHANGELOG.md`

- [ ] **Step 1:** Players' line under `## Unreleased`: what the line shows, the tooltip, Edit Mode placement and font size, per layout.
- [ ] **Step 2:** `stylua addons template types`, `scripts/lint.sh`; commit `docs(razzhuiquestxp): add the changelog entry`.
