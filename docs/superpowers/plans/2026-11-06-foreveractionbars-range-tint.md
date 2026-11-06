# ForeverActionBars out-of-range tint: implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task by task. Steps use checkbox (`- [ ]`) syntax for tracking.

> **Superseded in part.** The spec's "Amended after the step review" section and `Wash.lua` replace this plan's clearing (`OnActionChanged` → `RegisterFrame`/`UnregisterFrame` hooks and a login refresh), button test, pet-button match (`button.bar`) and wash setters (nested `C_CurveUtil.EvaluateColorValueFromBoolean` into `SetAlpha`). The plan is kept as the record of what was planned.

**Goal:** A new addon, ForeverActionBars, that puts a red wash and a red edge over every standard Blizzard action button that's out of range. Pet buttons only collect evidence.

**Architecture:** One post-hook on the global `ActionButton_UpdateRangeIndicator(button, checksRange, inRange)`, which every bar calls. For standard action buttons it drives two textures the addon adds to the button, using the client's secret-safe setters, so Lua never branches on a range value. For pet buttons it records evidence through `Knowledge.lua` (ForeverDev only). `EventRegistry` `"ActionButton.OnActionChanged"` clears the wash when a slot's action changes.

**Tech stack:** Lua 5.1, Forever client (interface 16001, Midnight 12.x API), ForeverDev for logging and evidence. No libraries.

**Spec:** `docs/superpowers/specs/2026-11-06-foreveractionbars-range-tint-design.md`

## Global constraints

- `## Interface: 16001`, `## Category: Forever Enhanced Addons`, `## X-Category: Action Bars`, `## X-License: MIT`.
- **No SavedVariables, no options** in this version. Remove the template's `## SavedVariables` line and its DB code.
- No globals created. No Blizzard function, mixin method or frame field overwritten. Post-hooks (`hooksecurefunc`, `EventRegistry`) only.
- Never compare, negate or branch on `checksRange` / `inRange` in code that runs for players. They go only into `SetAlphaFromBoolean` / `SetVertexColorFromBoolean`. `issecretvalue` appears only inside `if ns.dev.enabled then` blocks and `Knowledge.lua`.
- Never touch a button's attributes, size, points, scripts or protected methods. Adding child textures to a secure button, and setting their colour and alpha, is allowed in combat.
- Colour: `RED_FONT_COLOR`. Wash opacity **0.38**. Edge opacity **1**.
- Gamepad bars, the pet-bar wash, options and the learned-spells fallback are all out of scope.
- There's no automated test suite for addon code. A task is verified by `scripts/lint.sh` (and `luacheck addons template` when available), plus the in-game checks listed per task. Pure logic stays in small functions a reviewer can check by reading.

## Review focus

1. **A wash that sticks.** The slot is emptied, the action changes (talent swap, paging, stance or form), or the target is dropped. In every case no wash may stay. Each relies on Blizzard either calling the range function with `checksRange = false` or firing `ActionButton.OnActionChanged` (in-game check 3).
2. **The secret-safe AND.** The wash's effective alpha must be `vertexAlpha(checksRange) × regionAlpha(inRange)`. Check that the two setters don't overwrite each other's alpha, and that `colorIfFalse` has alpha 0 (in-game checks 1 and 4).
3. **Layering.** The wash must be below the cooldown swipe, hotkey, count and proc glow (all child frames of the button) and above the icon (in-game check 5).
4. **Pet and gamepad buttons reach the same hook.** They must never get textures or a wash. Only standard action buttons do.
5. **Taint.** The hook runs inside Blizzard's secure range update, and nothing it does may write fields Blizzard reads (in-game check 6).

---

## File structure

```
addons/ForeverActionBars/
  ForeverActionBars.toc   TOC, metadata, file list (Knowledge.lua before Wash.lua)
  CHANGELOG.md            "## Unreleased" player line
  Core.lua                template shim (ns.dev, ns.log, ns.Inert), no DB
  Knowledge.lua           ForeverDev-only pet range evidence
  Wash.lua                overlay textures, the range hook, clearing
types/forever.lua         annotation for ActionButton_UpdateRangeIndicator (if LuaLS flags it)
.luacheckrc               read globals the addon reads, if luacheck flags them
```

---

### Task 1: Scaffold ForeverActionBars

**Files:**
- Create: `addons/ForeverActionBars/` via `scripts/new-addon.sh ForeverActionBars`
- Modify: `addons/ForeverActionBars/ForeverActionBars.toc`, `Core.lua`, `CHANGELOG.md`

**Interfaces:**
- Produces: `ns.dev`, `ns.log(tag, ...)`, `ns.Inert(t)` (template shim, unchanged).

