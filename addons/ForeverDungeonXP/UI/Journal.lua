local _, ns = ...

-- The journal window: the character's runs grouped by dungeon on the left, the selected run's
-- totals and creatures on the right. Built on first use from Blizzard's own panel pieces
-- (ButtonFrameTemplate without a portrait as the addon list uses it, InsetFrameTemplate,
-- PanelDragBarTemplate, WowScrollBoxList, MinimalScrollBar); the rows are in UI/Templates.xml.
-- It holds no secure frames, so it opens and closes in combat with plain Show and Hide, and
-- Escape closes it through UISpecialFrames.

ns.Journal = {}

local L = ns.L

local FRAME_NAME = "ForeverDungeonXPFrame"
local WIDTH, HEIGHT = 720, 470
local LIST_WIDTH = 250
-- Blizzard's inset offsets for a panel without a portrait (SharedUIPanelTemplates.lua).
local INSET_LEFT, INSET_TOP, INSET_RIGHT, INSET_BOTTOM = 9, -24, -6, 4
local INSET_GAP = 4
local DETAIL_WIDTH = WIDTH - INSET_LEFT - LIST_WIDTH - INSET_GAP + INSET_RIGHT

local frame
local selectedID

----------------------------------------------------------------------------------------------
-- Pure: saved runs to list rows.

-- The run list's rows: per dungeon a header row, then its runs, newest first; the dungeon with
-- the newest run first. A run without kills (a visit in progress) is left out.
--   runs (ids 1..4): Deadmines 1, Wailing Caverns 2, Deadmines 3, Deadmines 4 (no kills)
--   -> header Deadmines (2 runs), run 3, run 1, header Wailing Caverns (1 run), run 2
local function BuildRunRows(runs)
	local dungeons, order = {}, {}
	for index = #runs, 1, -1 do
		local run = runs[index]
		if run.kills > 0 then
			local dungeon = dungeons[run.instanceID]
			if not dungeon then
				dungeon = { name = run.name, runs = {} }
				dungeons[run.instanceID] = dungeon
				table.insert(order, dungeon)
			end
			table.insert(dungeon.runs, run)
		end
	end
	local rows = {}
	for _, dungeon in ipairs(order) do
		table.insert(rows, { header = true, name = dungeon.name, count = #dungeon.runs })
		for _, run in ipairs(dungeon.runs) do
			table.insert(rows, { run = run })
		end
	end
	return rows
end

-- A run's creature rows, most experience first, then by name; the kills whose names were hidden
-- last.
local function BuildCreatureRows(run)
	local rows = {}
	for name, creature in pairs(run.creatures) do
		table.insert(rows, { name = name, kills = creature.kills, xp = creature.xp })
	end
	table.sort(rows, function(a, b)
		if a.xp ~= b.xp then
			return a.xp > b.xp
		end
		return a.name < b.name
	end)
	if run.unknown then
		table.insert(rows, { name = L.UNKNOWN_CREATURES, kills = run.unknown.kills, xp = run.unknown.xp })
	end
	return rows
end

local function Number(value)
	return BreakUpLargeNumbers(math.floor(value + 0.5))
end

local function Kills(count)
	return count == 1 and L.KILL_ONE or L.KILLS:format(Number(count))
end

----------------------------------------------------------------------------------------------
-- The frame.

local Refresh

local function Select(id)
	selectedID = id
	Refresh()
end

local function OpenRunMenu(owner, id)
	MenuUtil.CreateContextMenu(owner, function(_, root)
		root:CreateButton(L.DELETE_RUN, function()
			ns.Tracker.DeleteRun(id)
		end)
	end)
end

local function InitHeader(row, data)
	row.Text:SetText((data.count == 1 and L.DUNGEON_HEADER_ONE or L.DUNGEON_HEADER):format(data.name, data.count))
end

local function InitRun(row, data)
	local run = data.run
	row.Title:SetText(L.RUN_TITLE:format(run.number, date("%d %b %H:%M", run.firstKill)))
	row.Share:SetText(ns.Format.Share(run.share))
	row.Summary:SetText(
		L.RUN_SUMMARY:format(Number(run.xp), Kills(run.kills), ns.Format.Duration(ns.Format.RunSeconds(run)))
	)
	row.SelectedBar:SetShown(run.id == selectedID)
	row:SetScript("OnClick", function(self, button)
		if button == "RightButton" then
			OpenRunMenu(self, run.id)
		else
			Select(run.id)
		end
	end)
end

local function InitCreature(row, data)
	row.Name:SetText(data.name)
	row.Kills:SetText(Number(data.kills))
	row.Each:SetText(data.kills > 0 and Number(data.xp / data.kills) or L.NONE)
	row.Total:SetText(Number(data.xp))
end

-- A ScrollBox filling parent below top, with its scroll bar, anchored the way Blizzard's Forever
-- lists are (Camelot/SkillsFrame.xml). The bar hides while there is nothing to scroll.
local function CreateList(parent, top, factory)
	local scrollBox = CreateFrame("Frame", nil, parent, "WowScrollBoxList")
	scrollBox:SetPoint("TOPLEFT", 4, top)
	scrollBox:SetPoint("BOTTOMRIGHT", -20, 5)
	local scrollBar = CreateFrame("EventFrame", nil, parent, "MinimalScrollBar")
	scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 5, -2)
	scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 5, 4)
	scrollBar:SetHideIfUnscrollable(true)
	local view = CreateScrollBoxListLinearView()
	view:SetElementFactory(factory)
	ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)
	return scrollBox
