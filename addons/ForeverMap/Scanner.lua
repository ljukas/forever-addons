local ADDON_NAME, ns = ...

-- Finds the herb and ore tracking dots on the minimap (ADR 0001). The client tells addons
-- nothing about tracked nodes, but the minimap names what is under a point: with its soft cursor
-- on, Minimap:UpdateMouseoverAtPoint moves the minimap's mouseover there and
-- C_TooltipInfo.GetMinimapMouseover reads the names. A scan probes a coarse grid over the
-- minimap, a batch of points per frame, then probes each group of hits again on a fine grid to
-- place its dots (Logic/Grid.lua), and hands them to Markers.lua.
--
-- Log tags: SCAN per scan, DOT per dot, LINE per distinct tooltip line, MISS per name under a
-- probe that isn't in Data/Nodes.lua.
ns.Scanner = {}

local STEP = 8 -- coarse grid spacing, minimap pixels
local FINE = 2 -- fine grid spacing
local PER_FRAME = 60 -- probes per frame
local INTERVAL_MOVING = 0.5 -- seconds between scans while the player moves
local INTERVAL_STILL = 1.5 -- and while standing still
local MAX_INTERVAL = 3 -- the wait doubles after each scan that found nothing, up to this
local PAUSED = 0.25 -- seconds between checks while the mouse is over the minimap
local GATHER_YARDS = 5 -- how near the player a node gathered just now is

-- The area one dot's hits cover, learned from round groups (Grid.Dots). Starts at a guess and
-- stays within limits, both in pixels.
local MIN_DOT_AREA, MAX_DOT_AREA = math.pi * 3 ^ 2, math.pi * 24 ^ 2
local dotArea = math.pi * 8 ^ 2

local scan -- the scan running now, or nil
local wait = 0 -- seconds until the next scan
local empties = 0 -- scans in a row that found nothing
local lastX, lastY -- the player's map position when the last scan started
local grid, gridWidth -- the coarse grid, kept until the minimap's size changes

local function Usable(value)
	return value ~= nil and not issecretvalue(value)
end

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

-- Where the minimap is on screen, for turning grid points into probe coordinates; nil when any
-- of it can't be read.
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

-- Dev only: each distinct line once, and each name that isn't a known node once.
local function LogLine(text, r, g, b)
	ns.dev:LogOnce("line " .. text, "LINE", text, r, g, b)
	for part in text:gmatch("[^\n]+") do
		local name = ns.Lines.Clean(part)
		if name ~= "" and not ns.Nodes[name] then
			ns.dev:LogOnce("miss " .. name, "MISS", name)
		end
	end
end

-- Moves the minimap's mouseover to a grid point (pixels from the minimap's bottom left) and
-- returns the known nodes named there, as from Lines.Parse, or nil.
local function Probe(rect, x, y)
	Minimap:UpdateMouseoverAtPoint((rect.left + x) * rect.scale, (rect.bottom + y) * rect.scale)
	local data = C_TooltipInfo.GetMinimapMouseover()
	if not data or issecretvalue(data) then
		return nil
	end
	local lines = data.lines
	if not lines or issecretvalue(lines) then
		return nil
	end
	local found
	for _, line in ipairs(lines) do
		local text = Usable(line) and line.leftText
		if Usable(text) then
			local r, g, b = LineColor(line)
			if ns.dev.enabled then
				LogLine(text, r, g, b)
			end
			for _, node in ipairs(ns.Lines.Parse(text, r, g, b)) do
				found = found or {}
				table.insert(found, node)
			end
		end
	end
	return found
end

local function StartScan(rect)
	if gridWidth ~= rect.width then
		grid, gridWidth = ns.Grid.Points(rect.width, STEP), rect.width
	end
	local view = ns.Scanner.CurrentView()
	local moved = true
	if view then
		moved = view.px ~= lastX or view.py ~= lastY
		lastX, lastY = view.px, view.py
	end
	scan = { rect = rect, next = 1, hits = {}, dots = {}, moved = moved, probes = 0 }
	if ns.dev.enabled then
		scan.started = debugprofilestop()
	end
end

-- After the coarse pass: one fine job per group of touching hits of the same name.
local function StartJobs()
	scan.jobs, scan.job = {}, 1
	for name, set in pairs(scan.hits) do
		for _, group in ipairs(ns.Grid.Groups(set)) do
			local points = ns.Grid.FinePoints(group, STEP, FINE)
			table.insert(scan.jobs, { name = name, points = points, next = 1, keys = {}, gray = 0 })
		end
	end
end

