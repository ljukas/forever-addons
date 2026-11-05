# ForeverCombat: HoT meter on the player frame

One step, one PR: `feat(forevercombat): show the HoT meter on your own unit frame`.

## Shape

- The HoT meter today draws on the target and focus frames only. A player with Rejuvenation on
  themselves sees nothing on their own frame unless they target themselves.
- **Decision (user):** PlayerFrame becomes a third host, behind a new checkbox **"Show on Your
  Own Frame"** under the HoT Meter checkbox, on by default. It is greyed out while the HoT Meter
  is off. Settings key `hotPlayerFrame` in `ForeverCombatDB.settings`; registering the setting
  fills its default, so existing databases need no migration.
- The DoT meter never draws on the player (`ns.Units.Fits` needs an attackable unit), so the
  option is the HoT meter's alone.
- Deferred: party and raid frames, nameplates, the pet frame.

## Seams (checked in `.cache/wow-ui-source`)

- `PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.HealthBarsContainer` holds `HealthBar`
  and `HealthBarMask`, like the target frame (`Mainline/PlayerFrame.xml`, `PlayerFrame_GetHealthBarContainer`).
- `HealthBar.MyHealPredictionBar` / `OtherHealPredictionBar` are `StatusBarOverlaySegment`s with a
  `FillMask`, the same as the target's, so `HostMixin:GetIncomingHealEnd` works unchanged.
- The player frame has no `UpdateHealthBarVisuals` method: it is the global
  `PlayerFrame_UpdateHealthBarVisuals` (overridden by `Camelot/PlayerFrame.lua`), hooked with
  `hooksecurefunc` by name.
- In a vehicle `PlayerFrame.unit` becomes `"vehicle"`; a host only draws while
  `frame.unit == host.unit`.
- PlayerFrame's `OnEnter` is `UnitFrame_OnEnter` → `UnitFrame_UpdateTooltip`, which `Tooltip.lua`
  already hooks, so hovering the player frame lists the HoTs too.
- Nesting: `initializer:SetParentInitializer(parent, predicate)` (`Blizzard_SettingControls.lua`).

## Tasks

1. `UI/Hosts.lua`: `AddHost(frame, unit, container, hookVisuals, setting)`; hosts with a setting
   hide while it's off; skip drawing when `frame.unit ~= unit`. Add the player host.
   `Tooltip.lua`: skip hosts that aren't showing.
2. `Options.lua` + `Core.lua` strings: the nested checkbox.
3. TOC notes, HoT tooltip string, CHANGELOG line.

Taint: all frames are created at load like the target and focus hosts; nothing touches a secure
frame's attributes, points or visibility, and only `HookScript` / `hooksecurefunc` are used.

## Reviewers

Core reviewers, plus `savedvariables-guard` (new settings key) and a UI reviewer.
**Review Focus:** the player frame's paths and hook name; the vehicle guard; the option wiring
(default, greying, `OptionChanged`).

## Launch checks

- `/rl`: `scripts/devlog.sh --tag HOST` shows `HOST player bar width ...` with a non-secret width.
- Cast Rejuvenation on yourself with no target: `DISPLAY player <guid> hot=1 from fill (...)`, and
  the segment sits right of the green on the player frame, inside its rounded mask.
- Untick "Show on Your Own Frame": the segment hides; tick it again: it returns.
- Hover the player frame with a HoT running: the tooltip lists it.