- [ ] **Step 1:** Run `scripts/new-addon.sh ForeverActionBars`. Expected: `created addons/ForeverActionBars` and a link line. (The game links already point at this worktree.)
- [ ] **Step 2:** TOC: `## Title: ForeverActionBars`, `## Notes: Tints action buttons red while their target is out of range.`, add `## X-Category: Action Bars`, **delete** `## SavedVariables`. Keep the `#@do-not-package@` OptionalDeps block.
- [ ] **Step 3:** `Core.lua`: delete `defaults` and the `EventUtil.ContinueOnAddOnLoaded` DB block. Replace the shim comment's tag list with `-- Tags: RANGE (Wash.lua, Knowledge.lua).`
- [ ] **Step 4:** `CHANGELOG.md` under `## Unreleased`: `- Action buttons get a red wash and edge while their ability is out of range of your target, on top of the red hotkey.`
- [ ] **Step 5:** Run `scripts/lint.sh`. Expected: clean.
- [ ] **Step 6: Commit**

```bash
git add addons/ForeverActionBars && git branch --show-current && git commit -m "feat(foreveractionbars): scaffold the addon"
```

### Task 2: The wash on standard action buttons

**Files:**
- Create: `addons/ForeverActionBars/Wash.lua` (add it to the TOC after `Core.lua`)
- Modify: `types/forever.lua` (only if LuaLS reports `ActionButton_UpdateRangeIndicator` undefined)

**Interfaces:**
- Consumes: `ns.log`, `ns.dev` (Task 1). `ns.Knowledge.PetRange(button, checksRange, inRange)` (Task 3; until then, guard the call with `if ns.Knowledge then`).
- Produces: `ns.Wash.IsActionButton(button) -> boolean`, `ns.Wash.Apply(button, checksRange, inRange)`, `ns.Wash.Clear(button)`.

Verified seams (Forever source):
- `ActionButton_UpdateRangeIndicator(self, checksRange, inRange)`, global, `Blizzard_ActionBar/Shared/ActionButton.lua:1289`. Callers: action buttons on `ACTION_RANGE_CHECK_UPDATE` (`:1071`), `PetActionBar.lua:111` (timer, `PetActionBar.actionButtons[i]`), and `Blizzard_GamepadActionBars/Camelot/PetActionFlyoutButton.lua`.
- `ActionBarActionButtonMixin:UpdateAction` fires `EventRegistry:TriggerEvent("ActionButton.OnActionChanged", self)` after every action change (`:566`), except for assisted-combat-rotation buttons.
- Button layers (`Mainline/ActionButtonTemplate.xml`): `icon` and `SlotBackground` at BACKGROUND, `IconMask` the icon's mask, `Border` atlas `UI-HUD-ActionBar-IconFrame-Border` at OVERLAY. The cooldowns and the hotkey/count container are child frames, so they draw above all of the button's own regions.
- `Region:SetAlphaFromBoolean(value, alphaIfTrue, alphaIfFalse)` and `Region:SetVertexColorFromBoolean(value, colorIfTrue: ColorMixin, colorIfFalse: ColorMixin)`, both `SecretArguments = "AllowedWhenTainted"` (`SimpleRegionAPIDocumentation.lua:134`, `:205`). Neither value may be nil.

- [ ] **Step 1: `ns.Wash.IsActionButton(button)`** is true only for standard action bar buttons: `button.UpdateAction == ActionBarActionButtonMixin.UpdateAction`. Pet buttons and gamepad flyout buttons don't carry that method. Write this as a separate function so a reviewer can check it.
- [ ] **Step 2: Overlay creation, lazily on a button's first `Apply`.** Store the textures in a weak-keyed table local to `Wash.lua`, keyed by button. **Don't** write fields onto the button.
  - wash: `button:CreateTexture(nil, "BACKGROUND", nil, 7)`, `SetColorTexture(1, 1, 1)`, all points on `button.icon`, `AddMaskTexture(button.IconMask)`.
  - edge: `button:CreateTexture(nil, "OVERLAY", nil, 1)`, `SetAtlas("UI-HUD-ActionBar-IconFrame-Border", true)`, anchored like `button.Border` (`SetPoint("CENTER", button.Border)` after reading its point once out of combat, or `"CENTER"` on the button).
  - Both start at alpha 0.
- [ ] **Step 3: `ns.Wash.Apply(button, checksRange, inRange)`.** For each texture `t` with opacity `a` (wash 0.38, edge 1):

```lua
t:SetVertexColorFromBoolean(checksRange, SHOWN, HIDDEN) -- SHOWN = RED_FONT_COLOR rgb with alpha 1, HIDDEN = same rgb with alpha 0
t:SetAlphaFromBoolean(inRange, 0, a)
```

  Build `SHOWN` and `HIDDEN` once with `CreateColor`. No `if` on either argument.
- [ ] **Step 4: `ns.Wash.Clear(button)`** sets both textures' alpha to 0 when the button has textures, and does nothing otherwise.
- [ ] **Step 5: The hook.** `hooksecurefunc("ActionButton_UpdateRangeIndicator", function(button, checksRange, inRange) ... end)`:
  - `ns.Wash.IsActionButton(button)` → `Apply`;
  - else if `button:GetParent() == PetActionBar` → `ns.Knowledge.PetRange(button, checksRange, inRange)`;
  - else nothing.
  - `if checksRange == nil or inRange == nil then Clear(button) return end`. This is a nil check only, since nil is never secret; do it before `Apply`, because both setters reject nil.
