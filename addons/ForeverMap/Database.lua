local ADDON_NAME, ns = ...

-- ForeverMapDB layout (account-wide):
--   version  = schema version, see migrations below
--   settings = { showNodeIcons = boolean, nodeIconSize = number }, owned by Options.lua
-- Missing settings get their defaults when Options.lua registers them.
--   buttonBag = { angle = number|nil, ignored = { [key] = true } }, the minimap button bag.
--     angle is where the bag button sits on the minimap edge, in radians; nil means the default spot.
--     ignored holds the keys of addon buttons the player keeps out of the bag.

ns.DB = {}

local DB_VERSION = 2

local migrations = {
	[1] = function(db)
		db.settings = db.settings or {}
	end,
	[2] = function(db)
		db.buttonBag = db.buttonBag or {}
		db.buttonBag.ignored = db.buttonBag.ignored or {}
	end,
}

function ns.DB.Migrate(db)
	-- Data from a newer version of the addon is left alone rather than downgraded.
	for version = (db.version or 0) + 1, DB_VERSION do
		migrations[version](db)
		db.version = version
	end
end
