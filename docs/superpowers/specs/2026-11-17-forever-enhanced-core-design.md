# RazzhUI, step 1: the core and its options window

Date: 2026-11-17. Decision record: `docs/adr/0004-structure-the-addons-as-one-suite.md`.
Scope map: `docs/superpowers/specs/2026-11-17-forever-enhanced-suite-scope-map.md`.
Roadmap: `docs/superpowers/roadmaps/2026-11-17-forever-enhanced-suite.md` (this is step 1 of 4).

## Intent

Players should install one thing and choose its parts inside it, instead of ten addons. This step
builds the core that makes that possible and proves it in game with one module, before the other
nine addons are touched.

## Decided by the user

- The structure of EllesmereUI: a core addon, every other addon a module that depends on it, one
  options window for all of them, opened mainly from the Esc menu, where modules are switched on
  and off and a module's options are editable while it is on.
- Blizzard's UI language, not EllesmereUI's look.
- The window is Blizzard's Options window.
- Options stay with the module they belong to.
- It must work with parallel worktrees on different modules.
- In the end one download. Nothing is released after this work; it is only prepared.
- The core addon is named "RazzhUI", the way EllesmereUI is named, and the name is shown in
  Blizzard-like colours.

Everything else below is Claude's call unless marked. That includes what follows from the name:

- The folder and global are `RazzhUI`; module titles read "RazzhUI Tooltip".
- The colours: "Razzh" in Blizzard's Battle.net blue (`BATTLENET_FONT_COLOR`, `82c5ff`) and "UI"
  in its white (`HIGHLIGHT_FONT_COLOR`). Gold was the other candidate, but the AddOns list and
  the Esc-menu buttons already draw text in gold, so it wouldn't show. The coloured name is used
  where a title is drawn: TOC titles (the AddOns list and the addon dropdown) and the Esc-menu
  button. The Options category is plain "RazzhUI", because Options sorts and searches categories
  by their name. In Lua the colours come from the named constants; a TOC can only hold the hex.
- `## Category: Forever Enhanced Addons` is left as it is.

## Goals

- A new addon, `addons/RazzhUI` (title "RazzhUI"), the core.
- A "RazzhUI" button in the Esc menu that opens Options at the "RazzhUI"
  category. The same from the Addon Compartment (the minimap's addon dropdown).
- The "RazzhUI" page lists every module with a checkbox. Unticking one disables that
  addon; a "Reload UI" button on the page applies the change.
- A module that is loaded gets its options page as a subcategory of "RazzhUI", built by
  the module's own code.
- ForeverTooltip is the first module (the pilot): it has a real options page (a checkbox, a
  dropdown, a parent dependency), no Edit Mode and no library.
- A module nests under "RazzhUI" in the AddOns list.
- The tooling knows what a module is: lint checks its TOC lines, the template scaffolds one, and
  `scripts/worktree.sh` and `scripts/devlog.sh` handle the core being shared.

## Non-goals (this step)

- Converting the other nine addons (step 2). Until then they stay as they are: their own entries
  under Options > AddOns, not in the modules list.
- Pages for the Edit Mode modules (step 2), the single zip (step 3), moving shared code into the
  core (step 4).
- A slash command, a minimap button, a first-run picker, profiles.
- SavedVariables for the core. It stores nothing: the client keeps which addons are enabled.

## Anti-goals

- No taint: Logout, Exit Game, Macros, Edit Mode and Options keep working from the Esc menu, in
  and out of combat. The core writes no field on `GameMenuFrame`, on its pooled buttons or on
  any Blizzard table.
- No list of modules in the core, and no code in the core that is about one module.
- No module's saved data or settings names change. `FOREVERTOOLTIP_*` and `ForeverTooltipDB` stay.

## Approaches

Blizzard's Options window as the one window (picked by the user), a window of our own built from
Blizzard frame parts, or a small modules window that jumps into Options. ADR 0004 has the
trade-offs, and the other choices made here (a real disable, modules found by dependency, our own
Esc-menu button).

## How it works

### What a module is

An addon folder whose TOC has:

```
## Title: |cff82c5ffRazzh|r|cffffffffUI|r Tooltip
## Dependencies: RazzhUI
## Group: RazzhUI
```

- `Dependencies` makes the client load the core first and refuse the module without it. It is
  also how the core finds its modules.
- `Group` nests it under the core in the AddOns list. The value must equal the core's folder name
  (`AddonList.lua:450-455`).
- With its colour codes removed the title reads "RazzhUI Tooltip". The part after `RazzhUI ` is
  the module's **short name** ("Tooltip"), used for its checkbox and its page. The folder name
  doesn't change. The core's own title is `|cff82c5ffRazzh|r|cffffffffUI|r`.
- `## Notes` is the checkbox's tooltip.
- `## Category: Forever Enhanced Addons` stays, on the modules and on the core.

The core's TOC has no `Group` and no `Dependencies`. ForeverDev is not a module.

### The core's API

One global table, `RazzhUI` (the way ForeverDev exposes `ForeverDev`), with two functions:

- `RazzhUI.RegisterOptions(addonName)` returns `category, layout`: a vertical-layout
  subcategory of the "RazzhUI" category, named with the module's short name
  (`Settings.RegisterVerticalLayoutSubcategory`). The module fills it with the `Settings` calls
  it uses today. A second call for the same addon returns the same pair.
- `RazzhUI.OpenOptions(addonName)` opens Options at that module's page, or at the
  "RazzhUI" page when `addonName` is nil or has no page. In combat it opens nothing and
  shows Blizzard's red "can't do that in combat" error text (`ERR_NOT_IN_COMBAT` on
  `UIErrorsFrame`): opening a panel from addon code is refused in combat.

