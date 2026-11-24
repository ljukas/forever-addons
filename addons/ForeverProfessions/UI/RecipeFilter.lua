local _, ns = ...

-- "Have Some Materials" in the professions window's Filter menu
-- (docs/superpowers/specs/2026-11-24-have-some-materials-filter-design.md): keeps the recipes where
-- the player carries at least one of the required reagents. Blizzard builds the recipe list as
-- usual; we hook the crafting page's Init and prune the tree it just set. Nothing of Blizzard's is
-- replaced. The filter is session state, cleared by the filter reset button like Blizzard's own.

local L = ns.L
local BASIC = Enum.CraftingReagentType.Basic

local enabled = false
local page, dropdown

-- Whether the player owns at least one of any required reagent of the recipe. A recipe without
-- required reagents passes, as it does for "Have Materials".
local function HasSomeMaterials(recipeID)
	local schematic = C_TradeSkillUI.GetRecipeSchematic(recipeID, false)
	local slots = schematic and schematic.reagentSlotSchematics
	if not slots then
		return true
	end
	local anyRequired = false
	for _, slot in ipairs(slots) do
		if slot.reagentType == BASIC then
			anyRequired = true
			for _, reagent in ipairs(slot.reagents) do
				-- GetReagentQuantityInPossession asserts on a reagent with neither.
				if
					(reagent.itemID or reagent.currencyID)
					and ProfessionsUtil.GetReagentQuantityInPossession(reagent, true) > 0
				then
					return true
				end
			end
		end
	end
	return not anyRequired
end

-- Removes from node the recipes that fail the test (verdicts caches them per recipeID, since
-- favorites repeat recipes) and the categories left without any, with the padding of a category
-- left without recipes of its own. Returns whether node still holds a recipe somewhere below.
local function Prune(node, verdicts, counts)
	local hasRecipe, hasContent = false, false
	local children = CopyTable(node:GetNodes(), true)
	local skipInvalidation = true
	for _, child in ipairs(children) do
		local data = child:GetData()
		if data.recipeInfo then
			local recipeID = data.recipeInfo.recipeID
			local keep = verdicts[recipeID]
			if keep == nil then
				keep = HasSomeMaterials(recipeID)
				verdicts[recipeID] = keep
			end
			if keep then
				hasRecipe, hasContent = true, true
				counts.kept = counts.kept + 1
			else
				node:Remove(child, skipInvalidation)
				counts.removed = counts.removed + 1
			end
		elseif data.categoryInfo then
			if Prune(child, verdicts, counts) then
				hasContent = true
			else
				node:Remove(child, skipInvalidation)
			end
		end
	end
	if not hasRecipe then
		for _, child in ipairs(children) do
			local data = child:GetData()
			if data.topPadding or data.bottomPadding then
				node:Remove(child, skipInvalidation)
			end
		end
	end
	return hasContent
end

-- The divider above the unlearned recipes stays only while an unlearned category does.
local function PruneDivider(root)
	local divider, unlearned
	for _, child in ipairs(root:GetNodes()) do
		local data = child:GetData()
		if data.isDivider then
			divider = child
		elseif data.categoryInfo and data.categoryInfo.unlearned then
			unlearned = true
		end
	end
	if divider and not unlearned then
		root:Remove(divider, true)
	end
end

local function OnPageInit()
	if not enabled then
		return
	end
	local scrollBox = page.RecipeList.ScrollBox
	local provider = scrollBox:GetDataProvider()
	if not provider then
		return
	end
	local counts = { kept = 0, removed = 0 }
	local root = provider:GetRootNode()
	Prune(root, {}, counts)
	PruneDivider(root)
	provider:Invalidate()
	page.RecipeList.NoResultsText:SetShown(provider:IsEmpty())
	ns.log("FILTER", "pruned: kept", counts.kept, "removed", counts.removed)
end

-- Has Blizzard rebuild the list (and so our hook prune it, or not).
local function Rebuild()
	if page:IsVisible() and page.professionInfo then
		page:Init(page.professionInfo)
	end
end

local function IsEnabled()
	return enabled
end

local function Toggle()
	enabled = not enabled
	ns.log("FILTER", "have some materials", enabled)
	Rebuild()
end

local function AddCheckbox(owner, rootDescription)
	if owner ~= dropdown then
		return
	end
	-- Right below Blizzard's "Have Materials", or at the end if it isn't there.
	local index
	local position = 0
	for _, description in rootDescription:EnumerateElementDescriptions() do
		position = position + 1
		if MenuUtil.GetElementText(description) == CRAFT_IS_MAKEABLE then
			index = position + 1
		end
	end
	local checkbox = MenuUtil.CreateCheckbox(L.HAVE_SOME_MATERIALS, IsEnabled, Toggle)
	rootDescription:Insert(checkbox, index)
end

local function OnDefaultFilters()
	if not enabled then
		return
	end
	enabled = false
	ns.log("FILTER", "have some materials cleared by default filters")
	-- Blizzard's reset may change none of its own filters, and then sends no list update: rebuild
	-- once its own calls are done.
	RunNextFrame(Rebuild)
end

-- Blizzard's reset button only knows Blizzard's filters.
local function OnValidateResetState(self)
	if enabled then
		self.ResetButton:Show()
	end
end

local function Setup()
	local craftingPage = ProfessionsFrame and ProfessionsFrame.CraftingPage
	local list = craftingPage and craftingPage.RecipeList
	if not (craftingPage and list and list.FilterDropdown and list.FilterDropdown.ResetButton and list.ScrollBox) then
		ns.log("FILTER", "crafting page or filter dropdown not found, filter not added")
		return
	end
	page, dropdown = craftingPage, list.FilterDropdown
	hooksecurefunc(page, "Init", OnPageInit)
	hooksecurefunc(Professions, "SetDefaultFilters", OnDefaultFilters)
	hooksecurefunc(dropdown, "ValidateResetState", OnValidateResetState)
	Menu.ModifyMenu("MENU_PROFESSIONS_FILTER", AddCheckbox)
end

ns.OnInitialize(function()
	EventUtil.ContinueOnAddOnLoaded("Blizzard_Professions", Setup)
end)
