local ADDON_NAME, ns = ...

local L = ns.L

ns.Professions = {}

-- The gathering professions, by the key ns.GatherNodes and ForeverMapDB.nodes use.
--   name        localized profession name, used when the skill line ID doesn't match
--   skillLineID profession skill line, compared against the node's required skill
-- Skill line IDs are the Classic ones and still need checking in Forever.
local professions = {
	herbalism = { name = L.HERBALISM, skillLineID = 182 },
	mining = { name = L.MINING, skillLineID = 186 },
}

-- Returns the node's data and its profession, or nil if the name isn't a known node.
function ns.Professions.GetNode(name)
	local node = ns.GatherNodes[name]
	if node then
		return node, professions[node.profession]
	end
end

-- Skill lines by localized name, the fallback when a profession's skill line ID doesn't
-- match. Rebuilt lazily after SKILL_LINES_CHANGED.
local skillLinesByName = {}
local stale = true

local function RebuildByName()
	wipe(skillLinesByName)
	for index = 1, C_SkillInfo.GetNumSkillLines() do
		local info = C_SkillInfo.GetSkillLineInfo(index)
		if info and not info.isHeader then
			skillLinesByName[info.name] = info
		end
	end
	stale = false
end

-- By ID first: lines under a header collapsed in the Skills tab drop out of the
-- GetSkillLineInfo(index) enumeration, but not out of GetSkillLineInfoByID.
local function GetSkillLine(profession)
	local info = C_SkillInfo.GetSkillLineInfoByID(profession.skillLineID)
	if info then
		return info
	end
	if stale then
		RebuildByName()
	end
	return skillLinesByName[profession.name]
end

-- Returns the node's required skill, the player's effective rank (nil if not learned),
-- the localized profession name and whether the player is too low to gather it.
-- Returns nil for unknown node names.
function ns.Professions.GetRequirement(nodeName)
	local node, profession = ns.Professions.GetNode(nodeName)
	if not node then
		return nil
	end
	local info = GetSkillLine(profession)
	local rank = info and info.rank + info.modifier
	local name = info and info.name or profession.name
	return node.skill, rank, name, (rank or 0) < node.skill
end

function ns.Professions.IsTooLow(nodeName)
	local _, _, _, tooLow = ns.Professions.GetRequirement(nodeName)
	return tooLow == true
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("SKILL_LINES_CHANGED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:SetScript("OnEvent", function()
	stale = true
	ns.callbacks:TriggerEvent("SkillsChanged")
end)
