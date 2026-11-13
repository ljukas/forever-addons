local _, ns = ...

-- Dev-only: logs what the design assumes about the client and only the game can show (PROBE).
--   strings   every global format string for kill experience and instance resets, with its value
--   xpmsg     each CHAT_MSG_COMBAT_XP_GAIN: its text (or <secret>), which payload fields are
--             secret, and the XP bar at that moment
--   xpupdate  each PLAYER_XP_UPDATE with the XP bar, so the order against xpmsg shows
--   world     PLAYER_ENTERING_WORLD's flags and GetInstanceInfo()
--   guid      whether a creature's GUID is readable, per unit token and situation
--   system    system messages mentioning a reset, when readable
--   death     PLAYER_DEAD / PLAYER_UNGHOST with the dead, ghost and instance state
if not ns.dev.enabled then
	return
end

local function Log(...)
	ns.log("PROBE", ...)
end

-- True for the first lines of a kind in each situation, then false: a line per kill fills the
-- log's cap in one dungeon run and pushes the one-off lines (strings, world, guid) out of it.
local FEW = 6
local counts = {}

local function Few(kind)
	local key = kind .. " " .. ForeverDev.Situation()
	counts[key] = (counts[key] or 0) + 1
	return counts[key] <= FEW
end

local function LogStrings()
	local names = {}
	for name, value in pairs(_G) do
		if
			type(name) == "string"
			and type(value) == "string"
			and (name:find("^COMBATLOG_XPGAIN") or name:find("INSTANCE_RESET") or name:find("XP_GAIN"))
		then
			table.insert(names, name)
		end
	end
	table.sort(names)
	Log("strings", "count", #names)
	for _, name in ipairs(names) do
		Log("strings", name, "=", _G[name])
	end
end

local function XPBar()
	return ForeverDev.Describe(pcall(UnitXP, "player")) .. "/" .. ForeverDev.Describe(pcall(UnitXPMax, "player"))
end

local function LogGUID(source, unit)
	local exists = UnitExists(unit)
	if issecretvalue(exists) or not exists then
		return
	end
	local attackable = UnitCanAttack("player", unit)
	if issecretvalue(attackable) or not attackable then
		return
	end
	local situation = ForeverDev.Situation(unit)
	local guid = UnitGUID(unit)
	local secret = issecretvalue(guid)
	-- One line per source, situation and outcome: nameplates would flood the log otherwise.
	ns.dev:LogOnce(
		"guid " .. source .. " " .. situation .. " " .. tostring(secret),
		"PROBE",
		"guid",
		source,
		situation,
		"shouldBeSecret",
		ForeverDev.Describe(pcall(C_Secrets.ShouldUnitIdentityBeSecret, unit)),
		"guid",
		guid
	)
end

local handlers = {
	PLAYER_LOGIN = LogStrings,
	CHAT_MSG_COMBAT_XP_GAIN = function(text, playerName, _, _, playerName2, _, _, _, _, _, _, guid)
		if not Few("xpmsg") then
			return
		end
		Log(
			"xpmsg",
			ForeverDev.Situation(),
			"secret:",
			ForeverDev.SecretNames("text", text, "playerName", playerName, "playerName2", playerName2, "guid", guid),
			"bar",
			XPBar(),
			"text",
			text
		)
	end,
	PLAYER_XP_UPDATE = function()
		if Few("xpupdate") then
			Log("xpupdate", ForeverDev.Situation(), "bar", XPBar())
		end
	end,
	PLAYER_ENTERING_WORLD = function(isLogin, isReload)
		Log("world", "login", isLogin, "reload", isReload, "instance", GetInstanceInfo())
	end,
	PLAYER_TARGET_CHANGED = function()
		LogGUID("target", "target")
	end,
	UPDATE_MOUSEOVER_UNIT = function()
		LogGUID("mouseover", "mouseover")
	end,
	NAME_PLATE_UNIT_ADDED = function(unit)
		LogGUID("nameplate", unit)
	end,
	CHAT_MSG_SYSTEM = function(text)
		if issecretvalue(text) then
			ns.dev:LogOnce(
				"system secret " .. ForeverDev.Situation(),
				"PROBE",
				"system",
				ForeverDev.Situation(),
				"secret"
			)
		elseif text:lower():find("reset") then
			Log("system", ForeverDev.Situation(), text)
		end
	end,
	PLAYER_DEAD = function()
		Log("death", "dead", UnitIsDeadOrGhost("player"), "ghost", UnitIsGhost("player"), "instance", IsInInstance())
	end,
	PLAYER_UNGHOST = function()
		Log("death", "unghost", UnitIsDeadOrGhost("player"), "ghost", UnitIsGhost("player"), "instance", IsInInstance())
	end,
}

local frame = CreateFrame("Frame")
frame:SetScript("OnEvent", function(_, event, ...)
	handlers[event](...)
end)
for event in pairs(handlers) do
	frame:RegisterEvent(event)
end
