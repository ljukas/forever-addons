# RazzhUI Minimap Button Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The suite core `addons/RazzhUI` gets a minimap button that opens its options page, can be
dragged round the minimap's edge and hidden, and is collected by ForeverMinimap's button bag.

**Architecture:** A plain named `Button` parented to `Minimap` (no library), its angle and hidden
state in a new account-wide `RazzhUIDB`, the edge maths as a pure `Logic/Edge.lua`, and a
"Show minimap button" proxy setting on the core's existing Options page.

**Tech Stack:** Lua 5.1 on the Forever client (interface 16001), Blizzard's `Settings` API,
ForeverDev logging (`ns.log`). No automated tests exist for addon code: each task's check is
`scripts/lint.sh`, and behaviour is checked in game (the table at the end).

**Spec:** `docs/superpowers/specs/2026-11-18-razzhui-minimap-button-design.md`

One PR: `feat(razzhui): add a minimap button`.

## Global Constraints

- The core names no module and no other addon; ForeverMinimap is not changed.
- No library. No field written on a Blizzard frame; `Minimap` is only read, parented to and hooked
  with `HookScript`.
- Globals added: `RazzhUIMinimapButton` (the frame's name) and `RazzhUIDB` (SavedVariables). Nothing else.
- `RazzhUIDB` holds the core's own settings only. `DB_VERSION = 1`. Defaults are not written into it.
- The Settings variable name `RAZZHUI_MINIMAP_BUTTON` is player-facing and fixed from now on.
- Strings in `ns.L` (`Core.lua`), logging through `ns.log` with the tag `MINIMAP`, listed in the
  shim comment. Work done only for a log line goes inside `if ns.dev.enabled then`.
- Every API is looked up in `.cache/wow-ui-source` (build 70959) before its first use.
- After every task: `stylua addons template types` and `scripts/lint.sh` clean, then one commit
  with `git add <paths>` and `git branch --show-current` in the same command.

## Review Focus

1. **The checkbox is read before `RazzhUIDB` has loaded** (Options.lua registers it at file load).
   `ns.MinimapButton.IsShown()` must answer `true` without a database, not throw.
2. **A damaged or hand-edited `RazzhUIDB`** (not a table, `minimap` a string, `angle` a string,
   `hide` a number): the addon loads, the button sits at the default spot and is shown.
3. **A collector addon holds the button** (its parent is not `Minimap`): `Place` and the drag must
   do nothing, including from the `OnSizeChanged` hook; `SetShown` must still work.
4. **Hidden at login, shown later:** the button is created even when hidden, so the bag can have
   found it; showing it must not need a reload.
5. **A drag's mouse-up must not also open Options**, and a drag must not start while the cursor
   position or the minimap's centre can't be read (secret): the button stays where it is.

---

### Task 1: Storage

**Files:**
- Create: `addons/RazzhUI/Database.lua`
- Modify: `addons/RazzhUI/RazzhUI.toc`, `addons/RazzhUI/Core.lua`, `.luacheckrc`

**Interfaces:**
- Produces: `ns.OnInitialize(func)` (runs `func` once `RazzhUIDB` is loaded and migrated, in the
  order registered); `ns.db` (the table, nil before that); `ns.DB.Migrate(db)`;
  `ns.DB.Minimap()` returning `ns.db.minimap`, or nil before the database has loaded.

- [ ] **Step 1:** `RazzhUI.toc`: add `## SavedVariables: RazzhUIDB` after `## X-Category`, and
  `Database.lua` after `Core.lua` in the file list.
- [ ] **Step 2:** `Database.lua`: header comment with the layout from the spec and its owner;
  `DB_VERSION = 1`; `migrations[1]` sets `db.minimap = {}` unless it is a table; `Migrate` as in
  `addons/ForeverDungeonXP/Database.lua` (a non-number `version` counts as 0, a newer one is left
  alone); `ns.DB.Minimap()`.
- [ ] **Step 3:** `Core.lua`: `ns.OnInitialize` and its list; in the existing
  `EventUtil.ContinueOnAddOnLoaded` handler, first make `RazzhUIDB` a table if it isn't one, set
  `ns.db`, migrate, run the initializers, then the existing `LOADED` lines plus
  `ns.log("LOADED", "db version", ns.db.version)`.
- [ ] **Step 4:** `.luacheckrc`: add `"RazzhUIDB"` to the RazzhUI `globals` list.
- [ ] **Step 5:** `stylua addons template types && scripts/lint.sh` → clean. Commit
  `feat(razzhui): give the core a saved-settings table`.
- [ ] **Step 6 (gate):** dispatch `savedvariables-guard` on the commit; fix or rule on every
  finding before Task 3 builds on the layout.

### Task 2: Edge maths

**Files:**
- Create: `addons/RazzhUI/Logic/Edge.lua`
- Modify: `addons/RazzhUI/RazzhUI.toc` (after `Database.lua`, as `Logic/Edge.lua`)

**Interfaces:**
- Produces: `ns.Edge.DEFAULT_ANGLE = 270`; `ns.Edge.Offset(angle, radius, shape) -> x, y`;
  `ns.Edge.AngleTo(x, y) -> degrees in [0, 360)`.

- [ ] **Step 1:** Copy `addons/ForeverDungeonXP/Logic/Edge.lua` function for function (the same
  quadrant table and maths); only the header comment and `DEFAULT_ANGLE` differ. The comment says
  it is the repo's third copy and why. Keep the worked examples in the comments; they are the
  reviewer's test: `Offset(0, 75, "ROUND") -> 75, 0`, `Offset(90, 75, "ROUND") -> 0, 75`,
  `Offset(45, 75, "SQUARE") -> 67.9, 67.9`, and add `Offset(270, 104, "SQUARE") -> 0, -104`.
- [ ] **Step 2:** lint clean. Commit `feat(razzhui): add the minimap edge maths`.

### Task 3: The button

**Files:**
- Create: `addons/RazzhUI/MinimapButton.lua`
- Modify: `addons/RazzhUI/RazzhUI.toc` (after `Modules.lua`, before `Options.lua`),
  `addons/RazzhUI/Core.lua` (strings, shim comment)

**Interfaces:**
- Consumes: `ns.OnInitialize`, `ns.DB.Minimap()`, `ns.Edge.*`, `RazzhUI.OpenOptions()` (called at
  click time, so `Options.lua` loading later is fine).
- Produces: `ns.MinimapButton.IsShown() -> boolean` (true without a database or with a `hide`
  that isn't `true`); `ns.MinimapButton.SetShown(shown)` (stores `hide = true` or nil, applies it
  to the frame if it exists, logs `MINIMAP shown <bool>`).

- [ ] **Step 1:** `Core.lua`: `ns.L.MINIMAP_SHOW = "Show minimap button"`,
  `MINIMAP_SHOW_TOOLTIP = "Shows the RazzhUI button on the minimap. Drag the button to move it round the minimap's edge."`,
  `MINIMAP_TOOLTIP_CLICK = "Click to open the options."`,
  `MINIMAP_TOOLTIP_DRAG = "Drag to move this button."`; add `MINIMAP  MinimapButton.lua` to the
  shim comment's tag list.
- [ ] **Step 2:** `MinimapButton.lua`, following `addons/ForeverDungeonXP/Launcher.lua`'s
  `CreateButton`, `Place`, `OnMinimap` and `OnDragUpdate` with these differences: the name
  `RazzhUIMinimapButton`; the icon from `C_AddOns.GetAddOnMetadata(ADDON_NAME, "IconTexture")`;
  the angle read through a local `Angle()` that returns `DEFAULT_ANGLE` unless the saved one is a
  number; `OnDragUpdate` also returns early when the cursor position is secret; `OnDragStop` logs
  `MINIMAP angle <degrees>`; the click is `RazzhUI.OpenOptions()` then `ns.log("MINIMAP", "click")`;
  the tooltip is `L.TITLE_COLORED`, the click line, and the drag line only while `OnMinimap()`;
  after creation `button:SetShown(ns.MinimapButton.IsShown())` and
  `ns.log("MINIMAP", "created", angle, shown)`.
- [ ] **Step 3:** lint clean. Commit `feat(razzhui): add a minimap button`.

### Task 4: The checkbox

**Files:**
- Modify: `addons/RazzhUI/Options.lua`

**Interfaces:**
- Consumes: `ns.MinimapButton.IsShown`, `ns.MinimapButton.SetShown`.

- [ ] **Step 1:** Before the Modules header initializer, register
  `Settings.RegisterProxySetting(category, "RAZZHUI_MINIMAP_BUTTON", Settings.VarType.Boolean, L.MINIMAP_SHOW, Settings.Default.True, ns.MinimapButton.IsShown, ns.MinimapButton.SetShown)`
  and `Settings.CreateCheckbox(category, setting, L.MINIMAP_SHOW_TOOLTIP)`. Update the file's
  header comment.
- [ ] **Step 2:** lint clean. Commit `feat(razzhui): add a switch for the minimap button`.

### Task 5: Records

**Files:**
- Modify: `addons/RazzhUI/CHANGELOG.md`, `docs/superpowers/roadmaps/2026-11-17-forever-enhanced-suite.md`,
  `docs/superpowers/specs/2026-11-17-forever-enhanced-suite-scope-map.md`,
  `docs/adr/0004-structure-the-addons-as-one-suite.md`, `CLAUDE.md`

- [ ] **Step 1:** CHANGELOG, under `## Unreleased`: "Adds a RazzhUI button to the minimap, which
  opens the addon's Options page. Drag it round the minimap's edge to move it, or hide it with
  "Show minimap button" on the RazzhUI page."
- [ ] **Step 2:** Roadmap row 1b: the spec and plan paths and its status. Scope map: take "a
  minimap button" out of the deferred line. ADR 0004, Consequences: the core has a small saved
  table of its own for its minimap button since step 1b; modules' data stays in their own tables.
  CLAUDE.md, Layout: the core's description gains the minimap button and says what `RazzhUIDB` holds
  in place of "no SavedVariables".
- [ ] **Step 3:** Commit `docs(razzhui): record the minimap button`.

## Step reviewers (Phase 5)

Core: `addon-reviewer`, `api-verifier`, a correctness reviewer and a spec reviewer. Specialists:
`savedvariables-guard` (new SavedVariables and a settings key) and a UI reviewer (a frame on the
minimap, textures, a settings row). Each gets the Review Focus above.

## In-game checks

The spec's table. Every row has its `MINIMAP`, `OPTIONS` or `BAG` line; rows that are "by eye" are
the user's to look at.

## What the build changed (after the audit and the step review)

The tasks above are the plan as written. The build differs in these places; the spec holds the
final design.

- Task 1: the migration also starts over from a negative or fractional `version`, replaces a
  non-table `minimap` at the current version, and `ns.DB.Minimap()` returns nil for a non-table.
- Task 2: `DEFAULT_ANGLE` is 160, not 270 (six o'clock sits on Blizzard's coordinates text).
- Task 3: the angle and the shown state live in locals loaded once the settings are in, in place
  of an `Angle()` helper; the angle is saved while dragging and only when the button moved; a drag
  also ends once the mouse button is up; the click logs before it opens Options; the button is
  placed again a frame after its parent changes; the icon sinks a pixel while held; the `created`
  line carries the icon path. `MINIMAP_SHOW_TOOLTIP` is "Show the RazzhUI button on the minimap.
  It opens this page."
- Task 5: the TOC's `## Notes` names the minimap button too.
