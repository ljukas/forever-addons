local ADDON_NAME, ns = ...

-- What the tracker learns about the player's DoTs and HoTs in game, kept so the spell data
-- (Data/Spells.lua) and the matcher's tolerances can be corrected from evidence. Two layers:
--   * a trace line per decision through ns.log (ForeverDev's devlog, scripts/devlog.sh): SEEN,
--     TRACK, TICK, MISS, AVOID, END, UNLISTED, NOTREAD. It scrolls, ForeverDev keeps 500 lines.
--   * aggregates kept across sessions in ForeverDevDB.observed.ForeverCombat.spells
--     (scripts/combat-knowledge.sh), small enough to keep until /fdev forget ForeverCombat:
--     spells[spellName][spellID] = {
--       rank, kind, description, parsed  the latest cast's, parsed = "438 over 18s: 6 x 73"
--       casts, lastSeen                  lastSeen is a time() stamp
--       ticks = { count, crits, absorbed, min, max, sum }
--       intervals, firstTick             histograms { ["3.0"] = count }: seconds between ticks,
--                                        and from the cast to the first tick
--       ticksPerEffect                   histogram { ["5/6"] = count }: ticks seen of expected,
--                                        for effects that ran out (not refreshed or dropped)
--       powerRatio = { min, max }        tick / the description's tick: what power adds
--       misses = { [reason] = count }, missSamples = { last few as text }
--       avoided = { [event] = count }
--       unlisted = true                  for casts that read like a DoT or HoT but aren't on
--                                        the list: candidates to add
--     }

-- Players without ForeverDev record nothing.
if not ns.dev.enabled then
	ns.Knowledge = ns.Inert()
	return
end
ns.Knowledge = {}

local MAX_SAMPLES = 8

local STATS = {
	casts = 0,
	ticks = { count = 0, crits = 0, absorbed = 0, sum = 0 },
	intervals = {},
	firstTick = {},
	ticksPerEffect = {},
	misses = {},
	missSamples = {},
	avoided = {},
}

local function Stats(name, spellID)
	return ns.dev:Observed(STATS, "spells", name, spellID)
end

-- Counts a cast and keeps its description. Returns the spell's stats.
local function RecordCast(name, spellID, description)
	local stats = Stats(name, spellID)
	stats.casts = stats.casts + 1
	stats.lastSeen = time()
	stats.description = description
	return stats
end

local function OneDecimal(value)
	return string.format("%.1f", value)
end

-- A cast of a listed spell that was read and is now tracked.
function ns.Knowledge.Cast(effect, description)
	local stats = RecordCast(effect.name, effect.spellID, description)
	stats.kind = effect.kind
	stats.rank = C_Spell.GetSpellSubtext(effect.spellID)
	stats.parsed = string.format("%d over %ss: %d x %d", effect.total, effect.duration, effect.tickCount, effect.tick)

	-- Once per rank and session.
	ns.dev:LogOnce(
		"spell " .. effect.spellID,
		"SEEN",
		effect.name,
		"id",
		effect.spellID,
		"rank",
		stats.rank,
		"desc",
		description
	)
	local extra = (effect.points and (" points " .. effect.points) or "")
		.. (effect.stacks > 1 and (" stacks " .. effect.stacks) or "")
	ns.log(
		"TRACK",
		effect.name,
		"id",
		effect.spellID,
		"on",
		effect.mobKey,
		string.format(
			"total %d over %ss: %d x %s from %s%s",
			effect.total,
			effect.duration,
			effect.tickCount,
			OneDecimal(effect.tick),
			effect.tickSource,
			extra
		)
	)
end

-- A listed spell whose description didn't give an amount: it isn't tracked.
function ns.Knowledge.NotRead(name, spellID, description)
	ForeverDev.Count(RecordCast(name, spellID, description).misses, "notread")
	ns.log("NOTREAD", name, "id", spellID, "desc", description)
end

-- A cast that isn't on the list but reads like a DoT or HoT.
function ns.Knowledge.Unlisted(name, spellID, description)
	RecordCast(name, spellID, description).unlisted = true
	ns.dev:LogOnce("spell " .. spellID, "UNLISTED", name, "id", spellID, "desc", description)
end

-- A matched tick, recorded before the effect moves onto it.
function ns.Knowledge.Tick(effect, index, amount, flags, offset, now)
	local stats = Stats(effect.name, effect.spellID)
	local ticks = stats.ticks
	if amount == 0 then
		ticks.absorbed = ticks.absorbed + 1
	else
		ticks.count = ticks.count + 1
		ticks.sum = ticks.sum + amount
		ForeverDev.Extend(ticks, amount)
		if flags == "CRITICAL" then
			ticks.crits = ticks.crits + 1
		end
		stats.powerRatio = stats.powerRatio or {}
		ForeverDev.Extend(stats.powerRatio, amount / (effect.describedTick * effect.weights[index] * effect.stacks))
	end
	if effect.lastTickTime then
		ForeverDev.Count(stats.intervals, OneDecimal((now - effect.lastTickTime) / (index - effect.lastTickIndex)))
	else
		ForeverDev.Count(stats.firstTick, OneDecimal(now - effect.castTime))
	end
	ns.log(
		"TICK",
		effect.name,
		"on",
		effect.mobKey,
		"tick",
		index .. "/" .. effect.tickCount,
		"amount",
		amount,
		flags,
		"off",
		string.format("%+.2f", offset),
		"expected",
		string.format("%.0f", ns.TickMatcher.Expected(effect, index))
	)
end

-- A hit of the effect's kind and school that didn't fit it (see ns.TickMatcher.Match).
function ns.Knowledge.Miss(miss, amount)
	local stats = Stats(miss.effect.name, miss.effect.spellID)
	ForeverDev.Count(stats.misses, miss.reason)
	ForeverDev.Sample(stats.missSamples, string.format("%s: %d, %s", miss.reason, amount, miss.detail), MAX_SAMPLES)
	ns.log("MISS", miss.effect.name, "on", miss.effect.mobKey, "amount", amount, "why", miss.reason, miss.detail)
end

function ns.Knowledge.Avoid(effect, event)
	ForeverDev.Count(Stats(effect.name, effect.spellID).avoided, event)
	ns.log("AVOID", effect.name, "on", effect.mobKey, "by", event)
end

-- An effect stopped being tracked. why: "expired", "noticks", "refreshed", "avoided",
-- "plate", "target" or "focus".
function ns.Knowledge.End(effect, why)
	if why == "expired" then
		ForeverDev.Count(Stats(effect.name, effect.spellID).ticksPerEffect, effect.ticksSeen .. "/" .. effect.tickCount)
	end
	ns.log("END", effect.name, "on", effect.mobKey, why, "ticks seen", effect.ticksSeen .. "/" .. effect.tickCount)
end
