local _, ns = ...

-- ForeverDungeonXPDB layout (account-wide):
--   version    = schema version, see migrations below
--   minimap    = { angle = degrees }, the minimap button's place on the minimap's edge, owned by
--                Launcher.lua
--   characters = { [characterKey] = {
--     nextID = the next run's id,
--     open   = { [instanceID] = runID }, the run each dungeon's next visit may continue,
--     closed = { [instanceID] = "reset" }, why a dungeon has no open run, until its next run starts,
--     runs   = { run, ... } in the order they started } }
-- characterKey is "Name-Realm". instanceID is GetInstanceInfo()'s, the same for every run of a
-- dungeon. A run is:
--   id, instanceID, name (the dungeon's), number (1, 2, ... per dungeon),
--   copy       = the instance copy number from a creature's GUID, nil while unknown,
--   openedBy   = why it started: "first", "copy", "alive" or "gap" (Logic/RunRules.lua), "reset"
--                after a seen instance reset, "deleted" replacing a run deleted while recorded,
--   level      = the player's level at its first kill (at its start until then),
--   firstKill, lastKill = GetServerTime() of those kills, nil before the first,
--   xp         = kill experience gained, share = the same as a fraction of a level, summed gain
--                by gain against the level's size at that moment,
--   kills      = kill messages counted, parsed = those whose text named a creature,
--                fallback = those whose text was secret,
--   approximate = true once a kill's text was secret (its XP then comes from the XP bar and may
--                include other gains), died = true from the player's death until the next kill
--                or entry,
--   creatures  = { [name] = { kills, xp, ranks } }, ranks = { [rank] = votes } for "normal",
--                "elite", "rare" and "boss", nil until a rank was seen (Logic/Creatures.lua),
--   unknown    = { kills, xp } for kills whose text was secret, nil without any,
--   party      = { [name] = { class, level, role } }, the party members present at a kill, nil
--                without any: name is "Name" or "Name-Realm", class the class file name
--                ("WARRIOR"), level the latest seen, role "TANK", "HEALER", "DAMAGER" or nil.
-- Runs are kept until the player deletes them (a few KB each). Only this file writes the layout;
-- UI/Journal.lua and Tracker.lua read a run's fields.

ns.DB = {}

local DB_VERSION = 1

local migrations = {
	[1] = function(db)
		if type(db.minimap) ~= "table" then
			db.minimap = {}
		end
		if type(db.characters) ~= "table" then
			db.characters = {}
		end
	end,
}

function ns.DB.Migrate(db)
	-- Data from a newer version of the addon is left alone rather than downgraded.
	local from = type(db.version) == "number" and db.version or 0
	for version = from + 1, DB_VERSION do
		migrations[version](db)
		db.version = version
	end
end

function ns.DB.Minimap()
	return ns.db.minimap
end

-- Makes a character's section safe to use whatever was saved: a damaged file must not make every
-- dungeon entry throw, and a lost nextID must not hand out an id a run already has (deleting by
-- id would then delete the wrong run).
local function IsBucket(bucket)
	if type(bucket) ~= "table" or type(bucket.kills) ~= "number" or type(bucket.xp) ~= "number" then
		return false
	end
	if bucket.ranks == nil then
		return true
	end
	if type(bucket.ranks) ~= "table" then
		return false
	end
	for _, votes in pairs(bucket.ranks) do
		if type(votes) ~= "number" then
			return false
		end
	end
	return true
end

-- Whether a saved run has everything the functions below do arithmetic on.
local function IsRun(run)
	if type(run) ~= "table" or type(run.creatures) ~= "table" then
		return false
	end
	for _, field in ipairs({ "id", "number", "instanceID", "kills", "xp", "share", "parsed", "fallback" }) do
		if type(run[field]) ~= "number" then
			return false
		end
	end
	for _, creature in pairs(run.creatures) do
		if not IsBucket(creature) then
			return false
		end
	end
	if run.party ~= nil then
		if type(run.party) ~= "table" then
			return false
		end
		for _, member in pairs(run.party) do
			if type(member) ~= "table" or type(member.class) ~= "string" then
				return false
			end
		end
	end
	return run.unknown == nil or IsBucket(run.unknown)
end

