local _, ns = ...

-- Where a button sits on the minimap's edge. Pure: no client state. The quadrant table is
-- LibDBIcon's, so the core's button lands where every other minimap button would for the same
-- angle. Two addons in this repo carry the same maths and can't call the core until they are
-- modules; roadmap step 4 (shared code into the core) is where the copies become one
-- (docs/superpowers/specs/2026-11-18-razzhui-minimap-button-design.md names them).
--
-- Angles are degrees counter-clockwise from east (0 = east, 90 = north). Offsets are pixels from
-- the minimap's centre, x right and y up. shape is a GetMinimapShape() value.

ns.Edge = {}

-- Between nine and ten o'clock. Clear of what Blizzard puts round the minimap on Forever: the
-- header (top), the day and night indicator (about 57), the event button when there is one (about
-- 189), the group finder's eye (225), the coordinates text (270, an option) and the zoom buttons
-- (about 315). Also clear of where other addons' buttons start out (200 to 225).
ns.Edge.DEFAULT_ANGLE = 160

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
--   270, 104, "ROUND" -> 0, -104   270, 104, "SQUARE" -> 0, -104 (straight down is on the edge
--   of either shape; the 0 is cos(270 degrees), about -2e-16 in floating point)
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
