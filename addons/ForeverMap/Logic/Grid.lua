local ADDON_NAME, ns = ...

-- Turning minimap probe hits into dots. Pure functions: no client API, so a reviewer can check
-- them by reading (and they run outside the game).
--
-- Probe points sit on square grids over the minimap. A point is a key, gx * 1000 + gy, for the
-- grid point (gx * step, gy * step) in pixels from the minimap's bottom left. A scan probes a
-- coarse grid first; each group of touching hits is then probed again on a fine grid, and the
-- fine hits give the dots' centers.
ns.Grid = {}

local function Key(gx, gy)
	return gx * 1000 + gy
end

local function Coords(key)
	return math.floor(key / 1000), key % 1000
end

-- The grid points inside the round minimap of the given width, as a list of keys.
function ns.Grid.Points(width, step)
	local points, radius = {}, width / 2
	for gx = 0, math.floor(width / step) do
		for gy = 0, math.floor(width / step) do
			local dx, dy = gx * step - radius, gy * step - radius
			if dx * dx + dy * dy <= radius * radius then
				table.insert(points, Key(gx, gy))
			end
		end
	end
	return points
end

-- Splits a set of hit keys ({ [key] = true }) into groups of touching points, diagonals
-- included. Returns a list of lists of keys.
function ns.Grid.Groups(set)
	local groups, done = {}, {}
	for start in pairs(set) do
		if not done[start] then
			local group, queue = {}, { start }
			done[start] = true
			while #queue > 0 do
				local key = table.remove(queue)
				table.insert(group, key)
				for dx = -1, 1 do
					for dy = -1, 1 do
						local neighbour = key + dx * 1000 + dy
						if set[neighbour] and not done[neighbour] then
							done[neighbour] = true
							table.insert(queue, neighbour)
						end
					end
				end
			end
			table.insert(groups, group)
		end
	end
	return groups
end

-- The fine grid points that cover a coarse group: its bounding box, in pixels, widened by one
-- coarse step on every side so the edges of its dots are probed too.
function ns.Grid.FinePoints(group, coarseStep, fineStep)
	local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
	for _, key in ipairs(group) do
		local gx, gy = Coords(key)
		minX, maxX = math.min(minX, gx * coarseStep), math.max(maxX, gx * coarseStep)
		minY, maxY = math.min(minY, gy * coarseStep), math.max(maxY, gy * coarseStep)
	end
	local points = {}
	local fromX, toX =
		math.max(0, math.floor((minX - coarseStep) / fineStep)), math.ceil((maxX + coarseStep) / fineStep)
	local fromY, toY =
		math.max(0, math.floor((minY - coarseStep) / fineStep)), math.ceil((maxY + coarseStep) / fineStep)
	for gx = fromX, toX do
		for gy = fromY, toY do
			table.insert(points, Key(gx, gy))
		end
	end
	return points
end

-- The area in pixels that a set of fine hits covers.
function ns.Grid.DotArea(fineKeys, fineStep)
	return #fineKeys * fineStep * fineStep
end

local function Mean(points)
	local x, y = 0, 0
	for _, p in ipairs(points) do
		x, y = x + p.x, y + p.y
	end
	return { x = x / #points, y = y / #points }
end

local function Distance2(a, b)
	return (a.x - b.x) ^ 2 + (a.y - b.y) ^ 2
end

-- The point farthest from every center so far: a seed for the next center.
local function Farthest(points, centers)
	local best, bestDistance = points[1], -1
	for _, p in ipairs(points) do
		local nearest = math.huge
		for _, c in ipairs(centers) do
			nearest = math.min(nearest, Distance2(p, c))
		end
		if nearest > bestDistance then
			best, bestDistance = p, nearest
		end
	end
	return best
end

-- Dots in a group's fine hits, as a list of { x, y } centers in pixels from the minimap's
-- bottom left. dotArea is the area one dot's hits cover: a group covering about k times that
-- is k dots of the same name close together, split with k-means.
function ns.Grid.Dots(fineKeys, fineStep, dotArea)
	if #fineKeys == 0 then
		return {}
	end
	local points = {}
	for _, key in ipairs(fineKeys) do
		local gx, gy = Coords(key)
		table.insert(points, { x = gx * fineStep, y = gy * fineStep })
	end
	local center = Mean(points)
	local k = math.max(1, math.floor(ns.Grid.DotArea(fineKeys, fineStep) / dotArea + 0.5))
	if k == 1 then
		return { center }
	end

	-- Seeds spread out: the point farthest from the middle, then each next one farthest
	-- from the seeds so far.
	local centers = { Farthest(points, { center }) }
	while #centers < k do
		table.insert(centers, Farthest(points, centers))
	end
	for _ = 1, 10 do
		local clusters = {}
		for i = 1, k do
			clusters[i] = {}
		end
		for _, p in ipairs(points) do
			local nearest, nearestDistance = 1, math.huge
			for i, c in ipairs(centers) do
				local distance = Distance2(p, c)
				if distance < nearestDistance then
					nearest, nearestDistance = i, distance
				end
			end
			table.insert(clusters[nearest], p)
		end
		for i = 1, k do
			if #clusters[i] > 0 then
				centers[i] = Mean(clusters[i])
			end
		end
	end
	return centers
end
