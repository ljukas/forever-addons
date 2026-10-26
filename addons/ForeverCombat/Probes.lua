local ADDON_NAME, ns = ...

-- Launch-day probes, logged only (scripts/devlog.sh). They record what Forever restricts
-- where, to decide on later features: party members' DoTs could only be shared through
-- addon messages, which Midnight may block in instances.
--   PROBE   secret restrictions, addon message restriction and every restriction type's state,
--           on entering the world, changing zones and every restriction change
--   UNIT    which of a target's values are secret, once per kind of target and situation
--   AURA    whether a tracked spell's aura can be read on its unit after the cast, through the
--           two aura lookups without RequiresUnitAuraAccess (the others error in combat). They
--           return nothing for secret auras, but spells Blizzard flags as never secret would
--           read: those could be tracked from the aura instead of estimated. Once per spell and
--           situation.

local function RestrictionStates()
	local states = {}
	for name, restriction in pairs(Enum.AddOnRestrictionType) do
		table.insert(states, name .. "=" .. C_RestrictedActions.GetAddOnRestrictionState(restriction))
	end
	table.sort(states)
	return table.concat(states, " ")
end

local function Probe(reason)
	local _, instanceType = IsInInstance()
	ns.log(
		"PROBE",
		reason,
		"instance",
		instanceType,
		"secretRestrictions",
		C_Secrets.HasSecretRestrictions(),
		"addonMessagesRestricted",
		C_ChatInfo.AreOutgoingAddonChatMessagesRestricted(),
		"restrictions",
		RestrictionStates()
	)
end

local unitsProbed = {}

local function ProbeUnit(unit)
	if not UnitExists(unit) then
		return
	end
	local _, instanceType = IsInInstance()
	local hostile = UnitCanAttack("player", unit)
	local situation = string.format(
		"%s %s %s %s",
		instanceType,
		hostile and "hostile" or "friendly",
		UnitIsPlayer(unit) and "player" or "npc",
		InCombatLockdown() and "combat" or "idle"
	)
	if unitsProbed[situation] then
		return
	end
	unitsProbed[situation] = true
	local _, via = ns.Units.Key(unit)
	ns.log(
		"UNIT",
		situation,
		"guid secret",
		issecretvalue(UnitGUID(unit)),
		"name secret",
		issecretvalue((UnitName(unit))),
		"health secret",
		issecretvalue(UnitHealth(unit)),
		"max secret",
		issecretvalue(UnitHealthMax(unit)),
		"key via",
		via
	)
end

-- Seconds after the cast before looking: projectiles and the aura's application take a moment.
local AURA_PROBE_DELAY = 1

-- What an aura lookup gave, as text for the log. The aura's fields are checked one by one,
-- since a readable aura may still carry secret fields.
local function DescribeAura(ok, aura)
	if not ok then
		return "error " .. tostring(aura)
	elseif aura == nil then
		return "none"
	elseif issecretvalue(aura) then
		return "secret"
	end
	local points = aura.points and aura.points[1]
	if issecretvalue(aura.expirationTime) or issecretvalue(points) then
		return "secret fields"
	end
	local remaining = aura.expirationTime > 0 and string.format("%.1fs", aura.expirationTime - GetTime()) or "none"
	return string.format(
		"readable remaining %s points %s stacks %s",
		remaining,
		tostring(points),
		tostring(aura.applications)
	)
end

local aurasProbed = {}

local function ProbeAura(name, spellID, kind)
	local unit = "target"
	if kind == "hot" and not (UnitExists(unit) and not UnitCanAttack("player", unit)) then
		unit = "player"
	elseif kind == "dot" and not (UnitExists(unit) and UnitCanAttack("player", unit)) then
		return
	end
	local _, instanceType = IsInInstance()
	local situation = string.format("%d %s %s", spellID, instanceType, InCombatLockdown() and "combat" or "idle")
	if aurasProbed[situation] then
		return
	end
	aurasProbed[situation] = true
	local filter = (kind == "hot" and "HELPFUL" or "HARMFUL") .. "|PLAYER"
	ns.log(
		"AURA",
		name,
		"on",
		unit,
		situation,
		"bySpellID",
		DescribeAura(pcall(C_UnitAuras.GetUnitAuraBySpellID, unit, spellID)),
		"byName",
		DescribeAura(pcall(C_UnitAuras.GetAuraDataBySpellName, unit, name, filter))
	)
end

local playerClass

local handlers = {}

function handlers.PLAYER_ENTERING_WORLD(isInitialLogin, isReloadingUi)
	if isInitialLogin or isReloadingUi then
		local version, build = GetBuildInfo()
		ns.log("CLIENT", version, build, "class", select(2, UnitClass("player")), "level", UnitLevel("player"))
	end
	Probe("entering world")
end

function handlers.ZONE_CHANGED_NEW_AREA()
	Probe("zone")
end

function handlers.ADDON_RESTRICTION_STATE_CHANGED(restriction, state)
	local name = restriction
	for key, value in pairs(Enum.AddOnRestrictionType) do
		if value == restriction then
			name = key
		end
	end
	ns.log("RESTRICTION", name, "state", state)
	Probe("restriction change")
end

function handlers.PLAYER_TARGET_CHANGED()
	ProbeUnit("target")
end

function handlers.UNIT_SPELLCAST_SUCCEEDED(_, _, spellID)
	if issecretvalue(spellID) then
		return
	end
	local name = C_Spell.GetSpellName(spellID)
	local entry = name and ns.Spells.Lookup(name, playerClass)
	if entry then
		C_Timer.After(AURA_PROBE_DELAY, function()
			ProbeAura(name, spellID, entry.kind)
		end)
	end
end

ns.OnInitialize(function()
	playerClass = select(2, UnitClass("player"))
	local frame = CreateFrame("Frame")
	for event in pairs(handlers) do
		if event == "UNIT_SPELLCAST_SUCCEEDED" then
			frame:RegisterUnitEvent(event, "player")
		else
			frame:RegisterEvent(event)
		end
	end
	frame:SetScript("OnEvent", function(_, event, ...)
		handlers[event](...)
	end)
end)
