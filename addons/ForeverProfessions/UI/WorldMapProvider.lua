local ADDON_NAME, ns = ...

-- Draws known nodes on the world map through Blizzard's own map canvas pipeline, the
-- same way DeathMapDataProvider draws the corpse pin. Nodes are stored per zone map, so
-- they show when that zone is open.

local PIN_TEMPLATE = "ForeverProfessionsWorldPinTemplate"

---@class ForeverProfessionsDataProviderMixin : MapCanvasDataProviderMixin
local DataProviderMixin = CreateFromMixins(MapCanvasDataProviderMixin)

function DataProviderMixin:OnAdded(owningMap)
	MapCanvasDataProviderMixin.OnAdded(self, owningMap)
	ns.callbacks:RegisterCallback("NodesChanged", self.OnNodesChanged, self)
	ns.callbacks:RegisterCallback("OptionChanged", self.RefreshIfShown, self)
	ns.callbacks:RegisterCallback("SkillsChanged", self.OnSkillsChanged, self)
end

function DataProviderMixin:RemoveAllData()
	self:GetMap():RemoveAllPinsByTemplate(PIN_TEMPLATE)
end

-- A pin's size in canvas units at the map's current zoom: SIZE times the pin's scale, which
-- the canvas sets to Lerp(START_SCALE, END_SCALE, zoom percent) times the global pin scale,
-- divided by the canvas scale (MapCanvasPinMixin:ApplyCurrentScale).
local function PinCanvasSize(map)
	local pin = ns.WorldPin
	local zoom = map:HasZoomLevels() and math.min(1, math.max(0, map:GetCanvasZoomPercent())) or 0
	local scale = pin.START_SCALE + (pin.END_SCALE - pin.START_SCALE) * zoom
	local size = pin.SIZE * scale * map:GetGlobalPinScale() / map:GetCanvasScale()
	if ns.dev.enabled then
		local summary = ("canvas scale %.3f, zoom %.2f (scales %s to %s), pin scale %.2f: %.1f canvas units"):format(
			map:GetCanvasScale(),
			zoom,
			map:HasZoomLevels() and ("%.3f"):format(map:GetScaleForMinZoom()) or "-",
			map:HasZoomLevels() and ("%.3f"):format(map:GetScaleForMaxZoom()) or "-",
			map:GetGlobalPinScale(),
			size
		)
		ns.dev:LogChanged("size " .. map:GetMapID(), summary, "CLUSTER", "map", map:GetMapID(), summary)
	end
	return size
end

-- The map's shown nodes as pins, those that would overlap at the current zoom merged
-- (Clusters.lua), and a string that changes when the merging does.
local function BuildPins(map)
	local mapID = map:GetMapID()
	local nodes = {}
	ns.Layers.ForEachShownNode(mapID, function(layer, name, index, x, y, count)
		table.insert(nodes, { layer = layer, name = name, key = name .. index, x = x, y = y, count = count })
	end)
	-- In canvas units, where the pin size is.
	local canvas = map:GetCanvas()
	local width, height = canvas:GetWidth(), canvas:GetHeight()
	local points = {}
	for i, node in ipairs(nodes) do
		points[i] = { x = node.x * width, y = node.y * height }
	end
	local pins = ns.Clusters.Pins(nodes, points, PinCanvasSize(map))

	local signature = { mapID }
	for _, pin in ipairs(pins) do
		table.insert(signature, pin.key .. "=" .. #pin.nodes)
	end
	return pins, table.concat(signature, ";")
end

function DataProviderMixin:RefreshAllData()
	self:RemoveAllData()
	self.signature = nil
	if not ns.Options.Get("showWorldMap") then
		return
	end

	local map = self:GetMap()
	local pins, signature = BuildPins(map)
	self.signature = signature
	if ns.dev.enabled then
		local merged = 0
		for _, pin in ipairs(pins) do
			merged = merged + (#pin.nodes > 1 and 1 or 0)
		end
		local summary = ("%d pins, %d of them merged"):format(#pins, merged)
		ns.dev:LogChanged("pins " .. map:GetMapID(), summary, "CLUSTER", "map", map:GetMapID(), summary)
	end
	for _, pin in ipairs(pins) do
		map:AcquirePin(PIN_TEMPLATE, pin):SetPosition(pin.x, pin.y)
	end
end

-- Zooming changes which pins overlap; the pins are only rebuilt when that changes which merge.
function DataProviderMixin:OnCanvasScaleChanged()
	if not self.signature or not self:GetMap():IsShown() then
		return
	end
	local _, signature = BuildPins(self:GetMap())
	if signature ~= self.signature then
		self:RefreshAllData()
	end
end

-- Maximizing or minimizing the map changes its scale, and so which pins overlap.
function DataProviderMixin:OnCanvasSizeChanged()
	self:RefreshIfShown()
end

-- The canvas refreshes every provider when it is shown, so a hidden map can wait.
function DataProviderMixin:RefreshIfShown()
	if self:GetMap():IsShown() then
		self:RefreshAllData()
	end
end

function DataProviderMixin:OnNodesChanged(mapID)
	if mapID == self:GetMap():GetMapID() then
		self:RefreshIfShown()
	end
end

function DataProviderMixin:OnSkillsChanged()
	for pin in self:GetMap():EnumeratePinsByTemplate(PIN_TEMPLATE) do
		---@cast pin ForeverProfessionsWorldPinMixin
		pin:RefreshSkillState()
	end
end

ns.OnInitialize(function()
	EventUtil.ContinueOnAddOnLoaded("Blizzard_WorldMap", function()
		WorldMapFrame:AddDataProvider(CreateFromMixins(DataProviderMixin))
	end)
end)
