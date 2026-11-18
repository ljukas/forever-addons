# RazzhUI Modules Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The nine released addons that are not yet RazzhUI modules become modules, with their options under Options > AddOns > RazzhUI and no change to anything a player has saved.

**Architecture:** A module is three TOC lines plus, where it has options, a page asked from the core with `RazzhUI.RegisterOptions(ADDON_NAME)`. Seven addons need only that. The two Edit Mode addons each get a new `Options.lua` with one button that closes Options and opens Edit Mode, the way Blizzard's damage meter does it. The core (`addons/RazzhUI`) is not touched.

**Tech Stack:** Lua 5.1, WoW Forever client API (interface 16001), Bash for `scripts/lint.sh`.

**Spec:** `docs/superpowers/specs/2026-11-18-razzhui-modules-design.md`; the core's design `docs/superpowers/specs/2026-11-17-forever-enhanced-core-design.md`; decision record `docs/adr/0004-structure-the-addons-as-one-suite.md`. The worked example is ForeverTooltip in commit `bbaf4dc` (`git show bbaf4dc -- addons/ForeverTooltip`).

One step, one PR: `feat: move every addon under RazzhUI`.

## Global Constraints

- No file under `addons/RazzhUI/` or `addons/ForeverDev/` changes.
- Unchanged in every addon: the folder name, `ADDON_NAME`, every `## SavedVariables` line, every Settings variable name (`FOREVERMINIMAP_*`, `FOREVERCOMBAT_*`, `FOREVERPROFESSIONS_*`), every DB key and default, `/fdxp`, `ForeverDungeonXP_OnAddonCompartmentClick`, the dev slash commands.
- Module TOC lines, exactly: `## Title: |cffd6b380RazzhUI|r <Short name>`, `## Dependencies: RazzhUI`, `## Group: RazzhUI`. The two new lines go directly after the `## SavedVariables` line, or after the last `##` metadata line before `#@do-not-package@` when there is none (as in `addons/ForeverTooltip/ForeverTooltip.toc`).
- Short names: Action Bars, Bags, Combat, Combat Text, Dungeon XP, Minimap, Professions, Quests, Unit Frames.
- `## Category: Forever Enhanced Addons` is removed from every module TOC; `## X-Category` stays.
- Changelog line for each of the nine, as the last bullet under `## Unreleased`: `- <Folder> now needs RazzhUI installed, and is switched on or off with its checkbox on the RazzhUI page (Options → AddOns → RazzhUI).`
- No new globals. Modules read the `RazzhUI` global only.
- Every API is looked up in `.cache/wow-ui-source` before its first use (CLAUDE.md, "Looking up the API").
- `scripts/lint.sh` clean after every task; commit with `git add <paths>`, never `-A`, with `git branch --show-current` in the same command. The branch is `feat/suite-modules`.

## Review Focus

1. Saved data: any Settings variable name, DB table, key or default that differs from `origin/main`. Only the category handle may change in a `Settings.RegisterAddOnSetting` call.
2. The Edit Mode click from addon code: `SettingsPanel:Close` and `ShowUIPanel` in combat, with `CanEnterEditMode()` false (the `EditModeDisabled` game rule, the new-player restriction), with unapplied settings pending in Options, and whether it taints Edit Mode afterwards.
3. Load order and failure: `RazzhUI` must exist when a module's `ns.OnInitialize` handlers run; an error from `RazzhUI.RegisterOptions` stops the handlers listed after `Options.lua` in that TOC (ForeverMinimap lists it early).
4. The lint rule: TOCs with CRLF line ends, `template/Addon/__ADDON__.toc`, the core and ForeverDev exempt, a TOC with several dependencies.
5. Text that is now false: "Options → AddOns → ForeverX" in changelogs, comments or strings; "Forever Enhanced Addons" as a group; ForeverTooltip called "the first" module.

## Step reviewers (Phase 5)

