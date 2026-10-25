-- Pretty-prints a ForeverDev SavedVariables file. Run via scripts/devlog.sh.
-- Usage: devlog.lua <ForeverDev.lua path> <all|last> <all|errors>
local path, sessions, kinds = ...

local chunk = assert(loadfile(path))
local env = {}
setfenv(chunk, env)
chunk()

local db = env.ForeverDevDB
if not db or not db.entries then
	print("No ForeverDev data in " .. path)
	return
end

local client = db.client or {}
print(("ForeverDev log: session %s started %s, client %s (interface %s)"):format(
	tostring(db.session),
	db.sessionStarted and os.date("%Y-%m-%d %H:%M:%S", db.sessionStarted) or "?",
	tostring(client.build),
	tostring(client.interface)
))

local shown = 0
for _, entry in ipairs(db.entries) do
	local inSession = sessions == "all" or entry.session == db.session
	local inKinds = kinds == "all" or entry.kind ~= "log"
	if inSession and inKinds then
		shown = shown + 1
		local label = entry.kind:upper()
		if entry.count and entry.count > 1 then
			label = label .. " x" .. entry.count
		end
		local prefix = sessions == "all" and ("#" .. tostring(entry.session) .. " ") or ""
		local source = entry.addon and (entry.addon .. ": ") or ""
		print(("%s[%s] %s %s%s"):format(prefix, os.date("%H:%M:%S", entry.time), label, source, entry.message))
		if entry.stack and entry.stack ~= "" then
			print((entry.stack:gsub("\n*$", ""):gsub("([^\n]+)", "    %1")))
		end
	end
end
if shown == 0 then
	print("(no matching entries)")
end
