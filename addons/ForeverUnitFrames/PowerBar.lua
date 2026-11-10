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

-- Forever's PlayerFrame_UpdateManaBarVisuals (Blizzard_UnitFrame/Camelot/PlayerFrame.lua) anchors
-- the bar with SetPoint("TOPLEFT", 87, -61), relative to its parent, on every art change.
local BLIZZARD_X, BLIZZARD_Y = 87, -61

-- How far the power bar's mask reaches past the bar on each side (ApplyBar).
local MASK_OUTSET_X, MASK_OUTSET_Y = 16, 6

local holder = CreateFrame("Frame", nil, UIParent)
holder:SetFrameStrata(PlayerFrame:GetFrameStrata())
holder:SetSize(DEFAULTS.width, DEFAULTS.height)
holder:SetPoint(DEFAULTS.point, UIParent, DEFAULTS.point, DEFAULTS.x, DEFAULTS.y)
ns.PowerBar.holder = holder

-- The bar's parent. Its top-left sits (-87, 61) from the holder's, so Blizzard's anchor above lands
-- on the holder's top-left: the anchor ApplyBar sets. A re-layout in combat, when ours has to wait,
-- then leaves the bar in place.
local slot = CreateFrame("Frame", nil, holder)
slot:SetSize(1, 1)
slot:SetPoint("TOPLEFT", holder, "TOPLEFT", -BLIZZARD_X, -BLIZZARD_Y)

-- The cast bar's background and border (Blizzard_UIPanels_Game/Mainline/CastingBarFrame.xml, same
-- offsets), so the bar matches the other free-standing bars. The border sits above the bar's fill.
local background = holder:CreateTexture(nil, "BACKGROUND")
background:SetAtlas("ui-castingbar-background")
background:SetPoint("TOPLEFT", -1, 1)
background:SetPoint("BOTTOMRIGHT", 1, -1)
-- Darker than the cast bar's, so a little rage or energy (dark red, yellow) stands out against it.
background:SetVertexColor(0.35, 0.35, 0.35)

local border = CreateFrame("Frame", nil, holder)
border:SetAllPoints()
border:SetFrameLevel(holder:GetFrameLevel() + 5)
local borderTexture = border:CreateTexture(nil, "OVERLAY")
borderTexture:SetAtlas("ui-castingbar-frame")
borderTexture:SetPoint("TOPLEFT", -2, 2)
borderTexture:SetPoint("BOTTOMRIGHT", 2, -2)

-- Shown only while Blizzard shows the bar and it is in the holder, so a /reload in combat (which
-- leaves the bar in the player frame until combat ends) shows no empty box.
local function SetBackdropShown(shown)
	background:SetShown(shown)
	border:SetShown(shown)
end
SetBackdropShown(false)

local function ApplyBar()
	local bar = PlayerFrame_GetManaBar()
	if bar:GetParent() ~= slot then
		bar:SetParent(slot)
	end
	bar:SetFrameLevel(holder:GetFrameLevel() + 2)
	bar:ClearAllPoints()
	bar:SetPoint("TOPLEFT", slot, "TOPLEFT", BLIZZARD_X, BLIZZARD_Y)
	bar:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT")

	-- The player frame's mask is cut to its art; the cast bar's border frames this bar instead. The
	-- plain bar mask Blizzard uses beside an alternate power bar is stretched well past the bar, so
	-- its soft ends fall outside it and the fill reaches the bar's edges (in game, a 2 px margin
	-- left the left end empty).
	local mask = bar.ManaBarMask
	mask:SetAtlas("Unit_BarMask")
	mask:ClearAllPoints()
	mask:SetPoint("TOPLEFT", bar, "TOPLEFT", -MASK_OUTSET_X, MASK_OUTSET_Y)
	mask:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", MASK_OUTSET_X, -MASK_OUTSET_Y)

	-- The full-power pulse is laid out for the player frame's 124x10 bar from its top-right; centred
	-- on the right end, as the Personal Resource Display does, it fits any height.
	local pulse = bar.FullPowerFrame
	pulse:ClearAllPoints()
	pulse:SetPoint("RIGHT")
	pulse:SetHeight(holder:GetHeight())
	pulse.SpikeFrame:ClearAllPoints()
	pulse.SpikeFrame:SetPoint("RIGHT")
	pulse.PulseFrame:ClearAllPoints()
	pulse.PulseFrame:SetPoint("RIGHT")

	SetBackdropShown(bar:IsShown())
	if ns.dev.enabled then
		ns.log("POWER", "bar", bar:GetWidth(), bar:GetHeight(), "shown", bar:IsShown(), "unit", PlayerFrame.unit)
	end
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
		-- The pulse follows the bar's height.
		ApplyBar()
	end)
end

ns.OnInitialize(function()
	local bar = PlayerFrame_GetManaBar()
	bar:HookScript("OnShow", function(self)
		SetBackdropShown(self:GetParent() == slot)
	end)
	bar:HookScript("OnHide", function()
		SetBackdropShown(false)
	end)

	-- Blizzard runs this on every art change and lays the bar out for the player frame again, so
	-- ours goes on again right after.
	hooksecurefunc("PlayerFrame_UpdateManaBarVisuals", RequestBar)
	RequestBar()
end)
