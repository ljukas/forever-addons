local _, ns = ...

-- Appends the turn-in lines to the experience bar's tooltip. Blizzard builds that tooltip in
-- ExhaustionTick:ExhaustionToolTipText(), from the bar's OnEnter and from the rested pip's own
-- OnEnter, and shows nothing when the player has no rest state; then we open it ourselves.

ns.Tooltip = {}

local L = {
	COMPLETED = "Completed quests: %d",
	COMPLETED_XP = "Completed quests: %d (+%s XP)",
	LOADING = "Loading quest rewards…",
	LANDS = "→ %d%% of level %d",
	LEVEL_UP = "Level up!",
	PAST_LEVEL = "+%s XP past level %d",
}

local added = setmetatable({}, { __mode = "k" }) -- tooltip -> true once our lines are on it
local watched = setmetatable({}, { __mode = "k" }) -- tooltips whose clear/hide we hooked

local function Forget(tooltip)
	added[tooltip] = nil
end

local function Watch(tooltip)
	if watched[tooltip] then
		return
	end
	watched[tooltip] = true
	tooltip:HookScript("OnTooltipCleared", Forget)
	tooltip:HookScript("OnHide", Forget)
end

local function AddLines()
	local result = ns.ExpBar.Refresh()
	local quests, proj = result.quests, result.proj
	if quests.count == 0 then
		return
	end

	local tooltip = GetAppropriateTooltip()
	Watch(tooltip)
	if tooltip:IsShown() and added[tooltip] then
		return
	end
	if not tooltip:IsShown() then
		-- Blizzard showed nothing (no rest state): open it as ExhaustionToolTipText would.
		GameTooltip_SetDefaultAnchor(tooltip, UIParent)
		if result.cur then
			local percent = math.ceil(result.cur / result.max * 100)
			GameTooltip_SetTitle(
				tooltip,
				XP_TEXT:format(BreakUpLargeNumbers(result.cur), BreakUpLargeNumbers(result.max), percent)
			)
		end
	else
		GameTooltip_AddBlankLineToTooltip(tooltip)
	end

	if quests.pending then
		GameTooltip_AddNormalLine(tooltip, L.COMPLETED:format(quests.count))
		GameTooltip_AddColoredLine(tooltip, L.LOADING, GRAY_FONT_COLOR)
	elseif not proj then
		-- Secret XP, max level, XP disabled, or quests that reward no XP: the count only.
		GameTooltip_AddNormalLine(tooltip, L.COMPLETED:format(quests.count))
	else
		GameTooltip_AddNormalLine(tooltip, L.COMPLETED_XP:format(quests.count, BreakUpLargeNumbers(quests.xp)))
		if proj.levelsUp then
			GameTooltip_AddColoredLine(tooltip, L.LEVEL_UP, GREEN_FONT_COLOR)
			GameTooltip_AddColoredLine(
				tooltip,
				L.PAST_LEVEL:format(BreakUpLargeNumbers(proj.overflow), proj.nextLevel),
				GREEN_FONT_COLOR
			)
		else
			GameTooltip_AddHighlightLine(tooltip, L.LANDS:format(proj.percent, proj.nextLevel))
		end
	end
	added[tooltip] = true
	tooltip:Show()
end

-- Called by ExpBar.lua for each experience bar it hooks.
function ns.Tooltip.Attach(bar)
	bar:HookScript("OnEnter", AddLines)
	if bar.ExhaustionTick then
		bar.ExhaustionTick:HookScript("OnEnter", AddLines)
	end
end
