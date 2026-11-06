local ADDON_NAME, ns = ...

-- Options > AddOns > ForeverCombat: a checkbox per module, and under it, indented and greyed out
-- while the module is off, one for its portrait cue if it has one. The registered settings write
-- straight into ForeverCombatDB.settings, and registering one fills in its default.
ns.Options = {}

local function GetVariable(key)
	return "FOREVERCOMBAT_" .. key:upper()
end

function ns.Options.Get(key)
	return ns.db.settings[key]
end

-- Registers a boolean setting, on by default, and adds its checkbox. Returns the initializer.
local function AddCheckbox(category, key, label, tooltip)
	local setting = Settings.RegisterAddOnSetting(
		category,
		GetVariable(key),
		key,
		ns.db.settings,
		Settings.VarType.Boolean,
		label,
		Settings.Default.True
	)
	setting:SetValueChangedCallback(function()
		ns.callbacks:TriggerEvent("OptionChanged")
	end)
	return Settings.CreateCheckbox(category, setting, tooltip)
end

ns.OnInitialize(function()
	local category = Settings.RegisterVerticalLayoutCategory(ADDON_NAME)

	for _, module in ns.Modules.Enumerate() do
		local initializer = AddCheckbox(category, module.setting, module.label, module.tooltip)
		local portraitCue = module.portraitCue
		if portraitCue then
			local child = AddCheckbox(category, portraitCue.setting, portraitCue.label, portraitCue.tooltip)
			child:SetParentInitializer(initializer, function()
				return ns.Options.Get(module.setting)
			end)
		end
	end

	Settings.RegisterAddOnCategory(category)
end)
