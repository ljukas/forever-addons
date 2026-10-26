local ADDON_NAME, ns = ...

local L = ns.L

-- A layer is one profession's nodes drawn on the maps. The renderers, menus and options
-- iterate the registered layers, so showing a profession's nodes takes a Register call.
--   key         unique layer key
--   profession  the profession whose nodes it shows, a key in Professions.lua
--   label       shown in the menus and the options panel
--   atlas       pin icon; the same atlases Blizzard's tracking menu uses
--   setting     ForeverProfessionsDB.settings key that toggles the layer
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

-- Calls func(layer, name, index, x, y, count) for every node on the map whose layer the
-- player has turned on. index is unique per name.
function ns.Layers.ForEachShownNode(mapID, func)
	for _, layer in ipairs(layers) do
		if ns.Options.Get(layer.setting) then
			ns.DB.ForEachNode(mapID, layer.profession, function(name, index, x, y, count)
				func(layer, name, index, x, y, count)
			end)
		end
	end
end

ns.Layers.Register({
	key = "herb",
	profession = "herbalism",
	label = L.HERBS,
	atlas = "professions_tracking_herb",
	setting = "showHerbs",
})

ns.Layers.Register({
	key = "ore",
	profession = "mining",
	label = L.MINERALS,
	atlas = "professions_tracking_ore",
	setting = "showOre",
})
