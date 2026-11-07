local ADDON_NAME, ns = ...

-- Colours unit tooltips. For players and for creatures and NPCs you can attack, the level line by how
-- its level compares to yours (gray, green, yellow, orange, red: Blizzard's GetCreatureDifficultyColor, the
-- colours of quest and creature difficulty), with a skull icon in place of "??". For players also
-- the name line in the player's class colour, and the Alliance/Horde
-- line red for enemies, yellow for players you can attack who aren't hostile, green for allies, using
-- the same FACTION_BAR_COLORS entries Blizzard's GameTooltip_UnitColor uses for players. (Blizzard's
-- own function gives ordinary allies white, so it isn't reused.)
--
-- Why a tooltip post-call that recolours the finished font strings, not a line pre-call that sets
-- lineData.leftColor: Blizzard reads lineData after the pre-calls, so a field written by addon code
-- would put taint into its tooltip build (which can blank tooltips with secret lines, see the comment
-- in GameTooltipDataMixin:SetWorldCursor). Addon post-calls run quarantined through
-- TooltipDataProcessor's attribute delegate, and they run again on every rebuild
-- (TOOLTIP_DATA_UPDATE), so the colours survive a tooltip refreshing itself.
--
-- Secret values: when anything this needs is secret (unit identity restricted, e.g. in instances),
-- the line is left exactly as Blizzard drew it.

local ENEMY, ATTACKABLE, ALLY = 2, 4, 6 -- FACTION_BAR_COLORS indices, as in GameTooltip_UnitColor

-- Whether this code may index t. A secret table (or one whose contents taint hides) raises an error
-- when indexed by addon code; canaccesstable is the check Blizzard's own Dump.lua uses.
local function IsReadableTable(t)
	return type(t) == "table" and canaccesstable(t)
end

-- The unit token this unit tooltip shows (a player, creature or NPC), or nil when it can't be read.
local function GetUnit(data)
	if not IsReadableTable(data) then
		return nil
	end
	local guid = data.guid
	if issecretvalue(guid) or guid == nil then
		return nil
	end
	local unit = UnitTokenFromGUID(guid)
	if issecretvalue(unit) or unit == nil then
		return nil
	end
	return unit
end

-- Whether unit is a player; false when that can't be read.
local function IsPlayer(unit)
	local isPlayer = UnitIsPlayer(unit)
	return not issecretvalue(isPlayer) and isPlayer == true
end

local function ColorName(tooltip, unit)
	local _, classFilename = UnitClass(unit)
	if issecretvalue(classFilename) or classFilename == nil then
		ns.dev:LogOnce("secret-class", "COLOR", "class unreadable, name left to Blizzard")
		return
	end
	local color = C_ClassColor.GetClassColor(classFilename)
	if color then
		tooltip:GetLeftLine(1):SetTextColor(color:GetRGB())
	end
end

-- The FACTION_BAR_COLORS entry for this player, or nil when it can't be read.
local function GetReactionColor(unit)
	local canAttack = UnitCanAttack("player", unit)
	local canBeAttacked = UnitCanAttack(unit, "player")
	if issecretvalue(canAttack) or issecretvalue(canBeAttacked) then
		return nil
	end
	if canBeAttacked then
		return FACTION_BAR_COLORS[ENEMY]
	elseif canAttack then
		return FACTION_BAR_COLORS[ATTACKABLE]
	end
	return FACTION_BAR_COLORS[ALLY]
end

-- The tooltip line index of the level line, from its line type in the tooltip data. Blizzard sets
-- lineData.lineIndex when it adds each line (TooltipDataHandlerMixin:ProcessLineData).
local function FindLevelLineByType(data)
	if not IsReadableTable(data.lines) then
		return nil
	end
	for _, lineData in ipairs(data.lines) do
		if IsReadableTable(lineData) then
			local lineType = lineData.type
			if not issecretvalue(lineType) and lineType == Enum.TooltipDataLineType.UnitLevel then
				local index = lineData.lineIndex
				if not issecretvalue(index) then
					return index
				end
			end
		end
	end
	return nil
end

-- The texts of the left lines after the name, indexed by line, and the line count; nil when any is
-- secret. tag names the line the caller is looking for, for the log.
local function ReadLineTexts(tooltip, tag)
	local numLines = tooltip:NumLines()
	local texts = {}
	for i = 2, numLines do
		local text = tooltip:GetLeftLine(i):GetText()
		if issecretvalue(text) then
			ns.dev:LogOnce("secret-text-" .. tag, tag, "secret line text, line left to Blizzard")
			return nil
		end
		texts[i] = text or "" -- an empty line has no text
	end
	return texts, numLines
end

-- Fallback: the first line after the name that starts with the client's level text.
local function FindLevelLineByText(tooltip, level)
	local texts, numLines = ReadLineTexts(tooltip, "LEVEL")
	if not texts then
		return nil
	end
	local index = ns.LevelLine.Find(texts, ns.LevelLine.LevelText(UNIT_LEVEL_TEMPLATE, level), 2, numLines)
	if not index and ns.dev.enabled then
		ns.dev:LogOnce("level-miss", "LEVEL", "no level line in", table.concat(texts, " | ", 2, numLines))
	end
	return index
end

