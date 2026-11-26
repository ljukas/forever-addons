# ForeverBags ignored items list: implementation plan

**Goal:** Show the current character's ignored items on the Bags options page and let each be
removed.

**Architecture:** One custom Settings element (`Settings.CreateElementInitializer`) holding a
`WowScrollBoxList`. `Database.lua` gains read and remove functions; nothing saved changes.

**Spec:** `docs/superpowers/specs/2026-11-25-foreverbags-ignored-items-list-design.md`

**One PR:** `feat(foreverbags): show and remove ignored items in the options`

## Global constraints

- `ForeverBagsDB` layout and `DB_VERSION` stay as they are.
- No `SettingsPanel` internals; only `Settings.*`, `CreateSettings*Initializer` and the layout.
- The repo has no automated tests for addon code: each task is verified by `scripts/lint.sh`,
  and the step by the in-game checks below.

## Review focus

1. An item ID the client doesn't know (`C_Item.DoesItemExistByID` false):
   `Item:ContinueOnItemLoad` raises an error for it, so the row must not call it.
2. An item whose data loads after its row was reused for another item: the late callback must
   not write the old name onto the new row.
3. The list frame is pooled by the Settings scroll box: `RefreshIgnored` while the page is
   closed, or showing another category, must do nothing and not error.
4. Ignores held in memory (no readable GUID yet, or a foreign saved layout) are listed and
   removable like saved ones.
5. A list inside the page's own scroll box: the mouse wheel over a short list.

## Tasks

### Task 1: Database

**Files:** modify `addons/ForeverBags/Database.lua`

**Produces:**
- `ns.DB.Unignore(itemID)`: takes the item off the current list; logs `DB unignore <itemID>`.
- `ns.DB.GetIgnored()`: returns a new array of the current list's item IDs, ascending.

Verify: `scripts/lint.sh`. Commit `feat(foreverbags): read and remove single ignored items`.

### Task 2: The list on the options page

**Files:**
- Create `addons/ForeverBags/Options.xml` (loads `Options.lua`): `ForeverBagsIgnoredRowTemplate`
  (mixin `ForeverBagsIgnoredRowMixin`) and `ForeverBagsIgnoredListTemplate` (mixin
  `ForeverBagsIgnoredListMixin`).
- Modify `addons/ForeverBags/Options.lua`, `ForeverBags.toc` (`Options.lua` becomes
  `Options.xml`), `Core.lua` (strings `IGNORED_ITEMS`, `NO_IGNORED_ITEMS`; the shim's tag list),
  `Window.lua` (the ignore click calls `ns.Options.RefreshIgnored()`), `.luacheckrc` (the two
  mixin globals).

**Consumes:** Task 1's functions, `ns.Window.Refresh()`.

**Produces:** `ns.Options.RefreshIgnored()`: refills the list if it is on screen, else nothing.

Page order: section header, list element, reset button. Rows: icon
(`C_Item.GetItemIconByID`, `QUESTION_MARK_ICON` when nil), name and quality colour once the
item loads (guarded by the row's current item ID), the item ID as the name until then,
`GameTooltip:SetItemByID` on hover, a `REMOVE` button.

Verify: `scripts/lint.sh`. Commit `feat(foreverbags): list ignored items on the options page`.

### Task 3: Changelog

Add a players' line under `## Unreleased` in `addons/ForeverBags/CHANGELOG.md`. Commit with
task 2 or as `docs(foreverbags): ...`.

## Step reviewers

Core (`addon-reviewer`, `api-verifier`, correctness, spec) plus the UI reviewer. No
`savedvariables-guard`: nothing stored, no setting key, slash command or binding changes.

## In-game checks

| Check | Shown by |
| --- | --- |
| Two ignored items are listed with icon, name and colour | by eye |
| Remove takes the row away and the item is back in the window | by eye; `devlog.sh --tag DB` has `unignore <id>` |
| Reset shows the empty line | by eye |
| Ignoring with the page open adds the row | by eye |
| Wheel over the list, list height and paddings | by eye |
| No errors or blocked actions | `devlog.sh --errors` |
