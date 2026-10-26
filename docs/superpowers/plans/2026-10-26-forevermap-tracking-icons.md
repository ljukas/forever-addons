# ForeverMap Tracking Icons Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A new ForeverMap addon that covers each herb and ore tracking dot on the minimap with the kind's tracking icon in Blizzard's gold ring, stuck to its dot.

**Architecture:** A scanner probes the minimap's mouseover over a grid (soft cursor + `UpdateMouseoverAtPoint` + `C_TooltipInfo.GetMinimapMouseover`) and keeps names in ForeverMap's own node list. Pure functions group the hits into dots and convert dot positions to zone-map coordinates. A per-frame drawer places pooled icon frames from those world positions.

**Tech Stack:** Lua 5.1 WoW addon (Forever client, interface 16001), Blizzard `Settings`, `CallbackRegistryMixin`, XML templates. No libraries.

**Spec:** `docs/superpowers/specs/2026-10-26-forevermap-tracking-icons-design.md`, `docs/adr/0001-find-minimap-tracking-dots-by-probing-the-mouseover.md`

## Global Constraints

- CLAUDE.md conventions: Lua 5.1, `local ADDON_NAME, ns = ...` at the top of every file, no globals except `ForeverMapDB` and XML mixin names (all `ForeverMap`-prefixed and listed in `.luacheckrc`), every file in the TOC, `ns.log` never `print`.
- Never compare, do arithmetic on, or branch on a secret value: check `issecretvalue` on tooltip data, `data.lines`, each `leftText` and `leftColor`, and on `GetPlayerFacing()`/map positions before use.
- NodeSight (github.com/Krelock/NodeSight) has no license: no code copied from it. The algorithms below are our own.
- Icons: `professions_tracking_herb` / `professions_tracking_ore` atlases, `CircleMaskScalable` mask, ring `Interface\Minimap\MiniMap-TrackingBorder`. No custom art.
- Finder spell IDs (Blizzard's `TRACKING_SPELL_OVERRIDE_ATLAS`): Find Herbs 2383, 8387; Find Minerals 2580, 8388.
- No profession data beyond the herb/ore name list; no dependency on ForeverProfessions.
- Nothing runs in the client before 2026-11-04: every step's verification is `scripts/lint.sh` (StyLua, LuaLS against `.cache/wow-ui-source`, TOC checks), `luacheck addons template`, and, for the pure `Logic/` files, a throwaway `luajit` check script in the session scratchpad (not committed; paste its output in the task report).
- One PR for this feature. Removing ForeverProfessions' minimap pins is a separate PR, not in this plan.

## Review Focus

1. The player moves the mouse onto the minimap while a scan runs: the scan stops at once, the soft cursor is off, and the player's own hover and tooltip are untouched. (Task 5)
2. A party member, NPC or quest object ("Peacebloom 3/8") under a probe point near a node: never gets an icon. (Tasks 2, 5)
3. Two dots with the same name close together: two icons, each centered on its own dot, not one in between. (Task 3)
4. Zone change, loading screen, or a place with no map position (instances, caves): no icon left at a stale spot; map-less icons follow the scan only. (Tasks 4, 6)
5. Zooming the minimap or toggling `rotateMinimap` between scans: icons stay on their dots (positions are world-anchored and redrawn from the current view radius and facing; zoom triggers a rescan). (Tasks 4, 5, 7)

---

## File structure (addons/ForeverMap)

| File | Responsibility |
|---|---|
| `ForeverMap.toc`, `.pkgmeta`, `CHANGELOG.md` | From `scripts/new-addon.sh`, metadata filled in |
| `Core.lua` | ForeverDev shim, `ns.L`, `ns.callbacks`, `ns.OnInitialize`, loading `ForeverMapDB` |
| `Database.lua` | `ForeverMapDB` layout, `DB_VERSION`, migrations |
| `Data/Nodes.lua` | `ns.Nodes`: enUS node name → `"herb"` / `"ore"` |
| `Logic/Lines.lua` | Pure: minimap tooltip line → node names and gray flag |
| `Logic/Grid.lua` | Pure: scan grids, grouping hits, centers, splitting merged dots |
| `Logic/Anchor.lua` | Pure: minimap pixel offset ↔ zone-map position |
| `Tracking.lua` | Whether Find Herbs / Find Minerals is active |
| `Scanner.lua` | The probe loop, scan cadence, dev logs |
| `Markers.lua` | Current dots as world-anchored markers; removal on gather |
| `UI/NodeIcon.xml`, `UI/NodeIcons.lua` | Icon template; per-frame placement, look, fade |
| `Options.lua` | Options → AddOns → ForeverMap |

TOC order: `Core.lua, Database.lua, Data/Nodes.lua, Logic/Lines.lua, Logic/Grid.lua, Logic/Anchor.lua, Tracking.lua, Markers.lua, Scanner.lua, Options.lua, UI/NodeIcon.xml, UI/NodeIcons.lua`.

Coordinates used throughout: **minimap offset** `(ox, oy)` = pixels from the minimap's center in the Minimap's own units, x right, y up. **Grid key** `gx * 1000 + gy` for integer grid coords (`gx, gy >= 0`), point at `(gx * step, gy * step)` pixels from the minimap's bottom-left.

---

### Task 1: Scaffold ForeverMap with its saved settings

**Files:**
- Create (via `scripts/new-addon.sh ForeverMap`): `addons/ForeverMap/{ForeverMap.toc,.pkgmeta,CHANGELOG.md,Core.lua}`
- Create: `addons/ForeverMap/Database.lua`
- Modify: `.luacheckrc` (add `files["addons/ForeverMap/**"].globals = { "ForeverMapDB" }`; Task 7 adds the mixin)

**Interfaces:**
- Produces: `ns.dev`, `ns.log(tag, ...)`, `ns.Inert`, `ns.L` (table), `ns.callbacks` (CallbackRegistry with events `"OptionChanged"`, `"TrackingChanged"`), `ns.OnInitialize(func)`, `ns.db` (= `ForeverMapDB`), `ns.DB.Migrate(db)`; `ns.db.settings` exists after load.

- [ ] **Step 1:** Run `scripts/new-addon.sh ForeverMap`. TOC: `## Notes: Shows the herbs and ore your minimap tracking finds as icons in the minimap's gold tracking ring.`, `## IconTexture: Interface\Icons\INV_Misc_Map_01`, `## Category: Map & Minimap`; keep the template's `#@do-not-package@` ForeverDev block.
- [ ] **Step 2:** Rewrite `Core.lua` on the pattern of `addons/ForeverProfessions/Core.lua`: same shim, `ns.L = {}` (filled by Task 8), callbacks `{ "OptionChanged", "TrackingChanged" }`, `ns.OnInitialize`, and an `EventUtil.ContinueOnAddOnLoaded` that sets `ForeverMapDB = ForeverMapDB or {}`, `ns.db`, calls `ns.DB.Migrate`, runs initializers, logs `LOADED`. Header comment lists the log tags by file: `LOADED` Core.lua; `SCAN LINE MISS` Scanner.lua; `DOT` Scanner.lua.
- [ ] **Step 3:** `Database.lua` on the pattern of `addons/ForeverProfessions/Database.lua`: layout comment (`version`; `settings = { showNodeIcons = boolean, nodeIconSize = number }`, owned by Options.lua), `DB_VERSION = 1`, `migrations[1]` creates `db.settings`.
- [ ] **Step 4:** TOC file list: `Core.lua`, `Database.lua` (later tasks append in the order above).
- [ ] **Step 5:** Run `scripts/lint.sh` and `luacheck addons template`. Expected: clean.
- [ ] **Step 6:** Commit: `git add addons/ForeverMap .luacheckrc && git branch --show-current && git commit -m "feat(forevermap): scaffold addon with saved settings"`.
- [ ] **Step 7: SavedVariables gate.** Dispatch `savedvariables-guard` on this commit; fix or rule on every finding before Task 2.

### Task 2: Node list and tooltip line parsing

**Files:**
- Create: `addons/ForeverMap/Data/Nodes.lua`, `addons/ForeverMap/Logic/Lines.lua`; Modify: TOC

**Interfaces:**
- Produces: `ns.Nodes[name] -> "herb" | "ore" | nil`; `ns.Lines.Parse(text, r, g, b) -> list of { name = string, gray = boolean }` (only names in `ns.Nodes`); `ns.Lines.IsGray(r, g, b) -> boolean`.

- [ ] **Step 1:** `Data/Nodes.lua`: the 49 names of `addons/ForeverProfessions/Data/GatherNodes.lua`, `profession = "herbalism"` → `"herb"`, `"mining"` → `"ore"`; comment says it's a deliberate copy (addons stay independent; ADR 0001) and enUS only.
- [ ] **Step 2:** `Logic/Lines.lua`. `Parse` splits `text` on `\n`; per part: a leading `|cAARRGGBB` gives that part's own color (else the line's `r, g, b`), then strip `|c%x%x%x%x%x%x%x%x`, `|r`, `|T.-|t`, `strtrim` (use `text:match("^%s*(.-)%s*$")` so the file runs in luajit too); keep names found in `ns.Nodes`, deduplicated. `IsGray(r, g, b)`: `max - min < 0.06 and max < 0.9` (a launch check; nil color → false).
- [ ] **Step 3: Check with luajit** (scratchpad script that loads `Data/Nodes.lua` and `Logic/Lines.lua` with `loadfile(path)("ForeverMap", ns)`):
  - `Parse("Copper Vein", 1, 1, 1)` → `{ { name = "Copper Vein", gray = false } }`
  - `Parse("Peacebloom\nJaina", 1, 1, 1)` → only Peacebloom
  - `Parse("|cff808080Silverleaf|r", 1, 1, 1)` → Silverleaf, gray = true
  - `Parse("|TInterface\\Icons\\x:0|tMageroyal", 1, 1, 1)` → Mageroyal
  - `Parse("Peacebloom 3/8", 1, 1, 1)` → `{}` (Review Focus 2)
