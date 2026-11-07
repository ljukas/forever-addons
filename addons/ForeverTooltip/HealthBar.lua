local ADDON_NAME, ns = ...

-- Restyles the health bar under unit tooltips (GameTooltip.StatusBar) to match the player frame:
-- the same fill atlas as PlayerFrame's HealthBar, framed by Blizzard's own tooltip status bar border
-- (the one TooltipStatusBarTemplate uses), so the bar reads as part of the tooltip.
--
-- Taint: Blizzard's GameTooltip.lua warns that addon customisations of this bar have tainted its
-- OnUpdate, which then fails on secret health. So this only calls widget methods and hooks with
-- hooksecurefunc; it never writes a Lua field on the bar (e.g. lockColor), which Blizzard's
-- HealthBar_OnValueChanged would read while handling the secret health value.

local FILL_ATLAS = "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Health" -- PlayerFrame.xml's HealthBar BarTexture
local BORDER_FILE = "Interface\\Tooltips\\UI-StatusBar-Border" -- TooltipStatusBarTemplate's border

local bar = GameTooltip.StatusBar

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

-- The border file is drawn for a 128px bar (TooltipStatusBarTemplate). Sliced at the ends, its end caps
-- keep their size on wide tooltips and only the middle stretches. Wider caps cover the fill's ends, as
-- the border sits only 2px outside the bar. No top/bottom slice: the height stretches as Blizzard's does.
-- Margins are in the file's pixels.
local BORDER_CAP = 3

local border = bar:CreateTexture(nil, "OVERLAY")
border:SetTexture(BORDER_FILE)
border:SetTextureSliceMargins(BORDER_CAP, 0, BORDER_CAP, 0)
border:SetPoint("TOPLEFT", -2, 2)
border:SetPoint("BOTTOMRIGHT", 2, -2)

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
			self:GetHeight()
		)
	end)
end
