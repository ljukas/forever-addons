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
	return pin.SIZE * scale * map:GetGlobalPinScale() / map:GetCanvasScale()
end

-- A zoom that changes the pin size by less than this share doesn't regroup the pins. Forever's
-- zone maps zoom over a wide range (canvas scale 0.114 to 8.244 in Dun Morogh, seen in game),
-- so the step is relative.
local SIZE_STEP = 0.02

-- A string that changes whenever the merging does: each pin's anchor, shown node and members.
local function Signature(pins)
	local parts = {}
	for _, pin in ipairs(pins) do
		local keys = {}
		for _, node in ipairs(pin.nodes) do
			table.insert(keys, node.key)
		end
		table.insert(parts, pin.name .. ":" .. table.concat(keys, ","))
	end
	return table.concat(parts, ";")
end

-- Draws pins, merged as Clusters.Pins merges them.
function DataProviderMixin:Place(pins, size)
	local map = self:GetMap()
	map:RemoveAllPinsByTemplate(PIN_TEMPLATE)
	self.signature, self.size = Signature(pins), size
	for _, data in ipairs(pins) do
		local pin = map:AcquirePin(PIN_TEMPLATE, data) --[[@as ForeverProfessionsWorldPinMixin]]
		pin:SetPosition(data.x, data.y)
		-- The canvas only scales pins as it zooms, so a pin frame made just now would keep
		-- scale 1 until then.
		pin:ApplyCurrentScale()
	end
	if ns.dev.enabled then
		local merged = 0
		for _, data in ipairs(pins) do
			merged = merged + (#data.nodes > 1 and 1 or 0)
		end
		local summary = ("%d nodes in %d pins, %d merged; pin %.1f canvas units: canvas scale %.3f of %s to %s, pin scale %.2f"):format(
			#self.nodes,
			#pins,
			merged,
			size,
			map:GetCanvasScale(),
			map:HasZoomLevels() and ("%.3f"):format(map:GetScaleForMinZoom()) or "-",
			map:HasZoomLevels() and ("%.3f"):format(map:GetScaleForMaxZoom()) or "-",
			map:GetGlobalPinScale()
		)
		ns.dev:LogChanged("pins " .. map:GetMapID(), summary, "CLUSTER", "map", map:GetMapID(), summary)
	end
end

-- Reads the map's shown nodes and their places in canvas units (where the pin size is), kept
-- until the next refresh: zooming reuses them.
function DataProviderMixin:RefreshAllData()
	self:RemoveAllData()
	self.nodes, self.points, self.signature, self.size = nil, nil, nil, nil
	if not ns.Options.Get("showWorldMap") then
		return
	end

	local map = self:GetMap()
	local nodes, points = {}, {}
	local canvas = map:GetCanvas()
	local width, height = canvas:GetWidth(), canvas:GetHeight()
	ns.Layers.ForEachShownNode(map:GetMapID(), function(layer, name, index, x, y, count)
		table.insert(nodes, { layer = layer, name = name, key = name .. index, x = x, y = y, count = count })
		table.insert(points, { x = x * width, y = y * height })
	end)
	self.nodes, self.points = nodes, points
	local size = PinCanvasSize(map)
	self:Place(ns.Clusters.Pins(nodes, points, size), size)
end

-- Zooming changes which pins overlap. The canvas calls this on every frame of a zoom, so the
-- pins are only regrouped once the size has moved by SIZE_STEP, and only redrawn when that
-- changes the merging.
function DataProviderMixin:OnCanvasScaleChanged()
	if not self.nodes or not self:GetMap():IsShown() then
		return
	end
	local size = PinCanvasSize(self:GetMap())
	if math.abs(size - self.size) < SIZE_STEP * self.size then
		return
	end
	self.size = size
	local pins = ns.Clusters.Pins(self.nodes, self.points, size)
	if Signature(pins) ~= self.signature then
		self:Place(pins, size)
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
