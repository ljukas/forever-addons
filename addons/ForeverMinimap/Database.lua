local ADDON_NAME, ns = ...

-- ForeverMinimapDB layout (account-wide):
--   version   = schema version, see migrations below
--   settings  = { showNodeIcons = boolean, showButtonBag = boolean,
--                 buttonBagDirection = number (ns.Options.DIRECTION),
--                 buttonBagScale = number (gathered buttons' size, 1 = 31 px, a standard minimap button) },
--                 owned by Options.lua.
--                 (A nodeIconSize key from development builds before the first release is ignored.)
--   buttonBag = { angle = number|nil, ignored = { [key] = true } }
--     angle   = where the bag button sits on the minimap edge, in degrees counter-clockwise from east
--               (0 = east, 90 = north, LibDBIcon's minimapPos convention); nil means the default
--               spot. Owned by UI/BagButton.lua
--     ignored = keys of the addon buttons the player keeps out of the bag. Owned by ButtonBag.lua
-- Missing settings get their defaults when Options.lua registers them.

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
