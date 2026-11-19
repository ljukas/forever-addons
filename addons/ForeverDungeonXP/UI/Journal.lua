local _, ns = ...

-- The journal window: one character's runs, or all characters', on the left, grouped by dungeon
-- or by level or ranked by experience per hour (Logic/RunList.lua); the selected run's totals
-- on the right, with its creatures or its timeline (Logic/Timeline.lua) under them, switched by
-- Blizzard's panel tabs. Built on first use from Blizzard's own panel pieces (ButtonFrameTemplate
-- without a portrait as the addon list uses it, InsetFrameTemplate, PanelDragBarTemplate,
-- WowScrollBoxList, MinimalScrollBar); the rows are in UI/Templates.xml.
-- It holds no secure frames, so it opens and closes in combat with plain Show and Hide, and
-- Escape closes it through UISpecialFrames.

ns.Journal = {}

local L = ns.L

local FRAME_NAME = "ForeverDungeonXPFrame"
local WIDTH, HEIGHT = 850, 470
-- Room beside the two number columns (UI/Templates.xml) for the longest kind of title, a
-- character's name, a dungeon's and a date: "Thrall - Shadowfang Keep - 16 Nov".
local LIST_WIDTH = 380
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
-- What the run's lower part shows, for the session: its "creatures" table or its "timeline".
local detailView = "creatures"
local VIEWS = { "creatures", "timeline" }
-- The run list's grouping and order (Logic/RunList.lua's keys: "dungeon", "level" or "rate"),
-- for the session: by dungeon, A to Z, until a heading is clicked.
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

