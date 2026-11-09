local ADDON_NAME, ns = ...

-- The skill-up odds of a recipe at the player's current skill, from the craft history
-- (ns.DB.GetCraftRows) and the recipe's live colour. Pure functions, no frames or events
-- (docs/superpowers/specs/2026-11-09-skillup-odds-design.md, "The numbers"). Chances are
-- fractions from 0 to 1. rows is a list of { rank, attempts, skillUps, difficulty }.

ns.Odds = {}

-- Our estimate pools rows this many ranks either side of the current skill.
ns.Odds.WINDOW = 5
-- The recipe list shows our estimate once it rests on this many crafts, else the wiki's.
ns.Odds.LIST_MIN_CRAFTS = 5

local Difficulty = Enum.TradeskillRelativeDifficulty

local function Clamp(value)
	return math.max(0, math.min(1, value))
end

-- Returns the range lo, hi the recipe's yellow level lies in, or nil when it can't be told.
-- It is the lowest rank seen yellow, above the highest rank seen orange below it; the live
-- skill and colour count as one more sample. Orange seen above yellow is junk and ignored.
function ns.Odds.LearnYellow(rows, skill, difficulty)
	local firstYellow = difficulty == Difficulty.Medium and skill or nil
	for _, row in ipairs(rows) do
		if row.difficulty == Difficulty.Medium and (not firstYellow or row.rank < firstYellow) then
			firstYellow = row.rank
		end
	end
	if not firstYellow then
		return nil
	end
	local lastOrange = difficulty == Difficulty.Optimal and skill < firstYellow and skill or nil
	for _, row in ipairs(rows) do
		if
			row.difficulty == Difficulty.Optimal
			and row.rank < firstYellow
			and (not lastOrange or row.rank > lastOrange)
		then
			lastOrange = row.rank
		end
	end
	if not lastOrange then
		return nil
	end
	return lastOrange + 1, firstYellow
end

-- Returns the wiki's chance low, high at skill for a recipe of that colour, gray level and
-- yellow range (low == high when the yellow level is exact), or nil when it's unknown:
-- (gray - skill) / (gray - yellow), always while orange, never once gray.
function ns.Odds.Wiki(skill, difficulty, gray, lo, hi)
	if difficulty == Difficulty.Optimal then
		return 1, 1
	elseif difficulty == Difficulty.Trivial then
		return 0, 0
	elseif not lo or gray <= hi then
		return nil
	end
	return Clamp((gray - skill) / (gray - lo)), Clamp((gray - skill) / (gray - hi))
end

-- Returns our estimate p and the attempts n it rests on, from the rows within WINDOW ranks of
-- skill with the recipe's current colour, or nil when there are none. A craft can give more
-- than one point, so p is capped at 1.
function ns.Odds.Ours(rows, skill, difficulty)
	local attempts, skillUps = 0, 0
	for _, row in ipairs(rows) do
		if row.difficulty == difficulty and math.abs(row.rank - skill) <= ns.Odds.WINDOW then
			attempts = attempts + row.attempts
			skillUps = skillUps + row.skillUps
		end
	end
	if attempts == 0 then
		return nil
	end
	return math.min(1, skillUps / attempts), attempts
end
