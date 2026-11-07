local ADDON_NAME, ns = ...

-- Dev only: whether this client lets addons probe the minimap again. Since client 1.60.1.70862
-- (Scanner.lua, BLOCKED_FROM_BUILD) Minimap:UpdateMouseoverAtPoint no longer moves the minimap's
-- mouseover for addons. Ruled out in game on 2026-11-07: eight other coordinate spaces (screen,
-- physical pixels, minimap-local, centered, normalized), reading a frame later with the soft
-- cursor held on, and probing from a frame with no parent or a C_Timer callback instead of a
-- child of the minimap.
--
-- So on such a client this probes a grid over the minimap every EVERY seconds, with the mouse
-- off it, and logs how many points named something whenever that changes (COORD tag). A count
-- above 0 with no hover just before means probing works again, and BLOCKED_FROM_BUILD can go.
if not ns.dev.enabled or not ns.Scanner.Blocked() then
	return
end

local EVERY = 30
local STEP = 10 -- minimap units between probes

local function Text(data)
	if not data or issecretvalue(data) or issecrettable(data) then
		return nil
	end
	local lines = data.lines
	if not lines or issecretvalue(lines) or issecrettable(lines) or not lines[1] then
		return nil
	end
	local text = lines[1].leftText
	if text == nil or issecretvalue(text) then
		return "?"
	end
	return text
end

local function MouseOnMinimap()
	local over = Minimap:IsMouseOver()
	return issecretvalue(over) or over
end

local function Probe(source)
	if MouseOnMinimap() or not Minimap:IsVisible() then
		return
	end
	local left, bottom = Minimap:GetLeft(), Minimap:GetBottom()
	local width, scale = Minimap:GetWidth(), Minimap:GetEffectiveScale()
	if not (left and bottom and width and scale) then
		return
	end
	local hits, points, first = 0, 0, nil
	Minimap:SetUsingSoftCursor(true)
	local ok, err = pcall(function()
		for x = STEP / 2, width, STEP do
			for y = STEP / 2, width, STEP do
				points = points + 1
				Minimap:UpdateMouseoverAtPoint((left + x) * scale, (bottom + y) * scale)
				local text = Text(C_TooltipInfo.GetMinimapMouseover())
				if text then
					hits = hits + 1
					first = first or text
				end
			end
		end
	end)
	Minimap:SetUsingSoftCursor(false)
	if not ok then
		ns.log("COORD", source, "error", err)
		return
	end
	ns.dev:LogChanged(
		"coord " .. source,
		hits,
		"COORD",
		("%s: %d of %d points named something %s"):format(source, hits, points, first or "")
	)
end

C_Timer.NewTicker(EVERY, function()
	Probe("probe")
end)
