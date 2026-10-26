local ADDON_NAME, ns = ...

-- Shared by the world map and minimap pins (UI/Pin.xml).
---@class ForeverMapPinMixin : Frame
---@field Icon Texture
---@field Border Texture
---@field nodeName string
---@field timesGathered number
ForeverMapPinMixin = {}

function ForeverMapPinMixin:SetNode(layer, nodeName, timesGathered)
	self.nodeName = nodeName
	self.timesGathered = timesGathered
	self.Icon:SetAtlas(layer.atlas)
	self:RefreshSkillState()
end

-- Too low to gather: the gold ring turns red and the icon greys out. Pins are pooled,
-- so the normal state is always reapplied too.
function ForeverMapPinMixin:RefreshSkillState()
	local tooLow = ForeverProfessions.IsTooLow(self.nodeName)
	self.Icon:SetDesaturated(tooLow)
	self.Border:SetDesaturated(tooLow)
	self.Border:SetVertexColor((tooLow and RED_FONT_COLOR or WHITE_FONT_COLOR):GetRGB())
end

-- The minimap's own tooltip follows the cursor, so minimap pins do the same.
function ForeverMapPinMixin:GetTooltipAnchor()
	return "ANCHOR_CURSOR"
end

function ForeverMapPinMixin:OnMouseEnter()
	ns.Tooltip.ShowNode(GameTooltip, self, self:GetTooltipAnchor(), self.nodeName, self.timesGathered)
end

function ForeverMapPinMixin:OnMouseLeave()
	GameTooltip:Hide()
end

-- A pin released from its pool while hovered never gets OnMouseLeave.
function ForeverMapPinMixin:HideOwnedTooltip()
	if GameTooltip:IsOwned(self) then
		GameTooltip:Hide()
	end
end

---@class ForeverMapWorldPinMixin : ForeverMapPinMixin, MapCanvasPinMixin
ForeverMapWorldPinMixin = CreateFromMixins(MapCanvasPinMixin, ForeverMapPinMixin)

function ForeverMapWorldPinMixin:OnLoad()
	self:SetScalingLimits(1, 0.5, 0.75)
end

-- Arguments after the template name in AcquirePin.
function ForeverMapWorldPinMixin:OnAcquired(layer, nodeName, timesGathered)
	-- Alongside archaeology dig sites, below quests, POIs and vignettes.
	self:UseFrameLevelType("PIN_FRAME_LEVEL_DIG_SITE")
	self:SetNode(layer, nodeName, timesGathered)
end

function ForeverMapWorldPinMixin:OnReleased()
	self:HideOwnedTooltip()
	MapCanvasPinMixin.OnReleased(self)
end

-- The map canvas calls this on pins under the gamepad cursor. The highlight here is a
-- plain HIGHLIGHT layer, so there is nothing to lock.
function ForeverMapWorldPinMixin:SetHighlightLocked() end

-- Like Blizzard's corpse pin: open the tooltip on the side facing the map's centre.
function ForeverMapWorldPinMixin:GetTooltipAnchor()
	local x = self:GetCenter()
	local parentX = self:GetParent():GetCenter()
	return x > parentX and "ANCHOR_LEFT" or "ANCHOR_RIGHT"
end