Core: `addon-reviewer`, `api-verifier`, a correctness reviewer and a spec reviewer. Specialists: `savedvariables-guard` (the user asked for it; settings pages moved), a UI reviewer (the two new pages), a shell reviewer (`scripts/lint.sh`), a release reviewer (TOC metadata, the new files outside any do-not-package block).

## Order and gates

Build order: **Task 1, Gate A, Task 2, Gate B, Task 3, Gate C, Task 4, step review and its fixes.** A gate is a stop: nothing after it is built until its checks pass or the spec's fallback is chosen. Each gate: `scripts/worktree.sh game` (it points the changed addons' links at this worktree; RazzhUI's stays on main), the user does the steps and ends with `/rl`, then `scripts/devlog.sh --errors` and the tagged lines are read. The spec's "In-game checks" table lists what each gate must show.

**Gate A, after Task 1** (ActionBars, Quests, DungeonXP). May need a client restart: the titles changed.
1. Esc > AddOns: four modules nested under RazzhUI, titled "RazzhUI Action Bars", "RazzhUI Dungeon XP", "RazzhUI Quests", "RazzhUI Tooltip".
2. Options > AddOns > RazzhUI: four checkboxes, sorted; no page for the three new ones.
3. The three still work: red range wash on an out-of-range ability, the turn-in fill on the XP bar, `/fdxp` shows the recorded runs, the compartment entry (now reading "RazzhUI Dungeon XP") opens the journal.
4. Untick Quests, Reload UI: the XP bar fill is gone and the box is unticked. Tick it, Reload UI: it is back.
5. If a fight is at hand: open the Esc menu, get attacked with it open, leave combat; click the RazzhUI minimap button in combat.
6. `/rl`. Expect: `MODULES` lines for four modules, `TOGGLE ForeverQuests false` and `true`, no errors; for 5, `MENU undone combat` and `OPTIONS combat`.

