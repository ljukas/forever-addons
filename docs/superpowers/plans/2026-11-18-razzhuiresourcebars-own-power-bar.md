# RazzhUIResourceBars Own Power Bar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** ForeverUnitFrames becomes the RazzhUI module RazzhUIResourceBars, whose power bar is a status bar of ours fed from the player's power, with numbers of its own and nothing of Blizzard's player frame touched.

**Architecture:** `PowerBar.lua` keeps its holder, background, border and `fill`, and feeds `fill` from `UnitPower`/`UnitPowerMax` on the player's power events; art comes from `UnitPowerType` and `PowerBarColor` through one pure function. `PowerText.lua` puts three font strings on the holder and fills them through `SetFormattedText`. Everything that reached into `PlayerFrame` is deleted.

**Tech Stack:** Lua 5.1, WoW Forever client API (interface 16001), LibEditMode tag 19 (`.pkgmeta` external), the RazzhUI core (`## Dependencies`).

**Spec:** `docs/superpowers/specs/2026-11-18-razzhuiresourcebars-own-power-bar-design.md`; decision record `docs/adr/0005-draw-the-player-power-bar-ourselves.md`.

One step, one PR, built on `main` before roadmap step 2: `feat(razzhuiresourcebars)!: draw the power bar ourselves`.

There is no automated test suite for addon code. Each task's check is `scripts/lint.sh` (StyLua, LuaLS against the Forever source, TOC checks) plus the `ns.log` lines the in-game checks read.

## Global Constraints

- No code reads, hooks, re-parents or writes anything of `PlayerFrame` or its bars. `PlayerFrame` and `PlayerFrame_GetManaBar` appear nowhere in the addon when the step is done.
- Power values (`UnitPower`, `UnitPowerMax`, `UnitPowerPercent`, and `AbbreviateLargeNumbers` of them) are secret: they go from the API into `SetValue`, `SetMinMaxValues` or `SetFormattedText` and nowhere else. Never compare, add, concatenate, `tostring`, branch on or log them.
- `UnitPowerType("player")` may return nothing (`MayReturnNothing`); every use copes with a nil type and token.
- No special case for another addon by name.
- Lua 5.1; every file starts `local ADDON_NAME, ns = ...`; the only global is `RazzhUIResourceBarsDB`.
- `ns.log` tags when done: `LOADED` (Core.lua), `POWER` (PowerBar.lua, PowerText.lua), `OFFFORM` (OffFormPower.lua), `SAVE` `EDITMODE` (EditMode.lua).
- `scripts/lint.sh` clean after every task; commit with `git add <paths>` (never `-A`) and `git branch --show-current` in the same command. Branch: `feat/razzhuiresourcebars-own-power-bar`.

## Review Focus

1. Secret values: is every power value only ever handed to a widget? A compare, `..`, `%d` through `string.format`, `tostring` or log of one is a bug.
2. Leftovers: any hook, script or field access on Blizzard's player frame or its bars; any use of `ns.Layout`, `ns.HealthBar`, `barOutset`, `maskOutset`.
3. Login and `/reload`: `UnitPowerType` returning nothing before the world loads; the first fill before Edit Mode's layouts have arrived; a login while in Bear Form.
4. Saved data: an entry without `text`, an invalid `text`, a DB from a newer version, a file carried over from `ForeverUnitFramesDB` by the spec's command.
5. The druid row: still parented to the border, same outsets as before the change, its slide still clipped at the power bar's top edge now that the border is always shown.
6. Mouse: in "On Mouse-over" the bar takes mouse motion; clicks reach the world in every mode, and the Edit Mode selection still drags.

## In-game checks

The spec's table. Instrumentation: `POWER type <token> <atlas>` (`LogChanged` on the token), `POWER dead <bool>` (`LogChanged`), `POWER text <mode>` (on every mode change), `POWER holder ...` as today, `SAVE`, `EDITMODE`, `OFFFORM` unchanged.

