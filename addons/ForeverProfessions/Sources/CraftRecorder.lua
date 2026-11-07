local ADDON_NAME, ns = ...

-- Records every craft into ForeverProfessionsDB.crafts (Database.lua), for the player's own
-- skill-up odds per recipe and skill level. Event order checked in game with Dev/CraftProbe.lua
-- (docs/superpowers/specs/2026-11-07-craft-history-design.md, "Probe results"):
--   UNIT_SPELLCAST_START      snapshot the rank and colour for this cast. Each cast of a Create
--                             All queue gets its own. Not TRADE_SKILL_CRAFT_BEGIN: in a queue
--                             it fires before the previous craft's skill-up.
--   UNIT_SPELLCAST_SUCCEEDED  count the attempt; the craft becomes the last finished one
--   SKILL_LINES_CHANGED       a rank rise is credited to the profession's last finished craft,
--                             never to one only started. It arrives in the same frame as the
--                             next cast's START, before it.
--   TRADE_SKILL_ITEM_CRAFTED_RESULT  items made, ~0.1s after SUCCEEDED, for the last craft
-- Failed and interrupted casts count for nothing.

-- A skill rise or crafted result this long after a craft finished isn't the craft's. Mining
-- also rises from mining veins, which must not be credited to the last smelt.
local CREDIT_SECONDS = 3

-- The craft in progress, per castGUID: { recipeID, professionID, skillRank, maxRank,
-- difficulty, gray }.
local snapshots = {}
-- Per professionID, the last finished craft: a snapshot plus finishedAt (GetTime()).
local lastFinished = {}
-- The last finished craft of any profession, for TRADE_SKILL_ITEM_CRAFTED_RESULT.
local lastCraft
-- Per professionID, the rank last seen, for detecting a rise.
local lastKnownRank = {}

local characterKey

-- "Name-Realm", or nil while the client keeps the name secret.
local function GetCharacterKey()
	if not characterKey then
		local name = UnitName("player")
		local realm = GetNormalizedRealmName()
		if name and realm and not issecretvalue(name) and not issecretvalue(realm) then
			characterKey = name .. "-" .. realm
		end
	end
	return characterKey
end

local function AnySecret(...)
	for i = 1, select("#", ...) do
		if issecretvalue((select(i, ...))) then
			return true
		end
	end
	return false
end

local function IsRecent(craft)
	return craft ~= nil and GetTime() - craft.finishedAt <= CREDIT_SECONDS
end

local handlers = {}

function handlers.UNIT_SPELLCAST_START(_, castGUID, spellID)
	if AnySecret(castGUID, spellID) then
		return
	end
	local recipe = C_TradeSkillUI.GetRecipeInfo(spellID)
	if not recipe then
		return
	end
	local info = C_TradeSkillUI.GetProfessionInfoByRecipeID(spellID)
	if
		not info
		or AnySecret(
			info.professionID,
			info.skillLevel,
			info.maxSkillLevel,
			recipe.relativeDifficulty,
			recipe.maxTrivialLevel
		)
	then
		ns.log("SECRET", "recipe", spellID, "not recorded")
		return
	end
	snapshots[castGUID] = {
		recipeID = spellID,
		professionID = info.professionID,
		skillRank = info.skillLevel,
		maxRank = info.maxSkillLevel,
		difficulty = recipe.relativeDifficulty,
		gray = recipe.maxTrivialLevel,
	}
end

function handlers.UNIT_SPELLCAST_SUCCEEDED(_, castGUID)
	local craft = not issecretvalue(castGUID) and snapshots[castGUID]
	if not craft then
		return
	end
	snapshots[castGUID] = nil
	local key = GetCharacterKey()
	if not key then
		ns.log("SECRET", "character name, recipe", craft.recipeID, "not recorded")
		return
	end

	local capped = craft.skillRank >= craft.maxRank
	ns.DB.RecordAttempt(key, craft.recipeID, craft.skillRank, craft.difficulty, craft.gray, capped)
	craft.finishedAt = GetTime()
	lastFinished[craft.professionID] = craft
	lastCraft = craft
	lastKnownRank[craft.professionID] = craft.skillRank
	ns.log("CRAFTED", craft.recipeID, "rank", craft.skillRank, "difficulty", craft.difficulty, "capped", capped)
end

function handlers.UNIT_SPELLCAST_FAILED(_, castGUID)
	if not issecretvalue(castGUID) then
		snapshots[castGUID] = nil
	end
end
handlers.UNIT_SPELLCAST_INTERRUPTED = handlers.UNIT_SPELLCAST_FAILED
-- Every cast ends with STOP, after SUCCEEDED, so no snapshot outlives its cast.
handlers.UNIT_SPELLCAST_STOP = handlers.UNIT_SPELLCAST_FAILED

function handlers.TRADE_SKILL_ITEM_CRAFTED_RESULT(data)
	local quantity = data.quantity
	if not IsRecent(lastCraft) or AnySecret(quantity) or not GetCharacterKey() then
		return
	end
	ns.DB.AddMade(characterKey, lastCraft.recipeID, quantity)
end

local function IsInFlight(professionID)
	for _, craft in pairs(snapshots) do
		if craft.professionID == professionID then
			return true
		end
	end
	return false
end

function handlers.SKILL_LINES_CHANGED()
	for professionID, craft in pairs(lastFinished) do
		local info = C_TradeSkillUI.GetProfessionInfoByRecipeID(craft.recipeID)
		local rank = info and info.skillLevel
		if rank and not issecretvalue(rank) and rank ~= lastKnownRank[professionID] then
			local points = rank - lastKnownRank[professionID]
			if points > 0 and IsRecent(craft) and GetCharacterKey() then
				ns.DB.RecordSkillUp(characterKey, craft.recipeID, craft.skillRank, points)
				ns.log("SKILLUP", craft.recipeID, "rank", craft.skillRank, "points", points)
				if IsInFlight(professionID) then
					ns.dev:LogOnce("late " .. professionID, "LATE", "skill rise with a craft in flight", professionID)
				end
			end
			lastKnownRank[professionID] = rank
		end
		if not IsRecent(craft) then
			lastFinished[professionID] = nil
		end
	end
end

local UNIT_EVENTS = {
	UNIT_SPELLCAST_START = true,
	UNIT_SPELLCAST_SUCCEEDED = true,
	UNIT_SPELLCAST_FAILED = true,
	UNIT_SPELLCAST_INTERRUPTED = true,
	UNIT_SPELLCAST_STOP = true,
}

ns.OnInitialize(function()
	local frame = CreateFrame("Frame")
	for event in pairs(handlers) do
		if UNIT_EVENTS[event] then
			frame:RegisterUnitEvent(event, "player")
		else
			frame:RegisterEvent(event)
		end
	end
	frame:SetScript("OnEvent", function(_, event, ...)
		handlers[event](...)
	end)
end)
