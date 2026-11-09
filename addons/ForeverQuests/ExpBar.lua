local _, ns = ...

-- Draws, on Blizzard's experience bar, where the player's XP lands after turning in every
-- completed quest: a fill from the current XP to that point and a pip at its end, built the
-- way Blizzard draws rested XP (ExhaustionLevelFillBar and ExhaustionTick in
-- Blizzard_StatusTrackingBar/Shared/ExpBar.lua). Each status bar container
-- (MainStatusTrackingBarContainer, SecondaryStatusTrackingBarContainer) has its own exp bar,
-- so both get one.

ns.ExpBar = {}

local FILL_ATLAS = "UI-HUD-ExperienceBar-Fill-Prediction"
local PIP_ATLAS = "UI-HUD-ExperienceBar-Frame-Pip"
local PIP_WIDTH, PIP_HEIGHT = 10, 14
local EDGE_HIDE = 0.99 -- like Blizzard's hideAtBarEdge: no pip right at the bar's end

local bars = {} -- hooked exp bars; each gets bar.ForeverQuestsFill and bar.ForeverQuestsPip

-- The state shared by every bar and the tooltip. Fields:
--   quests = ns.Quests.Collect() result,
--   cur, max, level = the player's XP, the XP the level needs, the level (nil when secret),
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
	if fillWidth < 1 then
		fill:Hide()
		pip:Hide()
		return
	end

	local color = proj.levelsUp and GREEN_FONT_COLOR or QUEST_OBJECTIVE_FONT_COLOR
	fill:SetVertexColor(color:GetRGB())
	fill:ClearAllPoints()
	fill:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", startFraction * width, 0)
	fill:SetSize(fillWidth, bar:GetHeight())
	fill:SetTexCoord(startFraction, proj.fraction, 0, 1)
	fill:Show()

	pip:ClearAllPoints()
	pip:SetPoint("CENTER", bar, "LEFT", proj.fraction * width, 0)
	pip:SetShown(not proj.levelsUp and proj.fraction <= EDGE_HIDE)
end

-- Recomputes the result and redraws every hooked bar. Returns the result.
function ns.ExpBar.Refresh()
	local result = Compute()
	ns.ExpBar.lastResult = result
	for _, bar in ipairs(bars) do
		Draw(bar, result)
	end

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
			"bars",
			#bars
		)
	end
	return result
end

local function Hook(bar)
	if not bar or bar.ForeverQuestsFill then
		return
	end
	-- Above Blizzard's rested fill (ARTWORK, sublevel -1).
	local fill = bar:CreateTexture(nil, "ARTWORK", nil, 0)
	fill:SetAtlas(FILL_ATLAS)
	fill:Hide()
	bar.ForeverQuestsFill = fill

	-- On its own frame above the status bar, so the pip draws over the XP fill.
	local overlay = CreateFrame("Frame", nil, bar)
	overlay:SetAllPoints(bar)
	overlay:SetFrameLevel(bar.StatusBar:GetFrameLevel() + 2)
	local pip = overlay:CreateTexture(nil, "OVERLAY")
	pip:SetAtlas(PIP_ATLAS)
	pip:SetSize(PIP_WIDTH, PIP_HEIGHT)
	pip:Hide()
	bar.ForeverQuestsPip = pip

	bars[#bars + 1] = bar
	bar:HookScript("OnShow", ns.ExpBar.Refresh)
	bar:HookScript("OnSizeChanged", ns.ExpBar.Refresh)
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
