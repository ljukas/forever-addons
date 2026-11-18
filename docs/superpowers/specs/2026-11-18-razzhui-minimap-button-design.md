# RazzhUI: a minimap button

Date: 2026-11-18. Roadmap step 1b (`docs/superpowers/roadmaps/2026-11-17-forever-enhanced-suite.md`).
Working PR title: `feat(razzhui): add a minimap button`.

## Intent

After testing the core in game, the user looked for RazzhUI in ForeverMinimap's button bag (which
they call the minimap dropdown), where EllesmereUI's button sits, and it wasn't there. The core only
has an entry in Blizzard's Addon Compartment, and the bag collects real minimap button frames. So
the core gets a real minimap button that opens the RazzhUI options page.

Step 1's design (`2026-11-17-forever-enhanced-core-design.md`) listed a minimap button and
SavedVariables for the core as out of scope, and the scope map listed the button as deferred. This
step takes both in; the scope map, ADR 0004 and CLAUDE.md are updated to say so.

## Goals, non-goals

- **Goal:** a button on the minimap that the bag collects without either addon naming the other,
  and whose click opens Options at the RazzhUI page.
- **Goal:** the player can drag it round the minimap's edge and hide it, and both are remembered.
- **Goal:** the look of every other addon's minimap button, built from Blizzard's own textures.
- **Not in this step:** a right-click action, a lock, a logo of our own, per-character settings.
- **Must not happen:** the core naming ForeverMinimap (or any module), a library in the core, a
  field written on a Blizzard frame, a module's data in the core's saved table.

## What the bag collects (read from `addons/ForeverMinimap`)

`ButtonBag.lua` looks at the named children of `Minimap`, `MinimapBackdrop` and `MinimapCluster`.
`Reject` (`ButtonBag.lua:64`) and `ButtonRules.Verdict` keep a frame when all of these hold:

- it has a name, the name is its global (`_G[name] == frame`), and the name is not Blizzard's, not a
  pin addon's (`^ForeverMinimap`, `^ForeverProfessions`, `^Questie`, ...) and does not end in digits;
- it is a `Button` with an `OnClick` handler, and it is not protected;
- its centre is between 0.7 and 1.6 minimap radii from the minimap's centre.

The devlog of session 274 (18 November 2026, client 70959) shows two plain frames collected this
way: `BAG collect EllesmereUIMinimapButton` and `BAG collect ForeverDungeonXPMinimapButton`. A button
named `RazzhUIMinimapButton`, a child of `Minimap` sitting on its edge, meets every rule. The bag
labels it with the creating addon's TOC title, which is "RazzhUI" in bronze.

While the bag holds a button it reparents it, places it and clears its drag registration, and it
leaves the button's own shown state alone: a hidden button is left out of the strip.

## Approaches

1. **A plain frame at a fixed spot, nothing stored.** One file of about 60 lines; the button can't
   be dragged or hidden on its own. Claude proposed this one.
2. **A plain frame the player can drag and hide, with SavedVariables (chosen by the user on
   18 November 2026: "Draggable and hideable").** As ForeverDungeonXP's button
   (`addons/ForeverDungeonXP/Launcher.lua`): the angle saved, plus a "Show minimap button"
   checkbox on the RazzhUI page. The core gets `## SavedVariables: RazzhUIDB` and a `Database.lua`.
3. **LibDBIcon and LibDataBroker.** Drag, hide and lock come with the library, and the bag has a
   path for LibDBIcon buttons. But it needs a saved table as well, adds four libraries to an addon
   that has none, and both are published as SVN repositories, which `scripts/libs.sh` can't fetch
   (the reason ForeverDungeonXP built its own). Dropped.

## Design

### Storage: `RazzhUIDB` (account-wide), `addons/RazzhUI/Database.lua`

```
RazzhUIDB = {
  version = 1,
  minimap = {            -- owned by MinimapButton.lua
    angle = number|nil,  -- degrees counter-clockwise from east; nil until first dragged
    hide  = true|nil,    -- true once the player unticks "Show minimap button"
  },
}
```

The repo's pattern (`addons/ForeverDungeonXP/Database.lua`): `DB_VERSION = 1`, `migrations[1]`
makes `minimap` a table, a newer version's data is left alone. Defaults are not written: a missing
`angle` reads as the default and a missing `hide` as shown, so a later change of default reaches
everyone who never chose. A hand-edited value of the wrong type reads as the default too.

`Core.lua` gets the usual `ns.OnInitialize(func)` list, run in TOC order from its existing
`ADDON_LOADED` handler after `RazzhUIDB` is set up and migrated. It holds the core's own settings
only; modules keep their own tables (ADR 0004).

### Edge maths: `addons/RazzhUI/Logic/Edge.lua`

