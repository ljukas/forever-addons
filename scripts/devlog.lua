-- Pretty-prints a ForeverDev SavedVariables file. Run via scripts/devlog.sh.
-- Usage: devlog.lua <ForeverDev.lua path> <all|last> <all|errors> [addon[,addon...]] [tag]
local path, sessions, kinds, addon, tag = ...
local lib = dofile((arg[0]:match("^(.*)/") or ".") .. "/lib.lua")

local db = lib.Load(path).ForeverDevDB
if not db or not db.entries then
	print("No ForeverDev data in " .. path)
	return
end
local addons
for name in (addon or ""):gmatch("[^,%s]+") do
	addons = addons or {}
	table.insert(addons, name:lower())
end
tag = tag ~= "" and tag:lower() or nil

local client = db.client or {}
print(("ForeverDev log: session %s started %s, client %s (interface %s)"):format(
	tostring(db.session),
	db.sessionStarted and os.date("%Y-%m-%d %H:%M:%S", db.sessionStarted) or "?",
	tostring(client.build),
	tostring(client.interface)
))


local ADDON_PATH = "addons[/\\]([^/\\]+)[/\\]"

-- The first addon other than Blizzard's (and except, if given, skip) whose file
-- (Interface/AddOns/<Name>/...) text names, lowercased.
local function NamedAddon(text, skip)
	for name in (text or ""):lower():gmatch(ADDON_PATH) do
		if name ~= skip and not name:find("^blizzard_") then
			return name
		end
	end
end

-- The addon an entry belongs to, lowercased, or nil. Errors carry no addon, so this follows
-- ForeverDev's bucketOf: the addon their message names, else the first in their stack after
-- ForeverDev's own error handler.
local function OwnerOf(entry)
	if entry.addon then
		return entry.addon:lower()
	end
	return NamedAddon(entry.message) or NamedAddon(entry.stack, "foreverdev")
end

-- Whether entry passes the kind and tag filters and, when name is given, belongs to that addon.
local function PassesFilters(entry, name)
	if kinds ~= "all" and entry.kind == "log" then
		return false
	end
	if tag and not (entry.tag and entry.tag:lower() == tag) then
		return false
	end
	return not name or OwnerOf(entry) == name
end

-- Whether entry passes every filter but the session one. Under an addon filter, errors that
-- name no addon show too, since they could be any addon's.
local function Matches(entry)
	if not PassesFilters(entry) then
		return false
	end
	if not addons then
		return true
	end
	local owner = OwnerOf(entry)
	if not owner then
		return true
	end
	for _, name in ipairs(addons) do
		if owner == name then
			return true
		end
	end
	return false
end

local shown = 0
for _, entry in ipairs(db.entries) do
	if (sessions == "all" or entry.session == db.session) and Matches(entry) then
		shown = shown + 1
		local label = entry.kind:upper()
		if entry.count and entry.count > 1 then
			label = label .. " x" .. entry.count
		end
		local prefix = sessions == "all" and ("#" .. tostring(entry.session) .. " ") or ""
		local source = entry.addon and (entry.addon .. ": ") or ""
		local message = entry.tag and (entry.tag .. " " .. entry.message) or entry.message
		print(("%s[%s] %s %s%s"):format(prefix, os.date("%H:%M:%S", entry.time), label, source, message))
		if entry.stack and entry.stack ~= "" then
			print((entry.stack:gsub("\n*$", ""):gsub("([^\n]+)", "    %1")))
		end
	end
end
if shown == 0 then
	print("(no matching entries)")
end

-- For each addon asked about (or all of them) that has nothing in the latest session, say
-- where its latest entries are: another worktree's /rl may have started a newer session since
-- this one's test ran.
if sessions ~= "all" then
	for _, name in ipairs(addons or { false }) do
		local now, latest = false, nil
		for _, entry in ipairs(db.entries) do
			if PassesFilters(entry, name or nil) then
				if entry.session == db.session then
					now = true
				elseif (entry.session or 0) > (latest and latest.session or 0) then
					latest = entry
				end
			end
		end
		if not now and latest then
			print(
				("%s: nothing in this session; the latest are from session %s (%s), --all shows them."):format(
					name or "Matching entries",
					tostring(latest.session),
					os.date("%Y-%m-%d %H:%M:%S", latest.time)
				)
			)
		end
	end
end
