local ADDON_NAME, ns = ...

-- Deciding which minimap children the button bag may collect, from their frame name and position.
-- Pure functions: no client API, so a reviewer can check them by reading.
--
-- Verdict returns "ok" when the frame is a button to collect, else the reason to leave it:
--   anonymous  no name, so there is nothing to recognize it by
--   blizzard   one of Blizzard's own minimap frames
--   pin        a map pin (ours or another addon's), which sits on the minimap rather than around it;
--              pin addons number their pins, so a name ending in digits counts as one
-- LibDBIcon buttons (`LibDBIcon10_<object>`) are always "ok".
--
-- RingDistance and NearRing tell where a frame sits: buttons around the minimap's edge, pins inside.
ns.ButtonRules = {}

-- The band round the minimap's edge a button's center must be in, in minimap radii (1 = on the
-- edge). A guess until launch: the BAG skip lines log every frame's distance to tune it.
ns.ButtonRules.RING_MIN, ns.ButtonRules.RING_MAX = 0.7, 1.6

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
	"^Questie",
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
	if MatchesAny(name, PIN_PREFIXES) or name:find("%d+$") then
		return "pin"
	end
	return "ok"
end

-- The distance between a point and a center, in units of `radius`. All in the same units.
function ns.ButtonRules.RingDistance(x, y, centerX, centerY, radius)
	return math.sqrt((x - centerX) ^ 2 + (y - centerY) ^ 2) / radius
end

-- Whether a RingDistance is in the band where minimap buttons sit.
function ns.ButtonRules.NearRing(distance)
	return distance >= ns.ButtonRules.RING_MIN and distance <= ns.ButtonRules.RING_MAX
end
