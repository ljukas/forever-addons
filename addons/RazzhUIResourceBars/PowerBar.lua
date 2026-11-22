local ADDON_NAME, ns = ...

-- The player's power bar: a status bar of ours in a holder the player places and sizes in Edit Mode
-- (EditMode.lua), fed from the player's power on its events. Nothing of Blizzard's player frame is
-- read or touched, so the bar is the same whichever unit frames are shown
-- (docs/adr/0005-draw-the-player-power-bar-ourselves.md).
--
-- Display only. Power values are secret: they go from UnitPower straight into the status bar and
-- are never compared, logged or calculated with.
ns.PowerBar = {}

-- Where the bar sits and how big it is for an Edit Mode layout with nothing saved: bottom centre,
-- above Blizzard's default action bars.
ns.PowerBar.DEFAULTS = {
	point = "BOTTOM",
	x = 0,
	y = 150,
	width = 270,
	height = 12,
	smooth = true,
	-- How the power shows as numbers on the bar (PowerText.lua's MODES).
	text = "hover",
	-- A druid's other powers, in a row above the bar (OffFormPower.lua).
	offForm = true,
	offFormHeight = 10,
	-- A rogue's or Cat Form druid's combo points, in a row on top (ComboPoints.lua).
	comboPoints = true,
	comboPointsHeight = 10,
}

local DEFAULTS = ns.PowerBar.DEFAULTS

-- How far the fill reaches past the holder, under the border: the fill's art (made for the player
-- frame) starts short of the border's left edge, and a full bar stops short of its right edge (in
-- game, 2026-11-10/11). The fills of OffFormPower.lua's row reach as far.
ns.PowerBar.fillOutset = { left = 2, right = 3 }

local holder = CreateFrame("Frame", nil, UIParent)
-- The strata of Blizzard's unit frames, so the bar layers as it did in the player frame.
holder:SetFrameStrata("LOW")
holder:SetSize(DEFAULTS.width, DEFAULTS.height)
holder:SetPoint(DEFAULTS.point, UIParent, DEFAULTS.point, DEFAULTS.x, DEFAULTS.y)
ns.PowerBar.holder = holder

