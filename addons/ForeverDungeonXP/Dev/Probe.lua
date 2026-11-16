local _, ns = ...

-- Dev-only: logs what the design assumes about the client and only the game can show (PROBE).
--   strings   every global format string for kill experience and instance resets, with its value
--   xpmsg     each CHAT_MSG_COMBAT_XP_GAIN: its text (or <secret>), which payload fields are
--             secret, and the XP bar at that moment
--   xpupdate  each PLAYER_XP_UPDATE with the XP bar, so the order against xpmsg shows
--   rest      the rested pool and rest state at each of those and at UPDATE_EXHAUSTION: the game's
--             kill text has no rested bracket, so the pool's drop per kill is the only trace
--   restcheck whether the pool drops by exactly the kills' experience (in a group, in a dungeon)
--   loot, money, rep, wallet   candidate "what a run gave": the chat lines and GetMoney()
--   encounter, partydead       candidate boss timeline: ENCOUNTER_START/END and BOSS_KILL with
--             their arguments, and whether a party member's death is readable
--   quest     candidate quest experience per run: QUEST_TURNED_IN's rewards
--   world     PLAYER_ENTERING_WORLD's flags and GetInstanceInfo()
--   guid      whether a creature's GUID is readable, per unit token and situation
--   system    system messages mentioning a reset, when readable
--   death     PLAYER_DEAD / PLAYER_UNGHOST with the dead, ghost and instance state
if not ns.dev.enabled then
	return
end

local function Log(...)
	ns.log("PROBE", ...)
end

-- True for the first lines of a kind in each situation, then false: a line per kill fills the
-- log's cap in one dungeon run and pushes the one-off lines (strings, world, guid) out of it.
local FEW = 6
local counts = {}

local function Few(kind)
	local key = kind .. " " .. ForeverDev.Situation()
	counts[key] = (counts[key] or 0) + 1
	return counts[key] <= FEW
end

local function LogStrings()
	local names = {}
	for name, value in pairs(_G) do
		if
			type(name) == "string"
			and type(value) == "string"
			and (name:find("^COMBATLOG_XPGAIN") or name:find("INSTANCE_RESET") or name:find("XP_GAIN"))
		then
			table.insert(names, name)
		end
	end
	table.sort(names)
	Log("strings", "count", #names)
	for _, name in ipairs(names) do
		Log("strings", name, "=", _G[name])
	end
end

local function XPBar()
	return ForeverDev.Describe(pcall(UnitXP, "player")) .. "/" .. ForeverDev.Describe(pcall(UnitXPMax, "player"))
end

-- The rested pool (GetXPExhaustion: nil when not rested) and the rest state's ID, name and factor.
local function Rest()
	local ok, id, name, factor = pcall(GetRestState)
	local pool = ForeverDev.Describe(pcall(GetXPExhaustion))
	return "pool",
		pool,
		"state",
		ForeverDev.Describe(ok, id),
		ForeverDev.Describe(ok, name),
		ForeverDev.Describe(ok, factor)
end

local function LogGUID(source, unit)
	local exists = UnitExists(unit)
	if issecretvalue(exists) or not exists then
		return
	end
	local attackable = UnitCanAttack("player", unit)
	if issecretvalue(attackable) or not attackable then
		return
	end
	local situation = ForeverDev.Situation(unit)
	local guid = UnitGUID(unit)
	local secret = issecretvalue(guid)
	-- One line per source, situation and outcome: nameplates would flood the log otherwise.
	ns.dev:LogOnce(
		"guid " .. source .. " " .. situation .. " " .. tostring(secret),
		"PROBE",
		"guid",
		source,
		situation,
		"shouldBeSecret",
		ForeverDev.Describe(pcall(C_Secrets.ShouldUnitIdentityBeSecret, unit)),
		"guid",
		guid
	)
end

-- restcheck: does the rested pool drop by exactly the kills' experience, as it did solo in the
-- open world? The kills' experience since the last pool change is held here with the pool as it
-- stood at the first of them. English text only: fine for a dev probe.
local pendingXP, pendingPool = 0, nil

local function HoldKill(text)
	if issecretvalue(text) then
		return
	end
	local xp = tonumber(text:match("^.+ dies, you gain (%d+) experience"))
	local pool = GetXPExhaustion()
	if not xp or issecretvalue(pool) then
		return
	end
	if pendingXP == 0 then
		pendingPool = pool
	end
	pendingXP = pendingXP + xp
end

local function CheckPool()
	local pool = GetXPExhaustion()
	local xp, before = pendingXP, pendingPool
	pendingXP, pendingPool = 0, nil
	if xp == 0 or not before or issecretvalue(pool) then
		return
	end
	local drop = before - (pool or 0)
	local outcome = drop == xp and "equal" or (pool == nil and "pool emptied" or "differs")
	-- Once per situation and outcome, plus the first few that differ with their numbers.
	ns.dev:LogOnce("restcheck " .. ForeverDev.Situation() .. " " .. outcome, "PROBE", "restcheck", outcome)
	if outcome ~= "equal" and Few("restcheck") then
		Log("restcheck", outcome, ForeverDev.Situation(), "kills xp", xp, "pool", before, "to", pool, "drop", drop)
	end
end

-- Whether a party member's death can be read, once per situation and outcome (for a run's deaths).
local function LogPartyDeaths()
	for index = 1, 4 do
		local unit = "party" .. index
		local exists = UnitExists(unit)
		if not issecretvalue(exists) and exists then
			local dead = UnitIsDeadOrGhost(unit)
			local outcome = issecretvalue(dead) and "secret" or tostring(dead)
			ns.dev:LogOnce(
				"partydead " .. ForeverDev.Situation() .. " " .. outcome,
				"PROBE",
				"partydead",
				ForeverDev.Situation(),
				outcome
			)
		end
	end
