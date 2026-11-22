local _, ns = ...
local L = ns.L

-- What the line and its tooltip say, from numbers alone. Pure apart from BreakUpLargeNumbers and
-- Blizzard's colour constants, so it can be checked by reading. The client only tells us what the
-- current level needs (max), so past the next level the tooltip reports the XP carried over
-- rather than a level we can't compute.

ns.Summary = {}

--   count: completed quests; xp: their summed XP, buffs included;
--   cur, max: UnitXP / UnitXPMax ("player"); level: UnitLevel("player");
--   bonusPercent, bonusNames: ns.XPBonus.Get().
-- Returns nil when there is nothing to say (no quests, no XP, or no level size), otherwise {
--   text     = the line, e.g. "Quests: +4,250 XP (31%)": the XP and its share of the whole level,
--   levelsUp = true when cur + xp reaches max,
--   lines    = the tooltip's lines under its title, as { text, color } pairs,
-- }
function ns.Summary.Build(count, xp, cur, max, level, bonusPercent, bonusNames)
	if count <= 0 or xp <= 0 or max <= 0 then
		return nil
	end
	-- Multiply first: (29 / 100) * 100 is 28.999... and would floor to 28. XP values are small
	-- integers, so xp * 100 / max is exact whenever the percent is whole.
	local share = math.floor(xp * 100 / max)
	local total = cur + xp
	local levelsUp = total >= max

	local lines = {
		{ L.COMPLETED_XP:format(count, BreakUpLargeNumbers(xp)), NORMAL_FONT_COLOR },
		{ L.SHARE:format(share, level, BreakUpLargeNumbers(max)), HIGHLIGHT_FONT_COLOR },
	}
	-- The buff's name can be unreadable while its stacks are not; then the line would end in "from".
	if bonusPercent > 0 and #bonusNames > 0 then
		lines[#lines + 1] = { L.BONUS:format(bonusPercent, table.concat(bonusNames, ", ")), GRAY_FONT_COLOR }
	end
	if levelsUp then
		lines[#lines + 1] = { L.LEVEL_UP, GREEN_FONT_COLOR }
		if total > max then
			lines[#lines + 1] = { L.PAST_LEVEL:format(BreakUpLargeNumbers(total - max), level + 1), GREEN_FONT_COLOR }
		end
	else
		lines[#lines + 1] = { L.LANDS:format(math.floor(total * 100 / max), level), HIGHLIGHT_FONT_COLOR }
	end

	return {
		text = L.LINE:format(BreakUpLargeNumbers(xp), share),
		levelsUp = levelsUp,
		lines = lines,
	}
end
