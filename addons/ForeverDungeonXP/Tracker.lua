local _, ns = ...

-- Records kill experience into the current dungeon run. Decides on entering a 5-player dungeon
-- whether its open run continues (Logic/RunRules.lua), reads each kill message
-- (Logic/XPMessage.lua) and writes through Database.lua. Unverified in game until the first run:
-- whether the kill message's text and creature GUIDs are readable in a dungeon. Both are checked
-- with issecretvalue before use, and the RUN and KILL log lines say which case happened.

ns.Tracker = {}

local RUNS_CHANGED = "ForeverDungeonXP.RunsChanged"

-- A delta on the XP bar and the message it belongs to arrive within this many seconds.
local PAIR_WINDOW = 2

local current -- the run being recorded, nil outside a 5-player dungeon
local copyKnown -- this visit's copy number has been read
local matchers = {} -- for kill messages, Logic/XPMessage.lua
local resetPattern -- for "<dungeon> has been reset.", or nil

-- The XP bar at the last reading, or nil when it couldn't be read.
local lastXP, lastMax

-- Pairing a secret kill message with its XP: the bar's change may come before or after the
-- message. pending is a change no message has claimed yet; awaiting is the time a secret kill
-- started waiting for its change; owed is XP that readable messages already recorded and whose
-- bar change must not be counted again; skipped is the time a readable message that names no
-- creature (a quest, exploration) started waiting for its change.
local pending, pendingShare, pendingTime = 0, 0, 0
local awaiting, skipped
local owed, owedTime = 0, 0

function ns.Tracker.CurrentRun()
	return current
end

local function Changed()
	EventRegistry:TriggerEvent(RUNS_CHANGED)
end

-- Deletes a saved run. If it is the one being recorded, later kills go to a fresh run.
function ns.Tracker.DeleteRun(id)
	local deleted = current and current.id == id and current
	ns.DB.DeleteRun(id)
	if deleted then
		current = ns.DB.NewRun(deleted.instanceID, deleted.name, UnitLevel("player"), "first")
		if current then
			current.copy = deleted.copy
		end
	end
	ns.log("RUN", "deleted", id)
	Changed()
end

local function ReadBaseline()
	local xp, max = UnitXP("player"), UnitXPMax("player")
	if issecretvalue(xp) or issecretvalue(max) then
		lastXP, lastMax = nil, nil
	else
		lastXP, lastMax = xp, max
	end
end

local function ClearPairing()
	pending, pendingShare, pendingTime = 0, 0, 0
	owed, owedTime = 0, 0
	awaiting, skipped = nil, nil
end

local function Fresh(since)
	return since and GetTime() - since <= PAIR_WINDOW
end

-- The gain since the last reading and the fraction of a level it is. Across a level-up the bar
-- wraps: the part before it is measured against the old level, the rest against the new one.
local function ReadGain()
	local oldXP, oldMax = lastXP, lastMax
	ReadBaseline()
	if not oldXP or not lastXP or oldMax <= 0 or lastMax <= 0 then
		return 0, 0
	end
	if lastXP >= oldXP and lastMax == oldMax then
		local gain = lastXP - oldXP
		return gain, gain / oldMax
	end
	local before = oldMax - oldXP
	return before + lastXP, before / oldMax + lastXP / lastMax
end

-- Applies a copy number read from a creature. An unstamped run takes it, unless an earlier run
-- of this dungeon already has it and this one has no kills yet: then the fallback rule started
-- a run too many, and the earlier one continues. A run stamped with another number was continued
-- wrongly, and a new run starts (or the one with this number continues).
local function ApplyCopy(copy)
	copyKnown = true
	if current.copy == copy then
		return
	end
	local other = ns.DB.RunByCopy(current.instanceID, copy)
	if not current.copy and not (other and current.kills == 0) then
		current.copy = copy
		ns.log("RUN", "copy stamp", copy, "run", current.number)
		return
	end
	local previous = current
	if other then
		ns.DB.ReopenRun(other)
		current = other
	else
		current = ns.DB.NewRun(previous.instanceID, previous.name, UnitLevel("player"), "copy")
		current.copy = copy
	end
	ns.DB.DropEmptyRuns(current)
	ns.log("RUN", other and "copy same" or "copy new", copy, "run", current.number, "was", previous.number)
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

