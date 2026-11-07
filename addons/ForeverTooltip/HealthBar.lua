local ADDON_NAME, ns = ...

-- Restyles the health bar under unit tooltips (GameTooltip.StatusBar) to match the player frame:
-- the same fill atlas as PlayerFrame's HealthBar, framed by Blizzard's own tooltip status bar border
-- (the one TooltipStatusBarTemplate uses), on a panel with the tooltip's own backdrop, joined to the
-- tooltip's bottom edge, so the bar reads as part of the tooltip.
--
-- Taint: Blizzard's GameTooltip.lua warns that addon customisations of this bar have tainted its
-- OnUpdate, which then fails on secret health. So this only calls widget methods and hooks with
-- hooksecurefunc and HookScript; it never writes a Lua field on the bar (e.g. lockColor), which
-- Blizzard's HealthBar_OnValueChanged would read while handling the secret health value. The backdrop
-- is a frame of our own, so NineSliceUtil writes its pieces there, not on Blizzard's bar.

local FILL_ATLAS = "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Health" -- PlayerFrame.xml's HealthBar BarTexture
local BORDER_FILE = "Interface\\Tooltips\\UI-StatusBar-Border" -- TooltipStatusBarTemplate's border
local BACKDROP_LAYOUT = "TooltipDefaultLayout" -- the tooltip's own, as in SharedTooltip_SetBackdropStyle

-- TooltipStatusBarTemplate's height, the bar the border file is drawn for. Blizzard's 8px squashes both
-- the border and the fill atlas (drawn for PlayerFrame's 20px bar).
local BAR_HEIGHT = 12
-- Space between the backdrop's outer edge and the bar, on every side.
local BACKDROP_PADDING = 6
-- Vertical offset of the backdrop from the tooltip's bottom edge: 0 touches, negative leaves a gap.
local BACKDROP_OFFSET = 0

local bar = GameTooltip.StatusBar

-- The tooltip-style panel the bar sits on, as wide as the tooltip, right under it.
local backdrop = CreateFrame("Frame", nil, GameTooltip, "NineSliceCodeTemplate")
NineSliceUtil.ApplyLayout(backdrop, NineSliceUtil.GetLayout(BACKDROP_LAYOUT))
local bgR, bgG, bgB = TOOLTIP_DEFAULT_BACKGROUND_COLOR:GetRGB()
backdrop:SetCenterColor(bgR, bgG, bgB, 1)
backdrop:SetPoint("TOPLEFT", GameTooltip, "BOTTOMLEFT", 0, BACKDROP_OFFSET)
backdrop:SetPoint("TOPRIGHT", GameTooltip, "BOTTOMRIGHT", 0, BACKDROP_OFFSET)
backdrop:SetHeight(BAR_HEIGHT + 2 * BACKDROP_PADDING)
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
bar:SetPoint("TOPLEFT", backdrop, "TOPLEFT", BACKDROP_PADDING, -BACKDROP_PADDING)
bar:SetPoint("TOPRIGHT", backdrop, "TOPRIGHT", -BACKDROP_PADDING, -BACKDROP_PADDING)
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
			self:GetHeight(),
			"levels bar/backdrop",
			self:GetFrameLevel(),
			backdrop:GetFrameLevel()
		)
	end)
end
