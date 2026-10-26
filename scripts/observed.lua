-- Pretty-prints ForeverDevDB.observed. Run via scripts/observed.sh.
-- Usage: observed.lua <ForeverDev.lua path> [addon] [filter]
-- Layout: observed[addon][category][entry] = table of fields, see each addon's Knowledge.lua.
local path, addon, filter = ...
local lib = dofile((arg[0]:match("^(.*)/") or ".") .. "/lib.lua")
local SortedKeys = lib.SortedKeys

local db = lib.Load(path).ForeverDevDB
local observed = db and db.observed
if not observed or next(observed) == nil then
	print("Nothing observed yet in " .. path)
	return
end
addon = addon ~= "" and addon:lower() or nil
filter = filter ~= "" and filter:lower() or nil

local function Count(t)
	local count = 0
	for _ in pairs(t) do
		count = count + 1
	end
	return count
end

local function Scalar(key, value)
	if key == "lastSeen" and type(value) == "number" then
		return lib.Date(value)
	elseif type(value) == "number" and value ~= math.floor(value) then
		return string.format("%.2f", value)
	end
	return tostring(value)
end

local function IsFlat(t)
	for _, value in pairs(t) do
		if type(value) == "table" then
			return false
		end
	end
	return true
end

-- A flat table on one line: lists as "a | b", the rest as "key=value, key=value".
local function Inline(t)
	local parts = {}
	if #t == Count(t) then
		for _, value in ipairs(t) do
			table.insert(parts, tostring(value))
		end
		return table.concat(parts, " | ")
	end
	for _, key in ipairs(SortedKeys(t)) do
		table.insert(parts, tostring(key) .. "=" .. Scalar(key, t[key]))
	end
	return table.concat(parts, ", ")
end

-- Plain fields on one line, then a line per table field, nested ones indented further.
local function PrintFields(t, indent)
	local scalars = {}
	for _, key in ipairs(SortedKeys(t)) do
		if type(t[key]) ~= "table" then
			table.insert(scalars, tostring(key) .. "=" .. Scalar(key, t[key]))
		end
	end
	if #scalars > 0 then
		print(indent .. table.concat(scalars, "  "))
	end
	for _, key in ipairs(SortedKeys(t)) do
		local value = t[key]
		if type(value) == "table" then
			if IsFlat(value) then
				print(indent .. tostring(key) .. ": " .. (next(value) and Inline(value) or "-"))
			else
				print(indent .. tostring(key))
				PrintFields(value, indent .. "  ")
			end
		end
	end
end

if not addon then
	print("Addons with observations (scripts/observed.sh <addon>):")
	for _, name in ipairs(SortedKeys(observed)) do
		local sizes = {}
		for _, category in ipairs(SortedKeys(observed[name])) do
			table.insert(sizes, category .. " " .. Count(observed[name][category]))
		end
		print("  " .. name .. ": " .. table.concat(sizes, ", "))
	end
	return
end

local data
for name, categories in pairs(observed) do
	if name:lower() == addon then
		data = categories
	end
end
if not data then
	print("Nothing observed by " .. addon .. " yet.")
	return
end

local shown = 0
for _, category in ipairs(SortedKeys(data)) do
	print("")
	print(category .. ":")
	for _, key in ipairs(SortedKeys(data[category])) do
		if not filter or tostring(key):lower():find(filter, 1, true) then
			shown = shown + 1
			local entry = data[category][key]
			if type(entry) == "table" then
				print("  " .. tostring(key))
				PrintFields(entry, "    ")
			else
				print("  " .. tostring(key) .. " = " .. Scalar(key, entry))
			end
		end
	end
end
if shown == 0 then
	print("(no entries" .. (filter and (" matching " .. filter) or "") .. ")")
end