## Step reviewers

Core four (`addon-reviewer`, `api-verifier`, correctness, spec), plus `savedvariables-guard` (the SavedVariables name and the new `text` field), the UI reviewer (frames, font strings, Edit Mode dropdown) and the release reviewer (TOC, `.pkgmeta`). Task 3 is the last task that touches the saved layout, so the Phase 5 `savedvariables-guard` run directly after it is also the mid-step gate.

## File structure

| File (under `addons/RazzhUIResourceBars/`) | After this step |
|---|---|
| `RazzhUIResourceBars.toc` | renamed; module lines; lists `PowerText.lua`; no `Layout.lua`, `HealthBar.lua`, `Dev\ArtProbe.lua` |
| `Core.lua` | `RazzhUIResourceBarsDB`; tag list; new `ns.L` strings |
| `Database.lua` | layout comment: new name, `text` field |
| `PowerBar.lua` | rewritten: own values, art, dead look |
| `PowerText.lua` | new: the numbers |
| `OffFormPower.lua` | reads `ns.PowerBar.fillOutset.left/right` |
| `EditMode.lua` | `text` in `VALID`, `Apply`, a dropdown |
| `Snap.lua`, `.pkgmeta`, `CHANGELOG.md` | names only; changelog rewritten in Task 4 |
| `Layout.lua`, `HealthBar.lua`, `Dev/ArtProbe.lua` | deleted |

---

### Task 1: Rename to RazzhUIResourceBars

**Files:**
- Move: `addons/ForeverUnitFrames/` -> `addons/RazzhUIResourceBars/` (`git mv`), and inside it `ForeverUnitFrames.toc` -> `RazzhUIResourceBars.toc`
- Modify: the TOC, `Core.lua`, `Database.lua`, `EditMode.lua` (comments naming the DB), `.pkgmeta`, `CHANGELOG.md` (title line only)
- Modify: `.luacheckrc:82-85`, `addons/ForeverCombatText/EditMode.lua:7` (comment), `CLAUDE.md:101`, `docs/superpowers/roadmaps/2026-11-17-forever-enhanced-suite.md:12`, `docs/adr/0002-detach-the-player-power-bar-by-reparenting-blizzards-bar.md` (status line)

**Interfaces:**
- Produces: the global `RazzhUIResourceBarsDB` (same layout as `ForeverUnitFramesDB` v1), `ADDON_NAME == "RazzhUIResourceBars"`.

- [ ] **Step 1: Move the folder and the TOC** with `git mv`. `Libs/` is gitignored and stays behind in the old folder; run `scripts/libs.sh` afterwards so `Libs/LibEditMode` exists in the new one, then remove the now-empty old folder's leftovers (only the fetched library; look before deleting).

- [ ] **Step 2: Edit the TOC header**

```
## Title: |cffd6b380RazzhUI|r Resource Bars
## Notes: Your power bar (mana, rage, energy) as a bar of its own that you place and size in Edit Mode, with a druid's other powers in a row above it.
## SavedVariables: RazzhUIResourceBarsDB
## Dependencies: RazzhUI
## Group: RazzhUI
```

`## Category: Forever Enhanced Addons` and `## X-Category: Unit Frames` stay (as in `addons/ForeverTooltip/ForeverTooltip.toc`).

- [ ] **Step 3: Rename the DB global** in `Core.lua` (two uses and a comment), the comments in `Database.lua` and `EditMode.lua`, `package-as` in `.pkgmeta`, the changelog's `# ` title, and the `.luacheckrc` entry (path and `RazzhUIResourceBarsDB`; `SLASH_FOREVERUNITFRAMES_ART1` stays until Task 2 deletes the probe).