-- The cast bar's background, darker than there, so a little rage or energy (dark red, yellow)
-- stands out against it. Also for what else joins the frame (OffFormPower.lua's row); the caller
-- anchors it.
function ns.PowerBar.CreateBackground(frame)
	local texture = frame:CreateTexture(nil, "BACKGROUND")
	texture:SetAtlas("ui-castingbar-background")
	texture:SetVertexColor(0.35, 0.35, 0.35)
	return texture
end

local background = ns.PowerBar.CreateBackground(holder)
background:SetPoint("TOPLEFT", -1, 1)
background:SetPoint("BOTTOMRIGHT", 1, -1)

-- The cast bar's border too (Blizzard_UIPanels_Game/Mainline/CastingBarFrame.xml, same offsets as
-- the background's), so the bar matches the other free-standing bars. It sits above the bar's fill.
local border = CreateFrame("Frame", nil, holder)
border:SetAllPoints()
border:SetFrameLevel(holder:GetFrameLevel() + 5)
local borderTexture = border:CreateTexture(nil, "OVERLAY")
borderTexture:SetAtlas("ui-castingbar-frame")
borderTexture:SetPoint("TOPLEFT", -2, 2)
borderTexture:SetPoint("BOTTOMRIGHT", 2, -2)
-- What else belongs to the frame (OffFormPower.lua's row) is parented to it.
ns.PowerBar.border = border

-- How much of the dark inner rim the cast bar border shows between its line and the fill (in game,
-- 2026-11-22: two pixels at either end of the bar), and its colour there.
local RIM = 2
local RIM_R, RIM_G, RIM_B = 0.04, 0.02, 0

local function CreateRim(separator, side, far)
	local rim = separator:CreateTexture(nil, "ARTWORK")
	rim:SetColorTexture(RIM_R, RIM_G, RIM_B, 1)
	rim:SetWidth(RIM)
	rim:SetPoint("TOP" .. far, separator, "TOP" .. side)
	rim:SetPoint("BOTTOM" .. far, separator, "BOTTOM" .. side)
end

-- A line to split a row of the frame (OffFormPower.lua, ComboPoints.lua), this many pixels wide: a
-- strip off the cast bar border's left side, from its middle third (clear of the corners), with the
-- border's dark rim on either side, so each part of the row ends and starts as the row's ends do.
-- The border isn't sliced (in game, 2026-11-12), so a row wears one copy of it across its width and
-- these between its parts, rather than a squeezed copy per part. The line is plain dark if the art
-- can't be read. A frame above the fills, as wide as the line (the rims draw past it); the caller
-- anchors it.
function ns.PowerBar.CreateSeparator(parent, width)
	local separator = CreateFrame("Frame", nil, parent)
	separator:SetWidth(width)
	local line = separator:CreateTexture(nil, "OVERLAY")
	line:SetAllPoints()
	local info = C_Texture.GetAtlasInfo("ui-castingbar-frame")
	ns.dev:LogOnce("separator-art", "POWER", "separator art", info ~= nil and info.file ~= nil)
	if info and info.file and info.width > 0 then
		local u = info.leftTexCoord
		local du = (info.rightTexCoord - info.leftTexCoord) * width / info.width
		local dv = (info.bottomTexCoord - info.topTexCoord) / 3
		line:SetTexture(info.file)
		line:SetTexCoord(u, u + du, info.topTexCoord + dv, info.bottomTexCoord - dv)
	else
		line:SetColorTexture(0, 0, 0, 0.9)
	end
	CreateRim(separator, "LEFT", "RIGHT")
	CreateRim(separator, "RIGHT", "LEFT")
	return separator
end

-- The fill. It eases toward each new value when the layout asks for smooth fills.
local fill = CreateFrame("StatusBar", nil, holder)
fill:SetFrameLevel(holder:GetFrameLevel() + 1)
fill:SetPoint("TOPLEFT", holder, "TOPLEFT", -ns.PowerBar.fillOutset.left, 0)
fill:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", ns.PowerBar.fillOutset.right, 0)
-- For what is drawn on the fill (CostPrediction.lua).
ns.PowerBar.fill = fill
local interpolation = Enum.StatusBarInterpolation.ExponentialEaseOut

local ATLAS_PREFIX = "UI-HUD-UnitFrame-Player-PortraitOn-Bar-"

-- The fill's art for a power: its atlas and tint, after Blizzard's rules for the player frame's
-- bar (UnitFrameManaBar_UpdateType, Blizzard_UnitFrame/Mainline/UnitFrame.lua) over its
-- PowerBarColor table (PowerBarColorUtil.lua): the player-frame atlas of the power, else the
-- power's own atlas. A power the table knows only a colour for gets the plain bar in that colour
-- (Blizzard's bar keeps its last art there); one the table doesn't know gets the plain bar in the
-- colour the client gives for it, as Blizzard's does. No power at all (powerToken is nil until the
-- client knows the player) looks like mana. Pure.
function ns.PowerBar.Art(powerToken, altR, altG, altB)
	local info = powerToken and PowerBarColor[powerToken]
	if info and info.atlasElementName then
		return ATLAS_PREFIX .. info.atlasElementName, 1, 1, 1
	elseif info and info.atlas then
		return info.atlas, 1, 1, 1
	elseif info and info.r then
		return ATLAS_PREFIX .. "Mana-Status", info.r, info.g, info.b
	elseif powerToken and altR then
		return ATLAS_PREFIX .. "Mana-Status", altR, altG, altB
	end
	return ATLAS_PREFIX .. "Mana", 1, 1, 1
end

-- The power the bar shows: UnitPowerType's first two results, nil until the client has them.
local powerType, powerToken
-- The token the fill wears the art of; false before the first art, since nil is a token too.
---@type string|false|nil
local artToken = false

-- The fill's tint for its art (Art's colour), and the share of it the fill shows (SetDim).
local artR, artG, artB = 1, 1, 1
local dim = 1

local function ApplyColour()
	fill:SetStatusBarColor(artR * dim, artG * dim, artB * dim)
end

-- Shows the fill at a share of its brightness (1 is all of it): under the cost of the spell being
-- cast (CostPrediction.lua).
function ns.PowerBar.SetDim(share)
	dim = share
	ApplyColour()
end

-- Run after every update of the fill's values or power, with the power type and token (either
-- may be nil) and how the fill moves to the values: the numbers on the bar (PowerText.lua) and
-- the cost of the spell being cast (CostPrediction.lua).
local listeners = {}

