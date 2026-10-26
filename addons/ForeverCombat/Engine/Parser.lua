local ADDON_NAME, ns = ...

-- Reads amounts and durations out of English spell descriptions. Plain string functions with
-- no game API calls; Data/Spells.lua decides what is tracked, this only supplies the numbers.
-- Wordings it handles, from Forever's spellbook:
--   "causing 555 Nature damage over 15 sec"              Serpent Sting
--   "and then an additional 240 Arcane damage over 12 sec" Moonfire (the direct part is skipped)
--   "Heals a friendly target for 965 to 1077 and another 994 over 21 sec"  Regrowth
--   "Transfers 41 health ... every 3 sec. Lasts 30 sec."   Siphon Life (per tick)
--   "1 point : 243 damage over 12 sec. 2 points: 396 ..."  Rip, Rupture (finishers)
--   "Awards 1 combo points."                               builders
ns.Parser = {}

local function Normalize(text)
	text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	-- Thousands separators ("1,800"), but not a comma after a number in a sentence.
	text = text:gsub("(%d),(%d%d%d)", "%1%2")
	return (text:gsub("%s+", " "))
end

-- Returns total, duration[, interval] for the over-time part of a description, or nil.
-- The amount is the last number before "over N sec" with no other number in between, which
-- skips direct damage ("425 to 541 Fire damage and an additional 60 Fire damage over 8 sec").
function ns.Parser.ReadOverTime(text)
	text = Normalize(text)
	local total, duration = text:match("(%d+)[^%d]-over (%d+%.?%d*) sec")
	if total then
		return tonumber(total), tonumber(duration)
	end
	local perTick, interval, lasts = text:match("(%d+)[^%d]-every (%d+%.?%d*) sec.-[Ll]asts (%d+%.?%d*) sec")
	if perTick then
		interval, lasts = tonumber(interval), tonumber(lasts)
		return tonumber(perTick) * math.floor(lasts / interval + 0.5), lasts, interval
	end
end

-- Returns { [points] = { total = n, duration = n } } for a finisher's per-combo-point table,
-- or nil when the description has none.
function ns.Parser.ReadComboTable(text)
	local byPoints
	for points, total, duration in Normalize(text):gmatch("(%d) points? ?: ?(%d+)[^%d]-over (%d+%.?%d*) sec") do
		byPoints = byPoints or {}
		byPoints[tonumber(points)] = { total = tonumber(total), duration = tonumber(duration) }
	end
	return byPoints
end

-- Returns how many combo points the spell awards, or nil.
function ns.Parser.ReadComboAward(text)
	local points = Normalize(text):match("[Aa]wards (%d+) combo point")
	return points and tonumber(points)
end

function ns.Parser.IsFinisher(text)
	return text:find("Finishing move", 1, true) ~= nil
end
