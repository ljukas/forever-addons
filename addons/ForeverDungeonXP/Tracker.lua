local _, ns = ...

-- Records kill experience into the current dungeon run. Decides on entering a 5-player dungeon
-- whether its open run continues (Logic/RunRules.lua), reads each kill message
-- (Logic/XPMessage.lua) and writes through Database.lua. Unverified in game until the first run:
-- whether the kill message's text and creature GUIDs are readable in a dungeon. Both are checked
-- with issecretvalue before use, and the RUN and KILL log lines say which case happened.

ns.Tracker = {}

local RUNS_CHANGED = "ForeverDungeonXP.RunsChanged"

local current -- the run being recorded, nil outside a 5-player dungeon
local copyKnown -- this visit's copy number has been read
local matchers = {} -- for kill messages, Logic/XPMessage.lua
local resetPattern -- for "<dungeon> has been reset.", or nil
local entries = 0 -- counts Enter calls, so a retry from an earlier one can tell it is stale

local bar = ns.XPBar.New()

-- Experience for kills whose message was secret. A secret message carries no amount, and
-- whether the XP bar changes before or after its message isn't known, nor whether a pull's
-- kills change it once or one by one. So nothing is paired: the run's unknown bucket holds what
-- the bar gained while the run was recorded minus what readable messages explain, once a secret
-- kill has been seen. Any event order gives the same total. Per recording stretch (a visit, or
-- since the recorded run last changed):
local gained, gainedShare = 0, 0 -- the bar's gains
local explained, explainedShare = 0, 0 -- XP readable messages reported (kills or not)
local given, givenShare = 0, 0 -- what the unknown bucket got so far
local secretKills = 0
-- Until the first secret kill, only what happened in the last few seconds can belong to it: an
-- unexplained gain from minutes ago (a gain the client sent no message for) must not be swept in.
local STALE = 3
local lastActivity = 0

function ns.Tracker.CurrentRun()
	return current
end

local function Changed()
	EventRegistry:TriggerEvent(RUNS_CHANGED)
end

local function ClearAccounts()
	gained, gainedShare, explained, explainedShare, given, givenShare = 0, 0, 0, 0, 0, 0
	secretKills = 0
end

-- Called before each gain or readable message is added to the accounts.
local function Touch()
	local now = GetTime()
	if secretKills == 0 and now - lastActivity > STALE then
		gained, gainedShare, explained, explainedShare = 0, 0, 0, 0
	end
	lastActivity = now
end

-- Reads the XP bar. Returns the gain since the last reading and its fraction of a level.
local function ReadBar()
	local xp, max = UnitXP("player"), UnitXPMax("player")
	if issecretvalue(xp) or issecretvalue(max) then
		ns.XPBar.Reset(bar)
		return 0, 0
	end
	return ns.XPBar.Gain(bar, xp, max)
end

-- Brings the unknown bucket to what the bar gained and no readable message explains.
local function Settle()
	if secretKills == 0 then
		return
	end
	local xp = math.max(0, gained - explained)
	local share = math.max(0, gainedShare - explainedShare)
	if xp ~= given or share ~= givenShare then
		ns.DB.AddUnknownXP(current, xp - given, share - givenShare)
		given, givenShare = xp, share
	end
end

-- The player's level, 0 if the client keeps it secret.
local function PlayerLevel()
	local level = UnitLevel("player")
	return issecretvalue(level) and 0 or level
end

-- Makes run the one being recorded from now on.
local function Record(run)
	current = run
	ClearAccounts()
	return run
end

-- Deletes a saved run. If it is the one being recorded, later kills go to a fresh run.
function ns.Tracker.DeleteRun(id)
	local deleted = current and current.id == id and current
	ns.DB.DeleteRun(id)
	if deleted then
		Record(ns.DB.NewRun(deleted.instanceID, deleted.name, PlayerLevel(), "deleted"))
		if current then
			ns.DB.SetCopy(current, deleted.copy)
		end
	end
	ns.log("RUN", "deleted", id)
	Changed()
end

