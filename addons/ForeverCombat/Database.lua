local ADDON_NAME, ns = ...

-- ForeverCombatDB layout (account-wide):
--   version  = schema version, see migrations below
--   settings = { [key] = boolean }, owned by Options.lua
--   ticks    = { [tickKey] = { amount = number, count = number } }, learned tick sizes, owned by this file
--   observed = { [spellName] = { [spellID] = stats } }, what was seen in game, owned by Engine/Knowledge.lua
-- tickKey is the spell ID, or "spellID:points" for a finisher cast with that many combo points.
-- Ranks have their own spell IDs and tick sizes, so ticks are never shared between ranks.

ns.DB = {}

local DB_VERSION = 1

-- Learned tick sizes follow the player's spell and attack power as gear and buffs change:
-- each new tick moves the average by 1/LEARN_WINDOW of the difference once it's warmed up.
local LEARN_WINDOW = 8

local migrations = {
	[1] = function(db)
		db.settings = db.settings or {}
		db.ticks = db.ticks or {}
		db.observed = db.observed or {}
	end,
}

function ns.DB.Migrate(db)
	-- Data from a newer version of the addon is left alone rather than downgraded.
	for version = (db.version or 0) + 1, DB_VERSION do
		migrations[version](db)
		db.version = version
	end
end

function ns.DB.TickKey(spellID, points)
	return points and (spellID .. ":" .. points) or spellID
end

-- Returns the learned tick size, or nil if none has been seen yet.
function ns.DB.GetTick(tickKey)
	local learned = ns.db.ticks[tickKey]
	return learned and learned.amount
end

-- Records an observed (non-critical) tick and returns the new learned size.
function ns.DB.LearnTick(tickKey, amount)
	local learned = ns.db.ticks[tickKey]
	if not learned then
		learned = { amount = amount, count = 1 }
		ns.db.ticks[tickKey] = learned
	else
		learned.count = learned.count + 1
		learned.amount = learned.amount + (amount - learned.amount) / math.min(learned.count, LEARN_WINDOW)
	end
	return learned.amount
end
