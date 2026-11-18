# RazzhUI suite: roadmap

Date: 2026-11-17. Scope map: `docs/superpowers/specs/2026-11-17-forever-enhanced-suite-scope-map.md`.
Decision record: `docs/adr/0004-structure-the-addons-as-one-suite.md`.

One step is one plan, one session and one PR.

| Step | PR title (working) | What lands | Status |
|---|---|---|---|
| 1 | `feat(razzhui,forevertooltip): add the suite core` | `addons/RazzhUI` (Esc-menu button, "RazzhUI" category, modules list with on/off, `RegisterOptions`), ForeverTooltip as the first module, lint and template rules for modules, worktree notices, CLAUDE.md. Spec: `docs/superpowers/specs/2026-11-17-forever-enhanced-core-design.md`. Plan: `docs/superpowers/plans/2026-11-17-forever-enhanced-core.md` | built and reviewed; tested in game out of combat, the Esc-menu button's combat behaviour and the addon compartment entry still untested |
| 1b | `feat(razzhui): add a minimap button` | A real minimap button that opens the RazzhUI page, so the core shows in ForeverMinimap's button bag the way EllesmereUI does (asked for by the user after the in-game pass). It can be dragged and hidden, which gives the core its own saved settings (`RazzhUIDB`). Spec: `docs/superpowers/specs/2026-11-18-razzhui-minimap-button-design.md`. Plan: `docs/superpowers/plans/2026-11-18-razzhui-minimap-button.md` | built and reviewed; in game (18 November, session 276) the bag collects it and its click opens the page, with no errors; hiding, dragging, the remembered place and combat still untested |
| 2 | `feat: move every addon under RazzhUI` | The other five addons become modules (ForeverBags, ForeverCombatText, ForeverDungeonXP, ForeverMinimap, ForeverProfessions; RazzhUIResourceBars already is one, and ForeverActionBars, ForeverCombat and ForeverQuests were removed on 18 November); Edit Mode pages for RazzhUIResourceBars and ForeverCombatText. Spec: `docs/superpowers/specs/2026-11-18-razzhui-modules-design.md`. Plan: `docs/superpowers/plans/2026-11-18-razzhui-modules.md` | built and reviewed as nine addons, then cut down by #52 and #53 (that merge was not reviewed again); in game (18 November, sessions 281 to 318) the modules nest and load, the moved pages keep their saved values, unticking a module turns it off, and no error or blocked action came from the suite; the Edit Mode button was clicked once, on the old Unit Frames page, and its click on the Combat Text and Resource Bars pages, the click in combat, and ticking a module back on from the RazzhUI page are still unseen in the log |
| 3 | `build: package the suite as one download` | One zip, one version, `release.yml`, `package.sh`, CLAUDE.md's release section. Nothing is released | not started |
| 4 | `refactor: ...` (several) | Shared code moves into the core, one concern per PR | optional |

Step 2 waits for step 1's in-game checks: if the Esc-menu button or the on/off switch has to
change shape, it changes while one module depends on it, not ten. (18 November: the user chose to
go ahead with step 2 before the last of those checks.)
