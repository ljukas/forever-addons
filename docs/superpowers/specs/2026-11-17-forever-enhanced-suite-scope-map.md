# RazzhUI suite: scope map

Date: 2026-11-17. Decision record: `docs/adr/0004-structure-the-addons-as-one-suite.md`.
Steps: `docs/superpowers/roadmaps/2026-11-17-forever-enhanced-suite.md`.

## What it is

One core addon (`RazzhUI`) that every other released addon depends on. Players install
one download, open "RazzhUI" from the Esc menu, and switch modules on and off in
Blizzard's Options window, where each module that is on has its own options page.

## Feasibility

"Source" means read in `.cache/wow-ui-source` for this build. "EllesmereUI" means it does this
today on this client (9.8.8, installed locally). Nothing here has run in game from our code yet.

| Capability | Verdict | Evidence | Still to check in game |
|---|---|---|---|
| Modules nested under the core in the AddOns list | Yes | Source: `Blizzard_AddOnList/AddonList.lua:450-511` reads `Group` and nests an addon under the addon whose folder name equals it. EllesmereUI: the user's screenshot | By eye |
| A module can't load without the core and loads after it | Yes | `## Dependencies` (131 Blizzard TOCs use it; the AddOns list shows the dependency state) | By eye: the core disabled |
| A button in the Esc menu | Yes, without an API | Source: no extension point but `EventRegistry "GameMenuFrame.Shown"`; buttons come from a pool rebuilt on every show (`MainMenuFrameTemplates.lua:14-67`, `GameMenuFrame.lua:160-271`). EllesmereUI: its own button, re-placed in a hook on `Layout` | That Logout, Exit, Macros and Edit Mode stay untainted; that it sits right beside EllesmereUI's button |
| The button opens Options at our category | Yes, out of combat | Source: `Settings.OpenToCategory(id)` is the documented entry (`Blizzard_ImplementationReadme.lua:199-210`) and selects the AddOns tab. `HideUIPanel` / `ShowUIPanel` from addon code are refused in combat (`UIParentPanelManager.lua:854-861`), so the button hides in combat | That it opens from the click |
| One window: a root category with a page per module | Yes | Source: `Settings.RegisterVerticalLayoutSubcategory(parent, name)` (`Blizzard_Settings.lua:158`); the list nests and collapses (`Blizzard_CategoryList.lua:408-426`); `SetShouldSortAlphabetically` for the children | That a subcategory added after the root was registered shows up |
| Options code stays in the module | Yes | Four addons already build their pages with these calls; only the parent changes | The pilot module's page |
| Switch a module on and off | Yes, with a reload | Source: `C_AddOns.EnableAddOn` / `DisableAddOn` carry no restriction flag (`AddOnsDocumentation.lua:11,62`); Blizzard's own dialogs do `DisableAddOn` then `ReloadUI()` (`GameDialogDefs.lua:634-638, 720-725`). EllesmereUI: the same, and notes that Forever only allows a reload inside a click | That the state survives the reload, and what happens when the player doesn't reload |
| List modules that are off | Yes | Source: `GetNumAddOns`, `GetAddOnDependencies`, `GetAddOnMetadata`, `GetAddOnEnableState` work by name or index on addons that aren't loaded (the AddOns list is built from them) | The list is exactly our modules |
| Options of a module that is off are gone | Yes | Its code never loads, so its page is never registered. (A registered category can't be hidden: no API. Not needed) | By eye |
| Settings of the two Edit Mode modules reachable from the window | Probably | A page with a button that opens Edit Mode. `ShowUIPanel(EditModeManagerFrame)` from addon code is refused in combat and may taint Edit Mode | Step 2. Fallback: a line of text pointing to Esc > Edit Mode |
| One download | Yes, not verified | The BigWigs packager can put several folders in one zip (`move-folders`); to be checked against its docs in step 3 | Step 3: build the zip locally, install it into a clean AddOns folder |
| Parallel worktrees on different modules | Yes | Game links are per addon folder (`scripts/worktree.sh`); a module's work stays in its folder; the core is shared the way ForeverDev is | Two worktrees live at once |

Not possible, and not needed: reusing Blizzard's settings controls in a window of our own, and
hiding a Settings category after it was registered.

## Phases

1. **Core and one pilot module.** The core addon, the Esc-menu button, the "RazzhUI"
   category with the modules list, the page API, ForeverTooltip converted, and the tooling a
   module needs (lint, template, worktree notices). Every in-game check above except the Edit
   Mode and download rows is answered here, before the other nine addons are touched.
2. **The other nine modules.** TOC lines and the options parent for each; pages for the Edit Mode
   modules; modules without options appear only in the list.
3. **One download, prepared.** One zip, one version, release notes from the module changelogs,
   the release workflow and CLAUDE.md's release section. No tag is pushed.
4. **Shared code into the core** (optional, a refactor): the dev shim, the SavedVariables
   bootstrap and migration loop, the Edit Mode glue and one LibEditMode. Each under
   `docs/refactor-workflow.md`.

Deferred, not planned: a first-run module picker, profiles, a slash command. (A minimap button was
on this list until 18 November 2026; it became roadmap step 1b.)
