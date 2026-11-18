# 0005. Draw the player power bar ourselves, in a resource bars module

Date: 2026-11-18. Status: proposed (in-game checks pending). Supersedes decision 1 of
[ADR 0002](0002-detach-the-player-power-bar-by-reparenting-blizzards-bar.md); its decisions 2 and 3
are covered below.

## Context

ADR 0002 moved Blizzard's own player-frame power bar into a holder of ours and let Blizzard keep
updating it. That ties the bar to Blizzard's player frame being alive. The user now runs
EllesmereUI's unit frames, which hide Blizzard's player frame the way oUF layouts do:
`UnregisterAllEvents()` on the frame and on its bars (`EllesmereUIUnitFrames.lua`, `HandleFrame`,
once at PLAYER_LOGIN). Blizzard's bar then keeps the power type it had at login; a druid in Bear
Form saw a mana bar where rage belonged (in game, 18 November 2026).

The user's direction: the bar becomes a RazzhUI resource bar that works the same whichever player
frame is shown, and the addon stops touching Blizzard's player frame.

What ADR 0002 feared about drawing the bar ourselves has since been tried: `OffFormPower.lua` feeds
`UnitPower` and `UnitPowerMax`, both secret, straight into status bars of ours, and that has run
clean in game since 12 November 2026.

## Decision

1. **The power bar is a status bar of ours**, fed from `UnitPower("player", type)` and
   `UnitPowerMax` on the player's power events. The power type and its art come from
   `UnitPowerType` (not secret) and Blizzard's `PowerBarColor` table. Secret values are only handed
   to widgets (`SetValue`, `SetMinMaxValues`, `SetFormattedText`); nothing is compared or
   calculated.
2. **The addon never touches Blizzard's player frame.** The health bar growth and the removal of
   Blizzard's mana bar go. A player who still shows Blizzard's player frame sees its mana bar as
   well as ours.
3. **The addon is renamed ForeverResourceBars** ("RazzhUI Resource Bars"), with its own
   `ForeverResourceBarsDB`. Nothing was released under the old name.
4. **Placement stays with LibEditMode** (ADR 0002, decision 3). The combat gate for layout changes
   (ADR 0002, decision 2) goes: it existed for Blizzard's protected bars, and our frames are not
   protected.

## Alternatives considered

- **Switch the events of Blizzard's bar back on** (`hooksecurefunc(bar, "UnregisterAllEvents", ...)`
  plus the bar's own event list from `UnitFrameManaBar_Initialize`). A small fix that keeps the
  pulse, spend flash and text for free, since Blizzard's handler would still run untainted. It
  stays bound to Blizzard's frame and undoes part of what the unit frame addon asked for. The user
  chose to cut the tie instead.
- **Call `UnitFrameManaBar_UpdateType` from our code on UNIT_DISPLAYPOWER.** It writes
  `bar.powerType`, `bar.currValue` and `PlayerFrame.predictedPowerCost` tainted, and
  `UnitFrameManaBar_OnUpdate` reads them every frame before subtracting and comparing `UnitPower`'s
  secret result (`Blizzard_UnitFrame/Mainline/UnitFrame.lua`, lines 576-603 and 911-937). An error
  per frame, by the source.
- **Our own instance of Blizzard's mana bar template, driven by Blizzard's functions.** A frame an
  addon creates runs that code tainted; same secret arithmetic, same errors.

## Consequences

- Lost with Blizzard's bar, because they need arithmetic or a comparison on secret power: the spend
  flash (`BuilderSpenderFrame`: a change of more than 10% of the maximum), the full-power pulse
  (`newValue == maxValue`) and the mana cost preview while casting. The numbers on the bar are
  rebuilt (`AbbreviateLargeNumbers`, `UnitPowerPercent` with a curve, `SetFormattedText`; all accept
  secret arguments from addon code per the API docs), which is unconfirmed in game until the
  spec's checks have run.
- `HealthBar.lua`, `Layout.lua` and `Dev/ArtProbe.lua` (with `/fufart`) are deleted.
- Saved bar positions don't follow the rename by themselves: SavedVariables belong to the addon's
  name. The spec gives a one-time command to carry the file over.
- The module no longer cares which unit frame addon is installed, or whether one is.