end

-- A chat line that a feature would read (loot, money, reputation): its text and what is secret.
local function LogChat(kind)
	return function(text, playerName, _, _, playerName2, _, _, _, _, _, _, guid)
		if Few(kind) then
			Log(
				kind,
				ForeverDev.Situation(),
				"secret:",
				ForeverDev.SecretNames("text", text, "playerName", playerName, "playerName2", playerName2, "guid", guid),
				"text",
				text
			)
		end
	end
end

-- An encounter event: its arguments, with the ones that are secret named.
local function LogEncounter(kind)
	return function(id, name, difficulty, size, success)
		Log(
			"encounter",
			kind,
			ForeverDev.Situation(),
			"secret:",
			ForeverDev.SecretNames("id", id, "name", name, "difficulty", difficulty, "size", size, "success", success),
			id,
			name,
			difficulty,
			size,
			success
		)
	end
end

local handlers = {
	PLAYER_LOGIN = LogStrings,
	CHAT_MSG_COMBAT_XP_GAIN = function(text, playerName, _, _, playerName2, _, _, _, _, _, _, guid)
		HoldKill(text)
		if not Few("xpmsg") then
			return
		end
		Log(
			"xpmsg",
			ForeverDev.Situation(),
			"secret:",
			ForeverDev.SecretNames("text", text, "playerName", playerName, "playerName2", playerName2, "guid", guid),
			"bar",
			XPBar(),
			"text",
			text
		)
		Log("rest", "at xpmsg", Rest())
	end,
	PLAYER_XP_UPDATE = function()
		if Few("xpupdate") then
			Log("xpupdate", ForeverDev.Situation(), "bar", XPBar())
			Log("rest", "at xpupdate", Rest())
		end
	end,
	UPDATE_EXHAUSTION = function()
		CheckPool()
		if Few("exhaustion") then
			Log("rest", "changed", ForeverDev.Situation(), "bar", XPBar(), Rest())
		end
	end,
	PLAYER_LEVEL_UP = function(level)
		Log("rest", "level up", level, ForeverDev.Situation(), "bar", XPBar(), Rest())
	end,
	-- Candidate: loot, money and reputation per run.
	CHAT_MSG_LOOT = LogChat("loot"),
	CHAT_MSG_MONEY = LogChat("money"),
	CHAT_MSG_COMBAT_FACTION_CHANGE = LogChat("rep"),
	PLAYER_MONEY = function()
		if Few("wallet") then
			Log("wallet", ForeverDev.Situation(), ForeverDev.Describe(pcall(GetMoney)))
		end
	end,
	-- Candidate: a boss timeline per run, with wipes and deaths.
	ENCOUNTER_START = LogEncounter("start"),
	ENCOUNTER_END = LogEncounter("end"),
	BOSS_KILL = LogEncounter("bosskill"),
	PLAYER_REGEN_ENABLED = LogPartyDeaths,
	PLAYER_REGEN_DISABLED = LogPartyDeaths,
	-- Candidate: quest experience earned inside the dungeon, apart from kills.
	QUEST_TURNED_IN = function(questID, xpReward, moneyReward)
		Log(
			"quest",
			ForeverDev.Situation(),
			"secret:",
			ForeverDev.SecretNames("questID", questID, "xp", xpReward, "money", moneyReward),
			questID,
			xpReward,
			moneyReward,
			"bar",
			XPBar()
		)
	end,
	PLAYER_ENTERING_WORLD = function(isLogin, isReload)
		Log("world", "login", isLogin, "reload", isReload, "instance", GetInstanceInfo())
	end,
	PLAYER_TARGET_CHANGED = function()
		LogGUID("target", "target")
	end,
	UPDATE_MOUSEOVER_UNIT = function()
		LogGUID("mouseover", "mouseover")
	end,
	NAME_PLATE_UNIT_ADDED = function(unit)
		LogGUID("nameplate", unit)
	end,
	CHAT_MSG_SYSTEM = function(text)
		if issecretvalue(text) then
			ns.dev:LogOnce(
				"system secret " .. ForeverDev.Situation(),
				"PROBE",
				"system",
				ForeverDev.Situation(),
				"secret"
			)
		elseif text:lower():find("reset") then
			Log("system", ForeverDev.Situation(), text)
		end
	end,
	PLAYER_DEAD = function()
		Log("death", "dead", UnitIsDeadOrGhost("player"), "ghost", UnitIsGhost("player"), "instance", IsInInstance())
	end,
	PLAYER_UNGHOST = function()
		Log("death", "unghost", UnitIsDeadOrGhost("player"), "ghost", UnitIsGhost("player"), "instance", IsInInstance())
	end,
}

local frame = CreateFrame("Frame")
frame:SetScript("OnEvent", function(_, event, ...)
	handlers[event](...)
end)
for event in pairs(handlers) do
	frame:RegisterEvent(event)
end
