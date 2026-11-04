local _, ns = ...

-- Colours a hovered player's tooltip: the name line in the player's class colour, the level line in
-- the reaction colour Blizzard would have given the name (GameTooltip_UnitColor).
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

-- The player unit token this unit tooltip shows, or nil when it isn't a player or can't be read.
local function GetPlayerUnit(data)
	local guid = data and data.guid
	if guid == nil or issecretvalue(guid) then
		return nil
	end
	local unit = UnitTokenFromGUID(guid)
	if unit == nil or issecretvalue(unit) then
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
	if classFilename == nil or issecretvalue(classFilename) then
		ns.dev:LogOnce("secret-class", "COLOR", "class unreadable, name left to Blizzard")
		return
	end
	local color = C_ClassColor.GetClassColor(classFilename)
	if color then
		tooltip:GetLeftLine(1):SetTextColor(color:GetRGB())
	end
end

-- GameTooltip_UnitColor branches on UnitIsPVP, which is secret when the unit's identity is
-- restricted; called from addon code that branch would error, so check it first.
local function CanReadReaction(unit)
	return not issecretvalue(UnitIsPVP(unit))
end

local function ColorLevelLine(tooltip, unit)
	local level = UnitLevel(unit)
	if level == nil or issecretvalue(level) or not CanReadReaction(unit) then
		ns.dev:LogOnce("secret-level", "LEVEL", "level or reaction unreadable, level line left to Blizzard")
		return
	end

	local texts = {}
	for i = 2, tooltip:NumLines() do
		local text = tooltip:GetLeftLine(i):GetText()
		if issecretvalue(text) then
			ns.dev:LogOnce("secret-text", "LEVEL", "secret line text, level line left to Blizzard")
			return
		end
		texts[i] = text or "" -- an empty line has no text; keep texts free of holes for table.concat
	end

	local index = ns.LevelLine.Find(texts, ns.LevelLine.LevelText(UNIT_LEVEL_TEMPLATE, level), 2)
	if index then
		tooltip:GetLeftLine(index):SetTextColor(GameTooltip_UnitColor(unit))
	elseif ns.dev.enabled then
		ns.dev:LogOnce("level-miss", "LEVEL", "no level line in", table.concat(texts, " | ", 2))
	end
	if ns.dev.enabled then
		ns.dev:LogChanged("level-index", index, "LEVEL", "level line at", index)
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
	ColorLevelLine(tooltip, unit)
end)
