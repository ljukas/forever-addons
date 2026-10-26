# 0001: Find minimap tracking dots by probing the minimap's mouseover

Date: 2026-10-26. Status: accepted.

## Context

ForeverMap shows an icon on each herb or ore tracking dot on the minimap
(`docs/superpowers/specs/2026-10-26-forevermap-tracking-icons-design.md`). The Forever client
gives addons no list of tracked nodes or their positions, and no way to change or hide
individual minimap blips.

## Decision

Probe the minimap: switch on its soft cursor (`Minimap:SetUsingSoftCursor`), move its mouseover
over a grid of points (`Minimap:UpdateMouseoverAtPoint`), read the names under each point
(`C_TooltipInfo.GetMinimapMouseover`), and keep only names in ForeverMap's own herb and ore
name list. Group the hits into dots and cover each with an icon, anchored to the world so it
follows the minimap between scans. This is NodeSight's technique; NodeSight has no license, so
the code is our own.

## Alternatives considered

- **Change the blips themselves** (a blip texture setter): no such API in Forever's generated
  docs. `Minimap:SetIconScale` only resizes every minimap icon at once, and Edit Mode owns it.
- **Use recorded gather positions** (ForeverProfessions' history): shows only nodes gathered
  before, not what the tracking shows now, and would make ForeverMap depend on
  ForeverProfessions, which the user ruled out.
- **Decide a dot's kind from the active tracking alone**, with no name list: the mouseover also
  names party members, NPCs and quest objects, which would get herb or ore icons.
- **Hook the player's own minimap hover** (as ForeverProfessions' tooltip lines do): only sees the
  dot under the real cursor, not all of them.

## Consequences

- ForeverMap keeps an enUS herb/ore name list, copied from ForeverProfessions (no shared code
  between addons). Other locales see no icons until names are added.
- The scan costs some work every frame while a finder is on; it is spread over frames and paused
  while the player's mouse is over the minimap.
- Icons cover whatever is under them, including the player's arrow; size and see-through near
  the player keep that acceptable.
- Whether all of this behaves as the source suggests is unverified until the client launches.
