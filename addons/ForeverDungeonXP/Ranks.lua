local _, ns = ...

-- Finds out which creatures are elites and bosses (Logic/Creatures.lua says why this can't be
-- a lookup by name). Two sources:
--   deaths: kill messages that arrive together form a batch. Shortly after its first message,
--     the enemy units that died around then (nameplates, or the target while no nameplate has
--     been seen) are counted. If there are at least as many as the batch has kills and they all
--     have one rank, each creature named in the batch gets a vote for it. Otherwise nothing is
--     recorded: a mixed pull is no evidence.
--   encounters: a won encounter whose name is a creature's makes that creature a boss.
-- Unverified in game: that UnitIsDead and UnitClassification are readable for dungeon enemies
-- (the API docs don't flag them secret), that a dead unit's nameplate still answers when it is
-- removed, and that ENCOUNTER_END fires in Forever's dungeons. Everything is checked with
-- issecretvalue, and the RANK log lines say what happened.

ns.Ranks = {}

-- How long after a batch's first kill message the dead are counted, and how long before it a
-- death still belongs to the batch (the message and the death arrive in no known order).
local WINDOW = 0.5
local MAX_NAMEPLATES = 40

local batch -- { run, start, kills, names = { [creature] = true } }, nil between batches
local deaths = {} -- { time, rank } of enemy units seen dead, oldest first
-- [unit token] = true while its unit was last seen alive. Only such a unit's death counts, and
-- once: a corpse that was already there (a kill worth no experience, a corpse targeted again)
-- is not a death of this moment.
local alive = {}
local platesSeen = false -- a nameplate has been seen this session; the target is then left out
local bosses = {} -- [encounter name] = the run it was won in

local function Readable(value)
	if issecretvalue(value) then
		ns.dev:LogOnce("rank secret", "RANK", "a unit's state is secret: no ranks from deaths")
		return nil
	end
	return value
end

-- The rank of a unit, or nil when the client keeps it secret.
local function UnitRank(unit)
	local classification, isBoss, level = UnitClassification(unit), UnitIsBossMob(unit), UnitLevel(unit)
	if Readable(classification) == nil or Readable(isBoss) == nil or Readable(level) == nil then
		return nil
	end
	return ns.Creatures.Classify(classification, isBoss, level)
end

-- Notes whether the token now holds a living enemy.
local function SeeUnit(unit)
	alive[unit] = nil
	if Readable(UnitExists(unit)) and Readable(UnitCanAttack("player", unit)) then
		local dead = Readable(UnitIsDead(unit))
		alive[unit] = dead == false or nil
	end
end

-- Counts the unit's death, if it was seen alive and is now dead.
local function CountIfDead(unit)
	if not alive[unit] or not Readable(UnitExists(unit)) or not Readable(UnitIsDead(unit)) then
		return
	end
	alive[unit] = nil
	local rank = UnitRank(unit)
	if rank then
		if #deaths >= MAX_NAMEPLATES then
			-- Deaths no kill message followed (creatures worth no experience) don't pile up.
			table.remove(deaths, 1)
		end
		table.insert(deaths, { time = GetTime(), rank = rank })
	end
end

local function Flush()
	local finished = batch
	batch = nil
	if not finished or finished.run ~= ns.Tracker.CurrentRun() then
		return
	end
	for index = 1, MAX_NAMEPLATES do
		CountIfDead("nameplate" .. index)
	end
	if not platesSeen then
		CountIfDead("target")
	end
	local ranks = {}
	for _, death in ipairs(deaths) do
		if death.time >= finished.start - WINDOW then
			table.insert(ranks, death.rank)
		end
	end
	wipe(deaths)
	local rank = #ranks >= finished.kills and ns.Creatures.Agreed(ranks) or nil
	for name in pairs(finished.names) do
		if rank then
			ns.DB.AddRank(finished.run, name, rank)
		end
		if ns.dev.enabled then
			local outcome = rank
				or (#ranks == 0 and "no deaths seen")
				or (#ranks < finished.kills and "too few")
				or "mixed"
			ns.dev:LogOnce(
				"rank " .. name .. " " .. outcome,
				"RANK",
				name,
				outcome,
				"kills",
				finished.kills,
				"deaths",
				#ranks
			)
		end
	end
	if rank then
		EventRegistry:TriggerEvent("ForeverDungeonXP.RunsChanged")
	end
end

-- Tracker.lua calls this for each kill message that named a creature, after counting the kill.
function ns.Ranks.OnKill(run, creature)
	if bosses[creature] == run then
		bosses[creature] = nil
		ns.DB.AddRank(run, creature, "boss")
	end
	if batch and batch.run ~= run then
		batch = nil
	end
	if not batch then
		batch = { run = run, start = GetTime(), kills = 0, names = {} }
		C_Timer.After(WINDOW, Flush)
	end
	batch.kills = batch.kills + 1
	batch.names[creature] = true
end

local handlers = {
	NAME_PLATE_UNIT_ADDED = function(unit)
		platesSeen = true
		SeeUnit(unit)
	end,
	-- A dead unit's nameplate goes away at once, perhaps before the batch is counted.
	NAME_PLATE_UNIT_REMOVED = function(unit)
		if ns.Tracker.CurrentRun() then
			CountIfDead(unit)
		end
		alive[unit] = nil
	end,
	PLAYER_TARGET_CHANGED = function()
		SeeUnit("target")
	end,
	ENCOUNTER_END = function(_, name, _, _, success)
		local run = ns.Tracker.CurrentRun()
		if not run or issecretvalue(name) or issecretvalue(success) or success ~= 1 or type(name) ~= "string" then
			return
		end
		ns.log("RANK", "encounter won", name, "killed already", run.creatures[name] ~= nil)
		if run.creatures[name] then
			ns.DB.AddRank(run, name, "boss")
			EventRegistry:TriggerEvent("ForeverDungeonXP.RunsChanged")
		else
			-- The kill message may come after the encounter's end.
			bosses[name] = run
		end
	end,
}

ns.OnInitialize(function()
	local frame = CreateFrame("Frame")
	frame:SetScript("OnEvent", function(_, event, ...)
		handlers[event](...)
	end)
	for event in pairs(handlers) do
		frame:RegisterEvent(event)
	end
end)
