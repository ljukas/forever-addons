local ADDON_NAME = ...

-- Probes that hold for every addon, logged under ForeverDev (scripts/devlog.sh --addon
-- ForeverDev). They record what Forever restricts where, so features can be planned around it:
--   CLIENT       version, build, class and level, on login and reload
--   PROBE        secret restrictions, addon message restriction and every restriction type's
--                state, on entering the world, changing zones and every restriction change
--   RESTRICTION  a restriction type changing state
--   UNIT         which of a unit's values are secret (health, power, ...) and its power type's base
--                secrecy, once per unit, situation (ForeverDev.Situation), power type and answer:
--                the player on entering the world (any loading screen) and form changes, the
--                target when it changes, and both on every restriction change
-- Addon-specific probes live in that addon's Dev/ folder.

local dev = ForeverDev.For(ADDON_NAME)

local function EnumName(enum, value)
	for name, enumValue in pairs(enum) do
		if enumValue == value then
			return name
		end
	end
	return tostring(value)
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
	-- The unit's primary (displayed) power only.
	local powerType, powerToken = UnitPowerType(unit)
	local secrecy = powerType and EnumName(Enum.SecrecyLevel, C_Secrets.GetPowerTypeSecrecy(powerType)) or "none"
	powerToken = powerToken or "NOPOWER"
	local secret = ForeverDev.SecretNames(
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
	-- The answer is part of the key: InCombatLockdown and the secret restrictions may not switch
	-- at the same moment, so a first sample taken between them mustn't hide the later ones.
	dev:LogOnce(
		"unit " .. unit .. " " .. situation .. " " .. powerToken .. " " .. secret,
		"UNIT",
		unit,
		situation,
		powerToken,
		"secrecy",
		secrecy,
		"secret:",
		secret
	)
end

local function ProbeUnits()
	ProbeUnit("player")
	ProbeUnit("target")
end

local handlers = {}

function handlers.PLAYER_ENTERING_WORLD(isInitialLogin, isReloadingUi)
	if isInitialLogin or isReloadingUi then
		local version, build = GetBuildInfo()
		dev:Log("CLIENT", version, build, "class", select(2, UnitClass("player")), "level", UnitLevel("player"))
	end
	Probe("entering world")
	ProbeUnit("player")
end

function handlers.ZONE_CHANGED_NEW_AREA()
	Probe("zone")
end

function handlers.ADDON_RESTRICTION_STATE_CHANGED(restriction, state)
	dev:Log("RESTRICTION", EnumName(Enum.AddOnRestrictionType, restriction), "state", state)
	Probe("restriction change")
	-- Secrecy follows the restriction states, not combat, so this is when unit values can start
	-- or stop reading as secret, whether or not they change. A restriction that is activating is
	-- only enforced once this event's dispatch has completed, so the units are probed after it.
	C_Timer.After(0, ProbeUnits)
end

function handlers.PLAYER_TARGET_CHANGED()
	ProbeUnit("target")
end

-- A form change switches the player's displayed power type.
function handlers.UNIT_DISPLAYPOWER()
	ProbeUnit("player")
end

local frame = CreateFrame("Frame")
for event in pairs(handlers) do
	-- UNIT_ events are the player's only, so they don't fire for every party member and nameplate.
	if event:find("^UNIT_") then
		frame:RegisterUnitEvent(event, "player")
	else
		frame:RegisterEvent(event)
	end
end
frame:SetScript("OnEvent", function(_, event, ...)
	handlers[event](...)
end)
