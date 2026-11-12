local ADDON_NAME, ns = ...

-- Dev-only logging, probing and evidence through ForeverDev (addons/ForeverDev/ForeverDev.lua,
-- scripts/devlog.sh). Without ForeverDev, ns.dev is inert: ns.dev.enabled is false and every
-- call on it does nothing. ns.log(TAG, ...) logs a line tagged TAG. Tags by file:
--   Core.lua       LOADED
--   Tracker.lua    RUN (entering, leaving, run decisions, copy numbers, resets), KILL (each kill
--                  message: parsed, unparsed or secret)
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

-- "Name-Realm", or nil while the client doesn't give the name or realm yet (or keeps them secret).
function ns.CharacterKey()
	if not characterKey then
		local name = UnitName("player")
		local realm = GetNormalizedRealmName()
		-- The realm can still be empty early in a session; the key would then be wrong for good.
		if name and realm and not issecretvalue(name) and not issecretvalue(realm) and name ~= "" and realm ~= "" then
			characterKey = name .. "-" .. realm
		end
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

	for _, func in ipairs(initializers) do
		func()
	end
	ns.log("LOADED", "db version", ns.db.version)
end)
