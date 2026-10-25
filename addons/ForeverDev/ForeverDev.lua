-- ForeverDev: development-only helpers. Never released.
--
-- * /rl, a "Reload UI" keybinding and the minimap addon compartment all reload the UI.
-- * Lua errors and ADDON_ACTION_BLOCKED/FORBIDDEN (taint) are recorded in ForeverDevDB.
-- * Other addons can log through ForeverDev_Log(addonName, ...).
--
-- SavedVariables are only written to disk on /reload, logout or exit, after which
-- scripts/devlog.sh prints the log so it can be inspected outside the game.

local ADDON_NAME = ...

local MAX_ENTRIES = 500
local MAX_LOG_LENGTH = 2000

BINDING_HEADER_FOREVERDEV = ADDON_NAME
BINDING_NAME_FOREVERDEV_RELOADUI = "Reload UI"

-- ForeverDevDB is assigned when SavedVariables load (ADDON_LOADED). Anything
-- recorded before then is buffered and flushed into the new session.
local session
local pending = {}

-- Identical errors within a session are counted instead of stored again.
local errorsBySignature = {}

local function safeToString(value)
	if issecretvalue and issecretvalue(value) then
		return "<secret>"
	end
	return tostring(value)
end

local function addEntry(entry)
	entry.time = entry.time or time()
	if not session then
		table.insert(pending, entry)
		return
	end
	entry.session = session
	local entries = ForeverDevDB.entries
	table.insert(entries, entry)
	while #entries > MAX_ENTRIES do
		local removed = table.remove(entries, 1)
		if removed.kind == "error" then
			errorsBySignature[removed.message] = nil
		end
	end
end

local function recordError(message)
	local text = safeToString(message)
	local existing = errorsBySignature[text]
	if existing then
		existing.count = existing.count + 1
		return
	end
	local entry = { kind = "error", message = text, stack = debugstack(3), count = 1 }
	errorsBySignature[text] = entry
	addEntry(entry)
end

local previousErrorHandler = geterrorhandler()
seterrorhandler(function(message, ...)
	-- Never let a bug in the recorder hide the original error.
	pcall(recordError, message)
	return previousErrorHandler(message, ...)
end)

function ForeverDev_Log(addonName, ...)
	local parts = {}
	for i = 1, select("#", ...) do
		parts[i] = safeToString((select(i, ...)))
	end
	local message = table.concat(parts, " ")
	if #message > MAX_LOG_LENGTH then
		message = message:sub(1, MAX_LOG_LENGTH) .. "…"
	end
	addEntry({ kind = "log", addon = safeToString(addonName), message = message })
end

function ForeverDev_OnAddonCompartmentClick()
	ReloadUI()
end

EventUtil.ContinueOnAddOnLoaded(ADDON_NAME, function()
	ForeverDevDB = ForeverDevDB or {}
	ForeverDevDB.entries = ForeverDevDB.entries or {}
	ForeverDevDB.session = (ForeverDevDB.session or 0) + 1
	session = ForeverDevDB.session

	local _, build, _, interface = GetBuildInfo()
	ForeverDevDB.sessionStarted = time()
	ForeverDevDB.client = { build = build, interface = interface }

	for _, entry in ipairs(pending) do
		addEntry(entry)
	end
	pending = nil

	-- Show errors in-game too (an error-capture addon like BugSack may still swallow them).
	C_CVar.SetCVar("scriptErrors", "1")
end)

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_ACTION_BLOCKED")
eventFrame:RegisterEvent("ADDON_ACTION_FORBIDDEN")
eventFrame:SetScript("OnEvent", function(_, event, addonName, func)
	addEntry({ kind = "blocked", addon = safeToString(addonName), message = event .. ": " .. safeToString(func) })
end)

local function printErrors()
	local count = 0
	for _, entry in ipairs(ForeverDevDB.entries) do
		if entry.session == session and entry.kind ~= "log" then
			count = count + 1
			print(("|cffff5555[%s]|r %s"):format(entry.kind, entry.message))
		end
	end
	print(("ForeverDev: %d error(s)/blocked action(s) this session."):format(count))
end

SLASH_FOREVERDEV_RELOAD1 = "/rl"
SlashCmdList.FOREVERDEV_RELOAD = function()
	ReloadUI()
end

SLASH_FOREVERDEV1 = "/fdev"
SlashCmdList.FOREVERDEV = function(input)
	local command = strtrim(input or ""):lower()
	if command == "clear" then
		wipe(ForeverDevDB.entries)
		wipe(errorsBySignature)
		print("ForeverDev: log cleared.")
	elseif command == "errors" then
		printErrors()
	else
		print("ForeverDev: session " .. session .. ", " .. #ForeverDevDB.entries .. " stored entries.")
		print("  /rl - reload UI   /fdev errors - list this session's errors   /fdev clear - clear the log")
	end
end
