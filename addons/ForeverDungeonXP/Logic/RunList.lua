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

-- The run list's rows: the runs in groups, each a header row followed by its runs, newest
-- first. A run without kills (a visit in progress) is left out.
--   entries: { run, key, class } per run, key and class its character's (several characters'
--     runs may be mixed)
--   sortKey: "dungeon" groups by dungeon, ordered by name; "level" by the character's level
--     when the run started
--   ascending: A to Z or lowest level first; else the reverse
-- Returns header rows { header = true, count, dungeon = name } or { header = true, count,
-- level = number }, and the entries themselves as run rows.
--   Deadmines (level 18), Wailing Caverns (19), Deadmines (19), by "level" descending
--   -> header level 19 (2 runs), Deadmines, Wailing Caverns, header level 18 (1 run), Deadmines
function ns.RunList.Rows(entries, sortKey, ascending)
	local byLevel = sortKey == "level"
	local groups, order = {}, {}
	for _, entry in ipairs(entries) do
		local run = entry.run
		if run.kills > 0 then
			local value = byLevel and (run.level or 0) or run.instanceID
			local group = groups[value]
			if not group then
				group = { value = value, entries = {} }
				groups[value] = group
				table.insert(order, group)
			end
			table.insert(group.entries, entry)
		end
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
