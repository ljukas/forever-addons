# RazzhUI: a minimap button

Date: 2026-11-18. Roadmap step 1b (`docs/superpowers/roadmaps/2026-11-17-forever-enhanced-suite.md`).
Working PR title: `feat(razzhui): add a minimap button`.

## Intent

After testing the core in game, the user looked for RazzhUI in ForeverMinimap's button bag (which
they call the minimap dropdown), where EllesmereUI's button sits, and it wasn't there. The core only
has an entry in Blizzard's Addon Compartment, and the bag collects real minimap button frames. So
the core gets a real minimap button that opens the RazzhUI options page.

Step 1's design (`2026-11-17-forever-enhanced-core-design.md`) listed a minimap button as out of
scope and the scope map listed it as deferred. This step takes it in; the scope map's line is
updated.

## Goals, non-goals

- **Goal:** a button on the minimap that the bag collects without either addon naming the other,
  and whose click opens Options at the RazzhUI page.
- **Goal:** the look of every other addon's minimap button, built from Blizzard's own textures.
- **Not in this step:** dragging the button, hiding it, a right-click action, a logo of our own.
- **Must not happen:** the core naming ForeverMinimap (or any module), a library in the core, a
  field written on a Blizzard frame.

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

## Approaches

1. **A plain frame at a fixed spot, nothing stored (proposed).** One new file of about 60 lines.
   The button can't be dragged or hidden on its own: with the bag on it lives in the bag, where the
   bag places it and can keep it out ("keep on the minimap"); with the bag off it stays at its spot.
   The core keeps storing nothing, as ADR 0004 and step 1's design say. Dragging and hiding can be
   added later without a migration, because there is no stored data to change.
2. **A plain frame the player can drag and hide, with SavedVariables.** As ForeverDungeonXP's
   button (`addons/ForeverDungeonXP/Launcher.lua`): the angle saved, plus a "Show minimap button"
   checkbox on the RazzhUI page. The core gets `## SavedVariables: RazzhUIDB`, a `Database.lua` with
   defaults and a version, and the edge maths (`Logic/Edge.lua`, of which the repo already has two
   copies) a third time or moved into the core first. About three times the code, and step 1's
   "the core stores nothing" is amended.
3. **LibDBIcon and LibDataBroker.** Drag, hide and lock come with the library, and the bag has a
   path for LibDBIcon buttons. But it needs a saved table as well, adds four libraries to an addon
   that has none, and both are published as SVN repositories, which `scripts/libs.sh` can't fetch
   (the reason ForeverDungeonXP built its own). Dropped.

## Design (approach 1)

A new file `addons/RazzhUI/MinimapButton.lua`, listed last in `RazzhUI.toc`.

- **Frame:** `CreateFrame("Button", "RazzhUIMinimapButton", Minimap)`, created when the file loads
  (as `GameMenu.lua` creates its button), 31 x 31, strata `MEDIUM`, level 8, left click only. The
  name is the core's one new global, needed because the bag (and every other collector addon)
  recognizes a button by its global name. It is a plain, unprotected frame, so nothing about it
  is limited in combat.
- **Art:** the same four textures as ForeverDungeonXP's and EllesmereUI's buttons, so it looks like
  its neighbours in the bag: `Interface\Minimap\UI-Minimap-Background` (24 px), the icon (18 px,
  edges cropped), `Interface\Minimap\MiniMap-TrackingBorder` (the gold ring, 50 px from the top
  left) and `Interface\Minimap\UI-Minimap-ZoomButton-Highlight` on mouseover.
- **Icon:** the TOC's `## IconTexture` (the gear the Addon Compartment entry shows), read with
  `C_AddOns.GetAddOnMetadata`, so the two entries always show the same icon.
- **Place:** `SetPoint("CENTER", Minimap, "BOTTOM", 0, -5)`: six o'clock, the centre 5 px outside
  the edge. A point straight below the centre is on the edge whatever the minimap's size or shape
  (round or square), so there is no angle maths, no `GetMinimapShape` table and no hook on
  `Minimap`. Six o'clock is clear of Blizzard's zoom buttons (bottom right) and of the other
  buttons' default spots (200 to 225 degrees).
- **Click:** `RazzhUI.OpenOptions()`, which already shows the red "can't do that in combat" text
  instead of opening while in combat.
- **Tooltip:** "RazzhUI" in Forever bronze (`ns.L.TITLE_COLORED`) and one line, "Click to open the
  options." (`ns.L.MINIMAP_TOOLTIP`).
- **Logging:** a new tag `MINIMAP` in the shim comment: `MINIMAP created` once, `MINIMAP click` on
  a click (followed by `OPTIONS open root` or `OPTIONS combat` from `OpenOptions`).

Also: a line under `## Unreleased` in `addons/RazzhUI/CHANGELOG.md`; the roadmap row for 1b; the
scope map's "deferred" line; CLAUDE.md's description of the core; `razzhui-launch-checks`.

## In-game checks

| Check | Evidence |
|---|---|
| The button is collected by the bag and sits in the strip with the gear icon and gold ring | `scripts/devlog.sh --all-addons --addon ForeverMinimap --tag BAG`: `collect RazzhUIMinimapButton`; by eye |
| A click opens Options at the RazzhUI page | `MINIMAP click`, `OPTIONS open root` |
| "Keep on the minimap" in the bag's menu puts it at six o'clock, clear of everything else | by eye; `BAG release RazzhUIMinimapButton` |
| In combat a click shows the red error text and opens nothing | `MINIMAP click`, `OPTIONS combat`; `scripts/devlog.sh --errors` clean |

## Calls made by Claude, for the user to correct

- The classic gold-ring look rather than the bag button's own Forever ring, because that is what
  the button's neighbours in the bag wear.
- The gear icon from the TOC, not a logo.
- Six o'clock as the fixed spot.
- No press animation and no click sound, as ForeverDungeonXP's button has none.
