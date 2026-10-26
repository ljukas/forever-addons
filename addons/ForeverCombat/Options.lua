local ADDON_NAME, ns = ...

-- Options > AddOns > ForeverCombat: a checkbox per module. The registered settings write
-- straight into ForeverCombatDB.settings, and registering one fills in its default.
ns.Options = {}

local function GetVariable(key)
	return "FOREVERCOMBAT_" .. key:upper()
end

function ns.Options.Get(key)
	return ns.db.settings[key]
end

ns.OnInitialize(function()
	local category = Settings.RegisterVerticalLayoutCategory(ADDON_NAME)

	for _, module in ns.Modules.Enumerate() do
		local setting = Settings.RegisterAddOnSetting(
			category,
			GetVariable(module.setting),
			module.setting,
			ns.db.settings,
			Settings.VarType.Boolean,
			module.label,
			Settings.Default.True
		)
		setting:SetValueChangedCallback(function()
			ns.callbacks:TriggerEvent("OptionChanged")
		end)
		Settings.CreateCheckbox(category, setting, module.tooltip)
	end

	Settings.RegisterAddOnCategory(category)
end)
