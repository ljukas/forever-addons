local _, ns = ...

-- The journal window: one character's runs, or all characters', grouped by dungeon or by level
-- on the left (Logic/RunList.lua), the selected run's
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
-- The room the character dropdown takes above the run list, and the run list's headings
-- below it (24 high, 2 of it over the list's inset).
local PICKER_HEIGHT = 30
local HEADINGS_HEIGHT = 22
local DETAIL_WIDTH = WIDTH - INSET_LEFT - LIST_WIDTH - INSET_GAP + INSET_RIGHT

local frame
-- The selected run: its character's key and its id (ids are numbered per character).
local selectedKey, selectedID
-- Whose runs are shown: every character's with viewAll, else viewedKey's: nil for the current
-- character, else another's key (Database.lua). Opening the journal goes back to the current
-- character.
local viewAll, viewedKey = false, nil
-- The creature table's order (Logic/Creatures.lua's keys), for the session: most experience
-- first until a column heading is clicked.
local sortKey, sortAscending = "xp", false
-- The run list's grouping and order (Logic/RunList.lua's keys), for the session: by dungeon,
-- A to Z, until a heading is clicked.
local runSortKey, runSortAscending = "dungeon", true

-- Blizzard's own rank art: the nameplates' elite dragons and the target frame's skull.
local RANK_ATLAS = { elite = "nameplates-icon-elite-gold", rare = "nameplates-icon-elite-silver" }
local BOSS_TEXTURE = [[Interface\TargetingFrame\UI-TargetingFrame-Skull]]
-- The arrow on the sorted column, as the auction house has it.
local SORT_ARROW_ATLAS = "auctionhouse-ui-sortarrow"

local function Number(value)
	return BreakUpLargeNumbers(math.floor(value + 0.5))
end

local function Kills(count)
	return count == 1 and L.KILL_ONE or L.KILLS:format(Number(count))
end

-- text in a class's colour; unchanged for a class not known (a character that hasn't logged in
-- since classes were saved).
local function ClassColored(class, text)
	local color = class and C_ClassColor.GetClassColor(class)
	return color and color:WrapTextInColorCode(text) or text
end

-- The runs to list as Logic/RunList.lua's entries: every character's, or the viewed one's.
local function Entries()
	local shown = viewedKey or ns.CharacterKey()
	local entries = {}
	for _, character in ipairs(ns.DB.Characters()) do
		if viewAll or character.key == shown then
			for _, run in ipairs(ns.DB.RunsOf(character.key)) do
				table.insert(entries, { run = run, key = character.key, class = character.class })
			end
		end
	end
	return entries
end

