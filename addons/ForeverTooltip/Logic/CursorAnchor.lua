local _, ns = ...

-- Which corner of the tooltip is pinned to the cursor for each "Tooltip grows towards" choice, and
-- its offset from the pointer. The cursor arrow extends down and right from its hotspot, so
-- down-right needs the largest gap. Offsets are tuned at launch (launch check: ANCHOR).
-- Pure data: no WoW API calls. Directions are ns.Options.DIRECTION values:
--   1 DOWN_RIGHT -> "TOPLEFT",      20, -24
--   2 DOWN_LEFT  -> "TOPRIGHT",     -8,  -8
--   3 UP_RIGHT   -> "BOTTOMLEFT",    8,   8   (default, and the fallback for unknown values)
--   4 UP_LEFT    -> "BOTTOMRIGHT",  -8,   8
ns.CursorAnchor = {}

local POINTS = {
	[1] = { "TOPLEFT", 20, -24 },
	[2] = { "TOPRIGHT", -8, -8 },
	[3] = { "BOTTOMLEFT", 8, 8 },
	[4] = { "BOTTOMRIGHT", -8, 8 },
}

local FALLBACK = POINTS[3]

-- Returns point, offsetX, offsetY for a direction.
function ns.CursorAnchor.Point(direction)
	local entry = POINTS[direction] or FALLBACK
	return entry[1], entry[2], entry[3]
end
