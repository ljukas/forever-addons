local ADDON_NAME, ns = ...

-- Dev-only logging, probing and evidence through ForeverDev (addons/ForeverDev/ForeverDev.lua,
-- scripts/devlog.sh). Without ForeverDev, ns.dev is inert: ns.dev.enabled is false and every
-- call on it does nothing. ns.log(TAG, ...) logs a line tagged TAG. Tags by file:
--   Core.lua       LOADED, KEY (the character key, and legacy sections adopted in Database.lua)
--   Tracker.lua    RUN (entering, leaving, run decisions, copy numbers, resets), KILL (each kill
--                  message: parsed, unparsed or secret)
--   Ranks.lua      RANK (each creature's rank from deaths, or why none; encounters won)
--   Party.lua      PARTY (each party member recorded with a kill)
--   Events.lua     EVENT (each timeline event recorded: boss, wipe, death, level, loot)
--   UI/Journal.lua UI
--   Launcher.lua   UI
--   Dev/Probe.lua  PROBE
local function Nop() end

-- Returns t (or a new table) with every missing field a function that does nothing.
function ns.Inert(t)
	return setmetatable(t or {}, {
		__index = function()
			return Nop
		end,
	})
end

ns.dev = ForeverDev and ForeverDev.For(ADDON_NAME) or ns.Inert({ enabled = false })

function ns.log(tag, ...)
	ns.dev:Log(tag, ...)
end

local characterKey
local adopted

-- "Name-Surname", or nil while the client doesn't give both (or keeps them secret). On Forever
-- UnitName's second value is the surname, and Blizzard keeps first name and surname unique
-- together. Not the realm: since Forever's 1.60.1 hotfix the realm APIs return "" or 0.
function ns.CharacterKey()
	if not characterKey then
		local name, surname = UnitName("player")
		-- Secrecy first: a secret value can't even be tested for nil.
		if issecretvalue(name) or issecretvalue(surname) then
			return nil
		end
		if type(name) == "string" and name ~= "" and type(surname) == "string" and surname ~= "" then
			characterKey = name .. "-" .. surname
			ns.dev:LogOnce("character key", "KEY", "character key", characterKey)
		end
	end
	-- The character's runs from before the hotfix, if still under its old key, become its own.
	if characterKey and not adopted and ns.db then
		adopted = true
		ns.DB.AdoptLegacy(characterKey)
	end
	return characterKey
end

-- Modules register setup that needs ForeverDungeonXPDB. It runs in TOC order once the
-- SavedVariables have loaded.
local initializers = {}

function ns.OnInitialize(func)
	table.insert(initializers, func)
end

EventUtil.ContinueOnAddOnLoaded(ADDON_NAME, function()
	ForeverDungeonXPDB = ForeverDungeonXPDB or {}
	ns.db = ForeverDungeonXPDB
	ns.DB.Migrate(ns.db)
	-- A key read before the SavedVariables loaded hasn't adopted its legacy section yet.
	ns.CharacterKey()

	for _, func in ipairs(initializers) do
		func()
	end
	ns.log("LOADED", "db version", ns.db.version)
end)