Both check their argument and raise with `error(message, 2)`, so the error names the calling
module's file. `scripts/devlog.sh` credits an error to the first addon path in it; without the
level it would be filed under the core and hidden from the module's worktree.

The root category is created when the core's files load, which is before any module's
(`Dependencies`), and its children are sorted by name (`category:SetShouldSortAlphabetically(true)`).

### A module's options (the pilot)

`addons/ForeverTooltip/Options.lua` changes in two places:

```lua
-- before
local category = Settings.RegisterVerticalLayoutCategory(ADDON_NAME)
...
Settings.RegisterAddOnCategory(category)

-- after
local category = RazzhUI.RegisterOptions(ADDON_NAME)
...
-- (no RegisterAddOnCategory: a subcategory is registered by its parent)
```

Everything between stays: the same settings, variable names and saved keys.

### The modules list

The "RazzhUI" page, top to bottom:

```
RazzhUI                                   [Defaults]
  Modules
  [x] Tooltip          (tooltip: the module's Notes, then a "requires a UI reload" line)
  [x] ...
  [ Reload UI ]
```

- **Finding modules:** every addon index from 1 to `C_AddOns.GetNumAddOns()` whose
  `C_AddOns.GetAddOnDependencies` include the core's folder name. Per module: folder, short name
  (from `Title`), notes, whether it is loaded (`IsAddOnLoaded`), whether it is enabled for this
  character (`GetAddOnEnableState` with the player's GUID, as `AddOnUtil` does). This is a pure
  function over the `C_AddOns` answers, apart from the Settings code. Sorted by short name.
- **Each checkbox** is a proxy setting (`Settings.RegisterProxySetting`, variable
  `RAZZHUI_MODULE_<FOLDER IN UPPER CASE>`). Reading it gives "enabled for
  this character". Writing it calls `C_AddOns.EnableAddOn(folder)` or `DisableAddOn(folder)`
  **for all characters**: the suite is one account-wide choice, and Blizzard's AddOns list
  remains for per-character exceptions.
- **No default and no commit flag on these settings.** The proxy setting is registered with an
  explicit `Settings.VarType.Boolean` and a nil default. `SetValueToDefault` then skips it
  (`Blizzard_Setting.lua:139-143`), so neither this page's Defaults button nor "All Settings"
  pressed anywhere else in Options (Graphics, say) switches modules back on.
  `Settings.CommitFlag.UIReload` is not used: it would add Blizzard's reload line to the tooltip,
  but it also makes Defaults call `UIReload()` at once (`Blizzard_SettingsPanel.lua:397-413,
  478-492, 519-542`). The tooltip instead ends with that same line, added by the core
  (`VIDEO_OPTIONS_NEED_UIRELOAD`, or the core's own sentence if the string is missing in game).
- **Reload UI** (`RELOADUI` for its text) calls `ReloadUI()` from the click; Forever only allows
  a reload inside a click or keypress. It is enabled only while some module's checkbox differs
  from whether that module is loaded (`AddModifyPredicate`, re-evaluated when a module's setting
  changes: `initializer:AddEvaluateStateCVar(variable)` listens by variable name,
  `Blizzard_SettingControls.lua:194-199`).
- If no module is installed, the page has one line saying so.

### The Esc-menu button

- Our own button, created once, parented to `GameMenuFrame`, from the template Blizzard's menu
  buttons use (`GameMenuFrameButtonTemplate` or its parent `MainMenuFrameButtonTemplate`; the
  builder picks the one that looks identical). Text "RazzhUI".
- Placed each time the menu is laid out (`hooksecurefunc(GameMenuFrame, "Layout", ...)` and/or
  `EventRegistry "GameMenuFrame.Shown"`; the menu also rebuilds while open on
  `STORE_STATUS_CHANGED`). It sits as its own section directly above "AddOns" (found by its text,
  `ADDONS`); if that button is absent (`GameRulesUtil.ShouldShowAddOns()`), above "Edit Mode",
  else above "Support". The buttons from there down move by our button's height plus the section
  gap, and the frame grows by the same.
- State about the menu is kept in the core's own locals, never as fields on Blizzard's frames.
- In combat the button is hidden and nothing is moved: `HideUIPanel` from addon code is refused
  in combat, so the click couldn't work.
- Click: `PlaySound(SOUNDKIT.IG_MAINMENU_OPTION)`, `HideUIPanel(GameMenuFrame)`,
  `RazzhUI.OpenOptions()`, the shape of Blizzard's own menu callbacks
  (`GameMenuFrame.lua:166-172`).
- EllesmereUI is installed on the user's client and moves the same buttons in the same hook.
  Both buttons must show without overlapping; the builder reads its code
  (`EllesmereUI.lua:4461-4676`) for what it re-anchors.

### The Addon Compartment entry

`## AddonCompartmentFunc: RazzhUI_OnAddonCompartmentClick` and an `## IconTexture` on the
core. The function calls `RazzhUI.OpenOptions()`. It is the way in if the Esc-menu button
ever has to go.

### Files (a suggestion)

```
addons/RazzhUI/
  RazzhUI.toc     Category, X-Category, IconTexture, AddonCompartmentFunc, OptionalDeps ForeverDev (do-not-package)
  Core.lua                the dev shim, ns.L, the RazzhUI global
  Modules.lua             pure: which addons are modules, their names and states
  Options.lua             the root category, the modules page, RegisterOptions, OpenOptions
  GameMenu.lua            the Esc-menu button
  CHANGELOG.md, .pkgmeta
```

### Tooling

- **`scripts/lint.sh`, TOC checks.** For every TOC with a `## Dependencies` line: each addon
  named there is a folder under `addons/`; a TOC that depends on `RazzhUI` also has
  `## Group: RazzhUI` and a title starting with `RazzhUI `. Every addon folder
  that is neither the core nor ForeverDev and has none of the three lines is still fine in this
  step (step 2 turns that into a failure).
- **`template/Addon`.** The TOC gets the three module lines, so `scripts/new-addon.sh` scaffolds
  a module.
- **`scripts/worktree.sh`.** `game` prints a notice when the core's link points at another
  worktree ("RazzhUI loads from <name>: this worktree's modules run against that copy"),
  and when the core isn't linked at all. `status` already shows where each link points.
- **`scripts/devlog.sh`.** In a worktree it also shows the core's lines and errors, the way it
  already shows errors that name no addon: a module's bug can surface inside the core.
- **`.luacheckrc`.** An entry for the core: `RazzhUI`, `RazzhUI_OnAddonCompartmentClick`.
- **CLAUDE.md.** Layout (the core and what a module is), Worktrees (the core is shared like
  ForeverDev; claim it only on a branch that changes it), Code conventions (a module's options
  go through `RazzhUI.RegisterOptions`; nothing module-specific in the core).

### Changelogs

- `addons/RazzhUI/CHANGELOG.md`: the Esc-menu button and the modules page.
- `addons/ForeverTooltip/CHANGELOG.md`: its options moved under RazzhUI, and it now
  needs RazzhUI.

## Constraints

- Lua 5.1; `local ADDON_NAME, ns = ...`; the only globals are `RazzhUI` and
  `RazzhUI_OnAddonCompartmentClick`.
- Every API is checked in `.cache/wow-ui-source` before its first use. Strings come from
  Blizzard's GlobalStrings where one exists (`RELOADUI`, `ADDONS`); global strings aren't in
  `.cache/`, so their presence is an in-game check.
- `ns.log` tags, listed in the core's shim: `LOADED`, `MODULES`, `OPTIONS`, `TOGGLE`, `MENU`.
- No `## SavedVariables` on the core.
- The core's TOC follows the released-addon rules (Interface, Version, X-License, Category).

## In-game checks

| Check | How it shows |
|---|---|
| The AddOns list nests ForeverTooltip under RazzhUI, and nothing else | by eye; `MODULES` lists the modules found, each with loaded and enabled |
| With the core disabled, ForeverTooltip doesn't load | by eye in the AddOns list (dependency state), and tooltips are stock |
| The Esc menu shows "RazzhUI" above "AddOns", the text fits the button, and it opens Options at our page, on the AddOns tab | by eye; `MENU placed` (once per session: the anchor button found) and `MENU click` |
| No taint from the button | open the Esc menu, then: Logout (cancel), Macros, Edit Mode (enter and leave), Options, Exit Game (cancel), out of combat and again in combat; `scripts/devlog.sh --errors` shows no blocked action |
| In combat the button is hidden and the menu is stock | by eye; `MENU hidden combat` |
| With EllesmereUI enabled, both menu buttons show and none overlap | by eye, a screenshot |
| ForeverTooltip's page is under RazzhUI, works as before, keeps its values | by eye; no top-level "ForeverTooltip" entry; `OPTIONS page ForeverTooltip` |
| A subcategory registered after the root shows up | the row above |
| Unticking Tooltip and pressing Reload UI turns it off: no page, stock tooltips, box unticked | `TOGGLE ForeverTooltip false`; next session's `MODULES` |
| Ticking it and reloading brings it back with its settings | `TOGGLE ForeverTooltip true`; next session's `MODULES` |
| A toggle without the reload button, then `/rl` or logout | next session's `MODULES`: is the change kept? |
| Defaults on our page, and "All Settings" from another page, leave the modules as they are and don't reload | by eye; no `TOGGLE` line |
| The compartment entry opens the same page; in combat it shows the error text | by eye; `OPTIONS open`, `OPTIONS combat` |
| `RELOADUI`, `ADDONS`, `VIDEO_OPTIONS_NEED_UIRELOAD` and `ERR_NOT_IN_COMBAT` exist and read well | `LOADED` logs them |
| `UnitGUID("player")` is readable for the enable-state lookup | `MODULES` logs whether it is secret; if it is, look the state up by character name |

Fallbacks if a check fails:

- The button taints the menu: place it without moving Blizzard's buttons (below the menu frame).
  Still tainting: drop the button, keep the compartment entry, amend ADR 0004.
- Options doesn't open from the click: defer the open one frame (`C_Timer.After(0, ...)`), as
  EllesmereUI does from its Settings stub.
- An unreloaded toggle is lost or half-applied: write the change only when Reload UI is pressed.

## Left to the builder

- The file split, and the wording of the page's lines and the changelog entries.
- How the menu button is placed (which hook, how the other buttons are moved) within the rules
  above, and how it coexists with EllesmereUI's.
- The core's icon and `X-Category`.
- The exact text of the worktree and devlog notices.
