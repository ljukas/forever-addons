-- Pretty-prints a ForeverDev SavedVariables file. Run via scripts/devlog.sh.
-- Usage: devlog.lua <ForeverDev.lua path> <all|last> <all|errors> [addon] [tag]
local path, sessions, kinds, addon, tag = ...
local lib = dofile((arg[0]:match("^(.*)/") or ".") .. "/lib.lua")

local db = lib.Load(path).ForeverDevDB
if not db or not db.entries then
	print("No ForeverDev data in " .. path)
	return
end
addon = addon ~= "" and addon:lower() or nil
tag = tag ~= "" and tag:lower() or nil

local client = db.client or {}
print(("ForeverDev log: session %s started %s, client %s (interface %s)"):format(
	tostring(db.session),
	db.sessionStarted and os.date("%Y-%m-%d %H:%M:%S", db.sessionStarted) or "?",
	tostring(client.build),
	tostring(client.interface)
))

-- Errors carry no addon, but their message and stack name the file: AddOns/<Name>/...
local function MatchesAddon(entry)
	if entry.addon then
		return entry.addon:lower() == addon
	end
	local text = ((entry.message or "") .. "\n" .. (entry.stack or "")):lower()
	return text:find("addons[/\\]" .. addon .. "[/\\]") ~= nil
end

local shown = 0
for _, entry in ipairs(db.entries) do
	local inSession = sessions == "all" or entry.session == db.session
	local inKinds = kinds == "all" or entry.kind ~= "log"
	local inAddon = not addon or MatchesAddon(entry)
	local inTag = not tag or (entry.tag and entry.tag:lower() == tag)
	if inSession and inKinds and inAddon and inTag then
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
