local ADDON_NAME, ns = ...

-- A cue says the effects will finish the job: the DoTs kill, or the HoTs heal to full. That's
-- "total >= health", and health is secret, so addon code can't compare them. A StatusBar can:
-- a very long bar with max = health and value = total only fills to its end once
-- total >= health. A texture (the "rider") rides the end of that fill inside a clipping window
-- as wide as the rider, so it's only on screen at 100% (DoesItDie's kill icon trick).
--
-- Shapes:
--   CreateBarEnd  one of Blizzard's over-absorb glows at an end of the health bar, placed where
--                 Blizzard places it (UnitFrame_Initialize: 7px inside the bar's end)
ns.Cue = {}

-- At this length a rider w px wide starts to show once the total is within w/LONG_BAR_WIDTH of
-- the health (0.16% for the 16px glow).
local LONG_BAR_WIDTH = 10000
-- The glow templates' size, and how far into the bar Blizzard puts them.
local GLOW_WIDTH = 16
local GLOW_INSET = 7

---@class ForeverCombatCue
---@field window Frame
---@field bar StatusBar
local CueMixin = {}

-- maxValue may be secret.
function CueMixin:Set(maxValue, total)
	self.bar:SetMinMaxValues(0, maxValue)
	self.bar:SetValue(total)
	self.window:Show()
end

function CueMixin:Hide()
	self.window:Hide()
end

-- The clipping window (riderWidth wide, anchored by the caller) and the long bar inside it.
-- The caller anchors a rider texture with AttachRider.
local function NewCue(parent, riderWidth)
	local cue = CreateFromMixins(CueMixin)

	local window = CreateFrame("Frame", nil, parent)
	window:SetUsingParentLevel(true)
	window:SetClipsChildren(true)
	window:SetWidth(riderWidth)
	window:Hide()
	cue.window = window

	-- The bar's own fill is invisible; only its end matters.
	local bar = CreateFrame("StatusBar", nil, window)
	bar:SetUsingParentLevel(true)
	bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
	bar:SetStatusBarColor(0, 0, 0, 0)
	bar:SetWidth(LONG_BAR_WIDTH)
	bar:SetPoint("TOPRIGHT", window, "TOPRIGHT")
	bar:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT")
	cue.bar = bar

	return cue
end

-- Rides texture on the end of the cue's fill.
local function AttachRider(cue, texture, width)
	local fill = cue.bar:GetStatusBarTexture()
	texture:ClearAllPoints()
	texture:SetPoint("TOPRIGHT", fill, "TOPRIGHT")
	texture:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT")
	texture:SetWidth(width)
end

-- side: "LEFT" or "RIGHT" end of the bar; glowTemplate: Blizzard's OverAbsorbGlowTemplate or
-- OverHealAbsorbGlowTemplate (Blizzard_UnitFrame/Shared/UnitFrame.xml).
function ns.Cue.CreateBarEnd(healthBar, mask, side, glowTemplate)
	local cue = NewCue(healthBar, GLOW_WIDTH)

	local glow = cue.bar:CreateTexture(nil, "ARTWORK", glowTemplate)
	AttachRider(cue, glow, GLOW_WIDTH)
	glow:AddMaskTexture(mask)

	local window = cue.window
	if side == "LEFT" then
		window:SetPoint("TOPRIGHT", healthBar, "TOPLEFT", GLOW_INSET, 0)
		window:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMLEFT", GLOW_INSET, 0)
	else
		window:SetPoint("TOPLEFT", healthBar, "TOPRIGHT", -GLOW_INSET, 0)
		window:SetPoint("BOTTOMLEFT", healthBar, "BOTTOMRIGHT", -GLOW_INSET, 0)
	end

	return cue
end
