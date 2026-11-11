local ADDON_NAME, ns = ...

-- ForeverBagsDB layout (account-wide):
--   version    = schema version, see migrations below
--   characters = { [playerGUID] = { ignored = { [itemID] = true } } }
--                One entry per character: the ignore list is per character.

ns.DB = {}

local DB_VERSION = 1

local migrations = {
	[1] = function(db)
		db.characters = db.characters or {}
	end,
}

function ns.DB.Migrate(db)
	-- Data from a newer version of the addon is left alone rather than downgraded.
	for version = (db.version or 0) + 1, DB_VERSION do
		migrations[version](db)
		db.version = version
	end
end

-- The current character's ignore list, found on first use (the GUID isn't known before
-- PLAYER_LOGIN). UnitGUID can return a secret value where unit identity is restricted; a secret
-- can't be a table key, so until the GUID is readable the saved list isn't consulted.
local ignored

-- Ignores made while the character's list couldn't be found. They move into the saved list
-- the first time it can.
local unsaved = {}

local function TableOrNew(value)
	return type(value) == "table" and value or {}
end

local function Ignored()
	if ignored then
		return ignored
	end
	local guid = UnitGUID("player")
	if not guid or issecretvalue(guid) or not ns.db then
		ns.dev:LogOnce("no-character-key", "DB", "no character key yet, ignores are held until there is one")
		return unsaved
	end
	-- A database from a newer version may lack the layout this version expects.
	ns.db.characters = TableOrNew(ns.db.characters)
	local character = TableOrNew(ns.db.characters[guid])
	ns.db.characters[guid] = character
	character.ignored = TableOrNew(character.ignored)
	ignored = character.ignored
	for itemID in pairs(unsaved) do
		ignored[itemID] = true
	end
	wipe(unsaved)
	return ignored
end

function ns.DB.IsIgnored(itemID)
	return Ignored()[itemID] == true
end

function ns.DB.Ignore(itemID)
	Ignored()[itemID] = true
end

function ns.DB.ResetIgnored()
	wipe(Ignored())
end
