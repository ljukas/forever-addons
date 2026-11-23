local _, ns = ...

-- The maths behind the spell scaling line (SpellLine.lua), kept apart from the game so it can be
-- read and checked on its own. Spells and effects are entries of Data/SpellCoefficients.lua.
--
-- What a stat adds to a cast, the way Vanilla-era servers work it out:
--   bonus = talents × coefficient × stat × ticks
-- where talents is how much the tooltip's own (talented) number exceeds the data's base points, and
-- the coefficient is cut for spells learned below level 20.
ns.SpellScaling = {}

local L = ns.L

local PHYSICAL, HOLY = 1, 2 -- school masks
-- Spells learned below this level get a smaller spell power coefficient...
local LOW_LEVEL = 20
-- ...by this much per level below it.
local LOW_LEVEL_PENALTY = 0.0375
-- A description number belongs to an effect when it's within this ratio of the effect's untalented
-- value: talents raise it (Rake's +10%), and rounding moves small numbers.
local MIN_RATIO, MAX_RATIO = 0.8, 1.6
-- What follows a number that is not an amount: "9 sec", "2 min", "40%", "30 yards" (enUS).
local UNITS = { "^%s*%%", "^%s*sec", "^%s*min", "^%s*hour", "^%s*hr", "^%s*yard", "^%s*yd" }

-- The spell power coefficient of effect: the client's, after the low-level cut; 0 for physical spells.
-- A spell level of 0 means the data has no level for the spell, so it gets no cut.
function ns.SpellScaling.Coefficient(spell, effect)
	if spell.school == PHYSICAL then
		return 0
	end
	local coefficient = effect.sp
	if spell.level > 0 and spell.level < LOW_LEVEL then
		coefficient = coefficient * math.max(0, 1 - (LOW_LEVEL - spell.level) * LOW_LEVEL_PENALTY)
	end
	return coefficient
end

-- The attack power coefficient of effect, 0 unless it has been measured (Data/APCoefficients.lua).
-- The client's own `ap` is not used: the server applies attack power scaling the client data lacks,
-- so a client value can't be told from a placeholder.
function ns.SpellScaling.APCoefficient(spellID, effect)
	local measured = ns.APCoefficients and ns.APCoefficients[spellID]
	return measured and measured[effect.index] or 0
end

-- Whether effect scales with bonus healing rather than the school's bonus damage: heals, and Holy
-- absorbs (Power Word: Shield). Other absorbs (Ice Barrier) use spell damage.
function ns.SpellScaling.UsesHealing(spell, effect)
	return effect.kind == "heal" or (effect.kind == "absorb" and spell.school == HOLY)
end

-- How many times a periodic effect ticks over the spell's duration; 1 for everything else.
function ns.SpellScaling.Ticks(spell, effect)
	if not effect.periodic or effect.period <= 0 or spell.duration <= 0 then
		return 1
	end
	return math.max(1, math.floor(spell.duration / effect.period))
end

-- The number an untalented tooltip would show for effect at playerLevel: base points grown per level
-- between the spell's base and max level, times the ticks for a periodic effect. For an effect with
-- variance this is the middle of the range (Wrath rank 1: base 15, variance 0.154, "13 to 16").
function ns.SpellScaling.ExpectedBase(spell, effect, playerLevel)
	local levels = 0
	if spell.maxLevel > 0 then
		levels = math.max(0, math.min(playerLevel, spell.maxLevel) - spell.baseLevel)
	end
	return (effect.base + effect.perLevel * levels) * ns.SpellScaling.Ticks(spell, effect)
end

local function HasUnit(text, position)
	for _, pattern in ipairs(UNITS) do
		if text:find(pattern, position) then
			return true
		end
	end
	return false
end

-- The amounts in a description, in order: { low, high } each, "52 to 58" and "52-58" read as one
-- range. Decimals ("1.5") and numbers with a unit (UNITS) are not amounts and are left out.
local function ReadNumbers(description)
	-- "1,234" is one number.
	local text = description:gsub("(%d),(%d%d%d)", "%1%2")
	local numbers = {}
	local position = 1
	while true do
		local first, last, low = text:find("(%d+)", position)
		if not first then
			break
		end
		local _, decimalLast = text:find("^%d+%.%d+", first)
		if decimalLast then
			position = decimalLast + 1
		else
			local _, rangeLast, high = text:find("^%s+to%s+(%d+)", last + 1)
			if not rangeLast then
				_, rangeLast, high = text:find("^%s*%-%s*(%d+)", last + 1)
			end
			if rangeLast then
				last = rangeLast
			else
				high = low
			end
			if not HasUnit(text, last + 1) then
				table.insert(numbers, { low = tonumber(low), high = tonumber(high) })
			end
			position = last + 1
		end
	end
	return numbers
end

-- For each effect in expected ({ value = its ExpectedBase, range = whether its amount varies }), the
-- description amount that is its talented value: { low, high }, or false when none fits.
--
-- A varying effect takes a range first and a fixed one a single number, then the closest ratio wins,
-- and each amount goes to one effect only. Shape comes first because a talent lifts every number of
-- a spell alike: by ratio alone, a talented Regrowth's heal and its heal over time, which are about
-- the same size, would take each other's numbers.
function ns.SpellScaling.FindTooltipNumbers(description, expected)
	local numbers = ReadNumbers(description)
	local candidates = {}
	for effectIndex, effect in ipairs(expected) do
		for numberIndex, number in ipairs(numbers) do
			local ratio = effect.value > 0 and (number.low + number.high) / 2 / effect.value or 0
			if ratio >= MIN_RATIO and ratio <= MAX_RATIO then
				table.insert(candidates, {
					effect = effectIndex,
					number = numberIndex,
					shape = (number.low ~= number.high) == effect.range,
					score = math.abs(ratio - 1),
				})
			end
		end
	end
	table.sort(candidates, function(a, b)
		if a.shape ~= b.shape then
			return a.shape
		end
		if a.score ~= b.score then
			return a.score < b.score
		end
		if a.number ~= b.number then
			return a.number < b.number
		end
		return a.effect < b.effect
	end)

	local found, used = {}, {}
	for index = 1, #expected do
		found[index] = false
	end
	for _, pair in ipairs(candidates) do
		if not found[pair.effect] and not used[pair.number] then
			found[pair.effect] = numbers[pair.number]
			used[pair.number] = true
		end
	end
	return found
end

-- What stat adds to one cast, rounded down like the game's tooltips.
function ns.SpellScaling.Bonus(coefficient, stat, ticks, talents)
	return math.floor(talents * coefficient * stat * ticks)
end

local KIND = {
	damage = L.SCALING_DAMAGE,
	heal = L.SCALING_HEAL,
	absorb = L.SCALING_ABSORB,
}

-- "+57.1%": a percentage with at most one decimal.
local function FormatPercent(coefficient)
	local text = ("%.1f"):format(coefficient * 100):gsub("%.0$", "")
	return text .. "%"
end

-- The line's text: the coefficient (per tick, with the tick count, for a periodic effect), then what
-- it adds over the whole cast when bonus is given, then the resulting total (a range when totalHigh
-- differs) when total is given. attackPower labels the coefficient AP instead of SP.
function ns.SpellScaling.FormatLine(kind, coefficient, ticks, bonus, total, totalHigh, attackPower)
	local text = (attackPower and L.SCALING_AP or L.SCALING_SP):format(FormatPercent(coefficient))
	if ticks > 1 then
		text = text .. L.SCALING_TICKS:format(ticks)
	end
	if not bonus then
		return text
	end
	text = text .. L.SCALING_BONUS:format(bonus)
	if not total then
		return text
	end
	local amount = tostring(total)
	if totalHigh and totalHigh ~= total then
		amount = L.SCALING_RANGE:format(total, totalHigh)
	end
	return text .. L.SCALING_TOTAL:format(amount, KIND[kind])
end
