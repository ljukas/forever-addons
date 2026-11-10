local ADDON_NAME, ns = ...

-- Makes the power bar's holder an Edit Mode box through LibEditMode (fetched into Libs/ by
-- scripts/libs.sh, loaded namespaced as ns.LibEditMode): drag to place it, Width and Height sliders
-- in its dialog. Position and size are kept per Edit Mode layout in ForeverUnitFramesDB.powerBar
-- (Database.lua), like Blizzard's own systems.
local LEM = ns.LibEditMode
local L = ns.L
local DEFAULTS = ns.PowerBar.DEFAULTS
local holder = ns.PowerBar.holder

local WIDTH_MIN, WIDTH_MAX = 60, 600
local HEIGHT_MIN, HEIGHT_MAX = 4, 40

-- The saved value of key for a layout, or its default. layoutName is nil until Edit Mode has
-- loaded the layouts.
local function Get(layoutName, key)
	local saved = layoutName and ns.db.powerBar[layoutName]
	local value = saved and saved[key]
	if value == nil then
		return DEFAULTS[key]
	end
	return value
end

-- Saves values (a table of fields) for a layout. Nothing is saved before layouts have loaded.
local function Save(layoutName, values)
	if not layoutName then
		return
	end
	local saved = ns.db.powerBar[layoutName] or {}
	ns.db.powerBar[layoutName] = saved
	for key, value in pairs(values) do
		saved[key] = value
	end
	ns.log("SAVE", layoutName, saved.point, saved.x, saved.y, saved.width, saved.height)
end

local function Apply(layoutName)
	ns.PowerBar.SetLayout({
		point = Get(layoutName, "point"),
		x = Get(layoutName, "x"),
		y = Get(layoutName, "y"),
		width = Get(layoutName, "width"),
		height = Get(layoutName, "height"),
	})
end

local function SizeSlider(key, label, minValue, maxValue)
	return {
		name = label,
		kind = LEM.SettingType.Slider,
		default = DEFAULTS[key],
		minValue = minValue,
		maxValue = maxValue,
		valueStep = 1,
		get = function(layoutName)
			return Get(layoutName, key)
		end,
		set = function(layoutName, value)
			Save(layoutName, { [key] = value })
			Apply(layoutName)
		end,
	}
end

ns.OnInitialize(function()
	-- LibEditMode has already moved the holder when this runs; only the saved copy is new.
	local function OnMoved(_, layoutName, point, x, y)
		Save(layoutName, { point = point, x = x, y = y })
	end

	LEM:AddFrame(holder, OnMoved, { point = DEFAULTS.point, x = DEFAULTS.x, y = DEFAULTS.y }, L.POWER_BAR)
	LEM:AddFrameSettings(holder, {
		SizeSlider("width", L.WIDTH, WIDTH_MIN, WIDTH_MAX),
		SizeSlider("height", L.HEIGHT, HEIGHT_MIN, HEIGHT_MAX),
	})

	-- Fires at login once the layouts have loaded, and on every layout switch.
	LEM:RegisterCallback("layout", function(layoutName)
		ns.log("EDITMODE", "layout", layoutName)
		Apply(layoutName)
	end)

	-- A new layout copied from another starts with that layout's bar.
	LEM:RegisterCallback("create", function(layoutName, _, sourceLayoutName)
		local source = sourceLayoutName and ns.db.powerBar[sourceLayoutName]
		if source and not ns.db.powerBar[layoutName] then
			ns.db.powerBar[layoutName] = CopyTable(source)
			ns.log("EDITMODE", "create", layoutName, "from", sourceLayoutName)
		end
	end)

	LEM:RegisterCallback("rename", function(oldLayoutName, newLayoutName)
		ns.db.powerBar[newLayoutName] = ns.db.powerBar[oldLayoutName]
		ns.db.powerBar[oldLayoutName] = nil
		ns.log("EDITMODE", "rename", oldLayoutName, newLayoutName)
	end)

	LEM:RegisterCallback("delete", function(layoutName)
		ns.db.powerBar[layoutName] = nil
		ns.log("EDITMODE", "delete", layoutName)
	end)

	Apply(LEM:GetActiveLayoutName())
end)
