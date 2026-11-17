# ForeverCombatText Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A new addon that redraws the player's own floating combat text inside an Edit Mode box, with Scroll Length, Duration and Font Size sliders.

**Architecture:** `hooksecurefunc(CombatText, "AddMessage")` feeds every message Blizzard shows to our own font strings on a holder frame; Blizzard's copy is hidden with `CombatText:SetAlpha(0)`. Pure animation maths lives apart from frame code. LibEditMode registers the holder and keeps position and settings per Edit Mode layout.

**Tech Stack:** Lua 5.1, WoW Forever client API (interface 16001), LibEditMode tag 19 (`.pkgmeta` external).

**Spec:** `docs/superpowers/specs/2026-11-17-forevercombattext-design.md`; decision record `docs/adr/0003-move-combat-text-by-mirroring-blizzards-messages.md`.

One step, one PR: `feat(forevercombattext): add movable combat text for the player`.

## Global Constraints

- Addon code assigns no field on `CombatText`, `CombatTextConstants` or `CombatTextTypeInfo` and calls none of the mixin's Lua methods. `SetAlpha` is the only widget call on that frame.
- `message` may be secret: it goes to `FontString:SetText` and nowhere else. Never compare, concatenate, measure or log it (log `issecretvalue(message)` only).
- Lua 5.1; every file starts `local ADDON_NAME, ns = ...`; the only global is `ForeverCombatTextDB`.
- `ns.log` tags: `LOADED` (Core.lua), `HOOK`, `MSG` (Display.lua), `SAVE`, `EDITMODE` (EditMode.lua).
- Defaults: Scroll Length 225 (50–600, step 5), Duration 1.9 s (0.5–5, step 0.1), Font Size 25 (10–60, step 1).
- `scripts/lint.sh` clean after every task; commit with `git add <paths>`, never `-A`.

## Review Focus

1. Taint: does anything of ours write to, or call Lua methods on, Blizzard's `CombatText`? Does the hook survive `Blizzard_CombatText` loading before or after our addon, or never?
2. Secret message: is it only ever passed to `SetText`? Any branch, concat, `tostring`, `#`, or log of it is a bug.
3. Start edge: after a drag (LibEditMode re-derives the anchor point), a Scroll Length change and a layout switch, does the start edge stay where the player put it, and is the saved position the one re-applied after `/rl`?
4. Lines past the 20-line cap, a Duration change while lines are scrolling, and Edit Mode samples mixing with real messages: nothing errors, nothing leaks out of the pool.
5. Saved data: a missing, older or newer `ForeverCombatTextDB`, an invalid field, a character-specific layout while the GUID is secret.

## In-game checks

The spec's table. Instrumentation: `HOOK` (hooked or why not), `MSG` via `ns.dev:LogOnce` keyed by secrecy, display type, colour and direction (`issecretvalue(message)`, r, g, b, displayType, isStaggered, float mode, Blizzard's line top against our box), `SAVE`, `EDITMODE`.

## Step reviewers

Core four, plus `savedvariables-guard` (new SavedVariables), UI reviewer (frames, Edit Mode), release reviewer (new TOC, `.pkgmeta`).

---

### Task 1: Scaffold the addon

**Files:**
- Create via `scripts/new-addon.sh ForeverCombatText`: `addons/ForeverCombatText/{ForeverCombatText.toc,Core.lua,CHANGELOG.md}`
- Create: `addons/ForeverCombatText/.pkgmeta`, `addons/ForeverCombatText/Database.lua`
- Modify: `.luacheckrc` (globals entry `ForeverCombatTextDB`)

**Produces:** `ns.log`, `ns.dev`, `ns.Inert`, `ns.L` (`COMBAT_TEXT`, `SCROLL_LENGTH`, `DURATION`, `FONT_SIZE`), `ns.OnInitialize(func)`, `ns.db`, `ns.DB.Migrate(db)`.

- [ ] TOC like ForeverUnitFrames': Notes, `## IconTexture`, `## X-Category: Combat`, `## SavedVariables: ForeverCombatTextDB`, the LibEditMode lines, then `Core.lua`, `Database.lua`, `Scroll.lua`, `Display.lua`, `EditMode.lua`.
- [ ] `.pkgmeta` copied from ForeverUnitFrames' (LibEditMode tag `"19"`, manual changelog; no `Dev` ignore, there is no `Dev/`). Run `scripts/libs.sh`.
- [ ] `Core.lua`: the template shim with the tag list, `ns.L`, `ns.OnInitialize`, and the load sequence of ForeverUnitFrames' Core.lua.
- [ ] `Database.lua`: layout comment, `DB_VERSION = 1`, migration 1 creates `db.text = {}` when it isn't a table.
- [ ] `CHANGELOG.md`: a players' line under `## Unreleased`.
- [ ] Files that later tasks create are added to the TOC by those tasks, so lint stays clean. Lint, commit `feat(forevercombattext): scaffold the addon`.

### Task 2: Scroll maths

**Files:** Create `addons/ForeverCombatText/Scroll.lua`; add to TOC.