function ns.PowerBar.OnChanged(func)
	table.insert(listeners, func)
end

-- Blizzard's look for a dead player's bar: grey, at half strength.
local function ApplyDeadLook()
	local dead = UnitIsDeadOrGhost("player")
	local texture = fill:GetStatusBarTexture()
	texture:SetDesaturated(dead)
	texture:SetAlpha(dead and 0.5 or 1)
	ns.dev:LogChanged("power-dead", dead, "POWER", "dead", dead)
end

-- Fills the bar from the player's power. The values are secret and only pass through.
local function UpdateValues(valueInterpolation)
	if powerType then
		fill:SetMinMaxValues(0, UnitPowerMax("player", powerType))
		fill:SetValue(UnitPower("player", powerType), valueInterpolation)
	end
	for _, func in ipairs(listeners) do
		func(powerType, powerToken, valueInterpolation)
	end
end

-- Follows the power the player uses now. A new power gets its art, and the fill jumps to its
-- value rather than sliding there from the old power's.
local function UpdatePower()
	local newType, newToken, altR, altG, altB = UnitPowerType("player")
	if newType == powerType and newToken == artToken then
		return
	end
	powerType, powerToken, artToken = newType, newToken, newToken
	local atlas
	atlas, artR, artG, artB = ns.PowerBar.Art(newToken, altR, altG, altB)
	fill:SetStatusBarTexture(atlas)
	ApplyColour()
	ApplyDeadLook()
	UpdateValues(Enum.StatusBarInterpolation.Immediate)
	fill:SetToTargetValue()
	ns.dev:LogChanged("power-type", newToken, "POWER", "type", newToken, atlas)
end

-- Smooth fills ease toward each new value; otherwise the fill snaps to it.
local function SetSmooth(smooth)
	interpolation = smooth and Enum.StatusBarInterpolation.ExponentialEaseOut or Enum.StatusBarInterpolation.Immediate
	if not smooth then
		fill:SetToTargetValue()
	end
end

-- How fills move to a new value right now, for the other bars in the frame.
function ns.PowerBar.Interpolation()
	return interpolation
end

-- Places and sizes the holder: layout = { point, x, y, width, height, smooth }, all present. The
-- frames are ours and unprotected, so this is safe in combat.
function ns.PowerBar.SetLayout(layout)
	SetSmooth(layout.smooth)
	holder:ClearAllPoints()
	holder:SetPoint(layout.point, UIParent, layout.point, layout.x, layout.y)
	holder:SetSize(layout.width, layout.height)
	ns.log("POWER", "holder", layout.point, layout.x, layout.y, layout.width, layout.height)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player")
events:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
events:RegisterUnitEvent("UNIT_MAXPOWER", "player")
events:RegisterEvent("PLAYER_DEAD")
events:RegisterEvent("PLAYER_ALIVE")
events:RegisterEvent("PLAYER_UNGHOST")
events:SetScript("OnEvent", function(_, event)
	if event == "UNIT_POWER_FREQUENT" or event == "UNIT_MAXPOWER" then
		UpdateValues(interpolation)
	elseif event == "UNIT_DISPLAYPOWER" then
		UpdatePower()
	elseif event == "PLAYER_ENTERING_WORLD" then
		-- Behind the loading screen, so nothing slides: the bar is simply right when the world shows.
		UpdatePower()
		ApplyDeadLook()
		UpdateValues(Enum.StatusBarInterpolation.Immediate)
		fill:SetToTargetValue()
	else
		ApplyDeadLook()
	end
end)

-- On /reload the player is known already; at login this finds no power yet and the bar starts as
-- an empty mana bar until PLAYER_ENTERING_WORLD.
UpdatePower()
