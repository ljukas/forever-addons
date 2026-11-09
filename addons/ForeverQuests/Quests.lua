local _, ns = ...

-- Collects the completed quests in the log and the XP they reward, and tells ns.OnQuestsChanged
-- (set by ExpBar.lua) when that, or the player's XP, may have changed.

ns.Quests = {}

-- How long to wait for a quest's reward data before counting it as it reads. Blizzard's quest
-- log reads GetQuestLogRewardXP without waiting, so for log quests the data is normally there;
-- this only keeps a quest that never reports it from holding the display on "loading" forever.
local REWARD_WAIT = 5

local requestedAt = {} -- questID -> GetTime() of its one reward-data request this session
local predicted = {} -- questID -> last predicted XP, for the TURNIN log (dev only)
local cache -- the last Collect() result; nil once something changed

-- Returns { count, xp, pending, secret }:
--   count   = completed quests in the log (headers and hidden entries skipped),
--   xp      = their summed reward XP at the current level (0 when pending or secret),
--   pending = some completed quest's reward data is still being waited for,
--   secret  = some reward XP came back secret, so it can't be added up.
-- Cached until a quest or XP event (see Invalidate below).
function ns.Quests.Collect()
	if cache then
		return cache
	end
	local count, xp, pending, secret = 0, 0, false, false
	local now = GetTime()
	local parts = ns.dev.enabled and {} or nil
	for index = 1, C_QuestLog.GetNumQuestLogEntries() do
		local info = C_QuestLog.GetInfo(index)
		if info and not info.isHeader and not info.isHidden and C_QuestLog.IsComplete(info.questID) then
			local questID = info.questID
			count = count + 1
			local haveData = HaveQuestRewardData(questID)
			if not haveData and not requestedAt[questID] then
				requestedAt[questID] = now
				C_TaskQuest.RequestPreloadRewardData(questID)
				C_Timer.After(REWARD_WAIT + 0.1, ns.Quests.Invalidate)
			end
			if not haveData and now - requestedAt[questID] < REWARD_WAIT then
				pending = true
			else
				local reward = GetQuestLogRewardXP(questID)
				if issecretvalue(reward) then
					secret = true
				else
					xp = xp + reward
					if parts then
						predicted[questID] = reward
					end
				end
				if parts then
					parts[#parts + 1] = questID
						.. "="
						.. (issecretvalue(reward) and "secret" or reward)
						.. (haveData and "" or "(nodata)")
				end
			end
		end
	end
	if pending or secret then
		xp = 0
	end
	cache = { count = count, xp = xp, pending = pending, secret = secret }

	if parts then
		local unitXPSecret = issecretvalue(UnitXP("player"))
		local maxSecret = issecretvalue(UnitXPMax("player"))
		local quests = table.concat(parts, ",")
		ns.dev:LogChanged(
			"collect",
			table.concat({ count, xp, tostring(pending), tostring(secret), tostring(unitXPSecret), quests }, " "),
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
			unitXPSecret,
			"secretUnitXPMax",
			maxSecret,
			"combat",
			InCombatLockdown(),
			"quests",
			quests
		)
	end
	return cache
end

-- Coalesce bursts of events (QUEST_LOG_UPDATE fires often) into one refresh on the next frame.
local scheduled = false
function ns.Quests.Invalidate()
	cache = nil
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
frame:RegisterEvent("ENABLE_XP_GAIN")
frame:RegisterEvent("DISABLE_XP_GAIN")
frame:RegisterUnitEvent("PLAYER_XP_UPDATE", "player")
frame:SetScript("OnEvent", function(_, event, ...)
	if event == "QUEST_TURNED_IN" and ns.dev.enabled then
		local questID, xpReward = ...
		ns.log("TURNIN", "quest", questID, "xpReward", xpReward, "predicted", predicted[questID])
		predicted[questID] = nil
	end
	ns.Quests.Invalidate()
end)
