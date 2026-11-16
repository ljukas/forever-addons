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
-- Candidate run timeline (first and last kill, boss kills, checkpoints):
--   encounter ENCOUNTER_START/END and BOSS_KILL with their arguments; encounterstate, engage
--             (boss1 at INSTANCE_ENCOUNTER_ENGAGE_UNIT), objective ... and scenario ... events
--   bosses    the dungeon's boss list from the encounter journal, by each route that may exist
--   place     sub-zone, minimap zone and map as they change inside; position whether the
--             player's map position is readable
--   partydead, unitdied, partykill   whether deaths are readable: UnitIsDeadOrGhost on party
--             units, and the GUIDs of UNIT_DIED and PARTY_KILL
--   roster    the group's size as it changes; yell boss yells and whether they are secret;
--   lfg completed   LFG_COMPLETION_REWARD
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

-- Timeline candidates. A global that doesn't exist reads "error ..." through the pcall.
local function Try(fn, ...)
	return ForeverDev.Describe(pcall(fn, ...))
end

local function InDungeon()
	local _, instanceType = IsInInstance()
	return instanceType == "party" or instanceType == "raid"
end

-- place: the sub-zone and map names as they change, for checkpoints like "entered the Forge".
local function LogPlace(event)
	if not InDungeon() then
		return
	end
	local okMap, mapID = pcall(C_Map.GetBestMapForUnit, "player")
	local mapName = "none"
	if okMap and mapID and not issecretvalue(mapID) then
		local info = C_Map.GetMapInfo(mapID)
		mapName = info and info.name or "none"
	end
	local subZone, minimapZone = Try(GetSubZoneText), Try(GetMinimapZoneText)
	local map = ForeverDev.Describe(okMap, mapID)
	ns.dev:LogChanged(
		"place",
		subZone .. "|" .. minimapZone .. "|" .. map,
		"PROBE",
		"place",
		event,
		ForeverDev.Situation(),
		"subzone",
		subZone,
		"minimap",
		minimapZone,
		"map",
		map,
		mapName
	)
	-- Whether the player's position on the map can be read inside (for ordering checkpoints).
	if okMap and mapID and not issecretvalue(mapID) then
		local okPosition, position = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
		local outcome = not okPosition and "error" or (position == nil and "none" or "readable")
		ns.dev:LogOnce("position " .. ForeverDev.Situation() .. " " .. outcome, "PROBE", "position", outcome)
	end
end