-- Applies a copy number read from a creature. Three cases beyond "already known":
--   the recorded run has no number yet and no other run of this dungeon has this one: it takes it;
--   another run has it: that run is the one this visit continues, so the recorded run (started
--   by the fallback rule) is merged into it, or just dropped if it has no kills;
--   the recorded run has a different number: it was continued wrongly, and a new run starts.
local function ApplyCopy(copy)
	copyKnown = true
	if current.copy == copy then
		ns.log("RUN", "copy unchanged", copy, "run", current.number)
		return
	end
	local previous = current
	local other = ns.DB.RunByCopy(previous.instanceID, copy)
	if other then
		Settle()
		if not previous.copy and previous.kills > 0 then
			ns.DB.MergeRun(previous, other)
		end
		ns.DB.ReopenRun(other)
		Record(other)
		ns.log("RUN", "copy same", copy, "run", other.number, "was", previous.number, "kills", previous.kills)
	elseif not previous.copy then
		ns.DB.SetCopy(previous, copy)
		ns.log("RUN", "copy stamp", copy, "run", previous.number, "openedBy", previous.openedBy)
		return
	else
		Settle()
		Record(ns.DB.NewRun(previous.instanceID, previous.name, PlayerLevel(), "copy"))
		ns.DB.SetCopy(current, copy)
		ns.log("RUN", "copy new", copy, "run", current.number, "was", previous.number, "copy", previous.copy)
	end
	ns.DB.DropEmptyRuns(current)
	Changed()
end

local function TryCopy(unit)
	if not current or copyKnown then
		return
	end
	local exists = UnitExists(unit)
	if issecretvalue(exists) or not exists then
		return
	end
	local attackable = UnitCanAttack("player", unit)
	if issecretvalue(attackable) or not attackable then
		return
	end
	local guid = UnitGUID(unit)
	if issecretvalue(guid) or not guid then
		return
	end
	local copy = ns.RunRules.Copy(guid)
	if copy then
		ApplyCopy(copy)
	end
end

local OnXPUpdate

local function Enter(isLogin, isReload, attempt, entry)
	if entry ~= entries then
		return -- a later loading screen has taken over
	end
	-- Read the bar while the run being left is still the recorded one: a gain whose update the
	-- loading screen swallowed still belongs to it.
	OnXPUpdate()
	local name, instanceType, _, _, _, _, _, instanceID = GetInstanceInfo()
	if issecretvalue(name) or issecretvalue(instanceType) or issecretvalue(instanceID) then
		current = nil
		ns.log("RUN", "instance info secret")
		return
	end

	if instanceType ~= "party" then
		current = nil
		ns.DB.DropEmptyRuns(nil)
		ns.log("RUN", "outside", instanceType)
		Changed()
		return
	end
	if current and current.instanceID == instanceID then
		-- A loading screen inside the dungeon being recorded (a teleport): the same visit.
		ns.log("RUN", "enter", name, instanceID, "continue", "same visit", "run", current.number)
		return
	end
	current, copyKnown = nil, false
	if not ns.DB.Character() then
		-- The realm name can be empty right after login; without it there is nowhere to save.
		if attempt < 10 then
			C_Timer.After(1, function()
				Enter(isLogin, isReload, attempt + 1, entry)
			end)
		else
			ns.log("RUN", "not recording: no character key", name)
		end
		return
	end

	local open = ns.DB.OpenRun(instanceID)
	local decision, reason = ns.RunRules.Decide(open, { reload = isLogin or isReload, now = GetServerTime() })
	local run = Record(decision == "continue" and open or ns.DB.NewRun(instanceID, name, PlayerLevel(), reason))
	-- A death is one corpse run's worth: walking out alive after it starts a new run.
	ns.DB.SetDied(run, false)
	ns.DB.DropEmptyRuns(run)
	ns.log("RUN", "enter", name, instanceID, decision, reason, "run", run.number, "by", run.openedBy, "copy", run.copy)
	TryCopy("target")
	TryCopy("mouseover")
	Changed()
end

local function OnKillMessage(text)
	if not current then
		return
	end

	if issecretvalue(text) then
		Touch()
		secretKills = secretKills + 1
		ns.DB.AddKill(current, nil, 0, 0, GetServerTime(), PlayerLevel())
		ns.Party.OnKill(current)
		Settle()
		ns.log(
			"KILL",
			"secret",
			"run",
			current.number,
			"kills",
			current.kills,
			"fallback",
			current.fallback,
			"xp",
			current.xp
		)
		Changed()
		return
	end

	local creature, xp, format = ns.XPMessage.Parse(matchers, text)
	if not xp then
		ns.log("KILL", "unparsed", text)
		return
	end
	-- Measured against the level's size at the last bar reading. For the one kill that crosses a
	-- level-up this is one level's size for the whole gain: off by a fraction of that kill.
	local share = (bar.max and bar.max > 0) and xp / bar.max or 0
	Touch()
	explained, explainedShare = explained + xp, explainedShare + share
	if creature then
		ns.DB.AddKill(current, creature, xp, share, GetServerTime(), PlayerLevel())
		ns.Ranks.OnKill(current, creature)
		ns.Party.OnKill(current)
		if ns.dev.enabled then
			-- Once per format and creature: a line per kill pushes a run's RUN lines out of the
			-- log's cap.
			ns.dev:LogOnce("kill " .. format .. " " .. creature, "KILL", "parsed", format, creature, xp)
		end
	else
		-- A quest or exploration gain: not a kill.
		ns.log("KILL", "other", format, xp)
	end
	Settle()
	Changed()
