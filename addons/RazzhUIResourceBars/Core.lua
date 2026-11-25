local ADDON_NAME, ns = ...

-- Dev-only logging, probing and evidence through ForeverDev (addons/ForeverDev/ForeverDev.lua,
-- scripts/devlog.sh). Without ForeverDev, ns.dev is inert: ns.dev.enabled is false and every
-- call on it does nothing. ns.log(TAG, ...) logs a line tagged TAG, by file:
--   LOADED          Core.lua
--   POWER           PowerBar.lua, PowerText.lua
--   COST            CostPrediction.lua
--   OFFFORM         OffFormPower.lua
--   REGEN           RegenSpark.lua
--   COMBO           ComboPoints.lua
--   SAVE EDITMODE   EditMode.lua
--   OPTIONS         Options.lua
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
	NUMBERS = "Numbers",
	NUMBERS_DESC = "Show your power as numbers on the bar.",
	NUMBERS_NONE = "Off",
	NUMBERS_HOVER = "On Mouse-over",
	NUMBERS_VALUE = "Value",
	NUMBERS_PERCENT = "Percent",
	NUMBERS_BOTH = "Both",
	REGEN_SPARK = "Regen Spark",
	REGEN_SPARK_DESC = "After a spell spends mana, show a spark that crosses your mana bar in the five seconds before mana regenerates again.",
	OFF_FORM = "Other Powers",
	OFF_FORM_DESC = "Show your mana while in a form, and your energy outside Cat Form once you know it, in a row above the bar.",
	OFF_FORM_HEIGHT = "Other Powers Height",
	COMBO_POINTS = "Combo Points",
	COMBO_POINTS_DESC = "Show your combo points on your target as five slots on top of the bar, as a rogue or in Cat Form.",
	COMBO_POINTS_HEIGHT = "Combo Points Height",
	EDIT_MODE = "Edit Mode",
	EDIT_MODE_TOOLTIP = "Move the power bar and change its size and other settings in Edit Mode.",
}

-- Modules register setup that needs RazzhUIResourceBarsDB. It runs in TOC order once the
-- SavedVariables have loaded.
local initializers = {}

function ns.OnInitialize(func)
	table.insert(initializers, func)
end

EventUtil.ContinueOnAddOnLoaded(ADDON_NAME, function()
	RazzhUIResourceBarsDB = RazzhUIResourceBarsDB or {}
	ns.db = RazzhUIResourceBarsDB
	ns.DB.Migrate(ns.db)

	for _, func in ipairs(initializers) do
		func()
	end
	ns.log("LOADED", "db version", ns.db.version)
end)
