# ForeverMap Button Bag Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Gather every addon's minimap button behind one draggable button on ForeverMap's minimap ring, folding out in a player-chosen direction, with a per-button "keep on minimap" list.

**Architecture:** Pure math and name rules in `Logic/` (ring position, strip slots, frame-name rules), a bag button (`UI/BagButton.*`) styled from the zoom buttons' atlases, and a collector (`ButtonBag.lua`) that finds addon buttons, reparents them into a strip container and puts them back. Settings live in ForeverMap's existing category, plus a MenuUtil checkbox menu for the ignore list.

**Tech Stack:** Lua 5.1, Forever client (interface 16001, Midnight 12.x API), Blizzard `Settings`, `MenuUtil`, `hooksecurefunc`, optional LibDBIcon (only if another addon loaded it; we ship no library).

**Spec:** `docs/superpowers/specs/2026-11-03-forevermap-button-bag-design.md`

## Global Constraints

- Never touch a Blizzard frame: not reparent, re-anchor, hide or hook it. When unsure whether a frame is Blizzard's, leave it alone.
- Never collect map pins (HandyNotes, GatherMate2, TomTom, HereBeDragons-Pins, ForeverMap's own node icons).
- No replacing anyone's functions or scripts: `hooksecurefunc` / `HookScript` only. Skip protected frames (`frame:IsProtected()`).
- Blizzard atlases only, no custom art. Our button: `ui-hud-minimap-button` normal / `-button-down` pushed, the same art additive at 0.3 alpha as highlight, 17×17 (amended in review: the zoom-in atlas has its "+" baked in).
- Our button is draggable around the ring only, never detached.
- Lua 5.1; every file starts `local ADDON_NAME, ns = ...`; no new globals except a mixin named in XML (add it to `.luacheckrc`); every file listed in `ForeverMap.toc`.
- `ns.log`, never `print`. Dev-only work goes inside `if ns.dev.enabled then`.
- Untested in game until launch (4 November 2026). Lint (`scripts/lint.sh`) plus reading is the only check. **This machine lacks StyLua and LuaLS, so lint runs in CI;** install them (`cargo install stylua`, LuaLS release zip) if you can, otherwise say lint was not run locally.

## Review Focus

1. **LibDBIcon re-anchors a collected button** (its own refresh, minimap shape change, `/rl`): the button must stay in the strip. Owned by Task 4 (the `SetPoint`/`SetParent` hooks); launch check `BAG reanchor`.
2. **An addon hides or shows its button while it's collected:** a hidden one leaves no gap in the strip and stays hidden after release; a newly shown one appears. Task 4 (Show/Hide hooks → relayout).
3. **A load-on-demand addon creates its button after login:** it gets collected without a `/rl`. Task 4 (`ADDON_LOADED` rescan, LibDBIcon `LibDBIcon_IconCreated`).
4. **Turning the bag off, or ignoring a button,** returns it to exactly where its addon had it, on the ring, with drag working. Task 4 (`Release`).
5. **A Blizzard frame or a pin is misclassified** as an addon button. Task 2 (name rules) and Task 4 (every candidate logged with its verdict: `BAG collect` / `BAG skip <reason>`).

## Step reviewers (Phase 5)

Core: `addon-reviewer`, `api-verifier`, correctness and spec reviewers. Specialists: `savedvariables-guard` (DB v2, new settings keys) and a **UI reviewer** (zoom-button atlases, ring anchoring and layering, the menu, nothing Blizzard touched). One PR: the probe, design, plan and Tasks 1–6 together, at the user's request.

---

### Task 1: Saved layout and settings

**Files:**
- Modify: `addons/ForeverMap/Database.lua` (layout comment, `DB_VERSION = 2`, migration `[2]`)
- Modify: `addons/ForeverMap/Options.lua` (`DEFAULTS`, two registered settings)
- Modify: `addons/ForeverMap/Core.lua` (`ns.L` strings)

**Interfaces:**
- Produces: `ForeverMapDB.buttonBag = { angle = number|nil, ignored = { [key: string] = true } }`, created by migration 2. `ns.Options.Get("showButtonBag") -> boolean` (default `true`), `ns.Options.Get("buttonBagDirection") -> number` (default `ns.Options.DIRECTION.DOWN`). `ns.Options.DIRECTION = { DOWN = 1, UP = 2, LEFT = 3, RIGHT = 4 }`. Changing either fires `OptionChanged` (existing).

- [ ] **Step 1:** Bump `DB_VERSION` to 2; migration `[2]` sets `db.buttonBag = db.buttonBag or {}` and `db.buttonBag.ignored = db.buttonBag.ignored or {}`. A nil `angle` means "use the default"; don't write it. Update the layout comment.
- [ ] **Step 2:** Register `showButtonBag` (checkbox) and `buttonBagDirection` (dropdown via `Settings.CreateDropdown` with `Settings.CreateControlTextContainer`, the four directions) in the existing `ns.OnInitialize` block, below the node icon settings. The direction dropdown is a child of the checkbox (`SetParentInitializer`, as the size slider does). Strings in `ns.L`: `SHOW_BUTTON_BAG = "Gather addon minimap buttons"`, its tooltip, `BUTTON_BAG_DIRECTION = "Open buttons towards"`, `DIRECTION_DOWN/UP/LEFT/RIGHT = "Down"/"Up"/"Left"/"Right"`.
- [ ] **Step 3:** Run `scripts/lint.sh`. Expected: clean (or not runnable here, see constraints).
- [ ] **Step 4:** Commit `feat(forevermap): store button bag settings`.
- [ ] **Step 5: SavedVariables gate.** Dispatch `savedvariables-guard` on this commit and rule on every finding before Task 3 builds on the layout.

### Task 2: Pure logic: ring, strip, name rules

**Files:**
- Create: `addons/ForeverMap/Logic/Ring.lua`, `addons/ForeverMap/Logic/Strip.lua`, `addons/ForeverMap/Logic/ButtonRules.lua`
- Modify: `addons/ForeverMap/ForeverMap.toc` (after `Logic/Anchor.lua`)

**Interfaces:**
- Produces:
  - `ns.Ring.Offset(angle: number, radius: number, shape: string) -> x, y`. Angle is degrees counter-clockwise from east, the convention LibDBIcon uses for `minimapPos`. The offset is from the minimap's center. `shape` is a `GetMinimapShape()` value (`"ROUND"` default, `"SQUARE"`, `"CORNER-*"`, `"SIDE-*"`, `"TRICORNER-*"`). Port LibDBIcon's quadrant table: a square quadrant clamps to the box edge (`math.max(-radius, math.min(x * diag, radius))` with `diag = sqrt(2 * radius^2) - 10`).
  - `ns.Ring.AngleTo(x: number, y: number) -> number`. Degrees, 0–360, of the point (x, y) relative to the center. Use `math.atan2`.
  - `ns.Ring.DEFAULT_ANGLE = 225` (bottom-left).
  - `ns.Strip.Offset(index: number, direction: number, perLine: number, size: number, gap: number) -> x, y`. The slot offset of the 1-based `index` from our button's center. Slot 1 sits one step away from our button in `direction`. Lines grow along the direction and wrap after `perLine`. Wrapped lines stack perpendicular, to the right for DOWN/UP and downward for LEFT/RIGHT. `ns.Strip.PER_LINE = 6`.
  - `ns.ButtonRules.Verdict(name: string|nil) -> "ok" | reason: string`. Reasons: `"anonymous"` (nil name), `"blizzard"` (name in `BLIZZARD_NAMES` or matching `^Minimap`, `^MiniMap`, `^GameTime`, `^Queue`, `^GarrisonLandingPage`, `^ExpansionLandingPage`, `^AddonCompartment`, `^TimeManager`), `"pin"` (matches `^HandyNotes`, `^GatherMate`, `^TomTom`, `^HereBeDragons`, `^Questie`, `^ForeverMap`, `^ForeverProfessions`, or ends in digits, `%d+$`, as numbered pin frames do; added in review). `BLIZZARD_NAMES` lists every name in `Blizzard_Minimap/Mainline/Minimap.xml` and `Camelot/*.xml` (`MinimapCluster`, `Minimap`, `MinimapBackdrop`, `MinimapCompassTexture`, `MinimapCompassTextureUnderlay`, `ExpansionLandingPageMinimapButton`, `GameTimeFrame`, `AddonCompartmentFrame`, ...). Grep those files and copy every `name="..."`.
  - LibDBIcon buttons are named `LibDBIcon10_<object>`. `Verdict` returns `"ok"` for them before the other rules.

- [ ] **Step 1:** Write the three files as pure functions (no client API apart from `math`), each with a header comment like `Logic/Anchor.lua`'s explaining the coordinate conventions.
- [ ] **Step 2: Read-check by hand** and write the results into the commit body: `Ring.Offset(0, 80, "ROUND") ≈ (80, 0)`, `Ring.Offset(90, 80, "ROUND") ≈ (0, 80)`, `Ring.AngleTo(0, -1) == 270`, `Strip.Offset(1, DOWN, 6, 24, 2) == (0, -26)`, `Strip.Offset(7, DOWN, 6, 24, 2) == (26, -26)`, `Verdict("LibDBIcon10_Details") == "ok"`, `Verdict("MinimapZoomIn") == "blizzard"`, `Verdict("HandyNotesPin12") == "pin"`, `Verdict(nil) == "anonymous"`.
- [ ] **Step 3:** Lint; commit `feat(forevermap): add ring, strip and button rules logic`.

### Task 3: The bag button

**Files:**
- Create: `addons/ForeverMap/UI/BagButton.xml`, `addons/ForeverMap/UI/BagButton.lua`
- Modify: `ForeverMap.toc`, `.luacheckrc` (`ForeverMapBagButtonMixin`), `Core.lua` (`ns.L` strings, a new callback event `BagToggled`)

**Interfaces:**
- Consumes: `ns.Ring.*` (Task 2), `ns.db.buttonBag.angle` (Task 1), `ns.Options.Get("showButtonBag")`.
- Produces: `ns.BagButton` (the frame), `ns.BagButton:IsOpen() -> boolean`, `ns.BagButton:SetOpen(open: boolean)` (fires `ns.callbacks` `BagToggled(open)`), and `ns.BagButton.OnRightClick: function|nil`, which Task 5 sets to open the ignore menu.

- [ ] **Step 1:** In XML, define a 17×17 `Button` parented to `Minimap`, with mixin `ForeverMapBagButtonMixin` and the button atlases above as Normal/Pushed/Highlight. Add an `OVERLAY` texture `Icon` (about 11×11, centered) and a `frameLevel` above Minimap's border.
- [ ] **Step 2: Icon by runtime fallback.** `local ICON_ATLASES = { "uitools-icon-hamburger", "common-icon-hamburger", "friends-icon-menu", "OptionsIcon-Brown" }`. Use the first one for which `C_Texture.GetAtlasInfo` returns info, and log the choice with `ns.dev:LogOnce("icon", "BAG", "icon", atlas)`. If none exists, hide the icon. Keep this list in step with the `ATLAS` probe in `addons/ForeverDev/Probes.lua` and reorder it once launch shows which looks right.
- [ ] **Step 3: Ring drag.** `RegisterForDrag("LeftButton")`. While dragging, an `OnUpdate` computes the cursor's offset from `Minimap:GetCenter()` (both divided by effective scale) and sets `angle = ns.Ring.AngleTo`. Position with `SetPoint("CENTER", Minimap, "CENTER", ns.Ring.Offset(angle, Minimap:GetWidth() / 2 + 5, GetMinimapShape and GetMinimapShape() or "ROUND"))`. On drag stop, save `ns.db.buttonBag.angle`.
- [ ] **Step 4: Clicks and tooltip.** `RegisterForClicks("LeftButtonUp", "RightButtonUp")`. Left toggles `SetOpen`; right calls `OnRightClick`. The tooltip uses `GameTooltip_SetTitle(tooltip, ADDON_NAME)` plus two hint lines from `ns.L` (`BAG_TOOLTIP_TOGGLE`, `BAG_TOOLTIP_KEEP`). The button is shown only while `showButtonBag` is true, and `OptionChanged` re-checks that.
- [ ] **Step 5:** Lint; commit `feat(forevermap): add the minimap button bag button`.

### Task 4: The collector

**Files:**
- Create: `addons/ForeverMap/ButtonBag.lua`
- Modify: `ForeverMap.toc`, `Core.lua` (shim comment: `BAG` tag)

**Interfaces:**
- Consumes: `ns.ButtonRules.Verdict`, `ns.Strip.Offset`, `ns.BagButton`, `ns.db.buttonBag.ignored`, `ns.Options.Get("showButtonBag"|"buttonBagDirection")`, the `OptionChanged` and `BagToggled` callbacks.
- Produces: `ns.ButtonBag.Found() -> { { key: string, label: string, frame: Frame } }` sorted by label, `ns.ButtonBag.SetIgnored(key: string, ignored: boolean)`. The key is the frame name. The label is the LibDBIcon object name, else the creating addon's title from `issecurevariable(_G, name)` → `C_AddOns.GetAddOnTitle`, else the frame name.

- [ ] **Step 1: Strip container.** An anonymous `Frame` anchored to `ns.BagButton`, shown only while the bag is open. Collected buttons are reparented into it, so their own `Show`/`Hide` state is untouched and closing the bag hides them through the parent.
- [ ] **Step 2: Discovery.** `Scan()` walks the named children of `Minimap`, `MinimapBackdrop` and `MinimapCluster`. A candidate needs all of these:
  - `Verdict(name) == "ok"`;
  - `_G[name] == frame`;
  - not `IsForbidden()` and not `IsProtected()`;
  - a `Button` with an `OnClick` script (narrowed in review, with a ring-distance band and a HereBeDragons-pin check, so map pins aren't taken);
  - if `issecurevariable` exists, not secure (secure means Blizzard).

  LibDBIcon buttons qualify directly, via `LibStub("LibDBIcon-1.0", true)` and `GetButtonList()`. `Scan()` runs on `PLAYER_LOGIN` + `C_Timer.After(2)`, on `ADDON_LOADED` (debounced to the next frame) and on LibDBIcon's `LibDBIcon_IconCreated` callback (`lib.RegisterCallback(ns.ButtonBag, "LibDBIcon_IconCreated", ...)`). Log each frame once with `ns.dev:LogOnce(name, "BAG", "collect"|"skip", reason, name)`.
- [ ] **Step 3: Collect(frame).**
  - Save the frame's parent, every `GetPoint(i)`, frame strata and level.
  - Reparent it into the container.
  - For LibDBIcon buttons, clear drag (`RegisterForDrag()`); for others, `HookScript("OnDragStop", Layout)`.
  - Hook once per frame (a `hooked[frame]` set):
    - `hooksecurefunc(frame, "SetPoint", ...)` and `"SetParent"`: when the frame is collected and the call isn't ours (a `layingOut` flag), call `Layout` on the next frame.
    - `hooksecurefunc(frame, "Show"/"Hide"/"SetShown", Layout)`.
- [ ] **Step 4: Layout().** Lay out the collected frames that report `IsShown()`, sorted by label, at `ns.Strip.Offset(i, direction, ns.Strip.PER_LINE, 24, 2)`, at 24×24 *(scale the frame instead if it isn't that size)*. Set `layingOut` around the work.
- [ ] **Step 5: Release(frame).** Restore the saved parent, points, strata and level, and re-register drag `"LeftButton"` for LibDBIcon buttons. It runs when the bag is turned off (all frames), when a frame is ignored, and is a no-op for frames not collected. Ignoring and un-ignoring take effect immediately via `SetIgnored`.
- [ ] **Step 6:** `if ns.dev.enabled then` log `BAG reanchor <name>` whenever a hook catches a foreign re-anchor (Review Focus 1).
- [ ] **Step 7:** Lint; commit `feat(forevermap): collect addon minimap buttons into the bag`.

### Task 5: Ignore menu and options entry

**Files:**
- Modify: `addons/ForeverMap/ButtonBag.lua` (or a new `ButtonBagMenu.lua` if it grows past ~60 lines), `Options.lua`, `Core.lua` (`ns.L`)

**Interfaces:**
- Consumes: `ns.ButtonBag.Found`, `ns.ButtonBag.SetIgnored`, `ns.BagButton.OnRightClick`.
- Produces: `ns.ButtonBag.OpenIgnoreMenu(owner: Region)`.

- [ ] **Step 1:** `OpenIgnoreMenu` uses `MenuUtil.CreateContextMenu(owner, function(_, root) ... end)`. The title is `ns.L.KEEP_ON_MINIMAP` ("Keep on minimap"), followed by one `root:CreateCheckbox(label, isSelected, toggle, key)` per entry of `Found()`, including hidden ones. If nothing is found, show a disabled line `ns.L.NO_BUTTONS_FOUND`.
- [ ] **Step 2:** Set `ns.BagButton.OnRightClick = function(button) ns.ButtonBag.OpenIgnoreMenu(button) end`. In `Options.lua`, add `CreateSettingsButtonInitializer(L.KEEP_ON_MINIMAP, L.CHOOSE_BUTTONS, function() ... OpenIgnoreMenu(...) end, L.KEEP_ON_MINIMAP_TOOLTIP, true)` as a child of the `showButtonBag` checkbox, then `layout:AddInitializer` it. *(This replaces the spec's inline checkbox list: a vertical Settings category can't grow a row per button found at runtime, so the panel opens the same checkbox menu. Flag this in the PR.)*
- [ ] **Step 3:** Lint; commit `feat(forevermap): choose which buttons stay on the minimap`.

### Task 6: Player-facing text

**Files:**
- Modify: `addons/ForeverMap/CHANGELOG.md` (`## Unreleased`), `ForeverMap.toc` (`## Notes`)

- [ ] **Step 1:** Add changelog lines for players covering:
  - addon buttons gathered behind one button on the ring;
  - drag it around the ring;
  - choose which way it opens;
  - right-click (or Options) to keep chosen buttons on the minimap;
  - turn it off in Options.
- [ ] **Step 2:** Extend `## Notes` to mention the button bag. Lint; commit `docs(forevermap): describe the button bag for players`.

## Launch checks (record as memory `forevermap-launch-checks` in Phase 6)

| Assumption | How it shows | If wrong, change |
|---|---|---|
| A three-lines atlas exists | `ATLAS` probe lines; `BAG icon <atlas>` | `ICON_ATLASES` in `UI/BagButton.lua` |
| `issecurevariable` exists and names the creating addon | `MINIMAP issecurevariable function`, `creator tainted:<Addon>` | the secure check in `ButtonBag.lua` Scan |
| No Blizzard frame or pin is collected | `BAG collect` lines vs. the `MINIMAP` census | `ButtonRules.lua` |
| LibDBIcon buttons stay in the strip | no stray buttons on the ring after `/rl`; `BAG reanchor` lines | `ButtonBag.lua` hooks |
| Ring radius and button size line up with the zoom buttons | screenshot | `Minimap:GetWidth() / 2 + 5`, the 17×17 size |