-- The difficulty colour of a unit of this level for you: gray, green, yellow, orange or red.
-- Blizzard's GetCreatureDifficultyColor reads a skull level (-1) as far below you, so that's red here.
local function GetLevelColor(level)
	if level < 0 then
		return QuestDifficultyColors.impossible
	end
	return GetCreatureDifficultyColor(level)
end

-- Blizzard's skull icon, sized to the line's font, as Forever's own PaperDollFrameStats shows it.
local SKULL = "|TInterface\\TargetingFrame\\UI-TargetingFrame-Skull:0|t"

-- Shows the skull icon in place of the "??" of a skull-level line.
local function ShowSkull(line, index)
	local text = line:GetText()
	if issecretvalue(text) or text == nil then
		ns.dev:LogOnce("secret-skull", "LEVEL", "skull line text unreadable, ?? left to Blizzard")
		return
	end
	local withSkull = ns.LevelLine.WithSkull(text, UNIT_LEVEL_TEMPLATE, SKULL)
	if withSkull then
		line:SetText(withSkull)
	end
	if ns.dev.enabled then
		ns.dev:LogChanged(
			"skull",
			tostring(withSkull ~= nil) .. text,
			"LEVEL",
			"skull at line",
			index,
			withSkull ~= nil
		)
	end
end

-- Whether a unit's level line takes the difficulty colour. Players always do. Other units only when
-- you can attack them, as Blizzard's TargetFrameMixin:CheckLevel colours the target's level: a
-- friendly vendor's level says nothing about danger. False (Blizzard's colour stays) when unreadable.
local function ShouldColorLevel(unit, isPlayer)
	if isPlayer then
		return true
	end
	local canAttack = UnitCanAttack("player", unit)
	return not issecretvalue(canAttack) and canAttack == true
end

-- Colours the level line by difficulty when colorIt, and shows a skull for a ?? level either way.
local function ColorLevelLine(tooltip, unit, data, colorIt)
	local level = UnitLevel(unit)
	if issecretvalue(level) or level == nil then
		ns.dev:LogOnce("secret-level", "LEVEL", "level unreadable, level line left to Blizzard")
		return
	end
	local color = GetLevelColor(level)

	local index = FindLevelLineByType(data)
	local how = "type"
	if not index then
		how = "text"
		index = FindLevelLineByText(tooltip, level)
		if ns.dev.enabled then
			local types = {}
			for i, lineData in ipairs(IsReadableTable(data.lines) and data.lines or {}) do
				local readable = IsReadableTable(lineData) and not issecretvalue(lineData.type)
				types[i] = readable and tostring(lineData.type) or "?"
			end
			ns.dev:LogOnce("level-types", "LEVEL", "no UnitLevel line type; line types", table.concat(types, ","))
		end
	end
	if index then
		local line = tooltip:GetLeftLine(index)
		if ns.dev.enabled then
			-- Blizzard's own text, once per kind of line: shows whether it carries a colour code, which
			-- SetTextColor can't override.
			local raw = line:GetText()
			if raw and not issecretvalue(raw) then
				local key = "level-raw-" .. tostring(colorIt) .. tostring(level < 0)
				ns.dev:LogOnce(key, "LEVEL", "level line text", (raw:gsub("|", "||")))
			end
		end
		if level < 0 then
			ShowSkull(line, index) -- before the colour, so SetText can't reset it
		end
		if colorIt then
			line:SetTextColor(color.r, color.g, color.b)
		end
	end
	if ns.dev.enabled then
		ns.dev:LogChanged("level-index", how .. " " .. tostring(index), "LEVEL", "level line by", how, "at", index)
	end
end

-- The line that is exactly the player's faction name ("Alliance", "Horde"), coloured by reaction.
local function ColorFactionLine(tooltip, unit)
	local color = GetReactionColor(unit)
	if not color then
		ns.dev:LogOnce("secret-reaction", "FACTION", "reaction unreadable, faction line left to Blizzard")
		return
	end
	local _, factionName = UnitFactionGroup(unit)
	if issecretvalue(factionName) or factionName == nil or factionName == "" then
		ns.dev:LogOnce("no-faction", "FACTION", "faction name unreadable or empty, faction line left to Blizzard")
		return
	end
	local texts, numLines = ReadLineTexts(tooltip, "FACTION")
	if not texts then
		return
	end
	local index = ns.FactionLine.Find(texts, factionName, 2, numLines)
	if index then
		tooltip:GetLeftLine(index):SetTextColor(color:GetRGB())
	end
	if ns.dev.enabled then
		if not index then
			ns.dev:LogOnce(
				"faction-miss",
				"FACTION",
				"no",
				factionName,
				"line in",
				table.concat(texts, " | ", 2, numLines)
			)
		end
		ns.dev:LogChanged("faction-index", tostring(index), "FACTION", "faction line at", index)
	end
end

TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip, data)
	if tooltip ~= GameTooltip then
		return
	end
	local unit = GetUnit(data)
	if not unit then
		return
	end
	local isPlayer = IsPlayer(unit)
	ColorLevelLine(tooltip, unit, data, ShouldColorLevel(unit, isPlayer))
	if isPlayer then
		ColorName(tooltip, unit)
		ColorFactionLine(tooltip, unit)
	end
end)
