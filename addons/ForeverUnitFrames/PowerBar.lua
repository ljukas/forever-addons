local ADDON_NAME, ns = ...

-- Moves Blizzard's own player power bar (PlayerFrame_GetManaBar) out of the player frame into a
-- holder the player places and sizes in Edit Mode (EditMode.lua). Blizzard keeps updating the bar:
-- value, colour, text, full-power pulse and spend feedback, so the secret power values never reach
-- this code (docs/adr/0002-detach-the-player-power-bar-by-reparenting-blizzards-bar.md).
ns.PowerBar = {}

-- Where the bar sits and how big it is for an Edit Mode layout with nothing saved: bottom centre,
-- above Blizzard's default action bars.
ns.PowerBar.DEFAULTS = {
	point = "BOTTOM",
	x = 0,
	y = 150,
	width = 270,
	height = 12,
}

local DEFAULTS = ns.PowerBar.DEFAULTS

local holder = CreateFrame("Frame", nil, UIParent)
holder:SetFrameStrata(PlayerFrame:GetFrameStrata())
holder:SetSize(DEFAULTS.width, DEFAULTS.height)
holder:SetPoint(DEFAULTS.point, UIParent, DEFAULTS.point, DEFAULTS.x, DEFAULTS.y)
ns.PowerBar.holder = holder

-- The player frame's art gives the bar its dark well and edge; on its own it gets a dark
-- background and a thin black outline.
local outline = holder:CreateTexture(nil, "BACKGROUND", nil, -8)
outline:SetColorTexture(0, 0, 0, 1)
outline:SetPoint("TOPLEFT", -1, 1)
outline:SetPoint("BOTTOMRIGHT", 1, -1)

local background = holder:CreateTexture(nil, "BACKGROUND", nil, -7)
background:SetColorTexture(0.06, 0.06, 0.06, 0.85)
background:SetAllPoints()

-- The backdrop shows only while Blizzard shows the bar.
local function SetBackdropShown(shown)
	outline:SetShown(shown)
	background:SetShown(shown)
end

local function ApplyBar()
	local bar = PlayerFrame_GetManaBar()
	if bar:GetParent() ~= holder then
		bar:SetParent(holder)
	end
	bar:SetFrameLevel(holder:GetFrameLevel() + 1)
	-- Blizzard anchors the bar by its TOPLEFT and sets its size; filling the holder replaces both.
	bar:ClearAllPoints()
	bar:SetAllPoints(holder)

	-- The player frame's mask is cut to its art; the plain bar mask Blizzard uses beside an
	-- alternate power bar suits a free-standing bar.
	local mask = bar.ManaBarMask
	mask:SetAtlas("Unit_BarMask")
	mask:ClearAllPoints()
	mask:SetAllPoints(bar)

	SetBackdropShown(bar:IsShown())
	ns.log("POWER", "bar", holder:GetWidth(), holder:GetHeight(), "unit", PlayerFrame.unit)
end

local function RequestBar()
	ns.Layout.Request("power", ApplyBar)
end

-- Places and sizes the holder: layout = { point, x, y, width, height }, all present.
function ns.PowerBar.SetLayout(layout)
	ns.Layout.Request("holder", function()
		holder:ClearAllPoints()
		holder:SetPoint(layout.point, UIParent, layout.point, layout.x, layout.y)
		holder:SetSize(layout.width, layout.height)
		ns.log("POWER", "holder", layout.point, layout.x, layout.y, layout.width, layout.height)
	end)
end

ns.OnInitialize(function()
	local bar = PlayerFrame_GetManaBar()
	bar:HookScript("OnShow", function()
		SetBackdropShown(true)
	end)
	bar:HookScript("OnHide", function()
		SetBackdropShown(false)
	end)

	-- Blizzard runs this on every art change and puts the bar back at its spot in the player frame
	-- (now relative to our holder), so ours goes on again right after.
	hooksecurefunc("PlayerFrame_UpdateManaBarVisuals", RequestBar)
	RequestBar()
end)
