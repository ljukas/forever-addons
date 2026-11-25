# ForeverBags: ignored items on the options page

## Intent

A player who clicked an item's icon in the cheapest-items list never sees it listed again on that
character. Today the only way back is "Reset ignored items", which brings every item back, and
nothing shows what is on the list. The options page should show the list and let one item be
taken off it.

## Goals

- Options > AddOns > RazzhUI > Bags shows the current character's ignored items: icon, name in
  its quality colour, and a remove button each. Hovering a row shows the item's tooltip.
- Removing an item takes effect at once: the row goes, and the item is listed again in the
  cheapest-items window if that is open.
- An empty list says so.
- "Reset ignored items" stays, and empties the shown list too.

## Non-goals

- Other characters' lists. The data is keyed by character GUID with no name stored, so they
  can't be labelled.
- Adding an item to the list from the options page. That stays a click in the window.
- Any change to what is saved. `ForeverBagsDB` keeps its layout and version.

## Anti-goals

- No new window, and no rebuilding of the Settings page through `SettingsPanel` internals.

## Approaches

- **A. A list inside one row of the page (picked by the user).** One custom settings element
  holding a scroll box. The list is visible without a click and the page's own rows stay fixed.
- **B. A button opening a context menu of the items**, as ForeverMinimap does for kept buttons.
  Cheaper, but the list stays hidden until clicked and a long one makes a tall menu.
- **C. One real settings row per item.** The page's rows are fixed at registration, so every
  change would rebuild the page through Blizzard's internals. Ruled out for the taint risk.

## Design

Page order: a section header "Ignored items", the list element, then the existing reset button.

- **Database.lua** gains `ns.DB.Unignore(itemID)` and `ns.DB.GetIgnored()` (a new sorted array of
  item IDs, so nothing outside the file holds the saved table). Ignores held in memory because
  the character isn't known yet are listed and removable like saved ones.
- **Options.xml** (new, loads Options.lua, as Window.xml loads Window.lua) defines two templates:
  - `ForeverBagsIgnoredListTemplate`: a fixed-height frame with a `WowScrollBoxList`, a
    `MinimalScrollBar` that hides when there is nothing to scroll, and an "empty" font string,
    on a flat dark panel (a colour, no frame art: the Settings page is flat). While the list
    has nothing to scroll, the mouse wheel is left to the page.
    Added to the page with `Settings.CreateElementInitializer`.
  - `ForeverBagsIgnoredRowTemplate`: icon, name, and a small `UIPanelButtonTemplate` button
    labelled with Blizzard's `REMOVE`.
- **Options.lua**: the list fills when the page shows it (`Init`) and again after every change
  to the list. Changes are announced by one function, `ns.Options.RefreshIgnored()`, which the
  window's ignore click, the remove button and the reset button all call; it does nothing while
  the list isn't on screen.
- **Item data** may not be loaded for an item ID. A row shows the icon at once
  (`C_Item.GetItemIconByID`), and the name and colour through `Item:CreateFromItemID` and
  `ContinueOnItemLoad`, whose callback checks that the row still shows that item. An item the client doesn't
  know at all is shown as its ID and can still be removed.
- **Order:** by item ID. Names load late, and sorting by them would move rows under the cursor.
- **Secret values:** none are read. Item IDs come from our own saved data.
- **Combat:** nothing here is protected; the list works in combat like the rest of the page.

## Left to the builder

The list's height, row height and paddings, by eye in game.

## In-game checks

1. Ignore two items in the window, open the options page: both are listed with icon and name.
2. Remove one: the row goes; the item is back in the window.
3. Reset: the list shows the empty line.
4. Ignore an item while the options page is open: it appears in the list.
5. No Lua errors or blocked actions (`scripts/devlog.sh --errors`); `--tag DB` shows the
   `unignore` line for each removal.
