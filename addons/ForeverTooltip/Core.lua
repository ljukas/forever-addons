local ADDON_NAME, ns = ...

-- Dev-only logging, probing and evidence through ForeverDev (addons/ForeverDev/ForeverDev.lua,
-- scripts/devlog.sh). Without ForeverDev, ns.dev is inert: ns.dev.enabled is false and every
-- call on it does nothing. ns.log(TAG, ...) logs a line tagged TAG, by file:
--   LOADED        Core.lua
--   COLOR LEVEL   Colors.lua
--   ANCHOR        Anchor.lua
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

-- enUS only for now. Blizzard's own global strings are used where one exists.
ns.L = {
	CURSOR_ANCHOR = "Tooltip follows the cursor",
	CURSOR_ANCHOR_TOOLTIP = "Show tooltips for players, creatures and objects in the world next to the mouse cursor instead of at the tooltip position set in Edit Mode.",
	CURSOR_DIRECTION = "Tooltip grows towards",
	CURSOR_DIRECTION_TOOLTIP = "Which side of the mouse cursor the tooltip appears on.",
	DIRECTION_DOWN_RIGHT = "Down and right",
	DIRECTION_DOWN_LEFT = "Down and left",
	DIRECTION_UP_RIGHT = "Up and right",
	DIRECTION_UP_LEFT = "Up and left",
}

-- Modules register setup that needs ForeverTooltipDB. It runs in TOC order once the
-- SavedVariables have loaded.
local initializers = {}

function ns.OnInitialize(func)
	table.insert(initializers, func)
end

EventUtil.ContinueOnAddOnLoaded(ADDON_NAME, function()
	ForeverTooltipDB = ForeverTooltipDB or {}
	ns.db = ForeverTooltipDB
	ns.DB.Migrate(ns.db)

	for _, func in ipairs(initializers) do
		func()
	end
	ns.log("LOADED", "db version", ns.db.version)
end)
