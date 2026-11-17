local _, ns = ...

-- Turns successive readings of the XP bar (UnitXP, UnitXPMax) into gains. Pure: the caller reads
-- the bar and guarantees the readings are not secret.

ns.XPBar = {}

-- A reader's state: the last reading, plus what a level-up delivered in two parts has shown so
-- far: the size of the level being left (when the new size came before the new XP), or the XP
-- the bar dropped from (when the new XP came before the new size).
function ns.XPBar.New()
	return {}
end

-- Forgets the last reading (the bar couldn't be read, or readings were missed).
function ns.XPBar.Reset(state)
	state.xp, state.max, state.leaving, state.dropped = nil, nil, nil, nil
end

-- Takes a reading and returns the experience gained since the last one and the fraction of a
-- level it is. Across a level-up the bar wraps: the part before it is measured against the old
-- level's size, the rest against the new one's. How the client delivers a level-up is not known
-- (one event, or the XP and the size apart, in either order, the XP wrapped or not), so each is
-- handled:
--   500/1000 -> 600/1000                      100, 0.1
--   950/1000 -> 50/1200                       100, 50/1000 + 50/1200         (one event)
--   950/1000 -> 1050/1000 -> 50/1200          100, 0.1    then 0, 0          (XP first)
--   950/1000 -> 950/1200 -> 50/1200           0, 0        then 100, 50/1000 + 50/1200 (size first)
--   950/1000 -> 50/1000 -> 50/1200            0, 0        then 100, 50/1000 + 50/1200 (wrapped XP first)
--   600/1000 -> 400/1000 -> 450/1000          0, 0        then 50, 0.05  (XP lost: not a gain)
--   950/1000 -> 950/1200 -> 950/1200 -> 50/1200   100 in all: a repeated reading changes nothing
--   first reading, or a size of 0 (max level) 0, 0
function ns.XPBar.Gain(state, xp, max)
	local oldXP, oldMax, leaving, dropped = state.xp, state.max, state.leaving, state.dropped
	if xp == oldXP and max == oldMax then
		-- The same reading again (two events for one change): a level-up under way stays so.
		return 0, 0
	end
	state.xp, state.max, state.leaving, state.dropped = xp, max, nil, nil
	if not oldXP or oldMax <= 0 or max <= 0 then
		return 0, 0
	end
	if max == oldMax and xp >= oldXP then
		local gain = xp - oldXP
		return gain, gain / max
	end
	if xp >= oldXP then
		if dropped then
			-- The XP had already wrapped; now the new level's size arrived.
			local before = math.max(0, oldMax - dropped)
			return before + xp, before / oldMax + xp / max
		end
		-- The size changed and the XP didn't drop: the new level's size arrived first.
		state.leaving = oldMax
		local gain = xp - oldXP
		return gain, gain / oldMax
	end
	local size = max ~= oldMax and oldMax or leaving
	if not size then
		-- The XP dropped at an unchanged size: lost XP, or a level-up whose size is yet to come.
		state.dropped = oldXP
		return 0, 0
	end
	-- XP above the old size was already counted by an earlier reading.
	local before = math.max(0, size - oldXP)
	local after = math.max(0, xp - math.max(0, oldXP - size))
	return before + after, before / size + after / max
end
