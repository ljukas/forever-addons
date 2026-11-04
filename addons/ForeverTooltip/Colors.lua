local ADDON_NAME, ns = ...

-- Colours a hovered player's tooltip: the name line in the player's class colour, the level line
-- red for enemies, yellow for players you can attack who aren't hostile, green for allies, using
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

-- The player unit token this unit tooltip shows, or nil when it isn't a player or can't be read.
local function GetPlayerUnit(data)
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
	local isPlayer = UnitIsPlayer(unit)
	if issecretvalue(isPlayer) or not isPlayer then
		return nil
	end
	return unit
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

-- Fallback: the first line after the name that starts with the client's level text.
local function FindLevelLineByText(tooltip, unit)
	local level = UnitLevel(unit)
	if issecretvalue(level) or level == nil then
		return nil
	end
	local numLines = tooltip:NumLines()
	local texts = {}
	for i = 2, numLines do
		local text = tooltip:GetLeftLine(i):GetText()
		if issecretvalue(text) then
			ns.dev:LogOnce("secret-text", "LEVEL", "secret line text, level line left to Blizzard")
			return nil
		end
		texts[i] = text or "" -- an empty line has no text
	end
	local index = ns.LevelLine.Find(texts, ns.LevelLine.LevelText(UNIT_LEVEL_TEMPLATE, level), 2, numLines)
	if not index and ns.dev.enabled then
		ns.dev:LogOnce("level-miss", "LEVEL", "no level line in", table.concat(texts, " | ", 2, numLines))
	end
	return index
end

local function ColorLevelLine(tooltip, unit, data)
	local color = GetReactionColor(unit)
	if not color then
		ns.dev:LogOnce("secret-reaction", "LEVEL", "reaction unreadable, level line left to Blizzard")
		return
	end

	local index = FindLevelLineByType(data)
	local how = "type"
	if not index then
		how = "text"
		index = FindLevelLineByText(tooltip, unit)
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
		tooltip:GetLeftLine(index):SetTextColor(color:GetRGB())
	end
	if ns.dev.enabled then
		ns.dev:LogChanged("level-index", how .. " " .. tostring(index), "LEVEL", "level line by", how, "at", index)
	end
end

TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip, data)
	if tooltip ~= GameTooltip then
		return
	end
	local unit = GetPlayerUnit(data)
	if not unit then
		return
	end
	ColorName(tooltip, unit)
	ColorLevelLine(tooltip, unit, data)
end)
