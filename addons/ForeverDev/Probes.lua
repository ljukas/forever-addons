local ADDON_NAME = ...

-- Probes that hold for every addon, logged under ForeverDev (scripts/devlog.sh --addon
-- ForeverDev). They record what Forever restricts where, so features can be planned around it:
--   CLIENT       version, build, class and level, on login and reload
--   PROBE        secret restrictions, addon message restriction and every restriction type's
--                state, on entering the world, changing zones and every restriction change
--   RESTRICTION  a restriction type changing state
--   UNIT         which of a unit's values are secret (health, power, ...), once per unit, situation
--                (ForeverDev.Situation) and power type: the target when it changes, the player when
--                its power changes
-- Addon-specific probes live in that addon's Dev/ folder.

local dev = ForeverDev.For(ADDON_NAME)

local function RestrictionName(restriction)
	for name, value in pairs(Enum.AddOnRestrictionType) do
		if value == restriction then
			return name
		end
	end
	return tostring(restriction)
end

local function RestrictionStates()
	local states = {}
	for name, restriction in pairs(Enum.AddOnRestrictionType) do
		table.insert(states, name .. "=" .. C_RestrictedActions.GetAddOnRestrictionState(restriction))
	end
	table.sort(states)
	return table.concat(states, " ")
end

local function Probe(reason)
	dev:Log(
		"PROBE",
		reason,
		ForeverDev.Situation(),
		"secretRestrictions",
		C_Secrets.HasSecretRestrictions(),
		"addonMessagesRestricted",
		C_ChatInfo.AreOutgoingAddonChatMessagesRestricted(),
		"restrictions",
		RestrictionStates()
	)
end

local function ProbeUnit(unit)
	if not UnitExists(unit) then
		return
	end
	local situation = ForeverDev.Situation(unit)
	local _, powerToken = UnitPowerType(unit)
	powerToken = powerToken or "NOPOWER"
	dev:LogOnce(
		"unit " .. unit .. " " .. situation .. " " .. powerToken,
		"UNIT",
		unit,
		situation,
		powerToken,
		"secret:",
		ForeverDev.SecretNames(
			"guid",
			UnitGUID(unit),
			"name",
			(UnitName(unit)),
			"health",
			UnitHealth(unit),
			"max",
			UnitHealthMax(unit),
			"power",
			UnitPower(unit),
			"powerMax",
			UnitPowerMax(unit)
		)
	)
end

local handlers = {}

function handlers.PLAYER_ENTERING_WORLD(isInitialLogin, isReloadingUi)
	if isInitialLogin or isReloadingUi then
		local version, build = GetBuildInfo()
		dev:Log("CLIENT", version, build, "class", select(2, UnitClass("player")), "level", UnitLevel("player"))
	end
	Probe("entering world")
end

function handlers.ZONE_CHANGED_NEW_AREA()
	Probe("zone")
end

function handlers.ADDON_RESTRICTION_STATE_CHANGED(restriction, state)
	dev:Log("RESTRICTION", RestrictionName(restriction), "state", state)
	Probe("restriction change")
end

function handlers.PLAYER_TARGET_CHANGED()
	ProbeUnit("target")
end

function handlers.UNIT_POWER_UPDATE()
	ProbeUnit("player")
end

-- Events registered for one unit only, so they don't fire for every party member and nameplate.
local unitEvents = {
	UNIT_POWER_UPDATE = "player",
}

local frame = CreateFrame("Frame")
for event in pairs(handlers) do
	if unitEvents[event] then
		frame:RegisterUnitEvent(event, unitEvents[event])
	else
		frame:RegisterEvent(event)
	end
end
frame:SetScript("OnEvent", function(_, event, ...)
	handlers[event](...)
end)
