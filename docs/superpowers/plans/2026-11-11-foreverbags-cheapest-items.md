# ForeverBags Cheapest Items Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A new addon, ForeverBags, that lists the cheapest bag stacks by vendor price when looting fails on full bags (or from a bag-frame button), deletes the one the player clicks, and loots again.

**Architecture:** Pure logic (which stacks qualify, sorting) lives in `Items.lua`, apart from frames and events. `Delete.lua` owns the one protected action and runs only inside the player's click. `Window.lua`/`Window.xml` is a `ScrollingFlatPanelTemplate` frame (the loot window's own template) with one owner, `"loot"` or `"hand"`. `Loot.lua` drives automatic opening and the re-loot; `BagButton.lua` drives opening by hand.

**Tech Stack:** Lua 5.1 on the Forever client (interface 16001), Blizzard templates only, no libraries. There is no test framework: pure logic is checked by reading, the rest by `scripts/lint.sh` and in game.

**Spec:** `docs/superpowers/specs/2026-11-11-foreverbags-cheapest-items-design.md`

## Global Constraints

- PR title: `feat(foreverbags): list the cheapest bag items when bags are full`.
- The original addon (`DeleteCheapestItem`, All Rights Reserved) is **not** to be copied. Do not open its files while implementing.
- Non-goals, verbatim from the spec: no auction prices, no selling, no other automatic opening, no quality/soulbound filters, no slash command, no dragging or saved position, no localisation files.
- No addon name anywhere in the window. Title is `ERR_INV_FULL` with a trailing `.` removed.
- Hook only: `hooksecurefunc`, `HookScript`, `EventRegistry`. Never assign to a Blizzard function or frame field.
- `DeleteCursorItem` (`HasRestrictions = true`) is called only from an `OnClick` handler or a popup's `OnAccept`, never from an event or timer.
- TOC: `## Interface: 16001`, `## Category: Forever Enhanced Addons`, `## X-Category: Bags & Inventory`, `## X-Credits: Idea from DeleteCheapestItem by <Night Shift> Suey and its maintainers`.
- Globals allowed: `ForeverBagsDB`, `ForeverBagsWindow`, `ForeverBagsRowMixin`, `ForeverBagsRowTemplate` (XML). All go in `.luacheckrc`.
- `ns.log`, never `print`. Work done only to feed a log line goes inside `if ns.dev.enabled then`.
- Undocumented globals used (`LootSlot`, `GetNumLootItems`, `GetLootSlotInfo`) get annotations in `types/forever.lua`, citing `Blizzard_UIPanels_Game/Mainline/LootFrame.lua:84,227,228`.
- Seam reference (verified in `.cache/wow-ui-source`, build 1.60.1.70862):
  - `ScrollingFlatPanelMixin` (`Blizzard_UIPanels_Game/Mainline/ScrollingFlatPanel.lua`): `OnLoad` calls `SetTitle(self.panelTitle)` during `CreateFrame`, so call `frame:SetTitle(...)` afterwards; `Resize()` reads `panelWidth` and `panelMaxHeight` and needs a ScrollBox view; `CalculateElementsHeight()` must be implemented; `OnHideAnimFinished()` calls `HideUIPanel` and must be replaced on our frame with one that calls `self:Hide()`.
  - `LootFrame.lua:62-125` is the ScrollBox setup to mirror (`CreateScrollBoxListLinearView`, `ScrollUtil.InitScrollBoxWithScrollBar`, `ScrollUtil.CalculateScrollBoxElementExtent`); `LootFrame.xml:116` has `panelWidth=220`, `panelMaxHeight=290`.
  - `C_Container.GetContainerItemInfo` fields: `iconFileID, stackCount, isLocked, quality, hyperlink, hasNoValue, itemID, itemName`. `C_Container.GetContainerItemQuestInfo` → `{isQuestItem, questID, isActive}`. `C_Item.GetItemInfo` return 11 is `sellPrice`. None are flagged secret.
  - `GetMoneyString(money)` in `Blizzard_SharedXML/FormattingUtil.lua:72`. `ColorManager.GetColorDataForItemQuality(q)` as in `LootFrame.lua:489`.
  - Blizzard's delete dialogs: `DELETE_GOOD_ITEM` in `Blizzard_StaticPopup_Game/Mainline/GameDialogDefs.lua:572-650` (typed confirmation via `StaticPopup_StandardConfirmationTextHandler(editBox, DELETE_ITEM_CONFIRM_STRING)`).
  - Bag frames: `BagItemAutoSortButton` is 28x26 at `TOPRIGHT -9,-34` of the bag frame (`ContainerFrame.lua:1122-1146`); `ContainerFrameSettingsManager:IsUsingCombinedBags()`; `EventRegistry` `"ContainerFrame.OpenBag"` / `"ContainerFrame.CloseBag"`.
  - Settings: `CreateSettingsButtonInitializer(name, buttonText, onClick, tooltip, addSearchTags)` asserts `addSearchTags ~= nil` (`Blizzard_SettingControls.lua:1040`).

