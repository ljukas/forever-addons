# ForeverTooltip Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A new addon that class-colours hovered players' names, reaction-colours their level line, and optionally makes world-hover tooltips follow the cursor.

**Architecture:** One `TooltipDataProcessor` unit post-call recolours `GameTooltip`'s finished font strings (never Blizzard's `lineData`); a `hooksecurefunc` on `GameTooltip_SetDefaultAnchor` re-owns world-hover tooltips at the cursor. Pure string logic for finding the level line lives in `Logic/LevelLine.lua`. One account-wide setting through Blizzard's `Settings` API.

**Tech Stack:** Lua 5.1, Forever client (interface 16001, Midnight 12.x API with secret values), StyLua, LuaLS via `scripts/lint.sh`. No libraries.

**Spec:** `docs/superpowers/specs/2026-11-04-forevertooltip-design.md`

## Global Constraints

- `## Interface: 16001`, `## Category: Forever Enhanced Addons`, `## X-Category: Tooltip`, `## X-License: MIT`, `## SavedVariables: ForeverTooltipDB`.
- Name colour: `C_ClassColor.GetClassColor(classFilename)`. Level-line colour: `GameTooltip_UnitColor(unit)`. No colour literals.
- Colouring only for `UnitIsPlayer(unit)`; NPCs, pets, objects keep Blizzard's colours.
- Never compare, branch on or do arithmetic with a secret value: `issecretvalue` first, and on a secret value leave the line exactly as Blizzard drew it.
- Never write into Blizzard tables (`lineData`, `tooltipData`) or replace Blizzard functions; hooks only.
- Cursor option key `cursorAnchor`, default `false`. Anchor `"ANCHOR_CURSOR_RIGHT"` with a fixed offset (constants in `Anchor.lua`, start at x = 16, y = -16; tuned at launch).
- Cursor anchoring only when `tooltip == GameTooltip`, `parent == UIParent` **and** the mouse is over the world (`GetMouseFoci()` first region is `WorldFrame`). Minimap, XP bar and chat hyperlinks also anchor to `UIParent`, which is why the focus check is needed.
- Locale-independent level line: built from the client's `UNIT_LEVEL_TEMPLATE`, never the English word "Level".
- `ns.log` tags: `LOADED` (Core), `COLOR` and `LEVEL` (Colors.lua), `ANCHOR` (Anchor.lua). Use `ns.dev:LogOnce` / `LogChanged`, never per-hover spam.
- `scripts/lint.sh` clean after every task; luacheck globals for `ForeverTooltipDB` in `.luacheckrc`.

## Review Focus

