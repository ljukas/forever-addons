local ADDON_NAME, ns = ...

-- The animation maths, ported from Blizzard's CombatText.lua and CombatTextUtil.lua with the
-- player's settings in place of its constants. Plain numbers in and out, no frames.
--
-- "Travel" is how far a line is from the box's start edge along the direction it scrolls: 0 on
-- the edge, negative behind it. Display.lua turns it into an offset up or down.
ns.Scroll = {}

local Scroll = ns.Scroll

Scroll.MODE = { UP = 1, DOWN = 2, ARC = 3 }

local MODE = Scroll.MODE

-- Blizzard's numbers (CombatTextConstants.lua, CombatTextMixin:OnLoad), for the defaults of 225
-- travelled in 1.9 seconds at text height 25.
local BLIZZARD_LENGTH = 225
local BLIZZARD_DURATION = 1.9
local BLIZZARD_FADE_START = 1.3
local BLIZZARD_HEIGHT = 25
local ARC_RADIUS = 150
local CRIT_MIN, CRIT_MAX = 30, 60
local CRIT_GROW_TIME, CRIT_SHRINK_TIME = 0.05, 0.2
-- A new line starts this far behind the one before it, plus the spacing; never further back than
-- the limit. Blizzard measures the limit from 384 (see Display.lua), where a line scrolling down
-- starts; scrolling up or in an arc a line starts one line (25) beyond that, so the limit is a
-- line nearer.
local LINE_GAP = 16
local LINE_SPACING = 10
local BEHIND_LIMIT = 130

-- The direction for the floatingCombatTextFloatMode_v2 CVar's value, as in
-- CombatTextMixin:UpdateDisplayedMessages: "1" up, "2" down, anything else an arc.
function Scroll.ModeFromCVar(value)
	if value == "1" then
		return MODE.UP
	elseif value == "2" then
		return MODE.DOWN
	end
	return MODE.ARC
end

-- Where a line is t seconds in: its sideways offset and its travel. A line that stays (a crit)
-- doesn't move, as Blizzard's crits don't.
function Scroll.Position(mode, t, duration, length, startX, startTravel, xDir, stays)
	if stays then
		return startX, startTravel
	end
	local progress = t / duration
	if mode == MODE.ARC then
		local radius = length * ARC_RADIUS / BLIZZARD_LENGTH
		local angle = math.rad(90 * progress)
		return startX - xDir * radius * (1 - math.cos(angle)), startTravel + radius * math.sin(angle)
	end
	return startX, startTravel + length * progress
end

-- Opaque for the first 1.3 / 1.9 of its life, then fading out evenly.
function Scroll.Alpha(t, duration)
	local fadeStart = duration * BLIZZARD_FADE_START / BLIZZARD_DURATION
	if t <= fadeStart then
		return 1
	end
	return math.max(1 - (t - fadeStart) / (duration - fadeStart), 0)
end

-- A crit's text height t seconds in: it pops to double size and settles back. The second return
-- is true once it has settled.
function Scroll.CritHeight(t, fontSize)
	local small = fontSize * CRIT_MIN / BLIZZARD_HEIGHT
	local big = fontSize * CRIT_MAX / BLIZZARD_HEIGHT
	if t <= CRIT_GROW_TIME then
		return small + (big - small) * t / CRIT_GROW_TIME, false
	elseif t <= CRIT_SHRINK_TIME then
		return big - (big - small) * (t - CRIT_GROW_TIME) / (CRIT_SHRINK_TIME - CRIT_GROW_TIME), false
	end
	return small, true
end

-- Where a new line starts so it doesn't cover the ones still near the start (activeTravels: the
-- travel of each line on screen): behind the last of them. Past the limit a crit starts on the
-- edge anyway, and any other line starts at the limit and, second return, steps sideways.
function Scroll.StartTravel(activeTravels, fontSize, isCrit, mode)
	local gap = LINE_GAP * fontSize / BLIZZARD_HEIGHT + LINE_SPACING
	local limit = BEHIND_LIMIT
	if mode ~= MODE.DOWN then
		limit = limit - BLIZZARD_HEIGHT
	end
	local start = 0
	for _, travel in ipairs(activeTravels) do
		if start >= travel - gap then
			start = travel - gap
		end
	end
	if start < -limit then
		if isCrit then
			return 0, false
		end
		return -limit, true
	end
	return start, false
end

-- How far the box's anchor offset must move up when its height changes from oldLength to
-- newLength, so its start edge (the bottom, or the top when text scrolls down) stays where it is.
-- point is the anchor point the box is placed by.
function Scroll.ShiftForLength(point, oldLength, newLength, mode)
	local grown = newLength - oldLength
	-- How much of the growth the anchor leaves below it: none anchored by the bottom, all by the top.
	local below = 0.5
	if point:find("BOTTOM", 1, true) then
		below = 0
	elseif point:find("TOP", 1, true) then
		below = 1
	end
	if mode == MODE.DOWN then
		-- The top stays: the growth above the anchor is taken back.
		return -grown * (1 - below)
	end
	return grown * below
end
