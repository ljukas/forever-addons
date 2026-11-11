# ForeverBags: cheapest items when the bags are full

Date: 2026-11-11. Status: design, not built.

## Intent

When the bags are full and loot is waiting, the player wants to throw away the least valuable
thing they carry and pick the loot up, without opening the bags and comparing prices by hand.

The user has been using *DeleteCheapestItem Reloaded* for this and likes how it works. What they
dislike is its title bar reading "DeleteCheapestItem Reloaded": it marks the window as an addon
rather than part of the game. ForeverBags is our own version of the same idea, cut down to what
the user uses, and looking like Blizzard's loot window.

**Licence.** The original is "All Rights Reserved"; this repo is MIT. Its code was read to learn
what it does and is not to be copied. Everything here is written fresh. The addon's TOC credits
the idea (`## X-Credits`).

## Goals

1. A list of the cheapest stacks in the player's bags by **vendor price**, cheapest first, each
   with the price shown and a Delete button.
2. The list opens by itself in exactly one case: looting fails because the inventory is full.
3. A button on the bag frame opens and closes the list by hand.
4. After a stack is deleted, the addon tries again to loot what is left in the open loot window.
5. An ignore list: an ignored item never appears in the list again, until the list is reset.
6. The window looks native: the loot window's frame, titled with the game's own wording.

## Non-goals

- Auction prices, or any link to an auction addon.
- Selling to a vendor from the list.
- Opening automatically in any other situation: bags opened, quest rewards, trade, mail, loot
  rolls, low free slots.
- Quality or soulbound filters, full-stack values, combat visibility options, a debug mode.
- A slash command. The bag button is the manual way in.
- Dragging the window or saving its position.
- Localisation files. Text comes from Blizzard's GlobalStrings where one fits; the few strings of
  our own are English.

## Anti-goals

- Deleting something the player did not mean to delete. Every delete is a click on a row the
  player can read, on an item re-checked at that moment.
- A window that appears when the player did not cause it. Opening the bags must never open it.
- Anything that reads as "an addon": our name in a title, custom art, our own settings window.

## How it behaves

### The list

- Covers the backpack and the four equipped bags. The reagent bag and specialty bags are left out.
- One row per bag slot (per stack), not per item type.
- A stack's value is the item's vendor sell price times the stack count. Rows are sorted by that
  value, cheapest first; ties keep bag-then-slot order.
- Left out of the list entirely:
  - items with no vendor price (`hasNoValue`, or a sell price of 0);
  - quest items;
  - the Hearthstone (item 6948);
  - locked slots;
  - items on the ignore list.
- A row shows the icon with the stack count, the name in its quality colour, the stack's value as
  gold/silver/copper with coin icons, and a **Delete** button.
- Hovering the icon shows the item's normal tooltip, with one extra line saying a click ignores it.
- The list refreshes when the bags change while it is open. If item data is not loaded yet, the
  row appears once it is.
- If nothing qualifies, the window shows a single line saying so, not an empty frame.

### Opening and closing

- **Automatic:** on `UI_ERROR_MESSAGE` whose message is `ERR_INV_FULL` while the loot window is
  open. The window appears beside the loot window (to its right, moving to the left if it would
  leave the screen) and closes when the loot window closes (`LOOT_CLOSED`).
- **By hand:** the bag button toggles it. Opened this way it is anchored beside the bag frame and
  stays until the player closes it with the close button, the bag button, or Escape. Closing the
  bags closes it too.
- If the player closes it during a loot, it does not reopen for that loot window.
- There is one window, and it remembers how it was opened:
  - Opened by hand, then a loot fails on full bags: it stays where it is and stays hand-opened
    (it does not move, and `LOOT_CLOSED` does not close it). Looting again after a delete still
    applies.
  - Opened automatically, then the bag button is pressed: it closes, and does not reopen for
    that loot window.
  - Opened automatically, then the bags are closed: it stays. Only a hand-opened window closes
    with the bags.
- Combat: the window is not a secure frame and may open and close in combat.

### Deleting

- Clicking Delete re-reads the slot. If the item there is no longer the one the row showed (same
  item ID, link and count), or the cursor is holding something, nothing is deleted and the list
  refreshes.
- Poor (grey) and common (white) items are deleted at the click.
- Better items are confirmed the way Blizzard's own delete flow does it (`HandleDeleteItemConfirm`
  in `Blizzard_Game/Camelot/EventImplementation.lua`): uncommon (green) gets a yes/no popup with
  the item's link; rare (blue) and better require typing DELETE, with Blizzard's
  `DELETE_GOOD_ITEM` wording. The item is re-checked again when the popup is accepted.
- The delete itself is pick up the slot, confirm the cursor holds that item, delete the cursor
  item. If the cursor ends up holding anything else, it is cleared and nothing is deleted.

### Looting again

- After a successful delete while the loot window is open, the addon waits for the bag slot to
  be reported free (the next `BAG_UPDATE_DELAYED`), then loots every remaining slot of the loot
  window once.
