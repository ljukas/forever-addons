local _, ns = ...

-- Orders runs for the journal's run list. Pure: no client state.

ns.RunList = {}

-- When a run started; 0 for one without a first kill or with a damaged time.
local function Started(entry)
	local time = entry.run.firstKill
	return type(time) == "number" and time or 0
end

local function Newer(a, b)
	local aTime, bTime = Started(a), Started(b)
	if aTime ~= bTime then
		return aTime > bTime
	end
	if a.run.id ~= b.run.id then
		return a.run.id > b.run.id
	end
	return a.key < b.key
end

-- What each column orders the runs by; nil for a run without it (or with a damaged field).
local VALUE = {
	date = function(entry)
		local time = entry.run.firstKill
		return type(time) == "number" and time or nil
	end,
	dungeon = function(entry)
		local name = entry.run.name
		return type(name) == "string" and name or nil
	end,
	level = function(entry)
		local level = entry.run.level
		return type(level) == "number" and level or nil
	end,
	rate = function(entry)
		return entry.rate
	end,
}

-- The run list's rows: every run in one list, ordered by one of its columns. A run without
-- kills (a visit in progress) is left out.
--   entries: { run, key, class } per run, key and class its character's (several characters'
--     runs may be mixed)
--   sortKey: "date" (when the run started), "dungeon" (its name), "level" (the character's
--     when it started) or "rate" (its experience per hour, ns.Format.Rate)
--   ascending: oldest, A to Z or lowest first; else the reverse
-- Runs alike in the column go newest first whichever way the order goes, and a run without the
-- column's value (a rate for a run shorter than a minute, a date for a run with a damaged time)
-- stands last whichever way it goes.
-- Returns the entries themselves, each with rate (nil for a run without one) added.
--   rates 12843, none, 27085, by "rate" descending -> 27085, 12843, none (and ascending:
--   12843, 27085, none)
--   Deadmines 12 Nov, Wailing Caverns 16 Nov, Deadmines 17 Nov, by "dungeon" ascending
--   -> Deadmines 17 Nov, Deadmines 12 Nov, Wailing Caverns 16 Nov
function ns.RunList.Rows(entries, sortKey, ascending)
	local rows = {}
	for _, entry in ipairs(entries) do
		if entry.run.kills > 0 then
			entry.rate = ns.Format.Rate(entry.run)
			table.insert(rows, entry)
		end
	end
	local value = VALUE[sortKey] or VALUE.date
	table.sort(rows, function(a, b)
		local aValue, bValue = value(a), value(b)
		if aValue == bValue then
			return Newer(a, b)
		end
		if aValue == nil or bValue == nil then
			return aValue ~= nil
		end
		if ascending then
			return aValue < bValue
		end
		return aValue > bValue
	end)
	return rows
end
