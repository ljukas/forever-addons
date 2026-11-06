local ADDON_NAME, ns = ...

-- Draws an icon on each marker (Markers.lua), every frame, from the player's current position
-- and facing, so the icons move with the minimap exactly; scans only add and drop markers.

-- The tracking icons, for a herb or ore whose item has no icon (Data/Nodes.lua). Chests use
-- Find Treasure's icon instead (TreasureIcon).
local ATLASES = {
	herb = "professions_tracking_herb",
	ore = "professions_tracking_ore",
}
-- Item icons carry a dark border; Blizzard crops it off round item icons the same way.
local ITEM_INSET = 0.08

-- Seconds before asking the client again for an item icon it couldn't give.
local ICON_RETRY = 1

local itemIcons = {} -- [itemID] = icon file, once the client gave one
local iconRetryAt = {} -- [itemID] = GetTime() after which to ask again

-- The item's icon file, or nil: from the client's own item data, so no server query is needed.
-- Icons are drawn every frame, so each is asked for once and kept.
local function ItemIcon(item)
	if not item then
		return nil
	end
	local icon = itemIcons[item]
	if icon then
		return icon
	end
	local now = GetTime()
	if iconRetryAt[item] and now < iconRetryAt[item] then
		return nil
	end
	icon = C_Item.GetItemIconByID(item)
	if icon and not issecretvalue(icon) then
		itemIcons[item] = icon
		return icon
	end
	iconRetryAt[item] = now + ICON_RETRY
end

-- The ring is about 2.5 times the icon, and its hole sits up and to the left of the texture's
-- middle: Blizzard centers this ring at (+12, -13) from the icon for a 64 px ring
-- (Blizzard_HelpPlate.xml), so it is offset by that share of its size.
local RING_SCALE = 2.5
local RING_X, RING_Y = 12 / 64, -13 / 64
-- The dark disc under the icon, as on Blizzard's tracking button (25 px under a 20 px icon).
local BACKGROUND_SCALE = 1.25
-- An icon over the player's own arrow (which the game draws under addon art) is see-through: the
-- ring and the arrow overlap out to about this many icon sizes from the minimap's center.
local OVER_PLAYER = 1.75
local OVER_PLAYER_ALPHA = 0.35
-- Pixels kept clear inside the minimap's edge, where its gold frame overlaps the map (to tune
-- at launch).
local EDGE_MARGIN = 4
-- A node in a cave: dimmed as well as gray.
local CAVE_SHADE = 0.6
-- Icon size in minimap pixels at an icon scale of 100%: an estimate until launch, small enough
-- to leave the game's up and down arrows visible.
local BASE_SIZE = 9

---@class ForeverMinimapNodeIconMixin : Frame
---@field Background Texture
---@field Icon Texture
---@field Ring Texture
---@field kind string?
---@field item number?
---@field icon number?
---@field gray boolean?
---@field size number?
ForeverMinimapNodeIconMixin = {}

-- Whole pixels: Blizzard sizes and places these textures on the pixel grid, and a fractional
-- ring would wobble against the icon as it moves.
local function Round(value)
	return math.floor(value + 0.5)
end

-- A chest gives no one item: it gets Find Treasure's own icon from the tracking menu, as square
-- as an item icon.
-- The spell's icon is the fallback, asked for once and kept, and retried no more often than
-- item icons are.
local treasureSpellIcon, treasureRetryAt
local function TreasureIcon()
	local icon = ns.Tracking.TreasureTexture() or treasureSpellIcon
	if icon then
		return icon
	end
	local now = GetTime()
	if treasureRetryAt and now < treasureRetryAt then
		return nil
	end
	icon = C_Spell.GetSpellTexture(ns.Tracking.FIND_TREASURE)
	if icon and not issecretvalue(icon) then
		treasureSpellIcon = icon
		return icon
	end
	treasureRetryAt = now + ICON_RETRY
end