`ns.Edge.Offset(angle, radius, shape)` and `ns.Edge.AngleTo(x, y)`, pure, the same as
`addons/ForeverDungeonXP/Logic/Edge.lua` (itself ForeverMinimap's `Logic/Ring.lua`), so the button
lands where any other minimap button would for the same angle, on a round or a square minimap. It is
the repo's third copy: the two addons that hold the others are not modules yet and can't call the
core. Roadmap step 4 (shared code into the core) is where they become one.

`DEFAULT_ANGLE = 270`: six o'clock, clear of Blizzard's zoom buttons (bottom right) and of the
other buttons' default spots (ForeverDungeonXP 200, EllesmereUI 220, LibDBIcon and the bag 225).

### The button: `addons/RazzhUI/MinimapButton.lua`

- **Frame:** `CreateFrame("Button", "RazzhUIMinimapButton", Minimap)`, created from `OnInitialize`
  (it needs the saved angle), 31 x 31, strata `MEDIUM`, level 8, left click, left drag. The name
  is a new global, needed because the bag (and every other collector addon) recognizes a button
  by its global name. It is a plain, unprotected frame, so nothing about it is limited in combat.
- **Art:** the same four textures as ForeverDungeonXP's and EllesmereUI's buttons, so it looks like
  its neighbours in the bag: `Interface\Minimap\UI-Minimap-Background` (24 px), the icon (18 px,
  edges cropped), `Interface\Minimap\MiniMap-TrackingBorder` (the gold ring, 50 px from the top
  left) and `Interface\Minimap\UI-Minimap-ZoomButton-Highlight` on mouseover.
- **Icon:** the TOC's `## IconTexture` (the gear the Addon Compartment entry shows), read with
  `C_AddOns.GetAddOnMetadata`, so the two entries always show the same icon.
- **Place:** `CENTER` to `Minimap`'s `CENTER` at `Edge.Offset(angle, width / 2 + 5, shape)`, set
  again when the minimap's size changes (`Minimap:HookScript("OnSizeChanged")`, as the other two
  buttons do).
- **Drag:** while dragged the button follows the cursor round the edge and the angle is saved as it
  goes. Placing and dragging do nothing while the button's parent isn't `Minimap`: a collector
  addon has it then, and it is that addon's to place.
- **Click:** `RazzhUI.OpenOptions()`, which already shows the red "can't do that in combat" text
  instead of opening while in combat.
- **Tooltip:** "RazzhUI" in Forever bronze (`ns.L.TITLE_COLORED`), "Click to open the options.",
  and, while it is on the minimap, "Drag to move this button."
- **Hide:** `ns.MinimapButton.IsShown()` and `ns.MinimapButton.SetShown(shown)` read and write
  `minimap.hide` and show or hide the frame. The button is always created, so a collector that
  found it hidden has it when it is shown again.
- **Logging:** a new tag `MINIMAP` in the shim comment: `MINIMAP created <angle> <shown>` once,
  `MINIMAP click` on a click (followed by `OPTIONS open root` or `OPTIONS combat`),
  `MINIMAP angle <degrees>` when a drag ends, `MINIMAP shown <true|false>` from the checkbox.

### The checkbox: `addons/RazzhUI/Options.lua`

"Show minimap button", the first row of the RazzhUI page, above the Modules header. It is a proxy
setting (`Settings.RegisterProxySetting`, as the module switches are) with the variable
`RAZZHUI_MINIMAP_BUTTON`, default on, reading and writing through `ns.MinimapButton`. A proxy
setting is registered when the file loads, before `RazzhUIDB` exists, which a table-backed setting
can't be; nothing reads it until the page is shown. The page's Defaults button turns it back on.

### Also

`RazzhUI.toc` (`## SavedVariables: RazzhUIDB`, the three new files), `.luacheckrc` (`RazzhUIDB`),
a line under `## Unreleased` in `addons/RazzhUI/CHANGELOG.md`, the roadmap row for 1b, the scope
map's "deferred" line, ADR 0004's consequences, CLAUDE.md's description of the core (it says "no
SavedVariables"), and the `razzhui-launch-checks` memory.

## In-game checks

| Check | Evidence |
|---|---|
| The button is collected by the bag and sits in the strip with the gear icon and gold ring | `scripts/devlog.sh --all-addons --addon ForeverMinimap --tag BAG`: `collect RazzhUIMinimapButton`; by eye |
| A click opens Options at the RazzhUI page | `MINIMAP click`, `OPTIONS open root` |
| Unticking "Show minimap button" removes it from the strip; ticking brings it back; both survive `/rl` | `MINIMAP shown false`, `MINIMAP created <angle> false` after the reload |
| "Keep on the minimap" in the bag's menu puts it at six o'clock, clear of everything else | by eye; `BAG release RazzhUIMinimapButton` |
| On the minimap it drags round the edge, stays there after `/rl`, and a drag doesn't open Options | `MINIMAP angle <degrees>`, no `MINIMAP click` after it; `MINIMAP created <the same angle>` |
| In combat a click shows the red error text and opens nothing | `MINIMAP click`, `OPTIONS combat`; `scripts/devlog.sh --errors` clean |

## Calls made by Claude, for the user to correct

- The classic gold-ring look rather than the bag button's own Forever ring, because that is what
  the button's neighbours in the bag wear.
- The gear icon from the TOC, not a logo.
- Six o'clock as the default spot.
- Hiding is the checkbox only: no middle-click on the button (EllesmereUI has one), so it can't be
  hidden by accident.
- The checkbox goes first on the RazzhUI page, above Modules.
- Account-wide settings, like every other addon in the repo.
- No press animation and no click sound, as ForeverDungeonXP's button has none.
