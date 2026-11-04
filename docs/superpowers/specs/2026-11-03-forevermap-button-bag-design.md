# ForeverMap: minimap button bag

Date: 2026-11-03 · Status: draft, awaiting approval · Addon: ForeverMap

## Intent

Addons pile their buttons around the minimap until the ring is a cluster of icons. This
feature gathers every addon's minimap button behind **one button on the ring**. Click it and
the collected buttons fold out in a strip; click again and they tuck away. The minimap goes
back to looking like Blizzard's.

The model is [MinimapButtonBag Reborn](https://www.curseforge.com/wow/addons/minimapbuttenbag-reborn)
(a fork of MinimapButtonButton), which the user picked as the closest match. Other collectors
looked at for inspiration: MinimapButtonButton, One For All (Midnight Updated),
MinimapButtonHub, MinimapIconBar, MinimapOrganizer, Leatrix Plus's button bag, MidnightMap.

## Goals

- **Catch everything by default.** Every minimap button that another addon adds is collected,
  whether it comes from LibDBIcon or is a hand-made frame, including addons that load late (on
  demand) or create their button after login.
- **Collected buttons keep working.** Left-click, right-click, drag behaviour inside the strip
  is whatever the addon gave it; tooltips still show. We move and show/hide them, nothing else.
- **Fold-out direction is a setting:** down, up, left or right of our button (players who keep
  the minimap somewhere other than top-right need this).
- **Ignore list.** The player can keep chosen addons' buttons on the ring at all times. The
  options panel lists every addon button the bag has found, each with a "Keep on minimap"
  checkbox *(the checkbox UI is Claude's call; the user asked for ignoring, not for this UI)*.
  *Amended in the plan:* a vertical Settings category can't add a row per button found at
  runtime, so the options panel has a "Choose buttons" entry that opens the same checkbox menu
  as right-clicking the bag button.
  Ticking it puts that button back where its addon put it, immediately.
- **Our button looks native.** It uses the same HUD minimap art family as the zoom buttons
  (17×17, like `ui-hud-minimap-zoom-in` in `Blizzard_Minimap/Mainline/Minimap.xml`): ring
  styling, pressed state, hover glow. *Amended during review:* the zoom-in atlas has its "+"
  baked in, so the button uses the family's plain button, `ui-hud-minimap-button` / `-down`
  (Blizzard's own addon compartment button), with an additive hover. On it, a native "list /
  more" icon, ideally three horizontal lines.
- **Draggable around the ring.** Our button sits on the minimap's edge and the player can drag
  it to any angle around the ring, like a LibDBIcon button. The angle is saved. Default
  position: bottom-left, away from the zoom buttons *(Claude's call)*.
- **Turning the bag off** (a setting) puts every collected button back where its addon left it,
  without a reload.

## Non-goals (this step)

- Detaching our button from the minimap to sit anywhere on screen. The user ruled this out.
- Custom button order, auto-hide on mouse-out, a separate Button Manager window. These are
  Reborn extras and a possible later step.
- Feeding addons into Blizzard's own addon compartment (`AddonCompartmentFrame`).

## Anti-goals (a failure even if it works)

- **Touching any Blizzard button, ever**: tracking, mail, clock/calendar, zoom, the addon
  compartment, instance difficulty, crafting order, expansion/landing page, anything Blizzard's
  own code puts on or around the minimap. Not even as an option. When unsure whether a frame is
  Blizzard's, leave it alone.
- Taint or blocked actions: no overwriting Blizzard functions or fields, nothing done to
  protected frames, nothing in combat that the client blocks.
- A button that stops working once collected, or that ends up lost off-screen after the bag is
  turned off or the button is un-ignored.
- Custom art. Blizzard atlases only.

## Constraints

- Forever client, interface 16001, modern (Midnight 12.x) addon API, Lua 5.1. Verify every API
  in `.cache/wow-ui-source` (CLAUDE.md → "Looking up the API").
- Lives in **ForeverMap** as a new module; its options go into ForeverMap's existing settings
  category (`Options.lua`, `Settings.RegisterAddOnSetting` into `ForeverMapDB.settings`).
  *(Home is Claude's call; the user didn't object.)*
- New SavedVariables data goes into `ForeverMapDB` through a `DB_VERSION` bump and migration in
  `Database.lua`, account-wide. It holds: bag on/off, fold-out direction, our button's ring
  angle, and the set of ignored buttons. The savedvariables-guard gate applies.
- **Untested in game.** Forever launches 4 November 2026; until then lint and the source are the
  only checks. Everything the source can't prove goes in the launch checks below.

## How (decided)

- **Strip layout:** collected buttons line up in the chosen direction from our button and wrap
  into further rows/columns past a cap, about 6 per line *(Claude's call)*, so a long list never
  runs off screen. Sorted by name for a stable order *(Claude's call)*.
- **Ignore key:** an ignored entry is keyed by something stable across sessions (the button's
  frame name, or the LibDBIcon object name). The options list shows a readable label (the addon's
  title where known).

- **Only buttons, never pins** *(Claude's call)*. "Minimap button" means a clickable launcher
  an addon puts on or around the ring: LibDBIcon buttons, plus hand-made frames that take mouse
  clicks and sit at the ring's edge. Map pins are never collected: HandyNotes and GatherMate2
  nodes, TomTom waypoints, anything placed through HereBeDragons-Pins, and ForeverMap's own node
  icons. Pulling them into the strip would break them. Build the scanner as an allowlist of
  button-like frames, not "everything that isn't Blizzard's".
- **No dragging inside the strip** *(Claude's call)*. A collected button's drag is turned off
  while it is in the bag and turned back on when it leaves. Otherwise a LibDBIcon drag snaps the
  button out of the strip and silently rewrites that addon's saved `minimapPos`. Do this without
  replacing anyone's scripts, for example by clearing the button's drag registration
  (`RegisterForDrag()` with no arguments) and restoring it afterwards.
- **Hidden buttons stay hidden** *(Claude's call)*. A button its addon or the player has hidden
  (LibDBIcon `hide = true`, an addon's own "show minimap button" set to off) doesn't appear in
  the strip. It stays hidden when un-ignored or when the bag is turned off. The bag tracks each
  button's own shown state apart from the strip's open/closed state. Hidden buttons still appear
  in the options list, so they can be ignored ahead of time.

## Left to the builder

- **Finding the buttons.** Likely a mix of: LibDBIcon's registry and its icon-created callback
  when the library is present; scanning the children of `Minimap` and `MinimapCluster` for
  addon frames; a rescan when addons load (`ADDON_LOADED`) and shortly after login. How to tell
  a Blizzard frame from an addon's is the key design point. Two candidates: the Lua global
  `issecurevariable(_G, frameName)`, which names the addon that created a named frame (Ketho's
  annotations list it but the Forever source doesn't use it, so it's a launch check); and a
  denylist of every frame Blizzard puts on the minimap, built from `Blizzard_Minimap/`. Either
  way, the denylist rule is "when unsure, leave it".
- **Keeping buttons in place.** Addons (LibDBIcon especially) re-anchor their buttons on their
  own updates. Use `hooksecurefunc` on the button's methods or reparent into our container, not
  replacing other addons' or Blizzard's functions.
- **The icon.** No atlas list ships in the local source and the online atlas databases were
  unreachable, so the three-lines atlas name is unknown. Build a short ranked list of candidates
  (e.g. `friends-icon-menu` from `Blizzard_SocialUI`), ship a ForeverDev probe that logs which
  exist via `C_Texture.GetAtlasInfo` and use the best existing one, with a safe fallback.
- **Dragging around the ring:** angle math, round vs. square minimap shapes.
- **Combat.** Addon buttons are normally not protected, but if a collected frame is protected,
  skip it or defer changes until `PLAYER_REGEN_ENABLED`.
- **Tooltip and click on our button:** a tooltip with the addon name and a click hint, using
  Blizzard's GlobalStrings where one fits.

## Launch checks (to confirm once the client runs)

- Which candidate atlases exist for the icon, and how it looks next to the zoom buttons.
- `issecurevariable` exists in Forever and returns the creating addon for named addon frames.
- The list of frames the bag collects on a typical setup contains no Blizzard frame (log every
  collected and every skipped frame with its reason).
- LibDBIcon buttons stay in the strip after `/rl`, minimap shape changes and LibDBIcon refreshes.
- Late-created buttons (load-on-demand addons) are caught.
- Un-ignoring and turning the bag off return buttons to their original spots.
