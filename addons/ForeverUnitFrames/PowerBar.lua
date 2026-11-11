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
	smooth = true,
}

local DEFAULTS = ns.PowerBar.DEFAULTS

-- Forever's PlayerFrame_UpdateManaBarVisuals (Blizzard_UnitFrame/Camelot/PlayerFrame.lua) anchors
-- the bar with SetPoint("TOPLEFT", 87, -61), relative to its parent, on every art change.
local BLIZZARD_X, BLIZZARD_Y = 87, -61

-- How far the power bar's mask reaches past the bar on each side (ApplyBar), so its soft ends fall
-- outside the bar. Tunable by the dev probe (/fufart powermask <left> <right> <y>).
ns.PowerBar.maskOutset = { left = 16, right = 16, y = 6 }

-- How far the bar itself reaches past the holder, under the border: in game the fill's art (made
-- for the player frame) started short of the border's left edge, and a full mana bar stopped short
-- of its right edge (2026-11-10/11). Tunable by the dev probe (/fufart powerbar <left> <right>).
ns.PowerBar.barOutset = { left = 2, right = 0 }

-- How far the fill reaches past Blizzard's bar on the right: a full bar's art needs 3 px more to
-- meet the border, but Blizzard's spend flash, drawn on its own bar, ran past the border when the
-- bar itself was widened that far (2026-11-11). Tunable by the dev probe (/fufart powerfill <right>).
ns.PowerBar.fillOutset = { right = 3 }

local holder = CreateFrame("Frame", nil, UIParent)
holder:SetFrameStrata(PlayerFrame:GetFrameStrata())
holder:SetSize(DEFAULTS.width, DEFAULTS.height)
holder:SetPoint(DEFAULTS.point, UIParent, DEFAULTS.point, DEFAULTS.x, DEFAULTS.y)
ns.PowerBar.holder = holder

-- The bar's parent. Its top-left sits (-87, 61) from the bar's top-left, so Blizzard's anchor above
-- lands where ApplyBar puts the bar. A re-layout in combat, when ours has to wait, then leaves the
-- bar in place.
local slot = CreateFrame("Frame", nil, holder)
slot:SetSize(1, 1)

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

-- The fill players see. Blizzard's bar snaps to each new value; this one eases toward it when the
-- layout asks for smooth fills. It copies the values Blizzard sets (secret, but a status bar takes
-- them as they are) and its art, and Blizzard's own fill is made transparent. Blizzard's text,
-- full-power pulse and spend feedback stay on its bar, above this one.
local fill = CreateFrame("StatusBar", nil, holder)
fill:SetFrameLevel(holder:GetFrameLevel() + 1)
local interpolation = Enum.StatusBarInterpolation.ExponentialEaseOut

-- The alpha Blizzard gives its fill (half when dead or a ghost), which goes on this one instead.
local fillAlpha = 1

-- Shown only while Blizzard shows the bar and it is in the holder, so a /reload in combat (which
-- leaves the bar in the player frame until combat ends) shows no empty box.
local function SetBackdropShown(shown)
	background:SetShown(shown)
	border:SetShown(shown)
	fill:SetShown(shown)
end
SetBackdropShown(false)

local function ApplyBar()
	local bar = PlayerFrame_GetManaBar()
	if bar:GetParent() ~= slot then
		bar:SetParent(slot)
	end
	bar:SetFrameLevel(holder:GetFrameLevel() + 2)
	local barOutset = ns.PowerBar.barOutset
	slot:ClearAllPoints()
	slot:SetPoint("TOPLEFT", holder, "TOPLEFT", -BLIZZARD_X - barOutset.left, -BLIZZARD_Y)
	bar:ClearAllPoints()
	bar:SetPoint("TOPLEFT", slot, "TOPLEFT", BLIZZARD_X, BLIZZARD_Y)
	bar:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", barOutset.right, 0)

	-- The player frame's mask is cut to its art; the cast bar's border frames this bar instead. The
	-- plain bar mask Blizzard uses beside an alternate power bar is stretched well past the bar, so
	-- its soft ends fall outside it and the fill reaches the bar's edges (in game, a 2 px margin
	-- left the left end empty).
	local outset = ns.PowerBar.maskOutset
	local mask = bar.ManaBarMask
	mask:SetAtlas("Unit_BarMask")
	mask:ClearAllPoints()
	mask:SetPoint("TOPLEFT", bar, "TOPLEFT", -outset.left, outset.y)
	mask:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", outset.right, -outset.y)

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

	fill:ClearAllPoints()
	fill:SetPoint("TOPLEFT", bar)
	fill:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", ns.PowerBar.fillOutset.right, 0)

	SetBackdropShown(bar:IsShown())
	if ns.dev.enabled then
		ns.log("POWER", "bar", bar:GetWidth(), bar:GetHeight(), "shown", bar:IsShown(), "unit", PlayerFrame.unit)
	end
end

local function RequestBar()
	ns.Layout.Request("power", ApplyBar)
end
ns.PowerBar.Request = RequestBar

-- Copies Blizzard's art (UnitFrameManaBar_UpdateType: an atlas per power type, a colour, and
-- desaturated at half alpha when dead) onto the fill, and keeps Blizzard's fill transparent.
local function SyncArt()
	local bar = PlayerFrame_GetManaBar()
	local source = bar:GetStatusBarTexture()
	if not source then
		return
	end
	if source:GetAlpha() > 0 then
		fillAlpha = source:GetAlpha()
		source:SetAlpha(0)
	end
	local atlas = source:GetAtlas()
	if atlas then
		fill:SetStatusBarTexture(atlas)
	else
		fill:SetStatusBarTexture(source:GetTexture())
	end
	fill:SetStatusBarColor(bar:GetStatusBarColor())
	local texture = fill:GetStatusBarTexture()
	texture:SetDesaturated(source:IsDesaturated())
	texture:SetAlpha(fillAlpha)
end

local function SyncValues()
	local bar = PlayerFrame_GetManaBar()
	fill:SetMinMaxValues(bar:GetMinMaxValues())
	fill:SetValue(bar:GetValue())
end

-- Smooth fills ease toward each new value; otherwise the fill snaps to it, as Blizzard's does.
local function SetSmooth(smooth)
	interpolation = smooth and Enum.StatusBarInterpolation.ExponentialEaseOut or Enum.StatusBarInterpolation.Immediate
	if not smooth then
		fill:SetToTargetValue()
	end
end

-- Places and sizes the holder: layout = { point, x, y, width, height, smooth }, all present.
function ns.PowerBar.SetLayout(layout)
	SetSmooth(layout.smooth)
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

	hooksecurefunc(bar, "SetMinMaxValues", function(_, minValue, maxValue)
		fill:SetMinMaxValues(minValue, maxValue)
	end)
	hooksecurefunc(bar, "SetValue", function(_, value)
		fill:SetValue(value, interpolation)
	end)
	hooksecurefunc(bar, "SetStatusBarTexture", SyncArt)
	hooksecurefunc(bar, "SetStatusBarColor", SyncArt)
	-- Sets the fill's alpha and desaturation after its texture and colour.
	hooksecurefunc("UnitFrameManaBar_UpdateType", function(manaBar)
		if manaBar == bar then
			SyncArt()
		end
	end)
	SyncArt()
	SyncValues()

	-- Blizzard runs this on every art change and lays the bar out for the player frame again, so
	-- ours goes on again right after.
	hooksecurefunc("PlayerFrame_UpdateManaBarVisuals", RequestBar)
	RequestBar()
end)
