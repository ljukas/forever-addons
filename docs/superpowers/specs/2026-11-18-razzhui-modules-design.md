# RazzhUI, step 2: the other nine addons become modules

Date: 2026-11-18. Decision record: `docs/adr/0004-structure-the-addons-as-one-suite.md`.
Scope map: `docs/superpowers/specs/2026-11-17-forever-enhanced-suite-scope-map.md`.
Roadmap: `docs/superpowers/roadmaps/2026-11-17-forever-enhanced-suite.md` (this is step 2).
The core's design, which this builds on: `docs/superpowers/specs/2026-11-17-forever-enhanced-core-design.md`.

## Intent

After step 1 a player has the core and one module beside nine separate addons. This step puts all
ten under RazzhUI, so the AddOns list, the modules page and the options tree show one suite. It
changes where things are listed and reached, not what any addon does.

## Decided by the user

- The nine addons become modules: ForeverActionBars, ForeverBags, ForeverCombat,
  ForeverCombatText, ForeverDungeonXP, ForeverMinimap, ForeverProfessions, ForeverQuests,
  ForeverUnitFrames. ForeverDev stays out.
- Per addon: the three TOC lines, the options page through `RazzhUI.RegisterOptions`, a changelog
  line.
- Nothing breaks saved data: SavedVariables names, settings keys, slash commands and bindings
  stay.
- Nothing about one module goes into the core; the core's API only grows.
- In-game gates, a few addons per gate. Subagent per task for the build.
- Go ahead without the rest of step 1's combat checks (18 November). The devlog shows the
  Esc-menu button hidden in combat and back afterwards (session 275, `MENU hidden combat` then
  `MENU placed AddOns`) and no blocked action from RazzhUI. Combat starting with the menu open,
  and a click on the minimap button or compartment entry in combat, are still unrun.

Everything else below is Claude's call.

## Goals

- Ten modules nested under RazzhUI in the AddOns list, each with a checkbox on the RazzhUI page.
- The four addons with an options page have it under Options > AddOns > RazzhUI, with the same
  settings and saved values as before.
- The two Edit Mode modules have a page that leads to Edit Mode.
- Lint refuses a released addon that is not a module.
- The docs say what is now true: CLAUDE.md, the roadmap, the changelogs.

## Non-goals

- The single zip (step 3) and moving shared code into the core (step 4). The two copies of
  LibEditMode and of the page code below stay per module until then.
- New options for the three addons that have none.
- Changing the core. This branch leaves `addons/RazzhUI` alone, so its game link stays on main.

## Anti-goals

- A player's settings or data reset, or a slash command gone.
- Taint in Edit Mode from our page's button.
- A top-level "ForeverX" entry left under Options > AddOns.

## The nine addons

| Addon | Short name (title after `RazzhUI `) | Options today | Change |
|---|---|---|---|
| ForeverActionBars | Action Bars | none | TOC, changelog |
| ForeverQuests | Quests | none | TOC, changelog |
| ForeverDungeonXP | Dungeon XP | none (`/fdxp`, its own compartment entry) | TOC, changelog |
| ForeverBags | Bags | `Options.lua`, one button | TOC, options parent, changelog |
| ForeverCombat | Combat | `Options.lua`, checkboxes | TOC, options parent, changelog |
| ForeverMinimap | Minimap | `Options.lua`, checkboxes, dropdown, slider | TOC, options parent, changelog |
| ForeverProfessions | Professions | `Options.lua`, checkboxes | TOC, options parent, changelog |
| ForeverCombatText | Combat Text | Edit Mode dialog (LibEditMode) | TOC, new page, changelog |
| ForeverUnitFrames | Unit Frames | Edit Mode dialog (LibEditMode) | TOC, new page, changelog |

The short name is what the player reads on the checkbox and as the page's name, so multi-word
ones get a space. Folder names, `ADDON_NAME`, SavedVariables and setting variables
(`FOREVERMINIMAP_*` and the like) do not change.

### TOC

Each of the nine gets what ForeverTooltip got in PR #50:

```
## Title: |cffd6b380RazzhUI|r <Short name>
## Dependencies: RazzhUI
## Group: RazzhUI
```

