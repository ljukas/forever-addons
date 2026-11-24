# "Have Some Materials" recipe filter (ForeverProfessions)

## Intent

The professions window's Filter menu has "Have Materials", which shows only recipes the player
can make in full. The player wants to see recipes they are *close* to making: those where they
carry at least some of the reagents.

## Design (approved 24 Nov 2026)

- A checkbox **Have Some Materials** in the crafting page's Filter menu
  (`MENU_PROFESSIONS_FILTER`), inserted right below Blizzard's "Have Materials"
  (`CRAFT_IS_MAKEABLE`), or at the end if that entry isn't found. Only on the crafting page's own
  dropdown (`ProfessionsFrame.CraftingPage.RecipeList.FilterDropdown`); the menu tag is shared
  with the crafting-orders browse list.
- **"Some" (our call):** the player has at least 1 of any alternative in any required
  (`Enum.CraftingReagentType.Basic`) reagent slot, counted the way Blizzard's reagent slots count
  (`ProfessionsUtil.GetReagentQuantityInPossession(reagent, true)`, character inventory). Recipes
  where everything is owned also pass, so this is a looser "Have Materials". A recipe with no
  required reagents passes.
- **State (our call):** session-only, in a local. Cleared by the filter reset button
  (`hooksecurefunc(Professions, "SetDefaultFilters")`). No SavedVariables.
- Both boxes ticked: both apply, which leaves the "Have Materials" list.

## Approaches

1. **Prune Blizzard's list after it is built (picked).** `hooksecurefunc(CraftingPage, "Init")`
   walks the tree data provider the page just set, removes recipe nodes that fail the test and
   any category left without children. Hooks only, no Blizzard function replaced.
2. Replace `Professions.GenerateCraftingDataProvider`: cleaner list, but overwriting a Blizzard
   function spreads taint (repo rule).
3. Our own recipe list: not native.

## How the list refreshes

- Toggling the box calls `CraftingPage:Init(CraftingPage.professionInfo)` so Blizzard rebuilds the
  list and our hook prunes it.
- When bags change, Blizzard rebuilds on `TRADE_SKILL_LIST_UPDATE` if the client sends one
  (unverified in game). Our hook runs after each rebuild.
- The reset ✕ needs nothing from us: on Forever it is always shown, since Camelot's list build
  forces `SetShowUnlearned(false)` and so `IsUsingDefaultFilters` is never true (seen in game,
  24 Nov).
- The rebuild passes a copy of `professionInfo` without `openRecipeID`, so a recipe opened by
  link isn't selected and scrolled to again.

## Pruning (review, 24 Nov)

- Pruning also drops a category's top and bottom padding rows when none of its own recipes stay,
  and the unlearned divider when no unlearned category stays (30 px high when no learned one does).
- Blizzard selects a recipe from the unpruned list. If the shown recipe was pruned, we select the
  first kept one, or clear the selection and the schematic when the list is empty.
- Not handled: the minimized window's search results (Forever's frame has no minimize control).
