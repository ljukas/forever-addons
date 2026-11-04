local ADDON_NAME, ns = ...

-- Converting between a point on the minimap and a position on the zone map, so an icon found on
-- the minimap stays on its spot in the world as the player moves and turns. Pure functions: no
-- client API, so a reviewer can check them by reading (and they run outside the game).
--
-- A minimap offset (ox, oy) is in pixels from the minimap's center, x right and y up. A view
-- holds what the conversion needs at one moment:
--   px, py         the player's normalized position on the zone map
--   width, height  the zone map's size in yards
--   pixelsPerYard  minimap pixels per yard at the current zoom
--   facing         radians counter-clockwise from north when the minimap rotates, else 0
ns.Anchor = {}

-- A rotating minimap keeps the player's facing up, so world offsets are turned clockwise by
-- the facing on the way onto the minimap and back on the way off it. Map y grows southwards.

function ns.Anchor.ToMinimap(mapX, mapY, view)
	local east = (mapX - view.px) * view.width
	local north = (view.py - mapY) * view.height
	local sin, cos = math.sin(view.facing), math.cos(view.facing)
	return (east * cos + north * sin) * view.pixelsPerYard, (north * cos - east * sin) * view.pixelsPerYard
end

function ns.Anchor.ToMap(ox, oy, view)
	local sin, cos = math.sin(view.facing), math.cos(view.facing)
	local east = (ox * cos - oy * sin) / view.pixelsPerYard
	local north = (ox * sin + oy * cos) / view.pixelsPerYard
	return view.px + east / view.width, view.py - north / view.height
end
