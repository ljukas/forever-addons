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

local border = bar:CreateTexture(nil, "OVERLAY")
border:SetTexture(BORDER_FILE)
border:SetPoint("TOPLEFT", -2, 2)
border:SetPoint("BOTTOMRIGHT", 2, -2)

if ns.dev.enabled then
	local fill = bar:GetStatusBarTexture()
	ns.log("HEALTHBAR", "fill atlas", fill and fill:GetAtlas(), "size", bar:GetWidth(), bar:GetHeight())
end