## Review Focus

1. **A stale row deletes the wrong item.** The bag changes between drawing a row and clicking it (a stack merges, an item moves). Expected: `ns.Delete.Matches` re-reads the slot at the click and again at popup accept; a mismatch deletes nothing and refreshes (Task 3).
2. **The cursor already holds something**, or ends up holding the wrong item after pickup. Expected: nothing is deleted and `ClearCursor()` runs only for an item we picked up ourselves (Task 3).
3. **Item data not loaded.** `C_Item.GetItemInfo` returns nil for an uncached item. Expected: the stack is skipped this pass, never treated as price 0 or listed, and the list refreshes on `GET_ITEM_INFO_RECEIVED` (Tasks 2 and 4).
4. **Window owner mix-ups.** A hand-opened window must survive `LOOT_CLOSED`; an auto-opened one must not reopen after the player closes it during the same loot; Escape hides without the close callback. Expected: all state resets in the frame's `OnHide`, whichever way it was hidden (Tasks 4 and 5).
5. **Re-loot runs away.** `BAG_UPDATE_DELAYED` fires for many reasons. Expected: the re-loot runs once, only when a delete armed it and the loot window is still open, and is disarmed on `LOOT_CLOSED` (Task 5).

---

### Task 1: Scaffold the addon and its database

**Files:**
- Create (via `scripts/new-addon.sh ForeverBags`, then edit): `addons/ForeverBags/ForeverBags.toc`, `Core.lua`, `.pkgmeta`, `CHANGELOG.md`
- Create: `addons/ForeverBags/Database.lua`
- Modify: `.luacheckrc` (add `files["addons/ForeverBags/**"].globals`)

**Interfaces:**
- Produces:
  - `ns.OnInitialize(func)`: runs `func` after the DB is ready (pattern from `addons/ForeverTooltip/Core.lua:41-56`).
  - `ns.DB.Migrate(db)`, `DB_VERSION = 1` (pattern from `addons/ForeverTooltip/Database.lua`).
  - `ns.DB.IsIgnored(itemID) -> boolean`, `ns.DB.Ignore(itemID)`, `ns.DB.ResetIgnored()`.
  - `ns.L`: table of our English strings (`EMPTY`, `IGNORE_HINT`, `BUTTON_TOOLTIP`, `RESET_IGNORED`, `RESET_IGNORED_TOOLTIP`).

- [ ] **Step 1:** Run `scripts/new-addon.sh ForeverBags`. Edit the TOC per Global Constraints; Notes: `Lists your cheapest bag items when your inventory is full, so you can delete one and keep looting.` List `Core.lua`, `Database.lua`.
- [ ] **Step 2:** `Core.lua`: keep the template shim, add `ns.OnInitialize`, `ns.L`, and the tags comment: `LOADED` (Core.lua), `SCAN` (Items.lua), `DELETE` (Delete.lua), `FULL` `RELOOT` (Loot.lua), `WINDOW` (Window.lua).
- [ ] **Step 3:** `Database.lua`. Layout, documented in a header comment:
  `ForeverBagsDB = { version = 1, characters = { [playerGUID] = { ignored = { [itemID] = true } } } }`.
  Account-wide table (the repo has no per-character SavedVariables), keyed per character. The character entry is resolved lazily on first use with `UnitGUID("player")` (check its docs entry for secret flags first; never call it before `PLAYER_LOGIN`).
- [ ] **Step 4:** `scripts/lint.sh`. Expected: clean.
- [ ] **Step 5:** Commit `feat(foreverbags): scaffold the addon and its ignore list storage`.
- [ ] **Step 6 (gate):** Dispatch `savedvariables-guard` on this commit. Fix or rule on every finding before Task 2.

