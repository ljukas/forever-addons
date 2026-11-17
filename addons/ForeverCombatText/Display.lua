local ADDON_NAME, ns = ...

-- Draws the player's combat text in a box the player places in Edit Mode (EditMode.lua). Blizzard's
-- CombatText frame keeps deciding what to show, how it's worded and its colour; a secure hook on
-- its AddMessage hands each message to us, and its own copy is made invisible. Nothing is written
-- on Blizzard's frame or tables, so its handling of secret amounts stays untainted
-- (docs/adr/0003-move-combat-text-by-mirroring-blizzards-messages.md).
ns.Display = {}

local Scroll = ns.Scroll
local MODE = Scroll.MODE

-- The box is as tall as the text scrolls; its width is only something to grab.
local WIDTH = 200
-- As many lines as Blizzard's pool holds (CombatTextConstants.NumCombatTextLines).
local MAX_LINES = 20
-- CombatTextConstants.StaggerRange, and the sideways step of a line that can't start further back
-- (CombatTextMixin's textOffsetAdjustment).
local STAGGER_RANGE = 20
local SIDE_STEP = 80
-- Blizzard puts a new line's top one line below 384 on a 768-high world frame, in UIParent units
-- (CombatTextMixin:UpdateDisplayedMessages, AddMessage); ours are placed by their centre.
local BLIZZARD_START = 384
local BLIZZARD_START_BELOW = 37

-- The box and settings for an Edit Mode layout with nothing saved: where and how Blizzard draws.
ns.Display.DEFAULTS = {
	point = "BOTTOM",
	x = 0,
	y = math.floor(BLIZZARD_START * WorldFrame:GetHeight() / 768 - BLIZZARD_START_BELOW + 0.5),
	length = 225,
	duration = 1.9,
	fontSize = 25,
}

local DEFAULTS = ns.Display.DEFAULTS

local length, duration, fontSize = DEFAULTS.length, DEFAULTS.duration, DEFAULTS.fontSize

local holder = CreateFrame("Frame", nil, UIParent)
holder:SetSize(WIDTH, length)
holder:SetPoint(DEFAULTS.point, UIParent, DEFAULTS.point, DEFAULTS.x, DEFAULTS.y)
ns.Display.holder = holder

-- The lines on screen, oldest first, and the font strings waiting to be used again.
local active = {}
local free = {}
-- Lines alternate which way they arc, and side steps alternate sides.
local xDir = 1
local sideStep = SIDE_STEP

-- The direction set under Options > Combat.
function ns.Display.Mode()
	return Scroll.ModeFromCVar(C_CVar.GetCVar("floatingCombatTextFloatMode_v2"))
end

local function Place(line, x, travel)
	if line.mode == MODE.DOWN then
		line:SetPoint("CENTER", holder, "TOP", x, -travel)
	else
		line:SetPoint("CENTER", holder, "BOTTOM", x, travel)
	end
end

local function OnUpdate(_, elapsed)
	for index = #active, 1, -1 do
		local line = active[index]
		line.time = line.time + elapsed
		if line.time >= duration then
			line:Hide()
			table.remove(active, index)
			table.insert(free, line)
		else
			local x, travel = Scroll.Position(
				line.mode,
				line.time,
				duration,
				length,
				line.startX,
				line.startTravel,
				line.xDir,
				line.stays
			)
			line.travel = travel
			Place(line, x, travel)
			line:SetAlpha(Scroll.Alpha(line.time, duration))
			if line.isCrit then
				line:SetTextHeight(Scroll.CritHeight(line.time, fontSize))
			end
		end
	end
	if #active == 0 then
		holder:SetScript("OnUpdate", nil)
	end
end

-- A line of text on its way through the box.
---@class ForeverCombatTextLine : FontString
---@field mode number ns.Scroll.MODE, fixed when the line starts
---@field time number seconds since it started
---@field startX number
---@field startTravel number
---@field travel number where it is now
---@field xDir number 1 or -1, the side an arc bends to
---@field isCrit boolean
---@field stays boolean a crit or sticky line doesn't scroll

---@return ForeverCombatTextLine
local function AcquireLine()
	local line = table.remove(free)
	if not line then
		line = holder:CreateFontString(nil, "OVERLAY") --[[@as ForeverCombatTextLine]]
		line:SetFontObject(CombatTextFont)
	end
	return line
end

-- Starts a line. message may be a secret string: it is only handed to SetText. displayType is
-- Blizzard's: "crit", "sticky" or nil.
function ns.Display.Add(message, r, g, b, displayType, isStaggered)
	if #active >= MAX_LINES then
		return
	end
	local isCrit = displayType == "crit"
	local travels = {}
	for index, line in ipairs(active) do
		travels[index] = line.travel
	end
	local startTravel, steppedAside = Scroll.StartTravel(travels, fontSize, isCrit)

	local startX = 0
	if isStaggered then
		startX = math.random(0, STAGGER_RANGE) - STAGGER_RANGE / 2
	end
	xDir = -xDir
	if steppedAside then
		sideStep = -sideStep
		startX = startX + sideStep
		xDir = sideStep > 0 and -1 or 1
	end

	local line = AcquireLine()
	line.mode = ns.Display.Mode()
	line.time = 0
	line.startX = startX
	line.startTravel = startTravel
	line.travel = startTravel
	line.xDir = xDir
	line.isCrit = isCrit
	line.stays = isCrit or displayType == "sticky"
	line:SetText(message)
	line:SetTextColor(r, g, b)
	line:SetTextHeight(isCrit and Scroll.CritHeight(0, fontSize) or fontSize)
	line:SetAlpha(1)
	line:ClearAllPoints()
	Place(line, startX, startTravel)
	line:Show()
	table.insert(active, line)
	holder:SetScript("OnUpdate", OnUpdate)
end

-- Places and sizes the box and sets how lines move: { point, x, y, length, duration, fontSize }.
-- Lines already on screen keep their size and follow the new length and duration.
function ns.Display.SetLayout(layout)
	length, duration, fontSize = layout.length, layout.duration, layout.fontSize
	holder:SetSize(WIDTH, length)
	holder:ClearAllPoints()
	holder:SetPoint(layout.point, UIParent, layout.point, layout.x, layout.y)
end

-- Runs after Blizzard's CombatTextMixin:AddMessage(message, scrollFunction, r, g, b, displayType,
-- isStaggered). The colour and flags come from Blizzard's own tables, not from the game; should a
-- build ever hand them over secret, the line is white, plain and unstaggered.
local function OnMessage(_, message, _, r, g, b, displayType, isStaggered)
	if not issecretvalue(message) and message == nil then
		return
	end
	if
		issecretvalue(r)
		or issecretvalue(g)
		or issecretvalue(b)
		or type(r) ~= "number"
		or type(g) ~= "number"
		or type(b) ~= "number"
	then
		r, g, b = 1, 1, 1
	end
	if issecretvalue(displayType) then
		displayType = nil
	end
	if issecretvalue(isStaggered) then
		isStaggered = nil
	end
	if ns.dev.enabled then
		local secret = issecretvalue(message)
		local key = strjoin(":", tostring(secret), tostring(displayType), r, g, b)
		ns.dev:LogOnce(
			key,
			"MSG",
			"secret",
			secret,
			"color",
			r,
			g,
			b,
			displayType,
			isStaggered,
			"mode",
			ns.Display.Mode()
		)
	end
	ns.Display.Add(message, r, g, b, displayType, isStaggered)
end

ns.OnInitialize(function()
	-- Load-on-demand: the client loads it when Scrolling Combat Text for Self is on. Runs at once
	-- if it already has.
	EventUtil.ContinueOnAddOnLoaded("Blizzard_CombatText", function()
		if not CombatText or type(CombatText.AddMessage) ~= "function" then
			-- Blizzard's text stays as it is.
			ns.log("HOOK", "missing", CombatText and "AddMessage" or "CombatText")
			return
		end
		hooksecurefunc(CombatText, "AddMessage", OnMessage)
		-- Invisible, not hidden: a hidden CombatText drops its events.
		CombatText:SetAlpha(0)
		ns.log("HOOK", "hooked")
	end)
end)
