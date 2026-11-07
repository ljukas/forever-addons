local ADDON_NAME, ns = ...

-- Draws known nodes near the player on the minimap. There is no pin framework for the
-- minimap, so pins are placed by hand with the yards-to-pixels scale Blizzard's hybrid
-- minimap uses (Blizzard_HybridMinimap.lua: UpdateZoom).

local UPDATE_INTERVAL = 0.1
-- The pin template is 32px; minimap pins are drawn at half size.
local PIN_SCALE = 0.5
-- Keeps whole pins inside the round minimap.
local PIN_RADIUS_PIXELS = 8
-- A pin's size on the minimap, in minimap pixels: nodes closer than this share a pin.
local PIN_PIXELS = 32 * PIN_SCALE

local container = CreateFrame("Frame", nil, Minimap)
container:SetAllPoints()

local function ResetPin(pool, pin)
	pin:HideOwnedTooltip()
	Pool_HideAndClearAnchors(pool, pin)
end
local pool = CreateUnsecuredFramePool("Frame", container, "ForeverProfessionsMinimapPinTemplate", ResetPin)

-- Active pins by node key, so a pin under the cursor survives updates while moving.
local pinsByKey = {}
local generation = 0

-- What the pins were last drawn for. Draw is skipped while none of it changes.
local drawn = {}
local dirty = true
local sinceUpdate = 0

local function ReleaseAll()
	pool:ReleaseAll()
	wipe(pinsByKey)
	wipe(drawn)
end

local function GetFacing()
	if not CVarCallbackRegistry:GetCVarValueBool("rotateMinimap") then
		return 0
	end
	return GetPlayerFacing() or 0
end

local function Draw(mapID, px, py, facing, radius)
	local width, height = ns.GetMapSize(mapID)
	local pixelsPerYard = Minimap:GetWidth() / (2 * radius)
	local maxYards = radius - PIN_RADIUS_PIXELS / pixelsPerYard
	-- A rotating minimap keeps the player's facing up: rotate offsets clockwise by it.
	-- Facing is radians counter-clockwise from north.
	local sin, cos = math.sin(facing), math.cos(facing)

	generation = generation + 1
	-- The nodes in range, at their minimap pixel offsets (y growing southwards, down the
	-- minimap); those whose pins would overlap are merged (Clusters.lua).
	local nodes, points = {}, {}
	ns.Layers.ForEachShownNode(mapID, function(layer, name, index, x, y, count)
		-- Yards east and north of the player. Map y grows southwards.
		local dx = (x - px) * width
		local dy = (py - y) * height
		if dx * dx + dy * dy > maxYards * maxYards then
			return
		end
		table.insert(nodes, { layer = layer, name = name, key = name .. index, x = x, y = y, count = count })
		table.insert(points, {
			x = (dx * cos + dy * sin) * pixelsPerYard,
			y = -(dy * cos - dx * sin) * pixelsPerYard,
		})
	end)

	local pins = ns.Clusters.Pins(nodes, points, PIN_PIXELS)
	-- Group gives each pin its anchor's point; its nodes keep their order in nodes, so the
	-- anchor's point is found by key.
	local pointsByKey = {}
	for i, node in ipairs(nodes) do
		pointsByKey[node.key] = points[i]
	end
	for _, data in ipairs(pins) do
		local pin = pinsByKey[data.key]
		if not pin then
			pin = pool:Acquire() --[[@as ForeverProfessionsPinMixin]]
			pin:SetScale(PIN_SCALE)
			pin:Show()
			pinsByKey[data.key] = pin
		end
		pin:SetPin(data)
		pin.generation = generation
		-- SetPoint offsets are in the pin's own (scaled) units.
		local point = pointsByKey[data.key]
		pin:SetPoint("CENTER", Minimap, "CENTER", point.x / PIN_SCALE, -point.y / PIN_SCALE)
	end

	for key, pin in pairs(pinsByKey) do
		if pin.generation ~= generation then
			pool:Release(pin)
			pinsByKey[key] = nil
		end
	end
end

local function Update()
	local mapID, px, py = ns.GetPlayerMapPosition()
	if not ns.Options.Get("showMinimap") or not mapID or not ns.GetMapSize(mapID) then
		ReleaseAll()
		return
	end

	local facing = GetFacing()
	local radius = C_Minimap.GetViewRadius()
	if
		not dirty
		and mapID == drawn.mapID
		and px == drawn.x
		and py == drawn.y
		and facing == drawn.facing
		and radius == drawn.radius
	then
		return
	end
	if mapID ~= drawn.mapID then
		ReleaseAll()
	end

	dirty = false
	drawn.mapID, drawn.x, drawn.y, drawn.facing, drawn.radius = mapID, px, py, facing, radius
	Draw(mapID, px, py, facing, radius)
end

local function MarkDirty()
	dirty = true
end

ns.OnInitialize(function()
	ns.callbacks:RegisterCallback("NodesChanged", MarkDirty)
	ns.callbacks:RegisterCallback("OptionChanged", MarkDirty)
	ns.callbacks:RegisterCallback("SkillsChanged", MarkDirty)

	-- Only runs while the minimap is shown, since the container is its child.
	container:SetScript("OnUpdate", function(_, elapsed)
		sinceUpdate = sinceUpdate + elapsed
		if sinceUpdate >= UPDATE_INTERVAL then
			sinceUpdate = 0
			Update()
		end
	end)
end)
