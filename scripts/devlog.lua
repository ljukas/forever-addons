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

-- Errors carry no addon, but their message and stack name the file: AddOns/<Name>/...
local function MatchesAddon(entry, name)
	if entry.addon then
		return entry.addon:lower() == name
	end
	local text = ((entry.message or "") .. "\n" .. (entry.stack or "")):lower()
	return text:find("addons[/\\]" .. name .. "[/\\]") ~= nil
end

-- Whether entry passes the kind, addon and tag filters (not the session one).
local function Matches(entry)
	if kinds ~= "all" and entry.kind == "log" then
		return false
	end
	if tag and not (entry.tag and entry.tag:lower() == tag) then
		return false
	end
	if not addons then
		return true
	end
	for _, name in ipairs(addons) do
		if MatchesAddon(entry, name) then
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
	-- Another worktree's /rl may have started a newer session since this one's test ran.
	local latest
	for _, entry in ipairs(db.entries) do
		if Matches(entry) and (not latest or entry.session > latest.session) then
			latest = entry
		end
	end
	if sessions ~= "all" and latest then
		print(
			("The latest matching entries are from session %s (%s); --all shows them."):format(
				tostring(latest.session),
				os.date("%Y-%m-%d %H:%M:%S", latest.time)
			)
		)
	end
end
