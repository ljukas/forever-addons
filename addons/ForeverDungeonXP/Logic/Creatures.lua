local _, ns = ...

-- A run's creatures as table rows, and their ranks (elite, boss). Pure.
--
-- A kill message names a creature but no unit, and in a dungeon a unit's name is secret, so a
-- creature's rank can't be looked up. Tracker.lua instead reads the rank of the units that died
-- as kill messages arrived and, when they all agree, gives it to the creatures named, as one
-- vote each time (creature.ranks, Database.lua). The rank shown is the one with the most votes.

ns.Creatures = {}

-- A unit's rank from UnitClassification, UnitIsBossMob and UnitLevel (-1 is the skull level):
--   "worldboss", or a boss mob, or level -1 -> "boss"
--   "rare", "rareelite"                     -> "rare"
--   "elite"                                 -> "elite"
--   anything else                           -> "normal"
function ns.Creatures.Classify(classification, isBoss, level)
	if isBoss or classification == "worldboss" or level == -1 then
		return "boss"
	elseif classification == "rare" or classification == "rareelite" then
		return "rare"
	elseif classification == "elite" then
		return "elite"
	end
	return "normal"
end

-- The one rank a list of ranks agrees on, or nil when it is empty or mixed.
--   { "elite", "elite" } -> "elite"      { "elite", "normal" } -> nil      {} -> nil
function ns.Creatures.Agreed(ranks)
	local rank = ranks[1]
	for index = 2, #ranks do
		if ranks[index] ~= rank then
			return nil
		end
	end
	return rank
end

local function Votes(ranks, rank)
	local votes = ranks[rank]
	return type(votes) == "number" and votes or 0
end

-- The rank to show for a creature's votes, nil for a normal or never-seen creature. Any boss
-- vote wins (a boss dies alone or not at all); otherwise the most votes, a tie going to the
-- rank that shows an icon.
--   nil -> nil      { normal = 4 } -> nil      { elite = 3, normal = 1 } -> "elite"
--   { elite = 1, normal = 5 } -> nil           { boss = 1, elite = 2 } -> "boss"
function ns.Creatures.Rank(ranks)
	if type(ranks) ~= "table" then
		return nil
	end
	if Votes(ranks, "boss") > 0 then
		return "boss"
	end
	local best, most = nil, Votes(ranks, "normal")
	for _, rank in ipairs({ "rare", "elite" }) do
		local votes = Votes(ranks, rank)
		if votes > 0 and votes >= most then
			best, most = rank, votes
		end
	end
	return best
end

-- The sort keys of a creature row; "each" is the experience per kill.
local function Value(row, key)
	if key == "each" then
		return row.kills > 0 and row.xp / row.kills or 0
	end
	return row[key]
end

-- A run's creature rows { name, kills, xp, rank }, sorted by key ("name", "kills", "each" or
-- "xp"), ascending or not. Equal rows go by most experience, then by name. The kills whose
-- names were hidden come last whatever the order, named unknownName.
function ns.Creatures.Rows(run, unknownName, key, ascending)
	local rows = {}
	for name, creature in pairs(run.creatures) do
		table.insert(
			rows,
			{ name = name, kills = creature.kills, xp = creature.xp, rank = ns.Creatures.Rank(creature.ranks) }
		)
	end
	table.sort(rows, function(a, b)
		local valueA, valueB = Value(a, key), Value(b, key)
		if valueA ~= valueB then
			if ascending then
				return valueA < valueB
			end
			return valueA > valueB
		end
		if a.xp ~= b.xp then
			return a.xp > b.xp
		end
		return a.name < b.name
	end)
	if run.unknown then
		table.insert(rows, { name = unknownName, kills = run.unknown.kills, xp = run.unknown.xp })
	end
	return rows
end