end

function OnXPUpdate()
	local gain, share = ReadBar()
	if not current or gain <= 0 then
		return
	end
	Touch()
	gained, gainedShare = gained + gain, gainedShare + share
	if secretKills > 0 then
		Settle()
		ns.log("KILL", "bar", gain, "run", current.number, "unknown xp", given)
		Changed()
	end
end

local function OnSystemMessage(text)
	if not resetPattern or issecretvalue(text) then
		return
	end
	local dungeon = text:match(resetPattern)
	if not dungeon then
		return
	end
	for _, run in ipairs(ns.DB.Runs()) do
		if run.name == dungeon then
			ns.DB.CloseRun(run.instanceID, "reset")
		end
	end
	ns.log("RUN", "reset", dungeon)
end

-- The player's own reset closes every dungeon's run. The hook runs on the call, not on success,
-- so only where a reset can work: outside an instance, alone or as the group's leader.
local function OnResetInstances()
	if IsInInstance() or (IsInGroup() and not UnitIsGroupLeader("player")) then
		return
	end
	ns.DB.CloseAllRuns("reset")
	ns.log("RUN", "reset own")
end

local handlers = {
	PLAYER_ENTERING_WORLD = function(isLogin, isReload)
		entries = entries + 1
		Enter(isLogin, isReload, 1, entries)
	end,
	CHAT_MSG_COMBAT_XP_GAIN = OnKillMessage,
	PLAYER_XP_UPDATE = OnXPUpdate,
	PLAYER_LEVEL_UP = OnXPUpdate,
	CHAT_MSG_SYSTEM = OnSystemMessage,
	PLAYER_DEAD = function()
		if current then
			ns.DB.SetDied(current, true)
			ns.log("RUN", "died", "run", current.number)
		end
	end,
	PLAYER_TARGET_CHANGED = function()
		TryCopy("target")
	end,
	UPDATE_MOUSEOVER_UNIT = function()
		TryCopy("mouseover")
	end,
	NAME_PLATE_UNIT_ADDED = TryCopy,
}

-- The client's format strings for experience gains: every COMBATLOG_XPGAIN* global. Which ones
-- exist on Forever is only known in game, so they are collected by name prefix.
local function CollectFormats()
	local formats = {}
	for name, value in pairs(_G) do
		if type(name) == "string" and type(value) == "string" and name:find("^COMBATLOG_XPGAIN") then
			table.insert(formats, { name = name, format = value })
		end
	end
	return formats
end

ns.OnInitialize(function()
	local formats = CollectFormats()
	matchers = ns.XPMessage.Build(formats)

	local reset = _G["INSTANCE_RESET_SUCCESS"]
	if type(reset) == "string" then
		local pattern, captures = ns.XPMessage.Pattern(reset)
		if pattern and #captures == 1 and not captures[1].number then
			resetPattern = pattern
		end
	end

	if ns.dev.enabled then
		local creatures = 0
		for _, matcher in ipairs(matchers) do
			if matcher.creature then
				creatures = creatures + 1
			end
		end
		ns.log(
			"LOADED",
			"xp formats",
			#formats,
			"matchers",
			#matchers,
			"for kills",
			creatures,
			"reset pattern",
			resetPattern and "built" or (reset and "unusable" or "no INSTANCE_RESET_SUCCESS")
		)
	end

	hooksecurefunc("ResetInstances", OnResetInstances)

	local frame = CreateFrame("Frame")
	frame:SetScript("OnEvent", function(_, event, ...)
		handlers[event](...)
	end)
	for event in pairs(handlers) do
		if event == "PLAYER_XP_UPDATE" then
			frame:RegisterUnitEvent(event, "player")
		else
			frame:RegisterEvent(event)
		end
	end
end)
