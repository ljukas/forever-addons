local _, ns = ...

-- Records a run's timeline events (run.events, Database.lua): bosses killed and wiped on, deaths,
-- level-ups and the rare drops someone rolled Need on. First and last kill need no event: the run has their times.
-- Confirmed in game (Shadowfang Keep, 16 November 2026, a 5-player group):
--   ENCOUNTER_START and ENCOUNTER_END fire for every boss with a readable name and outcome;
--   UnitIsDeadOrGhost is readable on party units, in and out of combat;
--   CHAT_MSG_LOOT's text and the item's quality are readable in combat. A line that hands an
--   item to someone carries the looter as playerName2 ("Name Surname", for the player too); the
--   roll chatter around it ("|HlootHistory:..|h[Loot]|h: X has selected Greed for ...") doesn't.
--   A Need shows in that chatter, before the item is handed out, with the same item link:
--   "X has selected Need for: <link>", "You have selected Need for: <link>" and
--   "Need Roll - 25 for <link> by X".
-- Unverified in game: the names of the client's Need formats (collected by name, with the
-- English lines above as the fallback; the LOADED log line says which is in use), a wipe (ENCOUNTER_END with success 0), a feigned death being left out, and
-- that a death is seen soon enough (party deaths are looked for when any unit dies and when
-- combat starts or ends). Everything is still checked with issecretvalue. The EVENT log line
-- shows each event recorded.

local MAX_PARTY_MEMBERS = 4

-- When each encounter in progress started, by its ID.
local pulls = {}
-- Who was dead at the last look, by name (a unit token passes to another member when the group
-- changes), so a death is recorded once.
local dead = {}

-- The item links someone rolled Need on, until the item is handed out.
local needed = {}
-- Lua patterns that find a Need in a loot line, built in OnInitialize.
local needPatterns = {}
-- Used when the client has no Need format this addon can read.
local ENGLISH_NEED = { "selected Need for: ", "Need Roll %- %d+ for " }

