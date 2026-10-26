local ADDON_NAME, ns = ...

-- Tracks the player's DoTs and HoTs per mob. Auras on other units are secret in combat, and
-- the combat log is closed to addons, so effects are followed from the player's own casts:
--   UNIT_SPELLCAST_SENT       which unit the cast goes on (it names the cast's target)
--   UNIT_SPELLCAST_SUCCEEDED  a listed spell starts or refreshes an effect; its description
--                             gives the amount and duration
--   UNIT_COMBAT               a dodge, miss or resist right after a DoT's cast drops it again;
--                             later hits that fit its rhythm are its ticks, and teach the real
--                             tick size (descriptions leave out spell and attack power)
-- Remaining amounts are the ticks still due times the tick size. All numbers here are plain;
-- the display compares them with the (secret) health only inside StatusBar widgets.
--
-- An effect: { name, spellID, kind, school, mobKey, total, duration, interval, tickCount,
--   weights, stacks, points, tick, describedTick, tickKey, tickSource, castTime, start,
--   ticksSeen, lastTickIndex, lastTickTime }. start is when tick 0 would have landed; it moves
--   onto the observed rhythm with every matched tick.
ns.Tracker = {}

-- An avoid on the cast's mob this soon after the cast is taken as the cast's.
local AVOID_WINDOW = 0.6
-- A tick that hasn't been seen this long after it was due is assumed to have landed unseen
-- (UNIT_COMBAT only covers units with a token: target, focus, nameplates, the group).
local TICK_LATE = 0.5
local FIRST_TICK_LATE = 1.5
-- Ticks that may go missing while the mob is visibly being hit before the effect is dropped
-- as never applied (immune, or an avoid that wasn't caught).
local MISSED_TICKS = 2
local PRUNE_INTERVAL = 0.5
-- A sent cast that hasn't succeeded, failed or been interrupted by then never will.
local PENDING_LIFETIME = 10
local PHYSICAL = ns.Spells.PHYSICAL

-- UNIT_COMBAT events that mean a cast didn't land, by whether the cast is physical. Spell
-- casts ignore dodges and parries: those are the pet's or the player's melee. Heals can't be
-- avoided, so HoT casts are never checked.
local AVOIDS = {
	physical = { MISS = true, DODGE = true, PARRY = true, EVADE = true, IMMUNE = true, DEFLECT = true },
	spell = { MISS = true, RESIST = true, EVADE = true, IMMUNE = true, REFLECT = true },
}

-- The UNIT_COMBAT event each kind of effect ticks as.
local TICK_KINDS = { WOUND = "dot", HEAL = "hot" }

local playerClass
local effects = {} -- [mobKey] = { [spellName] = effect }
local pending = {} -- [castGUID] = { key, time }
local lastCasts = {} -- [mobKey] = { time, kind, school, effect, previous, awards, points, settled }
local heard = {} -- [mobKey] = GetTime() of the last UNIT_COMBAT on that mob
local spellFacts = {} -- [spellID] = { name, entry, awards, finisher, overTime }
local pruneTicker

local function Changed(key)
	ns.callbacks:TriggerEvent("EffectsChanged", key)
end

-- Name, list entry and what the description says about a spell ID. Cached for the session;
-- the amounts are read again on every cast.
local function SpellFacts(spellID)
	local facts = spellFacts[spellID]
	if not facts then
		local name = C_Spell.GetSpellName(spellID) or ""
		local description = C_Spell.GetSpellDescription(spellID) or ""
		facts = {
			name = name,
			entry = ns.Spells.Lookup(name, playerClass),
			awards = ns.Parser.ReadComboAward(description),
			finisher = ns.Parser.IsFinisher(description),
			overTime = ns.Parser.ReadOverTime(description) ~= nil,
		}
		spellFacts[spellID] = facts
	end
	return facts
end

local function EndTime(effect)
	return effect.start + effect.tickCount * effect.interval
end

-- Ticks that have landed or are overdue.
local function TicksDone(effect, now)
	local late = effect.ticksSeen == 0 and FIRST_TICK_LATE or TICK_LATE
	local due = math.floor((now - effect.start - late) / effect.interval)
	return math.max(effect.lastTickIndex, math.min(due, effect.tickCount))
end

-- Returns the amount still to come and the seconds until the last tick.
function ns.Tracker.Remaining(effect, now)
	local amount = 0
	for index = TicksDone(effect, now) + 1, effect.tickCount do
		amount = amount + ns.TickMatcher.Expected(effect, index)
	end
	return amount, math.max(0, EndTime(effect) - now)
end

local function ByEnd(a, b)
	return EndTime(a) < EndTime(b)
end

-- The player's effects of a kind on a mob that still have ticks to come, ending soonest
-- first. Returns nil when there are none.
function ns.Tracker.GetEffects(key, kind)
	local mob = effects[key]
	if not mob then
		return nil
	end
	local now = GetTime()
	local list
	for _, effect in pairs(mob) do
		if effect.kind == kind and TicksDone(effect, now) < effect.tickCount then
			list = list or {}
			table.insert(list, effect)
		end
	end
	if list then
		table.sort(list, ByEnd)
	end
	return list
end

local function Prune()
	local now = GetTime()
	for key, mob in pairs(effects) do
		for name, effect in pairs(mob) do
			local why
			if TicksDone(effect, now) >= effect.tickCount then
				why = "expired"
			elseif
				effect.ticksSeen == 0
				and (heard[key] or 0) > effect.start + effect.interval
				and now > effect.start + effect.interval * MISSED_TICKS + FIRST_TICK_LATE
			then
				why = "noticks"
			end
			if why then
				mob[name] = nil
				ns.Knowledge.End(effect, why)
				Changed(key)
			end
		end
		if not next(mob) then
			effects[key] = nil
			heard[key] = nil
		end
	end
	for key, cast in pairs(lastCasts) do
		if now - cast.time > AVOID_WINDOW then
			lastCasts[key] = nil
		end
	end
	for castGUID, cast in pairs(pending) do
		if now - cast.time > PENDING_LIFETIME then
			pending[castGUID] = nil
		end
	end
	if not next(effects) and not next(lastCasts) and not next(pending) then
		pruneTicker:Cancel()
		pruneTicker = nil
	end
end

local function KeepPruning()
	if not pruneTicker then
		pruneTicker = C_Timer.NewTicker(PRUNE_INTERVAL, Prune)
	end
end

local function Drop(key, why)
	local mob = effects[key]
	if not mob then
		return
	end
	effects[key] = nil
	heard[key] = nil
	lastCasts[key] = nil
	for _, effect in pairs(mob) do
		ns.Knowledge.End(effect, why)
	end
	Changed(key)
end

-- Builds the effect a cast starts, or returns nil when the description has no amount.
local function NewEffect(facts, spellID, description, key, points, previous, now)
	local entry = facts.entry
	local total, duration, interval
	if entry.finisher then
		local byPoints = ns.Parser.ReadComboTable(description)
		local row = byPoints and (byPoints[points] or byPoints[1])
		if row then
			total, duration = row.total, row.duration
		end
	else
		total, duration, interval = ns.Parser.ReadOverTime(description)
	end
	if not total or total <= 0 then
		return nil
	end

	interval = interval or entry.interval
	local tickCount = math.max(1, math.floor(duration / interval + 0.5))
	local weights = {}
	for index = 1, tickCount do
		weights[index] = ns.Spells.TickWeight(entry, index, tickCount)
	end
	local stacks = 1
	if entry.stacks and previous then
		stacks = math.min(entry.stacks, previous.stacks + 1)
	end

	local finisherPoints = entry.finisher and points or nil
	local describedTick = total / tickCount
	local tickKey = ns.DB.TickKey(spellID, finisherPoints)
	local learned = ns.DB.GetTick(tickKey)
	return {
		name = facts.name,
		spellID = spellID,
		kind = entry.kind,
		school = entry.school,
		mobKey = key,
		total = total,
		duration = duration,
		interval = interval,
		tickCount = tickCount,
		weights = weights,
		stacks = stacks,
		points = finisherPoints,
		describedTick = describedTick,
		tick = learned or describedTick,
		tickKey = tickKey,
		tickSource = learned and "learned" or "description",
		castTime = now,
		start = now,
		ticksSeen = 0,
		lastTickIndex = 0,
	}
end

-- Counts combo points: a finisher spends them (returned), a builder adds its award.
local function SpendCombo(key, facts)
	local points
	if facts.finisher then
		points = ns.Combo.Get(key)
		ns.Combo.Reset()
		ns.log("COMBO", facts.name, "spends", points)
	end
	if facts.awards then
		ns.log("COMBO", facts.name, "adds", facts.awards, "now", ns.Combo.Add(key, facts.awards))
	end
	return points
end

-- Starts or refreshes the effect a listed spell's cast puts on the mob. Returns the new
-- effect and the one it replaced; nil, nil when the description gave no amount.
local function StartEffect(key, facts, spellID, description, points, now)
	local previous = effects[key] and effects[key][facts.name]
	if previous and TicksDone(previous, now) >= previous.tickCount then
		previous = nil
	end
	if facts.entry.finisher and points == 0 then
		ns.log("COMBO", facts.name, "points unknown, using the 1 point row")
	end
	local effect = NewEffect(facts, spellID, description, key, points, previous, now)
	if not effect then
		ns.Knowledge.NotRead(facts.name, spellID, description)
		return nil, nil
	end
	effects[key] = effects[key] or {}
	effects[key][facts.name] = effect
	if previous then
		ns.Knowledge.End(previous, "refreshed")
	end
	ns.Knowledge.Cast(effect, description)
	Changed(key)
	return effect, previous
end

-- The avoid a UNIT_COMBAT event reports against a cast of that school, or nil.
local function AvoidEvent(castSchool, event, flags, amount, school)
	local avoid = event
	if event == "WOUND" and amount == 0 then
		-- A fully resisted or missed hit; a fully absorbed or blocked one still landed.
		if flags == "ABSORB" or flags == "BLOCK" then
			return nil
		end
		avoid = flags == "RESIST" and "RESIST" or "MISS"
	end
	local avoids = castSchool == PHYSICAL and AVOIDS.physical or AVOIDS.spell
	if avoids[avoid] and (school == 0 or bit.band(castSchool, school) ~= 0) then
		return avoid
	end
end

-- If the event says the last DoT cast or builder on the mob didn't land, takes it back:
-- the effect it replaced returns, and the combo points it added or spent are undone.
-- Returns true when it did.
local function TryAvoid(key, event, flags, amount, school, now)
	local cast = lastCasts[key]
	if not cast or cast.settled or cast.kind == "hot" or now - cast.time > AVOID_WINDOW then
		return false
	end
	local avoid = AvoidEvent(cast.school, event, flags, amount, school)
	if not avoid then
		return false
	end

	cast.settled = true
	if cast.awards then
		ns.log("COMBO", "taken back", cast.awards, "now", ns.Combo.Take(key, cast.awards))
	end
	if cast.points then
		ns.log("COMBO", "finisher avoided, back to", ns.Combo.Add(key, cast.points))
	end
	local effect = cast.effect
	if effect and effects[key] and effects[key][effect.name] == effect then
		ns.Knowledge.Avoid(effect, avoid)
		ns.Knowledge.End(effect, "avoided")
		effects[key][effect.name] = cast.previous
		Changed(key)
	end
	return true
end

-- Matches a hit to one of the player's effects on the mob and moves that effect onto it,
-- learning the tick size.
local function TryTick(key, mob, event, flags, amount, school, now)
	local kind = TICK_KINDS[event]
	-- A WOUND of 0 is a miss, unless a shield absorbed the whole tick.
	if not kind or (amount == 0 and flags ~= "ABSORB") then
		return
	end
	if school == 0 then
		ns.dev:LogOnce("school0 " .. event, "SCHOOL0", event, "reports school 0; ticks match on timing and size only")
	end

	local match, miss = ns.TickMatcher.Match(mob, kind, amount, school, now)
	if not match then
		if miss then
			ns.Knowledge.Miss(miss, amount)
		end
		return
	end

	local effect, index = match.effect, match.index
	ns.Knowledge.Tick(effect, index, amount, flags, match.offset, now)
	effect.ticksSeen = effect.ticksSeen + 1
	effect.lastTickIndex = index
	effect.lastTickTime = now
	effect.start = now - index * effect.interval
	if amount > 0 and flags ~= "CRITICAL" then
		effect.tick = ns.DB.LearnTick(effect.tickKey, amount / (effect.weights[index] * effect.stacks))
		effect.tickSource = "learned"
	end
	Changed(key)
end

-- The same hit arrives once per unit token that shows the mob (target, focus, its
-- nameplate). Two effects ticking the same amount at once arrive twice from each token, so
-- a hit is new only while its token has sent it more often than any other token has.
local dedupeTime
local dedupe = {}

local function IsDuplicate(key, unit, event, amount, school, now)
	if now ~= dedupeTime then
		dedupeTime = now
		wipe(dedupe)
	end
	local signature = key .. "|" .. event .. "|" .. amount .. "|" .. school
	local byUnit = dedupe[signature]
	if not byUnit then
		byUnit = {}
		dedupe[signature] = byUnit
	end
	local count = (byUnit[unit] or 0) + 1
	byUnit[unit] = count
	for other, otherCount in pairs(byUnit) do
		if other ~= unit and otherCount >= count then
			return true
		end
	end
	return false
end

local handlers = {}

function handlers.UNIT_SPELLCAST_SENT(_, targetName, castGUID, spellID)
	if issecretvalue(castGUID) or issecretvalue(spellID) then
		return
	end
	local facts = SpellFacts(spellID)
	if not facts.entry and not facts.awards and not facts.finisher then
		return
	end
	local unit = ns.Units.CastUnit(targetName, facts.entry and facts.entry.kind or "dot")
	local key, via
	if unit then
		key, via = ns.Units.Key(unit)
	end
	ns.log("SENT", facts.name, "id", spellID, "at", targetName, "unit", unit, "key", key, "via", via)
	if key then
		pending[castGUID] = { key = key, time = GetTime() }
		KeepPruning()
	end
end

function handlers.UNIT_SPELLCAST_SUCCEEDED(_, castGUID, spellID)
	if issecretvalue(castGUID) or issecretvalue(spellID) then
		return
	end
	local facts = SpellFacts(spellID)
	local description = (facts.entry or facts.overTime) and C_Spell.GetSpellDescription(spellID) or ""
	if not facts.entry and facts.overTime then
		ns.Knowledge.Unlisted(facts.name, spellID, description)
	end
	local cast = pending[castGUID]
	pending[castGUID] = nil
	if not cast then
		return
	end

	local now = GetTime()
	local key = cast.key
	local points = SpendCombo(key, facts)
	local effect, previous
	if facts.entry then
		effect, previous = StartEffect(key, facts, spellID, description, points, now)
	end
	lastCasts[key] = {
		time = now,
		kind = facts.entry and facts.entry.kind or "dot",
		school = facts.entry and facts.entry.school or PHYSICAL,
		effect = effect,
		previous = previous,
		awards = facts.awards,
		points = points and points > 0 and points or nil,
	}
	KeepPruning()
end

function handlers.UNIT_SPELLCAST_FAILED(_, castGUID)
	if not issecretvalue(castGUID) then
		pending[castGUID] = nil
	end
end
handlers.UNIT_SPELLCAST_INTERRUPTED = handlers.UNIT_SPELLCAST_FAILED

function handlers.UNIT_COMBAT(unit, event, flags, amount, school)
	if
		issecretvalue(unit)
		or issecretvalue(event)
		or issecretvalue(flags)
		or issecretvalue(amount)
		or issecretvalue(school)
	then
		ns.dev:LogOnce("secret combat", "SECRET", "UNIT_COMBAT payload is secret; ticks can't be read")
		return
	end
	if not next(effects) and not next(lastCasts) then
		return
	end
	local key = ns.Units.Key(unit)
	if not key or not (effects[key] or lastCasts[key]) then
		return
	end
	local now = GetTime()
	if IsDuplicate(key, unit, event, amount, school, now) then
		return
	end
	heard[key] = now

	if not TryAvoid(key, event, flags, amount, school, now) and effects[key] then
		TryTick(key, effects[key], event, flags, amount, school, now)
	end
end

function handlers.NAME_PLATE_UNIT_ADDED(token)
	ns.Units.AddPlate(token)
end

function handlers.NAME_PLATE_UNIT_REMOVED(token)
	ns.Units.RemovePlate(token)
	Drop("plate:" .. token, "plate")
end

function handlers.PLAYER_TARGET_CHANGED()
	ns.Combo.Reset()
	Drop("unit:target", "target")
end

function handlers.PLAYER_FOCUS_CHANGED()
	Drop("unit:focus", "focus")
end

local PLAYER_EVENTS = {
	UNIT_SPELLCAST_SENT = true,
	UNIT_SPELLCAST_SUCCEEDED = true,
	UNIT_SPELLCAST_FAILED = true,
	UNIT_SPELLCAST_INTERRUPTED = true,
}

ns.OnInitialize(function()
	playerClass = select(2, UnitClass("player"))
	-- Nameplates already shown after a /reload.
	for index = 1, 40 do
		local token = "nameplate" .. index
		if UnitExists(token) then
			ns.Units.AddPlate(token)
		end
	end

	local frame = CreateFrame("Frame")
	for event in pairs(handlers) do
		if PLAYER_EVENTS[event] then
			frame:RegisterUnitEvent(event, "player")
		else
			frame:RegisterEvent(event)
		end
	end
	frame:SetScript("OnEvent", function(_, event, ...)
		handlers[event](...)
	end)
end)