-- A run row's first line: whose run it is when all characters are listed, the dungeon when the
-- list's headers aren't dungeons (else the run's number in it), and when it started. The date
-- stands last and is the part cut off if the row is too narrow.
--   one character, by dungeon:   "Run 2 - 12 Nov 21:04"
--   one character, by level:     "Deadmines - 12 Nov 21:04"
--   all characters, by dungeon:  "Thrall - Run 2 - 12 Nov"
local function RunTitle(data)
	local run = data.run
	local parts = {}
	if viewAll then
		table.insert(parts, ClassColored(data.class, data.key:match("^[^-]+") or data.key))
	end
	table.insert(parts, runSortKey == "dungeon" and L.RUN_NUMBER:format(run.number) or run.name)
	table.insert(parts, date(#parts == 2 and "%d %b" or "%d %b %H:%M", run.firstKill))
	return table.concat(parts, L.RUN_TITLE_SEPARATOR)
end

----------------------------------------------------------------------------------------------
-- The frame.

local Refresh

-- Brings the selected run into view: the list is in sorted order, so it may be anywhere. On
-- the next frame, once the list has been laid out with its new rows.
local function ScrollToSelected()
	C_Timer.After(0, function()
		if frame:IsShown() then
			frame.RunList:ScrollToElementDataByPredicate(function(data)
				return data.run ~= nil and data.run.id == selectedID and data.key == selectedKey
			end, ScrollBoxConstants.AlignCenter, 0, ScrollBoxConstants.NoScrollInterpolation)
		end
	end)
end

local function Select(key, id)
	selectedKey, selectedID = key, id
	Refresh()
end

local function OpenRunMenu(owner, key, id)
	MenuUtil.CreateContextMenu(owner, function(_, root)
		root:CreateButton(L.DELETE_RUN, function()
			if key == ns.CharacterKey() then
				-- The tracker's: the run may be the one being recorded.
				ns.Tracker.DeleteRun(id)
			else
				ns.DB.DeleteRunOf(key, id)
				Refresh()
			end
		end)
	end)
end

local function InitHeader(row, data)
	if data.level then
		row.Text:SetText(
			data.count == 1 and L.LEVEL_HEADER_ONE:format(data.level) or L.LEVEL_HEADER:format(data.level, data.count)
		)
	else
		row.Text:SetText(
			(data.count == 1 and L.DUNGEON_HEADER_ONE or L.DUNGEON_HEADER):format(data.dungeon, data.count)
		)
	end
end

local function InitRun(row, data)
	local run = data.run
	row.Title:SetText(RunTitle(data))
	row.Share:SetText(ns.Format.Share(run.share))
	row.Summary:SetText(
		L.RUN_SUMMARY:format(Number(run.xp), Kills(run.kills), ns.Format.Duration(ns.Format.RunSeconds(run)))
	)
	row.SelectedBar:SetShown(run.id == selectedID and data.key == selectedKey)
	row:SetScript("OnClick", function(self, button)
		if button == "RightButton" then
			OpenRunMenu(self, data.key, run.id)
		else
			Select(data.key, run.id)
		end
	end)
end

local function InitCreature(row, data)
	row.Name:SetText(data.name)
	row.Kills:SetText(Number(data.kills))
	row.Each:SetText(data.kills > 0 and Number(data.xp / data.kills) or L.NONE)
	row.Total:SetText(Number(data.xp))
	if data.rank == "boss" then
		-- A reused row may still have an atlas's texture coordinates.
		row.Rank:SetTexture(BOSS_TEXTURE)
		row.Rank:SetTexCoord(0, 1, 0, 1)
	elseif RANK_ATLAS[data.rank] then
		row.Rank:SetAtlas(RANK_ATLAS[data.rank])
	end
	row.Rank:SetShown(data.rank ~= nil)
end

-- The party line's tooltip: each member's name, level, class and group role.
local function ShowPartyTooltip(self)
	GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT", 0, -2)
	GameTooltip_SetTitle(GameTooltip, L.PARTY_TOOLTIP_TITLE)
	for _, member in ipairs(self.members or {}) do
		local class = LOCALIZED_CLASS_NAMES_MALE[member.class] or member.class
		local detail = member.level and L.PARTY_TOOLTIP_MEMBER:format(member.level, class) or class
		local role = member.role and _G[member.role]
		if type(role) == "string" then
			detail = L.PARTY_TOOLTIP_ROLE:format(detail, role)
		end
		GameTooltip:AddDoubleLine(ClassColored(member.class, member.name), detail, 1, 1, 1, 1, 1, 1)
	end
	GameTooltip:Show()
end

-- A click on a creature table heading: a first click sorts best first (names A to Z), a second
-- turns the order.
local function SortCreatures(key)
	if sortKey == key then
		sortAscending = not sortAscending
	else
		sortKey, sortAscending = key, key == "name"
	end
	Refresh()
	frame.CreatureList:ScrollToBegin()
end

-- A click on a run list heading: dungeons start A to Z, levels highest first.
local function SortRuns(key)
	if runSortKey == key then
		runSortAscending = not runSortAscending
	else
		runSortKey, runSortAscending = key, key == "dungeon"
	end
	Refresh()
	frame.RunList:ScrollToBegin()
end

-- Shows the sort arrow on the heading a list is sorted by.
local function SetArrows(headings, key, ascending)
	for _, heading in ipairs(headings) do
		heading.Arrow:SetShown(heading.key == key)
		-- The art points down (largest first); turned over for ascending.
		heading.Arrow:SetTexCoord(0, 1, ascending and 1 or 0, ascending and 0 or 1)
	end
end

-- A column heading that sorts a list by key, through onClick(key): Blizzard's list heading
-- button (the Who list's look). The label is offset from the heading's justify edge, to stand
-- over its column's text.
local function CreateHeading(parent, text, key, justify, offset, onClick)
	local heading = CreateFrame("Button", nil, parent, "ColumnDisplayButtonNoScriptsTemplate")
	heading:SetText(text)
	local label = heading:GetFontString()
	label:ClearAllPoints()
	label:SetPoint(justify, offset, 0)
	heading.Arrow = heading:CreateTexture(nil, "ARTWORK")
	heading.Arrow:SetAtlas(SORT_ARROW_ATLAS, true)
	if justify == "LEFT" then
		heading.Arrow:SetPoint("LEFT", label, "RIGHT", 3, 0)
	else
		heading.Arrow:SetPoint("RIGHT", label, "LEFT", -3, 0)
	end
	heading.key = key
	heading:SetScript("OnClick", function()
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		onClick(key)
	end)
	return heading
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

	-- The template's inset becomes the run list; the run stands beside it.
	-- Whose runs to show: Blizzard's dropdown above the run list, the account's characters in
	-- their class colours.
	local picker = CreateFrame("DropdownButton", nil, frame, "WowStyle1DropdownTemplate")
	picker:SetPoint("TOPLEFT", INSET_LEFT, INSET_TOP - 2)
	picker:SetWidth(LIST_WIDTH)
	picker:SetupMenu(function(_, root)
		root:CreateRadio(L.ALL_CHARACTERS, function()
			return viewAll
		end, function()
			viewAll, viewedKey, selectedKey, selectedID = true, nil, nil, nil
			Refresh()
			ScrollToSelected()
		end)
		root:CreateDivider()
		local current = ns.CharacterKey()
		for _, character in ipairs(ns.DB.Characters()) do
			local key = character.key ~= current and character.key or nil
			root:CreateRadio(ClassColored(character.class, character.key), function()
				return not viewAll and viewedKey == key
			end, function()
				viewAll, viewedKey, selectedKey, selectedID = false, key, nil, nil
				Refresh()
				ScrollToSelected()
			end)
		end
	end)
	frame.Picker = picker

	local list = frame.Inset
	list:ClearAllPoints()
	list:SetPoint("TOPLEFT", INSET_LEFT, INSET_TOP - PICKER_HEIGHT - HEADINGS_HEIGHT)
	list:SetPoint("BOTTOMLEFT", INSET_LEFT, INSET_BOTTOM)
	list:SetWidth(LIST_WIDTH)
	frame.RunList = CreateList(list, -4, function(factory, data)
		if data.header then
			factory("ForeverDungeonXPHeaderTemplate", InitHeader)
		else
			factory("ForeverDungeonXPRunTemplate", InitRun)
		end
	end)

	-- The run list's headings, resting on its inset as the creature table's do: what the runs
	-- are grouped by, and in which order.
	local byLevel = CreateHeading(frame, L.COLUMN_LEVEL, "level", "RIGHT", -28, SortRuns)
	byLevel:SetFrameLevel(list:GetFrameLevel() + 1)
	byLevel:SetPoint("BOTTOMRIGHT", list, "TOPRIGHT", 0, -2)
	byLevel:SetWidth(90)
	local byDungeon = CreateHeading(frame, L.COLUMN_DUNGEON, "dungeon", "LEFT", 10, SortRuns)
	byDungeon:SetFrameLevel(list:GetFrameLevel() + 1)
	byDungeon:SetPoint("BOTTOMLEFT", list, "TOPLEFT", 0, -2)
	byDungeon:SetPoint("BOTTOMRIGHT", byLevel, "BOTTOMLEFT", 2, 0)
	frame.RunHeadings = { byDungeon, byLevel }

	-- The run beside the list, laid out as Blizzard's rosters are (the communities member
	-- list): the title and totals on the panel's own background, and an inset for the creature
	-- rows alone, with the column headings resting on its top edge.
	local detail = CreateFrame("Frame", nil, frame)
	detail:SetPoint("TOPLEFT", list, "TOPRIGHT", INSET_GAP, PICKER_HEIGHT + HEADINGS_HEIGHT)
	detail:SetPoint("BOTTOMRIGHT", INSET_RIGHT, INSET_BOTTOM)
	frame.Detail = detail

	-- With no runs an empty inset fills the place and shows only this line.
	detail.Empty = CreateFrame("Frame", nil, detail, "InsetFrameTemplate")
	detail.Empty:SetAllPoints()
	detail.Empty.Text = detail.Empty:CreateFontString(nil, "ARTWORK", "GameFontDisable")
	detail.Empty.Text:SetPoint("CENTER")

	local content = CreateFrame("Frame", nil, detail)
	content:SetAllPoints()
	detail.Content = content

	content.Header = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	content.Header:SetPoint("TOPLEFT", 12, -12)
	content.Header:SetPoint("RIGHT", -12, 0)
	content.Header:SetJustifyH("LEFT")
	content.Header:SetWordWrap(false)

	content.Note = content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	content.Note:SetPoint("TOPLEFT", 12, -46)
	content.Note:SetText(L.APPROXIMATE)

	-- Who the run was with: one line of names in class colours, the details in its tooltip.
	local party = CreateFrame("Frame", nil, content)
	party:SetPoint("TOPLEFT", 12, -31)
	party:SetPoint("RIGHT", -12, 0)
	party:SetHeight(14)
	party.Text = party:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	party.Text:SetAllPoints()
	party.Text:SetJustifyH("LEFT")
	party.Text:SetWordWrap(false)
	party:EnableMouse(true)
	party:SetScript("OnEnter", ShowPartyTooltip)
	party:SetScript("OnLeave", GameTooltip_Hide)
	content.Party = party

	local stats = CreateFrame("Frame", nil, content)
	stats:SetPoint("TOPLEFT", 8, -64)
	stats:SetSize(DETAIL_WIDTH - 16, 40)
	local labels = { L.STAT_XP, L.STAT_SHARE, L.STAT_KILLS, L.STAT_TIME, L.STAT_PER_HOUR }
	content.Stats = {}
	for index, label in ipairs(labels) do
		content.Stats[index] = CreateStat(stats, index, (DETAIL_WIDTH - 16) / #labels, label)
	end

	local rows = CreateFrame("Frame", nil, content, "InsetFrameTemplate")
	rows:SetPoint("TOPLEFT", 0, -134)
	rows:SetPoint("BOTTOMRIGHT")
	frame.CreatureList = CreateList(rows, -4, function(factory)
		factory("ForeverDungeonXPCreatureTemplate", InitCreature)
	end)

	-- Column headings on the inset's top edge, across its whole width (over the scroll bar
	-- too), each overlapping the next by OVERLAP as ColumnDisplayMixin lays them out. The
	-- offsets put each label over its column in the rows (UI/Templates.xml): the rows start
	-- 4 in from the inset's left and end 20 in from its right (CreateList), their numbers 8
	-- in from each column's right edge, their names 26 in from the left.
	local OVERLAP, ROW_LEFT, ROW_RIGHT = 2, 4, 20
	local function Heading(text, key, justify, offset)
		local heading = CreateHeading(content, text, key, justify, offset, SortCreatures)
		heading:SetFrameLevel(rows:GetFrameLevel() + 1)
		return heading
	end
	local total = Heading(L.COLUMN_TOTAL, "xp", "RIGHT", -(ROW_RIGHT + 8))
	total:SetPoint("BOTTOMRIGHT", rows, "TOPRIGHT", 0, -2)
	total:SetWidth(70 + ROW_RIGHT)
	local each = Heading(L.COLUMN_EACH, "each", "RIGHT", -(OVERLAP + 8))
	each:SetPoint("BOTTOMRIGHT", total, "BOTTOMLEFT", OVERLAP, 0)
	each:SetWidth(70 + OVERLAP)
	local kills = Heading(L.COLUMN_KILLS, "kills", "RIGHT", -(OVERLAP + 8))
	kills:SetPoint("BOTTOMRIGHT", each, "BOTTOMLEFT", OVERLAP, 0)
	kills:SetWidth(50 + OVERLAP)
	local name = Heading(L.COLUMN_CREATURE, "name", "LEFT", ROW_LEFT + 26)
	name:SetPoint("BOTTOMLEFT", rows, "TOPLEFT", 0, -2)
	name:SetPoint("BOTTOMRIGHT", kills, "BOTTOMLEFT", OVERLAP, 0)
	content.Headings = { name, kills, each, total }

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
	local members = ns.Format.Party(run)
	local names = {}
	for index, member in ipairs(members) do
		local text = member.level and L.PARTY_MEMBER:format(member.name, member.level) or member.name
		names[index] = ClassColored(member.class, text)
	end
	content.Party.members = members
	content.Party.Text:SetText(#names > 0 and L.PARTY:format(table.concat(names, ", ")) or "")
	content.Party:SetShown(#names > 0)
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
	SetArrows(content.Headings, sortKey, sortAscending)
	frame.CreatureList:SetDataProvider(
		CreateDataProvider(ns.Creatures.Rows(run, L.UNKNOWN_CREATURES, sortKey, sortAscending)),
		ScrollBoxConstants.RetainScrollPosition
	)
end

-- Rebuilds both lists. Keeps the selection if its run still has kills to show, else selects
-- the run being recorded, else the newest run.
function Refresh()
	local rows = ns.RunList.Rows(Entries(), runSortKey, runSortAscending)
	-- The run being recorded, if it is among the listed ones.
	local recording = not viewedKey and ns.Tracker.CurrentRun()
	local recordingKey = ns.CharacterKey()
	local selected, current, newest
	for _, row in ipairs(rows) do
		if row.run then
			if row.run.id == selectedID and row.key == selectedKey then
				selected = row
			end
			if recording and row.run.id == recording.id and row.key == recordingKey then
				current = row
			end
			if not newest or (row.run.firstKill or 0) > (newest.run.firstKill or 0) then
				newest = row
			end
		end
	end
	selected = selected or current or newest
	selectedKey, selectedID = selected and selected.key, selected and selected.run.id

	SetArrows(frame.RunHeadings, runSortKey, runSortAscending)
	frame.RunList:SetDataProvider(CreateDataProvider(rows), ScrollBoxConstants.RetainScrollPosition)
	frame.Detail.Content:SetShown(selected ~= nil)
	frame.Detail.Empty:SetShown(selected == nil)
	frame.Detail.Empty.Text:SetText(viewedKey and L.EMPTY_CHARACTER or L.EMPTY)
	if selected then
		ShowRun(selected.run)
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
	viewAll, viewedKey, selectedKey, selectedID = false, nil, nil, nil
	frame:Show()
	-- Rebuilt on opening, not on every refresh (a kill would close the open menu): the
	-- characters may have changed, and the dropdown's text must follow the reset above.
	frame.Picker:GenerateMenu()
	Refresh()
	ScrollToSelected()
	if ns.dev.enabled then
		ns.log("UI", "show", "runs", #ns.DB.Runs(), "selected", selectedID)
	end
end
