local ADDON_NAME, ns = ...

-- Makes the power bar's holder an Edit Mode box through LibEditMode (fetched into Libs/ by
-- scripts/libs.sh, loaded namespaced as ns.LibEditMode): drag to place it (snapping like
-- Blizzard's boxes, Snap.lua), Width and Height sliders, a smooth-fill checkbox and the numbers'
-- dropdown in its dialog, for druids the other-powers row's checkbox and height, and for rogues and
-- druids the combo points row's. These, with
-- the position, are kept per Edit Mode layout in RazzhUIResourceBarsDB.powerBar (Database.lua),
-- like Blizzard's own systems.
local LEM = ns.LibEditMode
local L = ns.L
local DEFAULTS = ns.PowerBar.DEFAULTS
local holder = ns.PowerBar.holder

-- Blizzard's own power bar height slider runs 10-30 (EditModeSettingDisplayInfo.lua); the bar's
-- text needs about 8.
local WIDTH_MIN, WIDTH_MAX = 60, 600
local HEIGHT_MIN, HEIGHT_MAX = 8, 40
-- The row of a druid's other powers (OffFormPower.lua): thin, with no text to fit.
local OFF_FORM_HEIGHT_MIN, OFF_FORM_HEIGHT_MAX = 3, 20
-- The combo points row (ComboPoints.lua): as thin, and as bare.
local COMBO_HEIGHT_MIN, COMBO_HEIGHT_MAX = 3, 20

local POINTS = {
	CENTER = true,
	TOP = true,
	BOTTOM = true,
	LEFT = true,
	RIGHT = true,
	TOPLEFT = true,
	TOPRIGHT = true,
	BOTTOMLEFT = true,
	BOTTOMRIGHT = true,
}

-- The ways the numbers can show (PowerText.lua).
local TEXT_MODES = {}
for _, mode in ipairs(ns.PowerText.MODES) do
	TEXT_MODES[mode] = true
end

-- What a saved value must be to be used; anything else reads as its default.
local VALID = {
	point = function(value)
		return POINTS[value] == true
	end,
	x = function(value)
		return type(value) == "number"
	end,
	y = function(value)
		return type(value) == "number"
	end,
	width = function(value)
		return type(value) == "number" and value >= WIDTH_MIN and value <= WIDTH_MAX
	end,
	height = function(value)
		return type(value) == "number" and value >= HEIGHT_MIN and value <= HEIGHT_MAX
	end,
	smooth = function(value)
		return type(value) == "boolean"
	end,
	text = function(value)
		return TEXT_MODES[value] == true
	end,
	offForm = function(value)
		return type(value) == "boolean"
	end,
	offFormHeight = function(value)
		return type(value) == "number" and value >= OFF_FORM_HEIGHT_MIN and value <= OFF_FORM_HEIGHT_MAX
	end,
	comboPoints = function(value)
		return type(value) == "boolean"
	end,
	comboPointsHeight = function(value)
		return type(value) == "number" and value >= COMBO_HEIGHT_MIN and value <= COMBO_HEIGHT_MAX
	end,
}

-- This character, for keys of its character-specific layouts: another character may have a
-- layout of the same name. Nil when the client keeps the player's GUID secret.
local characterKey

-- The saved entries. A DB written by a newer version of the addon may not have the table this
-- version expects; then nothing is read or saved this session.
local function Store()
	local store = ns.db.powerBar
	if type(store) == "table" then
		return store
	end
	return nil
end

-- The DB key for a layout: its name, plus this character for a character-specific layout. The
-- preset layouts (Modern, Classic) aren't in GetLayouts and are shared by every character, as in
-- Edit Mode. Nil for a character-specific layout while this character is unknown, so its settings
-- are neither read from nor saved to another character's shared entry.
local function Key(layoutName)
	if not layoutName then
		return nil
	end
	for _, layout in ipairs(C_EditMode.GetLayouts().layouts) do
		if layout.layoutName == layoutName and layout.layoutType == Enum.EditModeLayoutType.Character then
			return characterKey and (layoutName .. " @ " .. characterKey) or nil
		end
	end
	return layoutName
end

local function Get(layoutName, key)
	local store = Store()
	local entryKey = Key(layoutName)
	local saved = store and entryKey and store[entryKey]
	-- Not "and saved[key] or nil", which reads a saved false as nil.
	local value
	if type(saved) == "table" then
		value = saved[key]
	end
	if value == nil or not VALID[key](value) then
		return DEFAULTS[key]
	end
	return value
end

-- Saves values (a table of fields) for a layout. Nothing is saved before layouts have loaded.
local function Save(layoutName, values)
	local store = Store()
	local entryKey = Key(layoutName)
	if not store or not entryKey then
		return
	end
	local saved = type(store[entryKey]) == "table" and store[entryKey] or {}
	store[entryKey] = saved
	for key, value in pairs(values) do
		saved[key] = value
	end
	ns.log(
		"SAVE",
		entryKey,
		saved.point,
		saved.x,
		saved.y,
		saved.width,
		saved.height,
		saved.smooth,
		saved.text,
		saved.offForm,
		saved.offFormHeight,
		saved.comboPoints,
		saved.comboPointsHeight
	)
end

local function Apply(layoutName)
	ns.PowerBar.SetLayout({
		point = Get(layoutName, "point"),
		x = Get(layoutName, "x"),
		y = Get(layoutName, "y"),
		width = Get(layoutName, "width"),
		height = Get(layoutName, "height"),
		smooth = Get(layoutName, "smooth"),
	})
	ns.PowerText.SetMode(Get(layoutName, "text"))
	ns.OffFormPower.SetLayout(Get(layoutName, "offForm"), Get(layoutName, "offFormHeight"))
	ns.ComboPoints.SetLayout(Get(layoutName, "comboPoints"), Get(layoutName, "comboPointsHeight"))
end

local function Checkbox(key, label, desc)
	return {
		name = label,
		desc = desc,
		kind = LEM.SettingType.Checkbox,
		default = DEFAULTS[key],
		get = function(layoutName)
			return Get(layoutName, key)
		end,
		set = function(layoutName, value)
			Save(layoutName, { [key] = value })
			Apply(layoutName)
		end,
	}
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

-- The Numbers dropdown: one entry per way the numbers can show, in PowerText's order.
local function NumbersDropdown()
	local labels = {
		none = L.NUMBERS_NONE,
		hover = L.NUMBERS_HOVER,
		value = L.NUMBERS_VALUE,
		percent = L.NUMBERS_PERCENT,
		both = L.NUMBERS_BOTH,
	}
	local values = {}
	for _, mode in ipairs(ns.PowerText.MODES) do
		table.insert(values, { text = labels[mode], value = mode })
	end
	return {
		name = L.NUMBERS,
		desc = L.NUMBERS_DESC,
		kind = LEM.SettingType.Dropdown,
		default = DEFAULTS.text,
		values = values,
		get = function(layoutName)
			return Get(layoutName, "text")
		end,
		set = function(layoutName, value)
			Save(layoutName, { text = value })
			Apply(layoutName)
		end,
	}
end

-- After LibEditMode drops the box (and saved where it landed), moves it onto the closest snap line.
-- LibEditMode's MoveParentToPoint re-saves through OnMoved and refreshes its dialog's coordinates.
local function SnapAfterDrag(selection)
	if InCombatLockdown() then
		return
	end
	local dx, dy = ns.Snap.ShiftFor(holder)
	if dx == 0 and dy == 0 then
		return
	end
	local point, _, _, x, y = holder:GetPoint(1)
	ns.log("EDITMODE", "snap", dx, dy)
	LEM.internal:MoveParentToPoint(selection, point, x + dx, y + dy)
end

-- The layouts seen so far, by type and name, to tell which one a "create" is about.
local knownLayouts = {}

local function LayoutID(layout)
	return layout.layoutType .. ":" .. layout.layoutName
end

local function RememberLayouts()
	wipe(knownLayouts)
	for _, layout in ipairs(C_EditMode.GetLayouts().layouts) do
		knownLayouts[LayoutID(layout)] = true
	end
end

-- The DB key for a layout from C_EditMode.GetLayouts, as Key gives for a name.
local function KeyOf(layout)
	if layout.layoutType == Enum.EditModeLayoutType.Character then
		return characterKey and (layout.layoutName .. " @ " .. characterKey) or nil
	end
	return layout.layoutName
end

ns.OnInitialize(function()
	-- Checked for secrecy before anything else touches it.
	local guid = UnitGUID("player")
	if not issecretvalue(guid) and guid then
		characterKey = guid
	end

	-- LibEditMode has already moved the holder when this runs; only the saved copy is new.
	local function OnMoved(_, layoutName, point, x, y)
		Save(layoutName, { point = point, x = x, y = y })
	end

	LEM:AddFrame(holder, OnMoved, { point = DEFAULTS.point, x = DEFAULTS.x, y = DEFAULTS.y }, L.POWER_BAR)
	local settings = {
		SizeSlider("width", L.WIDTH, WIDTH_MIN, WIDTH_MAX),
		SizeSlider("height", L.HEIGHT, HEIGHT_MIN, HEIGHT_MAX),
		Checkbox("smooth", L.SMOOTH, L.SMOOTH_DESC),
		NumbersDropdown(),
	}
	-- Only druids have other powers to show.
	if ns.OffFormPower.available then
		table.insert(settings, Checkbox("offForm", L.OFF_FORM, L.OFF_FORM_DESC))
		table.insert(settings, SizeSlider("offFormHeight", L.OFF_FORM_HEIGHT, OFF_FORM_HEIGHT_MIN, OFF_FORM_HEIGHT_MAX))
	end
	-- Only rogues and druids build combo points.
	if ns.ComboPoints.available then
		table.insert(settings, Checkbox("comboPoints", L.COMBO_POINTS, L.COMBO_POINTS_DESC))
		table.insert(
			settings,
			SizeSlider("comboPointsHeight", L.COMBO_POINTS_HEIGHT, COMBO_HEIGHT_MIN, COMBO_HEIGHT_MAX)
		)
	end
	LEM:AddFrameSettings(holder, settings)
	local selection = LEM.frameSelections[holder]
	selection:HookScript("OnDragStop", SnapAfterDrag)

	-- Fires at login once the layouts have loaded, and on every layout switch.
	LEM:RegisterCallback("layout", function(layoutName)
		ns.log("EDITMODE", "layout", layoutName, "key", Key(layoutName))
		RememberLayouts()
		Apply(layoutName)
	end)

	-- Layouts are created in Edit Mode. The "layout" callback alone may have run only before the
	-- layouts loaded (it fires again only when the active layout changes), so they are also
	-- remembered when Edit Mode opens.
	LEM:RegisterCallback("enter", RememberLayouts)

	-- A new layout starts with the bar of the layout it was copied from, or the defaults.
	-- LibEditMode names the last layout in the list as the new one, but Blizzard inserts a new
	-- account layout before the character layouts (EditModeManagerFrameMixin:MakeNewLayout), so
	-- the new one is found here: the layout not seen before. An entry that exists is never
	-- replaced.
	LEM:RegisterCallback("create", function(reportedLayoutName, _, sourceLayoutName)
		local store = Store()
		local sourceKey = Key(sourceLayoutName)
		local source = store and sourceKey and store[sourceKey]
		for _, layout in ipairs(C_EditMode.GetLayouts().layouts) do
			local newKey = KeyOf(layout)
			if store and newKey and not knownLayouts[LayoutID(layout)] and store[newKey] == nil then
				store[newKey] = type(source) == "table" and CopyTable(source) or nil
				ns.log("EDITMODE", "create", newKey, "from", sourceLayoutName, "reported", reportedLayoutName)
			end
		end
		RememberLayouts()
	end)

	-- The layout already has its new name, so Key finds its type; the old key has the same type.
	LEM:RegisterCallback("rename", function(oldLayoutName, newLayoutName)
		local store = Store()
		local newKey = Key(newLayoutName)
		if not store or not newKey then
			return
		end
		local oldKey = newKey == newLayoutName and oldLayoutName or (oldLayoutName .. newKey:sub(#newLayoutName + 1))
		if store[oldKey] ~= nil and store[newKey] == nil then
			store[newKey] = store[oldKey]
			store[oldKey] = nil
		end
		ns.log("EDITMODE", "rename", oldKey, newKey)
		RememberLayouts()
	end)

	-- The layout is gone, so its type is unknown: this character's entry if it has one, else the
	-- shared one. While this character is unknown nothing is deleted; a stale entry is harmless.
	LEM:RegisterCallback("delete", function(layoutName)
		local store = Store()
		if not store or not characterKey then
			return
		end
		local characterEntry = characterKey and (layoutName .. " @ " .. characterKey)
		local key = characterEntry and store[characterEntry] ~= nil and characterEntry or layoutName
		store[key] = nil
		ns.log("EDITMODE", "delete", key)
		RememberLayouts()
	end)

	Apply(LEM:GetActiveLayoutName())
end)