end

local function CreateStat(parent, index, width, label)
	local stat = CreateFrame("Frame", nil, parent)
	stat:SetPoint("TOPLEFT", parent, "TOPLEFT", (index - 1) * width, 0)
	stat:SetSize(width, parent:GetHeight())
	stat.Label = stat:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	stat.Label:SetPoint("TOP", 0, -2)
	stat.Label:SetText(label)
	stat.Value = stat:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
	stat.Value:SetPoint("TOP", stat.Label, "BOTTOM", 0, -4)
	stat.Value:SetWidth(width)
	stat.Value:SetWordWrap(false)
	return stat
end

local function CreateJournal()
	frame = CreateFrame("Frame", FRAME_NAME, UIParent, "ButtonFrameTemplate")
	frame:Hide()
	frame:SetSize(WIDTH, HEIGHT)
	frame:SetPoint("CENTER")
	frame:SetToplevel(true)
	frame:EnableMouse(true)
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	ButtonFrameTemplate_HidePortrait(frame)
	ButtonFrameTemplate_HideButtonBar(frame)
	ButtonFrameTemplate_HideAttic(frame)
	frame:SetTitle(L.TITLE)
	tinsert(UISpecialFrames, FRAME_NAME)

	-- Dragging by the title bar, with Blizzard's own drag bar (as the event trace window has).
	-- It sits below the close button's frame level, so the close button keeps its clicks.
	local dragBar = CreateFrame("Button", nil, frame, "PanelDragBarTemplate")
	dragBar:SetPoint("TOPLEFT")
	dragBar:SetPoint("TOPRIGHT")
	dragBar:SetHeight(22)

	-- The template's inset becomes the run list; a second inset beside it holds the run.
	local list = frame.Inset
	list:ClearAllPoints()
	list:SetPoint("TOPLEFT", INSET_LEFT, INSET_TOP)
	list:SetPoint("BOTTOMLEFT", INSET_LEFT, INSET_BOTTOM)
	list:SetWidth(LIST_WIDTH)
	frame.RunList = CreateList(list, -4, function(factory, data)
		if data.header then
			factory("ForeverDungeonXPHeaderTemplate", InitHeader)
		else
			factory("ForeverDungeonXPRunTemplate", InitRun)
		end
	end)

	local detail = CreateFrame("Frame", nil, frame, "InsetFrameTemplate")
	detail:SetPoint("TOPLEFT", list, "TOPRIGHT", INSET_GAP, 0)
	detail:SetPoint("BOTTOMRIGHT", INSET_RIGHT, INSET_BOTTOM)
	frame.Detail = detail

	-- With no runs the inset stays and shows only this line.
	detail.Empty = detail:CreateFontString(nil, "ARTWORK", "GameFontDisable")
	detail.Empty:SetPoint("CENTER")
	detail.Empty:SetText(L.EMPTY)

	local content = CreateFrame("Frame", nil, detail)
	content:SetAllPoints()
	detail.Content = content

	content.Header = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	content.Header:SetPoint("TOPLEFT", 12, -12)
	content.Header:SetPoint("RIGHT", -12, 0)
	content.Header:SetJustifyH("LEFT")
	content.Header:SetWordWrap(false)

	content.Note = content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	content.Note:SetPoint("TOPLEFT", content.Header, "BOTTOMLEFT", 0, -3)
	content.Note:SetText(L.APPROXIMATE)

	local stats = CreateFrame("Frame", nil, content)
	stats:SetPoint("TOPLEFT", 8, -52)
	stats:SetSize(DETAIL_WIDTH - 16, 40)
	local labels = { L.STAT_XP, L.STAT_SHARE, L.STAT_KILLS, L.STAT_TIME, L.STAT_PER_HOUR }
	content.Stats = {}
	for index, label in ipairs(labels) do
		content.Stats[index] = CreateStat(stats, index, (DETAIL_WIDTH - 16) / #labels, label)
	end

	-- Column headings, placed like the creature rows beneath them (UI/Templates.xml).
	local columns = CreateFrame("Frame", nil, content)
	columns:SetPoint("TOPLEFT", 4, -100)
	columns:SetPoint("TOPRIGHT", -20, -100)
	columns:SetHeight(18)
	local function Column(text, justify)
		local heading = columns:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
		heading:SetJustifyH(justify)
		heading:SetText(text)
		return heading
	end
	local total = Column(L.COLUMN_TOTAL, "RIGHT")
	total:SetWidth(70)
	total:SetPoint("RIGHT", -8, 0)
	local each = Column(L.COLUMN_EACH, "RIGHT")
	each:SetWidth(70)
	each:SetPoint("RIGHT", total, "LEFT")
	local kills = Column(L.COLUMN_KILLS, "RIGHT")
	kills:SetWidth(50)
	kills:SetPoint("RIGHT", each, "LEFT")
	local name = Column(L.COLUMN_CREATURE, "LEFT")
	name:SetPoint("LEFT", 8, 0)

	frame.CreatureList = CreateList(content, -120, function(factory)
		factory("ForeverDungeonXPCreatureTemplate", InitCreature)
	end)

	frame:SetScript("OnShow", function()
		PlaySound(SOUNDKIT.IG_CHARACTER_INFO_OPEN)
	end)
	frame:SetScript("OnHide", function()
		PlaySound(SOUNDKIT.IG_CHARACTER_INFO_CLOSE)
	end)
	EventRegistry:RegisterCallback("ForeverDungeonXP.RunsChanged", function()
		if frame:IsShown() then
			Refresh()
		end
	end, frame)
end

local function ShowRun(run)
	local content = frame.Detail.Content
	content.Header:SetText(L.DETAIL_HEADER:format(run.name, run.number, run.level))
	content.Note:SetShown(run.approximate == true)
	local seconds = ns.Format.RunSeconds(run)
	local perHour = ns.Format.PerHour(run.xp, seconds)
	local values = {
		Number(run.xp),
		ns.Format.Share(run.share),
		Number(run.kills),
		ns.Format.Duration(seconds),
		perHour and Number(perHour) or L.NONE,
	}
	for index, value in ipairs(values) do
		content.Stats[index].Value:SetText(value)
	end
	frame.CreatureList:SetDataProvider(
		CreateDataProvider(BuildCreatureRows(run)),
		ScrollBoxConstants.RetainScrollPosition
	)
end

-- Rebuilds both lists. Keeps the selection if its run still has kills to show, else selects
-- the run being recorded, else the newest run.
function Refresh()
	local rows = BuildRunRows(ns.DB.Runs())
	local selected, newest
	for _, row in ipairs(rows) do
		if row.run then
			if row.run.id == selectedID then
				selected = row.run
			end
			if not newest or row.run.id > newest.id then
				newest = row.run
			end
		end
	end
	if not selected then
		local current = ns.Tracker.CurrentRun()
		selected = current and current.kills > 0 and current or newest
	end
	selectedID = selected and selected.id or nil

	frame.RunList:SetDataProvider(CreateDataProvider(rows), ScrollBoxConstants.RetainScrollPosition)
	frame.Detail.Content:SetShown(selected ~= nil)
	frame.Detail.Empty:SetShown(selected == nil)
	if selected then
		ShowRun(selected)
	end
end

function ns.Journal.Toggle()
	if not frame then
		CreateJournal()
	end
	if frame:IsShown() then
		frame:Hide()
		return
	end
	-- Opening goes to the run being recorded, else the newest: not to an earlier selection.
	selectedID = nil
	frame:Show()
	Refresh()
	if ns.dev.enabled then
		ns.log("UI", "show", "runs", #ns.DB.Runs(), "selected", selectedID)
	end
end
