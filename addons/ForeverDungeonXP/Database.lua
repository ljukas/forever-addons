local _, ns = ...

-- ForeverDungeonXPDB layout (account-wide):
--   version    = schema version, see migrations below
--   minimap    = { angle = degrees }, the minimap button's place on the minimap's edge, owned by
--                Launcher.lua
--   characters = { [characterKey] = {
--     nextID = the next run's id,
--     open   = { [instanceID] = runID }, the run each dungeon's next visit may continue,
--     runs   = { run, ... } in the order they started } }
-- characterKey is "Name-Realm". instanceID is GetInstanceInfo()'s, the same for every run of a
-- dungeon. A run is:
--   id, instanceID, name (the dungeon's), number (1, 2, ... per dungeon),
--   copy       = the instance copy number from a creature's GUID, nil while unknown,
--   openedBy   = why it started: "first", "copy", "alive", "gap" or "reset" (Logic/RunRules.lua),
--   level      = the player's level when it started,
--   firstKill, lastKill = GetServerTime() of those kills, nil before the first,
--   xp         = kill experience gained, share = the same as a fraction of a level, summed gain
--                by gain against the level's size at that moment,
--   kills      = kill messages counted, parsed = those whose text named a creature,
--                fallback = those whose text was secret,
--   approximate = true once a kill's text was secret (its XP then comes from the XP bar and may
--                include other gains), died = true from the player's death until the next kill,
--   creatures  = { [name] = { kills, xp } }, with UNKNOWN for kills whose text was secret.
-- Only this file knows the layout.

ns.DB = {}

-- The creatures key for kills whose message was secret. Not a name a creature can have.
ns.DB.UNKNOWN = "?"

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
	for version = (db.version or 0) + 1, DB_VERSION do
		migrations[version](db)
		db.version = version
	end
end

function ns.DB.Minimap()
	return ns.db.minimap
end

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
	character.nextID = character.nextID or 1
	character.open = character.open or {}
	character.runs = character.runs or {}
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

-- Starts a run and makes it the dungeon's open run. Returns nil without a character key.
function ns.DB.NewRun(instanceID, name, level, openedBy)
	local character = ns.DB.Character()
	if not character then
		return nil
	end
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

-- The dungeon's next visit starts a new run.
function ns.DB.CloseRun(instanceID)
	local character = ns.DB.Character()
	if character then
		character.open[instanceID] = nil
	end
end

function ns.DB.CloseAllRuns()
	local character = ns.DB.Character()
	if character then
		wipe(character.open)
	end
end

-- The current character's run of this dungeon with that copy number, or nil.
function ns.DB.RunByCopy(instanceID, copy)
	for _, run in ipairs(ns.DB.Runs()) do
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

-- Counts one kill. creatureName nil means the kill message was secret: the kill goes under
-- UNKNOWN and the run becomes approximate. xp and share may be 0 when the XP arrives apart
-- (AddXP). now is GetServerTime().
function ns.DB.AddKill(run, creatureName, xp, share, now)
	local key = creatureName
	if key then
		run.parsed = run.parsed + 1
	else
		key = ns.DB.UNKNOWN
		run.fallback = run.fallback + 1
		run.approximate = true
	end
	local creature = run.creatures[key]
	if not creature then
		creature = { kills = 0, xp = 0 }
		run.creatures[key] = creature
	end
	creature.kills = creature.kills + 1
	creature.xp = creature.xp + xp
	run.kills = run.kills + 1
	run.xp = run.xp + xp
	run.share = run.share + share
	run.firstKill = run.firstKill or now
	run.lastKill = now
	run.died = nil
end

-- Adds experience that arrived apart from its kill message (the message was secret), under
-- UNKNOWN.
function ns.DB.AddXP(run, xp, share)
	local creature = run.creatures[ns.DB.UNKNOWN]
	if not creature then
		creature = { kills = 0, xp = 0 }
		run.creatures[ns.DB.UNKNOWN] = creature
	end
	creature.xp = creature.xp + xp
	run.xp = run.xp + xp
	run.share = run.share + share
end
