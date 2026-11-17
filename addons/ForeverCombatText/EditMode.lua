local ADDON_NAME, ns = ...

-- Makes the combat text's box an Edit Mode box through LibEditMode (fetched into Libs/ by
-- scripts/libs.sh, loaded namespaced as ns.LibEditMode): drag to place it, and Scroll Length,
-- Duration and Font Size sliders in its dialog. These, with the position, are kept per Edit Mode
-- layout in ForeverCombatTextDB.text (Database.lua), like Blizzard's own systems. While Edit Mode
-- is open, sample messages scroll in the box. The per-layout store follows ForeverUnitFrames'
-- EditMode.lua.
local LEM = ns.LibEditMode
local L = ns.L
local DEFAULTS = ns.Display.DEFAULTS
local holder = ns.Display.holder

local LENGTH_MIN, LENGTH_MAX, LENGTH_STEP = 50, 600, 5
local DURATION_MIN, DURATION_MAX, DURATION_STEP = 0.5, 5, 0.1
local FONT_SIZE_MIN, FONT_SIZE_MAX = 10, 60

-- Seconds between sample messages while Edit Mode is open.
local SAMPLE_INTERVAL = 1
-- What Blizzard shows for a hit, a heal and a critical hit taken, in CombatTextTypeInfo's colours
-- (CombatTextConstants.lua: DAMAGE, HEAL, DAMAGE_CRIT). The amounts are made up.
local SAMPLES = {
	{ text = "-25", r = 1, g = 0.1, b = 0.1, isStaggered = true },
	{ text = "+120", r = 0.1, g = 1, b = 0.1 },
	{ text = "-250", r = 1, g = 0.1, b = 0.1, displayType = "crit" },
}

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

local function InRange(value, minValue, maxValue)
	return type(value) == "number" and value >= minValue and value <= maxValue
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
	length = function(value)
		return InRange(value, LENGTH_MIN, LENGTH_MAX)
	end,
	duration = function(value)
		return InRange(value, DURATION_MIN, DURATION_MAX)
	end,
	fontSize = function(value)
		return InRange(value, FONT_SIZE_MIN, FONT_SIZE_MAX)
	end,
}

-- This character, for keys of its character-specific layouts: another character may have a
-- layout of the same name. Nil when the client keeps the player's GUID secret.
local characterKey

-- The saved entries. A DB written by a newer version of the addon may not have the table this
-- version expects; then nothing is read or saved this session.
local function Store()
	local store = ns.db.text
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
	ns.log("SAVE", entryKey, saved.point, saved.x, saved.y, saved.length, saved.duration, saved.fontSize)
end

local function Apply(layoutName)
	ns.Display.SetLayout({
		point = Get(layoutName, "point"),
		x = Get(layoutName, "x"),
		y = Get(layoutName, "y"),
		length = Get(layoutName, "length"),
		duration = Get(layoutName, "duration"),
		fontSize = Get(layoutName, "fontSize"),
	})
end

-- A slider for a saved number. OnSet(layoutName, value), when given, returns the fields to save.
local function Slider(key, label, desc, minValue, maxValue, valueStep, OnSet)
	return {
		name = label,
		desc = desc,
		kind = LEM.SettingType.Slider,
		default = DEFAULTS[key],
		minValue = minValue,
		maxValue = maxValue,
		valueStep = valueStep,
		get = function(layoutName)
			return Get(layoutName, key)
		end,
		set = function(layoutName, value)
			Save(layoutName, OnSet and OnSet(layoutName, value) or { [key] = value })
			Apply(layoutName)
		end,
	}
end

-- The box is as tall as the text scrolls. Its start edge stays where the player put it: the saved
-- offset moves by what the anchor point would otherwise let that edge move.
local function LengthChanged(layoutName, value)
	local shift =
		ns.Scroll.ShiftForLength(Get(layoutName, "point"), Get(layoutName, "length"), value, ns.Display.Mode())
	return { length = value, y = Get(layoutName, "y") + shift }
end

-- The slider hands over 1.9000000001; one decimal is kept.
local function DurationChanged(_, value)
	local rounded = math.floor(value * 10 + 0.5) / 10
	return { duration = Clamp(rounded, DURATION_MIN, DURATION_MAX) }
end

local sampleTicker
local sampleIndex = 0

local function ShowSample()
	sampleIndex = sampleIndex % #SAMPLES + 1
	local sample = SAMPLES[sampleIndex]
	ns.Display.Add(sample.text, sample.r, sample.g, sample.b, sample.displayType, sample.isStaggered)
end

ns.OnInitialize(function()
	-- Checked for secrecy before anything else touches it.
	local guid = UnitGUID("player")
	if not issecretvalue(guid) and guid then
		characterKey = guid
	end

	-- LibEditMode has already moved the box when this runs; only the saved copy is new.
	local function OnMoved(_, layoutName, point, x, y)
		Save(layoutName, { point = point, x = x, y = y })
	end

	LEM:AddFrame(holder, OnMoved, { point = DEFAULTS.point, x = DEFAULTS.x, y = DEFAULTS.y }, L.COMBAT_TEXT)
	LEM:AddFrameSettings(holder, {
		Slider("length", L.SCROLL_LENGTH, nil, LENGTH_MIN, LENGTH_MAX, LENGTH_STEP, LengthChanged),
		Slider("duration", L.DURATION, L.DURATION_DESC, DURATION_MIN, DURATION_MAX, DURATION_STEP, DurationChanged),
		Slider("fontSize", L.FONT_SIZE, nil, FONT_SIZE_MIN, FONT_SIZE_MAX, 1),
	})

	LEM:RegisterCallback("enter", function()
		if not sampleTicker then
			sampleTicker = C_Timer.NewTicker(SAMPLE_INTERVAL, ShowSample)
		end
	end)
	LEM:RegisterCallback("exit", function()
		if sampleTicker then
			sampleTicker:Cancel()
			sampleTicker = nil
		end
	end)

	-- Fires at login once the layouts have loaded, and on every layout switch.
	LEM:RegisterCallback("layout", function(layoutName)
		ns.log("EDITMODE", "layout", layoutName, "key", Key(layoutName))
		Apply(layoutName)
	end)

	-- A new layout starts with the box of the layout it was copied from, or the defaults.
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
	-- shared one. While this character is unknown nothing is deleted; a stale entry is harmless.
	LEM:RegisterCallback("delete", function(layoutName)
		local store = Store()
		if not store or not characterKey then
			return
		end
		local characterEntry = layoutName .. " @ " .. characterKey
		local key = store[characterEntry] ~= nil and characterEntry or layoutName
		store[key] = nil
		ns.log("EDITMODE", "delete", key)
	end)

	Apply(LEM:GetActiveLayoutName())
end)