local function Repair(character)
	if type(character.open) ~= "table" then
		character.open = {}
	end
	if type(character.closed) ~= "table" then
		character.closed = {}
	end
	if type(character.runs) ~= "table" then
		character.runs = {}
	end
	local highest = 0
	for index = #character.runs, 1, -1 do
		local run = character.runs[index]
		if not IsRun(run) then
			table.remove(character.runs, index)
		elseif run.id > highest then
			highest = run.id
		end
	end
	if type(character.nextID) ~= "number" or character.nextID <= highest then
		character.nextID = highest + 1
	end
	-- An open pointer must name a run of that dungeon that still exists: a later run could
	-- otherwise get a removed run's id and be continued from another dungeon.
	local dungeons = {}
	for _, run in ipairs(character.runs) do
		dungeons[run.id] = run.instanceID
	end
	for instanceID, id in pairs(character.open) do
		if dungeons[id] ~= instanceID then
			character.open[instanceID] = nil
		end
	end
end

local repaired = {}

-- The current character's section, or nil while the character key isn't known yet.
function ns.DB.Character()
	local key = ns.CharacterKey()
	if not key then
		return nil
	end
	local character = ns.db.characters[key]
	if type(character) ~= "table" then
		character = {}
		ns.db.characters[key] = character
	end
	if not repaired[character] then
		Repair(character)
		repaired[character] = true
	end
	return character
end

-- The current character's runs in the order they started. Not to be modified.
function ns.DB.Runs()
	local character = ns.DB.Character()
	return character and character.runs or {}
end

function ns.DB.RunByID(id)
	for _, run in ipairs(ns.DB.Runs()) do
		if run.id == id then
			return run
		end
	end
end

-- The run the dungeon's next visit may continue, or nil.
function ns.DB.OpenRun(instanceID)
	local character = ns.DB.Character()
	local id = character and character.open[instanceID]
	return id and ns.DB.RunByID(id) or nil
end

-- Starts a run and makes it the dungeon's open run. Returns nil without a character key. A
-- "first" run of a dungeon whose last run was closed by a reset is recorded as "reset".
function ns.DB.NewRun(instanceID, name, level, openedBy)
	local character = ns.DB.Character()
	if not character then
		return nil
	end
	if openedBy == "first" and character.closed[instanceID] then
		openedBy = character.closed[instanceID]
	end
	character.closed[instanceID] = nil
	local number = 0
	for _, run in ipairs(character.runs) do
		if run.instanceID == instanceID and run.number > number then
			number = run.number
		end
	end
	local run = {
		id = character.nextID,
		instanceID = instanceID,
		name = name,
		number = number + 1,
		openedBy = openedBy,
		level = level,
		xp = 0,
		share = 0,
		kills = 0,
		parsed = 0,
		fallback = 0,
		creatures = {},
	}
	character.nextID = character.nextID + 1
	table.insert(character.runs, run)
	character.open[instanceID] = run.id
	return run
end

-- Makes an existing run its dungeon's open run again.
function ns.DB.ReopenRun(run)
	local character = ns.DB.Character()
	if character then
		character.open[run.instanceID] = run.id
	end
end

-- The dungeon's next visit starts a new run, recorded as opened by reason ("reset").
function ns.DB.CloseRun(instanceID, reason)
	local character = ns.DB.Character()
	if character and character.open[instanceID] then
		character.open[instanceID] = nil
		character.closed[instanceID] = reason
	end
end

function ns.DB.CloseAllRuns(reason)
	local character = ns.DB.Character()
	if character then
		for instanceID in pairs(character.open) do
			character.closed[instanceID] = reason
		end
		wipe(character.open)
	end
end

function ns.DB.SetCopy(run, copy)
	run.copy = copy
end

-- The player died in the run (true), or the death no longer matters (false): Logic/RunRules.lua.
function ns.DB.SetDied(run, died)
	run.died = died or nil
end

-- The current character's latest run of this dungeon with that copy number, or nil.
function ns.DB.RunByCopy(instanceID, copy)
	local runs = ns.DB.Runs()
	for index = #runs, 1, -1 do
		local run = runs[index]
		if run.instanceID == instanceID and run.copy == copy then
			return run
		end
	end
end

function ns.DB.DeleteRun(id)
	local character = ns.DB.Character()
	if not character then
		return
	end
	for index, run in ipairs(character.runs) do
		if run.id == id then
			table.remove(character.runs, index)
			if character.open[run.instanceID] == id then
				character.open[run.instanceID] = nil
			end
			return
		end
	end