1. **Secret values on hover in restricted situations** (instances, arenas, combat): `UnitClass` is `SecretWhenUnitIdentityRestricted`, font string text may be secret. Expect the tooltip to look exactly like Blizzard's, with no error. Task 3 guards every value with `issecretvalue` before use.
2. **Tooltip rebuilds** (`TOOLTIP_DATA_UPDATE` → `RebuildFromTooltipInfo`, e.g. a player's guild info loading a moment later): colours must survive the rebuild. The post-call runs again on rebuild; Task 3 relies on that and logs the rebuild.
3. **Level `??`** (skull-level hostile players, `UnitLevel` returns -1): the level line must still be found. Task 2's `LevelText` maps -1 to `"??"`.
4. **Tooltips that aren't `GameTooltip`** (e.g. `ItemRefTooltip`, embedded tooltips) reaching the unit post-call: they must be left alone. Task 3 returns early unless `tooltip == GameTooltip`.
5. **Cursor option toggled while a tooltip is showing**, and hovering UI over the world (minimap, unit frames, action bars): only fresh world hovers move. Task 4 reads the setting on each anchor call and checks the mouse focus.

---

### Task 1: Scaffold the addon, its database and the options checkbox

**Files:**
- Create (via `scripts/new-addon.sh ForeverTooltip`): `addons/ForeverTooltip/ForeverTooltip.toc`, `Core.lua`, `CHANGELOG.md`
- Create: `addons/ForeverTooltip/Database.lua`, `addons/ForeverTooltip/Options.lua`
- Modify: `.luacheckrc` (globals for `addons/ForeverTooltip/**`: `ForeverTooltipDB`)

**Interfaces:**
- Produces: `ns.db` (ForeverTooltipDB), `ns.OnInitialize(func)`, `ns.L`, `ns.Options.Get(key) -> value`, `ns.Options.DEFAULTS = { cursorAnchor = false }`.

- [ ] **Step 1:** Run `scripts/new-addon.sh ForeverTooltip`. Fill in the TOC: Notes "Colours hovered players' names by class and their level line by friend or foe, and can make tooltips follow the cursor.", `## IconTexture: Interface\Icons\INV_Misc_Note_01`, `## X-Category: Tooltip`. TOC file order: `Core.lua`, `Database.lua`, `Logic/LevelLine.lua`, `Options.lua`, `Colors.lua`, `Anchor.lua` (later tasks add the last three files; list each only when the file exists, so lint passes per task).
- [ ] **Step 2:** In `Core.lua`, follow `addons/ForeverMinimap/Core.lua`: shim comment listing tags by file, `ns.L` (enUS: `CURSOR_ANCHOR = "Tooltip follows the cursor"`, `CURSOR_ANCHOR_TOOLTIP = "Show tooltips for players, creatures and objects in the world next to the mouse cursor instead of at the tooltip position set in Edit Mode."`), `ns.OnInitialize`, and `ContinueOnAddOnLoaded` that sets `ForeverTooltipDB = ForeverTooltipDB or {}`, runs `ns.DB.Migrate`, then the initializers, then logs `LOADED` with the db version. No callback registry (nothing listens for changes; settings are read on use).
- [ ] **Step 3:** `Database.lua`: layout comment (`version`, `settings = { cursorAnchor = boolean }` owned by Options.lua), `DB_VERSION = 1`, migration 1 creates `db.settings`. Same shape as ForeverMinimap's `ns.DB.Migrate`.
- [ ] **Step 4:** `Options.lua`: `ns.Options.DEFAULTS`, `ns.Options.Get` (default when unsaved), and in `ns.OnInitialize` a vertical layout category named `ADDON_NAME` with one `Settings.RegisterAddOnSetting(category, "FOREVERTOOLTIP_CURSORANCHOR", "cursorAnchor", ns.db.settings, Settings.VarType.Boolean, L.CURSOR_ANCHOR, false)` and `Settings.CreateCheckbox`, then `Settings.RegisterAddOnCategory(category)` (check how ForeverMinimap/Options.lua finishes).
- [ ] **Step 5:** Add the `.luacheckrc` globals block. Run `scripts/lint.sh`. Expected: clean.
- [ ] **Step 6:** Dispatch `savedvariables-guard` (Phase 4 SavedVariables gate) on the TOC, Database.lua and Options.lua; fix confirmed findings before Task 2.
- [ ] **Step 7:** Commit: `feat(forevertooltip): add addon with cursor anchor option` (`git add addons/ForeverTooltip .luacheckrc`).

### Task 2: Pure level-line logic

**Files:**
- Create: `addons/ForeverTooltip/Logic/LevelLine.lua` (and list it in the TOC)

**Interfaces:**
- Produces:
  - `ns.LevelLine.LevelText(template: string, level: number) -> string` — `template` is `UNIT_LEVEL_TEMPLATE` (a `%d` format, e.g. `"Level %d"`). Returns `template:format(level)` for `level >= 0`; for `level < 0` returns the template with its `%d` replaced by `"??"` (use `gsub("%%d", "??")`, not `format`).
  - `ns.LevelLine.Find(texts: string[], levelText: string, first: integer) -> integer|nil` — index of the first entry at or after `first` that contains `levelText` as plain text (`string.find(text, levelText, 1, true)`), skipping nil entries; nil when none.
- No WoW API calls in this file; the caller passes the template, texts and level.

- [ ] **Step 1:** Write both functions with a header comment giving the examples below (there is no test runner; the examples are the reviewer's check):
  - `LevelText("Level %d", 60) == "Level 60"`; `LevelText("Level %d", -1) == "Level ??"`; `LevelText("%d级", 12) == "12级"`.
  - `Find({ "Thrall", "<Horde>", "Level 60 Orc Shaman" }, "Level 60", 2) == 3`; `Find({ "Thrall", "Level 60 Orc" }, "Level 6", 2) == 2` (plain substring is acceptable: the name line is skipped by `first = 2`); `Find({ "A", "B" }, "Level 1", 2) == nil`.
- [ ] **Step 2:** Run `scripts/lint.sh`. Expected: clean.
- [ ] **Step 3:** Commit: `feat(forevertooltip): find the level line from the client's level text`.

### Task 3: Class-coloured name and reaction-coloured level line

**Files:**
- Create: `addons/ForeverTooltip/Colors.lua` (and list it in the TOC)
- Modify: `types/forever.lua` only if LuaLS flags an API verified in the Forever source.

**Interfaces:**
- Consumes: `ns.LevelLine.LevelText`, `ns.LevelLine.Find`, `ns.log`, `ns.dev`.

- [ ] **Step 1:** Register at file load: `TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, OnUnitTooltip)`. `OnUnitTooltip(tooltip, data)`:
  1. Return unless `tooltip == GameTooltip`.
  2. Get the unit with `local _, unit = TooltipUtil.GetDisplayedUnit(tooltip)` (verify it in `Blizzard_SharedXMLGame/Tooltip/TooltipUtil.lua`). Return if `unit` is nil or `issecretvalue(unit)`.
  3. Return unless `UnitIsPlayer(unit)` (guard the result with `issecretvalue`).
  4. Name: `local _, classFilename = UnitClass(unit)`; if it is not secret and not nil, `local color = C_ClassColor.GetClassColor(classFilename)` and `tooltip:GetLeftLine(1):SetTextColor(color:GetRGB())` (verify `GetLeftLine` in `FrameAPITooltipDocumentation.lua`; fall back to `_G["GameTooltipTextLeft1"]` only if it's missing). Else `ns.dev:LogOnce("secret-class", "COLOR", "class secret, name left to Blizzard")`.
  5. Level line: read `UnitLevel(unit)` (skip if secret), collect the left texts of lines 2..`tooltip:NumLines()` (stop and log once with tag `LEVEL` if any text is secret), `index = ns.LevelLine.Find(texts, ns.LevelLine.LevelText(UNIT_LEVEL_TEMPLATE, level), 2)`. If found, `tooltip:GetLeftLine(index):SetTextColor(GameTooltip_UnitColor(unit))` (guard its returns with `issecretvalue`); if not found, `ns.dev:LogOnce("level-miss", "LEVEL", "no level line", texts joined)`. When `ns.dev.enabled`, `ns.dev:LogChanged("level-index", index, "LEVEL", "level line at", index)`.
- [ ] **Step 2:** Run `scripts/lint.sh`. Expected: clean.
- [ ] **Step 3:** Commit: `feat(forevertooltip): colour player names by class and level by reaction`.

### Task 4: Tooltip follows the cursor for world hovers

**Files:**
- Create: `addons/ForeverTooltip/Anchor.lua` (and list it in the TOC)

**Interfaces:**
- Consumes: `ns.Options.Get("cursorAnchor")`, `ns.log`.

- [ ] **Step 1:** `local OFFSET_X, OFFSET_Y = 16, -16` with a comment that they are tuned at launch. `local function IsMouseOverWorld()` returns true when `GetMouseFoci()`'s first region is `WorldFrame` (verify `GetMouseFoci` in `InputDocumentation.lua`).
- [ ] **Step 2:** `hooksecurefunc("GameTooltip_SetDefaultAnchor", function(tooltip, parent) ... end)`: when `ns.Options.Get("cursorAnchor")`, `tooltip == GameTooltip`, `parent == UIParent` and `IsMouseOverWorld()`, call `tooltip:SetOwner(parent, "ANCHOR_CURSOR_RIGHT", OFFSET_X, OFFSET_Y)`. Log `ns.dev:LogOnce("anchor", "ANCHOR", "world tooltip anchored to cursor")`; when `ns.dev.enabled` and parent is UIParent but the focus is not WorldFrame, `ns.dev:LogChanged("anchor-skip", focusName, "ANCHOR", "kept default for", focusName)` with the focus frame's `GetDebugName()`.
- [ ] **Step 3:** Run `scripts/lint.sh`. Expected: clean.
- [ ] **Step 4:** Commit: `feat(forevertooltip): let world tooltips follow the cursor`.

### Task 5: Changelog and launch checks

**Files:**
- Modify: `addons/ForeverTooltip/CHANGELOG.md`

- [ ] **Step 1:** Under `## Unreleased`, replace "Initial version." with player-facing lines: hovered players' names in their class colour; the level line red/yellow/green by friend or foe; an option in Options → AddOns → ForeverTooltip to make tooltips for things in the world follow the cursor.
- [ ] **Step 2:** Commit: `docs(forevertooltip): describe the first version in the changelog`.

### Task 6: Choose which way the tooltip grows from the cursor (added after review, user request)

**Files:**
- Create: `addons/ForeverTooltip/Logic/CursorAnchor.lua` (pure)
- Modify: `Core.lua` (strings), `Options.lua` (dropdown), `Anchor.lua` (positioning), `Database.lua` (layout comment), TOC, `CHANGELOG.md`

**Interfaces:**
- `ns.Options.DIRECTION = { DOWN_RIGHT = 1, DOWN_LEFT = 2, UP_RIGHT = 3, UP_LEFT = 4 }`; new setting `cursorDirection` (Number, default `UP_RIGHT`, variable `FOREVERTOOLTIP_CURSORDIRECTION`), a dropdown whose parent initializer is the `cursorAnchor` checkbox.
- `ns.CursorAnchor.Point(direction: number) -> point: string, offsetX: number, offsetY: number` — the tooltip corner pinned to the cursor and its offset from the pointer: DOWN_RIGHT `"TOPLEFT", 20, -24`; DOWN_LEFT `"TOPRIGHT", -8, -8`; UP_RIGHT `"BOTTOMLEFT", 8, 8`; UP_LEFT `"BOTTOMRIGHT", -8, 8`; unknown values fall back to UP_RIGHT.

- [ ] **Step 1:** Pure `Logic/CursorAnchor.lua` with the table above in a header comment.
- [ ] **Step 2:** `Anchor.lua`: the hook sets `following = true` and shows a driver frame instead of `SetAnchorType`; the driver's `OnUpdate` pins the corner at `GetCursorPosition() / GameTooltip:GetEffectiveScale()` relative to `UIParent` `"BOTTOMLEFT"`, and stops (hides itself) when `GameTooltip` is hidden, `GetOwner() ~= UIParent` or `GetAnchorType() ~= "ANCHOR_NONE"`. The hook clears `following` for non-world default anchors.
- [ ] **Step 3:** Options dropdown, strings, CHANGELOG line; `scripts/lint.sh` clean; `savedvariables-guard` on the new key.

## Launch checks (become the `forevertooltip-launch-checks` memory in Phase 6)

*Updated after the step review to match the code's log text.*

| Check in game | Confirms | Evidence | If wrong, change |
|---|---|---|---|
| Hover an ally, an enemy-faction player and an attackable (duel) player in the world, out of combat | Name in class colour; level line green / red / yellow | look; `devlog --tag LEVEL` shows "level line by type at N" (or "by text") | `Colors.lua` |
| Hover a guild member and a skull-level hostile | Level line found after the guild line, `??` handled | `LEVEL` has "level line by type", no "no level line in"; if "no UnitLevel line type; line types …", read the list | `Colors.lua`, `Logic/LevelLine.lua` |
| Hover players in a dungeon, battleground and in combat | Secret handling: Blizzard look, no errors | `devlog --errors` empty; `COLOR` "class unreadable" / `LEVEL` "reaction unreadable" or "secret line text" show where | `Colors.lua` |
| Tick the option; hover players, NPCs, herbs | Follows the cursor smoothly; **which way it grows** (up-right or down-right) and whether it covers the unit's head or nameplate; whether the fade after leaving a unit trails badly | look; `ANCHOR` "world tooltip anchored to cursor" | `Anchor.lua` (offsets; fallback: top-left at the cursor each frame) |
| With the option on, hover the minimap, XP bar, unit frames and action bars | UI tooltips stay at the default spot | `ANCHOR` "kept default anchor for Minimap…" | `Anchor.lua` (focus check) |
| With the option on, hover quest NPCs, nodes and players in combat and in instances | Full tooltip lines, widgets and progress bars (no taint "no lines") | look; `devlog --errors` has no blocked actions | `Anchor.lua`; fallback is removing the option |
