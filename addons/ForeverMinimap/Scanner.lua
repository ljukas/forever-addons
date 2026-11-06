local ADDON_NAME, ns = ...

-- Finds the herb, ore and chest tracking dots on the minimap (ADR 0001). The client tells addons nothing
-- about tracked nodes, but the minimap names what is under a point: with its soft cursor on,
-- Minimap:UpdateMouseoverAtPoint moves the minimap's mouseover there and
-- C_TooltipInfo.GetMinimapMouseover reads the names.
--
-- A sweep is a queue of such probes, worked through a batch per frame. It starts with a coarse
-- grid over the minimap; the hits of each name that touch form a group, and each group is probed
-- again on a fine grid laid out in the world, so the player moving or turning between frames
-- doesn't smear it. Every hit is turned into a world position in the frame it was read, and the
-- fine hits give the dots (Logic/Grid.lua), which become markers (Markers.lua).
--
-- Positions in a sweep are "places": yards east and south on the zone map, or, where the client
-- has no map position, minimap pixels from the center that don't follow the player.
--
-- Dev log tags: SCAN (a summary of the last few sweeps, and each time the minimap hides), DOT
-- (once per kind of dot seen), LINE (once per distinct tooltip line and color), MISS (once per
-- name that isn't a known node), LOOT (what gathering removed).
ns.Scanner = {}

local PROBES_PER_FRAME = 30
local INTERVAL_MOVING = 0.5 -- seconds between sweeps while the player moves or turns
local INTERVAL_STILL = 2 -- and while standing still
local INTERVAL_LONGEST = 3 -- the wait doubles after each sweep that found nothing, up to this
local PAUSE = 0.25 -- seconds between checks while the mouse is over the minimap
local REACH = 5 -- yards: how near the player a node gathered just now is
local TURN = 0.05 -- radians of turning that count as moving
local SUMMARY_EVERY = 20 -- sweeps per SCAN log line

-- The area one dot's hits cover, in minimap pixels: measured in every sweep (Settle), starting
-- from the hit radius measured in game at 100% icon scale (11.3 to 11.8 px), within limits.
local MIN_AREA, MAX_AREA = math.pi * 3 ^ 2, math.pi * 32 ^ 2
local dotArea = math.pi * 12 ^ 2

-- The grid spacings, in minimap pixels, follow a dot's radius. The coarse grid's half-diagonal
-- is three quarters of a radius, so a dot gets a coarse hit even when it is a quarter smaller
-- than learned; the fine grid takes about four steps per radius. Against Logic/Grid.lua on
-- modelled dots, that finds the same dots as an 8 and 2 px grid with half the probes at 100%
-- icon scale, and puts their middles within half a pixel on average.
local COARSE_PER_RADIUS, MIN_COARSE, MAX_COARSE = 1.05, 6, 14
local FINE_PER_RADIUS, MIN_FINE, MAX_FINE = 0.27, 2, 4

-- A dot's radius is learned only from dots the coarse grid finds, so a grid laid out for big
-- dots could keep missing small ones. The radius it is laid out for is therefore at most the
-- one measured at 100% icon scale times the minimap's icon scale now (Edit Mode, 50% to 200%),
-- in case the dots shrink with it.
local RADIUS_AT_FULL_SCALE = 11.5

local function Usable(value)
	return value ~= nil and not issecretvalue(value)
end

-- The minimap's icon scale as Edit Mode holds it, or its smallest when it can't be read (it
-- reads 0 until Edit Mode has set the minimap up).
local function IconScale()
	if not (MinimapCluster and MinimapCluster.GetSettingValue and Enum.EditModeMinimapSetting) then
		return 0.5
	end
	local percent = MinimapCluster:GetSettingValue(Enum.EditModeMinimapSetting.IconScale)
	if Usable(percent) and type(percent) == "number" and percent > 0 then
		return percent / 100
	end
	return 0.5
end

local function Spacings()
	local radius = math.min(math.sqrt(dotArea / math.pi), RADIUS_AT_FULL_SCALE * IconScale())
	local coarse = math.max(MIN_COARSE, math.min(MAX_COARSE, math.floor(radius * COARSE_PER_RADIUS + 0.5)))
	local fine = math.max(MIN_FINE, math.min(MAX_FINE, math.floor(radius * FINE_PER_RADIUS + 0.5)))
	return coarse, fine
end

local sweep -- the sweep running now, or nil
local wait = 0 -- seconds until the next sweep
local empties = 0 -- sweeps in a row that found nothing
local cleared = false -- whether the markers were cleared since the icons were last enabled
local last = {} -- where the player was when the last sweep started: { x, y, facing }
local layout, layoutWidth, layoutStep -- the coarse grid keys, kept until the minimap's size or the spacing changes
-- The fine hits of the last sweep that ran start to end with the player standing still: { view,
-- coarse, fine, age, groups = { [Signature] = points } }, or nil. age counts the sweeps in a row
-- that took them over; after REUSE_SWEEPS, every group is probed again. That bounds how long a
-- change the coarse grid can't see (one of two touching nodes gathered) shows wrong.
local kept
local REUSE_SWEEPS = 4
local sweeps = 0 -- dev only: sweeps since login
-- Dev only: totals over the sweeps since the last SCAN line. ms is all the time spent in sweeps,
-- client the part of it in the two client calls per probe, dev the part spent logging tooltip
-- lines (players don't pay for that), worst the slowest frame.
local stats
local function ResetStats()
	stats = { sweeps = 0, coarse = 0, fine = 0, reused = 0, dots = 0, ms = 0, client = 0, dev = 0, worst = 0 }
	stats.since = GetTime()
end
ResetStats()

-- Minimap pixels per yard at the current zoom, or nil.
function ns.Scanner.PixelsPerYard()
	local radius, width = C_Minimap.GetViewRadius(), Minimap:GetWidth()
	if Usable(radius) and Usable(width) and radius > 0 then
		return width / (2 * radius)
	end
end

-- The view (Logic/Anchor.lua) at this moment, with the map's ID, or nil where the client has
-- no map position (some instances and caves).
function ns.Scanner.CurrentView()
	local mapID = C_Map.GetBestMapForUnit("player")
	if not mapID or issecretvalue(mapID) then
		return nil
	end
	local position = C_Map.GetPlayerMapPosition(mapID, "player")
	if not position or issecretvalue(position) then
		return nil
	end
	local px, py = position:GetXY()
	local width, height = C_Map.GetMapWorldSize(mapID)
	local pixelsPerYard = ns.Scanner.PixelsPerYard()
	if not (Usable(px) and Usable(py) and Usable(width) and Usable(height) and pixelsPerYard) then
		return nil
	end
	if width <= 0 or height <= 0 then
		return nil
	end
	---@type number?
	local facing = 0
	if CVarCallbackRegistry:GetCVarValueBool("rotateMinimap") then
		facing = GetPlayerFacing()
		if not facing or issecretvalue(facing) then
			return nil
		end
	end
	return {
		mapID = mapID,
		px = px,
		py = py,
		width = width,
		height = height,
		pixelsPerYard = pixelsPerYard,
		facing = facing,
	}
end

-- Places: see the header.
local function ToPlace(ox, oy, view)
	if not view then
		return ox, oy
	end
	local mapX, mapY = ns.Anchor.ToMap(ox, oy, view)
	return mapX * view.width, mapY * view.height
end

local function ToOffset(x, y, view)
	if not view then
		return x, y
	end
	return ns.Anchor.ToMinimap(x / view.width, y / view.height, view)
end

-- Where the minimap is on screen and how big, or nil when any of it can't be read.
local function MinimapRect()
	local left, bottom = Minimap:GetLeft(), Minimap:GetBottom()
	local width, scale = Minimap:GetWidth(), Minimap:GetEffectiveScale()
	if Usable(left) and Usable(bottom) and Usable(width) and Usable(scale) then
		return { left = left, bottom = bottom, width = width, scale = scale }
	end
end

local function LineColor(line)
	local color = line.leftColor
	if Usable(color) and Usable(color.r) and Usable(color.g) and Usable(color.b) then
		return color.r, color.g, color.b
	end
end

-- Dev only: each distinct line and color once, and each name that isn't a known node once.
local function LogLine(text, r, g, b)
	local color = r and ("%.2f %.2f %.2f"):format(r, g, b) or "-"
	ns.dev:LogOnce("line " .. text .. " " .. color, "LINE", text, color)
	for part in text:gmatch("[^\n]+") do
		local name = ns.Lines.Split(part)
		if name ~= "" and not ns.Nodes[name] then
			ns.dev:LogOnce("miss " .. name, "MISS", name)
		end
	end
end

-- The known nodes named under a minimap offset, as from Lines.Parse, or nil. Secret tooltip
-- data (restricted states) reads as nothing.
-- What Lines.Parse made of each tooltip line, by its text: { r, g, b, nodes }. A quest area
-- covers much of the minimap, so most probes of a sweep read the same objective lines, and each
-- is parsed (and, in dev, logged) once instead of at every probe. Emptied when it holds
-- PARSED_MAX texts, so changing quest progress can't grow it without end.
local PARSED_MAX = 200
local parsed, parsedCount = {}, 0

local function Parse(text, r, g, b)
	local entry = parsed[text]
	if entry and entry.r == r and entry.g == g and entry.b == b then
		return entry.nodes
	end
	if ns.dev.enabled then
		local started = debugprofilestop()
		LogLine(text, r, g, b)
		stats.dev = stats.dev + debugprofilestop() - started
	end
	if not entry then
		if parsedCount >= PARSED_MAX then
			wipe(parsed)
			parsedCount = 0
		end
		parsedCount = parsedCount + 1
	end
	local nodes = ns.Lines.Parse(text, r, g, b)
	parsed[text] = { r = r, g = g, b = b, nodes = nodes }
	return nodes
end

local function ReadPoint(rect, ox, oy)
	local half = rect.width / 2
	local started = ns.dev.enabled and debugprofilestop()
	Minimap:UpdateMouseoverAtPoint((rect.left + half + ox) * rect.scale, (rect.bottom + half + oy) * rect.scale)
	local data = C_TooltipInfo.GetMinimapMouseover()
	if started then
		stats.client = stats.client + debugprofilestop() - started
	end
	if not data then
		return nil
	end
	if issecretvalue(data) or issecrettable(data) then
		sweep.blind = true
		return nil
	end
	local lines = data.lines
	if not lines or issecretvalue(lines) or issecrettable(lines) then
		sweep.blind = sweep.blind or lines ~= nil
		return nil
	end
	local nodes
	for _, line in ipairs(lines) do
		local text = Usable(line) and line.leftText or nil
		if Usable(text) then
			local r, g, b = LineColor(line)
			for _, node in ipairs(Parse(text, r, g, b)) do
				nodes = nodes or {}
				table.insert(nodes, node)
			end
		elseif text ~= nil or not Usable(line) then
			sweep.blind = true
		end
	end
	return nodes
end

-- Hit handlers, one per kind of probe. A coarse hit remembers where in the world each name was
-- seen; a fine hit adds the probe's own place to its group's points, once per probe.
local function OnCoarseHit(probe, nodes, x, y)
	for _, node in ipairs(nodes) do
		local seen = sweep.coarse[node.name] or {}
		sweep.coarse[node.name] = seen
		seen[probe.key] = { x = x, y = y }
	end
end

local function OnFineHit(probe, nodes)
	local group = probe.group
	for _, node in ipairs(nodes) do
		if node.name == group.name then
			table.insert(group.points, { x = probe.x, y = probe.y, gray = node.gray })
			return
		end
	end
end

-- Whether the minimap shows the same place in both views: the player hasn't moved, turned or
-- zoomed in between.
local function SameView(a, b)
	return a ~= nil
		and b ~= nil
		and a.mapID == b.mapID
		and a.px == b.px
		and a.py == b.py
		and a.facing == b.facing
		and a.pixelsPerYard == b.pixelsPerYard
end

-- A group's name and coarse keys as one string. Sorts keys.
local function Signature(name, keys)
	table.sort(keys)
	return name .. ":" .. table.concat(keys, ",")
end

-- Reached after the coarse probes: queues a fine grid, in places, over every group of hits.
-- While the player stands still, a group whose coarse hits are the same as in the last sweep
-- is the same dot, so it takes that sweep's fine hits instead of probing again.
local function Refine(view)
	local unit = view and 1 / view.pixelsPerYard or 1 -- places per minimap pixel
	sweep.unit = unit
	sweep.view = view
	sweep.steady = SameView(view, sweep.start)
	local reuse = sweep.steady
		and kept
		and kept.age < REUSE_SWEEPS
		and SameView(view, kept.view)
		and kept.coarse == sweep.coarseStep
		and kept.fine == sweep.fineStep
	sweep.reusing = reuse
	local reach = sweep.coarseStep * unit
	for name, seen in pairs(sweep.coarse) do
		local keysByGroup, placesByGroup = ns.Grid.Groups(seen), {}
		for i, keys in ipairs(keysByGroup) do
			placesByGroup[i] = {}
			for _, key in ipairs(keys) do
				table.insert(placesByGroup[i], seen[key])
			end
		end
		for i, places in ipairs(placesByGroup) do
			local group = { name = name, points = {}, signature = Signature(name, keysByGroup[i]) }
			table.insert(sweep.groups, group)
			local points = reuse and kept.groups[group.signature]
			if points then
				group.points = points
				sweep.reused = sweep.reused + 1
			else
				local others = {}
				for j, theirs in ipairs(placesByGroup) do
					if j ~= i then
						for _, place in ipairs(theirs) do
							table.insert(others, place)
						end
					end
				end
				local cover = ns.Grid.Cover(places, reach, sweep.fineStep * unit)
				for _, point in ipairs(ns.Grid.Claim(cover, places, others, reach)) do
					table.insert(sweep.queue, { x = point.x, y = point.y, group = group, onHit = OnFineHit })
				end
			end
		end
	end
end

-- Works through the next batch of the queue. Runs with the soft cursor on, under pcall.
local function Advance()
	local view = ns.Scanner.CurrentView()
	local rect = MinimapRect()
	-- A new map, or gaining or losing a map position, makes the places so far meaningless.
	if not rect or (view and view.mapID or false) ~= sweep.mapID then
		sweep, wait = nil, 0
		return
	end
	local reach = rect.width / 2
	local budget = PROBES_PER_FRAME
	while budget > 0 and sweep.at <= #sweep.queue do
		local probe = sweep.queue[sweep.at]
		sweep.at = sweep.at + 1
		if probe.onReach then
			probe.onReach(view)
		else
			budget = budget - 1
			local ox, oy = probe.ox, probe.oy
			if probe.x then
				ox, oy = ToOffset(probe.x, probe.y, view)
			end
			if ox * ox + oy * oy <= reach * reach then
				if probe.x then
					sweep.fineProbes = sweep.fineProbes + 1
				else
					sweep.coarseProbes = sweep.coarseProbes + 1
				end
				local nodes = ReadPoint(rect, ox, oy)
				if nodes then
					probe.onHit(probe, nodes, ToPlace(ox, oy, view))
				end
			end
		end
	end
end

-- After the last probe: the groups' fine hits become dots, the dots markers.
local function Settle()
	local unit = sweep.unit or 1
	local cellArea = (sweep.fineStep * unit) ^ 2

	-- One dot's area first, from this sweep's round groups, which are mostly lone dots: their
	-- median, so a round cluster of several nodes can't skew it. With a single round group it
	-- only pulls the estimate halfway; with none the estimate stays.
	local roundAreas = {}
	for _, group in ipairs(sweep.groups) do
		if #group.points > 0 and ns.Grid.IsRound(group.points) then
			table.insert(roundAreas, ns.Grid.DotArea(group.points, cellArea) / (unit * unit))
		end
	end
	table.sort(roundAreas)
	local median = roundAreas[math.floor((#roundAreas + 1) / 2)]
	if median then
		local learned = #roundAreas >= 2 and median or (dotArea + median) / 2
		dotArea = math.max(MIN_AREA, math.min(MAX_AREA, learned))
	end
	local areaInPlaces = dotArea * unit * unit

	local dotsByName, pointsByName = {}, {}
	for _, group in ipairs(sweep.groups) do
		local dots, round = ns.Grid.Dots(group.points, cellArea, areaInPlaces)
		local area = ns.Grid.DotArea(group.points, cellArea) / (unit * unit)
		dotsByName[group.name] = dotsByName[group.name] or {}
		pointsByName[group.name] = pointsByName[group.name] or {}
		for _, dot in ipairs(dots) do
			table.insert(dotsByName[group.name], dot)
		end
		for _, point in ipairs(group.points) do
			table.insert(pointsByName[group.name], point)
		end
		if ns.dev.enabled and #dots > 0 then
			local radius = math.floor(math.sqrt(area / #dots / math.pi) + 0.5)
			ns.dev:LogOnce(
				("dot %s %d %d"):format(group.name, radius, #dots),
				"DOT",
				group.name,
				"radius",
				radius,
				"round",
				round,
				"dots",
				#dots
			)
		end
	end

	-- The same dot found by two groups (the minimap moved under the coarse pass) is one dot.
	local markers = {}
	local apart = math.sqrt(areaInPlaces / math.pi)
	for name, dots in pairs(dotsByName) do
		local merged = ns.Grid.Merge(dots, apart)
		local grays, totals = {}, {}
		for _, point in ipairs(pointsByName[name]) do
			local nearest = ns.Grid.Nearest(point, merged)
			totals[nearest] = (totals[nearest] or 0) + 1
			grays[nearest] = (grays[nearest] or 0) + (point.gray and 1 or 0)
		end
		for i, dot in ipairs(merged) do
			local gray = (grays[i] or 0) * 2 > (totals[i] or 0)
			if sweep.mapID then
				table.insert(markers, {
					kind = ns.Nodes[name],
					item = ns.NodeItems[name],
					gray = gray,
					mapID = sweep.mapID,
					mapX = dot.x / sweep.width,
					mapY = dot.y / sweep.height,
				})
			else
				table.insert(
					markers,
					{ kind = ns.Nodes[name], item = ns.NodeItems[name], gray = gray, ox = dot.x, oy = dot.y }
				)
			end
		end
	end
	ns.Markers.Replace(markers)

	-- Kept only when the player stood still through the whole sweep and every probe could be
	-- read: a move during the fine pass can push some of its probes off the minimap, and a
	-- restricted state can hide what is under them, and either leaves a group short of hits.
	local age = sweep.reusing and kept.age + 1 or 0
	kept = nil
	if sweep.steady and not sweep.blind and SameView(ns.Scanner.CurrentView(), sweep.view) then
		kept = { view = sweep.view, coarse = sweep.coarseStep, fine = sweep.fineStep, age = age, groups = {} }
		for _, group in ipairs(sweep.groups) do
			kept.groups[group.signature] = group.points
		end
	end

	empties = #markers == 0 and empties + 1 or 0
	wait = math.min(INTERVAL_LONGEST, (sweep.moved and INTERVAL_MOVING or INTERVAL_STILL) * 2 ^ empties)
	if ns.dev.enabled then
		sweeps = sweeps + 1
		stats.sweeps, stats.dots = stats.sweeps + 1, stats.dots + #markers
		stats.coarse, stats.fine = stats.coarse + sweep.coarseProbes, stats.fine + sweep.fineProbes
		stats.reused = stats.reused + sweep.reused
		if sweeps == 1 or sweeps % SUMMARY_EVERY == 0 then
			local n = stats.sweeps
			ns.log(
				"SCAN",
				(
					"sweeps %d, per sweep of the last %d: %.0f+%.0f probes (grid %d/%d px) %.1f dots "
					.. "%.1f groups reused %.2f ms (client %.2f, dev %.2f); worst frame %.2f ms; dot radius %.1f px; "
					.. "%.2f ms per second over %.0f s"
				):format(
					sweeps,
					n,
					stats.coarse / n,
					stats.fine / n,
					sweep.coarseStep,
					sweep.fineStep,
					stats.dots / n,
					stats.reused / n,
					stats.ms / n,
					stats.client / n,
					stats.dev / n,
					stats.worst,
					math.sqrt(dotArea / math.pi),
					stats.ms / math.max(1, GetTime() - stats.since),
					GetTime() - stats.since
				)
			)
			ResetStats()
		end
	end
	sweep = nil
end

-- A new sweep: the coarse grid at fixed minimap offsets, then the fine pass (Refine).
local function Begin()
	local rect = MinimapRect()
	if not rect then
		wait = PAUSE
		return
	end
	local view = ns.Scanner.CurrentView()
	local moved = true
	if view then
		moved = view.px ~= last.x or view.py ~= last.y or math.abs(view.facing - (last.facing or 0)) > TURN
		last.x, last.y, last.facing = view.px, view.py, view.facing
	end
	local coarseStep, fineStep = Spacings()
	if layoutWidth ~= rect.width or layoutStep ~= coarseStep then
		layout, layoutWidth, layoutStep = ns.Grid.Points(rect.width, coarseStep), rect.width, coarseStep
	end
	sweep = {
		mapID = view and view.mapID or false,
		width = view and view.width,
		height = view and view.height,
		moved = moved,
		start = view,
		coarseStep = coarseStep,
		fineStep = fineStep,
		queue = {},
		at = 1,
		coarse = {},
		groups = {},
		coarseProbes = 0, -- dev only: probes read, coarse and fine, and groups that kept their fine hits
		fineProbes = 0,
		reused = 0,
	}
	local half = rect.width / 2
	for _, key in ipairs(layout) do
		local ox, oy = math.floor(key / 1000) * coarseStep - half, key % 1000 * coarseStep - half
		table.insert(sweep.queue, { ox = ox, oy = oy, key = key, onHit = OnCoarseHit })
	end
	table.insert(sweep.queue, { onReach = Refine })
end

-- One frame of a sweep. The soft cursor is on only inside it, and goes off even when something
-- fails: then the sweep is dropped, the error reported once, and the next sweep waits.
local function Step()
	local started = ns.dev.enabled and debugprofilestop()
	Minimap:SetUsingSoftCursor(true)
	local ok, err = pcall(Advance)
	Minimap:SetUsingSoftCursor(false)
	if not ok then
		sweep, wait = nil, INTERVAL_LONGEST
		geterrorhandler()(err)
		return
	end
	if sweep and sweep.at > #sweep.queue then
		ok, err = pcall(Settle)
		if not ok then
			sweep, wait = nil, INTERVAL_LONGEST
			geterrorhandler()(err)
			return
		end
	end
	if started then
		local ms = debugprofilestop() - started
		stats.ms, stats.worst = stats.ms + ms, math.max(stats.worst, ms)
	end
end

local function Enabled()
	return ns.Options.Get("showNodeIcons") and ns.Tracking.IsFinding()
end

-- Starts a new sweep at the next frame, dropping one that is half done, and probes every group
-- again: what called it (looting, zooming, a new zone, a changed option) may have changed them.
function ns.Scanner.ScanSoon()
	sweep, wait, empties, kept = nil, 0, 0, nil
end

-- Every frame while the minimap is shown (the frame is its child): a sweep, or the wait for it.
-- Sweeps go on in combat; nothing they call is blocked there.
local function OnUpdate(_, elapsed)
	if not Enabled() then
		if not cleared then
			sweep, cleared = nil, true
			ns.Markers.Replace({})
		end
		return
	end
	cleared = false
	-- Never move the minimap's mouseover while the player's own mouse is on it.
	local over = Minimap:IsMouseOver()
	if issecretvalue(over) or over then
		sweep = nil
		wait = math.max(wait, PAUSE)
		return
	end
	if sweep then
		Step()
		return
	end
	wait = wait - elapsed
	if wait <= 0 then
		Begin()
	end
end

local events = {}

-- The node looted just now is gone: drop its icon at once, then look again. At far zoom a pixel
-- is several yards, so the reach is at least two pixels.
function events.LOOT_CLOSED()
	local pixelsPerYard = ns.Scanner.PixelsPerYard()
	if pixelsPerYard then
		local reach = math.max(REACH, 2 / pixelsPerYard)
		local removed, nearest = ns.Markers.RemoveNearPlayer(reach, pixelsPerYard)
		ns.log("LOOT", "removed", removed, "nearest", nearest, "reach", reach)
	end
	ns.Scanner.ScanSoon()
end

-- Zooming moves every dot on the minimap.
function events.MINIMAP_UPDATE_ZOOM()
	ns.Scanner.ScanSoon()
end

-- A new zone or a loading screen: old icons belong to another place.
function events.PLAYER_ENTERING_WORLD()
	ns.Markers.Replace({})
	ns.Scanner.ScanSoon()
end
events.ZONE_CHANGED_NEW_AREA = events.PLAYER_ENTERING_WORLD

ns.OnInitialize(function()
	local frame = CreateFrame("Frame", nil, Minimap)
	for event in pairs(events) do
		frame:RegisterEvent(event)
	end
	frame:SetScript("OnEvent", function(_, event)
		events[event]()
	end)
	frame:SetScript("OnUpdate", OnUpdate)
	-- Hidden (Alt+Z, or the minimap toggled off), sweeps stop, and the player may be somewhere
	-- else by the time it shows: drop the half-done sweep so the first one after is whole. The
	-- markers stay, since they are drawn from where the player is then.
	frame:SetScript("OnHide", function()
		ns.log("SCAN", "minimap hidden, sweep dropped:", sweep ~= nil)
		ns.Scanner.ScanSoon()
	end)
	ns.callbacks:RegisterCallback("TrackingChanged", ns.Scanner.ScanSoon)
	ns.callbacks:RegisterCallback("OptionChanged", ns.Scanner.ScanSoon)
end)
