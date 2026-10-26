local ADDON_NAME, ns = ...

-- Width of the heal absorb bar's edge shadow (Blizzard anchors its right shadow 8px in).
local EDGE_WIDTH = 8

---@class ForeverCombatSegmentMixin : StatusBar
---@field Fill Texture
---@field EdgeShadow Texture
ForeverCombatSegmentMixin = {}

-- Once per segment. Draws one sublevel above the health fill like Blizzard's segments
-- (StatusBarOverlaySegmentMixin:Initialize), clipped to the health bar's rounded mask.
-- reverse segments fill leftward from their right edge. The shadow sits at the fill's left
-- end, where the next segment of a stack starts.
function ForeverCombatSegmentMixin:Init(healthBar, mask, color, reverse)
	local layer, subLevel = healthBar:GetStatusBarTexture():GetDrawLayer()
	self.Fill:SetDrawLayer(layer, subLevel + 1)
	self.EdgeShadow:SetDrawLayer(layer, subLevel + 2)
	self.Fill:AddMaskTexture(mask)
	self.EdgeShadow:AddMaskTexture(mask)
	self:SetStatusBarColor(color:GetRGBA())
	self:SetReverseFill(reverse)

	self.EdgeShadow:SetPoint("TOPLEFT", self.Fill, "TOPLEFT")
	self.EdgeShadow:SetPoint("BOTTOMLEFT", self.Fill, "BOTTOMLEFT")
	self.EdgeShadow:SetWidth(EDGE_WIDTH)
end

-- maxHealth may be secret; amount is the effect's remaining damage or healing.
function ForeverCombatSegmentMixin:SetAmount(maxHealth, amount)
	self:SetMinMaxValues(0, maxHealth)
	self:SetValue(amount)
end