- [ ] **Step 4:** Lint + luacheck clean; commit `feat(forevermap): add the herb and ore names and tooltip line parsing`.

### Task 3: Grouping hits into dots

**Files:**
- Create: `addons/ForeverMap/Logic/Grid.lua`; Modify: TOC

**Interfaces:**
- Produces:
  - `ns.Grid.Points(width, step) -> list of grid keys` inside the circle of diameter `width` (the round minimap).
  - `ns.Grid.Groups(keys) -> list of lists of keys`: 8-neighbour connected components of a key set (`{ [key] = true }`).
  - `ns.Grid.FinePoints(group, coarseStep, fineStep) -> list of keys` on the fine grid covering the group's bounding box expanded by `coarseStep` pixels.
  - `ns.Grid.Dots(fineKeys, fineStep, dotArea) -> list of { x, y }`: centers in pixels from the minimap's bottom-left.
  - `ns.Grid.DotArea(fineKeys, fineStep) -> number`: pixel area of one isolated dot's hits.

- [ ] **Step 1: Implement** with this algorithm (ours, not NodeSight's): `k = max(1, floor(#fineKeys * fineStep^2 / dotArea + 0.5))`. `k == 1` → the centroid of the fine points. `k > 1` → k-means on the fine points: seed 1 = the point farthest from the centroid, each next seed = the point farthest from all seeds so far; 10 iterations of assign-to-nearest / move-to-mean; return the means.
- [ ] **Step 2: Check with luajit**, generating fine hits as all fine points within radius 6 px of given centers:
  - one dot at (40, 52), fine step 2 → `Dots(..., dotArea = π·36)` returns 1 center within 1 px of (40, 52)
  - two dots at (40, 52) and (49, 52), overlapping → 2 centers, each within 1.5 px of its dot (Review Focus 3)
  - `Groups` on two far-apart dots → 2 groups; on a diagonal-touching pair → 1 group
  - `Points(140, 8)` contains no key whose point lies outside radius 70 of (70, 70)
- [ ] **Step 3:** Lint + luacheck clean; commit `feat(forevermap): group minimap probe hits into dots`.

### Task 4: Minimap offset ↔ map position

**Files:**
- Create: `addons/ForeverMap/Logic/Anchor.lua`; Modify: TOC

**Interfaces:**
- Produces: a **view** table `{ px, py, width, height, pixelsPerYard, facing }` (player's normalized map position, map size in yards, minimap pixels per yard, facing in radians or 0 when the minimap doesn't rotate);
  `ns.Anchor.ToMap(ox, oy, view) -> mapX, mapY`; `ns.Anchor.ToMinimap(mapX, mapY, view) -> ox, oy`.

- [ ] **Step 1: Implement.** `ToMinimap` is the math of `addons/ForeverProfessions/UI/MinimapPins.lua` `Draw` (yards east `dx = (mapX - px) * width`, north `dy = (py - mapY) * height`, rotated clockwise by facing, times pixels per yard); `ToMap` is its exact inverse.
- [ ] **Step 2: Check with luajit:** for facing 0, 1.2 and -2.5 and offsets (0, 0), (30, -12), (-55, 41): `ToMinimap(ToMap(ox, oy, v), v)` returns `ox, oy` within 1e-9; with facing 0, `ToMap(10, 0, v)` lies east of the player (`mapX > px`, `mapY == py`) and `ToMap(0, 10, v)` north (`mapY < py`). (Review Focus 5)
- [ ] **Step 3:** Lint + luacheck clean; commit `feat(forevermap): convert between minimap offsets and map positions`.

### Task 5: Tracking state and the scanner

**Files:**
- Create: `addons/ForeverMap/Tracking.lua`, `addons/ForeverMap/Scanner.lua`; Modify: TOC

**Interfaces:**
- Consumes: Tasks 1–4; `ns.Markers.Replace(dots, view)` and `ns.Markers.RemoveNearPlayer(yards, pixelsPerYard)` from Task 6 (called at run time, so the TOC order above works).
- Produces: `ns.Tracking.IsFinding() -> boolean`, firing `ns.callbacks` `"TrackingChanged"` on `MINIMAP_UPDATE_TRACKING`; `ns.Scanner.ScanSoon()`; `ns.Scanner.CurrentView() -> view | nil` (nil where the client has no map position); dots passed to Markers are `{ name, kind, gray, ox, oy }`.

- [ ] **Step 1: `Tracking.lua`.** `IsFinding` walks `C_Minimap.GetTrackingInfo(1..GetNumTrackingTypes())` for an `active` entry whose `spellID` is 2383, 8387, 2580 or 8388 (secret-checked; secret → false).
- [ ] **Step 2: `Scanner.lua`** on an `OnUpdate` frame. Values: `STEP = 8`, `FINE = 2`, `PER_FRAME = 60` probes, `INTERVAL = 0.5` s while moving, `1.5` s standing still, doubling after each empty scan up to `3` s. Initial `dotArea = math.pi * 6^2`, then the running average of `ns.Grid.DotArea` over groups that came out as one dot, clamped to `[π·3², π·15²]`.
  - A scan: coarse pass over `ns.Grid.Points(Minimap:GetWidth(), STEP)`, `PER_FRAME` per frame, then per group of hits a fine pass over `ns.Grid.FinePoints`, then `ns.Grid.Dots`; on finish call `ns.Markers.Replace(dots, view)` with the view captured when the scan started.
  - A probe: `Minimap:SetUsingSoftCursor(true)` once per frame before the batch, `Minimap:UpdateMouseoverAtPoint((Minimap:GetLeft() + x) * scale, (Minimap:GetBottom() + y) * scale)` with `scale = Minimap:GetEffectiveScale()`, `C_TooltipInfo.GetMinimapMouseover()`, `ns.Lines.Parse` per line; `SetUsingSoftCursor(false)` after the batch, every frame, before returning.
  - Abort the running scan (and start none) while `Minimap:IsMouseOver()`, `not Minimap:IsVisible()`, `not ns.Tracking.IsFinding()`, or `showNodeIcons` is off; in the last three cases also `ns.Markers.Replace({}, nil)`. (Review Focus 1) Combat is not a reason to stop: scanning continues in combat (spec).
  - Rescan at once on `LOOT_CLOSED` (after `ns.Markers.RemoveNearPlayer(5, pixelsPerYard)`), `MINIMAP_UPDATE_ZOOM`, `"TrackingChanged"`, `"OptionChanged"`; clear markers on `PLAYER_ENTERING_WORLD` and `ZONE_CHANGED_NEW_AREA`. (Review Focus 4, 5)
  - Dev logs (work inside `if ns.dev.enabled`): `LINE` raw line text and color via `ns.dev:LogOnce(text, ...)`; `MISS` names under a probe that aren't in `ns.Nodes` while finding, `LogOnce` per name; `SCAN` per scan: probes, groups, dots, milliseconds (`debugprofilestop`); `DOT` per new dot: center and fine area.
- [ ] **Step 3:** Verify every call above in `.cache/wow-ui-source` (signatures, `SecretArguments`, events) before first use. Lint + luacheck clean; commit `feat(forevermap): scan the minimap for tracked herb and ore dots`.

### Task 6: Markers

**Files:**
- Create: `addons/ForeverMap/Markers.lua`; Modify: TOC

**Interfaces:**
- Consumes: `ns.Anchor`, `ns.Scanner.CurrentView()`.
- Produces: `ns.Markers.Replace(dots, view)`; `ns.Markers.RemoveNearPlayer(yards, pixelsPerYard)`; `ns.Markers.Enumerate() -> ipairs over { kind, gray, mapID, mapX, mapY }` or, without a view, `{ kind, gray, ox, oy }`.

- [ ] **Step 1: Implement.** `Replace` converts each dot with `ns.Anchor.ToMap` (minimap offset = dot center minus half the minimap width) and stores the scan's `mapID`; with `view == nil` it keeps the offsets as they are (map-less places). `RemoveNearPlayer(yards, pixelsPerYard)` removes the one marker nearest the player within `yards`: for map markers, measure with the current view (`ns.Scanner.CurrentView()`, yards from map size); for offset markers, the offset's length divided by `pixelsPerYard`. The scanner passes `pixelsPerYard = Minimap:GetWidth() / (2 * C_Minimap.GetViewRadius())`, which needs no map.
- [ ] **Step 2:** Lint + luacheck clean; commit `feat(forevermap): keep found dots anchored to the world`.

### Task 7: Icons on the minimap

**Files:**
- Create: `addons/ForeverMap/UI/NodeIcon.xml`, `addons/ForeverMap/UI/NodeIcons.lua`; Modify: TOC, `.luacheckrc` (add `ForeverMapNodeIconMixin`)

**Interfaces:**
- Consumes: `ns.Markers.Enumerate()`, `ns.Scanner.CurrentView()`, `ns.Anchor.ToMinimap`, `ns.db.settings.nodeIconSize`.

- [ ] **Step 1: `NodeIcon.xml`:** `ForeverMapNodeIconTemplate`, a mouse-disabled Frame with `Icon` (ARTWORK), a `MaskTexture` using atlas `CircleMaskScalable` (`hWrapMode`/`vWrapMode` `CLAMPTOBLACKADDITIVE`, as Blizzard_PVPUI.xml) masking `Icon`, and `Ring` (OVERLAY, `Interface\Minimap\MiniMap-TrackingBorder`).
- [ ] **Step 2: `NodeIcons.lua`:** a container frame child of `Minimap` (`SetAllPoints`), an unsecured frame pool, an `OnUpdate` that each frame (only while markers exist) places one icon per marker at `ns.Anchor.ToMinimap` with the current view (offset markers at their offsets). `SetNodeIcon(kind, gray, size)` on the mixin: icon `size`×`size`, atlas by kind; ring `2.5 × size` square, its center at the icon's center plus `(12/64, -13/64) × ringSize` (Blizzard_HelpPlate.xml places this ring the same way); gray → icon and ring desaturated, vertex color 0.6. Not drawn when its center is farther than `Minimap:GetWidth() / 2 - 0.75 * size` from the center; alpha `0.35` when within `size` pixels of the center (the player arrow), else 1.
- [ ] **Step 3:** Lint + luacheck clean; commit `feat(forevermap): draw tracked nodes as icons in the gold tracking ring`.

### Task 8: Options and changelog

**Files:**
- Create: `addons/ForeverMap/Options.lua`; Modify: TOC, `addons/ForeverMap/CHANGELOG.md`, `Core.lua` (`ns.L` strings)

- [ ] **Step 1:** `Options.lua` on the pattern of `addons/ForeverProfessions/Options.lua` (`Settings.RegisterVerticalLayoutCategory(ADDON_NAME)`, `Settings.RegisterAddOnSetting` into `ns.db.settings`, variables `FOREVERMAP_<KEY>`, value changes fire `"OptionChanged"`): checkbox `showNodeIcons` (default true) "Show icons on tracked nodes", tooltip "Show the herbs and ore your tracking finds as icons on the minimap."; slider `nodeIconSize` via `Settings.CreateSliderOptions(6, 16, 1)` and `Settings.CreateSlider`, default `9`, "Icon size", tooltip "Size of the node icons on the minimap. Larger icons can cover the arrows that show a node above or below you." Strings go in `ns.L`.
- [ ] **Step 2:** CHANGELOG `## Unreleased`: replace the template line with players' lines: herbs and ore found by Find Herbs / Find Minerals show as their tracking icon in the minimap's gold ring; icons disappear when you gather the node; icon size and on/off under Options → AddOns → ForeverMap.
- [ ] **Step 3:** Lint + luacheck clean; commit `feat(forevermap): add options for the node icons`.

---

## Step reviewers (Phase 5)

Core: `addon-reviewer`, `api-verifier`, correctness reviewer, spec reviewer. Specialists: `savedvariables-guard` (new SavedVariables and settings keys), UI reviewer (template, mask, ring placement, layering on the Minimap), release reviewer (new TOC and `.pkgmeta`).

## Launch checks (Phase 6 → memory `forevermap-launch-checks`)

| Check | Evidence |
|---|---|
| Probing names tracked nodes | `SCAN` lines with dots > 0 while tracking near nodes |
| Node lines carry a texture escape (could replace the name list) | `LINE` raw texts |
| Gray = node in a cave | `LINE` colors near a cave node vs. outside |
| The list misses nodes | `MISS` names |
| Dot size and default icon size clear the up/down arrows | `DOT` areas + a screenshot like the user's |
| Icons stay centered and stick while riding and turning (rotate on/off) | screenshot / user report |
| Hovering the minimap still shows the normal tooltip | user report |
| Scan cost | `SCAN` milliseconds in a node-dense zone |
