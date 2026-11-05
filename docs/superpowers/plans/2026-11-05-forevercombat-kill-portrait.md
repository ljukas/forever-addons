# ForeverCombat Kill Portrait Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wash the target/focus frame portrait red while the player's DoTs cover the unit's remaining health.

**Architecture:** `UI/Cue.lua`'s "texture only on screen at 100%" trick is split into a shared core plus two shapes: the existing bar-end glow and a new portrait tint. The DoT module declares a `portraitCue` next to its bar `cue`; `UI/Hosts.lua` renders both from the same total in the same pass; `Options.lua` adds a child checkbox for it.

**Tech Stack:** Lua 5.1, Forever (Midnight 12.x API), Blizzard `Settings`, StatusBar/MaskTexture widgets.

**Spec:** `docs/superpowers/specs/2026-11-05-forevercombat-kill-portrait-design.md`

## Global Constraints

- Health is secret (even out of combat): no Lua comparison or arithmetic on `UnitHealth`; it only goes into `StatusBar:SetMinMaxValues`.
- Native look: Blizzard's `RED_FONT_COLOR`, the frame's own `TargetFrameContainer.PortraitMask`; no custom art.
- No taint: only our own frames/textures, parented to Blizzard's; no fields set on Blizzard frames.
- Setting key `dotKillPortrait`, default true, no DB migration.
- No automated tests exist for addon code; each task's check is `scripts/lint.sh` clean plus reading. In-game checks are the launch checks below (the game is owned by another session: do **not** run `scripts/worktree.sh game`).

## Review Focus

1. Portrait tint and bar glow disagree: they must use the same `total` and `GetMax(unit)` in the same `Render` call.
2. Option or DoT Meter turned off mid-fight: the portrait must clear on the next refresh (`HideMeter` and the setting check both hide it).
3. Target dies, changes, or frame hides while red: `Refresh` hides the meter (dead/invisible/no key), which must hide the portrait cue too.
4. Focus frame in small size: the window is anchored to the portrait texture, so it scales with it; no hardcoded size except the rider width read from the portrait at create time (`GetWidth()` of the 58 px template texture). Rescaling uses SetScale, so widths in frame units stay valid.
5. Layering: tint drawn over the gold ring or under the portrait (invisible). Launch check; the frame uses `SetUsingParentLevel(true)` on `TargetFrameContainer`.

---

### Task 1: Split the cue into a core and the bar-end shape (refactor, no behaviour change)

**Files:**
- Modify: `addons/ForeverCombat/UI/Cue.lua`
- Modify: `addons/ForeverCombat/UI/Hosts.lua` (call site rename only)

**Interfaces:**
- Produces: `ns.Cue.CreateBarEnd(healthBar, mask, side, glowTemplate) -> ForeverCombatCue` (today's `ns.Cue.Create`, renamed); internal `NewCue(parent, anchorTo, riderWidth) -> cue, bar` that builds the clipping window (anchored with `SetAllPoints(anchorTo)` or by the caller), the `LONG_BAR_WIDTH` bar, and returns the bar so the caller rides a texture on `bar:GetStatusBarTexture()`. `CueMixin:Set(maxValue, total)` and `:Hide()` unchanged.

- [ ] Step 1: Extract the window + long bar construction into `NewCue`; `CreateBarEnd` builds the glow rider and the side anchoring as today. Update the file comment.
- [ ] Step 2: `Hosts.lua` calls `ns.Cue.CreateBarEnd`.
- [ ] Step 3: `scripts/lint.sh` clean.
- [ ] Step 4: Commit `refactor(forevercombat): split the cue into a core and the bar-end glow`.

### Task 2: Red portrait cue, module declaration, hosts and checkbox

**Files:**
- Modify: `addons/ForeverCombat/UI/Cue.lua` (add `CreatePortrait`)
- Modify: `addons/ForeverCombat/Modules.lua` (document `portraitCue`)
- Modify: `addons/ForeverCombat/Modules/DoTMeter.lua` (declare it)
- Modify: `addons/ForeverCombat/UI/Hosts.lua` (create, render, hide)
- Modify: `addons/ForeverCombat/Options.lua` (child checkbox)
- Modify: `addons/ForeverCombat/Core.lua` (strings `DOT_KILL_PORTRAIT`, `DOT_KILL_PORTRAIT_TOOLTIP`)
- Modify: `addons/ForeverCombat/CHANGELOG.md` (`## Unreleased` player line)

**Interfaces:**
- Consumes: `NewCue` from Task 1.
- Produces: `ns.Cue.CreatePortrait(container) -> ForeverCombatCue`, where `container` is `frame.TargetFrameContainer`; window `SetAllPoints(container.Portrait)`; rider texture `ARTWORK`, `SetColorTexture(RED_FONT_COLOR:GetRGB())`, `SetBlendMode("MOD")`, width = `container.Portrait:GetWidth()`, `AddMaskTexture(container.PortraitMask)`.
- Module field: `portraitCue = { setting = "dotKillPortrait", label = L.DOT_KILL_PORTRAIT, tooltip = L.DOT_KILL_PORTRAIT_TOOLTIP }`. It lights on the same `cue.GetMax`/total as the module's bar cue.

- [ ] Step 1: `CreatePortrait` in `Cue.lua`.
- [ ] Step 2: `Modules.lua` doc block + DoT module field + strings in `Core.lua`.
- [ ] Step 3: `Hosts.lua`: in `Init`, `meter.portraitCue = module.portraitCue and ns.Cue.CreatePortrait(frame.TargetFrameContainer)`; in `Render`, after the bar cue, `Set(max, total)` when `ns.Options.Get(module.portraitCue.setting)`, else `Hide()`; `HideMeter` hides it.
- [ ] Step 4: `Options.lua`: after a module's checkbox, if it has `portraitCue`, register its setting (`Settings.Default.True`, same `OptionChanged` callback), `Settings.CreateCheckbox`, then `initializer:SetParentInitializer(parentInitializer, function() return ns.Options.Get(module.setting) end)`.
- [ ] Step 5: CHANGELOG line under `## Unreleased`.
- [ ] Step 6: `scripts/lint.sh` clean; `git diff` reread against Review Focus 1–3.
- [ ] Step 7: Commit `feat(forevercombat): turn the portrait red when your dots will kill`.

## Step reviewers (Phase 5)

Core (`addon-reviewer`, `api-verifier`, correctness, spec) plus the **UI reviewer** (frames, masks, layering) and `savedvariables-guard` (new settings key).

## Launch checks

As in the spec: red at the same moment as the bar glow and back off on heal/DoT end; round and aligned, incl. boss frame and small focus frame; face still recognisable; combo points visible; both checkboxes clear it at once; `scripts/devlog.sh --errors` clean. Checked by eye; health is secret so no log line can confirm the kill state.
