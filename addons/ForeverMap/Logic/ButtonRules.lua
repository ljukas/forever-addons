local ADDON_NAME, ns = ...

-- Deciding which minimap children the button bag may collect, from their frame name alone. Pure
-- function: no client API, so a reviewer can check it by reading.
--
-- Verdict returns "ok" when the frame is a button to collect, else the reason to leave it:
--   anonymous  no name, so there is nothing to recognize it by
--   blizzard   one of Blizzard's own minimap frames
--   pin        a map pin (ours or another addon's), which sits on the minimap rather than around it
-- LibDBIcon buttons (`LibDBIcon10_<object>`) are always "ok".
ns.ButtonRules = {}

-- Every named frame in Blizzard_Minimap (Mainline and Camelot) and the frames other Blizzard
-- addons parent to the minimap or its cluster.
local BLIZZARD_NAMES = {
	AddonCompartmentFrame = true,
	ExpansionLandingPageMinimapButton = true,
	GameTimeCalendarEventAlarmTexture = true,
	GameTimeCalendarInvitesGlow = true,
	GameTimeCalendarInvitesTexture = true,
	GameTimeFrame = true,
	HybridMinimap = true,
	MiniMapCraftingOrderIcon = true,
	MiniMapMailIcon = true,
	Minimap = true,
	MinimapBackdrop = true,
	MinimapCluster = true,
	MinimapCompassTexture = true,
	MinimapCompassTextureUnderlay = true,
	MinimapZoneText = true,
	TimeManagerClockButton = true,
}

local BLIZZARD_PREFIXES = {
	"^Minimap",
	"^MiniMap",
	"^GameTime",
	"^Queue",
	"^GarrisonLandingPage",
	"^ExpansionLandingPage",
	"^AddonCompartment",
	"^TimeManager",
}

local PIN_PREFIXES = {
	"^HandyNotes",
	"^GatherMate",
	"^TomTom",
	"^HereBeDragons",
	"^ForeverMap",
	"^ForeverProfessions",
}

local function MatchesAny(name, patterns)
	for _, pattern in ipairs(patterns) do
		if name:find(pattern) then
			return true
		end
	end
	return false
end

function ns.ButtonRules.Verdict(name)
	if not name then
		return "anonymous"
	end
	if name:find("^LibDBIcon10_") then
		return "ok"
	end
	if BLIZZARD_NAMES[name] or MatchesAny(name, BLIZZARD_PREFIXES) then
		return "blizzard"
	end
	if MatchesAny(name, PIN_PREFIXES) then
		return "pin"
	end
	return "ok"
end
