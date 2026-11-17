# Razzh Forever Enhanced Core Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A core addon, `RazzhForeverEnhanced`, with an Esc-menu button and one "Razzh Forever Enhanced" category in Blizzard's Options where modules are switched on and off and each loaded module has its own page; ForeverTooltip becomes the first module.

**Architecture:** The core finds its modules by asking `C_AddOns` which addons list it in `## Dependencies`, so it holds no list of them. It registers one Settings category whose page has a checkbox per module (a real `EnableAddOn` / `DisableAddOn`, applied by a Reload UI button) and hands each module a subcategory to fill with its own `Settings` calls. The Esc-menu button is the core's own frame, placed after Blizzard's layout.

**Tech Stack:** Lua 5.1, WoW Forever client API (interface 16001), Bash for `scripts/`.

**Spec:** `docs/superpowers/specs/2026-11-17-forever-enhanced-core-design.md`; decision record `docs/adr/0004-structure-the-addons-as-one-suite.md`; scope map and roadmap beside them (this is step 1 of 4).

One step, one PR: `feat(razzhforeverenhanced,forevertooltip): add the suite core`.

## Global Constraints

- Names: folder, TOC and global `RazzhForeverEnhanced`; title, Esc-menu text and Options category "Razzh Forever Enhanced"; module titles `Razzh Forever Enhanced: <Short name>`; `## Category: Forever Enhanced Addons` unchanged.
- The core's only globals: `RazzhForeverEnhanced` and `RazzhForeverEnhanced_OnAddonCompartmentClick`. No `## SavedVariables`.
- The core assigns no field on `GameMenuFrame`, its pooled buttons or any Blizzard table, and calls no Lua method of the menu's mixin. Allowed on Blizzard's frames: `hooksecurefunc`, reading, and the widget calls `SetPoint`, `SetHeight`, `GetPoint`, `GetHeight`, `GetText`, `IsShown`.
- Nothing in the core names a module. Modules are found, never listed.
- ForeverTooltip keeps `ForeverTooltipDB` and its `FOREVERTOOLTIP_*` variables.
- Module checkboxes: proxy settings with `Settings.VarType.Boolean`, a **nil default** and **no commit flag**.
- Every API is looked up in `.cache/wow-ui-source` before its first use (CLAUDE.md, "Looking up the API").
- `ns.log` tags: `LOADED` (Core.lua), `MODULES` (Modules.lua), `OPTIONS`, `TOGGLE` (Options.lua), `MENU` (GameMenu.lua).
- `scripts/lint.sh` clean after every task; commit with `git add <paths>`, never `-A`, with `git branch --show-current` in the same command.

## Review Focus

1. Taint: any field written on `GameMenuFrame` or a pooled button, any Lua method of Blizzard's called from our code, anything touched while `InCombatLockdown()`.
2. The menu button's placement is repeatable: `Layout` runs many times per show (and again on `STORE_STATUS_CHANGED`), EllesmereUI moves the same buttons in the same hook, and the "AddOns" button can be absent. No drift, no overlap, no error when the anchor isn't found.
3. The API's edges: `RegisterOptions` with a non-string, an addon that isn't a module, or twice; `OpenOptions` in combat, with an unknown name, before any page exists; a module whose title lacks the prefix. Errors must name the caller's file (`error(message, 2)`).
4. The switch: a module enabled for some characters only, `UnitGUID("player")` secret, a module that is enabled but failed to load, Defaults and "All Settings" leaving modules alone, a toggle with no reload after it.
5. The scripts: TOCs with CRLF line ends, several dependencies with spaces after the commas, the template's `__ADDON__` placeholder, empty arrays under `set -u` in bash 3.2, `WOW_DIR` with spaces, the core listed twice in the devlog filter.

## In-game checks

