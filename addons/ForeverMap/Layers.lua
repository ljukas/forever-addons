local ADDON_NAME, ns = ...

local L = ns.L

-- A layer is one kind of node drawn on the maps. The renderers, menus and options
-- iterate the registered layers, so adding a kind of node takes a Register call, its
-- entries in ns.GatherNodes and a source that records it.
--   key         storage key in ForeverMapDB.nodes and the layer field of ns.GatherNodes
--   label       shown in the menus and the options panel
--   atlas       pin icon; the same atlases Blizzard's tracking menu uses
--   setting     ForeverMapDB.settings key that toggles the layer
--   skillLineID profession skill line, compared against the node's required skill
--   profession  profession name, used when the skill line ID doesn't match
-- Register adds tooltip, the description used by the menus and the options panel.
ns.Layers = {}

local layers = {}
local layersByKey = {}

function ns.Layers.Register(layer)
	assert(not layersByKey[layer.key], "duplicate layer " .. layer.key)
	layer.tooltip = L.SHOW_LAYER_TOOLTIP:format(layer.label:lower())
	table.insert(layers, layer)
	layersByKey[layer.key] = layer
end

function ns.Layers.Enumerate()
	return ipairs(layers)
end

-- Returns the node's data and its layer, or nil if the name isn't a known node.
function ns.Layers.GetNode(name)
	local node = ns.GatherNodes[name]
	if node then
		return node, layersByKey[node.layer]
	end
end

-- Skill line IDs are the Classic ones and still need checking in Forever.
ns.Layers.Register({
	key = "herb",
	label = L.HERBS,
	atlas = "professions_tracking_herb",
	setting = "showHerbs",
	skillLineID = 182,
	profession = L.HERBALISM,
})

ns.Layers.Register({
	key = "ore",
	label = L.MINERALS,
	atlas = "professions_tracking_ore",
	setting = "showOre",
	skillLineID = 186,
	profession = L.MINING,
})
