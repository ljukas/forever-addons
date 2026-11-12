local _, ns = ...

-- Reads "X dies, you gain N experience" messages. Pure: no events, no client state. The patterns
-- are built from the client's own format strings (COMBATLOG_XPGAIN_*), so any locale works.
-- The caller guarantees no argument is secret.

ns.XPMessage = {}

local MAGIC = "[%^%$%(%)%%%.%[%]%*%+%-%?]"

-- Turns a format string into an anchored Lua pattern plus, per capture, the format argument it
-- holds: { index = argument position, number = true for %d }. Returns nil for a format with a
-- specifier other than %s, %d, their positional forms (%1$s, %2$d) and %%.
--   "%s dies, you gain %d experience."  -> "^(.+) dies, you gain (%d+) experience%.$",
--                                          { { index = 1 }, { index = 2, number = true } }
--   "%2$d Erfahrung durch %1$s."        -> "^(%d+) Erfahrung durch (.+)%.$",
--                                          { { index = 2, number = true }, { index = 1 } }
--   "You gain %.1f experience."         -> nil
function ns.XPMessage.Pattern(format)
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

-- Builds the matchers for a list of format strings. Only a format whose first argument is a
-- string is a creature kill ("%s dies, you gain %d experience. (%s exp %s bonus)"): that
-- argument is the creature and the format's first number is the experience gained. Formats
-- without one ("You gain %d experience.") name no creature and get no matcher. The longest
-- format comes first, so a bonus variant is tried before the plain one.
function ns.XPMessage.Build(formats)
	local matchers = {}
	for _, format in ipairs(formats) do
		local pattern, captures = ns.XPMessage.Pattern(format)
		local creature, xp, xpIndex
		for captureIndex, capture in ipairs(captures or {}) do
			if capture.index == 1 and not capture.number then
				creature = captureIndex
			elseif capture.number and (not xpIndex or capture.index < xpIndex) then
				xp, xpIndex = captureIndex, capture.index
			end
		end
		if creature and xp then
			table.insert(matchers, { pattern = pattern, creature = creature, xp = xp, length = #format })
		end
	end
	table.sort(matchers, function(a, b)
		return a.length > b.length
	end)
	return matchers
end

-- Returns the creature's name and the experience gained, or nil when the text names no creature.
--   "Defias Miner dies, you gain 72 experience."                          -> "Defias Miner", 72
--   "Mr. Smite dies, you gain 150 experience. (+50 exp Rested bonus)"     -> "Mr. Smite", 150
--   "Kam Deepfury-Guard's Pet dies, you gain 9 experience."               -> "Kam Deepfury-Guard's Pet", 9
--   "You gain 650 experience."                                           -> nil
function ns.XPMessage.Parse(matchers, text)
	for _, matcher in ipairs(matchers) do
		local captures = { text:match(matcher.pattern) }
		local xp = tonumber(captures[matcher.xp])
		if captures[matcher.creature] and xp then
			return captures[matcher.creature], xp
		end
	end
end
