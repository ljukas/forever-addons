local ADDON_NAME, ns = ...

-- ForeverMinimapDB.settings and their defaults. A value not saved yet reads as its default, so code
-- that runs before the options panel registers its settings never sees nil.
ns.Options = {}

-- Which way the button bag opens from its button.
ns.Options.DIRECTION = { DOWN = 1, UP = 2, LEFT = 3, RIGHT = 4 }

ns.Options.DEFAULTS = {
	showNodeIcons = true,
	showButtonBag = true,
	buttonBagDirection = ns.Options.DIRECTION.DOWN,
	buttonBagScale = 1,
}

-- The range of the gathered buttons' size, as a fraction of a standard minimap button's (31 px).
ns.Options.SCALE_MIN, ns.Options.SCALE_MAX, ns.Options.SCALE_STEP = 0.5, 1.5, 0.05

function ns.Options.Get(key)
	local value = ns.db and ns.db.settings[key]
	if value == nil then
		return ns.Options.DEFAULTS[key]
	end
	return value
end

local L = ns.L

local function GetVariable(key)
	return "FOREVERMINIMAP_" .. key:upper()
end

-- Options > AddOns > ForeverMinimap. The registered settings write straight into
-- ForeverMinimapDB.settings (filling in a default where nothing is saved yet), and every change
-- fires OptionChanged.
ns.OnInitialize(function()
	local category, layout = Settings.RegisterVerticalLayoutCategory(ADDON_NAME)

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

	-- No size option: the icons follow Edit Mode's minimap icon scale (UI/NodeIcons.lua).
	-- Greyed out, with the reason, on a client that keeps addons from finding the nodes (Scanner.lua).
	local blocked = ns.Scanner.Blocked()
	local show = Register("showNodeIcons", Settings.VarType.Boolean, L.SHOW_NODE_ICONS)
	local showInitializer =
		Settings.CreateCheckbox(category, show, blocked and L.NODE_ICONS_BLOCKED or L.SHOW_NODE_ICONS_TOOLTIP)
	showInitializer:AddModifyPredicate(function()
		return not blocked
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

	local scale = Register("buttonBagScale", Settings.VarType.Number, L.BUTTON_BAG_SCALE)
	local scaleOptions = Settings.CreateSliderOptions(ns.Options.SCALE_MIN, ns.Options.SCALE_MAX, ns.Options.SCALE_STEP)
	-- Rounded, so a step that lands on 0.6999 still reads 70%.
	scaleOptions:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
		return FormatPercentage(value, true)
	end)
	local scaleInitializer = Settings.CreateSlider(category, scale, scaleOptions, L.BUTTON_BAG_SCALE_TOOLTIP)
	scaleInitializer:SetParentInitializer(bagInitializer, function()
		return bag:GetValue()
	end)

	-- The buttons found change at runtime, so the panel opens the same menu as the bag button's
	-- right click. The click handler gets the clicked button, which the menu anchors to.
	local keepInitializer = CreateSettingsButtonInitializer(L.KEEP_ON_MINIMAP, L.CHOOSE_BUTTONS, function(button)
		ns.ButtonBag.OpenIgnoreMenu(button)
	end, L.KEEP_ON_MINIMAP_TOOLTIP, true)
	keepInitializer:SetParentInitializer(bagInitializer, function()
		return bag:GetValue()
	end)
	layout:AddInitializer(keepInitializer)

	Settings.RegisterAddOnCategory(category)
end)
