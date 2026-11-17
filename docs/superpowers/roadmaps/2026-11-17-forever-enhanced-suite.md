# Forever Enhanced suite: roadmap

Date: 2026-11-17. Scope map: `docs/superpowers/specs/2026-11-17-forever-enhanced-suite-scope-map.md`.
Decision record: `docs/adr/0004-structure-the-addons-as-one-suite.md`.

One step is one plan, one session and one PR.

| Step | PR title (working) | What lands | Status |
|---|---|---|---|
| 1 | `feat(foreverenhanced,forevertooltip): add the suite core` | `addons/ForeverEnhanced` (Esc-menu button, "Forever Enhanced" category, modules list with on/off, `RegisterOptions`), ForeverTooltip as the first module, lint and template rules for modules, worktree notices, CLAUDE.md. Spec: `docs/superpowers/specs/2026-11-17-forever-enhanced-core-design.md` | designing |
| 2 | `feat: move every addon under Forever Enhanced` | The other nine addons become modules; Edit Mode pages for ForeverUnitFrames and ForeverCombatText | not started |
| 3 | `build: package the suite as one download` | One zip, one version, `release.yml`, `package.sh`, CLAUDE.md's release section. Nothing is released | not started |
| 4 | `refactor: ...` (several) | Shared code moves into the core, one concern per PR | optional |

Step 2 waits for step 1's in-game checks: if the Esc-menu button or the on/off switch has to
change shape, it changes while one module depends on it, not ten.
