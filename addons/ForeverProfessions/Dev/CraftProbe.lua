local ADDON_NAME, ns = ...

-- Probe for the craft history recorder (docs/superpowers/specs/2026-11-07-craft-history-design.md,
-- "In-game checks"). Logged only (scripts/devlog.sh --tag CRAFT) and left out of releases (Dev/).
-- Every line starts with a sequence number and GetTime(), so the order of events in a Create All
-- can be read off the devlog:
--   start         a recipe cast began: its recipe info (colour, gray level) and profession rank
--   succeeded, failed, interrupted, stop   how that cast ended
--   craftBegin, craftedResult              the trade skill events, if Forever fires them
--   skillLines    SKILL_LINES_CHANGED, with the last recipe's profession rank when it changed
--   chatSkill     CHAT_MSG_SKILL, the "Your skill in X has increased" line
-- Secret values show as <secret>.

if not ns.dev.enabled then
	return
end

-- Cast events are logged only while a recipe cast is live or this many seconds after one, so
-- the devlog isn't filled with every spell the player casts.
local RECENT_SECONDS = 5

local sequence = 0
local liveCasts = {}
local lastRecipeID
local lastRecipeTime = 0

local function Log(event, ...)
	sequence = sequence + 1
	ns.log("CRAFT", sequence, string.format("%.3f", GetTime()), event, ...)
end

local function IsRecent()
	return next(liveCasts) ~= nil or GetTime() - lastRecipeTime <= RECENT_SECONDS
end

local function IsLive(castGUID)
	return not issecretvalue(castGUID) and liveCasts[castGUID] == true
end

local function LogProfession(event, recipeID)
	local info = C_TradeSkillUI.GetProfessionInfoByRecipeID(recipeID)
	if not info then
		Log(event, "recipe", recipeID, "no profession info")
		return
	end
	Log(
		event,
		"recipe",
		recipeID,
		"professionID",
		info.professionID,
		"profession",
		info.professionName,
		"skillLevel",
		info.skillLevel,
		"skillModifier",
		info.skillModifier,
		"maxSkillLevel",
		info.maxSkillLevel
	)
	return info
end

local handlers = {}

function handlers.UNIT_SPELLCAST_START(_, castGUID, spellID)
	if issecretvalue(spellID) or issecretvalue(castGUID) then
		Log(
			"start",
			"castGUID",
			castGUID,
			"spellID",
			spellID,
			"secrets",
			ForeverDev.SecretNames("castGUID", castGUID, "spellID", spellID)
		)
		return
	end
	local recipe = C_TradeSkillUI.GetRecipeInfo(spellID)
	if not recipe then
		ns.dev:LogOnce("not a recipe " .. spellID, "CRAFT", "not a recipe", spellID)
		return
	end
	-- Seen in game: a recipe START with no castGUID while another cast of it was live.
	if castGUID == nil then
		Log("startNoGUID", "spellID", spellID, "lastRecipeID", lastRecipeID)
		return
	end
	liveCasts[castGUID] = true
	lastRecipeID = spellID
	lastRecipeTime = GetTime()
	Log(
		"start",
		"castGUID",
		castGUID,
		"spellID",
		spellID,
		"recipe",
		recipe.name,
		"relativeDifficulty",
		recipe.relativeDifficulty,
		"maxTrivialLevel",
		recipe.maxTrivialLevel,
		"numSkillUps",
		recipe.numSkillUps,
		"canSkillUp",
		recipe.canSkillUp
	)
	LogProfession("startRank", spellID)
end

local function OnCastEnd(name, castGUID)
	if IsLive(castGUID) or (issecretvalue(castGUID) and IsRecent()) then
		Log(name, "castGUID", castGUID)
	end
end

function handlers.UNIT_SPELLCAST_SUCCEEDED(_, castGUID)
	OnCastEnd("succeeded", castGUID)
	if IsLive(castGUID) then
		lastRecipeTime = GetTime()
	end
end

function handlers.UNIT_SPELLCAST_FAILED(_, castGUID)
	OnCastEnd("failed", castGUID)
end

function handlers.UNIT_SPELLCAST_INTERRUPTED(_, castGUID)
	OnCastEnd("interrupted", castGUID)
end

-- STOP is the last event of a cast, so the cast stops being live here.
function handlers.UNIT_SPELLCAST_STOP(_, castGUID)
	OnCastEnd("stop", castGUID)
	if IsLive(castGUID) then
		liveCasts[castGUID] = nil
	end
end

function handlers.TRADE_SKILL_CRAFT_BEGIN(recipeSpellID)
	Log("craftBegin", "recipeSpellID", recipeSpellID)
end

function handlers.TRADE_SKILL_ITEM_CRAFTED_RESULT(data)
	Log("craftedResult", "itemID", data.itemID, "quantity", data.quantity, "multicraft", data.multicraft)
end

function handlers.SKILL_LINES_CHANGED()
	if not lastRecipeID then
		return
	end
	local info = C_TradeSkillUI.GetProfessionInfoByRecipeID(lastRecipeID)
	local level = info and info.skillLevel
	if level == nil or issecretvalue(level) then
		Log("skillLines", "skillLevel", level)
	else
		ns.dev:LogChanged(
			"skill " .. info.professionID,
			level,
			"CRAFT",
			"skillLines",
			"profession",
			info.professionName,
			"skillLevel",
			level,
			"at",
			string.format("%.3f", GetTime())
		)
	end
end

function handlers.CHAT_MSG_SKILL(text)
	Log("chatSkill", text)
end

local UNIT_EVENTS = {
	UNIT_SPELLCAST_START = true,
	UNIT_SPELLCAST_SUCCEEDED = true,
	UNIT_SPELLCAST_FAILED = true,
	UNIT_SPELLCAST_INTERRUPTED = true,
	UNIT_SPELLCAST_STOP = true,
}

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
