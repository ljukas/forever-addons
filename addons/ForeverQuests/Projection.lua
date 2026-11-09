local _, ns = ...

-- Where the player's XP lands after gaining `gain` XP. Pure: no game API calls, so it can be
-- checked by reading. The client only tells us what the current level needs (maxXP), so past
-- the next level we report the XP carried over rather than a level we can't compute.
--   curXP, maxXP: UnitXP / UnitXPMax ("player"); level: UnitLevel("player"); gain: >= 0.
-- Returns {
--   levelsUp  = true when curXP + gain reaches maxXP,
--   fraction  = 0..1, where the turn-ins end on the current bar (1 when it levels up),
--   percent   = floor(fraction * 100),
--   nextLevel = the level the bar ends in (level + 1 when it levels up; at least that far),
--   overflow  = XP past the end of the current level (0 unless it levels up),
-- }
function ns.Project(curXP, maxXP, level, gain)
	local total = curXP + gain
	if maxXP <= 0 then
		return { levelsUp = false, fraction = 0, percent = 0, nextLevel = level, overflow = 0 }
	end
	if total >= maxXP then
		return { levelsUp = true, fraction = 1, percent = 100, nextLevel = level + 1, overflow = total - maxXP }
	end
	local fraction = math.max(total / maxXP, 0)
	return {
		levelsUp = false,
		fraction = fraction,
		percent = math.floor(fraction * 100),
		nextLevel = level,
		overflow = 0,
	}
end
