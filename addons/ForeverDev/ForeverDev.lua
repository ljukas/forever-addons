-- ForeverDev: development-only helpers. Never released.
--
-- * /rl, a "Reload UI" keybinding and the minimap addon compartment all reload the UI.
-- * Lua errors and ADDON_ACTION_BLOCKED/FORBIDDEN (taint) are recorded in ForeverDevDB.entries.
-- * Other addons log and keep evidence through the ForeverDev API below. They reach it through
--   the ns.dev / ns.log shim in their Core.lua, which does nothing when ForeverDev isn't loaded.
-- * Probes.lua logs what the client restricts where, for every addon.
--
-- SavedVariables are only written to disk on /reload, logout or exit, after which
-- scripts/devlog.sh prints the log and scripts/observed.sh the evidence.
--
-- ForeverDevDB layout:
--   entries  = list of { kind = "error"|"blocked"|"log", session, time, message, addon?, tag?,
--              stack?, count? }, the last MAX_ENTRIES of them
--   observed = { [addonName] = { ... } }, evidence the addons keep across sessions (Observed)
--   session, sessionStarted, client = { build, interface }

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

-- The API. Without ForeverDev the shim's ns.dev is inert: every method call on it does nothing
-- and returns nil. So code that always runs may call ns.dev's methods, but anything that needs
-- a result (Observed, the ForeverDev.* helpers) only belongs in code that runs with ForeverDev:
-- Dev/ files and Knowledge modules, which check ns.dev.enabled.
ForeverDev = {}

---@class ForeverDevLogger
---@field enabled boolean
---@field addonName string
---@field once table<any, boolean>
---@field last table<any, any>
local LoggerMixin = {}

-- Logs a line for scripts/devlog.sh. tag is a short upper-case word (TICK, GATHER, ...) that
-- devlog.sh --tag filters on; the rest is joined with spaces, secret values as <secret>.
function LoggerMixin:Log(tag, ...)
	local parts = {}
	for i = 1, select("#", ...) do
		parts[i] = safeToString((select(i, ...)))
	end
	local message = table.concat(parts, " ")
	if #message > MAX_LOG_LENGTH then
		message = message:sub(1, MAX_LOG_LENGTH) .. "…"
	end
	addEntry({ kind = "log", addon = self.addonName, tag = safeToString(tag), message = message })
end

-- Logs only the first time key comes up this session (or since /fdev clear).
function LoggerMixin:LogOnce(key, tag, ...)
	if not self.once[key] then
		self.once[key] = true
		self:Log(tag, ...)
	end
end

-- Logs when value differs from the one last passed with key, for state that is checked often
-- but changes rarely. value must not be secret.
function LoggerMixin:LogChanged(key, value, tag, ...)
	if self.last[key] ~= value then
		self.last[key] = value
		self:Log(tag, ...)
	end
end

-- Returns the addon's evidence table at ForeverDevDB.observed[addonName][key1][key2]...,
-- creating it. Fields of defaults (may be nil) it doesn't have yet are filled in, tables as
-- copies, so fields added later appear on old entries too. Kept across sessions until
-- /fdev forget.
function LoggerMixin:Observed(defaults, ...)
	local node = ForeverDevDB.observed
	local keys = { self.addonName, ... }
	for i = 1, #keys do
		node[keys[i]] = node[keys[i]] or {}
		node = node[keys[i]]
	end
	for field, value in pairs(defaults or {}) do
		if node[field] == nil then
			node[field] = type(value) == "table" and CopyTable(value) or value
		end
	end
	return node
end

local loggers = {}

-- Returns the addon's logger; the shim in its Core.lua keeps it as ns.dev.
---@return ForeverDevLogger
function ForeverDev.For(addonName)
	local logger = loggers[addonName]
	if not logger then
		logger = CreateFromMixins(LoggerMixin)
		logger.enabled = true
		logger.addonName = addonName
		logger.once = {}
		logger.last = {}
		loggers[addonName] = logger
	end
	return logger
