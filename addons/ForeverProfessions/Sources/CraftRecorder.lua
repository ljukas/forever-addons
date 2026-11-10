local ADDON_NAME, ns = ...

-- Records every craft into ForeverProfessionsDB.crafts (Database.lua), for the player's own
-- skill-up odds per recipe and skill level. Event order checked in game with Dev/CraftProbe.lua
-- (docs/superpowers/specs/2026-11-07-craft-history-design.md, "Probe results"):
--   TRADE_SKILL_CRAFT_BEGIN   marks the recipe as a real craft; nothing else counts
--   UNIT_SPELLCAST_SUCCEEDED  read the rank and colour; the craft becomes the last finished one.
--                             Not on START: in a Create All queue the previous craft's skill-up
--                             can arrive after the next cast starts, so START may still read the
--                             old rank. By SUCCEEDED (a cast time later) it has arrived, and the
--                             craft's own skill-up hasn't yet.
--   SKILL_LINES_CHANGED       a rank rise is credited to the profession's last finished craft,
--                             ~0.4s after SUCCEEDED
--   TRADE_SKILL_ITEM_CRAFTED_RESULT  items made, ~0.1s after SUCCEEDED, for the last craft
-- Failed and interrupted casts never succeed, so they count for nothing.
--
-- A craft that can still give a point is held (pending) until its outcome is known, then its
-- attempt and skill-up are written together: written at SUCCEEDED, the odds would count it as
-- a miss until the rise arrived. It's settled by the rise, or with no point by the profession's
-- next craft, a gather, logout or the end of its credit time.

-- A skill rise or crafted result this long after a craft finished isn't the craft's. Mining
-- also rises from mining veins, which must not be credited to the last smelt.
local CREDIT_SECONDS = 3

-- Per professionID, the last finished craft: { recipeID, professionID, skillRank, finishedAt },
-- plus { key, difficulty, gray } and pending = true while its attempt isn't written yet.
local lastFinished = {}
-- The last finished craft of any profession, for TRADE_SKILL_ITEM_CRAFTED_RESULT.
local lastCraft
-- Per professionID, the rank last seen, for detecting a rise.
local lastKnownRank = {}

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

-- Writes a pending craft's attempt with the skill points it gave; does nothing once written.
local function Settle(craft, points)
	if not craft.pending then
		return
	end
	craft.pending = nil
	ns.DB.RecordAttempt(craft.key, craft.recipeID, craft.skillRank, craft.difficulty, craft.gray, false, points)
end

local function SettleAll()
	for _, craft in pairs(lastFinished) do
		Settle(craft, 0)
	end
end

-- Returns the recipe, its profession info and the character key, or nil (logged) when the
-- craft can't be recorded.
local function ReadCraft(spellID)
	local recipe = C_TradeSkillUI.GetRecipeInfo(spellID)
	if not recipe then
		return
	end
	-- relativeDifficulty is nilable; a craft without its colour says nothing about the odds.
	if recipe.relativeDifficulty == nil then
		ns.dev:LogOnce("no difficulty " .. spellID, "SECRET", "recipe", spellID, "has no difficulty, not recorded")
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
	-- An empty struct (profession data not loaded) would file a capped craft at rank 0.
	if info.professionID == 0 or info.maxSkillLevel <= 0 then
		ns.dev:LogOnce("no profession " .. spellID, "SECRET", "recipe", spellID, "has no profession info, not recorded")
		return
	end
	local key = ns.GetCharacterKey()
	if not key then
		ns.log("SECRET", "character name, recipe", spellID, "not recorded")
		return
	end
	return recipe, info, key
end

-- Recipes the client has started crafting, per recipeID. The profession spells themselves
-- (Engineering, Smelting: cast to open the window) are accepted by GetRecipeInfo and succeed
-- like a craft, but never begin one.
local begun = {}

local handlers = {}

function handlers.TRADE_SKILL_CRAFT_BEGIN(recipeSpellID)
	if not issecretvalue(recipeSpellID) then
		begun[recipeSpellID] = true
	end
end

