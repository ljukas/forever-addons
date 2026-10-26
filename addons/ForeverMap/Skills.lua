local ADDON_NAME, ns = ...

ns.Skills = {}

-- Skill lines by localized name, the fallback when a layer's skill line ID doesn't match.
-- Rebuilt lazily after SKILL_LINES_CHANGED.
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
local function GetSkillLine(layer)
	local info = C_SkillInfo.GetSkillLineInfoByID(layer.skillLineID)
	if info then
		return info
	end
	if stale then
		RebuildByName()
	end
	return skillLinesByName[layer.profession]
end

-- Returns the node's required skill, the player's effective rank (nil if not learned),
-- the localized profession name and whether the player is too low to gather it.
-- Returns nil for unknown node names.
function ns.Skills.GetRequirement(nodeName)
	local node, layer = ns.Layers.GetNode(nodeName)
	if not node then
		return nil
	end
	local info = GetSkillLine(layer)
	local rank = info and info.rank + info.modifier
	local profession = info and info.name or layer.profession
	return node.skill, rank, profession, (rank or 0) < node.skill
end

function ns.Skills.IsTooLow(nodeName)
	local _, _, _, tooLow = ns.Skills.GetRequirement(nodeName)
	return tooLow == true
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("SKILL_LINES_CHANGED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:SetScript("OnEvent", function()
	stale = true
	ns.callbacks:TriggerEvent("SkillsChanged")
end)
