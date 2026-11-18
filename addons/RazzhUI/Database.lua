local _, ns = ...

-- RazzhUIDB layout (account-wide). The core's own settings only: a module keeps its data in its
-- own table (ADR 0004).
--   version = schema version, see migrations below
--   minimap = { angle = degrees counter-clockwise from east, nil until the button is first dragged,
--               hide  = true once the player unticks "Show minimap button", else nil },
--             the minimap button's place and whether it is shown, owned by MinimapButton.lua
-- Defaults are not stored: a missing value reads as its default where it is used, and so does one
-- of the wrong type (a hand-edited file). A version above DB_VERSION (a newer RazzhUI wrote the
-- file) is left alone, so readers must cope with a part that is missing or has another shape:
-- ns.DB.Minimap() returns nil then, and nothing is written.

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
	-- A hand-edited version that no migration could have written (negative, fractional) starts over:
	-- every step only fills in what is missing.
	if from < 0 or from % 1 ~= 0 then
		from = 0
	end
	for version = from + 1, DB_VERSION do
		migrations[version](db)
		db.version = version
	end
	-- A file of this version damaged by hand: without the table the button could never be saved.
	if db.version == DB_VERSION and type(db.minimap) ~= "table" then
		db.minimap = {}
	end
end

-- The minimap button's settings, or nil before RazzhUIDB has loaded and when a newer version left
-- something else there.
function ns.DB.Minimap()
	local minimap = ns.db and ns.db.minimap
	return type(minimap) == "table" and minimap or nil
end