- [ ] **Step 6: Clearing.** `EventRegistry:RegisterCallback("ActionButton.OnActionChanged", function(_, button) ns.Wash.Clear(button) end, ns)`. The next range update for the new action re-applies the wash.
- [ ] **Step 7: `RANGE` logging (in-game checks 1 and 3).** Inside `if ns.dev.enabled then` in the hook: `ns.dev:LogChanged("secret " .. kind .. situation, issecretvalue(checksRange) or issecretvalue(inRange), "RANGE", kind, "secret", ...)`, where `kind` is `"action"` or `"pet"` and `situation` is `InCombatLockdown() and "combat" or "idle"`. In `Clear`, `ns.dev:LogOnce`-style one line per cause (`"actionChanged"`, `"nilArgs"`).
- [ ] **Step 8:** Run `scripts/lint.sh` (and `luacheck addons template`). Add `ActionButton_UpdateRangeIndicator` to `types/forever.lua` as `---@param self Button ...` if LuaLS needs it, and read globals to `.luacheckrc` if luacheck needs them. Expected: clean.
- [ ] **Step 9: Commit**

```bash
git add addons/ForeverActionBars/Wash.lua addons/ForeverActionBars/ForeverActionBars.toc types/forever.lua .luacheckrc && git branch --show-current && git commit -m "feat(foreveractionbars): tint out-of-range action buttons red"
```

**In-game checks for this task** (Phase 6, after `/rl`):
1. `RANGE action secret false` logged both idle and in combat, or `true` in combat (the wash must still be correct then).
2. Target dropped, target killed, slot dragged empty, bar paged, form or stance changed, talent or spec swapped: no wash remains.
3. Out of range plus out of mana shows blue under red. Out of range plus unusable shows grey under red. In range looks exactly like Blizzard's.
4. Cooldown swipe, proc glow, hotkey and charge count draw over the wash, and the wash follows the icon's rounded mask.
5. `scripts/devlog.sh --errors`: nothing after a fight.

### Task 3: Pet range evidence

**Files:**
- Create: `addons/ForeverActionBars/Knowledge.lua` (in the TOC **before** `Wash.lua`)

**Interfaces:**
- Consumes: `ns.dev:Observed`, `ForeverDev.Count`, `ns.dev:LogChanged` (ForeverDev API, see `addons/ForeverProfessions/Knowledge.lua` for the pattern).
- Produces: `ns.Knowledge.PetRange(button, checksRange, inRange)`. Inert for players.

- [ ] **Step 1:** Header comment documenting the layout, then `if not ns.dev.enabled then ns.Knowledge = ns.Inert() return end`.
- [ ] **Step 2:** Layout in `ForeverDevDB.observed.ForeverActionBars`:

```
pet[spellID] = { name, lastSeen, results = { [result .. "/" .. player] = count } }
  result: "in" | "out" | "nocheck" | "secret"
  player: "melee" | "far" | "unknown" | "secret"  -- C_Spell.IsSpellInRange(6603, "target") (Auto Attack): true → melee, false → far, nil → unknown
```

  The spell comes from `GetPetActionInfo(button:GetID())` (7th return, `spellID`). Skip when it's nil or secret.
- [ ] **Step 3:** The pet bar polls every ~0.2 s. Record only when `result .. "/" .. player` changed for that button (keep the last key per button locally), so counts mean "transitions" and not ticks.
- [ ] **Step 4:** `ns.dev:LogChanged("pet" .. spellID, key, "RANGE", "pet", spellID, key)`.
- [ ] **Step 5:** Run `scripts/lint.sh`. Expected: clean.
- [ ] **Step 6: Commit**

```bash
git add addons/ForeverActionBars/Knowledge.lua addons/ForeverActionBars/ForeverActionBars.toc && git branch --show-current && git commit -m "feat(foreveractionbars): record pet range evidence"
```

**The evidence that settles goal 4 (deferred, no pet class yet):** `scripts/observed.sh ForeverActionBars` shows a pet melee spell with `in/far` counts. That means the pet's range is measured from the pet, so the pet-bar wash can be turned on. `out/melee` with the pet far away also points to the pet. `in/melee` and `out/far` only ever → inconclusive.

---

## Phase 5 reviewers (beyond the core four)

- **UI reviewer** (`general-purpose`): layering, masking, native atlas and colour, nothing written to Blizzard fields.
- No `savedvariables-guard` (no SavedVariables, slash commands, bindings or settings).
- No release reviewer unless `.pkgmeta` changes.

## After the PR (Phase 6/7)

- A project memory, `foreveractionbars-launch-checks`, with the in-game checks above and the pet evidence rule, in case the user can't run everything before merge.
- Spec amendment: the overlay is two textures on the button, not a nested frame. The AND is nested `C_CurveUtil.EvaluateColorValueFromBoolean` into `SetAlpha` (vertex alpha × region alpha didn't work; see the spec's amended section).
