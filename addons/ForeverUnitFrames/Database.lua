local ADDON_NAME, ns = ...

-- ForeverUnitFramesDB layout (account-wide):
--   version  = schema version, see migrations below
--   powerBar = { [key] = { point = string, x = number, y = number, width = number, height = number } },
--              owned by EditMode.lua. key is the Edit Mode layout's name; for a character-specific
--              layout it is "<name> @ <player GUID>", since characters can each have a layout of the
--              same name. The preset layouts (Modern, Classic) are shared by every character. A
--              layout with no entry, or a missing or invalid field, uses ns.PowerBar.DEFAULTS.

ns.DB = {}

local DB_VERSION = 1

local migrations = {
	[1] = function(db)
		if type(db.powerBar) ~= "table" then
			db.powerBar = {}
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
