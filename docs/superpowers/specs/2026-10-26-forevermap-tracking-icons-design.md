# ForeverMap: tracking dots as icons — design

Date: 2026-10-26. Status: approved design, not yet planned. Nothing here has run in the client
(WoW Forever launches 2026-11-04); every "measured in game" item below is a launch check.

## Intent

With Find Herbs or Find Minerals on, the minimap shows every node as the same yellow dot, and
you have to hover each one to see what it is. ForeverMap puts the herb or ore tracking icon,
inside Blizzard's gold tracking ring, on each of those dots, so the minimap reads at a glance and
still looks like part of the game.

This is ForeverMap's first feature. ForeverMap is the base-map addon: minimap and map tweaks
that need no profession data. Gather history and everything profession-specific (item art per
herb, skill requirements, red "too low" tints) belongs to ForeverProfessions. The two addons
don't depend on each other.

Prior art: NodeSight (github.com/Krelock/NodeSight) does this and much more. It has no
license: learn from the technique, copy no code.

## Goals

- Every herb or ore tracking dot on the minimap gets the matching icon: `professions_tracking_herb`
  or `professions_tracking_ore`, the atlases Blizzard's own tracking menu uses for Find Herbs and
  Find Minerals (`Blizzard_Minimap/Mainline/Minimap.lua`, `TRACKING_SPELL_OVERRIDE_ATLAS`).
- The icon is round, inside Blizzard's gold tracking ring, and covers the dot under it.
- The icon sticks to its dot as the player moves and turns. It doesn't trail behind.
- The game's up and down arrows (a node above or below you) stay fully visible, at the default size.
- When the player gathers a node, its icon disappears at once.
- Options → AddOns → ForeverMap: "Show icons on tracked nodes" (on by default) and an icon-size slider.

## Non-goals

- Anything NodeSight does beyond this: shapes, ore rings, sparkles, an arrow to the nearest node,
  switching between Find Herbs and Find Minerals, rare/treasure/other tracking, sounds,
  a "what's new" dialog.
- Item art per herb, skill requirements, red tints, learning names from loot (profession data:
  a later ForeverProfessions extension if wanted).
- Anything on the world map. Other tracking types (Find Treasure, Track Beasts, ...).
- Remembered nodes (gather history) on the minimap. The user's decision: at this stage they show
  only on the world map, so ForeverProfessions stops drawing them on the minimap. That is a
  separate ForeverProfessions PR, not part of this feature; ForeverMap's icons are then the only
  thing drawn on tracking dots.
- Non-English clients. The name list is enUS; on other clients nothing matches and the dots stay as
  they are.

## Anti-goals (failure even if it "works")

- An icon on something that isn't a herb or ore node (a party member, a flight master, a quest
  NPC).
- An icon that covers the up or down arrow at the default size, or sits visibly off its dot
  (NodeSight's ring sits a little low and a little large and covers the down arrow; see the
  user's screenshot in the brainstorm).
- Anything that fights the player's own mouse on the minimap (tooltips flickering, hover lost).
- A look that isn't native: custom art, non-Blizzard colors.
- Noticeable frame-rate cost.

## Constraints (checked in `.cache/wow-ui-source`)

- There is no API for where tracked nodes are, and none to change or hide individual minimap
  blips. `Minimap:SetIconScale(scale)` resizes every minimap icon (party, POIs, ...) and Edit
  Mode sets it too, so it is off limits. Hence the dots are covered, not removed.
- The engine draws minimap blips under addon textures, so an icon covers whatever is under it,
  including the player's own arrow.
- Available (generated docs for this build; none returns secret values, the setters take
  `SecretArguments = "AllowedWhenUntainted"`):
  - `Minimap:SetUsingSoftCursor(bool)` and `Minimap:UpdateMouseoverAtPoint(x, y)`
    (MinimapFrameAPIDocumentation.lua).
  - `C_TooltipInfo.GetMinimapMouseover()` returns `TooltipData` (`data.lines[i].leftText`)
    (TooltipInfoDocumentation.lua).
  - `C_Minimap.GetNumTrackingTypes()`, `C_Minimap.GetTrackingInfo(i)` with `active` and `spellID`,
    `C_Minimap.GetViewRadius()` (yards) (MinimapDocumentation.lua).
  - `C_Map.GetBestMapForUnit`, `C_Map.GetPlayerMapPosition`, `C_Map.GetMapWorldSize`,
    `GetPlayerFacing`, the `rotateMinimap` CVar (as ForeverProfessions' `UI/MinimapPins.lua` uses
    them today).
- Tooltip text may still be secret in some restricted states: check `issecretvalue` on the data,
  its lines and each text, and skip what is secret (no icon from that probe).
- Lua 5.1, `ns`, no globals but SavedVariables and names the client requires (CLAUDE.md).

## How it works (decided)

### Finding the dots: probing the minimap's mouseover

While Find Herbs or Find Minerals is active, ForeverMap periodically scans the minimap: it turns
on the minimap's soft cursor, moves the minimap's mouseover to a grid of points across the
minimap with `UpdateMouseoverAtPoint`, reads the names under each point from
`C_TooltipInfo.GetMinimapMouseover()`, and turns the soft cursor off again in the same frame. A
few dozen points per frame, so a full pass spreads over several frames. This is NodeSight's
technique; the alternatives are in ADR 0001.

- `UpdateMouseoverAtPoint` takes screen coordinates: a point x, y pixels from the minimap's
  bottom left is `((Minimap:GetLeft() + x) * scale, (Minimap:GetBottom() + y) * scale)` with
  `scale = Minimap:GetEffectiveScale()` (as NodeSight does it).
- Only names in ForeverMap's own node list count (below). Every other name under a point (party
  members, NPCs, quest objects, "Peacebloom 3/8" quest progress) is ignored.
