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

-- The seconds between a run's first and last kill; 0 before its second kill, and for saved
-- times that aren't numbers (the run list works this out for every run, so one damaged run must
-- not stop the list).
function ns.Format.RunSeconds(run)
	if type(run.firstKill) ~= "number" or type(run.lastKill) ~= "number" then
		return 0
	end
	return math.max(0, run.lastKill - run.firstKill)
end

-- A run's experience per hour, from its first kill to its last, without its rested bonus, so
-- that rested and unrested runs compare; nil for a run shorter than a minute (PerHour). A run
-- recorded before the rested bonus was kept has none to leave out.
--   13994 XP, 8994 of it rested, in 31 minutes -> 9677        9418 XP in 44 minutes -> 12843
function ns.Format.Rate(run)
	-- Kept between none and all of the experience: a damaged figure must not raise the rate.
	local rested = type(run.rested) == "number" and math.min(math.max(0, run.rested), run.xp) or 0
	return ns.Format.PerHour(run.xp - rested, ns.Format.RunSeconds(run))
end

-- The same with the rested bonus in it: what the run paid.
--   13994 XP, 8994 of it rested, in 31 minutes -> 27085
function ns.Format.RateWithRested(run)
	return ns.Format.PerHour(run.xp, ns.Format.RunSeconds(run))
end

-- A run's party members { name, class, level, role } by name, for display; empty for a run
-- alone or recorded before members were kept.
function ns.Format.Party(run)
	local members = {}
	if type(run.party) == "table" then
		for name, member in pairs(run.party) do
			table.insert(members, { name = name, class = member.class, level = member.level, role = member.role })
		end
	end
	table.sort(members, function(a, b)
		return a.name < b.name
	end)
	return members
end
