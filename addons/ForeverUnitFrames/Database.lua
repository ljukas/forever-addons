local ADDON_NAME, ns = ...

-- ForeverUnitFramesDB layout (account-wide):
--   version  = schema version, see migrations below
--   powerBar = { [Edit Mode layout name] = { point = string, x = number, y = number,
--                                            width = number, height = number } },
--              owned by EditMode.lua. A layout with no entry, or a missing field, uses
--              ns.PowerBar.DEFAULTS.

ns.DB = {}

local DB_VERSION = 1

local migrations = {
	[1] = function(db)
		db.powerBar = db.powerBar or {}
	end,
}

function ns.DB.Migrate(db)
	-- Data from a newer version of the addon is left alone rather than downgraded.
	for version = (db.version or 0) + 1, DB_VERSION do
		migrations[version](db)
		db.version = version
	end
end
