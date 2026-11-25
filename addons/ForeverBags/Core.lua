local ADDON_NAME, ns = ...

-- Dev-only logging, probing and evidence through ForeverDev (addons/ForeverDev/ForeverDev.lua,
-- scripts/devlog.sh). Without ForeverDev, ns.dev is inert: ns.dev.enabled is false and every
-- call on it does nothing. ns.log(TAG, ...) logs a line tagged TAG, by file:
--   LOADED         Core.lua
--   DB             Database.lua
--   SCAN           Items.lua
--   DELETE         Delete.lua
--   WINDOW         Window.lua
--   FULL RELOOT    Loot.lua
--   BUTTON         BagButton.lua
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
	EMPTY = "Nothing in your bags can be sold to a vendor.",
	IGNORE_HINT = "Click to never list this item again.",
	BUTTON_TOOLTIP = "Cheapest items",
	BUTTON_TOOLTIP_TEXT = "Show the items in your bags that are worth the least to a vendor.",
	RESET_IGNORED = "Reset ignored items",
	RESET_IGNORED_TOOLTIP = "List every item again, including the ones you clicked to ignore on this character.",
}

-- Modules register setup that needs ForeverBagsDB. It runs in TOC order once the
-- SavedVariables have loaded.
local initializers = {}

function ns.OnInitialize(func)
	table.insert(initializers, func)
end

EventUtil.ContinueOnAddOnLoaded(ADDON_NAME, function()
	ForeverBagsDB = ForeverBagsDB or {}
	ns.db = ForeverBagsDB
	ns.DB.Migrate(ns.db)

	for _, func in ipairs(initializers) do
		func()
	end
	ns.log("LOADED", "db version", ns.db.version)
end)