-- A job's fine hits become dots. Each dot keeps the view of this moment, so the player moving
-- during a scan shifts it by a frame or two at most.
local function EndJob(job)
	local dots, round = ns.Grid.Dots(job.keys, FINE, dotArea)
	if round and #job.keys > 0 then
		local area = ns.Grid.DotArea(job.keys, FINE)
		dotArea = math.max(MIN_DOT_AREA, math.min(MAX_DOT_AREA, dotArea * 0.8 + area * 0.2))
	end
	local view = ns.Scanner.CurrentView()
	local half = scan.rect.width / 2
	local gray = job.gray * 2 > #job.keys
	for _, dot in ipairs(dots) do
		local ox, oy = dot.x - half, dot.y - half
		table.insert(
			scan.dots,
			{ name = job.name, kind = ns.Nodes[job.name], gray = gray, ox = ox, oy = oy, view = view }
		)
		ns.log("DOT", job.name, ("%.1f %.1f"):format(ox, oy), "area", ns.Grid.DotArea(job.keys, FINE), "round", round)
	end
end

local function FinishScan()
	ns.Markers.Replace(scan.dots)
	empties = #scan.dots == 0 and empties + 1 or 0
	wait = math.min(MAX_INTERVAL, (scan.moved and INTERVAL_MOVING or INTERVAL_STILL) * 2 ^ empties)
	if ns.dev.enabled then
		local ms = debugprofilestop() - scan.started
		ns.log("SCAN", "probes", scan.probes, "jobs", #scan.jobs, "dots", #scan.dots, ("%.1f ms"):format(ms))
	end
	scan = nil
end

-- Probes the next batch: coarse points first, then the fine jobs one after another.
local function ScanSome()
	local rect = scan.rect
	Minimap:SetUsingSoftCursor(true)
	local budget = PER_FRAME
	if not scan.jobs then
		local points = grid
		local last = math.min(scan.next + budget - 1, #points)
		for i = scan.next, last do
			local key = points[i]
			local found = Probe(rect, math.floor(key / 1000) * STEP, key % 1000 * STEP)
			for _, node in ipairs(found or {}) do
				scan.hits[node.name] = scan.hits[node.name] or {}
				scan.hits[node.name][key] = true
			end
		end
		scan.probes = scan.probes + last - scan.next + 1
		scan.next = last + 1
		if scan.next > #points then
			StartJobs()
		end
	else
		while budget > 0 and scan.job <= #scan.jobs do
			local job = scan.jobs[scan.job]
			local last = math.min(job.next + budget - 1, #job.points)
			for i = job.next, last do
				local key = job.points[i]
				for _, node in ipairs(Probe(rect, math.floor(key / 1000) * FINE, key % 1000 * FINE) or {}) do
					if node.name == job.name then
						table.insert(job.keys, key)
						job.gray = job.gray + (node.gray and 1 or 0)
					end
				end
			end
			budget = budget - (last - job.next + 1)
			scan.probes = scan.probes + last - job.next + 1
			job.next = last + 1
			if job.next > #job.points then
				EndJob(job)
				scan.job = scan.job + 1
			end
		end
	end
	-- The soft cursor is only ever on while this function runs.
	Minimap:SetUsingSoftCursor(false)
	if scan.jobs and scan.job > #scan.jobs then
		FinishScan()
	end
end

-- Stops the scan running now; with clear, also removes every icon.
local function Stop(clear)
	scan = nil
	if clear then
		ns.Markers.Replace({})
	end
end

local function Enabled()
	return ns.Options.Get("showNodeIcons") and ns.Tracking.IsFinding()
end

-- Starts a new scan at the next frame, dropping one that is half done.
function ns.Scanner.ScanSoon()
	scan, wait, empties = nil, 0, 0
end

-- Every frame while the minimap is shown (the frame is its child): the scan, or the wait for it.
-- Scanning goes on in combat; nothing it calls is blocked there.
local function OnUpdate(_, elapsed)
	if not Enabled() then
		if scan or wait >= 0 then
			Stop(true)
			wait = -1 -- cleared; ScanSoon starts again
		end
		return
	end
	-- Never move the minimap's mouseover while the player's own mouse is on it.
	if Minimap:IsMouseOver() then
		scan = nil
		wait = math.max(wait, PAUSED)
		return
	end
	if scan then
		ScanSome()
		return
	end
	wait = wait - elapsed
	if wait <= 0 then
		local rect = MinimapRect()
		if rect then
			StartScan(rect)
		else
			wait = PAUSED
		end
	end
end

local events = {}

-- The node looted just now is gone: drop its icon at once, then look again.
function events.LOOT_CLOSED()
	local pixelsPerYard = ns.Scanner.PixelsPerYard()
	if pixelsPerYard then
		ns.Markers.RemoveNearPlayer(GATHER_YARDS, pixelsPerYard)
	end
	ns.Scanner.ScanSoon()
end

-- Zooming moves every dot on the minimap.
function events.MINIMAP_UPDATE_ZOOM()
	ns.Scanner.ScanSoon()
end

-- A new zone or a loading screen: old icons belong to another place.
function events.PLAYER_ENTERING_WORLD()
	Stop(true)
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
	ns.callbacks:RegisterCallback("TrackingChanged", ns.Scanner.ScanSoon)
	ns.callbacks:RegisterCallback("OptionChanged", ns.Scanner.ScanSoon)
end)
