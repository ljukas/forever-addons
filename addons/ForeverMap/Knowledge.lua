local ADDON_NAME, ns = ...

-- What ForeverMap sees in game, kept so Data/GatherNodes.lua and the skill line IDs in
-- Professions.lua can be checked against evidence. Trace lines go through ns.log (scripts/devlog.sh
-- --addon ForeverMap): GATHER, NEW, AGAIN from Sources/GatherRecorder.lua, SKILL and UNLISTED
-- from here.
-- Aggregates are kept across sessions in ForeverDevDB.observed.ForeverMap (scripts/observed.sh
-- ForeverMap) until /fdev forget ForeverMap:
--   nodes[nodeName]          = { gathers, new, lastSeen, spellIDs = { [spellID] = count },
--                                maps = { [uiMapID] = count } }
--   unlisted[name]           = { casts, lastSeen, spellIDs }: casts of a gathering spell on
--                              something that isn't in Data/GatherNodes.lua, nodes to add
--   skillLines[skillLineID]  = { name, rank, modifier, maxRank, lastSeen }
-- lastSeen is a time() stamp. Gathering spells are the spell IDs seen gathering a known node.

-- Players without ForeverDev record nothing.
if not ns.dev.enabled then
	ns.Knowledge = ns.Inert()
	return
end
ns.Knowledge = {}

local NODE = { gathers = 0, new = 0, spellIDs = {}, maps = {} }
local UNLISTED = { casts = 0, spellIDs = {} }

local gatherSpells = {}

-- A known node was gathered; isNew when it was recorded for the first time.
function ns.Knowledge.Gathered(name, mapID, spellID, isNew)
	local node = ns.dev:Observed(NODE, "nodes", name)
	node.gathers = node.gathers + 1
	node.new = node.new + (isNew and 1 or 0)
	node.lastSeen = time()
	ForeverDev.Count(node.maps, mapID)
	if not issecretvalue(spellID) then
		ForeverDev.Count(node.spellIDs, spellID)
		gatherSpells[spellID] = true
	end
end

-- A cast on something that isn't a known node: recorded when it's a gathering spell.
function ns.Knowledge.OtherCast(target, spellID)
	if not target or target == "" or issecretvalue(spellID) or not gatherSpells[spellID] then
		return
	end
	local unlisted = ns.dev:Observed(UNLISTED, "unlisted", target)
	unlisted.casts = unlisted.casts + 1
	unlisted.lastSeen = time()
	ForeverDev.Count(unlisted.spellIDs, spellID)
	ns.dev:LogOnce("unlisted " .. target, "UNLISTED", target, "spellID", spellID)
end

local function RecordSkillLines()
	for index = 1, C_SkillInfo.GetNumSkillLines() do
		local info = C_SkillInfo.GetSkillLineInfo(index)
		if info and not info.isHeader then
			local skillLine = ns.dev:Observed(nil, "skillLines", info.skillID)
			skillLine.name = info.name
			skillLine.rank = info.rank
			skillLine.modifier = info.modifier
			skillLine.maxRank = info.maxRank
			skillLine.lastSeen = time()
			ns.dev:LogOnce(
				"skill " .. info.skillID,
				"SKILL",
				info.skillID,
				info.name,
				info.rank,
				info.modifier,
				info.maxRank
			)
		end
	end
end

ns.OnInitialize(function()
	for _, node in pairs(ns.dev:Observed(nil, "nodes")) do
		for spellID in pairs(node.spellIDs) do
			gatherSpells[spellID] = true
		end
	end
	local frame = CreateFrame("Frame")
	frame:RegisterEvent("PLAYER_ENTERING_WORLD")
	frame:RegisterEvent("SKILL_LINES_CHANGED")
	frame:SetScript("OnEvent", RecordSkillLines)
end)