### Task 2: Find and sort the cheapest stacks

**Files:**
- Create: `addons/ForeverBags/Items.lua` (add to TOC)

**Interfaces:**
- Consumes: `ns.DB.IsIgnored`.
- Produces:
  - Entry: `{ bag, slot, itemID, link, name, count, quality, icon, value }` (`value` = sellPrice × count, copper).
  - `ns.Items.Qualifies(info, questInfo, sellPrice, ignored) -> boolean`: pure; takes the two `C_Container` tables, the price and a boolean.
  - `ns.Items.Sort(entries)`: pure, in place; by `value`, then `bag`, then `slot`.
  - `ns.Items.Scan() -> entries, pending`: `pending` is true when any stack was skipped for unloaded item data.
  - `ns.Items.HEARTHSTONE = 6948`.

- [ ] **Step 1:** `Qualifies` returns false for: `hasNoValue`, `sellPrice` nil or 0, `isLocked`, `questInfo.isQuestItem` or `questInfo.questID`, item 6948, `ignored`. Otherwise true.
- [ ] **Step 2:** `Scan` walks bags `Enum.BagIndex.Backpack` to `Bag_4` only, skipping any bag whose `GetContainerNumFreeSlots` family is non-zero.
- [ ] **Step 3:** Inside `if ns.dev.enabled then`: `ns.log("SCAN", count, "pending", pending, "cheapest", link, value)` and, once per session via `ns.dev:LogOnce`, `issecretvalue` of one `sellPrice` and one `hasNoValue` (in-game check 5).
- [ ] **Step 4:** `scripts/lint.sh`. Expected: clean.
- [ ] **Step 5:** Commit `feat(foreverbags): find the cheapest bag stacks by vendor price`.

### Task 3: Delete safely, and prove the game allows it

**Files:**
- Create: `addons/ForeverBags/Delete.lua` (add to TOC)
- Create: `addons/ForeverBags/Dev/DeleteProbe.lua` (TOC, inside a `#@do-not-package@` block)

