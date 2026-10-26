local ADDON_NAME, ns = ...

-- The glow at the end of a health bar that says the effects will finish the job: the DoTs
-- kill, or the HoTs heal to full. That's "total >= health", and health is secret, so addon
-- code can't compare them. A StatusBar can: a very long bar with max = health and value =
-- total only fills to its end once total >= health. The glow rides the end of that fill
-- inside a clipping window as wide as the glow, so it's only on screen at 100% (DoesItDie's
-- kill icon trick). The glow is one of Blizzard's over-absorb glows, placed where Blizzard
-- places it (UnitFrame_Initialize: 7px inside the bar's end).
ns.Cue = {}

-- At this length the glow starts to show once the total is within 0.16% of the health.
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

-- side: "LEFT" or "RIGHT" end of the bar; glowTemplate: Blizzard's OverAbsorbGlowTemplate or
-- OverHealAbsorbGlowTemplate (Blizzard_UnitFrame/Shared/UnitFrame.xml).
function ns.Cue.Create(healthBar, mask, side, glowTemplate)
	local cue = CreateFromMixins(CueMixin)

	local window = CreateFrame("Frame", nil, healthBar)
	window:SetUsingParentLevel(true)
	window:SetClipsChildren(true)
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

	local glow = bar:CreateTexture(nil, "ARTWORK", glowTemplate)
	glow:ClearAllPoints()
	glow:SetPoint("TOPRIGHT", bar:GetStatusBarTexture(), "TOPRIGHT")
	glow:SetPoint("BOTTOMRIGHT", bar:GetStatusBarTexture(), "BOTTOMRIGHT")
	glow:SetWidth(GLOW_WIDTH)
	glow:AddMaskTexture(mask)

	window:SetWidth(GLOW_WIDTH)
	if side == "LEFT" then
		window:SetPoint("TOPRIGHT", healthBar, "TOPLEFT", GLOW_INSET, 0)
		window:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMLEFT", GLOW_INSET, 0)
	else
		window:SetPoint("TOPLEFT", healthBar, "TOPRIGHT", -GLOW_INSET, 0)
		window:SetPoint("BOTTOMLEFT", healthBar, "BOTTOMRIGHT", -GLOW_INSET, 0)
	end

	return cue
end
