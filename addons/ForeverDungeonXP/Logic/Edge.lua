local _, ns = ...

-- Where a button sits on the minimap's edge. Pure: no client state. The same maths as
-- ForeverMinimap's Logic/Ring.lua (its quadrant table is LibDBIcon's), so this addon's button
-- lands where every other minimap button would for the same angle.
--
-- Angles are degrees counter-clockwise from east (0 = east, 90 = north). Offsets are pixels from
-- the minimap's centre, x right and y up. shape is a GetMinimapShape() value.

ns.Edge = {}

ns.Edge.DEFAULT_ANGLE = 200

-- Per quadrant, whether the edge is round there (true) or follows a square corner (false). The
-- quadrants run: 1 = bottom-right, 2 = bottom-left, 3 = top-right, 4 = top-left.
local ROUND_QUADRANTS = {
	["ROUND"] = { true, true, true, true },
	["SQUARE"] = { false, false, false, false },
	["CORNER-TOPLEFT"] = { false, false, false, true },
	["CORNER-TOPRIGHT"] = { false, false, true, false },
	["CORNER-BOTTOMLEFT"] = { false, true, false, false },
	["CORNER-BOTTOMRIGHT"] = { true, false, false, false },
	["SIDE-LEFT"] = { false, true, false, true },
	["SIDE-RIGHT"] = { true, false, true, false },
	["SIDE-TOP"] = { false, false, true, true },
	["SIDE-BOTTOM"] = { true, true, false, false },
	["TRICORNER-TOPLEFT"] = { false, true, true, true },
	["TRICORNER-TOPRIGHT"] = { true, false, true, true },
	["TRICORNER-BOTTOMLEFT"] = { true, true, false, true },
	["TRICORNER-BOTTOMRIGHT"] = { true, true, true, false },
}

--   0, 75, "ROUND" -> 75, 0        90, 75, "ROUND" -> 0, 75        45, 75, "SQUARE" -> 67.9, 67.9
function ns.Edge.Offset(angle, radius, shape)
	local radians = math.rad(angle)
	local x, y = math.cos(radians), math.sin(radians)
	local quadrant = 1
	if x < 0 then
		quadrant = quadrant + 1
	end
	if y > 0 then
		quadrant = quadrant + 2
	end
	local quadrants = ROUND_QUADRANTS[shape] or ROUND_QUADRANTS.ROUND
	if quadrants[quadrant] then
		return x * radius, y * radius
	end
	-- A square corner: stretch the unit vector to the box's diagonal and clamp it to the edge.
	local diagonal = math.sqrt(2 * radius ^ 2) - 10
	return math.max(-radius, math.min(x * diagonal, radius)), math.max(-radius, math.min(y * diagonal, radius))
end

-- The angle of a point from the centre, 0 to 360.
--   1, 0 -> 0        0, 1 -> 90        -1, 0 -> 180        0, -1 -> 270
function ns.Edge.AngleTo(x, y)
	return math.deg(math.atan2(y, x)) % 360
end
