local ADDON_NAME, ns = ...

local L = ns.L

-- Options > AddOns > ForeverCombat: a checkbox per module, and under it, indented and greyed out
-- while the module is off, one for its portrait cue if it has one, and the HoT meter's one for the
-- player frame host (UI/Hosts.lua). The registered settings write straight into
-- ForeverCombatDB.settings, and registering one fills in its default.
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

-- Adds a checkbox nested under the module's, greyed out while the module is off.
local function AddChild(category, module, parent, key, label, tooltip)
	local child = AddCheckbox(category, key, label, tooltip)
	child:SetParentInitializer(parent, function()
		return ns.Options.Get(module.setting)
	end)
end

ns.OnInitialize(function()
	local category = Settings.RegisterVerticalLayoutCategory(ADDON_NAME)

	for _, module in ns.Modules.Enumerate() do
		local initializer = AddCheckbox(category, module.setting, module.label, module.tooltip)
		local portraitCue = module.portraitCue
		if portraitCue then
			AddChild(category, module, initializer, portraitCue.setting, portraitCue.label, portraitCue.tooltip)
		end
		if module.key == "hot" then
			-- Only HoTs draw on the player, so this one is the HoT meter's.
			AddChild(category, module, initializer, "hotPlayerFrame", L.HOT_PLAYER_FRAME, L.HOT_PLAYER_FRAME_TOOLTIP)
		end
	end

	Settings.RegisterAddOnCategory(category)
end)
