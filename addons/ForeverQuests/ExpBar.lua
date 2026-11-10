local _, ns = ...

-- Draws, on Blizzard's experience bar, where the player's XP lands after turning in every
-- completed quest: a fill from the current XP to that point and a pip at its end, built the
-- way Blizzard draws rested XP (ExhaustionLevelFillBar and ExhaustionTick in
-- Blizzard_StatusTrackingBar/Shared/ExpBar.lua). Each status bar container
-- (MainStatusTrackingBarContainer, SecondaryStatusTrackingBarContainer) has its own exp bar,
-- so both get one.

ns.ExpBar = {}

-- Blizzard's rested fill art, desaturated and tinted so it can't be mistaken for rested XP
-- (blue/purple): gold, or green when the turn-ins level the player up.
local FILL_ATLAS = "UI-HUD-ExperienceBar-Fill-Prediction"
local FILL_COLOR, LEVEL_UP_COLOR = NORMAL_FONT_COLOR, GREEN_FONT_COLOR
local PIP_ATLAS = "UI-HUD-ExperienceBar-Frame-Pip"
local PIP_WIDTH, PIP_HEIGHT = 10, 14
local EDGE_HIDE = 0.99 -- like Blizzard's hideAtBarEdge: no pip right at the bar's end

local bars = {} -- hooked exp bars; each gets bar.ForeverQuestsFill and bar.ForeverQuestsPip

-- The state shared by every bar and the tooltip. Fields:
--   quests = ns.Quests.Collect() result,
--   cur, max, level = the player's XP, the XP the level needs, the level (nil when not drawn),
--   xpSecret = UnitXP or UnitXPMax came back secret,
--   proj = ns.Project(...) result, or nil when nothing is drawn.
ns.ExpBar.lastResult = nil

local function Compute()
	local quests = ns.Quests.Collect()
	local result = { quests = quests }
	if IsXPUserDisabled() or GameRulesUtil.IsPlayerAtEffectiveMaxLevel() then
		return result
	end
	local cur, max = UnitXP("player"), UnitXPMax("player")
	if issecretvalue(cur) or issecretvalue(max) then
		result.xpSecret = true
		return result
	end
	result.cur, result.max, result.level = cur, max, UnitLevel("player")
	if quests.count > 0 and not quests.pending and not quests.secret and quests.xp > 0 then
		result.proj = ns.Project(cur, max, result.level, quests.xp)
	end
	return result
end

local function Draw(bar, result)
	local fill, pip = bar.ForeverQuestsFill, bar.ForeverQuestsPip
	local proj = result.proj
	local width = bar:GetWidth()
	if not proj or width <= 0 then
		fill:Hide()
		pip:Hide()
		return
	end

	local startFraction = math.min(result.cur / result.max, 1)
	local fillWidth = (proj.fraction - startFraction) * width
	if fillWidth >= 1 then
		fill:SetVertexColor((proj.levelsUp and LEVEL_UP_COLOR or FILL_COLOR):GetRGB())
		fill:ClearAllPoints()
		fill:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", startFraction * width, 0)
		-- As tall as Blizzard's rested fill, so the two line up.
		local rested = bar.ExhaustionLevelFillBar
		fill:SetSize(fillWidth, rested and rested:GetHeight() or bar:GetHeight())
		fill:SetTexCoord(startFraction, proj.fraction, 0, 1)
		fill:Show()
	else
		fill:Hide()
	end

	pip:ClearAllPoints()
	pip:SetPoint("CENTER", bar, "LEFT", proj.fraction * width, 0)
	pip:SetShown(not proj.levelsUp and proj.fraction <= EDGE_HIDE)
end

local function DrawAll()
	local result = ns.ExpBar.lastResult
	if not result then
		return
	end
	for _, bar in ipairs(bars) do
		Draw(bar, result)
	end
end

-- Recomputes the result and redraws every hooked bar. While the player's XP reads as secret
-- the bars keep what they last drew rather than blinking out. Returns the result.
function ns.ExpBar.Refresh()
	local result = Compute()
	local previous = ns.ExpBar.lastResult
	ns.ExpBar.lastResult = result
	if result.xpSecret and previous and previous.proj then
		result.cur, result.max, result.level, result.proj = previous.cur, previous.max, previous.level, previous.proj
	end
	DrawAll()

	if ns.dev.enabled then
		local proj = result.proj
		ns.dev:LogChanged(
			"bar",
			proj and (tostring(proj.fraction) .. tostring(proj.levelsUp)) or "none",
			"BAR",
			"cur",
			result.cur,
			"max",
			result.max,
			"gain",
			result.quests.xp,
			"fraction",
			proj and proj.fraction,
			"levelsUp",
			proj and proj.levelsUp,
			"xpSecret",
			result.xpSecret,
			"bars",
			#bars
		)
	end
	return result
end

local function Hook(bar)
	if not bar or not bar.StatusBar or bar.ForeverQuestsFill then
		return
	end
	-- Under Blizzard's rested fill (ARTWORK, sublevel -1), so the rested shading stays visible
	-- where the two overlap. Like it, it shows through the status bar's translucent background
	-- and under the current-XP fill.
	local fill = bar:CreateTexture(nil, "ARTWORK", nil, -2)
	fill:SetAtlas(FILL_ATLAS)
	fill:SetDesaturated(true)
	fill:Hide()
	bar.ForeverQuestsFill = fill

	-- On the status bar itself, above its fill, so it keeps its place when frame levels change.
	local pip = bar.StatusBar:CreateTexture(nil, "OVERLAY")
	pip:SetAtlas(PIP_ATLAS)
	pip:SetSize(PIP_WIDTH, PIP_HEIGHT)
	pip:SetVertexColor(NORMAL_FONT_COLOR:GetRGB())
	pip:Hide()
	bar.ForeverQuestsPip = pip

	bars[#bars + 1] = bar
	bar:HookScript("OnShow", DrawAll)
	bar:HookScript("OnSizeChanged", DrawAll)
	ns.Tooltip.Attach(bar)
end

EventUtil.ContinueOnAddOnLoaded("Blizzard_StatusTrackingBar", function()
	local experience = StatusTrackingBarInfo.BarsEnum.Experience
	for _, name in ipairs({ "MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer" }) do
		local container = _G[name]
		Hook(container and container.bars and container.bars[experience])
	end
	ns.OnQuestsChanged = ns.ExpBar.Refresh
	ns.ExpBar.Refresh()
end)
