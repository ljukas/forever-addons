local ADDON_NAME, ns = ...

-- Whether Find Herbs, Find Minerals or Find Treasure is on. The herb and ore spell IDs are the
-- ones Blizzard's own tracking menu gives the herb and ore icons (Blizzard_Minimap/Mainline/
-- Minimap.lua, TRACKING_SPELL_OVERRIDE_ATLAS); Find Treasure's is the Classic Era dwarf racial's
-- (a launch check: TRACK logs every tracking type with its spell ID).
--
-- Dev log tags: TRACK (the tracking types and which are on, each time that changes).
ns.Tracking = {}

local FIND_TREASURE = 2481
ns.Tracking.FIND_TREASURE = FIND_TREASURE

local FINDERS = {
	[2383] = true, -- Find Herbs
	[8387] = true, -- Find Herbs
	[2580] = true, -- Find Minerals
	[8388] = true, -- Find Minerals
	[FIND_TREASURE] = true,
}

local finding = false
-- Find Treasure's icon in the tracking menu, once seen: it marks chests (UI/NodeIcons.lua).
local treasureTexture

-- Only a change is announced: MINIMAP_UPDATE_TRACKING can fire repeatedly, and every
-- announcement restarts the scanner's sweep.
local function Refresh()
	local was = finding
	finding = false
	local seen = ns.dev.enabled and {}
	for index = 1, C_Minimap.GetNumTrackingTypes() do
		local info = C_Minimap.GetTrackingInfo(index)
		if info and not issecretvalue(info) and not issecretvalue(info.active) and not issecretvalue(info.spellID) then
			if seen then
				table.insert(
					seen,
					("%s=%s%s"):format(tostring(info.name), tostring(info.spellID), info.active and "*" or "")
				)
			end
			if info.spellID == FIND_TREASURE and not issecretvalue(info.texture) then
				treasureTexture = info.texture
			end
			if info.active and FINDERS[info.spellID] then
				finding = true
			end
		end
	end
	if seen then
		ns.dev:LogChanged("tracking", table.concat(seen, ", "), "TRACK", table.concat(seen, ", "))
	end
	if finding ~= was then
		ns.callbacks:TriggerEvent("TrackingChanged")
	end
end

function ns.Tracking.IsFinding()
	return finding
end

-- Find Treasure's tracking icon (a file ID), or nil while it hasn't been seen.
function ns.Tracking.TreasureTexture()
	return treasureTexture
end

ns.OnInitialize(function()
	local frame = CreateFrame("Frame")
	frame:RegisterEvent("MINIMAP_UPDATE_TRACKING")
	frame:RegisterEvent("PLAYER_ENTERING_WORLD")
	frame:SetScript("OnEvent", Refresh)
	Refresh()
end)