-- Patterns from the client's own Need formats: every LOOT_ROLL* global with NEED in its name
-- that takes an argument (the item, and for most who rolled or what). A bare label such
-- as "Need" is left out: it would match an item's name.
local function CollectNeedPatterns()
	local names = {}
	for name, value in pairs(_G) do
		if type(name) == "string" and type(value) == "string" and name:find("^LOOT_ROLL") and name:find("NEED") then
			local pattern, captures = ns.XPMessage.Pattern(value)
			if pattern and #captures >= 1 then
				-- Unanchored: the chat line has a "[Loot]:" link in front of it.
				table.insert(needPatterns, (pattern:gsub("^%^", ""):gsub("%$$", "")))
				table.insert(names, name)
			end
		end
	end
	if #needPatterns == 0 then
		needPatterns = ENGLISH_NEED
	end
	table.sort(names)
	ns.log("LOADED", "need formats", #names > 0 and table.concat(names, " ") or "none: English fallback")
end

local function IsNeed(text)
	for _, pattern in ipairs(needPatterns) do
		if text:find(pattern) then
			return true
		end
	end
	return false
end

local function Add(run, event)
	event.t = GetServerTime()
	ns.DB.AddEvent(run, event)
	ns.log("EVENT", event.kind, event.name or event.level, event.item)
	EventRegistry:TriggerEvent("ForeverDungeonXP.RunsChanged")
end

-- "Name Surname" as party members are keyed (Party.lua) and as loot lines name the looter; nil
-- when unreadable.
local function FullName(unit)
	local name, surname = UnitName(unit)
	if issecretvalue(name) or issecretvalue(surname) or type(name) ~= "string" or name == "" then
		return nil
	end
	return (type(surname) == "string" and surname ~= "") and (name .. " " .. surname) or name
end

-- Records the death of a unit that was alive at the last look. Without a run the state is still
-- kept, so someone already dead on entering isn't counted as dying in the run.
local function LookForDeath(unit)
	local exists = UnitExists(unit)
	if issecretvalue(exists) or not exists then
		return
	end
	local name = FullName(unit)
	if not name then
		return
	end
	local isDead, feigned = UnitIsDeadOrGhost(unit), UnitIsFeignDeath(unit)
	if issecretvalue(isDead) or issecretvalue(feigned) then
		ns.dev:LogOnce("death secret", "EVENT", "a unit's death is secret")
		return
	end
	isDead = isDead and not feigned
	local run = ns.Tracker.CurrentRun()
	if isDead and dead[name] == false and run then
		Add(run, { kind = "death", name = name })
	end
	dead[name] = isDead
end

local function LookForDeaths()
	LookForDeath("player")
	for index = 1, MAX_PARTY_MEMBERS do
		LookForDeath("party" .. index)
	end
end

local handlers = {
	ENCOUNTER_START = function(id)
		if not issecretvalue(id) and id then
			pulls[id] = GetServerTime()
		end
	end,
	ENCOUNTER_END = function(id, name, _, _, success)
		local run = ns.Tracker.CurrentRun()
		if not run or issecretvalue(id) or issecretvalue(name) or issecretvalue(success) or type(name) ~= "string" then
			return
		end
		local pull = id and pulls[id]
		if id then
			pulls[id] = nil
		end
		Add(run, { kind = success == 1 and "boss" or "wipe", name = name, pull = pull })
	end,
	PLAYER_LEVEL_UP = function(level)
		local run = ns.Tracker.CurrentRun()
		if run and not issecretvalue(level) and type(level) == "number" then
			Add(run, { kind = "level", level = level })
		end
	end,
	CHAT_MSG_LOOT = function(text, _, _, _, looter)
		local run = ns.Tracker.CurrentRun()
		if not run or issecretvalue(text) or issecretvalue(looter) then
			return
		end
		local link = text:match("|Hitem:.-|h%[.-%]|h")
		if not link then
			return
		end
		if IsNeed(text) then
			if not needed[link] then
				ns.log("EVENT", "need", link)
			end
			needed[link] = true
			return
		end
		-- Only the line that hands the item to someone names a looter, and only an item someone
		-- rolled Need on is worth a row.
		if type(looter) ~= "string" or looter == "" or text:find("^|HlootHistory") or not needed[link] then
			return
		end
		needed[link] = nil
		-- The quality of an item the client hasn't loaded yet is nil: the link's own colour code
		-- ("|cnIQ3:") then says it.
		local quality = C_Item.GetItemQualityByID(link)
		if issecretvalue(quality) then
			return
		end
		quality = quality or tonumber(text:match("|cnIQ(%d+):"))
		if type(quality) ~= "number" or quality < Enum.ItemQuality.Rare then
			return
		end
		-- The link with its colour, as the chat line has it.
		local colored = text:match("|c.-|Hitem:.-|h%[.-%]|h|r") or link
		Add(run, { kind = "loot", name = looter, item = colored })
	end,
	-- A death shows on the unit, not in an event that names it: looked for whenever something
	-- died and when combat starts or ends.
	UNIT_DIED = LookForDeaths,
	PLAYER_DEAD = LookForDeaths,
	PLAYER_REGEN_DISABLED = LookForDeaths,
	PLAYER_REGEN_ENABLED = LookForDeaths,
	GROUP_ROSTER_UPDATE = LookForDeaths,
	PLAYER_ENTERING_WORLD = function()
		wipe(pulls)
		wipe(dead)
		wipe(needed)
		LookForDeaths()
	end,
}

ns.OnInitialize(function()
	CollectNeedPatterns()
	local frame = CreateFrame("Frame")
	frame:SetScript("OnEvent", function(_, event, ...)
		handlers[event](...)
	end)
	for event in pairs(handlers) do
		frame:RegisterEvent(event)
	end
end)
