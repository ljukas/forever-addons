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
-- The width of the tooltip's border art. The bar is inset by it, so it fills the inside of the border,
-- and the backdrop overlaps the tooltip by it, so the two share one border line, as the player frame's
-- name and health bar do.
local BORDER_WIDTH = 4

local bar = GameTooltip.StatusBar

-- The tooltip-style panel the bar sits on, as wide as the tooltip, its top border on the tooltip's
-- bottom border.
local backdrop = CreateFrame("Frame", nil, GameTooltip, "NineSliceCodeTemplate")
NineSliceUtil.ApplyLayout(backdrop, NineSliceUtil.GetLayout(BACKDROP_LAYOUT))
local bgR, bgG, bgB = TOOLTIP_DEFAULT_BACKGROUND_COLOR:GetRGB()
backdrop:SetCenterColor(bgR, bgG, bgB, 1)
backdrop:SetPoint("TOPLEFT", GameTooltip, "BOTTOMLEFT", 0, BORDER_WIDTH)
backdrop:SetPoint("TOPRIGHT", GameTooltip, "BOTTOMRIGHT", 0, BORDER_WIDTH)
backdrop:SetHeight(BAR_HEIGHT + 2 * BORDER_WIDTH)
backdrop:Hide()

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
bar:SetPoint("TOPLEFT", backdrop, "TOPLEFT", BORDER_WIDTH, -BORDER_WIDTH)
bar:SetPoint("TOPRIGHT", backdrop, "TOPRIGHT", -BORDER_WIDTH, -BORDER_WIDTH)
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
