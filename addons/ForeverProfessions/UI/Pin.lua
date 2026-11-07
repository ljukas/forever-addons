local ADDON_NAME, ns = ...

-- Shared by the world map and minimap pins (UI/Pin.xml). A pin stands for one node, or for
-- several whose pins would overlap (Clusters.lua): it shows the icon of the node most of them
-- are, with their number.
---@class ForeverProfessionsPinMixin : Frame
---@field Icon Texture
---@field Border Texture
---@field Count FontString
---@field nodes ForeverProfessionsPinNode[] the nodes the pin stands for
---@field shownIcon (number|string)? the item icon or atlas the pin shows
ForeverProfessionsPinMixin = {}

---@class ForeverProfessionsPinNode
---@field layer table the node's layer (Layers.lua)
---@field name string
---@field key string unique per node on its map
---@field x number
---@field y number
---@field count number times gathered

---@class ForeverProfessionsPinData
---@field layer table
---@field name string the node shown
---@field key string
---@field x number
---@field y number
---@field nodes ForeverProfessionsPinNode[]

-- Item icons carry a dark border; Blizzard crops it off round item icons the same way.
local ITEM_INSET = 0.08

local itemIcons = {} -- [itemID] = icon file, once the client gave one

-- The icon of the item the node gives (Data/GatherNodes.lua), or nil: from the client's own
-- item data, so no server query is needed. Kept once given, since minimap pins are set again
-- whenever the player moves; one the client couldn't give yet is asked for on the next set.
local function NodeIcon(nodeName)
	local node = ns.GatherNodes[nodeName]
	local item = node and node.item
	if not item then
		return nil
	end
	local icon = itemIcons[item]
	if not icon then
		icon = C_Item.GetItemIconByID(item)
		if not icon or issecretvalue(icon) then
			return nil
		end
		itemIcons[item] = icon
	end
	return icon
end

---@param pin ForeverProfessionsPinData
function ForeverProfessionsPinMixin:SetPin(pin)
	self.nodes = pin.nodes
	local count = #pin.nodes
	self.Count:SetShown(count > 1)
	if count > 1 then
		self.Count:SetText(tostring(count))
	end
	-- A node with no item, or an item whose icon the client can't give, keeps the tracking icon.
	-- Minimap pins are set again every update while the player moves: only a change retextures.
	local icon = NodeIcon(pin.name)
	local shown = icon or pin.layer.atlas
	if self.shownIcon ~= shown then
		self.shownIcon = shown
		if icon then
			self.Icon:SetTexture(icon)
			self.Icon:SetTexCoord(ITEM_INSET, 1 - ITEM_INSET, ITEM_INSET, 1 - ITEM_INSET)
		else
			self.Icon:SetTexCoord(0, 1, 0, 1) -- pins are pooled; SetAtlas's own reset is not documented
			self.Icon:SetAtlas(pin.layer.atlas)
		end
	end
	self:RefreshSkillState()
	-- A hovered minimap pin keeps its frame while its merged nodes change.
	if GameTooltip:IsOwned(self) then
		self:OnMouseEnter()
	end
end

-- Too low to gather any of its nodes: the gold ring turns red and the icon greys out. Pins are
-- pooled, so the normal state is always reapplied too.
function ForeverProfessionsPinMixin:RefreshSkillState()
	local tooLow = true
	for _, node in ipairs(self.nodes) do
		if not ns.Professions.IsTooLow(node.name) then
			tooLow = false
			break
		end
	end
	self.Icon:SetDesaturated(tooLow)
	self.Border:SetDesaturated(tooLow)
	self.Border:SetVertexColor((tooLow and RED_FONT_COLOR or WHITE_FONT_COLOR):GetRGB())
end

-- The minimap's own tooltip follows the cursor, so minimap pins do the same.
function ForeverProfessionsPinMixin:GetTooltipAnchor()
	return "ANCHOR_CURSOR"
end

function ForeverProfessionsPinMixin:OnMouseEnter()
	ns.Tooltip.ShowNodes(GameTooltip, self, self:GetTooltipAnchor(), self.nodes)
end

function ForeverProfessionsPinMixin:OnMouseLeave()
	GameTooltip:Hide()
end

-- A pin released from its pool while hovered never gets OnMouseLeave.
function ForeverProfessionsPinMixin:HideOwnedTooltip()
	if GameTooltip:IsOwned(self) then
		GameTooltip:Hide()
	end
end

---@class ForeverProfessionsWorldPinMixin : ForeverProfessionsPinMixin, MapCanvasPinMixin
ForeverProfessionsWorldPinMixin = CreateFromMixins(MapCanvasPinMixin, ForeverProfessionsPinMixin)

-- World pin size and scaling, shared with UI/WorldMapProvider.lua, which merges pins that would
-- overlap at the map's current zoom.
ns.WorldPin = {
	SIZE = 32, -- the template's size
	START_SCALE = 0.5, -- the pin's scale fully zoomed out, relative to the map
	END_SCALE = 0.75, -- and fully zoomed in
}

function ForeverProfessionsWorldPinMixin:OnLoad()
	self:SetScalingLimits(1, ns.WorldPin.START_SCALE, ns.WorldPin.END_SCALE)
end

-- Arguments after the template name in AcquirePin.
---@param pin ForeverProfessionsPinData
function ForeverProfessionsWorldPinMixin:OnAcquired(pin)
	-- Alongside archaeology dig sites, below quests, POIs and vignettes.
	self:UseFrameLevelType("PIN_FRAME_LEVEL_DIG_SITE")
	self:SetPin(pin)
end

function ForeverProfessionsWorldPinMixin:OnReleased()
	self:HideOwnedTooltip()
	MapCanvasPinMixin.OnReleased(self)
end

-- The map canvas calls this on pins under the gamepad cursor. The highlight here is a
-- plain HIGHLIGHT layer, so there is nothing to lock.
function ForeverProfessionsWorldPinMixin:SetHighlightLocked() end

-- Like Blizzard's corpse pin: open the tooltip on the side facing the map's centre.
function ForeverProfessionsWorldPinMixin:GetTooltipAnchor()
	local x = self:GetCenter()
	local parentX = self:GetParent():GetCenter()
	return x > parentX and "ANCHOR_LEFT" or "ANCHOR_RIGHT"
end
