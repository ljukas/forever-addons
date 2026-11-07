local ADDON_NAME, ns = ...

-- Restyles the health bar under unit tooltips (GameTooltip.StatusBar) to match the player frame:
-- the same fill atlas as PlayerFrame's HealthBar, filling a panel with the tooltip's own backdrop
-- (border and background), joined to the tooltip's bottom edge, so the bar reads as part of the tooltip.
--
-- Taint: Blizzard's GameTooltip.lua warns that addon customisations of this bar have tainted its
-- OnUpdate, which then fails on secret health. So this only calls widget methods and hooks with
-- hooksecurefunc and HookScript; it never writes a Lua field on the bar (e.g. lockColor), which
-- Blizzard's HealthBar_OnValueChanged would read while handling the secret health value. The backdrop
-- is a frame of our own, so NineSliceUtil writes its pieces there, not on Blizzard's bar.

local FILL_ATLAS = "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Health" -- PlayerFrame.xml's HealthBar BarTexture
local BACKDROP_LAYOUT = "TooltipDefaultLayout" -- the tooltip's own, as in SharedTooltip_SetBackdropStyle

-- Blizzard's 8px squashes the fill atlas, which is drawn for PlayerFrame's 20px bar.
local BAR_HEIGHT = 12
-- The bar's inset from the backdrop's outer edge, on every side: the visible width of the tooltip's
-- border line, so the bar fills everything inside it with no backdrop showing around the fill.
local BAR_INSET = 2
-- Vertical offset of the backdrop from the tooltip's bottom edge: 0 touches. (Overlapping them to share
-- one border line looked worse in game.)
local BACKDROP_OFFSET = 0

local bar = GameTooltip.StatusBar

-- The tooltip-style panel the bar sits on, as wide as the tooltip, right under it.
local backdrop = CreateFrame("Frame", nil, GameTooltip, "NineSliceCodeTemplate")
NineSliceUtil.ApplyLayout(backdrop, NineSliceUtil.GetLayout(BACKDROP_LAYOUT))
local bgR, bgG, bgB = TOOLTIP_DEFAULT_BACKGROUND_COLOR:GetRGB()
backdrop:SetCenterColor(bgR, bgG, bgB, 1)
backdrop:SetPoint("TOPLEFT", GameTooltip, "BOTTOMLEFT", 0, BACKDROP_OFFSET)
backdrop:SetPoint("TOPRIGHT", GameTooltip, "BOTTOMRIGHT", 0, BACKDROP_OFFSET)
backdrop:SetHeight(BAR_HEIGHT + 2 * BAR_INSET)
backdrop:Hide()

ns.TooltipHealthBar = {}

-- How far the health bar panel hangs below GameTooltip's bottom edge while it shows, else 0. The
-- cursor anchor (Anchor.lua) counts it as part of the tooltip.
function ns.TooltipHealthBar.HeightBelow()
	if not backdrop:IsShown() then
		return 0
	end
	return backdrop:GetHeight() - BACKDROP_OFFSET
end

-- Shown and hidden with the bar (Blizzard shows it for units, hides it in ClearWatch), and kept just
-- below the bar's frame level so the bar draws on top.
bar:HookScript("OnShow", function(self)
	backdrop:SetFrameLevel(math.max(self:GetFrameLevel() - 1, 0))
	backdrop:Show()
end)
bar:HookScript("OnHide", function()
	backdrop:Hide()
end)

bar:ClearAllPoints()
bar:SetPoint("TOPLEFT", backdrop, "TOPLEFT", BAR_INSET, -BAR_INSET)
bar:SetPoint("TOPRIGHT", backdrop, "TOPRIGHT", -BAR_INSET, -BAR_INSET)
bar:SetHeight(BAR_HEIGHT)
bar:SetStatusBarTexture(FILL_ATLAS)

-- HealthBar_OnValueChanged tints the bar green on every change. The atlas has its own colour, so
-- set it back to white, as PlayerFrame does by locking the colour.
local resetting = false
hooksecurefunc(bar, "SetStatusBarColor", function(self)
	if resetting then
		return
	end
	resetting = true
	self:SetStatusBarColor(1, 1, 1)
	resetting = false
end)
bar:SetStatusBarColor(1, 1, 1)

-- Logged on show: at load the bar is hidden and has no size yet.
if ns.dev.enabled then
	bar:HookScript("OnShow", function(self)
		local fill = self:GetStatusBarTexture()
		local r, g, b = fill:GetVertexColor()
		ns.dev:LogOnce(
			"healthbar-shown",
			"HEALTHBAR",
			"fill atlas",
			fill:GetAtlas(),
			"colour",
			r,
			g,
			b,
			"size",
			self:GetWidth(),
			self:GetHeight(),
			"levels bar/backdrop",
			self:GetFrameLevel(),
			backdrop:GetFrameLevel()
		)
	end)
end