**Gate B, after Task 2** (Bags, Combat, Minimap, Professions).
1. Options > AddOns: no top-level ForeverBags, ForeverCombat, ForeverMinimap or ForeverProfessions. Under RazzhUI: Bags, Combat, Minimap, Professions, Tooltip.
2. Each page shows the values it had before (bag direction and scale, DoT and HoT boxes, node boxes).
3. Change the button bag's scale, toggle a node type from the world map's toggle and see the Professions page follow, press Bags' reset button.
4. The button bag still holds the RazzhUI minimap button.
5. `/rl`, then look at the pages again: the changed values are kept.
6. Expect: `OPTIONS page` for the four addons (core's log), `BAG collect RazzhUIMinimapButton`, no errors.

**Gate C, after Task 3** (CombatText, UnitFrames).
1. Under RazzhUI: pages "Combat Text" and "Unit Frames", each one row with an "Edit Mode" button.
2. Click the button on Unit Frames: Options closes, Edit Mode opens. Select the power bar, move it, save, leave Edit Mode. Then Esc > Macros (open, close) and Esc > Logout (cancel).
3. The same from the Combat Text page, moving the combat text box.
4. In combat, click the button: nothing opens, red "can't do that in combat" text.
5. The power bar and combat text sit where they were before this branch, with their sizes.
6. `/rl`. Expect: `OPTIONS editmode open` from each module, `OPTIONS editmode combat`, and `scripts/devlog.sh --errors --all-addons` with no blocked action after the clicks.

If Gate C shows a blocked action or a broken Edit Mode: Task 3's fallback.

## Files

| File | Task | Change |
|---|---|---|
| `addons/{ForeverActionBars,ForeverQuests,ForeverDungeonXP}/*.toc`, `CHANGELOG.md` | 1 | module lines, changelog |
| `addons/{ForeverBags,ForeverCombat,ForeverMinimap,ForeverProfessions}/*.toc`, `Options.lua`, `CHANGELOG.md` | 2 | module lines, options parent, changelog |
| `addons/{ForeverCombatText,ForeverUnitFrames}/*.toc`, `Core.lua`, `CHANGELOG.md` | 3 | module lines, strings, shim comment, changelog |
| `addons/{ForeverCombatText,ForeverUnitFrames}/Options.lua` | 3 | new: the page with the Edit Mode button |
| `types/forever.lua` | 3 | only what LuaLS asks for |
| `scripts/lint.sh`, `template/Addon/__ADDON__.toc`, `addons/ForeverTooltip/ForeverTooltip.toc`, `CLAUDE.md` | 4 | lint rule, `Category` off, docs |

---

### Task 1: ActionBars, Quests and DungeonXP become modules

**Files:**
- Modify: `addons/ForeverActionBars/ForeverActionBars.toc`, `addons/ForeverQuests/ForeverQuests.toc`, `addons/ForeverDungeonXP/ForeverDungeonXP.toc`
- Modify: `addons/ForeverActionBars/CHANGELOG.md`, `addons/ForeverQuests/CHANGELOG.md`, `addons/ForeverDungeonXP/CHANGELOG.md`

- [ ] **Step 1: Edit the three TOCs** per Global Constraints: the title (`Action Bars`, `Quests`, `Dungeon XP`), the two new lines, `## Category` removed. Nothing else in the TOC changes; ForeverDungeonXP keeps `## AddonCompartmentFunc`.
- [ ] **Step 2: Add the changelog line** from Global Constraints to each of the three.
- [ ] **Step 3: Verify.** `scripts/lint.sh` is clean. `git diff --stat` lists exactly the six files. `grep -c '^## \(Dependencies\|Group\): RazzhUI' addons/ForeverActionBars/*.toc addons/ForeverQuests/*.toc addons/ForeverDungeonXP/*.toc` prints 2 for each.
- [ ] **Step 4: Commit.** `feat(foreveractionbars,foreverquests,foreverdungeonxp): join RazzhUI`

Then **Gate A**.

### Task 2: Bags, Combat, Minimap and Professions move their options under RazzhUI

**Files:**
- Modify: the `.toc`, `Options.lua` and `CHANGELOG.md` of `addons/ForeverBags`, `addons/ForeverCombat`, `addons/ForeverMinimap`, `addons/ForeverProfessions`

**Interfaces:**
- Consumes: `RazzhUI.RegisterOptions(addonName) -> category, layout` (`addons/RazzhUI/Options.lua:79`), a vertical-layout subcategory already registered with its parent.

- [ ] **Step 1: Edit the four TOCs** per Global Constraints (`Bags`, `Combat`, `Minimap`, `Professions`).
- [ ] **Step 2: Swap the options parent in each `Options.lua`.** `Settings.RegisterVerticalLayoutCategory(ADDON_NAME)` becomes `RazzhUI.RegisterOptions(ADDON_NAME)`, and the `Settings.RegisterAddOnCategory(category)` line is deleted. Keep the left-hand side each file has today (`category`, or `category, layout`), except ForeverBags, where `category` is no longer used: `local _, layout = RazzhUI.RegisterOptions(ADDON_NAME)`. Nothing else in these functions changes.
- [ ] **Step 3: Correct the comments** that name the old place: `addons/ForeverCombat/Options.lua:5`, `addons/ForeverMinimap/Options.lua:34`, `addons/ForeverProfessions/Options.lua:5` and ForeverBags' header comment now say "Options > AddOns > RazzhUI > <Short name>".
- [ ] **Step 4: Changelogs.** Add the Global Constraints line to all four. In `addons/ForeverMinimap/CHANGELOG.md` (two places) and `addons/ForeverProfessions/CHANGELOG.md` (one), "Options → AddOns → ForeverMinimap" / "ForeverProfessions" becomes "Options → AddOns → RazzhUI → Minimap" / "Professions". Delete the bullet `Now grouped under "Forever Enhanced Addons" in the AddOns list.` from both.
- [ ] **Step 5: Verify.** `scripts/lint.sh` is clean. `grep -rnE 'RegisterAddOnCategory|RegisterVerticalLayoutCategory' addons --include='*.lua' --exclude-dir=Libs` prints only lines in `addons/RazzhUI/Options.lua`. `git diff origin/main -- 'addons/*/Options.lua' | grep -E '^[-+].*(GetVariable|RegisterAddOnSetting|ns\.db|Default)'` prints nothing. `grep -rn 'AddOns → Forever\|Forever Enhanced Addons' addons --include='*.md'` prints nothing.
- [ ] **Step 6: Commit.** `feat(foreverbags,forevercombat,foreverminimap,foreverprofessions): join RazzhUI` is 74 characters, so use two commits of two addons each: `feat(foreverbags,forevercombat): join RazzhUI` and `feat(foreverminimap,foreverprofessions): join RazzhUI`.

Then **Gate B**.

### Task 3: CombatText and UnitFrames become modules with an Edit Mode page

**Files:**
- Modify: `addons/ForeverCombatText/ForeverCombatText.toc`, `addons/ForeverUnitFrames/ForeverUnitFrames.toc`
- Modify: `addons/ForeverCombatText/Core.lua`, `addons/ForeverUnitFrames/Core.lua` (strings in `ns.L`, the shim comment's tag list)
- Create: `addons/ForeverCombatText/Options.lua`, `addons/ForeverUnitFrames/Options.lua`
- Modify: both `CHANGELOG.md`; `types/forever.lua` only if LuaLS reports an unknown field

**Interfaces:**
- Consumes: `RazzhUI.RegisterOptions(addonName) -> category, layout`; `ns.OnInitialize(func)` and `ns.L` from each module's `Core.lua`; `ns.L.COMBAT_TEXT` ("Combat Text") and `ns.L.POWER_BAR` ("Player Power Bar"), the names the boxes have in Edit Mode.
- Blizzard's, with where each is defined: `CreateSettingsButtonInitializer(name, buttonText, buttonClick, tooltip, addSearchTags)` (`Blizzard_Settings_Shared/Blizzard_SettingControls.lua:1040`; `addSearchTags` must not be nil), `SettingsPanel:Close(skipTransitionBackToOpeningPanel)` (`Blizzard_SettingsPanel.lua:256`), `EditModeManagerFrame:CanEnterEditMode()` (`Blizzard_EditMode/Shared/EditModeManager.lua:1730`), `ShowUIPanel`, `UIErrorsFrame:AddMessage`. The click copies `Blizzard_DamageMeter/DamageMeterSessionWindow.lua:473-477`.

- [ ] **Step 1: Edit the two TOCs** per Global Constraints (`Combat Text`, `Unit Frames`), and list `Options.lua` on the line after `EditMode.lua`, outside the do-not-package block.
- [ ] **Step 2: Add the strings** to `ns.L` in each `Core.lua`: `EDIT_MODE = "Edit Mode"` (used when the global string `HUD_EDIT_MODE_MENU` is missing) and `EDIT_MODE_TOOLTIP`: for UnitFrames "Move the power bar and change its size and other settings in Edit Mode.", for CombatText "Move the combat text and change how far it scrolls, how long it stays and how big it is in Edit Mode." Add the line `OPTIONS         Options.lua` to the tag list in each shim comment.
- [ ] **Step 3: Write `Options.lua`** in each module, the same shape in both:
  - `ns.OnInitialize(function() ... end)` gets the layout with `local _, layout = RazzhUI.RegisterOptions(ADDON_NAME)` and adds one row: `CreateSettingsButtonInitializer(<box name>, _G["HUD_EDIT_MODE_MENU"] or L.EDIT_MODE, OpenEditMode, L.EDIT_MODE_TOOLTIP, true)`.
  - `local function OpenEditMode()`: in combat (`InCombatLockdown()`), show `_G["ERR_NOT_IN_COMBAT"]` on `UIErrorsFrame` in the colour `RazzhUI.OpenOptions` uses (`1.0, 0.1, 0.1, 1.0`), `ns.log("OPTIONS", "editmode combat")`, return. If `not EditModeManagerFrame:CanEnterEditMode()`, `ns.log("OPTIONS", "editmode refused")`, return. Otherwise `SettingsPanel:Close(true)`, `ShowUIPanel(EditModeManagerFrame)`, `ns.log("OPTIONS", "editmode open")`.
  - A header comment: where the page is, that the settings themselves live in the Edit Mode dialog (`EditMode.lua`), and why the click is guarded (panels can't be shown or hidden from addon code in combat).
  - No predicate that greys the button; the click's own guards are enough.
- [ ] **Step 4: Changelogs.** The Global Constraints line, and one more bullet each: for UnitFrames `- A Unit Frames page under Options → AddOns → RazzhUI has a button that opens Edit Mode, where the power bar is moved and set up.`; for CombatText the same with "Combat Text page" and "the combat text".
- [ ] **Step 5: Verify.** `scripts/lint.sh` is clean (annotate in `types/forever.lua` whatever LuaLS doesn't know, after reading it in the source). `git diff origin/main -- addons/ForeverCombatText/EditMode.lua addons/ForeverUnitFrames/EditMode.lua addons/ForeverCombatText/Database.lua addons/ForeverUnitFrames/Database.lua` is empty.
- [ ] **Step 6: Commit.** `feat(forevercombattext,foreverunitframes): join RazzhUI`

Then **Gate C**.

**Fallback (only if Gate C fails on taint):** in both `Options.lua`, the button row and `OpenEditMode` go, and the page is one section header, `layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(L.EDIT_MODE_HINT))`, with `EDIT_MODE_HINT` = "Move and set up the power bar in Edit Mode (Esc > Edit Mode)." (CombatText: "the combat text"). The changelog bullets are reworded to match. Commit: `fix(forevercombattext,foreverunitframes): point to Edit Mode instead of opening it`.

### Task 4: Lint, template and docs

**Files:**
- Modify: `scripts/lint.sh`, `template/Addon/__ADDON__.toc`, `addons/ForeverTooltip/ForeverTooltip.toc`, `CLAUDE.md`

- [ ] **Step 1: Drop `## Category: Forever Enhanced Addons`** from the template TOC and ForeverTooltip's TOC.
- [ ] **Step 2: Add the lint rule** in the TOC loop of `scripts/lint.sh`, as the `else` of the existing three-marks `if`: an addon under `addons/` whose folder is neither `$CORE_ADDON` nor `ForeverDev` and that has none of the three marks fails with a message that names the three lines to add. The template's TOC is already a module and takes the existing branch. Update the comment above the check: it no longer says a plain addon is fine.
- [ ] **Step 3: Prove the rule.** Delete the `## Dependencies`, `## Group` lines and the title prefix from one TOC in the working tree: `scripts/lint.sh` fails with the new message and names that TOC. Restore the file (`git checkout -- <toc>`): lint is clean. Remove only `## Group`: the old three-marks message still fires. Restore.
- [ ] **Step 4: CLAUDE.md, Layout.** The first bullet no longer says released addons set `## Category`; it says every released addon except the core is a module, and that modules and the core carry no `## Category` line (their genre stays in `## X-Category`). The module bullet's last sentence becomes: "Every released addon is one; lint fails an addon under `addons/` that is neither the core, ForeverDev nor a module." The RazzhUI bullet's "the suite the released addons are becoming" becomes "the suite the released addons belong to".
- [ ] **Step 5: Verify.** `scripts/lint.sh` clean; `grep -rn '^## Category' addons template` prints only `addons/ForeverDev/ForeverDev.toc`.
- [ ] **Step 6: Commit** three times: `chore(forevertooltip): drop the unused Category line`, `build(scripts,template): fail lint for addons that aren't modules` and `docs: describe every released addon as a RazzhUI module`.

After Task 4: Phase 5 (one review of the whole diff by the step reviewers above) and its fixes. The controller then updates the roadmap's step 2 row with what the gates actually showed and what is still untested in game, and the `razzhui-launch-checks` memory. If a fix changed addon code, the gate that covers it is run again.
