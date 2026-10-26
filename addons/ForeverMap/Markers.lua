local ADDON_NAME, ns = ...

-- The dots the last scan found, kept as positions in the world so their icons follow the
-- minimap as the player moves and turns. A marker is
--   { kind, gray, mapID, mapX, mapY }  where the client gave a map position, or
--   { kind, gray, ox, oy }             a minimap offset, where it didn't (some instances and
--                                      caves); those stay put until the next scan.
ns.Markers = {}

local markers = {}

-- Replaces every marker with the dots of a scan (Scanner.lua): each dot has its minimap offset
-- (ox, oy) and the view it was measured in, or no view.
function ns.Markers.Replace(dots)
	wipe(markers)
	for _, dot in ipairs(dots) do
		local view = dot.view
		if view then
			local mapX, mapY = ns.Anchor.ToMap(dot.ox, dot.oy, view)
			table.insert(markers, { kind = dot.kind, gray = dot.gray, mapID = view.mapID, mapX = mapX, mapY = mapY })
		else
			table.insert(markers, { kind = dot.kind, gray = dot.gray, ox = dot.ox, oy = dot.oy })
		end
	end
end

function ns.Markers.Enumerate()
	return ipairs(markers)
end

function ns.Markers.IsEmpty()
	return markers[1] == nil
end

-- How far a marker is from the player in yards, or nil when that can't be told (a map marker
-- seen from another map, or with no map position now).
local function Yards(marker, view, pixelsPerYard)
	if marker.ox then
		return math.sqrt(marker.ox ^ 2 + marker.oy ^ 2) / pixelsPerYard
	end
	if view and view.mapID == marker.mapID then
		local east = (marker.mapX - view.px) * view.width
		local north = (marker.mapY - view.py) * view.height
		return math.sqrt(east ^ 2 + north ^ 2)
	end
end

-- Removes the marker nearest the player within the given yards: the node gathered just now.
function ns.Markers.RemoveNearPlayer(yards, pixelsPerYard)
	local view = ns.Scanner.CurrentView()
	local nearest, nearestYards
	for index, marker in ipairs(markers) do
		local distance = Yards(marker, view, pixelsPerYard)
		if distance and distance <= yards and (not nearestYards or distance < nearestYards) then
			nearest, nearestYards = index, distance
		end
	end
	if nearest then
		table.remove(markers, nearest)
	end
end