and loses `## Category: Forever Enhanced Addons`. So do ForeverTooltip and `template/Addon`.
Blizzard's list reads `Category` only for a group's parent (`AddonList.lua:475-494`); on a nested
addon it does nothing but match the search box. `## X-Category` (the genre) stays. The core
already has no `Category`.

### Options parent (Bags, Combat, Minimap, Professions)

The two-line change from the core design:
`Settings.RegisterVerticalLayoutCategory(ADDON_NAME)` becomes `RazzhUI.RegisterOptions(ADDON_NAME)`
(which also returns the layout), and `Settings.RegisterAddOnCategory(category)` goes. Everything
between stays, including each `Settings.RegisterAddOnSetting` variable name and the table and key
it writes. Comments that say "Options > AddOns > ForeverX" are corrected.

ForeverProfessions sets its settings from elsewhere by variable name (`Settings.SetValue`, for the
world map toggle); that keeps working because the names don't change.

### Modules without options (ActionBars, Quests, DungeonXP)

No page. They appear in the AddOns list and as a checkbox on the RazzhUI page, as the scope map
says. ForeverDungeonXP keeps `/fdxp` and its compartment entry.

### The Edit Mode pages (CombatText, UnitFrames)

The scope map's answer: a page with a button that opens Edit Mode, with a line of text as the
fallback. Each of the two modules gets an `Options.lua` (listed in its TOC) that asks the core for
its page and adds one button row:

```
RazzhUI > Unit Frames
  Player Power Bar                      [ Edit Mode ]
```

- The row's label is the name the module's box has in Edit Mode (`ns.L.POWER_BAR`,
  `ns.L.COMBAT_TEXT`). The button's text is Blizzard's `HUD_EDIT_MODE_MENU`, the string on the
  Esc menu's own button, with a fallback of our own since global strings exist only in game. The
  tooltip says that the box is moved and its settings changed in Edit Mode.
- The click closes Options and opens Edit Mode the way Blizzard's own code does outside the Esc
  menu: `if EditModeManagerFrame:CanEnterEditMode() then ShowUIPanel(EditModeManagerFrame) end`
  (`SlashCommandsOverrides.lua:353`, `Blizzard_CompactRaidFrameManager.lua:1372-1377`).
- In combat it opens nothing and shows `ERR_NOT_IN_COMBAT` in red, as `RazzhUI.OpenOptions`
  does: opening and closing panels from addon code is refused in combat.
- `ns.log("OPTIONS", ...)` on the click, in combat or not, so the gate can see it. The tag goes
  in each module's shim comment.
- **Fallback, if the gate shows a blocked action or broken Edit Mode after our click:** the
  button goes and the page is one line pointing to Esc > Edit Mode (a section header, the only
  plain-text row an addon page has).

## Approaches (for the Edit Mode pages)

1. **Each module builds its own page** (chosen). About 25 lines in each of two modules, the same
   shape twice. The core is untouched, which is what this step's rules ask for, and the
   duplication is listed for step 4 with the rest of the Edit Mode glue.
2. **A helper in the core** (`RazzhUI.AddEditModeButton(layout, label)`). One copy of the
   taint-sensitive click. But the branch would change the core and claim its shared game link,
   and the helper's shape would be fixed by two callers before the gate has shown the click is
   safe at all.
3. **No page.** The two appear only in the modules list; their `## Notes` already mention Edit
   Mode. No taint risk and no code, but a player who looks under RazzhUI for the power bar's
   settings finds nothing, and the roadmap asks for pages.

## Tooling and docs

