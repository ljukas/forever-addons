local _, ns = ...

-- A run's timeline for the journal. Pure: no events, no client state.

ns.Timeline = {}

-- The run's rows in the order things happened: its first and last kill and its events
-- (Database.lua's run.events). Each row is { kind, t, offset, ... the event's own fields }:
-- kind "first" or "last" for the kills, else the event's; offset the seconds since the timeline's
-- start, which is the first kill or an event before it. A boss or wipe with a known pull also
-- has duration, the fight's seconds. Rows at the same second keep the order: first kill, events
-- as recorded, last kill. Empty for a run without kills or events.
--   firstKill 100, lastKill 400, events { boss "Smite" t 250 pull 220 } ->
--     { first, offset 0 }, { boss, "Smite", offset 150, duration 30 }, { last, offset 300 }
function ns.Timeline.Rows(run)
	local rows = {}
	if run.firstKill then
		table.insert(rows, { kind = "first", t = run.firstKill })
	end
	for _, event in ipairs(run.events or {}) do
		local row = {}
		for field, value in pairs(event) do
			row[field] = value
		end
		if (row.kind == "boss" or row.kind == "wipe") and type(row.pull) == "number" and row.pull <= row.t then
			row.duration = row.t - row.pull
		end
		table.insert(rows, row)
	end
	-- A run with one kill has one moment: no separate last kill.
	if run.lastKill and run.lastKill ~= run.firstKill then
		table.insert(rows, { kind = "last", t = run.lastKill })
	end
	for index, row in ipairs(rows) do
		row.index = index
	end
	table.sort(rows, function(a, b)
		if a.t ~= b.t then
			return a.t < b.t
		end
		return a.index < b.index
	end)
	local start = rows[1] and rows[1].t
	for _, row in ipairs(rows) do
		row.offset = row.t - start
		row.index = nil
	end
	return rows
end

-- Seconds as a clock reading from the timeline's start: "0:00", "12:05", "1:02:03".
function ns.Timeline.Clock(seconds)
	seconds = math.max(0, math.floor(seconds))
	local hours = math.floor(seconds / 3600)
	local minutes = math.floor(seconds % 3600 / 60)
	if hours > 0 then
		return string.format("%d:%02d:%02d", hours, minutes, seconds % 60)
	end
	return string.format("%d:%02d", minutes, seconds % 60)
end