-- A character's name without its realm: "Thrall-Some Realm" -> "Thrall".
local function ShortName(key)
	return key:match("^[^-]+") or key
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
--   all characters, by rate:     "Thrall - Deadmines - 12 Nov"
local function RunTitle(data)
	local run = data.run
	local parts = {}
	if viewAll then
		table.insert(parts, ClassColored(data.class, ShortName(data.key)))
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
	-- Saved data isn't checked for a level: a run without one must not throw.
	row.Level:SetText(type(run.level) == "number" and tostring(run.level) or L.NONE)
	-- A run shorter than a minute has no rate.
	row.Rate:SetText(data.rate and Number(data.rate) or L.NONE)
	row.Summary:SetText(
		L.RUN_SUMMARY:format(
			Number(run.xp),
			ns.Format.Share(run.share),
			Kills(run.kills),
			ns.Format.Duration(ns.Format.RunSeconds(run))
		)
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

-- A timeline row (Logic/Timeline.lua's, with class added by ShowRun for the rows that name a
-- player): when, what, and for a boss how long the fight took.
local function InitEvent(row, data)
	row.Time:SetText(ns.Timeline.Clock(data.offset))
	-- Saved data is only checked for an event's time and kind: a missing field must not throw.
	local name, text = tostring(data.name or ""), nil
	if data.kind == "first" then
		text = L.EVENT_FIRST
	elseif data.kind == "last" then
		text = L.EVENT_LAST
	elseif data.kind == "boss" then
		text = L.EVENT_BOSS:format(name)
	elseif data.kind == "wipe" then
		text = RED_FONT_COLOR:WrapTextInColorCode(L.EVENT_WIPE:format(name))
	elseif data.kind == "death" then
		text = L.EVENT_DEATH:format(ClassColored(data.class, name))
	elseif data.kind == "level" then
		text = NORMAL_FONT_COLOR:WrapTextInColorCode(L.EVENT_LEVEL:format(tonumber(data.level) or 0))
	elseif data.kind == "loot" then
		text = L.EVENT_LOOT:format(ClassColored(data.class, name), tostring(data.item or ""))
	end
	row.Text:SetText(text or "")
	row.Detail:SetText(data.duration and ns.Timeline.Clock(data.duration) or "")
	row.Icon:SetShown(data.kind == "boss")
	if data.kind == "boss" then
		row.Icon:SetTexture(BOSS_TEXTURE)
	end
	-- A looted item's tooltip on its row.
	local link = data.kind == "loot" and type(data.item) == "string" and data.item:match("|H(item:.-)|h")
	row:SetScript("OnEnter", link and function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetHyperlink(link)
		GameTooltip:Show()
	end or nil)
	row:SetScript("OnLeave", link and GameTooltip_Hide or nil)
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

-- A click on a run list heading: dungeons start A to Z, levels highest first and rates best
-- first; a second click turns the order.
local function SortRuns(key)
	if runSortKey == key then
		runSortAscending = not runSortAscending
	else
		runSortKey, runSortAscending = key, key == "dungeon"
	end
	Refresh()
	frame.RunList:ScrollToBegin()
	if ns.dev.enabled then
		local rows = frame.RunList:GetDataProvider():GetSize()
		ns.log("UI", "sort", runSortKey, runSortAscending and "ascending" or "descending", "rows", rows)
	end
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
	-- A smaller line under the value, for the stats that have a second number.
	stat.Sub = stat:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	stat.Sub:SetPoint("TOP", stat.Value, "BOTTOM", 0, -2)
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
		local characters = ns.DB.Characters()
		-- First name and surname ("Thrall Doomhammer"; the first name alone until the character
		-- has logged in and its surname was saved), with the realm only where two would read
		-- the same.
		local names, sameName = {}, {}
		for index, character in ipairs(characters) do
			local name = ShortName(character.key)
			name = character.surname and (name .. " " .. character.surname) or name
			names[index] = name
			sameName[name] = (sameName[name] or 0) + 1
		end
		for index, character in ipairs(characters) do
			local key = character.key ~= current and character.key or nil
			local name = sameName[names[index]] > 1 and character.key or names[index]
			local level = character.level
			local radio = root:CreateRadio(ClassColored(character.class, name), function()
				return not viewAll and viewedKey == key
			end, function()
				viewAll, viewedKey, selectedKey, selectedID = false, key, nil, nil
				Refresh()
				ScrollToSelected()
			end)
			if level then
				-- The character's level at the row's right edge, attached as Blizzard's currency
				-- transfer menu attaches its amounts (the Menu implementation guide); the row's
				-- width has to be worked out by hand for that.
				radio:AddInitializer(function(button)
					local text = button:AttachFontString()
					text:SetFontObject(GameFontHighlightSmall)
					text:SetHeight(20)
					text:SetPoint("RIGHT")
					text:SetJustifyH("RIGHT")
					-- "Lv." in Blizzard's grey, the number in its gold, as level labels are.
					text:SetText(
						GRAY_FONT_COLOR:WrapTextInColorCode(L.LEVEL_PREFIX)
							.. " "
							.. NORMAL_FONT_COLOR:WrapTextInColorCode(level)
					)
					local pad = 40
					return pad + button.fontString:GetUnboundedStringWidth() + text:GetUnboundedStringWidth(), 20
				end)
			end
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

	-- Both lists' column headings rest on their inset's top edge, across its whole width (over
	-- the scroll bar too), each overlapping the next by OVERLAP as ColumnDisplayMixin lays them
	-- out. The rows start ROW_LEFT in from the inset's left and end ROW_RIGHT in from its right
	-- (CreateList), their numbers 8 in from each column's right edge (UI/Templates.xml).
	local OVERLAP, ROW_LEFT, ROW_RIGHT = 2, 4, 20

	-- The run list's headings, each over its column in the run rows: the dungeon (and so the
	-- run's title), the level the run started at and its experience per hour. A click orders
	-- the list by that column: grouped by dungeon or by level, or every run by its rate.
	local function RunHeading(text, key, justify, offset)
		local heading = CreateHeading(frame, text, key, justify, offset, SortRuns)
		heading:SetFrameLevel(list:GetFrameLevel() + 1)
		return heading
	end
	local byRate = RunHeading(L.COLUMN_RATE, "rate", "RIGHT", -(ROW_RIGHT + 8))
	byRate:SetPoint("BOTTOMRIGHT", list, "TOPRIGHT", 0, -2)
	byRate:SetWidth(62 + ROW_RIGHT)
	local byLevel = RunHeading(L.COLUMN_LEVEL, "level", "RIGHT", -(OVERLAP + 8))
	byLevel:SetPoint("BOTTOMRIGHT", byRate, "BOTTOMLEFT", OVERLAP, 0)
	byLevel:SetWidth(54 + OVERLAP)
	-- Over the runs' titles, 12 in from the rows' left.
	local byDungeon = RunHeading(L.COLUMN_DUNGEON, "dungeon", "LEFT", ROW_LEFT + 12)
	byDungeon:SetPoint("BOTTOMLEFT", list, "TOPLEFT", 0, -2)
	byDungeon:SetPoint("BOTTOMRIGHT", byLevel, "BOTTOMLEFT", OVERLAP, 0)
	frame.RunHeadings = { byDungeon, byLevel, byRate }

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
	-- The inset holds the creature table or the timeline (detailView), each in its own frame so
	-- its list and scroll bar show and hide together.
	content.Views = {}
	for _, view in ipairs(VIEWS) do
		content.Views[view] = CreateFrame("Frame", nil, rows)
		content.Views[view]:SetAllPoints()
	end
	frame.CreatureList = CreateList(content.Views.creatures, -4, function(factory)
		factory("ForeverDungeonXPCreatureTemplate", InitCreature)
	end)
	frame.Timeline = CreateList(content.Views.timeline, -4, function(factory)
		factory("ForeverDungeonXPEventTemplate", InitEvent)
	end)

	-- The creature table's headings, laid out as the run list's are. The offsets put each label
	-- over its column in the rows (UI/Templates.xml), the names 26 in from the rows' left.
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

	-- The timeline's headings in the same place: labels only, they sort nothing.
	local function Label(text, justify, offset)
		local heading = Heading(text, nil, justify, offset)
		heading:EnableMouse(false)
		heading.Arrow:Hide()
		return heading
	end
	local fight = Label(L.COLUMN_FIGHT, "RIGHT", -(ROW_RIGHT + 8))
	fight:SetPoint("BOTTOMRIGHT", rows, "TOPRIGHT", 0, -2)
	fight:SetWidth(70 + ROW_RIGHT)
	local time = Label(L.COLUMN_TIME, "LEFT", ROW_LEFT + 22)
	time:SetPoint("BOTTOMLEFT", rows, "TOPLEFT", 0, -2)
	time:SetWidth(ROW_LEFT + 64)
	local event = Label(L.COLUMN_EVENT, "LEFT", OVERLAP + 22)
	event:SetPoint("BOTTOMLEFT", time, "BOTTOMRIGHT", -OVERLAP, 0)
	event:SetPoint("BOTTOMRIGHT", fight, "BOTTOMLEFT", OVERLAP, 0)
	content.TimelineHeadings = { time, event, fight }

	-- Blizzard's panel tabs under the run, as the character frame has them: which of the two
	-- the inset shows.
	for index, text in ipairs({ L.TAB_CREATURES, L.TAB_TIMELINE }) do
		local tab = CreateFrame("Button", nil, frame, "PanelTabButtonTemplate")
		tab:SetID(index)
		tab:SetText(text)
		tab:SetScript("OnClick", function()
			PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
			detailView = VIEWS[index]
			Refresh()
		end)
		if index == 1 then
			tab:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", INSET_LEFT + LIST_WIDTH + INSET_GAP + 8, 2)
		end
	end
	PanelTemplates_SetNumTabs(frame, #VIEWS)
	PanelTemplates_SetTab(frame, detailView == "timeline" and 2 or 1)

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

-- class is the run's character's: the class of a timeline name that isn't a party member's.
local function ShowRun(run, class)
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
	-- With rested experience among the kills: how much of the total it was, and the hourly
	-- rate the run would have had without it.
	local rested = run.rested or 0
	local unrestedPerHour = rested > 0 and ns.Format.PerHour(run.xp - rested, seconds)
	local subs = {
		rested > 0 and L.STAT_RESTED:format(Number(rested)) or "",
		"",
		"",
		"",
		unrestedPerHour and L.STAT_UNRESTED:format(Number(unrestedPerHour)) or "",
	}
	for index, value in ipairs(values) do
		content.Stats[index].Value:SetText(value)
		content.Stats[index].Sub:SetText(subs[index])
	end
	for index, view in ipairs(VIEWS) do
		content.Views[view]:SetShown(view == detailView)
		if view == detailView then
			PanelTemplates_SetTab(frame, index)
		end
	end
	for _, heading in ipairs(content.Headings) do
		heading:SetShown(detailView == "creatures")
	end
	for _, heading in ipairs(content.TimelineHeadings) do
		heading:SetShown(detailView == "timeline")
	end
	if detailView == "timeline" then
		local events = ns.Timeline.Rows(run)
		for _, event in ipairs(events) do
			if event.name and (event.kind == "death" or event.kind == "loot") then
				local member = run.party and run.party[event.name]
				event.class = member and member.class or class
			end
		end
		frame.Timeline:SetDataProvider(CreateDataProvider(events), ScrollBoxConstants.RetainScrollPosition)
		return
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
	-- The tabs belong to the run: gone with it.
	for _, tab in ipairs(frame.Tabs) do
		tab:SetShown(selected ~= nil)
	end
	frame.Detail.Empty:SetShown(selected == nil)
	frame.Detail.Empty.Text:SetText(viewedKey and L.EMPTY_CHARACTER or L.EMPTY)
	if selected then
		ShowRun(selected.run, selected.class)
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
	ns.Tracker.SaveCharacter()
	-- Rebuilt on opening, not on every refresh (a kill would close the open menu): the
	-- characters may have changed, and the dropdown's text must follow the reset above.
	frame.Picker:GenerateMenu()
	Refresh()
	ScrollToSelected()
	if ns.dev.enabled then
		ns.log("UI", "show", "runs", #ns.DB.Runs(), "selected", selectedID)
	end
end