end

-- Removes every run that never got a kill, except keep (the run being recorded, or nil): a visit
-- without kills leaves nothing behind.
function ns.DB.DropEmptyRuns(keep)
	local character = ns.DB.Character()
	if not character then
		return
	end
	for index = #character.runs, 1, -1 do
		local run = character.runs[index]
		if run.kills == 0 and run ~= keep then
			table.remove(character.runs, index)
			if character.open[run.instanceID] == run.id then
				character.open[run.instanceID] = nil
			end
		end
	end
end

local function Bucket(run, creatureName)
	if not creatureName then
		run.unknown = run.unknown or { kills = 0, xp = 0 }
		return run.unknown
	end
	local creature = run.creatures[creatureName]
	if not creature then
		creature = { kills = 0, xp = 0 }
		run.creatures[creatureName] = creature
	end
	return creature
end

-- Counts one kill. creatureName nil means the kill message was secret: the kill goes to the
-- unknown bucket and the run becomes approximate; its XP arrives through AddUnknownXP. now is
-- GetServerTime(), level the player's level.
function ns.DB.AddKill(run, creatureName, xp, share, now, level)
	if creatureName then
		run.parsed = run.parsed + 1
	else
		run.fallback = run.fallback + 1
		run.approximate = true
	end
	local bucket = Bucket(run, creatureName)
	bucket.kills = bucket.kills + 1
	bucket.xp = bucket.xp + xp
	if run.kills == 0 then
		run.level = level
	end
	run.kills = run.kills + 1
	run.xp = run.xp + xp
	run.share = run.share + share
	run.firstKill = run.firstKill or now
	run.lastKill = now
	run.died = nil
end

-- Gives a creature of the run one vote for a rank ("normal", "elite", "rare" or "boss"). Does
-- nothing for a creature the run has no kill of.
function ns.DB.AddRank(run, creatureName, rank)
	local creature = run.creatures[creatureName]
	if creature then
		creature.ranks = creature.ranks or {}
		creature.ranks[rank] = (creature.ranks[rank] or 0) + 1
	end
end

-- Records a party member as present in the run, or brings their details up to date. A level
-- the client doesn't know (0 or less, a member out of sight) keeps the one recorded.
function ns.DB.AddPartyMember(run, name, class, level, role)
	run.party = run.party or {}
	local member = run.party[name]
	if not member then
		member = {}
		run.party[name] = member
	end
	member.class = class
	if type(level) == "number" and level > 0 then
		member.level = level
	end
	member.role = role or member.role
end

-- Adds experience (or takes it back, when negative) that no readable message explains, to the
-- unknown bucket.
function ns.DB.AddUnknownXP(run, xp, share)
	local bucket = Bucket(run, nil)
	bucket.xp = bucket.xp + xp
	run.xp = run.xp + xp
	run.share = run.share + share
end

-- Moves everything from's kills gave into into and removes from: the two turned out to be one
-- run (the same instance copy).
function ns.DB.MergeRun(from, into)
	for name, creature in pairs(from.creatures) do
		local bucket = Bucket(into, name)
		bucket.kills = bucket.kills + creature.kills
		bucket.xp = bucket.xp + creature.xp
		for rank, votes in pairs(creature.ranks or {}) do
			bucket.ranks = bucket.ranks or {}
			bucket.ranks[rank] = (bucket.ranks[rank] or 0) + votes
		end
	end
	if from.unknown then
		local bucket = Bucket(into, nil)
		bucket.kills = bucket.kills + from.unknown.kills
		bucket.xp = bucket.xp + from.unknown.xp
	end
	for _, field in ipairs({ "xp", "share", "kills", "parsed", "fallback" }) do
		into[field] = into[field] + from[field]
	end
	for name, member in pairs(from.party or {}) do
		into.party = into.party or {}
		into.party[name] = into.party[name] or member
	end
	into.approximate = into.approximate or from.approximate
	if from.firstKill and (not into.firstKill or from.firstKill < into.firstKill) then
		into.firstKill = from.firstKill
	end
	if from.lastKill and (not into.lastKill or from.lastKill > into.lastKill) then
		into.lastKill = from.lastKill
	end
	ns.DB.DeleteRun(from.id)
end