local function Enter(isLogin, isReload, attempt)
	local name, instanceType, _, _, _, _, _, instanceID = GetInstanceInfo()
	current, copyKnown = nil, false
	ClearPairing()
	ReadBaseline()

	if instanceType ~= "party" then
		ns.DB.DropEmptyRuns(nil)
		ns.log("RUN", "outside", instanceType)
		Changed()
		return
	end
	if not ns.DB.Character() then
		-- The realm name can be empty right after login; without it there is nowhere to save.
		if attempt < 10 then
			C_Timer.After(1, function()
				Enter(isLogin, isReload, attempt + 1)
			end)
		end
		return
	end

	local open = ns.DB.OpenRun(instanceID)
	local decision, reason = ns.RunRules.Decide(open, { reload = isLogin or isReload, now = GetServerTime() })
	if decision == "continue" then
		current = open
	else
		current = ns.DB.NewRun(instanceID, name, UnitLevel("player"), reason)
	end
	ns.DB.DropEmptyRuns(current)
	ns.log("RUN", "enter", name, instanceID, decision, reason, "run", current.number, "copy", current.copy)
	TryCopy("target")
	TryCopy("mouseover")
	Changed()
end

local function OnKillMessage(text)
	if not current then
		return
	end
	local now = GetServerTime()

	if issecretvalue(text) then
		ns.DB.AddKill(current, nil, 0, 0, now)
		if pending > 0 and Fresh(pendingTime) then
			ns.DB.AddXP(current, pending, pendingShare)
			awaiting = nil
		else
			awaiting = GetTime()
		end
		pending, pendingShare = 0, 0
		ns.log("KILL", "secret", "run", current.number, "kills", current.kills, "xp", current.xp)
		Changed()
		return
	end

	local creature, xp = ns.XPMessage.Parse(matchers, text)
	if not creature then
		-- A quest or exploration gain: not a kill. Its change on the bar must not be picked up
		-- by a secret kill either.
		if pending > 0 and Fresh(pendingTime) then
			pending, pendingShare = 0, 0
		else
			skipped = GetTime()
		end
		ns.log("KILL", "unparsed", text)
		return
	end

	local max = UnitXPMax("player")
	local share = (not issecretvalue(max) and max > 0) and xp / max or 0
	ns.DB.AddKill(current, creature, xp, share, now)
	if pending > 0 and Fresh(pendingTime) then
		pending, pendingShare = 0, 0
	else
		owed, owedTime = (Fresh(owedTime) and owed or 0) + xp, GetTime()
	end
	ns.log("KILL", "parsed", creature, xp, "run", current.number, "kills", current.kills, "xp", current.xp)
	Changed()
end

local function OnXPUpdate()
	if not current then
		ReadBaseline()
		return
	end
	local gain, share = ReadGain()
	if gain <= 0 then
		return
	end
	-- XP a readable kill message already recorded.
	if owed > 0 and Fresh(owedTime) then
		local used = math.min(owed, gain)
		owed = owed - used
		share = share * (gain - used) / gain
		gain = gain - used
		if gain <= 0 then
			return
		end
	end
	if Fresh(skipped) then
		skipped = nil
		return
	end
	if Fresh(awaiting) then
		awaiting = nil
		ns.DB.AddXP(current, gain, share)
		ns.log("KILL", "secret xp", gain, "run", current.number, "xp", current.xp)
		Changed()
		return
	end
	pending, pendingShare, pendingTime = gain, share, GetTime()
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
			ns.DB.CloseRun(run.instanceID)
		end
	end
	ns.log("RUN", "reset", dungeon)
end

local handlers = {
	PLAYER_ENTERING_WORLD = function(isLogin, isReload)
		Enter(isLogin, isReload, 1)
	end,
	CHAT_MSG_COMBAT_XP_GAIN = OnKillMessage,
	PLAYER_XP_UPDATE = OnXPUpdate,
	CHAT_MSG_SYSTEM = OnSystemMessage,
	PLAYER_DEAD = function()
		if current then
			current.died = true
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

-- The client's format strings for kill experience: every COMBATLOG_XPGAIN* global. Which ones
-- exist on Forever is only known in game, so they are collected by name prefix.
local function CollectFormats()
	local formats = {}
	for name, value in pairs(_G) do
		if type(name) == "string" and type(value) == "string" and name:find("^COMBATLOG_XPGAIN") then
			table.insert(formats, value)
		end
	end
	return formats
end

ns.OnInitialize(function()
	local formats = CollectFormats()
	matchers = ns.XPMessage.Build(formats)
	ns.log("LOADED", "xp formats", #formats, "kill matchers", #matchers)

	local reset = _G["INSTANCE_RESET_SUCCESS"]
	if type(reset) == "string" then
		local pattern, captures = ns.XPMessage.Pattern(reset)
		if pattern and #captures == 1 then
			resetPattern = pattern
		end
	end

	-- The player's own reset closes every dungeon's run, whatever the chat says.
	hooksecurefunc("ResetInstances", function()
		ns.DB.CloseAllRuns()
		ns.log("RUN", "reset own")
	end)

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