- [ ] **Step 4: Update the references outside the addon:** the comment in `addons/ForeverCombatText/EditMode.lua`; CLAUDE.md's module sentence (ForeverTooltip and RazzhUIResourceBars are modules; the others follow in step 2); the roadmap's step 2 row (the Edit Mode page is for RazzhUIResourceBars); ADR 0002's status: `accepted; decision 1 superseded by ADR 0005 (2026-11-18)`.

- [ ] **Step 5: Verify**

Run: `scripts/lint.sh`
Expected: `All checks passed.` (lint's module check accepts the title, dependency and group together.)
Run: `grep -rn "ForeverUnitFrames" addons .luacheckrc CLAUDE.md scripts`
Expected: no output.

- [ ] **Step 6: Commit** `refactor(razzhuiresourcebars)!: rename ForeverUnitFrames to RazzhUIResourceBars`, with a `BREAKING CHANGE:` footer saying saved bar positions don't follow the new name by themselves.

---

### Task 2: Draw the bar ourselves

**Files:**
- Rewrite: `addons/RazzhUIResourceBars/PowerBar.lua`
- Delete: `Layout.lua`, `HealthBar.lua`, `Dev/ArtProbe.lua` (and the `Dev/` line and its do-not-package block in the TOC; the `OptionalDeps` block stays)
- Modify: the TOC file list, `Core.lua` (tag list), `OffFormPower.lua:232`, `.luacheckrc` (drop the slash global), `.pkgmeta` (drop the `ignore: Dev` entry and its comment)

**Interfaces:**
- Consumes: nothing new.
- Produces (all on `ns.PowerBar`):
  - kept: `DEFAULTS`, `holder`, `border`, `CreateBackground(frame) -> Texture`, `Interpolation() -> Enum.StatusBarInterpolation`, `SetLayout(layout)` with `layout = { point, x, y, width, height, smooth }`
  - `fillOutset = { left = 2, right = 3 }` (replaces `barOutset`, `fillOutset.right`, `maskOutset`)
  - `Art(powerToken, altR, altG, altB) -> atlas, r, g, b`: pure; `powerToken` may be nil
  - `OnChanged(func)`: `func(powerType, powerToken)` runs after every update of the fill's values or power type (`powerType` may be nil); Task 3's numbers hang on it
  - removed: `Request`, `barOutset`, `maskOutset`

- [ ] **Step 1: Write `Art`.** Rules, in order, with `info = powerToken and PowerBarColor[powerToken]`:

| Case | Returns |
|---|---|
| `info.atlasElementName` | `"UI-HUD-UnitFrame-Player-PortraitOn-Bar-" .. info.atlasElementName`, 1, 1, 1 |
| `info.atlas` | `info.atlas`, 1, 1, 1 |
| no `info`, `altR` given | `"UI-HUD-UnitFrame-Player-PortraitOn-Bar-Mana-Status"`, `altR, altG, altB` |
| `info.r` | the same Mana-Status atlas, `info.r, info.g, info.b` |
| otherwise (nil token, unknown token) | `"UI-HUD-UnitFrame-Player-PortraitOn-Bar-Mana"`, 1, 1, 1 |

Worked examples for the reviewer: `Art("RAGE")` -> `...-Bar-Rage`, white; `Art("LUNAR_POWER")` -> `Unit_Druid_AstralPower_Fill`, white; `Art("COMBO_POINTS")` -> Mana-Status, 1.00/0.96/0.41; `Art("X", 0.2, 0.4, 0.6)` -> Mana-Status, 0.2/0.4/0.6; `Art(nil)` -> `...-Bar-Mana`, white.

- [ ] **Step 2: Rewrite the frames.** Holder strata `"LOW"`; background, border and `fill` as today; `fill` anchored `TOPLEFT` of the holder at `-fillOutset.left` and `BOTTOMRIGHT` at `+fillOutset.right`; all three always shown. Delete the slot frame, `SetBackdropShown`, `ApplyBar`, `RequestBar`, `SyncArt`, `SyncValues` and the whole `ns.OnInitialize` block of hooks.

- [ ] **Step 3: Feed the fill.** One event frame, registered at file load:

| Event | Does |
|---|---|
| `UNIT_DISPLAYPOWER` (player), `PLAYER_ENTERING_WORLD` | re-read the power type; refresh values |
| `UNIT_POWER_FREQUENT`, `UNIT_MAXPOWER` (player) | refresh values |
| `PLAYER_DEAD`, `PLAYER_ALIVE`, `PLAYER_UNGHOST` | re-apply the dead look |

Power type: `UnitPowerType("player")`; when the token differs from the last one, set `Art`'s atlas and colour on `fill`, re-apply the dead look, set the values with `Enum.StatusBarInterpolation.Immediate` and call `fill:SetToTargetValue()`. Values: `fill:SetMinMaxValues(0, UnitPowerMax("player", powerType))`, `fill:SetValue(UnitPower("player", powerType), interpolation)`; skipped while the type is nil. Dead look: the fill's texture `SetDesaturated(dead)` and `SetAlpha(dead and 0.5 or 1)` with `dead = UnitIsDeadOrGhost("player")`. Run the power type read once at file load too. After each refresh call the `OnChanged` functions.

Logs: `ns.dev:LogChanged("power-type", powerToken, "POWER", "type", powerToken, atlas)` and `ns.dev:LogChanged("power-dead", dead, "POWER", "dead", dead)`.

- [ ] **Step 4: `SetLayout` applies at once** (no `ns.Layout.Request`): place and size the holder, keep the `POWER holder ...` log, and `SetSmooth` as today.

- [ ] **Step 5: Point `OffFormPower.lua` at the new outsets:** `local left, right = ns.PowerBar.fillOutset.left, ns.PowerBar.fillOutset.right` (same numbers as before: 2 and 3).

- [ ] **Step 6: Delete the three files, their TOC lines, the tags `DEFER APPLY`, `LAYOUT`, `ART` in `Core.lua`'s list, the slash global in `.luacheckrc` and the `Dev` ignore in `.pkgmeta`.**

- [ ] **Step 7: Verify**

Run: `scripts/lint.sh`
Expected: `All checks passed.`
Run: `grep -rn "PlayerFrame\|ns\.Layout\|ns\.HealthBar\|barOutset\|maskOutset\|hooksecurefunc" addons/RazzhUIResourceBars --include=*.lua --exclude-dir=Libs`
Expected: no output.

- [ ] **Step 8: Commit** `feat(razzhuiresourcebars): draw the power bar from the player's power`.

---

### Task 3: The numbers

**Files:**
- Create: `addons/RazzhUIResourceBars/PowerText.lua` (listed in the TOC after `PowerBar.lua`)
- Modify: `PowerBar.lua` (`DEFAULTS.text = "hover"`), `EditMode.lua` (`VALID`, `Save`'s log, `Apply`, the settings list), `Core.lua` (`ns.L`, tag list), `Database.lua` (layout comment)

**Interfaces:**
- Consumes: `ns.PowerBar.holder`, `ns.PowerBar.OnChanged(func)`, `ns.PowerBar.DEFAULTS`.
- Produces: `ns.PowerText.MODES = { "none", "hover", "value", "percent", "both" }`; `ns.PowerText.SetMode(mode)`; the saved field `text` (one of `MODES`) on every `powerBar` entry.

- [ ] **Step 1: `PowerText.lua`: the strings.** A frame on the holder at `holder:GetFrameLevel() + 3` (above the fill at +1, below the border at +5), all points; three font strings from the template `TextStatusBarText`: `CENTER` at 0, 0; `LEFT` at 2, 0; `RIGHT` at -2, 0.

- [ ] **Step 2: `PowerText.lua`: filling them.** `Update(powerType, powerToken)`, registered with `ns.PowerBar.OnChanged`, does nothing while the mode is `"none"`, the type is nil, or the mode is `"hover"` and the mouse is not over the holder. Otherwise:

| Mode | Centre | Left | Right |
|---|---|---|---|
| `"hover"`, `"value"` | `SetFormattedText("%s / %s", AbbreviateLargeNumbers(power), AbbreviateLargeNumbers(max))` | empty | empty |
| `"percent"` | `SetFormattedText("%.0f%%", UnitPowerPercent("player", powerType, false, CurveConstants.ScaleTo100))` | empty | empty |
| `"both"` | empty | the percent line, only when `powerToken == "MANA"` | `SetFormattedText("%s", AbbreviateLargeNumbers(power))` |

with `power = UnitPower("player", powerType)` and `max = UnitPowerMax("player", powerType)`.

- [ ] **Step 3: `SetMode(mode)`** stores the mode, clears all three strings, sets `holder:SetMouseClickEnabled(false)` and `holder:SetMouseMotionEnabled(mode == "hover")`, and updates. The holder's `OnEnter` updates and `OnLeave` clears the strings while the mode is `"hover"`. Log `ns.log("POWER", "text", mode)`.

- [ ] **Step 4: `EditMode.lua`.** `VALID.text` accepts exactly the five strings; `Apply` calls `ns.PowerText.SetMode(Get(layoutName, "text"))`; `Save`'s log line gains `saved.text`; a `Dropdown` setting after the smooth checkbox, `kind = LEM.SettingType.Dropdown`, `default = DEFAULTS.text`, `values = { { text = L.NUMBERS_HOVER, value = "hover" }, ... }` in the order Off, On Mouse-over, Value, Percent, Both, with the usual `get`/`set`.

- [ ] **Step 5: Strings in `Core.lua`:** `NUMBERS = "Numbers"`, `NUMBERS_DESC = "Show your power as numbers on the bar."`, `NUMBERS_NONE = "Off"`, `NUMBERS_HOVER = "On Mouse-over"`, `NUMBERS_VALUE = "Value"`, `NUMBERS_PERCENT = "Percent"`, `NUMBERS_BOTH = "Both"`. `Database.lua`'s layout comment lists `text = "none"|"hover"|"value"|"percent"|"both"`; `DB_VERSION` stays 1 (a missing field reads as its default).

- [ ] **Step 6: Verify**

Run: `scripts/lint.sh`
Expected: `All checks passed.`

- [ ] **Step 7: Commit** `feat(razzhuiresourcebars): show the power as numbers on the bar`.

---

### Task 4: Changelog and records

**Files:**
- Modify: `addons/RazzhUIResourceBars/CHANGELOG.md`, `docs/adr/0005-draw-the-player-power-bar-ourselves.md` (status)

- [ ] **Step 1: Rewrite `## Unreleased`** for players, describing the addon as it now is: the power bar of its own (place, size, smooth fill, per Edit Mode layout); that it works with any unit frames or none and leaves Blizzard's player frame alone; the Numbers dropdown; the druid row; that it needs RazzhUI and is switched on and off there; the Edit Mode layout fix line as it stands. No line about the health bar.

- [ ] **Step 2: ADR 0005 status** -> `accepted (in-game checks pending)`.

- [ ] **Step 3: Verify**

Run: `scripts/lint.sh && scripts/check-pr-title.sh "feat(razzhuiresourcebars)!: draw the power bar ourselves"`
Expected: both pass.

- [ ] **Step 4: Commit** `docs(razzhuiresourcebars): describe the resource bars module in the changelog`.

---

## After the tasks

Phase 5 review (the reviewers above, in parallel, on `git diff origin/main...HEAD`), fixes, the pre-PR gate, then Phase 6 in game: `scripts/worktree.sh game RazzhUIResourceBars`, the old ForeverUnitFrames switched off in the AddOns list, and the spec's checks with EllesmereUI's unit frames on and off.
