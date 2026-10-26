local ADDON_NAME, ns = ...

-- Draws an icon on each marker (Markers.lua), every frame, from the player's current position
-- and facing, so the icons move with the minimap exactly; scans only add and drop markers.

local ATLASES = {
	herb = "professions_tracking_herb",
	ore = "professions_tracking_ore",
}

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

---@class ForeverMapNodeIconMixin : Frame
---@field Background Texture
---@field Icon Texture
---@field Ring Texture
---@field kind string?
---@field gray boolean?
---@field size number?
ForeverMapNodeIconMixin = {}

-- Whole pixels: Blizzard sizes and places these textures on the pixel grid, and a fractional
-- ring would wobble against the icon as it moves.
local function Round(value)
	return math.floor(value + 0.5)
end

function ForeverMapNodeIconMixin:SetNode(kind, gray, size)
	if self.kind ~= kind then
		self.kind = kind
		self.Icon:SetAtlas(ATLASES[kind])
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
	local size = ns.Options.Get("nodeIconSize")
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
				icon = CreateFrame("Frame", nil, container, "ForeverMapNodeIconTemplate") --[[@as ForeverMapNodeIconMixin]]
				icons[shown] = icon
			end
			icon:SetNode(marker.kind, marker.gray, size)
			icon:SetPoint("CENTER", Minimap, "CENTER", ox, oy)
			icon:SetAlpha(distance < OVER_PLAYER * size and OVER_PLAYER_ALPHA or 1)
			icon:Show()
		end
	end
	HideFrom(shown + 1)
end

-- Only runs while the minimap is shown, since the container is its child.
container:SetScript("OnUpdate", Draw)