-- bosses: the dungeon's boss list from the encounter journal, to show the ones not yet killed
-- and to match ENCOUNTER_START's ID. Each route is tried; Forever may have only some.
local function LogBosses()
	if not InDungeon() then
		return
	end
	local okMap, mapID = pcall(C_Map.GetBestMapForUnit, "player")
	if not okMap or not mapID or issecretvalue(mapID) then
		Log("bosses", "no map", ForeverDev.Describe(okMap, mapID))
		return
	end
	local okInstance, journalID = pcall(C_EncounterJournal.GetInstanceForGameMap, mapID)
	Log("bosses", "map", mapID, "journal instance", ForeverDev.Describe(okInstance, journalID))
	Log("bosses", "EJ_GetInstanceForMap", Try(EJ_GetInstanceForMap, mapID))
	local okList, list = pcall(C_EncounterJournal.GetEncountersOnMap, mapID)
	Log("bosses", "on map", okList and type(list) == "table" and #list or ForeverDev.Describe(okList, list))
	if okList and type(list) == "table" then
		for index, encounter in ipairs(list) do
			if index <= 12 then
				Log(
					"bosses",
					"on map",
					index,
					"id",
					encounter.encounterID,
					Try(EJ_GetEncounterInfo, encounter.encounterID)
				)
			end
		end
	end
	if okInstance and journalID and not issecretvalue(journalID) and journalID > 0 then
		for index = 1, 12 do
			local ok, name, _, encounterID, _, _, _, dungeonEncounterID =
				pcall(EJ_GetEncounterInfoByIndex, index, journalID)
			if not ok or not name then
				Log("bosses", "by index", index, ok and "end" or ("error " .. tostring(name)))
				break
			end
			Log("bosses", "by index", index, name, "journal id", encounterID, "encounter id", dungeonEncounterID)
		end
	end
	Log("bosses", "scenario", Try(C_ScenarioInfo.GetScenarioInfo))
end

-- A unit-death event whose GUID may be secret: once per event, situation and outcome, with the
-- GUID's kind ("Creature", "Player") when readable.
local function LogDeath(kind)
	return function(first, second)
		local guid = second or first
		local outcome = issecretvalue(guid) and "secret" or tostring(guid):match("^%a+") or "none"
		ns.dev:LogOnce(
			kind .. " " .. ForeverDev.Situation() .. " " .. outcome,
			"PROBE",
			kind,
			ForeverDev.Situation(),
			outcome
		)
	end
end

-- An event whose arguments are plain values: logged with them, the first few times.
local function LogEvent(kind)
	return function(...)
		if Few(kind) then
			Log(kind, ForeverDev.Situation(), ...)
		end
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
	-- Only rare (blue) and better would be shown: those are logged, with one sample of any quality
	-- per situation for the line's format and whether the item link and its quality are readable.
	CHAT_MSG_LOOT = function(text, playerName, _, _, playerName2)
		local situation = ForeverDev.Situation()
		if issecretvalue(text) then
			ns.dev:LogOnce("loot secret " .. situation, "PROBE", "loot", situation, "text secret")
			return
		end
		local link = text:match("|Hitem:.-|h%[.-%]|h")
		local quality = link and select(2, pcall(C_Item.GetItemQualityByID, link))
		local who = ForeverDev.SecretNames("playerName", playerName, "playerName2", playerName2)
		ns.dev:LogOnce("loot sample " .. situation, "PROBE", "loot", "sample", situation, "quality", quality, text)
		if type(quality) == "number" and not issecretvalue(quality) and quality >= Enum.ItemQuality.Rare then
			Log("loot", "rare+", situation, "quality", quality, "secret:", who, "by", playerName2, text)
		end
	end,
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
	ENCOUNTER_STATE_CHANGED = LogEvent("encounterstate"),
	INSTANCE_ENCOUNTER_ENGAGE_UNIT = function()
		local exists = UnitExists("boss1")
		local name = UnitName("boss1")
		Log(
			"engage",
			ForeverDev.Situation(),
			"boss1",
			issecretvalue(exists) and "secret" or tostring(exists),
			"name",
			name,
			"in progress",
			Try(C_InstanceEncounter.IsEncounterInProgress)
		)
	end,
	INSTANCE_ENCOUNTER_OBJECTIVE_START = LogEvent("objective start"),
	INSTANCE_ENCOUNTER_OBJECTIVE_UPDATE = LogEvent("objective update"),
	INSTANCE_ENCOUNTER_OBJECTIVE_COMPLETE = LogEvent("objective complete"),
	SCENARIO_UPDATE = LogEvent("scenario update"),
	SCENARIO_CRITERIA_UPDATE = LogEvent("scenario criteria"),
	SCENARIO_COMPLETED = LogEvent("scenario completed"),
	LFG_COMPLETION_REWARD = LogEvent("lfg completed"),
	UNIT_DIED = LogDeath("unitdied"),
	PARTY_KILL = LogDeath("partykill"),
	ZONE_CHANGED = function()
		LogPlace("ZONE_CHANGED")
	end,
	ZONE_CHANGED_INDOORS = function()
		LogPlace("ZONE_CHANGED_INDOORS")
	end,
	ZONE_CHANGED_NEW_AREA = function()
		LogPlace("ZONE_CHANGED_NEW_AREA")
		-- The map may not be ready at PLAYER_ENTERING_WORLD: the boss list is tried here too.
		if InDungeon() then
			ns.dev:LogOnce("bosses " .. tostring(select(8, GetInstanceInfo())), "PROBE", "bosses", "listing")
			LogBosses()
		end
	end,
	GROUP_ROSTER_UPDATE = function()
		local count = GetNumGroupMembers()
		ns.dev:LogChanged("roster", count, "PROBE", "roster", ForeverDev.Situation(), "members", count)
	end,
	CHAT_MSG_MONSTER_YELL = function(text, name)
		local outcome = ForeverDev.SecretNames("text", text, "name", name)
		ns.dev:LogOnce("yell " .. ForeverDev.Situation() .. " " .. outcome, "PROBE", "yell", "secret:", outcome)
		if Few("yell") then
			Log("yell", ForeverDev.Situation(), name, text)
		end
	end,
	PLAYER_ENTERING_WORLD = function(isLogin, isReload)
		Log("world", "login", isLogin, "reload", isReload, "instance", GetInstanceInfo())
		LogPlace("PLAYER_ENTERING_WORLD")
		LogBosses()
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
	-- A probe must never break a run: its errors are logged, once each.
	local ok, problem = pcall(handlers[event], ...)
	if not ok then
		ns.dev:LogOnce("error " .. event .. " " .. tostring(problem), "PROBE", "error", event, problem)
	end
end)
for event in pairs(handlers) do
	frame:RegisterEvent(event)
end