**Interfaces:**
- Consumes: Entry from Task 2.
- Produces:
  - `ns.Delete.Matches(entry) -> boolean`: slot still holds the same `itemID`, `hyperlink` and `stackCount`, is not locked, and `GetCursorInfo()` is nil.
  - `ns.Delete.Request(entry, onDeleted) -> "deleted" | "confirming" | "stale"`. Must be called from an `OnClick`.
  - Popups `FOREVERBAGS_DELETE_ITEM` (yes/no, text `DELETE_ITEM`) and `FOREVERBAGS_DELETE_GOOD_ITEM` (typed, text `DELETE_GOOD_ITEM`, modelled on Blizzard's dialog), both `showAlert`, `hideOnEscape`, `timeout = 0`.

- [ ] **Step 1:** Quality routing: below `Enum.ItemQuality.Uncommon` delete at once; `Uncommon` shows the yes/no popup; `Rare` and above shows the typed popup. `OnAccept` calls `Matches` again before deleting.
- [ ] **Step 2:** The delete: `C_Container.PickupContainerItem(bag, slot)`; check `GetCursorInfo()` is `"item"` with our `itemID`, else `ClearCursor()` and return `"stale"`; `DeleteCursorItem()`; if the cursor still holds anything, `ClearCursor()` and return `"stale"`; else call `onDeleted()`.
- [ ] **Step 3:** `ns.log("DELETE", result, link, count)` for every outcome.
- [ ] **Step 4:** `Dev/DeleteProbe.lua` (starts with `if not ns.dev.enabled then return end`): one `UIPanelButtonTemplate` button in the middle of the screen, text `DELETE`, whose click runs `ns.Items.Scan()` and `ns.Delete.Request` on the first entry.
- [ ] **Step 5:** `scripts/lint.sh`. Expected: clean. Commit `feat(foreverbags): delete a bag stack with Blizzard-style confirmation`.
- [ ] **Step 6 (in-game gate, with the user):** `scripts/worktree.sh game ForeverBags`; the user restarts the client, clicks the probe button once on a grey or white item and once on a green, then `/rl`. `scripts/devlog.sh --errors` must show no blocked action or taint; `scripts/devlog.sh --tag DELETE` must show `deleted`. **If deletion is blocked, stop: the design goes back to the user.**

### Task 4: The window

**Files:**
- Create: `addons/ForeverBags/Window.xml` (row template `ForeverBagsRowTemplate`, mixin `ForeverBagsRowMixin`), `addons/ForeverBags/Window.lua` (both in TOC; the XML includes nothing else)
- Delete: `addons/ForeverBags/Dev/DeleteProbe.lua` and its TOC lines

**Interfaces:**
- Consumes: `ns.Items.Scan`, `ns.Delete.Request`, `ns.DB.Ignore`, `ns.L`.
- Produces:
  - `ns.Window.Open(owner, anchorFrame)`: `owner` is `"loot"` or `"hand"`; anchors to the right of `anchorFrame`, or to its left when the right edge would leave the screen. A window already open keeps its owner and position.
  - `ns.Window.Close()`, `ns.Window.IsOpen() -> boolean`, `ns.Window.Owner() -> "loot" | "hand" | nil`, `ns.Window.Refresh()`.
  - `ns.Window.onDeleted`: field `Loot.lua` sets to a function, called after each successful delete.
  - `ns.Window.onClosedByPlayer`: field `Loot.lua` sets, called from `OnHide` when the hide was not `ns.Window.Close()`.

- [ ] **Step 1:** Frame: `CreateFrame("Frame", "ForeverBagsWindow", UIParent, "ScrollingFlatPanelTemplate")`, `panelWidth = 260`, `panelMaxHeight = 290`, strata `HIGH`, title set after creation, `OnHideAnimFinished` replaced, name added to `UISpecialFrames`. ScrollBox set up as in `LootFrame.lua:62-125` with element height 46, pad 6, spacing 2.
- [ ] **Step 2:** Row (XML): 37x37 icon button with count (`NumberFontNormal`), name (quality colour), price (`GetMoneyString(value)`), a `UIPanelButtonTemplate` Delete button (text `DELETE`). Background atlas `looting_itemcard_bg` as the loot rows use.
- [ ] **Step 3:** Row behaviour: Delete calls `ns.Delete.Request(entry, ...)`; on `"stale"` refresh. Icon `OnEnter` shows `GameTooltip:SetBagItem(bag, slot)` plus the `ns.L.IGNORE_HINT` line; icon click calls `ns.DB.Ignore(itemID)` and refreshes.
- [ ] **Step 4:** While shown, refresh on `BAG_UPDATE_DELAYED`, and on `GET_ITEM_INFO_RECEIVED` when the last scan was `pending`. Events are registered in `OnShow` and unregistered in `OnHide`.
- [ ] **Step 5:** Empty state: when the scan returns nothing, show one `GameFontDisable` line (`ns.L.EMPTY`) and size the frame for one row.
- [ ] **Step 6:** `ns.log("WINDOW", "open" | "close", owner, reason)`.
- [ ] **Step 7:** `scripts/lint.sh`. Expected: clean. Commit `feat(foreverbags): show the cheapest items in a loot-style window`.

### Task 5: Open on a full inventory, and loot again

**Files:**
- Create: `addons/ForeverBags/Loot.lua` (add to TOC)
- Modify: `types/forever.lua` (`LootSlot`, `GetNumLootItems`, `GetLootSlotInfo`)

**Interfaces:**
- Consumes: `ns.Window.*`.
- Produces: nothing other files call.

- [ ] **Step 1:** Register `UI_ERROR_MESSAGE` on `LOOT_OPENED` and unregister on `LOOT_CLOSED`, as `LootFrame.lua:148,190` does. On `ERR_INV_FULL`: if the window is closed and the player has not dismissed it for this loot, `ns.Window.Open("loot", LootFrame)`; if open, `Refresh()`. Log `ns.log("FULL", errorType, "auto", autoLoot)`.
- [ ] **Step 2:** `LOOT_CLOSED`: clear the dismissed flag and the re-loot arm; close the window only when `ns.Window.Owner() == "loot"`.
- [ ] **Step 3:** `ns.Window.onClosedByPlayer` sets the dismissed flag when a loot is open.
- [ ] **Step 4:** Re-loot: `ns.Window.onDeleted` arms it when a loot is open. The next `BAG_UPDATE_DELAYED` disarms it and calls `LootSlot(i)` for every `i` in `1..GetNumLootItems()` whose `GetLootSlotInfo(i)` returns a texture. Log `ns.log("RELOOT", "before", n)` and, on the following `LOOT_SLOT_CLEARED`/`LOOT_CLOSED`, `ns.log("RELOOT", "after", remaining)`.
- [ ] **Step 5:** `scripts/lint.sh`. Expected: clean. Commit `feat(foreverbags): open on a full inventory and loot again after a delete`.

### Task 6: The bag button

**Files:**
- Create: `addons/ForeverBags/BagButton.lua` (add to TOC)

**Interfaces:**
- Consumes: `ns.Window.*`, `ns.L.BUTTON_TOOLTIP`.

- [ ] **Step 1:** One 28x26 button, created once, reparented like Blizzard's sort button: on `"ContainerFrame.OpenBag"` put it on `ContainerFrameCombinedBags` when `ContainerFrameSettingsManager:IsUsingCombinedBags()`, else on `ContainerFrame1`, anchored `RIGHT` to `BagItemAutoSortButton`'s `LEFT` with a 2px gap. Pick its atlas from the client's own bag or loot art (search `.cache/wow-ui-source` for `bags-` atlases; confirm the atlas name exists in the source before using it).
- [ ] **Step 2:** Click toggles: open → `ns.Window.Close()`; closed → `ns.Window.Open("hand", <the bag frame>)`. Tooltip from `ns.L.BUTTON_TOOLTIP`.
- [ ] **Step 3:** On `"ContainerFrame.CloseBag"` for the frame holding the button, close the window only when `ns.Window.Owner() == "hand"`.
- [ ] **Step 4:** `scripts/lint.sh`. Expected: clean. Commit `feat(foreverbags): add a bag button that opens the cheapest items`.

### Task 7: Reset the ignore list, and the changelog

**Files:**
- Create: `addons/ForeverBags/Options.lua` (add to TOC)
- Modify: `addons/ForeverBags/CHANGELOG.md`

- [ ] **Step 1:** In `ns.OnInitialize`: `Settings.RegisterVerticalLayoutCategory(ADDON_NAME)`, one `CreateSettingsButtonInitializer("", ns.L.RESET_IGNORED, onClick, ns.L.RESET_IGNORED_TOOLTIP, true)` added to the layout, `Settings.RegisterAddOnCategory(category)`. The click calls `ns.DB.ResetIgnored()` and `ns.Window.Refresh()`.
- [ ] **Step 2:** `CHANGELOG.md` under `## Unreleased`, written for players: what the window shows, when it opens, the bag button, deleting and looting again, ignoring and resetting.
- [ ] **Step 3:** `stylua addons template types`, `scripts/lint.sh`, `scripts/check-pr-title.sh "feat(foreverbags): list the cheapest bag items when bags are full"`. Expected: all clean. Commit `feat(foreverbags): add a reset for ignored items and the changelog`.

---

## Step reviewers (Phase 5)

Core: `addon-reviewer`, `api-verifier`, a correctness reviewer and a spec reviewer. Specialists: `savedvariables-guard` (new SavedVariables), a UI reviewer (new window, row template, bag button), a release reviewer (new TOC and `.pkgmeta`, the `Dev/` probe must be gone). Each gets the Review Focus above.

## In-game checks

| # | Check | Evidence |
|---|---|---|
| 1 | Deleting from our button is not blocked or tainted | Task 3 gate: `devlog.sh --errors` clean, `--tag DELETE` shows `deleted` |
| 2 | `UI_ERROR_MESSAGE` carries `ERR_INV_FULL` with auto-loot and with a clicked loot row | `devlog.sh --tag FULL`: one line per failed loot, `auto` true and false |
| 3 | `LootSlot` works from `BAG_UPDATE_DELAYED` after a delete | `devlog.sh --tag RELOOT`: `after` lower than `before`. If equal, the fallback in the spec applies and the design goes back to the user |
| 4 | Vendor price and `hasNoValue` are not secret, in and out of combat | `devlog.sh --tag SCAN`: secret flags false |
| 5 | The typed-DELETE popup accepts and deletes a blue item | `devlog.sh --tag DELETE` shows `confirming` then `deleted`; `--errors` clean |
| 6 | Window sits beside the loot window; the bag button sits left of the sort button in combined and separate bags | by eye, screenshot |
| 7 | Hand-opened window survives a loot closing; auto-opened one closes with it and does not reopen after being dismissed | `devlog.sh --tag WINDOW` owner and reason lines |