- Tooltip lines can hold several names separated by newlines, and color or texture escapes around
  them: split and strip them, like ForeverProfessions' `Tooltip.lua` does for its hover lines.
- The scan pauses while the player's real mouse is over the minimap, and is not started then, so
  it never moves the minimap's mouseover out from under them.
- It keeps running in combat (nothing it calls is blocked; icons shouldn't vanish mid-fight).
- It stops, and all icons go, when neither Find Herbs nor Find Minerals is active, when the
  option is off, or while the minimap is hidden. Which tracking is active is read with
  `C_Minimap.GetTrackingInfo` by spell ID (Find Herbs 2383, 8387; Find Minerals 2580, 8388, the
  IDs Blizzard's tracking menu maps).

### The node list

ForeverMap keeps its own list of enUS herb and ore node names, name → `herb` or `ore`, no
skills or anything else (the user's call: a plain name list is fine in ForeverMap). It starts as
the 49 names in ForeverProfessions' `Data/GatherNodes.lua`, copied, so the addons stay
independent. The kind picks the icon; a dot's name decides its kind, regardless of which
tracking is on.

### Placing an icon exactly on its dot

Hits for the same name that touch on the grid form a group. Each group's dot center is where the
icon goes, and placement must be accurate to about a minimap pixel: NodeSight's visible offset
is what covers the arrows in the user's screenshot. A group too big for one dot is two or more
dots of the same name close together, and must be split into separate dots (NodeSight probes such
groups again on a finer grid). How to find centers and split groups is left to the builder, with
these requirements: the math lives in pure functions apart from frame code, so a reviewer can
check it by reading; it logs what it measured (below) so the result can be checked in game.

As built (amended after the step review): a sweep spans many frames, so every probe hit is turned
into a world position in the frame it is read, and each group's fine probes are laid out in the
world and projected with the current view, so moving or turning during a sweep doesn't move a dot.
A group's fine probes only cover points nearer its own coarse hits than another same-name group's.
One dot's area is measured in every sweep from the median area of its round groups; a stretched
group, or a round one well over a dot's area (a ring of nodes), is split with k-means. A dot cut
off at the minimap's rim is placed slightly inward, but its icon is culled there anyway.

### Sticking to the dot

When a dot is found, its minimap offset is converted to a position on the zone map: minimap
pixels to yards with `C_Minimap.GetViewRadius()` and the minimap's width, rotated by the player's
facing when `rotateMinimap` is on, then added to the player's map position using
`C_Map.GetMapWorldSize`. Every frame (or at the minimap's own redraw rate), icons are redrawn
from those positions and the player's current position and facing, the way ForeverProfessions'
`UI/MinimapPins.lua` draws its pins. So icons move with the minimap exactly; scans only add new
dots and drop gone ones.

Where the client has no map position (some instances and caves), icons keep their minimap offset
and only move on the next scan.

Icons outside the minimap's round edge are not drawn (as `MinimapPins.lua` does).

### When the player gathers

On `LOOT_CLOSED`, the icon nearest the player within a few yards is removed at once, and a scan
starts right away. No profession data is needed. Looting a mob next to a node removes that node's
icon until the next scan puts it back, which is acceptable.

### The look

- The icon texture is the kind's atlas, made round with a `MaskTexture` using the
  `CircleMaskScalable` atlas, the mask Blizzard uses on icons in its own UI (e.g.
  `Blizzard_PVPUI/Mainline/Blizzard_PVPUI.xml`).
- The ring is `Interface\Minimap\MiniMap-TrackingBorder`. Its hole is in the texture's upper
  left, so the ring is drawn larger than the icon and offset to center the hole on the icon:
  Blizzard's help plates center a 64 px ring at (+12, -13) from the icon center
  (`Blizzard_HelpPlate/Blizzard_HelpPlate.xml`), so scale that: ring size about 2.5 × the icon,
  offset (+12/64, -13/64) × ring size. Both scale with the icon-size option.
- Drawn on a frame that is a child of the Minimap, above the blips (unavoidable).
- An icon over the player's own arrow (near the minimap center) is drawn see-through, so the
  arrow stays visible while standing on a node.
- Nodes in a cave (my call, as NodeSight does): the minimap tooltip shows their name in gray
  (`line.leftColor`, or a color escape in the text). Their icon and ring are dimmed and
  desaturated, so a bright icon never suggests a node is reachable where the player stands. The
  probe therefore records, per hit, whether the name was gray, and a dot is gray when its hits
  were. Gray meaning "in a cave" on Forever is a launch check.

### Size and the arrows

The default icon size is chosen so the ring's outer edge clears the game's up and down arrows.
Their pixel size can only be measured in game, so the default is an estimate until launch
(a launch check). The slider lets the player go smaller or larger; its tooltip says that larger
sizes can cover the arrows.

### Options and saved data

- `ForeverMapDB` (account-wide), with a `version` and migrations from the start, like the other
  addons' `Database.lua`: `settings = { showNodeIcons = true, nodeIconSize = <default> }`.
- Options → AddOns → ForeverMap, registered with Blizzard's `Settings` API: a checkbox and a
  slider, writing straight into `ForeverMapDB.settings`, like ForeverProfessions' `Options.lua`.
  Changes apply immediately (icons resize, or all clear when turned off).
- No slash commands or key bindings.

### Dev logging (launch checks)

Through the ForeverDev shim (`ns.log`, `ns.dev:LogOnce`), dev-only work inside
`if ns.dev.enabled`. ForeverDev keeps one 500-line buffer for every addon and its errors, so
these log once or in summary rather than every sweep:
- `LINE`: each distinct tooltip line and color once (do node lines carry a texture escape that
  marks them as tracking nodes? Is a cave node's name gray?);
- `MISS`: each name under a probe that isn't in the list, once;
- `DOT`: each kind of dot once (name, measured radius in minimap pixels, round, how many dots);
- `SCAN`: a summary every 20 sweeps (probes and dots per sweep, time spent inside the sweep and
  the worst single frame, the measured dot radius);
- `LOOT`: what gathering removed (and how far the nearest icon was).

## Left to the builder

- Grid spacing, points per frame, scan intervals (moving, standing still, backing off after empty
  scans), within the frame-rate anti-goal.
- The center-finding and group-splitting method.
- Icon pooling, frame structure, file layout within the addon.
- The default icon size and slider range (estimate now, measured at launch).
- The see-through alpha and the "near the player arrow" distance; the "few yards" for gathering.

## Launch checks (to verify in game, 2026-11-04)

- The scan finds dots: `UpdateMouseoverAtPoint` + `GetMinimapMouseover` name tracked nodes, and
  using the soft cursor doesn't disturb the player's own hovering.
- Placement: icons sit centered on their dots; the default size leaves the up and down arrows
  fully visible (a screenshot like the user's).
- Icons stick while riding and turning, with `rotateMinimap` on and off.
- Gathering removes the icon at once.
- Frame-rate cost while tracking in a node-dense zone.
- Whether node tooltip lines carry a texture escape.
- Gray node names in the minimap tooltip mean the node is in a cave.
