local ADDON_NAME, ns = ...

-- Edit Mode snapping for the power bar's box, by the rules of Blizzard's EditModeMagnetismManager
-- (Blizzard_EditMode/Shared/EditModeUtil.lua): when the player has snapping on, a dropped box moves
-- onto the closest line within the magnetism range (8 screen pixels): the screen's edges and
-- centre, the Edit Mode grid lines, and the edges and centres of the other Edit Mode boxes. Blizzard's
-- state is only read; the box is ours. LibEditMode doesn't snap.
ns.Snap = {}

-- The shift (in the same units as the arguments) that puts the closest of points onto the closest
-- of lines, or 0 when none is within range. Pure.
function ns.Snap.Shift(points, lines, range)
	local best
	for _, point in ipairs(points) do
		for _, line in ipairs(lines) do
			local shift = line - point
			if math.abs(shift) <= range and (not best or math.abs(shift) < math.abs(best)) then
				best = shift
			end
		end
	end
	return best or 0
end

-- Whether intervals [a1, a2] and [b1, b2] overlap or come within gap of each other. Pure.
function ns.Snap.Near(a1, a2, b1, b2, gap)
	return a1 <= b2 + gap and b1 <= a2 + gap
end

-- A frame's sides in UIParent's coordinates (frames may have their own scale): left, right,
-- bottom, top, or nil when it isn't placed.
local function Sides(frame)
	local left, bottom, width, height = frame:GetRect()
	if not left then
		return nil
	end
	local scale = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
	return left * scale, (left + width) * scale, bottom * scale, (bottom + height) * scale
end

-- The x and y lines to snap to, for a box with the given sides.
local function Lines(left, right, bottom, top, range)
	local xLines, yLines = {}, {}

	local function AddFrame(frameLeft, frameRight, frameBottom, frameTop, sameAxisOnly)
		-- A box's vertical lines only count when it is beside or above/below us, as Blizzard's
		-- eligibility does; the screen's always do.
		if sameAxisOnly or ns.Snap.Near(bottom, top, frameBottom, frameTop, range) then
			tinsert(xLines, frameLeft)
			tinsert(xLines, frameRight)
			tinsert(xLines, (frameLeft + frameRight) / 2)
		end
		if sameAxisOnly or ns.Snap.Near(left, right, frameLeft, frameRight, range) then
			tinsert(yLines, frameBottom)
			tinsert(yLines, frameTop)
			tinsert(yLines, (frameBottom + frameTop) / 2)
		end
	end

	local parentLeft, parentRight, parentBottom, parentTop = Sides(UIParent)
	AddFrame(parentLeft, parentRight, parentBottom, parentTop, true)

	local magnetism = EditModeMagnetismManager
	local grid = magnetism.magneticGridLines
	if grid then
		for _, x in pairs(grid.vertical) do
			tinsert(xLines, x)
		end
		for _, y in pairs(grid.horizontal) do
			tinsert(yLines, y)
		end
	end

	for frame in pairs(magnetism.magneticFrames) do
		if frame:IsVisible() then
			local frameLeft, frameRight, frameBottom, frameTop = Sides(frame)
			if frameLeft then
				AddFrame(frameLeft, frameRight, frameBottom, frameTop, false)
			end
		end
	end
	return xLines, yLines
end

-- The shift that snaps frame (a box on UIParent) to its closest lines: dx, dy in UIParent's
-- units. 0, 0 while the player has snapping off.
function ns.Snap.ShiftFor(frame)
	if not EditModeManagerFrame:IsSnapEnabled() then
		return 0, 0
	end
	local left, right, bottom, top = Sides(frame)
	if not left then
		return 0, 0
	end
	local range = EditModeMagnetismManager.magnetismRange / UIParent:GetEffectiveScale()
	local xLines, yLines = Lines(left, right, bottom, top, range)
	local dx = ns.Snap.Shift({ left, right, (left + right) / 2 }, xLines, range)
	local dy = ns.Snap.Shift({ bottom, top, (bottom + top) / 2 }, yLines, range)
	return dx, dy
end
