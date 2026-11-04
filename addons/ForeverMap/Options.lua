local ADDON_NAME, ns = ...

-- ForeverMapDB.settings and their defaults. A value not saved yet reads as its default, so code
-- that runs before the options panel registers its settings never sees nil.
ns.Options = {}

-- Which way the button bag opens from its button.
ns.Options.DIRECTION = { DOWN = 1, UP = 2, LEFT = 3, RIGHT = 4 }

ns.Options.DEFAULTS = {
	showNodeIcons = true,
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
	local show = Register("showNodeIcons", Settings.VarType.Boolean, L.SHOW_NODE_ICONS)
	Settings.CreateCheckbox(category, show, L.SHOW_NODE_ICONS_TOOLTIP)

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
