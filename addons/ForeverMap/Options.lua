local ADDON_NAME, ns = ...

-- ForeverMapDB.settings and their defaults. A value not saved yet reads as its default, so code
-- that runs before the options panel registers its settings never sees nil.
ns.Options = {}

-- Which way the button bag opens from its button.
ns.Options.DIRECTION = { DOWN = 1, UP = 2, LEFT = 3, RIGHT = 4 }

ns.Options.DEFAULTS = {
	showNodeIcons = true,
	nodeIconSize = 9, -- an estimate until launch: small enough to leave the up/down arrows visible
	showButtonBag = true,
	buttonBagDirection = ns.Options.DIRECTION.DOWN,
}

function ns.Options.Get(key)
	local value = ns.db and ns.db.settings[key]
	if value == nil then
		return ns.Options.DEFAULTS[key]
	end
	return value
end

local L = ns.L

local function GetVariable(key)
	return "FOREVERMAP_" .. key:upper()
end

-- Options > AddOns > ForeverMap. The registered settings write straight into
-- ForeverMapDB.settings (filling in a default where nothing is saved yet), and every change
-- fires OptionChanged.
ns.OnInitialize(function()
	local category, layout = Settings.RegisterVerticalLayoutCategory(ADDON_NAME)
	ns.Options.layout = layout -- the button bag's ignore list adds its own entry to it

	local function Register(key, varType, label)
		local setting = Settings.RegisterAddOnSetting(
			category,
			GetVariable(key),
			key,
			ns.db.settings,
			varType,
			label,
			ns.Options.DEFAULTS[key]
		)
		setting:SetValueChangedCallback(function()
			ns.callbacks:TriggerEvent("OptionChanged")
		end)
		return setting
	end

	local show = Register("showNodeIcons", Settings.VarType.Boolean, L.SHOW_NODE_ICONS)
	local showInitializer = Settings.CreateCheckbox(category, show, L.SHOW_NODE_ICONS_TOOLTIP)

	local size = Register("nodeIconSize", Settings.VarType.Number, L.NODE_ICON_SIZE)
	local options = Settings.CreateSliderOptions(6, 16, 1)
	options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
		return tostring(value)
	end)
	local sizeInitializer = Settings.CreateSlider(category, size, options, L.NODE_ICON_SIZE_TOOLTIP)
	-- The size only matters while the icons are shown (Blizzard's pattern, Graphics settings).
	sizeInitializer:SetParentInitializer(showInitializer, function()
		return show:GetValue()
	end)

	local bag = Register("showButtonBag", Settings.VarType.Boolean, L.SHOW_BUTTON_BAG)
	local bagInitializer = Settings.CreateCheckbox(category, bag, L.SHOW_BUTTON_BAG_TOOLTIP)

	local direction = Register("buttonBagDirection", Settings.VarType.Number, L.BUTTON_BAG_DIRECTION)
	local function GetDirections()
		local container = Settings.CreateControlTextContainer()
		container:Add(ns.Options.DIRECTION.DOWN, L.DIRECTION_DOWN)
		container:Add(ns.Options.DIRECTION.UP, L.DIRECTION_UP)
		container:Add(ns.Options.DIRECTION.LEFT, L.DIRECTION_LEFT)
		container:Add(ns.Options.DIRECTION.RIGHT, L.DIRECTION_RIGHT)
		return container:GetData()
	end
	local directionInitializer = Settings.CreateDropdown(category, direction, GetDirections)
	-- The direction only matters while the bag is on.
	directionInitializer:SetParentInitializer(bagInitializer, function()
		return bag:GetValue()
	end)

	Settings.RegisterAddOnCategory(category)
end)
