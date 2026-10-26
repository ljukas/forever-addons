local ADDON_NAME, ns = ...

-- Decides which tracked effect a UNIT_COMBAT hit on a mob is a tick of. UNIT_COMBAT doesn't
-- name the spell or the caster, so a hit is a tick when its school, timing and size fit one
-- of the player's effects on that mob. Hits from other players and melee that fit by chance
-- are the cost of that. No game API calls; Engine/Tracker.lua feeds it.
ns.TickMatcher = {}

-- How far a tick may land from where the effect's rhythm puts it, in seconds.
local WINDOW = 0.4
-- The first tick comes one interval after the cast lands. Projectiles (Fireball, Serpent
-- Sting) land later than the cast succeeds, so it may come this much later still.
local FIRST_TICK_EARLY, FIRST_TICK_LATE = 0.4, 1.5
-- A tick's size relative to the expected one; partial resists make it smaller. Descriptions
-- leave out spell and attack power, so until a tick size is learned the real ones can be
-- several times larger (Rip and Garrote scale strongly with attack power).
local MIN_RATIO, MAX_RATIO = 0.45, 2.5
local MAX_RATIO_UNLEARNED = 6

-- The tick index the hit would be, how far off the rhythm it lands (seconds) and whether
-- that's close enough.
local function Place(effect, now)
	if effect.ticksSeen == 0 then
		local offset = now - effect.start - effect.interval
		return 1, offset, offset >= -FIRST_TICK_EARLY and offset <= FIRST_TICK_LATE
	end
	local steps = math.floor((now - effect.lastTickTime) / effect.interval + 0.5)
	local offset = now - effect.lastTickTime - steps * effect.interval
	return effect.lastTickIndex + steps, offset, math.abs(offset) <= WINDOW
end

-- Expected size of tick index on the effect.
function ns.TickMatcher.Expected(effect, index)
	return effect.tick * (effect.weights[index] or 1) * effect.stacks
end

-- Why a hit placed at tick index can't be that tick of the effect, or nil if it can.
local function Reject(effect, index, onTime, amount)
	if not onTime then
		return "timing"
	elseif index > effect.tickCount then
		return "ended"
	elseif index <= effect.lastTickIndex then
		return "seen"
	end
	-- amount 0 is a tick fully absorbed by a shield: it keeps the rhythm but says nothing
	-- about size.
	if amount > 0 then
		local ratio = amount / ns.TickMatcher.Expected(effect, index)
		local maxRatio = effect.tickSource == "learned" and MAX_RATIO or MAX_RATIO_UNLEARNED
		if ratio < MIN_RATIO or ratio > maxRatio then
			return "size"
		end
	end
end

-- effects: the player's effects on the mob ({ [name] = effect }). Only those of the hit's
-- kind and school are candidates; school 0 (unknown) fits any.
-- Returns { effect, index, offset } when the hit is a tick. Otherwise nil, plus
-- { effect, reason, detail } for the candidate that came nearest, or nil when there was none:
-- reason is "timing", "ended", "seen" or "size", detail describes the miss for the log.
function ns.TickMatcher.Match(effects, kind, amount, school, now)
	local match, miss
	for _, effect in pairs(effects) do
		if effect.kind == kind and (school == 0 or bit.band(effect.school, school) ~= 0) then
			local index, offset, onTime = Place(effect, now)
			local reason = Reject(effect, index, onTime, amount)
			if not reason then
				if not match or math.abs(offset) < math.abs(match.offset) then
					match = { effect = effect, index = index, offset = offset }
				end
			elseif not miss or reason == "size" then
				miss = {
					effect = effect,
					reason = reason,
					detail = string.format(
						"tick %d off %+.2fs expected %d",
						index,
						offset,
						ns.TickMatcher.Expected(effect, index)
					),
				}
			end
		end
	end
	if match then
		return match
	end
	return nil, miss
end
