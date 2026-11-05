local ADDON_NAME, ns = ...

local L = ns.L

-- Options > AddOns > ForeverCombat: a checkbox per module, and under the HoT meter's one for
-- the player frame host (UI/Hosts.lua). The registered settings write straight into
-- ForeverCombatDB.settings, and registering one fills in its default.
ns.Options = {}

local function GetVariable(key)
	return "FOREVERCOMBAT_" .. key:upper()
end

function ns.Options.Get(key)
	return ns.db.settings[key]
end

-- Adds a checkbox, on by default. Returns its setting and initializer.
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
	return setting, Settings.CreateCheckbox(category, setting, tooltip)
end

ns.OnInitialize(function()
	local category = Settings.RegisterVerticalLayoutCategory(ADDON_NAME)

	for _, module in ns.Modules.Enumerate() do
		local setting, initializer = AddCheckbox(category, module.setting, module.label, module.tooltip)
		if module.key == "hot" then
			-- Only HoTs draw on the player, so this is the HoT meter's, greyed out while it's off.
			local _, playerFrame =
				AddCheckbox(category, "hotPlayerFrame", L.HOT_PLAYER_FRAME, L.HOT_PLAYER_FRAME_TOOLTIP)
			playerFrame:SetParentInitializer(initializer, function()
				return setting:GetValue()
			end)
		end
	end

	Settings.RegisterAddOnCategory(category)
end)
