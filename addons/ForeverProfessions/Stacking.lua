local ADDON_NAME, ns = ...

-- Which pins overlap, and in what order to stack them. Pins on one frame level don't draw one
-- after another: every pin's background is drawn, then every icon, then every ring, so where
-- two overlap one's ring crosses the other's icon. Overlapping pins therefore get different
-- frame levels, so each draws whole, the southern one in front like a stack of coins.
-- Pure: no frames or API calls.
ns.Stacking = {}

-- points: array of { x, y } with y growing southwards, in units where two pins closer than size
-- overlap. Returns an array of levels from 1 to maxLevel, one per point (1 at the back). A pin
-- is drawn in front of every pin north of it that it overlaps; where maxLevel runs out, it
-- takes the lowest level none of them use, and only shares a level when every level is taken.
function ns.Stacking.Levels(points, size, maxLevel)
	local order = {}
	for i = 1, #points do
		order[i] = i
	end
	table.sort(order, function(a, b)
		local pa, pb = points[a], points[b]
		if pa.y ~= pb.y then
			return pa.y < pb.y
		end
		if pa.x ~= pb.x then
			return pa.x < pb.x
		end
		return a < b
	end)

	local levels = {}
	local sizeSquared = size * size
	for n = 1, #order do
		local i = order[n]
		local p = points[i]
		local highest, used = 0, {}
		-- Sorted north to south, so only the pins just before this one can be within size.
		for m = n - 1, 1, -1 do
			local j = order[m]
			local q = points[j]
			local dy = p.y - q.y
			if dy >= size then
				break
			end
			local dx = p.x - q.x
			if dx * dx + dy * dy < sizeSquared then
				used[levels[j]] = true
				highest = math.max(highest, levels[j])
			end
		end
		local level = highest + 1
		if level > maxLevel then
			level = maxLevel
			for free = 1, maxLevel do
				if not used[free] then
					level = free
					break
				end
			end
		end
		levels[i] = level
	end
	return levels
end