end

-- The circumstances a probe result holds in, as text and key for LogOnce: the instance type
-- and combat state, plus for a unit whether it's hostile and a player, e.g. "party combat
-- hostile npc".
function ForeverDev.Situation(unit)
	local _, instanceType = IsInInstance()
	local situation = instanceType .. " " .. (InCombatLockdown() and "combat" or "idle")
	if unit then
		if not UnitExists(unit) then
			return situation .. " nounit"
		end
		situation = string.format(
			"%s %s %s",
			situation,
			UnitCanAttack("player", unit) and "hostile" or "friendly",
			UnitIsPlayer(unit) and "player" or "npc"
		)
	end
	return situation
end

-- Takes name, value pairs and returns the names whose values are secret ("guid health"), or
-- "none".
function ForeverDev.SecretNames(...)
	local names = {}
	for i = 1, select("#", ...), 2 do
		if issecretvalue((select(i + 1, ...))) then
			table.insert(names, (select(i, ...)))
		end
	end
	return #names > 0 and table.concat(names, " ") or "none"
end

-- Describes a pcall's result for the log: "error <message>", "none", "secret", or the value
-- through format (tostring by default) when it's readable.
---@param format? fun(value: any): string
function ForeverDev.Describe(ok, value, format)
	if not ok then
		return "error " .. safeToString(value)
	elseif value == nil then
		return "none"
	elseif issecretvalue(value) then
		return "secret"
	end
	return (format or tostring)(value)
end

-- Evidence helpers for Observed tables.

-- Counts key in a histogram { [key] = count }.
function ForeverDev.Count(histogram, key)
	histogram[key] = (histogram[key] or 0) + 1
end

-- Widens range { min, max } to include value.
function ForeverDev.Extend(range, value)
	range.min = math.min(range.min or value, value)
	range.max = math.max(range.max or value, value)
end

-- Appends item to list, keeping only the last max items.
function ForeverDev.Sample(list, item, max)
	table.insert(list, item)
	while #list > max do
		table.remove(list, 1)
	end
end

function ForeverDev_OnAddonCompartmentClick()
	ReloadUI()
end

EventUtil.ContinueOnAddOnLoaded(ADDON_NAME, function()
	ForeverDevDB = ForeverDevDB or {}
	ForeverDevDB.entries = ForeverDevDB.entries or {}
	ForeverDevDB.observed = ForeverDevDB.observed or {}
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

-- Drops an addon's evidence, e.g. after its data was corrected. The name ignores case.
local function forget(addonName)
	for name in pairs(ForeverDevDB.observed) do
		if name:lower() == addonName then
			ForeverDevDB.observed[name] = nil
			print("ForeverDev: forgot what " .. name .. " observed.")
			return
		end
	end
	print("ForeverDev: nothing observed for " .. addonName .. ".")
end

SLASH_FOREVERDEV_RELOAD1 = "/rl"
SlashCmdList.FOREVERDEV_RELOAD = function()
	ReloadUI()
end

SLASH_FOREVERDEV1 = "/fdev"
SlashCmdList.FOREVERDEV = function(input)
	local command, argument = strsplit(" ", strtrim(input or ""):lower(), 2)
	if command == "clear" then
		wipe(ForeverDevDB.entries)
		wipe(errorsBySignature)
		-- So LogOnce and LogChanged lines show up again.
		for _, logger in pairs(loggers) do
			wipe(logger.once)
			wipe(logger.last)
		end
		print("ForeverDev: log cleared.")
	elseif command == "errors" then
		printErrors()
	elseif command == "forget" and argument then
		forget(strtrim(argument))
	else
		print("ForeverDev: session " .. session .. ", " .. #ForeverDevDB.entries .. " stored entries.")
		print("  /rl - reload UI   /fdev errors - list this session's errors   /fdev clear - clear the log")
		print("  /fdev forget <addon> - drop what that addon observed")
	end
end
