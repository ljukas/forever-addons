local ADDON_NAME, ns = ...

local L = ns.L

-- Options > AddOns > ForeverMap. The registered settings write straight into
-- ForeverMapDB.settings, and every change (from the panel, the map menus or the world
-- map toggle) goes through Settings.SetValue so they all stay in sync.
ns.Options = {}

local function GetVariable(key)
	return "FOREVERMAP_" .. key:upper()
end

function ns.Options.Get(key)
	return ns.db.settings[key]
end

function ns.Options.Set(key, value)
	Settings.SetValue(GetVariable(key), value)
end

function ns.Options.Toggle(key)
	ns.Options.Set(key, not ns.Options.Get(key))
end

ns.OnInitialize(function()
	local category, layout = Settings.RegisterVerticalLayoutCategory(ADDON_NAME)

	local function AddCheckbox(key, label, tooltip)
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
		Settings.CreateCheckbox(category, setting, tooltip)
	end

	AddCheckbox("showWorldMap", L.SHOW_ON_WORLD_MAP, L.SHOW_ON_WORLD_MAP_TOOLTIP)
	AddCheckbox("showMinimap", L.SHOW_ON_MINIMAP, L.SHOW_ON_MINIMAP_TOOLTIP)

	layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(L.KNOWN_NODES))
	for _, layer in ns.Layers.Enumerate() do
		AddCheckbox(layer.setting, layer.label, layer.tooltip)
	end

	Settings.RegisterAddOnCategory(category)
end)
