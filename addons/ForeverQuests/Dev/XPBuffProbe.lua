local _, ns = ...

-- Dev-only probe, logged only (scripts/devlog.sh --tag AURA) and left out of releases (Dev/).
-- Quest turn-ins pay more than GetQuestLogRewardXP reports while an XP buff is up (the
-- Well-Rested buff: +3%, so 650 became 669). No API reports an XP multiplier, so this logs the
-- player's helpful auras (name, spell ID, every points value) to find the buff's spell ID and
-- where its percentage lives. Once per spell ID per session, out of combat only (own auras are
-- readable then).

if not ns.dev.enabled then
	return
end

local WELL_RESTED = "Well-Rested"
local MAX_AURAS = 40

local function PointsText(aura)
	if not aura.points then
		return "none"
	end
	local parts = {}
	for i, value in ipairs(aura.points) do
		parts[i] = issecretvalue(value) and "secret" or tostring(value)
	end
	return "{" .. table.concat(parts, ",") .. "}"
end

local function LogAura(aura, how)
	if issecretvalue(aura.spellId) or issecretvalue(aura.name) then
		ns.dev:LogOnce("secret " .. how, "AURA", how, "secret aura")
		return
	end
	ns.dev:LogOnce(
		how .. " " .. aura.spellId,
		"AURA",
		how,
		"name",
		aura.name,
		"spellId",
		aura.spellId,
		"points",
		PointsText(aura),
		"stacks",
		aura.applications,
		"source",
		aura.sourceUnit
	)
end

local function Probe()
	if InCombatLockdown() then
		return
	end
	for index = 1, MAX_AURAS do
		local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", index, "HELPFUL")
		if not ok then
			ns.dev:LogOnce("byindex error", "AURA", "byIndex error", aura)
			break
		end
		if not aura then
			break
		end
		LogAura(aura, "byIndex")
	end

	local ok, aura = pcall(C_UnitAuras.GetAuraDataBySpellName, "player", WELL_RESTED, "HELPFUL")
	if not ok then
		ns.dev:LogOnce("byname error", "AURA", "byName error", aura)
	elseif aura then
		LogAura(aura, "byName")
	else
		ns.dev:LogOnce("byname none", "AURA", "byName", WELL_RESTED, "not found")
	end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterUnitEvent("UNIT_AURA", "player")
frame:SetScript("OnEvent", Probe)
