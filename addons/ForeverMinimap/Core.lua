local ADDON_NAME, ns = ...

-- Dev-only logging, probing and evidence through ForeverDev (addons/ForeverDev/ForeverDev.lua,
-- scripts/devlog.sh). Without ForeverDev, ns.dev is inert: ns.dev.enabled is false and every
-- call on it does nothing. ns.log(TAG, ...) logs a line tagged TAG, by file:
--   LOADED                   Core.lua
--   SCAN DOT LINE MISS LOOT  Scanner.lua
--   SCALE DRAW               UI/NodeIcons.lua
--   TRACK                    Tracking.lua
--   ITEM                     Dev/NodeItems.lua
--   BAG                      UI/BagButton.lua, ButtonBag.lua
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
	SHOW_NODE_ICONS_TOOLTIP = "Show the herbs, ore and treasure chests your tracking finds as icons on the minimap. They follow the minimap's Icon Scale in Edit Mode.",
	SHOW_BUTTON_BAG = "Gather addon minimap buttons",
	SHOW_BUTTON_BAG_TOOLTIP = "Collect the minimap buttons other addons add into one button on the minimap edge.",
	BUTTON_BAG_DIRECTION = "Open buttons towards",
	DIRECTION_DOWN = "Down",
	DIRECTION_UP = "Up",
	DIRECTION_LEFT = "Left",
	DIRECTION_RIGHT = "Right",
	BUTTON_BAG_SCALE = "Button size",
	BUTTON_BAG_SCALE_TOOLTIP = "How big the gathered buttons are when the bag is open. 100% is the size of a standard minimap button.",
	BAG_TOOLTIP_TOGGLE = "Left-click to open or close the button bag.",
	BAG_TOOLTIP_KEEP = "Right-click to choose buttons to keep out of the bag.",
	KEEP_ON_MINIMAP = "Keep on minimap",
	NO_BUTTONS_FOUND = "No addon buttons found",
	CHOOSE_BUTTONS = "Choose buttons",
	KEEP_ON_MINIMAP_TOOLTIP = "Choose which addon buttons stay on the minimap instead of going into the button bag.",
}

-- Internal events between the modules. Callbacks are called as func(owner, ...).
--   OptionChanged()    a ForeverMinimapDB.settings value changed
--   TrackingChanged()  the minimap tracking types may have changed
--   BagToggled(open)   the button bag was opened or closed (UI/BagButton.lua)
ns.callbacks = CreateFromMixins(CallbackRegistryMixin)
ns.callbacks:OnLoad()
ns.callbacks:GenerateCallbackEvents({ "OptionChanged", "TrackingChanged", "BagToggled" })

-- Modules register setup that needs ForeverMinimapDB. It runs in TOC order once the
-- SavedVariables have loaded.
local initializers = {}

function ns.OnInitialize(func)
	table.insert(initializers, func)
end

EventUtil.ContinueOnAddOnLoaded(ADDON_NAME, function()
	ForeverMinimapDB = ForeverMinimapDB or {}
	ns.db = ForeverMinimapDB
	ns.DB.Migrate(ns.db)

	for _, func in ipairs(initializers) do
		func()
	end
	ns.log("LOADED", "db version", ns.db.version)
end)
