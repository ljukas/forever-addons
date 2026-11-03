local ADDON_NAME = ...

-- Probes that hold for every addon, logged under ForeverDev (scripts/devlog.sh --addon
-- ForeverDev). They record what Forever restricts where, so features can be planned around it:
--   CLIENT       version, build, class and level, on login and reload
--   PROBE        secret restrictions, addon message restriction and every restriction type's
--                state, on entering the world, changing zones and every restriction change
--   RESTRICTION  a restriction type changing state
--   UNIT         which of a unit's values are secret (health, power, ...) and its power type's base
--                secrecy, once per unit, situation (ForeverDev.Situation), power type and answer:
--                the player on entering the world (any loading screen) and form changes, the
--                target when it changes, and both on every restriction change
--   ATLAS        whether each candidate atlas exists in this client, with its size, a few seconds
--                after login or reload. The list is atlases we want to use, verified or guessed
--   MINIMAP      every child frame of Minimap and MinimapCluster, a few seconds after login or
--                reload: type, whether it is shown and takes clicks, its distance from the
--                minimap's center, and what issecurevariable says created it (secure = Blizzard,
--                else the tainting addon). Also whether issecurevariable exists at all, and
--                LibDBIcon's button list
-- Addon-specific probes live in that addon's Dev/ folder.

local dev = ForeverDev.For(ADDON_NAME)

local function EnumName(enum, value)
	for name, enumValue in pairs(enum) do
		if enumValue == value then
			return name
		end
	end
	return tostring(value)
end

local function RestrictionStates()
	local states = {}
	for name, restriction in pairs(Enum.AddOnRestrictionType) do
		table.insert(states, name .. "=" .. C_RestrictedActions.GetAddOnRestrictionState(restriction))
	end
	table.sort(states)
	return table.concat(states, " ")
end

local function Probe(reason)
	dev:Log(
		"PROBE",
		reason,
		ForeverDev.Situation(),
		"secretRestrictions",
		C_Secrets.HasSecretRestrictions(),
		"addonMessagesRestricted",
		C_ChatInfo.AreOutgoingAddonChatMessagesRestricted(),
		"restrictions",
		RestrictionStates()
	)
end

local function ProbeUnit(unit)
	if not UnitExists(unit) then
		return
	end
	local situation = ForeverDev.Situation(unit)
	-- The unit's primary (displayed) power only.
	local powerType, powerToken = UnitPowerType(unit)
	local secrecy = powerType and EnumName(Enum.SecrecyLevel, C_Secrets.GetPowerTypeSecrecy(powerType)) or "none"
	powerToken = powerToken or "NOPOWER"
	local secret = ForeverDev.SecretNames(
		"guid",
		UnitGUID(unit),
		"name",
		(UnitName(unit)),
		"health",
		UnitHealth(unit),
		"max",
		UnitHealthMax(unit),
		"power",
		UnitPower(unit),
		"powerMax",
		UnitPowerMax(unit)
	)
	-- The answer is part of the key: InCombatLockdown and the secret restrictions may not switch
	-- at the same moment, so a first sample taken between them mustn't hide the later ones.
	dev:LogOnce(
		"unit " .. unit .. " " .. situation .. " " .. powerToken .. " " .. secret,
		"UNIT",
		unit,
		situation,
		powerToken,
		"secrecy",
		secrecy,
		"secret:",
		secret
	)
end

local function ProbeUnits()
	ProbeUnit("player")
	ProbeUnit("target")
end

-- Atlases a feature wants to use. Those marked "source" appear in Forever's own UI source; the
-- rest are guesses from Retail, and this probe is how we find out whether they exist.
local CANDIDATE_ATLASES = {
	-- ForeverMap's button bag: the minimap zoom buttons' art (source)
	"ui-hud-minimap-zoom-in",
	"ui-hud-minimap-zoom-in-down",
	"ui-hud-minimap-zoom-in-mouseover",
	"ui-hud-minimap-zoom-out",
	"ui-hud-minimap-addon-indicator",
	-- ForeverMap's button bag: the addon compartment button's plain art (source)
	"ui-hud-minimap-button",
	"ui-hud-minimap-button-down",
	-- ForeverMap's button bag: a "list / more" icon, ideally three horizontal lines
	"friends-icon-menu", -- source: Blizzard_SocialUI
	"OptionsIcon-Brown", -- source: Blizzard_GroupFinder_VanillaStyle
	"uitools-icon-hamburger",
	"common-icon-hamburger",
	"hamburger-menu",
	"Map-Filter-Button",
	"QuestLog-icon-setting",
	"UI-HUD-MicroMenu-GameMenu-Up",
}

