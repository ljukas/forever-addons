local _, ns = ...

-- Reads "X dies, you gain N experience" messages. Pure: no events, no client state. The patterns
-- are built from the client's own format strings (COMBATLOG_XPGAIN_*) rather than English text.
-- A format with a grammar escape ("|4singular:plural;", as some locales have) gets no pattern,
-- since the rendered text differs from it; its messages then read as unparsed.
-- The caller guarantees no argument is secret.

ns.XPMessage = {}

local MAGIC = "[%^%$%(%)%%%.%[%]%*%+%-%?]"

-- Turns a format string into an anchored Lua pattern plus, per capture, the format argument it
-- holds: { index = argument position, number = true for %d }. Returns nil for a format with a
-- specifier other than %s, %d, their positional forms (%1$s, %2$d) and %%, or with a "|" escape.
--   "%s dies, you gain %d experience."  -> "^(.+) dies, you gain (%d+) experience%.$",
--                                          { { index = 1 }, { index = 2, number = true } }
--   "%2$d Erfahrung durch %1$s."        -> "^(%d+) Erfahrung durch (.+)%.$",
--                                          { { index = 2, number = true }, { index = 1 } }
--   "You gain %.1f experience."         -> nil
function ns.XPMessage.Pattern(format)
	if format:find("|", 1, true) then
		return nil
	end
	local parts = { "^" }
	local captures = {}
	local position = 1
	local nextArgument = 1
	while position <= #format do
		local character = format:sub(position, position)
		if character == "%" then
			local argument, kind, finish = format:match("^%%(%d+)%$([sd])()", position)
			if not argument then
				kind, finish = format:match("^%%([sd%%])()", position)
			end
			if not kind then
				return nil
			end
			if kind == "%" then
				table.insert(parts, "%%")
			else
				local index = tonumber(argument) or nextArgument
				nextArgument = index + 1
				table.insert(captures, { index = index, number = kind == "d" or nil })
				table.insert(parts, kind == "d" and "(%d+)" or "(.+)")
			end
			position = finish
		else
			table.insert(parts, (character:gsub(MAGIC, "%%%0")))
			position = position + 1
		end
	end
	table.insert(parts, "$")
	return table.concat(parts), captures
end

-- Builds the matchers for a list of { name = the global's name, format = its value }. In every
-- one the format's first number is the experience gained. A format whose first argument is a
-- string is a creature kill ("%s dies, you gain %d experience. (%s exp %s bonus)") and that
-- argument is the creature; the others ("You gain %d experience.") are gains that name no
-- creature. The longest format comes first, so a bonus variant is tried before the plain one.
function ns.XPMessage.Build(formats)
	local matchers = {}
	for _, entry in ipairs(formats) do
		local pattern, captures = ns.XPMessage.Pattern(entry.format)
		local creature, xp, xpIndex, rested
		-- The rested formats (COMBATLOG_XPGAIN_EXHAUSTION1 and 2, with their group and raid
		-- forms): "(%s exp %s bonus)", the first %s the rested part as "+50". EXHAUSTION4 and 5
		-- have the same shape for a penalty, so the name decides.
		local isRested = entry.name:find("EXHAUSTION[12]") ~= nil
		for captureIndex, capture in ipairs(captures or {}) do
			if capture.index == 1 and not capture.number then
				creature = captureIndex
			elseif capture.number and (not xpIndex or capture.index < xpIndex) then
				xp, xpIndex = captureIndex, capture.index
			elseif isRested and capture.index == 3 and not capture.number then
				rested = captureIndex
			end
		end
		if xp then
			table.insert(matchers, {
				name = entry.name,
				pattern = pattern,
				creature = creature,
				xp = xp,
				rested = rested,
				length = #entry.format,
			})
		end
	end
	table.sort(matchers, function(a, b)
		if a.length ~= b.length then
			return a.length > b.length
		end
		return a.name < b.name
	end)
	return matchers
end

-- How much of a kill's experience was rested bonus, from the rested pool as it stood when the
-- kill's message arrived and the rest state's factor. Confirmed in game (16 November 2026): the
-- kill text has no rested bracket, its number includes the bonus, and the pool drops by that
-- whole number (a 252 XP kill at factor 2 took the pool from 7246 to 6994). So of the part the
-- pool covered, (factor - 1) / factor was bonus. 0 without a pool or with a factor of 1 or less.
--   252, 7246, 2 -> 126        252, 100, 2 -> 50        252, nil, 2 -> 0
function ns.XPMessage.RestedPart(xp, pool, factor)
	if not pool or pool <= 0 or not factor or factor <= 1 then
		return 0
	end
	return math.floor(math.min(xp, pool) * (factor - 1) / factor)
end

-- Returns the creature's name (nil for a gain that names none), the experience gained, the
-- matching format's name and how much of the experience was the rested bonus (0 without one);
-- nothing when no format matches.
--   "Defias Miner dies, you gain 72 experience."                      -> "Defias Miner", 72, name, 0
--   "Mr. Smite dies, you gain 150 experience. (+50 exp Rested bonus)" -> "Mr. Smite", 150, name, 50
--   "Kam Deepfury-Guard's Pet dies, you gain 9 experience."           -> "Kam Deepfury-Guard's Pet", 9, name, 0
--   "You gain 650 experience."                                       -> nil, 650, name, 0
--   "You are now rested."                                            -> nothing
function ns.XPMessage.Parse(matchers, text)
	for _, matcher in ipairs(matchers) do
		local captures = { text:match(matcher.pattern) }
		local xp = tonumber(captures[matcher.xp])
		if xp and (not matcher.creature or captures[matcher.creature]) then
			local rested = matcher.rested and tonumber((captures[matcher.rested] or ""):match("%d+")) or 0
			-- Never more than the gain itself, whatever the bracket says.
			rested = math.min(rested, xp)
			return matcher.creature and captures[matcher.creature] or nil, xp, matcher.name, rested
		end
	end
end
