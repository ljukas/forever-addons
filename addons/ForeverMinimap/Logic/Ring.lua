local ADDON_NAME, ns = ...

-- Where a button sits on the ring around the minimap, and the angle of a point from the center.
-- Pure functions: no client API, so a reviewer can check them by reading.
--
-- Angles are degrees counter-clockwise from east (0 = east, 90 = north), the convention LibDBIcon
-- uses for `minimapPos`. Offsets are in pixels from the minimap's center, x right and y up.
-- `shape` is a GetMinimapShape() value; the quadrant table is ported from LibDBIcon.
ns.Ring = {}

ns.Ring.DEFAULT_ANGLE = 225 -- bottom-left

-- Per quadrant, whether the ring is round there (true) or follows a square corner (false). The
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

function ns.Ring.Offset(angle, radius, shape)
	local rad = math.rad(angle)
	local x, y = math.cos(rad), math.sin(rad)
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
	local diag = math.sqrt(2 * radius ^ 2) - 10
	return math.max(-radius, math.min(x * diag, radius)), math.max(-radius, math.min(y * diag, radius))
end

function ns.Ring.AngleTo(x, y)
	local angle = math.deg(math.atan2(y, x))
	if angle < 0 then
		angle = angle + 360
	end
	return angle
end
