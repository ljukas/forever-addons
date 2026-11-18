local ADDON_NAME, ns = ...

-- Dev-only: does Blizzard's power bar still follow the player's power? An addon that replaces the
-- player frame turns off the frame's events and its bars' (UnregisterAllEvents), and a bar without
-- its events keeps the power type, the maximum and the dead look it had. Logs (POWERTYPE):
--   state <when>   the bar's power type against the player's, whether the bar and the player frame
--                  still get UNIT_DISPLAYPOWER, and whether the bar is greyed against the player
--                  being dead: at load, and a frame after login, entering the world, a change of
--                  power type or maximum, dying and coming back
--   unregister     who turned the bar's or the frame's events off
if not ns.dev.enabled then
	return
end

local bar = PlayerFrame_GetManaBar()

local function LogState(when)
	local powerType, powerToken = UnitPowerType("player")
	local texture = bar:GetStatusBarTexture()
	ns.log(
		"POWERTYPE",
		"state",
		when,
		"bar",
		bar.powerType,
		bar.powerToken,
		"player",
		powerType,
		powerToken,
		"events bar",
		(bar:IsEventRegistered("UNIT_DISPLAYPOWER")),
		"frame",
		(PlayerFrame:IsEventRegistered("UNIT_DISPLAYPOWER")),
		"grey",
		texture and texture:IsDesaturated(),
		"dead",
		UnitIsDeadOrGhost("player"),
		InCombatLockdown() and "combat" or "idle"
	)
end

-- The caller is two levels up from the hook: the hook, hooksecurefunc's wrapper, then the caller.
local function LogUnregister(name)
	return function()
		ns.log("POWERTYPE", "unregister", name, (debugstack(3, 2, 0):gsub("\n", " | ")))
	end
end

hooksecurefunc(bar, "UnregisterAllEvents", LogUnregister("bar"))
hooksecurefunc(PlayerFrame, "UnregisterAllEvents", LogUnregister("frame"))

LogState("load")

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player")
events:RegisterUnitEvent("UNIT_MAXPOWER", "player")
events:RegisterEvent("PLAYER_DEAD")
events:RegisterEvent("PLAYER_ALIVE")
events:RegisterEvent("PLAYER_UNGHOST")
events:SetScript("OnEvent", function(_, event)
	-- A frame later, so every handler of the event has run, Blizzard's and other addons'.
	C_Timer.After(0, function()
		LogState(event)
	end)
end)
