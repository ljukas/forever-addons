local ADDON_NAME, ns = ...

-- Launch-day probes, logged only (scripts/devlog.sh) and left out of releases (Dev/). The
-- ones every addon shares (restrictions, unit secrecy) are ForeverDev's own, in its Probes.lua.
--   AURA  whether a tracked spell's aura can be read on its unit after the cast, through the
--         two aura lookups without RequiresUnitAuraAccess (the others error in combat). They
--         return nothing for secret auras, but spells Blizzard flags as never secret would
--         read: those could be tracked from the aura instead of estimated. Once per spell and
--         situation.

if not ns.dev.enabled then
	return
end

-- Seconds after the cast before looking: projectiles and the aura's application take a moment.
local AURA_PROBE_DELAY = 1

-- A readable aura as text for the log. Its fields are checked one by one, since a readable
-- aura may still carry secret fields.
local function DescribeAura(aura)
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

local function ProbeAura(name, spellID, kind)
	local unit = "target"
	if kind == "hot" and not ns.Units.Fits(unit, kind) then
		unit = "player"
	elseif kind == "dot" and not ns.Units.Fits(unit, kind) then
		return
	end
	local situation = spellID .. " " .. ForeverDev.Situation()
	local filter = (kind == "hot" and "HELPFUL" or "HARMFUL") .. "|PLAYER"
	local bySpellID, aura = pcall(C_UnitAuras.GetUnitAuraBySpellID, unit, spellID)
	local byName, namedAura = pcall(C_UnitAuras.GetAuraDataBySpellName, unit, name, filter)
	ns.dev:LogOnce(
		"aura " .. situation,
		"AURA",
		name,
		"on",
		unit,
		situation,
		"bySpellID",
		ForeverDev.Describe(bySpellID, aura, DescribeAura),
		"byName",
		ForeverDev.Describe(byName, namedAura, DescribeAura)
	)
end

local playerClass

ns.OnInitialize(function()
	playerClass = select(2, UnitClass("player"))
	local frame = CreateFrame("Frame")
	frame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
	frame:SetScript("OnEvent", function(_, _, _, _, spellID)
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
	end)
end)
