-- Pretty-prints ForeverCombatDB.observed and the learned tick sizes. Run via
-- scripts/combat-knowledge.sh. Layout: addons/ForeverCombat/Engine/Knowledge.lua.
-- Usage: combat-knowledge.lua <ForeverCombat.lua path> [spell name filter]
local path, filter = ...

local chunk = assert(loadfile(path))
local env = {}
setfenv(chunk, env)
chunk()

local db = env.ForeverCombatDB
if not db or not db.observed then
	print("No ForeverCombat data in " .. path)
	return
end
filter = filter and filter ~= "" and filter:lower() or nil

local function SortedKeys(t, byValue)
	local keys = {}
	for key in pairs(t or {}) do
		table.insert(keys, key)
	end
	table.sort(keys, function(a, b)
		if byValue then
			return t[a] > t[b]
		end
		return tostring(a) < tostring(b)
	end)
	return keys
end

-- "3.0s x35, 3.1s x2", most frequent first.
local function Histogram(t, suffix)
	local parts = {}
	for _, key in ipairs(SortedKeys(t, true)) do
		table.insert(parts, key .. (suffix or "") .. " x" .. t[key])
	end
	return #parts > 0 and table.concat(parts, ", ") or "-"
end

-- Learned ticks per spell ID, including finishers' "spellID:points" keys.
local learnedBySpell = {}
for tickKey, learned in pairs(db.ticks or {}) do
	local spellID, points = tostring(tickKey):match("^(%d+):?(%d*)$")
	if spellID then
		local list = learnedBySpell[spellID] or {}
		learnedBySpell[spellID] = list
		table.insert(list, string.format("%s%.1f (n=%d)", points ~= "" and (points .. "pt ") or "", learned.amount, learned.count))
	end
end

local unlisted = {}
local shown = 0
for _, name in ipairs(SortedKeys(db.observed)) do
	if not filter or name:lower():find(filter, 1, true) then
		for _, spellID in ipairs(SortedKeys(db.observed[name])) do
			local stats = db.observed[name][spellID]
			if stats.unlisted then
				table.insert(unlisted, { name = name, spellID = spellID, stats = stats })
			else
				shown = shown + 1
				print("")
				print(string.format(
					"%s  id %s  %s  %s  casts %d  last seen %s",
					name,
					tostring(spellID),
					stats.rank or "",
					stats.kind or "?",
					stats.casts or 0,
					stats.lastSeen and os.date("%Y-%m-%d %H:%M", stats.lastSeen) or "?"
				))
				print("  parsed:      " .. (stats.parsed or "-"))
				local learned = learnedBySpell[tostring(spellID)]
				print("  learned:     " .. (learned and table.concat(learned, ", ") or "-"))
				local ticks = stats.ticks
				if ticks and ticks.count > 0 then
					print(string.format(
						"  ticks:       %d seen, avg %.1f (%d..%d), crits %d, absorbed %d",
						ticks.count,
						ticks.sum / ticks.count,
						ticks.min,
						ticks.max,
						ticks.crits,
						ticks.absorbed
					))
				end
				if stats.powerRatio then
					print(string.format(
						"  vs tooltip:  x%.2f .. x%.2f",
						stats.powerRatio.min,
						stats.powerRatio.max
					))
				end
				print("  intervals:   " .. Histogram(stats.intervals, "s"))
				print("  first tick:  " .. Histogram(stats.firstTick, "s"))
				print("  per effect:  " .. Histogram(stats.ticksPerEffect))
				print("  misses:      " .. Histogram(stats.misses))
				print("  avoided:     " .. Histogram(stats.avoided))
				for _, sample in ipairs(stats.missSamples or {}) do
					print("    " .. sample)
				end
				print("  description: " .. (stats.description or "-"))
			end
		end
	end
end

if #unlisted > 0 then
	print("")
	print("Not on the list, but read like a DoT or HoT:")
	for _, item in ipairs(unlisted) do
		print(string.format(
			"  %s  id %s  casts %d: %s",
			item.name,
			tostring(item.spellID),
			item.stats.casts or 0,
			item.stats.description or ""
		))
	end
end
if shown == 0 and #unlisted == 0 then
	print("(nothing observed yet" .. (filter and (" matching " .. filter) or "") .. ")")
end
