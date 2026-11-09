local _, ns = ...

-- Collects the completed quests in the log and the XP they reward, and tells ns.OnQuestsChanged
-- (set by ExpBar.lua) when that, or the player's XP, may have changed.

ns.Quests = {}

local requested = {} -- questID -> true once RequestLoadQuestByID was called for it
local lastXPByQuest = {} -- questID -> predicted XP from the last collection (TURNIN log)

-- Returns { count, xp, pending, secret }:
--   count   = completed quests in the log (headers and hidden entries skipped),
--   xp      = their summed reward XP at the current level (0 when pending or secret),
--   pending = some completed quest's reward data isn't loaded yet (a load has been requested),
--   secret  = some reward XP came back secret, so it can't be added up.
function ns.Quests.Collect()
	local count, xp, pending, secret = 0, 0, false, false
	wipe(lastXPByQuest)
	for index = 1, C_QuestLog.GetNumQuestLogEntries() do
		local info = C_QuestLog.GetInfo(index)
		if info and not info.isHeader and not info.isHidden and C_QuestLog.IsComplete(info.questID) then
			local questID = info.questID
			count = count + 1
			if not HaveQuestRewardData(questID) then
				pending = true
				if not requested[questID] then
					requested[questID] = true
					C_QuestLog.RequestLoadQuestByID(questID)
				end
			else
				local reward = GetQuestLogRewardXP(questID)
				if issecretvalue(reward) then
					secret = true
				elseif not secret then
					xp = xp + reward
					lastXPByQuest[questID] = reward
				end
			end
		end
	end
	if pending or secret then
		xp = 0
	end

	if ns.dev.enabled then
		local parts = {}
		for questID, reward in pairs(lastXPByQuest) do
			parts[#parts + 1] = questID .. "=" .. reward
		end
		table.sort(parts)
		local summary = table.concat({ count, xp, tostring(pending), tostring(secret) }, " ")
		ns.dev:LogChanged(
			"collect",
			summary .. " " .. table.concat(parts, ","),
			"XP",
			"count",
			count,
			"xp",
			xp,
			"pending",
			pending,
			"secret",
			secret,
			"secretUnitXP",
			issecretvalue(UnitXP("player")),
			"quests",
			table.concat(parts, ",")
		)
	end

	return { count = count, xp = xp, pending = pending, secret = secret }
end

-- Coalesce bursts of events (QUEST_LOG_UPDATE fires often) into one refresh on the next frame.
local scheduled = false
local function NotifyChanged()
	if scheduled then
		return
	end
	scheduled = true
	C_Timer.After(0, function()
		scheduled = false
		if ns.OnQuestsChanged then
			ns.OnQuestsChanged()
		end
	end)
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("QUEST_LOG_UPDATE")
frame:RegisterEvent("QUEST_DATA_LOAD_RESULT")
frame:RegisterEvent("QUEST_TURNED_IN")
frame:RegisterEvent("PLAYER_LEVEL_UP")
frame:RegisterUnitEvent("PLAYER_XP_UPDATE", "player")
frame:SetScript("OnEvent", function(_, event, ...)
	if event == "QUEST_DATA_LOAD_RESULT" then
		local questID = ...
		requested[questID] = nil
	elseif event == "QUEST_TURNED_IN" then
		local questID, xpReward = ...
		ns.log("TURNIN", "quest", questID, "xpReward", xpReward, "predicted", lastXPByQuest[questID])
	end
	NotifyChanged()
end)