The spec's table and its fallbacks. Instrumentation: `LOADED` (the four GlobalStrings: present or not), `MODULES` at `PLAYER_LOGIN` (each module: folder, short name, loaded, enabled; whether the player GUID is secret), `OPTIONS page <addon>`, `OPTIONS open <addon or root>`, `OPTIONS combat`, `TOGGLE <folder> <true|false>`, `MENU placed <anchor text>` and `MENU hidden combat` through `ns.dev:LogOnce`, `MENU click`.

## Step reviewers

Core four, plus `savedvariables-guard` (new settings variables `RAZZHFOREVERENHANCED_MODULE_*`; ForeverTooltip's must be unchanged), UI reviewer (the menu button, the Settings page), shell reviewer (`scripts/`), release reviewer (new TOC and `.pkgmeta`, template TOC).

---

### Task 1: Scaffold the core

**Files:**
- Create via `scripts/new-addon.sh RazzhForeverEnhanced`: `addons/RazzhForeverEnhanced/{RazzhForeverEnhanced.toc,Core.lua,CHANGELOG.md,.pkgmeta}`
- Modify: `.luacheckrc` (entry for `addons/RazzhForeverEnhanced/**`: the two globals)

**Produces:** `ns.log`, `ns.dev`, `ns.Inert`, `ns.L`, the global table `RazzhForeverEnhanced` (empty; Task 3 adds its functions).

- [ ] TOC, in ForeverTooltip's order: `## Title: Razzh Forever Enhanced`; `## Notes:` one sentence for players (what the Esc-menu entry and the Options page are for); Author, X-License, `## Version: @project-version@`; an `## IconTexture` and `## X-Category` of the builder's choice; `## Category: Forever Enhanced Addons`; `## AddonCompartmentFunc: RazzhForeverEnhanced_OnAddonCompartmentClick`; the ForeverDev `OptionalDeps` block; then `Core.lua`. Remove the template's `## SavedVariables` line.
- [ ] `Core.lua`: the shim from `addons/ForeverTooltip/Core.lua:1-25` with this addon's tag list; `RazzhForeverEnhanced = {}`; `ns.L` with `TITLE = "Razzh Forever Enhanced"`, `MODULE_PREFIX = "Razzh Forever Enhanced: "`, `MODULES = "Modules"`, `NO_MODULES`, `RELOAD_TOOLTIP`, `NEEDS_RELOAD` (the fallback for `VIDEO_OPTIONS_NEED_UIRELOAD`). No SavedVariables bootstrap.
- [ ] `ns.log("LOADED", ...)` once the addon has loaded: for `RELOADUI`, `ADDONS`, `VIDEO_OPTIONS_NEED_UIRELOAD`, `ERR_NOT_IN_COMBAT`, the string or "missing".
- [ ] `CHANGELOG.md`: `## Unreleased` with players' lines for the Esc-menu entry and the modules page. `.pkgmeta`: the template's, no `Dev` ignore needed.
- [ ] Later tasks add their files to the TOC. Lint, commit `feat(razzhforeverenhanced): scaffold the core`.

### Task 2: Find the modules

**Files:** Create `addons/RazzhForeverEnhanced/Modules.lua`; add to TOC after `Core.lua`.

**Consumes:** `ns.L.MODULE_PREFIX`.

**Produces:**
- `ns.Modules.ShortName(title) -> string`: the title without `MODULE_PREFIX`; the title unchanged when it doesn't start with it. Pure.
- `ns.Modules.DependsOn(dependencies, coreName) -> boolean`: `dependencies` is an array of folder names. Pure.
- `ns.Modules.List() -> { { folder, name, notes }, ... }`: sorted by `name`, built once and cached.
- `ns.Modules.Find(folder) -> entry or nil`.
- `ns.Modules.IsLoaded(folder) -> boolean`, `ns.Modules.IsEnabled(folder) -> boolean`, `ns.Modules.SetEnabled(folder, enabled)`, `ns.Modules.HasPendingChange() -> boolean` (some module's `IsEnabled` differs from its `IsLoaded`). All read live, nothing cached.

- [ ] `List`: indexes 1 to `C_AddOns.GetNumAddOns()`; a module is an addon whose `{ C_AddOns.GetAddOnDependencies(i) }` contains `ADDON_NAME`. `folder` from `GetAddOnName` (or the first return of `GetAddOnInfo`), `name` from `ShortName(GetAddOnMetadata(i, "Title"))`, `notes` from `GetAddOnMetadata(i, "Notes")` or `""`.
- [ ] `IsEnabled`: `C_AddOns.GetAddOnEnableState(folder, character) ~= Enum.AddOnEnableState.None`, where `character` is `UnitGUID("player")`, or `UnitName("player")` when the GUID is secret (`issecretvalue`).
- [ ] `SetEnabled`: `C_AddOns.EnableAddOn(folder)` or `DisableAddOn(folder)` with no character (all characters), then `ns.log("TOGGLE", folder, enabled)`.
- [ ] On `PLAYER_LOGIN` (`EventUtil.RegisterOnceFrameEventAndCallback`, or the repo's usual way), inside `if ns.dev.enabled then`: one `MODULES` line per module (folder, name, loaded, enabled) and one saying whether the GUID is secret.
- [ ] Lint, commit `feat(razzhforeverenhanced): find the modules that depend on the core`.

### Task 3: The options category, the modules page and the API

**Files:** Create `addons/RazzhForeverEnhanced/Options.lua`; add to TOC after `Modules.lua`.

**Consumes:** `ns.Modules.*`, `ns.L`.

**Produces (public, used by every module):**
- `RazzhForeverEnhanced.RegisterOptions(addonName) -> category, layout`
- `RazzhForeverEnhanced.OpenOptions(addonName)` (`addonName` optional)
- `RazzhForeverEnhanced_OnAddonCompartmentClick()` (named by the TOC)

- [ ] At file load: `Settings.RegisterVerticalLayoutCategory(ns.L.TITLE)` (keep `category, layout`), `category:SetShouldSortAlphabetically(true)`, then the page, then `Settings.RegisterAddOnCategory(category)`.
- [ ] The page: `CreateSettingsListSectionHeaderInitializer(ns.L.MODULES)`; then per module of `ns.Modules.List()` a proxy setting and `Settings.CreateCheckbox(category, setting, tooltip)`:
  - `Settings.RegisterProxySetting(category, variable, Settings.VarType.Boolean, module.name, nil, get, set)` with `variable = "RAZZHFOREVERENHANCED_MODULE_" .. module.folder:upper()`, `get` = `ns.Modules.IsEnabled(folder)`, `set` = `ns.Modules.SetEnabled(folder, value)`.
  - `tooltip` = the module's notes, a blank line, then `VIDEO_OPTIONS_NEED_UIRELOAD or ns.L.NEEDS_RELOAD`.
- [ ] The Reload UI row: `CreateSettingsButtonInitializer("", RELOADUI, ReloadUI, ns.L.RELOAD_TOOLTIP, true)` added with `layout:AddInitializer`; `AddModifyPredicate(ns.Modules.HasPendingChange)`; `AddEvaluateStateCVar(variable)` for every module variable so it re-evaluates when a box changes (`Blizzard_SettingControls.lua:194-199`). `ReloadUI` must be called directly from the click.
- [ ] With no modules: one line of text (`ns.L.NO_MODULES`) in place of the checkboxes and the button. Use whatever plain-text initializer Blizzard's own pages use; if there is none, a section header.
- [ ] `RegisterOptions`: `addonName` must be a string naming a module (`ns.Modules.Find`), else `error(message, 2)`. First call: `Settings.RegisterVerticalLayoutSubcategory(category, module.name)`, cached per addon, `ns.log("OPTIONS", "page", addonName)`. Later calls return the cached pair.
- [ ] `OpenOptions`: `addonName` nil or a string, else `error(message, 2)`. In combat: `UIErrorsFrame:AddMessage(ERR_NOT_IN_COMBAT, ...)` in Blizzard's error red, `ns.log("OPTIONS", "combat")`, return. Otherwise `Settings.OpenToCategory(id)` with the module's subcategory ID, or the root's when the addon has no page; `ns.log("OPTIONS", "open", addonName or "root")`.
- [ ] `RazzhForeverEnhanced_OnAddonCompartmentClick` calls `RazzhForeverEnhanced.OpenOptions()`.
- [ ] Lint, commit `feat(razzhforeverenhanced): add the options category and the modules page`.

### Task 4: The Esc-menu button

**Files:** Create `addons/RazzhForeverEnhanced/GameMenu.lua`; add to TOC last.

**Consumes:** `RazzhForeverEnhanced.OpenOptions`, `ns.L.TITLE`.

- [ ] Read first: `Blizzard_GameMenu/Shared/GameMenuFrame.lua:160-271` (which GlobalStrings the "AddOns", "Edit Mode" and "Support" buttons use), `Blizzard_SharedXML/Shared/Frame/MainMenuFrameTemplates.lua:14-67`, the layout mixin `GameMenuFrame` inherits (does `Layout` skip children without `layoutIndex`, and how does it anchor each child), and EllesmereUI's hook (`<WOW_DIR>/Interface/AddOns/EllesmereUI/EllesmereUI.lua:4461-4676`).
- [ ] One button, created once: `CreateFrame("Button", nil, GameMenuFrame, "GameMenuFrameButtonTemplate")`, text `ns.L.TITLE`. It gets no `layoutIndex`.
- [ ] `hooksecurefunc(GameMenuFrame, "Layout", Place)`. `Place`:
  - In combat: hide the button, `ns.dev:LogOnce("menu-combat", "MENU", "hidden combat")`, return.
  - Find the anchor among `GameMenuFrame.buttonPool:EnumerateActive()` by text: "AddOns", else "Edit Mode", else "Support". None found: hide the button and return.
  - `shift` = the button's height plus the menu's section gap. Every active pooled button at or below the anchor moves down by `shift` (same point, same relative frame, `y - shift`); our button takes the anchor's old place and size; `GameMenuFrame:SetHeight(GameMenuFrame:GetHeight() + shift)`. Blizzard's `Layout` resets all of this each time it runs, so `Place` starts from Blizzard's positions every time and keeps no base height.
  - `ns.dev:LogOnce("menu-placed", "MENU", "placed", anchorText)`.
- [ ] `PLAYER_REGEN_DISABLED` while the menu is shown: hide the button and undo the shift with the same arithmetic reversed (no `MarkDirty`, no `Layout` call). `PLAYER_REGEN_ENABLED` while it is shown: `Place` again.
- [ ] Click: `PlaySound(SOUNDKIT.IG_MAINMENU_OPTION)`, `HideUIPanel(GameMenuFrame)`, `RazzhForeverEnhanced.OpenOptions()`, `ns.log("MENU", "click")`.
- [ ] Beside EllesmereUI: from its code, write down in a comment what it moves and what it sets the height to, and make `Place` give a right result whichever hook runs first. If that can't be had from reading alone, say so in the task report; it becomes an in-game finding.
- [ ] Lint, commit `feat(razzhforeverenhanced): add the Esc menu button`.

### Task 5: ForeverTooltip becomes the first module

**Files:** Modify `addons/ForeverTooltip/ForeverTooltip.toc`, `addons/ForeverTooltip/Options.lua:34-68`, `addons/ForeverTooltip/CHANGELOG.md`.

**Consumes:** `RazzhForeverEnhanced.RegisterOptions(addonName) -> category, layout`.

- [ ] TOC: `## Title: Razzh Forever Enhanced: Tooltip`; add `## Dependencies: RazzhForeverEnhanced` and `## Group: RazzhForeverEnhanced` (above the ForeverDev block). Nothing else changes.
- [ ] `Options.lua`: `local category = RazzhForeverEnhanced.RegisterOptions(ADDON_NAME)` in place of `Settings.RegisterVerticalLayoutCategory(ADDON_NAME)`; delete the `Settings.RegisterAddOnCategory(category)` line; update the comment above (`Options > AddOns > Razzh Forever Enhanced > Tooltip`). Settings, variables and saved keys untouched.
- [ ] `CHANGELOG.md` under `## Unreleased`: the options moved (rewrite the existing line that says "Options → AddOns → ForeverTooltip"), and it now needs Razzh Forever Enhanced.
- [ ] Lint, commit `feat(forevertooltip): make it a Razzh Forever Enhanced module`.

### Task 6: Teach the tooling what a module is

**Files:** Modify `scripts/lib.sh`, `scripts/lint.sh:36-58`, `template/Addon/__ADDON__.toc`, `scripts/worktree.sh` (the `game` case), `scripts/devlog.sh:44-52`.

**Produces:** in `scripts/lib.sh`, `CORE_ADDON="RazzhForeverEnhanced"` and `CORE_TITLE="Razzh Forever Enhanced"`.

- [ ] `lint.sh`, in the per-TOC loop: read `## Dependencies:` (comma-separated, spaces and a trailing CR trimmed). Each name must be a folder `addons/<name>/<name>.toc`, else fail. A TOC that depends on `$CORE_ADDON` must have `## Group: $CORE_ADDON` and a `## Title:` starting with `$CORE_TITLE: `, else fail with a message naming the missing line.
- [ ] Prove the check: remove ForeverTooltip's `## Group` line, run `scripts/lint.sh`, expect a failure naming it; misspell its dependency, expect a failure; restore both, expect "All checks passed.".
- [ ] `template/Addon/__ADDON__.toc`: `## Title: Razzh Forever Enhanced: __ADDON__`, `## Dependencies: RazzhForeverEnhanced`, `## Group: RazzhForeverEnhanced`. Lint covers the template TOC already.
- [ ] `worktree.sh game`, after linking, when this checkout has the core and didn't just link it: a `note:` line when the core's link points at another worktree (`<label>`: this worktree's modules run against that copy), and one when the core has no link in game (its modules won't load; link it from the main checkout). Notices only, never a refusal.
- [ ] `devlog.sh`: in a worktree that holds addons, add `$CORE_ADDON` to the filter unless it's already there, and say so in the "Showing ..." line.
- [ ] Check by hand: `scripts/worktree.sh status`, `scripts/worktree.sh game` in this worktree (it holds the core, so no notice), `scripts/devlog.sh` (the core appears once in the "Showing" line). `bash -n` on each changed script.
- [ ] Commit `build(scripts,template): check and scaffold suite modules`.

### Task 7: Document the structure

**Files:** Modify `CLAUDE.md`, `docs/superpowers/roadmaps/2026-11-17-forever-enhanced-suite.md`.

- [ ] `CLAUDE.md`, "Layout": `addons/RazzhForeverEnhanced/` is the core every released addon depends on; what makes an addon a module (the three TOC lines); `scripts/new-addon.sh` scaffolds one.
- [ ] "Worktrees": the core is shared like ForeverDev (one checkout holds its link; claim it only on a branch that changes it; `worktree.sh game` and `devlog.sh` say when a module runs against another worktree's core).
- [ ] "Code conventions": a module's options page comes from `RazzhForeverEnhanced.RegisterOptions(ADDON_NAME)`; the core's API only grows; nothing about one module goes into the core.
- [ ] Roadmap: step 1's status.
- [ ] Commit `docs: describe the suite core and its modules`.

---

After Task 7: Phase 5 (one review of the whole diff by the step reviewers above), then Phase 6 (`scripts/worktree.sh game`, a client restart for the new folder, the in-game checks).
