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

local function IsTableOrNil(value)
	return value == nil or type(value) == "table"
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
	-- A database from a newer version may have another layout. What is missing is created;
	-- what is there in another shape is left alone, and the list isn't saved this session.
	local characters = ns.db.characters
	local character = type(characters) == "table" and characters[guid] or nil
	if
		not IsTableOrNil(characters)
		or not IsTableOrNil(character)
		or (character and not IsTableOrNil(character.ignored))
	then
		ns.dev:LogOnce("foreign-layout", "DB", "saved layout not recognised, ignores are not saved")
		return unsaved
	end
	ns.db.characters = characters or {}
	character = character or {}
	ns.db.characters[guid] = character
	character.ignored = character.ignored or {}
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
