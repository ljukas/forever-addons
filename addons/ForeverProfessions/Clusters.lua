local ADDON_NAME, ns = ...

-- Merges nodes whose pins would overlap into one pin. Pure: no frames or API calls.
ns.Clusters = {}

-- points: array of { x, y, weight } in units where two pins closer than size overlap. Returns
-- an array of groups { anchor = index, members = { index, ... } }, members including the
-- anchor. Points are taken heaviest first (then north to south, west to east): each joins the
-- nearest anchor closer than size, or anchors a group of its own. A group's pin goes on its
-- anchor, and anchors are never closer than size to each other, so no two pins overlap.
function ns.Clusters.Group(points, size)
	local order = {}
	for i = 1, #points do
		order[i] = i
	end
	table.sort(order, function(a, b)
		local pa, pb = points[a], points[b]
		if pa.weight ~= pb.weight then
			return pa.weight > pb.weight
		end
		if pa.y ~= pb.y then
			return pa.y < pb.y
		end
		if pa.x ~= pb.x then
			return pa.x < pb.x
		end
		return a < b
	end)

	local groups = {}
	local sizeSquared = size * size
	for _, i in ipairs(order) do
		local p = points[i]
		local nearest, nearestSquared = nil, sizeSquared
		for _, group in ipairs(groups) do
			local anchor = points[group.anchor]
			local dx, dy = p.x - anchor.x, p.y - anchor.y
			local distanceSquared = dx * dx + dy * dy
			if distanceSquared < nearestSquared then
				nearest, nearestSquared = group, distanceSquared
			end
		end
		if nearest then
			table.insert(nearest.members, i)
		else
			table.insert(groups, { anchor = i, members = { i } })
		end
	end
	return groups
end

-- nodes: array of { layer, name, key, x, y, count } (count: times gathered); points: their
-- positions as Group takes them, without weight. Returns one pin per group:
--   x, y, key   the anchor node's map position and key
--   layer, name the node shown: the name most of the group's nodes have (ties: the more
--               gathered, then the anchor's)
--   nodes       the group's nodes, anchor first
function ns.Clusters.Pins(nodes, points, size)
	for i, point in ipairs(points) do
		point.weight = nodes[i].count
	end
	local pins = {}
	for _, group in ipairs(ns.Clusters.Group(points, size)) do
		local anchor = nodes[group.anchor]
		local members, perName, gatheredPerName = {}, {}, {}
		for _, index in ipairs(group.members) do
			local node = nodes[index]
			table.insert(members, node)
			perName[node.name] = (perName[node.name] or 0) + 1
			gatheredPerName[node.name] = (gatheredPerName[node.name] or 0) + node.count
		end
		local shown = anchor
		for _, node in ipairs(members) do
			local more = perName[node.name] - perName[shown.name]
			if more > 0 or (more == 0 and gatheredPerName[node.name] > gatheredPerName[shown.name]) then
				shown = node
			end
		end
		table.insert(pins, {
			x = anchor.x,
			y = anchor.y,
			key = anchor.key,
			layer = shown.layer,
			name = shown.name,
			nodes = members,
		})
	end
	return pins
end
