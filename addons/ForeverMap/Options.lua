local ADDON_NAME, ns = ...

-- ForeverMapDB.settings and their defaults. A value not saved yet reads as its default, so code
-- that runs before the options panel registers its settings never sees nil.
ns.Options = {}

ns.Options.DEFAULTS = {
	showNodeIcons = true,
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
	local category = Settings.RegisterVerticalLayoutCategory(ADDON_NAME)

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

	Settings.RegisterAddOnCategory(category)
end)
