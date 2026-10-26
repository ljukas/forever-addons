local ADDON_NAME, ns = ...

-- Whether Find Herbs or Find Minerals is on. Their spell IDs are the ones Blizzard's own
-- tracking menu gives the herb and ore icons (Blizzard_Minimap/Mainline/Minimap.lua,
-- TRACKING_SPELL_OVERRIDE_ATLAS).
ns.Tracking = {}

local FINDERS = {
	[2383] = true, -- Find Herbs
	[8387] = true, -- Find Herbs
	[2580] = true, -- Find Minerals
	[8388] = true, -- Find Minerals
}

local finding = false

local function Refresh()
	finding = false
	for index = 1, C_Minimap.GetNumTrackingTypes() do
		local info = C_Minimap.GetTrackingInfo(index)
		if info and not issecretvalue(info) and not issecretvalue(info.active) and not issecretvalue(info.spellID) then
			if info.active and FINDERS[info.spellID] then
				finding = true
				break
			end
		end
	end
	ns.callbacks:TriggerEvent("TrackingChanged")
end

function ns.Tracking.IsFinding()
	return finding
end

ns.OnInitialize(function()
	local frame = CreateFrame("Frame")
	frame:RegisterEvent("MINIMAP_UPDATE_TRACKING")
	frame:RegisterEvent("PLAYER_ENTERING_WORLD")
	frame:SetScript("OnEvent", Refresh)
	Refresh()
end)