local function ProbeAtlases()
	for _, atlas in ipairs(CANDIDATE_ATLASES) do
		local info = C_Texture.GetAtlasInfo(atlas)
		if info then
			dev:Log("ATLAS", atlas, "exists", info.width .. "x" .. info.height, "file", info.file)
		else
			dev:Log("ATLAS", atlas, "missing")
		end
	end
end

-- Distance between the centers of frame and Minimap, "?" when either isn't laid out yet, or "secret"
-- when a center or scale is secret.
local function DistanceFromMinimap(frame)
	local x, y = frame:GetCenter()
	local mx, my = Minimap:GetCenter()
	local frameScale, minimapScale = frame:GetEffectiveScale(), Minimap:GetEffectiveScale()
	if
		issecretvalue(x)
		or issecretvalue(y)
		or issecretvalue(mx)
		or issecretvalue(my)
		or issecretvalue(frameScale)
		or issecretvalue(minimapScale)
	then
		return "secret"
	end
	if not (x and mx) then
		return "?"
	end
	local scale = frameScale / minimapScale
	return math.floor(math.sqrt((x * scale - mx) ^ 2 + (y * scale - my) ^ 2) + 0.5)
end

local function Creator(name, frame)
	if not issecurevariable then
		return "noapi"
	elseif not name or _G[name] ~= frame then
		return "anonymous"
	end
	local isSecure, taintedBy = issecurevariable(_G, name)
	return isSecure and "secure" or ("tainted:" .. tostring(taintedBy))
end

local function ProbeChildren(parentName, parent)
	for _, child in ipairs({ parent:GetChildren() }) do
		if child:IsForbidden() then
			dev:Log("MINIMAP", parentName, "forbidden child")
		else
			local name = child:GetName()
			dev:Log(
				"MINIMAP",
				parentName,
				name or "anonymous",
				child:GetObjectType(),
				"shown",
				child:IsShown(),
				"mouse",
				child:IsMouseEnabled(),
				"onclick",
				child:HasScript("OnClick") and child:GetScript("OnClick") ~= nil,
				"distance",
				DistanceFromMinimap(child),
				"creator",
				Creator(name, child)
			)
		end
	end
end

local function ProbeMinimap()
	dev:Log("MINIMAP", "issecurevariable", type(issecurevariable), "Minimap is", Creator("Minimap", Minimap))
	ProbeChildren("Minimap", Minimap)
	ProbeChildren("MinimapCluster", MinimapCluster)
	local dbIcon = LibStub and LibStub("LibDBIcon-1.0", true)
	if dbIcon then
		dev:Log("MINIMAP", "LibDBIcon buttons", table.concat(dbIcon:GetButtonList(), " "))
	else
		dev:Log("MINIMAP", "no LibDBIcon loaded")
	end
end

local handlers = {}

function handlers.PLAYER_ENTERING_WORLD(isInitialLogin, isReloadingUi)
	if isInitialLogin or isReloadingUi then
		local version, build = GetBuildInfo()
		dev:Log("CLIENT", version, build, "class", select(2, UnitClass("player")), "level", UnitLevel("player"))
		-- Late enough for other addons to have made their minimap buttons on PLAYER_LOGIN.
		C_Timer.After(5, function()
			ProbeAtlases()
			ProbeMinimap()
		end)
	end
	Probe("entering world")
	ProbeUnit("player")
end

function handlers.ZONE_CHANGED_NEW_AREA()
	Probe("zone")
end

function handlers.ADDON_RESTRICTION_STATE_CHANGED(restriction, state)
	dev:Log("RESTRICTION", EnumName(Enum.AddOnRestrictionType, restriction), "state", state)
	Probe("restriction change")
	-- Secrecy follows the restriction states, not combat, so this is when unit values can start
	-- or stop reading as secret, whether or not they change. A restriction that is activating is
	-- only enforced once this event's dispatch has completed, so the units are probed after it.
	C_Timer.After(0, ProbeUnits)
end

function handlers.PLAYER_TARGET_CHANGED()
	ProbeUnit("target")
end

-- A form change switches the player's displayed power type.
function handlers.UNIT_DISPLAYPOWER()
	ProbeUnit("player")
end

local frame = CreateFrame("Frame")
for event in pairs(handlers) do
	-- UNIT_ events are the player's only, so they don't fire for every party member and nameplate.
	if event:find("^UNIT_") then
		frame:RegisterUnitEvent(event, "player")
	else
		frame:RegisterEvent(event)
	end
end
frame:SetScript("OnEvent", function(_, event, ...)
	handlers[event](...)
end)
