local ADDON_NAME, ns = ...

-- Dev-only logging, probing and evidence through ForeverDev (addons/ForeverDev/ForeverDev.lua,
-- scripts/devlog.sh). Without ForeverDev, ns.dev is inert: ns.dev.enabled is false and every
-- call on it does nothing. ns.log(TAG, ...) logs a line tagged TAG, by file:
--   LOADED          Core.lua
--   DEFER APPLY     Layout.lua
--   LAYOUT          HealthBar.lua
--   POWER           PowerBar.lua
--   SAVE EDITMODE   EditMode.lua
--   ART             Dev/ArtProbe.lua
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

-- enUS only for now.
ns.L = {
	POWER_BAR = "Player Power Bar",
	WIDTH = "Width",
	HEIGHT = "Height",
	SMOOTH = "Smooth Fill",
	SMOOTH_DESC = "Slide the bar to each new value instead of jumping to it.",
}

-- Modules register setup that needs ForeverUnitFramesDB. It runs in TOC order once the
-- SavedVariables have loaded.
local initializers = {}

function ns.OnInitialize(func)
	table.insert(initializers, func)
end

EventUtil.ContinueOnAddOnLoaded(ADDON_NAME, function()
	ForeverUnitFramesDB = ForeverUnitFramesDB or {}
	ns.db = ForeverUnitFramesDB
	ns.DB.Migrate(ns.db)

	for _, func in ipairs(initializers) do
		func()
	end
	ns.log("LOADED", "db version", ns.db.version)
end)
