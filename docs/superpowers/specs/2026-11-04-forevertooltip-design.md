# ForeverTooltip: class-coloured player tooltips

Date: 2026-11-04 · Status: draft, awaiting approval · Addon: ForeverTooltip (new)

## Intent

Hovering another player should tell you at a glance **what class they are** and **whether
they are friend or foe**. Blizzard's unit tooltip colours the player's name by reaction
(hostile, attackable, PvP-flagged friendly, friendly) and leaves the level/race/class line
plain. This addon moves the reaction colour down to the level line and gives the name the
player's **official class colour**, the way FlareUI and similar tooltip addons do. It also
adds one opt-in tweak: the tooltip can follow the cursor.

Prior art the user pointed at or picked from: FlareUI's tooltip module (class/reaction-coloured
names, cursor anchoring). Cursor-anchor options compared: ElvUI (toggle, anchor type, X/Y
offsets), SmartTooltip (9 anchor points, offsets), IncredibleTooltip (lock to cursor, offsets).
The user asked for the minimal version of this.

## Goals

1. **Class-coloured name.** When the hovered unit is a player, the tooltip's name line uses the
   player's official class colour: `C_ClassColor.GetClassColor(classFilename)` (the client's
   own class colour table, the same as `RAID_CLASS_COLORS`). No custom colour values.
