local ADDON_NAME, ns = ...

-- ForeverTooltipDB.settings and their defaults. A value not saved yet reads as its default, so code
-- that runs before the options panel registers its settings never sees nil.
ns.Options = {}

ns.Options.DEFAULTS = {
	cursorAnchor = false,
}

function ns.Options.Get(key)
	local value = ns.db and ns.db.settings and ns.db.settings[key]
	if value == nil then
		return ns.Options.DEFAULTS[key]
	end
	return value
end

local L = ns.L

-- Options > AddOns > ForeverTooltip. The registered setting writes straight into
-- ForeverTooltipDB.settings. Nothing caches it: Anchor.lua reads it on every anchor call.
ns.OnInitialize(function()
	local category = Settings.RegisterVerticalLayoutCategory(ADDON_NAME)

	local cursorAnchor = Settings.RegisterAddOnSetting(
		category,
		"FOREVERTOOLTIP_CURSORANCHOR",
		"cursorAnchor",
		ns.db.settings,
		Settings.VarType.Boolean,
		L.CURSOR_ANCHOR,
		ns.Options.DEFAULTS.cursorAnchor
	)
	Settings.CreateCheckbox(category, cursorAnchor, L.CURSOR_ANCHOR_TOOLTIP)

	Settings.RegisterAddOnCategory(category)
end)