- If the bags are still full afterwards, the game raises the full-inventory error again and the
  window stays open with a refreshed list. If everything was looted, the loot window closes and
  takes ours with it.
- One retry per delete. No loops, no timers that keep trying.
- "Every remaining slot" is deliberate, including when the player was looting row by row: the
  user asked for the loot window's items to be retried. A slot that needs the game's own
  confirmation (bind on pickup, a group roll) gets that confirmation as usual.

### Ignoring

- Clicking an item's icon in the list adds that item (by item ID) to the ignore list, and the row
  disappears.
- The ignore list is saved per character.
- "Reset ignored items" is a button on the addon's page in the game's Settings panel. That page
  has nothing else on it for now.

### The window

- Built on `ScrollingFlatPanelTemplate`, the template `LootFrame` itself uses, so the border,
  close button, scroll box and scroll bar are Blizzard's.
- Title: `ERR_INV_FULL` with its trailing full stop removed ("Inventory is full"). No addon name
  anywhere in the window.
- Width close to the loot window's; height fits up to about five rows, then scrolls.
- Rows use Blizzard's button template for Delete (`UIPanelButtonTemplate`, text `DELETE`) and
  Blizzard's money formatting for the price.

### The bag button

- A small button in the header of the bag frame: on `ContainerFrameCombinedBags` when bags are
  combined, on the backpack (`ContainerFrame1`) when they are separate.
- Uses a Blizzard atlas for its icon, picked during the build from the client's own art.
- Tooltip: what it opens.
- It is our own frame parented to the bag frame; no Blizzard function or field is overwritten.

## Constraints

- Forever client, interface 16001, modern API. Every API is checked in `.cache/wow-ui-source`
  before use.
- `DeleteCursorItem` has restrictions (`HasRestrictions = true`): it must run from the player's
  click. The delete therefore happens directly in the Delete button's handler, or in the popup's
  accept handler, never from an event or a timer.
- `LootSlot` is not in the generated docs for this build; the original addon calls it on Forever.
  Whether it is accepted from an event handler shortly after the delete, outside the click, is
  **not known**. See the in-game checks.
- Never overwrite Blizzard functions or frame fields; hook with `hooksecurefunc` / `HookScript` /
  `EventRegistry`.
- Repo conventions in `CLAUDE.md`: `local ADDON_NAME, ns = ...`, no globals beyond SavedVariables
  and client-required names, `ns.log` not `print`, every file in the TOC, a players' line in
  `CHANGELOG.md`.

## What only the game can confirm

Each gets an `ns.log` line so the devlog answers it.

1. `UI_ERROR_MESSAGE` fires with `ERR_INV_FULL` when looting with full bags, both with auto-loot
   and when clicking a loot row. Tag `FULL`.
2. `LootSlot` works from the `BAG_UPDATE_DELAYED` handler after a delete. Tag `RELOOT`, logging
   the loot slots before and after. If it does not, the fallback is to loot in the Delete click
   itself (as the original does) and accept that the first attempt can lose the race with the
   server; that is a change to this design and comes back to the user.
3. Deleting from our button raises no blocked-action or taint event (`devlog.sh --errors`).
   Everything else rests on this, so the build checks it first: the first task the user tests
   in game is a bare Delete button on one row, before the rest of the window is built. If it is
   blocked, the build stops and the design comes back to the user.
4. The window lines up beside the loot window and the bag button sits cleanly in the bag header,
   in both combined and separate bag modes.
5. Vendor prices and `hasNoValue` are readable for every bag item, in and out of combat (not
   secret). Tag `SCAN`.

## Decided by the user

- Vendor price only.
- Opens automatically only on a full inventory while looting; never on opening the bags.
- A bag-frame button opens it by hand.
- Delete and an ignore list; vendor price shown on each row.
- Window style: the loot window's frame with the game's own "Inventory is full" title.
- Retry looting after a delete.

## Decided by Claude (check these)

- Addon name `ForeverBags`.
- Sort by whole-stack value; one row per stack.
- Items without a vendor price, quest items and the Hearthstone are never listed.
- No confirmation for grey and white; yes/no for green; typing DELETE for blue and better.
- Re-loot waits for the slot to free, one attempt per delete, and takes every remaining loot slot.
- How the two ways of opening combine (see "Opening and closing").
- The delete is tested in game first, before the rest of the window is built.
- Window is not draggable; it closes with the loot window, or stays until closed when opened from
  the bag button.
- Ignore by clicking the icon; reset in the Settings panel; saved per character.
- No slash command.
- Reagent and specialty bags are not scanned.
- Title has the trailing full stop of `ERR_INV_FULL` removed.

## Left to the builder

- File layout inside `addons/ForeverBags/` (from `scripts/new-addon.sh`), keeping the pure parts
  (which stacks qualify, sorting) apart from frames and events.
- The SavedVariables layout for the ignore list and its version field.
- Row template details, exact sizes and offsets, the bag button's atlas and position.
- The exact wording of our few English strings.
