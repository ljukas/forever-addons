local ADDON_NAME, ns = ...

-- ForeverTooltipDB.settings and their defaults. A value not saved yet reads as its default, so code
-- that runs before the options panel registers its settings never sees nil.
ns.Options = {}

-- Which way a cursor-following tooltip grows from the pointer. Defined (and stored values fixed) in
-- Logic/CursorAnchor.lua.
ns.Options.DIRECTION = ns.CursorAnchor.DIRECTION

ns.Options.DEFAULTS = {
	cursorAnchor = false,
	-- Up and right, like Blizzard's own cursor-anchored world tooltips (ANCHOR_CURSOR).
	cursorDirection = ns.Options.DIRECTION.UP_RIGHT,
}

function ns.Options.Get(key)
	local value = ns.db and ns.db.settings and ns.db.settings[key]
	if value == nil then
		return ns.Options.DEFAULTS[key]
	end
	return value
end

local L = ns.L

-- Settings variable names are player-facing; renaming a DB key renames its variable too.
local function GetVariable(key)
	return "FOREVERTOOLTIP_" .. key:upper()
end

-- Options > AddOns > ForeverTooltip. The registered settings write straight into
-- ForeverTooltipDB.settings. Nothing caches them: Anchor.lua reads them on every anchor call.
ns.OnInitialize(function()
	local category = Settings.RegisterVerticalLayoutCategory(ADDON_NAME)

	local function Register(key, varType, label)
		return Settings.RegisterAddOnSetting(
			category,
			GetVariable(key),
			key,
			ns.db.settings,
			varType,
			label,
			ns.Options.DEFAULTS[key]
		)
	end

	local cursorAnchor = Register("cursorAnchor", Settings.VarType.Boolean, L.CURSOR_ANCHOR)
	local cursorAnchorInitializer = Settings.CreateCheckbox(category, cursorAnchor, L.CURSOR_ANCHOR_TOOLTIP)

	local direction = Register("cursorDirection", Settings.VarType.Number, L.CURSOR_DIRECTION)
	local function GetDirections()
		local container = Settings.CreateControlTextContainer()
		container:Add(ns.Options.DIRECTION.DOWN_RIGHT, L.DIRECTION_DOWN_RIGHT)
		container:Add(ns.Options.DIRECTION.DOWN_LEFT, L.DIRECTION_DOWN_LEFT)
		container:Add(ns.Options.DIRECTION.UP_RIGHT, L.DIRECTION_UP_RIGHT)
		container:Add(ns.Options.DIRECTION.UP_LEFT, L.DIRECTION_UP_LEFT)
		return container:GetData()
	end
	local directionInitializer = Settings.CreateDropdown(category, direction, GetDirections, L.CURSOR_DIRECTION_TOOLTIP)
	-- The direction only matters while the tooltip follows the cursor.
	directionInitializer:SetParentInitializer(cursorAnchorInitializer, function()
		return cursorAnchor:GetValue()
	end)

	Settings.RegisterAddOnCategory(category)
end)
