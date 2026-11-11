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
-- can't be a table key, so the list then lives for this session only and isn't saved.
local ignored

local function Ignored()
	if ignored then
		return ignored
	end
	local guid = UnitGUID("player")
	if not guid or issecretvalue(guid) or not ns.db then
		ns.log("DB", "no character key, ignore list not saved this session")
		ignored = {}
		return ignored
	end
	-- A database from a newer version may lack the layout this version expects.
	ns.db.characters = ns.db.characters or {}
	local character = ns.db.characters[guid] or {}
	ns.db.characters[guid] = character
	character.ignored = character.ignored or {}
	ignored = character.ignored
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
