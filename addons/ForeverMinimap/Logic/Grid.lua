local ADDON_NAME, ns = ...

-- Turning minimap probe hits into dots. Pure functions: no client API, so a reviewer can check
-- them by reading (and they run outside the game).
--
-- The first look at the minimap probes a coarse grid of points. A grid point is a key,
-- gx * 1000 + gy, for (gx * step, gy * step) pixels from the minimap's bottom left; touching
-- hits form a group. Each group is then probed again on a fine grid laid out in the world
-- (Cover), and its fine hits, as plain { x, y } points in any unit, give the dots (Dots).
ns.Grid = {}

-- The coarse grid points inside the round minimap of the given width, as a list of keys.
function ns.Grid.Points(width, step)
	local keys, radius = {}, width / 2
	local last = math.floor(width / step)
	for gx = 0, last do
		for gy = 0, last do
			local dx, dy = gx * step - radius, gy * step - radius
			if dx * dx + dy * dy <= radius * radius then
				table.insert(keys, gx * 1000 + gy)
			end
		end
	end
	return keys
end

-- Splits a set of coarse keys ({ [key] = true }) into groups of touching points, diagonals
-- included. Returns a list of lists of keys.
function ns.Grid.Groups(set)
	local groups, seen = {}, {}
	for first in pairs(set) do
		if not seen[first] then
			seen[first] = true
			local group, pending = {}, { first }
			while #pending > 0 do
				local key = table.remove(pending)
				table.insert(group, key)
				for _, step in ipairs({ -1001, -1000, -999, -1, 1, 999, 1000, 1001 }) do
					local other = key + step
					if set[other] and not seen[other] then
						seen[other] = true
						table.insert(pending, other)
					end
				end
			end
			table.insert(groups, group)
		end
	end
	return groups
end

-- A grid of points every `spacing` (aligned to multiples of it, so overlapping covers share
-- points) over the box around the given points, widened by `margin` on every side.
function ns.Grid.Cover(points, margin, spacing)
	local left, right, bottom, top = math.huge, -math.huge, math.huge, -math.huge
	for _, p in ipairs(points) do
		left, right = math.min(left, p.x), math.max(right, p.x)
		bottom, top = math.min(bottom, p.y), math.max(top, p.y)
	end
	local cover = {}
	for i = math.floor((left - margin) / spacing), math.ceil((right + margin) / spacing) do
		for j = math.floor((bottom - margin) / spacing), math.ceil((top + margin) / spacing) do
			table.insert(cover, { x = i * spacing, y = j * spacing })
		end
	end
	return cover
end

-- The points of a cover that belong to one group: within reach of its own coarse hits, and
-- nearer to them than to the hits of any other group of the same name. Without this, a group's
-- cover box reaches into a neighbouring node of the same name and takes part of it.
function ns.Grid.Claim(cover, own, others, reach)
	local claimed = {}
	for _, p in ipairs(cover) do
		local mine = math.huge
		for _, q in ipairs(own) do
			mine = math.min(mine, (p.x - q.x) ^ 2 + (p.y - q.y) ^ 2)
		end
		if mine <= reach * reach then
			local theirs = math.huge
			for _, q in ipairs(others) do
				theirs = math.min(theirs, (p.x - q.x) ^ 2 + (p.y - q.y) ^ 2)
			end
			if mine <= theirs then
				table.insert(claimed, p)
			end
		end
	end
	return claimed
end

-- The area a set of fine hits covers, each standing for one grid cell of cellArea.
function ns.Grid.DotArea(points, cellArea)
	return #points * cellArea
end

local function Middle(points)
	local x, y = 0, 0
	for _, p in ipairs(points) do
		x, y = x + p.x, y + p.y
	end
	return { x = x / #points, y = y / #points }
end

local function Distance2(a, b)
	return (a.x - b.x) ^ 2 + (a.y - b.y) ^ 2
end

-- The index of the center nearest to a point.
function ns.Grid.Nearest(point, centers)
	local best, bestDistance = 1, math.huge
	for i, center in ipairs(centers) do
		local distance = Distance2(point, center)
		if distance < bestDistance then
			best, bestDistance = i, distance
		end
	end
	return best
end

-- Whether a group of points is round: its spread along its long axis is at most twice its
-- spread across it (the eigenvalues of its covariance). Dots of the same name that touch in a
-- row make a long group; a dot cut off at the minimap's edge does too, but covers less than a
-- dot's area, so Dots keeps it whole.
function ns.Grid.IsRound(points, middle)
	middle = middle or Middle(points)
	local xx, yy, xy = 0, 0, 0
	for _, p in ipairs(points) do
		local dx, dy = p.x - middle.x, p.y - middle.y
		xx, yy, xy = xx + dx * dx, yy + dy * dy, xy + dx * dy
	end
	local mean = (xx + yy) / 2
	local spread = math.sqrt(((xx - yy) / 2) ^ 2 + xy * xy)
	return mean + spread <= 2 * (mean - spread)
end

-- How far past one dot's area a round group must reach to hold several dots: a triangle or
-- square of nodes is round too. Below it, a wrong dot-area estimate can't split a lone dot.
local ROUND_SPLIT = 2.5

-- The dots in a group's fine hits: their centers as { x, y }, and whether the group was one
-- round dot (the caller learns dotArea, the area of one dot's hits, from those). cellArea is
-- the area each hit stands for, in the same unit as dotArea.
function ns.Grid.Dots(points, cellArea, dotArea)
	if #points == 0 then
		return {}, false
	end
	local middle = Middle(points)
	local ratio = ns.Grid.DotArea(points, cellArea) / dotArea
	local round = ns.Grid.IsRound(points, middle)
	local count = 1
	if not round or ratio > ROUND_SPLIT then
		count = math.max(1, math.floor(ratio + 0.5))
	end
	if count == 1 then
		return { middle }, round
	end

	-- k-means from spread-out seeds: the point farthest from the middle, then each next one
	-- farthest from every seed so far.
	local centers = {}
	while #centers < count do
		local seed, seedDistance = points[1], -1
		for _, p in ipairs(points) do
			local distance = #centers == 0 and Distance2(p, middle)
				or Distance2(p, centers[ns.Grid.Nearest(p, centers)])
			if distance > seedDistance then
				seed, seedDistance = p, distance
			end
		end
		table.insert(centers, { x = seed.x, y = seed.y })
	end
	for _ = 1, 10 do
		local members = {}
		for i = 1, count do
			members[i] = {}
		end
		for _, p in ipairs(points) do
			table.insert(members[ns.Grid.Nearest(p, centers)], p)
		end
		for i = 1, count do
			if #members[i] > 0 then
				centers[i] = Middle(members[i])
			end
		end
	end
	return centers, false
end

-- Joins dots closer than `distance` into one at their middle: the same dot found twice when the
-- minimap moved under the first look and split its hits into two groups.
function ns.Grid.Merge(dots, distance)
	local joined = {}
	for _, dot in ipairs(dots) do
		local into
		for _, other in ipairs(joined) do
			if Distance2(dot, other) < distance * distance then
				into = other
				break
			end
		end
		if into then
			into.x, into.y, into.count =
				(into.x * into.count + dot.x) / (into.count + 1),
				(into.y * into.count + dot.y) / (into.count + 1),
				into.count + 1
		else
			table.insert(joined, { x = dot.x, y = dot.y, count = 1 })
		end
	end
	return joined
end
