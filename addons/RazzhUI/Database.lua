local _, ns = ...

-- RazzhUIDB layout (account-wide). The core's own settings only: a module keeps its data in its
-- own table (ADR 0004).
--   version = schema version, see migrations below
--   minimap = { angle = degrees counter-clockwise from east, nil until the button is first dragged,
--               hide  = true once the player unticks "Show minimap button", else nil },
--             the minimap button's place and whether it is shown, owned by MinimapButton.lua
-- Defaults are not stored: a missing value reads as its default where it is used, and so does one
-- of the wrong type (a hand-edited file).

ns.DB = {}

local DB_VERSION = 1

local migrations = {
	[1] = function(db)
		if type(db.minimap) ~= "table" then
			db.minimap = {}
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

-- The minimap button's settings, or nil before RazzhUIDB has loaded.
function ns.DB.Minimap()
	return ns.db and ns.db.minimap
end
