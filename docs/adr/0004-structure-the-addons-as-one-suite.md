# 0004. Structure the addons as one suite: a core addon, dependent modules, Blizzard's Options as the window

Date: 2026-11-17. Status: accepted (in-game checks pending, see the scope map).

## Context

The repo holds ten released addons that players would install one by one, each with its own entry
under Options > AddOns (or no options at all). The user wants what EllesmereUI has: **one thing to
install**, whose parts are switched on and off in **one options window** opened from the Esc menu,
with a part's options editable while it is on. Two constraints from the user: keep Blizzard's UI
language (not EllesmereUI's custom look), and keep the repo's way of working, where several
sessions each work on a different addon in its own worktree.

EllesmereUI 9.8.8 is installed locally and was read for how it does this (not for its look):

- Every child TOC has `## Dependencies: EllesmereUI` and `## Group: EllesmereUI`. The Group line
  is what nests the children under the parent in the AddOns list.
- The on/off switch is a real addon disable: `C_AddOns.DisableAddOn` / `EnableAddOn`, then a
  reload. A module that is off never loads.
- Its Esc-menu button is its own button, placed after Blizzard lays the menu out and hidden in
  combat. The Game Menu has no API for adding one.
- All module options live in one load-on-demand `EllesmereUIOptions` addon (169,000 lines), so
  none of it is parsed until the window opens, and the core holds three hand-kept lists of
  modules. A module change there usually edits the core, the Options addon and the module.

Nothing in this repo has been released (no tags, every changelog is `## Unreleased`), so names
and layouts can still change freely.

## Decision

1. **A core addon, `RazzhUI`, and every other released addon a module of it.** A module's
   TOC adds `## Dependencies: RazzhUI` and `## Group: RazzhUI`. Modules keep their
   folders, names, saved data and code. ForeverDev stays outside the suite.
2. **The one window is Blizzard's Options window** (the user's pick). The core registers one
   category, "RazzhUI", on the AddOns tab. Its own page lists the modules with a checkbox
   each. Every loaded module's options are a subcategory under it.
3. **Options stay in the module** (the user's wish). A module asks the core for its page
   (`RazzhUI.RegisterOptions`) and fills it with the same `Settings` calls it uses today.
   There is no central options addon: ours total about 300 lines, so EllesmereUI's reason for one
   doesn't apply.
4. **On/off is a real addon disable plus a reload**, as in EllesmereUI and as Blizzard's own
   AddOns list does it. A module that is off has no page and runs no code.
5. **The core finds its modules by itself**: every addon whose TOC lists the core as a
   dependency. No list of modules is kept in the core, so adding a module never edits it.
6. **The Esc-menu button is our own button**, placed after Blizzard's layout, hidden in combat,
   writing no field on `GameMenuFrame` or its pooled buttons.
7. **One download**: the release is one zip with the core and every module folder, one version.
   It is prepared, not cut (the user: "we won't release the addon after this").
8. **Worktree rules.** A module's work touches only its own folder. The core is a shared folder
   like ForeverDev: one checkout holds its game link, a branch claims it only when it changes
   it, and its API only grows; a change that breaks the API updates every module in the same PR.
   Nothing specific to one module goes into the core.

## Alternatives considered

- **Our own window built from Blizzard frame parts** (EllesmereUI's layout: modules on the left
  with a switch each, options on the right). Rejected by the user in favour of Blizzard's Options.
  Blizzard's settings controls can't be reused outside `SettingsPanel` (they read the global
  panel's layout, tooltip and selection), so the core would need its own control kit and the
  existing options pages would be rewritten on it: more code, and a core that changes often.
- **A small modules window that jumps into Blizzard's Options per module.** Two windows; the user
  asked for one.
- **A soft on/off flag** (the module loads and skips its setup). Several addons install
  hooks as their files load (ForeverActionBars and ForeverTooltip among them), and a
  `hooksecurefunc` hook can't be removed. Every addon would need its file-level code moved behind
  a gate, and a module that is "off" would still cost load time.
- **A central options addon and a module roster in the core** (EllesmereUI's way). It makes every
  module change touch shared folders, which is what parallel worktrees can't have.
- **Adding the Esc-menu button with `GameMenuFrame:AddButton` from a hook on `InitButtons`.**
  The pool and its buttons are shared with the Logout, Exit and Edit Mode buttons; addon code
  would write the pool's tables and the frame's counters. It would also land below "Return to
  Game", since that button is added last.
- **One shared SavedVariables table in the core** (EllesmereUI's `EllesmereUIDB`). Needed there
  for profiles. We have no profiles, and per-module tables keep a module's data in its folder.

## Consequences

- Modules no longer load without the core.
- The Options window also shows other addons' categories beside ours, and the on/off switches are
  checkboxes on the "RazzhUI" page, not icons beside each name.
- Switching a module costs a reload.
- A Settings category can't be removed once registered (no API). That is fine with a real
  disable: the page of a module that is off is never registered.
- Whichever checkout holds the core serves every module in game; `scripts/worktree.sh` says so
  when it isn't main.
- The per-addon release (`<Name>-vX.Y.Z` tags, one zip per addon) is replaced by one suite
  release when that step is built.
- Since roadmap step 1b (18 November 2026) the core has a minimap button and, for its place and
  whether it is shown, a small SavedVariables table of its own (`RazzhUIDB`). That is not the
  shared table rejected above: it holds the core's own settings only, and a module's data stays in
  the module's table.
- Open until tested in game: that our Esc-menu button leaves Logout, Exit, Macros and Edit Mode
  untainted, and that it sits well beside EllesmereUI's button when both are installed. If it
  can't be made safe, the Addon Compartment entry stays as the way in and this record is amended.
