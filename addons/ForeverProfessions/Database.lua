local ADDON_NAME, ns = ...

-- ForeverProfessionsDB layout (account-wide):
--   version  = schema version, see migrations below
--   settings = { [key] = boolean }, owned by Options.lua
--   nodes    = { [uiMapID] = { [profession] = { [nodeName] = { x1, y1, count1, x2, y2, count2, ... } } } }
-- profession is the node's key in Professions.lua. x, y are normalized positions on that zone
-- map, rounded to 4 decimals. count is how many times the node has been gathered. Only this
-- file knows the flat layout.

ns.DB = {}

local DB_VERSION = 1
local STRIDE = 3

-- A gather within this distance of a known node of the same name is the same node.
local DEDUPE_YARDS = 10
-- Used for the dedupe distance when the client doesn't know a map's size.
local FALLBACK_MAP_YARDS = 1000

local migrations = {
	[1] = function(db)
		db.settings = db.settings or {}
		db.nodes = db.nodes or {}
	end,
}

function ns.DB.Migrate(db)
	-- Data from a newer version of the addon is left alone rather than downgraded.
	for version = (db.version or 0) + 1, DB_VERSION do
		migrations[version](db)
		db.version = version
	end
end

-- Calls func(name, index, x, y, count) for every node of the profession recorded on the
-- map. index is unique per name.
function ns.DB.ForEachNode(mapID, profession, func)
	local map = ns.db.nodes[mapID]
	local nodes = map and map[profession]
	if not nodes then
		return
	end
	for name, nodeData in pairs(nodes) do
		for i = 1, #nodeData, STRIDE do
			func(name, i, nodeData[i], nodeData[i + 1], nodeData[i + 2])
		end
	end
end

local function Round(value)
	return math.floor(value * 10000 + 0.5) / 10000
end

-- Records a gather of a known node. Returns true if the node was new, false if it was
-- an existing node gathered again.
function ns.DB.Add(mapID, name, x, y)
	local node = ns.Professions.GetNode(name)
	x, y = Round(x), Round(y)

	local width, height = ns.GetMapSize(mapID)
	width = width or FALLBACK_MAP_YARDS
	height = height or FALLBACK_MAP_YARDS

	local map = ns.db.nodes[mapID] or {}
	ns.db.nodes[mapID] = map
	local nodes = map[node.profession] or {}
	map[node.profession] = nodes
	local nodeData = nodes[name] or {}
	nodes[name] = nodeData

	local isNew = true
	for i = 1, #nodeData, STRIDE do
		local dx = (nodeData[i] - x) * width
		local dy = (nodeData[i + 1] - y) * height
		if dx * dx + dy * dy <= DEDUPE_YARDS * DEDUPE_YARDS then
			nodeData[i + 2] = nodeData[i + 2] + 1
			isNew = false
			break
		end
	end
	if isNew then
		table.insert(nodeData, x)
		table.insert(nodeData, y)
		table.insert(nodeData, 1)
	end

	ns.callbacks:TriggerEvent("NodesChanged", mapID)
	return isNew
end
