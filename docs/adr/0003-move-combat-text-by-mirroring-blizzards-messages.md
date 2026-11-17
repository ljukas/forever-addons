# 0003. Move the player's combat text by mirroring Blizzard's messages

Date: 2026-11-17. Status: accepted (in-game check pending, see the spec).

## Context

The floating text for things that happen to the player ("15 (Block)", "-42", "+120") is drawn by
Blizzard's `CombatText` frame (`Blizzard_CombatText`, load-on-demand). Its start point, scroll
distance, lifetime and text height are fixed numbers; the game only offers a direction (up, down,
arc). We want players to place it in Edit Mode and set its scroll length, duration and font size.

`C_CombatText.GetCurrentEventInfo` has `SecretReturns = true`, and `CombatTextMixin:OnEvent`
compares and does arithmetic on what it returns (`data == 0`, `arg3 > 0`), as does its low-health
check (`UnitHealth / UnitHealthMax`). Those only work while that code runs untainted.

## Decision

Mirror. `hooksecurefunc(CombatText, "AddMessage", ...)` hands us every message Blizzard decided to
show, already worded and coloured (`message, scrollFunction, r, g, b, displayType, isStaggered`).
We draw it with our own font strings in our own Edit Mode box and hide Blizzard's copy with
`CombatText:SetAlpha(0)`. We write no field on `CombatText`, `CombatTextConstants` or
`CombatTextTypeInfo`, and never call a `CombatText` method.

The message may be a secret string. We only pass it to `FontString:SetText`
(`SecretArguments = "AllowedWhenTainted"`) and never read, compare or measure it.

## Alternatives

- **Rewrite Blizzard's numbers** (`CombatText.textLocations` after `UpdateDisplayedMessages`,
  `CombatTextConstants.MessageScrollSpeed` and friends). Least code, and Blizzard's own animation
  stays. Rejected: the values we write are tainted, `OnUpdate` reads them, and `OnUpdate` calls
  `self:UpdateDisplayedMessages()` when the window's size changes. Run tainted, that writes a
  tainted `self.unit`, after which every `UNIT_HEALTH` taints the handler before its secret
  arithmetic: a Lua error on each health change until `/reload`. The arc mode's radius is also a
  local constant we couldn't reach.
- **Replace it**: turn Blizzard's text off and handle `COMBAT_TEXT_UPDATE` ourselves. Rejected: the
  wording branches on secret amounts (a partial block against a full hit), which addon code can't
  do, and we'd re-implement every message type and the Options > Combat filters.

## Consequences

- Blizzard keeps owning what is shown, its wording, its colours and the Options > Combat filters
  and on/off switch. We own only where and how it moves.
- We maintain a small animation of our own (scroll, fade, crit pop, stacking), ported from
  `CombatText.lua`.
- Blizzard's frame still animates its invisible copies. Its pool holds 20 lines.
- If a future build makes `AddMessage` local or renames it, the hook finds nothing: we then leave
  Blizzard's text visible and untouched.
