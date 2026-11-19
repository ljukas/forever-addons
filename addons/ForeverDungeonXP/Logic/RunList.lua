local _, ns = ...

-- Orders runs for the journal's run list. Pure: no client state.

ns.RunList = {}

local function Newer(a, b)
	local aTime, bTime = a.run.firstKill or 0, b.run.firstKill or 0
	if aTime ~= bTime then
		return aTime > bTime
	end
	if a.run.id ~= b.run.id then
		return a.run.id > b.run.id
	end
	return a.key < b.key
end

-- Orders entries by their rate. One without a rate (a run shorter than a minute) stands last
-- whichever way the order goes, and equal rates go newest first.
local function ByRate(ascending)
	return function(a, b)
		if a.rate == b.rate then
			return Newer(a, b)
		end
		if not a.rate or not b.rate then
			return a.rate ~= nil
		end
		if ascending then
			return a.rate < b.rate
		end
		return a.rate > b.rate
	end
end

-- The run list's rows: the runs in groups, each a header row followed by its runs, newest
-- first, or all of them in one list by their experience per hour. A run without kills (a visit
-- in progress) is left out.
--   entries: { run, key, class } per run, key and class its character's (several characters'
--     runs may be mixed)
--   sortKey: "dungeon" groups by dungeon, ordered by name; "level" by the character's level
--     when the run started; "rate" groups nothing and orders the runs by experience per hour
--   ascending: A to Z, lowest level first or lowest rate first; else the reverse
-- Returns header rows { header = true, count, dungeon = name } or { header = true, count,
-- level = number }, and the entries themselves as run rows, each with rate (ns.Format.Rate, nil
-- for a run without one) added.
--   Deadmines (level 18), Wailing Caverns (19), Deadmines (19), by "level" descending
--   -> header level 19 (2 runs), Deadmines, Wailing Caverns, header level 18 (1 run), Deadmines
--   rates 12843, none, 27085, by "rate" descending -> 27085, 12843, none (and ascending:
--   12843, 27085, none)
function ns.RunList.Rows(entries, sortKey, ascending)
	local listed = {}
	for _, entry in ipairs(entries) do
		if entry.run.kills > 0 then
			entry.rate = ns.Format.Rate(entry.run)
			table.insert(listed, entry)
		end
	end
	if sortKey == "rate" then
		table.sort(listed, ByRate(ascending))
		return listed
	end
	local byLevel = sortKey == "level"
	local groups, order = {}, {}
	for _, entry in ipairs(listed) do
		local run = entry.run
		local value = byLevel and (run.level or 0) or run.instanceID
		local group = groups[value]
		if not group then
			group = { value = value, entries = {} }
			groups[value] = group
			table.insert(order, group)
		end
		table.insert(group.entries, entry)
	end
	for _, group in ipairs(order) do
		table.sort(group.entries, Newer)
		-- A dungeon goes by the name its newest run saw.
		group.name = byLevel and "" or group.entries[1].run.name
	end
	table.sort(order, function(a, b)
		if a.name ~= b.name then
			if ascending then
				return a.name < b.name
			end
			return a.name > b.name
		end
		if ascending then
			return a.value < b.value
		end
		return a.value > b.value
	end)
	local rows = {}
	for _, group in ipairs(order) do
		local header = { header = true, count = #group.entries }
		if byLevel then
			header.level = group.value
		else
			header.dungeon = group.name
		end
		table.insert(rows, header)
		for _, entry in ipairs(group.entries) do
			table.insert(rows, entry)
		end
	end
	return rows
end
