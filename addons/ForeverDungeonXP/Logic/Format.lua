local _, ns = ...

-- Turns a run's numbers into the text the journal shows. Pure: no client state beyond ns.L.

ns.Format = {}

local L = ns.L

-- 0 -> "< 1 min", 59 -> "< 1 min", 60 -> "1 min", 2280 -> "38 min", 4320 -> "1 h 12 min"
function ns.Format.Duration(seconds)
	if seconds < 60 then
		return L.UNDER_A_MINUTE
	end
	local minutes = math.floor(seconds / 60)
	if minutes < 60 then
		return L.MINUTES:format(minutes)
	end
	return L.HOURS_MINUTES:format(math.floor(minutes / 60), minutes % 60)
end

-- Experience per hour, rounded, or nil for a run shorter than a minute (one pack would read as
-- millions per hour).
--   7380, 2280 -> 11653        500, 30 -> nil
function ns.Format.PerHour(xp, seconds)
	if seconds < 60 then
		return nil
	end
	return math.floor(xp / seconds * 3600 + 0.5)
end

-- A fraction of a level as a whole percentage.
--   0.412 -> "41%", 1.37 -> "137%", 0.003 -> "< 1%", 0 -> "0%"
function ns.Format.Share(fraction)
	if fraction > 0 and fraction < 0.005 then
		return L.UNDER_ONE_PERCENT
	end
	return L.PERCENT:format(math.floor(fraction * 100 + 0.5))
end

-- The seconds between a run's first and last kill; 0 before its second kill.
function ns.Format.RunSeconds(run)
	if not run.firstKill or not run.lastKill then
		return 0
	end
	return math.max(0, run.lastKill - run.firstKill)
end
