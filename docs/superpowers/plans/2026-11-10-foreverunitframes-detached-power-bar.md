# Plan: ForeverUnitFrames detached power bar

Spec: `docs/superpowers/specs/2026-11-10-foreverunitframes-detached-power-bar-design.md`.
ADR: `docs/adr/0002-detach-the-player-power-bar-by-reparenting-blizzards-bar.md`.

## PR slicing

1. `build(scripts): fetch libraries from addons' .pkgmeta externals`: `scripts/libs.sh` and
   the lint/StyLua/LuaLS/luacheck exclusions for `Libs/`. Its own PR, merged first.
2. `feat(foreverunitframes): detach the player power bar`: the addon, tasks below.

## Tasks (PR 2)

1. **Scaffold** with `scripts/new-addon.sh ForeverUnitFrames`: TOC metadata (Notes,
   `X-Category: Unit Frames`), `.pkgmeta` external `Libs/LibEditMode` (tag 19), TOC loads
   `Libs\LibEditMode\namespaced.lua` and `Libs\LibEditMode\embed.xml`, `.luacheckrc` globals.
2. **Database.lua:** `ForeverUnitFramesDB = { version = 1, powerBar = { [layoutName] =
   { point, x, y, width, height } } }`, migration 1. SavedVariables gate: `savedvariables-guard`.
3. **Layout.lua:** the combat gate: `ns.Layout.Request(name, func)` runs `func` now out of
   combat, or once on `PLAYER_REGEN_ENABLED`, logging `DEFER`/`APPLY`.
4. **HealthBar.lua:** `hooksecurefunc("PlayerFrame_UpdateHealthBarVisuals")` → through the gate,
   grow container, bar and mask by the power row's height. Apply once at load. Logs `LAYOUT`.
5. **PowerBar.lua:** holder frame, background and outline; re-parent the mana bar, fill the
   holder, rectangular mask; `hooksecurefunc("PlayerFrame_UpdateManaBarVisuals")` re-applies.
   Logs `POWER`.
6. **EditMode.lua:** LibEditMode `AddFrame` (position callback saves per layout), Width/Height
   sliders, `layout` callback re-applies position and size, `rename`/`delete` keep the DB tidy.
   Logs `SAVE`, `EDITMODE`.
7. **CHANGELOG** `## Unreleased` line for players.

## Reviewers (Phase 5)

Core (`addon-reviewer`, `api-verifier`, correctness, spec) plus `savedvariables-guard`, a UI
reviewer, a shell reviewer (PR 1) and a release reviewer (`.pkgmeta` externals, `Libs/`).

## Review focus

- Protected frames: every `SetParent`/`SetPoint`/`SetSize` on Blizzard's bars goes through the
  combat gate; nothing hides or moves the holder in combat.
- Hooks run after Blizzard's layout and fully override what it set (anchors are cleared first).
- LibEditMode callbacks arrive with a nil layout name before layouts load.
- `.pkgmeta` external fetched and packaged unmodified; nothing dev-only shipped.

## In-game checks

As listed in the spec, with the tags `LAYOUT`, `POWER`, `DEFER`, `APPLY`, `SAVE`, `EDITMODE`.