**Produces** (all plain numbers in and out; "travel" is distance along the direction of travel, 0 at the start edge):
- `ns.Scroll.MODE = { UP = 1, DOWN = 2, ARC = 3 }`, `ns.Scroll.ModeFromCVar(value)` (`"1"` up, `"2"` down, else arc)
- `ns.Scroll.Position(mode, t, duration, length, startX, startTravel, xDir, stays) -> x, travel`. Up and down: `travel = startTravel + (stays and 0 or length) * t / duration`. Arc (and not `stays`): radius `length * 150 / 225`, `x = startX - xDir * radius * (1 - cos(90° * t / duration))`, `travel = startTravel + radius * sin(...)`.
- `ns.Scroll.Alpha(t, duration) -> alpha`: 1 until `duration * 1.3 / 1.9`, then linear to 0 at `duration`.
- `ns.Scroll.CritHeight(t, fontSize) -> height`: `1.2 × fontSize` growing to `2.4 ×` over 0.05 s, back to `1.2 ×` by 0.2 s, `1.2 ×` after.
- `ns.Scroll.StartTravel(activeTravels, fontSize, isCrit) -> travel, sideStep`: port of `CombatTextMixin:AddMessage`'s search. Start at 0; behind every active line by `16 * fontSize / 25 + 10`; past `-130` a crit starts at 0, anything else at `-130` with `sideStep = true`.
- `ns.Scroll.ShiftForLength(point, oldLength, newLength, mode) -> dy`: how far the holder's anchor offset must move so the start edge (bottom for up and arc, top for down) stays put when the height changes, from the vertical part of `point`.

- [ ] Write it; check the values at defaults against `CombatText.lua` by running the file under a standalone Lua if one is installed (scratchpad script, not committed). Lint, commit `feat(forevercombattext): add the scroll maths`.

### Task 3: Display

**Files:** Create `addons/ForeverCombatText/Display.lua`; add to TOC.

**Consumes:** `ns.Scroll.*`. **Produces:**
- `ns.Display.DEFAULTS = { point, x, y, length = 225, duration = 1.9, fontSize = 25 }`; `point = "BOTTOM"`, `x = 0`, `y` from `ns.Display.DefaultY(mode)`: the box's start edge on the centre of Blizzard's first line for that direction (see the spec).
- `ns.Display.holder` (200 wide, on `UIParent`).
- `ns.Display.SetLayout({ point, x, y, length, duration, fontSize })`: sizes and places the holder; new values apply to lines added afterwards and to the movement of running ones.
- `ns.Display.Add(message, r, g, b, displayType, isStaggered)`: starts one line.

- [ ] Lines are the holder's own font strings (`BACKGROUND`, `CombatTextFont`) kept in a free list, at most 20 active; past that the oldest makes room. Each is anchored `CENTER` to the holder's start edge and moved by the holder's `OnUpdate`, which is set only while lines are active. Stagger ±10 when `isStaggered`; x direction alternates per line; a side step is 80, alternating sides (as `textOffsetAdjustment`).
- [ ] The hook: `EventUtil.ContinueOnAddOnLoaded("Blizzard_CombatText", ...)` inside `ns.OnInitialize`; if `CombatText` and its `AddMessage` exist, `hooksecurefunc` and `CombatText:SetAlpha(0)`, else log `HOOK` with what was missing. The hook guards r, g, b, displayType and isStaggered with `issecretvalue` (white, no crit, no stagger) and calls `ns.Display.Add`.
- [ ] `MSG` logging inside `if ns.dev.enabled then`, through `LogChanged`.
- [ ] Lint, commit `feat(forevercombattext): draw Blizzard's combat text in our own box`.

### Task 4: Edit Mode

**Files:** Create `addons/ForeverCombatText/EditMode.lua`; add to TOC.

**Consumes:** `ns.Display.*`, `ns.Scroll.ShiftForLength`, `ns.LibEditMode`, `ns.db.text`.

- [ ] Copy ForeverUnitFrames' `EditMode.lua` scheme (`Store`, `Key`, `Get`, `Save`, `Apply`, the `layout`, `create`, `rename`, `delete` callbacks) for the fields `point, x, y, length, duration, fontSize`. No snapping.
- [ ] Three sliders per the Global Constraints. Duration is rounded to one decimal before saving. The Scroll Length setter shifts and saves `y` by `ShiftForLength` before applying, so the start edge stays put.
- [ ] `enter` / `exit` callbacks start and stop a one-second `C_Timer.NewTicker` that feeds `ns.Display.Add` a hit, a heal and a crit in `CombatTextTypeInfo`'s colours (read-only).
- [ ] Lint, commit `feat(forevercombattext): place and tune the text in Edit Mode`.
- [ ] **SavedVariables gate:** dispatch `savedvariables-guard`; fix or rule on every finding before the step review.

### Task 5: Review, verify, ship

- [ ] Phase 5 reviewers in parallel on `git diff origin/main...HEAD`; verify and fix findings, one commit per concern.
- [ ] Pre-PR gate; `scripts/worktree.sh status` (new-addon.sh already linked the addon from this worktree); hand the user the in-game steps; record `forevercombattext-launch-checks` if they can't test now.
