local _, ns = ...

-- Appends the turn-in lines to the experience bar's tooltip. Blizzard builds that tooltip in
-- ExhaustionTick:ExhaustionToolTipText(), from the bar's OnEnter and from the rested pip's own
-- OnEnter, but only when GetRestState() reports a state; otherwise it shows nothing and we
-- open the tooltip ourselves, the same way.

ns.Tooltip = {}

-- Plain ASCII: the client font may lack arrows and ellipses.
local L = {
	COMPLETED = "Completed quests: %d",
	COMPLETED_XP = "Completed quests: %d (+%s XP)",
	LOADING = "Loading quest rewards...",
	LANDS = "Ends at %d%% of level %d",
	LEVEL_UP = "Level up!",
	PAST_LEVEL = "+%s XP past level %d",
	BONUS = "Includes +%d%% from %s",
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

-- The lines to add, as { text, color } pairs (color nil = normal), or nil for none. Only the
-- secret case shows the bare count; max level, XP disabled or no XP reward show nothing.
local function Lines(result)
	local quests, proj = result.quests, result.proj
	if quests.count == 0 then
		return nil
	end
	-- Max level or XP gain disabled: Compute read no XP, and it isn't because it was secret.
	if not result.cur and not result.xpSecret then
		return nil
	end
	if quests.pending then
		return { { L.COMPLETED:format(quests.count) }, { L.LOADING, GRAY_FONT_COLOR } }
	end
	if quests.secret or result.xpSecret then
		return { { L.COMPLETED:format(quests.count) } }
	end
	if not proj then
		return nil
	end
	local lines = { { L.COMPLETED_XP:format(quests.count, BreakUpLargeNumbers(quests.xp)) } }
	local bonus, buffNames = ns.XPBonus.Get()
	if bonus > 0 then
		lines[#lines + 1] = { L.BONUS:format(bonus, table.concat(buffNames, ", ")), GRAY_FONT_COLOR }
	end
	if proj.levelsUp then
		lines[#lines + 1] = { L.LEVEL_UP, GREEN_FONT_COLOR }
		if proj.overflow > 0 then
			lines[#lines + 1] =
				{ L.PAST_LEVEL:format(BreakUpLargeNumbers(proj.overflow), proj.nextLevel), GREEN_FONT_COLOR }
		end
	else
		lines[#lines + 1] = { L.LANDS:format(proj.percent, proj.nextLevel), HIGHLIGHT_FONT_COLOR }
	end
	return lines
end

local function AddLines()
	local lines = Lines(ns.ExpBar.Refresh())
	if not lines then
		return
	end

	local tooltip = GetAppropriateTooltip()
	Watch(tooltip)
	if GetRestState() then
		-- Blizzard just (re)built it: SetDefaultAnchor cleared it, so `added` was reset.
		if added[tooltip] then
			return
		end
		GameTooltip_AddBlankLineToTooltip(tooltip)
	else
		-- Blizzard showed nothing; whatever the tooltip holds now isn't ours. Start it afresh.
		GameTooltip_SetDefaultAnchor(tooltip, UIParent)
		local result = ns.ExpBar.lastResult
		if result.cur and not result.xpSecret and result.max > 0 then
			local percent = math.ceil(result.cur / result.max * 100)
			GameTooltip_SetTitle(
				tooltip,
				XP_TEXT:format(BreakUpLargeNumbers(result.cur), BreakUpLargeNumbers(result.max), percent)
			)
		end
	end

	for _, line in ipairs(lines) do
		GameTooltip_AddColoredLine(tooltip, line[1], line[2] or NORMAL_FONT_COLOR)
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
