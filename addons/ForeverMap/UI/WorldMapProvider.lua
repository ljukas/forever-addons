local ADDON_NAME, ns = ...

-- Draws known nodes on the world map through Blizzard's own map canvas pipeline, the
-- same way DeathMapDataProvider draws the corpse pin. Nodes are stored per zone map, so
-- they show when that zone is open.

local PIN_TEMPLATE = "ForeverMapWorldPinTemplate"

---@class ForeverMapDataProviderMixin : MapCanvasDataProviderMixin
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

function DataProviderMixin:RefreshAllData()
	self:RemoveAllData()
	if not ns.Options.Get("showWorldMap") then
		return
	end

	local map = self:GetMap()
	ns.DB.ForEachShownNode(map:GetMapID(), function(layer, name, _, x, y, count)
		map:AcquirePin(PIN_TEMPLATE, layer, name, count):SetPosition(x, y)
	end)
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
		---@cast pin ForeverMapWorldPinMixin
		pin:RefreshSkillState()
	end
end

ns.OnInitialize(function()
	EventUtil.ContinueOnAddOnLoaded("Blizzard_WorldMap", function()
		WorldMapFrame:AddDataProvider(CreateFromMixins(DataProviderMixin))
	end)
end)
