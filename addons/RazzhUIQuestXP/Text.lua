local _, ns = ...
local L = ns.L

-- The line itself: a box on UIParent holding one font string, placed and sized per Edit Mode
-- layout (EditMode.lua), with the wordy version in a tooltip. Bound to nothing of Blizzard's. The
-- box is as big as its text and anchored at the saved point, so the text grows from where the
-- player put it. It is hidden whenever there is nothing to say, except while Edit Mode is open,
-- when a sample stands in so there is something to drag.

ns.Text = {}

ns.Text.DEFAULTS = {
	point = "CENTER",
	x = 0,
	y = -250,
	fontSize = 14,
}
local DEFAULTS = ns.Text.DEFAULTS

local holder = CreateFrame("Frame", nil, UIParent)
holder:SetSize(1, 1)
holder:SetPoint(DEFAULTS.point, UIParent, DEFAULTS.point, DEFAULTS.x, DEFAULTS.y)
holder:Hide()
-- Motion only, for the tooltip: clicks on the text go to whatever is behind it.
holder:SetMouseMotionEnabled(true)
ns.Text.holder = holder

local line = holder:CreateFontString(nil, "ARTWORK", "GameFontNormal")
line:SetPoint("CENTER")

local sampling = false -- Edit Mode is open
local summary -- the last ns.Summary.Build result; nil when there is nothing to say

local function Resize()
	holder:SetSize(math.max(line:GetStringWidth(), 1), math.max(line:GetStringHeight(), 1))
end

local function ShowTooltip()
	if not summary then
		return
	end
	GameTooltip:SetOwner(holder, "ANCHOR_TOP")
	GameTooltip_SetTitle(GameTooltip, L.TITLE)
	for _, entry in ipairs(summary.lines) do
		GameTooltip_AddColoredLine(GameTooltip, entry[1], entry[2])
	end
	GameTooltip:Show()
end

holder:SetScript("OnEnter", ShowTooltip)
holder:SetScript("OnLeave", function()
	if GameTooltip:IsOwned(holder) then
		GameTooltip:Hide()
	end
end)
holder:SetScript("OnHide", function()
	if GameTooltip:IsOwned(holder) then
		GameTooltip:Hide()
	end
end)

-- The summary for the player's quests and XP right now, or nil and why there is none.
local function Compute()
	if IsXPUserDisabled() then
		return nil, "xp disabled"
	end
	-- The pair Blizzard's exp bar checks (Blizzard_StatusTrackingBar/Shared/ExpBar.lua).
	if GameRulesUtil.IsPlayerAtEffectiveMaxLevel() then
		return nil, "max level"
	end
	local quests = ns.Quests.Collect()
	if quests.count == 0 then
		return nil, "no quests"
	end
	if quests.pending then
		return nil, "pending"
	end
	local cur, max, level = UnitXP("player"), UnitXPMax("player"), UnitLevel("player")
	if quests.secret or issecretvalue(cur) or issecretvalue(max) or issecretvalue(level) then
		return nil, "secret"
	end
	local bonusPercent, bonusNames = ns.XPBonus.Get()
	local built = ns.Summary.Build(quests.count, quests.xp, cur, max, level, bonusPercent, bonusNames)
	if not built then
		return nil, "no xp"
	end
	return built
end

-- Redraws the line from the quest log. Called on every quest, XP and XP-buff change (Quests.lua)
-- and when Edit Mode opens or closes.
function ns.Text.Refresh()
	local why
	summary, why = Compute()
	if summary then
		line:SetText(summary.text)
		local color = summary.levelsUp and GREEN_FONT_COLOR or NORMAL_FONT_COLOR
		line:SetTextColor(color:GetRGB())
	elseif sampling then
		line:SetText(L.SAMPLE)
		line:SetTextColor(NORMAL_FONT_COLOR:GetRGB())
	end
	local shown = summary ~= nil or sampling
	if shown then
		Resize()
	end
	holder:SetShown(shown)
	if GameTooltip:IsOwned(holder) then
		if summary then
			ShowTooltip()
		else
			GameTooltip:Hide()
		end
	end
	if ns.dev.enabled then
		local state = summary and summary.text or (why .. (sampling and " (sample)" or ""))
		ns.dev:LogChanged("line", state, "LINE", state, "levelsUp", summary and summary.levelsUp or false)
	end
end
ns.OnQuestsChanged = ns.Text.Refresh

-- Places and sizes the line for an Edit Mode layout: { point, x, y, fontSize }.
function ns.Text.SetLayout(layout)
	local face, _, flags = GameFontNormal:GetFont()
	line:SetFont(face, layout.fontSize, flags)
	holder:ClearAllPoints()
	holder:SetPoint(layout.point, UIParent, layout.point, layout.x, layout.y)
	Resize()
end

-- While sampling (Edit Mode open) the box always shows, with a sample when there is no real line.
function ns.Text.SetSample(enabled)
	sampling = enabled
	ns.Text.Refresh()
end
