local ADDON_NAME, ns = ...

-- Dev-only logging, probing and evidence through ForeverDev (addons/ForeverDev/ForeverDev.lua,
-- scripts/devlog.sh). Without ForeverDev, ns.dev is inert: ns.dev.enabled is false and every
-- call on it does nothing. ns.log(TAG, ...) logs a line tagged TAG, by file:
--   LOADED                 Core.lua
--   SCAN DOT LINE MISS     Scanner.lua
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
	SHOW_NODE_ICONS = "Show icons on tracked nodes",
	SHOW_NODE_ICONS_TOOLTIP = "Show the herbs and ore your tracking finds as icons on the minimap.",
	NODE_ICON_SIZE = "Icon size",
	NODE_ICON_SIZE_TOOLTIP = "Size of the node icons on the minimap. Larger icons can cover the arrows that show a node above or below you.",
}

-- Internal events between the modules. Callbacks are called as func(owner, ...).
--   OptionChanged()    a ForeverMapDB.settings value changed
--   TrackingChanged()  the minimap tracking types may have changed
ns.callbacks = CreateFromMixins(CallbackRegistryMixin)
ns.callbacks:OnLoad()
ns.callbacks:GenerateCallbackEvents({ "OptionChanged", "TrackingChanged" })

-- Modules register setup that needs ForeverMapDB. It runs in TOC order once the
-- SavedVariables have loaded.
local initializers = {}

function ns.OnInitialize(func)
	table.insert(initializers, func)
end

EventUtil.ContinueOnAddOnLoaded(ADDON_NAME, function()
	ForeverMapDB = ForeverMapDB or {}
	ns.db = ForeverMapDB
	ns.DB.Migrate(ns.db)

	for _, func in ipairs(initializers) do
		func()
	end
	ns.log("LOADED", "db version", ns.db.version)
end)
