local ADDON_NAME, ns = ...

-- Where each button of the opened bag sits, as an offset from our own button's center. Pure
-- functions: no client API, so a reviewer can check them by reading.
--
-- Offsets are in pixels, x right and y up. Slot 1 is one step (size + gap) from our button in the
-- direction the strip grows. A line holds `perLine` slots, then the next line starts beside the
-- first: to the right for DOWN and UP, downward for LEFT and RIGHT.
ns.Strip = {}

ns.Strip.PER_LINE = 6

function ns.Strip.Offset(index, direction, perLine, size, gap)
	local step = size + gap
	local along = ((index - 1) % perLine + 1) * step
	local across = math.floor((index - 1) / perLine) * step
	-- ns.Options loads after this file, so its DIRECTION values are read when called.
	local DIRECTION = ns.Options.DIRECTION
	if direction == DIRECTION.DOWN then
		return across, -along
	elseif direction == DIRECTION.UP then
		return across, along
	elseif direction == DIRECTION.LEFT then
		return -along, -across
	end
	return along, -across -- RIGHT
end
