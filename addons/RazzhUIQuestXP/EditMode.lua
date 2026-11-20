local ADDON_NAME, ns = ...

-- Makes the line's box an Edit Mode box through LibEditMode (fetched into Libs/ by
-- scripts/libs.sh, loaded namespaced as ns.LibEditMode): drag to place it, and a Font Size slider
-- in its dialog. These are kept per Edit Mode layout in RazzhUIQuestXPDB.text (Database.lua), like
-- Blizzard's own systems. While Edit Mode is open the box always shows (Text.lua's sample). The
-- per-layout store follows ForeverCombatText's EditMode.lua.
local LEM = ns.LibEditMode
local L = ns.L
local DEFAULTS = ns.Text.DEFAULTS
local holder = ns.Text.holder

local FONT_SIZE_MIN, FONT_SIZE_MAX = 8, 32

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
	fontSize = function(value)
		return type(value) == "number" and value >= FONT_SIZE_MIN and value <= FONT_SIZE_MAX
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
	ns.log("SAVE", entryKey, saved.point, saved.x, saved.y, saved.fontSize)
end

local function Apply(layoutName)
	local layout = {
		point = Get(layoutName, "point"),
		x = Get(layoutName, "x"),
		y = Get(layoutName, "y"),
		fontSize = Get(layoutName, "fontSize"),
	}
	ns.Text.SetLayout(layout)
	if ns.dev.enabled then
		local applied = strjoin(" ", tostring(layoutName), layout.point, layout.x, layout.y, layout.fontSize)
		ns.dev:LogChanged("apply", applied, "EDITMODE", "apply", applied)
	end
end

-- The layout last applied: what a new layout is copied from when Edit Mode names no source.
local appliedLayoutName

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

	-- LibEditMode has already moved the box when this runs; only the saved copy is new.
	local function OnMoved(_, layoutName, point, x, y)
		Save(layoutName, { point = point, x = x, y = y })
	end

	local defaultPosition = { point = DEFAULTS.point, x = DEFAULTS.x, y = DEFAULTS.y }
	LEM:AddFrame(holder, OnMoved, defaultPosition, L.QUEST_XP)
	-- The selection LibEditMode lays over the box prints "Click to Edit" or the box's name in its
	-- middle (EditModeSystemSelectionMixin:UpdateLabelVisibility), which is where the line is, in a
	-- box no bigger than the line. The line is the label here; the hover tooltip and the dialog
	-- still name the box. The selection is LibEditMode's frame for our box, not one of Blizzard's.
	local selection = LEM.frameSelections and LEM.frameSelections[holder]
	if selection and selection.Label then
		selection.Label:SetAlpha(0)
	end
	LEM:AddFrameSettings(holder, {
		{
			-- Blizzard's own string (the chat window's Font Size menu), so it is translated.
			name = _G["FONT_SIZE"] or L.FONT_SIZE,
			kind = LEM.SettingType.Slider,
			default = DEFAULTS.fontSize,
			minValue = FONT_SIZE_MIN,
			maxValue = FONT_SIZE_MAX,
			valueStep = 1,
			get = function(layoutName)
				return Get(layoutName, "fontSize")
			end,
			set = function(layoutName, value)
				-- The slider may hand over 13.999999; whole sizes are kept.
				local size = Clamp(math.floor(value + 0.5), FONT_SIZE_MIN, FONT_SIZE_MAX)
				Save(layoutName, { fontSize = size })
				Apply(layoutName)
			end,
		},
	})

	LEM:RegisterCallback("enter", function()
		ns.log("EDITMODE", "enter")
		ns.Text.SetSample(true)
	end)
	LEM:RegisterCallback("exit", function()
		ns.log("EDITMODE", "exit")
		ns.Text.SetSample(false)
	end)

	-- Fires at login once the layouts have loaded, and on every layout switch.
	LEM:RegisterCallback("layout", function(layoutName)
		ns.log("EDITMODE", "layout", layoutName, "key", Key(layoutName))
		RememberLayouts()
		appliedLayoutName = layoutName
		Apply(layoutName)
	end)

	-- A new layout starts with the box of the layout it was copied from, or the defaults.
	-- LibEditMode names the last layout in the list as the new one, but Blizzard inserts a new
	-- account layout before the character layouts (EditModeManagerFrameMixin:MakeNewLayout), so
	-- the new one is found here: the layout not seen before. An entry that exists is never
	-- replaced. Only a row's Copy button names a source; "New Layout" and saving a preset as a new
	-- layout copy the active one without saying so (EditModeManagerFrame:ShowNewLayoutDialog with
	-- no argument), so then the source is the layout last applied.
	LEM:RegisterCallback("create", function(_, _, sourceLayoutName)
		sourceLayoutName = sourceLayoutName or appliedLayoutName
		local store = Store()
		local sourceKey = Key(sourceLayoutName)
		local source = store and sourceKey and store[sourceKey]
		for _, layout in ipairs(C_EditMode.GetLayouts().layouts) do
			local newKey = KeyOf(layout)
			if store and newKey and not knownLayouts[LayoutID(layout)] and store[newKey] == nil then
				store[newKey] = type(source) == "table" and CopyTable(source) or nil
				ns.log("EDITMODE", "create", newKey, "from", sourceLayoutName)
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
		local characterEntry = layoutName .. " @ " .. characterKey
		local key = store[characterEntry] ~= nil and characterEntry or layoutName
		store[key] = nil
		ns.log("EDITMODE", "delete", key)
		RememberLayouts()
	end)

	appliedLayoutName = LEM:GetActiveLayoutName()
	Apply(appliedLayoutName)
	if LEM:IsInEditMode() then
		ns.Text.SetSample(true)
	end
end)