function ForeverMinimapNodeIconMixin:SetNode(kind, item, gray, size)
	-- An item whose icon the client couldn't give yet is tried again (ItemIcon's retry).
	local icon
	if kind == "treasure" then
		icon = TreasureIcon()
	else
		icon = ItemIcon(item)
	end
	if self.kind ~= kind or self.item ~= item or self.icon ~= icon then
		self.kind, self.item, self.icon = kind, item, icon
		if icon then
			self.Icon:SetTexture(icon)
			self.Icon:SetTexCoord(ITEM_INSET, 1 - ITEM_INSET, ITEM_INSET, 1 - ITEM_INSET)
		else
			self.Icon:SetTexCoord(0, 1, 0, 1) -- SetAtlas's own reset is not documented
			if ATLASES[kind] then
				self.Icon:SetAtlas(ATLASES[kind])
			else
				self.Icon:SetTexture(nil) -- a chest before any treasure icon could be read: the ring alone
			end
		end
	end
	if self.size ~= size then
		self.size = size
		self:SetSize(size, size)
		local ring = Round(size * RING_SCALE)
		self.Ring:SetSize(ring, ring)
		self.Ring:ClearAllPoints()
		self.Ring:SetPoint("CENTER", self, "CENTER", Round(RING_X * ring), Round(RING_Y * ring))
		local background = Round(size * BACKGROUND_SCALE)
		self.Background:SetSize(background, background)
		self.Background:ClearAllPoints()
		self.Background:SetPoint("CENTER", self, "CENTER")
	end
	if self.gray ~= gray then
		self.gray = gray
		local shade = gray and CAVE_SHADE or 1
		for _, texture in ipairs({ self.Icon, self.Ring }) do
			texture:SetDesaturated(gray)
			texture:SetVertexColor(shade, shade, shade)
		end
	end
end

-- The icons follow the minimap's icon scale (Edit Mode → Minimap → Icon Scale), as the game's
-- own minimap icons do. The client has no getter for it, so it is kept from the calls to
-- Minimap:SetIconScale: Edit Mode makes one on its first layout apply (login, /reload), and
-- later whenever the scale changes: the slider, a revert, a layout with another scale
-- (EditModeMinimapSystemMixin, Blizzard_EditMode).
-- A value we can't use (secret, or not a positive number) leaves the last one in place.
local iconScale = 1

local function SetIconScale(scale, source)
	if issecretvalue(scale) or type(scale) ~= "number" or scale <= 0 then
		if ns.dev.enabled then
			local got = issecretvalue(scale) and "secret" or type(scale) .. " " .. tostring(scale)
			ns.log("SCALE", "unusable icon scale from", source, got, "kept", iconScale)
		end
		return
	end
	iconScale = scale
	ns.log("SCALE", "icon scale", scale, "from", source)
end

-- Before the first call, Edit Mode's minimap setting may already hold the scale (as the percent
-- its slider shows; it reads 0 until Edit Mode has set the minimap up). An unusable value is
-- passed on as it is, so SetIconScale logs and drops it.
if MinimapCluster and MinimapCluster.GetSettingValue and Enum.EditModeMinimapSetting then
	local percent = MinimapCluster:GetSettingValue(Enum.EditModeMinimapSetting.IconScale)
	local usable = not issecretvalue(percent) and type(percent) == "number" and percent > 0
	SetIconScale(usable and percent / 100 or percent, "edit mode")
end

hooksecurefunc(Minimap, "SetIconScale", function(_, scale)
	SetIconScale(scale, "SetIconScale")
end)

local container = CreateFrame("Frame", nil, Minimap)
container:SetAllPoints()

local icons = {}

local function HideFrom(first)
	for i = first, #icons do
		icons[i]:Hide()
	end
end

local function Draw()
	if ns.Markers.IsEmpty() then
		HideFrom(1)
		return
	end
	local width = Minimap:GetWidth()
	if not width or issecretvalue(width) then
		HideFrom(1)
		return
	end
	local view = ns.Scanner.CurrentView()
	local size = math.max(1, Round(BASE_SIZE * iconScale))
	-- Whole icons only: one past the minimap's round edge isn't drawn.
	local maxDistance = width / 2 - 0.75 * size - EDGE_MARGIN
	local shown = 0
	for _, marker in ns.Markers.Enumerate() do
		local ox, oy = marker.ox, marker.oy
		if marker.mapX then
			ox, oy = nil, nil
			if view and view.mapID == marker.mapID then
				ox, oy = ns.Anchor.ToMinimap(marker.mapX, marker.mapY, view)
			end
		end
		local distance = ox and math.sqrt(ox * ox + oy * oy)
		if distance and distance <= maxDistance then
			shown = shown + 1
			local icon = icons[shown]
			if not icon then
				icon = CreateFrame("Frame", nil, container, "ForeverMinimapNodeIconTemplate") --[[@as ForeverMinimapNodeIconMixin]]
				icons[shown] = icon
			end
			icon:SetNode(marker.kind, marker.item, marker.gray, size)
			icon:SetPoint("CENTER", Minimap, "CENTER", ox, oy)
			icon:SetAlpha(distance < OVER_PLAYER * size and OVER_PLAYER_ALPHA or 1)
			icon:Show()
		end
	end
	HideFrom(shown + 1)
end

-- Only runs while the minimap is shown, since the container is its child.
container:SetScript("OnUpdate", Draw)
