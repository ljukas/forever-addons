local _, ns = ...

-- XP buffs that quest turn-ins pay on top of what GetQuestLogRewardXP reports. No API reports
-- an XP multiplier, so known buffs are read from the player's auras. Confirmed in game
-- (2026-11-09): Well-Rested (spell 429959) stacks 1-3 times at +1% each, carries no points
-- value, and a 650 XP quest paid 669 with 3 stacks, i.e. floor(650 * 1.03).
--
-- Own auras are readable out of combat; in combat the last reading is kept, so the
-- prediction doesn't change mid-fight.

ns.XPBonus = {}

-- spellID -> percent per stack
local BUFFS = {
	[429959] = 1, -- Well-Rested
}

local current = { percent = 0, names = {} } -- the last reading

-- Rereads the buffs; does nothing in combat. Returns true when the reading changed.
function ns.XPBonus.Update()
	if InCombatLockdown() then
		return false
	end
	-- UNIT_AURA fires constantly: add up the percent first and build nothing unless it changed.
	local percent = 0
	for spellID, perStack in pairs(BUFFS) do
		local aura = C_UnitAuras.GetPlayerAuraBySpellID(spellID)
		if aura and not issecretvalue(aura.applications) then
			percent = percent + perStack * math.max(aura.applications or 0, 1)
		end
	end
	if percent == current.percent then
		return false
	end

	local names = {}
	for spellID in pairs(BUFFS) do
		local aura = C_UnitAuras.GetPlayerAuraBySpellID(spellID)
		if aura and not issecretvalue(aura.name) then
			names[#names + 1] = aura.name
		end
	end
	table.sort(names)
	current = { percent = percent, names = names }
	ns.log("BONUS", "percent", percent, "buffs", table.concat(names, ","))
	return true
end

-- The XP a quest reporting `reward` pays with the current buffs (the server rounds down).
function ns.XPBonus.Apply(reward)
	if current.percent == 0 then
		return reward
	end
	return math.floor(reward * (100 + current.percent) / 100)
end

-- The current bonus: percent (0 when none) and the buffs' names, for the tooltip.
function ns.XPBonus.Get()
	return current.percent, current.names
end
