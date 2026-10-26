local ADDON_NAME, ns = ...

-- ForeverMapDB layout (account-wide):
--   version  = schema version, see migrations below
--   settings = { showNodeIcons = boolean, nodeIconSize = number }, owned by Options.lua
-- Missing settings get their defaults when Options.lua registers them.

ns.DB = {}

local DB_VERSION = 1

local migrations = {
	[1] = function(db)
		db.settings = db.settings or {}
	end,
}

function ns.DB.Migrate(db)
	-- Data from a newer version of the addon is left alone rather than downgraded.
	for version = (db.version or 0) + 1, DB_VERSION do
		migrations[version](db)
		db.version = version
	end
end