- **`scripts/lint.sh`:** every addon folder except the core and ForeverDev must be a module (step
  1's design left this for now). The existing three-marks check stays.
- **`template/Addon`:** drop the `Category` line.
- **CLAUDE.md:** Layout says every released addon is a module, that modules carry no `Category`,
  and no longer calls ForeverTooltip "the first".
- **Roadmap:** step 2's status, and what is still untested in game.
- **`.luacheckrc`:** only if luacheck complains about the `RazzhUI` global in a module (it did
  not for ForeverTooltip).

## Changelogs

Nothing is released, so each changelog describes the addon as it will first ship:

- Every one of the nine gets the line ForeverTooltip has: it now needs RazzhUI and is switched on
  or off on the RazzhUI page.
- Lines the change makes false are corrected in place: "Options → AddOns → ForeverMinimap"
  becomes "Options → AddOns → RazzhUI → Minimap" (ForeverMinimap twice, ForeverProfessions
  once), and "Now grouped under "Forever Enhanced Addons" in the AddOns list" (ForeverMinimap,
  ForeverProfessions) goes.
- CombatText and UnitFrames mention their new page.

## Batches and gates

Each batch is built, linted and committed, then `scripts/worktree.sh game` points its addons'
links at this worktree and the user tests. The core's link stays on main throughout.

| Batch | Addons | The gate checks |
|---|---|---|
| A | ActionBars, Quests, DungeonXP (and the `Category` line off ForeverTooltip) | Nesting and the modules list with several modules |
| B | Bags, Combat, Minimap, Professions | Moved pages keep their values |
| C | CombatText, UnitFrames | The Edit Mode button, and taint |
| D | lint, template, CLAUDE.md, roadmap | none in game; the step review follows |

### In-game checks

| Gate | Check | How it shows |
|---|---|---|
| A | The AddOns list nests four modules under RazzhUI with the titles "RazzhUI Action Bars", "RazzhUI Dungeon XP", "RazzhUI Quests", "RazzhUI Tooltip"; none is left under "Forever Enhanced Addons" | by eye; `MODULES` lines from the core, one per module |
| A | The RazzhUI page lists the four, sorted, and the three new ones have no page of their own | by eye |
| A | The three still work: the red range wash, the turn-in fill on the XP bar, `/fdxp` and the journal's compartment entry with its recorded runs | by eye; `scripts/devlog.sh --errors` |
| A | Unticking one of them and pressing Reload UI turns it off; ticking it brings it back | `TOGGLE <Addon> false` / `true`, next session's `MODULES` |
| A | While in game anyway: enter combat with the Esc menu open; click the minimap button in combat | `MENU undone combat`; `OPTIONS combat` and the red text |
| B | Four pages under RazzhUI named Bags, Combat, Minimap, Professions; no top-level ForeverX entry | by eye; `OPTIONS page <Addon>` four times |
| B | Every value is what it was before the move (the bag's scale and direction, the DoT and HoT boxes, the node boxes) | by eye; the SavedVariables files are unchanged in shape |
| B | The world map's node toggle and the Professions page stay in step | by eye |
| B | The button bag still collects the RazzhUI minimap button | `BAG collect RazzhUIMinimapButton` |
| C | Pages "Combat Text" and "Unit Frames", each with its row and an "Edit Mode" button | by eye; `OPTIONS page <Addon>` |
| C | The click closes Options and opens Edit Mode; our box can be selected, moved and saved; Edit Mode closes normally; then Logout (cancel) and Macros from the Esc menu still work | by eye; each module's `OPTIONS` click line; `scripts/devlog.sh --errors` shows no blocked action |
| C | In combat the click opens nothing and shows the red text | the module's `OPTIONS` combat line |
| C | The power bar and the combat text sit where they were, with their sizes | by eye; no `SAVE` line at login |

A failed check is a bug to fix before the next batch, except the Edit Mode click, which has the
fallback above.

## Constraints

- Lua 5.1; `local ADDON_NAME, ns = ...`; no new globals. Modules read the `RazzhUI` global only.
- Every API is checked in `.cache/wow-ui-source` before its first use.
- `savedvariables-guard` runs on the finished step (no layout changes are intended, so there is
  no mid-step gate unless a task turns out to touch one).
- One PR, `feat: move every addon under RazzhUI`. Its Testing section says which gates ran and
  what is still untested in game.

## Left to the builder

- The wording of tooltips, comments and changelog lines.
- Whether Options has to be closed by our code before Edit Mode opens, or `ShowUIPanel` does it
  (read `SettingsPanel` and `UIPanelWindows` in the source).
- Whether the Edit Mode button is greyed when `CanEnterEditMode()` is false.
- The exact lint message.
