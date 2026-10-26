local ADDON_NAME = ...

-- Probes that hold for every addon, logged under ForeverDev (scripts/devlog.sh --addon
-- ForeverDev). They record what Forever restricts where, so features can be planned around it:
--   CLIENT       version, build, class and level, on login and reload
--   PROBE        secret restrictions, addon message restriction and every restriction type's
--                state, on entering the world, changing zones and every restriction change
--   RESTRICTION  a restriction type changing state
--   UNIT         which of a target's values are secret, once per situation (ForeverDev.Situation)
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
	dev:LogOnce(
		"unit " .. situation,
		"UNIT",
		situation,
		"secret:",
		ForeverDev.SecretNames(
			"guid",
			UnitGUID(unit),
			"name",
			(UnitName(unit)),
			"health",
			UnitHealth(unit),
			"max",
			UnitHealthMax(unit)
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

local frame = CreateFrame("Frame")
for event in pairs(handlers) do
	frame:RegisterEvent(event)
end
frame:SetScript("OnEvent", function(_, event, ...)
	handlers[event](...)
end)
