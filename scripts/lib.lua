-- Shared helpers for the scripts/*.lua SavedVariables readers. Load it with
--   local lib = dofile((arg[0]:match("^(.*)/") or ".") .. "/lib.lua")
local lib = {}

-- Runs a SavedVariables file in an empty environment and returns that environment, so
-- lib.Load(path).ForeverDevDB is the saved table.
function lib.Load(path)
	local chunk = assert(loadfile(path))
	local env = {}
	setfenv(chunk, env)
	chunk()
	return env
end

-- A table's keys sorted: numbers in numeric order before strings, or by value, largest
-- first, when byValue is set.
function lib.SortedKeys(t, byValue)
	local keys = {}
	for key in pairs(t or {}) do
		table.insert(keys, key)
	end
	table.sort(keys, function(a, b)
		if byValue then
			return t[a] > t[b]
		elseif type(a) == type(b) then
			return a < b
		end
		return type(a) == "number"
	end)
	return keys
end

-- A time() stamp as "2026-11-04 18:30", or "?".
function lib.Date(stamp)
	return stamp and os.date("%Y-%m-%d %H:%M", stamp) or "?"
end

return lib
