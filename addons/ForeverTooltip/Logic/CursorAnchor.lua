local ADDON_NAME, ns = ...

-- Where a cursor-following tooltip goes for each "Tooltip grows towards" choice. Pure maths: no WoW
-- API calls; every value is in the tooltip's own coordinate units.
ns.CursorAnchor = {}

-- Stored in ForeverTooltipDB.settings.cursorDirection: never renumber, only add new numbers.
ns.CursorAnchor.DIRECTION = { DOWN_RIGHT = 1, DOWN_LEFT = 2, UP_RIGHT = 3, UP_LEFT = 4 }

local D = ns.CursorAnchor.DIRECTION

-- Horizontal and vertical side of the cursor for each direction. Unknown values use UP_RIGHT.
local SIDES = {
	[D.DOWN_RIGHT] = { "RIGHT", "DOWN" },
	[D.DOWN_LEFT] = { "LEFT", "DOWN" },
	[D.UP_RIGHT] = { "RIGHT", "UP" },
	[D.UP_LEFT] = { "LEFT", "UP" },
}

-- Gap between the pointer's hotspot and the tooltip. The cursor arrow extends down and right from
-- the hotspot, so the down-right side needs the larger gap. Tuned at launch (launch check: ANCHOR).
local SMALL_GAP = 8
local ARROW_GAP_X, ARROW_GAP_Y = 20, 24

-- Returns point, x, y: the tooltip corner to pin and its position from UIParent's BOTTOMLEFT.
-- When the tooltip would leave the screen on a side it flips to the other side of the cursor, so
-- the screen clamp never pushes it back under the pointer. below (optional, default 0) is how far
-- something attached to the tooltip hangs below its bottom edge (the health bar panel, HealthBar.lua):
-- it counts towards the height, and a tooltip growing up is raised by it so it stays off the pointer.
-- Examples (screen 1000x800, tooltip 200x100, cursor at 500,400):
--   Place(UP_RIGHT, ...)   == "BOTTOMLEFT", 508, 408
--   Place(DOWN_RIGHT, ...) == "TOPLEFT", 520, 376
--   Place(UP_RIGHT, cursor 900,750) == "TOPRIGHT", 892, 742   (flips left and down)
--   Place(UP_RIGHT, ..., below 16) == "BOTTOMLEFT", 508, 424
--   Place(DOWN_RIGHT, cursor 500,130, below 16) == "BOTTOMLEFT", 508, 154   (flips up: 100 + 16 won't fit)
--   Place(UP_RIGHT, cursor 500,690, below 16) == "TOPLEFT", 520, 666   (flips down; fits without below)
function ns.CursorAnchor.Place(direction, cursorX, cursorY, width, height, screenWidth, screenHeight, below)
	below = below or 0
	local sides = SIDES[direction] or SIDES[D.UP_RIGHT]
	local horizontal, vertical = sides[1], sides[2]

	local function GapX()
		return (horizontal == "RIGHT" and vertical == "DOWN") and ARROW_GAP_X or SMALL_GAP
	end
	local function GapY()
		return (horizontal == "RIGHT" and vertical == "DOWN") and ARROW_GAP_Y or SMALL_GAP
	end

	if horizontal == "RIGHT" and cursorX + GapX() + width > screenWidth then
		horizontal = "LEFT"
	elseif horizontal == "LEFT" and cursorX - GapX() - width < 0 then
		horizontal = "RIGHT"
	end
	if vertical == "UP" and cursorY + GapY() + below + height > screenHeight then
		vertical = "DOWN"
	elseif vertical == "DOWN" and cursorY - GapY() - height - below < 0 then
		vertical = "UP"
	end

	local point = (vertical == "DOWN" and "TOP" or "BOTTOM") .. (horizontal == "RIGHT" and "LEFT" or "RIGHT")
	local x = cursorX + (horizontal == "RIGHT" and GapX() or -GapX())
	local y = cursorY + (vertical == "DOWN" and -GapY() or GapY() + below)
	return point, x, y
end