function handlers.UNIT_SPELLCAST_SUCCEEDED(_, _, spellID)
	if issecretvalue(spellID) or not begun[spellID] then
		return
	end
	-- A queue's next craft begins after this one succeeds, so clearing here loses nothing.
	begun[spellID] = nil
	local recipe, info, key = ReadCraft(spellID)
	if not (recipe and info and key) then
		-- Not a recorded craft: its items mustn't be credited to the craft before it.
		lastCraft = nil
		return
	end

	local skillRank = info.skillLevel
	local capped = skillRank >= info.maxSkillLevel
	local craft = {
		recipeID = spellID,
		professionID = info.professionID,
		skillRank = skillRank,
		finishedAt = GetTime(),
		key = key,
		difficulty = recipe.relativeDifficulty,
		gray = recipe.maxTrivialLevel,
	}
	-- The profession's previous craft had its chance at a rise; a later one is this craft's.
	if lastFinished[craft.professionID] then
		Settle(lastFinished[craft.professionID], 0)
	end
	if capped then
		-- No point can come from it, so there's nothing to wait for.
		ns.DB.RecordAttempt(key, spellID, skillRank, craft.difficulty, craft.gray, true)
	else
		craft.pending = true
		C_Timer.After(CREDIT_SECONDS, function()
			Settle(craft, 0)
		end)
	end
	lastFinished[craft.professionID] = craft
	lastCraft = craft
	-- Never lowered, so a rise already seen can't be booked a second time.
	lastKnownRank[craft.professionID] = math.max(lastKnownRank[craft.professionID] or 0, skillRank)
	ns.log("CRAFTED", spellID, "rank", skillRank, "difficulty", recipe.relativeDifficulty, "capped", capped)
end

function handlers.TRADE_SKILL_ITEM_CRAFTED_RESULT(data)
	local quantity = data.quantity
	if not IsRecent(lastCraft) or AnySecret(quantity) or not ns.GetCharacterKey() then
		return
	end
	ns.DB.AddMade(ns.GetCharacterKey(), lastCraft.recipeID, quantity)
end

function handlers.SKILL_LINES_CHANGED()
	for professionID, craft in pairs(lastFinished) do
		local info = C_TradeSkillUI.GetProfessionInfoByRecipeID(craft.recipeID)
		local rank = info and info.skillLevel
		if rank and not issecretvalue(rank) and rank ~= lastKnownRank[professionID] then
			local from = lastKnownRank[professionID]
			local points = rank - from
			local credited = false
			if points > 0 and IsRecent(craft) then
				if craft.pending then
					Settle(craft, points)
					credited = true
				elseif ns.GetCharacterKey() then
					credited = ns.DB.RecordSkillUp(ns.GetCharacterKey(), craft.recipeID, craft.skillRank, points)
				end
			end
			if credited then
				ns.log("SKILLUP", craft.recipeID, "rank", craft.skillRank, "points", points)
				-- The rise should start from the rank the craft was filed at; otherwise that rank
				-- was stale and the row is wrong.
				if from ~= craft.skillRank then
					ns.log("LATE", craft.recipeID, "filed at", craft.skillRank, "but the rise is from", from)
				end
			elseif points > 0 then
				ns.log("UNCREDITED", craft.recipeID, "points", points, "age", GetTime() - craft.finishedAt)
			end
			lastKnownRank[professionID] = math.max(from, rank)
		end
		if not IsRecent(craft) then
			Settle(craft, 0)
			lastFinished[professionID] = nil
		end
	end
end

-- SavedVariables are written after PLAYER_LOGOUT (also on /reload), so a craft still waiting
-- for its rise is written now rather than lost.
function handlers.PLAYER_LOGOUT()
	SettleAll()
end

-- A gather ends every craft's credit: Mining rises from veins as well as from smelting, and a
-- vein's skill-up must not land on the smelt before it. GatherRecorder announces each gather.
local function OnGathered()
	SettleAll()
	wipe(lastFinished)
	lastCraft = nil
end

ns.OnInitialize(function()
	ns.callbacks:RegisterCallback("NodesChanged", OnGathered)
	local frame = CreateFrame("Frame")
	for event in pairs(handlers) do
		if event:find("^UNIT_") then
			frame:RegisterUnitEvent(event, "player")
		else
			frame:RegisterEvent(event)
		end
	end
	frame:SetScript("OnEvent", function(_, event, ...)
		handlers[event](...)
	end)
end)