2. **Reaction-coloured level line.** On the same tooltip, the "Level 60 Human Warrior" line is
   coloured by reaction, using **exactly the colours Blizzard's `GameTooltip_UnitColor(unit)`
   would have given the name** (red for hostile, yellow for attackable-but-not-hostile, green
   for PvP-flagged friendly, Blizzard's colour for everyone else). Reuse that function rather
   than re-deriving the rules, so it reads the same as the rest of the UI.
3. **Everywhere a player unit tooltip shows:** players hovered in the world, on unit frames,
   party and raid frames. **Including your own character.**
4. **Tooltip follows the cursor (option, off by default).** One checkbox in Blizzard's
   Options → AddOns panel. When ticked, tooltips for things hovered **in the world** (players,
   NPCs, objects) follow the cursor instead of sitting at the default spot. No anchor-type
   dropdown, no offset sliders: Edit Mode already lets players move the default spot, so the
   addon only chooses "default spot or cursor". It must feel **natural and smooth and not cover
   what you are looking at** (see "Cursor anchoring" below).

## Cursor anchoring (how it should feel)

Researched against ElvUI, SmartTooltip, IncredibleTooltip and the Forever source:

- **The engine moves the tooltip, not Lua.** Use the client's cursor anchors in `SetOwner`, which
  the client repositions every frame itself: no `OnUpdate` loop, no `GetCursorPosition` maths,
  no jitter, correct at any UI scale. Hand-rolled followers are what make some addons' tooltips
  lag or shake.
- **Below-right of the cursor, not above it.** Use `"ANCHOR_CURSOR_RIGHT"` with a small fixed
  offset so the tooltip clears the cursor arrow and sits below and to the right of the pointer.
  Plain `"ANCHOR_CURSOR"` puts the tooltip above the pointer, over the head and nameplate of the
  unit you are hovering. Blizzard itself uses `ANCHOR_CURSOR_RIGHT` for world loot objects in
  `GameTooltipDataMixin:SetWorldCursor`. The exact offset is tuned at launch (launch check).
- **No flash at the old spot.** Re-anchor *before* the tooltip is filled and shown: hook the
  anchoring step (`GameTooltip_SetDefaultAnchor`), not the tooltip's `OnShow`, so the tooltip
  never appears at the default spot for a frame and then jumps.
- **World only.** World hovers reach the tooltip as `WORLD_CURSOR_TOOLTIP_UPDATE` →
  `GameTooltip:SetWorldCursor(anchorType)`, which, for `Enum.WorldCursorAnchorType.Default`,
  calls `GameTooltip_SetDefaultAnchor(GameTooltip, UIParent)`. Unit frames, buttons and other UI
  pass their own frame as the parent. So: only re-anchor `GameTooltip` when its parent is
  `UIParent`; everything else keeps Blizzard's anchoring. *Amended in the plan:* the minimap,
  XP bar and chat hyperlinks also anchor to `UIParent`, so the addon also requires the mouse to
  be over the world (`GetMouseFoci()` gives `WorldFrame`). (If the client already asks for
  `Cursor` or `Nameplate` anchoring, the addon does nothing.)
- **Keep Blizzard's fade.** When the cursor leaves a world unit Blizzard fades the tooltip out;
  that stays as is.
- **Screen edges:** the tooltip is clamped to the screen, so near the right or bottom edge it may
  slide under the cursor. Acceptable for this version; flipping sides near edges is left out to
  keep it minimal.
- **Taint risk to check at launch.** Blizzard's comment in `SetWorldCursor` warns that taint
  reaching the tooltip can make it "display no lines" when world cursor data has secret
  content. Re-anchoring from a `hooksecurefunc` post-hook should not spread taint into the
  caller, but this is the main launch check: hover players and NPCs in and out of combat with the
  option on and confirm full tooltips. If it fails, the fallback is to drop cursor anchoring, not
  to replace Blizzard code.

## Non-goals

- **NPC colours are untouched.** Blizzard already colours NPC names by reaction; the colouring
  only applies to `UnitIsPlayer` units (pets and other player-controlled non-players keep
  Blizzard's colours too). The cursor option is separate: when ticked, it moves *every* world
  hover (players, NPCs, objects) the same way, so the tooltip never behaves differently by what
  you point at.
- No reskin: background, border, font, scale and textures stay Blizzard's.
- None of the other ideas discussed (class-coloured border, "Targeting:" line, guild-line
  polish, item quality border / item ID). They may come later as separate features.
- No options beyond the one checkbox. The colouring is always on while the addon is enabled.

## Anti-goals (would be a failure even if it "works")

- Any Lua error, taint or `ADDON_ACTION_BLOCKED` caused by tooltips, in or out of combat.
  Tooltips show constantly, so a failure here is felt every few seconds.
- Overwriting Blizzard functions or tooltip fields. Hooks only (`TooltipDataProcessor`,
  `hooksecurefunc`).
- Making the tooltip *less* informative than Blizzard's: if the addon can't work out a colour,
  the line keeps Blizzard's colour.
- English-only behaviour: finding the level line must work in every client language.

## Constraints

- Forever client, interface 16001, Midnight 12.x addon API with secret values. Verify every
  API in `.cache/wow-ui-source` (CLAUDE.md).
- **Secret values.** Per the Forever API docs, `UnitClass` (and `UnitClassBase`, `UnitIsPVP`)
  are `SecretWhenUnitIdentityRestricted`; the `Unit*` functions take `SecretArguments =
  "AllowedWhenUntainted"`, so a secret unit token can't be passed from addon code.
  `C_ClassColor.GetClassColor` allows secret arguments when tainted. **Decided behaviour:**
  when the unit token, the class or anything the addon would branch on is secret, the addon
  leaves that line exactly as Blizzard drew it. It never compares or branches on a secret
  value (`issecretvalue` first).
- Hook points found in the Forever source (the builder confirms the details):
  - Blizzard colours the name in `TooltipDataRules.UnitName`, a
    `TooltipDataProcessor.AddLinePreCall(Enum.TooltipDataLineType.UnitName, ...)` in
    `Blizzard_SharedXMLGame/Tooltip/TooltipDataRules.lua`. The addon adds its own line call
    for the same line type (or a unit post-call) and sets the class colour after Blizzard's.
  - The level line has **no line type of its own** (it arrives as `None`), so the addon has to
    find it in the built tooltip. It must be found in a locale-independent way (for example
    from the client's own level format strings such as `UNIT_LEVEL_TEMPLATE` /
    `UNIT_TYPE_LEVEL_TEMPLATE`, or the unit's data, not the English word "Level").
  - Default anchoring goes through `GameTooltip_SetDefaultAnchor(tooltip, parent)` in
    `Blizzard_SharedXML/SharedTooltipTemplates.lua`, which anchors to
    `GameTooltipDefaultContainer` (the Edit Mode tooltip position). `"ANCHOR_CURSOR"` is used
    by Blizzard's own code in this build, so it exists.
- New addon from `template/Addon` via `scripts/new-addon.sh ForeverTooltip`: `## Category:
  Forever Enhanced Addons`, `## X-Category` for the genre (Tooltip), the ForeverDev shim, MIT.
- One account-wide SavedVariable, `ForeverTooltipDB`, holding the checkbox. Options panel with
  Blizzard's `Settings` API (follow `addons/ForeverMinimap/Options.lua` and `Database.lua`).

## Decided by the user

- First version: class-coloured name, reaction-coloured level line, cursor-follow checkbox.
- Official class colours for the name.
- Reaction colours as Blizzard uses them, on the level line.
- Applies to all player tooltips, including your own character; NPCs untouched.
- Minimal cursor option: one checkbox, no extra controls.

## Claude's calls (the user can override)

- **Which tooltips follow the cursor:** only tooltips for **things hovered in the world**
  (players, NPCs, objects), not every tooltip that uses the default spot. Rationale: a tooltip
  glued to the cursor over buttons and minimap icons covers what you are aiming at. Everything
  else keeps Blizzard's anchoring.
- **Placement below-right of the cursor** (`ANCHOR_CURSOR_RIGHT` plus a small offset), so the
  hovered unit's head and nameplate stay visible.
- The checkbox is **off by default**, so installing the addon changes only colours.
- Addon name **ForeverTooltip**, `## X-Category: Tooltip`.
- Only `GameTooltip` is coloured (the main tooltip that shows unit tooltips); other tooltip
  frames are left alone unless the builder finds Blizzard routing player unit tooltips through
  another frame.

## Left to the builder

- Exactly which `TooltipDataProcessor` call (line pre/post call vs. unit post-call) and how to
  locate the level line, within the constraints above.
- How cursor anchoring re-owns the tooltip (`SetOwner(parent, "ANCHOR_CURSOR")` after the hook
  vs. repositioning), as long as it doesn't overwrite Blizzard code and leaves non-world
  tooltips alone.
- File layout, `ns.log` tags and launch checks (e.g. log once when a value comes back secret,
  which line was found as the level line, which anchor was applied).

## Untested

The client launches today (2026-11-04); nothing here has run in game. The secret-value
behaviour of `UnitClass` on hovered players, the position of the level line, and cursor
anchoring all need the launch checks.
