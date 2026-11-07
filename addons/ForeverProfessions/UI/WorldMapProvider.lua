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

-- A pin's largest size in canvas units. A pin is SIZE times its scale, which goes from
-- START_SCALE to END_SCALE divided by the canvas scale as the map zooms in
-- (MapCanvasPinMixin:ApplyCurrentScale). Against the map that is largest at one end of the
-- zoom range, fully out or fully in depending on the zone's zoom levels, so both ends are
-- taken. The zoom levels exist once the map has laid out a zone; until then, the current scale.
local function PinCanvasSize(map)
	local pin = ns.WorldPin
	local scale
	if map:HasZoomLevels() then
		local minZoom, maxZoom = map:GetScaleForMinZoom(), map:GetScaleForMaxZoom()
		if minZoom > 0 and maxZoom > 0 then
			scale = math.max(pin.START_SCALE / minZoom, pin.END_SCALE / maxZoom)
		end
	end
	if not scale then
		scale = pin.START_SCALE / map:GetCanvasScale()
	end
	return pin.SIZE * scale * map:GetGlobalPinScale()
end

function DataProviderMixin:RefreshAllData()
	self:RemoveAllData()
	if not ns.Options.Get("showWorldMap") then
		return
	end

	local map = self:GetMap()
	local nodes = {}
	ns.Layers.ForEachShownNode(map:GetMapID(), function(layer, name, _, x, y, count)
		table.insert(nodes, { layer = layer, name = name, x = x, y = y, count = count })
	end)

	-- Positions in canvas units, where pins are stacked as they overlap at their largest against
	-- the map (PinCanvasSize); at other zooms, pins that no longer overlap keep their levels,
	-- which changes nothing.
	local canvas = map:GetCanvas()
	local width, height = canvas:GetWidth(), canvas:GetHeight()
	local points = {}
	for i, node in ipairs(nodes) do
		points[i] = { x = node.x * width, y = node.y * height }
	end
	local size = PinCanvasSize(map)
	local levels = ns.Stacking.Levels(points, size, ns.WorldPin.STACK_LEVELS)
	if ns.dev.enabled then
		local counts = {}
		for level = 1, ns.WorldPin.STACK_LEVELS do
			counts[level] = 0
		end
		for _, level in ipairs(levels) do
			counts[level] = counts[level] + 1
		end
		local summary = ("%d pins, size %.1f of canvas %.0fx%.0f, per level %s"):format(
			#levels,
			size,
			width,
			height,
			table.concat(counts, "/")
		)
		ns.dev:LogChanged("stack " .. map:GetMapID(), summary, "STACK", "map", map:GetMapID(), summary)
	end

	for i, node in ipairs(nodes) do
		map:AcquirePin(PIN_TEMPLATE, node.layer, node.name, node.count, levels[i]):SetPosition(node.x, node.y)
	end
end

-- Maximizing or minimizing the map changes its zoom levels, and so which pins overlap.
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
