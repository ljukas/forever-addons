local ADDON_NAME, ns = ...

-- Makes the power bar's holder an Edit Mode box through LibEditMode (fetched into Libs/ by
-- scripts/libs.sh, loaded namespaced as ns.LibEditMode): drag to place it (snapping like
-- Blizzard's boxes, Snap.lua), Width and Height sliders in its dialog. Position and size are kept
-- per Edit Mode layout in ForeverUnitFramesDB.powerBar (Database.lua), like Blizzard's own systems.
local LEM = ns.LibEditMode
local L = ns.L
local DEFAULTS = ns.PowerBar.DEFAULTS
local holder = ns.PowerBar.holder

-- Blizzard's own power bar height slider runs 10-30 (EditModeSettingDisplayInfo.lua); the bar's
-- text needs about 8.
local WIDTH_MIN, WIDTH_MAX = 60, 600
local HEIGHT_MIN, HEIGHT_MAX = 8, 40

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
-- Edit Mode.
local function Key(layoutName)
	if not layoutName then
		return nil
	end
	for _, layout in ipairs(C_EditMode.GetLayouts().layouts) do
		if layout.layoutName == layoutName and layout.layoutType == Enum.EditModeLayoutType.Character then
			return characterKey and (layoutName .. " @ " .. characterKey) or layoutName
		end
	end
	return layoutName
end

local function Get(layoutName, key)
	local store = Store()
	local entryKey = Key(layoutName)
	local saved = store and entryKey and store[entryKey]
	local value = type(saved) == "table" and saved[key] or nil
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
	ns.log("SAVE", entryKey, saved.point, saved.x, saved.y, saved.width, saved.height)
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

ns.OnInitialize(function()
	local guid = UnitGUID("player")
	if guid and not issecretvalue(guid) then
		characterKey = guid
	end

	-- LibEditMode has already moved the holder when this runs; only the saved copy is new.
	local function OnMoved(_, layoutName, point, x, y)
		Save(layoutName, { point = point, x = x, y = y })
	end

	LEM:AddFrame(holder, OnMoved, { point = DEFAULTS.point, x = DEFAULTS.x, y = DEFAULTS.y }, L.POWER_BAR)
	LEM:AddFrameSettings(holder, {
		SizeSlider("width", L.WIDTH, WIDTH_MIN, WIDTH_MAX),
		SizeSlider("height", L.HEIGHT, HEIGHT_MIN, HEIGHT_MAX),
	})
	local selection = LEM.frameSelections[holder]
	selection:HookScript("OnDragStop", SnapAfterDrag)

	-- Fires at login once the layouts have loaded, and on every layout switch.
	LEM:RegisterCallback("layout", function(layoutName)
		ns.log("EDITMODE", "layout", layoutName, "key", Key(layoutName))
		Apply(layoutName)
	end)

	-- A new layout starts with the bar of the layout it was copied from, or the defaults.
	LEM:RegisterCallback("create", function(layoutName, _, sourceLayoutName)
		local store = Store()
		local newKey = Key(layoutName)
		if not store or not newKey then
			return
		end
		local source = sourceLayoutName and store[Key(sourceLayoutName)]
		store[newKey] = type(source) == "table" and CopyTable(source) or nil
		ns.log("EDITMODE", "create", newKey, "from", sourceLayoutName)
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
	end)

	-- The layout is gone, so its type is unknown: this character's entry if it has one, else the
	-- shared one.
	LEM:RegisterCallback("delete", function(layoutName)
		local store = Store()
		if not store then
			return
		end
		local characterEntry = characterKey and (layoutName .. " @ " .. characterKey)
		local key = characterEntry and store[characterEntry] ~= nil and characterEntry or layoutName
		store[key] = nil
		ns.log("EDITMODE", "delete", key)
	end)

	Apply(LEM:GetActiveLayoutName())
end)
