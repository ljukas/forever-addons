local ADDON_NAME, ns = ...

-- Combo points are secret, so they're counted: builders add what their description awards,
-- an avoided builder takes its points back, and a finisher or a new target starts over.
-- Points belong to one mob, as in Classic. No game API calls; Engine/Tracker.lua feeds it.
ns.Combo = {}

local MAX_POINTS = 5

local mobKey
local points = 0

function ns.Combo.Add(key, count)
	if key ~= mobKey then
		mobKey, points = key, 0
	end
	points = math.min(MAX_POINTS, points + count)
	return points
end

function ns.Combo.Take(key, count)
	if key == mobKey then
		points = math.max(0, points - count)
	end
	return points
end

-- The points counted on that mob; 0 if they were built on another.
function ns.Combo.Get(key)
	return key == mobKey and points or 0
end

function ns.Combo.Reset()
	mobKey, points = nil, 0
end
